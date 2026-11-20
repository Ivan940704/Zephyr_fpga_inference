`timescale 1ns/1ps

// One-deep, sixteen-lane tile serializer.
//
// lane_valid_in identifies structural neuron validity, not spike activity.
// Invalid lanes are skipped. Valid lanes are emitted exactly once in
// ascending lane order. load_last_in marks the tile containing the end of a
// logical vector; last_out is therefore asserted only on that tile's final
// valid neuron, never merely at the end of an intermediate tile.
//
// The module contains one tile register bank and one pending mask. It has no
// FIFO, fall-through reload path, arithmetic engine, or second output buffer.
module pe_output_serializer #(
    parameter integer VALUE_WIDTH = 32,
    parameter integer INDEX_WIDTH = 9,
    parameter integer TAG_WIDTH   = 16
) (
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         load_valid,
    output wire                         load_ready,
    input  wire [16*VALUE_WIDTH-1:0]    values_in,
    input  wire [15:0]                  lane_valid_in,
    input  wire [INDEX_WIDTH-1:0]       base_index_in,
    input  wire [16*TAG_WIDTH-1:0]      tags_in,
    input  wire                         load_last_in,

    output wire                         out_valid,
    input  wire                         out_ready,
    output wire signed [VALUE_WIDTH-1:0] value_out,
    output wire [INDEX_WIDTH-1:0]       index_out,
    output wire [TAG_WIDTH-1:0]         tag_out,
    output wire                         last_out,

    output wire                         busy,
    output reg                          done
);

    reg [16*VALUE_WIDTH-1:0] values_r;
    reg [15:0]               pending_r;
    reg [INDEX_WIDTH-1:0]    base_index_r;
    reg [16*TAG_WIDTH-1:0]   tags_r;
    reg                      load_last_r;
    reg [3:0]                last_lane_r;
    reg [3:0]                selected_lane_r;
    reg                      selected_valid_r;

    wire [15:0] pending_after_pop;
    wire [4:0]  load_selection;
    wire [4:0]  next_selection;
    wire [3:0]  load_last_lane;
    wire        load_fire;
    wire        out_fire;

    // The selected lane is registered control state, not a second data
    // buffer. Registering it separates the lowest-set-bit selector from the
    // 16:1 value/tag mux while retaining one output handshake per cycle.
    function [4:0] lowest_set_lane;
        input [15:0] mask;
        begin
            casez (mask)
                16'b???????????????1: lowest_set_lane = {1'b1, 4'd0};
                16'b??????????????10: lowest_set_lane = {1'b1, 4'd1};
                16'b?????????????100: lowest_set_lane = {1'b1, 4'd2};
                16'b????????????1000: lowest_set_lane = {1'b1, 4'd3};
                16'b???????????10000: lowest_set_lane = {1'b1, 4'd4};
                16'b??????????100000: lowest_set_lane = {1'b1, 4'd5};
                16'b?????????1000000: lowest_set_lane = {1'b1, 4'd6};
                16'b????????10000000: lowest_set_lane = {1'b1, 4'd7};
                16'b???????100000000: lowest_set_lane = {1'b1, 4'd8};
                16'b??????1000000000: lowest_set_lane = {1'b1, 4'd9};
                16'b?????10000000000: lowest_set_lane = {1'b1, 4'd10};
                16'b????100000000000: lowest_set_lane = {1'b1, 4'd11};
                16'b???1000000000000: lowest_set_lane = {1'b1, 4'd12};
                16'b??10000000000000: lowest_set_lane = {1'b1, 4'd13};
                16'b?100000000000000: lowest_set_lane = {1'b1, 4'd14};
                16'b1000000000000000: lowest_set_lane = {1'b1, 4'd15};
                default:              lowest_set_lane = 5'd0;
            endcase
        end
    endfunction

    // Capture the highest structural lane once per tile. This four-bit
    // metadata makes last_out a short registered-control comparison instead
    // of a pending-mask reduction on the output path.
    function [3:0] highest_set_lane;
        input [15:0] mask;
        begin
            casez (mask)
                16'b1???????????????: highest_set_lane = 4'd15;
                16'b01??????????????: highest_set_lane = 4'd14;
                16'b001?????????????: highest_set_lane = 4'd13;
                16'b0001????????????: highest_set_lane = 4'd12;
                16'b00001???????????: highest_set_lane = 4'd11;
                16'b000001??????????: highest_set_lane = 4'd10;
                16'b0000001?????????: highest_set_lane = 4'd9;
                16'b00000001????????: highest_set_lane = 4'd8;
                16'b000000001???????: highest_set_lane = 4'd7;
                16'b0000000001??????: highest_set_lane = 4'd6;
                16'b00000000001?????: highest_set_lane = 4'd5;
                16'b000000000001????: highest_set_lane = 4'd4;
                16'b0000000000001???: highest_set_lane = 4'd3;
                16'b00000000000001??: highest_set_lane = 4'd2;
                16'b000000000000001?: highest_set_lane = 4'd1;
                default:              highest_set_lane = 4'd0;
            endcase
        end
    endfunction

    // Clearing the lowest set bit is equivalent to clearing selected_lane,
    // but avoids feeding the priority-encoder result back into pending state.
    assign pending_after_pop = pending_r & (pending_r - 16'd1);
    assign load_selection = lowest_set_lane(lane_valid_in);
    assign next_selection = lowest_set_lane(pending_after_pop);
    assign load_last_lane = highest_set_lane(lane_valid_in);

    assign busy       = |pending_r;
    assign load_ready = rst_n && !busy;
    assign out_valid  = rst_n && selected_valid_r;

    assign value_out = values_r[
        selected_lane_r*VALUE_WIDTH +: VALUE_WIDTH
    ];
    assign index_out = base_index_r + selected_lane_r;
    assign tag_out = tags_r[
        selected_lane_r*TAG_WIDTH +: TAG_WIDTH
    ];
    assign last_out = out_valid && load_last_r
        && (selected_lane_r == last_lane_r);

    assign load_fire = load_valid && load_ready;
    assign out_fire  = out_valid && out_ready;

    always @(posedge clk) begin
        if (!rst_n) begin
            values_r     <= {16*VALUE_WIDTH{1'b0}};
            pending_r    <= 16'd0;
            base_index_r <= {INDEX_WIDTH{1'b0}};
            tags_r       <= {16*TAG_WIDTH{1'b0}};
            load_last_r  <= 1'b0;
            last_lane_r  <= 4'd0;
            selected_lane_r  <= 4'd0;
            selected_valid_r <= 1'b0;
            done         <= 1'b0;
        end else begin
            done <= 1'b0;

            if (load_fire) begin
                values_r     <= values_in;
                pending_r    <= lane_valid_in;
                base_index_r <= base_index_in;
                tags_r       <= tags_in;
                load_last_r  <= load_last_in;
                last_lane_r  <= load_last_lane;
                selected_lane_r  <= load_selection[3:0];
                selected_valid_r <= load_selection[4];

                // A non-final empty tile is a legal no-op transaction. A
                // logical-vector terminator must contain at least one lane.
                if (lane_valid_in == 16'd0) begin
                    done <= 1'b1;
                end
            end else if (out_fire) begin
                pending_r <= pending_after_pop;
                selected_lane_r  <= next_selection[3:0];
                selected_valid_r <= next_selection[4];
                if (selected_lane_r == last_lane_r) begin
                    done <= 1'b1;
                end
            end
        end
    end

endmodule
