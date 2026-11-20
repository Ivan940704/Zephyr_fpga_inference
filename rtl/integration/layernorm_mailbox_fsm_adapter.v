`timescale 1ns/1ps

// Frame-safe bridge between the global scheduler, the projection coefficient
// stream, and layernorm_mailbox.
//
// The mailbox advertises a committed subband slot before its 782 payload bytes
// have streamed into PL.  The global FSM has a stronger contract: its
// ps_subbands_valid input means that every byte is already resident for later
// feature reads.  This adapter therefore buffers and validates the complete
// frame before acknowledging the FSM.
module layernorm_mailbox_fsm_adapter #(
    parameter integer FRAME_ID_WIDTH = 16,
    parameter integer SB_PAYLOAD_BYTES = 782
) (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       abort,

    // Lifecycle taps from the global FSM/subsystem connection.
    input  wire                       fb_projection_start,
    input  wire                       frame_done,
    input  wire                       fsm_fb_result_valid,
    output wire                       fsm_fb_result_ready,
    output wire                       fsm_ps_subbands_valid,
    input  wire                       fsm_ps_subbands_ready,

    // Fullband projection coefficient stream (stage 2 only).
    input  wire                       fb_coefficient_valid,
    output wire                       fb_coefficient_ready,
    input  wire signed [7:0]          fb_coefficient_value,
    input  wire [8:0]                 fb_coefficient_index,
    input  wire                       fb_coefficient_last,

    // Fullband write side of layernorm_mailbox.
    output wire                       mailbox_fb_begin_valid,
    input  wire                       mailbox_fb_begin_ready,
    output wire [FRAME_ID_WIDTH-1:0]  mailbox_fb_begin_frame_id,
    input  wire                       mailbox_fb_begin_slot,
    output wire                       mailbox_fb_data_valid,
    input  wire                       mailbox_fb_data_ready,
    output wire [7:0]                 mailbox_fb_data,
    output wire                       mailbox_fb_data_last,
    input  wire                       mailbox_fb_published_valid,
    input  wire                       mailbox_fb_published_slot,
    input  wire [FRAME_ID_WIDTH-1:0]  mailbox_fb_published_frame_id,

    // Atomic committed-frame and byte-stream side of layernorm_mailbox.
    input  wire                       mailbox_ps_subbands_valid,
    output wire                       mailbox_ps_subbands_ready,
    input  wire                       mailbox_ps_subbands_slot,
    input  wire [FRAME_ID_WIDTH-1:0]  mailbox_ps_subbands_frame_id,
    input  wire                       mailbox_sb_data_valid,
    output wire                       mailbox_sb_data_ready,
    input  wire [7:0]                 mailbox_sb_data,
    input  wire [9:0]                 mailbox_sb_data_index,
    input  wire                       mailbox_sb_data_last,
    input  wire                       mailbox_sb_released_valid,
    input  wire                       mailbox_sb_released_slot,
    input  wire [FRAME_ID_WIDTH-1:0]  mailbox_sb_released_frame_id,

    // Synchronous random-read port for the next dense-feature dispatcher.
    // Data remains valid and stable until read_rsp_ready is asserted.
    input  wire                       sb_read_valid,
    output wire                       sb_read_ready,
    input  wire [9:0]                 sb_read_index,
    input  wire [FRAME_ID_WIDTH-1:0]  sb_read_frame_id,
    output reg                        sb_read_rsp_valid,
    input  wire                       sb_read_rsp_ready,
    output reg  signed [7:0]          sb_read_rsp_data,
    output reg                        sb_read_rsp_error,

    output wire [FRAME_ID_WIDTH-1:0]  current_frame_id,
    output wire                       fb_publish_complete,
    output wire                       sb_buffer_valid,
    output wire                       quiescent,
    output reg                        error_valid,
    output reg  [7:0]                 error_code,
    output reg  [15:0]                error_detail
);
    localparam [1:0] FB_IDLE         = 2'd0;
    localparam [1:0] FB_BEGIN        = 2'd1;
    localparam [1:0] FB_STREAM       = 2'd2;
    localparam [1:0] FB_WAIT_PUBLISH = 2'd3;

    localparam [7:0] ERR_NONE              = 8'h00;
    localparam [7:0] ERR_FB_START           = 8'h40;
    localparam [7:0] ERR_FB_COEFFICIENT     = 8'h41;
    localparam [7:0] ERR_FB_PUBLISH         = 8'h42;
    localparam [7:0] ERR_SB_FRAME           = 8'h43;
    localparam [7:0] ERR_SB_STREAM          = 8'h44;
    localparam [7:0] ERR_FRAME_DONE         = 8'h45;
    localparam [7:0] ERR_SB_READ            = 8'h46;
    localparam [7:0] ERR_SB_RELEASE         = 8'h47;

    reg [1:0] fb_state_q;
    reg [6:0] fb_count_q;
    reg       fb_slot_q;
    reg       fb_publish_complete_q;

    reg [FRAME_ID_WIDTH-1:0] frame_id_q;
    reg [7:0] sb_buffer_q [0:SB_PAYLOAD_BYTES-1];
    reg       sb_load_active_q;
    reg [9:0] sb_load_count_q;
    reg       sb_load_slot_q;
    reg [FRAME_ID_WIDTH-1:0] sb_load_frame_q;
    reg       sb_buffer_valid_q;
    reg       sb_release_pending_q;
    reg       sb_release_seen_q;
    reg       sb_handoff_seen_q;

    wire fb_begin_fire;
    wire fb_coefficient_identity_ok;
    wire fb_coefficient_fire;
    wire mailbox_fb_data_fire;
    wire mailbox_sb_begin_fire;
    wire mailbox_sb_data_fire;
    wire mailbox_sb_identity_ok;
    wire fsm_fb_result_fire;
    wire fsm_ps_subbands_fire;
    wire sb_read_fire;
    wire sb_read_identity_ok;

    assign current_frame_id = frame_id_q;
    assign fb_publish_complete = fb_publish_complete_q;
    assign sb_buffer_valid = sb_buffer_valid_q && sb_release_seen_q;
    assign quiescent = (fb_state_q == FB_IDLE) &&
        !fb_publish_complete_q && !sb_load_active_q &&
        !sb_buffer_valid_q && !sb_release_pending_q &&
        !sb_release_seen_q && !sb_handoff_seen_q &&
        !sb_read_rsp_valid;

    assign mailbox_fb_begin_valid = (fb_state_q == FB_BEGIN) &&
                                    !abort && !error_valid;
    assign mailbox_fb_begin_frame_id = frame_id_q;
    assign fb_begin_fire = mailbox_fb_begin_valid &&
                           mailbox_fb_begin_ready;

    assign fb_coefficient_identity_ok =
        (fb_coefficient_index == {2'b00, fb_count_q}) &&
        (fb_coefficient_last == (fb_count_q == 7'd63));
    assign fb_coefficient_ready = (fb_state_q == FB_STREAM) &&
        !abort && !error_valid &&
        (fb_coefficient_identity_ok ? mailbox_fb_data_ready : 1'b1);
    assign fb_coefficient_fire = fb_coefficient_valid &&
                                 fb_coefficient_ready;

    assign mailbox_fb_data_valid = (fb_state_q == FB_STREAM) &&
        fb_coefficient_valid && fb_coefficient_identity_ok &&
        !abort && !error_valid;
    assign mailbox_fb_data = fb_coefficient_value;
    assign mailbox_fb_data_last = (fb_count_q == 7'd63);
    assign mailbox_fb_data_fire = mailbox_fb_data_valid &&
                                  mailbox_fb_data_ready;

    assign fsm_fb_result_ready = fb_publish_complete_q &&
                                 !abort && !error_valid;
    assign fsm_fb_result_fire = fsm_fb_result_valid &&
                                fsm_fb_result_ready;

    assign mailbox_ps_subbands_ready = !abort && !error_valid &&
        !sb_load_active_q && !sb_buffer_valid_q &&
        !sb_release_pending_q;
    assign mailbox_sb_begin_fire = mailbox_ps_subbands_valid &&
                                   mailbox_ps_subbands_ready;
    assign mailbox_sb_data_ready = sb_load_active_q &&
                                   !abort && !error_valid;
    assign mailbox_sb_data_fire = mailbox_sb_data_valid &&
                                  mailbox_sb_data_ready;
    assign mailbox_sb_identity_ok =
        (mailbox_sb_data_index == sb_load_count_q) &&
        (mailbox_sb_data_last ==
            (sb_load_count_q == (SB_PAYLOAD_BYTES - 1)));

    assign fsm_ps_subbands_valid = sb_buffer_valid_q &&
                                   sb_release_seen_q &&
                                   !abort && !error_valid;
    assign fsm_ps_subbands_fire = fsm_ps_subbands_valid &&
                                  fsm_ps_subbands_ready;

    assign sb_read_ready = sb_buffer_valid_q && sb_release_seen_q &&
        !frame_done && !abort && !error_valid &&
        (!sb_read_rsp_valid || sb_read_rsp_ready);
    assign sb_read_fire = sb_read_valid && sb_read_ready;
    assign sb_read_identity_ok =
        (sb_read_frame_id == frame_id_q) &&
        (sb_read_index < SB_PAYLOAD_BYTES);

    initial begin
        if (FRAME_ID_WIDTH != 16) begin
            $display("Production adapter requires FRAME_ID_WIDTH=16");
            $finish;
        end
        if ((SB_PAYLOAD_BYTES < 1) || (SB_PAYLOAD_BYTES > 1024)) begin
            $display("SB_PAYLOAD_BYTES must be in the range 1..1024");
            $finish;
        end
    end

    task latch_error;
        input [7:0] code;
        input [15:0] detail;
        begin
            if (!error_valid) begin
                error_valid  <= 1'b1;
                error_code   <= code;
                error_detail <= detail;
            end
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            fb_state_q <= FB_IDLE;
            fb_count_q <= 7'd0;
            fb_slot_q <= 1'b0;
            fb_publish_complete_q <= 1'b0;
            frame_id_q <= {FRAME_ID_WIDTH{1'b0}};
            sb_load_active_q <= 1'b0;
            sb_load_count_q <= 10'd0;
            sb_load_slot_q <= 1'b0;
            sb_load_frame_q <= {FRAME_ID_WIDTH{1'b0}};
            sb_buffer_valid_q <= 1'b0;
            sb_release_pending_q <= 1'b0;
            sb_release_seen_q <= 1'b0;
            sb_handoff_seen_q <= 1'b0;
            sb_read_rsp_valid <= 1'b0;
            sb_read_rsp_data <= 8'sd0;
            sb_read_rsp_error <= 1'b0;
            error_valid <= 1'b0;
            error_code <= ERR_NONE;
            error_detail <= 16'd0;
        end else begin
            if (sb_read_rsp_valid && sb_read_rsp_ready)
                sb_read_rsp_valid <= 1'b0;

            // Abort discards all transient ownership and returns both the
            // adapter and mailbox frame sequences to zero.  A latched adapter
            // fault itself remains visible until coordinated rst_n.
            if (abort) begin
                fb_state_q <= FB_IDLE;
                fb_count_q <= 7'd0;
                fb_publish_complete_q <= 1'b0;
                frame_id_q <= {FRAME_ID_WIDTH{1'b0}};
                sb_load_active_q <= 1'b0;
                sb_load_count_q <= 10'd0;
                sb_buffer_valid_q <= 1'b0;
                sb_release_pending_q <= 1'b0;
                sb_release_seen_q <= 1'b0;
                sb_handoff_seen_q <= 1'b0;
                sb_read_rsp_valid <= 1'b0;
                sb_read_rsp_error <= 1'b0;
            end else begin
                if (fb_projection_start) begin
                    if ((fb_state_q != FB_IDLE) ||
                        fb_publish_complete_q) begin
                        latch_error(ERR_FB_START,
                            {7'd0, fb_coefficient_index});
                    end else begin
                        fb_state_q <= FB_BEGIN;
                        fb_count_q <= 7'd0;
                    end
                end

                if (fb_begin_fire) begin
                    fb_slot_q <= mailbox_fb_begin_slot;
                    fb_state_q <= FB_STREAM;
                end

                if (fb_coefficient_fire) begin
                    if (!fb_coefficient_identity_ok) begin
                        latch_error(ERR_FB_COEFFICIENT,
                            {fb_coefficient_last,
                             fb_count_q,
                             fb_coefficient_index[7:0]});
                    end else if (mailbox_fb_data_fire) begin
                        if (fb_count_q == 7'd63) begin
                            fb_state_q <= FB_WAIT_PUBLISH;
                        end else begin
                            fb_count_q <= fb_count_q + 1'b1;
                        end
                    end
                end

                if (mailbox_fb_published_valid) begin
                    if ((fb_state_q != FB_WAIT_PUBLISH) ||
                        (mailbox_fb_published_slot != fb_slot_q) ||
                        (mailbox_fb_published_frame_id != frame_id_q)) begin
                        latch_error(ERR_FB_PUBLISH,
                            mailbox_fb_published_frame_id[15:0]);
                    end else begin
                        fb_state_q <= FB_IDLE;
                        fb_publish_complete_q <= 1'b1;
                    end
                end

                if (fsm_fb_result_fire)
                    fb_publish_complete_q <= 1'b0;

                if (mailbox_sb_begin_fire) begin
                    if (mailbox_ps_subbands_frame_id != frame_id_q) begin
                        latch_error(ERR_SB_FRAME,
                            mailbox_ps_subbands_frame_id[15:0]);
                    end else begin
                        sb_load_active_q <= 1'b1;
                        sb_load_count_q <= 10'd0;
                        sb_load_slot_q <= mailbox_ps_subbands_slot;
                        sb_load_frame_q <= mailbox_ps_subbands_frame_id;
                        sb_release_seen_q <= 1'b0;
                    end
                end

                if (mailbox_sb_data_fire) begin
                    if (!mailbox_sb_identity_ok) begin
                        latch_error(ERR_SB_STREAM,
                            {6'd0, mailbox_sb_data_index});
                    end else begin
                        sb_buffer_q[mailbox_sb_data_index] <=
                            mailbox_sb_data;
                        if (sb_load_count_q ==
                            (SB_PAYLOAD_BYTES - 1)) begin
                            sb_load_active_q <= 1'b0;
                            sb_buffer_valid_q <= 1'b1;
                            sb_release_pending_q <= 1'b1;
                        end else begin
                            sb_load_count_q <= sb_load_count_q + 1'b1;
                        end
                    end
                end

                if (mailbox_sb_released_valid) begin
                    if (!sb_release_pending_q ||
                        (mailbox_sb_released_slot != sb_load_slot_q) ||
                        (mailbox_sb_released_frame_id != sb_load_frame_q)) begin
                        latch_error(ERR_SB_RELEASE,
                            mailbox_sb_released_frame_id[15:0]);
                    end else begin
                        sb_release_pending_q <= 1'b0;
                        sb_release_seen_q <= 1'b1;
                    end
                end

                if (fsm_ps_subbands_fire)
                    sb_handoff_seen_q <= 1'b1;

                if (sb_read_fire) begin
                    sb_read_rsp_valid <= 1'b1;
                    if (sb_read_identity_ok) begin
                        sb_read_rsp_data <=
                            sb_buffer_q[sb_read_index];
                        sb_read_rsp_error <= 1'b0;
                    end else begin
                        sb_read_rsp_data <= 8'sd0;
                        sb_read_rsp_error <= 1'b1;
                        latch_error(ERR_SB_READ,
                            {6'd0, sb_read_index});
                    end
                end

                if (frame_done) begin
                    if (!sb_handoff_seen_q) begin
                        latch_error(ERR_FRAME_DONE, frame_id_q[15:0]);
                    end else begin
                        frame_id_q <= frame_id_q + 1'b1;
                        sb_buffer_valid_q <= 1'b0;
                        sb_release_seen_q <= 1'b0;
                        sb_handoff_seen_q <= 1'b0;
                        sb_read_rsp_valid <= 1'b0;
                        sb_read_rsp_error <= 1'b0;
                    end
                end
            end
        end
    end
endmodule
