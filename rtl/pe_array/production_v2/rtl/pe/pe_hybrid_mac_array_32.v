`timescale 1ns/1ps

// Production-v2 structural 32-lane Hybrid MAC array checkpoint.
//
// Every command field is lane-local so RAW, GATE, MEMBRANE, and CDF owners
// can independently clear, issue, or idle each physical accumulator.  The
// arithmetic contract remains entirely inside the frozen pe_hybrid_mac leaf.
module pe_hybrid_mac_array_32 (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire [31:0]           acc_clear,
    input  wire [31:0]           acc_enable,
    input  wire [32*2-1:0]       mode,
    input  wire [32*8-1:0]       operand_a,
    input  wire [32*8-1:0]       operand_b,
    input  wire [32*8-1:0]       gate_u8,
    input  wire [31:0]           spike_enable,
    input  wire [32*32-1:0]      direct_value,
    output wire [32*32-1:0]      accumulator,
    output wire [31:0]           overflow
);

    genvar lane;
    generate
        for (lane = 0; lane < 32; lane = lane + 1) begin : gen_hybrid_pe
            (* keep_hierarchy = "yes" *) pe_hybrid_mac u_pe_hybrid_mac (
                .clk(clk),
                .rst_n(rst_n),
                .acc_clear(acc_clear[lane]),
                .acc_enable(acc_enable[lane]),
                .mode(mode[lane*2 +: 2]),
                .operand_a(operand_a[lane*8 +: 8]),
                .operand_b(operand_b[lane*8 +: 8]),
                .gate_u8(gate_u8[lane*8 +: 8]),
                .spike_enable(spike_enable[lane]),
                .direct_value(direct_value[lane*32 +: 32]),
                .accumulator(accumulator[lane*32 +: 32]),
                .overflow(overflow[lane])
            );
        end
    endgenerate

endmodule
