`timescale 1ns/1ps

// Serial active-index encoder with ready/valid backpressure.
module spike_indexer #(
    parameter VECTOR_WIDTH = 320,
    parameter INDEX_WIDTH = 9
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         start,
    input  wire [VECTOR_WIDTH-1:0]      spike_vector,
    output reg                          index_valid,
    input  wire                         index_ready,
    output reg  [INDEX_WIDTH-1:0]       index_value,
    output reg  [INDEX_WIDTH:0]         active_count,
    output reg                          busy,
    output reg                          done
);
    reg [VECTOR_WIDTH-1:0] captured_vector;
    reg [INDEX_WIDTH-1:0] scan_index;

    always @(posedge clk) begin
        if (rst) begin
            captured_vector <= {VECTOR_WIDTH{1'b0}};
            scan_index <= {INDEX_WIDTH{1'b0}};
            index_valid <= 1'b0;
            index_value <= {INDEX_WIDTH{1'b0}};
            active_count <= {(INDEX_WIDTH+1){1'b0}};
            busy <= 1'b0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            if (start) begin
                captured_vector <= spike_vector;
                scan_index <= {INDEX_WIDTH{1'b0}};
                index_valid <= 1'b0;
                active_count <= {(INDEX_WIDTH+1){1'b0}};
                busy <= 1'b1;
            end else if (busy) begin
                if (index_valid) begin
                    if (index_ready) begin
                        index_valid <= 1'b0;
                        active_count <= active_count + 1'b1;
                        if (scan_index == VECTOR_WIDTH - 1) begin
                            busy <= 1'b0;
                            done <= 1'b1;
                        end else begin
                            scan_index <= scan_index + 1'b1;
                        end
                    end
                end else if (captured_vector[scan_index]) begin
                    index_value <= scan_index;
                    index_valid <= 1'b1;
                end else if (scan_index == VECTOR_WIDTH - 1) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end else begin
                    scan_index <= scan_index + 1'b1;
                end
            end
        end
    end
endmodule
