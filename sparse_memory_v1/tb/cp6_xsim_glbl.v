`timescale 1ps/1ps

// CP6-local XSim compatibility model.  The Vivado 2018.3 RAMB18E1 simulation
// primitive references glbl.GSR hierarchically.  Keeping this minimal model in
// the isolated allowlist avoids compiling the tool installation's glbl.v as a
// repository input.  It is simulation-only and is never read by either OOC
// synthesis runner.
module glbl;
    parameter ROC_WIDTH = 100000;

    wire GSR;
    reg GSR_int;

    assign (strong1, weak0) GSR = GSR_int;

    initial begin
        GSR_int = 1'b1;
        #(ROC_WIDTH);
        GSR_int = 1'b0;
    end
endmodule
