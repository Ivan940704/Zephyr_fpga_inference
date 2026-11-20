from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
TRACE_DIR = Path(__file__).resolve().parent / "traces"
FIXTURE_DIR = ROOT / "imports" / "fixtures" / "v4"
sys.path.insert(0, str(Path(__file__).resolve().parent))

from traffic_oracle import (  # noqa: E402
    AXI_BOUNDARY_BYTES,
    CACHE_BYTES,
    DENSE_BYTES_PER_FRAME,
    FRAME_STAGE_ORDER,
    LOGICAL_SOURCE_CAPACITY,
    LUT_BYTES_PER_RESET,
    SPARSE_ELIGIBLE_BYTES_PER_FRAME,
    STAGE_RULES,
    ZERO_ACTIVE_BYTES_PER_FRAME,
    ActiveListTrace,
    OracleError,
    TraceFormatError,
    accepted_r_bytes,
    contiguous_source_runs,
    load_v4_layout,
    plan_frame,
    plan_lut_transfer,
    plan_stage,
    split_axi_transfer,
)


def load_trace(name: str) -> ActiveListTrace:
    return ActiveListTrace.load(TRACE_DIR / f"{name}.json")


def uniform_trace(fb_count: int, sb_count: int) -> ActiveListTrace:
    records = []
    for frame_id in (0, 1):
        for logical_id, capacity in LOGICAL_SOURCE_CAPACITY.items():
            count = fb_count if capacity == 320 else sb_count
            records.append(
                {
                    "frame_id": frame_id,
                    "logical_id": logical_id,
                    "ordered_active_indices": list(range(count)),
                }
            )
    return ActiveListTrace.from_records(
        records,
        name=f"uniform-fb{fb_count}-sb{sb_count}",
    )


def sparse_matrix_selection(stage, matrix_id: int):
    return next(
        selection
        for selection in stage.matrix_selections
        if selection.matrix_id == matrix_id
    )


def matrix_ranges(stage, matrix_id: int):
    return tuple(
        copy_range
        for copy_range in stage.copy_ranges
        if copy_range.region == "matrix" and copy_range.matrix_id == matrix_id
    )


def test_layout_constants_and_sparse_floor_are_hash_pinned_v4_geometry():
    layout = load_v4_layout()
    assert layout.image_bytes == 1_053_056
    assert layout.cache_bytes == CACHE_BYTES
    assert layout.bus_bytes == 8
    assert len(layout.stages) == 12
    assert sum(stage.transfer_bytes for stage in layout.stages) == DENSE_BYTES_PER_FRAME
    assert layout.lut_transfer_bytes == LUT_BYTES_PER_RESET

    parameter_bytes = sum(stage.parameters.payload_bytes for stage in layout.stages)
    mandatory_dense_bytes = sum(
        layout.stage(stage_id).matrices[0].payload_bytes
        for stage_id in (0, 3, 6, 9)
    )
    assert parameter_bytes == 94_448
    assert mandatory_dense_bytes == 87_232
    assert parameter_bytes + mandatory_dense_bytes == ZERO_ACTIVE_BYTES_PER_FRAME
    assert DENSE_BYTES_PER_FRAME - ZERO_ACTIVE_BYTES_PER_FRAME == (
        SPARSE_ELIGIBLE_BYTES_PER_FRAME
    )


def test_trace_reader_loads_all_required_deterministic_scenarios():
    expected = {
        "zero",
        "one",
        "consecutive",
        "scattered",
        "quarter",
        "fifty_five_percent",
        "dense",
        "context_overlap",
        "context_disjoint",
    }
    actual = {path.stem for path in TRACE_DIR.glob("*.json")}
    assert actual == expected
    for name in sorted(expected):
        trace = load_trace(name)
        assert trace.name == name
        assert trace.description


def test_trace_reader_rejects_bad_schema_order_duplicates_and_bounds(tmp_path):
    bad_payloads = (
        {"format_version": 2, "name": "bad", "records": []},
        {
            "format_version": 1,
            "name": "bad",
            "records": [
                {
                    "frame_id": 0,
                    "logical_id": 0,
                    "ordered_active_indices": [2, 1],
                }
            ],
        },
        {
            "format_version": 1,
            "name": "bad",
            "records": [
                {
                    "frame_id": 0,
                    "logical_id": 2,
                    "ordered_active_indices": [224],
                }
            ],
        },
        {
            "format_version": 1,
            "name": "bad",
            "records": [
                {
                    "frame_id": 0,
                    "logical_id": 0,
                    "ordered_active_indices": [],
                },
                {
                    "frame_id": 0,
                    "logical_id": 0,
                    "ordered_active_indices": [],
                },
            ],
        },
    )
    for ordinal, payload in enumerate(bad_payloads):
        target = tmp_path / f"bad-{ordinal}.json"
        target.write_text(json.dumps(payload), encoding="utf-8")
        with pytest.raises(TraceFormatError):
            ActiveListTrace.load(target)


def test_exact_twelve_stage_context_and_generation_mapping():
    expected = {
        0: (0, 1, ("dense",), ("recurrent_self", -1, (0,))),
        1: (0, 1, ("predecessor", 0, (0,)), ("recurrent_self", -1, (1,))),
        2: (0, 1, ("predecessor", 0, (1,))),
        3: (1, 4, ("dense",), ("recurrent_self", -1, (2, 4, 6, 8))),
        4: (
            1,
            4,
            ("predecessor", 0, (2, 4, 6, 8)),
            ("recurrent_self", -1, (3, 5, 7, 9)),
        ),
        5: (1, 4, ("predecessor", 0, (3, 5, 7, 9))),
        6: (2, 3, ("dense",), ("recurrent_self", -1, (10, 12, 14))),
        7: (
            2,
            3,
            ("predecessor", 0, (10, 12, 14)),
            ("recurrent_self", -1, (11, 13, 15)),
        ),
        8: (2, 3, ("predecessor", 0, (11, 13, 15))),
        9: (3, 2, ("dense",), ("recurrent_self", -1, (16, 18))),
        10: (
            3,
            2,
            ("predecessor", 0, (16, 18)),
            ("recurrent_self", -1, (17, 19)),
        ),
        11: (3, 2, ("predecessor", 0, (17, 19))),
    }
    observed = {}
    for rule in STAGE_RULES:
        matrix_rules = []
        for matrix in rule.matrices:
            if matrix.dense:
                matrix_rules.append(("dense",))
            else:
                requirement = matrix.requirement
                assert requirement is not None
                matrix_rules.append(
                    (
                        requirement.relationship,
                        requirement.frame_delta,
                        requirement.logical_ids,
                    )
                )
        observed[rule.stage_id] = (
            rule.branch,
            rule.context_count,
            *matrix_rules,
        )
    assert observed == expected

    records = []
    for logical_id in range(20):
        records.extend(
            (
                {
                    "frame_id": 0,
                    "logical_id": logical_id,
                    "ordered_active_indices": [100 + logical_id],
                },
                {
                    "frame_id": 1,
                    "logical_id": logical_id,
                    "ordered_active_indices": [logical_id],
                },
            )
        )
    trace = ActiveListTrace.from_records(records, name="mapping-sentinels")
    layout = load_v4_layout()
    for rule in STAGE_RULES:
        traffic = plan_stage(layout, trace, frame_id=1, stage_id=rule.stage_id)
        for matrix_rule, selection in zip(
            rule.matrices, traffic.matrix_selections, strict=True
        ):
            if matrix_rule.dense:
                assert selection.dense
                continue
            requirement = matrix_rule.requirement
            assert requirement is not None
            expected_sources = tuple(
                sorted(
                    (100 + logical_id if requirement.frame_delta == -1 else logical_id)
                    for logical_id in requirement.logical_ids
                )
            )
            assert selection.logical_ids == requirement.logical_ids
            assert selection.source_frame_id == 1 + requirement.frame_delta
            assert selection.active_sources == expected_sources


def test_missing_predecessor_is_an_error_but_missing_recurrent_self_is_empty():
    layout = load_v4_layout()
    empty = ActiveListTrace.from_records([], name="empty")

    stage0 = plan_stage(layout, empty, frame_id=0, stage_id=0)
    assert sparse_matrix_selection(stage0, 1).active_sources == ()
    with pytest.raises(OracleError, match="requires frame 0 logical list 0"):
        plan_stage(layout, empty, frame_id=0, stage_id=1)


def test_zero_one_consecutive_and_scattered_source_runs():
    layout = load_v4_layout()
    zero = plan_stage(layout, load_trace("zero"), frame_id=1, stage_id=4)
    one = plan_stage(layout, load_trace("one"), frame_id=1, stage_id=4)
    consecutive = plan_stage(
        layout, load_trace("consecutive"), frame_id=1, stage_id=4
    )
    scattered = plan_stage(layout, load_trace("scattered"), frame_id=1, stage_id=4)

    assert sparse_matrix_selection(zero, 0).active_sources == ()
    assert matrix_ranges(zero, 0) == ()
    assert sparse_matrix_selection(one, 0).active_sources == (7,)
    assert [(item.first_source, item.source_count) for item in matrix_ranges(one, 0)] == [
        (7, 1)
    ]
    assert sparse_matrix_selection(consecutive, 0).active_sources == tuple(range(4, 11))
    assert [
        (item.first_source, item.source_count)
        for item in matrix_ranges(consecutive, 0)
    ] == [(4, 7)]
    assert sparse_matrix_selection(scattered, 0).active_sources == (
        1,
        9,
        17,
        33,
        70,
        100,
        170,
        223,
    )
    assert all(item.source_count == 1 for item in matrix_ranges(scattered, 0))


def test_quarter_fifty_five_percent_and_dense_fixture_bytes():
    layout = load_v4_layout()
    scenarios = (
        ("quarter", 80, 80),
        ("fifty_five_percent", 176, 16),
        ("dense", 320, 1),
    )
    for name, expected_sources, expected_runs in scenarios:
        stage = plan_stage(layout, load_trace(name), frame_id=1, stage_id=1)
        selection = sparse_matrix_selection(stage, 0)
        ranges = matrix_ranges(stage, 0)
        assert len(selection.active_sources) == expected_sources
        assert sum(item.byte_count for item in ranges) == expected_sources * 20 * 16
        assert len(ranges) == expected_runs


def test_context_overlap_and_disjoint_are_unioned_matrix_wise():
    layout = load_v4_layout()
    overlap = plan_stage(
        layout, load_trace("context_overlap"), frame_id=1, stage_id=4
    )
    disjoint = plan_stage(
        layout, load_trace("context_disjoint"), frame_id=1, stage_id=4
    )
    overlap_selection = sparse_matrix_selection(overlap, 0)
    disjoint_selection = sparse_matrix_selection(disjoint, 0)

    assert overlap_selection.logical_ids == (2, 4, 6, 8)
    assert overlap_selection.active_sources == tuple(range(10))
    assert [(item.first_source, item.source_count) for item in matrix_ranges(overlap, 0)] == [
        (0, 10)
    ]
    assert len(disjoint_selection.active_sources) == 12
    assert [(item.first_source, item.source_count) for item in matrix_ranges(disjoint, 0)] == [
        (0, 3),
        (10, 3),
        (20, 3),
        (30, 3),
    ]


def test_copy_ranges_use_canonical_ddr_and_cache_offsets_and_preserve_bytes():
    layout = load_v4_layout()
    stage_geometry = layout.stage(4)
    traffic = plan_stage(
        layout, load_trace("context_overlap"), frame_id=1, stage_id=4
    )
    matrix_range = matrix_ranges(traffic, 0)[0]
    assert matrix_range.image_byte_start == stage_geometry.image_byte_offset
    assert matrix_range.cache_byte_start == 0
    assert matrix_range.byte_count == 10 * 14 * 16

    parameter_range = next(
        copy_range
        for copy_range in traffic.copy_ranges
        if copy_range.region == "parameters"
    )
    assert parameter_range.image_byte_start == (
        stage_geometry.image_byte_offset
        + stage_geometry.parameters.local_byte_offset
    )
    assert parameter_range.cache_byte_start == stage_geometry.parameters.local_byte_offset
    assert parameter_range.byte_count == stage_geometry.parameters.payload_bytes

    image = (FIXTURE_DIR / "parameters_v4.bin").read_bytes()
    sentinel = 0xA5
    cache = bytearray([sentinel]) * layout.cache_bytes
    for copy_range in traffic.copy_ranges:
        cache[copy_range.cache_byte_start : copy_range.cache_byte_end] = image[
            copy_range.image_byte_start : copy_range.image_byte_end
        ]

    matrix = stage_geometry.matrices[0]
    selected = set(sparse_matrix_selection(traffic, 0).active_sources)
    for source in range(matrix.source_count):
        cache_start = matrix.local_byte_offset + source * matrix.source_stride_bytes
        cache_end = cache_start + matrix.source_stride_bytes
        image_start = stage_geometry.image_byte_offset + cache_start
        image_end = image_start + matrix.source_stride_bytes
        if source in selected:
            assert cache[cache_start:cache_end] == image[image_start:image_end]
        else:
            assert cache[cache_start:cache_end] == bytes([sentinel]) * (
                matrix.source_stride_bytes
            )


@pytest.mark.parametrize(
    ("fb_count", "sb_count", "expected_bytes"),
    (
        (0, 0, ZERO_ACTIVE_BYTES_PER_FRAME),
        (1, 1, 185_120),
        (80, 56, 398_896),
        (176, 123, 659_072),
        (320, 224, DENSE_BYTES_PER_FRAME),
    ),
)
def test_full_frame_zero_one_quarter_fifty_five_and_dense_traffic(
    fb_count, sb_count, expected_bytes
):
    layout = load_v4_layout()
    frame = plan_frame(layout, uniform_trace(fb_count, sb_count), frame_id=1)
    assert tuple(stage.stage_id for stage in frame.stages) == FRAME_STAGE_ORDER
    assert frame.planned_bytes == expected_bytes
    assert accepted_r_bytes(frame.accepted_r_beats) == expected_bytes
    # Independent closed form: FB eligible roles cost 1,024 bytes/source and
    # the three SB branches together cost 2,416 bytes/unioned source.
    assert expected_bytes == (
        ZERO_ACTIVE_BYTES_PER_FRAME + fb_count * 1_024 + sb_count * 2_416
    )
    if expected_bytes == DENSE_BYTES_PER_FRAME:
        assert all(stage.full_load_fallback for stage in frame.stages)
        assert frame.copy_commands == 12
        assert all(stage.copy_ranges[0].region == "full_stage" for stage in frame.stages)


def test_axi_split_obeys_max_burst_and_never_crosses_4k():
    boundary_case = split_axi_transfer(0x0FF8, 0, 24)
    assert [burst.accepted_r_beats for burst in boundary_case] == [1, 2]
    assert [burst.source_address for burst in boundary_case] == [0x0FF8, 0x1000]

    max_length_case = split_axi_transfer(0x2000, 0, 17 * 8)
    assert [burst.accepted_r_beats for burst in max_length_case] == [16, 1]
    for burst in boundary_case + max_length_case:
        assert 1 <= burst.accepted_r_beats <= 16
        assert burst.source_address // AXI_BOUNDARY_BYTES == (
            (burst.source_address_end - 1) // AXI_BOUNDARY_BYTES
        )


def test_real_frame_bursts_and_lut_use_accepted_r_beat_accounting():
    layout = load_v4_layout()
    frame = plan_frame(
        layout,
        uniform_trace(176, 123),
        frame_id=1,
        parameter_base_addr=0x1000_0000,
    )
    for stage in frame.stages:
        assert accepted_r_bytes(stage.accepted_r_beats) == stage.planned_bytes
        for burst in stage.axi_bursts:
            assert 1 <= burst.accepted_r_beats <= 16
            assert burst.source_address // AXI_BOUNDARY_BYTES == (
                (burst.source_address_end - 1) // AXI_BOUNDARY_BYTES
            )

    lut = plan_lut_transfer(layout, parameter_base_addr=0x1000_0000)
    assert lut.planned_bytes == LUT_BYTES_PER_RESET
    assert lut.accepted_r_beats == 255
    assert accepted_r_bytes(lut.accepted_r_beats) == LUT_BYTES_PER_RESET
    assert len(lut.axi_bursts) == 16


def test_address_and_beat_contract_rejects_unaligned_or_overflowing_inputs():
    layout = load_v4_layout()
    trace = uniform_trace(0, 0)
    with pytest.raises(OracleError, match="64-byte-aligned"):
        plan_frame(layout, trace, frame_id=1, parameter_base_addr=8)
    with pytest.raises(OracleError, match="overflows"):
        plan_stage(
            layout,
            trace,
            frame_id=1,
            stage_id=11,
            parameter_base_addr=0xFFFF_FFC0,
        )
    with pytest.raises(OracleError, match="whole number of beats"):
        split_axi_transfer(0, 0, 9)
    with pytest.raises(OracleError, match="non-negative integer"):
        accepted_r_bytes(-1)


def test_contiguous_source_run_helper_is_strict():
    assert contiguous_source_runs(()) == ()
    assert contiguous_source_runs((1, 2, 3, 8, 10, 11)) == (
        (1, 3),
        (8, 1),
        (10, 2),
    )
    with pytest.raises(OracleError, match="strictly increasing"):
        contiguous_source_runs((1, 1))
