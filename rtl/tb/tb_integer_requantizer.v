`timescale 1ns/1ps

module tb_integer_requantizer;
    reg signed [31:0] value_in;
    reg signed [31:0] multiplier;
    reg [5:0] right_shift;
    wire signed [63:0] value_out;
    integer errors;

    integer_requantizer dut (
        .value_in(value_in), .multiplier(multiplier),
        .right_shift(right_shift), .value_out(value_out)
    );

    task check;
        input signed [31:0] value;
        input signed [31:0] mult;
        input [5:0] amount;
        input signed [63:0] expected;
        begin
            value_in = value;
            multiplier = mult;
            right_shift = amount;
            #1;
            if (value_out !== expected) begin
                $display("ERROR requant value=%0d mult=%0d shift=%0d got=%0d expected=%0d",
                         value, mult, amount, value_out, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        check(32'sd100, 32'sd3, 1, 64'sd150);
        check(-32'sd101, 32'sd3, 1, -64'sd152);
        check(32'sd9, -32'sd5, 2, -64'sd11);
        check(32'sd77, 32'sd0, 30, 64'sd0);
        check(32'sd12345, 32'sd1073741824, 30, 64'sd12345);
        if (errors == 0) $display("PASS tb_integer_requantizer");
        else $fatal(1, "FAIL tb_integer_requantizer errors=%0d", errors);
        $finish;
    end
endmodule
