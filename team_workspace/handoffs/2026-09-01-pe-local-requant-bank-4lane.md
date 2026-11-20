# Handoff: `pe_local_requant_bank_4lane`

- Date: 2026-09-01 (Asia/Taipei)
- Owner: Ivan Huang (PE Array), with Codex assistance
- Branch: `codex/pe-local-requant-bank-4lane`
- Task: `team_workspace/tasks/2026-09-01-pe-array-independent-development.md`
- Status: module checkpoint complete; no next module started

## Changed files

- `rtl/pe_array/rtl/arithmetic/pe_local_requant_bank_4lane.sv`
- `rtl/pe_array/reference/pe_local_requant_bank_4lane_reference.py`
- `rtl/pe_array/tb/vectors/pe_local_requant_bank_4lane_vectors.txt`
- `rtl/pe_array/tb/unit/tb_pe_local_requant_bank_4lane.sv`
- `rtl/pe_array/scripts/sim/run_pe_local_requant_bank_4lane_xsim.tcl`
- `rtl/pe_array/scripts/synth/synth_pe_local_requant_bank_4lane_ooc.tcl`
- `rtl/pe_array/constraints/pe_local_requant_bank_4lane_200mhz.xdc`
- `rtl/pe_array/reports/pe_local_requant_bank_4lane/*`
- PE Array task/spec, Local RQ decision, and `PROJECT_STATUS.md`

No existing RTL under `rtl/leaf/`, `rtl/sparse/`, `rtl/gsu/`, or
`upstream/` was modified. Concurrent global-FSM files visible in the worktree
are unrelated and were left untouched.

## Interface and implementation

The bank exposes one common ready/valid transaction containing four flattened
lane slots and a four-bit lane mask. It instantiates exactly four
`pe_requant_lane` modules. Every bank transaction traverses all physical lanes;
inactive slots are forced to arithmetic zero and their mask bits travel as an
extra tag bit. Common output backpressure freezes all four rigid pipelines, so
data, tag, and mask cannot become misaligned.

The module contains no parameter RAM, bias, guard shift, saturation, QBN,
sigmoid, or membrane control.

## Verified results

- Standalone reference: 2,112 packets / 4,149 active results verified; SHA-256
  `8c3af6fd8924c620d841c6e7918a7a3917aa9ee44279759afc8318128b227f45`.
- XSim 2018.3: all packets PASS with every lane-mask pattern, mixed edge/random
  arithmetic, input bubbles, output stalls, and mask/tag/data stability checks.
- Exact latency: 9 cycles.
- Bank transaction II: 1 cycle without downstream stall.
- Maximum throughput: four active results per cycle.
- OOC synthesis: 2,167 LUT, 1,732 FF, 16 DSP48E1, zero BRAM.
- 5 ns timing: WNS +0.263 ns, TNS 0, estimated Fmax 211.104 MHz; target met.
- `check_timing`: zero unconstrained ports/endpoints and zero combinational
  loops after explicitly constraining synchronous `rst_n`.

## Limitations and next action

Evidence is XSim plus synthesized OOC timing/resource, not placed-and-routed
implementation or board measurement. Parameter-memory bandwidth and integrated
control/routing remain later risks. The four-lane bank is the first-version
baseline; an eight-lane variant is deferred until profiling.

Review and accept this checkpoint. Do not begin `pe_hybrid_mac` until
explicitly requested.
