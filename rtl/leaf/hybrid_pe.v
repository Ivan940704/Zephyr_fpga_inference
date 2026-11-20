`timescale 1ns/1ps

// One stateful heterogeneous accumulation lane.
// mode 0: signed INT8 x signed INT8 MAC
// mode 1: binary spike x signed INT8 weight accumulation
// mode 2: unsigned gate x signed INT8 state multiplication
// mode 3: direct signed INT8 accumulation
module hybrid_pe (
    input  wire               clk,
    input  wire               rst,
    input  wire               clear_acc,
    input  wire               enable,
    input  wire        [1:0]  mode,
    input  wire signed [7:0]  operand_a,
    input  wire signed [7:0]  operand_b,
    input  wire        [7:0]  gate_u8,
    input  wire               spike,
    output reg  signed [31:0] accumulator
);
    localparam MODE_DENSE  = 2'd0;
    localparam MODE_SPIKE  = 2'd1;
    localparam MODE_GATE   = 2'd2;
    localparam MODE_DIRECT = 2'd3;

    reg signed [31:0] term;
    reg signed [16:0] gate_product;
    reg signed [16:0] gate_extended;
    reg signed [16:0] operand_b_extended;

    always @* begin
        term = 32'sd0;
        gate_product = 17'sd0;
        gate_extended = $signed({1'b0, gate_u8});
        operand_b_extended = {{9{operand_b[7]}}, operand_b};
        case (mode)
            MODE_DENSE: term = operand_a * operand_b;
            MODE_SPIKE: term = spike ? {{24{operand_b[7]}}, operand_b} : 32'sd0;
            MODE_GATE: begin
                gate_product = gate_extended * operand_b_extended;
                term = {{15{gate_product[16]}}, gate_product};
            end
            MODE_DIRECT: term = {{24{operand_b[7]}}, operand_b};
            default: term = 32'sd0;
        endcase
    end

    always @(posedge clk) begin
        if (rst || clear_acc) begin
            accumulator <= 32'sd0;
        end else if (enable) begin
            accumulator <= accumulator + term;
        end
    end
endmodule
