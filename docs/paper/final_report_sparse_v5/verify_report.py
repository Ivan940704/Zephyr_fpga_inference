#!/usr/bin/env python3
"""Verify the sparse-v5 paper package against its frozen evidence JSON."""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parent
SPARSE_PATH = ROOT / "evidence_summary_sparse_v5.json"
BASELINE_PATH = ROOT / "evidence_summary_image_v5.json"
EXPECTED_HASHES = {
    SPARSE_PATH.name: "c3cd12954c10227da9d6503e6ffca042fda78ba4d6b7474a79cd634176c95ade",
    BASELINE_PATH.name: "79e79e7e577ae101d65f56e052b5cac431d4a2dd2ab12ce416c5984ed15b6065",
}


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def assert_close(actual: float, expected: float, tolerance: float = 1e-9) -> None:
    if not math.isclose(actual, expected, rel_tol=tolerance, abs_tol=tolerance):
        raise AssertionError(f"{actual!r} != {expected!r}")


def require_tokens(path: Path, tokens: list[str]) -> None:
    text = path.read_text(encoding="utf-8")
    missing = [token for token in tokens if token not in text]
    if missing:
        raise AssertionError(f"{path.name} is missing: {missing}")


def main() -> None:
    for path in (SPARSE_PATH, BASELINE_PATH):
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != EXPECTED_HASHES[path.name]:
            raise AssertionError(f"SHA-256 mismatch for {path.name}: {digest}")

    sparse = load_json(SPARSE_PATH)
    baseline = load_json(BASELINE_PATH)
    full = sparse["formal_full100"]
    hardware = sparse["routed_hardware"]
    energy = sparse["power_and_energy_estimate"]
    prior = baseline["primary_100_file_board_measurement"]

    assert sparse["status"] == "PASS"
    assert full["files_passed"] == 100
    assert full["frames"] == 426196
    assert full["profiling_counter_snapshots"] == 0
    assert full["enhanced_bit_exact_vs_image_v5"] == 100
    assert hardware["release_clock_mhz"] == 100

    frame_reduction = 100.0 * (
        prior["weighted_mean_start_to_output_ms"] - full["weighted_mean_frame_ms"]
    ) / prior["weighted_mean_start_to_output_ms"]
    iteration_reduction = 100.0 * (
        prior["weighted_mean_iteration_ms"] - full["weighted_mean_iteration_ms"]
    ) / prior["weighted_mean_iteration_ms"]
    rtf_reduction = 100.0 * (
        prior["sustained_board_loop_rtf"] - full["sustained_frame_loop_rtf"]
    ) / prior["sustained_board_loop_rtf"]
    assert_close(frame_reduction, sparse["comparison_vs_image_v5"]["mean_frame_reduction_percent"])
    assert_close(
        iteration_reduction,
        sparse["comparison_vs_image_v5"]["mean_iteration_reduction_percent"],
    )
    assert_close(rtf_reduction, sparse["comparison_vs_image_v5"]["board_loop_rtf_reduction_percent"])
    assert_close(
        energy["complete_iteration_mj_per_frame"],
        energy["total_on_chip_power_w"] * full["weighted_mean_iteration_ms"],
    )

    common_tokens = [
        "42,773",
        "45,344",
        "76 / 7",
        "68",
        "+0.251",
        "5.3943",
        "5.8076",
        "0.728054",
        "14.5120",
        "9.344",
    ]
    require_tokens(ROOT / "final_report_sparse_v5.md", common_tokens)
    require_tokens(ROOT / "tables_sparse_v5.tex", common_tokens)
    require_tokens(
        ROOT / "paper_measurement_notes_sparse_v5.tex",
        ["42,773", "5.3943", "0.728054", "14.5120", "9.344"],
    )

    for tex_path in (
        ROOT / "tables_sparse_v5.tex",
        ROOT / "paper_measurement_notes_sparse_v5.tex",
    ):
        tex = tex_path.read_text(encoding="utf-8")
        if tex.count("{") != tex.count("}"):
            raise AssertionError(f"Unbalanced braces in {tex_path.name}")

    print("PASS: sparse-v5 paper metrics match the frozen evidence summaries")


if __name__ == "__main__":
    main()
