# FSM and formal PE Array integration contract

## Scope

This document defines the production boundary between the frame-level
`rtl/control/fsm.v` and the frozen formal PE integration top
`rtl/pe_array/baseline/v1/rtl/top/pe_array_datapath.v`.

The two modules are intentionally not wired directly at the per-cycle operand
level. A production PE controller sits between them:

```text
                         stage request / completion
                  +-----------------------------------+
                  |                                   v
             +---------+       job valid/ready   +----------+
PS/top ----->|  fsm.v  |------------------------>| PE       |
             | frame + |<------------------------| controller|
             | layer   |  done / fault / barrier +----+-----+
             +---------+                              |
                  ^                                   | schedule
                  |                                   v
                  |                            +---------------+
                  +----- Memory status --------| formal        |
                                               | pe_array_     |
Memory providers <---- native payload/query -->| datapath      |
Memory sinks     <---- state/index/coeff/CDF ---| baseline/v1   |
                                               +---------------+
```

The global FSM owns frame and layer order. The PE controller owns legal
RAW/GATE/MEMBRANE/CDF ownership and all detailed ready/valid scheduling.
Memory owns parameter transport/storage, operand payloads, state/index stores,
coefficient/history stores, and their backpressure.

## FSM job interface

The existing operator signals now form held ready/valid job channels:

| FSM output | Ready input | Job metadata | Use |
| --- | --- | --- | --- |
| `fb_start` | `fb_start_ready` | `fb_stage` | Fullband GSU1, GSU2, projection |
| `sb_start[2:0]` | `sb_start_ready` | `sb_stage`, branch/context outputs | Shared or experimental parallel subband jobs |
| `df_start` | `df_start_ready` | implicit DeepFilter job | CDF/DeepFilter processing |

The producer holds a start valid until ready. For a parallel subband launch,
`sb_start_ready` accepts the whole asserted vector atomically. PYNQ-Z1
production uses only engine zero and ties `parallel_subbands` low.

`fb_done`, `sb_done`, and `df_done` mark operator completion. They do not prove
that the complete formal PE subsystem is empty. The FSM latches each completion
and waits for the corresponding `pe_barrier_idle` bit before loading or
launching the next job. `pe_active_debug` and `pe_done_pending_debug` expose the
accepted/running and done-but-draining states.

`pe_fault` combines PE protocol and arithmetic faults. A fault enters global
error code 8 and pulses `pe_abort_pulse`. Abort is directed to the external PE
controller because the frozen `pe_array_datapath` has no abort port.

## Full PE barrier

For each physical PE engine, top-level glue must compute:

```text
pe_barrier_idle =
    compute_idle
 && serializer_idle
 && shared_rq_idle
 && qbn_fork_idle
 && local_rq_idle
 && postprocess_idle
 && sigmoid_idle
 && (local_rq_outstanding == 0)
 && (postprocess_outstanding == 0)
 && (shared_rq_outstanding == 0)
 && retiring_phase_input_valids_are_low
 && external_writeback_is_committed
```

The final external-writeback term is implemented by the PE controller/Memory
adapter. It prevents a stage bank, state slot, active-index list, or coefficient
buffer from being reused while its final transaction is still stalled.

## Required PE-controller sequences

### GSU job

```text
accept FSM job
-> request RAW owner and wait for grant
-> issue dense/sparse input and recurrent Hybrid commands from Memory payloads
-> stop commands, release RAW, wait owner NONE/drain
-> request GATE owner and wait for grant
-> accept gate tile context
-> issue every INPUT then matching RECURRENT Local-RQ packet
-> join matching bias; collect i_t and lambda
-> wait gate_collect_complete
-> present and hold membrane descriptor until accepted
-> release GATE through NONE; allow MEMBRANE internal owner sequence
-> wait membrane_done and accept serialized QBN/state/index outputs
-> report operator done
-> assert full barrier only after every output/writeback retires
```

### Linear projection job

```text
accept FSM job
-> request RAW owner and wait for grant
-> issue sparse Hybrid commands selected by active source index
-> present held linear_tile descriptor until accepted
-> stop commands and release RAW
-> serve per-index Shared-RQ parameter queries
-> accept all coefficient outputs and logical-last
-> report done, then full barrier
```

### DeepFilter/CDF job

```text
accept FSM job
-> ensure Linear coefficients are committed and reshaped
-> hold cdf_start_valid as the sole owner request until cdf_start_ready
-> supply ordered tap packets and causal zero padding from Memory history
-> accept the held CDF result
-> wait cdf_done, owner NONE, Hybrid drain, and result commit
-> report done, then full barrier
```

## Memory stage lifetime

The FSM requests one stage using `stage_req_valid`, `stage_id`, and
`stage_bank`. Memory holds ready low until it can accept the request and asserts
`stage_load_done` only after the complete, version-matched image section is
resident. Compute starts only after successful completion.

The loaded bank remains immutable from job acceptance through full PE barrier.
Only then may Memory release or overwrite it. With the shared-engine baseline,
the twelve stage IDs are loaded and reused sequentially. A future sparse
active-source fetch policy may reduce DDR bytes, but it must preserve the same
stage generation/tag and ready/valid contract.

## Clocking baseline

The first integration uses a single 100 MHz PL/AXI clock. If a future PE clock
is raised to 200 MHz, job commands, Memory streams, state/index/coeff writes,
faults, and barrier return signals all require explicit CDC treatment and a new
complete implementation timing sign-off.
