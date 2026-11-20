`timescale 1ns/1ps

// Control and temporary state for the four-neuron-at-a-time membrane phase.
//
// Arithmetic ownership is deliberately external:
//   * the existing sixteen Hybrid MAC PEs form both raw membrane products;
//   * the existing four-lane Local RQ Bank requantizes cx and cellgate terms;
//   * Hybrid MAC MODE_DIRECT accumulates the two returned RQ terms; and
//   * the existing single gate postprocess instance performs final R8 and
//     signed INT8 saturation while this sequencer owns the shared resources.
//
// The sequencer contains no multiplier, requantizer, wide adder, or memory.
// GATE_DENOMINATOR is fixed at 255, so (255 - lambda) is exactly ~lambda for
// the unsigned eight-bit lambda domain and requires no subtractor.
module pe_membrane_sequencer #(
    parameter integer TAG_WIDTH = 16
) (
    input  wire                          clk,
    input  wire                          rst_n,

    input  wire                          start_valid,
    output wire                          start_ready,
    input  wire [15:0]                   lane_valid_in,
    input  wire [16*8-1:0]               i_t_in,
    input  wire [16*8-1:0]               u_prev_in,
    input  wire [16*8-1:0]               lambda_in,
    input  wire [16*32-1:0]              cx_multiplier_in,
    input  wire [16*6-1:0]               cx_shift_in,
    input  wire [16*32-1:0]              cell_multiplier_in,
    input  wire [16*6-1:0]               cell_shift_in,
    input  wire [16*TAG_WIDTH-1:0]       tag_in,

    // owner_grant covers the same sixteen PEs, the one Local RQ Bank, and the
    // one gate postprocess instance.  The arbiter must hold it until
    // owner_request drops.  postprocess_idle must cover pending input, every
    // internal pipeline valid, and the output register of that instance.
    output wire                          owner_request,
    input  wire                          owner_grant,
    input  wire                          postprocess_idle,

    // Controls and routed operands for the existing sixteen Hybrid MAC PEs.
    output reg  [15:0]                   pe_acc_clear,
    output reg  [15:0]                   pe_acc_enable,
    output reg  [1:0]                    pe_mode,
    output reg  [16*8-1:0]               pe_gate_u8,
    output reg  [16*8-1:0]               pe_operand_b,
    output reg  [16*32-1:0]              pe_direct_value,
    input  wire [16*32-1:0]              pe_accumulator,

    // Request/response connection to the existing four-lane Local RQ Bank.
    // Its tag width is TAG_WIDTH+3: {component, group[1:0], user_tag}.
    output reg                           rq_in_valid,
    input  wire                          rq_in_ready,
    output reg  [3:0]                    rq_in_lane_valid,
    output reg  [4*32-1:0]               rq_value_in,
    output reg  [4*32-1:0]               rq_multiplier_in,
    output reg  [4*6-1:0]                rq_shift_in,
    output reg  [4*(TAG_WIDTH+3)-1:0]    rq_tag_in,
    input  wire                          rq_out_valid,
    output wire                          rq_out_ready,
    input  wire [3:0]                    rq_out_lane_valid,
    input  wire [4*64-1:0]               rq_value_out,
    input  wire [4*(TAG_WIDTH+3)-1:0]    rq_tag_out,

    // Membrane-owned input stream to the existing pe_gate_postprocess.
    output reg                           post_in_valid,
    input  wire                          post_in_ready,
    output reg  [3:0]                    post_in_lane_valid,
    output reg  [4*64-1:0]               post_value_in,
    output reg                           post_component_in,
    output reg                           post_gate_in,
    output reg  [4*32-1:0]               post_bias_in,
    output reg  [4*TAG_WIDTH-1:0]        post_tag_in,
    input  wire                          post_out_valid,
    output wire                          post_out_ready,
    input  wire [3:0]                    post_out_lane_valid,
    input  wire [4*8-1:0]                post_value_out,
    input  wire                          post_gate_out,
    input  wire [4*TAG_WIDTH-1:0]        post_tag_out,

    output wire                          result_valid,
    input  wire                          result_ready,
    output wire [15:0]                   result_lane_valid,
    output wire [16*8-1:0]               result_value,
    output wire [16*TAG_WIDTH-1:0]       result_tag,

    output wire                          busy,
    output reg                           done,
    output wire                          protocol_error,
    output wire [3:0]                    phase,
    output reg  [7:0]                    rq_pending_mask
);

    localparam [1:0] MODE_GATE   = 2'd2;
    localparam [1:0] MODE_DIRECT = 2'd3;

    localparam RQ_COMPONENT_CX   = 1'b0;
    localparam RQ_COMPONENT_CELL = 1'b1;

    localparam POST_COMPONENT_INPUT     = 1'b0;
    localparam POST_COMPONENT_RECURRENT = 1'b1;

    localparam [3:0] S_IDLE         = 4'd0;
    localparam [3:0] S_ACQUIRE      = 4'd1;
    localparam [3:0] S_ISSUE_CX     = 4'd2;
    localparam [3:0] S_DRAIN_CX     = 4'd3;
    localparam [3:0] S_REQUEST_CX   = 4'd4;
    localparam [3:0] S_REQUEST_CELL = 4'd5;
    localparam [3:0] S_POSTPROCESS  = 4'd6;
    localparam [3:0] S_RESULT       = 4'd7;
    localparam [3:0] S_CLEAR_CELL   = 4'd8;
    localparam [3:0] S_ISSUE_CELL   = 4'd9;
    localparam [3:0] S_DRAIN_CELL   = 4'd10;

    reg [3:0] state;
    reg       resources_acquired;

    reg [15:0]                 lane_valid_r;
    reg [16*8-1:0]             i_t_r;
    reg [16*8-1:0]             u_prev_r;
    reg [16*8-1:0]             lambda_r;
    reg [16*32-1:0]            cx_multiplier_r;
    reg [16*6-1:0]             cx_shift_r;
    reg [16*32-1:0]            cell_multiplier_r;
    reg [16*6-1:0]             cell_shift_r;
    reg [16*TAG_WIDTH-1:0]     tag_r;

    reg [1:0] rq_request_group;
    reg [3:0] cell_request_mask;

    reg [3:0] cell_direct_pending;
    reg [3:0] final_sum_ready;

    reg [1:0] post_request_group;
    reg       post_request_component;
    reg       post_requests_complete;
    reg [2:0] post_response_count;

    reg [16*8-1:0] result_value_r;
    reg              control_error_r;
    reg [3:0]        rq_lane_error_r;
    reg [3:0]        post_lane_error_r;

    wire rq_in_fire;
    wire rq_out_fire;
    wire post_in_fire;
    wire post_out_fire;

    wire       rq_response_component;
    wire [1:0] rq_response_group;
    wire [2:0] rq_response_index;

    assign start_ready       = rst_n & (state == S_IDLE);
    assign owner_request     = (state != S_IDLE);
    assign busy              = (state != S_IDLE);
    assign phase             = state;

    // Result ownership is not released until the shared postprocess reports
    // completely empty after its last membrane output was accepted.
    assign result_valid      = (state == S_RESULT) & postprocess_idle;
    assign result_lane_valid = lane_valid_r;
    assign result_value      = result_value_r;
    assign result_tag        = tag_r;
    assign protocol_error    = control_error_r
        | (|rq_lane_error_r)
        | (|post_lane_error_r);

    assign rq_in_fire   = rq_in_valid & rq_in_ready;
    assign rq_out_fire  = rq_out_valid & rq_out_ready;
    assign post_in_fire = post_in_valid & post_in_ready;
    assign post_out_fire = post_out_valid & post_out_ready;

    assign rq_response_component =
        rq_tag_out[TAG_WIDTH + 2];
    assign rq_response_group =
        rq_tag_out[TAG_WIDTH +: 2];
    assign rq_response_index = {
        rq_response_component,
        rq_response_group
    };

    // Hold each CX response until the corresponding CELL raw accumulator has
    // been snapshotted.  Otherwise a nonzero requantized CX term can enter the
    // shared Hybrid accumulator before the CELL request samples its raw value.
    assign rq_out_ready = rq_out_valid
        ? (resources_acquired
           & rq_pending_mask[rq_response_index]
           & (rq_response_component
              | cell_request_mask[rq_response_group]))
        : 1'b0;

    // The sequencer always drains its four postprocess packets into the tile
    // result register; external result backpressure therefore cannot leave a
    // postprocess output pending during owner release.
    assign post_out_ready = resources_acquired
        & ((state == S_POSTPROCESS) | (state == S_RESULT))
        & (post_response_count < 3'd4);

    integer lane;
    integer selected_lane;
    integer group_base;
    reg [3:0] request_lane_mask;

    always @* begin
        pe_acc_clear      = 16'd0;
        pe_acc_enable     = 16'd0;
        pe_mode           = MODE_GATE;
        pe_gate_u8        = {16*8{1'b0}};
        pe_operand_b      = {16*8{1'b0}};
        pe_direct_value   = {16*32{1'b0}};

        rq_in_valid       = 1'b0;
        rq_in_lane_valid  = 4'd0;
        rq_value_in       = {4*32{1'b0}};
        rq_multiplier_in  = {4*32{1'b0}};
        rq_shift_in       = {4*6{1'b0}};
        rq_tag_in         = {4*(TAG_WIDTH+3){1'b0}};

        post_in_valid      = 1'b0;
        post_in_lane_valid = 4'd0;
        post_value_in      = {4*64{1'b0}};
        post_component_in  = post_request_component;
        post_gate_in       = 1'b0;
        post_bias_in       = {4*32{1'b0}};
        post_tag_in        = {4*TAG_WIDTH{1'b0}};

        request_lane_mask = 4'd0;
        group_base = rq_request_group * 4;

        // owner_grant and postprocess_idle are sampled on the same edge as
        // this early clear.  No DIRECT command can exist in S_ACQUIRE.
        if ((state == S_ACQUIRE) && owner_grant && postprocess_idle) begin
            pe_acc_clear = 16'hffff;
        end

        if (state == S_ISSUE_CX) begin
            pe_acc_enable = lane_valid_r;
            pe_mode = MODE_GATE;
            for (lane = 0; lane < 16; lane = lane + 1) begin
                pe_gate_u8[lane*8 +: 8] = lambda_r[lane*8 +: 8];
                pe_operand_b[lane*8 +: 8] = u_prev_r[lane*8 +: 8];
            end
        end

        // Separate the two raw phases.  All CELL products are issued only after
        // all four CX requests have entered the Local-RQ pipeline and the
        // previous accumulator contents have been cleared.
        if (state == S_ISSUE_CELL) begin
            pe_acc_enable = lane_valid_r;
            pe_mode = MODE_GATE;
            for (lane = 0; lane < 16; lane = lane + 1) begin
                pe_gate_u8[lane*8 +: 8] = ~lambda_r[lane*8 +: 8];
                pe_operand_b[lane*8 +: 8] = i_t_r[lane*8 +: 8];
            end
        end

        if (state == S_CLEAR_CELL)
            pe_acc_clear = lane_valid_r;

        // CX requests are followed immediately by CELL requests.  A group is
        // cleared only on the exact edge its old accumulator is accepted by
        // the Local RQ Bank.  The bank samples the pre-edge accumulator while
        // Hybrid MAC clear takes effect after the edge.
        if ((state == S_REQUEST_CX) || (state == S_REQUEST_CELL)) begin
            rq_in_valid = resources_acquired;
            request_lane_mask = lane_valid_r[group_base +: 4];
            rq_in_lane_valid = request_lane_mask;
            for (lane = 0; lane < 4; lane = lane + 1) begin
                selected_lane = group_base + lane;
                rq_value_in[lane*32 +: 32] =
                    pe_accumulator[selected_lane*32 +: 32];
                rq_tag_in[lane*(TAG_WIDTH+3) +: TAG_WIDTH+3] = {
                    (state == S_REQUEST_CELL),
                    rq_request_group,
                    tag_r[selected_lane*TAG_WIDTH +: TAG_WIDTH]
                };
                if (state == S_REQUEST_CX) begin
                    rq_multiplier_in[lane*32 +: 32] =
                        cx_multiplier_r[selected_lane*32 +: 32];
                    rq_shift_in[lane*6 +: 6] =
                        cx_shift_r[selected_lane*6 +: 6];
                end else begin
                    rq_multiplier_in[lane*32 +: 32] =
                        cell_multiplier_r[selected_lane*32 +: 32];
                    rq_shift_in[lane*6 +: 6] =
                        cell_shift_r[selected_lane*6 +: 6];
                end
            end
            if (rq_in_fire && (state == S_REQUEST_CELL)) begin
                pe_acc_clear[group_base +: 4] = 4'hf;
            end
        end

        // Returned RQ terms use only the existing Hybrid PE DIRECT bypass.
        // All final clears were performed with CELL requests, well before the
        // first response reaches this block.
        if (rq_out_fire) begin
            pe_mode = MODE_DIRECT;
            for (lane = 0; lane < 4; lane = lane + 1) begin
                selected_lane = rq_response_group * 4 + lane;
                pe_acc_enable[selected_lane] = rq_out_lane_valid[lane];
                pe_direct_value[selected_lane*32 +: 32] =
                    rq_value_out[lane*64 +: 32];
            end
        end

        // Each final PE sum is presented as INPUT, then paired with a zero
        // RECURRENT packet and zero bias.  This reuses the exact gate
        // postprocess equation for R8 and saturation without a second unit.
        if ((state == S_POSTPROCESS) && !post_requests_complete
            && final_sum_ready[post_request_group]) begin
            post_in_valid = resources_acquired;
            post_in_lane_valid =
                lane_valid_r[post_request_group*4 +: 4];
            post_component_in = post_request_component;
            for (lane = 0; lane < 4; lane = lane + 1) begin
                selected_lane = post_request_group * 4 + lane;
                post_tag_in[lane*TAG_WIDTH +: TAG_WIDTH] =
                    tag_r[selected_lane*TAG_WIDTH +: TAG_WIDTH];
                if (post_request_component == POST_COMPONENT_INPUT) begin
                    post_value_in[lane*64 +: 64] = {
                        {32{pe_accumulator[selected_lane*32 + 31]}},
                        pe_accumulator[selected_lane*32 +: 32]
                    };
                end
            end
        end
    end

    integer check_lane;
    integer response_lane;
    integer response_group_base;
    reg [2:0] request_index;

    always @(posedge clk) begin
        if (!rst_n) begin
            state                  <= S_IDLE;
            resources_acquired     <= 1'b0;
            lane_valid_r           <= 16'd0;
            i_t_r                  <= {16*8{1'b0}};
            u_prev_r               <= {16*8{1'b0}};
            lambda_r               <= {16*8{1'b0}};
            cx_multiplier_r        <= {16*32{1'b0}};
            cx_shift_r             <= {16*6{1'b0}};
            cell_multiplier_r      <= {16*32{1'b0}};
            cell_shift_r           <= {16*6{1'b0}};
            tag_r                  <= {16*TAG_WIDTH{1'b0}};
            rq_request_group       <= 2'd0;
            cell_request_mask      <= 4'd0;
            cell_direct_pending    <= 4'd0;
            final_sum_ready        <= 4'd0;
            post_request_group     <= 2'd0;
            post_request_component <= POST_COMPONENT_INPUT;
            post_requests_complete <= 1'b0;
            post_response_count    <= 3'd0;
            result_value_r         <= {16*8{1'b0}};
            done                   <= 1'b0;
            control_error_r        <= 1'b0;
            rq_lane_error_r        <= 4'd0;
            post_lane_error_r      <= 4'd0;
            rq_pending_mask        <= 8'd0;
        end else begin
            done <= 1'b0;

            // A CELL DIRECT command commits in the Hybrid PE on this edge;
            // make its group visible to postprocess starting next cycle.
            final_sum_ready     <= final_sum_ready | cell_direct_pending;
            cell_direct_pending <= 4'd0;

            if (resources_acquired && !owner_grant) begin
                control_error_r <= 1'b1;
            end

            if (rq_in_fire) begin
                request_index = {
                    (state == S_REQUEST_CELL),
                    rq_request_group
                };
                if (rq_pending_mask[request_index]) begin
                    control_error_r <= 1'b1;
                end
                rq_pending_mask[request_index] <= 1'b1;

                if (state == S_REQUEST_CELL)
                    cell_request_mask[rq_request_group] <= 1'b1;

                if (rq_request_group == 2'd3) begin
                    rq_request_group <= 2'd0;
                    if (state == S_REQUEST_CX) begin
                        state <= S_CLEAR_CELL;
                    end else begin
                        state <= S_POSTPROCESS;
                    end
                end else begin
                    rq_request_group <= rq_request_group + 2'd1;
                end
            end

            if (rq_out_fire) begin
                if (!rq_pending_mask[rq_response_index]) begin
                    control_error_r <= 1'b1;
                end
                rq_pending_mask[rq_response_index] <= 1'b0;

                response_group_base = rq_response_group * 4;
                for (response_lane = 0; response_lane < 4;
                     response_lane = response_lane + 1) begin
                    if (rq_out_lane_valid[response_lane]
                        != lane_valid_r[response_group_base + response_lane]) begin
                        rq_lane_error_r[response_lane] <= 1'b1;
                    end
                    if (rq_tag_out[response_lane*(TAG_WIDTH+3) + TAG_WIDTH]
                        != rq_response_group[0]
                        || rq_tag_out[response_lane*(TAG_WIDTH+3) + TAG_WIDTH + 1]
                        != rq_response_group[1]
                        || rq_tag_out[response_lane*(TAG_WIDTH+3) + TAG_WIDTH + 2]
                        != rq_response_component
                        || rq_tag_out[response_lane*(TAG_WIDTH+3) +: TAG_WIDTH]
                        != tag_r[(response_group_base+response_lane)*TAG_WIDTH
                                 +: TAG_WIDTH]) begin
                        rq_lane_error_r[response_lane] <= 1'b1;
                    end
                    if (rq_out_lane_valid[response_lane]
                        && (rq_value_out[response_lane*64 + 32 +: 32]
                            != {32{rq_value_out[response_lane*64 + 31]}})) begin
                        rq_lane_error_r[response_lane] <= 1'b1;
                    end
                end

                if (rq_response_component == RQ_COMPONENT_CELL) begin
                    cell_direct_pending[rq_response_group] <= 1'b1;
                end
            end

            if (post_in_fire) begin
                if (post_request_component == POST_COMPONENT_INPUT) begin
                    post_request_component <= POST_COMPONENT_RECURRENT;
                end else begin
                    post_request_component <= POST_COMPONENT_INPUT;
                    if (post_request_group == 2'd3) begin
                        post_requests_complete <= 1'b1;
                    end else begin
                        post_request_group <= post_request_group + 2'd1;
                    end
                end
            end

            if (post_out_fire) begin
                response_group_base = post_response_count[1:0] * 4;
                result_value_r[response_group_base*8 +: 4*8] <=
                    post_value_out;

                if (post_gate_out
                    || post_out_lane_valid
                       != lane_valid_r[response_group_base +: 4]) begin
                    control_error_r <= 1'b1;
                end
                for (check_lane = 0; check_lane < 4;
                     check_lane = check_lane + 1) begin
                    if (post_tag_out[check_lane*TAG_WIDTH +: TAG_WIDTH]
                        != tag_r[(response_group_base+check_lane)*TAG_WIDTH
                                 +: TAG_WIDTH]) begin
                        post_lane_error_r[check_lane] <= 1'b1;
                    end
                end

                if (post_response_count == 3'd3) begin
                    post_response_count <= 3'd4;
                    state <= S_RESULT;
                end else begin
                    post_response_count <= post_response_count + 3'd1;
                end
            end

            case (state)
                S_IDLE: begin
                    if (start_valid) begin
                        lane_valid_r       <= lane_valid_in;
                        i_t_r              <= i_t_in;
                        u_prev_r           <= u_prev_in;
                        lambda_r           <= lambda_in;
                        cx_multiplier_r    <= cx_multiplier_in;
                        cx_shift_r         <= cx_shift_in;
                        cell_multiplier_r  <= cell_multiplier_in;
                        cell_shift_r       <= cell_shift_in;
                        tag_r              <= tag_in;
                        rq_request_group   <= 2'd0;
                        cell_request_mask  <= 4'd0;
                        cell_direct_pending <= 4'd0;
                        final_sum_ready    <= 4'd0;
                        post_request_group <= 2'd0;
                        post_request_component <= POST_COMPONENT_INPUT;
                        post_requests_complete <= 1'b0;
                        post_response_count <= 3'd0;
                        result_value_r     <= {16*8{1'b0}};
                        rq_pending_mask    <= 8'd0;
                        control_error_r    <= 1'b0;
                        rq_lane_error_r    <= 4'd0;
                        post_lane_error_r  <= 4'd0;
                        state              <= S_ACQUIRE;
                    end
                end

                S_ACQUIRE: begin
                    if (owner_grant && postprocess_idle) begin
                        resources_acquired <= 1'b1;
                        state <= S_ISSUE_CX;
                    end
                end

                S_ISSUE_CX: begin
                    state <= S_DRAIN_CX;
                end

                S_DRAIN_CX: begin
                    state <= S_REQUEST_CX;
                end

                S_CLEAR_CELL: begin
                    state <= S_ISSUE_CELL;
                end

                S_ISSUE_CELL: begin
                    state <= S_DRAIN_CELL;
                end

                S_DRAIN_CELL: begin
                    state <= S_REQUEST_CELL;
                end

                S_RESULT: begin
                    if (result_valid && result_ready) begin
                        resources_acquired <= 1'b0;
                        done <= 1'b1;
                        state <= S_IDLE;
                    end
                end

                default: begin
                    // Request and postprocess states advance on handshakes in
                    // the logic above.
                end
            endcase
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (TAG_WIDTH < 1) begin
            $fatal(1, "pe_membrane_sequencer TAG_WIDTH must be at least one");
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            if ((pe_acc_clear & pe_acc_enable) != 16'd0) begin
                $fatal(1, "pe_membrane_sequencer clear/DIRECT-or-GATE collision");
            end
            if (resources_acquired && !owner_grant) begin
                $fatal(1, "pe_membrane_sequencer owner grant withdrawn");
            end
            if ((state == S_ACQUIRE) && owner_grant
                && !postprocess_idle && (pe_acc_clear != 16'd0)) begin
                $fatal(1, "pe_membrane_sequencer acquired non-idle postprocess");
            end
        end
    end
`endif

endmodule
