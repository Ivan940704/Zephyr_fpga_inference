# Task: Complete PE Array operators and verify a small model pipeline

- Owner: Codex
- Status: completed with integration risks
- Branch: `codex/pe-array-small-model`
- Scope:
  - Preserve and reuse the verified `pe_requant_lane` and
    `pe_local_requant_bank_4lane` checkpoints.
  - Implement and independently verify every remaining module named by
    `rtl/pe_array/spec/MODULE_DEVELOPMENT_PLAN.md`: Hybrid MAC, 255-entry
    sigmoid LUT, membrane sequencer, output serializer, shared requant engine,
    spike decision, active-index writer/buffer, PE Array controller, and top.
  - Build a parameterized small-model harness representing
    LayerNorm-reference input -> fullband neural path -> linear projection ->
    DeepFilter complex MAC.
  - Use a reduced exhaustive configuration for detailed checking and a
    64->320->320->64 shape-preserving smoke configuration where practical.
  - Produce self-checking SystemVerilog tests and independent integer reference
    vectors; run Windows Vivado 2018.3 XSim and representative XC7Z020 OOC
    synthesis.
- Out of scope:
  - Inventing an FPGA LayerNorm numeric format. Upstream explicitly leaves its
    fixed-point mean/variance/epsilon/rounding contract undefined, so the TB
    reference performs LayerNorm and presents normalized INT8 to PL.
  - Modifying the dirty nested `upstream/` repository, building AXI DMA/block
    design, generating a bitstream, or claiming board RTF/audio quality.
  - Duplicating the array for three simultaneous subband engines.

## PYNQ-Z1 feasibility

- Placement: one PE Array and the neural/DeepFilter harness in PL RTL;
  LayerNorm remains PC/PS software according to the current boundary.
- Target part / clock: `xc7z020clg400-1`; 200 MHz PE OOC target. Future global
  FSM/AXI integration is 100 MHz and needs explicit CDC outside this task.
- Numeric formats and shapes: INT8 weights/activations/state, unsigned 8-bit
  sigmoid lambda, INT32 MAC/bias accumulators, 64-bit internal requant result.
  Fullband target shape is 64->320->320->64; reduced verification dimensions
  remain parameterized and keep the same two-GSU-plus-projection ordering.
- Parallel instances / lanes: exactly 16 shared Hybrid MAC PEs, one four-lane
  Local RQ Bank, one 255-entry LUT, one serializer, and one shared RQ lane.
  DeepFilter uses a time-multiplexed complex MAC; no three-array replication.
- Estimated LUT / FF / DSP / BRAM per instance: measured four-lane Local RQ is
  2,167 LUT / 1,732 FF / 16 DSP / 0 BRAM. Gate-A analytical estimate for the
  remaining fixed array is below 12k LUT / 10k FF / 24 additional DSP / 8
  BRAM36, excluding weight cache. This estimate must be replaced by intended-
  count OOC results; it is not a fit claim.
- Scaled total at intended instance count: preliminary compute-only estimate
  below 14.2k LUT / 11.8k FF / 40 DSP / 8 BRAM36. Weight storage is explicitly
  external/tiled and is not hidden in this number.
- Local buffer/state and ports: two 320-neuron INT8 recurrent-state vectors,
  two 320-bit spike/index paths, one 64-element projection vector, tags/FIFOs,
  and DeepFilter spectrum history. Target below 8 BRAM36 before weight cache;
  exact inference depends on implementation.
- DDR/AXI: standalone tests use deterministic testbench memory. Production
  weights remain in PS DDR and require the separate v3 source-major memory
  service; no DDR bandwidth result is claimed here.
- Estimated cycles / II / RTF: Hybrid MAC accepts one enabled accumulation
  per PE per cycle; local RQ accepts four results/cycle at II=1; shared RQ
  accepts one serialized result/cycle at II=1. Complete frame cycles are to be
  measured by the integration TB as 10,651 commands for the deterministic
  one-frame compute trace. This is a command count, not board RTF; board RTF
  remains unknown.
- Clock domains / CDC: all modules in this task are synchronous to one 200 MHz
  test clock. AXI/control CDC is outside this checkpoint.
- Hot spot: parameter bandwidth and weight cache dominate system feasibility;
  Local RQ already uses 16 DSP. A naive fully resident fullband weight store
  does not fit PYNQ-Z1 BRAM.
- Fallback: retain one array, reduce active MAC lanes, time-multiplex Local RQ,
  use stage/tile ping-pong weight cache, and run compute at 100 MHz if 200 MHz
  routing does not close.
- Evidence level: repository facts, independent Python vectors, Windows Vivado
  2018.3 XSim, and representative post-synthesis OOC. No implementation or
  board evidence exists.
- Feasibility: `PASS WITH RISKS` for one time-multiplexed compute array;
  full integrated model remains `UNKNOWN` until memory/top implementation.

## Acceptance checks

- [x] Every named PE Array leaf/operator has RTL, self-checking TB, and a clear
  completion/evidence record.
- [x] Membrane sequencer contains no dedicated multiplier/MAC/requant datapath.
- [x] Spike path writes known neuron indices directly and never rescans a full
  spike vector.
- [ ] A fully connected reduced GSU datapath compares every postprocess result
  under randomized stalls. Leaf support stalls/reset pass, but the full-shape
  command stream currently connects matrix phases through the Python reference.
- [x] Shape-preserving 64->320->320->64 smoke test completes with deterministic
  vectors and reports cycles/read/operation counts.
- [x] DeepFilter order 1/3/5 complex arithmetic is covered.
- [x] Representative intended-count XC7Z020 OOC utilization/timing is recorded
  without extrapolating to board performance.
- [x] README, architecture, decision, handoff, PROJECT_STATUS, and version
  history are updated without modifying unrelated `upstream/` work.
