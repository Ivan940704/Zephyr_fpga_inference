`timescale 1ns/1ps

// One complex INT8 x INT8 term per cycle, accumulated in signed INT32.
module deepfilter_complex_mac (
    input  wire               clk,
    input  wire               rst,
    input  wire               clear_acc,
    input  wire               term_valid,
    input  wire signed [7:0]  spectrum_real_q,
    input  wire signed [7:0]  spectrum_imag_q,
    input  wire signed [7:0]  coefficient_real_q,
    input  wire signed [7:0]  coefficient_imag_q,
    output reg  signed [31:0] real_acc,
    output reg  signed [31:0] imag_acc
);
    wire signed [15:0] rr;
    wire signed [15:0] ii;
    wire signed [15:0] ri;
    wire signed [15:0] ir;
    wire signed [31:0] real_term;
    wire signed [31:0] imag_term;

    assign rr = spectrum_real_q * coefficient_real_q;
    assign ii = spectrum_imag_q * coefficient_imag_q;
    assign ri = spectrum_real_q * coefficient_imag_q;
    assign ir = spectrum_imag_q * coefficient_real_q;
    assign real_term = {{16{rr[15]}}, rr} - {{16{ii[15]}}, ii};
    assign imag_term = {{16{ri[15]}}, ri} + {{16{ir[15]}}, ir};

    always @(posedge clk) begin
        if (rst || clear_acc) begin
            real_acc <= 32'sd0;
            imag_acc <= 32'sd0;
        end else if (term_valid) begin
            real_acc <= real_acc + real_term;
            imag_acc <= imag_acc + imag_term;
        end
    end
endmodule
