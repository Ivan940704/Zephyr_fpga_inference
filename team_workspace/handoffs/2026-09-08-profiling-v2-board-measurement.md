# Profiling v2 board-measurement handoff

Date: 2026-09-08

## Ready

- Hardware source: `0d91423004978d3721c7ee1296fd80d974856346`.
- Image ABI: `0x00040002`.
- Full route: standard WNS +0.253 ns; 250 ps guardbanded WNS +0.003 ns;
  50 ps hold-guardbanded WHS +0.016 ns; zero timing/routing/blocking DRC
  failures.
- BIT SHA-256:
  `52d8f0296965068716d1b2a50966b5423f2abd92e8589e2e3fa372893097f289`.
- Matching HWH SHA-256:
  `0be56a415406f07fdaf619a142b1f209314440ae71d6f2a2ad3e617edc2eea57`.
- Exact-target JTAG programming and read-only v2 ABI smoke: PASS.
- Host regressions: 116 current software/RTL tests plus 81 isolated sparse
  tests, all PASS.
- Fixed 100-triplet input manifest, experiment matrix, 100-audio runner,
  endurance runner, PL snapshot parser, and power-trace analyzer are ready.

## Blocked inputs

The connected JTAG device has no explicitly identified PYNQ Linux/Jupyter/SSH
or serial execution endpoint in the current environment. Do not scan for or
guess an address, and do not operate DMA through XSCT while the PS/Linux fabric
may own it. Physical power additionally requires a calibrated external meter
and synchronized raw idle/load traces.

## Resume order on the confirmed PYNQ Linux endpoint

1. Clean-reboot the PS, copy and verify the pinned v2 release, and program the
   PL exactly once.
2. Build `libzephyr_native_layernorm.so` and `libzephyr_arm_barrier.so` on the
   ARM board; do not reuse host binaries.
3. Run `software/pynq/run_board_experiment_matrix.py`. Promote no option unless
   all boundary arrays and 256x2 accumulators are byte-exact, frame IDs are
   continuous, DMA/control/mailbox faults remain zero, and cleanup is safe.
4. Run `software/pynq/run_board_100_audio.py` against the exact 100-triplet
   manifest. Preserve raw metrics, enhanced WAVs, counter JSONL, hashes, and
   bootstrap aggregates.
5. Run `software/pynq/run_board_endurance.py`. PASS requires both one hour and
   450,000 continuous frames, healthy idle DMA state, one coordinated reset,
   reset-epoch advancement, and a successful post-reset frame.
6. Acquire five-repeat idle/load external-meter traces and analyze them with
   `software/evaluation/power_trace_metrics.py` using the checked-in
   measurement-spec schema.

The Vivado vectorless result (1.610 W total on-chip, Medium confidence) is only
a separate estimate and must never fill the physical-power fields.
