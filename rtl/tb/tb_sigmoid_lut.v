`timescale 1ns/1ps

module tb_sigmoid_lut;
    reg clk = 1'b0;
    reg cfg_we;
    reg [7:0] cfg_addr;
    reg [7:0] cfg_data;
    reg signed [7:0] input_q;
    wire [7:0] sigmoid_u8;
    integer errors;

    always #5 clk = ~clk;

    sigmoid_lut dut (
        .clk(clk), .cfg_we(cfg_we), .cfg_addr(cfg_addr), .cfg_data(cfg_data),
        .input_q(input_q), .sigmoid_u8(sigmoid_u8)
    );

    task write_entry;
        input [7:0] addr;
        input [7:0] data;
        begin
            @(negedge clk); cfg_we = 1'b1; cfg_addr = addr; cfg_data = data;
            @(posedge clk); #1; cfg_we = 1'b0;
        end
    endtask

    task check;
        input signed [7:0] value;
        input [7:0] expected;
        begin
            input_q = value;
            #1;
            if (sigmoid_u8 !== expected) begin
                $display("ERROR sigmoid input=%0d got=%0d expected=%0d", value, sigmoid_u8, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0; cfg_we = 0; cfg_addr = 0; cfg_data = 0; input_q = 0;
        write_entry(8'd0, 8'd3);
        write_entry(8'd127, 8'd128);
        write_entry(8'd254, 8'd252);
        check(-8'sd127, 8'd3);
        check(8'sd0, 8'd128);
        check(8'sd127, 8'd252);
        if (errors == 0) $display("PASS tb_sigmoid_lut");
        else $fatal(1, "FAIL tb_sigmoid_lut errors=%0d", errors);
        $finish;
    end
endmodule
