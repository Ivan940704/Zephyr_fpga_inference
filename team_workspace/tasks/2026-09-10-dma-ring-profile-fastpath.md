# DMA ring and profiling fast-path optimization

- Date: 2026-09-10 (Asia/Taipei)
- Owner: Codex
- Branch: `codex/latency-experiment-32pe`
- Status: complete (software fast path; full PC-board E2E remains open)


## Completion (2026-09-10)

Status: complete for the software fast path and fixed-five board validation.
Full PC-to-board-to-PC E2E and hard maximum-frame deadline remain open system
gates.

Implemented host DMA packet prepacking, A/B buffer overlap, direct mapped
register access, cached configuration, successful-path fault/retirement
deferral, bulk coherent profile snapshots, sampled profile capture, deferred
native batch output conversion, and a persistent multi-file runtime.

Fixed-five persistent board result:

- 23,137 contiguous frames / 185.056 s audio, 5/5 PASS.
- sustained frame-loop RTF 0.887954.
- setup-amortized frame-loop RTF 0.960928.
- weighted mean iteration 7.086854 ms.
- worst per-file p99 iteration 7.662979 ms.
- all five enhanced WAV hashes match the frozen image-v5 baseline.
- final frame ID 23,137, zero sticky fault/control error, all DMA idle.

Profiling snapshot result:

- original per-frame bucket 5.299282 ms.
- bulk every-frame bucket 0.861875 ms.
- bulk every-16-frame amortized bucket 0.096304 ms/audio frame.
- deferred decode 25.180900 s to 2.039519 s.
- 1,453 coherent samples, 5/5 output hashes unchanged.

The native C DMA polling experiment was slower than mapped Python polling and
was not promoted. A new RTL DMA ring/auto-run image was not built because the
software path passed the steady-state and p99 gates and the current routed
image has only limited LUT/timing margin. See
`rtl/reports/accelerator_dma_profile_fastpath_20260910/REPORT.md` and
`team_workspace/handoffs/2026-09-10-dma-profile-fastpath.md`.


## Outcome

Reduce the image-v5 PYNQ board-loop and profiling overhead without changing
the model, fixed-point arithmetic, 32-PE datapath, parameter image, or audio
output. Start with reversible runtime changes, then add queued/automatic frame
execution only if the software-only result cannot meet the 8 ms hop.

## Scope

1. Add a coherent bulk-MMIO hardware-profile snapshot path and defer profile
   decoding until after the timed frame loop.
2. Prepack host-computed magnitude and spectrum into DMA-ready arrays before
   timing begins; copy/flush into the A/B CMA slots during the existing overlap.
3. Remove redundant successful-path DMA status/IRQ operations, redundant
   parameter/config writes, and avoid the output bytes round trip.
4. Prototype a native or direct-mapped register hot path only when it preserves
   the ordering/barrier contract and has a host-testable fallback.
5. If host overhead remains above the real-time budget, implement a bounded
   frame queue/auto-start interface and overlap input DMA for frame N+1, PL
   compute for frame N, and output DMA for frame N-1. Preserve a diagnostic
   compatibility mode and the existing image-v5 ABI until the replacement
   image passes connected XSim and full-Zynq timing.

## Frozen board test

- File IDs: 000, 025, 050, 075, 099.
- 23,137 frames and 185.056 seconds evaluated audio.
- Compare against fast-retirement commit `ea4b327`: board-loop RTF 1.66162,
  E2E RTF 1.76205, mean frame 6.83950 ms, p99 7.31380 ms.
- Use the same host-precomputed feature bundles, parameter image, BIT/HWH, and
  busy-poll mode unless a new timing-clean hardware image is explicitly under
  test.

## Acceptance checks

- Host unit tests cover bulk/fallback snapshot coherence, deferred decode,
  packed-input equivalence, DMA ordering, timeout/error paths, and zero-copy
  output interpretation.
- Five enhanced WAV SHA-256 values remain identical to the frozen image-v5
  baseline unless an explicitly documented arithmetic change is made.
- Every file finishes with contiguous frame IDs, matching final hardware frame
  ID, zero sticky fault/control error, and idle/error-free DMA channels.
- Profiling reports the same per-frame counter values and cycle conservation
  while recording snapshot-read/decode overhead separately.
- Full-system real-time requires board-loop and E2E RTF below 1.0 and per-file
  p99 below the 8 ms hop. Do not infer a pass from compute-only or analytical
  results.
- Any new BIT/HWH must pass connected RTL simulation, complete full-Zynq route,
  non-negative setup/hold timing, zero route errors, and blocking-DRC gates
  before programming.

## Evidence boundary

Keep software-only measurements, RTL simulation, routed implementation,
analytical projections, and physical-board measurements explicitly separate.
The current AXI streams and Zynq HP ports are 64-bit; widening beyond the HP
port is not part of this task unless measurements show payload bandwidth is the
bottleneck.
