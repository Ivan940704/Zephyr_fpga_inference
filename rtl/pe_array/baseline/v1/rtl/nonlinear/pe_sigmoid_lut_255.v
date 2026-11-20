`timescale 1ns/1ps

// Four-lane, eight-table resident sigmoid lookup for the PE Array.
//
// Each table maps a signed gate value in [-127, 127] to an unsigned lambda
// value in [0, 255].  gate_in == -128 is outside the upstream arithmetic
// domain and is defensively mapped to table entry zero.
//
// The eight 255-byte tables are loaded in table-major order.  Each table uses
// a 256-entry address stride; address 255 is unused.  Two identical Xilinx
// RAMB18E1 true-dual-port memories provide the four independent lookup ports.
module pe_sigmoid_lut_255 #(
    parameter TAG_WIDTH = 8
) (
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         in_valid,
    output wire                         in_ready,
    input  wire [3:0]                   lane_valid_in,
    input  wire [31:0]                  gate_in,
    input  wire [(4*TAG_WIDTH)-1:0]     tag_in,
    input  wire [2:0]                   table_select,

    output reg                          out_valid,
    input  wire                         out_ready,
    output reg  [3:0]                   lane_valid_out,
    output wire [31:0]                  lambda_out,
    output reg  [(4*TAG_WIDTH)-1:0]     tag_out,

    input  wire                         cfg_start_valid,
    output wire                         cfg_start_ready,
    input  wire                         cfg_data_valid,
    output wire                         cfg_data_ready,
    input  wire [7:0]                   cfg_data,
    output reg                          cfg_done,
    output reg                          table_valid
);
    localparam integer TABLE_COUNT = 8;
    localparam integer TABLE_DEPTH = 256;

    wire [15:0] ram_01_do_a;
    wire [15:0] ram_01_do_b;
    wire [15:0] ram_23_do_a;
    wire [15:0] ram_23_do_b;

    reg       load_active;
    reg [2:0] cfg_table_index;
    reg [7:0] cfg_entry_index;

    wire output_advance;
    wire cfg_start_accept;
    wire cfg_write_accept;
    wire lookup_accept;
    wire [10:0] cfg_write_addr;
    wire [10:0] lookup_addr_0;
    wire [10:0] lookup_addr_1;
    wire [10:0] lookup_addr_2;
    wire [10:0] lookup_addr_3;
    wire [10:0] ram_01_addr_a;
    wire [10:0] ram_23_addr_a;

    function [7:0] gate_to_address;
        input [7:0] gate_value;
        begin
            if (gate_value == 8'h80)
                gate_to_address = 8'd0;
            else
                gate_to_address = gate_value + 8'd127;
        end
    endfunction

    assign output_advance = (~out_valid) | out_ready;

    // Configuration has priority over accepting a new lookup packet.  A new
    // load may start only after the elastic output register has drained.
    assign cfg_start_ready  = rst_n & (~load_active) & (~out_valid);
    assign cfg_start_accept = cfg_start_valid & cfg_start_ready;
    assign cfg_data_ready   = rst_n & load_active;
    assign cfg_write_accept = cfg_data_valid & cfg_data_ready;

    assign in_ready = rst_n & table_valid & (~load_active) &
                      (~cfg_start_valid) & output_advance;
    assign lookup_accept = in_valid & in_ready;

    assign cfg_write_addr = {cfg_table_index, cfg_entry_index};
    assign lookup_addr_0 = {table_select, gate_to_address(gate_in[7:0])};
    assign lookup_addr_1 = {table_select, gate_to_address(gate_in[15:8])};
    assign lookup_addr_2 = {table_select, gate_to_address(gate_in[23:16])};
    assign lookup_addr_3 = {table_select, gate_to_address(gate_in[31:24])};

    assign ram_01_addr_a = cfg_write_accept ? cfg_write_addr : lookup_addr_0;
    assign ram_23_addr_a = cfg_write_accept ? cfg_write_addr : lookup_addr_2;

    assign lambda_out = {
        ram_23_do_b[7:0],
        ram_23_do_a[7:0],
        ram_01_do_b[7:0],
        ram_01_do_a[7:0]
    };

    // A RAMB18E1 in 2048x9 true-dual-port mode stores all eight tables. Port A
    // is time-multiplexed between configuration writes and an even lookup lane;
    // port B is the matching odd lookup lane. Both replicas receive identical
    // configuration data.
    RAMB18E1 #(
        .DOA_REG(0),
        .DOB_REG(0),
        .READ_WIDTH_A(9),
        .READ_WIDTH_B(9),
        .WRITE_WIDTH_A(9),
        .WRITE_WIDTH_B(9),
        .RAM_MODE("TDP"),
        .WRITE_MODE_A("READ_FIRST"),
        .WRITE_MODE_B("READ_FIRST"),
        .SIM_COLLISION_CHECK("ALL")
    ) lut_replica_01 (
        .ADDRARDADDR({ram_01_addr_a, 3'b000}),
        .ADDRBWRADDR({lookup_addr_1, 3'b000}),
        .CLKARDCLK(clk),
        .CLKBWRCLK(clk),
        .DIADI({8'd0, cfg_data}),
        .DIBDI(16'd0),
        .DIPADIP(2'b00),
        .DIPBDIP(2'b00),
        .DOADO(ram_01_do_a),
        .DOBDO(ram_01_do_b),
        .DOPADOP(),
        .DOPBDOP(),
        .ENARDEN(cfg_write_accept | lookup_accept),
        .ENBWREN(lookup_accept),
        .REGCEAREGCE(1'b1),
        .REGCEB(1'b1),
        .RSTRAMARSTRAM(~rst_n),
        .RSTRAMB(~rst_n),
        .RSTREGARSTREG(~rst_n),
        .RSTREGB(~rst_n),
        .WEA({2{cfg_write_accept}}),
        .WEBWE(4'b0000)
    );

    RAMB18E1 #(
        .DOA_REG(0),
        .DOB_REG(0),
        .READ_WIDTH_A(9),
        .READ_WIDTH_B(9),
        .WRITE_WIDTH_A(9),
        .WRITE_WIDTH_B(9),
        .RAM_MODE("TDP"),
        .WRITE_MODE_A("READ_FIRST"),
        .WRITE_MODE_B("READ_FIRST"),
        .SIM_COLLISION_CHECK("ALL")
    ) lut_replica_23 (
        .ADDRARDADDR({ram_23_addr_a, 3'b000}),
        .ADDRBWRADDR({lookup_addr_3, 3'b000}),
        .CLKARDCLK(clk),
        .CLKBWRCLK(clk),
        .DIADI({8'd0, cfg_data}),
        .DIBDI(16'd0),
        .DIPADIP(2'b00),
        .DIPBDIP(2'b00),
        .DOADO(ram_23_do_a),
        .DOBDO(ram_23_do_b),
        .DOPADOP(),
        .DOPBDOP(),
        .ENARDEN(cfg_write_accept | lookup_accept),
        .ENBWREN(lookup_accept),
        .REGCEAREGCE(1'b1),
        .REGCEB(1'b1),
        .RSTRAMARSTRAM(~rst_n),
        .RSTRAMB(~rst_n),
        .RSTREGARSTREG(~rst_n),
        .RSTREGB(~rst_n),
        .WEA({2{cfg_write_accept}}),
        .WEBWE(4'b0000)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            out_valid       <= 1'b0;
            lane_valid_out  <= 4'b0000;
            tag_out         <= {(4*TAG_WIDTH){1'b0}};
            load_active     <= 1'b0;
            cfg_table_index <= 3'd0;
            cfg_entry_index <= 8'd0;
            cfg_done        <= 1'b0;
            table_valid     <= 1'b0;
        end else begin
            cfg_done <= 1'b0;

            if (cfg_start_accept) begin
                load_active     <= 1'b1;
                cfg_table_index <= 3'd0;
                cfg_entry_index <= 8'd0;
                table_valid     <= 1'b0;
            end else if (cfg_write_accept) begin
                if (cfg_entry_index == 8'd254) begin
                    cfg_entry_index <= 8'd0;
                    if (cfg_table_index == 3'd7) begin
                        cfg_table_index <= 3'd0;
                        load_active     <= 1'b0;
                        table_valid     <= 1'b1;
                        cfg_done        <= 1'b1;
                    end else begin
                        cfg_table_index <= cfg_table_index + 3'd1;
                    end
                end else begin
                    cfg_entry_index <= cfg_entry_index + 8'd1;
                end
            end

            if (output_advance) begin
                out_valid <= lookup_accept;
                if (lookup_accept) begin
                    lane_valid_out <= lane_valid_in;
                    tag_out        <= tag_in;
                end
            end
        end
    end
endmodule
