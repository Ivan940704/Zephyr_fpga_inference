`timescale 1ns/1ps

// AXI4-Stream to one-byte ready/valid adapter.
//
// Bytes are emitted in increasing TDATA lane order.  TKEEP holes are skipped,
// and native_last is asserted only with the final kept byte of a TLAST beat.
// One AXI beat is buffered; the final byte may be consumed in the same cycle
// that the next AXI beat is accepted.
module axis_int8_ingress #(
    parameter AXIS_DATA_WIDTH = 64,
    parameter AXIS_KEEP_WIDTH = AXIS_DATA_WIDTH / 8
) (
    input  wire                         aclk,
    input  wire                         aresetn,

    input  wire [AXIS_DATA_WIDTH-1:0]   s_axis_tdata,
    input  wire [AXIS_KEEP_WIDTH-1:0]   s_axis_tkeep,
    input  wire                         s_axis_tvalid,
    output wire                         s_axis_tready,
    input  wire                         s_axis_tlast,

    output wire                         native_valid,
    input  wire                         native_ready,
    output wire signed [7:0]            native_data,
    output wire                         native_last,

    output reg                          protocol_error
);
    reg [AXIS_DATA_WIDTH-1:0] beat_data;
    reg [AXIS_KEEP_WIDTH-1:0] beat_keep;
    reg                       beat_last;
    reg                       beat_valid;

    reg [7:0]                 selected_data;
    reg [AXIS_KEEP_WIDTH-1:0] selected_mask;
    reg                       selected_found;
    integer                   lane;

    always @* begin
        selected_data = 8'd0;
        selected_mask = {AXIS_KEEP_WIDTH{1'b0}};
        selected_found = 1'b0;
        for (lane = 0; lane < AXIS_KEEP_WIDTH; lane = lane + 1) begin
            if (!selected_found && beat_keep[lane]) begin
                selected_data = beat_data[lane*8 +: 8];
                selected_mask[lane] = 1'b1;
                selected_found = 1'b1;
            end
        end
    end

    assign native_valid = beat_valid && selected_found;
    assign native_data = selected_data;
    assign native_last = beat_last && (beat_keep == selected_mask);

    wire native_fire = native_valid && native_ready;
    wire native_final_fire = native_fire && (beat_keep == selected_mask);

    // Accept a new beat when empty, or replace the beat whose final byte is
    // being consumed on this clock edge.
    assign s_axis_tready = !beat_valid || native_final_fire;
    wire axis_fire = s_axis_tvalid && s_axis_tready;

    always @(posedge aclk) begin
        if (!aresetn) begin
            beat_data <= {AXIS_DATA_WIDTH{1'b0}};
            beat_keep <= {AXIS_KEEP_WIDTH{1'b0}};
            beat_last <= 1'b0;
            beat_valid <= 1'b0;
            protocol_error <= 1'b0;
        end else begin
            if (axis_fire) begin
                if (s_axis_tkeep == {AXIS_KEEP_WIDTH{1'b0}}) begin
                    // A zero-byte transfer cannot be represented on the native
                    // interface.  Consume it to avoid deadlock and flag it.
                    beat_data <= {AXIS_DATA_WIDTH{1'b0}};
                    beat_keep <= {AXIS_KEEP_WIDTH{1'b0}};
                    beat_last <= 1'b0;
                    beat_valid <= 1'b0;
                    protocol_error <= 1'b1;
                end else begin
                    beat_data <= s_axis_tdata;
                    beat_keep <= s_axis_tkeep;
                    beat_last <= s_axis_tlast;
                    beat_valid <= 1'b1;
                end
            end else if (native_fire) begin
                beat_keep <= beat_keep & ~selected_mask;
                if ((beat_keep & ~selected_mask) == {AXIS_KEEP_WIDTH{1'b0}}) begin
                    beat_last <= 1'b0;
                    beat_valid <= 1'b0;
                end
            end
        end
    end
endmodule

