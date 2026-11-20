# Handoff: sparsity-aware indexed-column execution proof

- From: Codex
- To: Zephyr FPGA integration task
- Branch / commit: requested `codex/sparsity-aware-column-mac`; no commit because
  the outer repository still has no initial commit and `.git` is sandbox-protected.
- Changed files:
  - `rtl/sparse/sparsity_aware_matvec.v`
  - `rtl/tb/tb_sparsity_aware_matvec.v`
  - `rtl/scripts/Run-XSim-Tests.cmd`
  - `rtl/scripts/run_all_xsim.tcl`
  - `rtl/tests/reference_checks.py`
  - `rtl/README.md`
  - Sparse task, decision, and this handoff record under `team_workspace/`.
- Verification run:
  - `python3 rtl/tests/reference_checks.py`
  - Windows Vivado 2018.3 `xvlog`, `xelab`, and `xsim` through
    `rtl/scripts/Run-XSim-Tests.cmd`.
- Verified result:
  - Python reference checks: PASS, 8/8.
  - Full XSim regression: PASS, 12/12.
  - Sparse system vectors:
    - 0/8 active columns: 0 reads versus 16 dense reads.
    - 2/8 active columns: 4 reads versus 16 dense reads.
    - 4/8 active columns: 8 reads versus 16 dense reads.
    - 8/8 active columns: 16 reads versus 16 dense reads.
  - Every sparse output row matched the dense matrix-vector reference.
  - Request addresses stayed stable under memory backpressure; result tile/data
    stayed stable under output backpressure.
  - Final XSim logs contain no warning, error, or fail diagnostics.
- Not verified / limitations:
  - Behavioral simulation only; no synthesis, timing, utilization, bitstream, or
    PYNQ-Z1 board measurement was run.
  - The proof uses an 8x8 matrix and four PE lanes. Parameters model the intended
    320x320 matrix and 16 lanes, but that configuration has not been synthesized.
  - The existing encoder is serial. It proves column selection but does not yet
    prove the report's 32-spike-bits-per-cycle performance assumption.
  - Weight storage is represented by an external ready/valid interface; physical
    BRAM banking, DDR tiling, and DMA overlap are intentionally not fixed here.
- Next action:
  - Synthesize the sparse controller at 320 columns and 16 lanes, then compare a
    serial, 16-bit, and 32-bit encoder before integrating `pe_array.v`/`memory.v`.
