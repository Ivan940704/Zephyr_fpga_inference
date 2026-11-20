`timescale 1ns/1ps

module tb_gsu_state_update;
    reg [7:0] forget_u8;
    reg signed [7:0] previous_state_q;
    reg signed [7:0] cellgate_q;
    reg signed [31:0] previous_multiplier;
    reg [5:0] previous_shift;
    reg signed [31:0] cellgate_multiplier;
    reg [5:0] cellgate_shift;
    reg signed [31:0] bn_multiplier;
    reg [5:0] bn_shift;
    reg signed [31:0] bn_bias_q;
    wire signed [7:0] state_pre_q;
    wire signed [7:0] state_q;
    wire spike_q;
    wire state_pre_clipped;
    wire state_clipped;
    integer errors;

    gsu_state_update dut (
        .forget_u8(forget_u8), .previous_state_q(previous_state_q), .cellgate_q(cellgate_q),
        .previous_multiplier(previous_multiplier), .previous_shift(previous_shift),
        .cellgate_multiplier(cellgate_multiplier), .cellgate_shift(cellgate_shift),
        .bn_multiplier(bn_multiplier), .bn_shift(bn_shift), .bn_bias_q(bn_bias_q),
        .state_pre_q(state_pre_q), .state_q(state_q), .spike_q(spike_q),
        .state_pre_clipped(state_pre_clipped), .state_clipped(state_clipped)
    );

    task check;
        input [7:0] forget;
        input signed [7:0] previous;
        input signed [7:0] cellgate;
        input signed [7:0] expected_pre;
        input signed [7:0] expected_state;
        input expected_spike;
        begin
            forget_u8 = forget; previous_state_q = previous; cellgate_q = cellgate;
            #1;
            if ((state_pre_q !== expected_pre) || (state_q !== expected_state) ||
                (spike_q !== expected_spike)) begin
                $display("ERROR state_update got pre/state/spike=%0d/%0d/%0d expected=%0d/%0d/%0d",
                         state_pre_q, state_q, spike_q, expected_pre, expected_state, expected_spike);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        previous_multiplier = 32'sd1073741824; previous_shift = 6'd30;
        cellgate_multiplier = 32'sd1073741824; cellgate_shift = 6'd30;
        // BN requantizer creates state_pre * 256 before the common guard shift.
        bn_multiplier = 32'sd1073741824; bn_shift = 6'd22;
        bn_bias_q = 32'sd0;
        check(8'd255, 8'sd10, -8'sd20, 8'sd10, 8'sd10, 1'b1);
        check(8'd0, 8'sd10, -8'sd20, -8'sd20, -8'sd20, 1'b0);
        check(8'd128, 8'sd100, -8'sd100, 8'sd0, 8'sd0, 1'b1);

        previous_shift = 6'd29;
        check(8'd255, 8'sd127, 8'sd0, 8'sd127, 8'sd127, 1'b1);
        if (!state_pre_clipped) begin
            $display("ERROR state_update expected pre-state clipping");
            errors = errors + 1;
        end

        if (errors == 0) $display("PASS tb_gsu_state_update");
        else $fatal(1, "FAIL tb_gsu_state_update errors=%0d", errors);
        $finish;
    end
endmodule
