#!/usr/bin/env python3
"""Generate the production-v1, consumer-native parameter image.

The source ``parameters.bin`` remains immutable and row-major.  This generator
creates a version-3 image for the PL memory service:

* INT8 matrices are transposed into ``{source_index, row_tile, lane}`` order;
* duplicated shared-GSU gate weights are byte-verified and stored once;
* INT64 requant multipliers/shifts are range checked and lowered to 32/6 bits;
* one GSU/projection parameter tile is pre-packed in native response bit order;
* sigmoid LUTs are independent sections; and
* every stage/section is aligned and described by deterministic JSON/RTL data.

The binary, layout, golden report, RTL header/table and checksum manifest are a
single versioned artifact set.  This script never modifies the source manifest
or blob in ``upstream/``.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import struct
import tempfile
from typing import Iterable


ROOT = Path(__file__).resolve().parents[2]

FORMAT_VERSION = 3
GENERATOR_VERSION = "zephyr-memory-v3.2"
IMAGE_MAGIC = b"ZEPHYR3\0"
IMAGE_HEADER_BYTES = 64
LANES = 16
BUS_BYTES = 8
STAGE_ALIGNMENT = 64
SECTION_ALIGNMENT = 64
CACHE_BYTES = 256 * 1024

STAGE_KIND_GSU = 0
STAGE_KIND_PROJECTION = 1

GSU_PARAM_RESPONSE_BITS = 5792
GSU_PARAM_RESPONSE_BYTES = GSU_PARAM_RESPONSE_BITS // 8
GSU_PARAM_RECORD_BYTES = 728
PROJECTION_PARAM_RESPONSE_BITS = 1120
PROJECTION_PARAM_RESPONSE_BYTES = PROJECTION_PARAM_RESPONSE_BITS // 8
PROJECTION_PARAM_RECORD_BYTES = 144

OPERATOR_EXECUTION_ORDER = [
    "fb_model.sequence_model.layers.0.cell",
    "fb_model.sequence_model.layers.1.cell",
    "fb_model.proj",
    "sb_model.sb_models.0.sequence_model.layers.0.cell",
    "sb_model.sb_models.0.sequence_model.layers.1.cell",
    "sb_model.sb_models.0.proj",
    "sb_model.sb_models.1.sequence_model.layers.0.cell",
    "sb_model.sb_models.1.sequence_model.layers.1.cell",
    "sb_model.sb_models.1.proj",
    "sb_model.sb_models.2.sequence_model.layers.0.cell",
    "sb_model.sb_models.2.sequence_model.layers.1.cell",
    "sb_model.sb_models.2.proj",
]

# Frozen board-smoke requests.  Stage 2 is the small projection-first smoke
# load.  Stage 1 is the maximum-size GSU stage and deliberately covers both
# matrices plus first/last source and row-tile boundaries.
WEIGHT_READBACK_REQUESTS = [
    {"stage": 2, "matrix": 0, "source": 0, "row_tile": 0, "tag": 0x20},
    {"stage": 2, "matrix": 0, "source": 0, "row_tile": 3, "tag": 0x21},
    {"stage": 2, "matrix": 0, "source": 1, "row_tile": 0, "tag": 0x22},
    {"stage": 2, "matrix": 0, "source": 159, "row_tile": 2, "tag": 0x23},
    {"stage": 2, "matrix": 0, "source": 319, "row_tile": 3, "tag": 0x24},
    {"stage": 1, "matrix": 0, "source": 0, "row_tile": 0, "tag": 0x10},
    {"stage": 1, "matrix": 0, "source": 0, "row_tile": 19, "tag": 0x11},
    {"stage": 1, "matrix": 0, "source": 159, "row_tile": 10, "tag": 0x12},
    {"stage": 1, "matrix": 0, "source": 319, "row_tile": 19, "tag": 0x13},
    {"stage": 1, "matrix": 1, "source": 0, "row_tile": 0, "tag": 0x14},
    {"stage": 1, "matrix": 1, "source": 0, "row_tile": 19, "tag": 0x15},
    {"stage": 1, "matrix": 1, "source": 159, "row_tile": 10, "tag": 0x16},
    {"stage": 1, "matrix": 1, "source": 319, "row_tile": 19, "tag": 0x17},
]

GSU_PARAM_FIELDS = [
    ("forget_input_multiplier", "input_requantizer.multiplier", "forget", 32, True),
    ("forget_input_shift", "input_requantizer.right_shift", "forget", 6, False),
    (
        "forget_recurrent_multiplier",
        "recurrent_requantizer.multiplier",
        "forget",
        32,
        True,
    ),
    (
        "forget_recurrent_shift",
        "recurrent_requantizer.right_shift",
        "forget",
        6,
        False,
    ),
    ("forget_bias_q", "bias_q", "forget", 32, True),
    ("cell_input_multiplier", "input_requantizer.multiplier", "cell", 32, True),
    ("cell_input_shift", "input_requantizer.right_shift", "cell", 6, False),
    (
        "cell_recurrent_multiplier",
        "recurrent_requantizer.multiplier",
        "cell",
        32,
        True,
    ),
    (
        "cell_recurrent_shift",
        "recurrent_requantizer.right_shift",
        "cell",
        6,
        False,
    ),
    ("cell_bias_q", "bias_q", "cell", 32, True),
    ("previous_multiplier", "cx_requantizer.multiplier", "channel", 32, True),
    ("previous_shift", "cx_requantizer.right_shift", "channel", 6, False),
    (
        "cellgate_multiplier",
        "cellgate_requantizer.multiplier",
        "channel",
        32,
        True,
    ),
    (
        "cellgate_shift",
        "cellgate_requantizer.right_shift",
        "channel",
        6,
        False,
    ),
    ("bn_multiplier", "bn_requantizer.multiplier", "channel", 32, True),
    ("bn_shift", "bn_requantizer.right_shift", "channel", 6, False),
    ("bn_bias_q", "bn_bias_q", "channel", 32, True),
]

PROJECTION_PARAM_FIELDS = [
    ("output_multiplier", "requantizer.multiplier", "channel", 32, True),
    ("output_shift", "requantizer.right_shift", "channel", 6, False),
    ("output_bias_q", "bias_q", "channel", 32, True),
]

DTYPE_FORMAT = {
    "int8": "b",
    "uint8": "B",
    "int32": "i",
    "int64": "q",
    "float64": "d",
}


def align_up(value: int, alignment: int) -> int:
    if alignment <= 0 or alignment & (alignment - 1):
        raise ValueError(f"alignment must be a positive power of two: {alignment}")
    return (value + alignment - 1) // alignment * alignment


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def macro_name(*parts: str) -> str:
    text = "_".join(parts).upper()
    return re.sub(r"[^A-Z0-9]+", "_", text).strip("_")


def relative_source_path(path: Path) -> str:
    resolved = path.resolve()
    try:
        return resolved.relative_to(ROOT).as_posix()
    except ValueError:
        return resolved.as_posix()


def atomic_write(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_name, path)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def json_bytes(value: dict) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=False) + "\n").encode("utf-8")


def tensor_bytes(blob: bytes, metadata: dict, name: str) -> bytes:
    if metadata.get("endianness") != "little":
        raise ValueError(f"tensor {name} is not little-endian")
    start = int(metadata["offset"])
    size = int(metadata["nbytes"])
    payload = blob[start : start + size]
    if len(payload) != size:
        raise ValueError(f"tensor {name} is truncated")
    if sha256(payload) != metadata["sha256"]:
        raise ValueError(f"tensor {name} SHA-256 mismatch")
    return payload


def tensor_values(blob: bytes, metadata: dict, name: str) -> list[int | float]:
    payload = tensor_bytes(blob, metadata, name)
    dtype = metadata["dtype"]
    if dtype not in DTYPE_FORMAT:
        raise ValueError(f"unsupported dtype for {name}: {dtype}")
    item_format = DTYPE_FORMAT[dtype]
    item_bytes = struct.calcsize(item_format)
    if len(payload) % item_bytes:
        raise ValueError(f"tensor {name} byte count is not dtype aligned")
    values = list(struct.unpack("<" + item_format * (len(payload) // item_bytes), payload))
    if len(values) != math.prod(metadata["shape"] or [1]):
        raise ValueError(f"tensor {name} shape does not match its byte count")
    return values


def lowered_value(value: int, width: int, signed: bool, field_name: str) -> int:
    integer = int(value)
    if signed:
        minimum = -(1 << (width - 1))
        maximum = (1 << (width - 1)) - 1
    else:
        minimum = 0
        maximum = (1 << width) - 1
    if not minimum <= integer <= maximum:
        kind = "signed" if signed else "unsigned"
        raise ValueError(
            f"{field_name} value {integer} is outside {kind} {width}-bit range"
        )
    return integer & ((1 << width) - 1)


def append_aligned(target: bytearray, payload: bytes, alignment: int) -> tuple[int, int]:
    offset = align_up(len(target), alignment)
    target.extend(bytes(offset - len(target)))
    target.extend(payload)
    return offset, len(payload)


def pack_source_major_matrix(
    raw: bytes,
    *,
    source_rows: int,
    output_rows: int,
    source_count: int,
    shared_gate_halves: bool,
    tensor_name: str,
) -> tuple[bytes, dict]:
    if len(raw) != source_rows * source_count:
        raise ValueError(f"matrix {tensor_name} shape/byte count mismatch")
    if shared_gate_halves:
        if source_rows != 2 * output_rows:
            raise ValueError(f"shared matrix {tensor_name} must contain two gate halves")
        half_bytes = output_rows * source_count
        if raw[:half_bytes] != raw[half_bytes:]:
            raise ValueError(f"shared matrix {tensor_name} gate halves differ")
    elif source_rows != output_rows:
        raise ValueError(f"matrix {tensor_name} has unexpected row count")

    row_tiles = (output_rows + LANES - 1) // LANES
    packed = bytearray()
    padding_lanes = 0
    for source_index in range(source_count):
        for row_tile in range(row_tiles):
            first_row = row_tile * LANES
            for lane in range(LANES):
                row = first_row + lane
                if row < output_rows:
                    packed.append(raw[row * source_count + source_index])
                else:
                    packed.append(0)
                    padding_lanes += 1

    metadata = {
        "physical_order": ["source_index", "row_tile", "lane"],
        "source_count": source_count,
        "output_rows": output_rows,
        "row_tiles": row_tiles,
        "lanes": LANES,
        "word_bytes": LANES,
        "source_stride_bytes": row_tiles * LANES,
        "row_tile_stride_bytes": LANES,
        "shared_gate_halves_verified": shared_gate_halves,
        "verified_source_values": output_rows * source_count,
        "verified_duplicate_values": output_rows * source_count if shared_gate_halves else 0,
        "padding_lanes": padding_lanes,
        "packed_sha256": sha256(bytes(packed)),
    }
    return bytes(packed), metadata


def field_source_index(selector: str, hidden_size: int, channel: int) -> int:
    if selector in {"forget", "channel"}:
        return channel
    if selector == "cell":
        return hidden_size + channel
    raise ValueError(f"unsupported field selector: {selector}")


def pack_parameter_records(
    *,
    blob: bytes,
    tensors: dict,
    hidden_size: int,
    fields: list[tuple[str, str, str, int, bool]],
    response_bits: int,
    record_bytes: int,
) -> tuple[bytes, dict, dict]:
    values_by_tensor: dict[str, list[int | float]] = {}
    for _, tensor_name, _, _, _ in fields:
        if tensor_name not in values_by_tensor:
            values_by_tensor[tensor_name] = tensor_values(
                blob, tensors[tensor_name], tensor_name
            )

    field_layout = []
    bit_cursor = 0
    for field_name, tensor_name, selector, width, signed in fields:
        field_layout.append(
            {
                "name": field_name,
                "source_tensor": tensor_name,
                "source_selector": selector,
                "lsb": bit_cursor,
                "lane_width": width,
                "lanes": LANES,
                "bits": width * LANES,
                "signed": signed,
            }
        )
        bit_cursor += width * LANES
    if bit_cursor != response_bits:
        raise ValueError(
            f"parameter ABI fields use {bit_cursor} bits, expected {response_bits}"
        )
    response_bytes = (response_bits + 7) // 8
    if record_bytes < response_bytes or record_bytes % BUS_BYTES:
        raise ValueError("parameter record does not contain aligned response payload")

    row_tiles = (hidden_size + LANES - 1) // LANES
    records = bytearray()
    field_ranges: dict[str, dict] = {}
    verified_values = 0
    for field_name, tensor_name, selector, width, signed in fields:
        source_values = values_by_tensor[tensor_name]
        selected = [
            int(source_values[field_source_index(selector, hidden_size, channel)])
            for channel in range(hidden_size)
        ]
        for value in selected:
            lowered_value(value, width, signed, field_name)
        field_ranges[field_name] = {
            "minimum": min(selected),
            "maximum": max(selected),
            "verified_values": len(selected),
        }
        verified_values += len(selected)

    for row_tile in range(row_tiles):
        word = 0
        for field in field_layout:
            source_values = values_by_tensor[field["source_tensor"]]
            for lane in range(LANES):
                channel = row_tile * LANES + lane
                value = 0
                if channel < hidden_size:
                    source_index = field_source_index(
                        field["source_selector"], hidden_size, channel
                    )
                    value = int(source_values[source_index])
                encoded = lowered_value(
                    value, field["lane_width"], field["signed"], field["name"]
                )
                lane_lsb = field["lsb"] + lane * field["lane_width"]
                word |= encoded << lane_lsb
        response = word.to_bytes(response_bytes, "little")
        records.extend(response)
        records.extend(bytes(record_bytes - response_bytes))

    metadata = {
        "row_tiles": row_tiles,
        "lanes": LANES,
        "response_bits": response_bits,
        "response_bytes": response_bytes,
        "record_bytes": record_bytes,
        "record_words": record_bytes // BUS_BYTES,
        "record_padding_bytes": record_bytes - response_bytes,
        "fields": field_layout,
        "verified_values": verified_values,
        "packed_sha256": sha256(bytes(records)),
    }
    return bytes(records), metadata, field_ranges


def validate_manifest(manifest: dict, blob: bytes) -> None:
    if set(manifest["operators"]) != set(OPERATOR_EXECUTION_ORDER):
        missing = sorted(set(OPERATOR_EXECUTION_ORDER) - set(manifest["operators"]))
        extra = sorted(set(manifest["operators"]) - set(OPERATOR_EXECUTION_ORDER))
        raise ValueError(f"operator set changed; missing={missing}, extra={extra}")
    if not manifest.get("model", {}).get("args", {}).get("shared_weights"):
        raise ValueError("v3 ABI currently requires shared_weights=true")
    if manifest.get("quantization", {}).get("gate_denominator") != 255:
        raise ValueError("v3 ABI requires gate_denominator=255")
    storage = manifest["storage"]
    if len(blob) != int(storage["nbytes"]):
        raise ValueError("source parameter blob byte count mismatch")
    if sha256(blob) != storage["sha256"]:
        raise ValueError("source parameter blob SHA-256 mismatch")


def image_header(manifest_sha: str, stage_count: int) -> bytes:
    prefix = struct.pack(
        "<8sIIIIII",
        IMAGE_MAGIC,
        FORMAT_VERSION,
        stage_count,
        LANES,
        BUS_BYTES,
        STAGE_ALIGNMENT,
        0,
    )
    header = prefix + bytes.fromhex(manifest_sha)
    if len(header) != IMAGE_HEADER_BYTES:
        raise AssertionError(f"image header is {len(header)} bytes")
    return header


def build_stage(
    *,
    stage_id: int,
    operator_name: str,
    operator: dict,
    blob: bytes,
) -> tuple[bytes, dict, dict]:
    stage = bytearray()
    matrices = []
    tensors = operator["tensors"]
    operator_class = operator["class"]

    if operator_class == "IntegerGSUCellReference":
        kind = "gsu"
        kind_id = STAGE_KIND_GSU
        hidden_size = int(tensors["bn_bias_q"]["shape"][0])
        matrix_specs = [
            (0, "weight_ih_q"),
            (1, "weight_hh_q"),
        ]
        for matrix_id, tensor_name in matrix_specs:
            tensor = tensors[tensor_name]
            source_rows, source_count = map(int, tensor["shape"])
            raw = tensor_bytes(blob, tensor, tensor_name)
            packed, matrix_meta = pack_source_major_matrix(
                raw,
                source_rows=source_rows,
                output_rows=hidden_size,
                source_count=source_count,
                shared_gate_halves=True,
                tensor_name=tensor_name,
            )
            local_offset, payload_bytes = append_aligned(
                stage, packed, SECTION_ALIGNMENT
            )
            matrix_meta.update(
                {
                    "id": matrix_id,
                    "name": tensor_name,
                    "source_shape": tensor["shape"],
                    "source_sha256": tensor["sha256"],
                    "local_byte_offset": local_offset,
                    "local_word_offset": local_offset // BUS_BYTES,
                    "payload_bytes": payload_bytes,
                }
            )
            matrices.append(matrix_meta)

        parameter_payload, parameter_meta, field_ranges = pack_parameter_records(
            blob=blob,
            tensors=tensors,
            hidden_size=hidden_size,
            fields=GSU_PARAM_FIELDS,
            response_bits=GSU_PARAM_RESPONSE_BITS,
            record_bytes=GSU_PARAM_RECORD_BYTES,
        )
        param_offset, param_bytes = append_aligned(
            stage, parameter_payload, SECTION_ALIGNMENT
        )
        parameter_meta.update(
            {
                "local_byte_offset": param_offset,
                "local_word_offset": param_offset // BUS_BYTES,
                "payload_bytes": param_bytes,
            }
        )

        lut_payload = tensor_bytes(blob, tensors["sigmoid_lut"], "sigmoid_lut")
        if len(lut_payload) != 255:
            raise ValueError(f"{operator_name} sigmoid LUT must contain 255 bytes")
        lut_offset, lut_bytes = append_aligned(stage, lut_payload, SECTION_ALIGNMENT)
        lut = {
            "present": True,
            "local_byte_offset": lut_offset,
            "local_word_offset": lut_offset // BUS_BYTES,
            "payload_bytes": lut_bytes,
            "transfer_bytes": align_up(lut_bytes, BUS_BYTES),
            "sha256": sha256(lut_payload),
            "verified_values": len(lut_payload),
        }
        stage.extend(bytes(align_up(len(stage), BUS_BYTES) - len(stage)))
        runtime_tensors = {
            "weight_ih_q",
            "weight_hh_q",
            "input_requantizer.multiplier",
            "input_requantizer.right_shift",
            "recurrent_requantizer.multiplier",
            "recurrent_requantizer.right_shift",
            "bias_q",
            "cx_requantizer.multiplier",
            "cx_requantizer.right_shift",
            "cellgate_requantizer.multiplier",
            "cellgate_requantizer.right_shift",
            "bn_requantizer.multiplier",
            "bn_requantizer.right_shift",
            "bn_bias_q",
            "sigmoid_lut",
        }
    elif operator_class == "IntegerLinearReference":
        kind = "projection"
        kind_id = STAGE_KIND_PROJECTION
        tensor = tensors["weight_q"]
        hidden_size, source_count = map(int, tensor["shape"])
        raw = tensor_bytes(blob, tensor, "weight_q")
        packed, matrix_meta = pack_source_major_matrix(
            raw,
            source_rows=hidden_size,
            output_rows=hidden_size,
            source_count=source_count,
            shared_gate_halves=False,
            tensor_name="weight_q",
        )
        matrix_offset, matrix_bytes = append_aligned(stage, packed, SECTION_ALIGNMENT)
        matrix_meta.update(
            {
                "id": 0,
                "name": "weight_q",
                "source_shape": tensor["shape"],
                "source_sha256": tensor["sha256"],
                "local_byte_offset": matrix_offset,
                "local_word_offset": matrix_offset // BUS_BYTES,
                "payload_bytes": matrix_bytes,
            }
        )
        matrices.append(matrix_meta)

        parameter_payload, parameter_meta, field_ranges = pack_parameter_records(
            blob=blob,
            tensors=tensors,
            hidden_size=hidden_size,
            fields=PROJECTION_PARAM_FIELDS,
            response_bits=PROJECTION_PARAM_RESPONSE_BITS,
            record_bytes=PROJECTION_PARAM_RECORD_BYTES,
        )
        param_offset, param_bytes = append_aligned(
            stage, parameter_payload, SECTION_ALIGNMENT
        )
        parameter_meta.update(
            {
                "local_byte_offset": param_offset,
                "local_word_offset": param_offset // BUS_BYTES,
                "payload_bytes": param_bytes,
            }
        )
        lut = {
            "present": False,
            "local_byte_offset": 0,
            "local_word_offset": 0,
            "payload_bytes": 0,
            "transfer_bytes": 0,
            "sha256": None,
            "verified_values": 0,
        }
        stage.extend(bytes(align_up(len(stage), BUS_BYTES) - len(stage)))
        runtime_tensors = {
            "weight_q",
            "requantizer.multiplier",
            "requantizer.right_shift",
            "bias_q",
        }
    else:
        raise ValueError(f"unsupported operator class: {operator_class}")

    if len(stage) > CACHE_BYTES:
        raise ValueError(
            f"stage {operator_name} is {len(stage)} bytes and exceeds 256 KiB cache"
        )

    excluded = sorted(set(tensors) - runtime_tensors)
    stage_meta = {
        "id": stage_id,
        "name": operator_name,
        "class": operator_class,
        "kind": kind,
        "kind_id": kind_id,
        "transfer_bytes": len(stage),
        "bram_words": len(stage) // BUS_BYTES,
        "matrix_count": len(matrices),
        "matrices": matrices,
        "parameters": parameter_meta,
        "lut": lut,
        "excluded_metadata_tensors": excluded,
        "stage_sha256": sha256(bytes(stage)),
    }
    golden = {
        "id": stage_id,
        "name": operator_name,
        "kind": kind,
        "stage_sha256": stage_meta["stage_sha256"],
        "matrices": [
            {
                "name": matrix["name"],
                "packed_sha256": matrix["packed_sha256"],
                "verified_source_values": matrix["verified_source_values"],
                "verified_duplicate_values": matrix["verified_duplicate_values"],
                "padding_lanes": matrix["padding_lanes"],
            }
            for matrix in matrices
        ],
        "parameters": {
            "packed_sha256": parameter_meta["packed_sha256"],
            "verified_values": parameter_meta["verified_values"],
            "field_ranges": field_ranges,
        },
        "lut": {
            "sha256": lut["sha256"],
            "verified_values": lut["verified_values"],
        },
    }
    return bytes(stage), stage_meta, golden


def build_weight_readback_vectors(image: bytes, layout: dict) -> list[dict]:
    """Resolve the frozen request coordinates to exact image bytes."""
    stages = {int(stage["id"]): stage for stage in layout["stages"]}
    vectors = []
    for index, request in enumerate(WEIGHT_READBACK_REQUESTS):
        stage = stages[request["stage"]]
        matrices = {int(matrix["id"]): matrix for matrix in stage["matrices"]}
        if request["matrix"] not in matrices:
            raise ValueError(f"readback vector {index} selects an absent matrix")
        matrix = matrices[request["matrix"]]
        if not 0 <= request["source"] < int(matrix["source_count"]):
            raise ValueError(f"readback vector {index} source is out of range")
        if not 0 <= request["row_tile"] < int(matrix["row_tiles"]):
            raise ValueError(f"readback vector {index} row tile is out of range")

        image_offset = (
            int(stage["dram_byte_offset"])
            + int(matrix["local_byte_offset"])
            + request["source"] * int(matrix["source_stride_bytes"])
            + request["row_tile"] * LANES
        )
        payload = image[image_offset : image_offset + LANES]
        if len(payload) != LANES:
            raise ValueError(f"readback vector {index} extends beyond the image")
        vectors.append(
            {
                "index": index,
                "stage": request["stage"],
                "matrix": request["matrix"],
                "source": request["source"],
                "row_tile": request["row_tile"],
                "tag": request["tag"],
                "image_byte_offset": image_offset,
                # Lane 0 is the first byte and maps to response bits [7:0].
                "expected_lane_bytes_hex": payload.hex(),
                "expected_u128_le_hex": (
                    f"0x{int.from_bytes(payload, 'little'):032x}"
                ),
                "expected_words_le": [
                    int.from_bytes(payload[word : word + 4], "little")
                    for word in range(0, LANES, 4)
                ],
            }
        )
    return vectors


def build_image(manifest_path: Path) -> tuple[bytes, dict, dict]:
    manifest_payload = manifest_path.read_bytes()
    manifest = json.loads(manifest_payload)
    blob_path = manifest_path.parent / manifest["storage"]["file"]
    blob = blob_path.read_bytes()
    validate_manifest(manifest, blob)

    manifest_sha = sha256(manifest_payload)
    image = bytearray(image_header(manifest_sha, len(OPERATOR_EXECUTION_ORDER)))
    stages = []
    golden_stages = []
    for stage_id, operator_name in enumerate(OPERATOR_EXECUTION_ORDER):
        stage_payload, stage_meta, golden = build_stage(
            stage_id=stage_id,
            operator_name=operator_name,
            operator=manifest["operators"][operator_name],
            blob=blob,
        )
        stage_start = align_up(len(image), STAGE_ALIGNMENT)
        image.extend(bytes(stage_start - len(image)))
        stage_meta["dram_byte_offset"] = stage_start
        image.extend(stage_payload)
        stages.append(stage_meta)
        golden_stages.append(golden)

    image_payload = bytes(image)
    image_sha = sha256(image_payload)
    layout = {
        "format_version": FORMAT_VERSION,
        "generator_version": GENERATOR_VERSION,
        "image_magic_ascii": IMAGE_MAGIC.rstrip(b"\0").decode("ascii"),
        "image_header_bytes": IMAGE_HEADER_BYTES,
        "image_bytes": len(image_payload),
        "image_sha256": image_sha,
        "source_manifest": relative_source_path(manifest_path),
        "source_manifest_sha256": manifest_sha,
        "source_blob": relative_source_path(blob_path),
        "source_blob_bytes": len(blob),
        "source_blob_sha256": sha256(blob),
        "bus_bytes": BUS_BYTES,
        "stage_alignment": STAGE_ALIGNMENT,
        "section_alignment": SECTION_ALIGNMENT,
        "lanes": LANES,
        "cache_bytes": CACHE_BYTES,
        "maximum_stage_bytes": max(stage["transfer_bytes"] for stage in stages),
        "stage_count": len(stages),
        "weight_physical_order": ["operator", "matrix", "source_index", "row_tile", "lane"],
        "parameter_abi": {
            "gsu_response_bits": GSU_PARAM_RESPONSE_BITS,
            "gsu_record_bytes": GSU_PARAM_RECORD_BYTES,
            "projection_response_bits": PROJECTION_PARAM_RESPONSE_BITS,
            "projection_record_bytes": PROJECTION_PARAM_RECORD_BYTES,
            "lane_zero_is_lowest_bits": True,
            "record_byte_order": "little-endian",
        },
        "canonical_generator_command": (
            "python3 rtl/tools/generate_memory_v3.py "
            "--manifest upstream/parameters/manifest.json"
        ),
        "stages": stages,
    }
    total_matrix_values = sum(
        matrix["verified_source_values"] + matrix["verified_duplicate_values"]
        for stage in golden_stages
        for matrix in stage["matrices"]
    )
    total_parameter_values = sum(
        stage["parameters"]["verified_values"] for stage in golden_stages
    )
    total_lut_values = sum(stage["lut"]["verified_values"] for stage in golden_stages)
    golden_report = {
        "format_version": FORMAT_VERSION,
        "generator_version": GENERATOR_VERSION,
        "source_manifest_sha256": manifest_sha,
        "source_blob_sha256": sha256(blob),
        "image_sha256": image_sha,
        "dense_reference_checks": {
            "all_matrix_values_compared": True,
            "all_shared_gate_duplicate_values_compared": True,
            "all_parameter_values_range_checked_and_repacked": True,
            "all_final_tile_padding_lanes_zero": True,
            "all_record_padding_bytes_zero": True,
            "matrix_values_verified": total_matrix_values,
            "parameter_values_verified": total_parameter_values,
            "lut_values_verified": total_lut_values,
        },
        "stages": golden_stages,
        "weight_readback_vectors": {
            "count": len(WEIGHT_READBACK_REQUESTS),
            "lane_zero_is_lowest_bits": True,
            "vectors": build_weight_readback_vectors(image_payload, layout),
        },
    }
    return image_payload, layout, golden_report


def emit_header(layout: dict) -> str:
    lines = [
        "// Generated by rtl/tools/generate_memory_v3.py; do not edit.",
        "`ifndef MODEL_MEMORY_V3_MAP_VH",
        "`define MODEL_MEMORY_V3_MAP_VH",
        "",
        f"`define MODEL_V3_IMAGE_VERSION 32'd{FORMAT_VERSION}",
        f"`define MODEL_V3_STAGE_COUNT {layout['stage_count']}",
        f"`define MODEL_V3_IMAGE_BYTES 32'd{layout['image_bytes']}",
        f"`define MODEL_V3_MAX_STAGE_BYTES 32'd{layout['maximum_stage_bytes']}",
        f"`define MODEL_V3_CACHE_BYTES 32'd{CACHE_BYTES}",
        f"`define MODEL_V3_LANES {LANES}",
        f"`define MODEL_V3_GSU_PARAM_BITS {GSU_PARAM_RESPONSE_BITS}",
        f"`define MODEL_V3_PROJECTION_PARAM_BITS {PROJECTION_PARAM_RESPONSE_BITS}",
        f"`define MODEL_V3_WEIGHT_READBACK_COUNT {len(WEIGHT_READBACK_REQUESTS)}",
        f"`define MODEL_V3_STAGE_KIND_GSU 1'b{STAGE_KIND_GSU}",
        f"`define MODEL_V3_STAGE_KIND_PROJECTION 1'b{STAGE_KIND_PROJECTION}",
        "",
    ]

    for stage in layout["stages"]:
        prefix = f"MODEL_V3_STAGE_{stage['id']}"
        lines.extend(
            [
                f"// Stage {stage['id']}: {stage['name']}",
                f"`define {prefix}_DRAM_OFFSET 32'd{stage['dram_byte_offset']}",
                f"`define {prefix}_TRANSFER_BYTES 32'd{stage['transfer_bytes']}",
                f"`define {prefix}_KIND 1'b{stage['kind_id']}",
            ]
        )
        for matrix in stage["matrices"]:
            matrix_prefix = f"{prefix}_MATRIX_{matrix['id']}"
            lines.extend(
                [
                    f"`define {matrix_prefix}_WORD_OFFSET 32'd{matrix['local_word_offset']}",
                    f"`define {matrix_prefix}_SOURCES 10'd{matrix['source_count']}",
                    f"`define {matrix_prefix}_ROW_TILES 6'd{matrix['row_tiles']}",
                ]
            )
        lines.extend(
            [
                f"`define {prefix}_PARAM_WORD_OFFSET 32'd{stage['parameters']['local_word_offset']}",
                f"`define {prefix}_PARAM_RECORD_WORDS 8'd{stage['parameters']['record_words']}",
                f"`define {prefix}_PARAM_RESPONSE_BITS 13'd{stage['parameters']['response_bits']}",
                f"`define {prefix}_PARAM_TILES 6'd{stage['parameters']['row_tiles']}",
                f"`define {prefix}_HAS_LUT 1'b{int(stage['lut']['present'])}",
                f"`define {prefix}_LUT_WORD_OFFSET 32'd{stage['lut']['local_word_offset']}",
                f"`define {prefix}_LUT_BYTES 9'd{stage['lut']['payload_bytes']}",
                "",
            ]
        )

    for abi_name, fields in (
        ("GSU", layout["stages"][0]["parameters"]["fields"]),
        ("PROJECTION", layout["stages"][2]["parameters"]["fields"]),
    ):
        lines.append(f"// {abi_name} parameter response field offsets.")
        for field in fields:
            prefix = macro_name("MODEL_V3", abi_name, "PARAM", field["name"])
            lines.append(f"`define {prefix}_LSB {field['lsb']}")
            lines.append(f"`define {prefix}_BITS {field['bits']}")
        lines.append("")

    lines.append("`endif")
    return "\n".join(lines) + "\n"


def emit_table(layout: dict) -> str:
    lines = [
        "`timescale 1ns/1ps",
        "`include \"memory/model_memory_v3_map.vh\"",
        "",
        "// Generated combinational stage table for the v3 parameter image.",
        "module model_memory_v3_table (",
        "    input  wire [3:0]  stage_id,",
        "    output reg         stage_valid,",
        "    output reg         stage_kind,",
        "    output reg  [31:0] dram_byte_offset,",
        "    output reg  [31:0] transfer_bytes,",
        "    output reg  [1:0]  matrix_count,",
        "    output reg  [31:0] matrix0_word_offset,",
        "    output reg  [9:0]  matrix0_sources,",
        "    output reg  [5:0]  matrix0_row_tiles,",
        "    output reg  [31:0] matrix1_word_offset,",
        "    output reg  [9:0]  matrix1_sources,",
        "    output reg  [5:0]  matrix1_row_tiles,",
        "    output reg  [31:0] param_word_offset,",
        "    output reg  [7:0]  param_record_words,",
        "    output reg  [12:0] param_response_bits,",
        "    output reg  [5:0]  param_tiles,",
        "    output reg         has_lut,",
        "    output reg  [31:0] lut_word_offset,",
        "    output reg  [8:0]  lut_bytes",
        ");",
        "    always @* begin",
        "        stage_valid = 1'b0;",
        "        stage_kind = 1'b0;",
        "        dram_byte_offset = 32'd0;",
        "        transfer_bytes = 32'd0;",
        "        matrix_count = 2'd0;",
        "        matrix0_word_offset = 32'd0;",
        "        matrix0_sources = 10'd0;",
        "        matrix0_row_tiles = 6'd0;",
        "        matrix1_word_offset = 32'd0;",
        "        matrix1_sources = 10'd0;",
        "        matrix1_row_tiles = 6'd0;",
        "        param_word_offset = 32'd0;",
        "        param_record_words = 8'd0;",
        "        param_response_bits = 13'd0;",
        "        param_tiles = 6'd0;",
        "        has_lut = 1'b0;",
        "        lut_word_offset = 32'd0;",
        "        lut_bytes = 9'd0;",
        "        case (stage_id)",
    ]
    for stage in layout["stages"]:
        matrices = stage["matrices"]
        matrix0 = matrices[0]
        matrix1 = matrices[1] if len(matrices) > 1 else None
        lines.extend(
            [
                f"            4'd{stage['id']}: begin",
                "                stage_valid = 1'b1;",
                f"                stage_kind = 1'b{stage['kind_id']};",
                f"                dram_byte_offset = 32'd{stage['dram_byte_offset']};",
                f"                transfer_bytes = 32'd{stage['transfer_bytes']};",
                f"                matrix_count = 2'd{len(matrices)};",
                f"                matrix0_word_offset = 32'd{matrix0['local_word_offset']};",
                f"                matrix0_sources = 10'd{matrix0['source_count']};",
                f"                matrix0_row_tiles = 6'd{matrix0['row_tiles']};",
            ]
        )
        if matrix1 is not None:
            lines.extend(
                [
                    f"                matrix1_word_offset = 32'd{matrix1['local_word_offset']};",
                    f"                matrix1_sources = 10'd{matrix1['source_count']};",
                    f"                matrix1_row_tiles = 6'd{matrix1['row_tiles']};",
                ]
            )
        lines.extend(
            [
                f"                param_word_offset = 32'd{stage['parameters']['local_word_offset']};",
                f"                param_record_words = 8'd{stage['parameters']['record_words']};",
                f"                param_response_bits = 13'd{stage['parameters']['response_bits']};",
                f"                param_tiles = 6'd{stage['parameters']['row_tiles']};",
                f"                has_lut = 1'b{int(stage['lut']['present'])};",
                f"                lut_word_offset = 32'd{stage['lut']['local_word_offset']};",
                f"                lut_bytes = 9'd{stage['lut']['payload_bytes']};",
                "            end",
            ]
        )
    lines.extend(
        [
            "            default: begin end",
            "        endcase",
            "    end",
            "endmodule",
            "",
        ]
    )
    return "\n".join(lines)


def emit_readback_table(golden: dict) -> str:
    """Emit the exact request/response vectors used by the RTL integration TB."""
    vectors = golden["weight_readback_vectors"]["vectors"]
    lines = [
        "`timescale 1ns/1ps",
        "",
        "// Generated by rtl/tools/generate_memory_v3.py; do not edit.",
        "module model_memory_v3_readback_table (",
        "    input  wire [3:0]   index,",
        "    output reg          valid,",
        "    output reg  [3:0]   stage_id,",
        "    output reg          matrix_id,",
        "    output reg  [9:0]   source_index,",
        "    output reg  [5:0]   row_tile,",
        "    output reg  [7:0]   tag,",
        "    output reg  [127:0] expected_data",
        ");",
        "    always @* begin",
        "        valid = 1'b0;",
        "        stage_id = 4'd0;",
        "        matrix_id = 1'b0;",
        "        source_index = 10'd0;",
        "        row_tile = 6'd0;",
        "        tag = 8'd0;",
        "        expected_data = 128'd0;",
        "        case (index)",
    ]
    for vector in vectors:
        numeric_hex = vector["expected_u128_le_hex"][2:]
        lines.extend(
            [
                f"            4'd{vector['index']}: begin",
                "                valid = 1'b1;",
                f"                stage_id = 4'd{vector['stage']};",
                f"                matrix_id = 1'b{vector['matrix']};",
                f"                source_index = 10'd{vector['source']};",
                f"                row_tile = 6'd{vector['row_tile']};",
                f"                tag = 8'h{vector['tag']:02x};",
                f"                expected_data = 128'h{numeric_hex};",
                "            end",
            ]
        )
    lines.extend(
        [
            "            default: begin end",
            "        endcase",
            "    end",
            "endmodule",
            "",
        ]
    )
    return "\n".join(lines)


def checksum_manifest(files: Iterable[Path], base_directories: Iterable[Path]) -> bytes:
    bases = [base.resolve() for base in base_directories]
    lines = []
    for path in files:
        resolved = path.resolve()
        display = path.name
        for base in bases:
            try:
                display = resolved.relative_to(base).as_posix()
                break
            except ValueError:
                continue
        lines.append(f"{sha256(path.read_bytes())}  {display}")
    return ("\n".join(lines) + "\n").encode("ascii")


def write_artifacts(
    *,
    image: bytes,
    layout: dict,
    golden: dict,
    output_dir: Path,
    output_vh: Path,
    output_table: Path,
    output_readback_table: Path,
) -> list[Path]:
    image_path = output_dir / "parameters_v3.bin"
    layout_path = output_dir / "memory_layout_v3.json"
    golden_path = output_dir / "memory_golden_v3.json"
    checksum_path = output_dir / "parameters_v3.sha256"

    atomic_write(image_path, image)
    atomic_write(layout_path, json_bytes(layout))
    atomic_write(golden_path, json_bytes(golden))
    atomic_write(output_vh, emit_header(layout).encode("utf-8"))
    atomic_write(output_table, emit_table(layout).encode("utf-8"))
    atomic_write(
        output_readback_table, emit_readback_table(golden).encode("utf-8")
    )
    artifact_paths = [
        image_path,
        layout_path,
        golden_path,
        output_vh,
        output_table,
        output_readback_table,
    ]
    atomic_write(
        checksum_path,
        checksum_manifest(
            artifact_paths,
            [
                output_dir,
                output_vh.parent,
                output_table.parent,
                output_readback_table.parent,
            ],
        ),
    )
    return artifact_paths + [checksum_path]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--manifest",
        type=Path,
        default=Path("upstream/parameters/manifest.json"),
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("outputs/memory/2026-09-01/v3"),
    )
    parser.add_argument(
        "--output-vh",
        type=Path,
        default=Path("rtl/memory/model_memory_v3_map.vh"),
    )
    parser.add_argument(
        "--output-table",
        type=Path,
        default=Path("rtl/memory/model_memory_v3_table.v"),
    )
    parser.add_argument(
        "--output-readback-table",
        type=Path,
        default=Path("rtl/memory/model_memory_v3_readback_table.v"),
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    image, layout, golden = build_image(args.manifest)
    paths = write_artifacts(
        image=image,
        layout=layout,
        golden=golden,
        output_dir=args.output_dir,
        output_vh=args.output_vh,
        output_table=args.output_table,
        output_readback_table=args.output_readback_table,
    )
    for path in paths:
        print(f"wrote {path} ({path.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
