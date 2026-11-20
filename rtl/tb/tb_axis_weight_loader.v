`timescale 1ns/1ps

module tb_axis_weight_loader;
    reg aclk = 1'b0;
    reg aresetn;
    reg begin_load;
    reg [3:0] base_addr;

    reg [63:0] s_axis_tdata;
    reg [7:0] s_axis_tkeep;
    reg s_axis_tvalid;
    wire s_axis_tready;
    reg s_axis_tlast;

    wire load_valid;
    reg load_ready;
    wire [3:0] load_addr;
    wire [127:0] load_data;
    wire load_last;
    wire [31:0] word_count;
    wire protocol_error;
    wire busy;

    wire load_we = load_valid && load_ready;
    reg read_en;
    reg [3:0] read_addr;
    wire [127:0] read_data;
    reg swap_banks;
    wire active_bank;

    reg [127:0] expected_words [0:7];
    integer expected_loads;
    integer observed_loads;
    integer errors;
    integer ready_cycle;
    reg check_loads;
    reg ready_pattern_enable;
    reg stalled_previous;
    reg [3:0] stalled_addr;
    reg [127:0] stalled_data;
    reg stalled_last;

    always #5 aclk = ~aclk;

    axis_weight_loader #(
        .AXIS_DATA_WIDTH(64),
        .WORD_WIDTH(128),
        .ADDR_WIDTH(4)
    ) dut (
        .aclk(aclk),
        .aresetn(aresetn),
        .begin_load(begin_load),
        .base_addr(base_addr),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .load_valid(load_valid),
        .load_ready(load_ready),
        .load_addr(load_addr),
        .load_data(load_data),
        .load_last(load_last),
        .word_count(word_count),
        .protocol_error(protocol_error),
        .busy(busy)
    );

    ping_pong_weight_buffer #(
        .WORD_WIDTH(128),
        .DEPTH(16),
        .ADDR_WIDTH(4)
    ) weight_buffer (
        .clk(aclk),
        .rst(!aresetn),
        .load_we(load_we),
        .load_addr(load_addr),
        .load_data(load_data),
        .read_en(read_en),
        .read_addr(read_addr),
        .read_data(read_data),
        .swap_banks(swap_banks),
        .active_bank(active_bank)
    );

    always @(negedge aclk) begin
        if (!aresetn) begin
            load_ready = 1'b0;
            ready_cycle = 0;
        end else if (!ready_pattern_enable) begin
            load_ready = 1'b1;
        end else begin
            ready_cycle = ready_cycle + 1;
            load_ready = ((ready_cycle % 5) != 1) &&
                         ((ready_cycle % 9) != 4);
        end
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            stalled_previous <= 1'b0;
        end else begin
            if (stalled_previous) begin
                if (!load_valid || load_addr !== stalled_addr ||
                    load_data !== stalled_data || load_last !== stalled_last) begin
                    $display("ERROR weight load payload changed under backpressure");
                    errors = errors + 1;
                end
            end
            stalled_previous <= load_valid && !load_ready;
            if (load_valid && !load_ready) begin
                stalled_addr <= load_addr;
                stalled_data <= load_data;
                stalled_last <= load_last;
            end

            if (load_we && check_loads) begin
                if (observed_loads >= expected_loads) begin
                    $display("ERROR unexpected weight word addr=%0d data=%h",
                             load_addr, load_data);
                    errors = errors + 1;
                end else begin
                    if (load_addr !== (4'd3 + observed_loads)) begin
                        $display("ERROR weight addr word=%0d got=%0d expected=%0d",
                                 observed_loads, load_addr, 3 + observed_loads);
                        errors = errors + 1;
                    end
                    if (load_data !== expected_words[observed_loads]) begin
                        $display("ERROR weight data word=%0d got=%h expected=%h",
                                 observed_loads, load_data,
                                 expected_words[observed_loads]);
                        errors = errors + 1;
                    end
                    if (load_last !== (observed_loads == expected_loads - 1)) begin
                        $display("ERROR weight last word=%0d got=%0d expected=%0d",
                                 observed_loads, load_last,
                                 observed_loads == expected_loads - 1);
                        errors = errors + 1;
                    end
                end
                observed_loads = observed_loads + 1;
            end
        end
    end

    task reset_dut;
        begin
            @(negedge aclk);
            aresetn = 1'b0;
            begin_load = 1'b0;
            s_axis_tvalid = 1'b0;
            read_en = 1'b0;
            swap_banks = 1'b0;
            repeat (3) @(posedge aclk);
            @(negedge aclk);
            aresetn = 1'b1;
        end
    endtask

    task start_load;
        input [3:0] address;
        begin
            @(negedge aclk);
            base_addr = address;
            begin_load = 1'b1;
            @(posedge aclk);
            @(negedge aclk);
            begin_load = 1'b0;
        end
    endtask

    task send_beat;
        input [63:0] data;
        input [7:0] keep;
        input last;
        input integer gap;
        integer accepted;
        begin
            repeat (gap) @(posedge aclk);
            @(negedge aclk);
            s_axis_tdata = data;
            s_axis_tkeep = keep;
            s_axis_tlast = last;
            s_axis_tvalid = 1'b1;
            accepted = 0;
            while (!accepted) begin
                @(posedge aclk);
                if (s_axis_tready)
                    accepted = 1;
            end
            @(negedge aclk);
            s_axis_tvalid = 1'b0;
            s_axis_tdata = 0;
            s_axis_tkeep = 0;
            s_axis_tlast = 0;
        end
    endtask

    task check_buffer;
        input [3:0] address;
        input [127:0] expected;
        begin
            @(negedge aclk);
            read_addr = address;
            read_en = 1'b1;
            @(posedge aclk); #1;
            read_en = 1'b0;
            if (read_data !== expected) begin
                $display("ERROR weight buffer addr=%0d got=%h expected=%h",
                         address, read_data, expected);
                errors = errors + 1;
            end
        end
    endtask

    integer index;
    integer timeout;
    initial begin
        aresetn = 0;
        begin_load = 0;
        base_addr = 0;
        s_axis_tdata = 0;
        s_axis_tkeep = 0;
        s_axis_tvalid = 0;
        s_axis_tlast = 0;
        load_ready = 0;
        read_en = 0;
        read_addr = 0;
        swap_banks = 0;
        expected_loads = 5;
        observed_loads = 0;
        errors = 0;
        check_loads = 0;
        ready_pattern_enable = 0;
        stalled_previous = 0;

        for (index = 0; index < expected_loads; index = index + 1)
            expected_words[index] = {
                64'h8000_0000_0000_0000 + index,
                64'h1000_0000_0000_0000 + index
            };

        reset_dut();

        // Reset in the middle of a word; the later transfer must not inherit
        // the abandoned low half.
        start_load(0);
        send_beat(64'h1111_2222_3333_4444, 8'hff, 1'b0, 0);
        if (!busy) begin
            $display("ERROR weight loader not busy after first half-word");
            errors = errors + 1;
        end
        reset_dut();
        if (busy || load_valid || word_count != 0) begin
            $display("ERROR reset did not clear partial weight word");
            errors = errors + 1;
        end

        // Early TLAST is malformed and must not create a BRAM write.
        start_load(0);
        send_beat(64'haaaa_bbbb_cccc_dddd, 8'hff, 1'b1, 0);
        repeat (3) @(posedge aclk);
        if (!protocol_error || load_valid || word_count != 0) begin
            $display("ERROR early TLAST handling error=%0d valid=%0d count=%0d",
                     protocol_error, load_valid, word_count);
            errors = errors + 1;
        end

        // Valid five-word transfer with source gaps and sink backpressure.
        start_load(3);
        ready_pattern_enable = 1;
        check_loads = 1;
        for (index = 0; index < expected_loads; index = index + 1) begin
            send_beat(expected_words[index][63:0], 8'hff, 1'b0,
                      index % 3);
            send_beat(expected_words[index][127:64], 8'hff,
                      index == expected_loads - 1, (index + 1) % 2);
        end

        timeout = 0;
        while ((observed_loads < expected_loads) && timeout < 1000) begin
            @(posedge aclk);
            timeout = timeout + 1;
        end
        // observed_loads is updated by the testbench monitor on the same edge
        // that the DUT increments word_count.  Sample after the DUT's NBA
        // update rather than comparing the previous-cycle counter value.
        @(posedge aclk); #1;
        if (timeout >= 1000) begin
            $display("ERROR weight loader timeout loads=%0d expected=%0d",
                     observed_loads, expected_loads);
            errors = errors + 1;
        end
        if (word_count != expected_loads) begin
            $display("ERROR weight word_count=%0d expected=%0d",
                     word_count, expected_loads);
            errors = errors + 1;
        end
        if (protocol_error) begin
            $display("ERROR valid weight transfer raised protocol_error");
            errors = errors + 1;
        end

        check_loads = 0;
        @(negedge aclk);
        swap_banks = 1'b1;
        @(posedge aclk); #1;
        swap_banks = 1'b0;
        if (active_bank !== 1'b1) begin
            $display("ERROR expected loaded ping-pong bank to become active");
            errors = errors + 1;
        end
        for (index = 0; index < expected_loads; index = index + 1)
            check_buffer(3 + index, expected_words[index]);

        // Partial TKEEP is detected even though the complete 128-bit word is
        // still forwarded for deterministic recovery/reporting.
        start_load(0);
        ready_pattern_enable = 0;
        send_beat(64'h0123_4567_89ab_cdef, 8'hff, 1'b0, 0);
        send_beat(64'hfedc_ba98_7654_3210, 8'h0f, 1'b1, 0);
        timeout = 0;
        while (!protocol_error && timeout < 20) begin
            @(posedge aclk);
            timeout = timeout + 1;
        end
        if (!protocol_error) begin
            $display("ERROR partial weight TKEEP did not set protocol_error");
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("AXIS_WEIGHT_METRIC words=%0d base_addr=3 stalls_tested=1",
                     expected_loads);
            $display("PASS tb_axis_weight_loader");
        end else begin
            $fatal(1, "FAIL tb_axis_weight_loader errors=%0d", errors);
        end
        $finish;
    end
endmodule
