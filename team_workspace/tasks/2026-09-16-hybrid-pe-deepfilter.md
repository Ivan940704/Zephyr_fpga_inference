# Hybrid PE array DeepFilter integration

- Owner: Codex.
- Branch: `codex/hybrid-pe-deepfilter`.
- Baseline: commit `946c002afc250921319d0cfb6e48941edca3fe9c`, sparse-v5 image ABI `0x00050002`, 32 PE, 100 MHz.
- Goal: execute Multi-Frame Complex DeepFiltering through the existing CDF owner and `pe_cdf_sequencer` in the shared 32-lane Hybrid PE array. The production system must not instantiate a separate DeepFilter arithmetic engine.
- Preserve: sparse union planning, active-index request/MAC skipping, sparse DDR-to-cache loading, cache residency, mandatory dense parameter handling, recurrent state/index storage, reset/abort/fault behavior, PL LayerNorm, coefficient generation/storage, 64-bit AXIS/DMA boundaries, and current numerical formats.
- Expected RTL scope: `rtl/top/accelerator_top.v`, `rtl/memory/sequential_v5_pe_memory_subsystem.v`, production PE-array CDF integration, a controller/adapter for coefficient/history/stream sequencing, affected testbenches/manifests/build scripts, control ABI/driver files if the observable contract changes.
- Functional gates: focused self-checking PE/CDF tests; sparse-memory dense/sparse equivalence and fault/backpressure regressions; accelerator-top reference comparison; INT8 complex operands with INT32 real/imag accumulation; orders 5/3/1 for bins 0-31/32-127/128-255; no output change versus the frozen sparse-v5 oracle.
- Implementation gates: full PYNQ-Z1 Vivado 2018.3 synthesis/place/route at 100 MHz, non-negative setup/hold slack, zero unrouted nets, no blocking DRC errors, and resource comparison against sparse-v5. Do not treat OOC timing as full-system closure.
- Board gates: generate matching BIT/HWH and checksum manifest only from a passing routed checkpoint; use safe DMA/reset/programming order; fixed-five files `000`, `025`, `050`, `075`, `099` must pass before any wider campaign; report correctness, fault gates, sparse counters, START-to-output and complete-iteration latency separately.
- Evidence boundary: repository facts, RTL/XSim evidence, Vivado measurements, board measurements, and estimates remain separately labeled. The frozen sparse-v5 reports remain unchanged.

## PYNQ-Z1 feasibility

- Placement: PL RTL, reusing the existing 32 Hybrid PEs instead of a second arithmetic engine.
- Target part / clock: `xc7z020clg400-1`, 100 MHz.
- Numeric formats: INT8 spectrum/coefficient operands and INT32 real/imag accumulators; 256 complex bins; causal orders 5/3/1.
- Parallel instances / lanes: one time-multiplexed 32-PE array; the current CDF sequencer drives 16 physical lanes per complex term phase.
- Local state: retain the existing coefficient store and five-frame spectrum history; exact placement will be chosen after interface audit.
- External interfaces: unchanged 64-bit spectrum AXIS ingress and 64-bit enhanced-spectrum AXIS egress; no new DMA packet.
- Sparse-memory impact: CDF receives PE ownership only after neural stages retire; loader/planner/cache and active-index paths must remain bit-exact and quiescent during CDF ownership.
- Main risk: routing/control fanout and arbitration timing at the already dense PE/memory boundary; fallback is additional registered command/result boundaries, not restoration of a dedicated MAC engine.
- Initial evidence level: repository facts plus design assumptions; the completion record below supersedes this with fresh XSim, routed implementation, and board runtime measurements.
- Feasibility: PASS WITH RISKS.

## Completion record

- Production architecture: PASS. `hybrid_pe_deepfilter_controller` performs
  history/coefficient/result storage and CDF packet scheduling, while the
  existing `OWNER_CDF` path and `pe_cdf_sequencer` execute every complex MAC on
  the same 32 physical Hybrid PEs. The production manifests no longer compile
  or instantiate `sequential_deepfilter_engine`.
- Sparse preservation: PASS in focused dense and sparse subsystem XSim. The
  sparse run planned and issued 865,808 bytes versus 2,107,312 dense-equivalent
  bytes, saving 1,241,504 bytes; actual bytes exactly matched the plan.
- Functional verification: dense subsystem 1,452,257 checks / 60 jobs / 25
  stages; sparse subsystem 1,073,066 checks / 60 jobs / 24 stages; PE-array
  reference/XSim and top integration checks PASS; driver/ABI tests PASS. A
  dedicated legacy-vs-hybrid differential XSim additionally passed five
  history-bearing frames, 1,305 checks, and 1,280/1,280 complex bin results
  bit-exactly.
- Routed implementation: PASS at 100 MHz on `xc7z020clg400-1`; standard WNS
  `+0.202 ns`, 50 ps hold-guardbanded WHS `+0.009 ns`, zero failing endpoints,
  zero routing errors, zero DRC errors/critical warnings. The optional 250 ps
  setup margin is `-0.048 ns` and is not claimed as met.
- Full-design resources: 44,717 LUT, 46,611 FF, 75 RAMB36, 7 RAMB18, and 62
  DSP48. OOC subsystem evidence independently identifies 32 Hybrid MAC
  instances and reports WNS `+0.013 ns`.
- Artifact and board: matching BIT/HWH generated for source commit
  `f460743940ca66ed04f2e33746968ce587b0dd72`; exact Digilent JTAG programming
  PASS. The board required the same PYNQ `Overlay(bit).download()` Linux/XRT
  initialization used by the earlier latency task after JTAG programming.
- Fixed-five board gate: PASS on formal files 000/025/050/075/099 with the
  exact sparse-v5 source and feature SHA-256 set. All 23,137 frame IDs were
  contiguous, all five enhanced WAVs were byte-for-byte identical to ABI
  `0x00050002`, all fault fields were zero, and all DMA channels ended idle.
  Weighted mean complete iteration was 5.788423 ms, aggregate p99 iteration
  6.582944 ms, sustained frame-loop RTF 0.725672, and persistent end-to-end
  RTF 0.994996. Timing deltas versus the separate sparse-v5 run are not claimed
  as a speedup.
- Sparse runtime gate: PASS on six coherent file-000 counter snapshots. Request
  sparsity / MAC skip fraction was 87.852697%; 2,876,688 sparse-stage bytes
  were read and 3,445,248 bytes saved (54.496724%). These are sampled totals,
  not fixed-five aggregate traffic.
- Formal 100-file board gate: PASS on file IDs 000--099, 426,196 frames, and
  3,408.768 s evaluated audio with one persistent runtime/parameter load. All
  100 enhanced WAVs are byte-for-byte identical to the frozen sparse-v5
  baseline. Weighted mean START-to-output was 5.382242 ms, complete iteration
  5.796062 ms, sustained frame-loop RTF 0.726617, and clip-mean enhanced SI-SDR
  14.511990 dB. All per-file control/mailbox faults were zero and all DMA
  channels ended idle/error-free.
- Remaining boundary: board-rail power, hybrid full-design vectorless power,
  thermal, endurance, DNSMOS, PESQ, STOI, and independent SI-SNR were not
  measured.

## Follow-up: formal 100-file hybrid campaign

- Owner: Codex.
- Scope: run file IDs 000--099 on the routed ABI `0x00050003` PYNQ-Z1 image
  with the frozen original source WAVs, precomputed feature bundles, sparse-v5
  parameter image, one persistent runtime, and profiling disabled for latency.
- Acceptance: 100/100 files PASS; every per-file frame sequence contiguous;
  final accelerator/DMA faults zero; output hashes compared against the frozen
  sparse-v5 100-file baseline; aggregate frame/iteration latency, sustained and
  end-to-end RTF, SNR, and SI-SDR reported with their exact aggregation method.
- Separate evidence: sparsity counters remain a counter-enabled profiling run;
  routed resource/timing reports remain Vivado evidence; vectorless power and
  operation-proxy energy remain estimates rather than board measurements.
- Result: PASS. The acceptance checks above were met. Exact aggregate and
  per-file numbers are recorded in `paper_metrics_100file.md`,
  `full100_run_manifest.json`, and `full100_per_file_metrics.csv`.
