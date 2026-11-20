# Hybrid PE array DeepFilter integration handoff

Date: 2026-09-16
Owner: Codex
Branch: `codex/hybrid-pe-deepfilter`
Hardware source commit: `f460743940ca66ed04f2e33746968ce587b0dd72`

## Result

Multi-Frame Complex DeepFiltering is now scheduled through the existing
`OWNER_CDF` path of `pe_array_datapath_v5_32`. The production design contains
one time-multiplexed 32-PE arithmetic array: neural dense/sparse jobs and CDF
complex terms use the same physical MAC lanes. There is no standalone
DeepFilter MAC engine in the production hierarchy.

`hybrid_pe_deepfilter_controller.v` retains spectrum history, reads generated
coefficients, dispatches grouped tap/phase packets, and stores/streams complex
INT32 results. Arithmetic remains in the existing Hybrid PE array through
`pe_cdf_sequencer`; the causal orders remain 5/3/1 for bins 0-31/32-127/128-255.

The image ABI is `0x00050003`. Both fullband and spectrum input packets are now
512 bytes and the output packet remains 2,048 bytes.

## Sparse-aware behavior retained

The sparse union planner, active-index lists, sparse DDR stage reads, parameter
cache residency, request/MAC zero-skipping, recurrent context storage, reset,
abort, and fault paths remain in the production subsystem. Focused sparse XSim
reported:

- dense-equivalent bytes: 2,107,312;
- planned sparse bytes: 865,808;
- actual sparse bytes: 865,808;
- saved bytes: 1,241,504;
- sparse commands/bursts/cycles: 1,322 / 7,247 / 292,348.

## Verification acquired

- Dense subsystem XSim: PASS, 1,452,257 checks, 60 jobs, 25 stages, 33,186
  sparse-side checks.
- Sparse subsystem XSim: PASS, 1,073,066 checks, 60 jobs, 24 stages, 33,186
  sparse-side checks.
- Production PE reference and XSim: PASS, 32 Hybrid PEs, 2,461 cycles over 22
  states.
- Legacy standalone DeepFilter versus shared-PE controller differential XSim:
  PASS over five history-bearing frames, 1,305 checks, and 1,280/1,280 complex
  INT32 bin results. Re-run with
  `rtl/scripts/run_hybrid_pe_deepfilter_equivalence_xsim.ps1`.
- Accelerator-top integration XSim: PASS, 17 checks.
- Architecture contract: PASS; production source excludes the standalone
  DeepFilter engine.
- Driver/ABI tests: 12 PASS.
- Full-design implementation-contract tests: 7 PASS.
- Final changed-scope regression (`implementation_contract`, `bringup`, and
  `inference`): 47 PASS.
- Current scoped host suite: 149 PASS / 7 historical frozen-evidence failures.
  The seven failures predate this branch and concern old v3/v4 image hashes,
  frozen manifest hashes, an obsolete exact timing value, and a status date.

## Vivado 2018.3 evidence

Full PYNQ-Z1 block-design implementation at 100 MHz:

- standard setup WNS `+0.202 ns`, TNS 0, zero setup failing endpoints;
- 50 ps hold-guardbanded WHS `+0.009 ns`, raw hold margin `+0.059 ns`, zero
  hold failing endpoints;
- optional 250 ps setup engineering margin `-0.048 ns` (not met and not used
  as the standard timing gate);
- zero routing errors, unconstrained internal endpoints, clockless registers,
  timing loops, DRC errors, and DRC critical warnings;
- LUT 44,717; FF 46,611; RAMB36 75; RAMB18 7; DSP48 62.

The connected-subsystem OOC route separately reports WNS `+0.013 ns`, internal
register-to-register WHS `+0.050 ns`, 32 Hybrid MAC instances, LUT 34,283, FF
34,759, DSP48 56, RAMB36 71, and RAMB18 2. Its `-1.410 ns` all-path hold value
is the expected virtual-I/O OOC artifact and is not substituted for full-design
hold closure.

## Artifacts and physical board

Release directory: `rtl/build/accelerator_full_release/f460743_20260916/`

- `zephyr_full.bit`: 4,045,679 bytes, SHA-256
  `9e537026de1d7215fddf8d262da86316a6ce5ed58ed20ec901b94c6313f4cf63`.
- `zephyr_full.hwh`: 585,343 bytes, SHA-256
  `253adfae9ae6058a6d1b29c733f71b48a65c4b929deea19f1e5ef0d055317ed7`.

The BIT was programmed to exact target
`localhost:3121/xilinx_tcf/Digilent/003017B78476A`. DONE internal/pin/IR are 1;
CRC, IDCODE, and security errors are 0. After a clean Linux reboot, JTAG
configuration alone left DMA MMIO unreachable from Linux. The earlier
`優化 FPGA 推論延遲` workflow revealed the missing step: PYNQ must also execute
`Overlay(bit).download()` to initialize the Linux/XRT overlay state. After that
step, control and all three DMA banks were accessible and runtime testing
proceeded normally.

The formal fixed-five used the exact sparse-v5 source/feature pair
`fixed5_sources_original + host_features_100_original_v2`. Files
000/025/050/075/099 passed, all 23,137 frame IDs were contiguous, and every
enhanced WAV SHA-256 matched the ABI `0x00050002` baseline byte-for-byte. Final
control error, first fault, mailbox error, and DMA error fields were zero; all
DMA channels were idle.

Board metrics for the hybrid image were weighted mean frame 5.380060 ms,
weighted mean complete iteration 5.788423 ms, aggregate p99 iteration
6.582944 ms, sustained frame-loop RTF 0.725672, and persistent end-to-end RTF
0.994996. The corresponding separate sparse-v5 run measured 5.389259 ms,
5.789871 ms, 6.567821 ms, 0.725752, and 0.990079. These small deltas are run
variation and are not claimed as a speedup. Enhanced SNR 12.542001 dB and
SI-SDR 12.458184 dB were identical.

A separate file-000 hardware-profile run captured six coherent snapshots:
87.852697% request sparsity / MAC skip, 13,992,784 skipped versus 1,934,768
retired MACs, 2,876,688 sparse-stage bytes read, and 3,445,248 bytes saved
(54.496724%). These are sampled counter totals rather than five-file aggregate
traffic. They verify that sparse planning, sparse DDR loading, and zero-skip
remained active while CDF used the shared PE array.

The formal profiling-off hybrid campaign passed file IDs 000--099: 100/100
files, 426,196 frames, and 3,408.768 s evaluated audio. All input/feature hashes
matched the frozen corpus and all 100 enhanced WAVs were byte-for-byte identical
to sparse-v5 ABI `0x00050002`. Weighted mean START-to-output was 5.382242 ms,
complete iteration 5.796062 ms, p99 iteration 6.713150 ms, sustained frame-loop
RTF 0.726617, and clip-mean enhanced SI-SDR 14.511990 dB. Per-file faults were
zero and all DMA channels ended idle/error-free.

Board-rail power, matching full-design hybrid vectorless power, thermal
behavior, long-duration endurance, DNSMOS, PESQ, STOI, and independent SI-SNR
remain outside the acquired evidence.

## Main files

- `rtl/integration/hybrid_pe_deepfilter_controller.v`
- `rtl/memory/sequential_v5_pe_memory_subsystem.v`
- `rtl/memory/memory_service_v5.v`
- `rtl/top/accelerator_top.v`
- `rtl/tb/tb_hybrid_pe_deepfilter_equivalence.sv`
- `rtl/scripts/smoke_accelerator_full_board_readonly.tcl`
- `rtl/reports/accelerator_full_bd_implementation/`
- `rtl/reports/accelerator_full_artifacts/`
- `rtl/reports/accelerator_full_board_hybrid_pe_20260916/board_program_status.txt`
- `rtl/reports/accelerator_full_board_hybrid_pe_20260916/board_mmio_readonly.txt`
- `rtl/reports/accelerator_full_board_hybrid_pe_20260916/fixed5_run_manifest.json`
- `rtl/reports/accelerator_full_board_hybrid_pe_20260916/full100_run_manifest.json`
- `rtl/reports/accelerator_full_board_hybrid_pe_20260916/full100_per_file_metrics.csv`
- `rtl/reports/accelerator_full_board_hybrid_pe_20260916/paper_metrics_100file.md`
- `rtl/reports/accelerator_full_board_hybrid_pe_20260916/profile_file000_metrics.json`
- `rtl/reports/accelerator_full_board_hybrid_pe_20260916/board_runtime_comparison.json`

No remote push was performed.
