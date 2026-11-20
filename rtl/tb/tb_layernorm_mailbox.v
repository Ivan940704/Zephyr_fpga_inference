`timescale 1ns/1ps

module tb_layernorm_mailbox;
    localparam integer FRAME_ID_WIDTH = 16;

    reg clk;
    reg rst_n;
    reg abort;
    reg clear_error;

    reg ps_bram_en;
    reg [3:0] ps_bram_we;
    reg [9:0] ps_bram_addr;
    reg [31:0] ps_bram_wdata;
    wire [31:0] ps_bram_rdata;
    wire ps_bram_rvalid;

    reg fb_begin_valid;
    wire fb_begin_ready;
    reg [FRAME_ID_WIDTH-1:0] fb_begin_frame_id;
    wire fb_begin_slot;
    reg fb_data_valid;
    wire fb_data_ready;
    reg [7:0] fb_data;
    reg fb_data_last;
    wire fb_published_valid;
    wire fb_published_slot;
    wire [FRAME_ID_WIDTH-1:0] fb_published_frame_id;

    reg ps_fb_release_valid;
    wire ps_fb_release_ready;
    reg ps_fb_release_slot;
    reg [FRAME_ID_WIDTH-1:0] ps_fb_release_frame_id;
    reg ps_sb_claim_valid;
    wire ps_sb_claim_ready;
    reg ps_sb_claim_slot;
    reg [FRAME_ID_WIDTH-1:0] ps_sb_claim_frame_id;
    reg ps_sb_commit_valid;
    wire ps_sb_commit_ready;
    reg ps_sb_commit_slot;
    reg [FRAME_ID_WIDTH-1:0] ps_sb_commit_frame_id;
    wire sb_committed_valid;
    wire sb_committed_slot;
    wire [FRAME_ID_WIDTH-1:0] sb_committed_frame_id;

    wire ps_subbands_valid;
    reg ps_subbands_ready;
    wire ps_subbands_slot;
    wire [FRAME_ID_WIDTH-1:0] ps_subbands_frame_id;
    wire sb_data_valid;
    reg sb_data_ready;
    wire [7:0] sb_data;
    wire [9:0] sb_data_index;
    wire sb_data_last;
    wire sb_released_valid;
    wire sb_released_slot;
    wire [FRAME_ID_WIDTH-1:0] sb_released_frame_id;

    wire [3:0] fb_slot_states;
    wire [3:0] sb_slot_states;
    wire [FRAME_ID_WIDTH-1:0] expected_fb_frame_id;
    wire [FRAME_ID_WIDTH-1:0] expected_sb_frame_id;
    wire [FRAME_ID_WIDTH-1:0] expected_consume_frame_id;
    wire error_valid;
    wire [7:0] error_code;
    wire error_slot;
    wire [FRAME_ID_WIDTH-1:0] error_frame_id;
    wire irq;

    integer failures;

    layernorm_mailbox #(
        .FRAME_ID_WIDTH(FRAME_ID_WIDTH),
        .TIMEOUT_CYCLES(5000)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .abort(abort),
        .clear_error(clear_error),
        .ps_bram_en(ps_bram_en),
        .ps_bram_we(ps_bram_we),
        .ps_bram_addr(ps_bram_addr),
        .ps_bram_wdata(ps_bram_wdata),
        .ps_bram_rdata(ps_bram_rdata),
        .ps_bram_rvalid(ps_bram_rvalid),
        .fb_begin_valid(fb_begin_valid),
        .fb_begin_ready(fb_begin_ready),
        .fb_begin_frame_id(fb_begin_frame_id),
        .fb_begin_slot(fb_begin_slot),
        .fb_data_valid(fb_data_valid),
        .fb_data_ready(fb_data_ready),
        .fb_data(fb_data),
        .fb_data_last(fb_data_last),
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
        .ps_subbands_valid(ps_subbands_valid),
        .ps_subbands_ready(ps_subbands_ready),
        .ps_subbands_slot(ps_subbands_slot),
        .ps_subbands_frame_id(ps_subbands_frame_id),
        .sb_data_valid(sb_data_valid),
        .sb_data_ready(sb_data_ready),
        .sb_data(sb_data),
        .sb_data_index(sb_data_index),
        .sb_data_last(sb_data_last),
        .sb_released_valid(sb_released_valid),
        .sb_released_slot(sb_released_slot),
        .sb_released_frame_id(sb_released_frame_id),
        .fb_slot_states(fb_slot_states),
        .sb_slot_states(sb_slot_states),
        .expected_fb_frame_id(expected_fb_frame_id),
        .expected_sb_frame_id(expected_sb_frame_id),
        .expected_consume_frame_id(expected_consume_frame_id),
        .error_valid(error_valid),
        .error_code(error_code),
        .error_slot(error_slot),
        .error_frame_id(error_frame_id),
        .irq(irq)
    );

    always #5 clk = ~clk;

    task fail;
        input [8*160-1:0] message;
        begin
            failures = failures + 1;
            $display("FAIL: %0s at time %0t", message, $time);
        end
    endtask

    function [7:0] expected_fb_byte;
        input [15:0] frame_id;
        input integer byte_index;
        begin
            expected_fb_byte = (frame_id * 8'd67) + byte_index + 8'h31;
        end
    endfunction

    function [7:0] expected_sb_byte;
        input [15:0] frame_id;
        input integer byte_index;
        begin
            expected_sb_byte = (frame_id * 8'd37) +
                               (byte_index * 8'd13) + 8'h07;
        end
    endfunction

    function [31:0] expected_sb_word;
        input [15:0] frame_id;
        input integer word_index;
        input bad_padding;
        integer lane;
        integer byte_index;
        begin
            expected_sb_word = 32'd0;
            for (lane = 0; lane < 4; lane = lane + 1) begin
                byte_index = word_index * 4 + lane;
                if (byte_index < 782)
                    expected_sb_word[lane*8 +: 8] =
                        expected_sb_byte(frame_id, byte_index);
                else if (bad_padding)
                    expected_sb_word[lane*8 +: 8] = 8'ha5;
                else
                    expected_sb_word[lane*8 +: 8] = 8'd0;
            end
        end
    endfunction

    task clear_sticky_error;
        begin
            @(negedge clk);
            clear_error = 1'b1;
            @(posedge clk);
            @(negedge clk);
            clear_error = 1'b0;
            if (error_valid)
                fail("mailbox clear_error did not clear sticky fault");
        end
    endtask

    task publish_fullband;
        input [15:0] frame_id;
        output published_slot;
        integer byte_index;
        begin
            @(negedge clk);
            fb_begin_frame_id = frame_id;
            fb_begin_valid = 1'b1;
            while (!fb_begin_ready)
                @(negedge clk);
            published_slot = fb_begin_slot;
            @(posedge clk);
            @(negedge clk);
            fb_begin_valid = 1'b0;

            for (byte_index = 0; byte_index < 64;
                 byte_index = byte_index + 1) begin
                // Deliberate producer gaps prove that exact length is counted
                // from successful ready/valid transfers, not wall-clock cycles.
                if ((byte_index % 11) == 5) begin
                    fb_data_valid = 1'b0;
                    @(posedge clk);
                    @(negedge clk);
                end
                fb_data = expected_fb_byte(frame_id, byte_index);
                fb_data_last = (byte_index == 63);
                fb_data_valid = 1'b1;
                if (!fb_data_ready)
                    fail("fullband payload lost mailbox ownership");
                @(posedge clk);
                @(negedge clk);
            end
            fb_data_valid = 1'b0;
            fb_data_last = 1'b0;
            if (!fb_published_valid ||
                (fb_published_slot !== published_slot) ||
                (fb_published_frame_id !== frame_id))
                fail("fullband frame was not published atomically");
        end
    endtask

    task check_fullband_word;
        input slot_id;
        input [15:0] frame_id;
        input integer word_index;
        integer lane;
        reg [31:0] expected;
        begin
            expected = 32'd0;
            for (lane = 0; lane < 4; lane = lane + 1)
                expected[lane*8 +: 8] =
                    expected_fb_byte(frame_id, word_index * 4 + lane);
            @(negedge clk);
            ps_bram_addr = (slot_id ? 10'd16 : 10'd0) + word_index;
            ps_bram_we = 4'b0000;
            ps_bram_en = 1'b1;
            @(posedge clk);
            #1;
            if (!ps_bram_rvalid || (ps_bram_rdata !== expected))
                fail("PS fullband mailbox read mismatch");
            @(negedge clk);
            ps_bram_en = 1'b0;
        end
    endtask

    task release_fullband;
        input slot_id;
        input [15:0] frame_id;
        begin
            @(negedge clk);
            ps_fb_release_slot = slot_id;
            ps_fb_release_frame_id = frame_id;
            ps_fb_release_valid = 1'b1;
            if (!ps_fb_release_ready)
                fail("fullband release interface was not ready");
            @(posedge clk);
            @(negedge clk);
            ps_fb_release_valid = 1'b0;
        end
    endtask

    task claim_subbands;
        input slot_id;
        input [15:0] frame_id;
        begin
            @(negedge clk);
            ps_sb_claim_slot = slot_id;
            ps_sb_claim_frame_id = frame_id;
            ps_sb_claim_valid = 1'b1;
            if (!ps_sb_claim_ready)
                fail("subband claim interface was not ready");
            @(posedge clk);
            @(negedge clk);
            ps_sb_claim_valid = 1'b0;
        end
    endtask

    task write_subband_word;
        input slot_id;
        input [15:0] frame_id;
        input integer word_index;
        input bad_padding;
        begin
            @(negedge clk);
            ps_bram_addr = (slot_id ? 10'd512 : 10'd256) + word_index;
            ps_bram_wdata = expected_sb_word(frame_id, word_index, bad_padding);
            ps_bram_we = 4'b1111;
            ps_bram_en = 1'b1;
            @(posedge clk);
            @(negedge clk);
            ps_bram_en = 1'b0;
            ps_bram_we = 4'b0000;
        end
    endtask

    task fill_subbands;
        input slot_id;
        input [15:0] frame_id;
        input bad_padding;
        integer word_index;
        begin
            for (word_index = 0; word_index < 196;
                 word_index = word_index + 1)
                write_subband_word(slot_id, frame_id, word_index, bad_padding);
            repeat (2) @(posedge clk);
        end
    endtask

    task commit_subbands;
        input slot_id;
        input [15:0] frame_id;
        input expect_success;
        begin
            @(negedge clk);
            ps_sb_commit_slot = slot_id;
            ps_sb_commit_frame_id = frame_id;
            ps_sb_commit_valid = 1'b1;
            if (!ps_sb_commit_ready)
                fail("subband commit interface was not ready");
            @(posedge clk);
            @(negedge clk);
            ps_sb_commit_valid = 1'b0;
            if (expect_success) begin
                if (!sb_committed_valid || (sb_committed_slot !== slot_id) ||
                    (sb_committed_frame_id !== frame_id))
                    fail("subband frame was not committed atomically");
            end else if (sb_committed_valid) begin
                fail("malformed subband frame was incorrectly committed");
            end
        end
    endtask

    task stream_subbands;
        input slot_id;
        input [15:0] frame_id;
        integer expected_index;
        integer loop_count;
        begin
            #1;
            if (!ps_subbands_valid || (ps_subbands_slot !== slot_id) ||
                (ps_subbands_frame_id !== frame_id))
                fail("committed frame was not selected in frame-ID order");
            @(negedge clk);
            ps_subbands_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            ps_subbands_ready = 1'b0;

            expected_index = 0;
            loop_count = 0;
            while ((expected_index < 782) && (loop_count < 10000)) begin
                // Hold one of every five offered bytes to test stream stability.
                sb_data_ready = ((loop_count % 5) != 2);
                if (sb_data_valid && sb_data_ready) begin
                    if ((sb_data_index !== expected_index[9:0]) ||
                        (sb_data !== expected_sb_byte(frame_id, expected_index)) ||
                        (sb_data_last !== (expected_index == 781)))
                        fail("subband byte stream mismatch");
                    expected_index = expected_index + 1;
                end
                @(posedge clk);
                @(negedge clk);
                loop_count = loop_count + 1;
            end
            sb_data_ready = 1'b0;
            if (expected_index != 782)
                fail("subband stream did not produce exactly 782 bytes");
            if (!sb_released_valid || (sb_released_slot !== slot_id) ||
                (sb_released_frame_id !== frame_id))
                fail("subband slot was not released after the final byte");
        end
    endtask

    integer word_index;
    reg fb_slot0;
    reg fb_slot1;
    initial begin
        $dumpfile("build/tb_layernorm_mailbox.vcd");
        $dumpvars(0, tb_layernorm_mailbox);

        clk = 1'b0;
        rst_n = 1'b0;
        abort = 1'b0;
        clear_error = 1'b0;
        ps_bram_en = 1'b0;
        ps_bram_we = 4'b0000;
        ps_bram_addr = 10'd0;
        ps_bram_wdata = 32'd0;
        fb_begin_valid = 1'b0;
        fb_begin_frame_id = 16'd0;
        fb_data_valid = 1'b0;
        fb_data = 8'd0;
        fb_data_last = 1'b0;
        ps_fb_release_valid = 1'b0;
        ps_fb_release_slot = 1'b0;
        ps_fb_release_frame_id = 16'd0;
        ps_sb_claim_valid = 1'b0;
        ps_sb_claim_slot = 1'b0;
        ps_sb_claim_frame_id = 16'd0;
        ps_sb_commit_valid = 1'b0;
        ps_sb_commit_slot = 1'b0;
        ps_sb_commit_frame_id = 16'd0;
        ps_subbands_ready = 1'b0;
        sb_data_ready = 1'b0;
        failures = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        // A release while PL still owns a FILL slot invalidates the partial
        // frame and must also stop the byte interface from republishing it.
        @(negedge clk);
        fb_begin_frame_id = 16'd0;
        fb_begin_valid = 1'b1;
        if (!fb_begin_ready)
            fail("fullband partial-frame setup was not ready");
        fb_slot0 = fb_begin_slot;
        @(posedge clk);
        @(negedge clk);
        fb_begin_valid = 1'b0;
        fb_data = 8'h5a;
        fb_data_last = 1'b0;
        fb_data_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        fb_data_valid = 1'b0;
        ps_fb_release_slot = fb_slot0;
        ps_fb_release_frame_id = 16'hffff;
        ps_fb_release_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        ps_fb_release_valid = 1'b0;
        #1;
        if (!error_valid || (error_code != 8'h22) || fb_data_ready ||
            (fb_slot_states != 4'b0000) || fb_published_valid ||
            (expected_fb_frame_id != 16'd0))
            fail("invalid fullband release did not invalidate an active fill");
        clear_sticky_error();

        // Both 64-byte PL->PS slots can be READY simultaneously.
        publish_fullband(16'd0, fb_slot0);
        publish_fullband(16'd1, fb_slot1);
        if ((fb_slot0 !== 1'b0) || (fb_slot1 !== 1'b1) || fb_begin_ready)
            fail("fullband double-slot allocation mismatch");
        for (word_index = 0; word_index < 16; word_index = word_index + 1) begin
            check_fullband_word(fb_slot0, 16'd0, word_index);
            check_fullband_word(fb_slot1, 16'd1, word_index);
        end
        release_fullband(fb_slot0, 16'd0);
        release_fullband(fb_slot1, 16'd1);
        if (fb_slot_states != 4'b0000)
            fail("released fullband slots did not return to FREE");

        // Incomplete byte coverage must fail commit and free the claimed slot.
        claim_subbands(1'b0, 16'd0);
        @(negedge clk);
        ps_bram_addr = 10'd256;
        ps_bram_wdata = expected_sb_word(16'd0, 0, 1'b0);
        ps_bram_we = 4'b0011;
        ps_bram_en = 1'b1;
        @(posedge clk);
        @(negedge clk);
        ps_bram_en = 1'b0;
        ps_bram_we = 4'b0000;
        if (!error_valid || (error_code != 8'h28))
            fail("partial PS write strobe was not rejected");
        clear_sticky_error();
        write_subband_word(1'b0, 16'd0, 0, 1'b0);
        commit_subbands(1'b0, 16'd0, 1'b0);
        if (!error_valid || (error_code != 8'h25) ||
            (sb_slot_states[1:0] != 2'b00))
            fail("incomplete subband commit was not rejected");
        clear_sticky_error();

        // Two exact 782-byte frames (plus two required zero pad bytes) may be
        // committed before the PL begins consuming frame 0.
        claim_subbands(1'b0, 16'd0);
        fill_subbands(1'b0, 16'd0, 1'b0);
        commit_subbands(1'b0, 16'd0, 1'b1);
        claim_subbands(1'b1, 16'd1);
        fill_subbands(1'b1, 16'd1, 1'b0);
        commit_subbands(1'b1, 16'd1, 1'b1);
        if ((expected_sb_frame_id != 16'd2) ||
            (sb_slot_states != 4'b1010) || !irq)
            fail("dual committed subband ownership mismatch");

        stream_subbands(1'b0, 16'd0);
        stream_subbands(1'b1, 16'd1);
        if ((expected_consume_frame_id != 16'd2) ||
            (sb_slot_states != 4'b0000))
            fail("subband stream did not release both slots in order");

        // Even with all write strobes observed, nonzero bytes 782/783 violate
        // the exact 782-byte ABI and must not become visible to PL.
        claim_subbands(1'b0, 16'd2);
        fill_subbands(1'b0, 16'd2, 1'b1);
        commit_subbands(1'b0, 16'd2, 1'b0);
        if (!error_valid || (error_code != 8'h25) || ps_subbands_valid)
            fail("nonzero subband padding was not rejected");

        clear_sticky_error();
        @(negedge clk);
        abort = 1'b1;
        @(posedge clk);
        @(negedge clk);
        abort = 1'b0;
        repeat (2) @(posedge clk);
        if ((fb_slot_states != 0) || (sb_slot_states != 0) ||
            (expected_fb_frame_id != 0) || (expected_sb_frame_id != 0) ||
            (expected_consume_frame_id != 0))
            fail("abort did not reset mailbox ownership and frame sequence");

        // A stale frame ID cannot claim a free slot.
        claim_subbands(1'b0, 16'd1);
        if (!error_valid || (error_code != 8'h23) ||
            (sb_slot_states[1:0] != 2'b00) ||
            (expected_sb_frame_id != 16'd0))
            fail("stale subband claim was not rejected atomically");
        clear_sticky_error();

        // A duplicate claim is treated as an overwrite attempt and invalidates
        // the partially owned slot before software retries.
        claim_subbands(1'b0, 16'd0);
        claim_subbands(1'b0, 16'd0);
        if (!error_valid || (error_code != 8'h23) ||
            (sb_slot_states[1:0] != 2'b00))
            fail("duplicate/overwrite claim was not rejected fail-closed");
        clear_sticky_error();

        // An invalid claim against a slot already owned by the PL invalidates
        // both its state and the in-flight stream, so stale bytes cannot leak.
        claim_subbands(1'b0, 16'd0);
        fill_subbands(1'b0, 16'd0, 1'b0);
        commit_subbands(1'b0, 16'd0, 1'b1);
        @(negedge clk);
        ps_subbands_ready = 1'b1;
        @(posedge clk);
        @(negedge clk);
        ps_subbands_ready = 1'b0;
        while (!sb_data_valid)
            @(negedge clk);
        claim_subbands(1'b0, 16'd1);
        #1;
        if (!error_valid || (error_code != 8'h23) || sb_data_valid ||
            (sb_slot_states[1:0] != 2'b00) ||
            (expected_consume_frame_id != 16'd0))
            fail("invalid claim did not cancel an active subband stream");
        clear_sticky_error();
        @(negedge clk);
        abort = 1'b1;
        @(posedge clk);
        @(negedge clk);
        abort = 1'b0;
        repeat (2) @(posedge clk);

        // Inactive ownership is bounded.  The slot must be freed without ever
        // becoming visible to PL, while preserving the expected frame ID.
        claim_subbands(1'b0, 16'd0);
        repeat (5002) @(posedge clk);
        #1;
        if (!error_valid || (error_code != 8'h27) || error_slot ||
            (error_frame_id != 16'd0) ||
            (sb_slot_states[1:0] != 2'b00) || ps_subbands_valid ||
            (expected_sb_frame_id != 16'd0))
            fail("subband ownership timeout did not fail closed");
        clear_sticky_error();

        // Reset invalidates partial ownership and frame tags even though BRAM
        // payload bits themselves deliberately retain old contents.
        claim_subbands(1'b0, 16'd0);
        write_subband_word(1'b0, 16'd0, 0, 1'b0);
        @(negedge clk);
        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        #1;
        if ((fb_slot_states != 0) || (sb_slot_states != 0) ||
            (expected_fb_frame_id != 0) || (expected_sb_frame_id != 0) ||
            (expected_consume_frame_id != 0) || error_valid ||
            ps_subbands_valid)
            fail("reset did not invalidate partial mailbox ownership");

        if (failures == 0)
            $display("PASS tb_layernorm_mailbox");
        else
            $fatal(1, "FAIL tb_layernorm_mailbox errors=%0d", failures);

        #20;
        $finish;
    end
endmodule
