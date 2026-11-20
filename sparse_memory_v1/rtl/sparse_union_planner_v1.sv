`timescale 1ns/1ps

// Matrix-wise active-list union planner for sequential-v4 sparse stage loads.
// The planner owns one context descriptor/read port while active and publishes
// only a complete, immutable plan.
module sparse_union_planner_v1 (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         plan_req_valid,
    output wire         plan_req_ready,
    input  wire [3:0]   plan_req_stage_id,
    input  wire         plan_req_sparse_enable,

    input  wire         controller_idle,
    input  wire         producer_busy,
    input  wire         context_commit_valid,
    input  wire         clear_state,
    input  wire         context_error_valid,

    output wire         list_desc_req_valid,
    input  wire         list_desc_req_ready,
    output wire [4:0]   list_desc_req_logical_id,
    output wire [7:0]   list_desc_req_tag,
    input  wire         list_desc_rsp_valid,
    output wire         list_desc_rsp_ready,
    input  wire         list_desc_rsp_present,
    input  wire [8:0]   list_desc_rsp_count,
    input  wire [7:0]   list_desc_rsp_tag,
    input  wire         list_desc_rsp_error,

    output wire         list_read_req_valid,
    input  wire         list_read_req_ready,
    output wire [4:0]   list_read_req_logical_id,
    output wire [8:0]   list_read_req_ordinal,
    output wire [7:0]   list_read_req_tag,
    input  wire         list_read_rsp_valid,
    output wire         list_read_rsp_ready,
    input  wire [8:0]   list_read_rsp_index,
    input  wire [7:0]   list_read_rsp_tag,
    input  wire         list_read_rsp_error,

    output wire         plan_valid,
    input  wire         plan_ready,
    output reg  [3:0]   plan_stage_id,
    output reg          plan_sparse_enable,
    output reg          plan_fallback_full,
    output reg  [1:0]   plan_matrix_count,
    output reg  [319:0] plan_bitmap0,
    output reg  [319:0] plan_bitmap1,
    output reg  [8:0]   plan_count0,
    output reg  [8:0]   plan_count1,

    output wire         planner_busy,
    output reg          planner_error_valid,
    output reg  [7:0]   planner_error_code,
    output reg  [31:0]  planner_error_detail,
    output wire         reset_required
);
    localparam [3:0] ST_IDLE        = 4'd0;
    localparam [3:0] ST_SELECT      = 4'd1;
    localparam [3:0] ST_DESC_REQ    = 4'd2;
    localparam [3:0] ST_DESC_WAIT   = 4'd3;
    localparam [3:0] ST_LIST_REQ    = 4'd4;
    localparam [3:0] ST_LIST_WAIT   = 4'd5;
    localparam [3:0] ST_NEXT_LIST   = 4'd6;
    localparam [3:0] ST_FINALIZE    = 4'd7;
    localparam [3:0] ST_HOLD        = 4'd8;
    localparam [3:0] ST_FAULT       = 4'd9;

    localparam [7:0] ERR_NONE        = 8'h00;
    localparam [7:0] ERR_STAGE       = 8'h01;
    localparam [7:0] ERR_OWNERSHIP   = 8'h02;
    localparam [7:0] ERR_DESC        = 8'h03;
    localparam [7:0] ERR_MISSING     = 8'h04;
    localparam [7:0] ERR_LIST        = 8'h05;
    localparam [7:0] ERR_INDEX       = 8'h06;
    localparam [7:0] ERR_ORDER       = 8'h07;
    localparam [7:0] ERR_CONTEXT     = 8'h08;
    localparam [7:0] ERR_UNSOLICITED = 8'h09;

    wire map_stage_valid;
    wire [1:0] map_matrix_count;
    wire [31:0] map_stage_dram_byte_offset;
    wire [31:0] map_stage_transfer_bytes;
    wire map_matrix0_dense;
    wire [9:0] map_matrix0_sources;
    wire [5:0] map_matrix0_row_tiles;
    wire [31:0] map_matrix0_local_byte_offset;
    wire [31:0] map_matrix0_source_stride_bytes;
    wire [2:0] map_matrix0_list_count;
    wire [4:0] map_matrix0_list_base;
    wire map_matrix0_require_present;
    wire map_matrix1_dense;
    wire [9:0] map_matrix1_sources;
    wire [5:0] map_matrix1_row_tiles;
    wire [31:0] map_matrix1_local_byte_offset;
    wire [31:0] map_matrix1_source_stride_bytes;
    wire [2:0] map_matrix1_list_count;
    wire [4:0] map_matrix1_list_base;
    wire map_matrix1_require_present;
    wire [31:0] map_parameter_local_byte_offset;
    wire [31:0] map_parameter_transfer_bytes;

    sparse_stage_map_v1 u_stage_map (
        .stage_id(plan_req_stage_id),
        .stage_valid(map_stage_valid),
        .matrix_count(map_matrix_count),
        .stage_dram_byte_offset(map_stage_dram_byte_offset),
        .stage_transfer_bytes(map_stage_transfer_bytes),
        .matrix0_dense(map_matrix0_dense),
        .matrix0_sources(map_matrix0_sources),
        .matrix0_row_tiles(map_matrix0_row_tiles),
        .matrix0_local_byte_offset(map_matrix0_local_byte_offset),
        .matrix0_source_stride_bytes(map_matrix0_source_stride_bytes),
        .matrix0_list_count(map_matrix0_list_count),
        .matrix0_list_base(map_matrix0_list_base),
        .matrix0_require_present(map_matrix0_require_present),
        .matrix1_dense(map_matrix1_dense),
        .matrix1_sources(map_matrix1_sources),
        .matrix1_row_tiles(map_matrix1_row_tiles),
        .matrix1_local_byte_offset(map_matrix1_local_byte_offset),
        .matrix1_source_stride_bytes(map_matrix1_source_stride_bytes),
        .matrix1_list_count(map_matrix1_list_count),
        .matrix1_list_base(map_matrix1_list_base),
        .matrix1_require_present(map_matrix1_require_present),
        .parameter_local_byte_offset(map_parameter_local_byte_offset),
        .parameter_transfer_bytes(map_parameter_transfer_bytes)
    );

    reg [3:0] state_q;
    reg plan_valid_q;
    reg current_matrix_q;
    reg [2:0] context_ordinal_q;
    reg [8:0] entry_ordinal_q;
    reg [8:0] entry_count_q;
    reg [7:0] request_tag_q;
    reg previous_index_valid_q;
    reg [8:0] previous_index_q;

    reg matrix0_dense_q;
    reg [9:0] matrix0_sources_q;
    reg [2:0] matrix0_list_count_q;
    reg [4:0] matrix0_list_base_q;
    reg matrix0_require_present_q;
    reg matrix1_dense_q;
    reg [9:0] matrix1_sources_q;
    reg [2:0] matrix1_list_count_q;
    reg [4:0] matrix1_list_base_q;
    reg matrix1_require_present_q;

    wire ownership_safe = controller_idle && !producer_busy &&
                          !context_commit_valid && !clear_state;
    wire [2:0] current_list_count = current_matrix_q
        ? matrix1_list_count_q : matrix0_list_count_q;
    wire [4:0] current_list_base = current_matrix_q
        ? matrix1_list_base_q : matrix0_list_base_q;
    wire current_require_present = current_matrix_q
        ? matrix1_require_present_q : matrix0_require_present_q;
    wire [9:0] current_sources = current_matrix_q
        ? matrix1_sources_q : matrix0_sources_q;
    wire current_dense = current_matrix_q
        ? matrix1_dense_q : matrix0_dense_q;
    wire [5:0] current_logical_id_sum =
        {1'b0, current_list_base} + {2'd0, context_ordinal_q, 1'b0};
    wire [4:0] current_logical_id = current_logical_id_sum[4:0];

    wire matrix0_sparse_eligible = !matrix0_dense_q &&
                                   (matrix0_sources_q != 0);
    wire matrix1_sparse_eligible = (plan_matrix_count == 2'd2) &&
                                   !matrix1_dense_q &&
                                   (matrix1_sources_q != 0);
    wire matrix0_union_full = !matrix0_sparse_eligible ||
                              ({1'b0, plan_count0} == matrix0_sources_q);
    wire matrix1_union_full = !matrix1_sparse_eligible ||
                              ({1'b0, plan_count1} == matrix1_sources_q);

    assign plan_req_ready = rst_n && (state_q == ST_IDLE) &&
                            !planner_error_valid && ownership_safe &&
                            !context_error_valid;
    assign list_desc_req_valid = (state_q == ST_DESC_REQ) &&
                                 !planner_error_valid && ownership_safe;
    assign list_desc_req_logical_id = current_logical_id;
    assign list_desc_req_tag = request_tag_q;
    assign list_desc_rsp_ready = (state_q == ST_DESC_WAIT) &&
                                 !planner_error_valid && ownership_safe;
    assign list_read_req_valid = (state_q == ST_LIST_REQ) &&
                                 !planner_error_valid && ownership_safe;
    assign list_read_req_logical_id = current_logical_id;
    assign list_read_req_ordinal = entry_ordinal_q;
    assign list_read_req_tag = request_tag_q;
    assign list_read_rsp_ready = (state_q == ST_LIST_WAIT) &&
                                 !planner_error_valid && ownership_safe;
    // Suppress a result combinationally if ownership or context health is
    // withdrawn in its acceptance cycle.  The sequential fault path then
    // makes the suppression sticky until reset.
    assign plan_valid = plan_valid_q && ownership_safe &&
                        !context_error_valid && !planner_error_valid;
    assign planner_busy = (state_q != ST_IDLE) && (state_q != ST_FAULT);
    assign reset_required = planner_error_valid;

    task automatic enter_fault;
        input [7:0] code;
        input [31:0] detail;
        begin
            if (!planner_error_valid) begin
                planner_error_valid <= 1'b1;
                planner_error_code <= code;
                planner_error_detail <= detail;
            end
            plan_valid_q <= 1'b0;
            state_q <= ST_FAULT;
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            state_q <= ST_IDLE;
            current_matrix_q <= 1'b0;
            context_ordinal_q <= 3'd0;
            entry_ordinal_q <= 9'd0;
            entry_count_q <= 9'd0;
            request_tag_q <= 8'd0;
            previous_index_valid_q <= 1'b0;
            previous_index_q <= 9'd0;
            matrix0_dense_q <= 1'b0;
            matrix0_sources_q <= 10'd0;
            matrix0_list_count_q <= 3'd0;
            matrix0_list_base_q <= 5'd0;
            matrix0_require_present_q <= 1'b0;
            matrix1_dense_q <= 1'b0;
            matrix1_sources_q <= 10'd0;
            matrix1_list_count_q <= 3'd0;
            matrix1_list_base_q <= 5'd0;
            matrix1_require_present_q <= 1'b0;
            plan_valid_q <= 1'b0;
            plan_stage_id <= 4'd0;
            plan_sparse_enable <= 1'b0;
            plan_fallback_full <= 1'b0;
            plan_matrix_count <= 2'd0;
            plan_bitmap0 <= 320'd0;
            plan_bitmap1 <= 320'd0;
            plan_count0 <= 9'd0;
            plan_count1 <= 9'd0;
            planner_error_valid <= 1'b0;
            planner_error_code <= ERR_NONE;
            planner_error_detail <= 32'd0;
        end else if (planner_error_valid) begin
            state_q <= ST_FAULT;
            plan_valid_q <= 1'b0;
        end else if (context_error_valid) begin
            enter_fault(ERR_CONTEXT, {28'd0, state_q});
        end else if ((state_q != ST_IDLE) && !ownership_safe) begin
            enter_fault(ERR_OWNERSHIP,
                        {24'd0, state_q, controller_idle, producer_busy,
                         context_commit_valid, clear_state});
        end else if (list_desc_rsp_valid && (state_q != ST_DESC_WAIT)) begin
            enter_fault(ERR_UNSOLICITED,
                        {9'd0, 1'b0, list_desc_rsp_present,
                         list_desc_rsp_count, list_desc_rsp_tag, state_q});
        end else if (list_read_rsp_valid && (state_q != ST_LIST_WAIT)) begin
            enter_fault(ERR_UNSOLICITED,
                        {10'd0, 1'b1, list_read_rsp_index,
                         list_read_rsp_tag, state_q});
        end else begin
            case (state_q)
                ST_IDLE: begin
                    plan_valid_q <= 1'b0;
                    if (plan_req_valid && plan_req_ready) begin
                        if (!map_stage_valid) begin
                            enter_fault(ERR_STAGE,
                                        {28'd0, plan_req_stage_id});
                        end else begin
                            plan_stage_id <= plan_req_stage_id;
                            plan_sparse_enable <=
                                plan_req_sparse_enable;
                            plan_fallback_full <= 1'b0;
                            plan_matrix_count <= map_matrix_count;
                            plan_bitmap0 <= 320'd0;
                            plan_bitmap1 <= 320'd0;
                            plan_count0 <= 9'd0;
                            plan_count1 <= 9'd0;
                            matrix0_dense_q <= map_matrix0_dense;
                            matrix0_sources_q <= map_matrix0_sources;
                            matrix0_list_count_q <=
                                map_matrix0_list_count;
                            matrix0_list_base_q <= map_matrix0_list_base;
                            matrix0_require_present_q <=
                                map_matrix0_require_present;
                            matrix1_dense_q <= map_matrix1_dense;
                            matrix1_sources_q <= map_matrix1_sources;
                            matrix1_list_count_q <=
                                map_matrix1_list_count;
                            matrix1_list_base_q <= map_matrix1_list_base;
                            matrix1_require_present_q <=
                                map_matrix1_require_present;
                            current_matrix_q <= 1'b0;
                            context_ordinal_q <= 3'd0;
                            entry_ordinal_q <= 9'd0;
                            entry_count_q <= 9'd0;
                            previous_index_valid_q <= 1'b0;
                            state_q <= ST_SELECT;
                        end
                    end
                end

                ST_SELECT: begin
                    context_ordinal_q <= 3'd0;
                    previous_index_valid_q <= 1'b0;
                    if (!current_matrix_q) begin
                        if (current_dense || (current_sources == 0) ||
                            (current_list_count == 0)) begin
                            current_matrix_q <= 1'b1;
                        end else begin
                            state_q <= ST_DESC_REQ;
                        end
                    end else if ((plan_matrix_count != 2'd2) ||
                                 current_dense ||
                                 (current_sources == 0) ||
                                 (current_list_count == 0)) begin
                        state_q <= ST_FINALIZE;
                    end else begin
                        state_q <= ST_DESC_REQ;
                    end
                end

                ST_DESC_REQ: begin
                    if (current_logical_id_sum >= 6'd20) begin
                        enter_fault(ERR_DESC,
                                    {14'd0, current_matrix_q,
                                     current_logical_id_sum,
                                     context_ordinal_q, request_tag_q});
                    end else if (list_desc_req_valid &&
                                 list_desc_req_ready) begin
                        state_q <= ST_DESC_WAIT;
                    end
                end

                ST_DESC_WAIT: begin
                    if (list_desc_rsp_valid && list_desc_rsp_ready) begin
                        if (list_desc_rsp_error ||
                            (list_desc_rsp_tag != request_tag_q) ||
                            (!list_desc_rsp_present &&
                             (list_desc_rsp_count != 0)) ||
                            ({1'b0, list_desc_rsp_count} >
                             current_sources)) begin
                            enter_fault(ERR_DESC,
                                {2'd0, current_matrix_q,
                                 list_desc_rsp_present,
                                 list_desc_rsp_count,
                                 list_desc_rsp_tag, request_tag_q,
                                 context_ordinal_q});
                        end else if (!list_desc_rsp_present &&
                                     current_require_present) begin
                            enter_fault(ERR_MISSING,
                                {15'd0, current_matrix_q,
                                 current_logical_id,
                                 context_ordinal_q, request_tag_q});
                        end else begin
                            request_tag_q <= request_tag_q + 1'b1;
                            entry_count_q <= list_desc_rsp_count;
                            entry_ordinal_q <= 9'd0;
                            previous_index_valid_q <= 1'b0;
                            if (!list_desc_rsp_present ||
                                (list_desc_rsp_count == 0))
                                state_q <= ST_NEXT_LIST;
                            else
                                state_q <= ST_LIST_REQ;
                        end
                    end
                end

                ST_LIST_REQ: begin
                    if (list_read_req_valid && list_read_req_ready)
                        state_q <= ST_LIST_WAIT;
                end

                ST_LIST_WAIT: begin
                    if (list_read_rsp_valid && list_read_rsp_ready) begin
                        if (list_read_rsp_error ||
                            (list_read_rsp_tag != request_tag_q)) begin
                            enter_fault(ERR_LIST,
                                {6'd0, current_matrix_q,
                                 list_read_rsp_index,
                                 list_read_rsp_tag, request_tag_q});
                        end else if ({1'b0, list_read_rsp_index} >=
                                     current_sources) begin
                            enter_fault(ERR_INDEX,
                                {8'd0, current_matrix_q,
                                 current_logical_id,
                                 list_read_rsp_index,
                                 entry_ordinal_q});
                        end else if (previous_index_valid_q &&
                                     (list_read_rsp_index <=
                                      previous_index_q)) begin
                            enter_fault(ERR_ORDER,
                                {5'd0, current_matrix_q,
                                 current_logical_id,
                                 previous_index_q,
                                 list_read_rsp_index, 3'd0});
                        end else begin
                            if (!current_matrix_q) begin
                                if (!plan_bitmap0[list_read_rsp_index]) begin
                                    plan_bitmap0[list_read_rsp_index] <= 1'b1;
                                    plan_count0 <= plan_count0 + 1'b1;
                                end
                            end else begin
                                if (!plan_bitmap1[list_read_rsp_index]) begin
                                    plan_bitmap1[list_read_rsp_index] <= 1'b1;
                                    plan_count1 <= plan_count1 + 1'b1;
                                end
                            end
                            previous_index_valid_q <= 1'b1;
                            previous_index_q <= list_read_rsp_index;
                            request_tag_q <= request_tag_q + 1'b1;
                            if (entry_ordinal_q + 1'b1 >= entry_count_q) begin
                                state_q <= ST_NEXT_LIST;
                            end else begin
                                entry_ordinal_q <= entry_ordinal_q + 1'b1;
                                state_q <= ST_LIST_REQ;
                            end
                        end
                    end
                end

                ST_NEXT_LIST: begin
                    previous_index_valid_q <= 1'b0;
                    entry_ordinal_q <= 9'd0;
                    entry_count_q <= 9'd0;
                    if (context_ordinal_q + 1'b1 <
                        current_list_count) begin
                        context_ordinal_q <= context_ordinal_q + 1'b1;
                        state_q <= ST_DESC_REQ;
                    end else if (!current_matrix_q) begin
                        current_matrix_q <= 1'b1;
                        context_ordinal_q <= 3'd0;
                        state_q <= ST_SELECT;
                    end else begin
                        state_q <= ST_FINALIZE;
                    end
                end

                ST_FINALIZE: begin
                    plan_fallback_full <= !plan_sparse_enable ||
                                          (matrix0_union_full &&
                                           matrix1_union_full);
                    plan_valid_q <= 1'b1;
                    state_q <= ST_HOLD;
                end

                ST_HOLD: begin
                    if (plan_valid && plan_ready) begin
                        plan_valid_q <= 1'b0;
                        state_q <= ST_IDLE;
                    end
                end

                default: begin
                    enter_fault(ERR_UNSOLICITED,
                                {28'd0, state_q});
                end
            endcase
        end
    end
endmodule
