`timescale 1ns/1ps
`include "memory/model_memory_v5_map.vh"

// Sequential-v5 parameter memory service for 32-row tiles.
//
// One unchanged memory.v instance provides a 256 KiB, 64-bit cache and a
// read-only AXI master. The first legal stage request after reset loads and
// streams the image-global 8 x 255-byte sigmoid section, then loads the
// requested stage in full. Later stages reuse the configured PE LUT.
//
// Compute requests are serialized. A weight response is built from two cache
// words and a parameter response from 181 (GSU) or 35 (projection) words. A
// held response must be consumed before another request is accepted. Any error
// is sticky and reset-only.
module memory_service_v5 #(
    parameter integer AXI_ADDR_WIDTH      = 32,
    parameter integer AXI_DATA_WIDTH      = 64,
    parameter integer AXI_ID_WIDTH        = 1,
    parameter integer CACHE_ADDR_WIDTH    = 15,
    parameter integer MAX_BURST_BEATS     = 16,
    parameter integer LOAD_TIMEOUT_CYCLES = 100000,
    parameter integer TAG_WIDTH           = 8
) (
    input  wire                           clk,
    input  wire                           rst_n,
    input  wire                           abort,
    input  wire                           clear_error,
    input  wire [AXI_ADDR_WIDTH-1:0]      parameter_base_addr,
    input  wire [31:0]                    image_version,

    input  wire                           plan_valid,
    output wire                           plan_ready,
    input  wire [3:0]                     plan_stage_id,
    input  wire                           plan_sparse_enable,
    input  wire                           plan_fallback_full,
    input  wire [1:0]                     plan_matrix_count,
    input  wire [319:0]                   plan_bitmap0,
    input  wire [319:0]                   plan_bitmap1,
    input  wire [8:0]                     plan_count0,
    input  wire [8:0]                     plan_count1,

    output reg                            stage_load_done,
    output reg                            stage_load_error,
    output wire                           stage_ready_for_compute,
    output wire                           lut_ready,
    input  wire                           stage_release_valid,
    output wire                           stage_release_ready,
    input  wire [3:0]                     stage_release_id,

    output wire [2:0]                     cache_state,
    output wire [3:0]                     active_stage_id,
    output wire [31:0]                    active_image_version,
    output wire                           active_stage_kind,
    output wire [1:0]                     active_matrix_count,
    output wire [9:0]                     active_matrix0_sources,
    output wire [5:0]                     active_matrix0_row_tiles,
    output wire [9:0]                     active_matrix1_sources,
    output wire [5:0]                     active_matrix1_row_tiles,
    output wire [5:0]                     active_param_tiles,
    output wire                           active_uses_sigmoid_table,
    output wire [2:0]                     active_sigmoid_table_select,

    output reg                            error_valid,
    output reg  [7:0]                     error_code,
    output reg  [3:0]                     error_stage,
    output reg  [31:0]                    error_detail,
    output wire                           reset_required,

    output wire                           raw_loader_busy,
    output wire                           raw_loader_done,
    output wire                           raw_loader_error,
    output wire                           raw_loader_timeout,
    output wire                           raw_loader_abort_drain,

    input  wire                           weight_req_valid,
    output wire                           weight_req_ready,
    input  wire                           weight_req_matrix,
    input  wire [9:0]                     weight_req_source,
    input  wire [5:0]                     weight_req_row_tile,
    input  wire [TAG_WIDTH-1:0]           weight_req_tag,
    output wire                           weight_rsp_valid,
    input  wire                           weight_rsp_ready,
    output wire [255:0]                   weight_rsp_data,
    output wire [TAG_WIDTH-1:0]           weight_rsp_tag,
    output wire                           weight_rsp_error,

    input  wire                           param_req_valid,
    output wire                           param_req_ready,
    input  wire [5:0]                     param_req_row_tile,
    input  wire [TAG_WIDTH-1:0]           param_req_tag,
    output wire                           param_rsp_valid,
    input  wire                           param_rsp_ready,
    output wire [11583:0]                 param_rsp_data,
    output wire                           param_rsp_kind,
    output wire [13:0]                    param_rsp_bits,
    output wire [TAG_WIDTH-1:0]           param_rsp_tag,
    output wire                           param_rsp_error,

    output wire                           lut_cfg_valid,
    input  wire                           lut_cfg_ready,
    output wire [3:0]                     lut_cfg_stage_id,
    output wire [7:0]                     lut_cfg_addr,
    output wire [7:0]                     lut_cfg_data,

    output reg  [31:0]                    diag_planned_bytes,
    output reg  [31:0]                    diag_actual_bytes,
    output reg  [31:0]                    diag_dense_bytes,
    output reg  [31:0]                    diag_saved_bytes,
    output reg  [8:0]                     diag_union_count0,
    output reg  [8:0]                     diag_union_count1,
    output reg  [15:0]                    diag_copy_commands,
    output reg  [31:0]                    diag_ar_bursts,
    output reg  [31:0]                    diag_load_cycles,
    output reg  [31:0]                    diag_lut_actual_bytes,

    output wire [AXI_ADDR_WIDTH-1:0]      m_axi_araddr,
    output wire [AXI_ID_WIDTH-1:0]        m_axi_arid,
    output wire [7:0]                     m_axi_arlen,
    output wire [2:0]                     m_axi_arsize,
    output wire [1:0]                     m_axi_arburst,
    output wire [2:0]                     m_axi_arprot,
    output wire [3:0]                     m_axi_arcache,
    output wire [3:0]                     m_axi_arqos,
    output wire                           m_axi_arlock,
    output wire                           m_axi_arvalid,
    input  wire                           m_axi_arready,
    input  wire [AXI_DATA_WIDTH-1:0]      m_axi_rdata,
    input  wire [AXI_ID_WIDTH-1:0]        m_axi_rid,
    input  wire [1:0]                     m_axi_rresp,
    input  wire                           m_axi_rlast,
    input  wire                           m_axi_rvalid,
    output wire                           m_axi_rready
);
    localparam integer CACHE_WORDS       = (1 << CACHE_ADDR_WIDTH);
    localparam integer PARAM_BUFFER_BITS = 11584; // 181 x 64-bit words

    localparam [4:0] S_EMPTY       = 5'd0;
    localparam [4:0] S_VALIDATE    = 5'd1;
    localparam [4:0] S_LUT_CMD     = 5'd2;
    localparam [4:0] S_LUT_LOAD    = 5'd3;
    localparam [4:0] S_LUT_STREAM  = 5'd4;
    localparam [4:0] S_PREPARE     = 5'd5;
    localparam [4:0] S_SCAN        = 5'd6;
    localparam [4:0] S_EXTEND      = 5'd7;
    localparam [4:0] S_PARAM       = 5'd8;
    localparam [4:0] S_CMD_CHECK   = 5'd9;
    localparam [4:0] S_CMD_SEND    = 5'd10;
    localparam [4:0] S_CMD_WAIT    = 5'd11;
    localparam [4:0] S_PUBLISH     = 5'd12;
    localparam [4:0] S_READY       = 5'd13;
    localparam [4:0] S_CMD_DECIDE  = 5'd14;
    localparam [4:0] S_VALIDATE_DONE = 5'd15;
    localparam [4:0] S_RUN_MUL     = 5'd16;
    localparam [4:0] S_RUN_COMMAND = 5'd17;
    localparam [4:0] S_DENSE_MUL   = 5'd18;
    localparam [4:0] S_DENSE_COMMAND = 5'd19;
    localparam [4:0] S_PLAN_BYTES_MUL = 5'd20;
    localparam [4:0] S_PLAN_BYTES_COMMIT = 5'd21;
    localparam [4:0] S_FATAL       = 5'd31;

    localparam [4:0] A_IDLE            = 5'd0;
    localparam [4:0] A_WEIGHT_CHECK    = 5'd1;
    localparam [4:0] A_WEIGHT_REQ      = 5'd2;
    localparam [4:0] A_WEIGHT_WAIT     = 5'd3;
    localparam [4:0] A_PARAM_CONSUME   = 5'd4;
    localparam [4:0] A_WEIGHT_RESPONSE = 5'd6;
    localparam [4:0] A_PARAM_CHECK     = 5'd7;
    localparam [4:0] A_PARAM_REQ       = 5'd8;
    localparam [4:0] A_PARAM_WAIT      = 5'd9;
    localparam [4:0] A_PARAM_RESPONSE  = 5'd10;
    localparam [4:0] A_LUT_REQ         = 5'd11;
    localparam [4:0] A_LUT_WAIT        = 5'd12;
    localparam [4:0] A_LUT_SEND        = 5'd13;

    localparam [7:0] ERR_NONE             = 8'h00;
    localparam [7:0] ERR_STAGE_ID         = 8'h01;
    localparam [7:0] ERR_IMAGE_VERSION    = 8'h02;
    localparam [7:0] ERR_BASE_ALIGNMENT   = 8'h03;
    localparam [7:0] ERR_ADDRESS_OVERFLOW = 8'h04;
    localparam [7:0] ERR_STAGE_TOO_LARGE  = 8'h05;
    localparam [7:0] ERR_AXI_LOAD         = 8'h06;
    localparam [7:0] ERR_AXI_TIMEOUT      = 8'h07;
    localparam [7:0] ERR_STAGE_RELEASE    = 8'h08;
    localparam [7:0] ERR_WEIGHT_REQUEST   = 8'h09;
    localparam [7:0] ERR_PARAM_REQUEST    = 8'h0a;
    localparam [7:0] ERR_ABORT            = 8'h0b;
    localparam [7:0] ERR_EPOCH_IDENTITY   = 8'h0c;
    localparam [7:0] ERR_PLAN             = 8'h0d;
    localparam [7:0] ERR_NOT_RESIDENT     = 8'h0e;
    localparam [7:0] ERR_TRAFFIC          = 8'h0f;

    reg [4:0] state_q;
    // Dedicated publication-valid register.  This keeps the high-fanout
    // compute descriptor enable off the memory-service FSM decode while
    // preserving the exact S_PUBLISH/S_READY lifetime.
    reg       stage_ready_q;
    reg [4:0] adapter_state_q;

    wire table_stage_valid;
    wire table_stage_kind;
    wire [31:0] table_dram_byte_offset;
    wire [31:0] table_transfer_bytes;
    wire [1:0] table_matrix_count;
    wire [31:0] table_matrix0_word_offset;
    wire [9:0] table_matrix0_sources;
    wire [5:0] table_matrix0_row_tiles;
    wire [31:0] table_matrix1_word_offset;
    wire [9:0] table_matrix1_sources;
    wire [5:0] table_matrix1_row_tiles;
    wire [31:0] table_param_word_offset;
    wire [7:0] table_param_record_words;
    wire [13:0] table_param_response_bits;
    wire [5:0] table_param_tiles;
    wire table_uses_sigmoid_table;
    wire [2:0] table_sigmoid_table_select;

    model_memory_v5_table stage_table (
        .stage_id(plan_stage_id),
        .stage_valid(table_stage_valid),
        .stage_kind(table_stage_kind),
        .dram_byte_offset(table_dram_byte_offset),
        .transfer_bytes(table_transfer_bytes),
        .matrix_count(table_matrix_count),
        .matrix0_word_offset(table_matrix0_word_offset),
        .matrix0_sources(table_matrix0_sources),
        .matrix0_row_tiles(table_matrix0_row_tiles),
        .matrix1_word_offset(table_matrix1_word_offset),
        .matrix1_sources(table_matrix1_sources),
        .matrix1_row_tiles(table_matrix1_row_tiles),
        .param_word_offset(table_param_word_offset),
        .param_record_words(table_param_record_words),
        .param_response_bits(table_param_response_bits),
        .param_tiles(table_param_tiles),
        .uses_sigmoid_table(table_uses_sigmoid_table),
        .sigmoid_table_select(table_sigmoid_table_select)
    );

    reg stage_kind_q;
    reg [31:0] stage_dram_offset_q;
    reg [31:0] stage_transfer_bytes_q;
    reg [1:0] matrix_count_q;
    reg [31:0] matrix0_word_offset_q;
    reg [9:0] matrix0_sources_q;
    reg [5:0] matrix0_row_tiles_q;
    reg [31:0] matrix1_word_offset_q;
    reg [9:0] matrix1_sources_q;
    reg [5:0] matrix1_row_tiles_q;
    reg [31:0] param_word_offset_q;
    reg [7:0] param_record_words_q;
    reg [13:0] param_response_bits_q;
    reg [5:0] param_tiles_q;
    reg uses_sigmoid_table_q;
    reg [2:0] sigmoid_table_select_q;
    reg matrix0_dense_q;

    reg [AXI_ADDR_WIDTH-1:0] transaction_base_q;
    reg [3:0] transaction_stage_id_q;
    reg [31:0] transaction_image_version_q;
    reg [3:0] published_stage_id_q;
    reg [31:0] published_image_version_q;
    reg [319:0] tentative_bitmap0_q;
    reg [319:0] tentative_bitmap1_q;
    reg [8:0] tentative_count0_q;
    reg [8:0] tentative_count1_q;
    reg tentative_sparse_enable_q;
    reg tentative_fallback_q;
    reg [319:0] resident_bitmap0_q;
    reg [319:0] resident_bitmap1_q;
    reg resident_fallback_q;

    reg lut_initialized_q;
    reg [AXI_ADDR_WIDTH-1:0] epoch_base_addr_q;
    reg [31:0] epoch_image_version_q;

    reg validation_matrix_q;
    reg [8:0] validation_index_q;
    reg [8:0] validation_count_q;
    // The current bitmap is consumed strictly from low to high in both the
    // validation and sparse-run scanners.  Keeping a shift cursor avoids a
    // 320:1 variable-index mux on the validation/error and copy-command paths.
    // The immutable tentative bitmaps remain the transaction/residency source
    // of truth and reload this cursor at each matrix boundary.
    reg [319:0] bitmap_shift_q;
    wire [9:0] validation_source_limit = validation_matrix_q
        ? matrix1_sources_q : (matrix0_dense_q ? 10'd0 : matrix0_sources_q);
    wire validation_bit = bitmap_shift_q[0];
    wire [8:0] validation_expected_count = validation_matrix_q
        ? tentative_count1_q : tentative_count0_q;
    wire [9:0] validation_count_next = {1'b0, validation_count_q} +
        ((validation_bit && ({1'b0, validation_index_q} < validation_source_limit))
         ? 10'd1 : 10'd0);

    wire eligible0_full = matrix0_dense_q ||
        (tentative_count0_q == matrix0_sources_q[8:0]);
    wire eligible1_full = (matrix_count_q < 2) ||
        (tentative_count1_q == matrix1_sources_q[8:0]);
    wire expected_fallback = !tentative_sparse_enable_q ||
                             (eligible0_full && eligible1_full);
    // All v5 geometry products are intrinsically narrow.  Preserve those
    // widths explicitly so Vivado cannot infer cascaded 32-bit DSP products
    // on command/count paths.
    wire [13:0] param_record_tile_product =
        param_record_words_q * param_tiles_q;
    wire [31:0] param_transfer_bytes =
        {15'd0, param_record_tile_product, 3'b000};
    wire [9:0] matrix0_loaded_sources = matrix0_dense_q
        ? matrix0_sources_q : {1'b0, tentative_count0_q};
    wire [15:0] matrix0_loaded_tile_product =
        matrix0_loaded_sources * matrix0_row_tiles_q;
    wire [14:0] matrix1_loaded_tile_product =
        tentative_count1_q * matrix1_row_tiles_q;
    reg [16:0] planned_param_bytes_q;
    reg [19:0] planned_matrix0_bytes_q;
    reg [18:0] planned_matrix1_bytes_q;

    reg scan_matrix_q;
    reg [9:0] scan_index_q;
    reg [9:0] run_start_q;
    reg [9:0] run_end_q;
    reg [9:0] run_length_q;
    reg [15:0] run_start_tile_product_q;
    reg [15:0] run_length_tile_product_q;
    wire [9:0] scan_sources = scan_matrix_q
        ? matrix1_sources_q : matrix0_sources_q;
    wire [5:0] scan_row_tiles = scan_matrix_q
        ? matrix1_row_tiles_q : matrix0_row_tiles_q;
    wire [31:0] scan_matrix_offset_bytes = scan_matrix_q
        ? (matrix1_word_offset_q << 3) : (matrix0_word_offset_q << 3);
    wire scan_dense = !scan_matrix_q && matrix0_dense_q;

    reg [31:0] command_local_offset_q;
    reg [31:0] command_byte_count_q;
    reg [4:0] post_command_state_q;
    reg command_bounds_valid_q;
    reg [AXI_ADDR_WIDTH-1:0] load_src_addr_q;
    reg [CACHE_ADDR_WIDTH-1:0] load_dst_word_q;
    wire [32:0] command_src_start_33 = {1'b0, transaction_base_q} +
        {1'b0, stage_dram_offset_q} + {1'b0, command_local_offset_q};
    wire [32:0] command_src_end_33 = command_src_start_33 +
        {1'b0, command_byte_count_q};
    wire [32:0] image_end_33 = {1'b0, transaction_base_q} +
        {1'b0, `MODEL_V5_IMAGE_BYTES};
    wire [32:0] command_cache_end_33 = {1'b0, command_local_offset_q} +
        {1'b0, command_byte_count_q};
    wire [32:0] command_stage_end_33 = {1'b0, command_local_offset_q} +
        {1'b0, command_byte_count_q};
    wire [32:0] requested_image_end_33 = {1'b0, parameter_base_addr} +
        {1'b0, `MODEL_V5_IMAGE_BYTES};
    wire [32:0] requested_lut_end_33 = {1'b0, parameter_base_addr} +
        {1'b0, `MODEL_V5_GLOBAL_SIGMOID_LUT_DRAM_OFFSET} +
        {1'b0, `MODEL_V5_GLOBAL_SIGMOID_LUT_TRANSFER_BYTES};
    wire command_bounds_valid =
        (command_byte_count_q != 0) &&
        ((command_local_offset_q & 32'd7) == 0) &&
        ((command_byte_count_q & 32'd7) == 0) &&
        !command_src_start_33[32] && !command_src_end_33[32] &&
        !image_end_33[32] &&
        (command_src_end_33 <= image_end_33) &&
        (command_cache_end_33 <= (CACHE_WORDS * 8)) &&
        (command_stage_end_33 <= {1'b0, stage_transfer_bytes_q});

    wire raw_cmd_valid = (state_q == S_LUT_CMD) || (state_q == S_CMD_SEND);
    wire raw_cmd_ready;
    wire raw_load_busy;
    wire raw_load_done;
    wire raw_load_error;
    wire raw_load_timeout;
    wire raw_rd_en;
    wire [CACHE_ADDR_WIDTH-3:0] raw_rd_addr;
    wire [255:0] raw_rdata;
    wire raw_rvalid;
    wire [AXI_ADDR_WIDTH-1:0] raw_cmd_src_addr = (state_q == S_LUT_CMD)
        ? transaction_base_q + `MODEL_V5_GLOBAL_SIGMOID_LUT_DRAM_OFFSET
        : load_src_addr_q;
    wire [CACHE_ADDR_WIDTH-1:0] raw_cmd_dst_word = (state_q == S_LUT_CMD)
        ? {CACHE_ADDR_WIDTH{1'b0}} : load_dst_word_q;
    wire [31:0] raw_cmd_byte_count = (state_q == S_LUT_CMD)
        ? `MODEL_V5_GLOBAL_SIGMOID_LUT_TRANSFER_BYTES : command_byte_count_q;

    memory_wide256 #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .DMA_ADDR_WIDTH(CACHE_ADDR_WIDTH),
        .MAX_BURST_BEATS(MAX_BURST_BEATS),
        .TIMEOUT_CYCLES(LOAD_TIMEOUT_CYCLES),
        .COMPUTE_DATA_WIDTH(256)
    ) raw_cache (
        .clk(clk),
        .rst_n(rst_n),
        .abort(abort || (state_q == S_FATAL)),
        .cmd_valid(raw_cmd_valid),
        .cmd_ready(raw_cmd_ready),
        .cmd_src_addr(raw_cmd_src_addr),
        .cmd_dst_word_addr(raw_cmd_dst_word),
        .cmd_byte_count(raw_cmd_byte_count),
        .load_busy(raw_load_busy),
        .load_done(raw_load_done),
        .load_error(raw_load_error),
        .load_timeout(raw_load_timeout),
        .pe_rd_en(raw_rd_en),
        .pe_addr(raw_rd_addr),
        .pe_rdata(raw_rdata),
        .pe_rvalid(raw_rvalid),
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

    reg counting_stage_q;
    reg counting_lut_q;
    reg diag_load_active_q;

    reg [31:0] weight_word_addr_q;
    reg [16:0] weight_request_detail_q;
    reg [255:0] weight_rsp_data_q;
    reg [TAG_WIDTH-1:0] weight_rsp_tag_q;
    reg weight_rsp_error_q;
    reg [31:0] param_record_addr_q;
    reg [5:0] param_request_tile_q;
    reg [7:0] param_word_index_q;
    reg [1:0] param_lane_q;
    reg [255:0] param_wide_data_q;
    reg [PARAM_BUFFER_BITS-1:0] param_buffer_q;
    reg [TAG_WIDTH-1:0] param_rsp_tag_q;
    reg param_rsp_error_q;
    reg param_rsp_kind_q;
    reg [13:0] param_rsp_bits_q;

    reg [8:0] lut_word_index_q;
    reg [2:0] lut_lane_q;
    reg [2:0] lut_table_q;
    reg [7:0] lut_table_addr_q;
    reg [63:0] lut_word_q;

    wire [31:0] selected_matrix_offset = weight_req_matrix
        ? matrix1_word_offset_q : matrix0_word_offset_q;
    wire [9:0] selected_matrix_sources = weight_req_matrix
        ? matrix1_sources_q : matrix0_sources_q;
    wire [5:0] selected_matrix_tiles = weight_req_matrix
        ? matrix1_row_tiles_q : matrix0_row_tiles_q;
    wire [31:0] requested_weight_product =
        {22'd0, weight_req_source} * {26'd0, selected_matrix_tiles};
    wire [31:0] requested_weight_word = selected_matrix_offset +
        ((requested_weight_product + {26'd0, weight_req_row_tile}) << 2);
    wire [31:0] requested_param_word = param_word_offset_q +
        ({26'd0, param_req_row_tile} * {24'd0, param_record_words_q});
    wire [31:0] current_param_word = param_record_addr_q +
        {24'd0, param_word_index_q};

    function automatic source_is_resident;
        input matrix_id;
        input [9:0] source_id;
        begin
            if (resident_fallback_q)
                source_is_resident = 1'b1;
            else if (!matrix_id && matrix0_dense_q)
                source_is_resident = 1'b1;
            else if (source_id >= 10'd320)
                source_is_resident = 1'b0;
            else if (matrix_id)
                source_is_resident = resident_bitmap1_q[source_id];
            else
                source_is_resident = resident_bitmap0_q[source_id];
        end
    endfunction

    wire adapter_idle = (adapter_state_q == A_IDLE);
    wire native_accept_enable = (state_q == S_READY) && !error_valid &&
                                adapter_idle && !stage_release_valid && !abort;
    assign plan_ready = (state_q == S_EMPTY) && !raw_load_busy &&
                        adapter_idle && !error_valid && !abort;
    assign stage_release_ready = (state_q == S_READY) && adapter_idle &&
                                 !error_valid && !abort;
    assign stage_ready_for_compute = stage_ready_q && !error_valid;
    assign lut_ready = lut_initialized_q;
    assign reset_required = error_valid;
    assign cache_state = (state_q == S_EMPTY) ? 3'd0 :
                         ((state_q == S_LUT_CMD) || (state_q == S_LUT_LOAD) ||
                          (state_q == S_LUT_STREAM)) ? 3'd1 :
                         (state_q == S_READY) ? 3'd6 :
                         (state_q == S_FATAL) ? 3'd7 : 3'd5;

    // Active identity, geometry, and residency become externally visible in
    // the same S_PUBLISH transition. Before that point (and after any fault)
    // every descriptor is invalidated rather than exposing tentative state.
    assign active_stage_id = stage_ready_for_compute
        ? published_stage_id_q : 4'd0;
    assign active_image_version = stage_ready_for_compute
        ? published_image_version_q : 32'd0;
    assign active_stage_kind = stage_ready_for_compute ? stage_kind_q : 1'b0;
    assign active_matrix_count = stage_ready_for_compute ? matrix_count_q : 2'd0;
    assign active_matrix0_sources = stage_ready_for_compute
        ? matrix0_sources_q : 10'd0;
    assign active_matrix0_row_tiles = stage_ready_for_compute
        ? matrix0_row_tiles_q : 6'd0;
    assign active_matrix1_sources = stage_ready_for_compute
        ? matrix1_sources_q : 10'd0;
    assign active_matrix1_row_tiles = stage_ready_for_compute
        ? matrix1_row_tiles_q : 6'd0;
    assign active_param_tiles = stage_ready_for_compute ? param_tiles_q : 6'd0;
    assign active_uses_sigmoid_table = stage_ready_for_compute
        ? uses_sigmoid_table_q : 1'b0;
    assign active_sigmoid_table_select = stage_ready_for_compute
        ? sigmoid_table_select_q : 3'd0;

    assign raw_loader_busy = raw_load_busy;
    assign raw_loader_done = raw_load_done;
    assign raw_loader_error = raw_load_error;
    assign raw_loader_timeout = raw_load_timeout;
    assign raw_loader_abort_drain = (state_q == S_FATAL) && raw_load_busy;

    assign weight_req_ready = native_accept_enable;
    assign param_req_ready = native_accept_enable && !weight_req_valid;
    assign weight_rsp_valid = (adapter_state_q == A_WEIGHT_RESPONSE);
    assign weight_rsp_data = weight_rsp_data_q;
    assign weight_rsp_tag = weight_rsp_tag_q;
    assign weight_rsp_error = weight_rsp_error_q;

    assign param_rsp_valid = (adapter_state_q == A_PARAM_RESPONSE);
    assign param_rsp_data = param_buffer_q;
    assign param_rsp_kind = param_rsp_kind_q;
    assign param_rsp_bits = param_rsp_bits_q;
    assign param_rsp_tag = param_rsp_tag_q;
    assign param_rsp_error = param_rsp_error_q;

    assign lut_cfg_valid = (adapter_state_q == A_LUT_SEND);
    assign lut_cfg_stage_id = {1'b0, lut_table_q};
    assign lut_cfg_addr = lut_table_addr_q;
    assign lut_cfg_data = lut_word_q[lut_lane_q*8 +: 8];

    assign raw_rd_en = (adapter_state_q == A_WEIGHT_REQ) ||
                       (adapter_state_q == A_PARAM_REQ) ||
                       (adapter_state_q == A_LUT_REQ);
    assign raw_rd_addr = (adapter_state_q == A_WEIGHT_REQ)
        ? weight_word_addr_q[CACHE_ADDR_WIDTH-1:2]
        : (adapter_state_q == A_PARAM_REQ)
                ? current_param_word[CACHE_ADDR_WIDTH-1:2]
                : {{(CACHE_ADDR_WIDTH-9){1'b0}},
                   lut_word_index_q[8:2]};

    initial begin
        if (AXI_ADDR_WIDTH != 32)
            $error("memory_service_v5 requires AXI_ADDR_WIDTH=32");
        if (AXI_DATA_WIDTH != 64)
            $error("memory_service_v5 requires AXI_DATA_WIDTH=64");
        if (CACHE_ADDR_WIDTH != 15)
            $error("memory_service_v5 requires the 256 KiB cache");
        if (PARAM_BUFFER_BITS < `MODEL_V5_GSU_PARAM_BITS)
            $error("parameter response buffer is too narrow");
    end

    task automatic latch_fault;
        input [7:0] code;
        input [3:0] stage;
        input [31:0] detail;
        begin
            stage_ready_q <= 1'b0;
            if (!error_valid) begin
                error_valid <= 1'b1;
                error_code <= code;
                error_stage <= stage;
                error_detail <= detail;
            end
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            state_q <= S_EMPTY;
            stage_ready_q <= 1'b0;
            adapter_state_q <= A_IDLE;
            transaction_stage_id_q <= 4'd0;
            transaction_image_version_q <= 32'd0;
            published_stage_id_q <= 4'd0;
            published_image_version_q <= 32'd0;
            stage_load_done <= 1'b0;
            stage_load_error <= 1'b0;
            error_valid <= 1'b0;
            error_code <= ERR_NONE;
            error_stage <= 4'd0;
            error_detail <= 32'd0;
            stage_kind_q <= 1'b0;
            stage_dram_offset_q <= 32'd0;
            stage_transfer_bytes_q <= 32'd0;
            matrix_count_q         <= 2'd0;
            matrix0_word_offset_q  <= 32'd0;
            matrix0_sources_q      <= 10'd0;
            matrix0_row_tiles_q    <= 6'd0;
            matrix1_word_offset_q  <= 32'd0;
            matrix1_sources_q      <= 10'd0;
            matrix1_row_tiles_q    <= 6'd0;
            param_word_offset_q    <= 32'd0;
            param_record_words_q   <= 8'd0;
            param_response_bits_q  <= 14'd0;
            param_tiles_q          <= 6'd0;
            uses_sigmoid_table_q   <= 1'b0;
            sigmoid_table_select_q <= 3'd0;
            matrix0_dense_q <= 1'b0;
            transaction_base_q <= {AXI_ADDR_WIDTH{1'b0}};
            tentative_bitmap0_q <= 320'd0;
            tentative_bitmap1_q <= 320'd0;
            tentative_count0_q <= 9'd0;
            tentative_count1_q <= 9'd0;
            tentative_sparse_enable_q <= 1'b0;
            tentative_fallback_q <= 1'b0;
            resident_bitmap0_q <= 320'd0;
            resident_bitmap1_q <= 320'd0;
            resident_fallback_q <= 1'b0;
            lut_initialized_q <= 1'b0;
            epoch_base_addr_q <= {AXI_ADDR_WIDTH{1'b0}};
            epoch_image_version_q <= 32'd0;
            validation_matrix_q <= 1'b0;
            validation_index_q <= 9'd0;
            validation_count_q <= 9'd0;
            bitmap_shift_q <= 320'd0;
            scan_matrix_q <= 1'b0;
            scan_index_q <= 10'd0;
            run_start_q <= 10'd0;
            run_end_q <= 10'd0;
            run_length_q <= 10'd0;
            run_start_tile_product_q <= 16'd0;
            run_length_tile_product_q <= 16'd0;
            command_local_offset_q <= 32'd0;
            command_byte_count_q <= 32'd0;
            post_command_state_q <= S_EMPTY;
            command_bounds_valid_q <= 1'b0;
            planned_param_bytes_q <= 17'd0;
            planned_matrix0_bytes_q <= 20'd0;
            planned_matrix1_bytes_q <= 19'd0;
            load_src_addr_q <= {AXI_ADDR_WIDTH{1'b0}};
            load_dst_word_q <= {CACHE_ADDR_WIDTH{1'b0}};
            counting_stage_q <= 1'b0;
            counting_lut_q <= 1'b0;
            diag_load_active_q <= 1'b0;
            diag_planned_bytes <= 32'd0;
            diag_actual_bytes <= 32'd0;
            diag_dense_bytes <= 32'd0;
            diag_saved_bytes <= 32'd0;
            diag_union_count0 <= 9'd0;
            diag_union_count1 <= 9'd0;
            diag_copy_commands <= 16'd0;
            diag_ar_bursts <= 32'd0;
            diag_load_cycles <= 32'd0;
            diag_lut_actual_bytes <= 32'd0;
            weight_word_addr_q <= 32'd0;
            weight_request_detail_q <= 17'd0;
            weight_rsp_data_q      <= 256'd0;
            weight_rsp_tag_q       <= {TAG_WIDTH{1'b0}};
            weight_rsp_error_q     <= 1'b0;
            param_record_addr_q    <= 32'd0;
            param_request_tile_q   <= 6'd0;
            param_word_index_q     <= 8'd0;
            param_lane_q           <= 2'd0;
            param_wide_data_q      <= 256'd0;
            param_buffer_q         <= {PARAM_BUFFER_BITS{1'b0}};
            param_rsp_tag_q        <= {TAG_WIDTH{1'b0}};
            param_rsp_error_q      <= 1'b0;
            param_rsp_kind_q       <= 1'b0;
            param_rsp_bits_q       <= 14'd0;
            lut_word_index_q       <= 9'd0;
            lut_lane_q             <= 3'd0;
            lut_table_q            <= 3'd0;
            lut_table_addr_q       <= 8'd0;
            lut_word_q             <= 64'd0;
        end else begin
            stage_load_done <= 1'b0;
            stage_load_error <= 1'b0;

            if (diag_load_active_q)
                diag_load_cycles <= diag_load_cycles + 1'b1;
            if (m_axi_arvalid && m_axi_arready && counting_stage_q)
                diag_ar_bursts <= diag_ar_bursts + 1'b1;
            if (m_axi_rvalid && m_axi_rready && counting_stage_q)
                diag_actual_bytes <= diag_actual_bytes + 32'd8;
            if (m_axi_rvalid && m_axi_rready && counting_lut_q)
                diag_lut_actual_bytes <= diag_lut_actual_bytes + 32'd8;
            if (raw_load_done) begin
                counting_stage_q <= 1'b0;
                counting_lut_q <= 1'b0;
            end

            // clear_error cannot recover a reset-only fault.
            if (abort) begin
                if (diag_load_active_q)
                    stage_load_error <= 1'b1;
                diag_load_active_q <= 1'b0;
                diag_saved_bytes <= 32'd0;
                state_q <= S_FATAL;
                adapter_state_q <= A_IDLE;
                latch_fault(ERR_ABORT, transaction_stage_id_q, 32'd0);
            end else if ((state_q != S_EMPTY) && (state_q != S_FATAL) &&
                         ((parameter_base_addr != transaction_base_q) ||
                          (image_version != transaction_image_version_q))) begin
                if (diag_load_active_q)
                    stage_load_error <= 1'b1;
                diag_load_active_q <= 1'b0;
                state_q <= S_FATAL;
                adapter_state_q <= A_IDLE;
                latch_fault(ERR_EPOCH_IDENTITY, transaction_stage_id_q,
                            parameter_base_addr);
            end else begin
                case (state_q)
                    S_EMPTY: begin
                        if (plan_valid && plan_ready) begin
                            transaction_stage_id_q <= plan_stage_id;
                            transaction_image_version_q <= image_version;
                            transaction_base_q <= parameter_base_addr;
                            stage_kind_q <= table_stage_kind;
                            stage_dram_offset_q <= table_dram_byte_offset;
                            stage_transfer_bytes_q <= table_transfer_bytes;
                            matrix_count_q <= table_matrix_count;
                            matrix0_word_offset_q <= table_matrix0_word_offset;
                            matrix0_sources_q <= table_matrix0_sources;
                            matrix0_row_tiles_q <= table_matrix0_row_tiles;
                            matrix1_word_offset_q <= table_matrix1_word_offset;
                            matrix1_sources_q <= table_matrix1_sources;
                            matrix1_row_tiles_q <= table_matrix1_row_tiles;
                            param_word_offset_q <= table_param_word_offset;
                            param_record_words_q <= table_param_record_words;
                            param_response_bits_q <= table_param_response_bits;
                            param_tiles_q <= table_param_tiles;
                            uses_sigmoid_table_q <= table_uses_sigmoid_table;
                            sigmoid_table_select_q <= table_sigmoid_table_select;
                            matrix0_dense_q <= (plan_stage_id == 4'd0) ||
                                (plan_stage_id == 4'd3) ||
                                (plan_stage_id == 4'd6) ||
                                (plan_stage_id == 4'd9);
                            tentative_bitmap0_q <= plan_bitmap0;
                            tentative_bitmap1_q <= plan_bitmap1;
                            bitmap_shift_q <= plan_bitmap0;
                            tentative_count0_q <= plan_count0;
                            tentative_count1_q <= plan_count1;
                            tentative_sparse_enable_q <= plan_sparse_enable;
                            tentative_fallback_q <= plan_fallback_full;
                            resident_bitmap0_q <= 320'd0;
                            resident_bitmap1_q <= 320'd0;
                            resident_fallback_q <= 1'b0;
                            validation_matrix_q <= 1'b0;
                            validation_index_q <= 9'd0;
                            validation_count_q <= 9'd0;
                            diag_planned_bytes <= 32'd0;
                            diag_actual_bytes <= 32'd0;
                            diag_dense_bytes <= table_transfer_bytes;
                            diag_saved_bytes <= 32'd0;
                            diag_union_count0 <= plan_count0;
                            diag_union_count1 <= plan_count1;
                            diag_copy_commands <= 16'd0;
                            diag_ar_bursts <= 32'd0;
                            diag_load_cycles <= 32'd1;
                            diag_load_active_q <= 1'b1;

                            if (!table_stage_valid) begin
                                stage_load_error <= 1'b1;
                                diag_load_active_q <= 1'b0;
                                state_q <= S_FATAL;
                                latch_fault(ERR_STAGE_ID, plan_stage_id, 32'd0);
                            end else if (image_version !=
                                         `MODEL_V5_IMAGE_VERSION) begin
                                stage_load_error <= 1'b1;
                                diag_load_active_q <= 1'b0;
                                state_q <= S_FATAL;
                                latch_fault(ERR_IMAGE_VERSION, plan_stage_id,
                                            image_version);
                            end else if (parameter_base_addr[5:0] != 6'd0) begin
                                stage_load_error <= 1'b1;
                                diag_load_active_q <= 1'b0;
                                state_q <= S_FATAL;
                                latch_fault(ERR_BASE_ALIGNMENT, plan_stage_id,
                                            parameter_base_addr);
                            end else if (requested_image_end_33[32] ||
                                         requested_lut_end_33[32]) begin
                                stage_load_error <= 1'b1;
                                diag_load_active_q <= 1'b0;
                                state_q <= S_FATAL;
                                latch_fault(ERR_ADDRESS_OVERFLOW, plan_stage_id,
                                            parameter_base_addr);
                            end else if ((table_transfer_bytes == 0) ||
                                         table_transfer_bytes[2:0] ||
                                         (table_transfer_bytes > CACHE_WORDS*8)) begin
                                stage_load_error <= 1'b1;
                                diag_load_active_q <= 1'b0;
                                state_q <= S_FATAL;
                                latch_fault(ERR_STAGE_TOO_LARGE, plan_stage_id,
                                            table_transfer_bytes);
                            end else if ((plan_matrix_count != table_matrix_count) ||
                                         (plan_count0 > 9'd320) ||
                                         (plan_count1 > 9'd320)) begin
                                stage_load_error <= 1'b1;
                                diag_load_active_q <= 1'b0;
                                state_q <= S_FATAL;
                                latch_fault(ERR_PLAN, plan_stage_id,
                                            {12'd0, plan_matrix_count,
                                             plan_count1, plan_count0});
                            end else if (lut_initialized_q &&
                                         ((parameter_base_addr != epoch_base_addr_q) ||
                                          (image_version != epoch_image_version_q))) begin
                                stage_load_error <= 1'b1;
                                diag_load_active_q <= 1'b0;
                                state_q <= S_FATAL;
                                latch_fault(ERR_EPOCH_IDENTITY, plan_stage_id,
                                            parameter_base_addr);
                            end else begin
                                state_q <= S_VALIDATE;
                            end
                        end
                    end

                    S_VALIDATE: begin
                        if (validation_bit &&
                            ({1'b0, validation_index_q} >= validation_source_limit)) begin
                            stage_load_error <= 1'b1;
                            diag_load_active_q <= 1'b0;
                            state_q <= S_FATAL;
                            latch_fault(ERR_PLAN, transaction_stage_id_q,
                                {12'd0, validation_matrix_q,
                                 validation_index_q, validation_source_limit});
                        end else if (validation_index_q == 9'd319) begin
                            validation_count_q <= validation_count_next[8:0];
                            state_q <= S_VALIDATE_DONE;
                        end else begin
                            validation_index_q <= validation_index_q + 1'b1;
                            validation_count_q <= validation_count_next[8:0];
                            bitmap_shift_q <= {1'b0, bitmap_shift_q[319:1]};
                        end
                    end

                    S_VALIDATE_DONE: begin
                            if (validation_count_q !=
                                validation_expected_count) begin
                                stage_load_error <= 1'b1;
                                diag_load_active_q <= 1'b0;
                                state_q <= S_FATAL;
                                latch_fault(ERR_PLAN, transaction_stage_id_q,
                                    {4'd0, validation_matrix_q,
                                     validation_expected_count,
                                     validation_count_q, 9'd0});
                            end else if (!validation_matrix_q) begin
                                validation_matrix_q <= 1'b1;
                                validation_index_q <= 9'd0;
                                validation_count_q <= 9'd0;
                                bitmap_shift_q <= tentative_bitmap1_q;
                                state_q <= S_VALIDATE;
                            end else if (tentative_fallback_q != expected_fallback) begin
                                stage_load_error <= 1'b1;
                                diag_load_active_q <= 1'b0;
                                state_q <= S_FATAL;
                                latch_fault(ERR_PLAN, transaction_stage_id_q,
                                    {28'd0, tentative_fallback_q,
                                     expected_fallback,
                                     tentative_sparse_enable_q,
                                     matrix0_dense_q});
                            end else begin
                                // Pipeline the three narrow geometry products
                                // before their byte-count addition.  This is a
                                // diagnostic/accounting path and the two extra
                                // pre-DMA cycles do not change the transaction
                                // or publication contract.
                                state_q <= S_PLAN_BYTES_MUL;
                            end
                    end

                    S_PLAN_BYTES_MUL: begin
                        planned_param_bytes_q <=
                            {param_record_tile_product, 3'b000};
                        planned_matrix0_bytes_q <=
                            {matrix0_loaded_tile_product, 5'b00000};
                        planned_matrix1_bytes_q <=
                            {matrix1_loaded_tile_product, 5'b00000};
                        state_q <= S_PLAN_BYTES_COMMIT;
                    end

                    S_PLAN_BYTES_COMMIT: begin
                        diag_planned_bytes <= tentative_fallback_q
                            ? stage_transfer_bytes_q
                            : ({15'd0, planned_param_bytes_q} +
                               {12'd0, planned_matrix0_bytes_q} +
                               ((matrix_count_q >= 2)
                                    ? {13'd0, planned_matrix1_bytes_q}
                                    : 32'd0));
                        if (!lut_initialized_q) begin
                            epoch_base_addr_q <= transaction_base_q;
                            epoch_image_version_q <=
                                transaction_image_version_q;
                            state_q <= S_LUT_CMD;
                        end else begin
                            state_q <= S_PREPARE;
                        end
                    end

                    S_LUT_CMD: begin
                        if (raw_cmd_valid && raw_cmd_ready) begin
                            counting_lut_q <= 1'b1;
                            state_q <= S_LUT_LOAD;
                        end
                    end

                    S_LUT_LOAD: begin
                        if (raw_load_timeout) begin
                            stage_load_error <= 1'b1;
                            diag_load_active_q <= 1'b0;
                            state_q <= S_FATAL;
                            latch_fault(ERR_AXI_TIMEOUT, transaction_stage_id_q,
                                        raw_cmd_src_addr);
                        end else if (raw_load_done) begin
                            if (raw_load_error) begin
                                stage_load_error <= 1'b1;
                                diag_load_active_q <= 1'b0;
                                state_q <= S_FATAL;
                                latch_fault(ERR_AXI_LOAD, transaction_stage_id_q,
                                            raw_cmd_src_addr);
                            end else begin
                                adapter_state_q <= A_LUT_REQ;
                                lut_word_index_q <= 9'd0;
                                lut_lane_q <= 3'd0;
                                lut_table_q <= 3'd0;
                                lut_table_addr_q <= 8'd0;
                                state_q <= S_LUT_STREAM;
                            end
                        end
                    end

                    S_LUT_STREAM: begin
                        if ((adapter_state_q == A_LUT_SEND) && lut_cfg_ready &&
                            (lut_table_q == 3'd7) &&
                            (lut_table_addr_q == 8'd254)) begin
                            lut_initialized_q <= 1'b1;
                            state_q <= S_PREPARE;
                        end
                    end

                    S_PREPARE: begin
                        if (tentative_fallback_q) begin
                            command_local_offset_q <= 32'd0;
                            command_byte_count_q <= stage_transfer_bytes_q;
                            post_command_state_q <= S_PUBLISH;
                            state_q <= S_CMD_CHECK;
                        end else begin
                            scan_matrix_q <= 1'b0;
                            scan_index_q <= 10'd0;
                            bitmap_shift_q <= tentative_bitmap0_q;
                            state_q <= S_SCAN;
                        end
                    end

                    S_SCAN: begin
                        if (scan_index_q >= scan_sources) begin
                            if (!scan_matrix_q && (matrix_count_q >= 2)) begin
                                scan_matrix_q <= 1'b1;
                                scan_index_q <= 10'd0;
                                bitmap_shift_q <= tentative_bitmap1_q;
                            end else begin
                                state_q <= S_PARAM;
                            end
                        end else if (scan_dense) begin
                            run_length_q <= scan_sources;
                            scan_index_q <= scan_sources;
                            state_q <= S_DENSE_MUL;
                        end else if (!bitmap_shift_q[0]) begin
                            scan_index_q <= scan_index_q + 1'b1;
                            bitmap_shift_q <= {1'b0, bitmap_shift_q[319:1]};
                        end else begin
                            run_start_q <= scan_index_q;
                            run_end_q <= scan_index_q + 1'b1;
                            bitmap_shift_q <= {1'b0, bitmap_shift_q[319:1]};
                            state_q <= S_EXTEND;
                        end
                    end

                    S_EXTEND: begin
                        if ((run_end_q < scan_sources) && bitmap_shift_q[0]) begin
                            run_end_q <= run_end_q + 1'b1;
                            bitmap_shift_q <= {1'b0, bitmap_shift_q[319:1]};
                        end else begin
                            run_length_q <= run_end_q - run_start_q;
                            scan_index_q <= run_end_q;
                            state_q <= S_RUN_MUL;
                        end
                    end

                    S_RUN_MUL: begin
                        run_start_tile_product_q <=
                            run_start_q * scan_row_tiles;
                        run_length_tile_product_q <=
                            run_length_q * scan_row_tiles;
                        state_q <= S_RUN_COMMAND;
                    end

                    S_RUN_COMMAND: begin
                        command_local_offset_q <= scan_matrix_offset_bytes +
                            {11'd0, run_start_tile_product_q, 5'b00000};
                        command_byte_count_q <=
                            {11'd0, run_length_tile_product_q, 5'b00000};
                        post_command_state_q <= S_SCAN;
                        state_q <= S_CMD_CHECK;
                    end

                    S_DENSE_MUL: begin
                        run_length_tile_product_q <=
                            run_length_q * scan_row_tiles;
                        state_q <= S_DENSE_COMMAND;
                    end

                    S_DENSE_COMMAND: begin
                        command_local_offset_q <= scan_matrix_offset_bytes;
                        command_byte_count_q <=
                            {11'd0, run_length_tile_product_q, 5'b00000};
                        post_command_state_q <= S_SCAN;
                        state_q <= S_CMD_CHECK;
                    end

                    S_PARAM: begin
                        command_local_offset_q <= param_word_offset_q << 3;
                        command_byte_count_q <= param_transfer_bytes;
                        post_command_state_q <= S_PUBLISH;
                        state_q <= S_CMD_CHECK;
                    end

                    S_CMD_CHECK: begin
                        // Register the complete 33-bit source/cache bounds
                        // decision before it can select the fault path.  This
                        // keeps the address add/compare cone off the shared
                        // first-fault register enables while preserving a
                        // fail-closed cycle in which no DMA command is valid.
                        command_bounds_valid_q <= command_bounds_valid;
                        load_src_addr_q <= command_src_start_33[31:0];
                        load_dst_word_q <=
                            command_local_offset_q[CACHE_ADDR_WIDTH+2:3];
                        state_q <= S_CMD_DECIDE;
                    end

                    S_CMD_DECIDE: begin
                        if (!command_bounds_valid_q) begin
                            stage_load_error <= 1'b1;
                            diag_load_active_q <= 1'b0;
                            state_q <= S_FATAL;
                            latch_fault(ERR_ADDRESS_OVERFLOW,
                                        transaction_stage_id_q,
                                        command_local_offset_q);
                        end else begin
                            state_q <= S_CMD_SEND;
                        end
                    end

                    S_CMD_SEND: begin
                        if (raw_cmd_valid && raw_cmd_ready) begin
                            counting_stage_q <= 1'b1;
                            diag_copy_commands <= diag_copy_commands + 1'b1;
                            state_q <= S_CMD_WAIT;
                        end
                    end

                    S_CMD_WAIT: begin
                        if (raw_load_timeout) begin
                            stage_load_error <= 1'b1;
                            diag_load_active_q <= 1'b0;
                            state_q <= S_FATAL;
                            latch_fault(ERR_AXI_TIMEOUT, transaction_stage_id_q,
                                        load_src_addr_q);
                        end else if (raw_load_done) begin
                            if (raw_load_error) begin
                                stage_load_error <= 1'b1;
                                diag_load_active_q <= 1'b0;
                                state_q <= S_FATAL;
                                latch_fault(ERR_AXI_LOAD,
                                            transaction_stage_id_q,
                                            load_src_addr_q);
                            end else begin
                                state_q <= post_command_state_q;
                            end
                        end
                    end

                    S_PUBLISH: begin
                        if (diag_actual_bytes != diag_planned_bytes) begin
                            stage_load_error <= 1'b1;
                            diag_load_active_q <= 1'b0;
                            state_q <= S_FATAL;
                            latch_fault(ERR_TRAFFIC, transaction_stage_id_q,
                                        diag_actual_bytes);
                        end else begin
                            resident_bitmap0_q <= tentative_bitmap0_q;
                            resident_bitmap1_q <= tentative_bitmap1_q;
                            resident_fallback_q <= tentative_fallback_q;
                            published_stage_id_q <= transaction_stage_id_q;
                            published_image_version_q <=
                                transaction_image_version_q;
                            diag_saved_bytes <=
                                stage_transfer_bytes_q - diag_actual_bytes;
                            diag_load_active_q <= 1'b0;
                            stage_load_done <= 1'b1;
                            stage_ready_q <= 1'b1;
                            state_q <= S_READY;
                        end
                    end

                    S_READY: begin
                        if (stage_release_valid && stage_release_ready) begin
                            if (stage_release_id == transaction_stage_id_q) begin
                                resident_bitmap0_q <= 320'd0;
                                resident_bitmap1_q <= 320'd0;
                                resident_fallback_q <= 1'b0;
                                published_stage_id_q <= 4'd0;
                                published_image_version_q <= 32'd0;
                                stage_ready_q <= 1'b0;
                                state_q <= S_EMPTY;
                            end else begin
                                state_q <= S_FATAL;
                                latch_fault(ERR_STAGE_RELEASE,
                                            transaction_stage_id_q,
                                            {28'd0, stage_release_id});
                            end
                        end
                    end

                    S_FATAL: begin
                        // Sticky. The raw DMA drains an accepted burst with
                        // cache writes disabled by its asserted abort input.
                    end

                    default: begin
                        if (diag_load_active_q)
                            stage_load_error <= 1'b1;
                        diag_load_active_q <= 1'b0;
                        state_q <= S_FATAL;
                        latch_fault(ERR_PLAN, transaction_stage_id_q,
                                    32'hffff_ffff);
                    end
                endcase

                case (adapter_state_q)
                    A_IDLE: begin
                        if (weight_req_valid && weight_req_ready) begin
                            weight_rsp_tag_q <= weight_req_tag;
                            weight_rsp_error_q <= 1'b0;
                            weight_request_detail_q <=
                                {weight_req_matrix, weight_req_row_tile,
                                 weight_req_source};
                            if ((weight_req_matrix &&
                                 (matrix_count_q < 2)) ||
                                (weight_req_source >=
                                 selected_matrix_sources) ||
                                (weight_req_row_tile >=
                                 selected_matrix_tiles)) begin
                                weight_rsp_data_q <= 256'd0;
                                weight_rsp_error_q <= 1'b1;
                                adapter_state_q <= A_WEIGHT_RESPONSE;
                                state_q <= S_FATAL;
                                latch_fault(ERR_WEIGHT_REQUEST,
                                            transaction_stage_id_q,
                                            {15'd0, weight_req_matrix,
                                             weight_req_row_tile,
                                             weight_req_source});
                            end else if (!source_is_resident(
                                         weight_req_matrix,
                                         weight_req_source)) begin
                                weight_rsp_data_q <= 256'd0;
                                weight_rsp_error_q <= 1'b1;
                                adapter_state_q <= A_WEIGHT_RESPONSE;
                                state_q <= S_FATAL;
                                latch_fault(ERR_NOT_RESIDENT,
                                            transaction_stage_id_q,
                                            {15'd0, weight_req_matrix,
                                             weight_req_row_tile,
                                             weight_req_source});
                            end else begin
                                weight_word_addr_q <= requested_weight_word;
                                weight_rsp_data_q <= 256'd0;
                                adapter_state_q <= A_WEIGHT_CHECK;
                            end
                        end else if (param_req_valid && param_req_ready) begin
                            param_rsp_tag_q <= param_req_tag;
                            param_rsp_error_q <= 1'b0;
                            param_rsp_kind_q <= stage_kind_q;
                            param_rsp_bits_q <= param_response_bits_q;
                            param_request_tile_q <= param_req_row_tile;
                            if ((param_req_row_tile >= param_tiles_q) ||
                                (param_record_words_q == 0)) begin
                                param_rsp_error_q <= 1'b1;
                                adapter_state_q <= A_PARAM_RESPONSE;
                                state_q <= S_FATAL;
                                latch_fault(ERR_PARAM_REQUEST,
                                            transaction_stage_id_q,
                                            {26'd0, param_req_row_tile});
                            end else begin
                                param_record_addr_q <= requested_param_word;
                                param_word_index_q <= 8'd0;
                                param_lane_q <= requested_param_word[1:0];
                                adapter_state_q <= A_PARAM_CHECK;
                            end
                        end
                    end

                    A_WEIGHT_CHECK: begin
                        if ((weight_word_addr_q + 2'd3) >=
                            (stage_transfer_bytes_q >> 3)) begin
                            weight_rsp_data_q <= 256'd0;
                            weight_rsp_error_q <= 1'b1;
                            adapter_state_q <= A_WEIGHT_RESPONSE;
                            state_q <= S_FATAL;
                            latch_fault(ERR_WEIGHT_REQUEST,
                                        transaction_stage_id_q,
                                        {15'd0, weight_request_detail_q});
                        end else begin
                            adapter_state_q <= A_WEIGHT_REQ;
                        end
                    end

                    A_WEIGHT_REQ:
                        adapter_state_q <= A_WEIGHT_WAIT;

                    A_WEIGHT_WAIT: begin
                        if (raw_rvalid) begin
                            weight_rsp_data_q <= raw_rdata;
                            adapter_state_q <= A_WEIGHT_RESPONSE;
                        end
                    end

                    A_WEIGHT_RESPONSE: begin
                        if (weight_rsp_ready)
                            adapter_state_q <= A_IDLE;
                    end

                    A_PARAM_CHECK: begin
                        if ((param_record_addr_q + param_record_words_q) >
                            (stage_transfer_bytes_q >> 3)) begin
                            param_rsp_error_q <= 1'b1;
                            adapter_state_q <= A_PARAM_RESPONSE;
                            state_q <= S_FATAL;
                            latch_fault(ERR_PARAM_REQUEST,
                                        transaction_stage_id_q,
                                        {26'd0, param_request_tile_q});
                        end else begin
                            adapter_state_q <= A_PARAM_REQ;
                        end
                    end

                    A_PARAM_REQ:
                        adapter_state_q <= A_PARAM_WAIT;

                    A_PARAM_WAIT: begin
                        if (raw_rvalid) begin
                            param_wide_data_q <= raw_rdata;
                            adapter_state_q <= A_PARAM_CONSUME;
                        end
                    end

                    A_PARAM_CONSUME: begin
                        param_buffer_q[param_word_index_q*64 +: 64] <=
                            param_wide_data_q[param_lane_q*64 +: 64];
                        if (param_word_index_q ==
                            (param_record_words_q - 1'b1)) begin
                            adapter_state_q <= A_PARAM_RESPONSE;
                        end else begin
                            param_word_index_q <= param_word_index_q + 1'b1;
                            if (param_lane_q == 2'd3) begin
                                param_lane_q <= 2'd0;
                                adapter_state_q <= A_PARAM_REQ;
                            end else begin
                                param_lane_q <= param_lane_q + 1'b1;
                            end
                        end
                    end

                    A_PARAM_RESPONSE: begin
                        if (param_rsp_ready)
                            adapter_state_q <= A_IDLE;
                    end

                    A_LUT_REQ:
                        adapter_state_q <= A_LUT_WAIT;

                    A_LUT_WAIT: begin
                        if (raw_rvalid) begin
                            lut_word_q <=
                                raw_rdata[lut_word_index_q[1:0]*64 +: 64];
                            lut_lane_q <= 3'd0;
                            adapter_state_q <= A_LUT_SEND;
                        end
                    end

                    A_LUT_SEND: begin
                        if (lut_cfg_ready) begin
                            if ((lut_table_q == 3'd7) &&
                                (lut_table_addr_q == 8'd254)) begin
                                adapter_state_q <= A_IDLE;
                            end else begin
                                if (lut_table_addr_q == 8'd254) begin
                                    lut_table_addr_q <= 8'd0;
                                    lut_table_q <= lut_table_q + 1'b1;
                                end else begin
                                    lut_table_addr_q <=
                                        lut_table_addr_q + 1'b1;
                                end
                                if (lut_lane_q == 3'd7) begin
                                    lut_lane_q <= 3'd0;
                                    lut_word_index_q <=
                                        lut_word_index_q + 1'b1;
                                    adapter_state_q <= A_LUT_REQ;
                                end else begin
                                    lut_lane_q <= lut_lane_q + 1'b1;
                                end
                            end
                        end
                    end

                    default: begin
                        adapter_state_q <= A_IDLE;
                        state_q <= S_FATAL;
                        latch_fault(ERR_AXI_LOAD,
                                    transaction_stage_id_q,
                                    32'hffff_fffe);
                    end
                endcase
            end
        end
    end

    wire unused_clear_error = clear_error;
endmodule
