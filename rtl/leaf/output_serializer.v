`timescale 1ns/1ps

module output_serializer #(
    parameter LANES = 16,
    parameter DATA_WIDTH = 32,
    parameter INDEX_WIDTH = 4
) (
    input  wire                          clk,
    input  wire                          rst,
    input  wire                          load,
    input  wire [LANES*DATA_WIDTH-1:0]   parallel_data,
    output wire                          output_valid,
    input  wire                          output_ready,
    output wire [DATA_WIDTH-1:0]         output_data,
    output wire [INDEX_WIDTH-1:0]        output_index,
    output wire                          output_last,
    output reg                           busy,
    output reg                           done
);
    reg [LANES*DATA_WIDTH-1:0] data_q;
    reg [INDEX_WIDTH-1:0] lane_q;

    assign output_valid = busy;
    assign output_index = lane_q;
    assign output_data = data_q[lane_q*DATA_WIDTH +: DATA_WIDTH];
    assign output_last = busy && (lane_q == LANES - 1);

    always @(posedge clk) begin
        if (rst) begin
            data_q <= {(LANES*DATA_WIDTH){1'b0}};
            lane_q <= {INDEX_WIDTH{1'b0}};
            busy <= 1'b0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            if (load && !busy) begin
                data_q <= parallel_data;
                lane_q <= {INDEX_WIDTH{1'b0}};
                busy <= 1'b1;
            end else if (busy && output_ready) begin
                if (lane_q == LANES - 1) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end else begin
                    lane_q <= lane_q + 1'b1;
                end
            end
        end
    end
endmodule
