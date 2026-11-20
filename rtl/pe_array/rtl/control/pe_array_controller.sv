`timescale 1ns/1ps

module pe_array_controller (
    input wire clk, input wire rst_n, input wire start,
    input wire phase_done,
    output reg [3:0] state, output reg phase_start,
    output reg busy, output reg done
);
    localparam IDLE=0, FB1_INPUT=1, FB1_RECURRENT=2, FB1_POST=3,
      FB1_MEMBRANE=4, FB2_INPUT=5, FB2_RECURRENT=6, FB2_POST=7,
      FB2_MEMBRANE=8, PROJECTION=9, PROJECTION_POST=10,
      DEEPFILTER=11, COMPLETE=12;
    always @(posedge clk) begin
        if (!rst_n) begin state<=IDLE; phase_start<=0; busy<=0; done<=0; end
        else begin
            phase_start<=0; done<=0;
            if (state==IDLE) begin
                busy<=0;
                if (start) begin state<=FB1_INPUT; phase_start<=1; busy<=1; end
            end else if (state==COMPLETE) begin state<=IDLE; busy<=0; done<=1; end
            else if (phase_done) begin state<=state+1'b1; phase_start<=1; end
        end
    end
endmodule
