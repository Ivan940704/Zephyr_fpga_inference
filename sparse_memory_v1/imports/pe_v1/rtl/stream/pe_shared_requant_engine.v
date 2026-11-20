`timescale 1ns/1ps

// One physical requantization lane shared by serialized QBN and Linear data.
//
// Arithmetic contract for both operation kinds:
//   rq      = pe_requant_lane(value_in, multiplier_in, shift_in)
//   sum     = signed64(rq) + sign_extend_64(bias_in)
//   rounded = sign(sum) * ((abs(sum) + 128) >> 8)
//   result  = saturate(rounded, -127, 127)
//
// op_kind uses 1'b0 for QBN and 1'b1 for Linear, and is opaque control
// metadata in this checkpoint.  It is retained at
// the output so downstream control can distinguish QBN from Linear results;
// it does not select a second datapath.  CDF is intentionally outside scope.
//
// The postprocess pipeline and its metadata use one common clock enable.  An
// output stall therefore holds every occupied postprocess stage stable and
// backpressures the sole pe_requant_lane.  There is no FIFO, scoreboard,
// parameter memory, or second requantization datapath.
module pe_shared_requant_engine #(
    parameter integer INDEX_WIDTH = 9,
    parameter integer TAG_WIDTH   = 16
) (
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         in_valid,
    output wire                         in_ready,
    input  wire signed [31:0]           value_in,
    input  wire                         op_kind_in,
    input  wire signed [31:0]           multiplier_in,
    input  wire        [5:0]            shift_in,
    input  wire signed [31:0]           bias_in,
    input  wire        [INDEX_WIDTH-1:0] index_in,
    input  wire        [TAG_WIDTH-1:0]  tag_in,
    input  wire                         last_in,

    output wire                         out_valid,
    input  wire                         out_ready,
    output wire signed [7:0]            value_out,
    output wire                         op_kind_out,
    output wire        [INDEX_WIDTH-1:0] index_out,
    output wire        [TAG_WIDTH-1:0]  tag_out,
    output wire                         last_out
);

    localparam integer RQ_TAG_WIDTH = 1 + 32 + INDEX_WIDTH + TAG_WIDTH + 1;
    localparam integer POST_META_WIDTH = 1 + INDEX_WIDTH + TAG_WIDTH + 1;

    localparam integer RQ_LAST_LSB  = 0;
    localparam integer RQ_USER_LSB  = RQ_LAST_LSB + 1;
    localparam integer RQ_INDEX_LSB = RQ_USER_LSB + TAG_WIDTH;
    localparam integer RQ_BIAS_LSB  = RQ_INDEX_LSB + INDEX_WIDTH;
    localparam integer RQ_OP_LSB    = RQ_BIAS_LSB + 32;

    localparam integer POST_LAST_LSB  = 0;
    localparam integer POST_USER_LSB  = POST_LAST_LSB + 1;
    localparam integer POST_INDEX_LSB = POST_USER_LSB + TAG_WIDTH;
    localparam integer POST_OP_LSB    = POST_INDEX_LSB + INDEX_WIDTH;

    wire                         rq_in_ready;
    wire                         rq_out_valid;
    wire                         rq_out_ready;
    wire signed [63:0]           rq_value_out;
    wire [RQ_TAG_WIDTH-1:0]      rq_tag_out;
    wire signed [63:0]           rq_bias_extended;
    wire signed [63:0]           rq_sum;
    wire [POST_META_WIDTH-1:0]   rq_post_meta;

    reg                          valid_p0;
    reg                          valid_p1;
    reg                          valid_p2;
    reg                          valid_p3;
    reg                          valid_p4;

    reg signed [63:0]            sum_p0;
    reg [POST_META_WIDTH-1:0]    meta_p0;

    reg        [63:0]            magnitude_p1;
    reg                          negative_p1;
    reg [POST_META_WIDTH-1:0]    meta_p1;

    reg        [55:0]            rounded_magnitude_p2;
    reg                          negative_p2;
    reg [POST_META_WIDTH-1:0]    meta_p2;

    reg        [6:0]             saturated_magnitude_p3;
    reg                          negative_p3;
    reg [POST_META_WIDTH-1:0]    meta_p3;

    reg signed [7:0]             result_p4;
    reg [POST_META_WIDTH-1:0]    meta_p4;

    wire                         post_advance;

    assign in_ready = rq_in_ready;

    assign out_valid = rst_n && valid_p4;
    assign value_out = result_p4;
    assign last_out = meta_p4[POST_LAST_LSB];
    assign tag_out = meta_p4[POST_USER_LSB +: TAG_WIDTH];
    assign index_out = meta_p4[POST_INDEX_LSB +: INDEX_WIDTH];
    assign op_kind_out = meta_p4[POST_OP_LSB];

    assign post_advance = (~valid_p4) | out_ready;
    assign rq_out_ready = rst_n && post_advance;

    assign rq_bias_extended = {
        {32{rq_tag_out[RQ_BIAS_LSB + 31]}},
        rq_tag_out[RQ_BIAS_LSB +: 32]
    };
    assign rq_sum = rq_value_out + rq_bias_extended;
    assign rq_post_meta = {
        rq_tag_out[RQ_OP_LSB],
        rq_tag_out[RQ_INDEX_LSB +: INDEX_WIDTH],
        rq_tag_out[RQ_USER_LSB +: TAG_WIDTH],
        rq_tag_out[RQ_LAST_LSB]
    };

    // Exactly one physical baseline requant lane.  The operation kind and all
    // postprocess metadata travel in its opaque tag and cannot be reordered.
    pe_requant_lane #(
        .TAG_WIDTH(RQ_TAG_WIDTH)
    ) u_requant_lane (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_ready(rq_in_ready),
        .value_in(value_in),
        .multiplier_in(multiplier_in),
        .shift_in(shift_in),
        .tag_in({op_kind_in, bias_in, index_in, tag_in, last_in}),
        .out_valid(rq_out_valid),
        .out_ready(rq_out_ready),
        .value_out(rq_value_out),
        .tag_out(rq_tag_out)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            valid_p0 <= 1'b0;
            valid_p1 <= 1'b0;
            valid_p2 <= 1'b0;
            valid_p3 <= 1'b0;
            valid_p4 <= 1'b0;

            sum_p0       <= 64'sd0;
            meta_p0      <= {POST_META_WIDTH{1'b0}};
            magnitude_p1 <= 64'd0;
            negative_p1  <= 1'b0;
            meta_p1      <= {POST_META_WIDTH{1'b0}};
            rounded_magnitude_p2 <= 56'd0;
            negative_p2  <= 1'b0;
            meta_p2      <= {POST_META_WIDTH{1'b0}};
            saturated_magnitude_p3 <= 7'd0;
            negative_p3  <= 1'b0;
            meta_p3      <= {POST_META_WIDTH{1'b0}};
            result_p4    <= 8'sd0;
            meta_p4      <= {POST_META_WIDTH{1'b0}};
        end else if (post_advance) begin
            valid_p0 <= rq_out_valid;
            valid_p1 <= valid_p0;
            valid_p2 <= valid_p1;
            valid_p3 <= valid_p2;
            valid_p4 <= valid_p3;

            // P0: add the operation-specific signed INT32 bias in INT64.
            sum_p0  <= rq_sum;
            meta_p0 <= rq_post_meta;

            // P1: separate sign and magnitude for symmetric rounding.
            negative_p1 <= sum_p0[63];
            magnitude_p1 <= sum_p0[63]
                ? (~sum_p0 + 64'd1)
                : sum_p0;
            meta_p1 <= meta_p0;

            // P2: fixed guard shift R8, round-nearest with ties away from zero.
            rounded_magnitude_p2 <= (magnitude_p1 + 64'd128) >> 8;
            negative_p2 <= negative_p1;
            meta_p2 <= meta_p1;

            // P3: clamp magnitude.  This stage is separate from sign restore
            // so the saturation compare remains a 200 MHz path.
            if (rounded_magnitude_p2 > 56'd127) begin
                saturated_magnitude_p3 <= 7'd127;
            end else begin
                saturated_magnitude_p3 <= rounded_magnitude_p2[6:0];
            end
            negative_p3 <= negative_p2;
            meta_p3 <= meta_p2;

            // P4: restore sign.  The formal activation domain excludes -128.
            result_p4 <= negative_p3
                ? -$signed({1'b0, saturated_magnitude_p3})
                :  $signed({1'b0, saturated_magnitude_p3});
            meta_p4 <= meta_p3;
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (INDEX_WIDTH < 1) begin
            $fatal(1, "pe_shared_requant_engine INDEX_WIDTH must be positive");
        end
        if (TAG_WIDTH < 1) begin
            $fatal(1, "pe_shared_requant_engine TAG_WIDTH must be positive");
        end
    end
`endif

endmodule
