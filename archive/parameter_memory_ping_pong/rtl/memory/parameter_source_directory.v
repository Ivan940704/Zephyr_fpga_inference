`timescale 1ns/1ps

// Two compact source directories and one binding-selected lookup pipeline.
//
// This module owns directory metadata only.  It neither instantiates nor
// mutates a parameter_weight_bank.  The two physical read channel groups at
// the bottom of the port list connect to already-owned bank instances.
// Directory RAM contents deliberately have no reset path; reset revokes all
// authority and requires an explicit 1024-entry scrub before a fresh claim.
module parameter_source_directory (
    input  wire         clk,
    input  wire         rst_n,

    output wire [5:0]   directory_state,
    output wire [31:0]  directory_generation,
    output wire [1:0]   directory_generation_initialized,
    output wire [1:0]   directory_descriptor_valid,
    output wire [1:0]   directory_lease_authority_valid,
    output wire [1:0]   directory_content_valid,
    output wire [1:0]   directory_scrub_required,
    output wire [1:0]   directory_scrub_busy,
    output wire [19:0]  directory_scrub_address,
    output wire [1:0]   directory_last_scrubbed_image_epoch_valid,
    output wire [63:0]  directory_last_scrubbed_image_epoch,
    output wire [19:0]  directory_committed_source_count,
    output wire [1:0]   directory_management_fence,
    output wire         management_busy,
    output wire         final_close_pending,
    output wire [1:0]   lookup_outstanding,
    output wire         directory_read_busy,
    output wire         publication_busy,
    output wire [3:0]   directory_to_bank_pending,
    output wire [3:0]   bank_rsp_outstanding,
    output wire [3:0]   directory_bank_ref_count,
    output wire         directory_quiescent,
    output wire [1:0]   bank_quiescent,
    output wire [1:0]   bank_drain_complete,
    output wire [1:0]   bank_retire_safe,
    output wire [1:0]   reset_required,
    output wire         global_reset_required,

    output wire [63:0]  directory_image_epoch,
    output wire [7:0]   directory_stage_id,
    output wire [63:0]  directory_stage_ticket,
    output wire [3:0]   directory_logical_branch,
    output wire [63:0]  directory_context_generation,
    output wire [63:0]  directory_content_handle,
    output wire [63:0]  directory_physical_bank_generation,
    output wire [63:0]  directory_cancellation_epoch,
    output wire [3:0]   directory_matrix_mask,
    output wire [63:0]  directory_matrix0_binding_token,
    output wire [63:0]  directory_matrix1_binding_token,
    output wire [19:0]  directory_matrix0_source_count,
    output wire [19:0]  directory_matrix1_source_count,
    output wire [11:0]  directory_matrix0_row_tile_count,
    output wire [11:0]  directory_matrix1_row_tile_count,

    output wire [1:0]   local_error_valid,
    output wire [15:0]  local_error_code,
    output wire [5:0]   local_error_source,
    output wire [63:0]  local_error_detail,
    output wire [31:0]  local_error_directory_generation,
    output wire [63:0]  local_error_physical_bank_generation,
    output wire [63:0]  local_error_stage_ticket,
    output wire [63:0]  local_error_content_handle,

    input  wire         mgmt_req_valid,
    output wire         mgmt_req_ready,
    input  wire [3:0]   mgmt_req_opcode,
    input  wire [1:0]   mgmt_req_bank_mask,
    input  wire [1:0]   mgmt_req_drain_target,
    input  wire [15:0]  mgmt_req_expected_directory_generation,
    input  wire [31:0]  mgmt_req_expected_content_handle,
    input  wire [31:0]  mgmt_req_expected_stage_ticket,
    input  wire [31:0]  mgmt_req_expected_physical_bank_generation,
    input  wire [31:0]  mgmt_req_new_image_epoch,
    input  wire [3:0]   mgmt_req_new_stage_id,
    input  wire [31:0]  mgmt_req_new_stage_ticket,
    input  wire [1:0]   mgmt_req_new_logical_branch,
    input  wire [31:0]  mgmt_req_new_context_generation,
    input  wire [31:0]  mgmt_req_new_content_handle,
    input  wire [31:0]  mgmt_req_new_physical_bank_generation,
    input  wire [31:0]  mgmt_req_new_cancellation_epoch,
    input  wire [1:0]   mgmt_req_new_matrix_mask,
    input  wire [31:0]  mgmt_req_new_matrix0_binding_token,
    input  wire [31:0]  mgmt_req_new_matrix1_binding_token,
    input  wire [9:0]   mgmt_req_new_matrix0_source_count,
    input  wire [9:0]   mgmt_req_new_matrix1_source_count,
    input  wire [5:0]   mgmt_req_new_matrix0_row_tile_count,
    input  wire [5:0]   mgmt_req_new_matrix1_row_tile_count,
    input  wire         mgmt_req_external_safe,
    input  wire [15:0]  mgmt_req_tag,
    output wire         mgmt_rsp_valid,
    input  wire         mgmt_rsp_ready,
    output wire [3:0]   mgmt_rsp_opcode,
    output wire [1:0]   mgmt_rsp_bank_mask,
    output wire [5:0]   mgmt_rsp_state,
    output wire [31:0]  mgmt_rsp_directory_generation,
    output wire [15:0]  mgmt_rsp_tag,
    output wire [7:0]   mgmt_rsp_status,

    input  wire         force_error_valid,
    output wire         force_error_ready,
    input  wire [1:0]   force_error_bank_mask,
    input  wire [7:0]   force_error_code,
    input  wire         force_error_data_untrusted,
    input  wire         force_error_causal_producers_drained,
    input  wire [31:0]  force_error_directory_generation,
    input  wire [63:0]  force_error_stage_ticket,
    input  wire [63:0]  force_error_content_handle,
    input  wire [63:0]  force_error_physical_bank_generation,
    input  wire [31:0]  force_error_cancellation_epoch,
    input  wire [15:0]  force_error_tag,
    output wire         force_error_rsp_valid,
    input  wire         force_error_rsp_ready,
    output wire [1:0]   force_error_rsp_bank_mask,
    output wire [7:0]   force_error_rsp_code,
    output wire [5:0]   force_error_rsp_state,
    output wire [31:0]  force_error_rsp_directory_generation,
    output wire [1:0]   force_error_rsp_reset_required,
    output wire [15:0]  force_error_rsp_tag,
    output wire [7:0]   force_error_rsp_status,

    input  wire         publish_req_valid,
    output wire         publish_req_ready,
    input  wire         publish_req_bank_id,
    input  wire [31:0]  publish_req_image_epoch,
    input  wire [3:0]   publish_req_stage_id,
    input  wire [31:0]  publish_req_stage_ticket,
    input  wire [1:0]   publish_req_logical_branch,
    input  wire [31:0]  publish_req_context_generation,
    input  wire [31:0]  publish_req_matrix_binding_token,
    input  wire [31:0]  publish_req_content_handle,
    input  wire [31:0]  publish_req_physical_bank_generation,
    input  wire [15:0]  publish_req_directory_generation,
    input  wire [31:0]  publish_req_cancellation_epoch,
    input  wire         publish_req_matrix_id,
    input  wire [9:0]   publish_req_source_index,
    input  wire [12:0]  publish_req_slot_base,
    input  wire [9:0]   publish_req_source_count,
    input  wire [5:0]   publish_req_row_tile_count,
    input  wire [1:0]   publish_req_matrix_mask,
    input  wire         publish_req_source_complete_proof,
    input  wire         publish_req_slot_assignment_validated,
    input  wire [15:0]  publish_req_tag,
    output wire         publish_rsp_valid,
    input  wire         publish_rsp_ready,
    output wire         publish_rsp_bank_id,
    output wire         publish_rsp_matrix_id,
    output wire [9:0]   publish_rsp_source_index,
    output wire [12:0]  publish_rsp_slot_base,
    output wire [15:0]  publish_rsp_directory_generation,
    output wire         publish_rsp_committed,
    output wire [9:0]   publish_rsp_committed_source_count,
    output wire [15:0]  publish_rsp_tag,
    output wire [7:0]   publish_rsp_status,

    input  wire         lookup_req_valid,
    output wire         lookup_req_ready,
    input  wire         lookup_req_kind,
    input  wire [31:0]  lookup_req_image_epoch,
    input  wire [3:0]   lookup_req_stage_id,
    input  wire [31:0]  lookup_req_stage_ticket,
    input  wire [1:0]   lookup_req_logical_branch,
    input  wire [31:0]  lookup_req_context_generation,
    input  wire         lookup_req_matrix_id,
    input  wire [9:0]   lookup_req_source_index,
    input  wire [5:0]   lookup_req_row_tile,
    input  wire [31:0]  lookup_req_matrix_binding_token,
    input  wire [31:0]  lookup_req_cancellation_epoch,
    input  wire [15:0]  lookup_req_user_tag,
    input  wire         lookup_res_resolution_validated,
    input  wire         lookup_res_selected_bank_id,
    input  wire [31:0]  lookup_res_physical_bank_generation,
    input  wire [31:0]  lookup_res_lease_owner_ticket,
    input  wire [31:0]  lookup_res_matrix_binding_token,
    input  wire [31:0]  lookup_res_content_handle,
    input  wire [15:0]  lookup_res_directory_generation,
    input  wire [31:0]  lookup_res_image_epoch,
    input  wire [3:0]   lookup_res_stage_id,
    input  wire [1:0]   lookup_res_logical_branch,
    input  wire [31:0]  lookup_res_context_generation,
    input  wire [31:0]  lookup_res_cancellation_epoch,
    input  wire [9:0]   lookup_res_matrix_source_count,
    input  wire [5:0]   lookup_res_row_tile_count,
    input  wire [1:0]   lookup_res_matrix_mask,
    input  wire         lookup_res_source_domain_validated,
    input  wire         lookup_res_compute_membership_validated,
    input  wire         lookup_res_causal_continuation,
    output wire         lookup_rsp_valid,
    input  wire         lookup_rsp_ready,
    output wire         lookup_rsp_kind,
    output wire [31:0]  lookup_rsp_image_epoch,
    output wire [3:0]   lookup_rsp_stage_id,
    output wire [31:0]  lookup_rsp_stage_ticket,
    output wire [1:0]   lookup_rsp_logical_branch,
    output wire [31:0]  lookup_rsp_context_generation,
    output wire         lookup_rsp_matrix_id,
    output wire [9:0]   lookup_rsp_source_index,
    output wire [5:0]   lookup_rsp_row_tile,
    output wire [31:0]  lookup_rsp_matrix_binding_token,
    output wire [31:0]  lookup_rsp_cancellation_epoch,
    output wire         lookup_rsp_causal_continuation,
    output wire         lookup_rsp_selected_bank_id,
    output wire [31:0]  lookup_rsp_physical_bank_generation,
    output wire [31:0]  lookup_rsp_content_handle,
    output wire [15:0]  lookup_rsp_directory_generation,
    output wire [12:0]  lookup_rsp_slot_base,
    output wire [12:0]  lookup_rsp_weight_addr,
    output wire         lookup_rsp_hit,
    output wire [127:0] lookup_rsp_weight_data,
    output wire [15:0]  lookup_rsp_user_tag,
    output wire [7:0]   lookup_rsp_status,
    output wire         lookup_rsp_fatal,

    output wire         bank0_rd_req_valid,
    input  wire         bank0_rd_req_ready,
    output wire [12:0]  bank0_rd_req_addr,
    output wire [31:0]  bank0_rd_req_generation,
    output wire [31:0]  bank0_rd_req_lease_owner_ticket,
    output wire [15:0]  bank0_rd_req_tag,
    input  wire         bank0_rd_rsp_valid,
    output wire         bank0_rd_rsp_ready,
    input  wire [127:0] bank0_rd_rsp_data,
    input  wire [12:0]  bank0_rd_rsp_addr,
    input  wire [31:0]  bank0_rd_rsp_generation,
    input  wire [31:0]  bank0_rd_rsp_lease_owner_ticket,
    input  wire [15:0]  bank0_rd_rsp_tag,
    input  wire [7:0]   bank0_rd_rsp_status,

    output wire         bank1_rd_req_valid,
    input  wire         bank1_rd_req_ready,
    output wire [12:0]  bank1_rd_req_addr,
    output wire [31:0]  bank1_rd_req_generation,
    output wire [31:0]  bank1_rd_req_lease_owner_ticket,
    output wire [15:0]  bank1_rd_req_tag,
    input  wire         bank1_rd_rsp_valid,
    output wire         bank1_rd_rsp_ready,
    input  wire [127:0] bank1_rd_rsp_data,
    input  wire [12:0]  bank1_rd_rsp_addr,
    input  wire [31:0]  bank1_rd_rsp_generation,
    input  wire [31:0]  bank1_rd_rsp_lease_owner_ticket,
    input  wire [15:0]  bank1_rd_rsp_tag,
    input  wire [7:0]   bank1_rd_rsp_status,

    output wire         fault_event_valid,
    input  wire         fault_event_ready,
    output wire [1:0]   fault_event_bank_mask,
    output wire [7:0]   fault_event_code,
    output wire [31:0]  fault_event_detail,
    output wire [15:0]  fault_event_directory_generation,
    output wire [31:0]  fault_event_stage_ticket,
    output wire [31:0]  fault_event_content_handle,
    output wire [31:0]  fault_event_physical_bank_generation
);

    localparam [2:0] ST_INVALID   = 3'd0;
    localparam [2:0] ST_SCRUBBING = 3'd1;
    localparam [2:0] ST_LOADING   = 3'd2;
    localparam [2:0] ST_READY     = 3'd3;
    localparam [2:0] ST_ACTIVE    = 3'd4;
    localparam [2:0] ST_DRAINING  = 3'd5;
    localparam [2:0] ST_RETAINED  = 3'd6;
    localparam [2:0] ST_ERROR     = 3'd7;

    localparam [3:0] MGMT_SCRUB           = 4'h0;
    localparam [3:0] MGMT_CLAIM_FRESH     = 4'h1;
    localparam [3:0] MGMT_REBIND_RETAINED = 4'h2;
    localparam [3:0] MGMT_PUBLISH_READY   = 4'h3;
    localparam [3:0] MGMT_ACTIVATE        = 4'h4;
    localparam [3:0] MGMT_BEGIN_DRAIN     = 4'h5;
    localparam [3:0] MGMT_FINISH_DRAIN    = 4'h6;
    localparam [3:0] MGMT_CLEAR_ERROR     = 4'h7;

    localparam [1:0] DRAIN_INVALID  = 2'b00;
    localparam [1:0] DRAIN_RETAINED = 2'b01;
    localparam [1:0] DRAIN_ERROR    = 2'b10;

    localparam [7:0] STATUS_OK                        = 8'h00;
    localparam [7:0] STATUS_ERR_BAD_OPCODE            = 8'h01;
    localparam [7:0] STATUS_ERR_WRONG_STATE           = 8'h02;
    localparam [7:0] STATUS_ERR_STALE_GENERATION      = 8'h03;
    localparam [7:0] STATUS_ERR_OWNER_MISMATCH        = 8'h04;
    localparam [7:0] STATUS_ERR_NOT_QUIESCENT         = 8'h05;
    localparam [7:0] STATUS_ERR_EXTERNAL_UNSAFE       = 8'h06;
    localparam [7:0] STATUS_ERR_GENERATION_EXHAUSTED  = 8'h07;
    localparam [7:0] STATUS_ERR_BAD_DRAIN_TARGET      = 8'h08;
    localparam [7:0] STATUS_ERR_ABORTED               = 8'h09;
    localparam [7:0] STATUS_ERR_LOCAL_PROTOCOL        = 8'h0a;
    localparam [7:0] STATUS_ERR_INTERNAL_STATE        = 8'h0b;
    localparam [7:0] STATUS_ERR_BAD_BANK_MASK         = 8'h0c;
    localparam [7:0] STATUS_ERR_BAD_IDENTITY          = 8'h0d;
    localparam [7:0] STATUS_ERR_BAD_BOUNDS            = 8'h0e;
    localparam [7:0] STATUS_ERR_BAD_MATRIX            = 8'h0f;
    localparam [7:0] STATUS_ERR_BAD_SOURCE            = 8'h10;
    localparam [7:0] STATUS_ERR_BAD_ROW_TILE          = 8'h11;
    localparam [7:0] STATUS_ERR_DUPLICATE_PUBLICATION = 8'h12;
    localparam [7:0] STATUS_ERR_DIRECTORY_RELOCATION  = 8'h13;
    localparam [7:0] STATUS_ERR_DIRECTORY_INCOMPLETE  = 8'h14;
    localparam [7:0] STATUS_ERR_DIRECTORY_CORRUPT     = 8'h15;
    localparam [7:0] STATUS_ERR_COMPUTE_MISS          = 8'h16;
    localparam [7:0] STATUS_ERR_BANK_RESPONSE_ERROR   = 8'h17;
    localparam [7:0] STATUS_ERR_BANK_IDENTITY_MISMATCH = 8'h18;
    localparam [7:0] STATUS_ERR_MEMBERSHIP_UNPROVEN   = 8'h19;
    localparam [7:0] STATUS_ERR_SCRUB_REQUIRED        = 8'h1a;
    localparam [7:0] STATUS_ERR_CONTENT_MISMATCH      = 8'h1b;
    localparam [7:0] STATUS_ERR_CANCELLATION_STALE    = 8'h1c;

    localparam [2:0] ERROR_SOURCE_MANAGEMENT = 3'd0;
    localparam [2:0] ERROR_SOURCE_PUBLICATION = 3'd1;
    localparam [2:0] ERROR_SOURCE_LOOKUP = 3'd2;
    localparam [2:0] ERROR_SOURCE_BANK_RESPONSE = 3'd3;
    localparam [2:0] ERROR_SOURCE_SCRUB = 3'd4;
    localparam [2:0] ERROR_SOURCE_FINAL_CLOSE = 3'd5;
    localparam [2:0] ERROR_SOURCE_INTERNAL = 3'd6;

    localparam [2:0] SLOT_FREE         = 3'd0;
    localparam [2:0] SLOT_WAIT_DIR     = 3'd1;
    localparam [2:0] SLOT_LOCAL_DONE   = 3'd2;
    localparam [2:0] SLOT_BANK_PENDING = 3'd3;
    localparam [2:0] SLOT_BANK_WAIT    = 3'd4;
    localparam [2:0] SLOT_OUTPUT       = 3'd5;

    function [1:0] slot_next;
        input [1:0] value;
        begin
            slot_next = (value == 2'd2) ? 2'd0 : value + 1'b1;
        end
    endfunction

    function descriptor_shape_valid;
        input [1:0] matrix_mask;
        input [31:0] matrix0_token;
        input [31:0] matrix1_token;
        input [9:0] matrix0_sources;
        input [9:0] matrix1_sources;
        input [5:0] matrix0_tiles;
        input [5:0] matrix1_tiles;
        begin
            descriptor_shape_valid = (matrix_mask != 2'b00) &&
                (matrix_mask[0] ? ((matrix0_token != 0) &&
                 (matrix0_sources >= 1) && (matrix0_sources <= 320) &&
                 (matrix0_tiles >= 1) && (matrix0_tiles <= 20)) :
                 ((matrix0_token == 0) && (matrix0_sources == 0) &&
                  (matrix0_tiles == 0))) &&
                (matrix_mask[1] ? ((matrix1_token != 0) &&
                 (matrix1_sources >= 1) && (matrix1_sources <= 320) &&
                 (matrix1_tiles >= 1) && (matrix1_tiles <= 20)) :
                 ((matrix1_token == 0) && (matrix1_sources == 0) &&
                  (matrix1_tiles == 0)));
        end
    endfunction

    // Keep the 14-bit internal-tag match as three small LUT compares rather
    // than allowing an equality operator to become a carry-chain comparator
    // on the same-edge bank-response fault/admission-fence path.
    function tag_incarnation_equal;
        input [13:0] lhs;
        input [13:0] rhs;
        begin
            tag_incarnation_equal =
                (lhs[5:0] == rhs[5:0]) &&
                (lhs[11:6] == rhs[11:6]) &&
                (lhs[13:12] == rhs[13:12]);
        end
    endfunction

    // Five <=3-bit equality groups fit individual LUT6s and their reduction
    // fits one LUT5.  This is used in response checks and the publication
    // live-fault relocation predicate.
    function equal13_lut_tree;
        input [12:0] lhs;
        input [12:0] rhs;
        begin
            equal13_lut_tree = (lhs[2:0] == rhs[2:0]) &&
                               (lhs[5:3] == rhs[5:3]) &&
                               (lhs[8:6] == rhs[8:6]) &&
                               (lhs[10:9] == rhs[10:9]) &&
                               (lhs[12:11] == rhs[12:11]);
        end
    endfunction

    // Each three-bit equality consumes exactly six LUT inputs.  The six
    // group results then fit one final LUT6, giving a fixed two-level tree
    // and preventing a generic 16-bit comparator/carry chain on the
    // BRAM-to-admission fast-fault path.
    function equal16_lut_tree;
        input [15:0] lhs;
        input [15:0] rhs;
        begin
            equal16_lut_tree = (lhs[2:0] == rhs[2:0]) &&
                               (lhs[5:3] == rhs[5:3]) &&
                               (lhs[8:6] == rhs[8:6]) &&
                               (lhs[11:9] == rhs[11:9]) &&
                               (lhs[13:12] == rhs[13:12]) &&
                               (lhs[15:14] == rhs[15:14]);
        end
    endfunction

    function equal32_lut_tree;
        input [31:0] lhs;
        input [31:0] rhs;
        begin
            equal32_lut_tree = (lhs[5:0] == rhs[5:0]) &&
                               (lhs[11:6] == rhs[11:6]) &&
                               (lhs[17:12] == rhs[17:12]) &&
                               (lhs[23:18] == rhs[23:18]) &&
                               (lhs[29:24] == rhs[29:24]) &&
                               (lhs[31:30] == rhs[31:30]);
        end
    endfunction

    // Exact 0..3 population relation in one five-input truth table.  This is
    // a fatal monitor only; it never participates in data selection.
    function lookup_population_valid;
        input [1:0] count;
        input [2:0] live;
        begin
            case ({count, live})
                5'b00_000,
                5'b01_001, 5'b01_010, 5'b01_100,
                5'b10_011, 5'b10_101, 5'b10_110,
                5'b11_111: lookup_population_valid = 1'b1;
                default:   lookup_population_valid = 1'b0;
            endcase
        end
    endfunction

    function [2:0] slot_onehot;
        input [1:0] slot;
        begin
            case (slot)
                2'd0:    slot_onehot = 3'b001;
                2'd1:    slot_onehot = 3'b010;
                2'd2:    slot_onehot = 3'b100;
                default: slot_onehot = 3'b000;
            endcase
        end
    endfunction

    // Minimal same-edge fatal classifier for one fixed physical directory.
    // This intentionally returns only the admission-fence bit.  The full
    // status/hit/address classifier below remains the sole terminal-response
    // authority.  Generation mismatch and empty entries are normal probe
    // misses but fatal compute misses; current-generation malformed flags and
    // incomplete entries are fatal for either request kind.
    function directory_entry_fast_fatal;
        input [31:0] entry;
        input        generation_match;
        input        compute_kind;
        input [5:0]  row_tile;
        reg [4:0] endpoint_propagate;
        reg [4:0] endpoint_generate;
        reg       endpoint_carry3;
        reg       endpoint_overflow;
        begin
            // A successful acceptance precheck proves row_tile is 0..19.
            // Therefore a 13-bit slot_base can cross 8192 only when its
            // upper eight bits are all one; in that case the carry out of the
            // low five bits is the exact overflow predicate.  The explicit
            // two-level carry look-ahead avoids inference of any arithmetic
            // carry chain on the mandatory BRAM-result-to-same-edge fence.
            endpoint_propagate = entry[4:0] ^ row_tile[4:0];
            endpoint_generate = entry[4:0] & row_tile[4:0];
            endpoint_carry3 = endpoint_generate[2] ||
                (endpoint_propagate[2] && endpoint_generate[1]) ||
                (endpoint_propagate[2] && endpoint_propagate[1] &&
                 endpoint_generate[0]);
            endpoint_overflow = (&entry[12:5]) &&
                (endpoint_generate[4] ||
                 (endpoint_propagate[4] && endpoint_generate[3]) ||
                 (endpoint_propagate[4] && endpoint_propagate[3] &&
                  endpoint_carry3));
            // This classifier is enabled only by a registered bank-local bit
            // created from an accepted, fully prechecked RAM read.  Invalid
            // accepted compute requests are fenced by the independent
            // acceptance classifier and terminalize through the full result
            // classifier, so neither precheck nor read-issued belongs on this
            // BRAM-result timing path.
            // Keep the compute and probe predicates as two local equations.
            // Besides documenting the asymmetric stale/empty semantics, this
            // avoids putting the generation-match result through a shared
            // if/else mux before it reaches the one-bit fatal endpoints.
            directory_entry_fast_fatal = compute_kind ?
                (!generation_match || entry[13] ||
                 !(entry[31] && entry[30]) || endpoint_overflow) :
                (generation_match &&
                 (entry[13] || (entry[31] ^ entry[30])));
        end
    endfunction

    // Publication treats a stale-generation entry as free.  For the current
    // generation, malformed flags/incomplete data or relocation of an already
    // complete key are fatal; exact duplicate publication is nonfatal.
    function publication_entry_fast_fatal;
        input [31:0] entry;
        input [15:0] expected_generation;
        input [12:0] expected_slot_base;
        input        precheck_ok;
        input        read_issued;
        begin
            if (!precheck_ok)
                publication_entry_fast_fatal = 1'b0;
            else if (!read_issued)
                publication_entry_fast_fatal = 1'b1;
            else if (!equal16_lut_tree(entry[29:14],
                                       expected_generation))
                publication_entry_fast_fatal = 1'b0;
            else
                publication_entry_fast_fatal = entry[13] ||
                    (entry[31] ^ entry[30]) ||
                    (entry[31] && entry[30] &&
                     !equal13_lut_tree(entry[12:0], expected_slot_base));
        end
    endfunction

    (* ram_style = "block" *) reg [31:0] directory_mem0 [0:1023];
    (* ram_style = "block" *) reg [31:0] directory_mem1 [0:1023];
    reg [31:0] mem0_read_data_q;
    reg [31:0] mem1_read_data_q;

    reg [2:0]  state_q [0:1];
    reg [1:0]  drain_target_q [0:1];
    reg [15:0] generation_q [0:1];
    reg        generation_initialized_q [0:1];
    reg        descriptor_valid_q [0:1];
    reg        lease_authority_valid_q [0:1];
    reg        content_valid_q [0:1];
    reg        scrub_required_q [0:1];
    reg        last_scrub_epoch_valid_q [0:1];
    reg [31:0] last_scrub_epoch_q [0:1];
    reg [9:0]  committed_count_q [0:1];
    reg        descriptor_install_pending_q [0:1];
    reg        descriptor_install_claim_q [0:1];
    reg [31:0] image_epoch_q [0:1];
    reg [3:0]  stage_id_q [0:1];
    reg [31:0] stage_ticket_q [0:1];
    reg        stage_ticket_clear_pending_q [0:1];
    reg [1:0]  logical_branch_q [0:1];
    reg [31:0] context_generation_q [0:1];
    reg [31:0] content_handle_q [0:1];
    reg [31:0] physical_bank_generation_q [0:1];
    reg [31:0] cancellation_epoch_q [0:1];
    reg [1:0]  matrix_mask_q [0:1];
    reg [31:0] matrix0_binding_token_q [0:1];
    reg [31:0] matrix1_binding_token_q [0:1];
    reg [9:0]  matrix0_source_count_q [0:1];
    reg [9:0]  matrix1_source_count_q [0:1];
    reg [5:0]  matrix0_row_tile_count_q [0:1];
    reg [5:0]  matrix1_row_tile_count_q [0:1];
    reg        begin_drain_rsp_retired_q [0:1];

    reg        local_error_valid_q [0:1];
    reg [7:0]  local_error_code_q [0:1];
    reg [2:0]  local_error_source_q [0:1];
    reg [31:0] local_error_detail_q [0:1];
    reg [15:0] local_error_directory_generation_q [0:1];
    reg [31:0] local_error_physical_bank_generation_q [0:1];
    reg [31:0] local_error_stage_ticket_q [0:1];
    reg [31:0] local_error_content_handle_q [0:1];
    reg        reset_required_q [0:1];
    reg        fault_fence_q [0:1];
    reg        fault_event_pending_q [0:1];

    // Final-close is an immediate narrow authority cut, but its wide local
    // first-error record is installed one edge later.  This registered
    // landing position keeps live directory/bank fault classification out of
    // every bit of the sticky error payload.  A registered rich fault always
    // wins the deferred install on the following edge.
    reg [1:0]  close_local_error_pending_q;
    reg [7:0]  close_local_error_code_q [0:1];
    reg [15:0] close_local_error_directory_generation_q [0:1];
    reg [31:0] close_local_error_physical_bank_generation_q [0:1];
    reg [31:0] close_local_error_stage_ticket_q [0:1];
    reg [31:0] close_local_error_content_handle_q [0:1];

    // One management operation/response position.
    reg        mgmt_active_q;
    reg [3:0]  mgmt_active_opcode_q;
    reg [1:0]  mgmt_active_bank_mask_q;
    reg [31:0] mgmt_active_image_epoch_q;
    reg [15:0] mgmt_active_tag_q;
    reg [9:0]  scrub_address_q;

    // A clean-static SCRUB acceptance first occupies this non-authoritative
    // candidate position.  The selected bank identity and request payload
    // live in the immutable management preview registers above.  Only the
    // one-bit/one-mask evidence below is sampled from the live fail-closed
    // classifier; lifecycle authority is granted on the following edge from
    // registered evidence.  The candidate may issue the harmless address-zero
    // scrub write, but cannot publish state or epoch authority by itself.
    reg        scrub_candidate_valid_q;
    reg [1:0]  scrub_candidate_initial_fault_q;

    // One-cycle management execution position.  Admission captures the
    // complete command and acceptance-edge quiescence evidence; mutation and
    // terminal response are produced together on a later execution edge.
    reg        mgmt_exec_valid_q;
    reg [3:0]  mgmt_exec_opcode_q;
    reg [1:0]  mgmt_exec_bank_mask_q;
    reg [1:0]  mgmt_exec_drain_target_q;
    reg [15:0] mgmt_exec_expected_directory_generation_q;
    reg [31:0] mgmt_exec_expected_content_handle_q;
    reg [31:0] mgmt_exec_expected_stage_ticket_q;
    reg [31:0] mgmt_exec_expected_physical_bank_generation_q;
    reg [31:0] mgmt_exec_new_image_epoch_q;
    reg [3:0]  mgmt_exec_new_stage_id_q;
    reg [31:0] mgmt_exec_new_stage_ticket_q;
    reg [1:0]  mgmt_exec_new_logical_branch_q;
    reg [31:0] mgmt_exec_new_context_generation_q;
    reg [31:0] mgmt_exec_new_content_handle_q;
    reg [31:0] mgmt_exec_new_physical_bank_generation_q;
    reg [31:0] mgmt_exec_new_cancellation_epoch_q;
    reg [1:0]  mgmt_exec_new_matrix_mask_q;
    reg [31:0] mgmt_exec_new_matrix0_binding_token_q;
    reg [31:0] mgmt_exec_new_matrix1_binding_token_q;
    reg [9:0]  mgmt_exec_new_matrix0_source_count_q;
    reg [9:0]  mgmt_exec_new_matrix1_source_count_q;
    reg [5:0]  mgmt_exec_new_matrix0_row_tile_count_q;
    reg [5:0]  mgmt_exec_new_matrix1_row_tile_count_q;
    reg        mgmt_exec_external_safe_q;
    reg [15:0] mgmt_exec_tag_q;
    reg [1:0]  mgmt_exec_accept_causal_empty_q;
    reg [1:0]  mgmt_exec_accept_drain_complete_q;
    reg [1:0]  mgmt_exec_fault_collision_q;
    reg        mgmt_decision_valid_q;
    reg [7:0]  mgmt_decision_status_q;
    reg [2:0]  mgmt_decision_new_state_q;
    reg [15:0] mgmt_decision_new_generation_q;
    reg        mgmt_decision_mutating_q;

    reg        mgmt_rsp_valid_q;
    reg [3:0]  mgmt_rsp_opcode_q;
    reg [1:0]  mgmt_rsp_bank_mask_q;
    reg [5:0]  mgmt_rsp_state_q;
    reg [15:0] mgmt_rsp_tag_q;
    reg [7:0]  mgmt_rsp_status_q;
    reg        mgmt_rsp_mutating_q;

    // One final-close overlay and one terminal response position.
    reg        close_pending_q;
    reg [1:0]  close_bank_mask_q;
    reg [7:0]  close_code_q [0:1];
    reg [15:0] close_tag_q;
    reg        force_rsp_valid_q;
    reg [1:0]  force_rsp_bank_mask_q;
    reg [7:0]  force_rsp_code_q;
    reg [5:0]  force_rsp_state_q;
    reg [31:0] force_rsp_generation_q;
    reg [1:0]  force_rsp_reset_required_q;
    reg [15:0] force_rsp_tag_q;
    reg [7:0]  force_rsp_status_q;

    // One publication execution position and one held terminal response.
    reg        pub_exec_valid_q;
    reg        pub_exec_read_issued_q;
    reg [7:0]  pub_exec_pre_status_q;
    reg        pub_exec_bank_q;
    reg [31:0] pub_exec_image_epoch_q;
    reg [3:0]  pub_exec_stage_id_q;
    reg [31:0] pub_exec_stage_ticket_q;
    reg [1:0]  pub_exec_logical_branch_q;
    reg [31:0] pub_exec_context_generation_q;
    reg [31:0] pub_exec_matrix_binding_token_q;
    reg [31:0] pub_exec_content_handle_q;
    reg [31:0] pub_exec_physical_bank_generation_q;
    reg [15:0] pub_exec_directory_generation_q;
    reg [31:0] pub_exec_cancellation_epoch_q;
    reg        pub_exec_matrix_id_q;
    reg [9:0]  pub_exec_source_index_q;
    reg [12:0] pub_exec_slot_base_q;
    reg [9:0]  pub_exec_source_count_q;
    reg [5:0]  pub_exec_row_tile_count_q;
    reg [1:0]  pub_exec_matrix_mask_q;
    reg [15:0] pub_exec_tag_q;
    reg        pub_rsp_valid_q;
    reg        pub_rsp_bank_q;
    reg        pub_rsp_matrix_id_q;
    reg [9:0]  pub_rsp_source_index_q;
    reg [12:0] pub_rsp_slot_base_q;
    reg [15:0] pub_rsp_directory_generation_q;
    reg        pub_rsp_committed_q;
    reg [9:0]  pub_rsp_committed_count_q;
    reg [15:0] pub_rsp_tag_q;
    reg [7:0]  pub_rsp_status_q;

    // Three ordered logical lookup records.  Data is held only in the final
    // output register; younger bank data remains in the selected bank.
    reg [2:0]  slot_state_q [0:2];
    reg [13:0] slot_incarnation_q [0:2];
    reg        slot_kind_q [0:2];
    reg [31:0] slot_image_epoch_q [0:2];
    reg [3:0]  slot_stage_id_q [0:2];
    reg [31:0] slot_stage_ticket_q [0:2];
    reg [1:0]  slot_logical_branch_q [0:2];
    reg [31:0] slot_context_generation_q [0:2];
    reg        slot_matrix_id_q [0:2];
    reg [9:0]  slot_source_index_q [0:2];
    reg [5:0]  slot_row_tile_q [0:2];
    reg [31:0] slot_matrix_binding_token_q [0:2];
    reg [31:0] slot_cancellation_epoch_q [0:2];
    reg        slot_causal_continuation_q [0:2];
    reg [15:0] slot_user_tag_q [0:2];
    reg        slot_bank_q [0:2];
    reg [31:0] slot_physical_bank_generation_q [0:2];
    reg [31:0] slot_content_handle_q [0:2];
    reg [15:0] slot_directory_generation_q [0:2];
    reg [12:0] slot_slot_base_q [0:2];
    reg [12:0] slot_weight_addr_q [0:2];
    reg [7:0]  slot_pre_status_q [0:2];
    reg [7:0]  slot_status_q [0:2];
    reg        slot_hit_q [0:2];
    reg        slot_fatal_q [0:2];

    reg [1:0] lookup_head_q;
    reg [1:0] lookup_tail_q;
    reg [1:0] lookup_count_q;
    reg [1:0] bank0_ref_count_q;
    reg [1:0] bank1_ref_count_q;
    reg       dir_pipe_valid_q;
    reg       dir_pipe_read_issued_q;
    reg [1:0] dir_pipe_slot_q;
    reg [2:0] dir_pipe_owner_onehot_q;
    // Fixed-index metadata is captured with the RAM request and is used only
    // by the shallow same-edge fault fence.  It removes the order-slot dynamic
    // mux from the BRAM-to-admission path without adding a pipeline cycle.
    reg [1:0] dir_pipe_fast_active_q;
    reg       dir_pipe_fast_kind_q;
    reg [15:0] dir_pipe_fast_generation_q;
    reg [5:0] dir_pipe_fast_row_tile_q;

    // Two response positions per physical bank mirror the accepted bank
    // primitive's two local response credits.  These are correlation
    // bookkeeping, not additional logical lookup credits.
    reg [1:0] bank0_expect_count_q;
    reg [1:0] bank1_expect_count_q;
    reg       bank0_expect_head_q;
    reg       bank0_expect_tail_q;
    reg       bank1_expect_head_q;
    reg       bank1_expect_tail_q;
    (* shreg_extract = "no", ram_style = "registers" *)
    reg [1:0] bank0_expect_slot_q [0:1];
    (* shreg_extract = "no", ram_style = "registers" *)
    reg [1:0] bank1_expect_slot_q [0:1];
    (* shreg_extract = "no", ram_style = "registers" *)
    reg [15:0] bank0_expect_tag_q [0:1];
    (* shreg_extract = "no", ram_style = "registers" *)
    reg [15:0] bank1_expect_tag_q [0:1];
    (* shreg_extract = "no", ram_style = "registers" *)
    reg [12:0] bank0_expect_addr_q [0:1];
    (* shreg_extract = "no", ram_style = "registers" *)
    reg [12:0] bank1_expect_addr_q [0:1];
    (* shreg_extract = "no", ram_style = "registers" *)
    reg [31:0] bank0_expect_generation_q [0:1];
    (* shreg_extract = "no", ram_style = "registers" *)
    reg [31:0] bank1_expect_generation_q [0:1];
    (* shreg_extract = "no", ram_style = "registers" *)
    reg [31:0] bank0_expect_ticket_q [0:1];
    (* shreg_extract = "no", ram_style = "registers" *)
    reg [31:0] bank1_expect_ticket_q [0:1];

    reg        lookup_out_valid_q;
    reg [2:0]  lookup_out_owner_onehot_q;
    reg        lookup_out_kind_q;
    reg [31:0] lookup_out_image_epoch_q;
    reg [3:0]  lookup_out_stage_id_q;
    reg [31:0] lookup_out_stage_ticket_q;
    reg [1:0]  lookup_out_logical_branch_q;
    reg [31:0] lookup_out_context_generation_q;
    reg        lookup_out_matrix_id_q;
    reg [9:0]  lookup_out_source_index_q;
    reg [5:0]  lookup_out_row_tile_q;
    reg [31:0] lookup_out_matrix_binding_token_q;
    reg [31:0] lookup_out_cancellation_epoch_q;
    reg        lookup_out_causal_continuation_q;
    reg        lookup_out_bank_q;
    reg [31:0] lookup_out_physical_bank_generation_q;
    reg [31:0] lookup_out_content_handle_q;
    reg [15:0] lookup_out_directory_generation_q;
    reg [12:0] lookup_out_slot_base_q;
    reg [12:0] lookup_out_weight_addr_q;
    reg        lookup_out_hit_q;
    reg [127:0] lookup_out_weight_data_q;
    reg [15:0] lookup_out_user_tag_q;
    reg [7:0]  lookup_out_status_q;
    reg        lookup_out_fatal_q;

    integer i;

    // Combinational controls and classifications are declared below the
    // architectural storage so synthesis keeps payload RAM inference simple.
    reg [7:0] lookup_pre_status;
    reg       lookup_pre_read;
    reg [7:0] dir_result_status;
    reg       dir_result_hit;
    reg       dir_result_fatal;
    reg [12:0] dir_result_slot_base;
    reg [12:0] dir_result_weight_addr;
    reg       dir_result_bank_pending;
    reg [31:0] dir_result_entry;
    reg [13:0] dir_result_sum;
    reg [7:0] publish_pre_status;
    reg [7:0] publish_result_status;
    reg       publish_result_committed;
    reg       publish_result_fatal;
    reg [31:0] publish_result_entry;
    reg [13:0] publish_endpoint;
    reg [2:0] issue_onehot;
    reg [1:0] response_slot;
    reg       response_slot_valid;
    reg [7:0] bank_response_status;
    reg       bank_response_fatal;
    reg [127:0] bank_response_data;
    reg [7:0] bank0_rsp_observed_status;
    reg [7:0] bank1_rsp_observed_status;
    reg       bank0_rsp_observed_fatal;
    reg       bank1_rsp_observed_fatal;
    reg       bank0_rsp_observed_reset;
    reg       bank1_rsp_observed_reset;
    reg [7:0] scrub_direct_status;
    reg [7:0] mgmt_status_d;
    reg [2:0] mgmt_new_state_d;
    reg [15:0] mgmt_new_generation_d;
    reg       mgmt_is_mutating_d;
    reg [1:0] mgmt_effective_mask;
    reg       force_request_exact;
    reg [7:0] force_request_status;
    reg [1:0] fault_now;
    reg [7:0] fault_code_now [0:1];
    reg [2:0] fault_source_now [0:1];
    reg [31:0] fault_detail_now [0:1];
    reg       fault_reset_now [0:1];
    // Source-local first stage.  Only one-bit event flags depend on live
    // classifiers.  Rich status/detail and authority scope are sampled into
    // independent registers, then merged on the following cycle.  This keeps
    // a directory BRAM result out of the global rich-priority mux endpoint.
    reg [5:0] fault_source_flags_q [0:1];
    reg [7:0] fault_bank_status_snapshot_q [0:1];
    reg       fault_bank_reset_snapshot_q [0:1];
    reg [15:0] fault_bank_tag_snapshot_q [0:1];
    reg [7:0] fault_dir_status_snapshot_q;
    reg [31:0] fault_dir_detail_snapshot_q;
    reg [7:0] fault_pub_status_snapshot_q;
    reg [31:0] fault_pub_detail_snapshot_q;
    reg [7:0] fault_lookup_status_snapshot_q;
    reg [31:0] fault_lookup_detail_snapshot_q;
    reg [15:0] fault_scope_directory_generation_q [0:1];
    reg [31:0] fault_scope_physical_bank_generation_q [0:1];
    reg [31:0] fault_scope_stage_ticket_q [0:1];
    reg [31:0] fault_scope_content_handle_q [0:1];
    // A live physical fault must fence the affected bank on the detection
    // edge, while the richer first-error record is deliberately registered
    // one stage later.  This narrow bridge carries that authority across the
    // staging interval without routing a BRAM result through the lifecycle
    // and error-state priority muxes.
    reg [1:0] fast_fault_bridge_q;
    wire [1:0] owned_close_fault_now;
    reg [7:0] owned_close_fault_code [0:1];

    wire lookup_rsp_fire;
    wire lookup_out_can_take;
    wire lookup_req_fire;
    wire publish_req_fire;
    wire publish_rsp_fire;
    wire mgmt_req_fire;
    wire mgmt_rsp_fire;
    wire force_error_fire;
    wire force_rsp_fire;
    wire [1:0] effective_response_slot;
    wire bank0_rsp_fire;
    wire bank1_rsp_fire;
    wire bank0_req_fire;
    wire bank1_req_fire;
    wire expected_bank_rsp_fire;
    wire bank_response_close_selected;
    wire bank_response_close_fault_override;
    wire [7:0] bank_response_terminal_status;
    wire bank_response_terminal_fatal;
    wire [127:0] bank_response_terminal_data;
    wire response_bank_id;
    wire [7:0] response_close_code;
    wire response_close_fatal;
    wire [7:0] publication_close_code;
    wire [7:0] bank0_close_code;
    wire [7:0] bank1_close_code;
    wire bank_req_fire;
    wire direct_result_issue;
    wire issue_valid;
    wire [1:0] physical_issue_slot;
    wire [2:0] direct_issue_onehot_w;
    wire [2:0] physical_issue_onehot_w;
    wire [2:0] direct_payload_onehot_w;
    wire [2:0] physical_payload_onehot_w;
    wire [2:0] bank0_issue_onehot_w;
    wire [2:0] bank1_issue_onehot_w;
    wire [2:0] bank0_payload_onehot_w;
    wire [2:0] bank1_payload_onehot_w;
    wire [12:0] slot0_issue_addr_w;
    wire [12:0] slot1_issue_addr_w;
    wire [12:0] slot2_issue_addr_w;
    wire pub_commit_now;
    wire [9:0] pub_key;
    wire [9:0] lookup_key;
    wire [31:0] pub_new_entry;
    wire [1:0] management_fence_w;
    wire [1:0] close_fence_w;
    wire [1:0] sticky_fault_fence_w;
    wire [1:0] current_fault_fence_w;
    wire [1:0] bank_ref_count_w;
    wire [1:0] bank_pending_count_w;
    wire [1:0] bank_wait_count_w;
    wire [1:0] bank0_ref_count_w;
    wire [1:0] bank1_ref_count_w;
    wire [1:0] bank0_pending_count_w;
    wire [1:0] bank1_pending_count_w;
    wire [1:0] bank0_wait_count_w;
    wire [1:0] bank1_wait_count_w;
    wire [1:0] bank_causal_empty_w;
    wire [1:0] bank_work_empty_w;
    wire [1:0] bank_quiescent_w;
    wire internal_order_fault;
    wire force_cut_bank0;
    wire force_cut_bank1;
    wire close_complete;
    wire [1:0] next_lookup_head;
    wire [1:0] response_second_slot;
    wire [1:0] response_third_slot;
    (* keep = "true" *) wire [1:0] preexisting_fence_now;
    wire [13:0] new_slot_incarnation;
    wire lookup_credit_claim;
    wire lookup_state_claim;
    wire lookup_admission_claim;
    wire lookup_port_claim;
    wire lookup_port_claim0;
    wire lookup_port_claim1;
    wire publish_port_claim;
    wire publish_admission_claim;
    wire publish_port_claim0;
    wire publish_port_claim1;
    wire ram_write_owner0;
    wire ram_write_owner1;
    wire [2:0] slot_live_w;
    wire [2:0] dir_wait_mask_w;
    wire [2:0] bank_ref_count_sum_w;
    wire [2:0] bank0_wait_slot_mask_w;
    wire [2:0] bank1_wait_slot_mask_w;
    wire [2:0] bank0_expect_slot_mask_w;
    wire [2:0] bank1_expect_slot_mask_w;
    wire slot_population_fault_w;
    wire bank_ref_count_fault_w;
    wire bank_expect_owner_fault_w;
    wire dir_pipe_owner_fault_w;
    wire lookup_output_owner_fault_w;
    wire bank0_rsp_fence_now_w;
    wire bank1_rsp_fence_now_w;
    wire [5:0] dir_fast_gen_equal0_w;
    wire [5:0] dir_fast_gen_equal1_w;
    wire dir_fast_generation_match0_w;
    wire dir_fast_generation_match1_w;
    wire dir_fast_fatal0_w;
    wire dir_fast_fatal1_w;
    wire pub_fast_fatal0_w;
    wire pub_fast_fatal1_w;
    wire dir_result_physical_fatal_w;
    wire [1:0] fast_fault_now_w;
    wire [1:0] mgmt_late_fault_now_w;
    wire scrub_live_veto_w;
    wire [5:0] fault_live_sources0_w;
    wire [5:0] fault_live_sources1_w;
    wire fault_live_reset0_w;
    wire fault_live_reset1_w;
    wire bank0_expect_can_push_w;
    wire bank1_expect_can_push_w;
    wire [1:0] bank0_expect_head_slot_w;
    wire [1:0] bank1_expect_head_slot_w;
    wire [15:0] bank0_expect_head_tag_w;
    wire [15:0] bank1_expect_head_tag_w;
    wire [12:0] bank0_expect_head_addr_w;
    wire [12:0] bank1_expect_head_addr_w;
    wire [31:0] bank0_expect_head_generation_w;
    wire [31:0] bank1_expect_head_generation_w;
    wire [31:0] bank0_expect_head_ticket_w;
    wire [31:0] bank1_expect_head_ticket_w;
    wire [7:0] first_fault_code0_w;
    wire [7:0] first_fault_code1_w;
    wire bank0_close_fatal_w;
    wire bank1_close_fatal_w;
    wire [1:0] fault_stage_valid_w;
    wire fault_event_candidate0_w;
    wire fault_event_candidate1_w;
    wire fault_event_from_pending0_w;
    wire fault_event_from_pending1_w;
    wire fault_event_fire_w;
    wire mgmt_raw_priority_available_w;
    wire mgmt_preview_capture_w;
    wire mgmt_activation_opcode_w;
    wire mgmt_activation_target0_w;
    wire mgmt_activation_target1_w;
    (* keep = "true" *) wire mgmt_ready_without_preexisting_w;
    wire mgmt_preexisting_activation_fence_w;
    wire scrub_candidate_accept_w;
    (* keep = "true" *) wire lookup_ready_without_preexisting_w;
    wire lookup_preexisting_fence_selected_w;
    (* keep = "true" *) wire publish_ready_without_preexisting_w;
    wire publish_preexisting_fence_selected_w;
    wire lookup_accept_fault_candidate_w;
    wire mgmt_generation_fault_candidate_w;
    wire [9:0] effective_committed_count0_w;
    wire [9:0] effective_committed_count1_w;
    wire [15:0] effective_generation0_w;
    wire [15:0] effective_generation1_w;
    wire [31:0] effective_image_epoch0_w;
    wire [31:0] effective_image_epoch1_w;
    wire [3:0] effective_stage_id0_w;
    wire [3:0] effective_stage_id1_w;
    wire [31:0] effective_stage_ticket0_w;
    wire [31:0] effective_stage_ticket1_w;
    wire [1:0] effective_logical_branch0_w;
    wire [1:0] effective_logical_branch1_w;
    wire [31:0] effective_context_generation0_w;
    wire [31:0] effective_context_generation1_w;
    wire [31:0] effective_content_handle0_w;
    wire [31:0] effective_content_handle1_w;
    wire [31:0] effective_physical_bank_generation0_w;
    wire [31:0] effective_physical_bank_generation1_w;
    wire [31:0] effective_cancellation_epoch0_w;
    wire [31:0] effective_cancellation_epoch1_w;
    wire [1:0] effective_matrix_mask0_w;
    wire [1:0] effective_matrix_mask1_w;
    wire [31:0] effective_matrix0_binding_token0_w;
    wire [31:0] effective_matrix0_binding_token1_w;
    wire [31:0] effective_matrix1_binding_token0_w;
    wire [31:0] effective_matrix1_binding_token1_w;
    wire [9:0] effective_matrix0_source_count0_w;
    wire [9:0] effective_matrix0_source_count1_w;
    wire [9:0] effective_matrix1_source_count0_w;
    wire [9:0] effective_matrix1_source_count1_w;
    wire [5:0] effective_matrix0_row_tile_count0_w;
    wire [5:0] effective_matrix0_row_tile_count1_w;
    wire [5:0] effective_matrix1_row_tile_count0_w;
    wire [5:0] effective_matrix1_row_tile_count1_w;
    wire [15:0] mgmt_current_generation_w;
    wire [31:0] mgmt_current_image_epoch_w;
    wire [3:0] mgmt_current_stage_id_w;
    wire [31:0] mgmt_current_stage_ticket_w;
    wire [1:0] mgmt_current_logical_branch_w;
    wire [31:0] mgmt_current_content_handle_w;
    wire [31:0] mgmt_current_physical_bank_generation_w;
    wire [1:0] mgmt_current_matrix_mask_w;
    wire [9:0] mgmt_current_matrix0_source_count_w;
    wire [9:0] mgmt_current_matrix1_source_count_w;
    wire [5:0] mgmt_current_matrix0_row_tile_count_w;
    wire [5:0] mgmt_current_matrix1_row_tile_count_w;

    // A successful CLAIM/REBIND publishes an architectural descriptor through
    // this registered install overlay.  The wide physical copy follows on the
    // next edge, so live fault classification never drives the clock-enable of
    // the descriptor payload flops.  CLAIM-only fields retain their old value
    // for REBIND, exactly as required by retained-content authority.
    assign effective_committed_count0_w =
        (descriptor_install_pending_q[0] && descriptor_install_claim_q[0]) ?
        10'd0 : committed_count_q[0];
    assign effective_committed_count1_w =
        (descriptor_install_pending_q[1] && descriptor_install_claim_q[1]) ?
        10'd0 : committed_count_q[1];
    assign effective_generation0_w =
        (descriptor_install_pending_q[0] && descriptor_install_claim_q[0]) ?
        mgmt_decision_new_generation_q : generation_q[0];
    assign effective_generation1_w =
        (descriptor_install_pending_q[1] && descriptor_install_claim_q[1]) ?
        mgmt_decision_new_generation_q : generation_q[1];
    assign effective_image_epoch0_w = descriptor_install_pending_q[0] ?
        mgmt_exec_new_image_epoch_q : image_epoch_q[0];
    assign effective_image_epoch1_w = descriptor_install_pending_q[1] ?
        mgmt_exec_new_image_epoch_q : image_epoch_q[1];
    assign effective_stage_id0_w = descriptor_install_pending_q[0] ?
        mgmt_exec_new_stage_id_q : stage_id_q[0];
    assign effective_stage_id1_w = descriptor_install_pending_q[1] ?
        mgmt_exec_new_stage_id_q : stage_id_q[1];
    assign effective_stage_ticket0_w =
        descriptor_install_pending_q[0] ? mgmt_exec_new_stage_ticket_q :
        (stage_ticket_clear_pending_q[0] ? 32'd0 : stage_ticket_q[0]);
    assign effective_stage_ticket1_w =
        descriptor_install_pending_q[1] ? mgmt_exec_new_stage_ticket_q :
        (stage_ticket_clear_pending_q[1] ? 32'd0 : stage_ticket_q[1]);
    assign effective_logical_branch0_w = descriptor_install_pending_q[0] ?
        mgmt_exec_new_logical_branch_q : logical_branch_q[0];
    assign effective_logical_branch1_w = descriptor_install_pending_q[1] ?
        mgmt_exec_new_logical_branch_q : logical_branch_q[1];
    assign effective_context_generation0_w =
        descriptor_install_pending_q[0] ?
        mgmt_exec_new_context_generation_q : context_generation_q[0];
    assign effective_context_generation1_w =
        descriptor_install_pending_q[1] ?
        mgmt_exec_new_context_generation_q : context_generation_q[1];
    assign effective_content_handle0_w =
        (descriptor_install_pending_q[0] && descriptor_install_claim_q[0]) ?
        mgmt_exec_new_content_handle_q : content_handle_q[0];
    assign effective_content_handle1_w =
        (descriptor_install_pending_q[1] && descriptor_install_claim_q[1]) ?
        mgmt_exec_new_content_handle_q : content_handle_q[1];
    assign effective_physical_bank_generation0_w =
        descriptor_install_pending_q[0] ?
        mgmt_exec_new_physical_bank_generation_q :
        physical_bank_generation_q[0];
    assign effective_physical_bank_generation1_w =
        descriptor_install_pending_q[1] ?
        mgmt_exec_new_physical_bank_generation_q :
        physical_bank_generation_q[1];
    assign effective_cancellation_epoch0_w =
        descriptor_install_pending_q[0] ?
        mgmt_exec_new_cancellation_epoch_q : cancellation_epoch_q[0];
    assign effective_cancellation_epoch1_w =
        descriptor_install_pending_q[1] ?
        mgmt_exec_new_cancellation_epoch_q : cancellation_epoch_q[1];
    assign effective_matrix_mask0_w =
        (descriptor_install_pending_q[0] && descriptor_install_claim_q[0]) ?
        mgmt_exec_new_matrix_mask_q : matrix_mask_q[0];
    assign effective_matrix_mask1_w =
        (descriptor_install_pending_q[1] && descriptor_install_claim_q[1]) ?
        mgmt_exec_new_matrix_mask_q : matrix_mask_q[1];
    assign effective_matrix0_binding_token0_w =
        descriptor_install_pending_q[0] ?
        mgmt_exec_new_matrix0_binding_token_q : matrix0_binding_token_q[0];
    assign effective_matrix0_binding_token1_w =
        descriptor_install_pending_q[1] ?
        mgmt_exec_new_matrix0_binding_token_q : matrix0_binding_token_q[1];
    assign effective_matrix1_binding_token0_w =
        descriptor_install_pending_q[0] ?
        mgmt_exec_new_matrix1_binding_token_q : matrix1_binding_token_q[0];
    assign effective_matrix1_binding_token1_w =
        descriptor_install_pending_q[1] ?
        mgmt_exec_new_matrix1_binding_token_q : matrix1_binding_token_q[1];
    assign effective_matrix0_source_count0_w =
        (descriptor_install_pending_q[0] && descriptor_install_claim_q[0]) ?
        mgmt_exec_new_matrix0_source_count_q : matrix0_source_count_q[0];
    assign effective_matrix0_source_count1_w =
        (descriptor_install_pending_q[1] && descriptor_install_claim_q[1]) ?
        mgmt_exec_new_matrix0_source_count_q : matrix0_source_count_q[1];
    assign effective_matrix1_source_count0_w =
        (descriptor_install_pending_q[0] && descriptor_install_claim_q[0]) ?
        mgmt_exec_new_matrix1_source_count_q : matrix1_source_count_q[0];
    assign effective_matrix1_source_count1_w =
        (descriptor_install_pending_q[1] && descriptor_install_claim_q[1]) ?
        mgmt_exec_new_matrix1_source_count_q : matrix1_source_count_q[1];
    assign effective_matrix0_row_tile_count0_w =
        (descriptor_install_pending_q[0] && descriptor_install_claim_q[0]) ?
        mgmt_exec_new_matrix0_row_tile_count_q : matrix0_row_tile_count_q[0];
    assign effective_matrix0_row_tile_count1_w =
        (descriptor_install_pending_q[1] && descriptor_install_claim_q[1]) ?
        mgmt_exec_new_matrix0_row_tile_count_q : matrix0_row_tile_count_q[1];
    assign effective_matrix1_row_tile_count0_w =
        (descriptor_install_pending_q[0] && descriptor_install_claim_q[0]) ?
        mgmt_exec_new_matrix1_row_tile_count_q : matrix1_row_tile_count_q[0];
    assign effective_matrix1_row_tile_count1_w =
        (descriptor_install_pending_q[1] && descriptor_install_claim_q[1]) ?
        mgmt_exec_new_matrix1_row_tile_count_q : matrix1_row_tile_count_q[1];
    // Once present, the sticky first-error record remains the sole rich error
    // authority.  A later stage may carry only a reset escalation and must not
    // replace that first code in management/close reporting.
    assign first_fault_code0_w = local_error_valid_q[0] ?
        local_error_code_q[0] :
        (fault_now[0] ? fault_code_now[0] :
         (close_local_error_pending_q[0] ?
          close_local_error_code_q[0] : STATUS_OK));
    assign first_fault_code1_w = local_error_valid_q[1] ?
        local_error_code_q[1] :
        (fault_now[1] ? fault_code_now[1] :
         (close_local_error_pending_q[1] ?
          close_local_error_code_q[1] : STATUS_OK));
    assign fault_stage_valid_w = fault_now;

    // One-bank management commands use a captured one-hot mask.  These
    // aliases keep every current-identity check on the same architectural
    // descriptor view while the physical install is pending.
    assign mgmt_current_generation_w = mgmt_exec_bank_mask_q[0] ?
        effective_generation0_w : effective_generation1_w;
    assign mgmt_current_image_epoch_w = mgmt_exec_bank_mask_q[0] ?
        effective_image_epoch0_w : effective_image_epoch1_w;
    assign mgmt_current_stage_id_w = mgmt_exec_bank_mask_q[0] ?
        effective_stage_id0_w : effective_stage_id1_w;
    assign mgmt_current_stage_ticket_w = mgmt_exec_bank_mask_q[0] ?
        effective_stage_ticket0_w : effective_stage_ticket1_w;
    assign mgmt_current_logical_branch_w = mgmt_exec_bank_mask_q[0] ?
        effective_logical_branch0_w : effective_logical_branch1_w;
    assign mgmt_current_content_handle_w = mgmt_exec_bank_mask_q[0] ?
        effective_content_handle0_w : effective_content_handle1_w;
    assign mgmt_current_physical_bank_generation_w =
        mgmt_exec_bank_mask_q[0] ? effective_physical_bank_generation0_w :
                                   effective_physical_bank_generation1_w;
    assign mgmt_current_matrix_mask_w = mgmt_exec_bank_mask_q[0] ?
        effective_matrix_mask0_w : effective_matrix_mask1_w;
    assign mgmt_current_matrix0_source_count_w = mgmt_exec_bank_mask_q[0] ?
        effective_matrix0_source_count0_w : effective_matrix0_source_count1_w;
    assign mgmt_current_matrix1_source_count_w = mgmt_exec_bank_mask_q[0] ?
        effective_matrix1_source_count0_w : effective_matrix1_source_count1_w;
    assign mgmt_current_matrix0_row_tile_count_w =
        mgmt_exec_bank_mask_q[0] ? effective_matrix0_row_tile_count0_w :
                                   effective_matrix0_row_tile_count1_w;
    assign mgmt_current_matrix1_row_tile_count_w =
        mgmt_exec_bank_mask_q[0] ? effective_matrix1_row_tile_count0_w :
                                   effective_matrix1_row_tile_count1_w;

    // Packed status/descriptor outputs.
    assign directory_state = {state_q[1], state_q[0]};
    assign directory_generation =
        {effective_generation1_w, effective_generation0_w};
    assign directory_generation_initialized =
        {generation_initialized_q[1], generation_initialized_q[0]};
    assign directory_descriptor_valid =
        {descriptor_valid_q[1], descriptor_valid_q[0]};
    assign directory_lease_authority_valid =
        {lease_authority_valid_q[1], lease_authority_valid_q[0]};
    assign directory_content_valid = {content_valid_q[1], content_valid_q[0]};
    assign directory_scrub_required =
        {scrub_required_q[1], scrub_required_q[0]};
    assign directory_scrub_busy =
        {(state_q[1] == ST_SCRUBBING) ||
         (scrub_candidate_valid_q && mgmt_active_bank_mask_q[1]),
         (state_q[0] == ST_SCRUBBING) ||
         (scrub_candidate_valid_q && mgmt_active_bank_mask_q[0])};
    assign directory_scrub_address = {scrub_address_q, scrub_address_q};
    assign directory_last_scrubbed_image_epoch_valid =
        {last_scrub_epoch_valid_q[1], last_scrub_epoch_valid_q[0]};
    assign directory_last_scrubbed_image_epoch =
        {last_scrub_epoch_q[1], last_scrub_epoch_q[0]};
    assign directory_committed_source_count =
        {effective_committed_count1_w, effective_committed_count0_w};
    assign directory_image_epoch =
        {effective_image_epoch1_w, effective_image_epoch0_w};
    assign directory_stage_id =
        {effective_stage_id1_w, effective_stage_id0_w};
    assign directory_stage_ticket =
        {effective_stage_ticket1_w, effective_stage_ticket0_w};
    assign directory_logical_branch =
        {effective_logical_branch1_w, effective_logical_branch0_w};
    assign directory_context_generation =
        {effective_context_generation1_w, effective_context_generation0_w};
    assign directory_content_handle =
        {effective_content_handle1_w, effective_content_handle0_w};
    assign directory_physical_bank_generation =
        {effective_physical_bank_generation1_w,
         effective_physical_bank_generation0_w};
    assign directory_cancellation_epoch =
        {effective_cancellation_epoch1_w, effective_cancellation_epoch0_w};
    assign directory_matrix_mask =
        {effective_matrix_mask1_w, effective_matrix_mask0_w};
    assign directory_matrix0_binding_token =
        {effective_matrix0_binding_token1_w,
         effective_matrix0_binding_token0_w};
    assign directory_matrix1_binding_token =
        {effective_matrix1_binding_token1_w,
         effective_matrix1_binding_token0_w};
    assign directory_matrix0_source_count =
        {effective_matrix0_source_count1_w,
         effective_matrix0_source_count0_w};
    assign directory_matrix1_source_count =
        {effective_matrix1_source_count1_w,
         effective_matrix1_source_count0_w};
    assign directory_matrix0_row_tile_count =
        {effective_matrix0_row_tile_count1_w,
         effective_matrix0_row_tile_count0_w};
    assign directory_matrix1_row_tile_count =
        {effective_matrix1_row_tile_count1_w,
         effective_matrix1_row_tile_count0_w};

    assign local_error_valid =
        {local_error_valid_q[1] || fault_now[1] ||
         close_local_error_pending_q[1],
         local_error_valid_q[0] || fault_now[0] ||
         close_local_error_pending_q[0]};
    // The valid bits are the authority for the first-error payload.  Masking
    // invalid payloads at the boundary preserves the specified reset/clear
    // value while allowing CLEAR_ERROR to retire authority without routing
    // its rich identity/quiescence decode to hundreds of payload reset pins.
    assign local_error_code =
        {local_error_valid_q[1] ? local_error_code_q[1] :
         (fault_now[1] ? fault_code_now[1] :
          (close_local_error_pending_q[1] ?
           close_local_error_code_q[1] : 8'd0)),
         local_error_valid_q[0] ? local_error_code_q[0] :
         (fault_now[0] ? fault_code_now[0] :
          (close_local_error_pending_q[0] ?
           close_local_error_code_q[0] : 8'd0))};
    assign local_error_source =
        {local_error_valid_q[1] ? local_error_source_q[1] :
         (fault_now[1] ? fault_source_now[1] :
          (close_local_error_pending_q[1] ?
           ERROR_SOURCE_FINAL_CLOSE : 3'd0)),
         local_error_valid_q[0] ? local_error_source_q[0] :
         (fault_now[0] ? fault_source_now[0] :
          (close_local_error_pending_q[0] ?
           ERROR_SOURCE_FINAL_CLOSE : 3'd0))};
    assign local_error_detail =
        {local_error_valid_q[1] ? local_error_detail_q[1] :
         (fault_now[1] ? fault_detail_now[1] : 32'd0),
         local_error_valid_q[0] ? local_error_detail_q[0] :
         (fault_now[0] ? fault_detail_now[0] : 32'd0)};
    assign local_error_directory_generation =
        {local_error_valid_q[1] ?
         local_error_directory_generation_q[1] :
         (fault_now[1] ? fault_scope_directory_generation_q[1] :
          (close_local_error_pending_q[1] ?
           close_local_error_directory_generation_q[1] : 16'd0)),
         local_error_valid_q[0] ?
         local_error_directory_generation_q[0] :
         (fault_now[0] ? fault_scope_directory_generation_q[0] :
          (close_local_error_pending_q[0] ?
           close_local_error_directory_generation_q[0] : 16'd0))};
    assign local_error_physical_bank_generation =
        {local_error_valid_q[1] ?
         local_error_physical_bank_generation_q[1] :
         (fault_now[1] ?
          fault_scope_physical_bank_generation_q[1] :
          (close_local_error_pending_q[1] ?
           close_local_error_physical_bank_generation_q[1] : 32'd0)),
         local_error_valid_q[0] ?
         local_error_physical_bank_generation_q[0] :
         (fault_now[0] ?
          fault_scope_physical_bank_generation_q[0] :
          (close_local_error_pending_q[0] ?
           close_local_error_physical_bank_generation_q[0] : 32'd0))};
    assign local_error_stage_ticket =
        {local_error_valid_q[1] ? local_error_stage_ticket_q[1] :
         (fault_now[1] ? fault_scope_stage_ticket_q[1] :
          (close_local_error_pending_q[1] ?
           close_local_error_stage_ticket_q[1] : 32'd0)),
         local_error_valid_q[0] ? local_error_stage_ticket_q[0] :
         (fault_now[0] ? fault_scope_stage_ticket_q[0] :
          (close_local_error_pending_q[0] ?
           close_local_error_stage_ticket_q[0] : 32'd0))};
    assign local_error_content_handle =
        {local_error_valid_q[1] ? local_error_content_handle_q[1] :
         (fault_now[1] ? fault_scope_content_handle_q[1] :
          (close_local_error_pending_q[1] ?
           close_local_error_content_handle_q[1] : 32'd0)),
         local_error_valid_q[0] ? local_error_content_handle_q[0] :
         (fault_now[0] ? fault_scope_content_handle_q[0] :
          (close_local_error_pending_q[0] ?
           close_local_error_content_handle_q[0] : 32'd0))};
    assign reset_required =
        {reset_required_q[1] ||
         (fault_now[1] && fault_reset_now[1]),
         reset_required_q[0] ||
         (fault_now[0] && fault_reset_now[0])};
    assign global_reset_required = reset_required[0] || reset_required[1];

    assign mgmt_rsp_valid = mgmt_rsp_valid_q;
    // Echo payload is accepted once at C0 and held under the single global
    // management credit.  Valid masks the physically unreset payload so the
    // reset/idle ABI remains all-zero without mapping functional zero values
    // onto wide synchronous-reset control cones.
    assign mgmt_rsp_opcode = mgmt_rsp_valid_q ? mgmt_rsp_opcode_q : 4'd0;
    assign mgmt_rsp_bank_mask = mgmt_rsp_valid_q ?
        mgmt_rsp_bank_mask_q : 2'd0;
    assign mgmt_rsp_state = mgmt_rsp_state_q;
    // Generation is the post-operation architectural view.  The sole global
    // management credit prevents a younger generation-changing command while
    // this response is held.  For CLAIM_FRESH the registered descriptor
    // install overlay exposes the new generation on the response edge; the
    // following durable copy preserves exactly the same value.  Using that
    // stable view directly avoids placing the live fail-closed decision cone
    // on a redundant 32-bit response-register enable.
    assign mgmt_rsp_directory_generation = mgmt_rsp_valid_q ?
        {effective_generation1_w, effective_generation0_w} : 32'd0;
    assign mgmt_rsp_tag = mgmt_rsp_valid_q ? mgmt_rsp_tag_q : 16'd0;
    assign mgmt_rsp_status = mgmt_rsp_status_q;

    assign force_error_rsp_valid = force_rsp_valid_q;
    assign force_error_rsp_bank_mask = force_rsp_bank_mask_q;
    assign force_error_rsp_code = force_rsp_code_q;
    assign force_error_rsp_state = force_rsp_state_q;
    assign force_error_rsp_directory_generation = force_rsp_generation_q;
    assign force_error_rsp_reset_required = force_rsp_reset_required_q;
    assign force_error_rsp_tag = force_rsp_tag_q;
    assign force_error_rsp_status = force_rsp_status_q;

    assign publish_rsp_valid = pub_rsp_valid_q;
    assign publish_rsp_bank_id = pub_rsp_bank_q;
    assign publish_rsp_matrix_id = pub_rsp_matrix_id_q;
    assign publish_rsp_source_index = pub_rsp_source_index_q;
    assign publish_rsp_slot_base = pub_rsp_slot_base_q;
    assign publish_rsp_directory_generation =
        pub_rsp_directory_generation_q;
    assign publish_rsp_committed = pub_rsp_committed_q;
    assign publish_rsp_committed_source_count =
        pub_rsp_committed_count_q;
    assign publish_rsp_tag = pub_rsp_tag_q;
    assign publish_rsp_status = pub_rsp_status_q;

    assign lookup_rsp_valid = lookup_out_valid_q;
    assign lookup_rsp_kind = lookup_out_kind_q;
    assign lookup_rsp_image_epoch = lookup_out_image_epoch_q;
    assign lookup_rsp_stage_id = lookup_out_stage_id_q;
    assign lookup_rsp_stage_ticket = lookup_out_stage_ticket_q;
    assign lookup_rsp_logical_branch = lookup_out_logical_branch_q;
    assign lookup_rsp_context_generation = lookup_out_context_generation_q;
    assign lookup_rsp_matrix_id = lookup_out_matrix_id_q;
    assign lookup_rsp_source_index = lookup_out_source_index_q;
    assign lookup_rsp_row_tile = lookup_out_row_tile_q;
    assign lookup_rsp_matrix_binding_token =
        lookup_out_matrix_binding_token_q;
    assign lookup_rsp_cancellation_epoch =
        lookup_out_cancellation_epoch_q;
    assign lookup_rsp_causal_continuation =
        lookup_out_causal_continuation_q;
    assign lookup_rsp_selected_bank_id = lookup_out_bank_q;
    assign lookup_rsp_physical_bank_generation =
        lookup_out_physical_bank_generation_q;
    assign lookup_rsp_content_handle = lookup_out_content_handle_q;
    assign lookup_rsp_directory_generation =
        lookup_out_directory_generation_q;
    // Keep terminal fail-closed masking outside the held payload registers.
    // This preserves zero-on-error at the ABI while avoiding a wide
    // same-edge fault/close cone on every address and data register input.
    // lookup_out_status_q is itself held whenever lookup_rsp_valid is held,
    // so all masked response fields remain stable under backpressure.
    assign lookup_rsp_slot_base =
        (lookup_out_status_q == STATUS_OK) ? lookup_out_slot_base_q : 13'd0;
    assign lookup_rsp_weight_addr =
        ((lookup_out_status_q == STATUS_OK) && lookup_out_hit_q) ?
        lookup_out_weight_addr_q : 13'd0;
    assign lookup_rsp_hit =
        (lookup_out_status_q == STATUS_OK) && lookup_out_hit_q;
    assign lookup_rsp_weight_data =
        ((lookup_out_status_q == STATUS_OK) && lookup_out_hit_q) ?
        lookup_out_weight_data_q : 128'd0;
    assign lookup_rsp_user_tag = lookup_out_user_tag_q;
    assign lookup_rsp_status = lookup_out_status_q;
    assign lookup_rsp_fatal = lookup_out_fatal_q;

    assign publish_rsp_fire = pub_rsp_valid_q && publish_rsp_ready;
    assign mgmt_rsp_fire = mgmt_rsp_valid_q && mgmt_rsp_ready;
    assign force_rsp_fire = force_rsp_valid_q && force_error_rsp_ready;
    assign lookup_rsp_fire = lookup_out_valid_q && lookup_rsp_ready;
    assign lookup_out_can_take = !lookup_out_valid_q || lookup_rsp_fire;
    assign next_lookup_head = slot_next(lookup_head_q);
    assign response_second_slot = slot_next(lookup_head_q);
    assign response_third_slot = slot_next(response_second_slot);
    assign new_slot_incarnation =
        (slot_incarnation_q[lookup_tail_q] == 14'h3fff) ? 14'd1 :
        slot_incarnation_q[lookup_tail_q] + 1'b1;

    assign bank0_expect_head_slot_w =
        bank0_expect_slot_q[bank0_expect_head_q];
    assign bank1_expect_head_slot_w =
        bank1_expect_slot_q[bank1_expect_head_q];
    assign bank0_expect_head_tag_w =
        bank0_expect_tag_q[bank0_expect_head_q];
    assign bank1_expect_head_tag_w =
        bank1_expect_tag_q[bank1_expect_head_q];
    assign bank0_expect_head_addr_w =
        bank0_expect_addr_q[bank0_expect_head_q];
    assign bank1_expect_head_addr_w =
        bank1_expect_addr_q[bank1_expect_head_q];
    assign bank0_expect_head_generation_w =
        bank0_expect_generation_q[bank0_expect_head_q];
    assign bank1_expect_head_generation_w =
        bank1_expect_generation_q[bank1_expect_head_q];
    assign bank0_expect_head_ticket_w =
        bank0_expect_ticket_q[bank0_expect_head_q];
    assign bank1_expect_head_ticket_w =
        bank1_expect_ticket_q[bank1_expect_head_q];

    // Counts derive from physical slot ownership, avoiding shadow counters.
    assign bank0_ref_count_w = bank0_ref_count_q;
    assign bank1_ref_count_w = bank1_ref_count_q;
    assign bank0_pending_count_w =
        {1'b0, ((slot_state_q[0] == SLOT_BANK_PENDING) && !slot_bank_q[0])} +
        {1'b0, ((slot_state_q[1] == SLOT_BANK_PENDING) && !slot_bank_q[1])} +
        {1'b0, ((slot_state_q[2] == SLOT_BANK_PENDING) && !slot_bank_q[2])};
    assign bank1_pending_count_w =
        {1'b0, ((slot_state_q[0] == SLOT_BANK_PENDING) && slot_bank_q[0])} +
        {1'b0, ((slot_state_q[1] == SLOT_BANK_PENDING) && slot_bank_q[1])} +
        {1'b0, ((slot_state_q[2] == SLOT_BANK_PENDING) && slot_bank_q[2])};
    assign bank0_wait_count_w = bank0_expect_count_q;
    assign bank1_wait_count_w = bank1_expect_count_q;
    assign directory_to_bank_pending =
        {bank1_pending_count_w, bank0_pending_count_w};
    assign bank_rsp_outstanding = {bank1_wait_count_w, bank0_wait_count_w};
    assign directory_bank_ref_count =
        {bank1_ref_count_w, bank0_ref_count_w};
    assign lookup_outstanding = lookup_count_q;
    assign directory_read_busy = dir_pipe_valid_q;
    assign publication_busy = pub_exec_valid_q || pub_rsp_valid_q;
    assign management_busy = mgmt_exec_valid_q || mgmt_decision_valid_q ||
                             descriptor_install_pending_q[0] ||
                             descriptor_install_pending_q[1] ||
                             scrub_candidate_valid_q || mgmt_active_q ||
                             mgmt_rsp_valid_q;
    assign final_close_pending = close_pending_q || force_rsp_valid_q;

    assign management_fence_w =
        ((mgmt_exec_valid_q || mgmt_decision_valid_q) ?
         mgmt_exec_bank_mask_q : 2'b00) |
        {descriptor_install_pending_q[1],
         descriptor_install_pending_q[0]} |
        (scrub_candidate_valid_q ? mgmt_active_bank_mask_q : 2'b00) |
        (mgmt_active_q ? mgmt_active_bank_mask_q : 2'b00) |
        ((mgmt_rsp_valid_q && mgmt_rsp_mutating_q) ?
         mgmt_rsp_bank_mask_q : 2'b00);
    assign close_fence_w = close_pending_q ? close_bank_mask_q : 2'b00;
    // Static bank authority fence.  Keep this distinct from fault_now: live
    // physical faults are already covered by preexisting_fence_now, while a
    // previously latched generation/reset fault must prevent a later SCRUB
    // from becoming a new management activation.
    assign sticky_fault_fence_w =
        {fault_fence_q[1] || local_error_valid_q[1] ||
         fast_fault_bridge_q[1],
         fault_fence_q[0] || local_error_valid_q[0] ||
         fast_fault_bridge_q[0]};
    assign current_fault_fence_w =
        sticky_fault_fence_w | {fault_now[1], fault_now[0]};

    // The two RAM outputs feed independent fixed-bank boolean classifiers.
    // These signals are deliberately separate from dir_result_status and
    // publish_result_status: only the one-bit equivalence needed for a
    // same-edge fail-closed admission fence is evaluated here.  Terminal
    // response fields continue to use the complete normative classifiers.
    // Each <=3-bit equality group is an explicit logical boundary: every
    // group consumes at most six LUT inputs, and the six results fit one final
    // LUT6.  No keep attribute is applied here; Vivado remains free to balance
    // or replicate the shallow cone for its bank-local admission endpoints.
    assign dir_fast_gen_equal0_w[0] =
        mem0_read_data_q[16:14] == dir_pipe_fast_generation_q[2:0];
    assign dir_fast_gen_equal0_w[1] =
        mem0_read_data_q[19:17] == dir_pipe_fast_generation_q[5:3];
    assign dir_fast_gen_equal0_w[2] =
        mem0_read_data_q[22:20] == dir_pipe_fast_generation_q[8:6];
    assign dir_fast_gen_equal0_w[3] =
        mem0_read_data_q[25:23] == dir_pipe_fast_generation_q[11:9];
    assign dir_fast_gen_equal0_w[4] =
        mem0_read_data_q[27:26] == dir_pipe_fast_generation_q[13:12];
    assign dir_fast_gen_equal0_w[5] =
        mem0_read_data_q[29:28] == dir_pipe_fast_generation_q[15:14];
    assign dir_fast_gen_equal1_w[0] =
        mem1_read_data_q[16:14] == dir_pipe_fast_generation_q[2:0];
    assign dir_fast_gen_equal1_w[1] =
        mem1_read_data_q[19:17] == dir_pipe_fast_generation_q[5:3];
    assign dir_fast_gen_equal1_w[2] =
        mem1_read_data_q[22:20] == dir_pipe_fast_generation_q[8:6];
    assign dir_fast_gen_equal1_w[3] =
        mem1_read_data_q[25:23] == dir_pipe_fast_generation_q[11:9];
    assign dir_fast_gen_equal1_w[4] =
        mem1_read_data_q[27:26] == dir_pipe_fast_generation_q[13:12];
    assign dir_fast_gen_equal1_w[5] =
        mem1_read_data_q[29:28] == dir_pipe_fast_generation_q[15:14];
    assign dir_fast_generation_match0_w = &dir_fast_gen_equal0_w;
    assign dir_fast_generation_match1_w = &dir_fast_gen_equal1_w;

    assign dir_fast_fatal0_w = dir_pipe_fast_active_q[0] &&
        directory_entry_fast_fatal(
            mem0_read_data_q,
            dir_fast_generation_match0_w,
            dir_pipe_fast_kind_q,
            dir_pipe_fast_row_tile_q);
    assign dir_fast_fatal1_w = dir_pipe_fast_active_q[1] &&
        directory_entry_fast_fatal(
            mem1_read_data_q,
            dir_fast_generation_match1_w,
            dir_pipe_fast_kind_q,
            dir_pipe_fast_row_tile_q);
    // The complete result classifier consumes this same fixed-bank predicate
    // for its fatal bit.  Status/hit/address remain independently normative;
    // keeping fatal one-bit-local prevents their rich priority mux from being
    // absorbed into slot_fatal_q and lookup_out_fatal_q register D cones.
    assign dir_result_physical_fatal_w = dir_fast_fatal0_w ||
                                         dir_fast_fatal1_w;
    assign pub_fast_fatal0_w = pub_exec_valid_q && !pub_exec_bank_q &&
        publication_entry_fast_fatal(
            mem0_read_data_q,
            pub_exec_directory_generation_q,
            pub_exec_slot_base_q,
            (pub_exec_pre_status_q == STATUS_OK),
            pub_exec_read_issued_q);
    assign pub_fast_fatal1_w = pub_exec_valid_q && pub_exec_bank_q &&
        publication_entry_fast_fatal(
            mem1_read_data_q,
            pub_exec_directory_generation_q,
            pub_exec_slot_base_q,
            (pub_exec_pre_status_q == STATUS_OK),
            pub_exec_read_issued_q);

    // Only faults discovered from pre-existing physical work participate in
    // same-edge ready fencing.  An offending request must itself be allowed
    // to fire so it can receive its terminal response; its acceptance-time
    // fault is latched at that edge and fences following cycles.
    assign preexisting_fence_now[0] = internal_order_fault ||
        bank0_rsp_fence_now_w ||
        dir_fast_fatal0_w || pub_fast_fatal0_w;
    assign preexisting_fence_now[1] = internal_order_fault ||
        bank1_rsp_fence_now_w ||
        dir_fast_fatal1_w || pub_fast_fatal1_w;
    // A management handshake captures the complete target fault snapshot in
    // mgmt_exec_fault_collision_q.  From that edge until terminalization,
    // management_fence_w prevents a new lookup or publication on the same
    // directory, and the one-cycle synchronous directory result that predates
    // the handshake was already visible in the captured snapshot.  Therefore
    // the only faults that can first appear against an in-flight ordinary
    // management command are an orphan/invalid physical-bank response or the
    // unscoped internal order invariant.  Keep this late-stage classifier
    // separate from preexisting_fence_now so a BRAM output never drives wide
    // management lifecycle state, while preserving the required C1/C2 orphan
    // response cancellation behavior.
    assign mgmt_late_fault_now_w[0] = internal_order_fault ||
        bank0_rsp_fence_now_w;
    assign mgmt_late_fault_now_w[1] = internal_order_fault ||
        bank1_rsp_fence_now_w;
    assign fast_fault_now_w[0] = preexisting_fence_now[0] ||
        (lookup_accept_fault_candidate_w &&
         !lookup_res_selected_bank_id) ||
        (mgmt_generation_fault_candidate_w &&
         (mgmt_exec_bank_mask_q == 2'b01));
    assign fast_fault_now_w[1] = preexisting_fence_now[1] ||
        (lookup_accept_fault_candidate_w &&
         lookup_res_selected_bank_id) ||
        (mgmt_generation_fault_candidate_w &&
         (mgmt_exec_bank_mask_q == 2'b10));
    // Registered rich-event sources.  Lookup uses the actual accepted fire.
    // Generation exhaustion is captured from the execution-edge classifier
    // into this one-bit boundary at the same edge that installs its fast
    // fence; the following rich merge still depends only on registered flags.
    // This preserves first-error priority if an exact close arrives while the
    // management decision is being materialized on the following cycle.
    assign fault_live_sources0_w = {
        internal_order_fault,
        bank0_rsp_observed_fatal,
        dir_fast_fatal0_w,
        pub_fast_fatal0_w,
        (lookup_req_fire && lookup_req_kind &&
         (lookup_pre_status != STATUS_OK) &&
         !lookup_res_selected_bank_id),
        (mgmt_generation_fault_candidate_w &&
         (mgmt_exec_bank_mask_q == 2'b01))};
    assign fault_live_sources1_w = {
        internal_order_fault,
        bank1_rsp_observed_fatal,
        dir_fast_fatal1_w,
        pub_fast_fatal1_w,
        (lookup_req_fire && lookup_req_kind &&
         (lookup_pre_status != STATUS_OK) &&
         lookup_res_selected_bank_id),
        (mgmt_generation_fault_candidate_w &&
         (mgmt_exec_bank_mask_q == 2'b10))};
    assign fault_live_reset0_w = fault_live_sources0_w[5] ||
        (fault_live_sources0_w[4] && bank0_rsp_observed_reset) ||
        fault_live_sources0_w[0];
    assign fault_live_reset1_w = fault_live_sources1_w[5] ||
        (fault_live_sources1_w[4] && bank1_rsp_observed_reset) ||
        fault_live_sources1_w[0];
    // A scrub starts only from acceptance-edge causal quiescence and then
    // fences both selected directory ports for its whole lifetime.  Therefore
    // a selected physical response during SCRUB is necessarily orphaned, and
    // no directory/publication/lookup live-fault term is reachable on that
    // target.  This shallow veto prevents final-address success immediately
    // without routing either directory RAM result through the scrub controls.
    // The registered rich classifier still supplies the exact error one edge
    // later.  For a dual-bank scrub, either selected response vetoes the
    // all-or-none completion; an unselected bank remains independent.
    assign scrub_live_veto_w = internal_order_fault ||
        (mgmt_active_bank_mask_q[0] && bank0_rd_rsp_valid) ||
        (mgmt_active_bank_mask_q[1] && bank1_rd_rsp_valid);
    assign directory_management_fence = management_fence_w;

    assign bank_work_empty_w[0] =
        (bank0_ref_count_w == 0) &&
        !bank0_rd_rsp_valid &&
        !(pub_exec_valid_q && !pub_exec_bank_q) &&
        !(pub_rsp_valid_q && !pub_rsp_bank_q) &&
        !((mgmt_exec_valid_q || mgmt_decision_valid_q) &&
          mgmt_exec_bank_mask_q[0]) &&
        !descriptor_install_pending_q[0] &&
        !(scrub_candidate_valid_q && mgmt_active_bank_mask_q[0]) &&
        !(mgmt_active_q && mgmt_active_bank_mask_q[0]) &&
        !(mgmt_rsp_valid_q && mgmt_rsp_bank_mask_q[0]);
    assign bank_work_empty_w[1] =
        (bank1_ref_count_w == 0) &&
        !bank1_rd_rsp_valid &&
        !(pub_exec_valid_q && pub_exec_bank_q) &&
        !(pub_rsp_valid_q && pub_rsp_bank_q) &&
        !((mgmt_exec_valid_q || mgmt_decision_valid_q) &&
          mgmt_exec_bank_mask_q[1]) &&
        !descriptor_install_pending_q[1] &&
        !(scrub_candidate_valid_q && mgmt_active_bank_mask_q[1]) &&
        !(mgmt_active_q && mgmt_active_bank_mask_q[1]) &&
        !(mgmt_rsp_valid_q && mgmt_rsp_bank_mask_q[1]);
    assign bank_causal_empty_w[0] = bank_work_empty_w[0] &&
        !fault_now[0] &&
        !close_local_error_pending_q[0] &&
        !fault_event_pending_q[0] &&
        !(force_rsp_valid_q && force_rsp_bank_mask_q[0]);
    assign bank_causal_empty_w[1] = bank_work_empty_w[1] &&
        !fault_now[1] &&
        !close_local_error_pending_q[1] &&
        !fault_event_pending_q[1] &&
        !(force_rsp_valid_q && force_rsp_bank_mask_q[1]);
    assign bank_quiescent_w[0] = bank_causal_empty_w[0] &&
        (state_q[0] != ST_SCRUBBING) &&
        !(close_pending_q && close_bank_mask_q[0]);
    assign bank_quiescent_w[1] = bank_causal_empty_w[1] &&
        (state_q[1] != ST_SCRUBBING) &&
        !(close_pending_q && close_bank_mask_q[1]);
    assign bank_quiescent = bank_quiescent_w;
    assign directory_quiescent = bank_quiescent_w[0] &&
                                 bank_quiescent_w[1] &&
                                 !mgmt_exec_valid_q &&
                                 !mgmt_decision_valid_q &&
                                 !descriptor_install_pending_q[0] &&
                                 !descriptor_install_pending_q[1] &&
                                 !scrub_candidate_valid_q &&
                                 !mgmt_active_q && !mgmt_rsp_valid_q &&
                                 !close_pending_q && !force_rsp_valid_q;
    assign bank_drain_complete[0] = (state_q[0] == ST_DRAINING) &&
                                     bank_causal_empty_w[0];
    assign bank_drain_complete[1] = (state_q[1] == ST_DRAINING) &&
                                     bank_causal_empty_w[1];
    assign bank_retire_safe[0] = bank_drain_complete[0] &&
        (drain_target_q[0] == DRAIN_INVALID) &&
        begin_drain_rsp_retired_q[0] && !local_error_valid_q[0] &&
        !reset_required_q[0] && !(close_fence_w[0]);
    assign bank_retire_safe[1] = bank_drain_complete[1] &&
        (drain_target_q[1] == DRAIN_INVALID) &&
        begin_drain_rsp_retired_q[1] && !local_error_valid_q[1] &&
        !reset_required_q[1] && !(close_fence_w[1]);

    // A newly staged first error is already an immutable architectural event.
    // Expose it directly, then either consume it on the stage-to-sticky edge or
    // leave one held pending bit.  A reset-only escalation behind an older
    // sticky first error never impersonates a second first-error event.
    assign fault_event_from_pending0_w = fault_event_pending_q[0];
    assign fault_event_from_pending1_w = fault_event_pending_q[1];
    assign fault_event_candidate0_w = fault_event_from_pending0_w ||
        (fault_now[0] && !local_error_valid_q[0]);
    assign fault_event_candidate1_w = fault_event_from_pending1_w ||
        (fault_now[1] && !local_error_valid_q[1]);
    assign fault_event_valid = fault_event_candidate0_w ||
                               fault_event_candidate1_w;
    assign fault_event_bank_mask = fault_event_candidate0_w ? 2'b01 :
                                   (fault_event_candidate1_w ? 2'b10 : 2'b00);
    assign fault_event_code = fault_event_candidate0_w ?
        (fault_event_from_pending0_w ? local_error_code_q[0] :
                                       fault_code_now[0]) :
        (fault_event_from_pending1_w ? local_error_code_q[1] :
                                       fault_code_now[1]);
    assign fault_event_detail = fault_event_candidate0_w ?
        (fault_event_from_pending0_w ? local_error_detail_q[0] :
                                       fault_detail_now[0]) :
        (fault_event_from_pending1_w ? local_error_detail_q[1] :
                                       fault_detail_now[1]);
    assign fault_event_directory_generation = fault_event_candidate0_w ?
        (fault_event_from_pending0_w ?
         local_error_directory_generation_q[0] :
         fault_scope_directory_generation_q[0]) :
        (fault_event_from_pending1_w ?
         local_error_directory_generation_q[1] :
         fault_scope_directory_generation_q[1]);
    assign fault_event_stage_ticket = fault_event_candidate0_w ?
        (fault_event_from_pending0_w ? local_error_stage_ticket_q[0] :
                                       fault_scope_stage_ticket_q[0]) :
        (fault_event_from_pending1_w ? local_error_stage_ticket_q[1] :
                                       fault_scope_stage_ticket_q[1]);
    assign fault_event_content_handle = fault_event_candidate0_w ?
        (fault_event_from_pending0_w ? local_error_content_handle_q[0] :
                                       fault_scope_content_handle_q[0]) :
        (fault_event_from_pending1_w ? local_error_content_handle_q[1] :
                                       fault_scope_content_handle_q[1]);
    assign fault_event_physical_bank_generation = fault_event_candidate0_w ?
        (fault_event_from_pending0_w ?
         local_error_physical_bank_generation_q[0] :
         fault_scope_physical_bank_generation_q[0]) :
        (fault_event_from_pending1_w ?
         local_error_physical_bank_generation_q[1] :
         fault_scope_physical_bank_generation_q[1]);
    assign fault_event_fire_w = fault_event_valid && fault_event_ready;

    // Acceptance-time lookup trust/bounds checks.  An invalid COMPUTE is a
    // lease fault; a PROBE rejection is caller-local.  No truncated key is
    // ever presented to RAM unless this status is OK.
    always @* begin
        lookup_pre_status = STATUS_OK;
        lookup_pre_read = 1'b0;
        if (!lookup_res_resolution_validated)
            lookup_pre_status = STATUS_ERR_BAD_IDENTITY;
        else if ((lookup_req_image_epoch != lookup_res_image_epoch) ||
                 (lookup_req_stage_id != lookup_res_stage_id) ||
                 (lookup_req_stage_ticket !=
                  lookup_res_lease_owner_ticket) ||
                 (lookup_req_logical_branch !=
                  lookup_res_logical_branch) ||
                 (lookup_req_context_generation !=
                  lookup_res_context_generation) ||
                 (lookup_req_matrix_binding_token !=
                  lookup_res_matrix_binding_token))
            lookup_pre_status = STATUS_ERR_BAD_IDENTITY;
        else if (lookup_req_cancellation_epoch !=
                 lookup_res_cancellation_epoch)
            lookup_pre_status = STATUS_ERR_CANCELLATION_STALE;
        else if (!descriptor_valid_q[lookup_res_selected_bank_id] ||
                 !lease_authority_valid_q[lookup_res_selected_bank_id])
            lookup_pre_status = STATUS_ERR_BAD_IDENTITY;
        // Data admission is fenced while a descriptor install or ticket clear
        // is pending, so only the durable per-bank descriptor may authorize a
        // lookup.  Any overlay-cycle speculative RAM read remains unowned.
        else if (((lookup_res_selected_bank_id ?
                   image_epoch_q[1] : image_epoch_q[0]) !=
                  lookup_res_image_epoch) ||
                 ((lookup_res_selected_bank_id ?
                   stage_id_q[1] : stage_id_q[0]) !=
                  lookup_res_stage_id) ||
                 ((lookup_res_selected_bank_id ?
                   stage_ticket_q[1] : stage_ticket_q[0]) !=
                  lookup_res_lease_owner_ticket) ||
                 ((lookup_res_selected_bank_id ?
                   logical_branch_q[1] : logical_branch_q[0]) !=
                  lookup_res_logical_branch) ||
                 ((lookup_res_selected_bank_id ?
                   context_generation_q[1] : context_generation_q[0]) !=
                  lookup_res_context_generation))
            lookup_pre_status = STATUS_ERR_BAD_IDENTITY;
        else if ((lookup_res_selected_bank_id ?
                  cancellation_epoch_q[1] : cancellation_epoch_q[0]) !=
                 lookup_res_cancellation_epoch)
            lookup_pre_status = STATUS_ERR_CANCELLATION_STALE;
        else if ((lookup_res_selected_bank_id ?
                  physical_bank_generation_q[1] :
                  physical_bank_generation_q[0]) !=
                 lookup_res_physical_bank_generation)
            lookup_pre_status = STATUS_ERR_STALE_GENERATION;
        else if ((lookup_res_selected_bank_id ? generation_q[1] :
                                                generation_q[0]) !=
                 lookup_res_directory_generation)
            lookup_pre_status = STATUS_ERR_STALE_GENERATION;
        else if ((lookup_res_selected_bank_id ?
                  content_handle_q[1] : content_handle_q[0]) !=
                 lookup_res_content_handle)
            lookup_pre_status = STATUS_ERR_CONTENT_MISMATCH;
        else if ((lookup_res_matrix_mask !=
                  (lookup_res_selected_bank_id ? matrix_mask_q[1] :
                                                 matrix_mask_q[0])) ||
                 !lookup_res_matrix_mask[lookup_req_matrix_id])
            lookup_pre_status = STATUS_ERR_BAD_MATRIX;
        else if (lookup_res_matrix_binding_token !=
                 (lookup_req_matrix_id ?
                  (lookup_res_selected_bank_id ?
                   matrix1_binding_token_q[1] :
                   matrix1_binding_token_q[0]) :
                  (lookup_res_selected_bank_id ?
                   matrix0_binding_token_q[1] :
                   matrix0_binding_token_q[0])))
            lookup_pre_status = STATUS_ERR_BAD_IDENTITY;
        else if (lookup_res_matrix_source_count !=
                 (lookup_req_matrix_id ?
                  (lookup_res_selected_bank_id ?
                   matrix1_source_count_q[1] :
                   matrix1_source_count_q[0]) :
                  (lookup_res_selected_bank_id ?
                   matrix0_source_count_q[1] :
                   matrix0_source_count_q[0])))
            lookup_pre_status = STATUS_ERR_BAD_BOUNDS;
        else if (lookup_res_row_tile_count !=
                 (lookup_req_matrix_id ?
                  (lookup_res_selected_bank_id ?
                   matrix1_row_tile_count_q[1] :
                   matrix1_row_tile_count_q[0]) :
                  (lookup_res_selected_bank_id ?
                   matrix0_row_tile_count_q[1] :
                   matrix0_row_tile_count_q[0])))
            lookup_pre_status = STATUS_ERR_BAD_BOUNDS;
        else if (!lookup_res_source_domain_validated)
            lookup_pre_status = STATUS_ERR_BAD_SOURCE;
        else if (lookup_req_kind &&
                 !lookup_res_compute_membership_validated)
            lookup_pre_status = STATUS_ERR_MEMBERSHIP_UNPROVEN;
        else if ((lookup_res_matrix_source_count < 1) ||
                 (lookup_res_matrix_source_count > 320) ||
                 lookup_req_source_index[9] ||
                 (lookup_req_source_index >=
                  lookup_res_matrix_source_count))
            lookup_pre_status = STATUS_ERR_BAD_SOURCE;
        else if ((lookup_res_row_tile_count < 1) ||
                 (lookup_res_row_tile_count > 20) ||
                 (lookup_req_kind &&
                  (lookup_req_row_tile >= lookup_res_row_tile_count)) ||
                 (!lookup_req_kind && (lookup_req_row_tile != 0)))
            lookup_pre_status = STATUS_ERR_BAD_ROW_TILE;
        else begin
            lookup_pre_status = STATUS_OK;
            lookup_pre_read = 1'b1;
        end
    end

    assign lookup_key = {lookup_req_matrix_id,
                         lookup_req_source_index[8:0]};

    // Publication identity/proof checks precede key/address truncation.
    always @* begin
        publish_pre_status = STATUS_OK;
        publish_endpoint = {1'b0, publish_req_slot_base} +
                           {8'd0, publish_req_row_tile_count} - 1'b1;
        if ((state_q[publish_req_bank_id] != ST_LOADING) ||
            !descriptor_valid_q[publish_req_bank_id] ||
            !lease_authority_valid_q[publish_req_bank_id])
            publish_pre_status = STATUS_ERR_WRONG_STATE;
        // Mutating management overlays fence publication admission.  Compare
        // against the durable descriptor so the precheck does not inherit the
        // descriptor-install mux cone.
        else if ((publish_req_image_epoch !=
                  (publish_req_bank_id ? image_epoch_q[1] :
                                         image_epoch_q[0])) ||
                 (publish_req_stage_id !=
                  (publish_req_bank_id ? stage_id_q[1] : stage_id_q[0])) ||
                 (publish_req_stage_ticket !=
                  (publish_req_bank_id ? stage_ticket_q[1] :
                                         stage_ticket_q[0])) ||
                 (publish_req_logical_branch !=
                  (publish_req_bank_id ? logical_branch_q[1] :
                                         logical_branch_q[0])) ||
                 (publish_req_context_generation !=
                  (publish_req_bank_id ? context_generation_q[1] :
                                         context_generation_q[0])))
            publish_pre_status = STATUS_ERR_BAD_IDENTITY;
        else if (publish_req_cancellation_epoch !=
                 (publish_req_bank_id ? cancellation_epoch_q[1] :
                                        cancellation_epoch_q[0]))
            publish_pre_status = STATUS_ERR_CANCELLATION_STALE;
        else if (publish_req_physical_bank_generation !=
                 (publish_req_bank_id ?
                  physical_bank_generation_q[1] :
                  physical_bank_generation_q[0]))
            publish_pre_status = STATUS_ERR_STALE_GENERATION;
        else if (publish_req_directory_generation !=
                 (publish_req_bank_id ? generation_q[1] : generation_q[0]))
            publish_pre_status = STATUS_ERR_STALE_GENERATION;
        else if (publish_req_content_handle !=
                 (publish_req_bank_id ? content_handle_q[1] :
                                        content_handle_q[0]))
            publish_pre_status = STATUS_ERR_CONTENT_MISMATCH;
        else if ((publish_req_matrix_mask !=
                  (publish_req_bank_id ? matrix_mask_q[1] :
                                         matrix_mask_q[0])) ||
                 !publish_req_matrix_mask[publish_req_matrix_id])
            publish_pre_status = STATUS_ERR_BAD_MATRIX;
        else if (publish_req_matrix_binding_token !=
                 (publish_req_matrix_id ?
                  (publish_req_bank_id ?
                   matrix1_binding_token_q[1] :
                   matrix1_binding_token_q[0]) :
                  (publish_req_bank_id ?
                   matrix0_binding_token_q[1] :
                   matrix0_binding_token_q[0])))
            publish_pre_status = STATUS_ERR_BAD_IDENTITY;
        else if (publish_req_source_count !=
                 (publish_req_matrix_id ?
                  (publish_req_bank_id ? matrix1_source_count_q[1] :
                                         matrix1_source_count_q[0]) :
                  (publish_req_bank_id ? matrix0_source_count_q[1] :
                                         matrix0_source_count_q[0])))
            publish_pre_status = STATUS_ERR_BAD_BOUNDS;
        else if (publish_req_row_tile_count !=
                 (publish_req_matrix_id ?
                  (publish_req_bank_id ?
                   matrix1_row_tile_count_q[1] :
                   matrix1_row_tile_count_q[0]) :
                  (publish_req_bank_id ?
                   matrix0_row_tile_count_q[1] :
                   matrix0_row_tile_count_q[0])))
            publish_pre_status = STATUS_ERR_BAD_BOUNDS;
        else if (!publish_req_source_complete_proof ||
                 !publish_req_slot_assignment_validated)
            publish_pre_status = STATUS_ERR_EXTERNAL_UNSAFE;
        else if ((publish_req_source_count < 1) ||
                 (publish_req_source_count > 320) ||
                 publish_req_source_index[9] ||
                 (publish_req_source_index >= publish_req_source_count))
            publish_pre_status = STATUS_ERR_BAD_SOURCE;
        else if ((publish_req_row_tile_count < 1) ||
                 (publish_req_row_tile_count > 20) ||
                 (publish_endpoint >= 8192))
            publish_pre_status = STATUS_ERR_BAD_BOUNDS;
    end

    assign pub_key = {publish_req_matrix_id,
                      publish_req_source_index[8:0]};
    assign pub_new_entry = {2'b11, publish_req_directory_generation,
                            1'b0, publish_req_slot_base};

    // Classify the registered directory result for the oldest one-cycle read.
    always @* begin
        dir_result_status = STATUS_OK;
        dir_result_hit = 1'b0;
        dir_result_slot_base = 13'd0;
        dir_result_weight_addr = 13'd0;
        dir_result_bank_pending = 1'b0;
        dir_result_entry = slot_bank_q[dir_pipe_slot_q] ?
                           mem1_read_data_q : mem0_read_data_q;
        dir_result_sum = {1'b0, dir_result_entry[12:0]} +
                         {8'd0, slot_row_tile_q[dir_pipe_slot_q]};

        if (dir_pipe_valid_q) begin
            if (slot_pre_status_q[dir_pipe_slot_q] != STATUS_OK) begin
                dir_result_status = slot_pre_status_q[dir_pipe_slot_q];
            end else if (!dir_pipe_read_issued_q) begin
                dir_result_status = STATUS_ERR_INTERNAL_STATE;
            end else if (dir_result_entry[29:14] !=
                         slot_directory_generation_q[dir_pipe_slot_q]) begin
                if (slot_kind_q[dir_pipe_slot_q]) begin
                    dir_result_status = STATUS_ERR_COMPUTE_MISS;
                end
            end else if (dir_result_entry[13] ||
                         (!dir_result_entry[31] &&
                          dir_result_entry[30])) begin
                dir_result_status = STATUS_ERR_DIRECTORY_CORRUPT;
            end else if (dir_result_entry[31] &&
                         !dir_result_entry[30]) begin
                dir_result_status = STATUS_ERR_DIRECTORY_INCOMPLETE;
            end else if (!dir_result_entry[31] &&
                         !dir_result_entry[30]) begin
                if (slot_kind_q[dir_pipe_slot_q]) begin
                    dir_result_status = STATUS_ERR_COMPUTE_MISS;
                end
            end else begin
                dir_result_hit = 1'b1;
                dir_result_slot_base = dir_result_entry[12:0];
                if (slot_kind_q[dir_pipe_slot_q]) begin
                    if (dir_result_sum >= 8192) begin
                        dir_result_status = STATUS_ERR_BAD_BOUNDS;
                        dir_result_hit = 1'b0;
                    end else begin
                        dir_result_weight_addr = dir_result_sum[12:0];
                        dir_result_bank_pending = 1'b1;
                    end
                end
            end
        end
    end

    // Fatal is the narrow companion to the rich result classifier above.
    // Invalid accepted requests and an impossible missing read preserve their
    // original terminal semantics.  A real BRAM result uses the fixed-bank
    // shallow predicate that also drives the same-edge physical fault fence.
    always @* begin
        dir_result_fatal = 1'b0;
        if (dir_pipe_valid_q) begin
            if (slot_pre_status_q[dir_pipe_slot_q] != STATUS_OK)
                dir_result_fatal = slot_kind_q[dir_pipe_slot_q];
            else if (!dir_pipe_read_issued_q)
                dir_result_fatal = 1'b1;
            else
                dir_result_fatal = dir_result_physical_fatal_w;
        end
    end

    // Classify publication pre-read.  Only an empty/stale entry receives a
    // single full-word valid+complete commit.
    always @* begin
        publish_result_status = pub_exec_pre_status_q;
        publish_result_committed = 1'b0;
        publish_result_fatal = 1'b0;
        publish_result_entry = pub_exec_bank_q ?
                               mem1_read_data_q : mem0_read_data_q;
        if (pub_exec_valid_q &&
            (pub_exec_pre_status_q == STATUS_OK)) begin
            if (!pub_exec_read_issued_q) begin
                publish_result_status = STATUS_ERR_INTERNAL_STATE;
                publish_result_fatal = 1'b1;
            end else if (publish_result_entry[29:14] !=
                pub_exec_directory_generation_q) begin
                publish_result_status = STATUS_OK;
                publish_result_committed = 1'b1;
            end else if (publish_result_entry[13] ||
                         (!publish_result_entry[31] &&
                          publish_result_entry[30]) ||
                         (publish_result_entry[31] &&
                          !publish_result_entry[30])) begin
                publish_result_status = STATUS_ERR_DIRECTORY_CORRUPT;
                publish_result_fatal = 1'b1;
            end else if (!publish_result_entry[31] &&
                         !publish_result_entry[30]) begin
                publish_result_status = STATUS_OK;
                publish_result_committed = 1'b1;
            end else if (publish_result_entry[12:0] ==
                         pub_exec_slot_base_q) begin
                publish_result_status = STATUS_ERR_DUPLICATE_PUBLICATION;
            end else begin
                publish_result_status = STATUS_ERR_DIRECTORY_RELOCATION;
                publish_result_fatal = 1'b1;
            end
        end
    end

    assign pub_commit_now = pub_exec_valid_q &&
                            publish_result_committed &&
        !(close_pending_q && close_bank_mask_q[pub_exec_bank_q]) &&
        !(force_error_fire && force_error_bank_mask[pub_exec_bank_q]);

    // Oldest bank-pending record is the sole physical issue candidate.  The
    // three fixed head rotations preserve the WAIT_DIR ordering barrier but
    // avoid a procedural dynamic-slot scan feeding every bank payload mux.
    always @* begin
        issue_onehot = 3'b000;
        case (lookup_head_q)
            2'd0: begin
                if ((lookup_count_q != 0) && !dir_wait_mask_w[0]) begin
                    if (slot_state_q[0] == SLOT_BANK_PENDING)
                        issue_onehot = 3'b001;
                    else if ((lookup_count_q > 1) &&
                             !dir_wait_mask_w[1]) begin
                        if (slot_state_q[1] == SLOT_BANK_PENDING)
                            issue_onehot = 3'b010;
                        else if ((lookup_count_q > 2) &&
                                 !dir_wait_mask_w[2] &&
                                 (slot_state_q[2] == SLOT_BANK_PENDING))
                            issue_onehot = 3'b100;
                    end
                end
            end
            2'd1: begin
                if ((lookup_count_q != 0) && !dir_wait_mask_w[1]) begin
                    if (slot_state_q[1] == SLOT_BANK_PENDING)
                        issue_onehot = 3'b010;
                    else if ((lookup_count_q > 1) &&
                             !dir_wait_mask_w[2]) begin
                        if (slot_state_q[2] == SLOT_BANK_PENDING)
                            issue_onehot = 3'b100;
                        else if ((lookup_count_q > 2) &&
                                 !dir_wait_mask_w[0] &&
                                 (slot_state_q[0] == SLOT_BANK_PENDING))
                            issue_onehot = 3'b001;
                    end
                end
            end
            2'd2: begin
                if ((lookup_count_q != 0) && !dir_wait_mask_w[2]) begin
                    if (slot_state_q[2] == SLOT_BANK_PENDING)
                        issue_onehot = 3'b100;
                    else if ((lookup_count_q > 1) &&
                             !dir_wait_mask_w[0]) begin
                        if (slot_state_q[0] == SLOT_BANK_PENDING)
                            issue_onehot = 3'b001;
                        else if ((lookup_count_q > 2) &&
                                 !dir_wait_mask_w[1] &&
                                 (slot_state_q[1] == SLOT_BANK_PENDING))
                            issue_onehot = 3'b010;
                    end
                end
            end
            default: issue_onehot = 3'b000;
        endcase
    end
    assign issue_valid = |issue_onehot;

    // A just-classified compute hit may issue directly from the synchronous
    // directory result at N+1.  If the selected bank stalls, the exact same
    // fields become the slot's held BANK_PENDING request after the edge.
    // An older registered pending record always wins, preserving issue order.
    assign direct_result_issue = dir_pipe_valid_q &&
                                 dir_result_bank_pending && !issue_valid;
    assign direct_issue_onehot_w =
        {3{direct_result_issue}} & dir_pipe_owner_onehot_q;
    assign physical_issue_onehot_w = issue_onehot |
                                     direct_issue_onehot_w;
    // Payload selection need not wait for the directory hit classifier.  The
    // bank samples these buses only when the separately qualified request
    // valid is high.  Selecting the current directory owner speculatively
    // therefore removes the BRAM-result classifier from every wide output
    // bit while preserving ready/valid semantics.  If a direct hit stalls,
    // the same fields are committed into that slot at the edge and remain
    // stable when selection changes to registered BANK_PENDING ownership.
    assign direct_payload_onehot_w =
        {3{dir_pipe_valid_q && !issue_valid}} & dir_pipe_owner_onehot_q;
    assign physical_payload_onehot_w = issue_onehot |
                                       direct_payload_onehot_w;
    assign physical_issue_slot = physical_issue_onehot_w[1] ? 2'd1 :
                                 physical_issue_onehot_w[2] ? 2'd2 : 2'd0;

    // A direct directory hit has not yet written its computed address into
    // the reserved slot.  Select that address locally for only its one-hot
    // owner; registered pending slots use their held addresses unchanged.
    assign slot0_issue_addr_w = direct_payload_onehot_w[0] ?
                                dir_result_weight_addr :
                                slot_weight_addr_q[0];
    assign slot1_issue_addr_w = direct_payload_onehot_w[1] ?
                                dir_result_weight_addr :
                                slot_weight_addr_q[1];
    assign slot2_issue_addr_w = direct_payload_onehot_w[2] ?
                                dir_result_weight_addr :
                                slot_weight_addr_q[2];
    assign bank0_issue_onehot_w = physical_issue_onehot_w &
        {!slot_bank_q[2], !slot_bank_q[1], !slot_bank_q[0]};
    assign bank1_issue_onehot_w = physical_issue_onehot_w &
        {slot_bank_q[2], slot_bank_q[1], slot_bank_q[0]};
    assign bank0_payload_onehot_w = physical_payload_onehot_w &
        {!slot_bank_q[2], !slot_bank_q[1], !slot_bank_q[0]};
    assign bank1_payload_onehot_w = physical_payload_onehot_w &
        {slot_bank_q[2], slot_bank_q[1], slot_bank_q[0]};

    // A same-edge response pop may recycle the second physical correlation
    // position.  This mirrors the bank's two response credits without adding
    // a fourth logical request position.
    assign bank0_expect_can_push_w = (bank0_expect_count_q < 2) ||
                                     bank0_rsp_fire;
    assign bank1_expect_can_push_w = (bank1_expect_count_q < 2) ||
                                     bank1_rsp_fire;

    assign bank0_rd_req_valid = (|bank0_issue_onehot_w) &&
        bank0_expect_can_push_w &&
        !(close_pending_q && close_bank_mask_q[0]) &&
        !(force_error_fire && force_error_bank_mask[0]);
    assign bank1_rd_req_valid = (|bank1_issue_onehot_w) &&
        bank1_expect_can_push_w &&
        !(close_pending_q && close_bank_mask_q[1]) &&
        !(force_error_fire && force_error_bank_mask[1]);
    // Per-bank one-hot local muxes remove the shared dynamic slot selector.
    // Payloads remain stable from the selected record even if final valid is
    // credit/fence gated; no valid-to-wide-zero mux sits on these buses.
    assign bank0_rd_req_addr =
        ({13{bank0_payload_onehot_w[0]}} & slot0_issue_addr_w) |
        ({13{bank0_payload_onehot_w[1]}} & slot1_issue_addr_w) |
        ({13{bank0_payload_onehot_w[2]}} & slot2_issue_addr_w);
    assign bank1_rd_req_addr =
        ({13{bank1_payload_onehot_w[0]}} & slot0_issue_addr_w) |
        ({13{bank1_payload_onehot_w[1]}} & slot1_issue_addr_w) |
        ({13{bank1_payload_onehot_w[2]}} & slot2_issue_addr_w);
    assign bank0_rd_req_generation =
        ({32{bank0_payload_onehot_w[0]}} &
         slot_physical_bank_generation_q[0]) |
        ({32{bank0_payload_onehot_w[1]}} &
         slot_physical_bank_generation_q[1]) |
        ({32{bank0_payload_onehot_w[2]}} &
         slot_physical_bank_generation_q[2]);
    assign bank1_rd_req_generation =
        ({32{bank1_payload_onehot_w[0]}} &
         slot_physical_bank_generation_q[0]) |
        ({32{bank1_payload_onehot_w[1]}} &
         slot_physical_bank_generation_q[1]) |
        ({32{bank1_payload_onehot_w[2]}} &
         slot_physical_bank_generation_q[2]);
    assign bank0_rd_req_lease_owner_ticket =
        ({32{bank0_payload_onehot_w[0]}} & slot_stage_ticket_q[0]) |
        ({32{bank0_payload_onehot_w[1]}} & slot_stage_ticket_q[1]) |
        ({32{bank0_payload_onehot_w[2]}} & slot_stage_ticket_q[2]);
    assign bank1_rd_req_lease_owner_ticket =
        ({32{bank1_payload_onehot_w[0]}} & slot_stage_ticket_q[0]) |
        ({32{bank1_payload_onehot_w[1]}} & slot_stage_ticket_q[1]) |
        ({32{bank1_payload_onehot_w[2]}} & slot_stage_ticket_q[2]);
    assign bank0_rd_req_tag =
        ({16{bank0_payload_onehot_w[0]}} &
         {slot_incarnation_q[0], 2'd0}) |
        ({16{bank0_payload_onehot_w[1]}} &
         {slot_incarnation_q[1], 2'd1}) |
        ({16{bank0_payload_onehot_w[2]}} &
         {slot_incarnation_q[2], 2'd2});
    assign bank1_rd_req_tag =
        ({16{bank1_payload_onehot_w[0]}} &
         {slot_incarnation_q[0], 2'd0}) |
        ({16{bank1_payload_onehot_w[1]}} &
         {slot_incarnation_q[1], 2'd1}) |
        ({16{bank1_payload_onehot_w[2]}} &
         {slot_incarnation_q[2], 2'd2});
    assign bank0_req_fire = bank0_rd_req_valid && bank0_rd_req_ready;
    assign bank1_req_fire = bank1_rd_req_valid && bank1_rd_req_ready;
    assign bank_req_fire = bank0_req_fire || bank1_req_fire;

    // Each asserted response is checked only against the registered head of
    // its physical bank's two-entry correlation FIFO.  A correct younger
    // response may remain held behind the other bank's older global response
    // without being mistaken for an orphan; no live slot scan participates
    // in the same-edge admission fence.
    assign bank0_rsp_fence_now_w = bank0_rd_rsp_valid &&
        ((bank0_expect_count_q == 0) ||
         (bank0_rd_rsp_tag != bank0_expect_head_tag_w) ||
         !equal13_lut_tree(bank0_rd_rsp_addr, bank0_expect_head_addr_w) ||
         !equal32_lut_tree(bank0_rd_rsp_generation,
                           bank0_expect_head_generation_w) ||
         !equal32_lut_tree(bank0_rd_rsp_lease_owner_ticket,
                           bank0_expect_head_ticket_w) ||
         (bank0_rd_rsp_status != STATUS_OK));
    assign bank1_rsp_fence_now_w = bank1_rd_rsp_valid &&
        ((bank1_expect_count_q == 0) ||
         (bank1_rd_rsp_tag != bank1_expect_head_tag_w) ||
         !equal13_lut_tree(bank1_rd_rsp_addr, bank1_expect_head_addr_w) ||
         !equal32_lut_tree(bank1_rd_rsp_generation,
                           bank1_expect_head_generation_w) ||
         !equal32_lut_tree(bank1_rd_rsp_lease_owner_ticket,
                           bank1_expect_head_ticket_w) ||
         (bank1_rd_rsp_status != STATUS_OK));

    always @* begin
        bank0_rsp_observed_status = STATUS_OK;
        bank0_rsp_observed_fatal = 1'b0;
        bank0_rsp_observed_reset = 1'b0;
        if (bank0_rd_rsp_valid) begin
            if ((bank0_expect_count_q == 0) ||
                (bank0_rd_rsp_tag != bank0_expect_head_tag_w)) begin
                bank0_rsp_observed_status = STATUS_ERR_INTERNAL_STATE;
                bank0_rsp_observed_fatal = 1'b1;
                bank0_rsp_observed_reset = 1'b1;
            end else if (!equal13_lut_tree(bank0_rd_rsp_addr,
                              bank0_expect_head_addr_w) ||
                         !equal32_lut_tree(bank0_rd_rsp_generation,
                              bank0_expect_head_generation_w) ||
                         !equal32_lut_tree(
                              bank0_rd_rsp_lease_owner_ticket,
                              bank0_expect_head_ticket_w)) begin
                bank0_rsp_observed_status =
                    STATUS_ERR_BANK_IDENTITY_MISMATCH;
                bank0_rsp_observed_fatal = 1'b1;
            end else if (bank0_rd_rsp_status != STATUS_OK) begin
                bank0_rsp_observed_status = STATUS_ERR_BANK_RESPONSE_ERROR;
                bank0_rsp_observed_fatal = 1'b1;
            end
        end
    end

    always @* begin
        bank1_rsp_observed_status = STATUS_OK;
        bank1_rsp_observed_fatal = 1'b0;
        bank1_rsp_observed_reset = 1'b0;
        if (bank1_rd_rsp_valid) begin
            if ((bank1_expect_count_q == 0) ||
                (bank1_rd_rsp_tag != bank1_expect_head_tag_w)) begin
                bank1_rsp_observed_status = STATUS_ERR_INTERNAL_STATE;
                bank1_rsp_observed_fatal = 1'b1;
                bank1_rsp_observed_reset = 1'b1;
            end else if (!equal13_lut_tree(bank1_rd_rsp_addr,
                              bank1_expect_head_addr_w) ||
                         !equal32_lut_tree(bank1_rd_rsp_generation,
                              bank1_expect_head_generation_w) ||
                         !equal32_lut_tree(
                              bank1_rd_rsp_lease_owner_ticket,
                              bank1_expect_head_ticket_w)) begin
                bank1_rsp_observed_status =
                    STATUS_ERR_BANK_IDENTITY_MISMATCH;
                bank1_rsp_observed_fatal = 1'b1;
            end else if (bank1_rd_rsp_status != STATUS_OK) begin
                bank1_rsp_observed_status = STATUS_ERR_BANK_RESPONSE_ERROR;
                bank1_rsp_observed_fatal = 1'b1;
            end
        end
    end

    // Only the aggregate response head may leave a physical bank.
    always @* begin
        response_slot = lookup_head_q;
        response_slot_valid = (lookup_count_q != 0);
        if (lookup_rsp_fire) begin
            response_slot = next_lookup_head;
            response_slot_valid = (lookup_count_q > 1);
        end
    end
    assign effective_response_slot = response_slot;
    assign bank0_rd_rsp_ready = rst_n && lookup_out_can_take &&
        response_slot_valid &&
        !response_bank_id &&
        (bank0_expect_count_q != 0) &&
        (bank0_expect_head_slot_w == response_slot);
    assign bank1_rd_rsp_ready = rst_n && lookup_out_can_take &&
        response_slot_valid &&
        response_bank_id &&
        (bank1_expect_count_q != 0) &&
        (bank1_expect_head_slot_w == response_slot);
    assign bank0_rsp_fire = bank0_rd_rsp_valid && bank0_rd_rsp_ready;
    assign bank1_rsp_fire = bank1_rd_rsp_valid && bank1_rd_rsp_ready;
    assign expected_bank_rsp_fire = bank0_rsp_fire || bank1_rsp_fire;
    assign response_bank_id = (response_slot == 2'd1) ? slot_bank_q[1] :
                              (response_slot == 2'd2) ? slot_bank_q[2] :
                                                       slot_bank_q[0];
    assign response_close_code = response_bank_id ? bank1_close_code :
                                                   bank0_close_code;
    assign response_close_fatal = response_bank_id ? bank1_close_fatal_w :
                                                     bank0_close_fatal_w;

    always @* begin
        bank_response_status = STATUS_OK;
        bank_response_fatal = 1'b0;
        bank_response_data = bank1_rsp_fire ? bank1_rd_rsp_data :
                                             bank0_rd_rsp_data;
        if (expected_bank_rsp_fire) begin
            if ((bank1_rsp_fire && bank1_rsp_observed_fatal) ||
                (bank0_rsp_fire && bank0_rsp_observed_fatal)) begin
                bank_response_status = bank1_rsp_fire ?
                    bank1_rsp_observed_status : bank0_rsp_observed_status;
                bank_response_fatal = 1'b1;
                bank_response_data = 128'd0;
            end else if (close_pending_q &&
                         (response_bank_id ? close_bank_mask_q[1] :
                                             close_bank_mask_q[0])) begin
                bank_response_status = response_bank_id ? close_code_q[1] :
                                                          close_code_q[0];
                bank_response_fatal =
                    (bank_response_status != STATUS_ERR_ABORTED);
                bank_response_data = 128'd0;
            end else if (force_error_fire && force_request_exact &&
                         (response_bank_id ? force_error_bank_mask[1] :
                                             force_error_bank_mask[0])) begin
                bank_response_status = response_close_code;
                bank_response_fatal = response_close_fatal;
                bank_response_data = 128'd0;
            end
        end
    end

    // SCRUB is the one management operation whose approved timing starts
    // physical work immediately after its acceptance edge.  Validate its
    // complete all-or-none request from the C0 inputs and pre-edge local
    // evidence.  A same-edge physical fault bypasses this direct path below
    // and enters the ordinary captured collision flow instead.
    always @* begin
        scrub_direct_status = STATUS_OK;
        if (mgmt_req_bank_mask == 2'b00)
            scrub_direct_status = STATUS_ERR_BAD_BANK_MASK;
        else if ((sticky_fault_fence_w & mgmt_req_bank_mask) != 0)
            // This direct decoder only decides whether C0 may mutate.  The
            // accepted request falls through to the captured decoder, which
            // returns the retained bank-local first-fatal code when present.
            scrub_direct_status = STATUS_ERR_LOCAL_PROTOCOL;
        else if (((mgmt_req_bank_mask[0]) &&
                  ((state_q[0] != ST_INVALID) ||
                   !bank_causal_empty_w[0])) ||
                 ((mgmt_req_bank_mask[1]) &&
                  ((state_q[1] != ST_INVALID) ||
                   !bank_causal_empty_w[1])))
            scrub_direct_status = STATUS_ERR_NOT_QUIESCENT;
        else if (!mgmt_req_external_safe)
            scrub_direct_status = STATUS_ERR_EXTERNAL_UNSAFE;
        else if (((mgmt_req_bank_mask[0]) &&
                  !scrub_required_q[0] &&
                  last_scrub_epoch_valid_q[0] &&
                  (mgmt_req_new_image_epoch == last_scrub_epoch_q[0])) ||
                 ((mgmt_req_bank_mask[1]) &&
                  !scrub_required_q[1] &&
                  last_scrub_epoch_valid_q[1] &&
                  (mgmt_req_new_image_epoch == last_scrub_epoch_q[1])))
            scrub_direct_status = STATUS_ERR_LOCAL_PROTOCOL;
        else if ((mgmt_req_expected_directory_generation != 0) ||
                 (mgmt_req_expected_content_handle != 0) ||
                 (mgmt_req_expected_stage_ticket != 0) ||
                 (mgmt_req_expected_physical_bank_generation != 0) ||
                 (mgmt_req_new_stage_id != 0) ||
                 (mgmt_req_new_stage_ticket != 0) ||
                 (mgmt_req_new_logical_branch != 0) ||
                 (mgmt_req_new_context_generation != 0) ||
                 (mgmt_req_new_content_handle != 0) ||
                 (mgmt_req_new_physical_bank_generation != 0) ||
                 (mgmt_req_new_cancellation_epoch != 0) ||
                 (mgmt_req_new_matrix_mask != 0) ||
                 (mgmt_req_new_matrix0_binding_token != 0) ||
                 (mgmt_req_new_matrix1_binding_token != 0) ||
                 (mgmt_req_new_matrix0_source_count != 0) ||
                 (mgmt_req_new_matrix1_source_count != 0) ||
                 (mgmt_req_new_matrix0_row_tile_count != 0) ||
                 (mgmt_req_new_matrix1_row_tile_count != 0))
            scrub_direct_status = STATUS_ERR_BAD_IDENTITY;
    end

    // Captured management-command evaluation.  Quiescence-sensitive checks
    // use acceptance-edge snapshots because the execution slot itself is now
    // an owned reference.  Only successful commands mutate state.
    always @* begin
        mgmt_status_d = STATUS_OK;
        mgmt_new_state_d = ST_INVALID;
        mgmt_new_generation_d = mgmt_exec_expected_directory_generation_q;
        mgmt_is_mutating_d = 1'b0;
        mgmt_effective_mask = mgmt_exec_bank_mask_q;
        if (mgmt_exec_opcode_q > MGMT_CLEAR_ERROR)
            mgmt_status_d = STATUS_ERR_BAD_OPCODE;
        else if ((mgmt_exec_opcode_q == MGMT_SCRUB) ?
                 (mgmt_exec_bank_mask_q == 2'b00) :
                 !((mgmt_exec_bank_mask_q == 2'b01) ||
                   (mgmt_exec_bank_mask_q == 2'b10)))
            mgmt_status_d = STATUS_ERR_BAD_BANK_MASK;
        else if (((mgmt_exec_fault_collision_q &
                   mgmt_exec_bank_mask_q) != 0))
            mgmt_status_d =
                (mgmt_exec_fault_collision_q[0] &&
                 mgmt_exec_bank_mask_q[0]) ? first_fault_code0_w :
                                             first_fault_code1_w;
        else if (mgmt_exec_opcode_q == MGMT_SCRUB) begin
            mgmt_is_mutating_d = 1'b1;
            if ((sticky_fault_fence_w & mgmt_exec_bank_mask_q) != 0)
                // Bank 0 has deterministic priority for a dual-bank SCRUB.
                // If its rich first-error record is not materialized yet,
                // return a deterministic local-protocol error; no mutation
                // is ever authorized from either status.
                mgmt_status_d =
                    (mgmt_exec_bank_mask_q[0] &&
                     local_error_valid_q[0]) ? local_error_code_q[0] :
                    (mgmt_exec_bank_mask_q[1] &&
                     local_error_valid_q[1]) ? local_error_code_q[1] :
                                               STATUS_ERR_LOCAL_PROTOCOL;
            else if (((mgmt_exec_bank_mask_q[0]) &&
                 ((state_q[0] != ST_INVALID) ||
                  !mgmt_exec_accept_causal_empty_q[0])) ||
                ((mgmt_exec_bank_mask_q[1]) &&
                 ((state_q[1] != ST_INVALID) ||
                  !mgmt_exec_accept_causal_empty_q[1])))
                mgmt_status_d = STATUS_ERR_NOT_QUIESCENT;
            else if (!mgmt_exec_external_safe_q)
                mgmt_status_d = STATUS_ERR_EXTERNAL_UNSAFE;
            else if (((mgmt_exec_bank_mask_q[0]) &&
                      !scrub_required_q[0] &&
                      last_scrub_epoch_valid_q[0] &&
                      (mgmt_exec_new_image_epoch_q ==
                       last_scrub_epoch_q[0])) ||
                     ((mgmt_exec_bank_mask_q[1]) &&
                      !scrub_required_q[1] &&
                      last_scrub_epoch_valid_q[1] &&
                      (mgmt_exec_new_image_epoch_q ==
                       last_scrub_epoch_q[1])))
                mgmt_status_d = STATUS_ERR_LOCAL_PROTOCOL;
            else if ((mgmt_exec_expected_directory_generation_q != 0) ||
                     (mgmt_exec_expected_content_handle_q != 0) ||
                     (mgmt_exec_expected_stage_ticket_q != 0) ||
                     (mgmt_exec_expected_physical_bank_generation_q != 0) ||
                     (mgmt_exec_new_stage_id_q != 0) ||
                     (mgmt_exec_new_stage_ticket_q != 0) ||
                     (mgmt_exec_new_logical_branch_q != 0) ||
                     (mgmt_exec_new_context_generation_q != 0) ||
                     (mgmt_exec_new_content_handle_q != 0) ||
                     (mgmt_exec_new_physical_bank_generation_q != 0) ||
                     (mgmt_exec_new_cancellation_epoch_q != 0) ||
                     (mgmt_exec_new_matrix_mask_q != 0) ||
                     (mgmt_exec_new_matrix0_binding_token_q != 0) ||
                     (mgmt_exec_new_matrix1_binding_token_q != 0) ||
                     (mgmt_exec_new_matrix0_source_count_q != 0) ||
                     (mgmt_exec_new_matrix1_source_count_q != 0) ||
                     (mgmt_exec_new_matrix0_row_tile_count_q != 0) ||
                     (mgmt_exec_new_matrix1_row_tile_count_q != 0))
                mgmt_status_d = STATUS_ERR_BAD_IDENTITY;
            else
                mgmt_new_state_d = ST_SCRUBBING;
        end else begin
            if (mgmt_exec_bank_mask_q == 2'b10) begin
                mgmt_new_state_d = state_q[1];
                mgmt_new_generation_d = effective_generation1_w;
            end else begin
                mgmt_new_state_d = state_q[0];
                mgmt_new_generation_d = effective_generation0_w;
            end
            case (mgmt_exec_opcode_q)
                MGMT_CLAIM_FRESH: begin
                    mgmt_is_mutating_d = 1'b1;
                    if ((mgmt_exec_bank_mask_q[0] ? state_q[0] : state_q[1]) !=
                        ST_INVALID)
                        mgmt_status_d = STATUS_ERR_WRONG_STATE;
                    else if (mgmt_exec_expected_directory_generation_q !=
                             mgmt_current_generation_w)
                        mgmt_status_d = STATUS_ERR_STALE_GENERATION;
                    else if ((mgmt_exec_expected_content_handle_q != 0) ||
                             (mgmt_exec_expected_stage_ticket_q != 0) ||
                             (mgmt_exec_expected_physical_bank_generation_q !=
                              0))
                        mgmt_status_d = STATUS_ERR_BAD_IDENTITY;
                    else if ((mgmt_exec_bank_mask_q[0] ? scrub_required_q[0] :
                                                      scrub_required_q[1]) ||
                             !(mgmt_exec_bank_mask_q[0] ?
                               last_scrub_epoch_valid_q[0] :
                               last_scrub_epoch_valid_q[1]) ||
                             (mgmt_exec_new_image_epoch_q !=
                              (mgmt_exec_bank_mask_q[0] ?
                               last_scrub_epoch_q[0] :
                               last_scrub_epoch_q[1])))
                        mgmt_status_d = STATUS_ERR_SCRUB_REQUIRED;
                    else if (!mgmt_exec_external_safe_q)
                        mgmt_status_d = STATUS_ERR_EXTERNAL_UNSAFE;
                    else if ((mgmt_exec_new_stage_id_q > 11) ||
                             (mgmt_exec_new_stage_ticket_q == 0) ||
                             (mgmt_exec_new_content_handle_q == 0) ||
                             (mgmt_exec_new_physical_bank_generation_q == 0) ||
                             !descriptor_shape_valid(
                              mgmt_exec_new_matrix_mask_q,
                              mgmt_exec_new_matrix0_binding_token_q,
                              mgmt_exec_new_matrix1_binding_token_q,
                              mgmt_exec_new_matrix0_source_count_q,
                              mgmt_exec_new_matrix1_source_count_q,
                              mgmt_exec_new_matrix0_row_tile_count_q,
                              mgmt_exec_new_matrix1_row_tile_count_q))
                        mgmt_status_d = STATUS_ERR_BAD_IDENTITY;
                    else if (mgmt_current_generation_w == 16'hffff)
                        mgmt_status_d =
                            STATUS_ERR_GENERATION_EXHAUSTED;
                    else begin
                        mgmt_new_state_d = ST_LOADING;
                        mgmt_new_generation_d =
                            mgmt_current_generation_w + 1'b1;
                    end
                end
                MGMT_REBIND_RETAINED: begin
                    mgmt_is_mutating_d = 1'b1;
                    if ((mgmt_exec_bank_mask_q[0] ? state_q[0] : state_q[1]) !=
                        ST_RETAINED)
                        mgmt_status_d = STATUS_ERR_WRONG_STATE;
                    else if (mgmt_exec_expected_directory_generation_q !=
                             mgmt_current_generation_w)
                        mgmt_status_d = STATUS_ERR_STALE_GENERATION;
                    else if ((mgmt_exec_expected_content_handle_q !=
                              mgmt_current_content_handle_w) ||
                             (mgmt_exec_new_content_handle_q !=
                              mgmt_exec_expected_content_handle_q))
                        mgmt_status_d = STATUS_ERR_CONTENT_MISMATCH;
                    else if ((mgmt_exec_expected_stage_ticket_q != 0) ||
                             (mgmt_exec_expected_physical_bank_generation_q !=
                              mgmt_current_physical_bank_generation_w))
                        mgmt_status_d = STATUS_ERR_BAD_IDENTITY;
                    else if (!mgmt_exec_external_safe_q)
                        mgmt_status_d = STATUS_ERR_EXTERNAL_UNSAFE;
                    else if (!descriptor_valid_q[
                             mgmt_exec_bank_mask_q[1]] ||
                             !content_valid_q[mgmt_exec_bank_mask_q[1]] ||
                             (mgmt_exec_new_image_epoch_q !=
                              mgmt_current_image_epoch_w) ||
                             (mgmt_exec_new_stage_id_q !=
                              mgmt_current_stage_id_w) ||
                             (mgmt_exec_new_logical_branch_q !=
                              mgmt_current_logical_branch_w) ||
                             (mgmt_exec_new_stage_id_q > 11) ||
                             (mgmt_exec_new_stage_ticket_q == 0) ||
                             (mgmt_exec_new_content_handle_q == 0) ||
                             (mgmt_exec_new_physical_bank_generation_q == 0) ||
                             (mgmt_exec_new_matrix_mask_q !=
                              mgmt_current_matrix_mask_w) ||
                             (mgmt_exec_new_matrix0_source_count_q !=
                              mgmt_current_matrix0_source_count_w) ||
                             (mgmt_exec_new_matrix1_source_count_q !=
                              mgmt_current_matrix1_source_count_w) ||
                             (mgmt_exec_new_matrix0_row_tile_count_q !=
                              mgmt_current_matrix0_row_tile_count_w) ||
                             (mgmt_exec_new_matrix1_row_tile_count_q !=
                              mgmt_current_matrix1_row_tile_count_w) ||
                             !descriptor_shape_valid(
                              mgmt_exec_new_matrix_mask_q,
                              mgmt_exec_new_matrix0_binding_token_q,
                              mgmt_exec_new_matrix1_binding_token_q,
                              mgmt_exec_new_matrix0_source_count_q,
                              mgmt_exec_new_matrix1_source_count_q,
                              mgmt_exec_new_matrix0_row_tile_count_q,
                              mgmt_exec_new_matrix1_row_tile_count_q))
                        mgmt_status_d = STATUS_ERR_BAD_IDENTITY;
                    else begin
                        mgmt_new_state_d = ST_LOADING;
                        mgmt_new_generation_d =
                            mgmt_exec_expected_directory_generation_q;
                    end
                end
                MGMT_PUBLISH_READY: begin
                    mgmt_is_mutating_d = 1'b1;
                    if ((mgmt_exec_bank_mask_q[0] ? state_q[0] : state_q[1]) !=
                        ST_LOADING)
                        mgmt_status_d = STATUS_ERR_WRONG_STATE;
                    else if (!mgmt_exec_external_safe_q)
                        mgmt_status_d = STATUS_ERR_EXTERNAL_UNSAFE;
                    else if (!(mgmt_exec_bank_mask_q[0] ?
                               mgmt_exec_accept_causal_empty_q[0] :
                               mgmt_exec_accept_causal_empty_q[1]))
                        mgmt_status_d = STATUS_ERR_NOT_QUIESCENT;
                    else if ((mgmt_exec_expected_directory_generation_q !=
                              mgmt_current_generation_w) ||
                             (mgmt_exec_expected_content_handle_q !=
                              mgmt_current_content_handle_w) ||
                             (mgmt_exec_expected_stage_ticket_q !=
                              mgmt_current_stage_ticket_w) ||
                             (mgmt_exec_expected_physical_bank_generation_q !=
                              mgmt_current_physical_bank_generation_w))
                        mgmt_status_d = STATUS_ERR_BAD_IDENTITY;
                    else
                        mgmt_new_state_d = ST_READY;
                end
                MGMT_ACTIVATE: begin
                    mgmt_is_mutating_d = 1'b1;
                    if ((mgmt_exec_bank_mask_q[0] ? state_q[0] : state_q[1]) !=
                        ST_READY)
                        mgmt_status_d = STATUS_ERR_WRONG_STATE;
                    else if (!mgmt_exec_external_safe_q)
                        mgmt_status_d = STATUS_ERR_EXTERNAL_UNSAFE;
                    else if ((mgmt_exec_expected_directory_generation_q !=
                              mgmt_current_generation_w) ||
                             (mgmt_exec_expected_content_handle_q !=
                              mgmt_current_content_handle_w) ||
                             (mgmt_exec_expected_stage_ticket_q !=
                              mgmt_current_stage_ticket_w) ||
                             (mgmt_exec_expected_physical_bank_generation_q !=
                              mgmt_current_physical_bank_generation_w))
                        mgmt_status_d = STATUS_ERR_BAD_IDENTITY;
                    else
                        mgmt_new_state_d = ST_ACTIVE;
                end
                MGMT_BEGIN_DRAIN: begin
                    mgmt_is_mutating_d = 1'b1;
                    if (!((mgmt_exec_drain_target_q == DRAIN_INVALID) ||
                          (mgmt_exec_drain_target_q == DRAIN_RETAINED) ||
                          (mgmt_exec_drain_target_q == DRAIN_ERROR)))
                        mgmt_status_d = STATUS_ERR_BAD_DRAIN_TARGET;
                    else if (!(((mgmt_exec_bank_mask_q[0] ? state_q[0] :
                                                           state_q[1]) ==
                                ST_LOADING) ||
                               ((mgmt_exec_bank_mask_q[0] ? state_q[0] :
                                                           state_q[1]) ==
                                ST_READY) ||
                               ((mgmt_exec_bank_mask_q[0] ? state_q[0] :
                                                           state_q[1]) ==
                                ST_ACTIVE) ||
                               ((mgmt_exec_bank_mask_q[0] ? state_q[0] :
                                                           state_q[1]) ==
                                ST_RETAINED)))
                        mgmt_status_d = STATUS_ERR_WRONG_STATE;
                    else if ((mgmt_exec_expected_directory_generation_q !=
                              mgmt_current_generation_w) ||
                             (mgmt_exec_expected_content_handle_q !=
                              mgmt_current_content_handle_w) ||
                             (mgmt_exec_expected_stage_ticket_q !=
                              mgmt_current_stage_ticket_w) ||
                             (mgmt_exec_expected_physical_bank_generation_q !=
                              mgmt_current_physical_bank_generation_w))
                        mgmt_status_d = STATUS_ERR_BAD_IDENTITY;
                    else if ((mgmt_exec_drain_target_q != DRAIN_ERROR) &&
                             (mgmt_exec_bank_mask_q[0] ?
                              local_error_valid_q[0] :
                              local_error_valid_q[1]))
                        mgmt_status_d = STATUS_ERR_LOCAL_PROTOCOL;
                    else begin
                        mgmt_new_state_d = ST_DRAINING;
                    end
                end
                MGMT_FINISH_DRAIN: begin
                    mgmt_is_mutating_d = 1'b1;
                    if ((mgmt_exec_bank_mask_q[0] ? state_q[0] : state_q[1]) !=
                        ST_DRAINING)
                        mgmt_status_d = STATUS_ERR_WRONG_STATE;
                    else if ((mgmt_exec_expected_directory_generation_q !=
                              mgmt_current_generation_w) ||
                             (mgmt_exec_expected_content_handle_q !=
                              mgmt_current_content_handle_w) ||
                             (mgmt_exec_expected_stage_ticket_q !=
                              mgmt_current_stage_ticket_w) ||
                             (mgmt_exec_expected_physical_bank_generation_q !=
                              mgmt_current_physical_bank_generation_w))
                        mgmt_status_d = STATUS_ERR_BAD_IDENTITY;
                    else if (!mgmt_exec_external_safe_q)
                        mgmt_status_d = STATUS_ERR_EXTERNAL_UNSAFE;
                    else if (!(mgmt_exec_bank_mask_q[0] ?
                               mgmt_exec_accept_drain_complete_q[0] :
                               mgmt_exec_accept_drain_complete_q[1]))
                        mgmt_status_d = STATUS_ERR_NOT_QUIESCENT;
                    else if ((mgmt_exec_bank_mask_q[0] ? drain_target_q[0] :
                                                       drain_target_q[1]) ==
                             DRAIN_INVALID)
                        mgmt_new_state_d = ST_INVALID;
                    else if ((mgmt_exec_bank_mask_q[0] ? drain_target_q[0] :
                                                       drain_target_q[1]) ==
                             DRAIN_RETAINED)
                        mgmt_new_state_d = ST_RETAINED;
                    else
                        mgmt_new_state_d = ST_ERROR;
                end
                MGMT_CLEAR_ERROR: begin
                    mgmt_is_mutating_d = 1'b1;
                    if ((mgmt_exec_bank_mask_q[0] ? state_q[0] : state_q[1]) !=
                        ST_ERROR)
                        mgmt_status_d = STATUS_ERR_WRONG_STATE;
                    else if (!(mgmt_exec_bank_mask_q[0] ?
                               local_error_valid_q[0] :
                               local_error_valid_q[1]))
                        mgmt_status_d = STATUS_ERR_LOCAL_PROTOCOL;
                    else if (mgmt_exec_expected_directory_generation_q !=
                             (mgmt_exec_bank_mask_q[0] ?
                              local_error_directory_generation_q[0] :
                              local_error_directory_generation_q[1]))
                        mgmt_status_d = STATUS_ERR_STALE_GENERATION;
                    else if ((mgmt_exec_expected_content_handle_q !=
                              (mgmt_exec_bank_mask_q[0] ?
                               local_error_content_handle_q[0] :
                               local_error_content_handle_q[1])) ||
                             (mgmt_exec_expected_stage_ticket_q !=
                              (mgmt_exec_bank_mask_q[0] ?
                               local_error_stage_ticket_q[0] :
                               local_error_stage_ticket_q[1])) ||
                             (mgmt_exec_expected_physical_bank_generation_q !=
                              (mgmt_exec_bank_mask_q[0] ?
                               local_error_physical_bank_generation_q[0] :
                               local_error_physical_bank_generation_q[1])))
                        mgmt_status_d = STATUS_ERR_BAD_IDENTITY;
                    else if (mgmt_exec_bank_mask_q[0] ? reset_required_q[0] :
                                                     reset_required_q[1])
                        mgmt_status_d = STATUS_ERR_INTERNAL_STATE;
                    else if (!mgmt_exec_external_safe_q)
                        mgmt_status_d = STATUS_ERR_EXTERNAL_UNSAFE;
                    else if (!(mgmt_exec_bank_mask_q[0] ?
                               mgmt_exec_accept_causal_empty_q[0] :
                               mgmt_exec_accept_causal_empty_q[1]))
                        mgmt_status_d = STATUS_ERR_NOT_QUIESCENT;
                    else
                        mgmt_new_state_d = ST_INVALID;
                end
                default: mgmt_status_d = STATUS_ERR_BAD_OPCODE;
            endcase
        end
    end

    // Final-close request syntax/scope validation.  Exact closes alone form a
    // same-edge cut; malformed closes return a caller-local response.
    always @* begin
        force_request_status = STATUS_OK;
        force_request_exact = 1'b0;
        if (force_error_bank_mask == 2'b00)
            force_request_status = STATUS_ERR_BAD_BANK_MASK;
        else if (force_error_code == STATUS_OK)
            force_request_status = STATUS_ERR_LOCAL_PROTOCOL;
        else if (force_error_data_untrusted &&
                 (force_error_code == STATUS_ERR_ABORTED))
            force_request_status = STATUS_ERR_LOCAL_PROTOCOL;
        else if (!force_error_data_untrusted &&
                 !force_error_causal_producers_drained)
            force_request_status = STATUS_ERR_EXTERNAL_UNSAFE;
        else if ((force_error_bank_mask[0] &&
                  (state_q[0] == ST_INVALID)) ||
                 (force_error_bank_mask[1] &&
                  (state_q[1] == ST_INVALID)))
            force_request_status = STATUS_ERR_WRONG_STATE;
        else if ((force_error_bank_mask[0] &&
                  (((!descriptor_valid_q[0]) &&
                   (state_q[0] != ST_SCRUBBING)) ||
                   (force_error_directory_generation[15:0] !=
                    effective_generation0_w) ||
                   (force_error_stage_ticket[31:0] !=
                    effective_stage_ticket0_w) ||
                   (force_error_content_handle[31:0] !=
                    effective_content_handle0_w) ||
                   (force_error_physical_bank_generation[31:0] !=
                    effective_physical_bank_generation0_w))) ||
                 (force_error_bank_mask[1] &&
                  (((!descriptor_valid_q[1]) &&
                   (state_q[1] != ST_SCRUBBING)) ||
                   (force_error_directory_generation[31:16] !=
                    effective_generation1_w) ||
                   (force_error_stage_ticket[63:32] !=
                    effective_stage_ticket1_w) ||
                   (force_error_content_handle[63:32] !=
                    effective_content_handle1_w) ||
                   (force_error_physical_bank_generation[63:32] !=
                    effective_physical_bank_generation1_w))))
            force_request_status = STATUS_ERR_BAD_IDENTITY;
        else begin
            force_request_status = STATUS_OK;
            force_request_exact = 1'b1;
        end
    end

    // Rich first-error merge.  Every selector below reads only source-local
    // registered event flags and registered raw snapshots.  In particular it
    // never references request ready, admission claims, or the live
    // preexisting fence.  The live shallow fence remains a separate same-edge
    // safety path; this registered merge is only the held error/status path.
    always @* begin
        fault_now = 2'b00;
        for (i = 0; i < 2; i = i + 1) begin
            fault_code_now[i] = STATUS_OK;
            fault_source_now[i] = ERROR_SOURCE_INTERNAL;
            fault_detail_now[i] = 32'd0;
            fault_reset_now[i] = 1'b0;
        end

        // Bank 0 priority: internal order, physical response, directory
        // result, publication, accepted compute request, generation exhaust.
        if (fault_source_flags_q[0] != 0) begin
            fault_now[0] = 1'b1;
            if (fault_source_flags_q[0][5]) begin
                fault_code_now[0] = STATUS_ERR_INTERNAL_STATE;
                fault_source_now[0] = ERROR_SOURCE_INTERNAL;
                fault_detail_now[0] = 32'h4f524452;
                fault_reset_now[0] = 1'b1;
            end else if (fault_source_flags_q[0][4]) begin
                fault_now[0] = 1'b1;
                fault_code_now[0] = fault_bank_status_snapshot_q[0];
                fault_source_now[0] = ERROR_SOURCE_BANK_RESPONSE;
                fault_detail_now[0] =
                    {16'd0, fault_bank_tag_snapshot_q[0]};
                fault_reset_now[0] = fault_bank_reset_snapshot_q[0];
            end else if (fault_source_flags_q[0][3]) begin
                fault_code_now[0] = fault_dir_status_snapshot_q;
                fault_source_now[0] = ERROR_SOURCE_LOOKUP;
                fault_detail_now[0] = fault_dir_detail_snapshot_q;
            end else if (fault_source_flags_q[0][2]) begin
                fault_code_now[0] = fault_pub_status_snapshot_q;
                fault_source_now[0] = ERROR_SOURCE_PUBLICATION;
                fault_detail_now[0] = fault_pub_detail_snapshot_q;
            end else if (fault_source_flags_q[0][1]) begin
                fault_code_now[0] = fault_lookup_status_snapshot_q;
                fault_source_now[0] = ERROR_SOURCE_LOOKUP;
                fault_detail_now[0] = fault_lookup_detail_snapshot_q;
            end else begin
                fault_code_now[0] = STATUS_ERR_GENERATION_EXHAUSTED;
                fault_source_now[0] = ERROR_SOURCE_MANAGEMENT;
                fault_detail_now[0] = 32'h0000ffff;
                fault_reset_now[0] = 1'b1;
            end
        end

        // Bank 1 uses the identical independent fixed priority chain.
        if (fault_source_flags_q[1] != 0) begin
            fault_now[1] = 1'b1;
            if (fault_source_flags_q[1][5]) begin
                fault_code_now[1] = STATUS_ERR_INTERNAL_STATE;
                fault_source_now[1] = ERROR_SOURCE_INTERNAL;
                fault_detail_now[1] = 32'h4f524452;
                fault_reset_now[1] = 1'b1;
            end else if (fault_source_flags_q[1][4]) begin
                fault_code_now[1] = fault_bank_status_snapshot_q[1];
                fault_source_now[1] = ERROR_SOURCE_BANK_RESPONSE;
                fault_detail_now[1] =
                    {16'd0, fault_bank_tag_snapshot_q[1]};
                fault_reset_now[1] = fault_bank_reset_snapshot_q[1];
            end else if (fault_source_flags_q[1][3]) begin
                fault_code_now[1] = fault_dir_status_snapshot_q;
                fault_source_now[1] = ERROR_SOURCE_LOOKUP;
                fault_detail_now[1] = fault_dir_detail_snapshot_q;
            end else if (fault_source_flags_q[1][2]) begin
                fault_code_now[1] = fault_pub_status_snapshot_q;
                fault_source_now[1] = ERROR_SOURCE_PUBLICATION;
                fault_detail_now[1] = fault_pub_detail_snapshot_q;
            end else if (fault_source_flags_q[1][1]) begin
                fault_code_now[1] = fault_lookup_status_snapshot_q;
                fault_source_now[1] = ERROR_SOURCE_LOOKUP;
                fault_detail_now[1] = fault_lookup_detail_snapshot_q;
            end else begin
                fault_code_now[1] = STATUS_ERR_GENERATION_EXHAUSTED;
                fault_source_now[1] = ERROR_SOURCE_MANAGEMENT;
                fault_detail_now[1] = 32'h0000ffff;
                fault_reset_now[1] = 1'b1;
            end
        end
    end

    // Final close only needs faults discovered by work that the bank already
    // owns.  Keep this bank-local classifier independent of lookup/management
    // admission-time faults: exact final close excludes those new fires on its
    // target, while an in-flight response/result must still outrank the owner
    // abort/fatal code on the same edge.
    // The fatal decision is a one-bit bank-local predicate.  Keep it outside
    // the rich close-code priority mux so a live BRAM result never reaches a
    // fatal register through status selection and an eight-bit comparison.
    assign owned_close_fault_now[0] = internal_order_fault ||
        bank0_rsp_observed_fatal || dir_fast_fatal0_w || pub_fast_fatal0_w;
    assign owned_close_fault_now[1] = internal_order_fault ||
        bank1_rsp_observed_fatal || dir_fast_fatal1_w || pub_fast_fatal1_w;

    always @* begin
        owned_close_fault_code[0] = STATUS_OK;
        owned_close_fault_code[1] = STATUS_OK;
        if (internal_order_fault) begin
            owned_close_fault_code[0] = STATUS_ERR_INTERNAL_STATE;
            owned_close_fault_code[1] = STATUS_ERR_INTERNAL_STATE;
        end else begin
            if (bank0_rsp_observed_fatal) begin
                owned_close_fault_code[0] = bank0_rsp_observed_status;
            end else if (dir_fast_fatal0_w) begin
                owned_close_fault_code[0] = dir_result_status;
            end else if (pub_fast_fatal0_w) begin
                owned_close_fault_code[0] = publish_result_status;
            end

            if (bank1_rsp_observed_fatal) begin
                owned_close_fault_code[1] = bank1_rsp_observed_status;
            end else if (dir_fast_fatal1_w) begin
                owned_close_fault_code[1] = dir_result_status;
            end else if (pub_fast_fatal1_w) begin
                owned_close_fault_code[1] = publish_result_status;
            end
        end
    end

    assign bank0_close_code = owned_close_fault_now[0] ?
        owned_close_fault_code[0] :
        (local_error_valid_q[0] ? local_error_code_q[0] :
         (fault_now[0] ? fault_code_now[0] :
         (close_pending_q ? close_code_q[0] : force_error_code)));
    assign bank1_close_code = owned_close_fault_now[1] ?
        owned_close_fault_code[1] :
        (local_error_valid_q[1] ? local_error_code_q[1] :
         (fault_now[1] ? fault_code_now[1] :
         (close_pending_q ? close_code_q[1] : force_error_code)));
    assign bank0_close_fatal_w = owned_close_fault_now[0] ? 1'b1 :
        (local_error_valid_q[0] ?
         (local_error_code_q[0] != STATUS_ERR_ABORTED) :
         (fault_now[0] ?
          (fault_code_now[0] != STATUS_ERR_ABORTED) :
          (close_pending_q ?
           (close_code_q[0] != STATUS_ERR_ABORTED) :
           (force_error_code != STATUS_ERR_ABORTED))));
    assign bank1_close_fatal_w = owned_close_fault_now[1] ? 1'b1 :
        (local_error_valid_q[1] ?
         (local_error_code_q[1] != STATUS_ERR_ABORTED) :
         (fault_now[1] ?
          (fault_code_now[1] != STATUS_ERR_ABORTED) :
          (close_pending_q ?
           (close_code_q[1] != STATUS_ERR_ABORTED) :
           (force_error_code != STATUS_ERR_ABORTED))));
    assign publication_close_code = pub_exec_bank_q ? bank1_close_code :
                                                       bank0_close_code;

    // If an already-owned operation discovers a higher-priority fault on the
    // exact final-close edge, that fault (rather than the owner abort/fatal
    // code) is the terminal status for a bank response consumed on the same
    // edge.  This selection is downstream of fault detection and therefore
    // does not feed bank-response classification or any RAM/admission signal.
    assign bank_response_close_selected = expected_bank_rsp_fire &&
        ((close_pending_q &&
          (response_bank_id ? close_bank_mask_q[1] :
                              close_bank_mask_q[0])) ||
         (force_error_fire && force_request_exact &&
          (response_bank_id ? force_error_bank_mask[1] :
                              force_error_bank_mask[0])));
    assign bank_response_close_fault_override =
        bank_response_close_selected &&
        (response_bank_id ? owned_close_fault_now[1] :
                            owned_close_fault_now[0]);
    assign bank_response_terminal_status =
        bank_response_close_fault_override ?
        response_close_code : bank_response_status;
    // Every owned same-edge close override is, by construction, a fatal
    // internal/directory/publication/bank-response condition; ERR_ABORTED can
    // only come from the non-override owner close path.  Express the fatal bit
    // directly so the rich eight-bit close-code selection does not sit on the
    // one-bit lookup response timing path.
    assign bank_response_terminal_fatal =
        bank_response_close_fault_override || bank_response_fatal;
    assign bank_response_terminal_data =
        (bank_response_terminal_status == STATUS_OK) ?
        bank_response_data : 128'd0;

    // The stored-state consistency check excludes transient same-edge next
    // state; a mismatch is therefore a genuine ownership failure.
    // Three-entry occupancy has a two-level exact boolean encoding:
    // population bit 0 is parity and bit 1 is the three-input majority.
    // Avoiding a synthesized multioperand adder keeps this always-live safety
    // monitor out of the admission and first-error critical paths.
    // WAIT_DIR is owned physically by the one-entry synchronous directory
    // pipeline.  Keeping that transient ownership out of the stored slot
    // state prevents the same-edge admission fence from driving every slot
    // state D input, while this virtual mask preserves the exact population,
    // ordering and close semantics.
    assign dir_wait_mask_w = dir_pipe_valid_q ?
                             dir_pipe_owner_onehot_q : 3'b000;
    assign slot_live_w = {(slot_state_q[2] != SLOT_FREE),
                          (slot_state_q[1] != SLOT_FREE),
                          (slot_state_q[0] != SLOT_FREE)} |
                         dir_wait_mask_w;
    assign slot_population_fault_w =
        !lookup_population_valid(lookup_count_q, slot_live_w);
    assign bank_ref_count_sum_w =
        {1'b0, bank0_ref_count_q} + {1'b0, bank1_ref_count_q};
    assign bank_ref_count_fault_w =
        (bank_ref_count_sum_w != {1'b0, lookup_count_q}) ||
        (bank0_ref_count_q > 3) || (bank1_ref_count_q > 3);
    assign bank0_wait_slot_mask_w =
        {((slot_state_q[2] == SLOT_BANK_WAIT) && !slot_bank_q[2]),
         ((slot_state_q[1] == SLOT_BANK_WAIT) && !slot_bank_q[1]),
         ((slot_state_q[0] == SLOT_BANK_WAIT) && !slot_bank_q[0])};
    assign bank1_wait_slot_mask_w =
        {((slot_state_q[2] == SLOT_BANK_WAIT) && slot_bank_q[2]),
         ((slot_state_q[1] == SLOT_BANK_WAIT) && slot_bank_q[1]),
         ((slot_state_q[0] == SLOT_BANK_WAIT) && slot_bank_q[0])};
    assign bank0_expect_slot_mask_w =
        (bank0_expect_count_q == 0) ? 3'b000 :
        (bank0_expect_count_q == 1) ?
        slot_onehot(bank0_expect_head_slot_w) :
        (slot_onehot(bank0_expect_slot_q[0]) |
         slot_onehot(bank0_expect_slot_q[1]));
    assign bank1_expect_slot_mask_w =
        (bank1_expect_count_q == 0) ? 3'b000 :
        (bank1_expect_count_q == 1) ?
        slot_onehot(bank1_expect_head_slot_w) :
        (slot_onehot(bank1_expect_slot_q[0]) |
         slot_onehot(bank1_expect_slot_q[1]));
    assign bank_expect_owner_fault_w =
        (bank0_expect_slot_mask_w != bank0_wait_slot_mask_w) ||
        (bank1_expect_slot_mask_w != bank1_wait_slot_mask_w) ||
        !lookup_population_valid(bank0_expect_count_q,
                                 bank0_expect_slot_mask_w) ||
        !lookup_population_valid(bank1_expect_count_q,
                                 bank1_expect_slot_mask_w);
    assign dir_pipe_owner_fault_w = dir_pipe_valid_q &&
        !(((dir_pipe_owner_onehot_q == 3'b001) &&
           (slot_state_q[0] == SLOT_FREE)) ||
          ((dir_pipe_owner_onehot_q == 3'b010) &&
           (slot_state_q[1] == SLOT_FREE)) ||
          ((dir_pipe_owner_onehot_q == 3'b100) &&
           (slot_state_q[2] == SLOT_FREE)));
    assign lookup_output_owner_fault_w = lookup_out_valid_q &&
        ((lookup_count_q == 0) ||
         !(((lookup_out_owner_onehot_q == 3'b001) &&
            (slot_state_q[0] == SLOT_OUTPUT)) ||
           ((lookup_out_owner_onehot_q == 3'b010) &&
            (slot_state_q[1] == SLOT_OUTPUT)) ||
           ((lookup_out_owner_onehot_q == 3'b100) &&
            (slot_state_q[2] == SLOT_OUTPUT))));
    assign internal_order_fault = slot_population_fault_w ||
        bank_ref_count_fault_w ||
        bank_expect_owner_fault_w ||
        (lookup_head_q == 2'd3) || (lookup_tail_q == 2'd3) ||
        (bank0_expect_count_q > 2) || (bank1_expect_count_q > 2) ||
        dir_pipe_owner_fault_w || lookup_output_owner_fault_w;

    // Admission rules.  A valid management/final-close request has priority
    // on its target.  Management admission is transport-only: a fault found
    // on that edge is captured with the command and fences its later mutation
    // independent of fault-event retirement.
    // A SCRUB candidate is an accepted causal management transaction, but its
    // lifecycle state is intentionally still INVALID.  Hold final-close for
    // this single registered validation edge so it cannot be misclassified as
    // a caller-local wrong-state request.  On the next edge the candidate has
    // either terminalized or become authoritative SCRUBBING work.
    assign force_error_ready = rst_n &&
        (!scrub_candidate_valid_q || !force_error_valid ||
         ((force_error_bank_mask & mgmt_active_bank_mask_q) == 0)) &&
        !close_pending_q && !force_rsp_valid_q;
    assign force_error_fire = force_error_valid && force_error_ready;
    // This shallow transport-capacity term also arbitrates management ahead
    // of same-bank lookup/publication.  Keep it independent of the projected
    // fault fence: a same-edge fault still lowers mgmt_req_ready below, while
    // the data channels are independently fenced on that same edge.  This
    // avoids routing the directory-result fault path through management ready
    // and back into the lookup/publication arbitration cone.
    assign mgmt_raw_priority_available_w = rst_n && !mgmt_exec_valid_q &&
                            !mgmt_decision_valid_q &&
                            !descriptor_install_pending_q[0] &&
                            !descriptor_install_pending_q[1] &&
                            !scrub_candidate_valid_q && !mgmt_active_q &&
                            !mgmt_rsp_valid_q &&
                            !close_pending_q && !force_rsp_valid_q &&
                            !(force_error_valid && force_error_ready);
    // Speculatively sample management payload whenever the sole transport
    // position is available.  This preview deliberately excludes the
    // projected same-edge fault fence; only mgmt_req_fire below grants
    // ownership.  An unaccepted preview is therefore architecturally inert.
    assign mgmt_preview_capture_w = mgmt_req_valid &&
                                    mgmt_raw_priority_available_w;
    assign mgmt_activation_opcode_w =
        (mgmt_req_opcode == MGMT_CLAIM_FRESH) ||
        (mgmt_req_opcode == MGMT_REBIND_RETAINED) ||
        (mgmt_req_opcode == MGMT_PUBLISH_READY) ||
        (mgmt_req_opcode == MGMT_ACTIVATE);
    assign mgmt_activation_target0_w = mgmt_activation_opcode_w &&
                                       (mgmt_req_bank_mask == 2'b01);
    assign mgmt_activation_target1_w = mgmt_activation_opcode_w &&
                                       (mgmt_req_bank_mask == 2'b10);
    // Registered/sticky fences are folded into a static-ready term.  The
    // live BRAM-result fence is applied only in the final target-specific
    // gate below, keeping the mandatory same-edge cut shallow.
    assign mgmt_ready_without_preexisting_w =
        mgmt_raw_priority_available_w &&
        !(mgmt_activation_target0_w && current_fault_fence_w[0]) &&
        !(mgmt_activation_target1_w && current_fault_fence_w[1]);
    assign mgmt_preexisting_activation_fence_w =
        (mgmt_activation_target0_w && preexisting_fence_now[0]) ||
        (mgmt_activation_target1_w && preexisting_fence_now[1]);
    assign mgmt_req_ready = mgmt_ready_without_preexisting_w &&
                            !mgmt_preexisting_activation_fence_w;
    assign mgmt_req_fire = mgmt_req_valid && mgmt_req_ready;

    // A clean-static SCRUB handshake reserves a registered, non-authoritative
    // candidate.  The C0 live physical-fault decision is sampled separately;
    // no BRAM-result signal reaches lifecycle, epoch-authority, or active-work
    // register D inputs.  The candidate is the physical landing position that
    // fences younger work until C1 promotion or fatal terminalization.
    assign scrub_candidate_accept_w = mgmt_req_fire &&
        (mgmt_req_opcode == MGMT_SCRUB) &&
        (scrub_direct_status == STATUS_OK);

    // First-error capture must not feed back through the very ready signals
    // that an already-visible fault fences.  These raw acceptance candidates
    // omit projected same-edge faults; the rich classifier below gives those
    // pre-existing faults higher priority, so an unaccepted younger request
    // can never replace them.  Registered/current fences, close and channel
    // ownership are still respected.
    assign lookup_accept_fault_candidate_w = lookup_admission_claim &&
        lookup_req_kind && (lookup_pre_status != STATUS_OK) &&
        !close_fence_w[lookup_res_selected_bank_id] &&
        !current_fault_fence_w[lookup_res_selected_bank_id] &&
        !management_fence_w[lookup_res_selected_bank_id] &&
        !(force_error_fire &&
          force_error_bank_mask[lookup_res_selected_bank_id]) &&
        !(mgmt_raw_priority_available_w && mgmt_req_valid &&
          mgmt_req_bank_mask[lookup_res_selected_bank_id]);
    assign mgmt_generation_fault_candidate_w = mgmt_exec_valid_q &&
        !force_error_fire &&
        ((close_pending_q & mgmt_exec_bank_mask_q) == 0) &&
        ((mgmt_exec_fault_collision_q & mgmt_exec_bank_mask_q) == 0) &&
        ((mgmt_late_fault_now_w & mgmt_exec_bank_mask_q) == 0) &&
        (mgmt_exec_opcode_q == MGMT_CLAIM_FRESH) &&
        ((mgmt_exec_bank_mask_q == 2'b01) ||
         (mgmt_exec_bank_mask_q == 2'b10)) &&
        !current_fault_fence_w[mgmt_exec_bank_mask_q[1]] &&
        ((mgmt_exec_bank_mask_q[0] ? state_q[0] : state_q[1]) ==
         ST_INVALID) &&
        (mgmt_exec_expected_directory_generation_q ==
         mgmt_current_generation_w) &&
        (mgmt_exec_expected_content_handle_q == 0) &&
        (mgmt_exec_expected_stage_ticket_q == 0) &&
        (mgmt_exec_expected_physical_bank_generation_q == 0) &&
        !(mgmt_exec_bank_mask_q[0] ? scrub_required_q[0] :
                                  scrub_required_q[1]) &&
        (mgmt_exec_bank_mask_q[0] ? last_scrub_epoch_valid_q[0] :
                                 last_scrub_epoch_valid_q[1]) &&
        (mgmt_exec_new_image_epoch_q ==
         (mgmt_exec_bank_mask_q[0] ? last_scrub_epoch_q[0] :
                                  last_scrub_epoch_q[1])) &&
        mgmt_exec_external_safe_q && (mgmt_exec_new_stage_id_q <= 11) &&
        (mgmt_exec_new_stage_ticket_q != 0) &&
        (mgmt_exec_new_content_handle_q != 0) &&
        (mgmt_exec_new_physical_bank_generation_q != 0) &&
        descriptor_shape_valid(
            mgmt_exec_new_matrix_mask_q,
            mgmt_exec_new_matrix0_binding_token_q,
            mgmt_exec_new_matrix1_binding_token_q,
            mgmt_exec_new_matrix0_source_count_q,
            mgmt_exec_new_matrix1_source_count_q,
            mgmt_exec_new_matrix0_row_tile_count_q,
            mgmt_exec_new_matrix1_row_tile_count_q) &&
        (mgmt_current_generation_w == 16'hffff);

    assign lookup_ready_without_preexisting_w = lookup_admission_claim &&
        !close_fence_w[lookup_res_selected_bank_id] &&
        !current_fault_fence_w[lookup_res_selected_bank_id] &&
        !management_fence_w[lookup_res_selected_bank_id] &&
        !(force_error_fire &&
          force_error_bank_mask[lookup_res_selected_bank_id]) &&
        !(mgmt_raw_priority_available_w && mgmt_req_valid &&
          mgmt_req_bank_mask[lookup_res_selected_bank_id]);
    assign lookup_preexisting_fence_selected_w =
        lookup_res_selected_bank_id ? preexisting_fence_now[1] :
                                      preexisting_fence_now[0];
    assign lookup_req_ready = lookup_ready_without_preexisting_w &&
                              !lookup_preexisting_fence_selected_w;
    assign lookup_req_fire = lookup_req_valid && lookup_req_ready;

    assign publish_ready_without_preexisting_w = publish_admission_claim &&
        !close_fence_w[publish_req_bank_id] &&
        !current_fault_fence_w[publish_req_bank_id] &&
        !management_fence_w[publish_req_bank_id] &&
        !(force_error_fire && force_error_bank_mask[publish_req_bank_id]) &&
        !(mgmt_raw_priority_available_w && mgmt_req_valid &&
          mgmt_req_bank_mask[publish_req_bank_id]) &&
        !(lookup_admission_claim &&
          (lookup_res_selected_bank_id == publish_req_bank_id));
    assign publish_preexisting_fence_selected_w = publish_req_bank_id ?
        preexisting_fence_now[1] : preexisting_fence_now[0];
    assign publish_req_ready = publish_ready_without_preexisting_w &&
                               !publish_preexisting_fence_selected_w;
    assign publish_req_fire = publish_req_valid && publish_req_ready;

    // RAM ports.  No target ever reads and writes on the same edge.
    // C1 address zero belongs to the non-authoritative candidate.  A fault
    // already visible on C0 suppresses even that harmless write.  A fault
    // first arriving on C1 may coincide with address zero exactly as before;
    // its registered fence suppresses address one and the active causal path
    // then terminalizes with the rich first-fatal status.
    wire scrub_candidate_write0 = rst_n && scrub_candidate_valid_q &&
        (mgmt_active_opcode_q == MGMT_SCRUB) &&
        mgmt_active_bank_mask_q[0] &&
        (scrub_candidate_initial_fault_q == 2'b00);
    wire scrub_candidate_write1 = rst_n && scrub_candidate_valid_q &&
        (mgmt_active_opcode_q == MGMT_SCRUB) &&
        mgmt_active_bank_mask_q[1] &&
        (scrub_candidate_initial_fault_q == 2'b00);
    wire force_intersects_active_scrub = force_error_fire &&
        ((force_error_bank_mask & mgmt_active_bank_mask_q) != 0);
    wire scrub_active_write0 = mgmt_active_q &&
        (mgmt_active_opcode_q == MGMT_SCRUB) &&
        mgmt_active_bank_mask_q[0] &&
        !fault_now[0] &&
        !force_intersects_active_scrub;
    wire scrub_active_write1 = mgmt_active_q &&
        (mgmt_active_opcode_q == MGMT_SCRUB) &&
        mgmt_active_bank_mask_q[1] &&
        !fault_now[1] &&
        !force_intersects_active_scrub;
    wire scrub_write0 = scrub_candidate_write0 || scrub_active_write0;
    wire scrub_write1 = scrub_candidate_write1 || scrub_active_write1;
    wire pub_write0 = pub_commit_now && !pub_exec_bank_q;
    wire pub_write1 = pub_commit_now && pub_exec_bank_q;
    wire mem0_write_enable = scrub_write0 || pub_write0;
    wire mem1_write_enable = scrub_write1 || pub_write1;
    wire [9:0] mem0_write_address = scrub_write0 ? scrub_address_q :
        {pub_exec_matrix_id_q, pub_exec_source_index_q[8:0]};
    wire [9:0] mem1_write_address = scrub_write1 ? scrub_address_q :
        {pub_exec_matrix_id_q, pub_exec_source_index_q[8:0]};
    wire [31:0] directory_publish_entry =
        {2'b11, pub_exec_directory_generation_q, 1'b0,
         pub_exec_slot_base_q};
    wire [31:0] mem0_write_data = scrub_write0 ? 32'd0 :
        directory_publish_entry;
    wire [31:0] mem1_write_data = scrub_write1 ? 32'd0 :
        directory_publish_entry;

    // Read ports are claimed speculatively after all trusted identity and
    // bounds checks, but without the current-cycle fault/management admission
    // fence.  Thus an invalid external key can never reach a truncated RAM
    // address.  A later same-edge fault can still suppress ready/fire and all
    // metadata advance; the resulting checked but unowned read is harmless.
    // This preserves the same-edge admission fence without routing physical
    // response fault logic back into a BRAM control pin.
    assign ram_write_owner0 =
        ((scrub_candidate_valid_q || mgmt_active_q) &&
         (mgmt_active_opcode_q == MGMT_SCRUB) &&
         mgmt_active_bank_mask_q[0]) ||
        (pub_exec_valid_q && (pub_exec_pre_status_q == STATUS_OK) &&
         !pub_exec_bank_q);
    assign ram_write_owner1 =
        ((scrub_candidate_valid_q || mgmt_active_q) &&
         (mgmt_active_opcode_q == MGMT_SCRUB) &&
         mgmt_active_bank_mask_q[1]) ||
        (pub_exec_valid_q && (pub_exec_pre_status_q == STATUS_OK) &&
         pub_exec_bank_q);
    assign lookup_credit_claim = (lookup_count_q < 3) || lookup_rsp_fire;
    assign lookup_state_claim = lookup_req_kind ?
        (state_q[lookup_res_selected_bank_id] == ST_ACTIVE) :
        ((state_q[lookup_res_selected_bank_id] == ST_LOADING) ||
         (state_q[lookup_res_selected_bank_id] == ST_READY) ||
         (state_q[lookup_res_selected_bank_id] == ST_ACTIVE));
    // Admission and physical RAM use are intentionally separate.  Port
    // availability is checked conservatively for every request, so neither
    // ready nor same-bank priority depends on the wide pre-status classifier.
    // Once admitted, a malformed request still reserves its ordered terminal
    // response, while only a fully checked key activates the synchronous RAM.
    assign lookup_admission_claim = rst_n && lookup_req_valid &&
        lookup_credit_claim && lookup_state_claim &&
        !(lookup_res_selected_bank_id ? ram_write_owner1 :
                                         ram_write_owner0);
    assign lookup_port_claim = lookup_admission_claim && lookup_pre_read;
    assign lookup_port_claim0 = lookup_port_claim &&
                                !lookup_res_selected_bank_id;
    assign lookup_port_claim1 = lookup_port_claim &&
                                 lookup_res_selected_bank_id;

    // Lookup owns a same-bank speculative read.  Publication may claim the
    // other port, or a same-bank port only when lookup did not claim it.  Thus
    // every accepted publication necessarily receives its synchronous
    // pre-read, while cross-bank lookup/publication remains concurrent.
    assign publish_port_claim = publish_admission_claim &&
        (publish_pre_status == STATUS_OK) &&
        !(lookup_admission_claim &&
          (lookup_res_selected_bank_id == publish_req_bank_id));
    assign publish_port_claim0 = publish_port_claim && !publish_req_bank_id;
    assign publish_port_claim1 = publish_port_claim && publish_req_bank_id;

    // Publication admission likewise uses only lifecycle/credit/port-owner
    // state.  Bad identity/bounds/proof still enters the execution position
    // without reading or writing a truncated directory address.  A lookup
    // admission on the same bank remains the sole arbitration winner.
    assign publish_admission_claim = rst_n && publish_req_valid &&
        !pub_exec_valid_q && !pub_rsp_valid_q &&
        (state_q[publish_req_bank_id] == ST_LOADING) &&
        !(publish_req_bank_id ? ram_write_owner1 : ram_write_owner0);

    wire mem0_read_enable = lookup_port_claim0 || publish_port_claim0;
    wire mem1_read_enable = lookup_port_claim1 || publish_port_claim1;
    wire [9:0] mem0_read_address =
        lookup_port_claim0 ? lookup_key : pub_key;
    wire [9:0] mem1_read_address =
        lookup_port_claim1 ? lookup_key : pub_key;

    // Canonical same-clock simple-dual-port templates: one clocked process
    // contains the full-word write port and registered synchronous-read port
    // for each directory.  This is the Vivado 2018.3 inference form already
    // proven by parameter_weight_bank; the payload arrays are never reset.
    always @(posedge clk) begin
        if (mem0_write_enable)
            directory_mem0[mem0_write_address] <= mem0_write_data;
        if (mem0_read_enable)
            mem0_read_data_q <= directory_mem0[mem0_read_address];
    end

    always @(posedge clk) begin
        if (mem1_write_enable)
            directory_mem1[mem1_write_address] <= mem1_write_data;
        if (mem1_read_enable)
            mem1_read_data_q <= directory_mem1[mem1_read_address];
    end

    // Same-edge ready gating uses fast_fault_now_w directly.  Starting on the
    // following cycle this set-dominant bridge maintains the fence until the
    // registered rich first-error record has taken ownership.  Continuous
    // faults keep it set; clearing therefore cannot create an authority gap.
    always @(posedge clk) begin
        if (!rst_n) begin
            fast_fault_bridge_q <= 2'b00;
        end else begin
            if (fast_fault_now_w[0])
                fast_fault_bridge_q[0] <= 1'b1;
            else if (fast_fault_bridge_q[0] &&
                     local_error_valid_q[0] && !fault_now[0])
                fast_fault_bridge_q[0] <= 1'b0;

            if (fast_fault_now_w[1])
                fast_fault_bridge_q[1] <= 1'b1;
            else if (fast_fault_bridge_q[1] &&
                     local_error_valid_q[1] && !fault_now[1])
                fast_fault_bridge_q[1] <= 1'b0;
        end
    end

    // Control/register implementation follows.  Payload RAM remains outside
    // the reset branch above.
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < 2; i = i + 1) begin
                state_q[i] <= ST_INVALID;
                drain_target_q[i] <= DRAIN_INVALID;
                generation_q[i] <= 16'd0;
                generation_initialized_q[i] <= 1'b0;
                descriptor_valid_q[i] <= 1'b0;
                lease_authority_valid_q[i] <= 1'b0;
                content_valid_q[i] <= 1'b0;
                scrub_required_q[i] <= 1'b1;
                last_scrub_epoch_valid_q[i] <= 1'b0;
                last_scrub_epoch_q[i] <= 32'd0;
                committed_count_q[i] <= 10'd0;
                descriptor_install_pending_q[i] <= 1'b0;
                descriptor_install_claim_q[i] <= 1'b0;
                image_epoch_q[i] <= 32'd0;
                stage_id_q[i] <= 4'd0;
                stage_ticket_q[i] <= 32'd0;
                stage_ticket_clear_pending_q[i] <= 1'b0;
                logical_branch_q[i] <= 2'd0;
                context_generation_q[i] <= 32'd0;
                content_handle_q[i] <= 32'd0;
                physical_bank_generation_q[i] <= 32'd0;
                cancellation_epoch_q[i] <= 32'd0;
                matrix_mask_q[i] <= 2'd0;
                matrix0_binding_token_q[i] <= 32'd0;
                matrix1_binding_token_q[i] <= 32'd0;
                matrix0_source_count_q[i] <= 10'd0;
                matrix1_source_count_q[i] <= 10'd0;
                matrix0_row_tile_count_q[i] <= 6'd0;
                matrix1_row_tile_count_q[i] <= 6'd0;
                begin_drain_rsp_retired_q[i] <= 1'b0;
                local_error_valid_q[i] <= 1'b0;
                local_error_code_q[i] <= STATUS_OK;
                local_error_source_q[i] <= 3'd0;
                local_error_detail_q[i] <= 32'd0;
                local_error_directory_generation_q[i] <= 16'd0;
                local_error_physical_bank_generation_q[i] <= 32'd0;
                local_error_stage_ticket_q[i] <= 32'd0;
                local_error_content_handle_q[i] <= 32'd0;
                reset_required_q[i] <= 1'b0;
                fault_fence_q[i] <= 1'b0;
                fault_event_pending_q[i] <= 1'b0;
                fault_source_flags_q[i] <= 6'd0;
            end
            mgmt_active_q <= 1'b0;
            mgmt_active_opcode_q <= 4'd0;
            mgmt_active_bank_mask_q <= 2'd0;
            mgmt_active_image_epoch_q <= 32'd0;
            mgmt_active_tag_q <= 16'd0;
            scrub_address_q <= 10'd0;
            scrub_candidate_valid_q <= 1'b0;
            scrub_candidate_initial_fault_q <= 2'b00;
            mgmt_exec_valid_q <= 1'b0;
            mgmt_exec_opcode_q <= 4'd0;
            mgmt_exec_bank_mask_q <= 2'd0;
            mgmt_exec_drain_target_q <= 2'd0;
            mgmt_exec_expected_directory_generation_q <= 16'd0;
            mgmt_exec_expected_content_handle_q <= 32'd0;
            mgmt_exec_expected_stage_ticket_q <= 32'd0;
            mgmt_exec_expected_physical_bank_generation_q <= 32'd0;
            mgmt_exec_new_image_epoch_q <= 32'd0;
            mgmt_exec_new_stage_id_q <= 4'd0;
            mgmt_exec_new_stage_ticket_q <= 32'd0;
            mgmt_exec_new_logical_branch_q <= 2'd0;
            mgmt_exec_new_context_generation_q <= 32'd0;
            mgmt_exec_new_content_handle_q <= 32'd0;
            mgmt_exec_new_physical_bank_generation_q <= 32'd0;
            mgmt_exec_new_cancellation_epoch_q <= 32'd0;
            mgmt_exec_new_matrix_mask_q <= 2'd0;
            mgmt_exec_new_matrix0_binding_token_q <= 32'd0;
            mgmt_exec_new_matrix1_binding_token_q <= 32'd0;
            mgmt_exec_new_matrix0_source_count_q <= 10'd0;
            mgmt_exec_new_matrix1_source_count_q <= 10'd0;
            mgmt_exec_new_matrix0_row_tile_count_q <= 6'd0;
            mgmt_exec_new_matrix1_row_tile_count_q <= 6'd0;
            mgmt_exec_external_safe_q <= 1'b0;
            mgmt_exec_tag_q <= 16'd0;
            mgmt_exec_accept_causal_empty_q <= 2'd0;
            mgmt_exec_accept_drain_complete_q <= 2'd0;
            mgmt_exec_fault_collision_q <= 2'd0;
            mgmt_decision_valid_q <= 1'b0;
            mgmt_decision_status_q <= STATUS_OK;
            mgmt_decision_new_state_q <= ST_INVALID;
            mgmt_decision_new_generation_q <= 16'd0;
            mgmt_decision_mutating_q <= 1'b0;
            mgmt_rsp_valid_q <= 1'b0;
            mgmt_rsp_state_q <= 6'd0;
            mgmt_rsp_status_q <= STATUS_OK;
            mgmt_rsp_mutating_q <= 1'b0;
            close_pending_q <= 1'b0;
            close_bank_mask_q <= 2'd0;
            close_code_q[0] <= STATUS_OK;
            close_code_q[1] <= STATUS_OK;
            close_local_error_pending_q <= 2'b00;
            close_tag_q <= 16'd0;
            force_rsp_valid_q <= 1'b0;
            force_rsp_bank_mask_q <= 2'd0;
            force_rsp_code_q <= STATUS_OK;
            force_rsp_state_q <= 6'd0;
            force_rsp_generation_q <= 32'd0;
            force_rsp_reset_required_q <= 2'd0;
            force_rsp_tag_q <= 16'd0;
            force_rsp_status_q <= STATUS_OK;
            pub_exec_valid_q <= 1'b0;
            pub_exec_read_issued_q <= 1'b0;
            pub_exec_pre_status_q <= STATUS_OK;
            pub_exec_bank_q <= 1'b0;
            pub_exec_image_epoch_q <= 32'd0;
            pub_exec_stage_id_q <= 4'd0;
            pub_exec_stage_ticket_q <= 32'd0;
            pub_exec_logical_branch_q <= 2'd0;
            pub_exec_context_generation_q <= 32'd0;
            pub_exec_matrix_binding_token_q <= 32'd0;
            pub_exec_content_handle_q <= 32'd0;
            pub_exec_physical_bank_generation_q <= 32'd0;
            pub_exec_directory_generation_q <= 16'd0;
            pub_exec_cancellation_epoch_q <= 32'd0;
            pub_exec_matrix_id_q <= 1'b0;
            pub_exec_source_index_q <= 10'd0;
            pub_exec_slot_base_q <= 13'd0;
            pub_exec_source_count_q <= 10'd0;
            pub_exec_row_tile_count_q <= 6'd0;
            pub_exec_matrix_mask_q <= 2'd0;
            pub_exec_tag_q <= 16'd0;
            pub_rsp_valid_q <= 1'b0;
            pub_rsp_bank_q <= 1'b0;
            pub_rsp_matrix_id_q <= 1'b0;
            pub_rsp_source_index_q <= 10'd0;
            pub_rsp_slot_base_q <= 13'd0;
            pub_rsp_directory_generation_q <= 16'd0;
            pub_rsp_committed_q <= 1'b0;
            pub_rsp_committed_count_q <= 10'd0;
            pub_rsp_tag_q <= 16'd0;
            pub_rsp_status_q <= STATUS_OK;
            for (i = 0; i < 3; i = i + 1) begin
                slot_state_q[i] <= SLOT_FREE;
                slot_incarnation_q[i] <= 14'd0;
                slot_kind_q[i] <= 1'b0;
                slot_image_epoch_q[i] <= 32'd0;
                slot_stage_id_q[i] <= 4'd0;
                slot_stage_ticket_q[i] <= 32'd0;
                slot_logical_branch_q[i] <= 2'd0;
                slot_context_generation_q[i] <= 32'd0;
                slot_matrix_id_q[i] <= 1'b0;
                slot_source_index_q[i] <= 10'd0;
                slot_row_tile_q[i] <= 6'd0;
                slot_matrix_binding_token_q[i] <= 32'd0;
                slot_cancellation_epoch_q[i] <= 32'd0;
                slot_causal_continuation_q[i] <= 1'b0;
                slot_user_tag_q[i] <= 16'd0;
                slot_bank_q[i] <= 1'b0;
                slot_physical_bank_generation_q[i] <= 32'd0;
                slot_content_handle_q[i] <= 32'd0;
                slot_directory_generation_q[i] <= 16'd0;
                slot_slot_base_q[i] <= 13'd0;
                slot_weight_addr_q[i] <= 13'd0;
                slot_pre_status_q[i] <= STATUS_OK;
                slot_status_q[i] <= STATUS_OK;
                slot_hit_q[i] <= 1'b0;
                slot_fatal_q[i] <= 1'b0;
            end
            lookup_head_q <= 2'd0;
            lookup_tail_q <= 2'd0;
            lookup_count_q <= 2'd0;
            bank0_ref_count_q <= 2'd0;
            bank1_ref_count_q <= 2'd0;
            dir_pipe_valid_q <= 1'b0;
            dir_pipe_read_issued_q <= 1'b0;
            dir_pipe_slot_q <= 2'd0;
            dir_pipe_owner_onehot_q <= 3'b000;
            dir_pipe_fast_active_q <= 2'b00;
            dir_pipe_fast_kind_q <= 1'b0;
            dir_pipe_fast_generation_q <= 16'd0;
            dir_pipe_fast_row_tile_q <= 6'd0;
            bank0_expect_count_q <= 2'd0;
            bank1_expect_count_q <= 2'd0;
            bank0_expect_head_q <= 1'b0;
            bank0_expect_tail_q <= 1'b0;
            bank1_expect_head_q <= 1'b0;
            bank1_expect_tail_q <= 1'b0;
            for (i = 0; i < 2; i = i + 1) begin
                bank0_expect_slot_q[i] <= 2'd0;
                bank1_expect_slot_q[i] <= 2'd0;
                bank0_expect_tag_q[i] <= 16'd0;
                bank1_expect_tag_q[i] <= 16'd0;
                bank0_expect_addr_q[i] <= 13'd0;
                bank1_expect_addr_q[i] <= 13'd0;
                bank0_expect_generation_q[i] <= 32'd0;
                bank1_expect_generation_q[i] <= 32'd0;
                bank0_expect_ticket_q[i] <= 32'd0;
                bank1_expect_ticket_q[i] <= 32'd0;
            end
            lookup_out_valid_q <= 1'b0;
            lookup_out_owner_onehot_q <= 3'b000;
            lookup_out_kind_q <= 1'b0;
            lookup_out_image_epoch_q <= 32'd0;
            lookup_out_stage_id_q <= 4'd0;
            lookup_out_stage_ticket_q <= 32'd0;
            lookup_out_logical_branch_q <= 2'd0;
            lookup_out_context_generation_q <= 32'd0;
            lookup_out_matrix_id_q <= 1'b0;
            lookup_out_source_index_q <= 10'd0;
            lookup_out_row_tile_q <= 6'd0;
            lookup_out_matrix_binding_token_q <= 32'd0;
            lookup_out_cancellation_epoch_q <= 32'd0;
            lookup_out_causal_continuation_q <= 1'b0;
            lookup_out_bank_q <= 1'b0;
            lookup_out_physical_bank_generation_q <= 32'd0;
            lookup_out_content_handle_q <= 32'd0;
            lookup_out_directory_generation_q <= 16'd0;
            lookup_out_slot_base_q <= 13'd0;
            lookup_out_weight_addr_q <= 13'd0;
            lookup_out_hit_q <= 1'b0;
            lookup_out_weight_data_q <= 128'd0;
            lookup_out_user_tag_q <= 16'd0;
            lookup_out_status_q <= STATUS_OK;
            lookup_out_fatal_q <= 1'b0;
        end else begin
            // A descriptor install is unconditional causal cleanup.  Exact
            // final close and local-fault handling occur later in this clocked
            // process, so their state/authority/cancellation overrides win,
            // while the new descriptor still becomes the durable ERROR scope.
            for (i = 0; i < 2; i = i + 1) begin
                if (stage_ticket_clear_pending_q[i]) begin
                    stage_ticket_q[i] <= 32'd0;
                    stage_ticket_clear_pending_q[i] <= 1'b0;
                end
                if (descriptor_install_pending_q[i]) begin
                    image_epoch_q[i] <= mgmt_exec_new_image_epoch_q;
                    stage_id_q[i] <= mgmt_exec_new_stage_id_q;
                    stage_ticket_q[i] <= mgmt_exec_new_stage_ticket_q;
                    stage_ticket_clear_pending_q[i] <= 1'b0;
                    logical_branch_q[i] <= mgmt_exec_new_logical_branch_q;
                    context_generation_q[i] <=
                        mgmt_exec_new_context_generation_q;
                    physical_bank_generation_q[i] <=
                        mgmt_exec_new_physical_bank_generation_q;
                    cancellation_epoch_q[i] <=
                        mgmt_exec_new_cancellation_epoch_q;
                    matrix0_binding_token_q[i] <=
                        mgmt_exec_new_matrix0_binding_token_q;
                    matrix1_binding_token_q[i] <=
                        mgmt_exec_new_matrix1_binding_token_q;
                    if (descriptor_install_claim_q[i]) begin
                        generation_q[i] <= mgmt_decision_new_generation_q;
                        committed_count_q[i] <= 10'd0;
                        content_handle_q[i] <=
                            mgmt_exec_new_content_handle_q;
                        matrix_mask_q[i] <= mgmt_exec_new_matrix_mask_q;
                        matrix0_source_count_q[i] <=
                            mgmt_exec_new_matrix0_source_count_q;
                        matrix1_source_count_q[i] <=
                            mgmt_exec_new_matrix1_source_count_q;
                        matrix0_row_tile_count_q[i] <=
                            mgmt_exec_new_matrix0_row_tile_count_q;
                        matrix1_row_tile_count_q[i] <=
                            mgmt_exec_new_matrix1_row_tile_count_q;
                    end
                    descriptor_install_pending_q[i] <= 1'b0;
                    descriptor_install_claim_q[i] <= 1'b0;
                end
            end

            // Default retirements.
            if (mgmt_rsp_fire) begin
                mgmt_rsp_valid_q <= 1'b0;
                if ((mgmt_rsp_status_q == STATUS_OK) &&
                    (mgmt_rsp_opcode_q == MGMT_BEGIN_DRAIN)) begin
                    if (mgmt_rsp_bank_mask_q[0])
                        begin_drain_rsp_retired_q[0] <= 1'b1;
                    if (mgmt_rsp_bank_mask_q[1])
                        begin_drain_rsp_retired_q[1] <= 1'b1;
                end
            end
            if (force_rsp_fire)
                force_rsp_valid_q <= 1'b0;
            if (publish_rsp_fire)
                pub_rsp_valid_q <= 1'b0;
            if (fault_event_fire_w) begin
                // Clear only a pre-existing held position here.  A directly
                // exposed stage event has no pending bit yet; its transfer
                // decision is handled atomically when the stage commits.
                if (fault_event_bank_mask[0] && fault_event_pending_q[0])
                    fault_event_pending_q[0] <= 1'b0;
                if (fault_event_bank_mask[1] && fault_event_pending_q[1])
                    fault_event_pending_q[1] <= 1'b0;
            end

            // Install an owner-selected final-close first error only after its
            // force-edge scope has crossed this registered boundary.  A rich
            // fault already staged on the exact-close edge has priority and is
            // committed by the common first-error path at the end of this
            // process instead.  The pending bit itself is exposed as local
            // error authority, so this extra physical-install edge neither
            // creates an observability gap nor permits close completion early.
            for (i = 0; i < 2; i = i + 1) begin
                if (close_local_error_pending_q[i]) begin
                    close_local_error_pending_q[i] <= 1'b0;
                    if (!local_error_valid_q[i] && !fault_now[i]) begin
                        local_error_valid_q[i] <= 1'b1;
                        local_error_code_q[i] <=
                            close_local_error_code_q[i];
                        local_error_source_q[i] <= ERROR_SOURCE_FINAL_CLOSE;
                        local_error_detail_q[i] <= 32'd0;
                        local_error_directory_generation_q[i] <=
                            close_local_error_directory_generation_q[i];
                        local_error_physical_bank_generation_q[i] <=
                            close_local_error_physical_bank_generation_q[i];
                        local_error_stage_ticket_q[i] <=
                            close_local_error_stage_ticket_q[i];
                        local_error_content_handle_q[i] <=
                            close_local_error_content_handle_q[i];
                    end
                end
            end

            // Lookup output retirement and ring pointers.
            if (lookup_rsp_fire) begin
                lookup_out_valid_q <= 1'b0;
                lookup_out_owner_onehot_q <= 3'b000;
                slot_state_q[lookup_head_q] <= SLOT_FREE;
                lookup_head_q <= slot_next(lookup_head_q);
            end
            case ({lookup_req_fire, lookup_rsp_fire})
                2'b10: lookup_count_q <= lookup_count_q + 1'b1;
                2'b01: lookup_count_q <= lookup_count_q - 1'b1;
                default: lookup_count_q <= lookup_count_q;
            endcase
            case ({lookup_req_fire && !lookup_res_selected_bank_id,
                   lookup_rsp_fire && !lookup_out_bank_q})
                2'b10: bank0_ref_count_q <= bank0_ref_count_q + 1'b1;
                2'b01: bank0_ref_count_q <= bank0_ref_count_q - 1'b1;
                default: bank0_ref_count_q <= bank0_ref_count_q;
            endcase
            case ({lookup_req_fire && lookup_res_selected_bank_id,
                   lookup_rsp_fire && lookup_out_bank_q})
                2'b10: bank1_ref_count_q <= bank1_ref_count_q + 1'b1;
                2'b01: bank1_ref_count_q <= bank1_ref_count_q - 1'b1;
                default: bank1_ref_count_q <= bank1_ref_count_q;
            endcase

            // Per-bank physical response correlation.  Push captures the
            // exact request echo at bank acceptance; pop occurs only when
            // that bank's registered head is also the aggregate order head.
            case ({bank0_req_fire, bank0_rsp_fire})
                2'b10: begin
                    bank0_expect_count_q <= bank0_expect_count_q + 1'b1;
                    bank0_expect_tail_q <= ~bank0_expect_tail_q;
                end
                2'b01: begin
                    bank0_expect_count_q <= bank0_expect_count_q - 1'b1;
                    bank0_expect_head_q <= ~bank0_expect_head_q;
                end
                2'b11: begin
                    bank0_expect_head_q <= ~bank0_expect_head_q;
                    bank0_expect_tail_q <= ~bank0_expect_tail_q;
                end
                default: begin
                    bank0_expect_count_q <= bank0_expect_count_q;
                end
            endcase
            if (bank0_req_fire) begin
                bank0_expect_slot_q[bank0_expect_tail_q] <=
                    physical_issue_slot;
                bank0_expect_tag_q[bank0_expect_tail_q] <= bank0_rd_req_tag;
                bank0_expect_addr_q[bank0_expect_tail_q] <=
                    bank0_rd_req_addr;
                bank0_expect_generation_q[bank0_expect_tail_q] <=
                    bank0_rd_req_generation;
                bank0_expect_ticket_q[bank0_expect_tail_q] <=
                    bank0_rd_req_lease_owner_ticket;
            end

            case ({bank1_req_fire, bank1_rsp_fire})
                2'b10: begin
                    bank1_expect_count_q <= bank1_expect_count_q + 1'b1;
                    bank1_expect_tail_q <= ~bank1_expect_tail_q;
                end
                2'b01: begin
                    bank1_expect_count_q <= bank1_expect_count_q - 1'b1;
                    bank1_expect_head_q <= ~bank1_expect_head_q;
                end
                2'b11: begin
                    bank1_expect_head_q <= ~bank1_expect_head_q;
                    bank1_expect_tail_q <= ~bank1_expect_tail_q;
                end
                default: begin
                    bank1_expect_count_q <= bank1_expect_count_q;
                end
            endcase
            if (bank1_req_fire) begin
                bank1_expect_slot_q[bank1_expect_tail_q] <=
                    physical_issue_slot;
                bank1_expect_tag_q[bank1_expect_tail_q] <= bank1_rd_req_tag;
                bank1_expect_addr_q[bank1_expect_tail_q] <=
                    bank1_rd_req_addr;
                bank1_expect_generation_q[bank1_expect_tail_q] <=
                    bank1_rd_req_generation;
                bank1_expect_ticket_q[bank1_expect_tail_q] <=
                    bank1_rd_req_lease_owner_ticket;
            end

            // A directory result always lands in its pre-reserved order slot.
            if (dir_pipe_valid_q) begin
                slot_status_q[dir_pipe_slot_q] <= dir_result_status;
                slot_hit_q[dir_pipe_slot_q] <= dir_result_hit;
                slot_fatal_q[dir_pipe_slot_q] <= dir_result_fatal;
                slot_slot_base_q[dir_pipe_slot_q] <=
                    ((dir_result_status == STATUS_OK) && dir_result_hit) ?
                    dir_result_slot_base : 13'd0;
                slot_weight_addr_q[dir_pipe_slot_q] <=
                    ((dir_result_status == STATUS_OK) && dir_result_hit) ?
                    dir_result_weight_addr : 13'd0;
                slot_state_q[dir_pipe_slot_q] <=
                    dir_result_bank_pending ? SLOT_BANK_PENDING :
                                              SLOT_LOCAL_DONE;
            end
            dir_pipe_valid_q <= lookup_req_fire;
            dir_pipe_fast_active_q <=
                (lookup_req_fire && lookup_pre_read) ?
                (lookup_res_selected_bank_id ? 2'b10 : 2'b01) : 2'b00;
            if (lookup_req_fire) begin
                dir_pipe_slot_q <= lookup_tail_q;
                dir_pipe_read_issued_q <= lookup_pre_read;
                dir_pipe_fast_kind_q <= lookup_req_kind;
                dir_pipe_fast_generation_q <=
                    lookup_res_directory_generation;
                dir_pipe_fast_row_tile_q <= lookup_req_row_tile;
                case (lookup_tail_q)
                    2'd0: dir_pipe_owner_onehot_q <= 3'b001;
                    2'd1: dir_pipe_owner_onehot_q <= 3'b010;
                    2'd2: dir_pipe_owner_onehot_q <= 3'b100;
                    default: dir_pipe_owner_onehot_q <= 3'b000;
                endcase
            end

            // Physical bank issue state advances only on its handshake.
            if (bank_req_fire)
                slot_state_q[physical_issue_slot] <= SLOT_BANK_WAIT;

            // Load the global response position from the current effective
            // head.  Same-edge output pop permits a following head to load.
            if (lookup_out_can_take && response_slot_valid &&
                (slot_state_q[response_slot] == SLOT_LOCAL_DONE)) begin
                lookup_out_valid_q <= 1'b1;
                case (response_slot)
                    2'd0: lookup_out_owner_onehot_q <= 3'b001;
                    2'd1: lookup_out_owner_onehot_q <= 3'b010;
                    2'd2: lookup_out_owner_onehot_q <= 3'b100;
                    default: lookup_out_owner_onehot_q <= 3'b000;
                endcase
                lookup_out_kind_q <= slot_kind_q[response_slot];
                lookup_out_image_epoch_q <= slot_image_epoch_q[response_slot];
                lookup_out_stage_id_q <= slot_stage_id_q[response_slot];
                lookup_out_stage_ticket_q <= slot_stage_ticket_q[response_slot];
                lookup_out_logical_branch_q <=
                    slot_logical_branch_q[response_slot];
                lookup_out_context_generation_q <=
                    slot_context_generation_q[response_slot];
                lookup_out_matrix_id_q <= slot_matrix_id_q[response_slot];
                lookup_out_source_index_q <= slot_source_index_q[response_slot];
                lookup_out_row_tile_q <= slot_row_tile_q[response_slot];
                lookup_out_matrix_binding_token_q <=
                    slot_matrix_binding_token_q[response_slot];
                lookup_out_cancellation_epoch_q <=
                    slot_cancellation_epoch_q[response_slot];
                lookup_out_causal_continuation_q <=
                    slot_causal_continuation_q[response_slot];
                lookup_out_bank_q <= slot_bank_q[response_slot];
                lookup_out_physical_bank_generation_q <=
                    slot_physical_bank_generation_q[response_slot];
                lookup_out_content_handle_q <=
                    slot_content_handle_q[response_slot];
                lookup_out_directory_generation_q <=
                    slot_directory_generation_q[response_slot];
                lookup_out_slot_base_q <= slot_slot_base_q[response_slot];
                lookup_out_weight_addr_q <= slot_weight_addr_q[response_slot];
                lookup_out_hit_q <= slot_hit_q[response_slot];
                lookup_out_weight_data_q <= 128'd0;
                lookup_out_user_tag_q <= slot_user_tag_q[response_slot];
                lookup_out_status_q <= slot_status_q[response_slot];
                lookup_out_fatal_q <= slot_fatal_q[response_slot];
                slot_state_q[response_slot] <= SLOT_OUTPUT;
            end else if (expected_bank_rsp_fire) begin
                lookup_out_valid_q <= 1'b1;
                case (response_slot)
                    2'd0: lookup_out_owner_onehot_q <= 3'b001;
                    2'd1: lookup_out_owner_onehot_q <= 3'b010;
                    2'd2: lookup_out_owner_onehot_q <= 3'b100;
                    default: lookup_out_owner_onehot_q <= 3'b000;
                endcase
                lookup_out_kind_q <= slot_kind_q[response_slot];
                lookup_out_image_epoch_q <= slot_image_epoch_q[response_slot];
                lookup_out_stage_id_q <= slot_stage_id_q[response_slot];
                lookup_out_stage_ticket_q <= slot_stage_ticket_q[response_slot];
                lookup_out_logical_branch_q <=
                    slot_logical_branch_q[response_slot];
                lookup_out_context_generation_q <=
                    slot_context_generation_q[response_slot];
                lookup_out_matrix_id_q <= slot_matrix_id_q[response_slot];
                lookup_out_source_index_q <= slot_source_index_q[response_slot];
                lookup_out_row_tile_q <= slot_row_tile_q[response_slot];
                lookup_out_matrix_binding_token_q <=
                    slot_matrix_binding_token_q[response_slot];
                lookup_out_cancellation_epoch_q <=
                    slot_cancellation_epoch_q[response_slot];
                lookup_out_causal_continuation_q <=
                    slot_causal_continuation_q[response_slot];
                lookup_out_bank_q <= slot_bank_q[response_slot];
                lookup_out_physical_bank_generation_q <=
                    slot_physical_bank_generation_q[response_slot];
                lookup_out_content_handle_q <=
                    slot_content_handle_q[response_slot];
                lookup_out_directory_generation_q <=
                    slot_directory_generation_q[response_slot];
                // Capture raw response fields.  Registered terminal status
                // masks them at the module boundary on any error/final close.
                // This keeps the rich first-fatal priority off the wide
                // payload-register D/reset paths without weakening fail-close.
                lookup_out_slot_base_q <= slot_slot_base_q[response_slot];
                lookup_out_weight_addr_q <= slot_weight_addr_q[response_slot];
                lookup_out_hit_q <= 1'b1;
                lookup_out_weight_data_q <= bank1_rsp_fire ?
                    bank1_rd_rsp_data : bank0_rd_rsp_data;
                lookup_out_user_tag_q <= slot_user_tag_q[response_slot];
                lookup_out_status_q <= bank_response_terminal_status;
                lookup_out_fatal_q <= bank_response_terminal_fatal;
                slot_state_q[response_slot] <= SLOT_OUTPUT;
            end

            // Reserve and fill a new order slot after old-slot retirement.
            if (lookup_req_fire) begin
                slot_incarnation_q[lookup_tail_q] <= new_slot_incarnation;
                slot_kind_q[lookup_tail_q] <= lookup_req_kind;
                slot_image_epoch_q[lookup_tail_q] <= lookup_req_image_epoch;
                slot_stage_id_q[lookup_tail_q] <= lookup_req_stage_id;
                slot_stage_ticket_q[lookup_tail_q] <= lookup_req_stage_ticket;
                slot_logical_branch_q[lookup_tail_q] <=
                    lookup_req_logical_branch;
                slot_context_generation_q[lookup_tail_q] <=
                    lookup_req_context_generation;
                slot_matrix_id_q[lookup_tail_q] <= lookup_req_matrix_id;
                slot_source_index_q[lookup_tail_q] <= lookup_req_source_index;
                slot_row_tile_q[lookup_tail_q] <= lookup_req_row_tile;
                slot_matrix_binding_token_q[lookup_tail_q] <=
                    lookup_req_matrix_binding_token;
                slot_cancellation_epoch_q[lookup_tail_q] <=
                    lookup_req_cancellation_epoch;
                slot_causal_continuation_q[lookup_tail_q] <=
                    lookup_res_causal_continuation;
                slot_user_tag_q[lookup_tail_q] <= lookup_req_user_tag;
                slot_bank_q[lookup_tail_q] <=
                    lookup_res_selected_bank_id;
                slot_physical_bank_generation_q[lookup_tail_q] <=
                    lookup_res_physical_bank_generation;
                slot_content_handle_q[lookup_tail_q] <=
                    lookup_res_content_handle;
                slot_directory_generation_q[lookup_tail_q] <=
                    lookup_res_directory_generation;
                slot_pre_status_q[lookup_tail_q] <= lookup_pre_status;
                // Result-only fields deliberately retain don't-care values
                // while the virtual directory-pipeline mask owns the record.
                // The registered directory result overwrites every one before
                // stored state can become terminal or issue a bank request.
                // Avoiding a wide acceptance-time clear keeps the ready/
                // arbitration cone off their synchronous reset pins.
                lookup_tail_q <= slot_next(lookup_tail_q);
            end

            // Publication execution and held response.
            // Any accepted final-close request that names this physical bank
            // owns its data edge.  A malformed request merely stalls the
            // already-owned publication for one cycle; an exact request
            // installs close_pending_q and the publication terminalizes from
            // that registered cut next cycle.  Thus no uncommitted source can
            // be published on the close edge, without routing the wide close-
            // identity comparator into BRAM write enable or response state.
            if (pub_exec_valid_q &&
                !(force_error_fire &&
                  force_error_bank_mask[pub_exec_bank_q])) begin
                pub_rsp_valid_q <= 1'b1;
                pub_rsp_bank_q <= pub_exec_bank_q;
                pub_rsp_matrix_id_q <= pub_exec_matrix_id_q;
                pub_rsp_source_index_q <= pub_exec_source_index_q;
                pub_rsp_slot_base_q <= pub_exec_slot_base_q;
                pub_rsp_directory_generation_q <=
                    pub_exec_directory_generation_q;
                pub_rsp_tag_q <= pub_exec_tag_q;
                if (close_pending_q &&
                    close_bank_mask_q[pub_exec_bank_q]) begin
                    pub_rsp_status_q <= publication_close_code;
                    pub_rsp_committed_q <= 1'b0;
                    pub_rsp_committed_count_q <=
                        pub_exec_bank_q ? effective_committed_count1_w :
                                          effective_committed_count0_w;
                end else begin
                    pub_rsp_status_q <= publish_result_status;
                    pub_rsp_committed_q <= publish_result_committed;
                    pub_rsp_committed_count_q <=
                        (pub_exec_bank_q ? effective_committed_count1_w :
                                           effective_committed_count0_w) +
                        publish_result_committed;
                    if (publish_result_committed) begin
                        if (pub_exec_bank_q)
                            committed_count_q[1] <=
                                effective_committed_count1_w + 1'b1;
                        else
                            committed_count_q[0] <=
                                effective_committed_count0_w + 1'b1;
                    end
                end
                pub_exec_valid_q <= 1'b0;
            end
            if (publish_req_fire) begin
                pub_exec_valid_q <= 1'b1;
                pub_exec_read_issued_q <=
                    (publish_pre_status == STATUS_OK);
                pub_exec_pre_status_q <= publish_pre_status;
                pub_exec_bank_q <= publish_req_bank_id;
                pub_exec_image_epoch_q <= publish_req_image_epoch;
                pub_exec_stage_id_q <= publish_req_stage_id;
                pub_exec_stage_ticket_q <= publish_req_stage_ticket;
                pub_exec_logical_branch_q <= publish_req_logical_branch;
                pub_exec_context_generation_q <=
                    publish_req_context_generation;
                pub_exec_matrix_binding_token_q <=
                    publish_req_matrix_binding_token;
                pub_exec_content_handle_q <= publish_req_content_handle;
                pub_exec_physical_bank_generation_q <=
                    publish_req_physical_bank_generation;
                pub_exec_directory_generation_q <=
                    publish_req_directory_generation;
                pub_exec_cancellation_epoch_q <=
                    publish_req_cancellation_epoch;
                pub_exec_matrix_id_q <= publish_req_matrix_id;
                pub_exec_source_index_q <= publish_req_source_index;
                pub_exec_slot_base_q <= publish_req_slot_base;
                pub_exec_source_count_q <= publish_req_source_count;
                pub_exec_row_tile_count_q <= publish_req_row_tile_count;
                pub_exec_matrix_mask_q <= publish_req_matrix_mask;
                pub_exec_tag_q <= publish_req_tag;
            end

            // Resolve the C0->C1 non-authoritative SCRUB candidate.  A fault
            // already visible on C0 was captured into the narrow mask and
            // therefore produces one held terminal response with no RAM or
            // lifecycle mutation.  Otherwise address zero commits on this
            // edge and the registered preview becomes authoritative
            // SCRUBBING work at address one.  A new fault first visible on C1
            // is intentionally handled by the ordinary active causal path:
            // address zero is harmless, its registered fence blocks address
            // one, and the rich first-fatal record terminalizes the scrub.
            if (scrub_candidate_valid_q) begin
                scrub_candidate_valid_q <= 1'b0;
                scrub_candidate_initial_fault_q <= 2'b00;
                if ((scrub_candidate_initial_fault_q &
                     mgmt_active_bank_mask_q) != 0) begin
                    mgmt_rsp_valid_q <= 1'b1;
                    mgmt_rsp_state_q <= {state_q[1], state_q[0]};
                    mgmt_rsp_status_q <=
                        (scrub_candidate_initial_fault_q[0] &&
                         mgmt_active_bank_mask_q[0]) ?
                        ((first_fault_code0_w != STATUS_OK) ?
                         first_fault_code0_w : STATUS_ERR_LOCAL_PROTOCOL) :
                        ((first_fault_code1_w != STATUS_OK) ?
                         first_fault_code1_w : STATUS_ERR_LOCAL_PROTOCOL);
                    mgmt_rsp_mutating_q <= 1'b0;
                    if (mgmt_active_bank_mask_q[0])
                        scrub_required_q[0] <= 1'b1;
                    if (mgmt_active_bank_mask_q[1])
                        scrub_required_q[1] <= 1'b1;
                end else begin
                    mgmt_active_q <= 1'b1;
                    scrub_address_q <= 10'd1;
                    if (mgmt_active_bank_mask_q[0]) begin
                        state_q[0] <= ST_SCRUBBING;
                        last_scrub_epoch_q[0] <=
                            mgmt_active_image_epoch_q;
                        last_scrub_epoch_valid_q[0] <= 1'b0;
                    end
                    if (mgmt_active_bank_mask_q[1]) begin
                        state_q[1] <= ST_SCRUBBING;
                        last_scrub_epoch_q[1] <=
                            mgmt_active_image_epoch_q;
                        last_scrub_epoch_valid_q[1] <= 1'b0;
                    end
                end
            end

            // Complete an in-progress 1024-write scrub.
            if (mgmt_active_q && (mgmt_active_opcode_q == MGMT_SCRUB)) begin
                // The epoch payload is copied on the first registered active
                // edge, independently of all live fault classification.  Its
                // valid bit was revoked when SCRUB obtained ownership and is
                // published only with the C1024 success response.  Therefore
                // an abort/fault may leave this physical candidate value in
                // place without granting it any authority.
                if (scrub_address_q == 10'd0) begin
                    if (mgmt_active_bank_mask_q[0])
                        last_scrub_epoch_q[0] <=
                            mgmt_active_image_epoch_q;
                    if (mgmt_active_bank_mask_q[1])
                        last_scrub_epoch_q[1] <=
                            mgmt_active_image_epoch_q;
                end
                if (((fault_stage_valid_w &
                      mgmt_active_bank_mask_q) != 0) ||
                    (force_error_fire && force_request_exact &&
                     ((force_error_bank_mask &
                       mgmt_active_bank_mask_q) != 0))) begin
                    mgmt_active_q <= 1'b0;
                    mgmt_rsp_valid_q <= 1'b1;
                    mgmt_rsp_state_q <= {state_q[1], state_q[0]};
                    if ((fault_stage_valid_w &
                         mgmt_active_bank_mask_q) != 0)
                        mgmt_rsp_status_q <=
                            (fault_now[0] &&
                             mgmt_active_bank_mask_q[0]) ?
                            fault_code_now[0] : fault_code_now[1];
                    else
                        mgmt_rsp_status_q <= force_error_code;
                    mgmt_rsp_mutating_q <= 1'b0;
                    if (mgmt_active_bank_mask_q[0]) begin
                        scrub_required_q[0] <= 1'b1;
                        if (fault_now[0]) begin
                            state_q[0] <= ST_ERROR;
                            mgmt_rsp_state_q[2:0] <= ST_ERROR;
                        end else if (force_error_fire && force_request_exact &&
                                     force_error_bank_mask[0]) begin
                            state_q[0] <= ST_DRAINING;
                            mgmt_rsp_state_q[2:0] <= ST_DRAINING;
                        end else begin
                            state_q[0] <= ST_INVALID;
                            mgmt_rsp_state_q[2:0] <= ST_INVALID;
                        end
                    end
                    if (mgmt_active_bank_mask_q[1]) begin
                        scrub_required_q[1] <= 1'b1;
                        if (fault_now[1]) begin
                            state_q[1] <= ST_ERROR;
                            mgmt_rsp_state_q[5:3] <= ST_ERROR;
                        end else if (force_error_fire && force_request_exact &&
                                     force_error_bank_mask[1]) begin
                            state_q[1] <= ST_DRAINING;
                            mgmt_rsp_state_q[5:3] <= ST_DRAINING;
                        end else begin
                            state_q[1] <= ST_INVALID;
                            mgmt_rsp_state_q[5:3] <= ST_INVALID;
                        end
                    end
                end else if (force_intersects_active_scrub) begin
                    // A malformed close that names either scrub target owns
                    // this edge but is not an exact cut.  Both write ports
                    // were conservatively idle above, so hold the address and
                    // resume without desynchronizing or skipping an entry.
                    mgmt_active_q <= 1'b1;
                    scrub_address_q <= scrub_address_q;
                end else if (scrub_live_veto_w) begin
                    // A fault first detected on the final scrub address may
                    // coincide with that address's harmless zero write, but it
                    // must not publish scrub success.  Hold the accepted scrub
                    // until the bank-local rich fault stage is registered; the
                    // following edge takes the abort branch above.  The live
                    // veto is intentionally limited to the global ownership
                    // invariant and an impossible selected-bank response: all
                    // other target producers were drained before admission and
                    // remain fenced throughout SCRUB.  Registered stage-valid
                    // also suppresses a duplicate RAM write.
                    mgmt_active_q <= 1'b1;
                    scrub_address_q <= scrub_address_q;
                end else if (scrub_address_q == 10'd1023) begin
                    mgmt_active_q <= 1'b0;
                    mgmt_rsp_valid_q <= 1'b1;
                    mgmt_rsp_state_q <= {state_q[1], state_q[0]};
                    mgmt_rsp_status_q <= STATUS_OK;
                    mgmt_rsp_mutating_q <= 1'b1;
                    if (mgmt_active_bank_mask_q[0]) begin
                        state_q[0] <= ST_INVALID;
                        mgmt_rsp_state_q[2:0] <= ST_INVALID;
                        scrub_required_q[0] <= 1'b0;
                        last_scrub_epoch_valid_q[0] <= 1'b1;
                    end
                    if (mgmt_active_bank_mask_q[1]) begin
                        state_q[1] <= ST_INVALID;
                        mgmt_rsp_state_q[5:3] <= ST_INVALID;
                        scrub_required_q[1] <= 1'b0;
                        last_scrub_epoch_valid_q[1] <= 1'b1;
                    end
                end else begin
                    scrub_address_q <= scrub_address_q + 1'b1;
                end
            end

            // The execution stage validates a captured command and registers
            // a compact decision.  Live physical faults may hold this stage
            // for one edge so the sticky first-error record becomes stable,
            // but no live fault signal reaches a lifecycle payload register.
            if (mgmt_exec_valid_q) begin
                if (close_pending_q &&
                    ((close_bank_mask_q & mgmt_exec_bank_mask_q) != 0)) begin
                    mgmt_exec_valid_q <= 1'b0;
                    mgmt_exec_fault_collision_q <= 2'b00;
                    mgmt_rsp_valid_q <= 1'b1;
                    mgmt_rsp_state_q <= {state_q[1], state_q[0]};
                    mgmt_rsp_status_q <=
                        (close_bank_mask_q[0] &&
                         mgmt_exec_bank_mask_q[0]) ? close_code_q[0] :
                                                    close_code_q[1];
                    mgmt_rsp_mutating_q <= 1'b0;
                end else if (force_error_fire) begin
                    mgmt_exec_fault_collision_q <=
                        mgmt_exec_fault_collision_q |
                        (mgmt_late_fault_now_w & mgmt_exec_bank_mask_q);
                end else if (((mgmt_exec_fault_collision_q &
                               mgmt_exec_bank_mask_q) == 0) &&
                             ((mgmt_late_fault_now_w &
                               mgmt_exec_bank_mask_q) != 0)) begin
                    mgmt_exec_fault_collision_q <=
                        mgmt_late_fault_now_w & mgmt_exec_bank_mask_q;
                end else begin
                    mgmt_exec_valid_q <= 1'b0;
                    mgmt_decision_valid_q <= 1'b1;
                    mgmt_decision_status_q <= mgmt_status_d;
                    mgmt_decision_new_state_q <= mgmt_new_state_d;
                    mgmt_decision_new_generation_q <=
                        mgmt_new_generation_d;
                    mgmt_decision_mutating_q <= mgmt_is_mutating_d &&
                                                (mgmt_status_d == STATUS_OK);
                    // Preserve a captured collision through the decision
                    // position.  Its rich bank-local first-error record is
                    // staged independently and must become authoritative
                    // before this accepted management request terminalizes.
                    // Clean requests naturally retain 2'b00 here.
                end
            end

            // The decision stage is the only ordinary-management path to wide
            // lifecycle payload registers.  Its decoder outputs are all
            // registered.  A fault first observed on the commit edge is held
            // for one edge and then returned as the sticky first-fatal code.
            if (mgmt_decision_valid_q) begin
                if (close_pending_q &&
                    ((close_bank_mask_q & mgmt_exec_bank_mask_q) != 0)) begin
                    mgmt_decision_valid_q <= 1'b0;
                    mgmt_exec_fault_collision_q <= 2'b00;
                    mgmt_rsp_valid_q <= 1'b1;
                    mgmt_rsp_state_q <= {state_q[1], state_q[0]};
                    mgmt_rsp_status_q <=
                        (close_bank_mask_q[0] &&
                         mgmt_exec_bank_mask_q[0]) ? close_code_q[0] :
                                                    close_code_q[1];
                    mgmt_rsp_mutating_q <= 1'b0;
                end else if (force_error_fire) begin
                    mgmt_exec_fault_collision_q <=
                        mgmt_exec_fault_collision_q |
                        (mgmt_late_fault_now_w & mgmt_exec_bank_mask_q);
                end else if ((mgmt_exec_fault_collision_q &
                              mgmt_exec_bank_mask_q) != 0) begin
                    // The registered source-event bundle is the physical
                    // landing position for rich code/detail/scope.  Hold the
                    // management decision until it commits into the immutable
                    // first-error record, then produce one terminal response.
                    if (((fault_stage_valid_w &
                          mgmt_exec_bank_mask_q) == 0)) begin
                        mgmt_decision_valid_q <= 1'b0;
                        mgmt_exec_fault_collision_q <= 2'b00;
                        mgmt_rsp_valid_q <= 1'b1;
                        mgmt_rsp_state_q <= {state_q[1], state_q[0]};
                        mgmt_rsp_status_q <=
                            (mgmt_exec_fault_collision_q[0] &&
                             mgmt_exec_bank_mask_q[0]) ?
                            first_fault_code0_w : first_fault_code1_w;
                        mgmt_rsp_mutating_q <= 1'b0;
                    end
                end else if ((mgmt_late_fault_now_w &
                              mgmt_exec_bank_mask_q) != 0) begin
                    mgmt_exec_fault_collision_q <=
                        mgmt_late_fault_now_w & mgmt_exec_bank_mask_q;
                end else begin
                    mgmt_decision_valid_q <= 1'b0;
                if ((mgmt_exec_opcode_q == MGMT_SCRUB) &&
                    (mgmt_decision_status_q == STATUS_OK)) begin
                    mgmt_active_q <= 1'b1;
                    if (mgmt_exec_bank_mask_q[0]) begin
                        state_q[0] <= ST_SCRUBBING;
                        last_scrub_epoch_valid_q[0] <= 1'b0;
                    end
                    if (mgmt_exec_bank_mask_q[1]) begin
                        state_q[1] <= ST_SCRUBBING;
                        last_scrub_epoch_valid_q[1] <= 1'b0;
                    end
                end else begin
                    mgmt_rsp_valid_q <= 1'b1;
                    mgmt_rsp_state_q <= {state_q[1], state_q[0]};
                    mgmt_rsp_status_q <= mgmt_decision_status_q;
                    mgmt_rsp_mutating_q <= mgmt_decision_mutating_q &&
                                           (mgmt_decision_status_q == STATUS_OK);
                    if ((mgmt_exec_opcode_q == MGMT_CLAIM_FRESH) &&
                        (mgmt_decision_status_q == STATUS_ERR_SCRUB_REQUIRED))
                        scrub_required_q[mgmt_exec_bank_mask_q[1]] <= 1'b1;
                    if (mgmt_decision_status_q == STATUS_OK) begin
                        if (mgmt_exec_bank_mask_q[0]) begin
                            mgmt_rsp_state_q[2:0] <= mgmt_decision_new_state_q;
                        end else begin
                            mgmt_rsp_state_q[5:3] <= mgmt_decision_new_state_q;
                        end

                        if (mgmt_exec_opcode_q == MGMT_CLAIM_FRESH) begin
                            state_q[mgmt_exec_bank_mask_q[1]] <= ST_LOADING;
                            generation_initialized_q[
                                mgmt_exec_bank_mask_q[1]] <= 1'b1;
                            descriptor_valid_q[mgmt_exec_bank_mask_q[1]] <= 1'b1;
                            lease_authority_valid_q[
                                mgmt_exec_bank_mask_q[1]] <= 1'b1;
                            content_valid_q[mgmt_exec_bank_mask_q[1]] <= 1'b0;
                            descriptor_install_pending_q[
                                mgmt_exec_bank_mask_q[1]] <= 1'b1;
                            descriptor_install_claim_q[
                                mgmt_exec_bank_mask_q[1]] <= 1'b1;
                            begin_drain_rsp_retired_q[
                                mgmt_exec_bank_mask_q[1]] <= 1'b0;
                        end else if (mgmt_exec_opcode_q ==
                                     MGMT_REBIND_RETAINED) begin
                            state_q[mgmt_exec_bank_mask_q[1]] <= ST_LOADING;
                            lease_authority_valid_q[
                                mgmt_exec_bank_mask_q[1]] <= 1'b1;
                            descriptor_install_pending_q[
                                mgmt_exec_bank_mask_q[1]] <= 1'b1;
                            descriptor_install_claim_q[
                                mgmt_exec_bank_mask_q[1]] <= 1'b0;
                            begin_drain_rsp_retired_q[
                                mgmt_exec_bank_mask_q[1]] <= 1'b0;
                        end else if (mgmt_exec_opcode_q ==
                                     MGMT_PUBLISH_READY) begin
                            state_q[mgmt_exec_bank_mask_q[1]] <= ST_READY;
                            content_valid_q[mgmt_exec_bank_mask_q[1]] <= 1'b1;
                        end else if (mgmt_exec_opcode_q == MGMT_ACTIVATE) begin
                            state_q[mgmt_exec_bank_mask_q[1]] <= ST_ACTIVE;
                        end else if (mgmt_exec_opcode_q == MGMT_BEGIN_DRAIN) begin
                            state_q[mgmt_exec_bank_mask_q[1]] <= ST_DRAINING;
                            drain_target_q[mgmt_exec_bank_mask_q[1]] <=
                                mgmt_exec_drain_target_q;
                            begin_drain_rsp_retired_q[
                                mgmt_exec_bank_mask_q[1]] <= 1'b0;
                        end else if (mgmt_exec_opcode_q == MGMT_FINISH_DRAIN) begin
                            state_q[mgmt_exec_bank_mask_q[1]] <=
                                mgmt_decision_new_state_q;
                            lease_authority_valid_q[
                                mgmt_exec_bank_mask_q[1]] <= 1'b0;
                            begin_drain_rsp_retired_q[
                                mgmt_exec_bank_mask_q[1]] <= 1'b0;
                            if (mgmt_decision_new_state_q == ST_INVALID) begin
                                descriptor_valid_q[
                                    mgmt_exec_bank_mask_q[1]] <= 1'b0;
                                content_valid_q[
                                    mgmt_exec_bank_mask_q[1]] <= 1'b0;
                            end else if (mgmt_decision_new_state_q == ST_RETAINED) begin
                                content_valid_q[
                                    mgmt_exec_bank_mask_q[1]] <= 1'b1;
                                stage_ticket_clear_pending_q[
                                    mgmt_exec_bank_mask_q[1]] <= 1'b1;
                            end else begin
                                content_valid_q[
                                    mgmt_exec_bank_mask_q[1]] <= 1'b0;
                            end
                        end else if (mgmt_exec_opcode_q == MGMT_CLEAR_ERROR) begin
                            state_q[mgmt_exec_bank_mask_q[1]] <= ST_INVALID;
                            descriptor_valid_q[
                                mgmt_exec_bank_mask_q[1]] <= 1'b0;
                            lease_authority_valid_q[
                                mgmt_exec_bank_mask_q[1]] <= 1'b0;
                            content_valid_q[mgmt_exec_bank_mask_q[1]] <= 1'b0;
                            scrub_required_q[mgmt_exec_bank_mask_q[1]] <= 1'b1;
                            local_error_valid_q[
                                mgmt_exec_bank_mask_q[1]] <= 1'b0;
                            fault_fence_q[mgmt_exec_bank_mask_q[1]] <= 1'b0;
                            fault_event_pending_q[
                                mgmt_exec_bank_mask_q[1]] <= 1'b0;
                        end
                    end
                end
                end
            end
            // Preview all wide request/context payload from the shallow
            // transport claim, before the projected-fault admission fence.
            // These registers carry no authority by themselves: only the
            // narrow exec/active valid bit set by mgmt_req_fire below publishes
            // the sampled request.  The global single credit prevents another
            // preview from overwriting an accepted request or held response.
            if (mgmt_preview_capture_w) begin
                mgmt_rsp_opcode_q <= mgmt_req_opcode;
                mgmt_rsp_bank_mask_q <= mgmt_req_bank_mask;
                mgmt_rsp_tag_q <= mgmt_req_tag;

                mgmt_exec_opcode_q <= mgmt_req_opcode;
                mgmt_exec_bank_mask_q <= mgmt_req_bank_mask;
                mgmt_exec_drain_target_q <= mgmt_req_drain_target;
                mgmt_exec_expected_directory_generation_q <=
                    mgmt_req_expected_directory_generation;
                mgmt_exec_expected_content_handle_q <=
                    mgmt_req_expected_content_handle;
                mgmt_exec_expected_stage_ticket_q <=
                    mgmt_req_expected_stage_ticket;
                mgmt_exec_expected_physical_bank_generation_q <=
                    mgmt_req_expected_physical_bank_generation;
                mgmt_exec_new_image_epoch_q <= mgmt_req_new_image_epoch;
                mgmt_exec_new_stage_id_q <= mgmt_req_new_stage_id;
                mgmt_exec_new_stage_ticket_q <= mgmt_req_new_stage_ticket;
                mgmt_exec_new_logical_branch_q <=
                    mgmt_req_new_logical_branch;
                mgmt_exec_new_context_generation_q <=
                    mgmt_req_new_context_generation;
                mgmt_exec_new_content_handle_q <=
                    mgmt_req_new_content_handle;
                mgmt_exec_new_physical_bank_generation_q <=
                    mgmt_req_new_physical_bank_generation;
                mgmt_exec_new_cancellation_epoch_q <=
                    mgmt_req_new_cancellation_epoch;
                mgmt_exec_new_matrix_mask_q <= mgmt_req_new_matrix_mask;
                mgmt_exec_new_matrix0_binding_token_q <=
                    mgmt_req_new_matrix0_binding_token;
                mgmt_exec_new_matrix1_binding_token_q <=
                    mgmt_req_new_matrix1_binding_token;
                mgmt_exec_new_matrix0_source_count_q <=
                    mgmt_req_new_matrix0_source_count;
                mgmt_exec_new_matrix1_source_count_q <=
                    mgmt_req_new_matrix1_source_count;
                mgmt_exec_new_matrix0_row_tile_count_q <=
                    mgmt_req_new_matrix0_row_tile_count;
                mgmt_exec_new_matrix1_row_tile_count_q <=
                    mgmt_req_new_matrix1_row_tile_count;
                mgmt_exec_external_safe_q <= mgmt_req_external_safe;
                mgmt_exec_tag_q <= mgmt_req_tag;
                mgmt_exec_accept_causal_empty_q <= bank_causal_empty_w;
                mgmt_exec_accept_drain_complete_q <= bank_drain_complete;

                // Direct-SCRUB context is likewise previewed.  While a scrub
                // is active the transport claim is false, so these fields and
                // its address cannot be overwritten before completion.
                mgmt_active_opcode_q <= mgmt_req_opcode;
                mgmt_active_bank_mask_q <= mgmt_req_bank_mask;
                mgmt_active_image_epoch_q <= mgmt_req_new_image_epoch;
                mgmt_active_tag_q <= mgmt_req_tag;
                scrub_address_q <= 10'd0;
            end

            // Request admission grants authority only to an explicit physical
            // landing position.  A legal-static SCRUB first owns the candidate
            // slot; only its registered clean evidence can promote lifecycle
            // authority on C1.  All other management requests use the ordinary
            // execution/decision pipeline.
            if (scrub_candidate_accept_w) begin
                scrub_candidate_valid_q <= 1'b1;
                scrub_candidate_initial_fault_q <=
                    (preexisting_fence_now | current_fault_fence_w) &
                    mgmt_req_bank_mask;
            end else if (mgmt_req_fire) begin
                mgmt_exec_valid_q <= 1'b1;
                mgmt_exec_fault_collision_q <=
                    preexisting_fence_now & mgmt_req_bank_mask;
            end
            // Exact final close installs an immediate admission cut.  Pending
            // pre-bank records become terminal errors; issued reads remain
            // owned and are consumed only to release physical bank credit.
            if (force_error_fire) begin
                if (!force_request_exact) begin
                    force_rsp_valid_q <= 1'b1;
                    force_rsp_bank_mask_q <= force_error_bank_mask;
                    force_rsp_code_q <= force_error_code;
                    force_rsp_state_q <= {state_q[1], state_q[0]};
                    force_rsp_generation_q <=
                        {effective_generation1_w, effective_generation0_w};
                    force_rsp_reset_required_q <=
                        {reset_required_q[1], reset_required_q[0]};
                    force_rsp_tag_q <= force_error_tag;
                    force_rsp_status_q <= force_request_status;
                end else begin
                    close_pending_q <= 1'b1;
                    close_bank_mask_q <= force_error_bank_mask;
                    close_tag_q <= force_error_tag;
                    close_code_q[0] <= bank0_close_code;
                    close_code_q[1] <= bank1_close_code;
                    for (i = 0; i < 2; i = i + 1) begin
                        if (force_error_bank_mask[i]) begin
                            state_q[i] <= ST_DRAINING;
                            drain_target_q[i] <= DRAIN_ERROR;
                            lease_authority_valid_q[i] <= 1'b0;
                            content_valid_q[i] <= 1'b0;
                            fault_fence_q[i] <= 1'b1;
                            cancellation_epoch_q[i] <=
                                force_error_cancellation_epoch;
                            if (force_error_data_untrusted &&
                                !force_error_causal_producers_drained)
                                reset_required_q[i] <= 1'b1;
                            if (!local_error_valid_q[i]) begin
                                // Do not consult live fault classification in
                                // the clock enable of this wide payload.  If a
                                // current rich fault exists, its registered
                                // authority suppresses the deferred owner fill
                                // on the following edge.
                                close_local_error_pending_q[i] <= 1'b1;
                                close_local_error_code_q[i] <=
                                    force_error_code;
                                close_local_error_directory_generation_q[i] <=
                                    (i == 0) ? effective_generation0_w :
                                               effective_generation1_w;
                                close_local_error_physical_bank_generation_q[i] <=
                                    (i == 0) ?
                                    effective_physical_bank_generation0_w :
                                    effective_physical_bank_generation1_w;
                                close_local_error_stage_ticket_q[i] <=
                                    (i == 0) ? effective_stage_ticket0_w :
                                               effective_stage_ticket1_w;
                                close_local_error_content_handle_q[i] <=
                                    (i == 0) ? effective_content_handle0_w :
                                               effective_content_handle1_w;
                            end
                        end
                    end
                    for (i = 0; i < 3; i = i + 1) begin
                        if ((dir_wait_mask_w[i] ||
                             slot_state_q[i] == SLOT_BANK_PENDING) &&
                            force_error_bank_mask[slot_bank_q[i]]) begin
                            slot_state_q[i] <= SLOT_LOCAL_DONE;
                            slot_status_q[i] <= slot_bank_q[i] ?
                                bank1_close_code : bank0_close_code;
                            slot_hit_q[i] <= 1'b0;
                            slot_fatal_q[i] <= slot_bank_q[i] ?
                                bank1_close_fatal_w : bank0_close_fatal_w;
                        end
                    end
                    // The ordinary directory-pipeline rollover above already
                    // consumes the pre-edge result.  Do not clear valid here:
                    // an exact close on one bank may legally coincide with a
                    // newly accepted lookup for the other bank, whose metadata
                    // now owns this same registered pipeline position.
                end
            end

            // A pending exact close advances to ERROR after all selected
            // causal positions and held terminal responses retire.
            if (close_pending_q) begin
                if (close_bank_mask_q[0] && bank_causal_empty_w[0])
                    state_q[0] <= ST_ERROR;
                if (close_bank_mask_q[1] && bank_causal_empty_w[1])
                    state_q[1] <= ST_ERROR;
                if (close_complete) begin
                    close_pending_q <= 1'b0;
                    force_rsp_valid_q <= 1'b1;
                    force_rsp_bank_mask_q <= close_bank_mask_q;
                    force_rsp_code_q <= close_bank_mask_q[0] ?
                        close_code_q[0] : close_code_q[1];
                    force_rsp_state_q <= {state_q[1], state_q[0]};
                    if (close_bank_mask_q[0])
                        force_rsp_state_q[2:0] <= ST_ERROR;
                    if (close_bank_mask_q[1])
                        force_rsp_state_q[5:3] <= ST_ERROR;
                    force_rsp_generation_q <=
                        {effective_generation1_w, effective_generation0_w};
                    force_rsp_reset_required_q <=
                        {reset_required_q[1], reset_required_q[0]};
                    force_rsp_tag_q <= close_tag_q;
                    force_rsp_status_q <= STATUS_OK;
                end
            end

            // Source-local raw snapshots have no live fault-dependent clock
            // enable.  The associated six one-bit event flags are the only
            // registers fed by live classifiers; fault_now merges those
            // registered flags on the following cycle.
            fault_bank_status_snapshot_q[0] <= bank0_rsp_observed_status;
            fault_bank_status_snapshot_q[1] <= bank1_rsp_observed_status;
            fault_bank_reset_snapshot_q[0] <= bank0_rsp_observed_reset;
            fault_bank_reset_snapshot_q[1] <= bank1_rsp_observed_reset;
            fault_bank_tag_snapshot_q[0] <= bank0_rd_rsp_tag;
            fault_bank_tag_snapshot_q[1] <= bank1_rd_rsp_tag;
            fault_dir_status_snapshot_q <= dir_result_status;
            fault_dir_detail_snapshot_q <=
                (dir_pipe_slot_q == 2'd0) ?
                {15'd0, slot_matrix_id_q[0], slot_source_index_q[0],
                 slot_row_tile_q[0]} :
                (dir_pipe_slot_q == 2'd1) ?
                {15'd0, slot_matrix_id_q[1], slot_source_index_q[1],
                 slot_row_tile_q[1]} :
                (dir_pipe_slot_q == 2'd2) ?
                {15'd0, slot_matrix_id_q[2], slot_source_index_q[2],
                 slot_row_tile_q[2]} : 32'd0;
            fault_pub_status_snapshot_q <= publish_result_status;
            fault_pub_detail_snapshot_q <=
                {8'd0, pub_exec_matrix_id_q, pub_exec_source_index_q,
                 pub_exec_slot_base_q};
            fault_lookup_status_snapshot_q <= lookup_pre_status;
            fault_lookup_detail_snapshot_q <=
                {15'd0, lookup_req_matrix_id, lookup_req_source_index,
                 lookup_req_row_tile};
            fault_scope_directory_generation_q[0] <=
                effective_generation0_w;
            fault_scope_directory_generation_q[1] <=
                effective_generation1_w;
            fault_scope_physical_bank_generation_q[0] <=
                effective_physical_bank_generation0_w;
            fault_scope_physical_bank_generation_q[1] <=
                effective_physical_bank_generation1_w;
            fault_scope_stage_ticket_q[0] <= effective_stage_ticket0_w;
            fault_scope_stage_ticket_q[1] <= effective_stage_ticket1_w;
            fault_scope_content_handle_q[0] <= effective_content_handle0_w;
            fault_scope_content_handle_q[1] <= effective_content_handle1_w;

            // The source flags are a raw one-cycle event landing position.
            // Capture them without feeding the already-sticky fault fence
            // back into their D path.  The rich stage below installs payload
            // only while local_error_valid_q is clear, so later events cannot
            // replace first-error identity; reset-class later events may still
            // raise reset_required through fault_reset_now.
            fault_source_flags_q[0] <= fault_live_sources0_w;
            fault_source_flags_q[1] <= fault_live_sources1_w;

            // The registered source bundle is already an architecturally
            // visible held event.  Transfer it into the immutable first-error
            // record (or reset escalation) and create a pending event only if
            // the directly exposed bundle did not handshake on this edge.
            for (i = 0; i < 2; i = i + 1) begin
                if (fault_now[i]) begin
                    // A later internal correlation/order failure may be more
                    // severe than the already-retained first error.  Preserve
                    // the sticky first-error payload, but never lose its
                    // coordinated-reset escalation.
                    if (fault_reset_now[i])
                        reset_required_q[i] <= 1'b1;
                    if (!local_error_valid_q[i]) begin
                        local_error_valid_q[i] <= 1'b1;
                        local_error_code_q[i] <= fault_code_now[i];
                        local_error_source_q[i] <= fault_source_now[i];
                        local_error_detail_q[i] <= fault_detail_now[i];
                        local_error_directory_generation_q[i] <=
                            fault_scope_directory_generation_q[i];
                        local_error_physical_bank_generation_q[i] <=
                            fault_scope_physical_bank_generation_q[i];
                        local_error_stage_ticket_q[i] <=
                            fault_scope_stage_ticket_q[i];
                        local_error_content_handle_q[i] <=
                            fault_scope_content_handle_q[i];
                        if (!(fault_event_fire_w &&
                              fault_event_bank_mask[i]))
                            fault_event_pending_q[i] <= 1'b1;
                        else
                            fault_event_pending_q[i] <= 1'b0;
                    end
                end
            end
        end
    end

    assign close_complete = close_pending_q &&
        (!close_bank_mask_q[0] || bank_causal_empty_w[0]) &&
        (!close_bank_mask_q[1] || bank_causal_empty_w[1]);

endmodule
