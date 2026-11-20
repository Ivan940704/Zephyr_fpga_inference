`timescale 1ns/1ps

// AXI4-Lite software/control boundary for the parameter-cache bring-up image.
//
// The slave implements one outstanding write and one outstanding read.  AW and
// W are captured independently, and B/R payloads are held until accepted.  All
// addresses are byte offsets in the assigned 4 KiB aperture (0x43c0_0000 in
// the PYNQ-Z1 block design).
module memory_service_axil #(
    parameter integer AXIL_ADDR_WIDTH = 12,
    parameter integer TAG_WIDTH       = 8
) (
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire [AXIL_ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  wire [2:0]                   s_axi_awprot,
    input  wire                         s_axi_awvalid,
    output wire                         s_axi_awready,
    input  wire [31:0]                  s_axi_wdata,
    input  wire [3:0]                   s_axi_wstrb,
    input  wire                         s_axi_wvalid,
    output wire                         s_axi_wready,
    output wire [1:0]                   s_axi_bresp,
    output wire                         s_axi_bvalid,
    input  wire                         s_axi_bready,
    input  wire [AXIL_ADDR_WIDTH-1:0]   s_axi_araddr,
    input  wire [2:0]                   s_axi_arprot,
    input  wire                         s_axi_arvalid,
    output wire                         s_axi_arready,
    output wire [31:0]                  s_axi_rdata,
    output wire [1:0]                   s_axi_rresp,
    output wire                         s_axi_rvalid,
    input  wire                         s_axi_rready,

    output reg  [31:0]                  parameter_base_addr,
    output reg  [31:0]                  image_version,
    output reg                          stage_req_valid,
    input  wire                         stage_req_ready,
    output reg  [3:0]                   stage_req_id,
    input  wire                         stage_load_done,
    input  wire                         stage_load_error,
    input  wire                         stage_ready_for_compute,
    input  wire                         lut_ready,
    output reg                          stage_release_valid,
    input  wire                         stage_release_ready,
    output reg  [3:0]                   stage_release_id,
    output reg                          abort_pulse,
    output reg                          clear_error_pulse,

    input  wire [2:0]                   cache_state,
    input  wire [3:0]                   active_stage_id,
    input  wire [31:0]                  active_image_version,
    input  wire                         service_error_valid,
    input  wire [7:0]                   service_error_code,
    input  wire [3:0]                   service_error_stage,
    input  wire [31:0]                  service_error_detail,
    input  wire                         raw_loader_busy,
    input  wire                         raw_loader_done,
    input  wire                         raw_loader_error,
    input  wire                         raw_loader_timeout,
    input  wire                         raw_loader_abort_drain,

    output reg                          weight_req_valid,
    input  wire                         weight_req_ready,
    output reg                          weight_req_matrix,
    output reg  [9:0]                   weight_req_source,
    output reg  [5:0]                   weight_req_row_tile,
    output reg  [TAG_WIDTH-1:0]         weight_req_tag,
    input  wire                         weight_rsp_valid,
    output wire                         weight_rsp_ready,
    input  wire [127:0]                 weight_rsp_data,
    input  wire [TAG_WIDTH-1:0]         weight_rsp_tag,
    input  wire                         weight_rsp_error,

    input  wire                         monitor_ar_fire,
    input  wire                         monitor_r_fire,
    input  wire                         monitor_lut_fire,

    output reg  [31:0]                  load_cycle_counter,
    output reg  [31:0]                  ar_burst_counter,
    output reg  [31:0]                  r_beat_counter,
    output reg  [31:0]                  lut_byte_counter,
    output reg                          wrapper_error_valid,
    output reg  [7:0]                   wrapper_error_code,
    output reg  [31:0]                  wrapper_error_detail,
    output wire [31:0]                  debug_status,
    output wire [31:0]                  debug_weight_status
);
    localparam [1:0] AXI_OKAY   = 2'b00;
    localparam [1:0] AXI_SLVERR = 2'b10;

    localparam [11:0] REG_HW_ID             = 12'h000;
    localparam [11:0] REG_ABI_VERSION       = 12'h004;
    localparam [11:0] REG_CAPABILITIES      = 12'h008;
    localparam [11:0] REG_CACHE_BYTES       = 12'h00c;
    localparam [11:0] REG_PARAMETER_BASE    = 12'h010;
    localparam [11:0] REG_IMAGE_VERSION     = 12'h014;
    localparam [11:0] REG_STAGE_ID          = 12'h018;
    localparam [11:0] REG_COMMAND           = 12'h01c;
    localparam [11:0] REG_STATUS            = 12'h020;
    localparam [11:0] REG_ACTIVE            = 12'h024;
    localparam [11:0] REG_ACTIVE_VERSION    = 12'h028;
    localparam [11:0] REG_SERVICE_ERROR     = 12'h02c;
    localparam [11:0] REG_SERVICE_DETAIL    = 12'h030;
    localparam [11:0] REG_WRAPPER_ERROR     = 12'h034;
    localparam [11:0] REG_WRAPPER_DETAIL    = 12'h038;
    localparam [11:0] REG_LOAD_CYCLES       = 12'h03c;
    localparam [11:0] REG_AR_BURSTS         = 12'h040;
    localparam [11:0] REG_R_BEATS           = 12'h044;
    localparam [11:0] REG_LUT_BYTES         = 12'h048;
    localparam [11:0] REG_RAW_STATUS        = 12'h04c;
    localparam [11:0] REG_WEIGHT_REQUEST    = 12'h050;
    localparam [11:0] REG_WEIGHT_COMMAND    = 12'h054;
    localparam [11:0] REG_WEIGHT_STATUS     = 12'h058;
    localparam [11:0] REG_WEIGHT_DATA0      = 12'h05c;
    localparam [11:0] REG_WEIGHT_DATA1      = 12'h060;
    localparam [11:0] REG_WEIGHT_DATA2      = 12'h064;
    localparam [11:0] REG_WEIGHT_DATA3      = 12'h068;

    localparam [7:0] WRAP_ERR_COMMAND       = 8'h80;
    localparam [7:0] WRAP_ERR_PRECONDITION  = 8'h81;
    localparam [7:0] WRAP_ERR_DEBUG_BUSY    = 8'h82;
    localparam [7:0] WRAP_ERR_BAD_ACCESS    = 8'h83;

    localparam [2:0] CACHE_INVALID = 3'd0;
    localparam [2:0] CACHE_COMMAND = 3'd1;
    localparam [2:0] CACHE_LOADING = 3'd2;
    localparam [2:0] CACHE_LUT     = 3'd3;
    localparam [2:0] CACHE_READY   = 3'd4;
    localparam [2:0] CACHE_ABORT   = 3'd6;

    reg [AXIL_ADDR_WIDTH-1:0] awaddr_q;
    reg                       aw_hold_q;
    reg [31:0]                wdata_q;
    reg [3:0]                 wstrb_q;
    reg                       w_hold_q;
    reg [1:0]                 bresp_q;
    reg                       bvalid_q;
    reg [31:0]                rdata_q;
    reg [1:0]                 rresp_q;
    reg                       rvalid_q;

    reg [3:0]                 stage_id_config_q;
    reg [31:0]                weight_request_config_q;
    reg                       weight_inflight_q;
    reg                       weight_rsp_slot_valid_q;
    reg [127:0]               weight_rsp_slot_data_q;
    reg [TAG_WIDTH-1:0]       weight_rsp_slot_tag_q;
    reg                       weight_rsp_slot_error_q;
    reg                       done_event_q;
    reg                       load_error_event_q;
    reg                       counter_active_q;
    reg                       abort_tracking_q;

    wire command_pending = stage_req_valid || stage_release_valid;
    wire stage_busy = command_pending || raw_loader_busy ||
        (cache_state == CACHE_COMMAND) || (cache_state == CACHE_LOADING) ||
        (cache_state == CACHE_LUT) || (cache_state == CACHE_ABORT);
    wire debug_busy = weight_req_valid || weight_inflight_q;
    wire debug_request_ready = weight_req_ready && !debug_busy &&
        !weight_rsp_slot_valid_q && stage_ready_for_compute &&
        !service_error_valid && !wrapper_error_valid;
    wire active_valid = (cache_state != CACHE_INVALID);

    assign s_axi_awready = !aw_hold_q && !bvalid_q;
    assign s_axi_wready  = !w_hold_q && !bvalid_q;
    assign s_axi_bresp   = bresp_q;
    assign s_axi_bvalid  = bvalid_q;
    assign s_axi_arready = !rvalid_q;
    assign s_axi_rdata   = rdata_q;
    assign s_axi_rresp   = rresp_q;
    assign s_axi_rvalid  = rvalid_q;
    assign weight_rsp_ready = !weight_rsp_slot_valid_q;

    assign debug_status = {
        13'b0,
        raw_loader_abort_drain,
        raw_loader_busy,
        weight_rsp_slot_error_q,
        weight_rsp_slot_valid_q,
        debug_busy,
        debug_request_ready,
        command_pending,
        cache_state,
        wrapper_error_valid,
        service_error_valid,
        lut_ready,
        stage_release_ready,
        stage_req_ready,
        load_error_event_q,
        done_event_q,
        stage_ready_for_compute,
        stage_busy
    };

    assign debug_weight_status = {
        16'b0,
        weight_rsp_slot_tag_q,
        4'b0,
        weight_rsp_slot_error_q,
        weight_rsp_slot_valid_q,
        debug_busy,
        debug_request_ready
    };

    function [31:0] merge_wstrb;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0] byte_strobes;
        integer lane;
        begin
            merge_wstrb = old_value;
            for (lane = 0; lane < 4; lane = lane + 1) begin
                if (byte_strobes[lane])
                    merge_wstrb[lane*8 +: 8] = new_value[lane*8 +: 8];
            end
        end
    endfunction

    task latch_wrapper_write_error;
        input [7:0] code;
        begin
            if (!wrapper_error_valid) begin
                wrapper_error_valid  <= 1'b1;
                wrapper_error_code   <= code;
                wrapper_error_detail <= {
                    1'b1, 3'b000, awaddr_q[11:0], wstrb_q, wdata_q[11:0]
                };
            end
        end
    endtask

    task latch_wrapper_read_error;
        input [AXIL_ADDR_WIDTH-1:0] bad_address;
        begin
            if (!wrapper_error_valid) begin
                wrapper_error_valid  <= 1'b1;
                wrapper_error_code   <= WRAP_ERR_BAD_ACCESS;
                wrapper_error_detail <= {
                    1'b0, 3'b000, bad_address[11:0], 16'b0
                };
            end
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            awaddr_q                 <= {AXIL_ADDR_WIDTH{1'b0}};
            aw_hold_q                <= 1'b0;
            wdata_q                  <= 32'b0;
            wstrb_q                  <= 4'b0;
            w_hold_q                 <= 1'b0;
            bresp_q                  <= AXI_OKAY;
            bvalid_q                 <= 1'b0;
            rdata_q                  <= 32'b0;
            rresp_q                  <= AXI_OKAY;
            rvalid_q                 <= 1'b0;
            parameter_base_addr      <= 32'b0;
            image_version            <= 32'b0;
            stage_id_config_q        <= 4'b0;
            stage_req_valid          <= 1'b0;
            stage_req_id             <= 4'b0;
            stage_release_valid      <= 1'b0;
            stage_release_id         <= 4'b0;
            abort_pulse              <= 1'b0;
            clear_error_pulse        <= 1'b0;
            weight_request_config_q  <= 32'b0;
            weight_req_valid         <= 1'b0;
            weight_req_matrix        <= 1'b0;
            weight_req_source        <= 10'b0;
            weight_req_row_tile      <= 6'b0;
            weight_req_tag           <= {TAG_WIDTH{1'b0}};
            weight_inflight_q        <= 1'b0;
            weight_rsp_slot_valid_q  <= 1'b0;
            weight_rsp_slot_data_q   <= 128'b0;
            weight_rsp_slot_tag_q    <= {TAG_WIDTH{1'b0}};
            weight_rsp_slot_error_q  <= 1'b0;
            done_event_q             <= 1'b0;
            load_error_event_q       <= 1'b0;
            counter_active_q         <= 1'b0;
            abort_tracking_q         <= 1'b0;
            load_cycle_counter       <= 32'b0;
            ar_burst_counter         <= 32'b0;
            r_beat_counter           <= 32'b0;
            lut_byte_counter         <= 32'b0;
            wrapper_error_valid      <= 1'b0;
            wrapper_error_code       <= 8'b0;
            wrapper_error_detail     <= 32'b0;
        end else begin
            abort_pulse       <= 1'b0;
            clear_error_pulse <= 1'b0;

            if (s_axi_awvalid && s_axi_awready) begin
                awaddr_q  <= s_axi_awaddr;
                aw_hold_q <= 1'b1;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                wdata_q  <= s_axi_wdata;
                wstrb_q  <= s_axi_wstrb;
                w_hold_q <= 1'b1;
            end
            if (bvalid_q && s_axi_bready)
                bvalid_q <= 1'b0;
            if (rvalid_q && s_axi_rready)
                rvalid_q <= 1'b0;

            if (stage_req_valid && stage_req_ready) begin
                stage_req_valid  <= 1'b0;
                counter_active_q <= 1'b1;
            end
            if (stage_release_valid && stage_release_ready)
                stage_release_valid <= 1'b0;

            if (weight_req_valid && weight_req_ready) begin
                weight_req_valid  <= 1'b0;
                weight_inflight_q <= 1'b1;
            end
            if (weight_rsp_valid && weight_rsp_ready) begin
                weight_rsp_slot_valid_q <= 1'b1;
                weight_rsp_slot_data_q  <= weight_rsp_data;
                weight_rsp_slot_tag_q   <= weight_rsp_tag;
                weight_rsp_slot_error_q <= weight_rsp_error;
                weight_inflight_q       <= 1'b0;
            end

            if (counter_active_q) begin
                load_cycle_counter <= load_cycle_counter + 1'b1;
                if (monitor_ar_fire)
                    ar_burst_counter <= ar_burst_counter + 1'b1;
                if (monitor_r_fire)
                    r_beat_counter <= r_beat_counter + 1'b1;
                if (monitor_lut_fire)
                    lut_byte_counter <= lut_byte_counter + 1'b1;
            end

            if (stage_load_done) begin
                counter_active_q   <= 1'b0;
                abort_tracking_q   <= 1'b0;
            end
            if (stage_load_error) begin
                counter_active_q   <= 1'b0;
            end
            if (abort_tracking_q && !raw_loader_busy &&
                (cache_state == CACHE_INVALID)) begin
                counter_active_q <= 1'b0;
                abort_tracking_q <= 1'b0;
            end

            // Complete a write only after independently captured AW and W are
            // both present.  The response remains asserted under backpressure.
            if (aw_hold_q && w_hold_q && !bvalid_q) begin
                aw_hold_q <= 1'b0;
                w_hold_q  <= 1'b0;
                bresp_q   <= AXI_OKAY;
                bvalid_q  <= 1'b1;

                if (awaddr_q[1:0] != 2'b00) begin
                    bresp_q <= AXI_SLVERR;
                    latch_wrapper_write_error(WRAP_ERR_BAD_ACCESS);
                end else begin
                    case (awaddr_q[11:0])
                        REG_PARAMETER_BASE: begin
                            if ((cache_state != CACHE_INVALID) || stage_busy ||
                                service_error_valid) begin
                                bresp_q <= AXI_SLVERR;
                                latch_wrapper_write_error(WRAP_ERR_PRECONDITION);
                            end else begin
                                parameter_base_addr <= merge_wstrb(
                                    parameter_base_addr, wdata_q, wstrb_q);
                            end
                        end

                        REG_IMAGE_VERSION: begin
                            if ((cache_state != CACHE_INVALID) || stage_busy ||
                                service_error_valid) begin
                                bresp_q <= AXI_SLVERR;
                                latch_wrapper_write_error(WRAP_ERR_PRECONDITION);
                            end else begin
                                image_version <= merge_wstrb(
                                    image_version, wdata_q, wstrb_q);
                            end
                        end

                        REG_STAGE_ID: begin : write_stage_id
                            reg [31:0] merged_stage_id;
                            merged_stage_id = merge_wstrb(
                                {28'b0, stage_id_config_q}, wdata_q, wstrb_q);
                            if (command_pending || (|merged_stage_id[31:4])) begin
                                bresp_q <= AXI_SLVERR;
                                latch_wrapper_write_error(WRAP_ERR_PRECONDITION);
                            end else begin
                                stage_id_config_q <= merged_stage_id[3:0];
                            end
                        end

                        REG_COMMAND: begin
                            if (wstrb_q != 4'b0001) begin
                                bresp_q <= AXI_SLVERR;
                                latch_wrapper_write_error(WRAP_ERR_COMMAND);
                            end else begin
                                case (wdata_q)
                                    32'h0000_0001: begin // START
                                        if (!stage_req_ready || stage_busy ||
                                            (cache_state != CACHE_INVALID) ||
                                            service_error_valid ||
                                            wrapper_error_valid || debug_busy ||
                                            weight_rsp_slot_valid_q) begin
                                            bresp_q <= AXI_SLVERR;
                                            latch_wrapper_write_error(
                                                WRAP_ERR_PRECONDITION);
                                        end else begin
                                            stage_req_id        <= stage_id_config_q;
                                            stage_req_valid     <= 1'b1;
                                            done_event_q        <= 1'b0;
                                            load_error_event_q  <= 1'b0;
                                            counter_active_q    <= 1'b0;
                                            abort_tracking_q    <= 1'b0;
                                            load_cycle_counter  <= 32'b0;
                                            ar_burst_counter    <= 32'b0;
                                            r_beat_counter      <= 32'b0;
                                            lut_byte_counter    <= 32'b0;
                                        end
                                    end

                                    32'h0000_0002: begin // RELEASE
                                        if (!stage_release_ready ||
                                            command_pending || debug_busy ||
                                            weight_rsp_slot_valid_q ||
                                            wrapper_error_valid ||
                                            service_error_valid) begin
                                            bresp_q <= AXI_SLVERR;
                                            latch_wrapper_write_error(
                                                WRAP_ERR_PRECONDITION);
                                        end else begin
                                            stage_release_id    <= stage_id_config_q;
                                            stage_release_valid <= 1'b1;
                                        end
                                    end

                                    32'h0000_0004: begin // ABORT
                                        abort_pulse             <= 1'b1;
                                        stage_req_valid         <= 1'b0;
                                        stage_release_valid     <= 1'b0;
                                        weight_req_valid        <= 1'b0;
                                        weight_inflight_q       <= 1'b0;
                                        weight_rsp_slot_valid_q <= 1'b0;
                                        abort_tracking_q        <=
                                            counter_active_q || stage_busy;
                                    end

                                    32'h0000_0008: begin // CLEAR_ERROR
                                        if (stage_busy || debug_busy ||
                                            raw_loader_busy) begin
                                            bresp_q <= AXI_SLVERR;
                                            latch_wrapper_write_error(
                                                WRAP_ERR_PRECONDITION);
                                        end else begin
                                            clear_error_pulse    <= 1'b1;
                                            wrapper_error_valid  <= 1'b0;
                                            wrapper_error_code   <= 8'b0;
                                            wrapper_error_detail <= 32'b0;
                                        end
                                    end

                                    32'h0000_0010: begin // CLEAR_EVENTS
                                        if (stage_busy || debug_busy ||
                                            raw_loader_busy) begin
                                            bresp_q <= AXI_SLVERR;
                                            latch_wrapper_write_error(
                                                WRAP_ERR_PRECONDITION);
                                        end else begin
                                            done_event_q        <= 1'b0;
                                            load_error_event_q  <= 1'b0;
                                            counter_active_q    <= 1'b0;
                                            abort_tracking_q    <= 1'b0;
                                            load_cycle_counter  <= 32'b0;
                                            ar_burst_counter    <= 32'b0;
                                            r_beat_counter      <= 32'b0;
                                            lut_byte_counter    <= 32'b0;
                                        end
                                    end

                                    default: begin
                                        bresp_q <= AXI_SLVERR;
                                        latch_wrapper_write_error(
                                            WRAP_ERR_COMMAND);
                                    end
                                endcase
                            end
                        end

                        REG_WEIGHT_REQUEST: begin : write_weight_request
                            reg [31:0] merged_weight_request;
                            merged_weight_request = merge_wstrb(
                                weight_request_config_q, wdata_q, wstrb_q);
                            if (debug_busy ||
                                (|merged_weight_request[5:1]) ||
                                (|merged_weight_request[23:22])) begin
                                bresp_q <= AXI_SLVERR;
                                latch_wrapper_write_error(WRAP_ERR_DEBUG_BUSY);
                            end else begin
                                weight_request_config_q <= merged_weight_request;
                            end
                        end

                        REG_WEIGHT_COMMAND: begin
                            if (wstrb_q != 4'b0001) begin
                                bresp_q <= AXI_SLVERR;
                                latch_wrapper_write_error(WRAP_ERR_COMMAND);
                            end else if (wdata_q == 32'h0000_0001) begin
                                if (!debug_request_ready) begin
                                    bresp_q <= AXI_SLVERR;
                                    latch_wrapper_write_error(
                                        WRAP_ERR_DEBUG_BUSY);
                                end else begin
                                    weight_req_matrix   <=
                                        weight_request_config_q[0];
                                    weight_req_source   <=
                                        weight_request_config_q[15:6];
                                    weight_req_row_tile <=
                                        weight_request_config_q[21:16];
                                    weight_req_tag      <=
                                        weight_request_config_q[31:24];
                                    weight_req_valid    <= 1'b1;
                                end
                            end else if (wdata_q == 32'h0000_0002) begin
                                if (!weight_rsp_slot_valid_q) begin
                                    bresp_q <= AXI_SLVERR;
                                    latch_wrapper_write_error(
                                        WRAP_ERR_DEBUG_BUSY);
                                end else begin
                                    weight_rsp_slot_valid_q <= 1'b0;
                                    weight_rsp_slot_error_q <= 1'b0;
                                end
                            end else begin
                                bresp_q <= AXI_SLVERR;
                                latch_wrapper_write_error(WRAP_ERR_COMMAND);
                            end
                        end

                        default: begin
                            bresp_q <= AXI_SLVERR;
                            latch_wrapper_write_error(WRAP_ERR_BAD_ACCESS);
                        end
                    endcase
                end
            end

            // Reads are decoded only on AR handshake.  RDATA/RRESP then remain
            // unchanged until RREADY consumes the response.
            if (s_axi_arvalid && s_axi_arready) begin
                rdata_q  <= 32'b0;
                rresp_q  <= AXI_OKAY;
                rvalid_q <= 1'b1;
                if (s_axi_araddr[1:0] != 2'b00) begin
                    rresp_q <= AXI_SLVERR;
                    latch_wrapper_read_error(s_axi_araddr);
                end else begin
                    case (s_axi_araddr[11:0])
                        REG_HW_ID:          rdata_q <= 32'h5a4d_454d;
                        REG_ABI_VERSION:    rdata_q <= 32'h0001_0000;
                        REG_CAPABILITIES:   rdata_q <= 32'h070f_100c;
                        REG_CACHE_BYTES:    rdata_q <= 32'h0004_0000;
                        REG_PARAMETER_BASE: rdata_q <= parameter_base_addr;
                        REG_IMAGE_VERSION:  rdata_q <= image_version;
                        REG_STAGE_ID:       rdata_q <= {28'b0, stage_id_config_q};
                        REG_STATUS:         rdata_q <= debug_status;
                        REG_ACTIVE:         rdata_q <= {
                            27'b0, active_valid, active_stage_id};
                        REG_ACTIVE_VERSION: rdata_q <= active_image_version;
                        REG_SERVICE_ERROR:  rdata_q <= {
                            service_error_valid, 19'b0,
                            service_error_stage, service_error_code};
                        REG_SERVICE_DETAIL: rdata_q <= service_error_detail;
                        REG_WRAPPER_ERROR:  rdata_q <= {
                            wrapper_error_valid, 23'b0, wrapper_error_code};
                        REG_WRAPPER_DETAIL: rdata_q <= wrapper_error_detail;
                        REG_LOAD_CYCLES:    rdata_q <= load_cycle_counter;
                        REG_AR_BURSTS:      rdata_q <= ar_burst_counter;
                        REG_R_BEATS:        rdata_q <= r_beat_counter;
                        REG_LUT_BYTES:      rdata_q <= lut_byte_counter;
                        REG_RAW_STATUS:     rdata_q <= {
                            26'b0, counter_active_q, raw_loader_timeout,
                            raw_loader_error, raw_loader_done,
                            raw_loader_abort_drain, raw_loader_busy};
                        REG_WEIGHT_REQUEST: rdata_q <= weight_request_config_q;
                        REG_WEIGHT_STATUS:  rdata_q <= debug_weight_status;
                        REG_WEIGHT_DATA0:   rdata_q <= weight_rsp_slot_data_q[31:0];
                        REG_WEIGHT_DATA1:   rdata_q <= weight_rsp_slot_data_q[63:32];
                        REG_WEIGHT_DATA2:   rdata_q <= weight_rsp_slot_data_q[95:64];
                        REG_WEIGHT_DATA3:   rdata_q <= weight_rsp_slot_data_q[127:96];
                        default: begin
                            rresp_q <= AXI_SLVERR;
                            latch_wrapper_read_error(s_axi_araddr);
                        end
                    endcase
                end
            end

            // Hardware event set has priority over a simultaneous software
            // CLEAR_EVENTS write, so a one-cycle completion pulse is never
            // lost at the AXI-Lite boundary.
            if (stage_load_done)
                done_event_q <= 1'b1;
            if (stage_load_error)
                load_error_event_q <= 1'b1;
        end
    end
endmodule
