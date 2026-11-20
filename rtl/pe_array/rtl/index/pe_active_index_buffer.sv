`timescale 1ns/1ps
module pe_active_index_buffer #(parameter integer DEPTH=320, INDEX_WIDTH=9) (
    input wire clk, input wire rst_n, input wire frame_clear,
    input wire write_valid, output wire write_ready,
    input wire [INDEX_WIDTH-1:0] write_index,
    input wire finalize, output reg finalized, output reg overflow,
    output reg [$clog2(DEPTH+1)-1:0] count,
    input wire [$clog2(DEPTH)-1:0] read_addr,
    output wire [INDEX_WIDTH-1:0] read_index
);
    reg [INDEX_WIDTH-1:0] mem[0:DEPTH-1];
    assign write_ready = (count < DEPTH) && !finalized;
    assign read_index = mem[read_addr];
    always @(posedge clk) begin
        if (!rst_n || frame_clear) begin count<=0; finalized<=0; overflow<=0; end
        else begin
            if (write_valid) begin
                if (write_ready) begin mem[count] <= write_index; count <= count + 1'b1; end
                else overflow <= 1'b1;
            end
            if (finalize) finalized <= 1'b1;
        end
    end
endmodule
