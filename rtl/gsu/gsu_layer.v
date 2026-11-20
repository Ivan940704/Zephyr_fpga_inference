`timescale 1ns/1ps

// Stateful shared-weight GSU layer with LANES output neurons per tile.
//
// This module implements one integer GSU time step:
//   shared input/recurrent MACs -> two gate requantizers -> sigmoid LUT ->
//   recurrent cell-state update -> folded-BN requantizer -> binary spike.
//
// The Zephyr checkpoint uses shared_weights=true, so forget and cell gates use
// the same MAC accumulators while retaining independent bias/requantization.
// Weight and parameter storage remain external through ready/valid interfaces;
// a later memory.v may map those requests to BRAM tiles or PS DDR DMA buffers.
module gsu_layer #(
    parameter INPUT_SIZE = 64,
    parameter HIDDEN_SIZE = 320,
    parameter LANES = 16,
    parameter INPUT_IS_BINARY = 0,
    parameter INPUT_INDEX_WIDTH = 6,
    parameter HIDDEN_INDEX_WIDTH = 9,
    parameter TILE_WIDTH = 5,
    parameter WEIGHT_INDEX_WIDTH = 9,
    parameter GATE_DENOMINATOR = 255,
    parameter GUARD_BITS = 8
) (
    input  wire                              clk,
    input  wire                              rst,
    input  wire                              clear_state,
    input  wire                              start,

    input  wire                              input_valid,
    output wire                              input_ready,
    input  wire signed [7:0]                 input_data,

    output wire                              weight_req_valid,
    input  wire                              weight_req_ready,
    output wire                              weight_matrix,
    output wire [TILE_WIDTH-1:0]             weight_tile,
    output wire [WEIGHT_INDEX_WIDTH-1:0]     weight_index,
    input  wire                              weight_rsp_valid,
    output wire                              weight_rsp_ready,
    input  wire [LANES*8-1:0]                weight_rsp_data,

    output wire                              param_req_valid,
    input  wire                              param_req_ready,
    output wire [TILE_WIDTH-1:0]             param_tile,
    input  wire                              param_rsp_valid,
    output wire                              param_rsp_ready,

    input  wire [LANES*32-1:0]               forget_input_multiplier,
    input  wire [LANES*6-1:0]                forget_input_shift,
    input  wire [LANES*32-1:0]               forget_recurrent_multiplier,
    input  wire [LANES*6-1:0]                forget_recurrent_shift,
    input  wire [LANES*32-1:0]               forget_bias_q,

    input  wire [LANES*32-1:0]               cell_input_multiplier,
    input  wire [LANES*6-1:0]                cell_input_shift,
    input  wire [LANES*32-1:0]               cell_recurrent_multiplier,
    input  wire [LANES*6-1:0]                cell_recurrent_shift,
    input  wire [LANES*32-1:0]               cell_bias_q,

    input  wire [LANES*32-1:0]               previous_multiplier,
    input  wire [LANES*6-1:0]                previous_shift,
    input  wire [LANES*32-1:0]               cellgate_multiplier,
    input  wire [LANES*6-1:0]                cellgate_shift,
    input  wire [LANES*32-1:0]               bn_multiplier,
    input  wire [LANES*6-1:0]                bn_shift,
    input  wire [LANES*32-1:0]               bn_bias_q,

    input  wire                              sigmoid_cfg_we,
    input  wire [7:0]                        sigmoid_cfg_addr,
    input  wire [7:0]                        sigmoid_cfg_data,

    output wire                              result_valid,
    input  wire                              result_ready,
    output wire [TILE_WIDTH-1:0]             result_tile,
    output wire                              result_last,
    output wire [LANES-1:0]                  result_spike_data,
    output wire [LANES*8-1:0]                result_state_data,
    output wire [LANES*8-1:0]                result_forget_data,
    output wire [LANES*8-1:0]                result_cellgate_data,
    output wire [LANES-1:0]                  result_forget_clipped,
    output wire [LANES-1:0]                  result_cellgate_clipped,
    output wire [LANES-1:0]                  result_state_pre_clipped,
    output wire [LANES-1:0]                  result_state_clipped,

    output wire [HIDDEN_INDEX_WIDTH:0]       recurrent_active_count,
    output reg  [31:0]                       input_weight_read_count,
    output reg  [31:0]                       recurrent_weight_read_count,
    output reg  [31:0]                       parameter_read_count,
    output wire                              busy,
    output wire                              done
);
    localparam ROW_TILES = HIDDEN_SIZE / LANES;
    localparam [TILE_WIDTH-1:0] LAST_TILE = ROW_TILES - 1;

    localparam [3:0] STATE_IDLE          = 4'd0;
    localparam [3:0] STATE_LOAD_INPUT    = 4'd1;
    localparam [3:0] STATE_INDEX_START   = 4'd2;
    localparam [3:0] STATE_INDEX         = 4'd3;
    localparam [3:0] STATE_PREP_TILE     = 4'd4;
    localparam [3:0] STATE_SCAN_INPUT    = 4'd5;
    localparam [3:0] STATE_ISSUE_INPUT   = 4'd6;
    localparam [3:0] STATE_WAIT_INPUT    = 4'd7;
    localparam [3:0] STATE_PREP_REC      = 4'd8;
    localparam [3:0] STATE_ISSUE_REC     = 4'd9;
    localparam [3:0] STATE_WAIT_REC      = 4'd10;
    localparam [3:0] STATE_ISSUE_PARAM   = 4'd11;
    localparam [3:0] STATE_WAIT_PARAM    = 4'd12;
    localparam [3:0] STATE_OUTPUT        = 4'd13;
    localparam [3:0] STATE_DONE          = 4'd14;

    reg [3:0] state;
    reg signed [7:0] input_buffer [0:INPUT_SIZE-1];
    reg signed [7:0] state_memory [0:HIDDEN_SIZE-1];
    reg [HIDDEN_SIZE-1:0] hx_vector;
    reg [HIDDEN_INDEX_WIDTH-1:0] index_buffer [0:HIDDEN_SIZE-1];
    reg [HIDDEN_INDEX_WIDTH:0] index_write_count;
    reg [HIDDEN_INDEX_WIDTH:0] active_total;
    reg [HIDDEN_INDEX_WIDTH:0] active_position;
    reg [INPUT_INDEX_WIDTH-1:0] input_position;
    reg [TILE_WIDTH-1:0] tile_position;

    reg [LANES-1:0] result_spike_reg;
    reg [LANES*8-1:0] result_state_reg;
    reg [LANES*8-1:0] result_forget_reg;
    reg [LANES*8-1:0] result_cellgate_reg;
    reg [LANES-1:0] result_forget_clipped_reg;
    reg [LANES-1:0] result_cellgate_clipped_reg;
    reg [LANES-1:0] result_state_pre_clipped_reg;
    reg [LANES-1:0] result_state_clipped_reg;

    wire index_start;
    wire index_valid;
    wire index_ready;
    wire [HIDDEN_INDEX_WIDTH-1:0] index_value;
    wire [HIDDEN_INDEX_WIDTH:0] encoded_active_count;
    wire index_busy;
    wire index_done;

    wire pe_clear;
    wire input_pe_enable;
    wire recurrent_pe_enable;
    wire [LANES*32-1:0] input_accumulators;
    wire [LANES*32-1:0] recurrent_accumulators;
    wire [LANES*8-1:0] computed_forget_data;
    wire [LANES*8-1:0] computed_cellgate_data;
    wire [LANES*8-1:0] computed_state_data;
    wire [LANES-1:0] computed_spike_data;
    wire [LANES-1:0] computed_forget_clipped;
    wire [LANES-1:0] computed_cellgate_clipped;
    wire [LANES-1:0] computed_state_pre_clipped;
    wire [LANES-1:0] computed_state_clipped;

    assign input_ready = (state == STATE_LOAD_INPUT);
    assign index_start = (state == STATE_INDEX_START);
    assign index_ready = (state == STATE_INDEX);

    assign weight_req_valid = (state == STATE_ISSUE_INPUT) ||
                              (state == STATE_ISSUE_REC);
    assign weight_matrix = (state == STATE_ISSUE_REC) ||
                           (state == STATE_WAIT_REC);
    assign weight_tile = tile_position;
    assign weight_index = weight_matrix
                        ? index_buffer[active_position[HIDDEN_INDEX_WIDTH-1:0]]
                        : input_position;
    assign weight_rsp_ready = (state == STATE_WAIT_INPUT) ||
                              (state == STATE_WAIT_REC);

    assign param_req_valid = (state == STATE_ISSUE_PARAM);
    assign param_tile = tile_position;
    assign param_rsp_ready = (state == STATE_WAIT_PARAM);

    assign result_valid = (state == STATE_OUTPUT);
    assign result_tile = tile_position;
    assign result_last = (tile_position == LAST_TILE);
    assign result_spike_data = result_spike_reg;
    assign result_state_data = result_state_reg;
    assign result_forget_data = result_forget_reg;
    assign result_cellgate_data = result_cellgate_reg;
    assign result_forget_clipped = result_forget_clipped_reg;
    assign result_cellgate_clipped = result_cellgate_clipped_reg;
    assign result_state_pre_clipped = result_state_pre_clipped_reg;
    assign result_state_clipped = result_state_clipped_reg;

    assign recurrent_active_count = active_total;
    assign busy = (state != STATE_IDLE) && (state != STATE_DONE);
    assign done = (state == STATE_DONE);

    assign pe_clear = (state == STATE_PREP_TILE);
    assign input_pe_enable = (state == STATE_WAIT_INPUT) &&
                             weight_rsp_valid && weight_rsp_ready;
    assign recurrent_pe_enable = (state == STATE_WAIT_REC) &&
                                 weight_rsp_valid && weight_rsp_ready;

    spike_indexer #(
        .VECTOR_WIDTH(HIDDEN_SIZE),
        .INDEX_WIDTH(HIDDEN_INDEX_WIDTH)
    ) recurrent_index_encoder (
        .clk(clk),
        .rst(rst || clear_state),
        .start(index_start),
        .spike_vector(hx_vector),
        .index_valid(index_valid),
        .index_ready(index_ready),
        .index_value(index_value),
        .active_count(encoded_active_count),
        .busy(index_busy),
        .done(index_done)
    );

    genvar lane;
    generate
        for (lane = 0; lane < LANES; lane = lane + 1) begin : gsu_lanes
            localparam integer LANE_BASE = lane * 8;
            wire signed [7:0] lane_weight;
            wire signed [31:0] lane_input_acc;
            wire signed [31:0] lane_recurrent_acc;
            wire signed [7:0] lane_forget_q;
            wire signed [7:0] lane_cellgate_q;
            wire [7:0] lane_forget_u8;
            wire signed [7:0] lane_previous_state;
            wire signed [7:0] lane_state_pre_q;
            wire signed [7:0] lane_state_q;
            wire lane_spike_q;
            wire lane_forget_clipped;
            wire lane_cellgate_clipped;
            wire lane_state_pre_clipped;
            wire lane_state_clipped;

            assign lane_weight = weight_rsp_data[LANE_BASE +: 8];
            assign lane_previous_state =
                state_memory[tile_position * LANES + lane];
            assign input_accumulators[lane*32 +: 32] = lane_input_acc;
            assign recurrent_accumulators[lane*32 +: 32] = lane_recurrent_acc;
            assign computed_forget_data[LANE_BASE +: 8] = lane_forget_q;
            assign computed_cellgate_data[LANE_BASE +: 8] = lane_cellgate_q;
            assign computed_state_data[LANE_BASE +: 8] = lane_state_q;
            assign computed_spike_data[lane] = lane_spike_q;
            assign computed_forget_clipped[lane] = lane_forget_clipped;
            assign computed_cellgate_clipped[lane] = lane_cellgate_clipped;
            assign computed_state_pre_clipped[lane] = lane_state_pre_clipped;
            assign computed_state_clipped[lane] = lane_state_clipped;

            hybrid_pe input_mac (
                .clk(clk),
                .rst(rst || clear_state),
                .clear_acc(pe_clear),
                .enable(input_pe_enable),
                .mode(INPUT_IS_BINARY ? 2'd1 : 2'd0),
                .operand_a(input_buffer[input_position]),
                .operand_b(lane_weight),
                .gate_u8(8'd0),
                .spike(1'b1),
                .accumulator(lane_input_acc)
            );

            hybrid_pe recurrent_mac (
                .clk(clk),
                .rst(rst || clear_state),
                .clear_acc(pe_clear),
                .enable(recurrent_pe_enable),
                .mode(2'd1),
                .operand_a(8'sd0),
                .operand_b(lane_weight),
                .gate_u8(8'd0),
                .spike(1'b1),
                .accumulator(lane_recurrent_acc)
            );

            gsu_gate_postprocess #(.GUARD_BITS(GUARD_BITS)) forget_gate (
                .input_acc(lane_input_acc),
                .recurrent_acc(lane_recurrent_acc),
                .input_multiplier(forget_input_multiplier[lane*32 +: 32]),
                .input_shift(forget_input_shift[lane*6 +: 6]),
                .recurrent_multiplier(forget_recurrent_multiplier[lane*32 +: 32]),
                .recurrent_shift(forget_recurrent_shift[lane*6 +: 6]),
                .bias_q(forget_bias_q[lane*32 +: 32]),
                .gate_q(lane_forget_q),
                .clipped(lane_forget_clipped)
            );

            gsu_gate_postprocess #(.GUARD_BITS(GUARD_BITS)) cell_gate (
                .input_acc(lane_input_acc),
                .recurrent_acc(lane_recurrent_acc),
                .input_multiplier(cell_input_multiplier[lane*32 +: 32]),
                .input_shift(cell_input_shift[lane*6 +: 6]),
                .recurrent_multiplier(cell_recurrent_multiplier[lane*32 +: 32]),
                .recurrent_shift(cell_recurrent_shift[lane*6 +: 6]),
                .bias_q(cell_bias_q[lane*32 +: 32]),
                .gate_q(lane_cellgate_q),
                .clipped(lane_cellgate_clipped)
            );

            sigmoid_lut lane_sigmoid (
                .clk(clk),
                .cfg_we(sigmoid_cfg_we),
                .cfg_addr(sigmoid_cfg_addr),
                .cfg_data(sigmoid_cfg_data),
                .input_q(lane_forget_q),
                .sigmoid_u8(lane_forget_u8)
            );

            gsu_state_update #(
                .GATE_DENOMINATOR(GATE_DENOMINATOR),
                .GUARD_BITS(GUARD_BITS)
            ) lane_state_update (
                .forget_u8(lane_forget_u8),
                .previous_state_q(lane_previous_state),
                .cellgate_q(lane_cellgate_q),
                .previous_multiplier(previous_multiplier[lane*32 +: 32]),
                .previous_shift(previous_shift[lane*6 +: 6]),
                .cellgate_multiplier(cellgate_multiplier[lane*32 +: 32]),
                .cellgate_shift(cellgate_shift[lane*6 +: 6]),
                .bn_multiplier(bn_multiplier[lane*32 +: 32]),
                .bn_shift(bn_shift[lane*6 +: 6]),
                .bn_bias_q(bn_bias_q[lane*32 +: 32]),
                .state_pre_q(lane_state_pre_q),
                .state_q(lane_state_q),
                .spike_q(lane_spike_q),
                .state_pre_clipped(lane_state_pre_clipped),
                .state_clipped(lane_state_clipped)
            );
        end
    endgenerate

    integer reset_index;
    integer update_lane;
    always @(posedge clk) begin
        if (rst || clear_state) begin
            state <= STATE_IDLE;
            hx_vector <= {HIDDEN_SIZE{1'b0}};
            index_write_count <= {(HIDDEN_INDEX_WIDTH+1){1'b0}};
            active_total <= {(HIDDEN_INDEX_WIDTH+1){1'b0}};
            active_position <= {(HIDDEN_INDEX_WIDTH+1){1'b0}};
            input_position <= {INPUT_INDEX_WIDTH{1'b0}};
            tile_position <= {TILE_WIDTH{1'b0}};
            result_spike_reg <= {LANES{1'b0}};
            result_state_reg <= {(LANES*8){1'b0}};
            result_forget_reg <= {(LANES*8){1'b0}};
            result_cellgate_reg <= {(LANES*8){1'b0}};
            result_forget_clipped_reg <= {LANES{1'b0}};
            result_cellgate_clipped_reg <= {LANES{1'b0}};
            result_state_pre_clipped_reg <= {LANES{1'b0}};
            result_state_clipped_reg <= {LANES{1'b0}};
            input_weight_read_count <= 32'd0;
            recurrent_weight_read_count <= 32'd0;
            parameter_read_count <= 32'd0;
            for (reset_index = 0; reset_index < HIDDEN_SIZE;
                 reset_index = reset_index + 1)
                state_memory[reset_index] <= 8'sd0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    if (start) begin
                        input_position <= {INPUT_INDEX_WIDTH{1'b0}};
                        tile_position <= {TILE_WIDTH{1'b0}};
                        index_write_count <= {(HIDDEN_INDEX_WIDTH+1){1'b0}};
                        active_total <= {(HIDDEN_INDEX_WIDTH+1){1'b0}};
                        input_weight_read_count <= 32'd0;
                        recurrent_weight_read_count <= 32'd0;
                        parameter_read_count <= 32'd0;
                        state <= STATE_LOAD_INPUT;
                    end
                end

                STATE_LOAD_INPUT: begin
                    if (input_valid && input_ready) begin
                        input_buffer[input_position] <= input_data;
                        if (input_position == INPUT_SIZE - 1) begin
                            input_position <= {INPUT_INDEX_WIDTH{1'b0}};
                            state <= STATE_INDEX_START;
                        end else begin
                            input_position <= input_position + 1'b1;
                        end
                    end
                end

                STATE_INDEX_START: begin
                    index_write_count <= {(HIDDEN_INDEX_WIDTH+1){1'b0}};
                    state <= STATE_INDEX;
                end

                STATE_INDEX: begin
                    if (index_valid && index_ready) begin
                        index_buffer[index_write_count[HIDDEN_INDEX_WIDTH-1:0]]
                            <= index_value;
                        index_write_count <= index_write_count + 1'b1;
                    end
                    if (index_done) begin
                        active_total <= index_write_count;
                        tile_position <= {TILE_WIDTH{1'b0}};
                        state <= STATE_PREP_TILE;
                    end
                end

                STATE_PREP_TILE: begin
                    input_position <= {INPUT_INDEX_WIDTH{1'b0}};
                    active_position <= {(HIDDEN_INDEX_WIDTH+1){1'b0}};
                    state <= STATE_SCAN_INPUT;
                end

                STATE_SCAN_INPUT: begin
                    if (INPUT_IS_BINARY &&
                        (input_buffer[input_position] == 8'sd0)) begin
                        if (input_position == INPUT_SIZE - 1) begin
                            state <= STATE_PREP_REC;
                        end else begin
                            input_position <= input_position + 1'b1;
                        end
                    end else begin
                        state <= STATE_ISSUE_INPUT;
                    end
                end

                STATE_ISSUE_INPUT: begin
                    if (weight_req_valid && weight_req_ready) begin
                        input_weight_read_count <= input_weight_read_count + 1'b1;
                        state <= STATE_WAIT_INPUT;
                    end
                end

                STATE_WAIT_INPUT: begin
                    if (weight_rsp_valid && weight_rsp_ready) begin
                        if (input_position == INPUT_SIZE - 1) begin
                            state <= STATE_PREP_REC;
                        end else begin
                            input_position <= input_position + 1'b1;
                            state <= STATE_SCAN_INPUT;
                        end
                    end
                end

                STATE_PREP_REC: begin
                    active_position <= {(HIDDEN_INDEX_WIDTH+1){1'b0}};
                    if (active_total == 0)
                        state <= STATE_ISSUE_PARAM;
                    else
                        state <= STATE_ISSUE_REC;
                end

                STATE_ISSUE_REC: begin
                    if (weight_req_valid && weight_req_ready) begin
                        recurrent_weight_read_count
                            <= recurrent_weight_read_count + 1'b1;
                        state <= STATE_WAIT_REC;
                    end
                end

                STATE_WAIT_REC: begin
                    if (weight_rsp_valid && weight_rsp_ready) begin
                        if (active_position + 1'b1 >= active_total) begin
                            state <= STATE_ISSUE_PARAM;
                        end else begin
                            active_position <= active_position + 1'b1;
                            state <= STATE_ISSUE_REC;
                        end
                    end
                end

                STATE_ISSUE_PARAM: begin
                    if (param_req_valid && param_req_ready) begin
                        parameter_read_count <= parameter_read_count + 1'b1;
                        state <= STATE_WAIT_PARAM;
                    end
                end

                STATE_WAIT_PARAM: begin
                    if (param_rsp_valid && param_rsp_ready) begin
                        result_spike_reg <= computed_spike_data;
                        result_state_reg <= computed_state_data;
                        result_forget_reg <= computed_forget_data;
                        result_cellgate_reg <= computed_cellgate_data;
                        result_forget_clipped_reg <= computed_forget_clipped;
                        result_cellgate_clipped_reg <= computed_cellgate_clipped;
                        result_state_pre_clipped_reg <= computed_state_pre_clipped;
                        result_state_clipped_reg <= computed_state_clipped;
                        for (update_lane = 0; update_lane < LANES;
                             update_lane = update_lane + 1) begin
                            state_memory[tile_position * LANES + update_lane]
                                <= computed_state_data[update_lane*8 +: 8];
                            hx_vector[tile_position * LANES + update_lane]
                                <= computed_spike_data[update_lane];
                        end
                        state <= STATE_OUTPUT;
                    end
                end

                STATE_OUTPUT: begin
                    if (result_valid && result_ready) begin
                        if (tile_position == LAST_TILE) begin
                            state <= STATE_DONE;
                        end else begin
                            tile_position <= tile_position + 1'b1;
                            state <= STATE_PREP_TILE;
                        end
                    end
                end

                STATE_DONE: state <= STATE_IDLE;

                default: state <= STATE_IDLE;
            endcase
        end
    end
endmodule
