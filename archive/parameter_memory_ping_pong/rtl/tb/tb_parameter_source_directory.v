`timescale 1ns/1ps

// Focused, self-checking Verilog-2001 testbench for the dual physical source
// directory.  The weight-bank ports are served by two deliberately unequal,
// independently backpressured behavioral responders; no production weight
// bank is instantiated here.
module tb_parameter_source_directory;
    localparam [2:0] ST_INVALID   = 3'd0;
    localparam [2:0] ST_SCRUBBING = 3'd1;
    localparam [2:0] ST_LOADING   = 3'd2;
    localparam [2:0] ST_READY     = 3'd3;
    localparam [2:0] ST_ACTIVE    = 3'd4;
    localparam [2:0] ST_DRAINING  = 3'd5;
    localparam [2:0] ST_RETAINED  = 3'd6;
    localparam [2:0] ST_ERROR     = 3'd7;

    localparam [1:0] DRAIN_INVALID  = 2'b00;
    localparam [1:0] DRAIN_RETAINED = 2'b01;
    localparam [1:0] DRAIN_ERROR    = 2'b10;

    localparam [3:0] OP_SCRUB          = 4'h0;
    localparam [3:0] OP_CLAIM_FRESH    = 4'h1;
    localparam [3:0] OP_REBIND_RETAINED= 4'h2;
    localparam [3:0] OP_PUBLISH_READY  = 4'h3;
    localparam [3:0] OP_ACTIVATE       = 4'h4;
    localparam [3:0] OP_BEGIN_DRAIN    = 4'h5;
    localparam [3:0] OP_FINISH_DRAIN   = 4'h6;
    localparam [3:0] OP_CLEAR_ERROR    = 4'h7;

    localparam [7:0] STATUS_OK                    = 8'h00;
    localparam [7:0] ERR_BAD_OPCODE               = 8'h01;
    localparam [7:0] ERR_WRONG_STATE              = 8'h02;
    localparam [7:0] ERR_STALE_GENERATION         = 8'h03;
    localparam [7:0] ERR_OWNER_MISMATCH           = 8'h04;
    localparam [7:0] ERR_NOT_QUIESCENT            = 8'h05;
    localparam [7:0] ERR_EXTERNAL_UNSAFE          = 8'h06;
    localparam [7:0] ERR_GENERATION_EXHAUSTED     = 8'h07;
    localparam [7:0] ERR_BAD_DRAIN_TARGET         = 8'h08;
    localparam [7:0] ERR_ABORTED                  = 8'h09;
    localparam [7:0] ERR_LOCAL_PROTOCOL           = 8'h0a;
    localparam [7:0] ERR_INTERNAL_STATE           = 8'h0b;
    localparam [7:0] ERR_BAD_BANK_MASK            = 8'h0c;
    localparam [7:0] ERR_BAD_IDENTITY             = 8'h0d;
    localparam [7:0] ERR_BAD_BOUNDS               = 8'h0e;
    localparam [7:0] ERR_BAD_MATRIX               = 8'h0f;
    localparam [7:0] ERR_BAD_SOURCE               = 8'h10;
    localparam [7:0] ERR_BAD_ROW_TILE             = 8'h11;
    localparam [7:0] ERR_DUPLICATE_PUBLICATION    = 8'h12;
    localparam [7:0] ERR_DIRECTORY_RELOCATION     = 8'h13;
    localparam [7:0] ERR_DIRECTORY_INCOMPLETE     = 8'h14;
    localparam [7:0] ERR_DIRECTORY_CORRUPT        = 8'h15;
    localparam [7:0] ERR_COMPUTE_MISS             = 8'h16;
    localparam [7:0] ERR_BANK_RESPONSE_ERROR      = 8'h17;
    localparam [7:0] ERR_BANK_IDENTITY_MISMATCH   = 8'h18;
    localparam [7:0] ERR_MEMBERSHIP_UNPROVEN      = 8'h19;
    localparam [7:0] ERR_SCRUB_REQUIRED           = 8'h1a;

    localparam [2:0] ERROR_SOURCE_BANK_RESPONSE = 3'd3;

    localparam [31:0] IMAGE_EPOCH = 32'h2026_0905;
    localparam [31:0] TICKET0 = 32'h1000_0001;
    localparam [31:0] TICKET1 = 32'h1000_0011;
    localparam [31:0] CONTENT0 = 32'h2000_0002;
    localparam [31:0] CONTENT1 = 32'h2000_0012;
    localparam [31:0] BANK_GEN0 = 32'h3000_0003;
    localparam [31:0] BANK_GEN1 = 32'h3000_0013;
    localparam [31:0] BIND00 = 32'h4000_0004;
    localparam [31:0] BIND01 = 32'h4000_0005;
    localparam [31:0] BIND10 = 32'h4000_0014;
    localparam [31:0] BIND11 = 32'h4000_0015;
    localparam [31:0] CONTEXT0 = 32'h5000_0005;
    localparam [31:0] CONTEXT1 = 32'h5000_0015;
    localparam [31:0] CANCEL0 = 32'h6000_0006;
    localparam [31:0] CANCEL1 = 32'h6000_0016;

    reg clk;
    reg rst_n;

    wire [5:0] directory_state;
    wire [31:0] directory_generation;
    wire [1:0] directory_content_valid;
    wire [1:0] directory_scrub_required;
    wire [1:0] directory_scrub_busy;
    wire [19:0] directory_scrub_address;
    wire [1:0] directory_last_scrubbed_image_epoch_valid;
    wire [63:0] directory_last_scrubbed_image_epoch;
    wire [19:0] directory_committed_source_count;
    wire [1:0] directory_management_fence;
    wire management_busy;
    wire final_close_pending;
    wire [1:0] lookup_outstanding;
    wire directory_read_busy;
    wire publication_busy;
    wire [3:0] directory_to_bank_pending;
    wire [3:0] bank_rsp_outstanding;
    wire [3:0] directory_bank_ref_count;
    wire directory_quiescent;
    wire [1:0] bank_quiescent;
    wire [1:0] bank_drain_complete;
    wire [1:0] bank_retire_safe;
    wire [1:0] reset_required;
    wire global_reset_required;
    wire [63:0] directory_image_epoch;
    wire [7:0] directory_stage_id;
    wire [3:0] directory_logical_branch;
    wire [63:0] directory_context_generation;
    wire [63:0] directory_content_handle;
    wire [63:0] directory_physical_bank_generation;
    wire [63:0] directory_cancellation_epoch;
    wire [3:0] directory_matrix_mask;
    wire [63:0] directory_matrix0_binding_token;
    wire [63:0] directory_matrix1_binding_token;
    wire [19:0] directory_matrix0_source_count;
    wire [19:0] directory_matrix1_source_count;
    wire [11:0] directory_matrix0_row_tile_count;
    wire [11:0] directory_matrix1_row_tile_count;
    wire [1:0] local_error_valid;
    wire [15:0] local_error_code;
    wire [5:0] local_error_source;
    wire [63:0] local_error_detail;
    wire [63:0] directory_stage_ticket;
    wire [31:0] local_error_directory_generation;
    wire [63:0] local_error_physical_bank_generation;
    wire [63:0] local_error_stage_ticket;
    wire [63:0] local_error_content_handle;

    reg mgmt_req_valid;
    wire mgmt_req_ready;
    reg [3:0] mgmt_req_opcode;
    reg [1:0] mgmt_req_bank_mask;
    reg [1:0] mgmt_req_drain_target;
    reg [15:0] mgmt_req_expected_directory_generation;
    reg [31:0] mgmt_req_expected_content_handle;
    reg [31:0] mgmt_req_expected_stage_ticket;
    reg [31:0] mgmt_req_expected_physical_bank_generation;
    reg [31:0] mgmt_req_new_image_epoch;
    reg [3:0] mgmt_req_new_stage_id;
    reg [31:0] mgmt_req_new_stage_ticket;
    reg [1:0] mgmt_req_new_logical_branch;
    reg [31:0] mgmt_req_new_context_generation;
    reg [31:0] mgmt_req_new_content_handle;
    reg [31:0] mgmt_req_new_physical_bank_generation;
    reg [31:0] mgmt_req_new_cancellation_epoch;
    reg [1:0] mgmt_req_new_matrix_mask;
    reg [31:0] mgmt_req_new_matrix0_binding_token;
    reg [31:0] mgmt_req_new_matrix1_binding_token;
    reg [9:0] mgmt_req_new_matrix0_source_count;
    reg [9:0] mgmt_req_new_matrix1_source_count;
    reg [5:0] mgmt_req_new_matrix0_row_tile_count;
    reg [5:0] mgmt_req_new_matrix1_row_tile_count;
    reg mgmt_req_external_safe;
    reg [15:0] mgmt_req_tag;
    wire mgmt_rsp_valid;
    reg mgmt_rsp_ready;
    wire [3:0] mgmt_rsp_opcode;
    wire [1:0] mgmt_rsp_bank_mask;
    wire [5:0] mgmt_rsp_state;
    wire [31:0] mgmt_rsp_directory_generation;
    wire [15:0] mgmt_rsp_tag;
    wire [7:0] mgmt_rsp_status;

    reg force_error_valid;
    wire force_error_ready;
    reg [1:0] force_error_bank_mask;
    reg [7:0] force_error_code;
    reg force_error_data_untrusted;
    reg force_error_causal_producers_drained;
    reg [31:0] force_error_directory_generation;
    reg [63:0] force_error_stage_ticket;
    reg [63:0] force_error_content_handle;
    reg [63:0] force_error_physical_bank_generation;
    reg [31:0] force_error_cancellation_epoch;
    reg [15:0] force_error_tag;
    wire force_error_rsp_valid;
    reg force_error_rsp_ready;
    wire [1:0] force_error_rsp_bank_mask;
    wire [7:0] force_error_rsp_code;
    wire [5:0] force_error_rsp_state;
    wire [31:0] force_error_rsp_directory_generation;
    wire [1:0] force_error_rsp_reset_required;
    wire [15:0] force_error_rsp_tag;
    wire [7:0] force_error_rsp_status;

    reg publish_req_valid;
    wire publish_req_ready;
    reg publish_req_bank_id;
    reg [31:0] publish_req_image_epoch;
    reg [3:0] publish_req_stage_id;
    reg [31:0] publish_req_stage_ticket;
    reg [1:0] publish_req_logical_branch;
    reg [31:0] publish_req_context_generation;
    reg [31:0] publish_req_matrix_binding_token;
    reg [31:0] publish_req_content_handle;
    reg [31:0] publish_req_physical_bank_generation;
    reg [15:0] publish_req_directory_generation;
    reg [31:0] publish_req_cancellation_epoch;
    reg publish_req_matrix_id;
    reg [9:0] publish_req_source_index;
    reg [12:0] publish_req_slot_base;
    reg [9:0] publish_req_source_count;
    reg [5:0] publish_req_row_tile_count;
    reg [1:0] publish_req_matrix_mask;
    reg publish_req_source_complete_proof;
    reg publish_req_slot_assignment_validated;
    reg [15:0] publish_req_tag;
    wire publish_rsp_valid;
    reg publish_rsp_ready;
    wire publish_rsp_bank_id;
    wire publish_rsp_matrix_id;
    wire [9:0] publish_rsp_source_index;
    wire [12:0] publish_rsp_slot_base;
    wire [15:0] publish_rsp_directory_generation;
    wire publish_rsp_committed;
    wire [9:0] publish_rsp_committed_source_count;
    wire [15:0] publish_rsp_tag;
    wire [7:0] publish_rsp_status;

    reg lookup_req_valid;
    wire lookup_req_ready;
    reg lookup_req_kind;
    reg [31:0] lookup_req_image_epoch;
    reg [3:0] lookup_req_stage_id;
    reg [31:0] lookup_req_stage_ticket;
    reg [1:0] lookup_req_logical_branch;
    reg [31:0] lookup_req_context_generation;
    reg lookup_req_matrix_id;
    reg [9:0] lookup_req_source_index;
    reg [5:0] lookup_req_row_tile;
    reg [31:0] lookup_req_matrix_binding_token;
    reg [31:0] lookup_req_cancellation_epoch;
    reg [15:0] lookup_req_user_tag;
    reg lookup_res_resolution_validated;
    reg lookup_res_selected_bank_id;
    reg [31:0] lookup_res_physical_bank_generation;
    reg [31:0] lookup_res_lease_owner_ticket;
    reg [31:0] lookup_res_matrix_binding_token;
    reg [31:0] lookup_res_content_handle;
    reg [15:0] lookup_res_directory_generation;
    reg [31:0] lookup_res_image_epoch;
    reg [3:0] lookup_res_stage_id;
    reg [1:0] lookup_res_logical_branch;
    reg [31:0] lookup_res_context_generation;
    reg [31:0] lookup_res_cancellation_epoch;
    reg [9:0] lookup_res_matrix_source_count;
    reg [5:0] lookup_res_row_tile_count;
    reg [1:0] lookup_res_matrix_mask;
    reg lookup_res_source_domain_validated;
    reg lookup_res_compute_membership_validated;
    reg lookup_res_causal_continuation;
    wire lookup_rsp_valid;
    reg lookup_rsp_ready;
    wire lookup_rsp_kind;
    wire [31:0] lookup_rsp_image_epoch;
    wire [3:0] lookup_rsp_stage_id;
    wire [31:0] lookup_rsp_stage_ticket;
    wire [1:0] lookup_rsp_logical_branch;
    wire [31:0] lookup_rsp_context_generation;
    wire lookup_rsp_matrix_id;
    wire [9:0] lookup_rsp_source_index;
    wire [5:0] lookup_rsp_row_tile;
    wire [31:0] lookup_rsp_matrix_binding_token;
    wire [31:0] lookup_rsp_cancellation_epoch;
    wire lookup_rsp_causal_continuation;
    wire lookup_rsp_selected_bank_id;
    wire [31:0] lookup_rsp_physical_bank_generation;
    wire [31:0] lookup_rsp_content_handle;
    wire [15:0] lookup_rsp_directory_generation;
    wire [12:0] lookup_rsp_slot_base;
    wire [12:0] lookup_rsp_weight_addr;
    wire lookup_rsp_hit;
    wire [127:0] lookup_rsp_weight_data;
    wire [15:0] lookup_rsp_user_tag;
    wire [7:0] lookup_rsp_status;
    wire lookup_rsp_fatal;

    wire bank0_rd_req_valid;
    reg bank0_rd_req_ready;
    wire [12:0] bank0_rd_req_addr;
    wire [31:0] bank0_rd_req_generation;
    wire [31:0] bank0_rd_req_lease_owner_ticket;
    wire [15:0] bank0_rd_req_tag;
    reg bank0_rd_rsp_valid;
    wire bank0_rd_rsp_ready;
    reg [127:0] bank0_rd_rsp_data;
    reg [12:0] bank0_rd_rsp_addr;
    reg [31:0] bank0_rd_rsp_generation;
    reg [31:0] bank0_rd_rsp_lease_owner_ticket;
    reg [15:0] bank0_rd_rsp_tag;
    reg [7:0] bank0_rd_rsp_status;

    wire bank1_rd_req_valid;
    reg bank1_rd_req_ready;
    wire [12:0] bank1_rd_req_addr;
    wire [31:0] bank1_rd_req_generation;
    wire [31:0] bank1_rd_req_lease_owner_ticket;
    wire [15:0] bank1_rd_req_tag;
    reg bank1_rd_rsp_valid;
    wire bank1_rd_rsp_ready;
    reg [127:0] bank1_rd_rsp_data;
    reg [12:0] bank1_rd_rsp_addr;
    reg [31:0] bank1_rd_rsp_generation;
    reg [31:0] bank1_rd_rsp_lease_owner_ticket;
    reg [15:0] bank1_rd_rsp_tag;
    reg [7:0] bank1_rd_rsp_status;

    wire fault_event_valid;
    reg fault_event_ready;
    wire [1:0] fault_event_bank_mask;
    wire [7:0] fault_event_code;
    wire [31:0] fault_event_detail;

    integer failures;
    integer checks;
    integer timeout_count;
    integer address;
    integer scrub_cut;
    integer accepted_count;
    integer response_count;
    integer expected_head;
    integer expected_tail;
    integer seed;
    integer random_delay_enable;
    integer sampled_count;
    integer random_stall_count;
    integer tb_cycle;
    integer request_cycle;
    integer measured_scrub_cycles;
    integer measured_scrub_accept_to_response_cycles;
    integer scrub_measure_active;
    integer scrub_write_count0;
    integer scrub_write_count1;
    integer scrub_sequence_errors0;
    integer scrub_sequence_errors1;
    integer measure_compute_active;
    integer measure_compute_accept_cycle;
    integer measured_compute_bank_issue_cycles;
    integer measured_compute_response_valid_cycles;
    integer measured_compute_terminal_cycles;
    integer measured_ii_start_cycle;
    integer measured_ii_start_accepts;
    integer measured_ii_window_cycles;
    integer measured_ii_accepts;
    integer measured_bank0_ii_window_cycles;
    integer measured_bank0_ii_accepts;
    integer measured_bank1_ii_window_cycles;
    integer measured_bank1_ii_accepts;
    integer directed_phase;
    reg scoreboard_enable;
    reg cycle_trace_enable;
    integer cycle_trace_index;
    reg auto_bank_responder;
    reg [12:0] manual_addr0;
    reg [12:0] manual_addr1;
    reg [31:0] manual_generation0;
    reg [31:0] manual_generation1;
    reg [31:0] manual_ticket0;
    reg [31:0] manual_ticket1;
    reg [15:0] manual_tag0;
    reg [15:0] manual_tag1;
    reg [15:0] expected_tag [0:4095];
    reg expected_bank [0:4095];
    reg [12:0] expected_addr [0:4095];
    reg [127:0] expected_data [0:4095];

    parameter_source_directory dut (
        .clk(clk), .rst_n(rst_n),
        .directory_state(directory_state),
        .directory_generation(directory_generation),
        .directory_content_valid(directory_content_valid),
        .directory_scrub_required(directory_scrub_required),
        .directory_scrub_busy(directory_scrub_busy),
        .directory_scrub_address(directory_scrub_address),
        .directory_last_scrubbed_image_epoch_valid(
            directory_last_scrubbed_image_epoch_valid),
        .directory_last_scrubbed_image_epoch(
            directory_last_scrubbed_image_epoch),
        .directory_committed_source_count(directory_committed_source_count),
        .directory_management_fence(directory_management_fence),
        .management_busy(management_busy),
        .final_close_pending(final_close_pending),
        .lookup_outstanding(lookup_outstanding),
        .directory_read_busy(directory_read_busy),
        .publication_busy(publication_busy),
        .directory_to_bank_pending(directory_to_bank_pending),
        .bank_rsp_outstanding(bank_rsp_outstanding),
        .directory_bank_ref_count(directory_bank_ref_count),
        .directory_quiescent(directory_quiescent),
        .bank_quiescent(bank_quiescent),
        .bank_drain_complete(bank_drain_complete),
        .bank_retire_safe(bank_retire_safe),
        .reset_required(reset_required),
        .global_reset_required(global_reset_required),
        .directory_image_epoch(directory_image_epoch),
        .directory_stage_id(directory_stage_id),
        .directory_logical_branch(directory_logical_branch),
        .directory_context_generation(directory_context_generation),
        .directory_content_handle(directory_content_handle),
        .directory_physical_bank_generation(
            directory_physical_bank_generation),
        .directory_cancellation_epoch(directory_cancellation_epoch),
        .directory_matrix_mask(directory_matrix_mask),
        .directory_matrix0_binding_token(directory_matrix0_binding_token),
        .directory_matrix1_binding_token(directory_matrix1_binding_token),
        .directory_matrix0_source_count(directory_matrix0_source_count),
        .directory_matrix1_source_count(directory_matrix1_source_count),
        .directory_matrix0_row_tile_count(
            directory_matrix0_row_tile_count),
        .directory_matrix1_row_tile_count(
            directory_matrix1_row_tile_count),
        .local_error_valid(local_error_valid),
        .local_error_code(local_error_code),
        .local_error_source(local_error_source),
        .local_error_detail(local_error_detail),
        .directory_stage_ticket(directory_stage_ticket),
        .local_error_directory_generation(
            local_error_directory_generation),
        .local_error_physical_bank_generation(
            local_error_physical_bank_generation),
        .local_error_stage_ticket(local_error_stage_ticket),
        .local_error_content_handle(local_error_content_handle),

        .mgmt_req_valid(mgmt_req_valid), .mgmt_req_ready(mgmt_req_ready),
        .mgmt_req_opcode(mgmt_req_opcode),
        .mgmt_req_bank_mask(mgmt_req_bank_mask),
        .mgmt_req_drain_target(mgmt_req_drain_target),
        .mgmt_req_expected_directory_generation(mgmt_req_expected_directory_generation),
        .mgmt_req_expected_content_handle(mgmt_req_expected_content_handle),
        .mgmt_req_expected_stage_ticket(mgmt_req_expected_stage_ticket),
        .mgmt_req_expected_physical_bank_generation(mgmt_req_expected_physical_bank_generation),
        .mgmt_req_new_image_epoch(mgmt_req_new_image_epoch),
        .mgmt_req_new_stage_id(mgmt_req_new_stage_id),
        .mgmt_req_new_stage_ticket(mgmt_req_new_stage_ticket),
        .mgmt_req_new_logical_branch(mgmt_req_new_logical_branch),
        .mgmt_req_new_context_generation(mgmt_req_new_context_generation),
        .mgmt_req_new_content_handle(mgmt_req_new_content_handle),
        .mgmt_req_new_physical_bank_generation(mgmt_req_new_physical_bank_generation),
        .mgmt_req_new_cancellation_epoch(mgmt_req_new_cancellation_epoch),
        .mgmt_req_new_matrix_mask(mgmt_req_new_matrix_mask),
        .mgmt_req_new_matrix0_binding_token(mgmt_req_new_matrix0_binding_token),
        .mgmt_req_new_matrix1_binding_token(mgmt_req_new_matrix1_binding_token),
        .mgmt_req_new_matrix0_source_count(mgmt_req_new_matrix0_source_count),
        .mgmt_req_new_matrix1_source_count(mgmt_req_new_matrix1_source_count),
        .mgmt_req_new_matrix0_row_tile_count(mgmt_req_new_matrix0_row_tile_count),
        .mgmt_req_new_matrix1_row_tile_count(mgmt_req_new_matrix1_row_tile_count),
        .mgmt_req_external_safe(mgmt_req_external_safe), .mgmt_req_tag(mgmt_req_tag),
        .mgmt_rsp_valid(mgmt_rsp_valid), .mgmt_rsp_ready(mgmt_rsp_ready),
        .mgmt_rsp_opcode(mgmt_rsp_opcode), .mgmt_rsp_bank_mask(mgmt_rsp_bank_mask),
        .mgmt_rsp_state(mgmt_rsp_state),
        .mgmt_rsp_directory_generation(mgmt_rsp_directory_generation),
        .mgmt_rsp_tag(mgmt_rsp_tag), .mgmt_rsp_status(mgmt_rsp_status),

        .force_error_valid(force_error_valid), .force_error_ready(force_error_ready),
        .force_error_bank_mask(force_error_bank_mask), .force_error_code(force_error_code),
        .force_error_data_untrusted(force_error_data_untrusted),
        .force_error_causal_producers_drained(force_error_causal_producers_drained),
        .force_error_directory_generation(force_error_directory_generation),
        .force_error_stage_ticket(force_error_stage_ticket),
        .force_error_content_handle(force_error_content_handle),
        .force_error_physical_bank_generation(force_error_physical_bank_generation),
        .force_error_cancellation_epoch(force_error_cancellation_epoch),
        .force_error_tag(force_error_tag),
        .force_error_rsp_valid(force_error_rsp_valid),
        .force_error_rsp_ready(force_error_rsp_ready),
        .force_error_rsp_bank_mask(force_error_rsp_bank_mask),
        .force_error_rsp_code(force_error_rsp_code),
        .force_error_rsp_state(force_error_rsp_state),
        .force_error_rsp_directory_generation(force_error_rsp_directory_generation),
        .force_error_rsp_reset_required(force_error_rsp_reset_required),
        .force_error_rsp_tag(force_error_rsp_tag),
        .force_error_rsp_status(force_error_rsp_status),

        .publish_req_valid(publish_req_valid), .publish_req_ready(publish_req_ready),
        .publish_req_bank_id(publish_req_bank_id),
        .publish_req_image_epoch(publish_req_image_epoch),
        .publish_req_stage_id(publish_req_stage_id),
        .publish_req_stage_ticket(publish_req_stage_ticket),
        .publish_req_logical_branch(publish_req_logical_branch),
        .publish_req_context_generation(publish_req_context_generation),
        .publish_req_matrix_binding_token(publish_req_matrix_binding_token),
        .publish_req_content_handle(publish_req_content_handle),
        .publish_req_physical_bank_generation(publish_req_physical_bank_generation),
        .publish_req_directory_generation(publish_req_directory_generation),
        .publish_req_cancellation_epoch(publish_req_cancellation_epoch),
        .publish_req_matrix_id(publish_req_matrix_id),
        .publish_req_source_index(publish_req_source_index),
        .publish_req_slot_base(publish_req_slot_base),
        .publish_req_source_count(publish_req_source_count),
        .publish_req_row_tile_count(publish_req_row_tile_count),
        .publish_req_matrix_mask(publish_req_matrix_mask),
        .publish_req_source_complete_proof(publish_req_source_complete_proof),
        .publish_req_slot_assignment_validated(publish_req_slot_assignment_validated),
        .publish_req_tag(publish_req_tag),
        .publish_rsp_valid(publish_rsp_valid), .publish_rsp_ready(publish_rsp_ready),
        .publish_rsp_bank_id(publish_rsp_bank_id),
        .publish_rsp_matrix_id(publish_rsp_matrix_id),
        .publish_rsp_source_index(publish_rsp_source_index),
        .publish_rsp_slot_base(publish_rsp_slot_base),
        .publish_rsp_directory_generation(publish_rsp_directory_generation),
        .publish_rsp_committed(publish_rsp_committed),
        .publish_rsp_committed_source_count(publish_rsp_committed_source_count),
        .publish_rsp_tag(publish_rsp_tag), .publish_rsp_status(publish_rsp_status),

        .lookup_req_valid(lookup_req_valid), .lookup_req_ready(lookup_req_ready),
        .lookup_req_kind(lookup_req_kind),
        .lookup_req_image_epoch(lookup_req_image_epoch),
        .lookup_req_stage_id(lookup_req_stage_id),
        .lookup_req_stage_ticket(lookup_req_stage_ticket),
        .lookup_req_logical_branch(lookup_req_logical_branch),
        .lookup_req_context_generation(lookup_req_context_generation),
        .lookup_req_matrix_id(lookup_req_matrix_id),
        .lookup_req_source_index(lookup_req_source_index),
        .lookup_req_row_tile(lookup_req_row_tile),
        .lookup_req_matrix_binding_token(lookup_req_matrix_binding_token),
        .lookup_req_cancellation_epoch(lookup_req_cancellation_epoch),
        .lookup_req_user_tag(lookup_req_user_tag),
        .lookup_res_resolution_validated(lookup_res_resolution_validated),
        .lookup_res_selected_bank_id(lookup_res_selected_bank_id),
        .lookup_res_physical_bank_generation(lookup_res_physical_bank_generation),
        .lookup_res_lease_owner_ticket(lookup_res_lease_owner_ticket),
        .lookup_res_matrix_binding_token(lookup_res_matrix_binding_token),
        .lookup_res_content_handle(lookup_res_content_handle),
        .lookup_res_directory_generation(lookup_res_directory_generation),
        .lookup_res_image_epoch(lookup_res_image_epoch),
        .lookup_res_stage_id(lookup_res_stage_id),
        .lookup_res_logical_branch(lookup_res_logical_branch),
        .lookup_res_context_generation(lookup_res_context_generation),
        .lookup_res_cancellation_epoch(lookup_res_cancellation_epoch),
        .lookup_res_matrix_source_count(lookup_res_matrix_source_count),
        .lookup_res_row_tile_count(lookup_res_row_tile_count),
        .lookup_res_matrix_mask(lookup_res_matrix_mask),
        .lookup_res_source_domain_validated(lookup_res_source_domain_validated),
        .lookup_res_compute_membership_validated(lookup_res_compute_membership_validated),
        .lookup_res_causal_continuation(lookup_res_causal_continuation),
        .lookup_rsp_valid(lookup_rsp_valid), .lookup_rsp_ready(lookup_rsp_ready),
        .lookup_rsp_kind(lookup_rsp_kind),
        .lookup_rsp_image_epoch(lookup_rsp_image_epoch),
        .lookup_rsp_stage_id(lookup_rsp_stage_id),
        .lookup_rsp_stage_ticket(lookup_rsp_stage_ticket),
        .lookup_rsp_logical_branch(lookup_rsp_logical_branch),
        .lookup_rsp_context_generation(lookup_rsp_context_generation),
        .lookup_rsp_matrix_id(lookup_rsp_matrix_id),
        .lookup_rsp_source_index(lookup_rsp_source_index),
        .lookup_rsp_row_tile(lookup_rsp_row_tile),
        .lookup_rsp_matrix_binding_token(lookup_rsp_matrix_binding_token),
        .lookup_rsp_cancellation_epoch(lookup_rsp_cancellation_epoch),
        .lookup_rsp_causal_continuation(lookup_rsp_causal_continuation),
        .lookup_rsp_selected_bank_id(lookup_rsp_selected_bank_id),
        .lookup_rsp_physical_bank_generation(lookup_rsp_physical_bank_generation),
        .lookup_rsp_content_handle(lookup_rsp_content_handle),
        .lookup_rsp_directory_generation(lookup_rsp_directory_generation),
        .lookup_rsp_slot_base(lookup_rsp_slot_base),
        .lookup_rsp_weight_addr(lookup_rsp_weight_addr),
        .lookup_rsp_hit(lookup_rsp_hit),
        .lookup_rsp_weight_data(lookup_rsp_weight_data),
        .lookup_rsp_user_tag(lookup_rsp_user_tag),
        .lookup_rsp_status(lookup_rsp_status), .lookup_rsp_fatal(lookup_rsp_fatal),

        .bank0_rd_req_valid(bank0_rd_req_valid), .bank0_rd_req_ready(bank0_rd_req_ready),
        .bank0_rd_req_addr(bank0_rd_req_addr),
        .bank0_rd_req_generation(bank0_rd_req_generation),
        .bank0_rd_req_lease_owner_ticket(bank0_rd_req_lease_owner_ticket),
        .bank0_rd_req_tag(bank0_rd_req_tag),
        .bank0_rd_rsp_valid(bank0_rd_rsp_valid), .bank0_rd_rsp_ready(bank0_rd_rsp_ready),
        .bank0_rd_rsp_data(bank0_rd_rsp_data), .bank0_rd_rsp_addr(bank0_rd_rsp_addr),
        .bank0_rd_rsp_generation(bank0_rd_rsp_generation),
        .bank0_rd_rsp_lease_owner_ticket(bank0_rd_rsp_lease_owner_ticket),
        .bank0_rd_rsp_tag(bank0_rd_rsp_tag), .bank0_rd_rsp_status(bank0_rd_rsp_status),
        .bank1_rd_req_valid(bank1_rd_req_valid), .bank1_rd_req_ready(bank1_rd_req_ready),
        .bank1_rd_req_addr(bank1_rd_req_addr),
        .bank1_rd_req_generation(bank1_rd_req_generation),
        .bank1_rd_req_lease_owner_ticket(bank1_rd_req_lease_owner_ticket),
        .bank1_rd_req_tag(bank1_rd_req_tag),
        .bank1_rd_rsp_valid(bank1_rd_rsp_valid), .bank1_rd_rsp_ready(bank1_rd_rsp_ready),
        .bank1_rd_rsp_data(bank1_rd_rsp_data), .bank1_rd_rsp_addr(bank1_rd_rsp_addr),
        .bank1_rd_rsp_generation(bank1_rd_rsp_generation),
        .bank1_rd_rsp_lease_owner_ticket(bank1_rd_rsp_lease_owner_ticket),
        .bank1_rd_rsp_tag(bank1_rd_rsp_tag), .bank1_rd_rsp_status(bank1_rd_rsp_status),

        .fault_event_valid(fault_event_valid), .fault_event_ready(fault_event_ready),
        .fault_event_bank_mask(fault_event_bank_mask),
        .fault_event_code(fault_event_code), .fault_event_detail(fault_event_detail)
    );

    always #5 clk = ~clk;

    always @(posedge clk)
        tb_cycle = tb_cycle + 1;

    // Count actual RAM scrub-write edges separately from management channel
    // latency.  The frozen contract requires both exactly 1,024 writes and
    // exactly 1,024 accept-to-response-valid cycles; neither may gain a
    // staging bubble, skip an address, or duplicate a payload write.
    always @(posedge clk) begin
        if (scrub_measure_active) begin
            if (dut.scrub_write0) begin
                if (directory_scrub_address[9:0] !==
                    scrub_write_count0[9:0])
                    scrub_sequence_errors0 = scrub_sequence_errors0 + 1;
                scrub_write_count0 = scrub_write_count0 + 1;
            end
            if (dut.scrub_write1) begin
                if (directory_scrub_address[19:10] !==
                    scrub_write_count1[9:0])
                    scrub_sequence_errors1 = scrub_sequence_errors1 + 1;
                scrub_write_count1 = scrub_write_count1 + 1;
            end
        end
    end

    // A deferred fresh descriptor install owns the bank-local accounting
    // update.  No publication commit may overlap that pending cleanup edge.
    always @(posedge clk) begin
        if (rst_n &&
            ((dut.descriptor_install_pending_q[0] &&
              dut.descriptor_install_claim_q[0] &&
              dut.pub_commit_now && !dut.pub_exec_bank_q) ||
             (dut.descriptor_install_pending_q[1] &&
              dut.descriptor_install_claim_q[1] &&
              dut.pub_commit_now && dut.pub_exec_bank_q)))
            fail("publication commit overlapped deferred fresh install");
    end

    always @(posedge clk) begin
        if (measure_compute_active &&
            (measured_compute_bank_issue_cycles < 0) &&
            ((bank0_rd_req_valid && bank0_rd_req_ready) ||
             (bank1_rd_req_valid && bank1_rd_req_ready)))
            measured_compute_bank_issue_cycles =
                tb_cycle - measure_compute_accept_cycle;
    end

    function [127:0] bank_data_pattern;
        input bank;
        input [12:0] word_address;
        begin
            bank_data_pattern = {32'h51a0_0000 | {31'd0, bank},
                                 32'hcafe_0000 | {19'd0, word_address},
                                 32'h35c0_0000 | {31'd0, bank},
                                 32'hface_0000 | {19'd0, word_address}};
        end
    endfunction

    task fail;
        input [8*160-1:0] message;
        begin
            failures = failures + 1;
            $display("FAIL: %0s at time %0t", message, $time);
        end
    endtask

    task check;
        input condition;
        input [8*160-1:0] message;
        begin
            checks = checks + 1;
            if (condition !== 1'b1)
                fail(message);
        end
    endtask

    // Rich fault classification is allowed to traverse a registered local
    // staging position after the combinational discovery-edge admission
    // fence.  Directed tests use this helper for the sticky record/event and
    // keep their same-edge ready checks separate and cycle-exact.
    task wait_fault_materialized;
        input bank;
        input require_event;
        begin
            timeout_count = 0;
            while (((local_error_valid[bank] !== 1'b1) ||
                    (require_event && (fault_event_valid !== 1'b1))) &&
                   timeout_count < 20) begin
                @(posedge clk);
                #1;
                timeout_count = timeout_count + 1;
            end
            check((local_error_valid[bank] === 1'b1) &&
                  (!require_event || (fault_event_valid === 1'b1)),
                  "bounded rich-fault materialization completes");
        end
    endtask

    task clear_inputs;
        begin
            mgmt_req_valid = 0;
            mgmt_req_opcode = 0;
            mgmt_req_bank_mask = 0;
            mgmt_req_drain_target = 0;
            mgmt_req_expected_directory_generation = 0;
            mgmt_req_expected_content_handle = 0;
            mgmt_req_expected_stage_ticket = 0;
            mgmt_req_expected_physical_bank_generation = 0;
            mgmt_req_new_image_epoch = 0;
            mgmt_req_new_stage_id = 0;
            mgmt_req_new_stage_ticket = 0;
            mgmt_req_new_logical_branch = 0;
            mgmt_req_new_context_generation = 0;
            mgmt_req_new_content_handle = 0;
            mgmt_req_new_physical_bank_generation = 0;
            mgmt_req_new_cancellation_epoch = 0;
            mgmt_req_new_matrix_mask = 0;
            mgmt_req_new_matrix0_binding_token = 0;
            mgmt_req_new_matrix1_binding_token = 0;
            mgmt_req_new_matrix0_source_count = 0;
            mgmt_req_new_matrix1_source_count = 0;
            mgmt_req_new_matrix0_row_tile_count = 0;
            mgmt_req_new_matrix1_row_tile_count = 0;
            mgmt_req_external_safe = 0;
            mgmt_req_tag = 0;
            force_error_valid = 0;
            force_error_bank_mask = 0;
            force_error_code = ERR_ABORTED;
            force_error_data_untrusted = 0;
            force_error_causal_producers_drained = 0;
            force_error_directory_generation = 0;
            force_error_stage_ticket = 0;
            force_error_content_handle = 0;
            force_error_physical_bank_generation = 0;
            force_error_cancellation_epoch = 0;
            force_error_tag = 0;
            publish_req_valid = 0;
            publish_req_bank_id = 0;
            publish_req_image_epoch = 0;
            publish_req_stage_id = 0;
            publish_req_stage_ticket = 0;
            publish_req_logical_branch = 0;
            publish_req_context_generation = 0;
            publish_req_matrix_binding_token = 0;
            publish_req_content_handle = 0;
            publish_req_physical_bank_generation = 0;
            publish_req_directory_generation = 0;
            publish_req_cancellation_epoch = 0;
            publish_req_matrix_id = 0;
            publish_req_source_index = 0;
            publish_req_slot_base = 0;
            publish_req_source_count = 0;
            publish_req_row_tile_count = 0;
            publish_req_matrix_mask = 0;
            publish_req_source_complete_proof = 0;
            publish_req_slot_assignment_validated = 0;
            publish_req_tag = 0;
            lookup_req_valid = 0;
            lookup_req_kind = 0;
            lookup_req_image_epoch = 0;
            lookup_req_stage_id = 0;
            lookup_req_stage_ticket = 0;
            lookup_req_logical_branch = 0;
            lookup_req_context_generation = 0;
            lookup_req_matrix_id = 0;
            lookup_req_source_index = 0;
            lookup_req_row_tile = 0;
            lookup_req_matrix_binding_token = 0;
            lookup_req_cancellation_epoch = 0;
            lookup_req_user_tag = 0;
            lookup_res_resolution_validated = 0;
            lookup_res_selected_bank_id = 0;
            lookup_res_physical_bank_generation = 0;
            lookup_res_lease_owner_ticket = 0;
            lookup_res_matrix_binding_token = 0;
            lookup_res_content_handle = 0;
            lookup_res_directory_generation = 0;
            lookup_res_image_epoch = 0;
            lookup_res_stage_id = 0;
            lookup_res_logical_branch = 0;
            lookup_res_context_generation = 0;
            lookup_res_cancellation_epoch = 0;
            lookup_res_matrix_source_count = 0;
            lookup_res_row_tile_count = 0;
            lookup_res_matrix_mask = 0;
            lookup_res_source_domain_validated = 0;
            lookup_res_compute_membership_validated = 0;
            lookup_res_causal_continuation = 0;
        end
    endtask

    task set_new_descriptor;
        input bank;
        begin
            mgmt_req_new_image_epoch = IMAGE_EPOCH;
            mgmt_req_new_stage_id = 4'd1;
            mgmt_req_new_stage_ticket = bank ? TICKET1 : TICKET0;
            mgmt_req_new_logical_branch = bank ? 2'd2 : 2'd1;
            mgmt_req_new_context_generation = bank ? CONTEXT1 : CONTEXT0;
            mgmt_req_new_content_handle = bank ? CONTENT1 : CONTENT0;
            mgmt_req_new_physical_bank_generation = bank ? BANK_GEN1 : BANK_GEN0;
            mgmt_req_new_cancellation_epoch = bank ? CANCEL1 : CANCEL0;
            mgmt_req_new_matrix_mask = 2'b11;
            mgmt_req_new_matrix0_binding_token = bank ? BIND10 : BIND00;
            mgmt_req_new_matrix1_binding_token = bank ? BIND11 : BIND01;
            mgmt_req_new_matrix0_source_count = 10'd320;
            mgmt_req_new_matrix1_source_count = 10'd320;
            mgmt_req_new_matrix0_row_tile_count = 6'd20;
            mgmt_req_new_matrix1_row_tile_count = 6'd20;
        end
    endtask

    task set_expected_identity;
        input bank;
        begin
            mgmt_req_expected_directory_generation = 16'd1;
            mgmt_req_expected_content_handle = bank ? CONTENT1 : CONTENT0;
            mgmt_req_expected_stage_ticket = bank ? TICKET1 : TICKET0;
            mgmt_req_expected_physical_bank_generation = bank ? BANK_GEN1 : BANK_GEN0;
        end
    endtask

    task clear_new_descriptor;
        begin
            mgmt_req_new_image_epoch = 0;
            mgmt_req_new_stage_id = 0;
            mgmt_req_new_stage_ticket = 0;
            mgmt_req_new_logical_branch = 0;
            mgmt_req_new_context_generation = 0;
            mgmt_req_new_content_handle = 0;
            mgmt_req_new_physical_bank_generation = 0;
            mgmt_req_new_cancellation_epoch = 0;
            mgmt_req_new_matrix_mask = 0;
            mgmt_req_new_matrix0_binding_token = 0;
            mgmt_req_new_matrix1_binding_token = 0;
            mgmt_req_new_matrix0_source_count = 0;
            mgmt_req_new_matrix1_source_count = 0;
            mgmt_req_new_matrix0_row_tile_count = 0;
            mgmt_req_new_matrix1_row_tile_count = 0;
        end
    endtask

    task send_mgmt;
        input [3:0] opcode;
        input [1:0] bank_mask;
        input [7:0] expected_status;
        input [15:0] tag;
        begin
            @(negedge clk);
            if ((opcode == OP_SCRUB) && (expected_status == STATUS_OK)) begin
                scrub_write_count0 = 0;
                scrub_write_count1 = 0;
                scrub_sequence_errors0 = 0;
                scrub_sequence_errors1 = 0;
                scrub_measure_active = 1;
            end
            mgmt_req_valid = 1;
            mgmt_req_opcode = opcode;
            mgmt_req_bank_mask = bank_mask;
            mgmt_req_tag = tag;
            timeout_count = 0;
            sampled_count = 0;
            while (!sampled_count && timeout_count < 1200) begin
                @(posedge clk);
                sampled_count = mgmt_req_ready;
                #1;
                timeout_count = timeout_count + 1;
            end
            check(sampled_count, "management request timed out");
            request_cycle = tb_cycle;
            // Caller-local validation failures may materialize their held
            // terminal response on the acceptance edge.  Successful commands
            // instead occupy the management execution/operation slot.  In
            // either case an accepted request must already own one physical
            // terminal landing position.
            check(management_busy || mgmt_rsp_valid,
                  "accepted management request owns execution or response position");
            @(negedge clk);
            mgmt_req_valid = 0;
            // Poison every live request field immediately after acceptance.
            // Execution and response must use only the immutable slot copy.
            mgmt_req_opcode = 4'hf;
            mgmt_req_bank_mask = 0;
            mgmt_req_drain_target = 2'b11;
            mgmt_req_expected_directory_generation = 0;
            mgmt_req_expected_content_handle = 0;
            mgmt_req_expected_stage_ticket = 0;
            mgmt_req_expected_physical_bank_generation = 0;
            clear_new_descriptor;
            mgmt_req_external_safe = 0;
            mgmt_req_tag = ~tag;
            timeout_count = 0;
            while (!mgmt_rsp_valid && timeout_count < 1200) begin
                @(posedge clk);
                #1;
                timeout_count = timeout_count + 1;
            end
            check(mgmt_rsp_valid, "management response timed out");
            if ((opcode == OP_SCRUB) && (expected_status == STATUS_OK)) begin
                measured_scrub_accept_to_response_cycles =
                    tb_cycle - request_cycle;
                measured_scrub_cycles = bank_mask[0] ?
                    scrub_write_count0 : scrub_write_count1;
                check(measured_scrub_accept_to_response_cycles == 1024,
                      "scrub accept-to-response-valid latency is exactly 1024 cycles");
                check(!bank_mask[0] || (scrub_write_count0 == 1024),
                      "selected bank0 scrub has exactly 1024 write edges");
                check(!bank_mask[1] || (scrub_write_count1 == 1024),
                      "selected bank1 scrub has exactly 1024 write edges");
                check(bank_mask[0] || (scrub_write_count0 == 0),
                      "unselected bank0 receives no scrub writes");
                check(bank_mask[1] || (scrub_write_count1 == 0),
                      "unselected bank1 receives no scrub writes");
                check(!bank_mask[0] || (scrub_sequence_errors0 == 0),
                      "bank0 scrub writes exact address sequence 0 through 1023");
                check(!bank_mask[1] || (scrub_sequence_errors1 == 0),
                      "bank1 scrub writes exact address sequence 0 through 1023");
                scrub_measure_active = 0;
            end
            check(mgmt_rsp_status == expected_status, "management status mismatch");
            check(mgmt_rsp_tag == tag, "management tag mismatch");
            @(negedge clk);
            mgmt_rsp_ready = 1;
            @(posedge clk);
            #1;
            mgmt_rsp_ready = 0;
            mgmt_req_bank_mask = 0;
        end
    endtask

    task scrub_both;
        begin
            clear_new_descriptor;
            mgmt_req_expected_directory_generation = 0;
            mgmt_req_expected_content_handle = 0;
            mgmt_req_expected_stage_ticket = 0;
            mgmt_req_expected_physical_bank_generation = 0;
            mgmt_req_new_image_epoch = IMAGE_EPOCH;
            mgmt_req_external_safe = 1;
            send_mgmt(OP_SCRUB, 2'b11, STATUS_OK, 16'h0001);
            check(directory_scrub_required == 2'b00, "dual scrub must clear required bits");
            check(directory_generation == 32'd0, "scrub must not allocate generation");
        end
    endtask

    task claim_bank;
        input bank;
        begin
            set_new_descriptor(bank);
            mgmt_req_expected_directory_generation = 16'd0;
            mgmt_req_external_safe = 1;
            send_mgmt(OP_CLAIM_FRESH, bank ? 2'b10 : 2'b01,
                      STATUS_OK, bank ? 16'h0011 : 16'h0010);
            check(directory_generation[bank*16 +: 16] == 16'd1,
                  "claim must allocate generation one");
            check(directory_state[bank*3 +: 3] == ST_LOADING,
                  "claim must enter loading");
        end
    endtask

    task set_publication;
        input bank;
        input matrix_id;
        input [9:0] source_index;
        input [12:0] slot_base;
        begin
            publish_req_bank_id = bank;
            publish_req_image_epoch = IMAGE_EPOCH;
            publish_req_stage_id = 4'd1;
            publish_req_stage_ticket = bank ? TICKET1 : TICKET0;
            publish_req_logical_branch = bank ? 2'd2 : 2'd1;
            publish_req_context_generation = bank ? CONTEXT1 : CONTEXT0;
            if (bank)
                publish_req_matrix_binding_token = matrix_id ? BIND11 : BIND10;
            else
                publish_req_matrix_binding_token = matrix_id ? BIND01 : BIND00;
            publish_req_content_handle = bank ? CONTENT1 : CONTENT0;
            publish_req_physical_bank_generation = bank ? BANK_GEN1 : BANK_GEN0;
            publish_req_directory_generation = 16'd1;
            publish_req_cancellation_epoch = bank ? CANCEL1 : CANCEL0;
            publish_req_matrix_id = matrix_id;
            publish_req_source_index = source_index;
            publish_req_slot_base = slot_base;
            publish_req_source_count = 10'd320;
            publish_req_row_tile_count = 6'd20;
            publish_req_matrix_mask = 2'b11;
            publish_req_source_complete_proof = 1;
            publish_req_slot_assignment_validated = 1;
        end
    endtask

    task publish_one;
        input bank;
        input matrix_id;
        input [9:0] source_index;
        input [12:0] slot_base;
        input [7:0] expected_status;
        input expected_commit;
        input [15:0] tag;
        begin
            @(negedge clk);
            set_publication(bank, matrix_id, source_index, slot_base);
            publish_req_tag = tag;
            publish_req_valid = 1;
            timeout_count = 0;
            sampled_count = 0;
            while (!sampled_count && timeout_count < 100) begin
                @(posedge clk);
                sampled_count = publish_req_ready;
                #1;
                timeout_count = timeout_count + 1;
            end
            if (!sampled_count)
                $display("PUB_TIMEOUT bank=%0d state=%0d fence=%b mgmt=%b pub=%b exec=%b rsp=%b rsptag=%h close=%b localerr=%b resetreq=%b",
                         bank, directory_state[bank*3 +: 3],
                         directory_management_fence[bank], management_busy,
                         publication_busy, dut.pub_exec_valid_q,
                         dut.pub_rsp_valid_q, dut.pub_rsp_tag_q,
                         final_close_pending,
                         local_error_valid[bank], reset_required[bank]);
            check(sampled_count, "publication request timed out");
            @(negedge clk);
            publish_req_valid = 0;
            timeout_count = 0;
            while (!publish_rsp_valid && timeout_count < 100) begin
                @(posedge clk);
                #1;
                timeout_count = timeout_count + 1;
            end
            check(publish_rsp_valid, "publication response timed out");
            check(publish_rsp_status == expected_status, "publication status mismatch");
            check(publish_rsp_committed == expected_commit, "publication commit mismatch");
            check(publish_rsp_tag == tag, "publication tag mismatch");
            @(negedge clk);
            publish_rsp_ready = 1;
            @(posedge clk);
            #1;
            publish_rsp_ready = 0;
        end
    endtask

    task set_lookup;
        input bank;
        input kind;
        input matrix_id;
        input [9:0] source_index;
        input [5:0] row_tile;
        input [15:0] user_tag;
        begin
            lookup_req_kind = kind;
            lookup_req_image_epoch = IMAGE_EPOCH;
            lookup_req_stage_id = 4'd1;
            lookup_req_stage_ticket = bank ? TICKET1 : TICKET0;
            lookup_req_logical_branch = bank ? 2'd2 : 2'd1;
            lookup_req_context_generation = bank ? CONTEXT1 : CONTEXT0;
            lookup_req_matrix_id = matrix_id;
            lookup_req_source_index = source_index;
            lookup_req_row_tile = row_tile;
            if (bank)
                lookup_req_matrix_binding_token = matrix_id ? BIND11 : BIND10;
            else
                lookup_req_matrix_binding_token = matrix_id ? BIND01 : BIND00;
            lookup_req_cancellation_epoch = bank ? CANCEL1 : CANCEL0;
            lookup_req_user_tag = user_tag;
            lookup_res_resolution_validated = 1;
            lookup_res_selected_bank_id = bank;
            lookup_res_physical_bank_generation = bank ? BANK_GEN1 : BANK_GEN0;
            lookup_res_lease_owner_ticket = bank ? TICKET1 : TICKET0;
            lookup_res_matrix_binding_token = lookup_req_matrix_binding_token;
            lookup_res_content_handle = bank ? CONTENT1 : CONTENT0;
            lookup_res_directory_generation = 16'd1;
            lookup_res_image_epoch = IMAGE_EPOCH;
            lookup_res_stage_id = 4'd1;
            lookup_res_logical_branch = bank ? 2'd2 : 2'd1;
            lookup_res_context_generation = bank ? CONTEXT1 : CONTEXT0;
            lookup_res_cancellation_epoch = bank ? CANCEL1 : CANCEL0;
            lookup_res_matrix_source_count = 10'd320;
            lookup_res_row_tile_count = 6'd20;
            lookup_res_matrix_mask = 2'b11;
            lookup_res_source_domain_validated = 1;
            lookup_res_compute_membership_validated = 1;
            lookup_res_causal_continuation = 0;
        end
    endtask

    task issue_lookup_wait;
        input bank;
        input kind;
        input matrix_id;
        input [9:0] source_index;
        input [5:0] row_tile;
        input [15:0] user_tag;
        input [7:0] expected_status;
        input expected_hit;
        input [12:0] expected_slot;
        input [12:0] expected_weight_addr;
        begin
            @(negedge clk);
            set_lookup(bank, kind, matrix_id, source_index, row_tile, user_tag);
            lookup_req_valid = 1;
            timeout_count = 0;
            sampled_count = 0;
            while (!sampled_count && timeout_count < 100) begin
                @(posedge clk);
                sampled_count = lookup_req_ready;
                #1;
                timeout_count = timeout_count + 1;
            end
            check(sampled_count, "lookup request timed out");
            if (user_tag == 16'h4000) begin
                measure_compute_active = 1;
                measure_compute_accept_cycle = tb_cycle;
                measured_compute_bank_issue_cycles = -1;
                measured_compute_response_valid_cycles = -1;
                measured_compute_terminal_cycles = -1;
            end
            @(negedge clk);
            lookup_req_valid = 0;
            timeout_count = 0;
            while (!lookup_rsp_valid && timeout_count < 100) begin
                @(posedge clk);
                #1;
                timeout_count = timeout_count + 1;
            end
            check(lookup_rsp_valid, "lookup response timed out");
            if (user_tag == 16'h4000)
                measured_compute_response_valid_cycles =
                    tb_cycle - measure_compute_accept_cycle;
            check(lookup_rsp_status == expected_status, "lookup status mismatch");
            check(lookup_rsp_hit == expected_hit, "lookup hit mismatch");
            check(lookup_rsp_slot_base == expected_slot, "lookup slot base mismatch");
            check(lookup_rsp_weight_addr == expected_weight_addr, "lookup weight addr mismatch");
            check(lookup_rsp_user_tag == user_tag, "lookup user tag mismatch");
            if (!kind)
                check(lookup_rsp_weight_data == 0, "probe must return zero weight data");
            @(negedge clk);
            lookup_rsp_ready = 1;
            @(posedge clk);
            #1;
            if (user_tag == 16'h4000) begin
                measured_compute_terminal_cycles =
                    tb_cycle - measure_compute_accept_cycle;
                measure_compute_active = 0;
            end
            lookup_rsp_ready = 0;
        end
    endtask

    // Behavioral physical-bank responders.  Their response data depends only
    // on the selected bank and checked word address, never on the opaque user
    // tag.  Each holds every response stable until the directory accepts it.
    always @(posedge clk) begin
        if (!rst_n) begin
            bank0_rd_rsp_valid <= 0;
            bank1_rd_rsp_valid <= 0;
        end else if (auto_bank_responder) begin
            if (bank0_rd_rsp_valid && bank0_rd_rsp_ready)
                bank0_rd_rsp_valid <= 0;
            if (bank1_rd_rsp_valid && bank1_rd_rsp_ready)
                bank1_rd_rsp_valid <= 0;
            if (bank0_rd_req_valid && bank0_rd_req_ready) begin
                bank0_rd_rsp_valid <= 1;
                bank0_rd_rsp_data <= bank_data_pattern(0, bank0_rd_req_addr);
                bank0_rd_rsp_addr <= bank0_rd_req_addr;
                bank0_rd_rsp_generation <= bank0_rd_req_generation;
                bank0_rd_rsp_lease_owner_ticket <= bank0_rd_req_lease_owner_ticket;
                bank0_rd_rsp_tag <= bank0_rd_req_tag;
                bank0_rd_rsp_status <= STATUS_OK;
            end
            if (bank1_rd_req_valid && bank1_rd_req_ready) begin
                bank1_rd_rsp_valid <= 1;
                bank1_rd_rsp_data <= bank_data_pattern(1, bank1_rd_req_addr);
                bank1_rd_rsp_addr <= bank1_rd_req_addr;
                bank1_rd_rsp_generation <= bank1_rd_req_generation;
                bank1_rd_rsp_lease_owner_ticket <= bank1_rd_req_lease_owner_ticket;
                bank1_rd_rsp_tag <= bank1_rd_req_tag;
                bank1_rd_rsp_status <= STATUS_OK;
            end
        end
    end

    // Machine-readable trace consumed by the dependency-free Python
    // cycle-reference checker.  Values are sampled in the active region at
    // the exact edge where ready/valid handshakes occur, before NBA updates.
    always @(posedge clk) begin
        if (cycle_trace_enable) begin
            $display("TRACE_PSD c=%0d qv=%0d qr=%0d qb=%0d qrow=%0d qtag=%04h b0qv=%0d b0qr=%0d b0qa=%0d b0qt=%04h b1qv=%0d b1qr=%0d b1qa=%0d b1qt=%04h b0rv=%0d b0rr=%0d b0ra=%0d b0rt=%04h b0rs=%02h b1rv=%0d b1rr=%0d b1ra=%0d b1rt=%04h b1rs=%02h ov=%0d or=%0d ob=%0d oa=%0d ot=%04h os=%02h oh=%0d od=%032h lo=%0d p0=%0d p1=%0d w0=%0d w1=%0d r0=%0d r1=%0d",
                     cycle_trace_index,
                     lookup_req_valid, lookup_req_ready,
                     lookup_res_selected_bank_id, lookup_req_row_tile,
                     lookup_req_user_tag,
                     bank0_rd_req_valid, bank0_rd_req_ready,
                     bank0_rd_req_addr, bank0_rd_req_tag,
                     bank1_rd_req_valid, bank1_rd_req_ready,
                     bank1_rd_req_addr, bank1_rd_req_tag,
                     bank0_rd_rsp_valid, bank0_rd_rsp_ready,
                     bank0_rd_rsp_addr, bank0_rd_rsp_tag,
                     bank0_rd_rsp_status,
                     bank1_rd_rsp_valid, bank1_rd_rsp_ready,
                     bank1_rd_rsp_addr, bank1_rd_rsp_tag,
                     bank1_rd_rsp_status,
                     lookup_rsp_valid, lookup_rsp_ready,
                     lookup_rsp_selected_bank_id,
                     lookup_rsp_weight_addr, lookup_rsp_user_tag,
                     lookup_rsp_status, lookup_rsp_hit,
                     lookup_rsp_weight_data, lookup_outstanding,
                     directory_to_bank_pending[1:0],
                     directory_to_bank_pending[3:2],
                     bank_rsp_outstanding[1:0],
                     bank_rsp_outstanding[3:2],
                     directory_bank_ref_count[1:0],
                     directory_bank_ref_count[3:2]);
            cycle_trace_index = cycle_trace_index + 1;
        end
    end

    task issue_lookup_no_wait;
        input bank;
        input kind;
        input matrix_id;
        input [9:0] source_index;
        input [5:0] row_tile;
        input [15:0] user_tag;
        begin
            @(negedge clk);
            set_lookup(bank, kind, matrix_id, source_index, row_tile, user_tag);
            lookup_req_valid = 1;
            timeout_count = 0;
            sampled_count = 0;
            while (!sampled_count && timeout_count < 100) begin
                @(posedge clk);
                sampled_count = lookup_req_ready;
                #1;
                timeout_count = timeout_count + 1;
            end
            check(sampled_count, "no-wait lookup request timed out");
            @(negedge clk);
            lookup_req_valid = 0;
        end
    endtask

    task pulse_reset;
        begin
            @(negedge clk);
            rst_n = 0;
            repeat (3) @(posedge clk);
            @(negedge clk);
            rst_n = 1;
            @(posedge clk);
            #1;
            check(directory_state == {ST_INVALID, ST_INVALID},
                  "reset returns both directories to invalid");
            check(directory_scrub_required == 2'b11,
                  "reset re-arms physical scrub");
        end
    endtask

    // Caller invokes this task from a negedge with the named physical
    // position already occupied.  Reset may discard cross-reset work, but it
    // must clear every authority/credit/held-response bit without touching
    // the BRAM payload arrays.
    task reset_drop_from_negedge;
        begin
            rst_n = 0;
            @(posedge clk);
            #1;
            check(directory_state == {ST_INVALID, ST_INVALID} &&
                  directory_scrub_required == 2'b11,
                  "pipeline reset-drop revokes authority and requires scrub");
            check(!management_busy && !final_close_pending &&
                  !directory_read_busy && !publication_busy,
                  "pipeline reset-drop clears execution positions");
            check(!lookup_rsp_valid && !publish_rsp_valid &&
                  !mgmt_rsp_valid && !force_error_rsp_valid &&
                  !fault_event_valid,
                  "pipeline reset-drop clears every held response position");
            check(!bank0_rd_req_valid && !bank1_rd_req_valid &&
                  lookup_outstanding == 0 &&
                  directory_to_bank_pending == 0 &&
                  bank_rsp_outstanding == 0 &&
                  directory_bank_ref_count == 0,
                  "pipeline reset-drop clears all causal credits and requests");
            check(local_error_valid == 0 && reset_required == 0 &&
                  directory_quiescent && bank_quiescent == 2'b11,
                  "pipeline reset-drop restores clean local quiescence");
            @(negedge clk);
            clear_inputs;
            auto_bank_responder = 0;
            bank0_rd_rsp_valid = 0;
            bank1_rd_rsp_valid = 0;
            bank0_rd_req_ready = 0;
            bank1_rd_req_ready = 0;
            lookup_rsp_ready = 0;
            publish_rsp_ready = 0;
            mgmt_rsp_ready = 0;
            force_error_rsp_ready = 0;
            fault_event_ready = 0;
            rst_n = 1;
            @(posedge clk);
            #1;
            check(directory_quiescent && bank_quiescent == 2'b11,
                  "pipeline reset-drop stays quiescent after reset release");
        end
    endtask

    task scrub_one;
        input bank;
        input [15:0] tag;
        begin
            clear_new_descriptor;
            mgmt_req_expected_directory_generation = 0;
            mgmt_req_expected_content_handle = 0;
            mgmt_req_expected_stage_ticket = 0;
            mgmt_req_expected_physical_bank_generation = 0;
            mgmt_req_new_image_epoch = IMAGE_EPOCH;
            mgmt_req_external_safe = 1;
            send_mgmt(OP_SCRUB, bank ? 2'b10 : 2'b01, STATUS_OK, tag);
        end
    endtask

    // Launch a legal SCRUB and return immediately after its C0 acceptance.
    // Directed fault tests then control the physical response pins on a
    // precise C1..C1024 write edge without consuming the held management
    // terminal response in the generic helper.
    task start_scrub_no_wait;
        input [1:0] bank_mask;
        input [15:0] tag;
        begin
            clear_new_descriptor;
            mgmt_req_expected_directory_generation = 0;
            mgmt_req_expected_content_handle = 0;
            mgmt_req_expected_stage_ticket = 0;
            mgmt_req_expected_physical_bank_generation = 0;
            mgmt_req_new_image_epoch = IMAGE_EPOCH;
            mgmt_req_external_safe = 1;
            scrub_write_count0 = 0;
            scrub_write_count1 = 0;
            scrub_sequence_errors0 = 0;
            scrub_sequence_errors1 = 0;
            scrub_measure_active = 1;
            @(negedge clk);
            mgmt_req_opcode = OP_SCRUB;
            mgmt_req_bank_mask = bank_mask;
            mgmt_req_tag = tag;
            mgmt_req_valid = 1;
            timeout_count = 0;
            sampled_count = 0;
            while (!sampled_count && timeout_count < 20) begin
                @(posedge clk);
                sampled_count = mgmt_req_ready;
                #1;
                timeout_count = timeout_count + 1;
            end
            check(sampled_count, "directed SCRUB request accepted at C0");
            request_cycle = tb_cycle;
            @(negedge clk);
            mgmt_req_valid = 0;
            mgmt_req_opcode = 4'hf;
            mgmt_req_bank_mask = 0;
            mgmt_req_new_image_epoch = 0;
            mgmt_req_external_safe = 0;
            mgmt_req_tag = ~tag;
        end
    endtask

    task setup_bank0_active;
        input [15:0] tag_base;
        begin
            auto_bank_responder = 1;
            bank0_rd_req_ready = 1;
            bank1_rd_req_ready = 1;
            lookup_rsp_ready = 0;
            publish_rsp_ready = 0;
            mgmt_rsp_ready = 0;
            scrub_one(0, tag_base);
            set_new_descriptor(0);
            mgmt_req_expected_directory_generation = 0;
            mgmt_req_external_safe = 1;
            send_mgmt(OP_CLAIM_FRESH, 2'b01, STATUS_OK, tag_base + 1'b1);
            publish_one(0, 0, 0, 13'd100, STATUS_OK, 1,
                        tag_base + 2'd2);
            clear_new_descriptor;
            set_expected_identity(0);
            mgmt_req_external_safe = 1;
            send_mgmt(OP_PUBLISH_READY, 2'b01, STATUS_OK,
                      tag_base + 2'd3);
            set_expected_identity(0);
            mgmt_req_external_safe = 1;
            send_mgmt(OP_ACTIVATE, 2'b01, STATUS_OK,
                      tag_base + 3'd4);
            check(directory_state[2:0] == ST_ACTIVE,
                  "setup leaves bank0 active");
        end
    endtask

    task setup_bank0_ready;
        input [15:0] tag_base;
        begin
            auto_bank_responder = 1;
            bank0_rd_req_ready = 1;
            bank1_rd_req_ready = 1;
            lookup_rsp_ready = 0;
            publish_rsp_ready = 0;
            mgmt_rsp_ready = 0;
            scrub_one(0, tag_base);
            set_new_descriptor(0);
            mgmt_req_expected_directory_generation = 0;
            mgmt_req_external_safe = 1;
            send_mgmt(OP_CLAIM_FRESH, 2'b01, STATUS_OK,
                      tag_base + 1'b1);
            publish_one(0, 0, 0, 13'd100, STATUS_OK, 1,
                        tag_base + 2'd2);
            clear_new_descriptor;
            set_expected_identity(0);
            mgmt_req_external_safe = 1;
            send_mgmt(OP_PUBLISH_READY, 2'b01, STATUS_OK,
                      tag_base + 2'd3);
            check(directory_state[2:0] == ST_READY,
                  "setup leaves bank0 ready");
        end
    endtask

    task setup_both_active;
        input [15:0] tag_base;
        begin
            auto_bank_responder = 1;
            bank0_rd_req_ready = 1;
            bank1_rd_req_ready = 1;
            lookup_rsp_ready = 0;
            publish_rsp_ready = 0;
            mgmt_rsp_ready = 0;
            scrub_both;
            claim_bank(0);
            claim_bank(1);
            publish_one(0, 0, 0, 13'd100, STATUS_OK, 1,
                        tag_base);
            publish_one(1, 0, 0, 13'd1000, STATUS_OK, 1,
                        tag_base + 1'b1);
            clear_new_descriptor;
            set_expected_identity(0);
            mgmt_req_external_safe = 1;
            send_mgmt(OP_PUBLISH_READY, 2'b01, STATUS_OK,
                      tag_base + 2'd2);
            set_expected_identity(1);
            mgmt_req_external_safe = 1;
            send_mgmt(OP_PUBLISH_READY, 2'b10, STATUS_OK,
                      tag_base + 2'd3);
            set_expected_identity(0);
            mgmt_req_external_safe = 1;
            send_mgmt(OP_ACTIVATE, 2'b01, STATUS_OK,
                      tag_base + 3'd4);
            set_expected_identity(1);
            mgmt_req_external_safe = 1;
            send_mgmt(OP_ACTIVATE, 2'b10, STATUS_OK,
                      tag_base + 3'd5);
            check(directory_state == {ST_ACTIVE, ST_ACTIVE},
                  "setup leaves both directories active");
        end
    endtask

    task inject_bad_bank0_response;
        input [2:0] bad_kind;
        input [7:0] expected_status;
        input expected_reset_required;
        input [15:0] request_tag;
        begin
            auto_bank_responder = 0;
            bank0_rd_req_ready = 0;
            lookup_rsp_ready = 0;
            fault_event_ready = 0;
            issue_lookup_no_wait(0, 1, 0, 0, 0, request_tag);
            timeout_count = 0;
            while (!bank0_rd_req_valid && timeout_count < 50) begin
                @(negedge clk);
                timeout_count = timeout_count + 1;
            end
            check(bank0_rd_req_valid,
                  "bad-response test receives selected bank request");
            manual_addr0 = bank0_rd_req_addr;
            manual_generation0 = bank0_rd_req_generation;
            manual_ticket0 = bank0_rd_req_lease_owner_ticket;
            manual_tag0 = bank0_rd_req_tag;
            bank0_rd_req_ready = 1;
            @(posedge clk);
            #1;
            @(negedge clk);
            bank0_rd_req_ready = 0;
            bank0_rd_rsp_data = {128{1'b1}};
            bank0_rd_rsp_addr = (bad_kind == 0) ?
                                (manual_addr0 + 1'b1) : manual_addr0;
            bank0_rd_rsp_generation = (bad_kind == 1) ?
                                      (manual_generation0 + 1'b1) :
                                      manual_generation0;
            bank0_rd_rsp_lease_owner_ticket = (bad_kind == 2) ?
                                              (manual_ticket0 + 1'b1) :
                                              manual_ticket0;
            if (bad_kind == 3)
                bank0_rd_rsp_tag = {manual_tag0[15:2], 2'b11};
            else if (bad_kind == 4)
                bank0_rd_rsp_tag = {manual_tag0[15:2] + 1'b1,
                                    manual_tag0[1:0]};
            else
                bank0_rd_rsp_tag = manual_tag0;
            bank0_rd_rsp_status = (bad_kind == 5) ?
                                  ERR_WRONG_STATE : STATUS_OK;
            bank0_rd_rsp_valid = 1;
            timeout_count = 0;
            while (!bank0_rd_rsp_ready && timeout_count < 50) begin
                @(negedge clk);
                timeout_count = timeout_count + 1;
            end
            check(bank0_rd_rsp_ready,
                  "owned malformed response must be consumed to release credit");
            @(posedge clk);
            #1;
            @(negedge clk);
            bank0_rd_rsp_valid = 0;
            timeout_count = 0;
            while (!lookup_rsp_valid && timeout_count < 50) begin
                @(posedge clk);
                #1;
                timeout_count = timeout_count + 1;
            end
            check(lookup_rsp_valid && lookup_rsp_status == expected_status,
                  "bad-response terminal status classification");
            check(!lookup_rsp_hit && lookup_rsp_weight_data == 0 &&
                  lookup_rsp_slot_base == 0 && lookup_rsp_weight_addr == 0 &&
                  lookup_rsp_fatal,
                  "bad response zeros all authorizing payload fields");
            wait_fault_materialized(0, 1);
            check(local_error_valid[0] &&
                  local_error_source[2:0] == ERROR_SOURCE_BANK_RESPONSE,
                  "bad response latches scoped bank-response error");
            check(reset_required[0] == expected_reset_required,
                  "bad response reset-required classification");
            check(fault_event_valid && fault_event_bank_mask == 2'b01 &&
                  fault_event_code == expected_status,
                  "bad response raises exact held fault event");
            @(negedge clk);
            lookup_rsp_ready = 1;
            fault_event_ready = 1;
            @(posedge clk);
            #1;
            lookup_rsp_ready = 0;
            fault_event_ready = 0;
        end
    endtask

    task set_exact_abort_bank0;
        input [15:0] close_tag;
        begin
            force_error_bank_mask = 2'b01;
            force_error_code = ERR_ABORTED;
            force_error_data_untrusted = 0;
            force_error_causal_producers_drained = 1;
            force_error_directory_generation = {16'd0, 16'd1};
            force_error_stage_ticket = {32'd0, TICKET0};
            force_error_content_handle = {32'd0, CONTENT0};
            force_error_physical_bank_generation = {32'd0, BANK_GEN0};
            force_error_cancellation_epoch = CANCEL0;
            force_error_tag = close_tag;
        end
    endtask

    // Exercise a lookup rejection or directory-result error that must never
    // escape onto either physical-bank request channel.  A fatal result also
    // has to raise the bank-scoped event independently of event backpressure.
    task issue_lookup_error_no_bank;
        input bank;
        input kind;
        input [9:0] source_index;
        input [5:0] row_tile;
        input membership_validated;
        input [7:0] expected_status;
        input expected_fatal;
        input [15:0] user_tag;
        integer saw_bank_request;
        begin
            auto_bank_responder = 0;
            bank0_rd_req_ready = 0;
            bank1_rd_req_ready = 0;
            lookup_rsp_ready = 0;
            fault_event_ready = 0;
            @(negedge clk);
            set_lookup(bank, kind, 0, source_index, row_tile, user_tag);
            lookup_res_compute_membership_validated = membership_validated;
            lookup_req_valid = 1;
            sampled_count = 0;
            timeout_count = 0;
            while (!sampled_count && timeout_count < 50) begin
                @(posedge clk);
                sampled_count = lookup_req_ready;
                #1;
                timeout_count = timeout_count + 1;
            end
            check(sampled_count, "error lookup request accepted");
            @(negedge clk);
            lookup_req_valid = 0;
            saw_bank_request = 0;
            timeout_count = 0;
            while (!lookup_rsp_valid && timeout_count < 50) begin
                @(posedge clk);
                #1;
                if (bank0_rd_req_valid || bank1_rd_req_valid)
                    saw_bank_request = 1;
                timeout_count = timeout_count + 1;
            end
            check(lookup_rsp_valid, "error lookup produces terminal response");
            check(!saw_bank_request && !bank0_rd_req_valid &&
                  !bank1_rd_req_valid,
                  "rejected lookup never issues a physical-bank read");
            check(lookup_rsp_status == expected_status &&
                  lookup_rsp_fatal == expected_fatal,
                  "error lookup status and severity");
            if (lookup_rsp_hit || (lookup_rsp_weight_data != 0) ||
                (lookup_rsp_slot_base != 0) ||
                (lookup_rsp_weight_addr != 0))
                $display("ERROR_LOOKUP_PAYLOAD tag=%h status=%h hit=%b data=%h slot=%h addr=%h",
                         user_tag, lookup_rsp_status, lookup_rsp_hit,
                         lookup_rsp_weight_data, lookup_rsp_slot_base,
                         lookup_rsp_weight_addr);
            check(!lookup_rsp_hit && lookup_rsp_weight_data == 0 &&
                  lookup_rsp_slot_base == 0 && lookup_rsp_weight_addr == 0,
                  "error lookup zeros every authorizing payload field");
            if (expected_fatal) begin
                wait_fault_materialized(bank, 1);
                check(fault_event_valid &&
                      fault_event_bank_mask == (bank ? 2'b10 : 2'b01) &&
                      fault_event_code == expected_status,
                      "fatal lookup raises exact bank-scoped event");
            end else begin
                check(!fault_event_valid,
                      "caller-local lookup rejection raises no fault event");
            end
            @(negedge clk);
            lookup_rsp_ready = 1;
            fault_event_ready = expected_fatal;
            @(posedge clk);
            #1;
            lookup_rsp_ready = 0;
            fault_event_ready = 0;
        end
    endtask

    // Observe both sides of the registered descriptor-install overlay.  On
    // the CLAIM commit edge the architectural outputs already expose the new
    // descriptor, while the deliberately poisoned physical payload remains
    // old until the following unconditional cleanup edge.
    task test_deferred_claim_install;
        input bank;
        input [15:0] tag;
        begin
            pulse_reset;
            scrub_one(bank, tag);
            @(negedge clk);
            dut.committed_count_q[bank] = 10'd9;
            dut.image_epoch_q[bank] = 32'hdead_1000 + bank;
            dut.stage_id_q[bank] = 4'he;
            dut.stage_ticket_q[bank] = 32'hdead_2000 + bank;
            dut.logical_branch_q[bank] = 2'b11;
            dut.context_generation_q[bank] = 32'hdead_3000 + bank;
            dut.content_handle_q[bank] = 32'hdead_4000 + bank;
            dut.physical_bank_generation_q[bank] =
                32'hdead_5000 + bank;
            dut.cancellation_epoch_q[bank] = 32'hdead_6000 + bank;
            dut.matrix_mask_q[bank] = 2'b01;
            dut.matrix0_binding_token_q[bank] = 32'hdead_7000 + bank;
            dut.matrix1_binding_token_q[bank] = 32'hdead_8000 + bank;
            dut.matrix0_source_count_q[bank] = 10'd7;
            dut.matrix1_source_count_q[bank] = 10'd8;
            dut.matrix0_row_tile_count_q[bank] = 6'd4;
            dut.matrix1_row_tile_count_q[bank] = 6'd5;
            #1;
            check(directory_committed_source_count[bank*10 +: 10] == 10'd9,
                  "pre-claim stale physical count is externally observable");

            set_new_descriptor(bank);
            mgmt_req_expected_directory_generation = 0;
            mgmt_req_expected_content_handle = 0;
            mgmt_req_expected_stage_ticket = 0;
            mgmt_req_expected_physical_bank_generation = 0;
            mgmt_req_external_safe = 1;
            mgmt_rsp_ready = 0;
            mgmt_req_opcode = OP_CLAIM_FRESH;
            mgmt_req_bank_mask = bank ? 2'b10 : 2'b01;
            mgmt_req_tag = tag + 1'b1;
            mgmt_req_valid = 1;
            while (!mgmt_req_ready) @(negedge clk);
            @(posedge clk);
            #1;
            @(negedge clk);
            mgmt_req_valid = 0;
            clear_new_descriptor;
            timeout_count = 0;
            while (!mgmt_rsp_valid && timeout_count < 20) begin
                @(posedge clk);
                #1;
                timeout_count = timeout_count + 1;
            end
            check(mgmt_rsp_valid && mgmt_rsp_status == STATUS_OK &&
                  directory_state[bank*3 +: 3] == ST_LOADING,
                  "fresh claim reaches registered descriptor commit edge");
            check(dut.descriptor_install_pending_q[bank] &&
                  dut.descriptor_install_claim_q[bank],
                  "fresh claim owns deferred descriptor-install slot");
            check(dut.committed_count_q[bank] == 10'd9 &&
                  dut.generation_q[bank] == 0 &&
                  dut.stage_ticket_q[bank] == (32'hdead_2000 + bank) &&
                  dut.content_handle_q[bank] == (32'hdead_4000 + bank),
                  "claim commit edge has not overwritten physical descriptor");
            check(directory_committed_source_count[bank*10 +: 10] == 0 &&
                  directory_generation[bank*16 +: 16] == 16'd1 &&
                  directory_image_epoch[bank*32 +: 32] == IMAGE_EPOCH &&
                  directory_stage_id[bank*4 +: 4] == 4'd1 &&
                  directory_stage_ticket[bank*32 +: 32] ==
                      (bank ? TICKET1 : TICKET0) &&
                  directory_logical_branch[bank*2 +: 2] ==
                      (bank ? 2'd2 : 2'd1),
                  "claim commit edge exposes effective base identity");
            check(directory_context_generation[bank*32 +: 32] ==
                      (bank ? CONTEXT1 : CONTEXT0) &&
                  directory_content_handle[bank*32 +: 32] ==
                      (bank ? CONTENT1 : CONTENT0) &&
                  directory_physical_bank_generation[bank*32 +: 32] ==
                      (bank ? BANK_GEN1 : BANK_GEN0) &&
                  directory_cancellation_epoch[bank*32 +: 32] ==
                      (bank ? CANCEL1 : CANCEL0),
                  "claim commit edge exposes effective lease identity");
            check(directory_matrix_mask[bank*2 +: 2] == 2'b11 &&
                  directory_matrix0_binding_token[bank*32 +: 32] ==
                      (bank ? BIND10 : BIND00) &&
                  directory_matrix1_binding_token[bank*32 +: 32] ==
                      (bank ? BIND11 : BIND01),
                  "claim commit edge exposes effective matrix bindings");
            check(directory_matrix0_source_count[bank*10 +: 10] == 10'd320 &&
                  directory_matrix1_source_count[bank*10 +: 10] == 10'd320 &&
                  directory_matrix0_row_tile_count[bank*6 +: 6] == 6'd20 &&
                  directory_matrix1_row_tile_count[bank*6 +: 6] == 6'd20,
                  "claim commit edge exposes effective matrix geometry");
            check(!(dut.descriptor_install_pending_q[bank] &&
                    dut.descriptor_install_claim_q[bank] &&
                    dut.pub_commit_now &&
                    (dut.pub_exec_bank_q == bank)),
                  "fresh descriptor install cannot overlap publication commit");

            @(posedge clk);
            #1;
            check(mgmt_rsp_valid &&
                  !dut.descriptor_install_pending_q[bank] &&
                  !dut.descriptor_install_claim_q[bank],
                  "descriptor install completes on following edge");
            check(dut.committed_count_q[bank] == 0 &&
                  dut.generation_q[bank] == 16'd1 &&
                  dut.image_epoch_q[bank] == IMAGE_EPOCH &&
                  dut.stage_id_q[bank] == 4'd1 &&
                  dut.stage_ticket_q[bank] ==
                      (bank ? TICKET1 : TICKET0) &&
                  dut.content_handle_q[bank] ==
                      (bank ? CONTENT1 : CONTENT0),
                  "following edge durably copies fresh physical descriptor");
            check(dut.physical_bank_generation_q[bank] ==
                      (bank ? BANK_GEN1 : BANK_GEN0) &&
                  dut.cancellation_epoch_q[bank] ==
                      (bank ? CANCEL1 : CANCEL0) &&
                  dut.matrix0_source_count_q[bank] == 10'd320 &&
                  dut.matrix1_source_count_q[bank] == 10'd320 &&
                  dut.matrix0_row_tile_count_q[bank] == 6'd20 &&
                  dut.matrix1_row_tile_count_q[bank] == 6'd20,
                  "following edge durably copies fresh lease geometry");
            @(negedge clk);
            mgmt_rsp_ready = 1;
            @(posedge clk);
            #1;
            mgmt_rsp_ready = 0;
        end
    endtask

    // Start a fresh claim and return on its descriptor-publication edge with
    // the successful management response held and the physical copy pending.
    task begin_claim_hold_at_commit;
        input bank;
        input [15:0] tag;
        begin
            set_new_descriptor(bank);
            mgmt_req_expected_directory_generation = 0;
            mgmt_req_expected_content_handle = 0;
            mgmt_req_expected_stage_ticket = 0;
            mgmt_req_expected_physical_bank_generation = 0;
            mgmt_req_external_safe = 1;
            mgmt_rsp_ready = 0;
            mgmt_req_opcode = OP_CLAIM_FRESH;
            mgmt_req_bank_mask = bank ? 2'b10 : 2'b01;
            mgmt_req_tag = tag;
            mgmt_req_valid = 1;
            while (!mgmt_req_ready) @(negedge clk);
            @(posedge clk);
            #1;
            @(negedge clk);
            mgmt_req_valid = 0;
            clear_new_descriptor;
            timeout_count = 0;
            while (!mgmt_rsp_valid && timeout_count < 20) begin
                @(posedge clk);
                #1;
                timeout_count = timeout_count + 1;
            end
            check(mgmt_rsp_valid && mgmt_rsp_status == STATUS_OK &&
                  mgmt_rsp_tag == tag &&
                  dut.descriptor_install_pending_q[bank],
                  "claim helper returns on deferred-install commit edge");
        end
    endtask

    // Acceptance-order scoreboard used for the 1,000-cycle II=1 and random
    // backpressure tests.  Repeated user tags are intentionally common.
    always @(posedge clk) begin
        if (!rst_n) begin
            expected_head = 0;
            expected_tail = 0;
            accepted_count = 0;
            response_count = 0;
        end else if (scoreboard_enable) begin
            if (lookup_req_valid && lookup_req_ready) begin
                expected_tag[expected_tail] = lookup_req_user_tag;
                expected_bank[expected_tail] = lookup_res_selected_bank_id;
                if (lookup_res_selected_bank_id)
                    expected_addr[expected_tail] = 13'd1000 + lookup_req_row_tile;
                else
                    expected_addr[expected_tail] = 13'd8172 + lookup_req_row_tile;
                expected_data[expected_tail] = bank_data_pattern(
                    lookup_res_selected_bank_id, expected_addr[expected_tail]);
                expected_tail = expected_tail + 1;
                accepted_count = accepted_count + 1;
            end
            if (lookup_rsp_valid && lookup_rsp_ready) begin
                check(expected_head < expected_tail,
                      "scoreboard response without accepted request");
                check(lookup_rsp_status == STATUS_OK, "scoreboard response status");
                check(lookup_rsp_hit, "scoreboard compute response must hit");
                check(lookup_rsp_user_tag == expected_tag[expected_head],
                      "strict global user-tag order");
                check(lookup_rsp_selected_bank_id == expected_bank[expected_head],
                      "strict global selected-bank order");
                check(lookup_rsp_weight_addr == expected_addr[expected_head],
                      "scoreboard word address");
                check(lookup_rsp_weight_data == expected_data[expected_head],
                      "scoreboard weight data");
                expected_head = expected_head + 1;
                response_count = response_count + 1;
            end
        end
    end

    initial begin
        clk = 0;
        rst_n = 0;
        failures = 0;
        checks = 0;
        timeout_count = 0;
        scoreboard_enable = 0;
        auto_bank_responder = 1;
        cycle_trace_enable = 0;
        cycle_trace_index = 0;
        seed = 32'h50d1_0003;
        random_delay_enable = 0;
        tb_cycle = 0;
        request_cycle = 0;
        measured_scrub_cycles = -1;
        measured_scrub_accept_to_response_cycles = -1;
        scrub_measure_active = 0;
        scrub_write_count0 = 0;
        scrub_write_count1 = 0;
        scrub_sequence_errors0 = 0;
        scrub_sequence_errors1 = 0;
        measure_compute_active = 0;
        measure_compute_accept_cycle = 0;
        measured_compute_bank_issue_cycles = -1;
        measured_compute_response_valid_cycles = -1;
        measured_compute_terminal_cycles = -1;
        measured_ii_start_cycle = 0;
        measured_ii_start_accepts = 0;
        measured_ii_window_cycles = 0;
        measured_ii_accepts = 0;
        measured_bank0_ii_window_cycles = 0;
        measured_bank0_ii_accepts = 0;
        measured_bank1_ii_window_cycles = 0;
        measured_bank1_ii_accepts = 0;
        directed_phase = 0;
        clear_inputs;
        mgmt_rsp_ready = 0;
        force_error_rsp_ready = 0;
        publish_rsp_ready = 0;
        lookup_rsp_ready = 0;
        fault_event_ready = 0;
        bank0_rd_req_ready = 1;
        bank1_rd_req_ready = 1;
        bank0_rd_rsp_valid = 0;
        bank1_rd_rsp_valid = 0;
        bank0_rd_rsp_data = 0;
        bank1_rd_rsp_data = 0;
        bank0_rd_rsp_addr = 0;
        bank1_rd_rsp_addr = 0;
        bank0_rd_rsp_generation = 0;
        bank1_rd_rsp_generation = 0;
        bank0_rd_rsp_lease_owner_ticket = 0;
        bank1_rd_rsp_lease_owner_ticket = 0;
        bank0_rd_rsp_tag = 0;
        bank1_rd_rsp_tag = 0;
        bank0_rd_rsp_status = 0;
        bank1_rd_rsp_status = 0;

        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
        #1;
        check(directory_state == {ST_INVALID, ST_INVALID}, "reset state invalid");
        check(directory_scrub_required == 2'b11, "reset requires both scrubs");
        check(directory_quiescent, "reset directory quiescent");
        check(local_error_valid == 0 && local_error_code == 0 &&
              local_error_source == 0 && local_error_detail == 0,
              "reset clears every local error output field");

        // RAM payload is not reset.  Make this observable before physical scrub.
        @(negedge clk);
        dut.directory_mem0[33] = 32'hdead_beef;
        dut.directory_mem1[999] = 32'hcafe_f00d;
        rst_n = 0;
        repeat (2) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
        #1;
        check(dut.directory_mem0[33] == 32'hdead_beef, "reset must not clear dir0 RAM");
        check(dut.directory_mem1[999] == 32'hcafe_f00d, "reset must not clear dir1 RAM");

        // A malformed management request still owns a held response position;
        // quiescence must remain low until that response retires.
        @(negedge clk);
        mgmt_req_valid = 1;
        mgmt_req_opcode = OP_ACTIVATE;
        mgmt_req_bank_mask = 2'b00;
        mgmt_req_tag = 16'h00e0;
        @(posedge clk);
        #1;
        @(negedge clk);
        mgmt_req_valid = 0;
        timeout_count = 0;
        while (!mgmt_rsp_valid && timeout_count < 20) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(mgmt_rsp_valid && mgmt_rsp_status == ERR_BAD_BANK_MASK,
              "malformed management gets held terminal error");
        check(!directory_quiescent,
              "held malformed management response prevents quiescence");
        repeat (3) begin
            @(posedge clk);
            #1;
            check(mgmt_rsp_valid && mgmt_rsp_status == ERR_BAD_BANK_MASK &&
                  mgmt_rsp_tag == 16'h00e0,
                  "malformed management response stable under stall");
            check(!directory_quiescent,
                  "malformed response stall remains non-quiescent");
        end
        @(negedge clk);
        mgmt_rsp_ready = 1;
        @(posedge clk);
        #1;
        mgmt_rsp_ready = 0;
        check(directory_quiescent,
              "malformed response retirement restores quiescence");

        // Malformed management requests receive one terminal response and do
        // not mutate physical authority.
        mgmt_req_external_safe = 1;
        send_mgmt(4'hf, 2'b01, ERR_BAD_OPCODE, 16'h00f0);
        mgmt_req_new_image_epoch = IMAGE_EPOCH;
        mgmt_req_external_safe = 0;
        send_mgmt(OP_SCRUB, 2'b01, ERR_EXTERNAL_UNSAFE, 16'h00f1);
        check(directory_state == {ST_INVALID, ST_INVALID},
              "rejected management leaves state unchanged");

        // Reset at every one of the 1,024 possible in-progress scrub write
        // positions.  Payload is intentionally not reset, while control must
        // always abandon progress and re-arm scrub_required.
        clear_new_descriptor;
        mgmt_req_expected_directory_generation = 0;
        mgmt_req_expected_content_handle = 0;
        mgmt_req_expected_stage_ticket = 0;
        mgmt_req_expected_physical_bank_generation = 0;
        mgmt_req_new_image_epoch = IMAGE_EPOCH;
        mgmt_req_external_safe = 1;
        mgmt_req_opcode = OP_SCRUB;
        mgmt_req_bank_mask = 2'b01;
        mgmt_req_tag = 16'h0100;
        for (scrub_cut = 0; scrub_cut < 1024; scrub_cut = scrub_cut + 1) begin
            @(negedge clk);
            mgmt_req_valid = 1;
            sampled_count = 0;
            while (!sampled_count) begin
                @(posedge clk);
                sampled_count = mgmt_req_ready;
                #1;
            end
            @(negedge clk);
            mgmt_req_valid = 0;
            repeat (scrub_cut + 1) @(posedge clk);
            @(negedge clk);
            rst_n = 0;
            @(posedge clk);
            #1;
            check(directory_state == {ST_INVALID, ST_INVALID},
                  "reset during scrub returns state to invalid");
            check(directory_scrub_required == 2'b11,
                  "reset during scrub re-arms both scrub requirements");
            check(!mgmt_rsp_valid && !management_busy,
                  "reset during scrub discards cross-reset management work");
            @(negedge clk);
            rst_n = 1;
            @(posedge clk);
            #1;
        end
        mgmt_req_bank_mask = 0;

        // SCRUB C0 collision: a target-bank response already present on the
        // acceptance edge is an orphan/current-authority fatal.  The request
        // still owns one terminal response, but it must never activate the
        // writer or clear scrub_required.
        pulse_reset;
        auto_bank_responder = 0;
        clear_new_descriptor;
        mgmt_req_expected_directory_generation = 0;
        mgmt_req_expected_content_handle = 0;
        mgmt_req_expected_stage_ticket = 0;
        mgmt_req_expected_physical_bank_generation = 0;
        mgmt_req_new_image_epoch = IMAGE_EPOCH;
        mgmt_req_external_safe = 1;
        scrub_write_count0 = 0;
        scrub_write_count1 = 0;
        scrub_sequence_errors0 = 0;
        scrub_sequence_errors1 = 0;
        scrub_measure_active = 1;
        @(negedge clk);
        mgmt_req_opcode = OP_SCRUB;
        mgmt_req_bank_mask = 2'b01;
        mgmt_req_tag = 16'h01c0;
        mgmt_req_valid = 1;
        bank0_rd_rsp_data = {128{1'b1}};
        bank0_rd_rsp_addr = 13'd0;
        bank0_rd_rsp_generation = 32'd0;
        bank0_rd_rsp_lease_owner_ticket = 32'd0;
        bank0_rd_rsp_tag = 16'h0003;
        bank0_rd_rsp_status = STATUS_OK;
        bank0_rd_rsp_valid = 1;
        @(posedge clk);
        sampled_count = mgmt_req_ready;
        #1;
        check(sampled_count,
              "C0 target orphan and SCRUB request collide on acceptance edge");
        request_cycle = tb_cycle;
        @(negedge clk);
        mgmt_req_valid = 0;
        mgmt_req_opcode = 4'hf;
        mgmt_req_bank_mask = 0;
        mgmt_req_new_image_epoch = 0;
        mgmt_req_external_safe = 0;
        mgmt_req_tag = 16'hfe3f;
        bank0_rd_rsp_valid = 0;
        scrub_measure_active = 0;
        check(scrub_write_count0 == 0 && scrub_write_count1 == 0,
              "C0 target orphan prevents every SCRUB write");
        wait_fault_materialized(0, 1);
        timeout_count = 0;
        while (!mgmt_rsp_valid && timeout_count < 20) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(mgmt_rsp_valid && mgmt_rsp_opcode == OP_SCRUB &&
              mgmt_rsp_tag == 16'h01c0 &&
              mgmt_rsp_status == ERR_INTERNAL_STATE,
              "C0 target orphan returns exact SCRUB fatal terminal");
        check(directory_state[2:0] == ST_INVALID &&
              directory_scrub_required[0] && reset_required[0],
              "C0 target orphan preserves invalid uninitialized authority");
        @(negedge clk);
        mgmt_rsp_ready = 1;
        fault_event_ready = 1;
        @(posedge clk);
        #1;
        mgmt_rsp_ready = 0;
        fault_event_ready = 0;

        // SCRUB C1 collision: address zero may complete its harmless zero
        // write on the discovery edge, but the active target is immediately
        // fenced and the accepted operation can never publish success.
        pulse_reset;
        auto_bank_responder = 0;
        start_scrub_no_wait(2'b01, 16'h01c1);
        check(dut.scrub_write0 &&
              directory_scrub_address[9:0] == 10'd0,
              "single-bank SCRUB presents address zero on C1");
        bank0_rd_rsp_data = {128{1'b1}};
        bank0_rd_rsp_addr = 13'd0;
        bank0_rd_rsp_generation = 32'd0;
        bank0_rd_rsp_lease_owner_ticket = 32'd0;
        bank0_rd_rsp_tag = 16'h0003;
        bank0_rd_rsp_status = STATUS_OK;
        bank0_rd_rsp_valid = 1;
        #1;
        check(!bank0_rd_rsp_ready,
              "C1 target orphan has no physical response owner");
        @(posedge clk);
        #1;
        check(scrub_write_count0 == 1 &&
              scrub_sequence_errors0 == 0 &&
              dut.directory_mem0[0] == 32'd0,
              "C1 collision commits only the address-zero scrub write");
        @(negedge clk);
        bank0_rd_rsp_valid = 0;
        wait_fault_materialized(0, 1);
        timeout_count = 0;
        while (!mgmt_rsp_valid && timeout_count < 20) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        scrub_measure_active = 0;
        check(mgmt_rsp_valid && mgmt_rsp_opcode == OP_SCRUB &&
              mgmt_rsp_tag == 16'h01c1 &&
              mgmt_rsp_status == ERR_INTERNAL_STATE,
              "C1 target orphan converts SCRUB to fatal terminal");
        check(scrub_write_count0 == 1 &&
              directory_state[2:0] == ST_ERROR &&
              directory_scrub_required[0] && reset_required[0],
              "C1 target orphan aborts before address one and poisons target");
        @(negedge clk);
        mgmt_rsp_ready = 1;
        fault_event_ready = 1;
        @(posedge clk);
        #1;
        mgmt_rsp_ready = 0;
        fault_event_ready = 0;

        // A selected-bank orphan during a dual scrub aborts the all-or-none
        // operation.  Both address-zero writes may complete on C1, but
        // neither bank may be published as successfully scrubbed.
        pulse_reset;
        auto_bank_responder = 0;
        start_scrub_no_wait(2'b11, 16'h01d1);
        check(dut.scrub_write0 && dut.scrub_write1 &&
              directory_scrub_address[9:0] == 10'd0 &&
              directory_scrub_address[19:10] == 10'd0,
              "dual-bank SCRUB presents both address-zero writes on C1");
        bank1_rd_rsp_data = {128{1'b1}};
        bank1_rd_rsp_addr = 13'd0;
        bank1_rd_rsp_generation = 32'd0;
        bank1_rd_rsp_lease_owner_ticket = 32'd0;
        bank1_rd_rsp_tag = 16'h0003;
        bank1_rd_rsp_status = STATUS_OK;
        bank1_rd_rsp_valid = 1;
        #1;
        check(!bank1_rd_rsp_ready,
              "dual-SCRUB selected orphan has no physical response owner");
        @(posedge clk);
        #1;
        check(scrub_write_count0 == 1 && scrub_write_count1 == 1 &&
              scrub_sequence_errors0 == 0 && scrub_sequence_errors1 == 0,
              "dual-SCRUB collision commits exactly both C1 zero writes");
        @(negedge clk);
        bank1_rd_rsp_valid = 0;
        wait_fault_materialized(1, 1);
        timeout_count = 0;
        while (!mgmt_rsp_valid && timeout_count < 20) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        scrub_measure_active = 0;
        check(mgmt_rsp_valid && mgmt_rsp_opcode == OP_SCRUB &&
              mgmt_rsp_tag == 16'h01d1 &&
              mgmt_rsp_status == ERR_INTERNAL_STATE,
              "selected orphan returns one dual-SCRUB fatal terminal");
        check(directory_scrub_required == 2'b11 &&
              directory_state[2:0] == ST_INVALID &&
              directory_state[5:3] == ST_ERROR && reset_required[1],
              "dual-SCRUB selected fault leaves neither bank initialized");
        @(negedge clk);
        mgmt_rsp_ready = 1;
        fault_event_ready = 1;
        @(posedge clk);
        #1;
        mgmt_rsp_ready = 0;
        fault_event_ready = 0;

        // The shallow live veto is selected-bank-local.  An orphan response
        // on bank1 must poison and fence bank1, but a bank0-only scrub still
        // writes the exact 0..1023 sequence and publishes success at C1024.
        pulse_reset;
        auto_bank_responder = 0;
        start_scrub_no_wait(2'b01, 16'h01e0);
        timeout_count = 0;
        while ((!dut.scrub_write0 ||
                (directory_scrub_address[9:0] != 10'd16)) &&
               timeout_count < 32) begin
            @(negedge clk);
            timeout_count = timeout_count + 1;
        end
        check(dut.scrub_write0 &&
              directory_scrub_address[9:0] == 10'd16,
              "single-bank SCRUB reaches directed unselected-fault edge");
        bank1_rd_rsp_data = {128{1'b1}};
        bank1_rd_rsp_addr = 13'd0;
        bank1_rd_rsp_generation = 32'd0;
        bank1_rd_rsp_lease_owner_ticket = 32'd0;
        bank1_rd_rsp_tag = 16'h0003;
        bank1_rd_rsp_status = STATUS_OK;
        bank1_rd_rsp_valid = 1;
        #1;
        check(!bank1_rd_rsp_ready && dut.scrub_write0,
              "unselected orphan does not veto target scrub write");
        @(posedge clk);
        #1;
        @(negedge clk);
        bank1_rd_rsp_valid = 0;
        wait_fault_materialized(1, 1);
        check(directory_scrub_busy[0] && !directory_scrub_busy[1],
              "unselected-bank fatal leaves selected scrub active");
        timeout_count = 0;
        while (!mgmt_rsp_valid && timeout_count < 1100) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        scrub_measure_active = 0;
        check(mgmt_rsp_valid && mgmt_rsp_opcode == OP_SCRUB &&
              mgmt_rsp_tag == 16'h01e0 && mgmt_rsp_status == STATUS_OK,
              "unselected-bank fatal cannot replace clean SCRUB success");
        check((tb_cycle - request_cycle) == 1024 &&
              scrub_write_count0 == 1024 && scrub_write_count1 == 0 &&
              scrub_sequence_errors0 == 0,
              "unselected fault preserves exact C1..C1024 address sequence");
        check(!directory_scrub_required[0] &&
              directory_last_scrubbed_image_epoch_valid[0] &&
              directory_last_scrubbed_image_epoch[31:0] == IMAGE_EPOCH &&
              directory_state[2:0] == ST_INVALID &&
              local_error_valid[1] && reset_required[1],
              "clean target publishes while unselected fault remains scoped");
        repeat (3) begin
            @(posedge clk);
            #1;
            check(mgmt_rsp_valid && mgmt_rsp_status == STATUS_OK &&
                  mgmt_rsp_tag == 16'h01e0 &&
                  fault_event_valid && fault_event_bank_mask == 2'b10 &&
                  fault_event_code == ERR_INTERNAL_STATE,
                  "SCRUB success and unselected fault stay stable under stall");
            check(scrub_write_count0 == 1024,
                  "held SCRUB response cannot restart serializer writes");
        end
        @(negedge clk);
        mgmt_rsp_ready = 1;
        fault_event_ready = 1;
        @(posedge clk);
        #1;
        mgmt_rsp_ready = 0;
        fault_event_ready = 0;

        // A first current-bank fast fault on the final scrub address cannot
        // be allowed to publish successful initialization.  The harmless
        // address-1023 zero write may complete on the discovery edge, then
        // the accepted SCRUB terminates fatally with scrub_required retained.
        pulse_reset;
        @(negedge clk);
        dut.directory_mem0[1023] = 32'hffff_ffff;
        scrub_write_count0 = 0;
        scrub_write_count1 = 0;
        scrub_sequence_errors0 = 0;
        scrub_sequence_errors1 = 0;
        scrub_measure_active = 1;
        clear_new_descriptor;
        mgmt_req_expected_directory_generation = 0;
        mgmt_req_expected_content_handle = 0;
        mgmt_req_expected_stage_ticket = 0;
        mgmt_req_expected_physical_bank_generation = 0;
        mgmt_req_new_image_epoch = IMAGE_EPOCH;
        mgmt_req_external_safe = 1;
        mgmt_req_opcode = OP_SCRUB;
        mgmt_req_bank_mask = 2'b01;
        mgmt_req_tag = 16'h01f0;
        mgmt_req_valid = 1;
        while (!mgmt_req_ready) @(negedge clk);
        @(posedge clk);
        #1;
        @(negedge clk);
        mgmt_req_valid = 0;
        timeout_count = 0;
        while ((!dut.scrub_write0 ||
                (directory_scrub_address[9:0] != 10'd1023)) &&
               timeout_count < 1100) begin
            @(negedge clk);
            timeout_count = timeout_count + 1;
        end
        check(dut.scrub_write0 &&
              directory_scrub_address[9:0] == 10'd1023,
              "fault test reaches active scrub address 1023 write edge");
        bank0_rd_rsp_data = {128{1'b1}};
        bank0_rd_rsp_addr = 13'd0;
        bank0_rd_rsp_generation = 32'd0;
        bank0_rd_rsp_lease_owner_ticket = 32'd0;
        bank0_rd_rsp_tag = 16'h0003;
        bank0_rd_rsp_status = STATUS_OK;
        bank0_rd_rsp_valid = 1;
        #1;
        check(!bank0_rd_rsp_ready && dut.scrub_write0,
              "final-address orphan fault preserves only harmless zero write");
        @(posedge clk);
        #1;
        check(dut.directory_mem0[1023] == 32'd0 &&
              scrub_write_count0 == 1024 &&
              scrub_sequence_errors0 == 0,
              "fault discovery edge commits exactly the last scrub zero");
        check(!mgmt_rsp_valid && directory_scrub_required[0],
              "fast fault suppresses same-edge SCRUB success publication");
        @(negedge clk);
        bank0_rd_rsp_valid = 0;
        wait_fault_materialized(0, 1);
        timeout_count = 0;
        while (!mgmt_rsp_valid && timeout_count < 20) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(mgmt_rsp_valid && mgmt_rsp_opcode == OP_SCRUB &&
              mgmt_rsp_tag == 16'h01f0 &&
              mgmt_rsp_status == ERR_INTERNAL_STATE,
              "final-address fault converts accepted SCRUB to fatal terminal");
        check(directory_state[2:0] == ST_ERROR &&
              directory_scrub_required[0] && reset_required[0],
              "faulted final scrub remains uninitialized and reset-required");
        scrub_measure_active = 0;
        repeat (3) begin
            @(posedge clk);
            #1;
            check(mgmt_rsp_valid && mgmt_rsp_opcode == OP_SCRUB &&
                  mgmt_rsp_tag == 16'h01f0 &&
                  mgmt_rsp_status == ERR_INTERNAL_STATE,
                  "C1024 fatal SCRUB response remains stable under stall");
            check(fault_event_valid && fault_event_bank_mask == 2'b01 &&
                  fault_event_code == ERR_INTERNAL_STATE,
                  "C1024 fault event remains stable under stall");
            check(scrub_write_count0 == 1024,
                  "held C1024 terminal cannot duplicate final scrub write");
        end
        @(negedge clk);
        mgmt_rsp_ready = 1;
        fault_event_ready = 1;
        @(posedge clk);
        #1;
        mgmt_rsp_ready = 0;
        fault_event_ready = 0;
        auto_bank_responder = 1;

        pulse_reset;
        scrub_both;
        for (address = 0; address < 1024; address = address + 1) begin
            check(dut.directory_mem0[address] == 32'h0000_0000,
                  "scrub clears every bank0 address");
            check(dut.directory_mem1[address] == 32'h0000_0000,
                  "scrub clears every bank1 address");
        end

        claim_bank(0);
        claim_bank(1);

        publish_one(0, 0, 10'd0, 13'd8172, STATUS_OK, 1, 16'h1000);
        publish_one(0, 0, 10'd1, 13'd100, STATUS_OK, 1, 16'h1001);
        publish_one(0, 1, 10'd1, 13'd200, STATUS_OK, 1, 16'h1002);
        publish_one(1, 0, 10'd0, 13'd1000, STATUS_OK, 1, 16'h1100);
        publish_one(1, 0, 10'd1, 13'd1020, STATUS_OK, 1, 16'h1101);
        publish_one(1, 0, 10'd7, 13'd700, STATUS_OK, 1, 16'h1107);

        // Exact duplicate does not commit or poison.
        publish_one(0, 0, 10'd1, 13'd100,
                    ERR_DUPLICATE_PUBLICATION, 0, 16'h1200);
        check(!local_error_valid[0], "duplicate publication is caller-local");

        // Same-directory lookup wins over a simultaneous publication; only
        // the actually handshaken request may later respond.
        @(negedge clk);
        set_lookup(0, 0, 0, 1, 0, 16'h1800);
        set_publication(0, 0, 2, 13'd120);
        lookup_req_valid = 1;
        publish_req_valid = 1;
        #1;
        check(lookup_req_ready, "same-bank lookup receives priority");
        check(!publish_req_ready, "same-bank publication loses arbitration");
        @(posedge clk);
        #1;
        lookup_req_valid = 0;
        publish_req_valid = 0;
        timeout_count = 0;
        while (!lookup_rsp_valid && timeout_count < 30) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(lookup_rsp_valid && lookup_rsp_status == STATUS_OK && lookup_rsp_hit,
              "same-bank arbitration accepted lookup completes once");
        check(!publish_rsp_valid, "losing publication produces no response");
        @(negedge clk);
        lookup_rsp_ready = 1;
        @(posedge clk);
        #1;
        lookup_rsp_ready = 0;

        // Different physical directories genuinely run lookup and publication
        // in parallel on the same edge.
        @(negedge clk);
        set_lookup(0, 0, 0, 1, 0, 16'h1810);
        set_publication(1, 0, 2, 13'd1040);
        publish_req_tag = 16'h1811;
        lookup_req_valid = 1;
        publish_req_valid = 1;
        #1;
        check(lookup_req_ready && publish_req_ready,
              "active-read inactive-publication cross-bank concurrency");
        @(posedge clk);
        #1;
        lookup_req_valid = 0;
        publish_req_valid = 0;
        timeout_count = 0;
        while ((!lookup_rsp_valid || !publish_rsp_valid) && timeout_count < 30) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(lookup_rsp_valid && lookup_rsp_status == STATUS_OK,
              "cross-bank lookup response");
        check(publish_rsp_valid && publish_rsp_status == STATUS_OK &&
              publish_rsp_committed,
              "cross-bank publication response");
        @(negedge clk);
        lookup_rsp_ready = 1;
        publish_rsp_ready = 1;
        @(posedge clk);
        #1;
        lookup_rsp_ready = 0;
        publish_rsp_ready = 0;

        // Prove the symmetric port case as a separate edge: bank1 lookup and
        // bank0 publication must both fire and complete without either RAM
        // port stealing the other bank's operation.
        @(negedge clk);
        set_lookup(1, 0, 0, 2, 0, 16'h1812);
        set_publication(0, 0, 2, 13'd120);
        publish_req_tag = 16'h1813;
        lookup_req_valid = 1;
        publish_req_valid = 1;
        #1;
        check(lookup_req_ready && publish_req_ready,
              "inactive-publication active-read reverse-bank concurrency");
        @(posedge clk);
        #1;
        lookup_req_valid = 0;
        publish_req_valid = 0;
        timeout_count = 0;
        while ((!lookup_rsp_valid || !publish_rsp_valid) &&
               timeout_count < 30) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(lookup_rsp_valid && lookup_rsp_status == STATUS_OK &&
              lookup_rsp_selected_bank_id && lookup_rsp_hit &&
              lookup_rsp_slot_base == 13'd1040,
              "reverse cross-bank lookup returns selected bank1 entry");
        check(publish_rsp_valid && publish_rsp_status == STATUS_OK &&
              !publish_rsp_bank_id && publish_rsp_committed &&
              publish_rsp_slot_base == 13'd120,
              "reverse cross-bank publication commits bank0 entry");
        @(negedge clk);
        lookup_rsp_ready = 1;
        publish_rsp_ready = 1;
        @(posedge clk);
        #1;
        lookup_rsp_ready = 0;
        publish_rsp_ready = 0;

        // Probe semantics and selected-bank-only behavior.  Bank1 contains key
        // seven; selected bank0 must still miss and must never issue bank reads.
        issue_lookup_wait(0, 0, 0, 10'd7, 0, 16'h2000,
                          STATUS_OK, 0, 0, 0);
        issue_lookup_wait(1, 0, 0, 10'd7, 0, 16'h2001,
                          STATUS_OK, 1, 13'd700, 0);

        clear_new_descriptor;
        set_expected_identity(0);
        mgmt_req_external_safe = 1;
        send_mgmt(OP_PUBLISH_READY, 2'b01, STATUS_OK, 16'h3000);
        set_expected_identity(1);
        mgmt_req_external_safe = 1;
        send_mgmt(OP_PUBLISH_READY, 2'b10, STATUS_OK, 16'h3001);
        set_expected_identity(0);
        mgmt_req_external_safe = 1;
        send_mgmt(OP_ACTIVATE, 2'b01, STATUS_OK, 16'h3010);
        set_expected_identity(1);
        mgmt_req_external_safe = 1;
        send_mgmt(OP_ACTIVATE, 2'b10, STATUS_OK, 16'h3011);
        check(directory_state == {ST_ACTIVE, ST_ACTIVE}, "both directories active");

        issue_lookup_wait(0, 1, 0, 10'd0, 6'd19, 16'h4000,
                          STATUS_OK, 1, 13'd8172, 13'd8191);

        // No-stall sustained II=1.  Alternating selected banks and four
        // repeating user tags exercise global ordering independently of tags.
        scoreboard_enable = 1;
        lookup_rsp_ready = 1;
        @(negedge clk);
        measured_ii_start_cycle = tb_cycle;
        measured_ii_start_accepts = accepted_count;
        set_lookup(0, 1, 0, 0, 0, 0);
        lookup_req_valid = 1;
        for (address = 0; address < 1000; address = address + 1) begin
            set_lookup(address[0], 1, 0, 0, address % 20, address % 4);
            @(posedge clk);
            #1;
            check(lookup_req_ready, "no-stall compute accepted II must equal one");
            @(negedge clk);
        end
        lookup_req_valid = 0;
        measured_ii_window_cycles = tb_cycle - measured_ii_start_cycle;
        measured_ii_accepts = accepted_count - measured_ii_start_accepts;
        timeout_count = 0;
        while (response_count < accepted_count && timeout_count < 200) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(accepted_count == 1000, "exactly 1000 continuous accepts");
        check(response_count == accepted_count, "all II=1 requests respond");
        scoreboard_enable = 0;
        lookup_rsp_ready = 0;

        // Per-bank sustained windows exercise each physical endpoint's two
        // response positions and same-edge rollover independently.  The
        // alternating-bank test above cannot prove either single bank can
        // sustain the frozen PE's one-word-per-clock demand by itself.
        scoreboard_enable = 1;
        lookup_rsp_ready = 1;
        bank0_rd_req_ready = 1;
        bank1_rd_req_ready = 1;
        @(negedge clk);
        measured_ii_start_cycle = tb_cycle;
        measured_ii_start_accepts = accepted_count;
        lookup_req_valid = 1;
        for (address = 0; address < 1000; address = address + 1) begin
            set_lookup(0, 1, 0, 0, address % 20, address % 4);
            @(posedge clk);
            #1;
            check(lookup_req_ready,
                  "bank0 no-stall compute accepted II must equal one");
            @(negedge clk);
        end
        lookup_req_valid = 0;
        measured_bank0_ii_window_cycles =
            tb_cycle - measured_ii_start_cycle;
        measured_bank0_ii_accepts =
            accepted_count - measured_ii_start_accepts;
        timeout_count = 0;
        while (response_count < accepted_count && timeout_count < 200) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(measured_bank0_ii_window_cycles == 1000 &&
              measured_bank0_ii_accepts == 1000,
              "bank0 sustains 1000 accepted requests in 1000 cycles");
        check(response_count == accepted_count,
              "bank0 sustained window drains every response");
        scoreboard_enable = 0;
        lookup_rsp_ready = 0;

        scoreboard_enable = 1;
        lookup_rsp_ready = 1;
        @(negedge clk);
        measured_ii_start_cycle = tb_cycle;
        measured_ii_start_accepts = accepted_count;
        lookup_req_valid = 1;
        for (address = 0; address < 1000; address = address + 1) begin
            set_lookup(1, 1, 0, 0, address % 20, address % 4);
            @(posedge clk);
            #1;
            check(lookup_req_ready,
                  "bank1 no-stall compute accepted II must equal one");
            @(negedge clk);
        end
        lookup_req_valid = 0;
        measured_bank1_ii_window_cycles =
            tb_cycle - measured_ii_start_cycle;
        measured_bank1_ii_accepts =
            accepted_count - measured_ii_start_accepts;
        timeout_count = 0;
        while (response_count < accepted_count && timeout_count < 200) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(measured_bank1_ii_window_cycles == 1000 &&
              measured_bank1_ii_accepts == 1000,
              "bank1 sustains 1000 accepted requests in 1000 cycles");
        check(response_count == accepted_count,
              "bank1 sustained window drains every response");
        scoreboard_enable = 0;
        lookup_rsp_ready = 0;

        // Deliberately let the younger bank-1 physical response arrive before
        // the older bank-0 response.  It must stay held with ready low until
        // the aggregate head retires; opaque user tags are equal.
        scoreboard_enable = 1;
        auto_bank_responder = 0;
        bank0_rd_req_ready = 0;
        bank1_rd_req_ready = 0;
        lookup_rsp_ready = 1;
        issue_lookup_no_wait(0, 1, 0, 0, 6'd3, 16'h5151);
        issue_lookup_no_wait(1, 1, 0, 0, 6'd4, 16'h5151);
        timeout_count = 0;
        while (!bank0_rd_req_valid && timeout_count < 50) begin
            @(negedge clk);
            timeout_count = timeout_count + 1;
        end
        check(bank0_rd_req_valid, "older bank0 request must become valid");
        manual_addr0 = bank0_rd_req_addr;
        manual_generation0 = bank0_rd_req_generation;
        manual_ticket0 = bank0_rd_req_lease_owner_ticket;
        manual_tag0 = bank0_rd_req_tag;
        bank0_rd_req_ready = 1;
        @(posedge clk);
        #1;
        @(negedge clk);
        bank0_rd_req_ready = 0;
        timeout_count = 0;
        while (!bank1_rd_req_valid && timeout_count < 50) begin
            @(negedge clk);
            timeout_count = timeout_count + 1;
        end
        check(bank1_rd_req_valid, "younger bank1 request must issue after older fire");
        manual_addr1 = bank1_rd_req_addr;
        manual_generation1 = bank1_rd_req_generation;
        manual_ticket1 = bank1_rd_req_lease_owner_ticket;
        manual_tag1 = bank1_rd_req_tag;
        bank1_rd_req_ready = 1;
        @(posedge clk);
        #1;
        @(negedge clk);
        bank1_rd_req_ready = 0;
        bank1_rd_rsp_data = bank_data_pattern(1, manual_addr1);
        bank1_rd_rsp_addr = manual_addr1;
        bank1_rd_rsp_generation = manual_generation1;
        bank1_rd_rsp_lease_owner_ticket = manual_ticket1;
        bank1_rd_rsp_tag = manual_tag1;
        bank1_rd_rsp_status = STATUS_OK;
        bank1_rd_rsp_valid = 1;
        repeat (3) begin
            @(posedge clk);
            #1;
            check(bank1_rd_rsp_valid && !bank1_rd_rsp_ready,
                  "younger bank response must remain held behind global head");
        end
        @(negedge clk);
        bank0_rd_rsp_data = bank_data_pattern(0, manual_addr0);
        bank0_rd_rsp_addr = manual_addr0;
        bank0_rd_rsp_generation = manual_generation0;
        bank0_rd_rsp_lease_owner_ticket = manual_ticket0;
        bank0_rd_rsp_tag = manual_tag0;
        bank0_rd_rsp_status = STATUS_OK;
        bank0_rd_rsp_valid = 1;
        #1;
        check(bank0_rd_rsp_ready, "oldest bank response must be selected");
        @(posedge clk);
        #1;
        @(negedge clk);
        bank0_rd_rsp_valid = 0;
        timeout_count = 0;
        while (!bank1_rd_rsp_ready && timeout_count < 20) begin
            @(negedge clk);
            timeout_count = timeout_count + 1;
        end
        check(bank1_rd_rsp_ready, "younger response released after old head retires");
        @(posedge clk);
        #1;
        @(negedge clk);
        bank1_rd_rsp_valid = 0;
        timeout_count = 0;
        while (response_count < accepted_count && timeout_count < 50) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(response_count == accepted_count,
              "unequal-bank-latency responses preserve global order");
        auto_bank_responder = 1;
        bank0_rd_req_ready = 1;
        bank1_rd_req_ready = 1;
        scoreboard_enable = 0;
        lookup_rsp_ready = 0;

        // Fixed-seed request, bank-request, and logical-response
        // backpressure.  Input payload advances only after an actual fire.
        scoreboard_enable = 1;
        random_stall_count = 0;
        sampled_count = accepted_count + 250;
        @(negedge clk);
        cycle_trace_index = 0;
        cycle_trace_enable = 1;
        $display("TRACE_PSD_BEGIN seed=50d10003");
        set_lookup(0, 1, 0, 0, 0, 0);
        lookup_req_valid = 1;
        while (accepted_count < sampled_count) begin
            lookup_rsp_ready = $random(seed) & 1;
            bank0_rd_req_ready = (($random(seed) & 3) != 0) &&
                                 (!bank0_rd_rsp_valid || bank0_rd_rsp_ready);
            bank1_rd_req_ready = (($random(seed) & 3) != 0) &&
                                 (!bank1_rd_rsp_valid || bank1_rd_rsp_ready);
            if (!lookup_req_ready)
                random_stall_count = random_stall_count + 1;
            @(posedge clk);
            #1;
            @(negedge clk);
            set_lookup(accepted_count[0], 1, 0, 0,
                       accepted_count % 20, accepted_count % 8);
        end
        lookup_req_valid = 0;
        lookup_rsp_ready = 1;
        bank0_rd_req_ready = 1;
        bank1_rd_req_ready = 1;
        timeout_count = 0;
        while (response_count < accepted_count && timeout_count < 200) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(random_stall_count > 0, "random test must exercise backpressure");
        check(response_count == accepted_count,
              "fixed-seed randomized scoreboard drains every response");
        cycle_trace_enable = 0;
        $display("TRACE_PSD_END cycles=%0d", cycle_trace_index);
        scoreboard_enable = 0;
        lookup_rsp_ready = 0;

        // Three credits fill under logical-response backpressure; a fourth
        // request must not fire and all held payload remains ordered.
        scoreboard_enable = 1;
        @(negedge clk);
        lookup_rsp_ready = 0;
        for (address = 0; address < 3; address = address + 1) begin
            set_lookup(address[0], 1, 0, 0, address, 16'h5500);
            lookup_req_valid = 1;
            timeout_count = 0;
            while (!lookup_req_ready && timeout_count < 20) begin
                @(negedge clk);
                timeout_count = timeout_count + 1;
            end
            @(posedge clk);
            #1;
            @(negedge clk);
            lookup_req_valid = 0;
        end
        set_lookup(0, 1, 0, 0, 4, 16'h5500);
        lookup_req_valid = 1;
        repeat (3) begin
            @(posedge clk);
            #1;
            check(!lookup_req_ready, "fourth lookup must be backpressured");
        end
        @(negedge clk);
        lookup_req_valid = 0;
        lookup_rsp_ready = 1;
        timeout_count = 0;
        while (response_count < accepted_count && timeout_count < 100) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(response_count == accepted_count, "three-credit responses drain");
        scoreboard_enable = 0;
        lookup_rsp_ready = 0;

        // A current-authority fatal fences admissions on the discovery edge;
        // the fence is independent of fault-event_ready.
        issue_lookup_wait(1, 1, 0, 10'd319, 0, 16'h6000,
                          ERR_COMPUTE_MISS, 0, 0, 0);
        wait_fault_materialized(1, 1);
        check(local_error_valid[1], "compute miss latches bank1 error");
        check(fault_event_valid, "compute miss creates held fault event");
        @(negedge clk);
        set_lookup(1, 1, 0, 0, 0, 16'h6001);
        lookup_req_valid = 1;
        set_publication(1, 0, 2, 1040);
        publish_req_valid = 1;
        repeat (3) begin
            @(posedge clk);
            #1;
            check(!lookup_req_ready, "fatal fence blocks selected lookup");
            check(!publish_req_ready, "fatal fence blocks selected publication");
        end
        @(negedge clk);
        lookup_req_valid = 0;
        publish_req_valid = 0;
        fault_event_ready = 1;
        @(posedge clk);
        #1;
        fault_event_ready = 0;

        // Close the poisoned bank and prove sticky first-fatal precedence over
        // the later explicit abort.  Exact CLEAR_ERROR must zero every local
        // error field, not merely clear valid.
        @(negedge clk);
        force_error_bank_mask = 2'b10;
        force_error_code = ERR_ABORTED;
        force_error_data_untrusted = 0;
        force_error_causal_producers_drained = 1;
        force_error_directory_generation = {16'd1, 16'd1};
        force_error_stage_ticket = {TICKET1, TICKET0};
        force_error_content_handle = {CONTENT1, CONTENT0};
        force_error_physical_bank_generation = {BANK_GEN1, BANK_GEN0};
        force_error_cancellation_epoch = CANCEL1;
        force_error_tag = 16'h6010;
        force_error_valid = 1;
        sampled_count = 0;
        while (!sampled_count) begin
            @(posedge clk);
            sampled_count = force_error_ready;
            #1;
        end
        @(negedge clk);
        force_error_valid = 0;
        timeout_count = 0;
        while (!force_error_rsp_valid && timeout_count < 100) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(force_error_rsp_valid && force_error_rsp_status == STATUS_OK,
              "poisoned-bank final close completes");
        check(force_error_rsp_code == ERR_COMPUTE_MISS,
              "sticky first fatal wins over later explicit abort");
        @(negedge clk);
        force_error_rsp_ready = 1;
        @(posedge clk);
        #1;
        force_error_rsp_ready = 0;
        check(directory_state[5:3] == ST_ERROR,
              "poisoned bank enters error after final close");

        clear_new_descriptor;
        mgmt_req_expected_directory_generation = 16'd1;
        mgmt_req_expected_content_handle = CONTENT1;
        mgmt_req_expected_stage_ticket = TICKET1;
        mgmt_req_expected_physical_bank_generation = BANK_GEN1;
        mgmt_req_external_safe = 1;
        send_mgmt(OP_CLEAR_ERROR, 2'b10, STATUS_OK, 16'h6011);
        check(!local_error_valid[1] && local_error_code[15:8] == 0 &&
              local_error_source[5:3] == 0 && local_error_detail[63:32] == 0,
              "CLEAR_ERROR zeros all bank1 local error fields");
        check(directory_scrub_required[1],
              "CLEAR_ERROR requires physical scrub before reuse");

        // Materialized success is immutable across final close.  Hold bank0's
        // logical response, close that exact lease, then verify the success is
        // not rewritten while the close waits for its terminal retirement.
        @(negedge clk);
        set_lookup(0, 1, 0, 0, 0, 16'h7000);
        lookup_req_valid = 1;
        while (!lookup_req_ready) @(negedge clk);
        @(posedge clk);
        #1;
        lookup_req_valid = 0;
        timeout_count = 0;
        while (!lookup_rsp_valid && timeout_count < 100) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(lookup_rsp_status == STATUS_OK, "pre-close response materialized success");
        check(lookup_rsp_weight_data == bank_data_pattern(0, 8172),
              "pre-close materialized data");
        @(negedge clk);
        force_error_bank_mask = 2'b01;
        force_error_code = ERR_ABORTED;
        force_error_data_untrusted = 0;
        force_error_causal_producers_drained = 1;
        force_error_directory_generation = {16'd1, 16'd1};
        force_error_stage_ticket = {TICKET1, TICKET0};
        force_error_content_handle = {CONTENT1, CONTENT0};
        force_error_physical_bank_generation = {BANK_GEN1, BANK_GEN0};
        force_error_cancellation_epoch = CANCEL0;
        force_error_tag = 16'h7001;
        force_error_valid = 1;
        while (!force_error_ready) @(negedge clk);
        @(posedge clk);
        #1;
        force_error_valid = 0;
        repeat (4) begin
            @(posedge clk);
            #1;
            check(lookup_rsp_status == STATUS_OK, "materialized status immutable");
            check(lookup_rsp_weight_data == bank_data_pattern(0, 8172),
                  "materialized data immutable");
        end
        @(negedge clk);
        lookup_rsp_ready = 1;
        force_error_rsp_ready = 1;
        timeout_count = 0;
        while (!force_error_rsp_valid && timeout_count < 100) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(force_error_rsp_valid, "final close response arrives after causal drain");
        check(force_error_rsp_code == ERR_ABORTED, "final close preserves abort code");
        check(force_error_rsp_status == STATUS_OK, "exact final close succeeds");
        @(posedge clk);
        #1;
        lookup_rsp_ready = 0;
        force_error_rsp_ready = 0;

        // Exercise normal causal drain to RETAINED and exact rebind without
        // changing directory generation or stored entries.
        pulse_reset;
        setup_bank0_active(16'h8000);
        clear_new_descriptor;
        set_expected_identity(0);
        mgmt_req_drain_target = 2'b01;
        mgmt_req_external_safe = 1;
        send_mgmt(OP_BEGIN_DRAIN, 2'b01, STATUS_OK, 16'h8010);
        check(directory_state[2:0] == ST_DRAINING,
              "BEGIN_DRAIN enters draining");
        check(bank_drain_complete[0], "empty active bank reaches drain complete");
        set_expected_identity(0);
        mgmt_req_external_safe = 1;
        send_mgmt(OP_FINISH_DRAIN, 2'b01, STATUS_OK, 16'h8011);
        check(directory_state[2:0] == ST_RETAINED,
              "FINISH_DRAIN reaches retained disposition");
        check(directory_content_valid[0], "retained content remains valid");
        check(dut.directory_mem0[0][31:30] == 2'b11 &&
              dut.directory_mem0[0][12:0] == 13'd100,
              "retained entry payload remains unchanged");

        mgmt_req_expected_directory_generation = 16'd1;
        mgmt_req_expected_content_handle = CONTENT0;
        mgmt_req_expected_stage_ticket = 0;
        mgmt_req_expected_physical_bank_generation = BANK_GEN0;
        set_new_descriptor(0);
        mgmt_req_new_stage_ticket = TICKET0 + 32'h100;
        mgmt_req_new_context_generation = CONTEXT0 + 32'h100;
        mgmt_req_new_physical_bank_generation = BANK_GEN0 + 32'h100;
        mgmt_req_new_cancellation_epoch = CANCEL0 + 32'h100;
        mgmt_req_new_matrix0_binding_token = BIND00 + 32'h100;
        mgmt_req_new_matrix1_binding_token = BIND01 + 32'h100;
        mgmt_req_external_safe = 1;
        send_mgmt(OP_REBIND_RETAINED, 2'b01, STATUS_OK, 16'h8012);
        check(directory_state[2:0] == ST_LOADING,
              "retained rebind returns to loading");
        check(directory_generation[15:0] == 16'd1,
              "retained rebind preserves directory generation");
        check(dut.directory_mem0[0][12:0] == 13'd100,
              "retained rebind preserves slot mapping");

        // Publication bounds are checked before truncation.  A source with
        // bit 9 set must not alias source zero, and an endpoint of 8192 must
        // not wrap into the 13-bit weight-bank address space.
        pulse_reset;
        scrub_one(0, 16'h8100);
        set_new_descriptor(0);
        mgmt_req_expected_directory_generation = 0;
        mgmt_req_external_safe = 1;
        send_mgmt(OP_CLAIM_FRESH, 2'b01, STATUS_OK, 16'h8101);
        publish_one(0, 0, 10'h200, 13'd100,
                    ERR_BAD_SOURCE, 0, 16'h8102);
        publish_one(0, 0, 10'd1, 13'd8173,
                    ERR_BAD_BOUNDS, 0, 16'h8103);
        check(dut.directory_mem0[0] == 0 && dut.directory_mem0[1] == 0,
              "rejected publication cannot create truncate aliases");
        check(!local_error_valid[0],
              "publication bounds failures remain caller-local");

        // Lookup prechecks likewise reject source_index[9] before any RAM or
        // bank access.  Compute membership is a trusted proof: when absent it
        // is fatal and the directory cannot manufacture membership locally.
        pulse_reset;
        setup_bank0_active(16'h8110);
        issue_lookup_error_no_bank(0, 0, 10'h200, 0, 1,
                                   ERR_BAD_SOURCE, 0, 16'h8115);
        check(!local_error_valid[0],
              "out-of-domain probe is caller-local and does not fence");
        issue_lookup_error_no_bank(0, 1, 0, 0, 0,
                                   ERR_MEMBERSHIP_UNPROVEN, 1, 16'h8116);
        check(local_error_valid[0] &&
              local_error_code[7:0] == ERR_MEMBERSHIP_UNPROVEN,
              "unproven compute membership poisons current authority");

        // Current-generation malformed entries fail closed.  The incomplete
        // and reserved-bit encodings are distinct from a normal generation
        // miss, and a 14-bit slot_base+row_tile endpoint of 8192 cannot alias.
        pulse_reset;
        setup_bank0_active(16'h8120);
        @(negedge clk);
        dut.directory_mem0[1] = {1'b1, 1'b0, 16'd1, 1'b0, 13'd100};
        issue_lookup_error_no_bank(0, 1, 1, 0, 1,
                                   ERR_DIRECTORY_INCOMPLETE, 1, 16'h8125);
        pulse_reset;
        setup_bank0_active(16'h8130);
        @(negedge clk);
        dut.directory_mem0[1] = {1'b1, 1'b1, 16'd1, 1'b1, 13'd100};
        issue_lookup_error_no_bank(0, 1, 1, 0, 1,
                                   ERR_DIRECTORY_CORRUPT, 1, 16'h8135);
        pulse_reset;
        setup_bank0_active(16'h8140);
        @(negedge clk);
        dut.directory_mem0[1] = {1'b1, 1'b1, 16'd1, 1'b0, 13'd8191};
        issue_lookup_error_no_bank(0, 1, 1, 1, 1,
                                   ERR_BAD_BOUNDS, 1, 16'h8145);

        // Exhaust the bank-local fast directory classifiers with public
        // behavior checks.  Probe generation mismatch and a current empty
        // encoding are normal misses; current illegal flags and the reserved
        // bit are fatal for probes just as they are for compute.  Conflicting
        // entries in the unselected directory must never affect the result.
        pulse_reset;
        setup_both_active(16'h8148);
        @(negedge clk);
        dut.directory_mem0[5] =
            {1'b1, 1'b1, 16'd2, 1'b0, 13'd500};
        dut.directory_mem1[5] =
            {1'b1, 1'b1, 16'd1, 1'b0, 13'd600};
        dut.directory_mem1[6] =
            {1'b0, 1'b0, 16'd1, 1'b0, 13'd777};
        issue_lookup_wait(0, 0, 0, 10'd5, 0, 16'h8149,
                          STATUS_OK, 0, 0, 0);
        issue_lookup_wait(1, 0, 0, 10'd6, 0, 16'h814a,
                          STATUS_OK, 0, 0, 0);
        check(!local_error_valid[0] && !local_error_valid[1],
              "stale and current-empty probes remain normal misses");
        @(negedge clk);
        dut.directory_mem0[7] =
            {1'b0, 1'b1, 16'd1, 1'b0, 13'd700};
        issue_lookup_error_no_bank(0, 0, 10'd7, 0, 1,
                                   ERR_DIRECTORY_CORRUPT, 1, 16'h814b);
        @(negedge clk);
        dut.directory_mem1[7] =
            {1'b1, 1'b1, 16'd1, 1'b1, 13'd700};
        issue_lookup_error_no_bank(1, 0, 10'd7, 0, 1,
                                   ERR_DIRECTORY_CORRUPT, 1, 16'h814c);
        check(local_error_valid == 2'b11,
              "illegal flags and reserved bit poison only selected scopes");

        // Exhaust the publication fast classifier's nonfatal cases and a
        // current-generation corruption on both physical RAM implementations.
        // Standard source publications above already exercise stale entries;
        // this explicit stale-valid entry proves generation mismatch wins over
        // its old valid payload.  Current empty commits, exact duplicate is a
        // caller-local diagnostic, and current reserved data fails closed.
        pulse_reset;
        scrub_both;
        claim_bank(0);
        claim_bank(1);
        @(negedge clk);
        dut.directory_mem0[3] =
            {1'b0, 1'b0, 16'd1, 1'b0, 13'd799};
        dut.directory_mem1[3] =
            {1'b1, 1'b1, 16'd1, 1'b0, 13'd400};
        dut.directory_mem1[4] =
            {1'b1, 1'b1, 16'd2, 1'b0, 13'd410};
        dut.directory_mem1[5] =
            {1'b1, 1'b1, 16'd1, 1'b1, 13'd420};
        publish_one(0, 0, 10'd3, 13'd300,
                    STATUS_OK, 1, 16'h814d);
        check(dut.directory_mem0[3] ==
              {2'b11, 16'd1, 1'b0, 13'd300},
              "current-empty publication atomically commits new entry");
        publish_one(1, 0, 10'd3, 13'd400,
                    ERR_DUPLICATE_PUBLICATION, 0, 16'h814e);
        check(!local_error_valid[1],
              "bank1 exact duplicate remains caller-local");
        publish_one(1, 0, 10'd4, 13'd411,
                    STATUS_OK, 1, 16'h814f);
        check(dut.directory_mem1[4] ==
              {2'b11, 16'd1, 1'b0, 13'd411},
              "stale valid publication overwrites with current authority");
        publish_one(1, 0, 10'd5, 13'd421,
                    ERR_DIRECTORY_CORRUPT, 0, 16'h8150);
        wait_fault_materialized(1, 1);
        check(local_error_code[15:8] == ERR_DIRECTORY_CORRUPT &&
              fault_event_bank_mask == 2'b10 &&
              fault_event_code == ERR_DIRECTORY_CORRUPT &&
              dut.committed_count_q[1] == 10'd1,
              "current corrupt publication is fatal and never commits");
        @(negedge clk);
        fault_event_ready = 1;
        @(posedge clk);
        #1;
        fault_event_ready = 0;

        // Every physical echo field participates in identity checking.  The
        // directory-owned correlation tag is stronger: reserved slot 3 and a
        // wrong incarnation are internal ownership failures requiring reset.
        pulse_reset;
        setup_bank0_active(16'h8150);
        inject_bad_bank0_response(1, ERR_BANK_IDENTITY_MISMATCH, 0, 16'h8155);
        pulse_reset;
        setup_bank0_active(16'h8160);
        inject_bad_bank0_response(2, ERR_BANK_IDENTITY_MISMATCH, 0, 16'h8165);
        pulse_reset;
        setup_bank0_active(16'h8170);
        inject_bad_bank0_response(3, ERR_INTERNAL_STATE, 1, 16'h8175);
        pulse_reset;
        setup_bank0_active(16'h8180);
        inject_bad_bank0_response(4, ERR_INTERNAL_STATE, 1, 16'h8185);

        // An unsolicited response with no live correlation slot is never
        // accepted, but it still latches an internal/reset-required fault.
        pulse_reset;
        setup_bank0_active(16'h8190);
        auto_bank_responder = 0;
        bank0_rd_rsp_data = {128{1'b1}};
        bank0_rd_rsp_addr = 13'd100;
        bank0_rd_rsp_generation = BANK_GEN0;
        bank0_rd_rsp_lease_owner_ticket = TICKET0;
        bank0_rd_rsp_tag = 16'h0003;
        bank0_rd_rsp_status = STATUS_OK;
        bank0_rd_rsp_valid = 1;
        @(posedge clk);
        #1;
        check(!bank0_rd_rsp_ready,
              "orphan response has no physical acceptance owner");
        @(negedge clk);
        bank0_rd_rsp_valid = 0;
        wait_fault_materialized(0, 1);
        check(local_error_valid[0] &&
              local_error_code[7:0] == ERR_INTERNAL_STATE &&
              local_error_source[2:0] == ERROR_SOURCE_BANK_RESPONSE &&
              reset_required[0],
              "orphan response latches internal reset-required fault");
        check(fault_event_valid && fault_event_code == ERR_INTERNAL_STATE,
              "orphan response reports internal fault event");
        @(negedge clk);
        fault_event_ready = 1;
        @(posedge clk);
        #1;
        fault_event_ready = 0;

        // Retire one correct response, hold its logical result stable, then
        // repeat the already-consumed physical response.  The duplicate has
        // no live slot and therefore cannot be mistaken for a new request.
        pulse_reset;
        setup_bank0_active(16'h81a0);
        auto_bank_responder = 0;
        bank0_rd_req_ready = 0;
        lookup_rsp_ready = 0;
        issue_lookup_no_wait(0, 1, 0, 0, 2, 16'h81a5);
        while (!bank0_rd_req_valid) @(negedge clk);
        manual_addr0 = bank0_rd_req_addr;
        manual_generation0 = bank0_rd_req_generation;
        manual_ticket0 = bank0_rd_req_lease_owner_ticket;
        manual_tag0 = bank0_rd_req_tag;
        bank0_rd_req_ready = 1;
        @(posedge clk);
        #1;
        @(negedge clk);
        bank0_rd_req_ready = 0;
        bank0_rd_rsp_data = bank_data_pattern(0, manual_addr0);
        bank0_rd_rsp_addr = manual_addr0;
        bank0_rd_rsp_generation = manual_generation0;
        bank0_rd_rsp_lease_owner_ticket = manual_ticket0;
        bank0_rd_rsp_tag = manual_tag0;
        bank0_rd_rsp_status = STATUS_OK;
        bank0_rd_rsp_valid = 1;
        while (!bank0_rd_rsp_ready) @(negedge clk);
        @(posedge clk);
        #1;
        @(negedge clk);
        bank0_rd_rsp_valid = 0;
        while (!lookup_rsp_valid) begin
            @(posedge clk);
            #1;
        end
        repeat (4) begin
            check(lookup_rsp_valid && lookup_rsp_status == STATUS_OK &&
                  lookup_rsp_hit &&
                  lookup_rsp_weight_data == bank_data_pattern(0, manual_addr0) &&
                  lookup_rsp_slot_base == 13'd100 &&
                  lookup_rsp_weight_addr == manual_addr0 &&
                  lookup_rsp_user_tag == 16'h81a5,
                  "held successful logical response remains bit-stable");
            @(posedge clk);
            #1;
        end
        @(negedge clk);
        lookup_rsp_ready = 1;
        @(posedge clk);
        #1;
        lookup_rsp_ready = 0;
        @(negedge clk);
        bank0_rd_rsp_valid = 1;
        @(posedge clk);
        #1;
        check(!bank0_rd_rsp_ready,
              "duplicate response has no physical acceptance owner");
        @(negedge clk);
        bank0_rd_rsp_valid = 0;
        wait_fault_materialized(0, 0);
        check(local_error_valid[0] &&
              local_error_code[7:0] == ERR_INTERNAL_STATE &&
              reset_required[0],
              "duplicate response after retirement is an orphan/reset fault");
        @(negedge clk);
        fault_event_ready = 1;
        @(posedge clk);
        #1;
        fault_event_ready = 0;

        // If a higher-priority orphan-token fault is discovered on the exact
        // final-close edge, it determines the close result and reset class.
        // The older sticky first-error record itself remains immutable.
        pulse_reset;
        setup_bank0_active(16'h81a8);
        issue_lookup_error_no_bank(0, 1, 10'd319, 0, 1,
                                   ERR_COMPUTE_MISS, 1, 16'h81ad);
        check(local_error_valid[0] &&
              local_error_code[7:0] == ERR_COMPUTE_MISS,
              "older sticky first-error established before same-edge close");
        @(negedge clk);
        set_exact_abort_bank0(16'h81ae);
        force_error_valid = 1;
        bank0_rd_rsp_data = {128{1'b1}};
        bank0_rd_rsp_addr = 13'd100;
        bank0_rd_rsp_generation = BANK_GEN0;
        bank0_rd_rsp_lease_owner_ticket = TICKET0;
        bank0_rd_rsp_tag = 16'h0003;
        bank0_rd_rsp_status = STATUS_OK;
        bank0_rd_rsp_valid = 1;
        check(force_error_ready,
              "exact close can fire with same-edge orphan-token fault");
        @(posedge clk);
        #1;
        check(local_error_code[7:0] == ERR_COMPUTE_MISS,
              "same-edge fault cannot overwrite sticky first-error record");
        @(negedge clk);
        force_error_valid = 0;
        bank0_rd_rsp_valid = 0;
        timeout_count = 0;
        while (!reset_required[0] && timeout_count < 20) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(reset_required[0],
              "same-edge orphan-token fault upgrades reset requirement");
        timeout_count = 0;
        while (!force_error_rsp_valid && timeout_count < 50) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(force_error_rsp_valid && force_error_rsp_status == STATUS_OK &&
              force_error_rsp_code == ERR_INTERNAL_STATE &&
              force_error_rsp_reset_required[0],
              "same-edge higher-priority fault defines coherent close response");
        @(negedge clk);
        force_error_rsp_ready = 1;
        fault_event_ready = 1;
        @(posedge clk);
        #1;
        force_error_rsp_ready = 0;
        fault_event_ready = 0;

        // Final close while a compute hit is waiting for bank-request ready:
        // the not-yet-issued request becomes one abort terminal, the physical
        // request never fires, and close cannot respond before that terminal
        // is retired.
        pulse_reset;
        setup_bank0_active(16'h81b0);
        auto_bank_responder = 0;
        bank0_rd_req_ready = 0;
        lookup_rsp_ready = 0;
        force_error_rsp_ready = 0;
        issue_lookup_no_wait(0, 1, 0, 0, 3, 16'h81b5);
        while (!bank0_rd_req_valid) @(negedge clk);
        @(negedge clk);
        set_exact_abort_bank0(16'h81b6);
        force_error_valid = 1;
        while (!force_error_ready) @(negedge clk);
        @(posedge clk);
        #1;
        check(!bank0_rd_req_valid,
              "final close cancels held bank-pending issue before fire");
        @(negedge clk);
        force_error_valid = 0;
        while (!lookup_rsp_valid) begin
            @(posedge clk);
            #1;
        end
        check(lookup_rsp_status == ERR_ABORTED && !lookup_rsp_fatal &&
              !lookup_rsp_hit && lookup_rsp_weight_data == 0 &&
              lookup_rsp_slot_base == 0 && lookup_rsp_weight_addr == 0,
              "pending-position final close returns zero abort terminal");
        check(!force_error_rsp_valid,
              "pending-position close waits for logical terminal retirement");
        @(negedge clk);
        lookup_rsp_ready = 1;
        @(posedge clk);
        #1;
        lookup_rsp_ready = 0;
        timeout_count = 0;
        while (!force_error_rsp_valid && timeout_count < 50) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(force_error_rsp_valid && force_error_rsp_status == STATUS_OK &&
              force_error_rsp_code == ERR_ABORTED,
              "pending-position final close responds after causal drain");
        @(negedge clk);
        force_error_rsp_ready = 1;
        @(posedge clk);
        #1;
        force_error_rsp_ready = 0;

        // Final close after the physical request fired must still accept the
        // exact causal bank response to release its credit, but it cannot turn
        // that response into success or expose the returned weight payload.
        pulse_reset;
        setup_bank0_active(16'h81c0);
        auto_bank_responder = 0;
        bank0_rd_req_ready = 0;
        lookup_rsp_ready = 0;
        force_error_rsp_ready = 0;
        issue_lookup_no_wait(0, 1, 0, 0, 4, 16'h81c5);
        while (!bank0_rd_req_valid) @(negedge clk);
        manual_addr0 = bank0_rd_req_addr;
        manual_generation0 = bank0_rd_req_generation;
        manual_ticket0 = bank0_rd_req_lease_owner_ticket;
        manual_tag0 = bank0_rd_req_tag;
        bank0_rd_req_ready = 1;
        @(posedge clk);
        #1;
        @(negedge clk);
        bank0_rd_req_ready = 0;
        set_exact_abort_bank0(16'h81c6);
        force_error_valid = 1;
        while (!force_error_ready) @(negedge clk);
        @(posedge clk);
        #1;
        @(negedge clk);
        force_error_valid = 0;
        bank0_rd_rsp_data = {128{1'b1}};
        bank0_rd_rsp_addr = manual_addr0;
        bank0_rd_rsp_generation = manual_generation0;
        bank0_rd_rsp_lease_owner_ticket = manual_ticket0;
        bank0_rd_rsp_tag = manual_tag0;
        bank0_rd_rsp_status = STATUS_OK;
        bank0_rd_rsp_valid = 1;
        while (!bank0_rd_rsp_ready) @(negedge clk);
        @(posedge clk);
        #1;
        @(negedge clk);
        bank0_rd_rsp_valid = 0;
        while (!lookup_rsp_valid) begin
            @(posedge clk);
            #1;
        end
        check(lookup_rsp_status == ERR_ABORTED && !lookup_rsp_fatal &&
              !lookup_rsp_hit && lookup_rsp_weight_data == 0 &&
              lookup_rsp_slot_base == 0 && lookup_rsp_weight_addr == 0,
              "bank-wait final close drains response as zero abort terminal");
        check(!force_error_rsp_valid,
              "bank-wait close waits for drained logical terminal");
        @(negedge clk);
        lookup_rsp_ready = 1;
        @(posedge clk);
        #1;
        lookup_rsp_ready = 0;
        while (!force_error_rsp_valid) begin
            @(posedge clk);
            #1;
        end
        check(force_error_rsp_status == STATUS_OK &&
              force_error_rsp_code == ERR_ABORTED,
              "bank-wait final close completes after physical/logical drain");
        @(negedge clk);
        force_error_rsp_ready = 1;
        @(posedge clk);
        #1;
        force_error_rsp_ready = 0;

        // A bank0 directory result may be resident in the aggregate read
        // pipeline while an exact bank0 close and an unrelated bank1 lookup
        // fire together.  The old bank0 transaction is converted to the stop
        // terminal, but the same-edge bank1 capture must survive rollover.
        pulse_reset;
        setup_both_active(16'h81c8);
        auto_bank_responder = 0;
        bank0_rd_req_ready = 0;
        bank1_rd_req_ready = 0;
        lookup_rsp_ready = 0;
        force_error_rsp_ready = 0;
        issue_lookup_no_wait(0, 1, 0, 0, 7, 16'h81cc);
        check(dut.dir_pipe_valid_q &&
              !dut.slot_bank_q[dut.dir_pipe_slot_q],
              "rollover setup holds old bank0 directory-pipeline result");
        @(negedge clk);
        set_exact_abort_bank0(16'h81ce);
        force_error_valid = 1;
        set_lookup(1, 1, 0, 0, 8, 16'h81cd);
        lookup_req_valid = 1;
        #1;
        check(force_error_ready && lookup_req_ready,
              "bank0 exact close and unrelated bank1 lookup fire together");
        @(posedge clk);
        #1;
        check(dut.dir_pipe_valid_q &&
              dut.slot_bank_q[dut.dir_pipe_slot_q],
              "same-edge bank1 lookup replaces closing bank0 dir-pipe owner");
        check(!bank0_rd_req_valid &&
              directory_bank_ref_count[1:0] == 1 &&
              directory_bank_ref_count[3:2] == 1,
              "rollover preserves both terminal references without bank0 issue");
        @(negedge clk);
        force_error_valid = 0;
        lookup_req_valid = 0;
        timeout_count = 0;
        while (!lookup_rsp_valid && timeout_count < 30) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(lookup_rsp_valid && lookup_rsp_status == ERR_ABORTED &&
              lookup_rsp_user_tag == 16'h81cc && !lookup_rsp_hit &&
              lookup_rsp_weight_data == 0 && lookup_rsp_slot_base == 0 &&
              lookup_rsp_weight_addr == 0,
              "closing bank0 directory result becomes ordered zero stop terminal");
        check(bank1_rd_req_valid && !bank0_rd_req_valid,
              "younger bank1 directory result survives as selected pending issue");
        @(negedge clk);
        lookup_rsp_ready = 1;
        @(posedge clk);
        #1;
        lookup_rsp_ready = 0;
        timeout_count = 0;
        while (!force_error_rsp_valid && timeout_count < 30) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(force_error_rsp_valid && force_error_rsp_status == STATUS_OK &&
              force_error_rsp_code == ERR_ABORTED &&
              force_error_rsp_tag == 16'h81ce,
              "bank0 close completes after old directory terminal retirement");
        @(negedge clk);
        force_error_rsp_ready = 1;
        manual_addr1 = bank1_rd_req_addr;
        manual_generation1 = bank1_rd_req_generation;
        manual_ticket1 = bank1_rd_req_lease_owner_ticket;
        manual_tag1 = bank1_rd_req_tag;
        bank1_rd_req_ready = 1;
        @(posedge clk);
        #1;
        force_error_rsp_ready = 0;
        @(negedge clk);
        bank1_rd_req_ready = 0;
        bank1_rd_rsp_data = bank_data_pattern(1, manual_addr1);
        bank1_rd_rsp_addr = manual_addr1;
        bank1_rd_rsp_generation = manual_generation1;
        bank1_rd_rsp_lease_owner_ticket = manual_ticket1;
        bank1_rd_rsp_tag = manual_tag1;
        bank1_rd_rsp_status = STATUS_OK;
        bank1_rd_rsp_valid = 1;
        while (!bank1_rd_rsp_ready) @(negedge clk);
        @(posedge clk);
        #1;
        @(negedge clk);
        bank1_rd_rsp_valid = 0;
        timeout_count = 0;
        while (!lookup_rsp_valid && timeout_count < 30) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(lookup_rsp_valid && lookup_rsp_status == STATUS_OK &&
              lookup_rsp_hit && lookup_rsp_selected_bank_id == 1 &&
              lookup_rsp_user_tag == 16'h81cd &&
              lookup_rsp_weight_addr == manual_addr1 &&
              lookup_rsp_weight_data == bank_data_pattern(1, manual_addr1),
              "surviving bank1 rollover request reaches exact success terminal");
        @(negedge clk);
        lookup_rsp_ready = 1;
        @(posedge clk);
        #1;
        lookup_rsp_ready = 0;
        check(lookup_outstanding == 0 &&
              directory_bank_ref_count == 0 &&
              directory_to_bank_pending == 0 && bank_rsp_outstanding == 0 &&
              bank_quiescent[1],
              "close-plus-other-bank rollover drains every causal credit");

        // A malformed current-authority response must fence its bank while it
        // is held behind an older response from the other bank.  Detection is
        // based on valid payload, not delayed until global-order ready/fire.
        pulse_reset;
        setup_both_active(16'h81d0);
        auto_bank_responder = 0;
        bank0_rd_req_ready = 0;
        bank1_rd_req_ready = 0;
        lookup_rsp_ready = 0;
        fault_event_ready = 0;
        issue_lookup_no_wait(0, 1, 0, 0, 5, 16'h81d5);
        issue_lookup_no_wait(1, 1, 0, 0, 6, 16'h81d6);
        while (!bank0_rd_req_valid) @(negedge clk);
        manual_addr0 = bank0_rd_req_addr;
        manual_generation0 = bank0_rd_req_generation;
        manual_ticket0 = bank0_rd_req_lease_owner_ticket;
        manual_tag0 = bank0_rd_req_tag;
        bank0_rd_req_ready = 1;
        @(posedge clk);
        #1;
        @(negedge clk);
        bank0_rd_req_ready = 0;
        while (!bank1_rd_req_valid) @(negedge clk);
        manual_addr1 = bank1_rd_req_addr;
        manual_generation1 = bank1_rd_req_generation;
        manual_ticket1 = bank1_rd_req_lease_owner_ticket;
        manual_tag1 = bank1_rd_req_tag;
        bank1_rd_req_ready = 1;
        @(posedge clk);
        #1;
        @(negedge clk);
        bank1_rd_req_ready = 0;
        bank1_rd_rsp_data = {128{1'b1}};
        bank1_rd_rsp_addr = manual_addr1 + 1'b1;
        bank1_rd_rsp_generation = manual_generation1;
        bank1_rd_rsp_lease_owner_ticket = manual_ticket1;
        bank1_rd_rsp_tag = manual_tag1;
        bank1_rd_rsp_status = STATUS_OK;
        bank1_rd_rsp_valid = 1;
        set_lookup(1, 1, 0, 0, 7, 16'h81d7);
        lookup_req_valid = 1;
        set_publication(1, 0, 1, 13'd1020);
        publish_req_tag = 16'h81d8;
        publish_req_valid = 1;
        #1;
        check(!bank1_rd_rsp_ready,
              "younger malformed bank response is held by global order");
        check(!lookup_req_ready && !publish_req_ready,
              "stalled malformed response fences same-edge admissions");
        @(posedge clk);
        #1;
        check(bank1_rd_rsp_valid && !bank1_rd_rsp_ready &&
              bank1_rd_rsp_addr == manual_addr1 + 1'b1 &&
              bank1_rd_rsp_tag == manual_tag1,
              "stalled malformed physical response payload remains stable");
        wait_fault_materialized(1, 1);
        check(local_error_valid[1] &&
              local_error_code[15:8] == ERR_BANK_IDENTITY_MISMATCH &&
              local_error_source[5:3] == ERROR_SOURCE_BANK_RESPONSE,
              "stalled malformed response latches current-authority fault");
        check(fault_event_valid && fault_event_bank_mask == 2'b10 &&
              fault_event_code == ERR_BANK_IDENTITY_MISMATCH,
              "stalled malformed response creates exact fault event");
        check(bank1_rd_rsp_valid && !bank1_rd_rsp_ready &&
              bank1_rd_rsp_addr == manual_addr1 + 1'b1 &&
              bank1_rd_rsp_tag == manual_tag1,
              "stalled malformed physical response payload remains stable");
        @(negedge clk);
        lookup_req_valid = 0;
        publish_req_valid = 0;
        bank1_rd_rsp_valid = 0;
        fault_event_ready = 1;
        @(posedge clk);
        #1;
        fault_event_ready = 0;

        // A known-slot wrong echoed address is consumed, returns zero data,
        // raises a lease-fatal event, and fences the bank immediately.
        pulse_reset;
        setup_bank0_active(16'h8200);
        auto_bank_responder = 0;
        bank0_rd_req_ready = 0;
        issue_lookup_no_wait(0, 1, 0, 0, 0, 16'h8210);
        timeout_count = 0;
        while (!bank0_rd_req_valid && timeout_count < 50) begin
            @(negedge clk);
            timeout_count = timeout_count + 1;
        end
        check(bank0_rd_req_valid, "bad-identity test receives bank request");
        manual_addr0 = bank0_rd_req_addr;
        manual_generation0 = bank0_rd_req_generation;
        manual_ticket0 = bank0_rd_req_lease_owner_ticket;
        manual_tag0 = bank0_rd_req_tag;
        bank0_rd_req_ready = 1;
        @(posedge clk);
        #1;
        @(negedge clk);
        bank0_rd_req_ready = 0;
        bank0_rd_rsp_data = {128{1'b1}};
        bank0_rd_rsp_addr = manual_addr0 + 1'b1;
        bank0_rd_rsp_generation = manual_generation0;
        bank0_rd_rsp_lease_owner_ticket = manual_ticket0;
        bank0_rd_rsp_tag = manual_tag0;
        bank0_rd_rsp_status = STATUS_OK;
        bank0_rd_rsp_valid = 1;
        timeout_count = 0;
        while (!bank0_rd_rsp_ready && timeout_count < 50) begin
            @(negedge clk);
            timeout_count = timeout_count + 1;
        end
        check(bank0_rd_rsp_ready, "known wrong bank response is consumed");
        @(posedge clk);
        #1;
        @(negedge clk);
        bank0_rd_rsp_valid = 0;
        timeout_count = 0;
        while (!lookup_rsp_valid && timeout_count < 50) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(lookup_rsp_status == ERR_BANK_IDENTITY_MISMATCH,
              "wrong bank echo reports identity mismatch");
        check(!lookup_rsp_hit && lookup_rsp_weight_data == 0 &&
              lookup_rsp_slot_base == 0 && lookup_rsp_weight_addr == 0 &&
              lookup_rsp_fatal,
              "wrong bank echo zeros every authorizing payload and is fatal");
        wait_fault_materialized(0, 1);
        check(local_error_valid[0] && fault_event_valid,
              "wrong bank echo latches first fatal before event handshake");
        @(negedge clk);
        lookup_rsp_ready = 1;
        fault_event_ready = 1;
        @(posedge clk);
        #1;
        lookup_rsp_ready = 0;
        fault_event_ready = 0;

        // A nonzero physical-bank status has its distinct terminal code and
        // must likewise never expose the supplied weight data.
        pulse_reset;
        setup_bank0_active(16'h8300);
        auto_bank_responder = 0;
        bank0_rd_req_ready = 0;
        issue_lookup_no_wait(0, 1, 0, 0, 0, 16'h8310);
        while (!bank0_rd_req_valid) @(negedge clk);
        manual_addr0 = bank0_rd_req_addr;
        manual_generation0 = bank0_rd_req_generation;
        manual_ticket0 = bank0_rd_req_lease_owner_ticket;
        manual_tag0 = bank0_rd_req_tag;
        bank0_rd_req_ready = 1;
        @(posedge clk);
        #1;
        @(negedge clk);
        bank0_rd_req_ready = 0;
        bank0_rd_rsp_data = {128{1'b1}};
        bank0_rd_rsp_addr = manual_addr0;
        bank0_rd_rsp_generation = manual_generation0;
        bank0_rd_rsp_lease_owner_ticket = manual_ticket0;
        bank0_rd_rsp_tag = manual_tag0;
        bank0_rd_rsp_status = ERR_WRONG_STATE;
        bank0_rd_rsp_valid = 1;
        while (!bank0_rd_rsp_ready) @(negedge clk);
        @(posedge clk);
        #1;
        @(negedge clk);
        bank0_rd_rsp_valid = 0;
        while (!lookup_rsp_valid) begin
            @(posedge clk);
            #1;
        end
        check(lookup_rsp_status == ERR_BANK_RESPONSE_ERROR,
              "nonzero bank status maps to bank-response error");
        check(!lookup_rsp_hit && lookup_rsp_weight_data == 0 &&
              lookup_rsp_slot_base == 0 && lookup_rsp_weight_addr == 0 &&
              lookup_rsp_fatal,
              "nonzero bank status zeros every authorizing payload and is fatal");
        @(negedge clk);
        lookup_rsp_ready = 1;
        fault_event_ready = 1;
        @(posedge clk);
        #1;
        lookup_rsp_ready = 0;
        fault_event_ready = 0;

        // A captured management command is still unmaterialized in its
        // one-deep execution slot.  An exact same-bank close on the following
        // edge converts BEGIN_DRAIN into the close terminal, prevents the
        // requested RETAINED disposition, and waits for that terminal to
        // retire before returning the force response.
        pulse_reset;
        setup_bank0_active(16'h83a0);
        @(negedge clk);
        clear_new_descriptor;
        set_expected_identity(0);
        mgmt_req_drain_target = DRAIN_RETAINED;
        mgmt_req_external_safe = 1;
        mgmt_req_opcode = OP_BEGIN_DRAIN;
        mgmt_req_bank_mask = 2'b01;
        mgmt_req_tag = 16'h83a5;
        mgmt_req_valid = 1;
        sampled_count = 0;
        while (!sampled_count) begin
            @(posedge clk);
            sampled_count = mgmt_req_ready;
            #1;
        end
        check(dut.mgmt_exec_valid_q && !mgmt_rsp_valid &&
              directory_state[2:0] == ST_ACTIVE,
              "management acceptance fills exec slot without early mutation");
        @(negedge clk);
        mgmt_req_valid = 0;
        set_exact_abort_bank0(16'h83a6);
        force_error_rsp_ready = 0;
        force_error_valid = 1;
        check(force_error_ready,
              "same-bank exact close accepted against pending mgmt exec");
        @(posedge clk);
        #1;
        check(dut.mgmt_exec_valid_q && !mgmt_rsp_valid,
              "force edge holds pending management until close is visible");
        check(directory_state[2:0] == ST_DRAINING &&
              dut.drain_target_q[0] == DRAIN_ERROR,
              "close overrides original retained drain disposition");
        check(directory_generation[15:0] == 16'd1,
              "converted management command cannot change generation");
        @(negedge clk);
        force_error_valid = 0;
        timeout_count = 0;
        while (!mgmt_rsp_valid && timeout_count < 20) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(mgmt_rsp_valid && mgmt_rsp_opcode == OP_BEGIN_DRAIN &&
              mgmt_rsp_tag == 16'h83a5 &&
              mgmt_rsp_status == ERR_ABORTED,
              "pending management receives unique converted close terminal");
        check(!force_error_rsp_valid,
              "force response waits for converted management terminal");
        repeat (3) begin
            @(posedge clk);
            #1;
            check(mgmt_rsp_valid && mgmt_rsp_status == ERR_ABORTED &&
                  mgmt_rsp_tag == 16'h83a5 && !force_error_rsp_valid,
                  "converted management terminal stable while close waits");
        end
        @(negedge clk);
        mgmt_rsp_ready = 1;
        @(posedge clk);
        #1;
        mgmt_rsp_ready = 0;
        timeout_count = 0;
        while (!force_error_rsp_valid && timeout_count < 20) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(force_error_rsp_valid && force_error_rsp_status == STATUS_OK &&
              force_error_rsp_code == ERR_ABORTED &&
              force_error_rsp_tag == 16'h83a6,
              "force response follows converted management retirement");
        @(negedge clk);
        force_error_rsp_ready = 1;
        @(posedge clk);
        #1;
        force_error_rsp_ready = 0;

        // A current-authority physical response fault on the management exec
        // edge must be captured before BEGIN_DRAIN can mutate the lifecycle.
        pulse_reset;
        setup_bank0_active(16'h83b0);
        auto_bank_responder = 0;
        bank0_rd_req_ready = 0;
        lookup_rsp_ready = 0;
        issue_lookup_no_wait(0, 1, 0, 0, 0, 16'h83b5);
        while (!bank0_rd_req_valid) @(negedge clk);
        manual_addr0 = bank0_rd_req_addr;
        manual_generation0 = bank0_rd_req_generation;
        manual_ticket0 = bank0_rd_req_lease_owner_ticket;
        manual_tag0 = bank0_rd_req_tag;
        bank0_rd_req_ready = 1;
        @(posedge clk);
        #1;
        @(negedge clk);
        bank0_rd_req_ready = 0;
        clear_new_descriptor;
        set_expected_identity(0);
        mgmt_req_drain_target = DRAIN_RETAINED;
        mgmt_req_external_safe = 1;
        mgmt_req_opcode = OP_BEGIN_DRAIN;
        mgmt_req_bank_mask = 2'b01;
        mgmt_req_tag = 16'h83b6;
        mgmt_req_valid = 1;
        while (!mgmt_req_ready) @(negedge clk);
        @(posedge clk);
        #1;
        check(dut.mgmt_exec_valid_q && directory_state[2:0] == ST_ACTIVE,
              "fault-collision management command captured before exec");
        @(negedge clk);
        mgmt_req_valid = 0;
        bank0_rd_rsp_data = {128{1'b1}};
        bank0_rd_rsp_addr = manual_addr0 + 1'b1;
        bank0_rd_rsp_generation = manual_generation0;
        bank0_rd_rsp_lease_owner_ticket = manual_ticket0;
        bank0_rd_rsp_tag = manual_tag0;
        bank0_rd_rsp_status = STATUS_OK;
        bank0_rd_rsp_valid = 1;
        check(bank0_rd_rsp_ready,
              "faulting current-authority response can drain on exec edge");
        @(posedge clk);
        #1;
        check(dut.mgmt_exec_valid_q && !mgmt_rsp_valid,
              "exec-edge target fault holds management before mutation");
        check(directory_state[2:0] == ST_ACTIVE &&
              dut.drain_target_q[0] != DRAIN_RETAINED,
              "exec-edge target fault prevents original management mutation");
        @(negedge clk);
        bank0_rd_rsp_valid = 0;
        wait_fault_materialized(0, 1);
        check(local_error_code[7:0] == ERR_BANK_IDENTITY_MISMATCH,
              "exec-edge target fault captures exact bank-response status");
        timeout_count = 0;
        while (!mgmt_rsp_valid && timeout_count < 20) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(mgmt_rsp_valid && mgmt_rsp_status ==
              ERR_BANK_IDENTITY_MISMATCH && mgmt_rsp_tag == 16'h83b6,
              "exec-edge target fault becomes management terminal status");
        check(directory_state[2:0] != ST_DRAINING,
              "faulted management command never enters requested drain state");
        @(negedge clk);
        mgmt_rsp_ready = 1;
        lookup_rsp_ready = 1;
        fault_event_ready = 1;
        @(posedge clk);
        #1;
        mgmt_rsp_ready = 0;
        lookup_rsp_ready = 0;
        fault_event_ready = 0;

        // ACTIVATE is pending in the exec slot when an orphan-token target
        // fault and an unrelated malformed final-close request arrive on the
        // same edge.  Global force priority may delay execution, but it must
        // preserve the collision and must never activate the poisoned bank.
        pulse_reset;
        setup_bank0_ready(16'h83c0);
        @(negedge clk);
        clear_new_descriptor;
        set_expected_identity(0);
        mgmt_req_external_safe = 1;
        mgmt_req_opcode = OP_ACTIVATE;
        mgmt_req_bank_mask = 2'b01;
        mgmt_req_tag = 16'h83c5;
        mgmt_req_valid = 1;
        while (!mgmt_req_ready) @(negedge clk);
        @(posedge clk);
        #1;
        check(dut.mgmt_exec_valid_q && directory_state[2:0] == ST_READY,
              "activation captured without same-edge state mutation");
        @(negedge clk);
        mgmt_req_valid = 0;
        bank0_rd_rsp_data = {128{1'b1}};
        bank0_rd_rsp_addr = 13'd100;
        bank0_rd_rsp_generation = BANK_GEN0;
        bank0_rd_rsp_lease_owner_ticket = TICKET0;
        bank0_rd_rsp_tag = 16'h0003;
        bank0_rd_rsp_status = STATUS_OK;
        bank0_rd_rsp_valid = 1;
        force_error_bank_mask = 2'b00;
        force_error_code = ERR_ABORTED;
        force_error_data_untrusted = 0;
        force_error_causal_producers_drained = 1;
        force_error_tag = 16'h83c6;
        force_error_rsp_ready = 0;
        force_error_valid = 1;
        check(force_error_ready,
              "malformed unrelated force request accepted beside collision");
        @(posedge clk);
        #1;
        check(force_error_rsp_valid &&
              force_error_rsp_status == ERR_BAD_BANK_MASK,
              "malformed force gets its own caller-local terminal");
        check(management_busy && !mgmt_rsp_valid &&
              directory_state[2:0] == ST_READY,
              "force priority retains target collision without activation");
        @(negedge clk);
        bank0_rd_rsp_valid = 0;
        force_error_valid = 0;
        wait_fault_materialized(0, 1);
        check(reset_required[0] &&
              local_error_code[7:0] == ERR_INTERNAL_STATE,
              "orphan target fault remains authoritative beside malformed force");
        timeout_count = 0;
        while (!mgmt_rsp_valid && timeout_count < 20) begin
            @(posedge clk);
            #1;
            check(directory_state[2:0] == ST_READY,
                  "registered collision decision cannot transiently activate");
            timeout_count = timeout_count + 1;
        end
        check(mgmt_rsp_valid && mgmt_rsp_status == ERR_INTERNAL_STATE &&
              mgmt_rsp_tag == 16'h83c5,
              "remembered collision terminates pending activation as fatal");
        check(directory_state[2:0] == ST_READY,
              "collided activation never changes READY to ACTIVE");
        @(negedge clk);
        mgmt_rsp_ready = 1;
        force_error_rsp_ready = 1;
        fault_event_ready = 1;
        @(posedge clk);
        #1;
        mgmt_rsp_ready = 0;
        force_error_rsp_ready = 0;
        fault_event_ready = 0;

        // A syntactically legal activation-like command cannot be accepted
        // on the same edge that a target preexisting fast fault is visible.
        // Structural malformed traffic remains caller-local and serviceable
        // after the fault so it cannot deadlock the shared management port.
        pulse_reset;
        setup_bank0_ready(16'h83c8);
        auto_bank_responder = 0;
        fault_event_ready = 0;
        @(negedge clk);
        clear_new_descriptor;
        set_expected_identity(0);
        mgmt_req_external_safe = 1;
        mgmt_req_opcode = OP_ACTIVATE;
        mgmt_req_bank_mask = 2'b01;
        mgmt_req_tag = 16'h83cd;
        mgmt_req_valid = 1;
        bank0_rd_rsp_data = {128{1'b1}};
        bank0_rd_rsp_addr = 13'd100;
        bank0_rd_rsp_generation = BANK_GEN0;
        bank0_rd_rsp_lease_owner_ticket = TICKET0;
        bank0_rd_rsp_tag = 16'h0003;
        bank0_rd_rsp_status = STATUS_OK;
        bank0_rd_rsp_valid = 1;
        #1;
        check(!bank0_rd_rsp_ready && !mgmt_req_ready,
              "same-edge target fast fault fences fresh legal ACTIVATE");
        @(posedge clk);
        #1;
        check(directory_state[2:0] == ST_READY && !mgmt_rsp_valid,
              "fenced fresh ACTIVATE has no fire, response, or mutation");
        @(negedge clk);
        mgmt_req_valid = 0;
        bank0_rd_rsp_valid = 0;
        wait_fault_materialized(0, 1);
        clear_new_descriptor;
        set_expected_identity(0);
        mgmt_req_external_safe = 1;
        send_mgmt(OP_ACTIVATE, 2'b11,
                  ERR_BAD_BANK_MASK, 16'h83ce);
        check(directory_state[2:0] == ST_READY,
              "malformed activation is caller-local on faulted READY bank");

        // Structural management syntax wins before faulted-bank activation
        // fencing.  A malformed activation-like mask of 11 must therefore be
        // admitted and return BAD_BANK_MASK, not deadlock behind the fault.
        pulse_reset;
        setup_bank0_active(16'h83d0);
        issue_lookup_error_no_bank(0, 1, 10'd319, 0, 1,
                                   ERR_COMPUTE_MISS, 1, 16'h83d5);
        clear_new_descriptor;
        set_expected_identity(0);
        mgmt_req_external_safe = 1;
        send_mgmt(OP_ACTIVATE, 2'b11, ERR_BAD_BANK_MASK, 16'h83d6);
        check(directory_state[2:0] == ST_ACTIVE &&
              directory_state[5:3] == ST_INVALID,
              "malformed activation mask cannot mutate either bank");
        check(local_error_valid[0] &&
              local_error_code[7:0] == ERR_COMPUTE_MISS,
              "malformed activation cannot replace faulted-bank error scope");

        // CLAIM_FRESH uses a deferred descriptor install.  Exercise both
        // physical banks and prove that effective outputs switch atomically
        // one edge before the wide physical descriptor copy.
        test_deferred_claim_install(0, 16'h83e0);
        test_deferred_claim_install(1, 16'h83e8);

        // REBIND_RETAINED uses the same install overlay for lease fields, but
        // must preserve the retained content generation, slot directory and
        // publication count.  Observe old physical versus new effective
        // identity at commit, then the durable copy on the following edge.
        pulse_reset;
        setup_bank0_active(16'h8500);
        clear_new_descriptor;
        set_expected_identity(0);
        mgmt_req_drain_target = DRAIN_RETAINED;
        mgmt_req_external_safe = 1;
        send_mgmt(OP_BEGIN_DRAIN, 2'b01, STATUS_OK, 16'h8505);
        clear_new_descriptor;
        set_expected_identity(0);
        mgmt_req_external_safe = 1;
        send_mgmt(OP_FINISH_DRAIN, 2'b01, STATUS_OK, 16'h8506);
        check(directory_state[2:0] == ST_RETAINED &&
              dut.stage_ticket_q[0] == 0 &&
              dut.committed_count_q[0] == 1,
              "retained object is ready for deferred rebind test");
        set_new_descriptor(0);
        mgmt_req_new_stage_ticket = TICKET0 + 32'h100;
        mgmt_req_new_context_generation = CONTEXT0 + 32'h100;
        mgmt_req_new_physical_bank_generation = BANK_GEN0 + 32'h100;
        mgmt_req_new_cancellation_epoch = CANCEL0 + 32'h100;
        mgmt_req_new_matrix0_binding_token = BIND00 + 32'h100;
        mgmt_req_new_matrix1_binding_token = BIND01 + 32'h100;
        mgmt_req_expected_directory_generation = 16'd1;
        mgmt_req_expected_content_handle = CONTENT0;
        mgmt_req_expected_stage_ticket = 0;
        mgmt_req_expected_physical_bank_generation = BANK_GEN0;
        mgmt_req_external_safe = 1;
        mgmt_rsp_ready = 0;
        mgmt_req_opcode = OP_REBIND_RETAINED;
        mgmt_req_bank_mask = 2'b01;
        mgmt_req_tag = 16'h8507;
        mgmt_req_valid = 1;
        while (!mgmt_req_ready) @(negedge clk);
        @(posedge clk);
        #1;
        @(negedge clk);
        mgmt_req_valid = 0;
        clear_new_descriptor;
        timeout_count = 0;
        while (!mgmt_rsp_valid && timeout_count < 20) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(mgmt_rsp_valid && mgmt_rsp_status == STATUS_OK &&
              dut.descriptor_install_pending_q[0] &&
              !dut.descriptor_install_claim_q[0],
              "retained rebind reaches deferred lease-install edge");
        check(dut.stage_ticket_q[0] == 0 &&
              dut.context_generation_q[0] == CONTEXT0 &&
              dut.physical_bank_generation_q[0] == BANK_GEN0 &&
              dut.cancellation_epoch_q[0] == CANCEL0 &&
              dut.matrix0_binding_token_q[0] == BIND00,
              "rebind commit edge leaves physical lease descriptor old");
        check(directory_stage_ticket[31:0] == TICKET0 + 32'h100 &&
              directory_context_generation[31:0] == CONTEXT0 + 32'h100 &&
              directory_physical_bank_generation[31:0] ==
                  BANK_GEN0 + 32'h100 &&
              directory_cancellation_epoch[31:0] == CANCEL0 + 32'h100,
              "rebind commit edge exposes effective lease identity");
        check(directory_matrix0_binding_token[31:0] == BIND00 + 32'h100 &&
              directory_matrix1_binding_token[31:0] == BIND01 + 32'h100 &&
              directory_generation[15:0] == 16'd1 &&
              directory_content_handle[31:0] == CONTENT0 &&
              directory_committed_source_count[9:0] == 10'd1,
              "rebind preserves retained content authority and count");
        @(posedge clk);
        #1;
        check(!dut.descriptor_install_pending_q[0] &&
              dut.stage_ticket_q[0] == TICKET0 + 32'h100 &&
              dut.context_generation_q[0] == CONTEXT0 + 32'h100 &&
              dut.physical_bank_generation_q[0] == BANK_GEN0 + 32'h100 &&
              dut.cancellation_epoch_q[0] == CANCEL0 + 32'h100 &&
              dut.matrix0_binding_token_q[0] == BIND00 + 32'h100,
              "rebind following edge durably copies lease descriptor");
        check(dut.generation_q[0] == 16'd1 &&
              dut.content_handle_q[0] == CONTENT0 &&
              dut.committed_count_q[0] == 10'd1,
              "rebind physical copy preserves retained content fields");
        @(negedge clk);
        mgmt_rsp_ready = 1;
        @(posedge clk);
        #1;
        mgmt_rsp_ready = 0;

        // Repeat the retained-content overlay observation on physical bank1;
        // selection must not silently depend on the low-half descriptor.
        pulse_reset;
        scrub_one(1, 16'h8510);
        claim_bank(1);
        publish_one(1, 0, 0, 13'd1000, STATUS_OK, 1, 16'h8512);
        clear_new_descriptor;
        set_expected_identity(1);
        mgmt_req_external_safe = 1;
        send_mgmt(OP_PUBLISH_READY, 2'b10, STATUS_OK, 16'h8513);
        set_expected_identity(1);
        mgmt_req_external_safe = 1;
        send_mgmt(OP_ACTIVATE, 2'b10, STATUS_OK, 16'h8514);
        clear_new_descriptor;
        set_expected_identity(1);
        mgmt_req_drain_target = DRAIN_RETAINED;
        mgmt_req_external_safe = 1;
        send_mgmt(OP_BEGIN_DRAIN, 2'b10, STATUS_OK, 16'h8515);
        clear_new_descriptor;
        set_expected_identity(1);
        mgmt_req_external_safe = 1;
        send_mgmt(OP_FINISH_DRAIN, 2'b10, STATUS_OK, 16'h8516);
        check(directory_state[5:3] == ST_RETAINED &&
              dut.stage_ticket_q[1] == 0 &&
              dut.committed_count_q[1] == 1,
              "bank1 retained object is ready for deferred rebind");
        set_new_descriptor(1);
        mgmt_req_new_stage_ticket = TICKET1 + 32'h100;
        mgmt_req_new_context_generation = CONTEXT1 + 32'h100;
        mgmt_req_new_physical_bank_generation = BANK_GEN1 + 32'h100;
        mgmt_req_new_cancellation_epoch = CANCEL1 + 32'h100;
        mgmt_req_new_matrix0_binding_token = BIND10 + 32'h100;
        mgmt_req_new_matrix1_binding_token = BIND11 + 32'h100;
        mgmt_req_expected_directory_generation = 16'd1;
        mgmt_req_expected_content_handle = CONTENT1;
        mgmt_req_expected_stage_ticket = 0;
        mgmt_req_expected_physical_bank_generation = BANK_GEN1;
        mgmt_req_external_safe = 1;
        mgmt_rsp_ready = 0;
        mgmt_req_opcode = OP_REBIND_RETAINED;
        mgmt_req_bank_mask = 2'b10;
        mgmt_req_tag = 16'h8517;
        mgmt_req_valid = 1;
        while (!mgmt_req_ready) @(negedge clk);
        @(posedge clk);
        #1;
        @(negedge clk);
        mgmt_req_valid = 0;
        clear_new_descriptor;
        timeout_count = 0;
        while (!mgmt_rsp_valid && timeout_count < 20) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(mgmt_rsp_valid && mgmt_rsp_status == STATUS_OK &&
              dut.descriptor_install_pending_q[1] &&
              !dut.descriptor_install_claim_q[1],
              "bank1 retained rebind reaches deferred lease-install edge");
        check(dut.stage_ticket_q[1] == 0 &&
              dut.context_generation_q[1] == CONTEXT1 &&
              dut.physical_bank_generation_q[1] == BANK_GEN1 &&
              directory_stage_ticket[63:32] == TICKET1 + 32'h100 &&
              directory_context_generation[63:32] == CONTEXT1 + 32'h100 &&
              directory_physical_bank_generation[63:32] ==
                  BANK_GEN1 + 32'h100,
              "bank1 rebind commit separates physical and effective identity");
        check(directory_generation[31:16] == 16'd1 &&
              directory_content_handle[63:32] == CONTENT1 &&
              directory_committed_source_count[19:10] == 10'd1,
              "bank1 rebind preserves retained content authority");
        @(posedge clk);
        #1;
        check(!dut.descriptor_install_pending_q[1] &&
              dut.stage_ticket_q[1] == TICKET1 + 32'h100 &&
              dut.context_generation_q[1] == CONTEXT1 + 32'h100 &&
              dut.physical_bank_generation_q[1] == BANK_GEN1 + 32'h100 &&
              dut.committed_count_q[1] == 10'd1,
              "bank1 rebind following edge durably copies lease identity");
        @(negedge clk);
        mgmt_rsp_ready = 1;
        @(posedge clk);
        #1;
        mgmt_rsp_ready = 0;

        // An exact final close may arrive on the deferred copy edge.  It must
        // validate against the new effective identity, make the new descriptor
        // the durable ERROR scope, preserve the materialized CLAIM success,
        // and override the copied cancellation epoch with the close epoch.
        pulse_reset;
        scrub_one(1, 16'h8520);
        begin_claim_hold_at_commit(1, 16'h8521);
        check(dut.generation_q[1] == 0 &&
              directory_generation[31:16] == 16'd1,
              "bank1 close test is poised between effective and physical claim");
        @(negedge clk);
        force_error_bank_mask = 2'b10;
        force_error_code = ERR_ABORTED;
        force_error_data_untrusted = 0;
        force_error_causal_producers_drained = 1;
        force_error_directory_generation = {16'd1, 16'd0};
        force_error_stage_ticket = {TICKET1, 32'd0};
        force_error_content_handle = {CONTENT1, 32'd0};
        force_error_physical_bank_generation = {BANK_GEN1, 32'd0};
        force_error_cancellation_epoch = 32'h6f00_0016;
        force_error_tag = 16'h8522;
        force_error_rsp_ready = 0;
        force_error_valid = 1;
        #1;
        check(force_error_ready,
              "copy-edge close validates new bank1 effective identity");
        @(posedge clk);
        #1;
        check(mgmt_rsp_valid && mgmt_rsp_status == STATUS_OK &&
              mgmt_rsp_tag == 16'h8521,
              "copy-edge close cannot rewrite materialized CLAIM success");
        check(!dut.descriptor_install_pending_q[1] &&
              dut.generation_q[1] == 16'd1 &&
              dut.stage_ticket_q[1] == TICKET1 &&
              dut.content_handle_q[1] == CONTENT1 &&
              dut.physical_bank_generation_q[1] == BANK_GEN1,
              "copy-edge close durably installs new bank1 ERROR scope");
        check(dut.cancellation_epoch_q[1] == 32'h6f00_0016 &&
              directory_cancellation_epoch[63:32] == 32'h6f00_0016,
              "copy-edge force cancellation overrides descriptor copy");
        check(local_error_valid[1] &&
              local_error_code[15:8] == ERR_ABORTED &&
              local_error_directory_generation[31:16] == 16'd1 &&
              local_error_stage_ticket[63:32] == TICKET1 &&
              local_error_content_handle[63:32] == CONTENT1 &&
              local_error_physical_bank_generation[63:32] == BANK_GEN1,
              "copy-edge close captures new effective bank1 error scope");
        check(directory_state[5:3] == ST_DRAINING &&
              !force_error_rsp_valid,
              "copy-edge close drains behind held management response");
        @(negedge clk);
        force_error_valid = 0;
        mgmt_rsp_ready = 1;
        @(posedge clk);
        #1;
        mgmt_rsp_ready = 0;
        timeout_count = 0;
        while (!force_error_rsp_valid && timeout_count < 20) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(force_error_rsp_valid && force_error_rsp_status == STATUS_OK &&
              force_error_rsp_code == ERR_ABORTED &&
              force_error_rsp_tag == 16'h8522,
              "copy-edge close returns after CLAIM terminal retirement");
        @(negedge clk);
        force_error_rsp_ready = 1;
        @(posedge clk);
        #1;
        force_error_rsp_ready = 0;

        // A target-local physical response fault on the descriptor copy edge
        // similarly captures the new identity without corrupting the already
        // materialized success.  Target traffic is fenced while a probe to
        // the independently active bank continues to make progress.
        directed_phase = 854;
        pulse_reset;
        setup_bank0_active(16'h8540);
        scrub_one(1, 16'h8548);
        begin_claim_hold_at_commit(1, 16'h8549);
        auto_bank_responder = 0;
        lookup_rsp_ready = 0;
        fault_event_ready = 0;
        @(negedge clk);
        set_publication(1, 0, 0, 13'd1000);
        publish_req_tag = 16'h854a;
        publish_req_valid = 1;
        set_lookup(0, 0, 0, 0, 0, 16'h854b);
        lookup_req_valid = 1;
        bank1_rd_rsp_data = {128{1'b1}};
        bank1_rd_rsp_addr = 13'd0;
        bank1_rd_rsp_generation = BANK_GEN1;
        bank1_rd_rsp_lease_owner_ticket = TICKET1;
        bank1_rd_rsp_tag = 16'h0003;
        bank1_rd_rsp_status = STATUS_OK;
        bank1_rd_rsp_valid = 1;
        #1;
        check(!publish_req_ready && lookup_req_ready,
              "copy-edge target is fenced while other-bank probe is admitted");
        @(posedge clk);
        #1;
        check(mgmt_rsp_valid && mgmt_rsp_status == STATUS_OK &&
              mgmt_rsp_tag == 16'h8549,
              "copy-edge local fatal preserves materialized CLAIM success");
        check(!dut.descriptor_install_pending_q[1] &&
              dut.generation_q[1] == 16'd1 &&
              dut.stage_ticket_q[1] == TICKET1 &&
              dut.content_handle_q[1] == CONTENT1,
              "local-fatal edge still completes durable bank1 descriptor copy");
        check(!publish_req_ready,
              "registered bank1 fatal fence blocks target publication");
        @(negedge clk);
        publish_req_valid = 0;
        lookup_req_valid = 0;
        bank1_rd_rsp_valid = 0;
        wait_fault_materialized(1, 1);
        check(local_error_valid[1] && reset_required[1] &&
              local_error_code[15:8] == ERR_INTERNAL_STATE &&
              local_error_directory_generation[31:16] == 16'd1 &&
              local_error_stage_ticket[63:32] == TICKET1 &&
              local_error_content_handle[63:32] == CONTENT1 &&
              local_error_physical_bank_generation[63:32] == BANK_GEN1,
              "copy-edge local fatal captures new bank1 descriptor scope");
        timeout_count = 0;
        while (!lookup_rsp_valid && timeout_count < 20) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(lookup_rsp_valid && lookup_rsp_status == STATUS_OK &&
              lookup_rsp_hit && lookup_rsp_selected_bank_id == 0 &&
              lookup_rsp_user_tag == 16'h854b,
              "other-bank probe completes normally across copy-edge fatal");
        @(negedge clk);
        lookup_rsp_ready = 1;
        mgmt_rsp_ready = 1;
        fault_event_ready = 1;
        @(posedge clk);
        #1;
        lookup_rsp_ready = 0;
        mgmt_rsp_ready = 0;
        fault_event_ready = 0;

        // Reset is the only event allowed to discard a materialized response
        // and pending install.  It must revoke the architectural descriptor
        // without executing the deferred physical copy after reset.
        directed_phase = 856;
        pulse_reset;
        scrub_one(1, 16'h8560);
        begin_claim_hold_at_commit(1, 16'h8561);
        check(dut.descriptor_install_pending_q[1] && mgmt_rsp_valid,
              "reset-drop test begins with held response and pending install");
        @(negedge clk);
        rst_n = 0;
        @(posedge clk);
        #1;
        check(!dut.descriptor_install_pending_q[1] &&
              !dut.descriptor_install_claim_q[1] && !mgmt_rsp_valid &&
              !management_busy,
              "reset drops pending descriptor install and response slot");
        check(directory_state == {ST_INVALID, ST_INVALID} &&
              directory_generation == 0 &&
              directory_stage_ticket == 0 &&
              directory_content_handle == 0 &&
              directory_scrub_required == 2'b11,
              "reset revokes all deferred descriptor authority");
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1;
        @(posedge clk);
        #1;
        check(directory_state == {ST_INVALID, ST_INVALID} &&
              directory_scrub_required == 2'b11,
              "reset-drop recovery remains invalid and requires scrub");

        // FINISH_DRAIN to RETAINED has the analogous ticket rule.  The public
        // owner ticket is zero on the commit edge; a same-window exact close
        // must validate against and capture that zero authority while the
        // old physical ticket is cleared unconditionally on the next edge.
        directed_phase = 858;
        pulse_reset;
        setup_bank0_active(16'h83f0);
        clear_new_descriptor;
        set_expected_identity(0);
        mgmt_req_drain_target = DRAIN_RETAINED;
        mgmt_req_external_safe = 1;
        send_mgmt(OP_BEGIN_DRAIN, 2'b01, STATUS_OK, 16'h83f5);
        check(bank_drain_complete[0],
              "retained deferred-clear case reaches drain complete");
        clear_new_descriptor;
        set_expected_identity(0);
        mgmt_req_external_safe = 1;
        mgmt_rsp_ready = 0;
        mgmt_req_opcode = OP_FINISH_DRAIN;
        mgmt_req_bank_mask = 2'b01;
        mgmt_req_tag = 16'h83f6;
        mgmt_req_valid = 1;
        while (!mgmt_req_ready) @(negedge clk);
        @(posedge clk);
        #1;
        @(negedge clk);
        mgmt_req_valid = 0;
        timeout_count = 0;
        while (!mgmt_rsp_valid && timeout_count < 20) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(mgmt_rsp_valid && mgmt_rsp_status == STATUS_OK &&
              directory_state[2:0] == ST_RETAINED,
              "finish-retained reaches its registered commit edge");
        check(dut.stage_ticket_clear_pending_q[0] &&
              dut.stage_ticket_q[0] == TICKET0 &&
              directory_stage_ticket[31:0] == 0,
              "retained pending mask removes ticket authority on commit edge");
        @(negedge clk);
        force_error_bank_mask = 2'b01;
        force_error_code = ERR_ABORTED;
        force_error_data_untrusted = 0;
        force_error_causal_producers_drained = 1;
        force_error_directory_generation = {16'd0, 16'd1};
        force_error_stage_ticket = 64'd0;
        force_error_content_handle = {32'd0, CONTENT0};
        force_error_physical_bank_generation = {32'd0, BANK_GEN0};
        force_error_cancellation_epoch = CANCEL0;
        force_error_tag = 16'h83f7;
        force_error_rsp_ready = 0;
        force_error_valid = 1;
        check(force_error_ready,
              "retained pending-clear exact close validates ticket zero");
        @(posedge clk);
        #1;
        check(mgmt_rsp_valid && mgmt_rsp_status == STATUS_OK,
              "materialized FINISH response remains immutable across close");
        check(!dut.stage_ticket_clear_pending_q[0] &&
              dut.stage_ticket_q[0] == 0 &&
              directory_stage_ticket[31:0] == 0,
              "retained physical ticket clears on following edge");
        check(local_error_valid[0] &&
              local_error_stage_ticket[31:0] == 0,
              "retained-window close captures architecturally zero ticket");
        check(!force_error_rsp_valid,
              "retained-window close waits for held FINISH response");
        @(negedge clk);
        force_error_valid = 0;
        mgmt_rsp_ready = 1;
        @(posedge clk);
        #1;
        mgmt_rsp_ready = 0;
        timeout_count = 0;
        while (!force_error_rsp_valid && timeout_count < 20) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(force_error_rsp_valid && force_error_rsp_status == STATUS_OK &&
              force_error_rsp_code == ERR_ABORTED,
              "retained pending-clear exact close completes after response drain");
        @(negedge clk);
        force_error_rsp_ready = 1;
        @(posedge clk);
        #1;
        force_error_rsp_ready = 0;

        // Ordinary management has a fixed registered C0/C1/C2 pipeline:
        // acceptance captures only, decision remains non-mutating, and the
        // response/state mutation materialize together on the third edge.
        directed_phase = 859;
        pulse_reset;
        setup_bank0_ready(16'h8580);
        @(negedge clk);
        clear_new_descriptor;
        set_expected_identity(0);
        mgmt_req_external_safe = 1;
        mgmt_req_opcode = OP_ACTIVATE;
        mgmt_req_bank_mask = 2'b01;
        mgmt_req_tag = 16'h8585;
        mgmt_req_valid = 1;
        check(mgmt_req_ready,
              "C0 activation request has an execution landing slot");
        @(posedge clk);
        #1;
        check(dut.mgmt_exec_valid_q && !dut.mgmt_decision_valid_q &&
              !mgmt_rsp_valid && directory_state[2:0] == ST_READY,
              "C0 captures management without response or state mutation");
        @(negedge clk);
        mgmt_req_valid = 0;
        @(posedge clk);
        #1;
        check(!dut.mgmt_exec_valid_q && dut.mgmt_decision_valid_q &&
              !mgmt_rsp_valid && directory_state[2:0] == ST_READY,
              "C1 registers decision without response or state mutation");
        @(posedge clk);
        #1;
        check(!dut.mgmt_decision_valid_q && mgmt_rsp_valid &&
              mgmt_rsp_status == STATUS_OK && mgmt_rsp_tag == 16'h8585 &&
              directory_state[2:0] == ST_ACTIVE,
              "C2 atomically materializes activation response and mutation");
        @(negedge clk);
        mgmt_rsp_ready = 1;
        @(posedge clk);
        #1;
        mgmt_rsp_ready = 0;

        // A target fault first visible while the registered decision is ready
        // to commit must hold that decision for one edge, latch the collision,
        // and then return the fault instead of transiently activating.
        directed_phase = 860;
        pulse_reset;
        setup_bank0_ready(16'h8590);
        auto_bank_responder = 0;
        fault_event_ready = 0;
        @(negedge clk);
        clear_new_descriptor;
        set_expected_identity(0);
        mgmt_req_external_safe = 1;
        mgmt_req_opcode = OP_ACTIVATE;
        mgmt_req_bank_mask = 2'b01;
        mgmt_req_tag = 16'h8595;
        mgmt_req_valid = 1;
        while (!mgmt_req_ready) @(negedge clk);
        @(posedge clk);
        #1;
        @(negedge clk);
        mgmt_req_valid = 0;
        @(posedge clk);
        #1;
        check(dut.mgmt_decision_valid_q && !mgmt_rsp_valid &&
              directory_state[2:0] == ST_READY,
              "fault-collision case reaches C1 decision position");
        @(negedge clk);
        bank0_rd_rsp_data = {128{1'b1}};
        bank0_rd_rsp_addr = 13'd100;
        bank0_rd_rsp_generation = BANK_GEN0;
        bank0_rd_rsp_lease_owner_ticket = TICKET0;
        bank0_rd_rsp_tag = 16'h0003;
        bank0_rd_rsp_status = STATUS_OK;
        bank0_rd_rsp_valid = 1;
        @(posedge clk);
        #1;
        check(dut.mgmt_decision_valid_q && !mgmt_rsp_valid &&
              directory_state[2:0] == ST_READY,
              "decision-edge fault holds command and prevents activation");
        @(negedge clk);
        bank0_rd_rsp_valid = 0;
        wait_fault_materialized(0, 1);
        check(local_error_valid[0] && reset_required[0] &&
              local_error_code[7:0] == ERR_INTERNAL_STATE,
              "decision-edge orphan captures directory-fatal scope");
        timeout_count = 0;
        while (!mgmt_rsp_valid && timeout_count < 10) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(!dut.mgmt_decision_valid_q && mgmt_rsp_valid &&
              mgmt_rsp_status == ERR_INTERNAL_STATE &&
              mgmt_rsp_tag == 16'h8595 &&
              directory_state[2:0] == ST_READY,
              "remembered C2 collision returns fault without mutation");
        @(negedge clk);
        mgmt_rsp_ready = 1;
        fault_event_ready = 1;
        @(posedge clk);
        #1;
        mgmt_rsp_ready = 0;
        fault_event_ready = 0;

        // Exact final close at the C2 decision edge is the management cut.
        // The decision cannot commit success, its unique terminal is abort,
        // and the force response waits for that terminal to retire.
        directed_phase = 861;
        pulse_reset;
        setup_bank0_ready(16'h85a0);
        @(negedge clk);
        clear_new_descriptor;
        set_expected_identity(0);
        mgmt_req_external_safe = 1;
        mgmt_req_opcode = OP_ACTIVATE;
        mgmt_req_bank_mask = 2'b01;
        mgmt_req_tag = 16'h85a5;
        mgmt_req_valid = 1;
        while (!mgmt_req_ready) @(negedge clk);
        @(posedge clk);
        #1;
        @(negedge clk);
        mgmt_req_valid = 0;
        @(posedge clk);
        #1;
        check(dut.mgmt_decision_valid_q && !mgmt_rsp_valid &&
              directory_state[2:0] == ST_READY,
              "force-collision case reaches C1 decision position");
        @(negedge clk);
        set_exact_abort_bank0(16'h85a6);
        force_error_rsp_ready = 0;
        force_error_valid = 1;
        #1;
        check(force_error_ready,
              "exact close is admitted on management decision edge");
        @(posedge clk);
        #1;
        check(dut.mgmt_decision_valid_q && !mgmt_rsp_valid &&
              directory_state[2:0] == ST_DRAINING &&
              dut.drain_target_q[0] == DRAIN_ERROR,
              "decision-edge close cuts activation before success commit");
        @(negedge clk);
        force_error_valid = 0;
        @(posedge clk);
        #1;
        check(!dut.mgmt_decision_valid_q && mgmt_rsp_valid &&
              mgmt_rsp_status == ERR_ABORTED &&
              mgmt_rsp_tag == 16'h85a5 && !force_error_rsp_valid,
              "cut decision receives one abort terminal before force response");
        repeat (2) begin
            @(posedge clk);
            #1;
            check(mgmt_rsp_valid && mgmt_rsp_status == ERR_ABORTED &&
                  !force_error_rsp_valid,
                  "held cut-management response blocks close completion");
        end
        @(negedge clk);
        mgmt_rsp_ready = 1;
        @(posedge clk);
        #1;
        mgmt_rsp_ready = 0;
        timeout_count = 0;
        while (!force_error_rsp_valid && timeout_count < 20) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(force_error_rsp_valid && force_error_rsp_status == STATUS_OK &&
              force_error_rsp_code == ERR_ABORTED &&
              force_error_rsp_tag == 16'h85a6,
              "decision-edge close completes after management terminal drain");
        @(negedge clk);
        force_error_rsp_ready = 1;
        @(posedge clk);
        #1;
        force_error_rsp_ready = 0;

        // A fatal directory result must fence new same-bank admission on its
        // discovery edge, before the sticky error register exists.  A safe
        // publication to the other physical directory still fires.
        directed_phase = 862;
        pulse_reset;
        scrub_both;
        claim_bank(0);
        claim_bank(1);
        publish_one(0, 0, 0, 13'd100, STATUS_OK, 1, 16'h8600);
        clear_new_descriptor;
        set_expected_identity(0);
        mgmt_req_external_safe = 1;
        send_mgmt(OP_PUBLISH_READY, 2'b01, STATUS_OK, 16'h8601);
        set_expected_identity(0);
        mgmt_req_external_safe = 1;
        send_mgmt(OP_ACTIVATE, 2'b01, STATUS_OK, 16'h8602);
        @(negedge clk);
        dut.directory_mem0[1] =
            {1'b1, 1'b0, 16'd1, 1'b0, 13'd120};
        auto_bank_responder = 0;
        bank0_rd_req_ready = 0;
        bank1_rd_req_ready = 0;
        lookup_rsp_ready = 0;
        publish_rsp_ready = 0;
        fault_event_ready = 0;
        issue_lookup_no_wait(0, 1, 0, 1, 0, 16'h8603);
        set_lookup(0, 1, 0, 0, 0, 16'h8604);
        lookup_req_valid = 1;
        set_publication(1, 0, 1, 13'd1020);
        publish_req_tag = 16'h8605;
        publish_req_valid = 1;
        #1;
        check(!local_error_valid[0] && !lookup_req_ready &&
              publish_req_ready,
              "directory-result fault fences target while other bank progresses");
        @(posedge clk);
        #1;
        @(negedge clk);
        lookup_req_valid = 0;
        publish_req_valid = 0;
        wait_fault_materialized(0, 1);
        check(local_error_valid[0] &&
              local_error_code[7:0] == ERR_DIRECTORY_INCOMPLETE,
              "directory-result fatal materializes after discovery fence");
        timeout_count = 0;
        while ((!lookup_rsp_valid || !publish_rsp_valid) &&
               timeout_count < 30) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(lookup_rsp_valid &&
              lookup_rsp_status == ERR_DIRECTORY_INCOMPLETE &&
              lookup_rsp_user_tag == 16'h8603 && !lookup_rsp_hit &&
              lookup_rsp_weight_data == 0,
              "fatal directory result produces one zero terminal");
        check(publish_rsp_valid && publish_rsp_status == STATUS_OK &&
              publish_rsp_tag == 16'h8605 && publish_rsp_committed,
              "other-bank publication commits across directory-result fault");
        @(negedge clk);
        lookup_rsp_ready = 1;
        publish_rsp_ready = 1;
        fault_event_ready = 1;
        @(posedge clk);
        #1;
        lookup_rsp_ready = 0;
        publish_rsp_ready = 0;
        fault_event_ready = 0;

        // The publication pre-read/result path has the symmetric discovery
        // fence.  A same-key relocation blocks a younger target publication
        // while an unrelated probe on the other bank remains admissible.
        pulse_reset;
        scrub_both;
        claim_bank(0);
        claim_bank(1);
        publish_one(0, 0, 1, 13'd100, STATUS_OK, 1, 16'h8620);
        publish_one(1, 0, 0, 13'd1000, STATUS_OK, 1, 16'h8621);
        clear_new_descriptor;
        set_expected_identity(1);
        mgmt_req_external_safe = 1;
        send_mgmt(OP_PUBLISH_READY, 2'b10, STATUS_OK, 16'h8622);
        set_expected_identity(1);
        mgmt_req_external_safe = 1;
        send_mgmt(OP_ACTIVATE, 2'b10, STATUS_OK, 16'h8623);
        auto_bank_responder = 0;
        lookup_rsp_ready = 0;
        publish_rsp_ready = 0;
        fault_event_ready = 0;
        @(negedge clk);
        set_publication(0, 0, 1, 13'd120);
        publish_req_tag = 16'h8624;
        publish_req_valid = 1;
        sampled_count = 0;
        timeout_count = 0;
        while (!sampled_count && timeout_count < 20) begin
            @(posedge clk);
            sampled_count = publish_req_ready;
            #1;
            timeout_count = timeout_count + 1;
        end
        check(sampled_count,
              "relocation publication acceptance is sampled on fire edge");
        @(negedge clk);
        publish_req_valid = 0;
        set_publication(0, 0, 2, 13'd140);
        publish_req_tag = 16'h8625;
        publish_req_valid = 1;
        set_lookup(1, 0, 0, 0, 0, 16'h8626);
        lookup_req_valid = 1;
        #1;
        check(!local_error_valid[0] && !publish_req_ready &&
              lookup_req_ready,
              "publication-result fault fences target while other bank progresses");
        @(posedge clk);
        #1;
        @(negedge clk);
        publish_req_valid = 0;
        lookup_req_valid = 0;
        wait_fault_materialized(0, 1);
        check(local_error_valid[0] &&
              local_error_code[7:0] == ERR_DIRECTORY_RELOCATION,
              "publication-result fatal materializes after discovery fence");
        timeout_count = 0;
        while ((!publish_rsp_valid || !lookup_rsp_valid) &&
               timeout_count < 30) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(publish_rsp_valid &&
              publish_rsp_status == ERR_DIRECTORY_RELOCATION &&
              publish_rsp_tag == 16'h8624 && !publish_rsp_committed,
              "relocation discovery returns one noncommitting terminal");
        check(lookup_rsp_valid && lookup_rsp_status == STATUS_OK &&
              lookup_rsp_hit && lookup_rsp_user_tag == 16'h8626,
              "other-bank probe completes across publication-result fault");
        check(dut.committed_count_q[0] == 10'd1,
              "faulted and fenced publications cannot increment source count");
        @(negedge clk);
        lookup_rsp_ready = 1;
        publish_rsp_ready = 1;
        fault_event_ready = 1;
        @(posedge clk);
        #1;
        lookup_rsp_ready = 0;
        publish_rsp_ready = 0;
        fault_event_ready = 0;

        // The three public causal counters must reflect physical ownership,
        // not a latency assumption.  Walk one compute through WAIT_DIR,
        // BANK_PENDING, BANK_WAIT, held logical response, and retirement.
        pulse_reset;
        setup_bank0_active(16'h8640);
        auto_bank_responder = 0;
        bank0_rd_req_ready = 0;
        bank1_rd_req_ready = 0;
        lookup_rsp_ready = 0;
        issue_lookup_no_wait(0, 1, 0, 0, 2, 16'h8645);
        #1;
        check(lookup_outstanding == 1 &&
              directory_bank_ref_count[1:0] == 1 &&
              directory_to_bank_pending[1:0] == 0 &&
              bank_rsp_outstanding[1:0] == 0,
              "accepted WAIT_DIR owns ref but no pending or bank response");
        @(posedge clk);
        #1;
        check(bank0_rd_req_valid &&
              directory_bank_ref_count[1:0] == 1 &&
              directory_to_bank_pending[1:0] == 1 &&
              bank_rsp_outstanding[1:0] == 0,
              "directory hit enters one held BANK_PENDING position");
        check(directory_bank_ref_count[3:2] == 0 &&
              directory_to_bank_pending[3:2] == 0 &&
              bank_rsp_outstanding[3:2] == 0,
              "unselected bank counters remain zero throughout transaction");
        manual_addr0 = bank0_rd_req_addr;
        manual_generation0 = bank0_rd_req_generation;
        manual_ticket0 = bank0_rd_req_lease_owner_ticket;
        manual_tag0 = bank0_rd_req_tag;
        @(negedge clk);
        bank0_rd_req_ready = 1;
        @(posedge clk);
        #1;
        check(directory_bank_ref_count[1:0] == 1 &&
              directory_to_bank_pending[1:0] == 0 &&
              bank_rsp_outstanding[1:0] == 1 &&
              !bank0_rd_req_valid,
              "bank request fire transfers pending credit to response credit");
        @(negedge clk);
        bank0_rd_req_ready = 0;
        bank0_rd_rsp_data = bank_data_pattern(0, manual_addr0);
        bank0_rd_rsp_addr = manual_addr0;
        bank0_rd_rsp_generation = manual_generation0;
        bank0_rd_rsp_lease_owner_ticket = manual_ticket0;
        bank0_rd_rsp_tag = manual_tag0;
        bank0_rd_rsp_status = STATUS_OK;
        bank0_rd_rsp_valid = 1;
        #1;
        check(bank0_rd_rsp_ready,
              "owned causal bank response is accepted at aggregate head");
        @(posedge clk);
        #1;
        check(lookup_rsp_valid && lookup_rsp_status == STATUS_OK &&
              lookup_rsp_user_tag == 16'h8645 &&
              lookup_rsp_weight_addr == manual_addr0 &&
              lookup_rsp_weight_data == bank_data_pattern(0, manual_addr0),
              "bank response materializes exact held logical success");
        check(directory_bank_ref_count[1:0] == 1 &&
              directory_to_bank_pending[1:0] == 0 &&
              bank_rsp_outstanding[1:0] == 0 &&
              lookup_outstanding == 1,
              "bank response fire releases physical credit but retains ref");
        @(negedge clk);
        bank0_rd_rsp_valid = 0;
        repeat (3) begin
            @(posedge clk);
            #1;
            check(lookup_rsp_valid &&
                  directory_bank_ref_count[1:0] == 1 &&
                  directory_to_bank_pending[1:0] == 0 &&
                  bank_rsp_outstanding[1:0] == 0,
                  "held logical response retains exactly one causal reference");
        end
        @(negedge clk);
        lookup_rsp_ready = 1;
        @(posedge clk);
        #1;
        check(!lookup_rsp_valid && lookup_outstanding == 0 &&
              directory_bank_ref_count[1:0] == 0 &&
              directory_to_bank_pending[1:0] == 0 &&
              bank_rsp_outstanding[1:0] == 0 && bank_quiescent[0],
              "logical response retirement releases final causal reference");
        lookup_rsp_ready = 0;

        // A tag naming a live but non-oldest slot in the same physical bank
        // is not an out-of-order completion mechanism.  It is an internal
        // correlation failure and consumes the aggregate head as zero data.
        pulse_reset;
        setup_bank0_active(16'h8650);
        auto_bank_responder = 0;
        bank0_rd_req_ready = 0;
        lookup_rsp_ready = 0;
        fault_event_ready = 0;
        issue_lookup_no_wait(0, 1, 0, 0, 3, 16'h8655);
        while (!bank0_rd_req_valid) @(negedge clk);
        manual_addr0 = bank0_rd_req_addr;
        manual_generation0 = bank0_rd_req_generation;
        manual_ticket0 = bank0_rd_req_lease_owner_ticket;
        manual_tag0 = bank0_rd_req_tag;
        bank0_rd_req_ready = 1;
        @(posedge clk);
        #1;
        @(negedge clk);
        bank0_rd_req_ready = 0;
        issue_lookup_no_wait(0, 1, 0, 0, 4, 16'h8656);
        while (!bank0_rd_req_valid) @(negedge clk);
        manual_addr1 = bank0_rd_req_addr;
        manual_generation1 = bank0_rd_req_generation;
        manual_ticket1 = bank0_rd_req_lease_owner_ticket;
        manual_tag1 = bank0_rd_req_tag;
        check(manual_tag1[1:0] != manual_tag0[1:0],
              "two same-bank requests own distinct live order slots");
        bank0_rd_req_ready = 1;
        @(posedge clk);
        #1;
        @(negedge clk);
        bank0_rd_req_ready = 0;
        bank0_rd_rsp_data = bank_data_pattern(0, manual_addr1);
        bank0_rd_rsp_addr = manual_addr1;
        bank0_rd_rsp_generation = manual_generation1;
        bank0_rd_rsp_lease_owner_ticket = manual_ticket1;
        bank0_rd_rsp_tag = manual_tag1;
        bank0_rd_rsp_status = STATUS_OK;
        bank0_rd_rsp_valid = 1;
        #1;
        check(bank0_rd_rsp_ready,
              "live non-oldest same-bank tag is consumed as internal fault");
        @(posedge clk);
        #1;
        @(negedge clk);
        bank0_rd_rsp_valid = 0;
        wait_fault_materialized(0, 1);
        timeout_count = 0;
        while (!lookup_rsp_valid && timeout_count < 10) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(local_error_valid[0] && reset_required[0] &&
              local_error_code[7:0] == ERR_INTERNAL_STATE &&
              lookup_rsp_valid && lookup_rsp_status == ERR_INTERNAL_STATE &&
              lookup_rsp_user_tag == 16'h8655 && !lookup_rsp_hit &&
              lookup_rsp_weight_data == 0 && lookup_rsp_slot_base == 0 &&
              lookup_rsp_weight_addr == 0,
              "non-oldest response fails aggregate head closed");

        // A live bank0 token returned on the bank1 physical channel has no
        // bank1 owner.  It must fault bank1 immediately and cannot consume the
        // still-outstanding bank0 transaction.
        pulse_reset;
        setup_both_active(16'h8660);
        auto_bank_responder = 0;
        bank0_rd_req_ready = 0;
        bank1_rd_req_ready = 0;
        fault_event_ready = 0;
        issue_lookup_no_wait(0, 1, 0, 0, 5, 16'h8665);
        while (!bank0_rd_req_valid) @(negedge clk);
        manual_addr0 = bank0_rd_req_addr;
        manual_generation0 = bank0_rd_req_generation;
        manual_ticket0 = bank0_rd_req_lease_owner_ticket;
        manual_tag0 = bank0_rd_req_tag;
        bank0_rd_req_ready = 1;
        @(posedge clk);
        #1;
        @(negedge clk);
        bank0_rd_req_ready = 0;
        bank1_rd_rsp_data = bank_data_pattern(0, manual_addr0);
        bank1_rd_rsp_addr = manual_addr0;
        bank1_rd_rsp_generation = manual_generation0;
        bank1_rd_rsp_lease_owner_ticket = manual_ticket0;
        bank1_rd_rsp_tag = manual_tag0;
        bank1_rd_rsp_status = STATUS_OK;
        bank1_rd_rsp_valid = 1;
        #1;
        check(!bank1_rd_rsp_ready,
              "wrong physical response channel has no acceptance owner");
        @(posedge clk);
        #1;
        @(negedge clk);
        bank1_rd_rsp_valid = 0;
        wait_fault_materialized(1, 1);
        check(local_error_valid[1] && reset_required[1] &&
              local_error_code[15:8] == ERR_INTERNAL_STATE &&
              bank_rsp_outstanding[1:0] == 1 &&
              directory_bank_ref_count[1:0] == 1,
              "wrong-channel fault leaves original bank0 causal work owned");

        // Simultaneous orphan responses poison both banks independently.  The
        // one-deep fault-event channel must serialize bank0 before bank1 and
        // hold each event stable under backpressure.
        pulse_reset;
        setup_both_active(16'h8680);
        auto_bank_responder = 0;
        fault_event_ready = 0;
        @(negedge clk);
        bank0_rd_rsp_data = {128{1'b1}};
        bank0_rd_rsp_addr = 13'd100;
        bank0_rd_rsp_generation = BANK_GEN0;
        bank0_rd_rsp_lease_owner_ticket = TICKET0;
        bank0_rd_rsp_tag = 16'h0003;
        bank0_rd_rsp_status = STATUS_OK;
        bank1_rd_rsp_data = {128{1'b1}};
        bank1_rd_rsp_addr = 13'd1000;
        bank1_rd_rsp_generation = BANK_GEN1;
        bank1_rd_rsp_lease_owner_ticket = TICKET1;
        bank1_rd_rsp_tag = 16'h0003;
        bank1_rd_rsp_status = STATUS_OK;
        bank0_rd_rsp_valid = 1;
        bank1_rd_rsp_valid = 1;
        @(posedge clk);
        #1;
        @(negedge clk);
        bank0_rd_rsp_valid = 0;
        bank1_rd_rsp_valid = 0;
        timeout_count = 0;
        while ((local_error_valid != 2'b11 || !fault_event_valid) &&
               timeout_count < 10) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(local_error_valid == 2'b11 && reset_required == 2'b11 &&
              local_error_code == {ERR_INTERNAL_STATE, ERR_INTERNAL_STATE},
              "simultaneous physical faults capture both bank-local records");
        check(fault_event_valid && fault_event_bank_mask == 2'b01 &&
              fault_event_code == ERR_INTERNAL_STATE,
              "simultaneous faults present bank0 event first");
        repeat (2) begin
            @(posedge clk);
            #1;
            check(fault_event_valid && fault_event_bank_mask == 2'b01 &&
                  fault_event_code == ERR_INTERNAL_STATE,
                  "bank0 fault event is stable while backpressured");
        end
        @(negedge clk);
        fault_event_ready = 1;
        @(posedge clk);
        #1;
        check(fault_event_valid && fault_event_bank_mask == 2'b10 &&
              fault_event_code == ERR_INTERNAL_STATE,
              "bank1 event follows bank0 event retirement");
        @(negedge clk);
        fault_event_ready = 0;
        repeat (2) begin
            @(posedge clk);
            #1;
            check(fault_event_valid && fault_event_bank_mask == 2'b10 &&
                  fault_event_code == ERR_INTERNAL_STATE,
                  "bank1 fault event is stable while backpressured");
        end
        @(negedge clk);
        fault_event_ready = 1;
        @(posedge clk);
        #1;
        check(!fault_event_valid,
              "both simultaneous fault events retire exactly once");
        fault_event_ready = 0;

        // Reset-drop coverage for every externally meaningful lookup and
        // publication pipeline position.  Cross-reset transactions may be
        // discarded, while BRAM payload bits remain physically untouched.

        // 1) Publication synchronous pre-read/execution position.
        directed_phase = 870;
        pulse_reset;
        scrub_one(0, 16'h8700);
        claim_bank(0);
        auto_bank_responder = 0;
        @(negedge clk);
        set_publication(0, 0, 9, 13'd300);
        publish_req_tag = 16'h8701;
        publish_req_valid = 1;
        #1;
        check(publish_req_ready,
              "publication reset-drop request has execution credit");
        @(posedge clk);
        #1;
        check(publication_busy && dut.pub_exec_valid_q && !publish_rsp_valid,
              "publication reset-drop occupies pre-read execution position");
        @(negedge clk);
        publish_req_valid = 0;
        reset_drop_from_negedge;
        check((dut.directory_mem0[9] == 32'd0) ||
              (dut.directory_mem0[9] == {2'b11, 16'd1, 1'b0, 13'd300}),
              "reset-edge publication leaves only an atomic stale entry");
        check(directory_scrub_required[0] && !directory_content_valid[0],
              "reset-edge stale publication never restores authority");

        // 2) Lookup synchronous directory-read position.
        directed_phase = 871;
        pulse_reset;
        setup_bank0_active(16'h8710);
        auto_bank_responder = 0;
        bank0_rd_req_ready = 0;
        issue_lookup_no_wait(0, 1, 0, 0, 1, 16'h8711);
        check(directory_read_busy && lookup_outstanding == 1 &&
              directory_bank_ref_count[1:0] == 1,
              "lookup reset-drop occupies synchronous directory read");
        reset_drop_from_negedge;

        // 3) Checked hit held in BANK_PENDING behind bank ready low.
        directed_phase = 872;
        pulse_reset;
        setup_bank0_active(16'h8720);
        auto_bank_responder = 0;
        bank0_rd_req_ready = 0;
        issue_lookup_no_wait(0, 1, 0, 0, 2, 16'h8721);
        @(posedge clk);
        #1;
        @(negedge clk);
        check(bank0_rd_req_valid &&
              directory_to_bank_pending[1:0] == 1 &&
              bank_rsp_outstanding[1:0] == 0,
              "lookup reset-drop occupies held BANK_PENDING position");
        reset_drop_from_negedge;

        // 4) Physical request accepted, response credit in BANK_WAIT.
        directed_phase = 873;
        pulse_reset;
        setup_bank0_active(16'h8730);
        auto_bank_responder = 0;
        bank0_rd_req_ready = 0;
        issue_lookup_no_wait(0, 1, 0, 0, 3, 16'h8731);
        while (!bank0_rd_req_valid) @(negedge clk);
        bank0_rd_req_ready = 1;
        @(posedge clk);
        #1;
        @(negedge clk);
        bank0_rd_req_ready = 0;
        check(bank_rsp_outstanding[1:0] == 1 &&
              directory_bank_ref_count[1:0] == 1,
              "lookup reset-drop owns one BANK_WAIT response credit");
        reset_drop_from_negedge;

        // 5) Younger bank1 physical response held behind older bank0 work.
        directed_phase = 874;
        pulse_reset;
        setup_both_active(16'h8740);
        auto_bank_responder = 0;
        bank0_rd_req_ready = 0;
        bank1_rd_req_ready = 0;
        lookup_rsp_ready = 0;
        issue_lookup_no_wait(0, 1, 0, 0, 4, 16'h8741);
        while (!bank0_rd_req_valid) @(negedge clk);
        bank0_rd_req_ready = 1;
        @(posedge clk);
        #1;
        @(negedge clk);
        bank0_rd_req_ready = 0;
        issue_lookup_no_wait(1, 1, 0, 0, 5, 16'h8742);
        while (!bank1_rd_req_valid) @(negedge clk);
        manual_addr1 = bank1_rd_req_addr;
        manual_generation1 = bank1_rd_req_generation;
        manual_ticket1 = bank1_rd_req_lease_owner_ticket;
        manual_tag1 = bank1_rd_req_tag;
        bank1_rd_req_ready = 1;
        @(posedge clk);
        #1;
        @(negedge clk);
        bank1_rd_req_ready = 0;
        bank1_rd_rsp_data = bank_data_pattern(1, manual_addr1);
        bank1_rd_rsp_addr = manual_addr1;
        bank1_rd_rsp_generation = manual_generation1;
        bank1_rd_rsp_lease_owner_ticket = manual_ticket1;
        bank1_rd_rsp_tag = manual_tag1;
        bank1_rd_rsp_status = STATUS_OK;
        bank1_rd_rsp_valid = 1;
        #1;
        check(!bank1_rd_rsp_ready && bank_rsp_outstanding[3:2] == 1,
              "lookup reset-drop holds younger physical response by order");
        reset_drop_from_negedge;

        // 6) Fully materialized logical response held by sink backpressure.
        directed_phase = 875;
        pulse_reset;
        setup_bank0_active(16'h8750);
        auto_bank_responder = 1;
        bank0_rd_req_ready = 1;
        lookup_rsp_ready = 0;
        issue_lookup_no_wait(0, 1, 0, 0, 6, 16'h8751);
        timeout_count = 0;
        while (!lookup_rsp_valid && timeout_count < 20) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(lookup_rsp_valid && lookup_rsp_status == STATUS_OK &&
              directory_bank_ref_count[1:0] == 1,
              "lookup reset-drop holds materialized logical response");
        @(negedge clk);
        reset_drop_from_negedge;

        // Directory generation must never wrap.  White-box setup avoids
        // issuing 65,535 leases solely to reach the architected boundary.
        // CLAIM captures at C0; its execution edge E discovers FFFF and
        // immediately fences the target, while the registered rich bundle
        // becomes authoritative at E+1.  Because the pre-claim bank remains
        // INVALID, a same-scope force request is caller-local WRONG_STATE,
        // not a fictitious exact close.  It cannot replace the generation
        // exhaustion first error or mutate the rejected claim descriptor.
        directed_phase = 880;
        pulse_reset;
        scrub_one(0, 16'h8400);
        @(negedge clk);
        dut.generation_q[0] = 16'hffff;
        dut.generation_initialized_q[0] = 1'b1;
        set_new_descriptor(0);
        mgmt_req_expected_directory_generation = 16'hffff;
        mgmt_req_external_safe = 1;
        mgmt_rsp_ready = 0;
        fault_event_ready = 0;
        mgmt_req_opcode = OP_CLAIM_FRESH;
        mgmt_req_bank_mask = 2'b01;
        mgmt_req_tag = 16'h8401;
        mgmt_req_valid = 1;
        while (!mgmt_req_ready) @(negedge clk);
        @(posedge clk);
        #1;
        check(dut.mgmt_exec_valid_q && !mgmt_rsp_valid &&
              directory_state[2:0] == ST_INVALID,
              "generation-exhaustion C0 only captures CLAIM transport");
        @(negedge clk);
        mgmt_req_valid = 0;
        clear_new_descriptor;
        #1;
        check(dut.mgmt_generation_fault_candidate_w &&
              dut.fast_fault_now_w[0],
              "generation-exhaustion exec edge has immediate target fence");
        @(posedge clk);
        #1;
        check(dut.mgmt_decision_valid_q && !mgmt_rsp_valid &&
              local_error_valid[0] &&
              local_error_code[7:0] == ERR_GENERATION_EXHAUSTED,
              "generation-exhaustion E to E+1 bundle precedes terminal");

        @(negedge clk);
        force_error_bank_mask = 2'b01;
        force_error_code = ERR_ABORTED;
        force_error_data_untrusted = 0;
        force_error_causal_producers_drained = 1;
        force_error_directory_generation = {16'd0, 16'hffff};
        force_error_stage_ticket = 64'd0;
        force_error_content_handle = 64'd0;
        force_error_physical_bank_generation = 64'd0;
        force_error_cancellation_epoch = CANCEL0;
        force_error_tag = 16'h8402;
        force_error_rsp_ready = 0;
        force_error_valid = 1;
        check(force_error_ready,
              "post-exhaustion force request has terminal response credit");
        @(posedge clk);
        #1;
        check(force_error_rsp_valid &&
              force_error_rsp_status == ERR_WRONG_STATE &&
              force_error_rsp_state[2:0] == ST_INVALID,
              "final close against rejected INVALID claim is caller-local");
        @(negedge clk);
        force_error_valid = 0;
        wait_fault_materialized(0, 1);
        check(directory_generation[15:0] == 16'hffff &&
              directory_state[2:0] == ST_INVALID &&
              !directory_content_valid[0],
              "generation exhaustion cannot wrap or install content");
        check(directory_stage_ticket[31:0] == 0 &&
              directory_content_handle[31:0] == 0 &&
              directory_physical_bank_generation[31:0] == 0,
              "rejected exhausted CLAIM cannot install descriptor identity");
        check(reset_required[0] && local_error_valid[0] &&
              local_error_code[7:0] == ERR_GENERATION_EXHAUSTED &&
              local_error_source[2:0] == 3'd0 &&
              local_error_detail[31:0] == 32'h0000_ffff,
              "generation exhaustion remains immutable first error");
        check(local_error_directory_generation[15:0] == 16'hffff &&
              local_error_stage_ticket[31:0] == 0 &&
              local_error_content_handle[31:0] == 0 &&
              local_error_physical_bank_generation[31:0] == 0,
              "generation error scope is pre-claim INVALID authority");
        timeout_count = 0;
        while (!mgmt_rsp_valid && timeout_count < 20) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(mgmt_rsp_valid && mgmt_rsp_opcode == OP_CLAIM_FRESH &&
              mgmt_rsp_tag == 16'h8401 &&
              mgmt_rsp_status == ERR_GENERATION_EXHAUSTED,
              "exhausted CLAIM receives unique generation-fatal terminal");
        repeat (2) begin
            @(posedge clk);
            #1;
            check(mgmt_rsp_valid &&
                  mgmt_rsp_status == ERR_GENERATION_EXHAUSTED &&
                  force_error_rsp_valid &&
                  force_error_rsp_status == ERR_WRONG_STATE,
                  "generation and caller-local force terminals stay stable");
        end
        @(negedge clk);
        mgmt_rsp_ready = 1;
        force_error_rsp_ready = 1;
        fault_event_ready = 1;
        @(posedge clk);
        #1;
        mgmt_rsp_ready = 0;
        force_error_rsp_ready = 0;
        fault_event_ready = 0;

        // A registered reset-required first fault is an admission fence, not
        // management-channel deadlock.  In particular, generation exhaustion
        // leaves the bank INVALID, so a syntactically legal new-epoch SCRUB
        // must still consume one management credit and return the retained
        // first-fatal code without activating the serializer.  Coordinated
        // reset remains the only recovery that can authorize that scrub.
        scrub_write_count0 = 0;
        scrub_write_count1 = 0;
        scrub_sequence_errors0 = 0;
        scrub_sequence_errors1 = 0;
        scrub_measure_active = 1;
        clear_new_descriptor;
        mgmt_req_expected_directory_generation = 0;
        mgmt_req_expected_content_handle = 0;
        mgmt_req_expected_stage_ticket = 0;
        mgmt_req_expected_physical_bank_generation = 0;
        mgmt_req_new_image_epoch = IMAGE_EPOCH + 1'b1;
        mgmt_req_external_safe = 1;
        send_mgmt(OP_SCRUB, 2'b01, ERR_GENERATION_EXHAUSTED,
                  16'h8403);
        scrub_measure_active = 0;
        check(scrub_write_count0 == 0 && scrub_write_count1 == 0 &&
              scrub_sequence_errors0 == 0 &&
              scrub_sequence_errors1 == 0,
              "registered exhaustion rejects SCRUB without RAM writes");
        check(!directory_scrub_busy[0] &&
              directory_state[2:0] == ST_INVALID &&
              directory_generation[15:0] == 16'hffff,
              "rejected post-exhaustion SCRUB cannot activate or mutate state");
        check(directory_last_scrubbed_image_epoch_valid[0] &&
              directory_last_scrubbed_image_epoch[31:0] == IMAGE_EPOCH,
              "rejected post-exhaustion SCRUB preserves prior scrub epoch");
        check(reset_required[0] && local_error_valid[0] &&
              local_error_code[7:0] == ERR_GENERATION_EXHAUSTED &&
              local_error_source[2:0] == 3'd0 &&
              local_error_detail[31:0] == 32'h0000_ffff &&
              local_error_directory_generation[15:0] == 16'hffff &&
              local_error_stage_ticket[31:0] == 0 &&
              local_error_content_handle[31:0] == 0 &&
              local_error_physical_bank_generation[31:0] == 0,
              "rejected post-exhaustion SCRUB preserves first-fatal scope");

        $display("MEASURE parameter_source_directory scrub_write_cycles=%0d",
                 measured_scrub_cycles);
        $display("MEASURE parameter_source_directory scrub_accept_to_response_cycles=%0d",
                 measured_scrub_accept_to_response_cycles);
        $display("MEASURE parameter_source_directory compute_accept_to_bank_issue_cycles=%0d",
                 measured_compute_bank_issue_cycles);
        $display("MEASURE parameter_source_directory compute_accept_to_response_valid_cycles=%0d",
                 measured_compute_response_valid_cycles);
        $display("MEASURE parameter_source_directory compute_accept_to_terminal_handshake_cycles=%0d",
                 measured_compute_terminal_cycles);
        $display("MEASURE parameter_source_directory no_stall_window_cycles=%0d no_stall_accepts=%0d accepted_ii=1",
                 measured_ii_window_cycles, measured_ii_accepts);
        $display("MEASURE parameter_source_directory bank0_no_stall_window_cycles=%0d bank0_no_stall_accepts=%0d accepted_ii=1",
                 measured_bank0_ii_window_cycles,
                 measured_bank0_ii_accepts);
        $display("MEASURE parameter_source_directory bank1_no_stall_window_cycles=%0d bank1_no_stall_accepts=%0d accepted_ii=1",
                 measured_bank1_ii_window_cycles,
                 measured_bank1_ii_accepts);

        if (failures == 0)
            $display("PASS tb_parameter_source_directory: %0d checks", checks);
        else
            $display("FAIL tb_parameter_source_directory: %0d failures / %0d checks",
                     failures, checks);
        if (failures != 0)
            $display("Focused directory testbench completed with failures");
        $finish;
    end

    initial begin
        #20000000;
        $display("FAIL: global simulation timeout");
        $display("TIMEOUT_DEBUG phase=%0d mgmt_exec=%b exec_tag=%h decision=%b collision=%b mgmt_active=%b mgmt_rsp=%b fault_stage=%b%b local_error=%b fault_event=%b event_bank=%b bank_rsp_valid=%b%b bank_expect=%0d/%0d close=%b force_rsp=%b state=%o",
                 directed_phase, dut.mgmt_exec_valid_q,
                 dut.mgmt_exec_tag_q, dut.mgmt_decision_valid_q,
                 dut.mgmt_exec_fault_collision_q, dut.mgmt_active_q,
                 mgmt_rsp_valid, dut.fault_stage_valid_w[1],
                 dut.fault_stage_valid_w[0], local_error_valid,
                 fault_event_valid, fault_event_bank_mask,
                 bank1_rd_rsp_valid, bank0_rd_rsp_valid,
                 dut.bank0_expect_count_q, dut.bank1_expect_count_q,
                 final_close_pending, force_error_rsp_valid,
                 directory_state);
        $finish;
    end
endmodule
