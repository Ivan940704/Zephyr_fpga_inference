`timescale 1ns/1ps

// Global frame scheduler for the Zephyr PYNQ-Z1 partition.
//
// This block contains control only.  Arithmetic, data buffering, CDC, AXI DMA,
// parameter addressing, and cache-hit policy remain outside this module.
//
// A frame executes in stage-major order:
//   FB GSU1 -> FB GSU2 -> FB projection -> PS preprocessing round trip
//   -> SB GSU1 (branches 0/1/2) -> SB GSU2 -> SB projection
//   -> DeepFilter -> final output.
//
// The subband branches contain 4, 3, and 2 persistent local contexts.  With
// parallel_subbands=0, physical subband engine 0 is time-multiplexed and
// sb_shared_branch selects the logical branch.  With parallel_subbands=1,
// engines/banks 0/1/2 are assumed to map to branches 0/1/2.  The mode is
// sampled only when start is accepted.
module fsm #(
    parameter integer TIMEOUT_CYCLES = 100000000
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        start,
    input  wire        abort,
    // Legacy ABI input.  Sequential-v4 fatal faults are reset-only, so this
    // input is intentionally ignored for recovery.
    input  wire        clear_error,
    input  wire        clear_state_on_start,
    input  wire        parallel_subbands,

    // One stage-load command at a time. Stage IDs match memory_layout.json:
    //   0..2: FB GSU1, GSU2, projection
    //   3..5: SB0 GSU1, GSU2, projection
    //   6..8: SB1 GSU1, GSU2, projection
    //   9..11: SB2 GSU1, GSU2, projection
    output wire        stage_req_valid,
    input  wire        stage_req_ready,
    output reg  [3:0]  stage_id,
    output reg  [1:0]  stage_bank,
    input  wire        stage_load_done,
    input  wire        stage_load_error,

    // Fullband PE job.  start is a held valid and transfers only with ready.
    // fb_stage: 0=GSU1, 1=GSU2, 2=projection.
    output wire        fb_start,
    input  wire        fb_start_ready,
    output reg  [1:0]  fb_stage,
    input  wire        fb_done,
    input  wire        fb_error,

    // PL -> PS fullband result, followed by one buffered return event which
    // means all 4+3+2 normalized subband vectors are available to PL.
    output wire        fb_result_valid,
    input  wire        fb_result_ready,
    input  wire        ps_subbands_valid,
    output wire        ps_subbands_ready,

    // Subband stage command.  In shared mode only bit 0 is used.  In parallel
    // mode bits 0/1/2 address physical branch engines 0/1/2.
    // The three-bit command is one atomic job-valid vector.  In shared mode
    // only bit zero is used; in parallel mode ready covers all asserted bits.
    output wire [2:0]  sb_start,
    input  wire        sb_start_ready,
    output reg  [1:0]  sb_stage,
    output reg  [1:0]  sb_shared_branch,
    output reg  [1:0]  sb_context_0,
    output reg  [1:0]  sb_context_1,
    output reg  [1:0]  sb_context_2,
    input  wire [2:0]  sb_done,
    input  wire [2:0]  sb_error,

    output wire        df_start,
    input  wire        df_start_ready,
    input  wire        df_done,
    input  wire        df_error,

    // PE-controller lifecycle feedback.  Each barrier bit means the complete
    // corresponding PE subsystem is drained, not merely compute_owner=NONE.
    // For the PYNQ-Z1 shared-engine baseline only bit zero is connected to a
    // physical pe_array_datapath; unused bits are tied high for idle and low
    // for fault.  pe_fault combines the PE protocol and arithmetic errors.
    input  wire [2:0]  pe_barrier_idle,
    input  wire [2:0]  pe_fault,
    output reg         pe_abort_pulse,
    output wire [2:0]  pe_active_debug,
    output wire [2:0]  pe_done_pending_debug,

    output wire        final_output_valid,
    input  wire        final_output_ready,

    output reg         clear_state_pulse,
    output wire        busy,
    output wire        done,
    output wire        error,
    output reg  [3:0]  error_code,
    output wire        parallel_mode_active,
    output wire [3:0]  state_debug,
    output reg  [31:0] state_cycle_count
);

    localparam [3:0] ST_IDLE         = 4'd0;
    localparam [3:0] ST_FB_LOAD_REQ  = 4'd1;
    localparam [3:0] ST_FB_LOAD_WAIT = 4'd2;
    localparam [3:0] ST_FB_RUN       = 4'd3;
    localparam [3:0] ST_FB_SEND      = 4'd4;
    localparam [3:0] ST_WAIT_PS      = 4'd5;
    localparam [3:0] ST_SB_LOAD_REQ  = 4'd6;
    localparam [3:0] ST_SB_LOAD_WAIT = 4'd7;
    localparam [3:0] ST_SB_RUN       = 4'd8;
    localparam [3:0] ST_DF_RUN       = 4'd9;
    localparam [3:0] ST_OUTPUT       = 4'd10;
    localparam [3:0] ST_DONE         = 4'd11;
    localparam [3:0] ST_ERROR        = 4'd12;

    localparam [3:0] ERR_NONE     = 4'd0;
    localparam [3:0] ERR_ABORT    = 4'd1;
    localparam [3:0] ERR_TIMEOUT  = 4'd2;
    localparam [3:0] ERR_MEMORY   = 4'd3;
    localparam [3:0] ERR_FULLBAND = 4'd4;
    localparam [3:0] ERR_SUBBAND  = 4'd5;
    localparam [3:0] ERR_DF       = 4'd6;
    localparam [3:0] ERR_PROTOCOL = 4'd7;
    localparam [3:0] ERR_PE       = 4'd8;

    reg [3:0] state_q;
    reg [3:0] state_prev_q;
    reg       start_armed_q;
    reg [1:0] load_branch_q;
    reg [2:0] branch_done_mask_q;
    reg       parallel_mode_q;

    reg       fb_launch_pending_q;
    reg       fb_active_q;
    reg       fb_done_pending_q;
    reg [2:0] sb_launch_pending_q;
    reg [2:0] sb_active_q;
    reg [2:0] sb_done_pending_q;
    reg       df_launch_pending_q;
    reg       df_active_q;
    reg       df_done_pending_q;

    wire [2:0] parallel_last_context;
    wire [2:0] sb_done_event;
    wire [2:0] sb_retire_now;
    wire [2:0] parallel_final_retire;
    wire [2:0] parallel_done_mask_next;
    wire       fb_start_fire;
    wire       fb_done_event;
    wire       fb_retire_now;
    wire       sb_start_fire;
    wire       sb_launch_barrier;
    wire       df_start_fire;
    wire       df_done_event;
    wire       df_retire_now;
    wire       timeout_enabled;
    wire       timeout_state;
    wire       timeout_hit;

    function [1:0] last_context_for_branch;
        input [1:0] branch_id;
        begin
            case (branch_id)
                2'd0: last_context_for_branch = 2'd3; // four contexts
                2'd1: last_context_for_branch = 2'd2; // three contexts
                default: last_context_for_branch = 2'd1; // two contexts
            endcase
        end
    endfunction

    assign stage_req_valid = (state_q == ST_FB_LOAD_REQ) ||
                             (state_q == ST_SB_LOAD_REQ);
    assign fb_result_valid = (state_q == ST_FB_SEND);
    assign ps_subbands_ready = (state_q == ST_WAIT_PS);
    assign final_output_valid = (state_q == ST_OUTPUT);
    assign busy = (state_q != ST_IDLE) && (state_q != ST_DONE) &&
                  (state_q != ST_ERROR);
    assign done = (state_q == ST_DONE);
    assign error = (state_q == ST_ERROR);
    assign parallel_mode_active = parallel_mode_q;
    assign state_debug = state_q;

    // Launches wait for a clean PE boundary and remain asserted under
    // controller backpressure.  A shared ready makes a parallel launch atomic.
    assign fb_start = fb_launch_pending_q && pe_barrier_idle[0];
    assign fb_start_fire = fb_start && fb_start_ready;
    assign fb_done_event = fb_done && fb_active_q;
    assign fb_retire_now = (fb_done_pending_q || fb_done_event)
        && pe_barrier_idle[0];

    assign sb_launch_barrier = &(pe_barrier_idle
        | ~sb_launch_pending_q);
    assign sb_start = sb_launch_pending_q
        & {3{sb_launch_barrier}};
    assign sb_start_fire = (|sb_start) && sb_start_ready;
    assign sb_done_event = sb_done & sb_active_q;
    assign sb_retire_now = (sb_done_pending_q | sb_done_event)
        & pe_barrier_idle;

    assign df_start = df_launch_pending_q && pe_barrier_idle[0];
    assign df_start_fire = df_start && df_start_ready;
    assign df_done_event = df_done && df_active_q;
    assign df_retire_now = (df_done_pending_q || df_done_event)
        && pe_barrier_idle[0];

    assign pe_active_debug = sb_active_q
        | {2'b00, (fb_active_q | df_active_q)};
    assign pe_done_pending_debug = sb_done_pending_q
        | {2'b00, (fb_done_pending_q | df_done_pending_q)};

    assign parallel_last_context = {
        (sb_context_2 == 2'd1),
        (sb_context_1 == 2'd2),
        (sb_context_0 == 2'd3)
    };
    assign parallel_final_retire = sb_retire_now & parallel_last_context &
                                   ~branch_done_mask_q;
    assign parallel_done_mask_next = branch_done_mask_q |
                                     parallel_final_retire;

    assign timeout_enabled = (TIMEOUT_CYCLES != 0);
    assign timeout_state = (state_q != ST_IDLE) && (state_q != ST_DONE) &&
                           (state_q != ST_ERROR);
    assign timeout_hit = timeout_enabled && timeout_state &&
                         (state_cycle_count >= TIMEOUT_CYCLES - 1);

    // Stage address remains stable for the whole request state.
    always @* begin
        stage_id = 4'd0;
        stage_bank = 2'd0;
        if ((state_q == ST_FB_LOAD_REQ) || (state_q == ST_FB_LOAD_WAIT)) begin
            stage_id = {2'd0, fb_stage};
        end else if ((state_q == ST_SB_LOAD_REQ) ||
                     (state_q == ST_SB_LOAD_WAIT)) begin
            stage_id = 4'd3 + (load_branch_q * 3) + sb_stage;
            stage_bank = parallel_mode_q ? load_branch_q : 2'd0;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state_q <= ST_IDLE;
            state_prev_q <= ST_IDLE;
            start_armed_q <= 1'b1;
            state_cycle_count <= 32'd0;
            error_code <= ERR_NONE;
            parallel_mode_q <= 1'b0;
            fb_stage <= 2'd0;
            sb_stage <= 2'd0;
            load_branch_q <= 2'd0;
            sb_shared_branch <= 2'd0;
            sb_context_0 <= 2'd0;
            sb_context_1 <= 2'd0;
            sb_context_2 <= 2'd0;
            branch_done_mask_q <= 3'b000;
            fb_launch_pending_q <= 1'b0;
            fb_active_q <= 1'b0;
            fb_done_pending_q <= 1'b0;
            sb_launch_pending_q <= 3'b000;
            sb_active_q <= 3'b000;
            sb_done_pending_q <= 3'b000;
            df_launch_pending_q <= 1'b0;
            df_active_q <= 1'b0;
            df_done_pending_q <= 1'b0;
            pe_abort_pulse <= 1'b0;
            clear_state_pulse <= 1'b0;
        end else begin
            // Abort is an event; job valids are held by the pending registers.
            pe_abort_pulse <= 1'b0;
            clear_state_pulse <= 1'b0;

            // Accept one frame for each low-to-high start request.  Software
            // may hold start high until it observes busy without retriggering
            // a second frame after DONE returns to IDLE.
            if (!start)
                start_armed_q <= 1'b1;

            state_prev_q <= state_q;
            if (state_q != state_prev_q)
                state_cycle_count <= 32'd0;
            else if (timeout_state)
                state_cycle_count <= state_cycle_count + 1'b1;
            else
                state_cycle_count <= 32'd0;

            if (abort && busy) begin
                state_q <= ST_ERROR;
                error_code <= ERR_ABORT;
                pe_abort_pulse <= 1'b1;
                fb_launch_pending_q <= 1'b0;
                fb_active_q <= 1'b0;
                fb_done_pending_q <= 1'b0;
                sb_launch_pending_q <= 3'b000;
                sb_active_q <= 3'b000;
                sb_done_pending_q <= 3'b000;
                df_launch_pending_q <= 1'b0;
                df_active_q <= 1'b0;
                df_done_pending_q <= 1'b0;
            end else if (timeout_hit) begin
                state_q <= ST_ERROR;
                error_code <= ERR_TIMEOUT;
                pe_abort_pulse <= 1'b1;
                fb_launch_pending_q <= 1'b0;
                fb_active_q <= 1'b0;
                fb_done_pending_q <= 1'b0;
                sb_launch_pending_q <= 3'b000;
                sb_active_q <= 3'b000;
                sb_done_pending_q <= 3'b000;
                df_launch_pending_q <= 1'b0;
                df_active_q <= 1'b0;
                df_done_pending_q <= 1'b0;
            end else if ((state_q != ST_ERROR) && (|pe_fault)) begin
                state_q <= ST_ERROR;
                error_code <= ERR_PE;
                pe_abort_pulse <= 1'b1;
                fb_launch_pending_q <= 1'b0;
                fb_active_q <= 1'b0;
                fb_done_pending_q <= 1'b0;
                sb_launch_pending_q <= 3'b000;
                sb_active_q <= 3'b000;
                sb_done_pending_q <= 3'b000;
                df_launch_pending_q <= 1'b0;
                df_active_q <= 1'b0;
                df_done_pending_q <= 1'b0;
            end else begin
                case (state_q)
                    ST_IDLE: begin
                        fb_launch_pending_q <= 1'b0;
                        fb_active_q <= 1'b0;
                        fb_done_pending_q <= 1'b0;
                        sb_launch_pending_q <= 3'b000;
                        sb_active_q <= 3'b000;
                        sb_done_pending_q <= 3'b000;
                        df_launch_pending_q <= 1'b0;
                        df_active_q <= 1'b0;
                        df_done_pending_q <= 1'b0;
                        if (start && start_armed_q && !abort && !(|pe_fault)) begin
                            start_armed_q <= 1'b0;
                            parallel_mode_q <= parallel_subbands;
                            clear_state_pulse <= clear_state_on_start;
                            error_code <= ERR_NONE;
                            fb_stage <= 2'd0;
                            sb_stage <= 2'd0;
                            load_branch_q <= 2'd0;
                            sb_shared_branch <= 2'd0;
                            sb_context_0 <= 2'd0;
                            sb_context_1 <= 2'd0;
                            sb_context_2 <= 2'd0;
                            branch_done_mask_q <= 3'b000;
                            state_q <= ST_FB_LOAD_REQ;
                        end
                    end

                    ST_FB_LOAD_REQ: begin
                        if (stage_req_ready)
                            state_q <= ST_FB_LOAD_WAIT;
                    end

                    ST_FB_LOAD_WAIT: begin
                        if (stage_load_done) begin
                            if (stage_load_error) begin
                                state_q <= ST_ERROR;
                                error_code <= ERR_MEMORY;
                                pe_abort_pulse <= 1'b1;
                            end else begin
                                fb_launch_pending_q <= 1'b1;
                                fb_active_q <= 1'b0;
                                fb_done_pending_q <= 1'b0;
                                state_q <= ST_FB_RUN;
                            end
                        end
                    end

                    ST_FB_RUN: begin
                        if (fb_start_fire) begin
                            fb_launch_pending_q <= 1'b0;
                            fb_active_q <= 1'b1;
                        end
                        if (fb_done_event) begin
                            fb_active_q <= 1'b0;
                            fb_done_pending_q <= 1'b1;
                        end
                        if (fb_error) begin
                            state_q <= ST_ERROR;
                            error_code <= ERR_FULLBAND;
                            pe_abort_pulse <= 1'b1;
                            fb_launch_pending_q <= 1'b0;
                            fb_active_q <= 1'b0;
                            fb_done_pending_q <= 1'b0;
                        end else if (fb_retire_now) begin
                            fb_done_pending_q <= 1'b0;
                            if (fb_stage == 2'd2) begin
                                state_q <= ST_FB_SEND;
                            end else begin
                                fb_stage <= fb_stage + 1'b1;
                                state_q <= ST_FB_LOAD_REQ;
                            end
                        end
                    end

                    ST_FB_SEND: begin
                        if (fb_result_ready)
                            state_q <= ST_WAIT_PS;
                    end

                    ST_WAIT_PS: begin
                        if (ps_subbands_valid) begin
                            sb_stage <= 2'd0;
                            load_branch_q <= 2'd0;
                            sb_shared_branch <= 2'd0;
                            sb_context_0 <= 2'd0;
                            sb_context_1 <= 2'd0;
                            sb_context_2 <= 2'd0;
                            branch_done_mask_q <= 3'b000;
                            state_q <= ST_SB_LOAD_REQ;
                        end
                    end

                    ST_SB_LOAD_REQ: begin
                        if (stage_req_ready)
                            state_q <= ST_SB_LOAD_WAIT;
                    end

                    ST_SB_LOAD_WAIT: begin
                        if (stage_load_done) begin
                            if (stage_load_error) begin
                                state_q <= ST_ERROR;
                                error_code <= ERR_MEMORY;
                                pe_abort_pulse <= 1'b1;
                            end else if (parallel_mode_q &&
                                         (load_branch_q != 2'd2)) begin
                                load_branch_q <= load_branch_q + 1'b1;
                                state_q <= ST_SB_LOAD_REQ;
                            end else begin
                                branch_done_mask_q <= 3'b000;
                                sb_context_0 <= 2'd0;
                                sb_context_1 <= 2'd0;
                                sb_context_2 <= 2'd0;
                                sb_active_q <= 3'b000;
                                sb_done_pending_q <= 3'b000;
                                if (parallel_mode_q) begin
                                    sb_launch_pending_q <= 3'b111;
                                end else begin
                                    sb_shared_branch <= load_branch_q;
                                    sb_launch_pending_q <= 3'b001;
                                end
                                state_q <= ST_SB_RUN;
                            end
                        end
                    end

                    ST_SB_RUN: begin
                        // Merge same-cycle launch and unrelated-engine done
                        // events so a parallel relaunch cannot be overwritten
                        // when another branch completes on that edge.
                        sb_active_q <= (sb_active_q |
                            ({3{sb_start_fire}} & sb_start)) &
                            ~sb_done_event;
                        sb_done_pending_q <= (sb_done_pending_q |
                            sb_done_event) & ~sb_retire_now;
                        if (sb_start_fire)
                            sb_launch_pending_q <= 3'b000;

                        if ((parallel_mode_q && (|sb_error)) ||
                            (!parallel_mode_q && sb_error[0])) begin
                            state_q <= ST_ERROR;
                            error_code <= ERR_SUBBAND;
                            pe_abort_pulse <= 1'b1;
                            sb_launch_pending_q <= 3'b000;
                            sb_active_q <= 3'b000;
                            sb_done_pending_q <= 3'b000;
                        end else if (parallel_mode_q) begin
                            branch_done_mask_q <= parallel_done_mask_next;

                            if (sb_retire_now[0] && !branch_done_mask_q[0] &&
                                !parallel_last_context[0]) begin
                                sb_context_0 <= sb_context_0 + 1'b1;
                                sb_launch_pending_q[0] <= 1'b1;
                            end
                            if (sb_retire_now[1] && !branch_done_mask_q[1] &&
                                !parallel_last_context[1]) begin
                                sb_context_1 <= sb_context_1 + 1'b1;
                                sb_launch_pending_q[1] <= 1'b1;
                            end
                            if (sb_retire_now[2] && !branch_done_mask_q[2] &&
                                !parallel_last_context[2]) begin
                                sb_context_2 <= sb_context_2 + 1'b1;
                                sb_launch_pending_q[2] <= 1'b1;
                            end

                            if (parallel_done_mask_next == 3'b111) begin
                                if (sb_stage == 2'd2) begin
                                    df_launch_pending_q <= 1'b1;
                                    state_q <= ST_DF_RUN;
                                end else begin
                                    sb_stage <= sb_stage + 1'b1;
                                    load_branch_q <= 2'd0;
                                    state_q <= ST_SB_LOAD_REQ;
                                end
                            end
                        end else if (sb_retire_now[0]) begin
                            if (sb_context_0 <
                                last_context_for_branch(sb_shared_branch)) begin
                                sb_context_0 <= sb_context_0 + 1'b1;
                                sb_launch_pending_q <= 3'b001;
                            end else if (sb_shared_branch != 2'd2) begin
                                load_branch_q <= sb_shared_branch + 1'b1;
                                sb_shared_branch <= sb_shared_branch + 1'b1;
                                sb_context_0 <= 2'd0;
                                state_q <= ST_SB_LOAD_REQ;
                            end else if (sb_stage != 2'd2) begin
                                sb_stage <= sb_stage + 1'b1;
                                load_branch_q <= 2'd0;
                                sb_shared_branch <= 2'd0;
                                sb_context_0 <= 2'd0;
                                state_q <= ST_SB_LOAD_REQ;
                            end else begin
                                df_launch_pending_q <= 1'b1;
                                state_q <= ST_DF_RUN;
                            end
                        end
                    end

                    ST_DF_RUN: begin
                        if (df_start_fire) begin
                            df_launch_pending_q <= 1'b0;
                            df_active_q <= 1'b1;
                        end
                        if (df_done_event) begin
                            df_active_q <= 1'b0;
                            df_done_pending_q <= 1'b1;
                        end
                        if (df_error) begin
                            state_q <= ST_ERROR;
                            error_code <= ERR_DF;
                            pe_abort_pulse <= 1'b1;
                            df_launch_pending_q <= 1'b0;
                            df_active_q <= 1'b0;
                            df_done_pending_q <= 1'b0;
                        end else if (df_retire_now) begin
                            df_done_pending_q <= 1'b0;
                            state_q <= ST_OUTPUT;
                        end
                    end

                    ST_OUTPUT: begin
                        if (final_output_ready)
                            state_q <= ST_DONE;
                    end

                    ST_DONE: begin
                        state_q <= ST_IDLE;
                    end

                    ST_ERROR: begin
                        // Sequential-v4 subsystem faults are reset-required.
                        // clear_error remains in the port list only for ABI
                        // compatibility and cannot release this state.
                        state_q <= ST_ERROR;
                    end

                    default: begin
                        state_q <= ST_ERROR;
                        error_code <= ERR_PROTOCOL;
                        pe_abort_pulse <= 1'b1;
                    end
                endcase
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (TIMEOUT_CYCLES < 0)
            $fatal(1, "fsm TIMEOUT_CYCLES must be non-negative");
    end
`endif

endmodule
