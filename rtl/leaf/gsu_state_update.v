`timescale 1ns/1ps

// Bit-oriented GSU state update after sigmoid lookup.
module gsu_state_update #(
    parameter GATE_DENOMINATOR = 255,
    parameter GUARD_BITS = 8
) (
    input  wire        [7:0]  forget_u8,
    input  wire signed [7:0]  previous_state_q,
    input  wire signed [7:0]  cellgate_q,
    input  wire signed [31:0] previous_multiplier,
    input  wire        [5:0]  previous_shift,
    input  wire signed [31:0] cellgate_multiplier,
    input  wire        [5:0]  cellgate_shift,
    input  wire signed [31:0] bn_multiplier,
    input  wire        [5:0]  bn_shift,
    input  wire signed [31:0] bn_bias_q,
    output wire signed [7:0]  state_pre_q,
    output wire signed [7:0]  state_q,
    output wire               spike_q,
    output wire               state_pre_clipped,
    output wire               state_clipped
);
    wire signed [16:0] previous_term;
    wire signed [16:0] cellgate_term;
    wire signed [16:0] forget_extended;
    wire signed [16:0] inverse_forget_extended;
    wire signed [16:0] previous_state_extended;
    wire signed [16:0] cellgate_extended;
    wire        [8:0]  inverse_forget;
    wire signed [31:0] previous_term_32;
    wire signed [31:0] cellgate_term_32;
    wire signed [63:0] previous_requant;
    wire signed [63:0] cellgate_requant;
    wire signed [63:0] state_pre_guarded;
    wire signed [63:0] state_pre_unclamped;
    wire signed [31:0] state_pre_32;
    wire signed [63:0] bn_requant;
    wire signed [63:0] bn_bias_extended;
    wire signed [63:0] state_guarded;
    wire signed [63:0] state_unclamped;
    localparam [5:0] GUARD_SHIFT = GUARD_BITS;

    assign inverse_forget = GATE_DENOMINATOR - forget_u8;
    assign forget_extended = $signed({9'd0, forget_u8});
    assign inverse_forget_extended = $signed({8'd0, inverse_forget});
    assign previous_state_extended = {{9{previous_state_q[7]}}, previous_state_q};
    assign cellgate_extended = {{9{cellgate_q[7]}}, cellgate_q};
    assign previous_term = forget_extended * previous_state_extended;
    assign cellgate_term = inverse_forget_extended * cellgate_extended;
    assign previous_term_32 = {{15{previous_term[16]}}, previous_term};
    assign cellgate_term_32 = {{15{cellgate_term[16]}}, cellgate_term};
    assign state_pre_guarded = previous_requant + cellgate_requant;
    assign state_pre_32 = {{24{state_pre_q[7]}}, state_pre_q};
    assign bn_bias_extended = {{32{bn_bias_q[31]}}, bn_bias_q};
    assign state_guarded = bn_requant + bn_bias_extended;
    assign spike_q = ~state_q[7];

    integer_requantizer previous_rq (
        .value_in(previous_term_32),
        .multiplier(previous_multiplier),
        .right_shift(previous_shift),
        .value_out(previous_requant)
    );

    integer_requantizer cellgate_rq (
        .value_in(cellgate_term_32),
        .multiplier(cellgate_multiplier),
        .right_shift(cellgate_shift),
        .value_out(cellgate_requant)
    );

    signed_round_shift #(.WIDTH(64), .SHIFT_WIDTH(6)) state_pre_guard_shift (
        .value_in(state_pre_guarded),
        .shift(GUARD_SHIFT),
        .value_out(state_pre_unclamped)
    );

    saturate_int8 #(.INPUT_WIDTH(64)) saturate_state_pre (
        .value_in(state_pre_unclamped),
        .value_out(state_pre_q),
        .clipped(state_pre_clipped)
    );

    integer_requantizer bn_rq (
        .value_in(state_pre_32),
        .multiplier(bn_multiplier),
        .right_shift(bn_shift),
        .value_out(bn_requant)
    );

    signed_round_shift #(.WIDTH(64), .SHIFT_WIDTH(6)) state_guard_shift (
        .value_in(state_guarded),
        .shift(GUARD_SHIFT),
        .value_out(state_unclamped)
    );

    saturate_int8 #(.INPUT_WIDTH(64)) saturate_state (
        .value_in(state_unclamped),
        .value_out(state_q),
        .clipped(state_clipped)
    );
endmodule
