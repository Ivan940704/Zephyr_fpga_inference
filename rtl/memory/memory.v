`timescale 1ns/1ps

// AXI4 read DMA + true-dual-port BRAM cache for static model parameters.
//
// Contract:
//   * cmd_src_addr and cmd_byte_count must be aligned to DATA_WIDTH/8.
//   * One command is accepted when cmd_valid && cmd_ready.
//   * load_done is a one-cycle pulse.  load_error is valid with load_done.
//   * The DMA is read-only on AXI.  Local BRAM reads/writes use word addresses.
//   * Local writes never create an AXI writeback path.
//   * Do not access the same BRAM word from the DMA and PE ports in one cycle.
//   * Abort drains an already accepted burst but does not issue later bursts.
//   * A read-channel timeout is reported immediately through load_timeout; an
//     accepted burst is still drained before load_done whenever the slave
//     eventually responds.  System reset is required if the slave never does.
//
// The controller emits one AXI read burst at a time, limits burst length, and
// never lets a burst cross a 4 KiB AXI boundary.
module memory #(
    parameter integer AXI_ADDR_WIDTH   = 32,
    parameter integer AXI_DATA_WIDTH   = 64,
    parameter integer AXI_ID_WIDTH     = 1,
    // Production-v1 correctness baseline: 2^15 x 64-bit = 256 KiB.
    parameter integer BRAM_ADDR_WIDTH  = 15,
    parameter integer MAX_BURST_BEATS  = 16,
    parameter integer TIMEOUT_CYCLES   = 100000,
    // Static parameter caches set this to zero so Vivado infers a simple
    // DMA-write/compute-read BRAM without byte-write steering logic.
    parameter integer ENABLE_PE_WRITES = 1
) (
    input  wire                           clk,
    input  wire                           rst_n,
    input  wire                           abort,

    // Command interface from the system FSM.
    input  wire                           cmd_valid,
    output wire                           cmd_ready,
    input  wire [AXI_ADDR_WIDTH-1:0]      cmd_src_addr,
    input  wire [BRAM_ADDR_WIDTH-1:0]     cmd_dst_word_addr,
    input  wire [31:0]                    cmd_byte_count,
    output wire                           load_busy,
    output wire                           load_done,
    output wire                           load_error,
    output wire                           load_timeout,

    // PE-side synchronous BRAM port (one-cycle read latency).
    input  wire                           pe_rd_en,
    input  wire [BRAM_ADDR_WIDTH-1:0]     pe_addr,
    output reg  [AXI_DATA_WIDTH-1:0]      pe_rdata,
    output reg                            pe_rvalid,
    input  wire                           pe_wr_en,
    input  wire [AXI_DATA_WIDTH-1:0]      pe_wdata,
    input  wire [(AXI_DATA_WIDTH/8)-1:0]  pe_wstrb,

    // AXI4 read-address channel.
    output wire [AXI_ADDR_WIDTH-1:0]      m_axi_araddr,
    output wire [AXI_ID_WIDTH-1:0]        m_axi_arid,
    output wire [7:0]                     m_axi_arlen,
    output wire [2:0]                     m_axi_arsize,
    output wire [1:0]                     m_axi_arburst,
    output wire [2:0]                     m_axi_arprot,
    output wire [3:0]                     m_axi_arcache,
    output wire [3:0]                     m_axi_arqos,
    output wire                           m_axi_arlock,
    output wire                           m_axi_arvalid,
    input  wire                           m_axi_arready,

    // AXI4 read-data channel.
    input  wire [AXI_DATA_WIDTH-1:0]      m_axi_rdata,
    input  wire [AXI_ID_WIDTH-1:0]        m_axi_rid,
    input  wire [1:0]                     m_axi_rresp,
    input  wire                           m_axi_rlast,
    input  wire                           m_axi_rvalid,
    output wire                           m_axi_rready
);

    function integer f_clog2;
        input integer value;
        integer temp;
        begin
            temp = value - 1;
            f_clog2 = 0;
            while (temp > 0) begin
                temp = temp >> 1;
                f_clog2 = f_clog2 + 1;
            end
        end
    endfunction

    localparam integer DATA_BYTES       = AXI_DATA_WIDTH / 8;
    localparam integer AXI_SIZE_VALUE   = f_clog2(DATA_BYTES);
    localparam integer BRAM_WORDS       = (1 << BRAM_ADDR_WIDTH);

    localparam [2:0] ST_IDLE = 3'd0;
    localparam [2:0] ST_AR   = 3'd1;
    localparam [2:0] ST_R    = 3'd2;
    localparam [2:0] ST_DONE = 3'd3;

    reg [2:0] state_q;
    reg [AXI_ADDR_WIDTH-1:0] src_addr_q;
    reg [31:0] words_remaining_q;
    reg [BRAM_ADDR_WIDTH-1:0] dma_bram_addr_q;
    reg [31:0] burst_beats_q;
    reg [31:0] beats_seen_q;
    reg error_q;
    reg abort_q;
    reg timeout_q;
    reg [31:0] wait_cycles_q;

    // Register the HP/interconnect R channel before it reaches the inferred
    // BRAM write port.  Some AXI infrastructure uses asynchronously-reset
    // RVALID/metadata registers; driving a RAMB36 enable directly from those
    // signals triggers REQP-1839 and leaves the control transition outside
    // normal timing analysis.  This elastic slot preserves one beat/cycle
    // throughput while making every BRAM data/control input locally clocked.
    reg [AXI_DATA_WIDTH-1:0] rbeat_data_q;
    reg [AXI_ID_WIDTH-1:0] rbeat_id_q;
    reg [1:0] rbeat_resp_q;
    reg rbeat_last_q;
    reg rbeat_valid_q;

    reg [AXI_DATA_WIDTH-1:0] bram [0:BRAM_WORDS-1];

    reg [31:0] planned_burst_beats;
    reg [31:0] words_to_4k_boundary;
    wire expected_last;
    wire axi_r_accept;
    wire rbeat_consume;
    wire dma_write_enable;

    // A legal AXI width is a power-of-two number of bytes.  Static parameter
    // checks are repeated in the testbench/build flow for tools that ignore
    // initial-time assertions during synthesis.
    initial begin
        if ((AXI_DATA_WIDTH % 8) != 0)
            $error("AXI_DATA_WIDTH must be a whole number of bytes");
        if ((DATA_BYTES & (DATA_BYTES - 1)) != 0)
            $error("AXI_DATA_WIDTH/8 must be a power of two");
        if ((MAX_BURST_BEATS < 1) || (MAX_BURST_BEATS > 256))
            $error("MAX_BURST_BEATS must be in the range 1..256");
        if (AXI_ID_WIDTH < 1)
            $error("AXI_ID_WIDTH must be at least one");
        if (BRAM_ADDR_WIDTH < 1)
            $error("BRAM_ADDR_WIDTH must be at least one");
        if (TIMEOUT_CYCLES < 0)
            $error("TIMEOUT_CYCLES must be zero (disabled) or positive");
        if ((ENABLE_PE_WRITES != 0) && (ENABLE_PE_WRITES != 1))
            $error("ENABLE_PE_WRITES must be zero or one");
    end

    // Select the next burst length.  AXI4 permits at most 256 beats and an
    // INCR burst must not cross a 4 KiB address boundary.
    always @* begin
        words_to_4k_boundary =
            (32'd4096 - {20'd0, src_addr_q[11:0]}) >> AXI_SIZE_VALUE;
        planned_burst_beats = words_remaining_q;
        if (planned_burst_beats > MAX_BURST_BEATS)
            planned_burst_beats = MAX_BURST_BEATS;
        if (planned_burst_beats > words_to_4k_boundary)
            planned_burst_beats = words_to_4k_boundary;
    end

    assign cmd_ready     = (state_q == ST_IDLE);
    assign load_busy     = (state_q != ST_IDLE);
    assign load_done     = (state_q == ST_DONE);
    assign load_error    = (state_q == ST_DONE) && error_q;
    assign load_timeout  = timeout_q;

    assign m_axi_araddr  = src_addr_q;
    assign m_axi_arid    = {AXI_ID_WIDTH{1'b0}};
    assign m_axi_arlen   = planned_burst_beats[7:0] - 8'd1;
    assign m_axi_arsize  = AXI_SIZE_VALUE;
    assign m_axi_arburst = 2'b01; // INCR
    // Explicit AXI sidebands for the Zynq HP/interconnect connection.  The
    // first version uses one ID, data access, default QoS and normal
    // non-cacheable/bufferable attributes.
    assign m_axi_arprot  = 3'b000;
    assign m_axi_arcache = 4'b0011;
    assign m_axi_arqos   = 4'b0000;
    assign m_axi_arlock  = 1'b0;
    assign m_axi_arvalid = (state_q == ST_AR);
    assign m_axi_rready  = (state_q == ST_R);

    assign expected_last = (beats_seen_q == (burst_beats_q - 1));
    assign axi_r_accept = m_axi_rvalid && m_axi_rready;
    assign rbeat_consume = (state_q == ST_R) && rbeat_valid_q;
    assign dma_write_enable = rbeat_consume &&
                              !abort && !abort_q && !timeout_q;

    // One-entry elastic ingress slot.  If a buffered beat is consumed while a
    // new external beat handshakes, replace the slot in the same cycle.
    always @(posedge clk) begin
        if (!rst_n) begin
            rbeat_data_q  <= {AXI_DATA_WIDTH{1'b0}};
            rbeat_id_q    <= {AXI_ID_WIDTH{1'b0}};
            rbeat_resp_q  <= 2'b00;
            rbeat_last_q  <= 1'b0;
            rbeat_valid_q <= 1'b0;
        end else if (state_q != ST_R) begin
            rbeat_valid_q <= 1'b0;
        end else if (axi_r_accept) begin
            rbeat_data_q  <= m_axi_rdata;
            rbeat_id_q    <= m_axi_rid;
            rbeat_resp_q  <= m_axi_rresp;
            rbeat_last_q  <= m_axi_rlast;
            rbeat_valid_q <= 1'b1;
        end else if (rbeat_consume) begin
            rbeat_valid_q <= 1'b0;
        end
    end

    // BRAM port A: DMA writes complete AXI words.
    always @(posedge clk) begin
        if (dma_write_enable)
            bram[dma_bram_addr_q] <= rbeat_data_q;
    end

    // BRAM port B: one-cycle compute read.  The optional write-capable branch
    // preserves the standalone loader/debug ABI, while production static
    // parameter service elaborates only the read-only branch.
    generate
        if (ENABLE_PE_WRITES != 0) begin : gen_pe_read_write
            integer byte_lane;
            always @(posedge clk) begin
                if (!rst_n) begin
                    pe_rdata  <= {AXI_DATA_WIDTH{1'b0}};
                    pe_rvalid <= 1'b0;
                end else begin
                    pe_rvalid <= 1'b0;
                    if (pe_wr_en) begin
                        for (byte_lane = 0; byte_lane < DATA_BYTES;
                             byte_lane = byte_lane + 1) begin
                            if (pe_wstrb[byte_lane])
                                bram[pe_addr][byte_lane*8 +: 8] <=
                                    pe_wdata[byte_lane*8 +: 8];
                        end
                    end
                    if (pe_rd_en) begin
                        pe_rdata  <= bram[pe_addr];
                        pe_rvalid <= 1'b1;
                    end
                end
            end
        end else begin : gen_pe_read_only
            always @(posedge clk) begin
                if (!rst_n) begin
                    pe_rdata  <= {AXI_DATA_WIDTH{1'b0}};
                    pe_rvalid <= 1'b0;
                end else begin
                    pe_rvalid <= 1'b0;
                    if (pe_rd_en) begin
                        pe_rdata  <= bram[pe_addr];
                        pe_rvalid <= 1'b1;
                    end
                end
            end
        end
    endgenerate

    // DMA control and AXI protocol checking.
    always @(posedge clk) begin
        if (!rst_n) begin
            state_q           <= ST_IDLE;
            src_addr_q        <= {AXI_ADDR_WIDTH{1'b0}};
            words_remaining_q <= 32'd0;
            dma_bram_addr_q   <= {BRAM_ADDR_WIDTH{1'b0}};
            burst_beats_q     <= 32'd0;
            beats_seen_q      <= 32'd0;
            error_q           <= 1'b0;
            abort_q           <= 1'b0;
            timeout_q         <= 1'b0;
            wait_cycles_q     <= 32'd0;
        end else begin
            case (state_q)
                ST_IDLE: begin
                    error_q       <= 1'b0;
                    abort_q       <= 1'b0;
                    timeout_q     <= 1'b0;
                    wait_cycles_q <= 32'd0;
                    if (cmd_valid && cmd_ready) begin
                        // Alignment and range failures complete immediately
                        // with load_error asserted alongside load_done.
                        if ((cmd_byte_count == 0) ||
                            ((cmd_src_addr & (DATA_BYTES - 1)) != 0) ||
                            ((cmd_byte_count & (DATA_BYTES - 1)) != 0) ||
                            ((cmd_byte_count / DATA_BYTES) >
                             (BRAM_WORDS - cmd_dst_word_addr))) begin
                            error_q <= 1'b1;
                            state_q <= ST_DONE;
                        end else begin
                            src_addr_q        <= cmd_src_addr;
                            words_remaining_q <= cmd_byte_count / DATA_BYTES;
                            dma_bram_addr_q   <= cmd_dst_word_addr;
                            state_q           <= ST_AR;
                        end
                    end
                end

                ST_AR: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        burst_beats_q <= planned_burst_beats;
                        beats_seen_q  <= 32'd0;
                        wait_cycles_q <= 32'd0;
                        if (abort) begin
                            abort_q <= 1'b1;
                            error_q <= 1'b1;
                        end
                        state_q       <= ST_R;
                    end else if (abort) begin
                        abort_q <= 1'b1;
                        error_q <= 1'b1;
                        state_q <= ST_DONE;
                    end else if ((TIMEOUT_CYCLES != 0) &&
                                 (wait_cycles_q >= (TIMEOUT_CYCLES - 1))) begin
                        timeout_q <= 1'b1;
                        error_q   <= 1'b1;
                        state_q   <= ST_DONE;
                    end else begin
                        wait_cycles_q <= wait_cycles_q + 1'b1;
                    end
                end

                ST_R: begin
                    if (abort) begin
                        abort_q <= 1'b1;
                        error_q <= 1'b1;
                    end

                    if (rbeat_consume) begin
                        wait_cycles_q <= 32'd0;
                        dma_bram_addr_q <= dma_bram_addr_q + 1'b1;

                        if (rbeat_resp_q != 2'b00)
                            error_q <= 1'b1;
                        if (rbeat_id_q != {AXI_ID_WIDTH{1'b0}})
                            error_q <= 1'b1;

                        // An early RLAST is unrecoverable for this command.
                        if (rbeat_last_q && !expected_last) begin
                            error_q <= 1'b1;
                            state_q <= ST_DONE;
                        end else if (expected_last) begin
                            // A missing RLAST is also a protocol error, but the
                            // expected beat count lets the controller terminate.
                            if (!rbeat_last_q)
                                error_q <= 1'b1;

                            words_remaining_q <=
                                words_remaining_q - burst_beats_q;
                            src_addr_q <= src_addr_q +
                                (burst_beats_q * DATA_BYTES);

                            if (abort || abort_q || timeout_q)
                                state_q <= ST_DONE;
                            else if (words_remaining_q == burst_beats_q)
                                state_q <= ST_DONE;
                            else
                                state_q <= ST_AR;
                        end else begin
                            beats_seen_q <= beats_seen_q + 1'b1;
                        end
                    end else if (axi_r_accept) begin
                        // The beat is safely captured; do not let the extra
                        // ingress register cycle look like a read timeout.
                        wait_cycles_q <= 32'd0;
                    end else if (!timeout_q && (TIMEOUT_CYCLES != 0) &&
                                 (wait_cycles_q >= (TIMEOUT_CYCLES - 1))) begin
                        // The accepted burst cannot be cancelled.  Stop cache
                        // writes and drain it if/when the slave resumes.
                        timeout_q <= 1'b1;
                        abort_q   <= 1'b1;
                        error_q   <= 1'b1;
                    end else if (!timeout_q) begin
                        wait_cycles_q <= wait_cycles_q + 1'b1;
                    end
                end

                ST_DONE: begin
                    // Pulse load_done/load_error for this cycle, then accept a
                    // new command on the following cycle.
                    state_q <= ST_IDLE;
                end

                default: begin
                    error_q <= 1'b1;
                    state_q <= ST_DONE;
                end
            endcase
        end
    end

endmodule
