# Real-time latency integration and staged board evaluation

- Date: 2026-09-09 (Asia/Taipei)
- Owner: Codex
- Branch: `codex/latency-experiment-32pe`
- Status: implementation and requested board experiments complete; PL hop gate passes, full-system real-time gate fails

## Outcome

Reduce sustained PYNQ-Z1 inference latency below the 8 ms audio hop. On
2026-09-09 the user replaced the per-checkpoint approval cadence with one
continuous implementation/verification run; pause only for a real permission,
hardware, or scope-changing blocker. Keep measured results, host regressions, RTL
simulation, Vivado implementation, and analytical projections separate. After
the final timing-clean release candidate is ready, rerun the same pinned
100-audio corpus used by the prior `ec457b1` board record.

## Frozen board set

- File IDs: `000`, `025`, `050`, `075`, `099`
- Audio duration: 185.056 s
- Frames: 23,137
- Hardware baseline: `ec457b1`, 16 PE, 100 MHz, 64-bit AXIS/HP
- Same-input control: mean PL 11.062 ms, board-loop RTF 2.694,
  end-to-end RTF 2.807

## Final 100-audio set

- File IDs: `000..099`
- Baseline corpus: the same 100 input triplets and hashes used by the
  `ec457b1` board record
- Baseline total: 426,196 frames and 3,408.768 s evaluated audio
- Baseline aggregate: weighted mean frame 11.055 ms; frame/board/E2E RTF
  1.382/2.739/2.853
- Detailed plan:
  `team_workspace/decisions/2026-09-09-final-100-audio-validation.md`

## Phases

1. Freeze latency recorder, fixed-point LayerNorm oracle, and a software/RTL
   bypass contract. Record baseline as phase 0.
2. Add a shared, pipelined PL LayerNorm engine and remove the production
   `ST_WAIT_PS` dependency while retaining an explicit debug fallback.
3. Integrate a production 32-PE/32-row tile path with matching controller,
   parameter-memory, requant, membrane, and serializer contracts.
4. Improve internal feeding with 256-bit tiles, banking/prefetch, longer
   bursts, and sufficient outstanding work; do not widen the Zynq-7020 HP
   port beyond its native 64 bits.
5. Convert the board runtime to persistent, overlapped DMA with double
   buffering and bounded completion waits.
6. Close the complete block design at 100 MHz, then sweep 105/110 MHz. Try
   125 MHz only after the lower-frequency images route cleanly.
7. Program only a timing-clean matching BIT/HWH and rerun the frozen five-file
   board set after each board-capable stage.
8. For the final release candidate, run the complete 100-audio corpus with
   profiling off for primary throughput, then run the fixed five files plus
   file081 with coherent hardware profiling for stage/operation latency.

## Latency record per phase

Each phase records commit/image identity, clock, PE count, input/interface
format, per-file and aggregate frame mean/p95/p99, `wait_ps`, PL state-cycle
breakdown, board-loop RTF, end-to-end RTF, DMA faults, frame continuity, audio
quality delta, and whether the result is measured or analytical.

## Acceptance gates

- Fixed-point LayerNorm is bit-exact against its frozen integer oracle across
  edge and randomized vectors, including biased variance, epsilon, rounding,
  affine gamma/beta, and output saturation.
- Connected RTL XSim passes before synthesis.
- Full design route has non-negative WNS/WHS, zero routing errors, complete
  timing coverage, and no blocking DRC before BIT/HWH generation.
- Board runs preserve frame IDs and finish with all DMA channels stopped and
  error-free after a hardware-acknowledged reset.
- Real-time pass requires PL p99 below 8 ms and sustained board-loop and
  end-to-end RTF below 1.0; the preferred margin is RTF at or below 0.8.

## Safety and rollback

- `rtl/pe_array/baseline/v1` remains frozen and unchanged.
- Production mailbox LayerNorm remains available as an explicit debug
  fallback until connected XSim, full-design timing, and board comparison pass.
- Do not generate or program BIT/HWH from a design with negative full-system
  WNS/WHS, routing errors, incomplete timing coverage, or blocking DRC.

## Progress

- Phase 0: recorded the same-input five-file PYNQ control at 16 PE, 100 MHz,
  64-bit AXIS/HP. Result: real-time FAIL (PL mean 11.062 ms, board RTF 2.694,
  end-to-end RTF 2.807).
- Phase 1: froze the signed-Q12/Q24/Q20 LayerNorm contract and passed 33 saved
  real-frame host comparisons. Result: numeric gate PASS; no board latency.
- Phase 2: implemented and bit-exact tested the shared LayerNorm leaf across 6
  vectors with randomized stalls. Final 125 MHz OOC route: WNS +0.144 ns,
  internal WHS +0.050 ns, 0 route errors, 1,559 LUT, 1,106 FF, 6 DSP. The
  longest tested vector used 4,043 cycles (32.344 us @ 125 MHz); the production
  10-vector testbench upper bound is 0.1916 ms @ 125 MHz. Result: leaf gate
  PASS; production integration and board latency remain pending.
- Phase 2b: generated 362 model-specific Q12 gamma/beta pairs, four reciprocal
  scales, the 255-entry projection dequantization map, and the 782-entry
  subband source map from the checksum-verified frozen parameter archive. All
  ROM entries and four invalid-index cases passed XSim with randomized output
  backpressure. 125 MHz OOC route: WNS +2.542 ns, internal WHS +0.102 ns,
  0 route errors, 293 LUT, 29 FF, 0 BRAM. Result: parameter-data gate PASS;
  no board latency change until the coordinator is connected.
- Phase 3: connected the 512-byte signed-Q12 magnitude ingress, shared
  LayerNorm engine, 64-byte fullband stream, projection capture, nine subband
  assembly/normalization passes, and local 782-byte dispatcher buffer. Three
  scaled connected-arithmetic fixtures passed byte-exact XSim for all 64
  fullband and 782 subband outputs under stalls. Each fixture reached
  `subbands_valid` in 22,875 cycles: 0.22875 ms @ 100 MHz or 0.18300 ms @
  125 MHz, excluding fullband PE projection wait and all top/DMA/software
  costs. OOC route passed at both 100 MHz (WNS +0.871 ns, internal WHS
  +0.052 ns) and 125 MHz (WNS +0.399 ns, internal WHS +0.051 ns), with 0
  route errors and 2,491 LUT, 1,288 FF, 6 DSP, 1 BRAM18. Result: coordinator
  gate PASS; production top integration and frozen five-file board latency
  remain pending.
- Phase 4: connected the coordinator into the production `accelerator_top`,
  made the 512-byte signed-Q12 magnitude ABI/image v3 the default, and retained
  the mailbox ABI behind `USE_PL_LAYERNORM=0`. Three coordinator-to-production-
  dispatcher fixtures passed all 846 feature reads across frames, using
  23,036/23,037/23,037 cycles to `subbands_valid` (maximum 0.23037 ms at
  100 MHz; this excludes real PE projection compute, the remaining accelerator,
  DMA, and software). Existing production-top XSim also passed. The 100 MHz
  OOC route had clean routing/coverage and WHS +0.007 ns, but WNS -0.015 ns on
  the frozen 16-PE fault/shared-requant/serializer chain. Result: functional
  gate PASS, setup timing FAIL; no BIT/HWH or five-file board measurement.
- Phase 4a: registered the PE-local overflow/protocol faults before they enter
  the subsystem's internal control/ready network while keeping public fault
  indication immediate and suppressing same-cycle done publication. Eleven
  structural assertions, 12,450,567 connected sparse XSim checks, and the
  production-top XSim passed. The 100 MHz OOC route now passes with WNS
  +0.006 ns, WHS +0.013 ns, clean routing/coverage, 21,267 LUT, 28,574 FF,
  71 RAMB36, 4 RAMB18, and 52 DSP. Normal-path cycle delta is zero; this is a
  timing-enablement result, not a board-latency reduction. No matching full-BD
  BIT/HWH or five-file board measurement exists yet.
- Phase 4b: added a non-fallthrough registered job-launch boundary between the
  global FSM and sparse job controller. The 12 structural assertions,
  12,450,755-check connected sparse XSim, and production-top XSim passed with
  unchanged dense/sparse bytes and job counts. Its conservative normal-frame
  cost is 30 cycles (0.00030 ms at 100 MHz); the four connected regression
  frames added 94 cycles total. The 100 MHz OOC route passed with WNS
  +0.064 ns and WHS +0.012 ns, but took 48:50 under high congestion. The next
  critical path is the 64-bit parameter-write register to the 5,824-bit
  parameter buffer, with 94.7 percent routing delay. No full-BD or board
  measurement exists for this phase.
- Phase 4c: replicated the registered 64-bit parameter-write data into eight
  kept locality banks, each driving no more than 12 of the 91 buffer words.
  The 13 structural assertions, 12,450,755-check connected sparse XSim, and
  production-top XSim passed with unchanged dense/sparse bytes. The normal
  frame latency delta is zero cycles. The 100 MHz OOC route passed with WNS
  +0.335 ns, WHS +0.017 ns, clean routing/coverage, 21,408 LUT, 28,957 FF,
  71 RAMB36, 4 RAMB18, and 52 DSP. The former 90-fanout path left the top ten,
  and route-design elapsed fell from 48:50 to 1:43. No full-BD or board
  measurement exists for this phase.
- Phase 4d: screened 100/102/103/104/105/111.111/125 MHz by re-constraining
  the Phase 4c routed checkpoint, then ran fresh OOC synthesis/place/route at
  102 and 104 MHz. Both fresh runs passed routing, timing coverage, DRC, and
  resource gates. At 102 MHz WNS/WHS were +0.232/+0.007 ns; at 104 MHz they
  were +0.032/+0.021 ns. The unchanged 23,037-cycle frontend component is
  0.225855 ms or 0.221501 ms respectively. Use 102 MHz as the preferred
  engineering candidate and treat 104 MHz as a low-margin OOC ceiling. No
  full-Zynq clock generation, BIT/HWH, or five-file board measurement exists.
- Phase 5 contract checkpoint: completed the mandatory baseline/interface
  review for the 32-PE architecture change. The exact incompatibilities are
  recorded in
  `team_workspace/decisions/2026-09-09-production-v2-32pe-contract.md`.
  `baseline/v1` remains unchanged. This checkpoint adds no RTL and no cycles;
  board latency is `NOT_MEASURED`. Using the prior file081 profile and the
  existing 70-percent parallel-compute model gives analytical mean PL latency
  of 8.077932 ms at 100 MHz, 7.955733 ms at 102 MHz, and 7.838234 ms at
  104 MHz. These are planning projections, not frozen-five-file measurements.
- Phase 5A: after explicit checkpoint approval, added the independent-control
  32-lane production Hybrid MAC array without modifying `baseline/v1`. A fresh
  Vivado 2018.3 XSim run passed 1,040 cycles, 27,881 accepted lane commands,
  and 33,280 cycle-accurate lane checks across all four modes, clear priority,
  sticky overflow, and mixed simultaneous activity. Fresh OOC place/route
  passed the Phase 5A gates at 100 MHz (WNS +4.118 ns, internal register hold
  +0.051 ns) and 102 MHz (WNS +3.888 ns, internal register hold +0.051 ns),
  using 3,743 LUT, 2,176 FF, 32 DSP, and no BRAM. The leaf command latency is
  one cycle with II=1. The all-path OOC WHS is -1.226 ns on top-level input
  boundary paths without physical partition-pin locations; it is recorded but
  is not full-system timing evidence. Result: Phase 5A component gate PASS;
  no production-top, full-Zynq, BIT/HWH, five-file, or 100-audio measurement.
  Phase 5B image-v5 packing was subsequently approved and is complete.
- Phase 5B: added a separate image-v5 generator and immutable artifact set for
  32-row weight tiles and 32-lane parameter fields. The row-tile vector is
  `[10,10,2,7,7,3,7,7,6,7,7,4]`; GSU records are exactly 11,584 bits/181
  64-bit words and projection records are 2,240 bits/35 words, with no record
  padding. The independent oracle passed 7/7 tests, exhaustively comparing
  every weight lane and parameter field to the current raw source and paired
  v4 tiles. Vivado 2018.3 `xvlog` accepted both generated descriptor modules.
  The 1,056,224-byte image has SHA-256 `0a898aca19599f976b3988f92ff645b1490dc3ac470003683199e80b134f458a`.
  Weight-tile requests fall from 59,756 to 29,990 and parameter records from
  153 to 77, but the layout is not connected; direct cycle delta is zero,
  board latency is `NOT_MEASURED`, and resources are not applicable. Result:
  artifact/oracle gate PASS. The later continuous-run authorization superseded
  the old instruction to pause before Phase 5C.
- Phase 5C: connected image-v5 to a separate `memory_service_v5` and replaced
  serial 64-bit local reads with `memory_wide256`, a four-bank cache that keeps
  the external Zynq HP/AXI path at its native 64 bits while returning one
  aligned 256-bit weight tile per local read. Parameter records support
  unaligned 181/35-word starts by retaining each 256-bit read and consuming its
  four 64-bit lanes locally. The full 1,056,224-byte image, all 12 stages,
  first/last matrix tiles, all parameter payloads, held-response behavior,
  version/error/timeout/abort behavior, and LUT epoch passed Vivado XSim with
  57,163 checks. Fresh OOC routes passed at 100 MHz (WNS/WHS
  +0.710/+0.056 ns) and 102 MHz (+0.478/+0.104 ns), with 0 routing errors,
  28,411 LUT, 12,931/13,121 FF, 64 RAMB36 and 1 DSP. These OOC resources include
  a very wide standalone parameter response and are not a full-system total.
  Relative to the v4 two-read 16-row service, 29,990 weight requests now cost
  89,970 service cycles rather than 298,780 cycles, an analytical reduction of
  208,810 cycles (2.08810 ms at 100 MHz, 2.04716 ms at 102 MHz). The 77
  parameter records cost 17,814 cycles. Result: Phase 5C memory/interface gate
  PASS; no board latency exists until the 32-row controller/datapath and full
  block design also pass.
- Phase 5D: connected a separate production-v2 32-lane datapath while keeping
  every frozen `baseline/v1` byte unchanged.  The 32 physical Hybrid MACs are
  shared by raw, gate, membrane, and CDF owners; gate/membrane processing now
  covers eight four-lane groups and the serializer accepts 32-row tiles.  The
  deterministic Python oracle and connected Vivado XSim passed in 2,461
  cycles, checking 22 QBN state writes, 11 active events, 20 projection
  coefficients, 42 shared-requant parameter joins, all upper-16 datapath
  lanes, and randomized stalls.  Fresh 100 MHz OOC route passed setup and
  internal hold (WNS +0.086 ns, internal WHS +0.050 ns), with zero routing/DRC
  errors and 16,921 LUT, 16,913 FF, 52 DSP, and 2 RAMB18.  The OOC top-boundary
  WHS is -1.370 ns and is not full-system sign-off.  A fresh 102 MHz run failed
  setup at WNS -0.112 ns, so 100 MHz remains the only routed candidate for
  subsystem/full-Zynq integration.  Result: datapath functional and 100 MHz
  OOC gates PASS; 102 MHz gate FAIL; no BIT/HWH or board measurement.
- Phase 5E: connected image-v5, the four-bank 256-bit local memory service,
  the 32-row controller/context store, and the production-v2 32-lane datapath
  into the production subsystem.  The exact two-frame connected XSim passed
  1,396,690 checks across 60 jobs, 25 stage launches, and 33,186 sparse
  requests with all dense/sparse output checks unchanged.  A non-fallthrough
  descriptor-request register and registered controller-side PE fault view cut
  the two final congestion-dominated control paths; the live subsystem fault
  output remains immediate.  Fresh 100 MHz OOC synthesis/place/route passed
  with WNS +0.026 ns, internal register-to-register WHS +0.021 ns, zero
  routing/DRC errors, complete timing coverage, 34,328 LUT, 30,151 registers,
  53 DSP, 70 RAMB36, 2 RAMB18, and exactly 32 Hybrid MAC instances.  The OOC
  top-boundary WHS is -1.409 ns because partition-pin locations are absent and
  is not full-system sign-off.  The production `accelerator_top` timing-cut
  XSim also passed 7/7 checks.  Result: connected subsystem gate PASS at
  100 MHz; full-Zynq route, BIT/HWH, and board latency remain pending.
- Phase 5F synthesis: rebuilt the complete PYNQ-Z1 block design from the
  image-v5 sources and marked only the macro-only memory-map header as a
  global include; the generated procedural ROM headers remain ordinary
  Verilog headers. Full-design synthesis completed with no undefined-macro
  diagnostics. Post-synthesis resources are 45,881 LUT (86.24%), 42,568 FF
  (40.01%), 76 RAMB36 plus 7 RAMB18 (56.79% BRAM36 equivalent), and 65 DSP
  (29.55%). Because the deliberate 32-PE design is above the former 80% LUT
  planning reserve, synthesis, route, and artifact generation now share a
  fail-closed 90% per-resource ceiling; timing, coverage, route, and blocking
  DRC gates are unchanged. Post-synthesis WNS/WHS are -0.656/+0.045 ns and
  are not route evidence. Result: synthesis/resource gate PASS; route and
  board latency remain pending.
- Phase 6 runtime: changed the PYNQ runtime to parity-selected A/B contiguous
  buffers for magnitude/fullband input, spectrum input, and output. The host
  packs and flushes frame N+1 after frame N starts, overlapping that work with
  PL execution; DMA channels remain persistent and bounded. The 100-audio
  runner now accepts and verifies one host-precomputed STFT/magnitude bundle
  per `fileid_NNN`, and the fixed-five runner defaults to busy polling for the
  latency candidate. Python compile plus the targeted runtime/feature/board
  suite passed 28 tests. Result: host/runtime gate PASS; on-board A/B latency
  remains pending a timing-clean routed image.
- Phase 5G full route: the complete PYNQ-Z1 image-v5 design passed a fresh
  Vivado 2018.3 implementation at 100 MHz. Post-route WNS/WHS are
  +0.254/+0.014 ns, all routable nets are fully routed with zero failed or
  unrouted nets, and post-route DRC contains zero errors. Final resources are
  45,103 LUT, 42,315 FF, 76 RAMB36 plus 7 RAMB18, and 65 DSP. The gated route
  script emitted `ACCELERATOR_FULL_IMPLEMENTATION_ROUTE_PASS`; BIT/HWH were
  still deliberately withheld by that run. Result: the full-Zynq route gate
  passes and artifact generation is now authorized.
- Phase 7 host corpus: downloaded the exact 100 noisy WAV inputs already used
  by the prior board evaluation and computed STFT plus magnitude on the PC.
  The resulting `host_features_100_original_v2` contains 100 checksummed
  feature bundles. For example, `fileid_000` has source SHA-256
  `898d1a2f2411e0e006c7f7d034c2199002b3de132026b748fc5c66b045a437b2`,
  matching the prior original-corpus record. These bundles are data-preparation
  evidence only until they are verified and consumed by the board runner.
- Artifact release: the independent artifact gate reopened the routed DCP,
  rechecked setup, the 50 ps hold guardband, route completion, blocking DRC,
  and the 90% resource ceiling, then generated the same-project BIT/HWH pair.
  `zephyr_full.bit` is 4,045,679 bytes with SHA-256
  `731a67f7ba3ea853abb4bdde1e3e8799604120242ef225e114c9783b539bc04c`;
  `zephyr_full.hwh` is 585,282 bytes with SHA-256
  `d2256a64659029bb2d2a46d52010693959b795a012bcab9f8ed35adeb3bfbaa6`.
  The artifact gate retained WNS +0.254 ns, 0 setup failures, guardbanded WHS
  +0.014 ns, 0 hold failures, 0 unrouted/partially routed nets, and 0 blocking
  DRC findings. Result: BIT/HWH generation gate PASS; board programming and
  measurement remain pending.
- First board frame exposed a 32-row packing boundary that the original
  connected test had modeled incorrectly: stage 5 has 80 projection outputs,
  so the third 32-lane tile contains only 16 model lanes. The unmasked padding
  delayed `coefficient_last` to lane 31; the coefficient store correctly
  stopped at index 79 with first-fault source/code `0x05/0x65`. The controller
  now masks the final stage-5 tile to lanes 0..15, and the regression expects
  exact projection lengths 64/80/192/128 rather than `tiles * 32`. Fresh
  connected XSim passed 1,395,922 checks, 60 jobs, 25 stage launches, and
  33,186 sparse requests. The old bitstream remains rejected; OOC and full
  route must pass again before a replacement image can be generated.
- The first controller-side partial-tile correction passed function but caused
  unacceptable full-design placement churn and failed the guarded 100 MHz
  timing gate. A coefficient-store padding absorber and a serializer-local
  trim also passed function, but their fresh and incremental routes failed
  timing. The selected timing-local strategy restores the known-routed PE
  serializer byte-for-byte and adds a consumer-boundary adapter in
  `accelerator_top`: stage 5 index 79 is presented to the compact store with
  logical `last`, while physical padding indices 80..95 are drained without
  entering the store. The top regression passed all 16 timing-cut/adapter
  assertions, and the physical-tile connected subsystem regression passed
  1,396,690 checks across 60 jobs, 25 stage launches, and 33,186 sparse
  requests. Full synthesis and full-Zynq route remain mandatory before
  artifact replacement.
- Final validation scope: accepted the user-requested 100-audio rerun after
  all architecture, clock, feed, DMA, full-Zynq timing, and BIT/HWH gates pass.
  The primary run preserves the prior per-file and aggregate performance/audio
  fields. A separate fixed-five-plus-file081 profile reports per-state and
  per-stage load/compute/stall latency so profiling overhead is not mixed into
  the headline 100-audio throughput result. The full timing-clean route now
  exists and the release artifacts passed their independent gate; board
  programming, fixed-five gate, and the 100-audio run remain pending.
- Final store-boundary release: restored the routed 32-row serializer and moved
  stage-5 partial-tile handling to the coefficient-store consumer boundary.
  The production-top timing-cut regression passed 17 assertions, and the
  physical 32-row connected subsystem passed 1,396,690 checks across 60 jobs,
  25 stage launches, and 33,186 sparse requests. Fresh full-Zynq route at
  100 MHz passed with WNS +0.250 ns, guardbanded WNS 0.000 ns, guardbanded WHS
  +0.016 ns, raw physical hold +0.066 ns, zero timing failures, zero unrouted
  or partially routed nets, and zero DRC errors/critical warnings. Post-route
  resources are 45,188 LUT, 42,151 FF, 76 RAMB36 plus 7 RAMB18, and 65 DSP.
- Final artifact and programming gate: the matching BIT is 4,045,679 bytes
  with SHA-256 `b8f1d8b9f46335d92591000d7bd22b5b00cff534181a842e8171b97661af3d35`;
  the matching HWH is 585,282 bytes with SHA-256
  `d2605bab752bf4c23cf8c1ab17a889b831ef0e83eed79c8f356dc699285a7b2b`.
  The independent artifact gate and PYNQ programming both passed. The hardware
  remains at 100 MHz because the fresh 102 MHz production-v2 32-lane datapath
  route failed setup with WNS -0.112 ns; no failing higher-clock image was
  programmed.
- Fixed-five board result: file IDs 000/025/050/075/099 all passed with 23,137
  frames and 185.056 s evaluated audio. Aggregate mean/p50/p95/p99/max frame
  latency is 6.933/6.911/7.265/7.390/9.237 ms; frame/board/E2E RTF is
  0.867/1.677/1.774. Against the same host-precomputed baseline, mean frame,
  board RTF, and E2E RTF improve by 37.80%, 38.43%, and 37.57% respectively.
- Final 100-audio board result: all 100 files and 426,196 frames passed with
  3,408.768 s evaluated audio, contiguous per-file frame IDs, and final DMA
  channels idle/error-free. Aggregate mean/p50/p95/p99/max frame latency is
  6.942/6.916/7.329/7.475/27.509 ms; every file's p99 is below 8 ms and the
  worst per-file p99 is 7.704 ms. Frame/board/E2E RTF is
  0.868/1.740/1.861. Relative to `ec457b1`, mean frame latency improves 37.21%,
  board RTF 36.47%, and E2E RTF 34.77%. Mean SNR-delta and SI-SDR-delta change
  by -0.023 dB and -0.022 dB; PESQ/STOI remain blocked by missing packages.
- Corpus range correction: file030 exposed three host magnitudes above the
  signed-Q12 input range. The ingress quantizer now saturates instead of
  aborting, and 34 targeted runtime/profile/feature tests pass. Across the 100
  bundles, 34 values in 28 frames and 8 files saturate; the maximum is
  9.508294 versus Q12 maximum 7.999756. The resumed records before file030 are
  numerically unaffected because all their inputs were in range.
- Coherent profile result: 000/025/050/075/081/099 contributed 27,383 fully
  profiled frames. Hardware-cycle mean/p95/p99/max is
  6.464/6.778/6.883/7.665 ms and state-cycle conservation passes. The largest
  mutually exclusive PL states are subband run 2.485 ms/frame, subband load
  wait 2.043 ms, fullband load wait 1.156 ms, and fullband run 0.517 ms. The
  largest software-side bucket is frame retirement/fault checking at
  5.303 ms/frame; profile-mode board/E2E RTF is excluded from the headline
  because per-frame counter reads and timestamps add instrumentation overhead.
- Final verdict: the requested architecture changes make the PL datapath
  real-time at the p99 hop criterion, but the complete PYNQ application is not
  real-time because board-loop and E2E RTF remain above 1.0. The next measured
  target is the 5.303 ms/frame retirement/fault-check path, followed by the PL
  subband load/run states. Detailed outputs are under
  `rtl/reports/accelerator_realtime_image_v5_32pe_board_20260910/`.
- Fast-retirement runtime follow-up: the production path now treats successful
  output-DMA TLAST completion as the frame retirement fence, tracks frame IDs
  in software, omits successful-path fault polling, and skips the standalone
  state-cycle MMIO read unless diagnostics/profiling are enabled. Startup,
  timeout, final sticky-fault, final frame-sequence, and final DMA-idle/error
  checks remain. Targeted runtime/profile tests pass 29/29; the software suite
  excluding its pre-existing v4-image-version assertion passes 73/73. A fresh
  fixed-five PYNQ run passed all 23,137 frames and produced enhanced WAVs that
  are SHA-256 identical to the previous image-v5 result. Aggregate mean frame
  latency improved from 6.9333 to 6.8395 ms (1.35%), board-loop RTF improved
  from 1.6775 to 1.6616 (0.95%), and E2E RTF improved from 1.7744 to 1.7621
  (0.69%). The complete application therefore remains non-real-time. The
  earlier 5.303 ms profiled retirement bucket included coherent per-frame
  hardware-profile snapshot reads, so it was not pure retirement/fault-check
  overhead. Evidence is recorded in
  `rtl/reports/accelerator_realtime_image_v5_32pe_fast_retirement_20260910/`.
