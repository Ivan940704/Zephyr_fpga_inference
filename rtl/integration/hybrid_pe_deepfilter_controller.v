`timescale 1ns/1ps

// Production controller for Multi-Frame Complex DeepFiltering on the shared
// Hybrid PE array.
//
// This block owns only spectrum/history buffering, coefficient reads, group
// scheduling, and AXI4-Stream packetization.  It contains no multiplier or
// DeepFilter arithmetic lane.  Every complex multiply-accumulate is issued
// through the PE array CDF interface, where pe_cdf_sequencer arbitrates the
// same physical Hybrid MAC lanes used by the neural stages.
//
// One CDF group covers eight bins.  The PE array uses sixteen lanes per group:
// two INT32 accumulators (real and imaginary) for each complex bin.  Causal
// orders are 5/3/1 for bins 0..31, 32..127, and 128..255.
module hybrid_pe_deepfilter_controller #(
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

    // Shared Hybrid PE array CDF request/result boundary.
    output wire                         cdf_start_valid,
    input  wire                         cdf_start_ready,
    output wire [2:0]                   cdf_order,
    output wire [7:0]                   cdf_bin_valid,
    output wire [7:0]                   cdf_bin_base,
    output wire [1:0]                   cdf_band,
    output wire [15:0]                  cdf_tag,
    output wire                         cdf_tap_valid,
    input  wire                         cdf_tap_ready,
    output wire [2:0]                   cdf_tap_index,
    output wire [63:0]                  cdf_spectrum_real,
    output wire [63:0]                  cdf_spectrum_imag,
    output wire [63:0]                  cdf_coefficient_real,
    output wire [63:0]                  cdf_coefficient_imag,
    input  wire                         cdf_result_valid,
    output wire                         cdf_result_ready,
    input  wire [255:0]                 cdf_result_real,
    input  wire [255:0]                 cdf_result_imag,
    input  wire [7:0]                   cdf_result_bin_valid,
    input  wire [2:0]                   cdf_result_order,
    input  wire [7:0]                   cdf_result_bin_base,
    input  wire [1:0]                   cdf_result_band,
    input  wire [15:0]                  cdf_result_tag,

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
    localparam [4:0] ST_IDLE         = 5'd0;
    localparam [4:0] ST_CDF_START    = 5'd1;
    localparam [4:0] ST_SPEC_REQ_0   = 5'd2;
    localparam [4:0] ST_SPEC_CAP_0   = 5'd3;
    localparam [4:0] ST_SPEC_CAP_1   = 5'd4;
    localparam [4:0] ST_COEFF_R_REQ  = 5'd5;
    localparam [4:0] ST_COEFF_R_WAIT = 5'd6;
    localparam [4:0] ST_COEFF_I_REQ  = 5'd7;
    localparam [4:0] ST_COEFF_I_WAIT = 5'd8;
    localparam [4:0] ST_CDF_TAP      = 5'd9;
    localparam [4:0] ST_CDF_RESULT   = 5'd10;
    localparam [4:0] ST_RESULT_STORE = 5'd11;

    localparam [7:0] ERR_NONE        = 8'h00;
    localparam [7:0] ERR_AXIS_KEEP   = 8'h70;
    localparam [7:0] ERR_AXIS_LAST   = 8'h71;
    localparam [7:0] ERR_FRAME_START = 8'h72;
    localparam [7:0] ERR_FRAME_DONE  = 8'h73;
    localparam [7:0] ERR_FRAME_ID    = 8'h74;
    localparam [7:0] ERR_START       = 8'h75;
    localparam [7:0] ERR_COEFFICIENT = 8'h76;
    localparam [7:0] ERR_OUTPUT      = 8'h77;
    localparam [7:0] ERR_CDF_RESULT  = 8'h78;

    // Five banks of 64 packed spectrum beats retain current + four history
    // frames.  Results remain a single-port 256x64 store for AXIS egress.
    (* ram_style = "block" *) reg [63:0] spectrum_mem [0:319];
    (* ram_style = "block" *) reg [63:0] result_mem [0:255];

    reg [4:0] state_q;
    reg [5:0] ingress_beat_q;
    reg [2:0] write_bank_q;
    reg [2:0] history_count_q;
    reg spectrum_buffer_valid_q;
    reg [FRAME_ID_WIDTH-1:0] spectrum_buffer_frame_q;
    reg frame_active_q;

    reg [7:0] group_base_q;
    reg [2:0] tap_q;
    reg [2:0] coefficient_lane_q;
    reg [2:0] result_lane_q;
    reg [63:0] spectrum_word_q;
    reg [63:0] spectrum_real_packet_q;
    reg [63:0] spectrum_imag_packet_q;
    reg [63:0] coefficient_real_packet_q;
    reg [63:0] coefficient_imag_packet_q;
    reg [255:0] cdf_result_real_q;
    reg [255:0] cdf_result_imag_q;
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
    wire cdf_start_fire;
    wire cdf_tap_fire;
    wire cdf_result_fire;
    wire output_issue;
    wire output_fire;
    wire [2:0] current_order;
    wire [1:0] current_band;
    wire [2:0] current_age;
    wire [2:0] current_sample_bank;
    wire current_sample_missing;
    wire [8:0] spectrum_word_address_0;
    wire [8:0] spectrum_word_address_1;
    wire [7:0] coefficient_bin;
    wire result_metadata_match;

    integer packed_lane;

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

    function [1:0] filter_band_for_bin;
        input [7:0] bin_index;
        begin
            if (bin_index < 8'd32)
                filter_band_for_bin = 2'd0;
            else if (bin_index < 8'd128)
                filter_band_for_bin = 2'd1;
            else
                filter_band_for_bin = 2'd2;
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
                // Shift/add forms keep address generation in LUT fabric; the
                // scheduler must not consume DSPs that belong to Hybrid MACs.
                context_base = {3'd0, bin_index[4:3], 6'd0} +
                               {5'd0, bin_index[4:3], 4'd0};
                local_bin = bin_index[2:0];
                coefficient_address_for = context_base +
                    (component_imag ? 11'd40 : 11'd0) +
                    {2'd0, local_bin, 2'd0} +
                    {4'd0, local_bin} + tap_index;
            end else if (bin_index < 8'd128) begin
                relative_bin = bin_index - 8'd32;
                context_base = 11'd320 +
                               {1'd0, relative_bin[7:5], 7'd0} +
                               {2'd0, relative_bin[7:5], 6'd0};
                local_bin = relative_bin[4:0];
                coefficient_address_for = context_base +
                    (component_imag ? 11'd96 : 11'd0) +
                    {3'd0, local_bin, 1'b0} +
                    {4'd0, local_bin} + tap_index;
            end else begin
                relative_bin = bin_index - 8'd128;
                context_base = 11'd896 +
                               {2'd0, relative_bin[7:6], 7'd0};
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

    assign current_order = filter_order_for_bin(group_base_q);
    assign current_band = filter_band_for_bin(group_base_q);
    assign current_age = current_order - 1'b1 - tap_q;
    assign current_sample_bank = history_bank_for_age(write_bank_q,
                                                       current_age);
    assign current_sample_missing = (current_age > history_count_q);
    assign spectrum_word_address_0 = {current_sample_bank, 6'b0} +
        {3'd0, group_base_q[7:2]};
    assign spectrum_word_address_1 = spectrum_word_address_0 + 1'b1;
    assign coefficient_bin = group_base_q + {5'd0, coefficient_lane_q};

    assign s_axis_spectrum_tready = rst_n && !abort && !error_valid &&
        !spectrum_buffer_valid_q && !frame_active_q;
    assign axis_fire = s_axis_spectrum_tvalid && s_axis_spectrum_tready;

    assign start_ready = rst_n && !abort && !error_valid && frame_active_q &&
        spectrum_buffer_valid_q && all_coefficients_valid &&
        !results_valid_q && (state_q == ST_IDLE);
    assign start_fire = start && start_ready;

    assign coefficient_read_req_valid = !abort && !error_valid &&
        ((state_q == ST_COEFF_R_REQ) || (state_q == ST_COEFF_I_REQ));
    assign coefficient_read_req_address = coefficient_read_address_q;
    assign coefficient_read_rsp_ready = !abort && !error_valid &&
        ((state_q == ST_COEFF_R_WAIT) || (state_q == ST_COEFF_I_WAIT));
    assign coefficient_req_fire = coefficient_read_req_valid &&
                                  coefficient_read_req_ready;
    assign coefficient_rsp_fire = coefficient_read_rsp_valid &&
                                  coefficient_read_rsp_ready;

    assign cdf_start_valid = rst_n && !abort && !error_valid &&
                             (state_q == ST_CDF_START);
    assign cdf_order = current_order;
    assign cdf_bin_valid = 8'hff;
    assign cdf_bin_base = group_base_q;
    assign cdf_band = current_band;
    assign cdf_tag = {8'd0, group_base_q};
    assign cdf_start_fire = cdf_start_valid && cdf_start_ready;

    assign cdf_tap_valid = rst_n && !abort && !error_valid &&
                           (state_q == ST_CDF_TAP);
    assign cdf_tap_index = tap_q;
    assign cdf_spectrum_real = spectrum_real_packet_q;
    assign cdf_spectrum_imag = spectrum_imag_packet_q;
    assign cdf_coefficient_real = coefficient_real_packet_q;
    assign cdf_coefficient_imag = coefficient_imag_packet_q;
    assign cdf_tap_fire = cdf_tap_valid && cdf_tap_ready;

    assign cdf_result_ready = rst_n && !abort && !error_valid &&
                              (state_q == ST_CDF_RESULT);
    assign cdf_result_fire = cdf_result_valid && cdf_result_ready;
    assign result_metadata_match =
        (cdf_result_bin_valid == 8'hff) &&
        (cdf_result_order == current_order) &&
        (cdf_result_bin_base == group_base_q) &&
        (cdf_result_band == current_band) &&
        (cdf_result_tag == {8'd0, group_base_q});

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
    assign active_bin = group_base_q;
    assign history_depth = history_count_q;
    assign error = error_valid;

    always @(posedge clk) begin
        if (!rst_n) begin
            state_q <= ST_IDLE;
            ingress_beat_q <= 6'd0;
            write_bank_q <= 3'd0;
            history_count_q <= 3'd0;
            spectrum_buffer_valid_q <= 1'b0;
            spectrum_buffer_frame_q <= {FRAME_ID_WIDTH{1'b0}};
            frame_active_q <= 1'b0;
            group_base_q <= 8'd0;
            tap_q <= 3'd0;
            coefficient_lane_q <= 3'd0;
            result_lane_q <= 3'd0;
            spectrum_word_q <= 64'd0;
            spectrum_real_packet_q <= 64'd0;
            spectrum_imag_packet_q <= 64'd0;
            coefficient_real_packet_q <= 64'd0;
            coefficient_imag_packet_q <= 64'd0;
            cdf_result_real_q <= 256'd0;
            cdf_result_imag_q <= 256'd0;
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
                        {22'd0, state_q, results_valid_q,
                         all_coefficients_valid, frame_active_q,
                         spectrum_buffer_valid_q, 1'b0});
                end else if (start_fire) begin
                    group_base_q <= 8'd0;
                    tap_q <= 3'd0;
                    state_q <= ST_CDF_START;
                end

                case (state_q)
                    ST_IDLE: begin
                    end

                    ST_CDF_START: begin
                        if (cdf_start_fire) begin
                            tap_q <= 3'd0;
                            state_q <= ST_SPEC_REQ_0;
                        end
                    end

                    ST_SPEC_REQ_0: begin
                        spectrum_real_packet_q <= 64'd0;
                        spectrum_imag_packet_q <= 64'd0;
                        coefficient_real_packet_q <= 64'd0;
                        coefficient_imag_packet_q <= 64'd0;
                        coefficient_lane_q <= 3'd0;
                        if (current_sample_missing) begin
                            coefficient_read_address_q <=
                                coefficient_address_for(
                                    group_base_q, tap_q, 1'b0);
                            state_q <= ST_COEFF_R_REQ;
                        end else begin
                            spectrum_word_q <=
                                spectrum_mem[spectrum_word_address_0];
                            state_q <= ST_SPEC_CAP_0;
                        end
                    end

                    ST_SPEC_CAP_0: begin
                        for (packed_lane = 0; packed_lane < 4;
                             packed_lane = packed_lane + 1) begin
                            spectrum_real_packet_q[packed_lane*8 +: 8] <=
                                spectrum_word_q[packed_lane*16 +: 8];
                            spectrum_imag_packet_q[packed_lane*8 +: 8] <=
                                spectrum_word_q[packed_lane*16 + 8 +: 8];
                        end
                        spectrum_word_q <=
                            spectrum_mem[spectrum_word_address_1];
                        state_q <= ST_SPEC_CAP_1;
                    end

                    ST_SPEC_CAP_1: begin
                        for (packed_lane = 0; packed_lane < 4;
                             packed_lane = packed_lane + 1) begin
                            spectrum_real_packet_q[(packed_lane+4)*8 +: 8] <=
                                spectrum_word_q[packed_lane*16 +: 8];
                            spectrum_imag_packet_q[(packed_lane+4)*8 +: 8] <=
                                spectrum_word_q[packed_lane*16 + 8 +: 8];
                        end
                        coefficient_lane_q <= 3'd0;
                        coefficient_read_address_q <=
                            coefficient_address_for(
                                group_base_q, tap_q, 1'b0);
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
                                    {6'd0, 1'b0, tap_q, coefficient_bin,
                                     coefficient_read_req_address, 3'd0});
                                state_q <= ST_IDLE;
                            end else begin
                                coefficient_real_packet_q[
                                    coefficient_lane_q*8 +: 8] <=
                                    coefficient_read_rsp_value;
                                coefficient_read_address_q <=
                                    coefficient_address_for(
                                        coefficient_bin, tap_q, 1'b1);
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
                                    {6'd0, 1'b1, tap_q, coefficient_bin,
                                     coefficient_read_req_address, 3'd0});
                                state_q <= ST_IDLE;
                            end else begin
                                coefficient_imag_packet_q[
                                    coefficient_lane_q*8 +: 8] <=
                                    coefficient_read_rsp_value;
                                if (coefficient_lane_q == 3'd7) begin
                                    state_q <= ST_CDF_TAP;
                                end else begin
                                    coefficient_lane_q <=
                                        coefficient_lane_q + 1'b1;
                                    coefficient_read_address_q <=
                                        coefficient_address_for(
                                            coefficient_bin + 1'b1,
                                            tap_q, 1'b0);
                                    state_q <= ST_COEFF_R_REQ;
                                end
                            end
                        end
                    end

                    ST_CDF_TAP: begin
                        if (cdf_tap_fire) begin
                            if (tap_q + 1'b1 == current_order) begin
                                state_q <= ST_CDF_RESULT;
                            end else begin
                                tap_q <= tap_q + 1'b1;
                                state_q <= ST_SPEC_REQ_0;
                            end
                        end
                    end

                    ST_CDF_RESULT: begin
                        if (cdf_result_fire) begin
                            if (!result_metadata_match) begin
                                latch_error(ERR_CDF_RESULT,
                                    {cdf_result_order,
                                     cdf_result_band,
                                     cdf_result_bin_valid,
                                     cdf_result_bin_base,
                                     cdf_result_tag[10:0]});
                                state_q <= ST_IDLE;
                            end else begin
                                cdf_result_real_q <= cdf_result_real;
                                cdf_result_imag_q <= cdf_result_imag;
                                result_lane_q <= 3'd0;
                                state_q <= ST_RESULT_STORE;
                            end
                        end
                    end

                    ST_RESULT_STORE: begin
                        result_mem[group_base_q +
                                   {5'd0, result_lane_q}] <=
                            {cdf_result_imag_q[result_lane_q*32 +: 32],
                             cdf_result_real_q[result_lane_q*32 +: 32]};
                        if (result_lane_q == 3'd7) begin
                            if (group_base_q == 8'd248) begin
                                results_valid_q <= 1'b1;
                                output_index_q <= 8'd0;
                                done <= 1'b1;
                                state_q <= ST_IDLE;
                            end else begin
                                group_base_q <= group_base_q + 4'd8;
                                tap_q <= 3'd0;
                                state_q <= ST_CDF_START;
                            end
                        end else begin
                            result_lane_q <= result_lane_q + 1'b1;
                        end
                    end

                    default: begin
                        latch_error(ERR_START, {27'd0, state_q});
                        state_q <= ST_IDLE;
                    end
                endcase

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
                            {22'd0, state_q, results_valid_q,
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

`ifndef SYNTHESIS
    initial begin
        if (FRAME_ID_WIDTH != 16) begin
            $display("Hybrid PE DeepFilter controller requires FRAME_ID_WIDTH=16");
            $finish;
        end
    end
`endif

endmodule
