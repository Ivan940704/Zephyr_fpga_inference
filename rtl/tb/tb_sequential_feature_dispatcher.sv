`timescale 1ns/1ps

module tb_sequential_feature_dispatcher;
    reg clk;
    reg rst_n;
    reg abort;
    reg [15:0] current_frame_id;
    reg frame_start;
    reg frame_done;

    reg s_axis_fb_tvalid;
    wire s_axis_fb_tready;
    reg [63:0] s_axis_fb_tdata;
    reg [7:0] s_axis_fb_tkeep;
    reg s_axis_fb_tlast;

    reg feature_req_valid;
    wire feature_req_ready;
    reg [3:0] feature_req_stage_id;
    reg [1:0] feature_req_branch;
    reg [1:0] feature_req_context;
    reg [9:0] feature_req_source;
    reg [7:0] feature_req_tag;
    wire feature_rsp_valid;
    reg feature_rsp_ready;
    wire signed [7:0] feature_rsp_value;
    wire [7:0] feature_rsp_tag;
    wire feature_rsp_error;

    reg sb_buffer_valid;
    wire sb_read_valid;
    wire sb_read_ready;
    wire [9:0] sb_read_index;
    wire [15:0] sb_read_frame_id;
    reg sb_read_rsp_valid;
    wire sb_read_rsp_ready;
    reg signed [7:0] sb_read_rsp_data;
    reg sb_read_rsp_error;

    wire fb_buffer_valid;
    wire [15:0] fb_buffer_frame_id;
    wire frame_active;
    wire busy;
    wire error_valid;
    wire [7:0] error_code;
    wire [31:0] error_detail;

    reg sb_pending;
    reg [9:0] sb_pending_index;
    reg expect_sb_read;
    integer expected_sb_index;
    integer sb_read_count;
    integer sb_read_total;
    integer cycle_count;
    integer failures;
    integer checks;

    sequential_feature_dispatcher dut (
        .clk(clk),
        .rst_n(rst_n),
        .abort(abort),
        .current_frame_id(current_frame_id),
        .frame_start(frame_start),
        .frame_done(frame_done),
        .s_axis_fb_tvalid(s_axis_fb_tvalid),
        .s_axis_fb_tready(s_axis_fb_tready),
        .s_axis_fb_tdata(s_axis_fb_tdata),
        .s_axis_fb_tkeep(s_axis_fb_tkeep),
        .s_axis_fb_tlast(s_axis_fb_tlast),
        .feature_req_valid(feature_req_valid),
        .feature_req_ready(feature_req_ready),
        .feature_req_stage_id(feature_req_stage_id),
        .feature_req_branch(feature_req_branch),
        .feature_req_context(feature_req_context),
        .feature_req_source(feature_req_source),
        .feature_req_tag(feature_req_tag),
        .feature_rsp_valid(feature_rsp_valid),
        .feature_rsp_ready(feature_rsp_ready),
        .feature_rsp_value(feature_rsp_value),
        .feature_rsp_tag(feature_rsp_tag),
        .feature_rsp_error(feature_rsp_error),
        .sb_buffer_valid(sb_buffer_valid),
        .sb_read_valid(sb_read_valid),
        .sb_read_ready(sb_read_ready),
        .sb_read_index(sb_read_index),
        .sb_read_frame_id(sb_read_frame_id),
        .sb_read_rsp_valid(sb_read_rsp_valid),
        .sb_read_rsp_ready(sb_read_rsp_ready),
        .sb_read_rsp_data(sb_read_rsp_data),
        .sb_read_rsp_error(sb_read_rsp_error),
        .fb_buffer_valid(fb_buffer_valid),
        .fb_buffer_frame_id(fb_buffer_frame_id),
        .frame_active(frame_active),
        .busy(busy),
        .error_valid(error_valid),
        .error_code(error_code),
        .error_detail(error_detail)
    );

    always #5 clk = ~clk;

    function automatic [7:0] expected_fb_byte;
        input integer index;
        begin
            expected_fb_byte = (8'h20 + index * 3) & 8'hff;
        end
    endfunction

    function automatic [7:0] expected_sb_byte;
        input integer index;
        begin
            expected_sb_byte = (8'ha5 ^ (index * 7)) & 8'hff;
        end
    endfunction

    task automatic fail;
        input string message;
        begin
            failures = failures + 1;
            $display("FAIL: %s time=%0t state=%0d code=%02x detail=%08x",
                     message, $time, dut.state_q, error_code,
                     error_detail);
        end
    endtask

    task automatic check;
        input bit condition;
        input string message;
        begin
            checks = checks + 1;
            if (!condition)
                fail(message);
        end
    endtask

    task automatic reset_dut;
        begin
            @(negedge clk);
            rst_n = 1'b0;
            abort = 1'b0;
            frame_start = 1'b0;
            frame_done = 1'b0;
            s_axis_fb_tvalid = 1'b0;
            s_axis_fb_tkeep = 8'd0;
            s_axis_fb_tlast = 1'b0;
            feature_req_valid = 1'b0;
            feature_rsp_ready = 1'b0;
            sb_buffer_valid = 1'b0;
            expect_sb_read = 1'b0;
            repeat (4) @(posedge clk);
            @(negedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic send_fullband_packet;
        integer beat;
        integer lane;
        reg [63:0] packet_word;
        begin
            for (beat = 0; beat < 8; beat = beat + 1) begin
                packet_word = 64'd0;
                for (lane = 0; lane < 8; lane = lane + 1)
                    packet_word[lane*8 +: 8] =
                        expected_fb_byte(beat*8 + lane);
                @(negedge clk);
                s_axis_fb_tdata = packet_word;
                s_axis_fb_tkeep = 8'hff;
                s_axis_fb_tlast = (beat == 7);
                s_axis_fb_tvalid = 1'b1;
                while (!s_axis_fb_tready)
                    @(negedge clk);
                @(posedge clk);
            end
            @(negedge clk);
            s_axis_fb_tvalid = 1'b0;
            s_axis_fb_tlast = 1'b0;
            s_axis_fb_tkeep = 8'd0;
        end
    endtask

    task automatic pulse_frame_start;
        begin
            @(negedge clk);
            frame_start = 1'b1;
            @(posedge clk);
            @(negedge clk);
            frame_start = 1'b0;
        end
    endtask

    task automatic request_feature;
        input [3:0] stage_id;
        input [1:0] branch_id;
        input [1:0] context_id;
        input [9:0] source_id;
        input [7:0] tag;
        input integer sb_index;
        input [7:0] expected_value;
        integer timeout;
        reg signed [7:0] held_value;
        reg [7:0] held_tag;
        begin
            expect_sb_read = (sb_index >= 0);
            expected_sb_index = sb_index;
            @(negedge clk);
            feature_req_stage_id = stage_id;
            feature_req_branch = branch_id;
            feature_req_context = context_id;
            feature_req_source = source_id;
            feature_req_tag = tag;
            feature_req_valid = 1'b1;
            timeout = 0;
            while (!feature_req_ready && timeout < 100) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            check(timeout < 100, "feature request timed out");
            @(posedge clk);
            @(negedge clk);
            feature_req_valid = 1'b0;

            timeout = 0;
            while (!feature_rsp_valid && timeout < 100) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            check(timeout < 100, "feature response timed out");
            check(!feature_rsp_error, "feature response raised error");
            check(feature_rsp_tag == tag, "feature response tag mismatch");
            check(feature_rsp_value === $signed(expected_value),
                  "feature response value mismatch");
            check(!expect_sb_read, "expected subband read was not issued");

            held_value = feature_rsp_value;
            held_tag = feature_rsp_tag;
            repeat (2) begin
                @(posedge clk);
                #1;
                check(feature_rsp_valid &&
                      (feature_rsp_value === held_value) &&
                      (feature_rsp_tag === held_tag),
                      "feature response changed under backpressure");
            end
            @(negedge clk);
            feature_rsp_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            feature_rsp_ready = 1'b0;
        end
    endtask

    assign sb_read_ready = !sb_pending && !sb_read_rsp_valid &&
                           (cycle_count[1:0] != 2'b10);

    always @(posedge clk) begin
        if (!rst_n) begin
            sb_pending <= 1'b0;
            sb_pending_index <= 10'd0;
            sb_read_rsp_valid <= 1'b0;
            sb_read_rsp_data <= 8'sd0;
            sb_read_rsp_error <= 1'b0;
            sb_read_count <= 0;
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            if (sb_read_valid && sb_read_ready) begin
                sb_pending <= 1'b1;
                sb_pending_index <= sb_read_index;
                sb_read_count <= sb_read_count + 1;
                sb_read_total <= sb_read_total + 1;
                check(expect_sb_read, "unexpected subband read");
                check(sb_read_index == expected_sb_index,
                      "subband payload index mismatch");
                check(sb_read_frame_id == current_frame_id,
                      "subband read frame ID mismatch");
                expect_sb_read <= 1'b0;
            end
            if (sb_pending && !sb_read_rsp_valid) begin
                sb_read_rsp_valid <= 1'b1;
                sb_read_rsp_data <= expected_sb_byte(sb_pending_index);
            end
            if (sb_read_rsp_valid && sb_read_rsp_ready) begin
                sb_read_rsp_valid <= 1'b0;
                sb_pending <= 1'b0;
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        abort = 1'b0;
        current_frame_id = 16'd0;
        frame_start = 1'b0;
        frame_done = 1'b0;
        s_axis_fb_tvalid = 1'b0;
        s_axis_fb_tdata = 64'd0;
        s_axis_fb_tkeep = 8'd0;
        s_axis_fb_tlast = 1'b0;
        feature_req_valid = 1'b0;
        feature_req_stage_id = 4'd0;
        feature_req_branch = 2'd0;
        feature_req_context = 2'd0;
        feature_req_source = 10'd0;
        feature_req_tag = 8'd0;
        feature_rsp_ready = 1'b0;
        sb_buffer_valid = 1'b0;
        sb_read_rsp_valid = 1'b0;
        sb_read_rsp_data = 8'sd0;
        sb_read_rsp_error = 1'b0;
        sb_pending = 1'b0;
        expect_sb_read = 1'b0;
        expected_sb_index = -1;
        failures = 0;
        checks = 0;
        sb_read_total = 0;

        repeat (6) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        send_fullband_packet();
        check(fb_buffer_valid, "fullband packet did not become valid");
        check(fb_buffer_frame_id == 16'd0,
              "fullband packet frame ID mismatch");
        check(!s_axis_fb_tready,
              "dispatcher accepted a second packet before frame completion");

        pulse_frame_start();
        check(frame_active, "frame did not become active");

        request_feature(4'd0, 2'd0, 2'd0, 10'd0, 8'h10, -1,
                        expected_fb_byte(0));
        request_feature(4'd0, 2'd0, 2'd0, 10'd17, 8'h11, -1,
                        expected_fb_byte(17));
        request_feature(4'd0, 2'd0, 2'd0, 10'd63, 8'h12, -1,
                        expected_fb_byte(63));

        // Mailbox payload: SB0 0..183, SB1 184..465, SB2 466..781.
        sb_buffer_valid = 1'b1;
        request_feature(4'd3, 2'd1, 2'd0, 10'd0, 8'h20, 0,
                        expected_sb_byte(0));
        request_feature(4'd3, 2'd1, 2'd3, 10'd45, 8'h21, 183,
                        expected_sb_byte(183));
        request_feature(4'd6, 2'd2, 2'd0, 10'd0, 8'h22, 184,
                        expected_sb_byte(184));
        request_feature(4'd6, 2'd2, 2'd2, 10'd93, 8'h23, 465,
                        expected_sb_byte(465));
        request_feature(4'd9, 2'd3, 2'd0, 10'd0, 8'h24, 466,
                        expected_sb_byte(466));
        request_feature(4'd9, 2'd3, 2'd1, 10'd157, 8'h25, 781,
                        expected_sb_byte(781));
        check(sb_read_count == 6,
              "dispatcher did not issue all six mapped subband reads");

        @(negedge clk);
        frame_done = 1'b1;
        @(posedge clk);
        @(negedge clk);
        frame_done = 1'b0;
        current_frame_id = 16'd1;
        sb_buffer_valid = 1'b0;
        check(!fb_buffer_valid && !frame_active,
              "frame completion did not release the ingress buffer");
        check(s_axis_fb_tready,
              "dispatcher did not accept the next frame after completion");

        // A partial keep mask is a reset-required packet fault.
        @(negedge clk);
        s_axis_fb_tvalid = 1'b1;
        s_axis_fb_tdata = 64'h8877665544332211;
        s_axis_fb_tkeep = 8'hfe;
        s_axis_fb_tlast = 1'b0;
        @(posedge clk);
        @(negedge clk);
        s_axis_fb_tvalid = 1'b0;
        check(error_valid && (error_code == 8'h50),
              "partial TKEEP did not latch ERR_AXIS_KEEP");

        current_frame_id = 16'd0;
        reset_dut();
        @(negedge clk);
        s_axis_fb_tvalid = 1'b1;
        s_axis_fb_tdata = 64'h0123456789abcdef;
        s_axis_fb_tkeep = 8'hff;
        s_axis_fb_tlast = 1'b1;
        @(posedge clk);
        @(negedge clk);
        s_axis_fb_tvalid = 1'b0;
        check(error_valid && (error_code == 8'h51),
              "early TLAST did not latch ERR_AXIS_LAST");

        reset_dut();
        send_fullband_packet();
        pulse_frame_start();
        @(negedge clk);
        feature_req_stage_id = 4'd3;
        feature_req_branch = 2'd0;
        feature_req_context = 2'd0;
        feature_req_source = 10'd0;
        feature_req_tag = 8'hf0;
        feature_req_valid = 1'b1;
        #1;
        check(feature_req_ready,
              "invalid tuple was not accepted for deterministic faulting");
        @(posedge clk);
        @(negedge clk);
        feature_req_valid = 1'b0;
        check(error_valid && (error_code == 8'h55),
              "invalid feature tuple did not latch ERR_FEATURE_REQ");

        if (failures == 0)
            $display("PASS tb_sequential_feature_dispatcher checks=%0d sb_reads=%0d",
                     checks, sb_read_total);
        else
            $fatal(1,
                "FAIL tb_sequential_feature_dispatcher errors=%0d checks=%0d",
                failures, checks);
        #20;
        $finish;
    end
endmodule
