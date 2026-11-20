# CP5 Isolated Subsystem Phase A Interface

Status: interface frozen for the CP5 implementation of
`sequential-v4-sparse-load-v1`

This checkpoint freezes the wrapper ABI and the ownership rules between the
CP3 planner, CP4 sparse-load service, context store, Sequential v4 controller,
and frozen PE.  It contains no CP5 implementation RTL and does not authorize
any production accelerator-top change.

The normative architecture remains
`docs/SEQUENTIAL_V4_SPARSE_LOAD_V1_CONTRACT.md`.  The planner and service sides
of this boundary remain governed by
`docs/CP3_SPARSE_PLANNER_PHASE_A_INTERFACE.md` and
`docs/CP4_SCATTER_LOAD_PHASE_A_INTERFACE.md` respectively.

## 1. Module identity and parameters

The isolated wrapper module is named:

```text
sequential_v4_sparse_memory_subsystem
```

It is a new module and must be compiled only by an explicit
`sparse_memory_v1/` allowlist.  It shall not replace, shadow, instantiate, or
be instantiated by the existing production `sequential_v4_pe_memory_subsystem`.

| Parameter | Default | Meaning |
| --- | ---: | --- |
| `AXI_ADDR_WIDTH` | 32 | Read-only parameter-image address width |
| `AXI_DATA_WIDTH` | 64 | Frozen v1 data width; other values are unsupported |
| `AXI_ID_WIDTH` | 1 | AXI read ID width |
| `LOAD_TIMEOUT_CYCLES` | 100,000 | Raw loader progress timeout |
| `CONTROLLER_TIMEOUT_CYCLES` | 1,000,000 | Sequential job-controller timeout |
| `LUT_STALL_TIMEOUT_CYCLES` | 100,000 | PE LUT-configuration stall timeout |

There is no planner timeout parameter.  Legal descriptor/list and plan-result
backpressure can last indefinitely; lack of a handshake is not itself a CP3
fault.

## 2. Clock, reset, and control inputs

Directions in all tables are relative to the wrapper.

| Signal | Width | Direction | Contract |
| --- | ---: | --- | --- |
| `clk` | 1 | in | Single 100 MHz PL clock for every isolated component |
| `rst_n` | 1 | in | Active-low coordinated synchronous reset |
| `abort` | 1 | in | Fatal abort request; accepted AXI traffic is drained safely |
| `clear_error` | 1 | in | Compatibility input; cannot restore operation after fatal state |
| `clear_state` | 1 | in | One-cycle recurrent state/list clear, legal only at global idle |
| `parameter_base_addr` | `AXI_ADDR_WIDTH` | in | 64-byte-aligned base of the pinned v4 image |

The wrapper samples `parameter_base_addr` with a stage request and checks that
it remains stable through the attempt.  After the one-time LUT is initialized,
the base address is the reset-epoch identity and any change is fatal.  Image
version is not an external port; the wrapper and service use the frozen v4
constant.

A legal `clear_state` requires the wrapper to be empty, with no resident stage,
planner transaction, loader command/burst, controller job, context producer or
commit, held context response, feature transaction, coefficient output, or PE
operation.  It clears context validity and descriptor `present` metadata but
does not scrub payload RAM.  An asserted `clear_state` outside that boundary is
fatal and is not forwarded as a recoverable local clear.

## 3. Stage-load boundary

The existing stage request fields and ready/valid behavior are retained.  The
only new functional input is `sparse_load_enable`.

| Signal | Width | Direction | Contract |
| --- | ---: | --- | --- |
| `stage_req_valid` | 1 | in | Held stage request valid |
| `stage_req_ready` | 1 | out | Request can be accepted at the global empty/safe boundary |
| `stage_id` | 4 | in | Sequential v4 stage ID; legal values are 0..11 |
| `stage_bank` | 2 | in | Existing bank field; only zero is supported |
| `sparse_load_enable` | 1 | in | Per-stage load mode sampled at request handshake |
| `stage_load_done` | 1 | out | One-cycle successful-residency-publication pulse |
| `stage_load_error` | 1 | out | Sticky failed-attempt indication until coordinated reset |

`stage_id`, `stage_bank`, `sparse_load_enable`, and the base address are sampled
only on `stage_req_valid && stage_req_ready`.  The requester holds all fields
stable while valid waits for ready.  Later changes, including changes to
`sparse_load_enable`, do not alter the accepted attempt.

`stage_req_ready` is high only when all of the following are true:

1. reset is deasserted and no component has requested reset;
2. the previous resident stage was released;
3. the planner and service are empty and can accept a new transaction;
4. the controller, PE, context producer/commit path, and every held response
   are idle, and the LUT adapter is quiescent (`IDLE` before initialization or
   `READY` afterward);
5. `clear_state` and `abort` are low.

An accepted invalid stage ID or nonzero bank enters fatal state without
starting the planner or AXI.  It asserts `stage_load_error`, never
`stage_load_done`, and creates a failed diagnostic snapshot.  In all other
cases the same external handshake becomes the CP3 `plan_req` handshake;
`sparse_load_enable` is forwarded as `plan_req_sparse_enable`.

The stage completion rules are strict:

- a planner result must first handshake into the CP4 service;
- all selected rows, mandatory dense matrix bytes, complete parameters, and
  any first-request LUT initialization must complete;
- only the CP4 atomic publication transition can assert `stage_load_done`;
- a planner, service, context, AXI, LUT, controller, or integration fault
  asserts `stage_load_error` and can never produce a successful done pulse.

This success-only definition intentionally differs from any legacy behavior
that asserted done and error together.  It is required by the CP1 residency
contract and must be accounted for explicitly in any future top-promotion
review.

## 4. Existing job boundary

The fullband and shared-subband ports retain their Sequential v4 widths and
held start/ready semantics.

| Signal | Width | Direction | Contract |
| --- | ---: | --- | --- |
| `fb_start` | 1 | in | Fullband job valid |
| `fb_start_ready` | 1 | out | Matching resident FB stage can accept one job |
| `fb_stage` | 2 | in | FB stage selector 0, 1, or 2 |
| `fb_done` | 1 | out | One-cycle completed FB job pulse |
| `fb_error` | 1 | out | Shared-engine fatal indication |
| `sb_start` | 3 | in | Existing subband engine-valid vector; only `3'b001` is legal |
| `sb_start_ready` | 1 | out | Shared engine can accept the selected subband job |
| `sb_stage` | 2 | in | Subband-local stage 0, 1, or 2 |
| `sb_shared_branch` | 2 | in | Subband group 0, 1, or 2 |
| `sb_context_0` | 2 | in | Context for the supported shared engine |
| `sb_context_1` | 2 | in | ABI-retained, unused while `parallel_subbands=0` |
| `sb_context_2` | 2 | in | ABI-retained, unused while `parallel_subbands=0` |
| `sb_done` | 3 | out | Only bit zero may pulse in this baseline |
| `sb_error` | 3 | out | Only bit zero reports the shared-engine fatal state |

A start is accepted only after successful stage publication, with no planner
or loader ownership, and when its mapped stage equals `active_stage_id`.
Fullband and subband starts are mutually exclusive.  Any nonzero subband start
vector other than `3'b001`, simultaneous FB/SB start, illegal branch/context,
wrong stage, duplicate context, or out-of-order context is fatal and is not
forwarded to the controller.

The external subband tuple maps to the v4 stage as:

```text
mapped_stage = 3 + 3 * sb_shared_branch + sb_stage
controller_branch = sb_shared_branch + 1
controller_context = sb_context_0
```

The wrapper enforces the resident-stage job count and release boundary:

| Resident stage | Accepted job tuple(s), in order | Release after |
| ---: | --- | --- |
| 0 | `fb_stage=0` | the one FB job |
| 1 | `fb_stage=1` | the one FB job |
| 2 | `fb_stage=2` | the one FB job |
| 3 | `sb_shared_branch=0, sb_stage=0, context=0..3` | context 3 |
| 4 | `sb_shared_branch=0, sb_stage=1, context=0..3` | context 3 |
| 5 | `sb_shared_branch=0, sb_stage=2, context=0..3` | context 3 |
| 6 | `sb_shared_branch=1, sb_stage=0, context=0..2` | context 2 |
| 7 | `sb_shared_branch=1, sb_stage=1, context=0..2` | context 2 |
| 8 | `sb_shared_branch=1, sb_stage=2, context=0..2` | context 2 |
| 9 | `sb_shared_branch=2, sb_stage=0, context=0..1` | context 1 |
| 10 | `sb_shared_branch=2, sb_stage=1, context=0..1` | context 1 |
| 11 | `sb_shared_branch=2, sb_stage=2, context=0..1` | context 1 |

The first accepted subband context is zero and each later accepted job is the
next context.  The controller commits each GSU context before its `done`; the
cache remains resident across the 4/3/2 context sequence and the controller
releases it only after the final context's full PE barrier.  Projection jobs do
not commit recurrent data but obey the same context order and final release.

The wrapper does not require stage IDs themselves to arrive in numeric order.
Planner `present` checks enforce predecessor availability.  This permits
focused isolated tests while still failing closed if, for example, GSU2 is
requested before every GSU1 predecessor context has committed.

## 5. Dense-feature and coefficient boundaries

These existing ports are unchanged and are owned only by the controller/PE
during a published job.

| Signal | Width | Direction | Contract |
| --- | ---: | --- | --- |
| `feature_req_valid` | 1 | out | Held dense-feature scalar request |
| `feature_req_ready` | 1 | in | External provider acceptance |
| `feature_req_stage_id` | 4 | out | Active stage identity |
| `feature_req_branch` | 2 | out | Existing controller branch identity |
| `feature_req_context` | 2 | out | Existing controller context identity |
| `feature_req_source` | 10 | out | Dense source index |
| `feature_req_tag` | 8 | out | Request transaction tag |
| `feature_rsp_valid` | 1 | in | Held feature response |
| `feature_rsp_ready` | 1 | out | Controller response acceptance |
| `feature_rsp_value` | 8 signed | in | INT8 feature scalar |
| `feature_rsp_tag` | 8 | in | Must match the accepted request tag |
| `feature_rsp_error` | 1 | in | Fatal provider error indication |
| `coefficient_valid` | 1 | out | Held projection coefficient valid |
| `coefficient_ready` | 1 | in | External sink acceptance |
| `coefficient_value` | 8 signed | out | INT8 coefficient |
| `coefficient_index` | 9 | out | Projection output index |
| `coefficient_tag` | 16 | out | Existing PE transaction tag |
| `coefficient_last` | 1 | out | Final coefficient of this projection job |

Every output payload remains stable while its valid is high and ready is low.
Sparse loading never changes feature request identity/order, response checking,
coefficient identity/order/last, active-index production, or arithmetic.

## 6. Read-only AXI boundary

The wrapper preserves the frozen read-only AXI master interface without an
interconnect, width converter, or additional outstanding channel.

| Signal | Width | Direction |
| --- | ---: | --- |
| `m_axi_araddr` | `AXI_ADDR_WIDTH` | out |
| `m_axi_arid` | `AXI_ID_WIDTH` | out |
| `m_axi_arlen` | 8 | out |
| `m_axi_arsize` | 3 | out |
| `m_axi_arburst` | 2 | out |
| `m_axi_arprot` | 3 | out |
| `m_axi_arcache` | 4 | out |
| `m_axi_arqos` | 4 | out |
| `m_axi_arlock` | 1 | out |
| `m_axi_arvalid` | 1 | out |
| `m_axi_arready` | 1 | in |
| `m_axi_rdata` | `AXI_DATA_WIDTH` | in |
| `m_axi_rid` | `AXI_ID_WIDTH` | in |
| `m_axi_rresp` | 2 | in |
| `m_axi_rlast` | 1 | in |
| `m_axi_rvalid` | 1 | in |
| `m_axi_rready` | 1 | out |

AXI address/control remains stable from assertion of `ARVALID` through the AR
handshake.  Each accepted AR burst is INCR, contains at most 16 64-bit beats,
and does not cross a 4 KiB source boundary.  RID, RRESP, RLAST, beat count, and
timeout are checked by the CP4 loader.  After a fatal event, an already
accepted burst is drained with cache writes disabled; no later burst is
created.  DDR movement is counted only by `RVALID && RREADY`, multiplied by
eight.

## 7. Planner/context arbitration

One two-bit internal owner register controls both context descriptor and list-
entry channels:

| Encoding | Owner | Legal wrapper phase |
| ---: | --- | --- |
| `0` | none | empty, loading, or release transition |
| `1` | planner | from accepted stage request through plan/service handshake |
| `2` | controller | published stage through final release handshake |
| `3` | fatal/reserved | no requests forwarded |

Ownership changes only when no descriptor or list request is pending and no
response is held.  Requests, ready, responses, tags, errors, descriptor count,
and descriptor `present` are routed only to the registered owner.  The inactive
client sees request-ready low and response-valid low.  An unsolicited response,
response to the wrong owner, or ownership transition with an outstanding/held
transaction is fatal.

Planner ownership additionally requires controller idle, PE barrier idle,
`producer_busy=0`, `context_commit_valid=0`, and `clear_state=0`.  The wrapper
blocks all controller job starts, producer opens, state writes, active-list
appends/finalize, and commits while the planner owns the port.  If any mutation
request appears during planner ownership, it is not accepted and the wrapper
enters fatal state.

The CP3 plan channel connects directly to the CP4 plan channel with the frozen
fields:

```text
plan_stage_id, plan_sparse_enable, plan_fallback_full, plan_matrix_count,
plan_bitmap0[319:0], plan_bitmap1[319:0],
plan_count0[8:0], plan_count1[8:0]
```

The planner retains ownership and all safety conditions until
`plan_valid && plan_ready`.  The service then owns the cache while loading and
the context owner becomes none.  On atomic residency publication the context
owner becomes controller.  The union bitmaps remain immutable even when GSU
jobs later commit replacement self-lists; they describe the rows selected from
the stage-request snapshot.

## 8. Memory/controller/PE invariants

The CP4 service is the controller's sole weight and parameter provider.  The
existing request/response widths, tags, record layout, and response
backpressure remain unchanged.  A weight request to a source not resident in
the published bitmap is fatal and returns no stale cache data.  Complete
parameter residency is required before the first controller job can start.

The LUT adapter retains one-start followed by exactly 2,040 accepted
table-major bytes.  It contains no payload RAM.  The first reset-epoch stage
cannot publish until the PE reports successful LUT configuration.  Later
stages reuse PE LUT residency; reset clears it.

The wrapper preserves one frozen PE instance, the existing 16-bit transaction
tag, gate/membrane/projection order, and all full-barrier checks.  CDF remains
tied inactive.  There is no second PE, parameter cache, context store, or
active-list producer.

## 9. Lifecycle and diagnostic outputs

The existing focused integration outputs remain in the ABI.

| Signal | Width | Direction | Meaning |
| --- | ---: | --- | --- |
| `pe_barrier_idle` | 3 | out | Bits 2:1 are one; bit 0 is the shared-engine full barrier |
| `pe_fault` | 3 | out | Bits 2:1 are zero; bit 0 mirrors aggregate fatal state |
| `reset_required` | 1 | out | Sticky aggregate fatal state |
| `active_stage_id` | 4 | out | Atomically published resident stage |
| `cache_state` | 3 | out | CP4 service/cache coarse state |
| `compute_owner` | 4 | out | Existing PE ownership diagnostic |
| `lut_adapter_state` | 3 | out | Existing LUT adapter state |
| `lut_accepted_bytes` | 12 | out | PE LUT data-channel handshakes, not DDR traffic |
| `lut_configuration_starts` | 2 | out | PE LUT start handshakes this reset epoch |
| `controller_state` | 6 | out | Existing controller state diagnostic |
| `controller_row_tile` | 6 | out | Existing active row tile |
| `weight_request_count` | 32 | out | Existing accepted job weight requests |
| `dense_weight_request_count` | 32 | out | Existing dense-role weight requests |
| `sparse_weight_request_count` | 32 | out | Existing sparse-role weight requests |
| `memory_error_valid` | 1 | out | CP4 service fatal source |
| `memory_error_code` | 8 | out | CP4 service error class |
| `context_error_valid` | 1 | out | Context-store fatal source |
| `context_error_code` | 8 | out | Context-store error class |
| `controller_error_valid` | 1 | out | Controller fatal source |
| `controller_error_code` | 8 | out | Controller error class |
| `integration_error_valid` | 1 | out | Wrapper/LUT/arbitration/schedule fatal source |
| `integration_error_code` | 8 | out | First wrapper error class |
| `integration_error_detail` | 32 | out | First wrapper error detail |

The new planner and traffic diagnostics are:

| Signal | Width | Direction | Meaning |
| --- | ---: | --- | --- |
| `context_port_owner` | 2 | out | Registered owner encoding from section 7 |
| `planner_error_valid` | 1 | out | CP3 sticky fatal source |
| `planner_error_code` | 8 | out | CP3 first error class |
| `planner_error_detail` | 32 | out | CP3 first error detail |
| `stage_diag_valid` | 1 | out | A complete attempt snapshot is available |
| `stage_diag_success` | 1 | out | Snapshot ended in atomic residency publication |
| `stage_diag_stage_id` | 4 | out | Sampled external stage ID |
| `stage_diag_sparse_enable` | 1 | out | Sampled external sparse-enable value |
| `stage_diag_fallback_full` | 1 | out | Complete-stage fallback was selected |
| `stage_dense_reference_bytes` | 32 | out | Generated v4 full-stage transfer bytes |
| `stage_planned_bytes` | 32 | out | Selected stage plan bytes; LUT excluded |
| `stage_actual_bytes` | 32 | out | Accepted stage R beats times eight; LUT excluded |
| `stage_saved_bytes` | 32 | out | Dense reference minus actual, valid only on success |
| `stage_union_count0` | 9 | out | CP3 matrix-0 union population |
| `stage_union_count1` | 9 | out | CP3 matrix-1 union population |
| `stage_copy_command_count` | 16 | out | Accepted logical CP4 stage commands; LUT excluded |
| `stage_ar_burst_count` | 32 | out | Accepted stage AR handshakes; LUT excluded |
| `stage_load_cycles` | 32 | out | External request handshake through success/failure |
| `epoch_lut_actual_bytes` | 32 | out | Accepted LUT DDR R beats times eight since reset |

`stage_diag_valid` is cleared on the next accepted stage request and otherwise
holds the complete snapshot until reset.  All snapshot fields update
atomically.  `stage_load_done` and a successful snapshot are produced in the
same transition.  A failed accepted request also produces a snapshot, with
`stage_diag_success=0` and `stage_saved_bytes=0`; bytes, commands, bursts, and
cycles already accepted before the fault remain visible.  A planner or wrapper
validation failure before CP4 acceptance reports zero stage actual bytes,
commands, and bursts.

`stage_load_cycles` is an end-to-end wrapper counter beginning at the external
stage handshake, so it includes list planning and first-stage LUT work.  Any
service-local load-cycle diagnostic is internal and must not be substituted for
this value.  Successful attempts require
`stage_actual_bytes == stage_planned_bytes`.  Dense fallback additionally
requires both equal `stage_dense_reference_bytes`.

## 10. Fault aggregation and protocol quiescence

`reset_required` is the OR of sticky first-fault state from the planner,
service, context store, controller, wrapper/LUT/schedule checks, PE overflow,
and PE protocol checks.  External `abort` also causes sticky fatal state.  The
first local error code/detail is retained; later errors must not overwrite it.

After aggregate fault:

- no new stage, job, context, feature, coefficient, plan, cache-read, or AXI AR
  request is created;
- no tentative plan or partial cache content is published;
- an already asserted ready/valid payload remains protocol-stable until its
  required handshake or coordinated reset;
- already accepted AXI read traffic is drained with cache writes disabled;
- `stage_load_done`, `fb_done`, and `sb_done` cannot claim successful work;
- `fb_error`, `sb_error[0]`, `pe_fault[0]`, and `reset_required` expose the
  shared reset-only failure.

`clear_error` may clear only compatibility presentation that is not used for
the aggregate reset decision.  Recovery requires `rst_n=0` across every
component and the AXI-side state.  Reset clears planner results, list presence,
cache residency, stage ownership, LUT readiness, job-sequence tracking,
diagnostic validity/counters, and every fatal latch; payload memories need not
be scrubbed.

## 11. Dense/sparse differential acceptance

CP5 compares two executions with identical v4 image, reset, feature values,
external backpressure, stage/job sequence, and context initialization.  One
execution samples `sparse_load_enable=0` for every stage; the other samples one
for every stage.  Different stage-load latency and AXI address traffic are
expected and are not numerical differences.

The following observables must be exactly equal after aligning on handshakes,
not raw wall-clock cycles:

1. every legal weight response data/tag/error for the controller's request
   sequence;
2. every parameter record, kind, valid-bit count, and tag;
3. dense feature request stage/branch/context/source/tag order and consumed
   feature values;
4. PE command identity and arithmetic result at each logical transaction;
5. recurrent state writes and final state for all twenty identities;
6. committed active-list `present`, count, ordered indices, and logical mapping;
7. projection coefficient value/index/tag/last order;
8. job done/error ordering, context commit points, full barriers, and stage
   release identity.

The permitted differences are the DDR AR address/length sequence, stage actual
bytes, logical copy-command count, AR-burst count, and stage-load cycles.  For
two successful frames:

- dense mode transfers exactly `2 * 1,050,544` stage bytes;
- the reset epoch transfers one additional 2,040 LUT bytes;
- sparse stage bytes equal the CP2 oracle for the planner snapshots;
- each accepted sparse weight request names a row resident in that stage's
  matrix-wise union;
- sparse mode must not claim a saved byte from an AXI request count, cache read
  count, or unaccepted R beat.

The connected regression uses the real pinned v4 image, all twelve stages,
FB plus every 4/3/2 subband context, and at least two frames so first-frame
missing self-lists and next-frame committed self-lists are both exercised.

## 12. Isolation and evidence boundary

The CP5 compile file shall list every source explicitly, and every resolved
source/include path shall remain below `sparse_memory_v1/`.  No source from the
existing `rtl/memory/`, `rtl/integration/`, `rtl/top/`, global control tree, or
accelerator-top manifest may be compiled directly.  Immutable PE/control
dependencies are used only through the hash-pinned local imports.

CP5 does not modify the production global FSM or accelerator top, and its
module is not added to their source lists.  Its XSim result, when available,
proves isolated functional equivalence only.  CP6 isolated OOC/route evidence
does not establish accelerator-top timing; CP7 board A/B evidence uses a
separate isolated block design and artifact namespace.  Promotion remains a
new, explicitly authorized integration task after CP8 freeze.

Any implementation that needs to change a port width, sampled boundary,
context-owner transition, stage reuse sequence, completion meaning, counter
definition, or fault-recovery rule must return to a reviewed CP5 Phase A
revision before Phase B is accepted.
