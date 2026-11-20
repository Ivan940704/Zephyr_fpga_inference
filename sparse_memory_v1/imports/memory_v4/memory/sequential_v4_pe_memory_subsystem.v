`timescale 1ns/1ps
`include "memory/model_memory_v4_map.vh"

// Connected sequential-v4 parameter-memory and frozen-PE subsystem.
//
// The global FSM owns stage loading and job launch.  One unchanged memory.v
// cache holds a complete stage; active lists suppress only cache reads and PE
// MAC commands.  All severe errors require coordinated reset.
module sequential_v4_pe_memory_subsystem #(
    parameter integer AXI_ADDR_WIDTH = 32,
    parameter integer AXI_DATA_WIDTH = 64,
    parameter integer AXI_ID_WIDTH = 1,
    parameter integer LOAD_TIMEOUT_CYCLES = 100000,
    parameter integer CONTROLLER_TIMEOUT_CYCLES = 1000000,
    parameter integer LUT_STALL_TIMEOUT_CYCLES = 100000
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         abort,
    input  wire                         clear_error,
    input  wire                         clear_state,
    input  wire [AXI_ADDR_WIDTH-1:0]    parameter_base_addr,

    // Existing global-FSM stage-load boundary.
    input  wire                         stage_req_valid,
    output wire                         stage_req_ready,
    input  wire [3:0]                   stage_id,
    input  wire [1:0]                   stage_bank,
    output wire                         stage_load_done,
    output wire                         stage_load_error,

    // Existing fullband and shared-subband job boundaries.
    input  wire                         fb_start,
    output wire                         fb_start_ready,
    input  wire [1:0]                   fb_stage,
    output wire                         fb_done,
    output wire                         fb_error,

    input  wire [2:0]                   sb_start,
    output wire                         sb_start_ready,
    input  wire [1:0]                   sb_stage,
    input  wire [1:0]                   sb_shared_branch,
    input  wire [1:0]                   sb_context_0,
    input  wire [1:0]                   sb_context_1,
    input  wire [1:0]                   sb_context_2,
    output wire [2:0]                   sb_done,
    output wire [2:0]                   sb_error,

    // External dense-feature scalar provider.
    output wire                         feature_req_valid,
    input  wire                         feature_req_ready,
    output wire [3:0]                   feature_req_stage_id,
    output wire [1:0]                   feature_req_branch,
    output wire [1:0]                   feature_req_context,
    output wire [9:0]                   feature_req_source,
    output wire [7:0]                   feature_req_tag,
    input  wire                         feature_rsp_valid,
    output wire                         feature_rsp_ready,
    input  wire signed [7:0]            feature_rsp_value,
    input  wire [7:0]                   feature_rsp_tag,
    input  wire                         feature_rsp_error,

    // Projection coefficient output remains external; no CDF store exists.
    output wire                         coefficient_valid,
    input  wire                         coefficient_ready,
    output wire signed [7:0]            coefficient_value,
    output wire [8:0]                   coefficient_index,
    output wire [15:0]                  coefficient_tag,
    output wire                         coefficient_last,

    // Read-only AXI master from unchanged memory.v.
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

    // Global-FSM lifecycle and focused integration diagnostics.
    output wire [2:0]                   pe_barrier_idle,
    output wire [2:0]                   pe_fault,
    output wire                         reset_required,
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
    output reg                          integration_error_valid,
    output reg  [7:0]                   integration_error_code,
    output reg  [31:0]                  integration_error_detail
);
    localparam [2:0] LUT_IDLE      = 3'd0;
    localparam [2:0] LUT_START     = 3'd1;
    localparam [2:0] LUT_DATA      = 3'd2;
    localparam [2:0] LUT_WAIT_DONE = 3'd3;
    localparam [2:0] LUT_READY     = 3'd4;
    localparam [2:0] LUT_ERROR     = 3'd7;

    localparam [7:0] INT_ERR_NONE       = 8'h00;
    localparam [7:0] INT_ERR_STAGE_BANK = 8'h01;
    localparam [7:0] INT_ERR_JOB_VECTOR = 8'h02;
    localparam [7:0] INT_ERR_LUT_ORDER  = 8'h03;
    localparam [7:0] INT_ERR_LUT_DONE   = 8'h04;
    localparam [7:0] INT_ERR_LUT_TIMEOUT= 8'h05;

    // ------------------------------------------------------------------
    // memory_service wires.
    // ------------------------------------------------------------------
    wire service_stage_req_valid;
    wire service_stage_req_ready;
    wire service_stage_load_done;
    wire service_stage_load_error;
    wire service_stage_ready;
    wire service_lut_ready;
    wire service_stage_kind;
    wire [1:0] service_matrix_count;
    wire [9:0] service_matrix0_sources;
    wire [5:0] service_matrix0_row_tiles;
    wire [9:0] service_matrix1_sources;
    wire [5:0] service_matrix1_row_tiles;
    wire [5:0] service_param_tiles;
    wire service_uses_sigmoid;
    wire [2:0] service_sigmoid_select;
    wire [31:0] service_active_image_version;
    wire [3:0] service_error_stage;
    wire [31:0] service_error_detail;
    wire service_raw_loader_busy;
    wire service_raw_loader_done;
    wire service_raw_loader_error;
    wire service_raw_loader_timeout;
    wire service_raw_abort_drain;

    wire controller_stage_release_valid;
    wire controller_stage_release_ready;
    wire [3:0] controller_stage_release_id;
    wire controller_weight_req_valid;
    wire controller_weight_req_ready;
    wire controller_weight_req_matrix;
    wire [9:0] controller_weight_req_source;
    wire [5:0] controller_weight_req_row_tile;
    wire [7:0] controller_weight_req_tag;
    wire controller_weight_rsp_valid;
    wire controller_weight_rsp_ready;
    wire [127:0] controller_weight_rsp_data;
    wire [7:0] controller_weight_rsp_tag;
    wire controller_weight_rsp_error;
    wire controller_param_req_valid;
    wire controller_param_req_ready;
    wire [5:0] controller_param_req_row_tile;
    wire [7:0] controller_param_req_tag;
    wire controller_param_rsp_valid;
    wire controller_param_rsp_ready;
    wire [5791:0] controller_param_rsp_data;
    wire controller_param_rsp_kind;
    wire [12:0] controller_param_rsp_bits;
    wire [7:0] controller_param_rsp_tag;
    wire controller_param_rsp_error;

    wire service_lut_cfg_valid;
    wire service_lut_cfg_ready;
    wire [3:0] service_lut_cfg_stage_id;
    wire [7:0] service_lut_cfg_addr;
    wire [7:0] service_lut_cfg_data;

    wire pe_overflow_any;
    wire pe_protocol_error;
    wire service_abort = abort || integration_error_valid ||
        controller_error_valid || context_error_valid ||
        pe_overflow_any || pe_protocol_error;

    wire invalid_stage_event;
    reg invalid_stage_pulse_q;
    assign stage_req_ready = rst_n && !reset_required &&
                             service_stage_req_ready;
    assign invalid_stage_event = stage_req_valid && stage_req_ready &&
                                 (stage_bank != 2'd0);
    assign service_stage_req_valid = stage_req_valid &&
        (stage_bank == 2'd0) && !reset_required;
    assign stage_load_done = service_stage_load_done || invalid_stage_pulse_q;
    assign stage_load_error = service_stage_load_error ||
                              invalid_stage_pulse_q;

    memory_service #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .LOAD_TIMEOUT_CYCLES(LOAD_TIMEOUT_CYCLES)
    ) u_memory_service (
        .clk(clk),
        .rst_n(rst_n),
        .abort(service_abort),
        .clear_error(clear_error),
        .parameter_base_addr(parameter_base_addr),
        .image_version(`MODEL_V4_IMAGE_VERSION),
        .stage_req_valid(service_stage_req_valid),
        .stage_req_ready(service_stage_req_ready),
        .stage_req_id(stage_id),
        .stage_load_done(service_stage_load_done),
        .stage_load_error(service_stage_load_error),
        .stage_ready_for_compute(service_stage_ready),
        .lut_ready(service_lut_ready),
        .stage_release_valid(controller_stage_release_valid),
        .stage_release_ready(controller_stage_release_ready),
        .stage_release_id(controller_stage_release_id),
        .cache_state(cache_state),
        .active_stage_id(active_stage_id),
        .active_image_version(service_active_image_version),
        .active_stage_kind(service_stage_kind),
        .active_matrix_count(service_matrix_count),
        .active_matrix0_sources(service_matrix0_sources),
        .active_matrix0_row_tiles(service_matrix0_row_tiles),
        .active_matrix1_sources(service_matrix1_sources),
        .active_matrix1_row_tiles(service_matrix1_row_tiles),
        .active_param_tiles(service_param_tiles),
        .active_uses_sigmoid_table(service_uses_sigmoid),
        .active_sigmoid_table_select(service_sigmoid_select),
        .error_valid(memory_error_valid),
        .error_code(memory_error_code),
        .error_stage(service_error_stage),
        .error_detail(service_error_detail),
        .raw_loader_busy(service_raw_loader_busy),
        .raw_loader_done(service_raw_loader_done),
        .raw_loader_error(service_raw_loader_error),
        .raw_loader_timeout(service_raw_loader_timeout),
        .raw_loader_abort_drain(service_raw_abort_drain),
        .weight_req_valid(controller_weight_req_valid),
        .weight_req_ready(controller_weight_req_ready),
        .weight_req_matrix(controller_weight_req_matrix),
        .weight_req_source(controller_weight_req_source),
        .weight_req_row_tile(controller_weight_req_row_tile),
        .weight_req_tag(controller_weight_req_tag),
        .weight_rsp_valid(controller_weight_rsp_valid),
        .weight_rsp_ready(controller_weight_rsp_ready),
        .weight_rsp_data(controller_weight_rsp_data),
        .weight_rsp_tag(controller_weight_rsp_tag),
        .weight_rsp_error(controller_weight_rsp_error),
        .param_req_valid(controller_param_req_valid),
        .param_req_ready(controller_param_req_ready),
        .param_req_row_tile(controller_param_req_row_tile),
        .param_req_tag(controller_param_req_tag),
        .param_rsp_valid(controller_param_rsp_valid),
        .param_rsp_ready(controller_param_rsp_ready),
        .param_rsp_data(controller_param_rsp_data),
        .param_rsp_kind(controller_param_rsp_kind),
        .param_rsp_bits(controller_param_rsp_bits),
        .param_rsp_tag(controller_param_rsp_tag),
        .param_rsp_error(controller_param_rsp_error),
        .lut_cfg_valid(service_lut_cfg_valid),
        .lut_cfg_ready(service_lut_cfg_ready),
        .lut_cfg_stage_id(service_lut_cfg_stage_id),
        .lut_cfg_addr(service_lut_cfg_addr),
        .lut_cfg_data(service_lut_cfg_data),
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

    // ------------------------------------------------------------------
    // Context-store wires and instance.
    // ------------------------------------------------------------------
    wire context_producer_open_valid;
    wire context_producer_open_ready;
    wire [4:0] context_producer_open_id;
    wire [5:0] context_producer_open_rows;
    wire context_list_desc_req_valid;
    wire context_list_desc_req_ready;
    wire [4:0] context_list_desc_req_id;
    wire [7:0] context_list_desc_req_tag;
    wire context_list_desc_rsp_valid;
    wire context_list_desc_rsp_ready;
    wire [8:0] context_list_desc_rsp_count;
    wire [7:0] context_list_desc_rsp_tag;
    wire context_list_desc_rsp_error;
    wire context_list_read_req_valid;
    wire context_list_read_req_ready;
    wire [4:0] context_list_read_req_id;
    wire [8:0] context_list_read_req_ordinal;
    wire [7:0] context_list_read_req_tag;
    wire context_list_read_rsp_valid;
    wire context_list_read_rsp_ready;
    wire [8:0] context_list_read_rsp_index;
    wire [7:0] context_list_read_rsp_tag;
    wire context_list_read_rsp_error;
    wire context_state_read_req_valid;
    wire context_state_read_req_ready;
    wire [4:0] context_state_read_req_id;
    wire [4:0] context_state_read_req_tile;
    wire [7:0] context_state_read_req_tag;
    wire context_state_read_rsp_valid;
    wire context_state_read_rsp_ready;
    wire [127:0] context_state_read_rsp_data;
    wire [7:0] context_state_read_rsp_tag;
    wire context_state_read_rsp_error;
    wire pe_state_write_valid;
    wire pe_state_write_ready;
    wire signed [7:0] pe_state_write_value;
    wire [8:0] pe_state_write_index;
    wire [15:0] pe_state_write_tag;
    wire pe_state_write_last;
    wire pe_active_cmd_valid;
    wire pe_active_cmd_ready;
    wire pe_active_cmd_write;
    wire [8:0] pe_active_cmd_index;
    wire [15:0] pe_active_cmd_tag;
    wire pe_active_cmd_finalize;
    wire context_commit_valid;
    wire context_commit_ready;
    wire [4:0] context_commit_id;
    wire context_commit_barrier;
    wire context_commit_done;
    wire context_producer_busy;
    wire [4:0] context_producer_id;
    wire [5:0] context_producer_rows;
    wire [8:0] context_producer_list_count;
    wire [31:0] context_error_detail;
    wire context_reset_required;
    // Registered copy of the controller's complete handshake-derived PE
    // barrier.  ST_TILE_DRAIN observes the live barrier before entering the
    // commit states, so this is a proof-retiming cut, not a latency guess.
    // The controller checks the live barrier again when commit_done returns.
    reg context_commit_barrier_q;
    // The controller establishes the selected list identity before entering
    // ST_LIST_REQ.  Sampling that stable identity here removes a long
    // cross-module list-address/error path without buffering the request or
    // changing its valid/ready handshake.
    (* keep = "true" *) reg [4:0] context_list_read_req_id_q;

    sequential_recurrent_context_store u_context_store (
        .clk(clk),
        .rst_n(rst_n),
        .clear_state(clear_state),
        .producer_open_valid(context_producer_open_valid),
        .producer_open_ready(context_producer_open_ready),
        .producer_open_logical_id(context_producer_open_id),
        .producer_open_row_tiles(context_producer_open_rows),
        .list_desc_req_valid(context_list_desc_req_valid),
        .list_desc_req_ready(context_list_desc_req_ready),
        .list_desc_req_logical_id(context_list_desc_req_id),
        .list_desc_req_tag(context_list_desc_req_tag),
        .list_desc_rsp_valid(context_list_desc_rsp_valid),
        .list_desc_rsp_ready(context_list_desc_rsp_ready),
        .list_desc_rsp_count(context_list_desc_rsp_count),
        .list_desc_rsp_tag(context_list_desc_rsp_tag),
        .list_desc_rsp_error(context_list_desc_rsp_error),
        .list_read_req_valid(context_list_read_req_valid),
        .list_read_req_ready(context_list_read_req_ready),
        .list_read_req_logical_id(context_list_read_req_id_q),
        .list_read_req_ordinal(context_list_read_req_ordinal),
        .list_read_req_tag(context_list_read_req_tag),
        .list_read_rsp_valid(context_list_read_rsp_valid),
        .list_read_rsp_ready(context_list_read_rsp_ready),
        .list_read_rsp_index(context_list_read_rsp_index),
        .list_read_rsp_tag(context_list_read_rsp_tag),
        .list_read_rsp_error(context_list_read_rsp_error),
        .state_read_req_valid(context_state_read_req_valid),
        .state_read_req_ready(context_state_read_req_ready),
        .state_read_req_logical_id(context_state_read_req_id),
        .state_read_req_row_tile(context_state_read_req_tile),
        .state_read_req_tag(context_state_read_req_tag),
        .state_read_rsp_valid(context_state_read_rsp_valid),
        .state_read_rsp_ready(context_state_read_rsp_ready),
        .state_read_rsp_data(context_state_read_rsp_data),
        .state_read_rsp_tag(context_state_read_rsp_tag),
        .state_read_rsp_error(context_state_read_rsp_error),
        .state_write_valid(pe_state_write_valid),
        .state_write_ready(pe_state_write_ready),
        .state_write_value(pe_state_write_value),
        .state_write_index(pe_state_write_index),
        .state_write_tag(pe_state_write_tag),
        .state_write_last(pe_state_write_last),
        .active_cmd_valid(pe_active_cmd_valid),
        .active_cmd_ready(pe_active_cmd_ready),
        .active_cmd_write(pe_active_cmd_write),
        .active_cmd_index(pe_active_cmd_index),
        .active_cmd_tag(pe_active_cmd_tag),
        .active_cmd_finalize(pe_active_cmd_finalize),
        .commit_valid(context_commit_valid),
        .commit_ready(context_commit_ready),
        .commit_logical_id(context_commit_id),
        .pe_barrier_idle(context_commit_barrier_q),
        .commit_done(context_commit_done),
        .producer_busy(context_producer_busy),
        .producer_logical_id(context_producer_id),
        .producer_row_tiles(context_producer_rows),
        .producer_list_count(context_producer_list_count),
        .error_valid(context_error_valid),
        .error_code(context_error_code),
        .error_detail(context_error_detail),
        .reset_required(context_reset_required)
    );

    // ------------------------------------------------------------------
    // Generic job mapping and controller instance.
    // ------------------------------------------------------------------
    wire any_sb_start = |sb_start;
    wire external_job_valid = fb_start || any_sb_start;
    wire legal_job_vector = !(fb_start && any_sb_start) &&
        (!any_sb_start || (sb_start == 3'b001));
    wire controller_job_ready;
    wire controller_job_valid = !reset_required && legal_job_vector &&
        ((fb_start && !any_sb_start) || (!fb_start && sb_start[0]));
    wire [3:0] mapped_sb_stage = 4'd3 +
        {1'b0, sb_shared_branch, 1'b0} +
        {2'd0, sb_shared_branch} + {2'd0, sb_stage};
    wire [3:0] controller_job_stage = fb_start
        ? {2'd0, fb_stage} : mapped_sb_stage;
    wire [1:0] controller_job_branch = fb_start
        ? 2'd0 : sb_shared_branch + 1'b1;
    wire [1:0] controller_job_context = fb_start
        ? 2'd0 : sb_context_0;
    wire external_job_fire = external_job_valid &&
                             (fb_start ? fb_start_ready : sb_start_ready);
    wire controller_job_fire = controller_job_valid && controller_job_ready;
    wire controller_job_done;
    wire controller_job_error;
    wire controller_busy;
    reg active_job_is_fb_q;

    assign fb_start_ready = rst_n && !reset_required && controller_job_ready;
    assign sb_start_ready = rst_n && !reset_required && controller_job_ready;
    assign fb_done = controller_job_done && active_job_is_fb_q;
    assign sb_done = {2'b00,
        controller_job_done && !active_job_is_fb_q};
    assign fb_error = reset_required;
    assign sb_error = {2'b00, reset_required};

    wire controller_raw_owner_request;
    wire controller_raw_owner_grant;
    wire controller_gate_owner_request;
    wire controller_gate_owner_grant;
    wire controller_compute_idle;
    wire [15:0] controller_acc_clear;
    wire [15:0] controller_acc_enable;
    wire [1:0] controller_pe_mode;
    wire [127:0] controller_operand_a;
    wire [127:0] controller_operand_b;
    wire [127:0] controller_gate_u8;
    wire [15:0] controller_spike_enable;
    wire [511:0] controller_direct_value;
    wire [511:0] pe_accumulator;
    wire [15:0] pe_overflow;
    wire controller_gate_tile_valid;
    wire controller_gate_tile_ready;
    wire [15:0] controller_gate_tile_mask;
    wire [255:0] controller_gate_tile_tags;
    wire [2:0] controller_gate_table_select;
    wire pe_gate_collect_complete;
    wire controller_gate_rq_valid;
    wire controller_gate_rq_ready;
    wire [3:0] controller_gate_rq_mask;
    wire [127:0] controller_gate_rq_value;
    wire [127:0] controller_gate_rq_multiplier;
    wire [23:0] controller_gate_rq_shift;
    wire controller_gate_rq_gate;
    wire controller_gate_rq_component;
    wire [1:0] controller_gate_rq_group;
    wire [63:0] controller_gate_rq_tags;
    wire controller_gate_bias_valid;
    wire controller_gate_bias_ready;
    wire controller_gate_bias_gate;
    wire [1:0] controller_gate_bias_group;
    wire [3:0] controller_gate_bias_mask;
    wire [127:0] controller_gate_bias_value;
    wire [63:0] controller_gate_bias_tags;
    wire pe_sigmoid_table_valid;
    wire controller_membrane_start_valid;
    wire controller_membrane_start_ready;
    wire [127:0] controller_membrane_u_prev;
    wire [511:0] controller_membrane_cx_multiplier;
    wire [95:0] controller_membrane_cx_shift;
    wire [511:0] controller_membrane_cell_multiplier;
    wire [95:0] controller_membrane_cell_shift;
    wire [8:0] controller_membrane_base;
    wire controller_membrane_last;
    wire pe_membrane_done;
    wire controller_linear_valid;
    wire controller_linear_ready;
    wire [15:0] controller_linear_mask;
    wire [8:0] controller_linear_base;
    wire [255:0] controller_linear_tags;
    wire controller_linear_last;
    wire pe_rq_query_valid;
    wire pe_rq_query_kind;
    wire [8:0] pe_rq_query_index;
    wire [15:0] pe_rq_query_tag;
    // One-entry registered query cut.  The frozen serializer holds its query
    // until the matching parameter handshake, so no retry token or FIFO is
    // required.  The deliberate bubble is acceptable for this sequential
    // baseline and keeps the PE index adder out of controller control paths.
    reg rq_query_hold_valid_q;
    reg rq_query_hold_kind_q;
    reg [8:0] rq_query_hold_index_q;
    reg [15:0] rq_query_hold_tag_q;
    wire controller_rq_param_valid;
    wire controller_rq_param_ready;
    wire controller_rq_param_kind;
    wire signed [31:0] controller_rq_multiplier;
    wire [5:0] controller_rq_shift;
    wire signed [31:0] controller_rq_bias;
    wire [8:0] controller_rq_index;
    wire [15:0] controller_rq_tag;
    wire rq_query_response_fire = controller_rq_param_valid &&
                                  controller_rq_param_ready;

    wire pe_hybrid_idle;
    wire pe_local_rq_idle;
    wire pe_postprocess_idle;
    wire pe_sigmoid_idle;
    wire pe_serializer_idle;
    wire pe_shared_rq_idle;
    wire pe_qbn_fork_idle;
    wire [4:0] pe_local_rq_outstanding;
    wire [4:0] pe_postprocess_outstanding;
    wire [4:0] pe_shared_rq_outstanding;
    wire controller_barrier_idle;
    wire [31:0] controller_error_detail;
    wire controller_reset_required;

    sequential_pe_job_controller #(
        .WAIT_TIMEOUT_CYCLES(CONTROLLER_TIMEOUT_CYCLES)
    ) u_job_controller (
        .clk(clk), .rst_n(rst_n),
        .abort(abort || integration_error_valid),
        .job_valid(controller_job_valid),
        .job_ready(controller_job_ready),
        .job_stage_id(controller_job_stage),
        .job_branch(controller_job_branch),
        .job_context(controller_job_context),
        .job_done(controller_job_done),
        .job_error(controller_job_error),
        .busy(controller_busy),
        .stage_ready_for_compute(service_stage_ready),
        .lut_ready(service_lut_ready),
        .active_stage_id(active_stage_id),
        .active_stage_kind(service_stage_kind),
        .active_matrix_count(service_matrix_count),
        .active_matrix0_sources(service_matrix0_sources),
        .active_matrix0_row_tiles(service_matrix0_row_tiles),
        .active_matrix1_sources(service_matrix1_sources),
        .active_matrix1_row_tiles(service_matrix1_row_tiles),
        .active_param_tiles(service_param_tiles),
        .active_uses_sigmoid_table(service_uses_sigmoid),
        .active_sigmoid_table_select(service_sigmoid_select),
        .memory_error_valid(memory_error_valid),
        .stage_release_valid(controller_stage_release_valid),
        .stage_release_ready(controller_stage_release_ready),
        .stage_release_id(controller_stage_release_id),
        .weight_req_valid(controller_weight_req_valid),
        .weight_req_ready(controller_weight_req_ready),
        .weight_req_matrix(controller_weight_req_matrix),
        .weight_req_source(controller_weight_req_source),
        .weight_req_row_tile(controller_weight_req_row_tile),
        .weight_req_tag(controller_weight_req_tag),
        .weight_rsp_valid(controller_weight_rsp_valid),
        .weight_rsp_ready(controller_weight_rsp_ready),
        .weight_rsp_data(controller_weight_rsp_data),
        .weight_rsp_tag(controller_weight_rsp_tag),
        .weight_rsp_error(controller_weight_rsp_error),
        .param_req_valid(controller_param_req_valid),
        .param_req_ready(controller_param_req_ready),
        .param_req_row_tile(controller_param_req_row_tile),
        .param_req_tag(controller_param_req_tag),
        .param_rsp_valid(controller_param_rsp_valid),
        .param_rsp_ready(controller_param_rsp_ready),
        .param_rsp_data(controller_param_rsp_data),
        .param_rsp_kind(controller_param_rsp_kind),
        .param_rsp_bits(controller_param_rsp_bits),
        .param_rsp_tag(controller_param_rsp_tag),
        .param_rsp_error(controller_param_rsp_error),
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
        .producer_open_valid(context_producer_open_valid),
        .producer_open_ready(context_producer_open_ready),
        .producer_open_logical_id(context_producer_open_id),
        .producer_open_row_tiles(context_producer_open_rows),
        .list_desc_req_valid(context_list_desc_req_valid),
        .list_desc_req_ready(context_list_desc_req_ready),
        .list_desc_req_logical_id(context_list_desc_req_id),
        .list_desc_req_tag(context_list_desc_req_tag),
        .list_desc_rsp_valid(context_list_desc_rsp_valid),
        .list_desc_rsp_ready(context_list_desc_rsp_ready),
        .list_desc_rsp_count(context_list_desc_rsp_count),
        .list_desc_rsp_tag(context_list_desc_rsp_tag),
        .list_desc_rsp_error(context_list_desc_rsp_error),
        .list_read_req_valid(context_list_read_req_valid),
        .list_read_req_ready(context_list_read_req_ready),
        .list_read_req_logical_id(context_list_read_req_id),
        .list_read_req_ordinal(context_list_read_req_ordinal),
        .list_read_req_tag(context_list_read_req_tag),
        .list_read_rsp_valid(context_list_read_rsp_valid),
        .list_read_rsp_ready(context_list_read_rsp_ready),
        .list_read_rsp_index(context_list_read_rsp_index),
        .list_read_rsp_tag(context_list_read_rsp_tag),
        .list_read_rsp_error(context_list_read_rsp_error),
        .state_read_req_valid(context_state_read_req_valid),
        .state_read_req_ready(context_state_read_req_ready),
        .state_read_req_logical_id(context_state_read_req_id),
        .state_read_req_row_tile(context_state_read_req_tile),
        .state_read_req_tag(context_state_read_req_tag),
        .state_read_rsp_valid(context_state_read_rsp_valid),
        .state_read_rsp_ready(context_state_read_rsp_ready),
        .state_read_rsp_data(context_state_read_rsp_data),
        .state_read_rsp_tag(context_state_read_rsp_tag),
        .state_read_rsp_error(context_state_read_rsp_error),
        .context_commit_valid(context_commit_valid),
        .context_commit_ready(context_commit_ready),
        .context_commit_logical_id(context_commit_id),
        .context_commit_pe_barrier_idle(context_commit_barrier),
        .context_commit_done(context_commit_done),
        .context_error_valid(context_error_valid),
        .raw_owner_request(controller_raw_owner_request),
        .raw_owner_grant(controller_raw_owner_grant),
        .gate_owner_request(controller_gate_owner_request),
        .gate_owner_grant(controller_gate_owner_grant),
        .compute_owner(compute_owner),
        .compute_idle(controller_compute_idle),
        .ctrl_pe_acc_clear(controller_acc_clear),
        .ctrl_pe_acc_enable(controller_acc_enable),
        .ctrl_pe_mode(controller_pe_mode),
        .ctrl_pe_operand_a(controller_operand_a),
        .ctrl_pe_operand_b(controller_operand_b),
        .ctrl_pe_gate_u8(controller_gate_u8),
        .ctrl_pe_spike_enable(controller_spike_enable),
        .ctrl_pe_direct_value(controller_direct_value),
        .pe_accumulator(pe_accumulator),
        .pe_overflow(pe_overflow),
        .gate_tile_valid(controller_gate_tile_valid),
        .gate_tile_ready(controller_gate_tile_ready),
        .gate_tile_lane_valid(controller_gate_tile_mask),
        .gate_tile_tags(controller_gate_tile_tags),
        .gate_tile_table_select(controller_gate_table_select),
        .gate_collect_complete(pe_gate_collect_complete),
        .gate_rq_valid(controller_gate_rq_valid),
        .gate_rq_ready(controller_gate_rq_ready),
        .gate_rq_lane_valid(controller_gate_rq_mask),
        .gate_rq_value(controller_gate_rq_value),
        .gate_rq_multiplier(controller_gate_rq_multiplier),
        .gate_rq_shift(controller_gate_rq_shift),
        .gate_rq_gate(controller_gate_rq_gate),
        .gate_rq_component(controller_gate_rq_component),
        .gate_rq_group(controller_gate_rq_group),
        .gate_rq_tags(controller_gate_rq_tags),
        .gate_bias_valid(controller_gate_bias_valid),
        .gate_bias_ready(controller_gate_bias_ready),
        .gate_bias_gate(controller_gate_bias_gate),
        .gate_bias_group(controller_gate_bias_group),
        .gate_bias_lane_valid(controller_gate_bias_mask),
        .gate_bias_value(controller_gate_bias_value),
        .gate_bias_tags(controller_gate_bias_tags),
        .sigmoid_table_valid(pe_sigmoid_table_valid),
        .membrane_start_valid(controller_membrane_start_valid),
        .membrane_start_ready(controller_membrane_start_ready),
        .membrane_u_prev(controller_membrane_u_prev),
        .membrane_cx_multiplier(controller_membrane_cx_multiplier),
        .membrane_cx_shift(controller_membrane_cx_shift),
        .membrane_cell_multiplier(controller_membrane_cell_multiplier),
        .membrane_cell_shift(controller_membrane_cell_shift),
        .membrane_base_index(controller_membrane_base),
        .membrane_logical_last(controller_membrane_last),
        .membrane_done(pe_membrane_done),
        .linear_tile_valid(controller_linear_valid),
        .linear_tile_ready(controller_linear_ready),
        .linear_tile_lane_valid(controller_linear_mask),
        .linear_tile_base_index(controller_linear_base),
        .linear_tile_tags(controller_linear_tags),
        .linear_tile_logical_last(controller_linear_last),
        .rq_param_query_valid(rq_query_hold_valid_q),
        .rq_param_query_op_kind(rq_query_hold_kind_q),
        .rq_param_query_index(rq_query_hold_index_q),
        .rq_param_query_tag(rq_query_hold_tag_q),
        .rq_param_valid(controller_rq_param_valid),
        .rq_param_ready(controller_rq_param_ready),
        .rq_param_op_kind(controller_rq_param_kind),
        .rq_param_multiplier(controller_rq_multiplier),
        .rq_param_shift(controller_rq_shift),
        .rq_param_bias(controller_rq_bias),
        .rq_param_index(controller_rq_index),
        .rq_param_tag(controller_rq_tag),
        .hybrid_idle(pe_hybrid_idle),
        .local_rq_idle(pe_local_rq_idle),
        .postprocess_idle(pe_postprocess_idle),
        .sigmoid_idle(pe_sigmoid_idle),
        .serializer_idle(pe_serializer_idle),
        .shared_rq_idle(pe_shared_rq_idle),
        .qbn_fork_idle(pe_qbn_fork_idle),
        .local_rq_outstanding(pe_local_rq_outstanding),
        .postprocess_outstanding(pe_postprocess_outstanding),
        .shared_rq_outstanding(pe_shared_rq_outstanding),
        .overflow_any(pe_overflow_any),
        .protocol_error(pe_protocol_error),
        .pe_barrier_idle(controller_barrier_idle),
        .error_valid(controller_error_valid),
        .error_code(controller_error_code),
        .error_detail(controller_error_detail),
        .reset_required(controller_reset_required),
        .controller_state(controller_state),
        .current_row_tile(controller_row_tile),
        .weight_request_count(weight_request_count),
        .dense_weight_request_count(dense_weight_request_count),
        .sparse_weight_request_count(sparse_weight_request_count)
    );

    // ------------------------------------------------------------------
    // Inline one-start/2,040-byte LUT adapter.
    // ------------------------------------------------------------------
    reg [2:0] lut_state_q;
    reg [11:0] lut_count_q;
    reg [2:0] lut_table_q;
    reg [7:0] lut_addr_q;
    reg [1:0] lut_start_count_q;
    reg [31:0] lut_stall_count_q;
    wire pe_sigmoid_cfg_start_ready;
    wire pe_sigmoid_cfg_data_ready;
    wire pe_sigmoid_cfg_done;
    wire pe_sigmoid_cfg_start_valid =
        (lut_state_q == LUT_START) && !reset_required;
    wire pe_sigmoid_cfg_data_valid =
        (lut_state_q == LUT_DATA) && service_lut_cfg_valid &&
        !reset_required;
    wire pe_sigmoid_cfg_data_fire = pe_sigmoid_cfg_data_valid &&
                                    pe_sigmoid_cfg_data_ready;
    wire lut_start_fire = pe_sigmoid_cfg_start_valid &&
                          pe_sigmoid_cfg_start_ready;
    wire lut_stream_match = (service_lut_cfg_stage_id ==
                             {1'b0, lut_table_q}) &&
                            (service_lut_cfg_addr == lut_addr_q);
    wire lut_timeout = (LUT_STALL_TIMEOUT_CYCLES != 0) &&
        (lut_state_q != LUT_IDLE) && (lut_state_q != LUT_READY) &&
        (lut_state_q != LUT_ERROR) &&
        (lut_stall_count_q >= LUT_STALL_TIMEOUT_CYCLES - 1);

    assign service_lut_cfg_ready = (lut_state_q == LUT_DATA) &&
        pe_sigmoid_cfg_data_ready && !reset_required;
    assign lut_adapter_state = lut_state_q;
    assign lut_accepted_bytes = lut_count_q;
    assign lut_configuration_starts = lut_start_count_q;

    // ------------------------------------------------------------------
    // Frozen PE instance.  CDF is intentionally inactive.
    // ------------------------------------------------------------------
    wire pe_membrane_busy;
    wire [3:0] pe_membrane_phase;
    wire pe_cdf_start_ready;
    wire pe_cdf_tap_ready;
    wire pe_cdf_result_valid;
    wire [255:0] pe_cdf_result_real;
    wire [255:0] pe_cdf_result_imag;
    wire [7:0] pe_cdf_result_bin_valid;
    wire [2:0] pe_cdf_result_order;
    wire [7:0] pe_cdf_result_bin_base;
    wire [1:0] pe_cdf_result_band;
    wire [15:0] pe_cdf_result_tag;
    wire pe_cdf_busy;
    wire pe_cdf_done;
    wire [2:0] pe_cdf_phase;
    wire [2:0] pe_cdf_active_tap;

    pe_array_datapath u_pe_array_datapath (
        .clk(clk), .rst_n(rst_n),
        .raw_owner_request(controller_raw_owner_request),
        .raw_owner_grant(controller_raw_owner_grant),
        .gate_owner_request(controller_gate_owner_request),
        .gate_owner_grant(controller_gate_owner_grant),
        .compute_owner(compute_owner),
        .compute_idle(controller_compute_idle),
        .ctrl_pe_acc_clear(controller_acc_clear),
        .ctrl_pe_acc_enable(controller_acc_enable),
        .ctrl_pe_mode(controller_pe_mode),
        .ctrl_pe_operand_a(controller_operand_a),
        .ctrl_pe_operand_b(controller_operand_b),
        .ctrl_pe_gate_u8(controller_gate_u8),
        .ctrl_pe_spike_enable(controller_spike_enable),
        .ctrl_pe_direct_value(controller_direct_value),
        .pe_accumulator(pe_accumulator),
        .pe_overflow(pe_overflow),
        .gate_tile_valid(controller_gate_tile_valid),
        .gate_tile_ready(controller_gate_tile_ready),
        .gate_tile_lane_valid(controller_gate_tile_mask),
        .gate_tile_tags(controller_gate_tile_tags),
        .gate_tile_table_select(controller_gate_table_select),
        .gate_collect_complete(pe_gate_collect_complete),
        .gate_rq_valid(controller_gate_rq_valid),
        .gate_rq_ready(controller_gate_rq_ready),
        .gate_rq_lane_valid(controller_gate_rq_mask),
        .gate_rq_value(controller_gate_rq_value),
        .gate_rq_multiplier(controller_gate_rq_multiplier),
        .gate_rq_shift(controller_gate_rq_shift),
        .gate_rq_gate(controller_gate_rq_gate),
        .gate_rq_component(controller_gate_rq_component),
        .gate_rq_group(controller_gate_rq_group),
        .gate_rq_tags(controller_gate_rq_tags),
        .gate_bias_valid(controller_gate_bias_valid),
        .gate_bias_ready(controller_gate_bias_ready),
        .gate_bias_gate(controller_gate_bias_gate),
        .gate_bias_group(controller_gate_bias_group),
        .gate_bias_lane_valid(controller_gate_bias_mask),
        .gate_bias_value(controller_gate_bias_value),
        .gate_bias_tags(controller_gate_bias_tags),
        .sigmoid_cfg_start_valid(pe_sigmoid_cfg_start_valid),
        .sigmoid_cfg_start_ready(pe_sigmoid_cfg_start_ready),
        .sigmoid_cfg_data_valid(pe_sigmoid_cfg_data_valid),
        .sigmoid_cfg_data_ready(pe_sigmoid_cfg_data_ready),
        .sigmoid_cfg_data(service_lut_cfg_data),
        .sigmoid_cfg_done(pe_sigmoid_cfg_done),
        .sigmoid_table_valid(pe_sigmoid_table_valid),
        .membrane_start_valid(controller_membrane_start_valid),
        .membrane_start_ready(controller_membrane_start_ready),
        .membrane_u_prev(controller_membrane_u_prev),
        .membrane_cx_multiplier(controller_membrane_cx_multiplier),
        .membrane_cx_shift(controller_membrane_cx_shift),
        .membrane_cell_multiplier(controller_membrane_cell_multiplier),
        .membrane_cell_shift(controller_membrane_cell_shift),
        .membrane_base_index(controller_membrane_base),
        .membrane_logical_last(controller_membrane_last),
        .membrane_busy(pe_membrane_busy),
        .membrane_done(pe_membrane_done),
        .membrane_phase(pe_membrane_phase),
        .linear_tile_valid(controller_linear_valid),
        .linear_tile_ready(controller_linear_ready),
        .linear_tile_lane_valid(controller_linear_mask),
        .linear_tile_base_index(controller_linear_base),
        .linear_tile_tags(controller_linear_tags),
        .linear_tile_logical_last(controller_linear_last),
        .rq_param_query_valid(pe_rq_query_valid),
        .rq_param_query_op_kind(pe_rq_query_kind),
        .rq_param_query_index(pe_rq_query_index),
        .rq_param_query_tag(pe_rq_query_tag),
        .rq_param_valid(controller_rq_param_valid),
        .rq_param_ready(controller_rq_param_ready),
        .rq_param_op_kind(controller_rq_param_kind),
        .rq_param_multiplier(controller_rq_multiplier),
        .rq_param_shift(controller_rq_shift),
        .rq_param_bias(controller_rq_bias),
        .rq_param_index(controller_rq_index),
        .rq_param_tag(controller_rq_tag),
        .state_write_valid(pe_state_write_valid),
        .state_write_ready(pe_state_write_ready),
        .state_write_value(pe_state_write_value),
        .state_write_index(pe_state_write_index),
        .state_write_tag(pe_state_write_tag),
        .state_write_last(pe_state_write_last),
        .active_cmd_valid(pe_active_cmd_valid),
        .active_cmd_ready(pe_active_cmd_ready),
        .active_cmd_write(pe_active_cmd_write),
        .active_cmd_index(pe_active_cmd_index),
        .active_cmd_tag(pe_active_cmd_tag),
        .active_cmd_finalize(pe_active_cmd_finalize),
        .coefficient_valid(coefficient_valid),
        .coefficient_ready(coefficient_ready),
        .coefficient_value(coefficient_value),
        .coefficient_index(coefficient_index),
        .coefficient_tag(coefficient_tag),
        .coefficient_last(coefficient_last),
        .cdf_start_valid(1'b0),
        .cdf_start_ready(pe_cdf_start_ready),
        .cdf_order(3'd0),
        .cdf_bin_valid(8'd0),
        .cdf_bin_base(8'd0),
        .cdf_band(2'd0),
        .cdf_tag(16'd0),
        .cdf_tap_valid(1'b0),
        .cdf_tap_ready(pe_cdf_tap_ready),
        .cdf_tap_index(3'd0),
        .cdf_spectrum_real(64'd0),
        .cdf_spectrum_imag(64'd0),
        .cdf_coefficient_real(64'd0),
        .cdf_coefficient_imag(64'd0),
        .cdf_result_valid(pe_cdf_result_valid),
        .cdf_result_ready(1'b1),
        .cdf_result_real(pe_cdf_result_real),
        .cdf_result_imag(pe_cdf_result_imag),
        .cdf_result_bin_valid(pe_cdf_result_bin_valid),
        .cdf_result_order(pe_cdf_result_order),
        .cdf_result_bin_base(pe_cdf_result_bin_base),
        .cdf_result_band(pe_cdf_result_band),
        .cdf_result_tag(pe_cdf_result_tag),
        .cdf_busy(pe_cdf_busy),
        .cdf_done(pe_cdf_done),
        .cdf_phase(pe_cdf_phase),
        .cdf_active_tap_index(pe_cdf_active_tap),
        .hybrid_idle(pe_hybrid_idle),
        .local_rq_idle(pe_local_rq_idle),
        .postprocess_idle(pe_postprocess_idle),
        .sigmoid_idle(pe_sigmoid_idle),
        .serializer_idle(pe_serializer_idle),
        .shared_rq_idle(pe_shared_rq_idle),
        .qbn_fork_idle(pe_qbn_fork_idle),
        .local_rq_outstanding(pe_local_rq_outstanding),
        .postprocess_outstanding(pe_postprocess_outstanding),
        .shared_rq_outstanding(pe_shared_rq_outstanding),
        .overflow_any(pe_overflow_any),
        .protocol_error(pe_protocol_error)
    );

    assign reset_required = integration_error_valid || memory_error_valid ||
        context_error_valid || controller_error_valid ||
        pe_overflow_any || pe_protocol_error;
    assign pe_fault = {2'b00, reset_required};
    assign pe_barrier_idle = {2'b11,
        controller_barrier_idle &&
        ((lut_state_q == LUT_READY) || !service_lut_ready)};

    task latch_integration_fault;
        input [7:0] code;
        input [31:0] detail;
        begin
            if (!integration_error_valid) begin
                integration_error_valid <= 1'b1;
                integration_error_code <= code;
                integration_error_detail <= detail;
            end
            lut_state_q <= LUT_ERROR;
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            integration_error_valid <= 1'b0;
            integration_error_code <= INT_ERR_NONE;
            integration_error_detail <= 32'd0;
            invalid_stage_pulse_q <= 1'b0;
            active_job_is_fb_q <= 1'b0;
            context_commit_barrier_q <= 1'b0;
            context_list_read_req_id_q <= 5'd0;
            rq_query_hold_valid_q <= 1'b0;
            rq_query_hold_kind_q <= 1'b0;
            rq_query_hold_index_q <= 9'd0;
            rq_query_hold_tag_q <= 16'd0;
            lut_state_q <= LUT_IDLE;
            lut_count_q <= 12'd0;
            lut_table_q <= 3'd0;
            lut_addr_q <= 8'd0;
            lut_start_count_q <= 2'd0;
            lut_stall_count_q <= 32'd0;
        end else begin
            invalid_stage_pulse_q <= 1'b0;
            context_commit_barrier_q <= context_commit_barrier &&
                                        !reset_required;
            context_list_read_req_id_q <= context_list_read_req_id;

            if (rq_query_response_fire) begin
                rq_query_hold_valid_q <= 1'b0;
            end else if (!rq_query_hold_valid_q && pe_rq_query_valid) begin
                rq_query_hold_valid_q <= 1'b1;
                rq_query_hold_kind_q <= pe_rq_query_kind;
                rq_query_hold_index_q <= pe_rq_query_index;
                rq_query_hold_tag_q <= pe_rq_query_tag;
            end

            if (controller_job_fire)
                active_job_is_fb_q <= fb_start;

            if (lut_start_fire || pe_sigmoid_cfg_data_fire ||
                pe_sigmoid_cfg_done)
                lut_stall_count_q <= 32'd0;
            else if ((lut_state_q != LUT_IDLE) &&
                     (lut_state_q != LUT_READY) &&
                     (lut_state_q != LUT_ERROR))
                lut_stall_count_q <= lut_stall_count_q + 1'b1;
            else
                lut_stall_count_q <= 32'd0;

            if (!integration_error_valid) begin
                if (invalid_stage_event) begin
                    invalid_stage_pulse_q <= 1'b1;
                    latch_integration_fault(INT_ERR_STAGE_BANK,
                        {26'd0, stage_bank, stage_id});
                end else if (external_job_fire && !legal_job_vector) begin
                    latch_integration_fault(INT_ERR_JOB_VECTOR,
                        {22'd0, fb_start, sb_start, fb_stage,
                         sb_stage, sb_shared_branch});
                end else if (lut_timeout) begin
                    latch_integration_fault(INT_ERR_LUT_TIMEOUT,
                        {1'd0, lut_state_q, lut_stall_count_q[27:0]});
                end else begin
                    case (lut_state_q)
                        LUT_IDLE: begin
                            if (pe_sigmoid_cfg_done)
                                latch_integration_fault(INT_ERR_LUT_DONE,
                                    32'h00000001);
                            else if (service_lut_cfg_valid) begin
                                lut_count_q <= 12'd0;
                                lut_table_q <= 3'd0;
                                lut_addr_q <= 8'd0;
                                lut_state_q <= LUT_START;
                            end
                        end
                        LUT_START: begin
                            if (pe_sigmoid_cfg_done)
                                latch_integration_fault(INT_ERR_LUT_DONE,
                                    32'h00000002);
                            else if (lut_start_fire) begin
                                lut_start_count_q <=
                                    lut_start_count_q + 1'b1;
                                lut_state_q <= LUT_DATA;
                            end
                        end
                        LUT_DATA: begin
                            if (pe_sigmoid_cfg_done)
                                latch_integration_fault(INT_ERR_LUT_DONE,
                                    32'h00000003);
                            else if (pe_sigmoid_cfg_data_fire) begin
                                if (!lut_stream_match) begin
                                    latch_integration_fault(INT_ERR_LUT_ORDER,
                                        {1'd0, service_lut_cfg_stage_id,
                                         service_lut_cfg_addr,
                                         lut_table_q, lut_addr_q,
                                         lut_count_q[7:0]});
                                end else begin
                                    lut_count_q <= lut_count_q + 1'b1;
                                    if ((lut_table_q == 3'd7) &&
                                        (lut_addr_q == 8'd254)) begin
                                        if (lut_count_q != 12'd2039)
                                            latch_integration_fault(
                                                INT_ERR_LUT_ORDER,
                                                {20'd0, lut_count_q});
                                        else
                                            lut_state_q <= LUT_WAIT_DONE;
                                    end else if (lut_addr_q == 8'd254) begin
                                        lut_addr_q <= 8'd0;
                                        lut_table_q <= lut_table_q + 1'b1;
                                    end else begin
                                        lut_addr_q <= lut_addr_q + 1'b1;
                                    end
                                end
                            end
                        end
                        LUT_WAIT_DONE: begin
                            if (pe_sigmoid_cfg_done) begin
                                if (!pe_sigmoid_table_valid ||
                                    (lut_count_q != 12'd2040) ||
                                    (lut_start_count_q != 2'd1))
                                    latch_integration_fault(INT_ERR_LUT_DONE,
                                        {17'd0, pe_sigmoid_table_valid,
                                         lut_start_count_q, lut_count_q});
                                else
                                    lut_state_q <= LUT_READY;
                            end
                        end
                        LUT_READY: begin
                            if (service_lut_cfg_valid ||
                                pe_sigmoid_cfg_done ||
                                !pe_sigmoid_table_valid)
                                latch_integration_fault(INT_ERR_LUT_DONE,
                                    32'h00000004);
                        end
                        default: lut_state_q <= LUT_ERROR;
                    endcase
                end
            end
        end
    end
endmodule
