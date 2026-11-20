`timescale 1ns/1ps

// Focused self-checking Verilog-2001 testbench for active_index_list_store.
//
// The directed cases intentionally exercise the architectural seams that are
// easiest to get wrong: OPEN/START atomic coupling, terminal-spike versus
// terminal-non-spike accounting, poison fail-drain, two-credit ordered reads,
// exact external references, ABA-safe release, and both forms of producer
// cancellation.  A verification-only dense-state-first fork is connected to
// the frozen pe_spike_decision/pe_active_index_writer leaves near the end.
module tb_active_index_list_store;
    localparam [2:0] ST_FREE           = 3'd0;
    localparam [2:0] ST_OPEN           = 3'd1;
    localparam [2:0] ST_SEALED         = 3'd2;
    localparam [2:0] ST_REFERENCED     = 3'd3;
    localparam [2:0] ST_POISON_DRAIN   = 3'd4;
    localparam [2:0] ST_CANCEL_PENDING = 3'd5;
    localparam [2:0] ST_CLOSING        = 3'd6;
    localparam [2:0] ST_ERROR          = 3'd7;

    localparam [2:0] OP_OPEN           = 3'd0;
    localparam [2:0] OP_PRODUCER_START = 3'd1;
    localparam [2:0] OP_REF_ACQUIRE    = 3'd2;
    localparam [2:0] OP_REF_TRANSFER   = 3'd3;
    localparam [2:0] OP_REF_RELEASE    = 3'd4;
    localparam [2:0] OP_LIST_RELEASE   = 3'd5;
    localparam [2:0] OP_CLEAR_ERROR    = 3'd6;

    localparam [1:0] REF_TEMPORARY  = 2'd1;
    localparam [1:0] REF_PENDING    = 2'd2;
    localparam [1:0] REF_PERSISTENT = 2'd3;

    localparam [2:0] REF_NEXT_LAYER = 3'd1;
    localparam [2:0] REF_RECURRENT  = 3'd2;
    localparam [2:0] REF_PROJECTION = 3'd3;
    localparam [2:0] REF_TEMP_ADD   = 3'd4;
    localparam [2:0] REF_TEMP_PROJ  = 3'd5;
    localparam [2:0] REF_CONTEXT    = 3'd6;

    localparam [7:0] STATUS_OK                = 8'h00;
    localparam [7:0] ERR_WRONG_STATE          = 8'h02;
    localparam [7:0] ERR_OWNER_MISMATCH        = 8'h04;
    localparam [7:0] ERR_BAD_DRAIN_TARGET      = 8'h08;
    localparam [7:0] ERR_ABORTED              = 8'h09;
    localparam [7:0] ERR_INTERNAL_STATE        = 8'h0b;
    localparam [7:0] ERR_STALE_TOKEN           = 8'h41;
    localparam [7:0] ERR_BAD_STAGE_DOMAIN       = 8'h43;
    localparam [7:0] ERR_BAD_DOMAIN_BOUND       = 8'h44;
    localparam [7:0] ERR_PROJECTION_PRODUCER    = 8'h45;
    localparam [7:0] ERR_REF_DUPLICATE         = 8'h46;
    localparam [7:0] ERR_REF_CAPACITY          = 8'h47;
    localparam [7:0] ERR_REF_NOT_FOUND         = 8'h48;
    localparam [7:0] ERR_BAD_ORDINAL           = 8'h4b;
    localparam [7:0] ERR_BAD_COMMAND_ENCODING  = 8'h4d;
    localparam [7:0] ERR_UNORDERED_INDEX       = 8'h4e;
    localparam [7:0] ERR_INDEX_OUT_OF_RANGE     = 8'h4f;
    localparam [7:0] ERR_EARLY_FINALIZE         = 8'h51;
    localparam [7:0] ERR_DUPLICATE_FINALIZE     = 8'h52;
    localparam [7:0] TEST_FATAL_STREAM           = 8'he1;
    localparam [7:0] TEST_FATAL_CLOSING          = 8'he2;
    localparam [7:0] TEST_FATAL_UNTRUSTED        = 8'he3;

    localparam [31:0] IMAGE0  = 32'h2026_0905;
    localparam [31:0] CONTEXT0= 32'h1100_0001;
    localparam [31:0] SEQ0    = 32'h2200_0001;
    localparam [31:0] CANCEL0 = 32'h3300_0001;
    localparam [31:0] REFOWN0 = 32'h4400_0001;

    reg clk;
    reg rst_n;

    wire [62:0] slot_state;
    wire [20:0] slot_authority_valid;
    wire [41:0] slot_external_ref_count;
    wire [41:0] slot_read_ref_count;
    wire [4:0] free_slot_count;
    wire allocation_candidate_valid;
    wire [4:0] allocation_candidate_slot;
    wire current_producer_valid;
    wire [4:0] current_producer_slot;
    wire [31:0] current_producer_token;
    wire [15:0] current_producer_generation;
    wire producer_started;
    wire producer_obligation;
    wire completion_slot_reserved;
    wire completion_event_pending;
    wire management_busy;
    wire closing_busy;
    wire [1:0] read_outstanding;
    wire read_pipeline_busy;
    wire [5:0] external_reference_total;
    wire [1:0] read_reference_total;
    wire [4:0] unreleased_error_slot_count;
    wire local_fault_pending;
    wire stop_pending;
    wire [31:0] last_stop_epoch;
    wire stop_drain_complete;
    wire store_quiescent;
    wire reset_required;
    wire wrap_recovery_required;

    reg mgmt_req_valid;
    wire mgmt_req_ready;
    reg [2:0] mgmt_req_opcode;
    reg [4:0] mgmt_req_slot_locator;
    reg [31:0] mgmt_req_list_token;
    reg [15:0] mgmt_req_list_generation;
    reg [31:0] mgmt_req_image_epoch;
    reg [3:0] mgmt_req_stage_id;
    reg [1:0] mgmt_req_logical_branch;
    reg [31:0] mgmt_req_context_generation;
    reg [31:0] mgmt_req_producer_sequence_ticket;
    reg [31:0] mgmt_req_cancellation_epoch;
    reg [31:0] mgmt_req_stop_epoch;
    reg [8:0] mgmt_req_domain_bound;
    reg mgmt_req_pe_recovery_safe;
    reg [2:0] mgmt_req_ref_owner_kind;
    reg [31:0] mgmt_req_ref_owner_token;
    reg [31:0] mgmt_req_ref_token;
    reg [1:0] mgmt_req_ref_phase;
    reg [2:0] mgmt_req_new_ref_owner_kind;
    reg [31:0] mgmt_req_new_ref_owner_token;
    reg [1:0] mgmt_req_new_ref_phase;
    reg mgmt_req_external_safe;
    reg [15:0] mgmt_req_tag;

    wire mgmt_rsp_valid;
    reg mgmt_rsp_ready;
    wire [2:0] mgmt_rsp_opcode;
    wire [7:0] mgmt_rsp_status;
    wire mgmt_rsp_committed;
    wire mgmt_rsp_released;
    wire [4:0] mgmt_rsp_slot_locator;
    wire [31:0] mgmt_rsp_list_token;
    wire [15:0] mgmt_rsp_list_generation;
    wire [31:0] mgmt_rsp_image_epoch;
    wire [3:0] mgmt_rsp_stage_id;
    wire [1:0] mgmt_rsp_logical_branch;
    wire [31:0] mgmt_rsp_context_generation;
    wire [31:0] mgmt_rsp_producer_sequence_ticket;
    wire [8:0] mgmt_rsp_domain_bound;
    wire [8:0] mgmt_rsp_reserved_capacity;
    wire [2:0] mgmt_rsp_state;
    wire [8:0] mgmt_rsp_active_count;
    wire [31:0] mgmt_rsp_ref_token;
    wire [2:0] mgmt_rsp_ref_owner_kind;
    wire [31:0] mgmt_rsp_ref_owner_token;
    wire [1:0] mgmt_rsp_ref_phase;
    wire [31:0] mgmt_rsp_cancellation_epoch;
    wire [31:0] mgmt_rsp_stop_epoch;
    wire [15:0] mgmt_rsp_tag;

    wire start_partner_valid;
    reg start_partner_ready;
    wire [4:0] start_partner_slot_locator;
    wire [31:0] start_partner_list_token;
    wire [15:0] start_partner_list_generation;
    wire [31:0] start_partner_image_epoch;
    wire [3:0] start_partner_stage_id;
    wire [1:0] start_partner_logical_branch;
    wire [31:0] start_partner_context_generation;
    wire [31:0] start_partner_producer_sequence_ticket;
    wire [31:0] start_partner_cancellation_epoch;
    wire [15:0] start_partner_tag;

    reg stop_req_valid;
    wire stop_req_ready;
    reg stop_req_is_fatal;
    reg stop_req_data_untrusted;
    reg stop_req_causal_producers_stopped;
    reg [31:0] stop_req_image_epoch;
    reg [31:0] stop_req_cancellation_epoch;
    reg [7:0] stop_req_code;
    reg [15:0] stop_req_tag;
    wire stop_rsp_valid;
    reg stop_rsp_ready;
    wire stop_rsp_committed;
    wire [7:0] stop_rsp_code;
    wire [31:0] stop_rsp_cancellation_epoch;
    wire [20:0] stop_rsp_error_slot_mask;
    wire stop_rsp_reset_required;
    wire [15:0] stop_rsp_tag;
    wire [7:0] stop_rsp_status;

    reg direct_active_cmd_valid;
    reg direct_active_cmd_write;
    reg [8:0] direct_active_cmd_index;
    reg [15:0] direct_active_cmd_tag;
    reg direct_active_cmd_finalize;
    reg use_frozen_path;
    wire active_cmd_valid;
    wire active_cmd_ready;
    wire active_cmd_write;
    wire [8:0] active_cmd_index;
    wire [15:0] active_cmd_tag;
    wire active_cmd_finalize;

    wire completion_valid;
    reg completion_ready;
    wire [7:0] completion_status;
    wire completion_sealed;
    wire [4:0] completion_slot_locator;
    wire [31:0] completion_list_token;
    wire [15:0] completion_list_generation;
    wire [31:0] completion_image_epoch;
    wire [3:0] completion_stage_id;
    wire [1:0] completion_logical_branch;
    wire [31:0] completion_context_generation;
    wire [31:0] completion_producer_sequence_ticket;
    wire [31:0] completion_cancellation_epoch;
    wire [31:0] completion_stop_epoch;
    wire [8:0] completion_domain_bound;
    wire [8:0] completion_active_count;
    wire [8:0] completion_last_committed_index;
    wire completion_last_valid;
    wire [15:0] completion_terminal_tag;
    wire [31:0] completion_error_detail;

    reg read_req_valid;
    wire read_req_ready;
    reg read_req_kind;
    reg [4:0] read_req_slot_locator;
    reg [31:0] read_req_list_token;
    reg [15:0] read_req_list_generation;
    reg [31:0] read_req_image_epoch;
    reg [3:0] read_req_stage_id;
    reg [1:0] read_req_logical_branch;
    reg [31:0] read_req_context_generation;
    reg [31:0] read_req_producer_sequence_ticket;
    reg [31:0] read_req_cancellation_epoch;
    reg read_req_causal_continuation;
    reg [31:0] read_req_stop_epoch;
    reg [31:0] read_req_external_ref_token;
    reg [8:0] read_req_ordinal;
    reg [15:0] read_req_tag;

    wire read_rsp_valid;
    reg read_rsp_ready;
    wire read_rsp_kind;
    wire [7:0] read_rsp_status;
    wire [4:0] read_rsp_slot_locator;
    wire [31:0] read_rsp_list_token;
    wire [15:0] read_rsp_list_generation;
    wire [31:0] read_rsp_image_epoch;
    wire [3:0] read_rsp_stage_id;
    wire [1:0] read_rsp_logical_branch;
    wire [31:0] read_rsp_context_generation;
    wire [31:0] read_rsp_producer_sequence_ticket;
    wire [31:0] read_rsp_cancellation_epoch;
    wire [31:0] read_rsp_stop_epoch;
    wire [8:0] read_rsp_domain_bound;
    wire [8:0] read_rsp_active_count;
    wire [15:0] read_rsp_terminal_tag;
    wire [2:0] read_rsp_state;
    wire [1:0] read_rsp_external_ref_count;
    wire [8:0] read_rsp_source_index;
    wire read_rsp_data_usable;
    wire [8:0] read_rsp_ordinal;
    wire read_rsp_last;
    wire read_rsp_sealed;
    wire read_rsp_causal_continuation;
    wire [31:0] read_rsp_external_ref_token;
    wire [15:0] read_rsp_tag;

    wire fault_event_valid;
    reg fault_event_ready;
    wire [7:0] fault_event_code;
    wire [3:0] fault_event_source;
    wire [31:0] fault_event_detail;
    wire [4:0] fault_event_slot_locator;
    wire [31:0] fault_event_list_token;
    wire [15:0] fault_event_list_generation;
    wire [31:0] fault_event_image_epoch;
    wire [3:0] fault_event_stage_id;
    wire [1:0] fault_event_logical_branch;
    wire [31:0] fault_event_context_generation;
    wire [31:0] fault_event_producer_sequence_ticket;
    wire [31:0] fault_event_cancellation_epoch;
    wire [31:0] fault_event_stop_epoch;
    wire fault_event_reset_required;

    wire local_error_valid;
    wire [7:0] local_error_code;
    wire [3:0] local_error_source;
    wire [31:0] local_error_detail;
    wire [4:0] local_error_slot_locator;
    wire [31:0] local_error_list_token;
    wire [15:0] local_error_list_generation;
    wire [31:0] local_error_image_epoch;
    wire [3:0] local_error_stage_id;
    wire [1:0] local_error_logical_branch;
    wire [31:0] local_error_context_generation;
    wire [31:0] local_error_producer_sequence_ticket;
    wire [31:0] local_error_cancellation_epoch;
    wire [31:0] local_error_stop_epoch;

    // Verification-only dense-state-first fork and frozen leaf wiring.
    reg qbn_valid;
    wire qbn_ready;
    reg signed [7:0] qbn_value;
    reg [8:0] qbn_index;
    reg [15:0] qbn_tag;
    reg qbn_last;
    reg dense_state_ready;
    wire dense_state_valid;
    wire signed [7:0] dense_state_value;
    wire [8:0] dense_state_index;
    wire [15:0] dense_state_tag;
    wire dense_state_last;

    reg fork_valid;
    reg fork_state_pending;
    reg fork_decision_pending;
    reg signed [7:0] fork_value;
    reg [8:0] fork_index;
    reg [15:0] fork_tag;
    reg fork_last;
    wire fork_decision_valid;
    wire fork_decision_ready;
    wire spike_event_valid;
    wire spike_event_ready;
    wire spike_event_spike;
    wire [8:0] spike_event_index;
    wire [15:0] spike_event_tag;
    wire spike_event_last;
    wire writer_cmd_valid;
    wire writer_cmd_ready;
    wire writer_cmd_write;
    wire [8:0] writer_cmd_index;
    wire [15:0] writer_cmd_tag;
    wire writer_cmd_finalize;
    wire fork_state_fire;
    wire fork_decision_fire;
    wire fork_retire;

    integer checks;
    integer failures;
    integer cycles;
    integer dense_fires;
    integer writer_fires;
    reg [31:0] stress_lfsr;
    integer i;
    reg [4:0] saved_slot;
    reg [31:0] saved_token;
    reg [15:0] saved_generation;
    reg [31:0] saved_ref_token;
    reg [31:0] saved_image;
    reg [3:0] saved_stage;
    reg [1:0] saved_branch;
    reg [31:0] saved_context;
    reg [31:0] saved_sequence;
    reg [31:0] saved_cancel;
    reg [8:0] saved_domain;
    reg [15:0] saved_terminal_tag;
    reg [4:0] live_slot [0:20];
    reg [31:0] live_token [0:20];
    reg [15:0] live_generation [0:20];
    reg [31:0] live_context [0:20];
    reg [31:0] live_sequence [0:20];
    reg [31:0] live_cancel [0:20];
    reg [31:0] live_ref_token [0:20];
    reg [31:0] live_ref_owner [0:20];

    assign active_cmd_valid    = use_frozen_path ? writer_cmd_valid    : direct_active_cmd_valid;
    assign active_cmd_write    = use_frozen_path ? writer_cmd_write    : direct_active_cmd_write;
    assign active_cmd_index    = use_frozen_path ? writer_cmd_index    : direct_active_cmd_index;
    assign active_cmd_tag      = use_frozen_path ? writer_cmd_tag      : direct_active_cmd_tag;
    assign active_cmd_finalize = use_frozen_path ? writer_cmd_finalize : direct_active_cmd_finalize;
    assign writer_cmd_ready    = use_frozen_path ? active_cmd_ready : 1'b0;

    assign dense_state_valid = fork_valid & fork_state_pending;
    assign dense_state_value = fork_value;
    assign dense_state_index = fork_index;
    assign dense_state_tag   = fork_tag;
    assign dense_state_last  = fork_last;
    assign fork_state_fire   = dense_state_valid & dense_state_ready;
    // The decision side may fire on the same edge as the dense-state side,
    // but never before it.  This is the frozen wrapper's dense-first rule.
    assign fork_decision_valid = fork_valid & fork_decision_pending &
                                 (~fork_state_pending | dense_state_ready);
    assign fork_decision_fire = fork_decision_valid & fork_decision_ready;
    assign fork_retire = fork_valid &
                         (~fork_state_pending | fork_state_fire) &
                         (~fork_decision_pending | fork_decision_fire);
    assign qbn_ready = ~fork_valid | fork_retire;

    pe_spike_decision #(.INDEX_WIDTH(9), .TAG_WIDTH(16)) u_spike (
        .in_valid(fork_decision_valid),
        .in_ready(fork_decision_ready),
        .state_q_in(fork_value),
        .index_in(fork_index),
        .tag_in(fork_tag),
        .last_in(fork_last),
        .out_valid(spike_event_valid),
        .out_ready(spike_event_ready),
        .spike_out(spike_event_spike),
        .index_out(spike_event_index),
        .tag_out(spike_event_tag),
        .last_out(spike_event_last)
    );

    pe_active_index_writer #(.INDEX_WIDTH(9), .TAG_WIDTH(16)) u_writer (
        .event_valid(spike_event_valid),
        .event_ready(spike_event_ready),
        .spike_in(spike_event_spike),
        .index_in(spike_event_index),
        .tag_in(spike_event_tag),
        .last_in(spike_event_last),
        .mem_cmd_valid(writer_cmd_valid),
        .mem_cmd_ready(writer_cmd_ready),
        .mem_cmd_write(writer_cmd_write),
        .mem_cmd_index(writer_cmd_index),
        .mem_cmd_tag(writer_cmd_tag),
        .mem_cmd_finalize(writer_cmd_finalize)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            fork_valid <= 1'b0;
            fork_state_pending <= 1'b0;
            fork_decision_pending <= 1'b0;
            fork_value <= 8'sd0;
            fork_index <= 9'd0;
            fork_tag <= 16'd0;
            fork_last <= 1'b0;
            dense_fires <= 0;
            writer_fires <= 0;
        end else begin
            if (fork_state_fire)
                dense_fires <= dense_fires + 1;
            if (writer_cmd_valid && writer_cmd_ready)
                writer_fires <= writer_fires + 1;

            if (qbn_ready) begin
                if (qbn_valid) begin
                    fork_valid <= 1'b1;
                    fork_state_pending <= 1'b1;
                    fork_decision_pending <= 1'b1;
                    fork_value <= qbn_value;
                    fork_index <= qbn_index;
                    fork_tag <= qbn_tag;
                    fork_last <= qbn_last;
                end else if (fork_retire) begin
                    fork_valid <= 1'b0;
                    fork_state_pending <= 1'b0;
                    fork_decision_pending <= 1'b0;
                end
            end else begin
                if (fork_state_fire)
                    fork_state_pending <= 1'b0;
                if (fork_decision_fire)
                    fork_decision_pending <= 1'b0;
            end
        end
    end

    active_index_list_store dut (
        .clk(clk),
        .rst_n(rst_n),
        .slot_state(slot_state),
        .slot_authority_valid(slot_authority_valid),
        .slot_external_ref_count(slot_external_ref_count),
        .slot_read_ref_count(slot_read_ref_count),
        .free_slot_count(free_slot_count),
        .allocation_candidate_valid(allocation_candidate_valid),
        .allocation_candidate_slot(allocation_candidate_slot),
        .current_producer_valid(current_producer_valid),
        .current_producer_slot(current_producer_slot),
        .current_producer_token(current_producer_token),
        .current_producer_generation(current_producer_generation),
        .producer_started(producer_started),
        .producer_obligation(producer_obligation),
        .completion_slot_reserved(completion_slot_reserved),
        .completion_event_pending(completion_event_pending),
        .management_busy(management_busy),
        .closing_busy(closing_busy),
        .read_outstanding(read_outstanding),
        .read_pipeline_busy(read_pipeline_busy),
        .external_reference_total(external_reference_total),
        .read_reference_total(read_reference_total),
        .unreleased_error_slot_count(unreleased_error_slot_count),
        .local_fault_pending(local_fault_pending),
        .stop_pending(stop_pending),
        .last_stop_epoch(last_stop_epoch),
        .stop_drain_complete(stop_drain_complete),
        .store_quiescent(store_quiescent),
        .reset_required(reset_required),
        .wrap_recovery_required(wrap_recovery_required),

        .mgmt_req_valid(mgmt_req_valid),
        .mgmt_req_ready(mgmt_req_ready),
        .mgmt_req_opcode(mgmt_req_opcode),
        .mgmt_req_slot_locator(mgmt_req_slot_locator),
        .mgmt_req_list_token(mgmt_req_list_token),
        .mgmt_req_list_generation(mgmt_req_list_generation),
        .mgmt_req_image_epoch(mgmt_req_image_epoch),
        .mgmt_req_stage_id(mgmt_req_stage_id),
        .mgmt_req_logical_branch(mgmt_req_logical_branch),
        .mgmt_req_context_generation(mgmt_req_context_generation),
        .mgmt_req_producer_sequence_ticket(mgmt_req_producer_sequence_ticket),
        .mgmt_req_cancellation_epoch(mgmt_req_cancellation_epoch),
        .mgmt_req_stop_epoch(mgmt_req_stop_epoch),
        .mgmt_req_domain_bound(mgmt_req_domain_bound),
        .mgmt_req_pe_recovery_safe(mgmt_req_pe_recovery_safe),
        .mgmt_req_ref_owner_kind(mgmt_req_ref_owner_kind),
        .mgmt_req_ref_owner_token(mgmt_req_ref_owner_token),
        .mgmt_req_ref_token(mgmt_req_ref_token),
        .mgmt_req_ref_phase(mgmt_req_ref_phase),
        .mgmt_req_new_ref_owner_kind(mgmt_req_new_ref_owner_kind),
        .mgmt_req_new_ref_owner_token(mgmt_req_new_ref_owner_token),
        .mgmt_req_new_ref_phase(mgmt_req_new_ref_phase),
        .mgmt_req_external_safe(mgmt_req_external_safe),
        .mgmt_req_tag(mgmt_req_tag),
        .mgmt_rsp_valid(mgmt_rsp_valid),
        .mgmt_rsp_ready(mgmt_rsp_ready),
        .mgmt_rsp_opcode(mgmt_rsp_opcode),
        .mgmt_rsp_status(mgmt_rsp_status),
        .mgmt_rsp_committed(mgmt_rsp_committed),
        .mgmt_rsp_released(mgmt_rsp_released),
        .mgmt_rsp_slot_locator(mgmt_rsp_slot_locator),
        .mgmt_rsp_list_token(mgmt_rsp_list_token),
        .mgmt_rsp_list_generation(mgmt_rsp_list_generation),
        .mgmt_rsp_image_epoch(mgmt_rsp_image_epoch),
        .mgmt_rsp_stage_id(mgmt_rsp_stage_id),
        .mgmt_rsp_logical_branch(mgmt_rsp_logical_branch),
        .mgmt_rsp_context_generation(mgmt_rsp_context_generation),
        .mgmt_rsp_producer_sequence_ticket(mgmt_rsp_producer_sequence_ticket),
        .mgmt_rsp_domain_bound(mgmt_rsp_domain_bound),
        .mgmt_rsp_reserved_capacity(mgmt_rsp_reserved_capacity),
        .mgmt_rsp_state(mgmt_rsp_state),
        .mgmt_rsp_active_count(mgmt_rsp_active_count),
        .mgmt_rsp_ref_token(mgmt_rsp_ref_token),
        .mgmt_rsp_ref_owner_kind(mgmt_rsp_ref_owner_kind),
        .mgmt_rsp_ref_owner_token(mgmt_rsp_ref_owner_token),
        .mgmt_rsp_ref_phase(mgmt_rsp_ref_phase),
        .mgmt_rsp_cancellation_epoch(mgmt_rsp_cancellation_epoch),
        .mgmt_rsp_stop_epoch(mgmt_rsp_stop_epoch),
        .mgmt_rsp_tag(mgmt_rsp_tag),

        .start_partner_valid(start_partner_valid),
        .start_partner_ready(start_partner_ready),
        .start_partner_slot_locator(start_partner_slot_locator),
        .start_partner_list_token(start_partner_list_token),
        .start_partner_list_generation(start_partner_list_generation),
        .start_partner_image_epoch(start_partner_image_epoch),
        .start_partner_stage_id(start_partner_stage_id),
        .start_partner_logical_branch(start_partner_logical_branch),
        .start_partner_context_generation(start_partner_context_generation),
        .start_partner_producer_sequence_ticket(start_partner_producer_sequence_ticket),
        .start_partner_cancellation_epoch(start_partner_cancellation_epoch),
        .start_partner_tag(start_partner_tag),

        .stop_req_valid(stop_req_valid),
        .stop_req_ready(stop_req_ready),
        .stop_req_is_fatal(stop_req_is_fatal),
        .stop_req_data_untrusted(stop_req_data_untrusted),
        .stop_req_causal_producers_stopped(stop_req_causal_producers_stopped),
        .stop_req_image_epoch(stop_req_image_epoch),
        .stop_req_cancellation_epoch(stop_req_cancellation_epoch),
        .stop_req_code(stop_req_code),
        .stop_req_tag(stop_req_tag),
        .stop_rsp_valid(stop_rsp_valid),
        .stop_rsp_ready(stop_rsp_ready),
        .stop_rsp_committed(stop_rsp_committed),
        .stop_rsp_code(stop_rsp_code),
        .stop_rsp_cancellation_epoch(stop_rsp_cancellation_epoch),
        .stop_rsp_error_slot_mask(stop_rsp_error_slot_mask),
        .stop_rsp_reset_required(stop_rsp_reset_required),
        .stop_rsp_tag(stop_rsp_tag),
        .stop_rsp_status(stop_rsp_status),

        .active_cmd_valid(active_cmd_valid),
        .active_cmd_ready(active_cmd_ready),
        .active_cmd_write(active_cmd_write),
        .active_cmd_index(active_cmd_index),
        .active_cmd_tag(active_cmd_tag),
        .active_cmd_finalize(active_cmd_finalize),

        .completion_valid(completion_valid),
        .completion_ready(completion_ready),
        .completion_status(completion_status),
        .completion_sealed(completion_sealed),
        .completion_slot_locator(completion_slot_locator),
        .completion_list_token(completion_list_token),
        .completion_list_generation(completion_list_generation),
        .completion_image_epoch(completion_image_epoch),
        .completion_stage_id(completion_stage_id),
        .completion_logical_branch(completion_logical_branch),
        .completion_context_generation(completion_context_generation),
        .completion_producer_sequence_ticket(completion_producer_sequence_ticket),
        .completion_cancellation_epoch(completion_cancellation_epoch),
        .completion_stop_epoch(completion_stop_epoch),
        .completion_domain_bound(completion_domain_bound),
        .completion_active_count(completion_active_count),
        .completion_last_committed_index(completion_last_committed_index),
        .completion_last_valid(completion_last_valid),
        .completion_terminal_tag(completion_terminal_tag),
        .completion_error_detail(completion_error_detail),

        .read_req_valid(read_req_valid),
        .read_req_ready(read_req_ready),
        .read_req_kind(read_req_kind),
        .read_req_slot_locator(read_req_slot_locator),
        .read_req_list_token(read_req_list_token),
        .read_req_list_generation(read_req_list_generation),
        .read_req_image_epoch(read_req_image_epoch),
        .read_req_stage_id(read_req_stage_id),
        .read_req_logical_branch(read_req_logical_branch),
        .read_req_context_generation(read_req_context_generation),
        .read_req_producer_sequence_ticket(read_req_producer_sequence_ticket),
        .read_req_cancellation_epoch(read_req_cancellation_epoch),
        .read_req_causal_continuation(read_req_causal_continuation),
        .read_req_stop_epoch(read_req_stop_epoch),
        .read_req_external_ref_token(read_req_external_ref_token),
        .read_req_ordinal(read_req_ordinal),
        .read_req_tag(read_req_tag),
        .read_rsp_valid(read_rsp_valid),
        .read_rsp_ready(read_rsp_ready),
        .read_rsp_kind(read_rsp_kind),
        .read_rsp_status(read_rsp_status),
        .read_rsp_slot_locator(read_rsp_slot_locator),
        .read_rsp_list_token(read_rsp_list_token),
        .read_rsp_list_generation(read_rsp_list_generation),
        .read_rsp_image_epoch(read_rsp_image_epoch),
        .read_rsp_stage_id(read_rsp_stage_id),
        .read_rsp_logical_branch(read_rsp_logical_branch),
        .read_rsp_context_generation(read_rsp_context_generation),
        .read_rsp_producer_sequence_ticket(read_rsp_producer_sequence_ticket),
        .read_rsp_cancellation_epoch(read_rsp_cancellation_epoch),
        .read_rsp_stop_epoch(read_rsp_stop_epoch),
        .read_rsp_domain_bound(read_rsp_domain_bound),
        .read_rsp_active_count(read_rsp_active_count),
        .read_rsp_terminal_tag(read_rsp_terminal_tag),
        .read_rsp_state(read_rsp_state),
        .read_rsp_external_ref_count(read_rsp_external_ref_count),
        .read_rsp_source_index(read_rsp_source_index),
        .read_rsp_data_usable(read_rsp_data_usable),
        .read_rsp_ordinal(read_rsp_ordinal),
        .read_rsp_last(read_rsp_last),
        .read_rsp_sealed(read_rsp_sealed),
        .read_rsp_causal_continuation(read_rsp_causal_continuation),
        .read_rsp_external_ref_token(read_rsp_external_ref_token),
        .read_rsp_tag(read_rsp_tag),

        .fault_event_valid(fault_event_valid),
        .fault_event_ready(fault_event_ready),
        .fault_event_code(fault_event_code),
        .fault_event_source(fault_event_source),
        .fault_event_detail(fault_event_detail),
        .fault_event_slot_locator(fault_event_slot_locator),
        .fault_event_list_token(fault_event_list_token),
        .fault_event_list_generation(fault_event_list_generation),
        .fault_event_image_epoch(fault_event_image_epoch),
        .fault_event_stage_id(fault_event_stage_id),
        .fault_event_logical_branch(fault_event_logical_branch),
        .fault_event_context_generation(fault_event_context_generation),
        .fault_event_producer_sequence_ticket(fault_event_producer_sequence_ticket),
        .fault_event_cancellation_epoch(fault_event_cancellation_epoch),
        .fault_event_stop_epoch(fault_event_stop_epoch),
        .fault_event_reset_required(fault_event_reset_required),
        .local_error_valid(local_error_valid),
        .local_error_code(local_error_code),
        .local_error_source(local_error_source),
        .local_error_detail(local_error_detail),
        .local_error_slot_locator(local_error_slot_locator),
        .local_error_list_token(local_error_list_token),
        .local_error_list_generation(local_error_list_generation),
        .local_error_image_epoch(local_error_image_epoch),
        .local_error_stage_id(local_error_stage_id),
        .local_error_logical_branch(local_error_logical_branch),
        .local_error_context_generation(local_error_context_generation),
        .local_error_producer_sequence_ticket(local_error_producer_sequence_ticket),
        .local_error_cancellation_epoch(local_error_cancellation_epoch),
        .local_error_stop_epoch(local_error_stop_epoch)
    );

    function [2:0] state_of;
        input [4:0] slot;
        reg [62:0] shifted;
        begin
            shifted = slot_state >> (slot * 3);
            state_of = shifted[2:0];
        end
    endfunction

    task check;
        input condition;
        input [8*96-1:0] message;
        begin
            checks = checks + 1;
            if (condition !== 1'b1) begin
                failures = failures + 1;
                $display("FAIL cycle=%0d: %0s", cycles, message);
            end
        end
    endtask

    task trace_basic_point;
        input integer step_number;
        begin
            $display("TRACE_AILS step=%0d state=%0d free=%0d producer=%0d started=%0d obligation=%0d completion=%0d cstatus=%02h ccount=%0d extrefs=%0d readrefs=%0d reads=%0d stop=%0d fault=%0d reset=%0d",
                     step_number, state_of(saved_slot), free_slot_count,
                     current_producer_valid, producer_started,
                     producer_obligation, completion_valid,
                     completion_valid ? completion_status : 8'd0,
                     completion_valid ? completion_active_count : 9'd0,
                     external_reference_total, read_reference_total,
                     read_outstanding, stop_pending, local_fault_pending,
                     reset_required);
        end
    endtask

    // Compact machine-readable differential transcript.  Each record is
    // emitted immediately after the clock edge that commits the named
    // operation (or while a ready/valid payload is intentionally held).
    // The dependency-free Python oracle compares every field and rejects
    // missing, duplicated, reordered, or X/Z-bearing records.
    task trace_diff_point;
        input integer step;
        begin
            $display("TRACE_AILS_DIFF step=%0d state=%0d free=%0d producer=%0d started=%0d obligation=%0d completion=%0d cstatus=%02h extrefs=%0d readrefs=%0d reads=%0d rvalid=%0d rstatus=%02h rusable=%0d mgvalid=%0d mgstatus=%02h mgcommit=%0d mgrelease=%0d stop=%0d stoprsp=%0d fault=%0d reset=%0d",
                     step, state_of(saved_slot), free_slot_count,
                     current_producer_valid, producer_started,
                     producer_obligation, completion_valid,
                     completion_status, external_reference_total,
                     read_reference_total, read_outstanding, read_rsp_valid,
                     read_rsp_status, read_rsp_data_usable, mgmt_rsp_valid,
                     mgmt_rsp_status, mgmt_rsp_committed, mgmt_rsp_released,
                     stop_pending, stop_rsp_valid, fault_event_valid,
                     reset_required);
        end
    endtask

    task clear_request_inputs;
        begin
            mgmt_req_valid = 1'b0;
            mgmt_req_opcode = OP_OPEN;
            mgmt_req_slot_locator = 5'd0;
            mgmt_req_list_token = 32'd0;
            mgmt_req_list_generation = 16'd0;
            mgmt_req_image_epoch = 32'd0;
            mgmt_req_stage_id = 4'd0;
            mgmt_req_logical_branch = 2'd0;
            mgmt_req_context_generation = 32'd0;
            mgmt_req_producer_sequence_ticket = 32'd0;
            mgmt_req_cancellation_epoch = 32'd0;
            mgmt_req_stop_epoch = 32'd0;
            mgmt_req_domain_bound = 9'd0;
            mgmt_req_pe_recovery_safe = 1'b0;
            mgmt_req_ref_owner_kind = 3'd0;
            mgmt_req_ref_owner_token = 32'd0;
            mgmt_req_ref_token = 32'd0;
            mgmt_req_ref_phase = 2'd0;
            mgmt_req_new_ref_owner_kind = 3'd0;
            mgmt_req_new_ref_owner_token = 32'd0;
            mgmt_req_new_ref_phase = 2'd0;
            mgmt_req_external_safe = 1'b0;
            mgmt_req_tag = 16'd0;

            stop_req_valid = 1'b0;
            stop_req_is_fatal = 1'b0;
            stop_req_data_untrusted = 1'b0;
            stop_req_causal_producers_stopped = 1'b0;
            stop_req_image_epoch = 32'd0;
            stop_req_cancellation_epoch = 32'd0;
            stop_req_code = 8'd0;
            stop_req_tag = 16'd0;

            direct_active_cmd_valid = 1'b0;
            direct_active_cmd_write = 1'b0;
            direct_active_cmd_index = 9'd0;
            direct_active_cmd_tag = 16'd0;
            direct_active_cmd_finalize = 1'b0;
            use_frozen_path = 1'b0;

            read_req_valid = 1'b0;
            read_req_kind = 1'b0;
            read_req_slot_locator = 5'd0;
            read_req_list_token = 32'd0;
            read_req_list_generation = 16'd0;
            read_req_image_epoch = 32'd0;
            read_req_stage_id = 4'd0;
            read_req_logical_branch = 2'd0;
            read_req_context_generation = 32'd0;
            read_req_producer_sequence_ticket = 32'd0;
            read_req_cancellation_epoch = 32'd0;
            read_req_causal_continuation = 1'b0;
            read_req_stop_epoch = 32'd0;
            read_req_external_ref_token = 32'd0;
            read_req_ordinal = 9'd0;
            read_req_tag = 16'd0;

            qbn_valid = 1'b0;
            qbn_value = 8'sd0;
            qbn_index = 9'd0;
            qbn_tag = 16'd0;
            qbn_last = 1'b0;
            dense_state_ready = 1'b1;
        end
    endtask

    task drive_saved_identity;
        begin
            mgmt_req_slot_locator = saved_slot;
            mgmt_req_list_token = saved_token;
            mgmt_req_list_generation = saved_generation;
            mgmt_req_image_epoch = saved_image;
            mgmt_req_stage_id = saved_stage;
            mgmt_req_logical_branch = saved_branch;
            mgmt_req_context_generation = saved_context;
            mgmt_req_producer_sequence_ticket = saved_sequence;
            mgmt_req_cancellation_epoch = saved_cancel;
            mgmt_req_domain_bound = saved_domain;
        end
    endtask

    task drive_saved_read_identity;
        begin
            read_req_slot_locator = saved_slot;
            read_req_list_token = saved_token;
            read_req_list_generation = saved_generation;
            read_req_image_epoch = saved_image;
            read_req_stage_id = saved_stage;
            read_req_logical_branch = saved_branch;
            read_req_context_generation = saved_context;
            read_req_producer_sequence_ticket = saved_sequence;
            read_req_cancellation_epoch = saved_cancel;
            read_req_causal_continuation = 1'b0;
            read_req_stop_epoch = 32'd0;
            read_req_external_ref_token = 32'd0;
        end
    endtask

    task reset_dut;
        begin
            @(negedge clk);
            clear_request_inputs;
            mgmt_rsp_ready = 1'b0;
            stop_rsp_ready = 1'b0;
            completion_ready = 1'b0;
            read_rsp_ready = 1'b0;
            fault_event_ready = 1'b0;
            start_partner_ready = 1'b0;
            rst_n = 1'b0;
            repeat (3) @(posedge clk);
            @(negedge clk);
            rst_n = 1'b1;
            repeat (3) @(posedge clk);
            #1;
            check(free_slot_count == 5'd21, "reset exposes all 21 FREE slots");
            check(current_producer_valid == 1'b0, "reset clears producer authority");
            check(read_outstanding == 2'd0, "reset clears read credits");
            check(slot_authority_valid == 21'd0, "reset clears all descriptor authority");
            check(!completion_valid && !mgmt_rsp_valid && !stop_rsp_valid,
                  "reset clears held terminal outputs");
        end
    endtask

    task wait_mgmt_ready_and_fire;
        integer timeout;
        begin
            timeout = 0;
            // Callers drive request fields on a falling edge.  Allow one
            // delta for the combinational arbiter before sampling ready so a
            // request cannot fire at the intervening rising edge unnoticed.
            #1;
            while ((mgmt_req_ready !== 1'b1) && (timeout < 200)) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 200)
                $display("MGMT_TIMEOUT op=%0d state=%0d stop=%0d stop_rsp=%0d local_fault=%0d reset=%0d busy=%0d closing=%0d valid=%0d slot=%0d token=%08h gen=%04h stop_epoch=%08h",
                         mgmt_req_opcode, state_of(saved_slot), stop_pending,
                         stop_rsp_valid, local_fault_pending, reset_required,
                         management_busy, closing_busy, mgmt_rsp_valid,
                         mgmt_req_slot_locator, mgmt_req_list_token,
                         mgmt_req_list_generation, mgmt_req_stop_epoch);
            check(timeout < 200, "management request eventually ready");
            @(posedge clk);
            #1;
            @(negedge clk);
            mgmt_req_valid = 1'b0;
        end
    endtask

    task retire_mgmt_response;
        integer timeout;
        begin
            timeout = 0;
            while ((mgmt_rsp_valid !== 1'b1) && (timeout < 200)) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            check(timeout < 200, "management response materializes");
            @(negedge clk);
            mgmt_rsp_ready = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            mgmt_rsp_ready = 1'b0;
        end
    endtask

    task open_list;
        input [3:0] stage;
        input [1:0] branch;
        input [8:0] domain;
        input [31:0] context_id;
        input [31:0] sequence_id;
        input [31:0] cancel_id;
        integer timeout;
        reg [31:0] hold_token;
        reg [15:0] hold_generation;
        reg [4:0] hold_slot;
        begin
            timeout = 0;
            while ((allocation_candidate_valid !== 1'b1) && (timeout < 100)) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            check(timeout < 100, "allocator produces registered FREE candidate");
            @(negedge clk);
            mgmt_req_opcode = OP_OPEN;
            mgmt_req_slot_locator = 5'd31;
            mgmt_req_list_token = 32'hdead_beef;
            mgmt_req_list_generation = 16'hbeef;
            mgmt_req_image_epoch = IMAGE0;
            mgmt_req_stage_id = stage;
            mgmt_req_logical_branch = branch;
            mgmt_req_context_generation = context_id;
            mgmt_req_producer_sequence_ticket = sequence_id;
            mgmt_req_cancellation_epoch = cancel_id;
            mgmt_req_stop_epoch = 32'd0;
            mgmt_req_domain_bound = domain;
            mgmt_req_pe_recovery_safe = 1'b1;
            mgmt_req_external_safe = 1'b0;
            mgmt_req_tag = 16'h0101;
            mgmt_req_valid = 1'b1;
            wait_mgmt_ready_and_fire;
            check(mgmt_rsp_valid, "OPEN produces held response on acceptance edge");
            check(mgmt_rsp_status == STATUS_OK && mgmt_rsp_committed,
                  "OPEN response reports committed success");
            check(mgmt_rsp_opcode == OP_OPEN && mgmt_rsp_tag == 16'h0101,
                  "OPEN response preserves opcode and caller tag");
            check(mgmt_rsp_slot_locator < 5'd21, "OPEN returns legal store-selected slot");
            check(mgmt_rsp_list_token != 32'd0 && mgmt_rsp_list_generation != 16'd0,
                  "OPEN allocates nonzero token and generation");
            check(mgmt_rsp_reserved_capacity == 9'd320,
                  "uniform slot reserves 320 index entries");
            saved_slot = mgmt_rsp_slot_locator;
            saved_token = mgmt_rsp_list_token;
            saved_generation = mgmt_rsp_list_generation;
            saved_image = IMAGE0;
            saved_stage = stage;
            saved_branch = branch;
            saved_context = context_id;
            saved_sequence = sequence_id;
            saved_cancel = cancel_id;
            saved_domain = domain;
            hold_slot = mgmt_rsp_slot_locator;
            hold_token = mgmt_rsp_list_token;
            hold_generation = mgmt_rsp_list_generation;
            repeat (2) begin
                @(posedge clk);
                #1;
                check(mgmt_rsp_valid && mgmt_rsp_slot_locator == hold_slot &&
                      mgmt_rsp_list_token == hold_token &&
                      mgmt_rsp_list_generation == hold_generation,
                      "stalled OPEN response remains stable");
            end
            check(current_producer_valid && !producer_started && !producer_obligation,
                  "OPEN owns producer slot without inventing finalize debt");
            check(state_of(saved_slot) == ST_OPEN, "OPEN slot state is OPEN");
            retire_mgmt_response;
        end
    endtask

    task start_list;
        integer timeout;
        reg [31:0] hold_token;
        begin
            @(negedge clk);
            drive_saved_identity;
            mgmt_req_opcode = OP_PRODUCER_START;
            mgmt_req_pe_recovery_safe = 1'b1;
            mgmt_req_tag = 16'h0202;
            start_partner_ready = 1'b0;
            mgmt_req_valid = 1'b1;
            timeout = 0;
            #1;
            while ((start_partner_valid !== 1'b1) && (timeout < 100)) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            check(timeout < 100, "exact START exposes partner valid");
            check(mgmt_req_ready == 1'b0,
                  "START cannot commit while first-job partner is stalled");
            hold_token = start_partner_list_token;
            repeat (3) begin
                @(posedge clk);
                #1;
                check(start_partner_valid && !mgmt_req_ready &&
                      start_partner_list_token == hold_token,
                      "START partner payload stable under backpressure");
            end
            @(negedge clk);
            start_partner_ready = 1'b1;
            check(start_partner_valid, "START valid does not depend on partner ready");
            @(posedge clk);
            #1;
            check(mgmt_rsp_valid && mgmt_rsp_status == STATUS_OK && mgmt_rsp_committed,
                  "START and partner commit atomically");
            check(producer_started && producer_obligation,
                  "START creates exactly one real-finalize obligation");
            @(negedge clk);
            mgmt_req_valid = 1'b0;
            start_partner_ready = 1'b0;
            retire_mgmt_response;
        end
    endtask

    task send_direct_command;
        input do_write;
        input [8:0] index_value;
        input [15:0] tag_value;
        input do_finalize;
        integer timeout;
        begin
            @(negedge clk);
            direct_active_cmd_write = do_write;
            direct_active_cmd_index = index_value;
            direct_active_cmd_tag = tag_value;
            direct_active_cmd_finalize = do_finalize;
            direct_active_cmd_valid = 1'b1;
            timeout = 0;
            while ((active_cmd_ready !== 1'b1) && (timeout < 100)) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            check(timeout < 100, "active command sink eventually ready");
            @(posedge clk);
            #1;
            @(negedge clk);
            direct_active_cmd_valid = 1'b0;
            direct_active_cmd_write = 1'b0;
            direct_active_cmd_finalize = 1'b0;
        end
    endtask

    task wait_for_completion;
        input [7:0] expected_status;
        input expected_sealed;
        input [8:0] expected_count;
        input [15:0] expected_tag;
        integer timeout;
        reg [31:0] hold_detail;
        begin
            timeout = 0;
            while ((completion_valid !== 1'b1) && (timeout < 200)) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            check(timeout < 200, "completion event materializes");
            check(completion_status == expected_status,
                  "completion returns expected terminal status");
            check(completion_sealed == expected_sealed,
                  "completion sealed bit matches authority result");
            check(completion_active_count == expected_count,
                  "completion active count is exact");
            check(completion_terminal_tag == expected_tag,
                  "completion preserves real-finalize terminal tag");
            check(completion_slot_locator == saved_slot &&
                  completion_list_token == saved_token &&
                  completion_list_generation == saved_generation,
                  "completion carries exact list identity");
            hold_detail = completion_error_detail;
            repeat (2) begin
                @(posedge clk);
                #1;
                check(completion_valid && completion_status == expected_status &&
                      completion_error_detail == hold_detail,
                      "held completion event remains immutable");
            end
        end
    endtask

    task retire_completion;
        begin
            @(negedge clk);
            completion_ready = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            completion_ready = 1'b0;
        end
    endtask

    task acquire_context_reference;
        input [31:0] owner_token;
        begin
            @(negedge clk);
            drive_saved_identity;
            mgmt_req_opcode = OP_REF_ACQUIRE;
            mgmt_req_ref_owner_kind = REF_CONTEXT;
            mgmt_req_ref_owner_token = owner_token;
            mgmt_req_ref_phase = REF_PERSISTENT;
            mgmt_req_tag = 16'h0a01;
            mgmt_req_valid = 1'b1;
            wait_mgmt_ready_and_fire;
            check(mgmt_rsp_valid && mgmt_rsp_status == STATUS_OK &&
                  mgmt_rsp_committed, "exact external reference acquire commits");
            check(mgmt_rsp_ref_token != 32'd0 &&
                  mgmt_rsp_ref_owner_kind == REF_CONTEXT &&
                  mgmt_rsp_ref_owner_token == owner_token &&
                  mgmt_rsp_ref_phase == REF_PERSISTENT,
                  "reference response returns exact allocated authority");
            saved_ref_token = mgmt_rsp_ref_token;
            check(state_of(saved_slot) == ST_REFERENCED &&
                  external_reference_total == 6'd1,
                  "first reference moves SEALED list to REFERENCED");
            retire_mgmt_response;
        end
    endtask

    task duplicate_reference_must_fail;
        input [31:0] owner_token;
        begin
            @(negedge clk);
            drive_saved_identity;
            mgmt_req_opcode = OP_REF_ACQUIRE;
            mgmt_req_ref_owner_kind = REF_CONTEXT;
            mgmt_req_ref_owner_token = owner_token;
            mgmt_req_ref_phase = REF_PERSISTENT;
            mgmt_req_tag = 16'h0a02;
            mgmt_req_valid = 1'b1;
            wait_mgmt_ready_and_fire;
            check(mgmt_rsp_valid && mgmt_rsp_status == ERR_REF_DUPLICATE &&
                  !mgmt_rsp_committed,
                  "duplicate external owner is rejected without side effect");
            check(external_reference_total == 6'd1,
                  "duplicate reference does not double-count");
            retire_mgmt_response;
        end
    endtask

    task release_context_reference;
        input [31:0] owner_token;
        input [31:0] cleanup_stop_epoch;
        input [7:0] expected_status;
        begin
            @(negedge clk);
            drive_saved_identity;
            mgmt_req_opcode = OP_REF_RELEASE;
            mgmt_req_stop_epoch = cleanup_stop_epoch;
            mgmt_req_ref_owner_kind = REF_CONTEXT;
            mgmt_req_ref_owner_token = owner_token;
            mgmt_req_ref_token = saved_ref_token;
            mgmt_req_ref_phase = REF_PERSISTENT;
            mgmt_req_tag = 16'h0a03;
            mgmt_req_valid = 1'b1;
            wait_mgmt_ready_and_fire;
            check(mgmt_rsp_valid && mgmt_rsp_status == expected_status &&
                  mgmt_rsp_committed && mgmt_rsp_released,
                  "exact reference release commits once");
            check(external_reference_total == 6'd0,
                  "exact reference release decrements count to zero");
            retire_mgmt_response;
        end
    endtask

    task release_list;
        input [31:0] cleanup_stop_epoch;
        input [7:0] expected_status;
        begin
            @(negedge clk);
            drive_saved_identity;
            mgmt_req_opcode = OP_LIST_RELEASE;
            mgmt_req_stop_epoch = cleanup_stop_epoch;
            mgmt_req_external_safe = 1'b1;
            mgmt_req_tag = 16'h0b01;
            mgmt_req_valid = 1'b1;
            wait_mgmt_ready_and_fire;
            check(mgmt_rsp_valid && mgmt_rsp_status == expected_status &&
                  mgmt_rsp_committed && mgmt_rsp_released,
                  "exact list release materializes terminal response");
            check(state_of(saved_slot) == ST_CLOSING &&
                  slot_authority_valid[saved_slot],
                  "held release response fences slot reuse in CLOSING");
            repeat (2) begin
                @(posedge clk);
                #1;
                check(state_of(saved_slot) == ST_CLOSING && mgmt_rsp_valid,
                      "stalled list-release response retains old authority");
            end
            retire_mgmt_response;
            @(posedge clk);
            #1;
            check(state_of(saved_slot) == ST_FREE &&
                  !slot_authority_valid[saved_slot],
                  "release response handshake is the FREE commit point");
        end
    endtask

    task clear_local_error_scope;
        input [31:0] cleanup_stop_epoch;
        begin
            @(negedge clk);
            drive_saved_identity;
            mgmt_req_opcode = OP_CLEAR_ERROR;
            mgmt_req_stop_epoch = cleanup_stop_epoch;
            mgmt_req_external_safe = 1'b1;
            mgmt_req_tag = 16'h0b02;
            mgmt_req_valid = 1'b1;
            wait_mgmt_ready_and_fire;
            check(mgmt_rsp_valid && mgmt_rsp_committed,
                  "exact drained local error can be cleared");
            check(!local_error_valid && !local_fault_pending,
                  "CLEAR_ERROR removes local first-error fence only after cleanup");
            retire_mgmt_response;
        end
    endtask

    task issue_stop;
        input [31:0] stop_epoch;
        input stop_fatal;
        input data_untrusted;
        input [7:0] stop_code;
        begin
            @(negedge clk);
            stop_req_is_fatal = stop_fatal;
            stop_req_data_untrusted = data_untrusted;
            stop_req_causal_producers_stopped = data_untrusted ? 1'b0 : 1'b1;
            stop_req_image_epoch = saved_image;
            stop_req_cancellation_epoch = stop_epoch;
            stop_req_code = stop_code;
            stop_req_tag = 16'h0c01;
            stop_req_valid = 1'b1;
            #1;
            while (stop_req_ready !== 1'b1)
                @(negedge clk);
            @(posedge clk);
            #1;
            check(stop_pending, "accepted stop installs registered admission fence");
            @(negedge clk);
            stop_req_valid = 1'b0;
        end
    endtask

    task wait_stop_response;
        input [7:0] expected_code;
        input [31:0] expected_epoch;
        integer timeout;
        begin
            timeout = 0;
            while ((stop_rsp_valid !== 1'b1) && (timeout < 400)) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            check(timeout < 400, "stop response waits for and observes local causal drain");
            check(stop_rsp_committed && stop_rsp_status == expected_code &&
                  stop_rsp_code == expected_code &&
                  stop_rsp_cancellation_epoch == expected_epoch,
                  "stop response preserves installed stop identity/code");
            check(stop_rsp_reset_required == reset_required,
                  "stop response snapshots the current coordinated-reset requirement");
            @(negedge clk);
            stop_rsp_ready = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            stop_rsp_ready = 1'b0;
        end
    endtask

    task drive_one_read;
        input kind;
        input [8:0] ordinal;
        input [15:0] tag_value;
        integer timeout;
        begin
            @(negedge clk);
            drive_saved_read_identity;
            read_req_kind = kind;
            read_req_ordinal = ordinal;
            read_req_tag = tag_value;
            read_req_valid = 1'b1;
            timeout = 0;
            #1;
            while ((read_req_ready !== 1'b1) && (timeout < 200)) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            check(timeout < 200, "read request eventually gets order-slot credit");
            @(posedge clk);
            #1;
            @(negedge clk);
            read_req_valid = 1'b0;
        end
    endtask

    task retire_read_response;
        begin
            @(negedge clk);
            read_rsp_ready = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            read_rsp_ready = 1'b0;
        end
    endtask

    task send_qbn_scalar;
        input signed [7:0] value;
        input [8:0] scalar_index;
        input [15:0] scalar_tag;
        input scalar_last;
        integer timeout;
        begin
            @(negedge clk);
            qbn_value = value;
            qbn_index = scalar_index;
            qbn_tag = scalar_tag;
            qbn_last = scalar_last;
            qbn_valid = 1'b1;
            timeout = 0;
            while ((qbn_ready !== 1'b1) && (timeout < 100)) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            check(timeout < 100, "verification QBN fork accepts scalar");
            @(posedge clk);
            #1;
            @(negedge clk);
            qbn_valid = 1'b0;
        end
    endtask

    task send_qbn_scalar_random_backpressure;
        input signed [7:0] value;
        input [8:0] scalar_index;
        input [15:0] scalar_tag;
        input scalar_last;
        integer timeout;
        begin
            // Each scalar is admitted into the one-entry verification fork,
            // then its dense-state side sees deterministic pseudo-random
            // backpressure.  A forced-ready escape every 16 attempts makes
            // the test bounded without weakening the deadlock check.
            @(negedge clk);
            qbn_value = value;
            qbn_index = scalar_index;
            qbn_tag = scalar_tag;
            qbn_last = scalar_last;
            qbn_valid = 1'b1;
            #1;
            check(qbn_ready,
                  "random-stress scalar finds an empty/replacing fork slot");
            @(posedge clk);
            #1;
            @(negedge clk);
            qbn_valid = 1'b0;
            timeout = 0;
            while ((fork_valid !== 1'b0) && (timeout < 128)) begin
                stress_lfsr = {stress_lfsr[30:0],
                    stress_lfsr[31] ^ stress_lfsr[21] ^
                    stress_lfsr[1] ^ stress_lfsr[0]};
                dense_state_ready = stress_lfsr[0] | stress_lfsr[5] |
                    (timeout[3:0] == 4'hf);
                @(posedge clk);
                #1;
                @(negedge clk);
                timeout = timeout + 1;
            end
            check(timeout < 128,
                  "random dense-state backpressure cannot deadlock QBN fork");
            dense_state_ready = 1'b1;
        end
    endtask

    task wait_fork_idle;
        integer timeout;
        begin
            timeout = 0;
            while ((fork_valid !== 1'b0) && (timeout < 100)) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            check(timeout < 100, "verification dense-first fork drains");
        end
    endtask

    task save_live_handle;
        input integer live_index;
        begin
            live_slot[live_index] = saved_slot;
            live_token[live_index] = saved_token;
            live_generation[live_index] = saved_generation;
            live_context[live_index] = saved_context;
            live_sequence[live_index] = saved_sequence;
            live_cancel[live_index] = saved_cancel;
            live_ref_token[live_index] = saved_ref_token;
        end
    endtask

    task load_live_handle;
        input integer live_index;
        begin
            saved_slot = live_slot[live_index];
            saved_token = live_token[live_index];
            saved_generation = live_generation[live_index];
            saved_image = IMAGE0;
            saved_stage = 4'd0;
            saved_branch = 2'd0;
            saved_context = live_context[live_index];
            saved_sequence = live_sequence[live_index];
            saved_cancel = live_cancel[live_index];
            saved_domain = 9'd320;
            saved_ref_token = live_ref_token[live_index];
        end
    endtask

    task reject_open;
        input [3:0] stage;
        input [1:0] branch;
        input [8:0] domain;
        input [7:0] expected_status;
        input [15:0] caller_tag;
        reg [4:0] free_before;
        begin
            free_before = free_slot_count;
            @(negedge clk);
            mgmt_req_opcode = OP_OPEN;
            mgmt_req_image_epoch = IMAGE0;
            mgmt_req_stage_id = stage;
            mgmt_req_logical_branch = branch;
            mgmt_req_context_generation = CONTEXT0 + caller_tag;
            mgmt_req_producer_sequence_ticket = SEQ0 + caller_tag;
            mgmt_req_cancellation_epoch = CANCEL0 + caller_tag;
            mgmt_req_stop_epoch = 32'd0;
            mgmt_req_domain_bound = domain;
            mgmt_req_pe_recovery_safe = 1'b1;
            mgmt_req_tag = caller_tag;
            mgmt_req_valid = 1'b1;
            wait_mgmt_ready_and_fire;
            check(mgmt_rsp_valid && mgmt_rsp_status == expected_status &&
                  !mgmt_rsp_committed,
                  "malformed/projection OPEN returns exact caller error");
            check(free_slot_count == free_before && !current_producer_valid &&
                  !completion_slot_reserved,
                  "rejected OPEN consumes no slot, token-visible authority, or event");
            retire_mgmt_response;
        end
    endtask

    task acquire_reference;
        input [2:0] owner_kind;
        input [31:0] owner_token;
        input [1:0] owner_phase;
        input [7:0] expected_status;
        input [15:0] caller_tag;
        output [31:0] returned_ref_token;
        begin
            returned_ref_token = 32'd0;
            @(negedge clk);
            drive_saved_identity;
            mgmt_req_opcode = OP_REF_ACQUIRE;
            mgmt_req_stop_epoch = 32'd0;
            mgmt_req_ref_owner_kind = owner_kind;
            mgmt_req_ref_owner_token = owner_token;
            mgmt_req_ref_token = 32'd0;
            mgmt_req_ref_phase = owner_phase;
            mgmt_req_tag = caller_tag;
            mgmt_req_valid = 1'b1;
            wait_mgmt_ready_and_fire;
            check(mgmt_rsp_valid && mgmt_rsp_status == expected_status,
                  "generic reference acquire returns expected status");
            if (expected_status == STATUS_OK) begin
                check(mgmt_rsp_committed && mgmt_rsp_ref_token != 32'd0,
                      "successful generic acquire returns nonzero reference token");
                returned_ref_token = mgmt_rsp_ref_token;
            end else begin
                check(!mgmt_rsp_committed,
                      "failed generic acquire has no committed side effect");
            end
            retire_mgmt_response;
        end
    endtask

    task transfer_reference;
        input [31:0] reference_token;
        input [2:0] old_kind;
        input [31:0] old_owner;
        input [1:0] old_phase;
        input [2:0] new_kind;
        input [31:0] new_owner;
        input [1:0] new_phase;
        begin
            @(negedge clk);
            drive_saved_identity;
            mgmt_req_opcode = OP_REF_TRANSFER;
            mgmt_req_stop_epoch = 32'd0;
            mgmt_req_ref_token = reference_token;
            mgmt_req_ref_owner_kind = old_kind;
            mgmt_req_ref_owner_token = old_owner;
            mgmt_req_ref_phase = old_phase;
            mgmt_req_new_ref_owner_kind = new_kind;
            mgmt_req_new_ref_owner_token = new_owner;
            mgmt_req_new_ref_phase = new_phase;
            mgmt_req_tag = 16'h0d11;
            mgmt_req_valid = 1'b1;
            wait_mgmt_ready_and_fire;
            check(mgmt_rsp_valid && mgmt_rsp_status == STATUS_OK &&
                  mgmt_rsp_committed &&
                  mgmt_rsp_ref_token == reference_token &&
                  mgmt_rsp_ref_owner_kind == new_kind &&
                  mgmt_rsp_ref_owner_token == new_owner &&
                  mgmt_rsp_ref_phase == new_phase,
                  "reference transfer atomically changes owner/phase without token gap");
            retire_mgmt_response;
        end
    endtask

    task release_reference_generic;
        input [31:0] reference_token;
        input [2:0] owner_kind;
        input [31:0] owner_token;
        input [1:0] owner_phase;
        input [31:0] cleanup_stop_epoch;
        input [7:0] expected_status;
        input expected_released;
        begin
            @(negedge clk);
            drive_saved_identity;
            mgmt_req_opcode = OP_REF_RELEASE;
            mgmt_req_stop_epoch = cleanup_stop_epoch;
            mgmt_req_ref_token = reference_token;
            mgmt_req_ref_owner_kind = owner_kind;
            mgmt_req_ref_owner_token = owner_token;
            mgmt_req_ref_phase = owner_phase;
            mgmt_req_tag = 16'h0d12;
            mgmt_req_valid = 1'b1;
            wait_mgmt_ready_and_fire;
            check(mgmt_rsp_valid && mgmt_rsp_status == expected_status &&
                  mgmt_rsp_released == expected_released,
                  "generic exact/stale reference release reports expected result");
            check(mgmt_rsp_committed == expected_released,
                  "reference committed bit agrees with exactly-once release side effect");
            retire_mgmt_response;
        end
    endtask

    task finish_zero_list;
        input [15:0] terminal_tag_value;
        begin
            start_list;
            send_direct_command(1'b0, saved_domain - 1'b1,
                                terminal_tag_value, 1'b1);
            wait_for_completion(STATUS_OK, 1'b1, 9'd0,
                                terminal_tag_value);
            retire_completion;
        end
    endtask

    task finish_dense_list;
        input [15:0] tag_base;
        integer dense_index;
        integer dense_accepts;
        begin
            start_list;
            @(negedge clk);
            use_frozen_path = 1'b0;
            direct_active_cmd_valid = 1'b1;
            dense_accepts = 0;
            for (dense_index = 0; dense_index < 320;
                 dense_index = dense_index + 1) begin
                direct_active_cmd_write = 1'b1;
                direct_active_cmd_index = dense_index[8:0];
                direct_active_cmd_tag = tag_base + dense_index[15:0];
                direct_active_cmd_finalize = (dense_index == 319);
                check(active_cmd_ready,
                      "dense payload producer retains one-command-per-cycle ready");
                @(posedge clk);
                if (active_cmd_ready)
                    dense_accepts = dense_accepts + 1;
                #1;
                if (dense_index != 319)
                    @(negedge clk);
            end
            @(negedge clk);
            direct_active_cmd_valid = 1'b0;
            direct_active_cmd_write = 1'b0;
            direct_active_cmd_finalize = 1'b0;
            check(dense_accepts == 320,
                  "dense helper accepts all 320 commands without bubble");
            wait_for_completion(STATUS_OK, 1'b1, 9'd320,
                                tag_base + 16'd319);
            retire_completion;
        end
    endtask

    task run_poison_case;
        input [8*48-1:0] case_name;
        input prior_write_valid;
        input [8:0] prior_index;
        input bad_write;
        input [8:0] bad_index;
        input bad_finalize;
        input [7:0] expected_error;
        integer expected_count;
        begin
            reset_dut;
            $display("TEST poison %0s", case_name);
            open_list(4'd0, 2'd0, 9'd320,
                      CONTEXT0 + 32'h100, SEQ0 + 32'h100,
                      CANCEL0 + 32'h100);
            start_list;
            if (prior_write_valid)
                send_direct_command(1'b1, prior_index, 16'h8801, 1'b0);
            fault_event_ready = 1'b0;
            send_direct_command(bad_write, bad_index, 16'h88ee,
                                bad_finalize);
            expected_count = prior_write_valid ? 1 : 0;
            check(local_error_valid && local_error_code == expected_error &&
                  state_of(saved_slot) == ST_POISON_DRAIN,
                  "poison case captures expected first error and state");
            check(active_cmd_ready && producer_obligation && fault_event_valid,
                  "poison case preserves fail-drain authority and held fault event");
            send_direct_command(1'b0, 9'd319, 16'h88ff, 1'b1);
            wait_for_completion(expected_error, 1'b0,
                                expected_count[8:0], 16'h88ff);
            @(negedge clk);
            fault_event_ready = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            fault_event_ready = 1'b0;
            retire_completion;
            check(state_of(saved_slot) == ST_ERROR,
                  "poison case never publishes partial list authority");
        end
    endtask

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!rst_n)
            cycles <= 0;
        else
            cycles <= cycles + 1;
    end

    initial begin : watchdog
        #1000000;
        $display("FAIL: global testbench timeout");
        $finish;
    end

    initial begin : directed_tests
        integer timeout;
        integer accepted;
        integer responses;
        integer build_index;
        integer churn_round;
        integer selected_live;
        reg [15:0] held_tag;
        reg [8:0] held_index;
        reg [31:0] held_token;
        reg [31:0] ref_a;
        reg [31:0] ref_b;
        reg [31:0] ref_c;
        reg [4:0] replacement_slot;
        reg [31:0] replacement_token;
        reg [15:0] replacement_generation;
        reg [31:0] replacement_context;
        reg [31:0] replacement_sequence;
        reg [31:0] replacement_cancel;
        reg [31:0] replacement_ref_token;
        reg [31:0] replacement_ref_owner;

        clk = 1'b0;
        rst_n = 1'b0;
        checks = 0;
        failures = 0;
        cycles = 0;
        dense_fires = 0;
        writer_fires = 0;
        saved_slot = 5'd0;
        saved_token = 32'd0;
        saved_generation = 16'd0;
        saved_ref_token = 32'd0;
        saved_image = 32'd0;
        saved_stage = 4'd0;
        saved_branch = 2'd0;
        saved_context = 32'd0;
        saved_sequence = 32'd0;
        saved_cancel = 32'd0;
        saved_domain = 9'd0;
        saved_terminal_tag = 16'd0;
        mgmt_rsp_ready = 1'b0;
        stop_rsp_ready = 1'b0;
        completion_ready = 1'b0;
        read_rsp_ready = 1'b0;
        fault_event_ready = 1'b0;
        start_partner_ready = 1'b0;
        clear_request_inputs;

        // -----------------------------------------------------------------
        // Basic terminal-non-spike list, held completion, ordered two-credit
        // read service, exact references, and ABA-safe release.
        // -----------------------------------------------------------------
        reset_dut;
        $display("TEST basic OPEN/START/list/read/reference/release");
        $display("TRACE_AILS_BEGIN seed=41a15e01");
        $display("TRACE_AILS_DIFF_BEGIN seed=d1ff2026");
        saved_slot = 5'd0;
        trace_basic_point(0);
        trace_diff_point(0);
        open_list(4'd0, 2'd0, 9'd320, CONTEXT0, SEQ0, CANCEL0);
        trace_basic_point(1);
        trace_diff_point(1);
        start_list;
        trace_basic_point(2);
        trace_diff_point(2);
        send_direct_command(1'b1, 9'd1, 16'h1001, 1'b0);
        send_direct_command(1'b1, 9'd7, 16'h1002, 1'b0);
        send_direct_command(1'b0, 9'd319, 16'h10ff, 1'b1);
        saved_terminal_tag = 16'h10ff;
        wait_for_completion(STATUS_OK, 1'b1, 9'd2, 16'h10ff);
        check(completion_last_valid && completion_last_committed_index == 9'd7,
              "terminal non-spike preserves last committed spike");
        check(!producer_obligation && state_of(saved_slot) == ST_SEALED,
              "healthy finalize clears obligation and freezes SEALED descriptor");
        trace_basic_point(3);
        trace_diff_point(3);
        retire_completion;
        trace_basic_point(4);
        trace_diff_point(4);

        // Accept descriptor then index in consecutive cycles while the
        // response is stalled.  Both physical order slots must be occupied.
        @(negedge clk);
        drive_saved_read_identity;
        read_req_kind = 1'b0;
        read_req_ordinal = 9'd0;
        read_req_tag = 16'h2010;
        read_req_valid = 1'b1;
        timeout = 0;
        while ((read_req_ready !== 1'b1) && (timeout < 100)) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        check(timeout < 100, "first ordered read position accepts descriptor");
        @(posedge clk);
        #1;
        @(negedge clk);
        read_req_kind = 1'b1;
        read_req_ordinal = 9'd0;
        read_req_tag = 16'h2020;
        check(read_req_ready, "second ordered read position accepts next-cycle index");
        @(posedge clk);
        #1;
        @(negedge clk);
        // Present a third request only to prove admission is fenced; it must
        // not handshake while two responses have no retirement path.
        read_req_kind = 1'b1;
        read_req_ordinal = 9'd1;
        read_req_tag = 16'h2030;
        check(!read_req_ready, "two occupied read slots backpressure a third request");
        read_req_valid = 1'b0;
        timeout = 0;
        while ((read_rsp_valid !== 1'b1) && (timeout < 100)) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        check(timeout < 100, "ordered read head materializes under output stall");
        check(read_outstanding == 2'd2 && read_reference_total == 2'd2,
              "two accepted legal reads hold two physical/read-reference credits");
        trace_basic_point(5);
        trace_diff_point(5);
        check(read_rsp_kind == 1'b0 && read_rsp_tag == 16'h2010 &&
              read_rsp_status == STATUS_OK && read_rsp_sealed,
              "descriptor response is first regardless of kind");
        held_tag = read_rsp_tag;
        held_token = read_rsp_list_token;
        repeat (3) begin
            @(posedge clk);
            #1;
            check(read_rsp_valid && read_rsp_tag == held_tag &&
                  read_rsp_list_token == held_token,
                  "held read response metadata remains stable");
        end
        trace_diff_point(6);
        retire_read_response;
        timeout = 0;
        while ((read_rsp_valid !== 1'b1) && (timeout < 20)) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        check(timeout < 20, "second ordered response follows head retirement");
        check(read_rsp_kind == 1'b1 && read_rsp_tag == 16'h2020 &&
              read_rsp_status == STATUS_OK && read_rsp_data_usable &&
              read_rsp_source_index == 9'd1 && read_rsp_ordinal == 9'd0 &&
              !read_rsp_last,
              "index response returns ordinal zero payload in order");
        trace_diff_point(7);
        retire_read_response;
        check(read_outstanding == 2'd0 && read_reference_total == 2'd0,
              "read response handshakes release both temporary references");
        trace_basic_point(6);
        trace_diff_point(8);

        drive_one_read(1'b1, 9'd2, 16'h2040);
        timeout = 0;
        while ((read_rsp_valid !== 1'b1) && (timeout < 100)) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        check(timeout < 100 && read_rsp_status == ERR_BAD_ORDINAL &&
              !read_rsp_data_usable,
              "ordinal equal to count returns ordered zero-data error");
        retire_read_response;

        acquire_context_reference(REFOWN0);
        trace_basic_point(7);
        trace_diff_point(9);
        duplicate_reference_must_fail(REFOWN0);
        trace_diff_point(10);
        release_context_reference(REFOWN0, 32'd0, STATUS_OK);
        check(state_of(saved_slot) == ST_SEALED,
              "last external-reference release restores SEALED state");
        trace_basic_point(8);
        trace_diff_point(11);
        release_list(32'd0, STATUS_OK);
        trace_basic_point(9);
        trace_diff_point(12);
        $display("TRACE_AILS_END steps=10");

        // -----------------------------------------------------------------
        // Every frozen/v4 GSU producer tuple is admitted.  Projection stages
        // and wrong branch/domain combinations receive caller-local errors
        // without consuming a slot or completion-event reservation.
        // -----------------------------------------------------------------
        $display("TEST all legal producer domains and projection rejection");
        reset_dut;
        open_list(4'd0, 2'd0, 9'd320, CONTEXT0, SEQ0, CANCEL0);
        reset_dut;
        open_list(4'd1, 2'd0, 9'd320, CONTEXT0, SEQ0, CANCEL0);
        reset_dut;
        open_list(4'd3, 2'd0, 9'd224, CONTEXT0, SEQ0, CANCEL0);
        reset_dut;
        open_list(4'd4, 2'd0, 9'd224, CONTEXT0, SEQ0, CANCEL0);
        reset_dut;
        open_list(4'd6, 2'd1, 9'd224, CONTEXT0, SEQ0, CANCEL0);
        reset_dut;
        open_list(4'd7, 2'd1, 9'd224, CONTEXT0, SEQ0, CANCEL0);
        reset_dut;
        open_list(4'd9, 2'd2, 9'd224, CONTEXT0, SEQ0, CANCEL0);
        reset_dut;
        open_list(4'd10, 2'd2, 9'd224, CONTEXT0, SEQ0, CANCEL0);
        reset_dut;
        reject_open(4'd2, 2'd0, 9'd64,
                    ERR_PROJECTION_PRODUCER, 16'h8012);
        reject_open(4'd5, 2'd0, 9'd80,
                    ERR_PROJECTION_PRODUCER, 16'h8015);
        reject_open(4'd8, 2'd1, 9'd192,
                    ERR_PROJECTION_PRODUCER, 16'h8018);
        reject_open(4'd11, 2'd2, 9'd128,
                    ERR_PROJECTION_PRODUCER, 16'h801b);
        reject_open(4'd6, 2'd0, 9'd224,
                    ERR_BAD_STAGE_DOMAIN, 16'h8026);
        reject_open(4'd0, 2'd0, 9'd200,
                    ERR_BAD_DOMAIN_BOUND, 16'h8020);

        // -----------------------------------------------------------------
        // Zero-source list: terminal non-spike is the first writer event.
        // -----------------------------------------------------------------
        reset_dut;
        $display("TEST zero-source terminal non-spike");
        open_list(4'd3, 2'd0, 9'd224,
                  CONTEXT0 + 32'd1, SEQ0 + 32'd1, CANCEL0 + 32'd1);
        start_list;
        send_direct_command(1'b0, 9'd223, 16'h30ff, 1'b1);
        wait_for_completion(STATUS_OK, 1'b1, 9'd0, 16'h30ff);
        check(!completion_last_valid && completion_last_committed_index == 9'd0,
              "zero-source descriptor has no last committed index");
        retire_completion;

        $display("TEST exact two-reference limit and no-gap recurrent handoff");
        acquire_reference(REF_CONTEXT, 32'h9000_0001, REF_PERSISTENT,
                          STATUS_OK, 16'h9011, ref_a);
        acquire_reference(REF_TEMP_ADD, 32'h9000_0002, REF_TEMPORARY,
                          STATUS_OK, 16'h9012, ref_b);
        check(external_reference_total == 6'd2 &&
              state_of(saved_slot) == ST_REFERENCED,
              "one list holds exactly two independent persistent/preparation authorities");
        acquire_reference(REF_CONTEXT, 32'h9000_0001, REF_PERSISTENT,
                          ERR_REF_DUPLICATE, 16'h9013, ref_c);
        acquire_reference(REF_TEMP_PROJ, 32'h9000_0003, REF_TEMPORARY,
                          ERR_REF_CAPACITY, 16'h9014, ref_c);
        check(external_reference_total == 6'd2,
              "duplicate and third reference attempts cannot silently saturate");
        release_reference_generic(ref_b ^ 32'h0000_0100,
                                  REF_TEMP_ADD, 32'h9000_0002,
                                  REF_TEMPORARY, 32'd0,
                                  ERR_REF_NOT_FOUND, 1'b0);
        check(external_reference_total == 6'd2,
              "stale reference release cannot drop a live record");
        transfer_reference(ref_b, REF_TEMP_ADD, 32'h9000_0002,
                           REF_TEMPORARY, REF_RECURRENT,
                           32'h9000_0012, REF_PENDING);
        check(external_reference_total == 6'd2,
              "temporary-to-pending handoff has no reference-count gap");
        transfer_reference(ref_b, REF_RECURRENT, 32'h9000_0012,
                           REF_PENDING, REF_RECURRENT,
                           32'h9000_0012, REF_PERSISTENT);
        check(external_reference_total == 6'd2,
              "pending-to-persistent handoff retains the same two authorities");
        release_reference_generic(ref_a, REF_CONTEXT, 32'h9000_0001,
                                  REF_PERSISTENT, 32'd0,
                                  STATUS_OK, 1'b1);
        check(external_reference_total == 6'd1 &&
              state_of(saved_slot) == ST_REFERENCED,
              "new recurrent authority exists before old context authority leaves");
        release_reference_generic(ref_b, REF_RECURRENT, 32'h9000_0012,
                                  REF_PERSISTENT, 32'd0,
                                  STATUS_OK, 1'b1);
        check(external_reference_total == 6'd0 &&
              state_of(saved_slot) == ST_SEALED,
              "last exact reference release returns immutable list to SEALED");
        release_list(32'd0, STATUS_OK);

        // -----------------------------------------------------------------
        // Dense all-spike stream: 320 consecutive accepted commands prove
        // active_cmd II=1 and terminal-spike write/finalize atomicity.
        // -----------------------------------------------------------------
        reset_dut;
        $display("TEST 320-cycle active_cmd II=1 and terminal spike");
        open_list(4'd1, 2'd0, 9'd320,
                  CONTEXT0 + 32'd2, SEQ0 + 32'd2, CANCEL0 + 32'd2);
        start_list;
        @(negedge clk);
        use_frozen_path = 1'b0;
        direct_active_cmd_valid = 1'b1;
        accepted = 0;
        for (i = 0; i < 320; i = i + 1) begin
            direct_active_cmd_write = 1'b1;
            direct_active_cmd_index = i[8:0];
            direct_active_cmd_tag = 16'h4000 + i[15:0];
            direct_active_cmd_finalize = (i == 319);
            check(active_cmd_ready,
                  "healthy reserved producer sustains active_cmd ready every cycle");
            @(posedge clk);
            if (active_cmd_ready)
                accepted = accepted + 1;
            #1;
            if (i != 319)
                @(negedge clk);
        end
        @(negedge clk);
        direct_active_cmd_valid = 1'b0;
        direct_active_cmd_write = 1'b0;
        direct_active_cmd_finalize = 1'b0;
        check(accepted == 320, "all-spike window accepts exactly 320 of 320 cycles");
        wait_for_completion(STATUS_OK, 1'b1, 9'd320, 16'h413f);
        check(completion_last_valid && completion_last_committed_index == 9'd319,
              "terminal spike commits payload[319] before sealing");
        retire_completion;

        // A stale LIST_RELEASE must not mutate the list.  A later exact
        // release enters CLOSING immediately but cannot materialize its
        // terminal response until the accepted/held index read retires.
        $display("TEST held read response blocks CLOSING completion and stale release");
        @(negedge clk);
        drive_saved_identity;
        mgmt_req_opcode = OP_LIST_RELEASE;
        mgmt_req_list_token = saved_token ^ 32'h0000_1000;
        mgmt_req_external_safe = 1'b1;
        mgmt_req_tag = 16'ha001;
        mgmt_req_valid = 1'b1;
        wait_mgmt_ready_and_fire;
        check(mgmt_rsp_valid && mgmt_rsp_status == ERR_STALE_TOKEN &&
              !mgmt_rsp_committed && state_of(saved_slot) == ST_SEALED,
              "stale list release is caller-local and leaves healthy slot SEALED");
        retire_mgmt_response;

        drive_one_read(1'b1, 9'd319, 16'ha002);
        timeout = 0;
        while ((read_rsp_valid !== 1'b1) && (timeout < 100)) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        check(timeout < 100 && read_rsp_source_index == 9'd319 &&
              read_rsp_last && read_reference_total == 2'd1,
              "held final-ordinal response retains one temporary read reference");

        @(negedge clk);
        drive_saved_identity;
        mgmt_req_opcode = OP_LIST_RELEASE;
        mgmt_req_external_safe = 1'b1;
        mgmt_req_tag = 16'ha003;
        mgmt_req_valid = 1'b1;
        wait_mgmt_ready_and_fire;
        check(state_of(saved_slot) == ST_CLOSING && closing_busy &&
              !mgmt_rsp_valid,
              "exact release enters CLOSING but waits for held read response");
        repeat (3) begin
            @(posedge clk);
            #1;
            check(state_of(saved_slot) == ST_CLOSING && !mgmt_rsp_valid &&
                  read_reference_total == 2'd1,
                  "CLOSING retains descriptor while accepted read is held");
        end
        retire_read_response;
        timeout = 0;
        while ((mgmt_rsp_valid !== 1'b1) && (timeout < 100)) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        check(timeout < 100 && mgmt_rsp_status == STATUS_OK &&
              mgmt_rsp_committed && mgmt_rsp_released,
              "last read retirement materializes exact release response");
        check(state_of(saved_slot) == ST_CLOSING &&
              slot_authority_valid[saved_slot],
              "held CLOSING response still fences ABA reuse");
        retire_mgmt_response;
        @(posedge clk);
        #1;
        check(state_of(saved_slot) == ST_FREE &&
              !slot_authority_valid[saved_slot],
              "CLOSING response handshake finally recycles the slot");

        // -----------------------------------------------------------------
        // Full accepted schedule census: 20 persistent recurrent lists plus
        // one replacement producer.  Slots 1 and 11 carry dense identity
        // payloads so the aggregate 1000-request stream alternates physical
        // RAMs while retaining strict order and a deliberately repeated tag.
        // -----------------------------------------------------------------
        reset_dut;
        $display("TEST 20 persistent lists, 1000 read II=1, 21st producer, and churn");
        for (build_index = 0; build_index < 20;
             build_index = build_index + 1) begin
            open_list(4'd0, 2'd0, 9'd320,
                      CONTEXT0 + 32'h1000 + build_index,
                      SEQ0 + 32'h1000 + build_index,
                      CANCEL0 + 32'h1000 + build_index);
            if (build_index == 0 || build_index == 11)
                finish_dense_list(16'hb000 + build_index[15:0]);
            else
                finish_zero_list(16'hb000 + build_index[15:0]);
            live_ref_owner[build_index] = 32'hb100_0000 + build_index;
            acquire_reference(REF_CONTEXT, live_ref_owner[build_index],
                              REF_PERSISTENT, STATUS_OK,
                              16'hb100 + build_index[15:0], ref_a);
            saved_ref_token = ref_a;
            save_live_handle(build_index);
        end
        check(free_slot_count == 5'd1 &&
              external_reference_total == 6'd20,
              "steady state has exactly 20 persistent lists and one FREE slot");
        $display("SLOT_FIXTURES first=%0d second=%0d",
                 live_slot[0], live_slot[11]);
        check(live_slot[0] < 5'd11 && live_slot[11] >= 5'd11,
              "dense read fixtures reside in opposite physical payload RAMs");

        accepted = 0;
        responses = 0;
        read_rsp_ready = 1'b1;
        @(negedge clk);
        read_req_valid = 1'b1;
        for (i = 0; i < 1000; i = i + 1) begin
            selected_live = (i & 1) ? 11 : 0;
            load_live_handle(selected_live);
            drive_saved_read_identity;
            read_req_kind = 1'b1;
            read_req_ordinal = (i >> 1) % 320;
            read_req_tag = 16'ha5a5;
            #1;
            check(read_req_ready,
                  "aggregate index service accepts every cycle with consumer ready");
            @(posedge clk);
            if (read_req_ready)
                accepted = accepted + 1;
            if (read_rsp_valid && read_rsp_ready) begin
                selected_live = (responses & 1) ? 11 : 0;
                check(read_rsp_status == STATUS_OK &&
                      read_rsp_data_usable && read_rsp_kind &&
                      read_rsp_slot_locator == live_slot[selected_live] &&
                      read_rsp_list_token == live_token[selected_live] &&
                      read_rsp_list_generation == live_generation[selected_live],
                      "1000-read stream preserves cross-RAM acceptance order and identity");
                check(read_rsp_ordinal == ((responses >> 1) % 320) &&
                      read_rsp_source_index == ((responses >> 1) % 320) &&
                      read_rsp_tag == 16'ha5a5,
                      "1000-read stream preserves ordinal/data with repeated opaque tag");
                responses = responses + 1;
            end
            #1;
            if (i != 999)
                @(negedge clk);
        end
        @(negedge clk);
        read_req_valid = 1'b0;
        timeout = 0;
        while ((responses < 1000) && (timeout < 100)) begin
            @(posedge clk);
            if (read_rsp_valid && read_rsp_ready) begin
                selected_live = (responses & 1) ? 11 : 0;
                check(read_rsp_status == STATUS_OK &&
                      read_rsp_data_usable &&
                      read_rsp_slot_locator == live_slot[selected_live] &&
                      read_rsp_ordinal == ((responses >> 1) % 320) &&
                      read_rsp_source_index == ((responses >> 1) % 320) &&
                      read_rsp_tag == 16'ha5a5,
                      "tail responses remain globally ordered across both RAMs");
                responses = responses + 1;
            end
            timeout = timeout + 1;
        end
        @(negedge clk);
        read_rsp_ready = 1'b0;
        check(accepted == 1000 && responses == 1000,
              "aggregate no-stall window accepts and retires 1000 ordered reads");
        check(read_outstanding == 2'd0 && read_reference_total == 2'd0,
              "1000-read window leaves no temporary read/reference credit");

        open_list(4'd0, 2'd0, 9'd320,
                  CONTEXT0 + 32'h2000, SEQ0 + 32'h2000,
                  CANCEL0 + 32'h2000);
        check(free_slot_count == 5'd0 && current_producer_valid,
              "20 persistent plus one OPEN producer consumes exactly 21 slots");
        @(negedge clk);
        mgmt_req_opcode = OP_OPEN;
        mgmt_req_image_epoch = IMAGE0;
        mgmt_req_stage_id = 4'd0;
        mgmt_req_logical_branch = 2'd0;
        mgmt_req_context_generation = CONTEXT0 + 32'h3000;
        mgmt_req_producer_sequence_ticket = SEQ0 + 32'h3000;
        mgmt_req_cancellation_epoch = CANCEL0 + 32'h3000;
        mgmt_req_stop_epoch = 32'd0;
        mgmt_req_domain_bound = 9'd320;
        mgmt_req_pe_recovery_safe = 1'b1;
        mgmt_req_tag = 16'hbeef;
        mgmt_req_valid = 1'b1;
        #1;
        repeat (5) begin
            check(!mgmt_req_ready && !mgmt_rsp_valid,
                  "22nd legal OPEN safely backpressures without allocating/error response");
            @(posedge clk);
            #1;
        end
        @(negedge clk);
        mgmt_req_valid = 1'b0;

        for (churn_round = 0; churn_round < 3;
             churn_round = churn_round + 1) begin
            finish_zero_list(16'hc000 + churn_round[15:0]);
            replacement_ref_owner = 32'hc100_0000 + churn_round;
            acquire_reference(REF_CONTEXT, replacement_ref_owner,
                              REF_PERSISTENT, STATUS_OK,
                              16'hc100 + churn_round[15:0], ref_a);
            saved_ref_token = ref_a;
            replacement_slot = saved_slot;
            replacement_token = saved_token;
            replacement_generation = saved_generation;
            replacement_context = saved_context;
            replacement_sequence = saved_sequence;
            replacement_cancel = saved_cancel;
            replacement_ref_token = saved_ref_token;

            load_live_handle(churn_round);
            release_reference_generic(live_ref_token[churn_round],
                                      REF_CONTEXT,
                                      live_ref_owner[churn_round],
                                      REF_PERSISTENT, 32'd0,
                                      STATUS_OK, 1'b1);
            release_list(32'd0, STATUS_OK);

            live_slot[churn_round] = replacement_slot;
            live_token[churn_round] = replacement_token;
            live_generation[churn_round] = replacement_generation;
            live_context[churn_round] = replacement_context;
            live_sequence[churn_round] = replacement_sequence;
            live_cancel[churn_round] = replacement_cancel;
            live_ref_token[churn_round] = replacement_ref_token;
            live_ref_owner[churn_round] = replacement_ref_owner;

            check(free_slot_count == 5'd1 &&
                  external_reference_total == 6'd20,
                  "replacement retires old list without changing persistent census");
            if (churn_round != 2)
                open_list(4'd0, 2'd0, 9'd320,
                          CONTEXT0 + 32'h2001 + churn_round,
                          SEQ0 + 32'h2001 + churn_round,
                          CANCEL0 + 32'h2001 + churn_round);
        end
        check(free_slot_count == 5'd1 &&
              external_reference_total == 6'd20 &&
              !current_producer_valid,
              "three replacement rounds finish with 20 persistent lists and no leak");

        // Independent poison variants use coordinated reset as their test
        // teardown boundary.  Each must keep ready high until the exact real
        // terminal index arrives and must publish no partial list.
        run_poison_case("malformed nonwrite/nonfinalize", 1'b0, 9'd0,
                        1'b0, 9'd3, 1'b0,
                        ERR_BAD_COMMAND_ENCODING);
        run_poison_case("descending index", 1'b1, 9'd10,
                        1'b1, 9'd9, 1'b0,
                        ERR_UNORDERED_INDEX);
        run_poison_case("index outside domain", 1'b0, 9'd0,
                        1'b1, 9'd320, 1'b0,
                        ERR_INDEX_OUT_OF_RANGE);
        run_poison_case("early nonspike finalize", 1'b0, 9'd0,
                        1'b0, 9'd318, 1'b1,
                        ERR_EARLY_FINALIZE);
        run_poison_case("terminal index without finalize", 1'b0, 9'd0,
                        1'b1, 9'd319, 1'b0,
                        ERR_EARLY_FINALIZE);
        run_poison_case("out-of-range finalize precedence", 1'b0, 9'd0,
                        1'b0, 9'd320, 1'b1,
                        ERR_INDEX_OUT_OF_RANGE);

        // -----------------------------------------------------------------
        // Poison fail-drain: a duplicate is not written, ready stays high,
        // one fault/event identity is retained, and only real terminal index
        // ends the obligation.  Cleanup uses the owner fatal overlay.
        // -----------------------------------------------------------------
        reset_dut;
        $display("TEST duplicate poison fail-drain and exact cleanup");
        open_list(4'd0, 2'd0, 9'd320,
                  CONTEXT0 + 32'd3, SEQ0 + 32'd3, CANCEL0 + 32'd3);
        start_list;
        send_direct_command(1'b1, 9'd4, 16'h5001, 1'b0);
        fault_event_ready = 1'b0;
        send_direct_command(1'b1, 9'd4, 16'h5002, 1'b0);
        check(local_error_valid && local_error_code == ERR_UNORDERED_INDEX &&
              state_of(saved_slot) == ST_POISON_DRAIN,
              "duplicate index captures first error and enters POISON_DRAIN");
        check(active_cmd_ready && producer_obligation,
              "poison keeps sink ready and preserves real-finalize obligation");
        check(fault_event_valid && fault_event_code == ERR_UNORDERED_INDEX &&
              fault_event_slot_locator == saved_slot,
              "poison emits one held authoritative fault event");
        held_token = fault_event_list_token;
        repeat (2) begin
            @(posedge clk);
            #1;
            check(fault_event_valid && fault_event_list_token == held_token,
                  "fault-event stall cannot overwrite first-error identity");
        end
        issue_stop(32'h7000_0001, 1'b1, 1'b0, ERR_UNORDERED_INDEX);
        @(negedge clk);
        direct_active_cmd_valid = 1'b1;
        direct_active_cmd_write = 1'b1;
        direct_active_cmd_finalize = 1'b0;
        accepted = 0;
        for (i = 0; i < 64; i = i + 1) begin
            direct_active_cmd_index = (9'd99 + i[8:0]);
            direct_active_cmd_tag = 16'h5100 + i[15:0];
            check(active_cmd_ready,
                  "cancelled poisoned producer drains every consecutive cycle");
            @(posedge clk);
            if (active_cmd_ready)
                accepted = accepted + 1;
            #1;
            if (i != 63)
                @(negedge clk);
        end
        @(negedge clk);
        direct_active_cmd_valid = 1'b0;
        direct_active_cmd_write = 1'b0;
        check(accepted == 64,
              "POISON/CANCEL fail-drain accepts 64 of 64 consecutive commands");
        send_direct_command(1'b0, 9'd319, 16'h50ff, 1'b1);
        wait_for_completion(ERR_UNORDERED_INDEX, 1'b0, 9'd1, 16'h50ff);
        check(completion_last_valid && completion_last_committed_index == 9'd4,
              "poison diagnostic count excludes bad and discarded commands");
        @(negedge clk);
        fault_event_ready = 1'b1;
        @(posedge clk);
        #1;
        @(negedge clk);
        fault_event_ready = 1'b0;
        retire_completion;
        check(state_of(saved_slot) == ST_ERROR,
              "poison completion retirement leaves non-computable ERROR slot");
        wait_stop_response(ERR_UNORDERED_INDEX, 32'h7000_0001);
        release_list(32'h7000_0001, ERR_UNORDERED_INDEX);
        clear_local_error_scope(32'h7000_0001);

        // -----------------------------------------------------------------
        // Explicit abort before START creates synthetic completion and no
        // impossible real-finalize debt.
        // -----------------------------------------------------------------
        reset_dut;
        $display("TEST unstarted OPEN explicit abort synthetic completion");
        open_list(4'd0, 2'd0, 9'd320,
                  CONTEXT0 + 32'd4, SEQ0 + 32'd4, CANCEL0 + 32'd4);
        trace_diff_point(13);
        issue_stop(32'h7000_0002, 1'b0, 1'b0, ERR_ABORTED);
        check(!producer_obligation && state_of(saved_slot) == ST_CANCEL_PENDING,
              "unstarted abort does not invent PE finalize obligation");
        trace_diff_point(14);
        wait_for_completion(ERR_ABORTED, 1'b0, 9'd0, 16'd0);
        trace_diff_point(15);
        retire_completion;
        check(state_of(saved_slot) == ST_ERROR,
              "synthetic abort completion retires to ERROR");
        trace_diff_point(16);
        wait_stop_response(ERR_ABORTED, 32'h7000_0002);
        trace_diff_point(17);
        release_list(32'h7000_0002, ERR_ABORTED);
        trace_diff_point(18);

        // -----------------------------------------------------------------
        // Explicit abort after START retains causal sink authority through a
        // matching real finalize and never rewrites START success.
        // -----------------------------------------------------------------
        reset_dut;
        $display("TEST started producer explicit abort real-finalize drain");
        open_list(4'd0, 2'd0, 9'd320,
                  CONTEXT0 + 32'd5, SEQ0 + 32'd5, CANCEL0 + 32'd5);
        start_list;
        trace_diff_point(19);
        send_direct_command(1'b1, 9'd2, 16'h6001, 1'b0);
        issue_stop(32'h7000_0003, 1'b0, 1'b0, ERR_ABORTED);
        check(producer_obligation && active_cmd_ready,
              "started abort keeps causal finalize sink live");
        trace_diff_point(20);
        send_direct_command(1'b1, 9'd17, 16'h6002, 1'b0);
        trace_diff_point(21);
        send_direct_command(1'b0, 9'd319, 16'h60ff, 1'b1);
        wait_for_completion(ERR_ABORTED, 1'b0, 9'd1, 16'h60ff);
        check(completion_last_valid && completion_last_committed_index == 9'd2,
              "post-abort active writes are drained but not committed");
        trace_diff_point(22);
        retire_completion;
        trace_diff_point(23);
        wait_stop_response(ERR_ABORTED, 32'h7000_0003);
        trace_diff_point(24);
        release_list(32'h7000_0003, ERR_ABORTED);
        trace_diff_point(25);

        // -----------------------------------------------------------------
        // REF_TRANSFER is strictly pre-stop and PENDING->PERSISTENT cannot
        // substitute a different owner token under the same reference.
        // -----------------------------------------------------------------
        reset_dut;
        $display("TEST REF_TRANSFER stop-epoch and owner-token fences");
        open_list(4'd0, 2'd0, 9'd320,
                  CONTEXT0 + 32'h4000, SEQ0 + 32'h4000,
                  CANCEL0 + 32'h4000);
        finish_zero_list(16'hd001);
        acquire_reference(REF_TEMP_ADD, 32'hd100_0001, REF_TEMPORARY,
                          STATUS_OK, 16'hd101, ref_a);
        trace_diff_point(26);
        @(negedge clk);
        drive_saved_identity;
        mgmt_req_opcode = OP_REF_TRANSFER;
        mgmt_req_stop_epoch = 32'h0000_0001;
        mgmt_req_ref_token = ref_a;
        mgmt_req_ref_owner_kind = REF_TEMP_ADD;
        mgmt_req_ref_owner_token = 32'hd100_0001;
        mgmt_req_ref_phase = REF_TEMPORARY;
        mgmt_req_new_ref_owner_kind = REF_RECURRENT;
        mgmt_req_new_ref_owner_token = 32'hd100_0002;
        mgmt_req_new_ref_phase = REF_PENDING;
        mgmt_req_tag = 16'hd102;
        mgmt_req_valid = 1'b1;
        wait_mgmt_ready_and_fire;
        check(mgmt_rsp_valid && mgmt_rsp_status == ERR_BAD_DRAIN_TARGET &&
              !mgmt_rsp_committed && external_reference_total == 6'd1,
              "nonzero pre-stop epoch rejects REF_TRANSFER without mutation");
        trace_diff_point(27);
        retire_mgmt_response;
        transfer_reference(ref_a, REF_TEMP_ADD, 32'hd100_0001,
                           REF_TEMPORARY, REF_RECURRENT,
                           32'hd100_0002, REF_PENDING);
        trace_diff_point(28);
        @(negedge clk);
        drive_saved_identity;
        mgmt_req_opcode = OP_REF_TRANSFER;
        mgmt_req_stop_epoch = 32'd0;
        mgmt_req_ref_token = ref_a;
        mgmt_req_ref_owner_kind = REF_RECURRENT;
        mgmt_req_ref_owner_token = 32'hd100_0002;
        mgmt_req_ref_phase = REF_PENDING;
        mgmt_req_new_ref_owner_kind = REF_RECURRENT;
        mgmt_req_new_ref_owner_token = 32'hd100_0003;
        mgmt_req_new_ref_phase = REF_PERSISTENT;
        mgmt_req_tag = 16'hd103;
        mgmt_req_valid = 1'b1;
        wait_mgmt_ready_and_fire;
        check(mgmt_rsp_valid && mgmt_rsp_status == ERR_OWNER_MISMATCH &&
              !mgmt_rsp_committed && external_reference_total == 6'd1,
              "PENDING-to-PERSISTENT cannot swap opaque owner token");
        trace_diff_point(29);
        retire_mgmt_response;
        transfer_reference(ref_a, REF_RECURRENT, 32'hd100_0002,
                           REF_PENDING, REF_RECURRENT,
                           32'hd100_0002, REF_PERSISTENT);
        trace_diff_point(30);
        release_reference_generic(ref_a, REF_RECURRENT, 32'hd100_0002,
                                  REF_PERSISTENT, 32'd0,
                                  STATUS_OK, 1'b1);
        trace_diff_point(31);
        release_list(32'd0, STATUS_OK);
        trace_diff_point(32);

        // -----------------------------------------------------------------
        // A compliant source may hold an unexpected active command while
        // ready is low.  Only its first observation edge blocks stop; the
        // registered fault fence allows stop on the next edge and must not
        // create a second fault event for the held offender.
        // -----------------------------------------------------------------
        reset_dut;
        $display("TEST held unexpected active_cmd one-edge stop fence");
        @(negedge clk);
        direct_active_cmd_valid = 1'b1;
        direct_active_cmd_write = 1'b0;
        direct_active_cmd_index = 9'd13;
        direct_active_cmd_tag = 16'he010;
        direct_active_cmd_finalize = 1'b0;
        stop_req_valid = 1'b1;
        stop_req_is_fatal = 1'b0;
        stop_req_data_untrusted = 1'b0;
        stop_req_causal_producers_stopped = 1'b1;
        stop_req_image_epoch = IMAGE0;
        stop_req_cancellation_epoch = 32'he000_0001;
        stop_req_code = ERR_ABORTED;
        stop_req_tag = 16'he011;
        #1;
        check(!active_cmd_ready && !stop_req_ready,
              "first unexpected-command observation suppresses same-edge stop");
        @(posedge clk);
        #1;
        check(local_fault_pending && local_error_valid &&
              local_error_code == 8'h0a && fault_event_valid &&
              reset_required && !stop_pending,
              "first observation captures one reset-required PE protocol fault");
        held_token = fault_event_detail;
        check(stop_req_ready,
              "held unexpected valid no longer deadlocks owner stop after first edge");
        @(posedge clk);
        #1;
        check(stop_pending && last_stop_epoch == 32'he000_0001,
              "second edge accepts held owner stop under registered fault fence");
        @(negedge clk);
        stop_req_valid = 1'b0;
        @(negedge clk);
        fault_event_ready = 1'b1;
        @(posedge clk);
        #1;
        @(negedge clk);
        fault_event_ready = 1'b0;
        repeat (3) begin
            @(posedge clk);
            #1;
            check(!fault_event_valid && local_error_detail == held_token,
                  "held unexpected command cannot regenerate/overwrite fault event");
        end
        @(negedge clk);
        direct_active_cmd_valid = 1'b0;

        // -----------------------------------------------------------------
        // A stream error and owner data-untrusted fatal may be accepted on
        // the same edge.  Sticky local diagnosis stays the stream code while
        // the fault/completion/stop terminal status uses owner first-fatal.
        // -----------------------------------------------------------------
        reset_dut;
        $display("TEST same-edge stream error plus owner fatal priority");
        open_list(4'd0, 2'd0, 9'd320,
                  CONTEXT0 + 32'h4100, SEQ0 + 32'h4100,
                  CANCEL0 + 32'h4100);
        start_list;
        @(negedge clk);
        direct_active_cmd_valid = 1'b1;
        direct_active_cmd_write = 1'b0;
        direct_active_cmd_index = 9'd8;
        direct_active_cmd_tag = 16'he101;
        direct_active_cmd_finalize = 1'b0;
        stop_req_valid = 1'b1;
        stop_req_is_fatal = 1'b1;
        stop_req_data_untrusted = 1'b1;
        stop_req_causal_producers_stopped = 1'b0;
        stop_req_image_epoch = saved_image;
        stop_req_cancellation_epoch = 32'he100_0001;
        stop_req_code = TEST_FATAL_STREAM;
        stop_req_tag = 16'he102;
        #1;
        check(active_cmd_ready && stop_req_ready,
              "causal active command and owner fatal can both fire same edge");
        @(posedge clk);
        #1;
        check(stop_pending && reset_required &&
              local_error_valid && local_error_code == ERR_BAD_COMMAND_ENCODING &&
              local_error_stop_epoch == 32'he100_0001,
              "same-edge fatal preserves sticky local stream code and stop epoch");
        check(fault_event_valid && fault_event_code == TEST_FATAL_STREAM &&
              fault_event_stop_epoch == 32'he100_0001 &&
              fault_event_reset_required,
              "fault terminal event reports owner fatal and coordinated-reset flag");
        trace_diff_point(33);
        @(negedge clk);
        direct_active_cmd_valid = 1'b0;
        stop_req_valid = 1'b0;
        send_direct_command(1'b0, 9'd319, 16'he1ff, 1'b1);
        wait_for_completion(TEST_FATAL_STREAM, 1'b0, 9'd0, 16'he1ff);
        check(completion_stop_epoch == 32'he100_0001 && reset_required,
              "fatal causal completion preserves installed stop epoch/reset fence");
        trace_diff_point(34);
        @(negedge clk);
        fault_event_ready = 1'b1;
        @(posedge clk);
        #1;
        @(negedge clk);
        fault_event_ready = 1'b0;
        retire_completion;
        trace_diff_point(35);
        wait_stop_response(TEST_FATAL_STREAM, 32'he100_0001);
        trace_diff_point(36);
        $display("TRACE_AILS_DIFF_END steps=37");

        // -----------------------------------------------------------------
        // A simultaneous local stream failure cannot suppress an exact
        // reference release belonging to already-admitted causal work.
        // Its one terminal response reports the local cut while completing
        // the decrement exactly once.
        // -----------------------------------------------------------------
        reset_dut;
        $display("TEST exact REF_RELEASE survives same-edge local stream cut");
        open_list(4'd0, 2'd0, 9'd320,
                  CONTEXT0 + 32'h4200, SEQ0 + 32'h4200,
                  CANCEL0 + 32'h4200);
        finish_zero_list(16'he201);
        live_ref_owner[0] = 32'he200_0001;
        acquire_reference(REF_CONTEXT, live_ref_owner[0], REF_PERSISTENT,
                          STATUS_OK, 16'he202, ref_a);
        saved_ref_token = ref_a;
        save_live_handle(0);
        open_list(4'd0, 2'd0, 9'd320,
                  CONTEXT0 + 32'h4201, SEQ0 + 32'h4201,
                  CANCEL0 + 32'h4201);
        start_list;
        save_live_handle(1);
        @(negedge clk);
        load_live_handle(0);
        drive_saved_identity;
        mgmt_req_opcode = OP_REF_RELEASE;
        mgmt_req_stop_epoch = 32'd0;
        mgmt_req_ref_token = live_ref_token[0];
        mgmt_req_ref_owner_kind = REF_CONTEXT;
        mgmt_req_ref_owner_token = live_ref_owner[0];
        mgmt_req_ref_phase = REF_PERSISTENT;
        mgmt_req_tag = 16'he203;
        mgmt_req_valid = 1'b1;
        direct_active_cmd_valid = 1'b1;
        direct_active_cmd_write = 1'b0;
        direct_active_cmd_index = 9'd5;
        direct_active_cmd_tag = 16'he204;
        direct_active_cmd_finalize = 1'b0;
        #1;
        check(mgmt_req_ready && active_cmd_ready,
              "exact REF_RELEASE retains admission on same-edge local fault");
        @(posedge clk);
        #1;
        check(mgmt_rsp_valid && mgmt_rsp_status == ERR_BAD_COMMAND_ENCODING &&
              mgmt_rsp_committed && mgmt_rsp_released &&
              external_reference_total == 6'd0,
              "same-edge local cut returns one committed/released terminal response");
        check(local_error_list_token == live_token[1] &&
              local_error_code == ERR_BAD_COMMAND_ENCODING,
              "local fault scope names producer, not released reference list");
        @(negedge clk);
        mgmt_req_valid = 1'b0;
        direct_active_cmd_valid = 1'b0;
        retire_mgmt_response;
        load_live_handle(1);
        send_direct_command(1'b0, 9'd319, 16'he2ff, 1'b1);
        wait_for_completion(ERR_BAD_COMMAND_ENCODING, 1'b0, 9'd0, 16'he2ff);
        @(negedge clk);
        fault_event_ready = 1'b1;
        @(posedge clk);
        #1;
        @(negedge clk);
        fault_event_ready = 1'b0;
        retire_completion;

        // Exact post-abort reference cleanup similarly commits once and
        // returns ERR_ABORTED rather than pretending the release failed.
        reset_dut;
        $display("TEST exact REF_RELEASE survives installed abort cut");
        open_list(4'd0, 2'd0, 9'd320,
                  CONTEXT0 + 32'h4300, SEQ0 + 32'h4300,
                  CANCEL0 + 32'h4300);
        finish_zero_list(16'he301);
        acquire_reference(REF_CONTEXT, 32'he300_0001, REF_PERSISTENT,
                          STATUS_OK, 16'he302, ref_a);
        issue_stop(32'he300_0010, 1'b0, 1'b0, ERR_ABORTED);
        release_reference_generic(ref_a, REF_CONTEXT, 32'he300_0001,
                                  REF_PERSISTENT, 32'he300_0010,
                                  ERR_ABORTED, 1'b1);
        check(external_reference_total == 6'd0,
              "post-abort exact release leaves no external-reference leak");
        wait_stop_response(ERR_ABORTED, 32'he300_0010);

        // -----------------------------------------------------------------
        // An exact LIST_RELEASE can be preaccepted while a read response is
        // held.  CLOSING blocks exact-target new reads; a later fatal changes
        // only the unmaterialized release response, not its side effect or
        // the already-materialized read response.
        // -----------------------------------------------------------------
        reset_dut;
        $display("TEST preaccepted CLOSING under fatal cut and exact-target read fence");
        open_list(4'd0, 2'd0, 9'd320,
                  CONTEXT0 + 32'h4400, SEQ0 + 32'h4400,
                  CANCEL0 + 32'h4400);
        start_list;
        send_direct_command(1'b1, 9'd5, 16'he401, 1'b0);
        send_direct_command(1'b0, 9'd319, 16'he4ff, 1'b1);
        wait_for_completion(STATUS_OK, 1'b1, 9'd1, 16'he4ff);
        retire_completion;
        drive_one_read(1'b1, 9'd0, 16'he410);
        timeout = 0;
        while ((read_rsp_valid !== 1'b1) && (timeout < 100)) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        check(timeout < 100 && read_rsp_status == STATUS_OK &&
              read_rsp_data_usable && read_rsp_source_index == 9'd5,
              "pre-fatal held read has materialized immutable usable data");
        @(negedge clk);
        drive_saved_identity;
        mgmt_req_opcode = OP_LIST_RELEASE;
        mgmt_req_stop_epoch = 32'd0;
        mgmt_req_external_safe = 1'b1;
        mgmt_req_tag = 16'he411;
        mgmt_req_valid = 1'b1;
        wait_mgmt_ready_and_fire;
        check(state_of(saved_slot) == ST_CLOSING && closing_busy &&
              !mgmt_rsp_valid,
              "preaccepted LIST_RELEASE waits in CLOSING for held read");
        @(negedge clk);
        drive_saved_read_identity;
        read_req_kind = 1'b1;
        read_req_ordinal = 9'd0;
        read_req_tag = 16'he412;
        read_req_valid = 1'b1;
        #1;
        check(!read_req_ready && read_outstanding == 2'd1,
              "exact CLOSING target read is backpressured, not admitted as new work");
        @(posedge clk);
        #1;
        check(read_outstanding == 2'd1,
              "blocked CLOSING-target read consumes no second order credit");
        @(negedge clk);
        read_req_valid = 1'b0;
        issue_stop(32'he400_0010, 1'b1, 1'b0, TEST_FATAL_CLOSING);
        check(read_rsp_valid && read_rsp_status == STATUS_OK &&
              read_rsp_data_usable && read_rsp_source_index == 9'd5,
              "materialized read remains immutable across later fatal cut");
        retire_read_response;
        timeout = 0;
        while ((mgmt_rsp_valid !== 1'b1) && (timeout < 100)) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        check(timeout < 100 && mgmt_rsp_status == TEST_FATAL_CLOSING &&
              mgmt_rsp_committed && mgmt_rsp_released &&
              mgmt_rsp_stop_epoch == 32'he400_0010,
              "fatal-cut CLOSING response preserves committed release side effect");
        retire_mgmt_response;
        @(posedge clk);
        #1;
        check(state_of(saved_slot) == ST_FREE &&
              !slot_authority_valid[saved_slot],
              "fatal-cut release response still frees exact old slot once");
        wait_stop_response(TEST_FATAL_CLOSING, 32'he400_0010);

        // -----------------------------------------------------------------
        // Emergency data-untrusted stop permits arbitrary requests only to
        // terminalize them with selected fatal/zero data.  It never acquires
        // a read reference or exposes stale RAM contents.
        // -----------------------------------------------------------------
        reset_dut;
        $display("TEST data-untrusted fatal arbitrary read zero/status cut");
        open_list(4'd0, 2'd0, 9'd320,
                  CONTEXT0 + 32'h4500, SEQ0 + 32'h4500,
                  CANCEL0 + 32'h4500);
        start_list;
        send_direct_command(1'b1, 9'd6, 16'he501, 1'b0);
        send_direct_command(1'b0, 9'd319, 16'he5ff, 1'b1);
        wait_for_completion(STATUS_OK, 1'b1, 9'd1, 16'he5ff);
        retire_completion;
        issue_stop(32'he500_0010, 1'b1, 1'b1, TEST_FATAL_UNTRUSTED);
        check(reset_required,
              "data-untrusted fatal immediately requires coordinated reset");
        @(negedge clk);
        read_req_kind = 1'b1;
        read_req_slot_locator = 5'd31;
        read_req_list_token = 32'hffff_eeee;
        read_req_list_generation = 16'heeee;
        read_req_image_epoch = 32'hffff_dddd;
        read_req_stage_id = 4'd15;
        read_req_logical_branch = 2'd3;
        read_req_context_generation = 32'hffff_cccc;
        read_req_producer_sequence_ticket = 32'hffff_bbbb;
        read_req_cancellation_epoch = 32'hffff_aaaa;
        read_req_causal_continuation = 1'b0;
        read_req_stop_epoch = 32'd0;
        read_req_external_ref_token = 32'd0;
        read_req_ordinal = 9'd319;
        read_req_tag = 16'he510;
        read_req_valid = 1'b1;
        #1;
        check(read_req_ready,
              "installed data-untrusted fatal admits arbitrary request for terminal cut");
        @(posedge clk);
        #1;
        @(negedge clk);
        read_req_valid = 1'b0;
        timeout = 0;
        while ((read_rsp_valid !== 1'b1) && (timeout < 100)) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        check(timeout < 100 && read_rsp_status == TEST_FATAL_UNTRUSTED &&
              !read_rsp_data_usable && read_rsp_source_index == 9'd0 &&
              !read_rsp_sealed && read_reference_total == 2'd0,
              "data-untrusted arbitrary read returns zero selected-fatal without authority");
        retire_read_response;

        // -----------------------------------------------------------------
        // Verification-only invariant injection.  A legal referenced list
        // is deliberately corrupted to the impossible CONTEXT/PENDING
        // reference tuple while an accepted index read is still in the
        // synchronous-RAM result stage.  The internal checker must fence a
        // second request combinationally and cut the unmaterialized result
        // to zero/ERR_INTERNAL_STATE on the following edge.
        // -----------------------------------------------------------------
        reset_dut;
        $display("TEST reference-record invariant injection fail-closed");
        open_list(4'd0, 2'd0, 9'd320,
                  CONTEXT0 + 32'h4600, SEQ0 + 32'h4600,
                  CANCEL0 + 32'h4600);
        start_list;
        send_direct_command(1'b1, 9'd12, 16'he601, 1'b0);
        send_direct_command(1'b0, 9'd319, 16'he6ff, 1'b1);
        wait_for_completion(STATUS_OK, 1'b1, 9'd1, 16'he6ff);
        retire_completion;
        acquire_reference(REF_CONTEXT, 32'he600_0001, REF_PERSISTENT,
                          STATUS_OK, 16'he610, ref_a);
        check(dut.ref0_valid_r[saved_slot] &&
              dut.ref0_owner_kind_r[saved_slot] == REF_CONTEXT &&
              dut.ref0_phase_r[saved_slot] == REF_PERSISTENT,
              "invariant fixture begins as a legal persistent context reference");
        drive_one_read(1'b1, 9'd0, 16'he611);
        check(read_outstanding == 2'd1 && dut.read_result_pending,
              "invariant fixture holds one accepted unmaterialized RAM read");
        drive_saved_read_identity;
        read_req_kind = 1'b1;
        read_req_ordinal = 9'd0;
        read_req_tag = 16'he612;
        read_req_valid = 1'b1;
        // Vivado 2018.3 does not permit force/release on an unpacked reg-array
        // word.  A hierarchical procedural assignment provides deposit
        // semantics here; coordinated reset is the only recovery operation.
        dut.ref0_owner_kind_r[saved_slot] = REF_CONTEXT;
        dut.ref0_phase_r[saved_slot] = REF_PENDING;
        #1;
        check(dut.internal_fault_comb && !read_req_ready,
              "impossible live reference tuple immediately fences new reads");
        @(posedge clk);
        #1;
        check(local_fault_pending && local_error_valid &&
              local_error_code == ERR_INTERNAL_STATE && reset_required &&
              local_error_slot_locator == saved_slot &&
              local_error_list_token == saved_token,
              "reference invariant failure latches exact internal/reset-required scope");
        check(fault_event_valid && fault_event_code == ERR_INTERNAL_STATE &&
              fault_event_source == 4'd7 && fault_event_reset_required &&
              fault_event_slot_locator == saved_slot &&
              fault_event_list_token == saved_token,
              "reference invariant failure emits one exact internal fault event");
        check(read_rsp_valid && read_rsp_status == ERR_INTERNAL_STATE &&
              !read_rsp_data_usable && read_rsp_source_index == 9'd0,
              "unmaterialized read is cut to internal error with zero unusable data");
        check(read_outstanding == 2'd1 && read_reference_total == 2'd1,
              "blocked second read consumes no credit during invariant failure");
        @(negedge clk);
        read_req_valid = 1'b0;
        retire_read_response;
        @(negedge clk);
        fault_event_ready = 1'b1;
        @(posedge clk);
        #1;
        @(negedge clk);
        fault_event_ready = 1'b0;
        check(!fault_event_valid,
              "internal invariant fault event retires exactly once");
        reset_dut;
        check(!local_error_valid && !local_fault_pending && !reset_required &&
              external_reference_total == 6'd0,
              "coordinated reset recovers invariant failure without stale authority");

        // A list-only reset proof is never sufficient to create fresh PE
        // producer authority.  A structurally legal OPEN must wait for the
        // owner-provided coordinated PE/list recovery proof.
        reset_dut;
        $display("TEST coordinated-recovery proof gates fresh OPEN");
        timeout = 0;
        while ((allocation_candidate_valid !== 1'b1) && (timeout < 100)) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        check(timeout < 100, "recovery-proof test obtains a FREE candidate");
        @(negedge clk);
        mgmt_req_opcode = OP_OPEN;
        mgmt_req_image_epoch = IMAGE0;
        mgmt_req_stage_id = 4'd0;
        mgmt_req_logical_branch = 2'd0;
        mgmt_req_context_generation = CONTEXT0 + 32'h4700;
        mgmt_req_producer_sequence_ticket = SEQ0 + 32'h4700;
        mgmt_req_cancellation_epoch = CANCEL0 + 32'h4700;
        mgmt_req_stop_epoch = 32'd0;
        mgmt_req_domain_bound = 9'd320;
        mgmt_req_pe_recovery_safe = 1'b0;
        mgmt_req_tag = 16'he700;
        mgmt_req_valid = 1'b1;
        repeat (3) begin
            #1;
            check(!mgmt_req_ready && free_slot_count == 5'd21 &&
                  !current_producer_valid,
                  "OPEN with recovery proof low cannot allocate authority");
            @(posedge clk);
            @(negedge clk);
        end
        mgmt_req_valid = 1'b0;

        // -----------------------------------------------------------------
        // Connected Frozen zero-source list.  The last negative scalar is
        // suppressed as an index write but the writer must still emit the
        // terminal non-spike finalize and seal an immutable count-zero list.
        // -----------------------------------------------------------------
        reset_dut;
        $display("TEST frozen connected zero-source completion");
        open_list(4'd0, 2'd0, 9'd320,
                  CONTEXT0 + 32'h4800, SEQ0 + 32'h4800,
                  CANCEL0 + 32'h4800);
        start_list;
        use_frozen_path = 1'b1;
        dense_state_ready = 1'b1;
        send_qbn_scalar(-8'sd1, 9'd319, 16'h0000, 1'b1);
        wait_fork_idle;
        check(dense_fires == 1 && writer_fires == 1,
              "terminal negative scalar reaches dense sink and writer exactly once");
        wait_for_completion(STATUS_OK, 1'b1, 9'd0, 16'h0000);
        check(!completion_last_valid && completion_last_committed_index == 9'd0,
              "Frozen terminal non-spike publishes no fabricated source index");
        send_qbn_scalar(-8'sd1, 9'd319, 16'h00ff, 1'b1);
        check(writer_cmd_valid && writer_cmd_finalize && !active_cmd_ready,
              "duplicate Frozen finalize is held outside producer authority");
        @(posedge clk);
        #1;
        check(local_error_valid &&
              local_error_code == ERR_DUPLICATE_FINALIZE && reset_required &&
              fault_event_valid &&
              fault_event_code == ERR_DUPLICATE_FINALIZE &&
              local_error_slot_locator == saved_slot,
              "held duplicate finalize receives exact reset-required classification");
        check(completion_valid && completion_status == STATUS_OK &&
              completion_sealed && completion_active_count == 9'd0 &&
              completion_terminal_tag == 16'h0000 && writer_fires == 1,
              "duplicate finalize cannot rewrite held successful completion or refire writer");

        // -----------------------------------------------------------------
        // Frozen terminal-spike atomicity plus same-edge fork replacement.
        // The second scalar is installed on the exact edge that retires the
        // first scalar.  Repeated all-ones PE tags remain opaque metadata and
        // cannot affect list token, count, ordering, or terminal detection.
        // -----------------------------------------------------------------
        reset_dut;
        $display("TEST frozen terminal spike, tag opacity, and same-edge replacement");
        open_list(4'd0, 2'd0, 9'd320,
                  CONTEXT0 + 32'h4900, SEQ0 + 32'h4900,
                  CANCEL0 + 32'h4900);
        start_list;
        use_frozen_path = 1'b1;
        dense_state_ready = 1'b0;
        @(negedge clk);
        qbn_value = 8'sd1;
        qbn_index = 9'd7;
        qbn_tag = 16'hffff;
        qbn_last = 1'b0;
        qbn_valid = 1'b1;
        #1;
        check(qbn_ready, "empty fork accepts first terminal-spike fixture scalar");
        @(posedge clk);
        #1;
        @(negedge clk);
        qbn_valid = 1'b0;
        check(fork_valid && fork_index == 9'd7 && !qbn_ready,
              "stalled dense sink holds first scalar and blocks replacement");
        dense_state_ready = 1'b1;
        qbn_value = 8'sd1;
        qbn_index = 9'd319;
        qbn_tag = 16'hffff;
        qbn_last = 1'b1;
        qbn_valid = 1'b1;
        #1;
        check(qbn_ready && writer_cmd_valid && active_cmd_ready,
              "ready replacement edge simultaneously retires first Frozen spike");
        @(posedge clk);
        #1;
        check(fork_valid && fork_index == 9'd319 && fork_last &&
              dense_fires == 1 && writer_fires == 1,
              "same edge replaces fork payload without bubble or duplicate fire");
        @(negedge clk);
        qbn_valid = 1'b0;
        wait_fork_idle;
        check(dense_fires == 2 && writer_fires == 2,
              "terminal spike reaches both fork sinks exactly once");
        wait_for_completion(STATUS_OK, 1'b1, 9'd2, 16'hffff);
        check(completion_last_valid &&
              completion_last_committed_index == 9'd319 &&
              completion_list_token == saved_token,
              "terminal spike atomically writes lane, increments count, and keeps tag opaque");
        retire_completion;
        drive_one_read(1'b1, 9'd1, 16'hffff);
        timeout = 0;
        while ((read_rsp_valid !== 1'b1) && (timeout < 100)) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        check(timeout < 100 && read_rsp_status == STATUS_OK &&
              read_rsp_data_usable && read_rsp_source_index == 9'd319 &&
              read_rsp_last && read_rsp_tag == 16'hffff,
              "terminal spike payload is readable at exact final ordinal despite repeated tag");
        retire_read_response;

        // -----------------------------------------------------------------
        // A Frozen duplicate spike poisons the current list, but the sink
        // remains ready for subsequent Frozen commands through the matching
        // real terminal scalar.  No post-poison writer command reaches RAM.
        // -----------------------------------------------------------------
        reset_dut;
        $display("TEST frozen poison-ready progress through real finalize");
        open_list(4'd0, 2'd0, 9'd320,
                  CONTEXT0 + 32'h4a00, SEQ0 + 32'h4a00,
                  CANCEL0 + 32'h4a00);
        start_list;
        use_frozen_path = 1'b1;
        dense_state_ready = 1'b1;
        send_qbn_scalar(8'sd1, 9'd5, 16'h5a01, 1'b0);
        wait_fork_idle;
        fault_event_ready = 1'b0;
        send_qbn_scalar(8'sd1, 9'd5, 16'h5a02, 1'b0);
        wait_fork_idle;
        check(local_error_valid && local_error_code == ERR_UNORDERED_INDEX &&
              state_of(saved_slot) == ST_POISON_DRAIN && active_cmd_ready &&
              producer_obligation,
              "Frozen duplicate enters poison while preserving ready/finalize debt");
        send_qbn_scalar(8'sd1, 9'd20, 16'h5a03, 1'b0);
        wait_fork_idle;
        check(active_cmd_ready && fault_event_valid &&
              fault_event_code == ERR_UNORDERED_INDEX,
              "Frozen post-poison spike is consumed/discarded without overwriting first fault");
        send_qbn_scalar(-8'sd1, 9'd319, 16'h5aff, 1'b1);
        wait_fork_idle;
        wait_for_completion(ERR_UNORDERED_INDEX, 1'b0, 9'd1, 16'h5aff);
        check(completion_last_valid && completion_last_committed_index == 9'd5 &&
              dense_fires == 4 && writer_fires == 4,
              "real Frozen finalize drains poison and excludes discarded writes from count");
        @(negedge clk);
        fault_event_ready = 1'b1;
        @(posedge clk);
        #1;
        @(negedge clk);
        fault_event_ready = 1'b0;
        retire_completion;
        check(state_of(saved_slot) == ST_ERROR,
              "Frozen poisoned list publishes no read/reference authority");

        // -----------------------------------------------------------------
        // An old Frozen command presented before START must win admission
        // arbitration over an exact START request.  The writer remains held,
        // neither side of START commits, and only coordinated reset can make
        // fresh producer authority safe again.
        // -----------------------------------------------------------------
        reset_dut;
        $display("TEST frozen pre-START command fences atomic START and needs reset");
        open_list(4'd0, 2'd0, 9'd320,
                  CONTEXT0 + 32'h4b00, SEQ0 + 32'h4b00,
                  CANCEL0 + 32'h4b00);
        use_frozen_path = 1'b1;
        dense_state_ready = 1'b1;
        send_qbn_scalar(8'sd1, 9'd3, 16'h5b03, 1'b0);
        check(writer_cmd_valid && !active_cmd_ready,
              "pre-START Frozen spike is held without a sink handshake");
        drive_saved_identity;
        mgmt_req_opcode = OP_PRODUCER_START;
        mgmt_req_pe_recovery_safe = 1'b1;
        mgmt_req_tag = 16'h5b10;
        mgmt_req_valid = 1'b1;
        start_partner_ready = 1'b1;
        #1;
        check(!mgmt_req_ready && !start_partner_valid,
              "held old Frozen command fences both sides of same-edge START");
        @(posedge clk);
        #1;
        check(local_fault_pending && reset_required && !producer_started &&
              !producer_obligation && !mgmt_rsp_valid,
              "pre-START command fault creates no half-committed producer job");
        check(writer_cmd_valid && !active_cmd_ready,
              "offending Frozen command remains held behind registered fault fence");
        @(negedge clk);
        mgmt_req_valid = 1'b0;
        start_partner_ready = 1'b0;
        reset_dut;
        check(!fork_valid && !writer_cmd_valid && !reset_required &&
              free_slot_count == 5'd21,
              "coordinated reset clears both Frozen fork and list-store authority");

        // -----------------------------------------------------------------
        // Deterministic pseudo-random dense-side backpressure across a full
        // 320-scalar Frozen sequence.  Every fifth scalar spikes; the final
        // non-spike must close the list.  The one-entry fork must always make
        // progress and repeated PE tags must not alter sparse membership.
        // -----------------------------------------------------------------
        reset_dut;
        $display("TEST frozen randomized dense-backpressure deadlock stress");
        open_list(4'd0, 2'd0, 9'd320,
                  CONTEXT0 + 32'h4c00, SEQ0 + 32'h4c00,
                  CANCEL0 + 32'h4c00);
        start_list;
        use_frozen_path = 1'b1;
        dense_state_ready = 1'b1;
        stress_lfsr = 32'h41a1_5e01;
        for (i = 0; i < 320; i = i + 1) begin
            if ((i % 5) == 0)
                send_qbn_scalar_random_backpressure(8'sd1, i[8:0],
                                                     16'ha5a5,
                                                     i == 319);
            else
                send_qbn_scalar_random_backpressure(-8'sd1, i[8:0],
                                                     16'ha5a5,
                                                     i == 319);
        end
        check(!fork_valid && dense_fires == 320 && writer_fires == 65,
              "random backpressure drains all 320 dense scalars and 65 writer commands");
        wait_for_completion(STATUS_OK, 1'b1, 9'd64, 16'ha5a5);
        check(completion_last_valid && completion_last_committed_index == 9'd315 &&
              !local_fault_pending,
              "randomized connected list preserves exact sparse count/order without deadlock");
        repeat (7) begin
            @(posedge clk);
            #1;
            check(completion_valid && completion_status == STATUS_OK &&
                  completion_active_count == 9'd64 &&
                  completion_terminal_tag == 16'ha5a5,
                  "randomly produced completion remains stable under extended stall");
        end
        retire_completion;

        // -----------------------------------------------------------------
        // Verification-only connected frozen writer path.  The dense-state
        // fork side must accept each scalar before its decision side can emit
        // an active command.  Ordinary non-spikes disappear; terminal
        // non-spike still finalizes the list.
        // -----------------------------------------------------------------
        reset_dut;
        $display("TEST frozen spike/writer with dense-state-first fork harness");
        open_list(4'd0, 2'd0, 9'd320,
                  CONTEXT0 + 32'd6, SEQ0 + 32'd6, CANCEL0 + 32'd6);
        start_list;
        use_frozen_path = 1'b1;
        dense_state_ready = 1'b1;
        send_qbn_scalar(-8'sd7, 9'd0, 16'h7100, 1'b0);
        wait_fork_idle;
        check(dense_fires == 1 && writer_fires == 0,
              "ordinary negative scalar writes dense state but emits no list command");

        dense_state_ready = 1'b0;
        send_qbn_scalar(8'sd0, 9'd7, 16'h7107, 1'b0);
        repeat (3) begin
            @(posedge clk);
            #1;
            check(!writer_cmd_valid,
                  "frozen decision cannot outrun stalled dense-state sink");
        end
        @(negedge clk);
        dense_state_ready = 1'b1;
        wait_fork_idle;
        check(dense_fires == 2 && writer_fires == 1,
              "inclusive-zero spike emits once after dense-state acceptance");

        send_qbn_scalar(-8'sd1, 9'd319, 16'h71ff, 1'b1);
        wait_fork_idle;
        check(dense_fires == 3 && writer_fires == 2,
              "terminal non-spike emits one finalize after dense-state acceptance");
        wait_for_completion(STATUS_OK, 1'b1, 9'd1, 16'h71ff);
        check(completion_last_valid && completion_last_committed_index == 9'd7,
              "connected frozen writer preserves index/write/finalize semantics");
        retire_completion;

        // An out-of-phase frozen command must fence recovery rather than be
        // silently ignored.  It is observed without a ready/valid handshake.
        @(negedge clk);
        use_frozen_path = 1'b0;
        direct_active_cmd_valid = 1'b1;
        direct_active_cmd_write = 1'b0;
        direct_active_cmd_index = 9'd319;
        direct_active_cmd_tag = 16'h7bad;
        direct_active_cmd_finalize = 1'b1;
        check(!active_cmd_ready, "post-terminal command has no sink authority");
        @(posedge clk);
        #1;
        check(reset_required && local_fault_pending,
              "unexpected post-terminal command requires coordinated recovery");
        @(negedge clk);
        direct_active_cmd_valid = 1'b0;

        repeat (5) @(posedge clk);
        if (failures == 0)
            $display("PASS tb_active_index_list_store checks=%0d", checks);
        else
            $display("FAIL: tb_active_index_list_store failures=%0d checks=%0d",
                     failures, checks);
        $finish;
    end

endmodule
