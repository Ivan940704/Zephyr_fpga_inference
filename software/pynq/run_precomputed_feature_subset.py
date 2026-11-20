#!/usr/bin/env python3
"""Run an exact file-ID subset with selectable frontend placement on PYNQ."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from software.audio_feature_bundle import load_feature_bundle, sha256_file  # noqa: E402

try:
    from .accelerator_bringup import fresh_parameter_epoch_reset
    from .parameter_bram_bringup import load_arm_dsb_sy
except ImportError:
    from accelerator_bringup import fresh_parameter_epoch_reset  # type: ignore
    from parameter_bram_bringup import load_arm_dsb_sy  # type: ignore


def weighted_mean(records: list[dict[str, object]], key: str, weight: str) -> float:
    total_weight = sum(float(record[weight]) for record in records)
    return sum(float(record[key]) * float(record[weight]) for record in records) / total_weight


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-results-root", type=Path, required=True)
    parser.add_argument("--feature-root", type=Path)
    parser.add_argument(
        "--frontend",
        choices=("precomputed", "pynq"),
        default="precomputed",
    )
    parser.add_argument(
        "--layernorm-placement", choices=("pl", "mailbox"), default="pl"
    )
    parser.add_argument("--poll-mode", choices=("sleep", "busy"), default="busy")
    parser.add_argument(
        "--dma-control", choices=("auto", "python", "native"), default="python"
    )
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--parameter-image", type=Path, required=True)
    parser.add_argument("--runtime-parameters", type=Path, required=True)
    parser.add_argument("--parameter-sha256", required=True)
    parser.add_argument("--native-library", type=Path, required=True)
    parser.add_argument("--barrier-library", type=Path, required=True)
    parser.add_argument("--profile", action="store_true")
    parser.add_argument("--hardware-profile", action="store_true")
    parser.add_argument("--hardware-profile-every", type=int, default=1)
    parser.add_argument(
        "--file-ids", type=int, nargs="+", default=(0, 25, 50, 75, 99)
    )
    parser.add_argument(
        "--runner",
        type=Path,
        default=Path(__file__).with_name("run_accelerator_inference.py"),
    )
    args = parser.parse_args()

    if not args.file_ids or len(set(args.file_ids)) != len(args.file_ids):
        parser.error("--file-ids must contain at least one unique file ID")
    if args.hardware_profile_every <= 0:
        parser.error("--hardware-profile-every must be positive")
    if args.frontend == "precomputed" and args.feature_root is None:
        parser.error("--frontend precomputed requires --feature-root")
    required_files = (
        args.parameter_image,
        args.runtime_parameters,
        args.native_library,
        args.barrier_library,
        args.runner,
    )
    for path in required_files:
        if not path.is_file():
            parser.error(f"required file does not exist: {path}")
    if sha256_file(args.parameter_image) != args.parameter_sha256.lower():
        parser.error("parameter image SHA-256 mismatch")
    if args.output_root.exists() and any(args.output_root.iterdir()):
        parser.error("output root must be empty")
    args.output_root.mkdir(parents=True, exist_ok=True)

    cases = []
    for file_id in args.file_ids:
        case_name = f"fileid_{file_id:03d}"
        source_dir = args.source_results_root / case_name
        noisy = source_dir / "noisy.wav"
        clean = source_dir / "clean.wav"
        if not noisy.is_file() or not clean.is_file():
            parser.error(f"missing source WAV pair for {case_name}")
        if args.frontend == "precomputed":
            assert args.feature_root is not None
            feature_dir = args.feature_root / case_name
            bundle = load_feature_bundle(feature_dir, source_wav=noisy)
            metadata_sha256 = bundle.metadata_sha256
        else:
            feature_dir = None
            metadata_sha256 = None
        cases.append((file_id, noisy, clean, feature_dir, metadata_sha256))

    barrier = load_arm_dsb_sy(args.barrier_library)
    records = []
    started = time.time()
    for index, (file_id, noisy, clean, feature_dir, metadata_sha256) in enumerate(cases):
        case_name = f"fileid_{file_id:03d}"
        case_output = args.output_root / case_name
        reset_evidence = fresh_parameter_epoch_reset(barrier=barrier)
        command = [
            sys.executable,
            str(args.runner.resolve()),
            "--parameter-image",
            str(args.parameter_image.resolve()),
            "--runtime-parameters",
            str(args.runtime_parameters.resolve()),
            "--parameter-sha256",
            args.parameter_sha256.lower(),
            "--native-library",
            str(args.native_library.resolve()),
            "--mailbox-io",
            "bulk",
            "--layernorm-placement",
            args.layernorm_placement,
            "--layernorm",
            "native",
            "--poll-mode",
            args.poll_mode,
            "--dma-control",
            args.dma_control,
            "--compact",
            "--progress-every",
            "0",
            "--optimized-output-cache",
            "--no-diagnostics",
            "--input-wav",
            str(noisy.resolve()),
            "--clean-reference",
            str(clean.resolve()),
            "--output-dir",
            str(case_output.resolve()),
        ]
        if feature_dir is not None:
            command.extend(("--precomputed-features", str(feature_dir.resolve())))
        if args.profile:
            command.append("--profile")
        if args.hardware_profile:
            command.append("--hardware-profile")
            command.extend(
                ("--hardware-profile-every", str(args.hardware_profile_every))
            )
        log_path = args.output_root / f"{case_name}.log"
        with log_path.open("w", encoding="utf-8") as log:
            subprocess.run(command, check=True, stdout=log, stderr=subprocess.STDOUT)
        metrics_path = case_output / "metrics.json"
        metrics = json.loads(metrics_path.read_text(encoding="utf-8"))
        if metrics.get("status") != "PASS":
            raise RuntimeError(f"{case_name} did not report PASS")
        frontend = metrics.get("frontend", {})
        expected_placement = (
            "computer_precomputed" if args.frontend == "precomputed" else "pynq_cpu"
        )
        if frontend.get("placement") != expected_placement:
            raise RuntimeError(f"{case_name} did not use the selected frontend")
        if args.frontend == "precomputed" and (
            frontend.get("bundle_metadata_sha256") != metadata_sha256
        ):
            raise RuntimeError(f"{case_name} did not consume the selected host bundle")
        record = {
            "file_id": file_id,
            "frames": metrics["frames"],
            "evaluated_audio_s": metrics["evaluated_audio_s"],
            "mean_frame_ms": metrics["mean_frame_ms"],
            "mean_iteration_ms": metrics.get("mean_iteration_ms"),
            "p99_iteration_ms": metrics.get("p99_iteration_ms"),
            "max_iteration_ms": metrics.get("max_iteration_ms"),
            "dma_control": metrics.get("dma_control"),
            "hardware_profile_samples": metrics.get("hardware_profile_samples"),
            "inference_loop_s": metrics["inference_loop_s"],
            "runtime_setup_s": metrics.get("runtime_setup_s"),
            "frame_loop_s": metrics.get("frame_loop_s"),
            "runtime_close_s": metrics.get("runtime_close_s"),
            "end_to_end_s": metrics["end_to_end_s"],
            "frame_compute_rtf": metrics["frame_compute_rtf"],
            "board_loop_rtf": metrics["board_loop_rtf"],
            "sustained_frame_loop_rtf": metrics.get("sustained_frame_loop_rtf"),
            "end_to_end_rtf": metrics["end_to_end_rtf"],
            "snr_delta_db": metrics.get("snr_delta_db"),
            "input_sha256": metrics["input_sha256"],
            "bundle_metadata_sha256": metadata_sha256,
            "metrics_sha256": sha256_file(metrics_path),
            "enhanced_sha256": sha256_file(case_output / "enhanced.wav"),
            "pre_run_reset": reset_evidence,
            "frontend_placement": expected_placement,
            "board_frontend_load_or_compute_s": frontend["board_frontend_load_or_compute_s"],
        }
        records.append(record)
        print(
            f"FRONTEND_SUBSET_PROGRESS completed={index + 1}/{len(cases)} "
            f"file_id={file_id}",
            flush=True,
        )

    total_audio_s = sum(float(record["evaluated_audio_s"]) for record in records)
    summary = {
        "schema": "zephyr.frontend-subset.v1",
        "status": "PASS",
        "frontend": args.frontend,
        "layernorm_placement": args.layernorm_placement,
        "poll_mode": args.poll_mode,
        "dma_control": args.dma_control,
        "host_packet_dma_double_buffered": True,
        "profile": args.profile,
        "hardware_profile": args.hardware_profile,
        "hardware_profile_every": args.hardware_profile_every,
        "file_ids": args.file_ids,
        "files": len(records),
        "frames": sum(int(record["frames"]) for record in records),
        "evaluated_audio_s": total_audio_s,
        "weighted_mean_frame_ms": weighted_mean(records, "mean_frame_ms", "frames"),
        "weighted_mean_iteration_ms": weighted_mean(
            records, "mean_iteration_ms", "frames"
        ),
        "worst_file_p99_iteration_ms": max(
            float(record["p99_iteration_ms"]) for record in records
        ),
        "aggregate_frame_compute_rtf": sum(
            float(record["mean_frame_ms"]) * int(record["frames"]) / 1000.0
            for record in records
        ) / total_audio_s,
        "aggregate_board_loop_rtf": sum(
            float(record["inference_loop_s"]) for record in records
        ) / total_audio_s,
        "aggregate_sustained_frame_loop_rtf": sum(
            float(record["frame_loop_s"]) for record in records
        ) / total_audio_s,
        "aggregate_end_to_end_rtf": sum(
            float(record["end_to_end_s"]) for record in records
        ) / total_audio_s,
        "elapsed_wall_s": time.time() - started,
        "records": records,
    }
    manifest_path = args.output_root / "run_manifest.json"
    manifest_path.write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print("FRONTEND_SUBSET_RESULT " + json.dumps(summary, sort_keys=True), flush=True)


if __name__ == "__main__":
    main()
