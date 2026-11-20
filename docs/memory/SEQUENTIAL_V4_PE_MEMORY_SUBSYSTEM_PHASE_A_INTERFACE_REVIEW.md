# `sequential_v4_pe_memory_subsystem` Phase A Interface Review

Status: approved by the user-provided sequential-v4 implementation plan

Scope: the final connected wrapper for the simple sequential baseline.  It
instantiates one v4 memory service, one recurrent context store, one sequential
job controller, and the frozen PE datapath.  It adds only an inline LUT
handshake adapter and shallow integration diagnostics; it contains no second
parameter or sigmoid payload memory.

## 1. Elaborated production hierarchy

```text
sequential_v4_pe_memory_subsystem
  +-- memory_service
  |    +-- memory                         (unchanged 256 KiB stage cache)
  |    +-- model_memory_v4_table
  +-- sequential_recurrent_context_store
  +-- sequential_pe_job_controller
  +-- pe_array_datapath                   (frozen baseline/v1)
       +-- pe_sigmoid_lut_255             (resident global LUT RAM)
       +-- frozen PE arithmetic pipeline
```

Elaboration must contain none of `parameter_weight_bank`,
`matrix0_raw_accumulator_scratch`, `parameter_source_directory`,
`active_index_list_store`, membership/binding/prefetch logic, or another LUT
RAM.  Those source files remain in the repository but are not compile inputs.

## 2. Clock, reset, and fixed mode

The wrapper is single-clock at 100 MHz.  `rst_n` synchronously covers all four
production instances and the inline adapter.  The supported mode is exactly:

- one physical PE datapath;
- one sequential 256 KiB stage cache;
- `parallel_subbands=0` behavior;
- stage bank zero; and
- subband engine bit zero.

There is no CDC in this module.  Any external AXI/interconnect clock conversion
belongs above it and must participate in coordinated reset.

## 3. Existing global-FSM stage boundary

The wrapper preserves the current stage ABI:

```text
stage_req_valid / stage_req_ready
stage_id[3:0]
stage_bank[1:0]
stage_load_done
stage_load_error
```

A bank-zero request passes directly to `memory_service`.  An accepted nonzero
bank is not forwarded; it atomically latches an integration fatal and produces
one `stage_load_done && stage_load_error` event so the existing FSM cannot
remain in its load-wait state.

`parameter_base_addr`, fixed image version four, and the complete read-only AXI
master interface are exposed without another buffering layer.  Every stage is
loaded in full.  Active-list density is absent from this interface and cannot
change DDR bytes.

## 4. Existing global-FSM job boundary

The wrapper preserves:

```text
fb_start / fb_start_ready
fb_stage[1:0]
fb_done / fb_error

sb_start[2:0] / sb_start_ready
sb_stage[1:0]
sb_shared_branch[1:0]
sb_context_0[1:0]
sb_context_1[1:0]
sb_context_2[1:0]
sb_done[2:0] / sb_error[2:0]
```

Legal fullband work maps to generic branch zero, context zero, and stage
`fb_stage`.  Legal subband work has `sb_start == 3'b001` and maps to:

```text
stage   = 3 + sb_shared_branch*3 + sb_stage
branch  = sb_shared_branch + 1
context = sb_context_0
```

Any simultaneous FB/SB launch, subband engine bit one/two, zero subband vector
presented as a launch, or illegal stage/branch/context tuple is fatal.  An
illegal vector is accepted into the diagnostic boundary rather than held in a
ready/valid deadlock, but is not forwarded to the controller.

Only controller completion for the captured job class drives `fb_done` or
`sb_done[0]`.  `sb_done[2:1]` are always zero.  As defined by the controller
contract, a subband stage remains resident across contexts and is released
only by the branch's final context.

The global FSM's DeepFilter job is outside this wrapper.  The frozen PE's CDF
ports are tied inactive internally; this checkpoint does not assert
`df_done`, store coefficients for CDF, or claim end-to-end DeepFilter support.

## 5. Dense feature and projection coefficient edges

The controller's dense-feature request/response channel is exposed unchanged
to an external provider.  It is active only for stages 0, 3, 6, and 9 matrix
zero.  The wrapper adds no feature RAM or FIFO.

The frozen PE's signed-INT8 `coefficient_*` stream is exposed unchanged to an
external sink.  Valid, value, index, tag, and logical-last remain stable under
sink backpressure.  The wrapper does not reshape or retain coefficients and
therefore does not implement the later CDF coefficient store.

## 6. Global sigmoid LUT adapter

`memory_service` emits one table-major stream of 2,040 bytes after reset.  The
inline adapter performs:

```text
IDLE --first service LUT valid--> START
START --PE start handshake--> DATA
DATA --2,040 byte handshakes--> WAIT_DONE
WAIT_DONE --PE cfg_done && table_valid--> READY
```

The adapter holds `sigmoid_cfg_start_valid` until accepted, then directly joins
service `lut_cfg_valid/data` to PE `sigmoid_cfg_data_valid/data` and propagates
PE ready back to the service.  It stores only table/address/count metadata.

For every byte it checks service table select 0..7 and address 0..254 against
its own nested counters.  Early/late done, duplicate configuration after
READY, malformed table/address, or byte-count mismatch is fatal.  Reset is the
only way back to IDLE.  Stage release never reloads the LUT.

The actual 2,040 bytes reside only transiently in unchanged `memory.v` during
load and persist only in the frozen PE's two RAMB18E1 replicas.  The wrapper
must not infer LUT payload RAM.

## 7. Internal connection rules

The controller exclusively drives memory-service weight/parameter/release
channels and context-store open/descriptor/item/state-read/commit channels.
The PE's `state_write_*` and `active_cmd_*` connect directly to the context
store.  The controller observes drain and commit rather than copying either
stream.

The controller drives RAW/GATE owner requests, Hybrid commands, Gate RQ/bias,
Membrane, Linear, and Shared-RQ parameter responses.  Every frozen PE idle,
outstanding, overflow, and protocol signal returns to the controller.  No
latency counter substitutes for these handshakes.

All CDF inputs are constant inactive/zero.  `cdf_result_ready` may be tied high
for defensive drain, but no CDF start or tap is ever asserted.

## 8. Barrier exported to the global FSM

`pe_barrier_idle[0]` is the controller's complete PE barrier, including owner,
Hybrid, Local-RQ, Postprocess, Sigmoid, Serializer, Shared-RQ, QBN fork,
outstanding counts, and all controller input valids.  It is also low while LUT
configuration occupies the PE.  Unsupported engine bits are tied high:

```text
pe_barrier_idle = {2'b11, controller_pe_barrier_idle}
```

This signal is a drain proof, not job completion.  The global FSM may retain a
done event until the same bit is high, matching its existing lifecycle.

## 9. Fault aggregation and reset-only recovery

The wrapper captures its first local integration error and ORs it with sticky
faults from memory service, controller, context store, PE overflow, and PE
protocol error.  It exports:

```text
reset_required
pe_fault = {2'b00, reset_required}
fb_error
sb_error = {2'b00, reset_required}
integration_error_code/detail
```

`abort` is fanned into memory service and controller and becomes fatal while
work is active.  `clear_error` remains connected only for legacy ABI
compatibility and cannot restore any production instance.  Once
`reset_required` rises, no new stage/job/feature/memory request is admitted.
Recovery is one coordinated reset of this wrapper and the AXI-side state.

## 10. External status and debug

The wrapper exposes enough read-only evidence for focused integration tests:

- active memory stage and cache state;
- LUT adapter state, accepted byte count, and configuration-start count;
- controller state, current tile, total/dense/sparse weight counts;
- current PE owner and complete barrier;
- component error-valid/code/detail signals; and
- aggregate reset-required.

Debug signals are observational and do not authorize local recovery.

## 11. Phase B connected verification

The connected testbench shall compile the real production hierarchy and the
frozen baseline/v1 dependency set.  It shall use the real v4 image through an
AXI read model and cover:

- exact global LUT bytes, one start and 2,040 accepted data beats per reset;
- all twelve stage descriptors and exact full-stage AXI transfer byte counts;
- legal FB and all 4/3/2 SB logical contexts across at least two frames;
- first-frame zero recurrent state and later-frame produced-list consumption;
- zero, low, 25-percent, approximately-55-percent, and dense active patterns;
- exact cache weight source sets and the sixteen sparse-eligible roles;
- dense feature traffic only on the four GSU1 input matrices;
- real Gate INPUT-to-RECURRENT order, Membrane/QBN writeback, list swap, and
  projection coefficient output under randomized backpressure;
- cache retention through non-final SB contexts and release by the final one;
- no stage release before context commit and full PE barrier;
- AXI error, malformed bank/engine/job, PE overflow/protocol, abort, and
  coordinated-reset recovery; and
- reset causing exactly one new LUT load/configuration epoch.

An independent reference shall compare weights, parameters, state/list
evolution, and coefficients bit-exactly where the external feature vectors are
defined.  Focused connected XSim, standalone regression, OOC/routed evidence,
and board evidence must remain separately labeled.

## 12. Vivado and hierarchy gates

Vivado 2018.3 on `xc7z020clg400-1` at 100 MHz shall report:

- WNS >= 0 for the connected OOC design;
- no combinational timing loop and no unconstrained internal endpoint;
- total utilization below 80 percent of the device;
- expected order of magnitude: 68 RAMB36E1, two RAMB18E1, and 37 DSP48E1;
- exactly one instance each of memory service, unchanged memory cache,
  context store, controller, and frozen PE datapath; and
- zero instances of every excluded ping-pong/sparse-DDR module.

Resource figures are acceptance evidence only after measured reports; the
listed values are analytical expectations.

## 13. Allowed Phase B files

Phase B may add `rtl/memory/sequential_v4_pe_memory_subsystem.v` as its sole
new production module, plus its focused testbench/reference, runner,
constraint, and evidence reports.  It may not modify `memory.v`,
`memory_service`, the context store, controller, global FSM, any frozen PE
file, v4 generated artifacts, superseded ping-pong modules, or unrelated work.
