`timescale 1ns/1ps

module tb_gsu_layer;
    localparam INPUT_SIZE = 5;
    localparam HIDDEN_SIZE = 8;
    localparam LANES = 4;
    localparam ROW_TILES = HIDDEN_SIZE / LANES;
    localparam INPUT_INDEX_WIDTH = 3;
    localparam HIDDEN_INDEX_WIDTH = 3;
    localparam TILE_WIDTH = 1;
    localparam WEIGHT_INDEX_WIDTH = 3;
    localparam GATE_DENOMINATOR = 255;
    localparam GUARD_BITS = 8;

    reg clk = 1'b0;
    reg rst;
    reg clear_state;
    reg start;
    reg input_valid;
    wire input_ready;
    reg signed [7:0] input_data;

    wire weight_req_valid;
    reg weight_req_ready;
    wire weight_matrix;
    wire [TILE_WIDTH-1:0] weight_tile;
    wire [WEIGHT_INDEX_WIDTH-1:0] weight_index;
    reg weight_rsp_valid;
    wire weight_rsp_ready;
    reg [LANES*8-1:0] weight_rsp_data;

    wire param_req_valid;
    reg param_req_ready;
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

    reg sigmoid_cfg_we;
    reg [7:0] sigmoid_cfg_addr;
    reg [7:0] sigmoid_cfg_data;

    wire result_valid;
    reg result_ready;
    wire [TILE_WIDTH-1:0] result_tile;
    wire result_last;
    wire [LANES-1:0] result_spike_data;
    wire [LANES*8-1:0] result_state_data;
    wire [LANES*8-1:0] result_forget_data;
    wire [LANES*8-1:0] result_cellgate_data;
    wire [LANES-1:0] result_forget_clipped;
    wire [LANES-1:0] result_cellgate_clipped;
    wire [LANES-1:0] result_state_pre_clipped;
    wire [LANES-1:0] result_state_clipped;
    wire [HIDDEN_INDEX_WIDTH:0] recurrent_active_count;
    wire [31:0] input_weight_read_count;
    wire [31:0] recurrent_weight_read_count;
    wire [31:0] parameter_read_count;
    wire busy;
    wire done;

    reg signed [7:0] input_weights [0:HIDDEN_SIZE-1][0:INPUT_SIZE-1];
    reg signed [7:0] recurrent_weights [0:HIDDEN_SIZE-1][0:HIDDEN_SIZE-1];
    reg [7:0] sigmoid_values [0:254];
    reg signed [7:0] frame_vector [0:INPUT_SIZE-1];

    integer forget_input_mult_values [0:HIDDEN_SIZE-1];
    integer forget_input_shift_values [0:HIDDEN_SIZE-1];
    integer forget_recurrent_mult_values [0:HIDDEN_SIZE-1];
    integer forget_recurrent_shift_values [0:HIDDEN_SIZE-1];
    integer forget_bias_values [0:HIDDEN_SIZE-1];
    integer cell_input_mult_values [0:HIDDEN_SIZE-1];
    integer cell_input_shift_values [0:HIDDEN_SIZE-1];
    integer cell_recurrent_mult_values [0:HIDDEN_SIZE-1];
    integer cell_recurrent_shift_values [0:HIDDEN_SIZE-1];
    integer cell_bias_values [0:HIDDEN_SIZE-1];
    integer previous_mult_values [0:HIDDEN_SIZE-1];
    integer previous_shift_values [0:HIDDEN_SIZE-1];
    integer cellgate_mult_values [0:HIDDEN_SIZE-1];
    integer cellgate_shift_values [0:HIDDEN_SIZE-1];
    integer bn_mult_values [0:HIDDEN_SIZE-1];
    integer bn_shift_values [0:HIDDEN_SIZE-1];
    integer bn_bias_values [0:HIDDEN_SIZE-1];

    integer previous_state [0:HIDDEN_SIZE-1];
    integer previous_spike [0:HIDDEN_SIZE-1];
    integer expected_forget [0:HIDDEN_SIZE-1];
    integer expected_cellgate [0:HIDDEN_SIZE-1];
    integer expected_state [0:HIDDEN_SIZE-1];
    integer expected_spike [0:HIDDEN_SIZE-1];
    integer expected_forget_clip [0:HIDDEN_SIZE-1];
    integer expected_cellgate_clip [0:HIDDEN_SIZE-1];
    integer expected_state_pre_clip [0:HIDDEN_SIZE-1];
    integer expected_state_clip [0:HIDDEN_SIZE-1];

    integer errors;
    integer frames_checked;
    integer global_cycle;
    integer frame_active;
    integer result_tiles_received;
    integer tb_input_reads;
    integer tb_recurrent_reads;
    integer tb_param_reads;
    integer weight_response_delay;
    integer param_response_delay;
    integer weight_request_stalls;
    integer param_request_stalls;
    integer result_stalls;
    integer total_weight_request_stalls;
    integer total_param_request_stalls;
    integer total_result_stalls;

    reg weight_response_pending;
    reg pending_weight_matrix;
    reg [TILE_WIDTH-1:0] pending_weight_tile;
    reg [WEIGHT_INDEX_WIDTH-1:0] pending_weight_index;
    reg param_response_pending;
    reg [TILE_WIDTH-1:0] pending_param_tile;
    reg [ROW_TILES*INPUT_SIZE-1:0] input_address_seen;
    reg [ROW_TILES*HIDDEN_SIZE-1:0] recurrent_address_seen;
    reg [ROW_TILES-1:0] param_tile_seen;
    reg [ROW_TILES-1:0] result_tile_seen;

    reg weight_request_stalled;
    reg held_weight_matrix;
    reg [TILE_WIDTH-1:0] held_weight_tile;
    reg [WEIGHT_INDEX_WIDTH-1:0] held_weight_index;
    reg param_request_stalled;
    reg [TILE_WIDTH-1:0] held_param_tile;
    reg result_stalled;
    reg [TILE_WIDTH-1:0] held_result_tile;
    reg [LANES-1:0] held_result_spike;
    reg [LANES*8-1:0] held_result_state;
    reg [LANES*8-1:0] held_result_forget;
    reg [LANES*8-1:0] held_result_cellgate;

    always #5 clk = ~clk;

    gsu_layer #(
        .INPUT_SIZE(INPUT_SIZE),
        .HIDDEN_SIZE(HIDDEN_SIZE),
        .LANES(LANES),
        .INPUT_IS_BINARY(0),
        .INPUT_INDEX_WIDTH(INPUT_INDEX_WIDTH),
        .HIDDEN_INDEX_WIDTH(HIDDEN_INDEX_WIDTH),
        .TILE_WIDTH(TILE_WIDTH),
        .WEIGHT_INDEX_WIDTH(WEIGHT_INDEX_WIDTH),
        .GATE_DENOMINATOR(GATE_DENOMINATOR),
        .GUARD_BITS(GUARD_BITS)
    ) dut (
        .clk(clk),
        .rst(rst),
        .clear_state(clear_state),
        .start(start),
        .input_valid(input_valid),
        .input_ready(input_ready),
        .input_data(input_data),
        .weight_req_valid(weight_req_valid),
        .weight_req_ready(weight_req_ready),
        .weight_matrix(weight_matrix),
        .weight_tile(weight_tile),
        .weight_index(weight_index),
        .weight_rsp_valid(weight_rsp_valid),
        .weight_rsp_ready(weight_rsp_ready),
        .weight_rsp_data(weight_rsp_data),
        .param_req_valid(param_req_valid),
        .param_req_ready(param_req_ready),
        .param_tile(param_tile),
        .param_rsp_valid(param_rsp_valid),
        .param_rsp_ready(param_rsp_ready),
        .forget_input_multiplier(forget_input_multiplier),
        .forget_input_shift(forget_input_shift),
        .forget_recurrent_multiplier(forget_recurrent_multiplier),
        .forget_recurrent_shift(forget_recurrent_shift),
        .forget_bias_q(forget_bias_q),
        .cell_input_multiplier(cell_input_multiplier),
        .cell_input_shift(cell_input_shift),
        .cell_recurrent_multiplier(cell_recurrent_multiplier),
        .cell_recurrent_shift(cell_recurrent_shift),
        .cell_bias_q(cell_bias_q),
        .previous_multiplier(previous_multiplier),
        .previous_shift(previous_shift),
        .cellgate_multiplier(cellgate_multiplier),
        .cellgate_shift(cellgate_shift),
        .bn_multiplier(bn_multiplier),
        .bn_shift(bn_shift),
        .bn_bias_q(bn_bias_q),
        .sigmoid_cfg_we(sigmoid_cfg_we),
        .sigmoid_cfg_addr(sigmoid_cfg_addr),
        .sigmoid_cfg_data(sigmoid_cfg_data),
        .result_valid(result_valid),
        .result_ready(result_ready),
        .result_tile(result_tile),
        .result_last(result_last),
        .result_spike_data(result_spike_data),
        .result_state_data(result_state_data),
        .result_forget_data(result_forget_data),
        .result_cellgate_data(result_cellgate_data),
        .result_forget_clipped(result_forget_clipped),
        .result_cellgate_clipped(result_cellgate_clipped),
        .result_state_pre_clipped(result_state_pre_clipped),
        .result_state_clipped(result_state_clipped),
        .recurrent_active_count(recurrent_active_count),
        .input_weight_read_count(input_weight_read_count),
        .recurrent_weight_read_count(recurrent_weight_read_count),
        .parameter_read_count(parameter_read_count),
        .busy(busy),
        .done(done)
    );

    function [LANES*8-1:0] make_weight_word;
        input matrix;
        input [TILE_WIDTH-1:0] tile;
        input [WEIGHT_INDEX_WIDTH-1:0] index;
        integer lane;
        integer neuron;
        begin
            make_weight_word = {(LANES*8){1'b0}};
            for (lane = 0; lane < LANES; lane = lane + 1) begin
                neuron = tile * LANES + lane;
                if (matrix)
                    make_weight_word[lane*8 +: 8] =
                        recurrent_weights[neuron][index];
                else
                    make_weight_word[lane*8 +: 8] =
                        input_weights[neuron][index];
            end
        end
    endfunction

    function automatic signed [63:0] round_shift_ref;
        input signed [63:0] value;
        input integer shift;
        reg signed [63:0] magnitude;
        begin
            if (shift == 0) begin
                round_shift_ref = value;
            end else if (value < 0) begin
                magnitude = -value;
                round_shift_ref = -((magnitude + (64'sd1 <<< (shift - 1))) >>> shift);
            end else begin
                round_shift_ref = (value + (64'sd1 <<< (shift - 1))) >>> shift;
            end
        end
    endfunction

    function automatic integer requant_ref;
        input integer value;
        input integer multiplier;
        input integer shift;
        reg signed [63:0] value_ext;
        reg signed [63:0] multiplier_ext;
        reg signed [63:0] product;
        begin
            value_ext = value;
            multiplier_ext = multiplier;
            product = value_ext * multiplier_ext;
            requant_ref = round_shift_ref(product, shift);
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

    task pack_param_tile;
        input [TILE_WIDTH-1:0] tile;
        integer lane;
        integer neuron;
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
            for (lane = 0; lane < LANES; lane = lane + 1) begin
                neuron = tile * LANES + lane;
                forget_input_multiplier[lane*32 +: 32] =
                    forget_input_mult_values[neuron];
                forget_input_shift[lane*6 +: 6] =
                    forget_input_shift_values[neuron];
                forget_recurrent_multiplier[lane*32 +: 32] =
                    forget_recurrent_mult_values[neuron];
                forget_recurrent_shift[lane*6 +: 6] =
                    forget_recurrent_shift_values[neuron];
                forget_bias_q[lane*32 +: 32] = forget_bias_values[neuron];
                cell_input_multiplier[lane*32 +: 32] =
                    cell_input_mult_values[neuron];
                cell_input_shift[lane*6 +: 6] =
                    cell_input_shift_values[neuron];
                cell_recurrent_multiplier[lane*32 +: 32] =
                    cell_recurrent_mult_values[neuron];
                cell_recurrent_shift[lane*6 +: 6] =
                    cell_recurrent_shift_values[neuron];
                cell_bias_q[lane*32 +: 32] = cell_bias_values[neuron];
                previous_multiplier[lane*32 +: 32] =
                    previous_mult_values[neuron];
                previous_shift[lane*6 +: 6] = previous_shift_values[neuron];
                cellgate_multiplier[lane*32 +: 32] =
                    cellgate_mult_values[neuron];
                cellgate_shift[lane*6 +: 6] = cellgate_shift_values[neuron];
                bn_multiplier[lane*32 +: 32] = bn_mult_values[neuron];
                bn_shift[lane*6 +: 6] = bn_shift_values[neuron];
                bn_bias_q[lane*32 +: 32] = bn_bias_values[neuron];
            end
        end
    endtask

    // Packed weight-memory model with request stalls and 0..2-cycle latency.
    always @(posedge clk) begin
        integer address;
        if (rst || clear_state) begin
            weight_req_ready <= 1'b0;
            weight_rsp_valid <= 1'b0;
            weight_rsp_data <= {(LANES*8){1'b0}};
            weight_response_pending <= 1'b0;
            pending_weight_matrix <= 1'b0;
            pending_weight_tile <= {TILE_WIDTH{1'b0}};
            pending_weight_index <= {WEIGHT_INDEX_WIDTH{1'b0}};
            weight_response_delay <= 0;
            global_cycle <= 0;
        end else begin
            global_cycle <= global_cycle + 1;
            weight_req_ready <= !weight_response_pending && !weight_rsp_valid &&
                                ((global_cycle % 5) != 1);

            if (weight_rsp_valid && weight_rsp_ready)
                weight_rsp_valid <= 1'b0;

            if (weight_req_valid && weight_req_ready) begin
                weight_response_pending <= 1'b1;
                pending_weight_matrix <= weight_matrix;
                pending_weight_tile <= weight_tile;
                pending_weight_index <= weight_index;
                weight_response_delay <=
                    (weight_tile + weight_index + global_cycle) % 3;
                if (frame_active) begin
                    if (weight_matrix) begin
                        tb_recurrent_reads = tb_recurrent_reads + 1;
                        address = weight_tile * HIDDEN_SIZE + weight_index;
                        if (recurrent_address_seen[address]) begin
                            $display("ERROR gsu_layer duplicate recurrent address tile=%0d index=%0d",
                                     weight_tile, weight_index);
                            errors = errors + 1;
                        end
                        recurrent_address_seen[address] = 1'b1;
                        if (!previous_spike[weight_index]) begin
                            $display("ERROR gsu_layer read inactive recurrent index=%0d",
                                     weight_index);
                            errors = errors + 1;
                        end
                    end else begin
                        tb_input_reads = tb_input_reads + 1;
                        address = weight_tile * INPUT_SIZE + weight_index;
                        if (input_address_seen[address]) begin
                            $display("ERROR gsu_layer duplicate input address tile=%0d index=%0d",
                                     weight_tile, weight_index);
                            errors = errors + 1;
                        end
                        input_address_seen[address] = 1'b1;
                    end
                end
            end

            if (weight_response_pending) begin
                if ((weight_response_delay == 0) && !weight_rsp_valid) begin
                    weight_rsp_data <= make_weight_word(
                        pending_weight_matrix,
                        pending_weight_tile,
                        pending_weight_index
                    );
                    weight_rsp_valid <= 1'b1;
                    weight_response_pending <= 1'b0;
                end else if (weight_response_delay != 0) begin
                    weight_response_delay <= weight_response_delay - 1;
                end
            end
        end
    end

    // Parameter-memory model returns all integer parameters for one row tile.
    always @(posedge clk) begin
        if (rst || clear_state) begin
            param_req_ready <= 1'b0;
            param_rsp_valid <= 1'b0;
            param_response_pending <= 1'b0;
            pending_param_tile <= {TILE_WIDTH{1'b0}};
            param_response_delay <= 0;
        end else begin
            param_req_ready <= !param_response_pending && !param_rsp_valid &&
                               ((global_cycle % 4) != 2);

            if (param_rsp_valid && param_rsp_ready)
                param_rsp_valid <= 1'b0;

            if (param_req_valid && param_req_ready) begin
                param_response_pending <= 1'b1;
                pending_param_tile <= param_tile;
                param_response_delay <= (param_tile + global_cycle) % 2;
                if (frame_active) begin
                    tb_param_reads = tb_param_reads + 1;
                    if (param_tile_seen[param_tile]) begin
                        $display("ERROR gsu_layer duplicate parameter tile=%0d", param_tile);
                        errors = errors + 1;
                    end
                    param_tile_seen[param_tile] = 1'b1;
                end
            end

            if (param_response_pending) begin
                if ((param_response_delay == 0) && !param_rsp_valid) begin
                    pack_param_tile(pending_param_tile);
                    param_rsp_valid <= 1'b1;
                    param_response_pending <= 1'b0;
                end else if (param_response_delay != 0) begin
                    param_response_delay <= param_response_delay - 1;
                end
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

    // Stability monitors for all three ready/valid output channels.
    always @(posedge clk) begin
        if (rst || clear_state) begin
            weight_request_stalled <= 1'b0;
            param_request_stalled <= 1'b0;
            result_stalled <= 1'b0;
        end else begin
            if (frame_active && weight_req_valid && !weight_req_ready) begin
                weight_request_stalls = weight_request_stalls + 1;
                total_weight_request_stalls = total_weight_request_stalls + 1;
                if (weight_request_stalled &&
                    ((weight_matrix !== held_weight_matrix) ||
                     (weight_tile !== held_weight_tile) ||
                     (weight_index !== held_weight_index))) begin
                    $display("ERROR gsu_layer weight request changed while stalled");
                    errors = errors + 1;
                end
                weight_request_stalled <= 1'b1;
                held_weight_matrix <= weight_matrix;
                held_weight_tile <= weight_tile;
                held_weight_index <= weight_index;
            end else begin
                weight_request_stalled <= 1'b0;
            end

            if (frame_active && param_req_valid && !param_req_ready) begin
                param_request_stalls = param_request_stalls + 1;
                total_param_request_stalls = total_param_request_stalls + 1;
                if (param_request_stalled && (param_tile !== held_param_tile)) begin
                    $display("ERROR gsu_layer parameter request changed while stalled");
                    errors = errors + 1;
                end
                param_request_stalled <= 1'b1;
                held_param_tile <= param_tile;
            end else begin
                param_request_stalled <= 1'b0;
            end

            if (frame_active && result_valid && !result_ready) begin
                result_stalls = result_stalls + 1;
                total_result_stalls = total_result_stalls + 1;
                if (result_stalled &&
                    ((result_tile !== held_result_tile) ||
                     (result_spike_data !== held_result_spike) ||
                     (result_state_data !== held_result_state) ||
                     (result_forget_data !== held_result_forget) ||
                     (result_cellgate_data !== held_result_cellgate))) begin
                    $display("ERROR gsu_layer result changed while stalled");
                    errors = errors + 1;
                end
                result_stalled <= 1'b1;
                held_result_tile <= result_tile;
                held_result_spike <= result_spike_data;
                held_result_state <= result_state_data;
                held_result_forget <= result_forget_data;
                held_result_cellgate <= result_cellgate_data;
            end else begin
                result_stalled <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        integer lane;
        integer neuron;
        if (!rst && !clear_state && frame_active && result_valid && result_ready) begin
            if (result_tile_seen[result_tile]) begin
                $display("ERROR gsu_layer duplicate result tile=%0d", result_tile);
                errors = errors + 1;
            end
            result_tile_seen[result_tile] = 1'b1;
            result_tiles_received = result_tiles_received + 1;
            if (result_last !== (result_tile == ROW_TILES - 1)) begin
                $display("ERROR gsu_layer result_last mismatch tile=%0d", result_tile);
                errors = errors + 1;
            end
            for (lane = 0; lane < LANES; lane = lane + 1) begin
                neuron = result_tile * LANES + lane;
                if ($signed(result_forget_data[lane*8 +: 8]) !==
                    expected_forget[neuron]) begin
                    $display("ERROR gsu_layer neuron=%0d forget got=%0d expected=%0d",
                             neuron, $signed(result_forget_data[lane*8 +: 8]),
                             expected_forget[neuron]);
                    errors = errors + 1;
                end
                if ($signed(result_cellgate_data[lane*8 +: 8]) !==
                    expected_cellgate[neuron]) begin
                    $display("ERROR gsu_layer neuron=%0d cellgate got=%0d expected=%0d",
                             neuron, $signed(result_cellgate_data[lane*8 +: 8]),
                             expected_cellgate[neuron]);
                    errors = errors + 1;
                end
                if ($signed(result_state_data[lane*8 +: 8]) !==
                    expected_state[neuron]) begin
                    $display("ERROR gsu_layer neuron=%0d state got=%0d expected=%0d",
                             neuron, $signed(result_state_data[lane*8 +: 8]),
                             expected_state[neuron]);
                    errors = errors + 1;
                end
                if (result_spike_data[lane] !== expected_spike[neuron]) begin
                    $display("ERROR gsu_layer neuron=%0d spike got=%0d expected=%0d",
                             neuron, result_spike_data[lane], expected_spike[neuron]);
                    errors = errors + 1;
                end
                if ((result_forget_clipped[lane] !== expected_forget_clip[neuron]) ||
                    (result_cellgate_clipped[lane] !== expected_cellgate_clip[neuron]) ||
                    (result_state_pre_clipped[lane] !== expected_state_pre_clip[neuron]) ||
                    (result_state_clipped[lane] !== expected_state_clip[neuron])) begin
                    $display("ERROR gsu_layer neuron=%0d clipping flags got=%b%b%b%b expected=%0d%0d%0d%0d",
                             neuron, result_forget_clipped[lane],
                             result_cellgate_clipped[lane],
                             result_state_pre_clipped[lane], result_state_clipped[lane],
                             expected_forget_clip[neuron],
                             expected_cellgate_clip[neuron],
                             expected_state_pre_clip[neuron],
                             expected_state_clip[neuron]);
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
                for (index = 0; index < INPUT_SIZE; index = index + 1)
                    input_weights[neuron][index] =
                        ((neuron * 7 + index * 5 + 3) % 15) - 7;
                for (index = 0; index < HIDDEN_SIZE; index = index + 1)
                    recurrent_weights[neuron][index] =
                        ((neuron * 11 + index * 3 + 5) % 13) - 6;

                forget_input_mult_values[neuron] = 1073741824;
                forget_input_shift_values[neuron] = 22 + (neuron % 2);
                forget_recurrent_mult_values[neuron] = 1073741824;
                forget_recurrent_shift_values[neuron] = 22;
                forget_bias_values[neuron] = (neuron * 18 - 60) * 256;
                cell_input_mult_values[neuron] = 1073741824;
                cell_input_shift_values[neuron] = 22;
                cell_recurrent_mult_values[neuron] = 1073741824;
                cell_recurrent_shift_values[neuron] = 22;
                cell_bias_values[neuron] = (neuron * 20 - 70) * 256;
                previous_mult_values[neuron] = 1073741824;
                previous_shift_values[neuron] = 30;
                cellgate_mult_values[neuron] = 1073741824;
                cellgate_shift_values[neuron] = 30;
                bn_mult_values[neuron] = 1073741824;
                bn_shift_values[neuron] = 22;
                bn_bias_values[neuron] = ((neuron % 3) - 1) * 512;
                previous_state[neuron] = 0;
                previous_spike[neuron] = 0;
            end
            for (index = 0; index < 255; index = index + 1)
                sigmoid_values[index] = index;
        end
    endtask

    task configure_sigmoid;
        integer address;
        begin
            for (address = 0; address < 255; address = address + 1) begin
                @(negedge clk);
                sigmoid_cfg_we = 1'b1;
                sigmoid_cfg_addr = address;
                sigmoid_cfg_data = sigmoid_values[address];
            end
            @(negedge clk);
            sigmoid_cfg_we = 1'b0;
        end
    endtask

    task build_expected;
        integer neuron;
        integer index;
        integer input_acc;
        integer recurrent_acc;
        integer gate_unclamped;
        integer forget_u8;
        integer previous_term;
        integer cellgate_term;
        integer state_pre_unclamped;
        integer state_pre;
        integer state_unclamped;
        integer input_value;
        integer weight_value;
        reg signed [63:0] sum64;
        begin
            for (neuron = 0; neuron < HIDDEN_SIZE; neuron = neuron + 1) begin
                input_acc = 0;
                recurrent_acc = 0;
                for (index = 0; index < INPUT_SIZE; index = index + 1) begin
                    input_value = $signed(frame_vector[index]);
                    weight_value = $signed(input_weights[neuron][index]);
                    input_acc = input_acc + input_value * weight_value;
                end
                for (index = 0; index < HIDDEN_SIZE; index = index + 1)
                    if (previous_spike[index])
                        recurrent_acc = recurrent_acc +
                            recurrent_weights[neuron][index];

                sum64 = requant_ref(input_acc,
                                    forget_input_mult_values[neuron],
                                    forget_input_shift_values[neuron]) +
                        requant_ref(recurrent_acc,
                                    forget_recurrent_mult_values[neuron],
                                    forget_recurrent_shift_values[neuron]) +
                        forget_bias_values[neuron];
                gate_unclamped = round_shift_ref(sum64, GUARD_BITS);
                expected_forget_clip[neuron] =
                    (gate_unclamped < -127) || (gate_unclamped > 127);
                expected_forget[neuron] = saturate_ref(gate_unclamped);

                sum64 = requant_ref(input_acc,
                                    cell_input_mult_values[neuron],
                                    cell_input_shift_values[neuron]) +
                        requant_ref(recurrent_acc,
                                    cell_recurrent_mult_values[neuron],
                                    cell_recurrent_shift_values[neuron]) +
                        cell_bias_values[neuron];
                gate_unclamped = round_shift_ref(sum64, GUARD_BITS);
                expected_cellgate_clip[neuron] =
                    (gate_unclamped < -127) || (gate_unclamped > 127);
                expected_cellgate[neuron] = saturate_ref(gate_unclamped);

                forget_u8 = sigmoid_values[expected_forget[neuron] + 127];
                previous_term = forget_u8 * previous_state[neuron];
                cellgate_term = (GATE_DENOMINATOR - forget_u8) *
                                expected_cellgate[neuron];
                sum64 = requant_ref(previous_term,
                                    previous_mult_values[neuron],
                                    previous_shift_values[neuron]) +
                        requant_ref(cellgate_term,
                                    cellgate_mult_values[neuron],
                                    cellgate_shift_values[neuron]);
                state_pre_unclamped = round_shift_ref(sum64, GUARD_BITS);
                expected_state_pre_clip[neuron] =
                    (state_pre_unclamped < -127) ||
                    (state_pre_unclamped > 127);
                state_pre = saturate_ref(state_pre_unclamped);

                sum64 = requant_ref(state_pre,
                                    bn_mult_values[neuron],
                                    bn_shift_values[neuron]) +
                        bn_bias_values[neuron];
                state_unclamped = round_shift_ref(sum64, GUARD_BITS);
                expected_state_clip[neuron] =
                    (state_unclamped < -127) || (state_unclamped > 127);
                expected_state[neuron] = saturate_ref(state_unclamped);
                expected_spike[neuron] = expected_state[neuron] >= 0;
            end
        end
    endtask

    task send_frame_input;
        integer index;
        begin
            for (index = 0; index < INPUT_SIZE; index = index + 1) begin
                if ((index % 3) == 1) begin
                    @(negedge clk);
                    input_valid = 1'b0;
                end
                @(negedge clk);
                input_valid = 1'b1;
                input_data = frame_vector[index];
                while (!input_ready)
                    @(negedge clk);
            end
            @(negedge clk);
            input_valid = 1'b0;
        end
    endtask

    task run_frame;
        input [8*24-1:0] frame_name;
        integer neuron;
        integer tile;
        integer expected_active;
        integer expected_input_reads;
        integer expected_recurrent_reads;
        integer timeout;
        integer errors_before;
        begin
            expected_active = 0;
            for (neuron = 0; neuron < HIDDEN_SIZE; neuron = neuron + 1)
                expected_active = expected_active + previous_spike[neuron];
            expected_input_reads = INPUT_SIZE * ROW_TILES;
            expected_recurrent_reads = expected_active * ROW_TILES;
            build_expected();

            @(negedge clk);
            if (busy || weight_response_pending || weight_rsp_valid ||
                param_response_pending || param_rsp_valid) begin
                $display("ERROR gsu_layer frame=%0s started while busy", frame_name);
                errors = errors + 1;
            end
            frame_active = 1;
            result_tiles_received = 0;
            tb_input_reads = 0;
            tb_recurrent_reads = 0;
            tb_param_reads = 0;
            weight_request_stalls = 0;
            param_request_stalls = 0;
            result_stalls = 0;
            input_address_seen = {(ROW_TILES*INPUT_SIZE){1'b0}};
            recurrent_address_seen = {(ROW_TILES*HIDDEN_SIZE){1'b0}};
            param_tile_seen = {ROW_TILES{1'b0}};
            result_tile_seen = {ROW_TILES{1'b0}};
            errors_before = errors;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            send_frame_input();

            timeout = 0;
            while (!done && (timeout < 10000)) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            if (!done)
                $fatal(1, "FAIL tb_gsu_layer frame=%0s timed out", frame_name);
            frame_active = 0;
            #1;

            if (recurrent_active_count != expected_active) begin
                $display("ERROR gsu_layer frame=%0s active got=%0d expected=%0d",
                         frame_name, recurrent_active_count, expected_active);
                errors = errors + 1;
            end
            if ((input_weight_read_count != expected_input_reads) ||
                (tb_input_reads != expected_input_reads)) begin
                $display("ERROR gsu_layer frame=%0s input reads dut/tb=%0d/%0d expected=%0d",
                         frame_name, input_weight_read_count, tb_input_reads,
                         expected_input_reads);
                errors = errors + 1;
            end
            if ((recurrent_weight_read_count != expected_recurrent_reads) ||
                (tb_recurrent_reads != expected_recurrent_reads)) begin
                $display("ERROR gsu_layer frame=%0s recurrent reads dut/tb=%0d/%0d expected=%0d",
                         frame_name, recurrent_weight_read_count,
                         tb_recurrent_reads, expected_recurrent_reads);
                errors = errors + 1;
            end
            if ((parameter_read_count != ROW_TILES) ||
                (tb_param_reads != ROW_TILES)) begin
                $display("ERROR gsu_layer frame=%0s parameter reads dut/tb=%0d/%0d expected=%0d",
                         frame_name, parameter_read_count, tb_param_reads, ROW_TILES);
                errors = errors + 1;
            end
            if ((result_tiles_received != ROW_TILES) ||
                (result_tile_seen !== {ROW_TILES{1'b1}}) ||
                (param_tile_seen !== {ROW_TILES{1'b1}}) ||
                (input_address_seen !== {(ROW_TILES*INPUT_SIZE){1'b1}})) begin
                $display("ERROR gsu_layer frame=%0s tile/address coverage incomplete",
                         frame_name);
                errors = errors + 1;
            end
            for (tile = 0; tile < ROW_TILES; tile = tile + 1) begin
                for (neuron = 0; neuron < HIDDEN_SIZE; neuron = neuron + 1) begin
                    if (previous_spike[neuron] &&
                        !recurrent_address_seen[tile * HIDDEN_SIZE + neuron]) begin
                        $display("ERROR gsu_layer frame=%0s missing recurrent tile=%0d index=%0d",
                                 frame_name, tile, neuron);
                        errors = errors + 1;
                    end
                end
            end

            $display("GSU_FRAME name=%0s prev_active=%0d input_reads=%0d recurrent_reads=%0d param_reads=%0d weight_stalls=%0d param_stalls=%0d result_stalls=%0d errors_added=%0d",
                     frame_name, expected_active, expected_input_reads,
                     expected_recurrent_reads, ROW_TILES,
                     weight_request_stalls, param_request_stalls, result_stalls,
                     errors - errors_before);

            for (neuron = 0; neuron < HIDDEN_SIZE; neuron = neuron + 1) begin
                previous_state[neuron] = expected_state[neuron];
                previous_spike[neuron] = expected_spike[neuron];
            end
            frames_checked = frames_checked + 1;
            @(posedge clk);
            #1;
        end
    endtask

    task clear_reference_state;
        integer neuron;
        begin
            @(negedge clk);
            clear_state = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            clear_state = 1'b0;
            for (neuron = 0; neuron < HIDDEN_SIZE; neuron = neuron + 1) begin
                previous_state[neuron] = 0;
                previous_spike[neuron] = 0;
            end
        end
    endtask

    initial begin
        errors = 0;
        frames_checked = 0;
        global_cycle = 0;
        frame_active = 0;
        total_weight_request_stalls = 0;
        total_param_request_stalls = 0;
        total_result_stalls = 0;
        result_tiles_received = 0;
        tb_input_reads = 0;
        tb_recurrent_reads = 0;
        tb_param_reads = 0;
        weight_request_stalls = 0;
        param_request_stalls = 0;
        result_stalls = 0;
        rst = 1'b1;
        clear_state = 1'b0;
        start = 1'b0;
        input_valid = 1'b0;
        input_data = 8'sd0;
        sigmoid_cfg_we = 1'b0;
        sigmoid_cfg_addr = 8'd0;
        sigmoid_cfg_data = 8'd0;
        initialize_model();
        pack_param_tile(0);

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        configure_sigmoid();

        frame_vector[0] = 3;
        frame_vector[1] = -2;
        frame_vector[2] = 5;
        frame_vector[3] = 1;
        frame_vector[4] = -4;
        run_frame("first_zero_state");

        frame_vector[0] = -7;
        frame_vector[1] = 4;
        frame_vector[2] = 0;
        frame_vector[3] = 6;
        frame_vector[4] = 2;
        run_frame("recurrent_sparse");

        frame_vector[0] = 127;
        frame_vector[1] = -127;
        frame_vector[2] = 127;
        frame_vector[3] = -127;
        frame_vector[4] = 127;
        run_frame("gate_clipping");

        clear_reference_state();
        frame_vector[0] = 3;
        frame_vector[1] = -2;
        frame_vector[2] = 5;
        frame_vector[3] = 1;
        frame_vector[4] = -4;
        run_frame("after_state_clear");

        if (total_weight_request_stalls == 0) begin
            $display("ERROR gsu_layer did not exercise weight request stalls");
            errors = errors + 1;
        end
        if (total_param_request_stalls == 0) begin
            $display("ERROR gsu_layer did not exercise parameter request stalls");
            errors = errors + 1;
        end
        if (total_result_stalls == 0) begin
            $display("ERROR gsu_layer did not exercise result stalls");
            errors = errors + 1;
        end

        if ((errors == 0) && (frames_checked == 4))
            $display("PASS tb_gsu_layer frames=%0d", frames_checked);
        else
            $fatal(1, "FAIL tb_gsu_layer errors=%0d frames=%0d",
                   errors, frames_checked);
        $finish;
    end
endmodule
