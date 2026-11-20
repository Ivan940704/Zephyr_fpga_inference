`timescale 1ns/1ps
module pe_active_index_writer #(parameter integer INDEX_WIDTH=9) (
    input wire in_valid, output wire in_ready,
    input wire [INDEX_WIDTH-1:0] index_in, input wire spike_in, input wire last_in,
    output wire buffer_valid, input wire buffer_ready,
    output wire [INDEX_WIDTH-1:0] buffer_index, output wire frame_finalize
);
    assign in_ready=spike_in ? buffer_ready : 1'b1;
    assign buffer_valid=in_valid & spike_in;
    assign buffer_index=index_in; assign frame_finalize=in_valid & in_ready & last_in;
endmodule
