# `sequential_pe_job_controller` Phase A Interface Review

Status: approved by the user-provided sequential-v4 implementation plan

Scope: one controller for the deliberately serialized v4 baseline.  It owns
job validation, sparse source iteration, parameter selection, PE ownership,
and completion sequencing.  It contains no parameter RAM, recurrent RAM,
active-list RAM, AXI master, coefficient storage, CDF datapath, ping-pong
placement, or sparse-DDR prefetch logic.

## 1. Job identity and existing FSM mapping

The generic job request is a held ready/valid transaction:

```text
job_valid / job_ready
job_stage_id[3:0]
job_branch[1:0]
job_context[1:0]
job_done                  // one-cycle success pulse
job_error                 // sticky fatal level
```

Branch zero denotes fullband.  Branches one, two, and three denote SB0, SB1,
and SB2.  Legal tuples are:

| Stage IDs | Branch | Legal contexts | Operator |
|---|---:|---:|---|
| 0, 1, 2 | 0 | 0 | FB GSU1, GSU2, projection |
| 3, 4, 5 | 1 | 0..3 | SB0 GSU1, GSU2, projection |
| 6, 7, 8 | 2 | 0..2 | SB1 GSU1, GSU2, projection |
| 9, 10, 11 | 3 | 0..1 | SB2 GSU1, GSU2, projection |

The integration wrapper derives this generic request from the existing
`fsm` ports.  Fullband `fb_stage` maps directly to stage 0..2.  A subband job
maps as `3 + sb_shared_branch*3 + sb_stage`, and adds one to the FSM's
zero-based branch number for `job_branch`.

`job_ready` is high only when the controller is idle, healthy, and no previous
completion pulse remains.  An accepted illegal tuple is a sticky fatal error;
it is not left waiting indefinitely.

## 2. Cache ownership clarification

The existing global FSM loads a subband stage once and then runs every context
that shares that stage.  Therefore a successful non-final subband-context job
must retain the cache.  The controller issues `stage_release_*` only for:

- every fullband job; or
- the last context of an SB branch: context 3 for SB0, 2 for SB1, and 1 for
  SB2.

All earlier contexts complete after a full PE barrier without releasing the
stage.  A final context reports `job_done` only after the matching release
handshake.  This is the only interpretation compatible with the existing FSM
and preserves one dense DDR load per branch/stage rather than one per context.

The global FSM remains the stage-load requester.  The controller does not
duplicate `stage_req_*`; it consumes the active-stage descriptors and owns
weight, parameter, and matching final-release traffic after job acceptance.

## 3. Active-stage validation

At job acceptance, the controller requires:

- `stage_ready_for_compute`, `lut_ready`, and matching `active_stage_id`;
- `image_version == 4` as enforced by `memory_service`;
- generated stage kind, matrix count, source counts, row-tile counts, and
  parameter-tile count matching the job role;
- a valid sigmoid table in the PE for GSU stages; and
- no memory-service, context-store, or PE fault.

GSU requires two matrices with equal nonzero row-tile counts and one parameter
record per tile.  Projection requires one matrix with the same row-tile and
parameter-tile count.  All current v4 dimensions are multiples of sixteen, so
every output tile has lane mask `16'hffff`.

The controller captures all active descriptors for the job.  They must remain
stable until the cache is released or the shared stage's final context ends.

## 4. Logical recurrent identities

For GSU jobs, the produced identity is:

```text
FB:  logical_id = layer
SB0: logical_id = 2  + context*2 + layer
SB1: logical_id = 10 + context*2 + layer
SB2: logical_id = 16 + context*2 + layer
```

`layer=0` denotes GSU1 and `layer=1` denotes GSU2.  Sparse-list sources are:

| Matrix role | List identity |
|---|---|
| GSU1 matrix 0 | none; external dense feature vector |
| GSU1 matrix 1 | current GSU1 logical identity |
| GSU2 matrix 0 | preceding GSU1 logical identity |
| GSU2 matrix 1 | current GSU2 logical identity |
| Projection matrix 0 | preceding GSU2 logical identity |

A GSU job opens one context-store producer before its first tile.  Projection
does not open or commit a recurrent context.

## 5. Active-list snapshot and replay

Each applicable list descriptor is read exactly once during job setup and its
nine-bit count is retained until completion.  GSU2 captures two descriptors;
GSU1 and projection capture one.  Descriptor and item transactions use one
eight-bit rolling context tag, with at most one transaction outstanding.

For every output row tile, each sparse matrix resets its ordinal to zero and
reads the retained list in strictly increasing order.  Every returned index
must be below that matrix's source count.  A count of zero causes no list-item
read, no weight request, and no MAC command.

The exact sparse weight-request cardinalities are:

```text
matrix requests = retained_active_count * matrix_row_tiles
```

The four GSU1 matrix-0 roles at stages 0, 3, 6, and 9 remain dense and issue
`matrix_sources * matrix_row_tiles` weight requests.  Active lists never alter
the prior full-stage DDR transfer.

## 6. External dense-feature provider

Only a GSU1 matrix-0 iteration uses this interface:

```text
feature_req_valid / feature_req_ready
feature_req_stage_id[3:0]
feature_req_branch[1:0]
feature_req_context[1:0]
feature_req_source[9:0]
feature_req_tag[7:0]

feature_rsp_valid / feature_rsp_ready
feature_rsp_value signed [7:0]
feature_rsp_tag[7:0]
feature_rsp_error
```

The controller requests one scalar, then one matching 128-bit weight word,
then emits one PE command.  It intentionally does not add lookahead or a FIFO.
The scalar is replicated to all sixteen `operand_a` lanes and the weight word
supplies the sixteen signed-INT8 `operand_b` lanes.

## 7. Serialized memory-service use

The controller directly drives the existing `weight_*`, `param_*`, and
`stage_release_*` channels.  Weight requests use the selected matrix, source
index, row tile, and one eight-bit rolling transaction tag.  Parameter requests
use the current row tile and the same no-overlap discipline.

Only one memory transaction may be outstanding.  A tag advances only after
the corresponding held response handshakes.  Wrong tags, response kind/width,
or response error are fatal.  A parameter record remains captured until every
Gate/Membrane or Linear/Shared-RQ use for that tile has drained.

## 8. RAW schedule and the only matrix-0 snapshot

The controller requests RAW ownership only from a fully idle owner state and
holds the level request through grant and RAW drain.  Each GSU row tile uses:

1. parameter-record read and old-state tile read;
2. one all-lane clear command and a handshake-derived Hybrid drain;
3. matrix 0 source iteration;
4. a Hybrid drain, followed by capture of exactly one 512-bit
   `16 x signed INT32` accumulator snapshot;
5. another all-lane clear and drain;
6. matrix 1 sparse iteration and drain, leaving the recurrent result live in
   the PE accumulators.

`MODE_DENSE` is used only for GSU1 matrix 0.  Every list-selected matrix uses
`MODE_SPIKE`, puts the 128-bit weight word on `operand_b`, and asserts all
sixteen `spike_enable` bits.  List selection has already proved the binary
source active; no dense recurrent scalar is fetched or multiplied.

The controller contains one 512-bit snapshot register, not 320 INT32 entries.
It must never issue a new Hybrid command while a value still required by Gate
or Linear is live.

Projection clears and accumulates its one sparse matrix under RAW ownership,
drains Hybrid, and then holds `linear_tile_*` until accepted.  RAW ownership is
not released before that capture.

## 9. Gate, Membrane, and Linear protocols

After a GSU RAW phase, the controller transitions RAW -> NONE -> GATE and
accepts one gate tile context with full lane mask, per-neuron tags, and the
captured v4 sigmoid-table select.

For forget gate then cell gate, and group zero through three, it emits exactly
one adjacent pair:

```text
INPUT(snapshot, input multiplier/shift)
RECURRENT(live accumulator, recurrent multiplier/shift)
```

The recurrent half retains a matching `gate_bias_*` transaction until the PE
accepts the bias with the RQ response.  The controller does not begin the next
pair until the previous bias handshake, preserving a deliberately conservative
single-pair schedule.

After `gate_collect_complete`, it deasserts `gate_owner_request` and asserts
held `membrane_start_valid` in the same controller phase.  The membrane payload
uses the retained old-state tile, previous-state multiplier/shift, cell-gate
multiplier/shift, base neuron index, and final-tile marker.  Tile completion is
not inferred from a fixed latency: `membrane_done` is observed and every
serializer/Shared-RQ/QBN sink is drained before the next row tile.

Projection uses `linear_tile_*` with full lane mask and the same canonical tags.
Its logical-last bit is high only on the final projection tile.  External
coefficient backpressure is reflected through the PE idle/barrier signals.

## 10. Parameter field mapping

The low 5,792 bits of the GSU response are interpreted only through generated
`MODEL_V4_GSU_PARAM_*` offsets.  Lane `n` is selected as:

```text
32-bit field: record[FIELD_LSB + n*32 +: 32]
 6-bit field: record[FIELD_LSB + n*6  +: 6]
```

Forget and cell input/recurrent fields drive the eight Gate RQ pairs and their
matching biases.  `PREVIOUS_*` and `CELLGATE_*` drive Membrane.  `BN_*` drives
QBN Shared-RQ responses.  Projection `OUTPUT_*` fields drive Linear Shared-RQ
responses.  Signed multipliers and biases are passed bit-exact; shifts are
unsigned six-bit values.

The numerical order is therefore fixed as two separate RQ operations:

```text
RQ_input(matrix0_snapshot) + RQ_recurrent(live_matrix1) + bias
```

No path may implement `RQ(matrix0 + matrix1)`.

## 11. Shared-RQ parameter join

The controller consumes the PE's combinational `rq_param_query_*` key and
produces a held matching parameter response from the retained tile record.
For QBN, op-kind is zero and the query index must be within the current GSU
tile.  For Linear, op-kind is one and the index must be within the current
projection tile.  Query tag must equal:

```text
{kind[1:0], logical_context_id[4:0], neuron_index[8:0]}
```

Kind zero is GSU and kind one is projection.  A query key mismatch is fatal;
the controller never presents mismatched parameters to make progress.  The
parameter payload and retained record remain stable under `rq_param_ready`
backpressure.

## 12. Full barrier, context commit, and completion

The controller's conservative PE barrier is:

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
&& all controller PE-facing valids/commands are inactive
```

After the final GSU tile reaches that barrier, the controller issues one
context commit with the produced logical ID and the same barrier proof.  It
waits for `commit_done`; a successful commit is required before job
completion.  Projection has no context commit.

The controller next releases the cache if this job is its final user under
Section 2.  `job_done` pulses only after commit, full barrier, and any required
release.  No fixed-cycle owner or pipeline drain is legal.

## 13. Fault and timeout behavior

Inputs include memory-service error, context-store error, PE
`overflow_any`/`pe_overflow`, and PE `protocol_error`.  The first fault captures
an eight-bit code plus 32-bit detail, enters sticky `error_valid`, asserts
`reset_required`, and suppresses further work.  `abort` is fatal; there is no
clean local abort or `clear_error` recovery.

Each blocking state has a parameterized watchdog.  Timeout while waiting for
feature, memory, context, PE ownership/handshake/drain, external coefficient
backpressure reflected in PE idle, commit, or release is fatal.  Recovery
requires the coordinated subsystem/AXI reset defined by the architecture
contract.

## 14. Phase B acceptance gates

Focused self-checking XSim plus an independent integer/Python reference shall
cover:

- all twelve real v4 stage geometries and every legal FB/SB context;
- zero, low-density, 25-percent, approximately-55-percent, and dense lists;
- exact ordered source indices and exact weight-request cardinalities;
- dense feature requests only for stages 0/3/6/9 matrix 0;
- zero-active matrices preserving cleared accumulators;
- one 512-bit matrix-0 snapshot and no 320-entry scratch;
- bit-exact GSU Gate/Membrane/QBN and projection Linear parameter selection;
- explicit rejection of the pre-summed single-RQ numerical order;
- owner transitions and full handshake-derived drains;
- arbitrary feature, memory, list, state, RQ-parameter, PE, coefficient, and
  commit/release backpressure;
- response mismatch, malformed job/descriptor/list index, overflow,
  protocol error, abort, and timeout;
- subband cache retention until each branch's final context.

Vivado 2018.3 controller-only OOC on `xc7z020clg400-1` at 100 MHz shall report
zero RAMB36E1, RAMB18E1, LUTRAM, SRL, and DSP48E1, with WNS >= 0.  The 5,792-bit
parameter holding register and 512-bit matrix snapshot may use flip-flops.

## 15. Allowed Phase B files

Phase B may add only `rtl/memory/sequential_pe_job_controller.v` as its
production module, plus directly associated focused TB/reference,
module-specific runner/constraint, and evidence reports.  It shall not modify
`memory.v`, `memory_service`, the context store, global FSM, frozen PE,
superseded ping-pong modules, or unrelated work.
