#!/usr/bin/env python3
"""PYNQ-Z1 runtime for the Sequential-v4 FPGA inference accelerator.

The production PL boundary consumes one 512-byte signed-Q12 magnitude vector
and one interleaved complex INT8 spectrum per frame.  A checked compatibility
mode retains the previous 64-byte INT8 fullband plus PS mailbox LayerNorm ABI.
The final DMA packet contains 256 little-endian INT32 complex bins.

PYNQ imports are intentionally lazy so the data preparation and DMA register
logic can be tested on a non-PYNQ host.
"""

from __future__ import annotations

import ctypes
import hashlib
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Optional

import numpy as np

try:
    from .accelerator_profile import (
        EXPECTED_IMAGE_VERSION,
        PL_LAYERNORM_IMAGE_VERSION,
        SPARSE_MEMORY_IMAGE_VERSION,
        PROFILING_IMAGE_VERSION,
        REG_PROFILE_CONTROL,
        SUPPORTED_IMAGE_VERSIONS,
        ProfileError,
        profile_control_value,
        read_profile_snapshot,
        read_profile_snapshot_words,
    )
except ImportError:
    from accelerator_profile import (  # type: ignore
        EXPECTED_IMAGE_VERSION,
        PL_LAYERNORM_IMAGE_VERSION,
        SPARSE_MEMORY_IMAGE_VERSION,
        PROFILING_IMAGE_VERSION,
        REG_PROFILE_CONTROL,
        SUPPORTED_IMAGE_VERSIONS,
        ProfileError,
        profile_control_value,
        read_profile_snapshot,
        read_profile_snapshot_words,
    )

try:
    from ..audio_feature_bundle import (
        MAGNITUDE_Q12_SCALE,
        pack_magnitude_frames_q12,
        pack_spectrum_frames_int8,
    )
except ImportError:
    from software.audio_feature_bundle import (  # type: ignore
        MAGNITUDE_Q12_SCALE,
        pack_magnitude_frames_q12,
        pack_spectrum_frames_int8,
    )


CONTROL_BASE = 0x43C0_0000
MAILBOX_BASE = 0x43C1_0000
IO_DMA_BASE = 0x4040_0000
SPECTRUM_DMA_BASE = 0x4041_0000
MMIO_BYTES = 0x1000

REG_COMMAND = 0x000
REG_CONFIG_SHADOW = 0x004
REG_PARAM_BASE_SHADOW = 0x008
REG_STATUS = 0x014
REG_EXECUTION = 0x018
REG_FRAME_ID = 0x01C
REG_STATE_CYCLES = 0x020
REG_FIRST_FAULT = 0x02C
REG_FIRST_FAULT_DETAIL = 0x030
REG_FIRST_FAULT_FRAME = 0x034
REG_PACKET_BYTES_0 = 0x038
REG_PACKET_BYTES_1 = 0x03C
REG_FB_RELEASE = 0x040
REG_SB_CLAIM = 0x044
REG_SB_COMMIT = 0x048
REG_MAILBOX_STATES = 0x04C
REG_EXPECTED_FRAMES_0 = 0x050
REG_EXPECTED_FRAMES_1 = 0x054
REG_MAILBOX_ERROR_0 = 0x064
REG_MAILBOX_ERROR_1 = 0x068
REG_INPUT_BUFFER_STATUS = 0x070
REG_INPUT_FRAME_IDS = 0x074
REG_CONTROL_ERROR = 0x0A0
REG_IMAGE_VERSION = 0x0A4

PL_PACKET_BYTES_0 = (512 << 16) | 512
MAILBOX_PACKET_BYTES_0 = (512 << 16) | 64
EXPECTED_PACKET_BYTES_0 = PL_PACKET_BYTES_0
EXPECTED_PACKET_BYTES_1 = 2048
MAGNITUDE_Q12_FRACTIONAL_BITS = 12
MAGNITUDE_Q12_MAX = 32767.0 / MAGNITUDE_Q12_SCALE

CMD_START = 1 << 0
FB_SLOT_OFFSETS = (0x000, 0x040)
SB_SLOT_OFFSETS = (0x400, 0x800)
SB_PAYLOAD_BYTES = 782
SB_TRANSFER_BYTES = 784

DMA_MM2S_DMACR = 0x00
DMA_MM2S_DMASR = 0x04
DMA_MM2S_ADDRESS = 0x18
DMA_MM2S_LENGTH = 0x28
DMA_S2MM_DMACR = 0x30
DMA_S2MM_DMASR = 0x34
DMA_S2MM_ADDRESS = 0x48
DMA_S2MM_LENGTH = 0x58
DMA_RESET = 1 << 2
DMA_RUN = 1 << 0
DMA_HALTED = 1 << 0
DMA_IDLE = 1 << 1
DMA_ERROR_MASK = 0x0000_0770
DMA_IRQ_MASK = 0x0000_7000
DMA_IOC_IRQ = 1 << 12

FREQ_CUTOFFS = (0, 32, 128, 256)
CENTER_SIZES = (8, 32, 64)
NEIGHBOR_SIZES = (15, 15, 15)
CONTEXT_COUNTS = (4, 3, 2)
SPECTRUM_SCALES = (
    0.20391013678603284,
    0.1222506545660064,
    0.019420942922276776,
)
COEFFICIENT_SCALES = (
    0.009312502981170895,
    0.007257460609195739,
    0.008034150431475302,
)

PROFILE_POINTS = (
    "T00_frame_api_entry",
    "T01_ownership_precheck_complete",
    "T02_frontend_packet_prepare_complete",
    "T03_spectrum_pack_complete",
    "T04_buffer_cache_preparation_complete",
    "T05_dma_descriptors_submitted",
    "T06_input_admission_complete",
    "T07_start_accepted",
    "T08_frontend_service_begin",
    "T09_projection_handoff_complete",
    "T10_subband_transform_complete",
    "T11_frontend_service_commit_complete",
    "T12_output_s2mm_complete",
    "T13_output_invalidate_copy_complete",
    "T14_frame_retirement_fault_check_complete",
    "T15_dequantization_statistics_complete",
    "T16_istft_contribution_complete",
)
PROFILE_DURATION_NAMES = tuple(
    f"{PROFILE_POINTS[index]}__{PROFILE_POINTS[index + 1]}"
    for index in range(len(PROFILE_POINTS) - 1)
)


class InferenceError(RuntimeError):
    """The FPGA runtime or a fixed ABI check failed."""


@dataclass(frozen=True)
class RuntimeParameters:
    fb_weight: np.ndarray
    fb_bias: np.ndarray
    fb_input_scale: float
    fb_projection_scale: float
    sb_weights: tuple[np.ndarray, np.ndarray, np.ndarray]
    sb_biases: tuple[np.ndarray, np.ndarray, np.ndarray]
    sb_input_scales: tuple[float, float, float]

    @classmethod
    def load(cls, path: str | Path) -> "RuntimeParameters":
        with np.load(path, allow_pickle=False) as archive:
            return cls(
                np.asarray(archive["fb_weight"], dtype=np.float32),
                np.asarray(archive["fb_bias"], dtype=np.float32),
                float(archive["fb_input_scale"]),
                float(archive["fb_projection_scale"]),
                tuple(
                    np.asarray(archive[f"sb{index}_weight"], dtype=np.float32)
                    for index in range(3)
                ),
                tuple(
                    np.asarray(archive[f"sb{index}_bias"], dtype=np.float32)
                    for index in range(3)
                ),
                tuple(float(archive[f"sb{index}_input_scale"]) for index in range(3)),
            )

    def validate(self) -> None:
        if self.fb_weight.shape != (64,) or self.fb_bias.shape != (64,):
            raise InferenceError("fullband LayerNorm affine shape must be 64")
        for index, width in enumerate((46, 94, 158)):
            if self.sb_weights[index].shape != (width,):
                raise InferenceError(f"subband {index} LayerNorm weight shape must be {width}")
            if self.sb_biases[index].shape != (width,):
                raise InferenceError(f"subband {index} LayerNorm bias shape must be {width}")
        scales = (self.fb_input_scale, self.fb_projection_scale, *self.sb_input_scales)
        if not all(np.isfinite(scale) and scale > 0 for scale in scales):
            raise InferenceError("LayerNorm quantization scales must be finite and positive")


@dataclass(frozen=True)
class FrameResult:
    frame_id: int
    fb_slot: int
    sb_slot: int
    fb_projection_q: Optional[np.ndarray]
    sb_payload_q: Optional[np.ndarray]
    spectrum_q: np.ndarray
    output_accumulators: np.ndarray
    elapsed_s: float
    mailbox_service_s: float
    state_cycles: int
    profile_timestamps_ns: Optional[tuple[int, ...]] = None
    hardware_profile: Optional[dict[str, object]] = None
    hardware_profile_words: Optional[tuple[int, ...]] = None


@dataclass(frozen=True)
class PreparedFrame:
    """Host-packed frame resident in one of the two DMA buffer slots."""

    frame_id: int
    slot: int
    spectrum_q: np.ndarray


def quantize_int8(values: np.ndarray, scale: float) -> np.ndarray:
    values = np.asarray(values, dtype=np.float64)
    # NumPy rint and torch.round both use round-to-nearest, ties-to-even.
    return np.clip(np.rint(values / float(scale)), -127, 127).astype(np.int8)


def pack_magnitude_q12(magnitude: np.ndarray) -> np.ndarray:
    """Saturate and pack 256 non-negative bins as signed-Q12 little-endian bytes."""

    try:
        values = np.asarray(magnitude)
        if values.shape != (256,):
            raise InferenceError("magnitude must contain exactly 256 bins")
        return pack_magnitude_frames_q12(values.reshape(256, 1))[0]
    except ValueError as exc:
        raise InferenceError(str(exc)) from exc


def layer_norm_quantize(
    values: np.ndarray,
    weight: np.ndarray,
    bias: np.ndarray,
    scale: float,
    *,
    epsilon: float = 1e-5,
) -> np.ndarray:
    values64 = np.asarray(values, dtype=np.float64)
    weight64 = np.asarray(weight, dtype=np.float64)
    bias64 = np.asarray(bias, dtype=np.float64)
    if values64.ndim != 1 or values64.shape != weight64.shape or values64.shape != bias64.shape:
        raise InferenceError("LayerNorm input, weight, and bias shapes must match one vector")
    mean = values64.mean(dtype=np.float64)
    variance = np.mean((values64 - mean) ** 2, dtype=np.float64)
    normalized = (values64 - mean) / np.sqrt(variance + epsilon)
    return quantize_int8(normalized * weight64 + bias64, scale)


def _reflect_window_source(
    magnitude: np.ndarray,
    lower: int,
    upper: int,
    neighbor: int,
) -> np.ndarray:
    if lower == 0:
        return np.pad(magnitude[: upper + neighbor], (neighbor, 0), mode="reflect")
    if upper == magnitude.size:
        return np.pad(magnitude[lower - neighbor :], (0, neighbor), mode="reflect")
    return magnitude[lower - neighbor : upper + neighbor]


def build_subband_payload(
    magnitude: np.ndarray,
    fb_projection_q: np.ndarray,
    parameters: RuntimeParameters,
) -> np.ndarray:
    """Build the fixed mailbox order: 4x46, 3x94, then 2x158."""

    parameters.validate()
    magnitude = np.asarray(magnitude, dtype=np.float32)
    fb_projection_q = np.asarray(fb_projection_q, dtype=np.int8)
    if magnitude.shape != (256,) or fb_projection_q.shape != (64,):
        raise InferenceError("magnitude must be 256 bins and FB projection must be 64 bytes")
    fb_feature = fb_projection_q.astype(np.float32) * np.float32(
        parameters.fb_projection_scale
    )
    fb_feature = np.tile(fb_feature, 4)
    vectors = []
    for band, (lower, upper, center, neighbor, contexts) in enumerate(
        zip(
            FREQ_CUTOFFS[:-1],
            FREQ_CUTOFFS[1:],
            CENTER_SIZES,
            NEIGHBOR_SIZES,
            CONTEXT_COUNTS,
        )
    ):
        source = _reflect_window_source(magnitude, lower, upper, neighbor)
        noisy_width = center + 2 * neighbor
        for context in range(contexts):
            noisy = source[context * center : context * center + noisy_width]
            fb = fb_feature[lower + context * center : lower + (context + 1) * center]
            concatenated = np.concatenate((noisy, fb))
            vectors.append(
                layer_norm_quantize(
                    concatenated,
                    parameters.sb_weights[band],
                    parameters.sb_biases[band],
                    parameters.sb_input_scales[band],
                )
            )
    payload = np.concatenate(vectors).astype(np.int8, copy=False)
    if payload.shape != (SB_PAYLOAD_BYTES,):
        raise AssertionError(f"subband payload is {payload.size} bytes")
    return payload


def _native_subband_layout(
    parameters: RuntimeParameters,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    source_indices = []
    vector_offsets = [0]
    weights = []
    biases = []
    scales = []
    magnitude_indices = np.arange(256, dtype=np.int32)
    for band, (lower, upper, center, neighbor, contexts) in enumerate(
        zip(
            FREQ_CUTOFFS[:-1],
            FREQ_CUTOFFS[1:],
            CENTER_SIZES,
            NEIGHBOR_SIZES,
            CONTEXT_COUNTS,
        )
    ):
        source = _reflect_window_source(magnitude_indices, lower, upper, neighbor)
        noisy_width = center + 2 * neighbor
        for context in range(contexts):
            noisy = source[context * center : context * center + noisy_width]
            fullband = np.arange(
                lower + context * center,
                lower + (context + 1) * center,
                dtype=np.int32,
            )
            fullband = (fullband % 64) + 256
            vector = np.concatenate((noisy, fullband))
            source_indices.append(vector)
            vector_offsets.append(vector_offsets[-1] + vector.size)
            weights.append(parameters.sb_weights[band])
            biases.append(parameters.sb_biases[band])
            scales.append(parameters.sb_input_scales[band])
    return (
        np.ascontiguousarray(np.concatenate(source_indices), dtype=np.uint16),
        np.ascontiguousarray(vector_offsets, dtype=np.uint16),
        np.ascontiguousarray(np.concatenate(weights), dtype=np.float32),
        np.ascontiguousarray(np.concatenate(biases), dtype=np.float32),
        np.ascontiguousarray(scales, dtype=np.float64),
    )


class NativeLayerNormEngine:
    """Checked ctypes wrapper around the target-compiled native kernels."""

    def __init__(
        self,
        library_path: str | Path,
        parameters: RuntimeParameters,
        *,
        epsilon: float = 1e-5,
    ) -> None:
        parameters.validate()
        path = Path(library_path)
        if not path.is_file():
            raise InferenceError(f"native LayerNorm library is missing: {path}")
        self.library = ctypes.CDLL(str(path))
        float_pointer = ctypes.POINTER(ctypes.c_float)
        int8_pointer = ctypes.POINTER(ctypes.c_int8)
        uint16_pointer = ctypes.POINTER(ctypes.c_uint16)
        double_pointer = ctypes.POINTER(ctypes.c_double)
        self.layer_norm = self.library.zephyr_layer_norm_quantize_f32
        self.layer_norm.argtypes = [
            float_pointer,
            float_pointer,
            float_pointer,
            ctypes.c_uint32,
            ctypes.c_double,
            ctypes.c_double,
            int8_pointer,
        ]
        self.layer_norm.restype = ctypes.c_int
        self.build_subbands = self.library.zephyr_build_subband_payload_f32
        self.build_subbands.argtypes = [
            float_pointer,
            int8_pointer,
            uint16_pointer,
            uint16_pointer,
            float_pointer,
            float_pointer,
            double_pointer,
            ctypes.c_double,
            ctypes.c_double,
            int8_pointer,
        ]
        self.build_subbands.restype = ctypes.c_int
        self.parameters = parameters
        self.epsilon = float(epsilon)
        self.fb_weight = np.ascontiguousarray(parameters.fb_weight, dtype=np.float32)
        self.fb_bias = np.ascontiguousarray(parameters.fb_bias, dtype=np.float32)
        (
            self.source_indices,
            self.vector_offsets,
            self.sb_weight,
            self.sb_bias,
            self.sb_scales,
        ) = _native_subband_layout(parameters)
        self.fb_output = np.empty(64, dtype=np.int8)
        self.sb_output = np.empty(SB_PAYLOAD_BYTES, dtype=np.int8)

    @staticmethod
    def _pointer(array: np.ndarray, ctype):
        return array.ctypes.data_as(ctypes.POINTER(ctype))

    def prepare_fullband_input(self, magnitude: np.ndarray) -> np.ndarray:
        values = np.ascontiguousarray(np.asarray(magnitude, dtype=np.float32)[:64])
        if np.asarray(magnitude).shape != (256,):
            raise InferenceError("magnitude must contain 256 bins")
        status = self.layer_norm(
            self._pointer(values, ctypes.c_float),
            self._pointer(self.fb_weight, ctypes.c_float),
            self._pointer(self.fb_bias, ctypes.c_float),
            values.size,
            self.parameters.fb_input_scale,
            self.epsilon,
            self._pointer(self.fb_output, ctypes.c_int8),
        )
        if status != 0:
            raise InferenceError(f"native fullband LayerNorm failed with status {status}")
        return self.fb_output.copy()

    def build_subband_payload(
        self, magnitude: np.ndarray, fullband_projection: np.ndarray
    ) -> np.ndarray:
        magnitude32 = np.ascontiguousarray(magnitude, dtype=np.float32)
        projection8 = np.ascontiguousarray(fullband_projection, dtype=np.int8)
        if magnitude32.shape != (256,) or projection8.shape != (64,):
            raise InferenceError("magnitude must be 256 bins and FB projection must be 64 bytes")
        status = self.build_subbands(
            self._pointer(magnitude32, ctypes.c_float),
            self._pointer(projection8, ctypes.c_int8),
            self._pointer(self.source_indices, ctypes.c_uint16),
            self._pointer(self.vector_offsets, ctypes.c_uint16),
            self._pointer(self.sb_weight, ctypes.c_float),
            self._pointer(self.sb_bias, ctypes.c_float),
            self._pointer(self.sb_scales, ctypes.c_double),
            self.parameters.fb_projection_scale,
            self.epsilon,
            self._pointer(self.sb_output, ctypes.c_int8),
        )
        if status != 0:
            raise InferenceError(f"native subband LayerNorm failed with status {status}")
        return self.sb_output.copy()


class NativeOutputDequantizer:
    """Write the fixed 256-bin complex output directly with one native call."""

    def __init__(self, library_path: str | Path) -> None:
        path = Path(library_path)
        if not path.is_file():
            raise InferenceError(f"native output library is missing: {path}")
        self.library = ctypes.CDLL(str(path))
        self.kernel = self.library.zephyr_dequantize_output_i32
        self.kernel.argtypes = [
            ctypes.POINTER(ctypes.c_int32),
            ctypes.POINTER(ctypes.c_float),
            ctypes.POINTER(ctypes.c_float),
        ]
        self.kernel.restype = ctypes.c_int
        self.batch_kernel = self.library.zephyr_dequantize_output_batch_i32
        self.batch_kernel.argtypes = [
            ctypes.POINTER(ctypes.c_int32),
            ctypes.c_uint32,
            ctypes.POINTER(ctypes.c_float),
            ctypes.POINTER(ctypes.c_float),
        ]
        self.batch_kernel.restype = ctypes.c_int
        self.scales = np.asarray(
            [
                SPECTRUM_SCALES[index] * COEFFICIENT_SCALES[index]
                for index in range(3)
            ],
            dtype=np.float32,
        )

    @staticmethod
    def _pointer(array: np.ndarray, ctype):
        return array.ctypes.data_as(ctypes.POINTER(ctype))

    def dequantize(
        self, accumulators: np.ndarray, output: Optional[np.ndarray] = None
    ) -> np.ndarray:
        values = np.asarray(accumulators)
        if values.dtype != np.int32 or values.shape != (256, 2) or not values.flags.c_contiguous:
            raise InferenceError("native output accumulators must be contiguous INT32 [256, 2]")
        if output is None:
            output = np.empty(256, dtype=np.complex64)
        else:
            output = np.asarray(output)
            if output.dtype != np.complex64 or output.shape != (256,) or not output.flags.c_contiguous:
                raise InferenceError("native complex output must be contiguous complex64 [256]")
        status = self.kernel(
            self._pointer(values, ctypes.c_int32),
            self._pointer(self.scales, ctypes.c_float),
            self._pointer(output.view(np.float32), ctypes.c_float),
        )
        if status != 0:
            raise InferenceError(f"native output dequantization failed with status {status}")
        return output

    def dequantize_batch(
        self, accumulators: np.ndarray, output: Optional[np.ndarray] = None
    ) -> np.ndarray:
        values = np.asarray(accumulators)
        if (
            values.dtype != np.int32
            or values.ndim != 3
            or values.shape[1:] != (256, 2)
            or not values.flags.c_contiguous
            or values.shape[0] == 0
        ):
            raise InferenceError(
                "native output accumulator batch must be contiguous INT32 [frames, 256, 2]"
            )
        if values.shape[0] > 0xFFFF_FFFF:
            raise InferenceError("native output batch has too many frames")
        if output is None:
            output = np.empty((values.shape[0], 256), dtype=np.complex64)
        else:
            output = np.asarray(output)
            if (
                output.dtype != np.complex64
                or output.shape != (values.shape[0], 256)
                or not output.flags.c_contiguous
            ):
                raise InferenceError(
                    "native complex output batch must be contiguous complex64 [frames, 256]"
                )
        status = self.batch_kernel(
            self._pointer(values, ctypes.c_int32),
            values.shape[0],
            self._pointer(self.scales, ctypes.c_float),
            self._pointer(output.view(np.float32), ctypes.c_float),
        )
        if status != 0:
            raise InferenceError(
                f"native batch output dequantization failed with status {status}"
            )
        return output


class NativeDmaEngine:
    """Run the fixed image-v5 DMA submit/poll/start sequence in one C call."""

    def __init__(
        self,
        library_path: str | Path,
        control_words: np.ndarray,
        io_dma_words: np.ndarray,
        spectrum_dma_words: np.ndarray,
    ) -> None:
        path = Path(library_path)
        if not path.is_file():
            raise InferenceError(f"native DMA library is missing: {path}")
        self.library = ctypes.CDLL(str(path))
        self.control_words = self._word_map(control_words, "control")
        self.io_dma_words = self._word_map(io_dma_words, "I/O DMA")
        self.spectrum_dma_words = self._word_map(
            spectrum_dma_words, "spectrum DMA"
        )
        uint32_pointer = ctypes.POINTER(ctypes.c_uint32)
        self.submit_kernel = self.library.zephyr_dma_submit_and_start
        self.submit_kernel.argtypes = [
            uint32_pointer,
            uint32_pointer,
            uint32_pointer,
            ctypes.c_uint32,
            ctypes.c_uint32,
            ctypes.c_uint32,
            ctypes.c_uint32,
            ctypes.c_uint64,
            ctypes.POINTER(ctypes.c_uint64),
            ctypes.POINTER(ctypes.c_uint32),
        ]
        self.submit_kernel.restype = ctypes.c_int
        self.wait_kernel = self.library.zephyr_dma_wait_output
        self.wait_kernel.argtypes = [
            uint32_pointer,
            ctypes.c_uint64,
            ctypes.POINTER(ctypes.c_uint32),
        ]
        self.wait_kernel.restype = ctypes.c_int

    @staticmethod
    def _word_map(words: np.ndarray, name: str) -> np.ndarray:
        view = np.asarray(words)
        if view.ndim != 1 or view.dtype.itemsize != 4 or not view.flags.c_contiguous:
            raise InferenceError(
                f"native {name} register map must be contiguous 32-bit words"
            )
        if not view.flags.writeable:
            raise InferenceError(f"native {name} register map must be writable")
        return view.view(np.uint32)

    @staticmethod
    def _pointer(array: np.ndarray):
        return array.ctypes.data_as(ctypes.POINTER(ctypes.c_uint32))

    @staticmethod
    def _timeout_ns(timeout_s: float) -> int:
        if not np.isfinite(timeout_s) or timeout_s <= 0:
            raise InferenceError("native DMA timeout must be positive and finite")
        return min(int(timeout_s * 1_000_000_000), (1 << 64) - 1)

    def submit_and_start(
        self,
        *,
        output_address: int,
        fullband_address: int,
        fullband_bytes: int,
        spectrum_address: int,
        timeout_s: float,
    ) -> float:
        for address, length in (
            (output_address, 2048),
            (fullband_address, fullband_bytes),
            (spectrum_address, 512),
        ):
            AxiDmaSimpleChannel._validate_transfer(address, length)
            if address > 0xFFFF_FFFF:
                raise InferenceError("native DMA supports 32-bit physical addresses")
        started_ns = ctypes.c_uint64()
        last_status = ctypes.c_uint32()
        status = self.submit_kernel(
            self._pointer(self.control_words),
            self._pointer(self.io_dma_words),
            self._pointer(self.spectrum_dma_words),
            output_address,
            fullband_address,
            fullband_bytes,
            spectrum_address,
            self._timeout_ns(timeout_s),
            ctypes.byref(started_ns),
            ctypes.byref(last_status),
        )
        if status != 0:
            raise InferenceError(
                "native DMA submit/start failed "
                f"with status {status}, input_status=0x{last_status.value:08x}"
            )
        if started_ns.value == 0:
            raise InferenceError("native DMA clock returned an invalid start timestamp")
        return started_ns.value / 1_000_000_000.0

    def wait_output(self, *, timeout_s: float) -> int:
        last_status = ctypes.c_uint32()
        status = self.wait_kernel(
            self._pointer(self.io_dma_words),
            self._timeout_ns(timeout_s),
            ctypes.byref(last_status),
        )
        if status != 0:
            raise InferenceError(
                "native output DMA wait failed "
                f"with status {status}, dma_status=0x{last_status.value:08x}"
            )
        return int(last_status.value)


def prepare_fullband_input(
    magnitude: np.ndarray, parameters: RuntimeParameters
) -> np.ndarray:
    parameters.validate()
    magnitude = np.asarray(magnitude, dtype=np.float32)
    if magnitude.shape != (256,):
        raise InferenceError("magnitude must contain 256 bins")
    return layer_norm_quantize(
        magnitude[:64],
        parameters.fb_weight,
        parameters.fb_bias,
        parameters.fb_input_scale,
    )


def pack_spectrum(spectrum: np.ndarray) -> np.ndarray:
    spectrum = np.asarray(spectrum)
    if spectrum.shape != (256,) or not np.iscomplexobj(spectrum):
        raise InferenceError("spectrum must be one complex vector with 256 bins")
    try:
        return pack_spectrum_frames_int8(spectrum.reshape(256, 1))[0]
    except ValueError as exc:
        raise InferenceError(str(exc)) from exc


def dequantize_output(accumulators: np.ndarray) -> np.ndarray:
    values = np.asarray(accumulators, dtype=np.int32)
    if values.shape != (256, 2):
        raise InferenceError("output accumulators must have shape [256, 2]")
    output = np.empty(256, dtype=np.complex64)
    for band, (lower, upper) in enumerate(zip(FREQ_CUTOFFS[:-1], FREQ_CUTOFFS[1:])):
        scale = SPECTRUM_SCALES[band] * COEFFICIENT_SCALES[band]
        output[lower:upper] = (
            values[lower:upper, 0].astype(np.float32)
            + 1j * values[lower:upper, 1].astype(np.float32)
        ) * np.float32(scale)
    return output


def _mapped_mmio_words(mmio, mode: str) -> Optional[np.ndarray]:
    """Return a uint32 MMIO view for low-overhead register access."""

    if mode not in ("auto", "scalar", "bulk"):
        raise InferenceError("register I/O mode must be auto, scalar, or bulk")
    if mode == "scalar":
        return None
    mapped = getattr(mmio, "array", None)
    if mapped is None:
        if mode == "bulk":
            raise InferenceError("bulk register I/O requires PYNQ MMIO.array")
        return None
    view = np.asarray(mapped)
    if view.ndim != 1 or view.dtype.itemsize != 4:
        if mode == "bulk":
            raise InferenceError("bulk register I/O requires a one-dimensional uint32 map")
        return None
    return view


class AxiDmaSimpleChannel:
    """Minimal direct-register Xilinx AXI DMA simple-mode channel."""

    def __init__(
        self,
        mmio,
        direction: str,
        *,
        monotonic: Callable[[], float] = time.monotonic,
        sleep: Callable[[float], None] = time.sleep,
        poll_interval_s: float = 0.0001,
        register_io_mode: str = "auto",
    ) -> None:
        if direction == "mm2s":
            self.control = DMA_MM2S_DMACR
            self.status = DMA_MM2S_DMASR
            self.address = DMA_MM2S_ADDRESS
            self.length = DMA_MM2S_LENGTH
        elif direction == "s2mm":
            self.control = DMA_S2MM_DMACR
            self.status = DMA_S2MM_DMASR
            self.address = DMA_S2MM_ADDRESS
            self.length = DMA_S2MM_LENGTH
        else:
            raise ValueError("direction must be mm2s or s2mm")
        self.mmio = mmio
        self.words = _mapped_mmio_words(mmio, register_io_mode)
        self.direction = direction
        self.monotonic = monotonic
        self.sleep = sleep
        if poll_interval_s < 0:
            raise ValueError("poll_interval_s must be non-negative")
        self.poll_interval_s = poll_interval_s

    def _read(self, offset: int) -> int:
        if self.words is not None:
            return int(self.words[offset // 4]) & 0xFFFF_FFFF
        return int(self.mmio.read(offset)) & 0xFFFF_FFFF

    def _write(self, offset: int, value: int) -> None:
        if self.words is not None:
            self.words[offset // 4] = np.uint32(int(value) & 0xFFFF_FFFF)
            return
        self.mmio.write(offset, int(value) & 0xFFFF_FFFF)

    def reset(self, timeout_s: float = 0.1) -> None:
        self._write(self.control, DMA_RESET)
        deadline = self.monotonic() + timeout_s
        while self._read(self.control) & DMA_RESET:
            if self.monotonic() >= deadline:
                raise InferenceError(f"{self.direction} DMA reset timed out")
        self.start(timeout_s=timeout_s)

    def start(self, timeout_s: float = 0.1) -> None:
        self._write(self.status, DMA_IRQ_MASK | DMA_ERROR_MASK)
        self._write(self.control, DMA_RUN)
        deadline = self.monotonic() + timeout_s
        while self._read(self.status) & DMA_HALTED:
            if self.monotonic() >= deadline:
                raise InferenceError(f"{self.direction} DMA did not enter run state")

    def submit(self, physical_address: int, length: int) -> None:
        self._validate_transfer(physical_address, length)
        status = self._read(self.status)
        if status & DMA_ERROR_MASK:
            raise InferenceError(f"{self.direction} DMA pre-submit error 0x{status:08x}")
        self._write(self.status, DMA_IRQ_MASK)
        self._write(self.address, physical_address)
        self._write(self.length, length)

    def submit_fast(self, physical_address: int, length: int) -> None:
        """Submit after a prior completion/admission fence established ownership."""

        self._validate_transfer(physical_address, length)
        self._write(self.address, physical_address)
        self._write(self.length, length)

    @staticmethod
    def _validate_transfer(physical_address: int, length: int) -> None:
        if physical_address & 0x7:
            raise InferenceError("DMA address must be 64-bit aligned")
        if not 0 < length < (1 << 26):
            raise InferenceError("DMA transfer length is outside simple-mode range")

    def wait(self, timeout_s: float = 2.0) -> int:
        deadline = self.monotonic() + timeout_s
        while True:
            status = self._read(self.status)
            if status & DMA_ERROR_MASK:
                raise InferenceError(f"{self.direction} DMA error 0x{status:08x}")
            if status & DMA_IOC_IRQ:
                self._write(self.status, DMA_IOC_IRQ)
                return status
            if self.monotonic() >= deadline:
                raise InferenceError(f"{self.direction} DMA completion timed out: 0x{status:08x}")
            if self.poll_interval_s:
                self.sleep(self.poll_interval_s)


class MailboxIO:
    """Scalar reference and contiguous uint32 mailbox access with one ABI."""

    def __init__(self, mmio, mode: str = "bulk") -> None:
        if mode not in ("scalar", "bulk"):
            raise InferenceError("mailbox I/O mode must be scalar or bulk")
        self.mmio = mmio
        self.mode = mode
        self.array = None
        if mode == "bulk":
            mapped = getattr(mmio, "array", None)
            if mapped is None:
                raise InferenceError("bulk mailbox I/O requires the PYNQ MMIO.array mapping")
            view = np.asarray(mapped)
            if view.ndim != 1 or view.dtype.itemsize != 4 or view.nbytes < MMIO_BYTES:
                raise InferenceError("bulk mailbox mapping must expose at least 4 KiB of uint32 words")
            self.array = view

    def read_fullband_projection(self, slot: int) -> np.ndarray:
        if slot not in (0, 1):
            raise InferenceError("fullband mailbox slot must be 0 or 1")
        base = FB_SLOT_OFFSETS[slot]
        if self.mode == "scalar":
            payload = bytearray()
            for word_index in range(16):
                payload.extend(
                    int(self.mmio.read(base + 4 * word_index)).to_bytes(4, "little")
                )
            return np.frombuffer(bytes(payload), dtype=np.int8).copy()
        start = base // 4
        words = np.asarray(self.array[start : start + 16], dtype="<u4")
        return np.frombuffer(words.tobytes(), dtype=np.int8).copy()

    def write_subbands(self, slot: int, payload: np.ndarray) -> None:
        if slot not in (0, 1):
            raise InferenceError("subband mailbox slot must be 0 or 1")
        raw = np.asarray(payload, dtype=np.int8).tobytes() + b"\x00\x00"
        if len(raw) != SB_TRANSFER_BYTES:
            raise InferenceError("subband transfer must be 782 bytes plus two pad bytes")
        base = SB_SLOT_OFFSETS[slot]
        if self.mode == "scalar":
            for word_index in range(SB_TRANSFER_BYTES // 4):
                value = int.from_bytes(
                    raw[word_index * 4 : word_index * 4 + 4], "little"
                )
                self.mmio.write(base + word_index * 4, value)
            final_word = int(self.mmio.read(base + SB_TRANSFER_BYTES - 4))
        else:
            start = base // 4
            words = np.frombuffer(raw, dtype="<u4")
            self.array[start : start + words.size] = words
            final_word = int(self.array[start + words.size - 1])
        if final_word >> 16:
            raise InferenceError("mailbox pad-byte readback is nonzero")


class PynqAcceleratorRuntime:
    """Own all buffers and execute ordered accelerator frames."""

    def __init__(
        self,
        parameter_image: str | Path,
        runtime_parameters: RuntimeParameters,
        *,
        expected_parameter_sha256: Optional[str] = None,
        poll_interval_s: float = 0.00005,
        mailbox_io_mode: str = "scalar",
        frontend_mode: str = "pl",
        layernorm_mode: str = "numpy",
        native_layernorm_library: Optional[str | Path] = None,
        native_dma_library: Optional[str | Path] = None,
        profiling: bool = False,
        hardware_profiling: bool = False,
        per_frame_diagnostics: bool = False,
        conservative_output_cache: bool = True,
        register_io_mode: str = "bulk",
        fast_dma_submit: bool = True,
    ) -> None:
        from pynq import MMIO, Overlay, allocate  # pylint: disable=import-outside-toplevel

        # JTAG programming does not update PYNQ's process-local DDR metadata.
        # Parsing the stock overlay without downloading it supplies the same
        # Zynq PS DDR allocator description while preserving the live PL image.
        Overlay("/home/xilinx/pynq/overlays/base/base.bit", download=False)
        self.control = MMIO(CONTROL_BASE, MMIO_BYTES)
        self.control_words = _mapped_mmio_words(self.control, register_io_mode)
        self.mailbox = MMIO(MAILBOX_BASE, MMIO_BYTES)
        self.mailbox_io = MailboxIO(self.mailbox, mailbox_io_mode)
        io_dma = MMIO(IO_DMA_BASE, MMIO_BYTES)
        spectrum_dma = MMIO(SPECTRUM_DMA_BASE, MMIO_BYTES)
        self.fb_tx = AxiDmaSimpleChannel(
            io_dma,
            "mm2s",
            poll_interval_s=poll_interval_s,
            register_io_mode=register_io_mode,
        )
        self.output_rx = AxiDmaSimpleChannel(
            io_dma,
            "s2mm",
            poll_interval_s=poll_interval_s,
            register_io_mode=register_io_mode,
        )
        self.spectrum_tx = AxiDmaSimpleChannel(
            spectrum_dma,
            "mm2s",
            poll_interval_s=poll_interval_s,
            register_io_mode=register_io_mode,
        )
        self.poll_interval_s = poll_interval_s
        if frontend_mode not in ("pl", "mailbox"):
            raise InferenceError("frontend mode must be pl or mailbox")
        self.frontend_mode = frontend_mode
        self.profiling = bool(profiling)
        self.hardware_profiling = bool(hardware_profiling)
        self.per_frame_diagnostics = bool(per_frame_diagnostics)
        self.conservative_output_cache = bool(conservative_output_cache)
        self.fast_dma_submit = bool(fast_dma_submit)
        self._last_config = None
        self._parameter_base_committed = False
        self.parameters = runtime_parameters
        self.parameters.validate()
        if self.frontend_mode == "pl":
            self.layernorm_engine = None
        elif layernorm_mode == "numpy":
            self.layernorm_engine = None
        elif layernorm_mode == "native":
            if native_layernorm_library is None:
                raise InferenceError("native LayerNorm mode requires a compiled library path")
            self.layernorm_engine = NativeLayerNormEngine(
                native_layernorm_library, self.parameters
            )
        else:
            raise InferenceError("LayerNorm mode must be numpy or native")
        self.native_dma_engine = None
        if native_dma_library is not None:
            if self.frontend_mode != "pl":
                raise InferenceError("native DMA control requires the PL frontend")
            if not self.fast_dma_submit:
                raise InferenceError("native DMA control requires fast DMA submit")
            if self.control_words is None:
                raise InferenceError("native DMA control requires bulk register I/O")
            if self.fb_tx.words is None or self.spectrum_tx.words is None:
                raise InferenceError("native DMA control requires bulk DMA register I/O")
            self.native_dma_engine = NativeDmaEngine(
                native_dma_library,
                self.control_words,
                self.fb_tx.words,
                self.spectrum_tx.words,
            )

        payload = Path(parameter_image).read_bytes()
        digest = hashlib.sha256(payload).hexdigest()
        if expected_parameter_sha256 is not None and digest != expected_parameter_sha256:
            raise InferenceError(
                f"parameter image SHA-256 mismatch: {digest} != {expected_parameter_sha256}"
            )
        self.parameter_buffer = allocate(shape=(len(payload),), dtype=np.uint8)
        self.fb_buffers = tuple(
            allocate(
                shape=(512 if self.frontend_mode == "pl" else 64,), dtype=np.uint8
            )
            for _ in range(2)
        )
        self.spectrum_buffers = tuple(
            allocate(shape=(512,), dtype=np.uint8) for _ in range(2)
        )
        self.output_buffers = tuple(
            allocate(shape=(2048,), dtype=np.uint8) for _ in range(2)
        )
        self.output_views = tuple(
            np.asarray(buffer).view("<i4").reshape(256, 2)
            for buffer in self.output_buffers
        )
        for output_buffer in self.output_buffers:
            output_buffer[:] = 0
            output_buffer.flush()
        self.parameter_buffer[:] = np.frombuffer(payload, dtype=np.uint8)
        self.parameter_buffer.flush()
        if int(self.parameter_buffer.physical_address) & 0x3F:
            raise InferenceError("allocated parameter buffer is not 64-byte aligned")

        self.image_version = self._verify_identity()
        # The output DMA's final TLAST is the production retirement fence.  Read
        # the hardware sequence once at startup, then track it locally instead
        # of paying for multiple AXI-Lite reads after every successful frame.
        self.expected_frame_id = self._read(REG_FRAME_ID) & 0xFFFF
        if self.hardware_profiling and self.image_version < PROFILING_IMAGE_VERSION:
            raise InferenceError(
                f"hardware profiling requires image 0x{PROFILING_IMAGE_VERSION:08x}; "
                f"loaded 0x{self.image_version:08x}"
            )
        # MM2S and S2MM are channels of one I/O DMA core. Resetting either
        # channel resets that whole core, so reset it once and then enable the
        # second channel without another reset. Spectrum is a separate core.
        self.fb_tx.reset()
        self.output_rx.start()
        self.spectrum_tx.reset()
        if self.hardware_profiling:
            self._write(
                REG_PROFILE_CONTROL,
                profile_control_value(enable=True, clear=True),
            )
            self._barrier()

    def close(self) -> None:
        for name in ("output_buffers", "spectrum_buffers", "fb_buffers"):
            buffers = getattr(self, name, ())
            for buffer in buffers:
                buffer.freebuffer()
            setattr(self, name, ())
        if self.parameter_buffer is not None:
            self.parameter_buffer.freebuffer()
            self.parameter_buffer = None

    def __enter__(self) -> "PynqAcceleratorRuntime":
        return self

    def __exit__(self, exc_type, exc_value, traceback) -> None:
        self.close()

    def _read(self, offset: int) -> int:
        control_words = getattr(self, "control_words", None)
        if control_words is not None:
            return int(control_words[offset // 4]) & 0xFFFF_FFFF
        return int(self.control.read(offset)) & 0xFFFF_FFFF

    def _write(self, offset: int, value: int) -> None:
        control_words = getattr(self, "control_words", None)
        if control_words is not None:
            control_words[offset // 4] = np.uint32(int(value) & 0xFFFF_FFFF)
            return
        self.control.write(offset, int(value) & 0xFFFF_FFFF)

    def _barrier(self) -> None:
        # A read response on the same Device mapping orders prior MMIO writes.
        self._read(REG_IMAGE_VERSION)

    def _verify_identity(self) -> int:
        actual = (
            self._read(REG_IMAGE_VERSION),
            self._read(REG_PACKET_BYTES_0),
            self._read(REG_PACKET_BYTES_1),
        )
        if self.frontend_mode == "pl":
            supported_images = (
                PL_LAYERNORM_IMAGE_VERSION,
                SPARSE_MEMORY_IMAGE_VERSION,
            )
            expected_packets = (PL_PACKET_BYTES_0, EXPECTED_PACKET_BYTES_1)
        else:
            supported_images = tuple(
                version for version in SUPPORTED_IMAGE_VERSIONS
                if version not in (
                    PL_LAYERNORM_IMAGE_VERSION,
                    SPARSE_MEMORY_IMAGE_VERSION,
                )
            )
            expected_packets = (MAILBOX_PACKET_BYTES_0, EXPECTED_PACKET_BYTES_1)
        if actual[0] not in supported_images or actual[1:] != expected_packets:
            raise InferenceError(
                f"accelerator ABI mismatch: {actual!r}; "
                f"frontend={self.frontend_mode!r} supported_images={supported_images!r} "
                f"expected_packets={expected_packets!r}"
            )
        if self._read(REG_CONTROL_ERROR) & 0x100:
            raise InferenceError("control plane already has a sticky error")
        if self._read(REG_FIRST_FAULT) & (1 << 24):
            raise InferenceError("accelerator already has a latched fault")
        return actual[0]

    def read_hardware_profile(self, *, expected_frame_id: int) -> dict[str, object]:
        if not self.hardware_profiling:
            raise InferenceError("hardware profiling was not enabled for this runtime")
        try:
            return read_profile_snapshot(
                self._read,
                read_words=self._read_control_words,
                expected_frame_id=expected_frame_id,
            )
        except ProfileError as exc:
            raise InferenceError(str(exc)) from exc

    def read_hardware_profile_words(self, *, expected_frame_id: int) -> tuple[int, ...]:
        """Bulk-copy a coherent snapshot for decoding outside the frame loop."""

        if not self.hardware_profiling:
            raise InferenceError("hardware profiling was not enabled for this runtime")
        try:
            return read_profile_snapshot_words(
                self._read,
                read_words=self._read_control_words,
                expected_frame_id=expected_frame_id,
            )
        except ProfileError as exc:
            raise InferenceError(str(exc)) from exc

    def _read_control_words(self, offset: int, count: int):
        control_words = getattr(self, "control_words", None)
        if control_words is None:
            return [self._read(offset + index * 4) for index in range(count)]
        start = offset // 4
        return np.asarray(
            control_words[start : start + count], dtype=np.uint32
        ).copy()

    def diagnostic_snapshot(self) -> dict[str, object]:
        """Capture final control and DMA state without changing ownership."""

        control_offsets = {
            "status": REG_STATUS,
            "execution": REG_EXECUTION,
            "frame_id": REG_FRAME_ID,
            "state_cycles": REG_STATE_CYCLES,
            "first_fault": REG_FIRST_FAULT,
            "first_fault_detail": REG_FIRST_FAULT_DETAIL,
            "first_fault_frame": REG_FIRST_FAULT_FRAME,
            "mailbox_error_0": REG_MAILBOX_ERROR_0,
            "mailbox_error_1": REG_MAILBOX_ERROR_1,
            "control_error": REG_CONTROL_ERROR,
            "image_version": REG_IMAGE_VERSION,
        }
        channels = {
            "io_mm2s": self.fb_tx,
            "io_s2mm": self.output_rx,
            "spectrum_mm2s": self.spectrum_tx,
        }
        dma = {}
        for name, channel in channels.items():
            status = channel._read(channel.status)
            dma[name] = {
                "control": channel._read(channel.control),
                "status": status,
                "idle": bool(status & DMA_IDLE),
                "halted": bool(status & DMA_HALTED),
                "errors": status & DMA_ERROR_MASK,
            }
        return {
            "control": {
                name: self._read(offset) for name, offset in control_offsets.items()
            },
            "dma": dma,
        }

    @staticmethod
    def _event(slot: int, frame_id: int) -> int:
        return 0x8000_0000 | ((frame_id & 0xFFFF) << 1) | (slot & 1)

    def _raise_if_fault(self, context: str) -> None:
        control_error = self._read(REG_CONTROL_ERROR)
        first_fault = self._read(REG_FIRST_FAULT)
        if (control_error & 0x100) or (first_fault & (1 << 24)):
            detail = self._read(REG_FIRST_FAULT_DETAIL)
            fault_frame = self._read(REG_FIRST_FAULT_FRAME)
            execution = self._read(REG_EXECUTION)
            mailbox0 = self._read(REG_MAILBOX_ERROR_0)
            mailbox1 = self._read(REG_MAILBOX_ERROR_1)
            raise InferenceError(
                f"{context}: control=0x{control_error:08x} first=0x{first_fault:08x} "
                f"detail=0x{detail:08x} frame=0x{fault_frame:08x} "
                f"execution=0x{execution:08x} mailbox=0x{mailbox0:08x}/0x{mailbox1:08x}"
            )

    def _raise_if_dma_fault(self, context: str) -> None:
        faults = []
        for name, channel in (
            ("io-mm2s", self.fb_tx),
            ("io-s2mm", self.output_rx),
            ("spectrum-mm2s", self.spectrum_tx),
        ):
            status = channel._read(channel.status)
            if status & DMA_ERROR_MASK:
                faults.append(f"{name}=0x{status:08x}")
        if faults:
            raise InferenceError(f"{context}: DMA error {' '.join(faults)}")

    def _wait_for(
        self,
        predicate,
        timeout_s: float,
        context: str,
        *,
        check_faults: bool = True,
    ):
        deadline = time.monotonic() + timeout_s
        while True:
            if check_faults:
                self._raise_if_fault(context)
            value = predicate()
            if value is not None:
                return value
            if time.monotonic() >= deadline:
                # Fault registers stay off the successful hot path but remain
                # available when a transfer genuinely fails to make progress.
                if not check_faults:
                    self._raise_if_fault(context)
                raise InferenceError(
                    f"{context} timed out: status=0x{self._read(REG_STATUS):08x} "
                    f"execution=0x{self._read(REG_EXECUTION):08x} "
                    f"state_cycles={self._read(REG_STATE_CYCLES)}"
                )
            if self.poll_interval_s:
                time.sleep(self.poll_interval_s)

    def _wait_for_fb_slot(self, timeout_s: float) -> int:
        def ready_slot():
            states = self._read(REG_MAILBOX_STATES) & 0xF
            ready = [slot for slot in (0, 1) if ((states >> (2 * slot)) & 0x3) == 2]
            return ready[0] if ready else None

        return int(self._wait_for(ready_slot, timeout_s, "fullband mailbox publish"))

    def _read_fb_projection(self, slot: int) -> np.ndarray:
        return self.mailbox_io.read_fullband_projection(slot)

    def _write_subbands(self, slot: int, payload: np.ndarray) -> None:
        self.mailbox_io.write_subbands(slot, payload)

    def prepare_frame(
        self,
        magnitude: np.ndarray,
        spectrum: np.ndarray,
        *,
        frame_id: Optional[int] = None,
        profile_mark: Optional[Callable[[], None]] = None,
    ) -> PreparedFrame:
        """Pack and flush a frame into its parity-selected A/B DMA slot."""

        expected_frame_id = (
            self.expected_frame_id
            if frame_id is None
            else int(frame_id) & 0xFFFF
        )
        slot = expected_frame_id & 1
        if self.frontend_mode == "pl":
            fb_q = pack_magnitude_q12(magnitude)
        elif self.layernorm_engine is None:
            fb_q = prepare_fullband_input(magnitude, self.parameters)
        else:
            fb_q = self.layernorm_engine.prepare_fullband_input(magnitude)
        if profile_mark is not None:
            profile_mark()
        spectrum_q = pack_spectrum(spectrum)
        if profile_mark is not None:
            profile_mark()

        return self.prepare_packed_frame(
            fb_q,
            spectrum_q,
            frame_id=expected_frame_id,
            profile_mark=profile_mark,
        )

    def prepare_packed_frame(
        self,
        fb_q: np.ndarray,
        spectrum_q: np.ndarray,
        *,
        frame_id: Optional[int] = None,
        profile_mark: Optional[Callable[[], None]] = None,
    ) -> PreparedFrame:
        """Copy already-quantized packets into one parity-selected CMA slot."""

        expected_frame_id = (
            self.expected_frame_id
            if frame_id is None
            else int(frame_id) & 0xFFFF
        )
        slot = expected_frame_id & 1
        expected_fb_bytes = 512 if self.frontend_mode == "pl" else 64
        fb_q = np.asarray(fb_q)
        spectrum_q = np.asarray(spectrum_q)
        if fb_q.shape != (expected_fb_bytes,) or fb_q.dtype not in (np.uint8, np.int8):
            raise InferenceError(
                f"packed fullband input must contain {expected_fb_bytes} bytes"
            )
        if spectrum_q.shape != (512,) or spectrum_q.dtype not in (np.uint8, np.int8):
            raise InferenceError("packed spectrum input must contain 512 bytes")
        fb_buffer = self.fb_buffers[slot]
        spectrum_buffer = self.spectrum_buffers[slot]
        output_buffer = self.output_buffers[slot]
        fb_buffer[:] = fb_q.view(np.uint8)
        spectrum_buffer[:] = spectrum_q.view(np.uint8)
        fb_buffer.flush()
        spectrum_buffer.flush()
        if self.conservative_output_cache:
            output_buffer[:] = 0
            output_buffer.flush()
        if profile_mark is not None:
            profile_mark()
        return PreparedFrame(
            frame_id=expected_frame_id,
            slot=slot,
            spectrum_q=spectrum_q,
        )

    def run_frame(
        self,
        magnitude: np.ndarray,
        spectrum: np.ndarray,
        *,
        clear_state: bool,
        sparse: bool = True,
        timeout_s: float = 5.0,
        prepared_frame: Optional[PreparedFrame] = None,
        during_execution: Optional[Callable[[], None]] = None,
        collect_hardware_profile: bool = True,
    ) -> FrameResult:
        profile_timestamps = [] if self.profiling else None

        def profile_mark() -> None:
            if profile_timestamps is not None:
                profile_timestamps.append(time.monotonic_ns())

        profile_mark()
        frame_id = self.expected_frame_id
        if self.frontend_mode == "mailbox":
            expected = self._read(REG_EXPECTED_FRAMES_0)
            if (expected & 0xFFFF) != frame_id or ((expected >> 16) & 0xFFFF) != frame_id:
                raise InferenceError(
                    f"mailbox sequence does not match frame {frame_id}: 0x{expected:08x}"
                )

        profile_mark()
        if prepared_frame is None:
            prepared_frame = self.prepare_frame(
                magnitude,
                spectrum,
                frame_id=frame_id,
                profile_mark=profile_mark,
            )
        else:
            if prepared_frame.frame_id != frame_id:
                raise InferenceError(
                    f"prepared frame ID {prepared_frame.frame_id} does not match "
                    f"hardware frame ID {frame_id}"
                )
            if prepared_frame.slot != (frame_id & 1):
                raise InferenceError("prepared frame selected the wrong DMA buffer slot")
            # Packing and cache maintenance ran concurrently with the previous
            # PL frame. Preserve the fixed T00-T14 profile shape with zero-cost
            # marks at the three already-completed preparation boundaries.
            profile_mark()
            profile_mark()
            profile_mark()
        dma_slot = prepared_frame.slot
        fb_buffer = self.fb_buffers[dma_slot]
        spectrum_buffer = self.spectrum_buffers[dma_slot]
        output_buffer = self.output_buffers[dma_slot]
        spectrum_q = prepared_frame.spectrum_q

        config = int(bool(sparse)) | (int(bool(clear_state)) << 1)
        if config != getattr(self, "_last_config", None):
            self._write(REG_CONFIG_SHADOW, config)
            self._last_config = config
        if not getattr(self, "_parameter_base_committed", False):
            self._write(
                REG_PARAM_BASE_SHADOW,
                int(self.parameter_buffer.physical_address),
            )
            self._parameter_base_committed = True

        use_native_dma = (
            self.native_dma_engine is not None
            and not self.profiling
            and not self.hardware_profiling
            and not self.per_frame_diagnostics
        )
        if use_native_dma:
            try:
                started = self.native_dma_engine.submit_and_start(
                    output_address=int(output_buffer.physical_address),
                    fullband_address=int(fb_buffer.physical_address),
                    fullband_bytes=int(fb_buffer.size),
                    spectrum_address=int(spectrum_buffer.physical_address),
                    timeout_s=timeout_s,
                )
            except InferenceError:
                self._raise_if_dma_fault("native input packet admission")
                self._raise_if_fault("native input packet admission")
                raise
            profile_mark()
            profile_mark()
            profile_mark()
        else:
            submit = (
                AxiDmaSimpleChannel.submit_fast
                if getattr(self, "fast_dma_submit", False)
                else AxiDmaSimpleChannel.submit
            )
            submit(self.output_rx, int(output_buffer.physical_address), 2048)
            submit(self.fb_tx, int(fb_buffer.physical_address), int(fb_buffer.size))
            submit(self.spectrum_tx, int(spectrum_buffer.physical_address), 512)
            profile_mark()
            if not getattr(self, "fast_dma_submit", False):
                self.fb_tx.wait(timeout_s=timeout_s)
                self.spectrum_tx.wait(timeout_s=timeout_s)

            def input_packet_admitted():
                status = self._read(REG_INPUT_BUFFER_STATUS)
                return status if (status & 3) == 3 else None

            try:
                self._wait_for(
                    input_packet_admitted,
                    timeout_s,
                    "input packet admission",
                    check_faults=self.per_frame_diagnostics,
                )
            except InferenceError:
                self._raise_if_dma_fault("input packet admission")
                raise
            profile_mark()

            started = time.monotonic()
            self._write(REG_COMMAND, CMD_START)
            self._barrier()
            profile_mark()
        overlap_error = None
        if during_execution is not None:
            try:
                during_execution()
            except Exception as error:  # finish the in-flight frame before failing
                overlap_error = error
        if self.frontend_mode == "pl":
            fb_slot = -1
            sb_slot = -1
            fb_projection_q = None
            sb_payload = None
            mailbox_service_s = 0.0
            profile_mark()
            profile_mark()
            profile_mark()
            profile_mark()
        else:
            fb_slot = self._wait_for_fb_slot(timeout_s)
            profile_mark()
            mailbox_started = time.monotonic()
            fb_projection_q = self._read_fb_projection(fb_slot)
            self._write(REG_FB_RELEASE, self._event(fb_slot, frame_id))
            self._barrier()
            profile_mark()

            if self.layernorm_engine is None:
                sb_payload = build_subband_payload(magnitude, fb_projection_q, self.parameters)
            else:
                sb_payload = self.layernorm_engine.build_subband_payload(
                    magnitude, fb_projection_q
                )
            profile_mark()
            sb_slot = frame_id & 1
            self._write(REG_SB_CLAIM, self._event(sb_slot, frame_id))
            self._barrier()
            self._write_subbands(sb_slot, sb_payload)
            self._write(REG_SB_COMMIT, self._event(sb_slot, frame_id))
            self._barrier()
            profile_mark()
            mailbox_service_s = time.monotonic() - mailbox_started

        try:
            if use_native_dma:
                self.native_dma_engine.wait_output(timeout_s=timeout_s)
            else:
                self.output_rx.wait(timeout_s=timeout_s)
        except InferenceError:
            # Read detailed PL diagnostics only on the exceptional path.  DMA
            # status remains the normal completion and error authority.
            self._raise_if_dma_fault("output DMA completion")
            self._raise_if_fault("output DMA completion")
            raise
        profile_mark()
        output_buffer.invalidate()
        output = self.output_views[dma_slot]
        profile_mark()
        next_frame = (frame_id + 1) & 0xFFFF
        if self.per_frame_diagnostics:
            self._wait_for(
                lambda: next_frame
                if (self._read(REG_FRAME_ID) & 0xFFFF) == next_frame
                else None,
                timeout_s,
                "frame retirement",
            )
            self._raise_if_fault("frame completion")
        self.expected_frame_id = next_frame
        elapsed_s = time.monotonic() - started
        if overlap_error is not None:
            raise overlap_error
        state_cycles = (
            self._read(REG_STATE_CYCLES)
            if self.profiling or self.per_frame_diagnostics
            else 0
        )
        hardware_profile_words = (
            self.read_hardware_profile_words(expected_frame_id=frame_id)
            if self.hardware_profiling and collect_hardware_profile
            else None
        )
        profile_mark()
        return FrameResult(
            frame_id=frame_id,
            fb_slot=fb_slot,
            sb_slot=sb_slot,
            fb_projection_q=fb_projection_q,
            sb_payload_q=sb_payload.copy() if sb_payload is not None else None,
            spectrum_q=spectrum_q,
            output_accumulators=output,
            elapsed_s=elapsed_s,
            mailbox_service_s=mailbox_service_s,
            state_cycles=state_cycles,
            profile_timestamps_ns=(
                tuple(profile_timestamps) if profile_timestamps is not None else None
            ),
            hardware_profile=None,
            hardware_profile_words=hardware_profile_words,
        )
