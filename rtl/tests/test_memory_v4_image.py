import hashlib
import json
from pathlib import Path
import re
import struct
from tempfile import TemporaryDirectory

from rtl.tools import generate_memory_v3 as v3
from rtl.tools.generate_memory_v4 import (
    BUS_BYTES,
    CACHE_BYTES,
    FORMAT_VERSION,
    GLOBAL_LUT_ENTRIES_PER_TABLE,
    GLOBAL_LUT_PAYLOAD_BYTES,
    GLOBAL_LUT_TABLE_COUNT,
    IMAGE_HEADER_BYTES,
    IMAGE_MAGIC,
    LANES,
    OPERATOR_EXECUTION_ORDER,
    ROOT,
    SECTION_ALIGNMENT,
    STAGE_ALIGNMENT,
    build_image,
    emit_header,
    emit_readback_table,
    emit_table,
    write_artifacts,
)


MANIFEST_PATH = ROOT / "upstream" / "parameters" / "manifest.json"
BLOB_PATH = ROOT / "upstream" / "parameters" / "parameters.bin"
V3_SNAPSHOT_ROOT = ROOT / "outputs" / "memory" / "2026-09-01" / "v3"
V4_SNAPSHOT_ROOT = ROOT / "outputs" / "memory" / "2026-09-03" / "v4"

V4_HEADER_PATH = ROOT / "rtl" / "memory" / "model_memory_v4_map.vh"
V4_TABLE_PATH = ROOT / "rtl" / "memory" / "model_memory_v4_table.v"
V4_READBACK_TABLE_PATH = (
    ROOT / "rtl" / "memory" / "model_memory_v4_readback_table.v"
)

FROZEN_PE_ROOT = ROOT / "rtl" / "pe_array" / "baseline" / "v1"
FROZEN_PE_SUMMARY_PATH = (
    FROZEN_PE_ROOT
    / "reports"
    / "pe_sigmoid_lut_255"
    / "reference_summary.json"
)
FROZEN_PE_TABLES_PATH = (
    FROZEN_PE_ROOT / "tb" / "vectors" / "pe_sigmoid_lut_255_tables.hex"
)


# These values are independent checkpoint oracles, not values imported from
# either generator.  They make accidental coordinated changes to source data,
# v3 artifacts, layout metadata, and v4 artifacts observable.
EXPECTED_RAW_MANIFEST_SHA256 = (
    "eb79e506e0abf820dc79a3ca5d4f1f2312d0e94a47040f14fb47e88fcb87bf78"
)
EXPECTED_RAW_BLOB_BYTES = 2_193_288
EXPECTED_RAW_BLOB_SHA256 = (
    "572da396d01fbc20a9ed23f17fbbb0c29e3539fe9f7c3c9eb8c1c2c82f22f894"
)

EXPECTED_V3_PROTECTED_SHA256 = {
    ROOT / "rtl" / "tools" / "generate_memory_v3.py": (
        "dd1edb2b89e260946b91ebe3b633773d8c1231acd1e1d6e355e0e8c741396d8c"
    ),
    ROOT / "rtl" / "tests" / "test_memory_v3_image.py": (
        "69069b8c3ce2795e18607c1f63282c9de6640a1a04714bdfe786b5912a12d28b"
    ),
    V3_SNAPSHOT_ROOT / "parameters_v3.bin": (
        "2e1f102b9c83cddbbc135a8218938c666d526aaa0db66699f89a8c5a79054f69"
    ),
    V3_SNAPSHOT_ROOT / "memory_layout_v3.json": (
        "c8764737fcc6812b4575eb59f10650606a146885ff75a4e17a13206c75eb75e6"
    ),
    V3_SNAPSHOT_ROOT / "memory_golden_v3.json": (
        "0f9c22dd0edbec07b33a048b99c780da48f5122057a322c049f3495becc71bc1"
    ),
    V3_SNAPSHOT_ROOT / "parameters_v3.sha256": (
        "f406cf7c042f7528af05183096d33d89ce97218ef662268041ff30789467d800"
    ),
    ROOT / "rtl" / "memory" / "model_memory_v3_map.vh": (
        "dfe0fbbfba71fa0d4180275ee1fb43691bc02f3fde5f76111a9407e82773dae0"
    ),
    ROOT / "rtl" / "memory" / "model_memory_v3_table.v": (
        "7bc856c13f6e7d8a1f7e0d6baf45c657d6762e4d8ce39b13e4e38f4c5191b4f0"
    ),
    ROOT / "rtl" / "memory" / "model_memory_v3_readback_table.v": (
        "5a8439f7bff994a1864f8432d7cdd36c982743473c9fbef53780041b0c789639"
    ),
}

EXPECTED_FROZEN_PE_SUMMARY_SHA256 = (
    "8d7a2d1db694387bc72c3531164ff553a375d9fad560d5686e8123e6e42f6afc"
)
EXPECTED_FROZEN_PE_TABLES_FILE_SHA256 = (
    "0ed091b0b4e1beee8ce7a48efaf5cbea642b735c2f19590ff4c5652458e70f56"
)
EXPECTED_GLOBAL_LUT_SHA256 = (
    "af70843be21e720cedb6f627b02b69ef69a2519912c5bf900d9147f70b602c21"
)

EXPECTED_TABLES = (
    (
        0,
        0,
        "fb_model.sequence_model.layers.0.cell",
        "2642b25d4ce6b8e712c37cf85b809d1277667ad2ac4a36d9afb3d2589366a2dd",
    ),
    (
        1,
        1,
        "fb_model.sequence_model.layers.1.cell",
        "b28cdd61312d3015de981bff10b4b6a1b7e1bfb677e28bd9292889b097ba2aa2",
    ),
    (
        2,
        3,
        "sb_model.sb_models.0.sequence_model.layers.0.cell",
        "2511187a1368410bc3379f9fc0dfbafca66c79819dda90c8b761855539126e6b",
    ),
    (
        3,
        4,
        "sb_model.sb_models.0.sequence_model.layers.1.cell",
        "63f7c47772ea88096238bf2dbe62d7d001502cd844934adeb3705125f303213d",
    ),
    (
        4,
        6,
        "sb_model.sb_models.1.sequence_model.layers.0.cell",
        "1673fc09919138da6a888b48459f89c4f4c12180ae499a28271acf110e62dd83",
    ),
    (
        5,
        7,
        "sb_model.sb_models.1.sequence_model.layers.1.cell",
        "655476b7839434e947f3808022368e6d836ab31b36f1eb4e7c8f7b0bb50d9857",
    ),
    (
        6,
        9,
        "sb_model.sb_models.2.sequence_model.layers.0.cell",
        "e5c12663c564ebe06b62db70b6cb795d1ea8fea643127d955a098930b9513bff",
    ),
    (
        7,
        10,
        "sb_model.sb_models.2.sequence_model.layers.1.cell",
        "8c6682a635b7197521ff0b973c9a95a7bc6fa8807ddb1a1de1e6a787721508d0",
    ),
)

EXPECTED_IMAGE_BYTES = 1_053_056
EXPECTED_IMAGE_SHA256 = (
    "e4f1f5cd78007a47c8ecfc137f2f0e8117aa2af162bd7050913bf1867cf2cf34"
)
EXPECTED_GLOBAL_LUT_OFFSET = 64
EXPECTED_STAGE_OFFSETS = (
    2_112,
    139_584,
    358_976,
    380_032,
    450_752,
    561_344,
    580_032,
    661_504,
    772_096,
    816_832,
    912_640,
    1_023_232,
)
EXPECTED_STAGE_TRANSFER_BYTES = (
    137_440,
    219_360,
    21_056,
    70_672,
    110_544,
    18_640,
    81_424,
    110_544,
    44_736,
    95_760,
    110_544,
    29_824,
)
EXPECTED_STAGE_SHA256 = (
    "2efd03cae9fd57ce5a36c4f1862bd2a85b952692744d997403866b8d36a3d78f",
    "977c09adea7c0bc2837a6e826f05c9cc817b045aef1b67ce955b81bb575246db",
    "0b959c92f195346413578b506e6f57baa0c236e46e311f5e49ba1ed0d685d6a7",
    "538b23afcfed6bb4cd1e106634f332d5ef4a74159c06af56d11a6c298aa2236c",
    "cb026c2c1b769bb6ef20fe0763c9405ce3c9e88bf66cfce32eae569b4ebd5848",
    "3ee7b49fe483942a80931a9c7c2ef08c71812b5c0625002c5bf6da16af9d2a20",
    "38262986215328d28b493654c3b0322dc36b2ffc7b0ab06d36d3aefd2823ee82",
    "9f4d8d23ff0bde5d53d1129fee653fe24042816fc02d5ee80db03e9e1da7f139",
    "bafefa7943c78aef54e52aa50ca1b69061bd27140f62c7f31b34f52842070fe0",
    "5616716352223fa09644f187b7bf4747311a36645d8fe51ccb268ddea95fb4b5",
    "e9edc4d9370530ce219a44ae011d48ef4522a95daf3ed52e936581ac6b80221a",
    "a9b03415d5f00ddd4732982c7da6b36abd5de7efa1eee5538f678851dbf5ad13",
)

PROJECTION_STAGE_IDS = {2, 5, 8, 11}


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def signed_value(encoded: int, width: int) -> int:
    sign = 1 << (width - 1)
    return encoded - (1 << width) if encoded & sign else encoded


def stage_section(image: bytes, stage: dict, section: dict) -> bytes:
    start = int(stage["dram_byte_offset"]) + int(section["local_byte_offset"])
    return image[start : start + int(section["payload_bytes"])]


def assert_zero(payload: bytes) -> None:
    assert payload == bytes(len(payload))


def parse_verilog_literal(token: str) -> int:
    match = re.fullmatch(r"(?:(\d+)'([bBdDhH]))?([0-9a-fA-F_]+)", token)
    assert match is not None, f"unsupported Verilog literal: {token}"
    base_code = (match.group(2) or "d").lower()
    base = {"b": 2, "d": 10, "h": 16}[base_code]
    return int(match.group(3).replace("_", ""), base)


def parse_assignments(source: str) -> dict[str, int]:
    assignments = {}
    for name, literal in re.findall(
        r"^\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*"
        r"((?:\d+'[bBdDhH])?[0-9a-fA-F_]+)\s*;",
        source,
        flags=re.MULTILINE,
    ):
        assignments[name] = parse_verilog_literal(literal)
    return assignments


def parse_stage_table(source: str) -> tuple[dict[str, int], dict[int, dict[str, int]]]:
    before_case, separator, _ = source.partition("case (stage_id)")
    assert separator
    defaults = parse_assignments(before_case)
    cases = {}
    for stage_text, body in re.findall(
        r"^\s*4'd(\d+):\s*begin\s*$"
        r"(.*?)"
        r"^\s*end\s*$",
        source,
        flags=re.MULTILINE | re.DOTALL,
    ):
        stage_id = int(stage_text)
        assert stage_id not in cases
        cases[stage_id] = parse_assignments(body)
    return defaults, cases


def test_raw_inputs_and_every_v3_artifact_are_frozen():
    manifest_payload = MANIFEST_PATH.read_bytes()
    blob = BLOB_PATH.read_bytes()

    assert sha256(manifest_payload) == EXPECTED_RAW_MANIFEST_SHA256
    assert len(blob) == EXPECTED_RAW_BLOB_BYTES
    assert sha256(blob) == EXPECTED_RAW_BLOB_SHA256

    manifest = json.loads(manifest_payload)
    assert manifest["storage"]["nbytes"] == EXPECTED_RAW_BLOB_BYTES
    assert manifest["storage"]["sha256"] == EXPECTED_RAW_BLOB_SHA256

    for path, expected_digest in EXPECTED_V3_PROTECTED_SHA256.items():
        assert sha256(path.read_bytes()) == expected_digest, path


def test_v4_snapshot_is_deterministic_and_complete():
    first_image, first_layout, first_golden = build_image(MANIFEST_PATH)
    second_image, second_layout, second_golden = build_image(MANIFEST_PATH)

    assert second_image == first_image
    assert second_layout == first_layout
    assert second_golden == first_golden

    expected_files = {
        "parameters_v4.bin": V4_SNAPSHOT_ROOT / "parameters_v4.bin",
        "memory_layout_v4.json": V4_SNAPSHOT_ROOT / "memory_layout_v4.json",
        "memory_golden_v4.json": V4_SNAPSHOT_ROOT / "memory_golden_v4.json",
        "model_memory_v4_map.vh": V4_HEADER_PATH,
        "model_memory_v4_table.v": V4_TABLE_PATH,
        "model_memory_v4_readback_table.v": V4_READBACK_TABLE_PATH,
        "parameters_v4.sha256": V4_SNAPSHOT_ROOT / "parameters_v4.sha256",
    }

    assert first_image == expected_files["parameters_v4.bin"].read_bytes()
    assert first_layout == load_json(expected_files["memory_layout_v4.json"])
    assert first_golden == load_json(expected_files["memory_golden_v4.json"])
    assert emit_header(first_layout) == V4_HEADER_PATH.read_text(encoding="utf-8")
    assert emit_table(first_layout) == V4_TABLE_PATH.read_text(encoding="utf-8")
    assert emit_readback_table(first_golden) == V4_READBACK_TABLE_PATH.read_text(
        encoding="utf-8"
    )

    with TemporaryDirectory() as directory:
        temporary = Path(directory)
        output_dir = temporary / "v4"
        output_vh = temporary / "rtl" / "model_memory_v4_map.vh"
        output_table = temporary / "rtl" / "model_memory_v4_table.v"
        output_readback = temporary / "rtl" / "model_memory_v4_readback_table.v"
        paths = write_artifacts(
            image=first_image,
            layout=first_layout,
            golden=first_golden,
            output_dir=output_dir,
            output_vh=output_vh,
            output_table=output_table,
            output_readback_table=output_readback,
        )

        assert {path.name for path in paths} == set(expected_files)
        for path in paths:
            assert path.read_bytes() == expected_files[path.name].read_bytes(), path

        checksum_lines = (output_dir / "parameters_v4.sha256").read_text(
            encoding="ascii"
        ).splitlines()
        assert len(checksum_lines) == len(paths) - 1
        listed = {}
        for line in checksum_lines:
            digest, name = line.split("  ", 1)
            assert name not in listed
            listed[name] = digest
        assert set(listed) == {path.name for path in paths if path.suffix != ".sha256"}
        for path in paths:
            if path.suffix != ".sha256":
                assert listed[path.name] == sha256(path.read_bytes())


def test_every_v4_weight_lane_and_readback_vector_matches_v3():
    v3_image = (V3_SNAPSHOT_ROOT / "parameters_v3.bin").read_bytes()
    v3_layout = load_json(V3_SNAPSHOT_ROOT / "memory_layout_v3.json")
    v3_golden = load_json(V3_SNAPSHOT_ROOT / "memory_golden_v3.json")
    v4_image = (V4_SNAPSHOT_ROOT / "parameters_v4.bin").read_bytes()
    v4_layout = load_json(V4_SNAPSHOT_ROOT / "memory_layout_v4.json")
    v4_golden = load_json(V4_SNAPSHOT_ROOT / "memory_golden_v4.json")

    assert [stage["name"] for stage in v4_layout["stages"]] == list(
        OPERATOR_EXECUTION_ORDER
    )
    assert [stage["name"] for stage in v3_layout["stages"]] == list(
        OPERATOR_EXECUTION_ORDER
    )
    assert v4_layout["weight_physical_order"] == [
        "operator",
        "matrix",
        "source_index",
        "row_tile",
        "lane",
    ]
    assert v4_layout["weight_physical_order"] == v3_layout["weight_physical_order"]

    lane_count = 0
    for v3_stage, v4_stage in zip(v3_layout["stages"], v4_layout["stages"]):
        assert v4_stage["id"] == v3_stage["id"]
        assert v4_stage["name"] == v3_stage["name"]
        assert v4_stage["matrix_count"] == v3_stage["matrix_count"]
        assert len(v4_stage["matrices"]) == len(v3_stage["matrices"])

        for v3_matrix, v4_matrix in zip(
            v3_stage["matrices"], v4_stage["matrices"]
        ):
            assert v4_matrix == v3_matrix
            assert stage_section(v4_image, v4_stage, v4_matrix) == stage_section(
                v3_image, v3_stage, v3_matrix
            )

            for source_index in range(v4_matrix["source_count"]):
                for row_tile in range(v4_matrix["row_tiles"]):
                    for lane in range(LANES):
                        local_index = (
                            v4_matrix["local_byte_offset"]
                            + source_index * v4_matrix["source_stride_bytes"]
                            + row_tile * LANES
                            + lane
                        )
                        v3_index = v3_stage["dram_byte_offset"] + local_index
                        v4_index = v4_stage["dram_byte_offset"] + local_index
                        assert v4_image[v4_index] == v3_image[v3_index]
                        lane_count += 1

    expected_lane_count = sum(
        matrix["source_count"] * matrix["row_tiles"] * LANES
        for stage in v3_layout["stages"]
        for matrix in stage["matrices"]
    )
    assert lane_count == expected_lane_count

    v3_vectors = v3_golden["weight_readback_vectors"]["vectors"]
    v4_vectors = v4_golden["weight_readback_vectors"]["vectors"]
    assert len(v3_vectors) == len(v4_vectors) == 13
    for v3_vector, v4_vector in zip(v3_vectors, v4_vectors):
        for key in (
            "index",
            "stage",
            "matrix",
            "source",
            "row_tile",
            "tag",
            "expected_lane_bytes_hex",
            "expected_u128_le_hex",
            "expected_words_le",
        ):
            assert v4_vector[key] == v3_vector[key]
        start = v4_vector["image_byte_offset"]
        payload = v4_image[start : start + LANES]
        assert payload.hex() == v4_vector["expected_lane_bytes_hex"]


def test_every_v4_parameter_field_and_record_padding_matches_v3():
    v3_image = (V3_SNAPSHOT_ROOT / "parameters_v3.bin").read_bytes()
    v3_layout = load_json(V3_SNAPSHOT_ROOT / "memory_layout_v3.json")
    v3_golden = load_json(V3_SNAPSHOT_ROOT / "memory_golden_v3.json")
    v4_image = (V4_SNAPSHOT_ROOT / "parameters_v4.bin").read_bytes()
    v4_layout = load_json(V4_SNAPSHOT_ROOT / "memory_layout_v4.json")
    v4_golden = load_json(V4_SNAPSHOT_ROOT / "memory_golden_v4.json")

    assert v4_layout["parameter_abi"] == v3_layout["parameter_abi"]
    checked_fields = 0
    for v3_stage, v4_stage in zip(v3_layout["stages"], v4_layout["stages"]):
        v3_params = v3_stage["parameters"]
        v4_params = v4_stage["parameters"]
        assert v4_params == v3_params

        v3_payload = stage_section(v3_image, v3_stage, v3_params)
        v4_payload = stage_section(v4_image, v4_stage, v4_params)
        assert v4_payload == v3_payload
        assert sha256(v4_payload) == v4_params["packed_sha256"]

        for tile in range(v4_params["row_tiles"]):
            record_offset = tile * v4_params["record_bytes"]
            response_end = record_offset + v4_params["response_bytes"]
            record_end = record_offset + v4_params["record_bytes"]
            v3_word = int.from_bytes(v3_payload[record_offset:response_end], "little")
            v4_word = int.from_bytes(v4_payload[record_offset:response_end], "little")
            assert_zero(v3_payload[response_end:record_end])
            assert_zero(v4_payload[response_end:record_end])

            for field in v4_params["fields"]:
                mask = (1 << field["lane_width"]) - 1
                for lane in range(LANES):
                    shift = field["lsb"] + lane * field["lane_width"]
                    v3_encoded = (v3_word >> shift) & mask
                    v4_encoded = (v4_word >> shift) & mask
                    if field["signed"]:
                        assert signed_value(v4_encoded, field["lane_width"]) == signed_value(
                            v3_encoded, field["lane_width"]
                        )
                    else:
                        assert v4_encoded == v3_encoded
                    checked_fields += 1

    assert checked_fields == v3_golden["dense_reference_checks"][
        "parameter_values_verified"
    ]
    assert checked_fields == v4_golden["dense_reference_checks"][
        "parameter_values_verified"
    ]


def test_global_lut_matches_frozen_pe_table_select_and_every_v3_stage_lut():
    assert sha256(FROZEN_PE_SUMMARY_PATH.read_bytes()) == (
        EXPECTED_FROZEN_PE_SUMMARY_SHA256
    )
    assert sha256(FROZEN_PE_TABLES_PATH.read_bytes()) == (
        EXPECTED_FROZEN_PE_TABLES_FILE_SHA256
    )

    frozen_summary = load_json(FROZEN_PE_SUMMARY_PATH)
    hex_lines = FROZEN_PE_TABLES_PATH.read_text(encoding="ascii").splitlines()
    assert len(hex_lines) == GLOBAL_LUT_PAYLOAD_BYTES
    assert all(re.fullmatch(r"[0-9a-f]{2}", line) for line in hex_lines)
    frozen_payload = bytes(int(line, 16) for line in hex_lines)
    assert sha256(frozen_payload) == EXPECTED_GLOBAL_LUT_SHA256

    v3_image = (V3_SNAPSHOT_ROOT / "parameters_v3.bin").read_bytes()
    v3_layout = load_json(V3_SNAPSHOT_ROOT / "memory_layout_v3.json")
    v4_image = (V4_SNAPSHOT_ROOT / "parameters_v4.bin").read_bytes()
    v4_layout = load_json(V4_SNAPSHOT_ROOT / "memory_layout_v4.json")
    v4_golden = load_json(V4_SNAPSHOT_ROOT / "memory_golden_v4.json")
    global_lut = v4_layout["global_sigmoid_lut"]

    assert frozen_summary["table_count"] == GLOBAL_LUT_TABLE_COUNT == 8
    assert frozen_summary["entries_per_table"] == GLOBAL_LUT_ENTRIES_PER_TABLE == 255
    assert frozen_summary["total_entries"] == GLOBAL_LUT_PAYLOAD_BYTES == 2_040
    assert global_lut["table_count"] == GLOBAL_LUT_TABLE_COUNT
    assert global_lut["entries_per_table"] == GLOBAL_LUT_ENTRIES_PER_TABLE
    assert global_lut["payload_bytes"] == GLOBAL_LUT_PAYLOAD_BYTES
    assert global_lut["table_major"] is True
    assert global_lut["physical_order"] == ["table_select", "entry_index"]
    assert global_lut["sha256"] == EXPECTED_GLOBAL_LUT_SHA256

    global_start = global_lut["dram_byte_offset"]
    global_payload = v4_image[global_start : global_start + GLOBAL_LUT_PAYLOAD_BYTES]
    assert global_payload == frozen_payload

    assert len(frozen_summary["tables"]) == len(global_lut["tables"]) == 8
    expected_gsu_stage_ids = set()
    for table_select, stage_id, operator_name, table_sha in EXPECTED_TABLES:
        expected_gsu_stage_ids.add(stage_id)
        frozen_table_meta = frozen_summary["tables"][table_select]
        layout_table_meta = global_lut["tables"][table_select]
        start = table_select * GLOBAL_LUT_ENTRIES_PER_TABLE
        end = start + GLOBAL_LUT_ENTRIES_PER_TABLE
        table_payload = global_payload[start:end]

        assert frozen_table_meta["table_index"] == table_select
        assert frozen_table_meta["operator"] == operator_name
        assert frozen_table_meta["sha256"] == table_sha
        assert layout_table_meta == {
            "table_select": table_select,
            "operator": operator_name,
            "source_stage_id": stage_id,
            "local_byte_offset": start,
            "payload_bytes": GLOBAL_LUT_ENTRIES_PER_TABLE,
            "entries": GLOBAL_LUT_ENTRIES_PER_TABLE,
            "sha256": table_sha,
            "dram_byte_offset": global_start + start,
        }
        assert sha256(table_payload) == table_sha

        v3_stage = v3_layout["stages"][stage_id]
        v4_stage = v4_layout["stages"][stage_id]
        assert v3_stage["name"] == v4_stage["name"] == operator_name
        assert v3_stage["lut"]["present"] is True
        assert v3_stage["lut"]["sha256"] == table_sha
        assert table_payload == stage_section(v3_image, v3_stage, v3_stage["lut"])
        assert "lut" not in v4_stage
        assert v4_stage["uses_sigmoid_table"] is True
        assert v4_stage["sigmoid_table_select"] == table_select

    assert expected_gsu_stage_ids == set(range(12)) - PROJECTION_STAGE_IDS
    for stage in v4_layout["stages"]:
        assert "lut" not in stage
        if stage["id"] in PROJECTION_STAGE_IDS:
            assert stage["kind"] == "projection"
            assert stage["uses_sigmoid_table"] is False
            assert stage["sigmoid_table_select"] is None
        else:
            assert stage["kind"] == "gsu"
            assert stage["uses_sigmoid_table"] is True
            assert isinstance(stage["sigmoid_table_select"], int)

    global_golden = v4_golden["global_sigmoid_lut"]
    assert global_golden["sha256"] == global_lut["sha256"]
    assert global_golden["verified_values"] == GLOBAL_LUT_PAYLOAD_BYTES
    assert global_golden["table_count"] == GLOBAL_LUT_TABLE_COUNT
    assert global_golden["entries_per_table"] == GLOBAL_LUT_ENTRIES_PER_TABLE
    assert global_golden["table_major"] is True
    assert global_golden["frozen_pe_table_select_order_verified"] is True
    assert [
        (
            table["table_select"],
            table["source_stage_id"],
            table["operator"],
            table["sha256"],
        )
        for table in global_golden["tables"]
    ] == list(EXPECTED_TABLES)


def test_v4_geometry_alignment_padding_size_and_all_hashes_are_exact():
    image = (V4_SNAPSHOT_ROOT / "parameters_v4.bin").read_bytes()
    layout = load_json(V4_SNAPSHOT_ROOT / "memory_layout_v4.json")
    golden = load_json(V4_SNAPSHOT_ROOT / "memory_golden_v4.json")

    assert layout["format_version"] == FORMAT_VERSION == 4
    assert layout["image_header_bytes"] == IMAGE_HEADER_BYTES == 64
    assert layout["image_bytes"] == len(image) == EXPECTED_IMAGE_BYTES
    assert layout["image_sha256"] == sha256(image) == EXPECTED_IMAGE_SHA256
    assert golden["image_sha256"] == EXPECTED_IMAGE_SHA256
    assert layout["source_manifest_sha256"] == EXPECTED_RAW_MANIFEST_SHA256
    assert layout["source_blob_bytes"] == EXPECTED_RAW_BLOB_BYTES
    assert layout["source_blob_sha256"] == EXPECTED_RAW_BLOB_SHA256
    assert golden["source_manifest_sha256"] == EXPECTED_RAW_MANIFEST_SHA256
    assert golden["source_blob_sha256"] == EXPECTED_RAW_BLOB_SHA256
    assert layout["stage_count"] == len(OPERATOR_EXECUTION_ORDER) == 12
    assert layout["maximum_stage_bytes"] == max(EXPECTED_STAGE_TRANSFER_BYTES)
    assert layout["maximum_stage_bytes"] <= CACHE_BYTES

    magic, version, stages, lanes, bus_bytes, stage_alignment, reserved = struct.unpack(
        "<8sIIIIII", image[:32]
    )
    assert magic == IMAGE_MAGIC == b"ZEPHYR4\0"
    assert version == FORMAT_VERSION
    assert stages == 12
    assert lanes == LANES == 16
    assert bus_bytes == BUS_BYTES == 8
    assert stage_alignment == STAGE_ALIGNMENT == 64
    assert reserved == 0
    assert image[32:IMAGE_HEADER_BYTES].hex() == EXPECTED_RAW_MANIFEST_SHA256

    global_lut = layout["global_sigmoid_lut"]
    assert global_lut["dram_byte_offset"] == EXPECTED_GLOBAL_LUT_OFFSET
    assert global_lut["dram_word_offset"] == EXPECTED_GLOBAL_LUT_OFFSET // BUS_BYTES
    assert global_lut["alignment_bytes"] == SECTION_ALIGNMENT == 64
    assert global_lut["dram_byte_offset"] % SECTION_ALIGNMENT == 0
    assert global_lut["payload_bytes"] == GLOBAL_LUT_PAYLOAD_BYTES == 2_040
    assert global_lut["transfer_bytes"] == GLOBAL_LUT_PAYLOAD_BYTES
    assert global_lut["transfer_bytes"] % BUS_BYTES == 0
    global_start = global_lut["dram_byte_offset"]
    global_payload_end = global_start + global_lut["payload_bytes"]
    global_transfer_end = global_start + global_lut["transfer_bytes"]
    assert sha256(image[global_start:global_payload_end]) == EXPECTED_GLOBAL_LUT_SHA256
    assert_zero(image[IMAGE_HEADER_BYTES:global_start])
    assert_zero(image[global_payload_end:global_transfer_end])

    assert tuple(stage["dram_byte_offset"] for stage in layout["stages"]) == (
        EXPECTED_STAGE_OFFSETS
    )
    assert tuple(stage["transfer_bytes"] for stage in layout["stages"]) == (
        EXPECTED_STAGE_TRANSFER_BYTES
    )
    assert tuple(stage["stage_sha256"] for stage in layout["stages"]) == (
        EXPECTED_STAGE_SHA256
    )

    cursor = global_transfer_end
    for stage, expected_sha in zip(layout["stages"], EXPECTED_STAGE_SHA256):
        stage_start = stage["dram_byte_offset"]
        stage_end = stage_start + stage["transfer_bytes"]
        assert stage_start % STAGE_ALIGNMENT == 0
        assert stage["transfer_bytes"] % BUS_BYTES == 0
        assert stage["bram_words"] == stage["transfer_bytes"] // BUS_BYTES
        assert stage["transfer_bytes"] <= CACHE_BYTES
        assert stage_start >= cursor
        assert_zero(image[cursor:stage_start])

        local_cursor = 0
        for section in [*stage["matrices"], stage["parameters"]]:
            section_start = int(section["local_byte_offset"])
            section_end = section_start + int(section["payload_bytes"])
            assert section_start % SECTION_ALIGNMENT == 0
            assert section_start >= local_cursor
            assert_zero(
                image[
                    stage_start + local_cursor : stage_start + section_start
                ]
            )
            payload = image[stage_start + section_start : stage_start + section_end]
            assert sha256(payload) == section["packed_sha256"]
            local_cursor = section_end

        expected_transfer = v3.align_up(local_cursor, BUS_BYTES)
        assert stage["transfer_bytes"] == expected_transfer
        assert_zero(image[stage_start + local_cursor : stage_end])
        assert sha256(image[stage_start:stage_end]) == stage["stage_sha256"]
        assert stage["stage_sha256"] == expected_sha
        cursor = stage_end

    assert cursor == len(image)

    checks = golden["dense_reference_checks"]
    assert checks["all_matrix_values_compared"] is True
    assert checks["all_shared_gate_duplicate_values_compared"] is True
    assert checks["all_parameter_values_range_checked_and_repacked"] is True
    assert checks["all_final_tile_padding_lanes_zero"] is True
    assert checks["all_record_padding_bytes_zero"] is True
    assert checks["all_global_lut_values_compared_to_source"] is True
    assert checks["all_global_lut_values_compared_to_frozen_pe_reference"] is True
    assert checks["all_per_stage_lut_payloads_removed"] is True
    assert checks["lut_values_verified"] == GLOBAL_LUT_PAYLOAD_BYTES

    assert len(golden["stages"]) == len(layout["stages"])
    for layout_stage, golden_stage in zip(layout["stages"], golden["stages"]):
        assert golden_stage["id"] == layout_stage["id"]
        assert golden_stage["name"] == layout_stage["name"]
        assert golden_stage["kind"] == layout_stage["kind"]
        assert golden_stage["stage_sha256"] == layout_stage["stage_sha256"]
        assert golden_stage["uses_sigmoid_table"] == layout_stage[
            "uses_sigmoid_table"
        ]
        assert golden_stage["sigmoid_table_select"] == layout_stage[
            "sigmoid_table_select"
        ]


def test_generated_v4_rtl_stage_table_matches_layout_json_field_for_field():
    layout = load_json(V4_SNAPSHOT_ROOT / "memory_layout_v4.json")
    table_text = V4_TABLE_PATH.read_text(encoding="utf-8")
    defaults, cases = parse_stage_table(table_text)

    exported_fields = {
        "stage_valid",
        "stage_kind",
        "dram_byte_offset",
        "transfer_bytes",
        "matrix_count",
        "matrix0_word_offset",
        "matrix0_sources",
        "matrix0_row_tiles",
        "matrix1_word_offset",
        "matrix1_sources",
        "matrix1_row_tiles",
        "param_word_offset",
        "param_record_words",
        "param_response_bits",
        "param_tiles",
        "uses_sigmoid_table",
        "sigmoid_table_select",
    }
    assert exported_fields <= defaults.keys()
    assert all(defaults[field] == 0 for field in exported_fields)
    assert set(cases) == set(range(12))
    assert "has_lut" not in table_text
    assert "lut_word_offset" not in table_text
    assert "lut_bytes" not in table_text

    for stage in layout["stages"]:
        case_assignments = cases[stage["id"]]
        # Both fields are explicit even for projections; the select value is
        # ignored only when uses_sigmoid_table is zero.
        assert "uses_sigmoid_table" in case_assignments
        assert "sigmoid_table_select" in case_assignments
        actual = dict(defaults)
        actual.update(case_assignments)

        matrix0 = stage["matrices"][0]
        matrix1 = stage["matrices"][1] if len(stage["matrices"]) == 2 else None
        expected = {
            "stage_valid": 1,
            "stage_kind": stage["kind_id"],
            "dram_byte_offset": stage["dram_byte_offset"],
            "transfer_bytes": stage["transfer_bytes"],
            "matrix_count": len(stage["matrices"]),
            "matrix0_word_offset": matrix0["local_word_offset"],
            "matrix0_sources": matrix0["source_count"],
            "matrix0_row_tiles": matrix0["row_tiles"],
            "matrix1_word_offset": 0 if matrix1 is None else matrix1["local_word_offset"],
            "matrix1_sources": 0 if matrix1 is None else matrix1["source_count"],
            "matrix1_row_tiles": 0 if matrix1 is None else matrix1["row_tiles"],
            "param_word_offset": stage["parameters"]["local_word_offset"],
            "param_record_words": stage["parameters"]["record_words"],
            "param_response_bits": stage["parameters"]["response_bits"],
            "param_tiles": stage["parameters"]["row_tiles"],
            "uses_sigmoid_table": int(stage["uses_sigmoid_table"]),
            "sigmoid_table_select": (
                0
                if stage["sigmoid_table_select"] is None
                else stage["sigmoid_table_select"]
            ),
        }
        assert {field: actual[field] for field in exported_fields} == expected
