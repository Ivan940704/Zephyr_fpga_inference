# Handoff: imported Memory RTL baseline and integration assessment

- From: Codex
- To: memory image/layout, fullband integration, Vivado block-design, and PS
  driver owners
- Date: 2026-09-01 (Asia/Taipei)
- Task: `team_workspace/tasks/2026-09-01-memory-rtl-import.md`
- Branch: not created because the outer repository still has no initial commit

## Outcome

The uploaded Memory-only archive was inspected as untrusted data, safely
extracted to a temporary directory, and selectively classified into the outer
repository. Nothing was written to the dirty `upstream/` nested repository and
no root README was overwritten.

The imported RTL is a standalone one-outstanding AXI4 read DMA plus a raw
64-bit dual-port BRAM cache. It is useful as a parameter stage-loader baseline,
but it is not yet the complete memory service expected by
`fullband_three_layer.v`. The detailed interface/layout analysis and proposed
integration sequence are in
`docs/memory/MEMORY_INTEGRATION_ANALYSIS.md`.

## Upload provenance and safety

- Source: `rtl_upload_bundle.zip`
- ZIP SHA-256:
  `d9f98401acdb60b9d19e678631b1d12ca6c772344cd51ab3b22bf7fb4529c3e9`
- Archive entries: 12 regular files; 1,508,272 uncompressed bytes
- Archive CRC test: PASS
- Rejected conditions checked: absolute paths, `..` traversal, symlinks,
  encrypted entries, duplicate case-folded paths, and nested archives; none
  were present.
- Current `upstream` HEAD matches the source handoff commit
  `13ea1405c9a400aac647025a42b216975765a9bb`; existing `upstream` worktree
  changes were preserved.

The uploaded binary snapshot remains byte-identical:

```text
74afdb9a57c7e8863556c48e0e7a8ad3bb9661b27ccb8a2c4665b99c5e60e938  parameters_axi.bin
```

Before repository-path adaptation, running the unmodified generator against the
current `upstream/parameters/manifest.json` reproduced the uploaded binary
byte-for-byte and the uploaded Verilog header after ignoring CRLF/LF; the JSON
content differed only in its `source_manifest` path string.

The classified JSON/header were regenerated after adapting the source manifest
and generator paths to the outer/nested repository layout:

```text
2877670fda56730f43bcee02e25ee015781a6f19f6e140f2a222eb08806e4664  memory_layout.json
d8e9dccf2b4028806acfe1ef79c228e1cf83253b6fb932e2ecc2258398e6e584  model_memory_map.vh
```

## Classified files

- Synthesizable/cache ABI:
  - `rtl/memory/memory.v`
  - `rtl/memory/model_memory_map.vh`
- Verification/build flow:
  - `rtl/tb/tb_memory.v`
  - `rtl/scripts/run_memory_xsim.ps1`
  - `rtl/tools/generate_axi_memory_image.py`
  - `rtl/tests/test_axi_memory_image.py`
  - memory sources added to `rtl/Makefile`, `rtl/scripts/run_all_xsim.tcl`, and
    `rtl/scripts/Run-XSim-Tests.cmd`
- Generated snapshot:
  - `outputs/memory/2026-09-01/parameters_axi.bin`
  - `outputs/memory/2026-09-01/memory_layout.json`
- Documentation/provenance:
  - `docs/memory/MEMORY_RTL_GUIDE.md`
  - `docs/memory/MEMORY_INTEGRATION_ANALYSIS.md`
  - `docs/memory/source_bundle/`
  - `rtl/README.md`
  - `PROJECT_STATUS.md`

## Verification performed in this workspace

1. Current image integrity:

   ```text
   python3 -m pytest -q rtl/tests/test_axi_memory_image.py
   2 passed in 0.03s
   ```

   This verifies stage/bus alignment, all shared-gate halves and metadata,
   non-shared bytes, maximum stage size, and the classified binary/JSON
   snapshot against current `upstream/parameters`.

2. Exact regeneration:

   ```text
   python3 rtl/tools/generate_axi_memory_image.py \
     --output-bin <temp>/parameters_axi.bin \
     --output-map <temp>/memory_layout.json \
     --output-vh <temp>/model_memory_map.vh
   cmp <temp>/parameters_axi.bin outputs/memory/2026-09-01/parameters_axi.bin
   cmp <temp>/memory_layout.json outputs/memory/2026-09-01/memory_layout.json
   cmp <temp>/model_memory_map.vh rtl/memory/model_memory_map.vh
   ```

   Result: all three `cmp` checks PASS.

3. Existing arithmetic/reference regression:

   ```text
   python3 rtl/tests/reference_checks.py
   13 tests PASS
   ```

4. HDL regression attempt:

   ```text
   make -C rtl test
   ```

   The Python 13/13 portion passed; HDL compilation stopped with exit 127
   because `iverilog`/`vvp` are not installed. `verilator` and `vivado` are also
   unavailable in this environment. No new HDL simulation was claimed.

## Prior local evidence retained, not reclassified as a new result

The uploaded handoff says `tb_memory` passed Vivado Simulator 2024.1 and lists
burst split, 4 KiB boundary, BRAM data, byte strobe, invalid command, and
`SLVERR` coverage. The bundle does not contain its console log. The current
project's stored Vivado 2018.3 log remains 20/20 from before `tb_memory` was
added; the imported test is now in both XSim manifests but has not been rerun.

## Main integration findings

- Existing GSU/projection requests need 128-bit, 16-lane weight words. The raw
  cache exposes one 64-bit word per local read.
- v2 weights remain row-major. A fixed source column's 16 output lanes are
  strided by 64 or 320 bytes, so two adjacent 64-bit reads cannot satisfy one
  logical weight response.
- A GSU parameter response is 5,792 bits at 16 lanes; projection is 1,120 bits.
  Current INT64 multiplier/shift arrays need range-checked lowering and a
  per-tile packed record/unpacker.
- The fullband controller immediately advances GSU1 -> GSU2 -> projection and
  has no stage-load completion/error barrier.
- The 512 KiB cache can hold the 460,688-byte fullband span, but a structural
  XC7Z020 estimate is roughly 128/140 BRAM36 for a 64-bit implementation. A
  256 KiB single-stage cache is roughly 64 BRAM36 but requires layer barriers.
  Neither number is synthesis evidence.
- The imported custom AXI AR/R master overlaps architecturally with the accepted
  Xilinx AXI DMA/64-bit AXI4-Stream direction. The block design must explicitly
  choose whether the custom master only loads static parameter stages or
  weights/parameters also arrive over AXI4-Stream.
- The source bundle's CPU LayerNorm writeback proposal is not the current
  system boundary. With fullband result egress and PS subband input ingress over
  AXI4-Stream, BRAM-to-DDR writeback is not a prerequisite for this checkpoint.

## Recommended next checkpoint

Define and test a v3 consumer-native image with
`{stage,matrix,row_tile,source_index,lane}` weights and range-checked packed
parameter tiles. Then implement an independent 64-to-128-bit memory-service
adapter and add stage barriers before connecting it to the reduced fullband
harness. Only after that behavioral checkpoint should the team use Vivado
synthesis to choose 256 KiB single-stage versus smaller tile ping-pong caches.
