`timescale 1ns/1ps

module tb_sequential_df_coefficient_store;
    reg clk;
    reg rst_n;
    reg abort;
    reg [15:0] current_frame_id;
    reg frame_start;
    reg frame_done;
    reg consume_start;

    reg coefficient_valid;
    wire coefficient_ready;
    reg signed [7:0] coefficient_value;
    reg [8:0] coefficient_index;
    reg [15:0] coefficient_tag;
    reg coefficient_last;
    reg [3:0] coefficient_stage_id;

    reg read_req_valid;
    wire read_req_ready;
    reg [10:0] read_req_address;
    wire read_rsp_valid;
    reg read_rsp_ready;
    wire signed [7:0] read_rsp_value;
    wire read_rsp_error;

    wire [8:0] context_valid;
    wire all_coefficients_valid;
    wire frame_active;
    wire [15:0] stored_frame_id;
    wire stream_active;
    wire error_valid;
    wire [7:0] error_code;
    wire [31:0] error_detail;

    integer failures;
    integer checks;
    integer accepted_coefficients;

    sequential_df_coefficient_store dut (
        .clk(clk),
        .rst_n(rst_n),
        .abort(abort),
        .current_frame_id(current_frame_id),
        .frame_start(frame_start),
        .frame_done(frame_done),
        .consume_start(consume_start),
        .coefficient_valid(coefficient_valid),
        .coefficient_ready(coefficient_ready),
        .coefficient_value(coefficient_value),
        .coefficient_index(coefficient_index),
        .coefficient_tag(coefficient_tag),
        .coefficient_last(coefficient_last),
        .coefficient_stage_id(coefficient_stage_id),
        .read_req_valid(read_req_valid),
        .read_req_ready(read_req_ready),
        .read_req_address(read_req_address),
        .read_rsp_valid(read_rsp_valid),
        .read_rsp_ready(read_rsp_ready),
        .read_rsp_value(read_rsp_value),
        .read_rsp_error(read_rsp_error),
        .context_valid(context_valid),
        .all_coefficients_valid(all_coefficients_valid),
        .frame_active(frame_active),
        .stored_frame_id(stored_frame_id),
        .stream_active(stream_active),
        .error_valid(error_valid),
        .error_code(error_code),
        .error_detail(error_detail)
    );

    always #5 clk = ~clk;

    function automatic [7:0] expected_value;
        input integer address;
        begin
            expected_value = (address * 13 + 7) & 8'hff;
        end
    endfunction

    function automatic integer context_count;
        input integer stage_id;
        begin
            case (stage_id)
                5: context_count = 4;
                8: context_count = 3;
                default: context_count = 2;
            endcase
        end
    endfunction

    function automatic integer coefficient_count;
        input integer stage_id;
        begin
            case (stage_id)
                5: coefficient_count = 80;
                8: coefficient_count = 192;
                default: coefficient_count = 128;
            endcase
        end
    endfunction

    function automatic integer logical_id;
        input integer stage_id;
        input integer context_id;
        begin
            case (stage_id)
                5: logical_id = 3 + context_id * 2;
                8: logical_id = 11 + context_id * 2;
                default: logical_id = 17 + context_id * 2;
            endcase
        end
    endfunction

    function automatic integer store_base;
        input integer stage_id;
        input integer context_id;
        begin
            case (stage_id)
                5: store_base = context_id * 80;
                8: store_base = 320 + context_id * 192;
                default: store_base = 896 + context_id * 128;
            endcase
        end
    endfunction

    task automatic fail;
        input string message;
        begin
            failures = failures + 1;
            $display("FAIL: %s time=%0t code=%02x detail=%08x",
                     message, $time, error_code, error_detail);
        end
    endtask

    task automatic check;
        input bit condition;
        input string message;
        begin
            checks = checks + 1;
            if (!condition)
                fail(message);
        end
    endtask

    task automatic reset_dut;
        begin
            @(negedge clk);
            rst_n = 1'b0;
            coefficient_valid = 1'b0;
            read_req_valid = 1'b0;
            read_rsp_ready = 1'b0;
            frame_start = 1'b0;
            frame_done = 1'b0;
            consume_start = 1'b0;
            repeat (4) @(posedge clk);
            @(negedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic pulse_frame_start;
        begin
            @(negedge clk);
            frame_start = 1'b1;
            @(posedge clk);
            @(negedge clk);
            frame_start = 1'b0;
            check(frame_active, "frame_start did not acquire the store");
            check(stored_frame_id == current_frame_id,
                  "stored frame ID mismatch");
        end
    endtask

    task automatic send_context;
        input integer stage_id;
        input integer context_id;
        integer index;
        integer count;
        integer base;
        integer lid;
        begin
            count = coefficient_count(stage_id);
            base = store_base(stage_id, context_id);
            lid = logical_id(stage_id, context_id);
            for (index = 0; index < count; index = index + 1) begin
                @(negedge clk);
                coefficient_stage_id = stage_id[3:0];
                coefficient_index = index[8:0];
                coefficient_tag = {2'b01, lid[4:0], index[8:0]};
                coefficient_value = expected_value(base + index);
                coefficient_last = (index == count - 1);
                coefficient_valid = 1'b1;
                while (!coefficient_ready)
                    @(negedge clk);
                @(posedge clk);
                accepted_coefficients = accepted_coefficients + 1;
            end
            @(negedge clk);
            coefficient_valid = 1'b0;
            coefficient_last = 1'b0;
            check(!stream_active, "completed context left stream active");
        end
    endtask

    task automatic check_read;
        input integer address;
        input integer stall_cycles;
        integer stall;
        reg signed [7:0] held_value;
        begin
            @(negedge clk);
            read_req_address = address[10:0];
            read_req_valid = 1'b1;
            while (!read_req_ready)
                @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            read_req_valid = 1'b0;
            while (!read_rsp_valid)
                @(negedge clk);
            check(!read_rsp_error, "legal coefficient read returned error");
            check(read_rsp_value === expected_value(address),
                  "coefficient read value mismatch");
            held_value = read_rsp_value;
            for (stall = 0; stall < stall_cycles; stall = stall + 1) begin
                @(posedge clk);
                @(negedge clk);
                check(read_rsp_valid && (read_rsp_value === held_value),
                      "read response changed under backpressure");
            end
            read_rsp_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            read_rsp_ready = 1'b0;
            check(!read_rsp_valid, "read response did not retire");
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        abort = 1'b0;
        current_frame_id = 16'h1234;
        frame_start = 1'b0;
        frame_done = 1'b0;
        consume_start = 1'b0;
        coefficient_valid = 1'b0;
        coefficient_value = 8'sd0;
        coefficient_index = 9'd0;
        coefficient_tag = 16'd0;
        coefficient_last = 1'b0;
        coefficient_stage_id = 4'd0;
        read_req_valid = 1'b0;
        read_req_address = 11'd0;
        read_rsp_ready = 1'b0;
        failures = 0;
        checks = 0;
        accepted_coefficients = 0;

        repeat (6) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        pulse_frame_start();

        send_context(5, 0);
        send_context(5, 1);
        send_context(5, 2);
        send_context(5, 3);
        send_context(8, 0);
        send_context(8, 1);
        send_context(8, 2);
        send_context(11, 0);
        send_context(11, 1);

        check(accepted_coefficients == 1152,
              "coefficient stream length mismatch");
        check(context_valid == 9'h1ff,
              "not all nine context packets committed");
        check(all_coefficients_valid,
              "all_coefficients_valid did not assert");

        @(negedge clk);
        consume_start = 1'b1;
        @(posedge clk);
        @(negedge clk);
        consume_start = 1'b0;
        check(!error_valid, "complete coefficient set rejected consume_start");

        check_read(0, 0);
        check_read(79, 2);
        check_read(80, 0);
        check_read(319, 0);
        check_read(320, 1);
        check_read(511, 0);
        check_read(895, 0);
        check_read(896, 0);
        check_read(1023, 0);
        check_read(1151, 3);

        @(negedge clk);
        frame_done = 1'b1;
        @(posedge clk);
        @(negedge clk);
        frame_done = 1'b0;
        check(!frame_active && !all_coefficients_valid,
              "frame_done did not release coefficient ownership");

        // Wrong kind is an identity fault.
        reset_dut();
        pulse_frame_start();
        @(negedge clk);
        coefficient_stage_id = 4'd5;
        coefficient_index = 9'd0;
        coefficient_tag = {2'b00, 5'd3, 9'd0};
        coefficient_value = 8'sd1;
        coefficient_last = 1'b0;
        coefficient_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        coefficient_valid = 1'b0;
        check(error_valid && (error_code == 8'h63),
              "wrong coefficient tag kind did not fault");

        // A stream may only begin at coefficient index zero.
        reset_dut();
        pulse_frame_start();
        @(negedge clk);
        coefficient_stage_id = 4'd8;
        coefficient_index = 9'd1;
        coefficient_tag = {2'b01, 5'd11, 9'd1};
        coefficient_value = 8'sd2;
        coefficient_last = 1'b0;
        coefficient_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        coefficient_valid = 1'b0;
        check(error_valid && (error_code == 8'h64),
              "out-of-order first coefficient did not fault");

        // TLAST must match the stage-specific packet length.
        reset_dut();
        pulse_frame_start();
        @(negedge clk);
        coefficient_stage_id = 4'd11;
        coefficient_index = 9'd0;
        coefficient_tag = {2'b01, 5'd17, 9'd0};
        coefficient_value = 8'sd3;
        coefficient_last = 1'b1;
        coefficient_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        coefficient_valid = 1'b0;
        check(error_valid && (error_code == 8'h65),
              "early coefficient_last did not fault");

        // DeepFilter may not start before all nine packets commit.
        reset_dut();
        pulse_frame_start();
        @(negedge clk);
        consume_start = 1'b1;
        @(posedge clk);
        @(negedge clk);
        consume_start = 1'b0;
        check(error_valid && (error_code == 8'h67),
              "incomplete coefficient set accepted consume_start");

        if (failures == 0)
            $display("PASS tb_sequential_df_coefficient_store checks=%0d coefficients=%0d",
                     checks, accepted_coefficients);
        else
            $fatal(1,
                "FAIL tb_sequential_df_coefficient_store errors=%0d checks=%0d",
                failures, checks);
        #20;
        $finish;
    end
endmodule
