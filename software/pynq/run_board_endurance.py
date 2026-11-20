#!/usr/bin/env python3
"""One-hour/450k-frame PYNQ endurance and coordinated reset recovery gate."""

from __future__ import annotations

import argparse
import json
import platform
import sys
import time
from pathlib import Path

import numpy as np

try:
    from .accelerator_bringup import (
        AcceleratorBringupDriver,
        fresh_parameter_epoch_reset,
    )
    from .accelerator_inference import PynqAcceleratorRuntime, RuntimeParameters
    from .parameter_bram_bringup import load_arm_dsb_sy
    from .run_accelerator_inference import make_signal, stft_centered
except ImportError:
    from accelerator_bringup import (  # type: ignore
        AcceleratorBringupDriver,
        fresh_parameter_epoch_reset,
    )
    from accelerator_inference import PynqAcceleratorRuntime, RuntimeParameters  # type: ignore
    from parameter_bram_bringup import load_arm_dsb_sy  # type: ignore
    from run_accelerator_inference import make_signal, stft_centered  # type: ignore


def percentile_summary(values: list[float]) -> dict[str, float]:
    array = np.asarray(values, dtype=np.float64) * 1000.0
    return {
        "mean_ms": float(np.mean(array)),
        "standard_deviation_ms": float(np.std(array)),
        "p50_ms": float(np.percentile(array, 50)),
        "p95_ms": float(np.percentile(array, 95)),
        "p99_ms": float(np.percentile(array, 99)),
        "max_ms": float(np.max(array)),
    }


def write_checkpoint(path: Path, evidence: dict[str, object]) -> None:
    temporary = path.with_suffix(".tmp")
    temporary.write_text(
        json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    temporary.replace(path)


def validate_hardware_snapshot(
    snapshot: dict[str, object], *, context: str
) -> dict[str, object]:
    """Fail closed unless control faults are clear and every DMA is idle."""

    try:
        control = snapshot["control"]
        dma = snapshot["dma"]
        assert isinstance(control, dict)
        assert isinstance(dma, dict)
        control_error = int(control["control_error"])
        first_fault = int(control["first_fault"])
    except (AssertionError, KeyError, TypeError, ValueError) as exc:
        raise RuntimeError(f"{context}: malformed hardware snapshot") from exc

    failures: dict[str, object] = {}
    if control_error & 0x100:
        failures["control_error"] = control_error
    if first_fault & (1 << 24):
        failures["first_fault"] = first_fault

    channel_status: dict[str, object] = {}
    for name, raw_channel in dma.items():
        if not isinstance(raw_channel, dict):
            raise RuntimeError(f"{context}: malformed DMA snapshot for {name}")
        try:
            idle = bool(raw_channel["idle"])
            errors = int(raw_channel["errors"])
            status = int(raw_channel["status"])
        except (KeyError, TypeError, ValueError) as exc:
            raise RuntimeError(
                f"{context}: malformed DMA snapshot for {name}"
            ) from exc
        channel_status[str(name)] = {
            "idle": idle,
            "errors": errors,
            "status": status,
        }
        if errors or not idle:
            failures[f"dma_{name}"] = channel_status[str(name)]

    if not channel_status:
        failures["dma"] = "no channels reported"
    if failures:
        raise RuntimeError(f"{context}: hardware completion gate failed: {failures!r}")
    return {
        "status": "PASS",
        "control_faults_zero": True,
        "all_dma_idle": True,
        "dma_errors_zero": True,
        "dma": channel_status,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--parameter-image", type=Path, required=True)
    parser.add_argument("--runtime-parameters", type=Path, required=True)
    parser.add_argument("--parameter-sha256", required=True)
    parser.add_argument("--native-library", type=Path, required=True)
    parser.add_argument("--barrier-library", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--minimum-duration-s", type=float, default=3600.0)
    parser.add_argument("--minimum-frames", type=int, default=450_000)
    parser.add_argument("--checkpoint-every", type=int, default=1000)
    parser.add_argument("--mailbox-io", choices=("scalar", "bulk"), default="bulk")
    parser.add_argument("--layernorm-placement", choices=("pl", "mailbox"), default="pl")
    parser.add_argument("--layernorm", choices=("numpy", "native"), default="native")
    parser.add_argument("--poll-mode", choices=("sleep", "busy"), default="sleep")
    parser.add_argument("--dense", action="store_true")
    parser.add_argument("--conservative-output-cache", action="store_true")
    parser.add_argument("--hardware-profile", action="store_true")
    args = parser.parse_args()
    if args.minimum_duration_s <= 0 or args.minimum_frames <= 0:
        parser.error("duration and frame thresholds must be positive")
    if args.checkpoint_every <= 0:
        parser.error("--checkpoint-every must be positive")
    for path in (
        args.parameter_image,
        args.runtime_parameters,
        args.native_library,
        args.barrier_library,
    ):
        if not path.is_file():
            parser.error(f"required file does not exist: {path}")
    if args.output.exists():
        parser.error("refusing to overwrite an existing endurance report")
    args.output.parent.mkdir(parents=True, exist_ok=True)

    params = RuntimeParameters.load(args.runtime_parameters)
    _, signal = make_signal(4096)
    spectrum_frames = stft_centered(signal)[:256].T
    magnitude_frames = np.sqrt(np.abs(spectrum_frames)).astype(np.float32)
    frame_elapsed: list[float] = []
    mailbox_elapsed: list[float] = []
    started = time.monotonic()
    evidence: dict[str, object] = {
        "schema": "zephyr.board-endurance.v1",
        "status": "RUNNING",
        "host": {"platform": platform.platform(), "python": sys.version},
        "requirements": {
            "minimum_duration_s": args.minimum_duration_s,
            "minimum_frames": args.minimum_frames,
            "stop_condition": "both thresholds reached",
        },
        "configuration": {
            "mailbox_io": args.mailbox_io,
            "layernorm_placement": args.layernorm_placement,
            "layernorm": args.layernorm,
            "poll_mode": args.poll_mode,
            "sparse": not args.dense,
            "conservative_output_cache": args.conservative_output_cache,
            "hardware_profile": args.hardware_profile,
        },
        "completed_frames": 0,
        "frame_id_discontinuities": 0,
    }
    barrier = load_arm_dsb_sy(args.barrier_library)
    pre_run_reset = fresh_parameter_epoch_reset(barrier=barrier)
    previous_frame_id = None
    final_state = None
    with PynqAcceleratorRuntime(
        args.parameter_image,
        params,
        expected_parameter_sha256=args.parameter_sha256.lower(),
        mailbox_io_mode=args.mailbox_io,
        frontend_mode=args.layernorm_placement,
        layernorm_mode=args.layernorm,
        native_layernorm_library=args.native_library,
        poll_interval_s=0.00005 if args.poll_mode == "sleep" else 0.0,
        hardware_profiling=args.hardware_profile,
        conservative_output_cache=args.conservative_output_cache,
    ) as runtime:
        frame = 0
        while True:
            source_index = frame % spectrum_frames.shape[0]
            result = runtime.run_frame(
                magnitude_frames[source_index],
                spectrum_frames[source_index],
                clear_state=(frame == 0),
                sparse=not args.dense,
            )
            if previous_frame_id is not None and result.frame_id != (
                (previous_frame_id + 1) & 0xFFFF
            ):
                evidence["frame_id_discontinuities"] += 1
                raise RuntimeError(
                    f"frame ID discontinuity {previous_frame_id}->{result.frame_id}"
                )
            previous_frame_id = result.frame_id
            frame_elapsed.append(result.elapsed_s)
            mailbox_elapsed.append(result.mailbox_service_s)
            frame += 1
            elapsed = time.monotonic() - started
            if frame % args.checkpoint_every == 0:
                evidence.update(
                    {
                        "completed_frames": frame,
                        "elapsed_s": elapsed,
                        "last_frame_id": result.frame_id,
                        "frame_latency": percentile_summary(frame_elapsed),
                        "mailbox_latency": percentile_summary(mailbox_elapsed),
                        "updated_unix_s": time.time(),
                    }
                )
                write_checkpoint(args.output, evidence)
                print(
                    f"ENDURANCE_PROGRESS frames={frame} elapsed_s={elapsed:.3f} "
                    f"frame_id={result.frame_id}",
                    flush=True,
                )
            if frame >= args.minimum_frames and elapsed >= args.minimum_duration_s:
                break
        final_state = runtime.diagnostic_snapshot()
        final_hardware_gate = validate_hardware_snapshot(
            final_state, context="endurance final state"
        )

    recovery_driver = AcceleratorBringupDriver.from_pynq(barrier=barrier)
    reset_evidence = recovery_driver.safe_soft_reset(timeout_s=2.0)
    with PynqAcceleratorRuntime(
        args.parameter_image,
        params,
        expected_parameter_sha256=args.parameter_sha256.lower(),
        mailbox_io_mode=args.mailbox_io,
        frontend_mode=args.layernorm_placement,
        layernorm_mode=args.layernorm,
        native_layernorm_library=args.native_library,
        poll_interval_s=0.00005 if args.poll_mode == "sleep" else 0.0,
        conservative_output_cache=args.conservative_output_cache,
    ) as runtime:
        recovered = runtime.run_frame(
            magnitude_frames[0], spectrum_frames[0], clear_state=True,
            sparse=not args.dense,
        )
        recovery_final_state = runtime.diagnostic_snapshot()
        recovery_hardware_gate = validate_hardware_snapshot(
            recovery_final_state, context="post-reset recovery state"
        )

    elapsed = time.monotonic() - started
    evidence.update(
        {
            "status": "PASS",
            "completed_frames": len(frame_elapsed),
            "elapsed_s": elapsed,
            "last_frame_id": previous_frame_id,
            "frame_latency": percentile_summary(frame_elapsed),
            "mailbox_latency": percentile_summary(mailbox_elapsed),
            "final_hardware_state": final_state,
            "final_hardware_gate": final_hardware_gate,
            "pre_run_reset": pre_run_reset,
            "soft_reset_recovery": {
                "epoch_before": reset_evidence["epoch_before"],
                "epoch_after": reset_evidence["epoch_after"],
                "post_reset_frame_id": recovered.frame_id,
                "post_reset_frame_elapsed_s": recovered.elapsed_s,
                "final_hardware_state": recovery_final_state,
                "final_hardware_gate": recovery_hardware_gate,
            },
            "completed_unix_s": time.time(),
        }
    )
    write_checkpoint(args.output, evidence)
    print(
        "BOARD_ENDURANCE_RESULT "
        + json.dumps(
            {
                "status": "PASS",
                "frames": len(frame_elapsed),
                "elapsed_s": elapsed,
                "output": str(args.output),
            },
            sort_keys=True,
        ),
        flush=True,
    )


if __name__ == "__main__":
    main()
