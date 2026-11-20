#!/usr/bin/env python3
"""PYNQ driver for the parameter-BRAM board bring-up checkpoint.

The module is importable on a development host: PYNQ and NumPy are loaded only
by the default board allocator.  Unit tests inject mock MMIO/buffer/barrier
objects; no result from those tests is board evidence.
"""

from __future__ import annotations

import ctypes
import hashlib
import json
from pathlib import Path
import struct
import time
from typing import Callable, Dict, List, Optional, Tuple


CONTROL_BASE = 0x43C0_0000
CONTROL_BYTES = 0x1000
IMAGE_VERSION = 3
IMAGE_BYTES = 1_053_056
BUFFER_ALIGNMENT = 64
IMAGE_MAGIC = b"ZEPHYR3\0"
IMAGE_HEADER_BYTES = 64
IMAGE_STAGE_COUNT = 12
IMAGE_LANES = 16
IMAGE_BUS_BYTES = 8
EXPECTED_HW_ID = 0x5A4D_454D
EXPECTED_ABI_VERSION = 0x0001_0000
EXPECTED_CAPABILITIES = 0x070F_100C
EXPECTED_CACHE_BYTES = 256 * 1024

REG_HW_ID = 0x000
REG_ABI_VERSION = 0x004
REG_CAPABILITIES = 0x008
REG_CACHE_BYTES = 0x00C
REG_PARAMETER_BASE = 0x010
REG_IMAGE_VERSION = 0x014
REG_STAGE_ID = 0x018
REG_COMMAND = 0x01C
REG_STATUS = 0x020
REG_ACTIVE = 0x024
REG_ACTIVE_VERSION = 0x028
REG_SERVICE_ERROR = 0x02C
REG_SERVICE_DETAIL = 0x030
REG_WRAPPER_ERROR = 0x034
REG_WRAPPER_DETAIL = 0x038
REG_LOAD_CYCLES = 0x03C
REG_AR_BURSTS = 0x040
REG_R_BEATS = 0x044
REG_LUT_BYTES = 0x048
REG_RAW_STATUS = 0x04C
REG_WEIGHT_REQUEST = 0x050
REG_WEIGHT_COMMAND = 0x054
REG_WEIGHT_STATUS = 0x058
REG_WEIGHT_DATA0 = 0x05C

CMD_START = 1 << 0
CMD_RELEASE = 1 << 1
CMD_ABORT = 1 << 2
CMD_CLEAR_ERROR = 1 << 3
CMD_CLEAR_EVENTS = 1 << 4
WEIGHT_CMD_REQUEST = 1 << 0
WEIGHT_CMD_ACK = 1 << 1

STATUS_BUSY = 1 << 0
STATUS_READY = 1 << 1
STATUS_DONE = 1 << 2
STATUS_LOAD_ERROR = 1 << 3
STATUS_STAGE_REQ_READY = 1 << 4
STATUS_STAGE_RELEASE_READY = 1 << 5
STATUS_LUT_READY = 1 << 6
STATUS_SERVICE_ERROR = 1 << 7
STATUS_WRAPPER_ERROR = 1 << 8
STATUS_CACHE_SHIFT = 9
STATUS_CACHE_MASK = 0x7 << STATUS_CACHE_SHIFT
STATUS_WEIGHT_REQ_READY = 1 << 13
STATUS_WEIGHT_BUSY = 1 << 14
STATUS_WEIGHT_RSP_VALID = 1 << 15
STATUS_WEIGHT_RSP_ERROR = 1 << 16
STATUS_RAW_BUSY = 1 << 17
STATUS_ABORT_DRAIN = 1 << 18

CACHE_INVALID = 0
CACHE_READY = 4
CACHE_ERROR = 5

EXPECTED_STAGE_METRICS = {
    2: {"offset": 357_440, "bytes": 21_056, "beats": 2_632, "lut_bytes": 0},
    1: {
        "offset": 137_792,
        "bytes": 219_648,
        "beats": 27_456,
        "lut_bytes": 255,
    },
}


class BringupError(RuntimeError):
    """Hardware contract or expected-data failure."""


class CleanupError(BringupError):
    """The PL may still own the DDR buffer, so it was intentionally retained."""


def _sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def expected_ar_bursts(
    image_base: int, stage_offset: int, transfer_bytes: int
) -> int:
    """Mirror the loader's 16-beat and 4 KiB-boundary burst splitting."""
    if transfer_bytes < 0 or transfer_bytes % 8:
        raise BringupError("stage transfer must contain whole 64-bit beats")
    address = image_base + stage_offset
    beats = transfer_bytes // 8
    bursts = 0
    while beats:
        beats_to_4k = (4096 - (address & 4095)) // 8
        burst_beats = min(beats, 16, beats_to_4k)
        if burst_beats == 0:
            raise BringupError("stage address is not 64-bit aligned")
        address += burst_beats * 8
        beats -= burst_beats
        bursts += 1
    return bursts


def load_v3_contract(image_path: Path, golden_path: Path) -> Tuple[bytes, Dict]:
    """Load and byte-validate the image plus the 13 request-level vectors."""
    image = Path(image_path).read_bytes()
    golden = json.loads(Path(golden_path).read_text(encoding="utf-8"))
    if len(image) != IMAGE_BYTES:
        raise BringupError(f"image has {len(image)} bytes, expected {IMAGE_BYTES}")
    if len(image) < IMAGE_HEADER_BYTES:
        raise BringupError("image is shorter than the v3 header")
    magic, version, stage_count, lanes, bus_bytes, alignment, reserved = struct.unpack(
        "<8sIIIIII", image[:32]
    )
    if magic != IMAGE_MAGIC:
        raise BringupError(f"image magic mismatch: {magic!r}")
    if version != IMAGE_VERSION:
        raise BringupError(f"image format version is {version}, expected {IMAGE_VERSION}")
    if stage_count != IMAGE_STAGE_COUNT:
        raise BringupError(
            f"image stage count is {stage_count}, expected {IMAGE_STAGE_COUNT}"
        )
    if lanes != IMAGE_LANES or bus_bytes != IMAGE_BUS_BYTES:
        raise BringupError(
            f"image geometry is lanes={lanes}, bus_bytes={bus_bytes}"
        )
    if alignment != BUFFER_ALIGNMENT or reserved != 0:
        raise BringupError(
            f"image header alignment/reserved mismatch: {alignment}/{reserved}"
        )
    if golden.get("format_version") != IMAGE_VERSION:
        raise BringupError("golden format/image version mismatch")
    if golden.get("image_sha256") != _sha256(image):
        raise BringupError("parameters_v3.bin SHA-256 does not match golden")

    group = golden.get("weight_readback_vectors", {})
    vectors = group.get("vectors", [])
    if group.get("count") != 13 or len(vectors) != 13:
        raise BringupError("golden must contain exactly 13 readback vectors")
    if sum(vector.get("stage") == 2 for vector in vectors) != 5:
        raise BringupError("golden must contain five stage-2 vectors")
    if sum(vector.get("stage") == 1 for vector in vectors) != 8:
        raise BringupError("golden must contain eight stage-1 vectors")

    for vector in vectors:
        start = int(vector["image_byte_offset"])
        payload = image[start : start + 16]
        if len(payload) != 16:
            raise BringupError(f"vector {vector['index']} is outside the image")
        if payload.hex() != vector["expected_lane_bytes_hex"]:
            raise BringupError(f"vector {vector['index']} byte payload mismatch")
        words = [
            int.from_bytes(payload[offset : offset + 4], "little")
            for offset in range(0, 16, 4)
        ]
        if words != vector["expected_words_le"]:
            raise BringupError(f"vector {vector['index']} word payload mismatch")
    return image, golden


def load_arm_dsb_sy(library_path: Optional[Path] = None) -> Callable[[], None]:
    """Load the target-compiled ``dsb sy`` helper.

    Host dry-runs inject a mock callable.  A real PYNQ run must compile the
    adjacent C source for ARM and place the shared library beside this module,
    or pass an explicit path.
    """
    path = (
        Path(library_path)
        if library_path is not None
        else Path(__file__).with_name("libzephyr_arm_barrier.so")
    )
    if not path.is_file():
        raise BringupError(
            f"ARM dsb helper is missing: {path}; compile arm_barrier.c on PYNQ"
        )
    library = ctypes.CDLL(str(path))
    function = library.zephyr_dsb_sy
    function.argtypes = []
    function.restype = None
    return function


def pynq_allocator(size: int):
    """Allocate the real contiguous uint8 buffer without host import coupling."""
    import numpy as np  # pylint: disable=import-outside-toplevel
    from pynq import allocate  # pylint: disable=import-outside-toplevel

    return allocate(shape=(size,), dtype=np.uint8)


def _free_buffer(buffer) -> None:
    if hasattr(buffer, "freebuffer"):
        buffer.freebuffer()
    elif hasattr(buffer, "close"):
        buffer.close()
    else:
        raise BringupError("allocated buffer has no freebuffer()/close() method")


class ParameterBramDriver:
    """Register-level driver with conservative DDR-buffer ownership."""

    def __init__(
        self,
        mmio,
        *,
        allocator: Callable[[int], object] = pynq_allocator,
        barrier: Optional[Callable[[], None]] = None,
        monotonic: Callable[[], float] = time.monotonic,
        sleep: Callable[[float], None] = time.sleep,
        poll_interval_s: float = 0.001,
    ) -> None:
        self.mmio = mmio
        self.allocator = allocator
        self.barrier = barrier if barrier is not None else load_arm_dsb_sy()
        self.monotonic = monotonic
        self.sleep = sleep
        self.poll_interval_s = poll_interval_s
        self.last_run_evidence: Optional[Dict] = None

    @classmethod
    def from_pynq(cls, **kwargs):
        """Construct against the fixed 0x43c0_0000/4 KiB MMIO aperture."""
        from pynq import MMIO  # pylint: disable=import-outside-toplevel

        return cls(MMIO(CONTROL_BASE, CONTROL_BYTES), **kwargs)

    def _read(self, offset: int) -> int:
        return int(self.mmio.read(offset)) & 0xFFFF_FFFF

    def _write(self, offset: int, value: int) -> None:
        self.mmio.write(offset, int(value) & 0xFFFF_FFFF)

    def _command(self, value: int) -> None:
        self._write(REG_COMMAND, value)
        self.barrier()

    def _weight_command(self, value: int) -> None:
        self._write(REG_WEIGHT_COMMAND, value)
        self.barrier()

    def verify_identity(self) -> Dict[str, int]:
        identity = {
            "hw_id": self._read(REG_HW_ID),
            "abi_version": self._read(REG_ABI_VERSION),
            "capabilities": self._read(REG_CAPABILITIES),
            "cache_bytes": self._read(REG_CACHE_BYTES),
        }
        if identity["hw_id"] != EXPECTED_HW_ID:
            raise BringupError("memory-service HW_ID mismatch")
        if identity["abi_version"] != EXPECTED_ABI_VERSION:
            raise BringupError("memory-service ABI version mismatch")
        if identity["capabilities"] != EXPECTED_CAPABILITIES:
            raise BringupError("memory-service capabilities mismatch")
        if identity["cache_bytes"] != EXPECTED_CACHE_BYTES:
            raise BringupError("memory-service cache size mismatch")
        return identity

    def snapshot_registers(self) -> Dict[str, int]:
        """Capture every software-visible status/error/diagnostic register."""
        return {
            "hw_id": self._read(REG_HW_ID),
            "abi_version": self._read(REG_ABI_VERSION),
            "capabilities": self._read(REG_CAPABILITIES),
            "cache_bytes": self._read(REG_CACHE_BYTES),
            "parameter_base": self._read(REG_PARAMETER_BASE),
            "image_version": self._read(REG_IMAGE_VERSION),
            "stage_id": self._read(REG_STAGE_ID),
            "status": self._read(REG_STATUS),
            "active": self._read(REG_ACTIVE),
            "active_version": self._read(REG_ACTIVE_VERSION),
            "service_error": self._read(REG_SERVICE_ERROR),
            "service_detail": self._read(REG_SERVICE_DETAIL),
            "wrapper_error": self._read(REG_WRAPPER_ERROR),
            "wrapper_detail": self._read(REG_WRAPPER_DETAIL),
            "load_cycles": self._read(REG_LOAD_CYCLES),
            "ar_bursts": self._read(REG_AR_BURSTS),
            "r_beats": self._read(REG_R_BEATS),
            "lut_bytes": self._read(REG_LUT_BYTES),
            "raw_status": self._read(REG_RAW_STATUS),
            "weight_request": self._read(REG_WEIGHT_REQUEST),
            "weight_status": self._read(REG_WEIGHT_STATUS),
        }

    def _wait_for(
        self, predicate: Callable[[int], bool], timeout_s: float, description: str
    ) -> int:
        deadline = self.monotonic() + timeout_s
        while True:
            status = self._read(REG_STATUS)
            if predicate(status):
                return status
            if self.monotonic() >= deadline:
                raise BringupError(f"timeout waiting for {description}: 0x{status:08x}")
            self.sleep(self.poll_interval_s)

    def _fault_text(self) -> str:
        return (
            f"status=0x{self._read(REG_STATUS):08x} "
            f"service=0x{self._read(REG_SERVICE_ERROR):08x}/"
            f"0x{self._read(REG_SERVICE_DETAIL):08x} "
            f"wrapper=0x{self._read(REG_WRAPPER_ERROR):08x}/"
            f"0x{self._read(REG_WRAPPER_DETAIL):08x}"
        )

    def start_stage(self, stage: int, timeout_s: float) -> Dict[str, int]:
        self._wait_for(
            lambda status: bool(
                status & STATUS_STAGE_REQ_READY
                and not status
                & (STATUS_BUSY | STATUS_SERVICE_ERROR | STATUS_WRAPPER_ERROR)
            ),
            timeout_s,
            f"stage {stage} request ready",
        )
        self._write(REG_STAGE_ID, stage)
        self._command(CMD_START)

        def terminal(status: int) -> bool:
            state = (status & STATUS_CACHE_MASK) >> STATUS_CACHE_SHIFT
            return bool(
                (
                    (status & (STATUS_READY | STATUS_DONE))
                    == (STATUS_READY | STATUS_DONE)
                    and not status & STATUS_BUSY
                    and status & STATUS_LUT_READY
                    and state == CACHE_READY
                )
                or status
                & (STATUS_LOAD_ERROR | STATUS_SERVICE_ERROR | STATUS_WRAPPER_ERROR)
            )

        status = self._wait_for(terminal, timeout_s, f"stage {stage} load")
        state = (status & STATUS_CACHE_MASK) >> STATUS_CACHE_SHIFT
        if (
            (status & (STATUS_READY | STATUS_DONE)) != (STATUS_READY | STATUS_DONE)
            or status & STATUS_BUSY
            or state != CACHE_READY
        ):
            raise BringupError(f"stage {stage} load failed: {self._fault_text()}")
        active = self._read(REG_ACTIVE)
        if not active & (1 << 4) or active & 0xF != stage:
            raise BringupError(f"stage {stage} active tag mismatch: 0x{active:08x}")
        if self._read(REG_ACTIVE_VERSION) != IMAGE_VERSION:
            raise BringupError("active image version mismatch")
        return {
            "load_cycles": self._read(REG_LOAD_CYCLES),
            "bursts": self._read(REG_AR_BURSTS),
            "beats": self._read(REG_R_BEATS),
            "lut_bytes": self._read(REG_LUT_BYTES),
        }

    def read_weight_evidence(self, vector: Dict, timeout_s: float) -> Dict:
        """Read, ACK, and return one held response with expected/actual fields."""
        self._wait_for(
            lambda status: bool(
                status & STATUS_WEIGHT_REQ_READY
                and not status
                & (STATUS_SERVICE_ERROR | STATUS_WRAPPER_ERROR)
            ),
            timeout_s,
            "weight request ready",
        )
        request = (
            (int(vector["tag"]) << 24)
            | (int(vector["row_tile"]) << 16)
            | (int(vector["source"]) << 6)
            | int(vector["matrix"])
        )
        self._write(REG_WEIGHT_REQUEST, request)
        self._weight_command(WEIGHT_CMD_REQUEST)

        def response_or_fault(status: int) -> bool:
            return bool(
                status & STATUS_WEIGHT_RSP_VALID
                or status & (STATUS_SERVICE_ERROR | STATUS_WRAPPER_ERROR)
            )

        status = self._wait_for(response_or_fault, timeout_s, "weight response")
        weight_status = self._read(REG_WEIGHT_STATUS)
        if not weight_status & (1 << 2):
            raise BringupError(f"weight response metadata failed: {self._fault_text()}")
        words = [self._read(REG_WEIGHT_DATA0 + 4 * index) for index in range(4)]
        # Re-read status before ACK: all four words belong to one held slot.
        held_status = self._read(REG_WEIGHT_STATUS)
        if held_status != weight_status:
            raise BringupError("weight response slot changed across four MMIO reads")
        self._weight_command(WEIGHT_CMD_ACK)
        if self._read(REG_WEIGHT_STATUS) & (1 << 2):
            raise BringupError("weight response ACK did not retire the holding slot")
        payload = b"".join(word.to_bytes(4, "little") for word in words)
        response_tag = (weight_status >> 8) & 0xFF
        response_error = bool(weight_status & (1 << 3))
        evidence = {
            "index": int(vector["index"]),
            "stage": int(vector["stage"]),
            "matrix": int(vector["matrix"]),
            "source": int(vector["source"]),
            "row_tile": int(vector["row_tile"]),
            "expected_tag": int(vector["tag"]),
            "actual_tag": response_tag,
            "response_error": response_error,
            "expected_hex": vector["expected_lane_bytes_hex"],
            "actual_hex": payload.hex(),
            "expected_words_le": [int(word) for word in vector["expected_words_le"]],
            "actual_words_le": words,
        }
        evidence["matched"] = bool(
            not response_error
            and response_tag == int(vector["tag"])
            and evidence["actual_hex"] == evidence["expected_hex"]
        )
        return evidence

    def read_weight(self, vector: Dict, timeout_s: float) -> bytes:
        evidence = self.read_weight_evidence(vector, timeout_s)
        if not evidence["matched"]:
            raise BringupError(f"readback vector {vector['index']} data mismatch")
        return bytes.fromhex(evidence["actual_hex"])

    def release_stage(self, stage: int, timeout_s: float) -> None:
        self._wait_for(
            lambda status: bool(
                status & STATUS_STAGE_RELEASE_READY
                and not status
                & (STATUS_BUSY | STATUS_SERVICE_ERROR | STATUS_WRAPPER_ERROR)
            ),
            timeout_s,
            f"stage {stage} release ready",
        )
        self._write(REG_STAGE_ID, stage)
        self._command(CMD_RELEASE)

        def released_or_fault(status: int) -> bool:
            state = (status & STATUS_CACHE_MASK) >> STATUS_CACHE_SHIFT
            return bool(
                (state == CACHE_INVALID and not status & STATUS_RAW_BUSY)
                or status & (STATUS_SERVICE_ERROR | STATUS_WRAPPER_ERROR)
            )

        status = self._wait_for(released_or_fault, timeout_s, f"stage {stage} release")
        if status & (STATUS_SERVICE_ERROR | STATUS_WRAPPER_ERROR):
            raise BringupError(f"stage {stage} release failed: {self._fault_text()}")
        if status & STATUS_READY or not status & STATUS_STAGE_REQ_READY:
            raise BringupError(f"stage {stage} release status is incomplete")

    def abort_and_drain(self, timeout_s: float) -> None:
        self._command(CMD_ABORT)

        def drained(status: int) -> bool:
            state = (status & STATUS_CACHE_MASK) >> STATUS_CACHE_SHIFT
            return state == CACHE_INVALID and not status & STATUS_RAW_BUSY

        self._wait_for(drained, timeout_s, "abort drain")

    def prepare_idle(self, timeout_s: float) -> None:
        """Recover a stale prior run and establish the reset/INVALID contract."""
        status = self._read(REG_STATUS)
        if status & STATUS_WEIGHT_RSP_VALID:
            self._weight_command(WEIGHT_CMD_ACK)
            status = self._read(REG_STATUS)

        state = (status & STATUS_CACHE_MASK) >> STATUS_CACHE_SHIFT
        if status & (STATUS_BUSY | STATUS_RAW_BUSY | STATUS_WEIGHT_BUSY) or state in (
            1,
            2,
            3,
            6,
        ):
            self.abort_and_drain(timeout_s)
            status = self._read(REG_STATUS)
            state = (status & STATUS_CACHE_MASK) >> STATUS_CACHE_SHIFT

        if status & (STATUS_SERVICE_ERROR | STATUS_WRAPPER_ERROR) or state == CACHE_ERROR:
            self._command(CMD_CLEAR_ERROR)
            status = self._wait_for(
                lambda value: not value
                & (STATUS_BUSY | STATUS_RAW_BUSY | STATUS_SERVICE_ERROR | STATUS_WRAPPER_ERROR)
                and ((value & STATUS_CACHE_MASK) >> STATUS_CACHE_SHIFT) != CACHE_ERROR,
                timeout_s,
                "error clear",
            )
            state = (status & STATUS_CACHE_MASK) >> STATUS_CACHE_SHIFT

        if state == CACHE_READY:
            active = self._read(REG_ACTIVE)
            if not active & (1 << 4):
                raise BringupError("READY cache has no active owner")
            self.release_stage(active & 0xF, timeout_s)

        # Exercise both explicit software clears even when reset state already
        # reports no fault; at this point every command precondition is idle.
        self._command(CMD_CLEAR_ERROR)
        self._wait_for(
            lambda value: not value
            & (STATUS_BUSY | STATUS_RAW_BUSY | STATUS_SERVICE_ERROR | STATUS_WRAPPER_ERROR),
            timeout_s,
            "explicit sticky-error clear",
        )
        self._command(CMD_CLEAR_EVENTS)
        status = self._wait_for(
            lambda value: bool(
                value & STATUS_STAGE_REQ_READY
                and not value
                & (
                    STATUS_BUSY
                    | STATUS_READY
                    | STATUS_DONE
                    | STATUS_LOAD_ERROR
                    | STATUS_SERVICE_ERROR
                    | STATUS_WRAPPER_ERROR
                    | STATUS_RAW_BUSY
                    | STATUS_WEIGHT_BUSY
                    | STATUS_WEIGHT_RSP_VALID
                    | STATUS_CACHE_MASK
                )
            ),
            timeout_s,
            "clean INVALID state",
        )

    @staticmethod
    def _copy_to_buffer(buffer, image: bytes) -> None:
        try:
            import numpy as np  # pylint: disable=import-outside-toplevel

            buffer[:] = np.frombuffer(image, dtype=np.uint8)
        except ImportError:
            buffer[:] = image

    def run_smoke(
        self,
        image_path: Path,
        golden_path: Path,
        *,
        load_timeout_s: float = 1.0,
        request_timeout_s: float = 0.1,
        recovery_timeout_s: float = 0.1,
    ) -> Dict:
        """Run stage 2 then maximum stage 1 and return machine-readable evidence."""
        image, golden = load_v3_contract(image_path, golden_path)
        vectors = golden["weight_readback_vectors"]["vectors"]
        buffer = self.allocator(len(image))
        pl_may_own_buffer = False
        cleanup_failure = None
        results: Dict = {
            "evidence_class": "pynq-driver-run",
            "image_bytes": len(image),
            "image_sha256": _sha256(image),
            "control_base": CONTROL_BASE,
            "abi_version": 0x0001_0000,
            "stages": [],
        }
        try:
            physical_address = int(buffer.physical_address)
            if physical_address % BUFFER_ALIGNMENT:
                raise BringupError(
                    f"buffer address 0x{physical_address:x} is not 64-byte aligned"
                )
            if physical_address < 0 or physical_address + len(image) - 1 > 0xFFFF_FFFF:
                raise BringupError("buffer is outside the 32-bit HP-addressable range")

            self._copy_to_buffer(buffer, image)
            buffer.flush()
            self.barrier()
            self.verify_identity()
            self.prepare_idle(recovery_timeout_s)
            self._write(REG_PARAMETER_BASE, physical_address)
            self._write(REG_IMAGE_VERSION, IMAGE_VERSION)
            results["buffer_physical_address"] = physical_address
            results["buffer_alignment"] = BUFFER_ALIGNMENT

            for stage in (2, 1):
                pl_may_own_buffer = True
                counters = self.start_stage(stage, load_timeout_s)
                expected = dict(EXPECTED_STAGE_METRICS[stage])
                expected["bursts"] = expected_ar_bursts(
                    physical_address, expected["offset"], expected["bytes"]
                )
                for field in ("beats", "bursts", "lut_bytes"):
                    if counters[field] != expected[field]:
                        raise BringupError(
                            f"stage {stage} {field}={counters[field]}, "
                            f"expected {expected[field]}"
                        )
                stage_vectors: List[Dict] = []
                for vector in vectors:
                    if vector["stage"] == stage:
                        payload = self.read_weight(vector, request_timeout_s)
                        stage_vectors.append(
                            {"index": vector["index"], "data_hex": payload.hex()}
                        )
                self.release_stage(stage, recovery_timeout_s)
                pl_may_own_buffer = False
                results["stages"].append(
                    {
                        "stage": stage,
                        "expected_bytes": expected["bytes"],
                        "counters": counters,
                        "readbacks": stage_vectors,
                    }
                )
            return results
        finally:
            if pl_may_own_buffer:
                try:
                    self.abort_and_drain(recovery_timeout_s)
                    pl_may_own_buffer = False
                except Exception as error:  # retain memory on any uncertain drain
                    cleanup_failure = error
            if not pl_may_own_buffer:
                _free_buffer(buffer)
            if cleanup_failure is not None:
                raise CleanupError(
                    "abort drain did not complete; contiguous buffer was not freed"
                ) from cleanup_failure

    def run_stage2_smoke(
        self,
        image_path: Path,
        golden_path: Path,
        *,
        load_timeout_s: float = 1.0,
        request_timeout_s: float = 0.1,
        recovery_timeout_s: float = 0.1,
    ) -> Dict:
        """Run exactly one Stage 2 load/readback/release board checkpoint."""
        image, golden = load_v3_contract(image_path, golden_path)
        vectors = [
            vector
            for vector in golden["weight_readback_vectors"]["vectors"]
            if vector["stage"] == 2
        ]
        if len(vectors) != 5:
            raise BringupError("Stage 2 contract must contain exactly five vectors")

        results: Dict = {
            "evidence_class": "pynq-stage2-board-smoke",
            "scope": "stage-2-only",
            "outcome": "IN_PROGRESS",
            "image": {
                "bytes": len(image),
                "sha256": _sha256(image),
                "magic_ascii": IMAGE_MAGIC.rstrip(b"\0").decode("ascii"),
                "format_version": IMAGE_VERSION,
                "stage_count": IMAGE_STAGE_COUNT,
            },
            "control_base": CONTROL_BASE,
            "readbacks": [],
        }
        self.last_run_evidence = results
        buffer = None
        pl_may_own_buffer = False
        cleanup_failure = None
        try:
            results["identity"] = self.verify_identity()
            results["initial_registers"] = self.snapshot_registers()
            self.prepare_idle(recovery_timeout_s)
            results["prepared_registers"] = self.snapshot_registers()
            prepared = results["prepared_registers"]
            if prepared["service_error"] or prepared["wrapper_error"]:
                raise BringupError("sticky errors remain after prepare_idle")
            if any(
                prepared[name]
                for name in ("load_cycles", "ar_bursts", "r_beats", "lut_bytes")
            ):
                raise BringupError("diagnostic counters remain after CLEAR_EVENTS")

            buffer = self.allocator(len(image))
            physical_address = int(buffer.physical_address)
            if physical_address % BUFFER_ALIGNMENT:
                raise BringupError(
                    f"buffer address 0x{physical_address:x} is not 64-byte aligned"
                )
            if physical_address < 0 or physical_address + len(image) - 1 > 0xFFFF_FFFF:
                raise BringupError("buffer is outside the 32-bit HP-addressable range")
            results["buffer"] = {
                "physical_address": physical_address,
                "alignment_bytes": BUFFER_ALIGNMENT,
                "address_is_64_byte_aligned": True,
                "address_is_32_bit": True,
                "released": False,
                "freed": False,
            }

            self._copy_to_buffer(buffer, image)
            buffer.flush()
            self.barrier()
            results["buffer"]["flush_completed"] = True
            results["buffer"]["post_flush_dsb_sy_completed"] = True

            self._write(REG_PARAMETER_BASE, physical_address)
            self._write(REG_IMAGE_VERSION, IMAGE_VERSION)
            self._write(REG_STAGE_ID, 2)
            if self._read(REG_PARAMETER_BASE) != physical_address:
                raise BringupError("PARAM_BASE readback mismatch")
            if self._read(REG_IMAGE_VERSION) != IMAGE_VERSION:
                raise BringupError("IMAGE_VERSION readback mismatch")
            if self._read(REG_STAGE_ID) != 2:
                raise BringupError("STAGE_ID readback mismatch")

            pl_may_own_buffer = True
            counters = self.start_stage(2, load_timeout_s)
            terminal_registers = self.snapshot_registers()
            if counters["load_cycles"] == 0:
                raise BringupError("Stage 2 load-cycle counter is zero")
            first_cycle_value = counters["load_cycles"]
            self.barrier()
            self.sleep(max(self.poll_interval_s, 0.000_001))
            frozen_cycle_value = self._read(REG_LOAD_CYCLES)
            if frozen_cycle_value != first_cycle_value:
                raise BringupError(
                    "Stage 2 load-cycle counter changed after terminal state"
                )

            expected = dict(EXPECTED_STAGE_METRICS[2])
            expected["bursts"] = expected_ar_bursts(
                physical_address, expected["offset"], expected["bytes"]
            )
            if expected["bursts"] != 165:
                raise BringupError(
                    f"Stage 2 physical alignment produced {expected['bursts']} bursts, "
                    "but this checkpoint requires 165"
                )
            for field in ("beats", "bursts", "lut_bytes"):
                if counters[field] != expected[field]:
                    raise BringupError(
                        f"stage 2 {field}={counters[field]}, expected {expected[field]}"
                    )
            if terminal_registers["service_error"] or terminal_registers["wrapper_error"]:
                raise BringupError("Stage 2 terminal snapshot contains a sticky error")
            if terminal_registers["raw_status"] & 0x23:
                raise BringupError(
                    "Stage 2 terminal snapshot still has raw busy/drain/counter-active state"
                )
            results["stage2"] = {
                "expected": expected,
                "counters": counters,
                "load_cycles_frozen_value": frozen_cycle_value,
                "terminal_registers": terminal_registers,
            }

            for vector in vectors:
                evidence = self.read_weight_evidence(vector, request_timeout_s)
                results["readbacks"].append(evidence)
                if not evidence["matched"]:
                    raise BringupError(
                        f"readback vector {vector['index']} metadata/data mismatch"
                    )

            self.release_stage(2, recovery_timeout_s)
            self.barrier()
            pl_may_own_buffer = False
            results["buffer"]["released"] = True
            results["buffer"]["post_release_dsb_sy_completed"] = True
            results["release_registers"] = self.snapshot_registers()
            results["outcome"] = "STAGE 2 BOARD SMOKE PASS"
            return results
        except Exception as error:
            results["outcome"] = "FAIL"
            results["failure_type"] = type(error).__name__
            results["failure"] = str(error)
            try:
                results["failure_registers_before_abort"] = self.snapshot_registers()
            except Exception as snapshot_error:
                results["failure_snapshot_error"] = str(snapshot_error)
            raise
        finally:
            if pl_may_own_buffer:
                try:
                    self.abort_and_drain(recovery_timeout_s)
                    self.barrier()
                    pl_may_own_buffer = False
                    results["abort_drain_completed"] = True
                    results["post_abort_dsb_sy_completed"] = True
                except Exception as error:  # retain memory on uncertain drain
                    cleanup_failure = error
                    results["abort_drain_completed"] = False
                    results["abort_drain_error"] = str(error)
            if buffer is not None and not pl_may_own_buffer:
                _free_buffer(buffer)
                if "buffer" in results:
                    results["buffer"]["freed"] = True
            self.last_run_evidence = results
            if cleanup_failure is not None:
                raise CleanupError(
                    "abort drain did not complete; contiguous buffer was not freed"
                ) from cleanup_failure


def validate_artifacts(image_path: Path, golden_path: Path) -> Dict[str, object]:
    image, golden = load_v3_contract(image_path, golden_path)
    return {
        "image_bytes": len(image),
        "image_sha256": _sha256(image),
        "image_magic_ascii": IMAGE_MAGIC.rstrip(b"\0").decode("ascii"),
        "image_format_version": IMAGE_VERSION,
        "readback_vectors": golden["weight_readback_vectors"]["count"],
        "note": "artifact validation only; no PYNQ hardware was accessed",
    }
