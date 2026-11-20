# Sequential v4 accelerator-top source manifest

Status: production integration allowlist

Frozen subsystem commit: `67b515757364fd9c9cabb404dcae303a45d9ea17`

The independent byte-level freeze for PE and memory is
`docs/frozen/PE_MEMORY_V4_FREEZE.md`.  It intentionally excludes
`rtl/control/fsm.v`, which may evolve against the frozen subsystem interface.

This manifest prevents a future accelerator build from collecting every RTL
file by wildcard.  Only the listed current sources, plus newly reviewed
top-specific glue, may enter the production compile.  Verify the frozen inputs
from repository root with:

```bash
sha256sum -c docs/memory/SHA256SUMS
sha256sum -c docs/frozen/PE_MEMORY_V4_SHA256SUMS
```

## 1. Include dependency

Add repository `rtl/` to the Verilog include search path.  The subsystem and
test/reference logic include:

```text
rtl/memory/model_memory_v4_map.vh
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
```

### Verilog-2001 sources

Compile in this deterministic order:

```text
rtl/memory/memory.v
rtl/memory/model_memory_v4_table.v
rtl/memory/memory_service.v
rtl/memory/sequential_recurrent_context_store.v
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
rtl/memory/sequential_v4_pe_memory_subsystem.v
rtl/integration/layernorm_mailbox_fsm_adapter.v
rtl/integration/sequential_feature_dispatcher.v
rtl/integration/sequential_df_coefficient_store.v
rtl/top/accelerator_top.v
```

`layernorm_mailbox` and `fsm` remain above/beside the frozen subsystem.  The
mailbox adapter, feature dispatcher, coefficient store, and `accelerator_top`
connect those blocks without changing the frozen PE/memory implementation.

## 3. Compile source identity

This table pins the complete current compile allowlist.  The FSM hash changes
when the controller is revised; the separate freeze manifest is authoritative
for the PE/memory bytes that must remain unchanged.

| Source | SHA-256 |
|---|---|
| `rtl/memory/memory.v` | `72435c38d85c7cbaaab25733c59912a52057b280e87c3b4d1b7ee52d7f5dab71` |
| `rtl/memory/model_memory_v4_map.vh` | `d7f5636965bb12182359960a1bcc887ad5a8075e9a82939c64f0b6a688a59c10` |
| `rtl/memory/model_memory_v4_table.v` | `2b7e4f924e6e0e2cf45ffd9f112d4ae8e89f2ae7ffb9e85f2c25b01c8d94b284` |
| `rtl/memory/memory_service.v` | `eda949ae825d12f6dcf0568ad12f152ac36fbe64fc44d7455089aaccf2e36b1a` |
| `rtl/memory/sequential_recurrent_context_store.v` | `9aa51e87b85bbfe2a9b5a1be5f699b391c54e861099c7e4b22fa6f1d000c8dbf` |
| `rtl/memory/sequential_pe_job_controller.v` | `46162d57793af8d5814e450868f2f8a4fc13589ea4a0236323e30a1ab925839e` |
| `rtl/pe_array/baseline/v1/rtl/arithmetic/pe_requant_lane.sv` | `f8ac9aa8914845d483655474bc9b35acc430ab751a5d197aab9803e3f73eb19d` |
| `rtl/pe_array/baseline/v1/rtl/arithmetic/pe_local_requant_bank_4lane.sv` | `c5faca719264b8d7ceea1ba891c24a5480feb49edd710f980b371c8bb0690973` |
| `rtl/pe_array/baseline/v1/rtl/pe/pe_hybrid_mac.sv` | `0e788eb30a518f260eec24eb07e9c753cdfc58ccafc6951a05759c2bf51d735d` |
| `rtl/pe_array/baseline/v1/rtl/nonlinear/pe_sigmoid_lut_255.v` | `438ee746e6ea94ae231e082077b19fcfb2418c278804b50f23c31306aa74bfe0` |
| `rtl/pe_array/baseline/v1/rtl/postprocess/pe_gate_postprocess.v` | `eb40765149f5efecd215c4e9aca0ba933a1227dc5c439494c805cf8f0d664b25` |
| `rtl/pe_array/baseline/v1/rtl/pe/pe_membrane_sequencer.v` | `f7b2a3cd211c293919fb21f10d4457748ab7a756c74692c6fbbba01dc0ee5b65` |
| `rtl/pe_array/baseline/v1/rtl/stream/pe_output_serializer.v` | `7c5c2c4543f7325110dcf52d5fc8ab58bf20b7d95eac10101fa62ed9f0399479` |
| `rtl/pe_array/baseline/v1/rtl/stream/pe_shared_requant_engine.v` | `562bb97a7adeb1cf41569b3a6e4ed0a942a33352c818d56efc31220ef79c7c53` |
| `rtl/pe_array/baseline/v1/rtl/index/pe_spike_decision.v` | `83ea62ff60913abc00cc7ece18e06805a85b519dcde72b37ef02d0e903813b66` |
| `rtl/pe_array/baseline/v1/rtl/index/pe_active_index_writer.v` | `799265e33f13057801defcf93faf19d2cba15269b79629f30ea52fa8575babf6` |
| `rtl/pe_array/baseline/v1/rtl/pe/pe_cdf_sequencer.v` | `59f58ea2bace9c1006fb00a899bebc9ae5c80c7b3d7c089894d972f4cd601dff` |
| `rtl/pe_array/baseline/v1/rtl/top/pe_array_datapath.v` | `bdde93915e380e910b6504cb8f9ec2439d8cd95fbd684513bd15af1426ed3954` |
| `rtl/memory/layernorm_mailbox.v` | `b32bbe6c7a4794f4cb8271533e4c491f515e62b7f85faea5f4c2f410ab658e0d` |
| `rtl/control/fsm.v` | `6f0c0cb2941a34619037d3578e4e373955f5480026d3b6f21923118ca298d54f` |
| `rtl/memory/sequential_v4_pe_memory_subsystem.v` | `772178329460fc53e5de0759a3aa7c61fea1ef18db04cbefd1d7800189ec2808` |
| `rtl/integration/layernorm_mailbox_fsm_adapter.v` | `5a5b26dc05e9459fe99cc14b05b8d4ec34e700b0a77743398921baacf386a27f` |
| `rtl/integration/sequential_feature_dispatcher.v` | `3d3894a550f9411da0cdb6fa8aac495f4eb832b9a1794631eb84be4fc1b7f364` |
| `rtl/integration/sequential_df_coefficient_store.v` | `0e8641f3c1d1c41b754849d8512dcc2c3a03d0efcc4f049f3d10835a0af7d770` |
| `rtl/top/accelerator_top.v` | `9471fa3c3fdd6ae40ee5fe9479142064fa30574316f3b37f5ca3579ea65d6bd5` |
| `rtl/memory/sequential_v4_pe_memory_subsystem_100mhz.xdc` | `94a2dfc35a987babd1aac954b8568c99c1e2adb6875907e932da29869dc87d34` |
| `rtl/top/accelerator_top_100mhz.xdc` | `80a989317087dfe3d19c5ff950450973ec0fe24543595598dae8c8760d33bda5` |

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
- The feature-dispatcher OOC synthesis runner is
  `rtl/scripts/Run-Accelerator-Top-Feature-Vivado.cmd`.
- The coefficient-store unit runner is
  `rtl/scripts/Run-DF-Coefficient-Store-XSim.cmd`.
- The coefficient-store OOC synthesis runner is
  `rtl/scripts/Run-DF-Coefficient-Store-Vivado.cmd`.
- The full implementation runner is
  `rtl/scripts/Run-Sequential-V4-PE-Memory-Subsystem-Vivado.cmd`.
- The routed evidence is under
  `rtl/reports/sequential_v4_pe_memory_subsystem/`.
- Step-4 connected-top OOC evidence is under
  `rtl/reports/accelerator_top_step4/`; its negative post-synthesis slack is a
  recorded open timing item, not a 100 MHz sign-off.
- Feature-dispatcher evidence is under
  `rtl/reports/accelerator_top_feature/`; dispatcher, mailbox adapter,
  coefficient-store, and top elaboration XSim pass, while the unchanged
  `-2.863 ns` post-synthesis WNS remains an open frozen-subsystem timing item.
- Coefficient-store standalone evidence is under
  `rtl/reports/df_coefficient_store/`; XSim and the 100 MHz OOC timing gate pass.

## 6. Explicit exclusions

Do not compile any source under `archive/parameter_memory_ping_pong/` into the
production top.  Also exclude these legacy or future-only paths unless a later
review explicitly promotes them:

```text
rtl/leaf/ping_pong_weight_buffer.v
rtl/axi/axis_weight_loader.v
rtl/memory/memory_service_axil.v
rtl/memory/parameter_bram_bringup_top.v
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
