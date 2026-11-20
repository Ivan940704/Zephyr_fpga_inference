#!/usr/bin/env python3
"""Create a hash-pinned manifest for the complete accelerator artifacts."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess


ARTIFACT_BASENAME = "zephyr_full"
HARDWARE_PREFIXES = (
    "rtl/axi",
    "rtl/control",
    "rtl/integration",
    "rtl/leaf",
    "rtl/memory",
    "rtl/profiling",
    "rtl/top",
    "rtl/experiments/realtime_layernorm",
    "rtl/pe_array/baseline/v1/rtl",
    "rtl/pe_array/production_v2/rtl",
    "sparse_memory_v1/rtl",
)
HARDWARE_FILES = (
    "rtl/tb/tb_accelerator_control_axil.sv",
    "rtl/tb/tb_accelerator_profiling_counters.v",
    "rtl/scripts/create_accelerator_full_bd.tcl",
    "rtl/scripts/synth_accelerator_full_bd.tcl",
    "rtl/scripts/implement_accelerator_full_bd.tcl",
    "rtl/scripts/xsim_run_all.tcl",
)
BUILD_FILES = (
    "rtl/scripts/Run-Accelerator-Full-BD-Implementation-Vivado.cmd",
    "rtl/scripts/write_accelerator_full_artifacts.tcl",
    "rtl/scripts/make_accelerator_full_manifest.py",
    "rtl/scripts/program_accelerator_full_board.tcl",
    "software/pynq/accelerator_bringup.py",
    "software/pynq/arm_barrier.c",
)
PARAMETER_IMAGE = "outputs/memory/2026-09-09/v5/parameters_v5.bin"
PARAMETER_GOLDEN = "outputs/memory/2026-09-09/v5/memory_golden_v5.json"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git_bytes(repo: Path, commit: str, relative_path: str) -> bytes:
    return subprocess.run(
        ["git", "show", f"{commit}:{relative_path}"],
        cwd=repo,
        check=True,
        stdout=subprocess.PIPE,
    ).stdout


def git_output(repo: Path, *args: str) -> str:
    return subprocess.run(
        ["git", *args],
        cwd=repo,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    ).stdout.strip()


def parse_key_values(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            result[key] = value
    return result


def baseline_hardware_files(repo: Path, hardware_commit: str) -> list[str]:
    listed = git_output(
        repo,
        "ls-tree",
        "-r",
        "--name-only",
        hardware_commit,
        "--",
        *HARDWARE_PREFIXES,
    ).splitlines()
    return sorted(set(listed).union(HARDWARE_FILES))


def file_record(path: Path, relative: str, matches_baseline: bool | None) -> dict:
    return {
        "path": relative,
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
        "matches_baseline": matches_baseline,
    }


def require_equal_number(
    metadata: dict[str, str], metrics: dict[str, str], left: str, right: str
) -> None:
    if abs(float(metadata[left]) - float(metrics[right])) > 0.0005:
        raise SystemExit(f"artifact metric {left} does not match implementation {right}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--artifact-dir", type=Path, required=True)
    parser.add_argument("--metadata", type=Path, required=True)
    parser.add_argument("--implementation-metrics", type=Path, required=True)
    parser.add_argument("--hardware-commit", required=True)
    parser.add_argument("--image-abi", type=lambda value: int(value, 0), required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    repo = args.repo.resolve()
    artifact_dir = args.artifact_dir.resolve()
    hardware_commit = git_output(
        repo, "rev-parse", f"{args.hardware_commit}^{{commit}}"
    )
    repository_head = git_output(repo, "rev-parse", "HEAD")
    if repository_head != hardware_commit:
        raise SystemExit(
            "repository HEAD does not match --hardware-commit: "
            f"{repository_head} != {hardware_commit}"
        )
    if not 0 <= args.image_abi <= 0xFFFF_FFFF:
        raise SystemExit("--image-abi must fit in an unsigned 32-bit register")
    image_abi = f"0x{args.image_abi:08X}"
    metadata = parse_key_values(args.metadata.resolve())
    metrics = parse_key_values(args.implementation_metrics.resolve())

    required_metadata = {
        "schema": "zephyr.accelerator.full.build.v1",
        "hardware_source_commit": hardware_commit,
        "vivado_version": "2018.3",
        "part": "xc7z020clg400-1",
        "top": "zephyr_full_wrapper",
        "write_bitstream_completed": "YES",
        "hwh_copied_from_same_project": "YES",
    }
    for key, expected in required_metadata.items():
        if metadata.get(key) != expected:
            raise SystemExit(f"build metadata mismatch: {key}={metadata.get(key)!r}")
    for gate in (
        "timing_met",
        "hold_met",
        "hold_guardband_met",
        "resources_below_limit",
        "routing_errors_zero",
        "blocking_drc_zero",
        "full_gate_pass",
    ):
        if metrics.get(gate) != "1":
            raise SystemExit(f"implementation release gate is not closed: {gate}")
    if metrics.get("design_baseline_commit") != hardware_commit:
        raise SystemExit("implementation metrics do not identify the frozen baseline")

    require_equal_number(metadata, metrics, "setup_wns_ns", "setup_wns_ns")
    require_equal_number(
        metadata, metrics, "setup_guardbanded_wns_ns", "setup_guardbanded_wns_ns"
    )
    require_equal_number(
        metadata, metrics, "hold_guardbanded_whs_ns", "hold_whs_ns"
    )
    require_equal_number(
        metadata, metrics, "hold_raw_physical_margin_ns", "hold_raw_physical_margin_ns"
    )

    source_inputs = []
    for relative in baseline_hardware_files(repo, hardware_commit):
        path = repo / relative
        worktree_bytes = path.read_bytes()
        if worktree_bytes != git_bytes(repo, hardware_commit, relative):
            raise SystemExit(
                f"hardware input differs from {hardware_commit}: {relative}"
            )
        source_inputs.append(file_record(path, relative, True))
    for relative in BUILD_FILES:
        path = repo / relative
        source_inputs.append(file_record(path, relative, None))

    artifacts = {}
    for suffix in ("bit", "hwh"):
        filename = f"{ARTIFACT_BASENAME}.{suffix}"
        path = artifact_dir / filename
        if not path.is_file() or path.stat().st_size == 0:
            raise SystemExit(f"artifact is missing or empty: {path}")
        artifacts[filename] = {
            "bytes": path.stat().st_size,
            "sha256": sha256_file(path),
        }

    image_path = repo / PARAMETER_IMAGE
    golden_path = repo / PARAMETER_GOLDEN
    for relative, path in (
        (PARAMETER_IMAGE, image_path),
        (PARAMETER_GOLDEN, golden_path),
    ):
        if path.read_bytes() != git_bytes(repo, hardware_commit, relative):
            raise SystemExit(
                f"parameter release input differs from {hardware_commit}: {relative}"
            )
    manifest = {
        "schema": "zephyr.accelerator.full.artifacts.v1",
        "hardware_source_commit": hardware_commit,
        "repository_head_at_manifest": repository_head,
        "source_baseline_verified": True,
        "manifest_created_utc": datetime.now(timezone.utc)
        .isoformat()
        .replace("+00:00", "Z"),
        "tool": {"name": "Vivado", "version": metadata["vivado_version"]},
        "target": {
            "part": metadata["part"],
            "board_part": "www.digilentinc.com:pynq-z1:part0:1.0",
            "top": metadata["top"],
            "fclk0_mhz": int(metadata["fclk0_mhz"]),
            "control_base": "0x43C00000",
            "image_abi": image_abi,
        },
        "post_route": {
            "setup_wns_ns": float(metadata["setup_wns_ns"]),
            "setup_margin_target_ns": float(metadata["setup_margin_target_ns"]),
            "setup_guardbanded_wns_ns": float(
                metadata["setup_guardbanded_wns_ns"]
            ),
            "setup_failing_endpoints": int(metadata["setup_failing_endpoints"]),
            "hold_guardbanded_whs_ns": float(metadata["hold_guardbanded_whs_ns"]),
            "hold_guardband_ns": float(metadata["hold_guardband_ns"]),
            "hold_raw_physical_margin_ns": float(
                metadata["hold_raw_physical_margin_ns"]
            ),
            "hold_failing_endpoints": int(metadata["hold_failing_endpoints"]),
            "unrouted_nets": int(metadata["unrouted_nets"]),
            "partially_routed_nets": int(metadata["partially_routed_nets"]),
            "drc_errors": int(metadata["drc_errors"]),
            "drc_critical_warnings": int(metadata["drc_critical_warnings"]),
            "drc_warnings": int(metadata["drc_warnings"]),
        },
        "artifacts": artifacts,
        "hardware_and_build_inputs": source_inputs,
        "parameter_image": file_record(image_path, PARAMETER_IMAGE, True),
        "parameter_golden": file_record(golden_path, PARAMETER_GOLDEN, True),
    }

    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    (artifact_dir / f"{ARTIFACT_BASENAME}.manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    print(f"ACCELERATOR_FULL_MANIFEST_PASS {output}")


if __name__ == "__main__":
    main()
