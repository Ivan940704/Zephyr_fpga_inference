import re
from pathlib import Path

import pytest

import software.pynq.accelerator_bringup as bringup

from software.pynq.accelerator_bringup import (
    BringupError,
    CMD_ABORT,
    CMD_RESET_QUIESCE,
    CMD_SOFT_RESET,
    DMA_DMACR_RS,
    DMA_DMASR_ERROR_MASK,
    DmaSnapshot,
    DMA_DMASR_HALTED,
    DMA_DMASR_IDLE,
    DMA_MM2S_DMACR,
    DMA_MM2S_DMASR,
    DMA_S2MM_DMACR,
    DMA_S2MM_DMASR,
    EXPECTED_IMAGE_VERSION,
    EXPECTED_PACKET_BYTES_0,
    EXPECTED_PACKET_BYTES_1,
    MAILBOX_PACKET_BYTES_0,
    REG_COMMAND,
    REG_CONTROL_ERROR,
    REG_EXPECTED_FRAMES_0,
    REG_FB_RELEASE,
    REG_IMAGE_VERSION,
    REG_PACKET_BYTES_0,
    REG_PACKET_BYTES_1,
    REG_RESET_STATUS,
    REG_SB_COMMIT,
    RESET_PENDING,
    RESET_QUIESCE,
    RESET_SAFE,
    AcceleratorBringupDriver,
    ResetTimeout,
    channel_names,
)


class FakeClock:
    def __init__(self):
        self.value = 0.0

    def monotonic(self):
        return self.value

    def sleep(self, seconds):
        self.value += max(seconds, 0.000_001)


class MockDma:
    def __init__(self, *, settle_reads=0, error=0, trace=None, name="dma"):
        running = DMA_DMACR_RS
        active = 0
        self.registers = {
            DMA_MM2S_DMACR: running,
            DMA_MM2S_DMASR: active,
            DMA_S2MM_DMACR: running,
            DMA_S2MM_DMASR: active,
        }
        self.settle_reads = settle_reads
        self.error = error
        self.trace = trace
        self.name = name
        self.stop_reads = {DMA_MM2S_DMASR: 0, DMA_S2MM_DMASR: 0}
        self.writes = []

    def write(self, offset, value):
        value &= 0xFFFF_FFFF
        self.writes.append((offset, value))
        if self.trace is not None:
            self.trace.append((self.name, offset, value))
        if offset in (DMA_MM2S_DMACR, DMA_S2MM_DMACR):
            self.registers[offset] = value
        elif offset in (DMA_MM2S_DMASR, DMA_S2MM_DMASR):
            self.registers[offset] &= ~value

    def read(self, offset):
        if offset in (DMA_MM2S_DMASR, DMA_S2MM_DMASR):
            control = DMA_MM2S_DMACR if offset == DMA_MM2S_DMASR else DMA_S2MM_DMACR
            if not (self.registers[control] & DMA_DMACR_RS):
                self.stop_reads[offset] += 1
                if self.stop_reads[offset] > self.settle_reads:
                    return DMA_DMASR_HALTED | self.error
            return self.error
        return self.registers.get(offset, 0)


class MockControl:
    def __init__(
        self, *, safe_after=0, complete_after=1, bad_identity=False,
        reject_quiesce=False, trace=None, image_version=EXPECTED_IMAGE_VERSION
    ):
        self.safe_after = safe_after
        self.complete_after = complete_after
        self.safe_reads = 0
        self.pending_reads = 0
        self.epoch = 7
        self.pending = False
        self.command_log = []
        self.writes = []
        self.bad_identity = bad_identity
        self.control_error = 0
        self.reject_quiesce = reject_quiesce
        self.trace = trace
        self.image_version = image_version

    def write(self, offset, value):
        value &= 0xFFFF_FFFF
        self.writes.append((offset, value))
        if offset == REG_COMMAND:
            self.command_log.append(value)
            if self.trace is not None:
                self.trace.append(("control", offset, value))
            if value == CMD_SOFT_RESET:
                self.pending = True
            elif value == CMD_RESET_QUIESCE and self.reject_quiesce:
                self.control_error = 0x0000_0108

    def read(self, offset):
        if offset == REG_IMAGE_VERSION:
            return self.image_version ^ int(self.bad_identity)
        if offset == REG_PACKET_BYTES_0:
            return (
                EXPECTED_PACKET_BYTES_0
                if self.image_version
                in (EXPECTED_IMAGE_VERSION, bringup.PL_LAYERNORM_IMAGE_VERSION)
                else MAILBOX_PACKET_BYTES_0
            )
        if offset == REG_PACKET_BYTES_1:
            return EXPECTED_PACKET_BYTES_1
        if offset == REG_CONTROL_ERROR:
            return self.control_error
        if offset == REG_EXPECTED_FRAMES_0:
            return (4 << 16) | 3
        if offset == REG_RESET_STATUS:
            if self.pending:
                self.pending_reads += 1
                if self.pending_reads >= self.complete_after:
                    self.pending = False
                    self.epoch = (self.epoch + 1) & 0xFFFF
            else:
                self.safe_reads += 1
            safe = self.safe_reads > self.safe_after
            return (self.epoch << 16) | RESET_QUIESCE | (
                RESET_SAFE if safe else 0
            ) | (
                RESET_PENDING if self.pending else 0
            )
        return 0


def make_driver(*, control=None, io_dma=None, spectrum_dma=None):
    clock = FakeClock()
    barriers = []
    driver = AcceleratorBringupDriver(
        control or MockControl(),
        io_dma or MockDma(),
        spectrum_dma or MockDma(),
        barrier=lambda: barriers.append("dsb"),
        monotonic=clock.monotonic,
        sleep=clock.sleep,
        poll_interval_s=0.01,
    )
    return driver, barriers


def test_dma_stopped_requires_rs_cleared_and_halted():
    assert DmaSnapshot("dma", 0, DMA_DMASR_HALTED).stopped
    assert not DmaSnapshot("dma", DMA_DMACR_RS, DMA_DMASR_HALTED).stopped
    assert not DmaSnapshot("dma", 0, DMA_DMASR_IDLE).stopped


def test_safe_reset_stops_three_channels_and_observes_epoch():
    trace = []
    driver, barriers = make_driver(
        control=MockControl(safe_after=2, complete_after=3, trace=trace),
        io_dma=MockDma(settle_reads=2, trace=trace, name="io"),
        spectrum_dma=MockDma(
            settle_reads=1, trace=trace, name="spectrum"
        ),
    )
    result = driver.safe_soft_reset(timeout_s=1.0)

    assert driver.control.command_log == [
        CMD_ABORT,
        CMD_RESET_QUIESCE,
        CMD_SOFT_RESET,
    ]
    assert result["epoch_before"] == 7
    assert result["epoch_after"] == 8
    assert result["identity"]["image_version"] == EXPECTED_IMAGE_VERSION
    assert set(result["dma"]) == {"io-mm2s", "io-s2mm", "spectrum-mm2s"}
    assert channel_names(driver.channels) == (
        "io-mm2s",
        "io-s2mm",
        "spectrum-mm2s",
    )
    assert len(barriers) >= 4
    quiesce_index = trace.index(("control", REG_COMMAND, CMD_RESET_QUIESCE))
    dma_stop_indices = [
        index
        for index, (owner, offset, value) in enumerate(trace)
        if owner in ("io", "spectrum")
        and offset in (DMA_MM2S_DMACR, DMA_S2MM_DMACR)
        and not (value & DMA_DMACR_RS)
    ]
    assert len(dma_stop_indices) == 3
    assert max(dma_stop_indices) < quiesce_index


def test_dma_timeout_never_issues_soft_reset():
    driver, _ = make_driver(io_dma=MockDma(settle_reads=10_000))
    with pytest.raises(ResetTimeout):
        driver.safe_soft_reset(timeout_s=0.05)
    assert driver.control.command_log == [CMD_ABORT]
    assert not driver.reset_attempted


def test_core_quiesce_timeout_never_issues_soft_reset():
    driver, _ = make_driver(control=MockControl(safe_after=10_000))
    with pytest.raises(ResetTimeout):
        driver.safe_soft_reset(timeout_s=0.05)
    assert driver.control.command_log == [CMD_ABORT, CMD_RESET_QUIESCE]
    assert not driver.reset_attempted


def test_epoch_timeout_does_not_retry_reset():
    driver, _ = make_driver(control=MockControl(complete_after=10_000))
    with pytest.raises(ResetTimeout):
        driver.safe_soft_reset(timeout_s=0.05)
    assert driver.control.command_log == [
        CMD_ABORT,
        CMD_RESET_QUIESCE,
        CMD_SOFT_RESET,
    ]
    assert driver.reset_attempted
    with pytest.raises(BringupError, match="already attempted"):
        driver.safe_soft_reset(timeout_s=1.0)


def test_quiesce_rejection_is_reported_without_soft_reset():
    driver, _ = make_driver(control=MockControl(reject_quiesce=True))
    with pytest.raises(BringupError, match="quiesce rejected"):
        driver.safe_soft_reset(timeout_s=1.0)
    assert driver.control.command_log == [CMD_ABORT, CMD_RESET_QUIESCE]
    assert not driver.reset_attempted


def test_dma_error_is_preserved_and_blocks_reset():
    driver, _ = make_driver(
        spectrum_dma=MockDma(error=DMA_DMASR_ERROR_MASK & 0x10)
    )
    with pytest.raises(BringupError, match="AXI DMA error"):
        driver.safe_soft_reset(timeout_s=1.0)
    assert driver.control.command_log == [CMD_ABORT]


def test_bad_identity_fails_after_single_completed_reset():
    driver, _ = make_driver(control=MockControl(bad_identity=True))
    with pytest.raises(BringupError, match="identity mismatch"):
        driver.safe_soft_reset(timeout_s=1.0)
    assert driver.control.command_log == [
        CMD_ABORT,
        CMD_RESET_QUIESCE,
        CMD_SOFT_RESET,
    ]
    assert driver.reset_attempted


def test_legacy_image_is_accepted_but_profiling_fails_closed():
    driver, _ = make_driver(control=MockControl(image_version=0x0004_0001))
    assert driver.verify_identity()["image_version"] == 0x0004_0001
    with pytest.raises(BringupError, match="hardware profiling requires"):
        driver.configure_hardware_profiling(enable=True, clear=True)


def test_mailbox_frame_and_parameter_alignment_fail_closed():
    driver, barriers = make_driver()
    driver.mailbox_event(REG_FB_RELEASE, 1, 3)
    driver.mailbox_event(REG_SB_COMMIT, 0, 4)
    assert driver.control.writes[-2:] == [
        (REG_FB_RELEASE, 0x8000_0007),
        (REG_SB_COMMIT, 0x8000_0008),
    ]
    assert len(barriers) == 2
    with pytest.raises(BringupError, match="frame mismatch"):
        driver.mailbox_event(REG_SB_COMMIT, 0, 3)
    with pytest.raises(BringupError, match="64-byte aligned"):
        driver.configure_start(0x1000_0001)


def test_diagnostic_snapshot_is_read_only_and_keeps_raw_state():
    driver, barriers = make_driver()
    snapshot = driver.diagnostic_snapshot()
    assert snapshot["control"]["image_version"] == EXPECTED_IMAGE_VERSION
    assert snapshot["control"]["reset_status"] >> 16 == 7
    assert set(snapshot["dma"]) == {
        "io-mm2s",
        "io-s2mm",
        "spectrum-mm2s",
    }
    assert snapshot["reset_attempted"] is False
    assert driver.control.writes == []
    assert barriers == []


def test_driver_constants_match_rtl_and_block_design_contract():
    root = Path(__file__).resolve().parents[2]
    control_rtl = (root / "rtl/axi/accelerator_control_axil.v").read_text(
        encoding="utf-8"
    )
    registers = {
        name: int(value, 16)
        for name, value in re.findall(
            r"localparam \[11:0\] (REG_[A-Z0-9_]+)\s*=\s*12'h([0-9a-fA-F]+)",
            control_rtl,
        )
    }
    for name in (
        "REG_COMMAND",
        "REG_CONFIG_SHADOW",
        "REG_PARAM_BASE_SHADOW",
        "REG_STATUS",
        "REG_EXECUTION",
        "REG_FRAME_ID",
        "REG_STATE_CYCLES",
        "REG_IRQ_STATUS",
        "REG_FIRST_FAULT",
        "REG_FIRST_FAULT_DETAIL",
        "REG_FIRST_FAULT_FRAME",
        "REG_PACKET_BYTES_0",
        "REG_PACKET_BYTES_1",
        "REG_FB_RELEASE",
        "REG_SB_CLAIM",
        "REG_SB_COMMIT",
        "REG_EXPECTED_FRAMES_0",
        "REG_CONTROL_ERROR",
        "REG_IMAGE_VERSION",
        "REG_RESET_STATUS",
        "REG_PROFILE_CONTROL",
    ):
        assert getattr(bringup, name) == registers[name], name
    assert "32'h0005_0003" in control_rtl

    bd_flow = (root / "rtl/scripts/create_accelerator_full_bd.tcl").read_text(
        encoding="utf-8"
    )
    for address in (
        bringup.CONTROL_BASE,
        bringup.IO_DMA_BASE,
        bringup.SPECTRUM_DMA_BASE,
    ):
        assert f"0x{address:08X}" in bd_flow
