import numpy as np
import pytest

from software.pynq.accelerator_bringup import (
    DmaSnapshot,
    fresh_parameter_epoch_reset,
)
from software.pynq.run_board_endurance import (
    percentile_summary,
    validate_hardware_snapshot,
)
from software.pynq.run_board_experiment_matrix import (
    compare_correctness,
    frame_ids_are_contiguous,
    repeated_statistics,
)


def result_arrays(value):
    return {
        "accumulators": np.full((1, 256, 2), value, dtype=np.int32),
        "fb_projections": np.full((1, 64), value, dtype=np.int8),
        "sb_payloads": np.full((1, 782), value, dtype=np.int8),
        "spectra_q": np.full((1, 512), value, dtype=np.int8),
        "hardware_bins": np.full((256, 1), value, dtype=np.complex64),
    }


def test_experiment_matrix_compares_every_hardware_boundary(tmp_path):
    baseline = tmp_path / "baseline.npz"
    equal = tmp_path / "equal.npz"
    changed = tmp_path / "changed.npz"
    np.savez(baseline, **result_arrays(1))
    np.savez(equal, **result_arrays(1))
    np.savez(changed, **result_arrays(2))
    comparison = compare_correctness(baseline, equal)
    assert all(item["equal"] for item in comparison.values())
    with pytest.raises(RuntimeError, match="correctness mismatch"):
        compare_correctness(baseline, changed)


def test_experiment_statistics_and_frame_wrap_are_explicit():
    assert frame_ids_are_contiguous([65534, 65535, 0, 1])
    assert not frame_ids_are_contiguous([1, 3])
    summary = repeated_statistics([1.0, 2.0, 3.0, 4.0, 5.0])
    assert summary["mean"] == pytest.approx(3.0)
    assert summary["student_t_mean_95ci"][0] < 3.0
    endurance = percentile_summary([0.001, 0.002, 0.003])
    assert endurance["p50_ms"] == pytest.approx(2.0)


def test_fresh_parameter_epoch_reset_is_fail_closed_and_json_safe():
    calls = []

    class Driver:
        def safe_soft_reset(self, *, timeout_s):
            calls.append(timeout_s)
            return {
                "identity": {"image_version": 0x0004_0002},
                "epoch_before": 7,
                "epoch_after": 8,
                "dma": {
                    "io-mm2s": DmaSnapshot("io-mm2s", 0, 0x3),
                },
            }

    result = fresh_parameter_epoch_reset(
        barrier=lambda: None,
        driver_factory=lambda **_kwargs: Driver(),
    )
    assert calls == [2.0]
    assert result["epoch_before"] == 7
    assert result["epoch_after"] == 8
    assert result["dma"]["io-mm2s"] == {
        "control": 0,
        "status": 3,
        "stopped": True,
        "errors": 0,
    }


def healthy_hardware_snapshot():
    return {
        "control": {"control_error": 0, "first_fault": 0},
        "dma": {
            name: {"idle": True, "errors": 0, "status": 0x2}
            for name in ("io_mm2s", "io_s2mm", "spectrum_mm2s")
        },
    }


def test_endurance_final_hardware_gate_requires_idle_error_free_dma():
    gate = validate_hardware_snapshot(
        healthy_hardware_snapshot(), context="unit test"
    )
    assert gate["status"] == "PASS"
    assert gate["all_dma_idle"] is True
    assert gate["dma_errors_zero"] is True

    active = healthy_hardware_snapshot()
    active["dma"]["io_s2mm"]["idle"] = False
    with pytest.raises(RuntimeError, match="hardware completion gate failed"):
        validate_hardware_snapshot(active, context="active DMA")

    errored = healthy_hardware_snapshot()
    errored["dma"]["spectrum_mm2s"]["errors"] = 0x10
    with pytest.raises(RuntimeError, match="hardware completion gate failed"):
        validate_hardware_snapshot(errored, context="errored DMA")


def test_endurance_final_hardware_gate_rejects_control_faults_and_bad_schema():
    faulted = healthy_hardware_snapshot()
    faulted["control"]["first_fault"] = 1 << 24
    with pytest.raises(RuntimeError, match="hardware completion gate failed"):
        validate_hardware_snapshot(faulted, context="faulted control")

    with pytest.raises(RuntimeError, match="malformed hardware snapshot"):
        validate_hardware_snapshot({"control": {}}, context="bad schema")
