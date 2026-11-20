# PYNQ-Z1 accelerator runtime optimization A/B runbook

Date: 2026-09-08

This runbook executes the Gate 1/2 portion of `final_revisit.md`.  Image v2
adds coherent PL counters while retaining v1 packet and parameter compatibility. Scalar
mailbox I/O, NumPy LayerNorm, per-frame output zero/flush, diagnostics, and
batch ISTFT remain the fail-closed defaults until a board A/B promotes an
optimized combination.

## Evidence state

- Host contract: acquired.  Bulk mailbox access is byte-identical to the
  scalar ABI, the portable C kernels match the NumPy reference, and streaming
  ISTFT matches the batch path.
- RTL counters, parser, profiler/control XSim, full implementation, matching
  v2 BIT/HWH, exact-target JTAG programming, and read-only ABI smoke are PASS.
  The released BIT SHA-256 is
  `52d8f0296965068716d1b2a50966b5423f2abd92e8589e2e3fa372893097f289`.
- PYNQ board performance/correctness and counter acquisition remain pending an
  explicitly available PYNQ Linux execution endpoint. Host timing and JTAG
  identity are not board inference results.
- Vivado vectorless power is available as a separate estimate. Physical power
  still requires an external calibrated meter and synchronized raw traces.

## Build the native library on the PYNQ target

Never copy an x86 host library to the ARM board.  Build the reviewed source on
the board and preserve the emitted compiler and SHA-256 metadata:

```bash
python3 software/pynq/build_native_layernorm.py \
  --output software/pynq/libzephyr_native_layernorm.so
```

Verify the release BIT, parameter image, runtime bundle, Python sources, C
source, and target-built library before the run.  Record PYNQ, Python, NumPy,
kernel, compiler, board, and artifact versions.

## Correctness order

Use a clean PS boot and exactly one JTAG configuration of the known-good
release.  Do not reconfigure PL while any AXI DMA channel remains enabled.
Run the same frozen input in this order:

1. scalar mailbox + NumPy + conservative cache (baseline);
2. bulk mailbox only;
3. native LayerNorm only;
4. bulk + native;
5. optimized output cache only after the preceding output is byte-identical;
6. diagnostics-off benchmark only after the saved correctness result passes.

Every optimized run must match the baseline frame IDs, fullband projection,
subband payload, quantized spectrum, and all 256x2 INT32 output accumulators.
A mismatch stops the sequence before performance promotion.

## Baseline command

The default arguments deliberately select scalar/NumPy/conservative cache:

```bash
python3 software/pynq/run_accelerator_inference.py \
  --parameter-image /absolute/path/parameters_v4.bin \
  --runtime-parameters /absolute/path/runtime_parameters.npz \
  --parameter-sha256 e4f1f5cd78007a47c8ecfc137f2f0e8117aa2af162bd7050913bf1867cf2cf34 \
  --output-dir /tmp/zephyr_ab_baseline \
  --samples 4096 \
  --progress-every 0
```

## Optimized correctness command

```bash
python3 software/pynq/run_accelerator_inference.py \
  --parameter-image /absolute/path/parameters_v4.bin \
  --runtime-parameters /absolute/path/runtime_parameters.npz \
  --parameter-sha256 e4f1f5cd78007a47c8ecfc137f2f0e8117aa2af162bd7050913bf1867cf2cf34 \
  --output-dir /tmp/zephyr_ab_optimized \
  --samples 4096 \
  --mailbox-io bulk \
  --layernorm native \
  --native-library software/pynq/libzephyr_native_layernorm.so \
  --optimized-output-cache \
  --progress-every 0
```

Compare `result.npz` boundary arrays and accumulators before benchmarking.
Do not compare only the enhanced WAV or SNR.

## Profiling and benchmark commands

Add `--profile` to save per-frame monotonic T00-T16 timestamps.  This changes
the hot path by performing incremental ISTFT and timestamp calls, so use it to
explain buckets, not as the primary throughput number.  Run a matched
profiling-off case and require profiling overhead below one percent before
using profiled throughput in a paper.

On image v2, add `--hardware-profile` to save the coherent 192-word per-frame
PL snapshot in `hardware_profile.jsonl`.  The runner validates schema, sequence,
frame ID and state-cycle conservation before accepting each frame.  Do not use
this mode for the primary throughput number because reading 192 MMIO words per
frame adds PS overhead.

For the profiling-off benchmark use `--compact --progress-every 0
--no-diagnostics`.  Warm up first, then run each A/B level at least five times.
Preserve mean, standard deviation, P50, P95, P99, maximum, frame IDs, faults,
DMA states, BIT/source/parameter hashes, raw metrics JSON, and result NPZ.

## Promotion gate

Promote no optimized option to the default until all of these hold on the
PYNQ-Z1: byte-exact boundary/output equality; zero accelerator, control,
mailbox, and DMA faults; continuous frame IDs; five-run latency statistics;
and safe cleanup.  This software checkpoint cannot by itself establish
real-time throughput, post-route timing, RTL counter correctness, endurance,
or physical power.

## Automated execution gates

After building the native ARM libraries and loading a matching v2 BIT/HWH, run
the ordered correctness and randomized five-repeat performance matrix:

```bash
python3 software/pynq/run_board_experiment_matrix.py \
  --parameter-image /absolute/path/parameters_v4.bin \
  --runtime-parameters /absolute/path/runtime_parameters.npz \
  --parameter-sha256 e4f1f5cd78007a47c8ecfc137f2f0e8117aa2af162bd7050913bf1867cf2cf34 \
  --native-library software/pynq/libzephyr_native_layernorm.so \
  --output-root /tmp/zephyr_experiment_matrix
```

It first compares scalar/bulk/native/cache/diagnostic/polling and dense/sparse
boundaries against the frozen 33-frame NumPy-validated NPZ.  It then captures
one PS+PL profile and runs 30-second audio equivalents in a seeded randomized
order five times per configuration.  A mismatch stops all later promotion.

Run the complete audio set from a board-local copy of the fixed dataset:

```bash
python3 software/pynq/run_board_100_audio.py \
  --dataset-root /absolute/path/PTQ_data \
  --parameter-image /absolute/path/parameters_v4.bin \
  --runtime-parameters /absolute/path/runtime_parameters.npz \
  --parameter-sha256 e4f1f5cd78007a47c8ecfc137f2f0e8117aa2af162bd7050913bf1867cf2cf34 \
  --native-library software/pynq/libzephyr_native_layernorm.so \
  --output-root /tmp/zephyr_100_audio
```

Use `--resume` only for directories whose input hashes, metrics and enhanced
WAV already pass validation; partial or mismatched directories are never
overwritten.  Finally run `run_board_endurance.py`; it stops only after both
one hour and 450,000 continuous frames, performs the coordinated single soft
reset, verifies the reset epoch increment, and completes one post-reset frame.

IRQ mode is not exposed by the current direct-register driver and remains
`BLOCKED`; the implemented wait-factor comparison is 50-us sleep versus true
busy polling.  Physical power is ingested separately using
`software/evaluation/power_trace_metrics.py` and the five-repeat measurement
spec template under `rtl/reports/accelerator_optimization_final/power_physical/`.
