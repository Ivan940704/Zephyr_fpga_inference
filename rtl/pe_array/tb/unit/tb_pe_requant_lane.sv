`timescale 1ns/1ps

module tb_pe_requant_lane;

    localparam integer TAG_WIDTH = 16;
    localparam integer MAX_VECTORS = 8192;
    localparam integer BURST_COUNT = 32;
    localparam integer EXPECTED_LATENCY = 9;

    reg clk;
    reg rst_n;
    reg in_valid;
    wire in_ready;
    reg signed [31:0] value_in;
    reg signed [31:0] multiplier_in;
    reg [5:0] shift_in;
    reg [TAG_WIDTH-1:0] tag_in;
    wire out_valid;
    reg out_ready;
    wire signed [63:0] value_out;
    wire [TAG_WIDTH-1:0] tag_out;

    reg signed [31:0] vector_value [0:MAX_VECTORS-1];
    reg signed [31:0] vector_multiplier [0:MAX_VECTORS-1];
    reg [5:0] vector_shift [0:MAX_VECTORS-1];
    reg [TAG_WIDTH-1:0] vector_tag [0:MAX_VECTORS-1];
    reg signed [63:0] vector_expected [0:MAX_VECTORS-1];

    reg signed [63:0] expected_fifo [0:MAX_VECTORS-1];
    reg [TAG_WIDTH-1:0] tag_fifo [0:MAX_VECTORS-1];

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
    integer scan_status;
    integer vector_file;
    integer temp_value;
    integer temp_multiplier;
    integer temp_shift;
    integer temp_tag;
    reg signed [63:0] temp_expected;
    reg [31:0] lfsr;
    reg hold_active;
    reg signed [63:0] held_value;
    reg [TAG_WIDTH-1:0] held_tag;
    reg held_valid;
    reg push_now;
    reg pop_now;
    reg [1023:0] vectors_path;

    pe_requant_lane #(
        .TAG_WIDTH(TAG_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .value_in(value_in),
        .multiplier_in(multiplier_in),
        .shift_in(shift_in),
        .tag_in(tag_in),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .value_out(value_out),
        .tag_out(tag_out)
    );

    initial begin
        clk = 1'b0;
        forever #2.5 clk = ~clk;
    end

    task drive_vector;
        input integer index;
        begin
            value_in      = vector_value[index];
            multiplier_in = vector_multiplier[index];
            shift_in      = vector_shift[index];
            tag_in        = vector_tag[index];
            driven_index  = index;
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            send_index                 = 0;
            driven_index               = -1;
            receive_count              = 0;
            write_pointer              = 0;
            read_pointer               = 0;
            pending_count              = 0;
            cycle_count                = 0;
            first_accept_cycle         = -1;
            last_burst_accept_cycle    = -1;
            last_burst_output_cycle    = -1;
            hold_active                = 1'b0;
            held_value                 = 64'sd0;
            held_tag                   = {TAG_WIDTH{1'b0}};
            held_valid                 = 1'b0;
        end else begin
            cycle_count = cycle_count + 1;
            push_now = in_valid && in_ready;
            pop_now  = out_valid && out_ready;

            if (hold_active) begin
                if ((out_valid !== held_valid)
                    || (value_out !== held_value)
                    || (tag_out !== held_tag)) begin
                    $fatal(1, "output changed while stalled at cycle %0d", cycle_count);
                end
            end

            if (pop_now) begin
                if (pending_count <= 0) begin
                    $fatal(1, "output transaction with empty scoreboard at cycle %0d", cycle_count);
                end
                if (value_out !== expected_fifo[read_pointer]) begin
                    $display("Mismatch vector=%0d value=%0d multiplier=%0d shift=%0d",
                        receive_count,
                        vector_value[receive_count],
                        vector_multiplier[receive_count],
                        vector_shift[receive_count]);
                    $fatal(1, "value mismatch got=%0d expected=%0d tag=%0d",
                        value_out, expected_fifo[read_pointer], tag_out);
                end
                if (tag_out !== tag_fifo[read_pointer]) begin
                    $fatal(1, "tag mismatch got=%0d expected=%0d",
                        tag_out, tag_fifo[read_pointer]);
                end

                if (receive_count == 0) begin
                    if ((cycle_count - first_accept_cycle) != EXPECTED_LATENCY) begin
                        $fatal(1, "latency mismatch got=%0d expected=%0d",
                            cycle_count - first_accept_cycle, EXPECTED_LATENCY);
                    end
                end

                if ((receive_count >= 1) && (receive_count < (1 + BURST_COUNT))) begin
                    if ((last_burst_output_cycle >= 0)
                        && ((cycle_count - last_burst_output_cycle) != 1)) begin
                        $fatal(1, "output II mismatch during burst");
                    end
                    last_burst_output_cycle = cycle_count;
                end

                read_pointer  = read_pointer + 1;
                receive_count = receive_count + 1;
            end

            if (push_now) begin
                if (send_index >= vector_count) begin
                    $fatal(1, "accepted more inputs than loaded vectors");
                end
                if (driven_index != send_index) begin
                    $fatal(1, "driver/scoreboard index mismatch driven=%0d expected=%0d",
                        driven_index, send_index);
                end
                expected_fifo[write_pointer] = vector_expected[send_index];
                tag_fifo[write_pointer]      = vector_tag[send_index];

                if (send_index == 0) begin
                    first_accept_cycle = cycle_count;
                end

                if ((send_index >= 1) && (send_index < (1 + BURST_COUNT))) begin
                    if ((last_burst_accept_cycle >= 0)
                        && ((cycle_count - last_burst_accept_cycle) != 1)) begin
                        $fatal(1, "input II mismatch during burst");
                    end
                    last_burst_accept_cycle = cycle_count;
                end

                write_pointer = write_pointer + 1;
                send_index    = send_index + 1;
            end

            case ({push_now, pop_now})
                2'b10: pending_count = pending_count + 1;
                2'b01: pending_count = pending_count - 1;
                default: pending_count = pending_count;
            endcase

            hold_active = out_valid && !out_ready;
            held_valid  = out_valid;
            held_value  = value_out;
            held_tag    = tag_out;
        end
    end

    initial begin
        rst_n         = 1'b0;
        in_valid      = 1'b0;
        value_in      = 32'sd0;
        multiplier_in = 32'sd0;
        shift_in      = 6'd0;
        tag_in        = {TAG_WIDTH{1'b0}};
        out_ready     = 1'b0;
        lfsr          = 32'h1ace_b00c;
        watchdog      = 0;
        vector_count  = 0;

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
                "%d %d %d %d %d\n",
                temp_value,
                temp_multiplier,
                temp_shift,
                temp_tag,
                temp_expected
            );
            if (scan_status == 5) begin
                if (vector_count >= MAX_VECTORS) begin
                    $fatal(1, "vector file exceeds MAX_VECTORS=%0d", MAX_VECTORS);
                end
                vector_value[vector_count]      = temp_value;
                vector_multiplier[vector_count] = temp_multiplier;
                vector_shift[vector_count]      = temp_shift[5:0];
                vector_tag[vector_count]        = temp_tag[TAG_WIDTH-1:0];
                vector_expected[vector_count]   = temp_expected;
                vector_count = vector_count + 1;
            end else if (!$feof(vector_file)) begin
                $fatal(1, "malformed vector file near vector %0d", vector_count);
            end
        end
        $fclose(vector_file);

        if (vector_count <= (1 + BURST_COUNT)) begin
            $fatal(1, "not enough vectors for latency/II checks");
        end

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n     = 1'b1;
        out_ready = 1'b1;

        // One isolated transaction proves the nine-cycle no-stall latency.
        drive_vector(0);
        in_valid = 1'b1;
        wait (send_index == 1);
        @(negedge clk);
        in_valid = 1'b0;
        wait (receive_count == 1);

        // A continuous accepted/output burst proves initiation interval one.
        repeat (BURST_COUNT) begin
            @(negedge clk);
            drive_vector(send_index);
            in_valid  = 1'b1;
            out_ready = 1'b1;
        end
        @(negedge clk);
        in_valid  = 1'b0;
        out_ready = 1'b1;
        wait (receive_count == (1 + BURST_COUNT));

        // Remaining directed and random vectors use independent source bubbles
        // and downstream stalls.  An unaccepted request is held unchanged.
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
                // send_index advances only after acceptance.  Therefore equality
                // means this request is still pending even if in_ready changed
                // after the previous rising edge.
                in_valid = in_valid;
            end else if (lfsr[5] | lfsr[9]) begin
                drive_vector(send_index);
                in_valid = 1'b1;
            end else begin
                in_valid = 1'b0;
            end
        end

        @(negedge clk);
        in_valid  = 1'b0;
        out_ready = 1'b1;
        repeat (5) @(posedge clk);

        if (pending_count != 0) begin
            $fatal(1, "scoreboard not empty: %0d", pending_count);
        end
        if (send_index != vector_count) begin
            $fatal(1, "not all vectors accepted: %0d/%0d", send_index, vector_count);
        end

        $display(
            "PASS: pe_requant_lane vectors=%0d latency=%0d cycles II=1 stalls_checked=1",
            vector_count,
            EXPECTED_LATENCY
        );
        $finish;
    end

endmodule
