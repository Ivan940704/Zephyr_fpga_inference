`timescale 1ns/1ps

module tb_sparse_union_planner_v1;
    reg clk;
    reg rst_n;

    reg plan_req_valid;
    wire plan_req_ready;
    reg [3:0] plan_req_stage_id;
    reg plan_req_sparse_enable;
    reg controller_idle;
    reg producer_busy;
    reg context_commit_valid;
    reg clear_state;
    reg context_error_valid;

    wire list_desc_req_valid;
    wire list_desc_req_ready;
    wire [4:0] list_desc_req_logical_id;
    wire [7:0] list_desc_req_tag;
    reg list_desc_rsp_valid;
    wire list_desc_rsp_ready;
    reg list_desc_rsp_present;
    reg [8:0] list_desc_rsp_count;
    reg [7:0] list_desc_rsp_tag;
    reg list_desc_rsp_error;

    wire list_read_req_valid;
    wire list_read_req_ready;
    wire [4:0] list_read_req_logical_id;
    wire [8:0] list_read_req_ordinal;
    wire [7:0] list_read_req_tag;
    reg list_read_rsp_valid;
    wire list_read_rsp_ready;
    reg [8:0] list_read_rsp_index;
    reg [7:0] list_read_rsp_tag;
    reg list_read_rsp_error;

    wire plan_valid;
    reg plan_ready;
    wire [3:0] plan_stage_id;
    wire plan_sparse_enable;
    wire plan_fallback_full;
    wire [1:0] plan_matrix_count;
    wire [319:0] plan_bitmap0;
    wire [319:0] plan_bitmap1;
    wire [8:0] plan_count0;
    wire [8:0] plan_count1;
    wire planner_busy;
    wire planner_error_valid;
    wire [7:0] planner_error_code;
    wire [31:0] planner_error_detail;
    wire reset_required;

    reg context_present [0:19];
    integer context_count [0:19];
    reg [8:0] context_list [0:19][0:319];

    reg desc_pending_q;
    reg [4:0] desc_id_q;
    reg [7:0] desc_tag_q;
    reg read_pending_q;
    reg [4:0] read_id_q;
    reg [8:0] read_ordinal_q;
    reg [7:0] read_tag_q;
    reg context_ready_enable;
    reg inject_desc_error;
    reg inject_desc_bad_tag;
    reg inject_list_error;
    reg inject_list_bad_tag;
    reg [15:0] cycle_q;
    integer desc_accepts;
    integer read_accepts;
    integer checks;
    integer failures;

    localparam [7:0] ERR_DESC      = 8'h03;
    localparam [7:0] ERR_OWNERSHIP = 8'h02;
    localparam [7:0] ERR_STAGE      = 8'h01;
    localparam [7:0] ERR_MISSING   = 8'h04;
    localparam [7:0] ERR_LIST      = 8'h05;
    localparam [7:0] ERR_INDEX     = 8'h06;
    localparam [7:0] ERR_ORDER     = 8'h07;
    localparam [7:0] ERR_CONTEXT   = 8'h08;

    sparse_union_planner_v1 dut (
        .clk(clk),
        .rst_n(rst_n),
        .plan_req_valid(plan_req_valid),
        .plan_req_ready(plan_req_ready),
        .plan_req_stage_id(plan_req_stage_id),
        .plan_req_sparse_enable(plan_req_sparse_enable),
        .controller_idle(controller_idle),
        .producer_busy(producer_busy),
        .context_commit_valid(context_commit_valid),
        .clear_state(clear_state),
        .context_error_valid(context_error_valid),
        .list_desc_req_valid(list_desc_req_valid),
        .list_desc_req_ready(list_desc_req_ready),
        .list_desc_req_logical_id(list_desc_req_logical_id),
        .list_desc_req_tag(list_desc_req_tag),
        .list_desc_rsp_valid(list_desc_rsp_valid),
        .list_desc_rsp_ready(list_desc_rsp_ready),
        .list_desc_rsp_present(list_desc_rsp_present),
        .list_desc_rsp_count(list_desc_rsp_count),
        .list_desc_rsp_tag(list_desc_rsp_tag),
        .list_desc_rsp_error(list_desc_rsp_error),
        .list_read_req_valid(list_read_req_valid),
        .list_read_req_ready(list_read_req_ready),
        .list_read_req_logical_id(list_read_req_logical_id),
        .list_read_req_ordinal(list_read_req_ordinal),
        .list_read_req_tag(list_read_req_tag),
        .list_read_rsp_valid(list_read_rsp_valid),
        .list_read_rsp_ready(list_read_rsp_ready),
        .list_read_rsp_index(list_read_rsp_index),
        .list_read_rsp_tag(list_read_rsp_tag),
        .list_read_rsp_error(list_read_rsp_error),
        .plan_valid(plan_valid),
        .plan_ready(plan_ready),
        .plan_stage_id(plan_stage_id),
        .plan_sparse_enable(plan_sparse_enable),
        .plan_fallback_full(plan_fallback_full),
        .plan_matrix_count(plan_matrix_count),
        .plan_bitmap0(plan_bitmap0),
        .plan_bitmap1(plan_bitmap1),
        .plan_count0(plan_count0),
        .plan_count1(plan_count1),
        .planner_busy(planner_busy),
        .planner_error_valid(planner_error_valid),
        .planner_error_code(planner_error_code),
        .planner_error_detail(planner_error_detail),
        .reset_required(reset_required)
    );

    always #5 clk = ~clk;

    // The mock store inserts deterministic request backpressure, returns one
    // response at a time, and holds every response until accepted.
    assign list_desc_req_ready = context_ready_enable && !desc_pending_q &&
                                 !list_desc_rsp_valid &&
                                 (cycle_q[1:0] != 2'b00);
    assign list_read_req_ready = context_ready_enable && !read_pending_q &&
                                 !list_read_rsp_valid && cycle_q[0];

    always @(posedge clk) begin
        if (!rst_n) begin
            desc_pending_q <= 1'b0;
            read_pending_q <= 1'b0;
            list_desc_rsp_valid <= 1'b0;
            list_desc_rsp_present <= 1'b0;
            list_desc_rsp_count <= 9'd0;
            list_desc_rsp_tag <= 8'd0;
            list_desc_rsp_error <= 1'b0;
            list_read_rsp_valid <= 1'b0;
            list_read_rsp_index <= 9'd0;
            list_read_rsp_tag <= 8'd0;
            list_read_rsp_error <= 1'b0;
            cycle_q <= 16'd0;
            desc_accepts <= 0;
            read_accepts <= 0;
        end else begin
            cycle_q <= cycle_q + 1'b1;

            if (list_desc_rsp_valid && list_desc_rsp_ready)
                list_desc_rsp_valid <= 1'b0;
            if (list_read_rsp_valid && list_read_rsp_ready)
                list_read_rsp_valid <= 1'b0;

            if (list_desc_req_valid && list_desc_req_ready) begin
                desc_pending_q <= 1'b1;
                desc_id_q <= list_desc_req_logical_id;
                desc_tag_q <= list_desc_req_tag;
                desc_accepts <= desc_accepts + 1;
            end
            if (list_read_req_valid && list_read_req_ready) begin
                read_pending_q <= 1'b1;
                read_id_q <= list_read_req_logical_id;
                read_ordinal_q <= list_read_req_ordinal;
                read_tag_q <= list_read_req_tag;
                read_accepts <= read_accepts + 1;
            end

            if (desc_pending_q && !list_desc_rsp_valid) begin
                desc_pending_q <= 1'b0;
                list_desc_rsp_valid <= 1'b1;
                list_desc_rsp_present <= context_present[desc_id_q];
                list_desc_rsp_count <= context_present[desc_id_q]
                    ? context_count[desc_id_q] : 9'd0;
                list_desc_rsp_tag <= inject_desc_bad_tag
                    ? desc_tag_q + 1'b1 : desc_tag_q;
                list_desc_rsp_error <= inject_desc_error;
            end

            if (read_pending_q && !list_read_rsp_valid) begin
                read_pending_q <= 1'b0;
                list_read_rsp_valid <= 1'b1;
                list_read_rsp_index <=
                    context_list[read_id_q][read_ordinal_q];
                list_read_rsp_tag <= inject_list_bad_tag
                    ? read_tag_q + 1'b1 : read_tag_q;
                list_read_rsp_error <= inject_list_error;
            end
        end
    end

    task automatic check;
        input condition;
        input [8*160-1:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                failures = failures + 1;
                $display("CHECK FAILED: %0s", message);
            end
        end
    endtask

    function automatic integer popcount320;
        input [319:0] value;
        integer bit_index;
        begin
            popcount320 = 0;
            for (bit_index = 0; bit_index < 320;
                 bit_index = bit_index + 1)
                popcount320 = popcount320 + value[bit_index];
        end
    endfunction

    function automatic integer matrix_count_for_stage;
        input integer stage;
        begin
            case (stage)
                2, 5, 8, 11: matrix_count_for_stage = 1;
                default: matrix_count_for_stage = 2;
            endcase
        end
    endfunction

    function automatic integer matrix0_sources_for_stage;
        input integer stage;
        begin
            case (stage)
                0: matrix0_sources_for_stage = 64;
                1, 2: matrix0_sources_for_stage = 320;
                3: matrix0_sources_for_stage = 46;
                6: matrix0_sources_for_stage = 94;
                9: matrix0_sources_for_stage = 158;
                default: matrix0_sources_for_stage = 224;
            endcase
        end
    endfunction

    function automatic integer matrix1_sources_for_stage;
        input integer stage;
        begin
            case (stage)
                0, 1: matrix1_sources_for_stage = 320;
                3, 4, 6, 7, 9, 10:
                    matrix1_sources_for_stage = 224;
                default: matrix1_sources_for_stage = 0;
            endcase
        end
    endfunction

    function automatic integer matrix0_is_mandatory;
        input integer stage;
        begin
            matrix0_is_mandatory =
                (stage == 0) || (stage == 3) ||
                (stage == 6) || (stage == 9);
        end
    endfunction

    task automatic add_context_to_bitmap;
        input integer logical_id;
        inout reg [319:0] bitmap;
        integer ordinal;
        begin
            if (context_present[logical_id]) begin
                for (ordinal = 0; ordinal < context_count[logical_id];
                     ordinal = ordinal + 1)
                    bitmap[context_list[logical_id][ordinal]] = 1'b1;
            end
        end
    endtask

    task automatic expected_plan;
        input integer stage;
        output reg [319:0] bitmap0;
        output reg [319:0] bitmap1;
        integer context_index;
        begin
            bitmap0 = 320'd0;
            bitmap1 = 320'd0;
            case (stage)
                0: add_context_to_bitmap(0, bitmap1);
                1: begin
                    add_context_to_bitmap(0, bitmap0);
                    add_context_to_bitmap(1, bitmap1);
                end
                2: add_context_to_bitmap(1, bitmap0);
                3: for (context_index = 0; context_index < 4;
                        context_index = context_index + 1)
                    add_context_to_bitmap(2 + context_index * 2,
                                          bitmap1);
                4: for (context_index = 0; context_index < 4;
                        context_index = context_index + 1) begin
                    add_context_to_bitmap(2 + context_index * 2,
                                          bitmap0);
                    add_context_to_bitmap(3 + context_index * 2,
                                          bitmap1);
                end
                5: for (context_index = 0; context_index < 4;
                        context_index = context_index + 1)
                    add_context_to_bitmap(3 + context_index * 2,
                                          bitmap0);
                6: for (context_index = 0; context_index < 3;
                        context_index = context_index + 1)
                    add_context_to_bitmap(10 + context_index * 2,
                                          bitmap1);
                7: for (context_index = 0; context_index < 3;
                        context_index = context_index + 1) begin
                    add_context_to_bitmap(10 + context_index * 2,
                                          bitmap0);
                    add_context_to_bitmap(11 + context_index * 2,
                                          bitmap1);
                end
                8: for (context_index = 0; context_index < 3;
                        context_index = context_index + 1)
                    add_context_to_bitmap(11 + context_index * 2,
                                          bitmap0);
                9: for (context_index = 0; context_index < 2;
                        context_index = context_index + 1)
                    add_context_to_bitmap(16 + context_index * 2,
                                          bitmap1);
                10: for (context_index = 0; context_index < 2;
                         context_index = context_index + 1) begin
                    add_context_to_bitmap(16 + context_index * 2,
                                          bitmap0);
                    add_context_to_bitmap(17 + context_index * 2,
                                          bitmap1);
                end
                11: for (context_index = 0; context_index < 2;
                         context_index = context_index + 1)
                    add_context_to_bitmap(17 + context_index * 2,
                                          bitmap0);
            endcase
        end
    endtask

    task automatic initialize_contexts;
        input make_present;
        integer logical_id;
        integer ordinal;
        begin
            for (logical_id = 0; logical_id < 20;
                 logical_id = logical_id + 1) begin
                context_present[logical_id] = make_present;
                context_count[logical_id] = 2;
                context_list[logical_id][0] = logical_id;
                context_list[logical_id][1] = logical_id + 32;
                for (ordinal = 2; ordinal < 320;
                     ordinal = ordinal + 1)
                    context_list[logical_id][ordinal] = 9'd0;
            end
        end
    endtask

    task automatic reset_dut;
        begin
            plan_req_valid = 1'b0;
            plan_req_stage_id = 4'd0;
            plan_req_sparse_enable = 1'b1;
            plan_ready = 1'b0;
            controller_idle = 1'b1;
            producer_busy = 1'b0;
            context_commit_valid = 1'b0;
            clear_state = 1'b0;
            context_error_valid = 1'b0;
            context_ready_enable = 1'b1;
            inject_desc_error = 1'b0;
            inject_desc_bad_tag = 1'b0;
            inject_list_error = 1'b0;
            inject_list_bad_tag = 1'b0;
            rst_n = 1'b0;
            repeat (3) @(posedge clk);
            @(negedge clk);
            rst_n = 1'b1;
        end
    endtask

    task automatic send_request;
        input [3:0] stage;
        input sparse_enable;
        integer timeout;
        begin
            @(negedge clk);
            plan_req_stage_id = stage;
            plan_req_sparse_enable = sparse_enable;
            plan_req_valid = 1'b1;
            timeout = 0;
            while (!plan_req_ready && timeout < 100) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 100) begin
                $display("PLAN_REQ_TIMEOUT time=%0t stage=%0d sparse=%0b state=%0d sticky_error=%0b error_code=0x%02h rst_n=%0b controller_idle=%0b producer_busy=%0b commit=%0b clear=%0b context_error=%0b plan_valid_q=%0b desc_rsp_valid=%0b list_rsp_valid=%0b",
                         $time, stage, sparse_enable, dut.state_q,
                         planner_error_valid, planner_error_code, rst_n,
                         controller_idle, producer_busy,
                         context_commit_valid, clear_state,
                         context_error_valid, dut.plan_valid_q,
                         list_desc_rsp_valid, list_read_rsp_valid);
            end
            check(timeout < 100, "plan request did not become ready");
            @(posedge clk);
            @(negedge clk);
            plan_req_valid = 1'b0;
        end
    endtask

    task automatic wait_for_fault;
        input [7:0] expected_code;
        input [8*160-1:0] message;
        integer timeout;
        begin
            timeout = 0;
            while (!planner_error_valid && timeout < 2000) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            check(timeout < 2000, message);
            check(planner_error_code == expected_code,
                  "planner fault code mismatch");
            check(reset_required && !plan_valid && !plan_req_ready,
                  "fault did not fail closed");
        end
    endtask

    task automatic run_plan;
        input integer stage;
        input sparse_enable;
        reg [319:0] expected0;
        reg [319:0] expected1;
        reg [319:0] held0;
        reg [319:0] held1;
        reg [25:0] held_meta;
        reg expected_full;
        integer timeout;
        begin
            expected_plan(stage, expected0, expected1);
            send_request(stage[3:0], sparse_enable);
            timeout = 0;
            while (!plan_valid && !planner_error_valid && timeout < 20000) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            check(timeout < 20000, "planner timed out");
            check(!planner_error_valid, "legal plan entered fault state");
            check(plan_stage_id == stage[3:0], "plan stage mismatch");
            check(plan_sparse_enable == sparse_enable,
                  "sampled sparse enable mismatch");
            check(plan_matrix_count == matrix_count_for_stage(stage),
                  "matrix count mismatch");
            check(plan_bitmap0 == expected0, "matrix0 union mismatch");
            check(plan_bitmap1 == expected1, "matrix1 union mismatch");
            check(plan_count0 == popcount320(expected0),
                  "matrix0 popcount mismatch");
            check(plan_count1 == popcount320(expected1),
                  "matrix1 popcount mismatch");
            check(!matrix0_is_mandatory(stage) ||
                  ((plan_bitmap0 == 0) && (plan_count0 == 0)),
                  "mandatory dense matrix leaked into union bitmap");
            check((matrix_count_for_stage(stage) == 2) ||
                  ((plan_bitmap1 == 0) && (plan_count1 == 0)),
                  "absent matrix leaked into union bitmap");

            expected_full = !sparse_enable ||
                ((!matrix0_is_mandatory(stage)
                  ? (popcount320(expected0) ==
                     matrix0_sources_for_stage(stage)) : 1'b1) &&
                 ((matrix_count_for_stage(stage) == 2)
                  ? (popcount320(expected1) ==
                     matrix1_sources_for_stage(stage)) : 1'b1));
            check(plan_fallback_full == expected_full,
                  "full-stage fallback mismatch");

            held0 = plan_bitmap0;
            held1 = plan_bitmap1;
            held_meta = {plan_stage_id, plan_sparse_enable,
                         plan_fallback_full, plan_matrix_count,
                         plan_count0, plan_count1};
            repeat (4) begin
                @(posedge clk);
                #1;
                check(plan_valid && (plan_bitmap0 == held0) &&
                      (plan_bitmap1 == held1) &&
                      ({plan_stage_id, plan_sparse_enable,
                        plan_fallback_full, plan_matrix_count,
                        plan_count0, plan_count1} == held_meta),
                      "plan changed under output backpressure");
            end
            @(negedge clk);
            plan_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            plan_ready = 1'b0;
            check(!plan_valid, "plan did not retire after handshake");
        end
    endtask

    integer stage;
    integer ordinal;
    integer desc_before;
    integer reads_before;
    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        checks = 0;
        failures = 0;
        initialize_contexts(1'b1);
        reset_dut();

        // A request and all of its fields remain held until the complete
        // ownership predicate permits acceptance.
        controller_idle = 1'b0;
        fork
            begin
                @(negedge clk);
                repeat (4) begin
                    @(posedge clk);
                    #1;
                    check(plan_req_valid && !plan_req_ready &&
                          (plan_req_stage_id == 4'd0) &&
                          plan_req_sparse_enable,
                          "held plan request changed while unsafe");
                end
                // Change ownership after the final sampled posedge, not on
                // the negedge where send_request also samples ready.  This
                // avoids a testbench active-region race that could let the
                // DUT accept while the request task missed the ready pulse.
                controller_idle = 1'b1;
            end
            begin
                run_plan(0, 1'b1);
            end
        join

        // Every stage is planned with periodic descriptor/list backpressure.
        // The shared stages exercise unions over 4, 3, and 2 contexts.
        for (stage = 0; stage < 12; stage = stage + 1)
            run_plan(stage, 1'b1);

        // Disabled sparse mode still reads and validates all eight mapped
        // lists for stage 4 before publishing a full-load fallback.
        desc_before = desc_accepts;
        reads_before = read_accepts;
        run_plan(4, 1'b0);
        check((desc_accepts - desc_before) == 8,
              "disabled sparse mode skipped descriptors");
        check((read_accepts - reads_before) == 16,
              "disabled sparse mode skipped list entries");

        // Cross-context overlap is legal and must collapse to one union bit.
        reset_dut();
        initialize_contexts(1'b0);
        context_present[2] = 1'b1;
        context_present[4] = 1'b1;
        context_present[6] = 1'b1;
        context_present[8] = 1'b1;
        context_count[2] = 2;
        context_count[4] = 2;
        context_count[6] = 2;
        context_count[8] = 2;
        context_list[2][0] = 9'd1;
        context_list[2][1] = 9'd7;
        context_list[4][0] = 9'd1;
        context_list[4][1] = 9'd8;
        context_list[6][0] = 9'd1;
        context_list[6][1] = 9'd9;
        context_list[8][0] = 9'd1;
        context_list[8][1] = 9'd10;
        run_plan(3, 1'b1);

        // A dense sparse-eligible union selects fallback.  Mandatory/absent
        // matrices remain zero in the result.
        context_present[1] = 1'b1;
        context_count[1] = 320;
        for (ordinal = 0; ordinal < 320; ordinal = ordinal + 1)
            context_list[1][ordinal] = ordinal[8:0];
        run_plan(2, 1'b1);

        // Missing recurrent self-lists are legal empty sets.
        reset_dut();
        initialize_contexts(1'b0);
        run_plan(3, 1'b1);

        // A committed empty predecessor is legal, while the optional self
        // remains a missing/empty first-frame list.
        reset_dut();
        initialize_contexts(1'b0);
        context_present[0] = 1'b1;
        context_count[0] = 0;
        run_plan(1, 1'b1);

        // Missing predecessors are fatal even when full fallback was selected.
        reset_dut();
        initialize_contexts(1'b0);
        send_request(4'd1, 1'b0);
        wait_for_fault(ERR_MISSING,
                       "missing predecessor did not become fatal");

        // Descriptor tag corruption fails closed.
        reset_dut();
        initialize_contexts(1'b1);
        inject_desc_bad_tag = 1'b1;
        send_request(4'd0, 1'b1);
        wait_for_fault(ERR_DESC, "bad descriptor tag was accepted");

        reset_dut();
        initialize_contexts(1'b1);
        inject_desc_error = 1'b1;
        send_request(4'd0, 1'b1);
        wait_for_fault(ERR_DESC, "descriptor error response was accepted");

        // List error and bad tag share the list-response fault class.
        reset_dut();
        initialize_contexts(1'b1);
        inject_list_error = 1'b1;
        send_request(4'd0, 1'b1);
        wait_for_fault(ERR_LIST, "list error response was accepted");

        reset_dut();
        initialize_contexts(1'b1);
        inject_list_bad_tag = 1'b1;
        send_request(4'd0, 1'b1);
        wait_for_fault(ERR_LIST, "bad list tag was accepted");

        // Index bounds and strict per-list ordering are independently checked.
        reset_dut();
        initialize_contexts(1'b1);
        context_count[0] = 1;
        context_list[0][0] = 9'd320;
        send_request(4'd0, 1'b1);
        wait_for_fault(ERR_INDEX, "out-of-range list index was accepted");

        reset_dut();
        initialize_contexts(1'b1);
        context_count[0] = 2;
        context_list[0][0] = 9'd7;
        context_list[0][1] = 9'd7;
        send_request(4'd0, 1'b1);
        wait_for_fault(ERR_ORDER, "duplicate list index was accepted");

        // Losing ownership while a completed result is backpressured must
        // discard even that complete-looking plan and enter reset-only fault.
        reset_dut();
        initialize_contexts(1'b1);
        send_request(4'd0, 1'b1);
        while (!plan_valid && !planner_error_valid)
            @(posedge clk);
        @(negedge clk);
        producer_busy = 1'b1;
        wait_for_fault(ERR_OWNERSHIP,
                       "ownership loss did not discard held plan");

        // A context-side sticky error propagates even while the planner is idle.
        reset_dut();
        initialize_contexts(1'b1);
        @(negedge clk);
        context_error_valid = 1'b1;
        wait_for_fault(ERR_CONTEXT, "context fault did not propagate");

        // An illegal stage request is accepted only to produce a sticky,
        // fail-closed diagnostic; it never publishes a result.
        reset_dut();
        initialize_contexts(1'b1);
        send_request(4'd12, 1'b1);
        wait_for_fault(ERR_STAGE, "illegal stage did not fault");

        if (failures == 0)
            $display("PASS tb_sparse_union_planner_v1 checks=%0d", checks);
        else
            $fatal(1, "FAIL tb_sparse_union_planner_v1 failures=%0d checks=%0d",
                   failures, checks);
        #20;
        $finish;
    end
endmodule
