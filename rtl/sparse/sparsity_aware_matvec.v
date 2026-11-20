`timescale 1ns/1ps

// Index-buffered binary-spike matrix-vector execution.
//
// The binary input vector is encoded into active column indices.  For every
// output-row tile, only those columns are requested from weight memory and
// accumulated by LANES hybrid PEs in spike mode.  Weight memory is expected to
// store one packed LANES-wide word for each {column, row_tile} address.
module sparsity_aware_matvec #(
    parameter COLUMNS = 320,
    parameter ROWS = 320,
    parameter LANES = 16,
    parameter INDEX_WIDTH = 9,
    parameter TILE_WIDTH = 5
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         start,
    input  wire [COLUMNS-1:0]           spike_vector,

    output wire                         weight_req_valid,
    input  wire                         weight_req_ready,
    output wire [INDEX_WIDTH-1:0]       weight_column,
    output wire [TILE_WIDTH-1:0]        weight_tile,
    input  wire                         weight_rsp_valid,
    output wire                         weight_rsp_ready,
    input  wire [LANES*8-1:0]           weight_rsp_data,

    output wire                         result_valid,
    input  wire                         result_ready,
    output wire [TILE_WIDTH-1:0]        result_tile,
    output wire [LANES*32-1:0]          result_data,

    output wire [INDEX_WIDTH:0]         active_count,
    output reg  [31:0]                  memory_read_count,
    output wire                         busy,
    output wire                         done
);
    localparam ROW_TILES = ROWS / LANES;
    localparam [TILE_WIDTH-1:0] LAST_TILE = ROW_TILES - 1;

    localparam [2:0] STATE_IDLE         = 3'd0;
    localparam [2:0] STATE_ENCODE       = 3'd1;
    localparam [2:0] STATE_PREP_TILE    = 3'd2;
    localparam [2:0] STATE_ISSUE_WEIGHT = 3'd3;
    localparam [2:0] STATE_WAIT_WEIGHT  = 3'd4;
    localparam [2:0] STATE_OUTPUT_TILE  = 3'd5;
    localparam [2:0] STATE_DONE         = 3'd6;

    reg [2:0] state;
    reg [INDEX_WIDTH-1:0] index_buffer [0:COLUMNS-1];
    reg [INDEX_WIDTH:0] index_write_count;
    reg [INDEX_WIDTH:0] active_total;
    reg [INDEX_WIDTH:0] active_position;
    reg [TILE_WIDTH-1:0] tile_position;

    wire index_start;
    wire index_valid;
    wire index_ready;
    wire [INDEX_WIDTH-1:0] index_value;
    wire [INDEX_WIDTH:0] encoded_active_count;
    wire index_busy;
    wire index_done;
    wire pe_clear;
    wire pe_enable;

    assign index_start = (state == STATE_IDLE) && start;
    assign index_ready = (state == STATE_ENCODE);
    assign weight_req_valid = (state == STATE_ISSUE_WEIGHT);
    assign weight_column = index_buffer[active_position[INDEX_WIDTH-1:0]];
    assign weight_tile = tile_position;
    assign weight_rsp_ready = (state == STATE_WAIT_WEIGHT);
    assign result_valid = (state == STATE_OUTPUT_TILE);
    assign result_tile = tile_position;
    assign active_count = active_total;
    assign busy = (state != STATE_IDLE) && (state != STATE_DONE);
    assign done = (state == STATE_DONE);
    assign pe_clear = (state == STATE_PREP_TILE);
    assign pe_enable = weight_rsp_valid && weight_rsp_ready;

    spike_indexer #(
        .VECTOR_WIDTH(COLUMNS),
        .INDEX_WIDTH(INDEX_WIDTH)
    ) active_index_encoder (
        .clk(clk),
        .rst(rst),
        .start(index_start),
        .spike_vector(spike_vector),
        .index_valid(index_valid),
        .index_ready(index_ready),
        .index_value(index_value),
        .active_count(encoded_active_count),
        .busy(index_busy),
        .done(index_done)
    );

    genvar lane;
    generate
        for (lane = 0; lane < LANES; lane = lane + 1) begin : pe_lanes
            wire signed [7:0] lane_weight;
            wire signed [31:0] lane_accumulator;

            assign lane_weight = weight_rsp_data[lane*8 +: 8];
            assign result_data[lane*32 +: 32] = lane_accumulator;

            hybrid_pe lane_pe (
                .clk(clk),
                .rst(rst),
                .clear_acc(pe_clear),
                .enable(pe_enable),
                .mode(2'd1),
                .operand_a(8'sd0),
                .operand_b(lane_weight),
                .gate_u8(8'd0),
                .spike(1'b1),
                .accumulator(lane_accumulator)
            );
        end
    endgenerate

    always @(posedge clk) begin
        if (rst) begin
            state <= STATE_IDLE;
            index_write_count <= {(INDEX_WIDTH+1){1'b0}};
            active_total <= {(INDEX_WIDTH+1){1'b0}};
            active_position <= {(INDEX_WIDTH+1){1'b0}};
            tile_position <= {TILE_WIDTH{1'b0}};
            memory_read_count <= 32'd0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    if (start) begin
                        index_write_count <= {(INDEX_WIDTH+1){1'b0}};
                        active_total <= {(INDEX_WIDTH+1){1'b0}};
                        active_position <= {(INDEX_WIDTH+1){1'b0}};
                        tile_position <= {TILE_WIDTH{1'b0}};
                        memory_read_count <= 32'd0;
                        state <= STATE_ENCODE;
                    end
                end

                STATE_ENCODE: begin
                    if (index_valid && index_ready) begin
                        index_buffer[index_write_count[INDEX_WIDTH-1:0]] <= index_value;
                        index_write_count <= index_write_count + 1'b1;
                    end
                    if (index_done) begin
                        active_total <= index_write_count;
                        tile_position <= {TILE_WIDTH{1'b0}};
                        state <= STATE_PREP_TILE;
                    end
                end

                STATE_PREP_TILE: begin
                    active_position <= {(INDEX_WIDTH+1){1'b0}};
                    if (active_total == 0)
                        state <= STATE_OUTPUT_TILE;
                    else
                        state <= STATE_ISSUE_WEIGHT;
                end

                STATE_ISSUE_WEIGHT: begin
                    if (weight_req_valid && weight_req_ready) begin
                        memory_read_count <= memory_read_count + 1'b1;
                        state <= STATE_WAIT_WEIGHT;
                    end
                end

                STATE_WAIT_WEIGHT: begin
                    if (weight_rsp_valid && weight_rsp_ready) begin
                        if (active_position + 1'b1 >= active_total) begin
                            state <= STATE_OUTPUT_TILE;
                        end else begin
                            active_position <= active_position + 1'b1;
                            state <= STATE_ISSUE_WEIGHT;
                        end
                    end
                end

                STATE_OUTPUT_TILE: begin
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
