`timescale 1ns/1ps

module tb_linear_postprocess;
    reg signed [31:0] accumulator;
    reg signed [31:0] multiplier;
    reg [5:0] right_shift;
    reg signed [31:0] bias_q;
    wire signed [7:0] output_q;
    wire clipped;
    integer errors;

    linear_postprocess dut (
        .accumulator(accumulator),
        .multiplier(multiplier),
        .right_shift(right_shift),
        .bias_q(bias_q),
        .output_q(output_q),
        .clipped(clipped)
    );

    task check;
        input signed [31:0] acc;
        input signed [31:0] mult;
        input [5:0] shift;
        input signed [31:0] bias;
        input signed [7:0] expected;
        input expected_clipped;
        begin
            accumulator = acc;
            multiplier = mult;
            right_shift = shift;
            bias_q = bias;
            #1;
            if ((output_q !== expected) || (clipped !== expected_clipped)) begin
                $display("ERROR linear_postprocess got=%0d/%0d expected=%0d/%0d",
                         output_q, clipped, expected, expected_clipped);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        check(32'sd25, 32'sd1073741824, 6'd22, 32'sd256, 8'sd26, 1'b0);
        check(-32'sd25, 32'sd1073741824, 6'd22, -32'sd256, -8'sd26, 1'b0);
        check(32'sd3, 32'sd1073741824, 6'd23, 32'sd0, 8'sd2, 1'b0);
        check(32'sd400, 32'sd1073741824, 6'd22, 32'sd0, 8'sd127, 1'b1);
        check(-32'sd400, 32'sd1073741824, 6'd22, 32'sd0, -8'sd127, 1'b1);
        if (errors == 0) $display("PASS tb_linear_postprocess");
        else $fatal(1, "FAIL tb_linear_postprocess errors=%0d", errors);
        $finish;
    end
endmodule
