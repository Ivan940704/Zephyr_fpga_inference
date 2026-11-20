`timescale 1ns/1ps

// Single-frame dense-feature provider for the Sequential-v4 PE controller.
//
// The external fullband LayerNorm result arrives as one 64-byte AXI4-Stream
// packet.  Subband LayerNorm results are read from the frame-safe 782-byte
// mailbox adapter buffer.  Only the four dense GSU-input stages are legal:
//
//   stage 0: fullband, branch 0, context 0, 64 sources
//   stage 3: logical branch 1, contexts 0..3, 46 sources each
//   stage 6: logical branch 2, contexts 0..2, 94 sources each
//   stage 9: logical branch 3, contexts 0..1, 158 sources each
//
// The global FSM numbers subbands 0/1/2.  The frozen subsystem deliberately
// adds one before presenting controller feature requests because logical
// branch zero is reserved for the fullband context.
//
// One controller request is serviced at a time.  All protocol faults are
// sticky and require coordinated rst_n; abort only discards transient data.
module sequential_feature_dispatcher #(
    parameter integer FRAME_ID_WIDTH = 16
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         abort,
    input  wire [FRAME_ID_WIDTH-1:0]    current_frame_id,
    input  wire                         frame_start,
    input  wire                         frame_done,

    // One 64-byte fullband input packet, little-endian byte lanes.
    input  wire                         s_axis_fb_tvalid,
    output wire                         s_axis_fb_tready,
    input  wire [63:0]                  s_axis_fb_tdata,
    input  wire [7:0]                   s_axis_fb_tkeep,
    input  wire                         s_axis_fb_tlast,

    // Sequential-v4 dense-feature request/response contract.
    input  wire                         feature_req_valid,
    output wire                         feature_req_ready,
    input  wire [3:0]                   feature_req_stage_id,
    input  wire [1:0]                   feature_req_branch,
    input  wire [1:0]                   feature_req_context,
    input  wire [9:0]                   feature_req_source,
    input  wire [7:0]                   feature_req_tag,
    output wire                         feature_rsp_valid,
    input  wire                         feature_rsp_ready,
    output wire signed [7:0]            feature_rsp_value,
    output wire [7:0]                   feature_rsp_tag,
    output wire                         feature_rsp_error,

    // Read side of layernorm_mailbox_fsm_adapter.
    input  wire                         sb_buffer_valid,
    output wire                         sb_read_valid,
    input  wire                         sb_read_ready,
    output wire [9:0]                   sb_read_index,
    output wire [FRAME_ID_WIDTH-1:0]    sb_read_frame_id,
    input  wire                         sb_read_rsp_valid,
    output wire                         sb_read_rsp_ready,
    input  wire signed [7:0]            sb_read_rsp_data,
    input  wire                         sb_read_rsp_error,

    output wire                         fb_buffer_valid,
    output wire [FRAME_ID_WIDTH-1:0]    fb_buffer_frame_id,
    output wire                         frame_active,
    output wire                         busy,
    output reg                          error_valid,
    output reg  [7:0]                   error_code,
    output reg  [31:0]                  error_detail
);
    localparam [1:0] ST_IDLE    = 2'd0;
    localparam [1:0] ST_SB_REQ  = 2'd1;
    localparam [1:0] ST_SB_WAIT = 2'd2;
    localparam [1:0] ST_RSP     = 2'd3;

    localparam [7:0] ERR_NONE         = 8'h00;
    localparam [7:0] ERR_AXIS_KEEP    = 8'h50;
    localparam [7:0] ERR_AXIS_LAST    = 8'h51;
    localparam [7:0] ERR_FRAME_START  = 8'h52;
    localparam [7:0] ERR_FRAME_DONE   = 8'h53;
    localparam [7:0] ERR_FRAME_ID     = 8'h54;
    localparam [7:0] ERR_FEATURE_REQ  = 8'h55;
    localparam [7:0] ERR_SB_READ      = 8'h56;

    reg [1:0] state_q;
    reg [3:0] ingress_beat_q;
    reg [7:0] fb_buffer_q [0:63];
    reg fb_buffer_valid_q;
    reg [FRAME_ID_WIDTH-1:0] fb_buffer_frame_q;
    reg frame_active_q;

    reg [9:0] sb_index_q;
    reg [FRAME_ID_WIDTH-1:0] request_frame_q;
    reg [7:0] request_tag_q;
    reg signed [7:0] response_value_q;
    reg response_error_q;

    wire axis_fire;
    wire request_fire;
    wire response_fire;
    wire request_is_fb;
    wire request_is_sb0;
    wire request_is_sb1;
    wire request_is_sb2;
    wire request_supported;
    wire request_data_available;
    wire sb_read_fire;
    wire sb_read_rsp_fire;

    integer lane;

    function [9:0] map_sb_index;
        input [3:0] stage_id;
        input [1:0] context_id;
        input [9:0] source_id;
        reg [9:0] context_offset;
        begin
            case (stage_id)
                4'd3: begin
                    context_offset = (context_id * 10'd46);
                    map_sb_index = context_offset + source_id;
                end
                4'd6: begin
                    context_offset = (context_id * 10'd94);
                    map_sb_index = 10'd184 + context_offset + source_id;
                end
                4'd9: begin
                    context_offset = (context_id * 10'd158);
                    map_sb_index = 10'd466 + context_offset + source_id;
                end
                default: map_sb_index = 10'd0;
            endcase
        end
    endfunction

    task latch_error;
        input [7:0] code;
        input [31:0] detail;
        begin
            if (!error_valid) begin
                error_valid <= 1'b1;
                error_code <= code;
                error_detail <= detail;
            end
        end
    endtask

    assign request_is_fb = (feature_req_stage_id == 4'd0) &&
                           (feature_req_branch == 2'd0) &&
                           (feature_req_context == 2'd0) &&
                           (feature_req_source < 10'd64);
    assign request_is_sb0 = (feature_req_stage_id == 4'd3) &&
                            (feature_req_branch == 2'd1) &&
                            (feature_req_source < 10'd46);
    assign request_is_sb1 = (feature_req_stage_id == 4'd6) &&
                            (feature_req_branch == 2'd2) &&
                            (feature_req_context < 2'd3) &&
                            (feature_req_source < 10'd94);
    assign request_is_sb2 = (feature_req_stage_id == 4'd9) &&
                            (feature_req_branch == 2'd3) &&
                            (feature_req_context < 2'd2) &&
                            (feature_req_source < 10'd158);
    assign request_supported = request_is_fb || request_is_sb0 ||
                               request_is_sb1 || request_is_sb2;
    assign request_data_available = request_is_fb
        ? (fb_buffer_valid_q &&
           (fb_buffer_frame_q == current_frame_id))
        : sb_buffer_valid;

    assign s_axis_fb_tready = rst_n && !abort && !error_valid &&
                              !fb_buffer_valid_q && !frame_active_q;
    assign axis_fire = s_axis_fb_tvalid && s_axis_fb_tready;

    // Unsupported requests are accepted so that a deterministic sticky fault
    // is produced instead of allowing the PE controller to time out.
    assign feature_req_ready = rst_n && (state_q == ST_IDLE) &&
        !abort && !error_valid &&
        (!request_supported || request_data_available);
    assign request_fire = feature_req_valid && feature_req_ready;

    assign feature_rsp_valid = (state_q == ST_RSP) &&
                               !abort && !error_valid;
    assign feature_rsp_value = response_value_q;
    assign feature_rsp_tag = request_tag_q;
    assign feature_rsp_error = response_error_q;
    assign response_fire = feature_rsp_valid && feature_rsp_ready;

    assign sb_read_valid = (state_q == ST_SB_REQ) &&
                           !abort && !error_valid;
    assign sb_read_index = sb_index_q;
    assign sb_read_frame_id = request_frame_q;
    assign sb_read_fire = sb_read_valid && sb_read_ready;
    assign sb_read_rsp_ready = (state_q == ST_SB_WAIT) &&
                               !abort && !error_valid;
    assign sb_read_rsp_fire = sb_read_rsp_valid && sb_read_rsp_ready;

    assign fb_buffer_valid = fb_buffer_valid_q;
    assign fb_buffer_frame_id = fb_buffer_frame_q;
    assign frame_active = frame_active_q;
    assign busy = frame_active_q || fb_buffer_valid_q ||
                  (ingress_beat_q != 0) || (state_q != ST_IDLE);

    initial begin
        if (FRAME_ID_WIDTH != 16) begin
            $display("Production dispatcher requires FRAME_ID_WIDTH=16");
            $finish;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state_q <= ST_IDLE;
            ingress_beat_q <= 4'd0;
            fb_buffer_valid_q <= 1'b0;
            fb_buffer_frame_q <= {FRAME_ID_WIDTH{1'b0}};
            frame_active_q <= 1'b0;
            sb_index_q <= 10'd0;
            request_frame_q <= {FRAME_ID_WIDTH{1'b0}};
            request_tag_q <= 8'd0;
            response_value_q <= 8'sd0;
            response_error_q <= 1'b0;
            error_valid <= 1'b0;
            error_code <= ERR_NONE;
            error_detail <= 32'd0;
        end else begin
            if (abort) begin
                state_q <= ST_IDLE;
                ingress_beat_q <= 4'd0;
                fb_buffer_valid_q <= 1'b0;
                frame_active_q <= 1'b0;
                sb_index_q <= 10'd0;
                response_error_q <= 1'b0;
            end else begin
                if (fb_buffer_valid_q &&
                    (fb_buffer_frame_q != current_frame_id) &&
                    !frame_done) begin
                    latch_error(ERR_FRAME_ID,
                        {fb_buffer_frame_q[15:0],
                         current_frame_id[15:0]});
                end

                if (axis_fire) begin
                    if (s_axis_fb_tkeep != 8'hff) begin
                        ingress_beat_q <= 4'd0;
                        latch_error(ERR_AXIS_KEEP,
                            {20'd0, ingress_beat_q, s_axis_fb_tkeep});
                    end else if (s_axis_fb_tlast !=
                                 (ingress_beat_q == 4'd7)) begin
                        ingress_beat_q <= 4'd0;
                        latch_error(ERR_AXIS_LAST,
                            {27'd0, s_axis_fb_tlast,
                             ingress_beat_q});
                    end else begin
                        for (lane = 0; lane < 8; lane = lane + 1)
                            fb_buffer_q[ingress_beat_q*8 + lane] <=
                                s_axis_fb_tdata[lane*8 +: 8];
                        if (ingress_beat_q == 4'd0)
                            fb_buffer_frame_q <= current_frame_id;
                        if (ingress_beat_q == 4'd7) begin
                            ingress_beat_q <= 4'd0;
                            fb_buffer_valid_q <= 1'b1;
                        end else begin
                            ingress_beat_q <= ingress_beat_q + 1'b1;
                        end
                    end
                end

                if (frame_start) begin
                    if (!fb_buffer_valid_q || frame_active_q ||
                        (fb_buffer_frame_q != current_frame_id)) begin
                        latch_error(ERR_FRAME_START,
                            {fb_buffer_frame_q[15:0],
                             current_frame_id[15:0]});
                    end else begin
                        frame_active_q <= 1'b1;
                        request_frame_q <= current_frame_id;
                    end
                end

                if (request_fire) begin
                    request_tag_q <= feature_req_tag;
                    request_frame_q <= current_frame_id;
                    response_error_q <= 1'b0;
                    if (!request_supported || !frame_active_q) begin
                        latch_error(ERR_FEATURE_REQ,
                            {feature_req_stage_id,
                             feature_req_branch,
                             feature_req_context,
                             feature_req_source,
                             feature_req_tag, 6'd0});
                    end else if (request_is_fb) begin
                        response_value_q <=
                            fb_buffer_q[feature_req_source[5:0]];
                        state_q <= ST_RSP;
                    end else begin
                        sb_index_q <= map_sb_index(
                            feature_req_stage_id,
                            feature_req_context,
                            feature_req_source);
                        state_q <= ST_SB_REQ;
                    end
                end

                if (sb_read_fire)
                    state_q <= ST_SB_WAIT;

                if (sb_read_rsp_fire) begin
                    if (sb_read_rsp_error) begin
                        response_error_q <= 1'b1;
                        latch_error(ERR_SB_READ,
                            {6'd0, sb_index_q,
                             request_frame_q[15:0]});
                    end else begin
                        response_value_q <= sb_read_rsp_data;
                        response_error_q <= 1'b0;
                        state_q <= ST_RSP;
                    end
                end

                if (response_fire) begin
                    response_error_q <= 1'b0;
                    state_q <= ST_IDLE;
                end

                if (frame_done) begin
                    if (!frame_active_q || (state_q != ST_IDLE)) begin
                        latch_error(ERR_FRAME_DONE,
                            {28'd0, state_q, frame_active_q, 1'b0});
                    end else begin
                        frame_active_q <= 1'b0;
                        fb_buffer_valid_q <= 1'b0;
                    end
                end
            end
        end
    end
endmodule
