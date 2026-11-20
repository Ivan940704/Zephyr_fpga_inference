`timescale 1ns/1ps

// Per-channel integer multiplier/right-shift requantization primitive.
// Multipliers are stored as signed 32-bit values but are constrained to the
// signed 30-bit magnitude contract used by the Python reference.
module integer_requantizer (
    input  wire signed [31:0] value_in,
    input  wire signed [31:0] multiplier,
    input  wire        [5:0]  right_shift,
    output wire signed [63:0] value_out
);
    wire signed [63:0] product;

    assign product = value_in * multiplier;

    signed_round_shift #(
        .WIDTH(64),
        .SHIFT_WIDTH(6)
    ) round_product (
        .value_in(product),
        .shift(right_shift),
        .value_out(value_out)
    );
endmodule
