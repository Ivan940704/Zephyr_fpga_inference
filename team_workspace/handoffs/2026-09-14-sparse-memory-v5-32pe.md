# Image-v5 32-PE sparse-memory handoff

## Result

The sparse-memory extension is implemented and physically tested on PYNQ-Z1.
It keeps the 32-PE, 100 MHz, 64-bit HP interface, 256-bit internal feed and PL
LayerNorm architecture, while adding an image-v5 stage map, active-list union
planner, sparse DDR stage loading and cache-residency enforcement. The release
image ABI is `0x00050002`.

The profiling-off 100-file run completed 100/100 PASS over 426,196 frames.
Mean START-to-output latency is `5.394255 ms`, complete iteration latency is
`5.807605 ms`, aggregate p99 is `6.289661/6.717971 ms`, and sustained
frame-loop RTF is `0.728054`. Versus frozen image-v5, mean frame latency falls
`19.09%`, mean iteration falls `17.93%`, and board-loop RTF falls `17.89%`.
All 100 enhanced WAV SHA-256 values match image-v5; clip-mean enhanced SI-SDR
remains `14.511990 dB`.

## Hardware evidence

- Full-design post-route WNS: `+0.251 ns`.
- Engineering-guardbanded WNS/WHS: `+0.001/+0.002 ns`.
- LUT/FF/DSP48: `42,773 / 45,344 / 68`.
- BRAM36/BRAM18: `76 / 7` (`79.5` BRAM36 equivalent).
- Slices: `13,013 / 13,300` (`97.84%`).
- Route/DRC gate: zero unrouted or partially routed nets, zero DRC errors or
  critical warnings.
- Vectorless post-route power: `1.609 W` total on-chip, `1.462 W` dynamic,
  `0.147 W` static, Medium confidence. Combined with measured latency this is
  `8.679 mJ/frame` for START-to-output or `9.344 mJ/frame` for a complete
  persistent iteration. It is not a physical power-rail measurement.

## Sparse profile

The separate fixed-five diagnostic used one counter snapshot every 16 frames:
1,453 samples instead of 23,137 per-frame snapshots, a `93.72%` reduction.
Measured input-dependent stage traffic was `1,053,656 B/frame`
dense-equivalent, `479,740.6 B/frame` actual and `573,915.4 B/frame` saved
(`54.47%`). Sparse load time was `1.783506 ms/frame` at 100 MHz; request
sparsity/MAC skip was `88.22%`. Do not substitute the instrumented
`5.481807/7.595231 ms` diagnostic frame/iteration values for the profiling-off
production latency.

## Evidence and continuation

- Rollback baseline:
  `outputs/checkpoints/2026-09-14-image-v5-32pe-baseline/` and tag
  `image-v5-32pe-final-20260910` (`2af280f`).
- Sparse checkpoint:
  `outputs/checkpoints/2026-09-14-sparse-v5-32pe/`.
- Final report, raw 5/100-file results, WAVs, JSONL counters and CSVs:
  `outputs/latency/2026-09-14-sparse-v5-32pe/`.
- Production image hashes: BIT
  `2e3e893791a7744ef7d54849d1bce5fe5e9939b676ef0a386e63fe11c414e147`,
  HWH
  `f51a32f4f3ec4903336a322521abccff5f5539f07efe76210124f2e6bcef6a4e`,
  parameters
  `0a898aca19599f976b3988f92ff645b1490dc3ac470003683199e80b134f458a`.
- Board directory `/home/xilinx/zephyr_sparse_v5_32pe_20260914/` remains
  separate from the original image-v5 deployment.
- Full current Python suite is `147 passed, 7 failed`; those same seven stale
  frozen-artifact/evidence tests fail on the untouched baseline. Focused
  current implementation-contract tests are `6 passed`.

The release clock should remain 100 MHz. The routed slack gives an arithmetic
ceiling near 102.57 MHz, but only `+0.001 ns` remains after the release
guardband and no 102 MHz routed closure is established.
