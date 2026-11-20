# Profiling timing closure and board evaluation gates

- Date: 2026-09-08
- Owner: Codex
- Branch: `codex/overnight-board-bringup`
- Status: PYNQ runtime and 100-audio complete; real-time, full endurance,
  PESQ/STOI, and physical power remain open

## Outcome

Produce a timing-clean PYNQ-Z1 image that exposes coherent per-frame PL
profiling, then use the matching BIT/HWH and frozen audio inputs to measure
correctness, latency, RTF, sparsity, traffic, power, and endurance without
mixing simulation, tool estimates, or physical board evidence.

## Scope

- Optimize the profiling snapshot/read path after the first implementation
  attempt exposed routing congestion and negative setup slack.
- Preserve the 192-word v2 software ABI and fail-closed error semantics.
- Keep the 100-audio corpus, experiment matrix, power trace analyzer, and
  endurance runner reproducible and resumable.
- Preserve all unrelated dirty Vivado reports and webtalk files.

## Files

- `rtl/profiling/accelerator_profiling_counters.v`
- `rtl/axi/accelerator_control_axil.v`
- `rtl/top/accelerator_system_top.v`
- `rtl/tb/tb_accelerator_profiling_counters.v`
- `rtl/tb/tb_accelerator_control_axil.sv`
- `software/pynq/accelerator_profile.py`
- `software/tests/test_accelerator_profile.py`
- `docs/PYNQ_Z1_PROFILING_V2.md`
- New evidence only under
  `rtl/reports/accelerator_optimization_final/`.

## Acceptance checks

- Profiling and AXI control XSim tests pass in Vivado 2018.3.
- Complete Python test suite passes.
- Clean full block-design synthesis, place, route, and post-route phys-opt
  satisfy setup/hold, DRC/CDC, routing, and under-80-percent resource gates.
- Only a passing routed checkpoint may produce a new BIT/HWH bundle.
- Board results require a verified PYNQ Linux endpoint and matching image.
- Physical power results require synchronized external-meter raw traces; a
  vectorless Vivado estimate is reported separately.

## Completion record

- Profiling and AXI control XSim: PASS in Vivado 2018.3. The profiler test
  observed `frame_cycles=4`, `state_sum=4`, `dense_eq=7680`,
  `retired_macs=1600`, and `skipped_macs=121280`.
- Current canonical host regressions: 119 tests in `rtl/tests software/tests`
  plus 92 tests in `sparse_memory_v1/tests sparse_memory_v1/tb`, all PASS.
- Failing snapshot-mux baseline: post-route setup WNS -1.186 ns, 10,679
  failing endpoints, 29,350 LUT, and 46,754 FF.
- Hardware-acknowledged-reset release `ec457b1`: standard setup WNS +0.264 ns,
  250 ps guardbanded WNS +0.014 ns, guardbanded hold WHS +0.006 ns, zero
  timing/routing/blocking-DRC failures, 27,761 LUT, and 38,456 FF.
- Matching BIT/HWH SHA-256:
  `6521bdca63ee58023b7884f880cae3c2c5a98749fef5b555ea6fa3964d9aeaeb`
  and
  `6538bd37b6202a1b2fc3194e766f2aa49e5c2e0faf55a5f1d6c5248b001476bc`.
- PYNQ-Z1 experiment matrix: PASS. Nine correctness/profile runs and forty
  30-second benchmarks completed 150,040 benchmark frames. All 49 resets
  advanced the hardware epoch exactly once with all DMAs stopped and no DMA
  errors. All frozen-oracle arrays matched and all fault gates remained zero.
- Fastest measured configuration (`bulk/native/cache/no-diagnostics/busy`):
  mean frame 12.667 ms, frame/board-loop/end-to-end RTF
  1.584/3.031/3.146, and 41.247 frames/s. Real-time remains FAIL.
- 100-audio campaign: 100/100 clips PASS, 426,196 frames, 3,408.768 s
  evaluated audio. Weighted mean frame 11.055 ms; aggregate
  frame/board-loop/end-to-end RTF 1.382/2.739/2.853. Mean SNR improves
  +7.688 dB and mean SI-SDR improves +7.454 dB. All 100 reset and final
  fault/DMA safety gates pass.
- Representative `fileid_081` profile: 4,246 frames, cycle conservation PASS,
  request/MAC skip 77.115%, parameter-byte savings 55.179%, and PL
  mean/p95/p99 latency 10.484/11.411/12.282 ms. Its raw scheduler outlier is
  retained and called out separately.
- Endurance is partial, not PASS: 179,000-frame／3,265.110-second durable
  checkpoint, zero frame-ID discontinuities, followed by safe reset epoch
  153→154 and stopped/error-free DMAs. It did not reach both 3,600 seconds
  and 450,000 frames, and no post-pause recovery inference was submitted.
- Vivado vectorless estimate: 1.589 W total, 1.443 W dynamic, 0.146 W static,
  43.3 C, Medium confidence; no SAIF/VCD and not physical board power.
- PESQ/STOI remain blocked only by missing optional board packages. Physical
  power remains blocked on a calibrated external meter and synchronized raw
  traces.

## Handoff

Full raw evidence is preserved at
`/home/ivanhuang/zephyr_board_results/ec457b1/`; the repository keeps the
100 per-clip metrics, evaluation/manifest, logs, experiment-matrix summary,
partial-endurance state, and full raw-file SHA-256 list under
`rtl/reports/accelerator_optimization_final/board_runs/ec457b1/`. Do not infer
PESQ/STOI, completed endurance, recovery inference, real-time throughput, or
physical power from the acquired data. A future endurance continuation must
either implement checkpoint resume or begin a new run; do not relabel the
partial file as complete. Physical power needs a calibrated external meter.
