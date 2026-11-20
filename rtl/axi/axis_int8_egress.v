`timescale 1ns/1ps

// One-byte ready/valid to AXI4-Stream adapter.
//
// Native bytes are packed into increasing TDATA lanes.  A beat is presented
// when full or when native_last terminates a partial packet.  TVALID payload is
// held stable for arbitrary downstream backpressure.
module axis_int8_egress #(
    parameter AXIS_DATA_WIDTH = 64,
    parameter AXIS_KEEP_WIDTH = AXIS_DATA_WIDTH / 8,
    parameter COUNT_WIDTH = $clog2(AXIS_KEEP_WIDTH + 1)
) (
    input  wire                         aclk,
    input  wire                         aresetn,

    input  wire                         native_valid,
    output wire                         native_ready,
    input  wire signed [7:0]            native_data,
    input  wire                         native_last,

    output reg  [AXIS_DATA_WIDTH-1:0]   m_axis_tdata,
    output reg  [AXIS_KEEP_WIDTH-1:0]   m_axis_tkeep,
    output reg                          m_axis_tvalid,
    input  wire                         m_axis_tready,
    output reg                          m_axis_tlast
);
    reg [COUNT_WIDTH-1:0] byte_count;

    // This compact adapter uses one output register.  It deliberately inserts
    // a cycle between output beats instead of consuming additional FIFO BRAM.
    assign native_ready = !m_axis_tvalid;
    wire native_fire = native_valid && native_ready;

    always @(posedge aclk) begin
        if (!aresetn) begin
            byte_count <= {COUNT_WIDTH{1'b0}};
            m_axis_tdata <= {AXIS_DATA_WIDTH{1'b0}};
            m_axis_tkeep <= {AXIS_KEEP_WIDTH{1'b0}};
            m_axis_tvalid <= 1'b0;
            m_axis_tlast <= 1'b0;
        end else begin
            if (m_axis_tvalid && m_axis_tready) begin
                m_axis_tdata <= {AXIS_DATA_WIDTH{1'b0}};
                m_axis_tkeep <= {AXIS_KEEP_WIDTH{1'b0}};
                m_axis_tvalid <= 1'b0;
                m_axis_tlast <= 1'b0;
            end

            if (native_fire) begin
                m_axis_tdata[byte_count*8 +: 8] <= native_data;
                m_axis_tkeep[byte_count] <= 1'b1;
                if ((byte_count == AXIS_KEEP_WIDTH - 1) || native_last) begin
                    byte_count <= {COUNT_WIDTH{1'b0}};
                    m_axis_tvalid <= 1'b1;
                    m_axis_tlast <= native_last;
                end else begin
                    byte_count <= byte_count + 1'b1;
                end
            end
        end
    end
endmodule

