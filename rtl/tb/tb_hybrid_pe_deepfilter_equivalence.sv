`timescale 1ns/1ps

// Differential regression for the production Hybrid-PE DeepFilter controller.
// The legacy sequential engine and the shared-PE controller receive identical
// spectra, coefficient responses, frame/history events, and output ready.
// Every signed INT32 complex result must match exactly.
module tb_hybrid_pe_deepfilter_equivalence;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg abort = 1'b0;
    reg clear_history = 1'b0;
    reg [15:0] current_frame_id = 16'd0;
    reg frame_start = 1'b0;
    reg frame_done = 1'b0;

    reg spectrum_valid = 1'b0;
    reg [63:0] spectrum_data = 64'd0;
    reg [7:0] spectrum_keep = 8'hff;
    reg spectrum_last = 1'b0;
    wire old_spectrum_ready;
    wire new_spectrum_ready;

    reg start = 1'b0;
    wire old_start_ready;
    wire new_start_ready;
    wire old_done;
    wire new_done;
    wire old_error;
    wire new_error;

    wire old_coeff_req_valid;
    wire [10:0] old_coeff_req_address;
    reg old_coeff_rsp_valid = 1'b0;
    wire old_coeff_rsp_ready;
    reg signed [7:0] old_coeff_rsp_value = 8'sd0;

    wire new_coeff_req_valid;
    wire [10:0] new_coeff_req_address;
    reg new_coeff_rsp_valid = 1'b0;
    wire new_coeff_rsp_ready;
    reg signed [7:0] new_coeff_rsp_value = 8'sd0;

    reg output_enable = 1'b0;
    wire old_output_valid;
    wire new_output_valid;
    wire [63:0] old_output_data;
    wire [63:0] new_output_data;
    wire old_output_complete;
    wire new_output_complete;

    wire cdf_start_valid;
    wire cdf_start_ready;
    wire [2:0] cdf_order;
    wire [7:0] cdf_bin_valid;
    wire [7:0] cdf_bin_base;
    wire [1:0] cdf_band;
    wire [15:0] cdf_tag;
    wire cdf_tap_valid;
    wire cdf_tap_ready;
    wire [2:0] cdf_tap_index;
    wire [63:0] cdf_spectrum_real;
    wire [63:0] cdf_spectrum_imag;
    wire [63:0] cdf_coefficient_real;
    wire [63:0] cdf_coefficient_imag;
    wire cdf_result_valid;
    wire cdf_result_ready;
    wire [255:0] cdf_result_real;
    wire [255:0] cdf_result_imag;
    wire [7:0] cdf_result_bin_valid;
    wire [2:0] cdf_result_order;
    wire [7:0] cdf_result_bin_base;
    wire [1:0] cdf_result_band;
    wire [15:0] cdf_result_tag;

    wire cdf_owner_request;
    wire [15:0] pe_acc_clear;
    wire [15:0] pe_acc_enable;
    wire [1:0] pe_mode;
    wire [16*8-1:0] pe_operand_a;
    wire [16*8-1:0] pe_operand_b;
    wire [16*32-1:0] pe_accumulator;
    wire [15:0] pe_overflow;
    wire cdf_protocol_error;

    wire old_error_valid;
    wire [7:0] old_error_code;
    wire [31:0] old_error_detail;
    wire new_error_valid;
    wire [7:0] new_error_code;
    wire [31:0] new_error_detail;

    reg [63:0] old_results [0:255];
    reg [63:0] new_results [0:255];
    integer old_output_count = 0;
    integer new_output_count = 0;
    integer checks = 0;
    integer frame_index;
    integer beat_index;
    integer lane_index;
    integer bin_index;
    integer mismatch_count = 0;

    always #5 clk = ~clk;

    function signed [7:0] coefficient_value;
        input [10:0] address;
        integer value;
        begin
            value = ((address * 29 + 17) % 255) - 127;
            coefficient_value = value;
        end
    endfunction

    function signed [7:0] spectrum_real_value;
        input integer frame_number;
        input integer bin_number;
        integer value;
        begin
            value = ((frame_number * 37 + bin_number * 11 + 3) % 255) - 127;
            spectrum_real_value = value;
        end
    endfunction

    function signed [7:0] spectrum_imag_value;
        input integer frame_number;
        input integer bin_number;
        integer value;
        begin
            value = ((frame_number * 19 + bin_number * 23 + 91) % 255) - 127;
            spectrum_imag_value = value;
        end
    endfunction

    task fail;
        input [8*120-1:0] message;
        begin
            $display("FAIL %0s frame=%0d time=%0t old_code=%02x old_detail=%08x new_code=%02x new_detail=%08x",
                     message, current_frame_id, $time,
                     old_error_code, old_error_detail,
                     new_error_code, new_error_detail);
            $finish;
        end
    endtask

    task check;
        input condition;
        input [8*120-1:0] message;
        begin
            checks = checks + 1;
            if (!condition)
                fail(message);
        end
    endtask

    sequential_deepfilter_engine old_engine (
        .clk(clk), .rst_n(rst_n), .abort(abort),
        .clear_history(clear_history), .current_frame_id(current_frame_id),
        .frame_start(frame_start), .frame_done(frame_done),
        .s_axis_spectrum_tvalid(spectrum_valid),
        .s_axis_spectrum_tready(old_spectrum_ready),
        .s_axis_spectrum_tdata(spectrum_data),
        .s_axis_spectrum_tkeep(spectrum_keep),
        .s_axis_spectrum_tlast(spectrum_last),
        .start(start), .start_ready(old_start_ready), .done(old_done),
        .error(old_error), .all_coefficients_valid(1'b1),
        .coefficient_read_req_valid(old_coeff_req_valid),
        .coefficient_read_req_ready(1'b1),
        .coefficient_read_req_address(old_coeff_req_address),
        .coefficient_read_rsp_valid(old_coeff_rsp_valid),
        .coefficient_read_rsp_ready(old_coeff_rsp_ready),
        .coefficient_read_rsp_value(old_coeff_rsp_value),
        .coefficient_read_rsp_error(1'b0),
        .output_enable(output_enable),
        .m_axis_output_tvalid(old_output_valid),
        .m_axis_output_tready(1'b1),
        .m_axis_output_tdata(old_output_data),
        .m_axis_output_tkeep(), .m_axis_output_tlast(),
        .output_complete(old_output_complete),
        .spectrum_buffer_valid(), .spectrum_buffer_frame_id(),
        .frame_active(), .busy(), .active_bin(), .history_depth(),
        .error_valid(old_error_valid), .error_code(old_error_code),
        .error_detail(old_error_detail)
    );

    hybrid_pe_deepfilter_controller new_controller (
        .clk(clk), .rst_n(rst_n), .abort(abort),
        .clear_history(clear_history), .current_frame_id(current_frame_id),
        .frame_start(frame_start), .frame_done(frame_done),
        .s_axis_spectrum_tvalid(spectrum_valid),
        .s_axis_spectrum_tready(new_spectrum_ready),
        .s_axis_spectrum_tdata(spectrum_data),
        .s_axis_spectrum_tkeep(spectrum_keep),
        .s_axis_spectrum_tlast(spectrum_last),
        .start(start), .start_ready(new_start_ready), .done(new_done),
        .error(new_error), .all_coefficients_valid(1'b1),
        .coefficient_read_req_valid(new_coeff_req_valid),
        .coefficient_read_req_ready(1'b1),
        .coefficient_read_req_address(new_coeff_req_address),
        .coefficient_read_rsp_valid(new_coeff_rsp_valid),
        .coefficient_read_rsp_ready(new_coeff_rsp_ready),
        .coefficient_read_rsp_value(new_coeff_rsp_value),
        .coefficient_read_rsp_error(1'b0),
        .output_enable(output_enable),
        .m_axis_output_tvalid(new_output_valid),
        .m_axis_output_tready(1'b1),
        .m_axis_output_tdata(new_output_data),
        .m_axis_output_tkeep(), .m_axis_output_tlast(),
        .output_complete(new_output_complete),
        .cdf_start_valid(cdf_start_valid),
        .cdf_start_ready(cdf_start_ready),
        .cdf_order(cdf_order), .cdf_bin_valid(cdf_bin_valid),
        .cdf_bin_base(cdf_bin_base), .cdf_band(cdf_band), .cdf_tag(cdf_tag),
        .cdf_tap_valid(cdf_tap_valid), .cdf_tap_ready(cdf_tap_ready),
        .cdf_tap_index(cdf_tap_index),
        .cdf_spectrum_real(cdf_spectrum_real),
        .cdf_spectrum_imag(cdf_spectrum_imag),
        .cdf_coefficient_real(cdf_coefficient_real),
        .cdf_coefficient_imag(cdf_coefficient_imag),
        .cdf_result_valid(cdf_result_valid),
        .cdf_result_ready(cdf_result_ready),
        .cdf_result_real(cdf_result_real),
        .cdf_result_imag(cdf_result_imag),
        .cdf_result_bin_valid(cdf_result_bin_valid),
        .cdf_result_order(cdf_result_order),
        .cdf_result_bin_base(cdf_result_bin_base),
        .cdf_result_band(cdf_result_band),
        .cdf_result_tag(cdf_result_tag),
        .spectrum_buffer_valid(), .spectrum_buffer_frame_id(),
        .frame_active(), .busy(), .active_bin(), .history_depth(),
        .error_valid(new_error_valid), .error_code(new_error_code),
        .error_detail(new_error_detail)
    );

    pe_cdf_sequencer cdf_sequencer (
        .clk(clk), .rst_n(rst_n),
        .start_valid(cdf_start_valid), .start_ready(cdf_start_ready),
        .order_in(cdf_order), .bin_valid_in(cdf_bin_valid),
        .bin_base_in(cdf_bin_base), .band_in(cdf_band), .tag_in(cdf_tag),
        .owner_request(cdf_owner_request), .owner_grant(cdf_owner_request),
        .tap_valid(cdf_tap_valid), .tap_ready(cdf_tap_ready),
        .tap_index_in(cdf_tap_index),
        .spectrum_real_in(cdf_spectrum_real),
        .spectrum_imag_in(cdf_spectrum_imag),
        .coefficient_real_in(cdf_coefficient_real),
        .coefficient_imag_in(cdf_coefficient_imag),
        .pe_acc_clear(pe_acc_clear), .pe_acc_enable(pe_acc_enable),
        .pe_mode(pe_mode), .pe_operand_a(pe_operand_a),
        .pe_operand_b(pe_operand_b), .pe_accumulator(pe_accumulator),
        .pe_overflow(pe_overflow),
        .result_valid(cdf_result_valid), .result_ready(cdf_result_ready),
        .result_real(cdf_result_real), .result_imag(cdf_result_imag),
        .result_bin_valid(cdf_result_bin_valid),
        .result_order(cdf_result_order),
        .result_bin_base(cdf_result_bin_base),
        .result_band(cdf_result_band), .result_tag(cdf_result_tag),
        .busy(), .done(), .protocol_error(cdf_protocol_error),
        .phase(), .active_tap_index()
    );

    genvar pe_lane;
    generate
        for (pe_lane = 0; pe_lane < 16; pe_lane = pe_lane + 1) begin : g_pe
            pe_hybrid_mac pe (
                .clk(clk), .rst_n(rst_n),
                .acc_clear(pe_acc_clear[pe_lane]),
                .acc_enable(pe_acc_enable[pe_lane]), .mode(pe_mode),
                .operand_a(pe_operand_a[pe_lane*8 +: 8]),
                .operand_b(pe_operand_b[pe_lane*8 +: 8]),
                .gate_u8(8'd0), .spike_enable(1'b0),
                .direct_value(32'sd0),
                .accumulator(pe_accumulator[pe_lane*32 +: 32]),
                .overflow(pe_overflow[pe_lane])
            );
        end
    endgenerate

    always @(posedge clk) begin
        if (old_coeff_rsp_valid && old_coeff_rsp_ready)
            old_coeff_rsp_valid <= 1'b0;
        if (old_coeff_req_valid) begin
            if (old_coeff_rsp_valid)
                fail("legacy coefficient response overlap");
            old_coeff_rsp_valid <= 1'b1;
            old_coeff_rsp_value <= coefficient_value(old_coeff_req_address);
        end

        if (new_coeff_rsp_valid && new_coeff_rsp_ready)
            new_coeff_rsp_valid <= 1'b0;
        if (new_coeff_req_valid) begin
            if (new_coeff_rsp_valid)
                fail("hybrid coefficient response overlap");
            new_coeff_rsp_valid <= 1'b1;
            new_coeff_rsp_value <= coefficient_value(new_coeff_req_address);
        end

        if (output_enable && old_output_valid) begin
            old_results[old_output_count] <= old_output_data;
            old_output_count <= old_output_count + 1;
        end
        if (output_enable && new_output_valid) begin
            new_results[new_output_count] <= new_output_data;
            new_output_count <= new_output_count + 1;
        end
    end

    task send_spectrum_frame;
        input integer frame_number;
        integer beat;
        integer packed_lane;
        integer absolute_bin;
        begin
            for (beat = 0; beat < 64; beat = beat + 1) begin
                @(negedge clk);
                spectrum_data = 64'd0;
                for (packed_lane = 0; packed_lane < 4;
                     packed_lane = packed_lane + 1) begin
                    absolute_bin = beat * 4 + packed_lane;
                    spectrum_data[packed_lane*16 +: 8] =
                        spectrum_real_value(frame_number, absolute_bin);
                    spectrum_data[packed_lane*16 + 8 +: 8] =
                        spectrum_imag_value(frame_number, absolute_bin);
                end
                spectrum_last = (beat == 63);
                spectrum_valid = 1'b1;
                while (!(old_spectrum_ready && new_spectrum_ready))
                    @(negedge clk);
                @(posedge clk);
            end
            @(negedge clk);
            spectrum_valid = 1'b0;
            spectrum_last = 1'b0;
            spectrum_data = 64'd0;
            @(posedge clk);
        end
    endtask

    task pulse_frame_start;
        begin
            @(negedge clk);
            frame_start = 1'b1;
            @(posedge clk);
            @(negedge clk);
            frame_start = 1'b0;
        end
    endtask

    task launch_both;
        begin
            while (!(old_start_ready && new_start_ready))
                @(negedge clk);
            start = 1'b1;
            @(posedge clk);
            @(negedge clk);
            start = 1'b0;
        end
    endtask

    task wait_both_done;
        integer watchdog;
        reg old_seen;
        reg new_seen;
        begin
            watchdog = 0;
            old_seen = 1'b0;
            new_seen = 1'b0;
            while (!(old_seen && new_seen) && watchdog < 100000) begin
                @(posedge clk);
                if (old_done)
                    old_seen = 1'b1;
                if (new_done)
                    new_seen = 1'b1;
                watchdog = watchdog + 1;
            end
            check(old_seen && new_seen, "engine completion timeout");
        end
    endtask

    task drain_and_compare;
        integer watchdog;
        integer index;
        begin
            old_output_count = 0;
            new_output_count = 0;
            output_enable = 1'b1;
            watchdog = 0;
            while (((old_output_count < 256) || (new_output_count < 256))
                   && watchdog < 2000) begin
                @(posedge clk);
                watchdog = watchdog + 1;
            end
            check(old_output_count == 256, "legacy output count mismatch");
            check(new_output_count == 256, "hybrid output count mismatch");
            @(posedge clk);
            output_enable = 1'b0;
            mismatch_count = 0;
            for (index = 0; index < 256; index = index + 1) begin
                checks = checks + 1;
                if (old_results[index] !== new_results[index]) begin
                    mismatch_count = mismatch_count + 1;
                    if (mismatch_count <= 12) begin
                        $display("MISMATCH frame=%0d bin=%0d old=%016x new=%016x old_r=%0d old_i=%0d new_r=%0d new_i=%0d",
                                 current_frame_id, index,
                                 old_results[index], new_results[index],
                                 $signed(old_results[index][31:0]),
                                 $signed(old_results[index][63:32]),
                                 $signed(new_results[index][31:0]),
                                 $signed(new_results[index][63:32]));
                    end
                end
            end
            if (mismatch_count != 0)
                fail("legacy and hybrid DeepFilter results differ");
        end
    endtask

    task complete_frame;
        begin
            @(negedge clk);
            frame_done = 1'b1;
            @(posedge clk);
            @(negedge clk);
            frame_done = 1'b0;
            @(posedge clk);
        end
    endtask

    initial begin
        #20000000;
        fail("global simulation timeout");
    end

    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        for (frame_index = 0; frame_index < 5;
             frame_index = frame_index + 1) begin
            current_frame_id = frame_index[15:0];
            send_spectrum_frame(frame_index);
            pulse_frame_start();
            launch_both();
            wait_both_done();
            drain_and_compare();
            check(!old_error && !old_error_valid,
                  "legacy engine reported an error");
            check(!new_error && !new_error_valid && !cdf_protocol_error,
                  "hybrid engine reported an error");
            complete_frame();
        end

        $display("PASS tb_hybrid_pe_deepfilter_equivalence frames=5 checks=%0d",
                 checks);
        $finish;
    end
endmodule
