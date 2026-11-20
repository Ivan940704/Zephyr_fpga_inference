`timescale 1ns/1ps

module tb_pe_sigmoid_lut_255;
    localparam TAG_WIDTH = 8;
    localparam QUEUE_DEPTH = 4096;

    reg clk;
    reg rst_n;

    reg in_valid;
    wire in_ready;
    reg [3:0] lane_valid_in;
    reg [31:0] gate_in;
    reg [(4*TAG_WIDTH)-1:0] tag_in;
    reg [2:0] table_select;

    wire out_valid;
    reg out_ready;
    wire [3:0] lane_valid_out;
    wire [31:0] lambda_out;
    wire [(4*TAG_WIDTH)-1:0] tag_out;

    reg cfg_start_valid;
    wire cfg_start_ready;
    reg cfg_data_valid;
    wire cfg_data_ready;
    reg [7:0] cfg_data;
    wire cfg_done;
    wire table_valid;

    reg [7:0] golden [0:2039];
    reg [31:0] expected_lambda [0:QUEUE_DEPTH-1];
    reg [3:0] expected_mask [0:QUEUE_DEPTH-1];
    reg [(4*TAG_WIDTH)-1:0] expected_tag [0:QUEUE_DEPTH-1];
    integer expected_cycle [0:QUEUE_DEPTH-1];
    integer expected_phase [0:QUEUE_DEPTH-1];

    integer queue_head;
    integer queue_tail;
    integer cycle_count;
    integer failures;
    integer accepted_packets;
    integer checked_packets;
    integer accepted_vectors;
    integer checked_vectors;
    integer no_stall_vectors;
    integer backpressure_vectors;
    integer defensive_vectors;
    integer stall_cycles;
    integer last_nostall_input_cycle;
    integer min_nostall_latency;
    integer max_nostall_latency;
    integer random_seed;
    integer random_value;
    integer test_phase;
    integer table_i;
    integer base_i;
    integer lane_i;
    integer entry_i;
    integer cfg_index;
    integer cfg_drive_cycle;
    integer wait_cycles;
    integer mask_count;
    reg random_ready_enable;
    reg test_passed;
    reg [8*512-1:0] vector_path;

    reg hold_active;
    reg [31:0] held_lambda;
    reg [3:0] held_mask;
    reg [(4*TAG_WIDTH)-1:0] held_tag;

    reg [31:0] packet_gates;
    reg [31:0] packet_tags;
    reg [3:0] packet_mask;

    always #2.5 clk = ~clk;

    pe_sigmoid_lut_255 #(
        .TAG_WIDTH(TAG_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .lane_valid_in(lane_valid_in),
        .gate_in(gate_in),
        .tag_in(tag_in),
        .table_select(table_select),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .lane_valid_out(lane_valid_out),
        .lambda_out(lambda_out),
        .tag_out(tag_out),
        .cfg_start_valid(cfg_start_valid),
        .cfg_start_ready(cfg_start_ready),
        .cfg_data_valid(cfg_data_valid),
        .cfg_data_ready(cfg_data_ready),
        .cfg_data(cfg_data),
        .cfg_done(cfg_done),
        .table_valid(table_valid)
    );

    function integer gate_index;
        input [7:0] gate_value;
        begin
            if (gate_value == 8'h80)
                gate_index = 0;
            else
                gate_index = $signed(gate_value) + 127;
        end
    endfunction

    function [7:0] expected_lookup;
        input [2:0] table_value;
        input [7:0] gate_value;
        integer flat_index;
        begin
            flat_index = (table_value * 255) + gate_index(gate_value);
            expected_lookup = golden[flat_index];
        end
    endfunction

    function integer popcount4;
        input [3:0] value;
        begin
            popcount4 = value[0] + value[1] + value[2] + value[3];
        end
    endfunction

    task record_failure;
        input [8*160-1:0] message;
        begin
            failures = failures + 1;
            if (failures <= 20)
                $display("FAIL %0s", message);
        end
    endtask

    task start_configuration;
        begin
            @(negedge clk);
            cfg_start_valid = 1'b1;
            @(posedge clk);
            if (!cfg_start_ready)
                record_failure("configuration start was not accepted");
            @(negedge clk);
            cfg_start_valid = 1'b0;
        end
    endtask

    task send_packet;
        input [2:0] packet_table;
        input [3:0] packet_lane_mask;
        input [31:0] packet_gate_values;
        input [31:0] packet_tag_values;
        integer packet_accepted;
        begin
            @(negedge clk);
            table_select = packet_table;
            lane_valid_in = packet_lane_mask;
            gate_in = packet_gate_values;
            tag_in = packet_tag_values;
            in_valid = 1'b1;
            packet_accepted = 0;
            while (packet_accepted == 0) begin
                @(posedge clk);
                if (in_ready)
                    packet_accepted = 1;
            end
            @(negedge clk);
            in_valid = 1'b0;
        end
    endtask

    always @(negedge clk) begin
        if (random_ready_enable) begin
            random_value = $random(random_seed);
            out_ready = ((random_value & 32'h0000_0003) != 0);
        end
    end

    // Transaction scoreboard. Inputs are driven only on falling edges, so all
    // ready/valid signals sampled here are stable before the DUT's NBA updates.
    always @(posedge clk) begin
        if (!rst_n) begin
            queue_head = 0;
            queue_tail = 0;
            cycle_count = 0;
            accepted_packets = 0;
            checked_packets = 0;
            accepted_vectors = 0;
            checked_vectors = 0;
            no_stall_vectors = 0;
            backpressure_vectors = 0;
            defensive_vectors = 0;
            stall_cycles = 0;
            last_nostall_input_cycle = -1;
            min_nostall_latency = 999999;
            max_nostall_latency = -1;
            hold_active = 1'b0;
        end else begin
            cycle_count = cycle_count + 1;

            if (hold_active) begin
                if (!out_valid || lambda_out !== held_lambda ||
                    lane_valid_out !== held_mask || tag_out !== held_tag)
                    record_failure("output payload changed while stalled");
                hold_active = 1'b0;
            end

            if (out_valid && !out_ready) begin
                held_lambda = lambda_out;
                held_mask = lane_valid_out;
                held_tag = tag_out;
                hold_active = 1'b1;
                stall_cycles = stall_cycles + 1;
            end

            if (out_valid && out_ready) begin
                if (queue_head >= queue_tail) begin
                    record_failure("unexpected output packet");
                end else begin
                    if (lane_valid_out !== expected_mask[queue_head])
                        record_failure("lane-valid mask mismatch");
                    if (tag_out !== expected_tag[queue_head])
                        record_failure("tag mismatch");
                    if (expected_mask[queue_head][0] &&
                        lambda_out[7:0] !== expected_lambda[queue_head][7:0])
                        record_failure("lane 0 lambda mismatch");
                    if (expected_mask[queue_head][1] &&
                        lambda_out[15:8] !== expected_lambda[queue_head][15:8])
                        record_failure("lane 1 lambda mismatch");
                    if (expected_mask[queue_head][2] &&
                        lambda_out[23:16] !== expected_lambda[queue_head][23:16])
                        record_failure("lane 2 lambda mismatch");
                    if (expected_mask[queue_head][3] &&
                        lambda_out[31:24] !== expected_lambda[queue_head][31:24])
                        record_failure("lane 3 lambda mismatch");

                    mask_count = popcount4(expected_mask[queue_head]);
                    checked_vectors = checked_vectors + mask_count;
                    checked_packets = checked_packets + 1;

                    if (expected_phase[queue_head] == 1) begin
                        if ((cycle_count - expected_cycle[queue_head]) < min_nostall_latency)
                            min_nostall_latency = cycle_count - expected_cycle[queue_head];
                        if ((cycle_count - expected_cycle[queue_head]) > max_nostall_latency)
                            max_nostall_latency = cycle_count - expected_cycle[queue_head];
                        if ((cycle_count - expected_cycle[queue_head]) != 1)
                            record_failure("no-stall lookup latency was not one cycle");
                    end
                    queue_head = queue_head + 1;
                end
            end

            if (in_valid && in_ready) begin
                if (queue_tail >= QUEUE_DEPTH) begin
                    record_failure("scoreboard queue overflow");
                end else begin
                    expected_lambda[queue_tail][7:0] =
                        expected_lookup(table_select, gate_in[7:0]);
                    expected_lambda[queue_tail][15:8] =
                        expected_lookup(table_select, gate_in[15:8]);
                    expected_lambda[queue_tail][23:16] =
                        expected_lookup(table_select, gate_in[23:16]);
                    expected_lambda[queue_tail][31:24] =
                        expected_lookup(table_select, gate_in[31:24]);
                    expected_mask[queue_tail] = lane_valid_in;
                    expected_tag[queue_tail] = tag_in;
                    expected_cycle[queue_tail] = cycle_count;
                    expected_phase[queue_tail] = test_phase;
                    queue_tail = queue_tail + 1;

                    mask_count = popcount4(lane_valid_in);
                    accepted_vectors = accepted_vectors + mask_count;
                    accepted_packets = accepted_packets + 1;
                    if (test_phase == 1) begin
                        no_stall_vectors = no_stall_vectors + mask_count;
                        if (last_nostall_input_cycle >= 0 &&
                            cycle_count != last_nostall_input_cycle + 1)
                            record_failure("no-stall packet initiation interval was not one cycle");
                        last_nostall_input_cycle = cycle_count;
                    end else if (test_phase == 2) begin
                        backpressure_vectors = backpressure_vectors + mask_count;
                    end else if (test_phase == 3) begin
                        defensive_vectors = defensive_vectors + mask_count;
                    end
                end
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        in_valid = 1'b0;
        lane_valid_in = 4'b0000;
        gate_in = 32'd0;
        tag_in = 32'd0;
        table_select = 3'd0;
        out_ready = 1'b1;
        cfg_start_valid = 1'b0;
        cfg_data_valid = 1'b0;
        cfg_data = 8'd0;
        random_ready_enable = 1'b0;
        random_seed = 32'h51_6D_0F_5A;
        test_phase = 0;
        failures = 0;
        test_passed = 1'b0;

        if (!$value$plusargs("VECTORS=%s", vector_path))
            vector_path = "tb/vectors/pe_sigmoid_lut_255_tables.hex";
        $readmemh(vector_path, golden);

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        #1;
        if (table_valid !== 1'b0 || in_ready !== 1'b0 || out_valid !== 1'b0)
            record_failure("reset or unconfigured state mismatch");

        // Begin a partial load and reset it. The incomplete table must never
        // become visible to the lookup stream.
        start_configuration();
        for (entry_i = 0; entry_i < 17; entry_i = entry_i + 1) begin
            @(negedge clk);
            cfg_data_valid = 1'b1;
            cfg_data = golden[entry_i];
            @(posedge clk);
            if (!cfg_data_ready)
                record_failure("partial configuration byte was not accepted");
        end
        @(negedge clk);
        cfg_data_valid = 1'b0;
        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        #1;
        if (table_valid !== 1'b0 || in_ready !== 1'b0)
            record_failure("partial-load reset did not invalidate table");

        // Load all eight real tables, 255 bytes per table, in table-major
        // order. The DUT internally skips address 255 between tables.
        start_configuration();
        cfg_index = 0;
        cfg_drive_cycle = 0;
        while (cfg_index < 2040) begin
            @(negedge clk);
            cfg_drive_cycle = cfg_drive_cycle + 1;
            if ((cfg_drive_cycle % 11) == 0) begin
                cfg_data_valid = 1'b0;
            end else begin
                cfg_data_valid = 1'b1;
                cfg_data = golden[cfg_index];
            end
            @(posedge clk);
            if (cfg_data_valid && cfg_data_ready)
                cfg_index = cfg_index + 1;
        end
        @(negedge clk);
        cfg_data_valid = 1'b0;
        if (!cfg_done || !table_valid)
            record_failure("full configuration did not assert done/table_valid");
        if (!in_ready)
            record_failure("lookup stream did not become ready after configuration");

        // First exhaustive pass: all eight tables and every legal gate value,
        // packed four at a time with no bubbles or output stalls.
        test_phase = 1;
        out_ready = 1'b1;
        for (table_i = 0; table_i < 8; table_i = table_i + 1) begin
            for (base_i = 0; base_i < 255; base_i = base_i + 4) begin
                packet_gates = 32'd0;
                packet_tags = 32'd0;
                packet_mask = 4'b0000;
                for (lane_i = 0; lane_i < 4; lane_i = lane_i + 1) begin
                    if ((base_i + lane_i) < 255) begin
                        packet_mask[lane_i] = 1'b1;
                        packet_gates[(lane_i*8) +: 8] = (base_i + lane_i) - 127;
                        packet_tags[(lane_i*8) +: 8] = (table_i * 17) + base_i + lane_i;
                    end
                end
                @(negedge clk);
                if (!in_ready)
                    record_failure("no-stall exhaustive source observed in_ready low");
                in_valid = 1'b1;
                table_select = table_i[2:0];
                lane_valid_in = packet_mask;
                gate_in = packet_gates;
                tag_in = packet_tags;
            end
        end
        @(negedge clk);
        in_valid = 1'b0;

        wait_cycles = 0;
        while (((queue_head != queue_tail) || out_valid) && wait_cycles < 10000) begin
            @(negedge clk);
            wait_cycles = wait_cycles + 1;
        end
        if (wait_cycles >= 10000)
            record_failure("timeout draining no-stall exhaustive pass");

        // Second exhaustive pass uses randomized output backpressure. Packets
        // are held until accepted and the scoreboard checks stable outputs.
        test_phase = 2;
        random_ready_enable = 1'b1;
        for (table_i = 0; table_i < 8; table_i = table_i + 1) begin
            for (base_i = 0; base_i < 255; base_i = base_i + 4) begin
                packet_gates = 32'd0;
                packet_tags = 32'd0;
                packet_mask = 4'b0000;
                for (lane_i = 0; lane_i < 4; lane_i = lane_i + 1) begin
                    if ((base_i + lane_i) < 255) begin
                        packet_mask[lane_i] = 1'b1;
                        packet_gates[(lane_i*8) +: 8] = (base_i + lane_i) - 127;
                        packet_tags[(lane_i*8) +: 8] = (table_i * 29) + base_i + lane_i;
                    end
                end
                send_packet(table_i[2:0], packet_mask, packet_gates, packet_tags);
            end
        end

        wait_cycles = 0;
        while (((queue_head != queue_tail) || out_valid) && wait_cycles < 20000) begin
            @(negedge clk);
            wait_cycles = wait_cycles + 1;
        end
        if (wait_cycles >= 20000)
            record_failure("timeout draining backpressure exhaustive pass");
        @(negedge clk);
        random_ready_enable = 1'b0;
        out_ready = 1'b1;

        // Defensive out-of-domain behavior: -128 aliases entry zero for every
        // resident table. Only lane zero is valid in these packets.
        test_phase = 3;
        for (table_i = 0; table_i < 8; table_i = table_i + 1) begin
            packet_gates = 32'd0;
            packet_gates[7:0] = 8'h80;
            packet_tags = 32'd0;
            packet_tags[7:0] = 8'hE0 + table_i;
            send_packet(table_i[2:0], 4'b0001, packet_gates, packet_tags);
        end

        wait_cycles = 0;
        while (((queue_head != queue_tail) || out_valid) && wait_cycles < 1000) begin
            @(negedge clk);
            wait_cycles = wait_cycles + 1;
        end
        if (wait_cycles >= 1000)
            record_failure("timeout draining defensive endpoint pass");

        if (no_stall_vectors != 2040)
            record_failure("no-stall exhaustive vector count mismatch");
        if (backpressure_vectors != 2040)
            record_failure("backpressure exhaustive vector count mismatch");
        if (defensive_vectors != 8)
            record_failure("defensive vector count mismatch");
        if (checked_vectors != 4088 || accepted_vectors != 4088)
            record_failure("total vector count mismatch");
        if (checked_packets != 1032 || accepted_packets != 1032)
            record_failure("packet count mismatch");
        if (min_nostall_latency != 1 || max_nostall_latency != 1)
            record_failure("measured no-stall latency mismatch");
        if (stall_cycles == 0)
            record_failure("randomized backpressure produced no stalled cycles");
        if (!table_valid)
            record_failure("table_valid dropped during lookup testing");

        if (failures == 0) begin
            test_passed = 1'b1;
            $display("PE_SIGMOID_METRICS tables=8 legal_vectors=4080 defensive_vectors=8 total_vectors=4088 packets=1032 latency=1 II=1 stalls=%0d", stall_cycles);
            $display("PASS tb_pe_sigmoid_lut_255");
        end else begin
            $display("FAIL tb_pe_sigmoid_lut_255 failures=%0d", failures);
            $fatal(1);
        end
        $finish;
    end
endmodule
