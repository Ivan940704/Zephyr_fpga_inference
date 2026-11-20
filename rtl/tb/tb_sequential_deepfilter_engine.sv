`timescale 1ns/1ps

module tb_sequential_deepfilter_engine;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg abort = 1'b0;
    reg clear_history = 1'b0;
    reg [15:0] current_frame_id = 16'd0;
    reg frame_start = 1'b0;
    reg frame_done = 1'b0;

    reg spectrum_valid = 1'b0;
    wire spectrum_ready;
    reg [63:0] spectrum_data = 64'd0;
    reg [7:0] spectrum_keep = 8'hff;
    reg spectrum_last = 1'b0;

    reg start = 1'b0;
    wire start_ready;
    wire done;
    wire error;
    reg all_coefficients_valid = 1'b1;

    wire coefficient_req_valid;
    reg coefficient_req_ready = 1'b1;
    wire [10:0] coefficient_req_address;
    reg coefficient_rsp_valid = 1'b0;
    wire coefficient_rsp_ready;
    reg signed [7:0] coefficient_rsp_value = 8'sd1;
    reg coefficient_rsp_error = 1'b0;

    reg output_enable = 1'b0;
    wire output_valid;
    reg output_ready = 1'b0;
    wire [63:0] output_data;
    wire [7:0] output_keep;
    wire output_last;
    wire output_complete;

    wire spectrum_buffer_valid;
    wire [15:0] spectrum_buffer_frame_id;
    wire engine_frame_active;
    wire busy;
    wire [7:0] active_bin;
    wire [2:0] history_depth;
    wire error_valid;
    wire [7:0] error_code;
    wire [31:0] error_detail;

    integer checks = 0;
    integer coefficient_reads = 0;
    integer output_beats = 0;
    integer stall_counter = 0;
    reg [10:0] pending_address = 11'd0;
    reg [63:0] held_output = 64'd0;

    always #5 clk = ~clk;

    initial begin
        #2000000;
        $display("TIMEOUT state=%0d bin=%0d tap=%0d start_ready=%0b req=%0b rsp=%0b output_valid=%0b",
                 dut.state_q, active_bin, dut.tap_q, start_ready,
                 coefficient_req_valid, coefficient_rsp_valid, output_valid);
        fail("global simulation timeout");
    end

    always @(posedge clk) begin
        if ((dut.state_q == 4'd9) && (active_bin[4:0] == 5'd0))
            $display("PROGRESS frame=%0d bin=%0d time=%0t",
                     current_frame_id, active_bin, $time);
    end

    sequential_deepfilter_engine dut (
        .clk(clk),
        .rst_n(rst_n),
        .abort(abort),
        .clear_history(clear_history),
        .current_frame_id(current_frame_id),
        .frame_start(frame_start),
        .frame_done(frame_done),
        .s_axis_spectrum_tvalid(spectrum_valid),
        .s_axis_spectrum_tready(spectrum_ready),
        .s_axis_spectrum_tdata(spectrum_data),
        .s_axis_spectrum_tkeep(spectrum_keep),
        .s_axis_spectrum_tlast(spectrum_last),
        .start(start),
        .start_ready(start_ready),
        .done(done),
        .error(error),
        .all_coefficients_valid(all_coefficients_valid),
        .coefficient_read_req_valid(coefficient_req_valid),
        .coefficient_read_req_ready(coefficient_req_ready),
        .coefficient_read_req_address(coefficient_req_address),
        .coefficient_read_rsp_valid(coefficient_rsp_valid),
        .coefficient_read_rsp_ready(coefficient_rsp_ready),
        .coefficient_read_rsp_value(coefficient_rsp_value),
        .coefficient_read_rsp_error(coefficient_rsp_error),
        .output_enable(output_enable),
        .m_axis_output_tvalid(output_valid),
        .m_axis_output_tready(output_ready),
        .m_axis_output_tdata(output_data),
        .m_axis_output_tkeep(output_keep),
        .m_axis_output_tlast(output_last),
        .output_complete(output_complete),
        .spectrum_buffer_valid(spectrum_buffer_valid),
        .spectrum_buffer_frame_id(spectrum_buffer_frame_id),
        .frame_active(engine_frame_active),
        .busy(busy),
        .active_bin(active_bin),
        .history_depth(history_depth),
        .error_valid(error_valid),
        .error_code(error_code),
        .error_detail(error_detail)
    );

    task fail;
        input [8*96-1:0] message;
        begin
            $display("FAIL %0s time=%0t code=%02x detail=%08x",
                     message, $time, error_code, error_detail);
            $finish;
        end
    endtask

    task check;
        input condition;
        input [8*96-1:0] message;
        begin
            checks = checks + 1;
            if (!condition)
                fail(message);
        end
    endtask

    task send_spectrum_frame;
        input signed [7:0] real_value;
        input signed [7:0] imag_value;
        integer beat;
        integer packed_lane;
        begin
            for (beat = 0; beat < 64; beat = beat + 1) begin
                @(negedge clk);
                spectrum_data = 64'd0;
                for (packed_lane = 0; packed_lane < 4;
                     packed_lane = packed_lane + 1) begin
                    spectrum_data[packed_lane*16 +: 8] = real_value;
                    spectrum_data[packed_lane*16 + 8 +: 8] = imag_value;
                end
                spectrum_last = (beat == 63);
                spectrum_valid = 1'b1;
                while (!spectrum_ready)
                    @(negedge clk);
                @(posedge clk);
            end
            @(negedge clk);
            spectrum_valid = 1'b0;
            spectrum_last = 1'b0;
            spectrum_data = 64'd0;
            @(posedge clk);
        end
    endtask

    task pulse_frame_start;
        begin
            @(negedge clk);
            frame_start = 1'b1;
            @(posedge clk);
            @(negedge clk);
            frame_start = 1'b0;
        end
    endtask

    task launch_engine;
        begin
            while (!start_ready)
                @(negedge clk);
            start = 1'b1;
            @(posedge clk);
            @(negedge clk);
            start = 1'b0;
        end
    endtask

    task wait_engine_done;
        integer watchdog;
        begin
            watchdog = 0;
            while (!done && watchdog < 30000) begin
                @(posedge clk);
                watchdog = watchdog + 1;
            end
            check(done, "engine completion timeout");
            @(posedge clk);
        end
    endtask

    task drain_output;
        input integer first_half_real;
        input integer first_half_imag;
        input integer second_half_real;
        input integer second_half_imag;
        integer expected_real;
        integer expected_imag;
        integer signed got_real;
        integer signed got_imag;
        integer beat;
        begin
            output_enable = 1'b1;
            output_beats = 0;
            stall_counter = 0;
            beat = 0;
            while (beat < 256) begin
                output_ready = ((stall_counter % 5) != 2);
                @(posedge clk);
                stall_counter = stall_counter + 1;
                if (output_valid && !output_ready) begin
                    held_output = output_data;
                    @(posedge clk);
                    check(output_valid && output_data == held_output,
                          "output changed under backpressure");
                    stall_counter = stall_counter + 1;
                end
                if (output_valid && output_ready) begin
                    got_real = $signed(output_data[31:0]);
                    got_imag = $signed(output_data[63:32]);
                    if (beat < 128) begin
                        expected_real = first_half_real;
                        expected_imag = first_half_imag;
                    end else begin
                        expected_real = second_half_real;
                        expected_imag = second_half_imag;
                    end
                    check(got_real == expected_real,
                          "unexpected output real component");
                    check(got_imag == expected_imag,
                          "unexpected output imaginary component");
                    check(output_keep == 8'hff,
                          "output keep must cover all bytes");
                    check(output_last == (beat == 255),
                          "output last position mismatch");
                    beat = beat + 1;
                    output_beats = output_beats + 1;
                end
            end
            @(negedge clk);
            check(output_complete, "missing output complete pulse");
            output_ready = 1'b0;
            // Match the real FSM: output_enable remains asserted throughout
            // the cycle in which it observes output_complete and drops only
            // after the following state transition.
            @(posedge clk);
            #1;
            check(!error_valid,
                  "completion handshake was misclassified as empty output");
            @(negedge clk);
            output_enable = 1'b0;
        end
    endtask

    task pulse_clear_history;
        begin
            @(negedge clk);
            clear_history = 1'b1;
            @(posedge clk);
            @(negedge clk);
            clear_history = 1'b0;
            @(posedge clk);
        end
    endtask

    task complete_frame;
        begin
            @(negedge clk);
            frame_done = 1'b1;
            @(posedge clk);
            @(negedge clk);
            frame_done = 1'b0;
            @(posedge clk);
        end
    endtask

    // One-cycle coefficient response.  Every real and imaginary coefficient
    // is +1, which makes the two-frame expected complex sums easy to audit.
    always @(posedge clk) begin
        if (coefficient_rsp_valid && coefficient_rsp_ready)
            coefficient_rsp_valid <= 1'b0;
        if (coefficient_req_valid && coefficient_req_ready) begin
            if (coefficient_rsp_valid)
                fail("coefficient request while response pending");
            coefficient_rsp_valid <= 1'b1;
            pending_address <= coefficient_req_address;
            coefficient_reads = coefficient_reads + 1;
        end
    end

    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        send_spectrum_frame(8'sd2, 8'sd3);
        check(spectrum_buffer_valid, "frame zero spectrum was not buffered");
        check(spectrum_buffer_frame_id == 16'd0,
              "frame zero spectrum ID mismatch");
        pulse_frame_start();
        check(engine_frame_active, "frame zero did not become active");
        launch_engine();
        wait_engine_done();
        check(coefficient_reads == 1152,
              "frame zero coefficient-read count mismatch");
        drain_output(-1, 5, -1, 5);
        complete_frame();
        check(history_depth == 3'd1, "history depth did not advance");

        current_frame_id = 16'd1;
        send_spectrum_frame(8'sd4, 8'sd5);
        pulse_frame_start();
        launch_engine();
        wait_engine_done();
        check(coefficient_reads == 2304,
              "two-frame coefficient-read count mismatch");
        drain_output(-2, 14, -1, 9);
        complete_frame();
        check(history_depth == 3'd2,
              "second history depth did not advance");
        check(!error && !error_valid,
              "unexpected error during valid two-frame run");

        current_frame_id = 16'd2;
        send_spectrum_frame(8'sd6, 8'sd7);
        pulse_frame_start();
        pulse_clear_history();
        check(history_depth == 3'd0,
              "clear history did not reset visible depth");
        launch_engine();
        wait_engine_done();
        check(coefficient_reads == 3456,
              "clear-history frame coefficient-read count mismatch");
        // Only the current (6+j7) frame may contribute after clear:
        // (6+j7)*(1+j1) = -1+j13 for every band/order.
        drain_output(-1, 13, -1, 13);
        complete_frame();
        check(history_depth == 3'd1,
              "clear-history frame did not become the new history root");
        check(!error && !error_valid,
              "unexpected error during clear-history frame");

        current_frame_id = 16'd3;
        @(negedge clk);
        spectrum_keep = 8'h7f;
        spectrum_data = 64'd0;
        spectrum_valid = 1'b1;
        spectrum_last = 1'b0;
        while (!spectrum_ready)
            @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        spectrum_valid = 1'b0;
        spectrum_keep = 8'hff;
        @(posedge clk);
        check(error_valid && error_code == 8'h70,
              "malformed spectrum keep did not latch fault");

        $display("PASS tb_sequential_deepfilter_engine checks=%0d coefficient_reads=%0d output_beats=%0d",
                 checks, coefficient_reads, output_beats);
        $finish;
    end
endmodule
