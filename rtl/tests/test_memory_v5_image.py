import hashlib
import json
import math
from pathlib import Path
import re
import struct
from tempfile import TemporaryDirectory

import pytest

from rtl.tools import generate_memory_v3 as v3
from rtl.tools import generate_memory_v5 as v5


ROOT = v5.ROOT
MANIFEST_PATH = ROOT / "upstream" / "parameters" / "manifest.json"
BLOB_PATH = ROOT / "upstream" / "parameters" / "parameters.bin"
V4_ROOT = ROOT / "outputs" / "memory" / "2026-09-03" / "v4"
V5_ROOT = ROOT / "outputs" / "memory" / "2026-09-09" / "v5"
V5_HEADER = ROOT / "rtl" / "memory" / "model_memory_v5_map.vh"
V5_TABLE = ROOT / "rtl" / "memory" / "model_memory_v5_table.v"
V5_READBACK = ROOT / "rtl" / "memory" / "model_memory_v5_readback_table.v"
V4_FROZEN = ROOT / "docs" / "frozen" / "PE_MEMORY_V4_SHA256SUMS"

EXPECTED_MANIFEST_SHA256 = (
    "e5618b86bcbef4d1d7f10c6bc05ff2d3c58e459235893c8428802cb2f726df99"
)
EXPECTED_BLOB_BYTES = 2_193_288
EXPECTED_BLOB_SHA256 = (
    "572da396d01fbc20a9ed23f17fbbb0c29e3539fe9f7c3c9eb8c1c2c82f22f894"
)
EXPECTED_V4_IMAGE_SHA256 = (
    "e4f1f5cd78007a47c8ecfc137f2f0e8117aa2af162bd7050913bf1867cf2cf34"
)
EXPECTED_GLOBAL_LUT_SHA256 = (
    "af70843be21e720cedb6f627b02b69ef69a2519912c5bf900d9147f70b602c21"
)
EXPECTED_ROW_TILES = (10, 10, 2, 7, 7, 3, 7, 7, 6, 7, 7, 4)

# Filled from the independently checked first v5 checkpoint and thereafter
# treated as immutable regression oracles.
EXPECTED_V5_IMAGE_BYTES = 1_056_224
EXPECTED_V5_IMAGE_SHA256 = (
    "0a898aca19599f976b3988f92ff645b1490dc3ac470003683199e80b134f458a"
)
EXPECTED_STAGE_OFFSETS = (
    2_112, 139_520, 358_848, 379_904, 450_560, 561_088,
    583_488, 664_896, 775_424, 820_160, 915_904, 1_026_432,
)
EXPECTED_STAGE_TRANSFER_BYTES = (
    137_360, 219_280, 21_040, 70_616, 110_488, 22_344,
    81_368, 110_488, 44_688, 95_704, 110_488, 29_792,
)
EXPECTED_STAGE_SHA256 = (
    "7fbd749e2206650072cf28ad2ab2911c3c3264016e43b9174cd3425ca8c5285a",
    "83867ac32edc541706d6752fd5b78ab268fef2d594be3aeab81f2f2804dba562",
    "e224d60f19ea68bc7cf792f413e2222dd1598224d9d878a27654d06223ecc75e",
    "301b57a35eb6c3b195011cc4dd8b08ab51240cc4990ec1271dd2c80998e7cb7a",
    "62705a28c3f725601625510af99e3d78cd7af1f2238d4e48b228ceb3238351a8",
    "a45874ad107e26f0988e4309e13f03036d5b02631ea18ddeb0af2c365a68ff52",
    "8a29c966ed6599ce114083554b195e5f03e0f8b28a4aa41672432310e84e3426",
    "9ede3e3241b8b5d73f584e5db73bd69327a2ae9b72f3ce2a512c3501bffacae7",
    "6299940d8af56b93c9a90c60d05bfcd59b7fb039c1253a53b6935e5923cc1759",
    "d3d5763e18b4cc123cb5f379ecb53158ec8713ec6b1b66b2fc7bdb02f8d2e5d3",
    "df0ab06667c10282770ad8fd4b3498ef06e47e5fa51759cbee189ac590ebdf04",
    "17627bbf70d1ac8ac5e5f1087d9fee3cd55d82b092b99741501e4199bafc8e45",
)

DTYPE_FORMAT = {
    "int8": "b",
    "uint8": "B",
    "int32": "i",
    "int64": "q",
    "float64": "d",
}


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def tensor_payload(blob: bytes, tensor: dict) -> bytes:
    start = int(tensor["offset"])
    size = int(tensor["nbytes"])
    payload = blob[start : start + size]
    assert len(payload) == size
    assert sha256(payload) == tensor["sha256"]
    return payload


def tensor_values(blob: bytes, tensor: dict) -> list[int | float]:
    payload = tensor_payload(blob, tensor)
    item_format = DTYPE_FORMAT[tensor["dtype"]]
    item_bytes = struct.calcsize(item_format)
    values = list(struct.unpack("<" + item_format * (len(payload) // item_bytes), payload))
    assert len(values) == math.prod(tensor["shape"] or [1])
    return values


def selected_index(selector: str, hidden_size: int, channel: int) -> int:
    if selector in {"forget", "channel"}:
        return channel
    assert selector == "cell"
    return hidden_size + channel


def signed_value(encoded: int, width: int) -> int:
    sign = 1 << (width - 1)
    return encoded - (1 << width) if encoded & sign else encoded


def stage_section(image: bytes, stage: dict, section: dict) -> bytes:
    start = int(stage["dram_byte_offset"]) + int(section["local_byte_offset"])
    return image[start : start + int(section["payload_bytes"])]


def decoded_field_lanes(payload: bytes, params: dict, tile: int, field: dict) -> list[int]:
    record_start = tile * int(params["record_bytes"])
    record_end = record_start + int(params["response_bytes"])
    word = int.from_bytes(payload[record_start:record_end], "little")
    mask = (1 << int(field["lane_width"])) - 1
    values = []
    for lane in range(int(field["lanes"])):
        encoded = (word >> (int(field["lsb"]) + lane * int(field["lane_width"]))) & mask
        values.append(signed_value(encoded, int(field["lane_width"])) if field["signed"] else encoded)
    return values


def parse_verilog_literal(token: str) -> int:
    match = re.fullmatch(r"(?:(\d+)'([bBdDhH]))?([0-9a-fA-F_]+)", token)
    assert match is not None, token
    base = {"b": 2, "d": 10, "h": 16}[(match.group(2) or "d").lower()]
    return int(match.group(3).replace("_", ""), base)


def parse_assignments(source: str) -> dict[str, int]:
    return {
        name: parse_verilog_literal(literal)
        for name, literal in re.findall(
            r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"
            r"((?:\d+'[bBdDhH])?[0-9a-fA-F_]+)\s*;",
            source,
            flags=re.MULTILINE,
        )
    }


def parse_stage_table(source: str) -> tuple[dict[str, int], dict[int, dict[str, int]]]:
    before_case, separator, _ = source.partition("case (stage_id)")
    assert separator
    defaults = parse_assignments(before_case)
    cases = {}
    for stage_text, body in re.findall(
        r"^\s*4'd(\d+):\s*begin\s*$" r"(.*?)" r"^\s*end\s*$",
        source,
        flags=re.MULTILINE | re.DOTALL,
    ):
        cases[int(stage_text)] = parse_assignments(body)
    return defaults, cases


def test_source_and_frozen_v4_checkpoint_are_unchanged():
    manifest_payload = MANIFEST_PATH.read_bytes()
    blob = BLOB_PATH.read_bytes()
    assert sha256(manifest_payload) == EXPECTED_MANIFEST_SHA256
    assert len(blob) == EXPECTED_BLOB_BYTES
    assert sha256(blob) == EXPECTED_BLOB_SHA256
    assert sha256((V4_ROOT / "parameters_v4.bin").read_bytes()) == EXPECTED_V4_IMAGE_SHA256

    # The historical file also lists later-evolved v1 datapath/runtime RTL.
    # Phase 5B freezes the v4-named generator, tests, image descriptors and
    # artifacts themselves; verify that exact subset without misclassifying
    # separately committed runtime fixes as image-v4 drift.
    lines = [
        line
        for line in V4_FROZEN.read_text(encoding="ascii").splitlines()
        if "v4" in line.split("  ", 1)[1]
    ]
    assert len(lines) == 8
    for line in lines:
        digest, relative = line.split("  ", 1)
        path = ROOT / relative
        assert path.is_file(), relative
        assert sha256(path.read_bytes()) == digest, relative
    assert sha256((ROOT / "rtl/tools/generate_memory_v4.py").read_bytes()) == (
        "88c38ee14ee4520ac34e819ce8a5fbef92f001093bb614497828649e4dcf4623"
    )
    assert sha256((ROOT / "rtl/tests/test_memory_v4_image.py").read_bytes()) == (
        "b9b7d66c31fc593b9aa658e9e727e1ed4809f53baddd0e375e71f5c8f9324bc5"
    )


def test_v5_snapshot_is_deterministic_complete_and_fixed():
    image, layout, golden = v5.build_image(MANIFEST_PATH)
    second = v5.build_image(MANIFEST_PATH)
    assert second == (image, layout, golden)

    assert image == (V5_ROOT / "parameters_v5.bin").read_bytes()
    assert layout == load_json(V5_ROOT / "memory_layout_v5.json")
    assert golden == load_json(V5_ROOT / "memory_golden_v5.json")
    assert v5.emit_header(layout) == V5_HEADER.read_text(encoding="utf-8")
    assert v5.emit_table(layout) == V5_TABLE.read_text(encoding="utf-8")
    assert v5.emit_readback_table(golden) == V5_READBACK.read_text(encoding="utf-8")

    assert len(image) == EXPECTED_V5_IMAGE_BYTES
    assert sha256(image) == layout["image_sha256"] == EXPECTED_V5_IMAGE_SHA256
    assert tuple(stage["dram_byte_offset"] for stage in layout["stages"]) == EXPECTED_STAGE_OFFSETS
    assert tuple(stage["transfer_bytes"] for stage in layout["stages"]) == EXPECTED_STAGE_TRANSFER_BYTES
    assert tuple(stage["stage_sha256"] for stage in layout["stages"]) == EXPECTED_STAGE_SHA256

    with TemporaryDirectory() as directory:
        root = Path(directory)
        paths = v5.write_artifacts(
            image=image,
            layout=layout,
            golden=golden,
            output_dir=root / "v5",
            output_vh=root / "rtl" / "model_memory_v5_map.vh",
            output_table=root / "rtl" / "model_memory_v5_table.v",
            output_readback_table=root / "rtl" / "model_memory_v5_readback_table.v",
        )
        expected = {
            "parameters_v5.bin": V5_ROOT / "parameters_v5.bin",
            "memory_layout_v5.json": V5_ROOT / "memory_layout_v5.json",
            "memory_golden_v5.json": V5_ROOT / "memory_golden_v5.json",
            "parameters_v5.sha256": V5_ROOT / "parameters_v5.sha256",
            "model_memory_v5_map.vh": V5_HEADER,
            "model_memory_v5_table.v": V5_TABLE,
            "model_memory_v5_readback_table.v": V5_READBACK,
        }
        assert {path.name for path in paths} == set(expected)
        for path in paths:
            assert path.read_bytes() == expected[path.name].read_bytes(), path.name


def test_header_geometry_alignment_and_parameter_abi_are_exact():
    image = (V5_ROOT / "parameters_v5.bin").read_bytes()
    layout = load_json(V5_ROOT / "memory_layout_v5.json")
    magic, version, stages, lanes, bus_bytes, stage_alignment, reserved = struct.unpack(
        "<8sIIIIII", image[:32]
    )
    assert (magic, version, stages, lanes, bus_bytes, stage_alignment, reserved) == (
        b"ZEPHYR5\0", 5, 12, 32, 8, 64, 0
    )
    assert image[32:64].hex() == EXPECTED_MANIFEST_SHA256
    assert layout["lanes"] == 32
    assert layout["bus_bytes"] == 8
    assert layout["parameter_abi"] == {
        "gsu_response_bits": 11_584,
        "gsu_record_bytes": 1_448,
        "gsu_record_words": 181,
        "projection_response_bits": 2_240,
        "projection_record_bytes": 280,
        "projection_record_words": 35,
        "lane_zero_is_lowest_bits": True,
        "record_byte_order": "little-endian",
        "record_padding_bytes": 0,
    }
    assert tuple(stage["parameters"]["row_tiles"] for stage in layout["stages"]) == EXPECTED_ROW_TILES
    assert all(stage["dram_byte_offset"] % 64 == 0 for stage in layout["stages"])
    assert all(stage["transfer_bytes"] % 8 == 0 for stage in layout["stages"])
    assert layout["maximum_stage_bytes"] <= layout["cache_bytes"] == 256 * 1024

    global_lut = layout["global_sigmoid_lut"]
    start = global_lut["dram_byte_offset"]
    end = start + global_lut["payload_bytes"]
    v4_image = (V4_ROOT / "parameters_v4.bin").read_bytes()
    v4_layout = load_json(V4_ROOT / "memory_layout_v4.json")
    v4_start = v4_layout["global_sigmoid_lut"]["dram_byte_offset"]
    v4_end = v4_start + v4_layout["global_sigmoid_lut"]["payload_bytes"]
    assert image[start:end] == v4_image[v4_start:v4_end]
    assert sha256(image[start:end]) == EXPECTED_GLOBAL_LUT_SHA256


def test_every_v5_weight_lane_matches_raw_tensor_and_v4_tile_pair():
    manifest = load_json(MANIFEST_PATH)
    blob = BLOB_PATH.read_bytes()
    v4_image = (V4_ROOT / "parameters_v4.bin").read_bytes()
    v4_layout = load_json(V4_ROOT / "memory_layout_v4.json")
    v5_image = (V5_ROOT / "parameters_v5.bin").read_bytes()
    v5_layout = load_json(V5_ROOT / "memory_layout_v5.json")
    checked_lanes = 0
    checked_duplicates = 0

    for v4_stage, v5_stage in zip(v4_layout["stages"], v5_layout["stages"]):
        operator = manifest["operators"][v5_stage["name"]]
        for v4_matrix, v5_matrix in zip(v4_stage["matrices"], v5_stage["matrices"]):
            tensor = operator["tensors"][v5_matrix["name"]]
            raw = tensor_payload(blob, tensor)
            source_rows, source_count = map(int, tensor["shape"])
            output_rows = int(v5_matrix["output_rows"])
            if v5_stage["kind"] == "gsu":
                half = output_rows * source_count
                assert raw[:half] == raw[half:]
                checked_duplicates += half
            else:
                assert source_rows == output_rows

            v4_payload = stage_section(v4_image, v4_stage, v4_matrix)
            v5_payload = stage_section(v5_image, v5_stage, v5_matrix)
            assert sha256(v5_payload) == v5_matrix["packed_sha256"]
            for source in range(source_count):
                for tile in range(v5_matrix["row_tiles"]):
                    start5 = source * v5_matrix["source_stride_bytes"] + tile * 32
                    tile5 = v5_payload[start5 : start5 + 32]
                    expected = bytearray()
                    for lane in range(32):
                        row = tile * 32 + lane
                        expected.append(raw[row * source_count + source] if row < output_rows else 0)
                    assert tile5 == bytes(expected)

                    pair = bytearray()
                    for old_tile in (2 * tile, 2 * tile + 1):
                        if old_tile < v4_matrix["row_tiles"]:
                            start4 = source * v4_matrix["source_stride_bytes"] + old_tile * 16
                            pair.extend(v4_payload[start4 : start4 + 16])
                        else:
                            pair.extend(bytes(16))
                    assert tile5 == bytes(pair)
                    checked_lanes += 32

    expected_lanes = sum(
        matrix["source_count"] * matrix["row_tiles"] * 32
        for stage in v5_layout["stages"] for matrix in stage["matrices"]
    )
    assert checked_lanes == expected_lanes
    assert checked_duplicates == sum(
        matrix["verified_duplicate_values"]
        for stage in v5_layout["stages"] for matrix in stage["matrices"]
    )


def test_every_v5_parameter_field_matches_raw_tensor_and_v4_tile_pair():
    manifest = load_json(MANIFEST_PATH)
    blob = BLOB_PATH.read_bytes()
    v4_image = (V4_ROOT / "parameters_v4.bin").read_bytes()
    v4_layout = load_json(V4_ROOT / "memory_layout_v4.json")
    v5_image = (V5_ROOT / "parameters_v5.bin").read_bytes()
    v5_layout = load_json(V5_ROOT / "memory_layout_v5.json")
    checked = 0

    for v4_stage, v5_stage in zip(v4_layout["stages"], v5_layout["stages"]):
        operator = manifest["operators"][v5_stage["name"]]
        tensors = operator["tensors"]
        v4_params, v5_params = v4_stage["parameters"], v5_stage["parameters"]
        v4_payload = stage_section(v4_image, v4_stage, v4_params)
        v5_payload = stage_section(v5_image, v5_stage, v5_params)
        assert v5_params["record_padding_bytes"] == 0
        assert v5_params["record_bytes"] == v5_params["response_bytes"]
        assert sha256(v5_payload) == v5_params["packed_sha256"]
        hidden_size = int(v5_stage["matrices"][0]["output_rows"])

        for v4_field, v5_field in zip(v4_params["fields"], v5_params["fields"]):
            assert v4_field["name"] == v5_field["name"]
            assert v4_field["source_tensor"] == v5_field["source_tensor"]
            assert v4_field["source_selector"] == v5_field["source_selector"]
            assert v4_field["lane_width"] == v5_field["lane_width"]
            assert v4_field["signed"] == v5_field["signed"]
            source_values = tensor_values(blob, tensors[v5_field["source_tensor"]])
            for tile in range(v5_params["row_tiles"]):
                lanes5 = decoded_field_lanes(v5_payload, v5_params, tile, v5_field)
                expected = []
                for lane in range(32):
                    channel = tile * 32 + lane
                    expected.append(
                        int(source_values[selected_index(v5_field["source_selector"], hidden_size, channel)])
                        if channel < hidden_size else 0
                    )
                assert lanes5 == expected

                pair = []
                for old_tile in (2 * tile, 2 * tile + 1):
                    if old_tile < v4_params["row_tiles"]:
                        pair.extend(decoded_field_lanes(v4_payload, v4_params, old_tile, v4_field))
                    else:
                        pair.extend([0] * 16)
                assert lanes5 == pair
                checked += sum(1 for lane in range(32) if tile * 32 + lane < hidden_size)

    golden = load_json(V5_ROOT / "memory_golden_v5.json")
    assert checked == golden["dense_reference_checks"]["parameter_values_verified"]


def test_generated_rtl_descriptors_match_json_and_256_bit_readbacks():
    layout = load_json(V5_ROOT / "memory_layout_v5.json")
    golden = load_json(V5_ROOT / "memory_golden_v5.json")
    header = V5_HEADER.read_text(encoding="utf-8")
    table = V5_TABLE.read_text(encoding="utf-8")
    readback = V5_READBACK.read_text(encoding="utf-8")
    assert "MODEL_V5_IMAGE_VERSION 32'd5" in header
    assert "MODEL_V5_LANES 32" in header
    assert "MODEL_V5_GSU_PARAM_BITS 11584" in header
    assert "MODEL_V5_PROJECTION_PARAM_BITS 2240" in header
    assert "output reg  [13:0] param_response_bits" in table
    assert "output reg  [255:0] expected_data" in readback
    defaults, cases = parse_stage_table(table)
    assert defaults["param_response_bits"] == 0
    assert set(cases) == set(range(12))
    for stage in layout["stages"]:
        case = cases[stage["id"]]
        assert case["stage_valid"] == 1
        assert case["dram_byte_offset"] == stage["dram_byte_offset"]
        assert case["transfer_bytes"] == stage["transfer_bytes"]
        assert case["param_record_words"] == stage["parameters"]["record_words"]
        assert case["param_response_bits"] == stage["parameters"]["response_bits"]
        assert case["param_tiles"] == stage["parameters"]["row_tiles"]
    for vector in golden["weight_readback_vectors"]["vectors"]:
        assert f"expected_data = 256'h{vector['expected_u256_le_hex'][2:]};" in readback
        assert len(vector["expected_lane_bytes_hex"]) == 64
        assert len(vector["expected_words_le"]) == 8


def test_v5_packers_fail_closed_on_bad_shared_halves_and_record_geometry():
    with pytest.raises(ValueError, match="gate halves differ"):
        v5.pack_source_major_matrix(
            bytes(range(8)), source_rows=4, output_rows=2, source_count=2,
            shared_gate_halves=True, tensor_name="bad",
        )
    with pytest.raises(ValueError, match="exact bus-aligned response"):
        v5.pack_parameter_records(
            blob=b"", tensors={}, hidden_size=1, fields=[], response_bits=0,
            record_bytes=8,
        )
