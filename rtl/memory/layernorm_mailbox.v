`timescale 1ns/1ps

// Keep the storage primitive in a deliberately small, canonical true-dual-port
// template.  Vivado 2018.3 will not infer BRAM when the two memory ports are
// embedded in the mailbox control processes, even though the accesses are
// mutually exclusive.  Isolating the RAM also makes the one-cycle read latency
// explicit to the surrounding protocol logic.
module zephyr_tdp_bram_1024x32 (
    input  wire        port_a_clk,
    input  wire        port_a_en,
    input  wire        port_a_we,
    input  wire [9:0]  port_a_addr,
    input  wire [31:0] port_a_wdata,
    output reg  [31:0] port_a_rdata,
    input  wire        port_b_clk,
    input  wire        port_b_en,
    input  wire        port_b_we,
    input  wire [9:0]  port_b_addr,
    input  wire [31:0] port_b_wdata,
    output reg  [31:0] port_b_rdata
);
    (* ram_style = "block" *) reg [31:0] ram [0:1023];

    always @(posedge port_a_clk) begin
        if (port_a_en) begin
            if (port_a_we)
                ram[port_a_addr] <= port_a_wdata;
            port_a_rdata <= ram[port_a_addr];
        end
    end

    always @(posedge port_b_clk) begin
        if (port_b_en) begin
            if (port_b_we)
                ram[port_b_addr] <= port_b_wdata;
            port_b_rdata <= ram[port_b_addr];
        end
    end
endmodule

// 4 KiB dual-slot mailbox for the PL -> PS -> PL LayerNorm round trip.
//
// Port A is the 1024 x 32-bit native BRAM interface connected to an AXI BRAM
// Controller on PS M_AXI_GP.  Port B is owned by this module: it fills one of
// two 64-byte fullband output slots and streams exactly 782 committed subband
// bytes back to PL.  Payload validity is carried only by slot/frame ownership;
// old BRAM contents are never interpreted as a valid frame after reset/error.
module layernorm_mailbox #(
    parameter integer FRAME_ID_WIDTH = 16,
    // PS scheduling jitter can exceed 10 ms during sustained Linux runs.
    // Keep the fail-closed timeout, but allow one second at the 100 MHz
    // production clock before declaring an abandoned slot.
    parameter integer TIMEOUT_CYCLES = 100000000
) (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       abort,
    input  wire                       clear_error,

    // Native BRAM Port A for the AXI BRAM Controller (word addressed).
    input  wire                       ps_bram_en,
    input  wire [3:0]                 ps_bram_we,
    input  wire [9:0]                 ps_bram_addr,
    input  wire [31:0]                ps_bram_wdata,
    output wire [31:0]                ps_bram_rdata,
    output reg                        ps_bram_rvalid,

    // PL publishes a 64-byte fullband projection frame.
    input  wire                       fb_begin_valid,
    output wire                       fb_begin_ready,
    input  wire [FRAME_ID_WIDTH-1:0]  fb_begin_frame_id,
    output wire                       fb_begin_slot,
    input  wire                       fb_data_valid,
    output wire                       fb_data_ready,
    input  wire [7:0]                 fb_data,
    input  wire                       fb_data_last,
    output reg                        fb_published_valid,
    output reg                        fb_published_slot,
    output reg  [FRAME_ID_WIDTH-1:0]  fb_published_frame_id,

    // Control events written through the accelerator AXI4-Lite registers.
    input  wire                       ps_fb_release_valid,
    output wire                       ps_fb_release_ready,
    input  wire                       ps_fb_release_slot,
    input  wire [FRAME_ID_WIDTH-1:0]  ps_fb_release_frame_id,

    input  wire                       ps_sb_claim_valid,
    output wire                       ps_sb_claim_ready,
    input  wire                       ps_sb_claim_slot,
    input  wire [FRAME_ID_WIDTH-1:0]  ps_sb_claim_frame_id,

    input  wire                       ps_sb_commit_valid,
    output wire                       ps_sb_commit_ready,
    input  wire                       ps_sb_commit_slot,
    input  wire [FRAME_ID_WIDTH-1:0]  ps_sb_commit_frame_id,
    output reg                        sb_committed_valid,
    output reg                        sb_committed_slot,
    output reg  [FRAME_ID_WIDTH-1:0]  sb_committed_frame_id,

    // Atomic frame availability followed by an ordered 782-byte stream:
    // SB0 contexts 0..3 (46 each), SB1 contexts 0..2 (94 each), then
    // SB2 contexts 0..1 (158 each).
    output wire                       ps_subbands_valid,
    input  wire                       ps_subbands_ready,
    output wire                       ps_subbands_slot,
    output wire [FRAME_ID_WIDTH-1:0]  ps_subbands_frame_id,
    output wire                       sb_data_valid,
    input  wire                       sb_data_ready,
    output wire [7:0]                 sb_data,
    output wire [9:0]                 sb_data_index,
    output wire                       sb_data_last,
    output reg                        sb_released_valid,
    output reg                        sb_released_slot,
    output reg  [FRAME_ID_WIDTH-1:0]  sb_released_frame_id,

    // Status for AXI4-Lite registers / debug.
    output wire [3:0]                 fb_slot_states,
    output wire [3:0]                 sb_slot_states,
    output reg  [FRAME_ID_WIDTH-1:0]  expected_fb_frame_id,
    output reg  [FRAME_ID_WIDTH-1:0]  expected_sb_frame_id,
    output reg  [FRAME_ID_WIDTH-1:0]  expected_consume_frame_id,
    output reg                        error_valid,
    output reg  [7:0]                 error_code,
    output reg                        error_slot,
    output reg  [FRAME_ID_WIDTH-1:0]  error_frame_id,
    output wire                       irq
);
    localparam [1:0] FB_FREE  = 2'd0;
    localparam [1:0] FB_FILL  = 2'd1;
    localparam [1:0] FB_READY = 2'd2;

    localparam [1:0] SB_FREE      = 2'd0;
    localparam [1:0] SB_PS_FILL   = 2'd1;
    localparam [1:0] SB_COMMITTED = 2'd2;
    localparam [1:0] SB_STREAMING = 2'd3;

    localparam [7:0] ERR_NONE             = 8'h00;
    localparam [7:0] ERR_FB_FRAME          = 8'h20;
    localparam [7:0] ERR_FB_LENGTH         = 8'h21;
    localparam [7:0] ERR_FB_RELEASE        = 8'h22;
    localparam [7:0] ERR_SB_CLAIM          = 8'h23;
    localparam [7:0] ERR_SB_WRITE_OWNER    = 8'h24;
    localparam [7:0] ERR_SB_COMMIT         = 8'h25;
    localparam [7:0] ERR_PORT_COLLISION    = 8'h26;
    localparam [7:0] ERR_SLOT_TIMEOUT      = 8'h27;
    localparam [7:0] ERR_SB_WRITE_STROBE   = 8'h28;

    localparam integer FB_SLOT0_WORD = 0;
    localparam integer FB_SLOT1_WORD = 16;
    localparam integer SB_SLOT0_WORD = 256;
    localparam integer SB_SLOT1_WORD = 512;
    localparam integer SB_TRANSFER_WORDS = 196; // 784 bytes, last two are zero
    localparam integer SB_PAYLOAD_BYTES = 782;

    reg [1:0] fb_state_q [0:1];
    reg [FRAME_ID_WIDTH-1:0] fb_frame_q [0:1];
    reg [31:0] fb_timeout_q [0:1];
    reg [1:0] sb_state_q [0:1];
    reg [FRAME_ID_WIDTH-1:0] sb_frame_q [0:1];
    reg [31:0] sb_timeout_q [0:1];
    // PS writes exactly 196 complete 32-bit transfer words.  A word bitmap is
    // sufficient to prove complete coverage without a 784-bit variable-index
    // byte scoreboard, and the final two pad bytes are shadowed separately so
    // commit never creates an asynchronous third BRAM read port.
    reg [195:0] sb_written_words_q [0:1];
    reg [15:0] sb_padding_q [0:1];

    reg fb_fill_active_q;
    reg fb_fill_slot_q;
    reg [6:0] fb_fill_count_q;
    reg [31:0] fb_pack_word_q;

    reg sb_stream_active_q;
    reg sb_stream_slot_q;
    reg [9:0] sb_stream_index_q;
    reg [1:0] sb_stream_lane_q;
    reg sb_read_pending_q;
    reg sb_word_valid_q;
    reg [31:0] sb_word_q;

    wire fb_slot0_free = (fb_state_q[0] == FB_FREE);
    wire fb_slot1_free = (fb_state_q[1] == FB_FREE);
    wire selected_fb_free_slot = fb_slot0_free ? 1'b0 : 1'b1;
    assign fb_begin_ready = !abort && !fb_fill_active_q && !sb_stream_active_q &&
                            (fb_slot0_free || fb_slot1_free);
    assign fb_begin_slot = selected_fb_free_slot;
    assign fb_data_ready = fb_fill_active_q && !abort;
    wire fb_data_fire = fb_data_valid && fb_data_ready;

    assign ps_fb_release_ready = !abort;
    assign ps_sb_claim_ready = !abort;
    assign ps_sb_commit_ready = !abort;

    wire sb_slot0_expected = (sb_state_q[0] == SB_COMMITTED) &&
                             (sb_frame_q[0] == expected_consume_frame_id);
    wire sb_slot1_expected = (sb_state_q[1] == SB_COMMITTED) &&
                             (sb_frame_q[1] == expected_consume_frame_id);
    wire selected_sb_slot = sb_slot0_expected ? 1'b0 : 1'b1;
    assign ps_subbands_valid = !abort && !fb_fill_active_q &&
                               !sb_stream_active_q &&
                               !ps_sb_claim_valid && !ps_sb_commit_valid &&
                               (sb_slot0_expected || sb_slot1_expected);
    assign ps_subbands_slot = selected_sb_slot;
    assign ps_subbands_frame_id = selected_sb_slot
        ? sb_frame_q[1] : sb_frame_q[0];

    assign sb_data_valid = sb_stream_active_q && sb_word_valid_q;
    assign sb_data = sb_word_q[sb_stream_lane_q*8 +: 8];
    assign sb_data_index = sb_stream_index_q;
    assign sb_data_last = (sb_stream_index_q == (SB_PAYLOAD_BYTES - 1));
    wire sb_data_fire = sb_data_valid && sb_data_ready;

    assign fb_slot_states = {fb_state_q[1], fb_state_q[0]};
    assign sb_slot_states = {sb_state_q[1], sb_state_q[0]};
    assign irq = error_valid || (fb_state_q[0] == FB_READY) ||
                 (fb_state_q[1] == FB_READY) ||
                 (sb_state_q[0] == SB_COMMITTED) ||
                 (sb_state_q[1] == SB_COMMITTED);

    wire ps_write_fire = ps_bram_en && (|ps_bram_we);
    wire ps_full_write = ps_write_fire && (&ps_bram_we);
    wire ps_read_fire = ps_bram_en && !(|ps_bram_we);
    wire ps_addr_in_sb0_payload =
        (ps_bram_addr >= SB_SLOT0_WORD) &&
        (ps_bram_addr < (SB_SLOT0_WORD + SB_TRANSFER_WORDS));
    wire ps_addr_in_sb1_payload =
        (ps_bram_addr >= SB_SLOT1_WORD) &&
        (ps_bram_addr < (SB_SLOT1_WORD + SB_TRANSFER_WORDS));
    wire ps_write_slot = ps_addr_in_sb1_payload;
    wire [9:0] ps_write_word_in_slot = ps_write_slot
        ? (ps_bram_addr - SB_SLOT1_WORD)
        : (ps_bram_addr - SB_SLOT0_WORD);
    wire ps_write_allowed =
        (ps_addr_in_sb0_payload && (sb_state_q[0] == SB_PS_FILL)) ||
        (ps_addr_in_sb1_payload && (sb_state_q[1] == SB_PS_FILL));
    wire ps_full_write_allowed = ps_full_write && ps_write_allowed;

    wire ps_read_fb0_collision = ps_read_fire &&
        (ps_bram_addr >= FB_SLOT0_WORD) &&
        (ps_bram_addr < (FB_SLOT0_WORD + 16)) &&
        (fb_state_q[0] == FB_FILL);
    wire ps_read_fb1_collision = ps_read_fire &&
        (ps_bram_addr >= FB_SLOT1_WORD) &&
        (ps_bram_addr < (FB_SLOT1_WORD + 16)) &&
        (fb_state_q[1] == FB_FILL);
    wire ps_read_sb0_collision = ps_read_fire &&
        (ps_bram_addr >= SB_SLOT0_WORD) &&
        (ps_bram_addr < (SB_SLOT0_WORD + SB_TRANSFER_WORDS)) &&
        ((sb_state_q[0] == SB_COMMITTED) ||
         (sb_state_q[0] == SB_STREAMING));
    wire ps_read_sb1_collision = ps_read_fire &&
        (ps_bram_addr >= SB_SLOT1_WORD) &&
        (ps_bram_addr < (SB_SLOT1_WORD + SB_TRANSFER_WORDS)) &&
        ((sb_state_q[1] == SB_COMMITTED) ||
         (sb_state_q[1] == SB_STREAMING));

    wire [9:0] fb_port_b_word = (fb_fill_slot_q ? FB_SLOT1_WORD : FB_SLOT0_WORD) +
                                fb_fill_count_q[6:2];
    wire [1:0] fb_port_b_lane = fb_fill_count_q[1:0];
    wire pl_read_enable = sb_stream_active_q && !sb_word_valid_q &&
                          !sb_read_pending_q;
    wire [9:0] pl_read_word =
        (sb_stream_slot_q ? SB_SLOT1_WORD : SB_SLOT0_WORD) +
        sb_stream_index_q[9:2];
    reg pl_read_valid_q;

    wire fb_word_write = fb_data_fire && (fb_port_b_lane == 2'd3);
    wire mailbox_port_a_en = ps_full_write_allowed || ps_read_fire;
    wire mailbox_port_b_en = fb_word_write || pl_read_enable;
    wire [9:0] mailbox_port_b_addr = fb_word_write
        ? fb_port_b_word : pl_read_word;
    wire [31:0] mailbox_port_b_wdata =
        {fb_data, fb_pack_word_q[23:0]};
    wire [31:0] mailbox_port_b_rdata;

    zephyr_tdp_bram_1024x32 mailbox_storage (
        .port_a_clk(clk),
        .port_a_en(mailbox_port_a_en),
        .port_a_we(ps_full_write_allowed),
        .port_a_addr(ps_bram_addr),
        .port_a_wdata(ps_bram_wdata),
        .port_a_rdata(ps_bram_rdata),
        .port_b_clk(clk),
        .port_b_en(mailbox_port_b_en),
        .port_b_we(fb_word_write),
        .port_b_addr(mailbox_port_b_addr),
        .port_b_wdata(mailbox_port_b_wdata),
        .port_b_rdata(mailbox_port_b_rdata)
    );

    initial begin
        if ((FRAME_ID_WIDTH < 1) || (FRAME_ID_WIDTH > 32))
            $error("FRAME_ID_WIDTH must be in the range 1..32");
        if (TIMEOUT_CYCLES < 0)
            $error("TIMEOUT_CYCLES must be zero (disabled) or positive");
    end

    // BRAM Port A response qualifier.  Storage and ownership gating are in the
    // canonical true-dual-port instance above.
    always @(posedge clk) begin
        if (!rst_n) begin
            ps_bram_rvalid <= 1'b0;
        end else begin
            ps_bram_rvalid <= ps_read_fire;
        end
    end

    // Four fullband bytes are packed before one complete Port B write.  A
    // registered qualifier aligns the canonical BRAM's one-cycle read output
    // with the subband stream controller.
    always @(posedge clk) begin
        if (!rst_n || abort) begin
            pl_read_valid_q <= 1'b0;
            fb_pack_word_q  <= 32'd0;
        end else begin
            pl_read_valid_q <= pl_read_enable;
            if (fb_data_fire) begin
                case (fb_port_b_lane)
                    2'd0: fb_pack_word_q[7:0]   <= fb_data;
                    2'd1: fb_pack_word_q[15:8]  <= fb_data;
                    2'd2: fb_pack_word_q[23:16] <= fb_data;
                    default: fb_pack_word_q <= 32'd0;
                endcase
            end
        end
    end

    task latch_fault;
        input [7:0] code;
        input slot;
        input [FRAME_ID_WIDTH-1:0] frame_id;
        begin
            if (!error_valid) begin
                error_valid    <= 1'b1;
                error_code     <= code;
                error_slot     <= slot;
                error_frame_id <= frame_id;
            end
        end
    endtask

    integer slot;
    reg fb_slot_progress;
    reg sb_slot_progress;
    always @(posedge clk) begin
        if (!rst_n) begin
            fb_state_q[0] <= FB_FREE;
            fb_state_q[1] <= FB_FREE;
            fb_frame_q[0] <= {FRAME_ID_WIDTH{1'b0}};
            fb_frame_q[1] <= {FRAME_ID_WIDTH{1'b0}};
            fb_timeout_q[0] <= 32'd0;
            fb_timeout_q[1] <= 32'd0;
            sb_state_q[0] <= SB_FREE;
            sb_state_q[1] <= SB_FREE;
            sb_frame_q[0] <= {FRAME_ID_WIDTH{1'b0}};
            sb_frame_q[1] <= {FRAME_ID_WIDTH{1'b0}};
            sb_timeout_q[0] <= 32'd0;
            sb_timeout_q[1] <= 32'd0;
            sb_written_words_q[0] <= 196'd0;
            sb_written_words_q[1] <= 196'd0;
            sb_padding_q[0] <= 16'd0;
            sb_padding_q[1] <= 16'd0;
            fb_fill_active_q <= 1'b0;
            fb_fill_slot_q <= 1'b0;
            fb_fill_count_q <= 7'd0;
            sb_stream_active_q <= 1'b0;
            sb_stream_slot_q <= 1'b0;
            sb_stream_index_q <= 10'd0;
            sb_stream_lane_q <= 2'd0;
            sb_read_pending_q <= 1'b0;
            sb_word_valid_q <= 1'b0;
            sb_word_q <= 32'd0;
            expected_fb_frame_id <= {FRAME_ID_WIDTH{1'b0}};
            expected_sb_frame_id <= {FRAME_ID_WIDTH{1'b0}};
            expected_consume_frame_id <= {FRAME_ID_WIDTH{1'b0}};
            fb_published_valid <= 1'b0;
            fb_published_slot <= 1'b0;
            fb_published_frame_id <= {FRAME_ID_WIDTH{1'b0}};
            sb_committed_valid <= 1'b0;
            sb_committed_slot <= 1'b0;
            sb_committed_frame_id <= {FRAME_ID_WIDTH{1'b0}};
            sb_released_valid <= 1'b0;
            sb_released_slot <= 1'b0;
            sb_released_frame_id <= {FRAME_ID_WIDTH{1'b0}};
            error_valid <= 1'b0;
            error_code <= ERR_NONE;
            error_slot <= 1'b0;
            error_frame_id <= {FRAME_ID_WIDTH{1'b0}};
        end else begin
            fb_published_valid <= 1'b0;
            sb_committed_valid <= 1'b0;
            sb_released_valid <= 1'b0;

            if (clear_error) begin
                error_valid <= 1'b0;
                error_code <= ERR_NONE;
                error_slot <= 1'b0;
                error_frame_id <= {FRAME_ID_WIDTH{1'b0}};
            end

            if (abort) begin
                fb_state_q[0] <= FB_FREE;
                fb_state_q[1] <= FB_FREE;
                sb_state_q[0] <= SB_FREE;
                sb_state_q[1] <= SB_FREE;
                sb_written_words_q[0] <= 196'd0;
                sb_written_words_q[1] <= 196'd0;
                sb_padding_q[0] <= 16'd0;
                sb_padding_q[1] <= 16'd0;
                fb_timeout_q[0] <= 32'd0;
                fb_timeout_q[1] <= 32'd0;
                sb_timeout_q[0] <= 32'd0;
                sb_timeout_q[1] <= 32'd0;
                fb_fill_active_q <= 1'b0;
                sb_stream_active_q <= 1'b0;
                sb_read_pending_q <= 1'b0;
                sb_word_valid_q <= 1'b0;
                expected_fb_frame_id <= {FRAME_ID_WIDTH{1'b0}};
                expected_sb_frame_id <= {FRAME_ID_WIDTH{1'b0}};
                expected_consume_frame_id <= {FRAME_ID_WIDTH{1'b0}};
            end else begin
                if (fb_begin_valid && fb_begin_ready) begin
                    if (fb_begin_frame_id != expected_fb_frame_id) begin
                        latch_fault(
                            ERR_FB_FRAME,
                            selected_fb_free_slot,
                            fb_begin_frame_id
                        );
                    end else begin
                        fb_state_q[selected_fb_free_slot] <= FB_FILL;
                        fb_frame_q[selected_fb_free_slot] <= fb_begin_frame_id;
                        fb_timeout_q[selected_fb_free_slot] <= 32'd0;
                        fb_fill_active_q <= 1'b1;
                        fb_fill_slot_q <= selected_fb_free_slot;
                        fb_fill_count_q <= 7'd0;
                    end
                end

                if (fb_data_fire) begin
                    fb_timeout_q[fb_fill_slot_q] <= 32'd0;
                    if (fb_data_last && (fb_fill_count_q != 7'd63)) begin
                        fb_state_q[fb_fill_slot_q] <= FB_FREE;
                        fb_fill_active_q <= 1'b0;
                        latch_fault(
                            ERR_FB_LENGTH,
                            fb_fill_slot_q,
                            fb_frame_q[fb_fill_slot_q]
                        );
                    end else if (fb_fill_count_q == 7'd63) begin
                        if (!fb_data_last) begin
                            fb_state_q[fb_fill_slot_q] <= FB_FREE;
                            latch_fault(
                                ERR_FB_LENGTH,
                                fb_fill_slot_q,
                                fb_frame_q[fb_fill_slot_q]
                            );
                        end else begin
                            fb_state_q[fb_fill_slot_q] <= FB_READY;
                            fb_published_valid <= 1'b1;
                            fb_published_slot <= fb_fill_slot_q;
                            fb_published_frame_id <= fb_frame_q[fb_fill_slot_q];
                            expected_fb_frame_id <= expected_fb_frame_id + 1'b1;
                        end
                        fb_fill_active_q <= 1'b0;
                    end else begin
                        fb_fill_count_q <= fb_fill_count_q + 1'b1;
                    end
                end

                if (ps_fb_release_valid && ps_fb_release_ready) begin
                    if ((fb_state_q[ps_fb_release_slot] == FB_READY) &&
                        (fb_frame_q[ps_fb_release_slot] ==
                         ps_fb_release_frame_id)) begin
                        fb_state_q[ps_fb_release_slot] <= FB_FREE;
                        fb_timeout_q[ps_fb_release_slot] <= 32'd0;
                    end else begin
                        fb_state_q[ps_fb_release_slot] <= FB_FREE;
                        fb_timeout_q[ps_fb_release_slot] <= 32'd0;
                        if (fb_fill_active_q &&
                            (fb_fill_slot_q == ps_fb_release_slot)) begin
                            fb_fill_active_q <= 1'b0;
                            fb_fill_count_q <= 7'd0;
                        end
                        latch_fault(
                            ERR_FB_RELEASE,
                            ps_fb_release_slot,
                            ps_fb_release_frame_id
                        );
                    end
                end

                if (ps_sb_claim_valid && ps_sb_claim_ready) begin
                    if ((sb_state_q[ps_sb_claim_slot] != SB_FREE) ||
                        (ps_sb_claim_frame_id != expected_sb_frame_id)) begin
                        sb_state_q[ps_sb_claim_slot] <= SB_FREE;
                        sb_written_words_q[ps_sb_claim_slot] <= 196'd0;
                        sb_padding_q[ps_sb_claim_slot] <= 16'd0;
                        sb_timeout_q[ps_sb_claim_slot] <= 32'd0;
                        if (sb_stream_active_q &&
                            (sb_stream_slot_q == ps_sb_claim_slot)) begin
                            sb_stream_active_q <= 1'b0;
                            sb_read_pending_q <= 1'b0;
                            sb_word_valid_q <= 1'b0;
                        end
                        latch_fault(
                            ERR_SB_CLAIM,
                            ps_sb_claim_slot,
                            ps_sb_claim_frame_id
                        );
                    end else begin
                        sb_state_q[ps_sb_claim_slot] <= SB_PS_FILL;
                        sb_frame_q[ps_sb_claim_slot] <= ps_sb_claim_frame_id;
                        sb_written_words_q[ps_sb_claim_slot] <= 196'd0;
                        sb_padding_q[ps_sb_claim_slot] <= 16'd0;
                        sb_timeout_q[ps_sb_claim_slot] <= 32'd0;
                    end
                end

                if (ps_write_fire) begin
                    if (!ps_write_allowed) begin
                        latch_fault(
                            ERR_SB_WRITE_OWNER,
                            ps_write_slot,
                            ps_write_slot ? sb_frame_q[1] : sb_frame_q[0]
                        );
                    end else if (!(&ps_bram_we)) begin
                        latch_fault(
                            ERR_SB_WRITE_STROBE,
                            ps_write_slot,
                            ps_write_slot ? sb_frame_q[1] : sb_frame_q[0]
                        );
                    end else begin
                        sb_written_words_q[ps_write_slot]
                                          [ps_write_word_in_slot] <= 1'b1;
                        if (ps_write_word_in_slot == 10'd195)
                            sb_padding_q[ps_write_slot] <= ps_bram_wdata[31:16];
                        sb_timeout_q[ps_write_slot] <= 32'd0;
                    end
                end

                if (ps_sb_commit_valid && ps_sb_commit_ready) begin
                    if ((sb_state_q[ps_sb_commit_slot] != SB_PS_FILL) ||
                        (sb_frame_q[ps_sb_commit_slot] !=
                         ps_sb_commit_frame_id) ||
                        (ps_sb_commit_frame_id != expected_sb_frame_id) ||
                        !(&sb_written_words_q[ps_sb_commit_slot]) ||
                        (sb_padding_q[ps_sb_commit_slot] != 16'd0)) begin
                        sb_state_q[ps_sb_commit_slot] <= SB_FREE;
                        sb_written_words_q[ps_sb_commit_slot] <= 196'd0;
                        sb_padding_q[ps_sb_commit_slot] <= 16'd0;
                        sb_timeout_q[ps_sb_commit_slot] <= 32'd0;
                        if (sb_stream_active_q &&
                            (sb_stream_slot_q == ps_sb_commit_slot)) begin
                            sb_stream_active_q <= 1'b0;
                            sb_read_pending_q <= 1'b0;
                            sb_word_valid_q <= 1'b0;
                        end
                        latch_fault(
                            ERR_SB_COMMIT,
                            ps_sb_commit_slot,
                            ps_sb_commit_frame_id
                        );
                    end else begin
                        sb_state_q[ps_sb_commit_slot] <= SB_COMMITTED;
                        sb_timeout_q[ps_sb_commit_slot] <= 32'd0;
                        sb_committed_valid <= 1'b1;
                        sb_committed_slot <= ps_sb_commit_slot;
                        sb_committed_frame_id <= ps_sb_commit_frame_id;
                        expected_sb_frame_id <= expected_sb_frame_id + 1'b1;
                    end
                end

                if (ps_subbands_valid && ps_subbands_ready) begin
                    sb_state_q[selected_sb_slot] <= SB_STREAMING;
                    sb_timeout_q[selected_sb_slot] <= 32'd0;
                    sb_stream_active_q <= 1'b1;
                    sb_stream_slot_q <= selected_sb_slot;
                    sb_stream_index_q <= 10'd0;
                    sb_stream_lane_q <= 2'd0;
                    sb_read_pending_q <= 1'b0;
                    sb_word_valid_q <= 1'b0;
                end

                if (pl_read_enable)
                    sb_read_pending_q <= 1'b1;
                if (pl_read_valid_q) begin
                    sb_word_q <= mailbox_port_b_rdata;
                    sb_word_valid_q <= 1'b1;
                    sb_read_pending_q <= 1'b0;
                    sb_stream_lane_q <= 2'd0;
                end

                if (sb_data_fire) begin
                    sb_timeout_q[sb_stream_slot_q] <= 32'd0;
                    if (sb_stream_index_q == (SB_PAYLOAD_BYTES - 1)) begin
                        sb_state_q[sb_stream_slot_q] <= SB_FREE;
                        sb_written_words_q[sb_stream_slot_q] <= 196'd0;
                        sb_padding_q[sb_stream_slot_q] <= 16'd0;
                        sb_stream_active_q <= 1'b0;
                        sb_word_valid_q <= 1'b0;
                        sb_released_valid <= 1'b1;
                        sb_released_slot <= sb_stream_slot_q;
                        sb_released_frame_id <= sb_frame_q[sb_stream_slot_q];
                        expected_consume_frame_id <=
                            expected_consume_frame_id + 1'b1;
                    end else begin
                        sb_stream_index_q <= sb_stream_index_q + 1'b1;
                        if (sb_stream_lane_q == 2'd3) begin
                            sb_stream_lane_q <= 2'd0;
                            sb_word_valid_q <= 1'b0;
                        end else begin
                            sb_stream_lane_q <= sb_stream_lane_q + 1'b1;
                        end
                    end
                end

                if (ps_read_fb0_collision || ps_read_fb1_collision ||
                    ps_read_sb0_collision || ps_read_sb1_collision) begin
                    latch_fault(
                        ERR_PORT_COLLISION,
                        ps_read_fb1_collision || ps_read_sb1_collision,
                        (ps_read_fb1_collision || ps_read_sb1_collision)
                            ? ((ps_bram_addr < SB_SLOT0_WORD)
                                ? fb_frame_q[1] : sb_frame_q[1])
                            : ((ps_bram_addr < SB_SLOT0_WORD)
                                ? fb_frame_q[0] : sb_frame_q[0])
                    );
                end

                // Inactivity timeouts protect FILL/READY/COMMITTED ownership.
                // A sticky timeout requires software abort/clear before the
                // frame sequence is restarted.
                for (slot = 0; slot < 2; slot = slot + 1) begin
                    fb_slot_progress =
                        (fb_data_fire && (fb_fill_slot_q == slot)) ||
                        (ps_fb_release_valid && ps_fb_release_ready &&
                         (ps_fb_release_slot == slot));
                    if (fb_state_q[slot] == FB_FREE) begin
                        fb_timeout_q[slot] <= 32'd0;
                    end else if (fb_slot_progress) begin
                        fb_timeout_q[slot] <= 32'd0;
                    end else if ((TIMEOUT_CYCLES != 0) &&
                                 (fb_timeout_q[slot] >=
                                  (TIMEOUT_CYCLES - 1))) begin
                        fb_state_q[slot] <= FB_FREE;
                        fb_timeout_q[slot] <= 32'd0;
                        if (fb_fill_active_q && (fb_fill_slot_q == slot))
                            fb_fill_active_q <= 1'b0;
                        latch_fault(
                            ERR_SLOT_TIMEOUT,
                            slot[0],
                            fb_frame_q[slot]
                        );
                    end else begin
                        fb_timeout_q[slot] <= fb_timeout_q[slot] + 1'b1;
                    end

                    sb_slot_progress =
                        (ps_full_write_allowed &&
                         (ps_write_slot == slot)) ||
                        (ps_sb_commit_valid && ps_sb_commit_ready &&
                         (ps_sb_commit_slot == slot)) ||
                        (ps_subbands_valid && ps_subbands_ready &&
                         (selected_sb_slot == slot)) ||
                        (sb_data_fire && (sb_stream_slot_q == slot));
                    if (sb_state_q[slot] == SB_FREE) begin
                        sb_timeout_q[slot] <= 32'd0;
                    end else if (sb_slot_progress) begin
                        sb_timeout_q[slot] <= 32'd0;
                    end else if ((TIMEOUT_CYCLES != 0) &&
                                 (sb_timeout_q[slot] >=
                                  (TIMEOUT_CYCLES - 1))) begin
                        sb_state_q[slot] <= SB_FREE;
                        sb_written_words_q[slot] <= 196'd0;
                        sb_padding_q[slot] <= 16'd0;
                        sb_timeout_q[slot] <= 32'd0;
                        if (sb_stream_active_q && (sb_stream_slot_q == slot)) begin
                            sb_stream_active_q <= 1'b0;
                            sb_read_pending_q <= 1'b0;
                            sb_word_valid_q <= 1'b0;
                        end
                        latch_fault(
                            ERR_SLOT_TIMEOUT,
                            slot[0],
                            sb_frame_q[slot]
                        );
                    end else begin
                        sb_timeout_q[slot] <= sb_timeout_q[slot] + 1'b1;
                    end
                end
            end
        end
    end
endmodule
