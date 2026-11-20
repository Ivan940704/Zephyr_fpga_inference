# PE Array formal baseline v1

## Purpose and scope

This directory is a byte-preserving archive of the formal PE Array baseline.
It contains exactly eleven accepted arithmetic/functional leaf modules plus
one separately classified PE-subsystem integration wrapper, together with
their directly matching verification and implementation evidence.

### Accepted arithmetic/functional leaf modules

1. `pe_requant_lane`
2. `pe_local_requant_bank_4lane`
3. `pe_hybrid_mac`
4. `pe_sigmoid_lut_255`
5. `pe_gate_postprocess`
6. `pe_membrane_sequencer`
7. `pe_output_serializer`
8. `pe_shared_requant_engine`
9. `pe_spike_decision`
10. `pe_active_index_writer`
11. `pe_cdf_sequencer`

### Accepted integration wrapper

- `pe_array_datapath`

`pe_array_datapath` is not a twelfth arithmetic/functional leaf. Formal leaf
membership remains exactly the eleven modules listed above.

The original source files remain in place.  The first three archived modules
retain their approved `.sv` source bytes; `pe_sigmoid_lut_255` is archived as
the separately verified pure-Verilog `.v` checkpoint, and
`pe_gate_postprocess`, `pe_membrane_sequencer`, `pe_output_serializer`,
`pe_shared_requant_engine`, `pe_spike_decision`, and
`pe_active_index_writer` are archived as their approved Verilog-2001 `.v`
checkpoints. `pe_cdf_sequencer` and the separately classified
`pe_array_datapath` integration wrapper are likewise archived as their
approved Verilog-2001 `.v` checkpoints.
This archive does not perform or imply a language/extension migration of the
first three modules. Any such migration requires a separate compile,
simulation, synthesis, and timing checkpoint.

`pe_array_datapath` is the sole accepted integration wrapper. No
layer/tile/workload controller FSM, full accelerator top, GSN cell,
`pe_array_top`, memory/AXI subsystem, active-index storage, experimental RTL,
or other production system module is part of baseline v1.
Their presence elsewhere in the repository must not be interpreted as
baseline acceptance. In particular, no experimental `.sv` sigmoid, gate
postprocess, spike-decision, or active-index-writer implementation is included.

## Git provenance

- Archive source worktree HEAD at creation:
  `0d0ea90bfb0214ddf3234b30ec6ab16809eadb43`
  (`Complete bit-exact GSN neuron cell`, 2026-09-01T20:30:09+08:00).
- The archived source paths were clean relative to the index when copied.
- `pe_requant_lane.sv` last-source commit:
  `124a7718c6fb212a6da76d0bc198702fac12fb6c`
  (`Establish verified Zephyr FPGA project baseline`).
- `pe_local_requant_bank_4lane.sv` and `pe_hybrid_mac.sv` last-source commit:
  `688ff9b09f85560a580706ba2905cbb6617eb408`
  (`Complete PE operators and full-shape model smoke`).
- `pe_sigmoid_lut_255.v` verified checkpoint commit:
  `23709cf3abf1f251d61535b9246db4f4c3099b74`
  (`Add verified four-lane resident sigmoid LUT`) on
  `codex/pe-sigmoid-lut-255`.
- `pe_gate_postprocess.v` verified checkpoint commit:
  `b7671e0897565f2958a46fd50f83ac0aed3fe56d`
  (`Add verified PE gate postprocess checkpoint`) on
  `codex/memory-design-guidelines`.
- `pe_membrane_sequencer.v` verified checkpoint commit:
  `838c5670fe5b9f0b718a3eb33c1ddf023a8abb02`
  (`Add verified membrane sequencer checkpoint`) on
  `codex/memory-design-guidelines`.
- `pe_output_serializer.v` verified checkpoint commit:
  `6cab9a963de17e1be7b9526db5bf8a2bdeca9389`
  (`Add verified PE output serializer checkpoint`) on
  `codex/memory-design-guidelines`.
- `pe_shared_requant_engine.v` verified checkpoint commit:
  `4bf3f7c22c15c1582a8a24a52cd12df03d07ec4e`
  (`Add verified shared requant engine checkpoint`) on
  `codex/memory-design-guidelines`.
- `pe_spike_decision.v` verified checkpoint commit:
  `3457166fdacdf85d1a8da3bf18d5998cc7a868f3`
  (`Add verified PE spike decision checkpoint`) on
  `codex/memory-design-guidelines`.
- `pe_active_index_writer.v` verified checkpoint commit:
  `400b3d2a73deaa7a9cad337f15af00de70cca293`
  (`Add verified PE active index writer checkpoint`) on
  `codex/memory-design-guidelines`.
- `pe_cdf_sequencer.v` verified checkpoint commit:
  `169c4c033c397982c7cb3187834505a667c74ca6`
  (`Add verified PE CDF sequencer checkpoint`) on
  `codex/memory-design-guidelines`.
- `pe_array_datapath.v` verified integration-wrapper checkpoint commit:
  `645a7659780b8b58a1ba0c627f0f17325acb4c90`
  (`Add verified PE array datapath integration checkpoint`) on
  `codex/memory-design-guidelines`. Its archived RTL SHA-256 is
  `bdde93915e380e910b6504cb8f9ec2439d8cd95fbd684513bd15af1426ed3954`.
  The connected build used only the eleven archived baseline leaf RTL files;
  this promotion does not modify or replace any accepted leaf RTL bytes.
- Corrective gate-routing erratum (2026-09-07): the archived integration
  wrapper now routes controller gate 0 (forget) through the sigmoid collector
  and gate 1 (cell candidate) through the signed `i_t` collector.  A connected
  sequential-v4 regression checks all 320 first-layer zero-input state bytes
  against the independently lowered integer model before the normal two-frame
  subsystem workload.  The corrected wrapper SHA-256 is
  `2fe7252bcff156f6d1a78fe073b8993ee8a661a9dfa949d67f9a78226e16861e`.
- Corrective recurrent-membrane erratum (2026-09-07): CX and CELL raw
  accumulator phases are separated, and each CX Local-RQ response is held
  until the matching CELL raw value has been snapshotted.  This prevents a
  nonzero CX term from being included in the CELL requantizer input.  The
  connected two-frame regression checks all 640 first-layer state bytes
  against the independently lowered integer model.  The corrected membrane
  sequencer SHA-256 is
  `4b6549c37f53759ef193f9bf297c3132a1ed7a01490ef6a4a779fbcc17907de2`;
  the corresponding wrapper SHA-256 is
  `14707a8126a1ede0625f592a94053fbb27a7c8bac72470c3e9c838f6ae40e93b`.
- The initial three-module archive was created without source deletion or
  source move. Approved updates likewise copy artifacts without changing their
  original source locations or the verified RTL bytes.

## Accepted leaf evidence

All timing and utilization numbers below are Vivado 2018.3 post-synthesis
out-of-context results for `xc7z020clg400-1` with a 5.000 ns / 200 MHz
constraint.  They are not placed-and-routed or board measurements.

| Module | Behavioral evidence | Latency / II | LUT | FF | DSP48E1 | BRAM | WNS |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| `pe_requant_lane` | 5,155/5,155 deterministic vectors PASS | 9 cycles / II=1 | 475 | 431 | 4 | 0 | +0.263 ns |
| `pe_local_requant_bank_4lane` | 2,112 packets and 4,149 active results PASS | 9 cycles / bank II=1; up to 4 results/cycle | 2,167 | 1,732 | 16 | 0 | +0.263 ns |
| `pe_hybrid_mac` | 4,109/4,109 mixed-mode commands PASS | 1-cycle command-to-accumulate / II=1 | 87 | 68 | 1 | 0 | +0.270 ns |
| `pe_sigmoid_lut_255` | 4,080 legal plus 8 defensive vectors PASS; all 8 x 255 table entries checked twice | 1 cycle / II=1 four-neuron packet | 72 | 51 | 0 | 2 x RAMB18E1 | +0.565 ns |
| `pe_gate_postprocess` | 1,520 packets / 5,007 active lane results bit-exact PASS | 6 cycles from INPUT, 5 from RECURRENT / protocol II=2 | 1,153 | 1,605 | 0 | 0 | +0.185 ns |
| `pe_membrane_sequencer` | Connected XSim bit-exact PASS: 96 tiles / 663 active results; 64 real-parameter plus 32 stress tiles | `result_valid` 31 cycles; no-stall handshake 32 cycles / tile II=33 | 2,934 | 2,058 | 0 | 0 | +0.227 ns |
| `pe_output_serializer` | Unit XSim PASS: 519 tiles / 4,014 outputs; connected membrane handshake PASS: 96 tiles / 663 outputs | 1 cycle / output II=1; full-tile load II=17 | 284 | 806 | 0 | 0 | +0.152 ns |
| `pe_shared_requant_engine` | Python 3,500 vectors, Unit XSim 3,500 vectors, and serializer-connected XSim 96 tiles / 486 outputs PASS | 14 cycles / II=1 | 739 | 773 | 4 | 0 | +0.263 ns |
| `pe_spike_decision` | Exhaustive 256-encoding unit, writer-connected, and shared-RQ-connected XSim PASS | 0 registered cycles / II=1 | 3 | 0 | 0 | 0 | +2.930 ns virtual |
| `pe_active_index_writer` | Unit, spike-decision-connected, and behavioral-memory-sink/backpressure XSim PASS | 0 registered cycles / II=1 | 0 | 0 | 0 | 0 | +4.027 ns virtual |
| `pe_cdf_sequencer` | Python bit-exact and connected 16-PE XSim PASS; all legal cases overflow-free | order 1/3/5: `result_valid` 3/7/11 cycles; group II=4/8/12 | 327 | 239 | 0 | 0 | +0.236 ns |

## Accepted integration-wrapper evidence

`pe_array_datapath` is accepted as a functional and structural integration
wrapper, not as a new arithmetic leaf and not as a 200 MHz timing-closed
subsystem.

Connected integer/Python reference and XSim verification PASS. The retained
XSim run completed in 2,330 cycles with 11 dense-state outputs, 6 active-index
writes, 12 Linear/CDF coefficient outputs, 23 Shared-RQ parameter handshakes,
and 8 gate-bias handshakes. It exercised the complete GSU-to-spike flow and
Linear-to-CDF flow, with owner transitions under randomized parameter delay
and sink backpressure.

Hierarchy inspection found exactly 16 `pe_hybrid_mac` instances, one
four-lane `pe_local_requant_bank_4lane`, one
`pe_shared_requant_engine`, five total physical `pe_requant_lane`
instances, and one instance of every other accepted leaf. It found no
active-index buffer, controller, `pe_array_top`, GSN cell, dedicated complex
multiplier, or duplicated arithmetic datapath.

The fully routed 100 MHz OOC implementation has 16,343 fully routed nets and
zero route-error nets. Internal register-to-register timing passes with setup
WNS **+0.727 ns** and hold WHS **+0.056 ns**; overall setup WNS is **+0.254
ns**. The standalone OOC boundary hold check is not clean: overall WHS is
**-1.368 ns** on a top-input boundary path and Vivado reports
`timing_constraints_met=0`. Therefore this is an accepted **100 MHz internal
register-to-register setup/hold result**, not a clean standalone wrapper
boundary timing sign-off.

Post-route utilization is **10,225 LUT / 10,573 FF / 36 DSP48E1 / two
RAMB18E1**, with zero RAMB36E1, distributed RAM/LUTRAM, or multiplier macros.
The wrapper hierarchy row attributes 150 LUT and 2,568 FF to integration glue
and zero DSP/BRAM/LUTRAM; all arithmetic DSPs and sigmoid BRAMs are accounted
for by the eleven frozen leaves.

**200 MHz is not a formally verified operating point for
`pe_array_datapath`.** After the production controller FSM and memory
subsystem are integrated, top-level placement/routing and complete setup/hold
closure must be repeated with real system boundaries and constraints.

## Baseline status and handoff

- Formal arithmetic/functional leaf membership remains exactly the eleven
  modules listed above, plus the separately classified
  `pe_array_datapath` integration wrapper.
- `pe_sigmoid_lut_255` uses four parallel lookup lanes, eight resident tables,
  two `RAMB18E1` primitives, and a common table selection per four-neuron
  packet.
- `pe_gate_postprocess` uses one pending INPUT packet to pair the following
  RECURRENT packet, then performs signed add, fixed eight-bit guard rounding,
  and saturation to signed INT8. It instantiates no requant lane, Local RQ,
  sigmoid, multiplier, DSP, or memory primitive.
- The gate postprocess OOC checkpoint meets 200 MHz, but its WNS is only
  **+0.185 ns**. Full integration and place-and-route must re-confirm timing.
- The accepted gate postprocess retains a **64-bit intermediate datapath**.
  Any future width reduction is a separate resource-optimization checkpoint
  and must first prove bit-exactness over the formal model domain.
- `pe_membrane_sequencer` reuses the existing sixteen Hybrid MAC PEs, four-lane
  Local RQ Bank, and single gate-postprocess instance. Its early accumulator
  clear is separate from all DIRECT commands, and ownership is retained until
  pending Local RQ and postprocess state is drained.
- The sequencer-only checkpoint uses **2,934 LUT / 2,058 FF**, with zero DSP,
  BRAM, LUTRAM, or multiplier macro, and meets 200 MHz at **WNS +0.227 ns**.
  Its LUT/FF cost is primarily sixteen-lane temporary state, routing, and
  control. Resource optimization is deferred until complete-integration
  profiling and must not alter this accepted design in the meantime.
- `pe_output_serializer` contains one tile register bank and one sixteen-bit
  pending mask, skips inactive lanes, and emits active lanes in ascending
  order with output II=1. `last_out` marks the final valid neuron of the
  logical vector, not every tile boundary.
- The serializer retains registered selected-lane control to split the
  lowest-set-bit selector from the value/tag mux critical path. Its checkpoint
  uses **284 LUT / 806 FF**, zero DSP, BRAM, LUTRAM, or multiplier macro, and
  meets 200 MHz at **WNS +0.152 ns**. Complete integration and place-and-route
  must re-confirm 200 MHz timing.
- `pe_shared_requant_engine` instantiates exactly one physical baseline
  `pe_requant_lane`; QBN and Linear share it and may alternate every cycle.
  Bias, operation kind, index, tag, and logical-last metadata cross the
  nine-cycle lane through its opaque tag, followed by one II=1 bias/R8/
  saturation pipeline. The accepted total latency is 14 cycles.
- The shared requant checkpoint uses **739 LUT / 773 FF / 4 DSP48E1**, zero
  BRAM or LUTRAM, and meets 200 MHz at **WNS +0.263 ns**. Hierarchical netlist
  inspection found exactly one `pe_requant_lane`; there is no parameter RAM,
  FIFO, scoreboard, CDF branch, or second requant datapath.
- `pe_spike_decision` applies the fixed inclusive predicate
  `signed(state_q) >= 0`; zero spikes. Ordinary non-spikes are consumed without
  an output transaction, while a terminal non-spike is emitted so the writer
  can finalize without writing an index. It passes index, tag, and logical-last
  metadata unchanged and never forms a complete spike vector.
- Exhaustive unit, writer-connected, and shared-RQ-connected XSim all PASS.
  Linear results explicitly bypass the QBN-only spike path. The accepted leaf
  has zero registered latency, II=1, **3 LUT / 0 FF / 0 DSP / 0 BRAM/LUTRAM**,
  and virtual-200-MHz OOC **WNS +2.930 ns**. Complete integration and
  place-and-route must re-confirm the combinational ready/event path.
- `pe_active_index_writer` is a pure combinational atomic command adapter.
  `spike` becomes the write action, `last` becomes the finalize action, and a
  terminal spike carries write plus finalize in the same ready/valid
  handshake. Index and opaque tag metadata pass through unchanged.
- Active count, index storage, capacity/full state, and the write pointer all
  remain memory-subsystem responsibilities. The writer contains no register,
  counter, FIFO, RAM, complete spike vector, or index storage. Unit,
  spike-decision-connected, and behavioral-memory-sink XSim all PASS. The
  accepted leaf has zero registered latency, II=1, zero LUT/FF/DSP/BRAM/LUTRAM,
  and virtual-200-MHz OOC **WNS +4.027 ns**.
- `pe_cdf_sequencer` time-multiplexes the existing sixteen Hybrid MAC PEs for
  CDF. Every two PEs form the signed-INT32 real/imaginary accumulators for one
  complex bin, so a group processes up to eight bins under a partial-bin mask.
  Each order-1/3/5 tap uses two `MODE_DENSE` phases: `Xr*Cr` / `Xr*Ci`, then
  `Xi*(-Ci)` / `Xi*Cr`. The output receives no requantization, rounding, or
  saturation.
- Connected hierarchy inspection found exactly sixteen formal-baseline
  `pe_hybrid_mac` instances and one sequencer. The sequencer itself contains
  no dedicated complex multiplier, DSP, BRAM, LUTRAM, requantizer, or wide
  accumulation datapath. Sequencer-only OOC uses **327 LUT / 239 FF** and
  passes 200 MHz at **WNS +0.236 ns**.
- Python bit-exact and connected 16-PE XSim both PASS for order 1/3/5, causal
  zero padding, `Ci=-127`, full/partial groups, randomized backpressure, and
  aligned metadata. All legal CDF cases keep Hybrid PE overflow at zero.
- CDF `result_valid` latency is 3/7/11 cycles and no-stall group II is 4/8/12
  cycles for orders 1/3/5 respectively. The OOC timing margin is positive but
  small, so complete integration and place-and-route must re-confirm 200 MHz.
- `pe_array_datapath` supplies only one-hot physical-resource ownership,
  mux/demux and metadata adaptation, atomic joins/forks, outstanding/drain
  accounting, collector/serializer context, backpressure routing, assertions,
  and overflow aggregation. It contains no layer/tile/workload controller FSM,
  RAM or memory subsystem, FIFO, scoreboard, new arithmetic unit, requantizer,
  or multiplier.
- Connected bit-exact functional verification and structural hierarchy checks
  PASS. The accepted 100 MHz result is limited to internal
  register-to-register setup/hold timing; standalone OOC boundary hold remains
  unclean, and 200 MHz is not an accepted connected operating point.
- The accepted leaf evidence and matching connected/post-route wrapper
  evidence are archived below.
- No additional arithmetic leaf or system module is implicitly approved, and
  downstream development must not depend on any non-baseline RTL without a
  separate checkpoint and explicit approval.

## Source-to-archive mapping

Every row maps an original repository path to its exact archived copy.

| Source path | Archive path |
| --- | --- |
| `rtl/pe_array/rtl/arithmetic/pe_requant_lane.sv` | `rtl/pe_array/baseline/v1/rtl/arithmetic/pe_requant_lane.sv` |
| `rtl/pe_array/rtl/arithmetic/pe_local_requant_bank_4lane.sv` | `rtl/pe_array/baseline/v1/rtl/arithmetic/pe_local_requant_bank_4lane.sv` |
| `rtl/pe_array/rtl/pe/pe_hybrid_mac.sv` | `rtl/pe_array/baseline/v1/rtl/pe/pe_hybrid_mac.sv` |
| `rtl/pe_array/rtl/nonlinear/pe_sigmoid_lut_255.v` | `rtl/pe_array/baseline/v1/rtl/nonlinear/pe_sigmoid_lut_255.v` |
| `rtl/pe_array/rtl/postprocess/pe_gate_postprocess.v` | `rtl/pe_array/baseline/v1/rtl/postprocess/pe_gate_postprocess.v` |
| `rtl/pe_array/rtl/pe/pe_membrane_sequencer.v` | `rtl/pe_array/baseline/v1/rtl/pe/pe_membrane_sequencer.v` |
| `rtl/pe_array/rtl/stream/pe_output_serializer.v` | `rtl/pe_array/baseline/v1/rtl/stream/pe_output_serializer.v` |
| `rtl/pe_array/rtl/stream/pe_shared_requant_engine.v` | `rtl/pe_array/baseline/v1/rtl/stream/pe_shared_requant_engine.v` |
| `rtl/pe_array/rtl/index/pe_spike_decision.v` | `rtl/pe_array/baseline/v1/rtl/index/pe_spike_decision.v` |
| `rtl/pe_array/rtl/index/pe_active_index_writer.v` | `rtl/pe_array/baseline/v1/rtl/index/pe_active_index_writer.v` |
| `rtl/pe_array/rtl/pe/pe_cdf_sequencer.v` | `rtl/pe_array/baseline/v1/rtl/pe/pe_cdf_sequencer.v` |
| `rtl/pe_array/rtl/top/pe_array_datapath.v` | `rtl/pe_array/baseline/v1/rtl/top/pe_array_datapath.v` |
| `rtl/pe_array/constraints/pe_array_datapath_100mhz.xdc` | `rtl/pe_array/baseline/v1/constraints/pe_array_datapath_100mhz.xdc` |
| `rtl/pe_array/tb/unit/tb_pe_requant_lane.sv` | `rtl/pe_array/baseline/v1/tb/unit/tb_pe_requant_lane.sv` |
| `rtl/pe_array/tb/unit/tb_pe_local_requant_bank_4lane.sv` | `rtl/pe_array/baseline/v1/tb/unit/tb_pe_local_requant_bank_4lane.sv` |
| `rtl/pe_array/tb/unit/tb_pe_hybrid_mac.sv` | `rtl/pe_array/baseline/v1/tb/unit/tb_pe_hybrid_mac.sv` |
| `rtl/pe_array/tb/unit/tb_pe_sigmoid_lut_255.v` | `rtl/pe_array/baseline/v1/tb/unit/tb_pe_sigmoid_lut_255.v` |
| `rtl/pe_array/tb/unit/tb_pe_gate_postprocess.v` | `rtl/pe_array/baseline/v1/tb/unit/tb_pe_gate_postprocess.v` |
| `rtl/pe_array/tb/vectors/pe_requant_lane_vectors.txt` | `rtl/pe_array/baseline/v1/tb/vectors/pe_requant_lane_vectors.txt` |
| `rtl/pe_array/tb/vectors/pe_local_requant_bank_4lane_vectors.txt` | `rtl/pe_array/baseline/v1/tb/vectors/pe_local_requant_bank_4lane_vectors.txt` |
| `rtl/pe_array/tb/vectors/pe_hybrid_mac_vectors.txt` | `rtl/pe_array/baseline/v1/tb/vectors/pe_hybrid_mac_vectors.txt` |
| `rtl/pe_array/tb/vectors/pe_sigmoid_lut_255_tables.hex` | `rtl/pe_array/baseline/v1/tb/vectors/pe_sigmoid_lut_255_tables.hex` |
| `rtl/pe_array/tb/vectors/pe_gate_postprocess_vectors.hex` | `rtl/pe_array/baseline/v1/tb/vectors/pe_gate_postprocess_vectors.hex` |
| `rtl/pe_array/tb/vectors/pe_gate_postprocess_vectors.count` | `rtl/pe_array/baseline/v1/tb/vectors/pe_gate_postprocess_vectors.count` |
| `rtl/pe_array/reference/pe_requant_lane_reference.py` | `rtl/pe_array/baseline/v1/reference/pe_requant_lane_reference.py` |
| `rtl/pe_array/reference/pe_local_requant_bank_4lane_reference.py` | `rtl/pe_array/baseline/v1/reference/pe_local_requant_bank_4lane_reference.py` |
| `rtl/pe_array/reference/pe_hybrid_mac_reference.py` | `rtl/pe_array/baseline/v1/reference/pe_hybrid_mac_reference.py` |
| `rtl/pe_array/reference/pe_sigmoid_lut_255_reference.py` | `rtl/pe_array/baseline/v1/reference/pe_sigmoid_lut_255_reference.py` |
| `rtl/pe_array/reference/pe_gate_postprocess_reference.py` | `rtl/pe_array/baseline/v1/reference/pe_gate_postprocess_reference.py` |
| `rtl/pe_array/scripts/sim/run_pe_requant_lane_xsim.tcl` | `rtl/pe_array/baseline/v1/scripts/sim/run_pe_requant_lane_xsim.tcl` |
| `rtl/pe_array/scripts/sim/run_pe_local_requant_bank_4lane_xsim.tcl` | `rtl/pe_array/baseline/v1/scripts/sim/run_pe_local_requant_bank_4lane_xsim.tcl` |
| `rtl/pe_array/scripts/sim/run_pe_hybrid_mac_xsim.tcl` | `rtl/pe_array/baseline/v1/scripts/sim/run_pe_hybrid_mac_xsim.tcl` |
| `rtl/pe_array/scripts/sim/run_pe_sigmoid_lut_255_xsim.tcl` | `rtl/pe_array/baseline/v1/scripts/sim/run_pe_sigmoid_lut_255_xsim.tcl` |
| `rtl/pe_array/scripts/sim/run_pe_gate_postprocess_xsim.tcl` | `rtl/pe_array/baseline/v1/scripts/sim/run_pe_gate_postprocess_xsim.tcl` |
| `rtl/pe_array/scripts/synth/synth_pe_requant_lane_ooc.tcl` | `rtl/pe_array/baseline/v1/scripts/synth/synth_pe_requant_lane_ooc.tcl` |
| `rtl/pe_array/scripts/synth/synth_pe_local_requant_bank_4lane_ooc.tcl` | `rtl/pe_array/baseline/v1/scripts/synth/synth_pe_local_requant_bank_4lane_ooc.tcl` |
| `rtl/pe_array/scripts/synth/synth_pe_hybrid_mac_ooc.tcl` | `rtl/pe_array/baseline/v1/scripts/synth/synth_pe_hybrid_mac_ooc.tcl` |
| `rtl/pe_array/scripts/synth/synth_pe_sigmoid_lut_255_ooc.tcl` | `rtl/pe_array/baseline/v1/scripts/synth/synth_pe_sigmoid_lut_255_ooc.tcl` |
| `rtl/pe_array/scripts/synth/synth_pe_gate_postprocess_ooc.tcl` | `rtl/pe_array/baseline/v1/scripts/synth/synth_pe_gate_postprocess_ooc.tcl` |
| `rtl/pe_array/constraints/pe_requant_lane_200mhz.xdc` | `rtl/pe_array/baseline/v1/constraints/pe_requant_lane_200mhz.xdc` |
| `rtl/pe_array/constraints/pe_local_requant_bank_4lane_200mhz.xdc` | `rtl/pe_array/baseline/v1/constraints/pe_local_requant_bank_4lane_200mhz.xdc` |
| `rtl/pe_array/constraints/pe_hybrid_mac_200mhz.xdc` | `rtl/pe_array/baseline/v1/constraints/pe_hybrid_mac_200mhz.xdc` |
| `rtl/pe_array/constraints/pe_sigmoid_lut_255_200mhz.xdc` | `rtl/pe_array/baseline/v1/constraints/pe_sigmoid_lut_255_200mhz.xdc` |
| `rtl/pe_array/constraints/pe_gate_postprocess_200mhz.xdc` | `rtl/pe_array/baseline/v1/constraints/pe_gate_postprocess_200mhz.xdc` |
| `rtl/pe_array/reports/pe_requant_lane/check_timing_post_synth.rpt` | `rtl/pe_array/baseline/v1/reports/pe_requant_lane/check_timing_post_synth.rpt` |
| `rtl/pe_array/reports/pe_requant_lane/metrics_post_synth.txt` | `rtl/pe_array/baseline/v1/reports/pe_requant_lane/metrics_post_synth.txt` |
| `rtl/pe_array/reports/pe_requant_lane/reference_check.txt` | `rtl/pe_array/baseline/v1/reports/pe_requant_lane/reference_check.txt` |
| `rtl/pe_array/reports/pe_requant_lane/summary.md` | `rtl/pe_array/baseline/v1/reports/pe_requant_lane/summary.md` |
| `rtl/pe_array/reports/pe_requant_lane/timing_paths_post_synth.rpt` | `rtl/pe_array/baseline/v1/reports/pe_requant_lane/timing_paths_post_synth.rpt` |
| `rtl/pe_array/reports/pe_requant_lane/timing_summary_post_synth.rpt` | `rtl/pe_array/baseline/v1/reports/pe_requant_lane/timing_summary_post_synth.rpt` |
| `rtl/pe_array/reports/pe_requant_lane/utilization_post_synth.rpt` | `rtl/pe_array/baseline/v1/reports/pe_requant_lane/utilization_post_synth.rpt` |
| `rtl/pe_array/reports/pe_requant_lane/xsim_simulate.txt` | `rtl/pe_array/baseline/v1/reports/pe_requant_lane/xsim_simulate.txt` |
| `rtl/pe_array/reports/pe_local_requant_bank_4lane/check_timing_post_synth.rpt` | `rtl/pe_array/baseline/v1/reports/pe_local_requant_bank_4lane/check_timing_post_synth.rpt` |
| `rtl/pe_array/reports/pe_local_requant_bank_4lane/metrics_post_synth.txt` | `rtl/pe_array/baseline/v1/reports/pe_local_requant_bank_4lane/metrics_post_synth.txt` |
| `rtl/pe_array/reports/pe_local_requant_bank_4lane/reference_check.txt` | `rtl/pe_array/baseline/v1/reports/pe_local_requant_bank_4lane/reference_check.txt` |
| `rtl/pe_array/reports/pe_local_requant_bank_4lane/summary.md` | `rtl/pe_array/baseline/v1/reports/pe_local_requant_bank_4lane/summary.md` |
| `rtl/pe_array/reports/pe_local_requant_bank_4lane/synth_console.txt` | `rtl/pe_array/baseline/v1/reports/pe_local_requant_bank_4lane/synth_console.txt` |
| `rtl/pe_array/reports/pe_local_requant_bank_4lane/timing_paths_post_synth.rpt` | `rtl/pe_array/baseline/v1/reports/pe_local_requant_bank_4lane/timing_paths_post_synth.rpt` |
| `rtl/pe_array/reports/pe_local_requant_bank_4lane/timing_summary_post_synth.rpt` | `rtl/pe_array/baseline/v1/reports/pe_local_requant_bank_4lane/timing_summary_post_synth.rpt` |
| `rtl/pe_array/reports/pe_local_requant_bank_4lane/utilization_post_synth.rpt` | `rtl/pe_array/baseline/v1/reports/pe_local_requant_bank_4lane/utilization_post_synth.rpt` |
| `rtl/pe_array/reports/pe_local_requant_bank_4lane/xsim_simulate.txt` | `rtl/pe_array/baseline/v1/reports/pe_local_requant_bank_4lane/xsim_simulate.txt` |
| `rtl/pe_array/reports/pe_hybrid_mac/check_timing_post_synth.rpt` | `rtl/pe_array/baseline/v1/reports/pe_hybrid_mac/check_timing_post_synth.rpt` |
| `rtl/pe_array/reports/pe_hybrid_mac/metrics_post_synth.txt` | `rtl/pe_array/baseline/v1/reports/pe_hybrid_mac/metrics_post_synth.txt` |
| `rtl/pe_array/reports/pe_hybrid_mac/summary.md` | `rtl/pe_array/baseline/v1/reports/pe_hybrid_mac/summary.md` |
| `rtl/pe_array/reports/pe_hybrid_mac/timing_summary_post_synth.rpt` | `rtl/pe_array/baseline/v1/reports/pe_hybrid_mac/timing_summary_post_synth.rpt` |
| `rtl/pe_array/reports/pe_hybrid_mac/utilization_post_synth.rpt` | `rtl/pe_array/baseline/v1/reports/pe_hybrid_mac/utilization_post_synth.rpt` |
| `rtl/pe_array/reports/pe_sigmoid_lut_255/check_timing_post_synth.rpt` | `rtl/pe_array/baseline/v1/reports/pe_sigmoid_lut_255/check_timing_post_synth.rpt` |
| `rtl/pe_array/reports/pe_sigmoid_lut_255/metrics_post_synth.txt` | `rtl/pe_array/baseline/v1/reports/pe_sigmoid_lut_255/metrics_post_synth.txt` |
| `rtl/pe_array/reports/pe_sigmoid_lut_255/reference_check.txt` | `rtl/pe_array/baseline/v1/reports/pe_sigmoid_lut_255/reference_check.txt` |
| `rtl/pe_array/reports/pe_sigmoid_lut_255/reference_summary.json` | `rtl/pe_array/baseline/v1/reports/pe_sigmoid_lut_255/reference_summary.json` |
| `rtl/pe_array/reports/pe_sigmoid_lut_255/summary.md` | `rtl/pe_array/baseline/v1/reports/pe_sigmoid_lut_255/summary.md` |
| `rtl/pe_array/reports/pe_sigmoid_lut_255/synth_console.txt` | `rtl/pe_array/baseline/v1/reports/pe_sigmoid_lut_255/synth_console.txt` |
| `rtl/pe_array/reports/pe_sigmoid_lut_255/timing_summary_post_synth.rpt` | `rtl/pe_array/baseline/v1/reports/pe_sigmoid_lut_255/timing_summary_post_synth.rpt` |
| `rtl/pe_array/reports/pe_sigmoid_lut_255/utilization_post_synth.rpt` | `rtl/pe_array/baseline/v1/reports/pe_sigmoid_lut_255/utilization_post_synth.rpt` |
| `rtl/pe_array/reports/pe_sigmoid_lut_255/xsim_console.txt` | `rtl/pe_array/baseline/v1/reports/pe_sigmoid_lut_255/xsim_console.txt` |
| `rtl/pe_array/reports/pe_gate_postprocess/check_timing_post_synth.rpt` | `rtl/pe_array/baseline/v1/reports/pe_gate_postprocess/check_timing_post_synth.rpt` |
| `rtl/pe_array/reports/pe_gate_postprocess/metrics_post_synth.txt` | `rtl/pe_array/baseline/v1/reports/pe_gate_postprocess/metrics_post_synth.txt` |
| `rtl/pe_array/reports/pe_gate_postprocess/reference_check.txt` | `rtl/pe_array/baseline/v1/reports/pe_gate_postprocess/reference_check.txt` |
| `rtl/pe_array/reports/pe_gate_postprocess/reference_summary.json` | `rtl/pe_array/baseline/v1/reports/pe_gate_postprocess/reference_summary.json` |
| `rtl/pe_array/reports/pe_gate_postprocess/summary.md` | `rtl/pe_array/baseline/v1/reports/pe_gate_postprocess/summary.md` |
| `rtl/pe_array/reports/pe_gate_postprocess/synth_console.txt` | `rtl/pe_array/baseline/v1/reports/pe_gate_postprocess/synth_console.txt` |
| `rtl/pe_array/reports/pe_gate_postprocess/timing_paths_post_synth.rpt` | `rtl/pe_array/baseline/v1/reports/pe_gate_postprocess/timing_paths_post_synth.rpt` |
| `rtl/pe_array/reports/pe_gate_postprocess/timing_summary_post_synth.rpt` | `rtl/pe_array/baseline/v1/reports/pe_gate_postprocess/timing_summary_post_synth.rpt` |
| `rtl/pe_array/reports/pe_gate_postprocess/utilization_post_synth.rpt` | `rtl/pe_array/baseline/v1/reports/pe_gate_postprocess/utilization_post_synth.rpt` |
| `rtl/pe_array/reports/pe_gate_postprocess/xsim_console.txt` | `rtl/pe_array/baseline/v1/reports/pe_gate_postprocess/xsim_console.txt` |

The membrane checkpoint used a temporary connected harness rather than
reusable checked-in source artifacts. Its accepted raw evidence is archived
directly under `reports/pe_membrane_sequencer/`: Python reference summary,
XSim console, OOC metrics, timing reports, utilization report, and the curated
checkpoint summary.

The serializer checkpoint likewise used temporary unit and connected
membrane-handshake harnesses. Its accepted raw evidence is archived directly
under `reports/pe_output_serializer/`: separate unit/connected XSim consoles,
OOC metrics, selector/mux/last timing reports, timing summary, utilization
report, and the curated checkpoint summary.

The shared-requant checkpoint used temporary Python, unit, connected-
serializer, and Vivado runners rather than reusable checked-in harnesses. Its
accepted raw evidence is archived directly under
`reports/pe_shared_requant_engine/`: Python reference summary, separate unit
and connected XSim logs, synthesis console, OOC metrics, timing reports,
utilization report, and the curated checkpoint summary.

The spike-decision checkpoint used temporary exhaustive-unit,
active-index-writer-behavior, shared-RQ-connected, and Vivado runners rather
than reusable checked-in harnesses. Its accepted raw evidence is archived
directly under `reports/pe_spike_decision/`: three XSim consoles, OOC metrics,
timing and utilization reports, and the curated checkpoint summary.

The active-index-writer checkpoint used temporary exhaustive mapping,
spike-decision-connected, behavioral-memory-sink/backpressure, and Vivado
runners rather than reusable checked-in harnesses. Its accepted raw evidence
is archived directly under `reports/pe_active_index_writer/`: three PASS XSim
consoles, OOC metrics, timing and utilization reports, and the curated summary.

The CDF-sequencer checkpoint used temporary Python-vector, connected 16-PE,
random-backpressure, hierarchy-inspection, and Vivado runners rather than
reusable checked-in harnesses. Its accepted raw evidence is archived directly
under `reports/pe_cdf_sequencer/`: Python reference summary, connected XSim
console, hierarchy counts, OOC metrics, timing/utilization reports, and the
curated checkpoint summary.

The integration-wrapper checkpoint likewise used checkpoint-local integer/
Python, connected-XSim, behavioral-controller/memory/parameter, hierarchy, and
Vivado harnesses rather than reusable baseline source. Its accepted evidence
is archived directly under `reports/pe_array_datapath/`: the retained XSim
console, elaborated hierarchy inventory, post-route metrics, route status,
internal and complete setup/hold reports, utilization reports, implementation
and read-only report-extraction consoles, and the curated checkpoint summary.
The exact 100 MHz XDC is archived separately because its 10.000 ns clock and
standalone OOC boundary assumptions are required to interpret the timing
evidence.

## Known source-artifact gaps and exclusions

- The source `pe_hybrid_mac` report directory has no standalone
  `reference_check.txt`, `xsim_simulate.txt`, `timing_paths_post_synth.rpt`, or
  `synth_console.txt`; its checked-in `summary.md` records the 4,109-command
  behavioral result and the checked-in synthesis reports record OOC evidence.
- The source `pe_requant_lane` report directory has no `synth_console.txt`.
- The accepted sigmoid RTL explicitly instantiates two Xilinx 7-series
  `RAMB18E1` primitives.  It is pure Verilog but not vendor-portable.
- The membrane connected testbench, vector generator, and runners were
  checkpoint-temporary files and are not promoted as reusable baseline source.
  The exact accepted production RTL and resulting connected-XSim/reference/OOC
  evidence are preserved in this archive.
- The serializer unit and connected testbenches and runners were likewise
  checkpoint-temporary files and are not promoted as reusable baseline source.
  The exact accepted production RTL and resulting XSim/OOC evidence are
  preserved in this archive.
- The shared-requant Python generator, unit/connected testbenches, constraints,
  and runners were checkpoint-temporary files and are not promoted as reusable
  baseline source. The accepted production RTL and raw Python/XSim/OOC evidence
  are preserved in this archive.
- The spike-decision unit/connected testbenches and Vivado runners were
  checkpoint-temporary files and are not promoted as reusable baseline source.
  The exact accepted production RTL and raw XSim/OOC evidence are preserved in
  this archive.
- The active-index-writer unit/connected testbenches, behavioral memory sink,
  and Vivado runner were checkpoint-temporary files and are not promoted as
  reusable baseline source. The exact accepted production RTL and raw XSim/OOC
  evidence are preserved in this archive. No active-index buffer or memory
  subsystem implementation is promoted by this checkpoint.
- The CDF Python generator, vectors, connected testbench/wrapper, constraints,
  hierarchy checker, and Vivado runner were checkpoint-temporary files and are
  not promoted as reusable baseline source. The exact production RTL and raw
  Python/XSim/hierarchy/OOC evidence are preserved in this archive. No
  coefficient memory, spectrum-history memory, controller, or dedicated
  complex arithmetic module is promoted by this checkpoint.
- The integration wrapper's reference model, connected testbench, behavioral
  controller/memory/parameter agents, hierarchy checker, and runners remain
  checkpoint harnesses and are not promoted as reusable baseline source. No
  layer/tile/workload controller FSM, parameter/state/coefficient memory,
  spectrum-history storage, active-index storage, or full accelerator top is
  promoted.
- The routed 100 MHz OOC checkpoint closes internal register-to-register setup
  and hold timing but has an unresolved top-level input-boundary hold
  violation. It is not a clean complete-boundary timing sign-off, and no
  bitstream was generated.
- Full-system implementation must rerun placement, routing, setup, and hold
  analysis with the real controller, memory subsystem, clocking, source/sink
  registers, and boundary constraints. Neither the standalone leaf 200 MHz OOC
  results nor this wrapper's internal 100 MHz result establishes a connected
  200 MHz operating point.
- Generated Vivado/XSim build trees, DCPs, caches, wave databases, and Python
  bytecode are intentionally excluded.  They are build products, not reviewed
  baseline source/report artifacts.
- `MANIFEST.md` and `SHA256SUMS` are archive metadata and are intentionally not
  included in `SHA256SUMS`, avoiding self-reference.
