`timescale 1ns/1ps
`include "memory/model_memory_v5_map.vh"

// Generated combinational stage table for the v5 parameter image.
module model_memory_v5_table (
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
    output reg  [13:0] param_response_bits,
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
        param_response_bits = 14'd0;
        param_tiles = 6'd0;
        uses_sigmoid_table = 1'b0;
        sigmoid_table_select = 3'd0;
        case (stage_id)
            4'd0: begin
                stage_valid = 1'b1;
                stage_kind = 1'b0;
                dram_byte_offset = 32'd2112;
                transfer_bytes = 32'd137360;
                matrix_count = 2'd2;
                matrix0_word_offset = 32'd0;
                matrix0_sources = 10'd64;
                matrix0_row_tiles = 6'd10;
                matrix1_word_offset = 32'd2560;
                matrix1_sources = 10'd320;
                matrix1_row_tiles = 6'd10;
                param_word_offset = 32'd15360;
                param_record_words = 8'd181;
                param_response_bits = 14'd11584;
                param_tiles = 6'd10;
                uses_sigmoid_table = 1'b1;
                sigmoid_table_select = 3'd0;
            end
            4'd1: begin
                stage_valid = 1'b1;
                stage_kind = 1'b0;
                dram_byte_offset = 32'd139520;
                transfer_bytes = 32'd219280;
                matrix_count = 2'd2;
                matrix0_word_offset = 32'd0;
                matrix0_sources = 10'd320;
                matrix0_row_tiles = 6'd10;
                matrix1_word_offset = 32'd12800;
                matrix1_sources = 10'd320;
                matrix1_row_tiles = 6'd10;
                param_word_offset = 32'd25600;
                param_record_words = 8'd181;
                param_response_bits = 14'd11584;
                param_tiles = 6'd10;
                uses_sigmoid_table = 1'b1;
                sigmoid_table_select = 3'd1;
            end
            4'd2: begin
                stage_valid = 1'b1;
                stage_kind = 1'b1;
                dram_byte_offset = 32'd358848;
                transfer_bytes = 32'd21040;
                matrix_count = 2'd1;
                matrix0_word_offset = 32'd0;
                matrix0_sources = 10'd320;
                matrix0_row_tiles = 6'd2;
                param_word_offset = 32'd2560;
                param_record_words = 8'd35;
                param_response_bits = 14'd2240;
                param_tiles = 6'd2;
                uses_sigmoid_table = 1'b0;
                sigmoid_table_select = 3'd0;
            end
            4'd3: begin
                stage_valid = 1'b1;
                stage_kind = 1'b0;
                dram_byte_offset = 32'd379904;
                transfer_bytes = 32'd70616;
                matrix_count = 2'd2;
                matrix0_word_offset = 32'd0;
                matrix0_sources = 10'd46;
                matrix0_row_tiles = 6'd7;
                matrix1_word_offset = 32'd1288;
                matrix1_sources = 10'd224;
                matrix1_row_tiles = 6'd7;
                param_word_offset = 32'd7560;
                param_record_words = 8'd181;
                param_response_bits = 14'd11584;
                param_tiles = 6'd7;
                uses_sigmoid_table = 1'b1;
                sigmoid_table_select = 3'd2;
            end
            4'd4: begin
                stage_valid = 1'b1;
                stage_kind = 1'b0;
                dram_byte_offset = 32'd450560;
                transfer_bytes = 32'd110488;
                matrix_count = 2'd2;
                matrix0_word_offset = 32'd0;
                matrix0_sources = 10'd224;
                matrix0_row_tiles = 6'd7;
                matrix1_word_offset = 32'd6272;
                matrix1_sources = 10'd224;
                matrix1_row_tiles = 6'd7;
                param_word_offset = 32'd12544;
                param_record_words = 8'd181;
                param_response_bits = 14'd11584;
                param_tiles = 6'd7;
                uses_sigmoid_table = 1'b1;
                sigmoid_table_select = 3'd3;
            end
            4'd5: begin
                stage_valid = 1'b1;
                stage_kind = 1'b1;
                dram_byte_offset = 32'd561088;
                transfer_bytes = 32'd22344;
                matrix_count = 2'd1;
                matrix0_word_offset = 32'd0;
                matrix0_sources = 10'd224;
                matrix0_row_tiles = 6'd3;
                param_word_offset = 32'd2688;
                param_record_words = 8'd35;
                param_response_bits = 14'd2240;
                param_tiles = 6'd3;
                uses_sigmoid_table = 1'b0;
                sigmoid_table_select = 3'd0;
            end
            4'd6: begin
                stage_valid = 1'b1;
                stage_kind = 1'b0;
                dram_byte_offset = 32'd583488;
                transfer_bytes = 32'd81368;
                matrix_count = 2'd2;
                matrix0_word_offset = 32'd0;
                matrix0_sources = 10'd94;
                matrix0_row_tiles = 6'd7;
                matrix1_word_offset = 32'd2632;
                matrix1_sources = 10'd224;
                matrix1_row_tiles = 6'd7;
                param_word_offset = 32'd8904;
                param_record_words = 8'd181;
                param_response_bits = 14'd11584;
                param_tiles = 6'd7;
                uses_sigmoid_table = 1'b1;
                sigmoid_table_select = 3'd4;
            end
            4'd7: begin
                stage_valid = 1'b1;
                stage_kind = 1'b0;
                dram_byte_offset = 32'd664896;
                transfer_bytes = 32'd110488;
                matrix_count = 2'd2;
                matrix0_word_offset = 32'd0;
                matrix0_sources = 10'd224;
                matrix0_row_tiles = 6'd7;
                matrix1_word_offset = 32'd6272;
                matrix1_sources = 10'd224;
                matrix1_row_tiles = 6'd7;
                param_word_offset = 32'd12544;
                param_record_words = 8'd181;
                param_response_bits = 14'd11584;
                param_tiles = 6'd7;
                uses_sigmoid_table = 1'b1;
                sigmoid_table_select = 3'd5;
            end
            4'd8: begin
                stage_valid = 1'b1;
                stage_kind = 1'b1;
                dram_byte_offset = 32'd775424;
                transfer_bytes = 32'd44688;
                matrix_count = 2'd1;
                matrix0_word_offset = 32'd0;
                matrix0_sources = 10'd224;
                matrix0_row_tiles = 6'd6;
                param_word_offset = 32'd5376;
                param_record_words = 8'd35;
                param_response_bits = 14'd2240;
                param_tiles = 6'd6;
                uses_sigmoid_table = 1'b0;
                sigmoid_table_select = 3'd0;
            end
            4'd9: begin
                stage_valid = 1'b1;
                stage_kind = 1'b0;
                dram_byte_offset = 32'd820160;
                transfer_bytes = 32'd95704;
                matrix_count = 2'd2;
                matrix0_word_offset = 32'd0;
                matrix0_sources = 10'd158;
                matrix0_row_tiles = 6'd7;
                matrix1_word_offset = 32'd4424;
                matrix1_sources = 10'd224;
                matrix1_row_tiles = 6'd7;
                param_word_offset = 32'd10696;
                param_record_words = 8'd181;
                param_response_bits = 14'd11584;
                param_tiles = 6'd7;
                uses_sigmoid_table = 1'b1;
                sigmoid_table_select = 3'd6;
            end
            4'd10: begin
                stage_valid = 1'b1;
                stage_kind = 1'b0;
                dram_byte_offset = 32'd915904;
                transfer_bytes = 32'd110488;
                matrix_count = 2'd2;
                matrix0_word_offset = 32'd0;
                matrix0_sources = 10'd224;
                matrix0_row_tiles = 6'd7;
                matrix1_word_offset = 32'd6272;
                matrix1_sources = 10'd224;
                matrix1_row_tiles = 6'd7;
                param_word_offset = 32'd12544;
                param_record_words = 8'd181;
                param_response_bits = 14'd11584;
                param_tiles = 6'd7;
                uses_sigmoid_table = 1'b1;
                sigmoid_table_select = 3'd7;
            end
            4'd11: begin
                stage_valid = 1'b1;
                stage_kind = 1'b1;
                dram_byte_offset = 32'd1026432;
                transfer_bytes = 32'd29792;
                matrix_count = 2'd1;
                matrix0_word_offset = 32'd0;
                matrix0_sources = 10'd224;
                matrix0_row_tiles = 6'd4;
                param_word_offset = 32'd3584;
                param_record_words = 8'd35;
                param_response_bits = 14'd2240;
                param_tiles = 6'd4;
                uses_sigmoid_table = 1'b0;
                sigmoid_table_select = 3'd0;
            end
            default: begin end
        endcase
    end
endmodule
