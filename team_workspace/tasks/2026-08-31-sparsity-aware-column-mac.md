# Task: Verify sparsity-aware indexed-column execution

- Owner: Codex
- Status: complete
- Branch: `codex/sparsity-aware-column-mac` requested; the outer repository has
  no commits and its `.git` metadata is not writable inside the default sandbox.
- Presentation contract:
  - Pages 27 and 30 encode a binary spike vector into active column indices.
  - Only indexed weight-matrix columns may be read and accumulated.
  - A 16-lane PE array consumes one row tile from each selected column.
  - Page 29 places an index buffer between spike generation and later sparse reuse.
- Scope:
  - Add a standalone system-level sparse matrix-vector wrapper that composes the
    existing spike indexer and hybrid PE lanes.
  - Buffer active indices, traverse selected columns by row tile, and expose an
    external ready/valid weight-memory interface.
  - Compare sparse execution against a dense matrix-vector reference in a
    self-checking testbench.
- Files expected to change:
  - `rtl/sparse/sparsity_aware_matvec.v`
  - `rtl/tb/tb_sparsity_aware_matvec.v`
  - `rtl/scripts/Run-XSim-Tests.cmd`
  - `rtl/tests/reference_checks.py`
  - `rtl/README.md`
  - `team_workspace/handoffs/2026-08-31-sparsity-aware-column-mac.md`
- Out of scope:
  - Final `top.v`, global `fsm.v`, `pe_array.v`, or `memory.v` integration.
  - DMA, AXI, synthesis, implementation, bitstream, and board measurement.
  - Optimizing the encoder to the estimated 32 spike bits per cycle.
  - Changes inside the dirty `upstream/` nested repository.
- Acceptance checks:
  - [x] Zero-spike input produces zero outputs and performs zero weight reads.
  - [x] Sparse input reads only active columns and matches the dense reference.
  - [x] Dense input matches the same reference and reads every column/tile pair.
  - [x] Weight request and result backpressure preserve address/data stability.
  - [x] Read count equals `active_count * row_tiles` for every test vector.
  - [x] Python reference checks and Windows Vivado 2018.3 XSim both pass.
  - [x] Results and remaining performance limitations are recorded.
