`timescale 1ns/1ps

// One independently controlled accumulator lane for the fixed PE Array.
// Dense and gate modes share one signed multiplier. Spike and direct modes
// bypass it, so an intended array contains one multiplier per Hybrid MAC PE.
module pe_hybrid_mac (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               acc_clear,
    input  wire               acc_enable,
    input  wire        [1:0]  mode,
    input  wire signed [7:0]  operand_a,
    input  wire signed [7:0]  operand_b,
    input  wire        [7:0]  gate_u8,
    input  wire               spike_enable,
    input  wire signed [31:0] direct_value,
    output reg  signed [31:0] accumulator,
    output reg                overflow
);

    localparam [1:0] MODE_DENSE  = 2'd0;
    localparam [1:0] MODE_SPIKE  = 2'd1;
    localparam [1:0] MODE_GATE   = 2'd2;
    localparam [1:0] MODE_DIRECT = 2'd3;

    reg signed [17:0] multiply_a;
    reg signed [17:0] multiply_b;
    wire signed [35:0] multiply_product;
    reg signed [32:0] bypass_term;
    reg signed [35:0] multiply_product_pipe;
    reg signed [32:0] bypass_term_pipe;
    reg        [1:0]  mode_pipe;
    reg               term_valid_pipe;
    reg signed [32:0] selected_term_pipe;
    wire signed [32:0] accumulator_extended;
    wire signed [32:0] sum_extended;
    wire add_overflow;

    assign multiply_product = multiply_a * multiply_b;
    assign accumulator_extended = {accumulator[31], accumulator};
    assign sum_extended = accumulator_extended + selected_term_pipe;
    assign add_overflow = sum_extended[32] != sum_extended[31];

    always @* begin
        multiply_a = 18'sd0;
        multiply_b = 18'sd0;
        bypass_term = 33'sd0;

        case (mode)
            MODE_DENSE: begin
                multiply_a = {{10{operand_a[7]}}, operand_a};
                multiply_b = {{10{operand_b[7]}}, operand_b};
            end

            MODE_SPIKE: begin
                bypass_term = spike_enable
                    ? {{25{operand_b[7]}}, operand_b}
                    : 33'sd0;
            end

            MODE_GATE: begin
                multiply_a = {10'd0, gate_u8};
                multiply_b = {{10{operand_b[7]}}, operand_b};
            end

            MODE_DIRECT: begin
                bypass_term = {direct_value[31], direct_value};
            end

            default: bypass_term = 33'sd0;
        endcase
    end

    always @* begin
        case (mode_pipe)
            MODE_DENSE:
                selected_term_pipe = {{17{multiply_product_pipe[15]}},
                                      multiply_product_pipe[15:0]};
            MODE_GATE:
                selected_term_pipe = {{16{multiply_product_pipe[16]}},
                                      multiply_product_pipe[16:0]};
            default:
                selected_term_pipe = bypass_term_pipe;
        endcase
    end

    // Synchronous active-low reset matches the other new PE Array arithmetic.
    always @(posedge clk) begin
        if (!rst_n) begin
            accumulator <= 32'sd0;
            overflow <= 1'b0;
            multiply_product_pipe <= 36'sd0;
            bypass_term_pipe <= 33'sd0;
            mode_pipe <= MODE_DENSE;
            term_valid_pipe <= 1'b0;
        end else if (acc_clear) begin
            accumulator <= 32'sd0;
            overflow <= 1'b0;
            term_valid_pipe <= 1'b0;
        end else begin
            if (term_valid_pipe) begin
                accumulator <= sum_extended[31:0];
                overflow <= overflow | add_overflow;
            end

            term_valid_pipe <= acc_enable;
            if (acc_enable) begin
                multiply_product_pipe <= multiply_product;
                bypass_term_pipe <= bypass_term;
                mode_pipe <= mode;
            end
        end
    end

endmodule
