import json

import pytest

from software.evaluation.power_trace_metrics import SCHEMA, analyze


def write_trace(path, power):
    path.write_text(
        "timestamp_s,power_w\n"
        + "".join(f"{second},{power}\n" for second in range(61)),
        encoding="utf-8",
    )


def make_spec(tmp_path):
    idle = []
    active = []
    for repeat in range(5):
        idle_path = tmp_path / f"idle_{repeat}.csv"
        dense_path = tmp_path / f"dense_{repeat}.csv"
        sparse_path = tmp_path / f"sparse_{repeat}.csv"
        write_trace(idle_path, 1.0)
        write_trace(dense_path, 2.0)
        write_trace(sparse_path, 1.5)
        idle.append({"csv": idle_path.name})
        active.extend(
            (
                {
                    "mode": "dense",
                    "csv": dense_path.name,
                    "completed_frames": 6000,
                    "evaluated_audio_s": 60,
                },
                {
                    "mode": "sparse",
                    "csv": sparse_path.name,
                    "completed_frames": 6000,
                    "evaluated_audio_s": 60,
                },
            )
        )
    spec = {
        "schema": SCHEMA,
        "instrument": {
            "model": "test meter",
            "serial_number": "unit-test",
            "calibration": "synthetic",
            "accuracy": "exact synthetic",
            "sample_rate_hz": 1,
            "connection": "synthetic",
            "input_voltage_v": 5,
            "ambient_temperature_c": 25,
        },
        "idle_runs": idle,
        "active_runs": active,
    }
    path = tmp_path / "spec.json"
    path.write_text(json.dumps(spec), encoding="utf-8")
    return path, spec


def test_physical_power_integrates_and_subtracts_idle(tmp_path):
    path, _ = make_spec(tmp_path)
    result = analyze(path)
    assert result["status"] == "PASS"
    assert result["evidence_type"] == "physical_board_input_power"
    assert result["idle_power_w"]["mean"] == pytest.approx(1.0)
    dense = result["mode_summary"]["dense"]
    sparse = result["mode_summary"]["sparse"]
    assert dense["gross_energy_per_frame_j"]["mean"] == pytest.approx(0.02)
    assert dense["incremental_energy_per_frame_j"]["mean"] == pytest.approx(0.01)
    assert sparse["incremental_energy_per_frame_j"]["mean"] == pytest.approx(0.005)
    assert dense["incremental_energy_per_audio_second_j"]["mean"] == pytest.approx(1.0)


def test_physical_power_rejects_insufficient_repeats(tmp_path):
    path, spec = make_spec(tmp_path)
    spec["idle_runs"] = spec["idle_runs"][:4]
    path.write_text(json.dumps(spec), encoding="utf-8")
    with pytest.raises(ValueError, match="five idle runs"):
        analyze(path)
