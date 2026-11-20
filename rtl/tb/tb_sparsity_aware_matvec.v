`timescale 1ns/1ps

module tb_sparsity_aware_matvec;
    localparam COLUMNS = 8;
    localparam ROWS = 8;
    localparam LANES = 4;
    localparam INDEX_WIDTH = 3;
    localparam TILE_WIDTH = 1;
    localparam ROW_TILES = ROWS / LANES;

    reg clk = 1'b0;
    reg rst;
    reg start;
    reg [COLUMNS-1:0] spike_vector;

    wire weight_req_valid;
    reg weight_req_ready;
    wire [INDEX_WIDTH-1:0] weight_column;
    wire [TILE_WIDTH-1:0] weight_tile;
    reg weight_rsp_valid;
    wire weight_rsp_ready;
    reg [LANES*8-1:0] weight_rsp_data;

    wire result_valid;
    reg result_ready;
    wire [TILE_WIDTH-1:0] result_tile;
    wire [LANES*32-1:0] result_data;
    wire [INDEX_WIDTH:0] active_count;
    wire [31:0] memory_read_count;
    wire busy;
    wire done;

    reg signed [7:0] weights [0:ROWS-1][0:COLUMNS-1];
    integer expected [0:ROWS-1];
    integer observed [0:ROWS-1];
    integer errors;
    integer request_count;
    integer received_tiles;
    integer cycle_count;
    integer response_delay;
    integer request_stall_cycles;
    reg [COLUMNS-1:0] accessed_columns;
    reg response_pending;
    reg [INDEX_WIDTH-1:0] pending_column;
    reg [TILE_WIDTH-1:0] pending_tile;
    reg request_stalled;
    reg [INDEX_WIDTH-1:0] held_request_column;
    reg [TILE_WIDTH-1:0] held_request_tile;

    always #5 clk = ~clk;

    sparsity_aware_matvec #(
        .COLUMNS(COLUMNS),
        .ROWS(ROWS),
        .LANES(LANES),
        .INDEX_WIDTH(INDEX_WIDTH),
        .TILE_WIDTH(TILE_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .spike_vector(spike_vector),
        .weight_req_valid(weight_req_valid),
        .weight_req_ready(weight_req_ready),
        .weight_column(weight_column),
        .weight_tile(weight_tile),
        .weight_rsp_valid(weight_rsp_valid),
        .weight_rsp_ready(weight_rsp_ready),
        .weight_rsp_data(weight_rsp_data),
        .result_valid(result_valid),
        .result_ready(result_ready),
        .result_tile(result_tile),
        .result_data(result_data),
        .active_count(active_count),
        .memory_read_count(memory_read_count),
        .busy(busy),
        .done(done)
    );

    function [LANES*8-1:0] make_weight_word;
        input [INDEX_WIDTH-1:0] column;
        input [TILE_WIDTH-1:0] tile;
        integer lane;
        integer row;
        begin
            make_weight_word = {(LANES*8){1'b0}};
            for (lane = 0; lane < LANES; lane = lane + 1) begin
                row = tile * LANES + lane;
                make_weight_word[lane*8 +: 8] = weights[row][column];
            end
        end
    endfunction

    // One-outstanding-request memory model.  req_ready is periodically low to
    // prove that the selected column/tile address remains stable under stalls.
    always @(posedge clk) begin
        if (rst) begin
            weight_req_ready <= 1'b0;
            weight_rsp_valid <= 1'b0;
            weight_rsp_data <= {(LANES*8){1'b0}};
            response_pending <= 1'b0;
            pending_column <= {INDEX_WIDTH{1'b0}};
            pending_tile <= {TILE_WIDTH{1'b0}};
            response_delay <= 0;
            request_count = 0;
            accessed_columns = {COLUMNS{1'b0}};
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            weight_req_ready <= !response_pending && !weight_rsp_valid &&
                                (cycle_count[1:0] != 2'd1);

            if (weight_rsp_valid && weight_rsp_ready)
                weight_rsp_valid <= 1'b0;

            if (weight_req_valid && weight_req_ready) begin
                response_pending <= 1'b1;
                pending_column <= weight_column;
                pending_tile <= weight_tile;
                response_delay <= request_count[0];
                request_count = request_count + 1;
                accessed_columns[weight_column] = 1'b1;
            end

            if (response_pending) begin
                if (response_delay == 0 && !weight_rsp_valid) begin
                    weight_rsp_data <= make_weight_word(pending_column, pending_tile);
                    weight_rsp_valid <= 1'b1;
                    response_pending <= 1'b0;
                end else if (response_delay != 0) begin
                    response_delay <= response_delay - 1;
                end
            end
        end
    end

    // Request-address stability check.
    always @(posedge clk) begin
        if (rst) begin
            request_stalled <= 1'b0;
            request_stall_cycles = 0;
            held_request_column <= {INDEX_WIDTH{1'b0}};
            held_request_tile <= {TILE_WIDTH{1'b0}};
        end else if (weight_req_valid && !weight_req_ready) begin
            request_stall_cycles = request_stall_cycles + 1;
            if (request_stalled &&
                ((weight_column !== held_request_column) ||
                 (weight_tile !== held_request_tile))) begin
                $display("ERROR sparse_matvec request changed while stalled");
                errors = errors + 1;
            end
            request_stalled <= 1'b1;
            held_request_column <= weight_column;
            held_request_tile <= weight_tile;
        end else begin
            request_stalled <= 1'b0;
        end
    end

    always @(posedge clk) begin
        integer lane;
        integer row;
        if (rst) begin
            received_tiles = 0;
        end else if (result_valid && result_ready) begin
            for (lane = 0; lane < LANES; lane = lane + 1) begin
                row = result_tile * LANES + lane;
                observed[row] = $signed(result_data[lane*32 +: 32]);
            end
            received_tiles = received_tiles + 1;
        end
    end

    task initialize_weights;
        integer row;
        integer column;
        begin
            for (column = 0; column < COLUMNS; column = column + 1) begin
                weights[0][column] = column + 1;
                weights[1][column] = -(column + 1);
                weights[2][column] = 10 * (column + 1);
                weights[3][column] = -10 * (column + 1);
                weights[4][column] = 2 * (column + 1);
                weights[5][column] = 3 * (column + 1);
                weights[6][column] = -2 * (column + 1);
                if (column[0])
                    weights[7][column] = -((column + 2) / 2);
                else
                    weights[7][column] = (column + 2) / 2;
            end
            for (row = 0; row < ROWS; row = row + 1) begin
                expected[row] = 0;
                observed[row] = 0;
            end
        end
    endtask

    task build_dense_reference;
        input [COLUMNS-1:0] vector;
        integer row;
        integer column;
        begin
            for (row = 0; row < ROWS; row = row + 1) begin
                expected[row] = 0;
                observed[row] = 0;
                for (column = 0; column < COLUMNS; column = column + 1)
                    if (vector[column])
                        expected[row] = expected[row] + $signed(weights[row][column]);
            end
        end
    endtask

    task run_case;
        input [COLUMNS-1:0] vector;
        input integer expected_active;
        input integer stall_first_result;
        integer row;
        integer hold_cycle;
        integer expected_reads;
        reg [LANES*32-1:0] held_result_data;
        reg [TILE_WIDTH-1:0] held_result_tile;
        begin
            build_dense_reference(vector);
            expected_reads = expected_active * ROW_TILES;

            @(negedge clk);
            rst = 1'b1;
            start = 1'b0;
            spike_vector = {COLUMNS{1'b0}};
            result_ready = 1'b1;
            repeat (2) @(posedge clk);
            @(negedge clk);
            rst = 1'b0;
            spike_vector = vector;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            if (stall_first_result) begin
                wait (result_valid);
                @(negedge clk);
                result_ready = 1'b0;
                held_result_data = result_data;
                held_result_tile = result_tile;
                for (hold_cycle = 0; hold_cycle < 3; hold_cycle = hold_cycle + 1) begin
                    @(posedge clk);
                    #1;
                    if (!result_valid || result_data !== held_result_data ||
                        result_tile !== held_result_tile) begin
                        $display("ERROR sparse_matvec result changed while stalled");
                        errors = errors + 1;
                    end
                end
                @(negedge clk);
                result_ready = 1'b1;
            end

            wait (done);
            #1;
            for (row = 0; row < ROWS; row = row + 1) begin
                if (observed[row] !== expected[row]) begin
                    $display("ERROR sparse_matvec vector=%b row=%0d got=%0d expected=%0d",
                             vector, row, observed[row], expected[row]);
                    errors = errors + 1;
                end
            end
            if (active_count != expected_active) begin
                $display("ERROR sparse_matvec active_count got=%0d expected=%0d",
                         active_count, expected_active);
                errors = errors + 1;
            end
            if ((memory_read_count != expected_reads) ||
                (request_count != expected_reads)) begin
                $display("ERROR sparse_matvec reads got dut/tb=%0d/%0d expected=%0d",
                         memory_read_count, request_count, expected_reads);
                errors = errors + 1;
            end
            if (accessed_columns !== vector) begin
                $display("ERROR sparse_matvec accessed columns got=%b expected=%b",
                         accessed_columns, vector);
                errors = errors + 1;
            end
            if (received_tiles != ROW_TILES) begin
                $display("ERROR sparse_matvec received tiles got=%0d expected=%0d",
                         received_tiles, ROW_TILES);
                errors = errors + 1;
            end
            if ((expected_reads != 0) && (request_stall_cycles == 0)) begin
                $display("ERROR sparse_matvec did not exercise request backpressure");
                errors = errors + 1;
            end
            $display("SPARSE_CASE vector=%b active=%0d reads=%0d dense_reads=%0d",
                     vector, expected_active, expected_reads, COLUMNS * ROW_TILES);
            @(posedge clk);
        end
    endtask

    initial begin
        errors = 0;
        rst = 1'b1;
        start = 1'b0;
        spike_vector = {COLUMNS{1'b0}};
        result_ready = 1'b1;
        initialize_weights();

        run_case(8'b0000_0000, 0, 1);
        run_case(8'b0100_0010, 2, 1);
        run_case(8'b1010_0101, 4, 0);
        run_case(8'b1111_1111, 8, 0);

        if (errors == 0) $display("PASS tb_sparsity_aware_matvec");
        else $fatal(1, "FAIL tb_sparsity_aware_matvec errors=%0d", errors);
        $finish;
    end
endmodule
