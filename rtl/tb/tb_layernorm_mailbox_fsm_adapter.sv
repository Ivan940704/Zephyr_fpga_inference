`timescale 1ns/1ps

module tb_layernorm_mailbox_fsm_adapter;
    localparam integer FRAME_ID_WIDTH = 16;

    reg clk;
    reg rst_n;
    reg abort;
    reg fb_projection_start;
    reg frame_done;
    reg fsm_fb_result_valid;
    wire fsm_fb_result_ready;
    wire fsm_ps_subbands_valid;
    reg fsm_ps_subbands_ready;

    reg fb_coefficient_valid;
    wire fb_coefficient_ready;
    reg signed [7:0] fb_coefficient_value;
    reg [8:0] fb_coefficient_index;
    reg fb_coefficient_last;

    wire mailbox_fb_begin_valid;
    wire mailbox_fb_begin_ready;
    wire [15:0] mailbox_fb_begin_frame_id;
    wire mailbox_fb_begin_slot;
    wire mailbox_fb_data_valid;
    wire mailbox_fb_data_ready;
    wire [7:0] mailbox_fb_data;
    wire mailbox_fb_data_last;
    wire fb_published_valid;
    wire fb_published_slot;
    wire [15:0] fb_published_frame_id;

    wire mailbox_ps_subbands_valid;
    wire mailbox_ps_subbands_ready;
    wire mailbox_ps_subbands_slot;
    wire [15:0] mailbox_ps_subbands_frame_id;
    wire mailbox_sb_data_valid;
    wire mailbox_sb_data_ready;
    wire [7:0] mailbox_sb_data;
    wire [9:0] mailbox_sb_data_index;
    wire mailbox_sb_data_last;
    wire sb_released_valid;
    wire sb_released_slot;
    wire [15:0] sb_released_frame_id;

    reg sb_read_valid;
    wire sb_read_ready;
    reg [9:0] sb_read_index;
    reg [15:0] sb_read_frame_id;
    wire sb_read_rsp_valid;
    reg sb_read_rsp_ready;
    wire signed [7:0] sb_read_rsp_data;
    wire sb_read_rsp_error;
    wire [15:0] current_frame_id;
    wire fb_publish_complete;
    wire sb_buffer_valid;
    wire adapter_quiescent;
    wire adapter_error_valid;
    wire [7:0] adapter_error_code;
    wire [15:0] adapter_error_detail;

    reg ps_bram_en;
    reg [3:0] ps_bram_we;
    reg [9:0] ps_bram_addr;
    reg [31:0] ps_bram_wdata;
    wire [31:0] ps_bram_rdata;
    wire ps_bram_rvalid;
    reg ps_fb_release_valid;
    wire ps_fb_release_ready;
    reg ps_fb_release_slot;
    reg [15:0] ps_fb_release_frame_id;
    reg ps_sb_claim_valid;
    wire ps_sb_claim_ready;
    reg ps_sb_claim_slot;
    reg [15:0] ps_sb_claim_frame_id;
    reg ps_sb_commit_valid;
    wire ps_sb_commit_ready;
    reg ps_sb_commit_slot;
    reg [15:0] ps_sb_commit_frame_id;
    wire sb_committed_valid;
    wire sb_committed_slot;
    wire [15:0] sb_committed_frame_id;
    wire mailbox_error_valid;
    wire [7:0] mailbox_error_code;
    wire [3:0] mailbox_fb_slot_states;

    integer accepted_sb_bytes;
    integer failures;
    reg captured_fb_slot;
    reg captured_fb_publish;

    layernorm_mailbox_fsm_adapter u_adapter (
        .clk(clk),
        .rst_n(rst_n),
        .abort(abort),
        .fb_projection_start(fb_projection_start),
        .frame_done(frame_done),
        .fsm_fb_result_valid(fsm_fb_result_valid),
        .fsm_fb_result_ready(fsm_fb_result_ready),
        .fsm_ps_subbands_valid(fsm_ps_subbands_valid),
        .fsm_ps_subbands_ready(fsm_ps_subbands_ready),
        .fb_coefficient_valid(fb_coefficient_valid),
        .fb_coefficient_ready(fb_coefficient_ready),
        .fb_coefficient_value(fb_coefficient_value),
        .fb_coefficient_index(fb_coefficient_index),
        .fb_coefficient_last(fb_coefficient_last),
        .mailbox_fb_begin_valid(mailbox_fb_begin_valid),
        .mailbox_fb_begin_ready(mailbox_fb_begin_ready),
        .mailbox_fb_begin_frame_id(mailbox_fb_begin_frame_id),
        .mailbox_fb_begin_slot(mailbox_fb_begin_slot),
        .mailbox_fb_data_valid(mailbox_fb_data_valid),
        .mailbox_fb_data_ready(mailbox_fb_data_ready),
        .mailbox_fb_data(mailbox_fb_data),
        .mailbox_fb_data_last(mailbox_fb_data_last),
        .mailbox_fb_published_valid(fb_published_valid),
        .mailbox_fb_published_slot(fb_published_slot),
        .mailbox_fb_published_frame_id(fb_published_frame_id),
        .mailbox_ps_subbands_valid(mailbox_ps_subbands_valid),
        .mailbox_ps_subbands_ready(mailbox_ps_subbands_ready),
        .mailbox_ps_subbands_slot(mailbox_ps_subbands_slot),
        .mailbox_ps_subbands_frame_id(mailbox_ps_subbands_frame_id),
        .mailbox_sb_data_valid(mailbox_sb_data_valid),
        .mailbox_sb_data_ready(mailbox_sb_data_ready),
        .mailbox_sb_data(mailbox_sb_data),
        .mailbox_sb_data_index(mailbox_sb_data_index),
        .mailbox_sb_data_last(mailbox_sb_data_last),
        .mailbox_sb_released_valid(sb_released_valid),
        .mailbox_sb_released_slot(sb_released_slot),
        .mailbox_sb_released_frame_id(sb_released_frame_id),
        .sb_read_valid(sb_read_valid),
        .sb_read_ready(sb_read_ready),
        .sb_read_index(sb_read_index),
        .sb_read_frame_id(sb_read_frame_id),
        .sb_read_rsp_valid(sb_read_rsp_valid),
        .sb_read_rsp_ready(sb_read_rsp_ready),
        .sb_read_rsp_data(sb_read_rsp_data),
        .sb_read_rsp_error(sb_read_rsp_error),
        .current_frame_id(current_frame_id),
        .fb_publish_complete(fb_publish_complete),
        .sb_buffer_valid(sb_buffer_valid),
        .quiescent(adapter_quiescent),
        .error_valid(adapter_error_valid),
        .error_code(adapter_error_code),
        .error_detail(adapter_error_detail)
    );

    layernorm_mailbox #(
        .FRAME_ID_WIDTH(FRAME_ID_WIDTH),
        .TIMEOUT_CYCLES(0)
    ) u_mailbox (
        .clk(clk),
        .rst_n(rst_n),
        .abort(abort),
        .clear_error(1'b0),
        .ps_bram_en(ps_bram_en),
        .ps_bram_we(ps_bram_we),
        .ps_bram_addr(ps_bram_addr),
        .ps_bram_wdata(ps_bram_wdata),
        .ps_bram_rdata(ps_bram_rdata),
        .ps_bram_rvalid(ps_bram_rvalid),
        .fb_begin_valid(mailbox_fb_begin_valid),
        .fb_begin_ready(mailbox_fb_begin_ready),
        .fb_begin_frame_id(mailbox_fb_begin_frame_id),
        .fb_begin_slot(mailbox_fb_begin_slot),
        .fb_data_valid(mailbox_fb_data_valid),
        .fb_data_ready(mailbox_fb_data_ready),
        .fb_data(mailbox_fb_data),
        .fb_data_last(mailbox_fb_data_last),
        .fb_published_valid(fb_published_valid),
        .fb_published_slot(fb_published_slot),
        .fb_published_frame_id(fb_published_frame_id),
        .ps_fb_release_valid(ps_fb_release_valid),
        .ps_fb_release_ready(ps_fb_release_ready),
        .ps_fb_release_slot(ps_fb_release_slot),
        .ps_fb_release_frame_id(ps_fb_release_frame_id),
        .ps_sb_claim_valid(ps_sb_claim_valid),
        .ps_sb_claim_ready(ps_sb_claim_ready),
        .ps_sb_claim_slot(ps_sb_claim_slot),
        .ps_sb_claim_frame_id(ps_sb_claim_frame_id),
        .ps_sb_commit_valid(ps_sb_commit_valid),
        .ps_sb_commit_ready(ps_sb_commit_ready),
        .ps_sb_commit_slot(ps_sb_commit_slot),
        .ps_sb_commit_frame_id(ps_sb_commit_frame_id),
        .sb_committed_valid(sb_committed_valid),
        .sb_committed_slot(sb_committed_slot),
        .sb_committed_frame_id(sb_committed_frame_id),
        .ps_subbands_valid(mailbox_ps_subbands_valid),
        .ps_subbands_ready(mailbox_ps_subbands_ready),
        .ps_subbands_slot(mailbox_ps_subbands_slot),
        .ps_subbands_frame_id(mailbox_ps_subbands_frame_id),
        .sb_data_valid(mailbox_sb_data_valid),
        .sb_data_ready(mailbox_sb_data_ready),
        .sb_data(mailbox_sb_data),
        .sb_data_index(mailbox_sb_data_index),
        .sb_data_last(mailbox_sb_data_last),
        .sb_released_valid(sb_released_valid),
        .sb_released_slot(sb_released_slot),
        .sb_released_frame_id(sb_released_frame_id),
        .fb_slot_states(mailbox_fb_slot_states),
        .error_valid(mailbox_error_valid),
        .error_code(mailbox_error_code)
    );

    always #5 clk = ~clk;

    function automatic [7:0] expected_fb_byte;
        input integer byte_index;
        begin
            expected_fb_byte = (8'h31 + byte_index * 7) & 8'hff;
        end
    endfunction

    function automatic [7:0] expected_sb_byte;
        input integer byte_index;
        begin
            expected_sb_byte = (8'h5a ^ (byte_index * 13)) & 8'hff;
        end
    endfunction

    function automatic [31:0] expected_sb_word;
        input integer word_index;
        integer lane;
        integer byte_index;
        reg [31:0] value;
        begin
            value = 32'd0;
            for (lane = 0; lane < 4; lane = lane + 1) begin
                byte_index = word_index * 4 + lane;
                if (byte_index < 782)
                    value[lane*8 +: 8] = expected_sb_byte(byte_index);
            end
            expected_sb_word = value;
        end
    endfunction

    task automatic fail;
        input string message;
        begin
            failures = failures + 1;
            $display("FAIL: %s", message);
        end
    endtask

    task automatic pulse_projection_start;
        begin
            @(negedge clk);
            fb_projection_start = 1'b1;
            @(posedge clk);
            @(negedge clk);
            fb_projection_start = 1'b0;
        end
    endtask

    task automatic send_fb_coefficients;
        integer byte_index;
        begin
            for (byte_index = 0; byte_index < 64;
                 byte_index = byte_index + 1) begin
                @(negedge clk);
                if ((byte_index % 9) == 4) begin
                    fb_coefficient_valid = 1'b0;
                    @(posedge clk);
                    @(negedge clk);
                end
                fb_coefficient_valid = 1'b1;
                fb_coefficient_value = expected_fb_byte(byte_index);
                fb_coefficient_index = byte_index[8:0];
                fb_coefficient_last = (byte_index == 63);
                while (!fb_coefficient_ready)
                    @(negedge clk);
                @(posedge clk);
            end
            @(negedge clk);
            fb_coefficient_valid = 1'b0;
            fb_coefficient_last = 1'b0;
        end
    endtask

    task automatic read_fb_word;
        input integer word_index;
        integer lane;
        reg [31:0] expected;
        begin
            expected = 32'd0;
            for (lane = 0; lane < 4; lane = lane + 1)
                expected[lane*8 +: 8] =
                    expected_fb_byte(word_index * 4 + lane);
            @(negedge clk);
            ps_bram_addr = (captured_fb_slot ? 10'd16 : 10'd0) +
                           word_index;
            ps_bram_we = 4'b0000;
            ps_bram_en = 1'b1;
            @(posedge clk);
            #1;
            if (!ps_bram_rvalid || (ps_bram_rdata !== expected))
                fail("fullband mailbox word mismatch");
            @(negedge clk);
            ps_bram_en = 1'b0;
        end
    endtask

    task automatic release_fullband;
        begin
            @(negedge clk);
            ps_fb_release_slot = captured_fb_slot;
            ps_fb_release_frame_id = 16'd0;
            ps_fb_release_valid = 1'b1;
            if (!ps_fb_release_ready)
                fail("fullband release was not ready");
            @(posedge clk);
            @(negedge clk);
            ps_fb_release_valid = 1'b0;
        end
    endtask

    task automatic claim_subband_slot;
        begin
            @(negedge clk);
            ps_sb_claim_slot = 1'b0;
            ps_sb_claim_frame_id = 16'd0;
            ps_sb_claim_valid = 1'b1;
            if (!ps_sb_claim_ready)
                fail("subband claim was not ready");
            @(posedge clk);
            @(negedge clk);
            ps_sb_claim_valid = 1'b0;
        end
    endtask

    task automatic write_subband_payload;
        integer word_index;
        begin
            for (word_index = 0; word_index < 196;
                 word_index = word_index + 1) begin
                @(negedge clk);
                ps_bram_addr = 10'd256 + word_index;
                ps_bram_wdata = expected_sb_word(word_index);
                ps_bram_we = 4'b1111;
                ps_bram_en = 1'b1;
                @(posedge clk);
            end
            @(negedge clk);
            ps_bram_en = 1'b0;
            ps_bram_we = 4'b0000;
        end
    endtask

    task automatic commit_subband_slot;
        begin
            repeat (2) @(posedge clk);
            @(negedge clk);
            ps_sb_commit_slot = 1'b0;
            ps_sb_commit_frame_id = 16'd0;
            ps_sb_commit_valid = 1'b1;
            if (!ps_sb_commit_ready)
                fail("subband commit was not ready");
            @(posedge clk);
            @(negedge clk);
            ps_sb_commit_valid = 1'b0;
        end
    endtask

    task automatic check_buffer_byte;
        input integer byte_index;
        reg signed [7:0] held_data;
        begin
            @(negedge clk);
            sb_read_index = byte_index[9:0];
            sb_read_frame_id = 16'd0;
            sb_read_valid = 1'b1;
            while (!sb_read_ready)
                @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            sb_read_valid = 1'b0;
            if (!sb_read_rsp_valid)
                fail("buffer read response was not valid");
            if (sb_read_rsp_error ||
                (sb_read_rsp_data !== expected_sb_byte(byte_index)))
                fail("buffered subband byte mismatch");
            held_data = sb_read_rsp_data;
            repeat (2) begin
                @(posedge clk);
                #1;
                if (!sb_read_rsp_valid ||
                    (sb_read_rsp_data !== held_data))
                    fail("buffer read response changed under backpressure");
            end
            @(negedge clk);
            sb_read_rsp_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            sb_read_rsp_ready = 1'b0;
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            accepted_sb_bytes <= 0;
            captured_fb_publish <= 1'b0;
            captured_fb_slot <= 1'b0;
        end else begin
            if (mailbox_sb_data_valid && mailbox_sb_data_ready)
                accepted_sb_bytes <= accepted_sb_bytes + 1;
            if (fsm_ps_subbands_valid && (accepted_sb_bytes < 782))
                fail("FSM saw subbands before all 782 bytes were buffered");
            if (fb_published_valid) begin
                captured_fb_publish <= 1'b1;
                captured_fb_slot <= fb_published_slot;
                if (fb_published_frame_id != 16'd0)
                    fail("published fullband frame ID mismatch");
            end
        end
    end

    integer timeout;
    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        abort = 1'b0;
        fb_projection_start = 1'b0;
        frame_done = 1'b0;
        fsm_fb_result_valid = 1'b0;
        fsm_ps_subbands_ready = 1'b0;
        fb_coefficient_valid = 1'b0;
        fb_coefficient_value = 8'sd0;
        fb_coefficient_index = 9'd0;
        fb_coefficient_last = 1'b0;
        sb_read_valid = 1'b0;
        sb_read_index = 10'd0;
        sb_read_frame_id = 16'd0;
        sb_read_rsp_ready = 1'b0;
        ps_bram_en = 1'b0;
        ps_bram_we = 4'b0000;
        ps_bram_addr = 10'd0;
        ps_bram_wdata = 32'd0;
        ps_fb_release_valid = 1'b0;
        ps_fb_release_slot = 1'b0;
        ps_fb_release_frame_id = 16'd0;
        ps_sb_claim_valid = 1'b0;
        ps_sb_claim_slot = 1'b0;
        ps_sb_claim_frame_id = 16'd0;
        ps_sb_commit_valid = 1'b0;
        ps_sb_commit_slot = 1'b0;
        ps_sb_commit_frame_id = 16'd0;
        accepted_sb_bytes = 0;
        failures = 0;
        captured_fb_slot = 1'b0;
        captured_fb_publish = 1'b0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);
        if (!adapter_quiescent)
            fail("adapter was not quiescent after reset");

        pulse_projection_start();
        if (adapter_quiescent)
            fail("adapter claimed quiescent during fullband publication");
        send_fb_coefficients();

        timeout = 0;
        while (!fb_publish_complete && (timeout < 100)) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (!fb_publish_complete || !captured_fb_publish)
            fail("fullband projection did not publish atomically");

        @(negedge clk);
        fsm_fb_result_valid = 1'b1;
        if (!fsm_fb_result_ready)
            fail("FSM fullband result was not acknowledged after publish");
        @(posedge clk);
        @(negedge clk);
        fsm_fb_result_valid = 1'b0;

        read_fb_word(0);
        read_fb_word(7);
        read_fb_word(15);
        release_fullband();

        claim_subband_slot();
        write_subband_payload();
        commit_subband_slot();

        timeout = 0;
        while (!sb_buffer_valid && (timeout < 5000)) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (!sb_buffer_valid || !fsm_ps_subbands_valid)
            fail("complete subband frame was not exposed to FSM");
        if (adapter_quiescent)
            fail("adapter claimed quiescent while subband data was owned");
        if (accepted_sb_bytes != 782)
            fail("adapter did not accept exactly 782 subband bytes");

        @(negedge clk);
        fsm_ps_subbands_ready = 1'b1;
        @(posedge clk);
        @(negedge clk);
        fsm_ps_subbands_ready = 1'b0;
        if (!sb_buffer_valid)
            fail("FSM handshake released the feature buffer too early");

        check_buffer_byte(0);
        check_buffer_byte(45);
        check_buffer_byte(183);
        check_buffer_byte(465);
        check_buffer_byte(781);

        @(negedge clk);
        frame_done = 1'b1;
        @(posedge clk);
        @(negedge clk);
        frame_done = 1'b0;
        if ((current_frame_id != 16'd1) || sb_buffer_valid)
            fail("frame completion did not advance and release the buffer");
        if (!adapter_quiescent)
            fail("adapter did not become quiescent after frame completion");

        // Reset to frame zero, then prove malformed coefficient identity is a
        // sticky adapter fault requiring coordinated reset.
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        pulse_projection_start();
        @(negedge clk);
        fb_coefficient_valid = 1'b1;
        fb_coefficient_value = 8'sd7;
        fb_coefficient_index = 9'd1;
        fb_coefficient_last = 1'b0;
        while (!fb_coefficient_ready)
            @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        fb_coefficient_valid = 1'b0;
        if (!adapter_error_valid || (adapter_error_code != 8'h41))
            fail("malformed coefficient did not latch ERR_FB_COEFFICIENT");

        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        if (adapter_error_valid || mailbox_error_valid)
            fail("coordinated reset did not clear mailbox path faults");

        if (failures == 0) begin
            $display("PASS tb_layernorm_mailbox_fsm_adapter bytes=782 reads=5");
            $finish;
        end
        $fatal(1, "FAIL tb_layernorm_mailbox_fsm_adapter failures=%0d",
               failures);
    end

    initial begin
        #200000;
        $fatal(1, "FAIL tb_layernorm_mailbox_fsm_adapter timeout");
    end
endmodule
