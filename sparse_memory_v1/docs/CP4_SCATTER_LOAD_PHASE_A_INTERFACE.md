# CP4 scatter-load service Phase A interface

Status: frozen for `sequential-v4-sparse-load-v1`

This review freezes the boundary between `sparse_union_planner_v1` and
`sparse_memory_service_v1`. It does not alter the imported dense service or
the production accelerator top.

## Ownership and sequencing

The planner owns active-list reads and publishes exactly one immutable plan.
The service owns the single 256 KiB cache, the copied/renamed raw DMA, stage
residency, weight/parameter reads, LUT configuration, and traffic diagnostics.

Only one plan or resident stage may exist. The service accepts a plan when it
is empty, then holds `plan_ready=0` until the matching stage is released or a
fault is reset. Planning, loading, and compute never overlap in v1.

## Planner-to-service channel

All fields are sampled only on `plan_valid && plan_ready`.

| Signal | Width | Meaning |
|---|---:|---|
| `plan_valid` / `plan_ready` | 1 / 1 | One held valid/ready transaction |
| `plan_stage_id` | 4 | Stage 0 through 11 |
| `plan_sparse_enable` | 1 | Value sampled with the external stage request |
| `plan_fallback_full` | 1 | Planner selected a full-stage dense transfer |
| `plan_matrix_count` | 2 | One for projection, two for GSU |
| `plan_bitmap0` | 320 | Canonical source-index residency request for matrix 0 |
| `plan_bitmap1` | 320 | Canonical source-index residency request for matrix 1 |
| `plan_count0` | 9 | Population count of `plan_bitmap0` |
| `plan_count1` | 9 | Population count of `plan_bitmap1` |

The service independently validates the stage table, matrix count, population
counts, all bits above each matrix's source count, and requires bitmap/count
zero for the mandatory dense matrix 0 of stages 0, 3, 6, and 9 and for an
absent matrix. The service derives mandatory residency from geometry; it does
not reinterpret a nonzero mandatory bitmap. A disagreement is fatal. A
deasserted `plan_sparse_enable`, an asserted `plan_fallback_full`, or full
coverage of every sparse-eligible matrix selects one full-stage transfer.

## Canonical scatter commands

The cache keeps the dense v4 local address map. It is neither compacted nor
accompanied by a source directory. For each maximal half-open source run
`[first,last)` in a selected matrix:

```text
stride_bytes = row_tiles * 16
src_addr      = parameter_base_addr + stage_dram_offset
                + matrix_local_byte_offset + first * stride_bytes
dst_word      = (matrix_local_byte_offset + first * stride_bytes) / 8
byte_count    = (last - first) * stride_bytes
```

After all matrix runs, the service transfers the complete parameter region:

```text
src_addr   = parameter_base_addr + stage_dram_offset
             + parameter_local_byte_offset
dst_word   = parameter_local_byte_offset / 8
byte_count = parameter_tiles * parameter_record_words * 8
```

Parameters are never sparse. Stage-0/3/6/9 matrix 0 is always complete. A
dense fallback instead issues one command from the stage DRAM address to
cache word zero for `stage_transfer_bytes`.

Each command must pass 33-bit start/end arithmetic before it is presented to
the DMA. Source start/end must remain in the 32-bit AXI address space and in
the pinned v4 image; destination start/end must remain within 262,144 cache
bytes. Source, destination, and byte count must be 8-byte aligned and count
must be nonzero. The copied DMA remains responsible for at most 16 beats per
burst, 4 KiB splitting, RID/RRESP/RLAST checking, timeout, and accepted-burst
drain on abort.

## Residency publication and compute ABI

Plan bitmaps are tentative while any command is pending. `stage_load_done`
pulses, `stage_ready_for_compute` asserts, and the active residency bitmaps
become visible in the same successful completion transition only after every
matrix run and the complete parameter region have finished. Partial cache
writes are deliberately left unobservable after a failed load.

Weight and parameter addressing remains the imported job-controller ABI.
Every weight request is range checked and its source bit is checked against
the active residency bitmap before a cache read. An unresident request is a
sticky fatal error; stale bytes in a hole are never returned as valid data.
Parameter requests are legal only after atomic publication. Response payload,
tag, error, valid, and data remain stable while response ready is low.

Stage release must match the resident stage and occur with the response
adapter idle. Release invalidates both residency bitmaps before a later plan
can be accepted.

## Error, abort, and reset

Invalid stage/image/base, malformed plan, address overflow, DMA protocol
error, timeout, abort, release mismatch, illegal weight/parameter request, or
unresident source enters a sticky fatal state. No further plan, compute
request, residency publication, or successful stage completion is permitted.
`clear_error` is a compatibility input and cannot recover the service; only
`rst_n=0` clears the fault and LUT epoch identity. If an AXI burst was already
accepted, the raw DMA drains it with cache writes disabled.

## Diagnostics

The service exposes per accepted stage plan:

- planned and accepted stage bytes, excluding the image-global LUT;
- dense-reference bytes and saved bytes (saturating at zero);
- accepted union counts for matrix 0 and matrix 1;
- raw copy-command handshakes, AXI AR handshakes, and load cycles;
- separately accumulated accepted LUT bytes for the reset epoch.

DDR movement is `m_axi_rvalid && m_axi_rready` handshakes multiplied by eight.
Cache requests or planned bytes are not evidence of accepted DDR traffic.

## Explicit v1 exclusions

There is no compact cache, source directory, ping-pong cache, parameter-cache
reduction, multiple outstanding AXI command, load/compute overlap, or
planner/producer overlap. Promotion into the production accelerator top is
outside CP4 and requires separate authorization.
