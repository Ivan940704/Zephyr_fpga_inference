`timescale 1ns/1ps

// One bit-exact integer GSN/GSU neuron below the matrix-accumulator boundary.
// Seven requant operations share one physical pe_requant_lane. Membrane
// products reuse one pe_hybrid_mac. Only one neuron transaction is in flight.
module pe_gsn_cell #(
    parameter integer TAG_WIDTH = 10,
    parameter integer GUARD_BITS = 8,
    parameter integer GATE_DENOMINATOR = 255
) (
    input  wire clk,
    input  wire rst_n,

    input  wire start_valid,
    output wire start_ready,
    input  wire signed [31:0] input_acc,
    input  wire signed [31:0] recurrent_acc,
    input  wire signed [7:0] previous_state_q,

    input  wire signed [31:0] forget_input_multiplier,
    input  wire        [5:0]  forget_input_shift,
    input  wire signed [31:0] forget_recurrent_multiplier,
    input  wire        [5:0]  forget_recurrent_shift,
    input  wire signed [31:0] forget_bias_q,

    input  wire signed [31:0] cell_input_multiplier,
    input  wire        [5:0]  cell_input_shift,
    input  wire signed [31:0] cell_recurrent_multiplier,
    input  wire        [5:0]  cell_recurrent_shift,
    input  wire signed [31:0] cell_bias_q,

    input  wire signed [31:0] previous_multiplier,
    input  wire        [5:0]  previous_shift,
    input  wire signed [31:0] cellgate_multiplier,
    input  wire        [5:0]  cellgate_shift,
    input  wire signed [31:0] bn_multiplier,
    input  wire        [5:0]  bn_shift,
    input  wire signed [31:0] bn_bias_q,
    input  wire        [TAG_WIDTH-1:0] tag_in,

    input  wire cfg_we,
    input  wire [7:0] cfg_addr,
    input  wire [7:0] cfg_data,

    output wire result_valid,
    input  wire result_ready,
    output wire signed [7:0] forget_q,
    output wire signed [7:0] cellgate_q,
    output wire        [7:0] forget_lambda_u8,
    output wire signed [7:0] state_pre_q,
    output wire signed [7:0] state_q,
    output wire spike_q,
    output wire forget_clipped,
    output wire cellgate_clipped,
    output wire state_pre_clipped,
    output wire state_clipped,
    output wire [TAG_WIDTH-1:0] tag_out,
    output wire busy
);
    localparam [5:0] S_IDLE=0,
      S_F_IN_REQ=1, S_F_IN_WAIT=2, S_F_REC_REQ=3, S_F_REC_WAIT=4,
      S_F_ADD_RQ=5, S_F_ADD_BIAS=6, S_F_MAG=7, S_F_ROUND=8,
      S_F_SAT=9, S_C_IN_REQ=10, S_C_IN_WAIT=11, S_C_REC_REQ=12,
      S_C_REC_WAIT=13, S_C_ADD_RQ=14, S_C_ADD_BIAS=15, S_C_MAG=16,
      S_C_ROUND=17, S_C_SAT=18, S_LUT_REQ=19, S_LUT_WAIT=20,
      S_CX_CLEAR=21, S_CX_ISSUE=22, S_CX_DRAIN=23, S_CX_CAPTURE=24,
      S_CX_RQ_REQ=25, S_CX_RQ_WAIT=26, S_CELL_CLEAR=27,
      S_CELL_ISSUE=28, S_CELL_DRAIN=29, S_CELL_CAPTURE=30,
      S_CELL_RQ_REQ=31, S_CELL_RQ_WAIT=32, S_PRE_ADD=33,
      S_PRE_MAG=34, S_PRE_ROUND=35, S_PRE_SAT=36, S_BN_REQ=37,
      S_BN_WAIT=38, S_BN_ADD=39, S_BN_MAG=40, S_BN_ROUND=41,
      S_STATE_SAT=42, S_RESULT=43, S_F_ADD_BIAS_DO=44,
      S_C_ADD_BIAS_DO=45;

    reg [5:0] state;
    reg signed [31:0] input_acc_r, recurrent_acc_r;
    reg signed [7:0] previous_state_r;
    reg signed [31:0] f_im_r,f_rm_r,f_bias_r,c_im_r,c_rm_r,c_bias_r;
    reg signed [31:0] prev_m_r,cell_m_r,bn_m_r,bn_bias_r;
    reg [5:0] f_is_r,f_rs_r,c_is_r,c_rs_r,prev_s_r,cell_s_r,bn_s_r;
    reg [TAG_WIDTH-1:0] tag_r;

    reg signed [63:0] f_input_rq,f_recurrent_rq,c_input_rq,c_recurrent_rq;
    reg signed [63:0] cx_rq,cell_rq,bn_rq;
    // The final fixed-point post-processing is deliberately split across
    // registers.  Each stage contains at most one 64-bit carry chain, which
    // avoids the long add/absolute/round/saturate path of the first draft.
    reg signed [63:0] arithmetic_r;
    reg signed [63:0] add_lhs_r,add_rhs_r;
    reg        [63:0] magnitude_r;
    reg        [55:0] rounded_magnitude_r;
    reg               negative_r;
    reg signed [31:0] cx_term,cell_term;
    reg signed [7:0] forget_r,cellgate_r,state_pre_r,state_r;
    reg [7:0] lambda_r;
    reg spike_r,forget_clip_r,cell_clip_r,pre_clip_r,state_clip_r;

    reg rq_in_valid;
    wire rq_in_ready,rq_out_valid;
    reg signed [31:0] rq_value;
    reg signed [31:0] rq_multiplier;
    reg [5:0] rq_shift;
    wire signed [63:0] rq_result;

    reg mac_clear,mac_enable;
    reg [7:0] mac_gate_r;
    reg signed [7:0] mac_operand_r;
    wire signed [31:0] mac_accumulator;
    wire mac_overflow;

    reg lut_in_valid;
    wire lut_in_ready,lut_out_valid;
    wire [7:0] lut_lambda;

    assign start_ready = (state == S_IDLE) & rst_n;
    assign result_valid = (state == S_RESULT);
    assign busy = (state != S_IDLE);
    assign forget_q=forget_r; assign cellgate_q=cellgate_r;
    assign forget_lambda_u8=lambda_r; assign state_pre_q=state_pre_r;
    assign state_q=state_r; assign spike_q=spike_r;
    assign forget_clipped=forget_clip_r; assign cellgate_clipped=cell_clip_r;
    assign state_pre_clipped=pre_clip_r; assign state_clipped=state_clip_r;
    assign tag_out=tag_r;

    pe_requant_lane #(.TAG_WIDTH(1)) u_requant (
      .clk(clk),.rst_n(rst_n),.in_valid(rq_in_valid),.in_ready(rq_in_ready),
      .value_in(rq_value),.multiplier_in(rq_multiplier),.shift_in(rq_shift),
      .tag_in(1'b0),.out_valid(rq_out_valid),.out_ready(1'b1),
      .value_out(rq_result),.tag_out());

    pe_hybrid_mac u_membrane_mac (
      .clk(clk),.rst_n(rst_n),.acc_clear(mac_clear),.acc_enable(mac_enable),
      .mode(2'd2),.operand_a(8'sd0),.operand_b(mac_operand_r),.gate_u8(mac_gate_r),
      .spike_enable(1'b0),.direct_value(32'sd0),
      .accumulator(mac_accumulator),.overflow(mac_overflow));

    pe_sigmoid_lut_255 u_sigmoid (
      .clk(clk),.rst_n(rst_n),.in_valid(lut_in_valid),.in_ready(lut_in_ready),
      .gate_in(forget_r),.out_valid(lut_out_valid),.out_ready(1'b1),
      .lambda_out(lut_lambda),.cfg_we(cfg_we),.cfg_addr(cfg_addr),.cfg_data(cfg_data));

    always @* begin
        rq_in_valid=1'b0;rq_value=32'sd0;rq_multiplier=32'sd0;rq_shift=6'd0;
        mac_clear=1'b0;mac_enable=1'b0;
        lut_in_valid=1'b0;
        case(state)
          S_F_IN_REQ: begin rq_in_valid=1;rq_value=input_acc_r;rq_multiplier=f_im_r;rq_shift=f_is_r;end
          S_F_REC_REQ: begin rq_in_valid=1;rq_value=recurrent_acc_r;rq_multiplier=f_rm_r;rq_shift=f_rs_r;end
          S_C_IN_REQ: begin rq_in_valid=1;rq_value=input_acc_r;rq_multiplier=c_im_r;rq_shift=c_is_r;end
          S_C_REC_REQ: begin rq_in_valid=1;rq_value=recurrent_acc_r;rq_multiplier=c_rm_r;rq_shift=c_rs_r;end
          S_LUT_REQ: lut_in_valid=1'b1;
          S_CX_CLEAR,S_CELL_CLEAR: mac_clear=1'b1;
          S_CX_ISSUE,S_CELL_ISSUE: mac_enable=1'b1;
          S_CX_RQ_REQ: begin rq_in_valid=1;rq_value=cx_term;rq_multiplier=prev_m_r;rq_shift=prev_s_r;end
          S_CELL_RQ_REQ: begin rq_in_valid=1;rq_value=cell_term;rq_multiplier=cell_m_r;rq_shift=cell_s_r;end
          S_BN_REQ: begin rq_in_valid=1;rq_value={{24{state_pre_r[7]}},state_pre_r};rq_multiplier=bn_m_r;rq_shift=bn_s_r;end
          default: begin end
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state<=S_IDLE;forget_r<=0;cellgate_r<=0;lambda_r<=0;state_pre_r<=0;
            state_r<=0;spike_r<=0;forget_clip_r<=0;cell_clip_r<=0;
            pre_clip_r<=0;state_clip_r<=0;tag_r<=0;
            mac_gate_r<=0;mac_operand_r<=0;
            arithmetic_r<=0;add_lhs_r<=0;add_rhs_r<=0;magnitude_r<=0;
            rounded_magnitude_r<=0;negative_r<=0;
        end else begin
            case(state)
              S_IDLE: if(start_valid) begin
                input_acc_r<=input_acc;recurrent_acc_r<=recurrent_acc;previous_state_r<=previous_state_q;
                f_im_r<=forget_input_multiplier;f_is_r<=forget_input_shift;
                f_rm_r<=forget_recurrent_multiplier;f_rs_r<=forget_recurrent_shift;f_bias_r<=forget_bias_q;
                c_im_r<=cell_input_multiplier;c_is_r<=cell_input_shift;
                c_rm_r<=cell_recurrent_multiplier;c_rs_r<=cell_recurrent_shift;c_bias_r<=cell_bias_q;
                prev_m_r<=previous_multiplier;prev_s_r<=previous_shift;
                cell_m_r<=cellgate_multiplier;cell_s_r<=cellgate_shift;
                bn_m_r<=bn_multiplier;bn_s_r<=bn_shift;bn_bias_r<=bn_bias_q;tag_r<=tag_in;
                state<=S_F_IN_REQ;
              end
              S_F_IN_REQ: if(rq_in_ready)state<=S_F_IN_WAIT;
              S_F_IN_WAIT: if(rq_out_valid)begin f_input_rq<=rq_result;state<=S_F_REC_REQ;end
              S_F_REC_REQ: if(rq_in_ready)state<=S_F_REC_WAIT;
              S_F_REC_WAIT: if(rq_out_valid)begin
                f_recurrent_rq<=rq_result;add_lhs_r<=f_input_rq;add_rhs_r<=rq_result;state<=S_F_ADD_RQ;
              end
              S_F_ADD_RQ: begin arithmetic_r<=add_lhs_r+add_rhs_r;state<=S_F_ADD_BIAS;end
              S_F_ADD_BIAS: begin add_lhs_r<=arithmetic_r;add_rhs_r<={{32{f_bias_r[31]}},f_bias_r};state<=S_F_ADD_BIAS_DO;end
              S_F_ADD_BIAS_DO: begin arithmetic_r<=add_lhs_r+add_rhs_r;state<=S_F_MAG;end
              S_F_MAG: begin negative_r<=arithmetic_r[63];magnitude_r<=arithmetic_r[63]?(~arithmetic_r+64'd1):arithmetic_r;state<=S_F_ROUND;end
              S_F_ROUND: begin rounded_magnitude_r<=(magnitude_r+64'd128)>>GUARD_BITS;state<=S_F_SAT;end
              S_F_SAT: begin
                forget_clip_r<=rounded_magnitude_r>56'd127;
                if(rounded_magnitude_r>56'd127)forget_r<=negative_r?-8'sd127:8'sd127;
                else if(negative_r)forget_r<=-$signed(rounded_magnitude_r[7:0]);
                else forget_r<=rounded_magnitude_r[7:0];
                state<=S_C_IN_REQ;
              end
              S_C_IN_REQ: if(rq_in_ready)state<=S_C_IN_WAIT;
              S_C_IN_WAIT: if(rq_out_valid)begin c_input_rq<=rq_result;state<=S_C_REC_REQ;end
              S_C_REC_REQ: if(rq_in_ready)state<=S_C_REC_WAIT;
              S_C_REC_WAIT: if(rq_out_valid)begin
                c_recurrent_rq<=rq_result;add_lhs_r<=c_input_rq;add_rhs_r<=rq_result;state<=S_C_ADD_RQ;
              end
              S_C_ADD_RQ: begin arithmetic_r<=add_lhs_r+add_rhs_r;state<=S_C_ADD_BIAS;end
              S_C_ADD_BIAS: begin add_lhs_r<=arithmetic_r;add_rhs_r<={{32{c_bias_r[31]}},c_bias_r};state<=S_C_ADD_BIAS_DO;end
              S_C_ADD_BIAS_DO: begin arithmetic_r<=add_lhs_r+add_rhs_r;state<=S_C_MAG;end
              S_C_MAG: begin negative_r<=arithmetic_r[63];magnitude_r<=arithmetic_r[63]?(~arithmetic_r+64'd1):arithmetic_r;state<=S_C_ROUND;end
              S_C_ROUND: begin rounded_magnitude_r<=(magnitude_r+64'd128)>>GUARD_BITS;state<=S_C_SAT;end
              S_C_SAT: begin
                cell_clip_r<=rounded_magnitude_r>56'd127;
                if(rounded_magnitude_r>56'd127)cellgate_r<=negative_r?-8'sd127:8'sd127;
                else if(negative_r)cellgate_r<=-$signed(rounded_magnitude_r[7:0]);
                else cellgate_r<=rounded_magnitude_r[7:0];
                state<=S_LUT_REQ;
              end
              S_LUT_REQ: if(lut_in_ready)state<=S_LUT_WAIT;
              S_LUT_WAIT: if(lut_out_valid)begin lambda_r<=lut_lambda;state<=S_CX_CLEAR;end
              S_CX_CLEAR: begin mac_gate_r<=lambda_r;mac_operand_r<=previous_state_r;state<=S_CX_ISSUE;end
              S_CX_ISSUE: state<=S_CX_DRAIN;
              S_CX_DRAIN: state<=S_CX_CAPTURE;
              S_CX_CAPTURE: begin cx_term<=mac_accumulator;state<=S_CX_RQ_REQ;end
              S_CX_RQ_REQ: if(rq_in_ready)state<=S_CX_RQ_WAIT;
              S_CX_RQ_WAIT: if(rq_out_valid)begin cx_rq<=rq_result;state<=S_CELL_CLEAR;end
              S_CELL_CLEAR: begin mac_gate_r<=GATE_DENOMINATOR-lambda_r;mac_operand_r<=cellgate_r;state<=S_CELL_ISSUE;end
              S_CELL_ISSUE: state<=S_CELL_DRAIN;
              S_CELL_DRAIN: state<=S_CELL_CAPTURE;
              S_CELL_CAPTURE: begin cell_term<=mac_accumulator;state<=S_CELL_RQ_REQ;end
              S_CELL_RQ_REQ: if(rq_in_ready)state<=S_CELL_RQ_WAIT;
              S_CELL_RQ_WAIT: if(rq_out_valid)begin
                cell_rq<=rq_result;add_lhs_r<=cx_rq;add_rhs_r<=rq_result;state<=S_PRE_ADD;
              end
              S_PRE_ADD: begin arithmetic_r<=add_lhs_r+add_rhs_r;state<=S_PRE_MAG;end
              S_PRE_MAG: begin negative_r<=arithmetic_r[63];magnitude_r<=arithmetic_r[63]?(~arithmetic_r+64'd1):arithmetic_r;state<=S_PRE_ROUND;end
              S_PRE_ROUND: begin rounded_magnitude_r<=(magnitude_r+64'd128)>>GUARD_BITS;state<=S_PRE_SAT;end
              S_PRE_SAT: begin
                pre_clip_r<=rounded_magnitude_r>56'd127;
                if(rounded_magnitude_r>56'd127)state_pre_r<=negative_r?-8'sd127:8'sd127;
                else if(negative_r)state_pre_r<=-$signed(rounded_magnitude_r[7:0]);
                else state_pre_r<=rounded_magnitude_r[7:0];
                state<=S_BN_REQ;
              end
              S_BN_REQ: if(rq_in_ready)state<=S_BN_WAIT;
              S_BN_WAIT: if(rq_out_valid)begin
                bn_rq<=rq_result;add_lhs_r<=rq_result;add_rhs_r<={{32{bn_bias_r[31]}},bn_bias_r};state<=S_BN_ADD;
              end
              S_BN_ADD: begin arithmetic_r<=add_lhs_r+add_rhs_r;state<=S_BN_MAG;end
              S_BN_MAG: begin negative_r<=arithmetic_r[63];magnitude_r<=arithmetic_r[63]?(~arithmetic_r+64'd1):arithmetic_r;state<=S_BN_ROUND;end
              S_BN_ROUND: begin rounded_magnitude_r<=(magnitude_r+64'd128)>>GUARD_BITS;state<=S_STATE_SAT;end
              S_STATE_SAT: begin
                state_clip_r<=rounded_magnitude_r>56'd127;
                if(rounded_magnitude_r>56'd127)state_r<=negative_r?-8'sd127:8'sd127;
                else if(negative_r)state_r<=-$signed(rounded_magnitude_r[7:0]);
                else state_r<=rounded_magnitude_r[7:0];
                spike_r<=!negative_r||(rounded_magnitude_r==0);
                state<=S_RESULT;
              end
              S_RESULT: if(result_ready)state<=S_IDLE;
              default: state<=S_IDLE;
            endcase
        end
    end

`ifndef SYNTHESIS
    initial begin
      if(GUARD_BITS!=8)$fatal(1,"pe_gsn_cell currently freezes GUARD_BITS=8");
      if(GATE_DENOMINATOR!=255)$fatal(1,"pe_gsn_cell currently freezes denominator=255");
    end
    always @(posedge clk) if(rst_n && mac_overflow)$fatal(1,"pe_gsn_cell membrane MAC overflow");
`endif
endmodule
