`timescale 1ns/1ps

module tb_deepfilter_complex_mac;
    reg clk = 1'b0;
    reg rst;
    reg clear_acc;
    reg term_valid;
    reg signed [7:0] spectrum_real_q;
    reg signed [7:0] spectrum_imag_q;
    reg signed [7:0] coefficient_real_q;
    reg signed [7:0] coefficient_imag_q;
    wire signed [31:0] real_acc;
    wire signed [31:0] imag_acc;
    integer errors;

    always #5 clk = ~clk;

    deepfilter_complex_mac dut (
        .clk(clk), .rst(rst), .clear_acc(clear_acc), .term_valid(term_valid),
        .spectrum_real_q(spectrum_real_q), .spectrum_imag_q(spectrum_imag_q),
        .coefficient_real_q(coefficient_real_q), .coefficient_imag_q(coefficient_imag_q),
        .real_acc(real_acc), .imag_acc(imag_acc)
    );

    task clear;
        begin
            @(negedge clk); clear_acc = 1'b1;
            @(posedge clk); #1; clear_acc = 1'b0;
        end
    endtask

    task add_term;
        input signed [7:0] sr;
        input signed [7:0] si;
        input signed [7:0] cr;
        input signed [7:0] ci;
        begin
            @(negedge clk);
            spectrum_real_q = sr; spectrum_imag_q = si;
            coefficient_real_q = cr; coefficient_imag_q = ci;
            term_valid = 1'b1;
            @(posedge clk); #1; term_valid = 1'b0;
        end
    endtask

    task check;
        input signed [31:0] expected_real;
        input signed [31:0] expected_imag;
        begin
            if ((real_acc !== expected_real) || (imag_acc !== expected_imag)) begin
                $display("ERROR deepfilter got=%0d+j%0d expected=%0d+j%0d",
                         real_acc, imag_acc, expected_real, expected_imag);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0; rst = 1; clear_acc = 0; term_valid = 0;
        spectrum_real_q = 0; spectrum_imag_q = 0; coefficient_real_q = 0; coefficient_imag_q = 0;
        repeat (2) @(posedge clk); @(negedge clk); rst = 0;

        clear(); add_term(8'sd3, 8'sd4, 8'sd5, -8'sd2); check(32'sd23, 32'sd14);
        add_term(-8'sd2, 8'sd1, 8'sd4, 8'sd3);
        add_term(8'sd7, -8'sd3, -8'sd1, 8'sd2); check(32'sd11, 32'sd29);
        add_term(-8'sd8, -8'sd7, 8'sd6, -8'sd5);
        add_term(8'sd127, -8'sd127, -8'sd127, 8'sd127); check(-32'sd72, 32'sd32285);

        if (errors == 0) $display("PASS tb_deepfilter_complex_mac");
        else $fatal(1, "FAIL tb_deepfilter_complex_mac errors=%0d", errors);
        $finish;
    end
endmodule
