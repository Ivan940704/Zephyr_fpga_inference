# Sparse memory v1 status

- Baseline: `sequential-v4-sparse-load-v1`
- Target: PYNQ-Z1 `xc7z020clg400-1`, 100 MHz
- Development boundary: `sparse_memory_v1/` only
- Imported repository commit: `a73c884d5514a3e6d812339836b2ff4b24008015`
- Completed checkpoints: CP0, CP1, CP2, CP3, CP4, CP5, CP6, and CP7
- Current checkpoint: CP7 registered internal-fault abort boundary frozen;
  accelerator-top promotion and board work remain outside this subtree
- CP0 evidence: all 47 frozen imports match their source SHA-256 values and
  the isolated dense runner reproduces all 12 stages at 1,050,544 B/frame
- CP2 evidence: the trace/oracle regression fixes dense traffic at
  1,050,544 B/frame, reset-epoch LUT traffic at 2,040 B, and zero-active
  traffic at 181,680 B/frame
- CP3 simulation evidence: XSim PASS, 369 checks covering all 12 stages,
  4/3/2-context unions, descriptor/list backpressure, missing-list policy,
  output backpressure, ownership faults, response faults, and reset-only
  fail-closed behavior
- CP3 implementation evidence: XC7Z020 OOC route at 100 MHz reports routed
  WNS 2.154 ns, 0 BRAM, 0 DSP, and 0 unrouted nets
- CP4/CP6 service simulation evidence: Vivado 2018.3 XSim PASS, 86,053 checks
  over the real v4 image and all 12 dense stages plus canonical sparse scatter,
  mandatory matrix and full parameter residency, stale-hole rejection,
  response backpressure, 4 KiB burst boundaries, RID/RRESP/RLAST faults,
  timeout, abort, and partial-load non-publication
- CP4 host evidence: 18 reference tests pass, including provenance checks for
  the renamed `memory.v` DMA and exact copied v4 geometry/table
- CP5/CP6 connected evidence: Vivado 2018.3 XSim PASS with 12,446,067 checks;
  dense and sparse modes each execute two frames, all 12 stages, and 60 jobs
  through the frozen PE/controller and locally renamed context-store path
- CP5 traffic evidence: two dense frames transfer 2,101,088 stage bytes and
  the connected non-dense sparse trace transfers 1,052,208 stage bytes; every
  successful snapshot matches both accepted AXI R beats times eight and an
  independent frozen-geometry/union-count oracle
- CP6 service OOC evidence: XC7Z020 route at 100 MHz reports WNS 0.206 ns,
  WHS 0.025 ns, 9,303/9,303 fully routed nets, 0 unconstrained internal
  endpoints, 7,520 LUTs, 8,818 registers, 64 RAMB36 primitives, and 4 DSP48s
- CP6 isolated-subsystem route evidence: XC7Z020 route at 100 MHz reports WNS
  0.151 ns, WHS 0.010 ns, 41,231/41,231 fully routed nets, 0 unconstrained
  internal endpoints, 25,096 slice LUTs, 27,527 registers, 68 RAMB36 plus 2
  RAMB18 primitives, and 40 DSP48s; all resource classes are below 80 percent
- CP6 host evidence: all 88 CP0--CP6 isolated tests pass; the connected
  reference also
  covers descriptor `present`, empty commit, response backpressure, sampled
  image base, planner-time mutation exclusion, global-clear exclusion, sticky
  faults, AXI response failure, and accepted-burst abort
- CP6 report evidence: all 5 evidence-verification tests pass over the exact
  41-file report bundle; CP3 planner OOC evidence is hash-stable and reused
  unchanged
- CP7 connected evidence: Vivado 2018.3 XSim passes 12,446,068 checks with
  dense and sparse modes each executing two frames, all 12 stages, and 60
  jobs.  A raw PE protocol fault blocks external admission in the same cycle,
  while sparse-memory and controller abort consume the registered boundary on
  the next cycle; dense/sparse stage traffic remains 2,101,088/1,052,208 B.
- Evidence not available: bitstream generation, PYNQ-Z1 board measurements,
  and accelerator-top timing closure; CP7 does not claim any of these

The existing production memory, accelerator top, global manifests, runners,
and reports are not part of this isolated checkpoint and are not modified by
the CP7 commit.
