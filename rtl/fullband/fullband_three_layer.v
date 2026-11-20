`timescale 1ns/1ps

// Sequential fullband path:
//   dense GSU layer 1 -> binary GSU layer 2 -> binary linear projection.
//
// The three engines share one external packed weight/parameter interface.  A
// layer identifier lets memory.v select the corresponding tensor region while
// the two GSU instances retain independent recurrent hx/cx state.
module fullband_three_layer #(
    parameter L1_INPUT_SIZE = 64,
    parameter HIDDEN_SIZE = 320,
    parameter PROJECTION_SIZE = 64,
    parameter LANES = 16,
    parameter L1_INPUT_INDEX_WIDTH = 6,
    parameter INDEX_WIDTH = 9,
    parameter TILE_WIDTH = 5,
    parameter GATE_DENOMINATOR = 255,
    parameter GUARD_BITS = 8
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         clear_state,
    input  wire                         start,

    input  wire                         input_valid,
    output wire                         input_ready,
    input  wire signed [7:0]            input_data,

    output wire                         weight_req_valid,
    input  wire                         weight_req_ready,
    output wire [1:0]                   weight_layer,
    output wire                         weight_matrix,
    output wire [TILE_WIDTH-1:0]        weight_tile,
    output wire [INDEX_WIDTH-1:0]       weight_index,
    input  wire                         weight_rsp_valid,
    output wire                         weight_rsp_ready,
    input  wire [LANES*8-1:0]           weight_rsp_data,

    output wire                         param_req_valid,
    input  wire                         param_req_ready,
    output wire [1:0]                   param_layer,
    output wire [TILE_WIDTH-1:0]        param_tile,
    input  wire                         param_rsp_valid,
    output wire                         param_rsp_ready,

    input  wire [LANES*32-1:0]          forget_input_multiplier,
    input  wire [LANES*6-1:0]           forget_input_shift,
    input  wire [LANES*32-1:0]          forget_recurrent_multiplier,
    input  wire [LANES*6-1:0]           forget_recurrent_shift,
    input  wire [LANES*32-1:0]          forget_bias_q,
    input  wire [LANES*32-1:0]          cell_input_multiplier,
    input  wire [LANES*6-1:0]           cell_input_shift,
    input  wire [LANES*32-1:0]          cell_recurrent_multiplier,
    input  wire [LANES*6-1:0]           cell_recurrent_shift,
    input  wire [LANES*32-1:0]          cell_bias_q,
    input  wire [LANES*32-1:0]          previous_multiplier,
    input  wire [LANES*6-1:0]           previous_shift,
    input  wire [LANES*32-1:0]          cellgate_multiplier,
    input  wire [LANES*6-1:0]           cellgate_shift,
    input  wire [LANES*32-1:0]          bn_multiplier,
    input  wire [LANES*6-1:0]           bn_shift,
    input  wire [LANES*32-1:0]          bn_bias_q,
    input  wire [LANES*32-1:0]          linear_multiplier,
    input  wire [LANES*6-1:0]           linear_shift,
    input  wire [LANES*32-1:0]          linear_bias_q,

    input  wire                         sigmoid_cfg_we,
    input  wire                         sigmoid_cfg_layer,
    input  wire [7:0]                   sigmoid_cfg_addr,
    input  wire [7:0]                   sigmoid_cfg_data,

    output wire                         result_valid,
    input  wire                         result_ready,
    output wire [TILE_WIDTH-1:0]        result_tile,
    output wire                         result_last,
    output wire [LANES*8-1:0]           result_data,
    output wire [LANES-1:0]             result_clipped,

    output wire [HIDDEN_SIZE-1:0]       layer1_spike_vector,
    output wire [HIDDEN_SIZE-1:0]       layer2_spike_vector,
    output wire [INDEX_WIDTH:0]         layer1_recurrent_active,
    output wire [INDEX_WIDTH:0]         layer2_recurrent_active,
    output wire [INDEX_WIDTH:0]         projection_active,
    output wire [31:0]                  layer1_input_reads,
    output wire [31:0]                  layer1_recurrent_reads,
    output wire [31:0]                  layer2_input_reads,
    output wire [31:0]                  layer2_recurrent_reads,
    output wire [31:0]                  projection_weight_reads,
    output wire [3:0]                   phase,
    output wire                         busy,
    output wire                         done
);
    localparam [1:0] LAYER_1 = 2'd0;
    localparam [1:0] LAYER_2 = 2'd1;
    localparam [1:0] LAYER_PROJECTION = 2'd2;

    localparam [3:0] STATE_IDLE       = 4'd0;
    localparam [3:0] STATE_RUN_L1     = 4'd1;
    localparam [3:0] STATE_START_L2   = 4'd2;
    localparam [3:0] STATE_FEED_L2    = 4'd3;
    localparam [3:0] STATE_RUN_L2     = 4'd4;
    localparam [3:0] STATE_START_PROJ = 4'd5;
    localparam [3:0] STATE_FEED_PROJ  = 4'd6;
    localparam [3:0] STATE_RUN_PROJ   = 4'd7;
    localparam [3:0] STATE_DONE       = 4'd8;

    reg [3:0] state;
    reg [HIDDEN_SIZE-1:0] layer1_spikes;
    reg [HIDDEN_SIZE-1:0] layer2_spikes;
    reg [INDEX_WIDTH-1:0] feed_position;

    wire l1_start;
    wire l1_input_ready;
    wire l1_weight_req_valid;
    wire l1_weight_req_ready;
    wire l1_weight_matrix;
    wire [TILE_WIDTH-1:0] l1_weight_tile;
    wire [INDEX_WIDTH-1:0] l1_weight_index;
    wire l1_weight_rsp_valid;
    wire l1_weight_rsp_ready;
    wire l1_param_req_valid;
    wire l1_param_req_ready;
    wire [TILE_WIDTH-1:0] l1_param_tile;
    wire l1_param_rsp_valid;
    wire l1_param_rsp_ready;
    wire l1_result_valid;
    wire l1_result_ready;
    wire [TILE_WIDTH-1:0] l1_result_tile;
    wire [LANES-1:0] l1_result_spikes;
    wire l1_busy;
    wire l1_done;

    wire l2_start;
    wire l2_input_valid;
    wire l2_input_ready;
    wire signed [7:0] l2_input_data;
    wire l2_weight_req_valid;
    wire l2_weight_req_ready;
    wire l2_weight_matrix;
    wire [TILE_WIDTH-1:0] l2_weight_tile;
    wire [INDEX_WIDTH-1:0] l2_weight_index;
    wire l2_weight_rsp_valid;
    wire l2_weight_rsp_ready;
    wire l2_param_req_valid;
    wire l2_param_req_ready;
    wire [TILE_WIDTH-1:0] l2_param_tile;
    wire l2_param_rsp_valid;
    wire l2_param_rsp_ready;
    wire l2_result_valid;
    wire l2_result_ready;
    wire [TILE_WIDTH-1:0] l2_result_tile;
    wire [LANES-1:0] l2_result_spikes;
    wire l2_busy;
    wire l2_done;

    wire projection_start;
    wire projection_input_valid;
    wire projection_input_ready;
    wire projection_weight_req_valid;
    wire projection_weight_req_ready;
    wire [INDEX_WIDTH-1:0] projection_weight_column;
    wire [TILE_WIDTH-1:0] projection_weight_tile;
    wire projection_weight_rsp_valid;
    wire projection_weight_rsp_ready;
    wire projection_param_req_valid;
    wire projection_param_req_ready;
    wire [TILE_WIDTH-1:0] projection_param_tile;
    wire projection_param_rsp_valid;
    wire projection_param_rsp_ready;
    wire projection_result_valid;
    wire projection_result_ready;
    wire projection_busy;
    wire projection_done;

    wire active_l1;
    wire active_l2;
    wire active_projection;

    assign phase = state;
    assign busy = (state != STATE_IDLE) && (state != STATE_DONE);
    assign done = (state == STATE_DONE);
    assign layer1_spike_vector = layer1_spikes;
    assign layer2_spike_vector = layer2_spikes;

    assign l1_start = (state == STATE_IDLE) && start;
    assign input_ready = (state == STATE_RUN_L1) && l1_input_ready;
    assign l1_result_ready = (state == STATE_RUN_L1);

    assign l2_start = (state == STATE_START_L2);
    assign l2_input_valid = (state == STATE_FEED_L2);
    assign l2_input_data = layer1_spikes[feed_position] ? 8'sd1 : 8'sd0;
    assign l2_result_ready = (state == STATE_RUN_L2);

    assign projection_start = (state == STATE_START_PROJ);
    assign projection_input_valid = (state == STATE_FEED_PROJ);

    assign result_valid = (state == STATE_RUN_PROJ) && projection_result_valid;
    assign projection_result_ready = (state == STATE_RUN_PROJ) && result_ready;

    assign active_l1 = (state == STATE_RUN_L1);
    assign active_l2 = (state == STATE_START_L2) ||
                       (state == STATE_FEED_L2) ||
                       (state == STATE_RUN_L2);
    assign active_projection = (state == STATE_START_PROJ) ||
                               (state == STATE_FEED_PROJ) ||
                               (state == STATE_RUN_PROJ);

    assign weight_req_valid = active_l1 ? l1_weight_req_valid :
                              active_l2 ? l2_weight_req_valid :
                              active_projection ? projection_weight_req_valid : 1'b0;
    assign weight_layer = active_l1 ? LAYER_1 :
                          active_l2 ? LAYER_2 : LAYER_PROJECTION;
    assign weight_matrix = active_l1 ? l1_weight_matrix :
                           active_l2 ? l2_weight_matrix : 1'b0;
    assign weight_tile = active_l1 ? l1_weight_tile :
                         active_l2 ? l2_weight_tile : projection_weight_tile;
    assign weight_index = active_l1 ? l1_weight_index :
                          active_l2 ? l2_weight_index : projection_weight_column;
    assign weight_rsp_ready = active_l1 ? l1_weight_rsp_ready :
                              active_l2 ? l2_weight_rsp_ready :
                              active_projection ? projection_weight_rsp_ready : 1'b0;

    assign l1_weight_req_ready = active_l1 && weight_req_ready;
    assign l2_weight_req_ready = active_l2 && weight_req_ready;
    assign projection_weight_req_ready = active_projection && weight_req_ready;
    assign l1_weight_rsp_valid = active_l1 && weight_rsp_valid;
    assign l2_weight_rsp_valid = active_l2 && weight_rsp_valid;
    assign projection_weight_rsp_valid = active_projection && weight_rsp_valid;

    assign param_req_valid = active_l1 ? l1_param_req_valid :
                             active_l2 ? l2_param_req_valid :
                             active_projection ? projection_param_req_valid : 1'b0;
    assign param_layer = active_l1 ? LAYER_1 :
                         active_l2 ? LAYER_2 : LAYER_PROJECTION;
    assign param_tile = active_l1 ? l1_param_tile :
                        active_l2 ? l2_param_tile : projection_param_tile;
    assign param_rsp_ready = active_l1 ? l1_param_rsp_ready :
                             active_l2 ? l2_param_rsp_ready :
                             active_projection ? projection_param_rsp_ready : 1'b0;

    assign l1_param_req_ready = active_l1 && param_req_ready;
    assign l2_param_req_ready = active_l2 && param_req_ready;
    assign projection_param_req_ready = active_projection && param_req_ready;
    assign l1_param_rsp_valid = active_l1 && param_rsp_valid;
    assign l2_param_rsp_valid = active_l2 && param_rsp_valid;
    assign projection_param_rsp_valid = active_projection && param_rsp_valid;

    gsu_layer #(
        .INPUT_SIZE(L1_INPUT_SIZE),
        .HIDDEN_SIZE(HIDDEN_SIZE),
        .LANES(LANES),
        .INPUT_IS_BINARY(0),
        .INPUT_INDEX_WIDTH(L1_INPUT_INDEX_WIDTH),
        .HIDDEN_INDEX_WIDTH(INDEX_WIDTH),
        .TILE_WIDTH(TILE_WIDTH),
        .WEIGHT_INDEX_WIDTH(INDEX_WIDTH),
        .GATE_DENOMINATOR(GATE_DENOMINATOR),
        .GUARD_BITS(GUARD_BITS)
    ) fullband_layer1 (
        .clk(clk), .rst(rst), .clear_state(clear_state), .start(l1_start),
        .input_valid(input_valid && (state == STATE_RUN_L1)),
        .input_ready(l1_input_ready), .input_data(input_data),
        .weight_req_valid(l1_weight_req_valid),
        .weight_req_ready(l1_weight_req_ready),
        .weight_matrix(l1_weight_matrix), .weight_tile(l1_weight_tile),
        .weight_index(l1_weight_index),
        .weight_rsp_valid(l1_weight_rsp_valid),
        .weight_rsp_ready(l1_weight_rsp_ready), .weight_rsp_data(weight_rsp_data),
        .param_req_valid(l1_param_req_valid), .param_req_ready(l1_param_req_ready),
        .param_tile(l1_param_tile), .param_rsp_valid(l1_param_rsp_valid),
        .param_rsp_ready(l1_param_rsp_ready),
        .forget_input_multiplier(forget_input_multiplier),
        .forget_input_shift(forget_input_shift),
        .forget_recurrent_multiplier(forget_recurrent_multiplier),
        .forget_recurrent_shift(forget_recurrent_shift),
        .forget_bias_q(forget_bias_q),
        .cell_input_multiplier(cell_input_multiplier),
        .cell_input_shift(cell_input_shift),
        .cell_recurrent_multiplier(cell_recurrent_multiplier),
        .cell_recurrent_shift(cell_recurrent_shift), .cell_bias_q(cell_bias_q),
        .previous_multiplier(previous_multiplier), .previous_shift(previous_shift),
        .cellgate_multiplier(cellgate_multiplier), .cellgate_shift(cellgate_shift),
        .bn_multiplier(bn_multiplier), .bn_shift(bn_shift), .bn_bias_q(bn_bias_q),
        .sigmoid_cfg_we(sigmoid_cfg_we && !sigmoid_cfg_layer),
        .sigmoid_cfg_addr(sigmoid_cfg_addr), .sigmoid_cfg_data(sigmoid_cfg_data),
        .result_valid(l1_result_valid), .result_ready(l1_result_ready),
        .result_tile(l1_result_tile), .result_last(),
        .result_spike_data(l1_result_spikes), .result_state_data(),
        .result_forget_data(), .result_cellgate_data(),
        .result_forget_clipped(), .result_cellgate_clipped(),
        .result_state_pre_clipped(), .result_state_clipped(),
        .recurrent_active_count(layer1_recurrent_active),
        .input_weight_read_count(layer1_input_reads),
        .recurrent_weight_read_count(layer1_recurrent_reads),
        .parameter_read_count(), .busy(l1_busy), .done(l1_done)
    );

    gsu_layer #(
        .INPUT_SIZE(HIDDEN_SIZE),
        .HIDDEN_SIZE(HIDDEN_SIZE),
        .LANES(LANES),
        .INPUT_IS_BINARY(1),
        .INPUT_INDEX_WIDTH(INDEX_WIDTH),
        .HIDDEN_INDEX_WIDTH(INDEX_WIDTH),
        .TILE_WIDTH(TILE_WIDTH),
        .WEIGHT_INDEX_WIDTH(INDEX_WIDTH),
        .GATE_DENOMINATOR(GATE_DENOMINATOR),
        .GUARD_BITS(GUARD_BITS)
    ) fullband_layer2 (
        .clk(clk), .rst(rst), .clear_state(clear_state), .start(l2_start),
        .input_valid(l2_input_valid), .input_ready(l2_input_ready),
        .input_data(l2_input_data),
        .weight_req_valid(l2_weight_req_valid),
        .weight_req_ready(l2_weight_req_ready),
        .weight_matrix(l2_weight_matrix), .weight_tile(l2_weight_tile),
        .weight_index(l2_weight_index),
        .weight_rsp_valid(l2_weight_rsp_valid),
        .weight_rsp_ready(l2_weight_rsp_ready), .weight_rsp_data(weight_rsp_data),
        .param_req_valid(l2_param_req_valid), .param_req_ready(l2_param_req_ready),
        .param_tile(l2_param_tile), .param_rsp_valid(l2_param_rsp_valid),
        .param_rsp_ready(l2_param_rsp_ready),
        .forget_input_multiplier(forget_input_multiplier),
        .forget_input_shift(forget_input_shift),
        .forget_recurrent_multiplier(forget_recurrent_multiplier),
        .forget_recurrent_shift(forget_recurrent_shift),
        .forget_bias_q(forget_bias_q),
        .cell_input_multiplier(cell_input_multiplier),
        .cell_input_shift(cell_input_shift),
        .cell_recurrent_multiplier(cell_recurrent_multiplier),
        .cell_recurrent_shift(cell_recurrent_shift), .cell_bias_q(cell_bias_q),
        .previous_multiplier(previous_multiplier), .previous_shift(previous_shift),
        .cellgate_multiplier(cellgate_multiplier), .cellgate_shift(cellgate_shift),
        .bn_multiplier(bn_multiplier), .bn_shift(bn_shift), .bn_bias_q(bn_bias_q),
        .sigmoid_cfg_we(sigmoid_cfg_we && sigmoid_cfg_layer),
        .sigmoid_cfg_addr(sigmoid_cfg_addr), .sigmoid_cfg_data(sigmoid_cfg_data),
        .result_valid(l2_result_valid), .result_ready(l2_result_ready),
        .result_tile(l2_result_tile), .result_last(),
        .result_spike_data(l2_result_spikes), .result_state_data(),
        .result_forget_data(), .result_cellgate_data(),
        .result_forget_clipped(), .result_cellgate_clipped(),
        .result_state_pre_clipped(), .result_state_clipped(),
        .recurrent_active_count(layer2_recurrent_active),
        .input_weight_read_count(layer2_input_reads),
        .recurrent_weight_read_count(layer2_recurrent_reads),
        .parameter_read_count(), .busy(l2_busy), .done(l2_done)
    );

    linear_projection #(
        .INPUT_SIZE(HIDDEN_SIZE),
        .OUTPUT_SIZE(PROJECTION_SIZE),
        .LANES(LANES),
        .INPUT_INDEX_WIDTH(INDEX_WIDTH),
        .TILE_WIDTH(TILE_WIDTH),
        .GUARD_BITS(GUARD_BITS)
    ) fullband_projection (
        .clk(clk), .rst(rst || clear_state), .start(projection_start),
        .input_valid(projection_input_valid),
        .input_ready(projection_input_ready),
        .input_spike(layer2_spikes[feed_position]),
        .weight_req_valid(projection_weight_req_valid),
        .weight_req_ready(projection_weight_req_ready),
        .weight_column(projection_weight_column),
        .weight_tile(projection_weight_tile),
        .weight_rsp_valid(projection_weight_rsp_valid),
        .weight_rsp_ready(projection_weight_rsp_ready),
        .weight_rsp_data(weight_rsp_data),
        .param_req_valid(projection_param_req_valid),
        .param_req_ready(projection_param_req_ready),
        .param_tile(projection_param_tile),
        .param_rsp_valid(projection_param_rsp_valid),
        .param_rsp_ready(projection_param_rsp_ready),
        .output_multiplier(linear_multiplier), .output_shift(linear_shift),
        .output_bias_q(linear_bias_q),
        .result_valid(projection_result_valid),
        .result_ready(projection_result_ready),
        .result_tile(result_tile), .result_last(result_last),
        .result_data(result_data), .result_clipped(result_clipped),
        .active_count(projection_active),
        .weight_read_count(projection_weight_reads),
        .parameter_read_count(), .busy(projection_busy), .done(projection_done)
    );

    integer lane;
    always @(posedge clk) begin
        if (rst || clear_state) begin
            state <= STATE_IDLE;
            layer1_spikes <= {HIDDEN_SIZE{1'b0}};
            layer2_spikes <= {HIDDEN_SIZE{1'b0}};
            feed_position <= {INDEX_WIDTH{1'b0}};
        end else begin
            if (l1_result_valid && l1_result_ready)
                layer1_spikes[l1_result_tile * LANES +: LANES]
                    <= l1_result_spikes;
            if (l2_result_valid && l2_result_ready)
                layer2_spikes[l2_result_tile * LANES +: LANES]
                    <= l2_result_spikes;

            case (state)
                STATE_IDLE: begin
                    if (start) begin
                        layer1_spikes <= {HIDDEN_SIZE{1'b0}};
                        layer2_spikes <= {HIDDEN_SIZE{1'b0}};
                        feed_position <= {INDEX_WIDTH{1'b0}};
                        state <= STATE_RUN_L1;
                    end
                end

                STATE_RUN_L1: begin
                    if (l1_done) begin
                        feed_position <= {INDEX_WIDTH{1'b0}};
                        state <= STATE_START_L2;
                    end
                end

                STATE_START_L2: state <= STATE_FEED_L2;

                STATE_FEED_L2: begin
                    if (l2_input_valid && l2_input_ready) begin
                        if (feed_position == HIDDEN_SIZE - 1) begin
                            feed_position <= {INDEX_WIDTH{1'b0}};
                            state <= STATE_RUN_L2;
                        end else begin
                            feed_position <= feed_position + 1'b1;
                        end
                    end
                end

                STATE_RUN_L2: begin
                    if (l2_done) begin
                        feed_position <= {INDEX_WIDTH{1'b0}};
                        state <= STATE_START_PROJ;
                    end
                end

                STATE_START_PROJ: state <= STATE_FEED_PROJ;

                STATE_FEED_PROJ: begin
                    if (projection_input_valid && projection_input_ready) begin
                        if (feed_position == HIDDEN_SIZE - 1) begin
                            feed_position <= {INDEX_WIDTH{1'b0}};
                            state <= STATE_RUN_PROJ;
                        end else begin
                            feed_position <= feed_position + 1'b1;
                        end
                    end
                end

                STATE_RUN_PROJ: begin
                    if (projection_done)
                        state <= STATE_DONE;
                end

                STATE_DONE: state <= STATE_IDLE;

                default: state <= STATE_IDLE;
            endcase
        end
    end
endmodule
