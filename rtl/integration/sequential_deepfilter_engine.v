`timescale 1ns/1ps

// Sequential DeepFilter execution engine for one 256-bin complex INT8 frame.
//
// Spectrum ingress is one 512-byte AXI4-Stream packet.  Each 64-bit beat holds
// four bins in little-endian byte lanes:
//   byte 2*n = signed real, byte 2*n+1 = signed imaginary.
// The engine retains four completed frames plus the current frame and applies
// causal orders 5/3/1 to bins 0..31, 32..127, and 128..255 respectively.
// Coefficients are read from sequential_df_coefficient_store in
// {component, local_bin, tap} order.  Output is 256 64-bit beats with signed
// INT32 real in bits 31:0 and signed INT32 imaginary in bits 63:32.
module sequential_deepfilter_engine #(
    parameter integer FRAME_ID_WIDTH = 16
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         abort,
    input  wire                         clear_history,
    input  wire [FRAME_ID_WIDTH-1:0]    current_frame_id,
    input  wire                         frame_start,
    input  wire                         frame_done,

    input  wire                         s_axis_spectrum_tvalid,
    output wire                         s_axis_spectrum_tready,
    input  wire [63:0]                  s_axis_spectrum_tdata,
    input  wire [7:0]                   s_axis_spectrum_tkeep,
    input  wire                         s_axis_spectrum_tlast,

    input  wire                         start,
    output wire                         start_ready,
    output reg                          done,
    output wire                         error,
    input  wire                         all_coefficients_valid,

    output wire                         coefficient_read_req_valid,
    input  wire                         coefficient_read_req_ready,
    output wire [10:0]                  coefficient_read_req_address,
    input  wire                         coefficient_read_rsp_valid,
    output wire                         coefficient_read_rsp_ready,
    input  wire signed [7:0]            coefficient_read_rsp_value,
    input  wire                         coefficient_read_rsp_error,

    input  wire                         output_enable,
    output wire                         m_axis_output_tvalid,
    input  wire                         m_axis_output_tready,
    output wire [63:0]                  m_axis_output_tdata,
    output wire [7:0]                   m_axis_output_tkeep,
    output wire                         m_axis_output_tlast,
    output reg                          output_complete,

    output wire                         spectrum_buffer_valid,
    output wire [FRAME_ID_WIDTH-1:0]    spectrum_buffer_frame_id,
    output wire                         frame_active,
    output wire                         busy,
    output wire [7:0]                   active_bin,
    output wire [2:0]                   history_depth,
    output reg                          error_valid,
    output reg [7:0]                    error_code,
    output reg [31:0]                   error_detail
);
    localparam [3:0] ST_IDLE       = 4'd0;
    localparam [3:0] ST_CLEAR      = 4'd1;
    localparam [3:0] ST_SPEC_REQ   = 4'd2;
    localparam [3:0] ST_SPEC_CAP   = 4'd3;
    localparam [3:0] ST_COEFF_R_REQ  = 4'd4;
    localparam [3:0] ST_COEFF_R_WAIT = 4'd5;
    localparam [3:0] ST_COEFF_I_REQ  = 4'd6;
    localparam [3:0] ST_COEFF_I_WAIT = 4'd7;
    localparam [3:0] ST_TERM       = 4'd8;
    localparam [3:0] ST_STORE      = 4'd9;

    localparam [7:0] ERR_NONE        = 8'h00;
    localparam [7:0] ERR_AXIS_KEEP   = 8'h70;
    localparam [7:0] ERR_AXIS_LAST   = 8'h71;
    localparam [7:0] ERR_FRAME_START = 8'h72;
    localparam [7:0] ERR_FRAME_DONE  = 8'h73;
    localparam [7:0] ERR_FRAME_ID    = 8'h74;
    localparam [7:0] ERR_START       = 8'h75;
    localparam [7:0] ERR_COEFFICIENT = 8'h76;
    localparam [7:0] ERR_OUTPUT      = 8'h77;

    (* ram_style = "block" *) reg [63:0] spectrum_mem [0:319];
    (* ram_style = "block" *) reg [63:0] result_mem [0:255];

    reg [3:0] state_q;
    reg [5:0] ingress_beat_q;
    reg [2:0] write_bank_q;
    reg [2:0] history_count_q;
    reg spectrum_buffer_valid_q;
    reg [FRAME_ID_WIDTH-1:0] spectrum_buffer_frame_q;
    reg frame_active_q;

    reg [7:0] bin_q;
    reg [2:0] tap_q;
    reg [63:0] spectrum_word_q;
    reg spectrum_missing_q;
    reg signed [7:0] spectrum_real_q;
    reg signed [7:0] spectrum_imag_q;
    reg signed [7:0] coefficient_real_q;
    reg signed [7:0] coefficient_imag_q;
    reg [10:0] coefficient_read_address_q;

    reg results_valid_q;
    reg [7:0] output_index_q;
    reg output_read_pending_q;
    reg output_valid_q;
    reg [63:0] output_data_q;

    wire axis_fire;
    wire start_fire;
    wire coefficient_req_fire;
    wire coefficient_rsp_fire;
    wire output_issue;
    wire output_fire;
    wire clear_acc;
    wire term_valid;
    wire signed [31:0] mac_real_acc;
    wire signed [31:0] mac_imag_acc;
    wire [2:0] current_order;
    wire [2:0] current_age;
    wire [2:0] current_sample_bank;
    wire current_sample_missing;
    wire [8:0] spectrum_read_address;

    integer lane;

    function [2:0] filter_order_for_bin;
        input [7:0] bin_index;
        begin
            if (bin_index < 8'd32)
                filter_order_for_bin = 3'd5;
            else if (bin_index < 8'd128)
                filter_order_for_bin = 3'd3;
            else
                filter_order_for_bin = 3'd1;
        end
    endfunction

    function [2:0] history_bank_for_age;
        input [2:0] current_bank;
        input [2:0] age;
        reg [3:0] adjusted;
        begin
            adjusted = {1'b0, current_bank} + 4'd5 - {1'b0, age};
            if (adjusted >= 4'd5)
                adjusted = adjusted - 4'd5;
            history_bank_for_age = adjusted[2:0];
        end
    endfunction

    function [10:0] coefficient_address_for;
        input [7:0] bin_index;
        input [2:0] tap_index;
        input component_imag;
        reg [7:0] relative_bin;
        reg [10:0] context_base;
        reg [6:0] local_bin;
        begin
            if (bin_index < 8'd32) begin
                context_base = (bin_index >> 3) * 11'd80;
                local_bin = bin_index[2:0];
                coefficient_address_for = context_base +
                    (component_imag ? 11'd40 : 11'd0) +
                    local_bin * 11'd5 + tap_index;
            end else if (bin_index < 8'd128) begin
                relative_bin = bin_index - 8'd32;
                context_base = 11'd320 + (relative_bin >> 5) * 11'd192;
                local_bin = relative_bin[4:0];
                coefficient_address_for = context_base +
                    (component_imag ? 11'd96 : 11'd0) +
                    local_bin * 11'd3 + tap_index;
            end else begin
                relative_bin = bin_index - 8'd128;
                context_base = 11'd896 + (relative_bin >> 6) * 11'd128;
                local_bin = relative_bin[5:0];
                coefficient_address_for = context_base +
                    (component_imag ? 11'd64 : 11'd0) + local_bin;
            end
        end
    endfunction

    task latch_error;
        input [7:0] code;
        input [31:0] detail;
        begin
            if (!error_valid) begin
                error_valid <= 1'b1;
                error_code <= code;
                error_detail <= detail;
            end
        end
    endtask

    assign current_order = filter_order_for_bin(bin_q);
    assign current_age = current_order - 1'b1 - tap_q;
    assign current_sample_bank = history_bank_for_age(write_bank_q,
                                                       current_age);
    assign current_sample_missing = (current_age > history_count_q);
    assign spectrum_read_address = {current_sample_bank, 6'b0} +
                                   {3'd0, bin_q[7:2]};

    assign s_axis_spectrum_tready = rst_n && !abort && !error_valid &&
        !spectrum_buffer_valid_q && !frame_active_q;
    assign axis_fire = s_axis_spectrum_tvalid && s_axis_spectrum_tready;

    assign start_ready = rst_n && !abort && !error_valid && frame_active_q &&
        spectrum_buffer_valid_q && all_coefficients_valid &&
        !results_valid_q && (state_q == ST_IDLE);
    assign start_fire = start && start_ready;

    assign coefficient_read_req_valid = !abort && !error_valid &&
        ((state_q == ST_COEFF_R_REQ) || (state_q == ST_COEFF_I_REQ));
    // Precompute the coefficient address on the state transition preceding
    // each request.  Keeping the BRAM address stable in a register removes
    // the long bin/tap arithmetic cone from the coefficient-store BRAM
    // control pins without adding a request or execution cycle.
    assign coefficient_read_req_address = coefficient_read_address_q;
    assign coefficient_read_rsp_ready = !abort && !error_valid &&
        ((state_q == ST_COEFF_R_WAIT) || (state_q == ST_COEFF_I_WAIT));
    assign coefficient_req_fire = coefficient_read_req_valid &&
                                  coefficient_read_req_ready;
    assign coefficient_rsp_fire = coefficient_read_rsp_valid &&
                                  coefficient_read_rsp_ready;

    assign clear_acc = (state_q == ST_CLEAR);
    assign term_valid = (state_q == ST_TERM);

    assign output_issue = output_enable && results_valid_q &&
                          !output_valid_q && !output_read_pending_q;
    assign m_axis_output_tvalid = output_enable && output_valid_q;
    assign m_axis_output_tdata = output_data_q;
    assign m_axis_output_tkeep = 8'hff;
    assign m_axis_output_tlast = (output_index_q == 8'hff);
    assign output_fire = m_axis_output_tvalid && m_axis_output_tready;

    assign spectrum_buffer_valid = spectrum_buffer_valid_q;
    assign spectrum_buffer_frame_id = spectrum_buffer_frame_q;
    assign frame_active = frame_active_q;
    assign busy = (state_q != ST_IDLE) || results_valid_q ||
                  output_read_pending_q || output_valid_q;
    assign active_bin = bin_q;
    assign history_depth = history_count_q;
    assign error = error_valid;

    deepfilter_complex_mac u_complex_mac (
        .clk(clk),
        .rst(!rst_n),
        .clear_acc(clear_acc),
        .term_valid(term_valid),
        .spectrum_real_q(spectrum_real_q),
        .spectrum_imag_q(spectrum_imag_q),
        .coefficient_real_q(coefficient_real_q),
        .coefficient_imag_q(coefficient_imag_q),
        .real_acc(mac_real_acc),
        .imag_acc(mac_imag_acc)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            state_q <= ST_IDLE;
            ingress_beat_q <= 6'd0;
            write_bank_q <= 3'd0;
            history_count_q <= 3'd0;
            spectrum_buffer_valid_q <= 1'b0;
            spectrum_buffer_frame_q <= {FRAME_ID_WIDTH{1'b0}};
            frame_active_q <= 1'b0;
            bin_q <= 8'd0;
            tap_q <= 3'd0;
            spectrum_word_q <= 64'd0;
            spectrum_missing_q <= 1'b0;
            spectrum_real_q <= 8'sd0;
            spectrum_imag_q <= 8'sd0;
            coefficient_real_q <= 8'sd0;
            coefficient_imag_q <= 8'sd0;
            coefficient_read_address_q <= 11'd0;
            results_valid_q <= 1'b0;
            output_index_q <= 8'd0;
            output_read_pending_q <= 1'b0;
            output_valid_q <= 1'b0;
            output_data_q <= 64'd0;
            done <= 1'b0;
            output_complete <= 1'b0;
            error_valid <= 1'b0;
            error_code <= ERR_NONE;
            error_detail <= 32'd0;
        end else begin
            done <= 1'b0;
            output_complete <= 1'b0;

            if (abort) begin
                state_q <= ST_IDLE;
                ingress_beat_q <= 6'd0;
                spectrum_buffer_valid_q <= 1'b0;
                frame_active_q <= 1'b0;
                results_valid_q <= 1'b0;
                output_read_pending_q <= 1'b0;
                output_valid_q <= 1'b0;
            end else begin
                // The frame spectrum is accepted before the control FSM
                // samples START.  Preserve write_bank_q so the current frame
                // remains addressable, but make every older age missing.
                if (clear_history)
                    history_count_q <= 3'd0;

                if (spectrum_buffer_valid_q &&
                    (spectrum_buffer_frame_q != current_frame_id) &&
                    !frame_done) begin
                    latch_error(ERR_FRAME_ID,
                        {spectrum_buffer_frame_q[15:0],
                         current_frame_id[15:0]});
                end

                if (axis_fire) begin
                    if (s_axis_spectrum_tkeep != 8'hff) begin
                        ingress_beat_q <= 6'd0;
                        latch_error(ERR_AXIS_KEEP,
                            {18'd0, ingress_beat_q,
                             s_axis_spectrum_tkeep});
                    end else if (s_axis_spectrum_tlast !=
                                 (ingress_beat_q == 6'd63)) begin
                        ingress_beat_q <= 6'd0;
                        latch_error(ERR_AXIS_LAST,
                            {25'd0, s_axis_spectrum_tlast,
                             ingress_beat_q});
                    end else begin
                        spectrum_mem[{write_bank_q, 6'b0} +
                                     ingress_beat_q] <=
                            s_axis_spectrum_tdata;
                        if (ingress_beat_q == 6'd0)
                            spectrum_buffer_frame_q <= current_frame_id;
                        if (ingress_beat_q == 6'd63) begin
                            ingress_beat_q <= 6'd0;
                            spectrum_buffer_valid_q <= 1'b1;
                        end else begin
                            ingress_beat_q <= ingress_beat_q + 1'b1;
                        end
                    end
                end

                if (frame_start) begin
                    if (!spectrum_buffer_valid_q || frame_active_q ||
                        (spectrum_buffer_frame_q != current_frame_id)) begin
                        latch_error(ERR_FRAME_START,
                            {spectrum_buffer_frame_q[15:0],
                             current_frame_id[15:0]});
                    end else begin
                        frame_active_q <= 1'b1;
                    end
                end

                if (start && !start_ready) begin
                    latch_error(ERR_START,
                        {23'd0, state_q, results_valid_q,
                         all_coefficients_valid, frame_active_q,
                         spectrum_buffer_valid_q, 1'b0});
                end else if (start_fire) begin
                    bin_q <= 8'd0;
                    tap_q <= 3'd0;
                    state_q <= ST_CLEAR;
                end

                case (state_q)
                    ST_IDLE: begin
                    end

                    ST_CLEAR: begin
                        tap_q <= 3'd0;
                        state_q <= ST_SPEC_REQ;
                    end

                    ST_SPEC_REQ: begin
                        spectrum_word_q <= spectrum_mem[
                            spectrum_read_address];
                        spectrum_missing_q <= current_sample_missing;
                        state_q <= ST_SPEC_CAP;
                    end

                    ST_SPEC_CAP: begin
                        if (spectrum_missing_q) begin
                            spectrum_real_q <= 8'sd0;
                            spectrum_imag_q <= 8'sd0;
                        end else begin
                            spectrum_real_q <= spectrum_word_q[
                                bin_q[1:0]*16 +: 8];
                            spectrum_imag_q <= spectrum_word_q[
                                bin_q[1:0]*16 + 8 +: 8];
                        end
                        coefficient_read_address_q <= coefficient_address_for(
                            bin_q, tap_q, 1'b0);
                        state_q <= ST_COEFF_R_REQ;
                    end

                    ST_COEFF_R_REQ: begin
                        if (coefficient_req_fire)
                            state_q <= ST_COEFF_R_WAIT;
                    end

                    ST_COEFF_R_WAIT: begin
                        if (coefficient_rsp_fire) begin
                            if (coefficient_read_rsp_error) begin
                                latch_error(ERR_COEFFICIENT,
                                    {9'd0, 1'b0, tap_q, bin_q,
                                     coefficient_read_req_address});
                                state_q <= ST_IDLE;
                            end else begin
                                coefficient_real_q <=
                                    coefficient_read_rsp_value;
                                coefficient_read_address_q <=
                                    coefficient_address_for(
                                        bin_q, tap_q, 1'b1);
                                state_q <= ST_COEFF_I_REQ;
                            end
                        end
                    end

                    ST_COEFF_I_REQ: begin
                        if (coefficient_req_fire)
                            state_q <= ST_COEFF_I_WAIT;
                    end

                    ST_COEFF_I_WAIT: begin
                        if (coefficient_rsp_fire) begin
                            if (coefficient_read_rsp_error) begin
                                latch_error(ERR_COEFFICIENT,
                                    {9'd0, 1'b1, tap_q, bin_q,
                                     coefficient_read_req_address});
                                state_q <= ST_IDLE;
                            end else begin
                                coefficient_imag_q <=
                                    coefficient_read_rsp_value;
                                state_q <= ST_TERM;
                            end
                        end
                    end

                    ST_TERM: begin
                        if (tap_q + 1'b1 == current_order)
                            state_q <= ST_STORE;
                        else begin
                            tap_q <= tap_q + 1'b1;
                            state_q <= ST_SPEC_REQ;
                        end
                    end

                    ST_STORE: begin
                        result_mem[bin_q] <= {mac_imag_acc, mac_real_acc};
                        if (bin_q == 8'hff) begin
                            results_valid_q <= 1'b1;
                            output_index_q <= 8'd0;
                            done <= 1'b1;
                            state_q <= ST_IDLE;
                        end else begin
                            bin_q <= bin_q + 1'b1;
                            state_q <= ST_CLEAR;
                        end
                    end

                    default: begin
                        latch_error(ERR_START, {28'd0, state_q});
                        state_q <= ST_IDLE;
                    end
                endcase

                // The consumer observes output_complete for one cycle while
                // its FSM is still asserting output_enable.  That is the
                // successful retirement handshake, not an empty-output
                // protocol violation.
                if (output_enable && !output_complete && !results_valid_q &&
                    !output_valid_q && !output_read_pending_q) begin
                    latch_error(ERR_OUTPUT, 32'h00000001);
                end

                if (output_issue)
                    output_read_pending_q <= 1'b1;

                if (output_read_pending_q) begin
                    output_data_q <= result_mem[output_index_q];
                    output_read_pending_q <= 1'b0;
                    output_valid_q <= 1'b1;
                end

                if (output_fire) begin
                    output_valid_q <= 1'b0;
                    if (output_index_q == 8'hff) begin
                        results_valid_q <= 1'b0;
                        output_complete <= 1'b1;
                    end else begin
                        output_index_q <= output_index_q + 1'b1;
                    end
                end

                if (frame_done) begin
                    if (!frame_active_q || (state_q != ST_IDLE) ||
                        results_valid_q || output_valid_q ||
                        output_read_pending_q) begin
                        latch_error(ERR_FRAME_DONE,
                            {23'd0, state_q, results_valid_q,
                             output_valid_q, output_read_pending_q,
                             frame_active_q, 1'b0});
                    end else begin
                        frame_active_q <= 1'b0;
                        spectrum_buffer_valid_q <= 1'b0;
                        if (write_bank_q == 3'd4)
                            write_bank_q <= 3'd0;
                        else
                            write_bank_q <= write_bank_q + 1'b1;
                        if (!clear_history && history_count_q < 3'd4)
                            history_count_q <= history_count_q + 1'b1;
                    end
                end
            end
        end
    end
endmodule
