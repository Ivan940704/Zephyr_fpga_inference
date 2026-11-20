import json
from pathlib import Path

import pytest

from software.pynq.parameter_bram_bringup import (
    CACHE_INVALID,
    CleanupError,
    EXPECTED_STAGE_METRICS,
    IMAGE_VERSION,
    ParameterBramDriver,
    REG_ABI_VERSION,
    REG_ACTIVE,
    REG_ACTIVE_VERSION,
    REG_AR_BURSTS,
    REG_CAPABILITIES,
    REG_CACHE_BYTES,
    REG_COMMAND,
    REG_HW_ID,
    REG_IMAGE_VERSION,
    REG_LOAD_CYCLES,
    REG_LUT_BYTES,
    REG_PARAMETER_BASE,
    REG_R_BEATS,
    REG_SERVICE_DETAIL,
    REG_SERVICE_ERROR,
    REG_STAGE_ID,
    REG_STATUS,
    REG_WEIGHT_COMMAND,
    REG_WEIGHT_DATA0,
    REG_WEIGHT_REQUEST,
    REG_WEIGHT_STATUS,
    REG_WRAPPER_DETAIL,
    REG_WRAPPER_ERROR,
    STATUS_ABORT_DRAIN,
    STATUS_DONE,
    STATUS_LUT_READY,
    STATUS_RAW_BUSY,
    STATUS_READY,
    STATUS_STAGE_RELEASE_READY,
    STATUS_STAGE_REQ_READY,
    STATUS_WEIGHT_REQ_READY,
    STATUS_WEIGHT_RSP_VALID,
    CMD_ABORT,
    CMD_CLEAR_ERROR,
    CMD_CLEAR_EVENTS,
    CMD_RELEASE,
    CMD_START,
    WEIGHT_CMD_ACK,
    WEIGHT_CMD_REQUEST,
    BringupError,
    expected_ar_bursts,
)


ROOT = Path(__file__).resolve().parents[2]
IMAGE_PATH = ROOT / "outputs" / "memory" / "2026-09-01" / "v3" / "parameters_v3.bin"
GOLDEN_PATH = ROOT / "outputs" / "memory" / "2026-09-01" / "v3" / "memory_golden_v3.json"


class FakeClock:
    def __init__(self):
        self.value = 0.0

    def monotonic(self):
        return self.value

    def sleep(self, seconds):
        self.value += max(seconds, 0.000_001)


class MockBuffer:
    def __init__(self, size, physical_address, can_free):
        self.data = bytearray(size)
        self.physical_address = physical_address
        self.flushed = False
        self.freed = False
        self._can_free = can_free

    def __setitem__(self, key, value):
        self.data[key] = bytes(value)

    def flush(self):
        self.flushed = True

    def freebuffer(self):
        assert self._can_free(), "driver freed a buffer still owned by PL"
        self.freed = True


class MockMMIO:
    def __init__(
        self,
        vectors,
        *,
        abort_reads=0,
        abort_never_finishes=False,
        fail_data_read=False,
    ):
        self.vectors = {
            (
                vector["stage"],
                vector["matrix"],
                vector["source"],
                vector["row_tile"],
                vector["tag"],
            ): vector
            for vector in vectors
        }
        self.registers = {REG_PARAMETER_BASE: 0, REG_IMAGE_VERSION: 0, REG_STAGE_ID: 0}
        self.active_stage = None
        self.last_stage = None
        self.ready = False
        self.done = False
        self.raw_busy = False
        self.draining = False
        self.abort_reads = abort_reads
        self.abort_reads_left = 0
        self.abort_never_finishes = abort_never_finishes
        self.response = None
        self.command_log = []
        self.fail_data_read = fail_data_read
        self.failed_data_read = False

    def safe_to_free(self):
        return not self.raw_busy and self.active_stage is None and not self.draining

    def _advance_drain(self):
        if not self.draining or self.abort_never_finishes:
            return
        if self.abort_reads_left > 0:
            self.abort_reads_left -= 1
        if self.abort_reads_left == 0:
            self.draining = False
            self.raw_busy = False
            self.active_stage = None

    def _status(self):
        self._advance_drain()
        status = 0
        if self.ready:
            status |= STATUS_READY | STATUS_STAGE_RELEASE_READY | STATUS_LUT_READY
            status |= 4 << 9
            if self.response is None:
                status |= STATUS_WEIGHT_REQ_READY
        elif self.draining:
            status |= STATUS_RAW_BUSY | STATUS_ABORT_DRAIN | (6 << 9)
        else:
            status |= STATUS_STAGE_REQ_READY
        if self.done:
            status |= STATUS_DONE
        if self.response is not None:
            status |= STATUS_WEIGHT_RSP_VALID
        return status

    def write(self, offset, value):
        value &= 0xFFFF_FFFF
        if offset in (REG_PARAMETER_BASE, REG_IMAGE_VERSION, REG_STAGE_ID):
            self.registers[offset] = value
            return
        if offset == REG_COMMAND:
            stage = self.registers[REG_STAGE_ID] & 0xF
            self.command_log.append((value, stage))
            if value == CMD_START:
                assert self.registers[REG_IMAGE_VERSION] == IMAGE_VERSION
                self.active_stage = stage
                self.last_stage = stage
                self.ready = True
                self.done = True
                self.raw_busy = False
            elif value == CMD_RELEASE:
                if stage == self.active_stage:
                    self.active_stage = None
                    self.ready = False
            elif value == CMD_ABORT:
                self.ready = False
                self.response = None
                self.draining = True
                self.raw_busy = True
                self.abort_reads_left = self.abort_reads
                if self.abort_reads == 0 and not self.abort_never_finishes:
                    self._advance_drain()
            elif value == CMD_CLEAR_EVENTS:
                self.done = False
            elif value == CMD_CLEAR_ERROR:
                pass
            return
        if offset == REG_WEIGHT_REQUEST:
            self.registers[offset] = value
            return
        if offset == REG_WEIGHT_COMMAND:
            if value == WEIGHT_CMD_REQUEST:
                request = self.registers[REG_WEIGHT_REQUEST]
                key = (
                    self.active_stage,
                    request & 1,
                    (request >> 6) & 0x3FF,
                    (request >> 16) & 0x3F,
                    (request >> 24) & 0xFF,
                )
                self.response = self.vectors[key]
            elif value == WEIGHT_CMD_ACK:
                self.response = None

    def read(self, offset):
        if offset == REG_HW_ID:
            return 0x5A4D_454D
        if offset == REG_ABI_VERSION:
            return 0x0001_0000
        if offset == REG_CAPABILITIES:
            return 0x070F_100C
        if offset == REG_CACHE_BYTES:
            return 256 * 1024
        if offset == REG_STATUS:
            return self._status()
        if offset == REG_ACTIVE:
            return 0 if self.active_stage is None else (1 << 4) | self.active_stage
        if offset == REG_ACTIVE_VERSION:
            return IMAGE_VERSION if self.active_stage is not None else 0
        if offset in (REG_SERVICE_ERROR, REG_SERVICE_DETAIL, REG_WRAPPER_ERROR, REG_WRAPPER_DETAIL):
            return 0
        if offset == REG_LOAD_CYCLES:
            return 1000 if self.last_stage is not None else 0
        if offset == REG_AR_BURSTS:
            if self.last_stage is None:
                return 0
            expected = EXPECTED_STAGE_METRICS[self.last_stage]
            return expected_ar_bursts(
                self.registers[REG_PARAMETER_BASE],
                expected["offset"],
                expected["bytes"],
            )
        if offset == REG_R_BEATS:
            return (
                0
                if self.last_stage is None
                else EXPECTED_STAGE_METRICS[self.last_stage]["beats"]
            )
        if offset == REG_LUT_BYTES:
            return (
                0
                if self.last_stage is None
                else EXPECTED_STAGE_METRICS[self.last_stage]["lut_bytes"]
            )
        if offset == REG_WEIGHT_STATUS:
            if self.response is None:
                return 0
            return (1 << 2) | (int(self.response["tag"]) << 8)
        if REG_WEIGHT_DATA0 <= offset <= REG_WEIGHT_DATA0 + 12:
            if self.fail_data_read and not self.failed_data_read:
                self.failed_data_read = True
                raise RuntimeError("injected MMIO read failure")
            word = (offset - REG_WEIGHT_DATA0) // 4
            return self.response["expected_words_le"][word]
        return self.registers.get(offset, 0)


def contract_vectors():
    return json.loads(GOLDEN_PATH.read_text(encoding="utf-8"))[
        "weight_readback_vectors"
    ]["vectors"]


def make_driver(mmio, buffer, clock, barriers):
    return ParameterBramDriver(
        mmio,
        allocator=lambda size: buffer,
        barrier=lambda: barriers.append("dsb sy"),
        monotonic=clock.monotonic,
        sleep=clock.sleep,
        poll_interval_s=0.001,
    )


def test_mock_driver_runs_stage2_then_stage1_and_frees_after_release():
    mmio = MockMMIO(contract_vectors())
    buffer = MockBuffer(1_053_056, 0x1800_0000, mmio.safe_to_free)
    clock = FakeClock()
    barriers = []
    driver = make_driver(mmio, buffer, clock, barriers)

    result = driver.run_smoke(IMAGE_PATH, GOLDEN_PATH)

    assert buffer.flushed is True
    assert buffer.freed is True
    assert bytes(buffer.data) == IMAGE_PATH.read_bytes()
    assert [stage["stage"] for stage in result["stages"]] == [2, 1]
    assert [len(stage["readbacks"]) for stage in result["stages"]] == [5, 8]
    assert [(command, stage) for command, stage in mmio.command_log if command == CMD_START] == [
        (CMD_START, 2),
        (CMD_START, 1),
    ]
    assert mmio.command_log[-1] == (CMD_RELEASE, 1)
    assert len(barriers) >= 1 + 2 * (1 + 2 + 2)


def test_mock_driver_stage2_checkpoint_never_starts_stage1():
    mmio = MockMMIO(contract_vectors())
    buffer = MockBuffer(1_053_056, 0x1800_0000, mmio.safe_to_free)
    clock = FakeClock()
    barriers = []
    driver = make_driver(mmio, buffer, clock, barriers)

    result = driver.run_stage2_smoke(IMAGE_PATH, GOLDEN_PATH)

    assert result["outcome"] == "STAGE 2 BOARD SMOKE PASS"
    assert result["identity"]["capabilities"] == 0x070F_100C
    assert result["stage2"]["counters"] == {
        "load_cycles": 1000,
        "bursts": 165,
        "beats": 2632,
        "lut_bytes": 0,
    }
    assert len(result["readbacks"]) == 5
    assert all(readback["matched"] for readback in result["readbacks"])
    assert [(command, stage) for command, stage in mmio.command_log if command == CMD_START] == [
        (CMD_START, 2)
    ]
    assert mmio.command_log[-1] == (CMD_RELEASE, 2)
    assert result["buffer"]["released"] is True
    assert result["buffer"]["freed"] is True
    assert buffer.freed is True
    assert len(barriers) >= 10


def test_stage2_checkpoint_failure_snapshots_aborts_and_never_starts_stage1():
    mmio = MockMMIO(contract_vectors(), abort_reads=3, fail_data_read=True)
    buffer = MockBuffer(1_053_056, 0x1800_0000, mmio.safe_to_free)
    clock = FakeClock()
    driver = make_driver(mmio, buffer, clock, [])

    with pytest.raises(RuntimeError, match="injected MMIO"):
        driver.run_stage2_smoke(
            IMAGE_PATH,
            GOLDEN_PATH,
            recovery_timeout_s=0.1,
        )

    starts = [
        stage for command, stage in mmio.command_log if command == CMD_START
    ]
    assert starts == [2]
    assert any(command == CMD_ABORT for command, _ in mmio.command_log)
    assert driver.last_run_evidence["failure_registers_before_abort"]
    assert driver.last_run_evidence["abort_drain_completed"] is True
    assert mmio.safe_to_free() is True
    assert buffer.freed is True


def test_64_byte_aligned_buffer_uses_physical_address_for_burst_count():
    mmio = MockMMIO(contract_vectors())
    # This is legal by the ABI but shifts stage 1 onto a 128-byte boundary,
    # reducing its count from the 4 KiB-base contract value 1717 to 1716.
    buffer = MockBuffer(1_053_056, 0x1800_0040, mmio.safe_to_free)
    clock = FakeClock()
    driver = make_driver(mmio, buffer, clock, [])

    result = driver.run_smoke(IMAGE_PATH, GOLDEN_PATH)

    assert result["stages"][0]["counters"]["bursts"] == 165
    assert result["stages"][1]["counters"]["bursts"] == 1716
    assert buffer.freed is True


def test_misaligned_physical_buffer_is_rejected_before_pl_ownership():
    mmio = MockMMIO(contract_vectors())
    buffer = MockBuffer(1_053_056, 0x1800_0004, mmio.safe_to_free)
    clock = FakeClock()
    driver = make_driver(mmio, buffer, clock, [])

    with pytest.raises(BringupError, match="64-byte aligned"):
        driver.run_smoke(IMAGE_PATH, GOLDEN_PATH)

    assert buffer.freed is True
    assert buffer.flushed is False
    assert mmio.command_log == []


def test_failure_after_start_aborts_drains_then_frees_buffer():
    mmio = MockMMIO(contract_vectors(), abort_reads=4, fail_data_read=True)
    buffer = MockBuffer(1_053_056, 0x1800_0000, mmio.safe_to_free)
    clock = FakeClock()
    driver = make_driver(mmio, buffer, clock, [])

    with pytest.raises(RuntimeError, match="injected MMIO"):
        driver.run_smoke(IMAGE_PATH, GOLDEN_PATH, recovery_timeout_s=0.1)

    assert any(command == CMD_ABORT for command, _ in mmio.command_log)
    assert mmio.safe_to_free() is True
    assert buffer.freed is True


def test_buffer_is_retained_when_abort_drain_cannot_be_proven():
    mmio = MockMMIO(
        contract_vectors(), abort_never_finishes=True, fail_data_read=True
    )
    buffer = MockBuffer(1_053_056, 0x1800_0000, mmio.safe_to_free)
    clock = FakeClock()
    driver = make_driver(mmio, buffer, clock, [])

    with pytest.raises(CleanupError, match="was not freed"):
        driver.run_smoke(
            IMAGE_PATH,
            GOLDEN_PATH,
            recovery_timeout_s=0.003,
        )

    assert buffer.freed is False
    assert mmio.safe_to_free() is False
    assert any(command == CMD_ABORT for command, _ in mmio.command_log)
