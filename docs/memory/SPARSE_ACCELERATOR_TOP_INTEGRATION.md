# Sparse-memory accelerator-top integration

Status: RTL integration complete; 100 MHz routed-OOC timing closed

Date: 2026-09-06

Branch: `codex/sparse-top-timing`

Base commit: `71ab2d8` (`Integrate sparse memory into accelerator top`)

Target: PYNQ-Z1 `xc7z020clg400-1`, one shared PE datapath, 100 MHz

## Promoted subsystem

The production `accelerator_top` now instantiates the frozen
`sparse_memory_v1/rtl/sequential_v4_sparse_memory_subsystem.sv`. It compiles
the unique sparse DMA, v4 table, service, planner, context-store, and wrapper
sources with the repository's byte-identical production PE/controller
sources. No file inside `sparse_memory_v1/` was modified.

The promoted subsystem was already complete at CP6. Its independent evidence
includes `12,446,067` connected XSim checks for dense and sparse modes,
positive-WNS 100 MHz service and isolated-subsystem routes, 88 host tests, and
5 report-bundle checks. Those results are subsystem evidence, not
accelerator-top timing or board evidence.

## FSM compatibility decisions

- The top-level input `sparse_load_enable` is sampled by `fsm.v` only when a
  new frame is accepted. `sparse_mode_active` and
  `stage_sparse_load_enable` then remain stable for that frame, so software
  cannot change the load policy between stage request and acceptance.
- The stage request fields remain the existing lifecycle handshake:
  `stage_req_valid`, `stage_req_ready`, `stage_id`, and the only legal
  production `stage_bank=0`.
- Sparse `stage_load_done` is success-only. The FSM now observes
  `stage_load_error` independently in fullband and subband load request/wait
  states. A fatal memory failure therefore enters `ERR_MEMORY`, clears the
  pending lifecycle, and pulses PE abort without waiting for `done` or a
  timeout.
- `parallel_subbands=0` remains the production contract. The single physical
  engine continues to use only `sb_start[0]`.
- The subsystem's aggregate `pe_fault`/`reset_required` output feeds the global
  fatal path. Recovery remains a coordinated reset; `clear_error` does not
  recover the sparse subsystem.

## Accelerator-top wiring

The sparse wrapper replaces `sequential_v4_pe_memory_subsystem` without
changing the existing feature-dispatch, coefficient-store, mailbox, or
DeepFilter data paths. The top also exposes read-only sparse diagnostics for
planner error identity, context-port owner, per-stage dense/planned/actual/
saved traffic, union counts, copy commands, AR bursts, load cycles, and epoch
LUT bytes.

The subsystem's combinational `pe_barrier_idle` diagnostic remains visible at
the top port, while the copy consumed by the global FSM is sampled into
`fsm_pe_barrier_idle_q`. This conservative one-cycle timing cut breaks the
single-cycle controller-state/barrier/FSM/job-valid feedback path without
changing request fields, ready/valid ownership, data order, or the reset-only
fault contract. It may delay scheduler recognition of a drained PE by one
cycle.

The active production include roots are `rtl/` and `sparse_memory_v1/rtl/`.
The exact source order and hashes are pinned in `MANIFEST.md` and
`SHA256SUMS`; wildcard RTL discovery remains forbidden.

## Verification result

Fresh XSim and elaboration:

- `tb_fsm`: PASS, including frame-sampled sparse mode and success-only-done
  fatal error handling.
- Mailbox adapter, feature dispatcher, coefficient store, and DeepFilter
  engine regressions: PASS.
- `tb_accelerator_top_timing_cut`: PASS, 7 checks covering conservative reset,
  immediate external diagnostics, and one-cycle FSM sampling.
- Full sparse `accelerator_top` elaboration: PASS.

Fresh Vivado 2018.3 routed OOC:

| Metric | Result |
| --- | ---: |
| Target period | `10.000 ns` |
| Post-synthesis WNS | `-0.005 ns` |
| Post-route WNS / TNS | `+0.115 ns / 0.000 ns` |
| Post-route WHS / THS | `+0.016 ns / 0.000 ns` |
| Worst setup data-path delay | `9.490 ns` |
| Slice LUTs / registers | `24,461 / 28,443` |
| RAMB36 / RAMB18 / DSP48 | `71 / 4 / 46` |
| Failed / unrouted / partially routed nets | `0 / 0 / 0` |
| Resource classes below 80 percent | yes |
| Internal unconstrained endpoints / clockless regs / loops | `0 / 0 / 0` |

Conclusion: the FSM ABI, synthesizable accelerator-top assembly, and 100 MHz
routed-OOC setup/hold gates pass. Before the timing cut, the worst path crossed
16 logic levels from the shared job controller through `pe_barrier_idle`, the
global FSM, and job-valid decode back to controller register clock enables.
That path is no longer in the critical list. The new worst setup path is a
one-LUT sparse-cache BRAM-read path to `weight_rsp_data_q`; it meets timing by
`0.115 ns`.

The complete PYNQ-Z1 PS7/interconnect/AXI-DMA block design was subsequently
implemented on 2026-09-07. At 100 MHz it passes setup/hold with WNS
`+0.160 ns`, guardbanded WHS `+0.007 ns`, and raw physical hold margin
`+0.057 ns`, with 0 failing endpoints, 0 routing errors, safely-timed reported
CDC paths, and all tracked resources below 80 percent. The flow applies 50 ps
of explicit hold uncertainty before placement/routing and does not use false or
multicycle exceptions. This is full-design route evidence, not board evidence;
setup margin and local congestion still need improvement.

## Not yet verified

- Full-design setup robustness beyond the current `+0.160 ns` margin,
  especially sparse-memory/job-controller congestion. The 50 ps hold-margin
  gate is now closed.
- Reset/recovery behavior with outstanding PS7 HP and AXI DMA traffic.
- Matching BIT/HWH/software package.
- PYNQ-Z1 DDR traffic reduction, latency, RTF, power, or audio behavior.
- Board recovery after a sparse planner/service fatal error.
