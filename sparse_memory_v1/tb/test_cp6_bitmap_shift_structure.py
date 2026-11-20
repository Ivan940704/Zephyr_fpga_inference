"""Structural guard for the CP6 sparse bitmap timing refactor."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "rtl" / "sparse_memory_service_v1.sv"
SERVICE_TB = ROOT / "tb" / "tb_sparse_memory_service_v1.sv"
SUBSYSTEM = ROOT / "rtl" / "sequential_v4_sparse_memory_subsystem.sv"
SUBSYSTEM_TB = ROOT / "tb" / "tb_sequential_v4_sparse_memory_subsystem.sv"
CONTEXT_CORE = ROOT / "rtl" / "sparse_recurrent_context_store_core_v1.v"
CONTEXT_WRAPPER = ROOT / "rtl" / "sparse_recurrent_context_store_v1.sv"
SUBSYSTEM_ROUTE = ROOT / "scripts" / "run_cp6_subsystem_route.tcl"


def test_bitmap_cursor_has_no_variable_index_mux() -> None:
    text = SERVICE.read_text(encoding="utf-8")

    assert text.count("reg [319:0] bitmap_shift_q;") == 1
    assert "wire validation_bit = bitmap_shift_q[0];" in text
    assert "scan_bitmap" not in text
    assert not re.search(r"tentative_bitmap[01]_q\s*\[", text)

    indices = re.findall(r"bitmap_shift_q\s*\[([^]]+)\]", text)
    assert indices
    assert set(indices) == {"0", "319:1"}

    shift = "bitmap_shift_q <= {1'b0, bitmap_shift_q[319:1]};"
    assert text.count(shift) == 4
    assert "bitmap_shift_q <= plan_bitmap0;" in text
    assert text.count("bitmap_shift_q <= tentative_bitmap0_q;") == 1
    assert text.count("bitmap_shift_q <= tentative_bitmap1_q;") == 2


def test_service_tb_covers_upper_bitmap_boundary() -> None:
    text = SERVICE_TB.read_text(encoding="utf-8")

    assert "(320'd1 << 319)" in text
    assert "check_weight(1'b0, 10'd319, 6'd3" in text
    assert "diag_planned_bytes == 32'd640" in text
    assert "diag_copy_commands == 2" in text


def test_command_bounds_decision_is_registered_before_dma_or_fault() -> None:
    text = SERVICE.read_text(encoding="utf-8")

    assert "localparam [4:0] S_CMD_DECIDE  = 5'd14;" in text
    assert "reg command_bounds_valid_q;" in text
    assert "command_bounds_valid_q <= command_bounds_valid;" in text
    assert "state_q <= S_CMD_DECIDE;" in text
    assert "S_CMD_DECIDE: begin" in text
    assert "if (!command_bounds_valid_q) begin" in text
    assert (
        "wire raw_cmd_valid = (state_q == S_LUT_CMD) || "
        "(state_q == S_CMD_SEND);"
    ) in text
    assert "(state_q == S_CMD_DECIDE)" not in text


def test_bitmap_validation_terminal_decision_has_its_own_state() -> None:
    text = SERVICE.read_text(encoding="utf-8")

    assert "localparam [4:0] S_VALIDATE_DONE = 5'd15;" in text
    validate = text.index("S_VALIDATE: begin")
    validate_done = text.index("S_VALIDATE_DONE: begin")
    plan_mul = text.index("S_PLAN_BYTES_MUL: begin")
    plan_commit = text.index("S_PLAN_BYTES_COMMIT: begin")
    lut = text.index("S_LUT_CMD: begin")
    validate_body = text[validate:validate_done]
    done_body = text[validate_done:plan_mul]
    plan_body = text[plan_mul:lut]

    assert "state_q <= S_VALIDATE_DONE;" in validate_body
    assert "validation_count_q <= validation_count_next[8:0];" in validate_body
    assert "validation_count_next !=" not in done_body
    assert "validation_count_q !=" in done_body
    assert "state_q <= S_VALIDATE;" in done_body
    assert "state_q <= S_PLAN_BYTES_MUL;" in done_body
    assert "planned_matrix0_bytes_q <=" in plan_body
    assert "planned_matrix1_bytes_q <=" in plan_body
    assert "state_q <= S_PLAN_BYTES_COMMIT;" in plan_body
    assert "diag_planned_bytes <=" in plan_body
    assert plan_mul < plan_commit < lut


def test_parameter_buffer_uses_registered_one_hot_word_writes() -> None:
    text = SERVICE.read_text(encoding="utf-8")

    assert "localparam integer PARAM_BUFFER_WORDS = PARAM_BUFFER_BITS / 64;" in text
    assert "localparam [4:0] A_PARAM_WRITE" in text
    assert "reg [PARAM_BUFFER_WORDS-1:0] param_word_write_q;" in text
    assert "reg [63:0] param_write_data_q;" not in text
    for bank in range(8):
        assert f"reg [63:0] param_write_data_bank{bank}_q;" in text
    assert "for (param_write_word = 0;" in text
    assert "if (param_word_write_q[param_write_word])" in text
    assert "param_buffer_q[param_write_word*64 +: 64] <=" in text
    assert "adapter_state_q <= A_PARAM_WRITE;" in text
    assert "A_PARAM_WRITE: adapter_state_q <= A_PARAM_RESPONSE;" in text
    assert "param_buffer_q <=" not in text


def test_context_core_list_read_decode_is_request_edge_pipelined() -> None:
    core = CONTEXT_CORE.read_text(encoding="utf-8")
    wrapper = CONTEXT_WRAPPER.read_text(encoding="utf-8")

    assert "module sparse_recurrent_context_store_core_v1 (" in core
    assert "module sequential_recurrent_context_store (" not in core
    assert "reg list_read_issue_q;" in core
    assert "!list_read_issue_q &&" in core
    assert "if (list_read_issue_q && list_read_issue_legal_q) begin" in core
    assert "active_mem0[list_read_issue_address_q]" in core
    assert "active_mem1[list_read_issue_address_q]" in core
    assert core.index("if (list_read_req_fire) begin") < core.index(
        "if (list_read_issue_q) begin"
    )
    assert "list_read_pending_tag_q <= list_read_issue_tag_q;" in core
    assert (
        "sparse_recurrent_context_store_core_v1 "
        "u_sparse_context_store_core" in wrapper
    )
    assert "../" not in core


def test_service_command_and_consumer_products_are_narrow_and_pipelined() -> None:
    text = SERVICE.read_text(encoding="utf-8")

    for state in (
        "S_RUN_MUL",
        "S_RUN_COMMAND",
        "S_DENSE_MUL",
        "S_DENSE_COMMAND",
    ):
        assert f"{state}: begin" in text
    assert "reg [15:0] run_start_tile_product_q;" in text
    assert "reg [15:0] run_length_tile_product_q;" in text
    assert "run_length_q <= run_end_q - run_start_q;" in text
    assert "run_length_q * scan_row_tiles" in text
    assert "{12'd0, run_length_tile_product_q, 4'b0000}" in text
    assert "run_end_q - run_start_q)} *" not in text
    assert "wire [15:0] requested_weight_product" in text
    assert "wire [13:0] requested_param_product" in text
    assert "A_WEIGHT_ISSUE: begin" in text
    assert "A_PARAM_ISSUE: begin" in text
    assert text.index("adapter_state_q <= A_WEIGHT_ISSUE;") < text.index(
        "A_WEIGHT_ISSUE: begin"
    )


def test_planner_request_is_issued_only_from_sampled_stage_and_fault_proof() -> None:
    text = SUBSYSTEM.read_text(encoding="utf-8")

    assert "reg planner_component_fault_q;" in text
    assert (
        "assign planner_plan_req_valid = stage_attempt_active_q &&" in text
    )
    assert ".plan_req_stage_id(sampled_stage_id_q)" in text
    assert ".plan_req_sparse_enable(sampled_stage_sparse_q)" in text
    assert ".context_error_valid(planner_component_fault_q)" in text
    assert "if (internal_reset_required || abort)" in text
    assert "planner_component_fault_q <= 1'b1;" in text
    assert "assign planner_plan_req_valid = stage_req_valid" not in text


def test_subsystem_route_uses_fixed_implementation_sequence_before_reports() -> None:
    text = SUBSYSTEM_ROUTE.read_text(encoding="utf-8")
    steps = (
        "opt_design\n",
        "place_design -directive Explore",
        "phys_opt_design\n",
        "route_design -directive Explore",
    )
    positions = [text.index(step) for step in steps]
    assert positions == sorted(positions)
    report = text.index("report_timing_summary", positions[-1])
    assert report > positions[-1]
    assert "route_design -tns_cleanup" not in text
    assert "report_phys_opt" not in text
    assert (
        "implementation_strategy="
        "DefaultOpt_ExplorePlace_DefaultPhysOpt_ExploreRoute" in text
    )


def test_context_list_read_dispatch_cuts_live_owner_from_store() -> None:
    text = SUBSYSTEM.read_text(encoding="utf-8")
    tb_text = SUBSYSTEM_TB.read_text(encoding="utf-8")

    for declaration in (
        '(* keep = "true" *) reg list_read_dispatch_valid_q;',
        '(* keep = "true" *) reg [1:0] list_read_dispatch_owner_q;',
        "reg [4:0] list_read_dispatch_id_q;",
        "reg [8:0] list_read_dispatch_ordinal_q;",
        "reg [7:0] list_read_dispatch_tag_q;",
    ):
        assert declaration in text
    assert (
        "assign store_list_read_req_valid = list_read_dispatch_valid_q &&"
        in text
    )
    assert "assign store_list_read_req_id = list_read_dispatch_id_q;" in text
    assert (
        "assign store_list_read_req_ordinal = list_read_dispatch_ordinal_q;"
        in text
    )
    assert "assign store_list_read_req_tag = list_read_dispatch_tag_q;" in text
    assert "assign store_list_read_req_id = (context_owner_q" not in text
    assert "abort || clear_fence || internal_reset_required" in text
    assert "!dut.list_read_dispatch_valid_q" in tb_text
    assert "held_planner_read_owner" in tb_text
    assert "component-fault test did not fill list-read dispatch" in tb_text
    assert "list-read dispatch became fallthrough" in tb_text
    assert "dut.controller_pe_protocol_error_q" in tb_text
    assert "controller_error_code == 8'h06" in tb_text


def test_component_faults_are_registered_at_all_internal_abort_boundaries() -> None:
    text = SUBSYSTEM.read_text(encoding="utf-8")
    tb_text = SUBSYSTEM_TB.read_text(encoding="utf-8")

    assert ".abort(abort || controller_registered_fault_abort)" in text
    assert "wire service_abort = abort || controller_registered_fault_abort;" in text
    assert ".abort(service_abort)" in text
    assert "pe_overflow_any || pe_protocol_error" not in text.split(
        "wire service_abort", maxsplit=1
    )[1].split(";", maxsplit=1)[0]
    assert ".memory_error_valid(controller_memory_fault_q)" in text
    assert ".context_error_valid(controller_context_fault_q)" in text
    assert ".overflow_any(controller_pe_overflow_q)" in text
    assert ".protocol_error(controller_pe_protocol_error_q)" in text
    assert (
        "assign reset_required = integration_error_valid || planner_error_valid ||"
        in text
    )
    assert "pe_overflow_any || pe_protocol_error;" in text
    assert "wire internal_reset_required = integration_error_valid ||" in text
    assert (
        "controller_error_valid || controller_pe_overflow_q ||" in text
    )
    assert "controller_pe_protocol_error_q;" in text
    assert "assign fb_done = controller_job_done && active_job_is_fb_q &&" in text
    assert "controller_job_done && !active_job_is_fb_q && !reset_required" in text
    assert "raw PE fault bypassed the internal registered boundary" in tb_text
    assert "raw PE fault did not suppress same-cycle fullband done" in tb_text
    assert "PE protocol fault did not cross registered abort boundary" in tb_text


def test_job_launch_uses_a_non_fallthrough_register_slice() -> None:
    text = SUBSYSTEM.read_text(encoding="utf-8")

    for declaration in (
        '(* keep = "true" *) reg job_request_valid_q;',
        "reg job_request_is_fb_q;",
        "reg [3:0] job_request_stage_q;",
        "reg [1:0] job_request_branch_q;",
        "reg [1:0] job_request_context_q;",
        "reg [1:0] job_request_shared_branch_q;",
        "reg [1:0] job_request_last_context_q;",
    ):
        assert declaration in text
    assert "wire controller_job_valid = job_request_valid_q &&" in text
    assert "wire [3:0] controller_job_stage = job_request_stage_q;" in text
    assert "wire [1:0] controller_job_branch = job_request_branch_q;" in text
    assert "wire [1:0] controller_job_context = job_request_context_q;" in text
    assert "assign fb_start_ready = job_admission_ready;" in text
    assert "assign sb_start_ready = job_admission_ready;" in text
    assert "job_request_valid_q <= 1'b1;" in text
    assert "active_job_is_fb_q <= job_request_is_fb_q;" in text
    assert "active_job_context_q <= job_request_context_q;" in text
    assert "!job_request_valid_q &&" in text


def test_parameter_write_data_is_partitioned_into_locality_banks() -> None:
    text = SERVICE.read_text(encoding="utf-8")

    for bank in range(8):
        declaration = (
            f'(* keep = "true" *) reg [63:0] '
            f'param_write_data_bank{bank}_q;'
        )
        assert declaration in text
        assert f"param_write_data_bank{bank}_q <= raw_rdata;" in text
        assert f"param_write_data_bank{bank}_q <= 64'd0;" in text

    assert "reg [63:0] param_write_data_q;" not in text
    assert "param_write_data_q <= raw_rdata;" not in text
    assert "case (param_write_word / 12)" in text
    assert text.count("param_write_data_bank") == 32
