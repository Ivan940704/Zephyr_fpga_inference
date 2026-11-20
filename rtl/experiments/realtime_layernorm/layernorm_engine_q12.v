`timescale 1ns/1ps

// Shared fixed-point LayerNorm arithmetic engine for the real-time experiment.
//
// Numeric contract:
//   values, affine weights, affine biases: signed Q12
//   population variance: Q24
//   inverse standard deviation and output reciprocal: Q20
//   divisions/right shifts: round-to-nearest, ties-to-even
//   output: saturated signed INT8 in [-127, 127]
//
// One packed synchronous RAM stores a complete vector.  Divider and square-root
// operations are iterative.  Every multiplier has an explicit result register
// before rounding, keeping the arithmetic path pipeline-friendly at 125 MHz.
// This experimental leaf does not modify the frozen PE baseline and contains
// no model-specific vector assembly.
module layernorm_engine_q12 #(
    parameter integer MAX_LENGTH = 158
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 abort,

    input  wire                 config_valid,
    output wire                 config_ready,
    input  wire [7:0]           config_length,
    input  wire [31:0]          config_output_reciprocal_q20,
    input  wire [31:0]          config_epsilon_q24,

    input  wire                 input_valid,
    output wire                 input_ready,
    input  wire signed [15:0]   input_value_q12,
    input  wire signed [15:0]   input_weight_q12,
    input  wire signed [15:0]   input_bias_q12,
    input  wire                 input_last,

    output wire                 output_valid,
    input  wire                 output_ready,
    output wire signed [7:0]    output_data,
    output wire [7:0]           output_index,
    output wire                 output_last,

    output wire                 busy,
    output reg                  done,
    output reg                  error,
    output reg  [7:0]           error_code,
    output reg  [31:0]          cycle_count
);
    localparam [5:0] ST_IDLE             = 6'd0;
    localparam [5:0] ST_LOAD             = 6'd1;
    localparam [5:0] ST_MEAN_DIV         = 6'd2;
    localparam [5:0] ST_VAR_READ         = 6'd3;
    localparam [5:0] ST_VAR_MULTIPLY     = 6'd4;
    localparam [5:0] ST_VAR_ACCUM        = 6'd5;
    localparam [5:0] ST_VAR_DIV          = 6'd6;
    localparam [5:0] ST_SQRT             = 6'd7;
    localparam [5:0] ST_INV_DIV          = 6'd8;
    localparam [5:0] ST_OUT_READ         = 6'd9;
    localparam [5:0] ST_OUT_NORM_MUL     = 6'd10;
    localparam [5:0] ST_OUT_NORM_ROUND   = 6'd11;
    localparam [5:0] ST_OUT_AFFINE_MUL   = 6'd12;
    localparam [5:0] ST_OUT_AFFINE_ROUND = 6'd13;
    localparam [5:0] ST_OUT_SCALE_MUL    = 6'd14;
    localparam [5:0] ST_OUT_SCALE_ROUND  = 6'd15;
    localparam [5:0] ST_OUT_HOLD         = 6'd16;
    localparam [5:0] ST_DIV_ROUND_CHECK  = 6'd17;
    localparam [5:0] ST_DIV_ROUND_ADD    = 6'd18;
    localparam [5:0] ST_SQRT_FINISH      = 6'd19;
    localparam [5:0] ST_DIV_APPLY        = 6'd20;
    localparam [5:0] ST_NORM_QUOTIENT    = 6'd21;
    localparam [5:0] ST_NORM_FINISH      = 6'd22;
    localparam [5:0] ST_AFFINE_QUOTIENT  = 6'd23;
    localparam [5:0] ST_AFFINE_SIGN      = 6'd24;
    localparam [5:0] ST_AFFINE_FINISH    = 6'd25;
    localparam [5:0] ST_SCALE_QUOTIENT   = 6'd26;
    localparam [5:0] ST_SCALE_FINISH     = 6'd27;
    localparam [5:0] ST_SQRT_ROUND_ADD   = 6'd28;
    localparam [5:0] ST_SQRT_APPLY       = 6'd29;
    localparam [5:0] ST_VAR_CENTER       = 6'd30;
    localparam [5:0] ST_OUT_CENTER       = 6'd31;
    localparam [5:0] ST_AFFINE_RANGE     = 6'd32;

    localparam [7:0] ERR_NONE           = 8'h00;
    localparam [7:0] ERR_CONFIG_LENGTH  = 8'h70;
    localparam [7:0] ERR_CONFIG_SCALE   = 8'h71;
    localparam [7:0] ERR_INPUT_LAST     = 8'h72;
    localparam [7:0] ERR_ZERO_STD       = 8'h73;
    localparam [7:0] ERR_INTERNAL_RANGE = 8'h74;

    localparam [63:0] INVERSE_STD_NUMERATOR = 64'h0000000100000000;

    reg [5:0] state_q;
    reg [7:0] length_q;
    reg [7:0] index_q;
    reg [31:0] output_reciprocal_q;
    reg [31:0] epsilon_q;
    (* ram_style = "block" *) reg [47:0] sample_memory [0:MAX_LENGTH-1];
    reg [47:0] sample_read_q;

    reg signed [32:0] sum_q;
    reg sum_negative_q;
    reg signed [16:0] mean_q;
    reg signed [16:0] centered_q;
    reg [63:0] square_sum_q;
    reg [31:0] inverse_standard_deviation_q;
    reg signed [33:0] variance_product_q;
    reg signed [49:0] normalized_product_q;
    reg normalized_negative_q;
    reg [49:0] normalized_magnitude_q;
    reg [30:0] normalized_quotient_q;
    reg signed [23:0] normalized_q;
    reg signed [39:0] affine_product_q;
    reg affine_negative_q;
    reg [39:0] affine_magnitude_q;
    reg [28:0] affine_quotient_q;
    reg signed [29:0] affine_weighted_q;
    reg signed [29:0] affine_with_bias_q;
    reg signed [23:0] affine_q;
    reg signed [56:0] output_product_q;
    reg output_negative_q;
    reg [56:0] output_magnitude_q;
    reg [25:0] output_quotient_q;

    reg [63:0] divider_dividend_q;
    reg [63:0] divider_denominator_q;
    reg [64:0] divider_remainder_q;
    reg [63:0] divider_quotient_q;
    reg [6:0] divider_count_q;
    reg [1:0] divider_destination_q;
    reg divider_round_up_q;
    reg [63:0] divider_rounded_quotient_q;

    reg [63:0] sqrt_radicand_q;
    reg [65:0] sqrt_remainder_q;
    reg [31:0] sqrt_root_q;
    reg [5:0] sqrt_count_q;
    reg sqrt_round_up_q;
    reg [31:0] sqrt_nearest_root_q;

    reg signed [7:0] output_data_q;
    reg [7:0] output_index_q;
    reg output_last_q;
    reg [31:0] working_cycle_count_q;

    wire config_fire = config_valid && config_ready;
    wire input_fire = input_valid && input_ready;
    wire output_fire = output_valid && output_ready;
    wire expected_input_last = (index_q == (length_q - 1'b1));

    wire signed [32:0] input_value_extended =
        {{17{input_value_q12[15]}}, input_value_q12};
    wire signed [32:0] load_sum_next = sum_q + input_value_extended;
    wire [32:0] load_sum_magnitude = load_sum_next[32]
        ? -load_sum_next : load_sum_next;

    wire [64:0] divider_shifted_remainder =
        {divider_remainder_q[63:0], divider_dividend_q[63]};
    wire divider_take = divider_shifted_remainder >=
        {1'b0, divider_denominator_q};
    wire [64:0] divider_next_remainder = divider_take
        ? divider_shifted_remainder - {1'b0, divider_denominator_q}
        : divider_shifted_remainder;
    wire [63:0] divider_next_quotient =
        {divider_quotient_q[62:0], divider_take};
    wire [65:0] divider_twice_remainder =
        {divider_remainder_q, 1'b0};
    wire [65:0] divider_extended_denominator =
        {2'b00, divider_denominator_q};
    wire divider_round_up =
        (divider_twice_remainder > divider_extended_denominator) ||
        ((divider_twice_remainder == divider_extended_denominator) &&
         divider_quotient_q[0]);
    wire [65:0] sqrt_shifted_remainder =
        {sqrt_remainder_q[63:0], sqrt_radicand_q[63:62]};
    wire [65:0] sqrt_trial = {32'd0, sqrt_root_q, 2'b01};
    wire sqrt_take = sqrt_shifted_remainder >= sqrt_trial;
    wire [65:0] sqrt_next_remainder = sqrt_take
        ? sqrt_shifted_remainder - sqrt_trial
        : sqrt_shifted_remainder;
    wire [31:0] sqrt_next_root = {sqrt_root_q[30:0], sqrt_take};
    wire [66:0] sqrt_twice_remainder = {sqrt_remainder_q, 1'b0};
    wire [66:0] sqrt_upper_distance_sum =
        {34'd0, sqrt_root_q, 1'b0} + 1'b1;
    wire sqrt_round_up = sqrt_twice_remainder > sqrt_upper_distance_sum;
    wire signed [15:0] sample_value = sample_read_q[15:0];
    wire signed [15:0] sample_weight = sample_read_q[31:16];
    wire signed [15:0] sample_bias = sample_read_q[47:32];
    wire signed [16:0] sample_value_extended =
        {sample_value[15], sample_value};
    wire signed [16:0] sample_centered = sample_value_extended - mean_q;
    wire signed [32:0] inverse_standard_deviation_extended =
        {1'b0, inverse_standard_deviation_q};
    wire signed [32:0] output_reciprocal_extended =
        {1'b0, output_reciprocal_q};

    wire normalized_round_up = normalized_magnitude_q[19] &&
        ((|normalized_magnitude_q[18:0]) || normalized_magnitude_q[20]);
    wire [30:0] normalized_magnitude_rounded =
        {1'b0, normalized_magnitude_q[49:20]} + normalized_round_up;
    wire signed [31:0] normalized_signed_rounded = normalized_negative_q
        ? -$signed({1'b0, normalized_quotient_q})
        : $signed({1'b0, normalized_quotient_q});

    wire affine_round_up = affine_magnitude_q[11] &&
        ((|affine_magnitude_q[10:0]) || affine_magnitude_q[12]);
    wire [28:0] affine_magnitude_rounded =
        {1'b0, affine_magnitude_q[39:12]} + affine_round_up;
    wire signed [29:0] affine_signed_rounded = affine_negative_q
        ? -$signed({1'b0, affine_quotient_q})
        : $signed({1'b0, affine_quotient_q});
    wire signed [29:0] affine_with_bias = affine_weighted_q +
        {{14{sample_bias[15]}}, sample_bias};

    wire output_round_up = output_magnitude_q[31] &&
        ((|output_magnitude_q[30:0]) || output_magnitude_q[32]);
    wire [25:0] output_magnitude_rounded =
        {1'b0, output_magnitude_q[56:32]} + output_round_up;

    assign config_ready = rst_n && !error && (state_q == ST_IDLE);
    assign input_ready = rst_n && !error && (state_q == ST_LOAD);
    assign output_valid = rst_n && !error && (state_q == ST_OUT_HOLD);
    assign output_data = output_data_q;
    assign output_index = output_index_q;
    assign output_last = output_last_q;
    assign busy = (state_q != ST_IDLE);

    initial begin
        if (MAX_LENGTH < 1 || MAX_LENGTH > 255) begin
            $display("layernorm_engine_q12 MAX_LENGTH must be 1..255");
            $finish;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state_q <= ST_IDLE;
            length_q <= 8'd0;
            index_q <= 8'd0;
            output_reciprocal_q <= 32'd0;
            epsilon_q <= 32'd0;
            sample_read_q <= 48'd0;
            sum_q <= 33'sd0;
            sum_negative_q <= 1'b0;
            mean_q <= 17'sd0;
            centered_q <= 17'sd0;
            square_sum_q <= 64'd0;
            inverse_standard_deviation_q <= 32'd0;
            variance_product_q <= 34'sd0;
            normalized_product_q <= 50'sd0;
            normalized_negative_q <= 1'b0;
            normalized_magnitude_q <= 50'd0;
            normalized_quotient_q <= 31'd0;
            normalized_q <= 24'sd0;
            affine_product_q <= 40'sd0;
            affine_negative_q <= 1'b0;
            affine_magnitude_q <= 40'd0;
            affine_quotient_q <= 29'd0;
            affine_weighted_q <= 30'sd0;
            affine_with_bias_q <= 30'sd0;
            affine_q <= 24'sd0;
            output_product_q <= 57'sd0;
            output_negative_q <= 1'b0;
            output_magnitude_q <= 57'd0;
            output_quotient_q <= 26'd0;
            divider_dividend_q <= 64'd0;
            divider_denominator_q <= 64'd0;
            divider_remainder_q <= 65'd0;
            divider_quotient_q <= 64'd0;
            divider_count_q <= 7'd0;
            divider_destination_q <= 2'd0;
            divider_round_up_q <= 1'b0;
            divider_rounded_quotient_q <= 64'd0;
            sqrt_radicand_q <= 64'd0;
            sqrt_remainder_q <= 66'd0;
            sqrt_root_q <= 32'd0;
            sqrt_count_q <= 6'd0;
            sqrt_round_up_q <= 1'b0;
            sqrt_nearest_root_q <= 32'd0;
            output_data_q <= 8'sd0;
            output_index_q <= 8'd0;
            output_last_q <= 1'b0;
            working_cycle_count_q <= 32'd0;
            cycle_count <= 32'd0;
            done <= 1'b0;
            error <= 1'b0;
            error_code <= ERR_NONE;
        end else begin
            done <= 1'b0;
            if (state_q != ST_IDLE)
                working_cycle_count_q <= working_cycle_count_q + 1'b1;

            if (abort) begin
                state_q <= ST_IDLE;
                index_q <= 8'd0;
                sum_q <= 33'sd0;
                square_sum_q <= 64'd0;
                divider_count_q <= 7'd0;
                sqrt_count_q <= 6'd0;
                output_last_q <= 1'b0;
            end else begin
                case (state_q)
                    ST_IDLE: begin
                        index_q <= 8'd0;
                        if (config_fire) begin
                            if ((config_length == 0) ||
                                (config_length > MAX_LENGTH)) begin
                                error <= 1'b1;
                                error_code <= ERR_CONFIG_LENGTH;
                            end else if ((config_output_reciprocal_q20 == 0) ||
                                         config_output_reciprocal_q20[31]) begin
                                error <= 1'b1;
                                error_code <= ERR_CONFIG_SCALE;
                            end else begin
                                length_q <= config_length;
                                output_reciprocal_q <=
                                    config_output_reciprocal_q20;
                                epsilon_q <= config_epsilon_q24;
                                sum_q <= 33'sd0;
                                working_cycle_count_q <= 32'd0;
                                state_q <= ST_LOAD;
                            end
                        end
                    end

                    ST_LOAD: begin
                        if (input_fire) begin
                            if (input_last != expected_input_last) begin
                                error <= 1'b1;
                                error_code <= ERR_INPUT_LAST;
                                state_q <= ST_IDLE;
                            end else begin
                                sample_memory[index_q] <= {
                                    input_bias_q12,
                                    input_weight_q12,
                                    input_value_q12
                                };
                                sum_q <= load_sum_next;
                                if (expected_input_last) begin
                                    sum_negative_q <= load_sum_next[32];
                                    divider_dividend_q <=
                                        {{31{1'b0}}, load_sum_magnitude};
                                    divider_denominator_q <=
                                        {{56{1'b0}}, length_q};
                                    divider_remainder_q <= 65'd0;
                                    divider_quotient_q <= 64'd0;
                                    divider_count_q <= 7'd64;
                                    state_q <= ST_MEAN_DIV;
                                end else begin
                                    index_q <= index_q + 1'b1;
                                end
                            end
                        end
                    end

                    ST_MEAN_DIV: begin
                        divider_dividend_q <=
                            {divider_dividend_q[62:0], 1'b0};
                        divider_remainder_q <= divider_next_remainder;
                        divider_quotient_q <= divider_next_quotient;
                        divider_count_q <= divider_count_q - 1'b1;
                        if (divider_count_q == 1) begin
                            divider_destination_q <= 2'd0;
                            state_q <= ST_DIV_ROUND_CHECK;
                        end
                    end

                    ST_VAR_READ: begin
                        sample_read_q <= sample_memory[index_q];
                        state_q <= ST_VAR_CENTER;
                    end

                    ST_VAR_CENTER: begin
                        centered_q <= sample_centered;
                        state_q <= ST_VAR_MULTIPLY;
                    end

                    ST_VAR_MULTIPLY: begin
                        variance_product_q <= centered_q * centered_q;
                        state_q <= ST_VAR_ACCUM;
                    end

                    ST_VAR_ACCUM: begin
                        square_sum_q <= square_sum_q +
                            {{30{1'b0}}, variance_product_q};
                        if (index_q == (length_q - 1'b1)) begin
                            divider_dividend_q <= square_sum_q +
                                {{30{1'b0}}, variance_product_q};
                            divider_denominator_q <=
                                {{56{1'b0}}, length_q};
                            divider_remainder_q <= 65'd0;
                            divider_quotient_q <= 64'd0;
                            divider_count_q <= 7'd64;
                            state_q <= ST_VAR_DIV;
                        end else begin
                            index_q <= index_q + 1'b1;
                            state_q <= ST_VAR_READ;
                        end
                    end

                    ST_VAR_DIV: begin
                        divider_dividend_q <=
                            {divider_dividend_q[62:0], 1'b0};
                        divider_remainder_q <= divider_next_remainder;
                        divider_quotient_q <= divider_next_quotient;
                        divider_count_q <= divider_count_q - 1'b1;
                        if (divider_count_q == 1) begin
                            divider_destination_q <= 2'd1;
                            state_q <= ST_DIV_ROUND_CHECK;
                        end
                    end

                    ST_SQRT: begin
                        sqrt_radicand_q <= {sqrt_radicand_q[61:0], 2'b00};
                        sqrt_remainder_q <= sqrt_next_remainder;
                        sqrt_root_q <= sqrt_next_root;
                        sqrt_count_q <= sqrt_count_q - 1'b1;
                        if (sqrt_count_q == 1) begin
                            state_q <= ST_SQRT_FINISH;
                        end
                    end

                    ST_SQRT_FINISH: begin
                        sqrt_round_up_q <= sqrt_round_up;
                        state_q <= ST_SQRT_ROUND_ADD;
                    end

                    ST_SQRT_ROUND_ADD: begin
                        sqrt_nearest_root_q <= sqrt_root_q + sqrt_round_up_q;
                        state_q <= ST_SQRT_APPLY;
                    end

                    ST_SQRT_APPLY: begin
                            if (sqrt_nearest_root_q == 0) begin
                                error <= 1'b1;
                                error_code <= ERR_ZERO_STD;
                                state_q <= ST_IDLE;
                            end else begin
                                divider_dividend_q <= INVERSE_STD_NUMERATOR;
                                divider_denominator_q <=
                                    {{32{1'b0}}, sqrt_nearest_root_q};
                                divider_remainder_q <= 65'd0;
                                divider_quotient_q <= 64'd0;
                                divider_count_q <= 7'd64;
                                state_q <= ST_INV_DIV;
                            end
                        end

                    ST_INV_DIV: begin
                        divider_dividend_q <=
                            {divider_dividend_q[62:0], 1'b0};
                        divider_remainder_q <= divider_next_remainder;
                        divider_quotient_q <= divider_next_quotient;
                        divider_count_q <= divider_count_q - 1'b1;
                        if (divider_count_q == 1) begin
                            divider_destination_q <= 2'd2;
                            state_q <= ST_DIV_ROUND_CHECK;
                        end
                    end

                    ST_DIV_ROUND_CHECK: begin
                        divider_round_up_q <= divider_round_up;
                        state_q <= ST_DIV_ROUND_ADD;
                    end

                    ST_DIV_ROUND_ADD: begin
                        divider_rounded_quotient_q <=
                            divider_quotient_q + divider_round_up_q;
                        state_q <= ST_DIV_APPLY;
                    end

                    ST_DIV_APPLY: begin
                        case (divider_destination_q)
                            2'd0: begin
                                mean_q <= sum_negative_q
                                    ? -$signed(divider_rounded_quotient_q[16:0])
                                    : $signed(divider_rounded_quotient_q[16:0]);
                                index_q <= 8'd0;
                                square_sum_q <= 64'd0;
                                state_q <= ST_VAR_READ;
                            end
                            2'd1: begin
                                sqrt_radicand_q <= divider_rounded_quotient_q +
                                    {{32{1'b0}}, epsilon_q};
                                sqrt_remainder_q <= 66'd0;
                                sqrt_root_q <= 32'd0;
                                sqrt_count_q <= 6'd32;
                                state_q <= ST_SQRT;
                            end
                            2'd2: begin
                                if (|divider_rounded_quotient_q[63:32]) begin
                                    error <= 1'b1;
                                    error_code <= ERR_INTERNAL_RANGE;
                                    state_q <= ST_IDLE;
                                end else begin
                                    inverse_standard_deviation_q <=
                                        divider_rounded_quotient_q[31:0];
                                    index_q <= 8'd0;
                                    state_q <= ST_OUT_READ;
                                end
                            end
                            default: begin
                                error <= 1'b1;
                                error_code <= ERR_INTERNAL_RANGE;
                                state_q <= ST_IDLE;
                            end
                        endcase
                    end

                    ST_OUT_READ: begin
                        sample_read_q <= sample_memory[index_q];
                        state_q <= ST_OUT_CENTER;
                    end

                    ST_OUT_CENTER: begin
                        centered_q <= sample_centered;
                        state_q <= ST_OUT_NORM_MUL;
                    end

                    ST_OUT_NORM_MUL: begin
                        normalized_product_q <= centered_q *
                            inverse_standard_deviation_extended;
                        state_q <= ST_OUT_NORM_ROUND;
                    end

                    ST_OUT_NORM_ROUND: begin
                        normalized_negative_q <= normalized_product_q[49];
                        normalized_magnitude_q <= normalized_product_q[49]
                            ? -normalized_product_q : normalized_product_q;
                        state_q <= ST_NORM_QUOTIENT;
                    end

                    ST_NORM_QUOTIENT: begin
                        normalized_quotient_q <= normalized_magnitude_rounded;
                        state_q <= ST_NORM_FINISH;
                    end

                    ST_NORM_FINISH: begin
                        if ((normalized_signed_rounded > 32'sd8388607) ||
                            (normalized_signed_rounded < -32'sd8388608)) begin
                            error <= 1'b1;
                            error_code <= ERR_INTERNAL_RANGE;
                            state_q <= ST_IDLE;
                        end else begin
                            normalized_q <= normalized_signed_rounded[23:0];
                            state_q <= ST_OUT_AFFINE_MUL;
                        end
                    end

                    ST_OUT_AFFINE_MUL: begin
                        affine_product_q <= normalized_q * sample_weight;
                        state_q <= ST_OUT_AFFINE_ROUND;
                    end

                    ST_OUT_AFFINE_ROUND: begin
                        affine_negative_q <= affine_product_q[39];
                        affine_magnitude_q <= affine_product_q[39]
                            ? -affine_product_q : affine_product_q;
                        state_q <= ST_AFFINE_QUOTIENT;
                    end

                    ST_AFFINE_QUOTIENT: begin
                        affine_quotient_q <= affine_magnitude_rounded;
                        state_q <= ST_AFFINE_SIGN;
                    end

                    ST_AFFINE_SIGN: begin
                        affine_weighted_q <= affine_signed_rounded;
                        state_q <= ST_AFFINE_FINISH;
                    end

                    ST_AFFINE_FINISH: begin
                        affine_with_bias_q <= affine_with_bias;
                        state_q <= ST_AFFINE_RANGE;
                    end

                    ST_AFFINE_RANGE: begin
                        if ((affine_with_bias_q > 30'sd8388607) ||
                            (affine_with_bias_q < -30'sd8388608)) begin
                            error <= 1'b1;
                            error_code <= ERR_INTERNAL_RANGE;
                            state_q <= ST_IDLE;
                        end else begin
                            affine_q <= affine_with_bias_q[23:0];
                            state_q <= ST_OUT_SCALE_MUL;
                        end
                    end

                    ST_OUT_SCALE_MUL: begin
                        output_product_q <= affine_q *
                            output_reciprocal_extended;
                        state_q <= ST_OUT_SCALE_ROUND;
                    end

                    ST_OUT_SCALE_ROUND: begin
                        output_negative_q <= output_product_q[56];
                        output_magnitude_q <= output_product_q[56]
                            ? -output_product_q : output_product_q;
                        state_q <= ST_SCALE_QUOTIENT;
                    end

                    ST_SCALE_QUOTIENT: begin
                        output_quotient_q <= output_magnitude_rounded;
                        state_q <= ST_SCALE_FINISH;
                    end

                    ST_SCALE_FINISH: begin
                        if (output_quotient_q > 26'd127)
                            output_data_q <= output_negative_q
                                ? -8'sd127 : 8'sd127;
                        else if (output_negative_q)
                            output_data_q <= -$signed(output_quotient_q[7:0]);
                        else
                            output_data_q <= output_quotient_q[7:0];
                        output_index_q <= index_q;
                        output_last_q <=
                            (index_q == (length_q - 1'b1));
                        state_q <= ST_OUT_HOLD;
                    end

                    ST_OUT_HOLD: begin
                        if (output_fire) begin
                            if (output_last_q) begin
                                cycle_count <= working_cycle_count_q + 1'b1;
                                done <= 1'b1;
                                output_last_q <= 1'b0;
                                state_q <= ST_IDLE;
                            end else begin
                                index_q <= index_q + 1'b1;
                                state_q <= ST_OUT_READ;
                            end
                        end
                    end

                    default: begin
                        error <= 1'b1;
                        error_code <= ERR_INTERNAL_RANGE;
                        state_q <= ST_IDLE;
                    end
                endcase
            end
        end
    end
endmodule
