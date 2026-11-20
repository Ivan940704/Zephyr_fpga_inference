#!/usr/bin/env python3
"""Create and verify the traceability manifest for Stage 2 board artifacts."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
from typing import Dict


BASELINE_COMMIT = "78c86f38f7c8f227bc2d032f5e2ef59ae4935d3e"
ARTIFACT_BASENAME = "parameter_bram_stage2"
HARDWARE_INPUTS = (
    "rtl/memory/memory.v",
    "rtl/memory/model_memory_v3_table.v",
    "rtl/memory/model_memory_v3_map.vh",
    "rtl/memory/memory_service.v",
    "rtl/memory/memory_service_axil.v",
    "rtl/memory/parameter_bram_bringup_top.v",
    "rtl/scripts/create_parameter_bram_bringup_bd.tcl",
    "rtl/scripts/implement_parameter_bram_bringup_bd.tcl",
)
BUILD_INPUTS = (
    "rtl/scripts/write_parameter_bram_stage2_bitstream.tcl",
    "rtl/scripts/Run-Parameter-Bram-Stage2-Bitstream-Vivado.cmd",
    "rtl/scripts/make_parameter_bram_stage2_manifest.py",
    "software/pynq/parameter_bram_bringup.py",
    "software/pynq/run_parameter_bram_stage2.py",
    "software/pynq/arm_barrier.c",
)
PARAMETER_IMAGE = "outputs/memory/2026-09-01/v3/parameters_v3.bin"
PARAMETER_GOLDEN = "outputs/memory/2026-09-01/v3/memory_golden_v3.json"
TEXT_REPORT_SUFFIXES = {".log", ".rpt", ".txt"}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_key_values(path: Path) -> Dict[str, str]:
    values: Dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key] = value
    return values


def normalize_text_reports(report_dir: Path) -> None:
    """Store Windows-generated text evidence using the repository LF style."""
    for path in sorted(report_dir.iterdir()):
        if not path.is_file() or path.suffix.lower() not in TEXT_REPORT_SUFFIXES:
            continue
        lines = path.read_text(encoding="utf-8").splitlines()
        while lines and not lines[-1].strip():
            lines.pop()
        path.write_text(
            "\n".join(line.rstrip() for line in lines) + "\n", encoding="utf-8"
        )


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


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--artifact-dir", type=Path, required=True)
    parser.add_argument("--metadata", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    repo = args.repo.resolve()
    artifact_dir = args.artifact_dir.resolve()
    metadata_path = args.metadata.resolve()
    output = args.output.resolve()
    normalize_text_reports(output.parent)
    metadata = parse_key_values(metadata_path)
    if metadata.get("hardware_source_commit") != BASELINE_COMMIT:
        raise SystemExit("build metadata does not identify the frozen baseline")
    if metadata.get("write_bitstream_completed") != "YES":
        raise SystemExit("build metadata does not confirm write_bitstream")
    if metadata.get("hwh_copied_from_same_project") != "YES":
        raise SystemExit("build metadata does not confirm a matching HWH")
    if float(metadata["setup_wns_ns"]) < 0 or float(metadata["hold_whs_ns"]) < 0:
        raise SystemExit("post-route timing is not clean")
    if int(metadata["blocking_drc_violations"]) != 0:
        raise SystemExit("post-route DRC has a blocking violation")
    if int(metadata["unrouted_nets"]) != 0:
        raise SystemExit("post-route design has unrouted nets")

    source_inputs = []
    for relative in HARDWARE_INPUTS:
        worktree_path = repo / relative
        worktree_bytes = worktree_path.read_bytes()
        baseline_bytes = git_bytes(repo, BASELINE_COMMIT, relative)
        if worktree_bytes != baseline_bytes:
            raise SystemExit(f"hardware input differs from {BASELINE_COMMIT}: {relative}")
        source_inputs.append(
            {
                "path": relative,
                "bytes": len(worktree_bytes),
                "sha256": hashlib.sha256(worktree_bytes).hexdigest(),
                "matches_baseline": True,
            }
        )
    for relative in BUILD_INPUTS:
        path = repo / relative
        source_inputs.append(
            {
                "path": relative,
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
                "matches_baseline": None,
            }
        )

    artifacts = {}
    for suffix in ("bit", "hwh", "ltx"):
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
    manifest = {
        "schema": "zephyr.parameter_bram.stage2.artifacts.v1",
        "hardware_source_commit": BASELINE_COMMIT,
        "repository_head_at_manifest": git_output(repo, "rev-parse", "HEAD"),
        "source_baseline_verified": True,
        "manifest_created_utc": datetime.now(timezone.utc).isoformat().replace(
            "+00:00", "Z"
        ),
        "tool": {
            "name": "Vivado",
            "version": metadata["vivado_version"],
            "version_full": metadata["vivado_version_full"],
        },
        "target": {
            "part": metadata["part"],
            "board_part": metadata["board_part"],
            "top": metadata["top"],
            "fclk0_mhz": int(metadata["fclk0_mhz"]),
        },
        "build": {
            "completed_utc": metadata["build_completed_utc"],
            "implementation_status": metadata["implementation_status"],
            "write_bitstream_completed": True,
            "hwh_copied_from_same_project": True,
            "write_debug_probes_completed": True,
            "board_connected_during_build": False,
        },
        "post_route": {
            "setup_wns_ns": float(metadata["setup_wns_ns"]),
            "setup_tns_ns": float(metadata["setup_tns_ns"]),
            "setup_failing_endpoints": int(metadata["setup_failing_endpoints"]),
            "hold_whs_ns": float(metadata["hold_whs_ns"]),
            "hold_ths_ns": float(metadata["hold_ths_ns"]),
            "hold_failing_endpoints": int(metadata["hold_failing_endpoints"]),
            "blocking_drc_violations": int(metadata["blocking_drc_violations"]),
            "unrouted_nets": int(metadata["unrouted_nets"]),
        },
        "artifact_basename": ARTIFACT_BASENAME,
        "artifacts": artifacts,
        "hardware_and_build_inputs": source_inputs,
        "parameter_image": {
            "path": PARAMETER_IMAGE,
            "bytes": image_path.stat().st_size,
            "sha256": sha256_file(image_path),
        },
        "parameter_golden": {
            "path": PARAMETER_GOLDEN,
            "bytes": golden_path.stat().st_size,
            "sha256": sha256_file(golden_path),
        },
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    artifact_manifest = artifact_dir / f"{ARTIFACT_BASENAME}.manifest.json"
    artifact_manifest.write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    print(f"PARAMETER_BRAM_STAGE2_MANIFEST_PASS {output}")


if __name__ == "__main__":
    main()
