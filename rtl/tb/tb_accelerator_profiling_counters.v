`timescale 1ns/1ps

module tb_accelerator_profiling_counters;
    reg clk = 1'b0;
    reg rst_n;
    reg enable;
    reg clear_pulse;
    reg snapshot_pulse;
    reg [7:0] read_index;
    wire [31:0] read_data;
    wire snapshot_valid;
    wire frame_active;
    wire snapshot_busy;
    reg accelerator_reset_active;
    reg frame_start;
    reg frame_done;
    reg frame_error;
    reg sparse_mode;
    reg [15:0] frame_id;
    reg [3:0] global_state;
    reg [3:0] active_stage_id;
    reg [5:0] controller_state;
    reg [3:0] compute_owner;
    reg parameter_arvalid;
    reg parameter_arready;
    reg [7:0] parameter_arlen;
    reg parameter_rvalid;
    reg parameter_rready;
    reg parameter_rlast;
    reg fb_axis_tvalid;
    reg fb_axis_tready;
    reg fb_axis_tlast;
    reg spectrum_axis_tvalid;
    reg spectrum_axis_tready;
    reg spectrum_axis_tlast;
    reg output_axis_tvalid;
    reg output_axis_tready;
    reg output_axis_tlast;
    reg fb_release_valid;
    reg fb_release_ready;
    reg sb_claim_valid;
    reg sb_claim_ready;
    reg sb_commit_valid;
    reg sb_commit_ready;
    reg mailbox_error_valid;
    reg [31:0] weight_request_count;
    reg [31:0] dense_weight_request_count;
    reg [31:0] sparse_weight_request_count;
    reg sparse_stage_diag_valid;
    reg [31:0] sparse_stage_actual_bytes;
    reg [31:0] sparse_stage_saved_bytes;
    reg [31:0] sparse_stage_ar_burst_count;
    reg [31:0] sparse_stage_load_cycles;

    integer errors;
    integer state_index;
    reg [63:0] state_cycle_total;

    always #5 clk = ~clk;

    accelerator_profiling_counters dut (
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .clear_pulse(clear_pulse),
        .snapshot_pulse(snapshot_pulse),
        .read_index(read_index),
        .read_data(read_data),
        .snapshot_valid(snapshot_valid),
        .frame_active(frame_active),
        .snapshot_busy(snapshot_busy),
        .accelerator_reset_active(accelerator_reset_active),
        .frame_start(frame_start),
        .frame_done(frame_done),
        .frame_error(frame_error),
        .sparse_mode(sparse_mode),
        .frame_id(frame_id),
        .global_state(global_state),
        .active_stage_id(active_stage_id),
        .controller_state(controller_state),
        .compute_owner(compute_owner),
        .parameter_arvalid(parameter_arvalid),
        .parameter_arready(parameter_arready),
        .parameter_arlen(parameter_arlen),
        .parameter_rvalid(parameter_rvalid),
        .parameter_rready(parameter_rready),
        .parameter_rlast(parameter_rlast),
        .fb_axis_tvalid(fb_axis_tvalid),
        .fb_axis_tready(fb_axis_tready),
        .fb_axis_tlast(fb_axis_tlast),
        .spectrum_axis_tvalid(spectrum_axis_tvalid),
        .spectrum_axis_tready(spectrum_axis_tready),
        .spectrum_axis_tlast(spectrum_axis_tlast),
        .output_axis_tvalid(output_axis_tvalid),
        .output_axis_tready(output_axis_tready),
        .output_axis_tlast(output_axis_tlast),
        .fb_release_valid(fb_release_valid),
        .fb_release_ready(fb_release_ready),
        .sb_claim_valid(sb_claim_valid),
        .sb_claim_ready(sb_claim_ready),
        .sb_commit_valid(sb_commit_valid),
        .sb_commit_ready(sb_commit_ready),
        .mailbox_error_valid(mailbox_error_valid),
        .weight_request_count(weight_request_count),
        .dense_weight_request_count(dense_weight_request_count),
        .sparse_weight_request_count(sparse_weight_request_count),
        .sparse_stage_diag_valid(sparse_stage_diag_valid),
        .sparse_stage_actual_bytes(sparse_stage_actual_bytes),
        .sparse_stage_saved_bytes(sparse_stage_saved_bytes),
        .sparse_stage_ar_burst_count(sparse_stage_ar_burst_count),
        .sparse_stage_load_cycles(sparse_stage_load_cycles)
    );

    task tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task read64;
        input integer base_index;
        output reg [63:0] value;
        reg [31:0] low_word;
        begin
            read_index = base_index[7:0];
            #1 low_word = read_data;
            read_index = (base_index + 1);
            #1 value = {read_data, low_word};
        end
    endtask

    task expect64;
        input integer base_index;
        input [63:0] expected;
        input [255:0] label_text;
        reg [63:0] actual;
        begin
            read64(base_index, actual);
            if (actual !== expected) begin
                $display("FAIL %0s expected=%0d actual=%0d", label_text,
                         expected, actual);
                errors = errors + 1;
            end
        end
    endtask

    task expect32;
        input integer index_value;
        input [31:0] expected;
        input [255:0] label_text;
        begin
            read_index = index_value[7:0];
            #1;
            if (read_data !== expected) begin
                $display("FAIL %0s expected=0x%08x actual=0x%08x",
                         label_text, expected, read_data);
                errors = errors + 1;
            end
        end
    endtask

    task clear_events;
        begin
            parameter_arvalid = 1'b0;
            parameter_arready = 1'b0;
            parameter_arlen = 8'd0;
            parameter_rvalid = 1'b0;
            parameter_rready = 1'b0;
            parameter_rlast = 1'b0;
            fb_axis_tvalid = 1'b0;
            fb_axis_tready = 1'b0;
            fb_axis_tlast = 1'b0;
            spectrum_axis_tvalid = 1'b0;
            spectrum_axis_tready = 1'b0;
            spectrum_axis_tlast = 1'b0;
            output_axis_tvalid = 1'b0;
            output_axis_tready = 1'b0;
            output_axis_tlast = 1'b0;
            fb_release_valid = 1'b0;
            fb_release_ready = 1'b0;
            sb_claim_valid = 1'b0;
            sb_claim_ready = 1'b0;
            sb_commit_valid = 1'b0;
            sb_commit_ready = 1'b0;
            mailbox_error_valid = 1'b0;
            sparse_stage_diag_valid = 1'b0;
        end
    endtask

    initial begin
        errors = 0;
        rst_n = 1'b0;
        enable = 1'b0;
        clear_pulse = 1'b0;
        snapshot_pulse = 1'b0;
        read_index = 8'd0;
        accelerator_reset_active = 1'b0;
        frame_start = 1'b0;
        frame_done = 1'b0;
        frame_error = 1'b0;
        sparse_mode = 1'b0;
        frame_id = 16'd0;
        global_state = 4'd0;
        active_stage_id = 4'd0;
        controller_state = 6'd0;
        compute_owner = 4'd0;
        weight_request_count = 32'd0;
        dense_weight_request_count = 32'd0;
        sparse_weight_request_count = 32'd0;
        sparse_stage_actual_bytes = 32'd0;
        sparse_stage_saved_bytes = 32'd0;
        sparse_stage_ar_burst_count = 32'd0;
        sparse_stage_load_cycles = 32'd0;
        clear_events();

        repeat (3) tick();
        rst_n = 1'b1;
        tick();

        // Activity while disabled must never create a usable snapshot.
        frame_start = 1'b1;
        frame_done = 1'b1;
        tick();
        frame_start = 1'b0;
        frame_done = 1'b0;
        if (snapshot_valid || frame_active) begin
            $display("FAIL disabled profiler changed state");
            errors = errors + 1;
        end

        enable = 1'b1;
        clear_pulse = 1'b1;
        tick();
        clear_pulse = 1'b0;

        // Start frame 7 in sparse mode. The start handshake itself is not a
        // profiled execution cycle; the following four cycles are.
        sparse_mode = 1'b1;
        frame_id = 16'd7;
        global_state = 4'd0;
        frame_start = 1'b1;
        tick();
        frame_start = 1'b0;

        global_state = 4'd1;
        active_stage_id = 4'd0;
        parameter_arvalid = 1'b1;
        parameter_arready = 1'b1;
        parameter_arlen = 8'd3;
        fb_axis_tvalid = 1'b1;
        fb_axis_tready = 1'b1;
        fb_axis_tlast = 1'b1;
        fb_release_valid = 1'b1;
        fb_release_ready = 1'b1;
        tick();
        clear_events();

        global_state = 4'd2;
        parameter_arvalid = 1'b1;
        parameter_arready = 1'b0;
        spectrum_axis_tvalid = 1'b1;
        spectrum_axis_tready = 1'b0;
        tick();
        clear_events();

        global_state = 4'd3;
        controller_state = 6'd36;
        compute_owner = 4'd1;
        weight_request_count = 32'd100;
        dense_weight_request_count = 32'd70;
        sparse_weight_request_count = 32'd30;
        parameter_rvalid = 1'b1;
        parameter_rready = 1'b1;
        parameter_rlast = 1'b1;
        output_axis_tvalid = 1'b1;
        output_axis_tready = 1'b1;
        output_axis_tlast = 1'b1;
        sb_claim_valid = 1'b1;
        sb_claim_ready = 1'b1;
        sb_commit_valid = 1'b1;
        sb_commit_ready = 1'b1;
        sparse_stage_diag_valid = 1'b1;
        sparse_stage_actual_bytes = 32'd64;
        sparse_stage_saved_bytes = 32'd128;
        sparse_stage_ar_burst_count = 32'd2;
        sparse_stage_load_cycles = 32'd11;
        tick();
        clear_events();

        // The production sparse-memory diagnostic is a level that remains
        // asserted until the next stage request.  Keep it high for a second
        // cycle to prove that profiling records exactly one completion edge.
        sparse_stage_diag_valid = 1'b1;
        sparse_stage_actual_bytes = 32'd64;
        sparse_stage_saved_bytes = 32'd128;
        sparse_stage_ar_burst_count = 32'd2;
        sparse_stage_load_cycles = 32'd11;

        // The final cycle deliberately contains backpressure so the test also
        // proves that same-cycle events are present in the coherent snapshot.
        global_state = 4'd5;
        controller_state = 6'd0;
        output_axis_tvalid = 1'b1;
        output_axis_tready = 1'b0;
        frame_done = 1'b1;
        tick();
        frame_done = 1'b0;
        clear_events();

        if (snapshot_valid || !snapshot_busy || frame_active) begin
            $display("FAIL serialized snapshot did not enter busy state");
            errors = errors + 1;
        end
        repeat (196) tick();
        if (!snapshot_valid || snapshot_busy || frame_active) begin
            $display("FAIL successful serialized frame snapshot state");
            errors = errors + 1;
        end
        expect32(0, 32'h5052_0001, "profile schema");
        expect32(1, 32'h0000_0013, "profile status flags");
        expect32(3, 32'd1, "snapshot sequence");
        expect64(4, 64'd4, "frame cycles");
        expect64(6, 64'd4, "state cycle sum");

        state_cycle_total = 64'd0;
        for (state_index = 0; state_index < 13; state_index = state_index + 1) begin
            read64(8 + (state_index * 2), state_cycle_total);
            if ((state_index == 1) || (state_index == 2) ||
                (state_index == 3) || (state_index == 5)) begin
                if (state_cycle_total !== 64'd1) begin
                    $display("FAIL state %0d cycle count=%0d",
                             state_index, state_cycle_total);
                    errors = errors + 1;
                end
            end else if (state_cycle_total !== 64'd0) begin
                $display("FAIL unexpected state %0d cycle count=%0d",
                         state_index, state_cycle_total);
                errors = errors + 1;
            end
        end

        expect64(48, 64'd2, "stage 0 load cycles");
        expect64(72, 64'd1, "stage 0 compute cycles");
        expect64(96, 64'd1, "stage 0 stall cycles");
        expect64(120, 64'd1, "AXI AR bursts");
        expect64(122, 64'd4, "AXI AR beats");
        expect64(124, 64'd1, "AXI R beats");
        expect64(126, 64'd8, "AXI R bytes");
        expect64(128, 64'd1, "AXI AR stall cycles");
        expect64(130, 64'd1, "AXI R wait cycles");
        expect64(134, 64'd1, "FB stream beats");
        expect64(140, 64'd1, "spectrum backpressure");
        expect64(142, 64'd1, "output stream beats");
        expect64(144, 64'd1, "output backpressure");
        expect64(146, 64'd1, "FB releases");
        expect64(148, 64'd1, "SB claims");
        expect64(150, 64'd1, "SB commits");
        expect64(152, 64'd1, "controller jobs");
        expect64(154, 64'd100, "weight requests");
        expect64(156, 64'd70, "dense requests");
        expect64(158, 64'd30, "sparse requests");
        expect64(160, 64'd7680, "dense-equivalent requests");
        expect64(162, 64'd1600, "retired MACs");
        expect64(164, 64'd121280, "skipped MACs");
        expect64(166, 64'd64, "stage actual bytes");
        expect64(168, 64'd128, "stage saved bytes");
        expect64(170, 64'd2, "stage AR bursts");
        expect64(172, 64'd11, "stage load cycles");
        expect64(174, 64'd1, "maximum outstanding bursts");
        expect64(176, 64'd1, "FB input packets");
        expect64(178, 64'd0, "spectrum input packets");
        expect64(180, 64'd1, "output packets");
        expect64(182, 64'd0, "frame error cycles");
        expect64(184, 64'd0, "mailbox errors");
        expect64(186, 64'd1, "sparse diagnostic events");
        expect64(188, 64'd1, "AXI RLAST completions");
        expect64(190, 64'd0, "invalid state cycles");

        clear_pulse = 1'b1;
        tick();
        clear_pulse = 1'b0;
        if (snapshot_valid) begin
            $display("FAIL clear did not invalidate snapshot");
            errors = errors + 1;
        end

        // An error seen before the terminal cycle must invalidate the entire
        // frame snapshot, even when frame_error is low on frame_done.
        frame_id = 16'd8;
        global_state = 4'd0;
        frame_start = 1'b1;
        tick();
        frame_start = 1'b0;
        global_state = 4'd1;
        frame_error = 1'b1;
        tick();
        frame_error = 1'b0;
        global_state = 4'd5;
        frame_done = 1'b1;
        tick();
        frame_done = 1'b0;
        repeat (196) tick();
        if (snapshot_valid) begin
            $display("FAIL errored frame produced valid snapshot");
            errors = errors + 1;
        end
        if (snapshot_busy) begin
            $display("FAIL errored frame serializer remained busy");
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PROFILE_METRIC frame_cycles=4 state_sum=4 dense_eq=7680 retired_macs=1600 skipped_macs=121280");
            $display("PASS tb_accelerator_profiling_counters");
        end else begin
            $fatal(1, "FAIL tb_accelerator_profiling_counters errors=%0d", errors);
        end
        $finish;
    end
endmodule
