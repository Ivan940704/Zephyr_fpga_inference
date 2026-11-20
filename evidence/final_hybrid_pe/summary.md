# Hybrid PE accelerator PYNQ-Z1 board evidence

## Image and programming

Vivado 2018.3 programmed the release built from hardware source commit
`f460743940ca66ed04f2e33746968ce587b0dd72` into exact target
`localhost:3121/xilinx_tcf/Digilent/003017B78476A` (`xc7z020_1`). Internal,
pin, and IR DONE are 1; CRC, IDCODE, and security errors are 0.

The 4,045,679-byte BIT SHA-256 is
`9e537026de1d7215fddf8d262da86316a6ce5ed58ed20ec901b94c6313f4cf63`;
the matching HWH SHA-256 is
`253adfae9ae6058a6d1b29c733f71b48a65c4b929deea19f1e5ef0d055317ed7`.
The board ran image ABI `0x00050003` with input packet sizes 512/512 bytes
and a 2,048-byte output packet.

A clean Linux reboot followed by JTAG configuration left the AXI DMA MMIO
unreachable from Linux. The prior board workflow in the Codex task
`優化 FPGA 推論延遲` also performs a PYNQ `Overlay(bit).download()` before
opening the runtime. Repeating that required Linux/XRT initialization made
the accelerator control and all three DMA register banks readable. Runtime
tests below were acquired only after that step.

## Differential RTL gate

`tb_hybrid_pe_deepfilter_equivalence.sv` drives the frozen standalone
`sequential_deepfilter_engine` and the production
`hybrid_pe_deepfilter_controller + pe_cdf_sequencer + 16 shared Hybrid MAC
lanes` with identical varying spectra, coefficients, history, and frame
events. Vivado 2018.3 XSim passed five frames, 1,305 checks, and all 1,280
complex INT32 bin results bit-exactly. This test exists specifically to catch
quantization, coefficient-address, tap-order, history, and PE-pipeline drift.
It is reproducible from the worktree root with
`powershell -ExecutionPolicy Bypass -File rtl/scripts/run_hybrid_pe_deepfilter_equivalence_xsim.ps1`.

## Fixed-five production runtime

The fixed-five gate used the exact sparse-v5 baseline inputs, not a repacked
substitute:

- source root: `fixed5_sources_original`;
- feature root: `host_features_100_original_v2`;
- files: 000, 025, 050, 075, 099;
- parameter image SHA-256:
  `0a898aca19599f976b3988f92ff645b1490dc3ac470003683199e80b134f458a`.

Result: PASS, 5/5 files and 23,137/23,137 contiguous frames. All five
enhanced WAV files are byte-for-byte identical to the ABI `0x00050002`
sparse-v5 baseline. Final control error, first fault, mailbox errors, and DMA
errors are zero; all DMA channels are idle.

| Metric | sparse-v5 `0x00050002` | hybrid PE `0x00050003` |
|---|---:|---:|
| Weighted mean frame | 5.389259 ms | 5.380060 ms |
| Weighted mean complete iteration | 5.789871 ms | 5.788423 ms |
| Aggregate p99 iteration | 6.567821 ms | 6.582944 ms |
| Sustained frame-loop RTF | 0.725752 | 0.725672 |
| Persistent end-to-end RTF | 0.990079 | 0.994996 |
| Enhanced SNR | 12.542001 dB | 12.542001 dB |
| Enhanced SI-SDR | 12.458184 dB | 12.458184 dB |

The small timing differences are separate board runs and are not claimed as a
speedup. The result establishes functional equivalence and continued
real-time throughput for this five-file gate.

## Formal 100-file production runtime

The profiling-off persistent runtime passed all file IDs 000--099. It processed
426,196 contiguous frames representing 3,408.768 s of evaluated audio with one
runtime instance and one parameter load. All 100 input hashes and feature-bundle
metadata hashes matched the frozen sparse-v5 corpus, and all 100 enhanced WAVs
were byte-for-byte identical to the ABI `0x00050002` sparse-v5 baseline. Every
per-file final control/mailbox fault field was zero and all three DMA channels
were idle and error-free.

| Metric | Hybrid PE `0x00050003` |
|---|---:|
| Weighted mean START-to-output | 5.382242 ms |
| Weighted mean complete iteration | 5.796062 ms |
| Aggregate p99 START-to-output | 6.281840 ms |
| Aggregate p99 complete iteration | 6.713150 ms |
| Maximum complete iteration | 15.404947 ms |
| Sustained frame-loop RTF | 0.726617 |
| Setup-amortized frame-loop RTF | 0.730467 |
| Persistent end-to-end RTF | 0.928533 |
| Clip-mean enhanced SNR | 14.757918 dB |
| Clip-mean enhanced SI-SDR | 14.511990 dB |

## Sparse-aware runtime evidence

An additional file-000 run sampled coherent hardware profiling counters every
1,000 frames and on the final frame (six samples total). It used the same
formal source and feature bundle as the fixed-five gate. The sampled totals
show that sparse execution remained active while the shared array also
executed CDF:

- dense-equivalent requests: 995,472;
- actual weight requests: 120,923 (36,684 dense + 84,239 sparse);
- request sparsity / MAC skip fraction: 87.852697%;
- retired MACs: 1,934,768; skipped MACs: 13,992,784;
- sparse-stage bytes read: 2,876,688;
- sparse-stage bytes saved: 3,445,248 (54.496724%);
- CDF run state: 18,556 cycles across the six sampled frames;
- cycle-conservation checks: PASS;
- final accelerator faults and DMA errors: zero.

These are sampled counter totals, not fixed-five aggregate traffic totals.
They demonstrate that sparse planning/loading and MAC skipping remained live
in the hybrid image; they are not a physical-power measurement.

## Evidence files

- `board_program_status.txt`: exact JTAG target and configuration status.
- `vivado-program.log`: Vivado 2018.3 programming transcript.
- `hybrid_deepfilter_equivalence_xsim.log`: differential RTL result.
- `baseline_sparse_v5_fixed5_manifest.json`: frozen board A/B baseline.
- `fixed5_run_manifest.json`: hybrid PE fixed-five result.
- `profile_file000_metrics.json`: sampled sparse counter summary.
- `profile_file000_hardware_profile.jsonl`: raw sampled counter snapshots.
- `board_runtime_comparison.json`: explicit A/B and output-hash comparison.
- `full100_run_manifest.json`: complete hybrid 100-file board result.
- `baseline_sparse_v5_full100_manifest.json`: frozen A/B baseline manifest.
- `full100_output_bit_exact_comparison.txt`: 100-file byte comparison.
- `full100_runner.log`: complete persistent-run transcript.
- `full100_per_file_metrics.csv`: all per-file latency, quality, and hashes.
- `paper_metrics_100file.md`: aggregate paper-number tables and evidence scope.

## Not acquired

No board-rail physical power, thermal, or long-duration endurance campaign was
run. No matching full-design hybrid vectorless-power report was acquired; a
historical image's estimate is not substituted for this image or for a physical
board measurement. DNSMOS, PESQ, STOI, and independent SI-SNR were not acquired.
