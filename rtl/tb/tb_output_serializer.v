`timescale 1ns/1ps

module tb_output_serializer;
    reg clk = 1'b0;
    reg rst;
    reg load;
    reg [63:0] parallel_data;
    wire output_valid;
    reg output_ready;
    wire [15:0] output_data;
    wire [1:0] output_index;
    wire output_last;
    wire busy;
    wire done;
    integer errors;
    integer received;
    reg [15:0] expected [0:3];

    always #5 clk = ~clk;

    output_serializer #(.LANES(4), .DATA_WIDTH(16), .INDEX_WIDTH(2)) dut (
        .clk(clk), .rst(rst), .load(load), .parallel_data(parallel_data),
        .output_valid(output_valid), .output_ready(output_ready),
        .output_data(output_data), .output_index(output_index), .output_last(output_last),
        .busy(busy), .done(done)
    );

    always @(posedge clk) begin
        if (output_valid && output_ready) begin
            if ((output_data !== expected[received]) || (output_index !== received[1:0])) begin
                $display("ERROR serializer item=%0d got data/index=%h/%0d expected=%h/%0d",
                         received, output_data, output_index, expected[received], received);
                errors = errors + 1;
            end
            if (output_last !== (received == 3)) begin
                $display("ERROR serializer last item=%0d last=%0d", received, output_last);
                errors = errors + 1;
            end
            received = received + 1;
        end
    end

    initial begin
        errors = 0; received = 0;
        expected[0] = 16'h1111; expected[1] = 16'h2222;
        expected[2] = 16'h3333; expected[3] = 16'h4444;
        rst = 1; load = 0; parallel_data = 0; output_ready = 1;
        repeat (2) @(posedge clk); @(negedge clk); rst = 0;
        @(negedge clk); parallel_data = 64'h4444_3333_2222_1111; load = 1;
        @(negedge clk); load = 0;
        wait (output_valid && output_index == 1);
        @(negedge clk); output_ready = 0;
        repeat (2) begin
            @(posedge clk); #1;
            if (output_data != 16'h2222 || output_index != 1) begin
                $display("ERROR serializer did not hold under backpressure");
                errors = errors + 1;
            end
        end
        @(negedge clk); output_ready = 1;
        wait (done); #1;
        if (received != 4) begin
            $display("ERROR serializer received=%0d expected=4", received);
            errors = errors + 1;
        end
        if (errors == 0) $display("PASS tb_output_serializer");
        else $fatal(1, "FAIL tb_output_serializer errors=%0d", errors);
        $finish;
    end
endmodule
