`timescale 1ns/1ps

module tb_accelerator_top_timing_cut;
    reg clk;
    reg rst_n;
    reg [2:0] forced_barrier;
    wire [2:0] pe_barrier_idle;
    integer checks;

    accelerator_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .pe_barrier_idle(pe_barrier_idle)
    );

    always #5 clk = ~clk;

    task automatic check;
        input condition;
        input [8*96-1:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                $display("FAIL tb_accelerator_top_timing_cut: %0s", message);
                $fatal(1);
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        forced_barrier = 3'b111;
        checks = 0;
        force dut.subsystem_pe_barrier_idle = forced_barrier;

        repeat (2) @(negedge clk);
        check(dut.fsm_pe_barrier_idle_q === 3'b000,
              "FSM barrier must reset to the conservative non-idle value");

        rst_n = 1'b1;
        forced_barrier = 3'b101;
        #1;
        check(pe_barrier_idle === 3'b101,
              "external diagnostic must remain combinational");
        check(dut.fsm_pe_barrier_idle_q === 3'b000,
              "FSM barrier must not bypass the timing register");

        @(negedge clk);
        check(dut.fsm_pe_barrier_idle_q === 3'b101,
              "FSM barrier must sample the subsystem value after one edge");

        forced_barrier = 3'b010;
        #1;
        check(pe_barrier_idle === 3'b010,
              "external diagnostic must track the current subsystem value");
        check(dut.fsm_pe_barrier_idle_q === 3'b101,
              "FSM barrier must hold the previous sample within the cycle");

        @(negedge clk);
        check(dut.fsm_pe_barrier_idle_q === 3'b010,
              "FSM barrier must capture the next subsystem sample");

        // Verify the consumer-boundary adapter for the only partial 32-row
        // image-v5 vector. Index 79 terminates the compact logical stream;
        // indices 80..95 are drained from the PE without reaching the store.
        force dut.active_stage_id = 4'd5;
        force dut.system_abort = 1'b0;
        force dut.subsystem_coefficient_valid = 1'b1;
        force dut.df_store_coefficient_ready = 1'b1;
        force dut.subsystem_coefficient_index = 9'd79;
        force dut.subsystem_coefficient_last = 1'b0;
        #1;
        check(dut.df_coefficient_padding === 1'b0,
              "stage-5 index 79 must remain a stored coefficient");
        check(dut.df_coefficient_last === 1'b1,
              "stage-5 index 79 must terminate the logical stream");
        check(dut.subsystem_coefficient_ready === 1'b1,
              "stage-5 index 79 must follow store readiness");
        check(dut.u_df_coefficient_store.coefficient_valid === 1'b1,
              "stage-5 index 79 must reach the compact store");

        force dut.df_store_coefficient_ready = 1'b0;
        force dut.subsystem_coefficient_index = 9'd80;
        #1;
        check(dut.df_coefficient_padding === 1'b1,
              "stage-5 index 80 must be structural padding");
        check(dut.subsystem_coefficient_ready === 1'b0,
              "stage-5 padding must retain the existing ready path");
        check(dut.u_df_coefficient_store.coefficient_valid === 1'b0,
              "stage-5 padding must not reach the compact store");

        force dut.df_store_coefficient_ready = 1'b1;
        #1;
        check(dut.subsystem_coefficient_ready === 1'b1,
              "stage-5 padding must drain while the healthy store is ready");

        force dut.active_stage_id = 4'd8;
        force dut.df_store_coefficient_ready = 1'b0;
        #1;
        check(dut.df_coefficient_padding === 1'b0,
              "full stage-8 tile must not be classified as padding");
        check(dut.subsystem_coefficient_ready === 1'b0,
              "non-padding coefficients must retain store backpressure");

        release dut.active_stage_id;
        release dut.system_abort;
        release dut.subsystem_coefficient_valid;
        release dut.df_store_coefficient_ready;
        release dut.subsystem_coefficient_index;
        release dut.subsystem_coefficient_last;

        release dut.subsystem_pe_barrier_idle;
        $display("PASS tb_accelerator_top_timing_cut checks=%0d", checks);
        $finish;
    end
endmodule
