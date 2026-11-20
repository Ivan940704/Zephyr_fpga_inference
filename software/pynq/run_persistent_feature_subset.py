#!/usr/bin/env python3
"""Process an exact feature subset with one persistent PYNQ runtime instance."""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import numpy as np


REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from software.audio_feature_bundle import (  # noqa: E402
    HOP_SIZE,
    SAMPLE_RATE,
    load_feature_bundle,
    pack_magnitude_frames_q12,
    pack_spectrum_frames_int8,
    read_pcm16,
    sha256_file,
)
from software.evaluation.ptq_audio_metrics import si_sdr_db  # noqa: E402

try:
    from .accelerator_bringup import fresh_parameter_epoch_reset
    from .accelerator_inference import (
        NativeOutputDequantizer,
        PynqAcceleratorRuntime,
        RuntimeParameters,
    )
    from .parameter_bram_bringup import load_arm_dsb_sy
    from .run_accelerator_inference import istft_centered, snr_db, write_pcm16
except ImportError:
    from accelerator_bringup import fresh_parameter_epoch_reset  # type: ignore
    from accelerator_inference import (  # type: ignore
        NativeOutputDequantizer,
        PynqAcceleratorRuntime,
        RuntimeParameters,
    )
    from parameter_bram_bringup import load_arm_dsb_sy  # type: ignore
    from run_accelerator_inference import (  # type: ignore
        istft_centered,
        snr_db,
        write_pcm16,
    )


def weighted_mean(records: list[dict[str, object]], key: str, weight: str) -> float:
    total_weight = sum(float(record[weight]) for record in records)
    return sum(float(record[key]) * float(record[weight]) for record in records) / total_weight


def percentile(values: list[float], percentile_value: float) -> float:
    return float(np.percentile(np.asarray(values, dtype=np.float64), percentile_value))


def validate_final_state(accelerator: PynqAcceleratorRuntime) -> dict[str, object]:
    state = accelerator.diagnostic_snapshot()
    control = state["control"]
    if int(control["control_error"]) & 0x100:
        raise RuntimeError("final control plane has a sticky error")
    if int(control["first_fault"]) & (1 << 24):
        raise RuntimeError("final accelerator state has a latched fault")
    hardware_frame_id = int(control["frame_id"]) & 0xFFFF
    if hardware_frame_id != accelerator.expected_frame_id:
        raise RuntimeError(
            "final accelerator frame ID does not match the software sequence: "
            f"hardware={hardware_frame_id} software={accelerator.expected_frame_id}"
        )
    for name, dma_state in state["dma"].items():
        if int(dma_state["errors"]) or not bool(dma_state["idle"]):
            raise RuntimeError(f"final DMA state is not idle/error-free: {name}={dma_state}")
    return state


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-results-root", type=Path, required=True)
    parser.add_argument("--feature-root", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--parameter-image", type=Path, required=True)
    parser.add_argument("--runtime-parameters", type=Path, required=True)
    parser.add_argument("--parameter-sha256", required=True)
    parser.add_argument("--native-library", type=Path, required=True)
    parser.add_argument("--barrier-library", type=Path, required=True)
    parser.add_argument("--file-ids", type=int, nargs="+", default=(0, 25, 50, 75, 99))
    parser.add_argument("--poll-mode", choices=("sleep", "busy"), default="busy")
    args = parser.parse_args()

    if not args.file_ids or len(args.file_ids) != len(set(args.file_ids)):
        parser.error("--file-ids must contain at least one unique file ID")
    for path in (
        args.parameter_image,
        args.runtime_parameters,
        args.native_library,
        args.barrier_library,
    ):
        if not path.is_file():
            parser.error(f"required file does not exist: {path}")
    if sha256_file(args.parameter_image) != args.parameter_sha256.lower():
        parser.error("parameter image SHA-256 mismatch")
    if args.output_root.exists() and any(args.output_root.iterdir()):
        parser.error("output root must be empty")
    args.output_root.mkdir(parents=True, exist_ok=True)

    cases = []
    for file_id in args.file_ids:
        case_name = f"fileid_{file_id:03d}"
        source_dir = args.source_results_root / case_name
        feature_dir = args.feature_root / case_name
        noisy_path = source_dir / "noisy.wav"
        clean_path = source_dir / "clean.wav"
        if not noisy_path.is_file() or not clean_path.is_file():
            parser.error(f"missing source WAV pair for {case_name}")
        if not feature_dir.is_dir():
            parser.error(f"missing feature bundle for {case_name}")
        cases.append((file_id, case_name, noisy_path, clean_path, feature_dir))

    runtime_parameters = RuntimeParameters.load(args.runtime_parameters)
    output_dequantizer = NativeOutputDequantizer(args.native_library)
    barrier = load_arm_dsb_sy(args.barrier_library)
    reset_evidence = fresh_parameter_epoch_reset(barrier=barrier)
    records = []
    all_frame_elapsed: list[float] = []
    all_iteration_elapsed: list[float] = []
    total_started = time.monotonic()
    runtime_setup_started = time.monotonic()
    with PynqAcceleratorRuntime(
        args.parameter_image,
        runtime_parameters,
        expected_parameter_sha256=args.parameter_sha256,
        mailbox_io_mode="bulk",
        frontend_mode="pl",
        layernorm_mode="native",
        native_layernorm_library=args.native_library,
        native_dma_library=None,
        profiling=False,
        hardware_profiling=False,
        per_frame_diagnostics=False,
        poll_interval_s=0.00005 if args.poll_mode == "sleep" else 0.0,
        conservative_output_cache=False,
        register_io_mode="bulk",
        fast_dma_submit=True,
    ) as accelerator:
        runtime_setup_s = time.monotonic() - runtime_setup_started
        loaded_image_version = accelerator.image_version
        unused_magnitude = np.empty(256, dtype=np.float32)
        unused_spectrum = np.empty(256, dtype=np.complex64)

        for case_index, (file_id, case_name, noisy_path, clean_path, feature_dir) in enumerate(cases):
            case_started = time.monotonic()
            frontend_started = time.monotonic()
            noisy = read_pcm16(noisy_path)
            clean = read_pcm16(clean_path)
            if noisy.shape != clean.shape:
                raise RuntimeError(f"{case_name} clean/noisy sample counts differ")
            bundle = load_feature_bundle(
                feature_dir,
                source_wav=noisy_path,
                source_samples=int(noisy.size),
            )
            magnitude_q12 = bundle.magnitude_q12
            spectrum_q = bundle.spectrum_q
            feature_packing = "prepacked"
            if magnitude_q12 is None or spectrum_q is None:
                magnitude_q12 = pack_magnitude_frames_q12(bundle.magnitude)
                spectrum_q = pack_spectrum_frames_int8(bundle.spectrum)
                feature_packing = "loaded_then_packed_before_board_loop"
            frontend_load_s = time.monotonic() - frontend_started

            frame_count = int(bundle.spectrum.shape[1])
            output_samples = min(noisy.size, max(0, (frame_count - 1) * HOP_SIZE))
            evaluated_audio_s = output_samples / SAMPLE_RATE
            accumulators = np.empty((frame_count, 256, 2), dtype=np.int32)
            frame_elapsed = []
            iteration_elapsed = []
            first_frame_id = accelerator.expected_frame_id
            last_frame_id = None
            prepared_frame = accelerator.prepare_packed_frame(
                magnitude_q12[0],
                spectrum_q[0],
                frame_id=first_frame_id,
            )

            frame_loop_started = time.monotonic()
            for frame in range(frame_count):
                iteration_started = time.monotonic()
                next_prepared = [None]
                prepare_next = None
                if frame + 1 < frame_count:
                    expected_next_frame_id = (prepared_frame.frame_id + 1) & 0xFFFF

                    def prepare_next(
                        next_frame_index=frame + 1,
                        next_frame_id=expected_next_frame_id,
                    ):
                        next_prepared[0] = accelerator.prepare_packed_frame(
                            magnitude_q12[next_frame_index],
                            spectrum_q[next_frame_index],
                            frame_id=next_frame_id,
                        )

                result = accelerator.run_frame(
                    unused_magnitude,
                    unused_spectrum,
                    clear_state=(frame == 0),
                    sparse=True,
                    prepared_frame=prepared_frame,
                    during_execution=prepare_next,
                )
                accumulators[frame] = result.output_accumulators
                frame_elapsed.append(result.elapsed_s)
                iteration_elapsed.append(time.monotonic() - iteration_started)
                last_frame_id = result.frame_id
                if frame + 1 < frame_count:
                    prepared_frame = next_prepared[0]
                    if prepared_frame is None:
                        raise RuntimeError("overlapped next-frame preparation did not complete")
            frame_loop_s = time.monotonic() - frame_loop_started
            final_hardware_state = validate_final_state(accelerator)

            dequant_started = time.monotonic()
            hardware_bins = output_dequantizer.dequantize_batch(accumulators)
            output_dequantization_s = time.monotonic() - dequant_started
            postprocess_started = time.monotonic()
            enhanced_stft = bundle.spectrum[:, :frame_count].copy()
            enhanced_stft[:256] = hardware_bins.T
            enhanced = istft_centered(enhanced_stft, output_samples)
            case_output = args.output_root / case_name
            case_output.mkdir(parents=True, exist_ok=True)
            enhanced_path = case_output / "enhanced.wav"
            write_pcm16(enhanced_path, enhanced)
            postprocess_s = time.monotonic() - postprocess_started

            noisy_eval = noisy[:output_samples]
            clean_eval = clean[:output_samples]
            input_snr = snr_db(clean_eval, noisy_eval)
            enhanced_snr = snr_db(clean_eval, enhanced)
            input_si_sdr = si_sdr_db(clean_eval, noisy_eval)
            enhanced_si_sdr = si_sdr_db(clean_eval, enhanced)
            frame_values = np.asarray(frame_elapsed, dtype=np.float64)
            iteration_values = np.asarray(iteration_elapsed, dtype=np.float64)
            all_frame_elapsed.extend(frame_elapsed)
            all_iteration_elapsed.extend(iteration_elapsed)
            record = {
                "status": "PASS",
                "file_id": file_id,
                "frames": frame_count,
                "first_frame_id": int(first_frame_id),
                "last_frame_id": int(last_frame_id),
                "frame_ids_contiguous": (
                    int(last_frame_id) == ((int(first_frame_id) + frame_count - 1) & 0xFFFF)
                ),
                "evaluated_audio_s": float(evaluated_audio_s),
                "frontend_load_s": float(frontend_load_s),
                "feature_packing": feature_packing,
                "frame_loop_s": float(frame_loop_s),
                "output_dequantization_s": float(output_dequantization_s),
                "postprocess_and_write_s": float(postprocess_s),
                "case_wall_s": float(time.monotonic() - case_started),
                "mean_frame_ms": float(np.mean(frame_values) * 1000),
                "p99_frame_ms": percentile(frame_elapsed, 99) * 1000,
                "mean_iteration_ms": float(np.mean(iteration_values) * 1000),
                "p95_iteration_ms": percentile(iteration_elapsed, 95) * 1000,
                "p99_iteration_ms": percentile(iteration_elapsed, 99) * 1000,
                "max_iteration_ms": float(np.max(iteration_values) * 1000),
                "sustained_frame_loop_rtf": float(frame_loop_s / evaluated_audio_s),
                "input_snr_db": float(input_snr),
                "enhanced_snr_db": float(enhanced_snr),
                "snr_delta_db": float(enhanced_snr - input_snr),
                "input_si_sdr_db": float(input_si_sdr),
                "enhanced_si_sdr_db": float(enhanced_si_sdr),
                "si_sdr_delta_db": float(enhanced_si_sdr - input_si_sdr),
                "input_sha256": sha256_file(noisy_path),
                "bundle_metadata_sha256": bundle.metadata_sha256,
                "enhanced_sha256": sha256_file(enhanced_path),
                "final_hardware_state": final_hardware_state,
            }
            (case_output / "metrics.json").write_text(
                json.dumps(record, indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )
            records.append(record)
            print(
                f"PERSISTENT_SUBSET_PROGRESS completed={case_index + 1}/{len(cases)} "
                f"file_id={file_id}",
                flush=True,
            )
        runtime_open_s = time.monotonic() - runtime_setup_started
        final_session_state = validate_final_state(accelerator)
        runtime_close_started = time.monotonic()
    runtime_close_s = time.monotonic() - runtime_close_started
    total_wall_s = time.monotonic() - total_started

    total_audio_s = sum(float(record["evaluated_audio_s"]) for record in records)
    total_frame_loop_s = sum(float(record["frame_loop_s"]) for record in records)
    total_dequant_s = sum(float(record["output_dequantization_s"]) for record in records)
    total_postprocess_s = sum(float(record["postprocess_and_write_s"]) for record in records)
    aggregate_frame_values = np.asarray(all_frame_elapsed, dtype=np.float64)
    aggregate_iteration_values = np.asarray(all_iteration_elapsed, dtype=np.float64)
    worst_file_p99 = max(records, key=lambda record: float(record["p99_iteration_ms"]))
    manifest = {
        "schema": "zephyr.persistent-feature-subset.v1",
        "status": "PASS",
        "board": "PYNQ-Z1",
        "image_version": f"0x{loaded_image_version:08x}",
        "file_ids": args.file_ids,
        "files": len(records),
        "frames": sum(int(record["frames"]) for record in records),
        "evaluated_audio_s": float(total_audio_s),
        "runtime_instances": 1,
        "parameter_loads": 1,
        "dma_control": "python",
        "software_profiling": False,
        "hardware_profiling": False,
        "profiling_counter_snapshots": 0,
        "per_frame_diagnostics": False,
        "boundary_diagnostic_snapshots": len(records) + 1,
        "output_dequantization_schedule": "deferred_batch_per_file",
        "runtime_setup_s": float(runtime_setup_s),
        "runtime_open_s": float(runtime_open_s),
        "runtime_close_s": float(runtime_close_s),
        "total_frame_loop_s": float(total_frame_loop_s),
        "total_output_dequantization_s": float(total_dequant_s),
        "total_postprocess_and_write_s": float(total_postprocess_s),
        "total_wall_s": float(total_wall_s),
        "weighted_mean_frame_ms": weighted_mean(records, "mean_frame_ms", "frames"),
        "weighted_mean_iteration_ms": weighted_mean(records, "mean_iteration_ms", "frames"),
        "aggregate_p50_frame_ms": float(np.percentile(aggregate_frame_values, 50) * 1000),
        "aggregate_p95_frame_ms": float(np.percentile(aggregate_frame_values, 95) * 1000),
        "aggregate_p99_frame_ms": float(np.percentile(aggregate_frame_values, 99) * 1000),
        "aggregate_max_frame_ms": float(np.max(aggregate_frame_values) * 1000),
        "aggregate_p50_iteration_ms": float(
            np.percentile(aggregate_iteration_values, 50) * 1000
        ),
        "aggregate_p95_iteration_ms": float(
            np.percentile(aggregate_iteration_values, 95) * 1000
        ),
        "aggregate_p99_iteration_ms": float(
            np.percentile(aggregate_iteration_values, 99) * 1000
        ),
        "aggregate_max_iteration_ms": float(np.max(aggregate_iteration_values) * 1000),
        "worst_file_p99_iteration_ms": float(worst_file_p99["p99_iteration_ms"]),
        "worst_file_p99_iteration_file_id": int(worst_file_p99["file_id"]),
        "audio_weighted_input_snr_db": weighted_mean(
            records, "input_snr_db", "evaluated_audio_s"
        ),
        "audio_weighted_enhanced_snr_db": weighted_mean(
            records, "enhanced_snr_db", "evaluated_audio_s"
        ),
        "audio_weighted_snr_delta_db": weighted_mean(
            records, "snr_delta_db", "evaluated_audio_s"
        ),
        "audio_weighted_input_si_sdr_db": weighted_mean(
            records, "input_si_sdr_db", "evaluated_audio_s"
        ),
        "audio_weighted_enhanced_si_sdr_db": weighted_mean(
            records, "enhanced_si_sdr_db", "evaluated_audio_s"
        ),
        "audio_weighted_si_sdr_delta_db": weighted_mean(
            records, "si_sdr_delta_db", "evaluated_audio_s"
        ),
        "aggregate_sustained_frame_loop_rtf": float(total_frame_loop_s / total_audio_s),
        "setup_amortized_frame_loop_rtf": float(
            (runtime_setup_s + total_frame_loop_s) / total_audio_s
        ),
        "persistent_runtime_open_rtf": float(runtime_open_s / total_audio_s),
        "persistent_end_to_end_rtf": float(total_wall_s / total_audio_s),
        "pre_run_reset": reset_evidence,
        "final_session_state": final_session_state,
        "records": records,
    }
    manifest_path = args.output_root / "run_manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print("PERSISTENT_SUBSET_RESULT " + json.dumps(manifest, sort_keys=True), flush=True)


if __name__ == "__main__":
    main()
