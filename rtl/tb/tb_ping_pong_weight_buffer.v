`timescale 1ns/1ps

module tb_ping_pong_weight_buffer;
    reg clk = 1'b0;
    reg rst;
    reg load_we;
    reg [1:0] load_addr;
    reg [31:0] load_data;
    reg read_en;
    reg [1:0] read_addr;
    wire [31:0] read_data;
    reg swap_banks;
    wire active_bank;
    integer errors;

    always #5 clk = ~clk;

    ping_pong_weight_buffer #(.WORD_WIDTH(32), .DEPTH(4), .ADDR_WIDTH(2)) dut (
        .clk(clk), .rst(rst), .load_we(load_we), .load_addr(load_addr), .load_data(load_data),
        .read_en(read_en), .read_addr(read_addr), .read_data(read_data),
        .swap_banks(swap_banks), .active_bank(active_bank)
    );

    task write_inactive;
        input [1:0] addr;
        input [31:0] data;
        begin
            @(negedge clk); load_we = 1; load_addr = addr; load_data = data;
            @(posedge clk); #1; load_we = 0;
        end
    endtask

    task swap;
        begin
            @(negedge clk); swap_banks = 1;
            @(posedge clk); #1; swap_banks = 0;
        end
    endtask

    task check_read;
        input [1:0] addr;
        input [31:0] expected;
        begin
            @(negedge clk); read_en = 1; read_addr = addr;
            @(posedge clk); #1; read_en = 0;
            if (read_data !== expected) begin
                $display("ERROR pingpong bank=%0d addr=%0d got=%h expected=%h",
                         active_bank, addr, read_data, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0; rst = 1; load_we = 0; load_addr = 0; load_data = 0;
        read_en = 0; read_addr = 0; swap_banks = 0;
        repeat (2) @(posedge clk); @(negedge clk); rst = 0;

        write_inactive(0, 32'haaaa0000); write_inactive(1, 32'haaaa0001);
        swap();
        if (active_bank !== 1'b1) begin
            $display("ERROR pingpong expected bank B active"); errors = errors + 1;
        end
        check_read(0, 32'haaaa0000); check_read(1, 32'haaaa0001);

        write_inactive(0, 32'hbbbb0000); write_inactive(1, 32'hbbbb0001);
        check_read(0, 32'haaaa0000);
        swap();
        if (active_bank !== 1'b0) begin
            $display("ERROR pingpong expected bank A active"); errors = errors + 1;
        end
        check_read(0, 32'hbbbb0000); check_read(1, 32'hbbbb0001);

        if (errors == 0) $display("PASS tb_ping_pong_weight_buffer");
        else $fatal(1, "FAIL tb_ping_pong_weight_buffer errors=%0d", errors);
        $finish;
    end
endmodule
