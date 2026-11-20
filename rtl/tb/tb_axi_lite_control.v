`timescale 1ns/1ps

module tb_axi_lite_control;
    reg aclk = 1'b0;
    reg aresetn;

    reg [5:0] s_axi_awaddr;
    reg s_axi_awvalid;
    wire s_axi_awready;
    reg [31:0] s_axi_wdata;
    reg [3:0] s_axi_wstrb;
    reg s_axi_wvalid;
    wire s_axi_wready;
    wire [1:0] s_axi_bresp;
    wire s_axi_bvalid;
    reg s_axi_bready;

    reg [5:0] s_axi_araddr;
    reg s_axi_arvalid;
    wire s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0] s_axi_rresp;
    wire s_axi_rvalid;
    reg s_axi_rready;

    reg status_busy;
    reg status_done;
    reg status_protocol_error;
    reg [31:0] cycle_count;
    wire start_pulse;
    wire clear_state_pulse;
    wire soft_reset_pulse;
    wire [15:0] frame_length;
    wire [31:0] config_word;
    wire done_sticky;
    wire error_sticky;
    wire irq;

    integer errors;
    integer start_pulses;
    integer clear_state_pulses;
    integer soft_reset_pulses;

    always #5 aclk = ~aclk;

    axi_lite_control dut (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .status_busy(status_busy),
        .status_done(status_done),
        .status_protocol_error(status_protocol_error),
        .cycle_count(cycle_count),
        .start_pulse(start_pulse),
        .clear_state_pulse(clear_state_pulse),
        .soft_reset_pulse(soft_reset_pulse),
        .frame_length(frame_length),
        .config_word(config_word),
        .done_sticky(done_sticky),
        .error_sticky(error_sticky),
        .irq(irq)
    );

    always @(posedge aclk) begin
        if (aresetn) begin
            if (start_pulse)
                start_pulses = start_pulses + 1;
            if (clear_state_pulse)
                clear_state_pulses = clear_state_pulses + 1;
            if (soft_reset_pulse)
                soft_reset_pulses = soft_reset_pulses + 1;
        end
    end

    task reset_dut;
        begin
            @(negedge aclk);
            aresetn = 1'b0;
            s_axi_awvalid = 1'b0;
            s_axi_wvalid = 1'b0;
            s_axi_bready = 1'b0;
            s_axi_arvalid = 1'b0;
            s_axi_rready = 1'b0;
            repeat (3) @(posedge aclk);
            @(negedge aclk);
            aresetn = 1'b1;
        end
    endtask

    task send_aw;
        input [5:0] address;
        input integer delay_cycles;
        integer accepted;
        begin
            repeat (delay_cycles) @(posedge aclk);
            @(negedge aclk);
            s_axi_awaddr = address;
            s_axi_awvalid = 1'b1;
            accepted = 0;
            while (!accepted) begin
                @(posedge aclk);
                if (s_axi_awready)
                    accepted = 1;
            end
            @(negedge aclk);
            s_axi_awvalid = 1'b0;
        end
    endtask

    task send_w;
        input [31:0] data;
        input [3:0] strobe;
        input integer delay_cycles;
        integer accepted;
        begin
            repeat (delay_cycles) @(posedge aclk);
            @(negedge aclk);
            s_axi_wdata = data;
            s_axi_wstrb = strobe;
            s_axi_wvalid = 1'b1;
            accepted = 0;
            while (!accepted) begin
                @(posedge aclk);
                if (s_axi_wready)
                    accepted = 1;
            end
            @(negedge aclk);
            s_axi_wvalid = 1'b0;
        end
    endtask

    task axi_write;
        input [5:0] address;
        input [31:0] data;
        input [3:0] strobe;
        input integer aw_delay;
        input integer w_delay;
        input integer response_stall;
        reg [1:0] held_resp;
        begin
            fork
                send_aw(address, aw_delay);
                send_w(data, strobe, w_delay);
            join
            wait (s_axi_bvalid);
            held_resp = s_axi_bresp;
            repeat (response_stall) begin
                @(posedge aclk); #1;
                if (!s_axi_bvalid || s_axi_bresp !== held_resp) begin
                    $display("ERROR AXI-Lite B channel changed under backpressure");
                    errors = errors + 1;
                end
            end
            @(negedge aclk);
            s_axi_bready = 1'b1;
            @(posedge aclk); #1;
            if (held_resp !== 2'b00) begin
                $display("ERROR AXI-Lite BRESP=%b expected OKAY", held_resp);
                errors = errors + 1;
            end
            @(negedge aclk);
            s_axi_bready = 1'b0;
        end
    endtask

    task axi_read_check;
        input [5:0] address;
        input [31:0] expected;
        input [31:0] mask;
        input integer response_stall;
        reg [31:0] held_data;
        reg [1:0] held_resp;
        integer accepted;
        begin
            @(negedge aclk);
            s_axi_araddr = address;
            s_axi_arvalid = 1'b1;
            accepted = 0;
            while (!accepted) begin
                @(posedge aclk);
                if (s_axi_arready)
                    accepted = 1;
            end
            @(negedge aclk);
            s_axi_arvalid = 1'b0;
            wait (s_axi_rvalid);
            held_data = s_axi_rdata;
            held_resp = s_axi_rresp;
            repeat (response_stall) begin
                @(posedge aclk); #1;
                if (!s_axi_rvalid || s_axi_rdata !== held_data ||
                    s_axi_rresp !== held_resp) begin
                    $display("ERROR AXI-Lite R channel changed under backpressure");
                    errors = errors + 1;
                end
            end
            if ((held_data & mask) !== (expected & mask)) begin
                $display("ERROR AXI-Lite read addr=%h got=%h expected=%h mask=%h",
                         address, held_data, expected, mask);
                errors = errors + 1;
            end
            if (held_resp !== 2'b00) begin
                $display("ERROR AXI-Lite RRESP=%b expected OKAY", held_resp);
                errors = errors + 1;
            end
            @(negedge aclk);
            s_axi_rready = 1'b1;
            @(posedge aclk);
            @(negedge aclk);
            s_axi_rready = 1'b0;
        end
    endtask

    initial begin
        aresetn = 0;
        s_axi_awaddr = 0;
        s_axi_awvalid = 0;
        s_axi_wdata = 0;
        s_axi_wstrb = 0;
        s_axi_wvalid = 0;
        s_axi_bready = 0;
        s_axi_araddr = 0;
        s_axi_arvalid = 0;
        s_axi_rready = 0;
        status_busy = 0;
        status_done = 0;
        status_protocol_error = 0;
        cycle_count = 32'h1234_5678;
        errors = 0;
        start_pulses = 0;
        clear_state_pulses = 0;
        soft_reset_pulses = 0;

        reset_dut();

        // AW first, W first, and simultaneous channels are all legal.
        axi_write(6'h08, 32'h1234_5678, 4'b0011, 0, 3, 2);
        axi_read_check(6'h08, 32'h0000_5678, 32'hffff_ffff, 2);
        axi_write(6'h08, 32'h0000_ab00, 4'b0010, 3, 0, 0);
        axi_read_check(6'h08, 32'h0000_ab78, 32'hffff_ffff, 0);

        axi_write(6'h0c, 32'hdead_beef, 4'b1111, 1, 1, 1);
        axi_write(6'h0c, 32'h1122_3344, 4'b0101, 0, 2, 0);
        axi_read_check(6'h0c, 32'hde22_be44, 32'hffff_ffff, 3);
        axi_read_check(6'h10, 32'h1234_5678, 32'hffff_ffff, 1);

        status_busy = 1'b1;
        axi_read_check(6'h04, 32'h0000_0001, 32'h0000_000f, 0);
        status_busy = 1'b0;

        @(negedge aclk); status_done = 1'b1;
        @(posedge aclk); @(negedge aclk); status_done = 1'b0;
        axi_read_check(6'h04, 32'h0000_000a, 32'h0000_000f, 2);

        // CONTROL produces one-cycle pulses and START clears done sticky.
        axi_write(6'h00, 32'h0000_000b, 4'b0001, 2, 0, 1);
        repeat (2) @(posedge aclk);
        if (start_pulses != 1 || clear_state_pulses != 1 ||
            soft_reset_pulses != 1) begin
            $display("ERROR control pulse counts start/clear/reset=%0d/%0d/%0d",
                     start_pulses, clear_state_pulses, soft_reset_pulses);
            errors = errors + 1;
        end
        if (done_sticky) begin
            $display("ERROR start did not clear done_sticky");
            errors = errors + 1;
        end

        @(negedge aclk); status_protocol_error = 1'b1;
        @(posedge aclk); @(negedge aclk); status_protocol_error = 1'b0;
        axi_read_check(6'h04, 32'h0000_000c, 32'h0000_000f, 0);
        axi_write(6'h00, 32'h0000_0004, 4'b0001, 0, 0, 0);
        axi_read_check(6'h04, 32'h0000_0000, 32'h0000_000e, 0);

        // A partial write address must be discarded by reset; no response may
        // appear until a complete post-reset transaction is issued.
        fork
            send_aw(6'h0c, 0);
        join
        reset_dut();
        repeat (3) @(posedge aclk);
        if (s_axi_bvalid || s_axi_rvalid || frame_length != 0 || config_word != 0 ||
            done_sticky || error_sticky || irq) begin
            $display("ERROR AXI-Lite reset did not clear state/registers");
            errors = errors + 1;
        end
        axi_write(6'h08, 32'h0000_009e, 4'b0011, 0, 0, 0);
        axi_read_check(6'h08, 32'h0000_009e, 32'hffff_ffff, 0);

        if (errors == 0) begin
            $display("AXIL_METRIC writes_tested=7 reads_tested=9 aw_w_skew=1 backpressure=1");
            $display("PASS tb_axi_lite_control");
        end else begin
            $fatal(1, "FAIL tb_axi_lite_control errors=%0d", errors);
        end
        $finish;
    end
endmodule
