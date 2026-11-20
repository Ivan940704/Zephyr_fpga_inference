# PE Array handoff

## Authoritative context

Read these files before continuing:

- `AGENTS.md` for mandatory subtree workflow and baseline rules;
- `spec/MODULE_DEVELOPMENT_PLAN.md` for the persistent architecture;
- `baseline/v1/MANIFEST.md` for accepted artifacts and evidence.

For formal PE Array status, the accepted baseline manifest and the latest
explicit user approval take precedence over experimental RTL, old combined
simulations, and broad project-status summaries.

## Current formal baseline

Baseline root:

```text
/home/ivanhuang/projects/Zephyr_fpga_inference/rtl/pe_array/baseline
```

Exactly eleven arithmetic/functional leaf modules are formally accepted and
frozen:

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

In addition, `pe_array_datapath` is formally accepted as a separately
classified PE-subsystem integration wrapper. It is not a twelfth arithmetic
leaf, and all eleven leaf RTL files remain byte-identical to their prior
baseline copies.

The accepted gate-postprocess checkpoint is the verified Verilog-2001 RTL
from commit `b7671e0`. It pairs one four-lane INPUT RQ packet with the following
RECURRENT RQ packet, adds signed INT32 bias in a signed 64-bit intermediate,
performs the fixed eight-bit upstream-exact guard rounding, and saturates to
signed INT8 `-127..127`. It uses one pending packet, has no `out_clipped` port,
and instantiates no requant lane, Local RQ, sigmoid, multiplier, DSP, or memory.

Checkpoint evidence records 1,520 output packets and 5,007 active lane results
bit-exact PASS, random backpressure with gate/lane/tag alignment preserved,
protocol II=2, and measured no-stall latency of six cycles from INPUT acceptance
or five cycles from RECURRENT acceptance. Vivado 2018.3 OOC for
`xc7z020clg400-1` at 5.000 ns reports 1,153 LUT, 1,605 FF, zero DSP/BRAM, and
WNS +0.185 ns.

The accepted membrane-sequencer checkpoint is the verified Verilog-2001 RTL
from commit `838c567`. It schedules the existing sixteen Hybrid MAC PEs for
the two raw membrane products, the existing four-lane Local RQ Bank for the cx
and cellgate requantization, the Hybrid PEs in DIRECT mode for final term
accumulation, and the existing single gate-postprocess instance for final R8
rounding/saturation. Accumulators are cleared in an earlier acquire cycle,
never in a DIRECT-command cycle, and resource ownership remains asserted until
the shared pending/pipeline/output state is drained.

Connected XSim is bit-exact PASS over 96 tiles / 663 active-lane results.
Accepted no-stall measurements are 31 cycles to `result_valid`, 32 cycles to
the tile result handshake, and tile II=33. Sequencer-only Vivado 2018.3 OOC at
200 MHz reports 2,934 LUT, 2,058 FF, zero DSP48E1, BRAM, LUTRAM, or multiplier,
and WNS +0.227 ns.

The accepted output-serializer checkpoint is the verified Verilog-2001 RTL
from commit `6cab9a9`. It contains one sixteen-lane tile register bank and one
sixteen-bit pending mask, skips inactive lanes, emits active lanes in ascending
order, and generates `index_out = base_index + selected_lane`. Output
ready/valid state holds value/index/tag/last stable throughout backpressure.
`last_out` marks only the final valid neuron of a logical vector, never merely
the end of an intermediate tile.

Unit XSim and connected membrane-handshake XSim both PASS. Accepted no-stall
measurements are one-cycle latency, output II=1, and full-tile load II=17.
Vivado 2018.3 OOC at 200 MHz reports 284 LUT, 806 FF, zero DSP48E1, BRAM, or
LUTRAM, and WNS +0.152 ns. Registered selected-lane control is deliberately
retained to separate the lowest-set-bit selector from the value/tag mux
critical path; it is control state, not a second tile buffer.

The accepted shared-requant checkpoint is the verified Verilog-2001 RTL from
commit `4bf3f7c`. It instantiates exactly one physical baseline
`pe_requant_lane`, shared by QBN and Linear requests at II=1. Both operation
kinds use the same signed requant, signed INT32 bias add in a signed 64-bit
intermediate, fixed R8 ties-away rounding, and saturation to `-127..127`.
Operation kind, bias, index, tag, and logical-last metadata remain aligned
through the lane opaque tag and the common-stalled postprocess pipeline.

Python reference, unit XSim, and serializer-connected XSim all PASS. The unit
test covered 3,500 vectors including every 1,984 formal QBN and 464 formal
Linear channels; consecutive QBN/Linear requests can alternate cycle by
cycle. The connected test passed 96 tiles / 486 serialized results. Accepted
latency is 14 cycles and II=1. Vivado 2018.3 OOC at 200 MHz reports 739 LUT,
773 FF, 4 DSP48E1, zero BRAM/LUTRAM, and WNS +0.263 ns. Hierarchical netlist
inspection reports one physical `pe_requant_lane`; there is no second RQ core,
parameter RAM, FIFO, scoreboard, or CDF path.

The accepted spike-decision checkpoint is the verified Verilog-2001 RTL from
commit `3457166`. It consumes only signed INT8 QBN `state_q` values and applies
the fixed predicate `signed(state_q) >= 0`, so zero produces a spike. Ordinary
non-spikes are consumed without a downstream transaction. A terminal
non-spike is still emitted as a finalize event; the active-index writer writes
only when `spike=1` and finalizes whenever `last=1`. Index, tag, and logical-last
metadata pass through unchanged, and no complete spike vector is formed.

Exhaustive unit XSim passed all 256 signed INT8 encodings, 2,048
valid/last/ready combinations, and 12,482 checks. Writer-connected XSim passed
512 inputs / 287 events / 273 writes / 31 finalizations with 84 randomized
stall cycles. Shared-RQ-connected XSim passed 192 alternating requests (96 QBN
and 96 Linear), with Linear explicitly bypassing the spike path. Accepted
latency is zero registered cycles and II=1. Clockless-leaf OOC under a virtual
5.000 ns / 200 MHz max-delay constraint reports 3 LUT, zero FF/DSP48E1/BRAM/
LUTRAM, worst datapath 2.070 ns, and WNS +2.930 ns.

The accepted active-index-writer checkpoint is the verified Verilog-2001 RTL
from commit `400b3d2`. It is a pure combinational atomic command adapter:
`spike` requests an index write, `last` requests finalize, and
`spike=1,last=1` performs both actions in the same ready/valid handshake.
Index and tag pass through unchanged. Active count, storage, full state, and
the write pointer belong to the memory subsystem; the writer contains no
register, counter, FIFO, RAM, complete spike vector, or index storage.

Unit XSim passed 3,082 cases / 18,492 checks. Spike-decision-connected XSim
passed 256 inputs / 132 commands / 128 writes / 9 finalizations with 19 stall
cycles. Behavioral-memory-sink XSim passed 64 frames / 314 commands / 291
writes / 66 finalizations with 140 stall cycles. Accepted latency is zero
registered cycles and II=1. Clockless-leaf OOC under a virtual 5.000 ns /
200 MHz max-delay constraint reports zero LUT/FF/DSP48E1/BRAM/LUTRAM, worst
datapath 0.973 ns, and WNS +4.027 ns.

The accepted CDF-sequencer checkpoint is the verified Verilog-2001 RTL from
commit `169c4c0`. It time-multiplexes the existing sixteen `pe_hybrid_mac`
instances: two PEs hold the signed-INT32 real and imaginary accumulators for
one complex bin, allowing up to eight bins per group under a partial-bin mask.
Each order-1/3/5 temporal tap uses two `MODE_DENSE` phases: `Xr*Cr` / `Xr*Ci`,
then `Xi*(-Ci)` / `Xi*Cr`. The provider supplies causal zero padding and the
current group operands; coefficient memory, coefficient-stream reshape, and
spectrum temporal-history memory remain outside this module. Results receive
no requantization, rounding, or saturation.

The deterministic Python reference passed 390 groups covering all three
orders, 291 partial groups, 1,114 active causal-zero-padding samples, and 340
`Ci=-127` boundary samples. Connected XSim passed 393 group checks / 2,023
active-bin checks with randomized tap/result backpressure. Every legal CDF
case kept Hybrid PE overflow at zero. Hierarchy inspection found exactly
sixteen byte-matched formal-baseline `pe_hybrid_mac` instances, one sequencer,
and no requant or complex-multiplier instance.

Accepted no-stall `result_valid` latency is 3/7/11 cycles and group II is
4/8/12 cycles for orders 1/3/5 respectively. Sequencer-only Vivado 2018.3 OOC
at 200 MHz reports 327 LUT, 239 FF, zero DSP48E1, BRAM, LUTRAM, or multiplier
macro, and WNS +0.236 ns.

The accepted `pe_array_datapath` is the Verilog-2001 integration wrapper
promoted from commit `645a765` plus the 2026-09-07 gate-routing and
recurrent-membrane errata, with SHA-256
`14707a8126a1ede0625f592a94053fbb27a7c8bac72470c3e9c838f6ae40e93b`.
It connects only the eleven formal `baseline/v1` leaves and supplies
one-hot resource ownership, mux/demux and tag adaptation, atomic joins/forks,
outstanding/drain tracking, collectors, serializer context, backpressure,
protocol assertions, and overflow aggregation. It adds no
layer/tile/workload controller FSM, RAM or memory subsystem, FIFO, scoreboard,
arithmetic unit, requantizer, or multiplier.

Connected integer/Python reference and XSim verification PASS. The retained
run completed in 2,330 cycles with 11 dense-state outputs, 6 active-index
writes, 12 Linear/CDF coefficient outputs, 23 Shared-RQ parameter handshakes,
and 8 gate-bias handshakes. Both the GSU-to-membrane/QBN/spike path and the
Linear-to-CDF path were checked bit-exactly, including owner transitions under
randomized parameter delay and downstream backpressure.

The recurrent-membrane regression additionally executes two full sequential-v4
frames and compares all 640 first-layer state bytes.  CX responses are held
per group until CELL raw snapshots are complete, so nonzero previous state is
not requantized a second time through the CELL path.

Hierarchy inspection PASS found exactly sixteen `pe_hybrid_mac` instances,
one four-lane Local RQ Bank, one Shared RQ Engine, five total physical
`pe_requant_lane` instances, and one instance of every other accepted leaf.
No forbidden controller, active-index buffer, GSN cell, `pe_array_top`,
dedicated complex multiplier, or duplicated arithmetic datapath was present.

The fully routed 100 MHz OOC checkpoint reports 10,225 LUT, 10,573 FF,
36 DSP48E1, two RAMB18E1, and zero RAMB36E1, LUTRAM, or multiplier macro.
All 16,343 routable nets are fully routed with zero route-error nets. Internal
register-to-register setup and hold PASS at WNS +0.727 ns and WHS +0.056 ns;
overall setup WNS is +0.254 ns.

The standalone OOC boundary hold check is not clean: overall WHS is -1.368 ns
on a top-level input path, so Vivado reports
`timing_constraints_met=0`. This promotion therefore accepts connected
bit-exact function, structural hierarchy, resources, and the **internal**
100 MHz register-to-register setup/hold result only. It does not claim clean
standalone boundary timing, and **200 MHz is not a formally verified operating
point** for the connected wrapper. Full-system controller FSM and memory
integration must be followed by new top-level placement/routing and complete
setup/hold timing closure using real boundaries and constraints.

Apart from the eleven frozen leaves and the separately accepted
`pe_array_datapath` integration wrapper, every other PE Array RTL module is
pre-existing, experimental, or unverified for the current formal process. No
other module may be used as a formal dependency without a separate approved
checkpoint.

## Baseline observations

1. The gate postprocess passes its 200 MHz OOC synthesis checkpoint, but the
   WNS is only **+0.185 ns**. Complete integration and place-and-route must
   re-confirm timing; the OOC result is not an integrated timing guarantee.
2. The accepted RTL retains the verified **64-bit intermediate datapath**.
   Resource optimization must not narrow it without a separate proof that the
   proposed widths remain bit-exact over the formal model domain.
3. The sequencer LUT/FF cost is mainly sixteen-lane temporary state, routing,
   and control. Reconsider optimization only after complete-integration
   resource profiling; do not modify the accepted design now.
4. The serializer passes its 200 MHz OOC synthesis checkpoint at **WNS
   +0.152 ns**, but complete integration and place-and-route must re-confirm
   200 MHz timing.
5. Preserve the accepted shared-requant five-stage postprocess pipeline and
   64-bit sum datapath. The saturation/sign split is part of the verified
   14-cycle design; do not perform extra resource or timing optimization
   without a separate approved checkpoint.
6. The spike decision is intentionally combinational. Its ready/event path
   passes the standalone virtual-200-MHz OOC checkpoint, but complete
   integration and place-and-route must re-confirm timing before the latency
   and path are treated as an integrated guarantee.
7. The active-index writer is intentionally a combinational port-alias leaf.
   Complete integration and place-and-route must re-confirm the combined
   spike-decision / writer / memory-ready path at 200 MHz.
8. The CDF sequencer passes its 200 MHz OOC synthesis checkpoint, but its WNS
   margin is only **+0.236 ns**. Complete integration and place-and-route must
   re-confirm timing; the standalone OOC result is not an integrated timing
   guarantee.
9. The integration wrapper has a fully routed 100 MHz OOC result with internal
   register-to-register setup/hold slack of **+0.727/+0.056 ns**, but the
   external input-boundary hold slack is **-1.368 ns**, so the complete OOC
   timing constraints are not clean. The wrapper has no formal 200 MHz
   verified point. Full-system controller and memory integration must
   re-establish both setup and hold timing through top-level place-and-route.

## Current authorization

The `pe_array_datapath` functional/structural integration-wrapper checkpoint
has been promoted into `baseline/v1` without changing the eleven formal
leaves. No full-system controller FSM, memory subsystem, `pe_array_top`,
resource/timing optimization, or additional module is authorized by this
handoff. Stop after promotion and wait for a new explicit user instruction.

## Required next-session behavior

1. Read `AGENTS.md`, the complete module plan, and the baseline manifest.
2. Confirm Git HEAD/status and preserve the unrelated dirty `upstream` nested
   repository state.
3. Treat the eleven frozen leaves as the complete formal arithmetic/functional
   dependency set and `pe_array_datapath` as the separately accepted
   integration wrapper.
4. Wait for explicit selection and authorization before reviewing or
   implementing another module.

## Repository checkpoint provenance

- Prior four-module baseline promotion commit: `ae7a64a`.
- Gate-postprocess verified checkpoint commit: `b7671e0`.
- Membrane-sequencer verified checkpoint commit: `838c567`.
- Output-serializer verified checkpoint commit: `6cab9a9`.
- Shared-requant verified checkpoint commit: `4bf3f7c`.
- Spike-decision verified checkpoint commit: `3457166`.
- Active-index-writer verified checkpoint commit: `400b3d2`.
- CDF-sequencer verified checkpoint commit: `169c4c0`.
- PE-array-datapath integration-wrapper checkpoint commit: `645a765`.
- Architecture-plan update commit: `fd0ff78`.
- Working branch at this handoff: `codex/memory-design-guidelines`.
- The existing dirty `upstream` nested-repository state is unrelated and must
  not be staged, reset, reformatted, or otherwise modified by PE Array work.
