`timescale 1ns/1ps

module tb_signed_round_shift;
    reg signed [63:0] value_in;
    reg [5:0] shift;
    wire signed [63:0] value_out;
    integer errors;

    signed_round_shift dut (.value_in(value_in), .shift(shift), .value_out(value_out));

    task check;
        input signed [63:0] value;
        input [5:0] amount;
        input signed [63:0] expected;
        begin
            value_in = value;
            shift = amount;
            #1;
            if (value_out !== expected) begin
                $display("ERROR signed_round_shift value=%0d shift=%0d got=%0d expected=%0d",
                         value, amount, value_out, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        check(64'sd10, 0, 64'sd10);
        check(64'sd3, 1, 64'sd2);
        check(-64'sd3, 1, -64'sd2);
        check(64'sd1, 1, 64'sd1);
        check(-64'sd1, 1, -64'sd1);
        check(64'sd255, 8, 64'sd1);
        check(-64'sd255, 8, -64'sd1);
        check(64'sd127, 8, 64'sd0);
        check(-64'sd127, 8, 64'sd0);
        if (errors == 0) $display("PASS tb_signed_round_shift");
        else $fatal(1, "FAIL tb_signed_round_shift errors=%0d", errors);
        $finish;
    end
endmodule
