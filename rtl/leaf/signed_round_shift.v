`timescale 1ns/1ps

// Signed round-to-nearest right shift.
// This matches upstream integer_ptq.py: round(abs(x) + 2^(s-1)) >> s,
// then restore the original sign.
module signed_round_shift #(
    parameter WIDTH = 64,
    parameter SHIFT_WIDTH = 6
) (
    input  wire signed [WIDTH-1:0] value_in,
    input  wire        [SHIFT_WIDTH-1:0] shift,
    output reg  signed [WIDTH-1:0] value_out
);
    reg [WIDTH-1:0] magnitude;
    reg [WIDTH-1:0] rounding;
    reg [WIDTH-1:0] rounded_magnitude;

    always @* begin
        magnitude = value_in[WIDTH-1] ? (~value_in + {{(WIDTH-1){1'b0}}, 1'b1}) : value_in;
        rounding = {WIDTH{1'b0}};
        rounded_magnitude = {WIDTH{1'b0}};

        if (shift == 0) begin
            rounded_magnitude = magnitude;
        end else if (shift < WIDTH) begin
            rounding = {{(WIDTH-1){1'b0}}, 1'b1} << (shift - 1'b1);
            rounded_magnitude = (magnitude + rounding) >> shift;
        end

        value_out = value_in[WIDTH-1] ? -$signed(rounded_magnitude) : $signed(rounded_magnitude);
    end
endmodule
