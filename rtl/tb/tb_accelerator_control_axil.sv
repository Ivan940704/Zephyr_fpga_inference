`timescale 1ns/1ps

module tb_accelerator_control_axil;
    reg aclk = 1'b0;
    reg aresetn;
    reg [11:0] s_axi_awaddr;
    reg [2:0] s_axi_awprot;
    reg s_axi_awvalid;
    wire s_axi_awready;
    reg [31:0] s_axi_wdata;
    reg [3:0] s_axi_wstrb;
    reg s_axi_wvalid;
    wire s_axi_wready;
    wire [1:0] s_axi_bresp;
    wire s_axi_bvalid;
    reg s_axi_bready;
    reg [11:0] s_axi_araddr;
    reg [2:0] s_axi_arprot;
    reg s_axi_arvalid;
    wire s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0] s_axi_rresp;
    wire s_axi_rvalid;
    reg s_axi_rready;

    reg accelerator_reset_active;
    reg accelerator_soft_reset_safe;
    reg accelerator_start_ready;
    reg accelerator_busy;
    reg accelerator_done;
    reg accelerator_error;
    reg accelerator_reset_required;
    reg [3:0] accelerator_error_code;
    reg [3:0] accelerator_state;
    reg [31:0] accelerator_state_cycles;
    reg accelerator_sparse_mode;
    reg [15:0] accelerator_frame_id;
    reg [3:0] fb_slot_states;
    reg [3:0] sb_slot_states;
    reg [15:0] expected_fb_frame_id;
    reg [15:0] expected_sb_frame_id;
    reg [15:0] expected_consume_frame_id;
    reg fb_published_valid;
    reg fb_published_slot;
    reg [15:0] fb_published_frame_id;
    reg sb_committed_valid;
    reg sb_committed_slot;
    reg [15:0] sb_committed_frame_id;
    reg sb_released_valid;
    reg sb_released_slot;
    reg [15:0] sb_released_frame_id;
    reg mailbox_error_valid;
    reg [7:0] mailbox_error_code;
    reg mailbox_error_slot;
    reg [15:0] mailbox_error_frame_id;
    reg mailbox_irq;
    reg fb_input_buffer_valid;
    reg [15:0] fb_input_buffer_frame_id;
    reg spectrum_input_buffer_valid;
    reg [15:0] spectrum_input_buffer_frame_id;
    reg [3:0] active_stage_id;
    reg [2:0] cache_state;
    reg [3:0] compute_owner;
    reg [5:0] controller_state;
    reg [31:0] weight_request_count;
    reg [31:0] dense_weight_request_count;
    reg [31:0] sparse_weight_request_count;
    reg sparse_stage_diag_valid;
    reg sparse_stage_diag_success;
    reg [3:0] sparse_stage_diag_stage_id;
    reg sparse_stage_diag_enabled;
    reg sparse_stage_diag_fallback_full;
    reg [31:0] sparse_stage_actual_bytes;
    reg [31:0] sparse_stage_saved_bytes;
    reg [31:0] sparse_stage_ar_burst_count;
    reg [31:0] sparse_stage_load_cycles;
    reg [31:0] profiling_read_data;
    reg profiling_snapshot_valid;
    reg profiling_frame_active;
    reg profiling_snapshot_busy;
    reg fault_valid;
    reg [7:0] fault_source;
    reg [7:0] fault_code;
    reg [31:0] fault_detail;

    wire start_valid;
    wire abort_pulse;
    wire clear_error_pulse;
    wire soft_reset_pulse;
    wire reset_quiesce_request;
    wire clear_state_on_start;
    wire sparse_load_enable;
    wire [31:0] parameter_base_addr;
    wire [7:0] profiling_read_index;
    wire profiling_enable;
    wire profiling_clear_pulse;
    wire profiling_snapshot_pulse;
    wire ps_fb_release_valid;
    reg ps_fb_release_ready;
    wire ps_fb_release_slot;
    wire [15:0] ps_fb_release_frame_id;
    wire ps_sb_claim_valid;
    reg ps_sb_claim_ready;
    wire ps_sb_claim_slot;
    wire [15:0] ps_sb_claim_frame_id;
    wire ps_sb_commit_valid;
    reg ps_sb_commit_ready;
    wire ps_sb_commit_slot;
    wire [15:0] ps_sb_commit_frame_id;
    wire irq;
    wire [31:0] debug_status;

    integer errors;
    integer start_handshakes;
    integer abort_pulses;
    integer clear_error_pulses;
    integer soft_reset_pulses;
    integer profiling_clear_pulses;
    integer profiling_snapshot_pulses;

    always #5 aclk = ~aclk;

    accelerator_control_axil dut (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awprot(s_axi_awprot),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arprot(s_axi_arprot),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .accelerator_reset_active(accelerator_reset_active),
        .accelerator_soft_reset_safe(accelerator_soft_reset_safe),
        .accelerator_start_ready(accelerator_start_ready),
        .accelerator_busy(accelerator_busy),
        .accelerator_done(accelerator_done),
        .accelerator_error(accelerator_error),
        .accelerator_reset_required(accelerator_reset_required),
        .accelerator_error_code(accelerator_error_code),
        .accelerator_state(accelerator_state),
        .accelerator_state_cycles(accelerator_state_cycles),
        .accelerator_sparse_mode(accelerator_sparse_mode),
        .accelerator_frame_id(accelerator_frame_id),
        .fb_slot_states(fb_slot_states),
        .sb_slot_states(sb_slot_states),
        .expected_fb_frame_id(expected_fb_frame_id),
        .expected_sb_frame_id(expected_sb_frame_id),
        .expected_consume_frame_id(expected_consume_frame_id),
        .fb_published_valid(fb_published_valid),
        .fb_published_slot(fb_published_slot),
        .fb_published_frame_id(fb_published_frame_id),
        .sb_committed_valid(sb_committed_valid),
        .sb_committed_slot(sb_committed_slot),
        .sb_committed_frame_id(sb_committed_frame_id),
        .sb_released_valid(sb_released_valid),
        .sb_released_slot(sb_released_slot),
        .sb_released_frame_id(sb_released_frame_id),
        .mailbox_error_valid(mailbox_error_valid),
        .mailbox_error_code(mailbox_error_code),
        .mailbox_error_slot(mailbox_error_slot),
        .mailbox_error_frame_id(mailbox_error_frame_id),
        .mailbox_irq(mailbox_irq),
        .fb_input_buffer_valid(fb_input_buffer_valid),
        .fb_input_buffer_frame_id(fb_input_buffer_frame_id),
        .spectrum_input_buffer_valid(spectrum_input_buffer_valid),
        .spectrum_input_buffer_frame_id(spectrum_input_buffer_frame_id),
        .active_stage_id(active_stage_id),
        .cache_state(cache_state),
        .compute_owner(compute_owner),
        .controller_state(controller_state),
        .weight_request_count(weight_request_count),
        .dense_weight_request_count(dense_weight_request_count),
        .sparse_weight_request_count(sparse_weight_request_count),
        .sparse_stage_diag_valid(sparse_stage_diag_valid),
        .sparse_stage_diag_success(sparse_stage_diag_success),
        .sparse_stage_diag_stage_id(sparse_stage_diag_stage_id),
        .sparse_stage_diag_enabled(sparse_stage_diag_enabled),
        .sparse_stage_diag_fallback_full(sparse_stage_diag_fallback_full),
        .sparse_stage_actual_bytes(sparse_stage_actual_bytes),
        .sparse_stage_saved_bytes(sparse_stage_saved_bytes),
        .sparse_stage_ar_burst_count(sparse_stage_ar_burst_count),
        .sparse_stage_load_cycles(sparse_stage_load_cycles),
        .profiling_read_data(profiling_read_data),
        .profiling_snapshot_valid(profiling_snapshot_valid),
        .profiling_frame_active(profiling_frame_active),
        .profiling_snapshot_busy(profiling_snapshot_busy),
        .fault_valid(fault_valid),
        .fault_source(fault_source),
        .fault_code(fault_code),
        .fault_detail(fault_detail),
        .start_valid(start_valid),
        .abort_pulse(abort_pulse),
        .clear_error_pulse(clear_error_pulse),
        .soft_reset_pulse(soft_reset_pulse),
        .reset_quiesce_request(reset_quiesce_request),
        .clear_state_on_start(clear_state_on_start),
        .sparse_load_enable(sparse_load_enable),
        .parameter_base_addr(parameter_base_addr),
        .profiling_read_index(profiling_read_index),
        .profiling_enable(profiling_enable),
        .profiling_clear_pulse(profiling_clear_pulse),
        .profiling_snapshot_pulse(profiling_snapshot_pulse),
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
        .irq(irq),
        .debug_status(debug_status)
    );

    always @(posedge aclk) begin
        if (aresetn) begin
            if (start_valid && accelerator_start_ready)
                start_handshakes = start_handshakes + 1;
            if (abort_pulse)
                abort_pulses = abort_pulses + 1;
            if (clear_error_pulse)
                clear_error_pulses = clear_error_pulses + 1;
            if (soft_reset_pulse)
                soft_reset_pulses = soft_reset_pulses + 1;
            if (profiling_clear_pulse)
                profiling_clear_pulses = profiling_clear_pulses + 1;
            if (profiling_snapshot_pulse)
                profiling_snapshot_pulses = profiling_snapshot_pulses + 1;
        end
    end

    task automatic check;
        input condition;
        input [8*96-1:0] message;
        begin
            if (!condition) begin
                $display("ERROR %0s", message);
                errors = errors + 1;
            end
        end
    endtask

    task automatic send_aw;
        input [11:0] address;
        input integer delay_cycles;
        integer accepted;
        begin
            repeat (delay_cycles) @(posedge aclk);
            @(negedge aclk);
            s_axi_awaddr = address;
            s_axi_awvalid = 1'b1;
            accepted = 0;
            while (!accepted) begin
                @(posedge aclk);
                if (s_axi_awready)
                    accepted = 1;
            end
            @(negedge aclk);
            s_axi_awvalid = 1'b0;
        end
    endtask

    task automatic send_w;
        input [31:0] data;
        input [3:0] strobe;
        input integer delay_cycles;
        integer accepted;
        begin
            repeat (delay_cycles) @(posedge aclk);
            @(negedge aclk);
            s_axi_wdata = data;
            s_axi_wstrb = strobe;
            s_axi_wvalid = 1'b1;
            accepted = 0;
            while (!accepted) begin
                @(posedge aclk);
                if (s_axi_wready)
                    accepted = 1;
            end
            @(negedge aclk);
            s_axi_wvalid = 1'b0;
        end
    endtask

    task automatic axi_write;
        input [11:0] address;
        input [31:0] data;
        input [3:0] strobe;
        input [1:0] expected_resp;
        input integer aw_delay;
        input integer w_delay;
        input integer response_stall;
        reg [1:0] held_resp;
        begin
            fork
                send_aw(address, aw_delay);
                send_w(data, strobe, w_delay);
            join
            wait (s_axi_bvalid);
            held_resp = s_axi_bresp;
            repeat (response_stall) begin
                @(posedge aclk); #1;
                check(s_axi_bvalid && (s_axi_bresp === held_resp),
                      "B channel changed under backpressure");
            end
            check(held_resp === expected_resp, "unexpected write response");
            @(negedge aclk);
            s_axi_bready = 1'b1;
            @(posedge aclk);
            @(negedge aclk);
            s_axi_bready = 1'b0;
        end
    endtask

    task automatic axi_read;
        input [11:0] address;
        input [31:0] expected_data;
        input [31:0] mask;
        input [1:0] expected_resp;
        input integer response_stall;
        reg [31:0] held_data;
        reg [1:0] held_resp;
        integer accepted;
        begin
            @(negedge aclk);
            s_axi_araddr = address;
            s_axi_arvalid = 1'b1;
            accepted = 0;
            while (!accepted) begin
                @(posedge aclk);
                if (s_axi_arready)
                    accepted = 1;
            end
            @(negedge aclk);
            s_axi_arvalid = 1'b0;
            wait (s_axi_rvalid);
            held_data = s_axi_rdata;
            held_resp = s_axi_rresp;
            repeat (response_stall) begin
                @(posedge aclk); #1;
                check(s_axi_rvalid && (s_axi_rdata === held_data) &&
                      (s_axi_rresp === held_resp),
                      "R channel changed under backpressure");
            end
            if ((held_data & mask) !== (expected_data & mask)) begin
                $display("ERROR unexpected read data address=%03h actual=%08h expected=%08h mask=%08h",
                         address, held_data, expected_data, mask);
                errors = errors + 1;
            end
            check(held_resp === expected_resp, "unexpected read response");
            @(negedge aclk);
            s_axi_rready = 1'b1;
            @(posedge aclk);
            @(negedge aclk);
            s_axi_rready = 1'b0;
        end
    endtask

    initial begin
        aresetn = 1'b0;
        s_axi_awaddr = 0;
        s_axi_awprot = 0;
        s_axi_awvalid = 0;
        s_axi_wdata = 0;
        s_axi_wstrb = 0;
        s_axi_wvalid = 0;
        s_axi_bready = 0;
        s_axi_araddr = 0;
        s_axi_arprot = 0;
        s_axi_arvalid = 0;
        s_axi_rready = 0;
        accelerator_reset_active = 0;
        accelerator_soft_reset_safe = 1;
        accelerator_start_ready = 0;
        accelerator_busy = 0;
        accelerator_done = 0;
        accelerator_error = 0;
        accelerator_reset_required = 0;
        accelerator_error_code = 0;
        accelerator_state = 0;
        accelerator_state_cycles = 32'h1020_3040;
        accelerator_sparse_mode = 0;
        accelerator_frame_id = 16'h0021;
        fb_slot_states = 4'h2;
        sb_slot_states = 4'h1;
        expected_fb_frame_id = 16'h0021;
        expected_sb_frame_id = 16'h0021;
        expected_consume_frame_id = 16'h0021;
        fb_published_valid = 0;
        fb_published_slot = 0;
        fb_published_frame_id = 0;
        sb_committed_valid = 0;
        sb_committed_slot = 0;
        sb_committed_frame_id = 0;
        sb_released_valid = 0;
        sb_released_slot = 0;
        sb_released_frame_id = 0;
        mailbox_error_valid = 0;
        mailbox_error_code = 0;
        mailbox_error_slot = 0;
        mailbox_error_frame_id = 0;
        mailbox_irq = 0;
        fb_input_buffer_valid = 0;
        fb_input_buffer_frame_id = 16'h0021;
        spectrum_input_buffer_valid = 0;
        spectrum_input_buffer_frame_id = 16'h0021;
        active_stage_id = 4'h3;
        cache_state = 3'h4;
        compute_owner = 4'h5;
        controller_state = 6'h12;
        weight_request_count = 32'd100;
        dense_weight_request_count = 32'd80;
        sparse_weight_request_count = 32'd20;
        sparse_stage_diag_valid = 1;
        sparse_stage_diag_success = 1;
        sparse_stage_diag_stage_id = 4'd3;
        sparse_stage_diag_enabled = 1;
        sparse_stage_diag_fallback_full = 0;
        sparse_stage_actual_bytes = 32'd4096;
        sparse_stage_saved_bytes = 32'd8192;
        sparse_stage_ar_burst_count = 32'd17;
        sparse_stage_load_cycles = 32'd1234;
        profiling_read_data = 32'hface_cafe;
        profiling_snapshot_valid = 1'b1;
        profiling_frame_active = 1'b1;
        profiling_snapshot_busy = 1'b0;
        fault_valid = 0;
        fault_source = 0;
        fault_code = 0;
        fault_detail = 0;
        ps_fb_release_ready = 0;
        ps_sb_claim_ready = 0;
        ps_sb_commit_ready = 0;
        errors = 0;
        start_handshakes = 0;
        abort_pulses = 0;
        clear_error_pulses = 0;
        soft_reset_pulses = 0;
        profiling_clear_pulses = 0;
        profiling_snapshot_pulses = 0;

        repeat (4) @(posedge aclk);
        @(negedge aclk);
        aresetn = 1'b1;

        axi_read(12'h004, 32'h0000_0003, 32'hffff_ffff, 2'b00, 1);
        axi_read(12'h00c, 32'h0000_0003, 32'hffff_ffff, 2'b00, 0);
        axi_write(12'h004, 32'h0000_0001, 4'hf, 2'b00, 0, 2, 2);
        axi_write(12'h008, 32'h1234_5000, 4'hf, 2'b00, 3, 0, 0);

        // START remains pending until both ingress packets make the core ready.
        axi_write(12'h000, 32'h0000_0001, 4'h1, 2'b00, 0, 0, 1);
        repeat (3) @(posedge aclk);
        check(start_valid, "start request was not held");
        check(parameter_base_addr == 32'h1234_5000,
              "parameter base was not atomically committed");
        check(sparse_load_enable && !clear_state_on_start,
              "active config was not atomically committed");
        axi_write(12'h000, 32'h0000_0001, 4'h1, 2'b10, 1, 0, 0);
        axi_read(12'h0a0, 32'h0000_0102, 32'h0000_01ff, 2'b00, 0);

        accelerator_start_ready = 1'b1;
        @(posedge aclk);
        @(negedge aclk);
        accelerator_start_ready = 1'b0;
        repeat (2) @(posedge aclk);
        check(!start_valid && (start_handshakes == 1),
              "start handshake did not retire exactly once");

        // Clear the control-protocol error and stale interrupt state.
        axi_write(12'h000, 32'h0000_0018, 4'h1, 2'b00, 0, 0, 0);
        repeat (2) @(posedge aclk);
        check(clear_error_pulses == 1, "clear-error pulse missing");
        axi_read(12'h0a0, 32'd0, 32'h0000_01ff, 2'b00, 0);

        // Ownership commands must not collapse to a one-cycle pulse.
        axi_write(12'h040, 32'h8000_0043, 4'hf, 2'b00, 2, 0, 1);
        repeat (3) begin
            @(posedge aclk); #1;
            check(ps_fb_release_valid && ps_fb_release_slot &&
                  (ps_fb_release_frame_id == 16'h0021),
                  "FB release payload changed while stalled");
        end
        axi_write(12'h040, 32'h8000_0043, 4'hf, 2'b10, 0, 0, 0);
        ps_fb_release_ready = 1'b1;
        @(posedge aclk);
        @(negedge aclk);
        ps_fb_release_ready = 1'b0;
        check(!ps_fb_release_valid, "FB release did not retire");
        axi_write(12'h044, 32'h0000_0042, 4'hf, 2'b10, 0, 0, 0);
        axi_write(12'h044, 32'h8000_0042, 4'hf, 2'b00, 0, 1, 0);
        ps_sb_claim_ready = 1'b1;
        @(posedge aclk);
        @(negedge aclk);
        ps_sb_claim_ready = 1'b0;
        axi_write(12'h048, 32'h8000_0042, 4'hf, 2'b00, 1, 0, 0);
        ps_sb_commit_ready = 1'b1;
        @(posedge aclk);
        @(negedge aclk);
        ps_sb_commit_ready = 1'b0;

        // Interrupt status is sticky, maskable, and W1C.  A live mailbox
        // level reasserts after software acknowledges it.
        axi_write(12'h000, 32'h0000_0018, 4'h1, 2'b00, 0, 0, 0);
        axi_write(12'h028, 32'hffff_ffff, 4'hf, 2'b00, 0, 0, 0);
        axi_write(12'h024, 32'h0000_003e, 4'hf, 2'b00, 0, 0, 0);
        @(negedge aclk); accelerator_done = 1'b1;
        @(posedge aclk); @(negedge aclk); accelerator_done = 1'b0;
        repeat (1) @(posedge aclk);
        check(irq, "done interrupt did not assert");
        axi_read(12'h028, 32'h0000_0002, 32'h0000_0002, 2'b00, 0);
        axi_write(12'h028, 32'h0000_0002, 4'h1, 2'b00, 0, 0, 0);
        repeat (1) @(posedge aclk);
        check(!irq, "done interrupt did not clear");
        mailbox_irq = 1'b1;
        repeat (2) @(posedge aclk);
        check(irq, "mailbox interrupt did not assert");
        axi_write(12'h028, 32'h0000_0008, 4'h1, 2'b00, 0, 0, 0);
        repeat (2) @(posedge aclk);
        check(irq, "live mailbox interrupt did not reassert");
        mailbox_irq = 1'b0;
        axi_write(12'h028, 32'h0000_0008, 4'h1, 2'b00, 0, 0, 0);

        // First-fault information remains stable until explicit clear/reset.
        fault_valid = 1'b1;
        fault_source = 8'h07;
        fault_code = 8'h44;
        fault_detail = 32'hdead_beef;
        @(posedge aclk);
        @(negedge aclk);
        fault_source = 8'h08;
        fault_code = 8'h55;
        fault_detail = 32'hcafe_f00d;
        @(posedge aclk);
        @(negedge aclk);
        fault_valid = 1'b0;
        axi_read(12'h02c, 32'h0107_4400, 32'hffff_ff00, 2'b00, 2);
        axi_read(12'h030, 32'hdead_beef, 32'hffff_ffff, 2'b00, 0);
        axi_read(12'h034, 32'h0000_0021, 32'hffff_ffff, 2'b00, 0);

        // Fixed packet ABI and representative diagnostics are software-visible.
        axi_read(12'h038, {16'd512, 16'd512}, 32'hffff_ffff, 2'b00, 0);
        axi_read(12'h03c, 32'd2048, 32'hffff_ffff, 2'b00, 0);
        axi_read(12'h080, 32'd100, 32'hffff_ffff, 2'b00, 0);
        axi_read(12'h090, 32'd8192, 32'hffff_ffff, 2'b00, 0);
        axi_read(12'h0a4, 32'h0005_0003, 32'hffff_ffff, 2'b00, 0);
        axi_read(12'h0a8, 32'h0000_0000, 32'hffff_ffff, 2'b00, 0);
        axi_read(12'h0b0, 32'h0000_0006, 32'hffff_ffff, 2'b00, 0);
        axi_read(12'h100, 32'hface_cafe, 32'hffff_ffff, 2'b00, 0);
        check(profiling_read_index == 8'd0,
              "profile read window index was not delegated");
        axi_read(12'h3fc, 32'hface_cafe, 32'hffff_ffff, 2'b00, 0);
        check(profiling_read_index == 8'd191,
              "profile read window last index was not delegated");
        axi_write(12'h0ac, 32'h0000_0007, 4'hf, 2'b00, 0, 0, 0);
        repeat (2) @(posedge aclk);
        check(profiling_enable && (profiling_clear_pulses == 1) &&
              (profiling_snapshot_pulses == 1),
              "profile control enable/pulses were not exact");
        check(!profiling_clear_pulse && !profiling_snapshot_pulse,
              "profile command pulses were not one cycle");
        axi_read(12'h0ac, 32'h0000_0001, 32'hffff_ffff, 2'b00, 0);
        axi_read(12'h0b0, 32'h0000_0007, 32'hffff_ffff, 2'b00, 0);
        axi_write(12'h0ac, 32'h0000_0000, 4'hf, 2'b00, 0, 0, 0);
        check(!profiling_enable, "profile enable did not clear");
        axi_read(12'h015, 32'd0, 32'd0, 2'b10, 0);

        // Soft reset is rejected unless the custom datapath and every held
        // control command are quiescent.
        accelerator_soft_reset_safe = 1'b0;
        axi_write(12'h000, 32'h0000_0004, 4'h1, 2'b10, 0, 0, 0);
        repeat (2) @(posedge aclk);
        check(soft_reset_pulses == 0,
              "unsafe soft reset unexpectedly emitted a pulse");
        axi_read(12'h0a0, 32'h0000_0107, 32'h0000_01ff, 2'b00, 0);
        axi_write(12'h000, 32'h0000_0008, 4'h1, 2'b00, 0, 0, 0);
        accelerator_soft_reset_safe = 1'b1;

        axi_write(12'h048, 32'h8000_0042, 4'hf, 2'b00, 0, 0, 0);
        axi_write(12'h000, 32'h0000_0004, 4'h1, 2'b10, 0, 0, 0);
        ps_sb_commit_ready = 1'b1;
        @(posedge aclk);
        @(negedge aclk);
        ps_sb_commit_ready = 1'b0;
        axi_write(12'h000, 32'h0000_0008, 4'h1, 2'b00, 0, 0, 0);

        // A legal request remains pending until the live control plane sees
        // the data-plane reset edge. Quiesce first fences new admissions; a
        // duplicate reset request then fails closed.
        axi_write(12'h000, 32'h0000_0020, 4'h1, 2'b00, 0, 0, 0);
        repeat (2) @(posedge aclk);
        check(reset_quiesce_request,
              "reset quiesce fence did not assert");
        axi_read(12'h0a8, 32'h0000_0009, 32'hffff_ffff, 2'b00, 0);
        axi_write(12'h000, 32'h0000_0004, 4'h1, 2'b00, 0, 0, 0);
        repeat (4) @(posedge aclk);
        check((soft_reset_pulses >= 3) && soft_reset_pulse &&
              !ps_sb_commit_valid && !start_valid,
              "soft reset request was not held until reset acknowledgement");
        axi_read(12'h0a8, 32'h0000_000d, 32'hffff_ffff, 2'b00, 0);
        axi_write(12'h000, 32'h0000_0004, 4'h1, 2'b10, 0, 0, 0);
        axi_read(12'h0a0, 32'h0000_0108, 32'h0000_01ff, 2'b00, 0);
        @(negedge aclk); accelerator_reset_active = 1'b1;
        repeat (2) @(posedge aclk);
        @(negedge aclk); accelerator_reset_active = 1'b0;
        repeat (2) @(posedge aclk);
        check(!soft_reset_pulse,
              "soft reset request did not retire after acknowledgement");
        axi_read(12'h0a8, 32'h0001_0000, 32'hffff_ffff, 2'b00, 0);
        check(!reset_quiesce_request,
              "reset quiesce fence did not retire after reset edge");
        axi_read(12'h0a0, 32'd0, 32'h0000_01ff, 2'b00, 0);

        // Abort is deliberately a pulse; the accelerator owns abort draining.
        axi_write(12'h000, 32'h0000_0002, 4'h1, 2'b00, 0, 0, 0);
        repeat (2) @(posedge aclk);
        check(abort_pulses == 1, "abort pulse missing");

        if (errors == 0) begin
            $display("ACCEL_CONTROL_METRIC checks=atomic_start,held_mailbox,irq_first_fault,reset_quiesce,reset_epoch,profiling_window");
            $display("PASS tb_accelerator_control_axil");
        end else begin
            $fatal(1, "FAIL tb_accelerator_control_axil errors=%0d", errors);
        end
        $finish;
    end
endmodule
