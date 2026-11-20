`timescale 1ns/1ps

// Vivado module-reference boundary for the complete Zephyr PL subsystem.
//
// All interfaces in the first PYNQ-Z1 build use PS7 FCLK0 at 100 MHz.  The
// block design connects S_AXI_CONTROL to PS M_AXI_GP0, M_AXI_PARAMETER to
// PS S_AXI_HP0, the three external DMA memory channels to HP1..HP3, and
// MAILBOX_BRAM to an AXI BRAM Controller on the same GP0 control fabric.
module accelerator_system_top #(
    parameter integer AXI_ADDR_WIDTH = 32,
    parameter integer AXI_DATA_WIDTH = 64,
    parameter integer AXI_ID_WIDTH = 6,
    parameter integer FRAME_ID_WIDTH = 16,
    parameter integer USE_PL_LAYERNORM = 1,
    parameter [31:0] IMAGE_VERSION = 32'h0005_0003
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aclk, ASSOCIATED_BUSIF S_AXI_CONTROL:M_AXI_PARAMETER:S_AXIS_FB:S_AXIS_SPECTRUM:M_AXIS_OUTPUT:MAILBOX_BRAM, ASSOCIATED_RESET aresetn:accelerator_aresetn, FREQ_HZ 100000000" *)
    input  wire                         aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aresetn, POLARITY ACTIVE_LOW" *)
    input  wire                         aresetn,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 accelerator_aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME accelerator_aresetn, POLARITY ACTIVE_LOW" *)
    input  wire                         accelerator_aresetn,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CONTROL AWADDR" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI_CONTROL, PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 12, FREQ_HZ 100000000, READ_WRITE_MODE READ_WRITE" *)
    input  wire [11:0]                  s_axi_control_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CONTROL AWPROT" *)
    input  wire [2:0]                   s_axi_control_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CONTROL AWVALID" *)
    input  wire                         s_axi_control_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CONTROL AWREADY" *)
    output wire                         s_axi_control_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CONTROL WDATA" *)
    input  wire [31:0]                  s_axi_control_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CONTROL WSTRB" *)
    input  wire [3:0]                   s_axi_control_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CONTROL WVALID" *)
    input  wire                         s_axi_control_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CONTROL WREADY" *)
    output wire                         s_axi_control_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CONTROL BRESP" *)
    output wire [1:0]                   s_axi_control_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CONTROL BVALID" *)
    output wire                         s_axi_control_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CONTROL BREADY" *)
    input  wire                         s_axi_control_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CONTROL ARADDR" *)
    input  wire [11:0]                  s_axi_control_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CONTROL ARPROT" *)
    input  wire [2:0]                   s_axi_control_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CONTROL ARVALID" *)
    input  wire                         s_axi_control_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CONTROL ARREADY" *)
    output wire                         s_axi_control_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CONTROL RDATA" *)
    output wire [31:0]                  s_axi_control_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CONTROL RRESP" *)
    output wire [1:0]                   s_axi_control_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CONTROL RVALID" *)
    output wire                         s_axi_control_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CONTROL RREADY" *)
    input  wire                         s_axi_control_rready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_PARAMETER ARADDR" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXI_PARAMETER, PROTOCOL AXI4, DATA_WIDTH 64, ADDR_WIDTH 32, ID_WIDTH 6, MAX_BURST_LENGTH 16, NUM_READ_OUTSTANDING 1, READ_WRITE_MODE READ_ONLY, FREQ_HZ 100000000" *)
    output wire [AXI_ADDR_WIDTH-1:0]    m_axi_parameter_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_PARAMETER ARID" *)
    output wire [AXI_ID_WIDTH-1:0]      m_axi_parameter_arid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_PARAMETER ARLEN" *)
    output wire [7:0]                   m_axi_parameter_arlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_PARAMETER ARSIZE" *)
    output wire [2:0]                   m_axi_parameter_arsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_PARAMETER ARBURST" *)
    output wire [1:0]                   m_axi_parameter_arburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_PARAMETER ARPROT" *)
    output wire [2:0]                   m_axi_parameter_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_PARAMETER ARCACHE" *)
    output wire [3:0]                   m_axi_parameter_arcache,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_PARAMETER ARQOS" *)
    output wire [3:0]                   m_axi_parameter_arqos,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_PARAMETER ARLOCK" *)
    output wire                         m_axi_parameter_arlock,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_PARAMETER ARVALID" *)
    output wire                         m_axi_parameter_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_PARAMETER ARREADY" *)
    input  wire                         m_axi_parameter_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_PARAMETER RDATA" *)
    input  wire [AXI_DATA_WIDTH-1:0]    m_axi_parameter_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_PARAMETER RID" *)
    input  wire [AXI_ID_WIDTH-1:0]      m_axi_parameter_rid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_PARAMETER RRESP" *)
    input  wire [1:0]                   m_axi_parameter_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_PARAMETER RLAST" *)
    input  wire                         m_axi_parameter_rlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_PARAMETER RVALID" *)
    input  wire                         m_axi_parameter_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_PARAMETER RREADY" *)
    output wire                         m_axi_parameter_rready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_FB TVALID" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXIS_FB, TDATA_NUM_BYTES 8, HAS_TKEEP 1, HAS_TLAST 1, FREQ_HZ 100000000" *)
    input  wire                         s_axis_fb_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_FB TREADY" *)
    output wire                         s_axis_fb_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_FB TDATA" *)
    input  wire [63:0]                  s_axis_fb_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_FB TKEEP" *)
    input  wire [7:0]                   s_axis_fb_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_FB TLAST" *)
    input  wire                         s_axis_fb_tlast,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_SPECTRUM TVALID" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXIS_SPECTRUM, TDATA_NUM_BYTES 8, HAS_TKEEP 1, HAS_TLAST 1, FREQ_HZ 100000000" *)
    input  wire                         s_axis_spectrum_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_SPECTRUM TREADY" *)
    output wire                         s_axis_spectrum_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_SPECTRUM TDATA" *)
    input  wire [63:0]                  s_axis_spectrum_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_SPECTRUM TKEEP" *)
    input  wire [7:0]                   s_axis_spectrum_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_SPECTRUM TLAST" *)
    input  wire                         s_axis_spectrum_tlast,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_OUTPUT TVALID" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXIS_OUTPUT, TDATA_NUM_BYTES 8, HAS_TKEEP 1, HAS_TLAST 1, FREQ_HZ 100000000" *)
    output wire                         m_axis_output_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_OUTPUT TREADY" *)
    input  wire                         m_axis_output_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_OUTPUT TDATA" *)
    output wire [63:0]                  m_axis_output_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_OUTPUT TKEEP" *)
    output wire [7:0]                   m_axis_output_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_OUTPUT TLAST" *)
    output wire                         m_axis_output_tlast,

    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 MAILBOX_BRAM CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME MAILBOX_BRAM, MEM_SIZE 4096, MASTER_TYPE BRAM_CTRL, MEM_ECC NONE, READ_LATENCY 1, READ_WRITE_MODE READ_WRITE" *)
    input  wire                         mailbox_bram_clk,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 MAILBOX_BRAM RST" *)
    input  wire                         mailbox_bram_rst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 MAILBOX_BRAM EN" *)
    input  wire                         mailbox_bram_en,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 MAILBOX_BRAM WE" *)
    input  wire [3:0]                   mailbox_bram_we,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 MAILBOX_BRAM ADDR" *)
    input  wire [11:0]                  mailbox_bram_addr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 MAILBOX_BRAM DIN" *)
    input  wire [31:0]                  mailbox_bram_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 MAILBOX_BRAM DOUT" *)
    output wire [31:0]                  mailbox_bram_rdata,

    (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 accelerator_irq INTERRUPT" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME accelerator_irq, SENSITIVITY LEVEL_HIGH" *)
    output wire                         accelerator_irq,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 soft_reset_request RST" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME soft_reset_request, POLARITY ACTIVE_HIGH" *)
    output wire                         soft_reset_request
);
    wire soft_reset_pulse;
    wire reset_quiesce_request;
    wire accelerator_reset_active = !accelerator_aresetn;
    wire [31:0] control_debug_unused;

    wire accelerator_start;
    wire accelerator_abort;
    wire accelerator_clear_error;
    wire clear_state_on_start;
    wire sparse_load_enable;
    wire [31:0] parameter_base_addr;
    wire [7:0] profiling_read_index;
    wire [31:0] profiling_read_data;
    wire profiling_enable;
    wire profiling_clear_pulse;
    wire profiling_snapshot_pulse;
    wire profiling_snapshot_valid;
    wire profiling_frame_active;
    wire profiling_snapshot_busy;
    wire accelerator_start_ready;
    wire accelerator_busy;
    wire accelerator_done;
    wire accelerator_error;
    wire [3:0] accelerator_error_code;
    wire [3:0] accelerator_state;
    wire [31:0] accelerator_state_cycles;
    wire accelerator_reset_required;
    wire accelerator_soft_reset_safe;
    wire accelerator_sparse_mode;
    wire [FRAME_ID_WIDTH-1:0] accelerator_frame_id;

    wire ps_fb_release_valid;
    wire ps_fb_release_ready;
    wire ps_fb_release_slot;
    wire [FRAME_ID_WIDTH-1:0] ps_fb_release_frame_id;
    wire ps_sb_claim_valid;
    wire ps_sb_claim_ready;
    wire ps_sb_claim_slot;
    wire [FRAME_ID_WIDTH-1:0] ps_sb_claim_frame_id;
    wire ps_sb_commit_valid;
    wire ps_sb_commit_ready;
    wire ps_sb_commit_slot;
    wire [FRAME_ID_WIDTH-1:0] ps_sb_commit_frame_id;

    wire [3:0] fb_slot_states;
    wire [3:0] sb_slot_states;
    wire [FRAME_ID_WIDTH-1:0] expected_fb_frame_id;
    wire [FRAME_ID_WIDTH-1:0] expected_sb_frame_id;
    wire [FRAME_ID_WIDTH-1:0] expected_consume_frame_id;
    wire fb_published_valid;
    wire fb_published_slot;
    wire [FRAME_ID_WIDTH-1:0] fb_published_frame_id;
    wire sb_committed_valid;
    wire sb_committed_slot;
    wire [FRAME_ID_WIDTH-1:0] sb_committed_frame_id;
    wire sb_released_valid;
    wire sb_released_slot;
    wire [FRAME_ID_WIDTH-1:0] sb_released_frame_id;
    wire mailbox_error_valid;
    wire [7:0] mailbox_error_code;
    wire mailbox_error_slot;
    wire [FRAME_ID_WIDTH-1:0] mailbox_error_frame_id;
    wire mailbox_irq;
    wire mailbox_bram_rvalid_unused;

    wire fb_input_buffer_valid;
    wire [FRAME_ID_WIDTH-1:0] fb_input_buffer_frame_id;
    wire spectrum_input_buffer_valid;
    wire [FRAME_ID_WIDTH-1:0] spectrum_input_buffer_frame_id;
    wire [3:0] active_stage_id;
    wire [2:0] cache_state;
    wire [3:0] compute_owner;
    wire [5:0] controller_state;
    wire [31:0] weight_request_count;
    wire [31:0] dense_weight_request_count;
    wire [31:0] sparse_weight_request_count;
    wire sparse_stage_diag_valid;
    wire sparse_stage_diag_success;
    wire [3:0] sparse_stage_diag_stage_id;
    wire sparse_stage_diag_enabled;
    wire sparse_stage_diag_fallback_full;
    wire [31:0] sparse_stage_actual_bytes;
    wire [31:0] sparse_stage_saved_bytes;
    wire [31:0] sparse_stage_ar_burst_count;
    wire [31:0] sparse_stage_load_cycles;

    wire adapter_error_valid;
    wire [7:0] adapter_error_code;
    wire [15:0] adapter_error_detail;
    wire feature_error_valid;
    wire [7:0] feature_error_code;
    wire [31:0] feature_error_detail;
    wire coefficient_error_valid;
    wire [7:0] coefficient_error_code;
    wire [31:0] coefficient_error_detail;
    wire df_error_valid;
    wire [7:0] df_error_code;
    wire [31:0] df_error_detail;
    wire unsupported_coefficient_fault;
    wire memory_error_valid;
    wire [7:0] memory_error_code;
    wire context_error_valid;
    wire [7:0] context_error_code;
    wire controller_error_valid;
    wire [7:0] controller_error_code;
    wire integration_error_valid;
    wire [7:0] integration_error_code;
    wire [31:0] integration_error_detail;
    wire planner_error_valid;
    wire [7:0] planner_error_code;
    wire [31:0] planner_error_detail;

    reg fault_valid;
    reg [7:0] fault_source;
    reg [7:0] fault_code;
    reg [31:0] fault_detail;

    // Keep the AXI-Lite control plane alive while a second proc_sys_reset
    // instance performs a synchronous, stretched reset of the data plane.
    // This removes the fabric counter/decode from the accelerator reset tree.
    assign soft_reset_request = soft_reset_pulse;

    // Preserve the same clock/reset domain as the AXI BRAM Controller.  The
    // native mailbox storage itself is clocked by aclk; BD validation requires
    // MAILBOX_BRAM.CLK and aclk to be the same FCLK0 net.
    wire mailbox_interface_unused = mailbox_bram_clk ^ mailbox_bram_rst;

    // Priority-encode the first actionable accelerator fault for software.
    // The source byte distinguishes equal local error codes from different
    // subsystems; the detailed native status remains available below.
    always @* begin
        fault_valid = 1'b1;
        fault_source = 8'h00;
        fault_code = 8'h00;
        fault_detail = 32'd0;
        if (mailbox_error_valid) begin
            fault_source = 8'h02;
            fault_code = mailbox_error_code;
            fault_detail = {7'd0, mailbox_error_slot,
                            mailbox_error_frame_id, mailbox_error_code};
        end else if (adapter_error_valid) begin
            fault_source = 8'h03;
            fault_code = adapter_error_code;
            fault_detail = {16'd0, adapter_error_detail};
        end else if (feature_error_valid) begin
            fault_source = 8'h04;
            fault_code = feature_error_code;
            fault_detail = feature_error_detail;
        end else if (coefficient_error_valid) begin
            fault_source = 8'h05;
            fault_code = coefficient_error_code;
            fault_detail = coefficient_error_detail;
        end else if (df_error_valid) begin
            fault_source = 8'h06;
            fault_code = df_error_code;
            fault_detail = df_error_detail;
        end else if (memory_error_valid) begin
            fault_source = 8'h07;
            fault_code = memory_error_code;
            fault_detail = {accelerator_frame_id, active_stage_id,
                            cache_state, controller_state, 3'd0};
        end else if (context_error_valid) begin
            fault_source = 8'h08;
            fault_code = context_error_code;
            fault_detail = {accelerator_frame_id, active_stage_id,
                            cache_state, controller_state, 3'd0};
        end else if (controller_error_valid) begin
            fault_source = 8'h09;
            fault_code = controller_error_code;
            fault_detail = {accelerator_frame_id, active_stage_id,
                            cache_state, controller_state, 3'd0};
        end else if (integration_error_valid) begin
            fault_source = 8'h0a;
            fault_code = integration_error_code;
            fault_detail = integration_error_detail;
        end else if (planner_error_valid) begin
            fault_source = 8'h0b;
            fault_code = planner_error_code;
            fault_detail = planner_error_detail;
        end else if (unsupported_coefficient_fault) begin
            fault_source = 8'h0c;
            fault_code = 8'h01;
            fault_detail = {accelerator_frame_id, 8'd0,
                            active_stage_id, accelerator_state};
        end else if (accelerator_error || accelerator_reset_required) begin
            fault_source = 8'h01;
            fault_code = {4'd0, accelerator_error_code};
            fault_detail = accelerator_state_cycles;
        end else begin
            fault_valid = 1'b0;
        end
    end

    accelerator_control_axil #(
        .AXI_ADDR_WIDTH(12),
        .FRAME_ID_WIDTH(FRAME_ID_WIDTH),
        .USE_PL_LAYERNORM(USE_PL_LAYERNORM),
        .IMAGE_VERSION(IMAGE_VERSION)
    ) u_control (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axi_awaddr(s_axi_control_awaddr),
        .s_axi_awprot(s_axi_control_awprot),
        .s_axi_awvalid(s_axi_control_awvalid),
        .s_axi_awready(s_axi_control_awready),
        .s_axi_wdata(s_axi_control_wdata),
        .s_axi_wstrb(s_axi_control_wstrb),
        .s_axi_wvalid(s_axi_control_wvalid),
        .s_axi_wready(s_axi_control_wready),
        .s_axi_bresp(s_axi_control_bresp),
        .s_axi_bvalid(s_axi_control_bvalid),
        .s_axi_bready(s_axi_control_bready),
        .s_axi_araddr(s_axi_control_araddr),
        .s_axi_arprot(s_axi_control_arprot),
        .s_axi_arvalid(s_axi_control_arvalid),
        .s_axi_arready(s_axi_control_arready),
        .s_axi_rdata(s_axi_control_rdata),
        .s_axi_rresp(s_axi_control_rresp),
        .s_axi_rvalid(s_axi_control_rvalid),
        .s_axi_rready(s_axi_control_rready),
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
        .start_valid(accelerator_start),
        .abort_pulse(accelerator_abort),
        .clear_error_pulse(accelerator_clear_error),
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
        .irq(accelerator_irq),
        .debug_status(control_debug_unused)
    );

    accelerator_profiling_counters #(
        .FRAME_ID_WIDTH(FRAME_ID_WIDTH),
        .AXI_DATA_BYTES(AXI_DATA_WIDTH / 8)
    ) u_profiling (
        .clk(aclk),
        .rst_n(aresetn),
        .enable(profiling_enable),
        .clear_pulse(profiling_clear_pulse),
        .snapshot_pulse(profiling_snapshot_pulse),
        .read_index(profiling_read_index),
        .read_data(profiling_read_data),
        .snapshot_valid(profiling_snapshot_valid),
        .frame_active(profiling_frame_active),
        .snapshot_busy(profiling_snapshot_busy),
        .accelerator_reset_active(accelerator_reset_active),
        .frame_start(accelerator_start && accelerator_start_ready),
        .frame_done(accelerator_done),
        .frame_error(accelerator_error || accelerator_reset_required),
        .sparse_mode(accelerator_sparse_mode),
        .frame_id(accelerator_frame_id),
        .global_state(accelerator_state),
        .active_stage_id(active_stage_id),
        .controller_state(controller_state),
        .compute_owner(compute_owner),
        .parameter_arvalid(m_axi_parameter_arvalid),
        .parameter_arready(m_axi_parameter_arready),
        .parameter_arlen(m_axi_parameter_arlen),
        .parameter_rvalid(m_axi_parameter_rvalid),
        .parameter_rready(m_axi_parameter_rready),
        .parameter_rlast(m_axi_parameter_rlast),
        .fb_axis_tvalid(s_axis_fb_tvalid),
        .fb_axis_tready(s_axis_fb_tready),
        .fb_axis_tlast(s_axis_fb_tlast),
        .spectrum_axis_tvalid(s_axis_spectrum_tvalid),
        .spectrum_axis_tready(s_axis_spectrum_tready),
        .spectrum_axis_tlast(s_axis_spectrum_tlast),
        .output_axis_tvalid(m_axis_output_tvalid),
        .output_axis_tready(m_axis_output_tready),
        .output_axis_tlast(m_axis_output_tlast),
        .fb_release_valid(ps_fb_release_valid),
        .fb_release_ready(ps_fb_release_ready),
        .sb_claim_valid(ps_sb_claim_valid),
        .sb_claim_ready(ps_sb_claim_ready),
        .sb_commit_valid(ps_sb_commit_valid),
        .sb_commit_ready(ps_sb_commit_ready),
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

    accelerator_top #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .FRAME_ID_WIDTH(FRAME_ID_WIDTH),
        .USE_PL_LAYERNORM(USE_PL_LAYERNORM)
    ) u_accelerator (
        .clk(aclk),
        .rst_n(accelerator_aresetn),
        .start(accelerator_start),
        .abort(accelerator_abort),
        .clear_error(accelerator_clear_error),
        .quiesce_request(reset_quiesce_request),
        .clear_state_on_start(clear_state_on_start),
        .sparse_load_enable(sparse_load_enable),
        .parameter_base_addr(parameter_base_addr),
        .start_ready(accelerator_start_ready),
        .s_axis_fb_tvalid(s_axis_fb_tvalid),
        .s_axis_fb_tready(s_axis_fb_tready),
        .s_axis_fb_tdata(s_axis_fb_tdata),
        .s_axis_fb_tkeep(s_axis_fb_tkeep),
        .s_axis_fb_tlast(s_axis_fb_tlast),
        .s_axis_spectrum_tvalid(s_axis_spectrum_tvalid),
        .s_axis_spectrum_tready(s_axis_spectrum_tready),
        .s_axis_spectrum_tdata(s_axis_spectrum_tdata),
        .s_axis_spectrum_tkeep(s_axis_spectrum_tkeep),
        .s_axis_spectrum_tlast(s_axis_spectrum_tlast),
        .m_axis_output_tvalid(m_axis_output_tvalid),
        .m_axis_output_tready(m_axis_output_tready),
        .m_axis_output_tdata(m_axis_output_tdata),
        .m_axis_output_tkeep(m_axis_output_tkeep),
        .m_axis_output_tlast(m_axis_output_tlast),
        .ps_bram_en(mailbox_bram_en),
        .ps_bram_we(mailbox_bram_we),
        .ps_bram_addr(mailbox_bram_addr[11:2]),
        .ps_bram_wdata(mailbox_bram_wdata),
        .ps_bram_rdata(mailbox_bram_rdata),
        .ps_bram_rvalid(mailbox_bram_rvalid_unused),
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
        .m_axi_araddr(m_axi_parameter_araddr),
        .m_axi_arid(m_axi_parameter_arid),
        .m_axi_arlen(m_axi_parameter_arlen),
        .m_axi_arsize(m_axi_parameter_arsize),
        .m_axi_arburst(m_axi_parameter_arburst),
        .m_axi_arprot(m_axi_parameter_arprot),
        .m_axi_arcache(m_axi_parameter_arcache),
        .m_axi_arqos(m_axi_parameter_arqos),
        .m_axi_arlock(m_axi_parameter_arlock),
        .m_axi_arvalid(m_axi_parameter_arvalid),
        .m_axi_arready(m_axi_parameter_arready),
        .m_axi_rdata(m_axi_parameter_rdata),
        .m_axi_rid(m_axi_parameter_rid),
        .m_axi_rresp(m_axi_parameter_rresp),
        .m_axi_rlast(m_axi_parameter_rlast),
        .m_axi_rvalid(m_axi_parameter_rvalid),
        .m_axi_rready(m_axi_parameter_rready),
        .busy(accelerator_busy),
        .done(accelerator_done),
        .error(accelerator_error),
        .error_code(accelerator_error_code),
        .state_debug(accelerator_state),
        .state_cycle_count(accelerator_state_cycles),
        .pe_active_debug(),
        .pe_done_pending_debug(),
        .reset_required(accelerator_reset_required),
        .soft_reset_safe(accelerator_soft_reset_safe),
        .sparse_mode_active(accelerator_sparse_mode),
        .current_frame_id(accelerator_frame_id),
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
        .adapter_fb_publish_complete(),
        .adapter_sb_buffer_valid(),
        .adapter_error_valid(adapter_error_valid),
        .adapter_error_code(adapter_error_code),
        .adapter_error_detail(adapter_error_detail),
        .feature_dispatcher_busy(),
        .fb_input_buffer_valid(fb_input_buffer_valid),
        .fb_input_buffer_frame_id(fb_input_buffer_frame_id),
        .feature_dispatcher_error_valid(feature_error_valid),
        .feature_dispatcher_error_code(feature_error_code),
        .feature_dispatcher_error_detail(feature_error_detail),
        .df_coefficient_context_valid(),
        .df_coefficients_valid(),
        .df_coefficient_store_busy(),
        .df_coefficient_store_error_valid(coefficient_error_valid),
        .df_coefficient_store_error_code(coefficient_error_code),
        .df_coefficient_store_error_detail(coefficient_error_detail),
        .spectrum_input_buffer_valid(spectrum_input_buffer_valid),
        .spectrum_input_buffer_frame_id(spectrum_input_buffer_frame_id),
        .df_engine_busy(),
        .df_engine_active_bin(),
        .df_history_depth(),
        .df_engine_error_valid(df_error_valid),
        .df_engine_error_code(df_error_code),
        .df_engine_error_detail(df_error_detail),
        .unsupported_coefficient_fault(unsupported_coefficient_fault),
        .pe_barrier_idle(),
        .pe_fault(),
        .active_stage_id(active_stage_id),
        .cache_state(cache_state),
        .compute_owner(compute_owner),
        .lut_adapter_state(),
        .lut_accepted_bytes(),
        .lut_configuration_starts(),
        .controller_state(controller_state),
        .controller_row_tile(),
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
        .integration_error_detail(integration_error_detail),
        .sparse_context_port_owner(),
        .sparse_planner_error_valid(planner_error_valid),
        .sparse_planner_error_code(planner_error_code),
        .sparse_planner_error_detail(planner_error_detail),
        .sparse_stage_diag_valid(sparse_stage_diag_valid),
        .sparse_stage_diag_success(sparse_stage_diag_success),
        .sparse_stage_diag_stage_id(sparse_stage_diag_stage_id),
        .sparse_stage_diag_enabled(sparse_stage_diag_enabled),
        .sparse_stage_diag_fallback_full(sparse_stage_diag_fallback_full),
        .sparse_stage_dense_reference_bytes(),
        .sparse_stage_planned_bytes(),
        .sparse_stage_actual_bytes(sparse_stage_actual_bytes),
        .sparse_stage_saved_bytes(sparse_stage_saved_bytes),
        .sparse_stage_union_count0(),
        .sparse_stage_union_count1(),
        .sparse_stage_copy_command_count(),
        .sparse_stage_ar_burst_count(sparse_stage_ar_burst_count),
        .sparse_stage_load_cycles(sparse_stage_load_cycles),
        .sparse_epoch_lut_actual_bytes()
    );
endmodule
