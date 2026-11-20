# Handoff: standalone RTL leaf-module verification

- Owner: Codex
- Status: complete
- Scope completed:
  - Added 11 standalone Verilog leaf modules under `rtl/leaf/`.
  - Added one self-checking testbench per leaf module under `rtl/tb/`.
  - Added dependency-free arithmetic/reference checks and testbench coverage checks.
  - Added Icarus and Vivado/XSim runners. The Windows runner stages sources in
    `%TEMP%` and directly invokes `xvlog`, `xelab`, and `xsim`.
  - Did not create or integrate `top.v`, `fsm.v`, `pe_array.v`, or `memory.v`.
- LayerNorm boundary:
  - LayerNorm remains on the PC/PS side.
  - RTL consumes already-normalized INT8 features.
- Verification performed:
  - `python3 rtl/tests/reference_checks.py`
    - Result: PASS, 7/7 tests.
  - `rtl/scripts/Run-XSim-Tests.cmd` through approved WSL-to-Windows interop
    - Toolchain: Vivado/XSim 2018.3 (64-bit), PYNQ-Z1 device family target remains
      `xc7z020clg400-1` for the optional Vivado project runner.
    - Result: PASS, 11/11 self-checking testbenches.
    - Compilation: `xvlog` PASS.
    - Elaboration: all 11 `xelab` runs PASS with no warnings in the final logs.
    - Simulation: all 11 `xsim` runs contain their expected `PASS tb_*` marker.
    - Final summary: `rtl/test-results/xsim-console.log`.
    - Per-test compile/elaboration/simulation logs: `rtl/test-results/*.log`.
  - Structural token check over all 22 Verilog files.
    - Result: PASS for balanced module/endmodule, begin/end, case/endcase,
      task/endtask, parentheses, brackets, and braces.
  - `make -C rtl test`
    - Python reference phase: PASS.
    - HDL compile phase: NOT RUN; stopped with `iverilog: No such file or directory`.
  - Initial WSL interop attempt was blocked by the sandbox. After the user changed
    the task to interactive approvals, the exact Windows commands were approved
    and the regression completed successfully.
- Limitations:
  - No synthesis, timing, utilization, implementation, or board measurements were run.
  - The tests are leaf-module behavioral simulations; no `top.v`, FSM, PE-array,
    memory wrapper, AXI/DMA path, or PC/PS data transfer has been integrated.
  - Icarus/Verilator portability is not verified because neither simulator is installed.
  - The outer `.git` metadata is read-only in this session, so the requested task
    branch could not actually be created; the working tree remains on `master`.
  - Existing changes inside `upstream/` were not modified.
