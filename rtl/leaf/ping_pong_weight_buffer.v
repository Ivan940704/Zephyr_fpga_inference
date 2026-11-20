`timescale 1ns/1ps

// Two local weight banks. DMA/config writes always target the inactive bank;
// PE reads always target the active bank.
module ping_pong_weight_buffer #(
    parameter WORD_WIDTH = 128,
    parameter DEPTH = 1024,
    parameter ADDR_WIDTH = 10
) (
    input  wire                      clk,
    input  wire                      rst,
    input  wire                      load_we,
    input  wire [ADDR_WIDTH-1:0]     load_addr,
    input  wire [WORD_WIDTH-1:0]     load_data,
    input  wire                      read_en,
    input  wire [ADDR_WIDTH-1:0]     read_addr,
    output reg  [WORD_WIDTH-1:0]     read_data,
    input  wire                      swap_banks,
    output reg                       active_bank
);
    reg [WORD_WIDTH-1:0] bank_a [0:DEPTH-1];
    reg [WORD_WIDTH-1:0] bank_b [0:DEPTH-1];

    always @(posedge clk) begin
        if (rst) begin
            active_bank <= 1'b0;
            read_data <= {WORD_WIDTH{1'b0}};
        end else begin
            if (load_we) begin
                if (active_bank)
                    bank_a[load_addr] <= load_data;
                else
                    bank_b[load_addr] <= load_data;
            end

            if (read_en) begin
                if (active_bank)
                    read_data <= bank_b[read_addr];
                else
                    read_data <= bank_a[read_addr];
            end

            if (swap_banks)
                active_bank <= ~active_bank;
        end
    end
endmodule
