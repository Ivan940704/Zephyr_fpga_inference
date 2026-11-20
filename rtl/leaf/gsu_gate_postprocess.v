`timescale 1ns/1ps

// Converts input/recurrent INT32 accumulators into one INT8 GSU gate value.
module gsu_gate_postprocess #(
    parameter GUARD_BITS = 8
) (
    input  wire signed [31:0] input_acc,
    input  wire signed [31:0] recurrent_acc,
    input  wire signed [31:0] input_multiplier,
    input  wire        [5:0]  input_shift,
    input  wire signed [31:0] recurrent_multiplier,
    input  wire        [5:0]  recurrent_shift,
    input  wire signed [31:0] bias_q,
    output wire signed [7:0]  gate_q,
    output wire               clipped
);
    wire signed [63:0] input_requant;
    wire signed [63:0] recurrent_requant;
    wire signed [63:0] bias_extended;
    wire signed [63:0] guarded_sum;
    wire signed [63:0] shifted_sum;
    localparam [5:0] GUARD_SHIFT = GUARD_BITS;

    assign bias_extended = {{32{bias_q[31]}}, bias_q};
    assign guarded_sum = input_requant + recurrent_requant + bias_extended;

    integer_requantizer input_rq (
        .value_in(input_acc),
        .multiplier(input_multiplier),
        .right_shift(input_shift),
        .value_out(input_requant)
    );

    integer_requantizer recurrent_rq (
        .value_in(recurrent_acc),
        .multiplier(recurrent_multiplier),
        .right_shift(recurrent_shift),
        .value_out(recurrent_requant)
    );

    signed_round_shift #(
        .WIDTH(64),
        .SHIFT_WIDTH(6)
    ) guard_shift (
        .value_in(guarded_sum),
        .shift(GUARD_SHIFT),
        .value_out(shifted_sum)
    );

    saturate_int8 #(.INPUT_WIDTH(64)) saturate_gate (
        .value_in(shifted_sum),
        .value_out(gate_q),
        .clipped(clipped)
    );
endmodule
