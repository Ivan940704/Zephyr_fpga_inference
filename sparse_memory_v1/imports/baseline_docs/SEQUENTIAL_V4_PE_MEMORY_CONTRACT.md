# Sequential v4 PE + Memory Architecture Contract

Status: normative production baseline

This contract replaces the archived
[`PARAMETER_MEMORY_PING_PONG_CONTRACT.md`](../../archive/parameter_memory_ping_pong/docs/memory/PARAMETER_MEMORY_PING_PONG_CONTRACT.md)
as the implementation authority for the current PE + parameter-memory
baseline.  The ping-pong design and its already committed primitives remain
useful research artifacts, but they are not dependencies of this baseline and
must not appear in its elaborated hierarchy.

## 1. Objective

The baseline minimizes control and recovery complexity.  Every stage is copied
in full from the v4 image in DDR into one 256 KiB cache.  Compute-side sparsity
then suppresses cache reads and PE MAC commands for inactive sources.  It does
not reduce DDR traffic.

The completion boundary is a sequential implementation of the twelve v4 GSU
and projection stages using one frozen PE array.  CDF, the PS mailbox, a full
accelerator block design, bitstream generation, and PYNQ-Z1 board execution are
outside this contract.

## 2. Frozen inputs and image identity

The implementation shall use:

| Item | Frozen value |
|---|---:|
| Image version | 4 |
| Image bytes | 1,053,056 |
| Image SHA-256 | `e4f1f5cd78007a47c8ecfc137f2f0e8117aa2af162bd7050913bf1867cf2cf34` |
| Global sigmoid offset | 64 bytes |
| Global sigmoid transfer | 2,040 bytes |
| Global sigmoid layout | 8 tables x 255 bytes, table-major |
| Global sigmoid SHA-256 | `af70843be21e720cedb6f627b02b69ef69a2519912c5bf900d9147f70b602c21` |
| Cache size | 262,144 bytes |
| Largest stage transfer | 219,360 bytes |
| Clock target | 100 MHz |
| PE arrays | 1 |
| `parallel_subbands` | 0 |

`rtl/memory/memory.v` is frozen byte-for-byte at SHA-256
`72435c38d85c7cbaaab25733c59912a52057b280e87c3b4d1b7ee52d7f5dab71`.
It remains the single AXI-to-cache storage primitive and shall not be modified.
The frozen PE implementation under `rtl/pe_array/baseline/v1/` also remains
unchanged.

The generated v4 table and map are the only production geometry authority:

- `rtl/memory/model_memory_v4_table.v`
- `rtl/memory/model_memory_v4_map.vh`
- `outputs/memory/2026-09-03/v4/memory_layout_v4.json`
- `outputs/memory/2026-09-03/v4/memory_golden_v4.json`

The v3 generator, images, tests, and board artifacts remain in the repository
as historical evidence.  The production `memory_service` is v4-only and no
longer promises v3 RTL compatibility.

## 3. Production hierarchy

```text
global fsm
    | stage/job
    v
sequential_v4_pe_memory_subsystem
    +-- memory_service
    |      +-- memory.v (unchanged single 256 KiB cache + AXI reader)
    +-- sequential_recurrent_context_store
    |      +-- dense recurrent-state RAM
    |      +-- persistent active-list RAM
    +-- sequential_pe_job_controller
    +-- pe_array_datapath (frozen)
           +-- internal global sigmoid LUT RAM

external dense-feature provider --> controller
projection coefficient sink      <-- PE
```

The following modules shall not be instantiated by this hierarchy:

- `parameter_weight_bank`
- `matrix0_raw_accumulator_scratch`
- `parameter_source_directory`
- `active_index_list_store`
- any membership, binding, ping-pong ownership, early-retire, or sparse-DDR
  prefetch module

They shall not be deleted merely to prove exclusion.  Elaboration evidence,
not source deletion, proves the production dependency boundary.

## 4. Global ownership and recovery

Only one stage, job, memory request, and PE operation stream are active at a
time.  A cached stage cannot be released or overwritten before all of the
following are true:

1. the controller has issued all work for the job;
2. all held memory, context, feature, and coefficient responses are consumed;
3. recurrent state and active-list commit is complete for a GSU job;
4. every relevant PE pipeline reports idle and all PE outstanding counts are
   zero;
5. no valid PE output from the retiring job remains asserted.

An AXI error or timeout, malformed request, response identity mismatch,
illegal ordering, capacity error, arithmetic overflow, or PE protocol error is
a fatal baseline error.  Fatal state is sticky, suppresses all new requests,
and asserts `reset_required`.  `clear_error` may clear diagnostic presentation
only where legacy ABI requires it; it shall not restore operation.  Recovery
requires one coordinated reset covering the controller, context store, cache,
PE, and associated AXI master/interconnect state.

No module is required to implement generation-safe local recovery, poison
drain, retained-content recovery, or early lease retirement.

## 5. Sequential v4 memory service

`memory_service` keeps its module name and principal request/response ABI.  It
shall instantiate `memory.v` and `model_memory_v4_table` directly.

It may add read-only active-stage descriptor outputs for:

- stage kind and matrix count;
- matrix 0/1 source and row-tile counts;
- parameter tile count;
- `uses_sigmoid_table` and `sigmoid_table_select`.

On the first accepted stage request after reset, the service holds that request
and performs this exact sequence:

1. load 2,040 bytes from `parameter_base_addr + 64` into cache address zero;
2. stream bytes through the existing `lut_cfg_*` channel in table order 0..7
   and address order 0..254;
3. latch `lut_ready` once every byte has handshaken;
4. overwrite cache address zero by loading the requested stage in full;
5. publish the stage descriptors and `stage_load_done`.

`lut_cfg_stage_id[2:0]` is redefined as the table select for v4; bit 3 is zero.
`lut_ready` remains high across all normal stage releases and subsequent stage
loads, and clears only on reset.  A base-address or image-identity change after
global LUT initialization is fatal.  Reset causes LUT initialization to occur
again before the next stage.

Every stage load starts at cache address zero and transfers the generated
`transfer_bytes`, independent of active-source count.  Weight addressing is:

```text
matrix_word_offset
+ (source_index * matrix_row_tiles + row_tile) * 2
```

The returned weight is the lower-addressed 64-bit word concatenated as bits
63:0 and the following word as bits 127:64.  Parameter reads remain sequential
91-word GSU records (5,792 bits) or 18-word projection records (1,120 valid
bits in the low portion of the 5,792-bit response bus).  There is exactly one
logical request and one held response; no lookahead or response FIFO is added.

## 6. Recurrent contexts and active lists

`sequential_recurrent_context_store` owns twenty logical identities:

| Logical IDs | Meaning |
|---|---|
| 0 | FB GSU1 |
| 1 | FB GSU2 |
| 2..9 | SB0: `2 + context*2 + layer` |
| 10..15 | SB1: `10 + context*2 + layer` |
| 16..19 | SB2: `16 + context*2 + layer` |

Layer zero means GSU1 and layer one means GSU2.  SB context counts are 4, 3,
and 2 respectively.

The store contains:

- 20 dense recurrent vectors of 20 x 128-bit row tiles;
- 20 persistent active-list identities plus one producer slot;
- at most 320 strictly increasing 9-bit indices per active list.

Target storage is two RAMB36E1 for dense state and two RAMB36E1 for active
lists.  Reset or `clear_state` clears validity, count, and mapping metadata but
does not scrub payload RAM.  An invalid recurrent tile reads as zero and an
invalid list reads as count zero.

One GSU job opens the producer slot.  The old list remains readable for the
whole recurrent computation while PE active-index output is appended to the
producer slot.  New state values update the target logical state in place, but
each row tile must complete its old-state read before its first new-state
write.  After the final state write, a valid active finalize, all context reads
drain, and the full PE barrier, commit atomically swaps the logical list mapping
with the producer slot.  The displaced old-list slot becomes the next producer.

There are no externally visible list tokens, generations, reference counts, or
poison lifecycle.  Wrong order, duplicate/non-increasing index, overflow,
incorrect `last`/finalize, or unsafe commit is fatal.

## 7. Compute-side sparsity and scheduling

Compute-side sparsity means that inactive sources cause neither a cache weight
request nor a PE MAC command.  It never shortens the preceding DDR stage load.

The four first-GSU input matrices (stage 0, 3, 6, and 9 matrix 0) are dense.
The following sixteen matrix roles are sparse-eligible:

- eight GSU recurrent matrix-1 roles;
- four GSU2 input matrix-0 roles;
- four projection matrices.

For a sparse role, the controller snapshots the applicable active-list count at
job start and replays list ordinals from zero for every output row tile.  A zero
count emits no weight or MAC request and leaves the cleared accumulator at zero.
For count `K` and `R` row tiles, the role emits exactly `K * R` weight requests.

The controller processes one row tile completely before the next.  A GSU tile
uses this mandatory order:

1. latch its 5,792-bit parameter record and old state tile;
2. select RAW ownership and clear sixteen accumulators;
3. execute matrix 0, then fully drain the hybrid path;
4. save exactly one 512-bit matrix-0 accumulator snapshot;
5. clear and execute sparse recurrent matrix 1, then fully drain;
6. preserve the live matrix-1 accumulator;
7. switch through no-owner to GATE ownership;
8. for forget then cell gate, and group 0..3, issue adjacent INPUT then
   RECURRENT Local-RQ commands;
9. run the gate collector and membrane operation using the old state;
10. accept QBN state and active-index outputs into the context store;
11. drain every tile-related output before advancing.

The numerical expression is fixed as:

```text
gate = RQ_input(matrix0_accumulator)
     + RQ_recurrent(matrix1_accumulator)
     + bias
```

The two RQ operations use their distinct multiplier and shift fields.  Applying
one RQ to a pre-summed accumulator is forbidden.  In particular, FB GSU2 uses
only the current tile's 16 x INT32 snapshot; no 320-entry matrix-0 scratch is
present.

A projection job snapshots the preceding GSU2 list, latches one 1,120-bit
parameter record per row tile, performs sparse RAW accumulation, executes the
linear tile/RQ protocol, and forwards coefficients to an external sink.  It
does not update a recurrent context or active list.

The 16-bit PE transaction tag is:

```text
{kind[1:0], logical_context_id[4:0], neuron_index[8:0]}
```

Kind zero denotes GSU and kind one denotes projection.  Memory service tags are
8-bit transaction identifiers and may be reused only after the sole response
has handshaken.

## 8. Integration boundary

`sequential_v4_pe_memory_subsystem` instantiates exactly one production
instance of the memory service, context store, controller, and frozen
`pe_array_datapath`.  A small handshake adapter converts the global LUT stream
to the PE's one-start/2,040-byte configuration protocol; it contains no LUT
payload RAM.

The subsystem connects to the existing global FSM stage/job handshake.  Only
`stage_bank == 0` and subband engine bit zero are supported.  A nonzero bank or
unsupported engine selection is fatal.  Dense feature request/response and
projection coefficient output remain external interfaces.  CDF outputs are
tied inactive and this baseline makes no DeepFilter completion claim.

The subsystem shall aggregate every component fault into one sticky
`reset_required`.  After that assertion, no new outward valid request may be
created until coordinated reset.

## 9. Verification gates

Each implementation checkpoint has one production module, one commit, and
independent test/reference/evidence.  Interface-only Phase A commits contain no
RTL.  Approved implementation gates are:

1. `memory_service`: v4 byte/golden checks for all stages, one-time 2,040-byte
   LUT stream, arbitrary backpressure and AXI faults, 64 RAMB36E1, 100 MHz
   WNS >= 0, and unchanged `memory.v` SHA.
2. `sequential_recurrent_context_store`: first-frame zero state, sparse/dense
   lists across all identities and multiple frames, old-read-before-write,
   stalls/faults, exactly four RAMB36E1, zero DSP, and WNS >= 0.
3. `sequential_pe_job_controller`: all true geometries and parameters against a
   bit-exact reference, zero/low/25%/approximately-55%/dense patterns, exact
   sparse request sets, strict two-RQ ordering, stalls/faults, no BRAM/DSP, and
   WNS >= 0.
4. Integration: the real v4 image, all twelve stages, FB and all SB contexts,
   at least two frames, produced lists consumed by later work, exact cache-read
   source sets, full DDR stage byte counts, one LUT load per reset epoch,
   barrier-safe release, and reset-only fault recovery.

Final implementation evidence must distinguish focused simulation, standalone
regression, OOC or routed Vivado measurements, and board measurements.  The
integration target is 100 MHz, WNS >= 0, no timing loop or unconstrained
internal endpoint, and total XC7Z020 utilization below 80%.  Approximately 68
RAMB36E1, two RAMB18E1, and 37 DSP48E1 are estimates, not acceptance evidence.

## 10. Checkpoint order

The implementation order is normative:

1. this architecture contract;
2. `memory_service` Phase A and Phase B;
3. `sequential_recurrent_context_store` Phase A and Phase B;
4. `sequential_pe_job_controller` Phase A and Phase B;
5. `sequential_v4_pe_memory_subsystem` Phase A and Phase B.

No checkpoint may silently reintroduce ping-pong placement, early retirement,
sparse DDR transfer, or the superseded membership/binding stack.  A discovered
interface contradiction must be resolved in the applicable Phase A contract
before its production RTL is committed.
