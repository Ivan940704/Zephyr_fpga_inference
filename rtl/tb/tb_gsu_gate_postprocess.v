`timescale 1ns/1ps

module tb_gsu_gate_postprocess;
    reg signed [31:0] input_acc;
    reg signed [31:0] recurrent_acc;
    reg signed [31:0] input_multiplier;
    reg [5:0] input_shift;
    reg signed [31:0] recurrent_multiplier;
    reg [5:0] recurrent_shift;
    reg signed [31:0] bias_q;
    wire signed [7:0] gate_q;
    wire clipped;
    integer errors;

    gsu_gate_postprocess dut (
        .input_acc(input_acc), .recurrent_acc(recurrent_acc),
        .input_multiplier(input_multiplier), .input_shift(input_shift),
        .recurrent_multiplier(recurrent_multiplier), .recurrent_shift(recurrent_shift),
        .bias_q(bias_q), .gate_q(gate_q), .clipped(clipped)
    );

    task check;
        input signed [31:0] in_acc;
        input signed [31:0] rec_acc;
        input signed [31:0] bias;
        input signed [7:0] expected;
        input expected_clipped;
        begin
            input_acc = in_acc; recurrent_acc = rec_acc; bias_q = bias;
            #1;
            if ((gate_q !== expected) || (clipped !== expected_clipped)) begin
                $display("ERROR gate_post got=%0d/%0d expected=%0d/%0d",
                         gate_q, clipped, expected, expected_clipped);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        input_multiplier = 32'sd1073741824; input_shift = 6'd30;
        recurrent_multiplier = 32'sd1073741824; recurrent_shift = 6'd30;
        check(32'sd2560, -32'sd512, 32'sd256, 8'sd9, 1'b0);
        check(-32'sd384, 32'sd0, 32'sd0, -8'sd2, 1'b0);
        check(32'sd40000, 32'sd0, 32'sd0, 8'sd127, 1'b1);
        if (errors == 0) $display("PASS tb_gsu_gate_postprocess");
        else $fatal(1, "FAIL tb_gsu_gate_postprocess errors=%0d", errors);
        $finish;
    end
endmodule
