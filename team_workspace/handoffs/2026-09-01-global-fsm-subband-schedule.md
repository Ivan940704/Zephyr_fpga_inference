# Handoff: global FSM and three-subband scheduler

- Date: 2026-09-01 (Asia/Taipei)
- Owner: Codex
- Branch: `codex/global-fsm-subband-schedule`
- Task: `team_workspace/tasks/2026-09-01-global-fsm-subband-schedule.md`
- Status: controller checkpoint complete; top/datapath integration not started

## Changed files

- `rtl/control/fsm.v`
- `rtl/control/fsm_100mhz.xdc`
- `rtl/tb/tb_fsm.v`
- `rtl/Makefile`
- `rtl/scripts/run_all_xsim.tcl`
- `rtl/scripts/Run-XSim-Tests.cmd`
- `rtl/scripts/synth_fsm_ooc.tcl`
- `rtl/reports/fsm/*`
- `rtl/test-results/tb_fsm-*` and latest regression summary/logs
- `rtl/README.md`
- `docs/GLOBAL_FSM_AND_SUBBAND_SCHEDULE.md`
- global-FSM task, decision, handoff, and `PROJECT_STATUS.md`

Concurrent `rtl/pe_array/` Local Requant Bank work and dirty `upstream/` files
were not modified or included in this checkpoint.

## Implemented contract

The FSM sequences fullband GSU1/GSU2/projection, PL-to-PS result transfer,
atomic return of all nine preprocessed subband vectors, subband
GSU1/GSU2/projection, DeepFilter, and final output. It provides timeout, abort,
sticky typed errors, one-cycle command pulses, held ready/valid outputs, stage
IDs 0..11, and state/status debug outputs.

Shared mode uses physical subband engine/bank 0 for branches with 4/3/2
contexts. Experimental parallel mode maps three engines/banks to the branches,
loads all three banks per stage, launches all engines together, independently
advances unequal context counts, and waits at stage barriers.

## Verification commands and results

Windows Vivado 2018.3 standalone XSim regression:

```powershell
rtl\scripts\Run-XSim-Tests.cmd
```

- Result: `XSIM_SUMMARY passed=22 total=22` and
  `XSIM_ALL_TESTS_COMPLETED`.
- `tb_fsm`: PASS.
- Normal-scoreboard contract: 12 stage loads, three fullband starts, 27
  subband context/stage completions, and three triple-start events in parallel
  mode.
- Covered shared and parallel flows, unequal per-engine latency, stage and
  output backpressure, mid-frame reset, explicit abort, timeout, and injected
  memory/fullband/subband/DeepFilter errors.

FSM-only OOC synthesis:

```powershell
vivado.bat -mode batch -source rtl/scripts/synth_fsm_ooc.tcl -tclargs rtl
```

- Part/constraint: `xc7z020clg400-1`, 10.000 ns.
- Utilization: 121 LUT, 67 FF, 0 DSP, 0 RAMB36, 0 RAMB18.
- Timing: WNS +4.792 ns, TNS 0, estimated critical delay 5.208 ns.
- `check_timing`: zero no-clock registers, unconstrained internal endpoints,
  missing input/output delays, multi-clock registers, and combinational loops.

## PYNQ-Z1 assessment

The FSM itself passes Gate B with large 100 MHz margin. This result cannot be
scaled into a three-engine conclusion. Current 64-bit raw-stage estimates are
83 BRAM36 for the three GSU1 banks, 102 BRAM36 for three GSU2 banks, 25 BRAM36
for three projection banks, and 210 BRAM36 if all three complete branch stage
sets remain resident. The PYNQ-Z1 has 140 BRAM36. The three-GSU2 group therefore
leaves only 38 BRAM36 for parameters, activations, recurrent state, DMA buffers,
DeepFilter, and other logic.

The current four-lane Local Requant Bank uses 16 DSP, so three copies use 48
DSP before the rest of each PE engine. Complete PE resources, concurrent
128-bit weight ports, implementation timing, DDR/cache traffic, frame cycles,
RTF, and board measurements remain unknown. True three-way parallelism is
`UNKNOWN / HIGH RISK`; the one-engine schedule is `PASS WITH RISKS` for future
integration.

## Next action

Integrate the FSM only after the 64-to-128-bit memory service exposes the stage
load/done/error barrier and after a complete subband engine has a stable
start/done/error contract. Future `top.v` should tie parallel mode low by
default. Enable three-way mode only after instance-scaled PE/memory OOC,
implementation timing, and board latency pass; otherwise evaluate two-way
parallelism or an active-source/tile cache.
