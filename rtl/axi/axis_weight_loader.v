`timescale 1ns/1ps

// Repack AXI4-Stream beats into the 16-lane weight words used by the PE array.
// The default converts two 64-bit DMA beats into one 128-bit BRAM write.
module axis_weight_loader #(
    parameter AXIS_DATA_WIDTH = 64,
    parameter AXIS_KEEP_WIDTH = AXIS_DATA_WIDTH / 8,
    parameter WORD_WIDTH = 128,
    parameter ADDR_WIDTH = 10,
    parameter BEATS_PER_WORD = WORD_WIDTH / AXIS_DATA_WIDTH,
    parameter BEAT_COUNT_WIDTH = (BEATS_PER_WORD <= 1) ? 1 : $clog2(BEATS_PER_WORD)
) (
    input  wire                         aclk,
    input  wire                         aresetn,

    input  wire                         begin_load,
    input  wire [ADDR_WIDTH-1:0]        base_addr,

    input  wire [AXIS_DATA_WIDTH-1:0]   s_axis_tdata,
    input  wire [AXIS_KEEP_WIDTH-1:0]   s_axis_tkeep,
    input  wire                         s_axis_tvalid,
    output wire                         s_axis_tready,
    input  wire                         s_axis_tlast,

    output reg                          load_valid,
    input  wire                         load_ready,
    output reg  [ADDR_WIDTH-1:0]        load_addr,
    output reg  [WORD_WIDTH-1:0]        load_data,
    output reg                          load_last,

    output reg  [31:0]                  word_count,
    output reg                          protocol_error,
    output wire                         busy
);
    reg [BEAT_COUNT_WIDTH-1:0] beat_index;

    assign s_axis_tready = !load_valid;
    wire axis_fire = s_axis_tvalid && s_axis_tready;
    wire load_fire = load_valid && load_ready;
    assign busy = load_valid || (beat_index != {BEAT_COUNT_WIDTH{1'b0}});

    always @(posedge aclk) begin
        if (!aresetn) begin
            beat_index <= {BEAT_COUNT_WIDTH{1'b0}};
            load_valid <= 1'b0;
            load_addr <= {ADDR_WIDTH{1'b0}};
            load_data <= {WORD_WIDTH{1'b0}};
            load_last <= 1'b0;
            word_count <= 32'd0;
            protocol_error <= 1'b0;
        end else if (begin_load) begin
            beat_index <= {BEAT_COUNT_WIDTH{1'b0}};
            load_valid <= 1'b0;
            load_addr <= base_addr;
            load_data <= {WORD_WIDTH{1'b0}};
            load_last <= 1'b0;
            word_count <= 32'd0;
            protocol_error <= 1'b0;
        end else begin
            if (load_fire) begin
                load_valid <= 1'b0;
                load_addr <= load_addr + 1'b1;
                word_count <= word_count + 1'b1;
            end

            if (axis_fire) begin
                if (s_axis_tkeep != {AXIS_KEEP_WIDTH{1'b1}})
                    protocol_error <= 1'b1;

                if (s_axis_tlast && (beat_index != BEATS_PER_WORD - 1)) begin
                    // Weight words must not be truncated by packet boundaries.
                    protocol_error <= 1'b1;
                    beat_index <= {BEAT_COUNT_WIDTH{1'b0}};
                    load_data <= {WORD_WIDTH{1'b0}};
                end else begin
                    load_data[beat_index*AXIS_DATA_WIDTH +: AXIS_DATA_WIDTH]
                        <= s_axis_tdata;
                    if (beat_index == BEATS_PER_WORD - 1) begin
                        beat_index <= {BEAT_COUNT_WIDTH{1'b0}};
                        load_valid <= 1'b1;
                        load_last <= s_axis_tlast;
                    end else begin
                        beat_index <= beat_index + 1'b1;
                    end
                end
            end
        end
    end
endmodule

