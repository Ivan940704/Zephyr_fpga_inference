`timescale 1ns/1ps
`include "memory/model_memory_v4_map.vh"

// Sequential-v4 parameter memory service.
//
// One unchanged memory.v instance provides a 256 KiB, 64-bit cache and a
// read-only AXI master. The first legal stage request after reset loads and
// streams the image-global 8 x 255-byte sigmoid section, then loads the
// requested stage in full. Later stages reuse the configured PE LUT.
//
// Compute requests are serialized. A weight response is built from two cache
// words and a parameter response from 91 (GSU) or 18 (projection) words. A
// held response must be consumed before another request is accepted. Any error
// is sticky and reset-only.
module memory_service #(
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

    input  wire                           stage_req_valid,
    output wire                           stage_req_ready,
    input  wire [3:0]                     stage_req_id,
    output reg                            stage_load_done,
    output reg                            stage_load_error,
    output wire                           stage_ready_for_compute,
    output wire                           lut_ready,

    input  wire                           stage_release_valid,
    output wire                           stage_release_ready,
    input  wire [3:0]                     stage_release_id,

    output wire [2:0]                     cache_state,
    output reg  [3:0]                     active_stage_id,
    output reg  [31:0]                    active_image_version,

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
    output wire [127:0]                   weight_rsp_data,
    output wire [TAG_WIDTH-1:0]           weight_rsp_tag,
    output wire                           weight_rsp_error,

    input  wire                           param_req_valid,
    output wire                           param_req_ready,
    input  wire [5:0]                     param_req_row_tile,
    input  wire [TAG_WIDTH-1:0]           param_req_tag,
    output wire                           param_rsp_valid,
    input  wire                           param_rsp_ready,
    output wire [5791:0]                  param_rsp_data,
    output wire                           param_rsp_kind,
    output wire [12:0]                    param_rsp_bits,
    output wire [TAG_WIDTH-1:0]           param_rsp_tag,
    output wire                           param_rsp_error,

    // In v4, stage_id[2:0] is table select and bit 3 is zero.
    output wire                           lut_cfg_valid,
    input  wire                           lut_cfg_ready,
    output wire [3:0]                     lut_cfg_stage_id,
    output wire [7:0]                     lut_cfg_addr,
    output wire [7:0]                     lut_cfg_data,

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
    localparam integer PARAM_BUFFER_BITS = 5824; // 91 x 64-bit words

    localparam [2:0] CACHE_EMPTY         = 3'd0;
    localparam [2:0] CACHE_LUT_COMMAND   = 3'd1;
    localparam [2:0] CACHE_LUT_LOADING   = 3'd2;
    localparam [2:0] CACHE_LUT_STREAM    = 3'd3;
    localparam [2:0] CACHE_STAGE_COMMAND = 3'd4;
    localparam [2:0] CACHE_STAGE_LOADING = 3'd5;
    localparam [2:0] CACHE_READY         = 3'd6;
    localparam [2:0] CACHE_FATAL         = 3'd7;

    localparam [3:0] ADAPTER_IDLE            = 4'd0;
    localparam [3:0] ADAPTER_WEIGHT_CHECK    = 4'd1;
    localparam [3:0] ADAPTER_WEIGHT_LO_REQ   = 4'd2;
    localparam [3:0] ADAPTER_WEIGHT_LO_WAIT  = 4'd3;
    localparam [3:0] ADAPTER_WEIGHT_HI_REQ   = 4'd4;
    localparam [3:0] ADAPTER_WEIGHT_HI_WAIT  = 4'd5;
    localparam [3:0] ADAPTER_WEIGHT_RESPONSE = 4'd6;
    localparam [3:0] ADAPTER_PARAM_CHECK     = 4'd7;
    localparam [3:0] ADAPTER_PARAM_REQ       = 4'd8;
    localparam [3:0] ADAPTER_PARAM_WAIT      = 4'd9;
    localparam [3:0] ADAPTER_PARAM_RESPONSE  = 4'd10;
    localparam [3:0] ADAPTER_LUT_REQ         = 4'd11;
    localparam [3:0] ADAPTER_LUT_WAIT        = 4'd12;
    localparam [3:0] ADAPTER_LUT_SEND        = 4'd13;

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

    reg [2:0] cache_state_q;
    reg [3:0] adapter_state_q;

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
    wire [12:0] table_param_response_bits;
    wire [5:0] table_param_tiles;
    wire table_uses_sigmoid_table;
    wire [2:0] table_sigmoid_table_select;

    model_memory_v4_table stage_table (
        .stage_id(stage_req_id),
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
    reg [12:0] param_response_bits_q;
    reg [5:0] param_tiles_q;
    reg uses_sigmoid_table_q;
    reg [2:0] sigmoid_table_select_q;
    reg [AXI_ADDR_WIDTH-1:0] retained_stage_src_addr_q;

    reg lut_initialized_q;
    reg [AXI_ADDR_WIDTH-1:0] epoch_base_addr_q;
    reg [31:0] epoch_image_version_q;
    reg [AXI_ADDR_WIDTH-1:0] load_src_addr_q;
    reg [31:0] load_byte_count_q;

    wire [32:0] requested_stage_src_address =
        {1'b0, parameter_base_addr[31:0]} +
        {1'b0, table_dram_byte_offset};
    wire [32:0] requested_lut_src_address =
        {1'b0, parameter_base_addr[31:0]} +
        {1'b0, `MODEL_V4_GLOBAL_SIGMOID_LUT_DRAM_OFFSET};

    wire raw_cmd_valid = (cache_state_q == CACHE_LUT_COMMAND) ||
                         (cache_state_q == CACHE_STAGE_COMMAND);
    wire raw_cmd_ready;
    wire raw_load_busy;
    wire raw_load_done;
    wire raw_load_error;
    wire raw_load_timeout;
    wire raw_rd_en;
    wire [CACHE_ADDR_WIDTH-1:0] raw_rd_addr;
    wire [AXI_DATA_WIDTH-1:0] raw_rdata;
    wire raw_rvalid;

    assign raw_loader_busy        = raw_load_busy;
    assign raw_loader_done        = raw_load_done;
    assign raw_loader_error       = raw_load_error;
    assign raw_loader_timeout     = raw_load_timeout;
    assign raw_loader_abort_drain =
        (cache_state_q == CACHE_FATAL) && raw_load_busy;

    memory #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .BRAM_ADDR_WIDTH(CACHE_ADDR_WIDTH),
        .MAX_BURST_BEATS(MAX_BURST_BEATS),
        .TIMEOUT_CYCLES(LOAD_TIMEOUT_CYCLES),
        .ENABLE_PE_WRITES(0)
    ) raw_cache (
        .clk(clk),
        .rst_n(rst_n),
        .abort(abort || (cache_state_q == CACHE_FATAL)),
        .cmd_valid(raw_cmd_valid),
        .cmd_ready(raw_cmd_ready),
        .cmd_src_addr(load_src_addr_q),
        .cmd_dst_word_addr({CACHE_ADDR_WIDTH{1'b0}}),
        .cmd_byte_count(load_byte_count_q),
        .load_busy(raw_load_busy),
        .load_done(raw_load_done),
        .load_error(raw_load_error),
        .load_timeout(raw_load_timeout),
        .pe_rd_en(raw_rd_en),
        .pe_addr(raw_rd_addr),
        .pe_rdata(raw_rdata),
        .pe_rvalid(raw_rvalid),
        .pe_wr_en(1'b0),
        .pe_wdata({AXI_DATA_WIDTH{1'b0}}),
        .pe_wstrb({(AXI_DATA_WIDTH/8){1'b0}}),
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

    reg [31:0] weight_word_addr_q;
    reg [16:0] weight_request_detail_q;
    reg [63:0] weight_lower_q;
    reg [127:0] weight_rsp_data_q;
    reg [TAG_WIDTH-1:0] weight_rsp_tag_q;
    reg weight_rsp_error_q;

    reg [31:0] param_record_addr_q;
    reg [5:0] param_request_tile_q;
    reg [7:0] param_word_index_q;
    reg [PARAM_BUFFER_BITS-1:0] param_buffer_q;
    reg [TAG_WIDTH-1:0] param_rsp_tag_q;
    reg param_rsp_error_q;
    reg param_rsp_kind_q;
    reg [12:0] param_rsp_bits_q;

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
        ((requested_weight_product + {26'd0, weight_req_row_tile}) << 1);
    wire [31:0] requested_param_word = param_word_offset_q +
        ({26'd0, param_req_row_tile} * {24'd0, param_record_words_q});

    wire adapter_idle = (adapter_state_q == ADAPTER_IDLE);
    wire native_accept_enable = (cache_state_q == CACHE_READY) &&
                                !error_valid && adapter_idle &&
                                !stage_release_valid && !abort;

    assign stage_req_ready = (cache_state_q == CACHE_EMPTY) &&
                             !raw_load_busy && adapter_idle &&
                             !error_valid && !abort;
    assign stage_release_ready = (cache_state_q == CACHE_READY) &&
                                 adapter_idle && !error_valid && !abort;
    assign stage_ready_for_compute = (cache_state_q == CACHE_READY) &&
                                     !error_valid;
    assign lut_ready = lut_initialized_q;
    assign cache_state = cache_state_q;

    assign active_stage_kind = stage_kind_q;
    assign active_matrix_count = matrix_count_q;
    assign active_matrix0_sources = matrix0_sources_q;
    assign active_matrix0_row_tiles = matrix0_row_tiles_q;
    assign active_matrix1_sources = matrix1_sources_q;
    assign active_matrix1_row_tiles = matrix1_row_tiles_q;
    assign active_param_tiles = param_tiles_q;
    assign active_uses_sigmoid_table = uses_sigmoid_table_q;
    assign active_sigmoid_table_select = sigmoid_table_select_q;

    assign weight_req_ready = native_accept_enable;
    assign param_req_ready = native_accept_enable && !weight_req_valid;

    assign weight_rsp_valid = (adapter_state_q == ADAPTER_WEIGHT_RESPONSE);
    assign weight_rsp_data = weight_rsp_data_q;
    assign weight_rsp_tag = weight_rsp_tag_q;
    assign weight_rsp_error = weight_rsp_error_q;

    assign param_rsp_valid = (adapter_state_q == ADAPTER_PARAM_RESPONSE);
    assign param_rsp_data = param_buffer_q[5791:0];
    assign param_rsp_kind = param_rsp_kind_q;
    assign param_rsp_bits = param_rsp_bits_q;
    assign param_rsp_tag = param_rsp_tag_q;
    assign param_rsp_error = param_rsp_error_q;

    assign lut_cfg_valid = (adapter_state_q == ADAPTER_LUT_SEND);
    assign lut_cfg_stage_id = {1'b0, lut_table_q};
    assign lut_cfg_addr = lut_table_addr_q;
    assign lut_cfg_data = lut_word_q[lut_lane_q*8 +: 8];

    assign raw_rd_en = (adapter_state_q == ADAPTER_WEIGHT_LO_REQ) ||
                       (adapter_state_q == ADAPTER_WEIGHT_HI_REQ) ||
                       (adapter_state_q == ADAPTER_PARAM_REQ) ||
                       (adapter_state_q == ADAPTER_LUT_REQ);
    assign raw_rd_addr = (adapter_state_q == ADAPTER_WEIGHT_LO_REQ)
        ? weight_word_addr_q[CACHE_ADDR_WIDTH-1:0]
        : (adapter_state_q == ADAPTER_WEIGHT_HI_REQ)
            ? (weight_word_addr_q[CACHE_ADDR_WIDTH-1:0] + 1'b1)
            : (adapter_state_q == ADAPTER_PARAM_REQ)
                ? (param_record_addr_q[CACHE_ADDR_WIDTH-1:0] +
                   param_word_index_q)
                : {{(CACHE_ADDR_WIDTH-9){1'b0}}, lut_word_index_q};

    initial begin
        if (AXI_ADDR_WIDTH != 32)
            $error("memory_service requires AXI_ADDR_WIDTH=32");
        if (AXI_DATA_WIDTH != 64)
            $error("memory_service requires AXI_DATA_WIDTH=64");
        if (CACHE_ADDR_WIDTH != 15)
            $error("memory_service requires the 256 KiB cache");
        if (PARAM_BUFFER_BITS < `MODEL_V4_GSU_PARAM_BITS)
            $error("parameter response buffer is too narrow");
    end

    task latch_fault;
        input [7:0] code;
        input [3:0] stage;
        input [31:0] detail;
        begin
            if (!error_valid) begin
                error_valid  <= 1'b1;
                error_code   <= code;
                error_stage  <= stage;
                error_detail <= detail;
            end
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            cache_state_q          <= CACHE_EMPTY;
            adapter_state_q        <= ADAPTER_IDLE;
            active_stage_id        <= 4'd0;
            active_image_version   <= 32'd0;
            stage_load_done        <= 1'b0;
            stage_load_error       <= 1'b0;
            error_valid            <= 1'b0;
            error_code             <= ERR_NONE;
            error_stage            <= 4'd0;
            error_detail           <= 32'd0;
            stage_kind_q           <= 1'b0;
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
            param_response_bits_q  <= 13'd0;
            param_tiles_q          <= 6'd0;
            uses_sigmoid_table_q   <= 1'b0;
            sigmoid_table_select_q <= 3'd0;
            retained_stage_src_addr_q <= {AXI_ADDR_WIDTH{1'b0}};
            lut_initialized_q      <= 1'b0;
            epoch_base_addr_q      <= {AXI_ADDR_WIDTH{1'b0}};
            epoch_image_version_q  <= 32'd0;
            load_src_addr_q        <= {AXI_ADDR_WIDTH{1'b0}};
            load_byte_count_q      <= 32'd0;
            weight_word_addr_q     <= 32'd0;
            weight_request_detail_q <= 17'd0;
            weight_lower_q         <= 64'd0;
            weight_rsp_data_q      <= 128'd0;
            weight_rsp_tag_q       <= {TAG_WIDTH{1'b0}};
            weight_rsp_error_q     <= 1'b0;
            param_record_addr_q    <= 32'd0;
            param_request_tile_q   <= 6'd0;
            param_word_index_q     <= 8'd0;
            param_buffer_q         <= {PARAM_BUFFER_BITS{1'b0}};
            param_rsp_tag_q        <= {TAG_WIDTH{1'b0}};
            param_rsp_error_q      <= 1'b0;
            param_rsp_kind_q       <= 1'b0;
            param_rsp_bits_q       <= 13'd0;
            lut_word_index_q       <= 9'd0;
            lut_lane_q             <= 3'd0;
            lut_table_q            <= 3'd0;
            lut_table_addr_q       <= 8'd0;
            lut_word_q             <= 64'd0;
        end else begin
            stage_load_done  <= 1'b0;
            stage_load_error <= 1'b0;

            // clear_error is a compatibility no-op; only reset recovers.
            if (abort) begin
                cache_state_q    <= CACHE_FATAL;
                adapter_state_q  <= ADAPTER_IDLE;
                stage_load_error <= (cache_state_q != CACHE_EMPTY) &&
                                    (cache_state_q != CACHE_READY);
                latch_fault(ERR_ABORT, active_stage_id, 32'd0);
            end else begin
                case (cache_state_q)
                    CACHE_EMPTY: begin
                        if (stage_req_valid && stage_req_ready) begin
                            active_stage_id          <= stage_req_id;
                            active_image_version     <= image_version;
                            stage_kind_q             <= table_stage_kind;
                            stage_transfer_bytes_q  <= table_transfer_bytes;
                            matrix_count_q           <= table_matrix_count;
                            matrix0_word_offset_q    <= table_matrix0_word_offset;
                            matrix0_sources_q        <= table_matrix0_sources;
                            matrix0_row_tiles_q      <= table_matrix0_row_tiles;
                            matrix1_word_offset_q    <= table_matrix1_word_offset;
                            matrix1_sources_q        <= table_matrix1_sources;
                            matrix1_row_tiles_q      <= table_matrix1_row_tiles;
                            param_word_offset_q      <= table_param_word_offset;
                            param_record_words_q     <= table_param_record_words;
                            param_response_bits_q    <= table_param_response_bits;
                            param_tiles_q            <= table_param_tiles;
                            uses_sigmoid_table_q     <= table_uses_sigmoid_table;
                            sigmoid_table_select_q   <= table_sigmoid_table_select;
                            retained_stage_src_addr_q <=
                                requested_stage_src_address[31:0];

                            if (!table_stage_valid) begin
                                cache_state_q    <= CACHE_FATAL;
                                stage_load_error <= 1'b1;
                                latch_fault(ERR_STAGE_ID, stage_req_id, 32'd0);
                            end else if (image_version !=
                                         `MODEL_V4_IMAGE_VERSION) begin
                                cache_state_q    <= CACHE_FATAL;
                                stage_load_error <= 1'b1;
                                latch_fault(ERR_IMAGE_VERSION,
                                            stage_req_id, image_version);
                            end else if (parameter_base_addr[5:0] != 6'd0) begin
                                cache_state_q    <= CACHE_FATAL;
                                stage_load_error <= 1'b1;
                                latch_fault(ERR_BASE_ALIGNMENT,
                                            stage_req_id,
                                            parameter_base_addr);
                            end else if (requested_stage_src_address[32] ||
                                         (!lut_initialized_q &&
                                          requested_lut_src_address[32])) begin
                                cache_state_q    <= CACHE_FATAL;
                                stage_load_error <= 1'b1;
                                latch_fault(ERR_ADDRESS_OVERFLOW,
                                            stage_req_id,
                                            table_dram_byte_offset);
                            end else if ((table_transfer_bytes == 0) ||
                                         (table_transfer_bytes[2:0] != 3'd0) ||
                                         (table_transfer_bytes >
                                          (CACHE_WORDS * 8))) begin
                                cache_state_q    <= CACHE_FATAL;
                                stage_load_error <= 1'b1;
                                latch_fault(ERR_STAGE_TOO_LARGE,
                                            stage_req_id,
                                            table_transfer_bytes);
                            end else if (lut_initialized_q &&
                                         ((parameter_base_addr !=
                                           epoch_base_addr_q) ||
                                          (image_version !=
                                           epoch_image_version_q))) begin
                                cache_state_q    <= CACHE_FATAL;
                                stage_load_error <= 1'b1;
                                latch_fault(ERR_EPOCH_IDENTITY,
                                            stage_req_id,
                                            parameter_base_addr);
                            end else if (!lut_initialized_q) begin
                                epoch_base_addr_q     <= parameter_base_addr;
                                epoch_image_version_q <= image_version;
                                load_src_addr_q <=
                                    requested_lut_src_address[31:0];
                                load_byte_count_q <=
                                    `MODEL_V4_GLOBAL_SIGMOID_LUT_TRANSFER_BYTES;
                                cache_state_q <= CACHE_LUT_COMMAND;
                            end else begin
                                load_src_addr_q <=
                                    requested_stage_src_address[31:0];
                                load_byte_count_q <= table_transfer_bytes;
                                cache_state_q <= CACHE_STAGE_COMMAND;
                            end
                        end
                    end

                    CACHE_LUT_COMMAND: begin
                        if (raw_cmd_valid && raw_cmd_ready)
                            cache_state_q <= CACHE_LUT_LOADING;
                    end

                    CACHE_LUT_LOADING: begin
                        if (raw_load_timeout) begin
                            cache_state_q    <= CACHE_FATAL;
                            stage_load_error <= 1'b1;
                            latch_fault(ERR_AXI_TIMEOUT,
                                        active_stage_id,
                                        load_src_addr_q);
                        end else if (raw_load_done) begin
                            if (raw_load_error) begin
                                cache_state_q    <= CACHE_FATAL;
                                stage_load_error <= 1'b1;
                                latch_fault(ERR_AXI_LOAD,
                                            active_stage_id,
                                            load_src_addr_q);
                            end else begin
                                cache_state_q    <= CACHE_LUT_STREAM;
                                adapter_state_q  <= ADAPTER_LUT_REQ;
                                lut_word_index_q <= 9'd0;
                                lut_lane_q       <= 3'd0;
                                lut_table_q      <= 3'd0;
                                lut_table_addr_q <= 8'd0;
                            end
                        end
                    end

                    CACHE_LUT_STREAM: begin
                        if ((adapter_state_q == ADAPTER_LUT_SEND) &&
                            lut_cfg_ready &&
                            (lut_table_q == 3'd7) &&
                            (lut_table_addr_q == 8'd254)) begin
                            lut_initialized_q <= 1'b1;
                            load_src_addr_q <= retained_stage_src_addr_q;
                            load_byte_count_q <= stage_transfer_bytes_q;
                            cache_state_q <= CACHE_STAGE_COMMAND;
                        end
                    end

                    CACHE_STAGE_COMMAND: begin
                        if (raw_cmd_valid && raw_cmd_ready)
                            cache_state_q <= CACHE_STAGE_LOADING;
                    end

                    CACHE_STAGE_LOADING: begin
                        if (raw_load_timeout) begin
                            cache_state_q    <= CACHE_FATAL;
                            stage_load_error <= 1'b1;
                            latch_fault(ERR_AXI_TIMEOUT,
                                        active_stage_id,
                                        load_src_addr_q);
                        end else if (raw_load_done) begin
                            if (raw_load_error) begin
                                cache_state_q    <= CACHE_FATAL;
                                stage_load_error <= 1'b1;
                                latch_fault(ERR_AXI_LOAD,
                                            active_stage_id,
                                            load_src_addr_q);
                            end else begin
                                cache_state_q   <= CACHE_READY;
                                stage_load_done <= 1'b1;
                            end
                        end
                    end

                    CACHE_READY: begin
                        if (stage_release_valid && stage_release_ready) begin
                            if (stage_release_id == active_stage_id) begin
                                cache_state_q <= CACHE_EMPTY;
                            end else begin
                                cache_state_q <= CACHE_FATAL;
                                latch_fault(ERR_STAGE_RELEASE,
                                            active_stage_id,
                                            {28'd0, stage_release_id});
                            end
                        end
                    end

                    CACHE_FATAL: begin
                        // Sticky. memory.v drains an accepted burst because
                        // its abort input remains asserted.
                    end

                    default: begin
                        cache_state_q    <= CACHE_FATAL;
                        stage_load_error <= 1'b1;
                        latch_fault(ERR_AXI_LOAD,
                                    active_stage_id,
                                    32'hffff_ffff);
                    end
                endcase

                case (adapter_state_q)
                    ADAPTER_IDLE: begin
                        if (weight_req_valid && weight_req_ready) begin
                            weight_rsp_tag_q   <= weight_req_tag;
                            weight_rsp_error_q <= 1'b0;
                            weight_request_detail_q <=
                                {weight_req_matrix,
                                 weight_req_row_tile,
                                 weight_req_source};
                            if ((weight_req_matrix &&
                                 (matrix_count_q < 2)) ||
                                (weight_req_source >=
                                 selected_matrix_sources) ||
                                (weight_req_row_tile >=
                                 selected_matrix_tiles)) begin
                                weight_rsp_data_q  <= 128'd0;
                                weight_rsp_error_q <= 1'b1;
                                adapter_state_q <= ADAPTER_WEIGHT_RESPONSE;
                                cache_state_q   <= CACHE_FATAL;
                                latch_fault(ERR_WEIGHT_REQUEST,
                                            active_stage_id,
                                            {15'd0,
                                             weight_req_matrix,
                                             weight_req_row_tile,
                                             weight_req_source});
                            end else begin
                                weight_word_addr_q <= requested_weight_word;
                                adapter_state_q <= ADAPTER_WEIGHT_CHECK;
                            end
                        end else if (param_req_valid && param_req_ready) begin
                            param_rsp_tag_q      <= param_req_tag;
                            param_rsp_error_q    <= 1'b0;
                            param_rsp_kind_q     <= stage_kind_q;
                            param_rsp_bits_q     <= param_response_bits_q;
                            param_buffer_q       <= {PARAM_BUFFER_BITS{1'b0}};
                            param_request_tile_q <= param_req_row_tile;
                            if ((param_req_row_tile >= param_tiles_q) ||
                                (param_record_words_q == 0)) begin
                                param_rsp_error_q <= 1'b1;
                                adapter_state_q <= ADAPTER_PARAM_RESPONSE;
                                cache_state_q   <= CACHE_FATAL;
                                latch_fault(ERR_PARAM_REQUEST,
                                            active_stage_id,
                                            {26'd0, param_req_row_tile});
                            end else begin
                                param_record_addr_q <= requested_param_word;
                                param_word_index_q <= 8'd0;
                                adapter_state_q <= ADAPTER_PARAM_CHECK;
                            end
                        end
                    end

                    ADAPTER_WEIGHT_CHECK: begin
                        if ((weight_word_addr_q + 1'b1) >=
                            (stage_transfer_bytes_q >> 3)) begin
                            weight_rsp_data_q  <= 128'd0;
                            weight_rsp_error_q <= 1'b1;
                            adapter_state_q <= ADAPTER_WEIGHT_RESPONSE;
                            cache_state_q   <= CACHE_FATAL;
                            latch_fault(ERR_WEIGHT_REQUEST,
                                        active_stage_id,
                                        {15'd0, weight_request_detail_q});
                        end else begin
                            adapter_state_q <= ADAPTER_WEIGHT_LO_REQ;
                        end
                    end

                    ADAPTER_WEIGHT_LO_REQ:
                        adapter_state_q <= ADAPTER_WEIGHT_LO_WAIT;

                    ADAPTER_WEIGHT_LO_WAIT: begin
                        if (raw_rvalid) begin
                            weight_lower_q <= raw_rdata;
                            adapter_state_q <= ADAPTER_WEIGHT_HI_REQ;
                        end
                    end

                    ADAPTER_WEIGHT_HI_REQ:
                        adapter_state_q <= ADAPTER_WEIGHT_HI_WAIT;

                    ADAPTER_WEIGHT_HI_WAIT: begin
                        if (raw_rvalid) begin
                            weight_rsp_data_q <= {raw_rdata, weight_lower_q};
                            adapter_state_q <= ADAPTER_WEIGHT_RESPONSE;
                        end
                    end

                    ADAPTER_WEIGHT_RESPONSE: begin
                        if (weight_rsp_ready)
                            adapter_state_q <= ADAPTER_IDLE;
                    end

                    ADAPTER_PARAM_CHECK: begin
                        if ((param_record_addr_q + param_record_words_q) >
                            (stage_transfer_bytes_q >> 3)) begin
                            param_rsp_error_q <= 1'b1;
                            adapter_state_q <= ADAPTER_PARAM_RESPONSE;
                            cache_state_q   <= CACHE_FATAL;
                            latch_fault(ERR_PARAM_REQUEST,
                                        active_stage_id,
                                        {26'd0, param_request_tile_q});
                        end else begin
                            adapter_state_q <= ADAPTER_PARAM_REQ;
                        end
                    end

                    ADAPTER_PARAM_REQ:
                        adapter_state_q <= ADAPTER_PARAM_WAIT;

                    ADAPTER_PARAM_WAIT: begin
                        if (raw_rvalid) begin
                            param_buffer_q[param_word_index_q*64 +: 64]
                                <= raw_rdata;
                            if (param_word_index_q ==
                                (param_record_words_q - 1'b1)) begin
                                adapter_state_q <= ADAPTER_PARAM_RESPONSE;
                            end else begin
                                param_word_index_q <= param_word_index_q + 1'b1;
                                adapter_state_q <= ADAPTER_PARAM_REQ;
                            end
                        end
                    end

                    ADAPTER_PARAM_RESPONSE: begin
                        if (param_rsp_ready)
                            adapter_state_q <= ADAPTER_IDLE;
                    end

                    ADAPTER_LUT_REQ:
                        adapter_state_q <= ADAPTER_LUT_WAIT;

                    ADAPTER_LUT_WAIT: begin
                        if (raw_rvalid) begin
                            lut_word_q <= raw_rdata;
                            lut_lane_q <= 3'd0;
                            adapter_state_q <= ADAPTER_LUT_SEND;
                        end
                    end

                    ADAPTER_LUT_SEND: begin
                        if (lut_cfg_ready) begin
                            if ((lut_table_q == 3'd7) &&
                                (lut_table_addr_q == 8'd254)) begin
                                adapter_state_q <= ADAPTER_IDLE;
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
                                    adapter_state_q <= ADAPTER_LUT_REQ;
                                end else begin
                                    lut_lane_q <= lut_lane_q + 1'b1;
                                end
                            end
                        end
                    end

                    default: begin
                        adapter_state_q <= ADAPTER_IDLE;
                        cache_state_q <= CACHE_FATAL;
                        latch_fault(ERR_AXI_LOAD,
                                    active_stage_id,
                                    32'hffff_fffe);
                    end
                endcase
            end
        end
    end
endmodule
