`timescale 1ns/1ps
`include "memory/model_memory_v4_map.vh"

// Generated combinational stage table for the v4 parameter image.
module model_memory_v4_table (
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
    output reg         uses_sigmoid_table,
    output reg  [2:0]  sigmoid_table_select
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
        uses_sigmoid_table = 1'b0;
        sigmoid_table_select = 3'd0;
        case (stage_id)
            4'd0: begin
                stage_valid = 1'b1;
                stage_kind = 1'b0;
                dram_byte_offset = 32'd2112;
                transfer_bytes = 32'd137440;
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
                uses_sigmoid_table = 1'b1;
                sigmoid_table_select = 3'd0;
            end
            4'd1: begin
                stage_valid = 1'b1;
                stage_kind = 1'b0;
                dram_byte_offset = 32'd139584;
                transfer_bytes = 32'd219360;
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
                uses_sigmoid_table = 1'b1;
                sigmoid_table_select = 3'd1;
            end
            4'd2: begin
                stage_valid = 1'b1;
                stage_kind = 1'b1;
                dram_byte_offset = 32'd358976;
                transfer_bytes = 32'd21056;
                matrix_count = 2'd1;
                matrix0_word_offset = 32'd0;
                matrix0_sources = 10'd320;
                matrix0_row_tiles = 6'd4;
                param_word_offset = 32'd2560;
                param_record_words = 8'd18;
                param_response_bits = 13'd1120;
                param_tiles = 6'd4;
                uses_sigmoid_table = 1'b0;
                sigmoid_table_select = 3'd0;
            end
            4'd3: begin
                stage_valid = 1'b1;
                stage_kind = 1'b0;
                dram_byte_offset = 32'd380032;
                transfer_bytes = 32'd70672;
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
                uses_sigmoid_table = 1'b1;
                sigmoid_table_select = 3'd2;
            end
            4'd4: begin
                stage_valid = 1'b1;
                stage_kind = 1'b0;
                dram_byte_offset = 32'd450752;
                transfer_bytes = 32'd110544;
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
                uses_sigmoid_table = 1'b1;
                sigmoid_table_select = 3'd3;
            end
            4'd5: begin
                stage_valid = 1'b1;
                stage_kind = 1'b1;
                dram_byte_offset = 32'd561344;
                transfer_bytes = 32'd18640;
                matrix_count = 2'd1;
                matrix0_word_offset = 32'd0;
                matrix0_sources = 10'd224;
                matrix0_row_tiles = 6'd5;
                param_word_offset = 32'd2240;
                param_record_words = 8'd18;
                param_response_bits = 13'd1120;
                param_tiles = 6'd5;
                uses_sigmoid_table = 1'b0;
                sigmoid_table_select = 3'd0;
            end
            4'd6: begin
                stage_valid = 1'b1;
                stage_kind = 1'b0;
                dram_byte_offset = 32'd580032;
                transfer_bytes = 32'd81424;
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
                uses_sigmoid_table = 1'b1;
                sigmoid_table_select = 3'd4;
            end
            4'd7: begin
                stage_valid = 1'b1;
                stage_kind = 1'b0;
                dram_byte_offset = 32'd661504;
                transfer_bytes = 32'd110544;
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
                uses_sigmoid_table = 1'b1;
                sigmoid_table_select = 3'd5;
            end
            4'd8: begin
                stage_valid = 1'b1;
                stage_kind = 1'b1;
                dram_byte_offset = 32'd772096;
                transfer_bytes = 32'd44736;
                matrix_count = 2'd1;
                matrix0_word_offset = 32'd0;
                matrix0_sources = 10'd224;
                matrix0_row_tiles = 6'd12;
                param_word_offset = 32'd5376;
                param_record_words = 8'd18;
                param_response_bits = 13'd1120;
                param_tiles = 6'd12;
                uses_sigmoid_table = 1'b0;
                sigmoid_table_select = 3'd0;
            end
            4'd9: begin
                stage_valid = 1'b1;
                stage_kind = 1'b0;
                dram_byte_offset = 32'd816832;
                transfer_bytes = 32'd95760;
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
                uses_sigmoid_table = 1'b1;
                sigmoid_table_select = 3'd6;
            end
            4'd10: begin
                stage_valid = 1'b1;
                stage_kind = 1'b0;
                dram_byte_offset = 32'd912640;
                transfer_bytes = 32'd110544;
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
                uses_sigmoid_table = 1'b1;
                sigmoid_table_select = 3'd7;
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
                uses_sigmoid_table = 1'b0;
                sigmoid_table_select = 3'd0;
            end
            default: begin end
        endcase
    end
endmodule
