#!/usr/bin/env python3
"""Compare same-input PYNQ and host-precomputed frontend board runs."""

from __future__ import annotations

import argparse
import json
import sys
import wave
from pathlib import Path

import numpy as np


REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from software.audio_feature_bundle import (  # noqa: E402
    load_feature_bundle,
    read_pcm16,
    sha256_file,
    stft_centered,
)
from software.pynq.accelerator_inference import (  # noqa: E402
    NativeLayerNormEngine,
    RuntimeParameters,
    pack_spectrum,
)


SELECTED_FILE_IDS = (0, 25, 50, 75, 99)
METRIC_KEYS = (
    "weighted_mean_frame_ms",
    "aggregate_frame_compute_rtf",
    "aggregate_board_loop_rtf",
    "aggregate_end_to_end_rtf",
)


def load_json(path: Path) -> dict[str, object]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected a JSON object: {path}")
    return value


def record_map(manifest: dict[str, object]) -> dict[int, dict[str, object]]:
    records = manifest.get("records")
    if not isinstance(records, list):
        raise ValueError("manifest records must be a list")
    mapped = {int(record["file_id"]): record for record in records}
    if tuple(mapped) != SELECTED_FILE_IDS:
        raise ValueError(f"unexpected file IDs: {tuple(mapped)}")
    return mapped


def read_pcm16_raw(path: Path) -> np.ndarray:
    with wave.open(str(path), "rb") as handle:
        if handle.getnchannels() != 1 or handle.getsampwidth() != 2:
            raise ValueError(f"expected mono PCM16 WAV: {path}")
        payload = handle.readframes(handle.getnframes())
    return np.frombuffer(payload, dtype="<i2").copy()


def percent_delta(candidate: float, reference: float) -> float:
    return 100.0 * (candidate / reference - 1.0)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--precomputed-root", type=Path, required=True)
    parser.add_argument("--control-root", type=Path, required=True)
    parser.add_argument("--source-results-root", type=Path, required=True)
    parser.add_argument("--feature-root", type=Path, required=True)
    parser.add_argument("--runtime-parameters", type=Path, required=True)
    parser.add_argument("--native-library", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    precomputed_manifest_path = args.precomputed_root / "run_manifest.json"
    control_manifest_path = args.control_root / "run_manifest.json"
    precomputed = load_json(precomputed_manifest_path)
    control = load_json(control_manifest_path)
    for name, manifest in (("precomputed", precomputed), ("control", control)):
        if manifest.get("status") != "PASS":
            raise ValueError(f"{name} run is not PASS")
        if list(manifest.get("file_ids", [])) != list(SELECTED_FILE_IDS):
            raise ValueError(f"{name} run used the wrong file IDs")
        if int(manifest.get("files", 0)) != len(SELECTED_FILE_IDS):
            raise ValueError(f"{name} run did not contain five files")

    precomputed_records = record_map(precomputed)
    control_records = record_map(control)
    runtime_parameters = RuntimeParameters.load(args.runtime_parameters)
    native_layernorm = NativeLayerNormEngine(
        args.native_library, runtime_parameters
    )
    comparisons = []
    for file_id in SELECTED_FILE_IDS:
        case_name = f"fileid_{file_id:03d}"
        noisy = args.source_results_root / case_name / "noisy.wav"
        bundle = load_feature_bundle(args.feature_root / case_name, source_wav=noisy)
        board_spectrum = stft_centered(read_pcm16(noisy))
        board_magnitude = np.sqrt(np.abs(board_spectrum[:256])).astype(np.float32)
        spectrum_exact = bool(np.array_equal(bundle.spectrum, board_spectrum))
        magnitude_exact = bool(np.array_equal(bundle.magnitude, board_magnitude))
        spectrum_delta = bundle.spectrum - board_spectrum
        magnitude_delta = bundle.magnitude - board_magnitude
        spectrum_q_different = 0
        spectrum_q_max_abs_lsb = 0
        fullband_q_different = 0
        fullband_q_max_abs_lsb = 0
        for frame in range(board_spectrum.shape[1]):
            pre_spectrum_q = pack_spectrum(bundle.spectrum[:256, frame])
            control_spectrum_q = pack_spectrum(board_spectrum[:256, frame])
            spectrum_q_delta = (
                pre_spectrum_q.astype(np.int16) - control_spectrum_q.astype(np.int16)
            )
            spectrum_q_different += int(np.count_nonzero(spectrum_q_delta))
            spectrum_q_max_abs_lsb = max(
                spectrum_q_max_abs_lsb, int(np.max(np.abs(spectrum_q_delta)))
            )
            pre_fullband_q = native_layernorm.prepare_fullband_input(
                bundle.magnitude[:, frame]
            )
            control_fullband_q = native_layernorm.prepare_fullband_input(
                board_magnitude[:, frame]
            )
            fullband_q_delta = (
                pre_fullband_q.astype(np.int16) - control_fullband_q.astype(np.int16)
            )
            fullband_q_different += int(np.count_nonzero(fullband_q_delta))
            fullband_q_max_abs_lsb = max(
                fullband_q_max_abs_lsb, int(np.max(np.abs(fullband_q_delta)))
            )

        pre_record = precomputed_records[file_id]
        control_record = control_records[file_id]
        source_sha = sha256_file(noisy)
        input_sha_match = (
            pre_record.get("input_sha256")
            == control_record.get("input_sha256")
            == source_sha
        )
        pre_metrics = load_json(args.precomputed_root / case_name / "metrics.json")
        control_metrics = load_json(args.control_root / case_name / "metrics.json")
        pre_frontend = float(
            pre_metrics["frontend"]["board_frontend_load_or_compute_s"]
        )
        control_frontend = float(
            control_metrics["frontend"]["board_frontend_load_or_compute_s"]
        )

        pre_pcm = read_pcm16_raw(args.precomputed_root / case_name / "enhanced.wav")
        control_pcm = read_pcm16_raw(args.control_root / case_name / "enhanced.wav")
        if pre_pcm.shape != control_pcm.shape:
            raise ValueError(f"enhanced WAV shape mismatch for {case_name}")
        pcm_delta = pre_pcm.astype(np.int32) - control_pcm.astype(np.int32)
        different_samples = int(np.count_nonzero(pcm_delta))
        comparisons.append(
            {
                "file_id": file_id,
                "frames": int(pre_record["frames"]),
                "input_sha256": source_sha,
                "input_sha256_match": input_sha_match,
                "spectrum_exact_on_pynq_numpy": spectrum_exact,
                "magnitude_exact_on_pynq_numpy": magnitude_exact,
                "spectrum_max_abs_float_delta": float(
                    np.max(np.abs(spectrum_delta))
                ),
                "magnitude_max_abs_float_delta": float(
                    np.max(np.abs(magnitude_delta))
                ),
                "spectrum_q_different_elements": spectrum_q_different,
                "spectrum_q_max_abs_lsb": spectrum_q_max_abs_lsb,
                "fullband_q_different_elements": fullband_q_different,
                "fullband_q_max_abs_lsb": fullband_q_max_abs_lsb,
                "precomputed_frontend_s": pre_frontend,
                "control_frontend_s": control_frontend,
                "frontend_delta_s": pre_frontend - control_frontend,
                "mean_frame_ms_precomputed": float(pre_record["mean_frame_ms"]),
                "mean_frame_ms_control": float(control_record["mean_frame_ms"]),
                "mean_frame_delta_percent": percent_delta(
                    float(pre_record["mean_frame_ms"]),
                    float(control_record["mean_frame_ms"]),
                ),
                "enhanced_sha256_precomputed": pre_record["enhanced_sha256"],
                "enhanced_sha256_control": control_record["enhanced_sha256"],
                "enhanced_sha256_match": (
                    pre_record["enhanced_sha256"] == control_record["enhanced_sha256"]
                ),
                "enhanced_pcm_different_samples": different_samples,
                "enhanced_pcm_max_abs_lsb": int(np.max(np.abs(pcm_delta))),
                "enhanced_pcm_mean_abs_lsb": float(np.mean(np.abs(pcm_delta))),
                "snr_delta_db_precomputed": float(pre_record["snr_delta_db"]),
                "snr_delta_db_control": float(control_record["snr_delta_db"]),
            }
        )

    aggregate_delta = {}
    for key in METRIC_KEYS:
        candidate = float(precomputed[key])
        reference = float(control[key])
        aggregate_delta[key] = {
            "precomputed": candidate,
            "control": reference,
            "absolute": candidate - reference,
            "percent": percent_delta(candidate, reference),
        }
    total_pre_frontend = sum(float(row["precomputed_frontend_s"]) for row in comparisons)
    total_control_frontend = sum(float(row["control_frontend_s"]) for row in comparisons)
    output = {
        "schema": "zephyr.frontend-ab-comparison.v1",
        "status": "PASS",
        "evidence": "measured_PYNQ_Z1_ec457b1_same_input_five_file_ab",
        "file_ids": list(SELECTED_FILE_IDS),
        "files": len(comparisons),
        "frames": int(precomputed["frames"]),
        "evaluated_audio_s": float(precomputed["evaluated_audio_s"]),
        "precomputed_manifest_sha256": sha256_file(precomputed_manifest_path),
        "control_manifest_sha256": sha256_file(control_manifest_path),
        "aggregate_delta_precomputed_minus_control": aggregate_delta,
        "frontend_total_s": {
            "precomputed_bundle_load": total_pre_frontend,
            "pynq_stft_compute": total_control_frontend,
            "absolute": total_pre_frontend - total_control_frontend,
            "percent": percent_delta(total_pre_frontend, total_control_frontend),
        },
        "feature_arrays_exact_for_all_files": all(
            row["spectrum_exact_on_pynq_numpy"]
            and row["magnitude_exact_on_pynq_numpy"]
            for row in comparisons
        ),
        "input_sha256_match_for_all_files": all(
            row["input_sha256_match"] for row in comparisons
        ),
        "quantized_spectrum_exact_for_all_files": all(
            row["spectrum_q_different_elements"] == 0 for row in comparisons
        ),
        "quantized_fullband_input_exact_for_all_files": all(
            row["fullband_q_different_elements"] == 0 for row in comparisons
        ),
        "enhanced_sha256_match_files": sum(
            bool(row["enhanced_sha256_match"]) for row in comparisons
        ),
        "conclusion": "NO_LATENCY_IMPROVEMENT_OBSERVED",
        "records": comparisons,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(output, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print("FRONTEND_AB_RESULT " + json.dumps(output, sort_keys=True))


if __name__ == "__main__":
    main()
