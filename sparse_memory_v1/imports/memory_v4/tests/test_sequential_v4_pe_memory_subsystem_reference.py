import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
RTL = ROOT / "rtl" / "memory" / "sequential_v4_pe_memory_subsystem.v"
FSM_TB = ROOT / "rtl" / "tb" / "tb_sequential_v4_pe_memory_subsystem_fsm.sv"
RUNNER = (
    ROOT / "rtl" / "scripts" / "Run-Sequential-V4-PE-Memory-Subsystem-Vivado.cmd"
)
XDC = ROOT / "rtl" / "memory" / "sequential_v4_pe_memory_subsystem_100mhz.xdc"
MEMORY = ROOT / "rtl" / "memory" / "memory.v"
PE = (
    ROOT
    / "rtl"
    / "pe_array"
    / "baseline"
    / "v1"
    / "rtl"
    / "top"
    / "pe_array_datapath.v"
)
V4 = ROOT / "outputs" / "memory" / "2026-09-03" / "v4"
IMAGE = V4 / "parameters_v4.bin"
LAYOUT = json.loads((V4 / "memory_layout_v4.json").read_text())


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_connected_wrapper_preserves_frozen_storage_and_pe_inputs():
    assert sha256(MEMORY) == (
        "72435c38d85c7cbaaab25733c59912a52057b280e87c3b4d1b7ee52d7f5dab71"
    )
    assert sha256(PE) == (
        "bdde93915e380e910b6504cb8f9ec2439d8cd95fbd684513bd15af1426ed3954"
    )
    assert sha256(IMAGE) == (
        "e4f1f5cd78007a47c8ecfc137f2f0e8117aa2af162bd7050913bf1867cf2cf34"
    )


def test_exact_production_hierarchy_and_exclusions():
    source = RTL.read_text(encoding="utf-8")
    expected_instantiations = {
        "memory_service": r"\bmemory_service\s*#\s*\(",
        "sequential_recurrent_context_store": (
            r"\bsequential_recurrent_context_store\s+u_context_store\s*\("
        ),
        "sequential_pe_job_controller": (
            r"\bsequential_pe_job_controller\s*#\s*\("
        ),
        "pe_array_datapath": r"\bpe_array_datapath\s+u_pe_array_datapath\s*\(",
    }
    for module, pattern in expected_instantiations.items():
        assert len(re.findall(pattern, source)) == 1, module

    for excluded in (
        "parameter_weight_bank",
        "matrix0_raw_accumulator_scratch",
        "parameter_source_directory",
        "active_index_list_store",
        "parameter_membership_binding",
        "parameter_axi_prefetch",
        "parameter_tile_provider",
        "parameter_ping_pong_owner",
    ):
        assert not re.search(rf"\b{excluded}\s+(?:#\s*\()?u_", source)

    # The inline adapter retains only counters/identity, never LUT payload.
    assert "reg [7:0] lut_addr_q" in source
    assert "reg [2:0] lut_table_q" in source
    assert not re.search(r"lut\w*\s*\[[^]]+:?[^]]*\]\s*\[", source)


def test_v4_full_stage_transfer_is_density_independent_and_lut_is_once_per_epoch():
    assert LAYOUT["format_version"] == 4
    assert LAYOUT["stage_count"] == 12
    assert LAYOUT["cache_bytes"] == 262_144
    assert max(stage["transfer_bytes"] for stage in LAYOUT["stages"]) == 219_360

    one_frame = sum(stage["transfer_bytes"] for stage in LAYOUT["stages"])
    assert one_frame == 1_050_544
    assert one_frame * 2 + 2_040 == 2_103_128

    lut = LAYOUT["global_sigmoid_lut"]
    payload = IMAGE.read_bytes()[lut["dram_byte_offset"] :][
        : lut["transfer_bytes"]
    ]
    assert len(payload) == 8 * 255 == 2_040
    assert hashlib.sha256(payload).hexdigest() == lut["sha256"]

    source = RTL.read_text(encoding="utf-8")
    assert ".image_version(`MODEL_V4_IMAGE_VERSION)" in source
    assert "service_stage_req_valid" in source
    assert "active_count" not in source.split("memory_service #(", 1)[0]


def context_identity(branch: int, context: int, layer: int) -> int:
    if branch == 0:
        return layer
    return (2, 10, 16)[branch - 1] + context * 2 + layer


def test_two_frame_global_fsm_schedule_covers_all_contexts_and_release_points():
    jobs = []
    stage_loads = []
    for frame in range(2):
        for stage in range(3):
            stage_loads.append(stage)
            jobs.append((frame, stage, 0, 0, True))
        for sb_stage in range(3):
            for branch in range(1, 4):
                stage = 3 + (branch - 1) * 3 + sb_stage
                stage_loads.append(stage)
                count = (4, 3, 2)[branch - 1]
                for context in range(count):
                    jobs.append((frame, stage, branch, context, context == count - 1))
    assert len(jobs) == 60
    assert sum(final for *_, final in jobs) == 24
    assert stage_loads[:12] == [0, 1, 2, 3, 6, 9, 4, 7, 10, 5, 8, 11]
    assert stage_loads[12:] == stage_loads[:12]

    identities = {
        context_identity(branch, context, layer)
        for branch, count in enumerate((1, 4, 3, 2))
        for context in range(count)
        for layer in range(2)
    }
    assert identities == set(range(20))


def test_compute_side_sparsity_request_equation_for_all_16_roles():
    sparse_roles = 0
    for density in (0.0, 0.03, 0.25, 0.55, 1.0):
        for stage in LAYOUT["stages"]:
            rows = stage["parameters"]["row_tiles"]
            expected = 0
            dense = 0
            for matrix_index, matrix in enumerate(stage["matrices"]):
                dense_role = stage["id"] in (0, 3, 6, 9) and matrix_index == 0
                if dense_role:
                    count = matrix["source_count"]
                    dense += count * rows
                else:
                    if density == 0:
                        count = 0
                    else:
                        count = min(
                            matrix["source_count"],
                            round(matrix["source_count"] * density),
                        )
                    expected += count * rows
                    if density == 0.0:
                        sparse_roles += 1
            expected += dense
            assert dense == (
                stage["matrices"][0]["source_count"] * rows
                if stage["id"] in (0, 3, 6, 9)
                else 0
            )
            assert expected >= dense
    assert sparse_roles == 16


def test_mapping_lut_and_reset_only_fault_wiring_are_explicit():
    source = RTL.read_text(encoding="utf-8")
    assert "4'd3 +" in source
    assert "sb_shared_branch + 1'b1" in source
    assert "sb_context_0" in source
    assert "stage_bank == 2'd0" in source
    assert "sb_start == 3'b001" in source
    assert "lut_count_q != 12'd2039" in source
    assert "lut_count_q != 12'd2040" in source
    assert "lut_start_count_q != 2'd1" in source
    assert re.search(
        r"assign reset_required\s*=.*integration_error_valid.*"
        r"memory_error_valid.*context_error_valid.*controller_error_valid.*"
        r"pe_overflow_any.*pe_protocol_error",
        source,
        re.S,
    )
    assert "clear_error(clear_error)" in source
    assert not re.search(
        r"if\s*\(clear_error\).*integration_error_valid\s*<=\s*1'b0",
        source,
        re.S,
    )
    assert ".cdf_start_valid(1'b0)" in source
    assert ".cdf_tap_valid(1'b0)" in source


def test_real_global_fsm_harness_and_timing_cuts_are_regression_inputs():
    source = RTL.read_text(encoding="utf-8")
    fsm_tb = FSM_TB.read_text(encoding="utf-8")
    runner = RUNNER.read_text(encoding="utf-8")
    xdc = XDC.read_text(encoding="utf-8")

    assert "reg rq_query_hold_valid_q" in source
    assert ".rq_param_query_valid(rq_query_hold_valid_q)" in source
    assert "context_list_read_req_id_q" in source
    assert ".list_read_req_logical_id(context_list_read_req_id_q)" in source
    assert re.search(r"\bfsm\s*#\s*\(", fsm_tb)
    assert "run_one_frame(1'b1)" in fsm_tb
    assert "run_one_frame(1'b0)" in fsm_tb
    assert "sb_accept_count == 54" in fsm_tb
    assert "stage_accept_count == 24" in fsm_tb
    assert FSM_TB.name in runner
    assert "metrics_post_route.txt" in runner
    assert "unconstrained_internal_endpoints_zero=1" in runner
    assert "create_clock -name clk -period 10.000" in xdc
    assert "HD.CLK_SRC BUFGCTRL_X0Y0" in xdc
