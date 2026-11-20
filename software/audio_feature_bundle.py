#!/usr/bin/env python3
"""Portable, checksummed host-side STFT and magnitude feature bundles."""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import time
import wave
from pathlib import Path

import numpy as np


SCHEMA = "zephyr.audio-feature-bundle.v2"
LEGACY_SCHEMA = "zephyr.audio-feature-bundle.v1"
SAMPLE_RATE = 16_000
FFT_SIZE = 512
HOP_SIZE = 128
SPECTRUM_BINS = FFT_SIZE // 2 + 1
HARDWARE_BINS = 256
MAGNITUDE_SEMANTICS = "sqrt(abs(complex_spectrum[:256]))"
PACKED_ABI = "image-v5-pl-q12-spectrum-int8-v1"
MAGNITUDE_Q12_SCALE = 1 << 12
SPECTRUM_SCALES = (
    0.20391013678603284,
    0.1222506545660064,
    0.019420942922276776,
)
FREQ_CUTOFFS = (0, 32, 128, 256)


class FeatureBundleError(ValueError):
    """Raised when a feature bundle does not satisfy the runtime contract."""


@dataclass(frozen=True)
class AudioFeatureBundle:
    spectrum: np.ndarray
    magnitude: np.ndarray
    magnitude_q12: np.ndarray | None
    spectrum_q: np.ndarray | None
    metadata: dict[str, object]
    metadata_sha256: str


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_pcm16(path: Path) -> np.ndarray:
    """Read the runtime's fixed 16 kHz, mono, signed-PCM input contract."""

    with wave.open(str(path), "rb") as handle:
        channels = handle.getnchannels()
        sample_width = handle.getsampwidth()
        sample_rate = handle.getframerate()
        compression = handle.getcomptype()
        frames = handle.getnframes()
        payload = handle.readframes(frames)
    if (channels, sample_width, sample_rate, compression) != (1, 2, SAMPLE_RATE, "NONE"):
        raise FeatureBundleError(
            "input WAV must be mono, 16-bit PCM, 16000 Hz; "
            f"got channels={channels}, width={sample_width}, rate={sample_rate}, "
            f"compression={compression}"
        )
    return np.frombuffer(payload, dtype="<i2").astype(np.float32) / np.float32(32768.0)


def periodic_hann(length: int) -> np.ndarray:
    return np.hanning(length + 1)[:-1].astype(np.float32)


def stft_centered(signal: np.ndarray) -> np.ndarray:
    signal = np.asarray(signal, dtype=np.float32)
    padded = np.pad(signal, (FFT_SIZE // 2, FFT_SIZE // 2))
    window = periodic_hann(FFT_SIZE)
    count = 1 + (padded.size - FFT_SIZE) // HOP_SIZE
    output = np.empty((SPECTRUM_BINS, count), dtype=np.complex64)
    for frame in range(count):
        start = frame * HOP_SIZE
        output[:, frame] = np.fft.rfft(padded[start : start + FFT_SIZE] * window)
    return output


def magnitude_for_accelerator(spectrum: np.ndarray) -> np.ndarray:
    spectrum = np.asarray(spectrum)
    if spectrum.ndim != 2 or spectrum.shape[0] != SPECTRUM_BINS:
        raise FeatureBundleError(
            f"spectrum must have shape ({SPECTRUM_BINS}, frames), got {spectrum.shape}"
        )
    return np.sqrt(np.abs(spectrum[:HARDWARE_BINS])).astype(np.float32)


def pack_magnitude_frames_q12(magnitude: np.ndarray) -> np.ndarray:
    """Pack ``[256, frames]`` magnitudes into contiguous ``[frames, 512]`` bytes."""

    values = np.asarray(magnitude, dtype=np.float64)
    if values.ndim != 2 or values.shape[0] != HARDWARE_BINS:
        raise FeatureBundleError(
            f"magnitude must have shape ({HARDWARE_BINS}, frames), got {values.shape}"
        )
    if not np.all(np.isfinite(values)):
        raise FeatureBundleError("magnitude must contain only finite values")
    if np.any(values < 0.0):
        raise FeatureBundleError("magnitude must be non-negative")
    scaled = np.clip(np.rint(values * MAGNITUDE_Q12_SCALE), 0.0, 32767.0)
    words = np.ascontiguousarray(scaled.T.astype("<i2"))
    return words.view(np.uint8).reshape(values.shape[1], HARDWARE_BINS * 2)


def pack_spectrum_frames_int8(spectrum: np.ndarray) -> np.ndarray:
    """Pack complex bins into frame-major interleaved signed-INT8 DMA packets."""

    values = np.asarray(spectrum)
    if (
        values.ndim != 2
        or values.shape[0] < HARDWARE_BINS
        or not np.iscomplexobj(values)
    ):
        raise FeatureBundleError(
            f"spectrum must have at least {HARDWARE_BINS} complex rows, got {values.shape}"
        )
    hardware = values[:HARDWARE_BINS].T
    output = np.empty((values.shape[1], HARDWARE_BINS * 2), dtype=np.int8)
    for band, (lower, upper) in enumerate(zip(FREQ_CUTOFFS[:-1], FREQ_CUTOFFS[1:])):
        scale = float(SPECTRUM_SCALES[band])
        real = np.asarray(hardware[:, lower:upper].real, dtype=np.float64)
        imag = np.asarray(hardware[:, lower:upper].imag, dtype=np.float64)
        output[:, 2 * lower : 2 * upper : 2] = np.clip(
            np.rint(real / scale), -127, 127
        ).astype(np.int8)
        output[:, 2 * lower + 1 : 2 * upper : 2] = np.clip(
            np.rint(imag / scale), -127, 127
        ).astype(np.int8)
    return output


def build_feature_bundle(input_wav: Path, output_dir: Path) -> dict[str, object]:
    """Compute the exact accelerator frontend on the host and save raw NPY arrays."""

    input_wav = input_wav.resolve()
    output_dir = output_dir.resolve()
    if output_dir.exists() and any(output_dir.iterdir()):
        raise FeatureBundleError(f"output directory is not empty: {output_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)
    started = time.perf_counter()
    samples = read_pcm16(input_wav)
    spectrum = stft_centered(samples)
    magnitude = magnitude_for_accelerator(spectrum)
    magnitude_q12 = pack_magnitude_frames_q12(magnitude)
    spectrum_q = pack_spectrum_frames_int8(spectrum)
    compute_elapsed_s = time.perf_counter() - started

    spectrum_path = output_dir / "spectrum.npy"
    magnitude_path = output_dir / "magnitude.npy"
    magnitude_q12_path = output_dir / "magnitude_q12.npy"
    spectrum_q_path = output_dir / "spectrum_q.npy"
    np.save(spectrum_path, spectrum, allow_pickle=False)
    np.save(magnitude_path, magnitude, allow_pickle=False)
    np.save(magnitude_q12_path, magnitude_q12, allow_pickle=False)
    np.save(spectrum_q_path, spectrum_q, allow_pickle=False)
    metadata = {
        "schema": SCHEMA,
        "source_name": input_wav.name,
        "source_sha256": sha256_file(input_wav),
        "source_samples": int(samples.size),
        "sample_rate": SAMPLE_RATE,
        "fft_size": FFT_SIZE,
        "hop_size": HOP_SIZE,
        "frame_count": int(spectrum.shape[1]),
        "spectrum": {
            "file": spectrum_path.name,
            "dtype": "complex64",
            "shape": list(spectrum.shape),
            "sha256": sha256_file(spectrum_path),
        },
        "magnitude": {
            "file": magnitude_path.name,
            "dtype": "float32",
            "shape": list(magnitude.shape),
            "sha256": sha256_file(magnitude_path),
            "semantics": MAGNITUDE_SEMANTICS,
        },
        "packed_abi": PACKED_ABI,
        "magnitude_q12": {
            "file": magnitude_q12_path.name,
            "dtype": "uint8",
            "shape": list(magnitude_q12.shape),
            "sha256": sha256_file(magnitude_q12_path),
        },
        "spectrum_q": {
            "file": spectrum_q_path.name,
            "dtype": "int8",
            "shape": list(spectrum_q.shape),
            "sha256": sha256_file(spectrum_q_path),
        },
        "host_compute_elapsed_s": float(compute_elapsed_s),
    }
    metadata_path = output_dir / "metadata.json"
    metadata_path.write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return {
        "bundle_dir": str(output_dir),
        "metadata_sha256": sha256_file(metadata_path),
        **metadata,
    }


def _array_from_metadata(
    bundle_dir: Path,
    metadata: dict[str, object],
    name: str,
    expected_dtype: np.dtype,
    expected_rows: int,
) -> np.ndarray:
    record = metadata.get(name)
    if not isinstance(record, dict):
        raise FeatureBundleError(f"missing {name} record")
    path = bundle_dir / str(record.get("file", ""))
    if not path.is_file():
        raise FeatureBundleError(f"missing {name} array: {path}")
    if sha256_file(path) != record.get("sha256"):
        raise FeatureBundleError(f"{name} SHA-256 mismatch")
    values = np.load(path, mmap_mode="r", allow_pickle=False)
    expected_shape = tuple(record.get("shape", ()))
    if values.dtype != expected_dtype or values.shape != expected_shape:
        raise FeatureBundleError(
            f"{name} array metadata mismatch: dtype={values.dtype}, shape={values.shape}"
        )
    if values.ndim != 2 or values.shape[0] != expected_rows:
        raise FeatureBundleError(f"invalid {name} shape: {values.shape}")
    return values


def _packed_array_from_metadata(
    bundle_dir: Path,
    metadata: dict[str, object],
    name: str,
    expected_dtype: np.dtype,
    frame_count: int,
) -> np.ndarray:
    record = metadata.get(name)
    if not isinstance(record, dict):
        raise FeatureBundleError(f"missing {name} record")
    path = bundle_dir / str(record.get("file", ""))
    if not path.is_file():
        raise FeatureBundleError(f"missing {name} array: {path}")
    if sha256_file(path) != record.get("sha256"):
        raise FeatureBundleError(f"{name} SHA-256 mismatch")
    values = np.load(path, mmap_mode="r", allow_pickle=False)
    expected_shape = (frame_count, HARDWARE_BINS * 2)
    if (
        values.dtype != expected_dtype
        or values.shape != tuple(record.get("shape", ()))
        or values.shape != expected_shape
        or not values.flags.c_contiguous
    ):
        raise FeatureBundleError(
            f"invalid {name} DMA layout: dtype={values.dtype}, shape={values.shape}"
        )
    return values


def load_feature_bundle(
    bundle_dir: Path,
    *,
    source_wav: Path | None = None,
    source_samples: int | None = None,
) -> AudioFeatureBundle:
    """Load and fail closed on stale, corrupt, or contract-incompatible features."""

    bundle_dir = bundle_dir.resolve()
    metadata_path = bundle_dir / "metadata.json"
    if not metadata_path.is_file():
        raise FeatureBundleError(f"missing bundle metadata: {metadata_path}")
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    if metadata.get("schema") not in (LEGACY_SCHEMA, SCHEMA):
        raise FeatureBundleError(
            f"bundle schema mismatch: expected {LEGACY_SCHEMA!r} or {SCHEMA!r}, "
            f"got {metadata.get('schema')!r}"
        )
    expected_scalars = {
        "sample_rate": SAMPLE_RATE,
        "fft_size": FFT_SIZE,
        "hop_size": HOP_SIZE,
    }
    for name, expected in expected_scalars.items():
        if metadata.get(name) != expected:
            raise FeatureBundleError(
                f"bundle {name} mismatch: expected {expected!r}, got {metadata.get(name)!r}"
            )
    if source_wav is not None and sha256_file(source_wav) != metadata.get("source_sha256"):
        raise FeatureBundleError("feature bundle does not match --input-wav SHA-256")
    if source_samples is not None and source_samples != metadata.get("source_samples"):
        raise FeatureBundleError("feature bundle sample count does not match input WAV")

    spectrum = _array_from_metadata(
        bundle_dir, metadata, "spectrum", np.dtype(np.complex64), SPECTRUM_BINS
    )
    magnitude = _array_from_metadata(
        bundle_dir, metadata, "magnitude", np.dtype(np.float32), HARDWARE_BINS
    )
    if spectrum.shape[1] != magnitude.shape[1]:
        raise FeatureBundleError("spectrum and magnitude frame counts differ")
    if spectrum.shape[1] != metadata.get("frame_count"):
        raise FeatureBundleError("array frame count does not match metadata")
    if metadata["magnitude"].get("semantics") != MAGNITUDE_SEMANTICS:
        raise FeatureBundleError("magnitude semantics mismatch")
    magnitude_q12 = None
    spectrum_q = None
    if metadata.get("schema") == SCHEMA:
        if metadata.get("packed_abi") != PACKED_ABI:
            raise FeatureBundleError("packed input ABI mismatch")
        frame_count = int(spectrum.shape[1])
        magnitude_q12 = _packed_array_from_metadata(
            bundle_dir, metadata, "magnitude_q12", np.dtype(np.uint8), frame_count
        )
        spectrum_q = _packed_array_from_metadata(
            bundle_dir, metadata, "spectrum_q", np.dtype(np.int8), frame_count
        )
    return AudioFeatureBundle(
        spectrum=spectrum,
        magnitude=magnitude,
        magnitude_q12=magnitude_q12,
        spectrum_q=spectrum_q,
        metadata=metadata,
        metadata_sha256=sha256_file(metadata_path),
    )
