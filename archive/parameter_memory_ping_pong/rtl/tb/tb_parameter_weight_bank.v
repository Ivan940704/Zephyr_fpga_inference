`timescale 1ns/1ps

// Self-checking Phase-B testbench for one physical parameter weight bank.
// The testbench intentionally uses Verilog-2001 syntax so that the focused
// XSim flow does not depend on SystemVerilog parsing.
module tb_parameter_weight_bank;
    localparam [2:0] ST_INVALID  = 3'd0;
    localparam [2:0] ST_LOADING  = 3'd1;
    localparam [2:0] ST_READY    = 3'd2;
    localparam [2:0] ST_ACTIVE   = 3'd3;
    localparam [2:0] ST_DRAINING = 3'd4;
    localparam [2:0] ST_RETAINED = 3'd5;
    localparam [2:0] ST_ERROR    = 3'd6;

    localparam [3:0] OP_CLAIM          = 4'h0;
    localparam [3:0] OP_PUBLISH_READY  = 4'h1;
    localparam [3:0] OP_ACTIVATE       = 4'h2;
    localparam [3:0] OP_BEGIN_DRAIN    = 4'h3;
    localparam [3:0] OP_FINISH_DRAIN   = 4'h4;
    localparam [3:0] OP_EARLY_RETIRE   = 4'h5;
    localparam [3:0] OP_EVICT_RETAINED = 4'h6;
    localparam [3:0] OP_CLEAR_ERROR    = 4'h7;

    localparam [1:0] TARGET_INVALID  = 2'b00;
    localparam [1:0] TARGET_RETAINED = 2'b01;
    localparam [1:0] TARGET_ERROR    = 2'b10;

    localparam [7:0] STATUS_OK                  = 8'h00;
    localparam [7:0] ERR_BAD_OPCODE             = 8'h01;
    localparam [7:0] ERR_WRONG_STATE            = 8'h02;
    localparam [7:0] ERR_STALE_GENERATION       = 8'h03;
    localparam [7:0] ERR_OWNER_MISMATCH         = 8'h04;
    localparam [7:0] ERR_NOT_QUIESCENT          = 8'h05;
    localparam [7:0] ERR_EXTERNAL_UNSAFE        = 8'h06;
    localparam [7:0] ERR_GENERATION_EXHAUSTED   = 8'h07;
    localparam [7:0] ERR_BAD_DRAIN_TARGET       = 8'h08;
    localparam [7:0] ERR_ABORTED                = 8'h09;
    localparam [7:0] ERR_LOCAL_PROTOCOL         = 8'h0a;
    localparam [7:0] ERR_INTERNAL_STATE         = 8'h0b;

    localparam [1:0] ERROR_SOURCE_LOADER   = 2'b00;
    localparam [1:0] ERROR_SOURCE_READ     = 2'b01;
    localparam [1:0] ERROR_SOURCE_INTERNAL = 2'b10;
    localparam [1:0] ERROR_SOURCE_FORCE    = 2'b11;

    localparam [31:0] TICKET_1 = 32'h1000_0001;
    localparam [31:0] TICKET_2 = 32'h2000_0002;
    localparam [31:0] TICKET_3 = 32'h3000_0003;
    localparam [31:0] TICKET_4 = 32'h4000_0004;
    localparam [31:0] TICKET_5 = 32'h5000_0005;
    localparam [31:0] TICKET_6 = 32'h6000_0006;
    localparam [31:0] TICKET_7 = 32'h7000_0007;
    localparam [31:0] TICKET_8 = 32'h8000_0008;
    localparam [31:0] TICKET_9 = 32'h9000_0009;
    localparam [31:0] TICKET_A = 32'ha000_000a;

    reg clk;
    reg rst_n;

    reg         force_error_valid;
    wire        force_error_ready;
    reg  [7:0]  force_error_code;

    wire [2:0]  bank_state;
    wire [31:0] bank_generation;
    wire        bank_generation_initialized;
    wire        bank_authority_valid;
    wire        bank_lease_owner_valid;
    wire [31:0] bank_lease_owner_ticket;
    wire        local_mgmt_busy;
    wire [1:0]  read_outstanding;
    wire [1:0]  write_outstanding;
    wire        read_idle;
    wire        write_idle;
    wire        local_quiescent;
    wire        drain_complete;
    wire        local_retire_eligible;
    wire        local_error_valid;
    wire [7:0]  local_error_code;
    wire [1:0]  local_error_source;
    wire [31:0] local_error_generation;
    wire [31:0] local_error_lease_owner_ticket;
    wire [15:0] local_error_tag;
    wire [13:0] local_error_address;
    wire        reset_required;

    reg         mgmt_req_valid;
    wire        mgmt_req_ready;
    reg  [3:0]  mgmt_req_opcode;
    reg  [1:0]  mgmt_req_drain_target;
    reg  [31:0] mgmt_req_generation;
    reg  [31:0] mgmt_req_lease_owner_ticket;
    reg         mgmt_req_external_safe;
    reg  [15:0] mgmt_req_tag;
    wire        mgmt_rsp_valid;
    reg         mgmt_rsp_ready;
    wire [3:0]  mgmt_rsp_opcode;
    wire [2:0]  mgmt_rsp_state;
    wire [31:0] mgmt_rsp_generation;
    wire [31:0] mgmt_rsp_lease_owner_ticket;
    wire [15:0] mgmt_rsp_tag;
    wire [7:0]  mgmt_rsp_status;

    reg         load_req_valid;
    wire        load_req_ready;
    reg  [13:0] load_req_beat_addr;
    reg  [63:0] load_req_data;
    reg  [31:0] load_req_generation;
    reg  [31:0] load_req_lease_owner_ticket;
    reg  [15:0] load_req_tag;
    wire        load_rsp_valid;
    reg         load_rsp_ready;
    wire [13:0] load_rsp_beat_addr;
    wire [31:0] load_rsp_generation;
    wire [31:0] load_rsp_lease_owner_ticket;
    wire [15:0] load_rsp_tag;
    wire [7:0]  load_rsp_status;

    reg          rd_req_valid;
    wire         rd_req_ready;
    reg  [12:0]  rd_req_addr;
    reg  [31:0]  rd_req_generation;
    reg  [31:0]  rd_req_lease_owner_ticket;
    reg  [15:0]  rd_req_tag;
    wire         rd_rsp_valid;
    reg          rd_rsp_ready;
    wire [127:0] rd_rsp_data;
    wire [12:0]  rd_rsp_addr;
    wire [31:0]  rd_rsp_generation;
    wire [31:0]  rd_rsp_lease_owner_ticket;
    wire [15:0]  rd_rsp_tag;
    wire [7:0]   rd_rsp_status;

    reg [127:0] reference_mem [0:8191];
    reg [127:0] expected_rd_data [0:4095];
    reg [12:0]  expected_rd_addr [0:4095];
    reg [31:0]  expected_rd_generation [0:4095];
    reg [31:0]  expected_rd_ticket [0:4095];
    reg [15:0]  expected_rd_tag [0:4095];

    integer failures;
    integer test_count;
    integer timeout_count;
    integer lane;
    integer index;
    integer seed;
    integer random_value;
    integer sampled_fire;
    integer scoreboard_enable;
    integer scoreboard_head;
    integer scoreboard_tail;
    integer scoreboard_accepts;
    integer scoreboard_responses;
    integer admission_count;
    reg [15:0] mgmt_tag_counter;
    reg [127:0] last_read_data;

    parameter_weight_bank dut (
        .clk(clk),
        .rst_n(rst_n),
        .force_error_valid(force_error_valid),
        .force_error_ready(force_error_ready),
        .force_error_code(force_error_code),
        .bank_state(bank_state),
        .bank_generation(bank_generation),
        .bank_generation_initialized(bank_generation_initialized),
        .bank_authority_valid(bank_authority_valid),
        .bank_lease_owner_valid(bank_lease_owner_valid),
        .bank_lease_owner_ticket(bank_lease_owner_ticket),
        .local_mgmt_busy(local_mgmt_busy),
        .read_outstanding(read_outstanding),
        .write_outstanding(write_outstanding),
        .read_idle(read_idle),
        .write_idle(write_idle),
        .local_quiescent(local_quiescent),
        .drain_complete(drain_complete),
        .local_retire_eligible(local_retire_eligible),
        .local_error_valid(local_error_valid),
        .local_error_code(local_error_code),
        .local_error_source(local_error_source),
        .local_error_generation(local_error_generation),
        .local_error_lease_owner_ticket(local_error_lease_owner_ticket),
        .local_error_tag(local_error_tag),
        .local_error_address(local_error_address),
        .reset_required(reset_required),
        .mgmt_req_valid(mgmt_req_valid),
        .mgmt_req_ready(mgmt_req_ready),
        .mgmt_req_opcode(mgmt_req_opcode),
        .mgmt_req_drain_target(mgmt_req_drain_target),
        .mgmt_req_generation(mgmt_req_generation),
        .mgmt_req_lease_owner_ticket(mgmt_req_lease_owner_ticket),
        .mgmt_req_external_safe(mgmt_req_external_safe),
        .mgmt_req_tag(mgmt_req_tag),
        .mgmt_rsp_valid(mgmt_rsp_valid),
        .mgmt_rsp_ready(mgmt_rsp_ready),
        .mgmt_rsp_opcode(mgmt_rsp_opcode),
        .mgmt_rsp_state(mgmt_rsp_state),
        .mgmt_rsp_generation(mgmt_rsp_generation),
        .mgmt_rsp_lease_owner_ticket(mgmt_rsp_lease_owner_ticket),
        .mgmt_rsp_tag(mgmt_rsp_tag),
        .mgmt_rsp_status(mgmt_rsp_status),
        .load_req_valid(load_req_valid),
        .load_req_ready(load_req_ready),
        .load_req_beat_addr(load_req_beat_addr),
        .load_req_data(load_req_data),
        .load_req_generation(load_req_generation),
        .load_req_lease_owner_ticket(load_req_lease_owner_ticket),
        .load_req_tag(load_req_tag),
        .load_rsp_valid(load_rsp_valid),
        .load_rsp_ready(load_rsp_ready),
        .load_rsp_beat_addr(load_rsp_beat_addr),
        .load_rsp_generation(load_rsp_generation),
        .load_rsp_lease_owner_ticket(load_rsp_lease_owner_ticket),
        .load_rsp_tag(load_rsp_tag),
        .load_rsp_status(load_rsp_status),
        .rd_req_valid(rd_req_valid),
        .rd_req_ready(rd_req_ready),
        .rd_req_addr(rd_req_addr),
        .rd_req_generation(rd_req_generation),
        .rd_req_lease_owner_ticket(rd_req_lease_owner_ticket),
        .rd_req_tag(rd_req_tag),
        .rd_rsp_valid(rd_rsp_valid),
        .rd_rsp_ready(rd_rsp_ready),
        .rd_rsp_data(rd_rsp_data),
        .rd_rsp_addr(rd_rsp_addr),
        .rd_rsp_generation(rd_rsp_generation),
        .rd_rsp_lease_owner_ticket(rd_rsp_lease_owner_ticket),
        .rd_rsp_tag(rd_rsp_tag),
        .rd_rsp_status(rd_rsp_status)
    );

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
            test_count = test_count + 1;
            if (condition !== 1'b1)
                fail(message);
        end
    endtask

    function [63:0] low_pattern;
        input [7:0] base;
        integer byte_lane;
        begin
            for (byte_lane = 0; byte_lane < 8; byte_lane = byte_lane + 1)
                low_pattern[byte_lane*8 +: 8] = base + byte_lane;
        end
    endfunction

    function [63:0] high_pattern;
        input [7:0] base;
        integer byte_lane;
        begin
            for (byte_lane = 0; byte_lane < 8; byte_lane = byte_lane + 1)
                high_pattern[byte_lane*8 +: 8] = base + byte_lane + 8;
        end
    endfunction

    task clear_drivers;
        begin
            force_error_valid = 1'b0;
            force_error_code = 8'd0;
            mgmt_req_valid = 1'b0;
            mgmt_req_opcode = 4'd0;
            mgmt_req_drain_target = 2'd0;
            mgmt_req_generation = 32'd0;
            mgmt_req_lease_owner_ticket = 32'd0;
            mgmt_req_external_safe = 1'b0;
            mgmt_req_tag = 16'd0;
            mgmt_rsp_ready = 1'b0;
            load_req_valid = 1'b0;
            load_req_beat_addr = 14'd0;
            load_req_data = 64'd0;
            load_req_generation = 32'd0;
            load_req_lease_owner_ticket = 32'd0;
            load_req_tag = 16'd0;
            load_rsp_ready = 1'b0;
            rd_req_valid = 1'b0;
            rd_req_addr = 13'd0;
            rd_req_generation = 32'd0;
            rd_req_lease_owner_ticket = 32'd0;
            rd_req_tag = 16'd0;
            rd_rsp_ready = 1'b0;
        end
    endtask

    task apply_reset;
        begin
            scoreboard_enable = 0;
            clear_drivers;
            rst_n = 1'b0;
            repeat (3) @(posedge clk);
            #1;
            check(bank_state === ST_INVALID, "reset did not select INVALID");
            check(bank_generation === 32'd0,
                  "reset did not clear bank generation");
            check(bank_generation_initialized === 1'b0,
                  "reset did not clear generation initialized");
            check(bank_authority_valid === 1'b0,
                  "reset did not clear bank authority");
            check(bank_lease_owner_valid === 1'b0,
                  "reset did not clear lease owner valid");
            check(bank_lease_owner_ticket === 32'd0,
                  "reset did not clear lease owner ticket");
            check(read_outstanding === 2'd0 && write_outstanding === 2'd0,
                  "reset did not clear outstanding accounting");
            check(read_idle && write_idle && local_quiescent,
                  "reset did not report idle/quiescent");
            check(!mgmt_rsp_valid && !load_rsp_valid && !rd_rsp_valid,
                  "reset did not clear response valids");
            check(!local_error_valid && !reset_required,
                  "reset did not clear local error state");
            check(!force_error_ready && !mgmt_req_ready &&
                  !load_req_ready && !rd_req_ready,
                  "request ready was asserted during reset");
            @(negedge clk);
            rst_n = 1'b1;
            @(posedge clk);
            #1;
            check(force_error_ready === 1'b1,
                  "force_error was not ready after reset release");
        end
    endtask

    task do_mgmt;
        input [3:0] opcode;
        input [1:0] drain_target;
        input [31:0] generation;
        input [31:0] owner_ticket;
        input external_safe;
        input [7:0] expected_status;
        input [2:0] expected_state;
        input [31:0] expected_generation;
        reg [3:0] held_opcode;
        reg [2:0] held_state;
        reg [31:0] held_generation;
        reg [31:0] held_ticket;
        reg [15:0] held_tag;
        reg [7:0] held_status;
        integer timeout;
        begin
            @(negedge clk);
            mgmt_req_opcode = opcode;
            mgmt_req_drain_target = drain_target;
            mgmt_req_generation = generation;
            mgmt_req_lease_owner_ticket = owner_ticket;
            mgmt_req_external_safe = external_safe;
            mgmt_req_tag = mgmt_tag_counter;
            mgmt_req_valid = 1'b1;
            mgmt_rsp_ready = 1'b0;

            timeout = 0;
            while (!mgmt_req_ready && timeout < 100) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (timeout == 100)
                fail("management request timed out waiting for ready");

            @(posedge clk);
            #1;
            mgmt_req_valid = 1'b0;

            timeout = 0;
            while (!mgmt_rsp_valid && timeout < 100) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            if (timeout == 100) begin
                fail("management response timed out");
            end else begin
                check(mgmt_rsp_opcode === opcode,
                      "management response opcode mismatch");
                check(mgmt_rsp_tag === mgmt_tag_counter,
                      "management response tag mismatch");
                check(mgmt_rsp_status === expected_status,
                      "management response status mismatch");
                check(mgmt_rsp_state === expected_state,
                      "management response state mismatch");
                check(mgmt_rsp_generation === expected_generation,
                      "management response generation mismatch");
                check(bank_state === expected_state,
                      "bank post-state did not match management response");

                held_opcode = mgmt_rsp_opcode;
                held_state = mgmt_rsp_state;
                held_generation = mgmt_rsp_generation;
                held_ticket = mgmt_rsp_lease_owner_ticket;
                held_tag = mgmt_rsp_tag;
                held_status = mgmt_rsp_status;
                repeat (2) begin
                    @(posedge clk);
                    #1;
                    check(mgmt_rsp_valid &&
                          mgmt_rsp_opcode === held_opcode &&
                          mgmt_rsp_state === held_state &&
                          mgmt_rsp_generation === held_generation &&
                          mgmt_rsp_lease_owner_ticket === held_ticket &&
                          mgmt_rsp_tag === held_tag &&
                          mgmt_rsp_status === held_status,
                          "held management response changed under stall");
                end

                mgmt_rsp_ready = 1'b1;
                @(posedge clk);
                #1;
                mgmt_rsp_ready = 1'b0;
                check(!mgmt_rsp_valid,
                      "management response did not retire exactly once");
            end
            mgmt_tag_counter = mgmt_tag_counter + 1'b1;
        end
    endtask

    task load_beat;
        input [13:0] beat_addr;
        input [63:0] data;
        input [31:0] generation;
        input [31:0] owner_ticket;
        input [15:0] tag;
        input [7:0] expected_status;
        reg [13:0] held_addr;
        reg [31:0] held_generation;
        reg [31:0] held_ticket;
        reg [15:0] held_tag;
        reg [7:0] held_status;
        integer timeout;
        begin
            @(negedge clk);
            load_req_beat_addr = beat_addr;
            load_req_data = data;
            load_req_generation = generation;
            load_req_lease_owner_ticket = owner_ticket;
            load_req_tag = tag;
            load_req_valid = 1'b1;
            load_rsp_ready = 1'b0;

            timeout = 0;
            while (!load_req_ready && timeout < 100) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (timeout == 100)
                fail("loader request timed out waiting for ready");

            @(posedge clk);
            #1;
            load_req_valid = 1'b0;

            timeout = 0;
            while (!load_rsp_valid && timeout < 100) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            if (timeout == 100) begin
                fail("loader response timed out");
            end else begin
                check(load_rsp_beat_addr === beat_addr,
                      "loader response address mismatch");
                check(load_rsp_generation === generation,
                      "loader response generation mismatch");
                check(load_rsp_lease_owner_ticket === owner_ticket,
                      "loader response owner mismatch");
                check(load_rsp_tag === tag,
                      "loader response tag mismatch");
                check(load_rsp_status === expected_status,
                      "loader response status mismatch");

                held_addr = load_rsp_beat_addr;
                held_generation = load_rsp_generation;
                held_ticket = load_rsp_lease_owner_ticket;
                held_tag = load_rsp_tag;
                held_status = load_rsp_status;
                repeat (2) begin
                    @(posedge clk);
                    #1;
                    check(load_rsp_valid &&
                          load_rsp_beat_addr === held_addr &&
                          load_rsp_generation === held_generation &&
                          load_rsp_lease_owner_ticket === held_ticket &&
                          load_rsp_tag === held_tag &&
                          load_rsp_status === held_status,
                          "held loader response changed under stall");
                end

                load_rsp_ready = 1'b1;
                @(posedge clk);
                #1;
                load_rsp_ready = 1'b0;
                check(!load_rsp_valid,
                      "loader response did not retire exactly once");
            end

            if (expected_status == STATUS_OK) begin
                if (beat_addr[0] == 1'b0)
                    reference_mem[beat_addr[13:1]][63:0] = data;
                else
                    reference_mem[beat_addr[13:1]][127:64] = data;
            end
        end
    endtask

    task read_word;
        input [12:0] address;
        input [31:0] generation;
        input [31:0] owner_ticket;
        input [15:0] tag;
        input [7:0] expected_status;
        input [127:0] expected_data;
        reg [127:0] held_data;
        reg [12:0] held_addr;
        reg [31:0] held_generation;
        reg [31:0] held_ticket;
        reg [15:0] held_tag;
        reg [7:0] held_status;
        integer timeout;
        begin
            @(negedge clk);
            rd_req_addr = address;
            rd_req_generation = generation;
            rd_req_lease_owner_ticket = owner_ticket;
            rd_req_tag = tag;
            rd_req_valid = 1'b1;
            rd_rsp_ready = 1'b0;

            timeout = 0;
            while (!rd_req_ready && timeout < 100) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (timeout == 100)
                fail("read request timed out waiting for ready");

            check(!rd_rsp_valid,
                  "read response appeared before request acceptance edge");

            @(posedge clk);
            #1;
            rd_req_valid = 1'b0;
            check(rd_rsp_valid,
                  "read response missed fixed one-cycle minimum latency");

            timeout = 0;
            while (!rd_rsp_valid && timeout < 100) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            if (timeout == 100) begin
                fail("read response timed out");
            end else begin
                check(rd_rsp_addr === address,
                      "read response address mismatch");
                check(rd_rsp_generation === generation,
                      "read response generation mismatch");
                check(rd_rsp_lease_owner_ticket === owner_ticket,
                      "read response owner mismatch");
                check(rd_rsp_tag === tag,
                      "read response tag mismatch");
                check(rd_rsp_status === expected_status,
                      "read response status mismatch");
                check(rd_rsp_data === expected_data,
                      "read response data mismatch");
                last_read_data = rd_rsp_data;

                held_data = rd_rsp_data;
                held_addr = rd_rsp_addr;
                held_generation = rd_rsp_generation;
                held_ticket = rd_rsp_lease_owner_ticket;
                held_tag = rd_rsp_tag;
                held_status = rd_rsp_status;
                repeat (2) begin
                    @(posedge clk);
                    #1;
                    check(rd_rsp_valid && rd_rsp_data === held_data &&
                          rd_rsp_addr === held_addr &&
                          rd_rsp_generation === held_generation &&
                          rd_rsp_lease_owner_ticket === held_ticket &&
                          rd_rsp_tag === held_tag &&
                          rd_rsp_status === held_status,
                          "held read response changed under stall");
                end

                rd_rsp_ready = 1'b1;
                @(posedge clk);
                #1;
                rd_rsp_ready = 1'b0;
                check(!rd_rsp_valid,
                      "read response did not retire exactly once");
            end
        end
    endtask

    task claim_bank;
        input [31:0] old_generation;
        input [31:0] owner_ticket;
        input [31:0] new_generation;
        begin
            do_mgmt(OP_CLAIM, TARGET_INVALID, old_generation, owner_ticket,
                    1'b1, STATUS_OK, ST_LOADING, new_generation);
            check(bank_generation_initialized,
                  "successful CLAIM did not initialize generation");
            check(bank_authority_valid && bank_lease_owner_valid,
                  "successful CLAIM did not establish authority");
            check(bank_generation === new_generation &&
                  bank_lease_owner_ticket === owner_ticket,
                  "successful CLAIM captured wrong identity");
        end
    endtask

    task publish_and_activate;
        input [31:0] generation;
        input [31:0] owner_ticket;
        begin
            do_mgmt(OP_PUBLISH_READY, TARGET_INVALID, generation,
                    owner_ticket, 1'b1, STATUS_OK, ST_READY, generation);
            do_mgmt(OP_ACTIVATE, TARGET_INVALID, generation, owner_ticket,
                    1'b1, STATUS_OK, ST_ACTIVE, generation);
            check(local_retire_eligible,
                  "newly ACTIVE idle bank was not locally retire eligible");
        end
    endtask

    task finish_error_and_clear;
        input [31:0] generation;
        input [31:0] owner_ticket;
        reg [7:0] held_error_code;
        reg [1:0] held_error_source;
        reg [15:0] held_error_tag;
        reg [13:0] held_error_address;
        begin
            timeout_count = 0;
            while (!drain_complete && timeout_count < 100) begin
                @(posedge clk);
                #1;
                timeout_count = timeout_count + 1;
            end
            check(drain_complete,
                  "error drain did not reach local completion");
            do_mgmt(OP_FINISH_DRAIN, TARGET_ERROR, generation, owner_ticket,
                    1'b1, STATUS_OK, ST_ERROR, generation);
            check(local_error_valid && !bank_authority_valid &&
                  !bank_lease_owner_valid,
                  "ERROR did not preserve error while clearing authority");

            held_error_code = local_error_code;
            held_error_source = local_error_source;
            held_error_tag = local_error_tag;
            held_error_address = local_error_address;
            do_mgmt(OP_CLEAR_ERROR, TARGET_INVALID, generation,
                    owner_ticket ^ 32'h0000_0001, 1'b1,
                    ERR_OWNER_MISMATCH, ST_ERROR, generation);
            check(local_error_valid &&
                  local_error_code == held_error_code &&
                  local_error_source == held_error_source &&
                  local_error_generation == generation &&
                  local_error_lease_owner_ticket == owner_ticket &&
                  local_error_tag == held_error_tag &&
                  local_error_address == held_error_address,
                  "wrong-owner CLEAR_ERROR changed sticky local detail");

            do_mgmt(OP_CLEAR_ERROR, TARGET_INVALID, generation, owner_ticket,
                    1'b1, STATUS_OK, ST_INVALID, generation);
            check(!local_error_valid && local_error_code == 8'd0 &&
                  local_error_source == 2'd0 &&
                  local_error_generation == 32'd0 &&
                  local_error_lease_owner_ticket == 32'd0 &&
                  local_error_tag == 16'd0 &&
                  local_error_address == 14'd0,
                  "CLEAR_ERROR did not clear complete local record");
            check(!bank_authority_valid && !bank_lease_owner_valid &&
                  bank_lease_owner_ticket == 32'd0,
                  "CLEAR_ERROR unexpectedly restored authority");
        end
    endtask

    task test_missing_lifecycle_and_authority_paths;
        begin
            apply_reset;

            // READY is not compute-readable.  Before exercising that routing
            // fault, prove that a caller cannot manufacture an ERROR-target
            // drain without an already-captured, matching local error.
            claim_bank(32'd0, TICKET_1, 32'd1);
            do_mgmt(OP_PUBLISH_READY, TARGET_INVALID, 32'd1, TICKET_1,
                    1'b1, STATUS_OK, ST_READY, 32'd1);
            do_mgmt(OP_BEGIN_DRAIN, TARGET_ERROR, 32'd1, TICKET_1,
                    1'b1, ERR_LOCAL_PROTOCOL, ST_READY, 32'd1);
            check(!local_error_valid,
                  "unscoped ERROR-target drain poisoned healthy READY bank");
            read_word(13'd64, 32'd1, TICKET_1, 16'h5100,
                      ERR_WRONG_STATE, 128'd0);
            check(bank_state == ST_DRAINING && local_error_valid &&
                  local_error_code == ERR_WRONG_STATE &&
                  local_error_source == ERROR_SOURCE_READ &&
                  local_error_generation == 32'd1 &&
                  local_error_lease_owner_ticket == TICKET_1,
                  "READY read rejection did not capture scoped read error");
            finish_error_and_clear(32'd1, TICKET_1);

            // A pure wrong-owner loader request uses the current generation,
            // returns exactly one error, and must not overwrite either plane.
            claim_bank(32'd1, TICKET_2, 32'd2);
            load_beat(14'd128, 64'h0123_4567_89ab_cdef,
                      32'd2, TICKET_2, 16'h5200, STATUS_OK);
            load_beat(14'd129, 64'hfedc_ba98_7654_3210,
                      32'd2, TICKET_2, 16'h5201, STATUS_OK);
            load_beat(14'd128, 64'hffff_ffff_ffff_ffff,
                      32'd2, TICKET_1, 16'h5202, ERR_OWNER_MISMATCH);
            check(bank_state == ST_DRAINING && local_error_valid &&
                  local_error_code == ERR_OWNER_MISMATCH &&
                  local_error_source == ERROR_SOURCE_LOADER &&
                  local_error_generation == 32'd2 &&
                  local_error_lease_owner_ticket == TICKET_2 &&
                  local_error_tag == 16'h5202 &&
                  local_error_address == 14'd128,
                  "wrong-owner loader did not preserve affected lease scope");
            finish_error_and_clear(32'd2, TICKET_2);

            claim_bank(32'd2, TICKET_3, 32'd3);
            publish_and_activate(32'd3, TICKET_3);
            read_word(13'd64, 32'd3, TICKET_3, 16'h5203, STATUS_OK,
                      128'hfedc_ba98_7654_3210_0123_4567_89ab_cdef);

            // Exercise the normal non-retained teardown path independently of
            // EARLY_RETIRE.
            do_mgmt(OP_BEGIN_DRAIN, TARGET_INVALID, 32'd3, TICKET_3,
                    1'b1, STATUS_OK, ST_DRAINING, 32'd3);
            check(drain_complete,
                  "empty normal INVALID-target drain did not complete");
            do_mgmt(OP_FINISH_DRAIN, TARGET_INVALID, 32'd3, TICKET_3,
                    1'b1, STATUS_OK, ST_INVALID, 32'd3);
            check(!bank_authority_valid && !bank_lease_owner_valid,
                  "normal INVALID-target drain retained authority");

            // Exercise RETAINED eviction, including the required owner-zero
            // management identity and generation preservation.
            claim_bank(32'd3, TICKET_4, 32'd4);
            publish_and_activate(32'd4, TICKET_4);
            do_mgmt(OP_BEGIN_DRAIN, TARGET_RETAINED, 32'd4, TICKET_4,
                    1'b1, STATUS_OK, ST_DRAINING, 32'd4);
            do_mgmt(OP_FINISH_DRAIN, TARGET_RETAINED, 32'd4, TICKET_4,
                    1'b1, STATUS_OK, ST_RETAINED, 32'd4);
            do_mgmt(OP_EVICT_RETAINED, TARGET_INVALID, 32'd4, 32'd0,
                    1'b1, STATUS_OK, ST_INVALID, 32'd4);
            check(bank_generation == 32'd4 && !bank_authority_valid &&
                  !bank_lease_owner_valid &&
                  bank_lease_owner_ticket == 32'd0,
                  "EVICT_RETAINED changed generation or retained authority");

            // Empty final close has no bank transaction to retire.  The direct
            // one-cycle read pipeline has no separate externally observable
            // BRAM-flight state: a request fire fills the N+1 primary response,
            // while same-edge force_error wins the one-fire arbiter.  The held
            // materialized-response case is exercised by lease eight below.
            claim_bank(32'd4, TICKET_5, 32'd5);
            publish_and_activate(32'd5, TICKET_5);
            check(local_quiescent && read_outstanding == 0 &&
                  write_outstanding == 0,
                  "empty final-close setup was not quiescent");
            pulse_force_error(ERR_ABORTED);
            check(bank_state == ST_DRAINING && drain_complete &&
                  local_error_valid && local_error_code == ERR_ABORTED &&
                  local_error_source == ERROR_SOURCE_FORCE &&
                  read_outstanding == 0 && write_outstanding == 0,
                  "empty explicit final close did not complete locally");
            finish_error_and_clear(32'd5, TICKET_5);

            apply_reset;
        end
    endtask

    task test_randomized_loader_write_readback;
        integer write_index;
        integer entry_index;
        reg [63:0] low_value;
        reg [63:0] high_value;
        begin
            apply_reset;
            claim_bank(32'd0, TICKET_6, 32'd1);
            seed = 32'h6d65_6d35;

            // A coprime permutation visits each entry in this 64-entry window
            // exactly once.  Data comes from a fixed random seed, so failures
            // reproduce while both loader planes and nonsequential addresses
            // are checked against the reference memory.
            for (write_index = 0; write_index < 64;
                 write_index = write_index + 1) begin
                entry_index = 256 + ((write_index * 37 + 11) & 63);
                random_value = $random(seed);
                low_value[31:0] = random_value;
                random_value = $random(seed);
                low_value[63:32] = random_value;
                random_value = $random(seed);
                high_value[31:0] = random_value;
                random_value = $random(seed);
                high_value[63:32] = random_value;
                load_beat(entry_index * 2, low_value, 32'd1, TICKET_6,
                          16'h6000 + write_index * 2, STATUS_OK);
                load_beat(entry_index * 2 + 1, high_value,
                          32'd1, TICKET_6,
                          16'h6001 + write_index * 2, STATUS_OK);
            end

            publish_and_activate(32'd1, TICKET_6);
            for (write_index = 0; write_index < 64;
                 write_index = write_index + 1) begin
                entry_index = 256 + ((write_index * 53 + 7) & 63);
                read_word(entry_index, 32'd1, TICKET_6,
                          16'h6800 + write_index, STATUS_OK,
                          reference_mem[entry_index]);
            end

            do_mgmt(OP_BEGIN_DRAIN, TARGET_INVALID, 32'd1, TICKET_6,
                    1'b1, STATUS_OK, ST_DRAINING, 32'd1);
            do_mgmt(OP_FINISH_DRAIN, TARGET_INVALID, 32'd1, TICKET_6,
                    1'b1, STATUS_OK, ST_INVALID, 32'd1);
            apply_reset;
        end
    endtask

    // The approved interface permits response retirement in parallel, but it
    // permits at most one new force/management/loader/read admission per edge.
    always @(posedge clk) begin
        if (rst_n) begin
            admission_count =
                (force_error_valid && force_error_ready) +
                (mgmt_req_valid && mgmt_req_ready) +
                (load_req_valid && load_req_ready) +
                (rd_req_valid && rd_req_ready);
            if (admission_count > 1)
                fail("more than one request admission fired on one edge");
        end
    end

    // Read-only scoreboard used by the long II=1 and randomized tests.  Those
    // phases issue only exact ACTIVE reads, so every response must be ordered
    // success with the reference-memory value sampled at request acceptance.
    always @(posedge clk) begin
        if (!rst_n) begin
            scoreboard_head = 0;
            scoreboard_tail = 0;
            scoreboard_accepts = 0;
            scoreboard_responses = 0;
        end else if (scoreboard_enable != 0) begin
            if (rd_req_valid && rd_req_ready) begin
                if (scoreboard_tail >= 4096) begin
                    fail("read scoreboard overflow");
                end else begin
                    expected_rd_data[scoreboard_tail] =
                        reference_mem[rd_req_addr];
                    expected_rd_addr[scoreboard_tail] = rd_req_addr;
                    expected_rd_generation[scoreboard_tail] =
                        rd_req_generation;
                    expected_rd_ticket[scoreboard_tail] =
                        rd_req_lease_owner_ticket;
                    expected_rd_tag[scoreboard_tail] = rd_req_tag;
                    scoreboard_tail = scoreboard_tail + 1;
                    scoreboard_accepts = scoreboard_accepts + 1;
                end
            end

            if (rd_rsp_valid && rd_rsp_ready) begin
                if (scoreboard_head >= scoreboard_tail) begin
                    fail("read response arrived without queued request");
                end else begin
                    if (rd_rsp_status !== STATUS_OK)
                        fail("scoreboard read returned non-OK status");
                    if (rd_rsp_data !== expected_rd_data[scoreboard_head])
                        fail("scoreboard read data mismatch");
                    if (rd_rsp_addr !== expected_rd_addr[scoreboard_head])
                        fail("scoreboard read address mismatch");
                    if (rd_rsp_generation !==
                        expected_rd_generation[scoreboard_head])
                        fail("scoreboard read generation mismatch");
                    if (rd_rsp_lease_owner_ticket !==
                        expected_rd_ticket[scoreboard_head])
                        fail("scoreboard read owner mismatch");
                    if (rd_rsp_tag !== expected_rd_tag[scoreboard_head])
                        fail("scoreboard read tag/order mismatch");
                    scoreboard_head = scoreboard_head + 1;
                    scoreboard_responses = scoreboard_responses + 1;
                end
            end
        end
    end

    task reset_read_scoreboard;
        begin
            check(read_outstanding == 0 && !rd_rsp_valid,
                  "scoreboard reset attempted with an outstanding read");
            scoreboard_enable = 0;
            scoreboard_head = 0;
            scoreboard_tail = 0;
            scoreboard_accepts = 0;
            scoreboard_responses = 0;
            scoreboard_enable = 1;
        end
    endtask

    task drain_read_scoreboard;
        integer timeout;
        begin
            rd_req_valid = 1'b0;
            rd_rsp_ready = 1'b1;
            timeout = 0;
            while ((scoreboard_head != scoreboard_tail ||
                    read_outstanding != 0) && timeout < 200) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            check(timeout < 200, "read scoreboard failed to drain");
            check(scoreboard_accepts == scoreboard_responses,
                  "read scoreboard accepted/response totals differ");
            @(negedge clk);
            rd_rsp_ready = 1'b0;
            scoreboard_enable = 0;
        end
    endtask

    task test_loader_two_credits;
        reg [13:0] held_addr;
        reg [31:0] held_generation;
        reg [31:0] held_ticket;
        reg [15:0] held_tag;
        reg [7:0] held_status;
        begin
            load_rsp_ready = 1'b0;

            // First request occupies wr_exec.
            @(negedge clk);
            load_req_valid = 1'b1;
            load_req_beat_addr = 14'd2;
            load_req_data = low_pattern(8'h20);
            load_req_generation = 32'd1;
            load_req_lease_owner_ticket = TICKET_1;
            load_req_tag = 16'ha001;
            check(load_req_ready, "first loader credit was unavailable");
            @(posedge clk);
            #1;
            reference_mem[1][63:0] = low_pattern(8'h20);

            // On the next edge request one advances to wr_rsp while request
            // two occupies wr_exec.
            @(negedge clk);
            load_req_beat_addr = 14'd3;
            load_req_data = high_pattern(8'h20);
            load_req_tag = 16'ha002;
            check(load_req_ready,
                  "loader did not sustain one request per cycle");
            @(posedge clk);
            #1;
            reference_mem[1][127:64] = high_pattern(8'h20);

            // A third request must stall behind held wr_rsp + wr_exec.
            @(negedge clk);
            load_req_beat_addr = 14'd4;
            load_req_data = low_pattern(8'h40);
            load_req_tag = 16'ha003;
            check(!load_req_ready,
                  "loader accepted beyond its two physical credits");
            @(posedge clk);
            #1;
            check(write_outstanding == 2,
                  "loader outstanding count did not reach two");
            check(load_rsp_valid && load_rsp_tag == 16'ha001 &&
                  load_rsp_status == STATUS_OK,
                  "first loader response was not held at the output");

            held_addr = load_rsp_beat_addr;
            held_generation = load_rsp_generation;
            held_ticket = load_rsp_lease_owner_ticket;
            held_tag = load_rsp_tag;
            held_status = load_rsp_status;
            repeat (3) begin
                @(posedge clk);
                #1;
                check(load_rsp_valid && !load_req_ready &&
                      load_rsp_beat_addr == held_addr &&
                      load_rsp_generation == held_generation &&
                      load_rsp_lease_owner_ticket == held_ticket &&
                      load_rsp_tag == held_tag &&
                      load_rsp_status == held_status,
                      "two-credit loader changed a held response");
            end

            // Pop response one, advance response two, and admit request three
            // on one edge.
            load_rsp_ready = 1'b1;
            #1;
            check(load_req_ready,
                  "loader did not use same-edge pop/advance/admit credit");
            @(posedge clk);
            #1;
            load_rsp_ready = 1'b0;
            load_req_valid = 1'b0;
            reference_mem[2][63:0] = low_pattern(8'h40);
            check(load_rsp_valid && load_rsp_tag == 16'ha002 &&
                  load_rsp_status == STATUS_OK,
                  "second loader response order mismatch");
            check(write_outstanding == 2,
                  "loader count changed during pop/advance/admit");

            // Pop response two while request three commits and advances.
            load_rsp_ready = 1'b1;
            @(posedge clk);
            #1;
            load_rsp_ready = 1'b0;
            check(load_rsp_valid && load_rsp_tag == 16'ha003 &&
                  load_rsp_status == STATUS_OK,
                  "third loader response order mismatch");
            check(write_outstanding == 1,
                  "loader count did not retain final held response");

            load_rsp_ready = 1'b1;
            @(posedge clk);
            #1;
            load_rsp_ready = 1'b0;
            check(write_outstanding == 0 && write_idle && !load_rsp_valid,
                  "loader credits did not return to empty");

            // Complete entry two before the later trusted publish.  The
            // primitive intentionally has no per-entry completeness bitmap,
            // so its test owner must not leave the high half unwritten.
            load_beat(14'd5, high_pattern(8'h40), 32'd1, TICKET_1,
                      16'ha004, STATUS_OK);
        end
    endtask

    task test_publish_with_held_write_response;
        input [31:0] generation;
        input [31:0] owner_ticket;
        begin
            load_rsp_ready = 1'b0;
            @(negedge clk);
            load_req_valid = 1'b1;
            load_req_beat_addr = 14'd6;
            load_req_data = low_pattern(8'h60);
            load_req_generation = generation;
            load_req_lease_owner_ticket = owner_ticket;
            load_req_tag = 16'ha100;
            check(load_req_ready,
                  "held-write setup loader request was not accepted");
            @(posedge clk);
            #1;
            load_req_valid = 1'b0;
            reference_mem[3][63:0] = low_pattern(8'h60);
            @(posedge clk);
            #1;
            check(load_rsp_valid && write_outstanding == 1,
                  "held-write setup did not materialize response");

            do_mgmt(OP_PUBLISH_READY, TARGET_INVALID, generation,
                    owner_ticket, 1'b1, ERR_NOT_QUIESCENT, ST_LOADING,
                    generation);
            check(load_rsp_valid && load_rsp_tag == 16'ha100 &&
                  load_rsp_status == STATUS_OK,
                  "rejected publish disturbed held loader response");
            load_rsp_ready = 1'b1;
            @(posedge clk);
            #1;
            load_rsp_ready = 1'b0;
            check(write_idle,
                  "held loader response failed to retire after publish reject");
        end
    endtask

    task test_read_ii_one;
        integer request_index;
        integer accepts_before;
        integer responses_before;
        begin
            reset_read_scoreboard;
            accepts_before = scoreboard_accepts;
            responses_before = scoreboard_responses;
            rd_rsp_ready = 1'b1;

            for (request_index = 0; request_index < 1000;
                 request_index = request_index + 1) begin
                @(negedge clk);
                rd_req_valid = 1'b1;
                if (request_index[0] == 1'b0)
                    rd_req_addr = 13'd0;
                else
                    rd_req_addr = 13'd8191;
                rd_req_generation = bank_generation;
                rd_req_lease_owner_ticket = bank_lease_owner_ticket;
                rd_req_tag = request_index[15:0];
                check(rd_req_ready,
                      "no-stall read path failed accepted II=1");
            end

            @(posedge clk);
            #1;
            rd_req_valid = 1'b0;
            drain_read_scoreboard;
            check(scoreboard_accepts - accepts_before == 1000,
                  "II=1 test did not accept exactly 1000 reads");
            check(scoreboard_responses - responses_before == 1000,
                  "II=1 test did not return exactly 1000 reads");
        end
    endtask

    task test_read_backpressure;
        reg [127:0] held_data;
        reg [12:0] held_addr;
        reg [31:0] held_generation;
        reg [31:0] held_ticket;
        reg [15:0] held_tag;
        reg [7:0] held_status;
        begin
            reset_read_scoreboard;
            rd_rsp_ready = 1'b0;

            @(negedge clk);
            rd_req_valid = 1'b1;
            rd_req_addr = 13'd0;
            rd_req_generation = bank_generation;
            rd_req_lease_owner_ticket = bank_lease_owner_ticket;
            rd_req_tag = 16'hb001;
            check(rd_req_ready, "first read credit was unavailable");
            @(posedge clk);
            #1;

            @(negedge clk);
            rd_req_addr = 13'd8191;
            rd_req_tag = 16'hb002;
            check(rd_req_ready,
                  "second read credit was unavailable on sudden stall");
            @(posedge clk);
            #1;

            @(negedge clk);
            rd_req_addr = 13'd1;
            rd_req_tag = 16'hb003;
            check(!rd_req_ready,
                  "read path accepted beyond two local credits");
            check(read_outstanding == 2,
                  "read outstanding count did not reach two");
            held_data = rd_rsp_data;
            held_addr = rd_rsp_addr;
            held_generation = rd_rsp_generation;
            held_ticket = rd_rsp_lease_owner_ticket;
            held_tag = rd_rsp_tag;
            held_status = rd_rsp_status;

            repeat (3) begin
                @(posedge clk);
                #1;
                check(rd_rsp_valid && !rd_req_ready &&
                      rd_rsp_data == held_data &&
                      rd_rsp_addr == held_addr &&
                      rd_rsp_generation == held_generation &&
                      rd_rsp_lease_owner_ticket == held_ticket &&
                      rd_rsp_tag == held_tag &&
                      rd_rsp_status == held_status,
                      "held read response changed under sudden stall");
            end

            // The third request has remained asserted and stable.  One pop
            // grants enough credit for it on the same edge.
            rd_rsp_ready = 1'b1;
            #1;
            check(rd_req_ready,
                  "read path did not reuse same-edge response credit");
            @(posedge clk);
            #1;
            rd_req_valid = 1'b0;
            drain_read_scoreboard;
            check(scoreboard_accepts == 3 && scoreboard_responses == 3,
                  "read backpressure sequence lost or duplicated a request");
        end
    endtask

    task test_random_reads;
        integer cycle_index;
        integer was_fire;
        integer request_serial;
        integer timeout;
        begin
            reset_read_scoreboard;
            seed = 32'h51a7_2026;
            request_serial = 0;
            rd_req_valid = 1'b0;
            rd_rsp_ready = 1'b0;

            for (cycle_index = 0; cycle_index < 500;
                 cycle_index = cycle_index + 1) begin
                @(posedge clk);
                was_fire = rd_req_valid && rd_req_ready;
                #1;
                @(negedge clk);
                random_value = $random(seed);
                rd_rsp_ready = ((random_value & 3) != 0);
                if (!rd_req_valid || was_fire) begin
                    random_value = $random(seed);
                    rd_req_valid = ((random_value & 3) != 0);
                    rd_req_addr = random_value & 13'h00f;
                    rd_req_generation = bank_generation;
                    rd_req_lease_owner_ticket = bank_lease_owner_ticket;
                    rd_req_tag = 16'hc000 + request_serial[15:0];
                    if (rd_req_valid)
                        request_serial = request_serial + 1;
                end
            end

            // Do not withdraw a request that was already asserted under
            // backpressure.  Give it credit, wait for its eventual fire, then
            // stop generation and drain all responses.
            rd_rsp_ready = 1'b1;
            timeout = 0;
            while (rd_req_valid && timeout < 100) begin
                @(posedge clk);
                was_fire = rd_req_valid && rd_req_ready;
                #1;
                if (was_fire)
                    rd_req_valid = 1'b0;
                timeout = timeout + 1;
            end
            check(timeout < 100,
                  "random held request did not receive eventual credit");
            drain_read_scoreboard;
            check(scoreboard_accepts > 100,
                  "randomized phase accepted too few requests");
        end
    endtask

    task pulse_force_error;
        input [7:0] error_code;
        integer timeout;
        begin
            @(negedge clk);
            force_error_code = error_code;
            force_error_valid = 1'b1;
            timeout = 0;
            while (!force_error_ready && timeout < 20) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (timeout == 20)
                fail("force_error did not become ready");
            @(posedge clk);
            #1;
            force_error_valid = 1'b0;
            force_error_code = 8'd0;
        end
    endtask

    task test_loading_arbitration;
        input [31:0] generation;
        input [31:0] owner_ticket;
        integer timeout;
        begin
            // A presented management request blocks both data channels even
            // when loader and read valids are also asserted.
            @(negedge clk);
            mgmt_rsp_ready = 1'b0;
            mgmt_req_valid = 1'b1;
            mgmt_req_opcode = 4'hf;
            mgmt_req_drain_target = TARGET_INVALID;
            mgmt_req_generation = generation;
            mgmt_req_lease_owner_ticket = owner_ticket;
            mgmt_req_external_safe = 1'b1;
            mgmt_req_tag = 16'he001;
            load_req_valid = 1'b1;
            load_req_beat_addr = 14'd30;
            load_req_data = 64'h1111_2222_3333_4444;
            load_req_generation = generation;
            load_req_lease_owner_ticket = owner_ticket;
            load_req_tag = 16'he002;
            rd_req_valid = 1'b1;
            rd_req_addr = 13'd0;
            rd_req_generation = generation;
            rd_req_lease_owner_ticket = owner_ticket;
            rd_req_tag = 16'he003;
            #1;
            check(mgmt_req_ready && !load_req_ready && !rd_req_ready,
                  "management did not win same-edge admission priority");
            @(posedge clk);
            #1;
            mgmt_req_valid = 1'b0;
            load_req_valid = 1'b0;
            rd_req_valid = 1'b0;
            check(mgmt_rsp_valid && mgmt_rsp_status == ERR_BAD_OPCODE,
                  "management arbitration response mismatch");
            check(write_outstanding == 0 && read_outstanding == 0,
                  "losing data channel acquired transaction ownership");
            mgmt_rsp_ready = 1'b1;
            @(posedge clk);
            #1;
            mgmt_rsp_ready = 1'b0;

            // In LOADING, loader wins over a simultaneously valid read.
            @(negedge clk);
            load_rsp_ready = 1'b0;
            load_req_valid = 1'b1;
            load_req_beat_addr = 14'd30;
            load_req_data = low_pattern(8'hf0);
            load_req_generation = generation;
            load_req_lease_owner_ticket = owner_ticket;
            load_req_tag = 16'he010;
            rd_req_valid = 1'b1;
            rd_req_addr = 13'd0;
            rd_req_generation = generation;
            rd_req_lease_owner_ticket = owner_ticket;
            rd_req_tag = 16'he011;
            #1;
            check(load_req_ready && !rd_req_ready,
                  "LOADING did not give loader deterministic priority");
            @(posedge clk);
            #1;
            load_req_valid = 1'b0;
            rd_req_valid = 1'b0;
            reference_mem[15][63:0] = low_pattern(8'hf0);
            timeout = 0;
            while (!load_rsp_valid && timeout < 20) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            check(load_rsp_valid && load_rsp_status == STATUS_OK &&
                  load_rsp_tag == 16'he010,
                  "LOADING winner did not receive its terminal response");
            check(read_outstanding == 0,
                  "LOADING losing read unexpectedly produced a transaction");
            load_rsp_ready = 1'b1;
            @(posedge clk);
            #1;
            load_rsp_ready = 1'b0;
        end
    endtask

    task test_active_arbitration;
        input [31:0] generation;
        input [31:0] owner_ticket;
        integer timeout;
        begin
            @(negedge clk);
            rd_rsp_ready = 1'b0;
            rd_req_valid = 1'b1;
            rd_req_addr = 13'd0;
            rd_req_generation = generation;
            rd_req_lease_owner_ticket = owner_ticket;
            rd_req_tag = 16'he100;
            load_req_valid = 1'b1;
            load_req_beat_addr = 14'd0;
            load_req_data = 64'hffff_eeee_dddd_cccc;
            load_req_generation = generation;
            load_req_lease_owner_ticket = owner_ticket;
            load_req_tag = 16'he101;
            #1;
            check(rd_req_ready && !load_req_ready,
                  "ACTIVE did not give read deterministic priority");
            @(posedge clk);
            #1;
            rd_req_valid = 1'b0;
            load_req_valid = 1'b0;
            timeout = 0;
            while (!rd_rsp_valid && timeout < 20) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            check(rd_rsp_valid && rd_rsp_status == STATUS_OK &&
                  rd_rsp_tag == 16'he100 &&
                  rd_rsp_data == reference_mem[0],
                  "ACTIVE winning read response mismatch");
            check(write_outstanding == 0,
                  "ACTIVE losing loader unexpectedly acquired credit");
            rd_rsp_ready = 1'b1;
            @(posedge clk);
            #1;
            rd_rsp_ready = 1'b0;
        end
    endtask

    task test_local_fault_force_same_edge;
        input [7:0] close_code;
        input [7:0] expected_loader_status;
        input [31:0] owner_ticket;
        integer timeout;
        begin
            apply_reset;
            claim_bank(32'd0, owner_ticket, 32'd1);

            // Leave an authorized write unmaterialized in wr_exec.
            load_rsp_ready = 1'b0;
            @(negedge clk);
            load_req_valid = 1'b1;
            load_req_beat_addr = 14'd8;
            load_req_data = 64'h55aa_0123_4567_89ef;
            load_req_generation = 32'd1;
            load_req_lease_owner_ticket = owner_ticket;
            load_req_tag = 16'hfa10;
            check(load_req_ready,
                  "local-fault priority setup failed to accept loader");
            @(posedge clk);
            #1;
            load_req_valid = 1'b0;

            // White-box corruption creates the approved slot-ownership
            // invariant fault.  force_error is accepted on the same edge.
            @(negedge clk);
            dut.rd_primary_valid_q = 1'b0;
            dut.rd_skid_valid_q = 1'b1;
            force_error_valid = 1'b1;
            force_error_code = close_code;
            #1;
            check(force_error_ready && !mgmt_req_ready &&
                  !load_req_ready && !rd_req_ready,
                  "local integrity fault did not block ordinary admissions");
            @(posedge clk);
            #1;
            force_error_valid = 1'b0;
            force_error_code = 8'd0;

            timeout = 0;
            while (!load_rsp_valid && timeout < 20) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            check(load_rsp_valid &&
                  load_rsp_status == expected_loader_status &&
                  load_rsp_tag == 16'hfa10,
                  "same-edge local-fault/force loader status mismatch");
            check(local_error_valid &&
                  local_error_code == ERR_INTERNAL_STATE &&
                  local_error_generation == 32'd1 &&
                  local_error_lease_owner_ticket == owner_ticket &&
                  reset_required,
                  "same-edge local fault did not own bank-local first error");
            check(bank_state == ST_DRAINING,
                  "same-edge local fault did not enter fail-closed drain");

            load_rsp_ready = 1'b1;
            @(posedge clk);
            #1;
            load_rsp_ready = 1'b0;
            apply_reset;
        end
    endtask


    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        failures = 0;
        test_count = 0;
        timeout_count = 0;
        seed = 1;
        scoreboard_enable = 0;
        scoreboard_head = 0;
        scoreboard_tail = 0;
        scoreboard_accepts = 0;
        scoreboard_responses = 0;
        mgmt_tag_counter = 16'h0100;
        last_read_data = 128'd0;
        clear_drivers;

        for (index = 0; index < 8192; index = index + 1)
            reference_mem[index] = 128'd0;

        apply_reset;

        // Caller-local management errors must not mutate a healthy bank or
        // create a sticky lease error.
        do_mgmt(4'hf, TARGET_INVALID, 32'd0, TICKET_1, 1'b1,
                ERR_BAD_OPCODE, ST_INVALID, 32'd0);
        do_mgmt(OP_ACTIVATE, TARGET_INVALID, 32'd0, TICKET_1, 1'b1,
                ERR_WRONG_STATE, ST_INVALID, 32'd0);
        do_mgmt(OP_CLAIM, TARGET_INVALID, 32'd0, TICKET_1, 1'b0,
                ERR_EXTERNAL_UNSAFE, ST_INVALID, 32'd0);
        check(!local_error_valid,
              "caller-local management error set sticky bank error");

        // Lease one: mapping, both address boundaries, loader credits, legal
        // lifecycle, read latency/order, II=1, and randomized backpressure.
        claim_bank(32'd0, TICKET_1, 32'd1);
        do_mgmt(OP_PUBLISH_READY, TARGET_INVALID, 32'd0, TICKET_1,
                1'b1, ERR_STALE_GENERATION, ST_LOADING, 32'd1);
        do_mgmt(OP_ACTIVATE, TARGET_INVALID, 32'd1, TICKET_1, 1'b1,
                ERR_WRONG_STATE, ST_LOADING, 32'd1);
        test_loading_arbitration(32'd1, TICKET_1);

        load_beat(14'd0, low_pattern(8'h00), 32'd1, TICKET_1,
                  16'h1000, STATUS_OK);
        load_beat(14'd1, high_pattern(8'h00), 32'd1, TICKET_1,
                  16'h1001, STATUS_OK);
        load_beat(14'd16382, low_pattern(8'he0), 32'd1, TICKET_1,
                  16'h1ffe, STATUS_OK);
        load_beat(14'd16383, high_pattern(8'he0), 32'd1, TICKET_1,
                  16'h1fff, STATUS_OK);
        test_publish_with_held_write_response(32'd1, TICKET_1);
        test_loader_two_credits;

        for (index = 3; index < 16; index = index + 1) begin
            load_beat(index * 2, low_pattern(index[7:0] * 8'h10),
                      32'd1, TICKET_1, 16'h2000 + index * 2,
                      STATUS_OK);
            load_beat(index * 2 + 1,
                      high_pattern(index[7:0] * 8'h10),
                      32'd1, TICKET_1, 16'h2001 + index * 2,
                      STATUS_OK);
        end

        do_mgmt(OP_PUBLISH_READY, TARGET_INVALID, 32'd1, TICKET_1,
                1'b0, ERR_EXTERNAL_UNSAFE, ST_LOADING, 32'd1);
        publish_and_activate(32'd1, TICKET_1);
        test_active_arbitration(32'd1, TICKET_1);

        read_word(13'd0, 32'd1, TICKET_1, 16'h3000, STATUS_OK,
                  {high_pattern(8'h00), low_pattern(8'h00)});
        check(last_read_data[7:0] == 8'h00 &&
              last_read_data[15:8] == 8'h01 &&
              last_read_data[71:64] == 8'h08 &&
              last_read_data[127:120] == 8'h0f,
              "INT8 lane order was changed");
        for (lane = 0; lane < 16; lane = lane + 1)
            check(last_read_data[lane*8 +: 8] == lane[7:0],
                  "one or more INT8 lanes were reordered");
        read_word(13'd8191, 32'd1, TICKET_1, 16'h3fff, STATUS_OK,
                  {high_pattern(8'he0), low_pattern(8'he0)});

        test_read_ii_one;
        test_read_backpressure;
        test_random_reads;

        // Illegal target is caller-local and must leave ACTIVE unchanged.
        do_mgmt(OP_BEGIN_DRAIN, 2'b11, 32'd1, TICKET_1, 1'b1,
                ERR_BAD_DRAIN_TARGET, ST_ACTIVE, 32'd1);
        check(!local_error_valid,
              "bad drain target incorrectly poisoned live lease");

        // Enter DRAINING with two accepted reads held, reject new requests,
        // wait for both responses, then retain the physical contents.
        reset_read_scoreboard;
        rd_rsp_ready = 1'b0;
        @(negedge clk);
        rd_req_valid = 1'b1;
        rd_req_addr = 13'd0;
        rd_req_generation = 32'd1;
        rd_req_lease_owner_ticket = TICKET_1;
        rd_req_tag = 16'hd001;
        @(posedge clk);
        #1;
        @(negedge clk);
        rd_req_addr = 13'd8191;
        rd_req_tag = 16'hd002;
        @(posedge clk);
        #1;
        rd_req_valid = 1'b0;
        check(read_outstanding == 2,
              "drain setup did not create two outstanding reads");
        do_mgmt(OP_BEGIN_DRAIN, TARGET_RETAINED, 32'd1, TICKET_1,
                1'b1, STATUS_OK, ST_DRAINING, 32'd1);
        check(!drain_complete && !rd_req_ready && !load_req_ready,
              "DRAINING admitted work or completed before responses retired");
        drain_read_scoreboard;
        check(drain_complete,
              "DRAINING did not complete after all held reads retired");
        do_mgmt(OP_FINISH_DRAIN, TARGET_RETAINED, 32'd1, TICKET_1,
                1'b1, STATUS_OK, ST_RETAINED, 32'd1);
        check(!bank_authority_valid && !bank_lease_owner_valid &&
              bank_lease_owner_ticket == 0,
              "RETAINED kept old stage-ticket authority");
        check(!load_req_ready && !rd_req_ready,
              "RETAINED admitted physical data request");

        // Lease two proves a retained rebind gets a fresh generation and an
        // old-generation loader request cannot touch the new lease.
        claim_bank(32'd1, TICKET_2, 32'd2);
        load_beat(14'd0, 64'hdead_beef_1234_5678, 32'd1, TICKET_2,
                  16'h4000, ERR_STALE_GENERATION);
        check(bank_state == ST_DRAINING && local_error_valid &&
              local_error_code == ERR_STALE_GENERATION,
              "stale loader request did not fail closed");
        check(local_error_generation == 32'd2 &&
              local_error_lease_owner_ticket == TICKET_2 &&
              local_error_tag == 16'h4000 &&
              local_error_address == 14'd0,
              "stale loader corrupted affected-lease error scope");
        finish_error_and_clear(32'd2, TICKET_2);

        // Lease three proves compute is forbidden during LOADING and that an
        // accepted diagnostic request still receives exactly one zero-data
        // response before ERROR teardown.
        claim_bank(32'd2, TICKET_3, 32'd3);
        read_word(13'd0, 32'd3, TICKET_3, 16'h4100,
                  ERR_WRONG_STATE, 128'd0);
        check(bank_state == ST_DRAINING && local_error_valid &&
              local_error_code == ERR_WRONG_STATE &&
              local_error_generation == 32'd3 &&
              local_error_lease_owner_ticket == TICKET_3,
              "LOADING read did not create correctly scoped error drain");
        finish_error_and_clear(32'd3, TICKET_3);

        // Lease four exercises retire protection and direct early retirement.
        claim_bank(32'd3, TICKET_4, 32'd4);
        load_beat(14'd0, low_pattern(8'h44), 32'd4, TICKET_4,
                  16'h4200, STATUS_OK);
        load_beat(14'd1, high_pattern(8'h44), 32'd4, TICKET_4,
                  16'h4201, STATUS_OK);
        publish_and_activate(32'd4, TICKET_4);

        rd_rsp_ready = 1'b0;
        @(negedge clk);
        rd_req_valid = 1'b1;
        rd_req_addr = 13'd0;
        rd_req_generation = 32'd4;
        rd_req_lease_owner_ticket = TICKET_4;
        rd_req_tag = 16'h4202;
        @(posedge clk);
        #1;
        rd_req_valid = 1'b0;
        check(read_outstanding == 1 && rd_rsp_valid,
              "early-retire setup did not hold one read response");
        do_mgmt(OP_EARLY_RETIRE, TARGET_INVALID, 32'd4, TICKET_4,
                1'b1, ERR_NOT_QUIESCENT, ST_ACTIVE, 32'd4);
        check(rd_rsp_valid && rd_rsp_status == STATUS_OK &&
              rd_rsp_data == reference_mem[0],
              "rejected early-retire disturbed held read response");
        rd_rsp_ready = 1'b1;
        @(posedge clk);
        #1;
        rd_rsp_ready = 1'b0;
        check(local_retire_eligible,
              "bank did not become retire eligible after read response");
        do_mgmt(OP_EARLY_RETIRE, TARGET_INVALID, 32'd4, TICKET_4,
                1'b1, STATUS_OK, ST_INVALID, 32'd4);
        check(!bank_authority_valid && !bank_lease_owner_valid &&
              bank_lease_owner_ticket == 0,
              "EARLY_RETIRE failed to revoke old authority");

        // Lease five proves a stale compute generation cannot expose content
        // written under a newer generation.
        claim_bank(32'd4, TICKET_5, 32'd5);
        load_beat(14'd0, low_pattern(8'h55), 32'd5, TICKET_5,
                  16'h4300, STATUS_OK);
        load_beat(14'd1, high_pattern(8'h55), 32'd5, TICKET_5,
                  16'h4301, STATUS_OK);
        publish_and_activate(32'd5, TICKET_5);
        read_word(13'd0, 32'd4, TICKET_5, 16'h4302,
                  ERR_STALE_GENERATION, 128'd0);
        check(local_error_valid &&
              local_error_generation == 32'd5 &&
              local_error_lease_owner_ticket == TICKET_5 &&
              local_error_tag == 16'h4302,
              "stale read selected offender identity as lease scope");
        pulse_force_error(8'hd3);
        check(local_error_code == ERR_STALE_GENERATION &&
              local_error_tag == 16'h4302 &&
              local_error_generation == 32'd5 &&
              local_error_lease_owner_ticket == TICKET_5,
              "later fatal close replaced sticky first local error");
        finish_error_and_clear(32'd5, TICKET_5);

        // Lease six distinguishes wrong owner from stale generation.
        claim_bank(32'd5, TICKET_6, 32'd6);
        publish_and_activate(32'd6, TICKET_6);
        read_word(13'd0, 32'd6, TICKET_5, 16'h4400,
                  ERR_OWNER_MISMATCH, 128'd0);
        check(local_error_valid && local_error_code == ERR_OWNER_MISMATCH &&
              local_error_generation == 32'd6 &&
              local_error_lease_owner_ticket == TICKET_6,
              "wrong-owner read changed affected current-lease scope");
        finish_error_and_clear(32'd6, TICKET_6);

        // Lease seven accepts a wrong-state loader in ACTIVE as a terminal
        // error, suppresses its RAM write, and fails the live lease closed.
        claim_bank(32'd6, TICKET_7, 32'd7);
        publish_and_activate(32'd7, TICKET_7);
        load_beat(14'd0, 64'hffff_ffff_ffff_ffff, 32'd7, TICKET_7,
                  16'h4500, ERR_WRONG_STATE);
        check(local_error_valid && local_error_code == ERR_WRONG_STATE &&
              local_error_generation == 32'd7 &&
              local_error_lease_owner_ticket == TICKET_7,
              "ACTIVE loader did not fail closed with current lease scope");
        finish_error_and_clear(32'd7, TICKET_7);

        // Lease eight: a response materialized before explicit final close
        // must remain immutable success.  Simultaneous ordinary request
        // valids all lose to force_error.
        claim_bank(32'd7, TICKET_8, 32'd8);
        publish_and_activate(32'd8, TICKET_8);
        rd_rsp_ready = 1'b0;
        @(negedge clk);
        rd_req_valid = 1'b1;
        rd_req_addr = 13'd0;
        rd_req_generation = 32'd8;
        rd_req_lease_owner_ticket = TICKET_8;
        rd_req_tag = 16'h4600;
        @(posedge clk);
        #1;
        rd_req_valid = 1'b0;
        check(rd_rsp_valid && rd_rsp_status == STATUS_OK,
              "abort setup read was not materialized as success");

        @(negedge clk);
        force_error_valid = 1'b1;
        force_error_code = ERR_ABORTED;
        mgmt_req_valid = 1'b1;
        mgmt_req_opcode = OP_EARLY_RETIRE;
        mgmt_req_generation = 32'd8;
        mgmt_req_lease_owner_ticket = TICKET_8;
        mgmt_req_external_safe = 1'b1;
        mgmt_req_tag = 16'h4601;
        load_req_valid = 1'b1;
        load_req_beat_addr = 14'd0;
        load_req_data = 64'h0102_0304_0506_0708;
        load_req_generation = 32'd8;
        load_req_lease_owner_ticket = TICKET_8;
        load_req_tag = 16'h4602;
        rd_req_valid = 1'b1;
        rd_req_addr = 13'd1;
        rd_req_generation = 32'd8;
        rd_req_lease_owner_ticket = TICKET_8;
        rd_req_tag = 16'h4603;
        #1;
        check(force_error_ready && !mgmt_req_ready &&
              !load_req_ready && !rd_req_ready,
              "force_error did not exclusively win admission edge");
        @(posedge clk);
        #1;
        force_error_valid = 1'b0;
        force_error_code = 8'd0;
        mgmt_req_valid = 1'b0;
        load_req_valid = 1'b0;
        rd_req_valid = 1'b0;
        check(bank_state == ST_DRAINING && local_error_valid &&
              local_error_code == ERR_ABORTED,
              "explicit final close did not enter abort drain");
        check(!mgmt_rsp_valid && write_outstanding == 0 &&
              read_outstanding == 1,
              "force-error losing channels acquired ownership");
        check(rd_rsp_valid && rd_rsp_status == STATUS_OK &&
              rd_rsp_tag == 16'h4600 &&
              rd_rsp_data == reference_mem[0],
              "abort rewrote a materialized read response");
        rd_rsp_ready = 1'b1;
        @(posedge clk);
        #1;
        rd_rsp_ready = 1'b0;
        finish_error_and_clear(32'd8, TICKET_8);

        // Lease nine: a non-abort fatal close supplies the exact selected
        // first-fatal code to a loader transaction that had been accepted but
        // whose registered write response had not yet materialized.
        claim_bank(32'd8, TICKET_9, 32'd9);
        load_rsp_ready = 1'b0;
        @(negedge clk);
        load_req_valid = 1'b1;
        load_req_beat_addr = 14'd0;
        load_req_data = 64'h1234_5678_9abc_def0;
        load_req_generation = 32'd9;
        load_req_lease_owner_ticket = TICKET_9;
        load_req_tag = 16'h4700;
        check(load_req_ready,
              "fatal pending-write setup could not accept loader request");
        @(posedge clk);
        #1;
        load_req_valid = 1'b0;
        reference_mem[0][63:0] = 64'h1234_5678_9abc_def0;
        @(negedge clk);
        force_error_valid = 1'b1;
        force_error_code = 8'hd2;
        @(posedge clk);
        #1;
        force_error_valid = 1'b0;
        force_error_code = 8'd0;
        timeout_count = 0;
        while (!load_rsp_valid && timeout_count < 20) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(load_rsp_valid && load_rsp_status == 8'hd2 &&
              load_rsp_beat_addr == 14'd0 &&
              load_rsp_generation == 32'd9 &&
              load_rsp_lease_owner_ticket == TICKET_9 &&
              load_rsp_tag == 16'h4700,
              "fatal close did not terminate pending loader exactly once");
        check(bank_state == ST_DRAINING && local_error_valid &&
              local_error_code == 8'hd2 &&
              local_error_generation == 32'd9 &&
              local_error_lease_owner_ticket == TICKET_9,
              "fatal close did not preserve supplied code and lease scope");
        load_rsp_ready = 1'b1;
        @(posedge clk);
        #1;
        load_rsp_ready = 1'b0;
        finish_error_and_clear(32'd9, TICKET_9);

        // Lease ten repeats the unmaterialized loader case for explicit abort
        // and requires ERR_ABORTED rather than the preceding fatal code.
        claim_bank(32'd9, TICKET_A, 32'd10);
        load_rsp_ready = 1'b0;
        @(negedge clk);
        load_req_valid = 1'b1;
        load_req_beat_addr = 14'd1;
        load_req_data = 64'h0fed_cba9_8765_4321;
        load_req_generation = 32'd10;
        load_req_lease_owner_ticket = TICKET_A;
        load_req_tag = 16'h4800;
        check(load_req_ready,
              "abort pending-write setup could not accept loader request");
        @(posedge clk);
        #1;
        load_req_valid = 1'b0;
        reference_mem[0][127:64] = 64'h0fed_cba9_8765_4321;
        @(negedge clk);
        force_error_valid = 1'b1;
        force_error_code = ERR_ABORTED;
        @(posedge clk);
        #1;
        force_error_valid = 1'b0;
        force_error_code = 8'd0;
        timeout_count = 0;
        while (!load_rsp_valid && timeout_count < 20) begin
            @(posedge clk);
            #1;
            timeout_count = timeout_count + 1;
        end
        check(load_rsp_valid && load_rsp_status == ERR_ABORTED &&
              load_rsp_tag == 16'h4800,
              "explicit abort did not mark unmaterialized loader response");
        check(local_error_valid && local_error_code == ERR_ABORTED,
              "explicit abort local record used wrong status");
        load_rsp_ready = 1'b1;
        @(posedge clk);
        #1;
        load_rsp_ready = 1'b0;
        finish_error_and_clear(32'd10, TICKET_A);

        // Reset is the sole operation allowed to discard a bank-accepted
        // response.  It clears all authority/accounting but must not clear the
        // BRAM contents.
        claim_bank(32'd10, TICKET_1, 32'd11);
        publish_and_activate(32'd11, TICKET_1);
        rd_rsp_ready = 1'b0;
        @(negedge clk);
        rd_req_valid = 1'b1;
        rd_req_addr = 13'd0;
        rd_req_generation = 32'd11;
        rd_req_lease_owner_ticket = TICKET_1;
        rd_req_tag = 16'h4900;
        @(posedge clk);
        #1;
        rd_req_valid = 1'b0;
        check(rd_rsp_valid && read_outstanding == 1,
              "reset test did not create held read response");
        rst_n = 1'b0;
        @(posedge clk);
        #1;
        check(bank_state == ST_INVALID && !rd_rsp_valid &&
              read_outstanding == 0 && !bank_authority_valid &&
              !bank_lease_owner_valid && !local_error_valid,
              "reset did not drop held transaction and authority");
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        #1;

        // Reclaim after reset starts from generation one.  Trusted publication
        // lets this storage-only test read the prior bytes and prove that reset
        // did not synthesize a 128 KiB RAM clear.
        claim_bank(32'd0, TICKET_2, 32'd1);
        publish_and_activate(32'd1, TICKET_2);
        read_word(13'd0, 32'd1, TICKET_2, 16'h4901, STATUS_OK,
                  {64'h0fed_cba9_8765_4321,
                   64'h1234_5678_9abc_def0});
        do_mgmt(OP_EARLY_RETIRE, TARGET_INVALID, 32'd1, TICKET_2,
                1'b1, STATUS_OK, ST_INVALID, 32'd1);

        // Close the remaining directed lifecycle, authority, error-clear, and
        // empty-close cases from the approved verification matrix.
        test_missing_lifecycle_and_authority_paths;

        // Exercise randomized production-DUT loader writes followed by
        // nonsequential readback against the testbench reference memory.
        test_randomized_loader_write_readback;

        // Explicit abort loses to a same-edge local integrity fault for both
        // the local record and an unmaterialized response.
        test_local_fault_force_same_edge(ERR_ABORTED,
                                         ERR_INTERNAL_STATE, TICKET_3);

        // A non-abort code is an already-selected global first fatal.  It
        // remains the response status while the independent local record
        // identifies the newly observed internal bank fault.
        test_local_fault_force_same_edge(8'h55, 8'h55, TICKET_4);

        // White-box boundary setup avoids issuing 2^32 leases solely to test
        // the architecturally required no-wrap behavior.
        @(negedge clk);
        dut.bank_generation_q = 32'hffff_ffff;
        dut.bank_generation_initialized_q = 1'b1;
        do_mgmt(OP_CLAIM, TARGET_INVALID, 32'hffff_ffff, TICKET_3,
                1'b1, ERR_GENERATION_EXHAUSTED, ST_INVALID,
                32'hffff_ffff);
        check(reset_required && bank_generation == 32'hffff_ffff &&
              !bank_authority_valid,
              "generation exhaustion wrapped or granted authority");
        do_mgmt(OP_CLEAR_ERROR, TARGET_INVALID, 32'hffff_ffff, 32'd0,
                1'b1, ERR_GENERATION_EXHAUSTED, ST_INVALID,
                32'hffff_ffff);
        check(reset_required,
              "CLEAR_ERROR incorrectly cleared reset_required");

        apply_reset;

        if (failures == 0)
            $display("PASS tb_parameter_weight_bank (%0d checks)",
                     test_count);
        else
            $display("FAIL tb_parameter_weight_bank: %0d failures in %0d checks",
                     failures, test_count);
        $finish;
    end

endmodule
