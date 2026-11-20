import json
import re
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[2]
RTL = ROOT / "rtl" / "memory" / "sequential_pe_job_controller.v"
MAP = ROOT / "rtl" / "memory" / "model_memory_v4_map.vh"
V4 = ROOT / "outputs" / "memory" / "2026-09-03" / "v4"
LAYOUT = json.loads((V4 / "memory_layout_v4.json").read_text())
GOLDEN = json.loads((V4 / "memory_golden_v4.json").read_text())
IMAGE = (V4 / "parameters_v4.bin").read_bytes()


def signed(value: int, bits: int) -> int:
    sign = 1 << (bits - 1)
    return value - (1 << bits) if value & sign else value


def extract(record: int, lsb: int, width: int, is_signed: bool) -> int:
    value = (record >> lsb) & ((1 << width) - 1)
    return signed(value, width) if is_signed else value


def macro_values() -> dict[str, int]:
    values: dict[str, int] = {}
    pattern = re.compile(r"^`define\s+(MODEL_V4_[A-Z0-9_]+)\s+(?:\d+'d)?(\d+)$")
    for line in MAP.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match:
            values[match.group(1)] = int(match.group(2))
    return values


def context_identity(branch: int, context: int, layer: int) -> int:
    if branch == 0:
        assert context == 0
        return layer
    return (2, 10, 16)[branch - 1] + context * 2 + layer


def active_indices(source_count: int, density: float) -> list[int]:
    if density == 0:
        return []
    target = min(source_count, round(source_count * density))
    if target == source_count:
        return list(range(source_count))
    return [index for index in range(source_count) if index * target % source_count < target][:target]


def scheduled_requests(stage: dict, matrix_lists: list[list[int]]) -> list[tuple[int, int, int]]:
    requests = []
    for tile in range(stage["parameters"]["row_tiles"]):
        for matrix_id, matrix in enumerate(stage["matrices"]):
            if stage["id"] in (0, 3, 6, 9) and matrix_id == 0:
                sources = range(matrix["source_count"])
            else:
                sources = matrix_lists[matrix_id]
            requests.extend((matrix_id, source, tile) for source in sources)
    return requests


@pytest.mark.parametrize("density", [0.0, 0.03, 0.25, 0.55, 1.0])
def test_all_stage_sparse_request_sets_and_full_ddr_bytes(density: float):
    sparse_roles = 0
    total_transfer = 0
    for stage in LAYOUT["stages"]:
        matrix_lists = []
        for matrix_id, matrix in enumerate(stage["matrices"]):
            dense_role = stage["id"] in (0, 3, 6, 9) and matrix_id == 0
            if dense_role:
                matrix_lists.append([])
            else:
                sparse_roles += 1
                matrix_lists.append(active_indices(matrix["source_count"], density))
        requests = scheduled_requests(stage, matrix_lists)
        expected = 0
        for matrix_id, matrix in enumerate(stage["matrices"]):
            dense_role = stage["id"] in (0, 3, 6, 9) and matrix_id == 0
            count = matrix["source_count"] if dense_role else len(matrix_lists[matrix_id])
            expected += count * matrix["row_tiles"]
        assert len(requests) == expected
        assert requests == sorted(requests, key=lambda item: (item[2], item[0], item[1]))
        total_transfer += stage["transfer_bytes"]
    assert sparse_roles == 16
    assert total_transfer == sum(stage["transfer_bytes"] for stage in LAYOUT["stages"])


def test_weight_schedule_addresses_real_v4_bytes():
    stages = {stage["id"]: stage for stage in LAYOUT["stages"]}
    vectors = GOLDEN["weight_readback_vectors"]["vectors"]
    assert len(vectors) == GOLDEN["weight_readback_vectors"]["count"] == 13
    for vector in vectors:
        stage = stages[vector["stage"]]
        matrix = stage["matrices"][vector["matrix"]]
        calculated_offset = (
            stage["dram_byte_offset"]
            + matrix["local_byte_offset"]
            + (
                vector["source"] * matrix["row_tiles"]
                + vector["row_tile"]
            )
            * 16
        )
        assert calculated_offset == vector["image_byte_offset"]
        word = IMAGE[calculated_offset : calculated_offset + 16]
        assert word.hex() == vector["expected_lane_bytes_hex"]
        assert int.from_bytes(word, "little") == int(
            vector["expected_u128_le_hex"], 16
        )


def test_generated_parameter_offsets_match_layout_and_real_image():
    macros = macro_values()
    for stage in LAYOUT["stages"]:
        parameter = stage["parameters"]
        prefix = "MODEL_V4_GSU_PARAM_" if stage["kind"] == "gsu" else "MODEL_V4_PROJECTION_PARAM_"
        for field in parameter["fields"]:
            macro_name = prefix + field["name"].upper() + "_LSB"
            assert macros[macro_name] == field["lsb"]
        for tile in range(parameter["row_tiles"]):
            start = (
                stage["dram_byte_offset"]
                + parameter["local_byte_offset"]
                + tile * parameter["record_bytes"]
            )
            payload = IMAGE[start : start + parameter["response_bytes"]]
            record = int.from_bytes(payload, "little")
            for field in parameter["fields"]:
                values = [
                    extract(
                        record,
                        field["lsb"] + lane * field["lane_width"],
                        field["lane_width"],
                        field["signed"],
                    )
                    for lane in range(16)
                ]
                assert len(values) == 16
                if field["signed"]:
                    assert all(-(1 << (field["lane_width"] - 1)) <= value < (1 << (field["lane_width"] - 1)) for value in values)
                else:
                    assert all(0 <= value < (1 << field["lane_width"]) for value in values)


def requant(value: int, multiplier: int, shift: int) -> int:
    product = value * multiplier
    magnitude = abs(product)
    bias = 0 if shift == 0 else 1 << (shift - 1)
    result = (magnitude + bias) >> shift
    return -result if product < 0 else result


def test_real_gsu_parameters_require_two_distinct_requantizers():
    differences = 0
    for stage in LAYOUT["stages"]:
        if stage["kind"] != "gsu":
            continue
        parameter = stage["parameters"]
        start = stage["dram_byte_offset"] + parameter["local_byte_offset"]
        record = int.from_bytes(
            IMAGE[start : start + parameter["response_bytes"]], "little"
        )
        fields = {field["name"]: field for field in parameter["fields"]}
        for gate in ("forget", "cell"):
            for lane in range(16):
                def value(name: str) -> int:
                    field = fields[name]
                    return extract(
                        record,
                        field["lsb"] + lane * field["lane_width"],
                        field["lane_width"],
                        field["signed"],
                    )

                input_multiplier = value(f"{gate}_input_multiplier")
                input_shift = value(f"{gate}_input_shift")
                recurrent_multiplier = value(f"{gate}_recurrent_multiplier")
                recurrent_shift = value(f"{gate}_recurrent_shift")
                bias = value(f"{gate}_bias_q")
                input_acc, recurrent_acc = 12345 + lane, -6789 - lane
                separate = (
                    requant(input_acc, input_multiplier, input_shift)
                    + requant(recurrent_acc, recurrent_multiplier, recurrent_shift)
                    + bias
                )
                forbidden = requant(
                    input_acc + recurrent_acc, input_multiplier, input_shift
                ) + bias
                differences += separate != forbidden
    assert differences > 0


def test_context_map_and_shared_stage_release_policy():
    ids = [context_identity(0, 0, layer) for layer in range(2)]
    for branch, count in enumerate((4, 3, 2), start=1):
        for context in range(count):
            ids.extend(context_identity(branch, context, layer) for layer in range(2))
    assert ids == list(range(20))
    assert [context == last for context, last in enumerate((3, 3, 3, 3))] == [False, False, False, True]
    assert [context == 2 for context in range(3)] == [False, False, True]
    assert [context == 1 for context in range(2)] == [False, True]


def test_rtl_is_sequential_and_contains_only_one_tile_snapshot():
    source = RTL.read_text(encoding="utf-8")
    assert source.count("reg [511:0] matrix0_snapshot_q") == 1
    assert "matrix0_raw_accumulator_scratch" not in source
    assert "parameter_weight_bank" not in source
    assert "parameter_source_directory" not in source
    assert "active_index_list_store" not in source
    assert "MODE_SPIKE" in source and "MODE_DENSE" in source
    assert "source_ordinal_q >= current_iteration_count" in source
    assert "ST_FEATURE_REQ" in source and "ST_WEIGHT_REQ" in source
    assert "RQ_input" not in source  # arithmetic is delegated, never fused here
    for macro in (
        "MODEL_V4_GSU_PARAM_FORGET_INPUT_MULTIPLIER_LSB",
        "MODEL_V4_GSU_PARAM_FORGET_RECURRENT_MULTIPLIER_LSB",
        "MODEL_V4_GSU_PARAM_CELL_INPUT_MULTIPLIER_LSB",
        "MODEL_V4_GSU_PARAM_CELL_RECURRENT_MULTIPLIER_LSB",
        "MODEL_V4_GSU_PARAM_BN_MULTIPLIER_LSB",
        "MODEL_V4_PROJECTION_PARAM_OUTPUT_MULTIPLIER_LSB",
    ):
        assert macro in source
