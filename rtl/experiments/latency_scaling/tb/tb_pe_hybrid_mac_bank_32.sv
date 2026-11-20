`timescale 1ns/1ps

module tb_pe_hybrid_mac_bank_32;
    reg clk;
    reg rst_n;
    reg acc_clear;
    reg acc_enable;
    reg [1:0] mode;
    reg [255:0] operand_a;
    reg [255:0] operand_b;
    reg [255:0] gate_u8;
    reg [31:0] spike_enable;
    reg [1023:0] direct_value;
    wire [1023:0] accumulator;
    wire [31:0] overflow;

    integer lane;
    integer failures;
    integer expected;
    reg test_passed;

    always #4 clk = ~clk;

    pe_hybrid_mac_bank_32 dut (
        .clk(clk),
        .rst_n(rst_n),
        .acc_clear(acc_clear),
        .acc_enable(acc_enable),
        .mode(mode),
        .operand_a(operand_a),
        .operand_b(operand_b),
        .gate_u8(gate_u8),
        .spike_enable(spike_enable),
        .direct_value(direct_value),
        .accumulator(accumulator),
        .overflow(overflow)
    );

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        acc_clear = 1'b0;
        acc_enable = 1'b0;
        mode = 2'd0;
        operand_a = 256'd0;
        operand_b = 256'd0;
        gate_u8 = 256'd0;
        spike_enable = 32'd0;
        direct_value = 1024'd0;
        failures = 0;
        test_passed = 1'b0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        #1;
        if (accumulator !== 1024'd0 || overflow !== 32'd0) begin
            $display("FAIL reset state");
            $fatal(1);
        end

        // Dense mode: every lane gets a distinct signed operand so swapped,
        // missing, or aliased lane wiring is observable.
        @(negedge clk);
        mode = 2'd0;
        for (lane = 0; lane < 32; lane = lane + 1) begin
            operand_a[lane * 8 +: 8] = lane - 16;
            operand_b[lane * 8 +: 8] = 8'sd2;
        end
        acc_enable = 1'b1;
        @(posedge clk);
        #1;
        @(negedge clk);
        acc_enable = 1'b0;
        @(posedge clk);
        #1;
        for (lane = 0; lane < 32; lane = lane + 1) begin
            expected = (lane - 16) * 2;
            if ($signed(accumulator[lane * 32 +: 32]) !== expected) begin
                failures = failures + 1;
                $display(
                    "FAIL dense lane=%0d got=%0d expected=%0d",
                    lane,
                    $signed(accumulator[lane * 32 +: 32]),
                    expected
                );
            end
        end

        // Clear and direct mode independently validate all 32 accumulator
        // slices without depending on multiplier arithmetic.
        @(negedge clk);
        acc_clear = 1'b1;
        @(posedge clk);
        #1;
        @(negedge clk);
        acc_clear = 1'b0;
        mode = 2'd3;
        for (lane = 0; lane < 32; lane = lane + 1)
            direct_value[lane * 32 +: 32] = lane * 1000 - 15000;
        acc_enable = 1'b1;
        @(posedge clk);
        #1;
        @(negedge clk);
        acc_enable = 1'b0;
        @(posedge clk);
        #1;
        for (lane = 0; lane < 32; lane = lane + 1) begin
            expected = lane * 1000 - 15000;
            if ($signed(accumulator[lane * 32 +: 32]) !== expected) begin
                failures = failures + 1;
                $display(
                    "FAIL direct lane=%0d got=%0d expected=%0d",
                    lane,
                    $signed(accumulator[lane * 32 +: 32]),
                    expected
                );
            end
        end
        if (overflow !== 32'd0) begin
            failures = failures + 1;
            $display("FAIL unexpected overflow mask=%h", overflow);
        end

        if (failures == 0) begin
            test_passed = 1'b1;
            $display("PE_HYBRID_MAC_BANK_32_METRICS lanes=32 checked_results=64 period_ns=8.000");
            $display("PASS tb_pe_hybrid_mac_bank_32");
        end else begin
            $display("FAIL tb_pe_hybrid_mac_bank_32 failures=%0d", failures);
            $fatal(1);
        end
        $finish;
    end
endmodule
