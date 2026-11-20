# Production-v2 32-PE array checkpoint handoff

- Date: 2026-09-09 (Asia/Taipei)
- Owner: Codex
- Branch: `codex/latency-experiment-32pe`
- Scope: Phase 5A only
- Status: verified and stopped for review

## Delivered

- Added pure Verilog-2001
  `rtl/pe_array/production_v2/rtl/pe/pe_hybrid_mac_array_32.v`.
- Instantiated exactly 32 frozen `pe_hybrid_mac` leaves with independent
  lane clear, enable, mode, operands, gate, spike, direct value, accumulator,
  and overflow buses.
- Added a self-checking 32-lane XSim testbench and reproducible XSim/OOC Tcl
  scripts with 100 and 102 MHz constraints.
- Preserved `rtl/pe_array/baseline/v1` unchanged.

## Verification

- XSim PASS: 1,040 cycles, 27,881 accepted commands, 33,280 checked lane
  results, zero failures, latency one cycle, II=1.
- 100 MHz OOC PASS: WNS +4.118 ns, internal WHS +0.051 ns, 3,743 LUT,
  2,176 FF, 32 DSP, zero BRAM.
- 102 MHz OOC PASS: WNS +3.888 ns, internal WHS +0.051 ns, same resources.
- Both runs: 32 Hybrid MAC references, zero routing errors, clean timing
  coverage, zero DRC errors, and resources below 80 percent.

The all-path OOC WHS of -1.226 ns belongs to top-level input boundary paths
without physical partition-pin locations; it is not full-system timing proof.
No production-top, full-Zynq, BIT/HWH, board, five-audio, or 100-audio result
was produced.

## Next review gate

Approve or reject Phase 5B: image-v5 32-row weight/parameter packing and a
bit-exact integer oracle. Do not begin controller/memory integration or promote
the production-v2 array into the accepted baseline before that review.
