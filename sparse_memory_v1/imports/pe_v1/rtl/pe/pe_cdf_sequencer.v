`timescale 1ns/1ps

// PE-side scheduler for one Complex Deep Filtering group of up to eight bins.
//
// Arithmetic is performed only by the existing sixteen pe_hybrid_mac lanes:
// two PEs hold the real and imaginary accumulators for each complex bin.  One
// tap is issued in two MODE_DENSE phases:
//
//   phase A: real += Xr * Cr;       imag += Xr * Ci
//   phase B: real += Xi * (-Ci);    imag += Xi * Cr
//
// The formal operand domain is signed INT8 -127..127.  Consequently -Ci is
// exactly representable as signed INT8.  Results are the Hybrid PE signed
// INT32 accumulators without requantization, rounding, or saturation.
//
// Coefficient reshape/storage and spectrum temporal-history storage are
// external.  This module holds only the current eight-bin tap packet and
// group metadata.  The provider supplies causal zero-padding values.
module pe_cdf_sequencer #(
    parameter integer BIN_INDEX_WIDTH = 8,
    parameter integer TAG_WIDTH       = 16
) (
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         start_valid,
    output wire                         start_ready,
    input  wire [2:0]                   order_in,
    input  wire [7:0]                   bin_valid_in,
    input  wire [BIN_INDEX_WIDTH-1:0]   bin_base_in,
    input  wire [1:0]                   band_in,
    input  wire [TAG_WIDTH-1:0]         tag_in,

    // The arbiter grants exclusive use of all sixteen Hybrid MAC PEs and
    // holds owner_grant while owner_request remains asserted.
    output wire                         owner_request,
    input  wire                         owner_grant,

    // One packet supplies one temporal tap for up to eight frequency bins.
    // tap_index_in is oldest-to-newest: zero is frame t-order+1 and the last
    // tap is the current frame.  Any causal padding is supplied as Xr=Xi=0.
    input  wire                         tap_valid,
    output wire                         tap_ready,
    input  wire [2:0]                   tap_index_in,
    input  wire [8*8-1:0]               spectrum_real_in,
    input  wire [8*8-1:0]               spectrum_imag_in,
    input  wire [8*8-1:0]               coefficient_real_in,
    input  wire [8*8-1:0]               coefficient_imag_in,

    // Controls and operands for the existing sixteen Hybrid MAC PEs.
    output reg  [15:0]                  pe_acc_clear,
    output reg  [15:0]                  pe_acc_enable,
    output reg  [1:0]                   pe_mode,
    output reg  [16*8-1:0]              pe_operand_a,
    output reg  [16*8-1:0]              pe_operand_b,
    input  wire [16*32-1:0]             pe_accumulator,
    input  wire [15:0]                  pe_overflow,

    output wire                         result_valid,
    input  wire                         result_ready,
    output reg  [8*32-1:0]              result_real,
    output reg  [8*32-1:0]              result_imag,
    output wire [7:0]                   result_bin_valid,
    output wire [2:0]                   result_order,
    output wire [BIN_INDEX_WIDTH-1:0]   result_bin_base,
    output wire [1:0]                   result_band,
    output wire [TAG_WIDTH-1:0]         result_tag,

    output wire                         busy,
    output reg                          done,
    output wire                         protocol_error,
    output wire [2:0]                   phase,
    output wire [2:0]                   active_tap_index
);

    localparam [1:0] MODE_DENSE = 2'd0;

    localparam [2:0] S_IDLE    = 3'd0;
    localparam [2:0] S_WAIT_A  = 3'd1;
    localparam [2:0] S_ISSUE_B = 3'd2;
    localparam [2:0] S_DRAIN   = 3'd3;
    localparam [2:0] S_RESULT  = 3'd4;

    reg [2:0] state;

    reg [2:0]                 order_r;
    reg [7:0]                 bin_valid_r;
    reg [BIN_INDEX_WIDTH-1:0] bin_base_r;
    reg [1:0]                 band_r;
    reg [TAG_WIDTH-1:0]       tag_r;
    reg [2:0]                 tap_index_r;

    reg [8*8-1:0] spectrum_imag_r;
    reg [8*8-1:0] coefficient_real_r;
    reg [8*8-1:0] coefficient_imag_r;

    reg control_error_r;

    wire start_fire;
    wire tap_fire;
    wire result_fire;

    function legal_order;
        input [2:0] value;
        begin
            legal_order = (value == 3'd1)
                || (value == 3'd3)
                || (value == 3'd5);
        end
    endfunction

    // A waiting requester raises owner_request before it can be accepted.
    // A new group may replace a consumed result without releasing ownership;
    // the same edge samples the old result and clears the PE accumulators.
    assign owner_request = rst_n && ((state != S_IDLE) || start_valid);
    assign start_ready = rst_n && owner_grant
        && ((state == S_IDLE)
            || ((state == S_RESULT) && result_ready));

    assign tap_ready = rst_n && owner_grant && (state == S_WAIT_A);
    assign result_valid = rst_n && (state == S_RESULT);

    assign start_fire  = start_valid && start_ready;
    assign tap_fire    = tap_valid && tap_ready;
    assign result_fire = result_valid && result_ready;

    assign result_bin_valid = bin_valid_r;
    assign result_order     = order_r;
    assign result_bin_base  = bin_base_r;
    assign result_band      = band_r;
    assign result_tag       = tag_r;

    assign busy = (state != S_IDLE);
    assign phase = state;
    assign active_tap_index = tap_index_r;
    assign protocol_error = control_error_r
        || (((state != S_IDLE) || result_valid) && (|pe_overflow));

    integer bin_index;
    integer real_pe;
    integer imag_pe;

    always @* begin
        pe_acc_clear  = 16'd0;
        pe_acc_enable = 16'd0;
        pe_mode       = MODE_DENSE;
        pe_operand_a  = {16*8{1'b0}};
        pe_operand_b  = {16*8{1'b0}};

        result_real = {8*32{1'b0}};
        result_imag = {8*32{1'b0}};

        // acc_clear has priority inside pe_hybrid_mac.  It is asserted only
        // on an accepted group start, never with a multiply command.
        if (start_fire) begin
            pe_acc_clear = 16'hffff;
        end

        // The phase-A request is accepted and issued on the same edge.  Its
        // operands are retained for phase B on the following cycle.
        if (tap_fire) begin
            for (bin_index = 0; bin_index < 8; bin_index = bin_index + 1) begin
                real_pe = 2 * bin_index;
                imag_pe = real_pe + 1;
                pe_acc_enable[real_pe] = bin_valid_r[bin_index];
                pe_acc_enable[imag_pe] = bin_valid_r[bin_index];
                pe_operand_a[real_pe*8 +: 8] =
                    spectrum_real_in[bin_index*8 +: 8];
                pe_operand_b[real_pe*8 +: 8] =
                    coefficient_real_in[bin_index*8 +: 8];
                pe_operand_a[imag_pe*8 +: 8] =
                    spectrum_real_in[bin_index*8 +: 8];
                pe_operand_b[imag_pe*8 +: 8] =
                    coefficient_imag_in[bin_index*8 +: 8];
            end
        end

        if ((state == S_ISSUE_B) && owner_grant) begin
            for (bin_index = 0; bin_index < 8; bin_index = bin_index + 1) begin
                real_pe = 2 * bin_index;
                imag_pe = real_pe + 1;
                pe_acc_enable[real_pe] = bin_valid_r[bin_index];
                pe_acc_enable[imag_pe] = bin_valid_r[bin_index];
                pe_operand_a[real_pe*8 +: 8] =
                    spectrum_imag_r[bin_index*8 +: 8];
                pe_operand_b[real_pe*8 +: 8] =
                    (~coefficient_imag_r[bin_index*8 +: 8]) + 8'd1;
                pe_operand_a[imag_pe*8 +: 8] =
                    spectrum_imag_r[bin_index*8 +: 8];
                pe_operand_b[imag_pe*8 +: 8] =
                    coefficient_real_r[bin_index*8 +: 8];
            end
        end

        // The PE accumulators themselves hold a stalled result.  No result
        // register bank, FIFO, or wide post-add datapath is added here.
        for (bin_index = 0; bin_index < 8; bin_index = bin_index + 1) begin
            result_real[bin_index*32 +: 32] =
                pe_accumulator[(2*bin_index)*32 +: 32];
            result_imag[bin_index*32 +: 32] =
                pe_accumulator[(2*bin_index+1)*32 +: 32];
        end
    end

    integer check_bin;

    always @(posedge clk) begin
        if (!rst_n) begin
            state                  <= S_IDLE;
            order_r                <= 3'd1;
            bin_valid_r            <= 8'd0;
            bin_base_r             <= {BIN_INDEX_WIDTH{1'b0}};
            band_r                 <= 2'd0;
            tag_r                  <= {TAG_WIDTH{1'b0}};
            tap_index_r            <= 3'd0;
            spectrum_imag_r        <= {8*8{1'b0}};
            coefficient_real_r     <= {8*8{1'b0}};
            coefficient_imag_r     <= {8*8{1'b0}};
            control_error_r        <= 1'b0;
            done                   <= 1'b0;
        end else begin
            done <= 1'b0;

            // owner_grant is a hold-until-release contract after start_fire.
            if ((state != S_IDLE) && !owner_grant) begin
                control_error_r <= 1'b1;
            end
            if ((state != S_IDLE) && (|pe_overflow)) begin
                control_error_r <= 1'b1;
            end

            case (state)
                S_IDLE: begin
                    if (start_fire) begin
                        state <= S_WAIT_A;
                    end
                end

                S_WAIT_A: begin
                    if (tap_fire) begin
                        spectrum_imag_r    <= spectrum_imag_in;
                        coefficient_real_r <= coefficient_real_in;
                        coefficient_imag_r <= coefficient_imag_in;
                        if (tap_index_in != tap_index_r) begin
                            control_error_r <= 1'b1;
                        end
                        for (check_bin = 0; check_bin < 8;
                             check_bin = check_bin + 1) begin
                            if (bin_valid_r[check_bin]
                                && ((spectrum_real_in[check_bin*8 +: 8] == 8'h80)
                                    || (spectrum_imag_in[check_bin*8 +: 8] == 8'h80)
                                    || (coefficient_real_in[check_bin*8 +: 8] == 8'h80)
                                    || (coefficient_imag_in[check_bin*8 +: 8] == 8'h80))) begin
                                control_error_r <= 1'b1;
                            end
                        end
                        state <= S_ISSUE_B;
                    end
                end

                S_ISSUE_B: begin
                    if (owner_grant) begin
                        if ((tap_index_r + 3'd1) >= order_r) begin
                            state <= S_DRAIN;
                        end else begin
                            tap_index_r <= tap_index_r + 3'd1;
                            state <= S_WAIT_A;
                        end
                    end
                end

                S_DRAIN: begin
                    // One empty command cycle commits the final pipelined
                    // MODE_DENSE term before any result becomes visible.
                    if (owner_grant) begin
                        state <= S_RESULT;
                    end
                end

                S_RESULT: begin
                    if (result_fire) begin
                        done <= 1'b1;
                        if (start_fire) begin
                            state <= S_WAIT_A;
                        end else begin
                            state <= S_IDLE;
                        end
                    end
                end

                default: begin
                    state <= S_IDLE;
                    control_error_r <= 1'b1;
                end
            endcase

            // Group metadata and protocol state are replaced only on a
            // start handshake.  A result/start overlap samples the old PE
            // values and clears them on that same edge.
            if (start_fire) begin
                order_r        <= order_in;
                bin_valid_r    <= bin_valid_in;
                bin_base_r     <= bin_base_in;
                band_r         <= band_in;
                tag_r          <= tag_in;
                tap_index_r    <= 3'd0;
                control_error_r <= !legal_order(order_in);
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (BIN_INDEX_WIDTH < 8) begin
            $fatal(1, "pe_cdf_sequencer BIN_INDEX_WIDTH must cover bins 0..255");
        end
        if (TAG_WIDTH < 1) begin
            $fatal(1, "pe_cdf_sequencer TAG_WIDTH must be positive");
        end
    end
`endif

endmodule
