# Sparse memory v1 manifest

Status: CP7 frozen isolated-Vivado evidence allowlist

This manifest is independent of `docs/memory/MANIFEST.md`. Existing
accelerator-top scripts must not consume it.

## Include roots

```text
sparse_memory_v1/imports/memory_v4
sparse_memory_v1/imports/pe_v1/rtl
```

## Imported SystemVerilog sources

```text
imports/pe_v1/rtl/arithmetic/pe_requant_lane.sv
imports/pe_v1/rtl/arithmetic/pe_local_requant_bank_4lane.sv
imports/pe_v1/rtl/pe/pe_hybrid_mac.sv
```

## Imported Verilog-2001 dense-baseline sources

```text
imports/memory_v4/memory/memory.v
imports/memory_v4/memory/model_memory_v4_table.v
imports/memory_v4/memory/memory_service.v
imports/memory_v4/memory/sequential_recurrent_context_store.v
imports/memory_v4/memory/sequential_pe_job_controller.v
imports/pe_v1/rtl/nonlinear/pe_sigmoid_lut_255.v
imports/pe_v1/rtl/postprocess/pe_gate_postprocess.v
imports/pe_v1/rtl/pe/pe_membrane_sequencer.v
imports/pe_v1/rtl/stream/pe_output_serializer.v
imports/pe_v1/rtl/stream/pe_shared_requant_engine.v
imports/pe_v1/rtl/index/pe_spike_decision.v
imports/pe_v1/rtl/index/pe_active_index_writer.v
imports/pe_v1/rtl/pe/pe_cdf_sequencer.v
imports/pe_v1/rtl/top/pe_array_datapath.v
imports/memory_v4/memory/sequential_v4_pe_memory_subsystem.v
```

The active sparse allowlist will be added checkpoint-by-checkpoint. Wildcards,
symlinks, and repository-external compile inputs are forbidden.

`rtl/sparse_recurrent_context_store_core_v1.v` is the uniquely named active
copy derived from the frozen context-store import.  Its request-edge list-read
issue stage adds one cycle of legal-response latency to cut the map/count cone;
the imported source above remains a byte-identical provenance snapshot and is
not an active sparse compile input.

## CP3 planner XSim sources

Compile these files in the listed order. No implicit source discovery is
permitted.

```text
rtl/sparse_recurrent_context_store_core_v1.v
rtl/sparse_stage_map_v1.sv
rtl/sparse_union_planner_v1.sv
rtl/sparse_recurrent_context_store_v1.sv
tb/tb_sparse_union_planner_v1.sv
```

## CP3 planner OOC sources

```text
rtl/sparse_stage_map_v1.sv
rtl/sparse_union_planner_v1.sv
constraints/sparse_union_planner_v1_100mhz.xdc
scripts/run_cp3_planner_ooc.tcl
```

## CP4 scatter-load XSim sources

Compile these files in the listed order with `rtl/` as the only include root.

```text
rtl/sparse_memory_dma_v1.v
rtl/sparse_memory_v4_table_v1.v
rtl/sparse_memory_service_v1.sv
tb/tb_sparse_memory_service_v1.sv
```

The service's only textual include is the isolated
`rtl/sparse_memory_v4_map_v1.vh`. No file in the existing `rtl/memory/` tree is
an input.

## CP5 connected subsystem XSim sources

Compile these project sources in the listed order. Use `rtl/` and
`imports/memory_v4/` as the only project include roots. The Vivado
`unisims_ver` simulation library is a toolchain library, not a project source.

```text
imports/pe_v1/rtl/arithmetic/pe_requant_lane.sv
imports/pe_v1/rtl/arithmetic/pe_local_requant_bank_4lane.sv
imports/pe_v1/rtl/pe/pe_hybrid_mac.sv
rtl/sparse_memory_dma_v1.v
rtl/sparse_memory_v4_table_v1.v
rtl/sparse_memory_service_v1.sv
rtl/sparse_stage_map_v1.sv
rtl/sparse_union_planner_v1.sv
rtl/sparse_recurrent_context_store_core_v1.v
rtl/sparse_recurrent_context_store_v1.sv
imports/memory_v4/memory/sequential_pe_job_controller.v
imports/pe_v1/rtl/nonlinear/pe_sigmoid_lut_255.v
imports/pe_v1/rtl/postprocess/pe_gate_postprocess.v
imports/pe_v1/rtl/pe/pe_membrane_sequencer.v
imports/pe_v1/rtl/stream/pe_output_serializer.v
imports/pe_v1/rtl/stream/pe_shared_requant_engine.v
imports/pe_v1/rtl/index/pe_spike_decision.v
imports/pe_v1/rtl/index/pe_active_index_writer.v
imports/pe_v1/rtl/pe/pe_cdf_sequencer.v
imports/pe_v1/rtl/top/pe_array_datapath.v
rtl/sequential_v4_sparse_memory_subsystem.sv
tb/tb_sequential_v4_sparse_memory_subsystem.sv
```

The runtime image is
`imports/fixtures/v4/parameters_v4.bin`. The connected regression compiles no
source or textual include outside `sparse_memory_v1/`.

## CP7 registered-fault connected XSim sources

CP7 reuses the CP6 connected source order above and adds no compile input.
`scripts/run_cp7_registered_fault_xsim.ps1` runs entirely from a Windows-local
temporary directory because Xilinx batch launchers cannot use a UNC current
directory.  It hash-pins the 23 sources, two include files, v4 image, and runner
before simulation and verifies that each remains stable afterward.

Published evidence is restricted to:

```text
reports/cp7/cp7_registered_fault_xsim_summary.txt
reports/cp7/cp7_registered_fault_xsim_inputs.txt
reports/cp7/cp7_registered_fault_xvlog_console.txt
reports/cp7/cp7_registered_fault_xelab_console.txt
reports/cp7/cp7_registered_fault_xsim_console.txt
reports/cp7/cp7_registered_fault_xsim.log
reports/cp7/summary.md
```

CP6 evidence remains historical after CP7 changes the active subsystem and
testbench.  Its verifier continues to hash-check every input except the two
explicitly superseded paths; CP7 independently requires those current paths
and every other active input to match its new manifest.

## CP6 service XSim sources

Compile these files in the listed order, with `rtl/` as the only include
root.  The pinned v4 image is copied into a run-specific directory below
`build/`; it is data, not a compile input.

```text
rtl/sparse_memory_dma_v1.v
rtl/sparse_memory_v4_table_v1.v
rtl/sparse_memory_service_v1.sv
tb/tb_sparse_memory_service_v1.sv
```

Required non-source inputs:

```text
rtl/sparse_memory_v4_map_v1.vh
imports/fixtures/v4/parameters_v4.bin
scripts/run_cp6_service_xsim.ps1
```

## CP6 connected XSim sources

The CP5 connected regression is rerun after the CP6 timing cuts.  Compile the
following files in order with `rtl/` and `imports/memory_v4/` as the only
project include roots.  `unisims_ver` remains a Vivado tool library rather
than a project source.

```text
tb/cp6_xsim_glbl.v
imports/pe_v1/rtl/arithmetic/pe_requant_lane.sv
imports/pe_v1/rtl/arithmetic/pe_local_requant_bank_4lane.sv
imports/pe_v1/rtl/pe/pe_hybrid_mac.sv
rtl/sparse_memory_dma_v1.v
rtl/sparse_memory_v4_table_v1.v
rtl/sparse_memory_service_v1.sv
rtl/sparse_stage_map_v1.sv
rtl/sparse_union_planner_v1.sv
rtl/sparse_recurrent_context_store_core_v1.v
rtl/sparse_recurrent_context_store_v1.sv
imports/memory_v4/memory/sequential_pe_job_controller.v
imports/pe_v1/rtl/nonlinear/pe_sigmoid_lut_255.v
imports/pe_v1/rtl/postprocess/pe_gate_postprocess.v
imports/pe_v1/rtl/pe/pe_membrane_sequencer.v
imports/pe_v1/rtl/stream/pe_output_serializer.v
imports/pe_v1/rtl/stream/pe_shared_requant_engine.v
imports/pe_v1/rtl/index/pe_spike_decision.v
imports/pe_v1/rtl/index/pe_active_index_writer.v
imports/pe_v1/rtl/pe/pe_cdf_sequencer.v
imports/pe_v1/rtl/top/pe_array_datapath.v
rtl/sequential_v4_sparse_memory_subsystem.sv
tb/tb_sequential_v4_sparse_memory_subsystem.sv
```

Required non-source inputs:

```text
rtl/sparse_memory_v4_map_v1.vh
imports/memory_v4/memory/model_memory_v4_map.vh
imports/fixtures/v4/parameters_v4.bin
scripts/run_cp6_cp5_xsim.ps1
```

## CP6 service OOC sources

```text
rtl/sparse_memory_dma_v1.v
rtl/sparse_memory_v4_table_v1.v
rtl/sparse_memory_service_v1.sv
rtl/sparse_memory_v4_map_v1.vh
constraints/sparse_memory_service_v1_cp6_100mhz.xdc
scripts/run_cp6_service_ooc.tcl
scripts/run_cp6_vivado_ooc.ps1
```

## CP6 isolated-subsystem route sources

The compile order is controlled by `scripts/run_cp6_subsystem_route.tcl`.
Its complete project-source allowlist is:

```text
imports/pe_v1/rtl/arithmetic/pe_requant_lane.sv
imports/pe_v1/rtl/arithmetic/pe_local_requant_bank_4lane.sv
imports/pe_v1/rtl/pe/pe_hybrid_mac.sv
rtl/sparse_memory_dma_v1.v
rtl/sparse_memory_v4_table_v1.v
rtl/sparse_memory_service_v1.sv
rtl/sparse_stage_map_v1.sv
rtl/sparse_union_planner_v1.sv
rtl/sparse_recurrent_context_store_core_v1.v
rtl/sparse_recurrent_context_store_v1.sv
imports/memory_v4/memory/sequential_pe_job_controller.v
imports/pe_v1/rtl/nonlinear/pe_sigmoid_lut_255.v
imports/pe_v1/rtl/postprocess/pe_gate_postprocess.v
imports/pe_v1/rtl/pe/pe_membrane_sequencer.v
imports/pe_v1/rtl/stream/pe_output_serializer.v
imports/pe_v1/rtl/stream/pe_shared_requant_engine.v
imports/pe_v1/rtl/index/pe_spike_decision.v
imports/pe_v1/rtl/index/pe_active_index_writer.v
imports/pe_v1/rtl/pe/pe_cdf_sequencer.v
imports/pe_v1/rtl/top/pe_array_datapath.v
rtl/sequential_v4_sparse_memory_subsystem.sv
rtl/sparse_memory_validation_top.sv
rtl/sparse_memory_v4_map_v1.vh
imports/memory_v4/memory/model_memory_v4_map.vh
constraints/sparse_memory_validation_top_cp6_100mhz.xdc
scripts/run_cp6_subsystem_route.tcl
scripts/run_cp6_vivado_ooc.ps1
```

The runner also hash-pins and validates the unchanged CP3 planner reports
before reusing that planner-only OOC result.  All temporary projects,
journals, simulator databases, and run-local reports must remain under
`build/`.  Only a fully passing run may publish fixed evidence names under
`reports/cp6/`.  The subsystem implementation sequence is fixed to default
optimization, Explore placement, default pre-route physical optimization, and
Explore routing; all final timing and route gates are evaluated afterward.
