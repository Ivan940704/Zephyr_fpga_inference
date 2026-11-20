# Image-v5 32-PE sparse-memory experiment

- Owner: Codex
- Baseline: WSL worktree `/home/ivanhuang/projects/Zephyr_fpga_inference_latency_32pe`, commit `2af280f4c5e8b1623a22b2162427702ce3ecc3e9`, image ABI `0x00050001`.
- Scope: freeze the deployed image-v5 evidence, implement a v5-compatible sparse DDR-to-cache stage loader for the existing 32-PE/100 MHz architecture, and measure fixed-five then 100-file board performance.
- Isolation: use the `codex/sparse-memory-v5-32pe` worktree; do not modify the frozen image-v5 worktree or the isolated `sparse_memory_v1/` checkpoint.
- Fixed-five IDs: `000`, `025`, `050`, `075`, `099`.
- Files: sparse-v5 RTL/tests/reports, production integration files only after the isolated functional gate passes, and a final result bundle with checksums.
- Acceptance checks:
  - Baseline commit, BIT/HWH, parameter image and result evidence are checksum-pinned and recoverable.
  - Dense and sparse modes are bit-exact in reference/XSim tests, including reset, backpressure, missing-list policy, residency and AXI fault cases.
  - Full PYNQ-Z1 implementation at 100 MHz has non-negative WNS/WHS, zero unrouted nets and no blocking DRC errors before bitstream generation.
  - Five-file board run is 5/5 complete, output-equivalent to image-v5 within the frozen integer/audio criteria, and reports DDR bytes, load latency, total PL/board-loop latency, SI-SDR, resource and timing data.
  - The 100-file run starts only if the fixed-five functional and latency gates pass; otherwise the report records the blocking result without claiming a 100-file measurement.
  - Simulation, routed implementation, board measurement, post-route power estimate and analytical values remain separately labeled.

## Completion record

- Status: complete on isolated branch `codex/sparse-memory-v5-32pe`.
- Source commits: `2114788` (sparse stage loading), `ee9a4ae` (registered
  DeepFilter coefficient addresses), `c9e227f` (explicit non-incremental full
  implementation), and `d4400a0` (current implementation contract).
- Original image-v5 rollback checkpoint:
  `outputs/checkpoints/2026-09-14-image-v5-32pe-baseline/`; annotated tag
  `image-v5-32pe-final-20260910` points to `2af280f`.
- New image: ABI `0x00050002`; BIT SHA-256
  `2e3e893791a7744ef7d54849d1bce5fe5e9939b676ef0a386e63fe11c414e147`;
  HWH SHA-256
  `f51a32f4f3ec4903336a322521abccff5f5539f07efe76210124f2e6bcef6a4e`.
- Full route at 100 MHz: WNS `+0.251 ns`, guardbanded WNS `+0.001 ns`,
  guardbanded WHS `+0.002 ns`, zero unrouted nets and zero blocking DRC.
- Resources: LUT `42,773`, FF `45,344`, DSP48 `68`, BRAM36/18 `76/7`
  (`79.5` BRAM36 equivalent), slices `13,013`.
- Fixed-five physical-board gate: 5/5 PASS, 23,137 frames, `5.389259 ms`
  mean START-to-output, `5.789871 ms` mean iteration, RTF `0.725752`, and
  5/5 enhanced WAV hashes equal to image-v5.
- Formal physical-board run: 100/100 PASS, 426,196 frames, profiling and
  hardware profiling off, zero counter snapshots, `5.394255 ms` mean
  START-to-output, `5.807605 ms` mean iteration, p99 frame/iteration
  `6.289661/6.717971 ms`, sustained RTF `0.728054`, and 100/100 enhanced WAV
  hashes equal to image-v5. Clip-mean enhanced SI-SDR is `14.511990 dB`.
- Fixed-five diagnostic profile: one hardware snapshot per 16 frames, 1,453
  samples; measured parameter traffic saving `54.47%` and sparse stage-load
  time `1.783506 ms` per sampled frame. This profiling run is not used for
  the production latency result.
- Post-route vectorless estimate: total on-chip `1.609 W` (Medium
  confidence); START-to-output energy estimate `8.679 mJ/frame`. This is not a
  physical board-rail measurement.
- Current regression: focused full-design contract `6 passed`; full suite
  `147 passed, 7 failed`. The untouched baseline independently gives
  `145 passed, 9 failed`; the same seven frozen v3/v4 and stale handoff/OOC
  evidence tests already fail there, while the two current contract tests were
  corrected.
- Final report and raw result directory:
  `outputs/latency/2026-09-14-sparse-v5-32pe/`.
