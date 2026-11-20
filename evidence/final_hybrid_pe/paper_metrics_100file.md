# Hybrid PE 100-file paper metrics

## Formal campaign identity and correctness

| Metric | Value | Evidence scope |
|---|---:|---|
| Status | PASS | Formal profiling-off board run |
| Board | PYNQ-Z1 | Board measurement |
| Device | XC7Z020-1 | Routed/board identity |
| Clock | 100 MHz | Routed/board identity |
| Image ABI | `0x00050003` | Board register |
| Hardware source commit | `f460743940ca66ed04f2e33746968ce587b0dd72` | BIT build identity |
| Files passed | 100 / 100 | File IDs 000--099 |
| Frames processed | 426,196 | Board run |
| Evaluated audio | 3,408.768 s | 56.8128 min |
| STFT window | 32 ms | Runtime configuration |
| Frame hop | 8 ms | Runtime configuration |
| Runtime instances | 1 | Persistent runtime |
| Parameter loads | 1 | Persistent runtime |
| Parameter-image SHA-256 | `0a898aca19599f976b3988f92ff645b1490dc3ac470003683199e80b134f458a` | Frozen sparse-v5 parameters |
| Input WAV hash matches | 100 / 100 | Versus frozen sparse-v5 full100 |
| Feature metadata hash matches | 100 / 100 | Versus frozen sparse-v5 full100 |
| Enhanced WAV bit-exact matches | 100 / 100 | Versus ABI `0x00050002` sparse-v5 |
| Contiguous per-file frame sequences | 100 / 100 | Board manifest |
| Fault-free per-file final states | 100 / 100 | Control/mailbox faults zero |
| DMA-idle/error-free per-file final states | 100 / 100 | Three DMA channels |
| Final control error | 0 | Board register |
| Final first fault | 0 | Board register |
| Final mailbox errors | 0 / 0 | Board registers |
| Final DMA errors | 0 | Three DMA channels |
| Final DMA idle channels | 3 / 3 | Three DMA channels |

## Profiling-off board latency and throughput

| Metric | Hybrid PE value | Frozen sparse-v5 value | Unit / aggregation |
|---|---:|---:|---|
| Weighted mean START-to-output | 5.382241839 | 5.394254902 | ms/frame |
| Weighted mean complete iteration | 5.796061535 | 5.807605082 | ms/frame |
| START-to-output p50 | 5.349544500 | 5.361612000 | ms/frame, all 426,196 frames |
| START-to-output p95 | 6.055170750 | 6.067756249 | ms/frame, all frames |
| START-to-output p99 | 6.281840300 | 6.289661300 | ms/frame, all frames |
| START-to-output maximum | 14.904314000 | 12.846462001 | ms/frame, all frames |
| Complete-iteration p50 | 5.763142000 | 5.775218500 | ms/frame, all frames |
| Complete-iteration p95 | 6.473699500 | 6.486345751 | ms/frame, all frames |
| Complete-iteration p99 | 6.713150350 | 6.717971198 | ms/frame, all frames |
| Complete-iteration maximum | 15.404947000 | 13.452319999 | ms/frame, all frames |
| Worst per-file p99 iteration | 7.036061150 | 7.064884140 | ms/frame, file 045 for both runs |
| Sustained frame-loop RTF | 0.726617419 | 0.728054134 | Frame loop / evaluated audio |
| Setup-amortized frame-loop RTF | 0.730467132 | 0.732000410 | Setup + frame loop / audio |
| Persistent end-to-end RTF | 0.928532685 | 0.927192878 | Full persistent script / audio |
| Sustained frame throughput | 172.070381077 | 171.730823685 | frames/s |
| Mean-iteration reciprocal throughput | 172.530949513 | 172.188016566 | iterations/s |
| Runtime setup | 13.122778793 | 13.451938853 | s |
| Total frame loop | 2,476.870204692 | 2,481.767634111 | s |
| Output dequantization | 7.962565543 | 7.910637671 | s |
| Postprocess and WAV write | 283.051628968 | 281.255635068 | s |
| Total persistent wall time | 3,165.152504551 | 3,160.585411082 | s |

## Speech-enhancement quality over 100 files

| Metric | Clip mean | Audio-duration weighted mean | Unit |
|---|---:|---:|---|
| Input SNR | 7.092192839 | 7.132004656 | dB |
| Enhanced SNR | 14.757917947 | 14.751458577 | dB |
| SNR improvement | 7.665725107 | 7.619453921 | dB |
| Input SI-SDR | 7.080649974 | 7.121167929 | dB |
| Enhanced SI-SDR | 14.511990404 | 14.504531698 | dB |
| SI-SDR improvement | 7.431340430 | 7.383363769 | dB |
| SI-SNR | N/A | N/A | Not independently evaluated |
| DNSMOS OVR | N/A | N/A | Not evaluated by this run |
| PESQ | N/A | N/A | Not evaluated by this run |
| STOI | N/A | N/A | Not evaluated by this run |

## Counter-enabled sparsity evidence

| Metric | Value | Scope |
|---|---:|---|
| Profiled file | 000 | Same ABI `0x00050003` image |
| Profile samples | 6 | Every 1,000 frames plus final frame |
| Dense-equivalent weight requests | 995,472 | Six sampled frames |
| Actual weight requests | 120,923 | Six sampled frames |
| Dense requests | 36,684 | Six sampled frames |
| Sparse requests | 84,239 | Six sampled frames |
| Active request fraction | 12.147303% | Actual / dense-equivalent requests |
| Request sparsity | 87.852697% | Skipped request fraction |
| Retired MACs | 1,934,768 | Six sampled frames |
| Skipped MACs | 13,992,784 | Six sampled frames |
| MAC skip fraction | 87.852697% | Six sampled frames |
| Sparse-stage actual bytes | 2,876,688 | Six sampled frames |
| Sparse-stage saved bytes | 3,445,248 | Six sampled frames |
| Parameter-stage traffic reduction | 54.496724% | Six sampled frames |
| AXI read bursts | 24,375 | Six sampled frames |
| Maximum outstanding bursts | 6 | Sampled hardware counter |
| CDF run cycles | 18,556 | Six sampled frames |
| Cycle-conservation failures | 0 | Six sampled frames |
| Profile-run hardware/DMA faults | 0 | Final state |

## Routed hybrid FPGA implementation

| Metric | Used | Device total | Utilization / result |
|---|---:|---:|---:|
| Physical Hybrid PEs | 32 | -- | One time-multiplexed array |
| CDF lanes per complex-term phase | 16 | 32 PEs | Shared PE array |
| LUT | 44,717 | 53,200 | 84.054511% |
| Flip-flop | 46,611 | 106,400 | 43.807331% |
| RAMB36 | 75 | 140 | -- |
| RAMB18 | 7 | 280 | -- |
| BRAM36 equivalent | 78.5 | 140 | 56.071429% |
| DSP48 | 62 | 220 | 28.181818% |
| External AXI HP stream width | 64 | -- | bits |
| Internal parameter feed width | 256 | -- | bits |
| Standard setup WNS | +0.202 | -- | ns |
| Standard setup TNS | 0.000 | -- | ns |
| Setup failing endpoints | 0 | -- | count |
| Raw hold margin | +0.059 | -- | ns |
| 50-ps guardbanded WHS | +0.009 | -- | ns |
| Hold failing endpoints | 0 | -- | count |
| Optional 250-ps setup margin | -0.048 | -- | ns; optional margin not met |
| Routing errors | 0 | -- | count |
| DRC errors | 0 | -- | count |
| DRC critical warnings | 0 | -- | count |

## Numerical replacements for the supplied manuscript

| Manuscript metric | Current draft number | Hybrid evidence number | Paper-safe status |
|---|---:|---:|---|
| Mean board START-to-output latency | 5.394 ms | 5.382 ms | Replace |
| Sustained board-loop RTF | 0.728 | 0.727 | Replace |
| Request/operation skip | 88.22% | 87.85% | Replace; sampled counter evidence |
| Parameter traffic reduction | 54.47% | 54.50% | Replace; sampled counter evidence |
| LUT | 42,773 | 44,717 | Replace |
| Flip-flop | 45,344 | 46,611 | Replace |
| DSP48 | 68 | 62 | Replace |
| BRAM36 equivalent | 79.5 | 78.5 | Replace |
| Enhanced SI-SDR | 14.54 dB | 14.512 dB | Replace |
| SI-SDR improvement | 7.43 dB | 7.431 dB | Replace |
| SI-SNR table entry | 14.54 dB | N/A | Do not substitute SI-SDR into SI-SNR column |
| DNSMOS OVR | 3.00 | N/A | Not measured in this campaign |
| INT8 model parameters | 965 K | 965 K | Model fact; not a board measurement |
| Claimed custom-ASIC energy | 52.9 nJ/frame | N/A | Draft analytical value; full-model accounting not validated |
| Claimed energy improvement | approximately 28x | N/A | Draft analytical value; not validated by this campaign |
| INT8 multiply cost assumption | 0.20 pJ/op | 0.20 pJ/op | Analytical 45-nm assumption |
| INT32 add cost assumption | 0.10 pJ/op | 0.10 pJ/op | Analytical 45-nm assumption |
| Hybrid FPGA board-rail power | N/A | N/A | Not physically measured |
| Hybrid FPGA vectorless power | N/A | N/A | No matching hybrid full-design power report acquired |

## Evidence file hashes

| Evidence file | SHA-256 |
|---|---|
| `full100_run_manifest.json` | `475c5dc332ab009f0d2cc4072aafd635fde88a2e76562ef5631c0bd9bc9cf14b` |
| `full100_output_bit_exact_comparison.txt` | `d0068a6460f80377d908b8348d4428240199335ec3bf53c3a344925618bbb729` |
| `baseline_sparse_v5_full100_manifest.json` | `5b7c8420aa3a864cbaabd40c8573d2789930def503e80f76b47c6c8a83b9576f` |
| `full100_runner.log` | `859bfbda130a93e234447d6092f4aa684a94bcdd71e7e2c4e3dfdb0a410bc7e1` |
