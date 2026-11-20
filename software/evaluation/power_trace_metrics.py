#!/usr/bin/env python3
"""Validate calibrated board-power traces and compute frame/audio energy."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import statistics
from pathlib import Path


SCHEMA = "zephyr.physical-power.v1"
REQUIRED_INSTRUMENT_FIELDS = (
    "model",
    "serial_number",
    "calibration",
    "accuracy",
    "sample_rate_hz",
    "connection",
    "input_voltage_v",
    "ambient_temperature_c",
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_trace(path: Path) -> dict[str, object]:
    timestamps: list[float] = []
    powers: list[float] = []
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None or not {"timestamp_s", "power_w"}.issubset(
            reader.fieldnames
        ):
            raise ValueError(f"{path}: CSV needs timestamp_s,power_w columns")
        for row in reader:
            timestamp = float(row["timestamp_s"])
            power = float(row["power_w"])
            if not math.isfinite(timestamp) or not math.isfinite(power) or power < 0:
                raise ValueError(f"{path}: timestamp/power must be finite and power nonnegative")
            if timestamps and timestamp <= timestamps[-1]:
                raise ValueError(f"{path}: timestamps must increase strictly")
            timestamps.append(timestamp)
            powers.append(power)
    if len(timestamps) < 2:
        raise ValueError(f"{path}: trace needs at least two samples")
    duration = timestamps[-1] - timestamps[0]
    if duration < 60.0:
        raise ValueError(f"{path}: trace duration {duration:.3f}s is below 60s")
    energy = sum(
        0.5 * (powers[index] + powers[index - 1])
        * (timestamps[index] - timestamps[index - 1])
        for index in range(1, len(timestamps))
    )
    intervals = [
        timestamps[index] - timestamps[index - 1]
        for index in range(1, len(timestamps))
    ]
    return {
        "path": str(path),
        "sha256": sha256_file(path),
        "samples": len(timestamps),
        "duration_s": duration,
        "mean_power_w": energy / duration,
        "energy_j": energy,
        "derived_sample_rate_hz": 1.0 / statistics.median(intervals),
    }


def repeated_statistics(values: list[float]) -> dict[str, object]:
    if len(values) < 2:
        raise ValueError("at least two values are needed")
    mean = statistics.fmean(values)
    deviation = statistics.stdev(values)
    # The physical-power gate requires five repeats, so df=4 is the minimum.
    critical = {4: 2.776, 5: 2.571, 6: 2.447, 7: 2.365, 8: 2.306}.get(
        len(values) - 1, 1.96
    )
    half_width = critical * deviation / math.sqrt(len(values))
    return {
        "count": len(values),
        "mean": mean,
        "standard_deviation": deviation,
        "student_t_mean_95ci": [mean - half_width, mean + half_width],
        "minimum": min(values),
        "maximum": max(values),
    }


def analyze(spec_path: Path) -> dict[str, object]:
    spec_path = spec_path.resolve()
    spec = json.loads(spec_path.read_text(encoding="utf-8"))
    if spec.get("schema") != SCHEMA:
        raise ValueError(f"spec schema must be {SCHEMA}")
    instrument = spec.get("instrument", {})
    missing = [name for name in REQUIRED_INSTRUMENT_FIELDS if not instrument.get(name)]
    if missing:
        raise ValueError(f"instrument metadata is incomplete: {missing}")
    declared_rate = float(instrument["sample_rate_hz"])
    if declared_rate <= 0:
        raise ValueError("instrument sample_rate_hz must be positive")

    base = spec_path.parent
    idle_specs = spec.get("idle_runs", [])
    active_specs = spec.get("active_runs", [])
    if len(idle_specs) < 5:
        raise ValueError("physical power requires at least five idle runs")
    modes = sorted({str(run.get("mode", "")) for run in active_specs})
    if not modes or "" in modes:
        raise ValueError("every active run needs a nonempty mode")
    for mode in modes:
        if sum(run.get("mode") == mode for run in active_specs) < 5:
            raise ValueError(f"mode {mode} needs at least five active runs")

    def resolve_trace(run: dict[str, object]) -> dict[str, object]:
        path = (base / str(run["csv"])).resolve()
        trace = read_trace(path)
        derived_rate = float(trace["derived_sample_rate_hz"])
        if abs(derived_rate - declared_rate) / declared_rate > 0.20:
            raise ValueError(
                f"{path}: derived sample rate {derived_rate:.3f}Hz differs from "
                f"declared {declared_rate:.3f}Hz by more than 20%"
            )
        return trace

    idle_runs = [resolve_trace(run) for run in idle_specs]
    idle_power = statistics.fmean(float(run["mean_power_w"]) for run in idle_runs)
    active_runs = []
    for run_spec in active_specs:
        completed_frames = int(run_spec.get("completed_frames", 0))
        evaluated_audio_s = float(run_spec.get("evaluated_audio_s", 0))
        if completed_frames <= 0 or evaluated_audio_s <= 0:
            raise ValueError("active runs require positive frames and evaluated_audio_s")
        trace = resolve_trace(run_spec)
        duration = float(trace["duration_s"])
        gross_energy = float(trace["energy_j"])
        incremental_energy = gross_energy - idle_power * duration
        active_runs.append(
            {
                **trace,
                "mode": run_spec["mode"],
                "completed_frames": completed_frames,
                "evaluated_audio_s": evaluated_audio_s,
                "gross_energy_per_frame_j": gross_energy / completed_frames,
                "incremental_energy_per_frame_j": incremental_energy
                / completed_frames,
                "gross_energy_per_audio_second_j": gross_energy
                / evaluated_audio_s,
                "incremental_energy_per_audio_second_j": incremental_energy
                / evaluated_audio_s,
                "idle_subtracted_mean_power_w": float(trace["mean_power_w"])
                - idle_power,
            }
        )

    fields = (
        "mean_power_w",
        "idle_subtracted_mean_power_w",
        "gross_energy_per_frame_j",
        "incremental_energy_per_frame_j",
        "gross_energy_per_audio_second_j",
        "incremental_energy_per_audio_second_j",
    )
    groups = {
        mode: {
            field: repeated_statistics(
                [float(run[field]) for run in active_runs if run["mode"] == mode]
            )
            for field in fields
        }
        for mode in modes
    }
    return {
        "schema": SCHEMA,
        "status": "PASS",
        "evidence_type": "physical_board_input_power",
        "instrument": instrument,
        "idle_power_w": repeated_statistics(
            [float(run["mean_power_w"]) for run in idle_runs]
        ),
        "idle_runs": idle_runs,
        "active_runs": active_runs,
        "mode_summary": groups,
        "definitions": {
            "gross_energy_per_frame": "integral(power dt) / completed_frames",
            "incremental_energy_per_frame": (
                "integral((power - pooled_idle_mean_power) dt) / completed_frames"
            ),
            "energy_per_audio_second": "energy / evaluated_audio_seconds",
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--spec", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = analyze(args.spec)
    if args.output.exists():
        parser.error("refusing to overwrite an existing physical-power result")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(
        "PHYSICAL_POWER_RESULT "
        + json.dumps(
            {
                "status": result["status"],
                "modes": sorted(result["mode_summary"]),
                "output": str(args.output),
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
