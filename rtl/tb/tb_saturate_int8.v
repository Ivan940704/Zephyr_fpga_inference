`timescale 1ns/1ps

module tb_saturate_int8;
    reg signed [63:0] value_in;
    wire signed [7:0] value_out;
    wire clipped;
    integer errors;

    saturate_int8 dut (.value_in(value_in), .value_out(value_out), .clipped(clipped));

    task check;
        input signed [63:0] value;
        input signed [7:0] expected;
        input expected_clipped;
        begin
            value_in = value;
            #1;
            if ((value_out !== expected) || (clipped !== expected_clipped)) begin
                $display("ERROR saturate value=%0d got=%0d/%0d expected=%0d/%0d",
                         value, value_out, clipped, expected, expected_clipped);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        check(-64'sd500, -8'sd127, 1'b1);
        check(-64'sd127, -8'sd127, 1'b0);
        check(64'sd0, 8'sd0, 1'b0);
        check(64'sd127, 8'sd127, 1'b0);
        check(64'sd500, 8'sd127, 1'b1);
        if (errors == 0) $display("PASS tb_saturate_int8");
        else $fatal(1, "FAIL tb_saturate_int8 errors=%0d", errors);
        $finish;
    end
endmodule
