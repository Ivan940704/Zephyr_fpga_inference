`timescale 1ns/1ps

module pe_shared_requant_engine #(
    parameter integer INDEX_WIDTH = 9,
    parameter integer TAG_WIDTH = 8
) (
    input wire clk, input wire rst_n,
    input wire in_valid, output wire in_ready,
    input wire op_linear,
    input wire signed [31:0] value_in,
    input wire signed [31:0] multiplier_in,
    input wire [5:0] right_shift_in,
    input wire signed [31:0] bias_in,
    input wire [5:0] guard_shift_in,
    input wire [INDEX_WIDTH-1:0] index_in,
    input wire [TAG_WIDTH-1:0] tag_in,
    input wire last_in,
    output wire out_valid, input wire out_ready,
    output reg signed [7:0] value_out,
    output wire [INDEX_WIDTH-1:0] index_out,
    output wire [TAG_WIDTH-1:0] tag_out,
    output wire last_out, output reg clipped_out,
    output wire op_linear_out
);
    localparam integer META_WIDTH = 1+INDEX_WIDTH+TAG_WIDTH+1+32+6;
    wire [META_WIDTH-1:0] meta_in = {op_linear,index_in,tag_in,last_in,bias_in,guard_shift_in};
    wire [META_WIDTH-1:0] meta_out;
    wire signed [63:0] rq_value;
    wire signed [31:0] bias_meta = meta_out[37:6];
    wire [5:0] guard_meta = meta_out[5:0];
    reg signed [64:0] biased;
    reg signed [64:0] rounded;
    reg signed [64:0] shifted;
    reg [64:0] magnitude;

    pe_requant_lane #(.TAG_WIDTH(META_WIDTH)) u_lane (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_ready(in_ready),
        .value_in(value_in), .multiplier_in(multiplier_in), .shift_in(right_shift_in),
        .tag_in(meta_in), .out_valid(out_valid), .out_ready(out_ready),
        .value_out(rq_value), .tag_out(meta_out)
    );

    assign last_out = meta_out[38];
    assign tag_out = meta_out[38+TAG_WIDTH:39];
    assign index_out = meta_out[38+TAG_WIDTH+INDEX_WIDTH:39+TAG_WIDTH];
    assign op_linear_out = meta_out[META_WIDTH-1];

    always @* begin
        biased = $signed({rq_value[63],rq_value}) + $signed({{33{bias_meta[31]}},bias_meta});
        magnitude = biased[64] ? (~biased + 65'd1) : biased;
        rounded = $signed(magnitude + ((guard_meta == 0) ? 65'd0 : (65'd1 << (guard_meta-1))));
        shifted = rounded >>> guard_meta;
        if (biased[64]) shifted = -shifted;
        clipped_out = (shifted > 65'sd127) || (shifted < -65'sd127);
        if (shifted > 65'sd127) value_out = 8'sd127;
        else if (shifted < -65'sd127) value_out = -8'sd127;
        else value_out = shifted[7:0];
    end
endmodule
