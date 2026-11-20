`timescale 1ns/1ps

module tb_pe_array_datapath;

    `include "pe_array_datapath_vectors.vh"

    localparam integer INDEX_WIDTH = 9;
    localparam integer SIGMOID_BYTES = 8 * 255;

    reg clk;
    reg rst_n;

    reg raw_owner_request;
    wire raw_owner_grant;
    reg gate_owner_request;
    wire gate_owner_grant;
    wire [3:0] compute_owner;
    wire compute_idle;

    reg [15:0] ctrl_pe_acc_clear;
    reg [15:0] ctrl_pe_acc_enable;
    reg [1:0] ctrl_pe_mode;
    reg [127:0] ctrl_pe_operand_a;
    reg [127:0] ctrl_pe_operand_b;
    reg [127:0] ctrl_pe_gate_u8;
    reg [15:0] ctrl_pe_spike_enable;
    reg [511:0] ctrl_pe_direct_value;
    wire [511:0] pe_accumulator;
    wire [15:0] pe_overflow;

    reg gate_tile_valid;
    wire gate_tile_ready;
    reg [15:0] gate_tile_lane_valid;
    reg [255:0] gate_tile_tags;
    reg [2:0] gate_tile_table_select;
    wire gate_collect_complete;

    reg gate_rq_valid;
    wire gate_rq_ready;
    reg [3:0] gate_rq_lane_valid;
    reg [127:0] gate_rq_value;
    reg [127:0] gate_rq_multiplier;
    reg [23:0] gate_rq_shift;
    reg gate_rq_gate;
    reg gate_rq_component;
    reg [1:0] gate_rq_group;
    reg [63:0] gate_rq_tags;

    reg gate_bias_valid;
    wire gate_bias_ready;
    reg gate_bias_gate;
    reg [1:0] gate_bias_group;
    reg [3:0] gate_bias_lane_valid;
    reg [127:0] gate_bias_value;
    reg [63:0] gate_bias_tags;

    reg sigmoid_cfg_start_valid;
    wire sigmoid_cfg_start_ready;
    reg sigmoid_cfg_data_valid;
    wire sigmoid_cfg_data_ready;
    reg [7:0] sigmoid_cfg_data;
    wire sigmoid_cfg_done;
    wire sigmoid_table_valid;

    reg membrane_start_valid;
    wire membrane_start_ready;
    reg [127:0] membrane_u_prev;
    reg [511:0] membrane_cx_multiplier;
    reg [95:0] membrane_cx_shift;
    reg [511:0] membrane_cell_multiplier;
    reg [95:0] membrane_cell_shift;
    reg [INDEX_WIDTH-1:0] membrane_base_index;
    reg membrane_logical_last;
    wire membrane_busy;
    wire membrane_done;
    wire [3:0] membrane_phase;

    reg linear_tile_valid;
    wire linear_tile_ready;
    reg [15:0] linear_tile_lane_valid;
    reg [INDEX_WIDTH-1:0] linear_tile_base_index;
    reg [255:0] linear_tile_tags;
    reg linear_tile_logical_last;

    wire rq_param_query_valid;
    wire rq_param_query_op_kind;
    wire [INDEX_WIDTH-1:0] rq_param_query_index;
    wire [15:0] rq_param_query_tag;
    reg rq_param_valid;
    wire rq_param_ready;
    reg rq_param_op_kind;
    reg signed [31:0] rq_param_multiplier;
    reg [5:0] rq_param_shift;
    reg signed [31:0] rq_param_bias;
    reg [INDEX_WIDTH-1:0] rq_param_index;
    reg [15:0] rq_param_tag;

    wire state_write_valid;
    reg state_write_ready;
    wire signed [7:0] state_write_value;
    wire [INDEX_WIDTH-1:0] state_write_index;
    wire [15:0] state_write_tag;
    wire state_write_last;

    wire active_cmd_valid;
    reg active_cmd_ready;
    wire active_cmd_write;
    wire [INDEX_WIDTH-1:0] active_cmd_index;
    wire [15:0] active_cmd_tag;
    wire active_cmd_finalize;

    wire coefficient_valid;
    reg coefficient_ready;
    wire signed [7:0] coefficient_value;
    wire [INDEX_WIDTH-1:0] coefficient_index;
    wire [15:0] coefficient_tag;
    wire coefficient_last;

    reg cdf_start_valid;
    wire cdf_start_ready;
    reg [2:0] cdf_order;
    reg [7:0] cdf_bin_valid;
    reg [7:0] cdf_bin_base;
    reg [1:0] cdf_band;
    reg [15:0] cdf_tag;
    reg cdf_tap_valid;
    wire cdf_tap_ready;
    reg [2:0] cdf_tap_index;
    reg [63:0] cdf_spectrum_real;
    reg [63:0] cdf_spectrum_imag;
    reg [63:0] cdf_coefficient_real;
    reg [63:0] cdf_coefficient_imag;
    wire cdf_result_valid;
    reg cdf_result_ready;
    wire [255:0] cdf_result_real;
    wire [255:0] cdf_result_imag;
    wire [7:0] cdf_result_bin_valid;
    wire [2:0] cdf_result_order;
    wire [7:0] cdf_result_bin_base;
    wire [1:0] cdf_result_band;
    wire [15:0] cdf_result_tag;
    wire cdf_busy;
    wire cdf_done;
    wire [2:0] cdf_phase;
    wire [2:0] cdf_active_tap_index;

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
    wire protocol_error;

    pe_array_datapath #(
        .INDEX_WIDTH(INDEX_WIDTH),
        .BIN_INDEX_WIDTH(8)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .raw_owner_request(raw_owner_request),
        .raw_owner_grant(raw_owner_grant),
        .gate_owner_request(gate_owner_request),
        .gate_owner_grant(gate_owner_grant),
        .compute_owner(compute_owner),
        .compute_idle(compute_idle),
        .ctrl_pe_acc_clear(ctrl_pe_acc_clear),
        .ctrl_pe_acc_enable(ctrl_pe_acc_enable),
        .ctrl_pe_mode(ctrl_pe_mode),
        .ctrl_pe_operand_a(ctrl_pe_operand_a),
        .ctrl_pe_operand_b(ctrl_pe_operand_b),
        .ctrl_pe_gate_u8(ctrl_pe_gate_u8),
        .ctrl_pe_spike_enable(ctrl_pe_spike_enable),
        .ctrl_pe_direct_value(ctrl_pe_direct_value),
        .pe_accumulator(pe_accumulator),
        .pe_overflow(pe_overflow),
        .gate_tile_valid(gate_tile_valid),
        .gate_tile_ready(gate_tile_ready),
        .gate_tile_lane_valid(gate_tile_lane_valid),
        .gate_tile_tags(gate_tile_tags),
        .gate_tile_table_select(gate_tile_table_select),
        .gate_collect_complete(gate_collect_complete),
        .gate_rq_valid(gate_rq_valid),
        .gate_rq_ready(gate_rq_ready),
        .gate_rq_lane_valid(gate_rq_lane_valid),
        .gate_rq_value(gate_rq_value),
        .gate_rq_multiplier(gate_rq_multiplier),
        .gate_rq_shift(gate_rq_shift),
        .gate_rq_gate(gate_rq_gate),
        .gate_rq_component(gate_rq_component),
        .gate_rq_group(gate_rq_group),
        .gate_rq_tags(gate_rq_tags),
        .gate_bias_valid(gate_bias_valid),
        .gate_bias_ready(gate_bias_ready),
        .gate_bias_gate(gate_bias_gate),
        .gate_bias_group(gate_bias_group),
        .gate_bias_lane_valid(gate_bias_lane_valid),
        .gate_bias_value(gate_bias_value),
        .gate_bias_tags(gate_bias_tags),
        .sigmoid_cfg_start_valid(sigmoid_cfg_start_valid),
        .sigmoid_cfg_start_ready(sigmoid_cfg_start_ready),
        .sigmoid_cfg_data_valid(sigmoid_cfg_data_valid),
        .sigmoid_cfg_data_ready(sigmoid_cfg_data_ready),
        .sigmoid_cfg_data(sigmoid_cfg_data),
        .sigmoid_cfg_done(sigmoid_cfg_done),
        .sigmoid_table_valid(sigmoid_table_valid),
        .membrane_start_valid(membrane_start_valid),
        .membrane_start_ready(membrane_start_ready),
        .membrane_u_prev(membrane_u_prev),
        .membrane_cx_multiplier(membrane_cx_multiplier),
        .membrane_cx_shift(membrane_cx_shift),
        .membrane_cell_multiplier(membrane_cell_multiplier),
        .membrane_cell_shift(membrane_cell_shift),
        .membrane_base_index(membrane_base_index),
        .membrane_logical_last(membrane_logical_last),
        .membrane_busy(membrane_busy),
        .membrane_done(membrane_done),
        .membrane_phase(membrane_phase),
        .linear_tile_valid(linear_tile_valid),
        .linear_tile_ready(linear_tile_ready),
        .linear_tile_lane_valid(linear_tile_lane_valid),
        .linear_tile_base_index(linear_tile_base_index),
        .linear_tile_tags(linear_tile_tags),
        .linear_tile_logical_last(linear_tile_logical_last),
        .rq_param_query_valid(rq_param_query_valid),
        .rq_param_query_op_kind(rq_param_query_op_kind),
        .rq_param_query_index(rq_param_query_index),
        .rq_param_query_tag(rq_param_query_tag),
        .rq_param_valid(rq_param_valid),
        .rq_param_ready(rq_param_ready),
        .rq_param_op_kind(rq_param_op_kind),
        .rq_param_multiplier(rq_param_multiplier),
        .rq_param_shift(rq_param_shift),
        .rq_param_bias(rq_param_bias),
        .rq_param_index(rq_param_index),
        .rq_param_tag(rq_param_tag),
        .state_write_valid(state_write_valid),
        .state_write_ready(state_write_ready),
        .state_write_value(state_write_value),
        .state_write_index(state_write_index),
        .state_write_tag(state_write_tag),
        .state_write_last(state_write_last),
        .active_cmd_valid(active_cmd_valid),
        .active_cmd_ready(active_cmd_ready),
        .active_cmd_write(active_cmd_write),
        .active_cmd_index(active_cmd_index),
        .active_cmd_tag(active_cmd_tag),
        .active_cmd_finalize(active_cmd_finalize),
        .coefficient_valid(coefficient_valid),
        .coefficient_ready(coefficient_ready),
        .coefficient_value(coefficient_value),
        .coefficient_index(coefficient_index),
        .coefficient_tag(coefficient_tag),
        .coefficient_last(coefficient_last),
        .cdf_start_valid(cdf_start_valid),
        .cdf_start_ready(cdf_start_ready),
        .cdf_order(cdf_order),
        .cdf_bin_valid(cdf_bin_valid),
        .cdf_bin_base(cdf_bin_base),
        .cdf_band(cdf_band),
        .cdf_tag(cdf_tag),
        .cdf_tap_valid(cdf_tap_valid),
        .cdf_tap_ready(cdf_tap_ready),
        .cdf_tap_index(cdf_tap_index),
        .cdf_spectrum_real(cdf_spectrum_real),
        .cdf_spectrum_imag(cdf_spectrum_imag),
        .cdf_coefficient_real(cdf_coefficient_real),
        .cdf_coefficient_imag(cdf_coefficient_imag),
        .cdf_result_valid(cdf_result_valid),
        .cdf_result_ready(cdf_result_ready),
        .cdf_result_real(cdf_result_real),
        .cdf_result_imag(cdf_result_imag),
        .cdf_result_bin_valid(cdf_result_bin_valid),
        .cdf_result_order(cdf_result_order),
        .cdf_result_bin_base(cdf_result_bin_base),
        .cdf_result_band(cdf_result_band),
        .cdf_result_tag(cdf_result_tag),
        .cdf_busy(cdf_busy),
        .cdf_done(cdf_done),
        .cdf_phase(cdf_phase),
        .cdf_active_tap_index(cdf_active_tap_index),
        .hybrid_idle(hybrid_idle),
        .local_rq_idle(local_rq_idle),
        .postprocess_idle(postprocess_idle),
        .sigmoid_idle(sigmoid_idle),
        .serializer_idle(serializer_idle),
        .shared_rq_idle(shared_rq_idle),
        .qbn_fork_idle(qbn_fork_idle),
        .local_rq_outstanding(local_rq_outstanding),
        .postprocess_outstanding(postprocess_outstanding),
        .shared_rq_outstanding(shared_rq_outstanding),
        .overflow_any(overflow_any),
        .protocol_error(protocol_error)
    );

    reg [7:0] sigmoid_bytes [0:SIGMOID_BYTES-1];
    reg [2047:0] sigmoid_path;
    reg [7:0] coefficient_real_mem [0:7];
    reg [7:0] coefficient_imag_mem [0:7];
    reg state_seen [0:15];
    reg coefficient_seen [0:15];
    integer expected_state_lanes [0:15];
    integer expected_coefficient_lanes [0:15];
    integer expected_active_lanes [0:15];
    integer expected_state_count;
    integer expected_coefficient_count;
    integer expected_active_count;
    integer state_count;
    integer coefficient_count;
    integer active_count;
    integer parameter_count;
    integer bias_count;
    integer cdf_result_count;
    integer cycle_count;
    integer errors;
    integer lane;
    integer seed_ready;
    integer seed_param;
    integer param_state;
    integer param_delay;
    reg seen_gate_owner;
    reg seen_membrane_owner;
    reg seen_raw_owner;
    reg seen_cdf_owner;
    reg test_passed;

    reg state_stall_q;
    reg signed [7:0] held_state_value;
    reg [INDEX_WIDTH-1:0] held_state_index;
    reg [15:0] held_state_tag;
    reg held_state_last;
    reg active_stall_q;
    reg held_active_write;
    reg [INDEX_WIDTH-1:0] held_active_index;
    reg [15:0] held_active_tag;
    reg held_active_finalize;
    reg coefficient_stall_q;
    reg signed [7:0] held_coefficient_value;
    reg [INDEX_WIDTH-1:0] held_coefficient_index;
    reg [15:0] held_coefficient_tag;
    reg held_coefficient_last;
    reg cdf_stall_q;
    reg [255:0] held_cdf_real;
    reg [255:0] held_cdf_imag;
    reg [7:0] held_cdf_mask;
    reg [15:0] held_cdf_tag;

    always #2.5 clk = ~clk;

    function automatic integer highest_lane16(input [15:0] mask);
        integer index;
        begin
            highest_lane16 = 0;
            for (index = 0; index < 16; index = index + 1)
                if (mask[index])
                    highest_lane16 = index;
        end
    endfunction

    task automatic fail(input [1023:0] message);
        begin
            $display("ERROR cycle=%0d %0s", cycle_count, message);
            errors = errors + 1;
        end
    endtask

    task automatic set_parameter_response;
        input op_kind;
        input [INDEX_WIDTH-1:0] index_value;
        input [15:0] tag_value;
        integer selected_lane;
        begin
            selected_lane = tag_value[3:0];
            rq_param_op_kind = op_kind;
            rq_param_index = index_value;
            rq_param_tag = tag_value;
            if (!op_kind && tag_value[15:4] == 12'h110) begin
                rq_param_multiplier = SC_QBN_MULTIPLIER[
                    selected_lane*32 +: 32];
                rq_param_shift = SC_QBN_SHIFT[selected_lane*6 +: 6];
                rq_param_bias = SC_QBN_BIAS[selected_lane*32 +: 32];
            end else if (op_kind && tag_value[15:4] == 12'h220) begin
                rq_param_multiplier = SC_LINEAR_MULTIPLIER[
                    selected_lane*32 +: 32];
                rq_param_shift = SC_LINEAR_SHIFT[selected_lane*6 +: 6];
                rq_param_bias = SC_LINEAR_BIAS[selected_lane*32 +: 32];
            end else begin
                fail("unknown parameter query key");
                rq_param_multiplier = 32'sd0;
                rq_param_shift = 6'd0;
                rq_param_bias = 32'sd0;
            end
        end
    endtask

    // Single-outstanding behavioral parameter provider with random response
    // delay.  Once valid, response fields are held until the atomic join fires.
    always @(posedge clk) begin
        if (!rst_n) begin
            rq_param_valid <= 1'b0;
            param_state <= 0;
            param_delay <= 0;
        end else begin
            case (param_state)
                0: begin
                    rq_param_valid <= 1'b0;
                    if (rq_param_query_valid) begin
                        set_parameter_response(
                            rq_param_query_op_kind,
                            rq_param_query_index,
                            rq_param_query_tag);
                        param_delay <= ($random(seed_param) & 3);
                        param_state <= 1;
                    end
                end
                1: begin
                    if (param_delay == 0) begin
                        rq_param_valid <= 1'b1;
                        param_state <= 2;
                    end else begin
                        param_delay <= param_delay - 1;
                    end
                end
                default: begin
                    if (rq_param_valid && rq_param_ready) begin
                        rq_param_valid <= 1'b0;
                        param_state <= 0;
                    end
                end
            endcase
        end
    end

    // Independent randomized sinks deliberately create complementary fork
    // stalls as well as coefficient and CDF-result backpressure.
    always @(negedge clk) begin
        if (!rst_n) begin
            state_write_ready = 1'b0;
            active_cmd_ready = 1'b0;
            coefficient_ready = 1'b0;
            cdf_result_ready = 1'b0;
        end else begin
            state_write_ready = (($random(seed_ready) & 3) != 0);
            active_cmd_ready = (($random(seed_ready) & 7) != 0);
            coefficient_ready = (($random(seed_ready) & 3) != 0);
            cdf_result_ready = (($random(seed_ready) & 3) != 0);
            if ((cycle_count % 17) == 3) begin
                state_write_ready = 1'b1;
                active_cmd_ready = 1'b0;
            end else if ((cycle_count % 17) == 4) begin
                state_write_ready = 1'b0;
                active_cmd_ready = 1'b1;
            end
        end
    end

    task automatic configure_sigmoid;
        integer byte_index;
        begin
            @(negedge clk);
            sigmoid_cfg_start_valid = 1'b1;
            @(posedge clk);
            while (!sigmoid_cfg_start_ready)
                @(posedge clk);
            @(negedge clk);
            sigmoid_cfg_start_valid = 1'b0;
            for (byte_index = 0; byte_index < SIGMOID_BYTES;
                 byte_index = byte_index + 1) begin
                sigmoid_cfg_data = sigmoid_bytes[byte_index];
                sigmoid_cfg_data_valid = 1'b1;
                @(posedge clk);
                while (!sigmoid_cfg_data_ready)
                    @(posedge clk);
                @(negedge clk);
            end
            sigmoid_cfg_data_valid = 1'b0;
            while (!sigmoid_table_valid)
                @(posedge clk);
        end
    endtask

    task automatic compute_dense;
        input [127:0] values;
        input [15:0] enable_mask;
        begin
            @(negedge clk);
            ctrl_pe_acc_clear = 16'hffff;
            ctrl_pe_acc_enable = 16'd0;
            ctrl_pe_mode = 2'd0;
            @(posedge clk);
            @(negedge clk);
            ctrl_pe_acc_clear = 16'd0;
            ctrl_pe_acc_enable = enable_mask;
            ctrl_pe_operand_a = values;
            ctrl_pe_operand_b = {16{8'h01}};
            @(posedge clk);
            @(negedge clk);
            ctrl_pe_acc_enable = 16'd0;
            while (!hybrid_idle) begin
                @(posedge clk);
                #1;
            end
        end
    endtask

    task automatic send_gate_packet;
        input gate_kind;
        input component;
        input integer group_index;
        begin
            @(negedge clk);
            gate_rq_gate = gate_kind;
            gate_rq_component = component;
            gate_rq_group = group_index[1:0];
            gate_rq_lane_valid = SC_GATE_MASK[group_index*4 +: 4];
            gate_rq_value = pe_accumulator[group_index*128 +: 128];
            gate_rq_multiplier = component ? 128'd0 : {4{32'd256}};
            gate_rq_shift = 24'd0;
            gate_rq_tags = SC_GATE_TAGS[group_index*64 +: 64];
            gate_rq_valid = 1'b1;
            @(posedge clk);
            while (!gate_rq_ready)
                @(posedge clk);
            @(negedge clk);
            gate_rq_valid = 1'b0;
        end
    endtask

    task automatic drive_gate_requests;
        integer group_index;
        begin
            compute_dense(SC_GATE_RAW_I, SC_GATE_MASK);
            for (group_index = 0; group_index < 4;
                 group_index = group_index + 1) begin
                send_gate_packet(1'b0, 1'b0, group_index);
                send_gate_packet(1'b0, 1'b1, group_index);
            end
            compute_dense(SC_GATE_RAW_LAMBDA, SC_GATE_MASK);
            for (group_index = 0; group_index < 4;
                 group_index = group_index + 1) begin
                send_gate_packet(1'b1, 1'b0, group_index);
                send_gate_packet(1'b1, 1'b1, group_index);
            end
        end
    endtask

    task automatic drive_gate_biases;
        integer gate_kind;
        integer group_index;
        integer gap_count;
        integer gap;
        begin
            for (gate_kind = 0; gate_kind < 2; gate_kind = gate_kind + 1) begin
                for (group_index = 0; group_index < 4;
                     group_index = group_index + 1) begin
                    gap_count = ($random(seed_param) & 3);
                    for (gap = 0; gap < gap_count; gap = gap + 1)
                        @(negedge clk);
                    gate_bias_gate = gate_kind[0];
                    gate_bias_group = group_index[1:0];
                    gate_bias_lane_valid =
                        SC_GATE_MASK[group_index*4 +: 4];
                    if (gate_kind == 0)
                        gate_bias_value = SC_GATE_I_BIAS[
                            group_index*128 +: 128];
                    else
                        gate_bias_value = SC_GATE_LAMBDA_BIAS[
                            group_index*128 +: 128];
                    gate_bias_tags = SC_GATE_TAGS[
                        group_index*64 +: 64];
                    gate_bias_valid = 1'b1;
                    @(posedge clk);
                    while (!gate_bias_ready)
                        @(posedge clk);
                    bias_count = bias_count + 1;
                    @(negedge clk);
                    gate_bias_valid = 1'b0;
                end
            end
        end
    endtask

    task automatic check_gate_collection;
        integer check_lane;
        begin
            for (check_lane = 0; check_lane < 16;
                 check_lane = check_lane + 1) begin
                if (SC_GATE_MASK[check_lane]) begin
                    if (dut.gate_i_values_q[check_lane*8 +: 8]
                        !== SC_GATE_EXPECT_I[check_lane*8 +: 8])
                        fail("gate i_t collector mismatch");
                    if (dut.gate_lambda_values_q[check_lane*8 +: 8]
                        !== SC_GATE_EXPECT_LAMBDA[check_lane*8 +: 8])
                        fail("gate lambda collector mismatch");
                end
            end
        end
    endtask

    task automatic run_gate_membrane_qbn;
        begin
            @(negedge clk);
            gate_owner_request = 1'b1;
            while (!gate_owner_grant) begin
                @(posedge clk);
                #1;
            end

            @(negedge clk);
            gate_tile_lane_valid = SC_GATE_MASK;
            gate_tile_tags = SC_GATE_TAGS;
            gate_tile_table_select = SC_GATE_TABLE_SELECT;
            gate_tile_valid = 1'b1;
            @(posedge clk);
            while (!gate_tile_ready)
                @(posedge clk);
            @(negedge clk);
            gate_tile_valid = 1'b0;

            fork
                drive_gate_requests();
                drive_gate_biases();
            join

            while (!gate_collect_complete) begin
                @(posedge clk);
                #1;
            end
            check_gate_collection();

            // Gate release and membrane reservation must occur on the same
            // edge, before gate_collect_complete is cleared by the start.
            @(negedge clk);
            gate_owner_request = 1'b0;
            membrane_start_valid = 1'b1;
            @(posedge clk);
            while (!membrane_start_ready)
                @(posedge clk);
            @(negedge clk);
            membrane_start_valid = 1'b0;

            while (!membrane_done)
                @(posedge clk);
            while (state_count != expected_state_count
                   || active_count != expected_active_count
                   || !serializer_idle || !shared_rq_idle || !qbn_fork_idle) begin
                @(posedge clk);
                #1;
            end
        end
    endtask

    task automatic run_linear;
        begin
            @(negedge clk);
            raw_owner_request = 1'b1;
            while (!raw_owner_grant) begin
                @(posedge clk);
                #1;
            end
            compute_dense(SC_LINEAR_RAW, SC_LINEAR_MASK);

            @(negedge clk);
            linear_tile_lane_valid = SC_LINEAR_MASK;
            linear_tile_base_index = SC_LINEAR_BASE;
            linear_tile_tags = SC_LINEAR_TAGS;
            linear_tile_logical_last = 1'b1;
            linear_tile_valid = 1'b1;
            @(posedge clk);
            while (!linear_tile_ready)
                @(posedge clk);
            @(negedge clk);
            linear_tile_valid = 1'b0;
            raw_owner_request = 1'b0;

            while (coefficient_count != expected_coefficient_count
                   || !serializer_idle || !shared_rq_idle) begin
                @(posedge clk);
                #1;
            end
        end
    endtask

    task automatic run_cdf;
        integer bin_index;
        begin
            cdf_coefficient_real = 64'd0;
            cdf_coefficient_imag = 64'd0;
            for (bin_index = 0; bin_index < 8; bin_index = bin_index + 1) begin
                cdf_coefficient_real[bin_index*8 +: 8] =
                    coefficient_real_mem[bin_index];
                cdf_coefficient_imag[bin_index*8 +: 8] =
                    coefficient_imag_mem[bin_index];
            end

            @(negedge clk);
            cdf_start_valid = 1'b1;
            @(posedge clk);
            while (!cdf_start_ready)
                @(posedge clk);
            @(negedge clk);
            cdf_start_valid = 1'b0;

            cdf_tap_valid = 1'b1;
            @(posedge clk);
            while (!cdf_tap_ready)
                @(posedge clk);
            @(negedge clk);
            cdf_tap_valid = 1'b0;

            while (!cdf_done)
                @(posedge clk);
            while (!compute_idle) begin
                @(posedge clk);
                #1;
            end
        end
    endtask

    always @(posedge clk) begin
        integer expected_lane;
        integer output_lane;
        reg signed [7:0] expected_value;
        cycle_count = cycle_count + 1;
        if (cycle_count > 30000)
            $fatal(1, "pe_array_datapath integration watchdog expired");

        if (rst_n) begin
            if (protocol_error)
                $fatal(1, "wrapper protocol_error asserted cycle=%0d", cycle_count);
            if (overflow_any || (|pe_overflow))
                $fatal(1, "Hybrid PE overflow cycle=%0d", cycle_count);
            if ((compute_owner != 4'b0000) &&
                (compute_owner != 4'b0001) &&
                (compute_owner != 4'b0010) &&
                (compute_owner != 4'b0100) &&
                (compute_owner != 4'b1000))
                $fatal(1, "compute owner is not one-hot-or-zero");

            if (compute_owner == 4'b0010) seen_gate_owner = 1'b1;
            if (compute_owner == 4'b0100) seen_membrane_owner = 1'b1;
            if (compute_owner == 4'b0001) seen_raw_owner = 1'b1;
            if (compute_owner == 4'b1000) seen_cdf_owner = 1'b1;

            if (rq_param_valid && rq_param_ready)
                parameter_count = parameter_count + 1;

            if (dut.serializer_load_fire && !dut.serializer_load_op_kind) begin
                for (output_lane = 0; output_lane < 16;
                     output_lane = output_lane + 1) begin
                    if (SC_GATE_MASK[output_lane]
                        && dut.membrane_result_value[output_lane*8 +: 8]
                           !== SC_MEMBRANE_EXPECT_PRE[output_lane*8 +: 8])
                        fail("membrane state_pre mismatch");
                end
            end
            if (dut.serializer_load_fire && dut.serializer_load_op_kind) begin
                for (output_lane = 0; output_lane < 16;
                     output_lane = output_lane + 1) begin
                    if (SC_LINEAR_MASK[output_lane]
                        && $signed(dut.serializer_values_in[
                            output_lane*32 +: 32])
                           !== $signed({{24{SC_LINEAR_RAW[output_lane*8+7]}},
                                        SC_LINEAR_RAW[output_lane*8 +: 8]}))
                        fail("Linear accumulator/serializer mismatch");
                end
            end

            if (state_write_valid && state_write_ready) begin
                if (state_count >= expected_state_count)
                    fail("duplicate QBN state write");
                else begin
                    expected_lane = expected_state_lanes[state_count];
                    expected_value = SC_QBN_EXPECT[expected_lane*8 +: 8];
                    if (state_write_value !== expected_value
                        || state_write_index !== SC_QBN_BASE + expected_lane
                        || state_write_tag !== SC_GATE_TAGS[
                            expected_lane*16 +: 16]
                        || state_write_last !==
                           (expected_lane == highest_lane16(SC_GATE_MASK)))
                        fail("QBN dense state transaction mismatch");
                    if (state_seen[expected_lane])
                        fail("QBN state transaction repeated");
                    state_seen[expected_lane] = 1'b1;
                    state_count = state_count + 1;
                end
            end

            if (active_cmd_valid && active_cmd_ready) begin
                if (!(active_cmd_write || active_cmd_finalize))
                    fail("valid active command has no action");
                if (active_count >= expected_active_count)
                    fail("duplicate active command");
                else begin
                    expected_lane = expected_active_lanes[active_count];
                    expected_value = SC_QBN_EXPECT[expected_lane*8 +: 8];
                    if (active_cmd_write !== (expected_value >= 0)
                        || active_cmd_finalize !==
                           (expected_lane == highest_lane16(SC_GATE_MASK))
                        || active_cmd_index !== SC_QBN_BASE + expected_lane
                        || active_cmd_tag !== SC_GATE_TAGS[
                            expected_lane*16 +: 16])
                        fail("active command mismatch");
                    if (!state_seen[expected_lane]
                        && !(state_write_valid && state_write_ready
                             && state_write_index == active_cmd_index))
                        fail("active command committed before dense state");
                    active_count = active_count + 1;
                end
            end

            if (coefficient_valid && coefficient_ready) begin
                if (coefficient_count >= expected_coefficient_count)
                    fail("duplicate Linear coefficient");
                else begin
                    expected_lane =
                        expected_coefficient_lanes[coefficient_count];
                    expected_value = SC_LINEAR_EXPECT[expected_lane*8 +: 8];
                    if (coefficient_value !== expected_value
                        || coefficient_index !== SC_LINEAR_BASE + expected_lane
                        || coefficient_tag !== SC_LINEAR_TAGS[
                            expected_lane*16 +: 16]
                        || coefficient_last !==
                           (expected_lane == highest_lane16(SC_LINEAR_MASK)))
                        fail("Linear coefficient transaction mismatch");
                    if (coefficient_seen[expected_lane])
                        fail("Linear coefficient repeated");
                    coefficient_seen[expected_lane] = 1'b1;
                    if (expected_lane < 8)
                        coefficient_real_mem[expected_lane] = coefficient_value;
                    else
                        coefficient_imag_mem[expected_lane-8] = coefficient_value;
                    coefficient_count = coefficient_count + 1;
                end
            end

            if (cdf_result_valid && cdf_result_ready) begin
                if (cdf_result_count != 0)
                    fail("duplicate CDF result");
                cdf_result_count = cdf_result_count + 1;
                if (cdf_result_bin_valid !== SC_CDF_MASK
                    || cdf_result_order !== 3'd1
                    || cdf_result_bin_base !== SC_CDF_BASE
                    || cdf_result_band !== SC_CDF_BAND
                    || cdf_result_tag !== SC_CDF_TAG)
                    fail("CDF result metadata mismatch");
                for (output_lane = 0; output_lane < 8;
                     output_lane = output_lane + 1) begin
                    if (SC_CDF_MASK[output_lane]
                        && (cdf_result_real[output_lane*32 +: 32]
                            !== SC_CDF_EXPECT_REAL[output_lane*32 +: 32]
                            || cdf_result_imag[output_lane*32 +: 32]
                            !== SC_CDF_EXPECT_IMAG[output_lane*32 +: 32]))
                        fail("CDF complex result mismatch");
                end
            end

            if (state_stall_q &&
                (!state_write_valid || state_write_value !== held_state_value
                 || state_write_index !== held_state_index
                 || state_write_tag !== held_state_tag
                 || state_write_last !== held_state_last))
                fail("state output changed while stalled");
            state_stall_q = state_write_valid && !state_write_ready;
            held_state_value = state_write_value;
            held_state_index = state_write_index;
            held_state_tag = state_write_tag;
            held_state_last = state_write_last;

            if (active_stall_q &&
                (!active_cmd_valid || active_cmd_write !== held_active_write
                 || active_cmd_index !== held_active_index
                 || active_cmd_tag !== held_active_tag
                 || active_cmd_finalize !== held_active_finalize))
                fail("active command changed while stalled");
            active_stall_q = active_cmd_valid && !active_cmd_ready;
            held_active_write = active_cmd_write;
            held_active_index = active_cmd_index;
            held_active_tag = active_cmd_tag;
            held_active_finalize = active_cmd_finalize;

            if (coefficient_stall_q &&
                (!coefficient_valid
                 || coefficient_value !== held_coefficient_value
                 || coefficient_index !== held_coefficient_index
                 || coefficient_tag !== held_coefficient_tag
                 || coefficient_last !== held_coefficient_last))
                fail("coefficient output changed while stalled");
            coefficient_stall_q = coefficient_valid && !coefficient_ready;
            held_coefficient_value = coefficient_value;
            held_coefficient_index = coefficient_index;
            held_coefficient_tag = coefficient_tag;
            held_coefficient_last = coefficient_last;

            if (cdf_stall_q &&
                (!cdf_result_valid || cdf_result_real !== held_cdf_real
                 || cdf_result_imag !== held_cdf_imag
                 || cdf_result_bin_valid !== held_cdf_mask
                 || cdf_result_tag !== held_cdf_tag))
                fail("CDF result changed while stalled");
            cdf_stall_q = cdf_result_valid && !cdf_result_ready;
            held_cdf_real = cdf_result_real;
            held_cdf_imag = cdf_result_imag;
            held_cdf_mask = cdf_result_bin_valid;
            held_cdf_tag = cdf_result_tag;
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        raw_owner_request = 1'b0;
        gate_owner_request = 1'b0;
        ctrl_pe_acc_clear = 16'd0;
        ctrl_pe_acc_enable = 16'd0;
        ctrl_pe_mode = 2'd0;
        ctrl_pe_operand_a = 128'd0;
        ctrl_pe_operand_b = 128'd0;
        ctrl_pe_gate_u8 = 128'd0;
        ctrl_pe_spike_enable = 16'd0;
        ctrl_pe_direct_value = 512'd0;
        gate_tile_valid = 1'b0;
        gate_tile_lane_valid = SC_GATE_MASK;
        gate_tile_tags = SC_GATE_TAGS;
        gate_tile_table_select = SC_GATE_TABLE_SELECT;
        gate_rq_valid = 1'b0;
        gate_rq_lane_valid = 4'd0;
        gate_rq_value = 128'd0;
        gate_rq_multiplier = 128'd0;
        gate_rq_shift = 24'd0;
        gate_rq_gate = 1'b0;
        gate_rq_component = 1'b0;
        gate_rq_group = 2'd0;
        gate_rq_tags = 64'd0;
        gate_bias_valid = 1'b0;
        gate_bias_gate = 1'b0;
        gate_bias_group = 2'd0;
        gate_bias_lane_valid = 4'd0;
        gate_bias_value = 128'd0;
        gate_bias_tags = 64'd0;
        sigmoid_cfg_start_valid = 1'b0;
        sigmoid_cfg_data_valid = 1'b0;
        sigmoid_cfg_data = 8'd0;
        membrane_start_valid = 1'b0;
        membrane_u_prev = SC_MEMBRANE_U_PREV;
        membrane_cx_multiplier = {16{32'd1}};
        membrane_cx_shift = 96'd0;
        membrane_cell_multiplier = {16{32'd1}};
        membrane_cell_shift = 96'd0;
        membrane_base_index = SC_QBN_BASE;
        membrane_logical_last = 1'b1;
        linear_tile_valid = 1'b0;
        linear_tile_lane_valid = SC_LINEAR_MASK;
        linear_tile_base_index = SC_LINEAR_BASE;
        linear_tile_tags = SC_LINEAR_TAGS;
        linear_tile_logical_last = 1'b1;
        rq_param_valid = 1'b0;
        rq_param_op_kind = 1'b0;
        rq_param_multiplier = 32'sd0;
        rq_param_shift = 6'd0;
        rq_param_bias = 32'sd0;
        rq_param_index = {INDEX_WIDTH{1'b0}};
        rq_param_tag = 16'd0;
        state_write_ready = 1'b0;
        active_cmd_ready = 1'b0;
        coefficient_ready = 1'b0;
        cdf_start_valid = 1'b0;
        cdf_order = 3'd1;
        cdf_bin_valid = SC_CDF_MASK;
        cdf_bin_base = SC_CDF_BASE;
        cdf_band = SC_CDF_BAND;
        cdf_tag = SC_CDF_TAG;
        cdf_tap_valid = 1'b0;
        cdf_tap_index = 3'd0;
        cdf_spectrum_real = SC_CDF_SPECTRUM_REAL;
        cdf_spectrum_imag = SC_CDF_SPECTRUM_IMAG;
        cdf_coefficient_real = 64'd0;
        cdf_coefficient_imag = 64'd0;
        cdf_result_ready = 1'b0;
        cycle_count = 0;
        errors = 0;
        state_count = 0;
        coefficient_count = 0;
        active_count = 0;
        parameter_count = 0;
        bias_count = 0;
        cdf_result_count = 0;
        seed_ready = 32'h51a7e123;
        seed_param = 32'h0badc0de;
        param_state = 0;
        param_delay = 0;
        seen_gate_owner = 1'b0;
        seen_membrane_owner = 1'b0;
        seen_raw_owner = 1'b0;
        seen_cdf_owner = 1'b0;
        test_passed = 1'b0;
        state_stall_q = 1'b0;
        active_stall_q = 1'b0;
        coefficient_stall_q = 1'b0;
        cdf_stall_q = 1'b0;

        expected_state_count = 0;
        expected_coefficient_count = 0;
        expected_active_count = 0;
        for (lane = 0; lane < 16; lane = lane + 1) begin
            state_seen[lane] = 1'b0;
            coefficient_seen[lane] = 1'b0;
            coefficient_real_mem[lane % 8] = 8'd0;
            coefficient_imag_mem[lane % 8] = 8'd0;
            if (SC_GATE_MASK[lane]) begin
                expected_state_lanes[expected_state_count] = lane;
                expected_state_count = expected_state_count + 1;
                if ($signed(SC_QBN_EXPECT[lane*8 +: 8]) >= 0
                    || lane == highest_lane16(SC_GATE_MASK)) begin
                    expected_active_lanes[expected_active_count] = lane;
                    expected_active_count = expected_active_count + 1;
                end
            end
            if (SC_LINEAR_MASK[lane]) begin
                expected_coefficient_lanes[expected_coefficient_count] = lane;
                expected_coefficient_count = expected_coefficient_count + 1;
            end
        end

        if (!$value$plusargs("LUT=%s", sigmoid_path))
            $fatal(1, "missing +LUT path");
        $readmemh(sigmoid_path, sigmoid_bytes);

        repeat (6) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        configure_sigmoid();
        run_gate_membrane_qbn();
        run_linear();
        run_cdf();

        if (!seen_gate_owner || !seen_membrane_owner
            || !seen_raw_owner || !seen_cdf_owner)
            fail("not all physical PE owners were observed");
        if (bias_count != 8)
            fail("gate recurrent bias handshake count mismatch");
        if (parameter_count != expected_state_count
                              + expected_coefficient_count)
            fail("shared-RQ parameter handshake count mismatch");
        if (state_count != expected_state_count)
            fail("QBN state count mismatch");
        if (active_count != expected_active_count)
            fail("active command count mismatch");
        if (coefficient_count != expected_coefficient_count)
            fail("coefficient count mismatch");
        if (cdf_result_count != 1)
            fail("CDF result count mismatch");
        if (!compute_idle || !local_rq_idle || !postprocess_idle
            || !serializer_idle || !shared_rq_idle || !qbn_fork_idle)
            fail("datapath did not drain to idle");

        if (errors == 0) begin
            test_passed = 1'b1;
            $display("PE_ARRAY_DATAPATH_XSIM_PASS cycles=%0d states=%0d active=%0d coefficients=%0d params=%0d biases=%0d",
                     cycle_count, state_count, active_count,
                     coefficient_count, parameter_count, bias_count);
        end else begin
            $fatal(1, "PE Array datapath failed with %0d errors", errors);
        end
        #10;
        $finish;
    end

endmodule
