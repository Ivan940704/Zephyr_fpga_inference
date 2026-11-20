# Task: Define and verify the global FSM and three-subband schedule

- Owner: Codex
- Status: complete
- Branch: `codex/global-fsm-subband-schedule`
- Scope:
  - Implement a standalone `fsm.v` that sequences the fullband three operators,
    PL-to-PS handoff, PS subband preprocessing return, three subband branches,
    DeepFilter, final output, timeout, abort, and error handling.
  - Support a resource-safe single-engine subband schedule and an experimental
    three-engine parallel schedule through the same verified control contract.
  - Treat the three branches as 4/3/2 persistent local contexts and schedule
    GSU1, GSU2, then projection in stage-major order.
  - Quantify whether true three-branch parallel execution is defensible on
    PYNQ-Z1 with the current PE and memory evidence.
- Files expected to change:
  - `rtl/control/fsm.v`
  - `rtl/tb/tb_fsm.v`
  - `rtl/Makefile`
  - `rtl/scripts/run_all_xsim.tcl`
  - `rtl/scripts/Run-XSim-Tests.cmd`
  - `rtl/README.md`
  - `docs/GLOBAL_FSM_AND_SUBBAND_SCHEDULE.md`
  - `team_workspace/decisions/2026-09-01-global-fsm-subband-parallelism.md`
  - `team_workspace/handoffs/2026-09-01-global-fsm-subband-schedule.md`
  - `PROJECT_STATUS.md`
- Out of scope:
  - Implementing `top.v`, the complete PE array, subband arithmetic, memory
    service, v3 parameter generator, PS software, DMA IP, or DeepFilter wrapper.
  - Modifying the dirty `upstream/` nested repository or the independent
    `pe_local_requant_bank_4lane` work.
  - Claiming full-system timing, RTF, or board feasibility from an FSM-only test.

## PYNQ-Z1 feasibility

- Placement: one global PL RTL control instance; PS preprocessing remains on
  PYNQ PS CPU and fullband LayerNorm remains on the external host.
- Target part / clock: `xc7z020clg400-1`, 100 MHz control/AXI domain.
- Numeric formats and vector/tensor shapes: control-only; stage IDs 0..11;
  subband branches have 4/3/2 contexts; datapath remains INT8/INT32 externally.
- Parallel instances / lanes: one FSM. Baseline controls one time-multiplexed
  subband engine; experimental mode controls three physical branch engines.
- Estimated LUT / FF / DSP / BRAM per instance: Gate A expected below 500 LUT
  and 500 FF, 0 DSP, 0 BRAM. Gate B Vivado 2018.3 OOC measured 121 LUT, 67 FF,
  0 DSP, and 0 BRAM for the FSM itself.
- Scaled total at the intended instance count: one FSM only. Parallel mode does
  not make the three engines free; their datapath/cache totals are outside the
  FSM and remain unverified.
- Local buffer and state bytes, ports, banking: FSM stores only counters/masks.
  Current v2 parallel stage groups would require approximately 83 BRAM36 for
  three GSU1 banks, 102 BRAM36 for three GSU2 banks, or 25 BRAM36 for three
  projection banks at 64-bit width. Keeping all three complete branches resident
  is approximately 210 BRAM36 and does not fit 140 BRAM36.
- DDR bytes per frame/audio and required sustained bandwidth: if all 12 v2
  stages are reloaded once per frame, transfer payload is 1,312,640 bytes/frame,
  approximately 165.4 MB/s at 126 frames/s before AXI overhead. Subband stages
  alone are 852,032 bytes/frame, approximately 107.4 MB/s. These are analytical
  traffic figures, not measured bandwidth.
- AXI payload, packet count, DMA/cache-maintenance frequency: single stage-load
  request interface, up to 12 logical stage checks/loads per frame; memory
  service may return a cache hit without DDR traffic. PS handoff is one
  fullband-result packet followed by one buffered set of nine normalized
  subband vectors.
- Estimated cycles/frame, initiation interval, and RTF contribution: FSM adds
  only state/handshake cycles; engine, PS, DMA, and cache latency are external.
  Sequential subband latency is the sum of 4/3/2 context work, while true
  parallel latency is the maximum branch latency. Current full cycle/RTF remains
  unknown.
- Clock domains / CDC: FSM itself is 100 MHz single-domain. Any 200 MHz PE array
  must use explicit request/completion CDC outside this module; PS AXI inputs
  must already be synchronized to `clk`.
- Resource or bandwidth hot spot: true parallel mode needs three PE engines,
  three simultaneously readable weight banks or a multi-client memory service,
  and coefficient/intermediate buffers. Three complete raw branch caches exceed
  BRAM capacity; the three-GSU2 stage group alone consumes an estimated 72.9%
  of BRAM before all other logic.
- Fallback if the estimate does not fit: compile/use the single-engine schedule,
  keep three logical contexts in state RAM, and time-multiplex one PE array;
  later consider two-way parallelism or active-source tile caches after OOC and
  memory bandwidth measurements.
- Evidence level: repository facts + structural/analytical estimates for the
  memory/datapath system; self-checking XSim and FSM-only OOC synthesis for the
  implemented controller. OOC used `xc7z020clg400-1`, 10 ns, WNS +4.792 ns,
  estimated critical delay 5.208 ns, with zero unconstrained endpoints.
- Feasibility: baseline FSM/single-engine schedule `PASS WITH RISKS` pending
  integration; three-engine parallel system `UNKNOWN / HIGH RISK` and must not
  be presented as PYNQ-qualified.

## Acceptance checks

- [x] State definitions cover reset/idle, 12 stages, PS round-trip, three
  subband branches, DeepFilter, output, done, timeout, abort, and errors.
- [x] Sequential mode uses only one physical subband engine and executes all
  4/3/2 contexts in GSU1 -> GSU2 -> projection stage order.
- [x] Parallel mode starts three branch engines together, independently advances
  their 4/3/2 contexts, and waits for all branches before changing stage/output.
- [x] Stage IDs and cache-bank IDs match the current 12-stage memory layout.
- [x] Self-checking TB covers normal sequential/parallel flows, unequal branch
  latency, backpressure, reset, abort, stage error, engine error, and timeout.
- [x] Relevant simulation and, if available, `xc7z020clg400-1` FSM-only OOC
  synthesis results are recorded without extrapolating to the complete design.
- [x] Architecture, decision, status, handoff, limitations, and next work are
  documented and committed without staging unrelated PE/upstream changes.
