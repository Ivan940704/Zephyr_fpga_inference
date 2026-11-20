`timescale 1ns/1ps
`include "memory/model_memory_v5_map.vh"

// Image-v5 / 32-row production-v2 PE job controller.
//
// This controller intentionally performs one transaction at a time.  A full
// stage is already resident in memory_service; active lists suppress only
// cache weight reads and PE MAC commands.  There is no ping-pong ownership,
// sparse DDR fetch, lookahead, or clean local recovery.
module sequential_pe_job_controller_v5 #(
    parameter integer WAIT_TIMEOUT_CYCLES = 1000000
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         abort,

    input  wire                         job_valid,
    output wire                         job_ready,
    input  wire [3:0]                   job_stage_id,
    input  wire [1:0]                   job_branch,
    input  wire [1:0]                   job_context,
    output reg                          job_done,
    output wire                         job_error,
    output wire                         busy,

    // Read-only active-stage descriptor from memory_service.
    input  wire                         stage_ready_for_compute,
    input  wire                         lut_ready,
    input  wire [3:0]                   active_stage_id,
    input  wire                         active_stage_kind,
    input  wire [1:0]                   active_matrix_count,
    input  wire [9:0]                   active_matrix0_sources,
    input  wire [5:0]                   active_matrix0_row_tiles,
    input  wire [9:0]                   active_matrix1_sources,
    input  wire [5:0]                   active_matrix1_row_tiles,
    input  wire [5:0]                   active_param_tiles,
    input  wire                         active_uses_sigmoid_table,
    input  wire [2:0]                   active_sigmoid_table_select,
    input  wire                         memory_error_valid,

    output wire                         stage_release_valid,
    input  wire                         stage_release_ready,
    output wire [3:0]                   stage_release_id,

    output wire                         weight_req_valid,
    input  wire                         weight_req_ready,
    output wire                         weight_req_matrix,
    output wire [9:0]                   weight_req_source,
    output wire [5:0]                   weight_req_row_tile,
    output wire [7:0]                   weight_req_tag,
    input  wire                         weight_rsp_valid,
    output wire                         weight_rsp_ready,
    input  wire [255:0]                 weight_rsp_data,
    input  wire [7:0]                   weight_rsp_tag,
    input  wire                         weight_rsp_error,

    output wire                         param_req_valid,
    input  wire                         param_req_ready,
    output wire [5:0]                   param_req_row_tile,
    output wire [7:0]                   param_req_tag,
    input  wire                         param_rsp_valid,
    output wire                         param_rsp_ready,
    input  wire [11583:0]               param_rsp_data,
    input  wire                         param_rsp_kind,
    input  wire [13:0]                  param_rsp_bits,
    input  wire [7:0]                   param_rsp_tag,
    input  wire                         param_rsp_error,

    // Dense input scalar provider.  Used only by GSU1 matrix zero.
    output wire                         feature_req_valid,
    input  wire                         feature_req_ready,
    output wire [3:0]                   feature_req_stage_id,
    output wire [1:0]                   feature_req_branch,
    output wire [1:0]                   feature_req_context,
    output wire [9:0]                   feature_req_source,
    output wire [7:0]                   feature_req_tag,
    input  wire                         feature_rsp_valid,
    output wire                         feature_rsp_ready,
    input  wire signed [7:0]            feature_rsp_value,
    input  wire [7:0]                   feature_rsp_tag,
    input  wire                         feature_rsp_error,

    // sequential_recurrent_context_store management/read side.
    output wire                         producer_open_valid,
    input  wire                         producer_open_ready,
    output wire [4:0]                   producer_open_logical_id,
    output wire [5:0]                   producer_open_row_tiles,

    output wire                         list_desc_req_valid,
    input  wire                         list_desc_req_ready,
    output wire [4:0]                   list_desc_req_logical_id,
    output wire [7:0]                   list_desc_req_tag,
    input  wire                         list_desc_rsp_valid,
    output wire                         list_desc_rsp_ready,
    input  wire [8:0]                   list_desc_rsp_count,
    input  wire [7:0]                   list_desc_rsp_tag,
    input  wire                         list_desc_rsp_error,

    output wire                         list_read_req_valid,
    input  wire                         list_read_req_ready,
    output wire [4:0]                   list_read_req_logical_id,
    output wire [8:0]                   list_read_req_ordinal,
    output wire [7:0]                   list_read_req_tag,
    input  wire                         list_read_rsp_valid,
    output wire                         list_read_rsp_ready,
    input  wire [8:0]                   list_read_rsp_index,
    input  wire [7:0]                   list_read_rsp_tag,
    input  wire                         list_read_rsp_error,

    output wire                         state_read_req_valid,
    input  wire                         state_read_req_ready,
    output wire [4:0]                   state_read_req_logical_id,
    output wire [4:0]                   state_read_req_row_tile,
    output wire [7:0]                   state_read_req_tag,
    input  wire                         state_read_rsp_valid,
    output wire                         state_read_rsp_ready,
    input  wire [255:0]                 state_read_rsp_data,
    input  wire [7:0]                   state_read_rsp_tag,
    input  wire                         state_read_rsp_error,

    output wire                         context_commit_valid,
    input  wire                         context_commit_ready,
    output wire [4:0]                   context_commit_logical_id,
    output wire                         context_commit_pe_barrier_idle,
    input  wire                         context_commit_done,
    input  wire                         context_error_valid,

    // Frozen pe_array_datapath controller boundary.
    output wire                         raw_owner_request,
    input  wire                         raw_owner_grant,
    output wire                         gate_owner_request,
    input  wire                         gate_owner_grant,
    input  wire [3:0]                   compute_owner,
    input  wire                         compute_idle,

    output reg  [31:0]                  ctrl_pe_acc_clear,
    output reg  [31:0]                  ctrl_pe_acc_enable,
    output reg  [1:0]                   ctrl_pe_mode,
    output reg  [255:0]                 ctrl_pe_operand_a,
    output reg  [255:0]                 ctrl_pe_operand_b,
    output reg  [255:0]                 ctrl_pe_gate_u8,
    output reg  [31:0]                  ctrl_pe_spike_enable,
    output reg  [1023:0]                ctrl_pe_direct_value,
    input  wire [1023:0]                pe_accumulator,
    input  wire [31:0]                  pe_overflow,

    output wire                         gate_tile_valid,
    input  wire                         gate_tile_ready,
    output wire [31:0]                  gate_tile_lane_valid,
    output reg  [511:0]                 gate_tile_tags,
    output wire [2:0]                   gate_tile_table_select,
    input  wire                         gate_collect_complete,

    output wire                         gate_rq_valid,
    input  wire                         gate_rq_ready,
    output wire [3:0]                   gate_rq_lane_valid,
    output reg  [127:0]                 gate_rq_value,
    output reg  [127:0]                 gate_rq_multiplier,
    output reg  [23:0]                  gate_rq_shift,
    output wire                         gate_rq_gate,
    output wire                         gate_rq_component,
    output wire [2:0]                   gate_rq_group,
    output reg  [63:0]                  gate_rq_tags,

    output wire                         gate_bias_valid,
    input  wire                         gate_bias_ready,
    output wire                         gate_bias_gate,
    output wire [2:0]                   gate_bias_group,
    output wire [3:0]                   gate_bias_lane_valid,
    output reg  [127:0]                 gate_bias_value,
    output reg  [63:0]                  gate_bias_tags,

    input  wire                         sigmoid_table_valid,
    output wire                         membrane_start_valid,
    input  wire                         membrane_start_ready,
    output wire [255:0]                 membrane_u_prev,
    output wire [1023:0]                membrane_cx_multiplier,
    output wire [191:0]                 membrane_cx_shift,
    output wire [1023:0]                membrane_cell_multiplier,
    output wire [191:0]                 membrane_cell_shift,
    output wire [8:0]                   membrane_base_index,
    output wire                         membrane_logical_last,
    input  wire                         membrane_done,

    output wire                         linear_tile_valid,
    input  wire                         linear_tile_ready,
    output wire [31:0]                  linear_tile_lane_valid,
    output wire [8:0]                   linear_tile_base_index,
    output reg  [511:0]                 linear_tile_tags,
    output wire                         linear_tile_logical_last,

    input  wire                         rq_param_query_valid,
    input  wire                         rq_param_query_op_kind,
    input  wire [8:0]                   rq_param_query_index,
    input  wire [15:0]                  rq_param_query_tag,
    output wire                         rq_param_valid,
    input  wire                         rq_param_ready,
    output wire                         rq_param_op_kind,
    output reg  signed [31:0]            rq_param_multiplier,
    output reg  [5:0]                   rq_param_shift,
    output reg  signed [31:0]            rq_param_bias,
    output wire [8:0]                   rq_param_index,
    output wire [15:0]                  rq_param_tag,

    input  wire                         hybrid_idle,
    input  wire                         local_rq_idle,
    input  wire                         postprocess_idle,
    input  wire                         sigmoid_idle,
    input  wire                         serializer_idle,
    input  wire                         shared_rq_idle,
    input  wire                         qbn_fork_idle,
    input  wire [4:0]                   local_rq_outstanding,
    input  wire [4:0]                   postprocess_outstanding,
    input  wire [4:0]                   shared_rq_outstanding,
    input  wire                         overflow_any,
    input  wire                         protocol_error,

    output wire                         pe_barrier_idle,
    output reg                          error_valid,
    output reg  [7:0]                   error_code,
    output reg  [31:0]                  error_detail,
    output wire                         reset_required,
    output wire [5:0]                   controller_state,
    output wire [5:0]                   current_row_tile,
    output reg  [31:0]                  weight_request_count,
    output reg  [31:0]                  dense_weight_request_count,
    output reg  [31:0]                  sparse_weight_request_count
);
    localparam [5:0] ST_IDLE          = 6'd0;
    localparam [5:0] ST_OPEN          = 6'd1;
    localparam [5:0] ST_DESC0_REQ     = 6'd2;
    localparam [5:0] ST_DESC0_WAIT    = 6'd3;
    localparam [5:0] ST_DESC1_REQ     = 6'd4;
    localparam [5:0] ST_DESC1_WAIT    = 6'd5;
    localparam [5:0] ST_PARAM_REQ     = 6'd6;
    localparam [5:0] ST_PARAM_WAIT    = 6'd7;
    localparam [5:0] ST_STATE_REQ     = 6'd8;
    localparam [5:0] ST_STATE_WAIT    = 6'd9;
    localparam [5:0] ST_RAW_ACQUIRE   = 6'd10;
    localparam [5:0] ST_CLEAR         = 6'd11;
    localparam [5:0] ST_CLEAR_WAIT    = 6'd12;
    localparam [5:0] ST_SOURCE_PREP   = 6'd13;
    localparam [5:0] ST_LIST_REQ      = 6'd14;
    localparam [5:0] ST_LIST_WAIT     = 6'd15;
    localparam [5:0] ST_FEATURE_REQ   = 6'd16;
    localparam [5:0] ST_FEATURE_WAIT  = 6'd17;
    localparam [5:0] ST_WEIGHT_REQ    = 6'd18;
    localparam [5:0] ST_WEIGHT_WAIT   = 6'd19;
    localparam [5:0] ST_MAC           = 6'd20;
    localparam [5:0] ST_MATRIX_DRAIN  = 6'd21;
    localparam [5:0] ST_RAW_RELEASE   = 6'd22;
    localparam [5:0] ST_GATE_ACQUIRE  = 6'd23;
    localparam [5:0] ST_GATE_TILE     = 6'd24;
    localparam [5:0] ST_GATE_INPUT    = 6'd25;
    localparam [5:0] ST_GATE_REC      = 6'd26;
    localparam [5:0] ST_GATE_BIAS     = 6'd27;
    localparam [5:0] ST_GATE_COLLECT  = 6'd28;
    localparam [5:0] ST_MEM_START     = 6'd29;
    localparam [5:0] ST_MEM_WAIT      = 6'd30;
    localparam [5:0] ST_LINEAR        = 6'd31;
    localparam [5:0] ST_TILE_DRAIN    = 6'd32;
    localparam [5:0] ST_COMMIT_REQ    = 6'd33;
    localparam [5:0] ST_COMMIT_WAIT   = 6'd34;
    localparam [5:0] ST_RELEASE       = 6'd35;
    localparam [5:0] ST_DONE          = 6'd36;
    localparam [5:0] ST_ERROR         = 6'd63;

    localparam [7:0] ERR_NONE          = 8'h00;
    localparam [7:0] ERR_JOB           = 8'h01;
    localparam [7:0] ERR_STAGE         = 8'h02;
    localparam [7:0] ERR_MEMORY        = 8'h03;
    localparam [7:0] ERR_CONTEXT       = 8'h04;
    localparam [7:0] ERR_FEATURE       = 8'h05;
    localparam [7:0] ERR_PE_PROTOCOL   = 8'h06;
    localparam [7:0] ERR_PE_OVERFLOW   = 8'h07;
    localparam [7:0] ERR_RESPONSE      = 8'h08;
    localparam [7:0] ERR_LIST_INDEX    = 8'h09;
    localparam [7:0] ERR_RQ_QUERY      = 8'h0a;
    localparam [7:0] ERR_COMMIT        = 8'h0b;
    localparam [7:0] ERR_TIMEOUT       = 8'h0c;
    localparam [7:0] ERR_ABORT         = 8'h0d;

    localparam [1:0] MODE_DENSE = 2'd0;
    localparam [1:0] MODE_SPIKE = 2'd1;

    reg [5:0] state_q;
    reg [5:0] state_prev_q;
    reg [31:0] state_cycle_count_q;

    reg [3:0] stage_id_q;
    reg [1:0] branch_q;
    reg [1:0] context_q;
    reg is_projection_q;
    reg is_gsu2_q;
    reg matrix0_dense_q;
    reg final_cache_user_q;
    reg [4:0] logical_id_q;
    reg [4:0] matrix0_list_id_q;
    reg [4:0] matrix1_list_id_q;
    reg [4:0] tag_logical_id_q;
    reg [2:0] sigmoid_select_q;
    reg [9:0] matrix0_sources_q;
    reg [9:0] matrix1_sources_q;
    reg [5:0] row_tiles_q;
    reg [5:0] row_tile_q;

    reg [8:0] matrix0_active_count_q;
    reg [8:0] matrix1_active_count_q;
    reg current_matrix_q;
    reg [9:0] source_ordinal_q;
    reg [9:0] source_index_q;
    reg signed [7:0] feature_value_q;
    reg [255:0] weight_word_q;
    // memory_service_v5 owns the parameter record until the controller asks
    // for the next row tile.  Consume that held record in place instead of
    // copying all 11,584 bits into a second register bank at response accept.
    // ST_TILE_DRAIN is the only path back to ST_PARAM_REQ, after every user of
    // the current record has drained, so the service cannot overwrite live
    // parameters.
    wire [11583:0] parameter_record_q;
    reg parameter_record_valid_q;
    reg [255:0] old_state_tile_q;
    reg [1023:0] matrix0_snapshot_q;
    reg gate_q;
    reg [2:0] gate_group_q;

    reg [7:0] memory_tag_q;
    reg [7:0] context_tag_q;
    reg [7:0] feature_tag_q;

    assign parameter_record_q = param_rsp_data;

    function is_projection_stage;
        input [3:0] stage_id;
        begin
            case (stage_id)
                4'd2, 4'd5, 4'd8, 4'd11:
                    is_projection_stage = 1'b1;
                default: is_projection_stage = 1'b0;
            endcase
        end
    endfunction

    function is_gsu2_stage;
        input [3:0] stage_id;
        begin
            case (stage_id)
                4'd1, 4'd4, 4'd7, 4'd10:
                    is_gsu2_stage = 1'b1;
                default: is_gsu2_stage = 1'b0;
            endcase
        end
    endfunction

    function is_dense_input_stage;
        input [3:0] stage_id;
        begin
            case (stage_id)
                4'd0, 4'd3, 4'd6, 4'd9:
                    is_dense_input_stage = 1'b1;
                default: is_dense_input_stage = 1'b0;
            endcase
        end
    endfunction

    function legal_job_tuple;
        input [3:0] stage_id;
        input [1:0] branch_id;
        input [1:0] context_id;
        begin
            legal_job_tuple = 1'b0;
            case (branch_id)
                2'd0: legal_job_tuple = (stage_id <= 4'd2) &&
                                         (context_id == 2'd0);
                2'd1: legal_job_tuple = (stage_id >= 4'd3) &&
                                         (stage_id <= 4'd5);
                2'd2: legal_job_tuple = (stage_id >= 4'd6) &&
                                         (stage_id <= 4'd8) &&
                                         (context_id <= 2'd2);
                2'd3: legal_job_tuple = (stage_id >= 4'd9) &&
                                         (stage_id <= 4'd11) &&
                                         (context_id <= 2'd1);
            endcase
        end
    endfunction

    function [4:0] context_identity;
        input [1:0] branch_id;
        input [1:0] context_id;
        input layer;
        begin
            case (branch_id)
                2'd0: context_identity = {4'd0, layer};
                2'd1: context_identity = 5'd2 +
                    {context_id, 1'b0} + layer;
                2'd2: context_identity = 5'd10 +
                    {context_id, 1'b0} + layer;
                default: context_identity = 5'd16 +
                    {context_id, 1'b0} + layer;
            endcase
        end
    endfunction

    function final_context;
        input [1:0] branch_id;
        input [1:0] context_id;
        begin
            case (branch_id)
                2'd0: final_context = 1'b1;
                2'd1: final_context = (context_id == 2'd3);
                2'd2: final_context = (context_id == 2'd2);
                default: final_context = (context_id == 2'd1);
            endcase
        end
    endfunction

    function [9:0] expected_matrix0_sources;
        input [3:0] stage_id;
        begin
            case (stage_id)
                4'd0: expected_matrix0_sources = 10'd64;
                4'd1, 4'd2: expected_matrix0_sources = 10'd320;
                4'd3: expected_matrix0_sources = 10'd46;
                4'd4, 4'd5: expected_matrix0_sources = 10'd224;
                4'd6: expected_matrix0_sources = 10'd94;
                4'd7, 4'd8: expected_matrix0_sources = 10'd224;
                4'd9: expected_matrix0_sources = 10'd158;
                default: expected_matrix0_sources = 10'd224;
            endcase
        end
    endfunction

    function [9:0] expected_matrix1_sources;
        input [3:0] stage_id;
        begin
            case (stage_id)
                4'd0, 4'd1: expected_matrix1_sources = 10'd320;
                4'd3, 4'd4, 4'd6, 4'd7, 4'd9, 4'd10:
                    expected_matrix1_sources = 10'd224;
                default: expected_matrix1_sources = 10'd0;
            endcase
        end
    endfunction

    function [5:0] expected_row_tiles;
        input [3:0] stage_id;
        begin
            case (stage_id)
                4'd0, 4'd1: expected_row_tiles = 6'd10;
                4'd2: expected_row_tiles = 6'd2;
                4'd3, 4'd4, 4'd6, 4'd7, 4'd9, 4'd10:
                    expected_row_tiles = 6'd7;
                4'd5: expected_row_tiles = 6'd3;
                4'd8: expected_row_tiles = 6'd6;
                default: expected_row_tiles = 6'd4;
            endcase
        end
    endfunction

    function [2:0] expected_sigmoid_select;
        input [3:0] stage_id;
        begin
            case (stage_id)
                4'd0: expected_sigmoid_select = 3'd0;
                4'd1: expected_sigmoid_select = 3'd1;
                4'd3: expected_sigmoid_select = 3'd2;
                4'd4: expected_sigmoid_select = 3'd3;
                4'd6: expected_sigmoid_select = 3'd4;
                4'd7: expected_sigmoid_select = 3'd5;
                4'd9: expected_sigmoid_select = 3'd6;
                4'd10: expected_sigmoid_select = 3'd7;
                default: expected_sigmoid_select = 3'd0;
            endcase
        end
    endfunction

    function [8:0] neuron_index;
        input [5:0] tile;
        input [4:0] lane;
        begin
            neuron_index = {tile[3:0], 5'b00000} + {4'd0, lane};
        end
    endfunction

    function [15:0] make_pe_tag;
        input [1:0] kind;
        input [4:0] logical_id;
        input [8:0] index;
        begin
            make_pe_tag = {kind, logical_id, index};
        end
    endfunction

    wire requested_projection = is_projection_stage(job_stage_id);
    wire requested_gsu2 = is_gsu2_stage(job_stage_id);
    wire requested_dense_input = is_dense_input_stage(job_stage_id);
    wire [5:0] requested_rows = expected_row_tiles(job_stage_id);
    wire descriptor_contract_ok = stage_ready_for_compute && lut_ready &&
        (active_stage_id == job_stage_id) &&
        (active_stage_kind == requested_projection) &&
        (active_matrix_count == (requested_projection ? 2'd1 : 2'd2)) &&
        (active_matrix0_sources ==
         expected_matrix0_sources(job_stage_id)) &&
        (active_matrix0_row_tiles == requested_rows) &&
        (active_param_tiles == requested_rows) &&
        (active_matrix1_sources ==
         expected_matrix1_sources(job_stage_id)) &&
        (active_matrix1_row_tiles ==
         (requested_projection ? 6'd0 : requested_rows)) &&
        (active_uses_sigmoid_table == !requested_projection) &&
        (requested_projection ||
         (active_sigmoid_table_select ==
          expected_sigmoid_select(job_stage_id))) &&
        (requested_projection || sigmoid_table_valid);

    wire current_sparse = !(matrix0_dense_q && !current_matrix_q);
    wire [9:0] current_iteration_count = current_matrix_q
        ? {1'b0, matrix1_active_count_q}
        : matrix0_dense_q ? matrix0_sources_q
        : {1'b0, matrix0_active_count_q};
    wire [4:0] current_list_id = current_matrix_q
        ? matrix1_list_id_q : matrix0_list_id_q;

    wire controller_pe_inputs_idle =
        (ctrl_pe_acc_clear == 32'd0) &&
        (ctrl_pe_acc_enable == 32'd0) &&
        !raw_owner_request && !gate_owner_request &&
        !gate_tile_valid && !gate_rq_valid && !gate_bias_valid &&
        !membrane_start_valid && !linear_tile_valid && !rq_param_valid;

    assign pe_barrier_idle = compute_idle && serializer_idle &&
        shared_rq_idle && qbn_fork_idle && local_rq_idle &&
        postprocess_idle && sigmoid_idle &&
        (local_rq_outstanding == 0) &&
        (postprocess_outstanding == 0) &&
        (shared_rq_outstanding == 0) && controller_pe_inputs_idle;

    assign job_ready = rst_n && (state_q == ST_IDLE) && !error_valid;
    assign job_error = error_valid;
    assign busy = (state_q != ST_IDLE) && (state_q != ST_ERROR);
    assign reset_required = error_valid;
    assign controller_state = state_q;
    assign current_row_tile = row_tile_q;

    assign stage_release_valid = (state_q == ST_RELEASE) && !error_valid;
    assign stage_release_id = stage_id_q;

    assign weight_req_valid = (state_q == ST_WEIGHT_REQ) && !error_valid;
    assign weight_req_matrix = current_matrix_q;
    assign weight_req_source = source_index_q;
    assign weight_req_row_tile = row_tile_q;
    assign weight_req_tag = memory_tag_q;
    assign weight_rsp_ready = (state_q == ST_WEIGHT_WAIT) && !error_valid;

    assign param_req_valid = (state_q == ST_PARAM_REQ) && !error_valid;
    assign param_req_row_tile = row_tile_q;
    assign param_req_tag = memory_tag_q;
    assign param_rsp_ready = (state_q == ST_PARAM_WAIT) && !error_valid;

    assign feature_req_valid = (state_q == ST_FEATURE_REQ) && !error_valid;
    assign feature_req_stage_id = stage_id_q;
    assign feature_req_branch = branch_q;
    assign feature_req_context = context_q;
    assign feature_req_source = source_ordinal_q;
    assign feature_req_tag = feature_tag_q;
    assign feature_rsp_ready = (state_q == ST_FEATURE_WAIT) && !error_valid;

    assign producer_open_valid = (state_q == ST_OPEN) && !error_valid;
    assign producer_open_logical_id = logical_id_q;
    assign producer_open_row_tiles = row_tiles_q;

    assign list_desc_req_valid =
        ((state_q == ST_DESC0_REQ) || (state_q == ST_DESC1_REQ)) &&
        !error_valid;
    assign list_desc_req_logical_id = (state_q == ST_DESC1_REQ)
        ? matrix1_list_id_q : matrix0_list_id_q;
    assign list_desc_req_tag = context_tag_q;
    assign list_desc_rsp_ready =
        ((state_q == ST_DESC0_WAIT) || (state_q == ST_DESC1_WAIT)) &&
        !error_valid;

    assign list_read_req_valid = (state_q == ST_LIST_REQ) && !error_valid;
    assign list_read_req_logical_id = current_list_id;
    assign list_read_req_ordinal = source_ordinal_q[8:0];
    assign list_read_req_tag = context_tag_q;
    assign list_read_rsp_ready = (state_q == ST_LIST_WAIT) && !error_valid;

    assign state_read_req_valid = (state_q == ST_STATE_REQ) && !error_valid;
    assign state_read_req_logical_id = logical_id_q;
    assign state_read_req_row_tile = row_tile_q[4:0];
    assign state_read_req_tag = context_tag_q;
    assign state_read_rsp_ready = (state_q == ST_STATE_WAIT) && !error_valid;

    assign context_commit_valid = (state_q == ST_COMMIT_REQ) && !error_valid;
    assign context_commit_logical_id = logical_id_q;
    assign context_commit_pe_barrier_idle = pe_barrier_idle;

    assign raw_owner_request = !error_valid &&
        ((state_q == ST_RAW_ACQUIRE) ||
         (state_q == ST_CLEAR) || (state_q == ST_CLEAR_WAIT) ||
         (state_q == ST_SOURCE_PREP) ||
         (state_q == ST_LIST_REQ) || (state_q == ST_LIST_WAIT) ||
         (state_q == ST_FEATURE_REQ) || (state_q == ST_FEATURE_WAIT) ||
         (state_q == ST_WEIGHT_REQ) || (state_q == ST_WEIGHT_WAIT) ||
         (state_q == ST_MAC) || (state_q == ST_MATRIX_DRAIN) ||
         (state_q == ST_LINEAR));

    assign gate_owner_request = !error_valid &&
        ((state_q == ST_GATE_ACQUIRE) || (state_q == ST_GATE_TILE) ||
         (state_q == ST_GATE_INPUT) || (state_q == ST_GATE_REC) ||
         (state_q == ST_GATE_BIAS) || (state_q == ST_GATE_COLLECT));

    assign gate_tile_valid = (state_q == ST_GATE_TILE) && !error_valid;
    assign gate_tile_lane_valid = 32'hffff_ffff;
    assign gate_tile_table_select = sigmoid_select_q;

    assign gate_rq_valid =
        ((state_q == ST_GATE_INPUT) || (state_q == ST_GATE_REC)) &&
        !error_valid;
    assign gate_rq_lane_valid = 4'hf;
    assign gate_rq_gate = gate_q;
    assign gate_rq_component = (state_q == ST_GATE_REC);
    assign gate_rq_group = gate_group_q;

    assign gate_bias_valid = (state_q == ST_GATE_BIAS) && !error_valid;
    assign gate_bias_gate = gate_q;
    assign gate_bias_group = gate_group_q;
    assign gate_bias_lane_valid = 4'hf;

    assign membrane_start_valid = (state_q == ST_MEM_START) && !error_valid;
    assign membrane_u_prev = old_state_tile_q;
    assign membrane_cx_multiplier = parameter_record_q[
        `MODEL_V5_GSU_PARAM_PREVIOUS_MULTIPLIER_LSB +: 1024];
    assign membrane_cx_shift = parameter_record_q[
        `MODEL_V5_GSU_PARAM_PREVIOUS_SHIFT_LSB +: 192];
    assign membrane_cell_multiplier = parameter_record_q[
        `MODEL_V5_GSU_PARAM_CELLGATE_MULTIPLIER_LSB +: 1024];
    assign membrane_cell_shift = parameter_record_q[
        `MODEL_V5_GSU_PARAM_CELLGATE_SHIFT_LSB +: 192];
    assign membrane_base_index = {row_tile_q[3:0], 5'b00000};
    assign membrane_logical_last = (row_tile_q == (row_tiles_q - 1'b1));

    assign linear_tile_valid = (state_q == ST_LINEAR) && !error_valid;
    assign linear_tile_lane_valid = 32'hffff_ffff;
    assign linear_tile_base_index = {row_tile_q[3:0], 5'b00000};
    assign linear_tile_logical_last =
        (row_tile_q == (row_tiles_q - 1'b1));

    wire [8:0] rq_tile_base = {row_tile_q[3:0], 5'b00000};
    wire rq_window = parameter_record_valid_q &&
        ((is_projection_q && (state_q == ST_TILE_DRAIN)) ||
         (!is_projection_q &&
          ((state_q == ST_MEM_WAIT) || (state_q == ST_TILE_DRAIN))));
    wire [15:0] rq_expected_tag = make_pe_tag(
        is_projection_q ? 2'b01 : 2'b00,
        tag_logical_id_q, rq_param_query_index);
    wire rq_query_match = rq_window &&
        (rq_param_query_op_kind == is_projection_q) &&
        (rq_param_query_index >= rq_tile_base) &&
        (rq_param_query_index < (rq_tile_base + 9'd32)) &&
        (rq_param_query_tag == rq_expected_tag);

    assign rq_param_valid = rq_param_query_valid && rq_query_match &&
                            !error_valid;
    assign rq_param_op_kind = rq_param_query_op_kind;
    assign rq_param_index = rq_param_query_index;
    assign rq_param_tag = rq_param_query_tag;

    integer output_lane;
    integer group_lane;
    integer selected_lane;
    always @* begin
        gate_tile_tags = 512'd0;
        linear_tile_tags = 512'd0;
        for (output_lane = 0; output_lane < 32;
             output_lane = output_lane + 1) begin
            gate_tile_tags[output_lane*16 +: 16] = make_pe_tag(
                2'b00, tag_logical_id_q,
                neuron_index(row_tile_q, output_lane[4:0]));
            linear_tile_tags[output_lane*16 +: 16] = make_pe_tag(
                2'b01, tag_logical_id_q,
                neuron_index(row_tile_q, output_lane[4:0]));
        end
    end

    always @* begin
        ctrl_pe_acc_clear = 32'd0;
        ctrl_pe_acc_enable = 32'd0;
        ctrl_pe_mode = MODE_DENSE;
        ctrl_pe_operand_a = 256'd0;
        ctrl_pe_operand_b = 256'd0;
        ctrl_pe_gate_u8 = 256'd0;
        ctrl_pe_spike_enable = 32'd0;
        ctrl_pe_direct_value = 1024'd0;
        if (state_q == ST_CLEAR) begin
            ctrl_pe_acc_clear = 32'hffff_ffff;
        end else if (state_q == ST_MAC) begin
            ctrl_pe_acc_enable = 32'hffff_ffff;
            ctrl_pe_operand_b = weight_word_q;
            if (current_sparse) begin
                ctrl_pe_mode = MODE_SPIKE;
                ctrl_pe_spike_enable = 32'hffff_ffff;
            end else begin
                ctrl_pe_mode = MODE_DENSE;
                ctrl_pe_operand_a = {32{feature_value_q}};
            end
        end
    end

    always @* begin
        gate_rq_value = 128'd0;
        gate_rq_multiplier = 128'd0;
        gate_rq_shift = 24'd0;
        gate_rq_tags = 64'd0;
        gate_bias_value = 128'd0;
        gate_bias_tags = 64'd0;

        if (state_q == ST_GATE_INPUT)
            gate_rq_value = matrix0_snapshot_q[gate_group_q*128 +: 128];
        else
            gate_rq_value = pe_accumulator[gate_group_q*128 +: 128];

        if (!gate_q) begin
            if (state_q == ST_GATE_INPUT) begin
                gate_rq_multiplier = parameter_record_q[
                    `MODEL_V5_GSU_PARAM_FORGET_INPUT_MULTIPLIER_LSB +
                    gate_group_q*128 +: 128];
                gate_rq_shift = parameter_record_q[
                    `MODEL_V5_GSU_PARAM_FORGET_INPUT_SHIFT_LSB +
                    gate_group_q*24 +: 24];
            end else begin
                gate_rq_multiplier = parameter_record_q[
                    `MODEL_V5_GSU_PARAM_FORGET_RECURRENT_MULTIPLIER_LSB +
                    gate_group_q*128 +: 128];
                gate_rq_shift = parameter_record_q[
                    `MODEL_V5_GSU_PARAM_FORGET_RECURRENT_SHIFT_LSB +
                    gate_group_q*24 +: 24];
            end
            gate_bias_value = parameter_record_q[
                `MODEL_V5_GSU_PARAM_FORGET_BIAS_Q_LSB +
                gate_group_q*128 +: 128];
        end else begin
            if (state_q == ST_GATE_INPUT) begin
                gate_rq_multiplier = parameter_record_q[
                    `MODEL_V5_GSU_PARAM_CELL_INPUT_MULTIPLIER_LSB +
                    gate_group_q*128 +: 128];
                gate_rq_shift = parameter_record_q[
                    `MODEL_V5_GSU_PARAM_CELL_INPUT_SHIFT_LSB +
                    gate_group_q*24 +: 24];
            end else begin
                gate_rq_multiplier = parameter_record_q[
                    `MODEL_V5_GSU_PARAM_CELL_RECURRENT_MULTIPLIER_LSB +
                    gate_group_q*128 +: 128];
                gate_rq_shift = parameter_record_q[
                    `MODEL_V5_GSU_PARAM_CELL_RECURRENT_SHIFT_LSB +
                    gate_group_q*24 +: 24];
            end
            gate_bias_value = parameter_record_q[
                `MODEL_V5_GSU_PARAM_CELL_BIAS_Q_LSB +
                gate_group_q*128 +: 128];
        end

        for (group_lane = 0; group_lane < 4;
             group_lane = group_lane + 1) begin
            selected_lane = gate_group_q*4 + group_lane;
            gate_rq_tags[group_lane*16 +: 16] = make_pe_tag(
                2'b00, tag_logical_id_q,
                neuron_index(row_tile_q, selected_lane[4:0]));
            gate_bias_tags[group_lane*16 +: 16] = make_pe_tag(
                2'b00, tag_logical_id_q,
                neuron_index(row_tile_q, selected_lane[4:0]));
        end
    end

    always @* begin
        rq_param_multiplier = 32'sd0;
        rq_param_shift = 6'd0;
        rq_param_bias = 32'sd0;
        if (is_projection_q) begin
            rq_param_multiplier = parameter_record_q[
                `MODEL_V5_PROJECTION_PARAM_OUTPUT_MULTIPLIER_LSB +
                rq_param_query_index[4:0]*32 +: 32];
            rq_param_shift = parameter_record_q[
                `MODEL_V5_PROJECTION_PARAM_OUTPUT_SHIFT_LSB +
                rq_param_query_index[4:0]*6 +: 6];
            rq_param_bias = parameter_record_q[
                `MODEL_V5_PROJECTION_PARAM_OUTPUT_BIAS_Q_LSB +
                rq_param_query_index[4:0]*32 +: 32];
        end else begin
            rq_param_multiplier = parameter_record_q[
                `MODEL_V5_GSU_PARAM_BN_MULTIPLIER_LSB +
                rq_param_query_index[4:0]*32 +: 32];
            rq_param_shift = parameter_record_q[
                `MODEL_V5_GSU_PARAM_BN_SHIFT_LSB +
                rq_param_query_index[4:0]*6 +: 6];
            rq_param_bias = parameter_record_q[
                `MODEL_V5_GSU_PARAM_BN_BIAS_Q_LSB +
                rq_param_query_index[4:0]*32 +: 32];
        end
    end

    wire timeout_enabled = (WAIT_TIMEOUT_CYCLES != 0);
    wire timeout_hit = timeout_enabled &&
        (state_q != ST_IDLE) && (state_q != ST_DONE) &&
        (state_q != ST_ERROR) &&
        (state_cycle_count_q >= WAIT_TIMEOUT_CYCLES - 1);

    task enter_fault;
        input [7:0] code;
        input [31:0] detail;
        begin
            if (!error_valid) begin
                error_valid <= 1'b1;
                error_code <= code;
                error_detail <= detail;
            end
            state_q <= ST_ERROR;
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            state_q <= ST_IDLE;
            state_prev_q <= ST_IDLE;
            state_cycle_count_q <= 32'd0;
            stage_id_q <= 4'd0;
            branch_q <= 2'd0;
            context_q <= 2'd0;
            is_projection_q <= 1'b0;
            is_gsu2_q <= 1'b0;
            matrix0_dense_q <= 1'b0;
            final_cache_user_q <= 1'b0;
            logical_id_q <= 5'd0;
            matrix0_list_id_q <= 5'd0;
            matrix1_list_id_q <= 5'd0;
            tag_logical_id_q <= 5'd0;
            sigmoid_select_q <= 3'd0;
            matrix0_sources_q <= 10'd0;
            matrix1_sources_q <= 10'd0;
            row_tiles_q <= 6'd0;
            row_tile_q <= 6'd0;
            matrix0_active_count_q <= 9'd0;
            matrix1_active_count_q <= 9'd0;
            current_matrix_q <= 1'b0;
            source_ordinal_q <= 10'd0;
            source_index_q <= 10'd0;
            feature_value_q <= 8'sd0;
            weight_word_q <= 256'd0;
            parameter_record_valid_q <= 1'b0;
            old_state_tile_q <= 256'd0;
            matrix0_snapshot_q <= 1024'd0;
            gate_q <= 1'b0;
            gate_group_q <= 3'd0;
            memory_tag_q <= 8'd0;
            context_tag_q <= 8'd0;
            feature_tag_q <= 8'd0;
            job_done <= 1'b0;
            error_valid <= 1'b0;
            error_code <= ERR_NONE;
            error_detail <= 32'd0;
            weight_request_count <= 32'd0;
            dense_weight_request_count <= 32'd0;
            sparse_weight_request_count <= 32'd0;
        end else begin
            job_done <= 1'b0;
            state_prev_q <= state_q;
            if (state_q != state_prev_q)
                state_cycle_count_q <= 32'd0;
            else if ((state_q != ST_IDLE) && (state_q != ST_ERROR))
                state_cycle_count_q <= state_cycle_count_q + 1'b1;
            else
                state_cycle_count_q <= 32'd0;

            if (memory_error_valid) begin
                enter_fault(ERR_MEMORY, {24'd0, state_q, 2'd0});
            end else if (context_error_valid) begin
                enter_fault(ERR_CONTEXT, {24'd0, state_q, 2'd0});
            end else if (protocol_error) begin
                enter_fault(ERR_PE_PROTOCOL, {24'd0, state_q, 2'd0});
            end else if (overflow_any || (pe_overflow != 32'd0)) begin
                enter_fault(ERR_PE_OVERFLOW,
                            pe_overflow);
            end else if (abort && busy) begin
                enter_fault(ERR_ABORT, {24'd0, state_q, 2'd0});
            end else if (timeout_hit) begin
                enter_fault(ERR_TIMEOUT,
                            {state_q, state_cycle_count_q[25:0]});
            end else if (rq_param_query_valid && !rq_query_match && busy) begin
                enter_fault(ERR_RQ_QUERY,
                            {6'd0, rq_param_query_op_kind,
                             rq_param_query_index,
                             rq_param_query_tag});
            end else begin
                case (state_q)
                    ST_IDLE: begin
                        parameter_record_valid_q <= 1'b0;
                        if (job_valid && job_ready) begin
                            if (!legal_job_tuple(job_stage_id, job_branch,
                                                 job_context)) begin
                                enter_fault(ERR_JOB,
                                    {24'd0, job_stage_id,
                                     job_branch, job_context});
                            end else if (!descriptor_contract_ok) begin
                                enter_fault(ERR_STAGE,
                                    {8'd0, active_stage_id,
                                     job_stage_id, active_matrix_count,
                                     active_matrix0_row_tiles,
                                     active_param_tiles});
                            end else if (!pe_barrier_idle) begin
                                enter_fault(ERR_PE_PROTOCOL, 32'h00000001);
                            end else begin
                                stage_id_q <= job_stage_id;
                                branch_q <= job_branch;
                                context_q <= job_context;
                                is_projection_q <= requested_projection;
                                is_gsu2_q <= requested_gsu2;
                                matrix0_dense_q <= requested_dense_input;
                                final_cache_user_q <= final_context(
                                    job_branch, job_context);
                                logical_id_q <= context_identity(
                                    job_branch, job_context,
                                    requested_gsu2);
                                matrix0_list_id_q <= context_identity(
                                    job_branch, job_context,
                                    requested_projection ? 1'b1 : 1'b0);
                                matrix1_list_id_q <= context_identity(
                                    job_branch, job_context,
                                    requested_gsu2);
                                tag_logical_id_q <= context_identity(
                                    job_branch, job_context,
                                    requested_projection ? 1'b1 :
                                    requested_gsu2);
                                sigmoid_select_q <=
                                    active_sigmoid_table_select;
                                matrix0_sources_q <=
                                    active_matrix0_sources;
                                matrix1_sources_q <=
                                    active_matrix1_sources;
                                row_tiles_q <= active_param_tiles;
                                row_tile_q <= 6'd0;
                                matrix0_active_count_q <= 9'd0;
                                matrix1_active_count_q <= 9'd0;
                                current_matrix_q <= 1'b0;
                                source_ordinal_q <= 10'd0;
                                memory_tag_q <= 8'd0;
                                context_tag_q <= 8'd0;
                                feature_tag_q <= 8'd0;
                                weight_request_count <= 32'd0;
                                dense_weight_request_count <= 32'd0;
                                sparse_weight_request_count <= 32'd0;
                                if (requested_projection)
                                    state_q <= ST_DESC0_REQ;
                                else
                                    state_q <= ST_OPEN;
                            end
                        end
                    end

                    ST_OPEN: begin
                        if (producer_open_valid && producer_open_ready) begin
                            if (is_gsu2_q)
                                state_q <= ST_DESC0_REQ;
                            else
                                state_q <= ST_DESC1_REQ;
                        end
                    end

                    ST_DESC0_REQ: begin
                        if (list_desc_req_valid && list_desc_req_ready)
                            state_q <= ST_DESC0_WAIT;
                    end

                    ST_DESC0_WAIT: begin
                        if (list_desc_rsp_valid && list_desc_rsp_ready) begin
                            if (list_desc_rsp_error ||
                                (list_desc_rsp_tag != context_tag_q) ||
                                ({1'b0, list_desc_rsp_count} >
                                 matrix0_sources_q)) begin
                                enter_fault(ERR_RESPONSE,
                                    {6'd0, list_desc_rsp_count,
                                     list_desc_rsp_tag, context_tag_q});
                            end else begin
                                matrix0_active_count_q <=
                                    list_desc_rsp_count;
                                context_tag_q <= context_tag_q + 1'b1;
                                if (is_projection_q) begin
                                    row_tile_q <= 6'd0;
                                    state_q <= ST_PARAM_REQ;
                                end else begin
                                    state_q <= ST_DESC1_REQ;
                                end
                            end
                        end
                    end

                    ST_DESC1_REQ: begin
                        if (list_desc_req_valid && list_desc_req_ready)
                            state_q <= ST_DESC1_WAIT;
                    end

                    ST_DESC1_WAIT: begin
                        if (list_desc_rsp_valid && list_desc_rsp_ready) begin
                            if (list_desc_rsp_error ||
                                (list_desc_rsp_tag != context_tag_q) ||
                                ({1'b0, list_desc_rsp_count} >
                                 matrix1_sources_q)) begin
                                enter_fault(ERR_RESPONSE,
                                    {6'd0, list_desc_rsp_count,
                                     list_desc_rsp_tag, context_tag_q});
                            end else begin
                                matrix1_active_count_q <=
                                    list_desc_rsp_count;
                                context_tag_q <= context_tag_q + 1'b1;
                                row_tile_q <= 6'd0;
                                state_q <= ST_PARAM_REQ;
                            end
                        end
                    end

                    ST_PARAM_REQ: begin
                        if (param_req_valid && param_req_ready)
                            state_q <= ST_PARAM_WAIT;
                    end

                    ST_PARAM_WAIT: begin
                        if (param_rsp_valid && param_rsp_ready) begin
                            if (param_rsp_error ||
                                (param_rsp_tag != memory_tag_q) ||
                                (param_rsp_kind != is_projection_q) ||
                                (param_rsp_bits !=
                                 (is_projection_q ? 14'd2240 : 14'd11584))) begin
                                enter_fault(ERR_RESPONSE,
                                    {param_rsp_bits, param_rsp_kind,
                                     is_projection_q, param_rsp_tag,
                                     memory_tag_q});
                            end else begin
                                parameter_record_valid_q <= 1'b1;
                                memory_tag_q <= memory_tag_q + 1'b1;
                                if (is_projection_q)
                                    state_q <= ST_RAW_ACQUIRE;
                                else
                                    state_q <= ST_STATE_REQ;
                            end
                        end
                    end

                    ST_STATE_REQ: begin
                        if (state_read_req_valid && state_read_req_ready)
                            state_q <= ST_STATE_WAIT;
                    end

                    ST_STATE_WAIT: begin
                        if (state_read_rsp_valid && state_read_rsp_ready) begin
                            if (state_read_rsp_error ||
                                (state_read_rsp_tag != context_tag_q)) begin
                                enter_fault(ERR_RESPONSE,
                                    {16'd0, state_read_rsp_tag,
                                     context_tag_q});
                            end else begin
                                old_state_tile_q <= state_read_rsp_data;
                                context_tag_q <= context_tag_q + 1'b1;
                                state_q <= ST_RAW_ACQUIRE;
                            end
                        end
                    end

                    ST_RAW_ACQUIRE: begin
                        if (raw_owner_grant) begin
                            if (compute_owner != 4'b0001) begin
                                enter_fault(ERR_PE_PROTOCOL,
                                    {22'd0, compute_owner, state_q});
                            end else begin
                                current_matrix_q <= 1'b0;
                                source_ordinal_q <= 10'd0;
                                state_q <= ST_CLEAR;
                            end
                        end
                    end

                    ST_CLEAR: state_q <= ST_CLEAR_WAIT;

                    ST_CLEAR_WAIT: begin
                        if (hybrid_idle)
                            state_q <= ST_SOURCE_PREP;
                    end

                    ST_SOURCE_PREP: begin
                        if (source_ordinal_q >= current_iteration_count) begin
                            state_q <= ST_MATRIX_DRAIN;
                        end else if (current_sparse) begin
                            state_q <= ST_LIST_REQ;
                        end else begin
                            source_index_q <= source_ordinal_q;
                            state_q <= ST_FEATURE_REQ;
                        end
                    end

                    ST_LIST_REQ: begin
                        if (list_read_req_valid && list_read_req_ready)
                            state_q <= ST_LIST_WAIT;
                    end

                    ST_LIST_WAIT: begin
                        if (list_read_rsp_valid && list_read_rsp_ready) begin
                            if (list_read_rsp_error ||
                                (list_read_rsp_tag != context_tag_q)) begin
                                enter_fault(ERR_RESPONSE,
                                    {7'd0, list_read_rsp_index,
                                     list_read_rsp_tag, context_tag_q});
                            end else if ({1'b0, list_read_rsp_index} >=
                                         (current_matrix_q
                                          ? matrix1_sources_q
                                          : matrix0_sources_q)) begin
                                enter_fault(ERR_LIST_INDEX,
                                    {13'd0, current_matrix_q,
                                     list_read_rsp_index,
                                     source_ordinal_q[8:0]});
                            end else begin
                                source_index_q <=
                                    {1'b0, list_read_rsp_index};
                                context_tag_q <= context_tag_q + 1'b1;
                                state_q <= ST_WEIGHT_REQ;
                            end
                        end
                    end

                    ST_FEATURE_REQ: begin
                        if (feature_req_valid && feature_req_ready)
                            state_q <= ST_FEATURE_WAIT;
                    end

                    ST_FEATURE_WAIT: begin
                        if (feature_rsp_valid && feature_rsp_ready) begin
                            if (feature_rsp_error ||
                                (feature_rsp_tag != feature_tag_q)) begin
                                enter_fault(ERR_FEATURE,
                                    {16'd0, feature_rsp_tag,
                                     feature_tag_q});
                            end else begin
                                feature_value_q <= feature_rsp_value;
                                feature_tag_q <= feature_tag_q + 1'b1;
                                state_q <= ST_WEIGHT_REQ;
                            end
                        end
                    end

                    ST_WEIGHT_REQ: begin
                        if (weight_req_valid && weight_req_ready) begin
                            weight_request_count <=
                                weight_request_count + 1'b1;
                            if (current_sparse)
                                sparse_weight_request_count <=
                                    sparse_weight_request_count + 1'b1;
                            else
                                dense_weight_request_count <=
                                    dense_weight_request_count + 1'b1;
                            state_q <= ST_WEIGHT_WAIT;
                        end
                    end

                    ST_WEIGHT_WAIT: begin
                        if (weight_rsp_valid && weight_rsp_ready) begin
                            if (weight_rsp_error ||
                                (weight_rsp_tag != memory_tag_q)) begin
                                enter_fault(ERR_RESPONSE,
                                    {16'd0, weight_rsp_tag,
                                     memory_tag_q});
                            end else begin
                                weight_word_q <= weight_rsp_data;
                                memory_tag_q <= memory_tag_q + 1'b1;
                                state_q <= ST_MAC;
                            end
                        end
                    end

                    ST_MAC: begin
                        source_ordinal_q <= source_ordinal_q + 1'b1;
                        state_q <= ST_SOURCE_PREP;
                    end

                    ST_MATRIX_DRAIN: begin
                        if (hybrid_idle) begin
                            if (is_projection_q) begin
                                state_q <= ST_LINEAR;
                            end else if (!current_matrix_q) begin
                                matrix0_snapshot_q <= pe_accumulator;
                                current_matrix_q <= 1'b1;
                                source_ordinal_q <= 10'd0;
                                state_q <= ST_CLEAR;
                            end else begin
                                state_q <= ST_RAW_RELEASE;
                            end
                        end
                    end

                    ST_RAW_RELEASE: begin
                        if (compute_idle)
                            state_q <= ST_GATE_ACQUIRE;
                    end

                    ST_GATE_ACQUIRE: begin
                        if (gate_owner_grant) begin
                            if (compute_owner != 4'b0010)
                                enter_fault(ERR_PE_PROTOCOL,
                                    {22'd0, compute_owner, state_q});
                            else
                                state_q <= ST_GATE_TILE;
                        end
                    end

                    ST_GATE_TILE: begin
                        if (gate_tile_valid && gate_tile_ready) begin
                            gate_q <= 1'b0;
                            gate_group_q <= 3'd0;
                            state_q <= ST_GATE_INPUT;
                        end
                    end

                    ST_GATE_INPUT: begin
                        if (gate_rq_valid && gate_rq_ready)
                            state_q <= ST_GATE_REC;
                    end

                    ST_GATE_REC: begin
                        if (gate_rq_valid && gate_rq_ready)
                            state_q <= ST_GATE_BIAS;
                    end

                    ST_GATE_BIAS: begin
                        if (gate_bias_valid && gate_bias_ready) begin
                            if (gate_group_q == 3'd7) begin
                                if (!gate_q) begin
                                    gate_q <= 1'b1;
                                    gate_group_q <= 3'd0;
                                    state_q <= ST_GATE_INPUT;
                                end else begin
                                    state_q <= ST_GATE_COLLECT;
                                end
                            end else begin
                                gate_group_q <= gate_group_q + 1'b1;
                                state_q <= ST_GATE_INPUT;
                            end
                        end
                    end

                    ST_GATE_COLLECT: begin
                        if (gate_collect_complete)
                            state_q <= ST_MEM_START;
                    end

                    ST_MEM_START: begin
                        if (membrane_start_valid && membrane_start_ready)
                            state_q <= ST_MEM_WAIT;
                    end

                    ST_MEM_WAIT: begin
                        if (membrane_done)
                            state_q <= ST_TILE_DRAIN;
                    end

                    ST_LINEAR: begin
                        if (linear_tile_valid && linear_tile_ready)
                            state_q <= ST_TILE_DRAIN;
                    end

                    ST_TILE_DRAIN: begin
                        if (pe_barrier_idle) begin
                            parameter_record_valid_q <= 1'b0;
                            if (row_tile_q + 1'b1 < row_tiles_q) begin
                                row_tile_q <= row_tile_q + 1'b1;
                                state_q <= ST_PARAM_REQ;
                            end else if (is_projection_q) begin
                                if (final_cache_user_q)
                                    state_q <= ST_RELEASE;
                                else
                                    state_q <= ST_DONE;
                            end else begin
                                state_q <= ST_COMMIT_REQ;
                            end
                        end
                    end

                    ST_COMMIT_REQ: begin
                        if (context_commit_valid && context_commit_ready)
                            state_q <= ST_COMMIT_WAIT;
                    end

                    ST_COMMIT_WAIT: begin
                        if (context_commit_done) begin
                            if (!pe_barrier_idle) begin
                                enter_fault(ERR_COMMIT, 32'h00000001);
                            end else if (final_cache_user_q) begin
                                state_q <= ST_RELEASE;
                            end else begin
                                state_q <= ST_DONE;
                            end
                        end
                    end

                    ST_RELEASE: begin
                        if (stage_release_valid && stage_release_ready)
                            state_q <= ST_DONE;
                    end

                    ST_DONE: begin
                        job_done <= 1'b1;
                        state_q <= ST_IDLE;
                    end

                    default: enter_fault(ERR_PE_PROTOCOL,
                                         {24'd0, state_q, 2'd0});
                endcase
            end
        end
    end
endmodule
