`timescale 1ns/1ps

// Focused, self-checking Phase-B verification for the single matrix-0 raw
// accumulator scratch.  This file intentionally uses Verilog-2001 syntax.
module tb_matrix0_raw_accumulator_scratch;
    localparam [2:0] ST_EMPTY    = 3'd0;
    localparam [2:0] ST_FILLING  = 3'd1;
    localparam [2:0] ST_COMPLETE = 3'd2;
    localparam [2:0] ST_VALID    = 3'd3;
    localparam [2:0] ST_IN_USE   = 3'd4;
    localparam [2:0] ST_ERROR    = 3'd5;

    localparam [2:0] OP_ALLOCATE       = 3'd0;
    localparam [2:0] OP_PUBLISH_VALID  = 3'd1;
    localparam [2:0] OP_RELEASE_OBJECT = 3'd2;
    localparam [2:0] OP_CLEAR_ERROR    = 3'd3;

    localparam [7:0] STATUS_OK                  = 8'h00;
    localparam [7:0] ERR_BAD_OPCODE             = 8'h01;
    localparam [7:0] ERR_WRONG_STATE            = 8'h02;
    localparam [7:0] ERR_STALE_GENERATION       = 8'h03;
    localparam [7:0] ERR_OWNER_MISMATCH         = 8'h04;
    localparam [7:0] ERR_EXTERNAL_UNSAFE        = 8'h06;
    localparam [7:0] ERR_GENERATION_EXHAUSTED   = 8'h07;
    localparam [7:0] ERR_ABORTED                = 8'h09;
    localparam [7:0] ERR_INTERNAL_STATE         = 8'h0b;
    localparam [7:0] ERR_STAGE_TICKET_MISMATCH  = 8'h20;
    localparam [7:0] ERR_CONTEXT_MISMATCH       = 8'h21;
    localparam [7:0] ERR_BINDING_MISMATCH       = 8'h22;
    localparam [7:0] ERR_IMAGE_EPOCH_MISMATCH   = 8'h23;
    localparam [7:0] ERR_BRANCH_MISMATCH        = 8'h24;
    localparam [7:0] ERR_BAD_TILE               = 8'h25;
    localparam [7:0] ERR_BAD_LANE_MASK          = 8'h26;
    localparam [7:0] ERR_DUPLICATE_TILE         = 8'h27;
    localparam [7:0] ERR_CAPTURE_ORDER          = 8'h28;
    localparam [7:0] ERR_OVERFLOW               = 8'h29;
    localparam [7:0] ERR_NOT_COMPLETE           = 8'h2a;
    localparam [7:0] ERR_STALE_USE              = 8'h2b;
    localparam [7:0] ERR_DUPLICATE_RELEASE      = 8'h2c;
    localparam [7:0] ERR_CANCELLATION_EPOCH     = 8'h2d;
    localparam [7:0] ERR_TILE_ALREADY_USED      = 8'h2f;
    localparam [7:0] ERR_BAD_CLOSE_CODE         = 8'h30;
    localparam [2:0] ERR_SRC_INTERNAL            = 3'b100;
    localparam [10:0] INTERNAL_OWNER_STATE_FAULT = 11'h00b;

    localparam [31:0] IMAGE_EPOCH = 32'h1020_3040;
    localparam [3:0]  STAGE_ID    = 4'd1;
    localparam [31:0] TICKET      = 32'h1111_0001;
    localparam [1:0]  BRANCH      = 2'd2;
    localparam [31:0] CONTEXT     = 32'h2222_0002;
    localparam [31:0] BINDING     = 32'h3333_0003;
    localparam        BANK_ID     = 1'b1;
    localparam [31:0] BANK_GEN    = 32'h4444_0004;
    localparam [31:0] CANCEL_EPOCH= 32'h5555_0005;

    reg clk;
    reg rst_n;

    wire [2:0] scratch_state;
    wire [31:0] scratch_generation;
    wire scratch_generation_initialized;
    wire scratch_owner_valid;
    wire [19:0] committed_tile_bitmap;
    wire [8:0] committed_entry_count;
    wire [19:0] replayed_tile_bitmap;
    wire [1:0] capture_outstanding;
    wire capture_busy;
    wire pack_busy;
    wire active_use_valid;
    wire [31:0] active_use_token;
    wire [5:0] active_use_row_tile;
    wire [31:0] active_use_replay_token;
    wire teardown_pending;
    wire fault_pending;
    wire causal_drain_complete;
    wire local_quiescent;
    wire early_retire_evidence_valid;
    wire reset_required;

    reg mgmt_req_valid;
    wire mgmt_req_ready;
    reg [2:0] mgmt_req_opcode;
    reg [31:0] mgmt_req_image_epoch;
    reg [3:0] mgmt_req_stage_id;
    reg [31:0] mgmt_req_stage_ticket;
    reg [1:0] mgmt_req_logical_branch;
    reg [31:0] mgmt_req_context_generation;
    reg [31:0] mgmt_req_matrix0_binding_token;
    reg mgmt_req_source_bank_id;
    reg [31:0] mgmt_req_source_bank_generation;
    reg [31:0] mgmt_req_scratch_generation;
    reg [31:0] mgmt_req_cancellation_epoch;
    reg [5:0] mgmt_req_expected_tile_count;
    reg [15:0] mgmt_req_expected_lane_mask;
    reg mgmt_req_external_safe;
    reg [15:0] mgmt_req_tag;
    wire mgmt_rsp_valid;
    reg mgmt_rsp_ready;
    wire [2:0] mgmt_rsp_opcode;
    wire [31:0] mgmt_rsp_request_generation;
    wire [31:0] mgmt_rsp_result_generation;
    wire [2:0] mgmt_rsp_state;
    wire [15:0] mgmt_rsp_tag;
    wire [7:0] mgmt_rsp_status;

    reg final_close_req_valid;
    wire final_close_req_ready;
    reg final_close_req_kind;
    reg [7:0] final_close_req_code;
    reg final_close_req_data_untrusted;
    reg final_close_req_causal_producers_drained;
    reg [31:0] final_close_req_cancellation_epoch;
    reg [15:0] final_close_req_tag;
    wire final_close_rsp_valid;
    reg final_close_rsp_ready;
    wire [2:0] final_close_rsp_state;
    wire [31:0] final_close_rsp_generation;
    wire [31:0] final_close_rsp_cancellation_epoch;
    wire [15:0] final_close_rsp_tag;
    wire [7:0] final_close_rsp_status;
    wire final_close_rsp_reset_required;

    reg capture_req_valid;
    wire capture_req_ready;
    reg [31:0] capture_req_image_epoch;
    reg [3:0] capture_req_stage_id;
    reg [31:0] capture_req_stage_ticket;
    reg [1:0] capture_req_logical_branch;
    reg [31:0] capture_req_context_generation;
    reg [31:0] capture_req_matrix0_binding_token;
    reg [31:0] capture_req_scratch_generation;
    reg [31:0] capture_req_cancellation_epoch;
    reg [5:0] capture_req_row_tile;
    reg [511:0] capture_req_accumulators;
    reg [15:0] capture_req_lane_valid;
    reg [15:0] capture_req_overflow;
    reg capture_req_pe_snapshot_safe;
    reg [15:0] capture_req_tag;
    wire capture_snapshot_commit;
    wire [5:0] capture_snapshot_row_tile;
    wire [31:0] capture_snapshot_scratch_generation;
    wire [15:0] capture_snapshot_tag;
    wire capture_rsp_valid;
    reg capture_rsp_ready;
    wire [31:0] capture_rsp_scratch_generation;
    wire [5:0] capture_rsp_row_tile;
    wire capture_rsp_snapshot_taken;
    wire [15:0] capture_rsp_committed_lane_mask;
    wire [19:0] capture_rsp_cumulative_tile_bitmap;
    wire [8:0] capture_rsp_cumulative_entry_count;
    wire [15:0] capture_rsp_tag;
    wire [7:0] capture_rsp_status;

    reg tile_req_valid;
    wire tile_req_ready;
    reg [31:0] tile_req_image_epoch;
    reg [3:0] tile_req_stage_id;
    reg [31:0] tile_req_stage_ticket;
    reg [1:0] tile_req_logical_branch;
    reg [31:0] tile_req_context_generation;
    reg [31:0] tile_req_retired_binding_token;
    reg [31:0] tile_req_scratch_generation;
    reg [31:0] tile_req_cancellation_epoch;
    reg [5:0] tile_req_row_tile;
    reg [31:0] tile_req_replay_token;
    reg tile_req_retired_binding_safe;
    reg [15:0] tile_req_tag;
    wire tile_rsp_valid;
    reg tile_rsp_ready;
    wire [511:0] tile_rsp_data;
    wire tile_rsp_complete;
    wire [31:0] tile_rsp_scratch_generation;
    wire [5:0] tile_rsp_row_tile;
    wire [31:0] tile_rsp_replay_token;
    wire [31:0] tile_rsp_use_token;
    wire [15:0] tile_rsp_tag;
    wire [7:0] tile_rsp_status;
    wire use_tile_valid;
    wire [511:0] use_tile_data;
    wire [31:0] use_tile_image_epoch;
    wire [3:0] use_tile_stage_id;
    wire [31:0] use_tile_scratch_generation;
    wire [31:0] use_tile_stage_ticket;
    wire [1:0] use_tile_logical_branch;
    wire [31:0] use_tile_context_generation;
    wire [31:0] use_tile_matrix0_binding_token;
    wire [31:0] use_tile_cancellation_epoch;
    wire [5:0] use_tile_row_tile;
    wire [31:0] use_tile_replay_token;
    wire [31:0] use_tile_token;

    reg use_release_req_valid;
    wire use_release_req_ready;
    reg [31:0] use_release_req_image_epoch;
    reg [3:0] use_release_req_stage_id;
    reg [31:0] use_release_req_scratch_generation;
    reg [31:0] use_release_req_stage_ticket;
    reg [1:0] use_release_req_logical_branch;
    reg [31:0] use_release_req_context_generation;
    reg [31:0] use_release_req_matrix0_binding_token;
    reg [31:0] use_release_req_cancellation_epoch;
    reg [5:0] use_release_req_row_tile;
    reg [31:0] use_release_req_replay_token;
    reg [31:0] use_release_req_use_token;
    reg use_release_req_all_input_handshakes_done;
    reg [15:0] use_release_req_tag;
    wire use_release_rsp_valid;
    reg use_release_rsp_ready;
    wire [5:0] use_release_rsp_row_tile;
    wire [31:0] use_release_rsp_use_token;
    wire [15:0] use_release_rsp_tag;
    wire [7:0] use_release_rsp_status;

    wire local_error_valid;
    wire [7:0] local_error_code;
    wire [2:0] local_error_source;
    wire [31:0] local_error_detail;
    wire [31:0] local_error_image_epoch;
    wire [3:0] local_error_stage_id;
    wire [31:0] local_error_scratch_generation;
    wire [31:0] local_error_stage_ticket;
    wire [1:0] local_error_logical_branch;
    wire [31:0] local_error_context_generation;
    wire [31:0] local_error_matrix0_binding_token;
    wire local_error_source_bank_id;
    wire [31:0] local_error_source_bank_generation;
    wire [31:0] local_error_object_cancellation_epoch;
    wire [31:0] local_error_stop_cancellation_epoch;
    wire [15:0] local_error_offender_tag;
    wire [5:0] local_error_offender_row_tile;
    wire first_overflow_valid;
    wire [5:0] first_overflow_row_tile;
    wire [3:0] first_overflow_lane;
    wire [15:0] first_overflow_mask;

    reg [31:0] expected_mem [0:319];
    reg [511:0] tile_vector;
    reg [511:0] held_vector;
    reg [31:0] held_use_token;
    reg [31:0] saved_generation;
    integer failures;
    integer checks;
    integer row;
    integer lane;
    integer index;
    integer pipeline_phase;
    integer wait_count;
    integer seed;
    integer random_word;

    matrix0_raw_accumulator_scratch dut (
        .clk(clk),
        .rst_n(rst_n),
        .scratch_state(scratch_state),
        .scratch_generation(scratch_generation),
        .scratch_generation_initialized(scratch_generation_initialized),
        .scratch_owner_valid(scratch_owner_valid),
        .committed_tile_bitmap(committed_tile_bitmap),
        .committed_entry_count(committed_entry_count),
        .replayed_tile_bitmap(replayed_tile_bitmap),
        .capture_outstanding(capture_outstanding),
        .capture_busy(capture_busy),
        .pack_busy(pack_busy),
        .active_use_valid(active_use_valid),
        .active_use_token(active_use_token),
        .active_use_row_tile(active_use_row_tile),
        .active_use_replay_token(active_use_replay_token),
        .teardown_pending(teardown_pending),
        .fault_pending(fault_pending),
        .causal_drain_complete(causal_drain_complete),
        .local_quiescent(local_quiescent),
        .early_retire_evidence_valid(early_retire_evidence_valid),
        .reset_required(reset_required),
        .mgmt_req_valid(mgmt_req_valid),
        .mgmt_req_ready(mgmt_req_ready),
        .mgmt_req_opcode(mgmt_req_opcode),
        .mgmt_req_image_epoch(mgmt_req_image_epoch),
        .mgmt_req_stage_id(mgmt_req_stage_id),
        .mgmt_req_stage_ticket(mgmt_req_stage_ticket),
        .mgmt_req_logical_branch(mgmt_req_logical_branch),
        .mgmt_req_context_generation(mgmt_req_context_generation),
        .mgmt_req_matrix0_binding_token(mgmt_req_matrix0_binding_token),
        .mgmt_req_source_bank_id(mgmt_req_source_bank_id),
        .mgmt_req_source_bank_generation(mgmt_req_source_bank_generation),
        .mgmt_req_scratch_generation(mgmt_req_scratch_generation),
        .mgmt_req_cancellation_epoch(mgmt_req_cancellation_epoch),
        .mgmt_req_expected_tile_count(mgmt_req_expected_tile_count),
        .mgmt_req_expected_lane_mask(mgmt_req_expected_lane_mask),
        .mgmt_req_external_safe(mgmt_req_external_safe),
        .mgmt_req_tag(mgmt_req_tag),
        .mgmt_rsp_valid(mgmt_rsp_valid),
        .mgmt_rsp_ready(mgmt_rsp_ready),
        .mgmt_rsp_opcode(mgmt_rsp_opcode),
        .mgmt_rsp_request_generation(mgmt_rsp_request_generation),
        .mgmt_rsp_result_generation(mgmt_rsp_result_generation),
        .mgmt_rsp_state(mgmt_rsp_state),
        .mgmt_rsp_tag(mgmt_rsp_tag),
        .mgmt_rsp_status(mgmt_rsp_status),
        .final_close_req_valid(final_close_req_valid),
        .final_close_req_ready(final_close_req_ready),
        .final_close_req_kind(final_close_req_kind),
        .final_close_req_code(final_close_req_code),
        .final_close_req_data_untrusted(final_close_req_data_untrusted),
        .final_close_req_causal_producers_drained(final_close_req_causal_producers_drained),
        .final_close_req_cancellation_epoch(final_close_req_cancellation_epoch),
        .final_close_req_tag(final_close_req_tag),
        .final_close_rsp_valid(final_close_rsp_valid),
        .final_close_rsp_ready(final_close_rsp_ready),
        .final_close_rsp_state(final_close_rsp_state),
        .final_close_rsp_generation(final_close_rsp_generation),
        .final_close_rsp_cancellation_epoch(final_close_rsp_cancellation_epoch),
        .final_close_rsp_tag(final_close_rsp_tag),
        .final_close_rsp_status(final_close_rsp_status),
        .final_close_rsp_reset_required(final_close_rsp_reset_required),
        .capture_req_valid(capture_req_valid),
        .capture_req_ready(capture_req_ready),
        .capture_req_image_epoch(capture_req_image_epoch),
        .capture_req_stage_id(capture_req_stage_id),
        .capture_req_stage_ticket(capture_req_stage_ticket),
        .capture_req_logical_branch(capture_req_logical_branch),
        .capture_req_context_generation(capture_req_context_generation),
        .capture_req_matrix0_binding_token(capture_req_matrix0_binding_token),
        .capture_req_scratch_generation(capture_req_scratch_generation),
        .capture_req_cancellation_epoch(capture_req_cancellation_epoch),
        .capture_req_row_tile(capture_req_row_tile),
        .capture_req_accumulators(capture_req_accumulators),
        .capture_req_lane_valid(capture_req_lane_valid),
        .capture_req_overflow(capture_req_overflow),
        .capture_req_pe_snapshot_safe(capture_req_pe_snapshot_safe),
        .capture_req_tag(capture_req_tag),
        .capture_snapshot_commit(capture_snapshot_commit),
        .capture_snapshot_row_tile(capture_snapshot_row_tile),
        .capture_snapshot_scratch_generation(capture_snapshot_scratch_generation),
        .capture_snapshot_tag(capture_snapshot_tag),
        .capture_rsp_valid(capture_rsp_valid),
        .capture_rsp_ready(capture_rsp_ready),
        .capture_rsp_scratch_generation(capture_rsp_scratch_generation),
        .capture_rsp_row_tile(capture_rsp_row_tile),
        .capture_rsp_snapshot_taken(capture_rsp_snapshot_taken),
        .capture_rsp_committed_lane_mask(capture_rsp_committed_lane_mask),
        .capture_rsp_cumulative_tile_bitmap(capture_rsp_cumulative_tile_bitmap),
        .capture_rsp_cumulative_entry_count(capture_rsp_cumulative_entry_count),
        .capture_rsp_tag(capture_rsp_tag),
        .capture_rsp_status(capture_rsp_status),
        .tile_req_valid(tile_req_valid),
        .tile_req_ready(tile_req_ready),
        .tile_req_image_epoch(tile_req_image_epoch),
        .tile_req_stage_id(tile_req_stage_id),
        .tile_req_stage_ticket(tile_req_stage_ticket),
        .tile_req_logical_branch(tile_req_logical_branch),
        .tile_req_context_generation(tile_req_context_generation),
        .tile_req_retired_binding_token(tile_req_retired_binding_token),
        .tile_req_scratch_generation(tile_req_scratch_generation),
        .tile_req_cancellation_epoch(tile_req_cancellation_epoch),
        .tile_req_row_tile(tile_req_row_tile),
        .tile_req_replay_token(tile_req_replay_token),
        .tile_req_retired_binding_safe(tile_req_retired_binding_safe),
        .tile_req_tag(tile_req_tag),
        .tile_rsp_valid(tile_rsp_valid),
        .tile_rsp_ready(tile_rsp_ready),
        .tile_rsp_data(tile_rsp_data),
        .tile_rsp_complete(tile_rsp_complete),
        .tile_rsp_scratch_generation(tile_rsp_scratch_generation),
        .tile_rsp_row_tile(tile_rsp_row_tile),
        .tile_rsp_replay_token(tile_rsp_replay_token),
        .tile_rsp_use_token(tile_rsp_use_token),
        .tile_rsp_tag(tile_rsp_tag),
        .tile_rsp_status(tile_rsp_status),
        .use_tile_valid(use_tile_valid),
        .use_tile_data(use_tile_data),
        .use_tile_image_epoch(use_tile_image_epoch),
        .use_tile_stage_id(use_tile_stage_id),
        .use_tile_scratch_generation(use_tile_scratch_generation),
        .use_tile_stage_ticket(use_tile_stage_ticket),
        .use_tile_logical_branch(use_tile_logical_branch),
        .use_tile_context_generation(use_tile_context_generation),
        .use_tile_matrix0_binding_token(use_tile_matrix0_binding_token),
        .use_tile_cancellation_epoch(use_tile_cancellation_epoch),
        .use_tile_row_tile(use_tile_row_tile),
        .use_tile_replay_token(use_tile_replay_token),
        .use_tile_token(use_tile_token),
        .use_release_req_valid(use_release_req_valid),
        .use_release_req_ready(use_release_req_ready),
        .use_release_req_image_epoch(use_release_req_image_epoch),
        .use_release_req_stage_id(use_release_req_stage_id),
        .use_release_req_scratch_generation(use_release_req_scratch_generation),
        .use_release_req_stage_ticket(use_release_req_stage_ticket),
        .use_release_req_logical_branch(use_release_req_logical_branch),
        .use_release_req_context_generation(use_release_req_context_generation),
        .use_release_req_matrix0_binding_token(use_release_req_matrix0_binding_token),
        .use_release_req_cancellation_epoch(use_release_req_cancellation_epoch),
        .use_release_req_row_tile(use_release_req_row_tile),
        .use_release_req_replay_token(use_release_req_replay_token),
        .use_release_req_use_token(use_release_req_use_token),
        .use_release_req_all_input_handshakes_done(use_release_req_all_input_handshakes_done),
        .use_release_req_tag(use_release_req_tag),
        .use_release_rsp_valid(use_release_rsp_valid),
        .use_release_rsp_ready(use_release_rsp_ready),
        .use_release_rsp_row_tile(use_release_rsp_row_tile),
        .use_release_rsp_use_token(use_release_rsp_use_token),
        .use_release_rsp_tag(use_release_rsp_tag),
        .use_release_rsp_status(use_release_rsp_status),
        .local_error_valid(local_error_valid),
        .local_error_code(local_error_code),
        .local_error_source(local_error_source),
        .local_error_detail(local_error_detail),
        .local_error_image_epoch(local_error_image_epoch),
        .local_error_stage_id(local_error_stage_id),
        .local_error_scratch_generation(local_error_scratch_generation),
        .local_error_stage_ticket(local_error_stage_ticket),
        .local_error_logical_branch(local_error_logical_branch),
        .local_error_context_generation(local_error_context_generation),
        .local_error_matrix0_binding_token(local_error_matrix0_binding_token),
        .local_error_source_bank_id(local_error_source_bank_id),
        .local_error_source_bank_generation(local_error_source_bank_generation),
        .local_error_object_cancellation_epoch(local_error_object_cancellation_epoch),
        .local_error_stop_cancellation_epoch(local_error_stop_cancellation_epoch),
        .local_error_offender_tag(local_error_offender_tag),
        .local_error_offender_row_tile(local_error_offender_row_tile),
        .first_overflow_valid(first_overflow_valid),
        .first_overflow_row_tile(first_overflow_row_tile),
        .first_overflow_lane(first_overflow_lane),
        .first_overflow_mask(first_overflow_mask)
    );

    always #5 clk = ~clk;

    task fail;
        input [8*220-1:0] message;
        begin
            failures = failures + 1;
            $display("FAIL: %0s at time %0t", message, $time);
        end
    endtask

    task check;
        input condition;
        input [8*220-1:0] message;
        begin
            checks = checks + 1;
            if (condition !== 1'b1)
                fail(message);
        end
    endtask

    task wait_for_state;
        input [2:0] expected_state;
        input [8*100-1:0] name;
        begin
            wait_count = 0;
            while ((scratch_state !== expected_state) && wait_count < 1000) begin
                @(posedge clk); #1;
                wait_count = wait_count + 1;
            end
            check(scratch_state === expected_state, name);
        end
    endtask

    task set_mgmt_identity;
        begin
            mgmt_req_image_epoch = IMAGE_EPOCH;
            mgmt_req_stage_id = STAGE_ID;
            mgmt_req_stage_ticket = TICKET;
            mgmt_req_logical_branch = BRANCH;
            mgmt_req_context_generation = CONTEXT;
            mgmt_req_matrix0_binding_token = BINDING;
            mgmt_req_source_bank_id = BANK_ID;
            mgmt_req_source_bank_generation = BANK_GEN;
            mgmt_req_scratch_generation = scratch_generation;
            mgmt_req_cancellation_epoch = CANCEL_EPOCH;
            mgmt_req_expected_tile_count = 6'd20;
            mgmt_req_expected_lane_mask = 16'hffff;
            mgmt_req_external_safe = 1'b1;
        end
    endtask

    task set_capture_identity;
        begin
            capture_req_image_epoch = IMAGE_EPOCH;
            capture_req_stage_id = STAGE_ID;
            capture_req_stage_ticket = TICKET;
            capture_req_logical_branch = BRANCH;
            capture_req_context_generation = CONTEXT;
            capture_req_matrix0_binding_token = BINDING;
            capture_req_scratch_generation = scratch_generation;
            capture_req_cancellation_epoch = CANCEL_EPOCH;
        end
    endtask

    task set_tile_identity;
        begin
            tile_req_image_epoch = IMAGE_EPOCH;
            tile_req_stage_id = STAGE_ID;
            tile_req_stage_ticket = TICKET;
            tile_req_logical_branch = BRANCH;
            tile_req_context_generation = CONTEXT;
            tile_req_retired_binding_token = BINDING;
            tile_req_scratch_generation = scratch_generation;
            tile_req_cancellation_epoch = CANCEL_EPOCH;
            tile_req_retired_binding_safe = 1'b1;
        end
    endtask

    task set_release_identity;
        begin
            use_release_req_image_epoch = IMAGE_EPOCH;
            use_release_req_stage_id = STAGE_ID;
            use_release_req_scratch_generation = scratch_generation;
            use_release_req_stage_ticket = TICKET;
            use_release_req_logical_branch = BRANCH;
            use_release_req_context_generation = CONTEXT;
            use_release_req_matrix0_binding_token = BINDING;
            use_release_req_cancellation_epoch = CANCEL_EPOCH;
        end
    endtask

    task reset_dut;
        begin
            @(negedge clk);
            rst_n = 1'b0;
            repeat (3) @(posedge clk);
            #1;
            check(scratch_state == ST_EMPTY, "reset state is EMPTY");
            check(scratch_generation == 0, "reset generation is zero");
            check(!scratch_owner_valid, "reset clears owner");
            check(!capture_busy && !pack_busy && !active_use_valid, "reset clears pipelines/use");
            @(negedge clk);
            rst_n = 1'b1;
        end
    endtask

    task consume_mgmt_response;
        input [7:0] expected_status;
        input [2:0] expected_state;
        begin
            wait_count = 0;
            while (!mgmt_rsp_valid && wait_count < 1000) begin
                @(posedge clk); #1;
                wait_count = wait_count + 1;
            end
            check(mgmt_rsp_valid, "management response arrived");
            check(mgmt_rsp_status == expected_status, "management response status");
            check(mgmt_rsp_state == expected_state, "management response post-state");
            @(negedge clk); mgmt_rsp_ready = 1'b1;
            @(posedge clk); #1;
            @(negedge clk); mgmt_rsp_ready = 1'b0;
        end
    endtask

    task send_mgmt;
        input [2:0] opcode;
        input [7:0] expected_status;
        input [2:0] expected_state;
        begin
            @(negedge clk);
            set_mgmt_identity;
            mgmt_req_opcode = opcode;
            mgmt_req_tag = mgmt_req_tag + 1'b1;
            mgmt_req_valid = 1'b1;
            #1;
            wait_count = 0;
            while (!mgmt_req_ready && wait_count < 1000) begin
                @(negedge clk);
                wait_count = wait_count + 1;
            end
            check(mgmt_req_ready, "management request became ready");
            @(posedge clk); #1; mgmt_req_valid = 1'b0;
            consume_mgmt_response(expected_status, expected_state);
        end
    endtask

    task allocate_object;
        begin
            send_mgmt(OP_ALLOCATE, STATUS_OK, ST_FILLING);
            check(scratch_generation_initialized, "allocation initializes generation");
            check(scratch_generation == 1, "first allocation selects generation one");
            check(scratch_owner_valid, "allocation installs owner");
        end
    endtask

    task send_publish_bad_binding;
        begin
            @(negedge clk);
            set_mgmt_identity;
            mgmt_req_opcode = OP_PUBLISH_VALID;
            mgmt_req_matrix0_binding_token = BINDING ^ 32'h0000_0001;
            mgmt_req_tag = mgmt_req_tag + 1'b1;
            mgmt_req_valid = 1'b1;
            #1;
            wait_count = 0;
            while (!mgmt_req_ready && wait_count < 1000) begin
                @(negedge clk);
                wait_count = wait_count + 1;
            end
            check(mgmt_req_ready, "bad-binding publish request became ready");
            @(posedge clk); #1; mgmt_req_valid = 1'b0;
            consume_mgmt_response(ERR_BINDING_MISMATCH, ST_COMPLETE);
            check(scratch_state == ST_COMPLETE,
                  "publish identity mismatch preserves COMPLETE");
        end
    endtask

    task make_tile_vector;
        input integer requested_row;
        begin
            for (lane = 0; lane < 16; lane = lane + 1)
                tile_vector[lane*32 +: 32] = expected_mem[requested_row*16 + lane];
        end
    endtask

    task fire_capture_only;
        input integer requested_row;
        input [15:0] request_tag;
        begin
            make_tile_vector(requested_row);
            @(negedge clk);
            set_capture_identity;
            capture_req_row_tile = requested_row[5:0];
            capture_req_accumulators = tile_vector;
            capture_req_lane_valid = 16'hffff;
            capture_req_overflow = 16'h0000;
            capture_req_pe_snapshot_safe = 1'b1;
            capture_req_tag = request_tag;
            capture_req_valid = 1'b1;
            #1;
            wait_count = 0;
            while (!capture_req_ready && wait_count < 1000) begin
                @(negedge clk);
                wait_count = wait_count + 1;
            end
            check(capture_req_ready, "capture-only request became ready");
            check(capture_snapshot_commit, "capture-only immutable snapshot event");
            @(posedge clk); #1;
            capture_req_valid = 1'b0;
            capture_req_accumulators = {16{32'hbad0_bad0}};
        end
    endtask

    task fire_tile_read_only;
        input integer requested_row;
        input [31:0] replay_token;
        input [15:0] request_tag;
        begin
            @(negedge clk);
            set_tile_identity;
            tile_req_row_tile = requested_row[5:0];
            tile_req_replay_token = replay_token;
            tile_req_tag = request_tag;
            tile_req_valid = 1'b1;
            #1;
            wait_count = 0;
            while (!tile_req_ready && wait_count < 1000) begin
                @(negedge clk);
                wait_count = wait_count + 1;
            end
            check(tile_req_ready, "tile-read-only request became ready");
            @(posedge clk); #1;
            tile_req_valid = 1'b0;
        end
    endtask

    task issue_capture;
        input integer requested_row;
        input [15:0] lane_mask;
        input [15:0] overflow_mask;
        input snapshot_safe;
        input [7:0] expected_status;
        input expect_snapshot;
        input hold_response;
        begin
            make_tile_vector(requested_row < 20 ? requested_row : 0);
            @(negedge clk);
            set_capture_identity;
            capture_req_row_tile = requested_row[5:0];
            capture_req_accumulators = tile_vector;
            capture_req_lane_valid = lane_mask;
            capture_req_overflow = overflow_mask;
            capture_req_pe_snapshot_safe = snapshot_safe;
            capture_req_tag = capture_req_tag + 1'b1;
            capture_req_valid = 1'b1;
            #1;
            wait_count = 0;
            while (!capture_req_ready && wait_count < 1000) begin
                @(negedge clk);
                wait_count = wait_count + 1;
            end
            check(capture_req_ready, "capture request became ready");
            #1;
            check(capture_snapshot_commit === expect_snapshot, "snapshot event is success-qualified");
            if (expect_snapshot) begin
                check(capture_snapshot_row_tile == requested_row[5:0], "snapshot row identity");
                check(capture_snapshot_scratch_generation == scratch_generation, "snapshot generation identity");
                check(capture_snapshot_tag == capture_req_tag, "snapshot tag identity");
            end
            @(posedge clk); #1;
            capture_req_valid = 1'b0;
            // Prove the source bus may be destroyed immediately after commit.
            capture_req_accumulators = {16{32'hdeadc0de}};

            if (expect_snapshot) begin
                for (index = 1; index < 16; index = index + 1) begin
                    @(posedge clk); #1;
                    check(!capture_rsp_valid, "capture response not materialized before lane 15");
                    check(capture_busy, "capture register held during serialization");
                end
                @(posedge clk); #1;
            end else begin
                wait_count = 0;
                while (!capture_rsp_valid && wait_count < 20) begin
                    @(posedge clk); #1;
                    wait_count = wait_count + 1;
                end
            end
            check(capture_rsp_valid, "capture terminal response arrived");
            check(capture_rsp_status == expected_status, "capture terminal status");
            check(capture_rsp_row_tile == requested_row[5:0], "capture response row");
            check(capture_rsp_snapshot_taken === expect_snapshot, "capture response snapshot flag");
            if (expect_snapshot) begin
                check(capture_rsp_committed_lane_mask == 16'hffff, "all capture lanes committed");
                check(capture_rsp_cumulative_entry_count == (requested_row + 1) * 16,
                      "cumulative committed entry count");
            end else begin
                check(capture_rsp_committed_lane_mask == 0, "rejected capture commits no lanes");
            end

            if (hold_response) begin
                held_vector = {capture_rsp_cumulative_tile_bitmap,
                               capture_rsp_cumulative_entry_count,
                               capture_rsp_committed_lane_mask,
                               capture_rsp_row_tile,
                               capture_rsp_tag,
                               capture_rsp_status,
                               437'b0};
                repeat (7) begin
                    @(posedge clk); #1;
                    check(capture_rsp_valid, "capture response remains held");
                    check({capture_rsp_cumulative_tile_bitmap,
                           capture_rsp_cumulative_entry_count,
                           capture_rsp_committed_lane_mask,
                           capture_rsp_row_tile,
                           capture_rsp_tag,
                           capture_rsp_status,
                           437'b0} == held_vector, "held capture response is stable");
                end
            end
            @(negedge clk); capture_rsp_ready = 1'b1;
            @(posedge clk); #1;
            @(negedge clk); capture_rsp_ready = 1'b0;
        end
    endtask

    task fill_and_publish;
        input test_bad_publish;
        begin
            for (row = 0; row < 20; row = row + 1)
                issue_capture(row, 16'hffff, 16'h0000, 1'b1,
                              STATUS_OK, 1'b1, row == 0);
            check(scratch_state == ST_COMPLETE, "last actual write forms COMPLETE");
            check(committed_tile_bitmap == 20'hfffff, "all twenty tile bits committed");
            check(committed_entry_count == 9'd320, "all 320 entries committed");
            check(!early_retire_evidence_valid, "COMPLETE is not early-retire evidence");
            if (test_bad_publish)
                send_publish_bad_binding;
            send_mgmt(OP_PUBLISH_VALID, STATUS_OK, ST_VALID);
            check(scratch_state == ST_VALID, "explicit publish forms VALID");
            check(early_retire_evidence_valid, "clean published object supplies retire evidence");
        end
    endtask

    task issue_tile_read;
        input integer requested_row;
        input [31:0] replay_token;
        input [7:0] expected_status;
        input expect_success;
        input hold_response;
        begin
            @(negedge clk);
            set_tile_identity;
            tile_req_row_tile = requested_row[5:0];
            tile_req_replay_token = replay_token;
            tile_req_tag = tile_req_tag + 1'b1;
            tile_req_valid = 1'b1;
            #1;
            wait_count = 0;
            while (!tile_req_ready && wait_count < 1000) begin
                @(negedge clk);
                wait_count = wait_count + 1;
            end
            check(tile_req_ready, "tile request became ready");
            @(posedge clk); #1; tile_req_valid = 1'b0;
            if (expect_success) begin
                check(scratch_state == ST_IN_USE, "legal read acquires IN_USE");
                for (index = 1; index < 16; index = index + 1) begin
                    @(posedge clk); #1;
                    check(!tile_rsp_valid, "packed response withheld before all sixteen reads");
                end
                @(posedge clk); #1;
            end else begin
                wait_count = 0;
                while (!tile_rsp_valid && wait_count < 20) begin
                    @(posedge clk); #1;
                    wait_count = wait_count + 1;
                end
            end
            check(tile_rsp_valid, "tile terminal response arrived");
            check(tile_rsp_status == expected_status, "tile terminal status");
            check(tile_rsp_row_tile == requested_row[5:0], "tile response row");
            check(tile_rsp_replay_token == replay_token, "tile response replay token");
            if (expect_success) begin
                make_tile_vector(requested_row);
                check(tile_rsp_complete, "successful response is complete");
                check(tile_rsp_data == tile_vector, "packed tile preserves lane order and bits");
                check(tile_rsp_use_token != 0, "successful read allocates nonzero use token");
            end else begin
                check(!tile_rsp_complete, "error response is not complete");
                check(tile_rsp_data == 0, "error response exposes zero data");
            end
            if (hold_response) begin
                held_vector = tile_rsp_data;
                held_use_token = tile_rsp_use_token;
                repeat (9) begin
                    @(posedge clk); #1;
                    check(tile_rsp_valid, "tile response remains held");
                    check(tile_rsp_data == held_vector, "held tile data remains stable");
                    check(tile_rsp_use_token == held_use_token, "held use token remains stable");
                    check(!use_tile_valid, "response stall does not start Gate use");
                end
            end
            held_use_token = tile_rsp_use_token;
            held_vector = tile_rsp_data;
            @(negedge clk); tile_rsp_ready = 1'b1;
            @(posedge clk); #1;
            @(negedge clk); tile_rsp_ready = 1'b0;
            if (expect_success) begin
                check(use_tile_valid, "response handshake starts held replay use");
                check(use_tile_data == held_vector, "use view aliases packed tile");
                check(use_tile_token == held_use_token, "use view has response token");
                check(use_tile_row_tile == requested_row[5:0], "use view has row");
                check(use_tile_replay_token == replay_token, "use view has replay token");
            end else begin
                check(!use_tile_valid, "error response creates no use");
            end
        end
    endtask

    task issue_use_release;
        input integer requested_row;
        input [31:0] replay_token;
        input [31:0] use_token;
        input all_done;
        input [7:0] expected_status;
        begin
            @(negedge clk);
            set_release_identity;
            use_release_req_row_tile = requested_row[5:0];
            use_release_req_replay_token = replay_token;
            use_release_req_use_token = use_token;
            use_release_req_all_input_handshakes_done = all_done;
            use_release_req_tag = use_release_req_tag + 1'b1;
            use_release_req_valid = 1'b1;
            // During teardown/final-close, ready is combinationally qualified
            // by the exact payload.  Let that path settle before deciding to
            // wait, or the task can miss the one-cycle ready/fire pulse.
            #1;
            wait_count = 0;
            while (!use_release_req_ready && wait_count < 1000) begin
                @(negedge clk);
                wait_count = wait_count + 1;
            end
            if (!use_release_req_ready) begin
                $display("RELEASE_READY_DIAG state=%0d fault=%0b teardown=%0b use=%0b req/use_gen=%h/%h row=%0d/%0d replay=%h/%h token=%h/%h img=%h/%h stage=%h/%h ticket=%h/%h branch=%h/%h context=%h/%h binding=%h/%h cancel=%h/%h all_done=%0b",
                         scratch_state, fault_pending, teardown_pending,
                         use_tile_valid,
                         use_release_req_scratch_generation,
                         use_tile_scratch_generation,
                         use_release_req_row_tile, use_tile_row_tile,
                         use_release_req_replay_token, use_tile_replay_token,
                         use_release_req_use_token, use_tile_token,
                         use_release_req_image_epoch, use_tile_image_epoch,
                         use_release_req_stage_id, use_tile_stage_id,
                         use_release_req_stage_ticket, use_tile_stage_ticket,
                         use_release_req_logical_branch,
                         use_tile_logical_branch,
                         use_release_req_context_generation,
                         use_tile_context_generation,
                         use_release_req_matrix0_binding_token,
                         use_tile_matrix0_binding_token,
                         use_release_req_cancellation_epoch,
                         use_tile_cancellation_epoch,
                         use_release_req_all_input_handshakes_done);
            end
            check(use_release_req_ready, "use-release request became ready");
            @(posedge clk); #1; use_release_req_valid = 1'b0;
            wait_count = 0;
            while (!use_release_rsp_valid && wait_count < 20) begin
                @(posedge clk); #1;
                wait_count = wait_count + 1;
            end
            check(use_release_rsp_valid, "use-release response arrived");
            check(use_release_rsp_status == expected_status, "use-release terminal status");
            check(use_release_rsp_row_tile == requested_row[5:0], "use-release row echo");
            check(use_release_rsp_use_token == use_token, "use-release token echo");
            repeat (3) begin
                @(posedge clk); #1;
                check(use_release_rsp_valid, "use-release response remains held");
                check(use_release_rsp_status == expected_status, "held release response is stable");
            end
            @(negedge clk); use_release_rsp_ready = 1'b1;
            @(posedge clk); #1;
            @(negedge clk); use_release_rsp_ready = 1'b0;
        end
    endtask

    task send_final_close_no_wait;
        input close_kind;
        input [7:0] close_code;
        input data_untrusted;
        begin
            @(negedge clk);
            final_close_req_kind = close_kind;
            final_close_req_code = close_code;
            final_close_req_data_untrusted = data_untrusted;
            final_close_req_causal_producers_drained = !data_untrusted;
            final_close_req_cancellation_epoch = 32'hface_0001;
            final_close_req_tag = final_close_req_tag + 1'b1;
            final_close_req_valid = 1'b1;
            #1;
            wait_count = 0;
            while (!final_close_req_ready && wait_count < 1000) begin
                @(negedge clk);
                wait_count = wait_count + 1;
            end
            check(final_close_req_ready, "final-close request became ready");
            @(posedge clk); #1; final_close_req_valid = 1'b0;
            check(fault_pending || final_close_rsp_valid,
                  "accepted final close installs pending fault or response");
        end
    endtask

    task consume_final_close;
        input [7:0] expected_status;
        begin
            wait_count = 0;
            while (!final_close_rsp_valid && wait_count < 2000) begin
                @(posedge clk); #1;
                wait_count = wait_count + 1;
            end
            check(final_close_rsp_valid, "final-close response arrived after causal drain");
            check(final_close_rsp_status == expected_status, "final-close response status");
            check(final_close_rsp_state == ST_ERROR, "live final-close ends in ERROR");
            @(negedge clk); final_close_rsp_ready = 1'b1;
            @(posedge clk); #1;
            @(negedge clk); final_close_rsp_ready = 1'b0;
        end
    endtask

    task initialize_inputs;
        begin
            rst_n = 1'b0;
            mgmt_req_valid = 0;
            mgmt_rsp_ready = 0;
            mgmt_req_opcode = 0;
            mgmt_req_tag = 0;
            set_mgmt_identity;
            final_close_req_valid = 0;
            final_close_req_kind = 0;
            final_close_req_code = ERR_ABORTED;
            final_close_req_data_untrusted = 0;
            final_close_req_causal_producers_drained = 1;
            final_close_req_cancellation_epoch = 0;
            final_close_req_tag = 0;
            final_close_rsp_ready = 0;
            capture_req_valid = 0;
            capture_rsp_ready = 0;
            capture_req_row_tile = 0;
            capture_req_accumulators = 0;
            capture_req_lane_valid = 16'hffff;
            capture_req_overflow = 0;
            capture_req_pe_snapshot_safe = 1;
            capture_req_tag = 0;
            set_capture_identity;
            tile_req_valid = 0;
            tile_rsp_ready = 0;
            tile_req_row_tile = 0;
            tile_req_replay_token = 1;
            tile_req_tag = 0;
            set_tile_identity;
            use_release_req_valid = 0;
            use_release_rsp_ready = 0;
            use_release_req_row_tile = 0;
            use_release_req_replay_token = 0;
            use_release_req_use_token = 0;
            use_release_req_all_input_handshakes_done = 1;
            use_release_req_tag = 0;
            set_release_identity;
        end
    endtask

    initial begin
        clk = 0;
        failures = 0;
        checks = 0;
        seed = 32'h3200_0010;
        initialize_inputs;

        // Use reproducible random bit patterns, with signed extremes at the
        // first four addresses.  Storage is checked bit-transparently.
        for (index = 0; index < 320; index = index + 1) begin
            random_word = $random(seed);
            expected_mem[index] = random_word[31:0];
        end
        expected_mem[0] = 32'h8000_0000;
        expected_mem[1] = 32'h7fff_ffff;
        expected_mem[2] = 32'h0000_0000;
        expected_mem[3] = 32'hffff_ffff;

        repeat (3) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;

        // Two physical capture transaction positions: a visible held response
        // plus a second serializer/committed-terminal slot.  Ordering is FIFO
        // and no hidden third credit exists.
        $display("PHASE: two capture credits");
        allocate_object;
        fire_capture_only(0, 16'ha100);
        repeat (16) begin @(posedge clk); #1; end
        check(capture_rsp_valid && capture_rsp_row_tile == 0,
              "first capture response is visibly held");
        check(capture_outstanding == 1, "one held response owns one credit");
        fire_capture_only(1, 16'ha101);
        repeat (16) begin @(posedge clk); #1; end
        check(capture_rsp_valid && capture_rsp_row_tile == 0,
              "held first response is not overwritten by second");
        check(capture_busy && capture_outstanding == 2,
              "second terminal remains in capture_exec credit");
        @(negedge clk);
        set_capture_identity;
        make_tile_vector(2);
        capture_req_row_tile = 6'd2;
        capture_req_accumulators = tile_vector;
        capture_req_lane_valid = 16'hffff;
        capture_req_overflow = 0;
        capture_req_pe_snapshot_safe = 1;
        capture_req_tag = 16'ha102;
        capture_req_valid = 1;
        #1;
        check(!capture_req_ready, "two owned positions backpressure third capture");
        repeat (3) begin
            @(posedge clk); #1;
            check(!capture_req_ready && capture_outstanding == 2,
                  "third capture stays unaccepted while both credits owned");
        end
        capture_req_valid = 0;
        @(negedge clk); capture_rsp_ready = 1;
        @(posedge clk); #1;
        capture_rsp_ready = 0;
        check(capture_rsp_valid && capture_rsp_row_tile == 1,
              "second terminal promotes in FIFO order on first pop");
        check(capture_rsp_tag == 16'ha101 && capture_rsp_status == STATUS_OK,
              "promoted second response retains metadata");
        @(negedge clk); capture_rsp_ready = 1;
        @(posedge clk); #1;
        @(negedge clk); capture_rsp_ready = 0;
        check(capture_outstanding == 0, "both capture credits retire exactly once");
        reset_dut;

        // Full deterministic 320-entry capture/readback, snapshot immutability,
        // COMPLETE/VALID split, response stalls, and two-gate reuse.
        allocate_object;
        fill_and_publish(1'b1);

        // Stale read generation is a zero-data caller-local diagnostic and
        // cannot acquire the current-tile use credit.
        @(negedge clk);
        set_tile_identity;
        tile_req_scratch_generation = scratch_generation + 1'b1;
        tile_req_row_tile = 6'd0;
        tile_req_replay_token = 32'h5151_0001;
        tile_req_tag = 16'h5151;
        tile_req_valid = 1;
        #1;
        wait_count = 0;
        while (!tile_req_ready && wait_count < 1000) begin
            @(negedge clk);
            wait_count = wait_count + 1;
        end
        check(tile_req_ready, "stale-generation tile request became ready");
        @(posedge clk); #1; tile_req_valid = 0;
        wait_count = 0;
        while (!tile_rsp_valid && wait_count < 1000) begin
            @(posedge clk); #1;
            wait_count = wait_count + 1;
        end
        check(tile_rsp_valid && tile_rsp_status == ERR_STALE_GENERATION,
              "stale-generation tile request returns exact diagnostic");
        check(!tile_rsp_complete && tile_rsp_data == 0 && !active_use_valid,
              "stale-generation tile request exposes no payload/use");
        @(negedge clk); tile_rsp_ready = 1;
        @(posedge clk); #1;
        @(negedge clk); tile_rsp_ready = 0;
        check(scratch_state == ST_VALID, "stale read preserves VALID object");

        for (row = 19; row >= 0; row = row - 1) begin
            issue_tile_read(row, 32'h9000_0000 + row, STATUS_OK, 1'b1, row == 19);
            for (index = 0; index < 8; index = index + 1) begin
                @(posedge clk); #1;
                check(use_tile_valid, "tile stays held through two gates x four groups");
                check(use_tile_data == held_vector, "held replay data stable across group gaps");
                check(use_tile_data[(index % 4)*128 +: 128] ==
                      tile_vector[(index % 4)*128 +: 128], "four-lane replay group ordering");
            end
            if (row == 19) begin
                issue_use_release(row, 32'h9000_0000 + row, held_use_token + 1,
                                  1'b1, ERR_STALE_USE);
                check(use_tile_valid, "stale release cannot clear active use");
                issue_use_release(row, 32'h9000_0000 + row, held_use_token,
                                  1'b0, ERR_EXTERNAL_UNSAFE);
                check(use_tile_valid, "incomplete Gate proof cannot clear active use");
            end
            issue_use_release(row, 32'h9000_0000 + row, held_use_token,
                              1'b1, STATUS_OK);
            check(!use_tile_valid, "exact release clears active use");
            check(replayed_tile_bitmap[row], "exact release commits replay bit");
        end
        check(replayed_tile_bitmap == 20'hfffff, "all tile use credits released exactly once");

        // Release/reallocation advances generation; the old generation loses
        // authority.  New allocation identity remains owner-provided.
        send_mgmt(OP_RELEASE_OBJECT, STATUS_OK, ST_EMPTY);
        check(scratch_generation == 2, "normal teardown advances generation once");
        send_mgmt(OP_ALLOCATE, STATUS_OK, ST_FILLING);
        check(scratch_generation == 2, "reallocation captures pre-advanced generation");

        // Publish-before-complete and retryable unsafe snapshot.
        send_mgmt(OP_PUBLISH_VALID, ERR_WRONG_STATE, ST_FILLING);
        issue_capture(0, 16'hffff, 0, 1'b0, ERR_EXTERNAL_UNSAFE, 1'b0, 1'b1);
        check(scratch_state == ST_FILLING, "unsafe snapshot is retryable caller-local error");

        // Normative one-fire arbitration: ordinary management beats capture.
        // The bad opcode receives one terminal diagnostic; the losing capture
        // neither fires nor grants accumulator clear.
        @(negedge clk);
        set_mgmt_identity;
        set_capture_identity;
        make_tile_vector(0);
        mgmt_req_opcode = 3'd7;
        mgmt_req_tag = 16'h7007;
        mgmt_req_valid = 1;
        capture_req_row_tile = 0;
        capture_req_accumulators = tile_vector;
        capture_req_lane_valid = 16'hffff;
        capture_req_overflow = 0;
        capture_req_pe_snapshot_safe = 1;
        capture_req_tag = 16'h7008;
        capture_req_valid = 1;
        #1;
        check(mgmt_req_ready && !capture_req_ready,
              "management wins same-edge arbitration over capture");
        check(!capture_snapshot_commit, "losing capture produces no snapshot event");
        @(posedge clk); #1;
        mgmt_req_valid = 0;
        capture_req_valid = 0;
        consume_mgmt_response(ERR_BAD_OPCODE, ST_FILLING);
        check(committed_entry_count == 0,
              "one-fire arbitration prevents losing capture side effect");

        // Missing lane, out-of-order, duplicate, range, and stale identity are
        // isolated with reset because live capture violations poison object.
        reset_dut; allocate_object;
        issue_capture(0, 16'hfffe, 0, 1'b1, ERR_BAD_LANE_MASK, 1'b0, 1'b0);
        wait_for_state(ST_ERROR, "missing-lane fault reaches ERROR after response drain");
        check(scratch_state == ST_ERROR && committed_entry_count == 0,
              "missing lane poisons without RAM completeness");

        reset_dut; allocate_object;
        issue_capture(1, 16'hffff, 0, 1'b1, ERR_CAPTURE_ORDER, 1'b0, 1'b0);
        wait_for_state(ST_ERROR, "capture-order fault reaches ERROR after response drain");
        check(scratch_state == ST_ERROR, "out-of-order capture poisons object");

        reset_dut; allocate_object;
        issue_capture(0, 16'hffff, 0, 1'b1, STATUS_OK, 1'b1, 1'b0);
        issue_capture(0, 16'hffff, 0, 1'b1, ERR_DUPLICATE_TILE, 1'b0, 1'b0);
        check(committed_entry_count == 16, "duplicate capture does not write twice");

        for (row = 20; row < 64; row = row + 1) begin
            reset_dut; allocate_object;
            issue_capture(row, 16'hffff, 0, 1'b1, ERR_BAD_TILE, 1'b0, 1'b0);
            check(committed_entry_count == 0, "out-of-range capture never writes RAM");
        end

        reset_dut; allocate_object;
        @(negedge clk); set_capture_identity;
        capture_req_stage_ticket = TICKET + 1;
        make_tile_vector(0);
        capture_req_row_tile = 0;
        capture_req_accumulators = tile_vector;
        capture_req_lane_valid = 16'hffff;
        capture_req_overflow = 0;
        capture_req_pe_snapshot_safe = 1;
        capture_req_tag = 16'h5a1e;
        capture_req_valid = 1;
        #1;
        wait_count = 0;
        while (!capture_req_ready && wait_count < 1000) begin
            @(negedge clk);
            wait_count = wait_count + 1;
        end
        check(capture_req_ready, "stale-ticket request became ready");
        #1; check(!capture_snapshot_commit, "stale ticket never grants PE clear");
        @(posedge clk); #1; capture_req_valid = 0;
        wait_count = 0;
        while (!capture_rsp_valid && wait_count < 1000) begin
            @(posedge clk); #1;
            wait_count = wait_count + 1;
        end
        check(capture_rsp_valid, "stale-ticket response arrived");
        check(capture_rsp_status == ERR_STAGE_TICKET_MISMATCH, "stale ticket diagnostic");
        check(local_error_stage_ticket == TICKET, "error scope retains stored owner ticket");
        @(negedge clk); capture_rsp_ready = 1;
        @(posedge clk); #1;
        @(negedge clk); capture_rsp_ready = 0;

        reset_dut; allocate_object;
        @(negedge clk); set_capture_identity;
        capture_req_scratch_generation = scratch_generation + 1'b1;
        make_tile_vector(0);
        capture_req_row_tile = 0;
        capture_req_accumulators = tile_vector;
        capture_req_lane_valid = 16'hffff;
        capture_req_overflow = 0;
        capture_req_pe_snapshot_safe = 1;
        capture_req_tag = 16'h5a1f;
        capture_req_valid = 1;
        #1;
        wait_count = 0;
        while (!capture_req_ready && wait_count < 1000) begin
            @(negedge clk);
            wait_count = wait_count + 1;
        end
        check(capture_req_ready, "stale-generation capture became ready");
        check(!capture_snapshot_commit, "stale generation cannot snapshot PE state");
        @(posedge clk); #1; capture_req_valid = 0;
        wait_count = 0;
        while (!capture_rsp_valid && wait_count < 1000) begin
            @(posedge clk); #1;
            wait_count = wait_count + 1;
        end
        check(capture_rsp_valid && capture_rsp_status == ERR_STALE_GENERATION,
              "stale-generation capture returns exact diagnostic");
        check(local_error_scratch_generation == scratch_generation,
              "stale capture cannot replace poisoned object generation");
        @(negedge clk); capture_rsp_ready = 1;
        @(posedge clk); #1;
        @(negedge clk); capture_rsp_ready = 0;

        // Every PE overflow lane rejects the whole capture, records the lowest
        // lane, and requires the approved coordinated reset.
        for (lane = 0; lane < 16; lane = lane + 1) begin
            reset_dut; allocate_object;
            issue_capture(0, 16'hffff, (16'h0001 << lane), 1'b1,
                          ERR_OVERFLOW, 1'b0, 1'b0);
            check(first_overflow_valid, "overflow records first event");
            check(first_overflow_row_tile == 0, "overflow records row");
            check(first_overflow_lane == lane[3:0], "overflow records lowest lane");
            check(first_overflow_mask == (16'h0001 << lane), "overflow records full mask");
            check(reset_required, "overflow requires coordinated PE/context reset");
            check(committed_entry_count == 0, "overflow capture commits no wrapped data");
        end

        // Read-before-VALID is diagnostic and never exposes data/use.
        reset_dut; allocate_object;
        issue_tile_read(0, 32'h1234, ERR_WRONG_STATE, 1'b0, 1'b1);
        check(scratch_state == ST_FILLING, "read-before-VALID preserves FILLING");

        // Explicit abort at each serializer phase: the accepted snapshot
        // finishes all writes, but its unmaterialized terminal response uses
        // the selected abort code.
        $display("PHASE: serializer final-close sweep");
        for (pipeline_phase = 0; pipeline_phase < 16;
             pipeline_phase = pipeline_phase + 1) begin
            reset_dut; allocate_object;
            make_tile_vector(0);
            @(negedge clk); set_capture_identity;
            capture_req_row_tile = 0;
            capture_req_accumulators = tile_vector;
            capture_req_lane_valid = 16'hffff;
            capture_req_overflow = 0;
            capture_req_pe_snapshot_safe = 1;
            capture_req_tag = 16'h6000 + pipeline_phase;
            capture_req_valid = 1;
            #1;
            wait_count = 0;
            while (!capture_req_ready && wait_count < 1000) begin
                @(negedge clk);
                wait_count = wait_count + 1;
            end
            check(capture_req_ready, "abort-phase capture became ready");
            #1; check(capture_snapshot_commit, "abort-phase capture snapshots successfully");
            @(posedge clk); #1; capture_req_valid = 0;
            repeat (pipeline_phase) @(posedge clk);
            send_final_close_no_wait(1'b0, ERR_ABORTED, 1'b0);
            wait_count = 0;
            while (!capture_rsp_valid && wait_count < 1000) begin
                @(posedge clk); #1;
                wait_count = wait_count + 1;
            end
            check(capture_rsp_valid, "post-close capture response arrived");
            check(capture_rsp_status == ERR_ABORTED, "post-close capture response reports abort");
            check(capture_rsp_committed_lane_mask == 16'hffff,
                  "causal abort drains all accepted serializer writes");
            @(negedge clk); capture_rsp_ready = 1;
            @(posedge clk); #1;
            @(negedge clk); capture_rsp_ready = 0;
            consume_final_close(ERR_ABORTED);
        end

        // Fatal close at every one of the sixteen synchronous pack phases.
        // An unmaterialized accepted read finishes deterministic accounting,
        // but returns the selected fatal code with zero exposed payload/use.
        $display("PHASE: read-pack final-close sweep");
        for (pipeline_phase = 0; pipeline_phase < 16;
             pipeline_phase = pipeline_phase + 1) begin
            reset_dut; allocate_object; fill_and_publish(1'b0);
            fire_tile_read_only(3, 32'hcafe_0000 + pipeline_phase,
                                16'h6800 + pipeline_phase);
            repeat (pipeline_phase) begin @(posedge clk); #1; end
            send_final_close_no_wait(1'b1, ERR_INTERNAL_STATE, 1'b0);
            wait_count = 0;
            while (!tile_rsp_valid && wait_count < 1000) begin
                @(posedge clk); #1;
                wait_count = wait_count + 1;
            end
            check(tile_rsp_valid, "close-time pack produces terminal response");
            check(tile_rsp_status == ERR_INTERNAL_STATE,
                  "unmaterialized packed response uses fatal code");
            check(!tile_rsp_complete && tile_rsp_data == 0,
                  "fatal packed response exposes neither completion nor data");
            check(!use_tile_valid, "fatal packed response cannot authorize Gate use");
            @(negedge clk); tile_rsp_ready = 1;
            @(posedge clk); #1;
            @(negedge clk); tile_rsp_ready = 0;
            consume_final_close(ERR_INTERNAL_STATE);
        end

        // A normal RELEASE accepted on the final active tile can be
        // superseded by final close, but neither response may overtake the
        // causal use-release response.  Generation must not advance.
        $display("PHASE: pending RELEASE superseded by final close");
        reset_dut; allocate_object; fill_and_publish(1'b0);
        force dut.replayed_tile_bitmap_q = 20'hfffdf; // all except row 5
        issue_tile_read(5, 32'hb005_0005, STATUS_OK, 1'b1, 1'b0);
        held_use_token = use_tile_token;
        saved_generation = scratch_generation;
        @(negedge clk);
        set_mgmt_identity;
        mgmt_req_opcode = OP_RELEASE_OBJECT;
        mgmt_req_tag = 16'h6a05;
        mgmt_req_valid = 1;
        #1;
        wait_count = 0;
        while (!mgmt_req_ready && wait_count < 1000) begin
            @(negedge clk);
            wait_count = wait_count + 1;
        end
        check(mgmt_req_ready, "last-tile RELEASE request became ready");
        @(posedge clk); #1; mgmt_req_valid = 0;
        check(teardown_pending && !mgmt_rsp_valid,
              "accepted RELEASE waits for active causal use");
        release dut.replayed_tile_bitmap_q;
        send_final_close_no_wait(1'b1, ERR_INTERNAL_STATE, 1'b0);
        check(teardown_pending && fault_pending,
              "final close coexists with pending RELEASE and active use");
        issue_use_release(5, 32'hb005_0005, held_use_token, 1'b1,
                          ERR_INTERNAL_STATE);
        check(!active_use_valid && replayed_tile_bitmap[5],
              "close-time exact release drains active tile side effect");
        wait_count = 0;
        while (!mgmt_rsp_valid && wait_count < 1000) begin
            @(posedge clk); #1;
            wait_count = wait_count + 1;
        end
        check(mgmt_rsp_valid && mgmt_rsp_status == ERR_INTERNAL_STATE,
              "superseded RELEASE response uses selected close code");
        check(mgmt_rsp_state == ST_ERROR && scratch_generation == saved_generation,
              "superseded RELEASE enters ERROR without generation advance");
        check(!final_close_rsp_valid,
              "final-close response waits behind held superseded RELEASE response");
        repeat (5) begin
            @(posedge clk); #1;
            check(mgmt_rsp_valid && mgmt_rsp_status == ERR_INTERNAL_STATE,
                  "superseded RELEASE response is stable under backpressure");
            check(!final_close_rsp_valid,
                  "held management response remains a close-drain reference");
        end
        @(negedge clk); mgmt_rsp_ready = 1;
        @(posedge clk); #1;
        @(negedge clk); mgmt_rsp_ready = 0;
        consume_final_close(ERR_INTERNAL_STATE);

        // Normal teardown cannot overtake an unfinished pack or a held read
        // response.  Both requests terminate with NOT_COMPLETE and leave the
        // exact read/use ownership intact.
        $display("PHASE: normal release versus pack/held response");
        reset_dut; allocate_object; fill_and_publish(1'b0);
        fire_tile_read_only(0, 32'ha0a0_0000, 16'h6900);
        repeat (5) begin @(posedge clk); #1; end
        send_mgmt(OP_RELEASE_OBJECT, ERR_NOT_COMPLETE, ST_IN_USE);
        check(pack_busy && active_use_valid && !use_tile_valid,
              "rejected release preserves reserved credit but exposes no Gate use");
        wait_count = 0;
        while (!tile_rsp_valid && wait_count < 1000) begin
            @(posedge clk); #1;
            wait_count = wait_count + 1;
        end
        check(tile_rsp_valid && tile_rsp_status == STATUS_OK,
              "pack survives rejected normal release");
        send_mgmt(OP_RELEASE_OBJECT, ERR_NOT_COMPLETE, ST_IN_USE);
        check(tile_rsp_valid && !use_tile_valid,
              "rejected release cannot consume held successful response");
        held_use_token = tile_rsp_use_token;
        held_vector = tile_rsp_data;
        @(negedge clk); tile_rsp_ready = 1;
        @(posedge clk); #1;
        @(negedge clk); tile_rsp_ready = 0;
        check(use_tile_valid && use_tile_data == held_vector,
              "held response remains deliverable after rejected release");
        issue_use_release(0, 32'ha0a0_0000, held_use_token, 1'b1, STATUS_OK);

        // A success response materialized before a data-untrusted fatal keeps
        // immutable OK/data, but its later handshake must not create Gate use.
        $display("PHASE: data-untrusted close with held success");
        fire_tile_read_only(1, 32'ha0a0_0001, 16'h6901);
        repeat (16) begin @(posedge clk); #1; end
        check(tile_rsp_valid && tile_rsp_status == STATUS_OK && tile_rsp_complete,
              "read success materializes before data-untrusted close");
        make_tile_vector(1);
        check(tile_rsp_data == tile_vector, "pre-close success payload is correct");
        send_final_close_no_wait(1'b1, ERR_INTERNAL_STATE, 1'b1);
        check(tile_rsp_valid && tile_rsp_status == STATUS_OK && tile_rsp_data == tile_vector,
              "materialized success remains immutable across final close");
        @(negedge clk); tile_rsp_ready = 1;
        @(posedge clk); #1;
        @(negedge clk); tile_rsp_ready = 0;
        check(!use_tile_valid && !active_use_valid,
              "data-untrusted close prevents held success from starting use");
        consume_final_close(ERR_INTERNAL_STATE);

        // White-box boundary setup is allowed by the approved verification
        // plan solely to reach the otherwise impractical 32-bit wrap edge.
        // Neither RELEASE nor CLEAR_ERROR may wrap FFFF_FFFF to zero.
        $display("PHASE: generation exhaustion gates");
        reset_dut; allocate_object; fill_and_publish(1'b0);
        force dut.replayed_tile_bitmap_q = 20'hfffff;
        force dut.scratch_generation_q = 32'hffff_ffff;
        #1;
        send_mgmt(OP_RELEASE_OBJECT, ERR_GENERATION_EXHAUSTED, ST_ERROR);
        check(scratch_generation == 32'hffff_ffff && scratch_state == ST_ERROR,
              "release generation exhaustion preserves identity/generation");
        check(reset_required && local_error_code == ERR_GENERATION_EXHAUSTED,
              "release exhaustion latches reset-required first error");
        send_mgmt(OP_CLEAR_ERROR, ERR_GENERATION_EXHAUSTED, ST_ERROR);
        check(scratch_generation == 32'hffff_ffff && scratch_state == ST_ERROR,
              "clear at max generation cannot wrap or clear ERROR");
        check(reset_required, "clear generation exhaustion retains reset requirement");
        release dut.scratch_generation_q;
        release dut.replayed_tile_bitmap_q;

        // The raw invariant predicate is intentionally kept out of the wide
        // sticky-error mutation cone.  It must nevertheless fail closed in
        // its detection cycle, and its compact registered record must keep
        // admission closed during the following-cycle sticky update.  Keep a
        // materialized OK response plus a causal serializer in flight to
        // prove neither is lost by that timing cut.
        $display("PHASE: registered internal-fault timing and causal drain");
        reset_dut; allocate_object;
        fire_capture_only(0, 16'h7b00);
        repeat (16) begin @(posedge clk); #1; end
        check(capture_rsp_valid && capture_rsp_status == STATUS_OK &&
              capture_rsp_row_tile == 0,
              "internal-fault precondition holds materialized capture response");
        check(capture_rsp_committed_lane_mask == 16'hffff,
              "held pre-fault response has complete committed mask");
        fire_capture_only(1, 16'h7b01);
        check(capture_busy && capture_outstanding == 2,
              "internal-fault precondition owns causal serializer credit");

        @(negedge clk);
        // White-box corruption reaches the Phase-A 00B invariant: a live
        // lifecycle state without its owner-valid bit.  Stored identity
        // fields themselves remain intact for first-error attribution.
        force dut.scratch_owner_valid_q = 1'b0;
        final_close_req_kind = 1'b0;
        final_close_req_code = ERR_ABORTED;
        final_close_req_data_untrusted = 1'b0;
        final_close_req_causal_producers_drained = 1'b1;
        final_close_req_cancellation_epoch = 32'hface_7b00;
        final_close_req_tag = 16'h7b10;
        final_close_req_valid = 1'b1;
        set_release_identity;
        use_release_req_row_tile = 0;
        use_release_req_replay_token = 32'h7b00_0000;
        use_release_req_use_token = 32'h7b00_0001;
        use_release_req_all_input_handshakes_done = 1'b1;
        use_release_req_tag = 16'h7b11;
        use_release_req_valid = 1'b1;
        set_mgmt_identity;
        mgmt_req_opcode = OP_PUBLISH_VALID;
        mgmt_req_tag = 16'h7b12;
        mgmt_req_valid = 1'b1;
        set_capture_identity;
        make_tile_vector(2);
        capture_req_row_tile = 2;
        capture_req_accumulators = tile_vector;
        capture_req_lane_valid = 16'hffff;
        capture_req_overflow = 0;
        capture_req_pe_snapshot_safe = 1'b1;
        capture_req_tag = 16'h7b13;
        capture_req_valid = 1'b1;
        set_tile_identity;
        tile_req_row_tile = 0;
        tile_req_replay_token = 32'h7b00_0002;
        tile_req_tag = 16'h7b14;
        tile_req_valid = 1'b1;
        #1;
        check(dut.internal_state_fault,
              "newly visible 00B raw invariant is detected combinationally");
        check(!dut.internal_fault_record_valid_q,
              "raw fault precedes its compact registered record");
        check(!final_close_req_ready && !use_release_req_ready &&
              !mgmt_req_ready && !capture_req_ready && !tile_req_ready,
              "raw invariant detection cycle suppresses every new request");
        check(!capture_snapshot_commit,
              "fault-cycle rejected capture cannot authorize PE clear");
        check(capture_rsp_valid && capture_rsp_status == STATUS_OK &&
              capture_rsp_row_tile == 0,
              "pre-materialized response stays immutable in detection cycle");

        @(posedge clk); #1;
        check(dut.internal_fault_record_valid_q,
              "detection edge captures compact internal-fault record");
        check(dut.internal_fault_record_subtype_q ==
              INTERNAL_OWNER_STATE_FAULT,
              "registered fault record preserves subtype 00B");
        check(!local_error_valid && !fault_pending && !reset_required,
              "wide sticky fault mutation is deliberately delayed one clock");
        check(!final_close_req_ready && !use_release_req_ready &&
              !mgmt_req_ready && !capture_req_ready && !tile_req_ready,
              "registered record keeps all admission closed after detect edge");

        @(negedge clk);
        // Repair only the injected raw predicate.  The registered record must
        // independently hold fail-closed behavior until sticky action lands.
        force dut.scratch_owner_valid_q = 1'b1;
        #1;
        check(!dut.internal_state_fault && dut.internal_fault_active,
              "registered record spans repaired raw-fault timing window");
        check(!final_close_req_ready && !use_release_req_ready &&
              !mgmt_req_ready && !capture_req_ready && !tile_req_ready,
              "no request slips through delayed sticky-fault timing cut");

        @(posedge clk); #1;
        check(local_error_valid && local_error_code == ERR_INTERNAL_STATE &&
              local_error_source == ERR_SRC_INTERNAL,
              "registered record installs sticky internal first error");
        check(reset_required && fault_pending,
              "registered internal invariant requires reset and causal drain");
        check(local_error_detail[31:29] == ERR_SRC_INTERNAL &&
              local_error_detail[28:21] == ERR_INTERNAL_STATE &&
              local_error_detail[20:15] == 1 &&
              local_error_detail[14:11] == 0 &&
              local_error_detail[10:0] == INTERNAL_OWNER_STATE_FAULT,
              "first-error detail retains row/lane/subtype from detect edge");
        check(local_error_image_epoch == IMAGE_EPOCH &&
              local_error_stage_id == STAGE_ID &&
              local_error_scratch_generation == 1 &&
              local_error_stage_ticket == TICKET &&
              local_error_logical_branch == BRANCH &&
              local_error_context_generation == CONTEXT &&
              local_error_matrix0_binding_token == BINDING &&
              local_error_source_bank_id == BANK_ID &&
              local_error_source_bank_generation == BANK_GEN &&
              local_error_object_cancellation_epoch == CANCEL_EPOCH,
              "delayed first-error action retains old complete owner identity");
        check(!mgmt_rsp_valid && !tile_rsp_valid &&
              !use_release_rsp_valid && !final_close_rsp_valid,
              "fault-cycle requests produced no terminal responses");
        check(capture_rsp_valid && capture_rsp_status == STATUS_OK &&
              capture_rsp_row_tile == 0,
              "held response remains immutable through sticky update");

        @(negedge clk);
        final_close_req_valid = 1'b0;
        use_release_req_valid = 1'b0;
        mgmt_req_valid = 1'b0;
        capture_req_valid = 1'b0;
        tile_req_valid = 1'b0;
        release dut.scratch_owner_valid_q;

        wait_count = 0;
        while (!dut.capture_exec_terminal_q && wait_count < 100) begin
            @(posedge clk); #1;
            wait_count = wait_count + 1;
            check(capture_rsp_valid && capture_rsp_status == STATUS_OK &&
                  capture_rsp_row_tile == 0,
                  "held OK response is stable while causal serializer drains");
            check(!causal_drain_complete,
                  "fault drain waits for causal serializer and held response");
            check(local_error_detail[10:0] == INTERNAL_OWNER_STATE_FAULT,
                  "repeated fault cycles cannot overwrite first subtype");
        end
        check(dut.capture_exec_terminal_q,
              "accepted serializer reaches terminal position after fault");
        check(capture_rsp_committed_lane_mask == 16'hffff &&
              capture_rsp_status == STATUS_OK,
              "pre-fault response remains bit-stable behind terminal result");

        @(negedge clk); capture_rsp_ready = 1'b1;
        @(posedge clk); #1;
        @(negedge clk); capture_rsp_ready = 1'b0;
        check(capture_rsp_valid && capture_rsp_row_tile == 1 &&
              capture_rsp_status == ERR_INTERNAL_STATE,
              "causal serializer terminal promotes with internal-fault status");
        check(capture_rsp_snapshot_taken &&
              capture_rsp_committed_lane_mask == 16'hffff,
              "faulted causal serializer still reports all committed writes");
        repeat (4) begin
            @(posedge clk); #1;
            check(capture_rsp_valid && capture_rsp_status == ERR_INTERNAL_STATE &&
                  capture_rsp_row_tile == 1,
                  "causal internal-error response remains stable when held");
            check(!causal_drain_complete,
                  "held causal terminal response prevents drain completion");
        end
        @(negedge clk); capture_rsp_ready = 1'b1;
        @(posedge clk); #1;
        @(negedge clk); capture_rsp_ready = 1'b0;
        check(causal_drain_complete && scratch_state == ST_ERROR,
              "internal fault reaches ERROR only after all causal responses retire");
        check(local_error_detail[10:0] == INTERNAL_OWNER_STATE_FAULT &&
              local_error_stage_ticket == TICKET,
              "first-error subtype and owner identity survive complete drain");

        // A newly detected raw fault blocks even an exact causal release on
        // that first edge.  Once the compact record owns the fault, the exact
        // release is the sole permitted admission so an already-delivered
        // Gate use cannot leak.  Its side effect occurs, while its terminal
        // response is the registered internal-fault code.
        $display("PHASE: registered fault permits only causal use release");
        reset_dut; allocate_object; fill_and_publish(1'b0);
        issue_tile_read(4, 32'h7c00_0004, STATUS_OK, 1'b1, 1'b0);
        held_use_token = use_tile_token;
        check(use_tile_valid && active_use_valid,
              "internal-fault release precondition owns delivered use");
        @(negedge clk);
        force dut.scratch_owner_valid_q = 1'b0;
        set_release_identity;
        use_release_req_row_tile = 4;
        use_release_req_replay_token = 32'h7c00_0004;
        use_release_req_use_token = held_use_token;
        use_release_req_all_input_handshakes_done = 1'b1;
        use_release_req_tag = 16'h7c04;
        use_release_req_valid = 1'b1;
        #1;
        check(dut.internal_state_fault && !use_release_req_ready,
              "raw fault edge blocks exact causal release admission");
        check(use_tile_valid && !use_release_rsp_valid,
              "blocked raw-edge release preserves use and has no response");
        @(posedge clk); #1;
        check(dut.internal_fault_record_valid_q && !local_error_valid,
              "active-use fault enters compact record before sticky action");
        check(use_release_req_ready,
              "registered record authorizes exact causal release after detect edge");
        @(negedge clk);
        force dut.scratch_owner_valid_q = 1'b1;
        #1;
        check(!dut.internal_state_fault && dut.internal_fault_record_valid_q,
              "active-use test repairs only raw injected invariant");
        check(use_release_req_ready,
              "registered fault admits exact causal release for drain");
        @(posedge clk); #1;
        check(local_error_valid && local_error_code == ERR_INTERNAL_STATE &&
              local_error_detail[10:0] == INTERNAL_OWNER_STATE_FAULT,
              "active-use delayed fault installs same sticky subtype");
        check(!use_tile_valid && !active_use_valid &&
              replayed_tile_bitmap[4],
              "registered-fault exact release performs causal side effect");
        check(use_release_rsp_valid &&
              use_release_rsp_status == ERR_INTERNAL_STATE,
              "registered-fault release terminal uses internal status");
        @(negedge clk);
        use_release_req_valid = 1'b0;
        release dut.scratch_owner_valid_q;
        repeat (4) begin
            @(posedge clk); #1;
            check(use_release_rsp_valid &&
                  use_release_rsp_status == ERR_INTERNAL_STATE,
                  "internal-fault causal release response is stable when held");
            check(!causal_drain_complete,
                  "held causal release response prevents fault drain");
        end
        @(negedge clk); use_release_rsp_ready = 1'b1;
        @(posedge clk); #1;
        @(negedge clk); use_release_rsp_ready = 1'b0;
        check(causal_drain_complete && scratch_state == ST_ERROR,
              "causal release response retirement completes fault drain");
        check(local_error_stage_ticket == TICKET &&
              local_error_matrix0_binding_token == BINDING,
              "active-use fault retains original owner identity after drain");

        // Approval-directed case: a success response/use exists before final
        // close.  Exact causal release still clears the use credit and replay
        // bit, but its newly materialized response returns the selected code.
        $display("PHASE: directed close-time causal use release");
        reset_dut; allocate_object; fill_and_publish(1'b0);
        issue_tile_read(7, 32'hd00d_0007, STATUS_OK, 1'b1, 1'b1);
        held_use_token = use_tile_token;
        send_final_close_no_wait(1'b1, ERR_INTERNAL_STATE, 1'b0);
        check(use_tile_valid && active_use_valid, "final close preserves causal active use");
        issue_use_release(7, 32'hd00d_0007, held_use_token, 1'b0,
                          ERR_EXTERNAL_UNSAFE);
        check(use_tile_valid && active_use_valid,
              "close-time incomplete proof returns error and retains use");
        issue_use_release(7, 32'hd00d_0007, held_use_token, 1'b1, ERR_INTERNAL_STATE);
        check(!use_tile_valid && !active_use_valid,
              "causal release side effect occurs after final close");
        check(replayed_tile_bitmap[7], "causal close-time release commits replay evidence");
        consume_final_close(ERR_INTERNAL_STATE);

        // Data-untrusted fatal requires reset and blocks further data use.
        reset_dut; allocate_object;
        send_final_close_no_wait(1'b1, ERR_INTERNAL_STATE, 1'b1);
        consume_final_close(ERR_INTERNAL_STATE);
        check(reset_required, "data-untrusted fatal requires reset");

        // Reset is the only event allowed to abandon cross-reset read/use
        // transactions.  Exercise pack, held response, and delivered use.
        $display("PHASE: reset read/use positions");
        reset_dut; allocate_object; fill_and_publish(1'b0);
        fire_tile_read_only(2, 32'h7200_0002, 16'h7202);
        repeat (7) begin @(posedge clk); #1; end
        check(pack_busy && active_use_valid && !use_tile_valid,
              "precondition: reset during pack");
        reset_dut;
        check(!pack_busy && !tile_rsp_valid && !active_use_valid,
              "reset drops in-progress pack authority");

        allocate_object; fill_and_publish(1'b0);
        fire_tile_read_only(3, 32'h7200_0003, 16'h7203);
        repeat (16) begin @(posedge clk); #1; end
        check(tile_rsp_valid && !use_tile_valid,
              "precondition: reset with held packed response");
        reset_dut;
        check(!tile_rsp_valid && !use_tile_valid && !active_use_valid,
              "reset drops held response/use reservation");

        allocate_object; fill_and_publish(1'b0);
        issue_tile_read(4, 32'h7200_0004, STATUS_OK, 1'b1, 1'b0);
        check(use_tile_valid && active_use_valid,
              "precondition: reset during delivered use");
        reset_dut;
        check(!use_tile_valid && !active_use_valid && scratch_state == ST_EMPTY,
              "reset drops delivered use authority");

        // Reset during an owned serializer drops authority/pipeline without
        // attempting to reset the payload RAM.
        reset_dut; allocate_object;
        make_tile_vector(0);
        @(negedge clk); set_capture_identity;
        capture_req_row_tile = 0;
        capture_req_accumulators = tile_vector;
        capture_req_valid = 1;
        #1;
        wait_count = 0;
        while (!capture_req_ready && wait_count < 1000) begin
            @(negedge clk);
            wait_count = wait_count + 1;
        end
        check(capture_req_ready, "reset-during-capture request became ready");
        @(posedge clk); #1; capture_req_valid = 0;
        repeat (7) @(posedge clk);
        reset_dut;
        check(capture_outstanding == 0 && !capture_rsp_valid,
              "reset abandons cross-reset serializer transaction");

        if (failures == 0) begin
            $display("PASS tb_matrix0_raw_accumulator_scratch: %0d checks", checks);
            $finish;
        end else begin
            $display("FAIL tb_matrix0_raw_accumulator_scratch: %0d failures / %0d checks",
                     failures, checks);
            $finish;
        end
    end

    initial begin
        #20000000;
        fail("global timeout");
        $finish;
    end
endmodule
