`timescale 1ns/1ps

module saturate_int8 #(
    parameter INPUT_WIDTH = 64
) (
    input  wire signed [INPUT_WIDTH-1:0] value_in,
    output reg  signed [7:0]             value_out,
    output reg                           clipped
);
    always @* begin
        clipped = 1'b0;
        if ($signed(value_in) > 127) begin
            value_out = 8'sd127;
            clipped = 1'b1;
        end else if ($signed(value_in) < -127) begin
            value_out = -8'sd127;
            clipped = 1'b1;
        end else begin
            value_out = value_in[7:0];
        end
    end
endmodule
