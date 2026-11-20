`timescale 1ns/1ps

module tb_hybrid_pe;
    reg clk = 1'b0;
    reg rst;
    reg clear_acc;
    reg enable;
    reg [1:0] mode;
    reg signed [7:0] operand_a;
    reg signed [7:0] operand_b;
    reg [7:0] gate_u8;
    reg spike;
    wire signed [31:0] accumulator;
    integer errors;

    always #5 clk = ~clk;

    hybrid_pe dut (
        .clk(clk), .rst(rst), .clear_acc(clear_acc), .enable(enable),
        .mode(mode), .operand_a(operand_a), .operand_b(operand_b),
        .gate_u8(gate_u8), .spike(spike), .accumulator(accumulator)
    );

    task apply_term;
        input [1:0] term_mode;
        input signed [7:0] a;
        input signed [7:0] b;
        input [7:0] gate;
        input spk;
        begin
            @(negedge clk);
            mode = term_mode;
            operand_a = a;
            operand_b = b;
            gate_u8 = gate;
            spike = spk;
            enable = 1'b1;
            @(posedge clk);
            #1;
            enable = 1'b0;
        end
    endtask

    task expect_acc;
        input signed [31:0] expected;
        begin
            if (accumulator !== expected) begin
                $display("ERROR hybrid_pe got=%0d expected=%0d", accumulator, expected);
                errors = errors + 1;
            end
        end
    endtask

    task clear;
        begin
            @(negedge clk); clear_acc = 1'b1;
            @(posedge clk); #1; clear_acc = 1'b0;
        end
    endtask

    initial begin
        errors = 0;
        rst = 1'b1; clear_acc = 1'b0; enable = 1'b0;
        mode = 0; operand_a = 0; operand_b = 0; gate_u8 = 0; spike = 0;
        repeat (2) @(posedge clk);
        @(negedge clk); rst = 1'b0;

        apply_term(2'd0, 8'sd3, -8'sd4, 0, 0);
        apply_term(2'd0, -8'sd2, -8'sd5, 0, 0);
        expect_acc(-32'sd2);

        clear();
        apply_term(2'd1, 0, -8'sd7, 0, 0);
        apply_term(2'd1, 0, -8'sd7, 0, 1);
        expect_acc(-32'sd7);

        clear();
        apply_term(2'd2, 0, -8'sd127, 8'd255, 0);
        expect_acc(-32'sd32385);

        clear();
        apply_term(2'd3, 0, 8'sd5, 0, 0);
        expect_acc(32'sd5);

        if (errors == 0) $display("PASS tb_hybrid_pe");
        else $fatal(1, "FAIL tb_hybrid_pe errors=%0d", errors);
        $finish;
    end
endmodule
