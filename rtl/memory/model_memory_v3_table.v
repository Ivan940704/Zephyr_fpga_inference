`timescale 1ns/1ps
`include "memory/model_memory_v3_map.vh"

// Generated combinational stage table for the v3 parameter image.
module model_memory_v3_table (
    input  wire [3:0]  stage_id,
    output reg         stage_valid,
    output reg         stage_kind,
    output reg  [31:0] dram_byte_offset,
    output reg  [31:0] transfer_bytes,
    output reg  [1:0]  matrix_count,
    output reg  [31:0] matrix0_word_offset,
    output reg  [9:0]  matrix0_sources,
    output reg  [5:0]  matrix0_row_tiles,
    output reg  [31:0] matrix1_word_offset,
    output reg  [9:0]  matrix1_sources,
    output reg  [5:0]  matrix1_row_tiles,
    output reg  [31:0] param_word_offset,
    output reg  [7:0]  param_record_words,
    output reg  [12:0] param_response_bits,
    output reg  [5:0]  param_tiles,
    output reg         has_lut,
    output reg  [31:0] lut_word_offset,
    output reg  [8:0]  lut_bytes
);
    always @* begin
        stage_valid = 1'b0;
        stage_kind = 1'b0;
        dram_byte_offset = 32'd0;
        transfer_bytes = 32'd0;
        matrix_count = 2'd0;
        matrix0_word_offset = 32'd0;
        matrix0_sources = 10'd0;
        matrix0_row_tiles = 6'd0;
        matrix1_word_offset = 32'd0;
        matrix1_sources = 10'd0;
        matrix1_row_tiles = 6'd0;
        param_word_offset = 32'd0;
        param_record_words = 8'd0;
        param_response_bits = 13'd0;
        param_tiles = 6'd0;
        has_lut = 1'b0;
        lut_word_offset = 32'd0;
        lut_bytes = 9'd0;
        case (stage_id)
            4'd0: begin
                stage_valid = 1'b1;
                stage_kind = 1'b0;
                dram_byte_offset = 32'd64;
                transfer_bytes = 32'd137728;
                matrix_count = 2'd2;
                matrix0_word_offset = 32'd0;
                matrix0_sources = 10'd64;
                matrix0_row_tiles = 6'd20;
                matrix1_word_offset = 32'd2560;
                matrix1_sources = 10'd320;
                matrix1_row_tiles = 6'd20;
                param_word_offset = 32'd15360;
                param_record_words = 8'd91;
                param_response_bits = 13'd5792;
                param_tiles = 6'd20;
                has_lut = 1'b1;
                lut_word_offset = 32'd17184;
                lut_bytes = 9'd255;
            end
            4'd1: begin
                stage_valid = 1'b1;
                stage_kind = 1'b0;
                dram_byte_offset = 32'd137792;
                transfer_bytes = 32'd219648;
                matrix_count = 2'd2;
                matrix0_word_offset = 32'd0;
                matrix0_sources = 10'd320;
                matrix0_row_tiles = 6'd20;
                matrix1_word_offset = 32'd12800;
                matrix1_sources = 10'd320;
                matrix1_row_tiles = 6'd20;
                param_word_offset = 32'd25600;
                param_record_words = 8'd91;
                param_response_bits = 13'd5792;
                param_tiles = 6'd20;
                has_lut = 1'b1;
                lut_word_offset = 32'd27424;
                lut_bytes = 9'd255;
            end
            4'd2: begin
                stage_valid = 1'b1;
                stage_kind = 1'b1;
                dram_byte_offset = 32'd357440;
                transfer_bytes = 32'd21056;
                matrix_count = 2'd1;
                matrix0_word_offset = 32'd0;
                matrix0_sources = 10'd320;
                matrix0_row_tiles = 6'd4;
                param_word_offset = 32'd2560;
                param_record_words = 8'd18;
                param_response_bits = 13'd1120;
                param_tiles = 6'd4;
                has_lut = 1'b0;
                lut_word_offset = 32'd0;
                lut_bytes = 9'd0;
            end
            4'd3: begin
                stage_valid = 1'b1;
                stage_kind = 1'b0;
                dram_byte_offset = 32'd378496;
                transfer_bytes = 32'd70976;
                matrix_count = 2'd2;
                matrix0_word_offset = 32'd0;
                matrix0_sources = 10'd46;
                matrix0_row_tiles = 6'd14;
                matrix1_word_offset = 32'd1288;
                matrix1_sources = 10'd224;
                matrix1_row_tiles = 6'd14;
                param_word_offset = 32'd7560;
                param_record_words = 8'd91;
                param_response_bits = 13'd5792;
                param_tiles = 6'd14;
                has_lut = 1'b1;
                lut_word_offset = 32'd8840;
                lut_bytes = 9'd255;
            end
            4'd4: begin
                stage_valid = 1'b1;
                stage_kind = 1'b0;
                dram_byte_offset = 32'd449472;
                transfer_bytes = 32'd110848;
                matrix_count = 2'd2;
                matrix0_word_offset = 32'd0;
                matrix0_sources = 10'd224;
                matrix0_row_tiles = 6'd14;
                matrix1_word_offset = 32'd6272;
                matrix1_sources = 10'd224;
                matrix1_row_tiles = 6'd14;
                param_word_offset = 32'd12544;
                param_record_words = 8'd91;
                param_response_bits = 13'd5792;
                param_tiles = 6'd14;
                has_lut = 1'b1;
                lut_word_offset = 32'd13824;
                lut_bytes = 9'd255;
            end
            4'd5: begin
                stage_valid = 1'b1;
                stage_kind = 1'b1;
                dram_byte_offset = 32'd560320;
                transfer_bytes = 32'd18640;
                matrix_count = 2'd1;
                matrix0_word_offset = 32'd0;
                matrix0_sources = 10'd224;
                matrix0_row_tiles = 6'd5;
                param_word_offset = 32'd2240;
                param_record_words = 8'd18;
                param_response_bits = 13'd1120;
                param_tiles = 6'd5;
                has_lut = 1'b0;
                lut_word_offset = 32'd0;
                lut_bytes = 9'd0;
            end
            4'd6: begin
                stage_valid = 1'b1;
                stage_kind = 1'b0;
                dram_byte_offset = 32'd579008;
                transfer_bytes = 32'd81728;
                matrix_count = 2'd2;
                matrix0_word_offset = 32'd0;
                matrix0_sources = 10'd94;
                matrix0_row_tiles = 6'd14;
                matrix1_word_offset = 32'd2632;
                matrix1_sources = 10'd224;
                matrix1_row_tiles = 6'd14;
                param_word_offset = 32'd8904;
                param_record_words = 8'd91;
                param_response_bits = 13'd5792;
                param_tiles = 6'd14;
                has_lut = 1'b1;
                lut_word_offset = 32'd10184;
                lut_bytes = 9'd255;
            end
            4'd7: begin
                stage_valid = 1'b1;
                stage_kind = 1'b0;
                dram_byte_offset = 32'd660736;
                transfer_bytes = 32'd110848;
                matrix_count = 2'd2;
                matrix0_word_offset = 32'd0;
                matrix0_sources = 10'd224;
                matrix0_row_tiles = 6'd14;
                matrix1_word_offset = 32'd6272;
                matrix1_sources = 10'd224;
                matrix1_row_tiles = 6'd14;
                param_word_offset = 32'd12544;
                param_record_words = 8'd91;
                param_response_bits = 13'd5792;
                param_tiles = 6'd14;
                has_lut = 1'b1;
                lut_word_offset = 32'd13824;
                lut_bytes = 9'd255;
            end
            4'd8: begin
                stage_valid = 1'b1;
                stage_kind = 1'b1;
                dram_byte_offset = 32'd771584;
                transfer_bytes = 32'd44736;
                matrix_count = 2'd1;
                matrix0_word_offset = 32'd0;
                matrix0_sources = 10'd224;
                matrix0_row_tiles = 6'd12;
                param_word_offset = 32'd5376;
                param_record_words = 8'd18;
                param_response_bits = 13'd1120;
                param_tiles = 6'd12;
                has_lut = 1'b0;
                lut_word_offset = 32'd0;
                lut_bytes = 9'd0;
            end
            4'd9: begin
                stage_valid = 1'b1;
                stage_kind = 1'b0;
                dram_byte_offset = 32'd816320;
                transfer_bytes = 32'd96064;
                matrix_count = 2'd2;
                matrix0_word_offset = 32'd0;
                matrix0_sources = 10'd158;
                matrix0_row_tiles = 6'd14;
                matrix1_word_offset = 32'd4424;
                matrix1_sources = 10'd224;
                matrix1_row_tiles = 6'd14;
                param_word_offset = 32'd10696;
                param_record_words = 8'd91;
                param_response_bits = 13'd5792;
                param_tiles = 6'd14;
                has_lut = 1'b1;
                lut_word_offset = 32'd11976;
                lut_bytes = 9'd255;
            end
            4'd10: begin
                stage_valid = 1'b1;
                stage_kind = 1'b0;
                dram_byte_offset = 32'd912384;
                transfer_bytes = 32'd110848;
                matrix_count = 2'd2;
                matrix0_word_offset = 32'd0;
                matrix0_sources = 10'd224;
                matrix0_row_tiles = 6'd14;
                matrix1_word_offset = 32'd6272;
                matrix1_sources = 10'd224;
                matrix1_row_tiles = 6'd14;
                param_word_offset = 32'd12544;
                param_record_words = 8'd91;
                param_response_bits = 13'd5792;
                param_tiles = 6'd14;
                has_lut = 1'b1;
                lut_word_offset = 32'd13824;
                lut_bytes = 9'd255;
            end
            4'd11: begin
                stage_valid = 1'b1;
                stage_kind = 1'b1;
                dram_byte_offset = 32'd1023232;
                transfer_bytes = 32'd29824;
                matrix_count = 2'd1;
                matrix0_word_offset = 32'd0;
                matrix0_sources = 10'd224;
                matrix0_row_tiles = 6'd8;
                param_word_offset = 32'd3584;
                param_record_words = 8'd18;
                param_response_bits = 13'd1120;
                param_tiles = 6'd8;
                has_lut = 1'b0;
                lut_word_offset = 32'd0;
                lut_bytes = 9'd0;
            end
            default: begin end
        endcase
    end
endmodule
