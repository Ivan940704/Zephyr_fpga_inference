# Recommended final implementation

Use the integrated **Hybrid PE + sparse-v5** configuration, ABI `0x00050003`, PYNQ-Z1 / XC7Z020, 32 PEs at 100 MHz. This is the final integrated configuration with a completed formal 100-file board campaign in the available development records. It combines sparse DDR/cache loading, PL LayerNorm and DeepFilter computation on the shared Hybrid PE array.

This is the recommended final project result based on integration, correctness and measured resource/latency tradeoffs. It is not a claim that every metric is globally optimal.

## Exact source identity

- Board image hardware source: `f460743940ca66ed04f2e33746968ce587b0dd72`.
- Published source snapshot: `d842ca1399c41e59446306ca1445e7925e3cb69d`, which records the subsequent formal 100-file results.
- Between these two development commits, no production HDL or `software/` files changed. The HDL addition is a differential equivalence testbench; build/evidence scripts and reports were updated.
- Production integration starts at `rtl/top/accelerator_top.v` and `rtl/memory/sequential_v5_pe_memory_subsystem.v`. DeepFilter uses the shared PE array through `hybrid_pe_deepfilter_controller` and the CDF sequencer; the standalone legacy DeepFilter engine is historical.
- `SOURCE_MANIFEST.json` identifies all copied original files by SHA-256.
- Final release tag: `v1.0.0-hybrid-pe-final`.

## Formal board result

100/100 files and 426,196 frames passed; all 100 enhanced WAVs match frozen sparse-v5 outputs byte for byte. Per-file frame sequences are contiguous, final control/mailbox faults are zero and all three DMA channels are idle and error-free.

| Metric | Recommended Hybrid PE | Previous sparse-v5 |
|---|---:|---:|
| Mean START-to-output | 5.382242 ms | 5.394255 ms |
| Mean complete iteration | 5.796062 ms | 5.807605 ms |
| Sustained frame-loop RTF | 0.726617 | 0.728054 |
| Persistent end-to-end RTF | 0.928533 | 0.927193 |
| Maximum complete iteration | 15.404947 ms | 13.452320 ms |
| DSP48 | 62 | 68 |
| LUT | 44,717 | 42,773 |
| BRAM36 equivalent | 78.5 | 79.5 |
| Standard setup WNS at 100 MHz | +0.202 ns | +0.251 ns |

The small average-latency differences come from separate runs and do not establish a repeatable speedup. Hybrid PE saves DSP/BRAM while using more LUTs; its end-to-end RTF and observed maximum are slightly worse. Its optional 250-ps setup guardband is not met. Standard setup and the documented 50-ps hold guardband pass. These results do not establish hard real-time behavior or physical power consumption.

## Evidence

- [Formal metrics and aggregation methods](evidence/final_hybrid_pe/paper_metrics_100file.md).
- [Board and differential-test summary](evidence/final_hybrid_pe/summary.md).
- [Full 100-file machine-readable manifest](evidence/final_hybrid_pe/full100_run_manifest.json).
- [Per-file metrics](evidence/final_hybrid_pe/full100_per_file_metrics.csv).

These are preserved historical measurements for the exact source identity above. Publication verification checked source hashes and version identity; simulation, Vivado and board tests were not rerun during publication. Generated BIT/HWH and parameter binaries are not included in this source upload.
