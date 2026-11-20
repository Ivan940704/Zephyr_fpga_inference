#!/usr/bin/env python3
"""Fail-closed PYNQ control helpers for the Sequential-v4 accelerator.

This module intentionally leaves overlay selection and loading to the caller.
It provides the register identity, mailbox ownership, and coordinated
DMA/datapath reset primitives used after a matching BIT/HWH pair is loaded.

Unit tests inject MMIO and clock doubles.  They are host evidence only.
"""

from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Callable, Dict, Iterable, Optional

try:
    from .accelerator_profile import (
        EXPECTED_IMAGE_VERSION,
        PL_LAYERNORM_IMAGE_VERSION,
        PROFILING_IMAGE_VERSION,
        SPARSE_MEMORY_IMAGE_VERSION,
        REG_PROFILE_CONTROL,
        SUPPORTED_IMAGE_VERSIONS,
        ProfileError,
        profile_control_value,
        read_profile_snapshot,
    )
except ImportError:
    from accelerator_profile import (  # type: ignore
        EXPECTED_IMAGE_VERSION,
        PL_LAYERNORM_IMAGE_VERSION,
        PROFILING_IMAGE_VERSION,
        SPARSE_MEMORY_IMAGE_VERSION,
        REG_PROFILE_CONTROL,
        SUPPORTED_IMAGE_VERSIONS,
        ProfileError,
        profile_control_value,
        read_profile_snapshot,
    )


CONTROL_BASE = 0x43C0_0000
CONTROL_BYTES = 0x1000
IO_DMA_BASE = 0x4040_0000
SPECTRUM_DMA_BASE = 0x4041_0000
DMA_BYTES = 0x1000

REG_COMMAND = 0x000
REG_CONFIG_SHADOW = 0x004
REG_PARAM_BASE_SHADOW = 0x008
REG_STATUS = 0x014
REG_EXECUTION = 0x018
REG_FRAME_ID = 0x01C
REG_STATE_CYCLES = 0x020
REG_IRQ_STATUS = 0x028
REG_FIRST_FAULT = 0x02C
REG_FIRST_FAULT_DETAIL = 0x030
REG_FIRST_FAULT_FRAME = 0x034
REG_PACKET_BYTES_0 = 0x038
REG_PACKET_BYTES_1 = 0x03C
REG_FB_RELEASE = 0x040
REG_SB_CLAIM = 0x044
REG_SB_COMMIT = 0x048
REG_EXPECTED_FRAMES_0 = 0x050
REG_CONTROL_ERROR = 0x0A0
REG_IMAGE_VERSION = 0x0A4
REG_RESET_STATUS = 0x0A8

CMD_START = 1 << 0
CMD_ABORT = 1 << 1
CMD_SOFT_RESET = 1 << 2
CMD_CLEAR_ERROR = 1 << 3
CMD_CLEAR_IRQ = 1 << 4
CMD_RESET_QUIESCE = 1 << 5

PL_PACKET_BYTES_0 = (512 << 16) | 512
MAILBOX_PACKET_BYTES_0 = (512 << 16) | 64
EXPECTED_PACKET_BYTES_0 = PL_PACKET_BYTES_0
EXPECTED_PACKET_BYTES_1 = 2048
PARAMETER_ALIGNMENT = 64

RESET_SAFE = 1 << 0
RESET_ACTIVE = 1 << 1
RESET_PENDING = 1 << 2
RESET_QUIESCE = 1 << 3
RESET_EPOCH_SHIFT = 16

DMA_MM2S_DMACR = 0x00
DMA_MM2S_DMASR = 0x04
DMA_S2MM_DMACR = 0x30
DMA_S2MM_DMASR = 0x34
DMA_DMACR_RS = 1 << 0
DMA_DMASR_HALTED = 1 << 0
DMA_DMASR_IDLE = 1 << 1
DMA_DMASR_ERROR_MASK = 0x0000_0770
DMA_DMASR_IRQ_MASK = 0x0000_7000


class BringupError(RuntimeError):
    """A hardware identity or fail-closed recovery contract failed."""


class ResetTimeout(BringupError):
    """Recovery stopped without issuing another reset attempt."""


@dataclass(frozen=True)
class DmaSnapshot:
    name: str
    control: int
    status: int

    @property
    def stopped(self) -> bool:
        # AXI DMA reports DMASR=Halted (without Idle) after RS is cleared.
        # Prove both the requested and observed halves of that stopped state.
        return not (self.control & DMA_DMACR_RS) and bool(self.status & DMA_DMASR_HALTED)

    @property
    def errors(self) -> int:
        return self.status & DMA_DMASR_ERROR_MASK


class AxiDmaChannel:
    """One simple-mode AXI DMA channel with conservative stop semantics."""

    def __init__(self, mmio, name: str, direction: str) -> None:
        if direction not in ("mm2s", "s2mm"):
            raise ValueError("direction must be 'mm2s' or 's2mm'")
        self.mmio = mmio
        self.name = name
        self.control_offset = (
            DMA_MM2S_DMACR if direction == "mm2s" else DMA_S2MM_DMACR
        )
        self.status_offset = (
            DMA_MM2S_DMASR if direction == "mm2s" else DMA_S2MM_DMASR
        )

    def _read(self, offset: int) -> int:
        return int(self.mmio.read(offset)) & 0xFFFF_FFFF

    def _write(self, offset: int, value: int) -> None:
        self.mmio.write(offset, int(value) & 0xFFFF_FFFF)

    def snapshot(self) -> DmaSnapshot:
        return DmaSnapshot(
            self.name,
            self._read(self.control_offset),
            self._read(self.status_offset),
        )

    def request_stop(self) -> None:
        control = self._read(self.control_offset)
        self._write(self.control_offset, control & ~DMA_DMACR_RS)

    def acknowledge_irqs(self) -> None:
        status = self._read(self.status_offset)
        self._write(self.status_offset, status & DMA_DMASR_IRQ_MASK)


class AcceleratorBringupDriver:
    """Identity, ownership, and coordinated reset operations.

    The caller must stop submitting new buffers before ``safe_soft_reset``.
    A timeout leaves all DMA channels stopped and never retries the reset.
    """

    def __init__(
        self,
        control_mmio,
        io_dma_mmio,
        spectrum_dma_mmio,
        *,
        barrier: Callable[[], None],
        monotonic: Callable[[], float] = time.monotonic,
        sleep: Callable[[float], None] = time.sleep,
        poll_interval_s: float = 0.001,
    ) -> None:
        self.control = control_mmio
        self.barrier = barrier
        self.monotonic = monotonic
        self.sleep = sleep
        self.poll_interval_s = poll_interval_s
        self.channels = (
            AxiDmaChannel(io_dma_mmio, "io-mm2s", "mm2s"),
            AxiDmaChannel(io_dma_mmio, "io-s2mm", "s2mm"),
            AxiDmaChannel(spectrum_dma_mmio, "spectrum-mm2s", "mm2s"),
        )
        self.reset_attempted = False
        self.image_version: Optional[int] = None

    @classmethod
    def from_pynq(cls, *, barrier: Callable[[], None], **kwargs):
        from pynq import MMIO  # pylint: disable=import-outside-toplevel

        return cls(
            MMIO(CONTROL_BASE, CONTROL_BYTES),
            MMIO(IO_DMA_BASE, DMA_BYTES),
            MMIO(SPECTRUM_DMA_BASE, DMA_BYTES),
            barrier=barrier,
            **kwargs,
        )

    def _read(self, offset: int) -> int:
        return int(self.control.read(offset)) & 0xFFFF_FFFF

    def _write(self, offset: int, value: int) -> None:
        self.control.write(offset, int(value) & 0xFFFF_FFFF)

    def _command(self, value: int) -> None:
        self._write(REG_COMMAND, value)
        self.barrier()

    def _deadline(self, timeout_s: float) -> float:
        if timeout_s <= 0:
            raise ValueError("timeout_s must be positive")
        return self.monotonic() + timeout_s

    def _wait(self, predicate: Callable[[], Optional[object]], deadline: float):
        while True:
            result = predicate()
            if result is not None:
                return result
            if self.monotonic() >= deadline:
                raise ResetTimeout("recovery timeout; reset was not retried")
            self.sleep(self.poll_interval_s)

    def verify_identity(self) -> Dict[str, int]:
        identity = {
            "image_version": self._read(REG_IMAGE_VERSION),
            "packet_bytes_0": self._read(REG_PACKET_BYTES_0),
            "packet_bytes_1": self._read(REG_PACKET_BYTES_1),
        }
        packet_identity = (
            identity["packet_bytes_0"],
            identity["packet_bytes_1"],
        )
        expected_packet_0 = (
            PL_PACKET_BYTES_0
            if identity["image_version"]
            in (PL_LAYERNORM_IMAGE_VERSION, SPARSE_MEMORY_IMAGE_VERSION)
            else MAILBOX_PACKET_BYTES_0
        )
        expected_packets = (expected_packet_0, EXPECTED_PACKET_BYTES_1)
        if (
            identity["image_version"] not in SUPPORTED_IMAGE_VERSIONS
            or packet_identity != expected_packets
        ):
            raise BringupError(
                "accelerator identity mismatch: "
                f"{identity!r}; supported_images={SUPPORTED_IMAGE_VERSIONS!r} "
                f"expected_packets={expected_packets!r}"
            )
        self.image_version = identity["image_version"]
        return identity

    def configure_hardware_profiling(
        self, *, enable: bool, clear: bool = False, snapshot: bool = False
    ) -> None:
        """Configure v2 counters; never write profile CSRs on a v1 image."""

        version = self.image_version
        if version is None:
            version = self.verify_identity()["image_version"]
        if version < PROFILING_IMAGE_VERSION:
            raise BringupError(
                f"hardware profiling requires image 0x{PROFILING_IMAGE_VERSION:08x}; "
                f"loaded 0x{version:08x}"
            )
        self._write(
            REG_PROFILE_CONTROL,
            profile_control_value(enable=enable, clear=clear, snapshot=snapshot),
        )
        self.barrier()

    def read_hardware_profile(
        self, *, expected_frame_id: Optional[int] = None
    ) -> Dict[str, object]:
        try:
            return read_profile_snapshot(
                self._read, expected_frame_id=expected_frame_id
            )
        except ProfileError as exc:
            raise BringupError(str(exc)) from exc

    @staticmethod
    def encode_mailbox_event(slot: int, frame_id: int) -> int:
        if slot not in (0, 1):
            raise BringupError("mailbox slot must be 0 or 1")
        if not 0 <= frame_id <= 0xFFFF:
            raise BringupError("frame_id must fit 16 bits")
        return 0x8000_0000 | (frame_id << 1) | slot

    def mailbox_event(self, register: int, slot: int, frame_id: int) -> None:
        if register not in (REG_FB_RELEASE, REG_SB_CLAIM, REG_SB_COMMIT):
            raise BringupError("unsupported mailbox ownership register")
        expected = self._read(REG_EXPECTED_FRAMES_0)
        expected_fb = expected & 0xFFFF
        expected_sb = (expected >> 16) & 0xFFFF
        expected_frame = expected_fb if register == REG_FB_RELEASE else expected_sb
        if frame_id != expected_frame:
            raise BringupError(
                f"mailbox frame mismatch: got {frame_id}, expected {expected_frame}"
            )
        self._write(register, self.encode_mailbox_event(slot, frame_id))
        self.barrier()

    def configure_start(self, parameter_base: int, *, sparse: bool = True) -> None:
        if parameter_base & (PARAMETER_ALIGNMENT - 1):
            raise BringupError("parameter buffer must be 64-byte aligned")
        if not 0 <= parameter_base <= 0xFFFF_FFFF:
            raise BringupError("parameter physical address must fit 32 bits")
        config = (1 if sparse else 0) | (1 << 1)
        self._write(REG_CONFIG_SHADOW, config)
        self._write(REG_PARAM_BASE_SHADOW, parameter_base)
        self.barrier()

    def dma_snapshots(self) -> Dict[str, DmaSnapshot]:
        return {channel.name: channel.snapshot() for channel in self.channels}

    def diagnostic_snapshot(self) -> Dict[str, object]:
        """Capture fault/reset state without changing hardware ownership."""
        control_offsets = {
            "status": REG_STATUS,
            "execution": REG_EXECUTION,
            "frame_id": REG_FRAME_ID,
            "state_cycles": REG_STATE_CYCLES,
            "irq_status": REG_IRQ_STATUS,
            "first_fault": REG_FIRST_FAULT,
            "first_fault_detail": REG_FIRST_FAULT_DETAIL,
            "first_fault_frame": REG_FIRST_FAULT_FRAME,
            "control_error": REG_CONTROL_ERROR,
            "reset_status": REG_RESET_STATUS,
            "image_version": REG_IMAGE_VERSION,
            "packet_bytes_0": REG_PACKET_BYTES_0,
            "packet_bytes_1": REG_PACKET_BYTES_1,
        }
        return {
            "control": {
                name: self._read(offset)
                for name, offset in control_offsets.items()
            },
            "dma": self.dma_snapshots(),
            "reset_attempted": self.reset_attempted,
        }

    def _all_dma_stopped(self) -> Optional[Dict[str, DmaSnapshot]]:
        snapshots = self.dma_snapshots()
        errors = {name: snap.errors for name, snap in snapshots.items() if snap.errors}
        if errors:
            raise BringupError(f"AXI DMA error before reset: {errors!r}")
        if all(snapshot.stopped for snapshot in snapshots.values()):
            return snapshots
        return None

    def safe_soft_reset(self, *, timeout_s: float = 1.0) -> Dict[str, object]:
        """Abort/drain, stop all DMA channels, and issue one soft reset.

        The reset command is written only after every DMA status is both
        RS-cleared and Halted and the persistent RTL quiesce fence plus the
        two-sample RESET_SAFE proof are high. Completion is the reset-epoch
        increment observed by the live AXI-Lite control plane.
        """
        if self.reset_attempted:
            raise BringupError("this driver instance already attempted reset")
        deadline = self._deadline(timeout_s)

        self._command(CMD_ABORT)
        for channel in self.channels:
            channel.request_stop()
        self.barrier()
        stopped = self._wait(self._all_dma_stopped, deadline)

        # Do not fence AXIS admission before MM2S has drained. Holding TREADY
        # low while a DMA owns a TVALID beat could prevent that channel from
        # ever reaching Halted. The caller has already stopped new
        # submissions, and cleared RS plus an observed Halted status closes the
        # admission race before this persistent hardware fence is raised.
        self._command(CMD_RESET_QUIESCE)

        def safe_status():
            value = self._read(REG_RESET_STATUS)
            control_error = self._read(REG_CONTROL_ERROR)
            if control_error & 0x100:
                raise BringupError(
                    "reset quiesce rejected by control plane: "
                    f"0x{control_error:08x}"
                )
            return value if (
                (value & (RESET_SAFE | RESET_QUIESCE)) ==
                (RESET_SAFE | RESET_QUIESCE)
                and not (value & (RESET_ACTIVE | RESET_PENDING))
            ) else None

        before = self._wait(safe_status, deadline)
        before_epoch = (before >> RESET_EPOCH_SHIFT) & 0xFFFF
        self.reset_attempted = True
        self._command(CMD_SOFT_RESET)

        def reset_completed():
            value = self._read(REG_RESET_STATUS)
            epoch = (value >> RESET_EPOCH_SHIFT) & 0xFFFF
            if epoch != before_epoch and not (value & RESET_PENDING):
                return value
            control_error = self._read(REG_CONTROL_ERROR)
            if control_error & 0x100:
                raise BringupError(
                    f"soft reset rejected by control plane: 0x{control_error:08x}"
                )
            return None

        after = self._wait(reset_completed, deadline)
        identity = self.verify_identity()
        for channel in self.channels:
            channel.acknowledge_irqs()
        self.barrier()
        return {
            "identity": identity,
            "epoch_before": before_epoch,
            "epoch_after": (after >> RESET_EPOCH_SHIFT) & 0xFFFF,
            "dma": stopped,
        }


def fresh_parameter_epoch_reset(
    *, barrier: Callable[[], None], timeout_s: float = 2.0, driver_factory=None
) -> Dict[str, object]:
    """Reset the data plane and return JSON-safe evidence for a fresh DDR epoch."""

    factory = driver_factory or AcceleratorBringupDriver.from_pynq
    result = factory(barrier=barrier).safe_soft_reset(timeout_s=timeout_s)
    return {
        "identity": result["identity"],
        "epoch_before": int(result["epoch_before"]),
        "epoch_after": int(result["epoch_after"]),
        "dma": {
            name: {
                "control": int(snapshot.control),
                "status": int(snapshot.status),
                "stopped": bool(snapshot.stopped),
                "errors": int(snapshot.errors),
            }
            for name, snapshot in result["dma"].items()
        },
    }


def channel_names(channels: Iterable[AxiDmaChannel]):
    """Stable helper used by diagnostics and host tests."""
    return tuple(channel.name for channel in channels)
