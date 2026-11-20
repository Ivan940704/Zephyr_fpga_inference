`timescale 1ns/1ps

module tb_spike_indexer;
    reg clk = 1'b0;
    reg rst;
    reg start;
    reg [15:0] spike_vector;
    wire index_valid;
    reg index_ready;
    wire [3:0] index_value;
    wire [4:0] active_count;
    wire busy;
    wire done;
    integer errors;
    integer received;
    reg [3:0] expected [0:15];

    always #5 clk = ~clk;

    spike_indexer #(.VECTOR_WIDTH(16), .INDEX_WIDTH(4)) dut (
        .clk(clk), .rst(rst), .start(start), .spike_vector(spike_vector),
        .index_valid(index_valid), .index_ready(index_ready), .index_value(index_value),
        .active_count(active_count), .busy(busy), .done(done)
    );

    always @(posedge clk) begin
        if (index_valid && index_ready) begin
            if (index_value !== expected[received]) begin
                $display("ERROR spike_indexer item=%0d got=%0d expected=%0d",
                         received, index_value, expected[received]);
                errors = errors + 1;
            end
            received = received + 1;
        end
    end

    task launch;
        input [15:0] vector;
        begin
            @(negedge clk); spike_vector = vector; start = 1'b1;
            @(negedge clk); start = 1'b0;
        end
    endtask

    task wait_done_and_check;
        input integer expected_count;
        begin
            while (!done) @(posedge clk);
            #1;
            if ((received != expected_count) || (active_count != expected_count)) begin
                $display("ERROR spike_indexer count got received/count=%0d/%0d expected=%0d",
                         received, active_count, expected_count);
                errors = errors + 1;
            end
            @(posedge clk);
        end
    endtask

    initial begin
        errors = 0; received = 0;
        rst = 1'b1; start = 1'b0; spike_vector = 0; index_ready = 1'b1;
        repeat (2) @(posedge clk);
        @(negedge clk); rst = 1'b0;

        expected[0] = 4'd1; expected[1] = 4'd4; expected[2] = 4'd15;
        received = 0;
        launch(16'b1000_0000_0001_0010);
        wait (index_valid && index_value == 4'd1);
        @(negedge clk); index_ready = 1'b0;
        repeat (3) begin
            @(posedge clk); #1;
            if (!index_valid || index_value != 4'd1) begin
                $display("ERROR spike_indexer did not hold output under backpressure");
                errors = errors + 1;
            end
        end
        @(negedge clk); index_ready = 1'b1;
        wait_done_and_check(3);

        received = 0;
        launch(16'b0);
        wait_done_and_check(0);

        for (received = 0; received < 16; received = received + 1)
            expected[received] = received[3:0];
        received = 0;
        launch(16'hffff);
        wait_done_and_check(16);

        if (errors == 0) $display("PASS tb_spike_indexer");
        else $fatal(1, "FAIL tb_spike_indexer errors=%0d", errors);
        $finish;
    end
endmodule
