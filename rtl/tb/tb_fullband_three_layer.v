`timescale 1ns/1ps

module tb_fullband_three_layer;
    localparam L1_INPUT_SIZE = 3;
    localparam HIDDEN_SIZE = 4;
    localparam PROJECTION_SIZE = 4;
    localparam LANES = 2;
    localparam ROW_TILES = HIDDEN_SIZE / LANES;
    localparam PROJECTION_TILES = PROJECTION_SIZE / LANES;
    localparam L1_INPUT_INDEX_WIDTH = 2;
    localparam INDEX_WIDTH = 2;
    localparam TILE_WIDTH = 1;

    reg clk = 1'b0;
    reg rst;
    reg clear_state;
    reg start;
    reg input_valid;
    wire input_ready;
    reg signed [7:0] input_data;

    wire weight_req_valid;
    reg weight_req_ready;
    wire [1:0] weight_layer;
    wire weight_matrix;
    wire [TILE_WIDTH-1:0] weight_tile;
    wire [INDEX_WIDTH-1:0] weight_index;
    reg weight_rsp_valid;
    wire weight_rsp_ready;
    reg [LANES*8-1:0] weight_rsp_data;

    wire param_req_valid;
    reg param_req_ready;
    wire [1:0] param_layer;
    wire [TILE_WIDTH-1:0] param_tile;
    reg param_rsp_valid;
    wire param_rsp_ready;

    reg [LANES*32-1:0] forget_input_multiplier;
    reg [LANES*6-1:0] forget_input_shift;
    reg [LANES*32-1:0] forget_recurrent_multiplier;
    reg [LANES*6-1:0] forget_recurrent_shift;
    reg [LANES*32-1:0] forget_bias_q;
    reg [LANES*32-1:0] cell_input_multiplier;
    reg [LANES*6-1:0] cell_input_shift;
    reg [LANES*32-1:0] cell_recurrent_multiplier;
    reg [LANES*6-1:0] cell_recurrent_shift;
    reg [LANES*32-1:0] cell_bias_q;
    reg [LANES*32-1:0] previous_multiplier;
    reg [LANES*6-1:0] previous_shift;
    reg [LANES*32-1:0] cellgate_multiplier;
    reg [LANES*6-1:0] cellgate_shift;
    reg [LANES*32-1:0] bn_multiplier;
    reg [LANES*6-1:0] bn_shift;
    reg [LANES*32-1:0] bn_bias_q;
    reg [LANES*32-1:0] linear_multiplier;
    reg [LANES*6-1:0] linear_shift;
    reg [LANES*32-1:0] linear_bias_q;

    reg sigmoid_cfg_we;
    reg sigmoid_cfg_layer;
    reg [7:0] sigmoid_cfg_addr;
    reg [7:0] sigmoid_cfg_data;

    wire result_valid;
    reg result_ready;
    wire [TILE_WIDTH-1:0] result_tile;
    wire result_last;
    wire [LANES*8-1:0] result_data;
    wire [LANES-1:0] result_clipped;
    wire [HIDDEN_SIZE-1:0] layer1_spike_vector;
    wire [HIDDEN_SIZE-1:0] layer2_spike_vector;
    wire [INDEX_WIDTH:0] layer1_recurrent_active;
    wire [INDEX_WIDTH:0] layer2_recurrent_active;
    wire [INDEX_WIDTH:0] projection_active;
    wire [31:0] layer1_input_reads;
    wire [31:0] layer1_recurrent_reads;
    wire [31:0] layer2_input_reads;
    wire [31:0] layer2_recurrent_reads;
    wire [31:0] projection_weight_reads;
    wire [3:0] phase;
    wire busy;
    wire done;

    reg signed [7:0] l1_input_weights [0:HIDDEN_SIZE-1][0:L1_INPUT_SIZE-1];
    reg signed [7:0] l1_recurrent_weights [0:HIDDEN_SIZE-1][0:HIDDEN_SIZE-1];
    reg signed [7:0] l2_input_weights [0:HIDDEN_SIZE-1][0:HIDDEN_SIZE-1];
    reg signed [7:0] l2_recurrent_weights [0:HIDDEN_SIZE-1][0:HIDDEN_SIZE-1];
    reg signed [7:0] projection_weights [0:PROJECTION_SIZE-1][0:HIDDEN_SIZE-1];
    reg [7:0] sigmoid_l1 [0:254];
    reg [7:0] sigmoid_l2 [0:254];
    reg signed [7:0] frame_input [0:L1_INPUT_SIZE-1];

    integer l1_previous_state [0:HIDDEN_SIZE-1];
    integer l1_previous_spike [0:HIDDEN_SIZE-1];
    integer l2_previous_state [0:HIDDEN_SIZE-1];
    integer l2_previous_spike [0:HIDDEN_SIZE-1];
    integer expected_l1_state [0:HIDDEN_SIZE-1];
    integer expected_l1_spike [0:HIDDEN_SIZE-1];
    integer expected_l2_state [0:HIDDEN_SIZE-1];
    integer expected_l2_spike [0:HIDDEN_SIZE-1];
    integer expected_projection [0:PROJECTION_SIZE-1];
    integer expected_projection_clip [0:PROJECTION_SIZE-1];

    integer errors;
    integer frames_checked;
    integer global_cycle;
    integer frame_active;
    integer weight_delay;
    integer param_delay;
    integer result_tiles_received;
    integer weight_counts [0:2][0:1];
    integer param_counts [0:2];
    integer previous_request_layer;
    integer request_stalls;
    integer param_stalls;
    integer result_stalls;
    integer total_request_stalls;
    integer total_param_stalls;
    integer total_result_stalls;

    reg weight_pending;
    reg [1:0] pending_weight_layer;
    reg pending_weight_matrix;
    reg [TILE_WIDTH-1:0] pending_weight_tile;
    reg [INDEX_WIDTH-1:0] pending_weight_index;
    reg param_pending;
    reg [1:0] pending_param_layer;
    reg [TILE_WIDTH-1:0] pending_param_tile;
    reg request_stalled;
    reg [1:0] held_weight_layer;
    reg held_weight_matrix;
    reg [TILE_WIDTH-1:0] held_weight_tile;
    reg [INDEX_WIDTH-1:0] held_weight_index;
    reg param_request_stalled;
    reg [1:0] held_param_layer;
    reg [TILE_WIDTH-1:0] held_param_tile;
    reg output_stalled;
    reg [TILE_WIDTH-1:0] held_result_tile;
    reg [LANES*8-1:0] held_result_data;
    reg [LANES-1:0] held_result_clipped;

    always #5 clk = ~clk;

    fullband_three_layer #(
        .L1_INPUT_SIZE(L1_INPUT_SIZE),
        .HIDDEN_SIZE(HIDDEN_SIZE),
        .PROJECTION_SIZE(PROJECTION_SIZE),
        .LANES(LANES),
        .L1_INPUT_INDEX_WIDTH(L1_INPUT_INDEX_WIDTH),
        .INDEX_WIDTH(INDEX_WIDTH),
        .TILE_WIDTH(TILE_WIDTH)
    ) dut (
        .clk(clk), .rst(rst), .clear_state(clear_state), .start(start),
        .input_valid(input_valid), .input_ready(input_ready), .input_data(input_data),
        .weight_req_valid(weight_req_valid),
        .weight_req_ready(weight_req_ready), .weight_layer(weight_layer),
        .weight_matrix(weight_matrix), .weight_tile(weight_tile),
        .weight_index(weight_index), .weight_rsp_valid(weight_rsp_valid),
        .weight_rsp_ready(weight_rsp_ready), .weight_rsp_data(weight_rsp_data),
        .param_req_valid(param_req_valid), .param_req_ready(param_req_ready),
        .param_layer(param_layer), .param_tile(param_tile),
        .param_rsp_valid(param_rsp_valid), .param_rsp_ready(param_rsp_ready),
        .forget_input_multiplier(forget_input_multiplier),
        .forget_input_shift(forget_input_shift),
        .forget_recurrent_multiplier(forget_recurrent_multiplier),
        .forget_recurrent_shift(forget_recurrent_shift), .forget_bias_q(forget_bias_q),
        .cell_input_multiplier(cell_input_multiplier),
        .cell_input_shift(cell_input_shift),
        .cell_recurrent_multiplier(cell_recurrent_multiplier),
        .cell_recurrent_shift(cell_recurrent_shift), .cell_bias_q(cell_bias_q),
        .previous_multiplier(previous_multiplier), .previous_shift(previous_shift),
        .cellgate_multiplier(cellgate_multiplier), .cellgate_shift(cellgate_shift),
        .bn_multiplier(bn_multiplier), .bn_shift(bn_shift), .bn_bias_q(bn_bias_q),
        .linear_multiplier(linear_multiplier), .linear_shift(linear_shift),
        .linear_bias_q(linear_bias_q),
        .sigmoid_cfg_we(sigmoid_cfg_we),
        .sigmoid_cfg_layer(sigmoid_cfg_layer),
        .sigmoid_cfg_addr(sigmoid_cfg_addr), .sigmoid_cfg_data(sigmoid_cfg_data),
        .result_valid(result_valid), .result_ready(result_ready),
        .result_tile(result_tile), .result_last(result_last),
        .result_data(result_data), .result_clipped(result_clipped),
        .layer1_spike_vector(layer1_spike_vector),
        .layer2_spike_vector(layer2_spike_vector),
        .layer1_recurrent_active(layer1_recurrent_active),
        .layer2_recurrent_active(layer2_recurrent_active),
        .projection_active(projection_active),
        .layer1_input_reads(layer1_input_reads),
        .layer1_recurrent_reads(layer1_recurrent_reads),
        .layer2_input_reads(layer2_input_reads),
        .layer2_recurrent_reads(layer2_recurrent_reads),
        .projection_weight_reads(projection_weight_reads),
        .phase(phase), .busy(busy), .done(done)
    );

    function [LANES*8-1:0] make_weight_word;
        input [1:0] layer_id;
        input matrix;
        input [TILE_WIDTH-1:0] tile;
        input [INDEX_WIDTH-1:0] index;
        integer lane;
        integer row;
        begin
            make_weight_word = {(LANES*8){1'b0}};
            for (lane = 0; lane < LANES; lane = lane + 1) begin
                row = tile * LANES + lane;
                case (layer_id)
                    2'd0: begin
                        if (matrix)
                            make_weight_word[lane*8 +: 8] =
                                l1_recurrent_weights[row][index];
                        else
                            make_weight_word[lane*8 +: 8] =
                                l1_input_weights[row][index];
                    end
                    2'd1: begin
                        if (matrix)
                            make_weight_word[lane*8 +: 8] =
                                l2_recurrent_weights[row][index];
                        else
                            make_weight_word[lane*8 +: 8] =
                                l2_input_weights[row][index];
                    end
                    default: make_weight_word[lane*8 +: 8] =
                                projection_weights[row][index];
                endcase
            end
        end
    endfunction

    function automatic signed [63:0] round_shift_ref;
        input signed [63:0] value;
        input integer shift;
        reg signed [63:0] magnitude;
        begin
            if (shift == 0)
                round_shift_ref = value;
            else if (value < 0) begin
                magnitude = -value;
                round_shift_ref = -((magnitude + (64'sd1 <<< (shift - 1))) >>> shift);
            end else
                round_shift_ref = (value + (64'sd1 <<< (shift - 1))) >>> shift;
        end
    endfunction

    function automatic integer requant_ref;
        input integer value;
        input integer multiplier;
        input integer shift;
        reg signed [63:0] value_ext;
        reg signed [63:0] multiplier_ext;
        begin
            value_ext = value;
            multiplier_ext = multiplier;
            requant_ref = round_shift_ref(value_ext * multiplier_ext, shift);
        end
    endfunction

    function automatic integer saturate_ref;
        input integer value;
        begin
            if (value > 127)
                saturate_ref = 127;
            else if (value < -127)
                saturate_ref = -127;
            else
                saturate_ref = value;
        end
    endfunction

    task pack_parameters;
        input [1:0] layer_id;
        input [TILE_WIDTH-1:0] tile;
        integer lane;
        integer neuron;
        integer forget_bias;
        integer cell_bias;
        begin
            forget_input_multiplier = {(LANES*32){1'b0}};
            forget_input_shift = {(LANES*6){1'b0}};
            forget_recurrent_multiplier = {(LANES*32){1'b0}};
            forget_recurrent_shift = {(LANES*6){1'b0}};
            forget_bias_q = {(LANES*32){1'b0}};
            cell_input_multiplier = {(LANES*32){1'b0}};
            cell_input_shift = {(LANES*6){1'b0}};
            cell_recurrent_multiplier = {(LANES*32){1'b0}};
            cell_recurrent_shift = {(LANES*6){1'b0}};
            cell_bias_q = {(LANES*32){1'b0}};
            previous_multiplier = {(LANES*32){1'b0}};
            previous_shift = {(LANES*6){1'b0}};
            cellgate_multiplier = {(LANES*32){1'b0}};
            cellgate_shift = {(LANES*6){1'b0}};
            bn_multiplier = {(LANES*32){1'b0}};
            bn_shift = {(LANES*6){1'b0}};
            bn_bias_q = {(LANES*32){1'b0}};
            linear_multiplier = {(LANES*32){1'b0}};
            linear_shift = {(LANES*6){1'b0}};
            linear_bias_q = {(LANES*32){1'b0}};
            for (lane = 0; lane < LANES; lane = lane + 1) begin
                neuron = tile * LANES + lane;
                if (layer_id < 2) begin
                    forget_bias = layer_id == 0 ? neuron * 20 - 30
                                                : neuron * 8 - 12;
                    cell_bias = layer_id == 0 ? neuron * 25 - 40
                                              : neuron * 5 - 5;
                    forget_input_multiplier[lane*32 +: 32] = 1073741824;
                    forget_input_shift[lane*6 +: 6] = 22 + (neuron % 2);
                    forget_recurrent_multiplier[lane*32 +: 32] = 1073741824;
                    forget_recurrent_shift[lane*6 +: 6] = 22;
                    forget_bias_q[lane*32 +: 32] = forget_bias * 256;
                    cell_input_multiplier[lane*32 +: 32] = 1073741824;
                    cell_input_shift[lane*6 +: 6] = 22;
                    cell_recurrent_multiplier[lane*32 +: 32] = 1073741824;
                    cell_recurrent_shift[lane*6 +: 6] = 22;
                    cell_bias_q[lane*32 +: 32] = cell_bias * 256;
                    previous_multiplier[lane*32 +: 32] = 1073741824;
                    previous_shift[lane*6 +: 6] = 30;
                    cellgate_multiplier[lane*32 +: 32] = 1073741824;
                    cellgate_shift[lane*6 +: 6] = 30;
                    bn_multiplier[lane*32 +: 32] = 1073741824;
                    bn_shift[lane*6 +: 6] = 22;
                    bn_bias_q[lane*32 +: 32] = ((neuron % 3) - 1) * 256;
                end else begin
                    linear_multiplier[lane*32 +: 32] = 1073741824;
                    linear_shift[lane*6 +: 6] = 22 + (neuron % 2);
                    linear_bias_q[lane*32 +: 32] = (-8 + neuron * 6) * 256;
                end
            end
        end
    endtask

    always @(posedge clk) begin
        if (rst || clear_state) begin
            weight_req_ready <= 1'b0;
            weight_rsp_valid <= 1'b0;
            weight_rsp_data <= {(LANES*8){1'b0}};
            weight_pending <= 1'b0;
            pending_weight_layer <= 2'd0;
            pending_weight_matrix <= 1'b0;
            pending_weight_tile <= {TILE_WIDTH{1'b0}};
            pending_weight_index <= {INDEX_WIDTH{1'b0}};
            weight_delay <= 0;
            global_cycle <= 0;
        end else begin
            global_cycle <= global_cycle + 1;
            weight_req_ready <= !weight_pending && !weight_rsp_valid &&
                                ((global_cycle % 5) != 2);
            if (weight_rsp_valid && weight_rsp_ready)
                weight_rsp_valid <= 1'b0;
            if (weight_req_valid && weight_req_ready) begin
                weight_pending <= 1'b1;
                pending_weight_layer <= weight_layer;
                pending_weight_matrix <= weight_matrix;
                pending_weight_tile <= weight_tile;
                pending_weight_index <= weight_index;
                weight_delay <= (weight_layer + weight_tile +
                                 weight_index + global_cycle) % 3;
                if (frame_active) begin
                    weight_counts[weight_layer][weight_matrix] =
                        weight_counts[weight_layer][weight_matrix] + 1;
                    if (weight_layer < previous_request_layer) begin
                        $display("ERROR fullband weight layer order moved backward %0d -> %0d",
                                 previous_request_layer, weight_layer);
                        errors = errors + 1;
                    end
                    previous_request_layer = weight_layer;
                end
            end
            if (weight_pending) begin
                if ((weight_delay == 0) && !weight_rsp_valid) begin
                    weight_rsp_data <= make_weight_word(
                        pending_weight_layer, pending_weight_matrix,
                        pending_weight_tile, pending_weight_index
                    );
                    weight_rsp_valid <= 1'b1;
                    weight_pending <= 1'b0;
                end else if (weight_delay != 0)
                    weight_delay <= weight_delay - 1;
            end
        end
    end

    always @(posedge clk) begin
        if (rst || clear_state) begin
            param_req_ready <= 1'b0;
            param_rsp_valid <= 1'b0;
            param_pending <= 1'b0;
            pending_param_layer <= 2'd0;
            pending_param_tile <= {TILE_WIDTH{1'b0}};
            param_delay <= 0;
        end else begin
            param_req_ready <= !param_pending && !param_rsp_valid &&
                               ((global_cycle % 4) != 1);
            if (param_rsp_valid && param_rsp_ready)
                param_rsp_valid <= 1'b0;
            if (param_req_valid && param_req_ready) begin
                param_pending <= 1'b1;
                pending_param_layer <= param_layer;
                pending_param_tile <= param_tile;
                param_delay <= (param_layer + param_tile + global_cycle) % 2;
                if (frame_active)
                    param_counts[param_layer] = param_counts[param_layer] + 1;
            end
            if (param_pending) begin
                if ((param_delay == 0) && !param_rsp_valid) begin
                    pack_parameters(pending_param_layer, pending_param_tile);
                    param_rsp_valid <= 1'b1;
                    param_pending <= 1'b0;
                end else if (param_delay != 0)
                    param_delay <= param_delay - 1;
            end
        end
    end

    always @(posedge clk) begin
        if (rst || clear_state)
            result_ready <= 1'b0;
        else if (!frame_active)
            result_ready <= 1'b1;
        else
            result_ready <= global_cycle[0];
    end

    always @(posedge clk) begin
        if (rst || clear_state) begin
            request_stalled <= 1'b0;
            param_request_stalled <= 1'b0;
            output_stalled <= 1'b0;
        end else begin
            if (frame_active && weight_req_valid && !weight_req_ready) begin
                request_stalls = request_stalls + 1;
                total_request_stalls = total_request_stalls + 1;
                if (request_stalled &&
                    ((weight_layer !== held_weight_layer) ||
                     (weight_matrix !== held_weight_matrix) ||
                     (weight_tile !== held_weight_tile) ||
                     (weight_index !== held_weight_index))) begin
                    $display("ERROR fullband weight request changed while stalled");
                    errors = errors + 1;
                end
                request_stalled <= 1'b1;
                held_weight_layer <= weight_layer;
                held_weight_matrix <= weight_matrix;
                held_weight_tile <= weight_tile;
                held_weight_index <= weight_index;
            end else
                request_stalled <= 1'b0;

            if (frame_active && param_req_valid && !param_req_ready) begin
                param_stalls = param_stalls + 1;
                total_param_stalls = total_param_stalls + 1;
                if (param_request_stalled &&
                    ((param_layer !== held_param_layer) ||
                     (param_tile !== held_param_tile))) begin
                    $display("ERROR fullband param request changed while stalled");
                    errors = errors + 1;
                end
                param_request_stalled <= 1'b1;
                held_param_layer <= param_layer;
                held_param_tile <= param_tile;
            end else
                param_request_stalled <= 1'b0;

            if (frame_active && result_valid && !result_ready) begin
                result_stalls = result_stalls + 1;
                total_result_stalls = total_result_stalls + 1;
                if (output_stalled &&
                    ((result_tile !== held_result_tile) ||
                     (result_data !== held_result_data) ||
                     (result_clipped !== held_result_clipped))) begin
                    $display("ERROR fullband result changed while stalled");
                    errors = errors + 1;
                end
                output_stalled <= 1'b1;
                held_result_tile <= result_tile;
                held_result_data <= result_data;
                held_result_clipped <= result_clipped;
            end else
                output_stalled <= 1'b0;
        end
    end

    always @(posedge clk) begin
        integer lane;
        integer output_index;
        if (!rst && !clear_state && frame_active && result_valid && result_ready) begin
            result_tiles_received = result_tiles_received + 1;
            if (result_last !== (result_tile == PROJECTION_TILES - 1)) begin
                $display("ERROR fullband projection last mismatch tile=%0d", result_tile);
                errors = errors + 1;
            end
            for (lane = 0; lane < LANES; lane = lane + 1) begin
                output_index = result_tile * LANES + lane;
                if ($signed(result_data[lane*8 +: 8]) !==
                    expected_projection[output_index] ||
                    result_clipped[lane] !== expected_projection_clip[output_index]) begin
                    $display("ERROR fullband projection output=%0d got=%0d/%0d expected=%0d/%0d",
                             output_index, $signed(result_data[lane*8 +: 8]),
                             result_clipped[lane], expected_projection[output_index],
                             expected_projection_clip[output_index]);
                    errors = errors + 1;
                end
            end
        end
    end

    task initialize_model;
        integer neuron;
        integer index;
        begin
            for (neuron = 0; neuron < HIDDEN_SIZE; neuron = neuron + 1) begin
                for (index = 0; index < L1_INPUT_SIZE; index = index + 1)
                    l1_input_weights[neuron][index] =
                        ((neuron * 5 + index * 3 + 2) % 11) - 5;
                for (index = 0; index < HIDDEN_SIZE; index = index + 1) begin
                    l1_recurrent_weights[neuron][index] =
                        ((neuron * 7 + index * 2 + 1) % 9) - 4;
                    l2_input_weights[neuron][index] =
                        ((neuron * 3 + index * 5 + 4) % 11) - 5;
                    l2_recurrent_weights[neuron][index] =
                        ((neuron * 5 + index * 3 + 2) % 9) - 4;
                end
            end
            for (neuron = 0; neuron < PROJECTION_SIZE; neuron = neuron + 1)
                for (index = 0; index < HIDDEN_SIZE; index = index + 1)
                    projection_weights[neuron][index] =
                        ((neuron * 7 + index * 4 + 3) % 13) - 6;
            for (index = 0; index < 255; index = index + 1) begin
                sigmoid_l1[index] = index;
                sigmoid_l2[index] = ((index * 3) / 4 + 32) > 254
                                  ? 254 : ((index * 3) / 4 + 32);
            end
            for (neuron = 0; neuron < HIDDEN_SIZE; neuron = neuron + 1) begin
                l1_previous_state[neuron] = 0;
                l1_previous_spike[neuron] = 0;
                l2_previous_state[neuron] = 0;
                l2_previous_spike[neuron] = 0;
            end
        end
    endtask

    task configure_sigmoid_layer;
        input layer_id;
        integer address;
        begin
            sigmoid_cfg_layer = layer_id;
            for (address = 0; address < 255; address = address + 1) begin
                @(negedge clk);
                sigmoid_cfg_we = 1'b1;
                sigmoid_cfg_addr = address;
                sigmoid_cfg_data = layer_id ? sigmoid_l2[address]
                                            : sigmoid_l1[address];
            end
            @(negedge clk);
            sigmoid_cfg_we = 1'b0;
        end
    endtask

    task compute_gsu_layer;
        input layer_id;
        integer neuron;
        integer index;
        integer input_acc;
        integer recurrent_acc;
        integer forget_gate;
        integer cell_gate;
        integer forget_u8;
        integer previous_term;
        integer cell_term;
        integer state_pre;
        integer state_value;
        integer input_value;
        integer weight_value;
        reg signed [63:0] sum64;
        begin
            for (neuron = 0; neuron < HIDDEN_SIZE; neuron = neuron + 1) begin
                input_acc = 0;
                recurrent_acc = 0;
                if (layer_id == 0) begin
                    for (index = 0; index < L1_INPUT_SIZE; index = index + 1) begin
                        input_value = $signed(frame_input[index]);
                        weight_value = $signed(l1_input_weights[neuron][index]);
                        input_acc = input_acc + input_value * weight_value;
                    end
                    for (index = 0; index < HIDDEN_SIZE; index = index + 1)
                        if (l1_previous_spike[index])
                            recurrent_acc = recurrent_acc +
                                $signed(l1_recurrent_weights[neuron][index]);
                    sum64 = requant_ref(input_acc, 1073741824, 22 + neuron % 2) +
                            requant_ref(recurrent_acc, 1073741824, 22) +
                            (neuron * 20 - 30) * 256;
                    forget_gate = saturate_ref(round_shift_ref(sum64, 8));
                    sum64 = requant_ref(input_acc, 1073741824, 22) +
                            requant_ref(recurrent_acc, 1073741824, 22) +
                            (neuron * 25 - 40) * 256;
                    cell_gate = saturate_ref(round_shift_ref(sum64, 8));
                    forget_u8 = sigmoid_l1[forget_gate + 127];
                    previous_term = forget_u8 * l1_previous_state[neuron];
                    cell_term = (255 - forget_u8) * cell_gate;
                end else begin
                    for (index = 0; index < HIDDEN_SIZE; index = index + 1)
                        if (expected_l1_spike[index])
                            input_acc = input_acc +
                                $signed(l2_input_weights[neuron][index]);
                    for (index = 0; index < HIDDEN_SIZE; index = index + 1)
                        if (l2_previous_spike[index])
                            recurrent_acc = recurrent_acc +
                                $signed(l2_recurrent_weights[neuron][index]);
                    sum64 = requant_ref(input_acc, 1073741824, 22 + neuron % 2) +
                            requant_ref(recurrent_acc, 1073741824, 22) +
                            (neuron * 8 - 12) * 256;
                    forget_gate = saturate_ref(round_shift_ref(sum64, 8));
                    sum64 = requant_ref(input_acc, 1073741824, 22) +
                            requant_ref(recurrent_acc, 1073741824, 22) +
                            (neuron * 5 - 5) * 256;
                    cell_gate = saturate_ref(round_shift_ref(sum64, 8));
                    forget_u8 = sigmoid_l2[forget_gate + 127];
                    previous_term = forget_u8 * l2_previous_state[neuron];
                    cell_term = (255 - forget_u8) * cell_gate;
                end
                sum64 = requant_ref(previous_term, 1073741824, 30) +
                        requant_ref(cell_term, 1073741824, 30);
                state_pre = saturate_ref(round_shift_ref(sum64, 8));
                sum64 = requant_ref(state_pre, 1073741824, 22) +
                        ((neuron % 3) - 1) * 256;
                state_value = saturate_ref(round_shift_ref(sum64, 8));
                if (layer_id == 0) begin
                    expected_l1_state[neuron] = state_value;
                    expected_l1_spike[neuron] = state_value >= 0;
                end else begin
                    expected_l2_state[neuron] = state_value;
                    expected_l2_spike[neuron] = state_value >= 0;
                end
            end
        end
    endtask

    task build_expected;
        integer output_index;
        integer input_index;
        integer accumulator;
        integer unclamped;
        reg signed [63:0] sum64;
        begin
            compute_gsu_layer(0);
            compute_gsu_layer(1);
            for (output_index = 0; output_index < PROJECTION_SIZE;
                 output_index = output_index + 1) begin
                accumulator = 0;
                for (input_index = 0; input_index < HIDDEN_SIZE;
                     input_index = input_index + 1)
                    if (expected_l2_spike[input_index])
                        accumulator = accumulator +
                            $signed(projection_weights[output_index][input_index]);
                sum64 = requant_ref(accumulator, 1073741824,
                                    22 + output_index % 2) +
                        (-8 + output_index * 6) * 256;
                unclamped = round_shift_ref(sum64, 8);
                expected_projection_clip[output_index] =
                    (unclamped < -127) || (unclamped > 127);
                expected_projection[output_index] = saturate_ref(unclamped);
            end
        end
    endtask

    task send_input_frame;
        integer index;
        begin
            for (index = 0; index < L1_INPUT_SIZE; index = index + 1) begin
                if (index == 1) begin
                    @(negedge clk);
                    input_valid = 1'b0;
                end
                @(negedge clk);
                input_valid = 1'b1;
                input_data = frame_input[index];
                while (!input_ready)
                    @(negedge clk);
            end
            @(negedge clk);
            input_valid = 1'b0;
        end
    endtask

    task run_frame;
        input [8*20-1:0] frame_name;
        integer index;
        integer l1_prev_active;
        integer l2_prev_active;
        integer l1_current_active;
        integer l2_current_active;
        integer timeout;
        integer errors_before;
        begin
            l1_prev_active = 0;
            l2_prev_active = 0;
            for (index = 0; index < HIDDEN_SIZE; index = index + 1) begin
                l1_prev_active = l1_prev_active + l1_previous_spike[index];
                l2_prev_active = l2_prev_active + l2_previous_spike[index];
            end
            build_expected();
            l1_current_active = 0;
            l2_current_active = 0;
            for (index = 0; index < HIDDEN_SIZE; index = index + 1) begin
                l1_current_active = l1_current_active + expected_l1_spike[index];
                l2_current_active = l2_current_active + expected_l2_spike[index];
            end

            @(negedge clk);
            frame_active = 1;
            result_tiles_received = 0;
            request_stalls = 0;
            param_stalls = 0;
            result_stalls = 0;
            previous_request_layer = 0;
            weight_counts[0][0] = 0;
            weight_counts[0][1] = 0;
            weight_counts[1][0] = 0;
            weight_counts[1][1] = 0;
            weight_counts[2][0] = 0;
            weight_counts[2][1] = 0;
            param_counts[0] = 0;
            param_counts[1] = 0;
            param_counts[2] = 0;
            errors_before = errors;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            send_input_frame();

            timeout = 0;
            while (!done && timeout < 20000) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            if (!done)
                $fatal(1, "FAIL tb_fullband_three_layer frame=%0s timed out",
                       frame_name);
            frame_active = 0;
            #1;

            if (layer1_spike_vector !== {expected_l1_spike[3][0],
                                         expected_l1_spike[2][0],
                                         expected_l1_spike[1][0],
                                         expected_l1_spike[0][0]}) begin
                $display("ERROR fullband frame=%0s layer1 spikes got=%b", frame_name,
                         layer1_spike_vector);
                errors = errors + 1;
            end
            if (layer2_spike_vector !== {expected_l2_spike[3][0],
                                         expected_l2_spike[2][0],
                                         expected_l2_spike[1][0],
                                         expected_l2_spike[0][0]}) begin
                $display("ERROR fullband frame=%0s layer2 spikes got=%b", frame_name,
                         layer2_spike_vector);
                errors = errors + 1;
            end
            if ((layer1_recurrent_active != l1_prev_active) ||
                (layer2_recurrent_active != l2_prev_active) ||
                (projection_active != l2_current_active)) begin
                $display("ERROR fullband frame=%0s active counts got=%0d/%0d/%0d expected=%0d/%0d/%0d",
                         frame_name, layer1_recurrent_active,
                         layer2_recurrent_active, projection_active,
                         l1_prev_active, l2_prev_active, l2_current_active);
                errors = errors + 1;
            end
            if ((layer1_input_reads != L1_INPUT_SIZE * ROW_TILES) ||
                (layer1_recurrent_reads != l1_prev_active * ROW_TILES) ||
                (layer2_input_reads != l1_current_active * ROW_TILES) ||
                (layer2_recurrent_reads != l2_prev_active * ROW_TILES) ||
                (projection_weight_reads != l2_current_active * PROJECTION_TILES)) begin
                $display("ERROR fullband frame=%0s DUT read counts got=%0d/%0d/%0d/%0d/%0d",
                         frame_name, layer1_input_reads, layer1_recurrent_reads,
                         layer2_input_reads, layer2_recurrent_reads,
                         projection_weight_reads);
                errors = errors + 1;
            end
            if ((weight_counts[0][0] != L1_INPUT_SIZE * ROW_TILES) ||
                (weight_counts[0][1] != l1_prev_active * ROW_TILES) ||
                (weight_counts[1][0] != l1_current_active * ROW_TILES) ||
                (weight_counts[1][1] != l2_prev_active * ROW_TILES) ||
                (weight_counts[2][0] != l2_current_active * PROJECTION_TILES)) begin
                $display("ERROR fullband frame=%0s TB read counts mismatch", frame_name);
                errors = errors + 1;
            end
            if ((param_counts[0] != ROW_TILES) ||
                (param_counts[1] != ROW_TILES) ||
                (param_counts[2] != PROJECTION_TILES) ||
                (result_tiles_received != PROJECTION_TILES)) begin
                $display("ERROR fullband frame=%0s param/result tile counts mismatch",
                         frame_name);
                errors = errors + 1;
            end

            $display("FULLBAND_FRAME name=%0s l1_prev=%0d l1_out=%0d l2_prev=%0d l2_out=%0d reads_l1=%0d+%0d reads_l2=%0d+%0d reads_proj=%0d stalls=%0d/%0d/%0d errors_added=%0d",
                     frame_name, l1_prev_active, l1_current_active,
                     l2_prev_active, l2_current_active,
                     L1_INPUT_SIZE * ROW_TILES, l1_prev_active * ROW_TILES,
                     l1_current_active * ROW_TILES, l2_prev_active * ROW_TILES,
                     l2_current_active * PROJECTION_TILES,
                     request_stalls, param_stalls, result_stalls,
                     errors - errors_before);

            for (index = 0; index < HIDDEN_SIZE; index = index + 1) begin
                l1_previous_state[index] = expected_l1_state[index];
                l1_previous_spike[index] = expected_l1_spike[index];
                l2_previous_state[index] = expected_l2_state[index];
                l2_previous_spike[index] = expected_l2_spike[index];
            end
            frames_checked = frames_checked + 1;
            @(posedge clk);
            #1;
        end
    endtask

    task clear_reference_state;
        integer index;
        begin
            @(negedge clk);
            clear_state = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            clear_state = 1'b0;
            for (index = 0; index < HIDDEN_SIZE; index = index + 1) begin
                l1_previous_state[index] = 0;
                l1_previous_spike[index] = 0;
                l2_previous_state[index] = 0;
                l2_previous_spike[index] = 0;
            end
        end
    endtask

    initial begin
        errors = 0;
        frames_checked = 0;
        global_cycle = 0;
        frame_active = 0;
        result_tiles_received = 0;
        request_stalls = 0;
        param_stalls = 0;
        result_stalls = 0;
        total_request_stalls = 0;
        total_param_stalls = 0;
        total_result_stalls = 0;
        previous_request_layer = 0;
        rst = 1'b1;
        clear_state = 1'b0;
        start = 1'b0;
        input_valid = 1'b0;
        input_data = 8'sd0;
        sigmoid_cfg_we = 1'b0;
        sigmoid_cfg_layer = 1'b0;
        sigmoid_cfg_addr = 8'd0;
        sigmoid_cfg_data = 8'd0;
        initialize_model();
        pack_parameters(0, 0);

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        configure_sigmoid_layer(0);
        configure_sigmoid_layer(1);

        frame_input[0] = 3;
        frame_input[1] = -2;
        frame_input[2] = 5;
        run_frame("frame_one");

        frame_input[0] = -4;
        frame_input[1] = 6;
        frame_input[2] = 1;
        run_frame("frame_two_stateful");

        frame_input[0] = 127;
        frame_input[1] = -127;
        frame_input[2] = 127;
        run_frame("frame_three_extreme");

        clear_reference_state();
        frame_input[0] = 3;
        frame_input[1] = -2;
        frame_input[2] = 5;
        run_frame("after_clear");

        if (total_request_stalls == 0 || total_param_stalls == 0 ||
            total_result_stalls == 0) begin
            $display("ERROR fullband did not exercise all backpressure paths");
            errors = errors + 1;
        end
        if ((errors == 0) && (frames_checked == 4))
            $display("PASS tb_fullband_three_layer frames=%0d", frames_checked);
        else
            $fatal(1, "FAIL tb_fullband_three_layer errors=%0d frames=%0d",
                   errors, frames_checked);
        $finish;
    end
endmodule
