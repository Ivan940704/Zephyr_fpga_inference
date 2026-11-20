# Sequential v4 production FSM handoff

Date: 2026-09-05

Branch: `codex/fsm-v4-production`

## Delivered

- Froze the PE array and Sequential v4 memory boundary as
  `sequential-v4-pe-memory-v1`; the authoritative 25-file list is
  `docs/frozen/PE_MEMORY_V4_SHA256SUMS` and deliberately excludes `fsm.v`.
- Retained the verified 13-state, 12-stage shared-engine schedule in
  `rtl/control/fsm.v`.
- Aligned global fault recovery with the frozen subsystem: ERROR is reset-only
  and the legacy `clear_error` port cannot return the controller to IDLE.
- Added one-shot start arming so one held-high PS request cannot execute two
  frames; start must be observed low before it can be accepted again.
- Made a pre-existing `pe_fault` enter ERR_PE even from IDLE and pulse abort.
- Replaced the architecture description and documented the exact differences
  from the previous checkpoint in `docs/GLOBAL_FSM_AND_SUBBAND_SCHEDULE.md`.

## Current verification

- Current compile allowlist: 26/26 SHA-256 entries OK.
- Frozen PE/memory boundary: 25/25 SHA-256 entries OK.
- Frozen PE archive: 158/158 SHA-256 entries OK.
- Vivado 2018.3 `tb_fsm`: PASS at 10,036 ns.
- Real v4 image plus frozen PE/memory connected FSM harness: PASS with
  2,385,005 checks, 24 stages, 6 FB jobs, 54 SB jobs, and 101,446 sparse
  requests across two frames.
- Frozen subsystem-only harness: 2,551,777 checks PASS in the same staged run.
- FSM-only synthesis, `xc7z020clg400-1`, 10 ns: WNS +4.135 ns, 163 LUT,
  80 FF, 0 DSP, and 0 BRAM.
- Vivado Hardware Manager: one Digilent JTAG target; `arm_dap_0` and
  `xc7z020_1`, with FPGA `PART=xc7z020`.

The repository-wide XSim wrapper did not run because its existing Windows
PowerShell preflight could not resolve `Get-FileHash`. Targeted Vivado commands
were used for the current FSM and connected harness. The wrapper is an
unrelated pre-existing working-tree change and was not edited here.

## Evidence boundary and next work

No PL image was programmed. The repository still lacks a production
`accelerator_top`, v4-compatible block design/bitstream, mailbox-to-FSM adapter,
feature provider, coefficient/CDF routing, DeepFilter path, final output path,
control/status registers, coordinated reset controller, AXI/DMA integration,
and CDC/top-level constraints.

The next integration task must keep `parallel_subbands=0`, verify both freeze
checksum sets before and after work, and connect the global FSM only to the
stage/job/barrier/fault interface of
`sequential_v4_pe_memory_subsystem`. It must not drive the frozen PE array's
microprotocol directly.
