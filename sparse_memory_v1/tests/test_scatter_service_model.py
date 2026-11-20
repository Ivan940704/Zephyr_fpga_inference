from __future__ import annotations

import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))

from scatter_service_model import (  # noqa: E402
    CACHE_BYTES,
    ScatterFault,
    ScatterServiceModel,
    accepted_r_bytes,
    axi_bursts,
    build_stage_commands,
    full_bitmap,
    load_layout,
)


IMAGE = (ROOT / "imports" / "fixtures" / "v4" / "parameters_v4.bin").read_bytes()


def test_zero_active_commands_are_parameters_plus_mandatory_dense():
    layout = load_layout()
    total = 0
    for stage_id in range(12):
        commands, _, dense = build_stage_commands(stage_id, (0, 0))
        assert not dense
        total += accepted_r_bytes(commands)
        assert commands[-1].kind == "parameters"
    assert total == 181_680
    assert sum(stage["parameters"]["payload_bytes"] for stage in layout["stages"]) == 94_448


def test_canonical_scatter_preserves_addresses_and_selected_weights():
    layout = load_layout()
    stage_id = 4
    bits0 = (1 << 1) | (1 << 2) | (1 << 9)
    bits1 = (1 << 0) | (1 << 200)
    model = ScatterServiceModel(IMAGE)
    model.load(stage_id, (bits0, bits1))
    assert [command.source_count for command in model.last_commands[:-1]] == [2, 1, 1, 1]
    for matrix_id, bits in enumerate((bits0, bits1)):
        matrix = layout["stages"][stage_id]["matrices"][matrix_id]
        for source in range(matrix["source_count"]):
            if (bits >> source) & 1:
                expected_at = (
                    layout["stages"][stage_id]["dram_byte_offset"]
                    + matrix["local_byte_offset"]
                    + source * matrix["source_stride_bytes"]
                )
                assert model.read_weight(matrix_id, source, 0) == IMAGE[
                    expected_at : expected_at + 16
                ]
    parameter = layout["stages"][stage_id]["parameters"]
    expected_at = layout["stages"][stage_id]["dram_byte_offset"] + parameter[
        "local_byte_offset"
    ]
    assert model.read_parameter(0) == IMAGE[
        expected_at : expected_at + parameter["response_bytes"]
    ]


def test_mandatory_input_matrix_is_forced_dense():
    layout = load_layout()
    for stage_id in (0, 3, 6, 9):
        commands, residency, dense = build_stage_commands(stage_id, (0, 0))
        assert not dense
        assert residency[0] == full_bitmap(
            layout["stages"][stage_id]["matrices"][0]["source_count"]
        )
        assert commands[0].matrix == 0 and commands[0].first_source == 0
        with pytest.raises(ScatterFault, match="bitmap must be zero"):
            build_stage_commands(stage_id, (1, 0))


def test_disabled_and_dense_union_take_one_full_stage_command():
    layout = load_layout()
    stage = layout["stages"][1]
    dense = tuple(full_bitmap(matrix["source_count"]) for matrix in stage["matrices"])
    for sparse_enable, bitmaps in ((False, (0, 0)), (True, dense)):
        commands, residency, fallback = build_stage_commands(
            1, bitmaps, sparse_enable=sparse_enable
        )
        assert fallback
        assert len(commands) == 1 and commands[0].kind == "dense_stage"
        assert commands[0].byte_count == stage["transfer_bytes"]
        assert all(residency)


def test_axi_bursts_never_cross_4k_and_actual_bytes_are_accepted_beats():
    commands, _, _ = build_stage_commands(
        1,
        ((1 << 320) - 1, 0),
        image_base=0x1000_0000,
    )
    for command in commands:
        bursts = axi_bursts(command)
        assert sum(beats * 8 for _, beats in bursts) == command.byte_count
        assert all(1 <= beats <= 16 for _, beats in bursts)
        assert all((address & ~0xFFF) == ((address + beats * 8 - 1) & ~0xFFF) for address, beats in bursts)


def test_stale_hole_is_fatal_and_never_returns_old_cache_data():
    model = ScatterServiceModel(IMAGE)
    model.load(4, (1 << 3, 0))
    with pytest.raises(ScatterFault, match="not resident"):
        model.read_weight(0, 4, 0)
    assert model.fatal


def test_partial_load_never_publishes_residency():
    model = ScatterServiceModel(IMAGE)
    with pytest.raises(ScatterFault, match="partial-load"):
        model.load(4, ((1 << 3) | (1 << 8), 1), fail_after_commands=1)
    assert model.active_stage is None
    assert model.residency == (0, 0)
    assert model.fatal


@pytest.mark.parametrize("stage_id", (0, 2))
def test_parameter_response_excludes_record_padding(stage_id):
    layout = load_layout()
    model = ScatterServiceModel(IMAGE)
    model.load(stage_id, (0, 0))
    parameter = layout["stages"][stage_id]["parameters"]
    response = model.read_parameter(0)
    assert len(response) == parameter["response_bytes"]
    assert parameter["record_bytes"] - len(response) == parameter["record_padding_bytes"]


def test_invalid_plan_makes_transaction_model_reset_only_fatal():
    model = ScatterServiceModel(IMAGE)
    with pytest.raises(ScatterFault, match="invalid stage"):
        model.load(12, (0, 0))
    assert model.fatal
    with pytest.raises(ScatterFault, match="not empty"):
        model.load(2, (0, 0))


@pytest.mark.parametrize(
    "stage_id,bitmaps,image_base",
    [
        (12, (0, 0), 0),
        (2, (0, 1), 0),
        (1, (1 << 320, 0), 0),
        (11, (1, 0), 0xFFFF_FFC0),
        (11, (0, 0), 0xFFEF_EE80),
    ],
)
def test_invalid_plan_or_33_bit_bounds_fail_closed(stage_id, bitmaps, image_base):
    with pytest.raises(ScatterFault):
        build_stage_commands(stage_id, bitmaps, image_base=image_base)


def test_cache_range_constant_is_single_256_kib_space():
    assert CACHE_BYTES == 262_144


def test_dma_copy_preserves_frozen_geometry_and_adds_protocol_fencing():
    imported = (
        ROOT / "imports" / "memory_v4" / "memory" / "memory.v"
    ).read_text(encoding="utf-8")
    isolated = (ROOT / "rtl" / "sparse_memory_dma_v1.v").read_text(
        encoding="utf-8"
    )
    for frozen_fragment in (
        "localparam integer DATA_BYTES",
        "localparam integer BRAM_WORDS",
        "words_to_4k_boundary",
        "planned_burst_beats",
        "reg [AXI_DATA_WIDTH-1:0] bram [0:BRAM_WORDS-1]",
    ):
        assert frozen_fragment in imported and frozen_fragment in isolated
    assert "module sparse_memory_dma_v1" in isolated
    assert "rbeat_protocol_error" in isolated
    assert "!error_q &&" in isolated
    assert "abort_q <= 1'b1" in isolated


def test_copied_stage_map_and_table_change_namespace_only():
    imported_map = (
        ROOT / "imports" / "memory_v4" / "memory" / "model_memory_v4_map.vh"
    ).read_text(encoding="utf-8")
    isolated_map = (ROOT / "rtl" / "sparse_memory_v4_map_v1.vh").read_text(
        encoding="utf-8"
    )
    assert imported_map.split("`define MODEL_V4_IMAGE_VERSION", 1)[1] == (
        isolated_map.split("`define MODEL_V4_IMAGE_VERSION", 1)[1]
    )

    imported_table = (
        ROOT / "imports" / "memory_v4" / "memory" / "model_memory_v4_table.v"
    ).read_text(encoding="utf-8")
    isolated_table = (ROOT / "rtl" / "sparse_memory_v4_table_v1.v").read_text(
        encoding="utf-8"
    )
    imported_table = imported_table.replace(
        '`include "memory/model_memory_v4_map.vh"',
        '`include "sparse_memory_v4_map_v1.vh"',
        1,
    ).replace("module model_memory_v4_table (", "module sparse_memory_v4_table_v1 (", 1)
    assert isolated_table == imported_table
