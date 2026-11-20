`timescale 1ns/1ps

module tb_pe_hybrid_mac;
    reg clk;
    reg rst_n;
    reg acc_clear;
    reg acc_enable;
    reg [1:0] mode;
    reg signed [7:0] operand_a;
    reg signed [7:0] operand_b;
    reg [7:0] gate_u8;
    reg spike_enable;
    reg signed [31:0] direct_value;
    wire signed [31:0] accumulator;
    wire overflow;

    integer vector_file;
    integer scan_count;
    integer vector_count;
    integer failures;
    integer clear_i;
    integer enable_i;
    integer mode_i;
    integer a_i;
    integer b_i;
    integer gate_i;
    integer spike_i;
    integer direct_i;
    integer expected_acc_i;
    integer expected_overflow_i;
    reg test_passed;
    reg [8*256-1:0] vector_path;
    reg [8*512-1:0] header_line;

    always #2.5 clk = ~clk;

    pe_hybrid_mac dut (
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
        operand_a = 8'sd0;
        operand_b = 8'sd0;
        gate_u8 = 8'd0;
        spike_enable = 1'b0;
        direct_value = 32'sd0;
        vector_count = 0;
        failures = 0;
        test_passed = 1'b0;

        if (!$value$plusargs("VECTORS=%s", vector_path))
            vector_path = "tb/vectors/pe_hybrid_mac_vectors.txt";

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        #1;
        if (accumulator !== 32'sd0 || overflow !== 1'b0) begin
            $display("FAIL tb_pe_hybrid_mac reset state");
            $fatal(1);
        end

        vector_file = $fopen(vector_path, "r");
        if (vector_file == 0) begin
            $display("FAIL tb_pe_hybrid_mac cannot open %0s", vector_path);
            $fatal(1);
        end
        scan_count = $fgets(header_line, vector_file);

        while (!$feof(vector_file)) begin
            scan_count = $fscanf(
                vector_file,
                "%d %d %d %d %d %d %d %d %d %d\n",
                clear_i, enable_i, mode_i, a_i, b_i, gate_i, spike_i,
                direct_i, expected_acc_i, expected_overflow_i
            );
            if (scan_count == 10) begin
                @(negedge clk);
                acc_clear = clear_i;
                acc_enable = enable_i;
                mode = mode_i[1:0];
                operand_a = a_i;
                operand_b = b_i;
                gate_u8 = gate_i;
                spike_enable = spike_i;
                direct_value = direct_i;
                @(posedge clk);
                #1;
                vector_count = vector_count + 1;
                if ($signed(accumulator) !== expected_acc_i ||
                    overflow !== expected_overflow_i[0]) begin
                    failures = failures + 1;
                    if (failures <= 12)
                        $display(
                            "FAIL vector=%0d mode=%0d got_acc=%0d exp_acc=%0d got_ov=%0d exp_ov=%0d",
                            vector_count, mode_i, $signed(accumulator),
                            expected_acc_i, overflow, expected_overflow_i
                        );
                end
            end
        end
        $fclose(vector_file);

        if (failures == 0) begin
            test_passed = 1'b1;
            $display("PE_HYBRID_METRICS vectors=%0d modes=4", vector_count);
            $display("PASS tb_pe_hybrid_mac");
        end else begin
            $display("FAIL tb_pe_hybrid_mac failures=%0d", failures);
            $fatal(1);
        end
        $finish;
    end
endmodule
