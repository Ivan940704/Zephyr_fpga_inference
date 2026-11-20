# Sparse-memory accelerator-top source manifest

Status: production integration allowlist

Sparse subsystem checkpoint: `6a13782` (`Complete CP6 isolated Vivado evidence`)

The active memory wrapper and its uniquely named dependencies are frozen under
`sparse_memory_v1/`. The production PE and job-controller files used beside
them are byte-identical to the frozen CP6 imports. `rtl/control/fsm.v` and
`rtl/top/accelerator_top.v` evolve at the integration boundary.

This manifest prevents a future accelerator build from collecting every RTL
file by wildcard.  Only the listed current sources, plus newly reviewed
top-specific glue, may enter the production compile.  Verify the frozen inputs
from repository root with:

```bash
sha256sum -c docs/memory/SHA256SUMS
sha256sum -c docs/frozen/PE_MEMORY_V4_SHA256SUMS
```

## 1. Include dependency

Add repository `rtl/` and `sparse_memory_v1/rtl/` to the Verilog include search
path. The sparse subsystem includes:

```text
sparse_memory_v1/rtl/sparse_memory_v4_map_v1.vh
```

The header is a dependency, not a separately elaborated module.

## 2. Compile order

Vivado 2018.3 uses separate SystemVerilog and Verilog analysis calls in the
validated runner.

### SystemVerilog sources

Compile these first with SystemVerilog enabled:

```text
rtl/pe_array/baseline/v1/rtl/arithmetic/pe_requant_lane.sv
rtl/pe_array/baseline/v1/rtl/arithmetic/pe_local_requant_bank_4lane.sv
rtl/pe_array/baseline/v1/rtl/pe/pe_hybrid_mac.sv
sparse_memory_v1/rtl/sparse_memory_service_v1.sv
sparse_memory_v1/rtl/sparse_stage_map_v1.sv
sparse_memory_v1/rtl/sparse_union_planner_v1.sv
sparse_memory_v1/rtl/sparse_recurrent_context_store_v1.sv
sparse_memory_v1/rtl/sequential_v4_sparse_memory_subsystem.sv
```

### Verilog-2001 sources

Compile in this deterministic order:

```text
sparse_memory_v1/rtl/sparse_memory_dma_v1.v
sparse_memory_v1/rtl/sparse_memory_v4_table_v1.v
sparse_memory_v1/rtl/sparse_recurrent_context_store_core_v1.v
rtl/memory/sequential_pe_job_controller.v
rtl/pe_array/baseline/v1/rtl/nonlinear/pe_sigmoid_lut_255.v
rtl/pe_array/baseline/v1/rtl/postprocess/pe_gate_postprocess.v
rtl/pe_array/baseline/v1/rtl/pe/pe_membrane_sequencer.v
rtl/pe_array/baseline/v1/rtl/stream/pe_output_serializer.v
rtl/pe_array/baseline/v1/rtl/stream/pe_shared_requant_engine.v
rtl/pe_array/baseline/v1/rtl/index/pe_spike_decision.v
rtl/pe_array/baseline/v1/rtl/index/pe_active_index_writer.v
rtl/pe_array/baseline/v1/rtl/pe/pe_cdf_sequencer.v
rtl/pe_array/baseline/v1/rtl/top/pe_array_datapath.v
rtl/memory/layernorm_mailbox.v
rtl/control/fsm.v
rtl/integration/layernorm_mailbox_fsm_adapter.v
rtl/integration/sequential_feature_dispatcher.v
rtl/integration/sequential_df_coefficient_store.v
rtl/leaf/deepfilter_complex_mac.v
rtl/integration/sequential_deepfilter_engine.v
rtl/top/accelerator_top.v
```

`layernorm_mailbox` and `fsm` remain above/beside the frozen sparse subsystem.
The mailbox adapter, feature dispatcher, coefficient store, DeepFilter engine,
and `accelerator_top` connect those blocks. CP7 subsequently registers the
sparse service's planned-byte calculation and parameter write strobes for
full-design setup closure; its connected XSim evidence is retained under
`sparse_memory_v1/reports/cp7/`.

## 3. Compile source identity

`docs/memory/SHA256SUMS` pins every active compile source, textual include,
top-level constraint, and v4 image/reference artifact. It is the single
machine-checked source-identity record; do not duplicate hashes in this prose
file. The sparse import checksums and CP7 evidence verifier remain authoritative
for the isolated sparse development boundary.

## 4. Parameter image and verification artifacts

| Artifact | Role | SHA-256 |
|---|---|---|
| `outputs/memory/2026-09-03/v4/parameters_v4.bin` | production DDR image | `e4f1f5cd78007a47c8ecfc137f2f0e8117aa2af162bd7050913bf1867cf2cf34` |
| `outputs/memory/2026-09-03/v4/memory_layout_v4.json` | machine-readable geometry | `40089d76ed4a7de77c67c50d39a8a4d43bdc595d1ee0a453d32e491a625ce7d1` |
| `outputs/memory/2026-09-03/v4/memory_golden_v4.json` | generated golden values | `18786f05ca4c41aa48ae995f038b9012ef5634f56e7b136bb2c0c1f938a40556` |
| `rtl/memory/model_memory_v4_readback_table.v` | verification-only readback vectors | `34c538ca10ad7723314548e101dd503489ae8bec14a278d189119930fa00f869` |

The image is 1,053,056 bytes.  Its global LUT starts at byte 64 and contains
2,040 bytes.  All twelve stage transfers total 1,050,544 bytes per frame.

## 5. Constraint and evidence inputs

- Apply `rtl/memory/sequential_v4_pe_memory_subsystem_100mhz.xdc` only to the
  subsystem OOC top.
- Apply `rtl/top/accelerator_top_100mhz.xdc` only to the current
  `accelerator_top` OOC build.  It constrains the single 100 MHz clock; I/O
  delays, generated clocks, CDC and physical constraints belong to the future
  Zynq block-design wrapper.
- The connected schedule test is
  `rtl/tb/tb_sequential_v4_pe_memory_subsystem_fsm.sv`.
- The mailbox/FSM atomic-frame test is
  `rtl/tb/tb_layernorm_mailbox_fsm_adapter.sv`.
- The Step-4 XSim/elaboration runner is
  `rtl/scripts/Run-Accelerator-Top-Step4-XSim.cmd`.
- The Step-4 OOC synthesis runner is
  `rtl/scripts/Run-Accelerator-Top-Step4-Vivado.cmd`.
- The feature-dispatcher unit/adapter/top-elaboration runner is
  `rtl/scripts/Run-Accelerator-Top-Feature-XSim.cmd`.
- Its focused top-level timing-cut harness is
  `rtl/tb/tb_accelerator_top_timing_cut.sv`.
- The feature-dispatcher OOC synthesis runner is
  `rtl/scripts/Run-Accelerator-Top-Feature-Vivado.cmd`.
- The coefficient-store unit runner is
  `rtl/scripts/Run-DF-Coefficient-Store-XSim.cmd`.
- The coefficient-store OOC synthesis runner is
  `rtl/scripts/Run-DF-Coefficient-Store-Vivado.cmd`.
- The DeepFilter-engine unit runner is
  `rtl/scripts/Run-DeepFilter-Engine-XSim.cmd`.
- The DeepFilter-engine OOC synthesis runner is
  `rtl/scripts/Run-DeepFilter-Engine-Vivado.cmd`.
- The combined routed-OOC runner is
  `rtl/scripts/Route-Accelerator-Top-Feature-Vivado.cmd`.
- The Sequential-v4 PE/memory-subsystem routed-OOC runner is
  `rtl/scripts/Run-Sequential-V4-PE-Memory-Subsystem-Vivado.cmd`.
- The complete PYNQ-Z1 block-design route-only implementation runner is
  `rtl/scripts/Run-Accelerator-Full-BD-Implementation-Vivado.cmd`; it rebuilds
  the validated BD, reruns global synthesis, executes
  `opt_design/place_design/phys_opt_design/route_design` plus a routed-design
  physical-optimization pass, applies timing/route/coverage/CDC/DRC/resource
  gates, and refuses to generate a bitstream.
- The corresponding full-design evidence is under
  `rtl/reports/accelerator_full_bd_implementation/`; on baseline `68335d7`,
  the 100 MHz final route has WNS `+0.160 ns`, guardbanded WHS `+0.007 ns`,
  raw physical hold margin `+0.057 ns`, 0 failing endpoints/routing errors/
  blocking DRC, and all tracked resources below 80%. The implementation
  applies 50 ps of hold uncertainty before placement/routing; this is not
  board evidence, and setup/congestion still need engineering margin work.
- The routed evidence is under
  `rtl/reports/sequential_v4_pe_memory_subsystem/`.
- Step-4 connected-top OOC evidence is under
  `rtl/reports/accelerator_top_step4/`; its negative post-synthesis slack is a
  recorded open timing item, not a 100 MHz sign-off.
- The pre-fix sparse-top baseline remains under
  `rtl/reports/accelerator_top_sparse/`; it records `-3.121 ns`
  post-synthesis and `-1.146 ns` post-route WNS.
- Current timing-closure evidence is under
  `rtl/reports/accelerator_top_sparse_timing/`; the existing functional bundle
  plus the seven-check barrier timing-cut harness pass. The combined top has
  `-0.005 ns` post-synthesis WNS and routed-OOC `+0.115 ns` WNS / `+0.016 ns`
  WHS, so the single-clock 100 MHz OOC setup and hold gates pass.
- The integration rationale and evidence boundary are recorded in
  `docs/memory/SPARSE_ACCELERATOR_TOP_INTEGRATION.md`.
- Coefficient-store standalone evidence is under
  `rtl/reports/df_coefficient_store/`; XSim and the 100 MHz OOC timing gate pass.
- DeepFilter-engine standalone evidence is under
  `rtl/reports/deepfilter_engine/`; its synthetic two-frame XSim and 100 MHz
  OOC timing gate pass.

## 6. Explicit exclusions

Do not compile any source under `archive/parameter_memory_ping_pong/` into the
production top.  Also exclude these legacy or future-only paths unless a later
review explicitly promotes them:

```text
rtl/leaf/ping_pong_weight_buffer.v
rtl/axi/axis_weight_loader.v
rtl/memory/memory_service_axil.v
rtl/memory/parameter_bram_bringup_top.v
rtl/memory/memory.v
rtl/memory/model_memory_v4_table.v
rtl/memory/memory_service.v
rtl/memory/sequential_recurrent_context_store.v
rtl/memory/sequential_v4_pe_memory_subsystem.v
rtl/pe_array/rtl/                    # working tree, not frozen baseline/v1
```

Do not use `glob rtl/**/*.v` for production integration.  That would silently
pull historical prototypes and bypass this manifest.

## 7. Retained v3 tooling and reference boundary

The v3 files are excluded from the production v4 RTL compile, but they are not
dead files and must not yet be deleted:

- `rtl/tools/generate_memory_v4.py` imports `generate_memory_v3.py` as its
  shared manifest validation, tensor packing, stage construction, readback,
  and checksum implementation.
- `rtl/tests/test_memory_v4_image.py` uses the frozen v3 image, layout, golden,
  generated tables, generator, and v3 test hash as a migration oracle.  It
  proves that v4 changed LUT placement without changing any weight lane,
  parameter field, ordering, signedness, or width.
- The historical parameter-BRAM bring-up test, runners, software, reports, and
  artifact manifest still reference the v3 image and generated RTL.  Keeping
  those inputs preserves reproducibility of the old BIT/HWH/LTX evidence,
  without making it compatible with the v4 production baseline.

A later v3-removal checkpoint must first extract the shared generator code into
a version-neutral library, replace the v4 migration oracle with an equally
strong raw-source reference, and decide whether to archive or retire the old
board-bring-up stack.  Until all three are complete, retain these nine tracked
v3 files:

```text
rtl/tools/generate_memory_v3.py
rtl/tests/test_memory_v3_image.py
rtl/memory/model_memory_v3_map.vh
rtl/memory/model_memory_v3_table.v
rtl/memory/model_memory_v3_readback_table.v
outputs/memory/2026-09-01/v3/parameters_v3.bin
outputs/memory/2026-09-01/v3/memory_layout_v3.json
outputs/memory/2026-09-01/v3/memory_golden_v3.json
outputs/memory/2026-09-01/v3/parameters_v3.sha256
```
