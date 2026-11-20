# DMA/control and profiling fast-path handoff

- Date: 2026-09-10 (Asia/Taipei)
- Branch: `codex/latency-experiment-32pe`
- Status: implementation and fixed-five board validation complete

## Result

The image-v5 32-PE design now passes steady-state mean throughput and the
per-file p99 8 ms gate when one persistent runtime is used. The fixed five-file
run completed 23,137 contiguous frames with aggregate sustained RTF 0.887954,
setup-amortized frame-loop RTF 0.960928, weighted mean iteration 7.086854 ms,
and worst per-file p99 7.662979 ms. All five enhanced WAV hashes are identical
to the frozen image-v5 baseline.

The full persistent PYNQ-script E2E RTF remains 1.078438 because file loading,
deferred dequantization, ISTFT, and WAV writing are serialized on the board.
PC-to-board-to-PC transport is not measured by this run. Isolated max-frame
outliers remain above 8 ms, so this is not a hard real-time proof.

## Implemented

- DMA-ready feature bundle v2 and exact v1-to-v2 upgrade.
- Mapped register access, cached static control writes, fast DMA submit.
- Coherent 176-word profile snapshot copy and deferred decode.
- Configurable hardware profile sampling interval.
- Native batch output dequantization after the measured frame loop.
- Persistent five-file runtime with one parameter load and one DMA allocation.
- Native C DMA polling experiment plus measured fallback to Python control.
- Production CLI defaults to the measured Python DMA path.

## Profiling result

Every-frame bulk snapshots reduced the old 5.299282 ms bucket to 0.861875 ms.
Sampling every 16 frames reduced the amortized bucket to 0.096304 ms/audio
frame and deferred decode from 25.180900 s to 2.039519 s. The sampled run
captured 1,453 coherent snapshots and kept all five outputs bit-exact.

## Verification

- `/home/ivanhuang/miniconda3/bin/python -m pytest -q software/tests`
  returned 81 passed.
- Board persistent result:
  `/home/xilinx/zephyr_image_v5_32pe_20260909/results/fixed5_persistent_8909d07`
- Board sampled-profile result:
  `/home/xilinx/zephyr_image_v5_32pe_20260909/results/profile5_sample16_8a4d82c`
- Board final independent-process result:
  `/home/xilinx/zephyr_image_v5_32pe_20260909/results/fixed5_deferred_1a518a5`
- Native DMA A/B:
  `smoke_file000_native_dma_ab81314` versus
  `ab_file000_python_3895f7a`

## Hardware boundary

No RTL or bitstream changed in this phase. Image `0x00050001` remains 32 PE,
64-bit AXI HP/stream, and 100 MHz. Existing full-route evidence is WNS +0.250
ns, LUT 45,188 (84.94%), FF 42,151 (39.62%), BRAM36 equivalent 79.5 (56.79%),
and DSP48 65 (29.55%). A hardware DMA ring was not promoted because the
software path passes the steady-state and p99 gates, the native C poll path was
slower, and a new queue would consume scarce LUT/timing margin.

## Commits

- `6a8d047` Batch input packing and profile snapshots
- `7ce9513` Upgrade existing feature bundles with DMA packets
- `804f8df` Separate sustained frame-loop latency
- `62d57f1` Move output dequantization into native hot path
- `ab81314` Run DMA control loop in native code
- `3895f7a` Expose DMA control mode in subset benchmarks
- `1a518a5` Defer output dequantization outside frame loop
- `bc6ddaf` Keep measured Python DMA control as default
- `8909d07` Keep PYNQ runtime alive across audio files
- `8a4d82c` Sample profiling snapshots outside the frame budget
- `9d43a3c` Align bring-up contract test with image v5

