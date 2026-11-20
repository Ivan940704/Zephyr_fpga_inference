`timescale 1ns/1ps

module tb_pe_gate_postprocess;
    localparam integer TAG_WIDTH = 16;
    localparam integer VECTOR_WIDTH = 741;
    localparam integer MAX_VECTORS = 2048;
    localparam integer LATENCY_PACKETS = 64;

    reg clk;
    reg rst_n;
    reg rq_in_valid;
    wire rq_in_ready;
    reg [3:0] rq_lane_valid;
    reg [4*64-1:0] rq_value_in;
    reg rq_component_in;
    reg rq_gate_in;
    reg [4*32-1:0] rq_bias_in;
    reg [4*TAG_WIDTH-1:0] rq_tag_in;

    wire out_valid;
    reg out_ready;
    wire [3:0] out_lane_valid;
    wire [4*8-1:0] out_value;
    wire out_gate;
    wire [4*TAG_WIDTH-1:0] out_tag;

    reg [VECTOR_WIDTH-1:0] vectors [0:MAX_VECTORS-1];
    reg [8*512-1:0] vector_file;
    integer vector_count;
    integer cycle_count;
    integer errors;
    integer expected_index;
    integer expected_end;
    integer drive_vector_index;
    integer input_handshakes;
    integer input_stall_cycles;
    integer stalled_output_cycles;
    integer active_results;
    integer expected_active_results;
    integer first_accept_cycle [0:MAX_VECTORS-1];
    integer recurrent_accept_cycle [0:MAX_VECTORS-1];
    integer measured_first_latency;
    integer measured_recurrent_latency;
    integer previous_output_cycle;
    integer measured_output_ii;
    integer input_seed;
    integer ready_seed;
    integer ready_random;
    integer index;
    integer lane;
    integer phase2_handshakes;
    reg monitor_enable;
    reg measure_latency;
    reg random_ready_enable;
    reg random_input_enable;
    reg stall_active;
    reg [3:0] stalled_lane_valid;
    reg [31:0] stalled_value;
    reg stalled_gate;
    reg [4*TAG_WIDTH-1:0] stalled_tag;
    reg test_passed;

    pe_gate_postprocess #(
        .TAG_WIDTH(TAG_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .rq_in_valid(rq_in_valid),
        .rq_in_ready(rq_in_ready),
        .rq_lane_valid(rq_lane_valid),
        .rq_value_in(rq_value_in),
        .rq_component_in(rq_component_in),
        .rq_gate_in(rq_gate_in),
        .rq_bias_in(rq_bias_in),
        .rq_tag_in(rq_tag_in),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .out_lane_valid(out_lane_valid),
        .out_value(out_value),
        .out_gate(out_gate),
        .out_tag(out_tag)
    );

    initial begin
        clk = 1'b0;
        forever #2.5 clk = ~clk;
    end

    task load_component;
        input integer vector_index;
        input component;
        begin
            rq_component_in = component;
            rq_gate_in = vectors[vector_index][0];
            rq_lane_valid = vectors[vector_index][4:1];
            rq_tag_in = vectors[vector_index][708:645];
            if (component == 1'b0) begin
                rq_value_in = vectors[vector_index][388:133];
                rq_bias_in = 128'd0;
            end else begin
                rq_value_in = vectors[vector_index][644:389];
                rq_bias_in = vectors[vector_index][132:5];
            end
            drive_vector_index = vector_index;
        end
    endtask

    task random_input_gap;
        integer gap_count;
        integer gap_index;
        integer random_value;
        begin
            gap_count = 0;
            if (random_input_enable) begin
                random_value = $random(input_seed);
                gap_count = random_value & 3;
            end
            for (gap_index = 0; gap_index < gap_count;
                 gap_index = gap_index + 1) begin
                @(negedge clk);
                rq_in_valid = 1'b0;
            end
        end
    endtask

    task send_component;
        input integer vector_index;
        input component;
        begin
            random_input_gap;
            @(negedge clk);
            load_component(vector_index, component);
            rq_in_valid = 1'b1;
            begin : wait_until_ready
                while (1) begin
                    #1;
                    if (rq_in_ready) begin
                        @(posedge clk);
                        disable wait_until_ready;
                    end
                    @(negedge clk);
                end
            end
        end
    endtask

    task drive_range;
        input integer start_index;
        input integer count;
        integer drive_index;
        begin
            for (drive_index = start_index;
                 drive_index < start_index + count;
                 drive_index = drive_index + 1) begin
                send_component(drive_index, 1'b0);
                send_component(drive_index, 1'b1);
            end
            @(negedge clk);
            rq_in_valid = 1'b0;
        end
    endtask

    task compare_output;
        input integer vector_index;
        begin
            if (out_gate !== vectors[vector_index][0]) begin
                $display("FAIL gate vector=%0d got=%b expected=%b",
                         vector_index, out_gate, vectors[vector_index][0]);
                errors = errors + 1;
            end
            if (out_lane_valid !== vectors[vector_index][4:1]) begin
                $display("FAIL mask vector=%0d got=%h expected=%h",
                         vector_index, out_lane_valid,
                         vectors[vector_index][4:1]);
                errors = errors + 1;
            end
            if (out_tag !== vectors[vector_index][708:645]) begin
                $display("FAIL tag vector=%0d got=%h expected=%h",
                         vector_index, out_tag,
                         vectors[vector_index][708:645]);
                errors = errors + 1;
            end
            for (lane = 0; lane < 4; lane = lane + 1) begin
                if (vectors[vector_index][lane + 1]
                    && out_value[lane*8 +: 8]
                       !== vectors[vector_index][709 + lane*8 +: 8]) begin
                    $display("FAIL value vector=%0d lane=%0d got=%0d expected=%0d",
                             vector_index, lane,
                             $signed(out_value[lane*8 +: 8]),
                             $signed(vectors[vector_index][709 + lane*8 +: 8]));
                    errors = errors + 1;
                end
            end
        end
    endtask

    always @(negedge clk) begin
        if (!rst_n) begin
            out_ready = 1'b0;
        end else if (random_ready_enable) begin
            ready_random = $random(ready_seed);
            out_ready = ((ready_random & 7) != 0);
        end else begin
            out_ready = 1'b1;
        end
    end

    always @(posedge clk) begin
        cycle_count = cycle_count + 1;
        if (!rst_n) begin
            stall_active = 1'b0;
        end else begin
            if (rq_in_valid && !rq_in_ready) begin
                input_stall_cycles = input_stall_cycles + 1;
            end
            if (rq_in_valid && rq_in_ready) begin
                input_handshakes = input_handshakes + 1;
                if (rq_component_in == 1'b0) begin
                    first_accept_cycle[drive_vector_index] = cycle_count;
                end else begin
                    recurrent_accept_cycle[drive_vector_index] = cycle_count;
                end
            end

            if (monitor_enable && out_valid) begin
                if (expected_index >= expected_end) begin
                    $display("FAIL unexpected output after vector %0d", expected_end - 1);
                    errors = errors + 1;
                end else begin
                    compare_output(expected_index);
                end

                if (stall_active) begin
                    if (out_lane_valid !== stalled_lane_valid
                        || out_value !== stalled_value
                        || out_gate !== stalled_gate
                        || out_tag !== stalled_tag) begin
                        $display("FAIL output changed while stalled vector=%0d",
                                 expected_index);
                        errors = errors + 1;
                    end
                end

                if (out_ready) begin
                    if (measure_latency && expected_index < expected_end) begin
                        if (measured_first_latency < 0) begin
                            measured_first_latency =
                                cycle_count - first_accept_cycle[expected_index];
                            measured_recurrent_latency =
                                cycle_count - recurrent_accept_cycle[expected_index];
                        end else begin
                            if (cycle_count - first_accept_cycle[expected_index]
                                != measured_first_latency) begin
                                $display("FAIL first-component latency vector=%0d got=%0d expected=%0d",
                                         expected_index,
                                         cycle_count - first_accept_cycle[expected_index],
                                         measured_first_latency);
                                errors = errors + 1;
                            end
                            if (cycle_count - recurrent_accept_cycle[expected_index]
                                != measured_recurrent_latency) begin
                                $display("FAIL recurrent-component latency vector=%0d got=%0d expected=%0d",
                                         expected_index,
                                         cycle_count - recurrent_accept_cycle[expected_index],
                                         measured_recurrent_latency);
                                errors = errors + 1;
                            end
                        end
                        if (previous_output_cycle >= 0) begin
                            if (measured_output_ii < 0) begin
                                measured_output_ii = cycle_count - previous_output_cycle;
                            end else if (cycle_count - previous_output_cycle
                                         != measured_output_ii) begin
                                $display("FAIL output II vector=%0d got=%0d expected=%0d",
                                         expected_index,
                                         cycle_count - previous_output_cycle,
                                         measured_output_ii);
                                errors = errors + 1;
                            end
                        end
                        previous_output_cycle = cycle_count;
                    end
                    for (lane = 0; lane < 4; lane = lane + 1) begin
                        if (out_lane_valid[lane]) begin
                            active_results = active_results + 1;
                        end
                    end
                    expected_index = expected_index + 1;
                    stall_active = 1'b0;
                end else begin
                    stalled_output_cycles = stalled_output_cycles + 1;
                    if (!stall_active) begin
                        stall_active = 1'b1;
                        stalled_lane_valid = out_lane_valid;
                        stalled_value = out_value;
                        stalled_gate = out_gate;
                        stalled_tag = out_tag;
                    end
                end
            end else if (monitor_enable && stall_active) begin
                $display("FAIL out_valid dropped while output stalled");
                errors = errors + 1;
                stall_active = 1'b0;
            end
        end
    end

    initial begin
        #20000000;
        $fatal(1, "FAIL tb_pe_gate_postprocess watchdog expected=%0d/%0d",
               expected_index, expected_end);
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        rq_in_valid = 1'b0;
        rq_lane_valid = 4'b0000;
        rq_value_in = 256'd0;
        rq_component_in = 1'b0;
        rq_gate_in = 1'b0;
        rq_bias_in = 128'd0;
        rq_tag_in = 64'd0;
        out_ready = 1'b0;
        vector_count = 0;
        cycle_count = 0;
        errors = 0;
        expected_index = 0;
        expected_end = 0;
        drive_vector_index = 0;
        input_handshakes = 0;
        input_stall_cycles = 0;
        stalled_output_cycles = 0;
        active_results = 0;
        expected_active_results = 0;
        measured_first_latency = -1;
        measured_recurrent_latency = -1;
        previous_output_cycle = -1;
        measured_output_ii = -1;
        input_seed = 32'h13579bdf;
        ready_seed = 32'h2468ace1;
        monitor_enable = 1'b0;
        measure_latency = 1'b0;
        random_ready_enable = 1'b0;
        random_input_enable = 1'b0;
        stall_active = 1'b0;
        test_passed = 1'b0;

        if (!$value$plusargs("VECTORS=%s", vector_file)
            || !$value$plusargs("COUNT=%d", vector_count)) begin
            $fatal(1, "missing VECTORS/COUNT plusargs");
        end
        if (vector_count <= LATENCY_PACKETS || vector_count > MAX_VECTORS) begin
            $fatal(1, "invalid vector_count=%0d", vector_count);
        end
        $readmemh(vector_file, vectors);
        for (index = 0; index < vector_count; index = index + 1) begin
            for (lane = 0; lane < 4; lane = lane + 1) begin
                if (vectors[index][lane + 1]) begin
                    expected_active_results = expected_active_results + 1;
                end
            end
        end

        repeat (3) @(posedge clk);
        if (rq_in_ready !== 1'b0 || out_valid !== 1'b0) begin
            $display("FAIL interface active during reset");
            errors = errors + 1;
        end
        @(negedge clk);
        rst_n = 1'b1;

        // Reset with only the first component pending.  No orphan output may
        // escape after reset release.
        send_component(0, 1'b0);
        @(negedge clk);
        rq_in_valid = 1'b0;
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (8) begin
            @(posedge clk);
            if (out_valid) begin
                $display("FAIL orphan output after pending reset");
                errors = errors + 1;
            end
        end

        // No-stall phase discovers the implementation latency and verifies the
        // required protocol throughput of one output packet every two cycles.
        input_handshakes = 0;
        expected_index = 0;
        expected_end = LATENCY_PACKETS;
        active_results = 0;
        monitor_enable = 1'b1;
        measure_latency = 1'b1;
        random_ready_enable = 1'b0;
        random_input_enable = 1'b0;
        fork
            drive_range(0, LATENCY_PACKETS);
            begin
                wait (expected_index == expected_end);
            end
        join
        @(negedge clk);
        monitor_enable = 1'b0;
        rq_in_valid = 1'b0;
        if (input_handshakes != 2 * LATENCY_PACKETS) begin
            $display("FAIL no-stall handshakes=%0d expected=%0d",
                     input_handshakes, 2 * LATENCY_PACKETS);
            errors = errors + 1;
        end
        if (measured_output_ii != 2) begin
            $display("FAIL measured protocol II=%0d expected=2", measured_output_ii);
            errors = errors + 1;
        end

        // Flush by reset, then re-run the full corpus with deterministic random
        // input gaps and output backpressure.
        @(negedge clk);
        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        input_handshakes = 0;
        input_stall_cycles = 0;
        stalled_output_cycles = 0;
        active_results = 0;
        expected_index = 0;
        expected_end = vector_count;
        monitor_enable = 1'b1;
        measure_latency = 1'b0;
        random_ready_enable = 1'b1;
        random_input_enable = 1'b1;
        fork
            drive_range(0, vector_count);
            begin
                wait (expected_index == expected_end);
            end
        join
        @(negedge clk);
        monitor_enable = 1'b0;
        random_ready_enable = 1'b0;
        random_input_enable = 1'b0;
        rq_in_valid = 1'b0;
        phase2_handshakes = input_handshakes;

        if (phase2_handshakes != 2 * vector_count) begin
            $display("FAIL randomized handshakes=%0d expected=%0d",
                     phase2_handshakes, 2 * vector_count);
            errors = errors + 1;
        end
        if (active_results != expected_active_results) begin
            $display("FAIL active results=%0d expected=%0d",
                     active_results, expected_active_results);
            errors = errors + 1;
        end
        if (stalled_output_cycles == 0 || input_stall_cycles == 0) begin
            $display("FAIL backpressure coverage output_stalls=%0d input_stalls=%0d",
                     stalled_output_cycles, input_stall_cycles);
            errors = errors + 1;
        end

        if (errors == 0) begin
            test_passed = 1'b1;
            $display("PE_GATE_POSTPROCESS_METRICS output_packets=%0d input_packets=%0d active_results=%0d first_latency=%0d recurrent_latency=%0d II=%0d output_stalls=%0d input_stalls=%0d",
                     vector_count, 2 * vector_count, active_results,
                     measured_first_latency, measured_recurrent_latency,
                     measured_output_ii, stalled_output_cycles,
                     input_stall_cycles);
            $display("PASS tb_pe_gate_postprocess");
        end else begin
            $fatal(1, "FAIL tb_pe_gate_postprocess errors=%0d", errors);
        end
        $finish;
    end

endmodule
