# Fast-retirement fixed-five PYNQ handoff

Date: 2026-09-10
Owner: Codex
Branch: `codex/latency-experiment-32pe`

## Scope completed

- Use output-DMA TLAST as the successful frame retirement fence.
- Track the expected frame ID in software instead of polling the hardware frame
  counter after every successful frame.
- Remove successful-path fault-register reads from each frame.
- Skip the per-frame state-cycle MMIO read unless diagnostics or profiling is
  enabled.
- Preserve startup validation, timeout fault capture, final sticky-fault and
  frame-sequence checks, and final DMA idle/error checks.
- Add `--per-frame-diagnostics` to restore the diagnostic path when required.

Runtime implementation commit: `ea4b327`.

## Verification

- Targeted runtime/profile tests: 29/29 PASS.
- Software suite excluding its pre-existing v4-image-version assertion: 73/73
  PASS.
- Fresh PYNQ fixed-five run: file IDs 000/025/050/075/099, 5/5 PASS, 23,137
  frames, 185.056 seconds of evaluated audio.
- Accuracy: 5/5 enhanced WAV SHA-256 values are identical to the previous
  image-v5 run; audio-weighted SNR delta remains +7.4764 dB.
- Safety checks: contiguous frame IDs, matching final hardware/software frame
  IDs, zero control errors, zero first-fault registers, and idle/error-free DMA
  channels after cleanup.

## Measured latency

| Metric | Previous image-v5 | Fast retirement | Improvement |
|---|---:|---:|---:|
| Mean frame | 6.9333 ms | 6.8395 ms | 1.35% |
| p50 frame | 6.9109 ms | 6.8127 ms | 1.42% |
| p95 frame | 7.2645 ms | 7.1740 ms | 1.25% |
| p99 frame | 7.3902 ms | 7.3138 ms | 1.03% |
| Frame-compute RTF | 0.8668 | 0.8551 | 1.35% |
| Board-loop RTF | 1.6775 | 1.6616 | 0.95% |
| End-to-end RTF | 1.7744 | 1.7621 | 0.69% |

PL p99 remains below the 8 ms hop, but board-loop and end-to-end RTF remain
above 1.0. The largest observed frame was 22.316 ms due to one Linux scheduling
outlier; every per-file p99 remained below 8 ms.

## Interpretation and boundary

The earlier 5.303 ms profiled `T13` bucket also contained the coherent
per-frame hardware-profile snapshot reads. It was therefore not pure
retirement/fault-check overhead, and removing the normal-path checks could not
recover the full 5.303 ms. The measured production-path board-loop reduction is
about 0.127 ms per 8 ms hop.

The hardware image is unchanged: image-v5, 32 PEs, 100 MHz, LUT 45,188
(84.94%), FF 42,151 (39.62%), BRAM36 equivalent 79.5 (56.79%), DSP 65
(29.55%), routed WNS +0.250 ns. Resource and timing numbers are implementation
evidence; latency and accuracy above are fresh physical-board measurements.

## Evidence

- Tracked summary: `rtl/reports/accelerator_realtime_image_v5_32pe_fast_retirement_20260910/REPORT.md`
- Machine-readable comparison: `rtl/reports/accelerator_realtime_image_v5_32pe_fast_retirement_20260910/comparison.json`
- Raw downloaded run: `outputs/latency/2026-09-10-image-v5-32pe-fast-retirement/fixed5_fast_retirement_ea4b327/`
- Board run directory: `/home/xilinx/zephyr_image_v5_32pe_20260909/results/fixed5_fast_retirement_ea4b327/`
