`timescale 1ns/1ps

// Minimal single-clock parameter-BRAM bring-up integration boundary.
// memory_service contains the 256 KiB (64 RAMB36-equivalent) cache; this top
// intentionally adds no mailbox, AXI DMA, PE, or model-control FSM.
module parameter_bram_bringup_top #(
    parameter integer AXI_ADDR_WIDTH      = 32,
    parameter integer AXI_DATA_WIDTH      = 64,
    // Zynq-7000 S_AXI_HP0 exposes six ID bits.  The service still emits only
    // ID zero, but matching the physical width avoids lossy BD adaptation.
    parameter integer AXI_ID_WIDTH        = 6,
    parameter integer LOAD_TIMEOUT_CYCLES = 100000
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aclk, ASSOCIATED_BUSIF S_AXI:M_AXI, ASSOCIATED_RESET aresetn, FREQ_HZ 100000000" *)
    input  wire                         aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aresetn, POLARITY ACTIVE_LOW" *)
    input  wire                         aresetn,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI, PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 12, FREQ_HZ 100000000, READ_WRITE_MODE READ_WRITE" *)
    input  wire [11:0]                  s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *)
    input  wire [2:0]                   s_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input  wire                         s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output wire                         s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input  wire [31:0]                  s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input  wire [3:0]                   s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input  wire                         s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output wire                         s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output wire [1:0]                   s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output wire                         s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input  wire                         s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input  wire [11:0]                  s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *)
    input  wire [2:0]                   s_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input  wire                         s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output wire                         s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output wire [31:0]                  s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output wire [1:0]                   s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output wire                         s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input  wire                         s_axi_rready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARADDR" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXI, PROTOCOL AXI4, DATA_WIDTH 64, ADDR_WIDTH 32, ID_WIDTH 6, MAX_BURST_LENGTH 16, NUM_READ_OUTSTANDING 1, READ_WRITE_MODE READ_ONLY, FREQ_HZ 100000000" *)
    output wire [AXI_ADDR_WIDTH-1:0]    m_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARID" *)
    output wire [AXI_ID_WIDTH-1:0]      m_axi_arid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARLEN" *)
    output wire [7:0]                   m_axi_arlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARSIZE" *)
    output wire [2:0]                   m_axi_arsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARBURST" *)
    output wire [1:0]                   m_axi_arburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARPROT" *)
    output wire [2:0]                   m_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARCACHE" *)
    output wire [3:0]                   m_axi_arcache,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARQOS" *)
    output wire [3:0]                   m_axi_arqos,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARLOCK" *)
    output wire                         m_axi_arlock,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARVALID" *)
    output wire                         m_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARREADY" *)
    input  wire                         m_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RDATA" *)
    input  wire [AXI_DATA_WIDTH-1:0]    m_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RID" *)
    input  wire [AXI_ID_WIDTH-1:0]      m_axi_rid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RRESP" *)
    input  wire [1:0]                   m_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RLAST" *)
    input  wire                         m_axi_rlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RVALID" *)
    input  wire                         m_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RREADY" *)
    output wire                         m_axi_rready,

    // Deliberately compact ILA probe groups.  Software-visible detail remains
    // available through the AXI-Lite register file.
    output wire [31:0]                  dbg_status,
    output wire [63:0]                  dbg_error,
    output wire [127:0]                 dbg_counters,
    output wire [41:0]                  dbg_axi_ar,
    output wire [68:0]                  dbg_axi_r
);
    wire [31:0] parameter_base_addr;
    wire [31:0] image_version;
    wire stage_req_valid;
    wire stage_req_ready;
    wire [3:0] stage_req_id;
    wire stage_load_done;
    wire stage_load_error;
    wire stage_ready_for_compute;
    wire lut_ready;
    wire stage_release_valid;
    wire stage_release_ready;
    wire [3:0] stage_release_id;
    wire abort_pulse;
    wire clear_error_pulse;
    wire [2:0] cache_state;
    wire [3:0] active_stage_id;
    wire [31:0] active_image_version;
    wire service_error_valid;
    wire [7:0] service_error_code;
    wire [3:0] service_error_stage;
    wire [31:0] service_error_detail;
    wire raw_loader_busy;
    wire raw_loader_done;
    wire raw_loader_error;
    wire raw_loader_timeout;
    wire raw_loader_abort_drain;

    wire weight_req_valid;
    wire weight_req_ready;
    wire weight_req_matrix;
    wire [9:0] weight_req_source;
    wire [5:0] weight_req_row_tile;
    wire [7:0] weight_req_tag;
    wire weight_rsp_valid;
    wire weight_rsp_ready;
    wire [127:0] weight_rsp_data;
    wire [7:0] weight_rsp_tag;
    wire weight_rsp_error;

    wire param_req_ready_unused;
    wire param_rsp_valid_unused;
    wire [5791:0] param_rsp_data_unused;
    wire param_rsp_kind_unused;
    wire [12:0] param_rsp_bits_unused;
    wire [7:0] param_rsp_tag_unused;
    wire param_rsp_error_unused;

    wire lut_cfg_valid;
    wire [3:0] lut_cfg_stage_id_unused;
    wire [7:0] lut_cfg_addr_unused;
    wire [7:0] lut_cfg_data_unused;

    wire [31:0] load_cycle_counter;
    wire [31:0] ar_burst_counter;
    wire [31:0] r_beat_counter;
    wire [31:0] lut_byte_counter;
    wire wrapper_error_valid;
    wire [7:0] wrapper_error_code;
    wire [31:0] wrapper_error_detail;
    wire [31:0] debug_weight_status_unused;

    wire monitor_ar_fire  = m_axi_arvalid && m_axi_arready;
    wire monitor_r_fire   = m_axi_rvalid && m_axi_rready;
    wire monitor_lut_fire = lut_cfg_valid;

    assign dbg_error = {
        10'b0,
        wrapper_error_valid,
        wrapper_error_code,
        service_error_valid,
        service_error_stage,
        service_error_code,
        service_error_detail
    };
    assign dbg_counters = {
        lut_byte_counter, r_beat_counter,
        ar_burst_counter, load_cycle_counter
    };
    assign dbg_axi_ar = {
        m_axi_arvalid, m_axi_arready, m_axi_arlen, m_axi_araddr
    };
    assign dbg_axi_r = {
        m_axi_rvalid, m_axi_rready, m_axi_rlast, m_axi_rresp, m_axi_rdata
    };

    memory_service_axil control (
        .clk(aclk),
        .rst_n(aresetn),
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
        .parameter_base_addr(parameter_base_addr),
        .image_version(image_version),
        .stage_req_valid(stage_req_valid),
        .stage_req_ready(stage_req_ready),
        .stage_req_id(stage_req_id),
        .stage_load_done(stage_load_done),
        .stage_load_error(stage_load_error),
        .stage_ready_for_compute(stage_ready_for_compute),
        .lut_ready(lut_ready),
        .stage_release_valid(stage_release_valid),
        .stage_release_ready(stage_release_ready),
        .stage_release_id(stage_release_id),
        .abort_pulse(abort_pulse),
        .clear_error_pulse(clear_error_pulse),
        .cache_state(cache_state),
        .active_stage_id(active_stage_id),
        .active_image_version(active_image_version),
        .service_error_valid(service_error_valid),
        .service_error_code(service_error_code),
        .service_error_stage(service_error_stage),
        .service_error_detail(service_error_detail),
        .raw_loader_busy(raw_loader_busy),
        .raw_loader_done(raw_loader_done),
        .raw_loader_error(raw_loader_error),
        .raw_loader_timeout(raw_loader_timeout),
        .raw_loader_abort_drain(raw_loader_abort_drain),
        .weight_req_valid(weight_req_valid),
        .weight_req_ready(weight_req_ready),
        .weight_req_matrix(weight_req_matrix),
        .weight_req_source(weight_req_source),
        .weight_req_row_tile(weight_req_row_tile),
        .weight_req_tag(weight_req_tag),
        .weight_rsp_valid(weight_rsp_valid),
        .weight_rsp_ready(weight_rsp_ready),
        .weight_rsp_data(weight_rsp_data),
        .weight_rsp_tag(weight_rsp_tag),
        .weight_rsp_error(weight_rsp_error),
        .monitor_ar_fire(monitor_ar_fire),
        .monitor_r_fire(monitor_r_fire),
        .monitor_lut_fire(monitor_lut_fire),
        .load_cycle_counter(load_cycle_counter),
        .ar_burst_counter(ar_burst_counter),
        .r_beat_counter(r_beat_counter),
        .lut_byte_counter(lut_byte_counter),
        .wrapper_error_valid(wrapper_error_valid),
        .wrapper_error_code(wrapper_error_code),
        .wrapper_error_detail(wrapper_error_detail),
        .debug_status(dbg_status),
        .debug_weight_status(debug_weight_status_unused)
    );

    memory_service #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .CACHE_ADDR_WIDTH(15),
        .MAX_BURST_BEATS(16),
        .LOAD_TIMEOUT_CYCLES(LOAD_TIMEOUT_CYCLES),
        .TAG_WIDTH(8)
    ) service (
        .clk(aclk),
        .rst_n(aresetn),
        .abort(abort_pulse),
        .clear_error(clear_error_pulse),
        .parameter_base_addr(parameter_base_addr),
        .image_version(image_version),
        .stage_req_valid(stage_req_valid),
        .stage_req_ready(stage_req_ready),
        .stage_req_id(stage_req_id),
        .stage_load_done(stage_load_done),
        .stage_load_error(stage_load_error),
        .stage_ready_for_compute(stage_ready_for_compute),
        .lut_ready(lut_ready),
        .stage_release_valid(stage_release_valid),
        .stage_release_ready(stage_release_ready),
        .stage_release_id(stage_release_id),
        .cache_state(cache_state),
        .active_stage_id(active_stage_id),
        .active_image_version(active_image_version),
        .error_valid(service_error_valid),
        .error_code(service_error_code),
        .error_stage(service_error_stage),
        .error_detail(service_error_detail),
        .raw_loader_busy(raw_loader_busy),
        .raw_loader_done(raw_loader_done),
        .raw_loader_error(raw_loader_error),
        .raw_loader_timeout(raw_loader_timeout),
        .raw_loader_abort_drain(raw_loader_abort_drain),
        .weight_req_valid(weight_req_valid),
        .weight_req_ready(weight_req_ready),
        .weight_req_matrix(weight_req_matrix),
        .weight_req_source(weight_req_source),
        .weight_req_row_tile(weight_req_row_tile),
        .weight_req_tag(weight_req_tag),
        .weight_rsp_valid(weight_rsp_valid),
        .weight_rsp_ready(weight_rsp_ready),
        .weight_rsp_data(weight_rsp_data),
        .weight_rsp_tag(weight_rsp_tag),
        .weight_rsp_error(weight_rsp_error),
        .param_req_valid(1'b0),
        .param_req_ready(param_req_ready_unused),
        .param_req_row_tile(6'b0),
        .param_req_tag(8'b0),
        .param_rsp_valid(param_rsp_valid_unused),
        .param_rsp_ready(1'b1),
        .param_rsp_data(param_rsp_data_unused),
        .param_rsp_kind(param_rsp_kind_unused),
        .param_rsp_bits(param_rsp_bits_unused),
        .param_rsp_tag(param_rsp_tag_unused),
        .param_rsp_error(param_rsp_error_unused),
        .lut_cfg_valid(lut_cfg_valid),
        .lut_cfg_ready(1'b1),
        .lut_cfg_stage_id(lut_cfg_stage_id_unused),
        .lut_cfg_addr(lut_cfg_addr_unused),
        .lut_cfg_data(lut_cfg_data_unused),
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
        .m_axi_rready(m_axi_rready)
    );
endmodule
