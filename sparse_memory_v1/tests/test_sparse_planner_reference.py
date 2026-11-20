from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
LAYOUT_PATH = ROOT / "imports" / "fixtures" / "v4" / "memory_layout_v4.json"


@dataclass(frozen=True)
class MatrixSpec:
    sources: int
    row_tiles: int
    local_offset: int
    source_stride: int
    dense: bool = False
    list_ids: tuple[int, ...] = ()
    require_present: bool = False


@dataclass(frozen=True)
class StageSpec:
    dram_offset: int
    transfer_bytes: int
    matrices: tuple[MatrixSpec, ...]
    parameter_offset: int
    parameter_bytes: int


@dataclass(frozen=True)
class Descriptor:
    present: bool
    entries: tuple[int, ...] = ()
    reported_count: int | None = None
    descriptor_error: bool = False
    descriptor_tag_matches: bool = True
    list_error_ordinal: int | None = None
    list_bad_tag_ordinal: int | None = None

    @property
    def count(self) -> int:
        return len(self.entries) if self.reported_count is None else self.reported_count


class PlannerFault(RuntimeError):
    pass


def matrix(
    sources: int,
    row_tiles: int,
    local_offset: int,
    source_stride: int,
    *,
    dense: bool = False,
    list_ids: tuple[int, ...] = (),
    require_present: bool = False,
) -> MatrixSpec:
    return MatrixSpec(
        sources,
        row_tiles,
        local_offset,
        source_stride,
        dense,
        list_ids,
        require_present,
    )


# This table is deliberately independent of the RTL.  It is the executable
# form of the CP1 stage geometry and stage-to-logical-list contract.
STAGES = (
    StageSpec(2112, 137440, (
        matrix(64, 20, 0, 320, dense=True),
        matrix(320, 20, 20480, 320, list_ids=(0,)),
    ), 122880, 14560),
    StageSpec(139584, 219360, (
        matrix(320, 20, 0, 320, list_ids=(0,), require_present=True),
        matrix(320, 20, 102400, 320, list_ids=(1,)),
    ), 204800, 14560),
    StageSpec(358976, 21056, (
        matrix(320, 4, 0, 64, list_ids=(1,), require_present=True),
    ), 20480, 576),
    StageSpec(380032, 70672, (
        matrix(46, 14, 0, 224, dense=True),
        matrix(224, 14, 10304, 224, list_ids=(2, 4, 6, 8)),
    ), 60480, 10192),
    StageSpec(450752, 110544, (
        matrix(224, 14, 0, 224, list_ids=(2, 4, 6, 8), require_present=True),
        matrix(224, 14, 50176, 224, list_ids=(3, 5, 7, 9)),
    ), 100352, 10192),
    StageSpec(561344, 18640, (
        matrix(224, 5, 0, 80, list_ids=(3, 5, 7, 9), require_present=True),
    ), 17920, 720),
    StageSpec(580032, 81424, (
        matrix(94, 14, 0, 224, dense=True),
        matrix(224, 14, 21056, 224, list_ids=(10, 12, 14)),
    ), 71232, 10192),
    StageSpec(661504, 110544, (
        matrix(224, 14, 0, 224, list_ids=(10, 12, 14), require_present=True),
        matrix(224, 14, 50176, 224, list_ids=(11, 13, 15)),
    ), 100352, 10192),
    StageSpec(772096, 44736, (
        matrix(224, 12, 0, 192, list_ids=(11, 13, 15), require_present=True),
    ), 43008, 1728),
    StageSpec(816832, 95760, (
        matrix(158, 14, 0, 224, dense=True),
        matrix(224, 14, 35392, 224, list_ids=(16, 18)),
    ), 85568, 10192),
    StageSpec(912640, 110544, (
        matrix(224, 14, 0, 224, list_ids=(16, 18), require_present=True),
        matrix(224, 14, 50176, 224, list_ids=(17, 19)),
    ), 100352, 10192),
    StageSpec(1023232, 29824, (
        matrix(224, 8, 0, 128, list_ids=(17, 19), require_present=True),
    ), 28672, 1152),
)


def missing() -> Descriptor:
    return Descriptor(False)


def present(*entries: int, **kwargs: object) -> Descriptor:
    return Descriptor(True, tuple(entries), **kwargs)


def plan_reference(
    stage_id: int,
    sparse_enable: bool,
    contexts: dict[int, Descriptor],
) -> tuple[tuple[int, int], tuple[int, int], bool, tuple[int, ...]]:
    if not 0 <= stage_id < len(STAGES):
        raise PlannerFault("invalid stage")

    bitmaps = [0, 0]
    counts = [0, 0]
    inspected: list[int] = []
    eligible_full: list[bool] = []

    for matrix_id, spec in enumerate(STAGES[stage_id].matrices):
        if spec.dense:
            # Mandatory residency is reconstructed by the load service.  The
            # planner never fabricates active bits for this matrix.
            continue

        bitmap = 0
        for logical_id in spec.list_ids:
            descriptor = contexts.get(logical_id, missing())
            inspected.append(logical_id)
            if descriptor.descriptor_error or not descriptor.descriptor_tag_matches:
                raise PlannerFault("bad descriptor response")
            if descriptor.count < 0 or descriptor.count > spec.sources:
                raise PlannerFault("descriptor count out of range")
            if not descriptor.present:
                if descriptor.count != 0:
                    raise PlannerFault("missing descriptor has nonzero count")
                if spec.require_present:
                    raise PlannerFault("missing predecessor")
                continue
            if descriptor.count != len(descriptor.entries):
                raise PlannerFault("incomplete reference list")

            previous = -1
            for ordinal, index in enumerate(descriptor.entries):
                if ordinal == descriptor.list_error_ordinal:
                    raise PlannerFault("list response error")
                if ordinal == descriptor.list_bad_tag_ordinal:
                    raise PlannerFault("bad list response tag")
                if not 0 <= index < spec.sources:
                    raise PlannerFault("list index out of range")
                if index <= previous:
                    raise PlannerFault("list is not strictly increasing")
                bitmap |= 1 << index
                previous = index

        bitmaps[matrix_id] = bitmap
        counts[matrix_id] = bitmap.bit_count()
        eligible_full.append(counts[matrix_id] == spec.sources)

    # Matrix 1 is absent for projection stages and therefore stays zero.
    fallback_full = (not sparse_enable) or all(eligible_full)
    return (bitmaps[0], bitmaps[1]), (counts[0], counts[1]), fallback_full, tuple(inspected)


def layout() -> dict[str, object]:
    return json.loads(LAYOUT_PATH.read_text(encoding="utf-8"))


def test_all_twelve_stage_geometries_match_frozen_v4_json():
    imported = layout()
    assert imported["stage_count"] == len(STAGES) == 12
    for expected, actual in zip(STAGES, imported["stages"], strict=True):
        assert actual["dram_byte_offset"] == expected.dram_offset
        assert actual["transfer_bytes"] == expected.transfer_bytes
        assert actual["matrix_count"] == len(expected.matrices)
        for expected_matrix, actual_matrix in zip(
            expected.matrices, actual["matrices"], strict=True
        ):
            assert actual_matrix["source_count"] == expected_matrix.sources
            assert actual_matrix["row_tiles"] == expected_matrix.row_tiles
            assert actual_matrix["local_byte_offset"] == expected_matrix.local_offset
            assert actual_matrix["source_stride_bytes"] == expected_matrix.source_stride
            assert actual_matrix["payload_bytes"] == (
                expected_matrix.sources * expected_matrix.source_stride
            )
        assert actual["parameters"]["local_byte_offset"] == expected.parameter_offset
        assert actual["parameters"]["payload_bytes"] == expected.parameter_bytes


def test_stage_list_mapping_covers_fullband_and_4_3_2_context_groups():
    expected = (
        ((), (0,)), ((0,), (1,)), ((1,),),
        ((), (2, 4, 6, 8)), ((2, 4, 6, 8), (3, 5, 7, 9)),
        ((3, 5, 7, 9),),
        ((), (10, 12, 14)), ((10, 12, 14), (11, 13, 15)),
        ((11, 13, 15),),
        ((), (16, 18)), ((16, 18), (17, 19)), ((17, 19),),
    )
    assert tuple(tuple(matrix_spec.list_ids for matrix_spec in stage.matrices) for stage in STAGES) == expected
    assert {item for stage in expected for matrix_ids in stage for item in matrix_ids} == set(range(20))
    assert [len(STAGES[index].matrices[-1].list_ids) for index in (3, 6, 9)] == [4, 3, 2]


@pytest.mark.parametrize("stage_id", range(12))
def test_every_stage_builds_expected_union_and_zeroes_mandatory_or_absent(stage_id: int):
    contexts = {logical_id: present(logical_id, logical_id + 32) for logical_id in range(20)}
    bitmaps, counts, fallback, inspected = plan_reference(stage_id, True, contexts)
    expected_inspected = tuple(
        logical_id
        for spec in STAGES[stage_id].matrices
        if not spec.dense
        for logical_id in spec.list_ids
    )
    assert inspected == expected_inspected
    assert counts == tuple(bitmap.bit_count() for bitmap in bitmaps)
    assert not fallback
    if STAGES[stage_id].matrices[0].dense:
        assert bitmaps[0] == counts[0] == 0
    if len(STAGES[stage_id].matrices) == 1:
        assert bitmaps[1] == counts[1] == 0


def test_union_collapses_cross_context_overlap_but_preserves_unique_bits():
    contexts = {
        2: present(1, 3, 7),
        4: present(3, 4, 7),
        6: present(7, 8),
        8: present(1, 9),
        3: present(),
        5: present(),
        7: present(),
        9: present(),
    }
    bitmaps, counts, fallback, _ = plan_reference(4, True, contexts)
    assert bitmaps[0] == sum(1 << index for index in (1, 3, 4, 7, 8, 9))
    assert counts == (6, 0)
    assert bitmaps[1] == 0
    assert not fallback


def test_missing_self_is_empty_but_missing_predecessor_is_always_fatal():
    # Stage 3 has a mandatory input matrix and four optional recurrent selves.
    bitmaps, counts, fallback, inspected = plan_reference(3, True, {})
    assert bitmaps == counts == (0, 0)
    assert not fallback
    assert inspected == (2, 4, 6, 8)

    # A present empty predecessor is valid and semantically distinct from a
    # missing predecessor.
    assert plan_reference(1, True, {0: present()})[1] == (0, 0)
    for sparse_enable in (True, False):
        with pytest.raises(PlannerFault, match="missing predecessor"):
            plan_reference(1, sparse_enable, {})


def test_sparse_disabled_still_inspects_every_descriptor_and_entry():
    contexts = {
        logical_id: present(1, 3) for logical_id in (2, 4, 6, 8, 3, 5, 7, 9)
    }
    _, counts, fallback, inspected = plan_reference(4, False, contexts)
    assert counts == (2, 2)
    assert fallback
    assert inspected == (2, 4, 6, 8, 3, 5, 7, 9)

    contexts[9] = present(1, 224)
    with pytest.raises(PlannerFault, match="out of range"):
        plan_reference(4, False, contexts)


def test_fallback_excludes_mandatory_matrix_and_requires_all_eligible_full():
    full_320 = present(*range(320))
    assert plan_reference(2, True, {1: full_320})[2]
    assert plan_reference(0, True, {0: full_320})[2]

    # Stage 1 has two eligible matrices; only one full union is insufficient.
    _, counts, fallback, _ = plan_reference(1, True, {0: full_320, 1: present(0)})
    assert counts == (320, 1)
    assert not fallback
    assert plan_reference(1, False, {0: full_320, 1: present(0)})[2]


@pytest.mark.parametrize(
    "descriptor,message",
    [
        (present(3, 3), "strictly increasing"),
        (present(4, 2), "strictly increasing"),
        (present(320), "out of range"),
        (present(1, reported_count=321), "count out of range"),
        (Descriptor(False, (), reported_count=1), "nonzero count"),
        (present(1, descriptor_error=True), "descriptor response"),
        (present(1, descriptor_tag_matches=False), "descriptor response"),
        (present(1, list_error_ordinal=0), "list response error"),
        (present(1, list_bad_tag_ordinal=0), "response tag"),
    ],
)
def test_malformed_context_data_fails_closed(descriptor: Descriptor, message: str):
    with pytest.raises(PlannerFault, match=message):
        plan_reference(0, True, {0: descriptor})


def test_rtl_contract_surface_and_resource_intent_are_structurally_explicit():
    planner = (ROOT / "rtl" / "sparse_union_planner_v1.sv").read_text(encoding="utf-8")
    stage_map = (ROOT / "rtl" / "sparse_stage_map_v1.sv").read_text(encoding="utf-8")
    context = (ROOT / "rtl" / "sparse_recurrent_context_store_v1.sv").read_text(encoding="utf-8")

    assert re.search(r"module\s+sparse_union_planner_v1\b", planner)
    assert re.search(r"output\s+reg\s+\[319:0\]\s+plan_bitmap0", planner)
    assert re.search(r"output\s+reg\s+\[319:0\]\s+plan_bitmap1", planner)
    assert re.search(r"output\s+wire\s+plan_valid", planner)
    assert "assign plan_valid = plan_valid_q && ownership_safe" in planner
    for signal in (
        "plan_req_valid", "plan_req_ready", "plan_valid", "plan_ready",
        "plan_stage_id", "plan_sparse_enable", "plan_fallback_full",
        "plan_count0", "plan_count1", "planner_error_valid", "reset_required",
    ):
        assert signal in planner
    assert "!plan_sparse_enable" in planner
    assert "matrix0_union_full &&" in planner
    assert "matrix1_union_full" in planner

    assert re.search(r"module\s+sparse_stage_map_v1\b", stage_map)
    assert len(re.findall(r"^\s*4'd(?:[0-9]|1[01]):\s+begin", stage_map, re.MULTILINE)) == 12
    for stage_id, spec in enumerate(STAGES):
        assert f"4'd{stage_id}: begin" in stage_map
        assert f"stage_dram_byte_offset = 32'd{spec.dram_offset};" in stage_map
        assert f"stage_transfer_bytes = 32'd{spec.transfer_bytes};" in stage_map
        assert f"parameter_local_byte_offset = 32'd{spec.parameter_offset};" in stage_map
        assert f"parameter_transfer_bytes = 32'd{spec.parameter_bytes};" in stage_map

    assert re.search(r"module\s+sparse_recurrent_context_store_v1\b", context)
    assert "output wire                         list_desc_rsp_present" in context
    assert "reg [19:0] logical_list_present_q" in context
    assert "inner_commit_done" in context
    assert (
        "sparse_recurrent_context_store_core_v1 "
        "u_sparse_context_store_core" in context
    )

    # The planner/map are control logic and bitmap registers only.  Any future
    # RAM or DSP primitive/attribute must trigger a deliberate gate update.
    for source in (planner, stage_map):
        lowered = source.lower()
        assert "ram_style" not in lowered
        assert "dsp48" not in lowered
        assert not re.search(r"\b(?:reg|logic)\s+\[[^]]+\]\s+\w+\s*\[[^]]+\]", source)


def test_cp3_files_use_unique_module_names_and_no_parent_path_references():
    created_rtl = [
        ROOT / "rtl" / "sparse_stage_map_v1.sv",
        ROOT / "rtl" / "sparse_union_planner_v1.sv",
        ROOT / "rtl" / "sparse_recurrent_context_store_v1.sv",
    ]
    names = []
    for path in created_rtl:
        text = path.read_text(encoding="utf-8")
        names.extend(re.findall(r"^module\s+(\w+)", text, re.MULTILINE))
        assert "../" not in text
    assert names == [
        "sparse_stage_map_v1",
        "sparse_union_planner_v1",
        "sparse_recurrent_context_store_v1",
    ]
    assert len(names) == len(set(names))
