`timescale 1ns/1ps

// One FB-GSU2 matrix-0 raw-accumulator scratch object.
//
// The payload RAM is deliberately not reset.  Authority, completeness,
// response ownership, and pipeline-valid state make old bits inaccessible.
// final_close is the owner's coordinated final local close transaction; it
// must not be connected directly to a raw Controller abort.
module matrix0_raw_accumulator_scratch (
    input  wire         clk,
    input  wire         rst_n,

    output wire [2:0]   scratch_state,
    output wire [31:0]  scratch_generation,
    output wire         scratch_generation_initialized,
    output wire         scratch_owner_valid,
    output wire [31:0]  scratch_image_epoch,
    output wire [3:0]   scratch_stage_id,
    output wire [31:0]  scratch_stage_ticket,
    output wire [1:0]   scratch_logical_branch,
    output wire [31:0]  scratch_context_generation,
    output wire [31:0]  scratch_matrix0_binding_token,
    output wire         scratch_source_bank_id,
    output wire [31:0]  scratch_source_bank_generation,
    output wire [31:0]  scratch_cancellation_epoch,
    output wire [19:0]  committed_tile_bitmap,
    output wire [8:0]   committed_entry_count,
    output wire [19:0]  replayed_tile_bitmap,
    output wire [1:0]   capture_outstanding,
    output wire         capture_busy,
    output wire         pack_busy,
    output wire         active_use_valid,
    output wire [31:0]  active_use_token,
    output wire [5:0]   active_use_row_tile,
    output wire [31:0]  active_use_replay_token,
    output wire         teardown_pending,
    output wire         fault_pending,
    output wire         causal_drain_complete,
    output wire         local_quiescent,
    output wire         early_retire_evidence_valid,
    output wire         reset_required,

    input  wire         mgmt_req_valid,
    output wire         mgmt_req_ready,
    input  wire [2:0]   mgmt_req_opcode,
    input  wire [31:0]  mgmt_req_image_epoch,
    input  wire [3:0]   mgmt_req_stage_id,
    input  wire [31:0]  mgmt_req_stage_ticket,
    input  wire [1:0]   mgmt_req_logical_branch,
    input  wire [31:0]  mgmt_req_context_generation,
    input  wire [31:0]  mgmt_req_matrix0_binding_token,
    input  wire         mgmt_req_source_bank_id,
    input  wire [31:0]  mgmt_req_source_bank_generation,
    input  wire [31:0]  mgmt_req_scratch_generation,
    input  wire [31:0]  mgmt_req_cancellation_epoch,
    input  wire [5:0]   mgmt_req_expected_tile_count,
    input  wire [15:0]  mgmt_req_expected_lane_mask,
    input  wire         mgmt_req_external_safe,
    input  wire [15:0]  mgmt_req_tag,
    output wire         mgmt_rsp_valid,
    input  wire         mgmt_rsp_ready,
    output wire [2:0]   mgmt_rsp_opcode,
    output wire [31:0]  mgmt_rsp_request_generation,
    output wire [31:0]  mgmt_rsp_result_generation,
    output wire [2:0]   mgmt_rsp_state,
    output wire [31:0]  mgmt_rsp_stage_ticket,
    output wire [31:0]  mgmt_rsp_matrix0_binding_token,
    output wire         mgmt_rsp_source_bank_id,
    output wire [31:0]  mgmt_rsp_source_bank_generation,
    output wire [15:0]  mgmt_rsp_tag,
    output wire [7:0]   mgmt_rsp_status,

    input  wire         final_close_req_valid,
    output wire         final_close_req_ready,
    input  wire         final_close_req_kind,
    input  wire [7:0]   final_close_req_code,
    input  wire         final_close_req_data_untrusted,
    input  wire         final_close_req_causal_producers_drained,
    input  wire [31:0]  final_close_req_cancellation_epoch,
    input  wire [15:0]  final_close_req_tag,
    output wire         final_close_rsp_valid,
    input  wire         final_close_rsp_ready,
    output wire [2:0]   final_close_rsp_state,
    output wire [31:0]  final_close_rsp_generation,
    output wire [31:0]  final_close_rsp_stage_ticket,
    output wire [31:0]  final_close_rsp_matrix0_binding_token,
    output wire [31:0]  final_close_rsp_cancellation_epoch,
    output wire [15:0]  final_close_rsp_tag,
    output wire [7:0]   final_close_rsp_status,
    output wire         final_close_rsp_reset_required,

    input  wire         capture_req_valid,
    output wire         capture_req_ready,
    input  wire [31:0]  capture_req_image_epoch,
    input  wire [3:0]   capture_req_stage_id,
    input  wire [31:0]  capture_req_stage_ticket,
    input  wire [1:0]   capture_req_logical_branch,
    input  wire [31:0]  capture_req_context_generation,
    input  wire [31:0]  capture_req_matrix0_binding_token,
    input  wire [31:0]  capture_req_scratch_generation,
    input  wire [31:0]  capture_req_cancellation_epoch,
    input  wire [5:0]   capture_req_row_tile,
    input  wire [511:0] capture_req_accumulators,
    input  wire [15:0]  capture_req_lane_valid,
    input  wire [15:0]  capture_req_overflow,
    input  wire         capture_req_pe_snapshot_safe,
    input  wire [15:0]  capture_req_tag,
    output wire         capture_snapshot_commit,
    output wire [5:0]   capture_snapshot_row_tile,
    output wire [31:0]  capture_snapshot_scratch_generation,
    output wire [31:0]  capture_snapshot_stage_ticket,
    output wire [31:0]  capture_snapshot_context_generation,
    output wire [31:0]  capture_snapshot_matrix0_binding_token,
    output wire [15:0]  capture_snapshot_tag,
    output wire         capture_rsp_valid,
    input  wire         capture_rsp_ready,
    output wire [31:0]  capture_rsp_image_epoch,
    output wire [3:0]   capture_rsp_stage_id,
    output wire [31:0]  capture_rsp_scratch_generation,
    output wire [31:0]  capture_rsp_stage_ticket,
    output wire [1:0]   capture_rsp_logical_branch,
    output wire [31:0]  capture_rsp_context_generation,
    output wire [31:0]  capture_rsp_matrix0_binding_token,
    output wire [31:0]  capture_rsp_cancellation_epoch,
    output wire [5:0]   capture_rsp_row_tile,
    output wire         capture_rsp_snapshot_taken,
    output wire [15:0]  capture_rsp_committed_lane_mask,
    output wire [19:0]  capture_rsp_cumulative_tile_bitmap,
    output wire [8:0]   capture_rsp_cumulative_entry_count,
    output wire         capture_rsp_source_bank_id,
    output wire [31:0]  capture_rsp_source_bank_generation,
    output wire [15:0]  capture_rsp_tag,
    output wire [7:0]   capture_rsp_status,

    input  wire         tile_req_valid,
    output wire         tile_req_ready,
    input  wire [31:0]  tile_req_image_epoch,
    input  wire [3:0]   tile_req_stage_id,
    input  wire [31:0]  tile_req_stage_ticket,
    input  wire [1:0]   tile_req_logical_branch,
    input  wire [31:0]  tile_req_context_generation,
    input  wire [31:0]  tile_req_retired_binding_token,
    input  wire [31:0]  tile_req_scratch_generation,
    input  wire [31:0]  tile_req_cancellation_epoch,
    input  wire [5:0]   tile_req_row_tile,
    input  wire [31:0]  tile_req_replay_token,
    input  wire         tile_req_retired_binding_safe,
    input  wire [15:0]  tile_req_tag,
    output wire         tile_rsp_valid,
    input  wire         tile_rsp_ready,
    output wire [511:0] tile_rsp_data,
    output wire         tile_rsp_complete,
    output wire [31:0]  tile_rsp_image_epoch,
    output wire [3:0]   tile_rsp_stage_id,
    output wire [31:0]  tile_rsp_scratch_generation,
    output wire [1:0]   tile_rsp_logical_branch,
    output wire [31:0]  tile_rsp_context_generation,
    output wire [31:0]  tile_rsp_cancellation_epoch,
    output wire [5:0]   tile_rsp_row_tile,
    output wire [31:0]  tile_rsp_replay_token,
    output wire [31:0]  tile_rsp_use_token,
    output wire [31:0]  tile_rsp_stage_ticket,
    output wire [31:0]  tile_rsp_matrix0_binding_token,
    output wire         tile_rsp_source_bank_id,
    output wire [31:0]  tile_rsp_source_bank_generation,
    output wire [15:0]  tile_rsp_tag,
    output wire [7:0]   tile_rsp_status,
    output wire         use_tile_valid,
    output wire [511:0] use_tile_data,
    output wire [31:0]  use_tile_image_epoch,
    output wire [3:0]   use_tile_stage_id,
    output wire [31:0]  use_tile_scratch_generation,
    output wire [31:0]  use_tile_stage_ticket,
    output wire [1:0]   use_tile_logical_branch,
    output wire [31:0]  use_tile_context_generation,
    output wire [31:0]  use_tile_matrix0_binding_token,
    output wire [31:0]  use_tile_cancellation_epoch,
    output wire         use_tile_source_bank_id,
    output wire [31:0]  use_tile_source_bank_generation,
    output wire [5:0]   use_tile_row_tile,
    output wire [31:0]  use_tile_replay_token,
    output wire [31:0]  use_tile_token,

    input  wire         use_release_req_valid,
    output wire         use_release_req_ready,
    input  wire [31:0]  use_release_req_image_epoch,
    input  wire [3:0]   use_release_req_stage_id,
    input  wire [31:0]  use_release_req_scratch_generation,
    input  wire [31:0]  use_release_req_stage_ticket,
    input  wire [1:0]   use_release_req_logical_branch,
    input  wire [31:0]  use_release_req_context_generation,
    input  wire [31:0]  use_release_req_matrix0_binding_token,
    input  wire [31:0]  use_release_req_cancellation_epoch,
    input  wire [5:0]   use_release_req_row_tile,
    input  wire [31:0]  use_release_req_replay_token,
    input  wire [31:0]  use_release_req_use_token,
    input  wire         use_release_req_all_input_handshakes_done,
    input  wire [15:0]  use_release_req_tag,
    output wire         use_release_rsp_valid,
    input  wire         use_release_rsp_ready,
    output wire [31:0]  use_release_rsp_image_epoch,
    output wire [3:0]   use_release_rsp_stage_id,
    output wire [31:0]  use_release_rsp_scratch_generation,
    output wire [31:0]  use_release_rsp_stage_ticket,
    output wire [1:0]   use_release_rsp_logical_branch,
    output wire [31:0]  use_release_rsp_context_generation,
    output wire [31:0]  use_release_rsp_matrix0_binding_token,
    output wire [31:0]  use_release_rsp_cancellation_epoch,
    output wire [5:0]   use_release_rsp_row_tile,
    output wire [31:0]  use_release_rsp_replay_token,
    output wire [31:0]  use_release_rsp_use_token,
    output wire [15:0]  use_release_rsp_tag,
    output wire [7:0]   use_release_rsp_status,

    output wire         local_error_valid,
    output wire [7:0]   local_error_code,
    output wire [2:0]   local_error_source,
    output wire [31:0]  local_error_detail,
    output wire [31:0]  local_error_image_epoch,
    output wire [3:0]   local_error_stage_id,
    output wire [31:0]  local_error_scratch_generation,
    output wire [31:0]  local_error_stage_ticket,
    output wire [1:0]   local_error_logical_branch,
    output wire [31:0]  local_error_context_generation,
    output wire [31:0]  local_error_matrix0_binding_token,
    output wire         local_error_source_bank_id,
    output wire [31:0]  local_error_source_bank_generation,
    output wire [31:0]  local_error_object_cancellation_epoch,
    output wire [31:0]  local_error_stop_cancellation_epoch,
    output wire [15:0]  local_error_offender_tag,
    output wire [5:0]   local_error_offender_row_tile,
    output wire         first_overflow_valid,
    output wire [5:0]   first_overflow_row_tile,
    output wire [3:0]   first_overflow_lane,
    output wire [15:0]  first_overflow_mask
);

    localparam [2:0] ST_EMPTY    = 3'd0;
    localparam [2:0] ST_FILLING  = 3'd1;
    localparam [2:0] ST_COMPLETE = 3'd2;
    localparam [2:0] ST_VALID    = 3'd3;
    localparam [2:0] ST_IN_USE   = 3'd4;
    localparam [2:0] ST_ERROR    = 3'd5;

    localparam [2:0] MGMT_ALLOCATE       = 3'd0;
    localparam [2:0] MGMT_PUBLISH_VALID  = 3'd1;
    localparam [2:0] MGMT_RELEASE_OBJECT = 3'd2;
    localparam [2:0] MGMT_CLEAR_ERROR    = 3'd3;

    localparam [7:0] STATUS_OK                        = 8'h00;
    localparam [7:0] STATUS_ERR_BAD_OPCODE            = 8'h01;
    localparam [7:0] STATUS_ERR_WRONG_STATE           = 8'h02;
    localparam [7:0] STATUS_ERR_STALE_GENERATION      = 8'h03;
    localparam [7:0] STATUS_ERR_OWNER_MISMATCH        = 8'h04;
    localparam [7:0] STATUS_ERR_NOT_QUIESCENT         = 8'h05;
    localparam [7:0] STATUS_ERR_EXTERNAL_UNSAFE       = 8'h06;
    localparam [7:0] STATUS_ERR_GENERATION_EXHAUSTED  = 8'h07;
    localparam [7:0] STATUS_ERR_ABORTED               = 8'h09;
    localparam [7:0] STATUS_ERR_LOCAL_PROTOCOL        = 8'h0a;
    localparam [7:0] STATUS_ERR_INTERNAL_STATE        = 8'h0b;
    localparam [7:0] STATUS_ERR_STAGE_TICKET_MISMATCH = 8'h20;
    localparam [7:0] STATUS_ERR_CONTEXT_MISMATCH      = 8'h21;
    localparam [7:0] STATUS_ERR_BINDING_MISMATCH      = 8'h22;
    localparam [7:0] STATUS_ERR_IMAGE_EPOCH_MISMATCH  = 8'h23;
    localparam [7:0] STATUS_ERR_BRANCH_MISMATCH       = 8'h24;
    localparam [7:0] STATUS_ERR_BAD_TILE              = 8'h25;
    localparam [7:0] STATUS_ERR_BAD_LANE_MASK         = 8'h26;
    localparam [7:0] STATUS_ERR_DUPLICATE_TILE        = 8'h27;
    localparam [7:0] STATUS_ERR_CAPTURE_ORDER         = 8'h28;
    localparam [7:0] STATUS_ERR_OVERFLOW              = 8'h29;
    localparam [7:0] STATUS_ERR_NOT_COMPLETE          = 8'h2a;
    localparam [7:0] STATUS_ERR_STALE_USE             = 8'h2b;
    localparam [7:0] STATUS_ERR_DUPLICATE_RELEASE     = 8'h2c;
    localparam [7:0] STATUS_ERR_CANCELLATION_EPOCH    = 8'h2d;
    localparam [7:0] STATUS_ERR_SOURCE_BANK_MISMATCH  = 8'h2e;
    localparam [7:0] STATUS_ERR_TILE_ALREADY_USED     = 8'h2f;
    localparam [7:0] STATUS_ERR_BAD_CLOSE_CODE        = 8'h30;

    localparam [2:0] ERR_SRC_MGMT     = 3'b000;
    localparam [2:0] ERR_SRC_CAPTURE  = 3'b001;
    localparam [2:0] ERR_SRC_TILE     = 3'b010;
    localparam [2:0] ERR_SRC_RELEASE  = 3'b011;
    localparam [2:0] ERR_SRC_INTERNAL = 3'b100;
    localparam [2:0] ERR_SRC_CLOSE    = 3'b101;
    localparam [2:0] ERR_SRC_GEN      = 3'b110;

    // A padded physical depth gives Vivado 2018.3 a canonical 512 x 32
    // single-port block-RAM geometry while logical accesses remain 0..319.
    (* ram_style = "block" *) reg [31:0] raw_mem [0:511];
    reg [31:0] ram_read_data_q;

    reg [2:0]  scratch_state_q;
    reg [31:0] scratch_generation_q;
    reg        scratch_generation_initialized_q;
    reg        scratch_owner_valid_q;
    reg [31:0] scratch_image_epoch_q;
    reg [3:0]  scratch_stage_id_q;
    reg [31:0] scratch_stage_ticket_q;
    reg [1:0]  scratch_logical_branch_q;
    reg [31:0] scratch_context_generation_q;
    reg [31:0] scratch_matrix0_binding_token_q;
    reg        scratch_source_bank_id_q;
    reg [31:0] scratch_source_bank_generation_q;
    reg [31:0] scratch_cancellation_epoch_q;
    reg [19:0] committed_tile_bitmap_q;
    reg [8:0]  committed_entry_count_q;
    reg [19:0] replayed_tile_bitmap_q;
    reg [5:0]  next_expected_tile_q;
    reg [31:0] use_token_counter_q;

    // Capture execution/terminal position.
    reg         capture_exec_valid_q;
    reg         capture_exec_terminal_q;
    reg [511:0] capture_data_q;
    reg [3:0]   capture_lane_q;
    reg [15:0]  capture_committed_mask_q;
    reg [31:0]  capture_exec_image_epoch_q;
    reg [3:0]   capture_exec_stage_id_q;
    reg [31:0]  capture_exec_scratch_generation_q;
    reg [31:0]  capture_exec_stage_ticket_q;
    reg [1:0]   capture_exec_logical_branch_q;
    reg [31:0]  capture_exec_context_generation_q;
    reg [31:0]  capture_exec_binding_token_q;
    reg [31:0]  capture_exec_cancellation_epoch_q;
    reg [5:0]   capture_exec_row_tile_q;
    reg         capture_exec_snapshot_taken_q;
    reg [19:0]  capture_exec_bitmap_q;
    reg [8:0]   capture_exec_count_q;
    reg         capture_exec_source_bank_id_q;
    reg [31:0]  capture_exec_source_bank_generation_q;
    reg [15:0]  capture_exec_tag_q;
    reg [7:0]   capture_exec_status_q;

    reg         capture_rsp_valid_q;
    reg [31:0]  capture_rsp_image_epoch_q;
    reg [3:0]   capture_rsp_stage_id_q;
    reg [31:0]  capture_rsp_scratch_generation_q;
    reg [31:0]  capture_rsp_stage_ticket_q;
    reg [1:0]   capture_rsp_logical_branch_q;
    reg [31:0]  capture_rsp_context_generation_q;
    reg [31:0]  capture_rsp_binding_token_q;
    reg [31:0]  capture_rsp_cancellation_epoch_q;
    reg [5:0]   capture_rsp_row_tile_q;
    reg         capture_rsp_snapshot_taken_q;
    reg [15:0]  capture_rsp_committed_lane_mask_q;
    reg [19:0]  capture_rsp_bitmap_q;
    reg [8:0]   capture_rsp_count_q;
    reg         capture_rsp_source_bank_id_q;
    reg [31:0]  capture_rsp_source_bank_generation_q;
    reg [15:0]  capture_rsp_tag_q;
    reg [7:0]   capture_rsp_status_q;

    // One current-tile position covers packing, response stall, and use.
    reg         tile_slot_valid_q;
    reg         pack_busy_q;
    reg [3:0]   pack_lane_q;
    reg [511:0] current_tile_data_q;
    reg         tile_rsp_valid_q;
    reg         use_tile_valid_q;
    reg [31:0]  tile_image_epoch_q;
    reg [3:0]   tile_stage_id_q;
    reg [31:0]  tile_scratch_generation_q;
    reg [31:0]  tile_stage_ticket_q;
    reg [1:0]   tile_logical_branch_q;
    reg [31:0]  tile_context_generation_q;
    reg [31:0]  tile_binding_token_q;
    reg [31:0]  tile_cancellation_epoch_q;
    reg [5:0]   tile_row_tile_q;
    reg [31:0]  tile_replay_token_q;
    reg [31:0]  tile_use_token_q;
    reg         tile_source_bank_id_q;
    reg [31:0]  tile_source_bank_generation_q;
    reg [15:0]  tile_tag_q;
    reg [7:0]   tile_status_q;

    // Exact use-release terminal response.
    reg         use_release_rsp_valid_q;
    reg [31:0]  use_release_rsp_image_epoch_q;
    reg [3:0]   use_release_rsp_stage_id_q;
    reg [31:0]  use_release_rsp_scratch_generation_q;
    reg [31:0]  use_release_rsp_stage_ticket_q;
    reg [1:0]   use_release_rsp_logical_branch_q;
    reg [31:0]  use_release_rsp_context_generation_q;
    reg [31:0]  use_release_rsp_binding_token_q;
    reg [31:0]  use_release_rsp_cancellation_epoch_q;
    reg [5:0]   use_release_rsp_row_tile_q;
    reg [31:0]  use_release_rsp_replay_token_q;
    reg [31:0]  use_release_rsp_use_token_q;
    reg [15:0]  use_release_rsp_tag_q;
    reg [7:0]   use_release_rsp_status_q;

    // Ordinary response plus the only delayed ordinary descriptor (release).
    reg         mgmt_rsp_valid_q;
    reg [2:0]   mgmt_rsp_opcode_q;
    reg [31:0]  mgmt_rsp_request_generation_q;
    reg [31:0]  mgmt_rsp_result_generation_q;
    reg [2:0]   mgmt_rsp_state_q;
    reg [31:0]  mgmt_rsp_stage_ticket_q;
    reg [31:0]  mgmt_rsp_binding_token_q;
    reg         mgmt_rsp_source_bank_id_q;
    reg [31:0]  mgmt_rsp_source_bank_generation_q;
    reg [15:0]  mgmt_rsp_tag_q;
    reg [7:0]   mgmt_rsp_status_q;
    reg         mgmt_pending_q;
    reg [2:0]   mgmt_pending_opcode_q;
    reg [31:0]  mgmt_pending_request_generation_q;
    reg [15:0]  mgmt_pending_tag_q;
    reg [7:0]   mgmt_pending_status_q;

    // Final-close descriptor and response are independent of ordinary mgmt.
    reg         close_pending_q;
    reg         close_had_owner_q;
    reg [7:0]   close_code_q;
    reg         close_data_untrusted_q;
    reg [31:0]  close_cancellation_epoch_q;
    reg [15:0]  close_tag_q;
    reg         final_close_rsp_valid_q;
    reg [2:0]   final_close_rsp_state_q;
    reg [31:0]  final_close_rsp_generation_q;
    reg [31:0]  final_close_rsp_stage_ticket_q;
    reg [31:0]  final_close_rsp_binding_token_q;
    reg [31:0]  final_close_rsp_cancellation_epoch_q;
    reg [15:0]  final_close_rsp_tag_q;
    reg [7:0]   final_close_rsp_status_q;
    reg         final_close_rsp_reset_required_q;

    reg         fault_pending_q;
    reg [7:0]   fault_code_q;
    reg         teardown_pending_q;
    reg         reset_required_q;

    // Raw invariant detection is intentionally separated from the sticky
    // fault action.  The raw predicate only closes admission combinationally
    // and selects a response which materializes on that edge.  This compact
    // record then drives the high-fanout lifecycle/error updates one clock
    // later, keeping the full invariant cone off identity-register controls.
    reg         internal_fault_record_valid_q;
    reg [10:0]  internal_fault_record_subtype_q;
    reg [5:0]   internal_fault_record_row_tile_q;
    reg [3:0]   internal_fault_record_lane_q;
    reg         mgmt_drain_checked_q;
    reg         close_drain_checked_q;

    // Sticky local error scope.
    reg         local_error_valid_q;
    reg [7:0]   local_error_code_q;
    reg [2:0]   local_error_source_q;
    reg [31:0]  local_error_detail_q;
    reg [31:0]  local_error_image_epoch_q;
    reg [3:0]   local_error_stage_id_q;
    reg [31:0]  local_error_scratch_generation_q;
    reg [31:0]  local_error_stage_ticket_q;
    reg [1:0]   local_error_logical_branch_q;
    reg [31:0]  local_error_context_generation_q;
    reg [31:0]  local_error_binding_token_q;
    reg         local_error_source_bank_id_q;
    reg [31:0]  local_error_source_bank_generation_q;
    reg [31:0]  local_error_object_cancellation_epoch_q;
    reg [31:0]  local_error_stop_cancellation_epoch_q;
    reg [15:0]  local_error_offender_tag_q;
    reg [5:0]   local_error_offender_row_tile_q;
    reg         first_overflow_valid_q;
    reg [5:0]   first_overflow_row_tile_q;
    reg [3:0]   first_overflow_lane_q;
    reg [15:0]  first_overflow_mask_q;

    reg [7:0] mgmt_accept_status;
    reg [7:0] capture_accept_status;
    reg       capture_accept_poison;
    reg       capture_accept_overflow;
    reg [3:0] capture_lowest_lane;
    reg [3:0] capture_lowest_missing_lane;
    reg [7:0] tile_accept_status;
    reg [7:0] use_release_accept_status;
    reg       use_release_accept_exact;
    reg [7:0] close_accept_status;

    wire internal_state_fault;
    wire internal_fault_active;
    wire final_close_candidate;
    wire final_close_fire;
    wire final_close_install_fire;
    wire mgmt_req_fire;
    wire capture_req_fire;
    wire capture_success_fire;
    wire capture_poison_fire;
    wire tile_req_fire;
    wire tile_success_fire;
    wire use_release_req_fire;
    wire use_release_exact_fire;
    wire mgmt_rsp_fire;
    wire capture_rsp_fire;
    wire tile_rsp_fire;
    wire use_release_rsp_fire;
    wire final_close_rsp_fire;
    wire capture_rsp_can_take;
    wire capture_write_fire;
    wire ram_read_fire;
    wire [8:0] ram_read_addr;
    wire [8:0] capture_write_addr;
    wire [31:0] capture_write_data;
    wire stop_pending;
    wire [7:0] selected_stop_code;
    wire release_identity_exact;
    wire duplicate_release_exact;
    wire release_last_tile_ok;
    wire mgmt_allocate_ok;
    wire mgmt_publish_ok;
    wire mgmt_release_ok;
    wire mgmt_release_generation_exhausted;
    wire mgmt_clear_ok;
    wire mgmt_clear_generation_exhausted;
    wire tile_slot_clears_this_edge;
    wire causal_drain_after_retire;
    wire [8:0] strict_order_entry_count;
    reg [10:0] internal_fault_subtype;
    integer lane_scan;
    reg overflow_lane_found;
    reg missing_lane_found;

    assign scratch_state = scratch_state_q;
    assign scratch_generation = scratch_generation_q;
    assign scratch_generation_initialized =
        scratch_generation_initialized_q;
    assign scratch_owner_valid = scratch_owner_valid_q;
    assign scratch_image_epoch = scratch_owner_valid_q ?
                                 scratch_image_epoch_q : 32'd0;
    assign scratch_stage_id = scratch_owner_valid_q ?
                              scratch_stage_id_q : 4'd0;
    assign scratch_stage_ticket = scratch_owner_valid_q ?
                                  scratch_stage_ticket_q : 32'd0;
    assign scratch_logical_branch = scratch_owner_valid_q ?
                                    scratch_logical_branch_q : 2'd0;
    assign scratch_context_generation = scratch_owner_valid_q ?
                                        scratch_context_generation_q : 32'd0;
    assign scratch_matrix0_binding_token = scratch_owner_valid_q ?
                                           scratch_matrix0_binding_token_q :
                                           32'd0;
    assign scratch_source_bank_id = scratch_owner_valid_q ?
                                    scratch_source_bank_id_q : 1'b0;
    assign scratch_source_bank_generation = scratch_owner_valid_q ?
                                            scratch_source_bank_generation_q :
                                            32'd0;
    assign scratch_cancellation_epoch = scratch_owner_valid_q ?
                                        scratch_cancellation_epoch_q : 32'd0;
    assign committed_tile_bitmap = committed_tile_bitmap_q;
    assign committed_entry_count = committed_entry_count_q;
    assign replayed_tile_bitmap = replayed_tile_bitmap_q;
    assign capture_outstanding = {1'b0, capture_exec_valid_q} +
                                 {1'b0, capture_rsp_valid_q};
    assign capture_busy = capture_exec_valid_q;
    assign pack_busy = pack_busy_q;
    // A legal read owns its use credit from acceptance through exact release;
    // use_tile_valid is the later, stricter Gate-replay authorization.
    assign active_use_valid = tile_slot_valid_q &&
                              (tile_use_token_q != 32'd0);
    assign active_use_token = active_use_valid ? tile_use_token_q : 32'd0;
    assign active_use_row_tile = active_use_valid ? tile_row_tile_q : 6'd0;
    assign active_use_replay_token = active_use_valid ?
                                     tile_replay_token_q : 32'd0;
    assign teardown_pending = teardown_pending_q;
    assign fault_pending = fault_pending_q;
    assign reset_required = reset_required_q;

    assign mgmt_rsp_valid = mgmt_rsp_valid_q;
    assign mgmt_rsp_opcode = mgmt_rsp_valid_q ? mgmt_rsp_opcode_q : 3'd0;
    assign mgmt_rsp_request_generation = mgmt_rsp_valid_q ?
        mgmt_rsp_request_generation_q : 32'd0;
    assign mgmt_rsp_result_generation = mgmt_rsp_valid_q ?
        mgmt_rsp_result_generation_q : 32'd0;
    assign mgmt_rsp_state = mgmt_rsp_valid_q ? mgmt_rsp_state_q : ST_EMPTY;
    assign mgmt_rsp_stage_ticket = mgmt_rsp_valid_q ?
        mgmt_rsp_stage_ticket_q : 32'd0;
    assign mgmt_rsp_matrix0_binding_token = mgmt_rsp_valid_q ?
        mgmt_rsp_binding_token_q : 32'd0;
    assign mgmt_rsp_source_bank_id = mgmt_rsp_valid_q ?
        mgmt_rsp_source_bank_id_q : 1'b0;
    assign mgmt_rsp_source_bank_generation = mgmt_rsp_valid_q ?
        mgmt_rsp_source_bank_generation_q : 32'd0;
    assign mgmt_rsp_tag = mgmt_rsp_valid_q ? mgmt_rsp_tag_q : 16'd0;
    assign mgmt_rsp_status = mgmt_rsp_valid_q ? mgmt_rsp_status_q : STATUS_OK;

    assign final_close_rsp_valid = final_close_rsp_valid_q;
    assign final_close_rsp_state = final_close_rsp_valid_q ?
                                   final_close_rsp_state_q : ST_EMPTY;
    assign final_close_rsp_generation = final_close_rsp_valid_q ?
                                        final_close_rsp_generation_q : 32'd0;
    assign final_close_rsp_stage_ticket = final_close_rsp_valid_q ?
        final_close_rsp_stage_ticket_q : 32'd0;
    assign final_close_rsp_matrix0_binding_token = final_close_rsp_valid_q ?
        final_close_rsp_binding_token_q : 32'd0;
    assign final_close_rsp_cancellation_epoch = final_close_rsp_valid_q ?
        final_close_rsp_cancellation_epoch_q : 32'd0;
    assign final_close_rsp_tag = final_close_rsp_valid_q ?
                                 final_close_rsp_tag_q : 16'd0;
    assign final_close_rsp_status = final_close_rsp_valid_q ?
                                    final_close_rsp_status_q : STATUS_OK;
    assign final_close_rsp_reset_required = final_close_rsp_valid_q &&
                                            final_close_rsp_reset_required_q;

    assign capture_rsp_valid = capture_rsp_valid_q;
    assign capture_rsp_image_epoch = capture_rsp_valid_q ?
                                     capture_rsp_image_epoch_q : 32'd0;
    assign capture_rsp_stage_id = capture_rsp_valid_q ?
                                  capture_rsp_stage_id_q : 4'd0;
    assign capture_rsp_scratch_generation = capture_rsp_valid_q ?
        capture_rsp_scratch_generation_q : 32'd0;
    assign capture_rsp_stage_ticket = capture_rsp_valid_q ?
                                      capture_rsp_stage_ticket_q : 32'd0;
    assign capture_rsp_logical_branch = capture_rsp_valid_q ?
                                        capture_rsp_logical_branch_q : 2'd0;
    assign capture_rsp_context_generation = capture_rsp_valid_q ?
        capture_rsp_context_generation_q : 32'd0;
    assign capture_rsp_matrix0_binding_token = capture_rsp_valid_q ?
        capture_rsp_binding_token_q : 32'd0;
    assign capture_rsp_cancellation_epoch = capture_rsp_valid_q ?
        capture_rsp_cancellation_epoch_q : 32'd0;
    assign capture_rsp_row_tile = capture_rsp_valid_q ?
                                  capture_rsp_row_tile_q : 6'd0;
    assign capture_rsp_snapshot_taken = capture_rsp_valid_q &&
                                        capture_rsp_snapshot_taken_q;
    assign capture_rsp_committed_lane_mask = capture_rsp_valid_q ?
        capture_rsp_committed_lane_mask_q : 16'd0;
    assign capture_rsp_cumulative_tile_bitmap = capture_rsp_valid_q ?
        capture_rsp_bitmap_q : 20'd0;
    assign capture_rsp_cumulative_entry_count = capture_rsp_valid_q ?
        capture_rsp_count_q : 9'd0;
    assign capture_rsp_source_bank_id = capture_rsp_valid_q ?
                                        capture_rsp_source_bank_id_q : 1'b0;
    assign capture_rsp_source_bank_generation = capture_rsp_valid_q ?
        capture_rsp_source_bank_generation_q : 32'd0;
    assign capture_rsp_tag = capture_rsp_valid_q ? capture_rsp_tag_q : 16'd0;
    assign capture_rsp_status = capture_rsp_valid_q ?
                                capture_rsp_status_q : STATUS_OK;

    assign capture_snapshot_commit = rst_n && capture_success_fire;
    assign capture_snapshot_row_tile = capture_snapshot_commit ?
                                       capture_req_row_tile : 6'd0;
    assign capture_snapshot_scratch_generation = capture_snapshot_commit ?
        capture_req_scratch_generation : 32'd0;
    assign capture_snapshot_stage_ticket = capture_snapshot_commit ?
        capture_req_stage_ticket : 32'd0;
    assign capture_snapshot_context_generation = capture_snapshot_commit ?
        capture_req_context_generation : 32'd0;
    assign capture_snapshot_matrix0_binding_token = capture_snapshot_commit ?
        capture_req_matrix0_binding_token : 32'd0;
    assign capture_snapshot_tag = capture_snapshot_commit ?
                                  capture_req_tag : 16'd0;

    assign tile_rsp_valid = tile_rsp_valid_q;
    assign tile_rsp_data = (tile_rsp_valid_q &&
                            (tile_status_q == STATUS_OK)) ?
                           current_tile_data_q : 512'd0;
    assign tile_rsp_complete = tile_rsp_valid_q &&
                               (tile_status_q == STATUS_OK);
    assign tile_rsp_image_epoch = tile_rsp_valid_q ? tile_image_epoch_q : 32'd0;
    assign tile_rsp_stage_id = tile_rsp_valid_q ? tile_stage_id_q : 4'd0;
    assign tile_rsp_scratch_generation = tile_rsp_valid_q ?
        tile_scratch_generation_q : 32'd0;
    assign tile_rsp_logical_branch = tile_rsp_valid_q ?
        tile_logical_branch_q : 2'd0;
    assign tile_rsp_context_generation = tile_rsp_valid_q ?
        tile_context_generation_q : 32'd0;
    assign tile_rsp_cancellation_epoch = tile_rsp_valid_q ?
        tile_cancellation_epoch_q : 32'd0;
    assign tile_rsp_row_tile = tile_rsp_valid_q ? tile_row_tile_q : 6'd0;
    assign tile_rsp_replay_token = tile_rsp_valid_q ?
        tile_replay_token_q : 32'd0;
    assign tile_rsp_use_token = (tile_rsp_valid_q &&
                                 (tile_status_q == STATUS_OK)) ?
                                tile_use_token_q : 32'd0;
    assign tile_rsp_stage_ticket = tile_rsp_valid_q ?
        tile_stage_ticket_q : 32'd0;
    assign tile_rsp_matrix0_binding_token = tile_rsp_valid_q ?
        tile_binding_token_q : 32'd0;
    assign tile_rsp_source_bank_id = tile_rsp_valid_q ?
        tile_source_bank_id_q : 1'b0;
    assign tile_rsp_source_bank_generation = tile_rsp_valid_q ?
        tile_source_bank_generation_q : 32'd0;
    assign tile_rsp_tag = tile_rsp_valid_q ? tile_tag_q : 16'd0;
    assign tile_rsp_status = tile_rsp_valid_q ? tile_status_q : STATUS_OK;

    assign use_tile_valid = use_tile_valid_q;
    assign use_tile_data = use_tile_valid_q ? current_tile_data_q : 512'd0;
    assign use_tile_image_epoch = use_tile_valid_q ? tile_image_epoch_q : 32'd0;
    assign use_tile_stage_id = use_tile_valid_q ? tile_stage_id_q : 4'd0;
    assign use_tile_scratch_generation = use_tile_valid_q ?
        tile_scratch_generation_q : 32'd0;
    assign use_tile_stage_ticket = use_tile_valid_q ?
        tile_stage_ticket_q : 32'd0;
    assign use_tile_logical_branch = use_tile_valid_q ?
        tile_logical_branch_q : 2'd0;
    assign use_tile_context_generation = use_tile_valid_q ?
        tile_context_generation_q : 32'd0;
    assign use_tile_matrix0_binding_token = use_tile_valid_q ?
        tile_binding_token_q : 32'd0;
    assign use_tile_cancellation_epoch = use_tile_valid_q ?
        tile_cancellation_epoch_q : 32'd0;
    assign use_tile_source_bank_id = use_tile_valid_q ?
        tile_source_bank_id_q : 1'b0;
    assign use_tile_source_bank_generation = use_tile_valid_q ?
        tile_source_bank_generation_q : 32'd0;
    assign use_tile_row_tile = use_tile_valid_q ? tile_row_tile_q : 6'd0;
    assign use_tile_replay_token = use_tile_valid_q ?
        tile_replay_token_q : 32'd0;
    assign use_tile_token = use_tile_valid_q ? tile_use_token_q : 32'd0;

    assign use_release_rsp_valid = use_release_rsp_valid_q;
    assign use_release_rsp_image_epoch = use_release_rsp_valid_q ?
        use_release_rsp_image_epoch_q : 32'd0;
    assign use_release_rsp_stage_id = use_release_rsp_valid_q ?
        use_release_rsp_stage_id_q : 4'd0;
    assign use_release_rsp_scratch_generation = use_release_rsp_valid_q ?
        use_release_rsp_scratch_generation_q : 32'd0;
    assign use_release_rsp_stage_ticket = use_release_rsp_valid_q ?
        use_release_rsp_stage_ticket_q : 32'd0;
    assign use_release_rsp_logical_branch = use_release_rsp_valid_q ?
        use_release_rsp_logical_branch_q : 2'd0;
    assign use_release_rsp_context_generation = use_release_rsp_valid_q ?
        use_release_rsp_context_generation_q : 32'd0;
    assign use_release_rsp_matrix0_binding_token = use_release_rsp_valid_q ?
        use_release_rsp_binding_token_q : 32'd0;
    assign use_release_rsp_cancellation_epoch = use_release_rsp_valid_q ?
        use_release_rsp_cancellation_epoch_q : 32'd0;
    assign use_release_rsp_row_tile = use_release_rsp_valid_q ?
        use_release_rsp_row_tile_q : 6'd0;
    assign use_release_rsp_replay_token = use_release_rsp_valid_q ?
        use_release_rsp_replay_token_q : 32'd0;
    assign use_release_rsp_use_token = use_release_rsp_valid_q ?
        use_release_rsp_use_token_q : 32'd0;
    assign use_release_rsp_tag = use_release_rsp_valid_q ?
        use_release_rsp_tag_q : 16'd0;
    assign use_release_rsp_status = use_release_rsp_valid_q ?
        use_release_rsp_status_q : STATUS_OK;

    assign local_error_valid = local_error_valid_q;
    assign local_error_code = local_error_valid_q ? local_error_code_q : 8'd0;
    assign local_error_source = local_error_valid_q ?
                                local_error_source_q : 3'd0;
    assign local_error_detail = local_error_valid_q ?
                                local_error_detail_q : 32'd0;
    assign local_error_image_epoch = local_error_valid_q ?
        local_error_image_epoch_q : 32'd0;
    assign local_error_stage_id = local_error_valid_q ?
        local_error_stage_id_q : 4'd0;
    assign local_error_scratch_generation = local_error_valid_q ?
        local_error_scratch_generation_q : 32'd0;
    assign local_error_stage_ticket = local_error_valid_q ?
        local_error_stage_ticket_q : 32'd0;
    assign local_error_logical_branch = local_error_valid_q ?
        local_error_logical_branch_q : 2'd0;
    assign local_error_context_generation = local_error_valid_q ?
        local_error_context_generation_q : 32'd0;
    assign local_error_matrix0_binding_token = local_error_valid_q ?
        local_error_binding_token_q : 32'd0;
    assign local_error_source_bank_id = local_error_valid_q ?
        local_error_source_bank_id_q : 1'b0;
    assign local_error_source_bank_generation = local_error_valid_q ?
        local_error_source_bank_generation_q : 32'd0;
    assign local_error_object_cancellation_epoch = local_error_valid_q ?
        local_error_object_cancellation_epoch_q : 32'd0;
    assign local_error_stop_cancellation_epoch = local_error_valid_q ?
        local_error_stop_cancellation_epoch_q : 32'd0;
    assign local_error_offender_tag = local_error_valid_q ?
        local_error_offender_tag_q : 16'd0;
    assign local_error_offender_row_tile = local_error_valid_q ?
        local_error_offender_row_tile_q : 6'd0;
    assign first_overflow_valid = first_overflow_valid_q;
    assign first_overflow_row_tile = first_overflow_valid_q ?
        first_overflow_row_tile_q : 6'd0;
    assign first_overflow_lane = first_overflow_valid_q ?
        first_overflow_lane_q : 4'd0;
    assign first_overflow_mask = first_overflow_valid_q ?
        first_overflow_mask_q : 16'd0;

    assign mgmt_rsp_fire = mgmt_rsp_valid_q && mgmt_rsp_ready;
    assign capture_rsp_fire = capture_rsp_valid_q && capture_rsp_ready;
    assign tile_rsp_fire = tile_rsp_valid_q && tile_rsp_ready;
    assign use_release_rsp_fire = use_release_rsp_valid_q &&
                                  use_release_rsp_ready;
    assign final_close_rsp_fire = final_close_rsp_valid_q &&
                                  final_close_rsp_ready;
    assign capture_rsp_can_take = !capture_rsp_valid_q || capture_rsp_fire;

    // Strict ascending capture order makes the committed-entry baseline a
    // cheap shift, avoiding a 20-input bitmap popcount in the global
    // fault/ready cone.  Full bitmap agreement is still checked at final
    // capture commit, publication, and early-retire evidence.
    assign strict_order_entry_count =
        {next_expected_tile_q[4:0], 4'b0000};
    assign internal_state_fault = (scratch_state_q == 3'd6) ||
        (scratch_state_q == 3'd7) ||
        (committed_entry_count_q > 9'd320) ||
        ((!scratch_generation_initialized_q) &&
         (scratch_generation_q != 32'd0)) ||
        (scratch_generation_initialized_q &&
         (scratch_generation_q == 32'd0)) ||
        (capture_exec_terminal_q && !capture_exec_valid_q) ||
        (pack_busy_q && !tile_slot_valid_q) ||
        (tile_rsp_valid_q && !tile_slot_valid_q) ||
        (use_tile_valid_q && !tile_slot_valid_q) ||
        (pack_busy_q && (tile_rsp_valid_q || use_tile_valid_q)) ||
        (tile_rsp_valid_q && use_tile_valid_q) ||
        (((scratch_state_q == ST_FILLING) ||
          (scratch_state_q == ST_COMPLETE) ||
          (scratch_state_q == ST_VALID) ||
          (scratch_state_q == ST_IN_USE)) && !scratch_owner_valid_q) ||
        (!capture_exec_valid_q &&
         (committed_entry_count_q != strict_order_entry_count)) ||
        (capture_exec_valid_q && !capture_exec_terminal_q &&
         ((capture_exec_row_tile_q >= 6'd20) ||
          (capture_exec_row_tile_q != next_expected_tile_q) ||
          (capture_committed_mask_q !=
           ((16'h0001 << capture_lane_q) - 1'b1)) ||
          (committed_entry_count_q !=
           (strict_order_entry_count + {5'd0, capture_lane_q})))) ||
        (capture_exec_valid_q && capture_exec_terminal_q &&
         (((capture_exec_snapshot_taken_q) &&
           ((capture_committed_mask_q != 16'hffff) ||
            (capture_exec_bitmap_q != committed_tile_bitmap_q) ||
            (capture_exec_count_q != committed_entry_count_q))) ||
          ((!capture_exec_snapshot_taken_q) &&
           ((capture_committed_mask_q != 16'h0000) ||
            (capture_exec_bitmap_q != committed_tile_bitmap_q) ||
            (capture_exec_count_q != committed_entry_count_q))))) ||
        ((replayed_tile_bitmap_q & ~committed_tile_bitmap_q) != 20'd0) ||
        ((pack_busy_q ||
          (tile_rsp_valid_q && (tile_status_q == STATUS_OK)) ||
          use_tile_valid_q) && (tile_use_token_q == 32'd0)) ||
        ((scratch_state_q == ST_IN_USE) && !tile_slot_valid_q &&
         !teardown_pending_q && !fault_pending_q && !close_pending_q &&
         !mgmt_pending_q) ||
        (capture_write_fire &&
         (pack_busy_q ||
          (tile_req_valid && (tile_accept_status == STATUS_OK))));

    // Consolidated observation point for focused invariant verification.
    // Functional controls below deliberately use the raw and registered
    // terms separately so synthesis cannot rebuild a raw-to-reclamation path.
    assign internal_fault_active = internal_state_fault ||
                                   internal_fault_record_valid_q;

    always @* begin
        if ((scratch_state_q == 3'd6) || (scratch_state_q == 3'd7))
            internal_fault_subtype = 11'h001;
        else if (committed_entry_count_q > 9'd320)
            internal_fault_subtype = 11'h002;
        else if (capture_exec_terminal_q && !capture_exec_valid_q)
            internal_fault_subtype = 11'h003;
        else if (capture_exec_valid_q && !capture_exec_terminal_q &&
                 ((capture_exec_row_tile_q >= 6'd20) ||
                  (capture_exec_row_tile_q != next_expected_tile_q) ||
                  (capture_committed_mask_q !=
                   ((16'h0001 << capture_lane_q) - 1'b1))))
            internal_fault_subtype = 11'h004;
        else if ((!capture_exec_valid_q &&
                  (committed_entry_count_q != strict_order_entry_count)) ||
                 (committed_entry_count_q > 9'd320) ||
                 (capture_exec_valid_q && !capture_exec_terminal_q &&
                  (committed_entry_count_q !=
                   (strict_order_entry_count +
                    {5'd0, capture_lane_q}))))
            internal_fault_subtype = 11'h005;
        else if ((replayed_tile_bitmap_q &
                  ~committed_tile_bitmap_q) != 20'd0)
            internal_fault_subtype = 11'h006;
        else if (capture_write_fire &&
                 (pack_busy_q ||
                  (tile_req_valid &&
                   (tile_accept_status == STATUS_OK))))
            internal_fault_subtype = 11'h007;
        else if ((pack_busy_q && !tile_slot_valid_q) ||
                 (pack_busy_q &&
                  (tile_rsp_valid_q || use_tile_valid_q)))
            internal_fault_subtype = 11'h008;
        else if ((tile_rsp_valid_q && !tile_slot_valid_q) ||
                 (capture_exec_terminal_q && !capture_exec_valid_q) ||
                 (capture_exec_valid_q && capture_exec_terminal_q &&
                  (((capture_exec_snapshot_taken_q) &&
                    ((capture_committed_mask_q != 16'hffff) ||
                     (capture_exec_bitmap_q != committed_tile_bitmap_q) ||
                     (capture_exec_count_q != committed_entry_count_q))) ||
                   ((!capture_exec_snapshot_taken_q) &&
                    ((capture_committed_mask_q != 16'h0000) ||
                     (capture_exec_bitmap_q != committed_tile_bitmap_q) ||
                     (capture_exec_count_q != committed_entry_count_q))))))
            internal_fault_subtype = 11'h009;
        else if ((use_tile_valid_q && !tile_slot_valid_q) ||
                 (tile_rsp_valid_q && use_tile_valid_q) ||
                 ((pack_busy_q ||
                   (tile_rsp_valid_q &&
                    (tile_status_q == STATUS_OK)) || use_tile_valid_q) &&
                  (tile_use_token_q == 32'd0)) ||
                 ((scratch_state_q == ST_IN_USE) &&
                  !tile_slot_valid_q && !teardown_pending_q &&
                  !fault_pending_q && !close_pending_q && !mgmt_pending_q))
            internal_fault_subtype = 11'h00a;
        else if (((scratch_state_q == ST_FILLING) ||
                  (scratch_state_q == ST_COMPLETE) ||
                  (scratch_state_q == ST_VALID) ||
                  (scratch_state_q == ST_IN_USE)) &&
                 !scratch_owner_valid_q)
            internal_fault_subtype = 11'h00b;
        else
            internal_fault_subtype = 11'h00c;
    end

    assign causal_drain_complete = !capture_exec_valid_q &&
        !capture_rsp_valid_q && !tile_slot_valid_q &&
        !use_release_rsp_valid_q && !mgmt_rsp_valid_q;

    assign tile_slot_clears_this_edge =
        (tile_rsp_fire && (tile_status_q != STATUS_OK)) ||
        use_release_exact_fire ||
        (tile_rsp_fire && (tile_status_q == STATUS_OK) &&
         ((close_pending_q && close_data_untrusted_q) ||
          (final_close_install_fire &&
           final_close_req_data_untrusted)));

    assign causal_drain_after_retire =
        !capture_exec_valid_q &&
        (!capture_rsp_valid_q || capture_rsp_fire) &&
        (!tile_slot_valid_q || tile_slot_clears_this_edge) &&
        !use_release_req_fire &&
        (!use_release_rsp_valid_q || use_release_rsp_fire) &&
        (!mgmt_rsp_valid_q || mgmt_rsp_fire);

    assign local_quiescent = causal_drain_complete &&
        !mgmt_pending_q && !close_pending_q &&
        !final_close_rsp_valid_q && !fault_pending_q &&
        !teardown_pending_q && !internal_fault_record_valid_q;

    assign early_retire_evidence_valid =
        (scratch_state_q == ST_VALID) && scratch_owner_valid_q &&
        (committed_tile_bitmap_q == 20'hfffff) &&
        (committed_entry_count_q == 9'd320) &&
        (replayed_tile_bitmap_q == 20'd0) &&
        (scratch_source_bank_generation_q != 32'd0) &&
        local_quiescent && !local_error_valid_q && !reset_required_q &&
        !internal_state_fault && !internal_fault_record_valid_q;

    assign release_identity_exact = use_tile_valid_q &&
        (use_release_req_image_epoch == tile_image_epoch_q) &&
        (use_release_req_stage_id == tile_stage_id_q) &&
        (use_release_req_scratch_generation == tile_scratch_generation_q) &&
        (use_release_req_stage_ticket == tile_stage_ticket_q) &&
        (use_release_req_logical_branch == tile_logical_branch_q) &&
        (use_release_req_context_generation == tile_context_generation_q) &&
        (use_release_req_matrix0_binding_token == tile_binding_token_q) &&
        (use_release_req_cancellation_epoch == tile_cancellation_epoch_q) &&
        (use_release_req_row_tile == tile_row_tile_q) &&
        (use_release_req_replay_token == tile_replay_token_q) &&
        (use_release_req_use_token == tile_use_token_q);

    assign duplicate_release_exact = scratch_owner_valid_q &&
        (use_release_req_image_epoch == scratch_image_epoch_q) &&
        (use_release_req_stage_id == scratch_stage_id_q) &&
        (use_release_req_scratch_generation == scratch_generation_q) &&
        (use_release_req_stage_ticket == scratch_stage_ticket_q) &&
        (use_release_req_logical_branch == scratch_logical_branch_q) &&
        (use_release_req_context_generation == scratch_context_generation_q) &&
        (use_release_req_matrix0_binding_token ==
         scratch_matrix0_binding_token_q) &&
        (use_release_req_cancellation_epoch ==
         scratch_cancellation_epoch_q) &&
        (use_release_req_row_tile < 6'd20) &&
        replayed_tile_bitmap_q[use_release_req_row_tile];

    assign final_close_candidate = final_close_req_valid &&
        !close_pending_q && !final_close_rsp_valid_q && !fault_pending_q;
    assign final_close_req_ready = rst_n && !internal_state_fault &&
        !internal_fault_record_valid_q &&
        !close_pending_q && !final_close_rsp_valid_q && !fault_pending_q;
    assign final_close_fire = final_close_candidate &&
                              final_close_req_ready;
    assign final_close_install_fire = final_close_fire &&
                                      (close_accept_status == STATUS_OK);

    // One new external admission per edge.  A higher-priority asserted
    // candidate is never bypassed merely because its local slot is occupied.
    assign use_release_req_ready = rst_n &&
        !final_close_candidate && !use_release_rsp_valid_q &&
        !final_close_rsp_valid_q &&
        ((!internal_state_fault && !internal_fault_record_valid_q &&
          !fault_pending_q && !close_pending_q && !teardown_pending_q &&
          (scratch_state_q != ST_ERROR)) ||
         (((fault_pending_q || close_pending_q || teardown_pending_q ||
            internal_fault_record_valid_q) && release_identity_exact) &&
          (!internal_state_fault || internal_fault_record_valid_q)));

    assign mgmt_req_ready = rst_n && !internal_state_fault &&
        !internal_fault_record_valid_q &&
        !final_close_candidate && !use_release_req_valid &&
        !mgmt_rsp_valid_q && !mgmt_pending_q &&
        !final_close_rsp_valid_q &&
        !fault_pending_q && !close_pending_q && !teardown_pending_q;

    assign capture_req_ready = rst_n && !internal_state_fault &&
        !internal_fault_record_valid_q &&
        !final_close_candidate && !use_release_req_valid &&
        !mgmt_req_valid && !mgmt_rsp_valid_q && !mgmt_pending_q &&
        !final_close_rsp_valid_q &&
        !fault_pending_q && !close_pending_q && !teardown_pending_q &&
        !capture_exec_valid_q && (scratch_state_q != ST_ERROR);

    assign tile_req_ready = rst_n && !internal_state_fault &&
        !internal_fault_record_valid_q &&
        !final_close_candidate && !use_release_req_valid &&
        !mgmt_req_valid && !capture_req_valid &&
        !mgmt_rsp_valid_q && !mgmt_pending_q &&
        !final_close_rsp_valid_q &&
        !fault_pending_q && !close_pending_q && !teardown_pending_q &&
        !tile_slot_valid_q && !use_release_rsp_valid_q &&
        (scratch_state_q != ST_IN_USE) && (scratch_state_q != ST_ERROR);

    assign mgmt_req_fire = mgmt_req_valid && mgmt_req_ready;
    assign capture_req_fire = capture_req_valid && capture_req_ready;
    assign capture_success_fire = capture_req_fire &&
                                  (capture_accept_status == STATUS_OK);
    assign capture_poison_fire = capture_req_fire && capture_accept_poison;
    assign tile_req_fire = tile_req_valid && tile_req_ready;
    assign tile_success_fire = tile_req_fire &&
                               (tile_accept_status == STATUS_OK);
    assign use_release_req_fire = use_release_req_valid &&
                                  use_release_req_ready;
    assign use_release_exact_fire = use_release_req_fire &&
                                    use_release_accept_exact;

    assign stop_pending = close_pending_q || fault_pending_q;
    assign selected_stop_code =
        (close_pending_q && (close_code_q != STATUS_ERR_ABORTED)) ?
            close_code_q :
        (fault_pending_q && (fault_code_q != STATUS_OK)) ?
            fault_code_q : close_code_q;

    assign capture_write_fire = rst_n && capture_exec_valid_q &&
                                !capture_exec_terminal_q;
    assign capture_write_addr =
        {capture_exec_row_tile_q[4:0], capture_lane_q};
    assign capture_write_data =
        capture_data_q[capture_lane_q*32 +: 32];

    assign ram_read_fire = tile_success_fire ||
                           (pack_busy_q && (pack_lane_q != 4'd15));
    assign ram_read_addr = tile_success_fire ?
        {tile_req_row_tile[4:0], 4'd0} :
        {tile_row_tile_q[4:0], (pack_lane_q + 1'b1)};

    // Canonical single-port synchronous RAM.  No reset branch is permitted.
    always @(posedge clk) begin
        if (capture_write_fire)
            raw_mem[capture_write_addr] <= capture_write_data;
        else if (ram_read_fire)
            ram_read_data_q <= raw_mem[ram_read_addr];
    end

    assign release_last_tile_ok =
        (scratch_state_q == ST_VALID) ?
            (replayed_tile_bitmap_q == 20'hfffff) :
        (scratch_state_q == ST_IN_USE) ?
            (use_tile_valid_q &&
             ((replayed_tile_bitmap_q |
               (20'b1 << tile_row_tile_q)) == 20'hfffff)) : 1'b0;

    // Direct operation outcomes drive lifecycle mutations.  The priority-
    // encoded 8-bit status below is intentionally confined to response data;
    // decoding it back into enables would put every identity comparator on a
    // long, high-fanout clear/load path.
    assign mgmt_allocate_ok =
        (mgmt_req_opcode == MGMT_ALLOCATE) &&
        (scratch_state_q == ST_EMPTY) && local_quiescent &&
        !local_error_valid_q && !reset_required_q &&
        (mgmt_req_scratch_generation == scratch_generation_q) &&
        (mgmt_req_stage_id == 4'd1) &&
        (mgmt_req_stage_ticket != 32'd0) &&
        (mgmt_req_matrix0_binding_token != 32'd0) &&
        (mgmt_req_source_bank_generation != 32'd0) &&
        (mgmt_req_expected_tile_count == 6'd20) &&
        (mgmt_req_expected_lane_mask == 16'hffff) &&
        mgmt_req_external_safe;

    assign mgmt_publish_ok =
        (mgmt_req_opcode == MGMT_PUBLISH_VALID) &&
        (scratch_state_q == ST_COMPLETE) &&
        (mgmt_req_scratch_generation == scratch_generation_q) &&
        (mgmt_req_image_epoch == scratch_image_epoch_q) &&
        (mgmt_req_stage_id == scratch_stage_id_q) &&
        (mgmt_req_stage_ticket == scratch_stage_ticket_q) &&
        (mgmt_req_logical_branch == scratch_logical_branch_q) &&
        (mgmt_req_context_generation == scratch_context_generation_q) &&
        (mgmt_req_matrix0_binding_token ==
         scratch_matrix0_binding_token_q) &&
        (mgmt_req_source_bank_id == scratch_source_bank_id_q) &&
        (mgmt_req_source_bank_generation ==
         scratch_source_bank_generation_q) &&
        (mgmt_req_cancellation_epoch == scratch_cancellation_epoch_q) &&
        (mgmt_req_expected_tile_count == 6'd20) &&
        (mgmt_req_expected_lane_mask == 16'hffff) &&
        (committed_tile_bitmap_q == 20'hfffff) &&
        (committed_entry_count_q == 9'd320) &&
        !capture_exec_valid_q && !capture_rsp_valid_q &&
        !tile_slot_valid_q && !use_release_rsp_valid_q &&
        !local_error_valid_q && !reset_required_q &&
        mgmt_req_external_safe;

    assign mgmt_release_ok =
        (mgmt_req_opcode == MGMT_RELEASE_OBJECT) &&
        ((scratch_state_q == ST_VALID) ||
         (scratch_state_q == ST_IN_USE)) &&
        (mgmt_req_scratch_generation == scratch_generation_q) &&
        (mgmt_req_image_epoch == scratch_image_epoch_q) &&
        (mgmt_req_stage_id == scratch_stage_id_q) &&
        (mgmt_req_stage_ticket == scratch_stage_ticket_q) &&
        (mgmt_req_logical_branch == scratch_logical_branch_q) &&
        (mgmt_req_context_generation == scratch_context_generation_q) &&
        (mgmt_req_matrix0_binding_token ==
         scratch_matrix0_binding_token_q) &&
        (mgmt_req_source_bank_id == scratch_source_bank_id_q) &&
        (mgmt_req_source_bank_generation ==
         scratch_source_bank_generation_q) &&
        (mgmt_req_cancellation_epoch == scratch_cancellation_epoch_q) &&
        release_last_tile_ok && mgmt_req_external_safe &&
        (scratch_generation_q != 32'hffff_ffff);

    assign mgmt_release_generation_exhausted =
        (mgmt_req_opcode == MGMT_RELEASE_OBJECT) &&
        ((scratch_state_q == ST_VALID) ||
         (scratch_state_q == ST_IN_USE)) &&
        (mgmt_req_scratch_generation == scratch_generation_q) &&
        (mgmt_req_image_epoch == scratch_image_epoch_q) &&
        (mgmt_req_stage_id == scratch_stage_id_q) &&
        (mgmt_req_stage_ticket == scratch_stage_ticket_q) &&
        (mgmt_req_logical_branch == scratch_logical_branch_q) &&
        (mgmt_req_context_generation == scratch_context_generation_q) &&
        (mgmt_req_matrix0_binding_token ==
         scratch_matrix0_binding_token_q) &&
        (mgmt_req_source_bank_id == scratch_source_bank_id_q) &&
        (mgmt_req_source_bank_generation ==
         scratch_source_bank_generation_q) &&
        (mgmt_req_cancellation_epoch == scratch_cancellation_epoch_q) &&
        release_last_tile_ok && mgmt_req_external_safe &&
        (scratch_generation_q == 32'hffff_ffff);

    assign mgmt_clear_ok =
        (mgmt_req_opcode == MGMT_CLEAR_ERROR) &&
        (scratch_state_q == ST_ERROR) && local_error_valid_q &&
        (mgmt_req_scratch_generation ==
         local_error_scratch_generation_q) &&
        (mgmt_req_image_epoch == local_error_image_epoch_q) &&
        (mgmt_req_stage_id == local_error_stage_id_q) &&
        (mgmt_req_stage_ticket == local_error_stage_ticket_q) &&
        (mgmt_req_logical_branch == local_error_logical_branch_q) &&
        (mgmt_req_context_generation ==
         local_error_context_generation_q) &&
        (mgmt_req_matrix0_binding_token == local_error_binding_token_q) &&
        (mgmt_req_source_bank_id == local_error_source_bank_id_q) &&
        (mgmt_req_source_bank_generation ==
         local_error_source_bank_generation_q) &&
        (mgmt_req_cancellation_epoch ==
         local_error_object_cancellation_epoch_q) &&
        (scratch_generation_q != 32'hffff_ffff) &&
        !reset_required_q && local_quiescent && mgmt_req_external_safe;

    assign mgmt_clear_generation_exhausted =
        (mgmt_req_opcode == MGMT_CLEAR_ERROR) &&
        (scratch_state_q == ST_ERROR) && local_error_valid_q &&
        (mgmt_req_scratch_generation ==
         local_error_scratch_generation_q) &&
        (mgmt_req_image_epoch == local_error_image_epoch_q) &&
        (mgmt_req_stage_id == local_error_stage_id_q) &&
        (mgmt_req_stage_ticket == local_error_stage_ticket_q) &&
        (mgmt_req_logical_branch == local_error_logical_branch_q) &&
        (mgmt_req_context_generation ==
         local_error_context_generation_q) &&
        (mgmt_req_matrix0_binding_token == local_error_binding_token_q) &&
        (mgmt_req_source_bank_id == local_error_source_bank_id_q) &&
        (mgmt_req_source_bank_generation ==
         local_error_source_bank_generation_q) &&
        (mgmt_req_cancellation_epoch ==
         local_error_object_cancellation_epoch_q) &&
        (scratch_generation_q == 32'hffff_ffff);

    // Management error selection follows the field order frozen in Phase A.
    always @* begin
        mgmt_accept_status = STATUS_OK;
        if (mgmt_req_opcode > MGMT_CLEAR_ERROR) begin
            mgmt_accept_status = STATUS_ERR_BAD_OPCODE;
        end else begin
            case (mgmt_req_opcode)
                MGMT_ALLOCATE: begin
                    if (scratch_state_q != ST_EMPTY)
                        mgmt_accept_status = STATUS_ERR_WRONG_STATE;
                    else if (!local_quiescent)
                        mgmt_accept_status = STATUS_ERR_NOT_QUIESCENT;
                    else if (local_error_valid_q || reset_required_q)
                        mgmt_accept_status = STATUS_ERR_LOCAL_PROTOCOL;
                    else if (mgmt_req_scratch_generation !=
                             scratch_generation_q)
                        mgmt_accept_status = STATUS_ERR_STALE_GENERATION;
                    else if (mgmt_req_stage_id != 4'd1)
                        mgmt_accept_status = STATUS_ERR_OWNER_MISMATCH;
                    else if (mgmt_req_stage_ticket == 32'd0)
                        mgmt_accept_status =
                            STATUS_ERR_STAGE_TICKET_MISMATCH;
                    else if (mgmt_req_matrix0_binding_token == 32'd0)
                        mgmt_accept_status = STATUS_ERR_BINDING_MISMATCH;
                    else if (mgmt_req_source_bank_generation == 32'd0)
                        mgmt_accept_status =
                            STATUS_ERR_SOURCE_BANK_MISMATCH;
                    else if ((mgmt_req_expected_tile_count != 6'd20) ||
                             (mgmt_req_expected_lane_mask != 16'hffff))
                        mgmt_accept_status = STATUS_ERR_LOCAL_PROTOCOL;
                    else if (!mgmt_req_external_safe)
                        mgmt_accept_status = STATUS_ERR_EXTERNAL_UNSAFE;
                end

                MGMT_PUBLISH_VALID: begin
                    if (scratch_state_q != ST_COMPLETE)
                        mgmt_accept_status = STATUS_ERR_WRONG_STATE;
                    else if (mgmt_req_scratch_generation !=
                             scratch_generation_q)
                        mgmt_accept_status = STATUS_ERR_STALE_GENERATION;
                    else if (mgmt_req_image_epoch != scratch_image_epoch_q)
                        mgmt_accept_status =
                            STATUS_ERR_IMAGE_EPOCH_MISMATCH;
                    else if (mgmt_req_stage_id != scratch_stage_id_q)
                        mgmt_accept_status = STATUS_ERR_OWNER_MISMATCH;
                    else if (mgmt_req_stage_ticket != scratch_stage_ticket_q)
                        mgmt_accept_status =
                            STATUS_ERR_STAGE_TICKET_MISMATCH;
                    else if (mgmt_req_logical_branch !=
                             scratch_logical_branch_q)
                        mgmt_accept_status = STATUS_ERR_BRANCH_MISMATCH;
                    else if (mgmt_req_context_generation !=
                             scratch_context_generation_q)
                        mgmt_accept_status = STATUS_ERR_CONTEXT_MISMATCH;
                    else if (mgmt_req_matrix0_binding_token !=
                             scratch_matrix0_binding_token_q)
                        mgmt_accept_status = STATUS_ERR_BINDING_MISMATCH;
                    else if ((mgmt_req_source_bank_id !=
                              scratch_source_bank_id_q) ||
                             (mgmt_req_source_bank_generation !=
                              scratch_source_bank_generation_q))
                        mgmt_accept_status =
                            STATUS_ERR_SOURCE_BANK_MISMATCH;
                    else if (mgmt_req_cancellation_epoch !=
                             scratch_cancellation_epoch_q)
                        mgmt_accept_status =
                            STATUS_ERR_CANCELLATION_EPOCH;
                    else if ((mgmt_req_expected_tile_count != 6'd20) ||
                             (mgmt_req_expected_lane_mask != 16'hffff))
                        mgmt_accept_status = STATUS_ERR_LOCAL_PROTOCOL;
                    else if ((committed_tile_bitmap_q != 20'hfffff) ||
                             (committed_entry_count_q != 9'd320))
                        mgmt_accept_status = STATUS_ERR_NOT_COMPLETE;
                    else if (capture_exec_valid_q || capture_rsp_valid_q ||
                             tile_slot_valid_q || use_release_rsp_valid_q)
                        mgmt_accept_status = STATUS_ERR_NOT_QUIESCENT;
                    else if (local_error_valid_q || reset_required_q)
                        mgmt_accept_status = STATUS_ERR_LOCAL_PROTOCOL;
                    else if (!mgmt_req_external_safe)
                        mgmt_accept_status = STATUS_ERR_EXTERNAL_UNSAFE;
                end

                MGMT_RELEASE_OBJECT: begin
                    if ((scratch_state_q != ST_VALID) &&
                        (scratch_state_q != ST_IN_USE))
                        mgmt_accept_status = STATUS_ERR_WRONG_STATE;
                    else if (mgmt_req_scratch_generation !=
                             scratch_generation_q)
                        mgmt_accept_status = STATUS_ERR_STALE_GENERATION;
                    else if (mgmt_req_image_epoch != scratch_image_epoch_q)
                        mgmt_accept_status =
                            STATUS_ERR_IMAGE_EPOCH_MISMATCH;
                    else if (mgmt_req_stage_id != scratch_stage_id_q)
                        mgmt_accept_status = STATUS_ERR_OWNER_MISMATCH;
                    else if (mgmt_req_stage_ticket != scratch_stage_ticket_q)
                        mgmt_accept_status =
                            STATUS_ERR_STAGE_TICKET_MISMATCH;
                    else if (mgmt_req_logical_branch !=
                             scratch_logical_branch_q)
                        mgmt_accept_status = STATUS_ERR_BRANCH_MISMATCH;
                    else if (mgmt_req_context_generation !=
                             scratch_context_generation_q)
                        mgmt_accept_status = STATUS_ERR_CONTEXT_MISMATCH;
                    else if (mgmt_req_matrix0_binding_token !=
                             scratch_matrix0_binding_token_q)
                        mgmt_accept_status = STATUS_ERR_BINDING_MISMATCH;
                    else if ((mgmt_req_source_bank_id !=
                              scratch_source_bank_id_q) ||
                             (mgmt_req_source_bank_generation !=
                              scratch_source_bank_generation_q))
                        mgmt_accept_status =
                            STATUS_ERR_SOURCE_BANK_MISMATCH;
                    else if (mgmt_req_cancellation_epoch !=
                             scratch_cancellation_epoch_q)
                        mgmt_accept_status =
                            STATUS_ERR_CANCELLATION_EPOCH;
                    else if (!release_last_tile_ok)
                        mgmt_accept_status = STATUS_ERR_NOT_COMPLETE;
                    else if (!mgmt_req_external_safe)
                        mgmt_accept_status = STATUS_ERR_EXTERNAL_UNSAFE;
                    else if (scratch_generation_q == 32'hffff_ffff)
                        mgmt_accept_status =
                            STATUS_ERR_GENERATION_EXHAUSTED;
                end

                MGMT_CLEAR_ERROR: begin
                    if (scratch_state_q != ST_ERROR)
                        mgmt_accept_status = STATUS_ERR_WRONG_STATE;
                    else if (mgmt_req_scratch_generation !=
                             local_error_scratch_generation_q)
                        mgmt_accept_status = STATUS_ERR_STALE_GENERATION;
                    else if (mgmt_req_image_epoch !=
                             local_error_image_epoch_q)
                        mgmt_accept_status =
                            STATUS_ERR_IMAGE_EPOCH_MISMATCH;
                    else if (mgmt_req_stage_id != local_error_stage_id_q)
                        mgmt_accept_status = STATUS_ERR_OWNER_MISMATCH;
                    else if (mgmt_req_stage_ticket !=
                             local_error_stage_ticket_q)
                        mgmt_accept_status =
                            STATUS_ERR_STAGE_TICKET_MISMATCH;
                    else if (mgmt_req_logical_branch !=
                             local_error_logical_branch_q)
                        mgmt_accept_status = STATUS_ERR_BRANCH_MISMATCH;
                    else if (mgmt_req_context_generation !=
                             local_error_context_generation_q)
                        mgmt_accept_status = STATUS_ERR_CONTEXT_MISMATCH;
                    else if (mgmt_req_matrix0_binding_token !=
                             local_error_binding_token_q)
                        mgmt_accept_status = STATUS_ERR_BINDING_MISMATCH;
                    else if ((mgmt_req_source_bank_id !=
                              local_error_source_bank_id_q) ||
                             (mgmt_req_source_bank_generation !=
                              local_error_source_bank_generation_q))
                        mgmt_accept_status =
                            STATUS_ERR_SOURCE_BANK_MISMATCH;
                    else if (mgmt_req_cancellation_epoch !=
                             local_error_object_cancellation_epoch_q)
                        mgmt_accept_status =
                            STATUS_ERR_CANCELLATION_EPOCH;
                    else if (scratch_generation_q == 32'hffff_ffff)
                        mgmt_accept_status =
                            STATUS_ERR_GENERATION_EXHAUSTED;
                    else if (reset_required_q)
                        mgmt_accept_status = STATUS_ERR_LOCAL_PROTOCOL;
                    else if (!local_quiescent)
                        mgmt_accept_status = STATUS_ERR_NOT_QUIESCENT;
                    else if (!mgmt_req_external_safe)
                        mgmt_accept_status = STATUS_ERR_EXTERNAL_UNSAFE;
                end

                default: mgmt_accept_status = STATUS_ERR_BAD_OPCODE;
            endcase
        end
    end

    // Capture failures on an existing object are poisonous except for the
    // explicitly retryable PE-stability proof failure.
    always @* begin
        capture_accept_status = STATUS_OK;
        capture_accept_poison = 1'b0;
        capture_accept_overflow = 1'b0;
        if (!scratch_owner_valid_q) begin
            capture_accept_status = STATUS_ERR_WRONG_STATE;
        end else if (capture_req_image_epoch != scratch_image_epoch_q) begin
            capture_accept_status = STATUS_ERR_IMAGE_EPOCH_MISMATCH;
            capture_accept_poison = 1'b1;
        end else if (capture_req_stage_id != scratch_stage_id_q) begin
            capture_accept_status = STATUS_ERR_OWNER_MISMATCH;
            capture_accept_poison = 1'b1;
        end else if (capture_req_stage_ticket != scratch_stage_ticket_q) begin
            capture_accept_status = STATUS_ERR_STAGE_TICKET_MISMATCH;
            capture_accept_poison = 1'b1;
        end else if (capture_req_logical_branch !=
                     scratch_logical_branch_q) begin
            capture_accept_status = STATUS_ERR_BRANCH_MISMATCH;
            capture_accept_poison = 1'b1;
        end else if (capture_req_context_generation !=
                     scratch_context_generation_q) begin
            capture_accept_status = STATUS_ERR_CONTEXT_MISMATCH;
            capture_accept_poison = 1'b1;
        end else if (capture_req_matrix0_binding_token !=
                     scratch_matrix0_binding_token_q) begin
            capture_accept_status = STATUS_ERR_BINDING_MISMATCH;
            capture_accept_poison = 1'b1;
        end else if (capture_req_scratch_generation !=
                     scratch_generation_q) begin
            capture_accept_status = STATUS_ERR_STALE_GENERATION;
            capture_accept_poison = 1'b1;
        end else if (capture_req_cancellation_epoch !=
                     scratch_cancellation_epoch_q) begin
            capture_accept_status = STATUS_ERR_CANCELLATION_EPOCH;
            capture_accept_poison = 1'b1;
        end else if (capture_req_row_tile >= 6'd20) begin
            capture_accept_status = STATUS_ERR_BAD_TILE;
            capture_accept_poison = 1'b1;
        end else if (committed_tile_bitmap_q[capture_req_row_tile]) begin
            capture_accept_status = STATUS_ERR_DUPLICATE_TILE;
            capture_accept_poison = 1'b1;
        end else if (scratch_state_q != ST_FILLING) begin
            capture_accept_status = STATUS_ERR_WRONG_STATE;
            capture_accept_poison = 1'b1;
        end else if (capture_req_row_tile != next_expected_tile_q) begin
            capture_accept_status = STATUS_ERR_CAPTURE_ORDER;
            capture_accept_poison = 1'b1;
        end else if (capture_req_lane_valid != 16'hffff) begin
            capture_accept_status = STATUS_ERR_BAD_LANE_MASK;
            capture_accept_poison = 1'b1;
        end else if (capture_req_overflow != 16'h0000) begin
            capture_accept_status = STATUS_ERR_OVERFLOW;
            capture_accept_poison = 1'b1;
            capture_accept_overflow = 1'b1;
        end else if (!capture_req_pe_snapshot_safe) begin
            capture_accept_status = STATUS_ERR_EXTERNAL_UNSAFE;
        end
    end

    always @* begin
        capture_lowest_lane = 4'd0;
        capture_lowest_missing_lane = 4'd0;
        overflow_lane_found = 1'b0;
        missing_lane_found = 1'b0;
        for (lane_scan = 0; lane_scan < 16; lane_scan = lane_scan + 1) begin
            if (!overflow_lane_found && capture_req_overflow[lane_scan]) begin
                capture_lowest_lane = lane_scan[3:0];
                overflow_lane_found = 1'b1;
            end
            if (!missing_lane_found && !capture_req_lane_valid[lane_scan]) begin
                capture_lowest_missing_lane = lane_scan[3:0];
                missing_lane_found = 1'b1;
            end
        end
    end

    always @* begin
        tile_accept_status = STATUS_OK;
        if (scratch_state_q != ST_VALID)
            tile_accept_status = STATUS_ERR_WRONG_STATE;
        else if (tile_req_scratch_generation != scratch_generation_q)
            tile_accept_status = STATUS_ERR_STALE_GENERATION;
        else if (tile_req_image_epoch != scratch_image_epoch_q)
            tile_accept_status = STATUS_ERR_IMAGE_EPOCH_MISMATCH;
        else if (tile_req_stage_id != scratch_stage_id_q)
            tile_accept_status = STATUS_ERR_OWNER_MISMATCH;
        else if (tile_req_stage_ticket != scratch_stage_ticket_q)
            tile_accept_status = STATUS_ERR_STAGE_TICKET_MISMATCH;
        else if (tile_req_logical_branch != scratch_logical_branch_q)
            tile_accept_status = STATUS_ERR_BRANCH_MISMATCH;
        else if (tile_req_context_generation !=
                 scratch_context_generation_q)
            tile_accept_status = STATUS_ERR_CONTEXT_MISMATCH;
        else if (tile_req_retired_binding_token !=
                 scratch_matrix0_binding_token_q)
            tile_accept_status = STATUS_ERR_BINDING_MISMATCH;
        else if (tile_req_cancellation_epoch !=
                 scratch_cancellation_epoch_q)
            tile_accept_status = STATUS_ERR_CANCELLATION_EPOCH;
        else if (tile_req_row_tile >= 6'd20)
            tile_accept_status = STATUS_ERR_BAD_TILE;
        else if (tile_req_replay_token == 32'd0)
            tile_accept_status = STATUS_ERR_STALE_USE;
        else if (replayed_tile_bitmap_q[tile_req_row_tile])
            tile_accept_status = STATUS_ERR_TILE_ALREADY_USED;
        else if (!tile_req_retired_binding_safe)
            tile_accept_status = STATUS_ERR_EXTERNAL_UNSAFE;
    end

    always @* begin
        use_release_accept_status = STATUS_OK;
        use_release_accept_exact = 1'b0;
        if (!use_tile_valid_q) begin
            if (duplicate_release_exact)
                use_release_accept_status = STATUS_ERR_DUPLICATE_RELEASE;
            else
                use_release_accept_status = STATUS_ERR_STALE_USE;
        end else if (use_release_req_image_epoch != tile_image_epoch_q)
            use_release_accept_status = STATUS_ERR_IMAGE_EPOCH_MISMATCH;
        else if (use_release_req_stage_id != tile_stage_id_q)
            use_release_accept_status = STATUS_ERR_OWNER_MISMATCH;
        else if (use_release_req_scratch_generation !=
                 tile_scratch_generation_q)
            use_release_accept_status = STATUS_ERR_STALE_GENERATION;
        else if (use_release_req_stage_ticket != tile_stage_ticket_q)
            use_release_accept_status = STATUS_ERR_STAGE_TICKET_MISMATCH;
        else if (use_release_req_logical_branch != tile_logical_branch_q)
            use_release_accept_status = STATUS_ERR_BRANCH_MISMATCH;
        else if (use_release_req_context_generation !=
                 tile_context_generation_q)
            use_release_accept_status = STATUS_ERR_CONTEXT_MISMATCH;
        else if (use_release_req_matrix0_binding_token !=
                 tile_binding_token_q)
            use_release_accept_status = STATUS_ERR_BINDING_MISMATCH;
        else if (use_release_req_cancellation_epoch !=
                 tile_cancellation_epoch_q)
            use_release_accept_status = STATUS_ERR_CANCELLATION_EPOCH;
        else if ((use_release_req_row_tile != tile_row_tile_q) ||
                 (use_release_req_replay_token != tile_replay_token_q) ||
                 (use_release_req_use_token != tile_use_token_q))
            use_release_accept_status = STATUS_ERR_STALE_USE;
        else if (!use_release_req_all_input_handshakes_done)
            use_release_accept_status = STATUS_ERR_EXTERNAL_UNSAFE;
        else begin
            use_release_accept_status = STATUS_OK;
            use_release_accept_exact = 1'b1;
        end
    end

    always @* begin
        close_accept_status = STATUS_OK;
        if ((!final_close_req_kind &&
             ((final_close_req_code != STATUS_ERR_ABORTED) ||
              final_close_req_data_untrusted)) ||
            (final_close_req_kind &&
             ((final_close_req_code == STATUS_OK) ||
              (final_close_req_code == STATUS_ERR_ABORTED))))
            close_accept_status = STATUS_ERR_BAD_CLOSE_CODE;
        else if (!final_close_req_causal_producers_drained &&
                 !final_close_req_data_untrusted)
            close_accept_status = STATUS_ERR_EXTERNAL_UNSAFE;
    end

    // Control, lifecycle, serializer/packer ownership, and held responses.
    // capture_data_q and current_tile_data_q are intentionally not reset;
    // their valid/authority state is reset and gates every external use.
    always @(posedge clk) begin
        if (!rst_n) begin
            scratch_state_q <= ST_EMPTY;
            scratch_generation_q <= 32'd0;
            scratch_generation_initialized_q <= 1'b0;
            scratch_owner_valid_q <= 1'b0;
            scratch_image_epoch_q <= 32'd0;
            scratch_stage_id_q <= 4'd0;
            scratch_stage_ticket_q <= 32'd0;
            scratch_logical_branch_q <= 2'd0;
            scratch_context_generation_q <= 32'd0;
            scratch_matrix0_binding_token_q <= 32'd0;
            scratch_source_bank_id_q <= 1'b0;
            scratch_source_bank_generation_q <= 32'd0;
            scratch_cancellation_epoch_q <= 32'd0;
            committed_tile_bitmap_q <= 20'd0;
            committed_entry_count_q <= 9'd0;
            replayed_tile_bitmap_q <= 20'd0;
            next_expected_tile_q <= 6'd0;
            use_token_counter_q <= 32'd0;

            capture_exec_valid_q <= 1'b0;
            capture_exec_terminal_q <= 1'b0;
            capture_lane_q <= 4'd0;
            capture_committed_mask_q <= 16'd0;
            capture_exec_image_epoch_q <= 32'd0;
            capture_exec_stage_id_q <= 4'd0;
            capture_exec_scratch_generation_q <= 32'd0;
            capture_exec_stage_ticket_q <= 32'd0;
            capture_exec_logical_branch_q <= 2'd0;
            capture_exec_context_generation_q <= 32'd0;
            capture_exec_binding_token_q <= 32'd0;
            capture_exec_cancellation_epoch_q <= 32'd0;
            capture_exec_row_tile_q <= 6'd0;
            capture_exec_snapshot_taken_q <= 1'b0;
            capture_exec_bitmap_q <= 20'd0;
            capture_exec_count_q <= 9'd0;
            capture_exec_source_bank_id_q <= 1'b0;
            capture_exec_source_bank_generation_q <= 32'd0;
            capture_exec_tag_q <= 16'd0;
            capture_exec_status_q <= STATUS_OK;

            capture_rsp_valid_q <= 1'b0;
            capture_rsp_image_epoch_q <= 32'd0;
            capture_rsp_stage_id_q <= 4'd0;
            capture_rsp_scratch_generation_q <= 32'd0;
            capture_rsp_stage_ticket_q <= 32'd0;
            capture_rsp_logical_branch_q <= 2'd0;
            capture_rsp_context_generation_q <= 32'd0;
            capture_rsp_binding_token_q <= 32'd0;
            capture_rsp_cancellation_epoch_q <= 32'd0;
            capture_rsp_row_tile_q <= 6'd0;
            capture_rsp_snapshot_taken_q <= 1'b0;
            capture_rsp_committed_lane_mask_q <= 16'd0;
            capture_rsp_bitmap_q <= 20'd0;
            capture_rsp_count_q <= 9'd0;
            capture_rsp_source_bank_id_q <= 1'b0;
            capture_rsp_source_bank_generation_q <= 32'd0;
            capture_rsp_tag_q <= 16'd0;
            capture_rsp_status_q <= STATUS_OK;

            tile_slot_valid_q <= 1'b0;
            pack_busy_q <= 1'b0;
            pack_lane_q <= 4'd0;
            tile_rsp_valid_q <= 1'b0;
            use_tile_valid_q <= 1'b0;
            tile_image_epoch_q <= 32'd0;
            tile_stage_id_q <= 4'd0;
            tile_scratch_generation_q <= 32'd0;
            tile_stage_ticket_q <= 32'd0;
            tile_logical_branch_q <= 2'd0;
            tile_context_generation_q <= 32'd0;
            tile_binding_token_q <= 32'd0;
            tile_cancellation_epoch_q <= 32'd0;
            tile_row_tile_q <= 6'd0;
            tile_replay_token_q <= 32'd0;
            tile_use_token_q <= 32'd0;
            tile_source_bank_id_q <= 1'b0;
            tile_source_bank_generation_q <= 32'd0;
            tile_tag_q <= 16'd0;
            tile_status_q <= STATUS_OK;

            use_release_rsp_valid_q <= 1'b0;
            use_release_rsp_image_epoch_q <= 32'd0;
            use_release_rsp_stage_id_q <= 4'd0;
            use_release_rsp_scratch_generation_q <= 32'd0;
            use_release_rsp_stage_ticket_q <= 32'd0;
            use_release_rsp_logical_branch_q <= 2'd0;
            use_release_rsp_context_generation_q <= 32'd0;
            use_release_rsp_binding_token_q <= 32'd0;
            use_release_rsp_cancellation_epoch_q <= 32'd0;
            use_release_rsp_row_tile_q <= 6'd0;
            use_release_rsp_replay_token_q <= 32'd0;
            use_release_rsp_use_token_q <= 32'd0;
            use_release_rsp_tag_q <= 16'd0;
            use_release_rsp_status_q <= STATUS_OK;

            mgmt_rsp_valid_q <= 1'b0;
            mgmt_rsp_opcode_q <= 3'd0;
            mgmt_rsp_request_generation_q <= 32'd0;
            mgmt_rsp_result_generation_q <= 32'd0;
            mgmt_rsp_state_q <= ST_EMPTY;
            mgmt_rsp_stage_ticket_q <= 32'd0;
            mgmt_rsp_binding_token_q <= 32'd0;
            mgmt_rsp_source_bank_id_q <= 1'b0;
            mgmt_rsp_source_bank_generation_q <= 32'd0;
            mgmt_rsp_tag_q <= 16'd0;
            mgmt_rsp_status_q <= STATUS_OK;
            mgmt_pending_q <= 1'b0;
            mgmt_pending_opcode_q <= 3'd0;
            mgmt_pending_request_generation_q <= 32'd0;
            mgmt_pending_tag_q <= 16'd0;
            mgmt_pending_status_q <= STATUS_OK;

            close_pending_q <= 1'b0;
            close_had_owner_q <= 1'b0;
            close_code_q <= STATUS_OK;
            close_data_untrusted_q <= 1'b0;
            close_cancellation_epoch_q <= 32'd0;
            close_tag_q <= 16'd0;
            final_close_rsp_valid_q <= 1'b0;
            final_close_rsp_state_q <= ST_EMPTY;
            final_close_rsp_generation_q <= 32'd0;
            final_close_rsp_stage_ticket_q <= 32'd0;
            final_close_rsp_binding_token_q <= 32'd0;
            final_close_rsp_cancellation_epoch_q <= 32'd0;
            final_close_rsp_tag_q <= 16'd0;
            final_close_rsp_status_q <= STATUS_OK;
            final_close_rsp_reset_required_q <= 1'b0;

            fault_pending_q <= 1'b0;
            fault_code_q <= STATUS_OK;
            teardown_pending_q <= 1'b0;
            reset_required_q <= 1'b0;
            internal_fault_record_valid_q <= 1'b0;
            internal_fault_record_subtype_q <= 11'd0;
            internal_fault_record_row_tile_q <= 6'd0;
            internal_fault_record_lane_q <= 4'd0;
            mgmt_drain_checked_q <= 1'b0;
            close_drain_checked_q <= 1'b0;

            local_error_valid_q <= 1'b0;
            local_error_code_q <= STATUS_OK;
            local_error_source_q <= 3'd0;
            local_error_detail_q <= 32'd0;
            local_error_image_epoch_q <= 32'd0;
            local_error_stage_id_q <= 4'd0;
            local_error_scratch_generation_q <= 32'd0;
            local_error_stage_ticket_q <= 32'd0;
            local_error_logical_branch_q <= 2'd0;
            local_error_context_generation_q <= 32'd0;
            local_error_binding_token_q <= 32'd0;
            local_error_source_bank_id_q <= 1'b0;
            local_error_source_bank_generation_q <= 32'd0;
            local_error_object_cancellation_epoch_q <= 32'd0;
            local_error_stop_cancellation_epoch_q <= 32'd0;
            local_error_offender_tag_q <= 16'd0;
            local_error_offender_row_tile_q <= 6'd0;
            first_overflow_valid_q <= 1'b0;
            first_overflow_row_tile_q <= 6'd0;
            first_overflow_lane_q <= 4'd0;
            first_overflow_mask_q <= 16'd0;
        end else begin
            // Independent response retirements.
            if (mgmt_rsp_fire)
                mgmt_rsp_valid_q <= 1'b0;
            if (capture_rsp_fire)
                capture_rsp_valid_q <= 1'b0;
            if (use_release_rsp_fire)
                use_release_rsp_valid_q <= 1'b0;
            if (final_close_rsp_fire)
                final_close_rsp_valid_q <= 1'b0;

            // Destructive lifecycle completion uses a registered integrity
            // authorization.  Arm only from a fully empty pre-edge causal
            // set; a newly detected raw invariant therefore records first and
            // cannot share an edge with identity reclamation.  Once an
            // internal-fault record exists, the same staging lets the pending
            // request complete with INTERNAL_STATE while retaining identity.
            if (!mgmt_pending_q)
                mgmt_drain_checked_q <= 1'b0;
            else if (!mgmt_drain_checked_q && causal_drain_complete &&
                     (!internal_state_fault ||
                      internal_fault_record_valid_q))
                mgmt_drain_checked_q <= 1'b1;

            if (!close_pending_q)
                close_drain_checked_q <= 1'b0;
            else if (!close_drain_checked_q && !mgmt_pending_q &&
                     causal_drain_complete &&
                     (!internal_state_fault ||
                      internal_fault_record_valid_q))
                close_drain_checked_q <= 1'b1;

            // An execution result which was held behind the visible capture
            // response advances without losing its reserved ownership.
            if (capture_exec_valid_q && capture_exec_terminal_q &&
                capture_rsp_can_take) begin
                capture_rsp_valid_q <= 1'b1;
                capture_rsp_image_epoch_q <= capture_exec_image_epoch_q;
                capture_rsp_stage_id_q <= capture_exec_stage_id_q;
                capture_rsp_scratch_generation_q <=
                    capture_exec_scratch_generation_q;
                capture_rsp_stage_ticket_q <= capture_exec_stage_ticket_q;
                capture_rsp_logical_branch_q <=
                    capture_exec_logical_branch_q;
                capture_rsp_context_generation_q <=
                    capture_exec_context_generation_q;
                capture_rsp_binding_token_q <= capture_exec_binding_token_q;
                capture_rsp_cancellation_epoch_q <=
                    capture_exec_cancellation_epoch_q;
                capture_rsp_row_tile_q <= capture_exec_row_tile_q;
                capture_rsp_snapshot_taken_q <=
                    capture_exec_snapshot_taken_q;
                capture_rsp_committed_lane_mask_q <=
                    capture_committed_mask_q;
                capture_rsp_bitmap_q <= capture_exec_bitmap_q;
                capture_rsp_count_q <= capture_exec_count_q;
                capture_rsp_source_bank_id_q <=
                    capture_exec_source_bank_id_q;
                capture_rsp_source_bank_generation_q <=
                    capture_exec_source_bank_generation_q;
                capture_rsp_tag_q <= capture_exec_tag_q;
                capture_rsp_status_q <= capture_exec_status_q;
                capture_exec_valid_q <= 1'b0;
                capture_exec_terminal_q <= 1'b0;
            end

            // One actual payload write commits per serializer edge.
            if (capture_write_fire) begin
                capture_committed_mask_q[capture_lane_q] <= 1'b1;
                committed_entry_count_q <= committed_entry_count_q + 1'b1;
                if (capture_lane_q == 4'd15) begin
                    committed_tile_bitmap_q[capture_exec_row_tile_q] <= 1'b1;
                    next_expected_tile_q <= next_expected_tile_q + 1'b1;
                    capture_exec_bitmap_q <= committed_tile_bitmap_q |
                        (20'b1 << capture_exec_row_tile_q);
                    capture_exec_count_q <= committed_entry_count_q + 1'b1;
                    capture_committed_mask_q <= 16'hffff;
                    capture_exec_status_q <=
                        (internal_state_fault ||
                         internal_fault_record_valid_q) ?
                        STATUS_ERR_INTERNAL_STATE :
                        (final_close_install_fire ? final_close_req_code :
                         (stop_pending ? selected_stop_code : STATUS_OK));

                    if ((capture_exec_row_tile_q == 6'd19) &&
                        ((committed_tile_bitmap_q |
                          (20'b1 << capture_exec_row_tile_q)) ==
                         20'hfffff) &&
                        ((committed_entry_count_q + 1'b1) == 9'd320) &&
                        !stop_pending && !final_close_install_fire)
                        scratch_state_q <= ST_COMPLETE;

                    if (capture_rsp_can_take) begin
                        capture_rsp_valid_q <= 1'b1;
                        capture_rsp_image_epoch_q <=
                            capture_exec_image_epoch_q;
                        capture_rsp_stage_id_q <= capture_exec_stage_id_q;
                        capture_rsp_scratch_generation_q <=
                            capture_exec_scratch_generation_q;
                        capture_rsp_stage_ticket_q <=
                            capture_exec_stage_ticket_q;
                        capture_rsp_logical_branch_q <=
                            capture_exec_logical_branch_q;
                        capture_rsp_context_generation_q <=
                            capture_exec_context_generation_q;
                        capture_rsp_binding_token_q <=
                            capture_exec_binding_token_q;
                        capture_rsp_cancellation_epoch_q <=
                            capture_exec_cancellation_epoch_q;
                        capture_rsp_row_tile_q <= capture_exec_row_tile_q;
                        capture_rsp_snapshot_taken_q <= 1'b1;
                        capture_rsp_committed_lane_mask_q <= 16'hffff;
                        capture_rsp_bitmap_q <= committed_tile_bitmap_q |
                            (20'b1 << capture_exec_row_tile_q);
                        capture_rsp_count_q <= committed_entry_count_q + 1'b1;
                        capture_rsp_source_bank_id_q <=
                            capture_exec_source_bank_id_q;
                        capture_rsp_source_bank_generation_q <=
                            capture_exec_source_bank_generation_q;
                        capture_rsp_tag_q <= capture_exec_tag_q;
                        capture_rsp_status_q <=
                            (internal_state_fault ||
                             internal_fault_record_valid_q) ?
                            STATUS_ERR_INTERNAL_STATE :
                            (final_close_install_fire ?
                             final_close_req_code :
                             (stop_pending ? selected_stop_code : STATUS_OK));
                        capture_exec_valid_q <= 1'b0;
                        capture_exec_terminal_q <= 1'b0;
                    end else begin
                        capture_exec_terminal_q <= 1'b1;
                    end
                end else begin
                    capture_lane_q <= capture_lane_q + 1'b1;
                end
            end

            // Full tile packing.  lane zero was issued on request acceptance.
            if (pack_busy_q) begin
                current_tile_data_q[pack_lane_q*32 +: 32] <= ram_read_data_q;
                if (pack_lane_q == 4'd15) begin
                    pack_busy_q <= 1'b0;
                    tile_rsp_valid_q <= 1'b1;
                    tile_status_q <=
                        (internal_state_fault ||
                         internal_fault_record_valid_q) ?
                        STATUS_ERR_INTERNAL_STATE :
                        (final_close_install_fire ? final_close_req_code :
                         (stop_pending ? selected_stop_code : STATUS_OK));
                end else begin
                    pack_lane_q <= pack_lane_q + 1'b1;
                end
            end

            // A read response handshake starts a use only for immutable OK.
            if (tile_rsp_fire) begin
                tile_rsp_valid_q <= 1'b0;
                if ((tile_status_q == STATUS_OK) &&
                    !(close_pending_q && close_data_untrusted_q) &&
                    !(final_close_install_fire &&
                      final_close_req_data_untrusted)) begin
                    use_tile_valid_q <= 1'b1;
                end else begin
                    use_tile_valid_q <= 1'b0;
                    tile_slot_valid_q <= 1'b0;
                    if (!stop_pending && !final_close_install_fire &&
                        (scratch_state_q == ST_IN_USE))
                        scratch_state_q <= ST_VALID;
                end
            end

            // Capture admission either snapshots all 512 bits atomically or
            // creates a terminal diagnostic without touching the RAM.
            if (capture_req_fire) begin
                capture_exec_valid_q <= 1'b1;
                capture_exec_terminal_q <=
                    (capture_accept_status != STATUS_OK);
                capture_lane_q <= 4'd0;
                capture_committed_mask_q <= 16'd0;
                capture_exec_image_epoch_q <= capture_req_image_epoch;
                capture_exec_stage_id_q <= capture_req_stage_id;
                capture_exec_scratch_generation_q <=
                    capture_req_scratch_generation;
                capture_exec_stage_ticket_q <= capture_req_stage_ticket;
                capture_exec_logical_branch_q <=
                    capture_req_logical_branch;
                capture_exec_context_generation_q <=
                    capture_req_context_generation;
                capture_exec_binding_token_q <=
                    capture_req_matrix0_binding_token;
                capture_exec_cancellation_epoch_q <=
                    capture_req_cancellation_epoch;
                capture_exec_row_tile_q <= capture_req_row_tile;
                capture_exec_snapshot_taken_q <=
                    (capture_accept_status == STATUS_OK);
                capture_exec_bitmap_q <= committed_tile_bitmap_q;
                capture_exec_count_q <= committed_entry_count_q;
                capture_exec_source_bank_id_q <= scratch_owner_valid_q ?
                    scratch_source_bank_id_q : 1'b0;
                capture_exec_source_bank_generation_q <=
                    scratch_owner_valid_q ?
                    scratch_source_bank_generation_q : 32'd0;
                capture_exec_tag_q <= capture_req_tag;
                capture_exec_status_q <= capture_accept_status;
                if (capture_accept_status == STATUS_OK)
                    capture_data_q <= capture_req_accumulators;
            end

            // Tile read admission reserves the complete response/use position.
            if (tile_req_fire) begin
                tile_slot_valid_q <= 1'b1;
                pack_busy_q <= (tile_accept_status == STATUS_OK);
                pack_lane_q <= 4'd0;
                tile_rsp_valid_q <= (tile_accept_status != STATUS_OK);
                use_tile_valid_q <= 1'b0;
                tile_image_epoch_q <= tile_req_image_epoch;
                tile_stage_id_q <= tile_req_stage_id;
                tile_scratch_generation_q <= tile_req_scratch_generation;
                tile_stage_ticket_q <= tile_req_stage_ticket;
                tile_logical_branch_q <= tile_req_logical_branch;
                tile_context_generation_q <= tile_req_context_generation;
                tile_binding_token_q <= tile_req_retired_binding_token;
                tile_cancellation_epoch_q <= tile_req_cancellation_epoch;
                tile_row_tile_q <= tile_req_row_tile;
                tile_replay_token_q <= tile_req_replay_token;
                tile_source_bank_id_q <= scratch_owner_valid_q ?
                                         scratch_source_bank_id_q : 1'b0;
                tile_source_bank_generation_q <= scratch_owner_valid_q ?
                    scratch_source_bank_generation_q : 32'd0;
                tile_tag_q <= tile_req_tag;
                tile_status_q <= tile_accept_status;
                if (tile_accept_status == STATUS_OK) begin
                    use_token_counter_q <= use_token_counter_q + 1'b1;
                    tile_use_token_q <= use_token_counter_q + 1'b1;
                    scratch_state_q <= ST_IN_USE;
                end else begin
                    tile_use_token_q <= 32'd0;
                end
            end

            // Release response always echoes the accepted request.  During a
            // final close, an exact causal release still frees the use credit
            // but its newly materialized response reports the stop code.
            if (use_release_req_fire) begin
                use_release_rsp_valid_q <= 1'b1;
                use_release_rsp_image_epoch_q <=
                    use_release_req_image_epoch;
                use_release_rsp_stage_id_q <= use_release_req_stage_id;
                use_release_rsp_scratch_generation_q <=
                    use_release_req_scratch_generation;
                use_release_rsp_stage_ticket_q <=
                    use_release_req_stage_ticket;
                use_release_rsp_logical_branch_q <=
                    use_release_req_logical_branch;
                use_release_rsp_context_generation_q <=
                    use_release_req_context_generation;
                use_release_rsp_binding_token_q <=
                    use_release_req_matrix0_binding_token;
                use_release_rsp_cancellation_epoch_q <=
                    use_release_req_cancellation_epoch;
                use_release_rsp_row_tile_q <= use_release_req_row_tile;
                use_release_rsp_replay_token_q <=
                    use_release_req_replay_token;
                use_release_rsp_use_token_q <= use_release_req_use_token;
                use_release_rsp_tag_q <= use_release_req_tag;
                use_release_rsp_status_q <=
                    internal_fault_record_valid_q ?
                    STATUS_ERR_INTERNAL_STATE :
                    ((use_release_accept_exact && stop_pending) ?
                     selected_stop_code : use_release_accept_status);

                if (use_release_accept_exact) begin
                    replayed_tile_bitmap_q[tile_row_tile_q] <= 1'b1;
                    use_tile_valid_q <= 1'b0;
                    tile_slot_valid_q <= 1'b0;
                    if (!stop_pending && !teardown_pending_q &&
                        !internal_fault_record_valid_q)
                        scratch_state_q <= ST_VALID;
                end
            end

            // Ordinary management requests other than a successful RELEASE
            // materialize their one held response immediately.
            if (mgmt_req_fire) begin
                if (mgmt_release_ok ||
                    mgmt_release_generation_exhausted) begin
                    mgmt_pending_q <= 1'b1;
                    mgmt_pending_opcode_q <= mgmt_req_opcode;
                    mgmt_pending_request_generation_q <=
                        mgmt_req_scratch_generation;
                    mgmt_pending_tag_q <= mgmt_req_tag;
                    mgmt_pending_status_q <=
                        mgmt_release_generation_exhausted ?
                        STATUS_ERR_GENERATION_EXHAUSTED : STATUS_OK;
                    teardown_pending_q <= 1'b1;
                    if (mgmt_release_generation_exhausted) begin
                        fault_pending_q <= 1'b1;
                        fault_code_q <= STATUS_ERR_GENERATION_EXHAUSTED;
                        reset_required_q <= 1'b1;
                    end
                end else begin
                    mgmt_rsp_valid_q <= 1'b1;
                    mgmt_rsp_opcode_q <= mgmt_req_opcode;
                    mgmt_rsp_request_generation_q <=
                        mgmt_req_scratch_generation;
                    mgmt_rsp_result_generation_q <=
                        (mgmt_allocate_ok &&
                         !scratch_generation_initialized_q) ? 32'd1 :
                        (mgmt_clear_ok ?
                         (scratch_generation_q + 1'b1) :
                         scratch_generation_q);
                    mgmt_rsp_state_q <=
                        mgmt_allocate_ok ? ST_FILLING :
                        (mgmt_publish_ok ? ST_VALID :
                         (mgmt_clear_ok ? ST_EMPTY : scratch_state_q));
                    mgmt_rsp_stage_ticket_q <=
                        mgmt_allocate_ok ?
                        mgmt_req_stage_ticket :
                        (scratch_owner_valid_q ? scratch_stage_ticket_q :
                         32'd0);
                    mgmt_rsp_binding_token_q <=
                        mgmt_allocate_ok ?
                        mgmt_req_matrix0_binding_token :
                        (scratch_owner_valid_q ?
                         scratch_matrix0_binding_token_q : 32'd0);
                    mgmt_rsp_source_bank_id_q <=
                        mgmt_allocate_ok ?
                        mgmt_req_source_bank_id :
                        (scratch_owner_valid_q ? scratch_source_bank_id_q :
                         1'b0);
                    mgmt_rsp_source_bank_generation_q <=
                        mgmt_allocate_ok ?
                        mgmt_req_source_bank_generation :
                        (scratch_owner_valid_q ?
                         scratch_source_bank_generation_q : 32'd0);
                    mgmt_rsp_tag_q <= mgmt_req_tag;
                    mgmt_rsp_status_q <= mgmt_accept_status;
                end

                if (mgmt_allocate_ok) begin
                    scratch_state_q <= ST_FILLING;
                    scratch_generation_q <=
                        scratch_generation_initialized_q ?
                        scratch_generation_q : 32'd1;
                    scratch_generation_initialized_q <= 1'b1;
                    scratch_owner_valid_q <= 1'b1;
                    scratch_image_epoch_q <= mgmt_req_image_epoch;
                    scratch_stage_id_q <= mgmt_req_stage_id;
                    scratch_stage_ticket_q <= mgmt_req_stage_ticket;
                    scratch_logical_branch_q <= mgmt_req_logical_branch;
                    scratch_context_generation_q <=
                        mgmt_req_context_generation;
                    scratch_matrix0_binding_token_q <=
                        mgmt_req_matrix0_binding_token;
                    scratch_source_bank_id_q <= mgmt_req_source_bank_id;
                    scratch_source_bank_generation_q <=
                        mgmt_req_source_bank_generation;
                    scratch_cancellation_epoch_q <=
                        mgmt_req_cancellation_epoch;
                    committed_tile_bitmap_q <= 20'd0;
                    committed_entry_count_q <= 9'd0;
                    replayed_tile_bitmap_q <= 20'd0;
                    next_expected_tile_q <= 6'd0;
                    use_token_counter_q <= 32'd0;
                end else if (mgmt_publish_ok) begin
                    scratch_state_q <= ST_VALID;
                end else if (mgmt_clear_ok) begin
                    scratch_state_q <= ST_EMPTY;
                    scratch_generation_q <= scratch_generation_q + 1'b1;
                    scratch_owner_valid_q <= 1'b0;
                    scratch_image_epoch_q <= 32'd0;
                    scratch_stage_id_q <= 4'd0;
                    scratch_stage_ticket_q <= 32'd0;
                    scratch_logical_branch_q <= 2'd0;
                    scratch_context_generation_q <= 32'd0;
                    scratch_matrix0_binding_token_q <= 32'd0;
                    scratch_source_bank_id_q <= 1'b0;
                    scratch_source_bank_generation_q <= 32'd0;
                    scratch_cancellation_epoch_q <= 32'd0;
                    committed_tile_bitmap_q <= 20'd0;
                    committed_entry_count_q <= 9'd0;
                    replayed_tile_bitmap_q <= 20'd0;
                    next_expected_tile_q <= 6'd0;
                    use_token_counter_q <= 32'd0;
                    local_error_valid_q <= 1'b0;
                    local_error_code_q <= STATUS_OK;
                    local_error_source_q <= 3'd0;
                    local_error_detail_q <= 32'd0;
                    local_error_image_epoch_q <= 32'd0;
                    local_error_stage_id_q <= 4'd0;
                    local_error_scratch_generation_q <= 32'd0;
                    local_error_stage_ticket_q <= 32'd0;
                    local_error_logical_branch_q <= 2'd0;
                    local_error_context_generation_q <= 32'd0;
                    local_error_binding_token_q <= 32'd0;
                    local_error_source_bank_id_q <= 1'b0;
                    local_error_source_bank_generation_q <= 32'd0;
                    local_error_object_cancellation_epoch_q <= 32'd0;
                    local_error_stop_cancellation_epoch_q <= 32'd0;
                    local_error_offender_tag_q <= 16'd0;
                    local_error_offender_row_tile_q <= 6'd0;
                    first_overflow_valid_q <= 1'b0;
                    first_overflow_row_tile_q <= 6'd0;
                    first_overflow_lane_q <= 4'd0;
                    first_overflow_mask_q <= 16'd0;
                    fault_pending_q <= 1'b0;
                    teardown_pending_q <= 1'b0;
                    close_pending_q <= 1'b0;
                end
            end

            // A delayed RELEASE commits only after all pre-existing causal
            // references (including a held use-release response) retire.
            if (mgmt_pending_q && mgmt_drain_checked_q &&
                causal_drain_complete) begin
                mgmt_pending_q <= 1'b0;
                mgmt_drain_checked_q <= 1'b0;
                teardown_pending_q <= 1'b0;
                mgmt_rsp_valid_q <= 1'b1;
                mgmt_rsp_opcode_q <= mgmt_pending_opcode_q;
                mgmt_rsp_request_generation_q <=
                    mgmt_pending_request_generation_q;
                mgmt_rsp_stage_ticket_q <= scratch_stage_ticket_q;
                mgmt_rsp_binding_token_q <=
                    scratch_matrix0_binding_token_q;
                mgmt_rsp_source_bank_id_q <= scratch_source_bank_id_q;
                mgmt_rsp_source_bank_generation_q <=
                    scratch_source_bank_generation_q;
                mgmt_rsp_tag_q <= mgmt_pending_tag_q;

                if (internal_fault_record_valid_q ||
                    (fault_pending_q &&
                     (fault_code_q == STATUS_ERR_INTERNAL_STATE))) begin
                    scratch_state_q <= ST_ERROR;
                    mgmt_rsp_result_generation_q <= scratch_generation_q;
                    mgmt_rsp_state_q <= ST_ERROR;
                    mgmt_rsp_status_q <= STATUS_ERR_INTERNAL_STATE;
                end else if (close_pending_q || final_close_install_fire) begin
                    scratch_state_q <= ST_ERROR;
                    mgmt_rsp_result_generation_q <= scratch_generation_q;
                    mgmt_rsp_state_q <= ST_ERROR;
                    mgmt_rsp_status_q <= final_close_install_fire ?
                        final_close_req_code : close_code_q;
                end else if (mgmt_pending_status_q ==
                             STATUS_ERR_GENERATION_EXHAUSTED) begin
                    scratch_state_q <= ST_ERROR;
                    mgmt_rsp_result_generation_q <= scratch_generation_q;
                    mgmt_rsp_state_q <= ST_ERROR;
                    mgmt_rsp_status_q <=
                        STATUS_ERR_GENERATION_EXHAUSTED;
                end else begin
                    scratch_state_q <= ST_EMPTY;
                    scratch_generation_q <= scratch_generation_q + 1'b1;
                    scratch_owner_valid_q <= 1'b0;
                    scratch_image_epoch_q <= 32'd0;
                    scratch_stage_id_q <= 4'd0;
                    scratch_stage_ticket_q <= 32'd0;
                    scratch_logical_branch_q <= 2'd0;
                    scratch_context_generation_q <= 32'd0;
                    scratch_matrix0_binding_token_q <= 32'd0;
                    scratch_source_bank_id_q <= 1'b0;
                    scratch_source_bank_generation_q <= 32'd0;
                    scratch_cancellation_epoch_q <= 32'd0;
                    committed_tile_bitmap_q <= 20'd0;
                    committed_entry_count_q <= 9'd0;
                    replayed_tile_bitmap_q <= 20'd0;
                    next_expected_tile_q <= 6'd0;
                    use_token_counter_q <= 32'd0;
                    mgmt_rsp_result_generation_q <=
                        scratch_generation_q + 1'b1;
                    mgmt_rsp_state_q <= ST_EMPTY;
                    mgmt_rsp_status_q <= STATUS_OK;
                end
            end

            // Final close validation errors are caller-local.  A valid close
            // on a live object installs an overlay and preserves old identity.
            if (final_close_fire) begin
                if (close_accept_status != STATUS_OK) begin
                    final_close_rsp_valid_q <= 1'b1;
                    final_close_rsp_state_q <= scratch_state_q;
                    final_close_rsp_generation_q <= scratch_generation_q;
                    final_close_rsp_stage_ticket_q <=
                        scratch_owner_valid_q ? scratch_stage_ticket_q : 32'd0;
                    final_close_rsp_binding_token_q <=
                        scratch_owner_valid_q ?
                        scratch_matrix0_binding_token_q : 32'd0;
                    final_close_rsp_cancellation_epoch_q <=
                        final_close_req_cancellation_epoch;
                    final_close_rsp_tag_q <= final_close_req_tag;
                    final_close_rsp_status_q <= close_accept_status;
                    final_close_rsp_reset_required_q <= reset_required_q;
                end else begin
                    close_pending_q <= 1'b1;
                    close_had_owner_q <= scratch_owner_valid_q;
                    close_code_q <= (!final_close_req_kind &&
                                     local_error_valid_q) ?
                                    local_error_code_q :
                                    final_close_req_code;
                    close_data_untrusted_q <=
                        final_close_req_data_untrusted;
                    close_cancellation_epoch_q <=
                        final_close_req_cancellation_epoch;
                    close_tag_q <= final_close_req_tag;
                    fault_pending_q <= 1'b1;
                    fault_code_q <= (!final_close_req_kind &&
                                     local_error_valid_q) ?
                                    local_error_code_q :
                                    final_close_req_code;
                    if (final_close_req_data_untrusted)
                        reset_required_q <= 1'b1;
                    if (scratch_owner_valid_q && local_error_valid_q) begin
                        local_error_stop_cancellation_epoch_q <=
                            final_close_req_cancellation_epoch;
                    end else if (scratch_owner_valid_q) begin
                        local_error_valid_q <= 1'b1;
                        local_error_code_q <= final_close_req_code;
                        local_error_source_q <= ERR_SRC_CLOSE;
                        local_error_detail_q <=
                            {ERR_SRC_CLOSE, final_close_req_code,
                             6'd0, 4'd0, 11'd0};
                        local_error_image_epoch_q <= scratch_image_epoch_q;
                        local_error_stage_id_q <= scratch_stage_id_q;
                        local_error_scratch_generation_q <=
                            scratch_generation_q;
                        local_error_stage_ticket_q <= scratch_stage_ticket_q;
                        local_error_logical_branch_q <=
                            scratch_logical_branch_q;
                        local_error_context_generation_q <=
                            scratch_context_generation_q;
                        local_error_binding_token_q <=
                            scratch_matrix0_binding_token_q;
                        local_error_source_bank_id_q <=
                            scratch_source_bank_id_q;
                        local_error_source_bank_generation_q <=
                            scratch_source_bank_generation_q;
                        local_error_object_cancellation_epoch_q <=
                            scratch_cancellation_epoch_q;
                        local_error_stop_cancellation_epoch_q <=
                            final_close_req_cancellation_epoch;
                        local_error_offender_tag_q <= final_close_req_tag;
                        local_error_offender_row_tile_q <= 6'd0;
                    end
                end
            end

            // The close response materializes only after every causal data or
            // pre-existing response position has drained.
            // A final close which superseded an accepted RELEASE must wait
            // for that ordinary terminal response to materialize and retire.
            // The registered drain check is armed only after the ordinary
            // RELEASE descriptor and response have both left the causal set.
            if (close_pending_q && !mgmt_pending_q &&
                close_drain_checked_q && causal_drain_complete) begin
                close_pending_q <= 1'b0;
                close_drain_checked_q <= 1'b0;
                fault_pending_q <= 1'b0;
                scratch_state_q <= close_had_owner_q ? ST_ERROR : ST_EMPTY;
                final_close_rsp_valid_q <= 1'b1;
                final_close_rsp_state_q <= close_had_owner_q ?
                                           ST_ERROR : ST_EMPTY;
                final_close_rsp_generation_q <= scratch_generation_q;
                final_close_rsp_stage_ticket_q <= close_had_owner_q ?
                    scratch_stage_ticket_q : 32'd0;
                final_close_rsp_binding_token_q <= close_had_owner_q ?
                    scratch_matrix0_binding_token_q : 32'd0;
                final_close_rsp_cancellation_epoch_q <=
                    close_cancellation_epoch_q;
                final_close_rsp_tag_q <= close_tag_q;
                final_close_rsp_status_q <=
                    internal_fault_record_valid_q ?
                    STATUS_ERR_INTERNAL_STATE : close_code_q;
                final_close_rsp_reset_required_q <=
                    reset_required_q || close_data_untrusted_q ||
                    internal_fault_record_valid_q;
            end else if (fault_pending_q && !close_pending_q &&
                         !mgmt_pending_q && causal_drain_after_retire) begin
                fault_pending_q <= 1'b0;
                scratch_state_q <= ST_ERROR;
            end

            // A fatal capture is attributed only after the request has passed
            // the exact attribution boundary in Section 7.4.
            if (capture_poison_fire) begin
                fault_pending_q <= 1'b1;
                fault_code_q <= capture_accept_status;
                if (!local_error_valid_q) begin
                    local_error_valid_q <= 1'b1;
                    local_error_code_q <= capture_accept_status;
                    local_error_source_q <= ERR_SRC_CAPTURE;
                    local_error_detail_q <=
                        {ERR_SRC_CAPTURE, capture_accept_status,
                         capture_req_row_tile,
                         (capture_accept_overflow ? capture_lowest_lane :
                          ((capture_accept_status ==
                            STATUS_ERR_BAD_LANE_MASK) ?
                           capture_lowest_missing_lane : 4'd0)), 11'd0};
                    local_error_image_epoch_q <= scratch_image_epoch_q;
                    local_error_stage_id_q <= scratch_stage_id_q;
                    local_error_scratch_generation_q <=
                        scratch_generation_q;
                    local_error_stage_ticket_q <= scratch_stage_ticket_q;
                    local_error_logical_branch_q <=
                        scratch_logical_branch_q;
                    local_error_context_generation_q <=
                        scratch_context_generation_q;
                    local_error_binding_token_q <=
                        scratch_matrix0_binding_token_q;
                    local_error_source_bank_id_q <= scratch_source_bank_id_q;
                    local_error_source_bank_generation_q <=
                        scratch_source_bank_generation_q;
                    local_error_object_cancellation_epoch_q <=
                        scratch_cancellation_epoch_q;
                    local_error_stop_cancellation_epoch_q <= 32'd0;
                    local_error_offender_tag_q <= capture_req_tag;
                    local_error_offender_row_tile_q <= capture_req_row_tile;
                end
                if (capture_accept_overflow) begin
                    reset_required_q <= 1'b1;
                    if (!first_overflow_valid_q) begin
                        first_overflow_valid_q <= 1'b1;
                        first_overflow_row_tile_q <= capture_req_row_tile;
                        first_overflow_lane_q <= capture_lowest_lane;
                        first_overflow_mask_q <= capture_req_overflow;
                    end
                end
            end

            // Generation exhaustion is a current-object fatal and retains
            // the object identity; it can never wrap to zero.
            if (mgmt_req_fire &&
                mgmt_release_generation_exhausted &&
                !local_error_valid_q) begin
                local_error_valid_q <= 1'b1;
                local_error_code_q <= STATUS_ERR_GENERATION_EXHAUSTED;
                local_error_source_q <= ERR_SRC_GEN;
                local_error_detail_q <=
                    {ERR_SRC_GEN, STATUS_ERR_GENERATION_EXHAUSTED,
                     6'd0, 4'd0, 11'd0};
                local_error_image_epoch_q <= scratch_image_epoch_q;
                local_error_stage_id_q <= scratch_stage_id_q;
                local_error_scratch_generation_q <= scratch_generation_q;
                local_error_stage_ticket_q <= scratch_stage_ticket_q;
                local_error_logical_branch_q <= scratch_logical_branch_q;
                local_error_context_generation_q <=
                    scratch_context_generation_q;
                local_error_binding_token_q <=
                    scratch_matrix0_binding_token_q;
                local_error_source_bank_id_q <= scratch_source_bank_id_q;
                local_error_source_bank_generation_q <=
                    scratch_source_bank_generation_q;
                local_error_object_cancellation_epoch_q <=
                    scratch_cancellation_epoch_q;
                local_error_stop_cancellation_epoch_q <= 32'd0;
                local_error_offender_tag_q <= mgmt_req_tag;
                local_error_offender_row_tile_q <= 6'd0;
            end

            if (mgmt_req_fire && mgmt_clear_generation_exhausted) begin
                reset_required_q <= 1'b1;
            end

            // Capture a newly visible invariant failure into a compact record.
            // Ready is already low in this detection cycle; the registered
            // record supplies the following cycle's sticky high-fanout action.
            if (internal_state_fault && !internal_fault_record_valid_q) begin
                internal_fault_record_valid_q <= 1'b1;
                internal_fault_record_subtype_q <= internal_fault_subtype;
                internal_fault_record_row_tile_q <=
                    capture_exec_valid_q ? capture_exec_row_tile_q :
                    (tile_slot_valid_q ? tile_row_tile_q : 6'd0);
                internal_fault_record_lane_q <=
                    capture_exec_valid_q ? capture_lane_q :
                    (tile_slot_valid_q ? pack_lane_q : 4'd0);
            end

            if (internal_fault_record_valid_q) begin
                fault_pending_q <= 1'b1;
                fault_code_q <= STATUS_ERR_INTERNAL_STATE;
                reset_required_q <= 1'b1;
                if (close_pending_q &&
                    (close_code_q == STATUS_ERR_ABORTED))
                    close_code_q <= STATUS_ERR_INTERNAL_STATE;
                if (!local_error_valid_q) begin
                    local_error_valid_q <= 1'b1;
                    local_error_code_q <= STATUS_ERR_INTERNAL_STATE;
                    local_error_source_q <= ERR_SRC_INTERNAL;
                    local_error_detail_q <=
                        {ERR_SRC_INTERNAL, STATUS_ERR_INTERNAL_STATE,
                         internal_fault_record_row_tile_q,
                         internal_fault_record_lane_q,
                         internal_fault_record_subtype_q};
                    local_error_image_epoch_q <= scratch_image_epoch_q;
                    local_error_stage_id_q <= scratch_stage_id_q;
                    local_error_scratch_generation_q <=
                        scratch_generation_q;
                    local_error_stage_ticket_q <= scratch_stage_ticket_q;
                    local_error_logical_branch_q <=
                        scratch_logical_branch_q;
                    local_error_context_generation_q <=
                        scratch_context_generation_q;
                    local_error_binding_token_q <=
                        scratch_matrix0_binding_token_q;
                    local_error_source_bank_id_q <= scratch_source_bank_id_q;
                    local_error_source_bank_generation_q <=
                        scratch_source_bank_generation_q;
                    local_error_object_cancellation_epoch_q <=
                        scratch_cancellation_epoch_q;
                    local_error_stop_cancellation_epoch_q <= 32'd0;
                    local_error_offender_tag_q <= 16'd0;
                    local_error_offender_row_tile_q <= 6'd0;
                end
            end
        end
    end

endmodule
