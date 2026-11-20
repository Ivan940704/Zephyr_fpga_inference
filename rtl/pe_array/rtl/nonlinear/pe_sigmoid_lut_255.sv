`timescale 1ns/1ps

module pe_sigmoid_lut_255 (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              in_valid,
    output wire              in_ready,
    input  wire signed [7:0] gate_in,
    output reg               out_valid,
    input  wire              out_ready,
    output reg        [7:0]  lambda_out,
    input  wire              cfg_we,
    input  wire       [7:0]  cfg_addr,
    input  wire       [7:0]  cfg_data
);
    reg [7:0] lut [0:254];
    wire advance = ~out_valid | out_ready;
    wire [7:0] lookup_addr = (gate_in == -8'sd128)
        ? 8'd0 : ($signed(gate_in) + 9'sd127);

    assign in_ready = rst_n & advance;

    always @(posedge clk) begin
        if (cfg_we && cfg_addr < 8'd255)
            lut[cfg_addr] <= cfg_data;
        if (!rst_n) begin
            out_valid <= 1'b0;
            lambda_out <= 8'd0;
        end else if (advance) begin
            out_valid <= in_valid;
            if (in_valid)
                lambda_out <= lut[lookup_addr];
        end
    end
endmodule
