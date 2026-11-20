#!/usr/bin/env python3
"""Generate the version-4 parameter image with one global sigmoid LUT.

Version 4 preserves the version-3 weight and parameter encodings byte for
byte, but removes the trailing sigmoid payload from every GSU stage.  All
eight 255-byte tables instead live in one table-major global section.  Each
GSU stage carries only the explicit frozen-PE ``sigmoid_table_select`` value;
projection stages explicitly carry no sigmoid mapping.

The source manifest/blob, the version-3 generator and every version-3
artifact remain read-only.  The frozen PE reference is checked while building
the global section so an ambiguous or changed table-select order fails closed.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import tempfile

if __package__:
    from . import generate_memory_v3 as v3
else:
    import generate_memory_v3 as v3


ROOT = v3.ROOT

FORMAT_VERSION = 4
GENERATOR_VERSION = "zephyr-memory-v4.0"
IMAGE_MAGIC = b"ZEPHYR4\0"
IMAGE_HEADER_BYTES = v3.IMAGE_HEADER_BYTES
LANES = v3.LANES
BUS_BYTES = v3.BUS_BYTES
STAGE_ALIGNMENT = v3.STAGE_ALIGNMENT
SECTION_ALIGNMENT = v3.SECTION_ALIGNMENT
CACHE_BYTES = v3.CACHE_BYTES

STAGE_KIND_GSU = v3.STAGE_KIND_GSU
STAGE_KIND_PROJECTION = v3.STAGE_KIND_PROJECTION
GSU_PARAM_RESPONSE_BITS = v3.GSU_PARAM_RESPONSE_BITS
GSU_PARAM_RECORD_BYTES = v3.GSU_PARAM_RECORD_BYTES
PROJECTION_PARAM_RESPONSE_BITS = v3.PROJECTION_PARAM_RESPONSE_BITS
PROJECTION_PARAM_RECORD_BYTES = v3.PROJECTION_PARAM_RECORD_BYTES
OPERATOR_EXECUTION_ORDER = v3.OPERATOR_EXECUTION_ORDER
WEIGHT_READBACK_REQUESTS = v3.WEIGHT_READBACK_REQUESTS

GLOBAL_LUT_TABLE_COUNT = 8
GLOBAL_LUT_ENTRIES_PER_TABLE = 255
GLOBAL_LUT_PAYLOAD_BYTES = GLOBAL_LUT_TABLE_COUNT * GLOBAL_LUT_ENTRIES_PER_TABLE

# This is the table_select order frozen by
# baseline/v1/reference/pe_sigmoid_lut_255_reference.py.  That reference sorts
# the eight GSU operator names; it does not use stage ID.  Projection stages
# make the distinction observable (table_select 2 maps to stage 3, and so on).
SIGMOID_TABLE_OPERATOR_ORDER = [
    "fb_model.sequence_model.layers.0.cell",
    "fb_model.sequence_model.layers.1.cell",
    "sb_model.sb_models.0.sequence_model.layers.0.cell",
    "sb_model.sb_models.0.sequence_model.layers.1.cell",
    "sb_model.sb_models.1.sequence_model.layers.0.cell",
    "sb_model.sb_models.1.sequence_model.layers.1.cell",
    "sb_model.sb_models.2.sequence_model.layers.0.cell",
    "sb_model.sb_models.2.sequence_model.layers.1.cell",
]
SIGMOID_TABLE_SELECT_BY_OPERATOR = {
    operator: table_select
    for table_select, operator in enumerate(SIGMOID_TABLE_OPERATOR_ORDER)
}

FROZEN_PE_REFERENCE_ROOT = ROOT / "rtl" / "pe_array" / "baseline" / "v1"
FROZEN_PE_REFERENCE_SUMMARY = (
    FROZEN_PE_REFERENCE_ROOT
    / "reports"
    / "pe_sigmoid_lut_255"
    / "reference_summary.json"
)
FROZEN_PE_REFERENCE_TABLES = (
    FROZEN_PE_REFERENCE_ROOT
    / "tb"
    / "vectors"
    / "pe_sigmoid_lut_255_tables.hex"
)
FROZEN_PE_REFERENCE_TABLES_SHA256 = (
    "0ed091b0b4e1beee8ce7a48efaf5cbea642b735c2f19590ff4c5652458e70f56"
)
FROZEN_GLOBAL_LUT_SHA256 = (
    "af70843be21e720cedb6f627b02b69ef69a2519912c5bf900d9147f70b602c21"
)


def align_up(value: int, alignment: int) -> int:
    return v3.align_up(value, alignment)


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def macro_name(*parts: str) -> str:
    text = "_".join(parts).upper()
    return re.sub(r"[^A-Z0-9]+", "_", text).strip("_")


def relative_source_path(path: Path) -> str:
    return v3.relative_source_path(path)


def atomic_write(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", dir=path.parent
    )
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


def load_frozen_pe_lut_contract() -> tuple[dict, bytes]:
    """Load and validate the immutable PE table_select reference artifacts."""
    summary = json.loads(FROZEN_PE_REFERENCE_SUMMARY.read_text(encoding="utf-8"))
    vector_text = FROZEN_PE_REFERENCE_TABLES.read_text(encoding="ascii")
    vector_payload = FROZEN_PE_REFERENCE_TABLES.read_bytes()

    if sha256(vector_payload) != FROZEN_PE_REFERENCE_TABLES_SHA256:
        raise ValueError("frozen PE sigmoid table vector SHA-256 mismatch")
    if summary.get("table_count") != GLOBAL_LUT_TABLE_COUNT:
        raise ValueError("frozen PE sigmoid table count changed")
    if summary.get("entries_per_table") != GLOBAL_LUT_ENTRIES_PER_TABLE:
        raise ValueError("frozen PE sigmoid table depth changed")
    if summary.get("total_entries") != GLOBAL_LUT_PAYLOAD_BYTES:
        raise ValueError("frozen PE flattened sigmoid length changed")

    tables = summary.get("tables", [])
    table_indices = [table.get("table_index") for table in tables]
    operators = [table.get("operator") for table in tables]
    if table_indices != list(range(GLOBAL_LUT_TABLE_COUNT)):
        raise ValueError("frozen PE sigmoid table indices are not ordered 0..7")
    if operators != SIGMOID_TABLE_OPERATOR_ORDER:
        raise ValueError("frozen PE sigmoid table_select operator order changed")

    lines = vector_text.splitlines()
    if len(lines) != GLOBAL_LUT_PAYLOAD_BYTES:
        raise ValueError("frozen PE sigmoid vector does not contain 8 x 255 bytes")
    try:
        flattened = bytes(int(line, 16) for line in lines)
    except ValueError as error:
        raise ValueError("frozen PE sigmoid vector contains a non-byte value") from error
    if any(len(line) != 2 for line in lines):
        raise ValueError("frozen PE sigmoid vector is not canonical byte-per-line hex")
    if sha256(flattened) != FROZEN_GLOBAL_LUT_SHA256:
        raise ValueError("frozen PE flattened sigmoid payload SHA-256 mismatch")
    return summary, flattened


def build_global_sigmoid_lut(
    manifest: dict, blob: bytes
) -> tuple[bytes, dict, dict[int, str]]:
    """Build all resident tables in the frozen PE table_select order."""
    summary, frozen_flattened = load_frozen_pe_lut_contract()
    discovered = sorted(
        name
        for name, operator in manifest["operators"].items()
        if "sigmoid_lut" in operator.get("tensors", {})
    )
    if discovered != SIGMOID_TABLE_OPERATOR_ORDER:
        raise ValueError(
            "manifest sigmoid operator order does not match frozen PE table_select"
        )

    payload = bytearray()
    tables = []
    stage_lut_sha_by_id: dict[int, str] = {}
    for table_select, operator_name in enumerate(SIGMOID_TABLE_OPERATOR_ORDER):
        tensor = manifest["operators"][operator_name]["tensors"]["sigmoid_lut"]
        if (
            tensor.get("dtype") != "uint8"
            or tensor.get("shape") != [GLOBAL_LUT_ENTRIES_PER_TABLE]
            or int(tensor.get("nbytes", -1)) != GLOBAL_LUT_ENTRIES_PER_TABLE
        ):
            raise ValueError(f"unexpected sigmoid LUT metadata for {operator_name}")
        table_payload = v3.tensor_bytes(blob, tensor, "sigmoid_lut")
        table_sha = sha256(table_payload)
        reference_table = summary["tables"][table_select]
        if reference_table["operator"] != operator_name:
            raise ValueError("frozen PE sigmoid operator/table index mismatch")
        if reference_table["sha256"] != table_sha:
            raise ValueError(
                f"{operator_name} sigmoid LUT differs from frozen PE table_select "
                f"{table_select}"
            )
        frozen_start = table_select * GLOBAL_LUT_ENTRIES_PER_TABLE
        frozen_end = frozen_start + GLOBAL_LUT_ENTRIES_PER_TABLE
        if table_payload != frozen_flattened[frozen_start:frozen_end]:
            raise ValueError(
                f"{operator_name} sigmoid bytes differ from frozen PE vector"
            )

        stage_id = OPERATOR_EXECUTION_ORDER.index(operator_name)
        local_offset = len(payload)
        payload.extend(table_payload)
        stage_lut_sha_by_id[stage_id] = table_sha
        tables.append(
            {
                "table_select": table_select,
                "operator": operator_name,
                "source_stage_id": stage_id,
                "local_byte_offset": local_offset,
                "payload_bytes": len(table_payload),
                "entries": GLOBAL_LUT_ENTRIES_PER_TABLE,
                "sha256": table_sha,
            }
        )

    flattened = bytes(payload)
    if len(flattened) != GLOBAL_LUT_PAYLOAD_BYTES:
        raise AssertionError("global sigmoid payload is not 8 x 255 bytes")
    if sha256(flattened) != FROZEN_GLOBAL_LUT_SHA256:
        raise ValueError("global sigmoid payload does not match frozen PE order")
    if len({table["sha256"] for table in tables}) != GLOBAL_LUT_TABLE_COUNT:
        raise ValueError("the eight frozen sigmoid tables are not unique")

    metadata = {
        "alignment_bytes": SECTION_ALIGNMENT,
        "payload_bytes": len(flattened),
        "transfer_bytes": align_up(len(flattened), BUS_BYTES),
        "table_count": GLOBAL_LUT_TABLE_COUNT,
        "entries_per_table": GLOBAL_LUT_ENTRIES_PER_TABLE,
        "table_major": True,
        "physical_order": ["table_select", "entry_index"],
        "sha256": sha256(flattened),
        "verified_values": len(flattened),
        "frozen_pe_reference_summary": relative_source_path(
            FROZEN_PE_REFERENCE_SUMMARY
        ),
        "frozen_pe_reference_tables": relative_source_path(
            FROZEN_PE_REFERENCE_TABLES
        ),
        "frozen_pe_reference_tables_sha256": FROZEN_PE_REFERENCE_TABLES_SHA256,
        "tables": tables,
    }
    return flattened, metadata, stage_lut_sha_by_id


def build_stage(
    *,
    stage_id: int,
    operator_name: str,
    operator: dict,
    blob: bytes,
    expected_lut_sha: str | None,
) -> tuple[bytes, dict, dict]:
    """Reuse v3 packing, then remove only the per-stage LUT section."""
    v3_payload, stage_meta, golden = v3.build_stage(
        stage_id=stage_id,
        operator_name=operator_name,
        operator=operator,
        blob=blob,
    )
    legacy_lut = stage_meta.pop("lut")
    golden.pop("lut")

    if stage_meta["kind"] == "gsu":
        if operator_name not in SIGMOID_TABLE_SELECT_BY_OPERATOR:
            raise ValueError(f"GSU stage {operator_name} has no frozen table_select")
        if not legacy_lut["present"] or legacy_lut["sha256"] != expected_lut_sha:
            raise ValueError(f"GSU stage {operator_name} LUT/global mapping mismatch")

        parameter_end = (
            int(stage_meta["parameters"]["local_byte_offset"])
            + int(stage_meta["parameters"]["payload_bytes"])
        )
        transfer_bytes = align_up(parameter_end, BUS_BYTES)
        lut_start = int(legacy_lut["local_byte_offset"])
        if transfer_bytes > lut_start:
            raise ValueError(f"GSU stage {operator_name} LUT overlaps parameters")
        if any(v3_payload[transfer_bytes:lut_start]):
            raise ValueError(f"GSU stage {operator_name} pre-LUT padding is nonzero")
        stage_payload = v3_payload[:transfer_bytes]
        uses_sigmoid_table = True
        sigmoid_table_select: int | None = SIGMOID_TABLE_SELECT_BY_OPERATOR[
            operator_name
        ]
    else:
        if operator_name in SIGMOID_TABLE_SELECT_BY_OPERATOR:
            raise ValueError(f"projection stage {operator_name} has a sigmoid mapping")
        if legacy_lut["present"] or expected_lut_sha is not None:
            raise ValueError(f"projection stage {operator_name} unexpectedly has a LUT")
        stage_payload = v3_payload
        uses_sigmoid_table = False
        sigmoid_table_select = None

    if len(stage_payload) > CACHE_BYTES:
        raise ValueError(
            f"stage {operator_name} is {len(stage_payload)} bytes and exceeds cache"
        )
    if len(stage_payload) % BUS_BYTES:
        raise AssertionError(f"stage {operator_name} is not bus aligned")

    stage_meta.update(
        {
            "transfer_bytes": len(stage_payload),
            "bram_words": len(stage_payload) // BUS_BYTES,
            "uses_sigmoid_table": uses_sigmoid_table,
            "sigmoid_table_select": sigmoid_table_select,
            "stage_sha256": sha256(stage_payload),
        }
    )
    golden.update(
        {
            "stage_sha256": stage_meta["stage_sha256"],
            "uses_sigmoid_table": uses_sigmoid_table,
            "sigmoid_table_select": sigmoid_table_select,
        }
    )
    return stage_payload, stage_meta, golden


def build_weight_readback_vectors(image: bytes, layout: dict) -> list[dict]:
    return v3.build_weight_readback_vectors(image, layout)


def build_image(manifest_path: Path) -> tuple[bytes, dict, dict]:
    manifest_payload = manifest_path.read_bytes()
    manifest = json.loads(manifest_payload)
    blob_path = manifest_path.parent / manifest["storage"]["file"]
    blob = blob_path.read_bytes()
    v3.validate_manifest(manifest, blob)

    manifest_sha = sha256(manifest_payload)
    global_payload, global_meta, stage_lut_sha_by_id = build_global_sigmoid_lut(
        manifest, blob
    )

    image = bytearray(image_header(manifest_sha, len(OPERATOR_EXECUTION_ORDER)))
    global_start = align_up(len(image), SECTION_ALIGNMENT)
    image.extend(bytes(global_start - len(image)))
    image.extend(global_payload)
    global_transfer_bytes = int(global_meta["transfer_bytes"])
    image.extend(bytes(global_transfer_bytes - len(global_payload)))
    global_meta["dram_byte_offset"] = global_start
    global_meta["dram_word_offset"] = global_start // BUS_BYTES
    for table in global_meta["tables"]:
        table["dram_byte_offset"] = global_start + int(table["local_byte_offset"])

    stages = []
    golden_stages = []
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
        "weight_physical_order": [
            "operator",
            "matrix",
            "source_index",
            "row_tile",
            "lane",
        ],
        "global_sigmoid_lut": global_meta,
        "parameter_abi": {
            "gsu_response_bits": GSU_PARAM_RESPONSE_BITS,
            "gsu_record_bytes": GSU_PARAM_RECORD_BYTES,
            "projection_response_bits": PROJECTION_PARAM_RESPONSE_BITS,
            "projection_record_bytes": PROJECTION_PARAM_RECORD_BYTES,
            "lane_zero_is_lowest_bits": True,
            "record_byte_order": "little-endian",
        },
        "canonical_generator_command": (
            "python3 rtl/tools/generate_memory_v4.py "
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
    global_golden = {
        "sha256": global_meta["sha256"],
        "verified_values": global_meta["verified_values"],
        "table_count": global_meta["table_count"],
        "entries_per_table": global_meta["entries_per_table"],
        "table_major": True,
        "frozen_pe_table_select_order_verified": True,
        "tables": [
            {
                "table_select": table["table_select"],
                "operator": table["operator"],
                "source_stage_id": table["source_stage_id"],
                "sha256": table["sha256"],
                "verified_values": table["entries"],
            }
            for table in global_meta["tables"]
        ],
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
    global_lut = layout["global_sigmoid_lut"]
    lines = [
        "// Generated by rtl/tools/generate_memory_v4.py; do not edit.",
        "`ifndef MODEL_MEMORY_V4_MAP_VH",
        "`define MODEL_MEMORY_V4_MAP_VH",
        "",
        f"`define MODEL_V4_IMAGE_VERSION 32'd{FORMAT_VERSION}",
        f"`define MODEL_V4_STAGE_COUNT {layout['stage_count']}",
        f"`define MODEL_V4_IMAGE_BYTES 32'd{layout['image_bytes']}",
        f"`define MODEL_V4_MAX_STAGE_BYTES 32'd{layout['maximum_stage_bytes']}",
        f"`define MODEL_V4_CACHE_BYTES 32'd{CACHE_BYTES}",
        f"`define MODEL_V4_LANES {LANES}",
        f"`define MODEL_V4_GSU_PARAM_BITS {GSU_PARAM_RESPONSE_BITS}",
        f"`define MODEL_V4_PROJECTION_PARAM_BITS {PROJECTION_PARAM_RESPONSE_BITS}",
        f"`define MODEL_V4_WEIGHT_READBACK_COUNT {len(WEIGHT_READBACK_REQUESTS)}",
        f"`define MODEL_V4_STAGE_KIND_GSU 1'b{STAGE_KIND_GSU}",
        f"`define MODEL_V4_STAGE_KIND_PROJECTION 1'b{STAGE_KIND_PROJECTION}",
        "",
        "// One image-global, table-major sigmoid section.",
        f"`define MODEL_V4_GLOBAL_SIGMOID_LUT_DRAM_OFFSET 32'd{global_lut['dram_byte_offset']}",
        f"`define MODEL_V4_GLOBAL_SIGMOID_LUT_WORD_OFFSET 32'd{global_lut['dram_word_offset']}",
        f"`define MODEL_V4_GLOBAL_SIGMOID_LUT_PAYLOAD_BYTES 32'd{global_lut['payload_bytes']}",
        f"`define MODEL_V4_GLOBAL_SIGMOID_LUT_TRANSFER_BYTES 32'd{global_lut['transfer_bytes']}",
        f"`define MODEL_V4_GLOBAL_SIGMOID_LUT_TABLE_COUNT 4'd{global_lut['table_count']}",
        f"`define MODEL_V4_GLOBAL_SIGMOID_LUT_ENTRIES_PER_TABLE 9'd{global_lut['entries_per_table']}",
        "",
    ]

    for stage in layout["stages"]:
        prefix = f"MODEL_V4_STAGE_{stage['id']}"
        table_select = stage["sigmoid_table_select"]
        encoded_select = 0 if table_select is None else table_select
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
                f"`define {prefix}_USES_SIGMOID_TABLE 1'b{int(stage['uses_sigmoid_table'])}",
                f"`define {prefix}_SIGMOID_TABLE_SELECT 3'd{encoded_select}",
                "",
            ]
        )

    for abi_name, fields in (
        ("GSU", layout["stages"][0]["parameters"]["fields"]),
        ("PROJECTION", layout["stages"][2]["parameters"]["fields"]),
    ):
        lines.append(f"// {abi_name} parameter response field offsets.")
        for field in fields:
            prefix = macro_name("MODEL_V4", abi_name, "PARAM", field["name"])
            lines.append(f"`define {prefix}_LSB {field['lsb']}")
            lines.append(f"`define {prefix}_BITS {field['bits']}")
        lines.append("")

    lines.append("`endif")
    return "\n".join(lines) + "\n"


def emit_table(layout: dict) -> str:
    lines = [
        "`timescale 1ns/1ps",
        "`include \"memory/model_memory_v4_map.vh\"",
        "",
        "// Generated combinational stage table for the v4 parameter image.",
        "module model_memory_v4_table (",
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
        "    output reg         uses_sigmoid_table,",
        "    output reg  [2:0]  sigmoid_table_select",
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
        "        uses_sigmoid_table = 1'b0;",
        "        sigmoid_table_select = 3'd0;",
        "        case (stage_id)",
    ]
    for stage in layout["stages"]:
        matrices = stage["matrices"]
        matrix0 = matrices[0]
        matrix1 = matrices[1] if len(matrices) > 1 else None
        encoded_select = stage["sigmoid_table_select"] or 0
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
                f"                uses_sigmoid_table = 1'b{int(stage['uses_sigmoid_table'])};",
                f"                sigmoid_table_select = 3'd{encoded_select};",
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
    vectors = golden["weight_readback_vectors"]["vectors"]
    lines = [
        "`timescale 1ns/1ps",
        "",
        "// Generated by rtl/tools/generate_memory_v4.py; do not edit.",
        "module model_memory_v4_readback_table (",
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


def checksum_manifest(files: list[Path], base_directories: list[Path]) -> bytes:
    return v3.checksum_manifest(files, base_directories)


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
    image_path = output_dir / "parameters_v4.bin"
    layout_path = output_dir / "memory_layout_v4.json"
    golden_path = output_dir / "memory_golden_v4.json"
    checksum_path = output_dir / "parameters_v4.sha256"

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
        default=Path("outputs/memory/2026-09-03/v4"),
    )
    parser.add_argument(
        "--output-vh",
        type=Path,
        default=Path("rtl/memory/model_memory_v4_map.vh"),
    )
    parser.add_argument(
        "--output-table",
        type=Path,
        default=Path("rtl/memory/model_memory_v4_table.v"),
    )
    parser.add_argument(
        "--output-readback-table",
        type=Path,
        default=Path("rtl/memory/model_memory_v4_readback_table.v"),
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
