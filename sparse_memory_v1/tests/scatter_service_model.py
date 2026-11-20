"""Executable CP4 reference model for canonical-address sparse scatter fill."""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "imports" / "fixtures" / "v4"
CACHE_BYTES = 256 * 1024
AXI_BEAT_BYTES = 8
MAX_BURST_BEATS = 16
MANDATORY_DENSE_MATRIX0 = frozenset({0, 3, 6, 9})


class ScatterFault(RuntimeError):
    """A fail-closed planning, loading, or residency violation."""


@dataclass(frozen=True)
class CopyCommand:
    kind: str
    matrix: int | None
    first_source: int | None
    source_count: int | None
    src_addr: int
    cache_byte_offset: int
    byte_count: int

    @property
    def accepted_r_bytes(self) -> int:
        return self.byte_count


def load_layout() -> dict:
    return json.loads((FIXTURE / "memory_layout_v4.json").read_text(encoding="utf-8"))


def contiguous_runs(bits: int, limit: int) -> list[tuple[int, int]]:
    """Return half-open runs of set bits and reject bits outside the domain."""

    if bits < 0 or bits >> limit:
        raise ScatterFault("bitmap contains an out-of-range source")
    runs: list[tuple[int, int]] = []
    index = 0
    while index < limit:
        if not ((bits >> index) & 1):
            index += 1
            continue
        end = index + 1
        while end < limit and ((bits >> end) & 1):
            end += 1
        runs.append((index, end))
        index = end
    return runs


def full_bitmap(source_count: int) -> int:
    return (1 << source_count) - 1


def _checked_command(
    *,
    kind: str,
    matrix: int | None,
    first_source: int | None,
    source_count: int | None,
    image_base: int,
    image_bytes: int,
    stage_offset: int,
    local_offset: int,
    cache_offset: int,
    byte_count: int,
) -> CopyCommand:
    src = image_base + stage_offset + local_offset
    src_end = src + byte_count
    image_end = image_base + image_bytes
    cache_end = cache_offset + byte_count
    if image_base < 0 or image_base >= (1 << 32):
        raise ScatterFault("parameter base is outside the 32-bit AXI domain")
    if (image_end >= (1 << 32) or src < image_base or
            src_end > image_end or src_end >= (1 << 32)):
        raise ScatterFault("33-bit source bounds check failed")
    if cache_offset < 0 or cache_end > CACHE_BYTES:
        raise ScatterFault("33-bit cache bounds check failed")
    if byte_count <= 0 or (src | cache_offset | byte_count) & (AXI_BEAT_BYTES - 1):
        raise ScatterFault("copy command must be nonzero and AXI-beat aligned")
    return CopyCommand(
        kind=kind,
        matrix=matrix,
        first_source=first_source,
        source_count=source_count,
        src_addr=src,
        cache_byte_offset=cache_offset,
        byte_count=byte_count,
    )


def build_stage_commands(
    stage_id: int,
    matrix_bitmaps: tuple[int, int] = (0, 0),
    *,
    sparse_enable: bool = True,
    image_base: int = 0,
    layout: dict | None = None,
) -> tuple[list[CopyCommand], tuple[int, int], bool]:
    """Build canonical scatter commands and return effective residency/fallback."""

    layout = layout or load_layout()
    if not 0 <= stage_id < len(layout["stages"]):
        raise ScatterFault("invalid stage")
    if image_base < 0 or image_base >= (1 << 32) or (image_base & 0x3F):
        raise ScatterFault("parameter base must be 64-byte aligned in AXI space")
    stage = layout["stages"][stage_id]
    matrices = stage["matrices"]
    effective = [matrix_bitmaps[0], matrix_bitmaps[1]]
    if stage_id in MANDATORY_DENSE_MATRIX0 and effective[0]:
        raise ScatterFault("mandatory dense matrix bitmap must be zero")
    for matrix_id, matrix in enumerate(matrices):
        contiguous_runs(effective[matrix_id], matrix["source_count"])
    if len(matrices) == 1 and effective[1]:
        raise ScatterFault("projection stage has no matrix1")
    if stage_id in MANDATORY_DENSE_MATRIX0:
        effective[0] = full_bitmap(matrices[0]["source_count"])

    union_is_dense = all(
        effective[matrix_id] == full_bitmap(matrix["source_count"])
        for matrix_id, matrix in enumerate(matrices)
    )
    dense_fallback = (not sparse_enable) or union_is_dense
    if dense_fallback:
        command = _checked_command(
            kind="dense_stage",
            matrix=None,
            first_source=None,
            source_count=None,
            image_base=image_base,
            image_bytes=layout["image_bytes"],
            stage_offset=stage["dram_byte_offset"],
            local_offset=0,
            cache_offset=0,
            byte_count=stage["transfer_bytes"],
        )
        residency = tuple(
            full_bitmap(matrix["source_count"]) if index < len(matrices) else 0
            for index, matrix in enumerate(matrices)
        )
        if len(residency) == 1:
            residency = (residency[0], 0)
        return [command], residency, True

    commands: list[CopyCommand] = []
    for matrix_id, matrix in enumerate(matrices):
        stride = matrix["source_stride_bytes"]
        for begin, end in contiguous_runs(effective[matrix_id], matrix["source_count"]):
            commands.append(
                _checked_command(
                    kind="matrix_run",
                    matrix=matrix_id,
                    first_source=begin,
                    source_count=end - begin,
                    image_base=image_base,
                    image_bytes=layout["image_bytes"],
                    stage_offset=stage["dram_byte_offset"],
                    local_offset=matrix["local_byte_offset"] + begin * stride,
                    cache_offset=matrix["local_byte_offset"] + begin * stride,
                    byte_count=(end - begin) * stride,
                )
            )

    param = stage["parameters"]
    commands.append(
        _checked_command(
            kind="parameters",
            matrix=None,
            first_source=None,
            source_count=None,
            image_base=image_base,
            image_bytes=layout["image_bytes"],
            stage_offset=stage["dram_byte_offset"],
            local_offset=param["local_byte_offset"],
            cache_offset=param["local_byte_offset"],
            byte_count=param["payload_bytes"],
        )
    )
    return commands, (effective[0], effective[1]), False


def axi_bursts(command: CopyCommand, max_beats: int = MAX_BURST_BEATS) -> list[tuple[int, int]]:
    """Return (address, beats) for one-command-at-a-time AXI4 reads."""

    if max_beats < 1 or max_beats > 256:
        raise ScatterFault("invalid maximum burst size")
    address = command.src_addr
    beats_left = command.byte_count // AXI_BEAT_BYTES
    result: list[tuple[int, int]] = []
    while beats_left:
        boundary_beats = (4096 - (address & 0xFFF)) // AXI_BEAT_BYTES
        beats = min(beats_left, max_beats, boundary_beats)
        if beats <= 0:
            raise ScatterFault("unaligned address reached a 4 KiB boundary")
        result.append((address, beats))
        address += beats * AXI_BEAT_BYTES
        beats_left -= beats
    return result


class ScatterServiceModel:
    """Transaction model with atomic residency publication and fatal holes."""

    def __init__(self, image: bytes, *, image_base: int = 0):
        self.layout = load_layout()
        if len(image) != self.layout["image_bytes"]:
            raise ScatterFault("image size mismatch")
        if hashlib.sha256(image).hexdigest() != self.layout["image_sha256"]:
            raise ScatterFault("image hash mismatch")
        self.image = image
        self.image_base = image_base
        self.cache = bytearray([0xA5]) * CACHE_BYTES
        self.active_stage: int | None = None
        self.residency = (0, 0)
        self.fatal = False
        self.last_commands: list[CopyCommand] = []
        self.actual_bytes = 0
        self.ar_bursts = 0

    def load(
        self,
        stage_id: int,
        bitmaps: tuple[int, int],
        *,
        sparse_enable: bool = True,
        fail_after_commands: int | None = None,
    ) -> None:
        if self.fatal or self.active_stage is not None:
            raise ScatterFault("service is not empty")
        try:
            commands, tentative_residency, _ = build_stage_commands(
                stage_id,
                bitmaps,
                sparse_enable=sparse_enable,
                image_base=self.image_base,
                layout=self.layout,
            )
        except ScatterFault:
            self.fatal = True
            raise
        self.last_commands = commands
        self.actual_bytes = 0
        self.ar_bursts = 0
        for ordinal, command in enumerate(commands):
            if fail_after_commands is not None and ordinal == fail_after_commands:
                self.fatal = True
                raise ScatterFault("injected partial-load failure")
            source = command.src_addr - self.image_base
            destination = command.cache_byte_offset
            self.cache[destination : destination + command.byte_count] = self.image[
                source : source + command.byte_count
            ]
            self.actual_bytes += command.accepted_r_bytes
            self.ar_bursts += len(axi_bursts(command))
        # This is the only atomic publication point.
        self.residency = tentative_residency
        self.active_stage = stage_id

    def release(self, stage_id: int) -> None:
        if stage_id != self.active_stage:
            self.fatal = True
            raise ScatterFault("stage release identity mismatch")
        self.active_stage = None
        self.residency = (0, 0)

    def read_weight(self, matrix_id: int, source: int, row_tile: int) -> bytes:
        if self.fatal or self.active_stage is None:
            raise ScatterFault("no resident stage")
        stage = self.layout["stages"][self.active_stage]
        if matrix_id >= len(stage["matrices"]):
            self.fatal = True
            raise ScatterFault("invalid matrix")
        matrix = stage["matrices"][matrix_id]
        if source >= matrix["source_count"] or row_tile >= matrix["row_tiles"]:
            self.fatal = True
            raise ScatterFault("weight request out of range")
        if not ((self.residency[matrix_id] >> source) & 1):
            self.fatal = True
            raise ScatterFault("weight source is not resident")
        offset = matrix["local_byte_offset"] + source * matrix["source_stride_bytes"]
        offset += row_tile * matrix["word_bytes"]
        return bytes(self.cache[offset : offset + matrix["word_bytes"]])

    def read_parameter(self, row_tile: int) -> bytes:
        if self.fatal or self.active_stage is None:
            raise ScatterFault("no resident stage")
        param = self.layout["stages"][self.active_stage]["parameters"]
        if row_tile >= param["row_tiles"]:
            self.fatal = True
            raise ScatterFault("parameter request out of range")
        begin = param["local_byte_offset"] + row_tile * param["record_bytes"]
        return bytes(self.cache[begin : begin + param["response_bytes"]])


def accepted_r_bytes(commands: Iterable[CopyCommand]) -> int:
    return sum(command.accepted_r_bytes for command in commands)
