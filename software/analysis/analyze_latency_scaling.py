#!/usr/bin/env python3
"""Combine measured board evidence with bounded 32-PE/clock/interface estimates."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path


BASE_CLOCK_HZ = 100_000_000
TARGET_CLOCK_HZ = 125_000_000
BASE_PE_LANES = 16
TARGET_PE_LANES = 32
SELECTED_FILE_IDS = (0, 25, 50, 75, 99)


def mean(values: list[float]) -> float:
    return sum(values) / len(values)


def load_profile(path: Path) -> list[dict[str, object]]:
    rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]
    if len(rows) < 2:
        raise ValueError("profile must contain at least two frames")
    return rows[1:]


def sum_mapping(row: dict[str, object], key: str) -> int:
    values = row[key]
    if not isinstance(values, dict):
        raise ValueError(f"{key} is not a mapping")
    return sum(int(value) for value in values.values())


def parse_metrics_text(path: Path) -> dict[str, object]:
    values: dict[str, object] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" not in line:
            continue
        key, raw = line.split("=", 1)
        try:
            values[key] = float(raw) if "." in raw or raw.startswith("-") else int(raw)
        except ValueError:
            values[key] = raw
    return values


def weighted_average(records: list[dict[str, object]], key: str, weight: str) -> float:
    denominator = sum(float(record[weight]) for record in records)
    return sum(float(record[key]) * float(record[weight]) for record in records) / denominator


def project_pl_latency_ms(
    *,
    frame_cycles: float,
    wait_ps_cycles: float,
    compute_cycles: float,
    scalable_compute_fraction: float,
    target_clock_hz: int,
) -> float:
    lane_speedup = TARGET_PE_LANES / BASE_PE_LANES
    saved_cycles = compute_cycles * scalable_compute_fraction * (1.0 - 1.0 / lane_speedup)
    remaining_clock_scaled_cycles = frame_cycles - wait_ps_cycles - saved_cycles
    if remaining_clock_scaled_cycles < 0:
        raise ValueError("projection removed more cycles than exist")
    # PS service latency is wall-time dominated: a faster PL clock does not make
    # the ARM service loop faster, so retain its measured duration.
    return 1000.0 * (
        wait_ps_cycles / BASE_CLOCK_HZ
        + remaining_clock_scaled_cycles / target_clock_hz
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline-root", type=Path, required=True)
    parser.add_argument("--hardware-profile", type=Path, required=True)
    parser.add_argument("--host-feature-manifest", type=Path, required=True)
    parser.add_argument("--ooc-metrics", type=Path, required=True)
    parser.add_argument("--board-frontend-ab-summary", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    baseline_records = []
    for file_id in SELECTED_FILE_IDS:
        path = args.baseline_root / f"fileid_{file_id:03d}" / "metrics.json"
        metrics = json.loads(path.read_text(encoding="utf-8"))
        if metrics.get("status") != "PASS":
            raise ValueError(f"baseline file ID {file_id} is not PASS")
        baseline_records.append(
            {
                "file_id": file_id,
                "frames": int(metrics["frames"]),
                "evaluated_audio_s": float(metrics["evaluated_audio_s"]),
                "mean_frame_ms": float(metrics["mean_frame_ms"]),
                "inference_loop_s": float(metrics["inference_loop_s"]),
                "end_to_end_s": float(metrics["end_to_end_s"]),
                "frame_compute_rtf": float(metrics["frame_compute_rtf"]),
                "board_loop_rtf": float(metrics["board_loop_rtf"]),
                "end_to_end_rtf": float(metrics["end_to_end_rtf"]),
                "snr_delta_db": float(metrics["snr_delta_db"]),
                "input_sha256": metrics["input_sha256"],
            }
        )
    total_audio_s = sum(record["evaluated_audio_s"] for record in baseline_records)
    total_frames = sum(record["frames"] for record in baseline_records)
    baseline = {
        "evidence": "measured_PYNQ_Z1_ec457b1",
        "selected_file_ids": list(SELECTED_FILE_IDS),
        "files": len(baseline_records),
        "frames": total_frames,
        "evaluated_audio_s": total_audio_s,
        "weighted_mean_frame_ms": weighted_average(
            baseline_records, "mean_frame_ms", "frames"
        ),
        "aggregate_frame_compute_rtf": sum(
            record["mean_frame_ms"] * record["frames"] / 1000.0
            for record in baseline_records
        ) / total_audio_s,
        "aggregate_board_loop_rtf": sum(
            record["inference_loop_s"] for record in baseline_records
        ) / total_audio_s,
        "aggregate_end_to_end_rtf": sum(
            record["end_to_end_s"] for record in baseline_records
        ) / total_audio_s,
        "audio_weighted_snr_delta_db": weighted_average(
            baseline_records, "snr_delta_db", "evaluated_audio_s"
        ),
        "records": baseline_records,
    }

    profile_rows = load_profile(args.hardware_profile)
    frame_cycles = mean([float(row["frame_cycles"]) for row in profile_rows])
    wait_ps_cycles = mean(
        [float(row["state_cycles"]["wait_ps"]) for row in profile_rows]
    )
    compute_cycles = mean(
        [float(sum_mapping(row, "stage_compute_cycles")) for row in profile_rows]
    )
    profile = {
        "evidence": "measured_PYNQ_Z1_fileid_081_excluding_first_frame",
        "frames": len(profile_rows),
        "mean_frame_cycles": frame_cycles,
        "mean_pl_latency_ms_at_100mhz": frame_cycles * 1000.0 / BASE_CLOCK_HZ,
        "mean_wait_ps_cycles": wait_ps_cycles,
        "mean_stage_compute_cycles": compute_cycles,
        "compute_fraction_of_frame": compute_cycles / frame_cycles,
    }

    scenarios = {}
    for name, scalable_fraction in (("conservative_70pct", 0.70), ("ideal_100pct", 1.0)):
        latency_100 = project_pl_latency_ms(
            frame_cycles=frame_cycles,
            wait_ps_cycles=wait_ps_cycles,
            compute_cycles=compute_cycles,
            scalable_compute_fraction=scalable_fraction,
            target_clock_hz=BASE_CLOCK_HZ,
        )
        latency_125 = project_pl_latency_ms(
            frame_cycles=frame_cycles,
            wait_ps_cycles=wait_ps_cycles,
            compute_cycles=compute_cycles,
            scalable_compute_fraction=scalable_fraction,
            target_clock_hz=TARGET_CLOCK_HZ,
        )
        scenarios[name] = {
            "evidence": "analytical_projection_not_board_measurement",
            "scalable_stage_compute_fraction": scalable_fraction,
            "pl_latency_ms_32pe_100mhz": latency_100,
            "pl_latency_ms_32pe_125mhz": latency_125,
            "pl_speedup_32pe_125mhz": profile["mean_pl_latency_ms_at_100mhz"] / latency_125,
        }
    clock_only_ms = project_pl_latency_ms(
        frame_cycles=frame_cycles,
        wait_ps_cycles=wait_ps_cycles,
        compute_cycles=compute_cycles,
        scalable_compute_fraction=0.0,
        target_clock_hz=TARGET_CLOCK_HZ,
    )

    payload_bytes = {"fullband": 64, "spectrum": 512, "output": 2048}
    beats_64 = sum(math.ceil(size / 8) for size in payload_bytes.values())
    beats_128 = sum(math.ceil(size / 16) for size in payload_bytes.values())
    interface = {
        "evidence": "analytical_upper_bound_from_current_payload_contract",
        "zynq7020_hp_port_width_bits": 64,
        "current_axis_width_bits": 64,
        "candidate_axis_width_bits": 128,
        "payload_bytes_per_frame": payload_bytes,
        "axis_beats_per_frame_64bit": beats_64,
        "axis_beats_per_frame_128bit": beats_128,
        "maximum_saved_axis_cycles_per_frame": beats_64 - beats_128,
        "maximum_saved_us_at_125mhz": (beats_64 - beats_128) * 1_000_000 / TARGET_CLOCK_HZ,
        "ddr_bandwidth_doubles": False,
        "reason": "PS7 S_AXI_HP ports remain 64-bit; a 128-bit AXIS adds width conversion",
    }

    host_features = json.loads(args.host_feature_manifest.read_text(encoding="utf-8"))
    host_compute = [float(record["host_compute_elapsed_s"]) for record in host_features["records"]]
    ooc = parse_metrics_text(args.ooc_metrics)
    full_design_clock = {
        "evidence": "existing_ec457b1_full_design_post_route_plus_period_arithmetic",
        "100mhz_standard_wns_ns": 0.264,
        "100mhz_250ps_guardband_wns_ns": 0.014,
        "projected_125mhz_standard_wns_ns_without_netlist_change": -1.736,
        "125mhz_full_design_status": "NOT_TIMING_CLOSED",
    }
    board_frontend_ab: object = "NOT_PROVIDED"
    if args.board_frontend_ab_summary is not None:
        board_frontend_ab = json.loads(
            args.board_frontend_ab_summary.read_text(encoding="utf-8")
        )
        if not isinstance(board_frontend_ab, dict):
            raise ValueError("board frontend A/B summary must be a JSON object")
        if board_frontend_ab.get("status") != "PASS":
            raise ValueError("board frontend A/B summary is not PASS")
        if board_frontend_ab.get("file_ids") != list(SELECTED_FILE_IDS):
            raise ValueError("board frontend A/B summary used unexpected file IDs")
    output = {
        "schema": "zephyr.latency-scaling-analysis.v2",
        "baseline_5_audio": baseline,
        "representative_hardware_profile": profile,
        "host_feature_precompute": {
            "evidence": "measured_Windows_x86",
            "files": len(host_compute),
            "mean_s": mean(host_compute),
            "min_s": min(host_compute),
            "max_s": max(host_compute),
        },
        "clock_only_125mhz": {
            "evidence": "analytical_projection_not_board_measurement",
            "projected_pl_latency_ms": clock_only_ms,
            "projected_pl_speedup": profile["mean_pl_latency_ms_at_100mhz"] / clock_only_ms,
        },
        "pe_and_clock_scenarios": scenarios,
        "interface_width": interface,
        "ooc_32lane_125mhz": ooc,
        "full_design_clock": full_design_clock,
        "board_frontend_ab": board_frontend_ab,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("LATENCY_SCALING_ANALYSIS " + json.dumps(output, sort_keys=True))


if __name__ == "__main__":
    main()
