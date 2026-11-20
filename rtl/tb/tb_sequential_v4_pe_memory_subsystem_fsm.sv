`timescale 1ns/1ps
`include "memory/model_memory_v4_map.vh"

// Schedule-level integration harness.  The deeper subsystem testbench checks
// every cache/list/PE transaction; this companion test proves that the
// existing production global FSM can drive the preserved stage/job ABI for
// two complete sequential frames.
module tb_sequential_v4_pe_memory_subsystem_fsm;
    localparam [31:0] PARAMETER_BASE = 32'h1000_0000;
    localparam integer IMAGE_BYTES = `MODEL_V4_IMAGE_BYTES;

    reg clk;
    reg rst_n;
    reg start;
    reg abort;
    reg clear_error;
    reg clear_state_on_start;

    wire stage_req_valid;
    wire stage_req_ready;
    wire [3:0] stage_id;
    wire [1:0] stage_bank;
    wire stage_load_done;
    wire stage_load_error;
    wire fb_start;
    wire fb_start_ready;
    wire [1:0] fb_stage;
    wire fb_done;
    wire fb_error;
    wire [2:0] sb_start;
    wire sb_start_ready;
    wire [1:0] sb_stage;
    wire [1:0] sb_shared_branch;
    wire [1:0] sb_context_0;
    wire [1:0] sb_context_1;
    wire [1:0] sb_context_2;
    wire [2:0] sb_done;
    wire [2:0] sb_error;
    wire [2:0] pe_barrier_idle;
    wire [2:0] pe_fault;
    wire pe_abort_pulse;
    wire clear_state_pulse;
    wire fsm_busy;
    wire fsm_done;
    wire fsm_error;
    wire [3:0] fsm_error_code;
    wire [3:0] fsm_state;
    wire [31:0] fsm_state_cycles;

    wire fb_result_valid;
    wire ps_subbands_ready;
    wire df_start;
    wire df_start_ready = 1'b1;
    reg df_done;
    reg df_pending;
    wire final_output_valid;

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
    reg feature_pending;
    reg [7:0] feature_pending_tag;

    wire coefficient_valid;
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
        .stage_id(stage_id), .stage_valid(ref_valid),
        .stage_kind(ref_kind), .dram_byte_offset(ref_dram_offset),
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

    fsm #(.TIMEOUT_CYCLES(6000000)) global_fsm (
        .clk(clk), .rst_n(rst_n), .start(start), .abort(abort),
        .clear_error(clear_error),
        .clear_state_on_start(clear_state_on_start),
        .sparse_load_enable(1'b0),
        .parallel_subbands(1'b0),
        .stage_req_valid(stage_req_valid),
        .stage_req_ready(stage_req_ready), .stage_id(stage_id),
        .stage_bank(stage_bank), .stage_load_done(stage_load_done),
        .stage_sparse_load_enable(),
        .stage_load_error(stage_load_error), .fb_start(fb_start),
        .fb_start_ready(fb_start_ready), .fb_stage(fb_stage),
        .fb_done(fb_done), .fb_error(fb_error),
        .fb_result_valid(fb_result_valid), .fb_result_ready(1'b1),
        .ps_subbands_valid(1'b1),
        .ps_subbands_ready(ps_subbands_ready), .sb_start(sb_start),
        .sb_start_ready(sb_start_ready), .sb_stage(sb_stage),
        .sb_shared_branch(sb_shared_branch),
        .sb_context_0(sb_context_0), .sb_context_1(sb_context_1),
        .sb_context_2(sb_context_2), .sb_done(sb_done),
        .sb_error(sb_error), .df_start(df_start),
        .df_start_ready(df_start_ready), .df_done(df_done),
        .df_error(1'b0), .pe_barrier_idle(pe_barrier_idle),
        .pe_fault(pe_fault), .pe_abort_pulse(pe_abort_pulse),
        .pe_active_debug(), .pe_done_pending_debug(),
        .final_output_valid(final_output_valid),
        .final_output_ready(1'b1),
        .clear_state_pulse(clear_state_pulse), .busy(fsm_busy),
        .done(fsm_done), .error(fsm_error),
        .error_code(fsm_error_code), .parallel_mode_active(),
        .sparse_mode_active(),
        .state_debug(fsm_state), .state_cycle_count(fsm_state_cycles)
    );

    sequential_v4_pe_memory_subsystem #(
        .LOAD_TIMEOUT_CYCLES(128),
        .CONTROLLER_TIMEOUT_CYCLES(1000),
        .LUT_STALL_TIMEOUT_CYCLES(128)
    ) dut (
        .clk(clk), .rst_n(rst_n), .abort(abort || pe_abort_pulse),
        .clear_error(clear_error), .clear_state(clear_state_pulse),
        .parameter_base_addr(PARAMETER_BASE),
        .stage_req_valid(stage_req_valid),
        .stage_req_ready(stage_req_ready), .stage_id(stage_id),
        .stage_bank(stage_bank), .stage_load_done(stage_load_done),
        .stage_load_error(stage_load_error), .fb_start(fb_start),
        .fb_start_ready(fb_start_ready), .fb_stage(fb_stage),
        .fb_done(fb_done), .fb_error(fb_error), .sb_start(sb_start),
        .sb_start_ready(sb_start_ready), .sb_stage(sb_stage),
        .sb_shared_branch(sb_shared_branch),
        .sb_context_0(sb_context_0), .sb_context_1(sb_context_1),
        .sb_context_2(sb_context_2), .sb_done(sb_done),
        .sb_error(sb_error), .feature_req_valid(feature_req_valid),
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
        .coefficient_ready(1'b1),
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
        .reset_required(reset_required),
        .active_stage_id(active_stage_id), .cache_state(cache_state),
        .compute_owner(compute_owner),
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
    integer cycle_count;
    integer axi_command_bytes;
    integer failures;
    integer checks;
    integer stage_accept_count;
    integer fb_accept_count;
    integer sb_accept_count;
    integer df_accept_count;
    integer expected_image_bytes;
    integer lut_byte_count;
    integer first_frame_sparse_requests;
    integer total_sparse_requests;
    integer expected_sb_stage;
    integer expected_sb_branch;
    integer expected_sb_context;

    always #5 clk = ~clk;

    task fail;
        input [8*180-1:0] message;
        begin
            failures = failures + 1;
            $display("FAIL: %0s time=%0t fsm=%0d controller=%0d",
                     message, $time, fsm_state, controller_state);
        end
    endtask

    task check;
        input condition;
        input [8*180-1:0] message;
        begin
            checks = checks + 1;
            if (!condition)
                fail(message);
        end
    endtask

    function [3:0] expected_stage;
        input integer ordinal;
        begin
            case (ordinal % 12)
                0: expected_stage = 4'd0;
                1: expected_stage = 4'd1;
                2: expected_stage = 4'd2;
                3: expected_stage = 4'd3;
                4: expected_stage = 4'd6;
                5: expected_stage = 4'd9;
                6: expected_stage = 4'd4;
                7: expected_stage = 4'd7;
                8: expected_stage = 4'd10;
                9: expected_stage = 4'd5;
                10: expected_stage = 4'd8;
                default: expected_stage = 4'd11;
            endcase
        end
    endfunction

    function integer last_context;
        input integer branch;
        begin
            case (branch)
                0: last_context = 3;
                1: last_context = 2;
                default: last_context = 1;
            endcase
        end
    endfunction

    function [63:0] image_word;
        input [31:0] byte_address;
        integer lane;
        integer image_index;
        begin
            image_word = 64'd0;
            image_index = byte_address - PARAMETER_BASE;
            for (lane = 0; lane < 8; lane = lane + 1)
                image_word[lane*8 +: 8] = dram[image_index + lane];
        end
    endfunction

    assign m_axi_arready = !dram_active && (cycle_count[2:0] != 3'b101);
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
        end else begin
            if (m_axi_arvalid && m_axi_arready) begin
                dram_active <= 1'b1;
                dram_read_addr <= m_axi_araddr;
                dram_beats_left <= {1'b0, m_axi_arlen} + 1'b1;
                axi_command_bytes <= axi_command_bytes +
                                     ((m_axi_arlen + 1) * 8);
                check((m_axi_arid == 0) && (m_axi_arsize == 3'd3) &&
                      (m_axi_arburst == 2'b01) &&
                      (m_axi_araddr[2:0] == 0),
                      "global-FSM AXI command contract mismatch");
            end
            if (dram_active && !m_axi_rvalid &&
                (cycle_count[2:0] != 3'b011)) begin
                m_axi_rdata <= image_word(dram_read_addr);
                m_axi_rlast <= (dram_beats_left == 1);
                m_axi_rvalid <= 1'b1;
            end
            if (m_axi_rvalid && m_axi_rready) begin
                m_axi_rvalid <= 1'b0;
                if (m_axi_rlast)
                    dram_active <= 1'b0;
                else begin
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
            feature_pending_tag <= 8'd0;
            feature_rsp_valid <= 1'b0;
            feature_rsp_value <= 8'sd0;
            feature_rsp_tag <= 8'd0;
            feature_rsp_error <= 1'b0;
        end else begin
            if (feature_req_valid && feature_req_ready) begin
                feature_pending <= 1'b1;
                feature_pending_tag <= feature_req_tag;
                check((feature_req_stage_id == 0) ||
                      (feature_req_stage_id == 3) ||
                      (feature_req_stage_id == 6) ||
                      (feature_req_stage_id == 9),
                      "global FSM exposed feature request outside GSU1");
            end
            if (feature_pending && !feature_rsp_valid) begin
                feature_rsp_valid <= 1'b1;
                feature_rsp_tag <= feature_pending_tag;
            end
            if (feature_rsp_valid && feature_rsp_ready) begin
                feature_rsp_valid <= 1'b0;
                feature_pending <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            df_done <= 1'b0;
            df_pending <= 1'b0;
            df_accept_count <= 0;
        end else begin
            df_done <= 1'b0;
            if (df_start && df_start_ready) begin
                df_pending <= 1'b1;
                df_accept_count <= df_accept_count + 1;
            end else if (df_pending) begin
                df_done <= 1'b1;
                df_pending <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            cycle_count <= 0;
            stage_accept_count <= 0;
            fb_accept_count <= 0;
            sb_accept_count <= 0;
            expected_image_bytes <= 2040;
            lut_byte_count <= 0;
            total_sparse_requests <= 0;
            expected_sb_stage <= 0;
            expected_sb_branch <= 0;
            expected_sb_context <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            if (stage_req_valid && stage_req_ready) begin
                check(ref_valid && (stage_bank == 0),
                      "global FSM issued invalid stage descriptor");
                check(stage_id == expected_stage(stage_accept_count),
                      "global FSM stage order mismatch");
                expected_image_bytes <= expected_image_bytes +
                                        ref_transfer_bytes;
                stage_accept_count <= stage_accept_count + 1;
            end
            if (fb_start && fb_start_ready) begin
                check(fb_stage == (fb_accept_count % 3),
                      "global FSM fullband job order mismatch");
                fb_accept_count <= fb_accept_count + 1;
            end
            if ((|sb_start) && sb_start_ready) begin
                check(sb_start == 3'b001,
                      "global FSM left shared-engine mode");
                check((sb_stage == (expected_sb_stage % 3)) &&
                      (sb_shared_branch == expected_sb_branch) &&
                      (sb_context_0 == expected_sb_context),
                      "global FSM subband context order mismatch");
                sb_accept_count <= sb_accept_count + 1;
                if (expected_sb_context ==
                    last_context(expected_sb_branch)) begin
                    expected_sb_context <= 0;
                    if (expected_sb_branch == 2) begin
                        expected_sb_branch <= 0;
                        expected_sb_stage <= expected_sb_stage + 1;
                    end else begin
                        expected_sb_branch <= expected_sb_branch + 1;
                    end
                end else begin
                    expected_sb_context <= expected_sb_context + 1;
                end
            end
            if (fb_done || sb_done[0])
                total_sparse_requests <= total_sparse_requests +
                                         sparse_weight_request_count;
            if (dut.pe_sigmoid_cfg_data_fire) begin
                check(dut.service_lut_cfg_data ===
                      dram[`MODEL_V4_GLOBAL_SIGMOID_LUT_DRAM_OFFSET +
                           lut_byte_count],
                      "global-FSM LUT byte mismatch");
                lut_byte_count <= lut_byte_count + 1;
            end
            check(!reset_required && !fsm_error,
                  "global-FSM connected run entered fatal state");
        end
    end

    task run_one_frame;
        input clear_contexts;
        integer timeout;
        begin
            while (fsm_busy || fsm_done) @(posedge clk);
            @(negedge clk);
            clear_state_on_start = clear_contexts;
            start = 1'b1;
            @(posedge clk);
            @(negedge clk);
            start = 1'b0;
            clear_state_on_start = 1'b0;
            timeout = 0;
            while (!fsm_done && !fsm_error && timeout < 10000000) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            check(timeout < 10000000,
                  "global FSM two-frame integration timed out");
            check(fsm_done && !fsm_error && !reset_required,
                  "global FSM frame did not finish cleanly");
            @(posedge clk);
        end
    endtask

    integer image_file;
    integer bytes_read;
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
        start = 1'b0;
        abort = 1'b0;
        clear_error = 1'b0;
        clear_state_on_start = 1'b0;
        failures = 0;
        checks = 0;
        first_frame_sparse_requests = 0;
        repeat (8) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        run_one_frame(1'b1);
        first_frame_sparse_requests = total_sparse_requests;
        run_one_frame(1'b0);

        check(stage_accept_count == 24,
              "global FSM did not request 12 stages per frame");
        check(fb_accept_count == 6,
              "global FSM did not launch three FB jobs per frame");
        check(sb_accept_count == 54,
              "global FSM did not launch 4/3/2 SB contexts per stage");
        check(df_accept_count == 2,
              "global FSM did not cross the external DF boundary twice");
        check((expected_sb_stage == 6) &&
              (expected_sb_branch == 0) &&
              (expected_sb_context == 0),
              "global FSM SB schedule did not close two frames");
        check((lut_byte_count == 2040) &&
              (lut_accepted_bytes == 2040) &&
              (lut_configuration_starts == 1),
              "global FSM path reloaded the reset-epoch LUT");
        check(axi_command_bytes == expected_image_bytes,
              "global FSM stage DDR bytes were not fully dense");
        check((first_frame_sparse_requests > 0) &&
              (total_sparse_requests > first_frame_sparse_requests),
              "global FSM did not consume produced sparse lists");
        check(pe_barrier_idle == 3'b111,
              "global FSM completed before the PE barrier");

        if (failures == 0)
            $display("PASS tb_sequential_v4_pe_memory_subsystem_fsm checks=%0d stages=%0d fb=%0d sb=%0d sparse=%0d",
                     checks, stage_accept_count, fb_accept_count,
                     sb_accept_count, total_sparse_requests);
        else
            $fatal(1, "FAIL tb_sequential_v4_pe_memory_subsystem_fsm errors=%0d checks=%0d",
                   failures, checks);
        #20;
        $finish;
    end
endmodule
