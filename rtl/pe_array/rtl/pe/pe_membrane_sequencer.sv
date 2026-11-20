`timescale 1ns/1ps

// Control-only schedule for reusing Hybrid MAC lanes and the local RQ bank.
module pe_membrane_sequencer #(parameter integer TAG_WIDTH=8) (
    input wire clk, input wire rst_n, input wire start,
    input wire [15:0] lane_mask_in, input wire [TAG_WIDTH-1:0] tag_in,
    output reg busy, output reg done, output reg [2:0] phase,
    output reg [15:0] pending_mask, output reg [TAG_WIDTH-1:0] tag_out,
    output reg pe_clear, output reg pe_enable, output reg [1:0] pe_mode,
    output reg local_rq_valid, input wire local_rq_ready,
    input wire local_rq_response_valid
);
    localparam IDLE=0, CLEAR=1, TERM_CX=2, TERM_CELL=3, RQ_REQUEST=4,
               RQ_WAIT=5, COMPLETE=6;
    always @* begin
        pe_clear=0; pe_enable=0; pe_mode=2'd2; local_rq_valid=0;
        case (phase)
            CLEAR: pe_clear=1;
            TERM_CX,TERM_CELL: begin pe_enable=1; pe_mode=2'd2; end
            RQ_REQUEST: local_rq_valid=1;
            default: begin end
        endcase
    end
    always @(posedge clk) begin
        if (!rst_n) begin busy<=0; done<=0; phase<=IDLE; pending_mask<=0; tag_out<=0; end
        else begin
            done<=0;
            case (phase)
                IDLE: if (start) begin busy<=1; pending_mask<=lane_mask_in; tag_out<=tag_in; phase<=CLEAR; end
                CLEAR: phase<=TERM_CX;
                TERM_CX: phase<=TERM_CELL;
                TERM_CELL: phase<=RQ_REQUEST;
                RQ_REQUEST: if (local_rq_ready) phase<=RQ_WAIT;
                RQ_WAIT: if (local_rq_response_valid) begin pending_mask<=0; phase<=COMPLETE; end
                COMPLETE: begin busy<=0; done<=1; phase<=IDLE; end
                default: phase<=IDLE;
            endcase
        end
    end
endmodule
