# Task: Stress sparsity-aware execution with realistic spike patterns

- Owner: Codex
- Status: complete
- Branch: `codex/realistic-spike-regression` requested; the outer repository has
  no commits, so a task branch cannot be created yet.
- Evidence available:
  - The presentation defines a 320-bit spike vector, active-index buffering,
    selected weight columns, and a 16-PE row tile.
  - The repository contains model weights and activation ranges, but no audio
    sample, exported spike trace, or measured per-frame spike distribution.
- Scope:
  - Add a self-checking XSim testbench at the presentation-scale dimensions:
    320 columns, 320 rows, 16 lanes, and 20 row tiles.
  - Exercise sparse scattered, clustered burst, dense, silent, and temporally
    correlated multi-frame spike patterns without resetting between frames.
  - Add deterministic request backpressure, variable memory response latency,
    and result backpressure.
  - Compare every output row against an independent dense reference and verify
    every active column is read exactly once per row tile.
  - Record active counts, memory reads, dense-read reduction, and cycle counts.
- Files expected to change:
  - `rtl/tb/tb_sparsity_aware_matvec_realistic.v`
  - `rtl/tests/reference_checks.py`
  - `rtl/README.md`
  - `team_workspace/handoffs/2026-08-31-realistic-spike-regression.md`
- Out of scope:
  - Claiming that synthetic profiles are measured model traces.
  - Generating traces from the PC model without representative audio input.
  - Final `top.v`, `fsm.v`, `pe_array.v`, or `memory.v` integration.
  - Synthesis, implementation, bitstream, and PYNQ-Z1 board measurement.
  - Changes inside the dirty `upstream/` nested repository.
- Acceptance checks:
  - [x] All-zero, 95%, 90%, 80%, 70%, 50%, and 0% sparsity cases pass.
  - [x] Clustered and scattered patterns with the same active count both pass.
  - [x] A multi-frame correlated sequence passes without reset between frames.
  - [x] Each frame returns all 320 reference-matching output rows.
  - [x] Read count is exactly `active_count * 20`; inactive columns are never read.
  - [x] Request and result signals remain stable during backpressure.
  - [x] Dependency-free reference checks and Windows Vivado 2018.3 XSim pass.
  - [x] Metrics and the lack of measured spike traces are documented.
