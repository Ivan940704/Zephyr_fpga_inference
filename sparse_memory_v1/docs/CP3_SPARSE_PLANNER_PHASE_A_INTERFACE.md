# CP3 sparse union planner Phase-A interface review

Status: interface frozen for the CP3 implementation in this isolated subtree

Baseline: `sequential-v4-sparse-load-v1`

Target: PYNQ-Z1 `xc7z020clg400-1`, 100 MHz

## 1. Boundary and objective

CP3 snapshots the persistent active lists needed by one Sequential-v4 stage
and emits two 320-bit source-residency bitmaps.  It does not issue AXI reads,
write the stage cache, change the v4 image, or connect to the production
accelerator top.  CP4 will consume the held plan and translate selected sources
into canonical-address copy commands.

All active files and evidence for this checkpoint remain below
`sparse_memory_v1/`.  The imported dense sources are immutable provenance.

The planner uses one list descriptor/read port exclusively while a plan is in
progress.  Planning starts only while the compute controller is idle, the
context producer is idle, and neither commit nor clear is asserted.  If any of
those conditions becomes false before the plan result handshakes, the planner
latches a reset-only fault and suppresses the result.

## 2. Stage-to-list contract

Logical recurrent-context IDs retain the dense baseline mapping:

```text
fullband: layer 0 = 0, layer 1 = 1
subband 46:  layer 0 = 2,4,6,8;    layer 1 = 3,5,7,9
subband 94:  layer 0 = 10,12,14;   layer 1 = 11,13,15
subband 158: layer 0 = 16,18;      layer 1 = 17,19
```

Within each stage-map entry, context IDs advance by two.  `required` means a
missing descriptor is fatal; `optional` means a missing recurrent self-list is
the legal reset/first-frame empty set.  A present descriptor with count zero is
always a valid empty list.

| Stage | Matrix 0 selection | Matrix 1 selection |
|---:|---|---|
| 0 | dense 64 | optional self ID 0 |
| 1 | required predecessor ID 0 | optional self ID 1 |
| 2 | required predecessor ID 1 | absent |
| 3 | dense 46 | optional self IDs 2,4,6,8 |
| 4 | required predecessor IDs 2,4,6,8 | optional self IDs 3,5,7,9 |
| 5 | required predecessor IDs 3,5,7,9 | absent |
| 6 | dense 94 | optional self IDs 10,12,14 |
| 7 | required predecessor IDs 10,12,14 | optional self IDs 11,13,15 |
| 8 | required predecessor IDs 11,13,15 | absent |
| 9 | dense 158 | optional self IDs 16,18 |
| 10 | required predecessor IDs 16,18 | optional self IDs 17,19 |
| 11 | required predecessor IDs 17,19 | absent |

The matrix source limits come from the imported v4 layout: fullband sparse
roles have 320 sources and subband sparse roles have 224 sources.  A returned
index at or beyond the applicable source limit is fatal.  Each individual list
must be strictly increasing; duplicates across different contexts are legal
and collapse in the union bitmap.

## 3. Planner request and result interface

The request is a conventional held ready/valid channel:

| Signal | Width | Direction | Meaning |
|---|---:|---|---|
| `plan_req_valid` | 1 | in | Request is present and fields are stable |
| `plan_req_ready` | 1 | out | Planner may accept the request this cycle |
| `plan_req_stage_id` | 4 | in | Sequential-v4 stage, legal range 0..11 |
| `plan_req_sparse_enable` | 1 | in | Sparse-mode value sampled at handshake |

`plan_req_ready` is asserted only in idle state with all safety conditions
true.  Once accepted, the stage and enable bit are sampled and are independent
of later input changes.

The result is held until `plan_valid && plan_ready`:

| Signal | Width | Direction | Meaning |
|---|---:|---|---|
| `plan_valid`, `plan_ready` | 1 each | out, in | Result handshake |
| `plan_stage_id` | 4 | out | Sampled stage ID |
| `plan_sparse_enable` | 1 | out | Sampled mode bit |
| `plan_fallback_full` | 1 | out | Use the original single full-stage load |
| `plan_matrix_count` | 2 | out | One for projection, two for GSU |
| `plan_bitmap0`, `plan_bitmap1` | 320 each | out | Selected canonical source indices |
| `plan_count0`, `plan_count1` | 9 each | out | Bitmap population counts |

A mandatory dense or absent matrix has a zero bitmap and zero count; CP4 derives
mandatory residency from stage geometry.  Every mapped descriptor and every
entry of a present list is still inspected when sparse mode is disabled, so
dense fallback cannot conceal a missing predecessor or malformed context data.
`plan_fallback_full` is one when the sampled sparse-enable bit is zero.  In
sparse mode it is one only when every sparse-eligible matrix has every valid
source bit set.  A mandatory dense matrix is excluded from this decision.

All result fields remain stable under output backpressure.  No partial bitmap
is externally valid.

## 4. Context-list interface and presence

The planner drives the existing single-outstanding descriptor and list-read
channels:

```text
descriptor request: valid/ready, logical_id[4:0], tag[7:0]
descriptor response: valid/ready, present, count[8:0], tag[7:0], error
list request:       valid/ready, logical_id[4:0], ordinal[8:0], tag[7:0]
list response:      valid/ready, index[8:0], tag[7:0], error
```

Requests and results obey held ready/valid semantics.  Response tags must
exactly echo request tags.  An error response, mismatched tag, unsolicited
response, invalid count, invalid index, or non-increasing list is a sticky
planner fault.

`sparse_recurrent_context_store_v1` adds `list_desc_rsp_present` around the
isolated, uniquely named context-store core derived from the immutable import.
Presence is false after reset or clear and becomes true only after that logical
context completes a successful commit.  This distinguishes a missing
first-frame list from a committed empty list.  The active core may add internal
ready/valid pipeline latency without changing this channel contract.

## 5. Safety and fault contract

The planner inputs `controller_idle`, `producer_busy`,
`context_commit_valid`, `clear_state`, and `context_error_valid` define its
ownership boundary.  A context error is always propagated into a sticky
planner fault.  The remaining safety inputs must stay in their planning-safe
values from request acceptance through result acceptance.

Fault outputs are `planner_error_valid`, `planner_error_code[7:0]`,
`planner_error_detail[31:0]`, and `reset_required`.  Fault state is reset-only:
the planner deasserts every context request, deasserts `plan_valid`, rejects
new plan requests, and never exposes a partial plan.

Legal ready/valid backpressure may last indefinitely in CP3 and is not itself a
fault.  A service-level timeout, AXI abort/drain, and cache publication belong
to CP4.

## 6. Verification and feasibility gate

The self-checking SystemVerilog testbench must cover all twelve stage mappings,
the 4/3/2 subband unions, duplicates across contexts, present-empty and missing
self lists, missing predecessors even with sparse mode disabled, disabled-
sparse/full fallback after complete descriptor inspection, held request
and result backpressure, bad tag, descriptor error, out-of-range index, and
non-increasing list faults.

The dependency-free Python reference independently derives source limits from
the imported v4 JSON and checks the complete mapping and union semantics.
Phase B records host/reference, HDL simulation, and Vivado evidence separately;
this Phase-A interface freeze makes no implementation or timing claim.

`sparse_stage_map_v1` and `sparse_union_planner_v1` contain only control
registers, counters, and 640 bitmap flip-flops.  Expected standalone inference
is zero BRAM and zero DSP.  The context adapter adds only presence/control
registers; the isolated context-store core retains the frozen payload and ABI
while allowing local timing registers, and is excluded from the planner-only
OOC resource expectation.  Its original import remains byte-identical.
