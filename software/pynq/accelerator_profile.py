#!/usr/bin/env python3
"""Decode coherent per-frame profiling snapshots from accelerator images."""

from __future__ import annotations

import time
from typing import Callable, Optional, Sequence


LEGACY_IMAGE_VERSION = 0x0004_0001
PROFILING_IMAGE_VERSION = 0x0004_0002
LEGACY_PL_LAYERNORM_IMAGE_VERSION = 0x0004_0003
V5_MAILBOX_IMAGE_VERSION = 0x0005_0000
PL_LAYERNORM_IMAGE_VERSION = 0x0005_0001
SPARSE_MEMORY_IMAGE_VERSION = 0x0005_0003
EXPECTED_IMAGE_VERSION = SPARSE_MEMORY_IMAGE_VERSION
SUPPORTED_IMAGE_VERSIONS = (
    LEGACY_IMAGE_VERSION,
    PROFILING_IMAGE_VERSION,
    LEGACY_PL_LAYERNORM_IMAGE_VERSION,
    V5_MAILBOX_IMAGE_VERSION,
    PL_LAYERNORM_IMAGE_VERSION,
    SPARSE_MEMORY_IMAGE_VERSION,
)

REG_PROFILE_CONTROL = 0x0AC
REG_PROFILE_STATUS = 0x0B0
REG_PROFILE_BASE = 0x100
REG_PROFILE_LAST = 0x3FC
PROFILE_WORD_COUNT = ((REG_PROFILE_LAST - REG_PROFILE_BASE) // 4) + 1
PROFILE_SCHEMA = 0x5052_0001

PROFILE_ENABLE = 1 << 0
PROFILE_CLEAR = 1 << 1
PROFILE_SNAPSHOT = 1 << 2
PROFILE_STATUS_ENABLE = 1 << 0
PROFILE_STATUS_VALID = 1 << 1
PROFILE_STATUS_ACTIVE = 1 << 2
PROFILE_STATUS_BUSY = 1 << 3

GLOBAL_STATE_NAMES = (
    "idle",
    "fb_load_req",
    "fb_load_wait",
    "fb_run",
    "fb_send",
    "wait_ps",
    "sb_load_req",
    "sb_load_wait",
    "sb_run",
    "df_run",
    "output",
    "done",
    "error",
)
STAGE_NAMES = tuple(f"stage_{index}" for index in range(12))
SUMMARY_NAMES = (
    "axi_ar_bursts",
    "axi_ar_requested_beats",
    "axi_r_beats",
    "axi_r_bytes",
    "axi_ar_stall_cycles",
    "axi_r_wait_cycles",
    "axi_r_backpressure_cycles",
    "fb_axis_beats",
    "fb_axis_backpressure_cycles",
    "spectrum_axis_beats",
    "spectrum_axis_backpressure_cycles",
    "output_axis_beats",
    "output_axis_backpressure_cycles",
    "fb_releases",
    "sb_claims",
    "sb_commits",
    "controller_jobs",
    "weight_requests",
    "dense_requests",
    "sparse_requests",
    "dense_equivalent_requests",
    "retired_macs",
    "skipped_macs",
    "sparse_stage_actual_bytes",
    "sparse_stage_saved_bytes",
    "sparse_stage_ar_bursts",
    "sparse_stage_load_cycles",
    "maximum_outstanding_bursts",
    "fb_axis_packets",
    "spectrum_axis_packets",
    "output_axis_packets",
    "frame_error_cycles",
    "mailbox_errors",
    "sparse_diagnostic_events",
    "axi_rlast_completions",
    "invalid_global_state_cycles",
)


class ProfileError(RuntimeError):
    """A hardware profiling capability or coherence contract failed."""


def profile_control_value(
    *, enable: bool, clear: bool = False, snapshot: bool = False
) -> int:
    return (
        int(bool(enable)) * PROFILE_ENABLE
        | int(bool(clear)) * PROFILE_CLEAR
        | int(bool(snapshot)) * PROFILE_SNAPSHOT
    )


def _u64(words: list[int], index: int) -> int:
    return words[index] | (words[index + 1] << 32)


def _fraction(numerator: int, denominator: int) -> Optional[float]:
    return float(numerator / denominator) if denominator else None


def decode_profile_words(
    words: list[int], *, clock_hz: int = 100_000_000
) -> dict[str, object]:
    """Validate and decode one immutable 176-word profile window."""

    if len(words) != PROFILE_WORD_COUNT:
        raise ProfileError(
            f"profile snapshot must contain {PROFILE_WORD_COUNT} words, got {len(words)}"
        )
    words = [int(value) & 0xFFFF_FFFF for value in words]
    if words[0] != PROFILE_SCHEMA:
        raise ProfileError(
            f"profile schema mismatch: 0x{words[0]:08x} != 0x{PROFILE_SCHEMA:08x}"
        )
    if clock_hz <= 0:
        raise ValueError("clock_hz must be positive")

    flags = words[1]
    frame_cycles = _u64(words, 4)
    state_sum = _u64(words, 6)
    state_cycles = {
        name: _u64(words, 8 + (index * 2))
        for index, name in enumerate(GLOBAL_STATE_NAMES)
    }
    state_visits = {
        name: words[34 + index]
        for index, name in enumerate(GLOBAL_STATE_NAMES)
    }
    stage_load_cycles = {
        name: _u64(words, 48 + (index * 2))
        for index, name in enumerate(STAGE_NAMES)
    }
    stage_compute_cycles = {
        name: _u64(words, 72 + (index * 2))
        for index, name in enumerate(STAGE_NAMES)
    }
    stage_stall_cycles = {
        name: _u64(words, 96 + (index * 2))
        for index, name in enumerate(STAGE_NAMES)
    }
    counters = {
        name: _u64(words, 120 + (index * 2))
        for index, name in enumerate(SUMMARY_NAMES)
    }

    decoded_state_sum = sum(state_cycles.values())
    if frame_cycles != state_sum or state_sum != decoded_state_sum:
        raise ProfileError(
            "profile cycle conservation failed: "
            f"frame={frame_cycles} state_sum={state_sum} decoded={decoded_state_sum}"
        )
    if not (flags & PROFILE_STATUS_VALID):
        raise ProfileError("profile snapshot is not valid")

    dense_equivalent = counters["dense_equivalent_requests"]
    skipped_macs = counters["skipped_macs"]
    dense_equivalent_macs = dense_equivalent * 16
    byte_total = (
        counters["sparse_stage_actual_bytes"]
        + counters["sparse_stage_saved_bytes"]
    )
    packed = words[2]
    return {
        "schema": f"0x{words[0]:08x}",
        "snapshot_sequence": words[3],
        "frame_id": packed & 0xFFFF,
        "end_state": (packed >> 17) & 0xF,
        "compute_owner": (packed >> 21) & 0xF,
        "sparse": bool(flags & (1 << 4)),
        "enabled": bool(flags & PROFILE_STATUS_ENABLE),
        "snapshot_valid": bool(flags & PROFILE_STATUS_VALID),
        "frame_active": bool(flags & PROFILE_STATUS_ACTIVE),
        "accelerator_reset_active": bool(flags & (1 << 3)),
        "clock_hz": clock_hz,
        "frame_cycles": frame_cycles,
        "pl_latency_s": float(frame_cycles / clock_hz),
        "state_cycles": state_cycles,
        "state_visits": state_visits,
        "stage_load_cycles": stage_load_cycles,
        "stage_compute_cycles": stage_compute_cycles,
        "stage_stall_cycles": stage_stall_cycles,
        "counters": counters,
        "derived": {
            "request_sparsity": _fraction(
                counters["dense_equivalent_requests"]
                - min(counters["weight_requests"], dense_equivalent),
                dense_equivalent,
            ),
            "mac_skip_fraction": _fraction(skipped_macs, dense_equivalent_macs),
            "parameter_byte_savings_fraction": _fraction(
                counters["sparse_stage_saved_bytes"], byte_total
            ),
        },
    }


def read_profile_snapshot_words(
    read_word: Callable[[int], int],
    *,
    read_words: Optional[Callable[[int, int], Sequence[int]]] = None,
    expected_frame_id: Optional[int] = None,
    retries: int = 3,
    ready_timeout_s: float = 0.100,
    poll_interval_s: float = 0.000_010,
) -> tuple[int, ...]:
    """Copy one sequence-stable snapshot without decoding it.

    ``read_words`` allows a memory-mapped implementation to copy the complete
    704-byte profile window in native code instead of issuing 176 Python MMIO
    calls.  Coherence checks remain on both sides of the bulk copy.  Decoding
    can be deferred until after a latency-critical frame loop.
    """

    if retries <= 0:
        raise ValueError("retries must be positive")
    if ready_timeout_s < 0.0:
        raise ValueError("ready_timeout_s must be non-negative")
    if poll_interval_s < 0.0:
        raise ValueError("poll_interval_s must be non-negative")

    deadline = time.monotonic() + ready_timeout_s
    while True:
        ready_status = int(read_word(REG_PROFILE_STATUS)) & 0xFFFF_FFFF
        if not (ready_status & PROFILE_STATUS_ENABLE):
            raise ProfileError("hardware profiling is not enabled")
        if ready_status & PROFILE_STATUS_VALID:
            break
        if not (ready_status & PROFILE_STATUS_BUSY):
            raise ProfileError("hardware profile snapshot completed without valid data")
        if time.monotonic() >= deadline:
            raise ProfileError("hardware profile snapshot readiness timed out")
        if poll_interval_s:
            time.sleep(poll_interval_s)

    last_reason = "no read attempted"
    for _ in range(retries):
        status_before = int(read_word(REG_PROFILE_STATUS)) & 0xFFFF_FFFF
        if not (status_before & PROFILE_STATUS_ENABLE):
            raise ProfileError("hardware profiling is not enabled")
        if not (status_before & PROFILE_STATUS_VALID):
            last_reason = "profile snapshot became invalid before read"
            continue
        sequence_before = int(read_word(REG_PROFILE_BASE + 12)) & 0xFFFF_FFFF
        if read_words is None:
            words = [
                int(read_word(REG_PROFILE_BASE + index * 4)) & 0xFFFF_FFFF
                for index in range(PROFILE_WORD_COUNT)
            ]
        else:
            words = [
                int(value) & 0xFFFF_FFFF
                for value in read_words(REG_PROFILE_BASE, PROFILE_WORD_COUNT)
            ]
            if len(words) != PROFILE_WORD_COUNT:
                raise ProfileError(
                    "bulk profile read returned "
                    f"{len(words)} words, expected {PROFILE_WORD_COUNT}"
                )
        sequence_after = int(read_word(REG_PROFILE_BASE + 12)) & 0xFFFF_FFFF
        status_after = int(read_word(REG_PROFILE_STATUS)) & 0xFFFF_FFFF
        if sequence_before != sequence_after or words[3] != sequence_before:
            last_reason = "snapshot sequence changed during read"
            continue
        if status_before != status_after:
            last_reason = "profile status changed during read"
            continue
        if words[0] != PROFILE_SCHEMA:
            raise ProfileError(
                f"profile schema mismatch: 0x{words[0]:08x} != 0x{PROFILE_SCHEMA:08x}"
            )
        if not (words[1] & PROFILE_STATUS_VALID):
            raise ProfileError("profile snapshot is not valid")
        frame_id = words[2] & 0xFFFF
        if expected_frame_id is not None and frame_id != expected_frame_id:
            raise ProfileError(
                f"profile frame mismatch: {frame_id} != {expected_frame_id}"
            )
        return tuple(words)
    raise ProfileError(f"could not obtain coherent profile snapshot: {last_reason}")


def read_profile_snapshot(
    read_word: Callable[[int], int],
    *,
    read_words: Optional[Callable[[int, int], Sequence[int]]] = None,
    expected_frame_id: Optional[int] = None,
    clock_hz: int = 100_000_000,
    retries: int = 3,
    ready_timeout_s: float = 0.100,
    poll_interval_s: float = 0.000_010,
) -> dict[str, object]:
    """Read, validate, and decode one coherent hardware profile snapshot."""

    words = read_profile_snapshot_words(
        read_word,
        read_words=read_words,
        expected_frame_id=expected_frame_id,
        retries=retries,
        ready_timeout_s=ready_timeout_s,
        poll_interval_s=poll_interval_s,
    )
    return decode_profile_words(list(words), clock_hz=clock_hz)
