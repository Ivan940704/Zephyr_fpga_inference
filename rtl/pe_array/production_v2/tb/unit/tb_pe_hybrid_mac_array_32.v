`timescale 1ns/1ps

module tb_pe_hybrid_mac_array_32;
    localparam [1:0] MODE_DENSE  = 2'd0;
    localparam [1:0] MODE_SPIKE  = 2'd1;
    localparam [1:0] MODE_GATE   = 2'd2;
    localparam [1:0] MODE_DIRECT = 2'd3;

    reg clk;
    reg rst_n;
    reg [31:0] acc_clear;
    reg [31:0] acc_enable;
    reg [63:0] mode;
    reg [255:0] operand_a;
    reg [255:0] operand_b;
    reg [255:0] gate_u8;
    reg [31:0] spike_enable;
    reg [1023:0] direct_value;
    wire [1023:0] accumulator;
    wire [31:0] overflow;

    reg signed [31:0] expected_accumulator [0:31];
    reg expected_overflow [0:31];
    reg signed [32:0] pending_term [0:31];
    reg pending_valid [0:31];
    reg signed [32:0] model_sum;

    integer lane;
    integer failures;
    integer checked_results;
    integer accepted_commands;
    integer test_cycles;
    integer mode_commands [0:3];
    reg test_passed;

    always #5 clk = ~clk;

    pe_hybrid_mac_array_32 dut (
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

    function signed [32:0] command_term;
        input [1:0] mode_in;
        input [7:0] operand_a_in;
        input [7:0] operand_b_in;
        input [7:0] gate_u8_in;
        input spike_enable_in;
        input [31:0] direct_value_in;
        reg signed [17:0] multiply_a_f;
        reg signed [17:0] multiply_b_f;
        reg signed [35:0] multiply_product_f;
        begin
            multiply_a_f = 18'sd0;
            multiply_b_f = 18'sd0;
            multiply_product_f = 36'sd0;
            command_term = 33'sd0;
            case (mode_in)
                MODE_DENSE: begin
                    multiply_a_f = {{10{operand_a_in[7]}}, operand_a_in};
                    multiply_b_f = {{10{operand_b_in[7]}}, operand_b_in};
                    multiply_product_f = multiply_a_f * multiply_b_f;
                    command_term = {{17{multiply_product_f[15]}},
                                    multiply_product_f[15:0]};
                end
                MODE_SPIKE: begin
                    command_term = spike_enable_in
                        ? {{25{operand_b_in[7]}}, operand_b_in}
                        : 33'sd0;
                end
                MODE_GATE: begin
                    multiply_a_f = {10'd0, gate_u8_in};
                    multiply_b_f = {{10{operand_b_in[7]}}, operand_b_in};
                    multiply_product_f = multiply_a_f * multiply_b_f;
                    command_term = {{16{multiply_product_f[16]}},
                                    multiply_product_f[16:0]};
                end
                MODE_DIRECT: begin
                    command_term = {direct_value_in[31], direct_value_in};
                end
                default: command_term = 33'sd0;
            endcase
        end
    endfunction

    task drive_idle;
        begin
            acc_clear = 32'd0;
            acc_enable = 32'd0;
            mode = 64'd0;
            operand_a = 256'd0;
            operand_b = 256'd0;
            gate_u8 = 256'd0;
            spike_enable = 32'd0;
            direct_value = 1024'd0;
        end
    endtask

    task drive_random_pattern;
        input integer sequence;
        integer pattern_lane;
        integer value_a;
        integer value_b;
        integer value_gate;
        integer value_direct;
        begin
            drive_idle;
            for (pattern_lane = 0; pattern_lane < 32;
                 pattern_lane = pattern_lane + 1) begin
                acc_clear[pattern_lane] =
                    (((sequence + pattern_lane*11) % 113) == 0);
                acc_enable[pattern_lane] =
                    (((sequence*3 + pattern_lane*5) % 7) != 0);
                mode[pattern_lane*2 +: 2] =
                    (sequence + pattern_lane) % 4;
                value_a = ((sequence*17 + pattern_lane*13) % 255) - 127;
                value_b = ((sequence*29 + pattern_lane*7) % 255) - 127;
                value_gate = (sequence*31 + pattern_lane*19) % 256;
                value_direct =
                    ((sequence*7919 + pattern_lane*104729) % 2097151)
                    - 1048575;
                operand_a[pattern_lane*8 +: 8] = value_a;
                operand_b[pattern_lane*8 +: 8] = value_b;
                gate_u8[pattern_lane*8 +: 8] = value_gate;
                spike_enable[pattern_lane] =
                    ((sequence + pattern_lane*3) % 5) != 0;
                direct_value[pattern_lane*32 +: 32] = value_direct;
            end
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            for (lane = 0; lane < 32; lane = lane + 1) begin
                expected_accumulator[lane] = 32'sd0;
                expected_overflow[lane] = 1'b0;
                pending_term[lane] = 33'sd0;
                pending_valid[lane] = 1'b0;
            end
        end else begin
            test_cycles = test_cycles + 1;
            for (lane = 0; lane < 32; lane = lane + 1) begin
                if (acc_clear[lane]) begin
                    expected_accumulator[lane] = 32'sd0;
                    expected_overflow[lane] = 1'b0;
                    pending_term[lane] = 33'sd0;
                    pending_valid[lane] = 1'b0;
                end else begin
                    if (pending_valid[lane]) begin
                        model_sum =
                            $signed({expected_accumulator[lane][31],
                                     expected_accumulator[lane]})
                            + pending_term[lane];
                        if (model_sum[32] != model_sum[31])
                            expected_overflow[lane] = 1'b1;
                        expected_accumulator[lane] = model_sum[31:0];
                    end
                    pending_valid[lane] = acc_enable[lane];
                    if (acc_enable[lane]) begin
                        pending_term[lane] = command_term(
                            mode[lane*2 +: 2],
                            operand_a[lane*8 +: 8],
                            operand_b[lane*8 +: 8],
                            gate_u8[lane*8 +: 8],
                            spike_enable[lane],
                            direct_value[lane*32 +: 32]
                        );
                        accepted_commands = accepted_commands + 1;
                        mode_commands[mode[lane*2 +: 2]] =
                            mode_commands[mode[lane*2 +: 2]] + 1;
                    end
                end
            end

            #1;
            for (lane = 0; lane < 32; lane = lane + 1) begin
                checked_results = checked_results + 1;
                if ($signed(accumulator[lane*32 +: 32]) !==
                    expected_accumulator[lane]) begin
                    failures = failures + 1;
                    if (failures <= 20)
                        $display("FAIL accumulator cycle=%0d lane=%0d got=%0d expected=%0d",
                            test_cycles, lane,
                            $signed(accumulator[lane*32 +: 32]),
                            expected_accumulator[lane]);
                end
                if (overflow[lane] !== expected_overflow[lane]) begin
                    failures = failures + 1;
                    if (failures <= 20)
                        $display("FAIL overflow cycle=%0d lane=%0d got=%b expected=%b",
                            test_cycles, lane, overflow[lane],
                            expected_overflow[lane]);
                end
            end
        end
    end

    integer sequence;
    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        failures = 0;
        checked_results = 0;
        accepted_commands = 0;
        test_cycles = 0;
        test_passed = 1'b0;
        for (lane = 0; lane < 32; lane = lane + 1) begin
            expected_accumulator[lane] = 32'sd0;
            expected_overflow[lane] = 1'b0;
            pending_term[lane] = 33'sd0;
            pending_valid[lane] = 1'b0;
        end
        for (lane = 0; lane < 4; lane = lane + 1)
            mode_commands[lane] = 0;
        drive_idle;

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // Distinct direct values expose missing, aliased, or swapped lanes.
        @(negedge clk);
        drive_idle;
        acc_enable = 32'hffff_ffff;
        for (lane = 0; lane < 32; lane = lane + 1) begin
            mode[lane*2 +: 2] = MODE_DIRECT;
            direct_value[lane*32 +: 32] = lane*100003 - 1500000;
        end
        @(negedge clk);
        drive_idle;
        repeat (2) @(posedge clk);

        // Clear odd lanes while even lanes accept a dense command.  Clear has
        // priority even where clear and enable are both asserted.
        @(negedge clk);
        drive_idle;
        acc_enable = 32'hffff_ffff;
        acc_clear = 32'haaaa_aaaa;
        for (lane = 0; lane < 32; lane = lane + 1) begin
            mode[lane*2 +: 2] = MODE_DENSE;
            operand_a[lane*8 +: 8] = lane - 16;
            operand_b[lane*8 +: 8] = -3;
        end
        @(negedge clk);
        drive_idle;
        repeat (2) @(posedge clk);

        // Explicit positive and negative signed overflow, sticky behavior,
        // and independent overflow clear.
        @(negedge clk);
        drive_idle;
        acc_clear[1:0] = 2'b11;
        @(negedge clk);
        drive_idle;
        acc_enable[1:0] = 2'b11;
        mode[1:0] = MODE_DIRECT;
        mode[3:2] = MODE_DIRECT;
        direct_value[31:0] = 32'h7fff_ffff;
        direct_value[63:32] = 32'h8000_0000;
        @(negedge clk);
        drive_idle;
        acc_enable[1:0] = 2'b11;
        mode[1:0] = MODE_DIRECT;
        mode[3:2] = MODE_DIRECT;
        direct_value[31:0] = 32'd1;
        direct_value[63:32] = 32'hffff_ffff;
        @(negedge clk);
        drive_idle;
        repeat (2) @(posedge clk);
        #2;
        if (overflow[1:0] !== 2'b11) begin
            failures = failures + 1;
            $display("FAIL explicit overflow mask got=%b expected=11",
                overflow[1:0]);
        end

        @(negedge clk);
        drive_idle;
        acc_clear[0] = 1'b1;
        @(negedge clk);
        drive_idle;
        @(posedge clk);
        #2;
        if (overflow[1:0] !== 2'b10) begin
            failures = failures + 1;
            $display("FAIL independent overflow clear got=%b expected=10",
                overflow[1:0]);
        end

        // Long deterministic mixed-mode stream exercises every lane with
        // independent bubbles and clears while maintaining II=1 traffic.
        for (sequence = 0; sequence < 1024; sequence = sequence + 1) begin
            @(negedge clk);
            drive_random_pattern(sequence);
        end
        @(negedge clk);
        drive_idle;
        repeat (2) @(posedge clk);
        #2;

        if (mode_commands[MODE_DENSE] == 0 ||
            mode_commands[MODE_SPIKE] == 0 ||
            mode_commands[MODE_GATE] == 0 ||
            mode_commands[MODE_DIRECT] == 0) begin
            failures = failures + 1;
            $display("FAIL one or more modes received no accepted command");
        end

        if (failures == 0) begin
            test_passed = 1'b1;
            $display("PE_HYBRID_MAC_ARRAY_32_METRICS lanes=32 cycles=%0d commands=%0d checks=%0d dense=%0d spike=%0d gate=%0d direct=%0d latency_cycles=1 ii=1",
                test_cycles, accepted_commands, checked_results,
                mode_commands[MODE_DENSE], mode_commands[MODE_SPIKE],
                mode_commands[MODE_GATE], mode_commands[MODE_DIRECT]);
            $display("PASS tb_pe_hybrid_mac_array_32");
        end else begin
            $display("FAIL tb_pe_hybrid_mac_array_32 failures=%0d",
                failures);
        end
        $finish;
    end

endmodule
