import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "rtl" / "scripts"
HYBRID_BASELINE = "f460743940ca66ed04f2e33746968ce587b0dd72"
ARTIFACT_REPORTS = ROOT / "rtl" / "reports" / "accelerator_full_artifacts"
BOARD_REPORTS = (
    ROOT / "rtl" / "reports" / "accelerator_full_board_hybrid_pe_20260916"
)


def key_values(path: Path) -> dict[str, str]:
    return dict(
        line.split("=", 1)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line and not line.startswith("#") and "=" in line
    )


def test_artifact_writer_rechecks_every_release_gate_before_bitstream():
    source = (SCRIPTS / "write_accelerator_full_artifacts.tcl").read_text(
        encoding="utf-8"
    )
    write_position = source.index("\n    write_bitstream -force $bit_path\n")
    for required in (
        "open_checkpoint $route_checkpoint",
        "get_cells -quiet zephyr_full_i",
        'REF_NAME [lindex $top_instances 0]] ne "zephyr_full"',
        "set setup_margin_target_ns 0.250",
        "set hold_guardband_ns 0.050",
        "setup_guardbanded_wns",
        "hold_raw_whs",
        "unrouted_nets",
        "partially_routed_nets",
        "drc_errors",
        "drc_critical_warnings",
    ):
        assert required in source
        assert source.index(required) < write_position
    assert "hwh_copied_from_same_project=YES" in source
    assert "ACCELERATOR_FULL_ARTIFACT_GATE_PASS" in source


def test_vectorless_power_report_cannot_be_mistaken_for_board_measurement():
    source = (SCRIPTS / "report_accelerator_vectorless_power.tcl").read_text(
        encoding="utf-8"
    )
    assert "open_checkpoint $route_checkpoint" in source
    assert "report_power -file $report_path" in source
    assert "activity_input=Vivado_vectorless_defaults" in source
    assert "saif_or_vcd_applied=NO" in source
    assert "physical_board_measurement=NO" in source
    assert "external_meter_trace=NONE" in source
    assert "ACCELERATOR_VECTORLESS_POWER_PASS" in source


def test_manifest_pins_requested_commit_artifacts_and_v5_image():
    source = (SCRIPTS / "make_accelerator_full_manifest.py").read_text(
        encoding="utf-8"
    )
    assert 'parser.add_argument("--hardware-commit", required=True)' in source
    assert 'parser.add_argument("--image-abi"' in source
    assert '"rtl/profiling"' in source
    assert 'ARTIFACT_BASENAME = "zephyr_full"' in source
    assert '"schema": "zephyr.accelerator.full.artifacts.v1"' in source
    assert "source_baseline_verified" in source
    assert "parameters_v5.bin" in source
    assert "memory_golden_v5.json" in source
    assert '"rtl/pe_array/production_v2/rtl"' in source
    assert '"rtl/experiments/realtime_layernorm"' in source
    assert '"image_abi": image_abi' in source


def test_programmer_requires_exact_target_and_verifies_done_and_errors():
    source = (SCRIPTS / "program_accelerator_full_board.tcl").read_text(
        encoding="utf-8"
    )
    assert "expected_target" in source
    assert "get_property NAME $target] eq $expected_target" in source
    assert "[llength $matching_targets] != 1" in source
    assert "[llength $matching_devices] != 1" in source
    assert "set expected_part xc7z020" in source
    assert "program_hw_devices $fpga" in source
    assert "BIT13_DONE_INTERNAL_SIGNAL_STATUS" in source
    assert "BIT14_DONE_PIN" in source
    assert "REGISTER.IR.BIT5_DONE" in source
    assert "BIT00_CRC_ERROR" in source
    assert "ACCELERATOR_FULL_PROGRAM_PASS" in source


def test_readonly_board_smoke_performs_no_mmio_writes():
    source = (SCRIPTS / "smoke_accelerator_full_board_readonly.tcl").read_text(
        encoding="utf-8"
    )
    assert "mrd -force -value" in source
    assert "mwr" not in source
    assert "mmio_writes=0" in source
    assert "ACCELERATOR_FULL_READONLY_SMOKE_PASS" in source


def test_saved_hybrid_artifact_and_readonly_board_evidence_are_clean():
    manifest = json.loads(
        (ARTIFACT_REPORTS / "artifact_manifest.json").read_text(encoding="utf-8")
    )
    assert manifest["schema"] == "zephyr.accelerator.full.artifacts.v1"
    assert manifest["hardware_source_commit"] == HYBRID_BASELINE
    assert manifest["source_baseline_verified"] is True
    assert manifest["artifacts"]["zephyr_full.bit"] == {
        "bytes": 4_045_679,
        "sha256": "9e537026de1d7215fddf8d262da86316a6ce5ed58ed20ec901b94c6313f4cf63",
    }
    assert manifest["artifacts"]["zephyr_full.hwh"] == {
        "bytes": 585_343,
        "sha256": "253adfae9ae6058a6d1b29c733f71b48a65c4b929deea19f1e5ef0d055317ed7",
    }
    assert manifest["target"]["image_abi"] == "0x00050003"
    assert manifest["post_route"]["setup_wns_ns"] >= 0.0
    expected_guardbanded_wns = (
        manifest["post_route"]["setup_wns_ns"]
        - manifest["post_route"]["setup_margin_target_ns"]
    )
    assert abs(
        manifest["post_route"]["setup_guardbanded_wns_ns"]
        - expected_guardbanded_wns
    ) < 1e-9
    assert manifest["post_route"]["hold_guardbanded_whs_ns"] >= 0.0
    assert manifest["post_route"]["hold_raw_physical_margin_ns"] >= 0.050
    assert manifest["post_route"]["drc_errors"] == 0
    assert manifest["post_route"]["drc_critical_warnings"] == 0
    assert manifest["parameter_image"]["path"].endswith("parameters_v5.bin")
    assert manifest["parameter_image"]["matches_baseline"] is True
    assert manifest["parameter_golden"]["path"].endswith("memory_golden_v5.json")
    assert manifest["parameter_golden"]["matches_baseline"] is True

    programmed = key_values(BOARD_REPORTS / "board_program_status.txt")
    assert programmed["observed_jtag_target"].endswith(
        "/Digilent/003017B78476A"
    )
    assert programmed["observed_device"] == "xc7z020_1"
    assert programmed["program_hw_devices_completed"] == "YES"
    assert programmed["configuration_status_verified"] == "YES"
    assert programmed["done_internal_after"] == "1"
    assert programmed["done_pin_after"] == "1"
    assert programmed["ir_done_after"] == "1"
    assert programmed["crc_error_after"] == "0"
    assert programmed["idcode_error_after"] == "0"
    assert programmed["security_error_after"] == "0"

    mmio = key_values(BOARD_REPORTS / "board_mmio_readonly.txt")
    assert mmio["schema"] == "zephyr.accelerator.full.mmio.readonly.v2"
    assert mmio["transport"] == "XSCT_JTAG_DAP"
    assert int(mmio["image_version"], 0) == 0x0005_0003
    assert int(mmio["packet_bytes_0"], 0) == (512 << 16) | 512
    assert int(mmio["packet_bytes_1"], 0) == 2048
    assert mmio["identity_verified"] == "YES"
    assert mmio["mmio_writes"] == "0"
    for field in (
        "status",
        "execution",
        "frame_id",
        "state_cycles",
        "irq_status",
        "first_fault",
        "first_fault_detail",
        "first_fault_frame",
        "control_error",
        "reset_status",
    ):
        assert int(mmio[field], 0) == 0
    for channel in ("io_dma_mm2s", "io_dma_s2mm", "spectrum_dma_mm2s"):
        # Halted without Idle is captured as a runtime blocker, not a traffic pass.
        assert int(mmio[f"{channel}_status"], 0) == 0x0000_0001
