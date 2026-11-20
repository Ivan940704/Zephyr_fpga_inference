`timescale 1ns/1ps

// Requantizes one INT32 linear-layer accumulator, adds guarded INT32 bias,
// applies the common guard shift, and saturates to symmetric INT8.
module linear_postprocess #(
    parameter GUARD_BITS = 8
) (
    input  wire signed [31:0] accumulator,
    input  wire signed [31:0] multiplier,
    input  wire        [5:0]  right_shift,
    input  wire signed [31:0] bias_q,
    output wire signed [7:0]  output_q,
    output wire               clipped
);
    wire signed [63:0] requantized;
    wire signed [63:0] bias_extended;
    wire signed [63:0] guarded_sum;
    wire signed [63:0] output_unclamped;
    localparam [5:0] GUARD_SHIFT = GUARD_BITS;

    assign bias_extended = {{32{bias_q[31]}}, bias_q};
    assign guarded_sum = requantized + bias_extended;

    integer_requantizer output_requantizer (
        .value_in(accumulator),
        .multiplier(multiplier),
        .right_shift(right_shift),
        .value_out(requantized)
    );

    signed_round_shift #(.WIDTH(64), .SHIFT_WIDTH(6)) output_guard_shift (
        .value_in(guarded_sum),
        .shift(GUARD_SHIFT),
        .value_out(output_unclamped)
    );

    saturate_int8 #(.INPUT_WIDTH(64)) output_saturator (
        .value_in(output_unclamped),
        .value_out(output_q),
        .clipped(clipped)
    );
endmodule
