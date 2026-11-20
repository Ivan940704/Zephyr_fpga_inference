# Sequential v4 Sparse-Load v1 Architecture Contract

Status: normative architecture contract for `sequential-v4-sparse-load-v1`

This document defines the isolated sparse DDR-to-BRAM development line under
`sparse_memory_v1/`.  It does not modify, supersede, or enter the compile graph
of the existing Sequential v4 production baseline.  In particular, the
imported dense contract remains the authority for the existing accelerator
top, while this document is the authority only for the new isolated manifest.

CP1 contains architecture decisions only.  It is not a Phase A interface
checkpoint and provides no RTL, simulation, timing, implementation, bitstream,
or board evidence.

## 1. Objective and fixed baseline

The sole optimization objective in v1 is to reduce accepted AXI DDR read bytes
when active-source lists are sparse.  Compute arithmetic, source indices,
weight order, parameter records, recurrent state, active-list production, and
the twelve-stage schedule remain bit-exact with Sequential v4.

| Item | Fixed value |
| --- | ---: |
| Baseline name | `sequential-v4-sparse-load-v1` |
| Image format / version | v4 / `4` |
| Image bytes | 1,053,056 |
| Image SHA-256 | `e4f1f5cd78007a47c8ecfc137f2f0e8117aa2af162bd7050913bf1867cf2cf34` |
| Stages | 12 |
| Dense stage bytes per frame | 1,050,544 |
| Global sigmoid load | 2,040 bytes per reset epoch |
| Parameter bytes per frame | 94,448 |
| Mandatory dense-matrix bytes per frame | 87,232 |
| Zero-active lower bound | 181,680 bytes per frame |
| Cache | one 262,144-byte cache |
| AXI data width | 64 bits |
| Target | PYNQ-Z1 `xc7z020clg400-1`, 100 MHz |
| PE arrays / subband engines | one / shared sequential engine |

The global LUT traffic is separate from per-frame stage traffic.  Thus a reset
epoch containing `F` successful frames has a dense reference of
`2,040 + F * 1,050,544` accepted DDR bytes.  No real-audio activation trace is
available at CP1, so this contract makes no workload savings claim.

## 2. Isolation and immutable dependencies

Every compile input, runner, artifact, and report for this line shall be below
`sparse_memory_v1/` and explicitly listed by the local manifest.  Symlinks,
wildcard discovery of repository RTL, direct includes from the existing
`rtl/memory/`, and compilation of repository-external sources are forbidden.

The snapshots below are immutable inputs:

- the v4 image, layout, golden data, and generated map/table;
- `memory.v` at SHA-256
  `72435c38d85c7cbaaab25733c59912a52057b280e87c3b4d1b7ee52d7f5dab71`;
- the frozen PE v1 arithmetic and datapath;
- the Sequential v4 controller, context store, and control-FSM references.

Any changed RTL is first copied into `sparse_memory_v1/rtl/` and given a unique
module name.  Imported files remain byte-identical.  The new hierarchy shall
not be added to an existing accelerator-top allowlist in this development
line.

## 3. Normative architecture

```text
stage request + sparse_load_enable
              |
              v
sequential_v4_sparse_memory_subsystem
    +-- sparse active-union planner
    |      +-- frozen-derived context store with descriptor.present
    +-- sparse_memory_service_v1
    |      +-- one hash-pinned memory.v (256 KiB cache)
    +-- frozen-derived sequential job controller
    +-- frozen PE array
```

There is exactly one physical cache.  Sparse rows are scatter-filled at their
dense-layout addresses; the cache is neither compacted nor rebased.  A stage
is loaded once and its matrix-wise union covers every context that will use
that stage.  The compute controller continues to replay each context's own
active list.  It must not compute over the union, so the optimization cannot
create extra MAC operations or change numerical results.

The context-list read port has exclusive ownership:

- the planner owns it only while planning a stage and the compute controller
  is idle;
- the compute controller owns it only while executing jobs;
- there is no concurrent arbitration, producer access, or speculative read.

## 4. Cache ownership and lifecycle

The externally observable cache lifecycle is:

```text
EMPTY -> PLANNING -> [LUT_LOAD] -> STAGE_LOADING -> READY -> EMPTY
   \          \              \            \          \
    +----------+--------------+------------+-----------> FATAL
```

The following invariants are mandatory:

1. Only one stage request, plan, load command, compute job stream, or release
   may own the cache at a time.
2. A stage request is accepted only after the previous stage was safely
   released and the controller, PE, list producer, commit path, and all held
   responses are idle.
3. `sparse_load_enable` is sampled with `stage_req_valid && stage_req_ready`.
   Later changes do not affect the accepted request.
4. Accepting a request invalidates all previously published stage and
   residency metadata before any planning or cache write occurs.
5. Cache payload RAM is not scrubbed.  Unwritten holes can contain stale data,
   but stale bytes are never resident and are never legal consumer data.
6. Stage descriptors and residency become visible atomically only after every
   planned command completes successfully.
7. `stage_load_done` denotes successful publication only.  It shall never be
   asserted for an aborted, partial, timed-out, or otherwise failed load.
8. `stage_ready_for_compute` is true only in `READY`, with matching stage and
   image identity and no sticky fault.
9. Release is accepted only for the published stage after the controller has
   drained all requests/responses, completed all required context commits, and
   observed the full PE barrier.  Release invalidates residency.
10. Planning or loading the next stage must not overlap compute on the current
    stage.

## 5. Stage geometry and canonical placement

The v4 generated layout is the only geometry authority.  The table below
records the values that the implementation and traffic oracle must reproduce.
`S x R` means `S` sources, each with a canonical `R`-byte source row.  All
offsets are stage-local byte offsets.

| Stage | Kind | Matrix 0 `S x R @ offset` | Matrix 1 `S x R @ offset` | Parameters `bytes @ offset` | Dense bytes |
| ---: | --- | --- | --- | --- | ---: |
| 0 | FB GSU1 | `64 x 320 @ 0` | `320 x 320 @ 20,480` | `14,560 @ 122,880` | 137,440 |
| 1 | FB GSU2 | `320 x 320 @ 0` | `320 x 320 @ 102,400` | `14,560 @ 204,800` | 219,360 |
| 2 | FB projection | `320 x 64 @ 0` | none | `576 @ 20,480` | 21,056 |
| 3 | SB0 GSU1 | `46 x 224 @ 0` | `224 x 224 @ 10,304` | `10,192 @ 60,480` | 70,672 |
| 4 | SB0 GSU2 | `224 x 224 @ 0` | `224 x 224 @ 50,176` | `10,192 @ 100,352` | 110,544 |
| 5 | SB0 projection | `224 x 80 @ 0` | none | `720 @ 17,920` | 18,640 |
| 6 | SB1 GSU1 | `94 x 224 @ 0` | `224 x 224 @ 21,056` | `10,192 @ 71,232` | 81,424 |
| 7 | SB1 GSU2 | `224 x 224 @ 0` | `224 x 224 @ 50,176` | `10,192 @ 100,352` | 110,544 |
| 8 | SB1 projection | `224 x 192 @ 0` | none | `1,728 @ 43,008` | 44,736 |
| 9 | SB2 GSU1 | `158 x 224 @ 0` | `224 x 224 @ 35,392` | `10,192 @ 85,568` | 95,760 |
| 10 | SB2 GSU2 | `224 x 224 @ 0` | `224 x 224 @ 50,176` | `10,192 @ 100,352` | 110,544 |
| 11 | SB2 projection | `224 x 128 @ 0` | none | `1,152 @ 28,672` | 29,824 |

Stages 0, 3, 6, and 9 matrix 0 are mandatory dense matrices.  Every byte of
every parameter record is also mandatory.  All other matrix sections are
sparse-eligible.

For an accepted stage, define:

```text
stage_src = zero_extend_33(parameter_base_addr) + stage_dram_byte_offset
row_bytes[m] = matrix_row_tiles[m] * 16
row_local(m, i) = matrix_local_byte_offset[m] + i * row_bytes[m]
```

For a selected consecutive source-index run `[first, last]`, the one logical
copy command is:

```text
src_addr  = stage_src + row_local(m, first)
cache_dst = row_local(m, first)
byte_count = (last - first + 1) * row_bytes[m]
```

The complete parameter section is one logical copy at its canonical local
offset.  A mandatory dense matrix is one logical copy of its complete matrix
section.  Sparse runs are emitted in increasing source order, matrix 0 before
matrix 1, with parameters last.  Runs are not merged across matrix or parameter
section boundaries.  Dense fallback is the sole exception and uses one
logical command for the complete stage, from `stage_src` to cache byte zero.

Each command is checked in 33-bit arithmetic before any address truncation:

- source start and exclusive end must remain within the pinned v4 image;
- cache start and exclusive end must be at most 262,144;
- the run must remain inside its generated matrix or parameter section;
- source, destination, and byte count must be 8-byte aligned;
- `first <= last < matrix_sources` and all derived additions must not carry
  beyond the implemented AXI address width.

`memory.v` may split one logical command into multiple AXI bursts.  Each burst
is INCR, at most 16 beats, and must not cross a 4 KiB source-address boundary.
There is no DDR over-fetch for an unselected row.

## 6. Logical contexts and list presence

The context store retains the twenty Sequential v4 logical identities:

| Logical IDs | Meaning |
| --- | --- |
| 0 | fullband GSU1 |
| 1 | fullband GSU2 |
| 2, 4, 6, 8 | SB0 GSU1, contexts 0..3 |
| 3, 5, 7, 9 | SB0 GSU2, contexts 0..3 |
| 10, 12, 14 | SB1 GSU1, contexts 0..2 |
| 11, 13, 15 | SB1 GSU2, contexts 0..2 |
| 16, 18 | SB2 GSU1, contexts 0..1 |
| 17, 19 | SB2 GSU2, contexts 0..1 |

The copied context-store descriptor adds `present` alongside `count`.
`present` is metadata, not inferred from payload RAM or count:

- reset and an accepted `clear_state` set every logical list's `present` to
  zero and clear its count/mapping validity without scrubbing payload RAM;
- a legal atomic commit sets `present` to one, including for a finalized empty
  list whose count is zero;
- `present=1, count=0` is a known empty list;
- `present=0` is a missing list, and its descriptor count must be reported as
  zero;
- planner descriptor and entry responses are held stable under backpressure.

A missing recurrent self-list is interpreted as empty.  This is the only
legal missing-list case and supports first-frame execution after reset or
state clear.  A missing predecessor list is a fatal scheduling error, even
when `sparse_load_enable` was sampled low.  Dense fallback must never conceal
a missing predecessor.

## 7. Stage-to-list mapping

`self` means the same recurrent layer's list from the preceding frame and may
legally be missing.  `predecessor` means a list produced and committed earlier
in the current frame and must be present.  Braces denote a matrix-wise union;
they do not change per-context compute lists.

| Stage | Matrix 0 source selection | Matrix 1 source selection |
| ---: | --- | --- |
| 0 | mandatory dense | `{0}` self |
| 1 | `{0}` predecessor | `{1}` self |
| 2 | `{1}` predecessor | none |
| 3 | mandatory dense | `{2,4,6,8}` self |
| 4 | `{2,4,6,8}` predecessor | `{3,5,7,9}` self |
| 5 | `{3,5,7,9}` predecessor | none |
| 6 | mandatory dense | `{10,12,14}` self |
| 7 | `{10,12,14}` predecessor | `{11,13,15}` self |
| 8 | `{11,13,15}` predecessor | none |
| 9 | mandatory dense | `{16,18}` self |
| 10 | `{16,18}` predecessor | `{17,19}` self |
| 11 | `{17,19}` predecessor | none |

Equivalently, for a subband group whose logical base is `B` and context count
is `C` (`(B,C) = (2,4), (10,3), (16,2)`):

- GSU1 matrix 1 unions `B + 2*c` for `0 <= c < C` as self-lists;
- GSU2 matrix 0 unions `B + 2*c` as predecessor lists;
- GSU2 matrix 1 unions `B + 2*c + 1` as self-lists;
- projection matrix 0 unions `B + 2*c + 1` as predecessor lists.

The scheduler shall not request a GSU2 or projection stage until all required
predecessor contexts for that stage have committed.  This is required because
one stage union is loaded once and reused across all of its context jobs.

## 8. Union construction and fallback

The planner owns exactly two 320-bit matrix bitmaps.  Bit `i` corresponds to
canonical source index `i`.  A bitmap for a mandatory dense matrix or absent
matrix is zero; mandatory residency is derived from stage geometry, not from
an artificial active list.

For every sparse-eligible matrix `m`:

```text
union_bitmap[m][i] = OR(list[j] contains i for every mapped context j)
union_count[m] = popcount(union_bitmap[m][0 : matrix_sources[m]])
```

All mapped descriptors are inspected for every accepted stage, regardless of
the sampled sparse-enable value.  For every present list, the planner reads
ordinals `0 .. count-1`.  The entries must be strictly increasing, no entry may
be outside the target matrix source domain, tags must match, and response
errors are fatal.  Backpressure must not advance an ordinal or modify a bitmap.
Bits at or above `matrix_sources` and all unused bitmap bits remain zero.

Planning is legal only while all of these are true:

- the stage/job controller and PE are idle;
- `producer_busy` is false;
- no producer open, active append/finalize, state write, commit, or
  `clear_state` handshake can occur;
- there is no held compute-side context response.

The wrapper shall prevent simultaneous handshakes by construction.  Detection
of a mutation or ownership contradiction after stage acceptance is fatal and
the plan is discarded.

Define a stage's union as **dense** only when every sparse-eligible matrix has
all of its valid source bits set.  For a two-eligible-matrix GSU stage, one
dense union and one sparse union is not a dense stage; the dense matrix is
copied in full and the other remains scatter-loaded.

The service selects complete-stage fallback when either condition is true:

1. the sampled `sparse_load_enable` is zero; or
2. the stage union is dense.

Otherwise it executes canonical scatter-fill.  The sparse candidate byte
count is:

```text
candidate_bytes = all_parameter_bytes
                + all_mandatory_dense_matrix_bytes
                + SUM(union_count[m] * row_bytes[m])
```

The selected `planned_bytes` is `dense_stage_bytes` in fallback mode and
`candidate_bytes` in scatter mode.  With all eligible unions empty, the twelve
stage totals are 94,448 parameter bytes plus 87,232 mandatory matrix bytes,
or 181,680 bytes per frame.  The lower bound does not include the once-per-
reset 2,040-byte LUT transfer.

## 9. Residency and compute-side access

Successful publication records the active stage identity, fallback mode,
parameter residency, mandatory dense residency, and the two selected-row
bitmaps.  This is fixed stage metadata, not a source-address directory:
addresses always use the canonical v4 formula and no row can be relocated.

For a weight request `(matrix, source, row_tile)`, acceptance requires:

1. a published matching stage and no sticky fault;
2. a valid matrix, `source < matrix_sources`, and
   `row_tile < matrix_row_tiles`;
3. complete-stage fallback, a mandatory dense matrix, or a resident selected
   source bit for that matrix.

Failure of condition 3 is a stale-cache-hole access and is fatal.  It must not
return whatever payload happens to remain at that cache address.  Legal weight
addressing and 128-bit word assembly remain unchanged:

```text
matrix_word_offset + (source * matrix_row_tiles + row_tile) * 2
```

Parameter requests are legal only after complete parameter residency and
retain the existing 91-word GSU and 18-word projection record ABI.  A load is
not publishable merely because the rows currently requested by the controller
have arrived; all planned rows, all mandatory dense data, and all parameters
must first be resident.

## 10. LUT and image-epoch behavior

The first accepted stage after coordinated reset performs the same one-time
global LUT transfer as dense Sequential v4.  Within an accepted transaction,
the normative order is:

1. validate and snapshot request, image identity, and context descriptors;
2. construct both matrix unions;
3. if the LUT is not initialized, load and stream all 2,040 bytes in table and
   address order;
4. execute the selected dense or scatter stage plan;
5. atomically publish stage descriptors and residency.

The LUT may temporarily occupy cache address zero and is overwritten by the
stage load.  It is retained in the PE's LUT RAM, not in a second parameter
cache.  `lut_ready` remains set until coordinated reset.  Any base-address or
image-version change after LUT initialization is fatal.  The base address and
image version must also remain stable throughout an accepted transaction.

## 11. Handshake, backpressure, and fault rules

All request/response and valid/ready channels obey these rules:

- a producer holds `valid` and every payload bit stable until handshake;
- state, ordinal, command, and counter advancement occurs on handshake only;
- only one context descriptor/read or cache load command is outstanding at a
  time unless a later interface checkpoint explicitly proves an equivalent
  ordered implementation;
- tags and stage identity are checked before response consumption;
- an AXI beat counts only on `RVALID && RREADY`;
- RID, RRESP, RLAST, burst length, timeout, and abort are checked independently
  for every accepted burst.

The following are fatal and fail closed: illegal stage/image/base, missing
predecessor, malformed descriptor, non-increasing/duplicate/out-of-range list
entry, response tag mismatch, context mutation during planning, 33-bit address
or cache bounds failure, command protocol failure, AXI RID/RRESP/RLAST error,
timeout, abort, partial load, bad release, unsupported stage bank/engine, and a
nonresident cache access.

Fatal state is sticky, asserts the subsystem `reset_required`, suppresses new
stage, list, load, compute, and outward-valid requests, and prevents residency
publication.  Already accepted AXI traffic is drained safely without creating
new bursts.  Written cache bytes and planner bitmaps from the failed attempt
are invalid.  `clear_error` may clear presentation fields required by an ABI,
but it cannot deassert `reset_required` or resume operation.

Recovery requires one coordinated reset of planner, context store, memory
service/cache, controller, PE, AXI master/interconnect state, LUT-ready state,
residency, and diagnostics.  Reset need not scrub cache, list, or recurrent
payload RAM because all associated validity metadata is cleared.  `clear_state`
is legal only at the defined global idle boundary; asserting it during
planning, loading, producer activity, or compute is fatal.

## 12. Traffic diagnostics

Every accepted stage attempt shall produce an atomic diagnostic snapshot with
at least:

| Diagnostic | Normative meaning |
| --- | --- |
| planned bytes | Selected dense or scatter plan bytes, excluding LUT |
| actual bytes | Accepted stage AXI R beats multiplied by 8 |
| saved bytes | `dense_stage_bytes - actual_bytes`, valid only on successful publication |
| union count 0/1 | Popcount of the two eligible-matrix union bitmaps |
| copy commands | Logical `memory.v` stage commands accepted, excluding LUT |
| AR bursts | Stage AXI AR handshakes, excluding LUT |
| load cycles | Clock cycles from accepted stage request through success or fatal failure |

The LUT has a separate accepted-R-byte count and is exactly 2,040 on a
successful initialization.  Failed attempts retain their actual accepted-byte,
command, burst, and cycle evidence but must not report saved bytes as a
successful saving.  A successful stage requires `actual_bytes == planned_bytes`.
Frame traffic is the sum of twelve successful stage snapshots; reset-epoch
traffic additionally includes the LUT count.

Subsystem or board-visible cumulative counters may supplement snapshots, but
must increment from the same handshake events.  PE/cache request counts,
planned row counts, AR requested lengths, or cache writes are not substitutes
for accepted DDR R beats.

## 13. Explicit exclusions

The following are outside `sequential-v4-sparse-load-v1` and shall not appear
in its elaborated hierarchy or performance claims:

- compacted, packed, rebased, associative, or variable-size cache placement;
- a source directory, tagged cache, membership/binding stack, or address
  remapping table;
- ping-pong stage caches, a second parameter cache, or parameter-cache BRAM
  reduction;
- compute/load overlap, next-stage prefetch, speculative list reads, early
  release, or multiple outstanding stage loads;
- parameter sparsity, parameter compression, weight compression, or changes to
  the v4 image format;
- changes to PE arithmetic, active-list semantics, recurrent-state ABI, or the
  global schedule;
- a fixed real-audio savings percentage, real-time claim, or bandwidth claim
  before matching board measurements;
- promotion into the existing accelerator top, its block design, source
  allowlist, runners, or artifacts.

The two fixed 320-bit residency/union bitmaps are not a directory: they contain
no addresses or tags and only authorize rows at immutable canonical offsets.

## 14. Verification and evidence boundary

Later checkpoints shall prove, in order, the traffic oracle, planner, scatter
service, isolated connected subsystem, Vivado evidence, board A/B behavior,
and freeze/handoff.  At minimum they cover zero, one, contiguous, disjoint,
25%, approximately 55%, dense, context-overlap, and context-disjoint lists;
stale holes; 4 KiB splitting; RID/RRESP/RLAST; timeout; abort; partial load;
reset; and response backpressure.

Dense and sparse modes use the same v4 image and inputs and are compared for
bit-exact weights, parameters, coefficients, state, active lists, and PE
results.  The primary traffic acceptance metric is accepted AXI R beats times
eight.

PYNQ-Z1 feasibility at CP1 is architectural only:

- placement is PL RTL at 100 MHz on `xc7z020clg400-1`;
- the existing one-cache organization remains 64 RAMB36E1 analytically;
- the two bitmaps contain 640 bits total and the planner is expected to use no
  BRAM or DSP, but this is an estimate until OOC synthesis;
- no additional PE instance or parameter cache is introduced;
- isolated OOC/route must later achieve WNS >= 0, zero unrouted nets, zero
  unconstrained internal endpoints, and less than 80% of each device resource;
- these isolated results cannot be cited as accelerator-top timing, bitstream,
  board bandwidth, latency, RTF, power, or audio-quality evidence.

Any contradiction discovered while defining the planner, service, or wrapper
ABI must be resolved by a new reviewed contract revision before its dependent
Phase B implementation is accepted.
