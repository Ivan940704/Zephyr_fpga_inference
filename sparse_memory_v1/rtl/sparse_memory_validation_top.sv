`timescale 1ns/1ps

// CP6 synthesis-only boundary for the isolated sparse-memory subsystem.
//
// This is not a production or board top.  Autonomous registered stimulus and
// registered observation make every subsystem boundary path clock-to-clock for
// OOC timing analysis without introducing repository-external RTL or IP.  The
// subsystem instance is kept intact so the CP6 hierarchy/resource report can
// distinguish the validation harness from the design under test.
module sparse_memory_validation_top (
    input  wire        clk,
    input  wire        rst_n,
    output reg  [31:0] validation_digest
);
    reg [127:0] stimulus_q;
    reg [671:0] captured_outputs_q;
    reg [4:0] scan_word_q;

    wire stimulus_feedback = stimulus_q[127] ^ stimulus_q[125] ^
                             stimulus_q[100] ^ stimulus_q[98];

    wire stage_req_ready;
    wire stage_load_done;
    wire stage_load_error;
    wire fb_start_ready;
    wire fb_done;
    wire fb_error;
    wire sb_start_ready;
    wire [2:0] sb_done;
    wire [2:0] sb_error;
    wire feature_req_valid;
    wire [3:0] feature_req_stage_id;
    wire [1:0] feature_req_branch;
    wire [1:0] feature_req_context;
    wire [9:0] feature_req_source;
    wire [7:0] feature_req_tag;
    wire feature_rsp_ready;
    wire coefficient_valid;
    wire signed [7:0] coefficient_value;
    wire [8:0] coefficient_index;
    wire [15:0] coefficient_tag;
    wire coefficient_last;
    wire [31:0] m_axi_araddr;
    wire m_axi_arid;
    wire [7:0] m_axi_arlen;
    wire [2:0] m_axi_arsize;
    wire [1:0] m_axi_arburst;
    wire [2:0] m_axi_arprot;
    wire [3:0] m_axi_arcache;
    wire [3:0] m_axi_arqos;
    wire m_axi_arlock;
    wire m_axi_arvalid;
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

    // The concatenation is exactly 656 bits.  Sixteen leading zeroes form the
    // 21 x 32-bit scan image used by the registered validation output.
    wire [655:0] subsystem_outputs = {
        stage_req_ready,
        stage_load_done,
        stage_load_error,
        fb_start_ready,
        fb_done,
        fb_error,
        sb_start_ready,
        sb_done,
        sb_error,
        feature_req_valid,
        feature_req_stage_id,
        feature_req_branch,
        feature_req_context,
        feature_req_source,
        feature_req_tag,
        feature_rsp_ready,
        coefficient_valid,
        coefficient_value,
        coefficient_index,
        coefficient_tag,
        coefficient_last,
        m_axi_araddr,
        m_axi_arid,
        m_axi_arlen,
        m_axi_arsize,
        m_axi_arburst,
        m_axi_arprot,
        m_axi_arcache,
        m_axi_arqos,
        m_axi_arlock,
        m_axi_arvalid,
        m_axi_rready,
        pe_barrier_idle,
        pe_fault,
        reset_required,
        active_stage_id,
        cache_state,
        compute_owner,
        lut_adapter_state,
        lut_accepted_bytes,
        lut_configuration_starts,
        controller_state,
        controller_row_tile,
        weight_request_count,
        dense_weight_request_count,
        sparse_weight_request_count,
        memory_error_valid,
        memory_error_code,
        context_error_valid,
        context_error_code,
        controller_error_valid,
        controller_error_code,
        context_port_owner,
        planner_error_valid,
        planner_error_code,
        planner_error_detail,
        stage_diag_valid,
        stage_diag_success,
        stage_diag_stage_id,
        stage_diag_sparse_enable,
        stage_diag_fallback_full,
        stage_dense_reference_bytes,
        stage_planned_bytes,
        stage_actual_bytes,
        stage_saved_bytes,
        stage_union_count0,
        stage_union_count1,
        stage_copy_command_count,
        stage_ar_burst_count,
        stage_load_cycles,
        epoch_lut_actual_bytes,
        integration_error_valid,
        integration_error_code,
        integration_error_detail
    };

    (* DONT_TOUCH = "yes", KEEP_HIERARCHY = "yes" *)
    sequential_v4_sparse_memory_subsystem u_sparse_subsystem (
        .clk(clk),
        .rst_n(rst_n),
        .abort(stimulus_q[0]),
        .clear_error(stimulus_q[1]),
        .clear_state(stimulus_q[2]),
        .parameter_base_addr({stimulus_q[127:102], 6'b0}),
        .stage_req_valid(stimulus_q[3]),
        .stage_req_ready(stage_req_ready),
        .stage_id(stimulus_q[7:4]),
        .stage_bank(stimulus_q[9:8]),
        .sparse_load_enable(stimulus_q[10]),
        .stage_load_done(stage_load_done),
        .stage_load_error(stage_load_error),
        .fb_start(stimulus_q[11]),
        .fb_start_ready(fb_start_ready),
        .fb_stage(stimulus_q[13:12]),
        .fb_done(fb_done),
        .fb_error(fb_error),
        .sb_start(stimulus_q[16:14]),
        .sb_start_ready(sb_start_ready),
        .sb_stage(stimulus_q[18:17]),
        .sb_shared_branch(stimulus_q[20:19]),
        .sb_context_0(stimulus_q[22:21]),
        .sb_context_1(stimulus_q[24:23]),
        .sb_context_2(stimulus_q[26:25]),
        .sb_done(sb_done),
        .sb_error(sb_error),
        .feature_req_valid(feature_req_valid),
        .feature_req_ready(stimulus_q[27]),
        .feature_req_stage_id(feature_req_stage_id),
        .feature_req_branch(feature_req_branch),
        .feature_req_context(feature_req_context),
        .feature_req_source(feature_req_source),
        .feature_req_tag(feature_req_tag),
        .feature_rsp_valid(stimulus_q[28]),
        .feature_rsp_ready(feature_rsp_ready),
        .feature_rsp_value(stimulus_q[36:29]),
        .feature_rsp_tag(stimulus_q[44:37]),
        .feature_rsp_error(stimulus_q[45]),
        .coefficient_valid(coefficient_valid),
        .coefficient_ready(stimulus_q[46]),
        .coefficient_value(coefficient_value),
        .coefficient_index(coefficient_index),
        .coefficient_tag(coefficient_tag),
        .coefficient_last(coefficient_last),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arid(m_axi_arid),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arprot(m_axi_arprot),
        .m_axi_arcache(m_axi_arcache),
        .m_axi_arqos(m_axi_arqos),
        .m_axi_arlock(m_axi_arlock),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(stimulus_q[47]),
        .m_axi_rdata(stimulus_q[111:48]),
        .m_axi_rid(stimulus_q[112]),
        .m_axi_rresp(stimulus_q[114:113]),
        .m_axi_rlast(stimulus_q[115]),
        .m_axi_rvalid(stimulus_q[116]),
        .m_axi_rready(m_axi_rready),
        .pe_barrier_idle(pe_barrier_idle),
        .pe_fault(pe_fault),
        .reset_required(reset_required),
        .active_stage_id(active_stage_id),
        .cache_state(cache_state),
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

    always @(posedge clk) begin
        if (!rst_n) begin
            stimulus_q <= 128'h1d4c_39a7_52e8_b601_c35a_8f27_94d2_6be1;
            captured_outputs_q <= 672'd0;
            scan_word_q <= 5'd0;
            validation_digest <= 32'd0;
        end else begin
            stimulus_q <= {stimulus_q[126:0], stimulus_feedback};
            captured_outputs_q <= {16'd0, subsystem_outputs};
            if (scan_word_q == 5'd20)
                scan_word_q <= 5'd0;
            else
                scan_word_q <= scan_word_q + 1'b1;

            case (scan_word_q)
                5'd0:  validation_digest <= captured_outputs_q[31:0];
                5'd1:  validation_digest <= captured_outputs_q[63:32];
                5'd2:  validation_digest <= captured_outputs_q[95:64];
                5'd3:  validation_digest <= captured_outputs_q[127:96];
                5'd4:  validation_digest <= captured_outputs_q[159:128];
                5'd5:  validation_digest <= captured_outputs_q[191:160];
                5'd6:  validation_digest <= captured_outputs_q[223:192];
                5'd7:  validation_digest <= captured_outputs_q[255:224];
                5'd8:  validation_digest <= captured_outputs_q[287:256];
                5'd9:  validation_digest <= captured_outputs_q[319:288];
                5'd10: validation_digest <= captured_outputs_q[351:320];
                5'd11: validation_digest <= captured_outputs_q[383:352];
                5'd12: validation_digest <= captured_outputs_q[415:384];
                5'd13: validation_digest <= captured_outputs_q[447:416];
                5'd14: validation_digest <= captured_outputs_q[479:448];
                5'd15: validation_digest <= captured_outputs_q[511:480];
                5'd16: validation_digest <= captured_outputs_q[543:512];
                5'd17: validation_digest <= captured_outputs_q[575:544];
                5'd18: validation_digest <= captured_outputs_q[607:576];
                5'd19: validation_digest <= captured_outputs_q[639:608];
                default: validation_digest <= captured_outputs_q[671:640];
            endcase
        end
    end
endmodule
