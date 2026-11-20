`timescale 1ns/1ps

module tb_realtime_layernorm_coordinator;
    reg clk;
    reg rst_n;
    reg abort;
    reg [15:0] current_frame_id;
    reg frame_done;
    reg s_axis_magnitude_tvalid;
    wire s_axis_magnitude_tready;
    reg [63:0] s_axis_magnitude_tdata;
    reg [7:0] s_axis_magnitude_tkeep;
    reg s_axis_magnitude_tlast;
    wire m_axis_fullband_tvalid;
    reg m_axis_fullband_tready;
    wire [63:0] m_axis_fullband_tdata;
    wire [7:0] m_axis_fullband_tkeep;
    wire m_axis_fullband_tlast;
    reg fb_projection_start;
    reg fb_coefficient_valid;
    wire fb_coefficient_ready;
    reg signed [7:0] fb_coefficient_value;
    reg [8:0] fb_coefficient_index;
    reg fb_coefficient_last;
    wire subbands_valid;
    reg subbands_ready;
    wire sb_buffer_valid;
    reg sb_read_valid;
    wire sb_read_ready;
    reg [9:0] sb_read_index;
    reg [15:0] sb_read_frame_id;
    wire sb_read_rsp_valid;
    reg sb_read_rsp_ready;
    wire signed [7:0] sb_read_rsp_data;
    wire sb_read_rsp_error;
    wire magnitude_buffer_valid;
    wire [15:0] magnitude_buffer_frame_id;
    wire busy;
    wire quiescent;
    wire [3:0] state_debug;
    wire [31:0] last_frame_cycle_count;
    wire error_valid;
    wire [7:0] error_code;
    wire [31:0] error_detail;

    reg signed [15:0] magnitude_vector [0:255];
    reg signed [7:0] expected_fullband [0:63];
    reg signed [7:0] projection_vector [0:63];
    reg signed [7:0] expected_subbands [0:781];
    reg [2047:0] vector_path;
    integer vector_file;
    integer scan_count;
    integer frame_count;
    integer saved_frame_index;
    integer temporary_value;
    integer frame_number;
    integer beat;
    integer lane;
    integer index;
    integer global_cycles;
    reg test_passed;

    realtime_layernorm_coordinator dut (
        .clk(clk),
        .rst_n(rst_n),
        .abort(abort),
        .current_frame_id(current_frame_id),
        .frame_done(frame_done),
        .s_axis_magnitude_tvalid(s_axis_magnitude_tvalid),
        .s_axis_magnitude_tready(s_axis_magnitude_tready),
        .s_axis_magnitude_tdata(s_axis_magnitude_tdata),
        .s_axis_magnitude_tkeep(s_axis_magnitude_tkeep),
        .s_axis_magnitude_tlast(s_axis_magnitude_tlast),
        .m_axis_fullband_tvalid(m_axis_fullband_tvalid),
        .m_axis_fullband_tready(m_axis_fullband_tready),
        .m_axis_fullband_tdata(m_axis_fullband_tdata),
        .m_axis_fullband_tkeep(m_axis_fullband_tkeep),
        .m_axis_fullband_tlast(m_axis_fullband_tlast),
        .fb_projection_start(fb_projection_start),
        .fb_coefficient_valid(fb_coefficient_valid),
        .fb_coefficient_ready(fb_coefficient_ready),
        .fb_coefficient_value(fb_coefficient_value),
        .fb_coefficient_index(fb_coefficient_index),
        .fb_coefficient_last(fb_coefficient_last),
        .subbands_valid(subbands_valid),
        .subbands_ready(subbands_ready),
        .sb_buffer_valid(sb_buffer_valid),
        .sb_read_valid(sb_read_valid),
        .sb_read_ready(sb_read_ready),
        .sb_read_index(sb_read_index),
        .sb_read_frame_id(sb_read_frame_id),
        .sb_read_rsp_valid(sb_read_rsp_valid),
        .sb_read_rsp_ready(sb_read_rsp_ready),
        .sb_read_rsp_data(sb_read_rsp_data),
        .sb_read_rsp_error(sb_read_rsp_error),
        .magnitude_buffer_valid(magnitude_buffer_valid),
        .magnitude_buffer_frame_id(magnitude_buffer_frame_id),
        .busy(busy),
        .quiescent(quiescent),
        .state_debug(state_debug),
        .last_frame_cycle_count(last_frame_cycle_count),
        .error_valid(error_valid),
        .error_code(error_code),
        .error_detail(error_detail)
    );

    always #4 clk = ~clk;

    task fail;
        input [2047:0] message;
        begin
            $display(
                "REALTIME_COORDINATOR_FAIL frame=%0d state=%0d code=%02x detail=%08x %0s",
                frame_number, state_debug, error_code, error_detail, message
            );
            $finish;
        end
    endtask

    task read_frame_vectors;
        begin
            scan_count = $fscanf(vector_file, "%d", saved_frame_index);
            if (scan_count != 1)
                fail("missing saved frame index");
            for (index = 0; index < 256; index = index + 1) begin
                scan_count = $fscanf(vector_file, "%d", temporary_value);
                if (scan_count != 1)
                    fail("malformed magnitude vector");
                magnitude_vector[index] = temporary_value[15:0];
            end
            for (index = 0; index < 64; index = index + 1) begin
                scan_count = $fscanf(vector_file, "%d", temporary_value);
                if (scan_count != 1)
                    fail("malformed fullband vector");
                expected_fullband[index] = temporary_value[7:0];
            end
            for (index = 0; index < 64; index = index + 1) begin
                scan_count = $fscanf(vector_file, "%d", temporary_value);
                if (scan_count != 1)
                    fail("malformed projection vector");
                projection_vector[index] = temporary_value[7:0];
            end
            for (index = 0; index < 782; index = index + 1) begin
                scan_count = $fscanf(vector_file, "%d", temporary_value);
                if (scan_count != 1)
                    fail("malformed subband vector");
                expected_subbands[index] = temporary_value[7:0];
            end
        end
    endtask

    task send_magnitude;
        begin
            for (beat = 0; beat < 64; beat = beat + 1) begin
                while (!s_axis_magnitude_tready)
                    @(negedge clk);
                @(negedge clk);
                for (lane = 0; lane < 4; lane = lane + 1)
                    s_axis_magnitude_tdata[lane*16 +: 16] =
                        magnitude_vector[beat*4 + lane];
                s_axis_magnitude_tvalid = 1'b1;
                s_axis_magnitude_tlast = (beat == 63);
                @(posedge clk);
                @(negedge clk);
                s_axis_magnitude_tvalid = 1'b0;
                s_axis_magnitude_tlast = 1'b0;
            end
        end
    endtask

    task receive_fullband;
        begin
            m_axis_fullband_tready = 1'b1;
            for (beat = 0; beat < 8; beat = beat + 1) begin
                while (!m_axis_fullband_tvalid)
                    @(negedge clk);
                if (m_axis_fullband_tkeep !== 8'hff ||
                    m_axis_fullband_tlast !== (beat == 7))
                    fail("fullband AXIS framing mismatch");
                for (lane = 0; lane < 8; lane = lane + 1) begin
                    if ($signed(m_axis_fullband_tdata[lane*8 +: 8]) !==
                        expected_fullband[beat*8 + lane])
                        fail("fullband LayerNorm mismatch");
                end
                @(posedge clk);
                @(negedge clk);
            end
            m_axis_fullband_tready = 1'b0;
        end
    endtask

    task send_projection;
        begin
            @(negedge clk);
            fb_projection_start = 1'b1;
            @(posedge clk);
            @(negedge clk);
            fb_projection_start = 1'b0;
            for (index = 0; index < 64; index = index + 1) begin
                while (!fb_coefficient_ready)
                    @(negedge clk);
                fb_coefficient_value = projection_vector[index];
                fb_coefficient_index = index[8:0];
                fb_coefficient_last = (index == 63);
                fb_coefficient_valid = 1'b1;
                @(posedge clk);
                @(negedge clk);
                fb_coefficient_valid = 1'b0;
                fb_coefficient_last = 1'b0;
            end
        end
    endtask

    task claim_and_check_subbands;
        begin
            while (!subbands_valid)
                @(negedge clk);
            if (!sb_buffer_valid)
                fail("subband valid asserted without local buffer");
            subbands_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            subbands_ready = 1'b0;

            for (index = 0; index < 782; index = index + 1) begin
                while (!sb_read_ready)
                    @(negedge clk);
                sb_read_index = index[9:0];
                sb_read_frame_id = current_frame_id;
                sb_read_valid = 1'b1;
                @(posedge clk);
                @(negedge clk);
                sb_read_valid = 1'b0;
                while (!sb_read_rsp_valid)
                    @(negedge clk);
                if (sb_read_rsp_error ||
                    sb_read_rsp_data !== expected_subbands[index])
                    fail("subband LayerNorm mismatch");
                if ((index & 7) == 3)
                    repeat (2) @(negedge clk);
                sb_read_rsp_ready = 1'b1;
                @(posedge clk);
                @(negedge clk);
                sb_read_rsp_ready = 1'b0;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        abort = 1'b0;
        current_frame_id = 16'd0;
        frame_done = 1'b0;
        s_axis_magnitude_tvalid = 1'b0;
        s_axis_magnitude_tdata = 64'd0;
        s_axis_magnitude_tkeep = 8'hff;
        s_axis_magnitude_tlast = 1'b0;
        m_axis_fullband_tready = 1'b0;
        fb_projection_start = 1'b0;
        fb_coefficient_valid = 1'b0;
        fb_coefficient_value = 8'sd0;
        fb_coefficient_index = 9'd0;
        fb_coefficient_last = 1'b0;
        subbands_ready = 1'b0;
        sb_read_valid = 1'b0;
        sb_read_index = 10'd0;
        sb_read_frame_id = 16'd0;
        sb_read_rsp_ready = 1'b0;
        frame_number = 0;
        global_cycles = 0;
        test_passed = 1'b0;

        if (!$value$plusargs("VECTOR_PATH=%s", vector_path))
            fail("missing VECTOR_PATH plusarg");
        vector_file = $fopen(vector_path, "r");
        if (vector_file == 0)
            fail("cannot open coordinator vector file");
        scan_count = $fscanf(vector_file, "%d", frame_count);
        if (scan_count != 1 || frame_count < 1)
            fail("invalid coordinator vector header");

        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);
        if (!quiescent)
            fail("coordinator not quiescent after reset");

        for (frame_number = 0; frame_number < frame_count;
             frame_number = frame_number + 1) begin
            read_frame_vectors();
            current_frame_id = frame_number[15:0];
            send_magnitude();
            receive_fullband();
            if (!magnitude_buffer_valid ||
                magnitude_buffer_frame_id != current_frame_id)
                fail("magnitude ownership mismatch");
            send_projection();
            claim_and_check_subbands();
            $display(
                "REALTIME_COORDINATOR_FRAME_PASS frame=%0d saved=%0d cycles=%0d",
                frame_number, saved_frame_index, last_frame_cycle_count
            );
            frame_done = 1'b1;
            @(posedge clk);
            @(negedge clk);
            frame_done = 1'b0;
            repeat (2) @(negedge clk);
            if (!quiescent || magnitude_buffer_valid || sb_buffer_valid)
                fail("frame retirement did not return to quiescent ingress");
        end
        $fclose(vector_file);
        test_passed = 1'b1;
        $display("REALTIME_COORDINATOR_XSIM_PASS frames=%0d", frame_count);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n)
            global_cycles <= global_cycles + 1;
        if (error_valid)
            fail("coordinator reported a sticky error");
        if (global_cycles > 300000)
            fail("simulation timeout");
    end
endmodule
