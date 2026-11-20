# `sequential_recurrent_context_store` Phase A Interface Review

Status: approved by the user-provided sequential-v4 implementation plan

Scope: one simple production store for dense recurrent state and persistent
active lists.  This interface intentionally removes the token, generation,
reference-count, poison-drain, and clean-recovery machinery of the superseded
ping-pong path.

## 1. Logical identity map

The store accepts a five-bit `logical_id`; only 0..19 are legal.

| IDs | Meaning |
|---|---|
| 0 | FB GSU1 |
| 1 | FB GSU2 |
| 2..9 | SB0: `2 + context*2 + layer` |
| 10..15 | SB1: `10 + context*2 + layer` |
| 16..19 | SB2: `16 + context*2 + layer` |

Layer zero is GSU1 and layer one is GSU2.  The controller, not this store,
validates the matching stage/branch/context tuple before deriving the ID.

## 2. Storage geometry

Dense state is twenty logical vectors, each with twenty 128-bit row tiles.  It
is implemented as two `512 x 64-bit` true-dual-port planes.  Only addresses
0..399 are used; Phase B shall infer exactly two RAMB36E1.

Active payload is twenty persistent lists and one producer slot, each with up
to 320 nine-bit indices.  A linear slot/ordinal address is split over two
`4096 x 9-bit` true-dual-port memories; only 6,720 of 8,192 addresses are used.
Phase B shall infer exactly two additional RAMB36E1.

Reset and legal `clear_state` reset metadata and the logical-to-physical slot
mapping only.  Payload RAM is never scrubbed.  Invalid state reads return zero;
invalid list descriptors return count zero.

## 3. Producer lifecycle

One producer is opened through:

```text
producer_open_valid / producer_open_ready
producer_open_logical_id[4:0]
producer_open_row_tiles[5:0]
```

`row_tiles` must be 1..20 and defines exactly `row_tiles * 16` QBN state
indices.  Opening clears producer count/finalize metadata and a twenty-bit
old-state-read bitmap.  The currently mapped active list remains unchanged and
readable throughout production.

Only one producer may be open.  Opening an illegal ID/geometry or attempting a
second open is fatal.  Because ready is asserted only in the idle state, a
well-behaved caller holds a request until its single handshake.

## 4. Active-list consumers

The descriptor channel is:

```text
list_desc_req_valid / list_desc_req_ready
list_desc_req_logical_id[4:0]
list_desc_req_tag[7:0]

list_desc_rsp_valid / list_desc_rsp_ready
list_desc_rsp_count[8:0]
list_desc_rsp_tag[7:0]
list_desc_rsp_error
```

The item channel is:

```text
list_read_req_valid / list_read_req_ready
list_read_req_logical_id[4:0]
list_read_req_ordinal[8:0]
list_read_req_tag[7:0]

list_read_rsp_valid / list_read_rsp_ready
list_read_rsp_index[8:0]
list_read_rsp_tag[7:0]
list_read_rsp_error
```

There is one held response per channel and one active-list RAM read in flight.
An ordinal must be below the currently mapped count.  Payload and metadata stay
stable under backpressure.  A bad ID/ordinal publishes a tagged zero/error
response and simultaneously enters sticky fatal state.

The controller reads a descriptor once at job start and treats the returned
count as its sequential-job snapshot.  Since only one job exists and mapping
changes only at that job's final commit, no list token is required.

## 5. Dense-state consumer

The state tile channel is:

```text
state_read_req_valid / state_read_req_ready
state_read_req_logical_id[4:0]
state_read_req_row_tile[4:0]
state_read_req_tag[7:0]

state_read_rsp_valid / state_read_rsp_ready
state_read_rsp_data[127:0]
state_read_rsp_tag[7:0]
state_read_rsp_error
```

There is one RAM read in flight and one held response.  A legal uninitialized
logical state returns all zeroes without consulting payload validity.  A
handshaken response for the open producer's ID marks that row tile as having
completed its old-state read.

## 6. PE write sinks

The dense-state sink directly matches frozen PE `state_write_*`:

```text
state_write_valid / state_write_ready
state_write_value signed [7:0]
state_write_index[8:0]
state_write_tag[15:0]
state_write_last
```

State indices must be exactly `0, 1, ..., row_tiles*16-1`.  The first write to
each row tile is legal only after that tile's old-state response handshake.
`state_write_last` is asserted only for the final index.  One byte is written
to the appropriate 64-bit state plane.  The full logical state becomes valid
only on final commit.

The active sink directly matches frozen PE `active_cmd_*`:

```text
active_cmd_valid / active_cmd_ready
active_cmd_write
active_cmd_index[8:0]
active_cmd_tag[15:0]
active_cmd_finalize
```

Written indices must be in range and strictly increasing.  A command may be a
write, a finalization, or both.  Finalization occurs exactly once and only at
the final logical neuron index.  Every write before and including finalization
is appended to the current producer slot; at most 320 writes are legal.

Both PE sinks validate the canonical tag:

```text
{kind=2'b00, producer_logical_id[4:0], command_index[8:0]}
```

The two sinks may stall independently and may handshake in the same cycle.
Any malformed tag/index/order/last/finalize/capacity condition is fatal.

## 7. Commit

The commit channel is:

```text
commit_valid / commit_ready
commit_logical_id[4:0]
pe_barrier_idle
commit_done                 // one-cycle success pulse
```

`commit_ready` denotes that a producer is open, not that all prerequisites are
already true.  This deliberate rule makes a premature commit handshake become
a detected fatal error instead of an indefinite ready/valid deadlock.

A successful commit requires, on the accepted edge:

- matching logical ID;
- every expected dense-state scalar accepted and the exact final `last` seen;
- one legal active finalization accepted;
- no descriptor, list, or state read pending or held;
- all expected old-state row tiles read;
- `pe_barrier_idle` high;
- no prior fatal error.

Success atomically maps the producer list slot to the logical ID, moves that
ID's displaced old slot into the producer role, publishes the new list count,
marks dense state valid, closes the producer, and pulses `commit_done`.  No RAM
copy or scrub occurs.

Partial in-place state writes after a fatal error are intentionally not rolled
back; coordinated reset/`clear_state` invalidates them before reuse.

## 8. Clear and fatal behavior

`clear_state` is legal only with no open producer, pending RAM read, or held
response.  A legal pulse restores identity mapping, producer slot 20, zero
counts, and invalid state/list metadata without RAM writes.  A busy clear is
fatal.

The first fault captures `error_code[7:0]` and `error_detail[31:0]`, asserts
sticky `error_valid` and `reset_required`, and deasserts every request ready.
No local clear-error input exists.  Reset is the only recovery after a fault.

## 9. Phase B acceptance

Focused self-checking XSim and a Python/reference model shall cover:

- first-frame zero state and zero lists;
- all twenty identities and the 4/3/2 SB context mapping;
- zero, sparse, and 320-entry active lists with strictly increasing values;
- at least two commits to the same identity, proving producer-slot swap;
- old list readability while the new list is produced;
- old-state-read-before-first-write for every tile and multi-frame value checks;
- independent response, state-write, active-command, and commit stalls;
- malformed IDs, ordinals, tags, order, last/finalize, capacity, premature
  commit, busy clear, and reset behavior;
- held response stability and reset cancellation.

Vivado 2018.3 OOC on `xc7z020clg400-1` at 100 MHz shall report exactly four
RAMB36E1, zero RAMB18E1/LUTRAM/SRL/DSP48E1, and WNS >= 0.  Source, testbench,
reference, runner, constraint, and report files belong to one Phase B commit;
no other production module may be changed.
