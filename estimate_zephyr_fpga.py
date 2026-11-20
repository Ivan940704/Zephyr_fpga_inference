#!/usr/bin/env python3
"""Analytical cycle/RTF estimator for Ivan940704/allen_Zephyr.

The estimator covers the repository's FPGA boundary only: external STFT bins
and magnitude features in, enhanced bins out.  It is not a synthesis report.
"""

from __future__ import annotations

import argparse
import math
from dataclasses import dataclass


N_FFT = 512
HOP_LENGTH = 128
RAW_PARAMETER_BYTES = 2_193_288
EXPORTED_WEIGHT_BYTES = 1_802_112
SHARED_WEIGHT_BYTES = 956_096
SHARED_DEDUP_PARAMETER_BYTES = 1_347_272
RECURRENT_STATE_BYTES = 9_344


@dataclass(frozen=True)
class GSU:
    name: str
    input_size: int
    hidden_size: int
    instances: int


@dataclass(frozen=True)
class Linear:
    name: str
    input_size: int
    output_size: int
    instances: int


GSUS = (
    GSU("FB GSU0", 64, 320, 1),
    GSU("FB GSU1", 320, 320, 1),
    GSU("SB0 GSU0", 46, 224, 4),
    GSU("SB0 GSU1", 224, 224, 4),
    GSU("SB1 GSU0", 94, 224, 3),
    GSU("SB1 GSU1", 224, 224, 3),
    GSU("SB2 GSU0", 158, 224, 2),
    GSU("SB2 GSU1", 224, 224, 2),
)

LINEARS = (
    Linear("FB projection", 320, 64, 1),
    Linear("SB0 projection", 224, 80, 4),
    Linear("SB1 projection", 224, 192, 3),
    Linear("SB2 projection", 224, 128, 2),
)

# 4 real INT8 multiplies per complex tap.
DEEPFILTER_REAL_MULTIPLIES = 4 * (32 * 5 + 96 * 3 + 128 * 1)

# LN(64) once, LN(46) four times, LN(94) three times, LN(158) twice.
LAYERNORM_ELEMENTS = 64 + 46 * 4 + 94 * 3 + 158 * 2
LAYERNORM_VECTORS = 1 + 4 + 3 + 2


def ceil_div(numerator: int, denominator: int) -> int:
    return (numerator + denominator - 1) // denominator


def stft_frames(samples: int, center: bool) -> int:
    if center:
        # PyTorch/librosa-style center padding by n_fft // 2 on both sides.
        return samples // HOP_LENGTH + 1
    if samples < N_FFT:
        return 0
    return 1 + (samples - N_FFT) // HOP_LENGTH


def int8_work(shared_weights: bool) -> tuple[int, int]:
    gsu_macs = 0
    for layer in GSUS:
        rows = layer.hidden_size if shared_weights else 2 * layer.hidden_size
        gsu_macs += layer.instances * rows * (layer.input_size + layer.hidden_size)
    linear_macs = sum(
        layer.instances * layer.input_size * layer.output_size for layer in LINEARS
    )
    return gsu_macs + linear_macs + DEEPFILTER_REAL_MULTIPLIES, linear_macs


def int8_cycles(mac_lanes: int, shared_weights: bool) -> int:
    cycles = 0
    for layer in GSUS:
        rows = layer.hidden_size if shared_weights else 2 * layer.hidden_size
        per_instance = ceil_div(rows * layer.input_size, mac_lanes)
        per_instance += ceil_div(rows * layer.hidden_size, mac_lanes)
        cycles += layer.instances * per_instance
    for layer in LINEARS:
        cycles += layer.instances * ceil_div(
            layer.input_size * layer.output_size, mac_lanes
        )
    cycles += ceil_div(DEEPFILTER_REAL_MULTIPLIES, mac_lanes)
    return cycles


def requant_operations() -> int:
    # Per GSU hidden channel: input gate x2, recurrent gate x2,
    # previous-state term, cell-gate term, and folded BatchNorm = 7.
    gsu = sum(layer.instances * 7 * layer.hidden_size for layer in GSUS)
    linear = sum(layer.instances * layer.output_size for layer in LINEARS)
    return gsu + linear


def _gsu_mac_cycles(layer: GSU, lanes: int, shared_weights: bool) -> int:
    rows = layer.hidden_size if shared_weights else 2 * layer.hidden_size
    return layer.instances * (
        ceil_div(rows * layer.input_size, lanes)
        + ceil_div(rows * layer.hidden_size, lanes)
    )


def _linear_mac_cycles(layer: Linear, lanes: int) -> int:
    return layer.instances * ceil_div(layer.input_size * layer.output_size, lanes)


def parallel_subband_cycles(args: argparse.Namespace) -> dict[str, int | tuple[int, ...]]:
    full_mac = sum(_gsu_mac_cycles(layer, args.mac_lanes, args.shared_weights) for layer in GSUS[:2])
    full_mac += _linear_mac_cycles(LINEARS[0], args.mac_lanes)
    full_rq_ops = sum(layer.instances * 7 * layer.hidden_size for layer in GSUS[:2])
    full_rq_ops += LINEARS[0].output_size
    full_rq = ceil_div(full_rq_ops, args.requant_lanes)
    full_ln = ceil_div(2 * 64, args.layernorm_lanes) + args.rsqrt_cycles
    full_total = full_mac + full_rq + full_ln + args.overhead_cycles

    deepfilter_by_band = (4 * 32 * 5, 4 * 96 * 3, 4 * 128 * 1)
    ln_elements_by_band = (46 * 4, 94 * 3, 158 * 2)
    ln_vectors_by_band = (4, 3, 2)
    band_totals: list[int] = []
    band_mac_cycles: list[int] = []
    band_rq_cycles: list[int] = []
    band_ln_cycles: list[int] = []
    for band in range(3):
        gsu_pair = GSUS[2 + 2 * band : 4 + 2 * band]
        linear = LINEARS[1 + band]
        mac = sum(
            _gsu_mac_cycles(layer, args.mac_lanes, args.shared_weights)
            for layer in gsu_pair
        )
        mac += _linear_mac_cycles(linear, args.mac_lanes)
        mac += ceil_div(deepfilter_by_band[band], args.mac_lanes)
        rq_ops = sum(layer.instances * 7 * layer.hidden_size for layer in gsu_pair)
        rq_ops += linear.instances * linear.output_size
        rq = ceil_div(rq_ops, args.requant_lanes)
        ln = ceil_div(2 * ln_elements_by_band[band], args.layernorm_lanes)
        ln += ln_vectors_by_band[band] * args.rsqrt_cycles
        band_mac_cycles.append(mac)
        band_rq_cycles.append(rq)
        band_ln_cycles.append(ln)
        band_totals.append(mac + rq + ln + args.overhead_cycles)
    critical_band = max(range(3), key=band_totals.__getitem__)
    return {
        "fullband_cycles": full_total,
        "subband_cycles": tuple(band_totals),
        "mac_cycles": full_mac + band_mac_cycles[critical_band],
        "requant_cycles": full_rq + band_rq_cycles[critical_band],
        "layernorm_cycles": full_ln + band_ln_cycles[critical_band],
        "control_cycles": 2 * args.overhead_cycles,
        "cycles_per_frame": full_total + max(band_totals),
    }


def sparsity_eligible_ops(shared_weights: bool) -> tuple[int, int]:
    eligible = 0
    dense = DEEPFILTER_REAL_MULTIPLIES
    for index, layer in enumerate(GSUS):
        rows = layer.hidden_size if shared_weights else 2 * layer.hidden_size
        # Every recurrent hx is binary.  The second GSU in each stack also
        # receives binary spikes from the preceding GSU; the first does not.
        eligible += layer.instances * rows * layer.hidden_size
        if index % 2 == 1:
            eligible += layer.instances * rows * layer.input_size
        else:
            dense += layer.instances * rows * layer.input_size
    eligible += sum(
        layer.instances * layer.input_size * layer.output_size for layer in LINEARS
    )
    return eligible, dense


def sparse_parallel_subband_cycles(
    args: argparse.Namespace,
) -> dict[str, int | tuple[int, ...]]:
    activity = 1.0 - args.spike_sparsity

    def sparse_matvec(rows: int, columns: int) -> tuple[int, int]:
        active_columns = math.ceil(columns * activity - 1e-12)
        compute = active_columns * ceil_div(rows, args.mac_lanes)
        encode = ceil_div(columns, args.spike_encoder_width)
        return compute, encode

    def stage(
        gsu_layers: tuple[GSU, ...],
        linear: Linear,
        ln_elements: int,
        ln_vectors: int,
        deepfilter_ops: int,
    ) -> tuple[int, int, int, int, int]:
        mac = 0
        encoder = 0
        for pair_index, layer in enumerate(gsu_layers):
            rows = layer.hidden_size if args.shared_weights else 2 * layer.hidden_size
            if pair_index == 0:
                mac += layer.instances * ceil_div(
                    rows * layer.input_size, args.mac_lanes
                )
            else:
                sparse_cycles, scan_cycles = sparse_matvec(rows, layer.input_size)
                mac += layer.instances * sparse_cycles
                encoder += layer.instances * scan_cycles
            sparse_cycles, scan_cycles = sparse_matvec(rows, layer.hidden_size)
            mac += layer.instances * sparse_cycles
            encoder += layer.instances * scan_cycles
        sparse_cycles, scan_cycles = sparse_matvec(
            linear.output_size, linear.input_size
        )
        mac += linear.instances * sparse_cycles
        encoder += linear.instances * scan_cycles
        mac += ceil_div(deepfilter_ops, args.mac_lanes) if deepfilter_ops else 0
        rq_ops = sum(layer.instances * 7 * layer.hidden_size for layer in gsu_layers)
        rq_ops += linear.instances * linear.output_size
        rq = ceil_div(rq_ops, args.requant_lanes)
        ln = ceil_div(2 * ln_elements, args.layernorm_lanes)
        ln += ln_vectors * args.rsqrt_cycles
        total = mac + encoder + rq + ln + args.overhead_cycles
        return total, mac, encoder, rq, ln

    full = stage(GSUS[:2], LINEARS[0], 64, 1, 0)
    band_specs = (
        (GSUS[2:4], LINEARS[1], 46 * 4, 4, 4 * 32 * 5),
        (GSUS[4:6], LINEARS[2], 94 * 3, 3, 4 * 96 * 3),
        (GSUS[6:8], LINEARS[3], 158 * 2, 2, 4 * 128),
    )
    bands = tuple(stage(*spec) for spec in band_specs)
    critical_band = max(range(3), key=lambda index: bands[index][0])
    critical = bands[critical_band]
    return {
        "fullband_cycles": full[0],
        "subband_cycles": tuple(band[0] for band in bands),
        "mac_cycles": full[1] + critical[1],
        "encoder_cycles": full[2] + critical[2],
        "requant_cycles": full[3] + critical[3],
        "layernorm_cycles": full[4] + critical[4],
        "control_cycles": 2 * args.overhead_cycles,
        "cycles_per_frame": full[0] + critical[0],
    }


def estimate(args: argparse.Namespace) -> dict[str, float | int]:
    samples = round(args.duration_seconds * args.sample_rate)
    frames = stft_frames(samples, args.center)
    int8_ops, linear_ops = int8_work(args.shared_weights)
    mac_cycles = int8_cycles(args.mac_lanes, args.shared_weights)
    rq_ops = requant_operations()
    rq_cycles = ceil_div(rq_ops, args.requant_lanes)
    ln_cycles = ceil_div(2 * LAYERNORM_ELEMENTS, args.layernorm_lanes)
    ln_cycles += LAYERNORM_VECTORS * args.rsqrt_cycles
    parallel = None
    if args.parallel_subbands:
        parallel = (
            sparse_parallel_subband_cycles(args)
            if args.spike_sparsity is not None
            else parallel_subband_cycles(args)
        )
        mac_cycles = int(parallel["mac_cycles"])
        rq_cycles = int(parallel["requant_cycles"])
        ln_cycles = int(parallel["layernorm_cycles"])
        cycles_per_frame = int(parallel["cycles_per_frame"])
        control_cycles = int(parallel["control_cycles"])
        encoder_cycles = int(parallel.get("encoder_cycles", 0))
    else:
        cycles_per_frame = mac_cycles + rq_cycles + ln_cycles + args.overhead_cycles
        control_cycles = args.overhead_cycles
        encoder_cycles = 0
    total_cycles = frames * cycles_per_frame
    inference_seconds = total_cycles / (args.clock_mhz * 1_000_000.0)
    accelerator_rtf = inference_seconds / args.duration_seconds
    result: dict[str, float | int] = {
        "samples": samples,
        "frames": frames,
        "int8_ops_per_frame": int8_ops,
        "linear_ops_per_frame": linear_ops,
        "requant_ops_per_frame": rq_ops,
        "mac_cycles_per_frame": mac_cycles,
        "requant_cycles_per_frame": rq_cycles,
        "layernorm_cycles_per_frame": ln_cycles,
        "cycles_per_frame": cycles_per_frame,
        "control_cycles_per_frame": control_cycles,
        "encoder_cycles_per_frame": encoder_cycles,
        "total_cycles": total_cycles,
        "inference_seconds": inference_seconds,
        "accelerator_rtf": accelerator_rtf,
        "weight_bytes_per_frame": int8_ops - DEEPFILTER_REAL_MULTIPLIES,
    }
    if parallel is not None:
        result["fullband_cycles_per_frame"] = int(parallel["fullband_cycles"])
        result["subband_cycles_per_frame"] = parallel["subband_cycles"]  # type: ignore[assignment]
    if args.spike_sparsity is not None:
        eligible, dense = sparsity_eligible_ops(args.shared_weights)
        result["sparsity_eligible_ops_per_frame"] = eligible
        result["non_skippable_ops_per_frame"] = dense
        result["effective_int8_ops_per_frame"] = round(
            dense + eligible * (1.0 - args.spike_sparsity)
        )
    if args.weight_bandwidth_mbps is not None:
        if args.weight_load_scope == "audio":
            weight_bytes = (
                SHARED_DEDUP_PARAMETER_BYTES
                if args.shared_weights
                else RAW_PARAMETER_BYTES
            )
        else:
            weight_bytes = frames * int(result["weight_bytes_per_frame"])
        weight_seconds = weight_bytes / (args.weight_bandwidth_mbps * 1_000_000.0)
        result["weight_bytes_per_audio"] = weight_bytes
        result["weight_seconds"] = weight_seconds
        result["bandwidth_bound_seconds"] = max(inference_seconds, weight_seconds)
        result["bandwidth_bound_rtf"] = (
            float(result["bandwidth_bound_seconds"]) / args.duration_seconds
        )
    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--duration-seconds", type=float, default=1.0)
    parser.add_argument("--sample-rate", type=int, default=16_000)
    parser.add_argument("--clock-mhz", type=float, default=100.0)
    parser.add_argument("--mac-lanes", type=int, default=64)
    parser.add_argument("--requant-lanes", type=int, default=8)
    parser.add_argument("--layernorm-lanes", type=int, default=1)
    parser.add_argument("--rsqrt-cycles", type=int, default=16)
    parser.add_argument("--overhead-cycles", type=int, default=256)
    parser.add_argument(
        "--weight-bandwidth-mbps",
        type=float,
        default=None,
        help="Optional sustained DDR-to-PL weight bandwidth in decimal MB/s.",
    )
    parser.add_argument(
        "--weight-load-scope",
        choices=("frame", "audio"),
        default="frame",
        help=(
            "Load weights for every frame, or tile each layer in BRAM and load "
            "the parameter set once per audio file (default: frame)."
        ),
    )
    parser.add_argument(
        "--center",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Use centered STFT frame-count convention (default: true).",
    )
    parser.add_argument(
        "--shared-weights",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Exploit the bit-identical two-gate GSU weights (default: true).",
    )
    parser.add_argument(
        "--parallel-subbands",
        action=argparse.BooleanOptionalAction,
        default=False,
        help="Run the three subband branches concurrently after fullband (default: false).",
    )
    parser.add_argument(
        "--spike-sparsity",
        type=float,
        default=None,
        help="Fraction of binary spike inputs equal to zero, from 0.0 to 1.0.",
    )
    parser.add_argument(
        "--spike-encoder-width",
        type=int,
        default=32,
        help="Spike bits scanned per encoder cycle (default: 32).",
    )
    args = parser.parse_args()
    for name in ("duration_seconds", "clock_mhz"):
        if getattr(args, name) <= 0:
            parser.error(f"--{name.replace('_', '-')} must be positive")
    for name in (
        "sample_rate",
        "mac_lanes",
        "requant_lanes",
        "layernorm_lanes",
        "rsqrt_cycles",
    ):
        if getattr(args, name) <= 0:
            parser.error(f"--{name.replace('_', '-')} must be positive")
    if args.overhead_cycles < 0:
        parser.error("--overhead-cycles must be non-negative")
    if args.weight_bandwidth_mbps is not None and args.weight_bandwidth_mbps <= 0:
        parser.error("--weight-bandwidth-mbps must be positive")
    if args.spike_sparsity is not None:
        if not 0.0 <= args.spike_sparsity <= 1.0:
            parser.error("--spike-sparsity must be between 0.0 and 1.0")
        if not args.parallel_subbands:
            parser.error("--spike-sparsity currently requires --parallel-subbands")
    if args.spike_encoder_width <= 0:
        parser.error("--spike-encoder-width must be positive")
    return args


def main() -> None:
    args = parse_args()
    result = estimate(args)
    mode = "shared-weight optimized" if args.shared_weights else "literal 2H export"
    print(f"Mode: {mode}")
    print(
        f"Audio: {args.duration_seconds:g} s, {args.sample_rate} Hz, "
        f"center={args.center}, frames={result['frames']}"
    )
    print(
        f"Architecture: {args.mac_lanes} INT8 MAC lanes, "
        f"{args.requant_lanes} requant lanes, {args.layernorm_lanes} LN lanes, "
        f"{args.clock_mhz:g} MHz"
    )
    if args.parallel_subbands:
        print("Schedule: fullband first, then SB0/SB1/SB2 on three parallel engines")
    if args.spike_sparsity is not None:
        print(
            f"Sparsity-aware: {args.spike_sparsity:.1%} zero spikes, "
            f"{args.spike_encoder_width}-bit encoder"
        )
    print(f"INT8 multiply/MAC work per frame: {result['int8_ops_per_frame']:,}")
    print(f"Requant multiplies per frame: {result['requant_ops_per_frame']:,}")
    print(
        "Cycle breakdown per frame: "
        f"MAC={result['mac_cycles_per_frame']:,}, "
        f"encoder={result['encoder_cycles_per_frame']:,}, "
        f"requant={result['requant_cycles_per_frame']:,}, "
        f"LayerNorm={result['layernorm_cycles_per_frame']:,}, "
        f"routing/control={result['control_cycles_per_frame']:,}"
    )
    if args.spike_sparsity is not None:
        print(
            "Sparsity-eligible INT8 ops per frame: "
            f"{result['sparsity_eligible_ops_per_frame']:,}; "
            f"effective INT8 ops: {result['effective_int8_ops_per_frame']:,}"
        )
    print(f"Estimated cycles per frame: {result['cycles_per_frame']:,}")
    if args.parallel_subbands:
        bands = result["subband_cycles_per_frame"]
        print(f"Fullband stage per frame: {result['fullband_cycles_per_frame']:,} cycles")
        print(
            "Parallel subband stages: "
            f"SB0={bands[0]:,}, SB1={bands[1]:,}, SB2={bands[2]:,} cycles"
        )
    print(f"Estimated cycles per audio file: {result['total_cycles']:,}")
    print(f"FPGA-boundary inference time: {result['inference_seconds']:.6f} s")
    print(f"Accelerator-only RTF: {result['accelerator_rtf']:.6f}")
    if args.weight_bandwidth_mbps is not None:
        print(
            f"Parameter traffic ({args.weight_load_scope} scope): "
            f"{result['weight_bytes_per_audio']:,} bytes; "
            f"DDR time at {args.weight_bandwidth_mbps:g} MB/s: "
            f"{result['weight_seconds']:.6f} s"
        )
        print(
            "Compute/DDR ideal-overlap lower bound: "
            f"{result['bandwidth_bound_seconds']:.6f} s, "
            f"RTF={result['bandwidth_bound_rtf']:.6f}"
        )
        print(
            "Non-overlapped compute + DDR upper estimate: "
            f"{result['inference_seconds'] + result['weight_seconds']:.6f} s"
        )
    print(
        "Whole-system RTF must additionally include external STFT, ISTFT, I/O, "
        "and host/FPGA transfer time."
    )


if __name__ == "__main__":
    main()
