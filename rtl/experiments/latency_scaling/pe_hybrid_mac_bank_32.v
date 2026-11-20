`timescale 1ns/1ps

// Feasibility-only 32-lane arithmetic bank.  The frozen 16-PE production
// datapath remains unchanged; this wrapper measures lane scaling in isolation.
module pe_hybrid_mac_bank_32 (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 acc_clear,
    input  wire                 acc_enable,
    input  wire         [1:0]   mode,
    input  wire         [255:0] operand_a,
    input  wire         [255:0] operand_b,
    input  wire         [255:0] gate_u8,
    input  wire         [31:0]  spike_enable,
    input  wire         [1023:0] direct_value,
    output wire         [1023:0] accumulator,
    output wire         [31:0]  overflow
);

    genvar lane;
    generate
        for (lane = 0; lane < 32; lane = lane + 1) begin : gen_hybrid_pe
            pe_hybrid_mac u_hybrid_mac (
                .clk(clk),
                .rst_n(rst_n),
                .acc_clear(acc_clear),
                .acc_enable(acc_enable),
                .mode(mode),
                .operand_a(operand_a[lane * 8 +: 8]),
                .operand_b(operand_b[lane * 8 +: 8]),
                .gate_u8(gate_u8[lane * 8 +: 8]),
                .spike_enable(spike_enable[lane]),
                .direct_value(direct_value[lane * 32 +: 32]),
                .accumulator(accumulator[lane * 32 +: 32]),
                .overflow(overflow[lane])
            );
        end
    endgenerate

endmodule
