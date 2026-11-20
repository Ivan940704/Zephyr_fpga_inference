# Image-v5 32-PE board-results handoff

- Branch: `codex/latency-experiment-32pe`
- Result commit: `37e29d1`
- Hardware source commit: `8cd92f8`
- Runtime range-fix commit: `0a8f510`
- Status: requested implementation, fixed-five test, 100-audio test, and
  six-file coherent profile complete

## Result

- The 100-file PL aggregate is 6.942 ms mean and 7.475 ms p99; the worst
  per-file p99 is 7.704 ms, so the PL 8 ms hop gate passes.
- Board-loop/E2E RTF are 1.740/1.861, so the complete application is not yet
  real-time.
- The timing-clean full-Zynq image runs at 100 MHz with WNS +0.250 ns,
  guardbanded WHS +0.016 ns, 45,188 LUT, 42,151 FF, 79.5 BRAM36 equivalent,
  and 65 DSP. The 102 MHz 32-lane datapath candidate failed setup and was not
  programmed.
- All 100 clips passed with contiguous frame IDs and final DMA channels
  idle/error-free. Mean SNR-delta and SI-SDR-delta changed by only
  -0.023/-0.022 dB versus `ec457b1`.

## Continue from here

The first software target is the profiled
`T13_output_invalidate_copy_complete__T14_frame_retirement_fault_check_complete`
bucket at 5.303 ms/frame. Preserve bounded completion, sticky-fault reporting,
and final DMA/error checks while reducing per-frame Python/MMIO work, for
example with a native bulk snapshot or safely amortized checks. The next PL
targets are `sb_load_wait` (2.043 ms/frame) and `sb_run` (2.485 ms/frame).

Do not call a follow-up real-time until a fresh unprofiled board run has both
board-loop and E2E RTF below 1.0. Keep the external Zynq HP/AXIS boundary at its
native 64 bits unless the block-design contract is deliberately redesigned.

## Evidence

- Tracked report:
  `rtl/reports/accelerator_realtime_image_v5_32pe_board_20260910/REPORT.md`
- Full result summaries and per-stage JSON are in the same directory.
- Full raw JSON/NPZ evidence archives remain in the shared Windows workspace:
  `outputs/latency/2026-09-10-image-v5-32pe/`.
- `rtl/pe_array/baseline/v1` has no diff against `ec457b1`.
