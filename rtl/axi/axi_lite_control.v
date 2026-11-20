`timescale 1ns/1ps

// Minimal AXI4-Lite control/status block for the later Zephyr top-level.
//
// 0x00 CONTROL (write pulses): bit0 start, bit1 clear_state,
//                              bit2 clear sticky status, bit3 soft_reset
// 0x04 STATUS  (read only):    bit0 busy, bit1 done_sticky,
//                              bit2 error_sticky, bit3 irq
// 0x08 FRAME_LENGTH (read/write, low 16 bits)
// 0x0c CONFIG       (read/write)
// 0x10 CYCLE_COUNT  (read only)
module axi_lite_control #(
    parameter AXI_ADDR_WIDTH = 6,
    parameter AXI_DATA_WIDTH = 32
) (
    input  wire                         aclk,
    input  wire                         aresetn,

    input  wire [AXI_ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire                         s_axi_awvalid,
    output wire                         s_axi_awready,
    input  wire [AXI_DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire [AXI_DATA_WIDTH/8-1:0]  s_axi_wstrb,
    input  wire                         s_axi_wvalid,
    output wire                         s_axi_wready,
    output reg  [1:0]                   s_axi_bresp,
    output reg                          s_axi_bvalid,
    input  wire                         s_axi_bready,

    input  wire [AXI_ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire                         s_axi_arvalid,
    output wire                         s_axi_arready,
    output reg  [AXI_DATA_WIDTH-1:0]    s_axi_rdata,
    output reg  [1:0]                   s_axi_rresp,
    output reg                          s_axi_rvalid,
    input  wire                         s_axi_rready,

    input  wire                         status_busy,
    input  wire                         status_done,
    input  wire                         status_protocol_error,
    input  wire [31:0]                  cycle_count,

    output reg                          start_pulse,
    output reg                          clear_state_pulse,
    output reg                          soft_reset_pulse,
    output reg  [15:0]                  frame_length,
    output reg  [31:0]                  config_word,
    output reg                          done_sticky,
    output reg                          error_sticky,
    output wire                         irq
);
    reg [AXI_ADDR_WIDTH-1:0] awaddr_hold;
    reg                      aw_hold_valid;
    reg [AXI_DATA_WIDTH-1:0] wdata_hold;
    reg [AXI_DATA_WIDTH/8-1:0] wstrb_hold;
    reg                      w_hold_valid;
    integer                  byte_index;

    assign s_axi_awready = !aw_hold_valid && !s_axi_bvalid;
    assign s_axi_wready = !w_hold_valid && !s_axi_bvalid;
    assign s_axi_arready = !s_axi_rvalid;
    assign irq = done_sticky || error_sticky;

    always @(posedge aclk) begin
        if (!aresetn) begin
            awaddr_hold <= {AXI_ADDR_WIDTH{1'b0}};
            aw_hold_valid <= 1'b0;
            wdata_hold <= {AXI_DATA_WIDTH{1'b0}};
            wstrb_hold <= {(AXI_DATA_WIDTH/8){1'b0}};
            w_hold_valid <= 1'b0;
            s_axi_bresp <= 2'b00;
            s_axi_bvalid <= 1'b0;
            s_axi_rdata <= {AXI_DATA_WIDTH{1'b0}};
            s_axi_rresp <= 2'b00;
            s_axi_rvalid <= 1'b0;
            start_pulse <= 1'b0;
            clear_state_pulse <= 1'b0;
            soft_reset_pulse <= 1'b0;
            frame_length <= 16'd0;
            config_word <= 32'd0;
            done_sticky <= 1'b0;
            error_sticky <= 1'b0;
        end else begin
            start_pulse <= 1'b0;
            clear_state_pulse <= 1'b0;
            soft_reset_pulse <= 1'b0;

            if (status_done)
                done_sticky <= 1'b1;
            if (status_protocol_error)
                error_sticky <= 1'b1;

            if (s_axi_awvalid && s_axi_awready) begin
                awaddr_hold <= s_axi_awaddr;
                aw_hold_valid <= 1'b1;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                wdata_hold <= s_axi_wdata;
                wstrb_hold <= s_axi_wstrb;
                w_hold_valid <= 1'b1;
            end

            if (!s_axi_bvalid && aw_hold_valid && w_hold_valid) begin
                case (awaddr_hold[5:2])
                    4'h0: begin
                        if (wstrb_hold[0]) begin
                            start_pulse <= wdata_hold[0];
                            clear_state_pulse <= wdata_hold[1];
                            soft_reset_pulse <= wdata_hold[3];
                            if (wdata_hold[0])
                                done_sticky <= 1'b0;
                            if (wdata_hold[2]) begin
                                done_sticky <= 1'b0;
                                error_sticky <= 1'b0;
                            end
                        end
                    end
                    4'h2: begin
                        for (byte_index = 0; byte_index < 2; byte_index = byte_index + 1)
                            if (wstrb_hold[byte_index])
                                frame_length[byte_index*8 +: 8]
                                    <= wdata_hold[byte_index*8 +: 8];
                    end
                    4'h3: begin
                        for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1)
                            if (wstrb_hold[byte_index])
                                config_word[byte_index*8 +: 8]
                                    <= wdata_hold[byte_index*8 +: 8];
                    end
                    default: begin
                    end
                endcase
                aw_hold_valid <= 1'b0;
                w_hold_valid <= 1'b0;
                s_axi_bresp <= 2'b00;
                s_axi_bvalid <= 1'b1;
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            if (s_axi_arvalid && s_axi_arready) begin
                case (s_axi_araddr[5:2])
                    4'h0: s_axi_rdata <= 32'd0;
                    4'h1: s_axi_rdata <= {28'd0, irq, error_sticky,
                                           done_sticky, status_busy};
                    4'h2: s_axi_rdata <= {16'd0, frame_length};
                    4'h3: s_axi_rdata <= config_word;
                    4'h4: s_axi_rdata <= cycle_count;
                    default: s_axi_rdata <= 32'd0;
                endcase
                s_axi_rresp <= 2'b00;
                s_axi_rvalid <= 1'b1;
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end
endmodule
