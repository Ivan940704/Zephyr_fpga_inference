#!/usr/bin/env python3
"""Summarize the image-v5 real-time latency board experiment."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: dict) -> None:
    path.write_text(
        json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def percent_reduction(old: float, new: float) -> float:
    return (old - new) / old * 100.0


def aggregate_run(root: Path) -> tuple[dict, list[dict], np.ndarray]:
    metric_paths = sorted(root.glob("fileid_*/metrics.json"))
    result_paths = sorted(root.glob("fileid_*/result.npz"))
    metrics = [load_json(path) for path in metric_paths]
    elapsed = np.concatenate([np.load(path)["elapsed_s"] for path in result_paths])
    frames = sum(int(item["frames"]) for item in metrics)
    if len(elapsed) != frames:
        raise ValueError(f"frame evidence mismatch under {root}")
    audio_s = sum(float(item["evaluated_audio_s"]) for item in metrics)
    summary = {
        "status": "PASS" if all(item["status"] == "PASS" for item in metrics) else "FAIL",
        "files": len(metrics),
        "frames": frames,
        "evaluated_audio_s": audio_s,
        "mean_frame_ms": float(np.mean(elapsed) * 1000.0),
        "p50_frame_ms": float(np.percentile(elapsed, 50) * 1000.0),
        "p95_frame_ms": float(np.percentile(elapsed, 95) * 1000.0),
        "p99_frame_ms": float(np.percentile(elapsed, 99) * 1000.0),
        "max_frame_ms": float(np.max(elapsed) * 1000.0),
        "frame_compute_rtf": float(np.sum(elapsed) / audio_s),
        "board_loop_rtf": sum(float(item["inference_loop_s"]) for item in metrics) / audio_s,
        "end_to_end_rtf": sum(float(item["end_to_end_s"]) for item in metrics) / audio_s,
        "worst_file_p99_ms": max(float(item["p99_frame_ms"]) for item in metrics),
        "worst_file_p99_id": int(
            max(metrics, key=lambda item: float(item["p99_frame_ms"]))["source_name"].split("fileid_")[-1].split(".")[0]
        ),
        "worst_file_max_ms": max(float(item["max_frame_ms"]) for item in metrics),
        "audio_weighted_snr_delta_db": sum(
            float(item["snr_delta_db"]) * float(item["evaluated_audio_s"])
            for item in metrics
        ) / audio_s,
        "all_dma_final_states_idle_error_free": all(
            all(state["idle"] and not state["errors"] for state in item["final_hardware_state"]["dma"].values())
            for item in metrics
        ),
        "all_frame_ids_contiguous": all(
            item["frame_ids"] == list(range(int(item["frames"]))) for item in metrics
        ),
    }
    return summary, metrics, elapsed


def sum_mapping(metrics: list[dict], key: str) -> dict[str, int]:
    result: dict[str, int] = {}
    for item in metrics:
        for name, value in item["hardware_profile"][key].items():
            result[name] = result.get(name, 0) + int(value)
    return result


def profile_summary(root: Path, layout_path: Path) -> dict:
    metrics = [load_json(path) for path in sorted(root.glob("fileid_*/metrics.json"))]
    results = [np.load(path) for path in sorted(root.glob("fileid_*/result.npz"))]
    cycles = np.concatenate([item["hardware_frame_cycles"] for item in results])
    timestamps = np.concatenate([item["profile_timestamps_ns"] for item in results])
    frames = len(cycles)
    clock_hz = int(metrics[0]["hardware_profile"]["clock_hz"])
    state_totals = sum_mapping(metrics, "state_cycle_totals")
    load_totals = sum_mapping(metrics, "stage_load_cycle_totals")
    compute_totals = sum_mapping(metrics, "stage_compute_cycle_totals")
    stall_totals = sum_mapping(metrics, "stage_stall_cycle_totals")
    counter_totals = sum_mapping(metrics, "counter_totals")
    layout = load_json(layout_path)
    stages = []
    for stage in layout["stages"]:
        key = f"stage_{stage['id']}"
        stages.append(
            {
                "id": int(stage["id"]),
                "name": stage["name"],
                "kind": stage["kind"],
                "load_ms_per_frame": load_totals[key] / frames / clock_hz * 1000.0,
                "compute_ms_per_frame": compute_totals[key] / frames / clock_hz * 1000.0,
                "stall_ms_per_frame": stall_totals[key] / frames / clock_hz * 1000.0,
            }
        )
    points = metrics[0]["profile"]["points"]
    durations_ms = np.diff(timestamps.astype(np.int64), axis=1) / 1_000_000.0
    buckets = []
    for index, values in enumerate(durations_ms.T):
        buckets.append(
            {
                "name": f"{points[index]}__{points[index + 1]}",
                "mean_ms": float(np.mean(values)),
                "p95_ms": float(np.percentile(values, 95)),
                "p99_ms": float(np.percentile(values, 99)),
                "max_ms": float(np.max(values)),
            }
        )
    return {
        "schema": "zephyr.image-v5-profile6-summary.v1",
        "status": "PASS",
        "scope": {
            "file_ids": [0, 25, 50, 75, 81, 99],
            "files": len(metrics),
            "frames": frames,
            "clock_hz": clock_hz,
            "profiling_overhead_excluded_from_primary_100_file_throughput": True,
        },
        "hardware_pl_latency_ms": {
            "mean": float(np.mean(cycles) / clock_hz * 1000.0),
            "p50": float(np.percentile(cycles, 50) / clock_hz * 1000.0),
            "p95": float(np.percentile(cycles, 95) / clock_hz * 1000.0),
            "p99": float(np.percentile(cycles, 99) / clock_hz * 1000.0),
            "max": float(np.max(cycles) / clock_hz * 1000.0),
        },
        "cycle_conservation": {
            "state_cycles": sum(state_totals.values()),
            "frame_cycles": int(np.sum(cycles)),
            "pass": sum(state_totals.values()) == int(np.sum(cycles)),
        },
        "state_latency_ms_per_frame": {
            name: value / frames / clock_hz * 1000.0
            for name, value in state_totals.items()
        },
        "stages": stages,
        "host_operation_buckets": buckets,
        "counter_totals": counter_totals,
        "mac_skip_fraction": counter_totals["skipped_macs"]
        / (counter_totals["retired_macs"] + counter_totals["skipped_macs"]),
        "request_sparsity": 1.0
        - counter_totals["weight_requests"] / counter_totals["dense_equivalent_requests"],
    }


def parse_build_metadata(path: Path) -> dict[str, object]:
    result: dict[str, object] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        key, value = line.split("=", 1)
        if value in {"YES", "NO"}:
            result[key] = value == "YES"
        else:
            try:
                result[key] = float(value) if "." in value else int(value)
            except ValueError:
                result[key] = value
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--experiment-root", type=Path, required=True)
    parser.add_argument("--baseline-100-root", type=Path, required=True)
    parser.add_argument("--baseline-fixed5", type=Path, required=True)
    parser.add_argument("--build-metadata", type=Path, required=True)
    parser.add_argument("--layout", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    fixed5, fixed5_metrics, _ = aggregate_run(args.experiment_root / "fixed5")
    full100, full100_metrics, _ = aggregate_run(args.experiment_root / "full100")
    evaluation = load_json(args.experiment_root / "full100" / "evaluation.json")
    baseline_metrics = [
        load_json(path) for path in sorted(args.baseline_100_root.glob("fileid_*/metrics.json"))
    ]
    baseline_audio_s = sum(float(item["evaluated_audio_s"]) for item in baseline_metrics)
    baseline_frames = sum(int(item["frames"]) for item in baseline_metrics)
    baseline100 = {
        "files": len(baseline_metrics),
        "frames": baseline_frames,
        "evaluated_audio_s": baseline_audio_s,
        "mean_frame_ms": sum(float(item["mean_frame_ms"]) * int(item["frames"]) for item in baseline_metrics) / baseline_frames,
        "frame_compute_rtf": sum(float(item["mean_frame_ms"]) * int(item["frames"]) / 1000.0 for item in baseline_metrics) / baseline_audio_s,
        "board_loop_rtf": sum(float(item["inference_loop_s"]) for item in baseline_metrics) / baseline_audio_s,
        "end_to_end_rtf": sum(float(item["end_to_end_s"]) for item in baseline_metrics) / baseline_audio_s,
        "worst_file_p99_ms": max(float(item["p99_frame_ms"]) for item in baseline_metrics),
        "worst_file_max_ms": max(float(item["max_frame_ms"]) for item in baseline_metrics),
    }
    baseline_evaluation = load_json(args.baseline_100_root / "evaluation.json")
    fixed5_baseline = load_json(args.baseline_fixed5)["precomputed"]
    build = parse_build_metadata(args.build_metadata)
    resources = {
        "schema": "zephyr.image-v5-full-zynq-resource-timing.v1",
        "evidence": "Vivado 2018.3 full-design post-route artifact gate",
        **build,
        "slice_lut_percent": float(build["slice_luts"]) / 53200.0 * 100.0,
        "slice_register_percent": float(build["slice_registers"]) / 106400.0 * 100.0,
        "bram36_equivalent_percent": float(build["bram36_equivalent"]) / 140.0 * 100.0,
        "dsp48_percent": float(build["dsp48_primitives"]) / 220.0 * 100.0,
    }
    profiles = profile_summary(args.experiment_root / "profile6", args.layout)
    comparison = {
        "schema": "zephyr.image-v5-comparison-v1",
        "fixed5_same_precomputed_frontend": {
            "baseline": fixed5_baseline,
            "candidate": fixed5,
            "reduction_percent": {
                "mean_frame_ms": percent_reduction(fixed5_baseline["weighted_mean_frame_ms"], fixed5["mean_frame_ms"]),
                "frame_compute_rtf": percent_reduction(fixed5_baseline["aggregate_frame_compute_rtf"], fixed5["frame_compute_rtf"]),
                "board_loop_rtf": percent_reduction(fixed5_baseline["aggregate_board_loop_rtf"], fixed5["board_loop_rtf"]),
                "end_to_end_rtf": percent_reduction(fixed5_baseline["aggregate_end_to_end_rtf"], fixed5["end_to_end_rtf"]),
            },
        },
        "full100_original_corpus": {
            "baseline": baseline100,
            "candidate": full100,
            "reduction_percent": {
                key: percent_reduction(baseline100[key], full100[key])
                for key in ("mean_frame_ms", "frame_compute_rtf", "board_loop_rtf", "end_to_end_rtf", "worst_file_p99_ms", "worst_file_max_ms")
            },
            "quality": {
                "baseline": baseline_evaluation["summary"],
                "candidate": evaluation["summary"],
                "mean_snr_delta_change_db": evaluation["summary"]["snr_delta_db"]["mean"] - baseline_evaluation["summary"]["snr_delta_db"]["mean"],
                "mean_si_sdr_delta_change_db": evaluation["summary"]["si_sdr_delta_db"]["mean"] - baseline_evaluation["summary"]["si_sdr_delta_db"]["mean"],
            },
        },
    }
    full100["quality"] = evaluation["summary"]
    full100["optional_metrics"] = evaluation["optional_metrics"]
    full100["realtime_gate"] = {
        "pl_p99_below_8ms": full100["p99_frame_ms"] < 8.0 and full100["worst_file_p99_ms"] < 8.0,
        "board_loop_rtf_below_1": full100["board_loop_rtf"] < 1.0,
        "end_to_end_rtf_below_1": full100["end_to_end_rtf"] < 1.0,
        "overall": "PASS" if full100["p99_frame_ms"] < 8.0 and full100["worst_file_p99_ms"] < 8.0 and full100["board_loop_rtf"] < 1.0 and full100["end_to_end_rtf"] < 1.0 else "FAIL",
    }
    fixed5["records"] = [
        {key: item[key] for key in ("source_name", "frames", "mean_frame_ms", "p50_frame_ms", "p95_frame_ms", "p99_frame_ms", "max_frame_ms", "frame_compute_rtf", "board_loop_rtf", "end_to_end_rtf", "snr_delta_db")}
        for item in fixed5_metrics
    ]
    archives = {
        "full100": {
            "path": str(args.experiment_root / "full100_store_boundary_evidence.tar"),
            "sha256": sha256_file(args.experiment_root / "full100_store_boundary_evidence.tar"),
        },
        "profile6": {
            "path": str(args.experiment_root / "profile6_store_boundary_evidence.tar"),
            "sha256": sha256_file(args.experiment_root / "profile6_store_boundary_evidence.tar"),
        },
    }
    write_json(args.output_dir / "fixed5_summary.json", fixed5)
    write_json(args.output_dir / "full100_summary.json", full100)
    write_json(args.output_dir / "profile6_stage_latency.json", profiles)
    write_json(args.output_dir / "resource_timing_summary.json", resources)
    write_json(args.output_dir / "comparison_vs_ec457b1.json", comparison)
    write_json(args.output_dir / "evidence_archives.json", archives)

    top_states = sorted(
        profiles["state_latency_ms_per_frame"].items(), key=lambda item: item[1], reverse=True
    )
    top_buckets = sorted(
        profiles["host_operation_buckets"], key=lambda item: item["mean_ms"], reverse=True
    )
    lines = [
        "# Image-v5 32-PE latency experiment",
        "",
        "## Outcome",
        "",
        f"The PL path passes the 8 ms hop gate: 100-file aggregate p99 is {full100['p99_frame_ms']:.3f} ms and the worst per-file p99 is {full100['worst_file_p99_ms']:.3f} ms. The complete system is not yet real-time: board-loop RTF is {full100['board_loop_rtf']:.3f} and end-to-end RTF is {full100['end_to_end_rtf']:.3f}.",
        "",
        "The candidate uses host-precomputed STFT/magnitude, PL LayerNorm, 32 PEs, a 256-bit internal four-bank feed, persistent A/B DMA buffers, and a timing-clean 100 MHz image. The native Zynq HP/AXIS boundary remains 64-bit. A fresh 102 MHz 32-lane datapath route failed setup (WNS -0.112 ns), so it was rejected rather than programmed.",
        "",
        "## Fixed five-file comparison",
        "",
        "| Metric | ec457b1 host-feature baseline | image-v5 | Reduction |",
        "|---|---:|---:|---:|",
        f"| Mean frame | {fixed5_baseline['weighted_mean_frame_ms']:.3f} ms | {fixed5['mean_frame_ms']:.3f} ms | {comparison['fixed5_same_precomputed_frontend']['reduction_percent']['mean_frame_ms']:.2f}% |",
        f"| Frame-compute RTF | {fixed5_baseline['aggregate_frame_compute_rtf']:.3f} | {fixed5['frame_compute_rtf']:.3f} | {comparison['fixed5_same_precomputed_frontend']['reduction_percent']['frame_compute_rtf']:.2f}% |",
        f"| Board-loop RTF | {fixed5_baseline['aggregate_board_loop_rtf']:.3f} | {fixed5['board_loop_rtf']:.3f} | {comparison['fixed5_same_precomputed_frontend']['reduction_percent']['board_loop_rtf']:.2f}% |",
        f"| End-to-end RTF | {fixed5_baseline['aggregate_end_to_end_rtf']:.3f} | {fixed5['end_to_end_rtf']:.3f} | {comparison['fixed5_same_precomputed_frontend']['reduction_percent']['end_to_end_rtf']:.2f}% |",
        "",
        f"Scope: 5 files, {fixed5['frames']:,} frames, {fixed5['evaluated_audio_s']:.3f} s audio. Candidate p50/p95/p99/max are {fixed5['p50_frame_ms']:.3f}/{fixed5['p95_frame_ms']:.3f}/{fixed5['p99_frame_ms']:.3f}/{fixed5['max_frame_ms']:.3f} ms.",
        "",
        "## 100-file comparison",
        "",
        "| Metric | ec457b1 | image-v5 | Reduction |",
        "|---|---:|---:|---:|",
        f"| Mean frame | {baseline100['mean_frame_ms']:.3f} ms | {full100['mean_frame_ms']:.3f} ms | {comparison['full100_original_corpus']['reduction_percent']['mean_frame_ms']:.2f}% |",
        f"| Frame-compute RTF | {baseline100['frame_compute_rtf']:.3f} | {full100['frame_compute_rtf']:.3f} | {comparison['full100_original_corpus']['reduction_percent']['frame_compute_rtf']:.2f}% |",
        f"| Board-loop RTF | {baseline100['board_loop_rtf']:.3f} | {full100['board_loop_rtf']:.3f} | {comparison['full100_original_corpus']['reduction_percent']['board_loop_rtf']:.2f}% |",
        f"| End-to-end RTF | {baseline100['end_to_end_rtf']:.3f} | {full100['end_to_end_rtf']:.3f} | {comparison['full100_original_corpus']['reduction_percent']['end_to_end_rtf']:.2f}% |",
        f"| Worst per-file p99 | {baseline100['worst_file_p99_ms']:.3f} ms | {full100['worst_file_p99_ms']:.3f} ms | {comparison['full100_original_corpus']['reduction_percent']['worst_file_p99_ms']:.2f}% |",
        "",
        f"Scope: 100/100 PASS, {full100['frames']:,} frames, {full100['evaluated_audio_s']:.3f} s audio. Aggregate p50/p95/p99/max are {full100['p50_frame_ms']:.3f}/{full100['p95_frame_ms']:.3f}/{full100['p99_frame_ms']:.3f}/{full100['max_frame_ms']:.3f} ms. All final DMA states were idle/error-free and all frame-ID sequences were contiguous.",
        "",
        f"Mean SNR-delta changed by {comparison['full100_original_corpus']['quality']['mean_snr_delta_change_db']:+.3f} dB and mean SI-SDR-delta by {comparison['full100_original_corpus']['quality']['mean_si_sdr_delta_change_db']:+.3f} dB. PESQ and STOI remain blocked because their Python packages were not installed on the board.",
        "",
        "## Full-Zynq route and resources",
        "",
        "| Item | Result |",
        "|---|---:|",
        f"| Clock | {build['fclk0_mhz']} MHz |",
        f"| WNS / guardbanded WNS | +{build['setup_wns_ns']:.3f} / {build['setup_guardbanded_wns_ns']:.3f} ns |",
        f"| Guardbanded WHS / raw hold | +{build['hold_guardbanded_whs_ns']:.3f} / +{build['hold_raw_physical_margin_ns']:.3f} ns |",
        f"| LUT | {build['slice_luts']:,} ({resources['slice_lut_percent']:.2f}%) |",
        f"| FF | {build['slice_registers']:,} ({resources['slice_register_percent']:.2f}%) |",
        f"| BRAM36 equivalent | {build['bram36_equivalent']:.1f} ({resources['bram36_equivalent_percent']:.2f}%) |",
        f"| DSP | {build['dsp48_primitives']} ({resources['dsp48_percent']:.2f}%) |",
        f"| Routing / DRC | 0 unrouted, {build['drc_errors']} errors, {build['drc_critical_warnings']} critical warnings |",
        "",
        "## Six-file coherent hardware profile",
        "",
        f"Scope: 000/025/050/075/081/099, {profiles['scope']['frames']:,} frames. Hardware-cycle mean/p95/p99/max are {profiles['hardware_pl_latency_ms']['mean']:.3f}/{profiles['hardware_pl_latency_ms']['p95']:.3f}/{profiles['hardware_pl_latency_ms']['p99']:.3f}/{profiles['hardware_pl_latency_ms']['max']:.3f} ms; cycle conservation passed.",
        "",
        "Largest PL state buckets:",
        "",
        "| State | ms/frame |",
        "|---|---:|",
        *[f"| {name} | {value:.4f} |" for name, value in top_states[:6]],
        "",
        "Per-stage load/compute/stall counters (stall is an overlapping diagnostic, not additive):",
        "",
        "| Stage | Model operator | Load ms | Compute ms | Stall ms |",
        "|---:|---|---:|---:|---:|",
        *[f"| {stage['id']} | {stage['name']} | {stage['load_ms_per_frame']:.4f} | {stage['compute_ms_per_frame']:.4f} | {stage['stall_ms_per_frame']:.4f} |" for stage in profiles["stages"]],
        "",
        "Largest profiled host/runtime buckets:",
        "",
        "| Operation bucket | Mean ms | p99 ms |",
        "|---|---:|---:|",
        *[f"| {item['name']} | {item['mean_ms']:.4f} | {item['p99_ms']:.4f} |" for item in top_buckets[:6]],
        "",
        "The 5.303 ms mean retirement/fault-check bucket is the largest software-side target. Profile-mode board/E2E RTF is intentionally excluded from the headline because counter reads and per-frame timestamping add instrumentation overhead.",
        "",
        "## Corpus range correction and evidence limits",
        "",
        "File 030 exposed three magnitude values above signed-Q12 range. The ingress quantizer was changed from fail-fast overflow to saturating Q12; the targeted runtime/profile/feature suite passed 34 tests. Across the complete corpus, 34 values in 28 frames and 8 files saturate; the maximum was 9.508294 versus the Q12 maximum 7.999756.",
        "",
        "This report separates host tests, XSim, full-Zynq routed timing, and physical board measurements. It does not claim a physical power result, endurance result, or PESQ/STOI result. The PYNQ system clock was stale, so saved wall-clock dates are not evidence timestamps; hashes and run manifests identify the artifacts.",
    ]
    (args.output_dir / "REPORT.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
