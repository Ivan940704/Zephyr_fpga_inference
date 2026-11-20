`timescale 1ns/1ps

module tb_layernorm_parameter_rom_q12;
    reg clk;
    reg rst_n;
    reg abort;
    reg [1:0] config_profile;
    wire [7:0] config_length;
    wire [31:0] config_output_reciprocal_q20;
    reg request_valid;
    wire request_ready;
    reg [1:0] request_profile;
    reg [7:0] request_index;
    wire response_valid;
    reg response_ready;
    wire signed [15:0] response_weight_q12;
    wire signed [15:0] response_bias_q12;
    wire response_error;

    integer vector_file;
    integer scan_count;
    integer expected_count;
    integer vector_count;
    integer profile_value;
    integer index_value;
    integer weight_value;
    integer bias_value;
    integer cycle_count;
    integer seed;
    reg [2047:0] vector_path;
    reg signed [15:0] held_weight;
    reg signed [15:0] held_bias;
    reg held_error;
    reg test_passed;

    layernorm_parameter_rom_q12 dut (
        .clk(clk),
        .rst_n(rst_n),
        .abort(abort),
        .config_profile(config_profile),
        .config_length(config_length),
        .config_output_reciprocal_q20(config_output_reciprocal_q20),
        .request_valid(request_valid),
        .request_ready(request_ready),
        .request_profile(request_profile),
        .request_index(request_index),
        .response_valid(response_valid),
        .response_ready(response_ready),
        .response_weight_q12(response_weight_q12),
        .response_bias_q12(response_bias_q12),
        .response_error(response_error)
    );

    always #4 clk = ~clk;

    task fail;
        input [1023:0] message;
        begin
            $display("LAYERNORM_PARAMETER_ROM_FAIL %0s", message);
            $finish;
        end
    endtask

    task check_config;
        input [1:0] profile;
        input [7:0] length;
        input [31:0] reciprocal;
        begin
            config_profile = profile;
            #1;
            if (config_length !== length ||
                config_output_reciprocal_q20 !== reciprocal)
                fail("profile configuration mismatch");
        end
    endtask

    task issue_and_check;
        input [1:0] profile;
        input [7:0] index;
        input signed [15:0] expected_weight;
        input signed [15:0] expected_bias;
        input expected_error;
        integer stall_cycles;
        begin
            @(negedge clk);
            request_profile = profile;
            request_index = index;
            request_valid = 1'b1;
            while (!request_ready)
                @(negedge clk);
            @(negedge clk);
            request_valid = 1'b0;

            while (!response_valid)
                @(negedge clk);
            held_weight = response_weight_q12;
            held_bias = response_bias_q12;
            held_error = response_error;
            stall_cycles = $random(seed) & 3;
            repeat (stall_cycles) begin
                response_ready = 1'b0;
                @(negedge clk);
                if (!response_valid || response_weight_q12 !== held_weight ||
                    response_bias_q12 !== held_bias ||
                    response_error !== held_error)
                    fail("response changed under backpressure");
            end
            response_ready = 1'b1;
            if (response_weight_q12 !== expected_weight ||
                response_bias_q12 !== expected_bias ||
                response_error !== expected_error)
                fail("parameter response mismatch");
            @(negedge clk);
            response_ready = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        abort = 1'b0;
        config_profile = 2'd0;
        request_valid = 1'b0;
        request_profile = 2'd0;
        request_index = 8'd0;
        response_ready = 1'b0;
        vector_count = 0;
        cycle_count = 0;
        seed = 32'h71a4e209;
        test_passed = 1'b0;

        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        check_config(2'd0, 8'd64, 32'd17789402);
        check_config(2'd1, 8'd46, 32'd26354903);
        check_config(2'd2, 8'd94, 32'd33864296);
        check_config(2'd3, 8'd158, 32'd50437752);

        if (!$value$plusargs("VECTOR_PATH=%s", vector_path))
            fail("missing VECTOR_PATH plusarg");
        vector_file = $fopen(vector_path, "r");
        if (vector_file == 0)
            fail("cannot open parameter vector file");
        scan_count = $fscanf(vector_file, "%d\n", expected_count);
        if (scan_count != 1 || expected_count != 362)
            fail("invalid parameter vector header");
        while (!$feof(vector_file) && vector_count < expected_count) begin
            scan_count = $fscanf(
                vector_file, "D %d %d %d %d\n",
                profile_value, index_value, weight_value, bias_value
            );
            if (scan_count != 4)
                fail("malformed parameter vector line");
            issue_and_check(
                profile_value[1:0], index_value[7:0],
                weight_value[15:0], bias_value[15:0], 1'b0
            );
            vector_count = vector_count + 1;
        end
        $fclose(vector_file);
        if (vector_count != expected_count)
            fail("parameter vector count mismatch");

        issue_and_check(2'd0, 8'd64, 16'sd0, 16'sd0, 1'b1);
        issue_and_check(2'd1, 8'd46, 16'sd0, 16'sd0, 1'b1);
        issue_and_check(2'd2, 8'd94, 16'sd0, 16'sd0, 1'b1);
        issue_and_check(2'd3, 8'd158, 16'sd0, 16'sd0, 1'b1);

        abort = 1'b1;
        @(negedge clk);
        abort = 1'b0;
        if (response_valid)
            fail("abort did not flush response state");
        test_passed = 1'b1;
        $display(
            "LAYERNORM_PARAMETER_ROM_XSIM_PASS entries=%0d cycles=%0d",
            vector_count, cycle_count
        );
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n)
            cycle_count <= cycle_count + 1;
        if (cycle_count > 10000)
            fail("simulation timeout");
    end
endmodule
