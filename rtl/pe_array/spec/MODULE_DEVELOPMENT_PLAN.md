# PE Array incremental module plan

This document is the persistent hardware-architecture source of truth for PE
Array development. A module is formal only when it appears in the accepted
baseline listed here. RTL, tests, reports, or combined simulations elsewhere
in the repository do not imply completion or approval.

## Target and production-language convention

- FPGA board: PYNQ-Z1.
- FPGA part: `xc7z020clg400-1`.
- Target clock: 200 MHz / 5.000 ns.
- Synthesis and XSim checkpoint tool: Vivado 2018.3.
- Every new production RTL file must use synthesizable Verilog-2001
  (IEEE 1364-2001) and the `.v` extension.
- New production RTL must not depend on SystemVerilog-only syntax or require
  `read_verilog -sv` / `xvlog --sv`.
- New unit testbenches should also use `.v` unless a separately reviewed tool
  requirement makes that impossible.

The first three accepted modules are preserved in the baseline with their
original `.sv` bytes because they were verified before the Verilog-2001
production convention was fixed. Their archived extension is historical and
must not be copied as the convention for new RTL. Converting any of them to
`.v` is a new implementation checkpoint requiring simulation, synthesis,
timing review, and explicit user approval.

## Formal baseline

Formal baseline root:

```text
/home/ivanhuang/projects/Zephyr_fpga_inference/rtl/pe_array/baseline
```

The current accepted archive is under `baseline/v1`. Formal baseline
membership is exactly:

1. `pe_requant_lane`
2. `pe_local_requant_bank_4lane`
3. `pe_hybrid_mac`
4. `pe_sigmoid_lut_255`

No other PE Array module is complete or approved. In particular, controller,
GSN-cell, PE-array-top, memory/AXI, serializer, gate-postprocess, membrane
sequencer, spike/index, and other support RTL found outside the baseline is
pre-existing, experimental, or unverified. It must not be reused, inherited,
or treated as a dependency of formal development without its own checkpoint
and explicit baseline approval.

## Fixed architecture and invariants

The production architecture is fixed as follows:

```text
16 x Hybrid MAC PE
        |
        | matrix / spike / gate raw accumulation
        v
one 4-lane Local Requant Bank
        |
        | RQ(input accumulator) and RQ(recurrent accumulator)
        v
pe_gate_postprocess
        |  add bias -> guard shift / rounding -> saturation
        +--------------------+
        |                    |
       i_t                g_lambda
                             |
                             v
                4-lane pe_sigmoid_lut_255
                             |
                          lambda_t
                             |
                             v
pe_membrane_sequencer controls reuse of the same 16 Hybrid MAC PEs
and the same 4-lane Local Requant Bank for membrane arithmetic
                             |
                             v
                  pe_output_serializer
                             |
                             v
             one pe_shared_requant_engine
                             |
                    QBN / Linear postprocess
                             |
                             v
                    pe_spike_decision
                             |
                             v
              pe_active_index_writer / buffer
```

The following invariants may not be changed by a module implementation:

- Exactly sixteen Hybrid MAC PEs form the arithmetic array.
- The same sixteen PEs are time-multiplexed for matrix/gate work and membrane
  arithmetic.
- There is no second PE array for membrane processing.
- There is no dedicated membrane multiplier, multiplier array, or neuron
  arithmetic lane.
- One four-lane Local Requant Bank is reused for gate input/recurrent RQ and
  membrane `cx`/`cellgate` RQ.
- The membrane sequencer contains control and temporary state only.
- A serializer is followed by one physical shared requant lane/engine for
  serialized QBN and Linear scale conversion.
- Spike decision already carries the current neuron index. A spike writes that
  index directly into the active-index path; no complete spike vector is formed
  and no `spike_indexer`-style vector scan is permitted.
- Interfaces for modules not yet accepted are provisional until their upstream
  arithmetic/functional contract and interface are reviewed and approved.
- Flattened packed buses are preferred for multi-lane Verilog-2001 ports.

## Verified baseline checkpoints

All numbers below are Vivado 2018.3 post-synthesis out-of-context results for
`xc7z020clg400-1` with a 5.000 ns constraint. They are not post-route or board
measurements.

| Module | Status/evidence | Latency / II | LUT | FF | DSP48E1 | BRAM | WNS |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| `pe_requant_lane` | XSim/reference PASS | 9 cycles / II=1 | 475 | 431 | 4 | 0 | +0.263 ns |
| `pe_local_requant_bank_4lane` | XSim/reference PASS | 9 cycles / II=1 four-result packet | 2,167 | 1,732 | 16 | 0 | +0.263 ns |
| `pe_hybrid_mac` | XSim/reference PASS | 1-cycle command-to-accumulate / II=1 | 87 | 68 | 1 | 0 | +0.270 ns |
| `pe_sigmoid_lut_255` | XSim exhaustive real-table PASS | 1 cycle / II=1 four-neuron packet | 72 | 51 | 0 | 2 x RAMB18E1 | +0.565 ns |

The accepted sigmoid organization is fixed:

- four parallel lookup lanes;
- eight 255-entry tables resident simultaneously;
- two explicit Xilinx 7-series `RAMB18E1` true-dual-port memories;
- four neurons accepted per cycle at II=1 when unstalled;
- one-cycle lookup latency;
- one common table selection per four-neuron packet;
- a complete 2,040-byte table load after reset, with no per-frame reload.

## Module responsibilities and interfaces

### 1. `pe_requant_lane` — baseline

Responsibility: one signed INT32 value multiplied by one signed INT32
multiplier, producing an exact signed INT64 product, followed by sign-symmetric
round-to-nearest and a variable right shift. It contains no bias, fixed guard
shift, saturation, QBN/membrane control, or parameter RAM.

Accepted logical interface:

- `clk`, synchronous active-low `rst_n`;
- `in_valid/in_ready`;
- signed `value_in[31:0]`, signed `multiplier_in[31:0]`, `shift_in[5:0]`, and
  parameterized opaque `tag_in`;
- `out_valid/out_ready`;
- signed `value_out[63:0]` and aligned `tag_out`.

Accepted performance: latency 9 cycles and II=1 with a rigid, globally stalled
pipeline under output backpressure.

### 2. `pe_local_requant_bank_4lane` — baseline

Responsibility: four synchronized `pe_requant_lane` instances. It processes
up to four tagged operations per accepted packet and does not own parameter
memory, bias, guard shift, saturation, sigmoid, or membrane control.

Accepted logical interface:

- one bank-level `in_valid/in_ready` and `out_valid/out_ready` transaction;
- four lane-valid bits;
- flattened four-lane `value`, `multiplier`, `shift`, and tag requests;
- flattened four-lane 64-bit results, tags, and lane-valid response mask.

Accepted performance: latency 9 cycles and II=1 bank packet, with up to four
results per cycle when unstalled.

### 3. `pe_hybrid_mac` — baseline

Responsibility: one independently controlled signed 32-bit accumulator lane
supporting:

- dense signed INT8 multiply-accumulate;
- spike-gated signed weight accumulation;
- unsigned gate times signed INT8 accumulation;
- signed INT32 direct accumulation.

It has synchronous active-low `rst_n`, accumulator clear/enable, mode and
operand controls, signed accumulator output, and sticky overflow indication.
Dense and gate modes share one physical multiplier; spike and direct modes
bypass it. A production array instantiates exactly sixteen copies.

### 4. `pe_sigmoid_lut_255` — baseline

Responsibility: four parallel mappings from signed gate-domain input
`-127..127` to unsigned `lambda_t` in `0..255`, using one of eight resident
real-model tables. Input `-128` is outside the upstream domain and defensively
maps to entry zero.

Accepted logical interface:

- `clk`, synchronous active-low `rst_n`;
- common `in_valid/in_ready` with four lane-valid bits;
- four flattened signed INT8 gate inputs and four opaque tags;
- common `table_select[2:0]`;
- common `out_valid/out_ready`, four lane-valid bits, four unsigned INT8 lambda
  outputs, and four aligned tags;
- configuration start/data ready-valid stream, `cfg_done`, and `table_valid`.

All eight tables are loaded in table-major order and remain resident. The
checkpoint exhaustively verified all `8 x 255` real entries in both continuous
and backpressured passes.

### 5. `pe_gate_postprocess.v` — next planned checkpoint, not baseline

Architectural position: directly after the four-lane Local Requant Bank and
before the Sigmoid LUT branch.

Required arithmetic function for each gate/neuron is:

```text
RQ(input accumulator)
+ RQ(recurrent accumulator)
+ bias
-> guard shift with upstream-exact rounding
-> saturation
-> i_t or g_lambda
```

The two RQ operations are performed only by
`pe_local_requant_bank_4lane`. `pe_gate_postprocess` must not instantiate a
requant lane, multiplier, DSP-based scale converter, sigmoid table, or membrane
arithmetic path.

Provisional logical interface for contract review:

- a four-lane ready/valid response stream from the Local RQ Bank;
- per-lane component identity (`input` or `recurrent`), gate/output identity,
  neuron/tag metadata, and signed widened RQ result;
- matching per-neuron bias and guard-shift configuration;
- temporary valid/pending state needed to pair input and recurrent results;
- a four-lane ready/valid signed INT8 output stream identifying `i_t` or
  `g_lambda` and preserving neuron/tag metadata.

`i_t` is retained for membrane processing. `g_lambda` is the signed gate input
to `pe_sigmoid_lut_255`. Exact bias width, sum width, guard rounding, clipping
limits, ordering, and packet schedule must be traced from upstream Python and
approved before RTL is written.

Verification must include real parameters, every operation/gate identity,
positive/negative guard-rounding cases, saturation boundaries, pairing order,
lane masks, tags, randomized backpressure, bit-exact Python comparison, and
Vivado OOC evidence. Netlist inspection must show no multiplier/DSP in this
module unless separately justified and approved.

### 6. `pe_membrane_sequencer.v` — planned, not baseline

Responsibility: membrane phase control and temporary-state storage only. It
schedules the same sixteen `pe_hybrid_mac` instances and the same four-lane
Local Requant Bank to execute the upstream bit-exact membrane equation.

Permitted contents:

- phase and dependency control;
- per-neuron `i_t`, `u_prev`, `lambda_t`, intermediate term, and tag registers;
- lane/pending/valid masks;
- Hybrid PE mode, clear, enable, operand-source, and lane controls;
- Local RQ request/response scheduling and tag matching;
- `busy`, `done`, and tile/context state.

Forbidden contents:

- a dedicated multiplier or DSP arithmetic lane;
- a local requantizer;
- a dedicated membrane MAC/ALU;
- a second PE array.

Hybrid PEs generate the raw membrane terms, the Local Requant Bank performs the
`cx` and `cellgate` scale conversions, and Hybrid PE direct accumulation combines
the returned terms. The exact issue schedule and temporary-register widths are
frozen only after the upstream membrane contract is rechecked.

Verification must be cycle-accurate and prove phase order, dependency handling,
pending masks, tag matching, backpressure, and bit-exact connected PE + Local
RQ behavior. OOC/netlist inspection must show that the sequencer itself adds
no multiplier, DSP, requant lane, or membrane arithmetic array.

### 7. `pe_output_serializer.v` — planned, not baseline

Responsibility: serialize sixteen lane/neuron results while preserving the
already-known global neuron index and honoring backpressure.

Provisional interface:

- parallel load ready/valid, sixteen values, lane-valid mask, base neuron index,
  and tile/tag;
- serialized output ready/valid, value, global neuron index, tag, and `last`;
- `busy` and `done` status.

Verification covers ascending index order, partial masks, exact-once delivery,
stable output under stalls, consecutive loads, and index/tag alignment.

### 8. `pe_shared_requant_engine.v` — planned, not baseline

Responsibility: one physical shared requant lane/engine after the serializer for
serialized QBN and Linear output scale conversion. It must not create a
per-neuron or per-lane multiplier array.

Provisional request/response streams carry operation identity, value, RQ
parameters, stage-specific postprocess fields, neuron index, tag, and `last`.
Exact QBN/Linear bias, guard shift, rounding, saturation, and ordering remain
operation-specific contracts that must be approved before implementation.

Verification uses real QBN and Linear parameters, signed boundary and
saturation cases, operation changes, arbitrary stalls, index/tag alignment,
bit-exact Python comparison, and netlist confirmation of only one shared lane.

### 9. Spike and active-index path — planned, not baseline

Planned modules:

- `pe_spike_decision.v`;
- `pe_active_index_writer.v`;
- `pe_active_index_buffer.v`.

The serialized neuron value arrives with its global index. When the spike
predicate is true, that index is sent directly to the writer and buffer. The
path must not first build a complete spike vector and must not instantiate or
reuse a vector-scanning `spike_indexer`.

Verification covers no-spike/all-spike, alternating and random patterns,
first/last index, ordering, stalls, buffer full/overflow, frame boundaries, and
exactly-once index writes.

### 10. `pe_array_controller.v` and `pe_array_top.v` — final integration, not baseline

These modules are implemented only after all required leaf checkpoints are
accepted. They schedule matrix computation, four-lane gate RQ, gate
postprocess, sigmoid lookup, PE/RQ membrane reuse, serialization, one-lane
shared RQ, state writeback, spike decision, and direct active-index generation.

Any existing controller, support operator, GSN-cell, 16-MAC shell, memory/AXI,
or combined-simulation RTL outside the baseline remains experimental evidence
only. This plan does not declare it complete and formal integration must not
inherit it automatically.

## Mandatory module-development methodology

Only one module may be active as a formal checkpoint at a time:

```text
select one module
-> trace and document upstream arithmetic/functional contract
-> review proposed interface and implementation plan
-> user approval to implement
-> implement pure Verilog-2001 .v RTL
-> self-checking XSim
-> Python/integer-reference bit-exact verification where applicable
-> Vivado OOC synthesis at 5.000 ns
-> record simulation, utilization, timing, latency, II, and limitations
-> stop
-> user reviews checkpoint
-> explicit user approval
-> copy only the approved checkpoint into the formal baseline
```

After producing a checkpoint report, development stops. The next module must
not begin automatically. A checkpoint must not be marked baseline, added as a
dependency, or used by later formal work until the user explicitly approves it.

## Artifact convention for each new module

For `<module>`:

- production RTL: `rtl/<category>/<module>.v`;
- self-checking Verilog TB: `tb/unit/tb_<module>.v`;
- vectors: `tb/vectors/<module>/` or a clearly named flat vector file;
- standalone reference: `reference/<module>_reference.py` when applicable;
- XSim entry: `scripts/sim/run_<module>_xsim.tcl`;
- OOC synthesis entry: `scripts/synth/synth_<module>_ooc.tcl`;
- 200 MHz constraint: `constraints/<module>_200mhz.xdc`;
- reviewed evidence: `reports/<module>/summary.md` plus raw utilization, timing,
  reference, and simulation evidence.

Each checkpoint report must state:

- function and interface;
- arithmetic/fixed-point contract;
- test coverage and vector count;
- XSim PASS/FAIL;
- LUT, FF, DSP, BRAM/RAMB utilization;
- exact latency and initiation interval;
- WNS and whether 200 MHz is achieved;
- inferred or instantiated arithmetic/memory primitives;
- known limitations and unresolved issues.

The next planned checkpoint is `pe_gate_postprocess.v`. It is not implemented,
verified, or part of the baseline at the time of this document update.
