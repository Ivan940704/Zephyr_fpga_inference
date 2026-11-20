"""Independent Sequential-v4 sparse DDR traffic oracle.

The trace format records the active list produced by each logical context in a
frame.  A stage consumes either a predecessor list produced in the same frame
or a recurrent self-list produced in the previous frame.  This distinction is
required because one logical list is updated in-place during a frame.

All DDR and cache addresses in :class:`CopyRange` are canonical byte offsets:
``image_byte_start`` is relative to the beginning of ``parameters_v4.bin`` and
``cache_byte_start`` is relative to the beginning of the 256 KiB stage cache.
AXI burst addresses add the supplied ``parameter_base_addr``.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from types import MappingProxyType
from typing import Iterable, Mapping, Sequence


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LAYOUT_PATH = (
    ROOT / "imports" / "fixtures" / "v4" / "memory_layout_v4.json"
)

DENSE_BYTES_PER_FRAME = 1_050_544
LUT_BYTES_PER_RESET = 2_040
ZERO_ACTIVE_BYTES_PER_FRAME = 181_680
SPARSE_ELIGIBLE_BYTES_PER_FRAME = 868_864

DEFAULT_BUS_BYTES = 8
DEFAULT_MAX_BURST_BEATS = 16
AXI_BOUNDARY_BYTES = 4096
CACHE_BYTES = 262_144
FRAME_STAGE_ORDER = (0, 1, 2, 3, 6, 9, 4, 7, 10, 5, 8, 11)

# FB GSU lists contain at most 320 indices; every SB GSU list contains at most
# 224.  Logical IDs and their layer/context meanings come from the imported
# sequential-v4 context-store/controller contract.
LOGICAL_SOURCE_CAPACITY = MappingProxyType(
    {**{logical_id: 320 for logical_id in (0, 1)},
     **{logical_id: 224 for logical_id in range(2, 20)}}
)


class OracleError(ValueError):
    """Raised when a layout, trace, address, or traffic contract is invalid."""


class TraceFormatError(OracleError):
    """Raised when an active-list trace violates its versioned schema."""


@dataclass(frozen=True)
class ListRequirement:
    """The active-list generation required by one sparse matrix."""

    logical_ids: tuple[int, ...]
    frame_delta: int
    relationship: str
    missing_is_empty: bool


@dataclass(frozen=True)
class MatrixRule:
    matrix_id: int
    dense: bool
    requirement: ListRequirement | None = None


@dataclass(frozen=True)
class StageRule:
    stage_id: int
    branch: int
    context_count: int
    matrices: tuple[MatrixRule, ...]


def _self(logical_ids: tuple[int, ...]) -> ListRequirement:
    return ListRequirement(
        logical_ids=logical_ids,
        frame_delta=-1,
        relationship="recurrent_self",
        missing_is_empty=True,
    )


def _predecessor(logical_ids: tuple[int, ...]) -> ListRequirement:
    return ListRequirement(
        logical_ids=logical_ids,
        frame_delta=0,
        relationship="predecessor",
        missing_is_empty=False,
    )


def _dense(matrix_id: int = 0) -> MatrixRule:
    return MatrixRule(matrix_id=matrix_id, dense=True)


def _sparse(matrix_id: int, requirement: ListRequirement) -> MatrixRule:
    return MatrixRule(
        matrix_id=matrix_id,
        dense=False,
        requirement=requirement,
    )


# Exact stage/list mapping derived from context_identity() and the matrix-list
# selection in the imported sequential_pe_job_controller.v.  Subband contexts
# are unioned matrix-wise because a stage is loaded once and then reused by all
# contexts in that branch.
STAGE_RULES = (
    StageRule(0, 0, 1, (_dense(), _sparse(1, _self((0,))))),
    StageRule(1, 0, 1, (_sparse(0, _predecessor((0,))),
                        _sparse(1, _self((1,))))),
    StageRule(2, 0, 1, (_sparse(0, _predecessor((1,))),)),
    StageRule(3, 1, 4, (_dense(), _sparse(1, _self((2, 4, 6, 8))))),
    StageRule(4, 1, 4, (_sparse(0, _predecessor((2, 4, 6, 8))),
                        _sparse(1, _self((3, 5, 7, 9))))),
    StageRule(5, 1, 4, (_sparse(0, _predecessor((3, 5, 7, 9))),)),
    StageRule(6, 2, 3, (_dense(), _sparse(1, _self((10, 12, 14))))),
    StageRule(7, 2, 3, (_sparse(0, _predecessor((10, 12, 14))),
                        _sparse(1, _self((11, 13, 15))))),
    StageRule(8, 2, 3, (_sparse(0, _predecessor((11, 13, 15))),)),
    StageRule(9, 3, 2, (_dense(), _sparse(1, _self((16, 18))))),
    StageRule(10, 3, 2, (_sparse(0, _predecessor((16, 18))),
                         _sparse(1, _self((17, 19))))),
    StageRule(11, 3, 2, (_sparse(0, _predecessor((17, 19))),)),
)


@dataclass(frozen=True)
class ActiveListTrace:
    """Validated mapping from ``(frame_id, logical_id)`` to active indices."""

    name: str
    records: Mapping[tuple[int, int], tuple[int, ...]]
    description: str = ""

    @classmethod
    def from_records(
        cls,
        records: Iterable[Mapping[str, object]],
        *,
        name: str = "inline",
        description: str = "",
    ) -> "ActiveListTrace":
        validated: dict[tuple[int, int], tuple[int, ...]] = {}
        for ordinal, record in enumerate(records):
            if not isinstance(record, Mapping):
                raise TraceFormatError(f"record {ordinal} must be an object")
            expected_keys = {
                "frame_id",
                "logical_id",
                "ordered_active_indices",
            }
            if set(record) != expected_keys:
                raise TraceFormatError(
                    f"record {ordinal} keys must be {sorted(expected_keys)}"
                )

            frame_id = _plain_int(record["frame_id"], f"record {ordinal} frame_id")
            logical_id = _plain_int(
                record["logical_id"], f"record {ordinal} logical_id"
            )
            if frame_id < 0:
                raise TraceFormatError(f"record {ordinal} frame_id must be >= 0")
            if logical_id not in LOGICAL_SOURCE_CAPACITY:
                raise TraceFormatError(
                    f"record {ordinal} logical_id must be in 0..19"
                )

            raw_indices = record["ordered_active_indices"]
            if not isinstance(raw_indices, list):
                raise TraceFormatError(
                    f"record {ordinal} ordered_active_indices must be an array"
                )
            indices = tuple(
                _plain_int(value, f"record {ordinal} index {index_ordinal}")
                for index_ordinal, value in enumerate(raw_indices)
            )
            capacity = LOGICAL_SOURCE_CAPACITY[logical_id]
            if len(indices) > capacity:
                raise TraceFormatError(
                    f"record {ordinal} has {len(indices)} indices; capacity is {capacity}"
                )
            previous = -1
            for index in indices:
                if not 0 <= index < capacity:
                    raise TraceFormatError(
                        f"record {ordinal} index {index} is outside 0..{capacity - 1}"
                    )
                if index <= previous:
                    raise TraceFormatError(
                        f"record {ordinal} indices must be strictly increasing"
                    )
                previous = index

            key = (frame_id, logical_id)
            if key in validated:
                raise TraceFormatError(
                    f"duplicate record for frame {frame_id}, logical {logical_id}"
                )
            validated[key] = indices

        return cls(
            name=name,
            records=MappingProxyType(validated),
            description=description,
        )

    @classmethod
    def load(cls, path: Path | str) -> "ActiveListTrace":
        trace_path = Path(path)
        try:
            payload = json.loads(trace_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise TraceFormatError(f"cannot read trace {trace_path}: {error}") from error
        if not isinstance(payload, dict):
            raise TraceFormatError("trace root must be an object")
        allowed_keys = {"format_version", "name", "description", "records"}
        if not set(payload) <= allowed_keys:
            extra = sorted(set(payload) - allowed_keys)
            raise TraceFormatError(f"unexpected trace keys: {extra}")
        if payload.get("format_version") != 1:
            raise TraceFormatError("trace format_version must be 1")
        name = payload.get("name")
        records = payload.get("records")
        description = payload.get("description", "")
        if not isinstance(name, str) or not name:
            raise TraceFormatError("trace name must be a non-empty string")
        if not isinstance(description, str):
            raise TraceFormatError("trace description must be a string")
        if not isinstance(records, list):
            raise TraceFormatError("trace records must be an array")
        return cls.from_records(records, name=name, description=description)

    def get(self, frame_id: int, logical_id: int) -> tuple[int, ...] | None:
        return self.records.get((frame_id, logical_id))


@dataclass(frozen=True)
class MatrixGeometry:
    matrix_id: int
    source_count: int
    row_tiles: int
    word_bytes: int
    source_stride_bytes: int
    local_byte_offset: int
    payload_bytes: int


@dataclass(frozen=True)
class ParameterGeometry:
    row_tiles: int
    record_bytes: int
    local_byte_offset: int
    payload_bytes: int


@dataclass(frozen=True)
class StageGeometry:
    stage_id: int
    kind: str
    image_byte_offset: int
    transfer_bytes: int
    matrices: tuple[MatrixGeometry, ...]
    parameters: ParameterGeometry


@dataclass(frozen=True)
class V4Layout:
    image_bytes: int
    cache_bytes: int
    bus_bytes: int
    lut_image_byte_offset: int
    lut_transfer_bytes: int
    stages: tuple[StageGeometry, ...]

    def stage(self, stage_id: int) -> StageGeometry:
        if not 0 <= stage_id < len(self.stages):
            raise OracleError(f"stage_id {stage_id} is outside 0..11")
        stage = self.stages[stage_id]
        if stage.stage_id != stage_id:
            raise OracleError("layout stage tuple is not ID-indexed")
        return stage


@dataclass(frozen=True)
class CopyRange:
    stage_id: int | None
    region: str
    matrix_id: int | None
    first_source: int | None
    source_count: int | None
    image_byte_start: int
    cache_byte_start: int
    byte_count: int

    @property
    def image_byte_end(self) -> int:
        return self.image_byte_start + self.byte_count

    @property
    def cache_byte_end(self) -> int:
        return self.cache_byte_start + self.byte_count


@dataclass(frozen=True)
class AxiBurst:
    source_address: int
    cache_byte_start: int
    accepted_r_beats: int
    bus_bytes: int

    @property
    def byte_count(self) -> int:
        return self.accepted_r_beats * self.bus_bytes

    @property
    def arlen(self) -> int:
        return self.accepted_r_beats - 1

    @property
    def source_address_end(self) -> int:
        return self.source_address + self.byte_count


@dataclass(frozen=True)
class MatrixSelection:
    matrix_id: int
    dense: bool
    relationship: str
    logical_ids: tuple[int, ...]
    source_frame_id: int | None
    active_sources: tuple[int, ...]


@dataclass(frozen=True)
class StageTraffic:
    stage_id: int
    matrix_selections: tuple[MatrixSelection, ...]
    copy_ranges: tuple[CopyRange, ...]
    axi_bursts: tuple[AxiBurst, ...]
    full_load_fallback: bool

    @property
    def planned_bytes(self) -> int:
        return sum(copy_range.byte_count for copy_range in self.copy_ranges)

    @property
    def copy_commands(self) -> int:
        return len(self.copy_ranges)

    @property
    def ar_burst_count(self) -> int:
        return len(self.axi_bursts)

    @property
    def accepted_r_beats(self) -> int:
        return sum(burst.accepted_r_beats for burst in self.axi_bursts)


@dataclass(frozen=True)
class FrameTraffic:
    frame_id: int
    stages: tuple[StageTraffic, ...]

    @property
    def planned_bytes(self) -> int:
        return sum(stage.planned_bytes for stage in self.stages)

    @property
    def copy_commands(self) -> int:
        return sum(stage.copy_commands for stage in self.stages)

    @property
    def ar_burst_count(self) -> int:
        return sum(stage.ar_burst_count for stage in self.stages)

    @property
    def accepted_r_beats(self) -> int:
        return sum(stage.accepted_r_beats for stage in self.stages)


@dataclass(frozen=True)
class LutTraffic:
    copy_range: CopyRange
    axi_bursts: tuple[AxiBurst, ...]

    @property
    def planned_bytes(self) -> int:
        return self.copy_range.byte_count

    @property
    def accepted_r_beats(self) -> int:
        return sum(burst.accepted_r_beats for burst in self.axi_bursts)


def _plain_int(value: object, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise TraceFormatError(f"{label} must be an integer")
    return value


def load_v4_layout(path: Path | str = DEFAULT_LAYOUT_PATH) -> V4Layout:
    """Load and strictly validate the imported v4 geometry."""

    layout_path = Path(path)
    try:
        raw = json.loads(layout_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise OracleError(f"cannot read layout {layout_path}: {error}") from error

    if raw.get("format_version") != 4:
        raise OracleError("only memory layout format_version 4 is supported")
    bus_bytes = raw.get("bus_bytes")
    cache_bytes = raw.get("cache_bytes")
    image_bytes = raw.get("image_bytes")
    if bus_bytes != DEFAULT_BUS_BYTES:
        raise OracleError("v4 oracle requires an 8-byte AXI data bus")
    if cache_bytes != CACHE_BYTES:
        raise OracleError("v4 oracle requires the 256 KiB cache")
    if raw.get("stage_count") != 12 or len(raw.get("stages", ())) != 12:
        raise OracleError("v4 oracle requires exactly 12 stages")

    stages: list[StageGeometry] = []
    previous_image_end = 0
    for expected_stage_id, item in enumerate(raw["stages"]):
        if item.get("id") != expected_stage_id:
            raise OracleError("layout stages must be ordered by IDs 0..11")
        matrices: list[MatrixGeometry] = []
        local_cursor = 0
        for expected_matrix_id, matrix in enumerate(item["matrices"]):
            if matrix.get("id") != expected_matrix_id:
                raise OracleError(
                    f"stage {expected_stage_id} matrix IDs must be contiguous"
                )
            geometry = MatrixGeometry(
                matrix_id=expected_matrix_id,
                source_count=matrix["source_count"],
                row_tiles=matrix["row_tiles"],
                word_bytes=matrix["word_bytes"],
                source_stride_bytes=matrix["source_stride_bytes"],
                local_byte_offset=matrix["local_byte_offset"],
                payload_bytes=matrix["payload_bytes"],
            )
            if geometry.word_bytes != 16:
                raise OracleError("each source row tile must be 16 bytes")
            if geometry.source_stride_bytes != geometry.row_tiles * 16:
                raise OracleError("source stride must equal row_tiles * 16 bytes")
            if geometry.payload_bytes != (
                geometry.source_count * geometry.source_stride_bytes
            ):
                raise OracleError("matrix payload does not match its geometry")
            if geometry.local_byte_offset != local_cursor:
                raise OracleError("matrix regions must be canonical and contiguous")
            local_cursor += geometry.payload_bytes
            matrices.append(geometry)

        parameters_raw = item["parameters"]
        parameters = ParameterGeometry(
            row_tiles=parameters_raw["row_tiles"],
            record_bytes=parameters_raw["record_bytes"],
            local_byte_offset=parameters_raw["local_byte_offset"],
            payload_bytes=parameters_raw["payload_bytes"],
        )
        if parameters.local_byte_offset != local_cursor:
            raise OracleError("parameter region must follow the matrix regions")
        if parameters.payload_bytes != parameters.row_tiles * parameters.record_bytes:
            raise OracleError("parameter payload does not match its record geometry")
        if local_cursor + parameters.payload_bytes != item["transfer_bytes"]:
            raise OracleError("stage transfer must end at the parameter payload end")
        if item["transfer_bytes"] > cache_bytes:
            raise OracleError("stage transfer exceeds the cache")
        if item["dram_byte_offset"] < previous_image_end:
            raise OracleError("stage image regions overlap")
        if item["dram_byte_offset"] + item["transfer_bytes"] > image_bytes:
            raise OracleError("stage image region exceeds the image")
        for value in (
            item["dram_byte_offset"],
            item["transfer_bytes"],
            parameters.local_byte_offset,
            parameters.payload_bytes,
        ):
            if value % bus_bytes:
                raise OracleError("all command ranges must be AXI-beat aligned")

        stages.append(
            StageGeometry(
                stage_id=expected_stage_id,
                kind=item["kind"],
                image_byte_offset=item["dram_byte_offset"],
                transfer_bytes=item["transfer_bytes"],
                matrices=tuple(matrices),
                parameters=parameters,
            )
        )
        previous_image_end = item["dram_byte_offset"] + item["transfer_bytes"]

    lut = raw["global_sigmoid_lut"]
    result = V4Layout(
        image_bytes=image_bytes,
        cache_bytes=cache_bytes,
        bus_bytes=bus_bytes,
        lut_image_byte_offset=lut["dram_byte_offset"],
        lut_transfer_bytes=lut["transfer_bytes"],
        stages=tuple(stages),
    )
    if sum(stage.transfer_bytes for stage in result.stages) != DENSE_BYTES_PER_FRAME:
        raise OracleError("unexpected dense v4 traffic baseline")
    if result.lut_transfer_bytes != LUT_BYTES_PER_RESET:
        raise OracleError("unexpected reset-epoch LUT transfer")
    fixed_bytes = sum(stage.parameters.payload_bytes for stage in result.stages)
    fixed_bytes += sum(result.stage(stage_id).matrices[0].payload_bytes
                       for stage_id in (0, 3, 6, 9))
    if fixed_bytes != ZERO_ACTIVE_BYTES_PER_FRAME:
        raise OracleError("unexpected zero-active v4 traffic floor")
    if DENSE_BYTES_PER_FRAME - fixed_bytes != SPARSE_ELIGIBLE_BYTES_PER_FRAME:
        raise OracleError("unexpected sparse-eligible v4 byte count")
    return result


def contiguous_source_runs(indices: Sequence[int]) -> tuple[tuple[int, int], ...]:
    """Return ``(first_source, source_count)`` for sorted contiguous runs."""

    if not indices:
        return ()
    runs: list[tuple[int, int]] = []
    first = indices[0]
    previous = first
    if first < 0:
        raise OracleError("source indices must be non-negative")
    for index in indices[1:]:
        if index <= previous:
            raise OracleError("source indices must be strictly increasing")
        if index != previous + 1:
            runs.append((first, previous - first + 1))
            first = index
        previous = index
    runs.append((first, previous - first + 1))
    return tuple(runs)


def split_axi_transfer(
    source_address: int,
    cache_byte_start: int,
    byte_count: int,
    *,
    bus_bytes: int = DEFAULT_BUS_BYTES,
    max_burst_beats: int = DEFAULT_MAX_BURST_BEATS,
    boundary_bytes: int = AXI_BOUNDARY_BYTES,
) -> tuple[AxiBurst, ...]:
    """Split one copy command exactly as ``memory.v`` splits AXI AR bursts."""

    for label, value in (
        ("source_address", source_address),
        ("cache_byte_start", cache_byte_start),
        ("byte_count", byte_count),
    ):
        if isinstance(value, bool) or not isinstance(value, int) or value < 0:
            raise OracleError(f"{label} must be a non-negative integer")
    if byte_count == 0:
        return ()
    if bus_bytes <= 0 or boundary_bytes <= 0 or max_burst_beats <= 0:
        raise OracleError("AXI split constants must be positive")
    if boundary_bytes % bus_bytes:
        raise OracleError("AXI boundary must contain whole beats")
    if source_address % bus_bytes or cache_byte_start % bus_bytes:
        raise OracleError("AXI source and cache destination must be beat aligned")
    if byte_count % bus_bytes:
        raise OracleError("AXI byte_count must be a whole number of beats")

    remaining_beats = byte_count // bus_bytes
    source = source_address
    destination = cache_byte_start
    bursts: list[AxiBurst] = []
    while remaining_beats:
        bytes_to_boundary = boundary_bytes - (source % boundary_bytes)
        beats_to_boundary = bytes_to_boundary // bus_bytes
        beats = min(remaining_beats, max_burst_beats, beats_to_boundary)
        if beats <= 0:
            raise OracleError("AXI burst splitter made no progress")
        bursts.append(
            AxiBurst(
                source_address=source,
                cache_byte_start=destination,
                accepted_r_beats=beats,
                bus_bytes=bus_bytes,
            )
        )
        advanced = beats * bus_bytes
        source += advanced
        destination += advanced
        remaining_beats -= beats
    return tuple(bursts)


def accepted_r_bytes(
    accepted_r_beats: int, *, bus_bytes: int = DEFAULT_BUS_BYTES
) -> int:
    """Reference movement counter: accepted AXI R beats multiplied by 8."""

    if (
        isinstance(accepted_r_beats, bool)
        or not isinstance(accepted_r_beats, int)
        or accepted_r_beats < 0
    ):
        raise OracleError("accepted_r_beats must be a non-negative integer")
    if bus_bytes != DEFAULT_BUS_BYTES:
        raise OracleError("Sequential-v4 movement accounting requires 8-byte beats")
    return accepted_r_beats * bus_bytes


def stage_rule(stage_id: int) -> StageRule:
    if not 0 <= stage_id < len(STAGE_RULES):
        raise OracleError(f"stage_id {stage_id} is outside 0..11")
    rule = STAGE_RULES[stage_id]
    if rule.stage_id != stage_id:
        raise OracleError("stage rule tuple is not ID-indexed")
    return rule


def _matrix_active_sources(
    trace: ActiveListTrace,
    *,
    frame_id: int,
    matrix: MatrixGeometry,
    rule: MatrixRule,
) -> MatrixSelection:
    if rule.dense:
        return MatrixSelection(
            matrix_id=matrix.matrix_id,
            dense=True,
            relationship="dense_input",
            logical_ids=(),
            source_frame_id=None,
            active_sources=tuple(range(matrix.source_count)),
        )

    requirement = rule.requirement
    if requirement is None:
        raise OracleError("sparse matrix rule is missing its list requirement")
    source_frame_id = frame_id + requirement.frame_delta
    union: set[int] = set()
    for logical_id in requirement.logical_ids:
        indices = None if source_frame_id < 0 else trace.get(source_frame_id, logical_id)
        if indices is None:
            if requirement.missing_is_empty:
                continue
            raise OracleError(
                f"stage matrix {matrix.matrix_id} requires frame {source_frame_id} "
                f"logical list {logical_id}"
            )
        for source in indices:
            if source >= matrix.source_count:
                raise OracleError(
                    f"logical list {logical_id} source {source} exceeds matrix "
                    f"source_count {matrix.source_count}"
                )
            union.add(source)
    return MatrixSelection(
        matrix_id=matrix.matrix_id,
        dense=False,
        relationship=requirement.relationship,
        logical_ids=requirement.logical_ids,
        source_frame_id=source_frame_id,
        active_sources=tuple(sorted(union)),
    )


def plan_stage(
    layout: V4Layout,
    trace: ActiveListTrace,
    *,
    frame_id: int,
    stage_id: int,
    parameter_base_addr: int = 0,
    max_burst_beats: int = DEFAULT_MAX_BURST_BEATS,
) -> StageTraffic:
    """Plan canonical sparse copy commands and their accepted AXI R bursts."""

    if isinstance(frame_id, bool) or not isinstance(frame_id, int) or frame_id < 0:
        raise OracleError("frame_id must be a non-negative integer")
    if (
        isinstance(parameter_base_addr, bool)
        or not isinstance(parameter_base_addr, int)
        or not 0 <= parameter_base_addr < (1 << 32)
        or parameter_base_addr % 64
    ):
        raise OracleError("parameter_base_addr must be a 64-byte-aligned uint32")

    stage = layout.stage(stage_id)
    rule = stage_rule(stage_id)
    if len(stage.matrices) != len(rule.matrices):
        raise OracleError(f"stage {stage_id} matrix count disagrees with its rule")

    selections: list[MatrixSelection] = []
    ranges: list[CopyRange] = []
    for matrix, matrix_rule in zip(stage.matrices, rule.matrices, strict=True):
        if matrix.matrix_id != matrix_rule.matrix_id:
            raise OracleError(f"stage {stage_id} matrix IDs disagree with their rule")
        selection = _matrix_active_sources(
            trace,
            frame_id=frame_id,
            matrix=matrix,
            rule=matrix_rule,
        )
        selections.append(selection)
        for first_source, source_count in contiguous_source_runs(
            selection.active_sources
        ):
            local_start = (
                matrix.local_byte_offset
                + first_source * matrix.source_stride_bytes
            )
            ranges.append(
                CopyRange(
                    stage_id=stage_id,
                    region="matrix",
                    matrix_id=matrix.matrix_id,
                    first_source=first_source,
                    source_count=source_count,
                    image_byte_start=stage.image_byte_offset + local_start,
                    cache_byte_start=local_start,
                    byte_count=source_count * matrix.source_stride_bytes,
                )
            )

    parameters = stage.parameters
    ranges.append(
        CopyRange(
            stage_id=stage_id,
            region="parameters",
            matrix_id=None,
            first_source=None,
            source_count=None,
            image_byte_start=stage.image_byte_offset + parameters.local_byte_offset,
            cache_byte_start=parameters.local_byte_offset,
            byte_count=parameters.payload_bytes,
        )
    )
    ranges.sort(key=lambda item: item.cache_byte_start)

    # The v1 contract retains the original one-command dense path.  Besides
    # avoiding needless command boundaries, this makes a fully active sparse
    # trace reproduce the existing dense loader behavior as well as its byte
    # count.
    full_load_fallback = (
        sum(copy_range.byte_count for copy_range in ranges)
        == stage.transfer_bytes
    )
    if full_load_fallback:
        ranges = [
            CopyRange(
                stage_id=stage_id,
                region="full_stage",
                matrix_id=None,
                first_source=None,
                source_count=None,
                image_byte_start=stage.image_byte_offset,
                cache_byte_start=0,
                byte_count=stage.transfer_bytes,
            )
        ]

    bursts: list[AxiBurst] = []
    for copy_range in ranges:
        if copy_range.image_byte_end > layout.image_bytes:
            raise OracleError("copy range exceeds the v4 image")
        if copy_range.cache_byte_end > layout.cache_bytes:
            raise OracleError("copy range exceeds the stage cache")
        source_address = parameter_base_addr + copy_range.image_byte_start
        if source_address + copy_range.byte_count > (1 << 32):
            raise OracleError("copy range overflows the 32-bit AXI address space")
        bursts.extend(
            split_axi_transfer(
                source_address,
                copy_range.cache_byte_start,
                copy_range.byte_count,
                bus_bytes=layout.bus_bytes,
                max_burst_beats=max_burst_beats,
            )
        )

    result = StageTraffic(
        stage_id=stage_id,
        matrix_selections=tuple(selections),
        copy_ranges=tuple(ranges),
        axi_bursts=tuple(bursts),
        full_load_fallback=full_load_fallback,
    )
    if accepted_r_bytes(result.accepted_r_beats) != result.planned_bytes:
        raise OracleError("accepted AXI R beats do not equal planned stage bytes")
    return result


def plan_frame(
    layout: V4Layout,
    trace: ActiveListTrace,
    *,
    frame_id: int,
    parameter_base_addr: int = 0,
    max_burst_beats: int = DEFAULT_MAX_BURST_BEATS,
) -> FrameTraffic:
    """Plan all twelve stage loads in the validated shared-engine order."""

    stages = tuple(
        plan_stage(
            layout,
            trace,
            frame_id=frame_id,
            stage_id=stage_id,
            parameter_base_addr=parameter_base_addr,
            max_burst_beats=max_burst_beats,
        )
        for stage_id in FRAME_STAGE_ORDER
    )
    result = FrameTraffic(frame_id=frame_id, stages=stages)
    if accepted_r_bytes(result.accepted_r_beats) != result.planned_bytes:
        raise OracleError("accepted AXI R beats do not equal planned frame bytes")
    return result


def plan_lut_transfer(
    layout: V4Layout,
    *,
    parameter_base_addr: int = 0,
    max_burst_beats: int = DEFAULT_MAX_BURST_BEATS,
) -> LutTraffic:
    """Plan the once-per-reset-epoch global sigmoid LUT transfer."""

    if (
        isinstance(parameter_base_addr, bool)
        or not isinstance(parameter_base_addr, int)
        or not 0 <= parameter_base_addr < (1 << 32)
        or parameter_base_addr % 64
    ):
        raise OracleError("parameter_base_addr must be a 64-byte-aligned uint32")
    copy_range = CopyRange(
        stage_id=None,
        region="global_lut",
        matrix_id=None,
        first_source=None,
        source_count=None,
        image_byte_start=layout.lut_image_byte_offset,
        cache_byte_start=0,
        byte_count=layout.lut_transfer_bytes,
    )
    source_address = parameter_base_addr + copy_range.image_byte_start
    if source_address + copy_range.byte_count > (1 << 32):
        raise OracleError("LUT transfer overflows the 32-bit AXI address space")
    bursts = split_axi_transfer(
        source_address,
        0,
        copy_range.byte_count,
        bus_bytes=layout.bus_bytes,
        max_burst_beats=max_burst_beats,
    )
    result = LutTraffic(copy_range=copy_range, axi_bursts=bursts)
    if accepted_r_bytes(result.accepted_r_beats) != LUT_BYTES_PER_RESET:
        raise OracleError("accepted AXI R beats do not equal LUT bytes")
    return result
