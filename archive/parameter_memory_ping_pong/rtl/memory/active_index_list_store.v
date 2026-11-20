`timescale 1ns/1ps

// Immutable active-index list storage for the shared single-PE schedule.
//
// The two payload arrays deliberately have no reset path.  Descriptor,
// token, generation, event, reference, and ordered-read authority make stale
// payload bits unreachable after reset or slot reuse.
module active_index_list_store (
    input  wire          clk,
    input  wire          rst_n,

    output wire [62:0]   slot_state,
    output wire [20:0]   slot_authority_valid,
    output wire [41:0]   slot_external_ref_count,
    output wire [41:0]   slot_read_ref_count,
    output reg  [4:0]    free_slot_count,
    output reg           allocation_candidate_valid,
    output reg  [4:0]    allocation_candidate_slot,
    output reg           current_producer_valid,
    output reg  [4:0]    current_producer_slot,
    output reg  [31:0]   current_producer_token,
    output reg  [15:0]   current_producer_generation,
    output reg           producer_started,
    output reg           producer_obligation,
    output reg           completion_slot_reserved,
    output wire          completion_event_pending,
    output wire          management_busy,
    output reg           closing_busy,
    output wire [1:0]    read_outstanding,
    output wire          read_pipeline_busy,
    output reg  [5:0]    external_reference_total,
    output reg  [1:0]    read_reference_total,
    output reg  [4:0]    unreleased_error_slot_count,
    output reg           local_fault_pending,
    output reg           stop_pending,
    output reg  [31:0]   last_stop_epoch,
    output reg           stop_drain_complete,
    output reg           store_quiescent,
    output reg           reset_required,
    output reg           wrap_recovery_required,

    input  wire          mgmt_req_valid,
    output reg           mgmt_req_ready,
    input  wire [2:0]    mgmt_req_opcode,
    input  wire [4:0]    mgmt_req_slot_locator,
    input  wire [31:0]   mgmt_req_list_token,
    input  wire [15:0]   mgmt_req_list_generation,
    input  wire [31:0]   mgmt_req_image_epoch,
    input  wire [3:0]    mgmt_req_stage_id,
    input  wire [1:0]    mgmt_req_logical_branch,
    input  wire [31:0]   mgmt_req_context_generation,
    input  wire [31:0]   mgmt_req_producer_sequence_ticket,
    input  wire [31:0]   mgmt_req_cancellation_epoch,
    input  wire [31:0]   mgmt_req_stop_epoch,
    input  wire [8:0]    mgmt_req_domain_bound,
    input  wire          mgmt_req_pe_recovery_safe,
    input  wire [2:0]    mgmt_req_ref_owner_kind,
    input  wire [31:0]   mgmt_req_ref_owner_token,
    input  wire [31:0]   mgmt_req_ref_token,
    input  wire [1:0]    mgmt_req_ref_phase,
    input  wire [2:0]    mgmt_req_new_ref_owner_kind,
    input  wire [31:0]   mgmt_req_new_ref_owner_token,
    input  wire [1:0]    mgmt_req_new_ref_phase,
    input  wire          mgmt_req_external_safe,
    input  wire [15:0]   mgmt_req_tag,
    output reg           mgmt_rsp_valid,
    input  wire          mgmt_rsp_ready,
    output reg  [2:0]    mgmt_rsp_opcode,
    output reg  [7:0]    mgmt_rsp_status,
    output reg           mgmt_rsp_committed,
    output reg           mgmt_rsp_released,
    output reg  [4:0]    mgmt_rsp_slot_locator,
    output reg  [31:0]   mgmt_rsp_list_token,
    output reg  [15:0]   mgmt_rsp_list_generation,
    output reg  [31:0]   mgmt_rsp_image_epoch,
    output reg  [3:0]    mgmt_rsp_stage_id,
    output reg  [1:0]    mgmt_rsp_logical_branch,
    output reg  [31:0]   mgmt_rsp_context_generation,
    output reg  [31:0]   mgmt_rsp_producer_sequence_ticket,
    output reg  [8:0]    mgmt_rsp_domain_bound,
    output reg  [8:0]    mgmt_rsp_reserved_capacity,
    output reg  [2:0]    mgmt_rsp_state,
    output reg  [8:0]    mgmt_rsp_active_count,
    output reg  [31:0]   mgmt_rsp_ref_token,
    output reg  [2:0]    mgmt_rsp_ref_owner_kind,
    output reg  [31:0]   mgmt_rsp_ref_owner_token,
    output reg  [1:0]    mgmt_rsp_ref_phase,
    output reg  [31:0]   mgmt_rsp_cancellation_epoch,
    output reg  [31:0]   mgmt_rsp_stop_epoch,
    output reg  [15:0]   mgmt_rsp_tag,

    output wire          start_partner_valid,
    input  wire          start_partner_ready,
    output wire [4:0]    start_partner_slot_locator,
    output wire [31:0]   start_partner_list_token,
    output wire [15:0]   start_partner_list_generation,
    output wire [31:0]   start_partner_image_epoch,
    output wire [3:0]    start_partner_stage_id,
    output wire [1:0]    start_partner_logical_branch,
    output wire [31:0]   start_partner_context_generation,
    output wire [31:0]   start_partner_producer_sequence_ticket,
    output wire [31:0]   start_partner_cancellation_epoch,
    output wire [15:0]   start_partner_tag,

    input  wire          stop_req_valid,
    output wire          stop_req_ready,
    input  wire          stop_req_is_fatal,
    input  wire          stop_req_data_untrusted,
    input  wire          stop_req_causal_producers_stopped,
    input  wire [31:0]   stop_req_image_epoch,
    input  wire [31:0]   stop_req_cancellation_epoch,
    input  wire [7:0]    stop_req_code,
    input  wire [15:0]   stop_req_tag,
    output reg           stop_rsp_valid,
    input  wire          stop_rsp_ready,
    output reg           stop_rsp_committed,
    output reg  [7:0]    stop_rsp_code,
    output reg  [31:0]   stop_rsp_cancellation_epoch,
    output reg  [20:0]   stop_rsp_error_slot_mask,
    output reg           stop_rsp_reset_required,
    output reg  [15:0]   stop_rsp_tag,
    output reg  [7:0]    stop_rsp_status,

    input  wire          active_cmd_valid,
    output wire          active_cmd_ready,
    input  wire          active_cmd_write,
    input  wire [8:0]    active_cmd_index,
    input  wire [15:0]   active_cmd_tag,
    input  wire          active_cmd_finalize,

    output reg           completion_valid,
    input  wire          completion_ready,
    output reg  [7:0]    completion_status,
    output reg           completion_sealed,
    output reg  [4:0]    completion_slot_locator,
    output reg  [31:0]   completion_list_token,
    output reg  [15:0]   completion_list_generation,
    output reg  [31:0]   completion_image_epoch,
    output reg  [3:0]    completion_stage_id,
    output reg  [1:0]    completion_logical_branch,
    output reg  [31:0]   completion_context_generation,
    output reg  [31:0]   completion_producer_sequence_ticket,
    output reg  [31:0]   completion_cancellation_epoch,
    output reg  [31:0]   completion_stop_epoch,
    output reg  [8:0]    completion_domain_bound,
    output reg  [8:0]    completion_active_count,
    output reg  [8:0]    completion_last_committed_index,
    output reg           completion_last_valid,
    output reg  [15:0]   completion_terminal_tag,
    output reg  [31:0]   completion_error_detail,

    input  wire          read_req_valid,
    output wire          read_req_ready,
    input  wire          read_req_kind,
    input  wire [4:0]    read_req_slot_locator,
    input  wire [31:0]   read_req_list_token,
    input  wire [15:0]   read_req_list_generation,
    input  wire [31:0]   read_req_image_epoch,
    input  wire [3:0]    read_req_stage_id,
    input  wire [1:0]    read_req_logical_branch,
    input  wire [31:0]   read_req_context_generation,
    input  wire [31:0]   read_req_producer_sequence_ticket,
    input  wire [31:0]   read_req_cancellation_epoch,
    input  wire          read_req_causal_continuation,
    input  wire [31:0]   read_req_stop_epoch,
    input  wire [31:0]   read_req_external_ref_token,
    input  wire [8:0]    read_req_ordinal,
    input  wire [15:0]   read_req_tag,
    output wire          read_rsp_valid,
    input  wire          read_rsp_ready,
    output wire          read_rsp_kind,
    output wire [7:0]    read_rsp_status,
    output wire [4:0]    read_rsp_slot_locator,
    output wire [31:0]   read_rsp_list_token,
    output wire [15:0]   read_rsp_list_generation,
    output wire [31:0]   read_rsp_image_epoch,
    output wire [3:0]    read_rsp_stage_id,
    output wire [1:0]    read_rsp_logical_branch,
    output wire [31:0]   read_rsp_context_generation,
    output wire [31:0]   read_rsp_producer_sequence_ticket,
    output wire [31:0]   read_rsp_cancellation_epoch,
    output wire [31:0]   read_rsp_stop_epoch,
    output wire [8:0]    read_rsp_domain_bound,
    output wire [8:0]    read_rsp_active_count,
    output wire [15:0]   read_rsp_terminal_tag,
    output wire [2:0]    read_rsp_state,
    output wire [1:0]    read_rsp_external_ref_count,
    output wire [8:0]    read_rsp_source_index,
    output wire          read_rsp_data_usable,
    output wire [8:0]    read_rsp_ordinal,
    output wire          read_rsp_last,
    output wire          read_rsp_sealed,
    output wire          read_rsp_causal_continuation,
    output wire [31:0]   read_rsp_external_ref_token,
    output wire [15:0]   read_rsp_tag,

    output reg           fault_event_valid,
    input  wire          fault_event_ready,
    output reg  [7:0]    fault_event_code,
    output reg  [3:0]    fault_event_source,
    output reg  [31:0]   fault_event_detail,
    output reg  [4:0]    fault_event_slot_locator,
    output reg  [31:0]   fault_event_list_token,
    output reg  [15:0]   fault_event_list_generation,
    output reg  [31:0]   fault_event_image_epoch,
    output reg  [3:0]    fault_event_stage_id,
    output reg  [1:0]    fault_event_logical_branch,
    output reg  [31:0]   fault_event_context_generation,
    output reg  [31:0]   fault_event_producer_sequence_ticket,
    output reg  [31:0]   fault_event_cancellation_epoch,
    output reg  [31:0]   fault_event_stop_epoch,
    output reg           fault_event_reset_required,
    output reg           local_error_valid,
    output reg  [7:0]    local_error_code,
    output reg  [3:0]    local_error_source,
    output reg  [31:0]   local_error_detail,
    output reg  [4:0]    local_error_slot_locator,
    output reg  [31:0]   local_error_list_token,
    output reg  [15:0]   local_error_list_generation,
    output reg  [31:0]   local_error_image_epoch,
    output reg  [3:0]    local_error_stage_id,
    output reg  [1:0]    local_error_logical_branch,
    output reg  [31:0]   local_error_context_generation,
    output reg  [31:0]   local_error_producer_sequence_ticket,
    output reg  [31:0]   local_error_cancellation_epoch,
    output reg  [31:0]   local_error_stop_epoch
);

    localparam [2:0] STATE_FREE           = 3'd0;
    localparam [2:0] STATE_OPEN           = 3'd1;
    localparam [2:0] STATE_SEALED         = 3'd2;
    localparam [2:0] STATE_REFERENCED     = 3'd3;
    localparam [2:0] STATE_POISON_DRAIN   = 3'd4;
    localparam [2:0] STATE_CANCEL_PENDING = 3'd5;
    localparam [2:0] STATE_CLOSING        = 3'd6;
    localparam [2:0] STATE_ERROR          = 3'd7;

    localparam [2:0] OP_OPEN         = 3'd0;
    localparam [2:0] OP_START        = 3'd1;
    localparam [2:0] OP_REF_ACQUIRE  = 3'd2;
    localparam [2:0] OP_REF_TRANSFER = 3'd3;
    localparam [2:0] OP_REF_RELEASE  = 3'd4;
    localparam [2:0] OP_LIST_RELEASE = 3'd5;
    localparam [2:0] OP_CLEAR_ERROR  = 3'd6;

    localparam [1:0] REF_TEMPORARY = 2'd1;
    localparam [1:0] REF_PENDING    = 2'd2;
    localparam [1:0] REF_PERSISTENT = 2'd3;

    localparam [7:0] STATUS_OK                 = 8'h00;
    localparam [7:0] ERR_BAD_OPCODE            = 8'h01;
    localparam [7:0] ERR_WRONG_STATE           = 8'h02;
    localparam [7:0] ERR_STALE_GENERATION      = 8'h03;
    localparam [7:0] ERR_OWNER_MISMATCH        = 8'h04;
    localparam [7:0] ERR_NOT_QUIESCENT         = 8'h05;
    localparam [7:0] ERR_EXTERNAL_UNSAFE       = 8'h06;
    localparam [7:0] ERR_GENERATION_EXHAUSTED  = 8'h07;
    localparam [7:0] ERR_BAD_DRAIN_TARGET      = 8'h08;
    localparam [7:0] ERR_ABORTED                = 8'h09;
    localparam [7:0] ERR_LOCAL_PROTOCOL         = 8'h0a;
    localparam [7:0] ERR_INTERNAL_STATE         = 8'h0b;
    localparam [7:0] ERR_BAD_SLOT               = 8'h40;
    localparam [7:0] ERR_STALE_TOKEN            = 8'h41;
    localparam [7:0] ERR_BAD_IDENTITY           = 8'h42;
    localparam [7:0] ERR_BAD_STAGE_DOMAIN       = 8'h43;
    localparam [7:0] ERR_BAD_DOMAIN_BOUND       = 8'h44;
    localparam [7:0] ERR_PROJECTION_PRODUCER    = 8'h45;
    localparam [7:0] ERR_REF_DUPLICATE          = 8'h46;
    localparam [7:0] ERR_REF_CAPACITY           = 8'h47;
    localparam [7:0] ERR_REF_NOT_FOUND          = 8'h48;
    localparam [7:0] ERR_STILL_REFERENCED       = 8'h49;
    localparam [7:0] ERR_EVENT_PENDING          = 8'h4a;
    localparam [7:0] ERR_BAD_ORDINAL            = 8'h4b;
    localparam [7:0] ERR_READ_UNSEALED           = 8'h4c;
    localparam [7:0] ERR_BAD_COMMAND_ENCODING   = 8'h4d;
    localparam [7:0] ERR_UNORDERED_INDEX        = 8'h4e;
    localparam [7:0] ERR_INDEX_OUT_OF_RANGE     = 8'h4f;
    localparam [7:0] ERR_CAPACITY_OVERFLOW      = 8'h50;
    localparam [7:0] ERR_EARLY_FINALIZE         = 8'h51;
    localparam [7:0] ERR_DUPLICATE_FINALIZE     = 8'h52;
    localparam [7:0] ERR_TOKEN_EXHAUSTED        = 8'h53;
    localparam [7:0] ERR_REF_TOKEN_EXHAUSTED    = 8'h54;
    localparam [7:0] ERR_RESET_REQUIRED         = 8'h55;
    localparam [7:0] ERR_STOP_EPOCH_EXHAUSTED   = 8'h56;

    localparam [3:0] SOURCE_NONE       = 4'd0;
    localparam [3:0] SOURCE_MANAGEMENT = 4'd1;
    localparam [3:0] SOURCE_ACTIVE     = 4'd2;
    localparam [3:0] SOURCE_READ       = 4'd3;
    localparam [3:0] SOURCE_REFERENCE  = 4'd4;
    localparam [3:0] SOURCE_CLOSE      = 4'd5;
    localparam [3:0] SOURCE_STOP       = 4'd6;
    localparam [3:0] SOURCE_INTERNAL   = 4'd7;
    localparam [3:0] SOURCE_ALLOCATOR  = 4'd8;

    localparam [1:0] READ_FREE   = 2'd0;
    localparam [1:0] READ_WAIT   = 2'd1;
    localparam [1:0] READ_OUTPUT = 2'd2;

    (* ram_style = "block" *) reg [8:0] index_mem0 [0:4095];
    (* ram_style = "block" *) reg [8:0] index_mem1 [0:4095];
    reg [8:0] index_mem0_q;
    reg [8:0] index_mem1_q;

    reg [2:0]  state_r [0:20];
    reg        authority_r [0:20];
    reg [31:0] token_r [0:20];
    reg [15:0] generation_r [0:20];
    reg [31:0] image_epoch_r [0:20];
    reg [3:0]  stage_id_r [0:20];
    reg [1:0]  logical_branch_r [0:20];
    reg [31:0] context_generation_r [0:20];
    reg [31:0] producer_ticket_r [0:20];
    reg [31:0] cancellation_epoch_r [0:20];
    reg [31:0] installed_stop_epoch_r [0:20];
    reg [8:0]  domain_bound_r [0:20];
    reg [8:0]  active_count_r [0:20];
    reg [8:0]  last_index_r [0:20];
    reg        last_valid_r [0:20];
    reg [15:0] terminal_tag_r [0:20];
    reg        event_retired_r [0:20];
    reg [1:0]  read_ref_count_r [0:20];

    reg        ref0_valid_r [0:20];
    reg [31:0] ref0_token_r [0:20];
    reg [2:0]  ref0_owner_kind_r [0:20];
    reg [31:0] ref0_owner_token_r [0:20];
    reg [1:0]  ref0_phase_r [0:20];
    reg        ref1_valid_r [0:20];
    reg [31:0] ref1_token_r [0:20];
    reg [2:0]  ref1_owner_kind_r [0:20];
    reg [31:0] ref1_owner_token_r [0:20];
    reg [1:0]  ref1_phase_r [0:20];

    reg [31:0] next_list_token;
    reg [31:0] next_reference_token;
    reg [4:0]  allocation_rr_slot;
    reg         list_token_exhausted;
    reg         reference_token_exhausted;
    reg [20:0] slot_generation_exhausted;
    reg         open_response_retired;

    reg [4:0] closing_slot_r;
    reg [15:0] closing_tag_r;
    reg [7:0] closing_status_r;

    reg [7:0]  installed_stop_code;
    reg [31:0] installed_stop_epoch;
    reg         installed_stop_data_untrusted;
    reg         stop_response_retired;
    reg [15:0]  stop_tag_r;

    reg [7:0]  producer_selected_status;
    reg [31:0] producer_selected_detail;

    reg [1:0] read_state_r [0:1];
    reg        read_kind_r [0:1];
    reg [7:0]  read_status_r [0:1];
    reg [4:0]  read_slot_locator_r [0:1];
    reg [31:0] read_list_token_r [0:1];
    reg [15:0] read_list_generation_r [0:1];
    reg [31:0] read_image_epoch_r [0:1];
    reg [3:0]  read_stage_id_r [0:1];
    reg [1:0]  read_logical_branch_r [0:1];
    reg [31:0] read_context_generation_r [0:1];
    reg [31:0] read_producer_ticket_r [0:1];
    reg [31:0] read_cancellation_epoch_r [0:1];
    reg [31:0] read_stop_epoch_r [0:1];
    reg [8:0]  read_domain_bound_r [0:1];
    reg [8:0]  read_active_count_r [0:1];
    reg [15:0] read_terminal_tag_r [0:1];
    reg [2:0]  read_list_state_r [0:1];
    reg [1:0]  read_external_ref_count_r [0:1];
    reg [8:0]  read_source_index_r [0:1];
    reg        read_data_usable_r [0:1];
    reg [8:0]  read_ordinal_r [0:1];
    reg        read_last_r [0:1];
    reg        read_sealed_r [0:1];
    reg        read_causal_r [0:1];
    reg [31:0] read_external_ref_token_r [0:1];
    reg [15:0] read_tag_r [0:1];
    reg        read_reference_taken_r [0:1];
    reg        read_ram_select_r [0:1];

    reg read_head;
    reg read_tail;
    reg [1:0] read_count_r;
    reg read_result_pending;
    reg read_result_slot;


    integer i;
    integer scan_offset;
    integer scan_index;
    reg alloc_scan_found;
    reg [4:0] alloc_scan_slot;
    reg [5:0] ext_count_comb;
    reg [1:0] read_ref_total_comb;
    reg [4:0] free_count_comb;
    reg [4:0] allocatable_free_count_comb;
    reg [4:0] error_count_comb;
    reg all_slots_free_comb;
    reg all_stop_slots_terminal_comb;
    reg store_image_valid_comb;
    reg [31:0] store_image_epoch_comb;
    reg internal_fault_comb;
    reg [4:0] internal_fault_slot_comb;
    reg [3:0] internal_fault_id_comb;
    reg [1:0] occupied_read_slots_comb;
    reg [1:0] reference_read_slots_comb;
    reg [1:0] wait_read_slots_comb;
    reg [1:0] physical_read_refs_comb [0:20];

    wire mgmt_slot_valid = (mgmt_req_slot_locator < 5'd21);
    wire [4:0] mgmt_slot_safe = mgmt_slot_valid ? mgmt_req_slot_locator : 5'd0;
    wire read_slot_valid = (read_req_slot_locator < 5'd21);
    wire [4:0] read_slot_safe = read_slot_valid ? read_req_slot_locator : 5'd0;
    wire [4:0] internal_slot_safe =
        (internal_fault_slot_comb < 5'd21) ? internal_fault_slot_comb : 5'd0;
    wire current_producer_slot_in_range =
        (current_producer_slot < 5'd21);
    wire [4:0] current_producer_slot_safe =
        current_producer_slot_in_range ? current_producer_slot : 5'd0;

    wire [1:0] mgmt_ext_count =
        {1'b0, ref0_valid_r[mgmt_slot_safe]} +
        {1'b0, ref1_valid_r[mgmt_slot_safe]};
    wire [1:0] read_ext_count =
        {1'b0, ref0_valid_r[read_slot_safe]} +
        {1'b0, ref1_valid_r[read_slot_safe]};

    wire mgmt_list_identity_exact = mgmt_slot_valid &&
        authority_r[mgmt_slot_safe] &&
        generation_r[mgmt_slot_safe] == mgmt_req_list_generation &&
        token_r[mgmt_slot_safe] == mgmt_req_list_token &&
        image_epoch_r[mgmt_slot_safe] == mgmt_req_image_epoch &&
        stage_id_r[mgmt_slot_safe] == mgmt_req_stage_id &&
        logical_branch_r[mgmt_slot_safe] == mgmt_req_logical_branch &&
        context_generation_r[mgmt_slot_safe] == mgmt_req_context_generation &&
        producer_ticket_r[mgmt_slot_safe] == mgmt_req_producer_sequence_ticket &&
        cancellation_epoch_r[mgmt_slot_safe] == mgmt_req_cancellation_epoch;

    wire read_list_identity_exact = read_slot_valid &&
        authority_r[read_slot_safe] &&
        generation_r[read_slot_safe] == read_req_list_generation &&
        token_r[read_slot_safe] == read_req_list_token &&
        image_epoch_r[read_slot_safe] == read_req_image_epoch &&
        stage_id_r[read_slot_safe] == read_req_stage_id &&
        logical_branch_r[read_slot_safe] == read_req_logical_branch &&
        context_generation_r[read_slot_safe] == read_req_context_generation &&
        producer_ticket_r[read_slot_safe] == read_req_producer_sequence_ticket &&
        cancellation_epoch_r[read_slot_safe] == read_req_cancellation_epoch;

    wire mgmt_ref0_exact = ref0_valid_r[mgmt_slot_safe] &&
        ref0_token_r[mgmt_slot_safe] == mgmt_req_ref_token &&
        ref0_owner_kind_r[mgmt_slot_safe] == mgmt_req_ref_owner_kind &&
        ref0_owner_token_r[mgmt_slot_safe] == mgmt_req_ref_owner_token &&
        ref0_phase_r[mgmt_slot_safe] == mgmt_req_ref_phase;
    wire mgmt_ref1_exact = ref1_valid_r[mgmt_slot_safe] &&
        ref1_token_r[mgmt_slot_safe] == mgmt_req_ref_token &&
        ref1_owner_kind_r[mgmt_slot_safe] == mgmt_req_ref_owner_kind &&
        ref1_owner_token_r[mgmt_slot_safe] == mgmt_req_ref_owner_token &&
        ref1_phase_r[mgmt_slot_safe] == mgmt_req_ref_phase;
    wire mgmt_ref_exact = mgmt_ref0_exact || mgmt_ref1_exact;
    wire mgmt_exact_ref_release = mgmt_req_opcode == OP_REF_RELEASE &&
        mgmt_list_identity_exact && mgmt_ref_exact &&
        ((!stop_pending && mgmt_req_stop_epoch == 32'd0) ||
         (stop_pending && mgmt_req_stop_epoch == installed_stop_epoch));

    wire read_live_reference =
        (ref0_valid_r[read_slot_safe] &&
         ref0_token_r[read_slot_safe] == read_req_external_ref_token) ||
        (ref1_valid_r[read_slot_safe] &&
         ref1_token_r[read_slot_safe] == read_req_external_ref_token);

    wire completion_fire = completion_valid && completion_ready;
    wire mgmt_event_effectively_retired = event_retired_r[mgmt_slot_safe] ||
        (completion_fire && completion_sealed &&
         completion_slot_locator == mgmt_slot_safe);
    wire read_event_effectively_retired = event_retired_r[read_slot_safe] ||
        (completion_fire && completion_sealed &&
         completion_slot_locator == read_slot_safe);

    wire pre_edge_sink_authority = current_producer_valid &&
        current_producer_slot_in_range &&
        producer_started && producer_obligation &&
        (state_r[current_producer_slot_safe] == STATE_OPEN ||
         state_r[current_producer_slot_safe] == STATE_POISON_DRAIN ||
         state_r[current_producer_slot_safe] == STATE_CANCEL_PENDING);
    assign active_cmd_ready = rst_n && pre_edge_sink_authority;
    wire active_fire = active_cmd_valid && active_cmd_ready;
    wire unexpected_active_cmd = rst_n && active_cmd_valid &&
        !pre_edge_sink_authority;
    // A compliant ready/valid source may hold valid while ready is low.  Only
    // the first observation edge takes absolute arbitration priority; after
    // that, the registered local-fault fence permits owner stop and exact
    // causal cleanup instead of deadlocking behind the held offender.
    wire new_unexpected_active_cmd = unexpected_active_cmd &&
        !local_fault_pending;

    reg [7:0] active_error_code_comb;
    reg active_error_comb;
    always @* begin
        active_error_comb = 1'b0;
        active_error_code_comb = STATUS_OK;
        if (active_fire && state_r[current_producer_slot_safe] == STATE_OPEN) begin
            if (!active_cmd_write && !active_cmd_finalize) begin
                active_error_comb = 1'b1;
                active_error_code_comb = ERR_BAD_COMMAND_ENCODING;
            end else if (active_cmd_write &&
                         (active_count_r[current_producer_slot_safe] >= 9'd320 ||
                          active_count_r[current_producer_slot_safe] >=
                              domain_bound_r[current_producer_slot_safe])) begin
                active_error_comb = 1'b1;
                active_error_code_comb = ERR_CAPACITY_OVERFLOW;
            end else if (active_cmd_index >= domain_bound_r[current_producer_slot_safe]) begin
                active_error_comb = 1'b1;
                active_error_code_comb = ERR_INDEX_OUT_OF_RANGE;
            end else if (active_cmd_write && last_valid_r[current_producer_slot_safe] &&
                         active_cmd_index <= last_index_r[current_producer_slot_safe]) begin
                active_error_comb = 1'b1;
                active_error_code_comb = ERR_UNORDERED_INDEX;
            end else if ((active_cmd_finalize &&
                          active_cmd_index != domain_bound_r[current_producer_slot_safe] - 1'b1) ||
                         (!active_cmd_finalize && active_cmd_write &&
                          active_cmd_index == domain_bound_r[current_producer_slot_safe] - 1'b1)) begin
                active_error_comb = 1'b1;
                active_error_code_comb = ERR_EARLY_FINALIZE;
            end
        end
    end

    wire same_edge_fatal_detect = active_error_comb || internal_fault_comb;
    wire stop_request_mode_valid =
        ((!stop_req_is_fatal && !stop_req_data_untrusted &&
          stop_req_code == ERR_ABORTED) ||
         (stop_req_is_fatal && stop_req_code != STATUS_OK &&
          stop_req_code != ERR_ABORTED));
    wire stop_request_image_valid = !store_image_valid_comb ||
        store_image_epoch_comb == stop_req_image_epoch;
    wire stop_request_epoch_valid =
        stop_req_cancellation_epoch != 32'd0 &&
        stop_req_cancellation_epoch > last_stop_epoch;
    wire stop_request_proof_valid = stop_req_data_untrusted ||
        stop_req_causal_producers_stopped;
    wire stop_request_well_formed = stop_request_mode_valid &&
        stop_request_image_valid && stop_request_epoch_valid &&
        stop_request_proof_valid;
    assign stop_req_ready = rst_n && !new_unexpected_active_cmd &&
        !stop_rsp_valid && !stop_pending;
    wire stop_fire = stop_req_valid && stop_req_ready;
    wire stop_commit = stop_fire && stop_request_well_formed;
    wire [7:0] stop_selected_code = internal_fault_comb ?
        ERR_INTERNAL_STATE :
        (local_error_valid ? local_error_code :
         ((active_error_comb && !stop_req_is_fatal) ?
            active_error_code_comb : stop_req_code));
    wire [7:0] unexpected_active_code =
        (completion_slot_reserved && active_cmd_finalize) ?
            ERR_DUPLICATE_FINALIZE : ERR_LOCAL_PROTOCOL;
    // Status for causal cleanup that has not yet materialized.  This encodes
    // the approved first-error order while leaving held responses immutable.
    wire [7:0] cleanup_terminal_status = internal_fault_comb ?
        ERR_INTERNAL_STATE :
        ((stop_pending && installed_stop_code != ERR_ABORTED) ?
            installed_stop_code :
         (local_error_valid ? local_error_code :
          ((stop_commit && stop_req_is_fatal) ? stop_req_code :
           (active_error_comb ? active_error_code_comb :
            (new_unexpected_active_cmd ? unexpected_active_code :
             (stop_commit ? stop_req_code :
              (stop_pending ? installed_stop_code : STATUS_OK)))))));

    wire start_exact = current_producer_valid && !producer_started &&
        open_response_retired && mgmt_list_identity_exact &&
        mgmt_req_slot_locator == current_producer_slot &&
        mgmt_req_list_token == current_producer_token &&
        mgmt_req_list_generation == current_producer_generation &&
        mgmt_req_stop_epoch == 32'd0 &&
        mgmt_req_pe_recovery_safe;

    assign start_partner_valid = rst_n && mgmt_req_valid &&
        mgmt_req_opcode == OP_START && start_exact && !mgmt_rsp_valid &&
        !closing_busy && !stop_pending && !stop_fire &&
        !local_fault_pending && !same_edge_fatal_detect &&
        !new_unexpected_active_cmd;
    assign start_partner_slot_locator = start_partner_valid ?
        current_producer_slot : 5'd0;
    assign start_partner_list_token = start_partner_valid ?
        current_producer_token : 32'd0;
    assign start_partner_list_generation = start_partner_valid ?
        current_producer_generation : 16'd0;
    assign start_partner_image_epoch = start_partner_valid ?
        image_epoch_r[current_producer_slot_safe] : 32'd0;
    assign start_partner_stage_id = start_partner_valid ?
        stage_id_r[current_producer_slot_safe] : 4'd0;
    assign start_partner_logical_branch = start_partner_valid ?
        logical_branch_r[current_producer_slot_safe] : 2'd0;
    assign start_partner_context_generation = start_partner_valid ?
        context_generation_r[current_producer_slot_safe] : 32'd0;
    assign start_partner_producer_sequence_ticket = start_partner_valid ?
        producer_ticket_r[current_producer_slot_safe] : 32'd0;
    assign start_partner_cancellation_epoch = start_partner_valid ?
        cancellation_epoch_r[current_producer_slot_safe] : 32'd0;
    assign start_partner_tag = start_partner_valid ? mgmt_req_tag : 16'd0;

    wire mgmt_fire = mgmt_req_valid && mgmt_req_ready;
    wire read_rsp_fire = read_rsp_valid && read_rsp_ready;
    wire read_credit_available = (read_count_r < 2) || read_rsp_fire;
    wire read_targets_exact_closing = read_list_identity_exact &&
        state_r[read_slot_safe] == STATE_CLOSING;
    assign read_req_ready = rst_n && read_credit_available &&
        !new_unexpected_active_cmd && !stop_fire && !same_edge_fatal_detect &&
        !mgmt_fire && !read_targets_exact_closing &&
        (!local_fault_pending ||
         (stop_pending && installed_stop_data_untrusted) ||
         (read_req_causal_continuation && !reset_required)) &&
        (!stop_pending ||
         installed_stop_data_untrusted || read_req_causal_continuation);
    wire read_fire = read_req_valid && read_req_ready;

    assign completion_event_pending = completion_valid;
    assign management_busy = mgmt_rsp_valid || closing_busy;
    assign read_outstanding = read_count_r;
    assign read_pipeline_busy = (read_count_r != 0);

    assign read_rsp_valid = (read_count_r != 0) &&
        (read_state_r[read_head] == READ_OUTPUT);
    assign read_rsp_kind = read_rsp_valid ? read_kind_r[read_head] : 1'b0;
    assign read_rsp_status = read_rsp_valid ? read_status_r[read_head] : 8'd0;
    assign read_rsp_slot_locator = read_rsp_valid ? read_slot_locator_r[read_head] : 5'd0;
    assign read_rsp_list_token = read_rsp_valid ? read_list_token_r[read_head] : 32'd0;
    assign read_rsp_list_generation = read_rsp_valid ? read_list_generation_r[read_head] : 16'd0;
    assign read_rsp_image_epoch = read_rsp_valid ? read_image_epoch_r[read_head] : 32'd0;
    assign read_rsp_stage_id = read_rsp_valid ? read_stage_id_r[read_head] : 4'd0;
    assign read_rsp_logical_branch = read_rsp_valid ? read_logical_branch_r[read_head] : 2'd0;
    assign read_rsp_context_generation = read_rsp_valid ? read_context_generation_r[read_head] : 32'd0;
    assign read_rsp_producer_sequence_ticket = read_rsp_valid ? read_producer_ticket_r[read_head] : 32'd0;
    assign read_rsp_cancellation_epoch = read_rsp_valid ? read_cancellation_epoch_r[read_head] : 32'd0;
    assign read_rsp_stop_epoch = read_rsp_valid ? read_stop_epoch_r[read_head] : 32'd0;
    assign read_rsp_domain_bound = read_rsp_valid ? read_domain_bound_r[read_head] : 9'd0;
    assign read_rsp_active_count = read_rsp_valid ? read_active_count_r[read_head] : 9'd0;
    assign read_rsp_terminal_tag = read_rsp_valid ? read_terminal_tag_r[read_head] : 16'd0;
    assign read_rsp_state = read_rsp_valid ? read_list_state_r[read_head] : 3'd0;
    assign read_rsp_external_ref_count = read_rsp_valid ? read_external_ref_count_r[read_head] : 2'd0;
    assign read_rsp_source_index = read_rsp_valid ? read_source_index_r[read_head] : 9'd0;
    assign read_rsp_data_usable = read_rsp_valid ? read_data_usable_r[read_head] : 1'b0;
    assign read_rsp_ordinal = read_rsp_valid ? read_ordinal_r[read_head] : 9'd0;
    assign read_rsp_last = read_rsp_valid ? read_last_r[read_head] : 1'b0;
    assign read_rsp_sealed = read_rsp_valid ? read_sealed_r[read_head] : 1'b0;
    assign read_rsp_causal_continuation = read_rsp_valid ? read_causal_r[read_head] : 1'b0;
    assign read_rsp_external_ref_token = read_rsp_valid ? read_external_ref_token_r[read_head] : 32'd0;
    assign read_rsp_tag = read_rsp_valid ? read_tag_r[read_head] : 16'd0;

    genvar g;
    generate
        for (g = 0; g < 21; g = g + 1) begin : GEN_SLOT_EVIDENCE
            assign slot_state[g*3 +: 3] = state_r[g];
            assign slot_authority_valid[g] = authority_r[g];
            assign slot_external_ref_count[g*2 +: 2] =
                {1'b0, ref0_valid_r[g]} + {1'b0, ref1_valid_r[g]};
            assign slot_read_ref_count[g*2 +: 2] = read_ref_count_r[g];
        end
    endgenerate

    function [11:0] payload_address;
        input [4:0] slot_number;
        input [8:0] ordinal;
        reg [4:0] local_slot;
        begin
            if (slot_number < 5'd11)
                local_slot = slot_number;
            else
                local_slot = slot_number - 5'd11;
            payload_address = {local_slot, 8'd0} +
                              {local_slot, 6'd0} + ordinal;
        end
    endfunction

    function producer_stage_is_projection;
        input [3:0] stage_value;
        begin
            producer_stage_is_projection = stage_value == 4'd2 ||
                stage_value == 4'd5 || stage_value == 4'd8 ||
                stage_value == 4'd11;
        end
    endfunction

    function producer_tuple_valid;
        input [3:0] stage_value;
        input [1:0] branch_value;
        input [8:0] domain_value;
        begin
            producer_tuple_valid =
                (((stage_value == 4'd0 || stage_value == 4'd1) &&
                  branch_value == 2'd0 && domain_value == 9'd320) ||
                 ((stage_value == 4'd3 || stage_value == 4'd4) &&
                  branch_value == 2'd0 && domain_value == 9'd224) ||
                 ((stage_value == 4'd6 || stage_value == 4'd7) &&
                  branch_value == 2'd1 && domain_value == 9'd224) ||
                 ((stage_value == 4'd9 || stage_value == 4'd10) &&
                  branch_value == 2'd2 && domain_value == 9'd224));
        end
    endfunction

    function [31:0] active_error_detail;
        input [4:0] slot_value;
        input write_value;
        input finalize_value;
        input [8:0] index_value;
        input [8:0] count_value;
        input [15:0] tag_value;
        begin
            active_error_detail = {4'd2, slot_value, write_value,
                finalize_value, index_value, count_value, tag_value[2:0]};
        end
    endfunction

    function [31:0] request_error_detail;
        input [3:0] source_value;
        input [2:0] subtype_value;
        input [4:0] slot_value;
        input [15:0] tag_value;
        input [3:0] field_value;
        begin
            request_error_detail = {source_value, subtype_value, slot_value,
                tag_value, field_value};
        end
    endfunction

    function [31:0] internal_error_detail;
        input [3:0] invariant_value;
        input [4:0] slot_value;
        input [8:0] count_value;
        input [1:0] external_count_value;
        input [1:0] read_count_value;
        input [2:0] state_value;
        input [2:0] summary_value;
        begin
            internal_error_detail = {4'd7, invariant_value, slot_value,
                count_value, external_count_value, read_count_value,
                state_value, summary_value};
        end
    endfunction

    function ref_transfer_is_legal;
        input [2:0] old_kind;
        input [1:0] old_phase;
        input [2:0] new_kind;
        input [1:0] new_phase;
        begin
            ref_transfer_is_legal =
                (old_kind == 3'd4 && old_phase == REF_TEMPORARY &&
                 (new_kind == 3'd1 || new_kind == 3'd2) &&
                 new_phase == REF_PENDING) ||
                ((old_kind == 3'd1 || old_kind == 3'd2) &&
                 old_phase == REF_PENDING && new_kind == old_kind &&
                 new_phase == REF_PERSISTENT) ||
                (old_kind == 3'd5 && old_phase == REF_TEMPORARY &&
                 new_kind == 3'd3 && new_phase == REF_PERSISTENT);
        end
    endfunction

    function ref_acquire_is_legal;
        input [2:0] owner_kind;
        input [1:0] owner_phase;
        begin
            ref_acquire_is_legal =
                ((owner_kind == 3'd4 || owner_kind == 3'd5) &&
                 owner_phase == REF_TEMPORARY) ||
                (owner_kind == 3'd6 && owner_phase == REF_PERSISTENT);
        end
    endfunction

    wire open_nonzero_identity = mgmt_req_image_epoch != 32'd0 &&
        mgmt_req_context_generation != 32'd0 &&
        mgmt_req_producer_sequence_ticket != 32'd0 &&
        mgmt_req_cancellation_epoch != 32'd0 &&
        mgmt_req_stop_epoch == 32'd0;
    wire open_structure_valid = producer_tuple_valid(
        mgmt_req_stage_id, mgmt_req_logical_branch,
        mgmt_req_domain_bound) && open_nonzero_identity;

    wire start_identity_without_retire = current_producer_valid &&
        !producer_started && mgmt_list_identity_exact &&
        mgmt_req_slot_locator == current_producer_slot &&
        mgmt_req_list_token == current_producer_token &&
        mgmt_req_list_generation == current_producer_generation &&
        mgmt_req_stop_epoch == 32'd0;

    always @* begin
        alloc_scan_found = 1'b0;
        alloc_scan_slot = 5'd0;
        for (scan_offset = 1; scan_offset <= 21; scan_offset = scan_offset + 1) begin
            scan_index = allocation_rr_slot + scan_offset;
            if (scan_index >= 21)
                scan_index = scan_index - 21;
            if (!alloc_scan_found && state_r[scan_index] == STATE_FREE &&
                !slot_generation_exhausted[scan_index]) begin
                alloc_scan_found = 1'b1;
                alloc_scan_slot = scan_index[4:0];
            end
        end
    end

    function ref_record_is_legal;
        input [2:0] owner_kind;
        input [1:0] owner_phase;
        begin
            ref_record_is_legal =
                ((owner_kind == 3'd4 || owner_kind == 3'd5) &&
                 owner_phase == REF_TEMPORARY) ||
                ((owner_kind == 3'd1 || owner_kind == 3'd2) &&
                 (owner_phase == REF_PENDING ||
                  owner_phase == REF_PERSISTENT)) ||
                ((owner_kind == 3'd3 || owner_kind == 3'd6) &&
                 owner_phase == REF_PERSISTENT);
        end
    endfunction

    always @* begin
        free_count_comb = 5'd0;
        allocatable_free_count_comb = 5'd0;
        error_count_comb = 5'd0;
        ext_count_comb = 6'd0;
        read_ref_total_comb = 2'd0;
        all_slots_free_comb = 1'b1;
        all_stop_slots_terminal_comb = 1'b1;
        store_image_valid_comb = 1'b0;
        store_image_epoch_comb = 32'd0;
        occupied_read_slots_comb = 2'd0;
        reference_read_slots_comb = 2'd0;
        wait_read_slots_comb = 2'd0;
        for (i = 0; i < 21; i = i + 1) begin
            physical_read_refs_comb[i] = 2'd0;
            if (state_r[i] == STATE_FREE)
                free_count_comb = free_count_comb + 1'b1;
            else
                all_slots_free_comb = 1'b0;
            if (state_r[i] == STATE_FREE &&
                !slot_generation_exhausted[i])
                allocatable_free_count_comb = allocatable_free_count_comb + 1'b1;
            if (state_r[i] == STATE_ERROR)
                error_count_comb = error_count_comb + 1'b1;
            ext_count_comb = ext_count_comb + ref0_valid_r[i] + ref1_valid_r[i];
            read_ref_total_comb = read_ref_total_comb + read_ref_count_r[i];
            if (authority_r[i] && installed_stop_epoch_r[i] != 32'd0 &&
                state_r[i] != STATE_ERROR && state_r[i] != STATE_FREE &&
                state_r[i] != STATE_CLOSING)
                all_stop_slots_terminal_comb = 1'b0;
            if (!store_image_valid_comb && authority_r[i]) begin
                store_image_valid_comb = 1'b1;
                store_image_epoch_comb = image_epoch_r[i];
            end
        end
        for (i = 0; i < 2; i = i + 1) begin
            if (read_state_r[i] != READ_FREE)
                occupied_read_slots_comb = occupied_read_slots_comb + 1'b1;
            if (read_state_r[i] == READ_WAIT)
                wait_read_slots_comb = wait_read_slots_comb + 1'b1;
            if (read_state_r[i] != READ_FREE &&
                read_reference_taken_r[i]) begin
                reference_read_slots_comb = reference_read_slots_comb + 1'b1;
                if (read_slot_locator_r[i] < 5'd21)
                    physical_read_refs_comb[read_slot_locator_r[i]] =
                        physical_read_refs_comb[read_slot_locator_r[i]] + 1'b1;
            end
        end

        free_slot_count = free_count_comb;
        unreleased_error_slot_count = error_count_comb;
        external_reference_total = ext_count_comb;
        read_reference_total = read_ref_total_comb;

        stop_drain_complete = stop_pending && !producer_obligation &&
            !completion_slot_reserved && !completion_valid &&
            read_count_r == 0 && read_ref_total_comb == 0 &&
            ext_count_comb == 0 && !mgmt_rsp_valid && !closing_busy &&
            !fault_event_valid && all_stop_slots_terminal_comb;

        store_quiescent = all_slots_free_comb && !current_producer_valid &&
            !producer_obligation && !completion_slot_reserved &&
            !completion_valid && !mgmt_rsp_valid && !closing_busy &&
            read_count_r == 0 && read_ref_total_comb == 0 &&
            ext_count_comb == 0 && !stop_pending && !stop_rsp_valid &&
            !local_fault_pending && !fault_event_valid;
    end

    always @* begin
        internal_fault_comb = 1'b0;
        internal_fault_slot_comb = current_producer_valid ?
            current_producer_slot : 5'd31;
        internal_fault_id_comb = 4'd0;
        if (read_count_r == 2'd3 ||
            occupied_read_slots_comb != read_count_r) begin
            internal_fault_comb = 1'b1;
            internal_fault_id_comb = 4'd1;
        end else if (read_result_pending &&
                     read_state_r[read_result_slot] != READ_WAIT) begin
            internal_fault_comb = 1'b1;
            internal_fault_id_comb = 4'd2;
        end else if (reference_read_slots_comb != read_ref_total_comb) begin
            internal_fault_comb = 1'b1;
            internal_fault_id_comb = 4'd3;
        end else if (wait_read_slots_comb != {1'b0, read_result_pending}) begin
            internal_fault_comb = 1'b1;
            internal_fault_id_comb = 4'd12;
        end else if ((read_count_r == 0 && read_head != read_tail) ||
                     (read_count_r == 1 && read_head == read_tail) ||
                     (read_count_r == 2 && read_head != read_tail) ||
                     (read_count_r != 0 &&
                      read_state_r[read_head] == READ_FREE)) begin
            internal_fault_comb = 1'b1;
            internal_fault_id_comb = 4'd13;
        end else if (producer_obligation &&
                     (!current_producer_valid || !producer_started)) begin
            internal_fault_comb = 1'b1;
            internal_fault_id_comb = 4'd4;
        end else if (current_producer_valid &&
                     (current_producer_slot >= 5'd21 ||
                      !authority_r[current_producer_slot_safe] ||
                      current_producer_token != token_r[current_producer_slot_safe] ||
                      current_producer_generation !=
                          generation_r[current_producer_slot_safe] ||
                      (state_r[current_producer_slot_safe] != STATE_OPEN &&
                       state_r[current_producer_slot_safe] != STATE_POISON_DRAIN &&
                       state_r[current_producer_slot_safe] != STATE_CANCEL_PENDING))) begin
            internal_fault_comb = 1'b1;
            internal_fault_id_comb = 4'd5;
        end else if (completion_valid && !completion_slot_reserved) begin
            internal_fault_comb = 1'b1;
            internal_fault_id_comb = 4'd6;
        end
        for (i = 0; i < 21; i = i + 1) begin
            if (!internal_fault_comb &&
                read_ref_count_r[i] != physical_read_refs_comb[i]) begin
                internal_fault_comb = 1'b1;
                internal_fault_slot_comb = i[4:0];
                internal_fault_id_comb = 4'd7;
            end else if (!internal_fault_comb && authority_r[i] &&
                         (active_count_r[i] > 9'd320 ||
                          active_count_r[i] > domain_bound_r[i])) begin
                internal_fault_comb = 1'b1;
                internal_fault_slot_comb = i[4:0];
                internal_fault_id_comb = 4'd8;
            end else if (!internal_fault_comb &&
                         ((state_r[i] == STATE_FREE && authority_r[i]) ||
                          (state_r[i] != STATE_FREE && !authority_r[i]))) begin
                internal_fault_comb = 1'b1;
                internal_fault_slot_comb = i[4:0];
                internal_fault_id_comb = 4'd9;
            end else if (!internal_fault_comb &&
                         state_r[i] == STATE_REFERENCED &&
                         !ref0_valid_r[i] && !ref1_valid_r[i]) begin
                internal_fault_comb = 1'b1;
                internal_fault_slot_comb = i[4:0];
                internal_fault_id_comb = 4'd10;
            end else if (!internal_fault_comb &&
                         state_r[i] == STATE_SEALED &&
                         (ref0_valid_r[i] || ref1_valid_r[i])) begin
                internal_fault_comb = 1'b1;
                internal_fault_slot_comb = i[4:0];
                internal_fault_id_comb = 4'd11;
            end else if (!internal_fault_comb &&
                         (ref0_valid_r[i] || ref1_valid_r[i]) &&
                         state_r[i] != STATE_REFERENCED) begin
                internal_fault_comb = 1'b1;
                internal_fault_slot_comb = i[4:0];
                internal_fault_id_comb = 4'd14;
            end else if (!internal_fault_comb && ref0_valid_r[i] &&
                         (ref0_token_r[i] == 32'd0 ||
                          ref0_owner_token_r[i] == 32'd0 ||
                          !ref_record_is_legal(ref0_owner_kind_r[i],
                                               ref0_phase_r[i]))) begin
                internal_fault_comb = 1'b1;
                internal_fault_slot_comb = i[4:0];
                internal_fault_id_comb = 4'd15;
            end else if (!internal_fault_comb && ref1_valid_r[i] &&
                         (ref1_token_r[i] == 32'd0 ||
                          ref1_owner_token_r[i] == 32'd0 ||
                          !ref_record_is_legal(ref1_owner_kind_r[i],
                                               ref1_phase_r[i]))) begin
                internal_fault_comb = 1'b1;
                internal_fault_slot_comb = i[4:0];
                internal_fault_id_comb = 4'd15;
            end else if (!internal_fault_comb && ref0_valid_r[i] &&
                         ref1_valid_r[i] &&
                         (ref0_token_r[i] == ref1_token_r[i] ||
                          (ref0_owner_kind_r[i] == ref1_owner_kind_r[i] &&
                           ref0_owner_token_r[i] ==
                               ref1_owner_token_r[i]))) begin
                internal_fault_comb = 1'b1;
                internal_fault_slot_comb = i[4:0];
                internal_fault_id_comb = 4'd15;
            end
        end
    end

    always @* begin
        mgmt_req_ready = 1'b0;
        if (rst_n && !mgmt_rsp_valid && !closing_busy &&
            !new_unexpected_active_cmd && !stop_fire &&
            (!same_edge_fatal_detect || mgmt_exact_ref_release)) begin
            if (local_fault_pending || stop_pending) begin
                if (mgmt_req_opcode == OP_REF_RELEASE)
                    mgmt_req_ready = 1'b1;
                else if (mgmt_req_opcode == OP_LIST_RELEASE &&
                         stop_pending && stop_response_retired &&
                         !reset_required)
                    mgmt_req_ready = 1'b1;
                else if (mgmt_req_opcode == OP_CLEAR_ERROR &&
                         !reset_required)
                    mgmt_req_ready = 1'b1;
            end else begin
                case (mgmt_req_opcode)
                    OP_OPEN: begin
                        if (!open_structure_valid)
                            mgmt_req_ready = 1'b1;
                        else if (!mgmt_req_pe_recovery_safe)
                            mgmt_req_ready = 1'b0;
                        else if (list_token_exhausted)
                            mgmt_req_ready = 1'b1;
                        else if (!allocation_candidate_valid &&
                                 free_count_comb != 0 &&
                                 allocatable_free_count_comb == 0)
                            mgmt_req_ready = 1'b1;
                        else if (!current_producer_valid &&
                                 !completion_slot_reserved &&
                                 allocation_candidate_valid &&
                                 state_r[allocation_candidate_slot] == STATE_FREE)
                            mgmt_req_ready = 1'b1;
                    end
                    OP_START: begin
                        if (start_identity_without_retire &&
                            !mgmt_req_pe_recovery_safe)
                            mgmt_req_ready = 1'b0;
                        else if (start_identity_without_retire &&
                                 !open_response_retired)
                            mgmt_req_ready = 1'b0;
                        else if (start_exact)
                            mgmt_req_ready = start_partner_ready;
                        else
                            mgmt_req_ready = 1'b1;
                    end
                    default: mgmt_req_ready = 1'b1;
                endcase
            end
        end
    end

    reg [7:0] read_accept_status;
    reg read_accept_take_reference;
    reg read_accept_issue_ram;
    reg read_accept_data_usable;
    reg read_accept_sealed;
    always @* begin
        read_accept_status = STATUS_OK;
        read_accept_take_reference = 1'b0;
        read_accept_issue_ram = 1'b0;
        read_accept_data_usable = 1'b0;
        read_accept_sealed = 1'b0;

        if (stop_pending && installed_stop_data_untrusted) begin
            read_accept_status = installed_stop_code;
            read_accept_data_usable = 1'b0;
        end else if (!read_slot_valid)
            read_accept_status = ERR_BAD_SLOT;
        else if (generation_r[read_slot_safe] != read_req_list_generation)
            read_accept_status = ERR_STALE_GENERATION;
        else if (!authority_r[read_slot_safe] ||
                 token_r[read_slot_safe] != read_req_list_token)
            read_accept_status = ERR_STALE_TOKEN;
        else if (!read_list_identity_exact)
            read_accept_status = ERR_BAD_IDENTITY;
        else if ((state_r[read_slot_safe] != STATE_SEALED &&
                  state_r[read_slot_safe] != STATE_REFERENCED) ||
                 !read_event_effectively_retired)
            read_accept_status = ERR_READ_UNSEALED;
        else if (!read_req_kind && read_req_ordinal != 9'd0)
            read_accept_status = ERR_BAD_ORDINAL;
        else if (read_req_kind &&
                 (active_count_r[read_slot_safe] == 9'd0 ||
                  read_req_ordinal >= active_count_r[read_slot_safe]))
            read_accept_status = ERR_BAD_ORDINAL;
        else if (!stop_pending && !local_fault_pending &&
                 read_req_causal_continuation &&
                 (read_req_stop_epoch != 32'd0 ||
                  read_req_external_ref_token == 32'd0 ||
                  !read_live_reference))
            read_accept_status = ERR_BAD_IDENTITY;
        else if (!stop_pending && !local_fault_pending &&
                 !read_req_causal_continuation &&
                 (read_req_stop_epoch != 32'd0 ||
                  (read_req_external_ref_token != 32'd0 &&
                   !read_live_reference)))
            read_accept_status = ERR_BAD_IDENTITY;
        else if (stop_pending &&
                 (!read_req_causal_continuation ||
                  read_req_stop_epoch != installed_stop_epoch ||
                  read_req_external_ref_token == 32'd0 ||
                  !read_live_reference))
            read_accept_status = ERR_BAD_IDENTITY;
        else if (local_fault_pending && !stop_pending &&
                 (!read_req_causal_continuation ||
                  read_req_stop_epoch != 32'd0 ||
                  read_req_external_ref_token == 32'd0 ||
                  !read_live_reference))
            read_accept_status = ERR_BAD_IDENTITY;
        else begin
            read_accept_take_reference = 1'b1;
            read_accept_sealed = 1'b1;
            if (stop_pending) begin
                read_accept_status = installed_stop_code;
                read_accept_data_usable = !installed_stop_data_untrusted;
                read_accept_issue_ram = read_req_kind &&
                    !installed_stop_data_untrusted;
            end else if (local_fault_pending) begin
                read_accept_status = local_error_code;
                read_accept_data_usable = !reset_required;
                read_accept_issue_ram = read_req_kind && !reset_required;
            end else begin
                read_accept_status = STATUS_OK;
                read_accept_data_usable = 1'b1;
                read_accept_issue_ram = read_req_kind;
            end
        end
    end

    wire payload_write_fire = active_fire && active_cmd_write &&
        state_r[current_producer_slot_safe] == STATE_OPEN && !active_error_comb &&
        !internal_fault_comb;
    wire payload_write_ram = (current_producer_slot >= 5'd11);
    wire [11:0] payload_write_addr = payload_address(
        current_producer_slot_safe,
        active_count_r[current_producer_slot_safe]);
    wire payload_read_fire = read_fire && read_accept_issue_ram;
    wire payload_read_ram = (read_slot_safe >= 5'd11);
    wire [11:0] payload_read_addr = payload_address(
        read_slot_safe, read_req_ordinal);

    always @(posedge clk) begin
        if (payload_write_fire && !payload_write_ram)
            index_mem0[payload_write_addr] <= active_cmd_index;
        if (payload_read_fire && !payload_read_ram)
            index_mem0_q <= index_mem0[payload_read_addr];
    end

    always @(posedge clk) begin
        if (payload_write_fire && payload_write_ram)
            index_mem1[payload_write_addr] <= active_cmd_index;
        if (payload_read_fire && payload_read_ram)
            index_mem1_q <= index_mem1[payload_read_addr];
    end

    task put_mgmt_response;
        input [7:0] status_value;
        input committed_value;
        input released_value;
        begin
            mgmt_rsp_valid <= 1'b1;
            mgmt_rsp_opcode <= mgmt_req_opcode;
            mgmt_rsp_status <= status_value;
            mgmt_rsp_committed <= committed_value;
            mgmt_rsp_released <= released_value;
            mgmt_rsp_slot_locator <= mgmt_req_slot_locator;
            mgmt_rsp_list_token <= mgmt_req_list_token;
            mgmt_rsp_list_generation <= mgmt_req_list_generation;
            mgmt_rsp_image_epoch <= mgmt_req_image_epoch;
            mgmt_rsp_stage_id <= mgmt_req_stage_id;
            mgmt_rsp_logical_branch <= mgmt_req_logical_branch;
            mgmt_rsp_context_generation <= mgmt_req_context_generation;
            mgmt_rsp_producer_sequence_ticket <=
                mgmt_req_producer_sequence_ticket;
            mgmt_rsp_domain_bound <= mgmt_req_domain_bound;
            mgmt_rsp_reserved_capacity <= 9'd0;
            mgmt_rsp_state <= mgmt_slot_valid ?
                state_r[mgmt_slot_safe] : STATE_FREE;
            mgmt_rsp_active_count <= mgmt_slot_valid ?
                active_count_r[mgmt_slot_safe] : 9'd0;
            mgmt_rsp_ref_token <= mgmt_req_ref_token;
            mgmt_rsp_ref_owner_kind <= mgmt_req_ref_owner_kind;
            mgmt_rsp_ref_owner_token <= mgmt_req_ref_owner_token;
            mgmt_rsp_ref_phase <= mgmt_req_ref_phase;
            mgmt_rsp_cancellation_epoch <= mgmt_req_cancellation_epoch;
            mgmt_rsp_stop_epoch <= stop_pending ? installed_stop_epoch : 32'd0;
            mgmt_rsp_tag <= mgmt_req_tag;
        end
    endtask

    task put_completion;
        input [7:0] status_value;
        input sealed_value;
        input [15:0] terminal_tag_value;
        input [31:0] detail_value;
        input [8:0] count_value;
        input [8:0] last_index_value;
        input last_valid_value;
        begin
            completion_valid <= 1'b1;
            completion_status <= status_value;
            completion_sealed <= sealed_value;
            completion_slot_locator <= current_producer_slot;
            completion_list_token <= current_producer_token;
            completion_list_generation <= current_producer_generation;
            completion_image_epoch <= image_epoch_r[current_producer_slot_safe];
            completion_stage_id <= stage_id_r[current_producer_slot_safe];
            completion_logical_branch <= logical_branch_r[current_producer_slot_safe];
            completion_context_generation <=
                context_generation_r[current_producer_slot_safe];
            completion_producer_sequence_ticket <=
                producer_ticket_r[current_producer_slot_safe];
            completion_cancellation_epoch <=
                cancellation_epoch_r[current_producer_slot_safe];
            completion_stop_epoch <= stop_pending ? installed_stop_epoch :
                (stop_commit ? stop_req_cancellation_epoch : 32'd0);
            completion_domain_bound <= domain_bound_r[current_producer_slot_safe];
            completion_active_count <= count_value;
            completion_last_committed_index <= last_index_value;
            completion_last_valid <= last_valid_value;
            completion_terminal_tag <= terminal_tag_value;
            completion_error_detail <= detail_value;
        end
    endtask

    task latch_local_fault;
        input [7:0] code_value;
        input [3:0] source_value;
        input [31:0] detail_value;
        input [4:0] slot_value;
        input reset_value;
        begin
            if (!local_error_valid) begin
                local_error_valid <= 1'b1;
                local_error_code <= code_value;
                local_error_source <= source_value;
                local_error_detail <= detail_value;
                local_error_slot_locator <= slot_value;
                if (slot_value < 5'd21 && authority_r[slot_value]) begin
                    local_error_list_token <= token_r[slot_value];
                    local_error_list_generation <= generation_r[slot_value];
                    local_error_image_epoch <= image_epoch_r[slot_value];
                    local_error_stage_id <= stage_id_r[slot_value];
                    local_error_logical_branch <= logical_branch_r[slot_value];
                    local_error_context_generation <= context_generation_r[slot_value];
                    local_error_producer_sequence_ticket <= producer_ticket_r[slot_value];
                    local_error_cancellation_epoch <= cancellation_epoch_r[slot_value];
                    local_error_stop_epoch <= stop_commit ?
                        stop_req_cancellation_epoch :
                        installed_stop_epoch_r[slot_value];
                end else begin
                    local_error_list_token <= 32'd0;
                    local_error_list_generation <= 16'd0;
                    local_error_image_epoch <= 32'd0;
                    local_error_stage_id <= 4'd0;
                    local_error_logical_branch <= 2'd0;
                    local_error_context_generation <= 32'd0;
                    local_error_producer_sequence_ticket <= 32'd0;
                    local_error_cancellation_epoch <= 32'd0;
                    local_error_stop_epoch <= stop_commit ?
                        stop_req_cancellation_epoch : 32'd0;
                end
            end
            local_fault_pending <= 1'b1;
            if (reset_value)
                reset_required <= 1'b1;
            if (!local_error_valid && !fault_event_valid) begin
                fault_event_valid <= 1'b1;
                fault_event_code <= code_value;
                fault_event_source <= source_value;
                fault_event_detail <= detail_value;
                fault_event_slot_locator <= slot_value;
                if (slot_value < 5'd21 && authority_r[slot_value]) begin
                    fault_event_list_token <= token_r[slot_value];
                    fault_event_list_generation <= generation_r[slot_value];
                    fault_event_image_epoch <= image_epoch_r[slot_value];
                    fault_event_stage_id <= stage_id_r[slot_value];
                    fault_event_logical_branch <= logical_branch_r[slot_value];
                    fault_event_context_generation <= context_generation_r[slot_value];
                    fault_event_producer_sequence_ticket <= producer_ticket_r[slot_value];
                    fault_event_cancellation_epoch <= cancellation_epoch_r[slot_value];
                    fault_event_stop_epoch <= stop_commit ?
                        stop_req_cancellation_epoch :
                        installed_stop_epoch_r[slot_value];
                end else begin
                    fault_event_list_token <= 32'd0;
                    fault_event_list_generation <= 16'd0;
                    fault_event_image_epoch <= 32'd0;
                    fault_event_stage_id <= 4'd0;
                    fault_event_logical_branch <= 2'd0;
                    fault_event_context_generation <= 32'd0;
                    fault_event_producer_sequence_ticket <= 32'd0;
                    fault_event_cancellation_epoch <= 32'd0;
                    fault_event_stop_epoch <= stop_commit ?
                        stop_req_cancellation_epoch : 32'd0;
                end
                fault_event_reset_required <= reset_value ||
                    (stop_commit && stop_req_data_untrusted);
            end
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            allocation_candidate_valid <= 1'b0;
            allocation_candidate_slot <= 5'd0;
            current_producer_valid <= 1'b0;
            current_producer_slot <= 5'd0;
            current_producer_token <= 32'd0;
            current_producer_generation <= 16'd0;
            producer_started <= 1'b0;
            producer_obligation <= 1'b0;
            completion_slot_reserved <= 1'b0;
            closing_busy <= 1'b0;
            closing_slot_r <= 5'd0;
            closing_tag_r <= 16'd0;
            closing_status_r <= STATUS_OK;
            local_fault_pending <= 1'b0;
            stop_pending <= 1'b0;
            last_stop_epoch <= 32'd0;
            reset_required <= 1'b0;
            wrap_recovery_required <= 1'b0;
            next_list_token <= 32'd1;
            next_reference_token <= 32'd1;
            allocation_rr_slot <= 5'd20;
            list_token_exhausted <= 1'b0;
            reference_token_exhausted <= 1'b0;
            slot_generation_exhausted <= 21'd0;
            open_response_retired <= 1'b0;
            installed_stop_code <= STATUS_OK;
            installed_stop_epoch <= 32'd0;
            installed_stop_data_untrusted <= 1'b0;
            stop_response_retired <= 1'b0;
            stop_tag_r <= 16'd0;
            producer_selected_status <= STATUS_OK;
            producer_selected_detail <= 32'd0;

            mgmt_rsp_valid <= 1'b0;
            mgmt_rsp_opcode <= 3'd0;
            mgmt_rsp_status <= 8'd0;
            mgmt_rsp_committed <= 1'b0;
            mgmt_rsp_released <= 1'b0;
            mgmt_rsp_slot_locator <= 5'd0;
            mgmt_rsp_list_token <= 32'd0;
            mgmt_rsp_list_generation <= 16'd0;
            mgmt_rsp_image_epoch <= 32'd0;
            mgmt_rsp_stage_id <= 4'd0;
            mgmt_rsp_logical_branch <= 2'd0;
            mgmt_rsp_context_generation <= 32'd0;
            mgmt_rsp_producer_sequence_ticket <= 32'd0;
            mgmt_rsp_domain_bound <= 9'd0;
            mgmt_rsp_reserved_capacity <= 9'd0;
            mgmt_rsp_state <= STATE_FREE;
            mgmt_rsp_active_count <= 9'd0;
            mgmt_rsp_ref_token <= 32'd0;
            mgmt_rsp_ref_owner_kind <= 3'd0;
            mgmt_rsp_ref_owner_token <= 32'd0;
            mgmt_rsp_ref_phase <= 2'd0;
            mgmt_rsp_cancellation_epoch <= 32'd0;
            mgmt_rsp_stop_epoch <= 32'd0;
            mgmt_rsp_tag <= 16'd0;

            stop_rsp_valid <= 1'b0;
            stop_rsp_committed <= 1'b0;
            stop_rsp_code <= 8'd0;
            stop_rsp_cancellation_epoch <= 32'd0;
            stop_rsp_error_slot_mask <= 21'd0;
            stop_rsp_reset_required <= 1'b0;
            stop_rsp_tag <= 16'd0;
            stop_rsp_status <= 8'd0;

            completion_valid <= 1'b0;
            completion_status <= 8'd0;
            completion_sealed <= 1'b0;
            completion_slot_locator <= 5'd0;
            completion_list_token <= 32'd0;
            completion_list_generation <= 16'd0;
            completion_image_epoch <= 32'd0;
            completion_stage_id <= 4'd0;
            completion_logical_branch <= 2'd0;
            completion_context_generation <= 32'd0;
            completion_producer_sequence_ticket <= 32'd0;
            completion_cancellation_epoch <= 32'd0;
            completion_stop_epoch <= 32'd0;
            completion_domain_bound <= 9'd0;
            completion_active_count <= 9'd0;
            completion_last_committed_index <= 9'd0;
            completion_last_valid <= 1'b0;
            completion_terminal_tag <= 16'd0;
            completion_error_detail <= 32'd0;

            read_head <= 1'b0;
            read_tail <= 1'b0;
            read_count_r <= 2'd0;
            read_result_pending <= 1'b0;
            read_result_slot <= 1'b0;

            fault_event_valid <= 1'b0;
            fault_event_code <= 8'd0;
            fault_event_source <= SOURCE_NONE;
            fault_event_detail <= 32'd0;
            fault_event_slot_locator <= 5'd0;
            fault_event_list_token <= 32'd0;
            fault_event_list_generation <= 16'd0;
            fault_event_image_epoch <= 32'd0;
            fault_event_stage_id <= 4'd0;
            fault_event_logical_branch <= 2'd0;
            fault_event_context_generation <= 32'd0;
            fault_event_producer_sequence_ticket <= 32'd0;
            fault_event_cancellation_epoch <= 32'd0;
            fault_event_stop_epoch <= 32'd0;
            fault_event_reset_required <= 1'b0;
            local_error_valid <= 1'b0;
            local_error_code <= 8'd0;
            local_error_source <= SOURCE_NONE;
            local_error_detail <= 32'd0;
            local_error_slot_locator <= 5'd0;
            local_error_list_token <= 32'd0;
            local_error_list_generation <= 16'd0;
            local_error_image_epoch <= 32'd0;
            local_error_stage_id <= 4'd0;
            local_error_logical_branch <= 2'd0;
            local_error_context_generation <= 32'd0;
            local_error_producer_sequence_ticket <= 32'd0;
            local_error_cancellation_epoch <= 32'd0;
            local_error_stop_epoch <= 32'd0;


            for (i = 0; i < 21; i = i + 1) begin
                state_r[i] <= STATE_FREE;
                authority_r[i] <= 1'b0;
                token_r[i] <= 32'd0;
                generation_r[i] <= 16'd0;
                image_epoch_r[i] <= 32'd0;
                stage_id_r[i] <= 4'd0;
                logical_branch_r[i] <= 2'd0;
                context_generation_r[i] <= 32'd0;
                producer_ticket_r[i] <= 32'd0;
                cancellation_epoch_r[i] <= 32'd0;
                installed_stop_epoch_r[i] <= 32'd0;
                domain_bound_r[i] <= 9'd0;
                active_count_r[i] <= 9'd0;
                last_index_r[i] <= 9'd0;
                last_valid_r[i] <= 1'b0;
                terminal_tag_r[i] <= 16'd0;
                event_retired_r[i] <= 1'b0;
                read_ref_count_r[i] <= 2'd0;
                ref0_valid_r[i] <= 1'b0;
                ref0_token_r[i] <= 32'd0;
                ref0_owner_kind_r[i] <= 3'd0;
                ref0_owner_token_r[i] <= 32'd0;
                ref0_phase_r[i] <= 2'd0;
                ref1_valid_r[i] <= 1'b0;
                ref1_token_r[i] <= 32'd0;
                ref1_owner_kind_r[i] <= 3'd0;
                ref1_owner_token_r[i] <= 32'd0;
                ref1_phase_r[i] <= 2'd0;
            end

            for (i = 0; i < 2; i = i + 1) begin
                read_state_r[i] <= READ_FREE;
                read_kind_r[i] <= 1'b0;
                read_status_r[i] <= 8'd0;
                read_slot_locator_r[i] <= 5'd0;
                read_list_token_r[i] <= 32'd0;
                read_list_generation_r[i] <= 16'd0;
                read_image_epoch_r[i] <= 32'd0;
                read_stage_id_r[i] <= 4'd0;
                read_logical_branch_r[i] <= 2'd0;
                read_context_generation_r[i] <= 32'd0;
                read_producer_ticket_r[i] <= 32'd0;
                read_cancellation_epoch_r[i] <= 32'd0;
                read_stop_epoch_r[i] <= 32'd0;
                read_domain_bound_r[i] <= 9'd0;
                read_active_count_r[i] <= 9'd0;
                read_terminal_tag_r[i] <= 16'd0;
                read_list_state_r[i] <= STATE_FREE;
                read_external_ref_count_r[i] <= 2'd0;
                read_source_index_r[i] <= 9'd0;
                read_data_usable_r[i] <= 1'b0;
                read_ordinal_r[i] <= 9'd0;
                read_last_r[i] <= 1'b0;
                read_sealed_r[i] <= 1'b0;
                read_causal_r[i] <= 1'b0;
                read_external_ref_token_r[i] <= 32'd0;
                read_tag_r[i] <= 16'd0;
                read_reference_taken_r[i] <= 1'b0;
                read_ram_select_r[i] <= 1'b0;
            end
        end else begin
            allocation_candidate_valid <= alloc_scan_found;
            allocation_candidate_slot <= alloc_scan_slot;


            if (fault_event_valid && fault_event_ready) begin
                fault_event_valid <= 1'b0;
                fault_event_code <= 8'd0;
                fault_event_source <= SOURCE_NONE;
                fault_event_detail <= 32'd0;
                fault_event_slot_locator <= 5'd0;
                fault_event_list_token <= 32'd0;
                fault_event_list_generation <= 16'd0;
                fault_event_image_epoch <= 32'd0;
                fault_event_stage_id <= 4'd0;
                fault_event_logical_branch <= 2'd0;
                fault_event_context_generation <= 32'd0;
                fault_event_producer_sequence_ticket <= 32'd0;
                fault_event_cancellation_epoch <= 32'd0;
                fault_event_stop_epoch <= 32'd0;
                fault_event_reset_required <= 1'b0;
            end

            if (mgmt_rsp_valid && mgmt_rsp_ready) begin
                if (mgmt_rsp_opcode == OP_OPEN && mgmt_rsp_committed)
                    open_response_retired <= 1'b1;
                if (mgmt_rsp_opcode == OP_LIST_RELEASE &&
                    mgmt_rsp_committed && mgmt_rsp_released) begin
                    state_r[mgmt_rsp_slot_locator] <= STATE_FREE;
                    authority_r[mgmt_rsp_slot_locator] <= 1'b0;
                    token_r[mgmt_rsp_slot_locator] <= 32'd0;
                    image_epoch_r[mgmt_rsp_slot_locator] <= 32'd0;
                    stage_id_r[mgmt_rsp_slot_locator] <= 4'd0;
                    logical_branch_r[mgmt_rsp_slot_locator] <= 2'd0;
                    context_generation_r[mgmt_rsp_slot_locator] <= 32'd0;
                    producer_ticket_r[mgmt_rsp_slot_locator] <= 32'd0;
                    cancellation_epoch_r[mgmt_rsp_slot_locator] <= 32'd0;
                    installed_stop_epoch_r[mgmt_rsp_slot_locator] <= 32'd0;
                    domain_bound_r[mgmt_rsp_slot_locator] <= 9'd0;
                    active_count_r[mgmt_rsp_slot_locator] <= 9'd0;
                    last_index_r[mgmt_rsp_slot_locator] <= 9'd0;
                    last_valid_r[mgmt_rsp_slot_locator] <= 1'b0;
                    terminal_tag_r[mgmt_rsp_slot_locator] <= 16'd0;
                    event_retired_r[mgmt_rsp_slot_locator] <= 1'b0;
                    ref0_valid_r[mgmt_rsp_slot_locator] <= 1'b0;
                    ref1_valid_r[mgmt_rsp_slot_locator] <= 1'b0;
                    closing_busy <= 1'b0;
                end
                mgmt_rsp_valid <= 1'b0;
                mgmt_rsp_opcode <= 3'd0;
                mgmt_rsp_status <= 8'd0;
                mgmt_rsp_committed <= 1'b0;
                mgmt_rsp_released <= 1'b0;
                mgmt_rsp_slot_locator <= 5'd0;
                mgmt_rsp_list_token <= 32'd0;
                mgmt_rsp_list_generation <= 16'd0;
                mgmt_rsp_image_epoch <= 32'd0;
                mgmt_rsp_stage_id <= 4'd0;
                mgmt_rsp_logical_branch <= 2'd0;
                mgmt_rsp_context_generation <= 32'd0;
                mgmt_rsp_producer_sequence_ticket <= 32'd0;
                mgmt_rsp_domain_bound <= 9'd0;
                mgmt_rsp_reserved_capacity <= 9'd0;
                mgmt_rsp_state <= STATE_FREE;
                mgmt_rsp_active_count <= 9'd0;
                mgmt_rsp_ref_token <= 32'd0;
                mgmt_rsp_ref_owner_kind <= 3'd0;
                mgmt_rsp_ref_owner_token <= 32'd0;
                mgmt_rsp_ref_phase <= 2'd0;
                mgmt_rsp_cancellation_epoch <= 32'd0;
                mgmt_rsp_stop_epoch <= 32'd0;
                mgmt_rsp_tag <= 16'd0;
            end

            if (stop_rsp_valid && stop_rsp_ready) begin
                stop_rsp_valid <= 1'b0;
                if (stop_rsp_committed)
                    stop_response_retired <= 1'b1;
                stop_rsp_committed <= 1'b0;
                stop_rsp_code <= 8'd0;
                stop_rsp_cancellation_epoch <= 32'd0;
                stop_rsp_error_slot_mask <= 21'd0;
                stop_rsp_reset_required <= 1'b0;
                stop_rsp_tag <= 16'd0;
                stop_rsp_status <= 8'd0;
            end

            if (completion_valid && completion_ready) begin
                completion_valid <= 1'b0;
                completion_slot_reserved <= 1'b0;
                event_retired_r[completion_slot_locator] <= 1'b1;
                if (!completion_sealed)
                    state_r[completion_slot_locator] <= STATE_ERROR;
                completion_status <= 8'd0;
                completion_sealed <= 1'b0;
                completion_slot_locator <= 5'd0;
                completion_list_token <= 32'd0;
                completion_list_generation <= 16'd0;
                completion_image_epoch <= 32'd0;
                completion_stage_id <= 4'd0;
                completion_logical_branch <= 2'd0;
                completion_context_generation <= 32'd0;
                completion_producer_sequence_ticket <= 32'd0;
                completion_cancellation_epoch <= 32'd0;
                completion_stop_epoch <= 32'd0;
                completion_domain_bound <= 9'd0;
                completion_active_count <= 9'd0;
                completion_last_committed_index <= 9'd0;
                completion_last_valid <= 1'b0;
                completion_terminal_tag <= 16'd0;
                completion_error_detail <= 32'd0;
            end

            if (read_rsp_fire) begin
                read_state_r[read_head] <= READ_FREE;
                read_head <= ~read_head;
            end

            if (read_result_pending) begin
                read_state_r[read_result_slot] <= READ_OUTPUT;
                if (read_kind_r[read_result_slot] &&
                    read_data_usable_r[read_result_slot] &&
                    !(stop_commit && stop_req_data_untrusted)) begin
                    if (read_ram_select_r[read_result_slot])
                        read_source_index_r[read_result_slot] <= index_mem1_q;
                    else
                        read_source_index_r[read_result_slot] <= index_mem0_q;
                end else begin
                    read_source_index_r[read_result_slot] <= 9'd0;
                end
                if (stop_commit) begin
                    read_status_r[read_result_slot] <= stop_selected_code;
                    read_stop_epoch_r[read_result_slot] <=
                        stop_req_cancellation_epoch;
                    if (stop_req_data_untrusted || internal_fault_comb ||
                        !read_causal_r[read_result_slot]) begin
                        read_data_usable_r[read_result_slot] <= 1'b0;
                        read_source_index_r[read_result_slot] <= 9'd0;
                    end
                end
                read_result_pending <= 1'b0;
            end

            if (read_fire) begin
                read_state_r[read_tail] <= READ_WAIT;
                read_kind_r[read_tail] <= read_req_kind;
                read_status_r[read_tail] <= read_accept_status;
                read_slot_locator_r[read_tail] <= read_req_slot_locator;
                read_list_token_r[read_tail] <= read_req_list_token;
                read_list_generation_r[read_tail] <= read_req_list_generation;
                read_image_epoch_r[read_tail] <= read_list_identity_exact ?
                    image_epoch_r[read_slot_safe] : read_req_image_epoch;
                read_stage_id_r[read_tail] <= read_list_identity_exact ?
                    stage_id_r[read_slot_safe] : read_req_stage_id;
                read_logical_branch_r[read_tail] <= read_list_identity_exact ?
                    logical_branch_r[read_slot_safe] : read_req_logical_branch;
                read_context_generation_r[read_tail] <= read_list_identity_exact ?
                    context_generation_r[read_slot_safe] : read_req_context_generation;
                read_producer_ticket_r[read_tail] <= read_list_identity_exact ?
                    producer_ticket_r[read_slot_safe] :
                    read_req_producer_sequence_ticket;
                read_cancellation_epoch_r[read_tail] <= read_list_identity_exact ?
                    cancellation_epoch_r[read_slot_safe] : read_req_cancellation_epoch;
                read_stop_epoch_r[read_tail] <= stop_pending ?
                    installed_stop_epoch : 32'd0;
                read_domain_bound_r[read_tail] <= read_list_identity_exact ?
                    domain_bound_r[read_slot_safe] : 9'd0;
                read_active_count_r[read_tail] <= read_list_identity_exact ?
                    active_count_r[read_slot_safe] : 9'd0;
                read_terminal_tag_r[read_tail] <= read_list_identity_exact ?
                    terminal_tag_r[read_slot_safe] : 16'd0;
                read_list_state_r[read_tail] <= read_list_identity_exact ?
                    state_r[read_slot_safe] : STATE_FREE;
                read_external_ref_count_r[read_tail] <= read_list_identity_exact ?
                    read_ext_count : 2'd0;
                read_source_index_r[read_tail] <= 9'd0;
                read_data_usable_r[read_tail] <= read_accept_data_usable;
                read_ordinal_r[read_tail] <= read_req_ordinal;
                read_last_r[read_tail] <= read_accept_take_reference &&
                    read_req_kind &&
                    (read_req_ordinal + 1'b1 == active_count_r[read_slot_safe]);
                read_sealed_r[read_tail] <= read_accept_sealed;
                read_causal_r[read_tail] <= read_req_causal_continuation;
                read_external_ref_token_r[read_tail] <=
                    read_req_external_ref_token;
                read_tag_r[read_tail] <= read_req_tag;
                read_reference_taken_r[read_tail] <=
                    read_accept_take_reference;
                read_ram_select_r[read_tail] <= payload_read_ram;
                read_result_slot <= read_tail;
                read_result_pending <= 1'b1;
                read_tail <= ~read_tail;
            end

            case ({read_fire, read_rsp_fire})
                2'b10: read_count_r <= read_count_r + 1'b1;
                2'b01: read_count_r <= read_count_r - 1'b1;
                default: read_count_r <= read_count_r;
            endcase

            for (i = 0; i < 21; i = i + 1) begin
                case ({read_fire && read_accept_take_reference &&
                       read_slot_safe == i,
                       read_rsp_fire && read_reference_taken_r[read_head] &&
                       read_slot_locator_r[read_head] == i})
                    2'b10: read_ref_count_r[i] <= read_ref_count_r[i] + 1'b1;
                    2'b01: read_ref_count_r[i] <= read_ref_count_r[i] - 1'b1;
                    default: read_ref_count_r[i] <= read_ref_count_r[i];
                endcase
            end

            if (closing_busy && !mgmt_rsp_valid &&
                (read_ref_count_r[closing_slot_r] == 2'd0 ||
                 (read_rsp_fire && read_reference_taken_r[read_head] &&
                  read_slot_locator_r[read_head] == closing_slot_r &&
                  read_ref_count_r[closing_slot_r] == 2'd1))) begin
                mgmt_rsp_valid <= 1'b1;
                mgmt_rsp_opcode <= OP_LIST_RELEASE;
                mgmt_rsp_status <= (cleanup_terminal_status != STATUS_OK) ?
                    cleanup_terminal_status : closing_status_r;
                mgmt_rsp_committed <= 1'b1;
                mgmt_rsp_released <= 1'b1;
                mgmt_rsp_slot_locator <= closing_slot_r;
                mgmt_rsp_list_token <= token_r[closing_slot_r];
                mgmt_rsp_list_generation <= generation_r[closing_slot_r];
                mgmt_rsp_image_epoch <= image_epoch_r[closing_slot_r];
                mgmt_rsp_stage_id <= stage_id_r[closing_slot_r];
                mgmt_rsp_logical_branch <= logical_branch_r[closing_slot_r];
                mgmt_rsp_context_generation <= context_generation_r[closing_slot_r];
                mgmt_rsp_producer_sequence_ticket <= producer_ticket_r[closing_slot_r];
                mgmt_rsp_domain_bound <= domain_bound_r[closing_slot_r];
                mgmt_rsp_reserved_capacity <= 9'd0;
                mgmt_rsp_state <= STATE_CLOSING;
                mgmt_rsp_active_count <= active_count_r[closing_slot_r];
                mgmt_rsp_ref_token <= 32'd0;
                mgmt_rsp_ref_owner_kind <= 3'd0;
                mgmt_rsp_ref_owner_token <= 32'd0;
                mgmt_rsp_ref_phase <= 2'd0;
                mgmt_rsp_cancellation_epoch <= cancellation_epoch_r[closing_slot_r];
                mgmt_rsp_stop_epoch <= stop_commit ?
                    stop_req_cancellation_epoch :
                    (stop_pending ? installed_stop_epoch : 32'd0);
                mgmt_rsp_tag <= closing_tag_r;
            end

            for (i = 0; i < 21; i = i + 1) begin
                if (stop_pending && authority_r[i] &&
                    installed_stop_epoch_r[i] == installed_stop_epoch &&
                    (state_r[i] == STATE_SEALED ||
                     state_r[i] == STATE_REFERENCED) &&
                    !ref0_valid_r[i] && !ref1_valid_r[i] &&
                    read_ref_count_r[i] == 2'd0 && event_retired_r[i])
                    state_r[i] <= STATE_ERROR;
            end

            if (stop_pending && !stop_rsp_valid && !stop_response_retired &&
                stop_drain_complete) begin
                stop_rsp_valid <= 1'b1;
                stop_rsp_committed <= 1'b1;
                stop_rsp_code <= installed_stop_code;
                stop_rsp_cancellation_epoch <= installed_stop_epoch;
                for (i = 0; i < 21; i = i + 1)
                    stop_rsp_error_slot_mask[i] <=
                        (state_r[i] == STATE_ERROR);
                stop_rsp_reset_required <= reset_required;
                stop_rsp_tag <= stop_tag_r;
                stop_rsp_status <= installed_stop_code;
            end

            if (stop_pending && stop_response_retired && !reset_required &&
                all_slots_free_comb && !current_producer_valid &&
                !producer_obligation && !completion_slot_reserved &&
                !completion_valid && read_count_r == 0 &&
                read_ref_total_comb == 0 && ext_count_comb == 0 &&
                !mgmt_rsp_valid && !closing_busy && !fault_event_valid &&
                !local_fault_pending) begin
                stop_pending <= 1'b0;
                installed_stop_code <= STATUS_OK;
                installed_stop_epoch <= 32'd0;
                installed_stop_data_untrusted <= 1'b0;
                stop_response_retired <= 1'b0;
            end

            if (mgmt_fire) begin
                case (mgmt_req_opcode)
                    OP_OPEN: begin
                        if (producer_stage_is_projection(mgmt_req_stage_id)) begin
                            put_mgmt_response(ERR_PROJECTION_PRODUCER, 1'b0, 1'b0);
                        end else if (!producer_tuple_valid(
                                     mgmt_req_stage_id,
                                     mgmt_req_logical_branch,
                                     mgmt_req_domain_bound)) begin
                            if ((mgmt_req_stage_id == 4'd0 ||
                                 mgmt_req_stage_id == 4'd1 ||
                                 mgmt_req_stage_id == 4'd3 ||
                                 mgmt_req_stage_id == 4'd4 ||
                                 mgmt_req_stage_id == 4'd6 ||
                                 mgmt_req_stage_id == 4'd7 ||
                                 mgmt_req_stage_id == 4'd9 ||
                                 mgmt_req_stage_id == 4'd10) &&
                                (mgmt_req_domain_bound != 9'd320 &&
                                 mgmt_req_domain_bound != 9'd224))
                                put_mgmt_response(ERR_BAD_DOMAIN_BOUND, 1'b0, 1'b0);
                            else
                                put_mgmt_response(ERR_BAD_STAGE_DOMAIN, 1'b0, 1'b0);
                        end else if (!open_nonzero_identity) begin
                            put_mgmt_response(ERR_BAD_IDENTITY, 1'b0, 1'b0);
                        end else if (store_image_valid_comb &&
                                     store_image_epoch_comb !=
                                         mgmt_req_image_epoch) begin
                            put_mgmt_response(ERR_BAD_IDENTITY, 1'b0, 1'b0);
                        end else if (list_token_exhausted) begin
                            put_mgmt_response(ERR_TOKEN_EXHAUSTED, 1'b0, 1'b0);
                        end else if (!allocation_candidate_valid ||
                                     state_r[allocation_candidate_slot] != STATE_FREE ||
                                     slot_generation_exhausted[allocation_candidate_slot]) begin
                            put_mgmt_response(ERR_GENERATION_EXHAUSTED, 1'b0, 1'b0);
                        end else begin
                            state_r[allocation_candidate_slot] <= STATE_OPEN;
                            authority_r[allocation_candidate_slot] <= 1'b1;
                            token_r[allocation_candidate_slot] <= next_list_token;
                            generation_r[allocation_candidate_slot] <=
                                generation_r[allocation_candidate_slot] + 1'b1;
                            image_epoch_r[allocation_candidate_slot] <=
                                mgmt_req_image_epoch;
                            stage_id_r[allocation_candidate_slot] <= mgmt_req_stage_id;
                            logical_branch_r[allocation_candidate_slot] <=
                                mgmt_req_logical_branch;
                            context_generation_r[allocation_candidate_slot] <=
                                mgmt_req_context_generation;
                            producer_ticket_r[allocation_candidate_slot] <=
                                mgmt_req_producer_sequence_ticket;
                            cancellation_epoch_r[allocation_candidate_slot] <=
                                mgmt_req_cancellation_epoch;
                            installed_stop_epoch_r[allocation_candidate_slot] <= 32'd0;
                            domain_bound_r[allocation_candidate_slot] <=
                                mgmt_req_domain_bound;
                            active_count_r[allocation_candidate_slot] <= 9'd0;
                            last_index_r[allocation_candidate_slot] <= 9'd0;
                            last_valid_r[allocation_candidate_slot] <= 1'b0;
                            terminal_tag_r[allocation_candidate_slot] <= 16'd0;
                            event_retired_r[allocation_candidate_slot] <= 1'b0;
                            read_ref_count_r[allocation_candidate_slot] <= 2'd0;
                            ref0_valid_r[allocation_candidate_slot] <= 1'b0;
                            ref1_valid_r[allocation_candidate_slot] <= 1'b0;

                            current_producer_valid <= 1'b1;
                            current_producer_slot <= allocation_candidate_slot;
                            current_producer_token <= next_list_token;
                            current_producer_generation <=
                                generation_r[allocation_candidate_slot] + 1'b1;
                            producer_started <= 1'b0;
                            producer_obligation <= 1'b0;
                            completion_slot_reserved <= 1'b1;
                            open_response_retired <= 1'b0;
                            producer_selected_status <= STATUS_OK;
                            producer_selected_detail <= 32'd0;
                            allocation_rr_slot <= allocation_candidate_slot;
                            allocation_candidate_valid <= 1'b0;
                            allocation_candidate_slot <= 5'd0;

                            put_mgmt_response(STATUS_OK, 1'b1, 1'b0);
                            mgmt_rsp_slot_locator <= allocation_candidate_slot;
                            mgmt_rsp_list_token <= next_list_token;
                            mgmt_rsp_list_generation <=
                                generation_r[allocation_candidate_slot] + 1'b1;
                            mgmt_rsp_reserved_capacity <= 9'd320;
                            mgmt_rsp_state <= STATE_OPEN;
                            mgmt_rsp_active_count <= 9'd0;
                            mgmt_rsp_stop_epoch <= 32'd0;

                            if (next_list_token == 32'hffff_ffff) begin
                                list_token_exhausted <= 1'b1;
                                wrap_recovery_required <= 1'b1;
                                reset_required <= 1'b1;
                            end else begin
                                next_list_token <= next_list_token + 1'b1;
                            end
                            if (generation_r[allocation_candidate_slot] ==
                                16'hfffe) begin
                                slot_generation_exhausted[allocation_candidate_slot] <= 1'b1;
                                wrap_recovery_required <= 1'b1;
                                reset_required <= 1'b1;
                            end
                        end
                    end

                    OP_START: begin
                        if (!mgmt_slot_valid) begin
                            put_mgmt_response(ERR_BAD_SLOT, 1'b0, 1'b0);
                        end else if (generation_r[mgmt_slot_safe] !=
                                     mgmt_req_list_generation) begin
                            put_mgmt_response(ERR_STALE_GENERATION, 1'b0, 1'b0);
                        end else if (!authority_r[mgmt_slot_safe] ||
                                    token_r[mgmt_slot_safe] !=
                                     mgmt_req_list_token) begin
                            put_mgmt_response(ERR_STALE_TOKEN, 1'b0, 1'b0);
                        end else if (!mgmt_list_identity_exact) begin
                            put_mgmt_response(ERR_BAD_IDENTITY, 1'b0, 1'b0);
                        end else if (state_r[mgmt_slot_safe] != STATE_OPEN ||
                                     producer_started ||
                                     mgmt_slot_safe != current_producer_slot) begin
                            put_mgmt_response(ERR_WRONG_STATE, 1'b0, 1'b0);
                        end else if (!open_response_retired) begin
                            put_mgmt_response(ERR_NOT_QUIESCENT, 1'b0, 1'b0);
                        end else if (start_exact && start_partner_ready) begin
                            producer_started <= 1'b1;
                            producer_obligation <= 1'b1;
                            put_mgmt_response(STATUS_OK, 1'b1, 1'b0);
                            mgmt_rsp_state <= STATE_OPEN;
                        end else begin
                            put_mgmt_response(ERR_BAD_IDENTITY, 1'b0, 1'b0);
                        end
                    end

                    OP_REF_ACQUIRE: begin
                        if (!mgmt_slot_valid)
                            put_mgmt_response(ERR_BAD_SLOT, 1'b0, 1'b0);
                        else if (generation_r[mgmt_slot_safe] !=
                                 mgmt_req_list_generation)
                            put_mgmt_response(ERR_STALE_GENERATION, 1'b0, 1'b0);
                        else if (!authority_r[mgmt_slot_safe] ||
                                 token_r[mgmt_slot_safe] != mgmt_req_list_token)
                            put_mgmt_response(ERR_STALE_TOKEN, 1'b0, 1'b0);
                        else if (!mgmt_list_identity_exact)
                            put_mgmt_response(ERR_BAD_IDENTITY, 1'b0, 1'b0);
                        else if (mgmt_req_stop_epoch != 32'd0)
                            put_mgmt_response(ERR_BAD_DRAIN_TARGET, 1'b0, 1'b0);
                        else if (state_r[mgmt_slot_safe] != STATE_SEALED &&
                                 state_r[mgmt_slot_safe] != STATE_REFERENCED)
                            put_mgmt_response(ERR_WRONG_STATE, 1'b0, 1'b0);
                        else if (!mgmt_event_effectively_retired)
                            put_mgmt_response(ERR_EVENT_PENDING, 1'b0, 1'b0);
                        else if (!ref_acquire_is_legal(
                                 mgmt_req_ref_owner_kind,
                                 mgmt_req_ref_phase) ||
                                 mgmt_req_ref_owner_token == 32'd0)
                            put_mgmt_response(ERR_OWNER_MISMATCH, 1'b0, 1'b0);
                        else if ((ref0_valid_r[mgmt_slot_safe] &&
                                  ref0_owner_kind_r[mgmt_slot_safe] ==
                                      mgmt_req_ref_owner_kind &&
                                  ref0_owner_token_r[mgmt_slot_safe] ==
                                      mgmt_req_ref_owner_token) ||
                                 (ref1_valid_r[mgmt_slot_safe] &&
                                  ref1_owner_kind_r[mgmt_slot_safe] ==
                                      mgmt_req_ref_owner_kind &&
                                  ref1_owner_token_r[mgmt_slot_safe] ==
                                      mgmt_req_ref_owner_token))
                            put_mgmt_response(ERR_REF_DUPLICATE, 1'b0, 1'b0);
                        else if (mgmt_ext_count == 2)
                            put_mgmt_response(ERR_REF_CAPACITY, 1'b0, 1'b0);
                        else if (reference_token_exhausted)
                            put_mgmt_response(ERR_REF_TOKEN_EXHAUSTED, 1'b0, 1'b0);
                        else begin
                            if (!ref0_valid_r[mgmt_slot_safe]) begin
                                ref0_valid_r[mgmt_slot_safe] <= 1'b1;
                                ref0_token_r[mgmt_slot_safe] <= next_reference_token;
                                ref0_owner_kind_r[mgmt_slot_safe] <=
                                    mgmt_req_ref_owner_kind;
                                ref0_owner_token_r[mgmt_slot_safe] <=
                                    mgmt_req_ref_owner_token;
                                ref0_phase_r[mgmt_slot_safe] <= mgmt_req_ref_phase;
                            end else begin
                                ref1_valid_r[mgmt_slot_safe] <= 1'b1;
                                ref1_token_r[mgmt_slot_safe] <= next_reference_token;
                                ref1_owner_kind_r[mgmt_slot_safe] <=
                                    mgmt_req_ref_owner_kind;
                                ref1_owner_token_r[mgmt_slot_safe] <=
                                    mgmt_req_ref_owner_token;
                                ref1_phase_r[mgmt_slot_safe] <= mgmt_req_ref_phase;
                            end
                            state_r[mgmt_slot_safe] <= STATE_REFERENCED;
                            put_mgmt_response(STATUS_OK, 1'b1, 1'b0);
                            mgmt_rsp_ref_token <= next_reference_token;
                            mgmt_rsp_state <= STATE_REFERENCED;
                            if (next_reference_token == 32'hffff_ffff) begin
                                reference_token_exhausted <= 1'b1;
                                wrap_recovery_required <= 1'b1;
                                reset_required <= 1'b1;
                            end else begin
                                next_reference_token <= next_reference_token + 1'b1;
                            end
                        end
                    end

                    OP_REF_TRANSFER: begin
                        if (!mgmt_slot_valid)
                            put_mgmt_response(ERR_BAD_SLOT, 1'b0, 1'b0);
                        else if (generation_r[mgmt_slot_safe] !=
                                 mgmt_req_list_generation)
                            put_mgmt_response(ERR_STALE_GENERATION, 1'b0, 1'b0);
                        else if (!authority_r[mgmt_slot_safe] ||
                                 token_r[mgmt_slot_safe] != mgmt_req_list_token)
                            put_mgmt_response(ERR_STALE_TOKEN, 1'b0, 1'b0);
                        else if (!mgmt_list_identity_exact)
                            put_mgmt_response(ERR_BAD_IDENTITY, 1'b0, 1'b0);
                        else if (mgmt_req_stop_epoch != 32'd0)
                            put_mgmt_response(ERR_BAD_DRAIN_TARGET, 1'b0, 1'b0);
                        else if (!mgmt_ref_exact)
                            put_mgmt_response(ERR_REF_NOT_FOUND, 1'b0, 1'b0);
                        else if (!ref_transfer_is_legal(
                                 mgmt_req_ref_owner_kind,
                                 mgmt_req_ref_phase,
                                 mgmt_req_new_ref_owner_kind,
                                 mgmt_req_new_ref_phase) ||
                                 (((mgmt_req_ref_owner_kind == 3'd1 ||
                                    mgmt_req_ref_owner_kind == 3'd2) &&
                                   mgmt_req_ref_phase == REF_PENDING &&
                                   mgmt_req_new_ref_phase == REF_PERSISTENT) &&
                                  mgmt_req_new_ref_owner_token !=
                                      mgmt_req_ref_owner_token) ||
                                 mgmt_req_new_ref_owner_token == 32'd0)
                            put_mgmt_response(ERR_OWNER_MISMATCH, 1'b0, 1'b0);
                        else if ((mgmt_ref0_exact && ref1_valid_r[mgmt_slot_safe] &&
                                  ref1_owner_kind_r[mgmt_slot_safe] ==
                                      mgmt_req_new_ref_owner_kind &&
                                  ref1_owner_token_r[mgmt_slot_safe] ==
                                      mgmt_req_new_ref_owner_token) ||
                                 (mgmt_ref1_exact && ref0_valid_r[mgmt_slot_safe] &&
                                  ref0_owner_kind_r[mgmt_slot_safe] ==
                                      mgmt_req_new_ref_owner_kind &&
                                  ref0_owner_token_r[mgmt_slot_safe] ==
                                      mgmt_req_new_ref_owner_token))
                            put_mgmt_response(ERR_REF_DUPLICATE, 1'b0, 1'b0);
                        else begin
                            if (mgmt_ref0_exact) begin
                                ref0_owner_kind_r[mgmt_slot_safe] <=
                                    mgmt_req_new_ref_owner_kind;
                                ref0_owner_token_r[mgmt_slot_safe] <=
                                    mgmt_req_new_ref_owner_token;
                                ref0_phase_r[mgmt_slot_safe] <=
                                    mgmt_req_new_ref_phase;
                            end else begin
                                ref1_owner_kind_r[mgmt_slot_safe] <=
                                    mgmt_req_new_ref_owner_kind;
                                ref1_owner_token_r[mgmt_slot_safe] <=
                                    mgmt_req_new_ref_owner_token;
                                ref1_phase_r[mgmt_slot_safe] <=
                                    mgmt_req_new_ref_phase;
                            end
                            put_mgmt_response(STATUS_OK, 1'b1, 1'b0);
                            mgmt_rsp_ref_owner_kind <= mgmt_req_new_ref_owner_kind;
                            mgmt_rsp_ref_owner_token <= mgmt_req_new_ref_owner_token;
                            mgmt_rsp_ref_phase <= mgmt_req_new_ref_phase;
                        end
                    end

                    OP_REF_RELEASE: begin
                        if (!mgmt_slot_valid)
                            put_mgmt_response(ERR_BAD_SLOT, 1'b0, 1'b0);
                        else if (generation_r[mgmt_slot_safe] !=
                                 mgmt_req_list_generation)
                            put_mgmt_response(ERR_STALE_GENERATION, 1'b0, 1'b0);
                        else if (!authority_r[mgmt_slot_safe] ||
                                 token_r[mgmt_slot_safe] != mgmt_req_list_token)
                            put_mgmt_response(ERR_STALE_TOKEN, 1'b0, 1'b0);
                        else if (!mgmt_list_identity_exact)
                            put_mgmt_response(ERR_BAD_IDENTITY, 1'b0, 1'b0);
                        else if ((!stop_pending && mgmt_req_stop_epoch != 32'd0) ||
                                 (stop_pending && mgmt_req_stop_epoch !=
                                  installed_stop_epoch))
                            put_mgmt_response(ERR_BAD_DRAIN_TARGET, 1'b0, 1'b0);
                        else if (!mgmt_ref_exact)
                            put_mgmt_response(ERR_REF_NOT_FOUND, 1'b0, 1'b0);
                        else begin
                            if (mgmt_ref0_exact)
                                ref0_valid_r[mgmt_slot_safe] <= 1'b0;
                            else
                                ref1_valid_r[mgmt_slot_safe] <= 1'b0;
                            if (mgmt_ext_count == 1 &&
                                state_r[mgmt_slot_safe] == STATE_REFERENCED)
                                state_r[mgmt_slot_safe] <= STATE_SEALED;
                            put_mgmt_response(cleanup_terminal_status,
                                              1'b1, 1'b1);
                            mgmt_rsp_state <= (mgmt_ext_count == 1 &&
                                state_r[mgmt_slot_safe] == STATE_REFERENCED) ?
                                    STATE_SEALED : state_r[mgmt_slot_safe];
                        end
                    end

                    OP_LIST_RELEASE: begin
                        if (!mgmt_slot_valid)
                            put_mgmt_response(ERR_BAD_SLOT, 1'b0, 1'b0);
                        else if (generation_r[mgmt_slot_safe] !=
                                 mgmt_req_list_generation)
                            put_mgmt_response(ERR_STALE_GENERATION, 1'b0, 1'b0);
                        else if (!authority_r[mgmt_slot_safe] ||
                                 token_r[mgmt_slot_safe] != mgmt_req_list_token)
                            put_mgmt_response(ERR_STALE_TOKEN, 1'b0, 1'b0);
                        else if (!mgmt_list_identity_exact)
                            put_mgmt_response(ERR_BAD_IDENTITY, 1'b0, 1'b0);
                        else if ((!stop_pending && mgmt_req_stop_epoch != 32'd0) ||
                                 (stop_pending && mgmt_req_stop_epoch !=
                                  installed_stop_epoch))
                            put_mgmt_response(ERR_BAD_DRAIN_TARGET, 1'b0, 1'b0);
                        else if (state_r[mgmt_slot_safe] == STATE_REFERENCED ||
                                 mgmt_ext_count != 0)
                            put_mgmt_response(ERR_STILL_REFERENCED, 1'b0, 1'b0);
                        else if (!mgmt_event_effectively_retired)
                            put_mgmt_response(ERR_EVENT_PENDING, 1'b0, 1'b0);
                        else if ((state_r[mgmt_slot_safe] != STATE_SEALED &&
                                  state_r[mgmt_slot_safe] != STATE_ERROR))
                            put_mgmt_response(ERR_WRONG_STATE, 1'b0, 1'b0);
                        else if (!mgmt_req_external_safe)
                            put_mgmt_response(ERR_EXTERNAL_UNSAFE, 1'b0, 1'b0);
                        else begin
                            state_r[mgmt_slot_safe] <= STATE_CLOSING;
                            closing_busy <= 1'b1;
                            closing_slot_r <= mgmt_slot_safe;
                            closing_tag_r <= mgmt_req_tag;
                            closing_status_r <= cleanup_terminal_status;
                            if (read_ref_count_r[mgmt_slot_safe] == 2'd0) begin
                                put_mgmt_response(cleanup_terminal_status,
                                                  1'b1, 1'b1);
                                mgmt_rsp_state <= STATE_CLOSING;
                            end
                        end
                    end

                    OP_CLEAR_ERROR: begin
                        if (!local_error_valid)
                            put_mgmt_response(ERR_WRONG_STATE, 1'b0, 1'b0);
                        else if (mgmt_req_slot_locator != local_error_slot_locator ||
                                 mgmt_req_list_token != local_error_list_token ||
                                 mgmt_req_list_generation !=
                                     local_error_list_generation ||
                                 mgmt_req_image_epoch != local_error_image_epoch ||
                                 mgmt_req_stage_id != local_error_stage_id ||
                                 mgmt_req_logical_branch !=
                                     local_error_logical_branch ||
                                 mgmt_req_context_generation !=
                                     local_error_context_generation ||
                                 mgmt_req_producer_sequence_ticket !=
                                     local_error_producer_sequence_ticket ||
                                 mgmt_req_cancellation_epoch !=
                                     local_error_cancellation_epoch)
                            put_mgmt_response(ERR_BAD_IDENTITY, 1'b0, 1'b0);
                        else if (!mgmt_req_external_safe)
                            put_mgmt_response(ERR_EXTERNAL_UNSAFE, 1'b0, 1'b0);
                        else if (reset_required)
                            put_mgmt_response(ERR_RESET_REQUIRED, 1'b0, 1'b0);
                        else if (error_count_comb != 0 || current_producer_valid ||
                                 completion_slot_reserved || completion_valid ||
                                 read_count_r != 0 || read_ref_total_comb != 0 ||
                                 ext_count_comb != 0 || fault_event_valid ||
                                 stop_rsp_valid)
                            put_mgmt_response(ERR_NOT_QUIESCENT, 1'b0, 1'b0);
                        else if ((!stop_pending && mgmt_req_stop_epoch != 32'd0) ||
                                 (stop_pending && mgmt_req_stop_epoch !=
                                  installed_stop_epoch))
                            put_mgmt_response(ERR_BAD_DRAIN_TARGET, 1'b0, 1'b0);
                        else begin
                            local_error_valid <= 1'b0;
                            local_error_code <= 8'd0;
                            local_error_source <= SOURCE_NONE;
                            local_error_detail <= 32'd0;
                            local_error_slot_locator <= 5'd0;
                            local_error_list_token <= 32'd0;
                            local_error_list_generation <= 16'd0;
                            local_error_image_epoch <= 32'd0;
                            local_error_stage_id <= 4'd0;
                            local_error_logical_branch <= 2'd0;
                            local_error_context_generation <= 32'd0;
                            local_error_producer_sequence_ticket <= 32'd0;
                            local_error_cancellation_epoch <= 32'd0;
                            local_error_stop_epoch <= 32'd0;
                            local_fault_pending <= 1'b0;
                            put_mgmt_response(STATUS_OK, 1'b1, 1'b0);
                        end
                    end

                    default: begin
                        put_mgmt_response(ERR_BAD_OPCODE, 1'b0, 1'b0);
                    end
                endcase
            end

            if (stop_fire) begin
                if (!stop_request_mode_valid) begin
                    stop_rsp_valid <= 1'b1;
                    stop_rsp_committed <= 1'b0;
                    stop_rsp_code <= stop_req_code;
                    stop_rsp_cancellation_epoch <= stop_req_cancellation_epoch;
                    stop_rsp_error_slot_mask <= 21'd0;
                    stop_rsp_reset_required <= reset_required;
                    stop_rsp_tag <= stop_req_tag;
                    stop_rsp_status <= ERR_BAD_DRAIN_TARGET;
                end else if (!stop_request_image_valid) begin
                    stop_rsp_valid <= 1'b1;
                    stop_rsp_committed <= 1'b0;
                    stop_rsp_code <= stop_req_code;
                    stop_rsp_cancellation_epoch <= stop_req_cancellation_epoch;
                    stop_rsp_error_slot_mask <= 21'd0;
                    stop_rsp_reset_required <= reset_required;
                    stop_rsp_tag <= stop_req_tag;
                    stop_rsp_status <= ERR_BAD_IDENTITY;
                end else if (!stop_request_epoch_valid) begin
                    stop_rsp_valid <= 1'b1;
                    stop_rsp_committed <= 1'b0;
                    stop_rsp_code <= stop_req_code;
                    stop_rsp_cancellation_epoch <= stop_req_cancellation_epoch;
                    stop_rsp_error_slot_mask <= 21'd0;
                    stop_rsp_reset_required <= reset_required;
                    stop_rsp_tag <= stop_req_tag;
                    stop_rsp_status <= ERR_BAD_DRAIN_TARGET;
                end else if (!stop_request_proof_valid) begin
                    stop_rsp_valid <= 1'b1;
                    stop_rsp_committed <= 1'b0;
                    stop_rsp_code <= stop_req_code;
                    stop_rsp_cancellation_epoch <= stop_req_cancellation_epoch;
                    stop_rsp_error_slot_mask <= 21'd0;
                    stop_rsp_reset_required <= reset_required;
                    stop_rsp_tag <= stop_req_tag;
                    stop_rsp_status <= ERR_NOT_QUIESCENT;
                end else begin
                    stop_pending <= 1'b1;
                    last_stop_epoch <= stop_req_cancellation_epoch;
                    installed_stop_epoch <= stop_req_cancellation_epoch;
                    installed_stop_code <= stop_selected_code;
                    installed_stop_data_untrusted <=
                        stop_req_data_untrusted || internal_fault_comb;
                    stop_response_retired <= 1'b0;
                    stop_tag_r <= stop_req_tag;
                    if (local_error_valid)
                        local_error_stop_epoch <= stop_req_cancellation_epoch;
                    producer_selected_status <=
                        (state_r[current_producer_slot_safe] == STATE_POISON_DRAIN) ?
                            producer_selected_status : stop_selected_code;
                    for (i = 0; i < 21; i = i + 1) begin
                        if (authority_r[i])
                            installed_stop_epoch_r[i] <=
                                stop_req_cancellation_epoch;
                    end
                    if (current_producer_valid &&
                        state_r[current_producer_slot_safe] != STATE_POISON_DRAIN)
                        state_r[current_producer_slot_safe] <= STATE_CANCEL_PENDING;
                    for (i = 0; i < 2; i = i + 1) begin
                        if (read_state_r[i] == READ_WAIT) begin
                            read_status_r[i] <= stop_selected_code;
                            read_stop_epoch_r[i] <= stop_req_cancellation_epoch;
                            if (stop_req_data_untrusted || internal_fault_comb ||
                                !read_causal_r[i]) begin
                                read_data_usable_r[i] <= 1'b0;
                                read_source_index_r[i] <= 9'd0;
                            end
                        end
                    end
                    if (stop_req_data_untrusted || internal_fault_comb)
                        reset_required <= 1'b1;
                    if (stop_req_cancellation_epoch == 32'hffff_ffff) begin
                        wrap_recovery_required <= 1'b1;
                        reset_required <= 1'b1;
                    end
                end
            end

            if (active_fire) begin
                if (state_r[current_producer_slot_safe] == STATE_OPEN) begin
                    if (active_error_comb) begin
                        producer_selected_status <= stop_commit ?
                            stop_selected_code : active_error_code_comb;
                        producer_selected_detail <= active_error_detail(
                            current_producer_slot, active_cmd_write,
                            active_cmd_finalize, active_cmd_index,
                            active_count_r[current_producer_slot_safe], active_cmd_tag);
                        state_r[current_producer_slot_safe] <= STATE_POISON_DRAIN;
                        latch_local_fault(stop_commit ? stop_selected_code :
                                active_error_code_comb,
                            SOURCE_ACTIVE,
                            active_error_detail(current_producer_slot,
                                active_cmd_write, active_cmd_finalize,
                                active_cmd_index,
                                active_count_r[current_producer_slot_safe],
                                active_cmd_tag),
                            current_producer_slot,
                            stop_commit && stop_req_data_untrusted);
                        // The sticky local record always describes the local
                        // stream fault.  A same-edge owner fatal may select
                        // the terminal/fault-event status without erasing
                        // this current-list diagnostic code.
                        if (!local_error_valid)
                            local_error_code <= active_error_code_comb;
                        for (i = 0; i < 2; i = i + 1) begin
                            if (read_state_r[i] == READ_WAIT) begin
                                read_status_r[i] <= stop_commit ?
                                    stop_selected_code : active_error_code_comb;
                                if (!read_causal_r[i] ||
                                    (stop_commit && stop_req_data_untrusted)) begin
                                    read_data_usable_r[i] <= 1'b0;
                                    read_source_index_r[i] <= 9'd0;
                                end
                            end
                        end
                        if (stop_commit)
                            local_error_stop_epoch <=
                                stop_req_cancellation_epoch;
                    end else begin
                        if (active_cmd_write) begin
                            active_count_r[current_producer_slot_safe] <=
                                active_count_r[current_producer_slot_safe] + 1'b1;
                            last_index_r[current_producer_slot_safe] <= active_cmd_index;
                            last_valid_r[current_producer_slot_safe] <= 1'b1;
                        end
                        if (active_cmd_finalize) begin
                            terminal_tag_r[current_producer_slot_safe] <= active_cmd_tag;
                            producer_obligation <= 1'b0;
                            current_producer_valid <= 1'b0;
                            current_producer_slot <= 5'd0;
                            current_producer_token <= 32'd0;
                            current_producer_generation <= 16'd0;
                            producer_started <= 1'b0;
                            if (stop_pending || stop_commit) begin
                                state_r[current_producer_slot_safe] <=
                                    STATE_CANCEL_PENDING;
                                put_completion(stop_pending ? installed_stop_code :
                                    stop_selected_code, 1'b0, active_cmd_tag, 32'd0,
                                    active_count_r[current_producer_slot_safe] +
                                        active_cmd_write,
                                    active_cmd_write ? active_cmd_index :
                                        last_index_r[current_producer_slot_safe],
                                    active_cmd_write ||
                                        last_valid_r[current_producer_slot_safe]);
                            end else begin
                                state_r[current_producer_slot_safe] <= STATE_SEALED;
                                put_completion(STATUS_OK, 1'b1, active_cmd_tag,
                                    32'd0,
                                    active_count_r[current_producer_slot_safe] +
                                        active_cmd_write,
                                    active_cmd_write ? active_cmd_index :
                                        last_index_r[current_producer_slot_safe],
                                    active_cmd_write ||
                                        last_valid_r[current_producer_slot_safe]);
                            end
                        end else if (stop_commit) begin
                            state_r[current_producer_slot_safe] <= STATE_CANCEL_PENDING;
                        end
                    end
                end else if (state_r[current_producer_slot_safe] ==
                             STATE_POISON_DRAIN) begin
                    if (active_cmd_finalize &&
                        active_cmd_index ==
                            domain_bound_r[current_producer_slot_safe] - 1'b1) begin
                        terminal_tag_r[current_producer_slot_safe] <= active_cmd_tag;
                        producer_obligation <= 1'b0;
                        current_producer_valid <= 1'b0;
                        current_producer_slot <= 5'd0;
                        current_producer_token <= 32'd0;
                        current_producer_generation <= 16'd0;
                        producer_started <= 1'b0;
                        put_completion(producer_selected_status, 1'b0,
                            active_cmd_tag, producer_selected_detail,
                            active_count_r[current_producer_slot_safe],
                            last_index_r[current_producer_slot_safe],
                            last_valid_r[current_producer_slot_safe]);
                    end
                end else if (state_r[current_producer_slot_safe] ==
                             STATE_CANCEL_PENDING) begin
                    if (active_cmd_finalize &&
                        active_cmd_index ==
                            domain_bound_r[current_producer_slot_safe] - 1'b1) begin
                        terminal_tag_r[current_producer_slot_safe] <= active_cmd_tag;
                        producer_obligation <= 1'b0;
                        current_producer_valid <= 1'b0;
                        current_producer_slot <= 5'd0;
                        current_producer_token <= 32'd0;
                        current_producer_generation <= 16'd0;
                        producer_started <= 1'b0;
                        put_completion(producer_selected_status, 1'b0,
                            active_cmd_tag, producer_selected_detail,
                            active_count_r[current_producer_slot_safe],
                            last_index_r[current_producer_slot_safe],
                            last_valid_r[current_producer_slot_safe]);
                    end
                end
            end

            if (stop_pending && current_producer_valid && !producer_started &&
                current_producer_slot_in_range &&
                state_r[current_producer_slot_safe] == STATE_CANCEL_PENDING &&
                open_response_retired && !completion_valid) begin
                current_producer_valid <= 1'b0;
                current_producer_slot <= 5'd0;
                current_producer_token <= 32'd0;
                current_producer_generation <= 16'd0;
                producer_obligation <= 1'b0;
                put_completion(producer_selected_status, 1'b0, 16'd0,
                    producer_selected_detail,
                    active_count_r[current_producer_slot_safe],
                    last_index_r[current_producer_slot_safe],
                    last_valid_r[current_producer_slot_safe]);
            end

            if (internal_fault_comb) begin
                latch_local_fault(ERR_INTERNAL_STATE, SOURCE_INTERNAL,
                    internal_error_detail(internal_fault_id_comb,
                        internal_fault_slot_comb,
                        (internal_fault_slot_comb < 5'd21) ?
                            active_count_r[internal_slot_safe] : 9'd0,
                        (internal_fault_slot_comb < 5'd21) ?
                            ({1'b0, ref0_valid_r[internal_slot_safe]} +
                             {1'b0, ref1_valid_r[internal_slot_safe]}) : 2'd0,
                        (internal_fault_slot_comb < 5'd21) ?
                            read_ref_count_r[internal_slot_safe] : 2'd0,
                        (internal_fault_slot_comb < 5'd21) ?
                            state_r[internal_slot_safe] : STATE_FREE,
                        {current_producer_valid, producer_started,
                         completion_valid}),
                    internal_fault_slot_comb, 1'b1);
                for (i = 0; i < 2; i = i + 1) begin
                    if (read_state_r[i] == READ_WAIT) begin
                        read_status_r[i] <= ERR_INTERNAL_STATE;
                        read_data_usable_r[i] <= 1'b0;
                        read_source_index_r[i] <= 9'd0;
                    end
                end
                if (current_producer_valid) begin
                    producer_selected_status <= ERR_INTERNAL_STATE;
                    producer_selected_detail <= internal_error_detail(
                        internal_fault_id_comb, internal_fault_slot_comb,
                        active_count_r[current_producer_slot_safe],
                        {1'b0, ref0_valid_r[current_producer_slot_safe]} +
                            {1'b0, ref1_valid_r[current_producer_slot_safe]},
                        read_ref_count_r[current_producer_slot_safe],
                        state_r[current_producer_slot_safe],
                        {current_producer_valid, producer_started,
                         completion_valid});
                    active_count_r[current_producer_slot_safe] <=
                        active_count_r[current_producer_slot_safe];
                    last_index_r[current_producer_slot_safe] <=
                        last_index_r[current_producer_slot_safe];
                    last_valid_r[current_producer_slot_safe] <=
                        last_valid_r[current_producer_slot_safe];
                    if (active_fire && active_cmd_finalize &&
                        active_cmd_index ==
                            domain_bound_r[current_producer_slot_safe] - 1'b1) begin
                        producer_obligation <= 1'b0;
                        current_producer_valid <= 1'b0;
                        current_producer_slot <= 5'd0;
                        current_producer_token <= 32'd0;
                        current_producer_generation <= 16'd0;
                        producer_started <= 1'b0;
                        terminal_tag_r[current_producer_slot_safe] <= active_cmd_tag;
                        state_r[current_producer_slot_safe] <= STATE_CANCEL_PENDING;
                        put_completion(ERR_INTERNAL_STATE, 1'b0,
                            active_cmd_tag,
                            internal_error_detail(internal_fault_id_comb,
                                internal_fault_slot_comb,
                                active_count_r[current_producer_slot_safe],
                                {1'b0, ref0_valid_r[current_producer_slot_safe]} +
                                    {1'b0, ref1_valid_r[current_producer_slot_safe]},
                                read_ref_count_r[current_producer_slot_safe],
                                state_r[current_producer_slot_safe],
                                {current_producer_valid, producer_started,
                                 completion_valid}),
                            active_count_r[current_producer_slot_safe],
                            last_index_r[current_producer_slot_safe],
                            last_valid_r[current_producer_slot_safe]);
                    end else begin
                        state_r[current_producer_slot_safe] <= STATE_CANCEL_PENDING;
                    end
                end
            end

            if (new_unexpected_active_cmd && !internal_fault_comb) begin
                for (i = 0; i < 2; i = i + 1) begin
                    if (read_state_r[i] == READ_WAIT) begin
                        read_status_r[i] <= ERR_LOCAL_PROTOCOL;
                        read_data_usable_r[i] <= 1'b0;
                        read_source_index_r[i] <= 9'd0;
                    end
                end
                if (current_producer_valid)
                    latch_local_fault(ERR_LOCAL_PROTOCOL, SOURCE_ACTIVE,
                        active_error_detail(current_producer_slot,
                            active_cmd_write, active_cmd_finalize,
                            active_cmd_index,
                            active_count_r[current_producer_slot_safe],
                            active_cmd_tag), current_producer_slot, 1'b1);
                else if (completion_slot_reserved)
                    latch_local_fault(active_cmd_finalize ?
                            ERR_DUPLICATE_FINALIZE : ERR_LOCAL_PROTOCOL,
                        SOURCE_ACTIVE,
                        active_error_detail(completion_slot_locator,
                            active_cmd_write, active_cmd_finalize,
                            active_cmd_index, completion_active_count,
                            active_cmd_tag), completion_slot_locator, 1'b1);
                else
                    latch_local_fault(ERR_LOCAL_PROTOCOL, SOURCE_ACTIVE,
                        active_error_detail(5'd31, active_cmd_write,
                            active_cmd_finalize, active_cmd_index, 9'd0,
                            active_cmd_tag), 5'd31, 1'b1);
            end
        end
    end

endmodule
