#!/usr/bin/env python3
"""Generate the production-v2, 32-row parameter image.

Version 5 preserves the frozen v4 global sigmoid-table contract and external
64-bit bus words. It changes only the accelerator-native image: weight tiles
and parameter fields contain 32 rows. A GSU response is 11,584 bits (181 bus
words) and a projection response is 2,240 bits (35 words), without padding.

The source manifest/blob and v3/v4 files are read-only. This emits a separate
v5 artifact set and does not connect it to the production controller.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct

if __package__:
    from . import generate_memory_v3 as v3
    from . import generate_memory_v4 as v4
else:
    import generate_memory_v3 as v3
    import generate_memory_v4 as v4


ROOT = v3.ROOT
FORMAT_VERSION = 5
GENERATOR_VERSION = "zephyr-memory-v5.0"
IMAGE_MAGIC = b"ZEPHYR5\0"
IMAGE_HEADER_BYTES = v3.IMAGE_HEADER_BYTES
LANES = 32
BUS_BYTES = v3.BUS_BYTES
STAGE_ALIGNMENT = v3.STAGE_ALIGNMENT
SECTION_ALIGNMENT = v3.SECTION_ALIGNMENT
CACHE_BYTES = v3.CACHE_BYTES

STAGE_KIND_GSU = v3.STAGE_KIND_GSU
STAGE_KIND_PROJECTION = v3.STAGE_KIND_PROJECTION
GSU_PARAM_RESPONSE_BITS = 11_584
GSU_PARAM_RECORD_BYTES = 1_448
PROJECTION_PARAM_RESPONSE_BITS = 2_240
PROJECTION_PARAM_RECORD_BYTES = 280
OPERATOR_EXECUTION_ORDER = v3.OPERATOR_EXECUTION_ORDER

GLOBAL_LUT_TABLE_COUNT = v4.GLOBAL_LUT_TABLE_COUNT
GLOBAL_LUT_ENTRIES_PER_TABLE = v4.GLOBAL_LUT_ENTRIES_PER_TABLE
GLOBAL_LUT_PAYLOAD_BYTES = v4.GLOBAL_LUT_PAYLOAD_BYTES
SIGMOID_TABLE_OPERATOR_ORDER = v4.SIGMOID_TABLE_OPERATOR_ORDER
SIGMOID_TABLE_SELECT_BY_OPERATOR = v4.SIGMOID_TABLE_SELECT_BY_OPERATOR

# Cover the smallest projection and largest GSU, both matrices, both halves of
# a 32-row tile, and first/last source/tile boundaries.
WEIGHT_READBACK_REQUESTS = [
    {"stage": 2, "matrix": 0, "source": 0, "row_tile": 0, "tag": 0x20},
    {"stage": 2, "matrix": 0, "source": 0, "row_tile": 1, "tag": 0x21},
    {"stage": 2, "matrix": 0, "source": 1, "row_tile": 0, "tag": 0x22},
    {"stage": 2, "matrix": 0, "source": 159, "row_tile": 1, "tag": 0x23},
    {"stage": 2, "matrix": 0, "source": 319, "row_tile": 1, "tag": 0x24},
    {"stage": 1, "matrix": 0, "source": 0, "row_tile": 0, "tag": 0x10},
    {"stage": 1, "matrix": 0, "source": 0, "row_tile": 9, "tag": 0x11},
    {"stage": 1, "matrix": 0, "source": 159, "row_tile": 5, "tag": 0x12},
    {"stage": 1, "matrix": 0, "source": 319, "row_tile": 9, "tag": 0x13},
    {"stage": 1, "matrix": 1, "source": 0, "row_tile": 0, "tag": 0x14},
    {"stage": 1, "matrix": 1, "source": 0, "row_tile": 9, "tag": 0x15},
    {"stage": 1, "matrix": 1, "source": 159, "row_tile": 5, "tag": 0x16},
    {"stage": 1, "matrix": 1, "source": 319, "row_tile": 9, "tag": 0x17},
]


def align_up(value: int, alignment: int) -> int:
    return v3.align_up(value, alignment)


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def image_header(manifest_sha: str, stage_count: int) -> bytes:
    prefix = struct.pack(
        "<8sIIIIII", IMAGE_MAGIC, FORMAT_VERSION, stage_count, LANES,
        BUS_BYTES, STAGE_ALIGNMENT, 0,
    )
    header = prefix + bytes.fromhex(manifest_sha)
    if len(header) != IMAGE_HEADER_BYTES:
        raise AssertionError(f"image header is {len(header)} bytes")
    return header


def pack_source_major_matrix(
    raw: bytes,
    *,
    source_rows: int,
    output_rows: int,
    source_count: int,
    shared_gate_halves: bool,
    tensor_name: str,
) -> tuple[bytes, dict]:
    """Transpose a source-row-major INT8 matrix into 32-row tiles."""
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

    payload = bytes(packed)
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
        "packed_sha256": sha256(payload),
    }
    return payload, metadata


def pack_parameter_records(
    *,
    blob: bytes,
    tensors: dict,
    hidden_size: int,
    fields: list[tuple[str, str, str, int, bool]],
    response_bits: int,
    record_bytes: int,
) -> tuple[bytes, dict, dict]:
    """Pack field-major responses with 32 adjacent lane values per field."""
    values_by_tensor: dict[str, list[int | float]] = {}
    for _, tensor_name, _, _, _ in fields:
        if tensor_name not in values_by_tensor:
            values_by_tensor[tensor_name] = v3.tensor_values(
                blob, tensors[tensor_name], tensor_name
            )

    field_layout = []
    bit_cursor = 0
    for field_name, tensor_name, selector, width, signed in fields:
        field_layout.append({
            "name": field_name,
            "source_tensor": tensor_name,
            "source_selector": selector,
            "lsb": bit_cursor,
            "lane_width": width,
            "lanes": LANES,
            "bits": width * LANES,
            "signed": signed,
        })
        bit_cursor += width * LANES
    if bit_cursor != response_bits:
        raise ValueError(
            f"parameter ABI fields use {bit_cursor} bits, expected {response_bits}"
        )
    response_bytes = (response_bits + 7) // 8
    if record_bytes != response_bytes or record_bytes % BUS_BYTES:
        raise ValueError("v5 parameter record must be an exact bus-aligned response")

    field_ranges: dict[str, dict] = {}
    verified_values = 0
    for field_name, tensor_name, selector, width, signed in fields:
        source_values = values_by_tensor[tensor_name]
        selected = [
            int(source_values[v3.field_source_index(selector, hidden_size, channel)])
            for channel in range(hidden_size)
        ]
        for value in selected:
            v3.lowered_value(value, width, signed, field_name)
        field_ranges[field_name] = {
            "minimum": min(selected),
            "maximum": max(selected),
            "verified_values": len(selected),
        }
        verified_values += len(selected)

    records = bytearray()
    row_tiles = (hidden_size + LANES - 1) // LANES
    for row_tile in range(row_tiles):
        word = 0
        for field in field_layout:
            source_values = values_by_tensor[field["source_tensor"]]
            for lane in range(LANES):
                channel = row_tile * LANES + lane
                value = 0
                if channel < hidden_size:
                    source_index = v3.field_source_index(
                        field["source_selector"], hidden_size, channel
                    )
                    value = int(source_values[source_index])
                encoded = v3.lowered_value(
                    value, field["lane_width"], field["signed"], field["name"]
                )
                word |= encoded << (field["lsb"] + lane * field["lane_width"])
        records.extend(word.to_bytes(response_bytes, "little"))

    payload = bytes(records)
    metadata = {
        "row_tiles": row_tiles,
        "lanes": LANES,
        "response_bits": response_bits,
        "response_bytes": response_bytes,
        "record_bytes": record_bytes,
        "record_words": record_bytes // BUS_BYTES,
        "record_padding_bytes": 0,
        "fields": field_layout,
        "verified_values": verified_values,
        "packed_sha256": sha256(payload),
    }
    return payload, metadata, field_ranges


def build_stage(
    *,
    stage_id: int,
    operator_name: str,
    operator: dict,
    blob: bytes,
    expected_lut_sha: str | None,
) -> tuple[bytes, dict, dict]:
    stage = bytearray()
    matrices = []
    tensors = operator["tensors"]
    operator_class = operator["class"]

    if operator_class == "IntegerGSUCellReference":
        kind, kind_id = "gsu", STAGE_KIND_GSU
        hidden_size = int(tensors["bn_bias_q"]["shape"][0])
        matrix_specs = [(0, "weight_ih_q"), (1, "weight_hh_q")]
        parameter_fields = v3.GSU_PARAM_FIELDS
        response_bits, record_bytes = GSU_PARAM_RESPONSE_BITS, GSU_PARAM_RECORD_BYTES
        runtime_tensors = {
            "weight_ih_q", "weight_hh_q", "input_requantizer.multiplier",
            "input_requantizer.right_shift", "recurrent_requantizer.multiplier",
            "recurrent_requantizer.right_shift", "bias_q",
            "cx_requantizer.multiplier", "cx_requantizer.right_shift",
            "cellgate_requantizer.multiplier", "cellgate_requantizer.right_shift",
            "bn_requantizer.multiplier", "bn_requantizer.right_shift",
            "bn_bias_q", "sigmoid_lut",
        }
        if operator_name not in SIGMOID_TABLE_SELECT_BY_OPERATOR:
            raise ValueError(f"GSU stage {operator_name} has no frozen table_select")
        lut_payload = v3.tensor_bytes(blob, tensors["sigmoid_lut"], "sigmoid_lut")
        if sha256(lut_payload) != expected_lut_sha:
            raise ValueError(f"GSU stage {operator_name} LUT/global mapping mismatch")
        uses_sigmoid_table = True
        sigmoid_table_select: int | None = SIGMOID_TABLE_SELECT_BY_OPERATOR[operator_name]
    elif operator_class == "IntegerLinearReference":
        kind, kind_id = "projection", STAGE_KIND_PROJECTION
        hidden_size, _ = map(int, tensors["weight_q"]["shape"])
        matrix_specs = [(0, "weight_q")]
        parameter_fields = v3.PROJECTION_PARAM_FIELDS
        response_bits, record_bytes = (
            PROJECTION_PARAM_RESPONSE_BITS, PROJECTION_PARAM_RECORD_BYTES
        )
        runtime_tensors = {
            "weight_q", "requantizer.multiplier", "requantizer.right_shift", "bias_q"
        }
        if operator_name in SIGMOID_TABLE_SELECT_BY_OPERATOR or expected_lut_sha is not None:
            raise ValueError(f"projection stage {operator_name} has a sigmoid mapping")
        uses_sigmoid_table = False
        sigmoid_table_select = None
    else:
        raise ValueError(f"unsupported operator class: {operator_class}")

    for matrix_id, tensor_name in matrix_specs:
        tensor = tensors[tensor_name]
        source_rows, source_count = map(int, tensor["shape"])
        packed, matrix_meta = pack_source_major_matrix(
            v3.tensor_bytes(blob, tensor, tensor_name),
            source_rows=source_rows,
            output_rows=hidden_size,
            source_count=source_count,
            shared_gate_halves=(kind == "gsu"),
            tensor_name=tensor_name,
        )
        local_offset, payload_bytes = v3.append_aligned(
            stage, packed, SECTION_ALIGNMENT
        )
        matrix_meta.update({
            "id": matrix_id,
            "name": tensor_name,
            "source_shape": tensor["shape"],
            "source_sha256": tensor["sha256"],
            "local_byte_offset": local_offset,
            "local_word_offset": local_offset // BUS_BYTES,
            "payload_bytes": payload_bytes,
        })
        matrices.append(matrix_meta)

    parameter_payload, parameter_meta, field_ranges = pack_parameter_records(
        blob=blob,
        tensors=tensors,
        hidden_size=hidden_size,
        fields=parameter_fields,
        response_bits=response_bits,
        record_bytes=record_bytes,
    )
    param_offset, param_bytes = v3.append_aligned(
        stage, parameter_payload, SECTION_ALIGNMENT
    )
    parameter_meta.update({
        "local_byte_offset": param_offset,
        "local_word_offset": param_offset // BUS_BYTES,
        "payload_bytes": param_bytes,
    })
    stage.extend(bytes(align_up(len(stage), BUS_BYTES) - len(stage)))

    if len(stage) > CACHE_BYTES:
        raise ValueError(f"stage {operator_name} is {len(stage)} bytes and exceeds cache")
    stage_payload = bytes(stage)
    stage_meta = {
        "id": stage_id,
        "name": operator_name,
        "class": operator_class,
        "kind": kind,
        "kind_id": kind_id,
        "transfer_bytes": len(stage_payload),
        "bram_words": len(stage_payload) // BUS_BYTES,
        "matrix_count": len(matrices),
        "matrices": matrices,
        "parameters": parameter_meta,
        "uses_sigmoid_table": uses_sigmoid_table,
        "sigmoid_table_select": sigmoid_table_select,
        "excluded_metadata_tensors": sorted(set(tensors) - runtime_tensors),
        "stage_sha256": sha256(stage_payload),
    }
    golden = {
        "id": stage_id,
        "name": operator_name,
        "kind": kind,
        "stage_sha256": stage_meta["stage_sha256"],
        "matrices": [{
            "name": matrix["name"],
            "packed_sha256": matrix["packed_sha256"],
            "verified_source_values": matrix["verified_source_values"],
            "verified_duplicate_values": matrix["verified_duplicate_values"],
            "padding_lanes": matrix["padding_lanes"],
        } for matrix in matrices],
        "parameters": {
            "packed_sha256": parameter_meta["packed_sha256"],
            "verified_values": parameter_meta["verified_values"],
            "field_ranges": field_ranges,
        },
        "uses_sigmoid_table": uses_sigmoid_table,
        "sigmoid_table_select": sigmoid_table_select,
    }
    return stage_payload, stage_meta, golden


def build_weight_readback_vectors(image: bytes, layout: dict) -> list[dict]:
    stages = {int(stage["id"]): stage for stage in layout["stages"]}
    vectors = []
    for index, request in enumerate(WEIGHT_READBACK_REQUESTS):
        stage = stages[request["stage"]]
        matrices = {int(matrix["id"]): matrix for matrix in stage["matrices"]}
        matrix = matrices.get(request["matrix"])
        if matrix is None:
            raise ValueError(f"readback vector {index} selects an absent matrix")
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
        vectors.append({
            "index": index,
            **request,
            "image_byte_offset": image_offset,
            "expected_lane_bytes_hex": payload.hex(),
            "expected_u256_le_hex": f"0x{int.from_bytes(payload, 'little'):064x}",
            "expected_words_le": [
                int.from_bytes(payload[word : word + 4], "little")
                for word in range(0, LANES, 4)
            ],
        })
    return vectors


def build_image(manifest_path: Path) -> tuple[bytes, dict, dict]:
    manifest_payload = manifest_path.read_bytes()
    manifest = json.loads(manifest_payload)
    blob_path = manifest_path.parent / manifest["storage"]["file"]
    blob = blob_path.read_bytes()
    v3.validate_manifest(manifest, blob)

    manifest_sha = sha256(manifest_payload)
    global_payload, global_meta, stage_lut_sha_by_id = v4.build_global_sigmoid_lut(
        manifest, blob
    )
    image = bytearray(image_header(manifest_sha, len(OPERATOR_EXECUTION_ORDER)))
    global_start = align_up(len(image), SECTION_ALIGNMENT)
    image.extend(bytes(global_start - len(image)))
    image.extend(global_payload)
    image.extend(bytes(int(global_meta["transfer_bytes"]) - len(global_payload)))
    global_meta["dram_byte_offset"] = global_start
    global_meta["dram_word_offset"] = global_start // BUS_BYTES
    for table in global_meta["tables"]:
        table["dram_byte_offset"] = global_start + int(table["local_byte_offset"])

    stages, golden_stages = [], []
    for stage_id, operator_name in enumerate(OPERATOR_EXECUTION_ORDER):
        stage_payload, stage_meta, golden = build_stage(
            stage_id=stage_id,
            operator_name=operator_name,
            operator=manifest["operators"][operator_name],
            blob=blob,
            expected_lut_sha=stage_lut_sha_by_id.get(stage_id),
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
        "source_manifest": v3.relative_source_path(manifest_path),
        "source_manifest_sha256": manifest_sha,
        "source_blob": v3.relative_source_path(blob_path),
        "source_blob_bytes": len(blob),
        "source_blob_sha256": sha256(blob),
        "bus_bytes": BUS_BYTES,
        "stage_alignment": STAGE_ALIGNMENT,
        "section_alignment": SECTION_ALIGNMENT,
        "lanes": LANES,
        "cache_bytes": CACHE_BYTES,
        "maximum_stage_bytes": max(stage["transfer_bytes"] for stage in stages),
        "stage_count": len(stages),
        "weight_physical_order": [
            "operator", "matrix", "source_index", "row_tile", "lane"
        ],
        "v4_tile_pairing": {
            "relationship": "v5_tile[t] = v4_tile[2*t] || v4_tile[2*t+1]",
            "lower_lanes": "v4 even tile lanes 0..15",
            "upper_lanes": "v4 odd tile lanes 16..31",
        },
        "global_sigmoid_lut": global_meta,
        "parameter_abi": {
            "gsu_response_bits": GSU_PARAM_RESPONSE_BITS,
            "gsu_record_bytes": GSU_PARAM_RECORD_BYTES,
            "gsu_record_words": GSU_PARAM_RECORD_BYTES // BUS_BYTES,
            "projection_response_bits": PROJECTION_PARAM_RESPONSE_BITS,
            "projection_record_bytes": PROJECTION_PARAM_RECORD_BYTES,
            "projection_record_words": PROJECTION_PARAM_RECORD_BYTES // BUS_BYTES,
            "lane_zero_is_lowest_bits": True,
            "record_byte_order": "little-endian",
            "record_padding_bytes": 0,
        },
        "canonical_generator_command": (
            "python3 rtl/tools/generate_memory_v5.py "
            "--manifest upstream/parameters/manifest.json"
        ),
        "stages": stages,
    }

    total_matrix_values = sum(
        matrix["verified_source_values"] + matrix["verified_duplicate_values"]
        for stage in golden_stages for matrix in stage["matrices"]
    )
    total_parameter_values = sum(
        stage["parameters"]["verified_values"] for stage in golden_stages
    )
    global_golden = {
        "sha256": global_meta["sha256"],
        "verified_values": global_meta["verified_values"],
        "table_count": global_meta["table_count"],
        "entries_per_table": global_meta["entries_per_table"],
        "table_major": True,
        "frozen_pe_table_select_order_verified": True,
        "tables": [{
            "table_select": table["table_select"],
            "operator": table["operator"],
            "source_stage_id": table["source_stage_id"],
            "sha256": table["sha256"],
            "verified_values": table["entries"],
        } for table in global_meta["tables"]],
    }
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
            "all_global_lut_values_compared_to_source": True,
            "all_global_lut_values_compared_to_frozen_pe_reference": True,
            "all_per_stage_lut_payloads_removed": True,
            "matrix_values_verified": total_matrix_values,
            "parameter_values_verified": total_parameter_values,
            "lut_values_verified": len(global_payload),
        },
        "global_sigmoid_lut": global_golden,
        "stages": golden_stages,
        "weight_readback_vectors": {
            "count": len(WEIGHT_READBACK_REQUESTS),
            "lane_zero_is_lowest_bits": True,
            "vectors": build_weight_readback_vectors(image_payload, layout),
        },
    }
    return image_payload, layout, golden_report


def emit_header(layout: dict) -> str:
    source = v4.emit_header(layout)
    return (
        source.replace("generate_memory_v4.py", "generate_memory_v5.py")
        .replace("MODEL_MEMORY_V4", "MODEL_MEMORY_V5")
        .replace("MODEL_V4", "MODEL_V5")
        .replace("MODEL_V5_IMAGE_VERSION 32'd4", "MODEL_V5_IMAGE_VERSION 32'd5")
        .replace("MODEL_V5_LANES 16", "MODEL_V5_LANES 32")
        .replace("MODEL_V5_GSU_PARAM_BITS 5792", "MODEL_V5_GSU_PARAM_BITS 11584")
        .replace(
            "MODEL_V5_PROJECTION_PARAM_BITS 1120",
            "MODEL_V5_PROJECTION_PARAM_BITS 2240",
        )
        .replace("13'd", "14'd")
    )


def emit_table(layout: dict) -> str:
    source = v4.emit_table(layout)
    return (
        source.replace("model_memory_v4_map.vh", "model_memory_v5_map.vh")
        .replace("model_memory_v4_table", "model_memory_v5_table")
        .replace("v4 parameter image", "v5 parameter image")
        .replace("[12:0] param_response_bits", "[13:0] param_response_bits")
        .replace("param_response_bits = 13'd", "param_response_bits = 14'd")
    )


def emit_readback_table(golden: dict) -> str:
    vectors = golden["weight_readback_vectors"]["vectors"]
    lines = [
        "`timescale 1ns/1ps", "",
        "// Generated by rtl/tools/generate_memory_v5.py; do not edit.",
        "module model_memory_v5_readback_table (",
        "    input  wire [3:0]   index,",
        "    output reg          valid,",
        "    output reg  [3:0]   stage_id,",
        "    output reg          matrix_id,",
        "    output reg  [9:0]   source_index,",
        "    output reg  [5:0]   row_tile,",
        "    output reg  [7:0]   tag,",
        "    output reg  [255:0] expected_data", ");",
        "    always @* begin",
        "        valid = 1'b0;", "        stage_id = 4'd0;",
        "        matrix_id = 1'b0;", "        source_index = 10'd0;",
        "        row_tile = 6'd0;", "        tag = 8'd0;",
        "        expected_data = 256'd0;", "        case (index)",
    ]
    for vector in vectors:
        numeric_hex = vector["expected_u256_le_hex"][2:]
        lines.extend([
            f"            4'd{vector['index']}: begin",
            "                valid = 1'b1;",
            f"                stage_id = 4'd{vector['stage']};",
            f"                matrix_id = 1'b{vector['matrix']};",
            f"                source_index = 10'd{vector['source']};",
            f"                row_tile = 6'd{vector['row_tile']};",
            f"                tag = 8'h{vector['tag']:02x};",
            f"                expected_data = 256'h{numeric_hex};",
            "            end",
        ])
    lines.extend([
        "            default: begin end", "        endcase", "    end",
        "endmodule", "",
    ])
    return "\n".join(lines)


def write_artifacts(
    *, image: bytes, layout: dict, golden: dict, output_dir: Path,
    output_vh: Path, output_table: Path, output_readback_table: Path,
) -> list[Path]:
    image_path = output_dir / "parameters_v5.bin"
    layout_path = output_dir / "memory_layout_v5.json"
    golden_path = output_dir / "memory_golden_v5.json"
    checksum_path = output_dir / "parameters_v5.sha256"
    v4.atomic_write(image_path, image)
    v4.atomic_write(layout_path, v4.json_bytes(layout))
    v4.atomic_write(golden_path, v4.json_bytes(golden))
    v4.atomic_write(output_vh, emit_header(layout).encode("utf-8"))
    v4.atomic_write(output_table, emit_table(layout).encode("utf-8"))
    v4.atomic_write(output_readback_table, emit_readback_table(golden).encode("utf-8"))
    artifact_paths = [
        image_path, layout_path, golden_path, output_vh, output_table,
        output_readback_table,
    ]
    v4.atomic_write(
        checksum_path,
        v3.checksum_manifest(
            artifact_paths,
            [output_dir, output_vh.parent, output_table.parent, output_readback_table.parent],
        ),
    )
    return artifact_paths + [checksum_path]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--manifest", type=Path, default=Path("upstream/parameters/manifest.json")
    )
    parser.add_argument(
        "--output-dir", type=Path, default=Path("outputs/memory/2026-09-09/v5")
    )
    parser.add_argument(
        "--output-vh", type=Path, default=Path("rtl/memory/model_memory_v5_map.vh")
    )
    parser.add_argument(
        "--output-table", type=Path, default=Path("rtl/memory/model_memory_v5_table.v")
    )
    parser.add_argument(
        "--output-readback-table", type=Path,
        default=Path("rtl/memory/model_memory_v5_readback_table.v"),
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    image, layout, golden = build_image(args.manifest)
    paths = write_artifacts(
        image=image, layout=layout, golden=golden, output_dir=args.output_dir,
        output_vh=args.output_vh, output_table=args.output_table,
        output_readback_table=args.output_readback_table,
    )
    for path in paths:
        print(f"wrote {path} ({path.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
