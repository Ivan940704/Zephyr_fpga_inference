`timescale 1ns/1ps

module tb_pe_local_requant_bank_4lane;

    localparam integer TAG_WIDTH = 16;
    localparam integer LANE_COUNT = 4;
    localparam integer MAX_PACKETS = 4096;
    localparam integer MAX_SLOTS = MAX_PACKETS * LANE_COUNT;
    localparam integer BURST_COUNT = 32;
    localparam integer EXPECTED_LATENCY = 9;

    reg clk;
    reg rst_n;
    reg in_valid;
    wire in_ready;
    reg [3:0] in_lane_valid;
    reg [4*32-1:0] value_in;
    reg [4*32-1:0] multiplier_in;
    reg [4*6-1:0] shift_in;
    reg [4*TAG_WIDTH-1:0] tag_in;
    wire out_valid;
    reg out_ready;
    wire [3:0] out_lane_valid;
    wire [4*64-1:0] value_out;
    wire [4*TAG_WIDTH-1:0] tag_out;

    reg [3:0] vector_mask [0:MAX_PACKETS-1];
    reg signed [31:0] vector_value [0:MAX_SLOTS-1];
    reg signed [31:0] vector_multiplier [0:MAX_SLOTS-1];
    reg [5:0] vector_shift [0:MAX_SLOTS-1];
    reg [TAG_WIDTH-1:0] vector_tag [0:MAX_SLOTS-1];
    reg signed [63:0] vector_expected [0:MAX_SLOTS-1];

    reg [3:0] expected_mask_fifo [0:MAX_PACKETS-1];
    reg signed [63:0] expected_value_fifo [0:MAX_SLOTS-1];
    reg [TAG_WIDTH-1:0] expected_tag_fifo [0:MAX_SLOTS-1];

    integer vector_count;
    integer send_index;
    integer driven_index;
    integer receive_count;
    integer write_pointer;
    integer read_pointer;
    integer pending_count;
    integer cycle_count;
    integer first_accept_cycle;
    integer last_burst_accept_cycle;
    integer last_burst_output_cycle;
    integer watchdog;
    integer vector_file;
    integer scan_status;
    integer lane;
    integer slot;
    integer temp_mask;
    integer temp_value0;
    integer temp_multiplier0;
    integer temp_shift0;
    integer temp_tag0;
    reg signed [63:0] temp_expected0;
    integer temp_value1;
    integer temp_multiplier1;
    integer temp_shift1;
    integer temp_tag1;
    reg signed [63:0] temp_expected1;
    integer temp_value2;
    integer temp_multiplier2;
    integer temp_shift2;
    integer temp_tag2;
    reg signed [63:0] temp_expected2;
    integer temp_value3;
    integer temp_multiplier3;
    integer temp_shift3;
    integer temp_tag3;
    reg signed [63:0] temp_expected3;
    reg [1023:0] vectors_path;
    reg [31:0] lfsr;
    reg hold_active;
    reg held_valid;
    reg [3:0] held_mask;
    reg [4*64-1:0] held_value;
    reg [4*TAG_WIDTH-1:0] held_tag;
    reg push_now;
    reg pop_now;
    reg test_passed;

    pe_local_requant_bank_4lane #(
        .TAG_WIDTH(TAG_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .in_lane_valid(in_lane_valid),
        .value_in(value_in),
        .multiplier_in(multiplier_in),
        .shift_in(shift_in),
        .tag_in(tag_in),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .out_lane_valid(out_lane_valid),
        .value_out(value_out),
        .tag_out(tag_out)
    );

    initial begin
        clk = 1'b0;
        forever #2.5 clk = ~clk;
    end

    task drive_packet;
        input integer index;
        begin
            in_lane_valid = vector_mask[index];
            for (lane = 0; lane < LANE_COUNT; lane = lane + 1) begin
                slot = index * LANE_COUNT + lane;
                value_in[lane*32 +: 32] = vector_value[slot];
                multiplier_in[lane*32 +: 32] = vector_multiplier[slot];
                shift_in[lane*6 +: 6] = vector_shift[slot];
                tag_in[lane*TAG_WIDTH +: TAG_WIDTH] = vector_tag[slot];
            end
            driven_index = index;
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            send_index = 0;
            driven_index = -1;
            receive_count = 0;
            write_pointer = 0;
            read_pointer = 0;
            pending_count = 0;
            cycle_count = 0;
            first_accept_cycle = -1;
            last_burst_accept_cycle = -1;
            last_burst_output_cycle = -1;
            hold_active = 1'b0;
            held_valid = 1'b0;
            held_mask = 4'd0;
            held_value = 256'd0;
            held_tag = {4*TAG_WIDTH{1'b0}};
        end else begin
            cycle_count = cycle_count + 1;
            push_now = in_valid && in_ready;
            pop_now = out_valid && out_ready;

            if (hold_active) begin
                if ((out_valid !== held_valid)
                    || (out_lane_valid !== held_mask)
                    || (value_out !== held_value)
                    || (tag_out !== held_tag)) begin
                    $fatal(1, "bank output changed while stalled at cycle %0d", cycle_count);
                end
            end

            if (pop_now) begin
                if (pending_count <= 0) begin
                    $fatal(1, "bank output with empty scoreboard at cycle %0d", cycle_count);
                end
                if (out_lane_valid !== expected_mask_fifo[read_pointer]) begin
                    $fatal(1, "lane mask mismatch packet=%0d got=%h expected=%h",
                        receive_count, out_lane_valid, expected_mask_fifo[read_pointer]);
                end
                for (lane = 0; lane < LANE_COUNT; lane = lane + 1) begin
                    slot = read_pointer * LANE_COUNT + lane;
                    if ($signed(value_out[lane*64 +: 64])
                        !== expected_value_fifo[slot]) begin
                        $fatal(1,
                            "value mismatch packet=%0d lane=%0d got=%0d expected=%0d",
                            receive_count, lane,
                            $signed(value_out[lane*64 +: 64]),
                            expected_value_fifo[slot]);
                    end
                    if (tag_out[lane*TAG_WIDTH +: TAG_WIDTH]
                        !== expected_tag_fifo[slot]) begin
                        $fatal(1,
                            "tag mismatch packet=%0d lane=%0d got=%0d expected=%0d",
                            receive_count, lane,
                            tag_out[lane*TAG_WIDTH +: TAG_WIDTH],
                            expected_tag_fifo[slot]);
                    end
                end

                if (receive_count == 0) begin
                    if ((cycle_count - first_accept_cycle) != EXPECTED_LATENCY) begin
                        $fatal(1, "bank latency mismatch got=%0d expected=%0d",
                            cycle_count - first_accept_cycle, EXPECTED_LATENCY);
                    end
                end

                if ((receive_count >= 1)
                    && (receive_count < (1 + BURST_COUNT))) begin
                    if ((last_burst_output_cycle >= 0)
                        && ((cycle_count - last_burst_output_cycle) != 1)) begin
                        $fatal(1, "bank output II mismatch during burst");
                    end
                    last_burst_output_cycle = cycle_count;
                end

                read_pointer = read_pointer + 1;
                receive_count = receive_count + 1;
            end

            if (push_now) begin
                if (send_index >= vector_count) begin
                    $fatal(1, "bank accepted more packets than loaded");
                end
                if (driven_index != send_index) begin
                    $fatal(1, "bank driver index mismatch driven=%0d expected=%0d",
                        driven_index, send_index);
                end
                expected_mask_fifo[write_pointer] = vector_mask[send_index];
                for (lane = 0; lane < LANE_COUNT; lane = lane + 1) begin
                    expected_value_fifo[write_pointer*LANE_COUNT + lane] =
                        vector_expected[send_index*LANE_COUNT + lane];
                    expected_tag_fifo[write_pointer*LANE_COUNT + lane] =
                        vector_tag[send_index*LANE_COUNT + lane];
                end

                if (send_index == 0) begin
                    first_accept_cycle = cycle_count;
                end
                if ((send_index >= 1)
                    && (send_index < (1 + BURST_COUNT))) begin
                    if ((last_burst_accept_cycle >= 0)
                        && ((cycle_count - last_burst_accept_cycle) != 1)) begin
                        $fatal(1, "bank input II mismatch during burst");
                    end
                    last_burst_accept_cycle = cycle_count;
                end

                write_pointer = write_pointer + 1;
                send_index = send_index + 1;
            end

            case ({push_now, pop_now})
                2'b10: pending_count = pending_count + 1;
                2'b01: pending_count = pending_count - 1;
                default: pending_count = pending_count;
            endcase

            hold_active = out_valid && !out_ready;
            held_valid = out_valid;
            held_mask = out_lane_valid;
            held_value = value_out;
            held_tag = tag_out;
        end
    end

    initial begin
        rst_n = 1'b0;
        in_valid = 1'b0;
        in_lane_valid = 4'd0;
        value_in = 128'd0;
        multiplier_in = 128'd0;
        shift_in = 24'd0;
        tag_in = {4*TAG_WIDTH{1'b0}};
        out_ready = 1'b0;
        lfsr = 32'h4ba9_2026;
        watchdog = 0;
        vector_count = 0;
        test_passed = 1'b0;

        if (!$value$plusargs("VECTORS=%s", vectors_path)) begin
            $fatal(1, "missing +VECTORS=<path> plusarg");
        end
        vector_file = $fopen(vectors_path, "r");
        if (vector_file == 0) begin
            $fatal(1, "cannot open vector file %s", vectors_path);
        end

        while (!$feof(vector_file)) begin
            scan_status = $fscanf(
                vector_file,
                "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
                temp_mask,
                temp_value0, temp_multiplier0, temp_shift0, temp_tag0, temp_expected0,
                temp_value1, temp_multiplier1, temp_shift1, temp_tag1, temp_expected1,
                temp_value2, temp_multiplier2, temp_shift2, temp_tag2, temp_expected2,
                temp_value3, temp_multiplier3, temp_shift3, temp_tag3, temp_expected3
            );
            if (scan_status == 21) begin
                if (vector_count >= MAX_PACKETS) begin
                    $fatal(1, "vector file exceeds MAX_PACKETS=%0d", MAX_PACKETS);
                end
                vector_mask[vector_count] = temp_mask[3:0];

                vector_value[vector_count*4 + 0] = temp_value0;
                vector_multiplier[vector_count*4 + 0] = temp_multiplier0;
                vector_shift[vector_count*4 + 0] = temp_shift0[5:0];
                vector_tag[vector_count*4 + 0] = temp_tag0[TAG_WIDTH-1:0];
                vector_expected[vector_count*4 + 0] = temp_expected0;

                vector_value[vector_count*4 + 1] = temp_value1;
                vector_multiplier[vector_count*4 + 1] = temp_multiplier1;
                vector_shift[vector_count*4 + 1] = temp_shift1[5:0];
                vector_tag[vector_count*4 + 1] = temp_tag1[TAG_WIDTH-1:0];
                vector_expected[vector_count*4 + 1] = temp_expected1;

                vector_value[vector_count*4 + 2] = temp_value2;
                vector_multiplier[vector_count*4 + 2] = temp_multiplier2;
                vector_shift[vector_count*4 + 2] = temp_shift2[5:0];
                vector_tag[vector_count*4 + 2] = temp_tag2[TAG_WIDTH-1:0];
                vector_expected[vector_count*4 + 2] = temp_expected2;

                vector_value[vector_count*4 + 3] = temp_value3;
                vector_multiplier[vector_count*4 + 3] = temp_multiplier3;
                vector_shift[vector_count*4 + 3] = temp_shift3[5:0];
                vector_tag[vector_count*4 + 3] = temp_tag3[TAG_WIDTH-1:0];
                vector_expected[vector_count*4 + 3] = temp_expected3;

                vector_count = vector_count + 1;
            end else if (!$feof(vector_file)) begin
                $fatal(1, "malformed vector file near packet %0d", vector_count);
            end
        end
        $fclose(vector_file);

        if (vector_count <= (1 + BURST_COUNT)) begin
            $fatal(1, "not enough packets for latency/II checks");
        end

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        out_ready = 1'b1;

        // Isolated packet proves exact nine-cycle bank latency.
        drive_packet(0);
        in_valid = 1'b1;
        wait (send_index == 1);
        @(negedge clk);
        in_valid = 1'b0;
        wait (receive_count == 1);

        // Continuous packet burst proves bank transaction II=1 and four-slot
        // throughput while masks/tags differ from cycle to cycle.
        repeat (BURST_COUNT) begin
            @(negedge clk);
            drive_packet(send_index);
            in_valid = 1'b1;
            out_ready = 1'b1;
        end
        @(negedge clk);
        in_valid = 1'b0;
        out_ready = 1'b1;
        wait (receive_count == (1 + BURST_COUNT));

        // Remaining packets use source bubbles and randomized output stalls.
        while (receive_count < vector_count) begin
            @(negedge clk);
            watchdog = watchdog + 1;
            if (watchdog > 200000) begin
                $fatal(1, "watchdog expired send=%0d receive=%0d total=%0d",
                    send_index, receive_count, vector_count);
            end

            lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
            out_ready = lfsr[0] | lfsr[3];

            if (send_index >= vector_count) begin
                in_valid = 1'b0;
            end else if (in_valid && (driven_index == send_index)) begin
                in_valid = in_valid;
            end else if (lfsr[5] | lfsr[9]) begin
                drive_packet(send_index);
                in_valid = 1'b1;
            end else begin
                in_valid = 1'b0;
            end
        end

        @(negedge clk);
        in_valid = 1'b0;
        out_ready = 1'b1;
        repeat (5) @(posedge clk);

        if (pending_count != 0) begin
            $fatal(1, "bank scoreboard not empty: %0d", pending_count);
        end
        if (send_index != vector_count) begin
            $fatal(1, "not all bank packets accepted: %0d/%0d",
                send_index, vector_count);
        end

        test_passed = 1'b1;
        $display(
            "PASS: pe_local_requant_bank_4lane packets=%0d latency=%0d cycles II=1 max_results_per_cycle=4 stalls_checked=1",
            vector_count,
            EXPECTED_LATENCY
        );
        $finish;
    end

endmodule
