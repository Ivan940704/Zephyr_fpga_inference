`timescale 1ns/1ps
`include "sparse_memory_v4_map_v1.vh"

module tb_sequential_v4_sparse_memory_subsystem;
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
    reg sparse_load_enable;
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
    wire quiescent;
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
    wire [1:0] context_port_owner;
    wire planner_error_valid;
    wire [7:0] planner_error_code;
    wire [31:0] planner_error_detail;
    wire stage_diag_valid;
    wire stage_diag_success;
    wire [3:0] stage_diag_stage_id;
    wire stage_diag_sparse_enable;
    wire stage_diag_fallback_full;
    wire [31:0] stage_dense_reference_bytes;
    wire [31:0] stage_planned_bytes;
    wire [31:0] stage_actual_bytes;
    wire [31:0] stage_saved_bytes;
    wire [8:0] stage_union_count0;
    wire [8:0] stage_union_count1;
    wire [15:0] stage_copy_command_count;
    wire [31:0] stage_ar_burst_count;
    wire [31:0] stage_load_cycles;
    wire [31:0] epoch_lut_actual_bytes;
    wire integration_error_valid;
    wire [7:0] integration_error_code;
    wire [31:0] integration_error_detail;

    // Direct CP5 check port for the present-aware adapter.  This second,
    // isolated instance proves reset/clear, an empty active-list commit, the
    // immediately following descriptor, and held-response backpressure
    // independently of the much longer connected PE run.
    reg probe_clear_state;
    reg probe_open_valid;
    wire probe_open_ready;
    reg [4:0] probe_open_id;
    reg [5:0] probe_open_rows;
    reg probe_desc_req_valid;
    wire probe_desc_req_ready;
    reg [4:0] probe_desc_req_id;
    reg [7:0] probe_desc_req_tag;
    wire probe_desc_rsp_valid;
    reg probe_desc_rsp_ready;
    wire probe_desc_rsp_present;
    wire [8:0] probe_desc_rsp_count;
    wire [7:0] probe_desc_rsp_tag;
    wire probe_desc_rsp_error;
    reg probe_state_req_valid;
    wire probe_state_req_ready;
    reg [4:0] probe_state_req_id;
    reg [4:0] probe_state_req_tile;
    reg [7:0] probe_state_req_tag;
    wire probe_state_rsp_valid;
    reg probe_state_rsp_ready;
    wire probe_state_rsp_error;
    reg probe_state_write_valid;
    wire probe_state_write_ready;
    reg signed [7:0] probe_state_write_value;
    reg [8:0] probe_state_write_index;
    reg [15:0] probe_state_write_tag;
    reg probe_state_write_last;
    reg probe_active_valid;
    wire probe_active_ready;
    reg probe_active_write;
    reg [8:0] probe_active_index;
    reg [15:0] probe_active_tag;
    reg probe_active_finalize;
    reg probe_commit_valid;
    wire probe_commit_ready;
    reg [4:0] probe_commit_id;
    reg probe_commit_barrier;
    wire probe_commit_done;
    wire probe_producer_busy;
    wire [8:0] probe_producer_list_count;
    wire probe_error_valid;
    wire [7:0] probe_error_code;
    wire probe_reset_required;

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

    sparse_memory_v4_table_v1 reference_table (
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

    sequential_v4_sparse_memory_subsystem #(
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
        .sparse_load_enable(sparse_load_enable),
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
        .reset_required(reset_required), .quiescent(quiescent),
        .active_stage_id(active_stage_id),
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
        .context_port_owner(context_port_owner),
        .planner_error_valid(planner_error_valid),
        .planner_error_code(planner_error_code),
        .planner_error_detail(planner_error_detail),
        .stage_diag_valid(stage_diag_valid),
        .stage_diag_success(stage_diag_success),
        .stage_diag_stage_id(stage_diag_stage_id),
        .stage_diag_sparse_enable(stage_diag_sparse_enable),
        .stage_diag_fallback_full(stage_diag_fallback_full),
        .stage_dense_reference_bytes(stage_dense_reference_bytes),
        .stage_planned_bytes(stage_planned_bytes),
        .stage_actual_bytes(stage_actual_bytes),
        .stage_saved_bytes(stage_saved_bytes),
        .stage_union_count0(stage_union_count0),
        .stage_union_count1(stage_union_count1),
        .stage_copy_command_count(stage_copy_command_count),
        .stage_ar_burst_count(stage_ar_burst_count),
        .stage_load_cycles(stage_load_cycles),
        .epoch_lut_actual_bytes(epoch_lut_actual_bytes),
        .integration_error_valid(integration_error_valid),
        .integration_error_code(integration_error_code),
        .integration_error_detail(integration_error_detail)
    );

    sparse_recurrent_context_store_v1 u_present_adapter_probe (
        .clk(clk),
        .rst_n(rst_n),
        .clear_state(probe_clear_state),
        .producer_open_valid(probe_open_valid),
        .producer_open_ready(probe_open_ready),
        .producer_open_logical_id(probe_open_id),
        .producer_open_row_tiles(probe_open_rows),
        .list_desc_req_valid(probe_desc_req_valid),
        .list_desc_req_ready(probe_desc_req_ready),
        .list_desc_req_logical_id(probe_desc_req_id),
        .list_desc_req_tag(probe_desc_req_tag),
        .list_desc_rsp_valid(probe_desc_rsp_valid),
        .list_desc_rsp_ready(probe_desc_rsp_ready),
        .list_desc_rsp_present(probe_desc_rsp_present),
        .list_desc_rsp_count(probe_desc_rsp_count),
        .list_desc_rsp_tag(probe_desc_rsp_tag),
        .list_desc_rsp_error(probe_desc_rsp_error),
        .list_read_req_valid(1'b0),
        .list_read_req_ready(),
        .list_read_req_logical_id(5'd0),
        .list_read_req_ordinal(9'd0),
        .list_read_req_tag(8'd0),
        .list_read_rsp_valid(),
        .list_read_rsp_ready(1'b1),
        .list_read_rsp_index(),
        .list_read_rsp_tag(),
        .list_read_rsp_error(),
        .state_read_req_valid(probe_state_req_valid),
        .state_read_req_ready(probe_state_req_ready),
        .state_read_req_logical_id(probe_state_req_id),
        .state_read_req_row_tile(probe_state_req_tile),
        .state_read_req_tag(probe_state_req_tag),
        .state_read_rsp_valid(probe_state_rsp_valid),
        .state_read_rsp_ready(probe_state_rsp_ready),
        .state_read_rsp_data(),
        .state_read_rsp_tag(),
        .state_read_rsp_error(probe_state_rsp_error),
        .state_write_valid(probe_state_write_valid),
        .state_write_ready(probe_state_write_ready),
        .state_write_value(probe_state_write_value),
        .state_write_index(probe_state_write_index),
        .state_write_tag(probe_state_write_tag),
        .state_write_last(probe_state_write_last),
        .active_cmd_valid(probe_active_valid),
        .active_cmd_ready(probe_active_ready),
        .active_cmd_write(probe_active_write),
        .active_cmd_index(probe_active_index),
        .active_cmd_tag(probe_active_tag),
        .active_cmd_finalize(probe_active_finalize),
        .commit_valid(probe_commit_valid),
        .commit_ready(probe_commit_ready),
        .commit_logical_id(probe_commit_id),
        .pe_barrier_idle(probe_commit_barrier),
        .commit_done(probe_commit_done),
        .producer_busy(probe_producer_busy),
        .producer_logical_id(),
        .producer_row_tiles(),
        .producer_list_count(probe_producer_list_count),
        .error_valid(probe_error_valid),
        .error_code(probe_error_code),
        .error_detail(),
        .reset_required(probe_reset_required)
    );

    reg [7:0] dram [0:IMAGE_BYTES-1];
    reg dram_active;
    reg [31:0] dram_read_addr;
    reg [8:0] dram_beats_left;
    reg force_axi_stall;
    reg inject_axi_error;
    integer axi_command_bytes;
    integer axi_accepted_r_bytes;
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
    integer mode_stage_bytes;
    integer dense_two_frame_stage_bytes;
    integer sparse_two_frame_stage_bytes;
    integer planner_desc_capture_count;
    integer planner_desc_store_count;
    integer planner_read_capture_count;
    integer planner_read_store_count;
    reg planner_desc_outstanding;
    reg planner_read_outstanding;
    reg [7:0] planner_desc_expected_tag;
    reg [7:0] planner_read_expected_tag;
    reg selected_sparse_mode;
    reg compare_against_dense;
    reg oracle_stage_plan_seen;
    reg [3:0] oracle_stage_id;
    reg oracle_stage_fallback;
    reg [8:0] oracle_stage_union_count0;
    reg [8:0] oracle_stage_union_count1;
    reg [31:0] oracle_stage_expected_bytes;

    // Dense mode records every functional boundary transaction.  After a
    // coordinated reset, sparse mode compares the second two-frame run
    // transaction-by-transaction against these exact payloads.
    reg [25:0] dense_feature_stream [0:32767];
    reg [33:0] dense_coefficient_stream [0:4095];
    reg [33:0] dense_state_stream [0:32767];
    reg [26:0] dense_active_stream [0:16383];
    reg [136:0] dense_weight_rsp_stream [0:262143];
    reg [5814:0] dense_param_rsp_stream [0:4095];
    integer feature_stream_index;
    integer coefficient_stream_index;
    integer state_stream_index;
    integer active_stream_index;
    integer weight_rsp_stream_index;
    integer param_rsp_stream_index;
    integer dense_feature_stream_count;
    integer dense_coefficient_stream_count;
    integer dense_state_stream_count;
    integer dense_active_stream_count;
    integer dense_weight_rsp_stream_count;
    integer dense_param_rsp_stream_count;
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

    // Independent connected traffic oracle.  It uses only the frozen table
    // geometry and the planner's completed union populations; it does not use
    // any byte/count output from sparse_memory_service_v1.
    function [31:0] connected_oracle_bytes;
        input [3:0] oracle_stage;
        input oracle_fallback;
        input [31:0] dense_transfer;
        input [1:0] matrix_count;
        input [9:0] matrix0_sources;
        input [5:0] matrix0_rows;
        input [9:0] matrix1_sources;
        input [5:0] matrix1_rows;
        input [8:0] union_count0;
        input [8:0] union_count1;
        input [7:0] parameter_record_words;
        input [5:0] parameter_tiles;
        reg [31:0] oracle_bytes;
        begin
            if (oracle_fallback) begin
                connected_oracle_bytes = dense_transfer;
            end else begin
                oracle_bytes = parameter_record_words * parameter_tiles * 8;
                if ((oracle_stage == 4'd0) ||
                    (oracle_stage == 4'd3) ||
                    (oracle_stage == 4'd6) ||
                    (oracle_stage == 4'd9))
                    oracle_bytes = oracle_bytes +
                        matrix0_sources * matrix0_rows * 16;
                else
                    oracle_bytes = oracle_bytes +
                        union_count0 * matrix0_rows * 16;
                if (matrix_count == 2)
                    oracle_bytes = oracle_bytes +
                        union_count1 * matrix1_rows * 16;
                connected_oracle_bytes = oracle_bytes;
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
            axi_accepted_r_bytes <= 0;
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
                axi_accepted_r_bytes <= axi_accepted_r_bytes + 8;
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
            feature_stream_index <= 0;
            coefficient_stream_index <= 0;
            state_stream_index <= 0;
            active_stream_index <= 0;
            weight_rsp_stream_index <= 0;
            param_rsp_stream_index <= 0;
            oracle_stage_plan_seen <= 1'b0;
            oracle_stage_id <= 4'd0;
            oracle_stage_fallback <= 1'b0;
            oracle_stage_union_count0 <= 9'd0;
            oracle_stage_union_count1 <= 9'd0;
            oracle_stage_expected_bytes <= 32'd0;
            planner_desc_capture_count <= 0;
            planner_desc_store_count <= 0;
            planner_read_capture_count <= 0;
            planner_read_store_count <= 0;
            planner_desc_outstanding <= 1'b0;
            planner_read_outstanding <= 1'b0;
            planner_desc_expected_tag <= 8'd0;
            planner_read_expected_tag <= 8'd0;
        end else begin
            cycle_count <= cycle_count + 1;
            if (stage_req_valid && stage_req_ready) begin
                oracle_stage_plan_seen <= 1'b0;
                planner_desc_capture_count <= 0;
                planner_desc_store_count <= 0;
                planner_read_capture_count <= 0;
                planner_read_store_count <= 0;
                planner_desc_outstanding <= 1'b0;
                planner_read_outstanding <= 1'b0;
            end
            if (dut.planner_list_desc_req_valid &&
                dut.planner_list_desc_req_ready)
                planner_desc_capture_count <=
                    planner_desc_capture_count + 1;
            if ((dut.context_owner_q == 2'd1) &&
                dut.store_list_desc_req_valid &&
                dut.store_list_desc_req_ready) begin
                check(!planner_desc_outstanding,
                      "planner descriptor request reordered/overlapped");
                planner_desc_store_count <= planner_desc_store_count + 1;
                planner_desc_outstanding <= 1'b1;
                planner_desc_expected_tag <= dut.store_list_desc_req_tag;
            end
            if (dut.planner_list_desc_rsp_valid &&
                dut.planner_list_desc_rsp_ready) begin
                check(planner_desc_outstanding &&
                      (dut.planner_list_desc_rsp_tag ==
                       planner_desc_expected_tag),
                      "planner descriptor response ordering mismatch");
                planner_desc_outstanding <= 1'b0;
            end
            if (dut.planner_list_read_req_valid &&
                dut.planner_list_read_req_ready)
                planner_read_capture_count <=
                    planner_read_capture_count + 1;
            if (dut.store_list_read_req_valid &&
                dut.store_list_read_req_ready) begin
                check((dut.list_read_dispatch_owner_q == 2'd1) ||
                      (dut.list_read_dispatch_owner_q == 2'd2),
                      "list-read dispatch lost request provenance");
                check((dut.list_read_dispatch_owner_q ==
                       dut.context_owner_q) || reset_required,
                      "list-read dispatch owner changed before retirement");
            end
            if ((dut.list_read_dispatch_owner_q == 2'd1) &&
                dut.store_list_read_req_valid &&
                dut.store_list_read_req_ready) begin
                check(!planner_read_outstanding,
                      "planner list request reordered/overlapped");
                planner_read_store_count <= planner_read_store_count + 1;
                planner_read_outstanding <= 1'b1;
                planner_read_expected_tag <= dut.store_list_read_req_tag;
            end
            if ((dut.planner_list_read_req_valid &&
                 dut.planner_list_read_req_ready) ||
                (dut.context_list_read_req_valid &&
                 dut.context_list_read_req_ready)) begin
                check(!((dut.planner_list_read_req_valid &&
                         dut.planner_list_read_req_ready) &&
                        (dut.context_list_read_req_valid &&
                         dut.context_list_read_req_ready)),
                      "planner and controller captured list reads together");
                if (!dut.list_read_dispatch_valid_q)
                    check(!dut.store_list_read_req_valid,
                          "list-read dispatch became fallthrough");
            end
            if (dut.planner_list_read_rsp_valid &&
                dut.planner_list_read_rsp_ready) begin
                check(planner_read_outstanding &&
                      (dut.planner_list_read_rsp_tag ==
                       planner_read_expected_tag),
                      "planner list response ordering mismatch");
                planner_read_outstanding <= 1'b0;
            end
            if ((planner_desc_capture_count < planner_desc_store_count) ||
                ((planner_desc_capture_count - planner_desc_store_count) > 1))
                fail("planner descriptor capture/delivery distance exceeded one");
            if ((planner_read_capture_count < planner_read_store_count) ||
                ((planner_read_capture_count - planner_read_store_count) > 1))
                fail("planner list capture/delivery distance exceeded one");
            if (dut.planner_plan_fire) begin
                check((planner_desc_capture_count ==
                       planner_desc_store_count) &&
                      (planner_read_capture_count ==
                       planner_read_store_count) &&
                      !planner_desc_outstanding &&
                      !planner_read_outstanding &&
                      !dut.planner_desc_req_buf_valid_q &&
                      !dut.list_read_dispatch_valid_q,
                      "planner published with buffered request outstanding");
                check(ref_valid &&
                      (dut.planner_plan_stage_id == reference_stage_id),
                      "traffic oracle table/planner stage mismatch");
                oracle_stage_plan_seen <= 1'b1;
                oracle_stage_id <= dut.planner_plan_stage_id;
                oracle_stage_fallback <= dut.planner_plan_fallback_full;
                oracle_stage_union_count0 <= dut.planner_plan_count0;
                oracle_stage_union_count1 <= dut.planner_plan_count1;
                oracle_stage_expected_bytes <= connected_oracle_bytes(
                    dut.planner_plan_stage_id,
                    dut.planner_plan_fallback_full,
                    ref_transfer_bytes,
                    ref_matrix_count,
                    ref_matrix0_sources,
                    ref_matrix0_row_tiles,
                    ref_matrix1_sources,
                    ref_matrix1_row_tiles,
                    dut.planner_plan_count0,
                    dut.planner_plan_count1,
                    ref_param_record_words,
                    ref_param_tiles);
            end
            if (stage_load_done) begin
                check(oracle_stage_plan_seen &&
                      (stage_diag_stage_id == oracle_stage_id) &&
                      (stage_diag_fallback_full == oracle_stage_fallback) &&
                      (stage_union_count0 == oracle_stage_union_count0) &&
                      (stage_union_count1 == oracle_stage_union_count1) &&
                      (stage_planned_bytes == oracle_stage_expected_bytes) &&
                      (stage_actual_bytes == oracle_stage_expected_bytes),
                      "accepted stage bytes disagree with independent oracle");
                check(dut.service_lut_ready &&
                      (lut_adapter_state == 3'd4),
                      "stage success preceded LUT READY qualification");
            end
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
            if (feature_req_valid && feature_req_ready) begin
                check(feature_stream_index < 32768,
                      "feature differential stream overflow");
                if (compare_against_dense) begin
                    check(feature_stream_index < dense_feature_stream_count,
                          "sparse feature stream longer than dense");
                    if (feature_stream_index < dense_feature_stream_count)
                        check({feature_req_stage_id, feature_req_branch,
                               feature_req_context, feature_req_source,
                               feature_req_tag} ===
                              dense_feature_stream[feature_stream_index],
                              "dense/sparse feature request mismatch");
                end else begin
                    dense_feature_stream[feature_stream_index] <=
                        {feature_req_stage_id, feature_req_branch,
                         feature_req_context, feature_req_source,
                         feature_req_tag};
                end
                feature_stream_index <= feature_stream_index + 1;
            end
            if (coefficient_valid && coefficient_ready) begin
                check(coefficient_stream_index < 4096,
                      "coefficient differential stream overflow");
                if (compare_against_dense) begin
                    check(coefficient_stream_index <
                          dense_coefficient_stream_count,
                          "sparse coefficient stream longer than dense");
                    if (coefficient_stream_index <
                        dense_coefficient_stream_count)
                        check({coefficient_value, coefficient_index,
                               coefficient_tag, coefficient_last} ===
                              dense_coefficient_stream[
                                  coefficient_stream_index],
                              "dense/sparse coefficient mismatch");
                end else begin
                    dense_coefficient_stream[coefficient_stream_index] <=
                        {coefficient_value, coefficient_index,
                         coefficient_tag, coefficient_last};
                end
                coefficient_stream_index <= coefficient_stream_index + 1;
            end
            if (dut.pe_state_write_valid && dut.pe_state_write_ready) begin
                state_write_count <= state_write_count + 1;
                check(state_stream_index < 32768,
                      "state differential stream overflow");
                if (compare_against_dense) begin
                    check(state_stream_index < dense_state_stream_count,
                          "sparse state stream longer than dense");
                    if (state_stream_index < dense_state_stream_count)
                        check({dut.pe_state_write_value,
                               dut.pe_state_write_index,
                               dut.pe_state_write_tag,
                               dut.pe_state_write_last} ===
                              dense_state_stream[state_stream_index],
                              "dense/sparse recurrent state mismatch");
                end else begin
                    dense_state_stream[state_stream_index] <=
                        {dut.pe_state_write_value, dut.pe_state_write_index,
                         dut.pe_state_write_tag, dut.pe_state_write_last};
                end
                state_stream_index <= state_stream_index + 1;
            end
            if (dut.pe_active_cmd_valid && dut.pe_active_cmd_ready) begin
                if (dut.pe_active_cmd_finalize)
                    active_finalize_count <= active_finalize_count + 1;
                check(active_stream_index < 16384,
                      "active-list differential stream overflow");
                if (compare_against_dense) begin
                    check(active_stream_index < dense_active_stream_count,
                          "sparse active stream longer than dense");
                    if (active_stream_index < dense_active_stream_count)
                        check({dut.pe_active_cmd_write,
                               dut.pe_active_cmd_index,
                               dut.pe_active_cmd_tag,
                               dut.pe_active_cmd_finalize} ===
                              dense_active_stream[active_stream_index],
                              "dense/sparse active-list command mismatch");
                end else begin
                    dense_active_stream[active_stream_index] <=
                        {dut.pe_active_cmd_write, dut.pe_active_cmd_index,
                         dut.pe_active_cmd_tag,
                         dut.pe_active_cmd_finalize};
                end
                active_stream_index <= active_stream_index + 1;
            end
            if (dut.controller_weight_rsp_valid &&
                dut.controller_weight_rsp_ready) begin
                check(weight_rsp_stream_index < 262144,
                      "weight differential stream overflow");
                if (compare_against_dense) begin
                    check(weight_rsp_stream_index <
                          dense_weight_rsp_stream_count,
                          "sparse weight response stream longer than dense");
                    if (weight_rsp_stream_index <
                        dense_weight_rsp_stream_count)
                        check({dut.controller_weight_rsp_data,
                               dut.controller_weight_rsp_tag,
                               dut.controller_weight_rsp_error} ===
                              dense_weight_rsp_stream[
                                  weight_rsp_stream_index],
                              "dense/sparse weight response mismatch");
                end else begin
                    dense_weight_rsp_stream[weight_rsp_stream_index] <=
                        {dut.controller_weight_rsp_data,
                         dut.controller_weight_rsp_tag,
                         dut.controller_weight_rsp_error};
                end
                weight_rsp_stream_index <= weight_rsp_stream_index + 1;
            end
            if (dut.controller_param_rsp_valid &&
                dut.controller_param_rsp_ready) begin
                check(param_rsp_stream_index < 4096,
                      "parameter differential stream overflow");
                if (compare_against_dense) begin
                    check(param_rsp_stream_index < dense_param_rsp_stream_count,
                          "sparse parameter stream longer than dense");
                    if (param_rsp_stream_index < dense_param_rsp_stream_count)
                        check({dut.controller_param_rsp_data,
                               dut.controller_param_rsp_kind,
                               dut.controller_param_rsp_bits,
                               dut.controller_param_rsp_tag,
                               dut.controller_param_rsp_error} ===
                              dense_param_rsp_stream[param_rsp_stream_index],
                              "dense/sparse parameter response mismatch");
                end else begin
                    dense_param_rsp_stream[param_rsp_stream_index] <=
                        {dut.controller_param_rsp_data,
                         dut.controller_param_rsp_kind,
                         dut.controller_param_rsp_bits,
                         dut.controller_param_rsp_tag,
                         dut.controller_param_rsp_error};
                end
                param_rsp_stream_index <= param_rsp_stream_index + 1;
            end
            if (dut.context_commit_done)
                commit_done_count <= commit_done_count + 1;
            check((compute_owner == 4'b0000) ||
                  (compute_owner == 4'b0001) ||
                  (compute_owner == 4'b0010) ||
                  (compute_owner == 4'b0100),
                  "unsupported or overlapping PE owner");
            check(!((dut.planner_plan_req_valid &&
                     dut.planner_plan_req_ready) &&
                    (dut.context_producer_open_valid &&
                     dut.context_producer_open_ready)),
                  "planner and context producer handshook in one cycle");
        end
    end

    task check_probe_descriptor;
        input expected_present;
        input [8:0] expected_count;
        input [7:0] request_tag;
        input integer backpressure_cycles;
        integer probe_timeout;
        integer hold_cycle;
        begin
            @(negedge clk);
            probe_desc_req_id = 5'd5;
            probe_desc_req_tag = request_tag;
            probe_desc_req_valid = 1'b1;
            probe_timeout = 0;
            while (!probe_desc_req_ready && probe_timeout < 20) begin
                @(negedge clk);
                probe_timeout = probe_timeout + 1;
            end
            check(probe_timeout < 20,
                  "present probe descriptor request not accepted");
            @(posedge clk);
            #1;
            @(negedge clk);
            probe_desc_req_valid = 1'b0;
            probe_timeout = 0;
            while (!probe_desc_rsp_valid && probe_timeout < 20) begin
                @(posedge clk);
                #1;
                probe_timeout = probe_timeout + 1;
            end
            check(probe_timeout < 20,
                  "present probe descriptor response timed out");
            check((probe_desc_rsp_present == expected_present) &&
                  (probe_desc_rsp_count == expected_count) &&
                  (probe_desc_rsp_tag == request_tag) &&
                  !probe_desc_rsp_error,
                  "present probe descriptor payload mismatch");
            for (hold_cycle = 0; hold_cycle < backpressure_cycles;
                 hold_cycle = hold_cycle + 1) begin
                @(posedge clk);
                #1;
                check(probe_desc_rsp_valid &&
                      (probe_desc_rsp_present == expected_present) &&
                      (probe_desc_rsp_count == expected_count) &&
                      (probe_desc_rsp_tag == request_tag) &&
                      !probe_desc_rsp_error,
                      "present probe response changed under backpressure");
            end
            @(negedge clk);
            probe_desc_rsp_ready = 1'b1;
            @(posedge clk);
            #1;
            check(!probe_desc_rsp_valid,
                  "present probe response did not retire on handshake");
            @(negedge clk);
            probe_desc_rsp_ready = 1'b0;
        end
    endtask

    task test_present_adapter;
        integer probe_index;
        integer probe_timeout;
        integer hold_cycle;
        begin
            // Reset creates an absent descriptor with an empty payload.
            check_probe_descriptor(1'b0, 9'd0, 8'ha1, 2);

            // Open logical context five with one state tile.  Consume the old
            // (reset-invalid) tile, write all 16 dense state bytes, and
            // finalize without any active index writes: a present empty list.
            @(negedge clk);
            probe_open_id = 5'd5;
            probe_open_rows = 6'd1;
            probe_open_valid = 1'b1;
            probe_timeout = 0;
            while (!probe_open_ready && probe_timeout < 20) begin
                @(negedge clk);
                probe_timeout = probe_timeout + 1;
            end
            check(probe_timeout < 20,
                  "present probe producer open not accepted");
            @(posedge clk);
            @(negedge clk);
            probe_open_valid = 1'b0;

            probe_state_req_id = 5'd5;
            probe_state_req_tile = 5'd0;
            probe_state_req_tag = 8'hb1;
            probe_state_req_valid = 1'b1;
            probe_timeout = 0;
            while (!probe_state_req_ready && probe_timeout < 20) begin
                @(negedge clk);
                probe_timeout = probe_timeout + 1;
            end
            check(probe_timeout < 20,
                  "present probe old-state read not accepted");
            @(posedge clk);
            #1;
            @(negedge clk);
            probe_state_req_valid = 1'b0;
            probe_timeout = 0;
            while (!probe_state_rsp_valid && probe_timeout < 20) begin
                @(posedge clk);
                #1;
                probe_timeout = probe_timeout + 1;
            end
            check(probe_timeout < 20 && !probe_state_rsp_error,
                  "present probe old-state response failed");
            @(posedge clk);
            #1;
            check(!probe_state_rsp_valid,
                  "present probe old-state response did not retire");

            for (probe_index = 0; probe_index < 16;
                 probe_index = probe_index + 1) begin
                @(negedge clk);
                probe_state_write_value = probe_index[7:0];
                probe_state_write_index = probe_index[8:0];
                probe_state_write_tag =
                    {2'b00, 5'd5, probe_index[8:0]};
                probe_state_write_last = (probe_index == 15);
                probe_state_write_valid = 1'b1;
                probe_timeout = 0;
                while (!probe_state_write_ready && probe_timeout < 20) begin
                    @(negedge clk);
                    probe_timeout = probe_timeout + 1;
                end
                check(probe_timeout < 20,
                      "present probe state write not accepted");
                @(posedge clk);
                @(negedge clk);
                probe_state_write_valid = 1'b0;
            end

            probe_active_write = 1'b0;
            probe_active_index = 9'd15;
            probe_active_tag = {2'b00, 5'd5, 9'd15};
            probe_active_finalize = 1'b1;
            probe_active_valid = 1'b1;
            probe_timeout = 0;
            while (!probe_active_ready && probe_timeout < 20) begin
                @(negedge clk);
                probe_timeout = probe_timeout + 1;
            end
            check(probe_timeout < 20,
                  "present probe empty list finalize not accepted");
            @(posedge clk);
            @(negedge clk);
            probe_active_valid = 1'b0;

            probe_commit_id = 5'd5;
            probe_commit_barrier = 1'b1;
            probe_commit_valid = 1'b1;
            probe_timeout = 0;
            while (!probe_commit_ready && probe_timeout < 20) begin
                @(negedge clk);
                probe_timeout = probe_timeout + 1;
            end
            check(probe_timeout < 20,
                  "present probe empty commit not accepted");
            @(posedge clk);
            #1;
            check(probe_commit_done && !probe_producer_busy &&
                  (probe_producer_list_count == 0),
                  "present probe empty commit did not publish atomically");

            // Assert the descriptor in the immediately following cycle while
            // commit_done is still visible.  The adapter's bypass must make
            // present=1, and the response must remain stable while stalled.
            @(negedge clk);
            probe_commit_valid = 1'b0;
            probe_desc_req_id = 5'd5;
            probe_desc_req_tag = 8'hc1;
            probe_desc_req_valid = 1'b1;
            check(probe_desc_req_ready,
                  "immediate post-commit descriptor was not ready");
            @(posedge clk);
            #1;
            @(negedge clk);
            probe_desc_req_valid = 1'b0;
            check(probe_desc_rsp_valid && probe_desc_rsp_present &&
                  (probe_desc_rsp_count == 0) &&
                  (probe_desc_rsp_tag == 8'hc1) &&
                  !probe_desc_rsp_error,
                  "immediate post-commit empty descriptor was not present");
            for (hold_cycle = 0; hold_cycle < 3;
                 hold_cycle = hold_cycle + 1) begin
                @(posedge clk);
                #1;
                check(probe_desc_rsp_valid && probe_desc_rsp_present &&
                      (probe_desc_rsp_count == 0) &&
                      (probe_desc_rsp_tag == 8'hc1) &&
                      !probe_desc_rsp_error,
                      "post-commit descriptor changed under backpressure");
            end
            @(negedge clk);
            probe_desc_rsp_ready = 1'b1;
            @(posedge clk);
            #1;
            check(!probe_desc_rsp_valid,
                  "post-commit descriptor did not retire");
            @(negedge clk);
            probe_desc_rsp_ready = 1'b0;

            // A legal idle clear removes presence without depending on a RAM
            // scrub.  The next descriptor remains count zero but is absent.
            probe_clear_state = 1'b1;
            @(posedge clk);
            @(negedge clk);
            probe_clear_state = 1'b0;
            check_probe_descriptor(1'b0, 9'd0, 8'hd1, 1);
            check(!probe_error_valid && !probe_reset_required &&
                  (probe_error_code == 0),
                  "present adapter probe entered fatal state");
        end
    endtask

    task reset_dut;
        begin
            rst_n = 1'b0;
            abort = 1'b0;
            clear_error = 1'b0;
            clear_state = 1'b0;
            stage_req_valid = 1'b0;
            stage_id = 4'd0;
            stage_bank = 2'd0;
            reference_stage_id = 4'd0;
            sparse_load_enable = selected_sparse_mode;
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
            probe_clear_state = 1'b0;
            probe_open_valid = 1'b0;
            probe_open_id = 5'd0;
            probe_open_rows = 6'd0;
            probe_desc_req_valid = 1'b0;
            probe_desc_req_id = 5'd0;
            probe_desc_req_tag = 8'd0;
            probe_desc_rsp_ready = 1'b0;
            probe_state_req_valid = 1'b0;
            probe_state_req_id = 5'd0;
            probe_state_req_tile = 5'd0;
            probe_state_req_tag = 8'd0;
            probe_state_rsp_ready = 1'b1;
            probe_state_write_valid = 1'b0;
            probe_state_write_value = 8'sd0;
            probe_state_write_index = 9'd0;
            probe_state_write_tag = 16'd0;
            probe_state_write_last = 1'b0;
            probe_active_valid = 1'b0;
            probe_active_write = 1'b0;
            probe_active_index = 9'd0;
            probe_active_tag = 16'd0;
            probe_active_finalize = 1'b0;
            probe_commit_valid = 1'b0;
            probe_commit_id = 5'd0;
            probe_commit_barrier = 1'b0;
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
                  (lut_adapter_state == 0) && quiescent,
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
            bytes_before = axi_accepted_r_bytes;
            expected_bytes = first_load_in_epoch ? 2040 : 0;
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
            check(stage_load_done && !stage_load_error && !reset_required &&
                  !quiescent,
                  "legal stage load failed");
            check((active_stage_id == requested_stage) &&
                  (cache_state == 6),
                  "loaded stage identity/cache state mismatch");
            check(stage_diag_valid && stage_diag_success &&
                  (stage_diag_stage_id == requested_stage) &&
                  (stage_diag_sparse_enable == selected_sparse_mode),
                  "atomic stage diagnostic identity/mode mismatch");
            check((stage_dense_reference_bytes == ref_transfer_bytes) &&
                  (stage_actual_bytes == stage_planned_bytes) &&
                  (stage_saved_bytes ==
                   (ref_transfer_bytes - stage_actual_bytes)),
                  "stage traffic diagnostic arithmetic mismatch");
            check((axi_accepted_r_bytes - bytes_before) ==
                  (expected_bytes + stage_actual_bytes),
                  "accepted AXI bytes disagree with stage diagnostics");
            check(oracle_stage_plan_seen &&
                  (oracle_stage_id == requested_stage) &&
                  (stage_planned_bytes == oracle_stage_expected_bytes) &&
                  (stage_actual_bytes == oracle_stage_expected_bytes),
                  "stage bytes disagree with frozen-geometry oracle");
            if (!selected_sparse_mode) begin
                check(stage_diag_fallback_full &&
                      (stage_actual_bytes == ref_transfer_bytes) &&
                      (stage_saved_bytes == 0),
                      "disabled sparse mode did not reproduce dense load");
            end else begin
                check(stage_actual_bytes <= ref_transfer_bytes,
                      "sparse stage exceeded dense reference bytes");
            end
            check((stage_copy_command_count != 0) &&
                  (stage_ar_burst_count != 0) &&
                  (stage_load_cycles != 0),
                  "stage traffic command/cycle diagnostic missing");
            mode_stage_bytes = mode_stage_bytes + stage_actual_bytes;
            if (first_load_in_epoch) begin
                check((epoch_lut_observed == 2040) &&
                      (lut_accepted_bytes == 2040) &&
                      (epoch_lut_actual_bytes == 2040) &&
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
            check(context_port_owner ==
                  (final_context ? 2'd0 : 2'd2),
                  "planner/controller context-port ownership mismatch");
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

    task check_pre_service_failure_snapshot;
        integer snapshot_timeout;
        begin
            snapshot_timeout = 0;
            while (!stage_diag_valid && snapshot_timeout < 20) begin
                @(posedge clk);
                #1;
                snapshot_timeout = snapshot_timeout + 1;
            end
            check((snapshot_timeout < 20) && stage_load_error &&
                  !stage_load_done && !stage_diag_success,
                  "pre-service failure snapshot did not terminate");
            check(!stage_diag_fallback_full &&
                  (stage_dense_reference_bytes == 0) &&
                  (stage_planned_bytes == 0) &&
                  (stage_actual_bytes == 0) &&
                  (stage_saved_bytes == 0) &&
                  (stage_union_count0 == 0) &&
                  (stage_union_count1 == 0) &&
                  (stage_copy_command_count == 0) &&
                  (stage_ar_burst_count == 0) &&
                  (stage_load_cycles != 0),
                  "pre-service failure exposed stale service diagnostics");
        end
    endtask

    integer image_file;
    integer bytes_read;
    integer timeout;
    integer ar_before;
    reg [4:0] held_planner_desc_id;
    reg [7:0] held_planner_desc_tag;
    reg [4:0] held_planner_read_id;
    reg [8:0] held_planner_read_ordinal;
    reg [7:0] held_planner_read_tag;
    reg [1:0] held_planner_read_owner;
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
        selected_sparse_mode = 1'b0;
        compare_against_dense = 1'b0;
        mode_stage_bytes = 0;
        dense_two_frame_stage_bytes = 0;
        sparse_two_frame_stage_bytes = 0;
        dense_feature_stream_count = 0;
        dense_coefficient_stream_count = 0;
        dense_state_stream_count = 0;
        dense_active_stream_count = 0;
        dense_weight_rsp_stream_count = 0;
        dense_param_rsp_stream_count = 0;
        total_sparse_requests = 0;
        completed_jobs = 0;
        completed_stage_loads = 0;

        // First record a complete dense-load baseline for two frames.
        reset_dut();
        test_present_adapter();
        @(negedge clk);
        clear_state = 1'b1;
        #1;
        check(dut.global_clear_safe && !dut.context_clear_state &&
              !dut.clear_pending_q,
              "idle wrapper clear request was not safely admitted");
        @(posedge clk);
        #1;
        check(dut.clear_pending_q && !dut.context_clear_state &&
              !stage_req_ready && !fb_start_ready && !sb_start_ready,
              "clear request was not fenced while pending");
        @(negedge clk);
        clear_state = 1'b0;
        stage_req_valid = 1'b1;
        force dut.context_producer_open_valid = 1'b1;
        #1;
        check(!stage_req_ready && !dut.store_producer_open_valid &&
              !dut.context_producer_open_ready,
              "pending clear admitted stage or context mutation");
        @(posedge clk);
        #1;
        check(!dut.clear_pending_q && dut.context_clear_state &&
              !stage_req_ready && !dut.store_producer_open_valid,
              "safe clear did not produce one registered fenced pulse");
        @(negedge clk);
        stage_req_valid = 1'b0;
        release dut.context_producer_open_valid;
        @(posedge clk);
        #1;
        check(!dut.context_clear_state,
              "registered context clear pulse lasted more than one cycle");
        check(!reset_required && (context_port_owner == 0),
              "legal idle wrapper clear became fatal");
        // Force the first real planner list-read request through a held
        // non-fallthrough slice.  The connected frame continues only after
        // every buffered field has remained stable for three stalled cycles.
        fork
            begin : planner_read_buffer_backpressure
                integer read_wait_cycles;
                read_wait_cycles = 0;
                while ((dut.u_sparse_union_planner.state_q != 4'd4) &&
                       (read_wait_cycles < 2000000)) begin
                    @(negedge clk);
                    read_wait_cycles = read_wait_cycles + 1;
                end
                check(read_wait_cycles < 2000000,
                      "planner never issued a list-read request");
                if (read_wait_cycles < 2000000) begin
                    force dut.store_list_read_req_ready = 1'b0;
                    read_wait_cycles = 0;
                    while (!dut.list_read_dispatch_valid_q &&
                           (read_wait_cycles < 100)) begin
                        @(posedge clk);
                        #1;
                        read_wait_cycles = read_wait_cycles + 1;
                    end
                    check(read_wait_cycles < 100,
                          "planner list request did not enter elastic buffer");
                    held_planner_read_id = dut.store_list_read_req_id;
                    held_planner_read_ordinal =
                        dut.store_list_read_req_ordinal;
                    held_planner_read_tag = dut.store_list_read_req_tag;
                    held_planner_read_owner =
                        dut.list_read_dispatch_owner_q;
                    repeat (3) begin
                        @(posedge clk);
                        #1;
                        check(dut.store_list_read_req_valid &&
                              !dut.store_list_read_req_ready &&
                              (dut.list_read_dispatch_owner_q ==
                               held_planner_read_owner) &&
                              (held_planner_read_owner == 2'd1) &&
                              (dut.store_list_read_req_id ==
                               held_planner_read_id) &&
                              (dut.store_list_read_req_ordinal ==
                               held_planner_read_ordinal) &&
                              (dut.store_list_read_req_tag ==
                               held_planner_read_tag),
                              "planner list buffer changed under backpressure");
                    end
                    @(negedge clk);
                    release dut.store_list_read_req_ready;
                end
            end
            begin
                run_frame(0);
            end
        join
        run_frame(1);
        check(completed_stage_loads == 24,
              "two-frame run did not load all twelve stages twice");
        check(completed_jobs == 60,
              "two-frame run did not execute all 20 logical jobs per layer");
        check(total_sparse_requests > 0,
              "later produced active lists never drove sparse cache reads");
        check((epoch_lut_observed == 2040) &&
              (lut_configuration_starts == 1),
              "dense two-frame run configured LUT more than once");
        check(mode_stage_bytes == 2 * 1050544,
              "dense two-frame stage bytes mismatch");
        dense_two_frame_stage_bytes = mode_stage_bytes;
        dense_feature_stream_count = feature_stream_index;
        dense_coefficient_stream_count = coefficient_stream_index;
        dense_state_stream_count = state_stream_index;
        dense_active_stream_count = active_stream_index;
        dense_weight_rsp_stream_count = weight_rsp_stream_index;
        dense_param_rsp_stream_count = param_rsp_stream_index;

        // A coordinated reset starts the sparse A/B run from identical state.
        // Every functional transaction is compared exactly against the dense
        // streams above; only stage-load AXI traffic and latency may differ.
        selected_sparse_mode = 1'b1;
        compare_against_dense = 1'b1;
        mode_stage_bytes = 0;
        total_sparse_requests = 0;
        completed_jobs = 0;
        completed_stage_loads = 0;
        reset_dut();
        run_frame(0);
        run_frame(1);
        sparse_two_frame_stage_bytes = mode_stage_bytes;
        check(completed_stage_loads == 24,
              "sparse two-frame run did not load all stages");
        check(completed_jobs == 60,
              "sparse two-frame run did not execute all jobs");
        check(feature_stream_index == dense_feature_stream_count,
              "dense/sparse feature stream length mismatch");
        check(coefficient_stream_index == dense_coefficient_stream_count,
              "dense/sparse coefficient stream length mismatch");
        check(state_stream_index == dense_state_stream_count,
              "dense/sparse state stream length mismatch");
        check(active_stream_index == dense_active_stream_count,
              "dense/sparse active-list stream length mismatch");
        check(weight_rsp_stream_index == dense_weight_rsp_stream_count,
              "dense/sparse weight response length mismatch");
        check(param_rsp_stream_index == dense_param_rsp_stream_count,
              "dense/sparse parameter response length mismatch");
        check(sparse_two_frame_stage_bytes < dense_two_frame_stage_bytes,
              "non-dense trace did not reduce DDR-to-cache stage bytes");
        check((epoch_lut_observed == 2040) &&
              (epoch_lut_actual_bytes == 2040) &&
              (lut_configuration_starts == 1),
              "sparse two-frame run reloaded or truncated LUT");

        compare_against_dense = 1'b0;

        // The request-handshake base is the only address identity forwarded
        // to CP4.  Changing the live pin after an accepted original-base LUT
        // AR is fatal, but cannot redirect or create a later AR transaction.
        reset_dut();
        @(negedge clk);
        stage_id = 4'd0;
        stage_bank = 2'd0;
        stage_req_valid = 1'b1;
        while (!stage_req_ready) @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        stage_req_valid = 1'b0;
        timeout = 0;
        while (!(m_axi_arvalid && m_axi_arready) && timeout < 5000) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        check(timeout < 5000,
              "sampled-base test did not issue initial LUT AR");
        check(m_axi_araddr ==
              (PARAMETER_BASE + `MODEL_V4_GLOBAL_SIGMOID_LUT_DRAM_OFFSET),
              "first AR did not use request-handshake base");
        @(posedge clk);
        #1;
        ar_before = axi_commands;
        @(negedge clk);
        parameter_base_addr = PARAMETER_BASE + 64;
        wait_for_reset_required("post-handshake base change was not fatal");
        check(integration_error_valid &&
              (integration_error_code == 8'h09) &&
              (dut.sampled_parameter_base_q == PARAMETER_BASE),
              "sampled-base fault identity/value mismatch");
        repeat (40) @(posedge clk);
        check(axi_commands == ar_before,
              "base change launched an AR from the live address");
        parameter_base_addr = PARAMETER_BASE;

        // During planner ownership, raw context mutation valids are visible
        // for faulting but are disconnected from the store and ready return.
        reset_dut();
        @(negedge clk);
        stage_id = 4'd0;
        stage_bank = 2'd0;
        stage_req_valid = 1'b1;
        while (!stage_req_ready) @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        stage_req_valid = 1'b0;
        force dut.store_list_desc_req_ready = 1'b0;
        timeout = 0;
        while (!dut.planner_desc_req_buf_valid_q && timeout < 100) begin
            @(posedge clk);
            #1;
            timeout = timeout + 1;
        end
        check(timeout < 100,
              "planner descriptor request did not enter elastic buffer");
        held_planner_desc_id = dut.store_list_desc_req_id;
        held_planner_desc_tag = dut.store_list_desc_req_tag;
        repeat (3) begin
            @(posedge clk);
            #1;
            check(dut.store_list_desc_req_valid &&
                  !dut.store_list_desc_req_ready &&
                  (dut.store_list_desc_req_id == held_planner_desc_id) &&
                  (dut.store_list_desc_req_tag == held_planner_desc_tag),
                  "planner descriptor buffer changed under backpressure");
        end
        @(negedge clk);
        force dut.context_producer_open_valid = 1'b1;
        #1;
        check((context_port_owner == 2'd1) &&
              !dut.store_producer_open_valid &&
              !dut.context_producer_open_ready,
              "planner owner did not block context producer handshake");
        @(posedge clk);
        #1;
        release dut.context_producer_open_valid;
        release dut.store_list_desc_req_ready;
        wait_for_reset_required("planner-time context mutation was not fatal");
        check(integration_error_valid &&
              (integration_error_code == 8'h0a) &&
              !dut.store_list_desc_req_valid,
              "planner-time context mutation fault mismatch");
        check_pre_service_failure_snapshot();

        // An abort asserted while a planner request is buffered is a shallow
        // same-cycle veto: releasing store backpressure must not consume the
        // queued request, and the next edge clears the buffer fail-closed.
        reset_dut();
        @(negedge clk);
        stage_id = 4'd0;
        stage_bank = 2'd0;
        stage_req_valid = 1'b1;
        while (!stage_req_ready) @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        stage_req_valid = 1'b0;
        force dut.store_list_desc_req_ready = 1'b0;
        timeout = 0;
        while (!dut.planner_desc_req_buf_valid_q && timeout < 100) begin
            @(posedge clk);
            #1;
            timeout = timeout + 1;
        end
        check(timeout < 100,
              "abort test did not fill planner descriptor buffer");
        @(negedge clk);
        abort = 1'b1;
        release dut.store_list_desc_req_ready;
        #1;
        check(!dut.store_list_desc_req_valid,
              "abort allowed a buffered planner request into the store");
        @(posedge clk);
        #1;
        check(!dut.planner_desc_req_buf_valid_q,
              "abort did not clear buffered planner request");
        @(negedge clk);
        abort = 1'b0;
        wait_for_reset_required("buffered-request abort was not fatal");

        // A synchronous component/PE fault is deliberately sampled by the
        // registered ownership proof.  One already-buffered read-only request
        // may retire on that edge, but the buffer is empty on the next cycle,
        // reset is sticky, and neither a plan nor residency may publish.
        reset_dut();
        @(negedge clk);
        stage_id = 4'd0;
        stage_bank = 2'd0;
        stage_req_valid = 1'b1;
        while (!stage_req_ready) @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        stage_req_valid = 1'b0;
        force dut.store_list_read_req_ready = 1'b0;
        force dut.planner_list_read_req_valid = 1'b1;
        force dut.planner_list_read_req_id = 5'd0;
        force dut.planner_list_read_req_ordinal = 9'd0;
        force dut.planner_list_read_req_tag = 8'hd2;
        timeout = 0;
        while (!dut.list_read_dispatch_valid_q && timeout < 100) begin
            @(posedge clk);
            #1;
            timeout = timeout + 1;
        end
        check(timeout < 100,
              "component-fault test did not fill list-read dispatch");
        check((dut.list_read_dispatch_owner_q == 2'd1) &&
              (dut.store_list_read_req_id == 5'd0) &&
              (dut.store_list_read_req_ordinal == 9'd0) &&
              (dut.store_list_read_req_tag == 8'hd2),
              "component-fault test captured the wrong dispatch tuple");
        ar_before = planner_read_store_count;
        @(negedge clk);
        release dut.planner_list_read_req_valid;
        release dut.planner_list_read_req_id;
        release dut.planner_list_read_req_ordinal;
        release dut.planner_list_read_req_tag;
        force dut.pe_protocol_error = 1'b1;
        force dut.controller_job_done = 1'b1;
        force dut.active_job_is_fb_q = 1'b1;
        release dut.store_list_read_req_ready;
        #1;
        check(reset_required && !dut.service_abort &&
              !dut.controller_registered_fault_abort &&
              !dut.internal_reset_required,
              "raw PE fault bypassed the internal registered boundary");
        check(!fb_done,
              "raw PE fault did not suppress same-cycle fullband done");
        check(dut.store_list_read_req_valid &&
              dut.store_list_read_req_ready &&
              (dut.list_read_dispatch_owner_q == 2'd1),
              "proven buffered request was not visible on component-fault edge");
        @(posedge clk);
        #1;
        check((planner_read_store_count == ar_before + 1) &&
              (planner_read_capture_count == planner_read_store_count) &&
              !dut.list_read_dispatch_valid_q && reset_required &&
              dut.internal_reset_required && (context_port_owner == 2'd3),
              "component-fault edge retired more than one buffered request");
        check(dut.controller_pe_protocol_error_q && dut.service_abort &&
              dut.controller_registered_fault_abort,
              "PE protocol fault did not cross registered abort boundary");
        @(negedge clk);
        release dut.controller_job_done;
        release dut.active_job_is_fb_q;
        release dut.pe_protocol_error;
        repeat (10) begin
            @(posedge clk);
            #1;
            check(controller_error_valid &&
                  (controller_error_code == 8'h06) &&
                  !dut.store_list_desc_req_valid &&
                  !dut.store_list_read_req_valid &&
                  !dut.planner_list_read_rsp_valid &&
                  !dut.context_list_read_rsp_valid &&
                  !dut.planner_plan_valid &&
                  !dut.service_stage_ready &&
                  !stage_load_done &&
                  (dut.u_sparse_memory_service.resident_bitmap0_q == 0) &&
                  (dut.u_sparse_memory_service.resident_bitmap1_q == 0),
                  "component fault allowed request/plan/residency publication");
        end

        // clear_state is forwarded only at the complete global-empty boundary.
        reset_dut();
        @(negedge clk);
        stage_id = 4'd0;
        stage_bank = 2'd0;
        stage_req_valid = 1'b1;
        while (!stage_req_ready) @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        stage_req_valid = 1'b0;
        clear_state = 1'b1;
        #1;
        check(!dut.global_clear_safe && !dut.context_clear_state,
              "planner-time clear reached context store");
        @(posedge clk);
        @(negedge clk);
        clear_state = 1'b0;
        repeat (2) @(posedge clk);
        #1;
        check(!dut.context_clear_state,
              "unsafe planner-time clear produced a store pulse");
        wait_for_reset_required("planner-time clear was not fatal");
        check(integration_error_valid &&
              (integration_error_code == 8'h08),
              "planner-time clear fault mismatch");
        check_pre_service_failure_snapshot();

        // A clear coincident with an abort must retain the fault and must
        // never become a delayed store mutation through the clear pipeline.
        reset_dut();
        @(negedge clk);
        clear_state = 1'b1;
        abort = 1'b1;
        #1;
        check(!dut.global_clear_safe && !dut.context_clear_state,
              "clear coincident with abort was reported safe");
        @(posedge clk);
        @(negedge clk);
        clear_state = 1'b0;
        abort = 1'b0;
        repeat (2) @(posedge clk);
        #1;
        check(reset_required && !dut.context_clear_state &&
              integration_error_valid &&
              (integration_error_code == 8'h08),
              "clear/abort collision did not fail closed without clearing");

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
        check(!stage_load_done && stage_load_error && stage_diag_valid &&
              !stage_diag_success,
              "invalid bank did not produce terminal load diagnostic");
        wait_for_reset_required("invalid bank did not become fatal");
        check(integration_error_valid && (integration_error_code == 8'h01),
              "invalid bank fault identity mismatch");
        check_pre_service_failure_snapshot();
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
        stage_id = 4'd0;
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
            $display("PASS tb_sequential_v4_sparse_memory_subsystem checks=%0d dense_bytes=%0d sparse_bytes=%0d",
                     checks, dense_two_frame_stage_bytes,
                     sparse_two_frame_stage_bytes);
        else
            $fatal(1, "FAIL tb_sequential_v4_sparse_memory_subsystem errors=%0d checks=%0d",
                   failures, checks);
        #20;
        $finish;
    end
endmodule
