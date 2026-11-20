# Task: Independent PE Array incremental development

- Owner: Ivan Huang (PE Array), with Codex assistance
- Status: superseded by full operator checkpoint
- Branch/worktree: `codex/pe-array-small-model`
- Scope: create and incrementally verify a clean-room PE Array implementation
  entirely under `rtl/pe_array/`
- Files expected to change: `rtl/pe_array/**`, this task, future matching handoffs,
  and checkpoint entries in `PROJECT_STATUS.md`

## Constraints

- Do not modify, include, instantiate, or copy implementations from `rtl/leaf/`,
  `rtl/sparse/`, `rtl/gsu/`, or other existing RTL areas.
- Existing RTL and upstream Python may be read only as behavioral/numerical
  references.
- Target `xc7z020clg400-1`, 200 MHz.
- Preserve the fixed 16-PE, 4-lane local RQ, 255-entry LUT, PE-reuse membrane,
  serializer, one-lane shared RQ, and direct active-index architecture. The
  membrane module is a control-only `pe_membrane_sequencer`: it may contain phase
  control, temporary registers, pending masks, and PE/RQ scheduling, but no
  multiplier, requant lane, MAC, or dedicated membrane arithmetic datapath.
- Advance strictly one module at a time through RTL, self-checking TB, applicable
  Python bit-exact comparison, Vivado synthesis, and report review.

## Current checkpoint: full operator set and small-model verification

- [x] Create an isolated `rtl/pe_array/` directory structure.
- [x] Document module responsibilities and provisional interfaces.
- [x] Document per-module verification and synthesis gates.
- [x] Confirm no PE RTL or full controller was generated in this checkpoint.
- [x] Confirm existing `rtl/leaf/` and `rtl/sparse/` content is unchanged.
- [x] Implement the standalone signed INT32 x signed multiplier requant lane.
- [x] Generate deterministic edge, tie, symmetry, and random golden vectors.
- [x] Pass self-checking XSim with ready/valid backpressure.
- [x] Pass 5 ns Vivado out-of-context synthesis and record measured resources,
  timing, exact latency, and II.

## PYNQ-Z1 feasibility: `pe_local_requant_bank_4lane` Gate A

- Placement: PL RTL, isolated PE Array local requant datapath.
- Target part / clock: `xc7z020clg400-1`, one synchronous 200 MHz domain;
  no CDC inside the module.
- Numeric formats and shape: one bank transaction contains four signed INT32
  values, four signed 32-bit multipliers, four 6-bit shifts, four opaque tags,
  and a four-bit lane mask. Results are four signed INT64 values with matching
  tags and lane mask.
- Parallel instances / lanes: exactly four existing `pe_requant_lane`
  instances; no parameter RAM, bias, guard shift, saturation, QBN, or membrane
  control.
- Measured per-lane baseline: 475 LUT, 431 FF, 4 DSP48E1, latency 9, II=1,
  based on the completed Vivado 2018.3 OOC result.
- Scaled arithmetic-core baseline: 1,900 LUT, 1,724 FF, 16 DSP48E1, zero BRAM;
  bank wrapper/mask routing is additional and must be replaced by measured bank
  OOC utilization at Gate B.
- Device share before wrapper: 3.57% LUT, 1.62% FF, 7.27% DSP48E1.
- Local buffer / ports: no payload buffer or parameter storage. Lane-valid is
  carried through each lane as one extra tag bit. Common backpressure keeps all
  four rigid pipelines synchronized.
- DDR / AXI: none locally. The upstream sequencer must provide at most four
  multiplier/shift tuples per accepted cycle; system parameter-memory banking
  remains an integration responsibility.
- Cycle/II assumption: exact no-stall latency remains 9 cycles and one bank
  transaction (up to four active elements) per cycle. A 16-neuron gate/membrane
  tile issues 16 + 8 bank cycles for its 64 + 32 local-RQ operations; dependency
  latency is handled by later group scheduling.
- Clock/reset: synchronous active-low reset, matching the verified lane. The
  200 MHz bank-level result is not claimed until bank OOC synthesis passes.
- Hot spot / risk: four 32x32 logical multiplies require 16 DSP48E1; replicated
  ready/valid and wider tag routing may reduce WNS relative to one lane.
- Fallback: keep the four-lane architecture but add shallow registered request/
  response boundaries or floorplanning during integration. An eight-lane bank
  is a profiling-only future optimization, not the first implementation.
- Evidence level: per-lane resource/timing is measured OOC synthesis; scaled
  resource, tile cycles, and wrapper impact are analytical assumptions.
- Feasibility: **PASS WITH RISKS**, requiring four-lane XSim and OOC synthesis.

## Gate B result: `pe_local_requant_bank_4lane`

- Standalone reference: 2,112 packets and 4,149 active results verified.
- XSim 2018.3: bit-exact PASS for all lane masks, edge/random arithmetic,
  latency 9, bank II=1, four results/cycle, and randomized backpressure.
- Vivado 2018.3 OOC: 2,167 LUT, 1,732 FF, 16 DSP48E1, zero BRAM.
- Timing: 5.000 ns constraint, WNS +0.263 ns, TNS 0, estimated Fmax
  211.104 MHz.
- Constraint audit: zero unconstrained ports/internal endpoints and zero loops.
- Parameter-memory read bandwidth and full-array routing remain integration
  risks. Evidence is unit XSim/OOC only, not implementation or board data.
- Feasibility: **PASS WITH INTEGRATION RISKS**.

## Incremental acceptance checks

- [x] `pe_requant_lane`: 5,155-vector bit-exact XSim PASS; latency 9, II=1;
  475 LUT, 431 FF, 4 DSP; WNS +0.263 ns at 5 ns OOC synthesis.
- [x] `pe_local_requant_bank_4lane`: 2,112-packet XSim PASS; latency 9,
  II=1, four results/cycle; 2,167 LUT, 1,732 FF, 16 DSP; WNS +0.263 ns.
- [x] `pe_hybrid_mac`: 4,109-vector cycle-exact XSim and 5 ns OOC PASS;
  87 LUT, 68 FF, 1 DSP, WNS +0.270 ns.
- [x] `pe_sigmoid_lut_255`: all 255 real fullband LUT entries pass XSim.
- [x] `pe_membrane_sequencer`: control-only PE/RQ phase checks pass XSim; no
  arithmetic operator is present in RTL.
- [x] `pe_output_serializer`: mask/order/index/tag and backpressure pass XSim.
- [x] `pe_shared_requant_engine`: requant/bias/guard/saturation/metadata pass
  the combined support XSim; the physical lane remains the verified
  `pe_requant_lane`.
- [x] Spike/active-index path: direct-index, non-spiking last event,
  count/read/finalize pass XSim without a vector scan.
- [x] Controller and 16-MAC arithmetic shell: controller phases and full-shape
  model XSim pass; shell OOC uses 1,346 LUT, 1,050 FF, 16 DSP, WNS +0.270 ns.

## Remaining integration scope

- Production memory/AXI wiring, a completely connected GSU postprocess datapath,
  recurrent multi-frame tests, place-and-route, bitstream, RTF and board test.
- The combined support operators do not each have a separate OOC report; current
  synthesis evidence is the multiplier-heavy lanes/bank and intended 16-MAC
  shell. Full subsystem OOC remains an integration gate.
