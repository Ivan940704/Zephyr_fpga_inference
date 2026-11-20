`timescale 1ns/1ps

// Image-v5 / 32-row production integration shell.  The default frontend
// performs LayerNorm in PL; setting USE_PL_LAYERNORM=0 restores the checked PS
// mailbox path as an explicit debug fallback.
//
// This is the synthesizable RTL top for the current integration step.  A
// future Vivado block-design wrapper will connect its native AXI/BRAM/control
// ports to the Zynq PS, AXI DMA, and clock/reset infrastructure.
//
// Deliberately still external at this checkpoint:
//   * AXI DMA instances around the two ingress streams and result egress;
//   * AXI4-Lite register decode and PS block-design wiring.
module accelerator_top #(
    parameter integer AXI_ADDR_WIDTH = 32,
    parameter integer AXI_DATA_WIDTH = 64,
    parameter integer AXI_ID_WIDTH = 1,
    parameter integer FRAME_ID_WIDTH = 16,
    parameter integer FSM_TIMEOUT_CYCLES = 100000000,
    parameter integer MAILBOX_TIMEOUT_CYCLES = 100000000,
    parameter integer LOAD_TIMEOUT_CYCLES = 100000,
    parameter integer CONTROLLER_TIMEOUT_CYCLES = 1000000,
    parameter integer LUT_STALL_TIMEOUT_CYCLES = 100000,
    parameter integer USE_PL_LAYERNORM = 1
) (
    input  wire                         clk,
    input  wire                         rst_n,

    // Future AXI4-Lite control register inputs.
    input  wire                         start,
    input  wire                         abort,
    input  wire                         clear_error,
    input  wire                         quiesce_request,
    input  wire                         clear_state_on_start,
    input  wire                         sparse_load_enable,
    input  wire [AXI_ADDR_WIDTH-1:0]    parameter_base_addr,
    output wire                         start_ready,

    // Default PL frontend: one 512-byte packet containing 256 signed-Q12
    // magnitude bins. Debug fallback: one 64-byte normalized INT8 fullband
    // packet. Both modes retain the native 64-bit Zynq HP/AXIS width.
    input  wire                         s_axis_fb_tvalid,
    output wire                         s_axis_fb_tready,
    input  wire [63:0]                  s_axis_fb_tdata,
    input  wire [7:0]                   s_axis_fb_tkeep,
    input  wire                         s_axis_fb_tlast,

    // One 512-byte noisy complex-spectrum packet per frame from AXI DMA MM2S.
    input  wire                         s_axis_spectrum_tvalid,
    output wire                         s_axis_spectrum_tready,
    input  wire [63:0]                  s_axis_spectrum_tdata,
    input  wire [7:0]                   s_axis_spectrum_tkeep,
    input  wire                         s_axis_spectrum_tlast,

    // One 256-beat INT32 complex DeepFilter result packet to AXI DMA S2MM.
    output wire                         m_axis_output_tvalid,
    input  wire                         m_axis_output_tready,
    output wire [63:0]                  m_axis_output_tdata,
    output wire [7:0]                   m_axis_output_tkeep,
    output wire                         m_axis_output_tlast,

    // Native mailbox BRAM port for an AXI BRAM Controller on PS M_AXI_GP.
    input  wire                         ps_bram_en,
    input  wire [3:0]                   ps_bram_we,
    input  wire [9:0]                   ps_bram_addr,
    input  wire [31:0]                  ps_bram_wdata,
    output wire [31:0]                  ps_bram_rdata,
    output wire                         ps_bram_rvalid,

    // Mailbox ownership events from future AXI4-Lite control registers.
    input  wire                         ps_fb_release_valid,
    output wire                         ps_fb_release_ready,
    input  wire                         ps_fb_release_slot,
    input  wire [FRAME_ID_WIDTH-1:0]    ps_fb_release_frame_id,
    input  wire                         ps_sb_claim_valid,
    output wire                         ps_sb_claim_ready,
    input  wire                         ps_sb_claim_slot,
    input  wire [FRAME_ID_WIDTH-1:0]    ps_sb_claim_frame_id,
    input  wire                         ps_sb_commit_valid,
    output wire                         ps_sb_commit_ready,
    input  wire                         ps_sb_commit_slot,
    input  wire [FRAME_ID_WIDTH-1:0]    ps_sb_commit_frame_id,

    // Read-only parameter-image AXI master to the PS HP path.
    output wire [AXI_ADDR_WIDTH-1:0]    m_axi_araddr,
    output wire [AXI_ID_WIDTH-1:0]      m_axi_arid,
    output wire [7:0]                   m_axi_arlen,
    output wire [2:0]                   m_axi_arsize,
    output wire [1:0]                   m_axi_arburst,
    output wire [2:0]                   m_axi_arprot,
    output wire [3:0]                   m_axi_arcache,
    output wire [3:0]                   m_axi_arqos,
    output wire                         m_axi_arlock,
    output wire                         m_axi_arvalid,
    input  wire                         m_axi_arready,
    input  wire [AXI_DATA_WIDTH-1:0]    m_axi_rdata,
    input  wire [AXI_ID_WIDTH-1:0]      m_axi_rid,
    input  wire [1:0]                   m_axi_rresp,
    input  wire                         m_axi_rlast,
    input  wire                         m_axi_rvalid,
    output wire                         m_axi_rready,

    // System/FSM status.
    output wire                         busy,
    output wire                         done,
    output wire                         error,
    output wire [3:0]                   error_code,
    output wire [3:0]                   state_debug,
    output wire [31:0]                  state_cycle_count,
    output wire [2:0]                   pe_active_debug,
    output wire [2:0]                   pe_done_pending_debug,
    output wire                         reset_required,
    output wire                         soft_reset_safe,
    output wire                         sparse_mode_active,
    output wire [FRAME_ID_WIDTH-1:0]    current_frame_id,

    // Mailbox/adapter status for future AXI4-Lite readback.
    output wire [3:0]                   fb_slot_states,
    output wire [3:0]                   sb_slot_states,
    output wire [FRAME_ID_WIDTH-1:0]    expected_fb_frame_id,
    output wire [FRAME_ID_WIDTH-1:0]    expected_sb_frame_id,
    output wire [FRAME_ID_WIDTH-1:0]    expected_consume_frame_id,
    output wire                         fb_published_valid,
    output wire                         fb_published_slot,
    output wire [FRAME_ID_WIDTH-1:0]    fb_published_frame_id,
    output wire                         sb_committed_valid,
    output wire                         sb_committed_slot,
    output wire [FRAME_ID_WIDTH-1:0]    sb_committed_frame_id,
    output wire                         sb_released_valid,
    output wire                         sb_released_slot,
    output wire [FRAME_ID_WIDTH-1:0]    sb_released_frame_id,
    output wire                         mailbox_error_valid,
    output wire [7:0]                   mailbox_error_code,
    output wire                         mailbox_error_slot,
    output wire [FRAME_ID_WIDTH-1:0]    mailbox_error_frame_id,
    output wire                         mailbox_irq,
    output wire                         adapter_fb_publish_complete,
    output wire                         adapter_sb_buffer_valid,
    output wire                         adapter_error_valid,
    output wire [7:0]                   adapter_error_code,
    output wire [15:0]                  adapter_error_detail,
    output wire                         feature_dispatcher_busy,
    output wire                         fb_input_buffer_valid,
    output wire [FRAME_ID_WIDTH-1:0]    fb_input_buffer_frame_id,
    output wire                         feature_dispatcher_error_valid,
    output wire [7:0]                   feature_dispatcher_error_code,
    output wire [31:0]                  feature_dispatcher_error_detail,
    output wire [8:0]                   df_coefficient_context_valid,
    output wire                         df_coefficients_valid,
    output wire                         df_coefficient_store_busy,
    output wire                         df_coefficient_store_error_valid,
    output wire [7:0]                   df_coefficient_store_error_code,
    output wire [31:0]                  df_coefficient_store_error_detail,
    output wire                         spectrum_input_buffer_valid,
    output wire [FRAME_ID_WIDTH-1:0]    spectrum_input_buffer_frame_id,
    output wire                         df_engine_busy,
    output wire [7:0]                   df_engine_active_bin,
    output wire [2:0]                   df_history_depth,
    output wire                         df_engine_error_valid,
    output wire [7:0]                   df_engine_error_code,
    output wire [31:0]                  df_engine_error_detail,
    output wire                         unsupported_coefficient_fault,

    // Focused image-v5/32-PE subsystem diagnostics.
    output wire [2:0]                   pe_barrier_idle,
    output wire [2:0]                   pe_fault,
    output wire [3:0]                   active_stage_id,
    output wire [2:0]                   cache_state,
    output wire [3:0]                   compute_owner,
    output wire [2:0]                   lut_adapter_state,
    output wire [11:0]                  lut_accepted_bytes,
    output wire [1:0]                   lut_configuration_starts,
    output wire [5:0]                   controller_state,
    output wire [5:0]                   controller_row_tile,
    output wire [31:0]                  weight_request_count,
    output wire [31:0]                  dense_weight_request_count,
    output wire [31:0]                  sparse_weight_request_count,
    output wire                         memory_error_valid,
    output wire [7:0]                   memory_error_code,
    output wire                         context_error_valid,
    output wire [7:0]                   context_error_code,
    output wire                         controller_error_valid,
    output wire [7:0]                   controller_error_code,
    output wire                         integration_error_valid,
    output wire [7:0]                   integration_error_code,
    output wire [31:0]                  integration_error_detail,

    // Sparse-load planning, traffic, and ownership diagnostics.
    output wire [1:0]                   sparse_context_port_owner,
    output wire                         sparse_planner_error_valid,
    output wire [7:0]                   sparse_planner_error_code,
    output wire [31:0]                  sparse_planner_error_detail,
    output wire                         sparse_stage_diag_valid,
    output wire                         sparse_stage_diag_success,
    output wire [3:0]                   sparse_stage_diag_stage_id,
    output wire                         sparse_stage_diag_enabled,
    output wire                         sparse_stage_diag_fallback_full,
    output wire [31:0]                  sparse_stage_dense_reference_bytes,
    output wire [31:0]                  sparse_stage_planned_bytes,
    output wire [31:0]                  sparse_stage_actual_bytes,
    output wire [31:0]                  sparse_stage_saved_bytes,
    output wire [8:0]                   sparse_stage_union_count0,
    output wire [8:0]                   sparse_stage_union_count1,
    output wire [15:0]                  sparse_stage_copy_command_count,
    output wire [31:0]                  sparse_stage_ar_burst_count,
    output wire [31:0]                  sparse_stage_load_cycles,
    output wire [31:0]                  sparse_epoch_lut_actual_bytes
);
    wire stage_req_valid;
    wire stage_req_ready;
    wire [3:0] stage_id;
    wire [1:0] stage_bank;
    wire stage_load_done;
    wire stage_load_error;
    wire fsm_stage_sparse_load_enable;

    wire fsm_fb_start;
    wire subsystem_fb_start_ready;
    wire [1:0] fsm_fb_stage;
    wire subsystem_fb_done;
    wire subsystem_fb_error;
    wire fsm_fb_result_valid;
    wire adapter_fsm_fb_result_ready;
    wire adapter_fsm_ps_subbands_valid;
    wire selected_fsm_fb_result_ready;
    wire selected_fsm_ps_subbands_valid;
    wire fsm_ps_subbands_ready;

    wire [2:0] fsm_sb_start;
    wire subsystem_sb_start_ready;
    wire [1:0] fsm_sb_stage;
    wire [1:0] fsm_sb_shared_branch;
    wire [1:0] fsm_sb_context_0;
    wire [1:0] fsm_sb_context_1;
    wire [1:0] fsm_sb_context_2;
    wire [2:0] subsystem_sb_done;
    wire [2:0] subsystem_sb_error;

    wire [2:0] subsystem_pe_barrier_idle;
    wire [2:0] subsystem_pe_fault;
    wire subsystem_reset_required;
    wire subsystem_quiescent;
    wire fsm_pe_abort_pulse;
    wire fsm_clear_state_pulse;
    wire fsm_error;
    wire [2:0] fsm_pe_fault;
    reg  [2:0] fsm_pe_barrier_idle_q;
    wire fsm_start_request;
    reg start_armed_q;

    wire subsystem_feature_req_valid;
    wire dispatcher_feature_req_ready;
    wire [3:0] subsystem_feature_req_stage_id;
    wire [1:0] subsystem_feature_req_branch;
    wire [1:0] subsystem_feature_req_context;
    wire [9:0] subsystem_feature_req_source;
    wire [7:0] subsystem_feature_req_tag;
    wire dispatcher_feature_rsp_valid;
    wire subsystem_feature_rsp_ready;
    wire signed [7:0] dispatcher_feature_rsp_value;
    wire [7:0] dispatcher_feature_rsp_tag;
    wire dispatcher_feature_rsp_error;

    wire dispatcher_sb_read_valid;
    wire adapter_sb_read_ready;
    wire [9:0] dispatcher_sb_read_index;
    wire [FRAME_ID_WIDTH-1:0] dispatcher_sb_read_frame_id;
    wire adapter_sb_read_rsp_valid;
    wire dispatcher_sb_read_rsp_ready;
    wire signed [7:0] adapter_sb_read_rsp_data;
    wire adapter_sb_read_rsp_error;
    wire selected_sb_buffer_valid;
    wire selected_sb_read_ready;
    wire selected_sb_read_rsp_valid;
    wire signed [7:0] selected_sb_read_rsp_data;
    wire selected_sb_read_rsp_error;
    wire adapter_quiescent;
    wire adapter_fb_publish_complete_raw;
    wire adapter_sb_buffer_valid_raw;
    wire adapter_error_valid_raw;
    wire [7:0] adapter_error_code_raw;
    wire [15:0] adapter_error_detail_raw;
    wire [FRAME_ID_WIDTH-1:0] adapter_current_frame_id;
    wire dispatcher_frame_active;
    wire dispatcher_s_axis_fb_tready;

    wire coordinator_magnitude_tready;
    wire coordinator_fullband_tvalid;
    wire coordinator_fullband_tready;
    wire [63:0] coordinator_fullband_tdata;
    wire [7:0] coordinator_fullband_tkeep;
    wire coordinator_fullband_tlast;
    wire coordinator_fb_coefficient_ready;
    wire coordinator_subbands_valid;
    wire coordinator_sb_buffer_valid;
    wire coordinator_sb_read_ready;
    wire coordinator_sb_read_rsp_valid;
    wire signed [7:0] coordinator_sb_read_rsp_data;
    wire coordinator_sb_read_rsp_error;
    wire coordinator_magnitude_buffer_valid;
    wire [FRAME_ID_WIDTH-1:0] coordinator_magnitude_frame_id;
    wire coordinator_busy;
    wire coordinator_quiescent;
    wire [3:0] coordinator_state_debug;
    wire [31:0] coordinator_last_frame_cycles;
    wire coordinator_error_valid;
    wire [7:0] coordinator_error_code;
    wire [31:0] coordinator_error_detail;
    wire selected_layernorm_quiescent;
    wire selected_fullband_tvalid;
    wire [63:0] selected_fullband_tdata;
    wire [7:0] selected_fullband_tkeep;
    wire selected_fullband_tlast;
    reg [FRAME_ID_WIDTH-1:0] pl_frame_id_q;

    wire subsystem_coefficient_valid;
    wire subsystem_coefficient_ready;
    wire signed [7:0] subsystem_coefficient_value;
    wire [8:0] subsystem_coefficient_index;
    wire [15:0] subsystem_coefficient_tag;
    wire subsystem_coefficient_last;
    wire coefficient_is_fullband;
    wire coefficient_is_subband;
    wire df_coefficient_padding;
    wire df_coefficient_last;
    wire adapter_fb_coefficient_ready;
    wire df_store_coefficient_ready;
    wire df_store_frame_active;
    wire [FRAME_ID_WIDTH-1:0] df_store_frame_id;
    wire df_store_stream_active;
    wire df_coefficient_read_req_valid;
    wire df_coefficient_read_req_ready;
    wire [10:0] df_coefficient_read_req_address;
    wire df_coefficient_read_rsp_valid;
    wire df_coefficient_read_rsp_ready;
    wire signed [7:0] df_coefficient_read_rsp_value;
    wire df_coefficient_read_rsp_error;
    wire df_engine_start_ready;
    wire df_engine_done;
    wire df_engine_error;
    wire df_engine_output_complete;
    wire df_engine_frame_active;
    wire df_engine_s_axis_spectrum_tready;
    wire fsm_final_output_valid;
    reg unsupported_coefficient_fault_q;
    reg [2:0] fsm_pe_fault_q;
    reg subsystem_quiescent_q;
    reg df_store_frame_done_q;
    reg soft_reset_safe_sample_q;
    reg soft_reset_safe_q;

    wire mailbox_fb_begin_valid;
    wire mailbox_fb_begin_ready;
    wire [FRAME_ID_WIDTH-1:0] mailbox_fb_begin_frame_id;
    wire mailbox_fb_begin_slot;
    wire mailbox_fb_data_valid;
    wire mailbox_fb_data_ready;
    wire [7:0] mailbox_fb_data;
    wire mailbox_fb_data_last;
    wire mailbox_ps_subbands_valid;
    wire mailbox_ps_subbands_ready;
    wire mailbox_ps_subbands_slot;
    wire [FRAME_ID_WIDTH-1:0] mailbox_ps_subbands_frame_id;
    wire mailbox_sb_data_valid;
    wire mailbox_sb_data_ready;
    wire [7:0] mailbox_sb_data;
    wire [9:0] mailbox_sb_data_index;
    wire mailbox_sb_data_last;

    wire interface_fault;
    wire system_abort;
    wire fb_projection_start;
    wire fsm_df_start;

    assign coefficient_is_fullband = (active_stage_id == 4'd2);
    assign coefficient_is_subband = (active_stage_id == 4'd5) ||
                                    (active_stage_id == 4'd8) ||
                                    (active_stage_id == 4'd11);
    // The 32-row PE packs stage 5's 80 coefficients into three physical
    // tiles. Terminate the logical stream at index 79 and drain the remaining
    // 16 structural padding beats without presenting them to the compact
    // coefficient store. Keeping this adapter at the consumer boundary avoids
    // adding stage decode to the congestion-critical PE serializer.
    assign df_coefficient_padding = (active_stage_id == 4'd5) &&
                                    (subsystem_coefficient_index >= 9'd80);
    assign df_coefficient_last = subsystem_coefficient_last ||
        ((active_stage_id == 4'd5) &&
         (subsystem_coefficient_index == 9'd79));
    assign subsystem_coefficient_ready = system_abort ? 1'b0 :
        (coefficient_is_fullband ?
            (USE_PL_LAYERNORM ? coordinator_fb_coefficient_ready :
                                adapter_fb_coefficient_ready) :
        (coefficient_is_subband ? df_store_coefficient_ready : 1'b0));

    assign selected_fsm_fb_result_ready = USE_PL_LAYERNORM ?
        (rst_n && !system_abort) : adapter_fsm_fb_result_ready;
    assign selected_fsm_ps_subbands_valid = USE_PL_LAYERNORM ?
        coordinator_subbands_valid : adapter_fsm_ps_subbands_valid;
    assign selected_sb_buffer_valid = USE_PL_LAYERNORM ?
        coordinator_sb_buffer_valid : adapter_sb_buffer_valid_raw;
    assign selected_sb_read_ready = USE_PL_LAYERNORM ?
        coordinator_sb_read_ready : adapter_sb_read_ready;
    assign selected_sb_read_rsp_valid = USE_PL_LAYERNORM ?
        coordinator_sb_read_rsp_valid : adapter_sb_read_rsp_valid;
    assign selected_sb_read_rsp_data = USE_PL_LAYERNORM ?
        coordinator_sb_read_rsp_data : adapter_sb_read_rsp_data;
    assign selected_sb_read_rsp_error = USE_PL_LAYERNORM ?
        coordinator_sb_read_rsp_error : adapter_sb_read_rsp_error;
    assign selected_layernorm_quiescent = USE_PL_LAYERNORM ?
        coordinator_quiescent : adapter_quiescent;

    assign selected_fullband_tvalid = USE_PL_LAYERNORM ?
        coordinator_fullband_tvalid :
        (s_axis_fb_tvalid && !quiesce_request);
    assign selected_fullband_tdata = USE_PL_LAYERNORM ?
        coordinator_fullband_tdata : s_axis_fb_tdata;
    assign selected_fullband_tkeep = USE_PL_LAYERNORM ?
        coordinator_fullband_tkeep : s_axis_fb_tkeep;
    assign selected_fullband_tlast = USE_PL_LAYERNORM ?
        coordinator_fullband_tlast : s_axis_fb_tlast;
    assign coordinator_fullband_tready = USE_PL_LAYERNORM &&
        dispatcher_s_axis_fb_tready;

    assign current_frame_id = USE_PL_LAYERNORM ? pl_frame_id_q :
                              adapter_current_frame_id;
    assign adapter_fb_publish_complete = USE_PL_LAYERNORM ?
        (fsm_fb_result_valid && selected_fsm_fb_result_ready) :
        adapter_fb_publish_complete_raw;
    assign adapter_sb_buffer_valid = selected_sb_buffer_valid;
    assign adapter_error_valid = USE_PL_LAYERNORM ?
        coordinator_error_valid : adapter_error_valid_raw;
    assign adapter_error_code = USE_PL_LAYERNORM ?
        coordinator_error_code : adapter_error_code_raw;
    assign adapter_error_detail = USE_PL_LAYERNORM ?
        coordinator_error_detail[15:0] : adapter_error_detail_raw;

    assign unsupported_coefficient_fault =
        unsupported_coefficient_fault_q;
    assign interface_fault =
                             ((!USE_PL_LAYERNORM) && mailbox_error_valid) ||
                             adapter_error_valid ||
                             feature_dispatcher_error_valid ||
                             df_coefficient_store_error_valid ||
                             df_engine_error_valid ||
                             unsupported_coefficient_fault_q;
    assign fsm_pe_fault = fsm_pe_fault_q;
    // Do not feed subsystem_reset_required back into its own abort input.
    // The subsystem already stops itself on fatal internal faults; the sticky
    // output is a reset request, not an additional combinational abort source.
    assign system_abort = abort || fsm_pe_abort_pulse || interface_fault;
    assign reset_required = fsm_error || subsystem_reset_required ||
                            interface_fault;
    assign error = fsm_error;
    assign pe_barrier_idle = subsystem_pe_barrier_idle;
    assign pe_fault = subsystem_pe_fault;
    // Software reset is legal only after abort/drain has emptied every custom
    // transaction and ownership path.  AXI DMA channel-idle is outside this
    // RTL boundary and remains an additional driver-side prerequisite.
    wire soft_reset_safe_now = rst_n && subsystem_quiescent_q &&
        !busy && (&fsm_pe_barrier_idle_q) &&
        selected_layernorm_quiescent &&
        !dispatcher_frame_active && !feature_dispatcher_busy &&
        !df_store_frame_active && !df_store_stream_active &&
        !df_engine_frame_active && !df_engine_busy &&
        !m_axis_output_tvalid && !s_axis_fb_tvalid &&
        !s_axis_spectrum_tvalid &&
        (USE_PL_LAYERNORM || ((fb_slot_states == 4'd0) &&
                              (sb_slot_states == 4'd0)));
    assign soft_reset_safe = soft_reset_safe_q;
    assign s_axis_fb_tready = USE_PL_LAYERNORM ?
        (coordinator_magnitude_tready &&
         (!quiesce_request || coordinator_busy)) :
        (!quiesce_request && dispatcher_s_axis_fb_tready);
    assign s_axis_spectrum_tready = !quiesce_request &&
                                    df_engine_s_axis_spectrum_tready;

    // Once the control-plane fence is active, no new lifecycle, mailbox, or
    // AXIS admission can begin. Two registered samples then cut the wide
    // quiescence cone out of the AXI-Lite decode timing path and prevent a
    // stale one-cycle proof from authorizing reset.
    always @(posedge clk) begin
        if (!rst_n || !quiesce_request) begin
            soft_reset_safe_sample_q <= 1'b0;
            soft_reset_safe_q <= 1'b0;
        end else begin
            soft_reset_safe_sample_q <= soft_reset_safe_now;
            soft_reset_safe_q <= soft_reset_safe_sample_q;
        end
    end

    // In PL mode the disabled mailbox adapter no longer owns frame identity.
    // Advance only on the global retirement pulse, matching the fallback
    // adapter's externally visible sequence.
    always @(posedge clk) begin
        if (!rst_n || system_abort)
            pl_frame_id_q <= {FRAME_ID_WIDTH{1'b0}};
        else if (USE_PL_LAYERNORM && done)
            pl_frame_id_q <= pl_frame_id_q + 1'b1;
    end

    assign start_ready = rst_n && !quiesce_request && start_armed_q && !busy &&
        !reset_required && fb_input_buffer_valid &&
        (fb_input_buffer_frame_id == current_frame_id) &&
        spectrum_input_buffer_valid &&
        (spectrum_input_buffer_frame_id == current_frame_id);
    assign fsm_start_request = start && start_ready;

    assign fb_projection_start = fsm_fb_start &&
        subsystem_fb_start_ready && (fsm_fb_stage == 2'd2);

    always @(posedge clk) begin
        if (!rst_n) begin
            unsupported_coefficient_fault_q <= 1'b0;
        end else if (subsystem_coefficient_valid &&
                     !coefficient_is_fullband &&
                     !coefficient_is_subband) begin
            unsupported_coefficient_fault_q <= 1'b1;
        end
    end

    // Preserve the external one-shot start contract even though the request is
    // qualified by ingress-buffer readiness before reaching the FSM.
    always @(posedge clk) begin
        if (!rst_n) begin
            start_armed_q <= 1'b1;
        end else begin
            if (!start)
                start_armed_q <= 1'b1;
            else if (fsm_start_request)
                start_armed_q <= 1'b0;
        end
    end

    // Timing cuts for scheduler/control-only observations.  These indications
    // are sticky or conservative, so one registered cycle does not alter data
    // retirement; it removes long cross-design control cones at high density.
    always @(posedge clk) begin
        if (!rst_n) begin
            fsm_pe_barrier_idle_q <= 3'b000;
            fsm_pe_fault_q <= 3'b000;
            subsystem_quiescent_q <= 1'b0;
            df_store_frame_done_q <= 1'b0;
        end else begin
            fsm_pe_barrier_idle_q <= subsystem_pe_barrier_idle;
            fsm_pe_fault_q <= subsystem_pe_fault | {2'b00, interface_fault};
            subsystem_quiescent_q <= subsystem_quiescent;
            df_store_frame_done_q <= done;
        end
    end

    fsm #(
        .TIMEOUT_CYCLES(FSM_TIMEOUT_CYCLES)
    ) u_global_fsm (
        .clk(clk),
        .rst_n(rst_n),
        .start(fsm_start_request),
        .abort(abort),
        .clear_error(clear_error),
        .clear_state_on_start(clear_state_on_start),
        .sparse_load_enable(sparse_load_enable),
        .parallel_subbands(1'b0),
        .stage_req_valid(stage_req_valid),
        .stage_req_ready(stage_req_ready),
        .stage_id(stage_id),
        .stage_bank(stage_bank),
        .stage_sparse_load_enable(fsm_stage_sparse_load_enable),
        .stage_load_done(stage_load_done),
        .stage_load_error(stage_load_error),
        .fb_start(fsm_fb_start),
        .fb_start_ready(subsystem_fb_start_ready),
        .fb_stage(fsm_fb_stage),
        .fb_done(subsystem_fb_done),
        .fb_error(subsystem_fb_error),
        .fb_result_valid(fsm_fb_result_valid),
        .fb_result_ready(selected_fsm_fb_result_ready),
        .ps_subbands_valid(selected_fsm_ps_subbands_valid),
        .ps_subbands_ready(fsm_ps_subbands_ready),
        .sb_start(fsm_sb_start),
        .sb_start_ready(subsystem_sb_start_ready),
        .sb_stage(fsm_sb_stage),
        .sb_shared_branch(fsm_sb_shared_branch),
        .sb_context_0(fsm_sb_context_0),
        .sb_context_1(fsm_sb_context_1),
        .sb_context_2(fsm_sb_context_2),
        .sb_done(subsystem_sb_done),
        .sb_error(subsystem_sb_error),
        .df_start(fsm_df_start),
        .df_start_ready(df_engine_start_ready),
        .df_done(df_engine_done),
        .df_error(df_engine_error),
        .pe_barrier_idle(fsm_pe_barrier_idle_q),
        .pe_fault(fsm_pe_fault),
        .pe_abort_pulse(fsm_pe_abort_pulse),
        .pe_active_debug(pe_active_debug),
        .pe_done_pending_debug(pe_done_pending_debug),
        .final_output_valid(fsm_final_output_valid),
        .final_output_ready(df_engine_output_complete),
        .clear_state_pulse(fsm_clear_state_pulse),
        .busy(busy),
        .done(done),
        .error(fsm_error),
        .error_code(error_code),
        .parallel_mode_active(),
        .sparse_mode_active(sparse_mode_active),
        .state_debug(state_debug),
        .state_cycle_count(state_cycle_count)
    );

    sequential_v5_pe_memory_subsystem #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .LOAD_TIMEOUT_CYCLES(LOAD_TIMEOUT_CYCLES),
        .CONTROLLER_TIMEOUT_CYCLES(CONTROLLER_TIMEOUT_CYCLES),
        .LUT_STALL_TIMEOUT_CYCLES(LUT_STALL_TIMEOUT_CYCLES)
    ) u_pe_memory_subsystem (
        .clk(clk),
        .rst_n(rst_n),
        .abort(system_abort),
        .clear_error(1'b0),
        .clear_state(fsm_clear_state_pulse),
        .parameter_base_addr(parameter_base_addr),
        .stage_req_valid(stage_req_valid),
        .stage_req_ready(stage_req_ready),
        .stage_id(stage_id),
        .stage_bank(stage_bank),
        .sparse_load_enable(fsm_stage_sparse_load_enable),
        .stage_load_done(stage_load_done),
        .stage_load_error(stage_load_error),
        .fb_start(fsm_fb_start),
        .fb_start_ready(subsystem_fb_start_ready),
        .fb_stage(fsm_fb_stage),
        .fb_done(subsystem_fb_done),
        .fb_error(subsystem_fb_error),
        .sb_start(fsm_sb_start),
        .sb_start_ready(subsystem_sb_start_ready),
        .sb_stage(fsm_sb_stage),
        .sb_shared_branch(fsm_sb_shared_branch),
        .sb_context_0(fsm_sb_context_0),
        .sb_context_1(fsm_sb_context_1),
        .sb_context_2(fsm_sb_context_2),
        .sb_done(subsystem_sb_done),
        .sb_error(subsystem_sb_error),
        .feature_req_valid(subsystem_feature_req_valid),
        .feature_req_ready(dispatcher_feature_req_ready),
        .feature_req_stage_id(subsystem_feature_req_stage_id),
        .feature_req_branch(subsystem_feature_req_branch),
        .feature_req_context(subsystem_feature_req_context),
        .feature_req_source(subsystem_feature_req_source),
        .feature_req_tag(subsystem_feature_req_tag),
        .feature_rsp_valid(dispatcher_feature_rsp_valid),
        .feature_rsp_ready(subsystem_feature_rsp_ready),
        .feature_rsp_value(dispatcher_feature_rsp_value),
        .feature_rsp_tag(dispatcher_feature_rsp_tag),
        .feature_rsp_error(dispatcher_feature_rsp_error),
        .coefficient_valid(subsystem_coefficient_valid),
        .coefficient_ready(subsystem_coefficient_ready),
        .coefficient_value(subsystem_coefficient_value),
        .coefficient_index(subsystem_coefficient_index),
        .coefficient_tag(subsystem_coefficient_tag),
        .coefficient_last(subsystem_coefficient_last),
        .current_frame_id(current_frame_id),
        .frame_start(fsm_start_request),
        .frame_done(done),
        .s_axis_spectrum_tvalid(s_axis_spectrum_tvalid && !quiesce_request),
        .s_axis_spectrum_tready(df_engine_s_axis_spectrum_tready),
        .s_axis_spectrum_tdata(s_axis_spectrum_tdata),
        .s_axis_spectrum_tkeep(s_axis_spectrum_tkeep),
        .s_axis_spectrum_tlast(s_axis_spectrum_tlast),
        .df_start(fsm_df_start),
        .df_start_ready(df_engine_start_ready),
        .df_done(df_engine_done),
        .df_error(df_engine_error),
        .df_all_coefficients_valid(df_coefficients_valid),
        .df_coefficient_read_req_valid(df_coefficient_read_req_valid),
        .df_coefficient_read_req_ready(df_coefficient_read_req_ready),
        .df_coefficient_read_req_address(df_coefficient_read_req_address),
        .df_coefficient_read_rsp_valid(df_coefficient_read_rsp_valid),
        .df_coefficient_read_rsp_ready(df_coefficient_read_rsp_ready),
        .df_coefficient_read_rsp_value(df_coefficient_read_rsp_value),
        .df_coefficient_read_rsp_error(df_coefficient_read_rsp_error),
        .df_output_enable(fsm_final_output_valid),
        .m_axis_output_tvalid(m_axis_output_tvalid),
        .m_axis_output_tready(m_axis_output_tready),
        .m_axis_output_tdata(m_axis_output_tdata),
        .m_axis_output_tkeep(m_axis_output_tkeep),
        .m_axis_output_tlast(m_axis_output_tlast),
        .df_output_complete(df_engine_output_complete),
        .spectrum_buffer_valid(spectrum_input_buffer_valid),
        .spectrum_buffer_frame_id(spectrum_input_buffer_frame_id),
        .df_frame_active(df_engine_frame_active),
        .df_busy(df_engine_busy),
        .df_active_bin(df_engine_active_bin),
        .df_history_depth(df_history_depth),
        .df_error_valid(df_engine_error_valid),
        .df_error_code(df_engine_error_code),
        .df_error_detail(df_engine_error_detail),
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
        .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rid(m_axi_rid),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        .pe_barrier_idle(subsystem_pe_barrier_idle),
        .pe_fault(subsystem_pe_fault),
        .reset_required(subsystem_reset_required),
        .quiescent(subsystem_quiescent),
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
        .context_port_owner(sparse_context_port_owner),
        .planner_error_valid(sparse_planner_error_valid),
        .planner_error_code(sparse_planner_error_code),
        .planner_error_detail(sparse_planner_error_detail),
        .stage_diag_valid(sparse_stage_diag_valid),
        .stage_diag_success(sparse_stage_diag_success),
        .stage_diag_stage_id(sparse_stage_diag_stage_id),
        .stage_diag_sparse_enable(sparse_stage_diag_enabled),
        .stage_diag_fallback_full(sparse_stage_diag_fallback_full),
        .stage_dense_reference_bytes(sparse_stage_dense_reference_bytes),
        .stage_planned_bytes(sparse_stage_planned_bytes),
        .stage_actual_bytes(sparse_stage_actual_bytes),
        .stage_saved_bytes(sparse_stage_saved_bytes),
        .stage_union_count0(sparse_stage_union_count0),
        .stage_union_count1(sparse_stage_union_count1),
        .stage_copy_command_count(sparse_stage_copy_command_count),
        .stage_ar_burst_count(sparse_stage_ar_burst_count),
        .stage_load_cycles(sparse_stage_load_cycles),
        .epoch_lut_actual_bytes(sparse_epoch_lut_actual_bytes),
        .integration_error_valid(integration_error_valid),
        .integration_error_code(integration_error_code),
        .integration_error_detail(integration_error_detail)
    );

    layernorm_mailbox #(
        .FRAME_ID_WIDTH(FRAME_ID_WIDTH),
        .TIMEOUT_CYCLES(MAILBOX_TIMEOUT_CYCLES)
    ) u_layernorm_mailbox (
        .clk(clk),
        .rst_n(rst_n),
        .abort(system_abort || USE_PL_LAYERNORM),
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
        .fb_slot_states(fb_slot_states),
        .sb_slot_states(sb_slot_states),
        .expected_fb_frame_id(expected_fb_frame_id),
        .expected_sb_frame_id(expected_sb_frame_id),
        .expected_consume_frame_id(expected_consume_frame_id),
        .error_valid(mailbox_error_valid),
        .error_code(mailbox_error_code),
        .error_slot(mailbox_error_slot),
        .error_frame_id(mailbox_error_frame_id),
        .irq(mailbox_irq)
    );

    layernorm_mailbox_fsm_adapter #(
        .FRAME_ID_WIDTH(FRAME_ID_WIDTH),
        .SB_PAYLOAD_BYTES(782)
    ) u_mailbox_adapter (
        .clk(clk),
        .rst_n(rst_n),
        .abort(system_abort || USE_PL_LAYERNORM),
        .fb_projection_start(fb_projection_start && !USE_PL_LAYERNORM),
        .frame_done(df_store_frame_done_q),
        .fsm_fb_result_valid(fsm_fb_result_valid && !USE_PL_LAYERNORM),
        .fsm_fb_result_ready(adapter_fsm_fb_result_ready),
        .fsm_ps_subbands_valid(adapter_fsm_ps_subbands_valid),
        .fsm_ps_subbands_ready(fsm_ps_subbands_ready &&
                               !USE_PL_LAYERNORM),
        .fb_coefficient_valid(subsystem_coefficient_valid &&
                              coefficient_is_fullband &&
                              !USE_PL_LAYERNORM),
        .fb_coefficient_ready(adapter_fb_coefficient_ready),
        .fb_coefficient_value(subsystem_coefficient_value),
        .fb_coefficient_index(subsystem_coefficient_index),
        .fb_coefficient_last(subsystem_coefficient_last),
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
        .sb_read_valid(dispatcher_sb_read_valid && !USE_PL_LAYERNORM),
        .sb_read_ready(adapter_sb_read_ready),
        .sb_read_index(dispatcher_sb_read_index),
        .sb_read_frame_id(dispatcher_sb_read_frame_id),
        .sb_read_rsp_valid(adapter_sb_read_rsp_valid),
        .sb_read_rsp_ready(dispatcher_sb_read_rsp_ready &&
                           !USE_PL_LAYERNORM),
        .sb_read_rsp_data(adapter_sb_read_rsp_data),
        .sb_read_rsp_error(adapter_sb_read_rsp_error),
        .current_frame_id(adapter_current_frame_id),
        .fb_publish_complete(adapter_fb_publish_complete_raw),
        .sb_buffer_valid(adapter_sb_buffer_valid_raw),
        .quiescent(adapter_quiescent),
        .error_valid(adapter_error_valid_raw),
        .error_code(adapter_error_code_raw),
        .error_detail(adapter_error_detail_raw)
    );

    realtime_layernorm_coordinator #(
        .FRAME_ID_WIDTH(FRAME_ID_WIDTH)
    ) u_realtime_layernorm_coordinator (
        .clk(clk),
        .rst_n(rst_n),
        .abort(system_abort),
        .current_frame_id(current_frame_id),
        .frame_done(done),
        .s_axis_magnitude_tvalid(s_axis_fb_tvalid && USE_PL_LAYERNORM &&
                                 (!quiesce_request || coordinator_busy)),
        .s_axis_magnitude_tready(coordinator_magnitude_tready),
        .s_axis_magnitude_tdata(s_axis_fb_tdata),
        .s_axis_magnitude_tkeep(s_axis_fb_tkeep),
        .s_axis_magnitude_tlast(s_axis_fb_tlast),
        .m_axis_fullband_tvalid(coordinator_fullband_tvalid),
        .m_axis_fullband_tready(coordinator_fullband_tready),
        .m_axis_fullband_tdata(coordinator_fullband_tdata),
        .m_axis_fullband_tkeep(coordinator_fullband_tkeep),
        .m_axis_fullband_tlast(coordinator_fullband_tlast),
        .fb_projection_start(fb_projection_start && USE_PL_LAYERNORM),
        .fb_coefficient_valid(subsystem_coefficient_valid &&
                              coefficient_is_fullband &&
                              USE_PL_LAYERNORM),
        .fb_coefficient_ready(coordinator_fb_coefficient_ready),
        .fb_coefficient_value(subsystem_coefficient_value),
        .fb_coefficient_index(subsystem_coefficient_index),
        .fb_coefficient_last(subsystem_coefficient_last),
        .subbands_valid(coordinator_subbands_valid),
        .subbands_ready(fsm_ps_subbands_ready && USE_PL_LAYERNORM),
        .sb_buffer_valid(coordinator_sb_buffer_valid),
        .sb_read_valid(dispatcher_sb_read_valid && USE_PL_LAYERNORM),
        .sb_read_ready(coordinator_sb_read_ready),
        .sb_read_index(dispatcher_sb_read_index),
        .sb_read_frame_id(dispatcher_sb_read_frame_id),
        .sb_read_rsp_valid(coordinator_sb_read_rsp_valid),
        .sb_read_rsp_ready(dispatcher_sb_read_rsp_ready &&
                           USE_PL_LAYERNORM),
        .sb_read_rsp_data(coordinator_sb_read_rsp_data),
        .sb_read_rsp_error(coordinator_sb_read_rsp_error),
        .magnitude_buffer_valid(coordinator_magnitude_buffer_valid),
        .magnitude_buffer_frame_id(coordinator_magnitude_frame_id),
        .busy(coordinator_busy),
        .quiescent(coordinator_quiescent),
        .state_debug(coordinator_state_debug),
        .last_frame_cycle_count(coordinator_last_frame_cycles),
        .error_valid(coordinator_error_valid),
        .error_code(coordinator_error_code),
        .error_detail(coordinator_error_detail)
    );

    sequential_feature_dispatcher #(
        .FRAME_ID_WIDTH(FRAME_ID_WIDTH)
    ) u_feature_dispatcher (
        .clk(clk),
        .rst_n(rst_n),
        .abort(system_abort),
        .current_frame_id(current_frame_id),
        .frame_start(fsm_start_request),
        .frame_done(done),
        .s_axis_fb_tvalid(selected_fullband_tvalid),
        .s_axis_fb_tready(dispatcher_s_axis_fb_tready),
        .s_axis_fb_tdata(selected_fullband_tdata),
        .s_axis_fb_tkeep(selected_fullband_tkeep),
        .s_axis_fb_tlast(selected_fullband_tlast),
        .feature_req_valid(subsystem_feature_req_valid),
        .feature_req_ready(dispatcher_feature_req_ready),
        .feature_req_stage_id(subsystem_feature_req_stage_id),
        .feature_req_branch(subsystem_feature_req_branch),
        .feature_req_context(subsystem_feature_req_context),
        .feature_req_source(subsystem_feature_req_source),
        .feature_req_tag(subsystem_feature_req_tag),
        .feature_rsp_valid(dispatcher_feature_rsp_valid),
        .feature_rsp_ready(subsystem_feature_rsp_ready),
        .feature_rsp_value(dispatcher_feature_rsp_value),
        .feature_rsp_tag(dispatcher_feature_rsp_tag),
        .feature_rsp_error(dispatcher_feature_rsp_error),
        .sb_buffer_valid(selected_sb_buffer_valid),
        .sb_read_valid(dispatcher_sb_read_valid),
        .sb_read_ready(selected_sb_read_ready),
        .sb_read_index(dispatcher_sb_read_index),
        .sb_read_frame_id(dispatcher_sb_read_frame_id),
        .sb_read_rsp_valid(selected_sb_read_rsp_valid),
        .sb_read_rsp_ready(dispatcher_sb_read_rsp_ready),
        .sb_read_rsp_data(selected_sb_read_rsp_data),
        .sb_read_rsp_error(selected_sb_read_rsp_error),
        .fb_buffer_valid(fb_input_buffer_valid),
        .fb_buffer_frame_id(fb_input_buffer_frame_id),
        .frame_active(dispatcher_frame_active),
        .busy(feature_dispatcher_busy),
        .error_valid(feature_dispatcher_error_valid),
        .error_code(feature_dispatcher_error_code),
        .error_detail(feature_dispatcher_error_detail)
    );

    sequential_df_coefficient_store #(
        .FRAME_ID_WIDTH(FRAME_ID_WIDTH)
    ) u_df_coefficient_store (
        .clk(clk),
        .rst_n(rst_n),
        .abort(system_abort),
        .current_frame_id(current_frame_id),
        .frame_start(fsm_start_request),
        .frame_done(done),
        .consume_start(fsm_df_start),
        .coefficient_valid(subsystem_coefficient_valid &&
                           coefficient_is_subband &&
                           !df_coefficient_padding),
        .coefficient_ready(df_store_coefficient_ready),
        .coefficient_value(subsystem_coefficient_value),
        .coefficient_index(subsystem_coefficient_index),
        .coefficient_tag(subsystem_coefficient_tag),
        .coefficient_last(df_coefficient_last),
        .coefficient_stage_id(active_stage_id),
        .read_req_valid(df_coefficient_read_req_valid),
        .read_req_ready(df_coefficient_read_req_ready),
        .read_req_address(df_coefficient_read_req_address),
        .read_rsp_valid(df_coefficient_read_rsp_valid),
        .read_rsp_ready(df_coefficient_read_rsp_ready),
        .read_rsp_value(df_coefficient_read_rsp_value),
        .read_rsp_error(df_coefficient_read_rsp_error),
        .context_valid(df_coefficient_context_valid),
        .all_coefficients_valid(df_coefficients_valid),
        .frame_active(df_store_frame_active),
        .stored_frame_id(df_store_frame_id),
        .stream_active(df_store_stream_active),
        .error_valid(df_coefficient_store_error_valid),
        .error_code(df_coefficient_store_error_code),
        .error_detail(df_coefficient_store_error_detail)
    );

    assign df_coefficient_store_busy = df_store_frame_active ||
                                       df_store_stream_active;

endmodule
