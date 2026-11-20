`timescale 1ns/1ps
`include "memory/model_memory_v5_map.vh"

module tb_sequential_pe_job_controller_v5;
    reg clk;
    reg rst_n;
    reg abort;
    reg job_valid;
    wire job_ready;
    reg [3:0] job_stage_id;
    reg [1:0] job_branch;
    reg [1:0] job_context;
    wire job_done;
    wire job_error;
    wire busy;

    reg stage_ready_for_compute;
    reg lut_ready;
    reg [3:0] active_stage_id;
    reg active_stage_kind;
    reg [1:0] active_matrix_count;
    reg [9:0] active_matrix0_sources;
    reg [5:0] active_matrix0_row_tiles;
    reg [9:0] active_matrix1_sources;
    reg [5:0] active_matrix1_row_tiles;
    reg [5:0] active_param_tiles;
    reg active_uses_sigmoid_table;
    reg [2:0] active_sigmoid_table_select;
    reg memory_error_valid;
    wire stage_release_valid;
    reg stage_release_ready;
    wire [3:0] stage_release_id;

    wire weight_req_valid;
    reg weight_req_ready;
    wire weight_req_matrix;
    wire [9:0] weight_req_source;
    wire [5:0] weight_req_row_tile;
    wire [7:0] weight_req_tag;
    reg weight_rsp_valid;
    wire weight_rsp_ready;
    reg [255:0] weight_rsp_data;
    reg [7:0] weight_rsp_tag;
    reg weight_rsp_error;

    wire param_req_valid;
    reg param_req_ready;
    wire [5:0] param_req_row_tile;
    wire [7:0] param_req_tag;
    reg param_rsp_valid;
    wire param_rsp_ready;
    reg [11583:0] param_rsp_data;
    reg param_rsp_kind;
    reg [13:0] param_rsp_bits;
    reg [7:0] param_rsp_tag;
    reg param_rsp_error;

    wire feature_req_valid;
    reg feature_req_ready;
    wire [3:0] feature_req_stage_id;
    wire [1:0] feature_req_branch;
    wire [1:0] feature_req_context;
    wire [9:0] feature_req_source;
    wire [7:0] feature_req_tag;
    reg feature_rsp_valid;
    wire feature_rsp_ready;
    reg signed [7:0] feature_rsp_value;
    reg [7:0] feature_rsp_tag;
    reg feature_rsp_error;

    wire producer_open_valid;
    reg producer_open_ready;
    wire [4:0] producer_open_logical_id;
    wire [5:0] producer_open_row_tiles;
    wire list_desc_req_valid;
    reg list_desc_req_ready;
    wire [4:0] list_desc_req_logical_id;
    wire [7:0] list_desc_req_tag;
    reg list_desc_rsp_valid;
    wire list_desc_rsp_ready;
    reg [8:0] list_desc_rsp_count;
    reg [7:0] list_desc_rsp_tag;
    reg list_desc_rsp_error;
    wire list_read_req_valid;
    reg list_read_req_ready;
    wire [4:0] list_read_req_logical_id;
    wire [8:0] list_read_req_ordinal;
    wire [7:0] list_read_req_tag;
    reg list_read_rsp_valid;
    wire list_read_rsp_ready;
    reg [8:0] list_read_rsp_index;
    reg [7:0] list_read_rsp_tag;
    reg list_read_rsp_error;
    wire state_read_req_valid;
    reg state_read_req_ready;
    wire [4:0] state_read_req_logical_id;
    wire [4:0] state_read_req_row_tile;
    wire [7:0] state_read_req_tag;
    reg state_read_rsp_valid;
    wire state_read_rsp_ready;
    reg [255:0] state_read_rsp_data;
    reg [7:0] state_read_rsp_tag;
    reg state_read_rsp_error;
    wire context_commit_valid;
    reg context_commit_ready;
    wire [4:0] context_commit_logical_id;
    wire context_commit_pe_barrier_idle;
    reg context_commit_done;
    reg context_error_valid;

    wire raw_owner_request;
    wire raw_owner_grant;
    wire gate_owner_request;
    wire gate_owner_grant;
    wire [3:0] compute_owner;
    wire compute_idle;
    wire [31:0] ctrl_pe_acc_clear;
    wire [31:0] ctrl_pe_acc_enable;
    wire [1:0] ctrl_pe_mode;
    wire [255:0] ctrl_pe_operand_a;
    wire [255:0] ctrl_pe_operand_b;
    wire [255:0] ctrl_pe_gate_u8;
    wire [31:0] ctrl_pe_spike_enable;
    wire [1023:0] ctrl_pe_direct_value;
    reg [1023:0] pe_accumulator;
    reg [31:0] pe_overflow;

    wire gate_tile_valid;
    reg gate_tile_ready;
    wire [31:0] gate_tile_lane_valid;
    wire [511:0] gate_tile_tags;
    wire [2:0] gate_tile_table_select;
    reg gate_collect_complete;
    wire gate_rq_valid;
    reg gate_rq_ready;
    wire [3:0] gate_rq_lane_valid;
    wire [127:0] gate_rq_value;
    wire [127:0] gate_rq_multiplier;
    wire [23:0] gate_rq_shift;
    wire gate_rq_gate;
    wire gate_rq_component;
    wire [2:0] gate_rq_group;
    wire [63:0] gate_rq_tags;
    wire gate_bias_valid;
    reg gate_bias_ready;
    wire gate_bias_gate;
    wire [2:0] gate_bias_group;
    wire [3:0] gate_bias_lane_valid;
    wire [127:0] gate_bias_value;
    wire [63:0] gate_bias_tags;

    reg sigmoid_table_valid;
    wire membrane_start_valid;
    reg membrane_start_ready;
    wire [255:0] membrane_u_prev;
    wire [1023:0] membrane_cx_multiplier;
    wire [191:0] membrane_cx_shift;
    wire [1023:0] membrane_cell_multiplier;
    wire [191:0] membrane_cell_shift;
    wire [8:0] membrane_base_index;
    wire membrane_logical_last;
    reg membrane_done;
    wire linear_tile_valid;
    reg linear_tile_ready;
    wire [31:0] linear_tile_lane_valid;
    wire [8:0] linear_tile_base_index;
    wire [511:0] linear_tile_tags;
    wire linear_tile_logical_last;

    reg rq_param_query_valid;
    reg rq_param_query_op_kind;
    reg [8:0] rq_param_query_index;
    reg [15:0] rq_param_query_tag;
    wire rq_param_valid;
    reg rq_param_ready;
    wire rq_param_op_kind;
    wire signed [31:0] rq_param_multiplier;
    wire [5:0] rq_param_shift;
    wire signed [31:0] rq_param_bias;
    wire [8:0] rq_param_index;
    wire [15:0] rq_param_tag;

    wire hybrid_idle;
    wire local_rq_idle;
    wire postprocess_idle;
    wire sigmoid_idle;
    wire serializer_idle;
    wire shared_rq_idle;
    wire qbn_fork_idle;
    wire [4:0] local_rq_outstanding;
    wire [4:0] postprocess_outstanding;
    wire [4:0] shared_rq_outstanding;
    wire overflow_any;
    reg protocol_error;
    wire pe_barrier_idle;
    wire error_valid;
    wire [7:0] error_code;
    wire [31:0] error_detail;
    wire reset_required;
    wire [5:0] controller_state;
    wire [5:0] current_row_tile;
    wire [31:0] weight_request_count;
    wire [31:0] dense_weight_request_count;
    wire [31:0] sparse_weight_request_count;

    integer cycle_count;
    integer checks;
    integer release_count;
    integer feature_count;
    integer weight_sequence_count;
    integer weight_sequence_position;
    integer expected_matrix [0:19999];
    integer expected_source [0:19999];
    integer expected_tile [0:19999];
    integer active_count_model [0:19];
    integer active_index_model [0:19][0:319];
    reg [11583:0] last_parameter_record;
    reg [4:0] open_logical_id;
    reg [5:0] open_row_tiles;
    reg bias_pending;
    reg expected_gate;
    reg expected_component;
    reg [2:0] expected_group;
    reg rq_stream_active;
    reg rq_stream_kind;
    reg [8:0] rq_stream_index;
    reg [8:0] rq_stream_last;
    reg [511:0] rq_stream_tags;
    reg membrane_active;
    reg expect_fatal;
    reg inject_feature_tag_error;
    reg stall_parameter_request;

    sequential_pe_job_controller_v5 #(
        .WAIT_TIMEOUT_CYCLES(2000)
    ) dut (.*);

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task fail;
        input [8*120-1:0] message;
        begin
            $display("FAIL %0s cycle=%0d state=%0d", message,
                     cycle_count, controller_state);
            $fatal(1);
        end
    endtask

    task check;
        input condition;
        input [8*120-1:0] message;
        begin
            checks = checks + 1;
            if (!condition)
                fail(message);
        end
    endtask

    function [4:0] identity;
        input [1:0] branch_id;
        input [1:0] context_id;
        input layer;
        begin
            case (branch_id)
                2'd0: identity = {4'd0, layer};
                2'd1: identity = 5'd2 + context_id*2 + layer;
                2'd2: identity = 5'd10 + context_id*2 + layer;
                default: identity = 5'd16 + context_id*2 + layer;
            endcase
        end
    endfunction

    function is_projection;
        input [3:0] stage_id;
        begin
            is_projection = (stage_id == 2) || (stage_id == 5) ||
                            (stage_id == 8) || (stage_id == 11);
        end
    endfunction

    function is_gsu2;
        input [3:0] stage_id;
        begin
            is_gsu2 = (stage_id == 1) || (stage_id == 4) ||
                      (stage_id == 7) || (stage_id == 10);
        end
    endfunction

    function is_gsu1;
        input [3:0] stage_id;
        begin
            is_gsu1 = (stage_id == 0) || (stage_id == 3) ||
                      (stage_id == 6) || (stage_id == 9);
        end
    endfunction

    function [11583:0] make_parameter_record;
        input [3:0] stage_id;
        input [5:0] tile;
        integer lane;
        reg [11583:0] value;
        begin
            value = 11584'd0;
            for (lane = 0; lane < 32; lane = lane + 1) begin
                if (is_projection(stage_id)) begin
                    value[`MODEL_V5_PROJECTION_PARAM_OUTPUT_MULTIPLIER_LSB +
                          lane*32 +: 32] = 32'd10000 + tile*32 + lane;
                    value[`MODEL_V5_PROJECTION_PARAM_OUTPUT_SHIFT_LSB +
                          lane*6 +: 6] = (lane + tile) & 6'h1f;
                    value[`MODEL_V5_PROJECTION_PARAM_OUTPUT_BIAS_Q_LSB +
                          lane*32 +: 32] = -32'sd5000 + tile*32 + lane;
                end else begin
                    value[`MODEL_V5_GSU_PARAM_FORGET_INPUT_MULTIPLIER_LSB +
                          lane*32 +: 32] = 32'd1000 + tile*32 + lane;
                    value[`MODEL_V5_GSU_PARAM_FORGET_INPUT_SHIFT_LSB +
                          lane*6 +: 6] = (lane + 1) & 6'h1f;
                    value[`MODEL_V5_GSU_PARAM_FORGET_RECURRENT_MULTIPLIER_LSB +
                          lane*32 +: 32] = 32'd2000 + tile*32 + lane;
                    value[`MODEL_V5_GSU_PARAM_FORGET_RECURRENT_SHIFT_LSB +
                          lane*6 +: 6] = (lane + 2) & 6'h1f;
                    value[`MODEL_V5_GSU_PARAM_FORGET_BIAS_Q_LSB +
                          lane*32 +: 32] = -32'sd3000 + tile*32 + lane;
                    value[`MODEL_V5_GSU_PARAM_CELL_INPUT_MULTIPLIER_LSB +
                          lane*32 +: 32] = 32'd4000 + tile*32 + lane;
                    value[`MODEL_V5_GSU_PARAM_CELL_INPUT_SHIFT_LSB +
                          lane*6 +: 6] = (lane + 3) & 6'h1f;
                    value[`MODEL_V5_GSU_PARAM_CELL_RECURRENT_MULTIPLIER_LSB +
                          lane*32 +: 32] = 32'd5000 + tile*32 + lane;
                    value[`MODEL_V5_GSU_PARAM_CELL_RECURRENT_SHIFT_LSB +
                          lane*6 +: 6] = (lane + 4) & 6'h1f;
                    value[`MODEL_V5_GSU_PARAM_CELL_BIAS_Q_LSB +
                          lane*32 +: 32] = -32'sd6000 + tile*32 + lane;
                    value[`MODEL_V5_GSU_PARAM_PREVIOUS_MULTIPLIER_LSB +
                          lane*32 +: 32] = 32'd7000 + tile*32 + lane;
                    value[`MODEL_V5_GSU_PARAM_PREVIOUS_SHIFT_LSB +
                          lane*6 +: 6] = (lane + 5) & 6'h1f;
                    value[`MODEL_V5_GSU_PARAM_CELLGATE_MULTIPLIER_LSB +
                          lane*32 +: 32] = 32'd8000 + tile*32 + lane;
                    value[`MODEL_V5_GSU_PARAM_CELLGATE_SHIFT_LSB +
                          lane*6 +: 6] = (lane + 6) & 6'h1f;
                    value[`MODEL_V5_GSU_PARAM_BN_MULTIPLIER_LSB +
                          lane*32 +: 32] = 32'd9000 + tile*32 + lane;
                    value[`MODEL_V5_GSU_PARAM_BN_SHIFT_LSB +
                          lane*6 +: 6] = (lane + 7) & 6'h1f;
                    value[`MODEL_V5_GSU_PARAM_BN_BIAS_Q_LSB +
                          lane*32 +: 32] = -32'sd10000 + tile*32 + lane;
                end
            end
            make_parameter_record = value;
        end
    endfunction

    task configure_stage;
        input [3:0] stage_id;
        begin
            active_stage_id = stage_id;
            active_stage_kind = is_projection(stage_id);
            active_matrix_count = is_projection(stage_id) ? 1 : 2;
            active_matrix1_sources = 0;
            active_matrix1_row_tiles = 0;
            active_uses_sigmoid_table = !is_projection(stage_id);
            active_sigmoid_table_select = 0;
            case (stage_id)
                0: begin active_matrix0_sources=64; active_matrix0_row_tiles=10;
                         active_matrix1_sources=320; active_matrix1_row_tiles=10;
                         active_sigmoid_table_select=0; end
                1: begin active_matrix0_sources=320; active_matrix0_row_tiles=10;
                         active_matrix1_sources=320; active_matrix1_row_tiles=10;
                         active_sigmoid_table_select=1; end
                2: begin active_matrix0_sources=320; active_matrix0_row_tiles=2; end
                3: begin active_matrix0_sources=46; active_matrix0_row_tiles=7;
                         active_matrix1_sources=224; active_matrix1_row_tiles=7;
                         active_sigmoid_table_select=2; end
                4: begin active_matrix0_sources=224; active_matrix0_row_tiles=7;
                         active_matrix1_sources=224; active_matrix1_row_tiles=7;
                         active_sigmoid_table_select=3; end
                5: begin active_matrix0_sources=224; active_matrix0_row_tiles=3; end
                6: begin active_matrix0_sources=94; active_matrix0_row_tiles=7;
                         active_matrix1_sources=224; active_matrix1_row_tiles=7;
                         active_sigmoid_table_select=4; end
                7: begin active_matrix0_sources=224; active_matrix0_row_tiles=7;
                         active_matrix1_sources=224; active_matrix1_row_tiles=7;
                         active_sigmoid_table_select=5; end
                8: begin active_matrix0_sources=224; active_matrix0_row_tiles=6; end
                9: begin active_matrix0_sources=158; active_matrix0_row_tiles=7;
                         active_matrix1_sources=224; active_matrix1_row_tiles=7;
                         active_sigmoid_table_select=6; end
                10: begin active_matrix0_sources=224; active_matrix0_row_tiles=7;
                          active_matrix1_sources=224; active_matrix1_row_tiles=7;
                          active_sigmoid_table_select=7; end
                default: begin active_matrix0_sources=224;
                               active_matrix0_row_tiles=4; end
            endcase
            active_param_tiles = active_matrix0_row_tiles;
        end
    endtask

    task append_expected;
        input integer matrix_id;
        input integer source_id;
        input integer tile_id;
        begin
            expected_matrix[weight_sequence_count] = matrix_id;
            expected_source[weight_sequence_count] = source_id;
            expected_tile[weight_sequence_count] = tile_id;
            weight_sequence_count = weight_sequence_count + 1;
        end
    endtask

    task prepare_expected_sequence;
        input [3:0] stage_id;
        input [1:0] branch_id;
        input [1:0] context_id;
        integer tile;
        integer source;
        integer ordinal;
        integer list0;
        integer list1;
        begin
            weight_sequence_count = 0;
            weight_sequence_position = 0;
            feature_count = 0;
            list0 = identity(branch_id, context_id,
                             is_projection(stage_id) ? 1 : 0);
            list1 = identity(branch_id, context_id, is_gsu2(stage_id));
            for (tile = 0; tile < active_matrix0_row_tiles;
                 tile = tile + 1) begin
                if (is_gsu1(stage_id)) begin
                    for (source = 0; source < active_matrix0_sources;
                         source = source + 1)
                        append_expected(0, source, tile);
                end else begin
                    for (ordinal = 0; ordinal < active_count_model[list0];
                         ordinal = ordinal + 1)
                        append_expected(0,
                            active_index_model[list0][ordinal], tile);
                end
                if (!is_projection(stage_id)) begin
                    for (ordinal = 0; ordinal < active_count_model[list1];
                         ordinal = ordinal + 1)
                        append_expected(1,
                            active_index_model[list1][ordinal], tile);
                end
            end
        end
    endtask

    task run_job;
        input [3:0] stage_id;
        input [1:0] branch_id;
        input [1:0] context_id;
        input expect_release;
        integer release_before;
        begin
            configure_stage(stage_id);
            prepare_expected_sequence(stage_id, branch_id, context_id);
            release_before = release_count;
            while (!job_ready) @(posedge clk);
            @(negedge clk);
            job_stage_id = stage_id;
            job_branch = branch_id;
            job_context = context_id;
            job_valid = 1'b1;
            @(posedge clk);
            while (!job_ready) @(posedge clk);
            @(negedge clk);
            job_valid = 1'b0;
            while (!job_done && !job_error) @(posedge clk);
            check(!job_error, "job entered error");
            check(weight_sequence_position == weight_sequence_count,
                  "weight sequence length mismatch");
            check(weight_request_count == weight_sequence_count,
                  "controller weight count mismatch");
            check(feature_count ==
                  (is_gsu1(stage_id)
                   ? active_matrix0_sources*active_matrix0_row_tiles : 0),
                  "dense feature request count mismatch");
            check(release_count == release_before + expect_release,
                  "stage release policy mismatch");
            @(posedge clk);
        end
    endtask

    task launch_job;
        input [3:0] stage_id;
        input [1:0] branch_id;
        input [1:0] context_id;
        begin
            configure_stage(stage_id);
            prepare_expected_sequence(stage_id, branch_id, context_id);
            while (!job_ready) @(posedge clk);
            @(negedge clk);
            job_stage_id = stage_id;
            job_branch = branch_id;
            job_context = context_id;
            job_valid = 1'b1;
            @(posedge clk);
            while (!job_ready) @(posedge clk);
            @(negedge clk);
            job_valid = 1'b0;
        end
    endtask

    task reset_controller;
        begin
            @(negedge clk);
            rst_n = 0;
            job_valid = 0;
            protocol_error = 0;
            pe_overflow = 0;
            abort = 0;
            memory_error_valid = 0;
            context_error_valid = 0;
            inject_feature_tag_error = 0;
            stall_parameter_request = 0;
            repeat (4) @(posedge clk);
            @(negedge clk);
            rst_n = 1;
            repeat (3) @(posedge clk);
        end
    endtask

    assign raw_owner_grant = raw_owner_request;
    assign gate_owner_grant = gate_owner_request;
    assign compute_owner = raw_owner_request ? 4'b0001 :
                           gate_owner_request ? 4'b0010 :
                           membrane_active ? 4'b0100 : 4'b0000;
    assign compute_idle = (compute_owner == 4'b0000);
    assign hybrid_idle = 1'b1;
    assign local_rq_idle = !bias_pending;
    assign postprocess_idle = !bias_pending;
    assign sigmoid_idle = 1'b1;
    assign serializer_idle = !rq_stream_active;
    assign shared_rq_idle = !rq_stream_active;
    assign qbn_fork_idle = !rq_stream_active;
    assign local_rq_outstanding = 0;
    assign postprocess_outstanding = 0;
    assign shared_rq_outstanding = 0;
    assign overflow_any = |pe_overflow;

    integer lane;
    integer base;
    reg signed [7:0] operand_a_lane;
    reg signed [7:0] operand_b_lane;
    always @(posedge clk) begin
        if (!rst_n) begin
            pe_accumulator <= 0;
        end else begin
            for (lane = 0; lane < 32; lane = lane + 1) begin
                if (ctrl_pe_acc_clear[lane]) begin
                    pe_accumulator[lane*32 +: 32] <= 0;
                end else if (ctrl_pe_acc_enable[lane]) begin
                    operand_a_lane = ctrl_pe_operand_a[lane*8 +: 8];
                    operand_b_lane = ctrl_pe_operand_b[lane*8 +: 8];
                    if (ctrl_pe_mode == 0)
                        pe_accumulator[lane*32 +: 32] <=
                            $signed(pe_accumulator[lane*32 +: 32]) +
                            operand_a_lane * operand_b_lane;
                    else if ((ctrl_pe_mode == 1) &&
                             ctrl_pe_spike_enable[lane])
                        pe_accumulator[lane*32 +: 32] <=
                            $signed(pe_accumulator[lane*32 +: 32]) +
                            operand_b_lane;
                end
            end
        end
    end

    // Deterministic independent backpressure on every producer.
    always @* begin
        stage_release_ready = (cycle_count % 5) != 0;
        weight_req_ready = (cycle_count % 7) != 1;
        param_req_ready = !stall_parameter_request &&
                          ((cycle_count % 5) != 2);
        feature_req_ready = (cycle_count % 4) != 1;
        producer_open_ready = (cycle_count % 6) != 2;
        list_desc_req_ready = (cycle_count % 5) != 3;
        list_read_req_ready = (cycle_count % 6) != 4;
        state_read_req_ready = (cycle_count % 5) != 1;
        context_commit_ready = (cycle_count % 7) != 3;
        gate_tile_ready = (cycle_count % 5) != 2;
        gate_rq_ready = (cycle_count % 4) != 0;
        gate_bias_ready = bias_pending && ((cycle_count % 5) != 1);
        membrane_start_ready = (cycle_count % 6) != 1;
        linear_tile_ready = (cycle_count % 5) != 3;
        rq_param_ready = (cycle_count % 4) != 2;
    end

    // Memory and context-store response models.  Each response is held until
    // the controller accepts it.
    always @(posedge clk) begin
        if (!rst_n) begin
            weight_rsp_valid <= 0;
            param_rsp_valid <= 0;
            feature_rsp_valid <= 0;
            list_desc_rsp_valid <= 0;
            list_read_rsp_valid <= 0;
            state_read_rsp_valid <= 0;
            context_commit_done <= 0;
            release_count <= 0;
            feature_count <= 0;
            open_logical_id <= 0;
            open_row_tiles <= 0;
        end else begin
            context_commit_done <= 0;
            if (weight_rsp_valid && weight_rsp_ready)
                weight_rsp_valid <= 0;
            if (param_rsp_valid && param_rsp_ready)
                param_rsp_valid <= 0;
            if (feature_rsp_valid && feature_rsp_ready)
                feature_rsp_valid <= 0;
            if (list_desc_rsp_valid && list_desc_rsp_ready)
                list_desc_rsp_valid <= 0;
            if (list_read_rsp_valid && list_read_rsp_ready)
                list_read_rsp_valid <= 0;
            if (state_read_rsp_valid && state_read_rsp_ready)
                state_read_rsp_valid <= 0;

            if (stage_release_valid && stage_release_ready) begin
                check(stage_release_id == active_stage_id,
                      "release stage mismatch");
                release_count <= release_count + 1;
            end
            if (producer_open_valid && producer_open_ready) begin
                open_logical_id <= producer_open_logical_id;
                open_row_tiles <= producer_open_row_tiles;
            end
            if (context_commit_valid && context_commit_ready) begin
                check(context_commit_logical_id == open_logical_id,
                      "context commit identity mismatch");
                check(context_commit_pe_barrier_idle,
                      "context commit without full PE barrier");
                context_commit_done <= 1;
            end

            if (weight_req_valid && weight_req_ready) begin
                check(weight_sequence_position < weight_sequence_count,
                      "unexpected weight request");
                check(weight_req_matrix ==
                      expected_matrix[weight_sequence_position],
                      "weight matrix order mismatch");
                check(weight_req_source ==
                      expected_source[weight_sequence_position],
                      "weight source order mismatch");
                check(weight_req_row_tile ==
                      expected_tile[weight_sequence_position],
                      "weight tile order mismatch");
                weight_sequence_position = weight_sequence_position + 1;
                weight_rsp_data <= {32{
                    weight_req_source[7:0] +
                    {2'b00, weight_req_row_tile} + 1'b1}};
                weight_rsp_tag <= weight_req_tag;
                weight_rsp_valid <= 1;
            end
            if (param_req_valid && param_req_ready) begin
                param_rsp_data <= make_parameter_record(
                    active_stage_id, param_req_row_tile);
                last_parameter_record <= make_parameter_record(
                    active_stage_id, param_req_row_tile);
                param_rsp_kind <= active_stage_kind;
                param_rsp_bits <= active_stage_kind ? 2240 : 11584;
                param_rsp_tag <= param_req_tag;
                param_rsp_valid <= 1;
            end
            if (feature_req_valid && feature_req_ready) begin
                check(is_gsu1(active_stage_id),
                      "feature requested outside GSU1");
                check(feature_req_stage_id == active_stage_id,
                      "feature stage mismatch");
                feature_count = feature_count + 1;
                feature_rsp_value <= feature_req_source[7:0] + 1'b1;
                feature_rsp_tag <= inject_feature_tag_error
                    ? feature_req_tag + 1'b1 : feature_req_tag;
                feature_rsp_valid <= 1;
            end
            if (list_desc_req_valid && list_desc_req_ready) begin
                list_desc_rsp_count <=
                    active_count_model[list_desc_req_logical_id];
                list_desc_rsp_tag <= list_desc_req_tag;
                list_desc_rsp_valid <= 1;
            end
            if (list_read_req_valid && list_read_req_ready) begin
                check(list_read_req_ordinal <
                      active_count_model[list_read_req_logical_id],
                      "list ordinal out of model range");
                list_read_rsp_index <= active_index_model[
                    list_read_req_logical_id][list_read_req_ordinal];
                list_read_rsp_tag <= list_read_req_tag;
                list_read_rsp_valid <= 1;
            end
            if (state_read_req_valid && state_read_req_ready) begin
                check(state_read_req_logical_id == open_logical_id,
                      "old state identity mismatch");
                check(state_read_req_row_tile < open_row_tiles,
                      "old state tile out of range");
                state_read_rsp_data <= {32{
                    state_read_req_logical_id +
                    state_read_req_row_tile + 1'b1}};
                state_read_rsp_tag <= state_read_req_tag;
                state_read_rsp_valid <= 1;
            end
        end
    end

    // Gate protocol checker and conservative behavioral completion.
    always @(posedge clk) begin
        if (!rst_n) begin
            bias_pending <= 0;
            gate_collect_complete <= 0;
            expected_gate <= 0;
            expected_component <= 0;
            expected_group <= 0;
        end else begin
            if (gate_tile_valid && gate_tile_ready) begin
                check(gate_tile_lane_valid == 32'hffff_ffff,
                      "gate lane mask mismatch");
                expected_gate <= 0;
                expected_component <= 0;
                expected_group <= 0;
                gate_collect_complete <= 0;
            end
            if (gate_rq_valid && gate_rq_ready) begin
                check(gate_rq_gate == expected_gate,
                      "gate order mismatch");
                check(gate_rq_component == expected_component,
                      "INPUT/RECURRENT order mismatch");
                check(gate_rq_group == expected_group,
                      "gate group order mismatch");
                check(gate_rq_lane_valid == 4'hf,
                      "gate group lane mask mismatch");
                if (!gate_rq_component)
                    check(gate_rq_value == dut.matrix0_snapshot_q[
                          gate_rq_group*128 +: 128],
                          "INPUT did not use matrix-0 snapshot");
                else begin
                    check(gate_rq_value == pe_accumulator[
                          gate_rq_group*128 +: 128],
                          "RECURRENT did not use live matrix-1 accumulator");
                    bias_pending <= 1;
                end
                if (!expected_component)
                    expected_component <= 1;
            end
            if (gate_bias_valid && gate_bias_ready) begin
                check(bias_pending, "gate bias without recurrent response");
                check(gate_bias_gate == expected_gate,
                      "gate bias gate mismatch");
                check(gate_bias_group == expected_group,
                      "gate bias group mismatch");
                bias_pending <= 0;
                expected_component <= 0;
                if (expected_group == 7) begin
                    expected_group <= 0;
                    if (!expected_gate)
                        expected_gate <= 1;
                    else
                        gate_collect_complete <= 1;
                end else begin
                    expected_group <= expected_group + 1'b1;
                end
            end
            if (membrane_start_valid && membrane_start_ready)
                gate_collect_complete <= 0;
        end
    end

    // Serializer/Shared-RQ behavior for one complete 32-lane tile.
    always @(posedge clk) begin
        membrane_done <= 0;
        if (!rst_n) begin
            rq_stream_active <= 0;
            rq_param_query_valid <= 0;
            rq_param_query_op_kind <= 0;
            rq_param_query_index <= 0;
            rq_param_query_tag <= 0;
            membrane_active <= 0;
        end else begin
            if (membrane_start_valid && membrane_start_ready) begin
                check(membrane_cx_multiplier == last_parameter_record[
                      `MODEL_V5_GSU_PARAM_PREVIOUS_MULTIPLIER_LSB +: 1024],
                      "membrane previous multiplier mismatch");
                check(membrane_cell_multiplier == last_parameter_record[
                      `MODEL_V5_GSU_PARAM_CELLGATE_MULTIPLIER_LSB +: 1024],
                      "membrane cell multiplier mismatch");
                rq_stream_active <= 1;
                rq_param_query_valid <= 1;
                rq_stream_kind <= 0;
                rq_stream_index <= membrane_base_index;
                rq_stream_last <= membrane_base_index + 31;
                rq_stream_tags <= gate_tile_tags;
                rq_param_query_op_kind <= 0;
                rq_param_query_index <= membrane_base_index;
                rq_param_query_tag <= gate_tile_tags[15:0];
                membrane_active <= 1;
            end else if (linear_tile_valid && linear_tile_ready) begin
                rq_stream_active <= 1;
                rq_param_query_valid <= 1;
                rq_stream_kind <= 1;
                rq_stream_index <= linear_tile_base_index;
                rq_stream_last <= linear_tile_base_index + 31;
                rq_stream_tags <= linear_tile_tags;
                rq_param_query_op_kind <= 1;
                rq_param_query_index <= linear_tile_base_index;
                rq_param_query_tag <= linear_tile_tags[15:0];
            end else if (rq_param_valid && rq_param_ready) begin
                check(rq_param_op_kind == rq_stream_kind,
                      "Shared-RQ op kind mismatch");
                check(rq_param_index == rq_stream_index,
                      "Shared-RQ index mismatch");
                check(rq_param_tag == rq_param_query_tag,
                      "Shared-RQ tag mismatch");
                if (rq_stream_kind) begin
                    check(rq_param_multiplier == last_parameter_record[
                          `MODEL_V5_PROJECTION_PARAM_OUTPUT_MULTIPLIER_LSB +
                          rq_stream_index[4:0]*32 +: 32],
                          "Linear multiplier mismatch");
                    check(rq_param_bias == last_parameter_record[
                          `MODEL_V5_PROJECTION_PARAM_OUTPUT_BIAS_Q_LSB +
                          rq_stream_index[4:0]*32 +: 32],
                          "Linear bias mismatch");
                end else begin
                    check(rq_param_multiplier == last_parameter_record[
                          `MODEL_V5_GSU_PARAM_BN_MULTIPLIER_LSB +
                          rq_stream_index[4:0]*32 +: 32],
                          "QBN multiplier mismatch");
                    check(rq_param_bias == last_parameter_record[
                          `MODEL_V5_GSU_PARAM_BN_BIAS_Q_LSB +
                          rq_stream_index[4:0]*32 +: 32],
                          "QBN bias mismatch");
                end
                if (rq_stream_index == rq_stream_last) begin
                    rq_stream_active <= 0;
                    rq_param_query_valid <= 0;
                    if (!rq_stream_kind) begin
                        membrane_active <= 0;
                        membrane_done <= 1;
                    end
                end else begin
                    rq_stream_index <= rq_stream_index + 1'b1;
                    rq_param_query_index <= rq_stream_index + 1'b1;
                    rq_param_query_tag <= rq_stream_tags[
                        (rq_stream_index[4:0]+1'b1)*16 +: 16];
                end
            end
        end
    end

    always @(posedge clk) begin
        cycle_count = cycle_count + 1;
        if (cycle_count > 1000000)
            fail("testbench watchdog expired");
        if (rst_n) begin
            check(!(raw_owner_request && gate_owner_request),
                  "simultaneous owner requests");
            if (error_valid && !expect_fatal)
                fail("unexpected controller fatal");
        end
    end

    integer id;
    integer ordinal;
    initial begin
        cycle_count = 0;
        checks = 0;
        rst_n = 0;
        abort = 0;
        job_valid = 0;
        job_stage_id = 0;
        job_branch = 0;
        job_context = 0;
        stage_ready_for_compute = 1;
        lut_ready = 1;
        sigmoid_table_valid = 1;
        memory_error_valid = 0;
        context_error_valid = 0;
        protocol_error = 0;
        pe_overflow = 0;
        weight_rsp_valid = 0;
        weight_rsp_data = 0;
        weight_rsp_tag = 0;
        weight_rsp_error = 0;
        param_rsp_valid = 0;
        param_rsp_data = 0;
        param_rsp_kind = 0;
        param_rsp_bits = 0;
        param_rsp_tag = 0;
        param_rsp_error = 0;
        feature_rsp_valid = 0;
        feature_rsp_value = 0;
        feature_rsp_tag = 0;
        feature_rsp_error = 0;
        list_desc_rsp_valid = 0;
        list_desc_rsp_count = 0;
        list_desc_rsp_tag = 0;
        list_desc_rsp_error = 0;
        list_read_rsp_valid = 0;
        list_read_rsp_index = 0;
        list_read_rsp_tag = 0;
        list_read_rsp_error = 0;
        state_read_rsp_valid = 0;
        state_read_rsp_data = 0;
        state_read_rsp_tag = 0;
        state_read_rsp_error = 0;
        context_commit_done = 0;
        last_parameter_record = 0;
        release_count = 0;
        feature_count = 0;
        bias_pending = 0;
        gate_collect_complete = 0;
        rq_stream_active = 0;
        rq_param_query_valid = 0;
        membrane_active = 0;
        membrane_done = 0;
        expect_fatal = 0;
        inject_feature_tag_error = 0;
        stall_parameter_request = 0;
        configure_stage(0);

        for (id = 0; id < 20; id = id + 1) begin
            active_count_model[id] = id % 5;
            for (ordinal = 0; ordinal < 320; ordinal = ordinal + 1)
                active_index_model[id][ordinal] = ordinal*3 + (id % 3);
        end

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (3) @(posedge clk);

        // All true stage geometries, using each branch's final context so the
        // cache is released exactly once after each stage.
        run_job(0, 0, 0, 1);
        run_job(1, 0, 0, 1);
        run_job(2, 0, 0, 1);
        run_job(3, 1, 3, 1);
        run_job(4, 1, 3, 1);
        run_job(5, 1, 3, 1);
        run_job(6, 2, 2, 1);
        run_job(7, 2, 2, 1);
        run_job(8, 2, 2, 1);
        run_job(9, 3, 1, 1);
        run_job(10, 3, 1, 1);
        run_job(11, 3, 1, 1);

        // A non-final SB context must retain the stage; the final context then
        // performs the sole release.
        run_job(3, 1, 0, 0);
        run_job(3, 1, 3, 1);

        check(!reset_required, "reset_required unexpectedly asserted");

        // Reset-only fatal policy and first-cause diagnostics.
        expect_fatal = 1;
        configure_stage(0);
        launch_job(0, 1, 0);
        while (!error_valid) @(posedge clk);
        check(error_code == 8'h01, "malformed job error code mismatch");
        check(reset_required, "malformed job did not require reset");
        reset_controller();

        inject_feature_tag_error = 1;
        launch_job(0, 0, 0);
        while (!error_valid) @(posedge clk);
        check(error_code == 8'h05, "feature response error code mismatch");
        reset_controller();

        launch_job(2, 0, 0);
        while (!busy) @(posedge clk);
        @(negedge clk);
        protocol_error = 1;
        @(posedge clk);
        #1;
        check(error_code == 8'h06, "PE protocol error code mismatch");
        reset_controller();

        launch_job(2, 0, 0);
        while (!busy) @(posedge clk);
        @(negedge clk);
        pe_overflow = 32'h0000_0001;
        @(posedge clk);
        #1;
        check(error_code == 8'h07, "PE overflow error code mismatch");
        reset_controller();

        launch_job(2, 0, 0);
        while (!busy) @(posedge clk);
        @(negedge clk);
        abort = 1;
        @(posedge clk);
        #1;
        check(error_code == 8'h0d, "abort error code mismatch");
        reset_controller();

        stall_parameter_request = 1;
        launch_job(2, 0, 0);
        while (!error_valid) @(posedge clk);
        check(error_code == 8'h0c, "timeout error code mismatch");
        check(reset_required, "timeout did not require reset");
        reset_controller();
        expect_fatal = 0;

        $display("PASS tb_sequential_pe_job_controller_v5 checks=%0d cycles=%0d",
                 checks, cycle_count);
        $finish;
    end
endmodule
