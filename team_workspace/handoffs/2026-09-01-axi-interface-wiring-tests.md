# Handoff: AXI interface wiring tests

- From: Codex
- To: Fullband AXI integration, memory/DMA, and Vivado block-design tasks
- Branch / commit: requested `codex/axi-interface-wiring-tests`; no commit
  because the outer repository has no initial commit.
- Main files:
  - `rtl/axi/axis_int8_ingress.v`
  - `rtl/axi/axis_int8_egress.v`
  - `rtl/axi/axis_int8_loopback.v`
  - `rtl/axi/axis_weight_loader.v`
  - `rtl/axi/axi_lite_control.v`
  - `rtl/tb/tb_axis_int8_link.v`
  - `rtl/tb/tb_axis_weight_loader.v`
  - `rtl/tb/tb_axi_lite_control.v`
  - Updated Makefile, XSim runners, RTL README, decision, task, status, logs,
    and this handoff.

## RTL behavior verified

- The 64-bit stream ingress emits kept INT8 bytes in lane order, skips `TKEEP`
  holes, and moves `TLAST` to the final native byte.
- The stream egress repacks native bytes, produces correct partial `TKEEP`, and
  holds its complete payload stable under downstream stalls.
- End-to-end loopback passed 325 bytes in seven packets: lengths 1, 8, 13, 46,
  94, and 158 plus a non-contiguous-keep packet.  Twenty output-stall cycles
  were observed; reset flushed a held beat; zero `TKEEP` set a sticky error.
- The weight loader assembled five 128-bit words from ten 64-bit beats,
  generated sequential addresses from base address 3, honored output stalls,
  and passed ping-pong-bank readback.  Early `TLAST`, partial `TKEEP`, and
  mid-word reset paths were exercised.
- AXI4-Lite passed seven writes and nine reads with AW-first, W-first, and
  simultaneous arrivals; `WSTRB`, B/R backpressure, control pulses, sticky
  done/error, IRQ, and reset after a partial address transaction were checked.

## Verification

- Windows Vivado 2018.3 XSim: PASS, 20/20 testbenches.
- Dependency-free Python reference: PASS, 13/13.
- Final compile/elaboration/simulation logs contain no warning, error, fatal,
  or fail diagnostics.
- `rtl/test-results/xsim-console.log` and the three AXI per-test logs contain
  the final summary and metrics.
- `make test` could not compile HDL locally because `iverilog` is not installed
  in WSL.  The command stopped before HDL compilation; this is a tool
  availability limitation, not a second simulator result.

## Problems found and corrected

- Vivado 2018.3 treats `config` as a Verilog keyword; the AXI-Lite register
  output was renamed `config_word`.
- The first weight-loader TB sampled `word_count` in the same timestep as its
  nonblocking update.  Sampling after the NBA update removed the testbench
  race; the data/address/readback checks were already correct.
- The Windows runner now scans the compile log for `ERROR:` because the old
  `xvlog.bat` wrapper can return success even after a parser error.

## Not yet verified

- The adapters are not connected to `fullband_three_layer.v`, `memory.v`, a
  final `top.v`, or a Xilinx AXI DMA instance.
- No Vivado IP-integrator address map, PS HP/GP port, clock-domain crossing,
  cache-coherent buffer, interrupt driver, synthesis, timing, or board transfer
  has been tested.
- The resource-light egress intentionally has a bubble while an AXI beat is
  outstanding; throughput optimization requires a skid buffer or FIFO if
  measurement shows it is necessary.

## Recommended next checkpoint

Wrap a reduced fullband harness with the verified AXI-Lite and AXI-Stream
adapters.  Use a DMA-like testbench model to send one normalized 64-byte frame,
start the engine through AXI-Lite, stall both data directions, and compare the
64-byte projection packet before creating the Vivado block design.

