`timescale 1ns/1ps

module tb_layernorm_engine_q12;
    reg clk;
    reg rst_n;
    reg abort;
    reg config_valid;
    wire config_ready;
    reg [7:0] config_length;
    reg [31:0] config_output_reciprocal_q20;
    reg [31:0] config_epsilon_q24;
    reg input_valid;
    wire input_ready;
    reg signed [15:0] input_value_q12;
    reg signed [15:0] input_weight_q12;
    reg signed [15:0] input_bias_q12;
    reg input_last;
    wire output_valid;
    reg output_ready;
    wire signed [7:0] output_data;
    wire [7:0] output_index;
    wire output_last;
    wire busy;
    wire done;
    wire error;
    wire [7:0] error_code;
    wire [31:0] cycle_count;

    reg test_passed;
    integer failures;
    integer vector_file;
    integer scan_status;
    integer vector_count;
    integer vector_number;
    integer length_integer;
    integer reciprocal_integer;
    integer epsilon_integer;
    integer data_index;
    integer value_integer;
    integer weight_integer;
    integer bias_integer;
    integer expected_integer;
    integer observed_outputs;
    integer timeout_cycles;
    integer cycle_limit;
    integer marker;
    reg [2047:0] vector_path;
    reg signed [15:0] values [0:157];
    reg signed [15:0] weights [0:157];
    reg signed [15:0] biases [0:157];
    reg signed [7:0] expected [0:157];
    reg [15:0] lfsr_q;
    reg stalled_q;
    reg signed [7:0] stalled_data_q;
    reg [7:0] stalled_index_q;
    reg stalled_last_q;

    layernorm_engine_q12 #(
        .MAX_LENGTH(158)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .abort(abort),
        .config_valid(config_valid),
        .config_ready(config_ready),
        .config_length(config_length),
        .config_output_reciprocal_q20(config_output_reciprocal_q20),
        .config_epsilon_q24(config_epsilon_q24),
        .input_valid(input_valid),
        .input_ready(input_ready),
        .input_value_q12(input_value_q12),
        .input_weight_q12(input_weight_q12),
        .input_bias_q12(input_bias_q12),
        .input_last(input_last),
        .output_valid(output_valid),
        .output_ready(output_ready),
        .output_data(output_data),
        .output_index(output_index),
        .output_last(output_last),
        .busy(busy),
        .done(done),
        .error(error),
        .error_code(error_code),
        .cycle_count(cycle_count)
    );

    always #4 clk = ~clk;

    always @(posedge clk) begin
        if (!rst_n) begin
            lfsr_q <= 16'h1ace;
            stalled_q <= 1'b0;
        end else begin
            lfsr_q <= {lfsr_q[14:0],
                       lfsr_q[15] ^ lfsr_q[13] ^ lfsr_q[12] ^ lfsr_q[10]};
            if (output_valid && !output_ready) begin
                if (stalled_q &&
                    ((output_data !== stalled_data_q) ||
                     (output_index !== stalled_index_q) ||
                     (output_last !== stalled_last_q))) begin
                    $display("FAIL output changed under stall");
                    failures = failures + 1;
                end
                stalled_q <= 1'b1;
                stalled_data_q <= output_data;
                stalled_index_q <= output_index;
                stalled_last_q <= output_last;
            end else begin
                stalled_q <= 1'b0;
            end
        end
    end

    task fail;
        input [1023:0] message;
        begin
            $display("FAIL %0s", message);
            failures = failures + 1;
        end
    endtask

    task load_vector;
        integer load_index;
        begin
            scan_status = $fscanf(
                vector_file, "V %d %d %d\n",
                length_integer, reciprocal_integer, epsilon_integer
            );
            if (scan_status != 3)
                fail("could not read vector header");
            for (load_index = 0; load_index < length_integer;
                 load_index = load_index + 1) begin
                scan_status = $fscanf(
                    vector_file, "D %d %d %d %d\n",
                    value_integer, weight_integer, bias_integer,
                    expected_integer
                );
                if (scan_status != 4)
                    fail("could not read vector data");
                values[load_index] = value_integer;
                weights[load_index] = weight_integer;
                biases[load_index] = bias_integer;
                expected[load_index] = expected_integer;
            end
        end
    endtask

    task send_config;
        begin
            config_length = length_integer;
            config_output_reciprocal_q20 = reciprocal_integer;
            config_epsilon_q24 = epsilon_integer;
            @(negedge clk);
            config_valid = 1'b1;
            while (!config_ready)
                @(posedge clk);
            @(negedge clk);
            config_valid = 1'b0;
        end
    endtask

    task send_inputs;
        integer send_index;
        begin
            for (send_index = 0; send_index < length_integer;
                 send_index = send_index + 1) begin
                repeat (lfsr_q[1:0]) @(posedge clk);
                @(negedge clk);
                input_value_q12 = values[send_index];
                input_weight_q12 = weights[send_index];
                input_bias_q12 = biases[send_index];
                input_last = (send_index == length_integer - 1);
                input_valid = 1'b1;
                while (!input_ready)
                    @(posedge clk);
                @(negedge clk);
                input_valid = 1'b0;
            end
            input_last = 1'b0;
        end
    endtask

    task receive_outputs;
        begin
            observed_outputs = 0;
            timeout_cycles = 0;
            while ((observed_outputs < length_integer) &&
                   (timeout_cycles < 20000)) begin
                output_ready = lfsr_q[0] | lfsr_q[3];
                @(posedge clk);
                timeout_cycles = timeout_cycles + 1;
                if (output_valid && output_ready) begin
                    if (output_index !== observed_outputs[7:0]) begin
                        $display("FAIL index vector=%0d expected=%0d got=%0d",
                            vector_number, observed_outputs, output_index);
                        failures = failures + 1;
                    end
                    if ($signed(output_data) !==
                        $signed(expected[observed_outputs])) begin
                        $display("FAIL data vector=%0d index=%0d expected=%0d got=%0d",
                            vector_number, observed_outputs,
                            $signed(expected[observed_outputs]),
                            $signed(output_data));
                        failures = failures + 1;
                    end
                    if (output_last !==
                        (observed_outputs == length_integer - 1)) begin
                        $display("FAIL last vector=%0d index=%0d",
                            vector_number, observed_outputs);
                        failures = failures + 1;
                    end
                    observed_outputs = observed_outputs + 1;
                end
            end
            output_ready = 1'b0;
            if (observed_outputs != length_integer)
                fail("output timeout");
            @(posedge clk);
            if (error) begin
                $display("FAIL sticky error code=0x%02x", error_code);
                failures = failures + 1;
            end
            cycle_limit = 25 * length_integer + 280;
            if (cycle_count > cycle_limit) begin
                $display("FAIL cycle budget vector=%0d length=%0d cycles=%0d limit=%0d",
                    vector_number, length_integer, cycle_count, cycle_limit);
                failures = failures + 1;
            end
            $display("LAYER_NORM_VECTOR_PASS vector=%0d length=%0d cycles=%0d",
                vector_number, length_integer, cycle_count);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        abort = 1'b0;
        config_valid = 1'b0;
        config_length = 8'd0;
        config_output_reciprocal_q20 = 32'd0;
        config_epsilon_q24 = 32'd0;
        input_valid = 1'b0;
        input_value_q12 = 16'sd0;
        input_weight_q12 = 16'sd0;
        input_bias_q12 = 16'sd0;
        input_last = 1'b0;
        output_ready = 1'b0;
        failures = 0;
        test_passed = 1'b0;
        if (!$value$plusargs("VECTOR_PATH=%s", vector_path))
            vector_path = "layernorm_q12_vectors.txt";
        vector_file = $fopen(vector_path, "r");
        if (vector_file == 0) begin
            $display("FAIL could not open vectors: %0s", vector_path);
            $fatal(1);
        end
        scan_status = $fscanf(vector_file, "%d\n", vector_count);
        if (scan_status != 1 || vector_count < 1) begin
            $display("FAIL invalid vector count");
            $fatal(1);
        end

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        for (vector_number = 0; vector_number < vector_count;
             vector_number = vector_number + 1) begin
            load_vector();
            send_config();
            send_inputs();
            receive_outputs();
        end
        $fclose(vector_file);

        // Protocol fail-closed smoke: length zero is rejected and sticky.
        config_length = 8'd0;
        config_output_reciprocal_q20 = 32'd1;
        config_epsilon_q24 = 32'd168;
        @(negedge clk);
        config_valid = 1'b1;
        @(negedge clk);
        config_valid = 1'b0;
        @(posedge clk);
        if (!error || error_code != 8'h70)
            fail("invalid configuration did not latch ERR_CONFIG_LENGTH");

        if (failures == 0) begin
            test_passed = 1'b1;
            $display("LAYER_NORM_Q12_XSIM_PASS vectors=%0d", vector_count);
        end else begin
            $fatal(1, "LAYER_NORM_Q12_XSIM_FAIL failures=%0d", failures);
        end
        #20;
        $finish;
    end
endmodule
