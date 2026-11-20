`timescale 1ns/1ps

module tb_sequential_recurrent_context_store_v5;
    reg clk;
    reg rst_n;
    reg clear_state;

    reg producer_open_valid;
    wire producer_open_ready;
    reg [4:0] producer_open_logical_id;
    reg [5:0] producer_open_row_tiles;

    reg list_desc_req_valid;
    wire list_desc_req_ready;
    reg [4:0] list_desc_req_logical_id;
    reg [7:0] list_desc_req_tag;
    wire list_desc_rsp_valid;
    reg list_desc_rsp_ready;
    wire [8:0] list_desc_rsp_count;
    wire [7:0] list_desc_rsp_tag;
    wire list_desc_rsp_error;

    reg list_read_req_valid;
    wire list_read_req_ready;
    reg [4:0] list_read_req_logical_id;
    reg [8:0] list_read_req_ordinal;
    reg [7:0] list_read_req_tag;
    wire list_read_rsp_valid;
    reg list_read_rsp_ready;
    wire [8:0] list_read_rsp_index;
    wire [7:0] list_read_rsp_tag;
    wire list_read_rsp_error;

    reg state_read_req_valid;
    wire state_read_req_ready;
    reg [4:0] state_read_req_logical_id;
    reg [4:0] state_read_req_row_tile;
    reg [7:0] state_read_req_tag;
    wire state_read_rsp_valid;
    reg state_read_rsp_ready;
    wire [255:0] state_read_rsp_data;
    wire [7:0] state_read_rsp_tag;
    wire state_read_rsp_error;

    reg state_write_valid;
    wire state_write_ready;
    reg signed [7:0] state_write_value;
    reg [8:0] state_write_index;
    reg [15:0] state_write_tag;
    reg state_write_last;

    reg active_cmd_valid;
    wire active_cmd_ready;
    reg active_cmd_write;
    reg [8:0] active_cmd_index;
    reg [15:0] active_cmd_tag;
    reg active_cmd_finalize;

    reg commit_valid;
    wire commit_ready;
    reg [4:0] commit_logical_id;
    reg pe_barrier_idle;
    wire commit_done;

    wire producer_busy;
    wire [4:0] producer_logical_id;
    wire [5:0] producer_row_tiles;
    wire [8:0] producer_list_count;
    wire error_valid;
    wire [7:0] error_code;
    wire [31:0] error_detail;
    wire reset_required;

    sequential_recurrent_context_store_v5 dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear_state(clear_state),
        .producer_open_valid(producer_open_valid),
        .producer_open_ready(producer_open_ready),
        .producer_open_logical_id(producer_open_logical_id),
        .producer_open_row_tiles(producer_open_row_tiles),
        .list_desc_req_valid(list_desc_req_valid),
        .list_desc_req_ready(list_desc_req_ready),
        .list_desc_req_logical_id(list_desc_req_logical_id),
        .list_desc_req_tag(list_desc_req_tag),
        .list_desc_rsp_valid(list_desc_rsp_valid),
        .list_desc_rsp_ready(list_desc_rsp_ready),
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
        .state_read_req_valid(state_read_req_valid),
        .state_read_req_ready(state_read_req_ready),
        .state_read_req_logical_id(state_read_req_logical_id),
        .state_read_req_row_tile(state_read_req_row_tile),
        .state_read_req_tag(state_read_req_tag),
        .state_read_rsp_valid(state_read_rsp_valid),
        .state_read_rsp_ready(state_read_rsp_ready),
        .state_read_rsp_data(state_read_rsp_data),
        .state_read_rsp_tag(state_read_rsp_tag),
        .state_read_rsp_error(state_read_rsp_error),
        .state_write_valid(state_write_valid),
        .state_write_ready(state_write_ready),
        .state_write_value(state_write_value),
        .state_write_index(state_write_index),
        .state_write_tag(state_write_tag),
        .state_write_last(state_write_last),
        .active_cmd_valid(active_cmd_valid),
        .active_cmd_ready(active_cmd_ready),
        .active_cmd_write(active_cmd_write),
        .active_cmd_index(active_cmd_index),
        .active_cmd_tag(active_cmd_tag),
        .active_cmd_finalize(active_cmd_finalize),
        .commit_valid(commit_valid),
        .commit_ready(commit_ready),
        .commit_logical_id(commit_logical_id),
        .pe_barrier_idle(pe_barrier_idle),
        .commit_done(commit_done),
        .producer_busy(producer_busy),
        .producer_logical_id(producer_logical_id),
        .producer_row_tiles(producer_row_tiles),
        .producer_list_count(producer_list_count),
        .error_valid(error_valid),
        .error_code(error_code),
        .error_detail(error_detail),
        .reset_required(reset_required)
    );

    integer failures;
    integer checks;
    integer logical_id;
    integer tile;
    integer lane;
    integer neuron;
    integer expected_count;
    integer expected_indices [0:319];

    always #5 clk = ~clk;

    task fail;
        input [8*180-1:0] message;
        begin
            failures = failures + 1;
            $display("FAIL: %0s at time %0t", message, $time);
        end
    endtask

    task check;
        input condition;
        input [8*180-1:0] message;
        begin
            checks = checks + 1;
            if (!condition)
                fail(message);
        end
    endtask

    function [5:0] rows_for_id;
        input integer id_value;
        begin
            if (id_value < 2)
                rows_for_id = 6'd10;
            else
                rows_for_id = 6'd7;
        end
    endfunction

    function [7:0] state_value_for;
        input integer id_value;
        input integer frame_value;
        input integer index_value;
        integer mixed;
        begin
            mixed = ((id_value * 17) + (frame_value * 53) +
                     index_value) % 255;
            state_value_for = mixed + 1;
        end
    endfunction

    function is_active_for;
        input integer id_value;
        input integer frame_value;
        input integer index_value;
        begin
            if ((id_value == 0) && (frame_value == 0))
                is_active_for = 1'b1;
            else if ((id_value == 1) && (frame_value == 0))
                is_active_for = ((index_value % 32) == 0);
            else if ((id_value == 19) && (frame_value == 0))
                is_active_for = 1'b0;
            else if ((id_value == 0) && (frame_value == 1))
                is_active_for = ((index_value % 20) < 11);
            else
                is_active_for = ((index_value % 4) == (id_value % 4));
        end
    endfunction

    task reset_dut;
        begin
            rst_n = 1'b0;
            clear_state = 1'b0;
            producer_open_valid = 1'b0;
            list_desc_req_valid = 1'b0;
            list_desc_rsp_ready = 1'b0;
            list_read_req_valid = 1'b0;
            list_read_rsp_ready = 1'b0;
            state_read_req_valid = 1'b0;
            state_read_rsp_ready = 1'b0;
            state_write_valid = 1'b0;
            active_cmd_valid = 1'b0;
            commit_valid = 1'b0;
            pe_barrier_idle = 1'b0;
            repeat (5) @(posedge clk);
            @(negedge clk);
            rst_n = 1'b1;
            repeat (3) @(posedge clk);
        end
    endtask

    task open_producer;
        input [4:0] id_value;
        input [5:0] row_tiles_value;
        begin
            @(negedge clk);
            producer_open_logical_id = id_value;
            producer_open_row_tiles = row_tiles_value;
            producer_open_valid = 1'b1;
            while (!producer_open_ready)
                @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            producer_open_valid = 1'b0;
            check(producer_busy &&
                  (producer_logical_id == id_value) &&
                  (producer_row_tiles == row_tiles_value),
                  "producer open status mismatch");
        end
    endtask

    task read_descriptor;
        input [4:0] id_value;
        input [7:0] tag_value;
        input [8:0] expected_value;
        input expected_error;
        integer timeout;
        reg [8:0] held_count;
        begin
            @(negedge clk);
            list_desc_req_logical_id = id_value;
            list_desc_req_tag = tag_value;
            list_desc_req_valid = 1'b1;
            while (!list_desc_req_ready)
                @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            list_desc_req_valid = 1'b0;
            timeout = 0;
            while (!list_desc_rsp_valid && timeout < 20) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            check(timeout < 20, "descriptor response timeout");
            check((list_desc_rsp_count === expected_value) &&
                  (list_desc_rsp_tag === tag_value) &&
                  (list_desc_rsp_error === expected_error),
                  "descriptor response mismatch");
            held_count = list_desc_rsp_count;
            repeat (2) begin
                @(posedge clk);
                #1;
                check(list_desc_rsp_valid &&
                      (list_desc_rsp_count === held_count) &&
                      (list_desc_rsp_tag === tag_value),
                      "descriptor changed while stalled");
            end
            @(negedge clk);
            list_desc_rsp_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            list_desc_rsp_ready = 1'b0;
        end
    endtask

    task read_list_item;
        input [4:0] id_value;
        input [8:0] ordinal_value;
        input [7:0] tag_value;
        input [8:0] expected_value;
        input expected_error;
        integer timeout;
        reg [8:0] held_index;
        begin
            @(negedge clk);
            list_read_req_logical_id = id_value;
            list_read_req_ordinal = ordinal_value;
            list_read_req_tag = tag_value;
            list_read_req_valid = 1'b1;
            while (!list_read_req_ready)
                @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            list_read_req_valid = 1'b0;
            timeout = 0;
            while (!list_read_rsp_valid && timeout < 20) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            check(timeout < 20, "list response timeout");
            check((list_read_rsp_index === expected_value) &&
                  (list_read_rsp_tag === tag_value) &&
                  (list_read_rsp_error === expected_error),
                  "list response mismatch");
            held_index = list_read_rsp_index;
            repeat (2) begin
                @(posedge clk);
                #1;
                check(list_read_rsp_valid &&
                      (list_read_rsp_index === held_index) &&
                      (list_read_rsp_tag === tag_value),
                      "list response changed while stalled");
            end
            @(negedge clk);
            list_read_rsp_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            list_read_rsp_ready = 1'b0;
        end
    endtask

    task read_state_tile;
        input [4:0] id_value;
        input [4:0] tile_value;
        input [7:0] tag_value;
        input old_valid;
        input integer old_frame;
        integer timeout;
        integer check_lane;
        reg [255:0] held_data;
        begin
            @(negedge clk);
            state_read_req_logical_id = id_value;
            state_read_req_row_tile = tile_value;
            state_read_req_tag = tag_value;
            state_read_req_valid = 1'b1;
            while (!state_read_req_ready)
                @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            state_read_req_valid = 1'b0;
            timeout = 0;
            while (!state_read_rsp_valid && timeout < 20) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            check(timeout < 20, "state response timeout");
            check((state_read_rsp_tag === tag_value) &&
                  !state_read_rsp_error,
                  "state response metadata mismatch");
            for (check_lane = 0; check_lane < 32;
                 check_lane = check_lane + 1) begin
                if (old_valid)
                    check(state_read_rsp_data[check_lane*8 +: 8] ===
                          state_value_for(id_value, old_frame,
                                          tile_value*32 + check_lane),
                          "retained state byte mismatch");
                else
                    check(state_read_rsp_data[check_lane*8 +: 8] === 8'd0,
                          "uninitialized state was not zero");
            end
            held_data = state_read_rsp_data;
            repeat (2) begin
                @(posedge clk);
                #1;
                check(state_read_rsp_valid &&
                      (state_read_rsp_data === held_data) &&
                      (state_read_rsp_tag === tag_value),
                      "state response changed while stalled");
            end
            @(negedge clk);
            state_read_rsp_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            state_read_rsp_ready = 1'b0;
        end
    endtask

    task send_state_write;
        input [4:0] id_value;
        input [8:0] index_value;
        input [7:0] value;
        input last_value;
        begin
            @(negedge clk);
            state_write_index = index_value;
            state_write_value = value;
            state_write_tag = {2'b00, id_value, index_value};
            state_write_last = last_value;
            state_write_valid = 1'b1;
            while (!state_write_ready)
                @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            state_write_valid = 1'b0;
        end
    endtask

    task send_active_cmd;
        input [4:0] id_value;
        input [8:0] index_value;
        input write_value;
        input finalize_value;
        begin
            @(negedge clk);
            active_cmd_write = write_value;
            active_cmd_index = index_value;
            active_cmd_tag = {2'b00, id_value, index_value};
            active_cmd_finalize = finalize_value;
            active_cmd_valid = 1'b1;
            while (!active_cmd_ready)
                @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            active_cmd_valid = 1'b0;
        end
    endtask

    task commit_producer;
        input [4:0] id_value;
        begin
            repeat (2) @(posedge clk);
            @(negedge clk);
            pe_barrier_idle = 1'b1;
            commit_logical_id = id_value;
            commit_valid = 1'b1;
            check(commit_ready, "completed producer was not commit-ready");
            @(posedge clk);
            #1;
            check(commit_done, "legal commit did not pulse done");
            @(negedge clk);
            commit_valid = 1'b0;
            pe_barrier_idle = 1'b0;
            check(!producer_busy, "legal commit did not close producer");
        end
    endtask

    task run_frame;
        input integer id_value;
        input integer frame_value;
        input old_valid;
        input integer old_frame;
        integer total_neurons;
        integer local_index;
        integer local_tile;
        integer local_lane;
        integer local_count;
        begin
            total_neurons = rows_for_id(id_value) * 32;
            open_producer(id_value[4:0], rows_for_id(id_value));

            // The committed old list remains visible after producer open.
            if (old_valid) begin
                if ((id_value == 0) && (old_frame == 0)) begin
                    read_descriptor(id_value[4:0], 8'hd0, 9'd320, 1'b0);
                    read_list_item(id_value[4:0], 9'd0,
                                   8'hd1, 9'd0, 1'b0);
                    read_list_item(id_value[4:0], 9'd319,
                                   8'hd2, 9'd319, 1'b0);
                end
            end

            local_count = 0;
            for (local_tile = 0;
                 local_tile < rows_for_id(id_value);
                 local_tile = local_tile + 1) begin
                read_state_tile(id_value[4:0], local_tile[4:0],
                                local_tile[7:0], old_valid, old_frame);
                for (local_lane = 0; local_lane < 32;
                     local_lane = local_lane + 1) begin
                    local_index = local_tile*32 + local_lane;
                    send_state_write(
                        id_value[4:0], local_index[8:0],
                        state_value_for(id_value, frame_value, local_index),
                        local_index == (total_neurons - 1));
                    if (is_active_for(id_value, frame_value, local_index)) begin
                        expected_indices[local_count] = local_index;
                        local_count = local_count + 1;
                        send_active_cmd(
                            id_value[4:0], local_index[8:0], 1'b1,
                            local_index == (total_neurons - 1));
                    end else if (local_index == (total_neurons - 1)) begin
                        send_active_cmd(
                            id_value[4:0], local_index[8:0], 1'b0, 1'b1);
                    end
                end
            end
            expected_count = local_count;
            check(producer_list_count == local_count,
                  "producer active count mismatch before commit");
            commit_producer(id_value[4:0]);
            read_descriptor(id_value[4:0], 8'he0,
                            local_count[8:0], 1'b0);
            for (local_index = 0; local_index < local_count;
                 local_index = local_index + 1)
                read_list_item(id_value[4:0], local_index[8:0],
                               local_index[7:0],
                               expected_indices[local_index][8:0], 1'b0);
        end
    endtask

    integer timeout;
    initial begin
        #5_000_000;
        $fatal(1, "FAIL tb_sequential_recurrent_context_store_v5 timeout");
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        clear_state = 1'b0;
        producer_open_valid = 1'b0;
        producer_open_logical_id = 5'd0;
        producer_open_row_tiles = 6'd0;
        list_desc_req_valid = 1'b0;
        list_desc_req_logical_id = 5'd0;
        list_desc_req_tag = 8'd0;
        list_desc_rsp_ready = 1'b0;
        list_read_req_valid = 1'b0;
        list_read_req_logical_id = 5'd0;
        list_read_req_ordinal = 9'd0;
        list_read_req_tag = 8'd0;
        list_read_rsp_ready = 1'b0;
        state_read_req_valid = 1'b0;
        state_read_req_logical_id = 5'd0;
        state_read_req_row_tile = 5'd0;
        state_read_req_tag = 8'd0;
        state_read_rsp_ready = 1'b0;
        state_write_valid = 1'b0;
        state_write_value = 8'd0;
        state_write_index = 9'd0;
        state_write_tag = 16'd0;
        state_write_last = 1'b0;
        active_cmd_valid = 1'b0;
        active_cmd_write = 1'b0;
        active_cmd_index = 9'd0;
        active_cmd_tag = 16'd0;
        active_cmd_finalize = 1'b0;
        commit_valid = 1'b0;
        commit_logical_id = 5'd0;
        pe_barrier_idle = 1'b0;
        failures = 0;
        checks = 0;

        reset_dut();

        // All logical identities begin with zero state and zero list count.
        for (logical_id = 0; logical_id < 20;
             logical_id = logical_id + 1) begin
            read_descriptor(logical_id[4:0], logical_id[7:0],
                            9'd0, 1'b0);
            read_state_tile(logical_id[4:0], 5'd0,
                            logical_id[7:0], 1'b0, 0);
        end

        // Exercise every FB/SB logical identity. Patterns include dense,
        // low-density, 25 percent, and zero-active lists.
        for (logical_id = 0; logical_id < 20;
             logical_id = logical_id + 1)
            run_frame(logical_id, 0, 1'b0, 0);

        // Same-identity second frame proves old-state retention and physical
        // producer-slot swap. This pattern is exactly 55 percent active.
        run_frame(0, 1, 1'b1, 0);
        check(expected_count == 176,
              "55-percent pattern produced wrong count");

        // Legal metadata-only clear restores first-frame behavior.
        @(negedge clk);
        clear_state = 1'b1;
        @(posedge clk);
        @(negedge clk);
        clear_state = 1'b0;
        read_descriptor(5'd0, 8'hf0, 9'd0, 1'b0);
        read_state_tile(5'd0, 5'd0, 8'hf1, 1'b0, 0);

        // Old-state-read-before-write violation is fail-stop.
        open_producer(5'd0, 6'd1);
        send_state_write(5'd0, 9'd0, 8'h11, 1'b0);
        check(error_valid && reset_required && (error_code == 8'h05),
              "unsafe state write was not fatal");

        // Invalid list ordinal returns one error response and enters fatal.
        reset_dut();
        read_list_item(5'd0, 9'd0, 8'hf2, 9'd0, 1'b1);
        check(error_valid && (error_code == 8'h03),
              "invalid list read was not fatal");

        // Bad active ordering is detected without a payload append.
        reset_dut();
        open_producer(5'd0, 6'd1);
        send_active_cmd(5'd0, 9'd3, 1'b1, 1'b0);
        send_active_cmd(5'd0, 9'd3, 1'b1, 1'b0);
        check(error_valid && (error_code == 8'h06),
              "duplicate active index was not fatal");

        // Premature commit is accepted as a checked operation, then fails.
        reset_dut();
        open_producer(5'd0, 6'd1);
        @(negedge clk);
        commit_logical_id = 5'd0;
        pe_barrier_idle = 1'b1;
        commit_valid = 1'b1;
        check(commit_ready, "open producer did not expose commit channel");
        @(posedge clk);
        @(negedge clk);
        commit_valid = 1'b0;
        pe_barrier_idle = 1'b0;
        check(error_valid && (error_code == 8'h07),
              "premature commit was not fatal");

        // clear_state while producer-owned is also fail-stop.
        reset_dut();
        open_producer(5'd0, 6'd1);
        @(negedge clk);
        clear_state = 1'b1;
        @(posedge clk);
        @(negedge clk);
        clear_state = 1'b0;
        check(error_valid && (error_code == 8'h08),
              "busy clear_state was not fatal");

        // Reset cancels all fault/ownership state without scrubbing payload.
        reset_dut();
        check(!error_valid && !reset_required && !producer_busy &&
              producer_open_ready,
              "reset did not restore clean metadata state");

        if (failures == 0)
            $display("PASS tb_sequential_recurrent_context_store_v5 checks=%0d",
                     checks);
        else
            $fatal(1, "FAIL tb_sequential_recurrent_context_store_v5 errors=%0d checks=%0d",
                   failures, checks);
        #20;
        $finish;
    end
endmodule
