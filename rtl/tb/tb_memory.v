`timescale 1ns/1ps

module tb_memory;
    localparam integer AXI_ADDR_WIDTH  = 32;
    localparam integer AXI_DATA_WIDTH  = 64;
    localparam integer AXI_ID_WIDTH    = 1;
    localparam integer BRAM_ADDR_WIDTH = 6;
    localparam integer DATA_BYTES      = AXI_DATA_WIDTH / 8;

    reg clk;
    reg rst_n;
    reg abort;

    reg                              cmd_valid;
    wire                             cmd_ready;
    reg  [AXI_ADDR_WIDTH-1:0]        cmd_src_addr;
    reg  [BRAM_ADDR_WIDTH-1:0]       cmd_dst_word_addr;
    reg  [31:0]                      cmd_byte_count;
    wire                             load_busy;
    wire                             load_done;
    wire                             load_error;
    wire                             load_timeout;

    reg                              pe_rd_en;
    reg  [BRAM_ADDR_WIDTH-1:0]       pe_addr;
    wire [AXI_DATA_WIDTH-1:0]        pe_rdata;
    wire                             pe_rvalid;
    reg                              pe_wr_en;
    reg  [AXI_DATA_WIDTH-1:0]        pe_wdata;
    reg  [(AXI_DATA_WIDTH/8)-1:0]    pe_wstrb;

    wire [AXI_ADDR_WIDTH-1:0]        m_axi_araddr;
    wire [AXI_ID_WIDTH-1:0]          m_axi_arid;
    wire [7:0]                       m_axi_arlen;
    wire [2:0]                       m_axi_arsize;
    wire [1:0]                       m_axi_arburst;
    wire [2:0]                       m_axi_arprot;
    wire [3:0]                       m_axi_arcache;
    wire [3:0]                       m_axi_arqos;
    wire                             m_axi_arlock;
    wire                             m_axi_arvalid;
    wire                             m_axi_arready;
    reg  [AXI_DATA_WIDTH-1:0]        m_axi_rdata;
    reg  [AXI_ID_WIDTH-1:0]          m_axi_rid;
    reg  [1:0]                       m_axi_rresp;
    reg                              m_axi_rlast;
    reg                              m_axi_rvalid;
    wire                             m_axi_rready;

    reg                              dram_active;
    reg  [AXI_ADDR_WIDTH-1:0]        dram_read_addr;
    reg  [8:0]                       dram_beats_left;
    reg                              inject_error_once;
    reg                              inject_bad_id_once;
    reg                              stall_read_data;
    integer                          ar_count;
    integer                          failures;
    integer                          boundary_bytes;

    memory #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .BRAM_ADDR_WIDTH(BRAM_ADDR_WIDTH),
        .MAX_BURST_BEATS(4),
        .TIMEOUT_CYCLES(64)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .abort(abort),
        .cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready),
        .cmd_src_addr(cmd_src_addr),
        .cmd_dst_word_addr(cmd_dst_word_addr),
        .cmd_byte_count(cmd_byte_count),
        .load_busy(load_busy),
        .load_done(load_done),
        .load_error(load_error),
        .load_timeout(load_timeout),
        .pe_rd_en(pe_rd_en),
        .pe_addr(pe_addr),
        .pe_rdata(pe_rdata),
        .pe_rvalid(pe_rvalid),
        .pe_wr_en(pe_wr_en),
        .pe_wdata(pe_wdata),
        .pe_wstrb(pe_wstrb),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arid(m_axi_arid),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arprot(m_axi_arprot),
        .m_axi_arcache(m_axi_arcache),
        .m_axi_arqos(m_axi_arqos),
        .m_axi_arlock(m_axi_arlock),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rid(m_axi_rid),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready)
    );

    always #5 clk = ~clk;

    assign m_axi_arready = !dram_active;

    function [AXI_DATA_WIDTH-1:0] pattern_word;
        input [AXI_ADDR_WIDTH-1:0] byte_addr;
        integer lane;
        begin
            for (lane = 0; lane < DATA_BYTES; lane = lane + 1)
                pattern_word[lane*8 +: 8] = byte_addr[7:0] + lane;
        end
    endfunction

    task fail;
        input [8*120-1:0] message;
        begin
            failures = failures + 1;
            $display("FAIL: %0s at time %0t", message, $time);
        end
    endtask

    // Minimal AXI memory model.  It creates deterministic bytes from each
    // aligned read address and supports one outstanding burst.
    always @(posedge clk) begin
        if (!rst_n) begin
            dram_active     <= 1'b0;
            dram_read_addr  <= 0;
            dram_beats_left <= 0;
            m_axi_rdata     <= 0;
            m_axi_rid       <= 0;
            m_axi_rresp     <= 2'b00;
            m_axi_rlast     <= 1'b0;
            m_axi_rvalid    <= 1'b0;
            inject_error_once <= 1'b0;
            inject_bad_id_once <= 1'b0;
            stall_read_data   <= 1'b0;
            ar_count        <= 0;
        end else begin
            if (m_axi_arvalid && m_axi_arready) begin
                dram_active     <= 1'b1;
                dram_read_addr  <= m_axi_araddr;
                dram_beats_left <= {1'b0, m_axi_arlen} + 1'b1;
                ar_count        <= ar_count + 1;

                boundary_bytes = m_axi_araddr[11:0] +
                                 ((m_axi_arlen + 1) << m_axi_arsize);
                if (m_axi_arburst != 2'b01)
                    fail("AR channel did not request an INCR burst");
                if ((m_axi_arid != 0) || (m_axi_arprot != 3'b000) ||
                    (m_axi_arcache != 4'b0011) || (m_axi_arqos != 0) ||
                    m_axi_arlock)
                    fail("AXI sideband baseline changed unexpectedly");
                if (boundary_bytes > 4096)
                    fail("AXI burst crossed a 4 KiB boundary");
            end

            if (dram_active && !m_axi_rvalid && !stall_read_data) begin
                m_axi_rdata  <= pattern_word(dram_read_addr);
                m_axi_rid    <= inject_bad_id_once ? 1'b1 : 1'b0;
                m_axi_rresp  <= inject_error_once ? 2'b10 : 2'b00;
                m_axi_rlast  <= (dram_beats_left == 1);
                m_axi_rvalid <= 1'b1;
                if (inject_error_once)
                    inject_error_once <= 1'b0;
                if (inject_bad_id_once)
                    inject_bad_id_once <= 1'b0;
            end

            if (m_axi_rvalid && m_axi_rready) begin
                m_axi_rvalid <= 1'b0;
                if (m_axi_rlast) begin
                    dram_active <= 1'b0;
                end else begin
                    dram_read_addr  <= dram_read_addr + DATA_BYTES;
                    dram_beats_left <= dram_beats_left - 1'b1;
                end
            end
        end
    end

    task run_command;
        input [AXI_ADDR_WIDTH-1:0] src_addr;
        input [BRAM_ADDR_WIDTH-1:0] dst_word;
        input [31:0] byte_count;
        input expected_error;
        integer timeout;
        begin
            @(negedge clk);
            cmd_src_addr      = src_addr;
            cmd_dst_word_addr = dst_word;
            cmd_byte_count    = byte_count;
            cmd_valid         = 1'b1;

            while (!cmd_ready)
                @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            cmd_valid = 1'b0;

            timeout = 0;
            while (!load_done && timeout < 500) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            if (timeout == 500)
                fail("DMA command timed out");
            else if (load_error !== expected_error)
                fail("DMA command returned unexpected error status");
            if (load_timeout)
                fail("DMA command unexpectedly timed out");
            @(negedge clk);
        end
    endtask

    task check_pe_word;
        input [BRAM_ADDR_WIDTH-1:0] address;
        input [AXI_DATA_WIDTH-1:0] expected;
        begin
            @(negedge clk);
            pe_addr  = address;
            pe_rd_en = 1'b1;
            @(posedge clk);
            #1;
            if (!pe_rvalid)
                fail("PE BRAM read did not assert valid");
            if (pe_rdata !== expected) begin
                $display("  address=%0d expected=%h actual=%h", address, expected, pe_rdata);
                fail("PE BRAM read data mismatch");
            end
            @(negedge clk);
            pe_rd_en = 1'b0;
        end
    endtask

    task pe_write_word;
        input [BRAM_ADDR_WIDTH-1:0] address;
        input [AXI_DATA_WIDTH-1:0] data;
        input [(AXI_DATA_WIDTH/8)-1:0] strobe;
        begin
            @(negedge clk);
            pe_addr  = address;
            pe_wdata = data;
            pe_wstrb = strobe;
            pe_wr_en = 1'b1;
            @(posedge clk);
            @(negedge clk);
            pe_wr_en = 1'b0;
        end
    endtask

    integer i;
    integer ar_before;
    reg [63:0] partial_expected;
    initial begin
        $dumpfile("build/tb_memory.vcd");
        $dumpvars(0, tb_memory);

        clk               = 1'b0;
        rst_n             = 1'b0;
        abort             = 1'b0;
        cmd_valid         = 1'b0;
        cmd_src_addr      = 0;
        cmd_dst_word_addr = 0;
        cmd_byte_count    = 0;
        pe_rd_en          = 1'b0;
        pe_addr           = 0;
        pe_wr_en          = 1'b0;
        pe_wdata          = 0;
        pe_wstrb          = 0;
        inject_error_once = 1'b0;
        inject_bad_id_once = 1'b0;
        stall_read_data    = 1'b0;
        failures          = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // Test 1: ten words require bursts of 4 + 4 + 2 beats.
        ar_before = ar_count;
        run_command(32'h0000_0018, 6'd5, 32'd80, 1'b0);
        if ((ar_count - ar_before) != 3)
            fail("MAX_BURST_BEATS split was incorrect");
        for (i = 0; i < 10; i = i + 1)
            check_pe_word(5 + i, pattern_word(32'h18 + i*DATA_BYTES));

        // Test 2: source begins 16 bytes before a 4 KiB boundary.  The first
        // burst must be 2 beats and the second burst 4 beats.
        ar_before = ar_count;
        run_command(32'h0000_0ff0, 6'd20, 32'd48, 1'b0);
        if ((ar_count - ar_before) != 2)
            fail("4 KiB boundary split was incorrect");
        for (i = 0; i < 6; i = i + 1)
            check_pe_word(20 + i, pattern_word(32'hff0 + i*DATA_BYTES));

        // Test 3: PE byte-enable writes preserve lanes whose strobe is zero.
        pe_write_word(6'd40, 64'h1122_3344_5566_7788, 8'hff);
        pe_write_word(6'd40, 64'haabb_ccdd_eeff_0011, 8'b0000_1001);
        partial_expected = 64'h1122_3344_ee66_7711;
        check_pe_word(6'd40, partial_expected);

        // Test 4: invalid commands fail before issuing AXI traffic.
        ar_before = ar_count;
        run_command(32'h0000_0003, 6'd0, 32'd8, 1'b1);
        run_command(32'h0000_0000, 6'd60, 32'd40, 1'b1);
        run_command(32'h0000_0000, 6'd0, 32'd0, 1'b1);
        if (ar_count != ar_before)
            fail("invalid command issued an AXI read");

        // Test 5: AXI SLVERR propagates to load_error.
        inject_error_once = 1'b1;
        run_command(32'h0000_0080, 6'd0, 32'd8, 1'b1);
        check_pe_word(6'd0, pattern_word(32'h80));

        // Test 6: a response ID mismatch is a command error.
        inject_bad_id_once = 1'b1;
        run_command(32'h0000_0090, 6'd1, 32'd8, 1'b1);

        // Test 7: once AR is accepted, a timeout suppresses cache writes but
        // keeps RREADY asserted until the outstanding burst is drained.
        pe_write_word(6'd50, 64'hcafe_f00d_1234_5678, 8'hff);
        stall_read_data = 1'b1;
        @(negedge clk);
        cmd_src_addr = 32'h0000_0100;
        cmd_dst_word_addr = 6'd50;
        cmd_byte_count = 32'd8;
        cmd_valid = 1'b1;
        while (!cmd_ready)
            @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        cmd_valid = 1'b0;
        while (!load_timeout)
            @(posedge clk);
        #1;
        if (!load_busy || load_done || !m_axi_rready)
            fail("accepted timeout did not remain in burst-drain mode");
        stall_read_data = 1'b0;
        while (!load_done)
            @(negedge clk);
        #1;
        if (!load_error || !load_timeout)
            fail("drained timeout did not complete with typed error status");
        @(negedge clk);
        check_pe_word(6'd50, 64'hcafe_f00d_1234_5678);

        if (failures == 0)
            $display("PASS tb_memory");
        else
            $fatal(1, "FAIL tb_memory errors=%0d", failures);

        #20;
        $finish;
    end

endmodule
