#!/usr/bin/env python3
"""Fail-closed correctness, profiling, and performance matrix on PYNQ-Z1."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import platform
import random
import statistics
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

import numpy as np

try:
    from .accelerator_bringup import fresh_parameter_epoch_reset
    from .parameter_bram_bringup import load_arm_dsb_sy
except ImportError:
    from accelerator_bringup import fresh_parameter_epoch_reset  # type: ignore
    from parameter_bram_bringup import load_arm_dsb_sy  # type: ignore


@dataclass(frozen=True)
class Case:
    name: str
    arguments: tuple[str, ...]


CASES = (
    Case("c0_scalar_numpy", ()),
    Case("c1_bulk_numpy", ("--mailbox-io", "bulk")),
    Case("c2_scalar_native", ("--layernorm", "native")),
    Case(
        "c3_bulk_native",
        ("--mailbox-io", "bulk", "--layernorm", "native"),
    ),
    Case(
        "c4_bulk_native_cache",
        (
            "--mailbox-io",
            "bulk",
            "--layernorm",
            "native",
            "--optimized-output-cache",
        ),
    ),
    Case(
        "c5_bulk_native_cache_nodiag",
        (
            "--mailbox-io",
            "bulk",
            "--layernorm",
            "native",
            "--optimized-output-cache",
            "--no-diagnostics",
        ),
    ),
    Case(
        "c6_bulk_native_cache_nodiag_busy",
        (
            "--mailbox-io",
            "bulk",
            "--layernorm",
            "native",
            "--optimized-output-cache",
            "--no-diagnostics",
            "--poll-mode",
            "busy",
        ),
    ),
    Case(
        "c7_bulk_native_cache_nodiag_dense",
        (
            "--mailbox-io",
            "bulk",
            "--layernorm",
            "native",
            "--optimized-output-cache",
            "--no-diagnostics",
            "--dense",
        ),
    ),
)

CORRECTNESS_ARRAYS = (
    "accumulators",
    "fb_projections",
    "sb_payloads",
    "spectra_q",
    "hardware_bins",
)
PERFORMANCE_FIELDS = (
    "mean_frame_ms",
    "p50_frame_ms",
    "p95_frame_ms",
    "p99_frame_ms",
    "max_frame_ms",
    "mean_mailbox_ms",
    "p99_mailbox_ms",
    "frame_compute_rtf",
    "board_loop_rtf",
    "end_to_end_rtf",
    "throughput_frames_per_s",
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def new_directory(path: Path) -> None:
    if path.exists() and any(path.iterdir()):
        raise SystemExit(f"refusing to overwrite non-empty output directory: {path}")
    path.mkdir(parents=True, exist_ok=True)


def frame_ids_are_contiguous(values: list[int]) -> bool:
    return all(
        int(values[index]) == ((int(values[index - 1]) + 1) & 0xFFFF)
        for index in range(1, len(values))
    )


def student_t_975(degrees_of_freedom: int) -> float:
    table = {
        1: 12.706,
        2: 4.303,
        3: 3.182,
        4: 2.776,
        5: 2.571,
        6: 2.447,
        7: 2.365,
        8: 2.306,
        9: 2.262,
        10: 2.228,
        11: 2.201,
        12: 2.179,
        13: 2.160,
        14: 2.145,
        15: 2.131,
        16: 2.120,
        17: 2.110,
        18: 2.101,
        19: 2.093,
        20: 2.086,
        25: 2.060,
        30: 2.042,
    }
    if degrees_of_freedom in table:
        return table[degrees_of_freedom]
    if degrees_of_freedom < 25:
        return table[20]
    if degrees_of_freedom < 30:
        return table[25]
    return 1.96


def repeated_statistics(values: list[float]) -> dict[str, object]:
    mean = statistics.fmean(values)
    deviation = statistics.stdev(values) if len(values) > 1 else 0.0
    half_width = (
        student_t_975(len(values) - 1) * deviation / math.sqrt(len(values))
        if len(values) > 1
        else 0.0
    )
    return {
        "count": len(values),
        "mean": mean,
        "standard_deviation": deviation,
        "student_t_mean_95ci": [mean - half_width, mean + half_width],
        "minimum": min(values),
        "maximum": max(values),
    }


def compare_correctness(reference: Path, candidate: Path) -> dict[str, object]:
    result: dict[str, object] = {}
    with np.load(reference, allow_pickle=False) as baseline, np.load(
        candidate, allow_pickle=False
    ) as tested:
        for name in CORRECTNESS_ARRAYS:
            if name not in baseline or name not in tested:
                raise RuntimeError(f"correctness array {name} is missing")
            equal = np.array_equal(baseline[name], tested[name])
            result[name] = {
                "equal": bool(equal),
                "shape": list(baseline[name].shape),
            }
            if not equal:
                raise RuntimeError(f"correctness mismatch in {name}")
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
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
    parser.add_argument(
        "--oracle-npz",
        type=Path,
        default=(
            Path(__file__).resolve().parents[2]
            / "rtl/reports/accelerator_full_board/inference_result.npz"
        ),
        help="frozen deterministic 33-frame NumPy-validated result",
    )
    parser.add_argument("--correctness-samples", type=int, default=4096)
    parser.add_argument("--benchmark-samples", type=int, default=480_000)
    parser.add_argument("--repeats", type=int, default=5)
    parser.add_argument("--order-seed", type=int, default=0x5EED)
    args = parser.parse_args()
    if args.correctness_samples < 512 or args.benchmark_samples < 512:
        parser.error("sample counts must be at least 512")
    if args.repeats < 2:
        parser.error("--repeats must be at least 2 for a confidence interval")
    for path in (
        args.parameter_image,
        args.runtime_parameters,
        args.native_library,
        args.barrier_library,
        args.runner,
        args.oracle_npz,
    ):
        if not path.is_file():
            parser.error(f"required file does not exist: {path}")
    if sha256_file(args.parameter_image) != args.parameter_sha256.lower():
        parser.error("parameter image SHA-256 mismatch before experiment")
    new_directory(args.output_root)
    barrier = load_arm_dsb_sy(args.barrier_library)

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
        "--progress-every",
        "0",
    ]
    manifest: dict[str, object] = {
        "schema": "zephyr.board-experiment-matrix.v1",
        "status": "RUNNING",
        "started_unix_s": time.time(),
        "host": {
            "platform": platform.platform(),
            "python": sys.version,
            "numpy": np.__version__,
        },
        "artifacts": {
            "parameter_image": {
                "path": str(args.parameter_image.resolve()),
                "sha256": sha256_file(args.parameter_image),
            },
            "runtime_parameters": {
                "path": str(args.runtime_parameters.resolve()),
                "sha256": sha256_file(args.runtime_parameters),
            },
            "native_library": {
                "path": str(args.native_library.resolve()),
                "sha256": sha256_file(args.native_library),
            },
            "barrier_library": {
                "path": str(args.barrier_library.resolve()),
                "sha256": sha256_file(args.barrier_library),
            },
            "runner": {
                "path": str(args.runner.resolve()),
                "sha256": sha256_file(args.runner),
            },
            "oracle_npz": {
                "path": str(args.oracle_npz.resolve()),
                "sha256": sha256_file(args.oracle_npz),
            },
        },
        "correctness": {},
        "benchmark_order": [],
        "benchmark_runs": [],
    }

    def execute(case: Case, output: Path, samples: int, *, compact: bool) -> dict:
        reset_evidence = fresh_parameter_epoch_reset(barrier=barrier)
        if output.exists():
            raise RuntimeError(f"refusing to reuse case output: {output}")
        command = common + [
            "--output-dir",
            str(output),
            "--samples",
            str(samples),
        ]
        if compact:
            command.append("--compact")
        command.extend(case.arguments)
        started = time.monotonic()
        subprocess.run(command, check=True)
        wall_s = time.monotonic() - started
        metrics_path = output / "metrics.json"
        metrics = json.loads(metrics_path.read_text(encoding="utf-8"))
        if metrics.get("status") != "PASS":
            raise RuntimeError(f"case {case.name} did not report PASS")
        if not frame_ids_are_contiguous(metrics["frame_ids"]):
            raise RuntimeError(f"case {case.name} frame IDs are not contiguous")
        return {
            "case": case.name,
            "command": command,
            "wall_s": wall_s,
            "metrics_path": str(metrics_path),
            "metrics_sha256": sha256_file(metrics_path),
            "result_sha256": sha256_file(output / "result.npz"),
            "metrics": metrics,
            "pre_run_reset": reset_evidence,
        }

    correctness_root = args.output_root / "correctness_33_frame"
    correctness_root.mkdir()
    sparse_cases = CASES
    baseline_result = None
    for case in sparse_cases:
        run = execute(
            case,
            correctness_root / case.name,
            args.correctness_samples,
            compact=False,
        )
        result_path = correctness_root / case.name / "result.npz"
        if baseline_result is None:
            baseline_result = result_path
            comparison = {
                "baseline": True,
                "frozen_oracle": compare_correctness(
                    args.oracle_npz.resolve(), result_path
                ),
            }
        else:
            comparison = compare_correctness(baseline_result, result_path)
        manifest["correctness"][case.name] = {
            "comparison": comparison,
            "metrics_sha256": run["metrics_sha256"],
            "result_sha256": run["result_sha256"],
            "pre_run_reset": run["pre_run_reset"],
        }

    profile_case = Case(
        "p0_final_ps_pl_profile",
        CASES[5].arguments + ("--profile", "--hardware-profile"),
    )
    profile_run = execute(
        profile_case,
        correctness_root / profile_case.name,
        args.correctness_samples,
        compact=False,
    )
    manifest["correctness"][profile_case.name] = {
        "comparison": compare_correctness(
            baseline_result, correctness_root / profile_case.name / "result.npz"
        ),
        "metrics_sha256": profile_run["metrics_sha256"],
        "hardware_profile_sha256": sha256_file(
            correctness_root / profile_case.name / "hardware_profile.jsonl"
        ),
        "pre_run_reset": profile_run["pre_run_reset"],
    }

    benchmark_root = args.output_root / "benchmark_30_second"
    benchmark_root.mkdir()
    randomizer = random.Random(args.order_seed)
    for repeat in range(args.repeats):
        order = list(CASES)
        randomizer.shuffle(order)
        manifest["benchmark_order"].append([case.name for case in order])
        for case in order:
            run = execute(
                case,
                benchmark_root / f"repeat_{repeat + 1:02d}" / case.name,
                args.benchmark_samples,
                compact=True,
            )
            manifest["benchmark_runs"].append(run)

    summary: dict[str, object] = {}
    for case in CASES:
        runs = [
            run for run in manifest["benchmark_runs"] if run["case"] == case.name
        ]
        summary[case.name] = {
            name: repeated_statistics(
                [float(run["metrics"][name]) for run in runs]
            )
            for name in PERFORMANCE_FIELDS
        }
    manifest["summary"] = summary
    manifest["status"] = "PASS"
    manifest["completed_unix_s"] = time.time()
    output = args.output_root / "experiment_matrix.json"
    output.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(
        "BOARD_EXPERIMENT_MATRIX "
        + json.dumps(
            {
                "status": "PASS",
                "correctness_cases": len(manifest["correctness"]),
                "benchmark_runs": len(manifest["benchmark_runs"]),
                "output": str(output),
            },
            sort_keys=True,
        ),
        flush=True,
    )


if __name__ == "__main__":
    main()
