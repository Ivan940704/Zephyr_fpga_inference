`timescale 1ns/1ps

module tb_fsm;
    localparam integer TIMEOUT_CYCLES = 64;

    localparam [3:0] ST_IDLE  = 4'd0;
    localparam [3:0] ST_ERROR = 4'd12;

    localparam [3:0] ERR_ABORT    = 4'd1;
    localparam [3:0] ERR_TIMEOUT  = 4'd2;
    localparam [3:0] ERR_MEMORY   = 4'd3;
    localparam [3:0] ERR_FULLBAND = 4'd4;
    localparam [3:0] ERR_SUBBAND  = 4'd5;
    localparam [3:0] ERR_DF       = 4'd6;
    localparam [3:0] ERR_PE       = 4'd8;

    reg clk;
    reg rst_n;
    reg start;
    reg abort;
    reg clear_error;
    reg clear_state_on_start;
    reg parallel_subbands;
    reg sparse_load_enable;

    wire stage_req_valid;
    reg stage_req_ready;
    wire [3:0] stage_id;
    wire [1:0] stage_bank;
    wire stage_sparse_load_enable;
    reg stage_load_done;
    reg stage_load_error;

    wire fb_start;
    reg fb_start_ready;
    wire [1:0] fb_stage;
    reg fb_done;
    reg fb_error;

    wire fb_result_valid;
    reg fb_result_ready;
    reg ps_subbands_valid;
    wire ps_subbands_ready;

    wire [2:0] sb_start;
    reg sb_start_ready;
    wire [1:0] sb_stage;
    wire [1:0] sb_shared_branch;
    wire [1:0] sb_context_0;
    wire [1:0] sb_context_1;
    wire [1:0] sb_context_2;
    reg [2:0] sb_done;
    reg [2:0] sb_error;

    wire df_start;
    reg df_start_ready;
    reg df_done;
    reg df_error;

    reg [2:0] pe_barrier_idle;
    reg [2:0] pe_fault;
    wire pe_abort_pulse;
    wire [2:0] pe_active_debug;
    wire [2:0] pe_done_pending_debug;

    wire final_output_valid;
    reg final_output_ready;
    wire clear_state_pulse;
    wire busy;
    wire done;
    wire error;
    wire [3:0] error_code;
    wire parallel_mode_active;
    wire sparse_mode_active;
    wire [3:0] state_debug;
    wire [31:0] state_cycle_count;

    integer failures;
    integer run_parallel;
    integer run_sparse;
    integer auto_respond;
    integer request_count;
    integer fb_start_count;
    integer df_start_count;
    integer sb_done_count;
    integer triple_start_count;
    integer sb_start_count [0:2][0:2];
    integer mem_countdown;
    integer fb_countdown;
    integer sb_countdown [0:2];
    integer df_countdown;
    integer pe_barrier_countdown [0:2];
    integer inject_memory_error;
    integer inject_fb_error;
    integer inject_sb_error;
    integer inject_sb_error_lane;
    integer inject_df_error;
    integer i;
    integer j;
    integer guard;
    integer logical_branch;
    integer logical_context;

    always #5 clk = ~clk;

    fsm #(
        .TIMEOUT_CYCLES(TIMEOUT_CYCLES)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .abort(abort),
        .clear_error(clear_error),
        .clear_state_on_start(clear_state_on_start),
        .sparse_load_enable(sparse_load_enable),
        .parallel_subbands(parallel_subbands),
        .stage_req_valid(stage_req_valid),
        .stage_req_ready(stage_req_ready),
        .stage_id(stage_id),
        .stage_bank(stage_bank),
        .stage_sparse_load_enable(stage_sparse_load_enable),
        .stage_load_done(stage_load_done),
        .stage_load_error(stage_load_error),
        .fb_start(fb_start),
        .fb_start_ready(fb_start_ready),
        .fb_stage(fb_stage),
        .fb_done(fb_done),
        .fb_error(fb_error),
        .fb_result_valid(fb_result_valid),
        .fb_result_ready(fb_result_ready),
        .ps_subbands_valid(ps_subbands_valid),
        .ps_subbands_ready(ps_subbands_ready),
        .sb_start(sb_start),
        .sb_start_ready(sb_start_ready),
        .sb_stage(sb_stage),
        .sb_shared_branch(sb_shared_branch),
        .sb_context_0(sb_context_0),
        .sb_context_1(sb_context_1),
        .sb_context_2(sb_context_2),
        .sb_done(sb_done),
        .sb_error(sb_error),
        .df_start(df_start),
        .df_start_ready(df_start_ready),
        .df_done(df_done),
        .df_error(df_error),
        .pe_barrier_idle(pe_barrier_idle),
        .pe_fault(pe_fault),
        .pe_abort_pulse(pe_abort_pulse),
        .pe_active_debug(pe_active_debug),
        .pe_done_pending_debug(pe_done_pending_debug),
        .final_output_valid(final_output_valid),
        .final_output_ready(final_output_ready),
        .clear_state_pulse(clear_state_pulse),
        .busy(busy),
        .done(done),
        .error(error),
        .error_code(error_code),
        .parallel_mode_active(parallel_mode_active),
        .sparse_mode_active(sparse_mode_active),
        .state_debug(state_debug),
        .state_cycle_count(state_cycle_count)
    );

    task fail;
        input [8*160-1:0] message;
        begin
            failures = failures + 1;
            $display("FAIL: %0s at time %0t state=%0d error=%0d fb=%b sb=%b df=%b active=%b pending=%b barrier=%b",
                     message, $time, state_debug, error_code, fb_start,
                     sb_start, df_start, pe_active_debug,
                     pe_done_pending_debug, pe_barrier_idle);
        end
    endtask

    function [3:0] expected_stage;
        input integer index;
        begin
            case (index)
                0: expected_stage = 4'd0;
                1: expected_stage = 4'd1;
                2: expected_stage = 4'd2;
                3: expected_stage = 4'd3;
                4: expected_stage = 4'd6;
                5: expected_stage = 4'd9;
                6: expected_stage = 4'd4;
                7: expected_stage = 4'd7;
                8: expected_stage = 4'd10;
                9: expected_stage = 4'd5;
                10: expected_stage = 4'd8;
                default: expected_stage = 4'd11;
            endcase
        end
    endfunction

    function integer context_limit;
        input integer branch_id;
        begin
            case (branch_id)
                0: context_limit = 4;
                1: context_limit = 3;
                default: context_limit = 2;
            endcase
        end
    endfunction

    task clear_scoreboard;
        begin
            request_count = 0;
            fb_start_count = 0;
            df_start_count = 0;
            sb_done_count = 0;
            triple_start_count = 0;
            for (i = 0; i < 3; i = i + 1)
                for (j = 0; j < 3; j = j + 1)
                    sb_start_count[i][j] = 0;
        end
    endtask

    task apply_reset;
        begin
            start = 1'b0;
            abort = 1'b0;
            clear_error = 1'b0;
            clear_state_on_start = 1'b0;
            pe_fault = 3'b000;
            sparse_load_enable = 1'b0;
            rst_n = 1'b0;
            repeat (3) @(posedge clk);
            @(negedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
            #1;
            if (state_debug !== ST_IDLE || busy || done || error)
                fail("reset did not return FSM to clean IDLE");
            if (pe_active_debug != 3'b000 ||
                pe_done_pending_debug != 3'b000 || pe_abort_pulse)
                fail("reset did not clear PE lifecycle tracking");
        end
    endtask

    task pulse_start;
        input integer parallel_value;
        input integer hold_start_high;
        begin
            run_parallel = parallel_value;
            @(negedge clk);
            parallel_subbands = parallel_value;
            sparse_load_enable = run_sparse;
            clear_state_on_start = 1'b1;
            start = 1'b1;
            @(posedge clk);
            #1;
            if (!clear_state_pulse)
                fail("accepted start did not pulse clear_state");
            @(negedge clk);
            if (!hold_start_high)
                start = 1'b0;
            clear_state_on_start = 1'b0;
            // Prove the mode is sampled, not live.
            parallel_subbands = !parallel_value;
            sparse_load_enable = !run_sparse;
            @(posedge clk);
            #1;
            if (parallel_mode_active !== parallel_value[0])
                fail("parallel mode was not latched at start");
            if (sparse_mode_active !== run_sparse[0] ||
                stage_sparse_load_enable !== run_sparse[0])
                fail("sparse load mode was not latched at start");
        end
    endtask

    task send_ps_subbands;
        begin
            guard = 0;
            while (!ps_subbands_ready && guard < 500) begin
                @(posedge clk);
                guard = guard + 1;
            end
            if (guard == 500)
                fail("timed out waiting for PS subband return handshake");
            repeat (2) @(posedge clk);
            @(negedge clk);
            ps_subbands_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            ps_subbands_valid = 1'b0;
        end
    endtask

    task wait_for_error;
        input [3:0] expected_code;
        begin
            guard = 0;
            while (!error && guard < 3000) begin
                @(posedge clk);
                #1;
                guard = guard + 1;
            end
            if (guard == 3000)
                fail("timed out waiting for expected FSM error");
            else if (state_debug !== ST_ERROR || error_code !== expected_code)
                fail("FSM reported the wrong error code");
            if (busy)
                fail("FSM remained busy after entering error state");
        end
    endtask

    task prove_clear_error_cannot_recover;
        input [3:0] expected_code;
        begin
            @(negedge clk);
            clear_error = 1'b1;
            @(posedge clk);
            @(negedge clk);
            clear_error = 1'b0;
            @(posedge clk);
            #1;
            if (state_debug !== ST_ERROR || !error ||
                error_code !== expected_code)
                fail("clear_error incorrectly released reset-only ERROR");
        end
    endtask

    task verify_normal_scoreboard;
        input integer parallel_value;
        begin
            if (request_count != 12)
                fail("normal frame did not request all 12 stages exactly once");
            if (fb_start_count != 3)
                fail("normal frame did not start all three fullband operators");
            if (df_start_count != 1)
                fail("normal frame did not start DeepFilter exactly once");
            if (sb_done_count != 27)
                fail("normal frame did not complete 27 subband context/stage commands");
            for (i = 0; i < 3; i = i + 1)
                for (j = 0; j < 3; j = j + 1)
                    if (sb_start_count[i][j] != context_limit(j))
                        fail("subband context count mismatch");
            if (parallel_value && triple_start_count != 3)
                fail("parallel mode did not launch all branches together per stage");
            if (!parallel_value && triple_start_count != 0)
                fail("shared mode unexpectedly launched multiple engines");
        end
    endtask

    task run_normal_frame;
        input integer parallel_value;
        input integer hold_start_high;
        begin
            apply_reset;
            clear_scoreboard;
            auto_respond = 1;
            stage_req_ready = 1'b0;
            fb_result_ready = 1'b0;
            final_output_ready = 1'b0;
            fb_start_ready = 1'b0;
            sb_start_ready = 1'b0;
            df_start_ready = 1'b0;
            pulse_start(parallel_value, hold_start_high);

            // Request address must remain stable while the memory service stalls.
            guard = 0;
            while (!stage_req_valid && guard < 20) begin
                @(posedge clk);
                guard = guard + 1;
            end
            if (!stage_req_valid || stage_id != 0 || stage_bank != 0)
                fail("first stage request was not held while ready was low");
            repeat (3) begin
                @(posedge clk);
                #1;
                if (!stage_req_valid || stage_id != 0 || stage_bank != 0)
                    fail("stage request changed under backpressure");
            end
            @(negedge clk);
            stage_req_ready = 1'b1;

            // A PE job start is held until the controller accepts it.
            guard = 0;
            while (!fb_start && guard < 100) begin
                @(posedge clk);
                #1;
                guard = guard + 1;
            end
            if (guard == 100)
                fail("timed out waiting for held fullband start");
            repeat (3) begin
                @(posedge clk);
                #1;
                if (!fb_start || pe_active_debug[0])
                    fail("fullband start was not held before ready");
            end
            @(negedge clk);
            fb_start_ready = 1'b1;

            // Hold the PL->PS packet for three cycles to verify valid retention.
            guard = 0;
            while (!fb_result_valid && guard < 500) begin
                @(posedge clk);
                #1;
                guard = guard + 1;
            end
            if (guard == 500)
                fail("timed out waiting for fullband result");
            repeat (3) begin
                @(posedge clk);
                #1;
                if (!fb_result_valid)
                    fail("fullband result valid was not held under backpressure");
            end
            @(negedge clk);
            fb_result_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            fb_result_ready = 1'b0;

            send_ps_subbands;

            guard = 0;
            while (!(|sb_start) && guard < 500) begin
                @(posedge clk);
                #1;
                guard = guard + 1;
            end
            if (guard == 500)
                fail("timed out waiting for held subband start");
            repeat (2) begin
                @(posedge clk);
                #1;
                if (!(|sb_start) || (|pe_active_debug))
                    fail("subband start was not held before ready");
            end
            @(negedge clk);
            sb_start_ready = 1'b1;

            guard = 0;
            while (!df_start && guard < 3000) begin
                @(posedge clk);
                #1;
                guard = guard + 1;
            end
            if (guard == 3000)
                fail("timed out waiting for held DeepFilter start");
            repeat (2) begin
                @(posedge clk);
                #1;
                if (!df_start || pe_active_debug[0])
                    fail("DeepFilter start was not held before ready");
            end
            @(negedge clk);
            df_start_ready = 1'b1;

            guard = 0;
            while (!final_output_valid && guard < 3000) begin
                @(posedge clk);
                #1;
                guard = guard + 1;
            end
            if (guard == 3000)
                fail("timed out waiting for final output");
            repeat (3) begin
                @(posedge clk);
                #1;
                if (!final_output_valid)
                    fail("final output valid was not held under backpressure");
            end
            @(negedge clk);
            final_output_ready = 1'b1;

            guard = 0;
            while (!done && guard < 20) begin
                @(posedge clk);
                #1;
                guard = guard + 1;
            end
            if (guard == 20)
                fail("normal frame did not produce done");
            verify_normal_scoreboard(parallel_value);
            @(negedge clk);
            final_output_ready = 1'b0;
            @(posedge clk);
            #1;
            if (done || busy || error || state_debug != ST_IDLE)
                fail("done state did not return to IDLE after one cycle");
            if (hold_start_high) begin
                repeat (4) begin
                    @(posedge clk);
                    #1;
                    if (state_debug != ST_IDLE || busy || stage_req_valid ||
                        clear_state_pulse)
                        fail("held-high start retriggered a second frame");
                end
                @(negedge clk);
                start = 1'b0;
                @(posedge clk);
            end
        end
    endtask

    // Deterministic responder and protocol scoreboard.
    always @(posedge clk) begin
        stage_load_done <= 1'b0;
        stage_load_error <= 1'b0;
        fb_done <= 1'b0;
        fb_error <= 1'b0;
        sb_done <= 3'b000;
        sb_error <= 3'b000;
        df_done <= 1'b0;
        df_error <= 1'b0;

        if (!rst_n) begin
            mem_countdown = -1;
            fb_countdown = -1;
            df_countdown = -1;
            pe_barrier_idle <= 3'b111;
            for (i = 0; i < 3; i = i + 1) begin
                sb_countdown[i] = -1;
                pe_barrier_countdown[i] = -1;
            end
        end else if (auto_respond) begin
            if (stage_req_valid && stage_req_ready && mem_countdown < 0) begin
                if (stage_id !== expected_stage(request_count))
                    fail("stage request order did not match the 12-stage contract");
                if (stage_sparse_load_enable !== run_sparse[0])
                    fail("stage request did not hold the sampled sparse mode");
                if (run_parallel && request_count >= 3) begin
                    if (stage_bank !== ((request_count - 3) % 3))
                        fail("parallel stage was loaded into the wrong branch bank");
                end else if (stage_bank !== 0) begin
                    fail("shared schedule used a nonzero stage bank");
                end
                request_count = request_count + 1;
                mem_countdown = 1 + stage_id[0];
            end else if (mem_countdown == 0) begin
                stage_load_done <= 1'b1;
                stage_load_error <= inject_memory_error;
                mem_countdown = -1;
            end else if (mem_countdown > 0) begin
                mem_countdown = mem_countdown - 1;
            end

            if (fb_start && fb_start_ready) begin
                if (fb_stage !== fb_start_count[1:0])
                    fail("fullband operator start order mismatch");
                if (fb_countdown >= 0)
                    fail("fullband engine was restarted while busy");
                fb_start_count = fb_start_count + 1;
                fb_countdown = 2 + fb_stage;
                pe_barrier_idle[0] <= 1'b0;
            end else if (fb_countdown == 0) begin
                fb_done <= 1'b1;
                fb_error <= inject_fb_error;
                fb_countdown = -1;
                pe_barrier_countdown[0] = 3;
            end else if (fb_countdown > 0) begin
                fb_countdown = fb_countdown - 1;
            end

            if ((sb_start == 3'b111) && sb_start_ready)
                triple_start_count = triple_start_count + 1;
            for (i = 0; i < 3; i = i + 1) begin
                if (sb_start[i] && sb_start_ready) begin
                    logical_branch = run_parallel ? i : sb_shared_branch;
                    case (i)
                        0: logical_context = sb_context_0;
                        1: logical_context = sb_context_1;
                        default: logical_context = sb_context_2;
                    endcase
                    if (!run_parallel)
                        logical_context = sb_context_0;
                    if (!run_parallel && i != 0)
                        fail("shared schedule started an unavailable physical engine");
                    if (logical_context != sb_start_count[sb_stage][logical_branch])
                        fail("subband context IDs were not issued in ascending order");
                    if (sb_countdown[i] >= 0)
                        fail("subband engine was restarted while busy");
                    sb_start_count[sb_stage][logical_branch] =
                        sb_start_count[sb_stage][logical_branch] + 1;
                    // Different branch delays force the parallel FSM to wait
                    // and independently relaunch 4/3/2 contexts.
                    sb_countdown[i] = 1 + (i * 2) +
                                      ((logical_context + sb_stage) % 2);
                    pe_barrier_idle[i] <= 1'b0;
                end else if (sb_countdown[i] == 0) begin
                    sb_done[i] <= 1'b1;
                    if (inject_sb_error && (i == inject_sb_error_lane))
                        sb_error[i] <= 1'b1;
                    sb_done_count = sb_done_count + 1;
                    sb_countdown[i] = -1;
                    pe_barrier_countdown[i] = 2 + i;
                end else if (sb_countdown[i] > 0) begin
                    sb_countdown[i] = sb_countdown[i] - 1;
                end
            end

            if (df_start && df_start_ready) begin
                if (sb_done_count != 27)
                    fail("DeepFilter started before all subband projections completed");
                df_start_count = df_start_count + 1;
                df_countdown = 3;
                pe_barrier_idle[0] <= 1'b0;
            end else if (df_countdown == 0) begin
                df_done <= 1'b1;
                df_error <= inject_df_error;
                df_countdown = -1;
                pe_barrier_countdown[0] = 3;
            end else if (df_countdown > 0) begin
                df_countdown = df_countdown - 1;
            end

            for (i = 0; i < 3; i = i + 1) begin
                if (pe_barrier_countdown[i] == 0) begin
                    pe_barrier_idle[i] <= 1'b1;
                    pe_barrier_countdown[i] = -1;
                end else if (pe_barrier_countdown[i] > 0) begin
                    pe_barrier_countdown[i] =
                        pe_barrier_countdown[i] - 1;
                end
            end

            if ((|pe_done_pending_debug) &&
                ((state_debug == 4'd1) || (state_debug == 4'd2) ||
                 (state_debug == 4'd4) || (state_debug == 4'd5) ||
                 (state_debug == 4'd6) || (state_debug == 4'd7) ||
                 (state_debug == 4'd10) || (state_debug == 4'd11)))
                fail("FSM crossed a stage boundary before PE drain");
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        abort = 1'b0;
        clear_error = 1'b0;
        clear_state_on_start = 1'b0;
        parallel_subbands = 1'b0;
        sparse_load_enable = 1'b0;
        stage_req_ready = 1'b0;
        stage_load_done = 1'b0;
        stage_load_error = 1'b0;
        fb_start_ready = 1'b1;
        fb_done = 1'b0;
        fb_error = 1'b0;
        fb_result_ready = 1'b0;
        ps_subbands_valid = 1'b0;
        sb_done = 3'b000;
        sb_error = 3'b000;
        sb_start_ready = 1'b1;
        df_start_ready = 1'b1;
        df_done = 1'b0;
        df_error = 1'b0;
        pe_barrier_idle = 3'b111;
        pe_fault = 3'b000;
        final_output_ready = 1'b0;
        failures = 0;
        auto_respond = 0;
        run_parallel = 0;
        run_sparse = 0;
        inject_memory_error = 0;
        inject_fb_error = 0;
        inject_sb_error = 0;
        inject_sb_error_lane = 0;
        inject_df_error = 0;
        for (i = 0; i < 3; i = i + 1)
            pe_barrier_countdown[i] = -1;
        clear_scoreboard;

        // Reset while a request is stalled must flush the frame.
        apply_reset;
        auto_respond = 0;
        stage_req_ready = 1'b0;
        pulse_start(0, 0);
        while (!stage_req_valid)
            @(posedge clk);
        repeat (3) @(posedge clk);
        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        #1;
        if (state_debug != ST_IDLE || busy || error || stage_req_valid)
            fail("mid-frame reset did not flush the FSM");

        // Resource-safe shared-engine schedule and experimental parallel mode.
        inject_memory_error = 0;
        inject_fb_error = 0;
        inject_sb_error = 0;
        inject_df_error = 0;
        run_sparse = 1;
        run_normal_frame(0, 1);
        run_sparse = 0;
        run_normal_frame(1, 0);

        // Sparse memory failure is independent of success-only load done.
        apply_reset;
        clear_scoreboard;
        auto_respond = 0;
        stage_req_ready = 1'b1;
        run_sparse = 1;
        pulse_start(0, 0);
        guard = 0;
        while ((state_debug != 4'd2) && guard < 20) begin
            @(posedge clk);
            guard = guard + 1;
        end
        if (guard == 20)
            fail("sparse fault test did not reach load-wait state");
        @(negedge clk);
        stage_load_error = 1'b1;
        wait_for_error(ERR_MEMORY);
        if (stage_load_done)
            fail("success-only done was asserted during sparse load failure");
        prove_clear_error_cannot_recover(ERR_MEMORY);

        // Memory error.
        apply_reset;
        clear_scoreboard;
        auto_respond = 1;
        stage_req_ready = 1'b1;
        inject_memory_error = 1;
        fb_start_ready = 1'b1;
        sb_start_ready = 1'b1;
        df_start_ready = 1'b1;
        pulse_start(0, 0);
        wait_for_error(ERR_MEMORY);
        prove_clear_error_cannot_recover(ERR_MEMORY);
        inject_memory_error = 0;

        // Fullband engine error.
        apply_reset;
        clear_scoreboard;
        auto_respond = 1;
        stage_req_ready = 1'b1;
        inject_fb_error = 1;
        fb_start_ready = 1'b1;
        sb_start_ready = 1'b1;
        df_start_ready = 1'b1;
        pulse_start(0, 0);
        wait_for_error(ERR_FULLBAND);
        prove_clear_error_cannot_recover(ERR_FULLBAND);
        inject_fb_error = 0;

        // Parallel subband engine error after a valid PS round trip.
        apply_reset;
        clear_scoreboard;
        auto_respond = 1;
        stage_req_ready = 1'b1;
        fb_result_ready = 1'b1;
        inject_sb_error = 1;
        inject_sb_error_lane = 2;
        fb_start_ready = 1'b1;
        sb_start_ready = 1'b1;
        df_start_ready = 1'b1;
        pulse_start(1, 0);
        send_ps_subbands;
        wait_for_error(ERR_SUBBAND);
        prove_clear_error_cannot_recover(ERR_SUBBAND);
        inject_sb_error = 0;
        fb_result_ready = 1'b0;

        // DeepFilter error after all subband contexts complete.
        apply_reset;
        clear_scoreboard;
        auto_respond = 1;
        stage_req_ready = 1'b1;
        fb_result_ready = 1'b1;
        inject_df_error = 1;
        fb_start_ready = 1'b1;
        sb_start_ready = 1'b1;
        df_start_ready = 1'b1;
        pulse_start(0, 0);
        send_ps_subbands;
        wait_for_error(ERR_DF);
        prove_clear_error_cannot_recover(ERR_DF);
        inject_df_error = 0;
        fb_result_ready = 1'b0;

        // A pre-existing PE/subsystem fault blocks start even while IDLE.
        apply_reset;
        clear_scoreboard;
        auto_respond = 0;
        @(negedge clk);
        pe_fault[0] = 1'b1;
        @(posedge clk);
        #1;
        if (!pe_abort_pulse)
            fail("idle PE fault did not pulse pe_abort_pulse");
        wait_for_error(ERR_PE);
        @(negedge clk);
        pe_fault = 3'b000;
        prove_clear_error_cannot_recover(ERR_PE);

        // Sticky PE protocol/arithmetic fault propagates through ERR_PE and
        // asks the external PE controller to cancel the current job.
        apply_reset;
        clear_scoreboard;
        auto_respond = 1;
        stage_req_ready = 1'b1;
        fb_start_ready = 1'b1;
        sb_start_ready = 1'b1;
        df_start_ready = 1'b1;
        pulse_start(0, 0);
        guard = 0;
        while (!pe_active_debug[0] && guard < 100) begin
            @(posedge clk);
            #1;
            guard = guard + 1;
        end
        if (guard == 100)
            fail("timed out waiting for active PE job before fault injection");
        @(negedge clk);
        pe_fault[0] = 1'b1;
        @(posedge clk);
        #1;
        if (!pe_abort_pulse)
            fail("PE fault did not pulse pe_abort_pulse");
        wait_for_error(ERR_PE);
        @(negedge clk);
        pe_fault = 3'b000;
        prove_clear_error_cannot_recover(ERR_PE);

        // Explicit abort while the first memory request is stalled.
        apply_reset;
        clear_scoreboard;
        auto_respond = 0;
        stage_req_ready = 1'b0;
        fb_start_ready = 1'b1;
        sb_start_ready = 1'b1;
        df_start_ready = 1'b1;
        pulse_start(0, 0);
        while (!stage_req_valid)
            @(posedge clk);
        @(negedge clk);
        abort = 1'b1;
        @(posedge clk);
        @(negedge clk);
        abort = 1'b0;
        wait_for_error(ERR_ABORT);
        prove_clear_error_cannot_recover(ERR_ABORT);

        // Timeout while the memory service never accepts a request.
        apply_reset;
        clear_scoreboard;
        auto_respond = 0;
        stage_req_ready = 1'b0;
        pulse_start(0, 0);
        wait_for_error(ERR_TIMEOUT);
        prove_clear_error_cannot_recover(ERR_TIMEOUT);

        if (failures == 0) begin
            $display("FSM_METRICS normal_stage_requests=12 subband_commands=27 parallel_triple_starts=3 timeout_cycles=%0d", TIMEOUT_CYCLES);
            $display("PASS tb_fsm");
        end else begin
            $display("FAIL tb_fsm failures=%0d", failures);
            $fatal(1);
        end
        $finish;
    end

endmodule
