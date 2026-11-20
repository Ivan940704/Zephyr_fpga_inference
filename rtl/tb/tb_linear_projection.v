`timescale 1ns/1ps

module tb_linear_projection;
    localparam INPUT_SIZE = 8;
    localparam OUTPUT_SIZE = 8;
    localparam LANES = 4;
    localparam ROW_TILES = OUTPUT_SIZE / LANES;
    localparam INPUT_INDEX_WIDTH = 3;
    localparam TILE_WIDTH = 1;

    reg clk = 1'b0;
    reg rst;
    reg start;
    reg input_valid;
    wire input_ready;
    reg input_spike;

    wire weight_req_valid;
    reg weight_req_ready;
    wire [INPUT_INDEX_WIDTH-1:0] weight_column;
    wire [TILE_WIDTH-1:0] weight_tile;
    reg weight_rsp_valid;
    wire weight_rsp_ready;
    reg [LANES*8-1:0] weight_rsp_data;

    wire param_req_valid;
    reg param_req_ready;
    wire [TILE_WIDTH-1:0] param_tile;
    reg param_rsp_valid;
    wire param_rsp_ready;
    reg [LANES*32-1:0] output_multiplier;
    reg [LANES*6-1:0] output_shift;
    reg [LANES*32-1:0] output_bias_q;

    wire result_valid;
    reg result_ready;
    wire [TILE_WIDTH-1:0] result_tile;
    wire result_last;
    wire [LANES*8-1:0] result_data;
    wire [LANES-1:0] result_clipped;
    wire [INPUT_INDEX_WIDTH:0] active_count;
    wire [31:0] weight_read_count;
    wire [31:0] parameter_read_count;
    wire busy;
    wire done;

    reg signed [7:0] weights [0:OUTPUT_SIZE-1][0:INPUT_SIZE-1];
    integer multiplier_values [0:OUTPUT_SIZE-1];
    integer shift_values [0:OUTPUT_SIZE-1];
    integer bias_values [0:OUTPUT_SIZE-1];
    integer expected_output [0:OUTPUT_SIZE-1];
    integer expected_clipped [0:OUTPUT_SIZE-1];
    reg [INPUT_SIZE-1:0] test_vector;

    integer errors;
    integer cases_checked;
    integer global_cycle;
    integer case_active;
    integer tb_weight_reads;
    integer tb_param_reads;
    integer result_tiles;
    integer weight_delay;
    integer param_delay;
    integer weight_stalls;
    integer param_stalls;
    integer result_stalls;
    integer total_weight_stalls;
    integer total_param_stalls;
    integer total_result_stalls;

    reg weight_pending;
    reg [INPUT_INDEX_WIDTH-1:0] pending_column;
    reg [TILE_WIDTH-1:0] pending_weight_tile;
    reg param_pending;
    reg [TILE_WIDTH-1:0] pending_param_tile;
    reg [INPUT_SIZE*ROW_TILES-1:0] weight_address_seen;
    reg [ROW_TILES-1:0] param_tile_seen;
    reg [ROW_TILES-1:0] result_tile_seen;
    reg request_stalled;
    reg [INPUT_INDEX_WIDTH-1:0] held_column;
    reg [TILE_WIDTH-1:0] held_weight_tile;
    reg param_request_stalled;
    reg [TILE_WIDTH-1:0] held_param_tile;
    reg output_stalled;
    reg [TILE_WIDTH-1:0] held_result_tile;
    reg [LANES*8-1:0] held_result_data;
    reg [LANES-1:0] held_result_clipped;

    always #5 clk = ~clk;

    linear_projection #(
        .INPUT_SIZE(INPUT_SIZE),
        .OUTPUT_SIZE(OUTPUT_SIZE),
        .LANES(LANES),
        .INPUT_INDEX_WIDTH(INPUT_INDEX_WIDTH),
        .TILE_WIDTH(TILE_WIDTH)
    ) dut (
        .clk(clk), .rst(rst), .start(start),
        .input_valid(input_valid), .input_ready(input_ready),
        .input_spike(input_spike),
        .weight_req_valid(weight_req_valid),
        .weight_req_ready(weight_req_ready),
        .weight_column(weight_column), .weight_tile(weight_tile),
        .weight_rsp_valid(weight_rsp_valid),
        .weight_rsp_ready(weight_rsp_ready), .weight_rsp_data(weight_rsp_data),
        .param_req_valid(param_req_valid), .param_req_ready(param_req_ready),
        .param_tile(param_tile), .param_rsp_valid(param_rsp_valid),
        .param_rsp_ready(param_rsp_ready),
        .output_multiplier(output_multiplier), .output_shift(output_shift),
        .output_bias_q(output_bias_q),
        .result_valid(result_valid), .result_ready(result_ready),
        .result_tile(result_tile), .result_last(result_last),
        .result_data(result_data), .result_clipped(result_clipped),
        .active_count(active_count), .weight_read_count(weight_read_count),
        .parameter_read_count(parameter_read_count),
        .busy(busy), .done(done)
    );

    function [LANES*8-1:0] make_weight_word;
        input [INPUT_INDEX_WIDTH-1:0] column;
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

    function automatic signed [63:0] round_shift_ref;
        input signed [63:0] value;
        input integer shift;
        reg signed [63:0] magnitude;
        begin
            if (shift == 0)
                round_shift_ref = value;
            else if (value < 0) begin
                magnitude = -value;
                round_shift_ref = -((magnitude + (64'sd1 <<< (shift - 1))) >>> shift);
            end else
                round_shift_ref = (value + (64'sd1 <<< (shift - 1))) >>> shift;
        end
    endfunction

    function automatic integer requant_ref;
        input integer value;
        input integer multiplier;
        input integer shift;
        reg signed [63:0] value_ext;
        reg signed [63:0] multiplier_ext;
        begin
            value_ext = value;
            multiplier_ext = multiplier;
            requant_ref = round_shift_ref(value_ext * multiplier_ext, shift);
        end
    endfunction

    task pack_params;
        input [TILE_WIDTH-1:0] tile;
        integer lane;
        integer row;
        begin
            output_multiplier = {(LANES*32){1'b0}};
            output_shift = {(LANES*6){1'b0}};
            output_bias_q = {(LANES*32){1'b0}};
            for (lane = 0; lane < LANES; lane = lane + 1) begin
                row = tile * LANES + lane;
                output_multiplier[lane*32 +: 32] = multiplier_values[row];
                output_shift[lane*6 +: 6] = shift_values[row];
                output_bias_q[lane*32 +: 32] = bias_values[row];
            end
        end
    endtask

    always @(posedge clk) begin
        integer address;
        if (rst) begin
            weight_req_ready <= 1'b0;
            weight_rsp_valid <= 1'b0;
            weight_rsp_data <= {(LANES*8){1'b0}};
            weight_pending <= 1'b0;
            pending_column <= {INPUT_INDEX_WIDTH{1'b0}};
            pending_weight_tile <= {TILE_WIDTH{1'b0}};
            weight_delay <= 0;
            global_cycle <= 0;
        end else begin
            global_cycle <= global_cycle + 1;
            weight_req_ready <= !weight_pending && !weight_rsp_valid &&
                                ((global_cycle % 5) != 2);
            if (weight_rsp_valid && weight_rsp_ready)
                weight_rsp_valid <= 1'b0;
            if (weight_req_valid && weight_req_ready) begin
                weight_pending <= 1'b1;
                pending_column <= weight_column;
                pending_weight_tile <= weight_tile;
                weight_delay <= (weight_column + weight_tile + global_cycle) % 3;
                if (case_active) begin
                    tb_weight_reads = tb_weight_reads + 1;
                    address = weight_column * ROW_TILES + weight_tile;
                    if (!test_vector[weight_column] || weight_address_seen[address]) begin
                        $display("ERROR linear_projection invalid/duplicate weight column=%0d tile=%0d",
                                 weight_column, weight_tile);
                        errors = errors + 1;
                    end
                    weight_address_seen[address] = 1'b1;
                end
            end
            if (weight_pending) begin
                if ((weight_delay == 0) && !weight_rsp_valid) begin
                    weight_rsp_data <= make_weight_word(pending_column,
                                                        pending_weight_tile);
                    weight_rsp_valid <= 1'b1;
                    weight_pending <= 1'b0;
                end else if (weight_delay != 0)
                    weight_delay <= weight_delay - 1;
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            param_req_ready <= 1'b0;
            param_rsp_valid <= 1'b0;
            param_pending <= 1'b0;
            pending_param_tile <= {TILE_WIDTH{1'b0}};
            param_delay <= 0;
        end else begin
            param_req_ready <= !param_pending && !param_rsp_valid &&
                               ((global_cycle % 4) != 1);
            if (param_rsp_valid && param_rsp_ready)
                param_rsp_valid <= 1'b0;
            if (param_req_valid && param_req_ready) begin
                param_pending <= 1'b1;
                pending_param_tile <= param_tile;
                param_delay <= (param_tile + global_cycle) % 2;
                if (case_active) begin
                    tb_param_reads = tb_param_reads + 1;
                    if (param_tile_seen[param_tile]) begin
                        $display("ERROR linear_projection duplicate param tile=%0d", param_tile);
                        errors = errors + 1;
                    end
                    param_tile_seen[param_tile] = 1'b1;
                end
            end
            if (param_pending) begin
                if ((param_delay == 0) && !param_rsp_valid) begin
                    pack_params(pending_param_tile);
                    param_rsp_valid <= 1'b1;
                    param_pending <= 1'b0;
                end else if (param_delay != 0)
                    param_delay <= param_delay - 1;
            end
        end
    end

    always @(posedge clk) begin
        if (rst)
            result_ready <= 1'b0;
        else if (!case_active)
            result_ready <= 1'b1;
        else
            result_ready <= global_cycle[0];
    end

    always @(posedge clk) begin
        if (rst) begin
            request_stalled <= 1'b0;
            param_request_stalled <= 1'b0;
            output_stalled <= 1'b0;
        end else begin
            if (case_active && weight_req_valid && !weight_req_ready) begin
                weight_stalls = weight_stalls + 1;
                total_weight_stalls = total_weight_stalls + 1;
                if (request_stalled &&
                    ((weight_column !== held_column) ||
                     (weight_tile !== held_weight_tile))) begin
                    $display("ERROR linear_projection weight request changed while stalled");
                    errors = errors + 1;
                end
                request_stalled <= 1'b1;
                held_column <= weight_column;
                held_weight_tile <= weight_tile;
            end else
                request_stalled <= 1'b0;

            if (case_active && param_req_valid && !param_req_ready) begin
                param_stalls = param_stalls + 1;
                total_param_stalls = total_param_stalls + 1;
                if (param_request_stalled && param_tile !== held_param_tile) begin
                    $display("ERROR linear_projection param request changed while stalled");
                    errors = errors + 1;
                end
                param_request_stalled <= 1'b1;
                held_param_tile <= param_tile;
            end else
                param_request_stalled <= 1'b0;

            if (case_active && result_valid && !result_ready) begin
                result_stalls = result_stalls + 1;
                total_result_stalls = total_result_stalls + 1;
                if (output_stalled &&
                    ((result_tile !== held_result_tile) ||
                     (result_data !== held_result_data) ||
                     (result_clipped !== held_result_clipped))) begin
                    $display("ERROR linear_projection result changed while stalled");
                    errors = errors + 1;
                end
                output_stalled <= 1'b1;
                held_result_tile <= result_tile;
                held_result_data <= result_data;
                held_result_clipped <= result_clipped;
            end else
                output_stalled <= 1'b0;
        end
    end

    always @(posedge clk) begin
        integer lane;
        integer row;
        if (!rst && case_active && result_valid && result_ready) begin
            if (result_tile_seen[result_tile]) begin
                $display("ERROR linear_projection duplicate result tile=%0d", result_tile);
                errors = errors + 1;
            end
            result_tile_seen[result_tile] = 1'b1;
            result_tiles = result_tiles + 1;
            if (result_last !== (result_tile == ROW_TILES - 1)) begin
                $display("ERROR linear_projection last mismatch tile=%0d", result_tile);
                errors = errors + 1;
            end
            for (lane = 0; lane < LANES; lane = lane + 1) begin
                row = result_tile * LANES + lane;
                if ($signed(result_data[lane*8 +: 8]) !== expected_output[row] ||
                    result_clipped[lane] !== expected_clipped[row]) begin
                    $display("ERROR linear_projection row=%0d got=%0d/%0d expected=%0d/%0d",
                             row, $signed(result_data[lane*8 +: 8]),
                             result_clipped[lane], expected_output[row],
                             expected_clipped[row]);
                    errors = errors + 1;
                end
            end
        end
    end

    task initialize_model;
        integer row;
        integer column;
        begin
            for (row = 0; row < OUTPUT_SIZE; row = row + 1) begin
                for (column = 0; column < INPUT_SIZE; column = column + 1)
                    weights[row][column] = ((row * 7 + column * 5 + 3) % 17) - 8;
                multiplier_values[row] = 1073741824;
                shift_values[row] = 22 + (row % 2);
                if (row == 0)
                    bias_values[row] = -140 * 256;
                else if (row == OUTPUT_SIZE - 1)
                    bias_values[row] = 140 * 256;
                else
                    bias_values[row] = (row * 5 - 15) * 256;
            end
        end
    endtask

    task build_expected;
        integer row;
        integer column;
        integer accumulator;
        integer unclamped;
        integer input_value;
        reg signed [63:0] sum64;
        begin
            for (row = 0; row < OUTPUT_SIZE; row = row + 1) begin
                accumulator = 0;
                for (column = 0; column < INPUT_SIZE; column = column + 1)
                    if (test_vector[column])
                        accumulator = accumulator + $signed(weights[row][column]);
                sum64 = requant_ref(accumulator, multiplier_values[row],
                                    shift_values[row]) + bias_values[row];
                unclamped = round_shift_ref(sum64, 8);
                expected_clipped[row] = (unclamped < -127) || (unclamped > 127);
                if (unclamped < -127)
                    expected_output[row] = -127;
                else if (unclamped > 127)
                    expected_output[row] = 127;
                else
                    expected_output[row] = unclamped;
            end
        end
    endtask

    task send_vector;
        integer column;
        begin
            for (column = 0; column < INPUT_SIZE; column = column + 1) begin
                if ((column % 3) == 2) begin
                    @(negedge clk);
                    input_valid = 1'b0;
                end
                @(negedge clk);
                input_valid = 1'b1;
                input_spike = test_vector[column];
                while (!input_ready)
                    @(negedge clk);
            end
            @(negedge clk);
            input_valid = 1'b0;
        end
    endtask

    task run_case;
        input [8*20-1:0] case_name;
        input [INPUT_SIZE-1:0] vector;
        integer expected_active;
        integer expected_reads;
        integer column;
        integer tile;
        integer timeout;
        integer errors_before;
        begin
            test_vector = vector;
            expected_active = 0;
            for (column = 0; column < INPUT_SIZE; column = column + 1)
                expected_active = expected_active + vector[column];
            expected_reads = expected_active * ROW_TILES;
            build_expected();

            @(negedge clk);
            case_active = 1;
            tb_weight_reads = 0;
            tb_param_reads = 0;
            result_tiles = 0;
            weight_stalls = 0;
            param_stalls = 0;
            result_stalls = 0;
            weight_address_seen = {(INPUT_SIZE*ROW_TILES){1'b0}};
            param_tile_seen = {ROW_TILES{1'b0}};
            result_tile_seen = {ROW_TILES{1'b0}};
            errors_before = errors;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            send_vector();

            timeout = 0;
            while (!done && timeout < 10000) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            if (!done)
                $fatal(1, "FAIL tb_linear_projection case=%0s timed out", case_name);
            case_active = 0;
            #1;

            if (active_count != expected_active ||
                weight_read_count != expected_reads ||
                tb_weight_reads != expected_reads) begin
                $display("ERROR linear_projection case=%0s active/reads got=%0d/%0d/%0d expected=%0d/%0d",
                         case_name, active_count, weight_read_count,
                         tb_weight_reads, expected_active, expected_reads);
                errors = errors + 1;
            end
            if (parameter_read_count != ROW_TILES || tb_param_reads != ROW_TILES ||
                result_tiles != ROW_TILES ||
                param_tile_seen !== {ROW_TILES{1'b1}} ||
                result_tile_seen !== {ROW_TILES{1'b1}}) begin
                $display("ERROR linear_projection case=%0s tile coverage incomplete",
                         case_name);
                errors = errors + 1;
            end
            for (column = 0; column < INPUT_SIZE; column = column + 1)
                for (tile = 0; tile < ROW_TILES; tile = tile + 1)
                    if (weight_address_seen[column * ROW_TILES + tile] !==
                        vector[column]) begin
                        $display("ERROR linear_projection case=%0s address coverage column=%0d tile=%0d",
                                 case_name, column, tile);
                        errors = errors + 1;
                    end

            $display("LINEAR_CASE name=%0s active=%0d reads=%0d dense_reads=%0d weight_stalls=%0d param_stalls=%0d result_stalls=%0d errors_added=%0d",
                     case_name, expected_active, expected_reads,
                     INPUT_SIZE * ROW_TILES, weight_stalls, param_stalls,
                     result_stalls, errors - errors_before);
            cases_checked = cases_checked + 1;
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        errors = 0;
        cases_checked = 0;
        global_cycle = 0;
        case_active = 0;
        tb_weight_reads = 0;
        tb_param_reads = 0;
        result_tiles = 0;
        weight_stalls = 0;
        param_stalls = 0;
        result_stalls = 0;
        total_weight_stalls = 0;
        total_param_stalls = 0;
        total_result_stalls = 0;
        rst = 1'b1;
        start = 1'b0;
        input_valid = 1'b0;
        input_spike = 1'b0;
        initialize_model();
        pack_params(0);

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        run_case("zero", 8'b0000_0000);
        run_case("sparse_two", 8'b0100_0010);
        run_case("sparse_five", 8'b1011_0101);
        run_case("dense", 8'b1111_1111);

        if (total_weight_stalls == 0 || total_param_stalls == 0 ||
            total_result_stalls == 0) begin
            $display("ERROR linear_projection did not exercise all stalls");
            errors = errors + 1;
        end
        if ((errors == 0) && (cases_checked == 4))
            $display("PASS tb_linear_projection cases=%0d", cases_checked);
        else
            $fatal(1, "FAIL tb_linear_projection errors=%0d cases=%0d",
                   errors, cases_checked);
        $finish;
    end
endmodule
