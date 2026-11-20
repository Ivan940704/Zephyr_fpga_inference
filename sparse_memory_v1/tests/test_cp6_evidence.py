"""Fail-closed host checks for the published CP6 evidence bundle."""

from __future__ import annotations

import hashlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPORTS = ROOT / "reports" / "cp6"

# CP6 remains historical evidence after the CP7 registered-fault cut.  These
# two inputs are intentionally superseded; CP7 has its own current-source hash
# gate.  Every other CP6 input must still match the published bundle.
SUPERSEDED_BY_CP7 = {
    "rtl/sparse_memory_service_v1.sv",
    "rtl/sequential_v4_sparse_memory_subsystem.sv",
    "tb/tb_sequential_v4_sparse_memory_subsystem.sv",
}

SERVICE_XSIM_INPUTS = (
    ("source", "rtl/sparse_memory_dma_v1.v"),
    ("source", "rtl/sparse_memory_v4_table_v1.v"),
    ("source", "rtl/sparse_memory_service_v1.sv"),
    ("source", "tb/tb_sparse_memory_service_v1.sv"),
    ("include_file", "rtl/sparse_memory_v4_map_v1.vh"),
    ("data", "imports/fixtures/v4/parameters_v4.bin"),
)

CONNECTED_XSIM_INPUTS = (
    ("source", "tb/cp6_xsim_glbl.v"),
    ("source", "imports/pe_v1/rtl/arithmetic/pe_requant_lane.sv"),
    ("source", "imports/pe_v1/rtl/arithmetic/pe_local_requant_bank_4lane.sv"),
    ("source", "imports/pe_v1/rtl/pe/pe_hybrid_mac.sv"),
    ("source", "rtl/sparse_memory_dma_v1.v"),
    ("source", "rtl/sparse_memory_v4_table_v1.v"),
    ("source", "rtl/sparse_memory_service_v1.sv"),
    ("source", "rtl/sparse_stage_map_v1.sv"),
    ("source", "rtl/sparse_union_planner_v1.sv"),
    ("source", "rtl/sparse_recurrent_context_store_core_v1.v"),
    ("source", "rtl/sparse_recurrent_context_store_v1.sv"),
    ("source", "imports/memory_v4/memory/sequential_pe_job_controller.v"),
    ("source", "imports/pe_v1/rtl/nonlinear/pe_sigmoid_lut_255.v"),
    ("source", "imports/pe_v1/rtl/postprocess/pe_gate_postprocess.v"),
    ("source", "imports/pe_v1/rtl/pe/pe_membrane_sequencer.v"),
    ("source", "imports/pe_v1/rtl/stream/pe_output_serializer.v"),
    ("source", "imports/pe_v1/rtl/stream/pe_shared_requant_engine.v"),
    ("source", "imports/pe_v1/rtl/index/pe_spike_decision.v"),
    ("source", "imports/pe_v1/rtl/index/pe_active_index_writer.v"),
    ("source", "imports/pe_v1/rtl/pe/pe_cdf_sequencer.v"),
    ("source", "imports/pe_v1/rtl/top/pe_array_datapath.v"),
    ("source", "rtl/sequential_v4_sparse_memory_subsystem.sv"),
    ("source", "tb/tb_sequential_v4_sparse_memory_subsystem.sv"),
    ("include_file", "rtl/sparse_memory_v4_map_v1.vh"),
    ("include_file", "imports/memory_v4/memory/model_memory_v4_map.vh"),
    ("data", "imports/fixtures/v4/parameters_v4.bin"),
)

SERVICE_OOC_DECLARATIONS = (
    ("include_dir", "rtl"),
    ("verilog", "rtl/sparse_memory_dma_v1.v"),
    ("verilog", "rtl/sparse_memory_v4_table_v1.v"),
    ("systemverilog", "rtl/sparse_memory_service_v1.sv"),
    ("include_file", "rtl/sparse_memory_v4_map_v1.vh"),
    ("xdc", "constraints/sparse_memory_service_v1_cp6_100mhz.xdc"),
    ("runner", "scripts/run_cp6_service_ooc.tcl"),
)

SUBSYSTEM_VERILOG = (
    "rtl/sparse_memory_dma_v1.v",
    "rtl/sparse_memory_v4_table_v1.v",
    "rtl/sparse_recurrent_context_store_core_v1.v",
    "imports/memory_v4/memory/sequential_pe_job_controller.v",
    "imports/pe_v1/rtl/nonlinear/pe_sigmoid_lut_255.v",
    "imports/pe_v1/rtl/postprocess/pe_gate_postprocess.v",
    "imports/pe_v1/rtl/pe/pe_membrane_sequencer.v",
    "imports/pe_v1/rtl/stream/pe_output_serializer.v",
    "imports/pe_v1/rtl/stream/pe_shared_requant_engine.v",
    "imports/pe_v1/rtl/index/pe_spike_decision.v",
    "imports/pe_v1/rtl/index/pe_active_index_writer.v",
    "imports/pe_v1/rtl/pe/pe_cdf_sequencer.v",
    "imports/pe_v1/rtl/top/pe_array_datapath.v",
)
SUBSYSTEM_SYSTEMVERILOG = (
    "imports/pe_v1/rtl/arithmetic/pe_requant_lane.sv",
    "imports/pe_v1/rtl/arithmetic/pe_local_requant_bank_4lane.sv",
    "imports/pe_v1/rtl/pe/pe_hybrid_mac.sv",
    "rtl/sparse_memory_service_v1.sv",
    "rtl/sparse_stage_map_v1.sv",
    "rtl/sparse_union_planner_v1.sv",
    "rtl/sparse_recurrent_context_store_v1.sv",
    "rtl/sequential_v4_sparse_memory_subsystem.sv",
    "rtl/sparse_memory_validation_top.sv",
)
SUBSYSTEM_INCLUDES = (
    "rtl/sparse_memory_v4_map_v1.vh",
    "imports/memory_v4/memory/model_memory_v4_map.vh",
)
SUBSYSTEM_CP3_EVIDENCE = (
    "reports/cp3/planner_ooc_summary.txt",
    "reports/cp3/planner_timing_summary.rpt",
    "reports/cp3/planner_route_status.rpt",
    "reports/cp3/planner_utilization.rpt",
)
SUBSYSTEM_OOC_DECLARATIONS = (
    (("include_dir", "rtl"), ("include_dir", "imports/memory_v4"))
    + tuple(("verilog", path) for path in SUBSYSTEM_VERILOG)
    + tuple(("include_file", path) for path in SUBSYSTEM_INCLUDES)
    + tuple(("systemverilog", path) for path in SUBSYSTEM_SYSTEMVERILOG)
    + (("xdc", "constraints/sparse_memory_validation_top_cp6_100mhz.xdc"),)
    + (("runner", "scripts/run_cp6_subsystem_route.tcl"),)
    + tuple(("reused_cp3_evidence", path) for path in SUBSYSTEM_CP3_EVIDENCE)
)

CP6_REPORT_FILES = {
    "cp6_service_xsim_summary.txt",
    "cp6_service_xsim_resolved_inputs.txt",
    "cp6_service_xvlog_console.txt",
    "cp6_service_xelab_console.txt",
    "cp6_service_xsim_console.txt",
    "cp6_service_xsim.log",
    "cp6_cp5_xsim_summary.txt",
    "cp6_cp5_xsim_resolved_inputs.txt",
    "cp6_cp5_xvlog_console.txt",
    "cp6_cp5_xelab_console.txt",
    "cp6_cp5_xsim_console.txt",
    "cp6_cp5_xsim.log",
    "cp6_service_ooc_summary.txt",
    "cp6_service_ooc_launcher_summary.txt",
    "cp6_service_ooc_resolved_inputs.txt",
    "cp6_service_ooc_vivado_console.txt",
    "cp6_service_utilization_post_synth.rpt",
    "cp6_service_timing_post_synth.rpt",
    "cp6_service_check_timing_post_synth.rpt",
    "cp6_service_utilization_post_route.rpt",
    "cp6_service_timing_post_route.rpt",
    "cp6_service_setup_paths_post_route.rpt",
    "cp6_service_hold_paths_post_route.rpt",
    "cp6_service_check_timing_post_route.rpt",
    "cp6_service_route_status_post_route.rpt",
    "cp6_subsystem_ooc_summary.txt",
    "cp6_subsystem_ooc_launcher_summary.txt",
    "cp6_subsystem_ooc_resolved_inputs.txt",
    "cp6_subsystem_ooc_vivado_console.txt",
    "cp6_subsystem_utilization_hierarchical_post_synth.rpt",
    "cp6_subsystem_utilization_post_synth.rpt",
    "cp6_subsystem_timing_post_synth.rpt",
    "cp6_subsystem_check_timing_post_synth.rpt",
    "cp6_subsystem_utilization_hierarchical_post_route.rpt",
    "cp6_subsystem_utilization_post_route.rpt",
    "cp6_subsystem_timing_post_route.rpt",
    "cp6_subsystem_setup_paths_post_route.rpt",
    "cp6_subsystem_hold_paths_post_route.rpt",
    "cp6_subsystem_check_timing_post_route.rpt",
    "cp6_subsystem_route_status_post_route.rpt",
    "cp6_subsystem_clock_utilization_post_route.rpt",
}


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _summary(name: str) -> dict[str, str]:
    path = REPORTS / name
    assert path.is_file(), f"missing CP6 evidence: {path}"
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8-sig").splitlines():
        if not raw:
            continue
        key, separator, value = raw.partition("=")
        assert separator, f"malformed evidence line in {path.name}: {raw!r}"
        assert key not in values, f"duplicate evidence key in {path.name}: {key}"
        values[key] = value
    return values


def _assert_pass(values: dict[str, str]) -> None:
    assert values["checkpoint"] == "CP6"
    assert values["status"] == "PASS"
    assert values["gate_pass"] == "1"


def _local_path(recorded_path: str) -> Path:
    normalized = recorded_path.replace("\\", "/")
    marker = "/sparse_memory_v1/"
    assert marker in normalized, f"recorded input escaped sparse root: {recorded_path}"
    relative = normalized.split(marker, 1)[1]
    target = ROOT / relative
    target.resolve().relative_to(ROOT.resolve())
    return target


def _relative(recorded_path: str) -> str:
    return _local_path(recorded_path).relative_to(ROOT).as_posix()


def _verify_xsim_resolved_inputs(
    name: str,
    expected_includes: tuple[str, ...],
    expected_records: tuple[tuple[str, str], ...],
) -> dict[str, str]:
    path = REPORTS / name
    assert path.is_file()
    metadata: dict[str, str] = {}
    includes: list[str] = []
    records: list[tuple[str, str, str]] = []
    for raw in path.read_text(encoding="utf-8-sig").splitlines():
        if not raw:
            continue
        pieces = raw.split("|", 2)
        if len(pieces) == 3:
            kind, digest, recorded = pieces
            assert kind in {"source", "include_file", "data", "runner"}
            target = _local_path(recorded)
            assert target.is_file()
            relative = _relative(recorded)
            if relative not in SUPERSEDED_BY_CP7:
                assert _sha256(target) == digest
            records.append((kind, digest, relative))
            continue
        key, separator, value = raw.partition("=")
        assert separator, f"malformed resolved-input line: {raw!r}"
        if key == "include_dir":
            assert _local_path(value).is_dir()
            includes.append(_relative(value))
        else:
            assert key not in metadata, f"duplicate metadata key: {key}"
            metadata[key] = value

    assert metadata["checkpoint"] == "CP6"
    assert tuple(includes) == expected_includes
    assert tuple((kind, relative) for kind, _, relative in records) == expected_records
    material = [*(f"include_dir|{path}" for path in includes)]
    material.extend(
        f"{kind}|{digest}|{relative}" for kind, digest, relative in records
    )
    aggregate = hashlib.sha256(("\n".join(material) + "\n").encode()).hexdigest()
    assert metadata["input_set_sha256"] == aggregate
    return metadata


def _verify_ooc_resolved_inputs(
    name: str,
    expected_declarations: tuple[tuple[str, str], ...],
    expected_hash_paths: tuple[str, ...],
) -> dict[str, str]:
    path = REPORTS / name
    assert path.is_file()
    metadata: dict[str, str] = {}
    declarations: list[tuple[str, str]] = []
    hashes: list[tuple[str, str]] = []
    path_keys = {
        "include_dir",
        "verilog",
        "systemverilog",
        "include_file",
        "xdc",
        "runner",
        "reused_cp3_evidence",
    }
    for raw in path.read_text(encoding="utf-8-sig").splitlines():
        if not raw:
            continue
        if raw.startswith("sha256="):
            digest, recorded = raw.removeprefix("sha256=").split("|", 1)
            target = _local_path(recorded)
            assert target.is_file()
            relative = _relative(recorded)
            if relative not in SUPERSEDED_BY_CP7:
                assert _sha256(target) == digest
            hashes.append((digest, relative))
            continue
        key, separator, value = raw.partition("=")
        assert separator, f"malformed resolved-input line: {raw!r}"
        if key in path_keys:
            target = _local_path(value)
            assert target.is_dir() if key == "include_dir" else target.is_file()
            declarations.append((key, _relative(value)))
        else:
            assert key not in metadata, f"duplicate metadata key: {key}"
            metadata[key] = value

    assert metadata["checkpoint"] == "CP6"
    assert tuple(declarations) == expected_declarations
    assert tuple(relative for _, relative in hashes) == expected_hash_paths
    return metadata


def _verify_xsim(
    summary_name: str,
    resolved_name: str,
    runner_relative: str,
    expected_includes: tuple[str, ...],
    expected_records: tuple[tuple[str, str], ...],
    expected: dict[str, str],
) -> None:
    values = _summary(summary_name)
    _assert_pass(values)
    assert values["evidence_type"] == "Vivado_2018.3_XSim"
    assert values["accelerator_top_included"] == "0"
    assert values["source_hash_stable"] == "1"
    assert values["runner_hash_stable"] == "1"
    assert values["xvlog_exit"] == "0"
    assert values["xelab_exit"] == "0"
    assert values["xsim_exit"] == "0"
    assert values["pass_signature_count"] == "1"
    assert values["fail_or_fatal_signature_count"] == "0"
    for key, wanted in expected.items():
        assert values[key] == wanted

    log_name = summary_name.removesuffix("_summary.txt") + ".log"
    assert _sha256(REPORTS / log_name) == values["xsim_log_sha256"]
    assert values["runner_sha256"] == _sha256(ROOT / runner_relative)
    assert int(values["project_source_count"]) == sum(
        kind == "source" for kind, _ in expected_records
    )
    metadata = _verify_xsim_resolved_inputs(
        resolved_name, expected_includes, expected_records
    )
    assert metadata["run_id"] == values["run_id"]
    assert metadata["input_set_sha256"] == values["resolved_inputs_sha256"]


def _verify_ooc(
    flow: str,
    expected_scope: str,
    expected_type: str,
    expected_top: str,
    expected_count: int,
    expected_declarations: tuple[tuple[str, str], ...],
    expected_hash_paths: tuple[str, ...],
) -> dict[str, str]:
    summary_name = f"cp6_{flow}_ooc_summary.txt"
    values = _summary(summary_name)
    _assert_pass(values)
    assert values["evidence_type"] == expected_type
    assert values["design_scope"] == expected_scope
    assert values["top"] == expected_top
    assert values["accelerator_top_included"] == "0"
    assert values["bitstream_generated"] == "0"
    assert values["vivado_version"] == "2018.3"
    assert values["part"] == "xc7z020clg400-1"
    assert values["target_frequency_mhz"] == "100"
    assert float(values["target_period_ns"]) == 10.0
    assert float(values["actual_period_ns"]) == 10.0
    if flow == "subsystem":
        assert (
            values["implementation_strategy"]
            == "DefaultOpt_ExplorePlace_DefaultPhysOpt_ExploreRoute"
        )
    assert float(values["post_route_wns_ns"]) >= 0.0
    assert float(values["post_route_whs_ns"]) >= 0.0
    for key in (
        "unrouted_nets",
        "routing_error_nets",
        "incomplete_routable_nets",
        "no_clock_pins",
        "constant_clock_pins",
        "unconstrained_internal_endpoints",
        "unconstrained_due_to_constant_clock",
    ):
        assert values[key] == "0"
    assert int(values["routable_nets"]) > 0
    assert values["fully_routed_nets"] == values["routable_nets"]
    assert values["resources_below_80_percent"] == "1"
    assert values["source_hash_stable"] == "1"
    assert values["runner_hash_stable"] == "1"
    assert values["guarded_design_file_count"] == str(expected_count)

    lut_key = "slice_luts" if flow == "service" else "slice_luts_including_harness"
    ff_key = (
        "slice_registers"
        if flow == "service"
        else "slice_registers_including_harness"
    )
    assert int(values[lut_key]) < 42_560
    assert int(values[ff_key]) < 85_120
    assert float(values["bram36_equivalent"]) < 112.0
    assert int(values["dsp48_primitives"]) < 176

    metadata = _verify_ooc_resolved_inputs(
        f"cp6_{flow}_ooc_resolved_inputs.txt",
        expected_declarations,
        expected_hash_paths,
    )
    assert metadata["checkpoint"] == "CP6"

    launcher = _summary(f"cp6_{flow}_ooc_launcher_summary.txt")
    _assert_pass(launcher)
    assert launcher["flow"] == flow
    assert launcher["inner_run_id"] == values["run_id"]
    assert launcher["native_exit"] == "0"
    assert launcher["pass_signature_count"] == "1"
    assert launcher["failure_signature_count"] == "0"
    assert launcher["tcl_hash_stable"] == "1"
    assert launcher["launcher_hash_stable"] == "1"
    assert launcher["failure_detail"] == "none"
    assert launcher["flow_summary_sha256"] == _sha256(REPORTS / summary_name)
    assert launcher["console_sha256"] == _sha256(
        REPORTS / f"cp6_{flow}_ooc_vivado_console.txt"
    )
    assert launcher["launcher_sha256"] == _sha256(
        ROOT / "scripts" / "run_cp6_vivado_ooc.ps1"
    )
    assert launcher["tcl_sha256"] == _sha256(
        ROOT / "scripts" / f"run_cp6_{flow}_ooc.tcl"
        if flow == "service"
        else ROOT / "scripts" / "run_cp6_subsystem_route.tcl"
    )
    assert values["runner_sha256"] == launcher["tcl_sha256"]
    return values


def test_cp6_service_xsim_evidence_is_current() -> None:
    _verify_xsim(
        "cp6_service_xsim_summary.txt",
        "cp6_service_xsim_resolved_inputs.txt",
        "scripts/run_cp6_service_xsim.ps1",
        ("rtl",),
        SERVICE_XSIM_INPUTS,
        {"project_source_count": "4", "checks": "86053"},
    )


def test_cp6_connected_xsim_evidence_is_current() -> None:
    _verify_xsim(
        "cp6_cp5_xsim_summary.txt",
        "cp6_cp5_xsim_resolved_inputs.txt",
        "scripts/run_cp6_cp5_xsim.ps1",
        ("rtl", "imports/memory_v4"),
        CONNECTED_XSIM_INPUTS,
        {
            "project_source_count": "23",
            "checks": "12446067",
            "dense_bytes": "2101088",
            "sparse_bytes": "1052208",
        },
    )


def test_cp6_service_ooc_evidence_passes_all_gates() -> None:
    declarations = SERVICE_OOC_DECLARATIONS
    hash_paths = tuple(path for kind, path in declarations if kind != "include_dir")
    values = _verify_ooc(
        "service",
        "sparse_memory_service_v1_only",
        "Vivado_OOC_synthesis_place_route",
        "sparse_memory_service_v1",
        5,
        declarations,
        hash_paths,
    )
    assert values["service_resources_preserved"] == "1"
    assert values["ramb36e1_primitives"] == "64"
    assert values["ramb18e1_primitives"] == "0"
    assert values["dsp48_primitives"] == "4"


def test_cp6_subsystem_route_evidence_passes_all_gates() -> None:
    hash_paths = (
        SUBSYSTEM_VERILOG
        + SUBSYSTEM_SYSTEMVERILOG
        + SUBSYSTEM_INCLUDES
        + ("constraints/sparse_memory_validation_top_cp6_100mhz.xdc",)
        + SUBSYSTEM_CP3_EVIDENCE
        + ("scripts/run_cp6_subsystem_route.tcl",)
    )
    values = _verify_ooc(
        "subsystem",
        "validation_harness_plus_sequential_v4_sparse_memory_subsystem",
        "Vivado_isolated_subsystem_OOC_synthesis_place_route",
        "sparse_memory_validation_top",
        25,
        SUBSYSTEM_OOC_DECLARATIONS,
        hash_paths,
    )
    assert values["core_hierarchy"] == "u_sparse_subsystem"
    assert values["core_resources_preserved"] == "1"
    assert int(values["core_ramb36e1_primitives"]) >= 64
    assert values["planner_ooc_evidence"] == "reused_unchanged_CP3"
    assert values["planner_ooc_post_route_wns_ns"] == "2.154"
    assert values["planner_ooc_bram_primitives"] == "0"
    assert values["planner_ooc_dsp_primitives"] == "0"
    assert values["planner_ooc_unrouted_nets"] == "0"
    assert values["planner_ooc_routing_error_nets"] == "0"
    assert values["planner_ooc_no_clock_pins"] == "0"
    assert values["planner_ooc_constant_clock_pins"] == "0"
    assert values["planner_ooc_unconstrained_internal_endpoints"] == "0"
    assert values["planner_ooc_unconstrained_due_to_constant_clock"] == "0"
    assert values["planner_ooc_evidence_hash_stable"] == "1"
    assert values["planner_ooc_reuse_gate_pass"] == "1"
    for field, name in (
        ("planner_ooc_summary_sha256", "planner_ooc_summary.txt"),
        ("planner_ooc_timing_sha256", "planner_timing_summary.rpt"),
        ("planner_ooc_route_sha256", "planner_route_status.rpt"),
        ("planner_ooc_utilization_sha256", "planner_utilization.rpt"),
    ):
        assert values[field] == _sha256(ROOT / "reports" / "cp3" / name)


def test_cp6_report_bundle_is_exact() -> None:
    entries = tuple(REPORTS.iterdir())
    assert {path.name for path in entries} == CP6_REPORT_FILES
    assert all(path.is_file() and not path.is_symlink() for path in entries)
