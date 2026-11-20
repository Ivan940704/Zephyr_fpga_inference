`timescale 1ns/1ps

// Four synchronized bit-exact IntegerRequantizer lanes.
//
// A bank transaction always traverses all four physical lanes.  in_lane_valid
// marks which slots carry useful work; inactive slots are forced to arithmetic
// zero.  The mask bit is carried as one extra bit in each lane's opaque tag, so
// valid/mask/tag/data remain aligned through stalls without a second pipeline.
//
// The bank intentionally contains no parameter RAM, bias, guard shift,
// saturation, QBN, sigmoid, or membrane control.
module pe_local_requant_bank_4lane #(
    parameter integer TAG_WIDTH = 16
) (
    input  wire                          clk,
    input  wire                          rst_n,

    input  wire                          in_valid,
    output wire                          in_ready,
    input  wire [3:0]                    in_lane_valid,
    input  wire [4*32-1:0]               value_in,
    input  wire [4*32-1:0]               multiplier_in,
    input  wire [4*6-1:0]                shift_in,
    input  wire [4*TAG_WIDTH-1:0]        tag_in,

    output wire                          out_valid,
    input  wire                          out_ready,
    output wire [3:0]                    out_lane_valid,
    output wire [4*64-1:0]               value_out,
    output wire [4*TAG_WIDTH-1:0]        tag_out
);

    localparam integer LANE_COUNT = 4;
    localparam integer LANE_TAG_WIDTH = TAG_WIDTH + 1;

    wire [LANE_COUNT-1:0] lane_in_ready;
    wire [LANE_COUNT-1:0] lane_out_valid;
    wire [LANE_COUNT*64-1:0] lane_value_out;
    wire [LANE_COUNT*LANE_TAG_WIDTH-1:0] lane_tag_out;

    assign in_ready = &lane_in_ready;
    assign out_valid = &lane_out_valid;

    genvar lane;
    generate
        for (lane = 0; lane < LANE_COUNT; lane = lane + 1) begin : gen_requant_lane
            wire signed [31:0] selected_value;
            wire signed [31:0] selected_multiplier;
            wire        [5:0]  selected_shift;
            wire [LANE_TAG_WIDTH-1:0] extended_tag;

            assign selected_value = in_lane_valid[lane]
                ? $signed(value_in[lane*32 +: 32])
                : 32'sd0;
            assign selected_multiplier = in_lane_valid[lane]
                ? $signed(multiplier_in[lane*32 +: 32])
                : 32'sd0;
            assign selected_shift = in_lane_valid[lane]
                ? shift_in[lane*6 +: 6]
                : 6'd0;
            assign extended_tag = {
                in_lane_valid[lane],
                tag_in[lane*TAG_WIDTH +: TAG_WIDTH]
            };

            pe_requant_lane #(
                .TAG_WIDTH(LANE_TAG_WIDTH)
            ) u_requant_lane (
                .clk(clk),
                .rst_n(rst_n),
                .in_valid(in_valid),
                .in_ready(lane_in_ready[lane]),
                .value_in(selected_value),
                .multiplier_in(selected_multiplier),
                .shift_in(selected_shift),
                .tag_in(extended_tag),
                .out_valid(lane_out_valid[lane]),
                .out_ready(out_ready),
                .value_out(lane_value_out[lane*64 +: 64]),
                .tag_out(lane_tag_out[lane*LANE_TAG_WIDTH +: LANE_TAG_WIDTH])
            );

            assign out_lane_valid[lane] =
                lane_tag_out[lane*LANE_TAG_WIDTH + TAG_WIDTH];
            assign value_out[lane*64 +: 64] =
                lane_value_out[lane*64 +: 64];
            assign tag_out[lane*TAG_WIDTH +: TAG_WIDTH] =
                lane_tag_out[lane*LANE_TAG_WIDTH +: TAG_WIDTH];
        end
    endgenerate

`ifndef SYNTHESIS
    initial begin
        if (TAG_WIDTH < 1) begin
            $fatal(1, "pe_local_requant_bank_4lane TAG_WIDTH must be at least one");
        end
    end

    // Every physical lane receives the same packet-valid and output-ready.
    // Any divergence therefore indicates a reset/connection implementation bug.
    always @(posedge clk) begin
        if (rst_n) begin
            if ((lane_in_ready !== {LANE_COUNT{lane_in_ready[0]}})
                || (lane_out_valid !== {LANE_COUNT{lane_out_valid[0]}})) begin
                $fatal(1, "pe_local_requant_bank_4lane lane synchronization lost");
            end
        end
    end
`endif

endmodule
