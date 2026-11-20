`timescale 1ns/1ps

// One bit-exact IntegerRequantizer arithmetic lane.
//
// Arithmetic contract:
//   product = signed(value_in) * signed(multiplier_in)
//   bias    = shift_in == 0 ? 0 : 2**(shift_in - 1)
//   result  = sign(product) * ((abs(product) + bias) >> shift_in)
//
// This block intentionally contains no bias add, guard shift, saturation,
// QBN/membrane control, or parameter storage.
module pe_requant_lane #(
    parameter integer TAG_WIDTH = 16
) (
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         in_valid,
    output wire                         in_ready,
    input  wire signed [31:0]           value_in,
    input  wire signed [31:0]           multiplier_in,
    input  wire        [5:0]            shift_in,
    input  wire        [TAG_WIDTH-1:0]  tag_in,

    output wire                         out_valid,
    input  wire                         out_ready,
    output wire signed [63:0]           value_out,
    output wire        [TAG_WIDTH-1:0]  tag_out
);

    // The rigid pipeline is globally stalled when its output is valid but not
    // accepted.  This keeps arithmetic, valid, and tag state aligned and gives
    // II=1 whenever the downstream is ready.
    reg valid_s0;
    reg valid_s1;
    reg valid_s2;
    reg valid_s3;
    reg valid_s4;
    reg valid_s5;
    reg valid_s6;
    reg valid_s7;
    reg valid_s8;

    // S0: registered request and 16-bit limbs.
    reg signed [31:0] value_s0;
    reg signed [31:0] multiplier_s0;
    reg        [5:0]  shift_s0;
    reg [TAG_WIDTH-1:0] tag_s0;

    wire signed [15:0] value_hi_s0;
    wire signed [16:0] value_lo_s0;
    wire signed [15:0] multiplier_hi_s0;
    wire signed [16:0] multiplier_lo_s0;

    assign value_hi_s0      = value_s0[31:16];
    assign value_lo_s0      = {1'b0, value_s0[15:0]};
    assign multiplier_hi_s0 = multiplier_s0[31:16];
    assign multiplier_lo_s0 = {1'b0, multiplier_s0[15:0]};

    // S1: four narrow partial products.  These map independently to DSP48E1s
    // instead of creating an unpipelined four-DSP 32x32 cascade.
    reg signed [31:0] partial_hh_s1;
    reg signed [32:0] partial_hl_s1;
    reg signed [32:0] partial_lh_s1;
    reg signed [33:0] partial_ll_s1;
    reg        [5:0]  shift_s1;
    reg [TAG_WIDTH-1:0] tag_s1;

    // S2: cross-term addition.
    reg signed [31:0] partial_hh_s2;
    reg signed [33:0] cross_s2;
    reg signed [33:0] partial_ll_s2;
    reg        [5:0]  shift_s2;
    reg [TAG_WIDTH-1:0] tag_s2;

    // S3/S4: reconstruct the exact signed 64-bit 32x32 product.
    reg signed [63:0] high_cross_s3;
    reg signed [33:0] partial_ll_s3;
    reg        [5:0]  shift_s3;
    reg [TAG_WIDTH-1:0] tag_s3;

    reg signed [63:0] product_s4;
    reg        [5:0]  shift_s4;
    reg [TAG_WIDTH-1:0] tag_s4;

    // S5-S8: sign-symmetric rounding, variable shift, sign restoration.
    reg        [63:0] magnitude_s5;
    reg               negative_s5;
    reg        [5:0]  shift_s5;
    reg [TAG_WIDTH-1:0] tag_s5;

    reg        [63:0] rounded_magnitude_s6;
    reg               negative_s6;
    reg        [5:0]  shift_s6;
    reg [TAG_WIDTH-1:0] tag_s6;

    reg        [63:0] shifted_magnitude_s7;
    reg               negative_s7;
    reg [TAG_WIDTH-1:0] tag_s7;

    reg signed [63:0] result_s8;
    reg [TAG_WIDTH-1:0] tag_s8;

    wire pipeline_advance;
    wire [63:0] rounding_bias_s5;

    assign out_valid = valid_s8;
    assign value_out = result_s8;
    assign tag_out   = tag_s8;

    assign pipeline_advance = (~valid_s8) | out_ready;
    assign in_ready = rst_n & pipeline_advance;

    assign rounding_bias_s5 = (shift_s5 == 6'd0)
        ? 64'd0
        : (64'd1 << (shift_s5 - 6'd1));

    // rst_n is active-low and synchronous.  Synchronous reset allows Vivado to
    // use DSP48E1 pipeline registers; in_ready remains low while rst_n=0.
    always @(posedge clk) begin
        if (!rst_n) begin
            valid_s0 <= 1'b0;
            valid_s1 <= 1'b0;
            valid_s2 <= 1'b0;
            valid_s3 <= 1'b0;
            valid_s4 <= 1'b0;
            valid_s5 <= 1'b0;
            valid_s6 <= 1'b0;
            valid_s7 <= 1'b0;
            valid_s8 <= 1'b0;

            value_s0              <= 32'sd0;
            multiplier_s0         <= 32'sd0;
            shift_s0              <= 6'd0;
            tag_s0                <= {TAG_WIDTH{1'b0}};
            partial_hh_s1         <= 32'sd0;
            partial_hl_s1         <= 33'sd0;
            partial_lh_s1         <= 33'sd0;
            partial_ll_s1         <= 34'sd0;
            shift_s1              <= 6'd0;
            tag_s1                <= {TAG_WIDTH{1'b0}};
            partial_hh_s2         <= 32'sd0;
            cross_s2              <= 34'sd0;
            partial_ll_s2         <= 34'sd0;
            shift_s2              <= 6'd0;
            tag_s2                <= {TAG_WIDTH{1'b0}};
            high_cross_s3         <= 64'sd0;
            partial_ll_s3         <= 34'sd0;
            shift_s3              <= 6'd0;
            tag_s3                <= {TAG_WIDTH{1'b0}};
            product_s4            <= 64'sd0;
            shift_s4              <= 6'd0;
            tag_s4                <= {TAG_WIDTH{1'b0}};
            magnitude_s5          <= 64'd0;
            negative_s5           <= 1'b0;
            shift_s5              <= 6'd0;
            tag_s5                <= {TAG_WIDTH{1'b0}};
            rounded_magnitude_s6  <= 64'd0;
            negative_s6           <= 1'b0;
            shift_s6              <= 6'd0;
            tag_s6                <= {TAG_WIDTH{1'b0}};
            shifted_magnitude_s7  <= 64'd0;
            negative_s7           <= 1'b0;
            tag_s7                <= {TAG_WIDTH{1'b0}};
            result_s8             <= 64'sd0;
            tag_s8                <= {TAG_WIDTH{1'b0}};
        end else if (pipeline_advance) begin
            valid_s0 <= in_valid;
            valid_s1 <= valid_s0;
            valid_s2 <= valid_s1;
            valid_s3 <= valid_s2;
            valid_s4 <= valid_s3;
            valid_s5 <= valid_s4;
            valid_s6 <= valid_s5;
            valid_s7 <= valid_s6;
            valid_s8 <= valid_s7;

            // S0: registered request.
            value_s0      <= value_in;
            multiplier_s0 <= multiplier_in;
            shift_s0      <= shift_in;
            tag_s0        <= tag_in;

            // S1: A = ahi*2^16 + alo, B = bhi*2^16 + blo.
            partial_hh_s1 <= value_hi_s0 * multiplier_hi_s0;
            partial_hl_s1 <= value_hi_s0 * multiplier_lo_s0;
            partial_lh_s1 <= value_lo_s0 * multiplier_hi_s0;
            partial_ll_s1 <= value_lo_s0 * multiplier_lo_s0;
            shift_s1      <= shift_s0;
            tag_s1        <= tag_s0;

            // S2: cross = ahi*blo + alo*bhi.
            partial_hh_s2 <= partial_hh_s1;
            cross_s2      <= {partial_hl_s1[32], partial_hl_s1}
                           + {partial_lh_s1[32], partial_lh_s1};
            partial_ll_s2 <= partial_ll_s1;
            shift_s2      <= shift_s1;
            tag_s2        <= tag_s1;

            // S3/S4: product = hh*2^32 + cross*2^16 + ll.
            high_cross_s3 <= $signed({partial_hh_s2, 32'b0})
                           + $signed({{14{cross_s2[33]}}, cross_s2, 16'b0});
            partial_ll_s3 <= partial_ll_s2;
            shift_s3      <= shift_s2;
            tag_s3        <= tag_s2;

            product_s4 <= high_cross_s3
                        + $signed({32'b0, partial_ll_s3[31:0]});
            shift_s4   <= shift_s3;
            tag_s4     <= tag_s3;

            // S5: legal products are bounded by 2**61, so magnitude negation
            // cannot encounter INT64_MIN.
            negative_s5  <= product_s4[63];
            magnitude_s5 <= product_s4[63]
                ? (~product_s4 + 64'd1)
                : product_s4;
            shift_s5 <= shift_s4;
            tag_s5   <= tag_s4;

            // S6: round magnitude to nearest.  Sign restoration in S8 makes
            // exact half-way cases round away from zero symmetrically.
            rounded_magnitude_s6 <= magnitude_s5 + rounding_bias_s5;
            negative_s6          <= negative_s5;
            shift_s6             <= shift_s5;
            tag_s6               <= tag_s5;

            // S7: the magnitude is unsigned, hence logical right shift.
            shifted_magnitude_s7 <= rounded_magnitude_s6 >> shift_s6;
            negative_s7          <= negative_s6;
            tag_s7               <= tag_s6;

            // S8: restore product sign.  Negative zero naturally remains zero.
            result_s8 <= negative_s7
                ? -$signed(shifted_magnitude_s7)
                :  $signed(shifted_magnitude_s7);
            tag_s8 <= tag_s7;
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (TAG_WIDTH < 1) begin
            $fatal(1, "pe_requant_lane TAG_WIDTH must be at least one");
        end
    end

    always @(posedge clk) begin
        if (rst_n && in_valid && in_ready) begin
            if (shift_in > 6'd62) begin
                $fatal(1, "pe_requant_lane shift_in=%0d exceeds legal maximum 62", shift_in);
            end
            if (($signed(multiplier_in) < -32'sd1073741824)
                || ($signed(multiplier_in) > 32'sd1073741824)) begin
                $fatal(1, "pe_requant_lane multiplier is outside +/-2**30");
            end
        end
    end
`endif

endmodule

