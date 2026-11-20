`timescale 1ns/1ps

module pe_output_serializer #(
    parameter integer LANES = 16,
    parameter integer VALUE_WIDTH = 32,
    parameter integer INDEX_WIDTH = 9,
    parameter integer TAG_WIDTH = 8
) (
    input  wire clk, input wire rst_n,
    input  wire load_valid, output wire load_ready,
    input  wire [LANES*VALUE_WIDTH-1:0] values_in,
    input  wire [LANES-1:0] lane_valid_in,
    input  wire [INDEX_WIDTH-1:0] base_index_in,
    input  wire [TAG_WIDTH-1:0] tag_in,
    output wire out_valid, input wire out_ready,
    output wire signed [VALUE_WIDTH-1:0] value_out,
    output wire [INDEX_WIDTH-1:0] index_out,
    output wire [TAG_WIDTH-1:0] tag_out,
    output wire out_last, output wire busy, output reg done
);
    reg [LANES*VALUE_WIDTH-1:0] values;
    reg [LANES-1:0] pending;
    reg [INDEX_WIDTH-1:0] base_index;
    reg [TAG_WIDTH-1:0] tag;
    integer scan;
    reg [$clog2(LANES)-1:0] selected;
    reg found;

    always @* begin
        selected = {$clog2(LANES){1'b0}};
        found = 1'b0;
        for (scan = 0; scan < LANES; scan = scan + 1)
            if (!found && pending[scan]) begin selected = scan; found = 1'b1; end
    end

    assign busy = |pending;
    assign load_ready = ~busy;
    assign out_valid = found;
    assign value_out = values[selected*VALUE_WIDTH +: VALUE_WIDTH];
    assign index_out = base_index + selected;
    assign tag_out = tag;
    assign out_last = found && ((pending & ~( {{(LANES-1){1'b0}},1'b1} << selected)) == 0);

    always @(posedge clk) begin
        if (!rst_n) begin
            pending <= {LANES{1'b0}};
            values <= {(LANES*VALUE_WIDTH){1'b0}};
            base_index <= {INDEX_WIDTH{1'b0}};
            tag <= {TAG_WIDTH{1'b0}};
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            if (load_valid && load_ready) begin
                values <= values_in;
                pending <= lane_valid_in;
                base_index <= base_index_in;
                tag <= tag_in;
                if (lane_valid_in == {LANES{1'b0}}) done <= 1'b1;
            end else if (out_valid && out_ready) begin
                pending[selected] <= 1'b0;
                if (out_last) done <= 1'b1;
            end
        end
    end
endmodule
