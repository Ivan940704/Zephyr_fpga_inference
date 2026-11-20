`timescale 1ns/1ps

// Arithmetic integration shell. Memory/AXI and the global FSM remain external.
module pe_array_top (
    input wire clk, input wire rst_n,
    input wire start, input wire phase_done,
    output wire [3:0] state, output wire phase_start,
    output wire busy, output wire done,
    input wire mac_clear, input wire mac_issue, input wire [1:0] mac_mode,
    input wire [16*8-1:0] operand_a,
    input wire [16*8-1:0] operand_b,
    input wire [16*8-1:0] gate_u8,
    input wire [15:0] spike_enable,
    input wire [16*32-1:0] direct_value,
    output wire [16*32-1:0] accumulators,
    output wire [15:0] overflow
);
    pe_array_controller u_controller(
      .clk(clk),.rst_n(rst_n),.start(start),.phase_done(phase_done),
      .state(state),.phase_start(phase_start),.busy(busy),.done(done));
    genvar lane;
    generate for(lane=0;lane<16;lane=lane+1) begin: g_mac
      pe_hybrid_mac u_mac(
        .clk(clk),.rst_n(rst_n),.acc_clear(mac_clear),.acc_enable(mac_issue),
        .mode(mac_mode),.operand_a(operand_a[lane*8 +: 8]),
        .operand_b(operand_b[lane*8 +: 8]),.gate_u8(gate_u8[lane*8 +: 8]),
        .spike_enable(spike_enable[lane]),
        .direct_value(direct_value[lane*32 +: 32]),
        .accumulator(accumulators[lane*32 +: 32]),.overflow(overflow[lane]));
    end endgenerate
endmodule
