#!/usr/bin/env python3
"""Inventory and summarize the fixed 100-triplet PTQ audio experiment.

The tool intentionally keeps optional perceptual metrics fail-closed: missing
PESQ/STOI packages are reported as BLOCKED instead of silently substituting a
different score.  Confidence intervals resample complete clips because frames
within an audio clip are not independent observations.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import wave
from dataclasses import dataclass
from importlib.metadata import PackageNotFoundError, version
from pathlib import Path
from typing import Iterable, Optional

import numpy as np


SAMPLE_RATE = 16_000
FILE_ID_RE = re.compile(r"fileid_(\d+)\.wav$", re.IGNORECASE)
SCHEMA = "zephyr.ptq-audio-evaluation.v1"


def package_version(name: str) -> str:
    try:
        return version(name)
    except PackageNotFoundError:
        return "UNKNOWN"


@dataclass(frozen=True)
class Triplet:
    file_id: int
    clean: Path
    noise: Path
    noisy: Path


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_pcm16(path: Path) -> np.ndarray:
    with wave.open(str(path), "rb") as handle:
        contract = (
            handle.getnchannels(),
            handle.getsampwidth(),
            handle.getframerate(),
            handle.getcomptype(),
        )
        frames = handle.getnframes()
        payload = handle.readframes(frames)
    if contract != (1, 2, SAMPLE_RATE, "NONE"):
        raise ValueError(
            f"{path}: expected mono 16-bit PCM at {SAMPLE_RATE} Hz, got {contract}"
        )
    return np.frombuffer(payload, dtype="<i2").astype(np.float64) / 32768.0


def _id_map(paths: Iterable[Path], label: str) -> dict[int, Path]:
    result: dict[int, Path] = {}
    for path in paths:
        match = FILE_ID_RE.search(path.name)
        if match is None:
            raise ValueError(f"{label}: cannot parse file ID from {path.name}")
        file_id = int(match.group(1))
        if file_id in result:
            raise ValueError(f"{label}: duplicate file ID {file_id}")
        result[file_id] = path
    return result


def discover_triplets(root: Path, expected_count: int = 100) -> list[Triplet]:
    root = root.resolve()
    clean = _id_map(sorted((root / "clean").glob("*.wav")), "clean")
    noise = _id_map(sorted((root / "noise").glob("*.wav")), "noise")
    noisy = _id_map(sorted((root / "noisy").glob("*.wav")), "noisy")
    clean_ids = set(clean)
    if clean_ids != set(noise) or clean_ids != set(noisy):
        raise ValueError(
            "clean/noise/noisy IDs differ: "
            f"clean={sorted(clean)} noise={sorted(noise)} noisy={sorted(noisy)}"
        )
    ids = sorted(clean_ids)
    if len(ids) != expected_count:
        raise ValueError(f"expected {expected_count} triplets, found {len(ids)}")
    if ids != list(range(expected_count)):
        raise ValueError(f"expected contiguous IDs 0..{expected_count - 1}, got {ids}")
    return [Triplet(file_id, clean[file_id], noise[file_id], noisy[file_id]) for file_id in ids]


def snr_db(reference: np.ndarray, estimate: np.ndarray) -> float:
    reference = np.asarray(reference, dtype=np.float64)
    estimate = np.asarray(estimate, dtype=np.float64)
    error = reference - estimate
    return float(
        10.0
        * np.log10(
            max(float(np.dot(reference, reference)), 1e-30)
            / max(float(np.dot(error, error)), 1e-30)
        )
    )


def si_sdr_db(reference: np.ndarray, estimate: np.ndarray) -> float:
    reference = np.asarray(reference, dtype=np.float64)
    estimate = np.asarray(estimate, dtype=np.float64)
    reference = reference - np.mean(reference)
    estimate = estimate - np.mean(estimate)
    reference_energy = max(float(np.dot(reference, reference)), 1e-30)
    target = reference * (float(np.dot(estimate, reference)) / reference_energy)
    residual = estimate - target
    return float(
        10.0
        * np.log10(
            max(float(np.dot(target, target)), 1e-30)
            / max(float(np.dot(residual, residual)), 1e-30)
        )
    )


def signal_statistics(values: np.ndarray) -> dict[str, float | int]:
    values = np.asarray(values, dtype=np.float64)
    abs_values = np.abs(values)
    saturation = int(np.count_nonzero(abs_values >= (32767.0 / 32768.0)))
    return {
        "samples": int(values.size),
        "rms": float(np.sqrt(np.mean(values * values))),
        "dc_mean": float(np.mean(values)),
        "peak_absolute": float(np.max(abs_values)),
        "saturation_samples": saturation,
        "clipping_fraction": float(saturation / values.size),
    }


def optional_metric_availability() -> dict[str, dict[str, object]]:
    availability: dict[str, dict[str, object]] = {}
    try:
        import pystoi  # type: ignore

        availability["stoi"] = {
            "status": "AVAILABLE",
            "package": "pystoi",
            "version": package_version("pystoi"),
            "sample_rate_hz": SAMPLE_RATE,
        }
    except ImportError:
        availability["stoi"] = {
            "status": "BLOCKED",
            "requirement": "pystoi",
            "reason": "Python package is not installed",
        }
    try:
        import pesq as pesq_package  # type: ignore

        availability["pesq"] = {
            "status": "AVAILABLE",
            "package": "pesq",
            "version": package_version("pesq"),
            "sample_rate_hz": SAMPLE_RATE,
            "mode": "wb",
        }
    except ImportError:
        availability["pesq"] = {
            "status": "BLOCKED",
            "requirement": "pesq",
            "reason": "Python package is not installed",
        }
    return availability


def _optional_scores(
    reference: np.ndarray,
    estimate: np.ndarray,
    availability: dict[str, dict[str, object]],
) -> dict[str, object]:
    scores: dict[str, object] = {"stoi": None, "pesq": None, "errors": {}}
    if availability["stoi"]["status"] == "AVAILABLE":
        try:
            from pystoi import stoi  # type: ignore

            scores["stoi"] = float(
                stoi(reference, estimate, SAMPLE_RATE, extended=False)
            )
        except Exception as exc:  # optional package exposes several exception types
            scores["errors"]["stoi"] = f"{type(exc).__name__}: {exc}"
    if availability["pesq"]["status"] == "AVAILABLE":
        try:
            from pesq import pesq  # type: ignore

            scores["pesq"] = float(pesq(SAMPLE_RATE, reference, estimate, "wb"))
        except Exception as exc:  # PESQ rejects silent/short/invalid clips
            scores["errors"]["pesq"] = f"{type(exc).__name__}: {exc}"
    return scores


def bootstrap_mean_ci(
    values: Iterable[float], *, resamples: int = 10_000, seed: int = 0x5EED
) -> list[float]:
    data = np.asarray(list(values), dtype=np.float64)
    if data.size == 0:
        return [math.nan, math.nan]
    rng = np.random.default_rng(seed)
    indices = rng.integers(0, data.size, size=(resamples, data.size))
    means = np.mean(data[indices], axis=1)
    return [float(np.percentile(means, 2.5)), float(np.percentile(means, 97.5))]


def aggregate(values: Iterable[float], *, resamples: int) -> dict[str, object]:
    data = np.asarray(list(values), dtype=np.float64)
    return {
        "count": int(data.size),
        "mean": float(np.mean(data)),
        "median": float(np.median(data)),
        "standard_deviation": float(np.std(data)),
        "minimum": float(np.min(data)),
        "maximum": float(np.max(data)),
        "clip_bootstrap_mean_95ci": bootstrap_mean_ci(data, resamples=resamples),
    }


def _enhanced_paths(root: Path, file_id: int) -> tuple[Path, Optional[Path]]:
    candidates = [
        root / f"fileid_{file_id:03d}" / "enhanced.wav",
        root / f"fileid_{file_id}" / "enhanced.wav",
    ]
    matches = [path for path in candidates if path.is_file()]
    if len(matches) != 1:
        raise ValueError(
            f"file ID {file_id}: expected one enhanced WAV in canonical directory, "
            f"found {matches}"
        )
    metrics = matches[0].with_name("metrics.json")
    return matches[0], metrics if metrics.is_file() else None


def evaluate(
    dataset_root: Path,
    *,
    enhanced_root: Optional[Path],
    expected_count: int,
    resamples: int,
) -> dict[str, object]:
    triplets = discover_triplets(dataset_root, expected_count)
    availability = optional_metric_availability()
    records: list[dict[str, object]] = []
    for triplet in triplets:
        clean = read_pcm16(triplet.clean)
        noise = read_pcm16(triplet.noise)
        noisy = read_pcm16(triplet.noisy)
        if clean.shape != noise.shape or clean.shape != noisy.shape:
            raise ValueError(f"file ID {triplet.file_id}: triplet sample counts differ")
        record: dict[str, object] = {
            "file_id": triplet.file_id,
            "files": {
                "clean": {"name": triplet.clean.name, "sha256": sha256_file(triplet.clean)},
                "noise": {"name": triplet.noise.name, "sha256": sha256_file(triplet.noise)},
                "noisy": {"name": triplet.noisy.name, "sha256": sha256_file(triplet.noisy)},
            },
            "sample_rate_hz": SAMPLE_RATE,
            "samples": int(clean.size),
            "duration_s": float(clean.size / SAMPLE_RATE),
            "input_snr_db": snr_db(clean, noisy),
            "input_si_sdr_db": si_sdr_db(clean, noisy),
            "input_statistics": signal_statistics(noisy),
        }
        if enhanced_root is not None:
            enhanced_path, metrics_path = _enhanced_paths(enhanced_root, triplet.file_id)
            enhanced = read_pcm16(enhanced_path)
            evaluated = min(clean.size, noisy.size, enhanced.size)
            if evaluated <= 0:
                raise ValueError(f"file ID {triplet.file_id}: no aligned samples")
            clean_eval = clean[:evaluated]
            noisy_eval = noisy[:evaluated]
            enhanced_eval = enhanced[:evaluated]
            input_optional = _optional_scores(clean_eval, noisy_eval, availability)
            enhanced_optional = _optional_scores(clean_eval, enhanced_eval, availability)
            enhanced_snr = snr_db(clean_eval, enhanced_eval)
            enhanced_si_sdr = si_sdr_db(clean_eval, enhanced_eval)
            record.update(
                {
                    "evaluated_samples": int(evaluated),
                    "enhanced_sha256": sha256_file(enhanced_path),
                    "enhanced_snr_db": enhanced_snr,
                    "snr_delta_db": enhanced_snr - snr_db(clean_eval, noisy_eval),
                    "enhanced_si_sdr_db": enhanced_si_sdr,
                    "si_sdr_delta_db": enhanced_si_sdr - si_sdr_db(clean_eval, noisy_eval),
                    "input_stoi": input_optional["stoi"],
                    "enhanced_stoi": enhanced_optional["stoi"],
                    "input_pesq": input_optional["pesq"],
                    "enhanced_pesq": enhanced_optional["pesq"],
                    "enhanced_statistics": signal_statistics(enhanced_eval),
                }
            )
            optional_errors = {}
            for metric in ("stoi", "pesq"):
                if metric in input_optional["errors"]:
                    optional_errors[f"input_{metric}"] = input_optional["errors"][metric]
                if metric in enhanced_optional["errors"]:
                    optional_errors[f"enhanced_{metric}"] = enhanced_optional["errors"][metric]
            if optional_errors:
                record["optional_metric_errors"] = optional_errors
            if (
                input_optional["stoi"] is not None
                and enhanced_optional["stoi"] is not None
            ):
                record["stoi_delta"] = enhanced_optional["stoi"] - input_optional["stoi"]
            if (
                input_optional["pesq"] is not None
                and enhanced_optional["pesq"] is not None
            ):
                record["pesq_delta"] = enhanced_optional["pesq"] - input_optional["pesq"]
            if metrics_path is not None:
                board_metrics = json.loads(metrics_path.read_text(encoding="utf-8"))
                record["board_metrics"] = {
                    name: board_metrics.get(name)
                    for name in (
                        "status",
                        "frames",
                        "mean_frame_ms",
                        "p95_frame_ms",
                        "p99_frame_ms",
                        "max_frame_ms",
                        "mean_mailbox_ms",
                        "p99_mailbox_ms",
                        "board_loop_rtf",
                        "end_to_end_rtf",
                        "throughput_frames_per_s",
                    )
                }
        records.append(record)

    result: dict[str, object] = {
        "schema": SCHEMA,
        "status": "READY" if enhanced_root is None else "PASS",
        "expected_triplets": expected_count,
        "triplets": len(records),
        "sample_rate_hz": SAMPLE_RATE,
        "optional_metrics": availability,
        "records": records,
    }
    if enhanced_root is not None:
        summary: dict[str, object] = {}
        for name in (
            "input_snr_db",
            "enhanced_snr_db",
            "snr_delta_db",
            "input_si_sdr_db",
            "enhanced_si_sdr_db",
            "si_sdr_delta_db",
            "input_stoi",
            "enhanced_stoi",
            "stoi_delta",
            "input_pesq",
            "enhanced_pesq",
            "pesq_delta",
        ):
            values = [float(record[name]) for record in records if record.get(name) is not None]
            if values:
                summary[name] = aggregate(values, resamples=resamples)
        summary["snr_regression_ratio"] = float(
            sum(float(record["snr_delta_db"]) < 0.0 for record in records) / len(records)
        )
        result["summary"] = summary
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset-root", type=Path, required=True)
    parser.add_argument("--enhanced-root", type=Path)
    parser.add_argument("--expected-count", type=int, default=100)
    parser.add_argument("--bootstrap-resamples", type=int, default=10_000)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.expected_count <= 0 or args.bootstrap_resamples <= 0:
        parser.error("counts and bootstrap resamples must be positive")
    result = evaluate(
        args.dataset_root,
        enhanced_root=args.enhanced_root,
        expected_count=args.expected_count,
        resamples=args.bootstrap_resamples,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "PTQ_AUDIO_EVALUATION "
        + json.dumps(
            {
                "status": result["status"],
                "triplets": result["triplets"],
                "output": str(args.output),
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
