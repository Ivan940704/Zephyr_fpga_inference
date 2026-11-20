`timescale 1ns/1ps

// Presentation-scale stress test for indexed-column binary-spike execution.
//
// These deterministic profiles approximate silence, scattered firing,
// contiguous bursts, and temporal correlation.  They are intentionally not
// described as measured model traces because the repository does not contain
// representative audio or an exported per-frame spike trace.
module tb_sparsity_aware_matvec_realistic;
    localparam COLUMNS = 320;
    localparam ROWS = 320;
    localparam LANES = 16;
    localparam INDEX_WIDTH = 9;
    localparam TILE_WIDTH = 5;
    localparam ROW_TILES = ROWS / LANES;
    localparam ADDRESS_COUNT = COLUMNS * ROW_TILES;
    localparam MAX_FRAME_CYCLES = 200000;

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
    integer column_reads [0:COLUMNS-1];

    integer errors;
    integer frames_checked;
    integer global_cycle;
    integer request_count;
    integer received_tiles;
    integer request_stall_cycles;
    integer result_stall_cycles;
    integer response_delay;
    integer request_address;
    integer duplicate_addresses;
    integer invalid_requests;

    reg frame_active;
    reg response_pending;
    reg [INDEX_WIDTH-1:0] pending_column;
    reg [TILE_WIDTH-1:0] pending_tile;
    reg [15:0] latency_lfsr;
    reg [ADDRESS_COUNT-1:0] address_seen;
    reg [COLUMNS-1:0] accessed_columns;
    reg [ROW_TILES-1:0] result_tile_seen;

    reg request_stalled;
    reg [INDEX_WIDTH-1:0] held_request_column;
    reg [TILE_WIDTH-1:0] held_request_tile;
    reg result_stalled;
    reg [TILE_WIDTH-1:0] held_result_tile;
    reg [LANES*32-1:0] held_result_data;

    reg [COLUMNS-1:0] pattern;
    reg [COLUMNS-1:0] correlated_base;
    reg [COLUMNS-1:0] previous_vector;
    reg previous_valid;

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

    // One-outstanding-request memory model.  It deliberately combines
    // periodic request stalls with a repeatable 0..3-cycle response delay.
    always @(posedge clk) begin
        if (rst) begin
            weight_req_ready <= 1'b0;
            weight_rsp_valid <= 1'b0;
            weight_rsp_data <= {(LANES*8){1'b0}};
            response_pending <= 1'b0;
            pending_column <= {INDEX_WIDTH{1'b0}};
            pending_tile <= {TILE_WIDTH{1'b0}};
            response_delay <= 0;
            latency_lfsr <= 16'h1ace;
            global_cycle <= 0;
        end else begin
            global_cycle <= global_cycle + 1;
            latency_lfsr <= {latency_lfsr[14:0],
                             latency_lfsr[15] ^ latency_lfsr[13] ^
                             latency_lfsr[12] ^ latency_lfsr[10]};

            weight_req_ready <= !response_pending && !weight_rsp_valid &&
                                ((global_cycle % 7) != 2) &&
                                ((global_cycle % 11) != 5);

            if (weight_rsp_valid && weight_rsp_ready)
                weight_rsp_valid <= 1'b0;

            if (weight_req_valid && weight_req_ready) begin
                response_pending <= 1'b1;
                pending_column <= weight_column;
                pending_tile <= weight_tile;
                response_delay <= latency_lfsr[1:0];

                if (frame_active) begin
                    request_count = request_count + 1;
                    if ((weight_column >= COLUMNS) || (weight_tile >= ROW_TILES)) begin
                        $display("ERROR realistic_sparse invalid request column=%0d tile=%0d",
                                 weight_column, weight_tile);
                        invalid_requests = invalid_requests + 1;
                        errors = errors + 1;
                    end else begin
                        request_address = weight_column * ROW_TILES + weight_tile;
                        if (!spike_vector[weight_column]) begin
                            $display("ERROR realistic_sparse read inactive column=%0d tile=%0d",
                                     weight_column, weight_tile);
                            invalid_requests = invalid_requests + 1;
                            errors = errors + 1;
                        end
                        if (address_seen[request_address]) begin
                            $display("ERROR realistic_sparse duplicate request column=%0d tile=%0d",
                                     weight_column, weight_tile);
                            duplicate_addresses = duplicate_addresses + 1;
                            errors = errors + 1;
                        end
                        address_seen[request_address] = 1'b1;
                        accessed_columns[weight_column] = 1'b1;
                        column_reads[weight_column] = column_reads[weight_column] + 1;
                    end
                end
            end

            if (response_pending) begin
                if ((response_delay == 0) && !weight_rsp_valid) begin
                    weight_rsp_data <= make_weight_word(pending_column, pending_tile);
                    weight_rsp_valid <= 1'b1;
                    response_pending <= 1'b0;
                end else if (response_delay != 0) begin
                    response_delay <= response_delay - 1;
                end
            end
        end
    end

    // Result consumer stalls for two adjacent cycles in each 13-cycle window.
    always @(posedge clk) begin
        if (rst)
            result_ready <= 1'b0;
        else if (!frame_active)
            result_ready <= 1'b1;
        else
            result_ready <= ((global_cycle % 13) != 6) &&
                            ((global_cycle % 13) != 7);
    end

    // Ready/valid protocol monitors for both DUT output interfaces.
    always @(posedge clk) begin
        if (rst) begin
            request_stalled <= 1'b0;
            held_request_column <= {INDEX_WIDTH{1'b0}};
            held_request_tile <= {TILE_WIDTH{1'b0}};
            result_stalled <= 1'b0;
            held_result_tile <= {TILE_WIDTH{1'b0}};
            held_result_data <= {(LANES*32){1'b0}};
        end else begin
            if (frame_active && weight_req_valid && !weight_req_ready) begin
                request_stall_cycles = request_stall_cycles + 1;
                if (request_stalled &&
                    ((weight_column !== held_request_column) ||
                     (weight_tile !== held_request_tile))) begin
                    $display("ERROR realistic_sparse request changed while stalled");
                    errors = errors + 1;
                end
                request_stalled <= 1'b1;
                held_request_column <= weight_column;
                held_request_tile <= weight_tile;
            end else begin
                request_stalled <= 1'b0;
            end

            if (frame_active && result_valid && !result_ready) begin
                result_stall_cycles = result_stall_cycles + 1;
                if (result_stalled &&
                    ((result_tile !== held_result_tile) ||
                     (result_data !== held_result_data))) begin
                    $display("ERROR realistic_sparse result changed while stalled");
                    errors = errors + 1;
                end
                result_stalled <= 1'b1;
                held_result_tile <= result_tile;
                held_result_data <= result_data;
            end else begin
                result_stalled <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        integer lane;
        integer row;
        if (!rst && frame_active && result_valid && result_ready) begin
            if (result_tile >= ROW_TILES) begin
                $display("ERROR realistic_sparse invalid result tile=%0d", result_tile);
                errors = errors + 1;
            end else begin
                if (result_tile_seen[result_tile]) begin
                    $display("ERROR realistic_sparse duplicate result tile=%0d", result_tile);
                    errors = errors + 1;
                end
                result_tile_seen[result_tile] = 1'b1;
                for (lane = 0; lane < LANES; lane = lane + 1) begin
                    row = result_tile * LANES + lane;
                    observed[row] = $signed(result_data[lane*32 +: 32]);
                end
                received_tiles = received_tiles + 1;
            end
        end
    end

    task initialize_weights;
        integer row;
        integer column;
        integer mixed;
        begin
            // Signed INT8 matrix spanning -127..127.  The nontrivial row/column
            // coupling makes incorrect column or lane selection easy to detect.
            for (row = 0; row < ROWS; row = row + 1) begin
                for (column = 0; column < COLUMNS; column = column + 1) begin
                    mixed = (row * 73 + column * 151 +
                             ((row * column) % 257) * 19 + 23) % 255;
                    weights[row][column] = mixed - 127;
                    expected[row] = 0;
                    observed[row] = 0;
                end
            end
        end
    endtask

    task make_scattered;
        output [COLUMNS-1:0] vector;
        input integer count;
        input integer offset;
        input integer stride;
        integer index;
        integer column;
        begin
            vector = {COLUMNS{1'b0}};
            for (index = 0; index < count; index = index + 1) begin
                column = (offset + index * stride) % COLUMNS;
                vector[column] = 1'b1;
            end
        end
    endtask

    task make_cluster;
        output [COLUMNS-1:0] vector;
        input integer count;
        input integer first_column;
        integer index;
        integer column;
        begin
            vector = {COLUMNS{1'b0}};
            for (index = 0; index < count; index = index + 1) begin
                column = (first_column + index) % COLUMNS;
                vector[column] = 1'b1;
            end
        end
    endtask

    task make_correlated_churn;
        output [COLUMNS-1:0] vector;
        input [COLUMNS-1:0] base;
        input integer replace_count;
        integer column;
        integer removed;
        integer added;
        integer candidate;
        integer guard;
        begin
            vector = base;
            removed = 0;
            for (column = 0; column < COLUMNS; column = column + 1) begin
                if (base[column] && (removed < replace_count)) begin
                    vector[column] = 1'b0;
                    removed = removed + 1;
                end
            end

            added = 0;
            candidate = 211;
            guard = 0;
            while ((added < replace_count) && (guard < COLUMNS * 2)) begin
                if (!base[candidate] && !vector[candidate]) begin
                    vector[candidate] = 1'b1;
                    added = added + 1;
                end
                candidate = (candidate + 29) % COLUMNS;
                guard = guard + 1;
            end
            if ((removed != replace_count) || (added != replace_count)) begin
                $display("ERROR realistic_sparse could not build correlated vector");
                errors = errors + 1;
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
                observed[row] = 32'h5a5a5a5a;
                for (column = 0; column < COLUMNS; column = column + 1) begin
                    if (vector[column])
                        expected[row] = expected[row] + $signed(weights[row][column]);
                end
            end
        end
    endtask

    task run_frame;
        input [8*32-1:0] profile_name;
        input [COLUMNS-1:0] vector;
        input integer expected_active;
        integer row;
        integer column;
        integer tile;
        integer expected_reads;
        integer timeout_cycles;
        integer start_cycle;
        integer frame_cycles;
        integer overlap_count;
        integer changed_bits;
        integer errors_before;
        begin
            build_dense_reference(vector);
            expected_reads = expected_active * ROW_TILES;
            overlap_count = 0;
            changed_bits = 0;
            if (previous_valid) begin
                for (column = 0; column < COLUMNS; column = column + 1) begin
                    if (vector[column] && previous_vector[column])
                        overlap_count = overlap_count + 1;
                    if (vector[column] != previous_vector[column])
                        changed_bits = changed_bits + 1;
                end
            end else begin
                overlap_count = -1;
                changed_bits = -1;
            end

            @(negedge clk);
            if (busy || response_pending || weight_rsp_valid) begin
                $display("ERROR realistic_sparse frame started before interfaces were idle");
                errors = errors + 1;
            end
            request_count = 0;
            received_tiles = 0;
            request_stall_cycles = 0;
            result_stall_cycles = 0;
            duplicate_addresses = 0;
            invalid_requests = 0;
            accessed_columns = {COLUMNS{1'b0}};
            address_seen = {ADDRESS_COUNT{1'b0}};
            result_tile_seen = {ROW_TILES{1'b0}};
            for (column = 0; column < COLUMNS; column = column + 1)
                column_reads[column] = 0;

            spike_vector = vector;
            frame_active = 1'b1;
            start = 1'b1;
            start_cycle = global_cycle;
            errors_before = errors;
            @(negedge clk);
            start = 1'b0;

            timeout_cycles = 0;
            while (!done && (timeout_cycles < MAX_FRAME_CYCLES)) begin
                @(posedge clk);
                #1;
                timeout_cycles = timeout_cycles + 1;
            end
            if (!done) begin
                $fatal(1, "FAIL realistic_sparse profile=%0s timed out", profile_name);
            end
            frame_cycles = global_cycle - start_cycle;
            frame_active = 1'b0;
            #1;

            for (row = 0; row < ROWS; row = row + 1) begin
                if (observed[row] !== expected[row]) begin
                    if ((errors - errors_before) < 8)
                        $display("ERROR realistic_sparse profile=%0s row=%0d got=%0d expected=%0d",
                                 profile_name, row, observed[row], expected[row]);
                    errors = errors + 1;
                end
            end

            if (active_count != expected_active) begin
                $display("ERROR realistic_sparse profile=%0s active got=%0d expected=%0d",
                         profile_name, active_count, expected_active);
                errors = errors + 1;
            end
            if ((memory_read_count != expected_reads) ||
                (request_count != expected_reads)) begin
                $display("ERROR realistic_sparse profile=%0s reads dut/tb=%0d/%0d expected=%0d",
                         profile_name, memory_read_count, request_count, expected_reads);
                errors = errors + 1;
            end
            if (accessed_columns !== vector) begin
                $display("ERROR realistic_sparse profile=%0s accessed-column mask mismatch",
                         profile_name);
                errors = errors + 1;
            end
            if ((received_tiles != ROW_TILES) ||
                (result_tile_seen !== {ROW_TILES{1'b1}})) begin
                $display("ERROR realistic_sparse profile=%0s result tiles=%0d expected=%0d",
                         profile_name, received_tiles, ROW_TILES);
                errors = errors + 1;
            end

            for (column = 0; column < COLUMNS; column = column + 1) begin
                if (vector[column]) begin
                    if (column_reads[column] != ROW_TILES) begin
                        $display("ERROR realistic_sparse profile=%0s column=%0d reads=%0d expected=%0d",
                                 profile_name, column, column_reads[column], ROW_TILES);
                        errors = errors + 1;
                    end
                    for (tile = 0; tile < ROW_TILES; tile = tile + 1) begin
                        if (!address_seen[column * ROW_TILES + tile]) begin
                            $display("ERROR realistic_sparse profile=%0s missing column=%0d tile=%0d",
                                     profile_name, column, tile);
                            errors = errors + 1;
                        end
                    end
                end else if (column_reads[column] != 0) begin
                    $display("ERROR realistic_sparse profile=%0s inactive column=%0d reads=%0d",
                             profile_name, column, column_reads[column]);
                    errors = errors + 1;
                end
            end

            if ((expected_reads != 0) && (request_stall_cycles == 0)) begin
                $display("ERROR realistic_sparse profile=%0s request stalls not exercised",
                         profile_name);
                errors = errors + 1;
            end
            if (result_stall_cycles == 0) begin
                $display("ERROR realistic_sparse profile=%0s result stalls not exercised",
                         profile_name);
                errors = errors + 1;
            end

            $display("REALISTIC_FRAME profile=%0s active=%0d sparsity_permille=%0d reads=%0d dense_reads=%0d saved_reads=%0d cycles=%0d overlap_prev=%0d changed_bits=%0d req_stalls=%0d result_stalls=%0d",
                     profile_name, expected_active,
                     ((COLUMNS - expected_active) * 1000) / COLUMNS,
                     expected_reads, ADDRESS_COUNT, ADDRESS_COUNT - expected_reads,
                     frame_cycles, overlap_count, changed_bits,
                     request_stall_cycles, result_stall_cycles);

            previous_vector = vector;
            previous_valid = 1'b1;
            frames_checked = frames_checked + 1;

            // STATE_DONE lasts one cycle.  Advance to STATE_IDLE before the
            // next frame, but do not assert reset between audio-like frames.
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        errors = 0;
        frames_checked = 0;
        global_cycle = 0;
        request_count = 0;
        received_tiles = 0;
        request_stall_cycles = 0;
        result_stall_cycles = 0;
        duplicate_addresses = 0;
        invalid_requests = 0;
        frame_active = 1'b0;
        previous_valid = 1'b0;
        previous_vector = {COLUMNS{1'b0}};
        rst = 1'b1;
        start = 1'b0;
        spike_vector = {COLUMNS{1'b0}};
        initialize_weights();

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        pattern = {COLUMNS{1'b0}};
        run_frame("silent", pattern, 0);

        make_scattered(pattern, 16, 3, 37);
        run_frame("scattered_95pct_sparse", pattern, 16);

        make_cluster(pattern, 16, 300);
        run_frame("cluster_wrap_95pct_sparse", pattern, 16);

        make_scattered(pattern, 32, 11, 37);
        run_frame("scattered_90pct_sparse", pattern, 32);

        make_scattered(pattern, 64, 5, 37);
        run_frame("scattered_80pct_sparse", pattern, 64);

        make_scattered(pattern, 96, 19, 37);
        run_frame("scattered_70pct_sparse", pattern, 96);

        make_scattered(pattern, 160, 7, 37);
        run_frame("scattered_50pct_sparse", pattern, 160);

        make_scattered(pattern, 320, 0, 37);
        run_frame("dense_reference_limit", pattern, 320);

        make_scattered(correlated_base, 32, 13, 37);
        run_frame("temporal_base_32", correlated_base, 32);
        run_frame("temporal_repeat_100pct", correlated_base, 32);

        make_correlated_churn(pattern, correlated_base, 8);
        run_frame("temporal_churn_8_of_32", pattern, 32);

        make_cluster(correlated_base, 32, 100);
        run_frame("moving_burst_base", correlated_base, 32);
        make_cluster(pattern, 32, 104);
        run_frame("moving_burst_shift4", pattern, 32);

        if ((errors == 0) && (frames_checked == 13))
            $display("PASS tb_sparsity_aware_matvec_realistic frames=%0d", frames_checked);
        else
            $fatal(1, "FAIL tb_sparsity_aware_matvec_realistic errors=%0d frames=%0d",
                   errors, frames_checked);
        $finish;
    end
endmodule
