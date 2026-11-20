`timescale 1ns/1ps
`include "memory/model_memory_v4_map.vh"

module tb_sequential_v4_pe_memory_subsystem;
    localparam [31:0] PARAMETER_BASE = 32'h1000_0000;
    localparam integer IMAGE_BYTES = `MODEL_V4_IMAGE_BYTES;

    reg clk;
    reg rst_n;
    reg abort;
    reg clear_error;
    reg clear_state;
    reg [31:0] parameter_base_addr;

    reg stage_req_valid;
    wire stage_req_ready;
    reg [3:0] stage_id;
    reg [1:0] stage_bank;
    wire stage_load_done;
    wire stage_load_error;

    reg fb_start;
    wire fb_start_ready;
    reg [1:0] fb_stage;
    wire fb_done;
    wire fb_error;
    reg [2:0] sb_start;
    wire sb_start_ready;
    reg [1:0] sb_stage;
    reg [1:0] sb_shared_branch;
    reg [1:0] sb_context_0;
    reg [1:0] sb_context_1;
    reg [1:0] sb_context_2;
    wire [2:0] sb_done;
    wire [2:0] sb_error;

    wire feature_req_valid;
    wire feature_req_ready;
    wire [3:0] feature_req_stage_id;
    wire [1:0] feature_req_branch;
    wire [1:0] feature_req_context;
    wire [9:0] feature_req_source;
    wire [7:0] feature_req_tag;
    reg feature_rsp_valid;
    wire feature_rsp_ready;
    reg signed [7:0] feature_rsp_value;
    reg [7:0] feature_rsp_tag;
    reg feature_rsp_error;

    wire coefficient_valid;
    wire coefficient_ready;
    wire signed [7:0] coefficient_value;
    wire [8:0] coefficient_index;
    wire [15:0] coefficient_tag;
    wire coefficient_last;

    wire [31:0] m_axi_araddr;
    wire [0:0] m_axi_arid;
    wire [7:0] m_axi_arlen;
    wire [2:0] m_axi_arsize;
    wire [1:0] m_axi_arburst;
    wire [2:0] m_axi_arprot;
    wire [3:0] m_axi_arcache;
    wire [3:0] m_axi_arqos;
    wire m_axi_arlock;
    wire m_axi_arvalid;
    wire m_axi_arready;
    reg [63:0] m_axi_rdata;
    reg [0:0] m_axi_rid;
    reg [1:0] m_axi_rresp;
    reg m_axi_rlast;
    reg m_axi_rvalid;
    wire m_axi_rready;

    wire [2:0] pe_barrier_idle;
    wire [2:0] pe_fault;
    wire reset_required;
    wire [3:0] active_stage_id;
    wire [2:0] cache_state;
    wire [3:0] compute_owner;
    wire [2:0] lut_adapter_state;
    wire [11:0] lut_accepted_bytes;
    wire [1:0] lut_configuration_starts;
    wire [5:0] controller_state;
    wire [5:0] controller_row_tile;
    wire [31:0] weight_request_count;
    wire [31:0] dense_weight_request_count;
    wire [31:0] sparse_weight_request_count;
    wire memory_error_valid;
    wire [7:0] memory_error_code;
    wire context_error_valid;
    wire [7:0] context_error_code;
    wire controller_error_valid;
    wire [7:0] controller_error_code;
    wire integration_error_valid;
    wire [7:0] integration_error_code;
    wire [31:0] integration_error_detail;

    reg [3:0] reference_stage_id;
    wire ref_valid;
    wire ref_kind;
    wire [31:0] ref_dram_offset;
    wire [31:0] ref_transfer_bytes;
    wire [1:0] ref_matrix_count;
    wire [31:0] ref_matrix0_word_offset;
    wire [9:0] ref_matrix0_sources;
    wire [5:0] ref_matrix0_row_tiles;
    wire [31:0] ref_matrix1_word_offset;
    wire [9:0] ref_matrix1_sources;
    wire [5:0] ref_matrix1_row_tiles;
    wire [31:0] ref_param_word_offset;
    wire [7:0] ref_param_record_words;
    wire [12:0] ref_param_response_bits;
    wire [5:0] ref_param_tiles;
    wire ref_uses_sigmoid;
    wire [2:0] ref_sigmoid_select;

    model_memory_v4_table reference_table (
        .stage_id(reference_stage_id),
        .stage_valid(ref_valid),
        .stage_kind(ref_kind),
        .dram_byte_offset(ref_dram_offset),
        .transfer_bytes(ref_transfer_bytes),
        .matrix_count(ref_matrix_count),
        .matrix0_word_offset(ref_matrix0_word_offset),
        .matrix0_sources(ref_matrix0_sources),
        .matrix0_row_tiles(ref_matrix0_row_tiles),
        .matrix1_word_offset(ref_matrix1_word_offset),
        .matrix1_sources(ref_matrix1_sources),
        .matrix1_row_tiles(ref_matrix1_row_tiles),
        .param_word_offset(ref_param_word_offset),
        .param_record_words(ref_param_record_words),
        .param_response_bits(ref_param_response_bits),
        .param_tiles(ref_param_tiles),
        .uses_sigmoid_table(ref_uses_sigmoid),
        .sigmoid_table_select(ref_sigmoid_select)
    );

    sequential_v4_pe_memory_subsystem #(
        .LOAD_TIMEOUT_CYCLES(128),
        .CONTROLLER_TIMEOUT_CYCLES(1000),
        .LUT_STALL_TIMEOUT_CYCLES(128)
    ) dut (
        .clk(clk), .rst_n(rst_n), .abort(abort),
        .clear_error(clear_error), .clear_state(clear_state),
        .parameter_base_addr(parameter_base_addr),
        .stage_req_valid(stage_req_valid),
        .stage_req_ready(stage_req_ready),
        .stage_id(stage_id), .stage_bank(stage_bank),
        .stage_load_done(stage_load_done),
        .stage_load_error(stage_load_error),
        .fb_start(fb_start), .fb_start_ready(fb_start_ready),
        .fb_stage(fb_stage), .fb_done(fb_done), .fb_error(fb_error),
        .sb_start(sb_start), .sb_start_ready(sb_start_ready),
        .sb_stage(sb_stage), .sb_shared_branch(sb_shared_branch),
        .sb_context_0(sb_context_0), .sb_context_1(sb_context_1),
        .sb_context_2(sb_context_2), .sb_done(sb_done),
        .sb_error(sb_error),
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
        .coefficient_valid(coefficient_valid),
        .coefficient_ready(coefficient_ready),
        .coefficient_value(coefficient_value),
        .coefficient_index(coefficient_index),
        .coefficient_tag(coefficient_tag),
        .coefficient_last(coefficient_last),
        .m_axi_araddr(m_axi_araddr), .m_axi_arid(m_axi_arid),
        .m_axi_arlen(m_axi_arlen), .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst), .m_axi_arprot(m_axi_arprot),
        .m_axi_arcache(m_axi_arcache), .m_axi_arqos(m_axi_arqos),
        .m_axi_arlock(m_axi_arlock), .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready), .m_axi_rdata(m_axi_rdata),
        .m_axi_rid(m_axi_rid), .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast), .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        .pe_barrier_idle(pe_barrier_idle), .pe_fault(pe_fault),
        .reset_required(reset_required), .active_stage_id(active_stage_id),
        .cache_state(cache_state), .compute_owner(compute_owner),
        .lut_adapter_state(lut_adapter_state),
        .lut_accepted_bytes(lut_accepted_bytes),
        .lut_configuration_starts(lut_configuration_starts),
        .controller_state(controller_state),
        .controller_row_tile(controller_row_tile),
        .weight_request_count(weight_request_count),
        .dense_weight_request_count(dense_weight_request_count),
        .sparse_weight_request_count(sparse_weight_request_count),
        .memory_error_valid(memory_error_valid),
        .memory_error_code(memory_error_code),
        .context_error_valid(context_error_valid),
        .context_error_code(context_error_code),
        .controller_error_valid(controller_error_valid),
        .controller_error_code(controller_error_code),
        .integration_error_valid(integration_error_valid),
        .integration_error_code(integration_error_code),
        .integration_error_detail(integration_error_detail)
    );

    reg [7:0] dram [0:IMAGE_BYTES-1];
    reg dram_active;
    reg [31:0] dram_read_addr;
    reg [8:0] dram_beats_left;
    reg force_axi_stall;
    reg inject_axi_error;
    integer axi_command_bytes;
    integer axi_commands;
    integer cycle_count;

    integer failures;
    integer checks;
    integer epoch_lut_observed;
    integer first_load_in_epoch;
    integer feature_accept_count;
    integer coefficient_accept_count;
    integer state_write_count;
    integer active_finalize_count;
    integer commit_done_count;
    integer total_sparse_requests;
    integer completed_jobs;
    integer completed_stage_loads;
    reg projection_monitor_active;
    integer projection_expected_index;
    integer projection_expected_count;
    reg coefficient_stalled;
    reg signed [7:0] held_coefficient_value;
    reg [8:0] held_coefficient_index;
    reg [15:0] held_coefficient_tag;
    reg held_coefficient_last;

    reg feature_pending;
    reg [2:0] feature_delay;
    reg [7:0] pending_feature_tag;

    always #5 clk = ~clk;

    task fail;
        input [8*200-1:0] message;
        begin
            failures = failures + 1;
            $display("FAIL: %0s time=%0t cycle=%0d ctrl=%0d", message,
                     $time, cycle_count, controller_state);
        end
    endtask

    task check;
        input condition;
        input [8*200-1:0] message;
        begin
            checks = checks + 1;
            if (!condition)
                fail(message);
        end
    endtask

    function [63:0] image_word;
        input [31:0] byte_address;
        integer lane;
        integer image_index;
        begin
            image_word = 64'd0;
            image_index = byte_address - PARAMETER_BASE;
            for (lane = 0; lane < 8; lane = lane + 1) begin
                if ((image_index + lane >= 0) &&
                    (image_index + lane < IMAGE_BYTES))
                    image_word[lane*8 +: 8] = dram[image_index + lane];
                else
                    image_word[lane*8 +: 8] = 8'hxx;
            end
        end
    endfunction

    assign m_axi_arready = !dram_active && !force_axi_stall &&
                           (cycle_count[2:0] != 3'b101);

    // One outstanding AXI burst with deterministic command/data stalls.
    always @(posedge clk) begin
        if (!rst_n) begin
            dram_active <= 1'b0;
            dram_read_addr <= 32'd0;
            dram_beats_left <= 9'd0;
            m_axi_rdata <= 64'd0;
            m_axi_rid <= 1'b0;
            m_axi_rresp <= 2'b00;
            m_axi_rlast <= 1'b0;
            m_axi_rvalid <= 1'b0;
            axi_command_bytes <= 0;
            axi_commands <= 0;
        end else begin
            if (m_axi_arvalid && m_axi_arready) begin
                dram_active <= 1'b1;
                dram_read_addr <= m_axi_araddr;
                dram_beats_left <= {1'b0, m_axi_arlen} + 1'b1;
                axi_command_bytes <= axi_command_bytes +
                                     ((m_axi_arlen + 1) * 8);
                axi_commands <= axi_commands + 1;
                check((m_axi_arid == 0) && (m_axi_arsize == 3'd3) &&
                      (m_axi_arburst == 2'b01) &&
                      (m_axi_arprot == 3'b000) &&
                      (m_axi_arcache == 4'b0011) &&
                      (m_axi_arqos == 0) && !m_axi_arlock,
                      "AXI sideband mismatch");
                check(m_axi_araddr[2:0] == 0,
                      "AXI address is not 64-bit aligned");
                check((m_axi_araddr[11:0] +
                       ((m_axi_arlen + 1) << m_axi_arsize)) <= 4096,
                      "AXI burst crossed a 4 KiB boundary");
            end
            if (dram_active && !m_axi_rvalid && !force_axi_stall &&
                (cycle_count[2:0] != 3'b011)) begin
                m_axi_rdata <= image_word(dram_read_addr);
                m_axi_rid <= 1'b0;
                m_axi_rresp <= inject_axi_error ? 2'b10 : 2'b00;
                m_axi_rlast <= (dram_beats_left == 1);
                m_axi_rvalid <= 1'b1;
            end
            if (m_axi_rvalid && m_axi_rready) begin
                m_axi_rvalid <= 1'b0;
                if (m_axi_rlast) begin
                    dram_active <= 1'b0;
                end else begin
                    dram_read_addr <= dram_read_addr + 8;
                    dram_beats_left <= dram_beats_left - 1'b1;
                end
            end
        end
    end

    assign feature_req_ready = !feature_pending && !feature_rsp_valid &&
                               (cycle_count[2:0] != 3'b110);
    always @(posedge clk) begin
        if (!rst_n) begin
            feature_pending <= 1'b0;
            feature_delay <= 3'd0;
            pending_feature_tag <= 8'd0;
            feature_rsp_valid <= 1'b0;
            feature_rsp_value <= 8'sd0;
            feature_rsp_tag <= 8'd0;
            feature_rsp_error <= 1'b0;
            feature_accept_count <= 0;
        end else begin
            if (feature_req_valid && feature_req_ready) begin
                feature_pending <= 1'b1;
                feature_delay <= {1'b0, feature_req_source[1:0]} + 1'b1;
                pending_feature_tag <= feature_req_tag;
                feature_accept_count <= feature_accept_count + 1;
                check((feature_req_stage_id == 0) ||
                      (feature_req_stage_id == 3) ||
                      (feature_req_stage_id == 6) ||
                      (feature_req_stage_id == 9),
                      "feature request escaped a dense GSU1 stage");
            end
            if (feature_pending && !feature_rsp_valid) begin
                if (feature_delay != 0)
                    feature_delay <= feature_delay - 1'b1;
                else begin
                    feature_rsp_valid <= 1'b1;
                    feature_rsp_value <= 8'sd0;
                    feature_rsp_tag <= pending_feature_tag;
                end
            end
            if (feature_rsp_valid && feature_rsp_ready) begin
                feature_rsp_valid <= 1'b0;
                feature_pending <= 1'b0;
            end
        end
    end

    assign coefficient_ready = (cycle_count[3:0] != 4'h5) &&
                               (cycle_count[3:0] != 4'hc);
    always @(posedge clk) begin
        if (!rst_n) begin
            coefficient_accept_count <= 0;
            coefficient_stalled <= 1'b0;
            held_coefficient_value <= 8'sd0;
            held_coefficient_index <= 9'd0;
            held_coefficient_tag <= 16'd0;
            held_coefficient_last <= 1'b0;
        end else begin
            if (coefficient_valid && !coefficient_ready) begin
                if (coefficient_stalled) begin
                    check((coefficient_value === held_coefficient_value) &&
                          (coefficient_index === held_coefficient_index) &&
                          (coefficient_tag === held_coefficient_tag) &&
                          (coefficient_last === held_coefficient_last),
                          "coefficient changed while stalled");
                end else begin
                    coefficient_stalled <= 1'b1;
                    held_coefficient_value <= coefficient_value;
                    held_coefficient_index <= coefficient_index;
                    held_coefficient_tag <= coefficient_tag;
                    held_coefficient_last <= coefficient_last;
                end
            end else begin
                coefficient_stalled <= 1'b0;
            end
            if (coefficient_valid && coefficient_ready) begin
                coefficient_accept_count <= coefficient_accept_count + 1;
                check(projection_monitor_active,
                      "coefficient emitted outside projection job");
                check(coefficient_index == projection_expected_index[8:0],
                      "projection coefficient index/order mismatch");
                check(coefficient_tag[15:14] == 2'b01,
                      "projection coefficient tag kind mismatch");
                check(coefficient_last ==
                      (projection_expected_index ==
                       projection_expected_count - 1),
                      "projection coefficient last mismatch");
                projection_expected_index <= projection_expected_index + 1;
            end
        end
    end

    // Connected internal-boundary monitors.  They observe only accepted
    // transactions and do not alter the production hierarchy.
    always @(posedge clk) begin
        if (!rst_n) begin
            cycle_count <= 0;
            epoch_lut_observed <= 0;
            state_write_count <= 0;
            active_finalize_count <= 0;
            commit_done_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            if (dut.pe_sigmoid_cfg_data_fire) begin
                check(epoch_lut_observed < 2040,
                      "too many LUT configuration bytes");
                check(dut.service_lut_cfg_stage_id ==
                      (epoch_lut_observed / 255),
                      "LUT table order mismatch");
                check(dut.service_lut_cfg_addr ==
                      (epoch_lut_observed % 255),
                      "LUT address order mismatch");
                check(dut.service_lut_cfg_data ===
                      dram[`MODEL_V4_GLOBAL_SIGMOID_LUT_DRAM_OFFSET +
                           epoch_lut_observed],
                      "LUT byte differs from v4 image");
                epoch_lut_observed <= epoch_lut_observed + 1;
            end
            if (dut.pe_state_write_valid && dut.pe_state_write_ready)
                state_write_count <= state_write_count + 1;
            if (dut.pe_active_cmd_valid && dut.pe_active_cmd_ready &&
                dut.pe_active_cmd_finalize)
                active_finalize_count <= active_finalize_count + 1;
            if (dut.context_commit_done)
                commit_done_count <= commit_done_count + 1;
            check((compute_owner == 4'b0000) ||
                  (compute_owner == 4'b0001) ||
                  (compute_owner == 4'b0010) ||
                  (compute_owner == 4'b0100),
                  "unsupported or overlapping PE owner");
        end
    end

    task reset_dut;
        begin
            rst_n = 1'b0;
            abort = 1'b0;
            clear_error = 1'b0;
            clear_state = 1'b0;
            stage_req_valid = 1'b0;
            stage_id = 4'd0;
            stage_bank = 2'd0;
            fb_start = 1'b0;
            fb_stage = 2'd0;
            sb_start = 3'd0;
            sb_stage = 2'd0;
            sb_shared_branch = 2'd0;
            sb_context_0 = 2'd0;
            sb_context_1 = 2'd0;
            sb_context_2 = 2'd0;
            force_axi_stall = 1'b0;
            inject_axi_error = 1'b0;
            projection_monitor_active = 1'b0;
            projection_expected_index = 0;
            projection_expected_count = 0;
            first_load_in_epoch = 1;
            repeat (6) @(posedge clk);
            @(negedge clk);
            rst_n = 1'b1;
            repeat (4) @(posedge clk);
            #1;
            check(!reset_required && (cache_state == 0) &&
                  (lut_adapter_state == 0),
                  "coordinated reset did not restore subsystem");
        end
    endtask

    task request_legal_stage;
        input [3:0] requested_stage;
        integer timeout;
        integer bytes_before;
        integer expected_bytes;
        begin
            reference_stage_id = requested_stage;
            #1;
            check(ref_valid, "reference stage invalid");
            bytes_before = axi_command_bytes;
            expected_bytes = ref_transfer_bytes +
                             (first_load_in_epoch ? 2040 : 0);
            @(negedge clk);
            stage_id = requested_stage;
            stage_bank = 2'd0;
            stage_req_valid = 1'b1;
            timeout = 0;
            while (!stage_req_ready && timeout < 1000) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            check(timeout < 1000, "legal stage request not accepted");
            @(posedge clk);
            @(negedge clk);
            stage_req_valid = 1'b0;
            timeout = 0;
            while (!stage_load_done && !stage_load_error &&
                   timeout < 1000000) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            check(timeout < 1000000, "legal stage load timed out");
            check(stage_load_done && !stage_load_error && !reset_required,
                  "legal stage load failed");
            check((active_stage_id == requested_stage) &&
                  (cache_state == 6),
                  "loaded stage identity/cache state mismatch");
            check((axi_command_bytes - bytes_before) == expected_bytes,
                  "stage did not perform exact full-image transfer bytes");
            if (first_load_in_epoch) begin
                check((epoch_lut_observed == 2040) &&
                      (lut_accepted_bytes == 2040) &&
                      (lut_configuration_starts == 1) &&
                      (lut_adapter_state == 4),
                      "first load did not configure one exact global LUT");
                first_load_in_epoch = 0;
            end else begin
                check((epoch_lut_observed == 2040) &&
                      (lut_configuration_starts == 1),
                      "later stage reloaded global LUT");
            end
            completed_stage_loads = completed_stage_loads + 1;
            @(negedge clk);
        end
    endtask

    task run_job;
        input integer is_fb;
        input [3:0] absolute_stage;
        input [1:0] branch;
        input [1:0] context_id;
        input integer final_context;
        integer timeout;
        integer feature_before;
        integer coefficient_before;
        integer state_before;
        integer finalize_before;
        integer commit_before;
        integer expected_dense;
        integer expected_weight;
        integer expected_coefficients;
        begin
            reference_stage_id = absolute_stage;
            #1;
            feature_before = feature_accept_count;
            coefficient_before = coefficient_accept_count;
            state_before = state_write_count;
            finalize_before = active_finalize_count;
            commit_before = commit_done_count;
            expected_dense = (((absolute_stage == 0) ||
                               (absolute_stage == 3) ||
                               (absolute_stage == 6) ||
                               (absolute_stage == 9))
                              ? ref_matrix0_sources * ref_param_tiles : 0);
            expected_coefficients = ref_kind ? ref_param_tiles * 16 : 0;
            projection_monitor_active = ref_kind;
            projection_expected_index = 0;
            projection_expected_count = expected_coefficients;

            @(negedge clk);
            if (is_fb) begin
                fb_stage = absolute_stage[1:0];
                fb_start = 1'b1;
            end else begin
                sb_stage = (absolute_stage - (3 + branch*3));
                sb_shared_branch = branch;
                sb_context_0 = context_id;
                sb_context_1 = 2'd0;
                sb_context_2 = 2'd0;
                sb_start = 3'b001;
            end
            timeout = 0;
            while (!(is_fb ? fb_start_ready : sb_start_ready) &&
                   timeout < 1000) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            check(timeout < 1000, "job request not accepted");
            @(posedge clk);
            @(negedge clk);
            fb_start = 1'b0;
            sb_start = 3'b000;

            timeout = 0;
            while (!(is_fb ? fb_done : sb_done[0]) &&
                   !reset_required && timeout < 5000000) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            check(timeout < 5000000, "connected job timed out");
            check(!reset_required && !fb_error && (sb_error == 0),
                  "connected job entered fatal state");
            check(is_fb ? fb_done : sb_done[0],
                  "connected job completed without matching done");
            check(weight_request_count ==
                  dense_weight_request_count + sparse_weight_request_count,
                  "weight counter partition mismatch");
            check(dense_weight_request_count == expected_dense,
                  "dense weight count mismatch");
            expected_weight = expected_dense;
            if (ref_kind) begin
                expected_weight =
                    dut.u_job_controller.matrix0_active_count_q *
                    ref_param_tiles;
            end else if (expected_dense != 0) begin
                expected_weight = expected_dense +
                    dut.u_job_controller.matrix1_active_count_q *
                    ref_param_tiles;
            end else begin
                expected_weight =
                    (dut.u_job_controller.matrix0_active_count_q +
                     dut.u_job_controller.matrix1_active_count_q) *
                    ref_param_tiles;
            end
            check(weight_request_count == expected_weight,
                  "active-list weight suppression count mismatch");
            check((feature_accept_count - feature_before) == expected_dense,
                  "dense feature request count mismatch");
            check((coefficient_accept_count - coefficient_before) ==
                  expected_coefficients,
                  "projection coefficient count mismatch");
            check(projection_expected_index == expected_coefficients,
                  "projection coefficient stream did not finish in order");
            if (ref_kind) begin
                check((state_write_count == state_before) &&
                      (active_finalize_count == finalize_before) &&
                      (commit_done_count == commit_before),
                      "projection touched recurrent state/list lifecycle");
            end else begin
                check((state_write_count - state_before) ==
                      ref_param_tiles * 16,
                      "GSU dense state write count mismatch");
                check((active_finalize_count - finalize_before) == 1,
                      "GSU active list did not finalize exactly once");
                check((commit_done_count - commit_before) == 1,
                      "GSU context mapping did not commit exactly once");
            end
            check(cache_state == (final_context ? 0 : 6),
                  "shared stage retention/release policy mismatch");
            check(pe_barrier_idle == 3'b111,
                  "job done preceded complete PE barrier");
            total_sparse_requests = total_sparse_requests +
                                    sparse_weight_request_count;
            completed_jobs = completed_jobs + 1;
            projection_monitor_active = 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    task run_frame;
        input integer frame_number;
        integer stage;
        integer context_index;
        integer branch;
        integer context_count;
        begin
            for (stage = 0; stage < 12; stage = stage + 1) begin
                request_legal_stage(stage[3:0]);
                if (stage < 3) begin
                    run_job(1, stage[3:0], 0, 0, 1);
                end else begin
                    branch = (stage - 3) / 3;
                    case (branch)
                        0: context_count = 4;
                        1: context_count = 3;
                        default: context_count = 2;
                    endcase
                    for (context_index = 0; context_index < context_count;
                         context_index = context_index + 1)
                        run_job(0, stage[3:0], branch[1:0],
                                context_index[1:0],
                                context_index == context_count - 1);
                end
            end
            $display("INFO frame=%0d jobs=%0d sparse_requests=%0d",
                     frame_number, completed_jobs, total_sparse_requests);
        end
    endtask

    task wait_for_reset_required;
        input [8*160-1:0] reason;
        integer timeout;
        begin
            timeout = 0;
            while (!reset_required && timeout < 1000) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            check(timeout < 1000, reason);
            check((pe_fault == 3'b001) && fb_error &&
                  (sb_error == 3'b001),
                  "aggregate reset-only fault outputs mismatch");
        end
    endtask

    integer image_file;
    integer bytes_read;
    integer timeout;
    integer ar_before;
    reg [8*256-1:0] image_path;

    initial begin
        if (!$value$plusargs("IMAGE=%s", image_path))
            image_path = "parameters_v4.bin";
        image_file = $fopen(image_path, "rb");
        if (image_file == 0)
            $fatal(1, "FAIL cannot open v4 image %0s", image_path);
        bytes_read = $fread(dram, image_file);
        $fclose(image_file);
        if (bytes_read != IMAGE_BYTES)
            $fatal(1, "FAIL image bytes=%0d expected=%0d",
                   bytes_read, IMAGE_BYTES);

        clk = 1'b0;
        rst_n = 1'b0;
        parameter_base_addr = PARAMETER_BASE;
        reference_stage_id = 4'd0;
        failures = 0;
        checks = 0;
        total_sparse_requests = 0;
        completed_jobs = 0;
        completed_stage_loads = 0;

        reset_dut();
        run_frame(0);
        run_frame(1);
        check(completed_stage_loads == 24,
              "two-frame run did not load all twelve stages twice");
        check(completed_jobs == 60,
              "two-frame run did not execute all 20 logical jobs per layer");
        check(total_sparse_requests > 0,
              "later produced active lists never drove sparse cache reads");
        check((epoch_lut_observed == 2040) &&
              (lut_configuration_starts == 1),
              "normal two-frame run configured LUT more than once");

        // Unsupported physical stage bank is consumed as a diagnostic event.
        reset_dut();
        @(negedge clk);
        stage_id = 4'd0;
        stage_bank = 2'd1;
        stage_req_valid = 1'b1;
        while (!stage_req_ready) @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        stage_req_valid = 1'b0;
        #1;
        check(stage_load_done && stage_load_error,
              "invalid bank did not produce terminal load diagnostic");
        wait_for_reset_required("invalid bank did not become fatal");
        check(integration_error_valid && (integration_error_code == 8'h01),
              "invalid bank fault identity mismatch");
        clear_error = 1'b1;
        @(posedge clk);
        @(negedge clk);
        clear_error = 1'b0;
        check(reset_required && !stage_req_ready,
              "clear_error illegally recovered integration fault");

        // Unsupported parallel subband engine is fatal after a legal stage.
        reset_dut();
        request_legal_stage(4'd0);
        @(negedge clk);
        sb_start = 3'b010;
        sb_stage = 2'd0;
        sb_shared_branch = 2'd0;
        while (!sb_start_ready) @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        sb_start = 3'b000;
        wait_for_reset_required("parallel subband engine did not become fatal");
        check(integration_error_valid && (integration_error_code == 8'h02),
              "parallel subband fault identity mismatch");

        // AXI response error is owned by memory_service and requires reset.
        reset_dut();
        inject_axi_error = 1'b1;
        @(negedge clk);
        stage_id = 4'd0;
        stage_bank = 2'd0;
        stage_req_valid = 1'b1;
        while (!stage_req_ready) @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        stage_req_valid = 1'b0;
        timeout = 0;
        while (!stage_load_error && timeout < 1000) begin
            @(posedge clk);
            #1;
            timeout = timeout + 1;
        end
        check(timeout < 1000, "AXI error did not terminate stage load");
        wait_for_reset_required("AXI error did not require reset");
        check(memory_error_valid && (memory_error_code == 8'h06),
              "AXI error source/code mismatch");

        // Explicit abort after an accepted burst is reset-only fatal.
        reset_dut();
        ar_before = axi_commands;
        @(negedge clk);
        stage_id = 4'd1;
        stage_req_valid = 1'b1;
        while (!stage_req_ready) @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        stage_req_valid = 1'b0;
        timeout = 0;
        while ((axi_commands == ar_before) && timeout < 1000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        check(timeout < 1000, "abort test did not issue AXI command");
        @(negedge clk);
        abort = 1'b1;
        @(posedge clk);
        @(negedge clk);
        abort = 1'b0;
        wait_for_reset_required("accepted-load abort did not become fatal");
        check(memory_error_valid && (memory_error_code == 8'h0b),
              "abort fault source/code mismatch");

        // The frozen PE's simulation-only assertions intentionally terminate
        // on injected overflow/protocol faults.  Keep this connected run
        // assertion-enabled and cover the two aggregate OR terms structurally.
        reset_dut();

        if (failures == 0)
            $display("PASS tb_sequential_v4_pe_memory_subsystem checks=%0d jobs=%0d stages=%0d sparse=%0d",
                     checks, completed_jobs, completed_stage_loads,
                     total_sparse_requests);
        else
            $fatal(1, "FAIL tb_sequential_v4_pe_memory_subsystem errors=%0d checks=%0d",
                   failures, checks);
        #20;
        $finish;
    end
endmodule
