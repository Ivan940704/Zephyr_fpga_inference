`timescale 1ns/1ps
`include "memory/model_memory_v3_map.vh"

// Real-v3, software-visible integration test.  All DUT control/debug traffic
// uses AXI4-Lite; the only other stimulus is the PS-DDR AXI read model.
module tb_parameter_bram_bringup;
    localparam [31:0] PARAMETER_BASE = 32'h1000_0000;
    localparam integer IMAGE_BYTES = 1053056;
    localparam integer LOAD_TIMEOUT_CYCLES = 64;

    localparam [11:0] REG_HW_ID          = 12'h000;
    localparam [11:0] REG_PARAMETER_BASE = 12'h010;
    localparam [11:0] REG_IMAGE_VERSION  = 12'h014;
    localparam [11:0] REG_STAGE_ID       = 12'h018;
    localparam [11:0] REG_COMMAND        = 12'h01c;
    localparam [11:0] REG_STATUS         = 12'h020;
    localparam [11:0] REG_ACTIVE         = 12'h024;
    localparam [11:0] REG_SERVICE_ERROR  = 12'h02c;
    localparam [11:0] REG_WRAPPER_ERROR  = 12'h034;
    localparam [11:0] REG_LOAD_CYCLES    = 12'h03c;
    localparam [11:0] REG_AR_BURSTS      = 12'h040;
    localparam [11:0] REG_R_BEATS        = 12'h044;
    localparam [11:0] REG_LUT_BYTES      = 12'h048;
    localparam [11:0] REG_RAW_STATUS     = 12'h04c;
    localparam [11:0] REG_WEIGHT_REQUEST = 12'h050;
    localparam [11:0] REG_WEIGHT_COMMAND = 12'h054;
    localparam [11:0] REG_WEIGHT_STATUS  = 12'h058;
    localparam [11:0] REG_WEIGHT_DATA0   = 12'h05c;
    localparam [11:0] REG_WEIGHT_DATA1   = 12'h060;
    localparam [11:0] REG_WEIGHT_DATA2   = 12'h064;
    localparam [11:0] REG_WEIGHT_DATA3   = 12'h068;

    localparam [31:0] CMD_START        = 32'h0000_0001;
    localparam [31:0] CMD_RELEASE      = 32'h0000_0002;
    localparam [31:0] CMD_ABORT        = 32'h0000_0004;
    localparam [31:0] CMD_CLEAR_ERROR  = 32'h0000_0008;
    localparam [31:0] CMD_CLEAR_EVENTS = 32'h0000_0010;

    localparam [31:0] STATUS_BUSY          = 32'h0000_0001;
    localparam [31:0] STATUS_READY         = 32'h0000_0002;
    localparam [31:0] STATUS_DONE          = 32'h0000_0004;
    localparam [31:0] STATUS_LOAD_ERROR    = 32'h0000_0008;
    localparam [31:0] STATUS_SERVICE_ERROR = 32'h0000_0080;
    localparam [31:0] STATUS_WRAPPER_ERROR = 32'h0000_0100;
    localparam [31:0] STATUS_RSP_VALID     = 32'h0000_8000;
    localparam [31:0] STATUS_RAW_BUSY      = 32'h0002_0000;
    localparam [31:0] STATUS_ABORT_DRAIN   = 32'h0004_0000;
    localparam [31:0] STATUS_CACHE_MASK    = 32'h0000_0e00;

    reg clk;
    reg rst_n;

    reg [11:0] s_axi_awaddr;
    reg [2:0] s_axi_awprot;
    reg s_axi_awvalid;
    wire s_axi_awready;
    reg [31:0] s_axi_wdata;
    reg [3:0] s_axi_wstrb;
    reg s_axi_wvalid;
    wire s_axi_wready;
    wire [1:0] s_axi_bresp;
    wire s_axi_bvalid;
    reg s_axi_bready;
    reg [11:0] s_axi_araddr;
    reg [2:0] s_axi_arprot;
    reg s_axi_arvalid;
    wire s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0] s_axi_rresp;
    wire s_axi_rvalid;
    reg s_axi_rready;

    wire [31:0] m_axi_araddr;
    wire [0:0] m_axi_arid;
    wire [7:0] m_axi_arlen;
    wire [2:0] m_axi_arsize;
    wire [1:0] m_axi_arburst;
    wire [2:0] m_axi_arprot;
    wire [3:0] m_axi_arcache;
    wire [3:0] m_axi_arqos;
    wire m_axi_arlock;
    wire m_axi_arvalid;
    wire m_axi_arready;
    reg [63:0] m_axi_rdata;
    reg [0:0] m_axi_rid;
    reg [1:0] m_axi_rresp;
    reg m_axi_rlast;
    reg m_axi_rvalid;
    wire m_axi_rready;

    wire [31:0] dbg_status;
    wire [63:0] dbg_error;
    wire [127:0] dbg_counters;
    wire [41:0] dbg_axi_ar;
    wire [68:0] dbg_axi_r;

    reg [7:0] dram [0:IMAGE_BYTES-1];
    reg dram_active;
    reg [31:0] dram_read_addr;
    reg [8:0] dram_beats_left;
    reg ar_pause;
    reg r_pause;
    integer observed_ar_count;
    integer observed_r_count;

    reg [3:0] vector_index;
    wire vector_valid;
    wire [3:0] vector_stage;
    wire vector_matrix;
    wire [9:0] vector_source;
    wire [5:0] vector_row_tile;
    wire [7:0] vector_tag;
    wire [127:0] vector_expected_data;

    integer failures;
    integer image_file;
    integer image_bytes_read;
    integer poll_count;
    integer drain_seen;
    reg [8*256-1:0] image_path;
    reg [31:0] read_value;
    reg [31:0] status_value;
    reg [31:0] word0;
    reg [31:0] word1;
    reg [31:0] word2;
    reg [31:0] word3;

    parameter_bram_bringup_top #(
        .AXI_ID_WIDTH(1),
        .LOAD_TIMEOUT_CYCLES(LOAD_TIMEOUT_CYCLES)
    ) dut (
        .aclk(clk),
        .aresetn(rst_n),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awprot(s_axi_awprot),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arprot(s_axi_arprot),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
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
        .m_axi_rready(m_axi_rready),
        .dbg_status(dbg_status),
        .dbg_error(dbg_error),
        .dbg_counters(dbg_counters),
        .dbg_axi_ar(dbg_axi_ar),
        .dbg_axi_r(dbg_axi_r)
    );

    model_memory_v3_readback_table vectors (
        .index(vector_index),
        .valid(vector_valid),
        .stage_id(vector_stage),
        .matrix_id(vector_matrix),
        .source_index(vector_source),
        .row_tile(vector_row_tile),
        .tag(vector_tag),
        .expected_data(vector_expected_data)
    );

    always #5 clk = ~clk;
    assign m_axi_arready = !dram_active && !ar_pause;

    task fail;
        input [8*192-1:0] message;
        begin
            failures = failures + 1;
            $display("FAIL: %0s at %0t", message, $time);
        end
    endtask

    function [63:0] image_word;
        input [31:0] byte_address;
        integer lane;
        integer image_index;
        begin
            image_word = 64'd0;
            image_index = byte_address - PARAMETER_BASE;
            for (lane = 0; lane < 8; lane = lane + 1) begin
                if ((image_index + lane >= 0) &&
                    (image_index + lane < IMAGE_BYTES))
                    image_word[lane*8 +: 8] = dram[image_index + lane];
                else
                    image_word[lane*8 +: 8] = 8'hxx;
            end
        end
    endfunction

    // One accepted burst at a time, matching the Zynq HP-path contract used by
    // memory.v.  r_pause can hold an accepted burst for timeout/abort tests.
    always @(posedge clk) begin
        if (!rst_n) begin
            dram_active       <= 1'b0;
            dram_read_addr    <= 32'b0;
            dram_beats_left   <= 9'b0;
            m_axi_rdata       <= 64'b0;
            m_axi_rid         <= 1'b0;
            m_axi_rresp       <= 2'b00;
            m_axi_rlast       <= 1'b0;
            m_axi_rvalid      <= 1'b0;
            observed_ar_count <= 0;
            observed_r_count  <= 0;
        end else begin
            if (m_axi_arvalid && m_axi_arready) begin
                dram_active       <= 1'b1;
                dram_read_addr    <= m_axi_araddr;
                dram_beats_left   <= {1'b0, m_axi_arlen} + 1'b1;
                observed_ar_count <= observed_ar_count + 1;
                if ((m_axi_arid != 0) || (m_axi_arsize != 3'd3) ||
                    (m_axi_arburst != 2'b01) || (m_axi_arprot != 3'b000) ||
                    (m_axi_arcache != 4'b0011) || (m_axi_arqos != 0) ||
                    m_axi_arlock)
                    fail("DDR AR sideband contract mismatch");
                if (m_axi_araddr[2:0] != 0)
                    fail("DDR AR address is not 64-bit aligned");
                if ((m_axi_araddr < PARAMETER_BASE) ||
                    (m_axi_araddr >= (PARAMETER_BASE + IMAGE_BYTES)))
                    fail("DDR AR address is outside parameters_v3.bin");
                if ((m_axi_araddr[11:0] +
                     ((m_axi_arlen + 1) << m_axi_arsize)) > 4096)
                    fail("DDR AR burst crossed a 4 KiB boundary");
            end

            if (dram_active && !m_axi_rvalid && !r_pause) begin
                m_axi_rdata  <= image_word(dram_read_addr);
                m_axi_rid    <= 1'b0;
                m_axi_rresp  <= 2'b00;
                m_axi_rlast  <= (dram_beats_left == 1);
                m_axi_rvalid <= 1'b1;
            end

            if (m_axi_rvalid && m_axi_rready) begin
                observed_r_count <= observed_r_count + 1;
                m_axi_rvalid      <= 1'b0;
                if (m_axi_rlast) begin
                    dram_active <= 1'b0;
                end else begin
                    dram_read_addr  <= dram_read_addr + 8;
                    dram_beats_left <= dram_beats_left - 1'b1;
                end
            end
        end
    end

    task drive_aw;
        input [11:0] address;
        input integer delay_cycles;
        integer timeout;
        begin
            repeat (delay_cycles) @(negedge clk);
            s_axi_awaddr  = address;
            s_axi_awvalid = 1'b1;
            timeout = 0;
            while (!s_axi_awready && timeout < 1000) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (timeout == 1000)
                fail("AXI-Lite AW handshake timeout");
            @(posedge clk);
            @(negedge clk);
            s_axi_awvalid = 1'b0;
        end
    endtask

    task drive_w;
        input [31:0] data;
        input [3:0] strobes;
        input integer delay_cycles;
        integer timeout;
        begin
            repeat (delay_cycles) @(negedge clk);
            s_axi_wdata  = data;
            s_axi_wstrb  = strobes;
            s_axi_wvalid = 1'b1;
            timeout = 0;
            while (!s_axi_wready && timeout < 1000) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (timeout == 1000)
                fail("AXI-Lite W handshake timeout");
            @(posedge clk);
            @(negedge clk);
            s_axi_wvalid = 1'b0;
        end
    endtask

    task axi_write;
        input [11:0] address;
        input [31:0] data;
        input [3:0] strobes;
        input integer aw_delay;
        input integer w_delay;
        input integer backpressure_cycles;
        input [1:0] expected_response;
        integer timeout;
        reg [1:0] held_response;
        begin
            s_axi_bready = 1'b0;
            fork
                drive_aw(address, aw_delay);
                drive_w(data, strobes, w_delay);
            join
            timeout = 0;
            while (!s_axi_bvalid && timeout < 1000) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            if (timeout == 1000) begin
                fail("AXI-Lite B response timeout");
            end else begin
                held_response = s_axi_bresp;
                if (held_response !== expected_response)
                    fail("AXI-Lite B response mismatch");
                repeat (backpressure_cycles) begin
                    @(posedge clk);
                    #1;
                    if (!s_axi_bvalid || (s_axi_bresp !== held_response))
                        fail("AXI-Lite B response changed under backpressure");
                end
                @(negedge clk);
                s_axi_bready = 1'b1;
                @(posedge clk);
                @(negedge clk);
                s_axi_bready = 1'b0;
            end
        end
    endtask

    task axi_read;
        input [11:0] address;
        input integer backpressure_cycles;
        input [1:0] expected_response;
        output [31:0] data;
        integer timeout;
        reg [31:0] held_data;
        reg [1:0] held_response;
        begin
            s_axi_rready = 1'b0;
            @(negedge clk);
            s_axi_araddr  = address;
            s_axi_arvalid = 1'b1;
            timeout = 0;
            while (!s_axi_arready && timeout < 1000) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (timeout == 1000)
                fail("AXI-Lite AR handshake timeout");
            @(posedge clk);
            @(negedge clk);
            s_axi_arvalid = 1'b0;

            timeout = 0;
            while (!s_axi_rvalid && timeout < 1000) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            if (timeout == 1000) begin
                fail("AXI-Lite R response timeout");
                data = 32'hxxxx_xxxx;
            end else begin
                held_data = s_axi_rdata;
                held_response = s_axi_rresp;
                if (held_response !== expected_response)
                    fail("AXI-Lite R response mismatch");
                repeat (backpressure_cycles) begin
                    @(posedge clk);
                    #1;
                    if (!s_axi_rvalid || (s_axi_rdata !== held_data) ||
                        (s_axi_rresp !== held_response))
                        fail("AXI-Lite R response changed under backpressure");
                end
                data = held_data;
                @(negedge clk);
                s_axi_rready = 1'b1;
                @(posedge clk);
                @(negedge clk);
                s_axi_rready = 1'b0;
            end
        end
    endtask

    task read_ok;
        input [11:0] address;
        output [31:0] data;
        begin
            axi_read(address, 0, 2'b00, data);
        end
    endtask

    task expect_wrapper_error;
        input [7:0] expected_code;
        begin
            read_ok(REG_WRAPPER_ERROR, read_value);
            if (!read_value[31] || (read_value[7:0] != expected_code))
                fail("wrapper first-fault code mismatch");
        end
    endtask

    task clear_errors;
        begin
            axi_write(REG_COMMAND, CMD_CLEAR_ERROR, 4'b0001,
                      0, 0, 1, 2'b00);
            read_ok(REG_WRAPPER_ERROR, read_value);
            if (read_value != 0)
                fail("CLEAR_ERROR did not clear wrapper error");
            read_ok(REG_SERVICE_ERROR, read_value);
            if (read_value != 0)
                fail("CLEAR_ERROR did not clear service error");
        end
    endtask

    task wait_ready;
        integer timeout;
        begin
            timeout = 0;
            status_value = 0;
            while (((status_value & (STATUS_READY | STATUS_DONE)) !=
                    (STATUS_READY | STATUS_DONE)) && timeout < 100000) begin
                read_ok(REG_STATUS, status_value);
                if (status_value & STATUS_LOAD_ERROR)
                    fail("stage load reported an unexpected error");
                timeout = timeout + 1;
            end
            if (timeout == 100000)
                fail("stage READY poll timed out");
        end
    endtask

    task start_stage;
        input [3:0] stage;
        begin
            axi_write(REG_STAGE_ID, {28'b0, stage}, 4'b1111,
                      0, 0, 0, 2'b00);
            axi_write(REG_COMMAND, CMD_START, 4'b0001,
                      0, 0, 0, 2'b00);
        end
    endtask

    task check_load_counters;
        input [31:0] expected_bursts;
        input [31:0] expected_beats;
        input [31:0] expected_lut_bytes;
        begin
            read_ok(REG_LOAD_CYCLES, read_value);
            if (read_value == 0)
                fail("load cycle counter did not run");
            read_ok(REG_AR_BURSTS, read_value);
            if (read_value != expected_bursts)
                fail("AR burst counter mismatch");
            read_ok(REG_R_BEATS, read_value);
            if (read_value != expected_beats)
                fail("R beat counter mismatch");
            read_ok(REG_LUT_BYTES, read_value);
            if (read_value != expected_lut_bytes)
                fail("LUT accepted-byte counter mismatch");
        end
    endtask

    task check_readback_vector;
        input [3:0] requested_index;
        input test_occupied_slot;
        reg [31:0] request_word;
        reg [127:0] received_data;
        integer timeout;
        begin
            vector_index = requested_index;
            #1;
            if (!vector_valid)
                fail("generated readback table index is invalid");
            read_ok(REG_ACTIVE, read_value);
            if (!read_value[4] || (read_value[3:0] != vector_stage))
                fail("readback vector stage does not match active stage");

            request_word = {
                vector_tag, 2'b00, vector_row_tile,
                vector_source, 5'b00000, vector_matrix
            };
            axi_write(REG_WEIGHT_REQUEST, request_word, 4'b1111,
                      0, 1, 0, 2'b00);
            axi_write(REG_WEIGHT_COMMAND, 32'h1, 4'b0001,
                      1, 0, 0, 2'b00);

            timeout = 0;
            read_value = 0;
            while (!read_value[2] && timeout < 1000) begin
                read_ok(REG_WEIGHT_STATUS, read_value);
                timeout = timeout + 1;
            end
            if (timeout == 1000) begin
                fail("weight response poll timed out");
            end else begin
                if (read_value[3] || (read_value[15:8] != vector_tag))
                    fail("weight response metadata mismatch");

                if (test_occupied_slot) begin
                    axi_write(REG_WEIGHT_COMMAND, 32'h1, 4'b0001,
                              0, 0, 2, 2'b10);
                    expect_wrapper_error(8'h82);
                end

                axi_read(REG_WEIGHT_DATA0, 3, 2'b00, word0);
                axi_read(REG_WEIGHT_DATA1, 1, 2'b00, word1);
                axi_read(REG_WEIGHT_DATA2, 2, 2'b00, word2);
                axi_read(REG_WEIGHT_DATA3, 1, 2'b00, word3);
                received_data = {word3, word2, word1, word0};
                if (received_data !== vector_expected_data)
                    fail("128-bit weight readback mismatched frozen golden");
                read_ok(REG_WEIGHT_STATUS, read_value);
                if (!read_value[2] || (read_value[15:8] != vector_tag))
                    fail("weight response slot was not held across four reads");

                axi_write(REG_WEIGHT_COMMAND, 32'h2, 4'b0001,
                          0, 0, 0, 2'b00);
                read_ok(REG_WEIGHT_STATUS, read_value);
                if (read_value[2])
                    fail("weight response ACK did not retire the slot");
                if (test_occupied_slot)
                    clear_errors();
            end
        end
    endtask

    task release_stage;
        input [3:0] stage;
        integer timeout;
        begin
            axi_write(REG_STAGE_ID, {28'b0, stage}, 4'b1111,
                      0, 0, 0, 2'b00);
            axi_write(REG_COMMAND, CMD_RELEASE, 4'b0001,
                      0, 0, 1, 2'b00);
            timeout = 0;
            status_value = STATUS_CACHE_MASK;
            while (((status_value & STATUS_CACHE_MASK) != 0) &&
                   timeout < 1000) begin
                read_ok(REG_STATUS, status_value);
                timeout = timeout + 1;
            end
            if (timeout == 1000)
                fail("matching RELEASE did not return cache to INVALID");
        end
    endtask

    task clear_events_and_check;
        begin
            axi_write(REG_COMMAND, CMD_CLEAR_EVENTS, 4'b0001,
                      0, 0, 0, 2'b00);
            read_ok(REG_LOAD_CYCLES, read_value);
            if (read_value != 0)
                fail("CLEAR_EVENTS left load cycles nonzero");
            read_ok(REG_AR_BURSTS, read_value);
            if (read_value != 0)
                fail("CLEAR_EVENTS left AR bursts nonzero");
            read_ok(REG_R_BEATS, read_value);
            if (read_value != 0)
                fail("CLEAR_EVENTS left R beats nonzero");
            read_ok(REG_LUT_BYTES, read_value);
            if (read_value != 0)
                fail("CLEAR_EVENTS left LUT bytes nonzero");
        end
    endtask

    initial begin
        // Hard stop prevents a protocol regression from hanging batch XSim.
        #20_000_000;
        $fatal(1, "FAIL tb_parameter_bram_bringup global timeout");
    end

    initial begin
        if (!$value$plusargs("IMAGE=%s", image_path))
            image_path = "../outputs/memory/2026-09-01/v3/parameters_v3.bin";
        image_file = $fopen(image_path, "rb");
        if (image_file == 0)
            $fatal(1, "FAIL cannot open %0s", image_path);
        image_bytes_read = $fread(dram, image_file);
        $fclose(image_file);
        if (image_bytes_read != IMAGE_BYTES)
            $fatal(1, "FAIL image bytes=%0d expected=%0d",
                   image_bytes_read, IMAGE_BYTES);

        clk = 1'b0;
        rst_n = 1'b0;
        s_axi_awaddr = 12'b0;
        s_axi_awprot = 3'b0;
        s_axi_awvalid = 1'b0;
        s_axi_wdata = 32'b0;
        s_axi_wstrb = 4'b0;
        s_axi_wvalid = 1'b0;
        s_axi_bready = 1'b0;
        s_axi_araddr = 12'b0;
        s_axi_arprot = 3'b0;
        s_axi_arvalid = 1'b0;
        s_axi_rready = 1'b0;
        m_axi_rdata = 64'b0;
        m_axi_rid = 1'b0;
        m_axi_rresp = 2'b00;
        m_axi_rlast = 1'b0;
        m_axi_rvalid = 1'b0;
        ar_pause = 1'b0;
        r_pause = 1'b0;
        vector_index = 4'b0;
        failures = 0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        // R backpressure and reset of a partially captured AW transaction.
        axi_read(REG_HW_ID, 4, 2'b00, read_value);
        if (read_value != 32'h5a4d_454d)
            fail("HW_ID mismatch");
        @(negedge clk);
        s_axi_awaddr = REG_PARAMETER_BASE;
        s_axi_awvalid = 1'b1;
        while (!s_axi_awready)
            @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        s_axi_awvalid = 1'b0;
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        if (s_axi_bvalid)
            fail("reset preserved a partial AXI-Lite write");

        // Error policy: command WSTRB is exact; writes to read-only space fail.
        axi_write(REG_COMMAND, CMD_START, 4'b1111,
                  0, 0, 3, 2'b10);
        expect_wrapper_error(8'h80);
        clear_errors();
        axi_write(REG_STATUS, 32'hffff_ffff, 4'b1111,
                  0, 0, 0, 2'b10);
        expect_wrapper_error(8'h83);
        clear_errors();

        // Independent AW/W arrival and B hold while programming the image.
        axi_write(REG_PARAMETER_BASE, PARAMETER_BASE, 4'b1111,
                  0, 4, 4, 2'b00);
        axi_write(REG_IMAGE_VERSION, `MODEL_V3_IMAGE_VERSION, 4'b1111,
                  3, 0, 2, 2'b00);
        read_ok(REG_PARAMETER_BASE, read_value);
        if (read_value != PARAMETER_BASE)
            fail("parameter base readback mismatch");

        // Timeout after an accepted AR: partial data never becomes READY, and
        // CLEAR_ERROR is rejected until the unavoidable burst is drained.
        r_pause = 1'b1;
        start_stage(4'd2);
        poll_count = 0;
        status_value = 0;
        while (!(status_value & STATUS_SERVICE_ERROR) && poll_count < 1000) begin
            read_ok(REG_STATUS, status_value);
            if (status_value & STATUS_READY)
                fail("timed-out partial load became READY");
            poll_count = poll_count + 1;
        end
        if (poll_count == 1000)
            fail("loader timeout was not reported");
        read_ok(REG_SERVICE_ERROR, read_value);
        if (!read_value[31] || (read_value[7:0] != 8'h07))
            fail("timeout service error code mismatch");
        if (!(status_value & STATUS_RAW_BUSY))
            fail("timeout did not expose raw loader busy/drain state");
        axi_write(REG_COMMAND, CMD_CLEAR_ERROR, 4'b0001,
                  0, 0, 0, 2'b10);
        expect_wrapper_error(8'h81);
        r_pause = 1'b0;
        poll_count = 0;
        while ((status_value & STATUS_RAW_BUSY) && poll_count < 1000) begin
            read_ok(REG_STATUS, status_value);
            if (status_value & STATUS_READY)
                fail("stale timeout data became READY during drain");
            poll_count = poll_count + 1;
        end
        if (poll_count == 1000)
            fail("timed-out AXI burst did not drain");
        clear_errors();
        clear_events_and_check();

        // Explicit ABORT also drains an accepted burst and discards the cache.
        r_pause = 1'b1;
        start_stage(4'd2);
        poll_count = 0;
        status_value = 0;
        while (!(status_value & STATUS_RAW_BUSY) && poll_count < 100) begin
            read_ok(REG_STATUS, status_value);
            poll_count = poll_count + 1;
        end
        if (poll_count == 100)
            fail("abort test never observed a live raw load");
        axi_write(REG_COMMAND, CMD_ABORT, 4'b0001,
                  0, 0, 2, 2'b00);
        read_ok(REG_STATUS, status_value);
        if (!(status_value & STATUS_ABORT_DRAIN))
            fail("abort drain status was not exposed");
        r_pause = 1'b0;
        drain_seen = 0;
        poll_count = 0;
        while ((((status_value & STATUS_CACHE_MASK) != 0) ||
                (status_value & STATUS_RAW_BUSY)) && poll_count < 1000) begin
            read_ok(REG_STATUS, status_value);
            if (status_value & STATUS_ABORT_DRAIN)
                drain_seen = 1;
            if (status_value & STATUS_READY)
                fail("aborted partial load became READY");
            poll_count = poll_count + 1;
        end
        if ((poll_count == 1000) || !drain_seen)
            fail("abort did not drain and return to INVALID");
        clear_events_and_check();

        // Successful stage-2 retry.  A second START while busy is rejected but
        // cannot corrupt the in-flight load or its diagnostics.
        start_stage(4'd2);
        read_ok(REG_STATUS, status_value);
        axi_write(REG_COMMAND, CMD_START, 4'b0001,
                  0, 0, 2, 2'b10);
        expect_wrapper_error(8'h81);
        wait_ready();
        clear_errors();
        check_load_counters(32'd165, 32'd2632, 32'd0);
        for (vector_index = 0; vector_index < 5;
             vector_index = vector_index + 1)
            check_readback_vector(vector_index, vector_index == 0);

        // Wrong release is a service first-fault and cannot invalidate READY.
        axi_write(REG_STAGE_ID, 32'd1, 4'b1111,
                  0, 0, 0, 2'b00);
        axi_write(REG_COMMAND, CMD_RELEASE, 4'b0001,
                  0, 0, 0, 2'b00);
        poll_count = 0;
        status_value = 0;
        while (!(status_value & STATUS_SERVICE_ERROR) && poll_count < 100) begin
            read_ok(REG_STATUS, status_value);
            poll_count = poll_count + 1;
        end
        read_ok(REG_SERVICE_ERROR, read_value);
        if (!read_value[31] || (read_value[7:0] != 8'h08) ||
            !(status_value & STATUS_READY))
            fail("wrong RELEASE was not rejected atomically");
        clear_errors();
        release_stage(4'd2);
        clear_events_and_check();

        // Maximum 219,648-byte stage: both matrices and all boundary vectors.
        start_stage(4'd1);
        wait_ready();
        check_load_counters(32'd1717, 32'd27456, 32'd255);
        for (vector_index = 5; vector_index < 13;
             vector_index = vector_index + 1)
            check_readback_vector(vector_index, 1'b0);
        release_stage(4'd1);
        clear_events_and_check();

        // A held response is state, not a new-result indication.  Reset must
        // discard it and all cache ownership before software can retry.
        start_stage(4'd2);
        wait_ready();
        vector_index = 0;
        #1;
        word0 = {
            vector_tag, 2'b00, vector_row_tile,
            vector_source, 5'b00000, vector_matrix
        };
        axi_write(REG_WEIGHT_REQUEST, word0, 4'b1111,
                  0, 0, 0, 2'b00);
        axi_write(REG_WEIGHT_COMMAND, 32'h1, 4'b0001,
                  0, 0, 0, 2'b00);
        poll_count = 0;
        status_value = 0;
        while (!(status_value & STATUS_RSP_VALID) && poll_count < 1000) begin
            read_ok(REG_STATUS, status_value);
            poll_count = poll_count + 1;
        end
        if (poll_count == 1000)
            fail("reset test did not create a held response");
        @(negedge clk);
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);
        read_ok(REG_STATUS, status_value);
        if ((status_value & (STATUS_READY | STATUS_RSP_VALID | STATUS_BUSY |
                             STATUS_SERVICE_ERROR | STATUS_WRAPPER_ERROR)) != 0)
            fail("reset left stale cache/response/error state");
        read_ok(REG_AR_BURSTS, read_value);
        if (read_value != 0)
            fail("reset left stale diagnostics");

        if (failures == 0)
            $display("PASS tb_parameter_bram_bringup vectors=13 stage2_bytes=21056 stage2_beats=2632 stage2_bursts=165 stage1_bytes=219648 stage1_beats=27456 stage1_bursts=1717 stage1_lut_bytes=255");
        else
            $fatal(1, "FAIL tb_parameter_bram_bringup errors=%0d", failures);

        #20;
        $finish;
    end
endmodule
