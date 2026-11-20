# Codex handoff: PE Controller/FSM and Memory integration

## Mission status

The PE subsystem has a formally promoted and frozen baseline. Continue with
Controller/FSM and Memory-side interface mapping and integration; do not
redesign or edit the PE baseline.

The only formal PE RTL source is:

```text
rtl/pe_array/baseline/v1/
```

The frozen PE subsystem integration contract is:

```text
rtl/pe_array/baseline/v1/rtl/top/pe_array_datapath.v
```

Baseline v1 contains exactly eleven arithmetic/functional leaves plus one
separately classified integration wrapper, `pe_array_datapath`. The wrapper
is not a twelfth leaf. RTL elsewhere under `rtl/pe_array/rtl/` is not a
formal integration dependency unless a later approved baseline explicitly
contains it.

## Hard-stop baseline rules

- Treat every file below `rtl/pe_array/baseline/v1/` as read-only.
- Never modify, delete, rename, format, overwrite, regenerate, or copy over a
  baseline/v1 file.
- Controller/FSM and Memory RTL must adapt to the existing
  `pe_array_datapath.v` interface.
- Do not alter the PE baseline to simplify integration.
- If any interface incompatibility or required PE change is discovered:

  1. stop immediately;
  2. report the exact incompatible ports/protocol and the reason;
  3. do not modify `baseline/v1/`;
  4. wait for explicit user approval.

- If a future PE change is explicitly approved, create a new checkpoint and a
  new baseline version. Never overwrite baseline/v1.

## Before making any change

Complete this checklist in order:

1. Read `rtl/pe_array/AGENTS.md`.
2. Read `rtl/pe_array/spec/MODULE_DEVELOPMENT_PLAN.md`.
3. Read `rtl/pe_array/HANDOFF.md`.
4. Read `rtl/pe_array/PE_INTEGRATION_HANDOFF.md`.
5. Read `rtl/pe_array/CODEX_INTEGRATION_HANDOFF.md`.
6. Read `rtl/pe_array/baseline/v1/MANIFEST.md`.
7. Check the current Git branch, HEAD, status, and worktree.
8. Preserve all existing unrelated dirty and untracked state.
9. Never modify `rtl/pe_array/baseline/v1/`.

`MODULE_DEVELOPMENT_PLAN.md` remains authoritative for architecture
invariants, but some of its module-completion status text predates the current
promotion. Use `baseline/v1/MANIFEST.md`, the current handoffs, and the latest
explicit user approval for formal completion status.

## Important repository paths

| Purpose | Path |
| --- | --- |
| Repository root | `/home/ivanhuang/projects/Zephyr_fpga_inference` |
| PE rules | `rtl/pe_array/AGENTS.md` |
| Persistent architecture plan | `rtl/pe_array/spec/MODULE_DEVELOPMENT_PLAN.md` |
| Detailed PE checkpoint handoff | `rtl/pe_array/HANDOFF.md` |
| Human integration handoff | `rtl/pe_array/PE_INTEGRATION_HANDOFF.md` |
| This Codex handoff | `rtl/pe_array/CODEX_INTEGRATION_HANDOFF.md` |
| Frozen baseline manifest | `rtl/pe_array/baseline/v1/MANIFEST.md` |
| Frozen integration top | `rtl/pe_array/baseline/v1/rtl/top/pe_array_datapath.v` |
| Baseline checksums | `rtl/pe_array/baseline/v1/SHA256SUMS` |
| Accepted connected evidence | `rtl/pe_array/baseline/v1/reports/pe_array_datapath/` |

## Frozen constants and micro-contract

Default top parameters:

- `INDEX_WIDTH = 9`
- `BIN_INDEX_WIDTH = 8`
- external user tag width = 16

Encodings:

| Field | Encoding |
| --- | --- |
| `compute_owner` | NONE=`0000`, RAW=`0001`, GATE=`0010`, MEMBRANE=`0100`, CDF=`1000` |
| `ctrl_pe_mode` | DENSE=`0`, SPIKE=`1`, GATE=`2`, DIRECT=`3` |
| Gate component | INPUT=`0`, RECURRENT=`1` |
| Shared-RQ `op_kind` | QBN=`0`, Linear=`1` |

Frozen tag formats:

- Physical Local RQ `TAG_WIDTH=20`
  - Gate: `{gate, component, group[1:0], user_tag[15:0]}`
  - Membrane: `{1'b0, membrane_tag[18:0]}`
- Gate Postprocess and Sigmoid `TAG_WIDTH=18`
  - `{group[1:0], user_tag[15:0]}`

Other frozen stream behavior:

- Serializer emits active lanes in ascending lane order.
- Inactive lanes are skipped.
- Scalar index is `base_index + selected_lane`.
- `last` means the final valid neuron of the logical vector, not each tile.
- Membrane signed INT8 results are sign-extended to signed INT32 before the
  serializer.
- QBN state and Linear coefficient outputs are signed INT8 saturated to
  `-127..127`.
- Active-bin CDF Xr/Xi/Cr/Ci operands must be signed INT8 in `-127..127`;
  `8'h80` is illegal because `-Ci` must remain exactly representable. CDF
  real/imag results are signed INT32 per bin with no RQ, rounding, or
  saturation.
- Spike predicate is signed `state_q >= 0`; zero spikes.

Do not change widths, encodings, tag layouts, ordering, signedness, or
last/finalize semantics in Controller or Memory adapters.

## Top-level interface ownership

Directions below are relative to `pe_array_datapath`.

### Controller/FSM-owned control and scheduling

Controller drives or schedules:

- clock/reset: `clk`, `rst_n`;
- external compute ownership:
  - `raw_owner_request`
  - `gate_owner_request`;
- RAW/GATE physical-PE commands:
  - `ctrl_pe_acc_clear[15:0]`
  - `ctrl_pe_acc_enable[15:0]`
  - `ctrl_pe_mode[1:0]`
  - `ctrl_pe_operand_a[16*8-1:0]`
  - `ctrl_pe_operand_b[16*8-1:0]`
  - `ctrl_pe_gate_u8[16*8-1:0]`
  - `ctrl_pe_spike_enable[15:0]`
  - `ctrl_pe_direct_value[16*32-1:0]`;
- gate tile context: `gate_tile_*`;
- gate four-lane Local-RQ packets: `gate_rq_*`;
- matching gate bias transactions: `gate_bias_*`;
- Sigmoid resident-table configuration scheduling: `sigmoid_cfg_*`;
- membrane job descriptor and start: `membrane_start_*`,
  `membrane_u_prev`, cx/cell multiplier/shift, base index, logical-last;
- Linear accumulator-tile descriptor: `linear_tile_*`;
- CDF job descriptor/start and tap scheduling: `cdf_start_*`, `cdf_tap_*`.

Controller observes:

- `raw_owner_grant`, `gate_owner_grant`, `compute_owner`,
  `compute_idle`;
- `pe_accumulator`, `pe_overflow`;
- `gate_collect_complete`, `sigmoid_table_valid`;
- membrane ready/busy/done/phase;
- Linear tile ready;
- CDF ready/busy/done/phase/`cdf_active_tap_index`;
- all derived idle/outstanding outputs;
- `overflow_any` and sticky `protocol_error`.

Payload data may come from Memory-side providers, but the Controller owns
scheduling and legal transaction order.

### Memory/parameter-owned data services and sinks

Memory/integration owns:

- RAW/GATE operands, weights, and PE-command data fetch;
- Gate Local-RQ multipliers/shifts and gate bias values;
- Sigmoid configuration byte source;
- previous dense state supplied as `membrane_u_prev`;
- membrane cx/cell multiplier and shift parameters;
- Shared-RQ parameter lookup:
  - consume `rq_param_query_*`;
  - produce matching `rq_param_*`;
- dense QBN state sink: `state_write_*`;
- active-index command sink: `active_cmd_*`;
- Linear coefficient scalar sink: `coefficient_*`;
- coefficient reshape/staging/storage;
- CDF coefficient storage and spectrum temporal-history storage;
- CDF causal zero padding and per-tap Xr/Xi/Cr/Ci production;
- CDF signed-INT32 result sink: `cdf_result_*`.

The Controller and Memory implementation may partition request generation and
payload muxing differently, but the PE-facing port protocol must remain
unchanged.

## Valid/ready and backpressure rules

Apply these rules to every true ready/valid channel:

1. A transaction transfers exactly once on `valid && ready`.
2. The producer must hold `valid` and every payload/metadata field stable
   while `valid && !ready`.
3. The consumer may apply arbitrary backpressure.
4. Never treat a valid pulse without ready as accepted.
5. Never change value, index, tag, mask, group, component, op-kind, or last
   while stalled.
6. Do not drop, duplicate, replay, or reorder a transaction across owner
   transitions.

Exceptions and special forms:

- `ctrl_pe_*` is a clocked per-cycle command interface, not a ready/valid
  stream. With no command, drive all `acc_clear` and `acc_enable` bits low.
  Do not assert clear and enable for the same lane in the same cycle;
  `acc_clear` has leaf priority.
- `raw_owner_request` and `gate_owner_request` are level requests, not
  one-cycle pulses. Hold a request through acquisition and its required
  ownership lifetime.
- `rq_param_query_*` is combinational look-ahead, not an accepted request.
- `done`, phase, and historical module latency are observational; none is a
  substitute for ready/valid handshakes and derived drain.

## Physical resource reuse and owner rules

| Physical resource | Legal use |
| --- | --- |
| 16 x `pe_hybrid_mac` | mutually reused by RAW, GATE, MEMBRANE, CDF |
| 1 x four-lane Local RQ Bank | reused by GATE and MEMBRANE |
| 1 x Gate Postprocess | reused by GATE and MEMBRANE |
| 1 x Sigmoid LUT | GATE datapath; configuration only while owner is NONE |
| 1 x Output Serializer | Membrane/QBN tile or RAW/Linear tile |
| 1 x Shared RQ Engine | QBN and Linear tokens selected by `op_kind` |
| Spike Decision + Active Index Writer | QBN only |
| CDF Sequencer | reuses the same 16 Hybrid PEs; no complex multiplier |

Owner lock rules:

- `compute_owner[3:0]` is a registered one-hot, all-or-none lock.
- The wrapper performs no priority arbitration.
- While owner is NONE, request vector must be zero or exactly one-hot.
- Multiple simultaneous requests do not select a winner and assert a protocol
  error.
- Every owner-to-owner transition passes through NONE.
- Controller directly controls RAW and GATE requests.
- Membrane start is accepted by the wrapper before the leaf raises its
  internal owner request.
- CDF has different acquisition semantics: held `cdf_start_valid` raises the
  leaf's CDF owner request before the start handshake. It must be the sole
  request while owner is NONE; only after CDF grant can `cdf_start_ready`
  assert and accept the job.
- Do not assert RAW/GATE requests against an active or pending Membrane/CDF
  ownership sequence.

Recommended external-owner sequence:

1. Wait for `compute_idle=1`.
2. Assert exactly one of `raw_owner_request` or `gate_owner_request`.
3. Hold it until the corresponding grant.
4. Issue only commands valid for that owner.
5. Stop all old-owner input valids and PE commands.
6. Deassert the old request.
7. Wait for `compute_owner==NONE` and the required derived drain.
8. Only then request the next phase.

Do not use a fixed cycle count or any accepted leaf latency to release or
switch an owner.

## Derived idle and drain contract

The wrapper derives drain from accepted-handshake accounting, held valids,
command-pipe state, and accumulator lifetime:

- `hybrid_idle`: registered full-cycle Hybrid quiescence proof and no live
  Controller command or active Membrane/CDF compute request.
- `local_rq_idle`: Local-RQ accepted request/response count is zero and no
  Membrane RQ command remains in the timing stage.
- `postprocess_idle`: no Membrane postprocess timing-stage command, no INPUT
  half-pair, and completed-pair outstanding count is zero.
- `sigmoid_idle`: accepted in/out count is zero and configuration is idle.
- `serializer_idle`: no serializer context, busy state, held output, or load.
- `shared_rq_idle`: Shared-RQ accepted input/output count is zero.
- `qbn_fork_idle`: no held QBN token remains.

`local_rq_outstanding`, `postprocess_outstanding`, and
`shared_rq_outstanding` expose the corresponding accepted-transaction
counts.

Owner release safety:

- RAW: Hybrid is drained, Controller clear/enable are zero, and
  `linear_tile_valid=0`.
- GATE: Hybrid, Local RQ, Postprocess, and Sigmoid are drained; no gate
  half-pair, gate-RQ valid, or bias valid remains; gate collection is complete,
  handed to Membrane, or absent.
- MEMBRANE: leaf owner request has dropped; Hybrid, Local RQ, and Postprocess
  are drained; no held membrane result remains.
- CDF: leaf owner request has dropped; CDF command pre-pipeline and Hybrid are
  drained; no held CDF result remains.

`compute_idle` only describes the compute-owner/acquire domain. It does not
mean Serializer, Shared RQ, or the QBN fork are empty. For a conservative
full-PE-subsystem barrier, require:

```text
compute_idle
&& serializer_idle
&& shared_rq_idle
&& qbn_fork_idle
&& local_rq_idle
&& postprocess_idle
&& sigmoid_idle
&& local_rq_outstanding == 0
&& postprocess_outstanding == 0
&& shared_rq_outstanding == 0
```

Also ensure every external input valid for the retiring phase is low.

Output-stall nuance:

- RAW ownership is retained until a live Linear accumulator tile is accepted
  by the serializer.
- MEMBRANE ownership is retained until its result is accepted by the
  serializer.
- CDF ownership is retained until the CDF result handshake.
- After a tile has been copied into the serializer, later Shared-RQ/state/
  coefficient stalls may overlap independent compute work. Do not incorrectly
  redefine `compute_idle` as full downstream drain.

## Strict Gate INPUT -> RECURRENT rule

Before Gate work:

- Sigmoid table must be valid.
- Accept one nonzero `gate_tile_lane_valid` context with its per-lane tags and
  table select.

For every required gate and four-lane group, send exactly:

```text
INPUT:
  gate_rq_component = 0
  gate/group/lane_mask/tags = P

then

RECURRENT:
  gate_rq_component = 1
  gate/group/lane_mask/tags = the same P
```

Rules:

- Do not interleave another gate/group between the two halves.
- The RECURRENT packet must match gate, group, lane mask, and every active-lane
  tag.
- Each packet mask must equal the corresponding four bits of the accepted gate
  tile mask.
- The wrapper does not snapshot Gate raw accumulators. Keep the selected
  `gate_rq_value` stable through its handshake and do not overwrite it with a
  new PE command.
- `gate=0` postprocess output is collected as `i_t`.
- `gate=1` postprocess output passes through Sigmoid and is collected as
  `lambda`.
- Every active lane must receive exactly one i_t and one lambda value before
  Gate-to-Membrane handoff.

Gate bias is an atomic join with the matching RECURRENT Local-RQ response:

- assert and hold `gate_bias_valid` with stable payload until ready;
- gate, group, lane mask, and active-lane tags must match the response;
- a wrong key is a protocol violation even where comparison is intentionally
  outside the timing-critical ready path.

Recommended Gate-to-Membrane handoff:

1. Complete all required Gate INPUT/RECURRENT pairs.
2. Wait for `gate_collect_complete`.
3. Stop Gate PE commands, Gate RQ valid, and bias valid.
4. Assert and hold `membrane_start_valid` plus all job fields.
5. Do not assert RAW/CDF request or Sigmoid configuration.
6. Deassert `gate_owner_request` when retiring Gate ownership.
7. Allow the registered lock to transition GATE -> NONE -> MEMBRANE.
8. Follow handshakes and derived idle; do not use a latency timer.

## Shared-RQ parameter atomic join and op-kind demux

`rq_param_query_*` is only a look-ahead key for the currently held serializer
scalar:

```text
{rq_param_query_op_kind, rq_param_query_index, rq_param_query_tag}
```

The parameter provider must return:

```text
rq_param_valid
rq_param_op_kind      == query op_kind
rq_param_index        == query index
rq_param_tag          == query tag
rq_param_multiplier   signed INT32
rq_param_shift        6 bits
rq_param_bias         signed INT32
```

Hold the response fields stable until `rq_param_valid && rq_param_ready`.
Serializer scalar and parameter response are accepted atomically only when
both are valid and the single Shared RQ core is ready. Query-key equality is a
protocol assertion, not a ready-path filter; Memory must prevent mismatched
responses from being presented.

Output demux is per token:

- `op_kind=QBN` -> QBN holding/fork -> dense state and spike decision.
- `op_kind=Linear` -> `coefficient_*` only.
- Linear must never enter Spike Decision or Active Index Writer.
- Do not instantiate a second Shared RQ or a second requant datapath.

## QBN exactly-once fork

The wrapper contains one holding register with independent
`state_pending` and `decision_pending` state:

- Every QBN scalar produces exactly one dense `state_write_*` transaction.
- Every QBN scalar is evaluated by Spike Decision exactly once.
- Decision cannot commit before its matching dense state write; it may commit
  on the same edge or later.
- State and decision sinks may stall independently without loss or replay.
- A retiring token may be replaced on the same edge, preserving no-stall II=1.
- Ordinary non-spike: consume decision, no active command.
- Terminal non-spike: emit finalize-only active command.
- Spike: emit write active command.
- Terminal spike: write and finalize are both asserted in one atomic command.

Memory must not attempt to reconstruct this fork or create a full spike vector.

## Memory ownership boundaries

### Dense state

PE supplies `state_write_{valid,value,index,tag,last}`. Memory owns the dense
state RAM, addressing, capacity, read scheduling, and `state_write_ready`.
The same store supplies future `membrane_u_prev`.

### Active index

PE supplies
`active_cmd_{valid,write,index,tag,finalize}`. Memory owns active count,
write pointer, full/capacity state, frame bookkeeping, and index storage.
Backpressure is returned only with `active_cmd_ready`.

### Linear coefficients

PE supplies signed-INT8 values saturated to `-127..127` on
`coefficient_{valid,value,index,tag,last}`. Memory/integration owns reshape,
resident staging, coefficient addressing, and later CDF tap reads.

### CDF spectrum history

Memory owns the complete noisy-spectrum temporal history and causal padding.
For each accepted CDF job it supplies tap packets oldest-to-newest and only
when `cdf_tap_index` matches `cdf_active_tap_index`:

- `tap_index` must be `0, 1, ..., order-1` in sequence;
- `tap_index=0` represents frame `t-order+1`;
- `tap_index=order-1` is the current frame;
- causal padding is supplied as `Xr=Xi=0`;
- active-bin Xr/Xi/Cr/Ci values must be in signed-INT8 range `-127..127`;
  `8'h80` is a protocol error and must never be supplied.

PE returns up to eight signed-INT32 real/imag results with bin mask, order,
base, band, and tag. Memory owns the result sink/storage.

Do not put active-index storage, coefficient staging, spectrum history, causal
padding storage, parameter RAM, or dense state RAM into the PE wrapper.

## Forbidden integration changes

Do not:

- place the production Controller FSM inside `pe_array_datapath`;
- place Memory RAM or storage inside `pe_array_datapath`;
- modify any baseline/v1 leaf or wrapper;
- infer owner switching from fixed latency;
- add a FIFO, scoreboard, second tile buffer, or full spike vector;
- add any arithmetic unit, multiplier, DSP path, Local RQ lane, Shared RQ core,
  or dedicated complex multiplier;
- duplicate physical arithmetic for RAW/GATE/MEMBRANE/CDF phases;
- bypass ready/valid backpressure;
- change tag/index/last/op-kind metadata;
- route Linear output into the QBN spike path.

Adapters outside the frozen PE wrapper are permitted only when they preserve
the exact PE-facing protocol and remain within the separately approved
Controller or Memory task scope.

## Accepted evidence and timing boundary

Accepted connected evidence:

- integer/Python bit-exact reference PASS;
- connected XSim PASS in 2,330 cycles;
- GSU -> Membrane -> QBN -> Spike -> Active Index flow PASS;
- Linear -> Shared RQ -> behavioral coefficient staging -> CDF flow PASS;
- owner transitions under randomized parameter delay and downstream
  backpressure PASS;
- hierarchy: 16 Hybrid MAC, one Local RQ Bank, five total physical requant
  lanes, one Shared RQ Engine;
- resources: 36 DSP48E1 and two RAMB18E1.

Timing status at 100 MHz / 10.000 ns:

- internal register-to-register setup WNS = +0.727 ns: PASS;
- internal register-to-register hold WHS = +0.056 ns: PASS;
- overall setup WNS = +0.254 ns;
- standalone OOC boundary hold WHS = -1.368 ns;
- standalone OOC boundary timing is not clean;
- `timing_constraints_met=0`.

Do not claim complete 100 MHz top-level timing closure. Do not claim 200 MHz:
**200 MHz is not the verified operating point for the connected wrapper.**

The accepted test used behavioral Controller and Memory/parameter agents. It
is not production Controller/Memory integration, bitstream, or board evidence.

## Recommended next step

Controller and Memory owners must independently map every relevant port and
protocol in
`rtl/pe_array/baseline/v1/rtl/top/pe_array_datapath.v`. Review and agree on
the mapping before either side begins RTL integration.

After production Controller and Memory integration, rerun:

1. system-level self-checking XSim;
2. Python/integer golden bit-exact comparison;
3. randomized backpressure and owner-switch stress;
4. exactly-once state/active-index/coefficient checks;
5. hierarchy and physical-resource-count checks;
6. top-level synthesis, placement, and routing;
7. complete setup and hold timing closure with real system boundaries.
