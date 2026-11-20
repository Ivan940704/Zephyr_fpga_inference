`timescale 1ns/1ps

// Binary-input INT8 linear projection with indexed-column weight reads.
// Default dimensions match the fullband 320 -> 64 projection.
module linear_projection #(
    parameter INPUT_SIZE = 320,
    parameter OUTPUT_SIZE = 64,
    parameter LANES = 16,
    parameter INPUT_INDEX_WIDTH = 9,
    parameter TILE_WIDTH = 2,
    parameter GUARD_BITS = 8
) (
    input  wire                          clk,
    input  wire                          rst,
    input  wire                          start,

    input  wire                          input_valid,
    output wire                          input_ready,
    input  wire                          input_spike,

    output wire                          weight_req_valid,
    input  wire                          weight_req_ready,
    output wire [INPUT_INDEX_WIDTH-1:0]  weight_column,
    output wire [TILE_WIDTH-1:0]         weight_tile,
    input  wire                          weight_rsp_valid,
    output wire                          weight_rsp_ready,
    input  wire [LANES*8-1:0]            weight_rsp_data,

    output wire                          param_req_valid,
    input  wire                          param_req_ready,
    output wire [TILE_WIDTH-1:0]         param_tile,
    input  wire                          param_rsp_valid,
    output wire                          param_rsp_ready,
    input  wire [LANES*32-1:0]           output_multiplier,
    input  wire [LANES*6-1:0]            output_shift,
    input  wire [LANES*32-1:0]           output_bias_q,

    output wire                          result_valid,
    input  wire                          result_ready,
    output wire [TILE_WIDTH-1:0]         result_tile,
    output wire                          result_last,
    output wire [LANES*8-1:0]            result_data,
    output wire [LANES-1:0]              result_clipped,

    output wire [INPUT_INDEX_WIDTH:0]    active_count,
    output wire [31:0]                   weight_read_count,
    output reg  [31:0]                   parameter_read_count,
    output wire                          busy,
    output wire                          done
);
    localparam ROW_TILES = OUTPUT_SIZE / LANES;
    localparam [TILE_WIDTH-1:0] LAST_TILE = ROW_TILES - 1;

    localparam [3:0] STATE_IDLE        = 4'd0;
    localparam [3:0] STATE_LOAD_INPUT  = 4'd1;
    localparam [3:0] STATE_START_MAC   = 4'd2;
    localparam [3:0] STATE_WAIT_MAC    = 4'd3;
    localparam [3:0] STATE_ISSUE_PARAM = 4'd4;
    localparam [3:0] STATE_WAIT_PARAM  = 4'd5;
    localparam [3:0] STATE_OUTPUT      = 4'd6;
    localparam [3:0] STATE_DONE        = 4'd7;

    reg [3:0] state;
    reg [INPUT_SIZE-1:0] spike_vector;
    reg [INPUT_INDEX_WIDTH-1:0] input_position;
    reg [TILE_WIDTH-1:0] captured_tile;
    reg [LANES*32-1:0] captured_accumulators;
    reg [LANES*8-1:0] result_data_reg;
    reg [LANES-1:0] result_clipped_reg;

    wire matvec_start;
    wire matvec_result_valid;
    wire matvec_result_ready;
    wire [TILE_WIDTH-1:0] matvec_result_tile;
    wire [LANES*32-1:0] matvec_result_data;
    wire matvec_busy;
    wire matvec_done;
    wire [LANES*8-1:0] computed_result_data;
    wire [LANES-1:0] computed_result_clipped;

    assign input_ready = (state == STATE_LOAD_INPUT);
    assign matvec_start = (state == STATE_START_MAC);
    assign matvec_result_ready = (state == STATE_WAIT_MAC);
    assign param_req_valid = (state == STATE_ISSUE_PARAM);
    assign param_tile = captured_tile;
    assign param_rsp_ready = (state == STATE_WAIT_PARAM);
    assign result_valid = (state == STATE_OUTPUT);
    assign result_tile = captured_tile;
    assign result_last = (captured_tile == LAST_TILE);
    assign result_data = result_data_reg;
    assign result_clipped = result_clipped_reg;
    assign busy = (state != STATE_IDLE) && (state != STATE_DONE);
    assign done = (state == STATE_DONE);

    sparsity_aware_matvec #(
        .COLUMNS(INPUT_SIZE),
        .ROWS(OUTPUT_SIZE),
        .LANES(LANES),
        .INDEX_WIDTH(INPUT_INDEX_WIDTH),
        .TILE_WIDTH(TILE_WIDTH)
    ) sparse_binary_mac (
        .clk(clk),
        .rst(rst),
        .start(matvec_start),
        .spike_vector(spike_vector),
        .weight_req_valid(weight_req_valid),
        .weight_req_ready(weight_req_ready),
        .weight_column(weight_column),
        .weight_tile(weight_tile),
        .weight_rsp_valid(weight_rsp_valid),
        .weight_rsp_ready(weight_rsp_ready),
        .weight_rsp_data(weight_rsp_data),
        .result_valid(matvec_result_valid),
        .result_ready(matvec_result_ready),
        .result_tile(matvec_result_tile),
        .result_data(matvec_result_data),
        .active_count(active_count),
        .memory_read_count(weight_read_count),
        .busy(matvec_busy),
        .done(matvec_done)
    );

    genvar lane;
    generate
        for (lane = 0; lane < LANES; lane = lane + 1) begin : projection_lanes
            wire signed [7:0] lane_output;
            wire lane_clipped;

            assign computed_result_data[lane*8 +: 8] = lane_output;
            assign computed_result_clipped[lane] = lane_clipped;

            linear_postprocess #(.GUARD_BITS(GUARD_BITS)) lane_postprocess (
                .accumulator(captured_accumulators[lane*32 +: 32]),
                .multiplier(output_multiplier[lane*32 +: 32]),
                .right_shift(output_shift[lane*6 +: 6]),
                .bias_q(output_bias_q[lane*32 +: 32]),
                .output_q(lane_output),
                .clipped(lane_clipped)
            );
        end
    endgenerate

    always @(posedge clk) begin
        if (rst) begin
            state <= STATE_IDLE;
            spike_vector <= {INPUT_SIZE{1'b0}};
            input_position <= {INPUT_INDEX_WIDTH{1'b0}};
            captured_tile <= {TILE_WIDTH{1'b0}};
            captured_accumulators <= {(LANES*32){1'b0}};
            result_data_reg <= {(LANES*8){1'b0}};
            result_clipped_reg <= {LANES{1'b0}};
            parameter_read_count <= 32'd0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    if (start) begin
                        spike_vector <= {INPUT_SIZE{1'b0}};
                        input_position <= {INPUT_INDEX_WIDTH{1'b0}};
                        parameter_read_count <= 32'd0;
                        state <= STATE_LOAD_INPUT;
                    end
                end

                STATE_LOAD_INPUT: begin
                    if (input_valid && input_ready) begin
                        spike_vector[input_position] <= input_spike;
                        if (input_position == INPUT_SIZE - 1) begin
                            input_position <= {INPUT_INDEX_WIDTH{1'b0}};
                            state <= STATE_START_MAC;
                        end else begin
                            input_position <= input_position + 1'b1;
                        end
                    end
                end

                STATE_START_MAC: state <= STATE_WAIT_MAC;

                STATE_WAIT_MAC: begin
                    if (matvec_result_valid && matvec_result_ready) begin
                        captured_tile <= matvec_result_tile;
                        captured_accumulators <= matvec_result_data;
                        state <= STATE_ISSUE_PARAM;
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
                        result_data_reg <= computed_result_data;
                        result_clipped_reg <= computed_result_clipped;
                        state <= STATE_OUTPUT;
                    end
                end

                STATE_OUTPUT: begin
                    if (result_valid && result_ready) begin
                        if (captured_tile == LAST_TILE)
                            state <= STATE_DONE;
                        else
                            state <= STATE_WAIT_MAC;
                    end
                end

                STATE_DONE: state <= STATE_IDLE;

                default: state <= STATE_IDLE;
            endcase
        end
    end
endmodule
