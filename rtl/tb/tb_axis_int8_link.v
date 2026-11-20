`timescale 1ns/1ps

module tb_axis_int8_link;
    localparam DATA_WIDTH = 64;
    localparam KEEP_WIDTH = 8;

    reg aclk = 1'b0;
    reg aresetn;

    reg [DATA_WIDTH-1:0] s_axis_tdata;
    reg [KEEP_WIDTH-1:0] s_axis_tkeep;
    reg s_axis_tvalid;
    wire s_axis_tready;
    reg s_axis_tlast;

    wire [DATA_WIDTH-1:0] m_axis_tdata;
    wire [KEEP_WIDTH-1:0] m_axis_tkeep;
    wire m_axis_tvalid;
    reg m_axis_tready;
    wire m_axis_tlast;
    wire protocol_error;

    reg [7:0] expected_data [0:2047];
    reg       expected_last [0:2047];
    integer expected_count;
    integer received_count;
    integer received_packets;
    integer errors;
    integer ready_cycle;
    integer output_stall_cycles;
    integer lane;
    integer last_lane;
    reg ready_pattern_enable;

    reg stalled_previous;
    reg [DATA_WIDTH-1:0] stalled_data;
    reg [KEEP_WIDTH-1:0] stalled_keep;
    reg stalled_last;

    always #5 aclk = ~aclk;

    axis_int8_loopback #(
        .AXIS_DATA_WIDTH(DATA_WIDTH),
        .AXIS_KEEP_WIDTH(KEEP_WIDTH)
    ) dut (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .protocol_error(protocol_error)
    );

    // Deterministic sink stalls exercise TVALID stability and propagate
    // backpressure through both adapters to the source interface.
    always @(negedge aclk) begin
        if (!aresetn) begin
            ready_cycle = 0;
            m_axis_tready = 1'b0;
        end else if (!ready_pattern_enable) begin
            m_axis_tready = 1'b0;
        end else begin
            ready_cycle = ready_cycle + 1;
            m_axis_tready = ((ready_cycle % 7) != 2) &&
                            ((ready_cycle % 11) != 5) &&
                            ((ready_cycle % 13) != 9);
        end
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            stalled_previous <= 1'b0;
        end else begin
            if (stalled_previous) begin
                if (!m_axis_tvalid ||
                    (m_axis_tdata !== stalled_data) ||
                    (m_axis_tkeep !== stalled_keep) ||
                    (m_axis_tlast !== stalled_last)) begin
                    $display("ERROR AXIS master payload changed under backpressure");
                    errors = errors + 1;
                end
            end

            stalled_previous <= m_axis_tvalid && !m_axis_tready;
            if (m_axis_tvalid && !m_axis_tready) begin
                stalled_data <= m_axis_tdata;
                stalled_keep <= m_axis_tkeep;
                stalled_last <= m_axis_tlast;
                output_stall_cycles = output_stall_cycles + 1;
            end

            if (m_axis_tvalid && m_axis_tready) begin
                if (m_axis_tkeep == 0) begin
                    $display("ERROR AXIS master emitted zero TKEEP");
                    errors = errors + 1;
                end

                last_lane = -1;
                for (lane = 0; lane < KEEP_WIDTH; lane = lane + 1)
                    if (m_axis_tkeep[lane])
                        last_lane = lane;

                for (lane = 0; lane < KEEP_WIDTH; lane = lane + 1) begin
                    if (m_axis_tkeep[lane]) begin
                        if (received_count >= expected_count) begin
                            $display("ERROR AXIS produced unexpected byte lane=%0d data=%h",
                                     lane, m_axis_tdata[lane*8 +: 8]);
                            errors = errors + 1;
                        end else begin
                            if (m_axis_tdata[lane*8 +: 8] !==
                                expected_data[received_count]) begin
                                $display("ERROR AXIS byte=%0d got=%h expected=%h",
                                         received_count,
                                         m_axis_tdata[lane*8 +: 8],
                                         expected_data[received_count]);
                                errors = errors + 1;
                            end
                            if ((lane == last_lane) &&
                                (m_axis_tlast !== expected_last[received_count])) begin
                                $display("ERROR AXIS TLAST byte=%0d got=%0d expected=%0d",
                                         received_count, m_axis_tlast,
                                         expected_last[received_count]);
                                errors = errors + 1;
                            end
                            if ((lane != last_lane) && expected_last[received_count]) begin
                                $display("ERROR packet boundary occurred before beat end byte=%0d",
                                         received_count);
                                errors = errors + 1;
                            end
                        end
                        received_count = received_count + 1;
                    end
                end
                if (m_axis_tlast)
                    received_packets = received_packets + 1;
            end
        end
    end

    task reset_dut;
        begin
            @(negedge aclk);
            aresetn = 1'b0;
            s_axis_tvalid = 1'b0;
            s_axis_tdata = 0;
            s_axis_tkeep = 0;
            s_axis_tlast = 1'b0;
            repeat (3) @(posedge aclk);
            @(negedge aclk);
            aresetn = 1'b1;
        end
    endtask

    task send_raw_beat;
        input [63:0] data;
        input [7:0] keep;
        input last;
        integer accepted;
        begin
            @(negedge aclk);
            s_axis_tdata = data;
            s_axis_tkeep = keep;
            s_axis_tlast = last;
            s_axis_tvalid = 1'b1;
            accepted = 0;
            while (!accepted) begin
                @(posedge aclk);
                if (s_axis_tready)
                    accepted = 1;
            end
            @(negedge aclk);
            s_axis_tvalid = 1'b0;
            s_axis_tdata = 0;
            s_axis_tkeep = 0;
            s_axis_tlast = 1'b0;
        end
    endtask

    task send_contiguous_packet;
        input integer length;
        input integer base_value;
        input integer gap_seed;
        integer position;
        integer beat_bytes;
        integer local_lane;
        integer gap_cycles;
        reg [63:0] beat_data;
        reg [7:0] beat_keep;
        begin
            position = 0;
            while (position < length) begin
                beat_data = 64'd0;
                beat_keep = 8'd0;
                beat_bytes = length - position;
                if (beat_bytes > 8)
                    beat_bytes = 8;
                for (local_lane = 0; local_lane < beat_bytes;
                     local_lane = local_lane + 1) begin
                    beat_data[local_lane*8 +: 8]
                        = (base_value + position + local_lane) & 8'hff;
                    beat_keep[local_lane] = 1'b1;
                    expected_data[expected_count]
                        = (base_value + position + local_lane) & 8'hff;
                    expected_last[expected_count]
                        = ((position + local_lane) == (length - 1));
                    expected_count = expected_count + 1;
                end

                gap_cycles = ((position / 8) + gap_seed) % 4;
                repeat (gap_cycles) @(posedge aclk);
                send_raw_beat(beat_data, beat_keep,
                              (position + beat_bytes) == length);
                position = position + beat_bytes;
            end
        end
    endtask

    task send_noncontiguous_packet;
        integer local_lane;
        reg [7:0] keep_pattern;
        begin
            keep_pattern = 8'b1010_1101;
            for (local_lane = 0; local_lane < 8; local_lane = local_lane + 1) begin
                if (keep_pattern[local_lane]) begin
                    expected_data[expected_count] = 8'ha0 + local_lane;
                    expected_last[expected_count] = (local_lane == 7);
                    expected_count = expected_count + 1;
                end
            end
            send_raw_beat(64'ha7_a6_a5_a4_a3_a2_a1_a0, keep_pattern, 1'b1);
        end
    endtask

    integer timeout;
    initial begin
        errors = 0;
        expected_count = 0;
        received_count = 0;
        received_packets = 0;
        output_stall_cycles = 0;
        ready_pattern_enable = 1'b0;
        aresetn = 1'b0;
        s_axis_tdata = 0;
        s_axis_tkeep = 0;
        s_axis_tvalid = 0;
        s_axis_tlast = 0;
        m_axis_tready = 0;
        stalled_previous = 0;

        reset_dut();

        // Fill the complete loopback, hold its master output, then reset.  No
        // stale beat may survive the reset.
        send_raw_beat(64'h8877_6655_4433_2211, 8'hff, 1'b1);
        timeout = 0;
        while (!m_axis_tvalid && timeout < 100) begin
            @(posedge aclk);
            timeout = timeout + 1;
        end
        if (!m_axis_tvalid) begin
            $display("ERROR reset test never filled AXIS output");
            errors = errors + 1;
        end
        reset_dut();
        @(posedge aclk); #1;
        if (m_axis_tvalid || protocol_error) begin
            $display("ERROR reset did not clear AXIS link state");
            errors = errors + 1;
        end

        // A malformed zero-keep beat is consumed and reported rather than
        // deadlocking the source.
        send_raw_beat(64'hdead_beef_cafe_f00d, 8'h00, 1'b1);
        @(posedge aclk); #1;
        if (!protocol_error) begin
            $display("ERROR zero-TKEEP transfer did not set protocol_error");
            errors = errors + 1;
        end
        reset_dut();

        ready_pattern_enable = 1'b1;
        send_contiguous_packet(1,   8'h10, 0);
        send_contiguous_packet(8,   8'h20, 1);
        send_contiguous_packet(13,  8'h30, 2);
        send_contiguous_packet(46,  8'h40, 3);
        send_contiguous_packet(94,  8'h60, 4);
        send_contiguous_packet(158, 8'h80, 5);
        send_noncontiguous_packet();

        timeout = 0;
        while ((received_count < expected_count) && timeout < 20000) begin
            @(posedge aclk);
            timeout = timeout + 1;
        end
        repeat (5) @(posedge aclk);

        if (timeout >= 20000) begin
            $display("ERROR AXIS loopback timeout received=%0d expected=%0d",
                     received_count, expected_count);
            errors = errors + 1;
        end
        if (received_count != expected_count) begin
            $display("ERROR AXIS byte count got=%0d expected=%0d",
                     received_count, expected_count);
            errors = errors + 1;
        end
        if (expected_count != 325) begin
            $display("ERROR test construction expected_count=%0d expected=325",
                     expected_count);
            errors = errors + 1;
        end
        if (received_packets != 7) begin
            $display("ERROR AXIS packet count got=%0d expected=7",
                     received_packets);
            errors = errors + 1;
        end
        if (protocol_error) begin
            $display("ERROR valid AXIS traffic raised protocol_error");
            errors = errors + 1;
        end
        if (output_stall_cycles == 0) begin
            $display("ERROR AXIS test did not exercise output backpressure");
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("AXIS_METRIC bytes=%0d packets=%0d output_stall_cycles=%0d",
                     received_count, received_packets, output_stall_cycles);
            $display("PASS tb_axis_int8_link");
        end else begin
            $fatal(1, "FAIL tb_axis_int8_link errors=%0d", errors);
        end
        $finish;
    end
endmodule
