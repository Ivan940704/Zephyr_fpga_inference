`timescale 1ns/1ps

// Pair four-lane input/recurrent requant results and convert them to the
// upstream signed INT8 gate domain.  Requantization is performed exclusively
// by the upstream pe_local_requant_bank_4lane; this module contains only
// add/round/saturate logic.
//
// Packet protocol:
//   1. one INPUT packet is accepted and held in the one-deep pending register;
//   2. the immediately following accepted packet is RECURRENT with identical
//      gate, lane mask, and active-lane tags;
//   3. one four-lane completed gate packet is produced.
//
// rq_bias_in is meaningful on the RECURRENT packet.  The fixed guard shift is
// eight bits and uses sign-symmetric round-to-nearest with ties away from zero.
module pe_gate_postprocess #(
    parameter integer TAG_WIDTH = 16
) (
    input  wire                          clk,
    input  wire                          rst_n,

    input  wire                          rq_in_valid,
    output wire                          rq_in_ready,
    input  wire [3:0]                    rq_lane_valid,
    input  wire [4*64-1:0]               rq_value_in,
    input  wire                          rq_component_in,
    input  wire                          rq_gate_in,
    input  wire [4*32-1:0]               rq_bias_in,
    input  wire [4*TAG_WIDTH-1:0]        rq_tag_in,

    output wire                          out_valid,
    input  wire                          out_ready,
    output wire [3:0]                    out_lane_valid,
    output wire [4*8-1:0]                out_value,
    output wire                          out_gate,
    output wire [4*TAG_WIDTH-1:0]        out_tag
);

    localparam COMPONENT_INPUT     = 1'b0;
    localparam COMPONENT_RECURRENT = 1'b1;

    reg                         pending_valid;
    reg [3:0]                   pending_lane_valid;
    reg [4*64-1:0]              pending_value;
    reg                         pending_gate;
    reg [4*TAG_WIDTH-1:0]       pending_tag;

    reg                         pair_valid;
    reg [3:0]                   pair_lane_valid;
    reg [4*64-1:0]              pair_sum;
    reg [4*32-1:0]              pair_bias;
    reg                         pair_gate;
    reg [4*TAG_WIDTH-1:0]       pair_tag;

    reg                         biased_valid;
    reg [3:0]                   biased_lane_valid;
    reg [4*64-1:0]              biased_sum;
    reg                         biased_gate;
    reg [4*TAG_WIDTH-1:0]       biased_tag;

    reg                         magnitude_valid;
    reg [3:0]                   magnitude_lane_valid;
    reg [4*64-1:0]              magnitude_value;
    reg [3:0]                   magnitude_negative;
    reg                         magnitude_gate;
    reg [4*TAG_WIDTH-1:0]       magnitude_tag;

    reg                         rounded_valid;
    reg [3:0]                   rounded_lane_valid;
    reg [4*56-1:0]              rounded_magnitude;
    reg [3:0]                   rounded_negative;
    reg                         rounded_gate;
    reg [4*TAG_WIDTH-1:0]       rounded_tag;

    reg                         out_valid_r;
    reg [3:0]                   out_lane_valid_r;
    reg [4*8-1:0]               out_value_r;
    reg                         out_gate_r;
    reg [4*TAG_WIDTH-1:0]       out_tag_r;

    // A stalled output freezes the whole short pipeline and backpressures the
    // Local RQ Bank.  This preserves every packet and all pairing metadata.
    wire pipeline_enable;
    assign pipeline_enable = ~out_valid_r | out_ready;

    // Component identity participates in readiness so malformed ordering is
    // never consumed.  Gate/mask/tag agreement is a required upstream
    // protocol and is checked by simulation assertions below.
    assign rq_in_ready = rst_n
        & pipeline_enable
        & ((!pending_valid & (rq_component_in == COMPONENT_INPUT))
           | (pending_valid & (rq_component_in == COMPONENT_RECURRENT)));

    assign out_valid      = out_valid_r;
    assign out_lane_valid = out_lane_valid_r;
    assign out_value      = out_value_r;
    assign out_gate       = out_gate_r;
    assign out_tag        = out_tag_r;

    integer lane;
    always @(posedge clk) begin
        if (!rst_n) begin
            pending_valid        <= 1'b0;
            pair_valid           <= 1'b0;
            biased_valid         <= 1'b0;
            magnitude_valid      <= 1'b0;
            rounded_valid        <= 1'b0;
            out_valid_r          <= 1'b0;
            out_lane_valid_r     <= 4'b0000;
            out_value_r          <= 32'd0;
            out_gate_r           <= 1'b0;
            out_tag_r            <= {4*TAG_WIDTH{1'b0}};
        end else if (pipeline_enable) begin
            // Output/saturation stage.  rounded_magnitude is unsigned and the
            // sign is restored only after the fixed guard rounding.
            out_valid_r      <= rounded_valid;
            out_lane_valid_r <= rounded_lane_valid;
            out_gate_r       <= rounded_gate;
            out_tag_r        <= rounded_tag;
            for (lane = 0; lane < 4; lane = lane + 1) begin
                if (rounded_magnitude[lane*56 +: 56] > 56'd127) begin
                    out_value_r[lane*8 +: 8] <= rounded_negative[lane]
                        ? -8'sd127 : 8'sd127;
                end else if (rounded_negative[lane]) begin
                    out_value_r[lane*8 +: 8] <=
                        -$signed(rounded_magnitude[lane*56 +: 8]);
                end else begin
                    out_value_r[lane*8 +: 8] <=
                        rounded_magnitude[lane*56 +: 8];
                end
            end

            // Fixed guard shift: (abs(sum) + 128) >> 8.
            rounded_valid        <= magnitude_valid;
            rounded_lane_valid   <= magnitude_lane_valid;
            rounded_negative     <= magnitude_negative;
            rounded_gate         <= magnitude_gate;
            rounded_tag          <= magnitude_tag;
            for (lane = 0; lane < 4; lane = lane + 1) begin
                rounded_magnitude[lane*56 +: 56] <=
                    (magnitude_value[lane*64 +: 64] + 64'd128) >> 8;
            end

            // Sign/magnitude stage.  A 64-bit unsigned magnitude represents
            // abs(INT64_MIN) exactly, although real GSU parameters are far
            // inside that boundary.
            magnitude_valid      <= biased_valid;
            magnitude_lane_valid <= biased_lane_valid;
            magnitude_gate       <= biased_gate;
            magnitude_tag        <= biased_tag;
            for (lane = 0; lane < 4; lane = lane + 1) begin
                magnitude_negative[lane] <= biased_sum[lane*64 + 63];
                if (biased_sum[lane*64 + 63]) begin
                    magnitude_value[lane*64 +: 64] <=
                        (~biased_sum[lane*64 +: 64]) + 64'd1;
                end else begin
                    magnitude_value[lane*64 +: 64] <=
                        biased_sum[lane*64 +: 64];
                end
            end

            // Bias is signed INT32 and is added after both signed INT64 RQ
            // results, matching the upstream torch.int64 expression order.
            biased_valid      <= pair_valid;
            biased_lane_valid <= pair_lane_valid;
            biased_gate       <= pair_gate;
            biased_tag        <= pair_tag;
            for (lane = 0; lane < 4; lane = lane + 1) begin
                biased_sum[lane*64 +: 64] <=
                    $signed(pair_sum[lane*64 +: 64])
                    + $signed({{32{pair_bias[lane*32 + 31]}},
                               pair_bias[lane*32 +: 32]});
            end

            // The pair stage is normally a bubble on INPUT cycles and valid
            // on RECURRENT cycles, giving one completed output per two input
            // packets without a general scoreboard.
            pair_valid <= 1'b0;
            if (rq_in_valid & rq_in_ready) begin
                if (rq_component_in == COMPONENT_INPUT) begin
                    pending_valid      <= 1'b1;
                    pending_lane_valid <= rq_lane_valid;
                    pending_value      <= rq_value_in;
                    pending_gate       <= rq_gate_in;
                    pending_tag        <= rq_tag_in;
                end else begin
                    pending_valid  <= 1'b0;
                    pair_valid     <= 1'b1;
                    pair_lane_valid <= pending_lane_valid;
                    pair_bias      <= rq_bias_in;
                    pair_gate      <= pending_gate;
                    pair_tag       <= pending_tag;
                    for (lane = 0; lane < 4; lane = lane + 1) begin
                        pair_sum[lane*64 +: 64] <=
                            $signed(pending_value[lane*64 +: 64])
                            + $signed(rq_value_in[lane*64 +: 64]);
                    end
                end
            end
        end
    end

`ifndef SYNTHESIS
    integer check_lane;
    initial begin
        if (TAG_WIDTH < 1) begin
            $fatal(1, "pe_gate_postprocess TAG_WIDTH must be at least one");
        end
    end

    always @(posedge clk) begin
        if (rst_n && rq_in_valid && pipeline_enable) begin
            if (!pending_valid && rq_component_in != COMPONENT_INPUT) begin
                $fatal(1, "pe_gate_postprocess expected INPUT component");
            end
            if (pending_valid && rq_component_in != COMPONENT_RECURRENT) begin
                $fatal(1, "pe_gate_postprocess expected RECURRENT component");
            end
            if (pending_valid && rq_component_in == COMPONENT_RECURRENT) begin
                if (rq_gate_in != pending_gate) begin
                    $fatal(1, "pe_gate_postprocess gate mismatch");
                end
                if (rq_lane_valid != pending_lane_valid) begin
                    $fatal(1, "pe_gate_postprocess lane-mask mismatch");
                end
                for (check_lane = 0; check_lane < 4;
                     check_lane = check_lane + 1) begin
                    if (pending_lane_valid[check_lane]
                        && rq_tag_in[check_lane*TAG_WIDTH +: TAG_WIDTH]
                           != pending_tag[check_lane*TAG_WIDTH +: TAG_WIDTH]) begin
                        $fatal(1, "pe_gate_postprocess active-lane tag mismatch");
                    end
                end
            end
        end
    end
`endif

endmodule
