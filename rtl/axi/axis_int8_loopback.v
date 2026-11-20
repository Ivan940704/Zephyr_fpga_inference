`timescale 1ns/1ps

// Wiring proof for a PS/DMA-like AXI stream crossing a native byte-oriented
// processing boundary and returning to AXI stream.
module axis_int8_loopback #(
    parameter AXIS_DATA_WIDTH = 64,
    parameter AXIS_KEEP_WIDTH = AXIS_DATA_WIDTH / 8
) (
    input  wire                         aclk,
    input  wire                         aresetn,

    input  wire [AXIS_DATA_WIDTH-1:0]   s_axis_tdata,
    input  wire [AXIS_KEEP_WIDTH-1:0]   s_axis_tkeep,
    input  wire                         s_axis_tvalid,
    output wire                         s_axis_tready,
    input  wire                         s_axis_tlast,

    output wire [AXIS_DATA_WIDTH-1:0]   m_axis_tdata,
    output wire [AXIS_KEEP_WIDTH-1:0]   m_axis_tkeep,
    output wire                         m_axis_tvalid,
    input  wire                         m_axis_tready,
    output wire                         m_axis_tlast,

    output wire                         protocol_error
);
    wire              native_valid;
    wire              native_ready;
    wire signed [7:0] native_data;
    wire              native_last;

    axis_int8_ingress #(
        .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH),
        .AXIS_KEEP_WIDTH(AXIS_KEEP_WIDTH)
    ) ingress (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .native_valid(native_valid),
        .native_ready(native_ready),
        .native_data(native_data),
        .native_last(native_last),
        .protocol_error(protocol_error)
    );

    axis_int8_egress #(
        .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH),
        .AXIS_KEEP_WIDTH(AXIS_KEEP_WIDTH)
    ) egress (
        .aclk(aclk),
        .aresetn(aresetn),
        .native_valid(native_valid),
        .native_ready(native_ready),
        .native_data(native_data),
        .native_last(native_last),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast)
    );
endmodule

