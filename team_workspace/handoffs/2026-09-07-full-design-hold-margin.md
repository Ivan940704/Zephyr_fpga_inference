# Full-design hold-margin handoff

Date: 2026-09-07

Branch: `codex/hold-margin`

Design-input baseline: `68335d78a6150efca454f3adcede9e39740be545`

## Change

The full-design implementation flow now applies
`set_clock_uncertainty -hold 0.050` to `clk_fpga_0` before `opt_design`,
placement, and routing. This turns the former thin hold pass into a 50 ps
fail-closed guardband. The final gate requires both non-negative guardbanded
WHS and a separately measured raw physical hold margin of at least 50 ps.

No functional RTL, clock frequency, false-path constraint, or multicycle
constraint changed. The Windows wrapper now also requires
`hold_guardband_met=1`.

## Fresh Vivado 2018.3 result

- Control XSim: PASS.
- PYNQ-Z1 block-design validation: PASS.
- Global synthesis: WNS `-0.321 ns`, WHS `+0.045 ns`, 31,016 LUT, 35,326 FF,
  74 RAMB36, 7 RAMB18, and 46 DSP.
- Final setup: WNS `+0.160 ns`, TNS `0`, 0 failing endpoints.
- Final hold under 50 ps user uncertainty: WHS `+0.007 ns`, THS `0`, 0 failing
  endpoints.
- Raw physical hold margin after temporarily removing only the deliberate
  guardband for measurement: `+0.057 ns`.
- Improvement over the previous raw WHS `+0.014 ns`: 43 ps.
- Routing: 55,958/55,958 routable nets complete, 0 routing errors.
- Resources: 29,847 LUT, 34,927 FF, 74 RAMB36, 7 RAMB18, and 46 DSP. The
  guardbanded route uses 37 more LUTs; all tracked resource classes remain
  below 80 percent.
- Timing coverage: 0 clockless registers, unconstrained internal endpoints,
  combinational loops, or latch loops. CDC reports all paths safely timed.
- DRC/methodology: 0 Error, 0 Critical Warning; 113 DRC and 5 methodology
  Warning violations remain non-blocking and unwaived.
- Runner: Vivado return code 0, metrics gate PASS, wrapper exit status 0.

The worst guarded hold path is inside the Xilinx AXI DMA S2MM datapath. Its
report explicitly shows 0.050 ns user uncertainty. The new worst setup path is
an accelerator fault-control path into a sparse-cache BRAM enable and meets
timing by 0.160 ns.

## Evidence boundary and next work

This closes the requested hold-margin issue at the full post-route evidence
level. It does not prove voltage/temperature board margin. No bitstream,
production HWH, hardware-platform export, board connection, or board test was
performed.

The next hardware priorities are:

1. Improve setup margin from `+0.160 ns` toward at least `+0.250 ns` and reduce
   sparse-memory/job-controller congestion.
2. Fault-inject software reset with outstanding DMA/HP transactions.
3. Classify or fix the remaining DRC/methodology warnings and board-preset DDR
   DQS warnings before authorizing production artifacts.
4. Then generate a matching BIT/HWH/driver package and run end-to-end board
   correctness, performance, power, and audio-quality tests.

Primary evidence:
`rtl/reports/accelerator_full_bd_implementation/summary.md`.
