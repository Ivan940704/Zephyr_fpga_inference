# Final 100-audio validation for the real-time accelerator

- Date: 2026-09-09 (Asia/Taipei)
- Owner: Codex
- Status: accepted test scope; execution waits for a timing-clean final image
- Development smoke set: file IDs `000/025/050/075/099`
- Final corpus: file IDs `000..099`

## Decision

Intermediate RTL and board-capable checkpoints use the frozen five-file set
for fast, directly comparable A/B measurements. After the PL LayerNorm,
production-v2 32-PE path, internal 256-bit feeding, selected clock, and
persistent/overlapped DMA are integrated, the release candidate is evaluated
against the same 100-triplet corpus and hashes used by the prior `ec457b1`
record.

The final test is not permitted until the complete Zynq block design has
non-negative WNS and WHS, complete timing coverage, zero route-error nets, no
blocking DRC, and a matching BIT/HWH pair whose hashes and image ABI are
recorded. Component OOC timing alone is insufficient.

## Pinned comparison baseline

The prior 100-audio record contains 100 clips, 426,196 frames, and 3,408.768 s
of evaluated audio. Its aggregate measurements are:

| Measurement | `ec457b1` baseline |
|---|---:|
| Weighted mean frame latency | 11.055 ms |
| Frame-compute RTF | 1.382 |
| Board-loop RTF | 2.739 |
| End-to-end RTF | 2.853 |
| Mean SNR improvement | +7.688 dB |
| Mean SI-SDR improvement | +7.454 dB |

The separate file081 hardware profile reports PL mean/p95/p99 of
10.484/11.411/12.282 ms. Baseline identity is pinned by commit, BIT/HWH,
parameter/runtime, input-triplet, and result hashes; a new run with different
inputs is not called a direct A/B.

## Two-pass measurement design

### Pass A: primary 100-audio throughput

Run all 100 clips with profiling and per-frame MMIO diagnostics disabled on
the hot path. Preserve one result directory per file plus aggregate
`run_manifest.json` and `evaluation.json`. Record per clip and aggregate:

- frame count, evaluated samples, and duration;
- frame latency mean, standard deviation, p50, p95, p99, and maximum;
- throughput frames/s and frame-compute RTF;
- board-loop and end-to-end wall time/RTF;
- frame-ID continuity and dropped/duplicated frame count;
- first-fault, control, mailbox/interaction, DMA status, timeout, and reset
  epoch evidence;
- input/output SHA-256 and enhanced WAV statistics;
- input/enhanced SNR and SI-SDR, their deltas, distribution statistics, and
  bootstrap mean confidence intervals;
- PESQ/STOI only when the required packages are actually available.

Each clip starts from one hardware-acknowledged reset. The reset epoch must
advance exactly once, all DMA channels must be stopped and error-free before
launch, and final fault/control/DMA values must remain zero. Cleanup performs
one final acknowledged reset and records the final DMA state.

### Pass B: stage and operation profiling

Run the fixed five files plus representative file081 with coherent hardware
profiling enabled. This pass explains latency but is not used as the primary
throughput result because snapshot MMIO reads and timestamps perturb the hot
path. Report mean/p50/p95/p99/max cycles and milliseconds for:

- PL magnitude ingress and shared LayerNorm;
- fullband feature dispatch, PE stages 0/1/2, and fullband projection return;
- subband assembly/LayerNorm and each branch/context for stages 3 through 11;
- per-stage memory load, PE compute, and stall cycles;
- serializer, shared requant, state/active-index/coefficient retirement;
- CDF/deep-filter processing and output streaming;
- AXI read issue, `r_wait`, backpressure, and achieved bytes/cycle;
- PS interaction, DMA submission/completion, output reconstruction, and any
  remaining software-only work.

The profile schema/decoder must be versioned for 32 PEs. In particular, the
current `dense_equivalent_requests * 16` MAC accounting must use the image's
recorded PE count, and cycle conservation must pass on every captured frame.

## Hardware implementation report

For the exact final BIT/HWH, preserve post-synthesis and post-route reports and
publish one comparison table containing:

- Slice LUT, LUTRAM/distributed RAM, FF, DSP48E1, RAMB18E1, RAMB36E1,
  BUFG/MMCM/PLL, and device-utilization percentages;
- chosen PL clock, period, WNS/TNS, WHS/THS, timing coverage, critical path,
  routed-net status, and DRC summary;
- hierarchy counts for 32 Hybrid MAC lanes, the shared LayerNorm engine, Local
  RQ Bank, Shared RQ Engine, serializer, memory banks, and DMA-facing logic;
- analytical/simulation/component/full-system/board evidence clearly marked
  as different scopes.

Vivado vectorless power may be included only as an estimate. It is not called
physical board power without synchronized external-meter evidence.

## Comparison outputs

The final result bundle will include at least:

```text
run_manifest.json
evaluation.json
resource_timing_summary.json
stage_latency_summary.json
comparison_vs_ec457b1.json
summary.md
fileid_000/metrics.json
...
fileid_099/metrics.json
```

`summary.md` contains three concise tables: hardware resources/timing,
end-to-end 100-audio performance/quality, and stage/operation latency. Raw
per-frame profile data may remain outside Git, but its checksum list and
aggregate summaries are retained.

## Acceptance

- Functional run: 100/100 clips PASS, continuous frame IDs, zero accelerator/
  control/DMA faults, and safe reset/cleanup.
- Real-time: PL p99 below 8 ms and aggregate board-loop and end-to-end RTF
  below 1.0.
- Preferred margin: both aggregate RTF values at or below 0.8.
- Regression: boundary arrays and integer results pass the frozen oracle;
  audio-quality differences are reported rather than hidden or inferred.
- Comparison: every percentage improvement states its denominator and uses
  the pinned same-corpus `ec457b1` baseline.
