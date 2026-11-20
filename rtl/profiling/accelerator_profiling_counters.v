`timescale 1ns/1ps

// Coherent, read-only per-frame profiling snapshot for accelerator_system_top.
// Counters are reset at every frame and kept at 32 bits; the exported 64-bit
// ABI zero-extends every high word.  A pipelined serializer writes the frozen
// frame into distributed RAM so the PS read path never traverses the counter
// bank.  The module observes existing handshakes only and never feeds the
// accelerator datapath.
module accelerator_profiling_counters #(
    parameter integer FRAME_ID_WIDTH = 16,
    parameter integer AXI_DATA_BYTES = 8
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         enable,
    input  wire                         clear_pulse,
    input  wire                         snapshot_pulse,
    input  wire [7:0]                   read_index,
    output reg  [31:0]                  read_data,
    output wire                         snapshot_valid,
    output wire                         frame_active,
    output wire                         snapshot_busy,

    input  wire                         accelerator_reset_active,
    input  wire                         frame_start,
    input  wire                         frame_done,
    input  wire                         frame_error,
    input  wire                         sparse_mode,
    input  wire [FRAME_ID_WIDTH-1:0]    frame_id,
    input  wire [3:0]                   global_state,
    input  wire [3:0]                   active_stage_id,
    input  wire [5:0]                   controller_state,
    input  wire [3:0]                   compute_owner,

    input  wire                         parameter_arvalid,
    input  wire                         parameter_arready,
    input  wire [7:0]                   parameter_arlen,
    input  wire                         parameter_rvalid,
    input  wire                         parameter_rready,
    input  wire                         parameter_rlast,

    input  wire                         fb_axis_tvalid,
    input  wire                         fb_axis_tready,
    input  wire                         fb_axis_tlast,
    input  wire                         spectrum_axis_tvalid,
    input  wire                         spectrum_axis_tready,
    input  wire                         spectrum_axis_tlast,
    input  wire                         output_axis_tvalid,
    input  wire                         output_axis_tready,
    input  wire                         output_axis_tlast,

    input  wire                         fb_release_valid,
    input  wire                         fb_release_ready,
    input  wire                         sb_claim_valid,
    input  wire                         sb_claim_ready,
    input  wire                         sb_commit_valid,
    input  wire                         sb_commit_ready,
    input  wire                         mailbox_error_valid,

    input  wire [31:0]                  weight_request_count,
    input  wire [31:0]                  dense_weight_request_count,
    input  wire [31:0]                  sparse_weight_request_count,
    input  wire                         sparse_stage_diag_valid,
    input  wire [31:0]                  sparse_stage_actual_bytes,
    input  wire [31:0]                  sparse_stage_saved_bytes,
    input  wire [31:0]                  sparse_stage_ar_burst_count,
    input  wire [31:0]                  sparse_stage_load_cycles
);
    localparam [3:0] GLOBAL_FB_LOAD_REQ  = 4'd1;
    localparam [3:0] GLOBAL_FB_LOAD_WAIT = 4'd2;
    localparam [3:0] GLOBAL_FB_RUN       = 4'd3;
    localparam [3:0] GLOBAL_WAIT_PS      = 4'd5;
    localparam [3:0] GLOBAL_SB_LOAD_REQ  = 4'd6;
    localparam [3:0] GLOBAL_SB_LOAD_WAIT = 4'd7;
    localparam [3:0] GLOBAL_SB_RUN       = 4'd8;
    localparam [3:0] GLOBAL_DF_RUN       = 4'd9;
    localparam [5:0] CONTROLLER_DONE     = 6'd36;

    localparam integer GLOBAL_STATE_COUNT = 13;
    localparam integer STAGE_COUNT = 12;
    localparam integer SUMMARY_COUNT = 36;

    // Summary slots are exposed as low/high word pairs at read indices 120+.
    localparam integer SUM_AXI_AR_BURSTS       = 0;
    localparam integer SUM_AXI_AR_BEATS        = 1;
    localparam integer SUM_AXI_R_BEATS         = 2;
    localparam integer SUM_AXI_R_BYTES         = 3;
    localparam integer SUM_AXI_AR_STALL        = 4;
    localparam integer SUM_AXI_R_WAIT          = 5;
    localparam integer SUM_AXI_R_BACKPRESSURE  = 6;
    localparam integer SUM_FB_AXIS_BEATS       = 7;
    localparam integer SUM_FB_AXIS_BACKPRESSURE = 8;
    localparam integer SUM_SPECTRUM_AXIS_BEATS = 9;
    localparam integer SUM_SPECTRUM_AXIS_BACKPRESSURE = 10;
    localparam integer SUM_OUTPUT_AXIS_BEATS   = 11;
    localparam integer SUM_OUTPUT_AXIS_BACKPRESSURE = 12;
    localparam integer SUM_FB_RELEASES         = 13;
    localparam integer SUM_SB_CLAIMS           = 14;
    localparam integer SUM_SB_COMMITS          = 15;
    localparam integer SUM_CONTROLLER_JOBS     = 16;
    localparam integer SUM_WEIGHT_REQUESTS     = 17;
    localparam integer SUM_DENSE_REQUESTS      = 18;
    localparam integer SUM_SPARSE_REQUESTS     = 19;
    localparam integer SUM_DENSE_EQ_REQUESTS   = 20;
    localparam integer SUM_RETIRED_MACS        = 21;
    localparam integer SUM_SKIPPED_MACS        = 22;
    localparam integer SUM_STAGE_ACTUAL_BYTES  = 23;
    localparam integer SUM_STAGE_SAVED_BYTES   = 24;
    localparam integer SUM_STAGE_AR_BURSTS     = 25;
    localparam integer SUM_STAGE_LOAD_CYCLES   = 26;
    localparam integer SUM_MAX_OUTSTANDING     = 27;
    localparam integer SUM_FB_AXIS_PACKETS      = 28;
    localparam integer SUM_SPECTRUM_AXIS_PACKETS = 29;
    localparam integer SUM_OUTPUT_AXIS_PACKETS  = 30;
    localparam integer SUM_FRAME_ERROR_CYCLES   = 31;
    localparam integer SUM_MAILBOX_ERRORS       = 32;
    localparam integer SUM_SPARSE_DIAG_EVENTS   = 33;
    localparam integer SUM_AXI_RLASTS            = 34;
    localparam integer SUM_INVALID_STATE_CYCLES = 35;

    reg active_q;
    reg snapshot_valid_q;
    reg snapshot_sparse_q;
    reg [FRAME_ID_WIDTH-1:0] active_frame_id_q;
    reg [31:0] snapshot_sequence_q;
    reg [3:0] previous_global_state_q;
    reg [5:0] previous_controller_state_q;
    reg [8:0] outstanding_bursts_q;
    reg error_seen_work_q;
    reg sparse_stage_diag_valid_q;

    reg [31:0] frame_cycles_work_q;
    reg [31:0] state_sum_work_q;
    reg [31:0] state_cycles_work_q [0:GLOBAL_STATE_COUNT-1];
    reg [31:0] state_visits_work_q [0:GLOBAL_STATE_COUNT-1];
    reg [31:0] stage_load_work_q [0:STAGE_COUNT-1];
    reg [31:0] stage_compute_work_q [0:STAGE_COUNT-1];
    reg [31:0] stage_stall_work_q [0:STAGE_COUNT-1];
    reg [31:0] summary_work_q [0:SUMMARY_COUNT-1];

    reg capture_busy_q;
    reg capture_valid_q;
    reg capture_sparse_q;
    reg capture_reset_active_q;
    reg capture_frame_active_q;
    reg [FRAME_ID_WIDTH-1:0] capture_frame_id_q;
    reg [3:0] capture_end_state_q;
    reg [3:0] capture_compute_owner_q;
    reg [31:0] capture_sequence_q;
    reg [7:0] capture_issue_index_q;

    reg stage1_valid_q;
    reg [7:0] stage1_address_q;
    reg [2:0] stage1_group_q;
    reg [31:0] stage1_header_q;
    reg [31:0] stage1_state_cycles_q;
    reg [31:0] stage1_state_visits_q;
    reg [31:0] stage1_stage_load_q;
    reg [31:0] stage1_stage_compute_q;
    reg [31:0] stage1_stage_stall_q;
    reg [31:0] stage1_summary_q;
    reg stage2_valid_q;
    reg [7:0] stage2_address_q;
    reg [31:0] stage2_data_q;

    (* ram_style = "distributed" *)
    reg [31:0] snapshot_words [0:191];

    integer index;

    wire parameter_ar_fire = parameter_arvalid && parameter_arready;
    wire parameter_r_fire = parameter_rvalid && parameter_rready;
    wire parameter_rlast_fire = parameter_r_fire && parameter_rlast;
    wire parameter_progress = parameter_ar_fire || parameter_r_fire;
    wire fb_axis_fire = fb_axis_tvalid && fb_axis_tready;
    wire spectrum_axis_fire = spectrum_axis_tvalid && spectrum_axis_tready;
    wire output_axis_fire = output_axis_tvalid && output_axis_tready;
    wire controller_job_done = (controller_state == CONTROLLER_DONE) &&
                               (previous_controller_state_q != CONTROLLER_DONE);
    wire global_state_changed = global_state != previous_global_state_q;
    wire valid_global_state = global_state < GLOBAL_STATE_COUNT;
    wire sparse_stage_diag_pulse = sparse_stage_diag_valid &&
                                        !sparse_stage_diag_valid_q;
    wire valid_stage = active_stage_id < STAGE_COUNT;
    wire load_state = (global_state == GLOBAL_FB_LOAD_REQ) ||
                      (global_state == GLOBAL_FB_LOAD_WAIT) ||
                      (global_state == GLOBAL_SB_LOAD_REQ) ||
                      (global_state == GLOBAL_SB_LOAD_WAIT);
    wire compute_state = (global_state == GLOBAL_FB_RUN) ||
                         (global_state == GLOBAL_SB_RUN) ||
                         (global_state == GLOBAL_DF_RUN);
    wire load_wait_state = (global_state == GLOBAL_FB_LOAD_WAIT) ||
                           (global_state == GLOBAL_SB_LOAD_WAIT);
    wire controller_wait_state =
        (controller_state == 6'd3)  || (controller_state == 6'd5)  ||
        (controller_state == 6'd7)  || (controller_state == 6'd9)  ||
        (controller_state == 6'd12) || (controller_state == 6'd15) ||
        (controller_state == 6'd17) || (controller_state == 6'd19) ||
        (controller_state == 6'd21) || (controller_state == 6'd30) ||
        (controller_state == 6'd32) || (controller_state == 6'd34);
    wire stage_stall_sample =
        (load_wait_state && !parameter_progress) ||
        (compute_state && controller_wait_state);

    function [31:0] dense_requests_for_stage;
        input [3:0] stage_id;
        begin
            case (stage_id)
                4'd0: dense_requests_for_stage = 32'd7680;
                4'd1: dense_requests_for_stage = 32'd12800;
                4'd2: dense_requests_for_stage = 32'd1280;
                4'd3: dense_requests_for_stage = 32'd3780;
                4'd4: dense_requests_for_stage = 32'd6272;
                4'd5: dense_requests_for_stage = 32'd1120;
                4'd6: dense_requests_for_stage = 32'd4452;
                4'd7: dense_requests_for_stage = 32'd6272;
                4'd8: dense_requests_for_stage = 32'd2688;
                4'd9: dense_requests_for_stage = 32'd5348;
                4'd10: dense_requests_for_stage = 32'd6272;
                4'd11: dense_requests_for_stage = 32'd1792;
                default: dense_requests_for_stage = 32'd0;
            endcase
        end
    endfunction

    wire [31:0] job_dense_requests = dense_requests_for_stage(active_stage_id);
    wire [31:0] job_skipped_requests =
        (job_dense_requests >= weight_request_count)
            ? (job_dense_requests - weight_request_count) : 32'd0;
    wire [31:0] job_retired_macs = weight_request_count << 4;
    wire [31:0] job_skipped_macs = job_skipped_requests << 4;
    wire [8:0] outstanding_after_ar = outstanding_bursts_q + 1'b1;
    wire [31:0] parameter_ar_beats = {24'd0, parameter_arlen} + 32'd1;

    assign snapshot_valid = snapshot_valid_q;
    assign frame_active = active_q;
    assign snapshot_busy = capture_busy_q || stage1_valid_q || stage2_valid_q;

    initial begin
        if ((FRAME_ID_WIDTH < 1) || (FRAME_ID_WIDTH > 16))
            $error("FRAME_ID_WIDTH must be in the range 1..16");
        if (AXI_DATA_BYTES <= 0)
            $error("AXI_DATA_BYTES must be positive");
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            active_q <= 1'b0;
            snapshot_valid_q <= 1'b0;
            snapshot_sparse_q <= 1'b0;
            active_frame_id_q <= {FRAME_ID_WIDTH{1'b0}};
            snapshot_sequence_q <= 32'd0;
            previous_global_state_q <= 4'd0;
            previous_controller_state_q <= 6'd0;
            outstanding_bursts_q <= 9'd0;
            error_seen_work_q <= 1'b0;
            sparse_stage_diag_valid_q <= 1'b0;
            frame_cycles_work_q <= 32'd0;
            state_sum_work_q <= 32'd0;
            capture_busy_q <= 1'b0;
            capture_valid_q <= 1'b0;
            capture_sparse_q <= 1'b0;
            capture_reset_active_q <= 1'b0;
            capture_frame_active_q <= 1'b0;
            capture_frame_id_q <= {FRAME_ID_WIDTH{1'b0}};
            capture_end_state_q <= 4'd0;
            capture_compute_owner_q <= 4'd0;
            capture_sequence_q <= 32'd0;
            capture_issue_index_q <= 8'd0;
            stage1_valid_q <= 1'b0;
            stage1_address_q <= 8'd0;
            stage1_group_q <= 3'd0;
            stage1_header_q <= 32'd0;
            stage1_state_cycles_q <= 32'd0;
            stage1_state_visits_q <= 32'd0;
            stage1_stage_load_q <= 32'd0;
            stage1_stage_compute_q <= 32'd0;
            stage1_stage_stall_q <= 32'd0;
            stage1_summary_q <= 32'd0;
            stage2_valid_q <= 1'b0;
            stage2_address_q <= 8'd0;
            stage2_data_q <= 32'd0;
            for (index = 0; index < GLOBAL_STATE_COUNT; index = index + 1) begin
                state_cycles_work_q[index] <= 32'd0;
                state_visits_work_q[index] <= 32'd0;
            end
            for (index = 0; index < STAGE_COUNT; index = index + 1) begin
                stage_load_work_q[index] <= 32'd0;
                stage_compute_work_q[index] <= 32'd0;
                stage_stall_work_q[index] <= 32'd0;
            end
            for (index = 0; index < SUMMARY_COUNT; index = index + 1)
                summary_work_q[index] <= 32'd0;
        end else if (clear_pulse) begin
            active_q <= 1'b0;
            snapshot_valid_q <= 1'b0;
            snapshot_sparse_q <= 1'b0;
            snapshot_sequence_q <= 32'd0;
            outstanding_bursts_q <= 9'd0;
            error_seen_work_q <= 1'b0;
            frame_cycles_work_q <= 32'd0;
            sparse_stage_diag_valid_q <= 1'b0;
            state_sum_work_q <= 32'd0;
            capture_busy_q <= 1'b0;
            capture_valid_q <= 1'b0;
            capture_issue_index_q <= 8'd0;
            stage1_valid_q <= 1'b0;
            stage2_valid_q <= 1'b0;
            for (index = 0; index < GLOBAL_STATE_COUNT; index = index + 1) begin
                state_cycles_work_q[index] <= 32'd0;
                state_visits_work_q[index] <= 32'd0;
            end
            for (index = 0; index < STAGE_COUNT; index = index + 1) begin
                stage_load_work_q[index] <= 32'd0;
                stage_compute_work_q[index] <= 32'd0;
                stage_stall_work_q[index] <= 32'd0;
            end
            for (index = 0; index < SUMMARY_COUNT; index = index + 1)
                summary_work_q[index] <= 32'd0;
        end else begin
            previous_global_state_q <= global_state;
            previous_controller_state_q <= controller_state;
            sparse_stage_diag_valid_q <= sparse_stage_diag_valid;

            if (!enable || accelerator_reset_active) begin
                active_q <= 1'b0;
                outstanding_bursts_q <= 9'd0;
                error_seen_work_q <= 1'b0;
            end else if (frame_start) begin
                active_q <= 1'b1;
                active_frame_id_q <= frame_id;
                snapshot_sparse_q <= sparse_mode;
                previous_global_state_q <= global_state;
                previous_controller_state_q <= controller_state;
                outstanding_bursts_q <= 9'd0;
                error_seen_work_q <= 1'b0;
                frame_cycles_work_q <= 32'd0;
                state_sum_work_q <= 32'd0;
                for (index = 0; index < GLOBAL_STATE_COUNT; index = index + 1) begin
                    state_cycles_work_q[index] <= 32'd0;
                    state_visits_work_q[index] <= 32'd0;
                end
                for (index = 0; index < STAGE_COUNT; index = index + 1) begin
                    stage_load_work_q[index] <= 32'd0;
                    stage_compute_work_q[index] <= 32'd0;
                    stage_stall_work_q[index] <= 32'd0;
                end
                for (index = 0; index < SUMMARY_COUNT; index = index + 1)
                    summary_work_q[index] <= 32'd0;
            end else if (active_q) begin
                if (frame_error)
                    error_seen_work_q <= 1'b1;
                frame_cycles_work_q <= frame_cycles_work_q + 1'b1;
                state_sum_work_q <= state_sum_work_q + 1'b1;
                if (valid_global_state) begin
                    state_cycles_work_q[global_state] <=
                        state_cycles_work_q[global_state] + 1'b1;
                    if (global_state_changed)
                        state_visits_work_q[global_state] <=
                            state_visits_work_q[global_state] + 1'b1;
                end
                if (valid_stage) begin
                    if (load_state)
                        stage_load_work_q[active_stage_id] <=
                            stage_load_work_q[active_stage_id] + 1'b1;
                    if (compute_state)
                        stage_compute_work_q[active_stage_id] <=
                            stage_compute_work_q[active_stage_id] + 1'b1;
                    if (stage_stall_sample)
                        stage_stall_work_q[active_stage_id] <=
                            stage_stall_work_q[active_stage_id] + 1'b1;
                end

                if (parameter_ar_fire) begin
                    summary_work_q[SUM_AXI_AR_BURSTS] <=
                        summary_work_q[SUM_AXI_AR_BURSTS] + 1'b1;
                    summary_work_q[SUM_AXI_AR_BEATS] <=
                        summary_work_q[SUM_AXI_AR_BEATS] + parameter_ar_beats;
                end
                if (parameter_r_fire) begin
                    summary_work_q[SUM_AXI_R_BEATS] <=
                        summary_work_q[SUM_AXI_R_BEATS] + 1'b1;
                    summary_work_q[SUM_AXI_R_BYTES] <=
                        summary_work_q[SUM_AXI_R_BYTES] + AXI_DATA_BYTES;
                end
                if (parameter_arvalid && !parameter_arready)
                    summary_work_q[SUM_AXI_AR_STALL] <=
                        summary_work_q[SUM_AXI_AR_STALL] + 1'b1;
                if ((outstanding_bursts_q != 0) && !parameter_rvalid)
                    summary_work_q[SUM_AXI_R_WAIT] <=
                        summary_work_q[SUM_AXI_R_WAIT] + 1'b1;
                if (parameter_rvalid && !parameter_rready)
                    summary_work_q[SUM_AXI_R_BACKPRESSURE] <=
                        summary_work_q[SUM_AXI_R_BACKPRESSURE] + 1'b1;

                case ({parameter_ar_fire, parameter_rlast_fire})
                    2'b10: outstanding_bursts_q <= outstanding_bursts_q + 1'b1;
                    2'b01: if (outstanding_bursts_q != 0)
                        outstanding_bursts_q <= outstanding_bursts_q - 1'b1;
                    default: begin
                    end
                endcase
                if (parameter_ar_fire &&
                    (outstanding_after_ar > summary_work_q[SUM_MAX_OUTSTANDING][8:0]))
                    summary_work_q[SUM_MAX_OUTSTANDING] <=
                        {23'd0, outstanding_after_ar};

                if (fb_axis_fire)
                    summary_work_q[SUM_FB_AXIS_BEATS] <=
                        summary_work_q[SUM_FB_AXIS_BEATS] + 1'b1;
                if (fb_axis_tvalid && !fb_axis_tready)
                    summary_work_q[SUM_FB_AXIS_BACKPRESSURE] <=
                        summary_work_q[SUM_FB_AXIS_BACKPRESSURE] + 1'b1;
                if (spectrum_axis_fire)
                    summary_work_q[SUM_SPECTRUM_AXIS_BEATS] <=
                        summary_work_q[SUM_SPECTRUM_AXIS_BEATS] + 1'b1;
                if (spectrum_axis_tvalid && !spectrum_axis_tready)
                    summary_work_q[SUM_SPECTRUM_AXIS_BACKPRESSURE] <=
                        summary_work_q[SUM_SPECTRUM_AXIS_BACKPRESSURE] + 1'b1;
                if (output_axis_fire)
                    summary_work_q[SUM_OUTPUT_AXIS_BEATS] <=
                        summary_work_q[SUM_OUTPUT_AXIS_BEATS] + 1'b1;
                if (output_axis_tvalid && !output_axis_tready)
                    summary_work_q[SUM_OUTPUT_AXIS_BACKPRESSURE] <=
                        summary_work_q[SUM_OUTPUT_AXIS_BACKPRESSURE] + 1'b1;

                if (fb_release_valid && fb_release_ready)
                    summary_work_q[SUM_FB_RELEASES] <=
                        summary_work_q[SUM_FB_RELEASES] + 1'b1;
                if (sb_claim_valid && sb_claim_ready)
                    summary_work_q[SUM_SB_CLAIMS] <=
                        summary_work_q[SUM_SB_CLAIMS] + 1'b1;
                if (sb_commit_valid && sb_commit_ready)
                    summary_work_q[SUM_SB_COMMITS] <=
                        summary_work_q[SUM_SB_COMMITS] + 1'b1;

                if (controller_job_done) begin
                    summary_work_q[SUM_CONTROLLER_JOBS] <=
                        summary_work_q[SUM_CONTROLLER_JOBS] + 1'b1;
                    summary_work_q[SUM_WEIGHT_REQUESTS] <=
                        summary_work_q[SUM_WEIGHT_REQUESTS] + weight_request_count;
                    summary_work_q[SUM_DENSE_REQUESTS] <=
                        summary_work_q[SUM_DENSE_REQUESTS] + dense_weight_request_count;
                    summary_work_q[SUM_SPARSE_REQUESTS] <=
                        summary_work_q[SUM_SPARSE_REQUESTS] + sparse_weight_request_count;
                    summary_work_q[SUM_DENSE_EQ_REQUESTS] <=
                        summary_work_q[SUM_DENSE_EQ_REQUESTS] + job_dense_requests;
                    summary_work_q[SUM_RETIRED_MACS] <=
                        summary_work_q[SUM_RETIRED_MACS] + job_retired_macs;
                    summary_work_q[SUM_SKIPPED_MACS] <=
                        summary_work_q[SUM_SKIPPED_MACS] + job_skipped_macs;
                end

                if (sparse_stage_diag_pulse) begin
                    summary_work_q[SUM_STAGE_ACTUAL_BYTES] <=
                        summary_work_q[SUM_STAGE_ACTUAL_BYTES] +
                        sparse_stage_actual_bytes;
                    summary_work_q[SUM_STAGE_SAVED_BYTES] <=
                        summary_work_q[SUM_STAGE_SAVED_BYTES] +
                        sparse_stage_saved_bytes;
                    summary_work_q[SUM_STAGE_AR_BURSTS] <=
                        summary_work_q[SUM_STAGE_AR_BURSTS] +
                        sparse_stage_ar_burst_count;
                    summary_work_q[SUM_STAGE_LOAD_CYCLES] <=
                        summary_work_q[SUM_STAGE_LOAD_CYCLES] +
                        sparse_stage_load_cycles;
                end
                if (fb_axis_fire && fb_axis_tlast)
                    summary_work_q[SUM_FB_AXIS_PACKETS] <=
                        summary_work_q[SUM_FB_AXIS_PACKETS] + 1'b1;
                if (spectrum_axis_fire && spectrum_axis_tlast)
                    summary_work_q[SUM_SPECTRUM_AXIS_PACKETS] <=
                        summary_work_q[SUM_SPECTRUM_AXIS_PACKETS] + 1'b1;
                if (output_axis_fire && output_axis_tlast)
                    summary_work_q[SUM_OUTPUT_AXIS_PACKETS] <=
                        summary_work_q[SUM_OUTPUT_AXIS_PACKETS] + 1'b1;
                if (frame_error)
                    summary_work_q[SUM_FRAME_ERROR_CYCLES] <=
                        summary_work_q[SUM_FRAME_ERROR_CYCLES] + 1'b1;
                if (mailbox_error_valid)
                    summary_work_q[SUM_MAILBOX_ERRORS] <=
                        summary_work_q[SUM_MAILBOX_ERRORS] + 1'b1;
                if (sparse_stage_diag_pulse)
                    summary_work_q[SUM_SPARSE_DIAG_EVENTS] <=
                        summary_work_q[SUM_SPARSE_DIAG_EVENTS] + 1'b1;
                if (parameter_rlast_fire)
                    summary_work_q[SUM_AXI_RLASTS] <=
                        summary_work_q[SUM_AXI_RLASTS] + 1'b1;
                if (!valid_global_state)
                    summary_work_q[SUM_INVALID_STATE_CYCLES] <=
                        summary_work_q[SUM_INVALID_STATE_CYCLES] + 1'b1;

                if (frame_done) begin
                    active_q <= 1'b0;
                    snapshot_valid_q <= 1'b0;
                    capture_busy_q <= 1'b1;
                    capture_valid_q <= !(error_seen_work_q || frame_error);
                    capture_sparse_q <= snapshot_sparse_q;
                    capture_reset_active_q <= accelerator_reset_active;
                    capture_frame_active_q <= 1'b0;
                    capture_frame_id_q <= active_frame_id_q;
                    capture_end_state_q <= global_state;
                    capture_compute_owner_q <= compute_owner;
                    capture_sequence_q <= snapshot_sequence_q + 1'b1;
                    capture_issue_index_q <= 8'd0;
                end
            end else if (snapshot_pulse && !snapshot_busy) begin
                snapshot_valid_q <= 1'b0;
                capture_busy_q <= 1'b1;
                capture_valid_q <= !error_seen_work_q;
                capture_sparse_q <= snapshot_sparse_q;
                capture_reset_active_q <= accelerator_reset_active;
                capture_frame_active_q <= 1'b0;
                capture_frame_id_q <= active_frame_id_q;
                capture_end_state_q <= global_state;
                capture_compute_owner_q <= compute_owner;
                capture_sequence_q <= snapshot_sequence_q + 1'b1;
                capture_issue_index_q <= 8'd0;
            end

            // Freeze validity if a new frame arrives before the serializer has
            // drained.  The profiler remains observational and never stalls the
            // accelerator, so software can detect and retry this rare collision.
            if (frame_start && snapshot_busy)
                capture_valid_q <= 1'b0;

            // Stage 1: select within one small counter family.  Keeping these
            // banks separate prevents synthesis from rebuilding a 192-to-1 mux.
            stage1_valid_q <= capture_busy_q;
            if (capture_busy_q) begin
                stage1_address_q <= capture_issue_index_q;
                if (capture_issue_index_q < 8'd8) begin
                    stage1_group_q <= 3'd0;
                    case (capture_issue_index_q)
                        8'd0: stage1_header_q <= 32'h5052_0001;
                        8'd1: stage1_header_q <=
                            {27'd0, capture_sparse_q,
                             capture_reset_active_q, capture_frame_active_q,
                             capture_valid_q, enable};
                        8'd2: stage1_header_q <=
                            {7'd0, capture_compute_owner_q,
                             capture_end_state_q, 1'b0,
                             {(16-FRAME_ID_WIDTH){1'b0}}, capture_frame_id_q};
                        8'd3: stage1_header_q <= capture_sequence_q;
                        8'd4: stage1_header_q <= frame_cycles_work_q;
                        8'd5: stage1_header_q <= 32'd0;
                        8'd6: stage1_header_q <= state_sum_work_q;
                        default: stage1_header_q <= 32'd0;
                    endcase
                end else if (capture_issue_index_q < 8'd34) begin
                    stage1_group_q <= 3'd1;
                    stage1_state_cycles_q <= capture_issue_index_q[0]
                        ? 32'd0
                        : state_cycles_work_q[
                            (capture_issue_index_q - 8'd8) >> 1];
                end else if (capture_issue_index_q < 8'd47) begin
                    stage1_group_q <= 3'd2;
                    stage1_state_visits_q <= state_visits_work_q[
                        capture_issue_index_q - 8'd34];
                end else if (capture_issue_index_q == 8'd47) begin
                    stage1_group_q <= 3'd0;
                    stage1_header_q <= 32'd0;
                end else if (capture_issue_index_q < 8'd72) begin
                    stage1_group_q <= 3'd3;
                    stage1_stage_load_q <= capture_issue_index_q[0]
                        ? 32'd0
                        : stage_load_work_q[
                            (capture_issue_index_q - 8'd48) >> 1];
                end else if (capture_issue_index_q < 8'd96) begin
                    stage1_group_q <= 3'd4;
                    stage1_stage_compute_q <= capture_issue_index_q[0]
                        ? 32'd0
                        : stage_compute_work_q[
                            (capture_issue_index_q - 8'd72) >> 1];
                end else if (capture_issue_index_q < 8'd120) begin
                    stage1_group_q <= 3'd5;
                    stage1_stage_stall_q <= capture_issue_index_q[0]
                        ? 32'd0
                        : stage_stall_work_q[
                            (capture_issue_index_q - 8'd96) >> 1];
                end else begin
                    stage1_group_q <= 3'd6;
                    stage1_summary_q <= capture_issue_index_q[0]
                        ? 32'd0
                        : summary_work_q[
                            (capture_issue_index_q - 8'd120) >> 1];
                end

                if (capture_issue_index_q == 8'd191)
                    capture_busy_q <= 1'b0;
                else
                    capture_issue_index_q <= capture_issue_index_q + 1'b1;
            end

            // Stage 2: select the already-localized family output.
            stage2_valid_q <= stage1_valid_q;
            if (stage1_valid_q) begin
                stage2_address_q <= stage1_address_q;
                case (stage1_group_q)
                    3'd0: stage2_data_q <= stage1_header_q;
                    3'd1: stage2_data_q <= stage1_state_cycles_q;
                    3'd2: stage2_data_q <= stage1_state_visits_q;
                    3'd3: stage2_data_q <= stage1_stage_load_q;
                    3'd4: stage2_data_q <= stage1_stage_compute_q;
                    3'd5: stage2_data_q <= stage1_stage_stall_q;
                    default: stage2_data_q <= stage1_summary_q;
                endcase
            end

            // One write per cycle permits distributed-RAM inference.  Valid is
            // published only after the final word has committed.
            if (stage2_valid_q) begin
                snapshot_words[stage2_address_q] <= stage2_data_q;
                if (stage2_address_q == 8'd191) begin
                    snapshot_sequence_q <= capture_sequence_q;
                    snapshot_valid_q <= capture_valid_q &&
                                        !(frame_start && snapshot_busy);
                end
            end
        end
    end

    // 0..7 header, 8..33 state cycles, 34..46 state visits,
    // 48..71 stage load, 72..95 stage compute, 96..119 stage stall,
    // 120..191 summary counter pairs.  The AXI wrapper registers the address
    // before sampling this asynchronous distributed-RAM read port.
    always @* begin
        if (read_index < 8'd192)
            read_data = snapshot_words[read_index];
        else
            read_data = 32'd0;
    end
endmodule
