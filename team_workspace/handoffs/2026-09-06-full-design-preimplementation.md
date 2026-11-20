# Full-design pre-implementation handoff

Date: 2026-09-06

Branch: `codex/full-design-preimplementation`

## Delivered

- Added a production AXI4-Lite control/status block with shadow-to-active START
  commit, held mailbox commands, interrupt/W1C status, first-fault capture, and
  sparse-memory diagnostics.
- Added `accelerator_system_top` as the Vivado module-reference boundary around
  the existing accelerator, without changing the teammate-owned sparse-memory
  RTL or its frozen handshake ABI.
- Added a reproducible PYNQ-Z1 block design with PS7, GP0 control, four HP data
  paths, two simple-mode AXI DMAs, mailbox BRAM control, interrupt concat, and a
  single 100 MHz PL clock.
- Split reset into a persistent control plane and a synchronously stretched
  data-plane reset.  Soft reset covers accelerator, DMA, mailbox, and HP fabric.
- Switched the BD to global synthesis so PS7 FCLK0 timing constraints are
  applied through the custom module hierarchy in Vivado 2018.3.
- Added a Windows Vivado runner invoked from the WSL checkout.  It stages a
  disposable project, runs control XSim, validates the BD, performs global
  synthesis, writes reports, and enforces the no-implementation/no-bitstream
  boundary.

## Verification

- Control XSim: PASS at 1,695 ns.
- PYNQ-Z1 `validate_bd_design`: PASS.
- Full global synthesis: complete with 0 errors and 0 critical warnings.
- Post-synthesis setup WNS: -0.321 ns at 100 MHz.
- Post-synthesis hold WHS: +0.045 ns.
- Timing coverage: zero clockless or unconstrained internal endpoints and zero
  combinational/latch loops.
- CDC: all reported paths safely timed.
- Utilization: 31,016 LUT, 35,326 FF, 74 RAMB36, 7 RAMB18, and 46 DSP48; every
  category is below the 80% pre-implementation gate.
- Implementation status: Not started.  No opt/place/route, routed checkpoint,
  bitstream, or board run was produced.

## Continue from here

The next task is full-design implementation and routed timing closure.  Start
from the generated BD/synthesis scripts, run implementation with an explicit
high-effort placement/physical-optimization/routing strategy, and preserve the
evidence boundary until routed reports exist.  Detailed risks and acceptance
criteria are in
`rtl/reports/accelerator_full_bd_preimplementation/summary.md`.
