`timescale 1ns/1ps

// Configurable 255-entry LUT. Each GSU layer may load its own calibrated table.
module sigmoid_lut (
    input  wire              clk,
    input  wire              cfg_we,
    input  wire       [7:0]  cfg_addr,
    input  wire       [7:0]  cfg_data,
    input  wire signed [7:0] input_q,
    output wire       [7:0]  sigmoid_u8
);
    reg [7:0] lut [0:254];
    wire [8:0] lookup_addr;

    assign lookup_addr = $signed(input_q) + 9'sd127;
    assign sigmoid_u8 = lut[lookup_addr];

    always @(posedge clk) begin
        if (cfg_we && cfg_addr < 8'd255)
            lut[cfg_addr] <= cfg_data;
    end
endmodule
