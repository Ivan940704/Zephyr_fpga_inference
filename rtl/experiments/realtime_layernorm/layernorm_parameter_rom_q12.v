`timescale 1ns/1ps

// Synchronous model-specific affine parameter ROM for the shared Q12
// LayerNorm engine.  Profiles are fullband, low, mid, and high subband.
module layernorm_parameter_rom_q12 (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 abort,

    input  wire [1:0]           config_profile,
    output reg  [7:0]           config_length,
    output reg  [31:0]          config_output_reciprocal_q20,

    input  wire                 request_valid,
    output wire                 request_ready,
    input  wire [1:0]           request_profile,
    input  wire [7:0]           request_index,

    output wire                 response_valid,
    input  wire                 response_ready,
    output wire signed [15:0]   response_weight_q12,
    output wire signed [15:0]   response_bias_q12,
    output wire                 response_error
);
    (* rom_style = "block" *) reg [31:0] parameter_memory [0:361];
    reg response_valid_q;
    reg signed [15:0] response_weight_q;
    reg signed [15:0] response_bias_q;
    reg response_error_q;

    reg [8:0] request_address;
    reg request_in_range;

    initial begin
        `include "layernorm_parameter_rom_q12_init.vh"
    end

    initial begin
        if ((17789402 == 0) || (26354903 == 0) ||
            (33864296 == 0) || (50437752 == 0)) begin
            $display("LayerNorm parameter ROM reciprocal configuration is invalid");
            $finish;
        end
    end

    always @(*) begin
        case (config_profile)
            2'd0: begin
                config_length = 8'd64;
                config_output_reciprocal_q20 = 32'd17789402;
            end
            2'd1: begin
                config_length = 8'd46;
                config_output_reciprocal_q20 = 32'd26354903;
            end
            2'd2: begin
                config_length = 8'd94;
                config_output_reciprocal_q20 = 32'd33864296;
            end
            default: begin
                config_length = 8'd158;
                config_output_reciprocal_q20 = 32'd50437752;
            end
        endcase
    end

    always @(*) begin
        request_address = 9'd0;
        request_in_range = 1'b0;
        case (request_profile)
            2'd0: begin
                request_address = {1'b0, request_index};
                request_in_range = (request_index < 8'd64);
            end
            2'd1: begin
                request_address = 9'd64 + request_index;
                request_in_range = (request_index < 8'd46);
            end
            2'd2: begin
                request_address = 9'd110 + request_index;
                request_in_range = (request_index < 8'd94);
            end
            default: begin
                request_address = 9'd204 + request_index;
                request_in_range = (request_index < 8'd158);
            end
        endcase
    end

    assign request_ready = rst_n && !abort &&
                           (!response_valid_q || response_ready);
    assign response_valid = response_valid_q;
    assign response_weight_q12 = response_weight_q;
    assign response_bias_q12 = response_bias_q;
    assign response_error = response_error_q;

    always @(posedge clk) begin
        if (!rst_n || abort) begin
            response_valid_q <= 1'b0;
            response_weight_q <= 16'sd0;
            response_bias_q <= 16'sd0;
            response_error_q <= 1'b0;
        end else if (request_ready) begin
            response_valid_q <= request_valid;
            response_error_q <= request_valid && !request_in_range;
            if (request_valid && request_in_range) begin
                response_weight_q <= parameter_memory[request_address][15:0];
                response_bias_q <= parameter_memory[request_address][31:16];
            end else begin
                response_weight_q <= 16'sd0;
                response_bias_q <= 16'sd0;
            end
        end
    end
endmodule
