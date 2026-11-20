# PE Array development rules

This file applies to every file and directory under `rtl/pe_array/`.

## Sources of truth

Before doing PE Array work, read:

1. `AGENTS.md` in this directory;
2. `spec/MODULE_DEVELOPMENT_PLAN.md`;
3. `baseline/v1/MANIFEST.md` and the relevant accepted artifacts;
4. the repository-root collaboration rules and PYNQ-Z1 feasibility checklist.

`spec/MODULE_DEVELOPMENT_PLAN.md` is the persistent PE Array hardware
architecture source of truth. The latest explicit user instruction takes
precedence, but no implementation may silently change an invariant in that
plan. Project-wide status pages, experimental RTL, old handoffs, combined
simulations, or files outside the formal baseline do not override the PE Array
plan or establish formal completion.

## Fixed target

- Board: PYNQ-Z1.
- FPGA part: `xc7z020clg400-1`.
- Target PL clock: 200 MHz / 5.000 ns.
- Checkpoint toolchain: Vivado 2018.3 XSim and OOC synthesis.
- Evidence must distinguish analysis, XSim/reference results, OOC synthesis,
  full implementation, and board measurements.

## Production RTL convention

- Every new formal production RTL file must use synthesizable Verilog-2001
  (IEEE 1364-2001) and the `.v` extension.
- Do not introduce SystemVerilog-only syntax into new production RTL and do not
  compile it with `read_verilog -sv` or `xvlog --sv`.
- Prefer flattened packed buses for multi-lane Verilog-2001 interfaces.
- The accepted baseline contains three historical `.sv` modules. Preserve
  those archived bytes; they do not authorize `.sv` for new production RTL.
- Migrating an accepted `.sv` module to `.v` is a new checkpoint and requires
  the complete review, verification, synthesis, and approval sequence.

## One-module checkpoint workflow

Only one formal module may be developed at a time. Use this exact sequence:

```text
trace upstream arithmetic/functional contract
-> propose and review interface and implementation plan
-> wait for explicit user approval to implement
-> implement only that module in Verilog-2001 .v
-> run self-checking XSim
-> run Python/integer-reference bit-exact verification when applicable
-> run Vivado OOC synthesis for xc7z020clg400-1 at 5.000 ns
-> report coverage, PASS/FAIL, resources, timing, latency, II, and limitations
-> stop
-> wait for explicit user checkpoint approval
-> if a future baseline change is explicitly approved, create a new checkpoint
   and baseline version; never overwrite baseline/v1
```

Do not start the next module automatically. Do not continue after reporting a
checkpoint until the user responds. Do not mark a module completed or baseline
merely because RTL, a testbench, a combined simulation, or a synthesis report
exists.

## Baseline and dependency rules

Frozen formal baseline root:

```text
/home/ivanhuang/projects/Zephyr_fpga_inference/rtl/pe_array/baseline/v1
```

`baseline/v1/` is the verified, formally accepted, and frozen PE baseline.
Its exact contents and leaf/integration-wrapper classifications are recorded
in `baseline/v1/MANIFEST.md`. It currently contains eleven frozen
arithmetic/functional leaves plus the separately classified
`rtl/top/pe_array_datapath.v` integration wrapper.

- Treat every file under `baseline/v1/` as a read-only integration
  dependency.
- Do not modify, delete, rename, format, overwrite, or regenerate any file
  under `baseline/v1/`.
- Controller/FSM and memory integration must adapt to the existing
  `baseline/v1/rtl/top/pe_array_datapath.v` interface. Do not change the PE
  baseline to make controller or memory integration more convenient.
- If an interface incompatibility is found, or a baseline change appears
  necessary:

  1. stop immediately;
  2. report the incompatibility and its cause;
  3. do not modify `baseline/v1/`;
  4. wait for explicit user approval.

- Even when a future change is explicitly approved, create a new checkpoint
  and a new baseline version. Never overwrite `baseline/v1/`.
- Other contributors and their Codex agents must, by default, use
  `baseline/v1/` only as a read-only integration dependency.
- Do not copy experimental `.sv` files or unapproved support/controller RTL
  into any formal baseline.
- Do not let a later formal module instantiate, inherit, or otherwise depend on
  an unapproved module.
- An unapproved checkpoint remains non-baseline even if all automated checks
  pass.
- Any future approved baseline version must preserve its verified artifacts
  and carry its own manifest and checksum evidence.

## Architecture guardrails

All work must follow `spec/MODULE_DEVELOPMENT_PLAN.md`, including:

- sixteen Hybrid MAC PEs;
- reuse of the same sixteen PEs for matrix/gate and membrane arithmetic;
- one four-lane Local Requant Bank reused for gate and membrane RQ;
- no dedicated membrane multiplier array, arithmetic lane, or second PE array;
- four-lane, eight-table resident sigmoid lookup;
- serializer followed by one shared requant engine;
- direct active-index generation without a full spike-vector scan.

The membrane sequencer is control and temporary state only. Any proposal that
changes these invariants must stop at architecture review and obtain explicit
user approval before RTL changes.

## Controller/FSM and Memory integration contract

The global `rtl/control/fsm.v` is a frame/layer scheduler. It must not directly
generate per-cycle Hybrid-PE operands, Local-RQ packets, gate bias payloads, or
CDF tap data. A production PE controller outside the frozen wrapper translates
the FSM job interface into the existing `pe_array_datapath` protocol; the
Memory provider supplies payloads and accepts writeback under that controller's
schedule.

- Treat `fb_start`, `sb_start`, and `df_start` as held job-valid signals. A job
  starts only on the corresponding `*_start && *_start_ready` handshake.
- The PE controller may report operator `done` before downstream serialization,
  Shared-RQ, QBN fork, or writeback is empty. The FSM must retain completion and
  may cross a layer/stage boundary only after the corresponding full
  `pe_barrier_idle` is asserted.
- Build `pe_barrier_idle` from `compute_idle`, `serializer_idle`,
  `shared_rq_idle`, `qbn_fork_idle`, `local_rq_idle`, `postprocess_idle`, and
  `sigmoid_idle`, with all three exposed outstanding counts equal to zero and
  every retiring input valid withdrawn. `compute_idle` alone is insufficient.
- Combine the wrapper's sticky `protocol_error` and `overflow_any` into the
  FSM-side `pe_fault`. On `pe_abort_pulse`, the PE controller and Memory provider
  must stop issuing new valids. Restart requires a defined drain or subsystem
  reset; clearing only the global FSM error does not clear the wrapper's sticky
  protocol error.
- PYNQ-Z1 production mode uses one shared PE Array on engine bit zero. Tie
  unused barrier bits high and unused fault bits low, and keep
  `parallel_subbands=0` until three complete PE/memory instances pass resource,
  port, timing, and board gates.

Memory integration must obey all of the following even before the final
`memory.v` implementation is selected:

- A stage request is one ready/valid transaction. Hold `stage_id` and
  `stage_bank` stable until acceptance; assert `stage_load_done` only after the
  entire version-matched stage and its required LUT/parameter metadata are
  resident and visible to PE consumers.
- Do not overwrite or release the resident stage bank until its PE job has
  completed and the full PE barrier is true. Track at least image version,
  stage ID, bank ID, valid/loading state, and a generation or frame tag.
- Keep the raw model blob immutable. Generate a versioned FPGA image offline
  with physical weight order
  `{operator,matrix,source_index,row_tile,lane}`. One row tile is sixteen signed
  INT8 lanes / 128 bits; a 64-bit cache returns it from two adjacent words.
- Preserve logical selected-source addressing
  `{operator,matrix,source_index,row_tile}`. Dense first-layer input may scan
  all sources; binary/recurrent/projection paths should consume stored active
  indices and fetch only their source rows when the chosen cache policy permits.
  A full-stage DDR preload does not reduce DDR traffic merely because PE MACs
  skip inactive sources.
- The Shared-RQ parameter response must atomically match the current
  `rq_param_query_{op_kind,index,tag}`. Equality is a protocol assertion rather
  than a ready-path filter, so Memory must never present a mismatched response
  and must hold every response field stable while stalled.
- Memory owns dense state RAM, previous-state reads, active-index storage/count,
  coefficient reshape/staging, CDF coefficient/history storage, causal zero
  padding, and all corresponding backpressure. Do not move these stores into
  `pe_array_datapath` and do not reconstruct a full spike vector.
- Gate INPUT/RECURRENT parameters, lane masks, groups, and active-lane tags must
  be issued in the exact paired order required by the wrapper. Bias is an atomic
  join with the matching RECURRENT response; Sigmoid LUT loading completes
  before a Gate owner request.
- Start at one 100 MHz PL/AXI domain. Any later 200 MHz PE domain requires
  explicit CDC FIFOs or handshakes, independent reset synchronization, and new
  full-system timing analysis. A standalone leaf/OOC result is not CDC or board
  evidence.
- Budget BRAM ports and capacity before choosing cache size. Preserve space for
  state, active indices, coefficients, spectrum history, mailbox, AXI
  infrastructure, and debug; do not restore the rejected default 512 KiB cache
  without a new PYNQ-Z1 feasibility review.
- Every request/response path must be self-checked under arbitrary
  backpressure, abort/reset, stale/wrong tags, terminal/finalize cases, sparse
  extremes, cache bounds, and AXI response errors before integration is called
  complete.

## Change hygiene

- Inspect `git status` before editing and preserve unrelated contributor work.
- Stage and commit only files belonging to the approved task scope.
- Never modify existing RTL during a contract/interface-only checkpoint.
- Do not update unrelated project status, task, decision, or handoff files
  unless explicitly requested.
- Report exactly what was changed and what verification was or was not run.
