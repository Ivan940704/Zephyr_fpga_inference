#!/usr/bin/env python3
"""Run all fixed PTQ clips on PYNQ and produce resumable quality evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import subprocess
import sys
import time
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

try:
    from .accelerator_bringup import fresh_parameter_epoch_reset
    from .parameter_bram_bringup import load_arm_dsb_sy
except ImportError:
    from accelerator_bringup import fresh_parameter_epoch_reset  # type: ignore
    from parameter_bram_bringup import load_arm_dsb_sy  # type: ignore

from software.evaluation.ptq_audio_metrics import (  # noqa: E402
    discover_triplets,
    evaluate,
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def valid_completed_case(
    output: Path,
    noisy: Path,
    clean: Path,
    feature_dir: Path | None = None,
) -> bool:
    metrics_path = output / "metrics.json"
    enhanced_path = output / "enhanced.wav"
    if not metrics_path.is_file() or not enhanced_path.is_file():
        return False
    metrics = json.loads(metrics_path.read_text(encoding="utf-8"))
    frontend = metrics.get("frontend", {})
    bundle_matches = feature_dir is None or bool(
        (feature_dir / "metadata.json").is_file()
        and frontend.get("placement") == "computer_precomputed"
        and frontend.get("bundle_metadata_sha256")
        == sha256_file(feature_dir / "metadata.json")
    )
    return bool(
        metrics.get("status") == "PASS"
        and metrics.get("input_sha256") == sha256_file(noisy)
        and metrics.get("clean_reference_sha256") == sha256_file(clean)
        and metrics.get("frames", 0) > 0
        and metrics.get("final_hardware_state")
        and bundle_matches
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset-root", type=Path, required=True)
    parser.add_argument(
        "--feature-root",
        type=Path,
        help="host-precomputed STFT/magnitude root containing fileid_NNN bundles",
    )
    parser.add_argument("--parameter-image", type=Path, required=True)
    parser.add_argument("--runtime-parameters", type=Path, required=True)
    parser.add_argument("--parameter-sha256", required=True)
    parser.add_argument("--native-library", type=Path, required=True)
    parser.add_argument("--barrier-library", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument(
        "--runner",
        type=Path,
        default=Path(__file__).with_name("run_accelerator_inference.py"),
    )
    parser.add_argument("--mailbox-io", choices=("scalar", "bulk"), default="bulk")
    parser.add_argument("--layernorm", choices=("numpy", "native"), default="native")
    parser.add_argument("--poll-mode", choices=("sleep", "busy"), default="sleep")
    parser.add_argument("--dense", action="store_true")
    parser.add_argument("--conservative-output-cache", action="store_true")
    parser.add_argument("--diagnostics", action="store_true")
    parser.add_argument(
        "--profile",
        action="store_true",
        help="record host T00-T16 operation buckets for each clip",
    )
    parser.add_argument("--hardware-profile", action="store_true")
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--expected-count", type=int, default=100)
    parser.add_argument("--bootstrap-resamples", type=int, default=10_000)
    args = parser.parse_args()
    if args.expected_count <= 0 or args.bootstrap_resamples <= 0:
        parser.error("counts must be positive")
    required = (
        args.parameter_image,
        args.runtime_parameters,
        args.native_library,
        args.barrier_library,
        args.runner,
    )
    for path in required:
        if not path.is_file():
            parser.error(f"required file does not exist: {path}")
    if args.feature_root is not None and not args.feature_root.is_dir():
        parser.error(f"feature root does not exist: {args.feature_root}")
    if sha256_file(args.parameter_image) != args.parameter_sha256.lower():
        parser.error("parameter image SHA-256 mismatch")
    triplets = discover_triplets(args.dataset_root, args.expected_count)
    if args.output_root.exists() and any(args.output_root.iterdir()) and not args.resume:
        parser.error("output root is non-empty; use --resume or a new directory")
    args.output_root.mkdir(parents=True, exist_ok=True)
    barrier = load_arm_dsb_sy(args.barrier_library)

    started = time.time()
    records = []
    common = [
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
        args.mailbox_io,
        "--layernorm",
        args.layernorm,
        "--poll-mode",
        args.poll_mode,
        "--compact",
        "--progress-every",
        "0",
    ]
    if not args.conservative_output_cache:
        common.append("--optimized-output-cache")
    if not args.diagnostics:
        common.append("--no-diagnostics")
    if args.dense:
        common.append("--dense")
    if args.hardware_profile:
        common.append("--hardware-profile")
    if args.profile:
        common.append("--profile")

    run_manifest_path = args.output_root / "run_manifest.json"
    for index, triplet in enumerate(triplets):
        output = args.output_root / f"fileid_{triplet.file_id:03d}"
        feature_dir = (
            args.feature_root / f"fileid_{triplet.file_id:03d}"
            if args.feature_root is not None
            else None
        )
        if feature_dir is not None and not (feature_dir / "metadata.json").is_file():
            raise RuntimeError(f"missing feature bundle for file ID {triplet.file_id}")
        if args.resume and valid_completed_case(
            output, triplet.noisy, triplet.clean, feature_dir
        ):
            outcome = "RESUMED_EXISTING_PASS"
            reset_evidence = None
        else:
            reset_evidence = fresh_parameter_epoch_reset(barrier=barrier)
            if output.exists() and any(output.iterdir()):
                raise RuntimeError(
                    f"file ID {triplet.file_id} has incomplete/nonmatching output; "
                    "refusing to overwrite it"
                )
            command = common + [
                "--output-dir",
                str(output),
                "--input-wav",
                str(triplet.noisy.resolve()),
                "--clean-reference",
                str(triplet.clean.resolve()),
            ]
            if feature_dir is not None:
                command.extend(("--precomputed-features", str(feature_dir.resolve())))
            subprocess.run(command, check=True)
            if not valid_completed_case(
                output, triplet.noisy, triplet.clean, feature_dir
            ):
                raise RuntimeError(f"file ID {triplet.file_id} failed post-run validation")
            outcome = "EXECUTED_PASS"
        metrics_path = output / "metrics.json"
        record = {
            "file_id": triplet.file_id,
            "outcome": outcome,
            "input_sha256": sha256_file(triplet.noisy),
            "clean_sha256": sha256_file(triplet.clean),
            "metrics_sha256": sha256_file(metrics_path),
            "enhanced_sha256": sha256_file(output / "enhanced.wav"),
            "pre_run_reset": reset_evidence,
            "feature_bundle_metadata_sha256": (
                sha256_file(feature_dir / "metadata.json")
                if feature_dir is not None
                else None
            ),
        }
        records.append(record)
        checkpoint = {
            "schema": "zephyr.board-100-audio-run.v1",
            "status": "RUNNING",
            "completed": len(records),
            "expected": len(triplets),
            "started_unix_s": started,
            "updated_unix_s": time.time(),
            "host": {"platform": platform.platform(), "python": sys.version},
            "configuration": {
                "mailbox_io": args.mailbox_io,
                "layernorm": args.layernorm,
                "poll_mode": args.poll_mode,
                "sparse": not args.dense,
                "conservative_output_cache": args.conservative_output_cache,
                "diagnostics": args.diagnostics,
                "profile": args.profile,
                "hardware_profile": args.hardware_profile,
                "frontend_placement": (
                    "computer_precomputed"
                    if args.feature_root is not None
                    else "pynq_cpu"
                ),
                "host_packet_dma_double_buffered": True,
                "fresh_parameter_epoch_before_each_executed_clip": True,
            },
            "records": records,
        }
        run_manifest_path.write_text(
            json.dumps(checkpoint, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        print(
            f"BOARD_100_AUDIO_PROGRESS completed={index + 1}/{len(triplets)} "
            f"file_id={triplet.file_id} outcome={outcome}",
            flush=True,
        )

    evaluation = evaluate(
        args.dataset_root,
        enhanced_root=args.output_root,
        expected_count=args.expected_count,
        resamples=args.bootstrap_resamples,
    )
    evaluation_path = args.output_root / "evaluation.json"
    evaluation_path.write_text(
        json.dumps(evaluation, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    checkpoint["status"] = "PASS"
    checkpoint["completed_unix_s"] = time.time()
    checkpoint["evaluation_sha256"] = sha256_file(evaluation_path)
    run_manifest_path.write_text(
        json.dumps(checkpoint, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(
        "BOARD_100_AUDIO_RESULT "
        + json.dumps(
            {
                "status": "PASS",
                "clips": len(records),
                "evaluation": str(evaluation_path),
                "manifest": str(run_manifest_path),
            },
            sort_keys=True,
        ),
        flush=True,
    )


if __name__ == "__main__":
    main()
