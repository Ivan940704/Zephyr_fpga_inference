# `memory_service` v4 Sequential Phase A Interface Review

Status: approved by the user-provided sequential-v4 implementation plan

Scope: interface and lifecycle contract only.  This review authorizes one
subsequent Phase B commit that directly converts `rtl/memory/memory_service.v`
to the v4-only sequential service.  `rtl/memory/memory.v` remains unchanged.

## 1. Production boundary

The existing module name, AXI master interface, stage request/release interface,
weight interface, parameter interface, diagnostics, and `lut_cfg_*` stream are
retained.  The service continues to instantiate exactly one `memory` cache and
supports exactly one held logical response.

The service replaces `model_memory_v3_table` with
`model_memory_v4_table`.  Version 3 requests are rejected with
`ERR_IMAGE_VERSION`; retained v3 generators, images, and tests are historical
artifacts rather than RTL compatibility requirements.

## 2. Added descriptor outputs

The following read-only outputs are added after the existing active-stage
identity outputs.  They are valid only while `stage_ready_for_compute` is high.

| Port | Width | Meaning |
|---|---:|---|
| `active_stage_kind` | 1 | 0 GSU, 1 projection |
| `active_matrix_count` | 2 | one or two matrices |
| `active_matrix0_sources` | 10 | legal source count |
| `active_matrix0_row_tiles` | 6 | matrix-0 output tiles |
| `active_matrix1_sources` | 10 | zero for projection |
| `active_matrix1_row_tiles` | 6 | zero for projection |
| `active_param_tiles` | 6 | legal parameter tile count |
| `active_uses_sigmoid_table` | 1 | generated v4 stage property |
| `active_sigmoid_table_select` | 3 | resident PE table selection |

The descriptors are captured atomically with the accepted stage request.  They
remain stable until successful release or reset.  Existing wrappers may leave
these added outputs unconnected.

## 3. Stage request and configuration identity

`stage_req_ready` is high only when no cached stage, no loader command, no held
native response, no fatal error, and no abort are present.  Acceptance captures
`stage_req_id`, the v4 table row, `parameter_base_addr`, and `image_version`.

A request is rejected fatally if:

- the stage ID is outside 0..11;
- image version is not `MODEL_V4_IMAGE_VERSION`;
- base address is not 64-byte aligned;
- base plus the selected image offset overflows 32 bits;
- the selected transfer is zero, not 8-byte aligned, or larger than 256 KiB;
- global LUT initialization has already completed but the base or image version
  differs from the identity captured for that reset epoch.

Only reset starts a new configuration epoch.

## 4. Global LUT sequence

The first legal stage request after reset is retained while the service:

1. commands `memory` to load 2,040 bytes at
   `parameter_base_addr + MODEL_V4_GLOBAL_SIGMOID_LUT_DRAM_OFFSET` into cache
   word zero;
2. reads all 255 cache words and presents their bytes little-endian;
3. emits exactly 2,040 accepted `lut_cfg_*` transfers;
4. uses table select `byte_ordinal / 255` and table address
   `byte_ordinal % 255`;
5. sets sticky `lut_ready` only after ordinal 2,039 handshakes;
6. reloads cache word zero with the retained requested stage;
7. publishes `stage_load_done` and `stage_ready_for_compute`.

`lut_cfg_stage_id[3]` is zero and bits `[2:0]` carry the table select.  Valid,
table, address, and data remain stable while `lut_cfg_ready` is low.  Subsequent
stage requests in the same reset epoch skip steps 1..5.  Normal stage release
does not clear `lut_ready`.

The service guarantees byte-stream completion, but the integration wrapper is
responsible for issuing the PE's one-cycle configuration start and for gating
compute on PE `table_valid`.

## 5. Cache and native accesses

Every requested stage is loaded in full at cache destination word zero using
the exact generated v4 `transfer_bytes`.  Active-source count does not affect
AXI traffic.

Weight requests are validated against the captured matrix count, sources, row
tiles, and stage cache length.  Their lower and upper 64-bit reads form one
held 128-bit response.  Parameter requests are validated against parameter tile
count and record length; all 91 GSU words or 18 projection words are read before
the held response is published.  Weight keeps deterministic arbitration
priority when both requesters assert.

`stage_release_ready` requires a ready stage and an idle native adapter.  A
matching release invalidates the cached stage but preserves the LUT epoch.  A
mismatched release is fatal and does not release the cache.

## 6. Abort and fatal semantics

The `abort` input is treated as a fatal condition, not a recoverable stage
cancel.  If an AXI burst is active, `memory` is asked to drain it; no new work is
accepted.  The service remains in fatal state after the drain.

The first fault captures `error_code`, `error_stage`, and `error_detail`, pulses
`stage_load_error` when applicable, and makes `error_valid` sticky until reset.
`clear_error` is accepted only for source compatibility and has no operational
effect: it does not clear the diagnostic record, cache fatal state, or LUT
identity.  Every response that exposed a request error may be held long enough
for its requester to observe it, but no later request is admitted.

The raw loader can signal timeout before an accepted burst drains.  The service
immediately enters fatal state and keeps the raw abort/drain indication asserted
until `raw_loader_busy` falls.  Coordinated reset is the sole recovery path.

## 7. State model and arbitration

The load lifecycle is:

```text
EMPTY
  -> LUT_COMMAND -> LUT_LOADING -> LUT_STREAM
  -> STAGE_COMMAND -> STAGE_LOADING -> READY
  -> EMPTY (matching release)

any state -> FATAL (first error or abort)
FATAL -> EMPTY only by reset
```

The cache read adapter is idle during either DMA load.  LUT streaming owns the
read port exclusively.  READY permits one weight or parameter transaction;
weight wins same-cycle contention.  No cache read is issued while a prior held
response waits for ready.

## 8. Stable status semantics

| Signal | Contract |
|---|---|
| `stage_load_done` | one-cycle pulse after requested stage DMA succeeds |
| `stage_load_error` | one-cycle pulse when a stage request/load first fails |
| `stage_ready_for_compute` | level, only READY and no fatal error |
| `lut_ready` | sticky level after all 2,040 LUT bytes handshake |
| `raw_loader_abort_drain` | fatal/abort state while raw loader remains busy |
| `cache_state` | exposes the implementation state encoding for diagnostics only |

## 9. Phase B acceptance gates

Phase B shall provide focused self-checking simulation and a Python/reference
check covering:

- exact one-time LUT bytes/table/address under arbitrary backpressure;
- LUT reinitialization after reset and no reinitialization after release;
- all twelve v4 stage byte counts, descriptor rows, weight boundaries, parameter
  records, and generated golden readback points;
- stable held responses, arbitration, illegal requests, release mismatch,
  abort, AXI response/protocol error, timeout, and fatal admission fence;
- proof that stage byte count is independent of active-source information;
- unchanged `memory.v` SHA-256.

The complete RTL regression must pass.  Vivado 2018.3 OOC on
`xc7z020clg400-1` at 100 MHz shall report exactly 64 RAMB36E1 for the cache and
WNS >= 0.  Analytical, XSim, OOC, routed, and board evidence must be reported as
distinct categories; no place-and-route or board result may be inferred from
OOC synthesis.

## 10. Allowed Phase B files

The production change is limited to `rtl/memory/memory_service.v`.  Directly
associated focused TB/reference, module-specific runner/constraint, and report
files may be added or updated in the same Phase B commit.  Historical v3 image
artifacts are not removed.  Unrelated work, the frozen PE, the pending complex
active-list implementation, and all superseded ping-pong primitives remain
untouched.
