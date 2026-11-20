`timescale 1ns/1ps
module pe_spike_decision #(parameter integer INDEX_WIDTH=9, TAG_WIDTH=8) (
    input wire in_valid, output wire in_ready,
    input wire signed [7:0] value_in,
    input wire [INDEX_WIDTH-1:0] index_in,
    input wire [TAG_WIDTH-1:0] tag_in, input wire last_in,
    output wire out_valid, input wire out_ready,
    output wire [INDEX_WIDTH-1:0] index_out,
    output wire [TAG_WIDTH-1:0] tag_out, output wire last_out,
    output wire spike_out
);
    assign spike_out = ($signed(value_in) >= 0);
    // A non-spiking final sample is still forwarded as an end-of-frame event.
    assign out_valid = in_valid & (spike_out | last_in);
    assign in_ready = (spike_out | last_in) ? out_ready : 1'b1;
    assign index_out=index_in; assign tag_out=tag_in; assign last_out=last_in;
endmodule
