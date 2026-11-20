import hashlib
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HANDOFF_DIR = ROOT / "docs" / "memory"
ARCHIVE = ROOT / "archive" / "parameter_memory_ping_pong"


def _verify_sha256_file(path: Path) -> list[Path]:
    checked = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line:
            continue
        digest, relative = line.split("  ", 1)
        target = ROOT / relative
        assert target.is_file(), relative
        assert hashlib.sha256(target.read_bytes()).hexdigest() == digest
        checked.append(target)
    return checked


def test_production_source_manifest_is_complete_and_hash_clean():
    checked = _verify_sha256_file(HANDOFF_DIR / "SHA256SUMS")
    assert len(checked) == 35
    assert (
        ROOT
        / "sparse_memory_v1"
        / "rtl"
        / "sequential_v4_sparse_memory_subsystem.sv"
        in checked
    )
    assert ROOT / "sparse_memory_v1" / "rtl" / "sparse_memory_service_v1.sv" in checked
    assert ROOT / "rtl" / "memory" / "layernorm_mailbox.v" in checked
    assert ROOT / "rtl" / "control" / "fsm.v" in checked
    assert ROOT / "rtl" / "top" / "accelerator_top.v" in checked
    assert ROOT / "rtl" / "memory" / "sequential_v4_pe_memory_subsystem.v" not in checked


def test_handoff_freezes_top_ownership_and_known_gaps():
    handoff = (HANDOFF_DIR / "HANDOFF.md").read_text(encoding="utf-8")
    manifest = (HANDOFF_DIR / "MANIFEST.md").read_text(encoding="utf-8")
    for required in (
        "67b515757364fd9c9cabb404dcae303a45d9ea17",
        "parallel_subbands=1'b0",
        "coordinated reset",
        "External dense-feature provider",
        "Projection coefficient sink",
        "Remaining system boundary",
        "AXI read address",
        "layernorm_mailbox",
        "sparse_load_enable",
        "SPARSE_ACCELERATOR_TOP_INTEGRATION.md",
    ):
        assert required in handoff
    assert "Do not use `glob rtl/**/*.v`" in manifest
    assert "archive/parameter_memory_ping_pong/" in manifest


def test_sparse_top_report_bundle_has_functional_and_route_evidence():
    # Keep the pre-fix result immutable so the timing improvement is auditable.
    report_dir = ROOT / "rtl" / "reports" / "accelerator_top_sparse"
    expected_xsim = {
        "xsim-fsm.log": "PASS tb_fsm",
        "xsim-adapter.log": "PASS tb_layernorm_mailbox_fsm_adapter",
        "xsim-feature-dispatcher.log": "PASS tb_sequential_feature_dispatcher",
        "xsim-df-coefficient-store.log": "PASS tb_sequential_df_coefficient_store",
        "xsim-deepfilter-engine.log": "PASS tb_sequential_deepfilter_engine",
    }
    for name, marker in expected_xsim.items():
        assert marker in (report_dir / name).read_text(encoding="utf-8")

    synth = (report_dir / "metrics_post_synth.txt").read_text(encoding="utf-8")
    route = (report_dir / "metrics_post_route.txt").read_text(encoding="utf-8")
    assert "evidence=ooc_post_synthesis_only" in synth
    assert "wns_ns=-3.121" in synth
    assert "evidence=ooc_post_route_only" in route
    assert "wns_ns=-1.146" in route
    assert "timing_met=0" in route
    for required in (
        "resources_below_80_percent=1",
        "routing_errors_zero=1",
        "unconstrained_internal_endpoints_zero=1",
        "clockless_registers_zero=1",
        "combinational_loops_zero=1",
    ):
        assert required in route


def test_sparse_top_timing_cut_closes_setup_and_hold():
    report_dir = ROOT / "rtl" / "reports" / "accelerator_top_sparse_timing"
    expected_xsim = {
        "xsim-fsm.log": "PASS tb_fsm",
        "xsim-adapter.log": "PASS tb_layernorm_mailbox_fsm_adapter",
        "xsim-feature-dispatcher.log": "PASS tb_sequential_feature_dispatcher",
        "xsim-df-coefficient-store.log": "PASS tb_sequential_df_coefficient_store",
        "xsim-deepfilter-engine.log": "PASS tb_sequential_deepfilter_engine",
        "xsim-top-timing-cut.log": "PASS tb_accelerator_top_timing_cut checks=7",
    }
    for name, marker in expected_xsim.items():
        assert marker in (report_dir / name).read_text(encoding="utf-8")

    top = (ROOT / "rtl" / "top" / "accelerator_top.v").read_text(
        encoding="utf-8"
    )
    assert "fsm_pe_barrier_idle_q <= subsystem_pe_barrier_idle" in top
    assert ".pe_barrier_idle(fsm_pe_barrier_idle_q)" in top

    synth = (report_dir / "metrics_post_synth.txt").read_text(encoding="utf-8")
    route = (report_dir / "metrics_post_route.txt").read_text(encoding="utf-8")
    summary = (report_dir / "timing_summary_post_route.rpt").read_text(
        encoding="utf-8"
    )
    assert "evidence=ooc_post_synthesis_only" in synth
    assert "wns_ns=-0.005" in synth
    assert "evidence=ooc_post_route_only" in route
    setup_slack = re.search(r"^wns_ns=([-0-9.]+)$", route, re.MULTILINE)
    hold_slack = re.search(r"^whs_ns=([-0-9.]+)$", route, re.MULTILINE)
    assert setup_slack is not None and float(setup_slack.group(1)) > 0
    assert hold_slack is not None and float(hold_slack.group(1)) > 0
    for required in (
        "timing_met=1",
        "hold_met=1",
        "resources_below_80_percent=1",
        "routing_errors_zero=1",
        "unconstrained_internal_endpoints_zero=1",
        "clockless_registers_zero=1",
        "combinational_loops_zero=1",
    ):
        assert required in route
    assert "All user specified timing constraints are met." in summary


def test_v3_inputs_remain_an_explicit_nonproduction_dependency():
    manifest = (HANDOFF_DIR / "MANIFEST.md").read_text(encoding="utf-8")
    retained = (
        "rtl/tools/generate_memory_v3.py",
        "rtl/tests/test_memory_v3_image.py",
        "rtl/memory/model_memory_v3_map.vh",
        "rtl/memory/model_memory_v3_table.v",
        "rtl/memory/model_memory_v3_readback_table.v",
        "outputs/memory/2026-09-01/v3/parameters_v3.bin",
        "outputs/memory/2026-09-01/v3/memory_layout_v3.json",
        "outputs/memory/2026-09-01/v3/memory_golden_v3.json",
        "outputs/memory/2026-09-01/v3/parameters_v3.sha256",
    )
    for relative in retained:
        assert relative in manifest
        assert (ROOT / relative).is_file()

    old_directory = (
        ROOT / "docs" / "integration" / "sequential_v4_accelerator_top"
    )
    assert not old_directory.exists()


def test_new_handoff_markdown_links_resolve():
    documents = [
        HANDOFF_DIR / "HANDOFF.md",
        HANDOFF_DIR / "SPARSE_ACCELERATOR_TOP_INTEGRATION.md",
        ROOT / "docs" / "memory" / "SEQUENTIAL_V4_PE_MEMORY_CONTRACT.md",
    ]
    pattern = re.compile(r"\[[^]]+\]\(([^)]+)\)")
    for document in documents:
        for raw_target in pattern.findall(document.read_text(encoding="utf-8")):
            target_text = raw_target.split("#", 1)[0]
            if not target_text or "://" in target_text:
                continue
            target = (document.parent / target_text).resolve()
            assert target.exists(), f"{document}: {raw_target}"


def test_ping_pong_research_is_outside_current_rtl_and_preserved():
    old_current_paths = (
        "rtl/memory/parameter_weight_bank.v",
        "rtl/memory/matrix0_raw_accumulator_scratch.v",
        "rtl/memory/parameter_source_directory.v",
        "rtl/memory/active_index_list_store.v",
        "rtl/tests/test_parameter_weight_bank_reference.py",
        "rtl/tests/test_matrix0_raw_accumulator_scratch_reference.py",
        "rtl/tests/test_parameter_source_directory_reference.py",
        "rtl/tests/test_active_index_list_store_reference.py",
    )
    for relative in old_current_paths:
        assert not (ROOT / relative).exists(), relative

    imported = _verify_sha256_file(
        ARCHIVE / "ACTIVE_INDEX_LIST_IMPORTED_SHA256SUMS"
    )
    assert len(imported) == 16
    assert (ARCHIVE / "docs" / "memory" / "PARAMETER_MEMORY_PING_PONG_CONTRACT.md").is_file()
    assert (ARCHIVE / "rtl" / "memory" / "parameter_weight_bank.v").is_file()
    assert (ARCHIVE / "rtl" / "memory" / "matrix0_raw_accumulator_scratch.v").is_file()
    assert (ARCHIVE / "rtl" / "memory" / "parameter_source_directory.v").is_file()
    assert (ARCHIVE / "rtl" / "memory" / "active_index_list_store.v").is_file()


def test_project_status_points_to_current_integration_entry():
    status_path = ROOT / "PROJECT_STATUS.md"
    status = status_path.read_text(encoding="utf-8")
    assert "最後更新：2026-09-08" in status
    assert "ec457b1" in status
    assert "0x00040002" in status
    assert "Full-design implementation摘要" in status
    assert "WNS +0.160 ns" in status
    assert "Sparse accelerator-top integration" in status
    assert "67b5157" in status
    assert "12,450,566" in status
    assert "-1.146 ns" in status
    assert "archive/parameter_memory_ping_pong/" in status

    pattern = re.compile(r"\[[^]]+\]\(([^)]+)\)")
    for raw_target in pattern.findall(status):
        target_text = raw_target.split("#", 1)[0]
        if not target_text or "://" in target_text:
            continue
        assert (status_path.parent / target_text).exists(), raw_target
