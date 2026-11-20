# Register the sparse-top PE barrier before the global FSM

Date: 2026-09-06

## Decision

Keep `pe_barrier_idle` combinational at the accelerator-top diagnostic port,
but sample it once into `fsm_pe_barrier_idle_q` before the global FSM consumes
it. Reset the FSM copy to non-idle so the delayed observation is conservative.

## Reason

The pre-fix routed worst path crossed from the PE job-controller state through
the barrier, global FSM launch logic, sparse job mapping, and back to controller
register clock enables. It had 16 logic levels and `-1.146 ns` slack at
100 MHz. The barrier is a completion condition, so delaying its assertion by
one cycle does not change request ownership or data ordering.

## Evidence and boundary

The focused XSim harness passed 7 checks. Fresh Vivado 2018.3 routed OOC closed
at WNS `+0.115 ns`, TNS `0.000 ns`, WHS `+0.016 ns`, and THS `0.000 ns`, with
zero routing errors and all checked resources below 80 percent. Full Zynq
block-design timing, CDC, external I/O timing, bitstream, and board behavior
remain separate checkpoints.
