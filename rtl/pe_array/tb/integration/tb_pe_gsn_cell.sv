`timescale 1ns/1ps
module tb_pe_gsn_cell;
  localparam WIDTH=490,MAX_VECTORS=700;
  reg clk=0,rst_n=0;always #2.5 clk=~clk;
  reg[WIDTH-1:0]vectors[0:MAX_VECTORS-1];reg[7:0]lut0[0:254],lut1[0:254];
  reg[8*512-1:0]vector_file,lut0_file,lut1_file;integer vector_count;
  integer i,j,errors=0,latency,min_latency=100000,max_latency=0,current_layer=-1;
  integer clipped_vectors=0,stall_vectors=0;reg test_passed=0;

  reg start_valid=0,result_ready=1,cfg_we=0;wire start_ready,result_valid,busy;
  reg signed[31:0]input_acc,recurrent_acc;reg signed[7:0]previous_state;
  reg signed[31:0]fim,frm,fbias,cim,crm,cbias,pm,cm,bm,bb;
  reg[5:0]fis,frs,cis,crs,ps,cs,bs;reg[9:0]tag;reg[7:0]cfg_addr,cfg_data;
  wire signed[7:0]forget_q,cellgate_q,state_pre_q,state_q;wire[7:0]lambda;
  wire spike,fc,cc,pc,sc;wire[9:0]tag_out;

  pe_gsn_cell dut(.clk(clk),.rst_n(rst_n),.start_valid(start_valid),.start_ready(start_ready),
    .input_acc(input_acc),.recurrent_acc(recurrent_acc),.previous_state_q(previous_state),
    .forget_input_multiplier(fim),.forget_input_shift(fis),.forget_recurrent_multiplier(frm),
    .forget_recurrent_shift(frs),.forget_bias_q(fbias),.cell_input_multiplier(cim),
    .cell_input_shift(cis),.cell_recurrent_multiplier(crm),.cell_recurrent_shift(crs),
    .cell_bias_q(cbias),.previous_multiplier(pm),.previous_shift(ps),
    .cellgate_multiplier(cm),.cellgate_shift(cs),.bn_multiplier(bm),.bn_shift(bs),
    .bn_bias_q(bb),.tag_in(tag),.cfg_we(cfg_we),.cfg_addr(cfg_addr),.cfg_data(cfg_data),
    .result_valid(result_valid),.result_ready(result_ready),.forget_q(forget_q),
    .cellgate_q(cellgate_q),.forget_lambda_u8(lambda),.state_pre_q(state_pre_q),
    .state_q(state_q),.spike_q(spike),.forget_clipped(fc),.cellgate_clipped(cc),
    .state_pre_clipped(pc),.state_clipped(sc),.tag_out(tag_out),.busy(busy));

  task tick;begin @(posedge clk);#1;end endtask
  task apply_vector;input integer index;begin
    input_acc=vectors[index][32:1];recurrent_acc=vectors[index][64:33];previous_state=vectors[index][72:65];
    fim=vectors[index][104:73];fis=vectors[index][110:105];frm=vectors[index][142:111];frs=vectors[index][148:143];fbias=vectors[index][180:149];
    cim=vectors[index][212:181];cis=vectors[index][218:213];crm=vectors[index][250:219];crs=vectors[index][256:251];cbias=vectors[index][288:257];
    pm=vectors[index][320:289];ps=vectors[index][326:321];cm=vectors[index][358:327];cs=vectors[index][364:359];
    bm=vectors[index][396:365];bs=vectors[index][402:397];bb=vectors[index][434:403];tag=vectors[index][444:435];
  end endtask
  task load_lut;input integer layer;begin
    for(j=0;j<255;j=j+1)begin @(negedge clk);cfg_we=1;cfg_addr=j;cfg_data=(layer==0)?lut0[j]:lut1[j];tick;end
    @(negedge clk);cfg_we=0;tick;current_layer=layer;
  end endtask
  task compare_result;input integer index;input count_clip;begin
    if(forget_q!==vectors[index][452:445]||cellgate_q!==vectors[index][460:453]||lambda!==vectors[index][468:461]||
       state_pre_q!==vectors[index][476:469]||state_q!==vectors[index][484:477]||spike!==vectors[index][485]||
       fc!==vectors[index][486]||cc!==vectors[index][487]||pc!==vectors[index][488]||sc!==vectors[index][489]||
       tag_out!==vectors[index][444:435])begin
      errors=errors+1;if(errors<12)$display("FAIL vector=%0d got f=%0d c=%0d l=%0d pre=%0d state=%0d sp=%0d clip=%b%b%b%b",index,forget_q,cellgate_q,lambda,state_pre_q,state_q,spike,fc,cc,pc,sc);
    end
    if(count_clip&&(fc||cc||pc||sc))clipped_vectors=clipped_vectors+1;
  end endtask

  initial begin #10000000;$fatal(1,"FAIL tb_pe_gsn_cell watchdog vector=%0d state=%0d",i,dut.state);end
  initial begin
    if(!$value$plusargs("VECTORS=%s",vector_file)||!$value$plusargs("COUNT=%d",vector_count)||
       !$value$plusargs("LUT0=%s",lut0_file)||!$value$plusargs("LUT1=%s",lut1_file))$fatal(1,"missing vector plusargs");
    $readmemh(vector_file,vectors);$readmemh(lut0_file,lut0);$readmemh(lut1_file,lut1);
    repeat(3)tick;if(start_ready!==0)errors=errors+1;@(negedge clk);rst_n=1;tick;
    load_lut(0);

    // Abort one active transaction with reset, then re-run it in the main loop.
    apply_vector(0);@(negedge clk);start_valid=1;tick;start_valid=0;repeat(5)tick;
    @(negedge clk);rst_n=0;tick;if(result_valid||start_ready)errors=errors+1;
    @(negedge clk);rst_n=1;tick;if(!start_ready)errors=errors+1;

    for(i=0;i<vector_count;i=i+1)begin
      if(vectors[i][0]!==current_layer)load_lut(vectors[i][0]);
      apply_vector(i);result_ready=((i%7)!=3);
      @(negedge clk);start_valid=1;tick;start_valid=0;latency=0;
      while(!result_valid)begin tick;latency=latency+1;end
      if(latency<min_latency)min_latency=latency;if(latency>max_latency)max_latency=latency;
      compare_result(i,1'b1);
      if(!result_ready)begin
        stall_vectors=stall_vectors+1;
        repeat(3)begin tick;compare_result(i,1'b0);end
        @(negedge clk);result_ready=1;tick;
      end else tick;
      if(!start_ready)begin $display("FAIL cell did not return idle vector=%0d",i);errors=errors+1;end
    end
    if(min_latency!=max_latency)begin $display("FAIL variable latency min=%0d max=%0d",min_latency,max_latency);errors=errors+1;end
    if(clipped_vectors==0||stall_vectors==0)errors=errors+1;
    if(errors==0)begin test_passed=1;$display("PE_GSN_CELL_METRICS vectors=%0d latency=%0d stalled_results=%0d clipped_vectors=%0d",vector_count,min_latency,stall_vectors,clipped_vectors);$display("PASS tb_pe_gsn_cell");end
    else $fatal(1,"FAIL tb_pe_gsn_cell errors=%0d",errors);
    $finish;
  end
endmodule
