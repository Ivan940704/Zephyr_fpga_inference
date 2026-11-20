#!/usr/bin/env python3
"""Run a deterministic waveform through the live PYNQ-Z1 accelerator."""

from __future__ import annotations

import argparse
import json
import sys
import time
import wave
from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from software.audio_feature_bundle import (  # noqa: E402
    FFT_SIZE,
    HOP_SIZE,
    SAMPLE_RATE,
    load_feature_bundle,
    periodic_hann,
    read_pcm16,
    sha256_file,
    stft_centered,
)
from software.pynq.accelerator_profile import decode_profile_words  # noqa: E402

try:
    from .accelerator_inference import (
        PROFILE_DURATION_NAMES,
        PROFILE_POINTS,
        NativeOutputDequantizer,
        PynqAcceleratorRuntime,
        RuntimeParameters,
        dequantize_output,
    )
except ImportError:
    from accelerator_inference import (  # type: ignore
        PROFILE_DURATION_NAMES,
        PROFILE_POINTS,
        NativeOutputDequantizer,
        PynqAcceleratorRuntime,
        RuntimeParameters,
        dequantize_output,
    )


def ratio_or_none(numerator: float, denominator: float):
    """Return a finite ratio, or None when its measurement interval is empty."""
    if denominator <= 0:
        return None
    return float(numerator / denominator)


def istft_centered(spectrum: np.ndarray, output_samples: int) -> np.ndarray:
    spectrum = np.asarray(spectrum)
    window = periodic_hann(FFT_SIZE)
    padded_samples = (spectrum.shape[1] - 1) * HOP_SIZE + FFT_SIZE
    output = np.zeros(padded_samples, dtype=np.float64)
    weight = np.zeros(padded_samples, dtype=np.float64)
    for frame in range(spectrum.shape[1]):
        start = frame * HOP_SIZE
        values = np.fft.irfft(spectrum[:, frame], n=FFT_SIZE)
        output[start : start + FFT_SIZE] += values * window
        weight[start : start + FFT_SIZE] += window.astype(np.float64) ** 2
    valid = weight > 1e-12
    output[valid] /= weight[valid]
    start = FFT_SIZE // 2
    return output[start : start + output_samples].astype(np.float32)


class StreamingIstftAccumulator:
    """Incremental equivalent of ``istft_centered`` for per-frame profiling."""

    def __init__(self, frame_count: int) -> None:
        if frame_count <= 0:
            raise ValueError("frame_count must be positive")
        self.window = periodic_hann(FFT_SIZE)
        padded_samples = (frame_count - 1) * HOP_SIZE + FFT_SIZE
        self.output = np.zeros(padded_samples, dtype=np.float64)
        self.weight = np.zeros(padded_samples, dtype=np.float64)
        self.next_frame = 0

    def add(self, spectrum: np.ndarray) -> None:
        spectrum = np.asarray(spectrum)
        if spectrum.shape != (FFT_SIZE // 2 + 1,):
            raise ValueError("one ISTFT contribution must contain 257 bins")
        start = self.next_frame * HOP_SIZE
        values = np.fft.irfft(spectrum, n=FFT_SIZE)
        self.output[start : start + FFT_SIZE] += values * self.window
        self.weight[start : start + FFT_SIZE] += self.window.astype(np.float64) ** 2
        self.next_frame += 1

    def finish(self, output_samples: int) -> np.ndarray:
        valid = self.weight > 1e-12
        self.output[valid] /= self.weight[valid]
        start = FFT_SIZE // 2
        return self.output[start : start + output_samples].astype(np.float32)


def make_signal(samples: int, seed: int = 0x5A17) -> tuple[np.ndarray, np.ndarray]:
    time_axis = np.arange(samples, dtype=np.float64) / SAMPLE_RATE
    clean = (
        0.18 * np.sin(2 * np.pi * 220 * time_axis)
        + 0.11 * np.sin(2 * np.pi * 440 * time_axis + 0.3)
        + 0.06 * np.sin(2 * np.pi * 880 * time_axis + 0.8)
    )
    rng = np.random.default_rng(seed)
    noise = 0.055 * rng.standard_normal(samples) + 0.035 * np.sin(
        2 * np.pi * 3100 * time_axis
    )
    noisy = np.clip(clean + noise, -0.98, 0.98)
    return clean.astype(np.float32), noisy.astype(np.float32)


def snr_db(reference: np.ndarray, estimate: np.ndarray) -> float:
    reference = np.asarray(reference, dtype=np.float64)
    error = reference - np.asarray(estimate, dtype=np.float64)
    return float(10.0 * np.log10(np.sum(reference * reference) / max(np.sum(error * error), 1e-30)))


def write_pcm16(path: Path, values: np.ndarray) -> None:
    pcm = np.clip(np.rint(np.asarray(values) * 32767.0), -32768, 32767).astype("<i2")
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(pcm.tobytes())


def summarize_hardware_profiles(profiles: list[dict[str, object]]) -> dict[str, object]:
    """Aggregate frame snapshots without hiding their raw JSONL evidence."""

    if not profiles:
        return {"enabled": False}
    frame_cycles = np.asarray(
        [int(profile["frame_cycles"]) for profile in profiles], dtype=np.uint64
    )
    state_names = tuple(profiles[0]["state_cycles"])
    stage_names = tuple(profiles[0]["stage_load_cycles"])
    counter_names = tuple(profiles[0]["counters"])
    state_totals = {
        name: sum(int(profile["state_cycles"][name]) for profile in profiles)
        for name in state_names
    }
    stage_load_totals = {
        name: sum(int(profile["stage_load_cycles"][name]) for profile in profiles)
        for name in stage_names
    }
    stage_compute_totals = {
        name: sum(int(profile["stage_compute_cycles"][name]) for profile in profiles)
        for name in stage_names
    }
    stage_stall_totals = {
        name: sum(int(profile["stage_stall_cycles"][name]) for profile in profiles)
        for name in stage_names
    }
    counter_totals = {
        name: sum(int(profile["counters"][name]) for profile in profiles)
        for name in counter_names
    }
    dense_equivalent = counter_totals["dense_equivalent_requests"]
    actual_requests = counter_totals["weight_requests"]
    dense_equivalent_macs = dense_equivalent * 16
    byte_total = (
        counter_totals["sparse_stage_actual_bytes"]
        + counter_totals["sparse_stage_saved_bytes"]
    )
    clock_hz = int(profiles[0]["clock_hz"])
    latency_ms = frame_cycles.astype(np.float64) * 1000.0 / clock_hz
    return {
        "enabled": True,
        "schema": profiles[0]["schema"],
        "clock_hz": clock_hz,
        "frames": len(profiles),
        "raw_evidence": "hardware_profile.jsonl",
        "cycle_conservation_all_frames": all(
            int(profile["frame_cycles"])
            == sum(int(value) for value in profile["state_cycles"].values())
            for profile in profiles
        ),
        "pl_latency_ms": {
            "mean": float(np.mean(latency_ms)),
            "p50": float(np.percentile(latency_ms, 50)),
            "p95": float(np.percentile(latency_ms, 95)),
            "p99": float(np.percentile(latency_ms, 99)),
            "max": float(np.max(latency_ms)),
        },
        "state_cycle_totals": state_totals,
        "stage_load_cycle_totals": stage_load_totals,
        "stage_compute_cycle_totals": stage_compute_totals,
        "stage_stall_cycle_totals": stage_stall_totals,
        "counter_totals": counter_totals,
        "request_sparsity": (
            float((dense_equivalent - min(actual_requests, dense_equivalent)) /
                  dense_equivalent)
            if dense_equivalent
            else None
        ),
        "mac_skip_fraction": (
            float(counter_totals["skipped_macs"] / dense_equivalent_macs)
            if dense_equivalent_macs
            else None
        ),
        "parameter_byte_savings_fraction": (
            float(counter_totals["sparse_stage_saved_bytes"] / byte_total)
            if byte_total
            else None
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--parameter-image", type=Path, required=True)
    parser.add_argument("--runtime-parameters", type=Path, required=True)
    parser.add_argument("--parameter-sha256", required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--samples", type=int, default=4096)
    parser.add_argument("--input-wav", type=Path)
    parser.add_argument("--clean-reference", type=Path)
    parser.add_argument(
        "--precomputed-features",
        type=Path,
        help="host-generated feature bundle; requires --input-wav",
    )
    parser.add_argument("--max-frames", type=int, default=0)
    parser.add_argument("--progress-every", type=int, default=1)
    parser.add_argument(
        "--compact",
        action="store_true",
        help="save compact timing metadata instead of all hardware boundary arrays",
    )
    parser.add_argument("--mailbox-io", choices=("scalar", "bulk"), default="scalar")
    parser.add_argument(
        "--layernorm-placement",
        choices=("pl", "mailbox"),
        default="pl",
        help="PL uses the 512-byte signed-Q12 magnitude ABI; mailbox retains the debug ABI",
    )
    parser.add_argument("--layernorm", choices=("numpy", "native"), default="numpy")
    parser.add_argument("--native-library", type=Path)
    parser.add_argument(
        "--dma-control",
        choices=("auto", "python", "native"),
        default="python",
        help="python is the measured production default; auto/native enable the experimental C poll loop",
    )
    parser.add_argument(
        "--output-dequantization",
        choices=("auto", "numpy", "native"),
        default="auto",
        help="auto uses the native kernel when --native-library is available",
    )
    parser.add_argument(
        "--profile",
        action="store_true",
        help="record monotonic T00-T16 timestamps and execute incremental ISTFT",
    )
    parser.add_argument(
        "--hardware-profile",
        action="store_true",
        help="require image v2 and save coherent per-frame PL cycle/sparsity counters",
    )
    parser.add_argument(
        "--hardware-profile-every",
        type=int,
        default=1,
        help="capture one hardware counter snapshot every N frames (and the final frame)",
    )
    parser.add_argument(
        "--per-frame-diagnostics",
        action="store_true",
        help=(
            "poll frame retirement and fault registers after every frame; "
            "the production fast path validates them once at the end"
        ),
    )
    parser.add_argument(
        "--optimized-output-cache",
        action="store_true",
        help="skip the per-frame S2MM destination zero/flush after explicit A/B validation",
    )
    parser.add_argument(
        "--no-diagnostics",
        action="store_true",
        help="remove boundary sparsity and absmax scans from the benchmark hot path",
    )
    parser.add_argument("--dense", action="store_true")
    parser.add_argument(
        "--poll-mode",
        choices=("sleep", "busy"),
        default="sleep",
        help="sleep polls at 50 us; busy performs no scheduler sleep",
    )
    parser.add_argument(
        "--no-overlap-host-packing",
        action="store_true",
        help="disable A/B DMA buffers and packing frame N+1 while frame N runs",
    )
    parser.add_argument(
        "--register-io",
        choices=("bulk", "scalar"),
        default="bulk",
        help="use the direct MMIO.array register map or PYNQ scalar calls",
    )
    parser.add_argument(
        "--conservative-dma-submit",
        action="store_true",
        help="restore per-transfer status/IRQ checks and separate input-DMA waits",
    )
    args = parser.parse_args()
    if args.clean_reference is not None and args.input_wav is None:
        parser.error("--clean-reference requires --input-wav")
    if args.precomputed_features is not None and args.input_wav is None:
        parser.error("--precomputed-features requires --input-wav")
    if args.progress_every < 0:
        parser.error("--progress-every must be non-negative")
    if args.hardware_profile_every <= 0:
        parser.error("--hardware-profile-every must be positive")
    if (
        args.layernorm_placement == "mailbox"
        and args.layernorm == "native"
        and args.native_library is None
    ):
        parser.error("--layernorm native requires --native-library")
    if args.output_dequantization == "native" and args.native_library is None:
        parser.error("--output-dequantization native requires --native-library")
    if args.dma_control == "native" and args.native_library is None:
        parser.error("--dma-control native requires --native-library")
    native_dma_incompatible = (
        args.layernorm_placement != "pl"
        or args.profile
        or args.hardware_profile
        or args.per_frame_diagnostics
        or args.conservative_dma_submit
        or args.register_io != "bulk"
    )
    if args.dma_control == "native" and native_dma_incompatible:
        parser.error(
            "--dma-control native requires the PL frontend, bulk register I/O, "
            "fast submit, and profiling/diagnostics disabled"
        )

    input_sha256 = None
    clean_sha256 = None
    if args.input_wav is None:
        clean, noisy = make_signal(args.samples)
        source_kind = "deterministic_synthetic"
        source_name = None
    else:
        noisy = read_pcm16(args.input_wav)
        clean = read_pcm16(args.clean_reference) if args.clean_reference is not None else None
        if clean is not None and clean.shape != noisy.shape:
            parser.error("--clean-reference must contain exactly the same number of samples")
        source_kind = "external_wav"
        source_name = args.input_wav.name
        input_sha256 = sha256_file(args.input_wav)
        clean_sha256 = sha256_file(args.clean_reference) if args.clean_reference is not None else None

    if noisy.size < FFT_SIZE:
        parser.error("--samples must be at least 512")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    runtime_parameters = RuntimeParameters.load(args.runtime_parameters)
    precomputed_magnitude = None
    prepacked_magnitude_q12 = None
    prepacked_spectrum_q = None
    feature_bundle = None
    end_to_end_started = time.monotonic()
    frontend_started = time.monotonic()
    if args.precomputed_features is None:
        noisy_stft = stft_centered(noisy)
        frontend_placement = "pynq_cpu"
    else:
        feature_bundle = load_feature_bundle(
            args.precomputed_features,
            source_wav=args.input_wav,
            source_samples=int(noisy.size),
        )
        noisy_stft = feature_bundle.spectrum
        precomputed_magnitude = feature_bundle.magnitude
        prepacked_magnitude_q12 = feature_bundle.magnitude_q12
        prepacked_spectrum_q = feature_bundle.spectrum_q
        frontend_placement = "computer_precomputed"
        source_kind = "external_wav_precomputed_features"
    frontend_elapsed_s = time.monotonic() - frontend_started
    frame_count = noisy_stft.shape[1]
    if args.max_frames:
        frame_count = min(frame_count, args.max_frames)
    output_samples = min(noisy.size, max(0, (frame_count - 1) * HOP_SIZE))
    hardware_bins_by_frame = np.empty((frame_count, 256), dtype=np.complex64)
    use_native_output = args.output_dequantization == "native" or (
        args.output_dequantization == "auto" and args.native_library is not None
    )
    output_dequantizer = (
        NativeOutputDequantizer(args.native_library) if use_native_output else None
    )
    defer_output_dequantization = output_dequantizer is not None and not args.profile
    use_native_dma = (
        args.dma_control != "python"
        and args.native_library is not None
        and not native_dma_incompatible
    )
    accumulators = None if args.compact else np.empty((frame_count, 256, 2), dtype=np.int32)
    deferred_accumulators = (
        accumulators
        if defer_output_dequantization and accumulators is not None
        else (
            np.empty((frame_count, 256, 2), dtype=np.int32)
            if defer_output_dequantization
            else None
        )
    )
    save_mailbox_boundaries = not args.compact and args.layernorm_placement == "mailbox"
    fb_projections = (
        np.empty((frame_count, 64), dtype=np.int8) if save_mailbox_boundaries else None
    )
    sb_payloads = (
        np.empty((frame_count, 782), dtype=np.int8) if save_mailbox_boundaries else None
    )
    spectra_q = None if args.compact else np.empty((frame_count, 512), dtype=np.int8)
    elapsed = []
    iteration_elapsed = []
    mailbox = []
    frame_ids = []
    profile_rows = []
    hardware_profiles = []
    hardware_profile_words = []
    streaming_istft = (
        StreamingIstftAccumulator(frame_count) if args.profile else None
    )
    accumulator_absmax = 0
    zero_counts = {"spectrum": 0, "accumulator": 0}
    element_counts = {"spectrum": 0, "accumulator": 0}
    if args.layernorm_placement == "mailbox":
        zero_counts.update({"fb_projection": 0, "subband_payload": 0})
        element_counts.update({"fb_projection": 0, "subband_payload": 0})

    inference_started = time.monotonic()
    runtime_setup_started = time.monotonic()
    with PynqAcceleratorRuntime(
        args.parameter_image,
        runtime_parameters,
        expected_parameter_sha256=args.parameter_sha256,
        mailbox_io_mode=args.mailbox_io,
        frontend_mode=args.layernorm_placement,
        layernorm_mode=args.layernorm,
        native_layernorm_library=args.native_library,
        native_dma_library=args.native_library if use_native_dma else None,
        profiling=args.profile,
        hardware_profiling=args.hardware_profile,
        per_frame_diagnostics=args.per_frame_diagnostics,
        poll_interval_s=0.00005 if args.poll_mode == "sleep" else 0.0,
        conservative_output_cache=not args.optimized_output_cache,
        register_io_mode=args.register_io,
        fast_dma_submit=not args.conservative_dma_submit,
    ) as accelerator:
        runtime_setup_s = time.monotonic() - runtime_setup_started
        loaded_image_version = accelerator.image_version

        def frame_inputs(frame_index):
            frame_spectrum = noisy_stft[:256, frame_index]
            frame_magnitude = (
                precomputed_magnitude[:, frame_index]
                if precomputed_magnitude is not None
                else np.sqrt(np.abs(frame_spectrum)).astype(np.float32)
            )
            return frame_magnitude, frame_spectrum

        overlap_host_packing = not args.no_overlap_host_packing and frame_count > 1
        use_prepacked_dma = (
            args.layernorm_placement == "pl"
            and prepacked_magnitude_q12 is not None
            and prepacked_spectrum_q is not None
        )

        def prepare_dma_frame(frame_index, frame_id=None):
            if use_prepacked_dma:
                return accelerator.prepare_packed_frame(
                    prepacked_magnitude_q12[frame_index],
                    prepacked_spectrum_q[frame_index],
                    frame_id=frame_id,
                )
            frame_magnitude, frame_spectrum = frame_inputs(frame_index)
            return accelerator.prepare_frame(
                frame_magnitude,
                frame_spectrum,
                frame_id=frame_id,
            )

        magnitude, spectrum = frame_inputs(0)
        prepared_frame = (
            prepare_dma_frame(0)
            if overlap_host_packing
            else None
        )
        frame_loop_started = time.monotonic()
        for frame in range(frame_count):
            iteration_started = time.monotonic()
            next_inputs = frame_inputs(frame + 1) if frame + 1 < frame_count else None
            next_prepared = [None]
            prepare_next = None
            if overlap_host_packing and next_inputs is not None:
                expected_next_frame_id = (prepared_frame.frame_id + 1) & 0xFFFF

                def prepare_next(
                    next_frame_index=frame + 1,
                    next_frame_id=expected_next_frame_id,
                ):
                    next_prepared[0] = prepare_dma_frame(
                        next_frame_index, frame_id=next_frame_id
                    )

            collect_hardware_profile = args.hardware_profile and (
                frame % args.hardware_profile_every == 0 or frame + 1 == frame_count
            )
            result = accelerator.run_frame(
                magnitude,
                spectrum,
                clear_state=(frame == 0),
                sparse=not args.dense,
                prepared_frame=prepared_frame,
                during_execution=prepare_next,
                collect_hardware_profile=collect_hardware_profile,
            )
            if deferred_accumulators is not None:
                deferred_accumulators[frame] = result.output_accumulators
                hardware_frame = None
            elif output_dequantizer is None:
                hardware_bins_by_frame[frame] = dequantize_output(
                    result.output_accumulators
                )
            else:
                output_dequantizer.dequantize(
                    result.output_accumulators,
                    output=hardware_bins_by_frame[frame],
                )
            if deferred_accumulators is None:
                hardware_frame = hardware_bins_by_frame[frame]
            if accumulators is not None and accumulators is not deferred_accumulators:
                accumulators[frame] = result.output_accumulators
                if fb_projections is not None and result.fb_projection_q is not None:
                    fb_projections[frame] = result.fb_projection_q
                if sb_payloads is not None and result.sb_payload_q is not None:
                    sb_payloads[frame] = result.sb_payload_q
                spectra_q[frame] = result.spectrum_q
            elapsed.append(result.elapsed_s)
            mailbox.append(result.mailbox_service_s)
            frame_ids.append(result.frame_id)
            if args.hardware_profile:
                if collect_hardware_profile and result.hardware_profile_words is None:
                    raise RuntimeError("hardware profiling run did not return raw words")
                if result.hardware_profile_words is not None:
                    hardware_profile_words.append(result.hardware_profile_words)
            frame_absmax = None
            if not args.no_diagnostics:
                arrays = {
                    "spectrum": result.spectrum_q,
                    "accumulator": result.output_accumulators,
                }
                if result.fb_projection_q is not None:
                    arrays["fb_projection"] = result.fb_projection_q
                if result.sb_payload_q is not None:
                    arrays["subband_payload"] = result.sb_payload_q
                for name, values in arrays.items():
                    zero_counts[name] += int(np.count_nonzero(values == 0))
                    element_counts[name] += int(values.size)
                frame_absmax = int(
                    np.max(np.abs(result.output_accumulators.astype(np.int64)))
                )
                accumulator_absmax = max(accumulator_absmax, frame_absmax)
            if args.profile:
                if result.profile_timestamps_ns is None or len(result.profile_timestamps_ns) != 15:
                    raise RuntimeError("profiling run did not return T00-T14")
                t15 = time.monotonic_ns()
                full_spectrum = noisy_stft[:, frame].copy()
                full_spectrum[:256] = hardware_frame
                streaming_istft.add(full_spectrum)
                t16 = time.monotonic_ns()
                profile_rows.append((*result.profile_timestamps_ns, t15, t16))
            if args.progress_every and (
                frame == 0 or (frame + 1) % args.progress_every == 0 or frame + 1 == frame_count
            ):
                print(
                    f"FRAME frame={frame} hardware_id={result.frame_id} "
                    f"elapsed_ms={result.elapsed_s * 1000:.3f} "
                    f"mailbox_ms={result.mailbox_service_s * 1000:.3f} "
                    f"absmax={frame_absmax if frame_absmax is not None else 'disabled'}",
                    flush=True,
                )
            if next_inputs is not None:
                magnitude, spectrum = next_inputs
                prepared_frame = next_prepared[0] if overlap_host_packing else None
            iteration_elapsed.append(time.monotonic() - iteration_started)
        final_hardware_state = accelerator.diagnostic_snapshot()
        if final_hardware_state["control"]["control_error"] & 0x100:
            raise RuntimeError("final control plane has a sticky error")
        if final_hardware_state["control"]["first_fault"] & (1 << 24):
            raise RuntimeError("final accelerator state has a latched fault")
        if (
            final_hardware_state["control"]["frame_id"] & 0xFFFF
        ) != accelerator.expected_frame_id:
            raise RuntimeError(
                "final accelerator frame ID does not match the software sequence: "
                f"hardware={final_hardware_state['control']['frame_id'] & 0xFFFF} "
                f"software={accelerator.expected_frame_id}"
            )
        for name, state in final_hardware_state["dma"].items():
            if state["errors"] or not state["idle"]:
                raise RuntimeError(f"final DMA state is not idle/error-free: {name}={state}")
        frame_loop_s = time.monotonic() - frame_loop_started
        runtime_close_started = time.monotonic()
    runtime_close_s = time.monotonic() - runtime_close_started
    inference_loop_s = time.monotonic() - inference_started
    hardware_profile_decode_started = time.monotonic()
    if hardware_profile_words:
        hardware_profiles = [
            decode_profile_words(list(words)) for words in hardware_profile_words
        ]
    hardware_profile_decode_s = time.monotonic() - hardware_profile_decode_started
    output_dequantization_started = time.monotonic()
    if deferred_accumulators is not None:
        output_dequantizer.dequantize_batch(
            deferred_accumulators, output=hardware_bins_by_frame
        )
    output_dequantization_s = time.monotonic() - output_dequantization_started

    if streaming_istft is not None:
        enhanced = streaming_istft.finish(output_samples)
    else:
        enhanced_stft = noisy_stft[:, :frame_count].copy()
        enhanced_stft[:256] = hardware_bins_by_frame.T
        enhanced = istft_centered(enhanced_stft, output_samples)
    clean_eval = clean[:output_samples] if clean is not None else None
    noisy_eval = noisy[:output_samples]
    evaluated_audio_s = output_samples / SAMPLE_RATE
    elapsed_array = np.asarray(elapsed, dtype=np.float64)
    iteration_elapsed_array = np.asarray(iteration_elapsed, dtype=np.float64)
    mailbox_array = np.asarray(mailbox, dtype=np.float64)
    profile_array = np.asarray(profile_rows, dtype=np.uint64).reshape((-1, len(PROFILE_POINTS)))
    end_to_end_s = time.monotonic() - end_to_end_started
    metrics = {
        "status": "PASS",
        "board": "PYNQ-Z1",
        "image_version": f"0x{loaded_image_version:08x}",
        "frames": frame_count,
        "frame_ids": frame_ids,
        "mailbox_io": args.mailbox_io,
        "layernorm_placement": args.layernorm_placement,
        "layernorm": args.layernorm,
        "output_dequantization": "native" if use_native_output else "numpy",
        "output_dequantization_schedule": (
            "deferred_batch" if defer_output_dequantization else "per_frame"
        ),
        "dma_control": "native" if use_native_dma else "python",
        "profiling": args.profile,
        "hardware_profiling": args.hardware_profile,
        "hardware_profile_sample_every_frames": args.hardware_profile_every,
        "hardware_profile_samples": len(hardware_profiles),
        "poll_mode": args.poll_mode,
        "host_packet_dma_double_buffered": not args.no_overlap_host_packing,
        "host_dma_packets_prepacked": bool(use_prepacked_dma),
        "register_io": args.register_io,
        "fast_dma_submit": not args.conservative_dma_submit,
        "conservative_output_cache": not args.optimized_output_cache,
        "diagnostics": not args.no_diagnostics,
        "sparse": not args.dense,
        "source_kind": source_kind,
        "source_name": source_name,
        "input_sha256": input_sha256,
        "clean_reference_sha256": clean_sha256,
        "frontend": {
            "placement": frontend_placement,
            "board_frontend_load_or_compute_s": float(frontend_elapsed_s),
            "bundle_metadata_sha256": (
                feature_bundle.metadata_sha256 if feature_bundle is not None else None
            ),
            "host_compute_elapsed_s": (
                feature_bundle.metadata.get("host_compute_elapsed_s")
                if feature_bundle is not None
                else None
            ),
        },
        "input_samples": int(noisy.size),
        "evaluated_samples": int(output_samples),
        "input_audio_s": float(noisy.size / SAMPLE_RATE),
        "evaluated_audio_s": float(evaluated_audio_s),
        "mean_frame_ms": float(np.mean(elapsed_array) * 1000),
        "p50_frame_ms": float(np.percentile(elapsed_array, 50) * 1000),
        "p95_frame_ms": float(np.percentile(elapsed_array, 95) * 1000),
        "p99_frame_ms": float(np.percentile(elapsed_array, 99) * 1000),
        "max_frame_ms": float(np.max(elapsed_array) * 1000),
        "mean_iteration_ms": float(np.mean(iteration_elapsed_array) * 1000),
        "p50_iteration_ms": float(np.percentile(iteration_elapsed_array, 50) * 1000),
        "p95_iteration_ms": float(np.percentile(iteration_elapsed_array, 95) * 1000),
        "p99_iteration_ms": float(np.percentile(iteration_elapsed_array, 99) * 1000),
        "max_iteration_ms": float(np.max(iteration_elapsed_array) * 1000),
        "mean_mailbox_ms": float(np.mean(mailbox_array) * 1000),
        "p95_mailbox_ms": float(np.percentile(mailbox_array, 95) * 1000),
        "p99_mailbox_ms": float(np.percentile(mailbox_array, 99) * 1000),
        "inference_loop_s": float(inference_loop_s),
        "runtime_setup_s": float(runtime_setup_s),
        "frame_loop_s": float(frame_loop_s),
        "runtime_close_s": float(runtime_close_s),
        "hardware_profile_decode_s": float(hardware_profile_decode_s),
        "output_dequantization_s": float(output_dequantization_s),
        "end_to_end_s": float(end_to_end_s),
        "frame_compute_rtf": ratio_or_none(np.sum(elapsed_array), evaluated_audio_s),
        "board_loop_rtf": ratio_or_none(inference_loop_s, evaluated_audio_s),
        "sustained_frame_loop_rtf": ratio_or_none(frame_loop_s, evaluated_audio_s),
        "end_to_end_rtf": ratio_or_none(end_to_end_s, evaluated_audio_s),
        "throughput_frames_per_s": float(frame_count / inference_loop_s),
        "input_snr_db": snr_db(clean_eval, noisy_eval) if output_samples and clean_eval is not None else None,
        "enhanced_snr_db": snr_db(clean_eval, enhanced) if output_samples and clean_eval is not None else None,
        "output_accumulator_absmax": (
            int(accumulator_absmax) if not args.no_diagnostics else None
        ),
        "output_accumulator_nonzero": (
            int(element_counts["accumulator"] - zero_counts["accumulator"])
            if not args.no_diagnostics
            else None
        ),
        "boundary_zero_fraction": (
            {
                name: float(zero_counts[name] / element_counts[name])
                for name in zero_counts
            }
            if not args.no_diagnostics
            else None
        ),
        "final_hardware_state": final_hardware_state,
    }
    metrics["hardware_profile"] = summarize_hardware_profiles(hardware_profiles)
    if args.profile:
        durations_ms = np.diff(profile_array.astype(np.int64), axis=1) / 1_000_000.0
        total_ns = profile_array[:, -1].astype(np.int64) - profile_array[:, 0].astype(np.int64)
        reconstructed_ns = np.sum(np.diff(profile_array.astype(np.int64), axis=1), axis=1)
        metrics["profile"] = {
            "clock": "time.monotonic_ns",
            "points": PROFILE_POINTS,
            "bucket_statistics_ms": {
                name: {
                    "mean": float(np.mean(values)),
                    "standard_deviation": float(np.std(values)),
                    "p50": float(np.percentile(values, 50)),
                    "p95": float(np.percentile(values, 95)),
                    "p99": float(np.percentile(values, 99)),
                    "max": float(np.max(values)),
                }
                for name, values in zip(PROFILE_DURATION_NAMES, durations_ms.T)
            },
            "maximum_reconstruction_error_ns": int(
                np.max(np.abs(total_ns - reconstructed_ns))
            ),
        }
    else:
        metrics["profile"] = {"clock": "time.monotonic_ns", "enabled": False}
    if output_samples and clean_eval is not None:
        metrics["snr_delta_db"] = metrics["enhanced_snr_db"] - metrics["input_snr_db"]
    (args.output_dir / "metrics.json").write_text(
        json.dumps(metrics, indent=2) + "\n", encoding="utf-8"
    )
    if hardware_profiles:
        (args.output_dir / "hardware_profile.jsonl").write_text(
            "".join(
                json.dumps(profile, sort_keys=True) + "\n"
                for profile in hardware_profiles
            ),
            encoding="utf-8",
        )
    if args.compact:
        compact_arrays = {
            "elapsed_s": elapsed_array,
            "iteration_elapsed_s": iteration_elapsed_array,
            "mailbox_s": mailbox_array,
            "frame_ids": np.asarray(frame_ids, dtype=np.uint16),
        }
        if args.profile:
            compact_arrays["profile_timestamps_ns"] = profile_array
        if hardware_profiles:
            compact_arrays["hardware_frame_cycles"] = np.asarray(
                [profile["frame_cycles"] for profile in hardware_profiles],
                dtype=np.uint64,
            )
        np.savez_compressed(args.output_dir / "result.npz", **compact_arrays)
    else:
        result_arrays = {
            "noisy": noisy,
            "noisy_stft": noisy_stft,
            "hardware_bins": hardware_bins_by_frame.T,
            "accumulators": accumulators,
            "spectra_q": spectra_q,
            "enhanced": enhanced,
            "elapsed_s": elapsed_array,
            "iteration_elapsed_s": iteration_elapsed_array,
            "mailbox_s": mailbox_array,
        }
        if fb_projections is not None:
            result_arrays["fb_projections"] = fb_projections
        if sb_payloads is not None:
            result_arrays["sb_payloads"] = sb_payloads
        if args.profile:
            result_arrays["profile_timestamps_ns"] = profile_array
        if hardware_profiles:
            result_arrays["hardware_frame_cycles"] = np.asarray(
                [profile["frame_cycles"] for profile in hardware_profiles],
                dtype=np.uint64,
            )
        if clean is not None:
            result_arrays["clean"] = clean
        np.savez(args.output_dir / "result.npz", **result_arrays)
    if clean_eval is not None:
        write_pcm16(args.output_dir / "clean.wav", clean_eval)
    write_pcm16(args.output_dir / "noisy.wav", noisy_eval)
    write_pcm16(args.output_dir / "enhanced.wav", enhanced)
    print("BOARD_INFERENCE_RESULT " + json.dumps(metrics, sort_keys=True), flush=True)


if __name__ == "__main__":
    main()
