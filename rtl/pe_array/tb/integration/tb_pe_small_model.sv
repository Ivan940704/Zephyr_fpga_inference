`timescale 1ns/1ps
module tb_pe_small_model;
  localparam WIDTH=1166, MAX_COMMANDS=20000;
  reg clk=0,rst_n=0,start=0,phase_done=0; always #2.5 clk=~clk;
  reg [WIDTH-1:0] commands[0:MAX_COMMANDS-1]; reg [8*512-1:0] command_file;
  integer command_count,i,lane,errors=0,checks=0; reg test_passed=0;
  reg mac_clear,mac_issue;reg[1:0]mac_mode;reg[16*8-1:0]operand_a,operand_b,gate;
  reg[15:0]spike;reg[16*32-1:0]direct;wire[16*32-1:0]acc;wire[15:0]overflow;
  wire[3:0]state;wire phase_start,busy,done;
  pe_array_top dut(.clk(clk),.rst_n(rst_n),.start(start),.phase_done(phase_done),.state(state),
    .phase_start(phase_start),.busy(busy),.done(done),.mac_clear(mac_clear),.mac_issue(mac_issue),
    .mac_mode(mac_mode),.operand_a(operand_a),.operand_b(operand_b),.gate_u8(gate),
    .spike_enable(spike),.direct_value(direct),.accumulators(acc),.overflow(overflow));
  initial begin #2000000;$fatal(1,"FAIL tb_pe_small_model watchdog command=%0d",i);end
  initial begin
    if(!$value$plusargs("COMMAND_FILE=%s",command_file))$fatal(1,"missing COMMAND_FILE");
    if(!$value$plusargs("COMMAND_COUNT=%d",command_count))$fatal(1,"missing COMMAND_COUNT");
    $readmemh(command_file,commands); mac_clear=0;mac_issue=0;mac_mode=0;operand_a=0;operand_b=0;gate=0;spike=0;direct=0;
    repeat(3)@(posedge clk);@(negedge clk);rst_n=1;
    for(i=0;i<command_count;i=i+1)begin
      @(negedge clk);
      mac_clear=commands[i][0];mac_issue=commands[i][1];mac_mode=commands[i][3:2];
      for(lane=0;lane<16;lane=lane+1)operand_a[lane*8 +:8]=commands[i][11:4];
      spike={16{commands[i][12]}};operand_b=commands[i][140:13];direct=commands[i][652:141];
      @(posedge clk);#1;
      if(commands[i][653])begin
        checks=checks+1;
        for(lane=0;lane<16;lane=lane+1)
          if($signed(acc[lane*32 +:32])!==$signed(commands[i][654+lane*32 +:32]))begin
            errors=errors+1;if(errors<12)$display("FAIL cmd=%0d lane=%0d got=%0d expected=%0d",i,lane,$signed(acc[lane*32 +:32]),$signed(commands[i][654+lane*32 +:32]));
          end
      end
    end
    if(overflow!==0)begin $display("FAIL unexpected overflow=%h",overflow);errors=errors+1;end
    if(errors==0)begin test_passed=1;$display("PE_SMALL_MODEL_METRICS commands=%0d tile_checks=%0d shape=64x320x320x64 df_orders=5_3_1",command_count,checks);$display("PASS tb_pe_small_model");end
    else $fatal(1,"FAIL tb_pe_small_model errors=%0d",errors);
    $finish;
  end
endmodule
