import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "rtl" / "scripts"
REPORTS = ROOT / "rtl" / "reports" / "accelerator_full_bd_implementation"


def _key_values(path):
    values = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
    return values


def test_full_implementation_tcl_is_route_only_and_fail_closed():
    flow = (SCRIPTS / "implement_accelerator_full_bd.tcl").read_text(
        encoding="utf-8"
    )

    opt_step = "\n    opt_design\n"
    route_step = "\n    route_design -directive Explore\n"
    place_match = re.search(
        r"(?m)^\s+place_design -directive Explore$", flow
    )
    assert place_match is not None
    physopt_positions = [
        match.start()
        for match in re.finditer(
            r"\n\s+phys_opt_design -directive AggressiveExplore\n", flow
        )
    ]
    assert len(physopt_positions) == 2
    first_physopt, second_physopt = physopt_positions
    route = flow.index(route_step)
    positions = [
        flow.index(opt_step),
        place_match.start(),
        first_physopt,
        route,
        second_physopt,
    ]
    assert positions == sorted(positions)
    assert "Vivado 2018.3 automatically selects post-route mode" in flow
    assert "route_setup_wns_before_post_route_physopt_ns" in flow
    guardband_step = "set_clock_uncertainty -hold $hold_guardband_ns $target_clock"
    assert "set hold_guardband_ns 0.050" in flow
    assert "set setup_margin_target_ns 0.250" in flow
    assert "set setup_default_uncertainty_ns 0.154" in flow
    assert "setup_implementation_uncertainty_ns" in flow
    setup_guardband_step = (
        "set_clock_uncertainty -setup $setup_implementation_uncertainty_ns"
    )
    setup_restore_step = "set_clock_uncertainty -setup $setup_default_uncertainty_ns"
    assert flow.index(setup_guardband_step) < route
    assert flow.index(setup_restore_step) > second_physopt
    assert flow.index(guardband_step) < route
    assert "hold_raw_physical_margin_ns" in flow

    for forbidden_command in (
        "write_bitstream",
        "write_hw_platform",
        "export_hardware",
    ):
        assert re.search(
            rf"(?m)^\s*{forbidden_command}\s", flow
        ) is None, forbidden_command

    for required_report in (
        "report_utilization",
        "report_timing_summary",
        "check_timing",
        "report_clocks",
        "report_clock_utilization",
        "report_clock_interaction",
        "report_bus_skew",
        "report_cdc",
        "report_route_status",
        "report_design_analysis",
        "report_drc",
        "report_methodology",
        "report_high_fanout_nets",
    ):
        assert required_report in flow

    for gate in (
        "$setup_met",
        "$setup_engineering_margin_met",
        "$hold_met",
        "$hold_guardband_met",
        "$resources_below_limit",
        "$route_error_free",
        "$no_unconstrained_internal",
        "$no_clockless_registers",
        "$no_timing_loops",
        "$no_latch_loops",
        "$cdc_safe",
        "$blocking_drc_zero",
    ):
        assert gate in flow
    assert "ACCELERATOR_FULL_IMPLEMENTATION_GATE_FAIL" in flow
    assert 'puts $metrics "write_bitstream_invoked=NO"' in flow
    assert "ACCELERATOR_FULL_IMPLEMENTATION_ROUTE_COMPLETE" in flow


def test_full_implementation_runner_rebuilds_and_rejects_bitstreams():
    runner = (
        SCRIPTS / "Run-Accelerator-Full-BD-Implementation-Vivado.cmd"
    ).read_text(encoding="utf-8")

    calls = (
        "create_accelerator_full_bd.tcl",
        "synth_accelerator_full_bd.tcl",
        "implement_accelerator_full_bd.tcl",
    )
    positions = [runner.index(f'-source "rtl\\scripts\\{name}"') for name in calls]
    assert positions == sorted(positions)
    assert "ZEPHYR_DESIGN_REVISION" in runner
    assert "WORKTREE_UNSPECIFIED" in runner
    assert "1cb0724908b3eb1329977a6689785859d007214a" not in runner
    assert "tb_accelerator_profiling_counters.v" in runner
    assert "PASS tb_accelerator_profiling_counters" in runner
    assert 'for /r "%WORK_ROOT%" %%F in (*.bit)' in runner
    assert "full_gate_pass=1" in runner
    assert "hold_guardband_met=1" in runner
    assert "resources_below_limit=1" in runner
    assert "ZEPHYR_INCREMENTAL_REFERENCE" in runner
    assert "write_bitstream_requested=NO" in runner
    assert "post_route_phys_opt_design_requested=YES" in runner
    assert "ACCELERATOR_FULL_IMPLEMENTATION_ALL_PASS" in runner
    assert 'findstr /b /l /c:"%%~M"' in runner
    assert "Vivado Tcl writes LF-only text" in runner
    assert 'findstr /x /c:"%%~M"' not in runner


def test_preimplementation_boundary_remains_separate():
    preimplementation = (
        SCRIPTS / "Run-Accelerator-Full-BD-Preimplementation-Vivado.cmd"
    ).read_text(encoding="utf-8")
    assert "opt_design_requested=NO" in preimplementation
    assert "place_design_requested=NO" in preimplementation
    assert "route_design_requested=NO" in preimplementation
    assert "write_bitstream_requested=NO" in preimplementation


def test_soft_reset_only_resets_quiescent_custom_datapath():
    flow = (SCRIPTS / "create_accelerator_full_bd.tcl").read_text(
        encoding="utf-8"
    )
    control_reset = re.search(
        r"connect_bd_net \$control_resetn \\\n(.*?)"
        r"\n    connect_bd_net \$data_resetn",
        flow,
        re.DOTALL,
    )
    data_reset = re.search(
        r"connect_bd_net \$data_resetn \\\n(.*?)"
        r"\n    foreach hp_index",
        flow,
        re.DOTALL,
    )
    assert control_reset is not None
    assert data_reset is not None
    for infrastructure_pin in (
        "$mailbox_bram/s_axi_aresetn",
        "$io_dma/axi_resetn",
        "$spectrum_dma/axi_resetn",
    ):
        assert infrastructure_pin in control_reset.group(1)
        assert infrastructure_pin not in data_reset.group(1)
    assert "$accel/accelerator_aresetn" in data_reset.group(1)
    hp_reset = re.search(
        r"foreach hp_index \{0 1 2 3\} \{\n"
        r"        connect_bd_net \$(\w+resetn) \\\n"
        r"            \[get_bd_pins \$hp_ic",
        flow,
    )
    assert hp_reset is not None
    assert hp_reset.group(1) == "control_resetn"
    assert "data_rst->accelerator_only" in flow
    assert "soft_reset_axi_infrastructure_survives=YES" in flow

    control = (ROOT / "rtl/axi/accelerator_control_axil.v").read_text(
        encoding="utf-8"
    )
    system_top = (ROOT / "rtl/top/accelerator_system_top.v").read_text(
        encoding="utf-8"
    )
    assert "input  wire                         accelerator_soft_reset_safe" in control
    assert "CTRL_ERR_RESET_UNSAFE" in control
    assert "CTRL_ERR_RESET_PENDING" in control
    assert "command_reset_quiesce" in control
    assert "reset_quiesce_request = reset_quiesce_q" in control
    assert "reset_quiesce_q &&" in control
    assert "REG_RESET_STATUS" in control
    assert "32'h0005_0003" in control
    assert "soft_reset_pending_q && !accelerator_reset_active" in control
    assert "profiling accelerator_profiling_counters.v" in flow
    assert "accelerator_profiling_counters" in system_top
    assert ".frame_start(accelerator_start && accelerator_start_ready)" in system_top
    assert ".accelerator_soft_reset_safe(accelerator_soft_reset_safe)" in system_top
    assert ".reset_quiesce_request(reset_quiesce_request)" in system_top
    assert ".quiesce_request(reset_quiesce_request)" in system_top

    accelerator_top = (ROOT / "rtl/top/accelerator_top.v").read_text(
        encoding="utf-8"
    )
    assert "soft_reset_safe_sample_q <= soft_reset_safe_now" in accelerator_top
    assert "soft_reset_safe_q <= soft_reset_safe_sample_q" in accelerator_top
    assert "s_axis_fb_tvalid && !quiesce_request" in accelerator_top
    assert "s_axis_spectrum_tvalid && !quiesce_request" in accelerator_top


def test_deepfilter_arithmetic_is_owned_by_the_shared_hybrid_pe_array():
    accelerator_top = (ROOT / "rtl/top/accelerator_top.v").read_text(
        encoding="utf-8"
    )
    subsystem = (
        ROOT / "rtl/memory/sequential_v5_pe_memory_subsystem.v"
    ).read_text(encoding="utf-8")
    controller = (
        ROOT / "rtl/integration/hybrid_pe_deepfilter_controller.v"
    ).read_text(encoding="utf-8")

    assert "u_deepfilter_engine" not in accelerator_top
    assert "sequential_deepfilter_engine" not in accelerator_top
    assert "u_hybrid_pe_deepfilter_controller" in subsystem
    assert ".cdf_start_valid(df_cdf_start_valid)" in subsystem
    assert ".cdf_tap_valid(df_cdf_tap_valid)" in subsystem
    assert ".cdf_result_ready(pe_cdf_result_ready)" in subsystem
    assert ".cdf_start_valid(1'b0)" not in subsystem
    assert re.search(r"\bdeepfilter_complex_mac\s*(?:#\s*\([^;]*\))?\s+\w+\s*\(", controller) is None

    production_flows = (
        "create_accelerator_full_bd.tcl",
        "run_accelerator_top_frequency_ooc.tcl",
        "run_accelerator_top_v5_ooc.tcl",
        "synth_accelerator_top_feature_ooc.tcl",
    )
    for name in production_flows:
        source_manifest = (SCRIPTS / name).read_text(encoding="utf-8")
        assert "hybrid_pe_deepfilter_controller.v" in source_manifest, name
        assert "sequential_deepfilter_engine.v" not in source_manifest, name
        assert "deepfilter_complex_mac.v" not in source_manifest, name


def test_saved_full_implementation_evidence_passes_release_timing_gate():
    metrics = _key_values(REPORTS / "metrics_post_route.txt")

    assert metrics["vivado_version"] == "2018.3"
    assert metrics["part"] == "xc7z020clg400-1"
    assert metrics["top"] == "zephyr_full_wrapper"
    assert metrics["design_baseline_commit"] == (
        "f460743940ca66ed04f2e33746968ce587b0dd72"
    )
    for gate in (
        "timing_met",
        "hold_met",
        "hold_guardband_met",
        "resources_below_limit",
        "routing_errors_zero",
        "unconstrained_internal_endpoints_zero",
        "clockless_registers_zero",
        "combinational_loops_zero",
        "latch_loops_zero",
        "cdc_all_paths_safely_timed",
        "blocking_drc_zero",
    ):
        assert metrics[gate] == "1", gate

    assert metrics["full_gate_pass"] == "1"

    assert float(metrics["setup_margin_target_ns"]) >= 0.25
    assert float(metrics["setup_implementation_uncertainty_ns"]) == (
        float(metrics["setup_default_uncertainty_ns"])
        + float(metrics["setup_margin_target_ns"])
    )
    assert float(metrics["setup_wns_ns"]) >= 0.0
    expected_margin_gate = (
        "1" if float(metrics["setup_guardbanded_wns_ns"]) >= 0.0 else "0"
    )
    assert metrics["setup_engineering_margin_met"] == expected_margin_gate
    assert float(metrics["hold_whs_ns"]) >= 0.0
    assert float(metrics["hold_guardband_ns"]) >= 0.05
    assert float(metrics["hold_raw_physical_margin_ns"]) >= float(
        metrics["hold_guardband_ns"]
    )
    assert metrics["setup_failing_endpoints"] == "0"
    assert metrics["hold_failing_endpoints"] == "0"
    assert metrics["drc_errors"] == "0"
    assert metrics["drc_critical_warnings"] == "0"
    assert metrics["required_report_failures"] == "0"
    assert metrics["write_bitstream_invoked"] == "NO"
    assert metrics["hwh_requested"] == "NO"
    assert metrics["board_connected"] == "NO"


def test_saved_reports_confirm_timing_route_cdc_and_artifact_boundary():
    timing = (REPORTS / "timing_summary_post_route.rpt").read_text(
        encoding="utf-8"
    )
    route = (REPORTS / "route_status_post_route.rpt").read_text(
        encoding="utf-8"
    )
    cdc = (REPORTS / "cdc_post_route.rpt").read_text(encoding="utf-8")
    implementation_log = (REPORTS / "vivado-implementation.log").read_text(
        encoding="utf-8"
    )
    run_status = _key_values(REPORTS / "run_status.txt")

    assert "All user specified timing constraints are met." in timing
    routable_match = re.search(r"# of routable nets\.+\s*:\s*(\d+)", route)
    routed_match = re.search(r"# of fully routed nets\.+\s*:\s*(\d+)", route)
    assert routable_match is not None
    assert routed_match is not None
    assert routed_match.group(1) == routable_match.group(1)
    assert "# of nets with routing errors.......... :           0" in route
    assert "All paths are Safely Timed." in cdc
    assert "ACCELERATOR_FULL_IMPLEMENTATION_ROUTE_COMPLETE" in implementation_log
    assert "ACCELERATOR_FULL_IMPLEMENTATION_ROUTE_PASS" in implementation_log
    wrapper_path = REPORTS / "wrapper_validation.txt"
    if wrapper_path.exists():
        wrapper = _key_values(wrapper_path)
        assert wrapper["windows_cmd_recheck"] == "METRICS_PARSER_PASS"
        assert wrapper["metrics_missing"] == "0"
    else:
        assert run_status["vivado_implementation_rc"] == "0"
        assert run_status["metrics_gate"] == "PASS"
        assert run_status["exit_failed"] == "0"
    assert not list(REPORTS.rglob("*.bit"))
    assert not list(REPORTS.rglob("*.hwh"))
