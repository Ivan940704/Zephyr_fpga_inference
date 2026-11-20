`timescale 1ns/1ps

// Sequential-v4 stage-to-active-list mapping used by the isolated sparse
// planner.  Contexts within a list group always advance by two logical IDs.
module sparse_stage_map_v1 (
    input  wire [3:0] stage_id,
    output reg        stage_valid,
    output reg [1:0]  matrix_count,
    output reg [31:0] stage_dram_byte_offset,
    output reg [31:0] stage_transfer_bytes,

    output reg        matrix0_dense,
    output reg [9:0]  matrix0_sources,
    output reg [5:0]  matrix0_row_tiles,
    output reg [31:0] matrix0_local_byte_offset,
    output reg [31:0] matrix0_source_stride_bytes,
    output reg [2:0]  matrix0_list_count,
    output reg [4:0]  matrix0_list_base,
    output reg        matrix0_require_present,

    output reg        matrix1_dense,
    output reg [9:0]  matrix1_sources,
    output reg [5:0]  matrix1_row_tiles,
    output reg [31:0] matrix1_local_byte_offset,
    output reg [31:0] matrix1_source_stride_bytes,
    output reg [2:0]  matrix1_list_count,
    output reg [4:0]  matrix1_list_base,
    output reg        matrix1_require_present,

    output reg [31:0] parameter_local_byte_offset,
    output reg [31:0] parameter_transfer_bytes
);
    always @* begin
        stage_valid = 1'b1;
        matrix_count = 2'd2;
        stage_dram_byte_offset = 32'd0;
        stage_transfer_bytes = 32'd0;

        matrix0_dense = 1'b0;
        matrix0_sources = 10'd0;
        matrix0_row_tiles = 6'd0;
        matrix0_local_byte_offset = 32'd0;
        matrix0_source_stride_bytes = 32'd0;
        matrix0_list_count = 3'd0;
        matrix0_list_base = 5'd0;
        matrix0_require_present = 1'b0;

        matrix1_dense = 1'b0;
        matrix1_sources = 10'd0;
        matrix1_row_tiles = 6'd0;
        matrix1_local_byte_offset = 32'd0;
        matrix1_source_stride_bytes = 32'd0;
        matrix1_list_count = 3'd0;
        matrix1_list_base = 5'd0;
        matrix1_require_present = 1'b0;
        parameter_local_byte_offset = 32'd0;
        parameter_transfer_bytes = 32'd0;

        case (stage_id)
            4'd0: begin
                stage_dram_byte_offset = 32'd2112;
                stage_transfer_bytes = 32'd137440;
                matrix0_dense = 1'b1;
                matrix0_sources = 10'd64;
                matrix0_row_tiles = 6'd20;
                matrix0_source_stride_bytes = 32'd320;
                matrix1_sources = 10'd320;
                matrix1_row_tiles = 6'd20;
                matrix1_local_byte_offset = 32'd20480;
                matrix1_source_stride_bytes = 32'd320;
                matrix1_list_count = 3'd1;
                matrix1_list_base = 5'd0;
                parameter_local_byte_offset = 32'd122880;
                parameter_transfer_bytes = 32'd14560;
            end
            4'd1: begin
                stage_dram_byte_offset = 32'd139584;
                stage_transfer_bytes = 32'd219360;
                matrix0_sources = 10'd320;
                matrix0_row_tiles = 6'd20;
                matrix0_source_stride_bytes = 32'd320;
                matrix0_list_count = 3'd1;
                matrix0_list_base = 5'd0;
                matrix0_require_present = 1'b1;
                matrix1_sources = 10'd320;
                matrix1_row_tiles = 6'd20;
                matrix1_local_byte_offset = 32'd102400;
                matrix1_source_stride_bytes = 32'd320;
                matrix1_list_count = 3'd1;
                matrix1_list_base = 5'd1;
                parameter_local_byte_offset = 32'd204800;
                parameter_transfer_bytes = 32'd14560;
            end
            4'd2: begin
                stage_dram_byte_offset = 32'd358976;
                stage_transfer_bytes = 32'd21056;
                matrix_count = 2'd1;
                matrix0_sources = 10'd320;
                matrix0_row_tiles = 6'd4;
                matrix0_source_stride_bytes = 32'd64;
                matrix0_list_count = 3'd1;
                matrix0_list_base = 5'd1;
                matrix0_require_present = 1'b1;
                parameter_local_byte_offset = 32'd20480;
                parameter_transfer_bytes = 32'd576;
            end
            4'd3: begin
                stage_dram_byte_offset = 32'd380032;
                stage_transfer_bytes = 32'd70672;
                matrix0_dense = 1'b1;
                matrix0_sources = 10'd46;
                matrix0_row_tiles = 6'd14;
                matrix0_source_stride_bytes = 32'd224;
                matrix1_sources = 10'd224;
                matrix1_row_tiles = 6'd14;
                matrix1_local_byte_offset = 32'd10304;
                matrix1_source_stride_bytes = 32'd224;
                matrix1_list_count = 3'd4;
                matrix1_list_base = 5'd2;
                parameter_local_byte_offset = 32'd60480;
                parameter_transfer_bytes = 32'd10192;
            end
            4'd4: begin
                stage_dram_byte_offset = 32'd450752;
                stage_transfer_bytes = 32'd110544;
                matrix0_sources = 10'd224;
                matrix0_row_tiles = 6'd14;
                matrix0_source_stride_bytes = 32'd224;
                matrix0_list_count = 3'd4;
                matrix0_list_base = 5'd2;
                matrix0_require_present = 1'b1;
                matrix1_sources = 10'd224;
                matrix1_row_tiles = 6'd14;
                matrix1_local_byte_offset = 32'd50176;
                matrix1_source_stride_bytes = 32'd224;
                matrix1_list_count = 3'd4;
                matrix1_list_base = 5'd3;
                parameter_local_byte_offset = 32'd100352;
                parameter_transfer_bytes = 32'd10192;
            end
            4'd5: begin
                stage_dram_byte_offset = 32'd561344;
                stage_transfer_bytes = 32'd18640;
                matrix_count = 2'd1;
                matrix0_sources = 10'd224;
                matrix0_row_tiles = 6'd5;
                matrix0_source_stride_bytes = 32'd80;
                matrix0_list_count = 3'd4;
                matrix0_list_base = 5'd3;
                matrix0_require_present = 1'b1;
                parameter_local_byte_offset = 32'd17920;
                parameter_transfer_bytes = 32'd720;
            end
            4'd6: begin
                stage_dram_byte_offset = 32'd580032;
                stage_transfer_bytes = 32'd81424;
                matrix0_dense = 1'b1;
                matrix0_sources = 10'd94;
                matrix0_row_tiles = 6'd14;
                matrix0_source_stride_bytes = 32'd224;
                matrix1_sources = 10'd224;
                matrix1_row_tiles = 6'd14;
                matrix1_local_byte_offset = 32'd21056;
                matrix1_source_stride_bytes = 32'd224;
                matrix1_list_count = 3'd3;
                matrix1_list_base = 5'd10;
                parameter_local_byte_offset = 32'd71232;
                parameter_transfer_bytes = 32'd10192;
            end
            4'd7: begin
                stage_dram_byte_offset = 32'd661504;
                stage_transfer_bytes = 32'd110544;
                matrix0_sources = 10'd224;
                matrix0_row_tiles = 6'd14;
                matrix0_source_stride_bytes = 32'd224;
                matrix0_list_count = 3'd3;
                matrix0_list_base = 5'd10;
                matrix0_require_present = 1'b1;
                matrix1_sources = 10'd224;
                matrix1_row_tiles = 6'd14;
                matrix1_local_byte_offset = 32'd50176;
                matrix1_source_stride_bytes = 32'd224;
                matrix1_list_count = 3'd3;
                matrix1_list_base = 5'd11;
                parameter_local_byte_offset = 32'd100352;
                parameter_transfer_bytes = 32'd10192;
            end
            4'd8: begin
                stage_dram_byte_offset = 32'd772096;
                stage_transfer_bytes = 32'd44736;
                matrix_count = 2'd1;
                matrix0_sources = 10'd224;
                matrix0_row_tiles = 6'd12;
                matrix0_source_stride_bytes = 32'd192;
                matrix0_list_count = 3'd3;
                matrix0_list_base = 5'd11;
                matrix0_require_present = 1'b1;
                parameter_local_byte_offset = 32'd43008;
                parameter_transfer_bytes = 32'd1728;
            end
            4'd9: begin
                stage_dram_byte_offset = 32'd816832;
                stage_transfer_bytes = 32'd95760;
                matrix0_dense = 1'b1;
                matrix0_sources = 10'd158;
                matrix0_row_tiles = 6'd14;
                matrix0_source_stride_bytes = 32'd224;
                matrix1_sources = 10'd224;
                matrix1_row_tiles = 6'd14;
                matrix1_local_byte_offset = 32'd35392;
                matrix1_source_stride_bytes = 32'd224;
                matrix1_list_count = 3'd2;
                matrix1_list_base = 5'd16;
                parameter_local_byte_offset = 32'd85568;
                parameter_transfer_bytes = 32'd10192;
            end
            4'd10: begin
                stage_dram_byte_offset = 32'd912640;
                stage_transfer_bytes = 32'd110544;
                matrix0_sources = 10'd224;
                matrix0_row_tiles = 6'd14;
                matrix0_source_stride_bytes = 32'd224;
                matrix0_list_count = 3'd2;
                matrix0_list_base = 5'd16;
                matrix0_require_present = 1'b1;
                matrix1_sources = 10'd224;
                matrix1_row_tiles = 6'd14;
                matrix1_local_byte_offset = 32'd50176;
                matrix1_source_stride_bytes = 32'd224;
                matrix1_list_count = 3'd2;
                matrix1_list_base = 5'd17;
                parameter_local_byte_offset = 32'd100352;
                parameter_transfer_bytes = 32'd10192;
            end
            4'd11: begin
                stage_dram_byte_offset = 32'd1023232;
                stage_transfer_bytes = 32'd29824;
                matrix_count = 2'd1;
                matrix0_sources = 10'd224;
                matrix0_row_tiles = 6'd8;
                matrix0_source_stride_bytes = 32'd128;
                matrix0_list_count = 3'd2;
                matrix0_list_base = 5'd17;
                matrix0_require_present = 1'b1;
                parameter_local_byte_offset = 32'd28672;
                parameter_transfer_bytes = 32'd1152;
            end
            default: begin
                stage_valid = 1'b0;
                matrix_count = 2'd0;
            end
        endcase
    end
endmodule
