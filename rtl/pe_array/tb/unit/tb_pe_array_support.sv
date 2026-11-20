`timescale 1ns/1ps
module tb_pe_array_support;
  reg clk=0, rst_n=0; always #2.5 clk=~clk;
  integer errors=0, i, expected_index, seen;
  reg test_passed=0;

  reg lut_iv=0,lut_or=1,cfg_we=0; reg signed [7:0] gate_in=0;
  reg [7:0] cfg_addr=0,cfg_data=0; wire lut_ir,lut_ov; wire [7:0] lambda;
  reg [7:0] lut_expected[0:254];
  reg [8*512-1:0] lut_file;
  pe_sigmoid_lut_255 u_lut(.clk(clk),.rst_n(rst_n),.in_valid(lut_iv),.in_ready(lut_ir),
    .gate_in(gate_in),.out_valid(lut_ov),.out_ready(lut_or),.lambda_out(lambda),
    .cfg_we(cfg_we),.cfg_addr(cfg_addr),.cfg_data(cfg_data));

  reg ser_lv=0,ser_or=1; wire ser_lr,ser_ov,ser_last,ser_busy,ser_done;
  reg [16*32-1:0] ser_values; reg [15:0] ser_mask; reg [8:0] ser_base; reg [7:0] ser_tag;
  wire signed [31:0] ser_value; wire [8:0] ser_index; wire [7:0] ser_tag_o;
  pe_output_serializer u_ser(.clk(clk),.rst_n(rst_n),.load_valid(ser_lv),.load_ready(ser_lr),
    .values_in(ser_values),.lane_valid_in(ser_mask),.base_index_in(ser_base),.tag_in(ser_tag),
    .out_valid(ser_ov),.out_ready(ser_or),.value_out(ser_value),.index_out(ser_index),
    .tag_out(ser_tag_o),.out_last(ser_last),.busy(ser_busy),.done(ser_done));

  reg rq_iv=0,rq_or=1; wire rq_ir,rq_ov,rq_clip,rq_op; reg rq_op_i;
  reg signed [31:0] rq_value,rq_mult,rq_bias; reg [5:0] rq_shift,rq_guard;
  reg [8:0] rq_index; reg [7:0] rq_tag; reg rq_last;
  wire signed [7:0] rq_out; wire [8:0] rq_index_o; wire [7:0] rq_tag_o; wire rq_last_o;
  pe_shared_requant_engine u_rq(.clk(clk),.rst_n(rst_n),.in_valid(rq_iv),.in_ready(rq_ir),
    .op_linear(rq_op_i),.value_in(rq_value),.multiplier_in(rq_mult),.right_shift_in(rq_shift),
    .bias_in(rq_bias),.guard_shift_in(rq_guard),.index_in(rq_index),.tag_in(rq_tag),.last_in(rq_last),
    .out_valid(rq_ov),.out_ready(rq_or),.value_out(rq_out),.index_out(rq_index_o),
    .tag_out(rq_tag_o),.last_out(rq_last_o),.clipped_out(rq_clip),.op_linear_out(rq_op));

  reg spike_iv=0; wire spike_ir,spike_ov,spike_bit; reg signed [7:0] spike_value;
  reg [8:0] spike_index; reg spike_last; wire [8:0] active_index; wire active_last;
  wire writer_ready,buffer_valid,buffer_ready,finalize; wire [8:0] buffer_index;
  wire finalized,overflow; wire [8:0] count; reg [8:0] read_addr=0; wire [8:0] read_index;
  pe_spike_decision u_spike(.in_valid(spike_iv),.in_ready(spike_ir),.value_in(spike_value),
    .index_in(spike_index),.tag_in(8'd0),.last_in(spike_last),.out_valid(spike_ov),
    .out_ready(writer_ready),.index_out(active_index),.tag_out(),.last_out(active_last),.spike_out(spike_bit));
  pe_active_index_writer u_writer(.in_valid(spike_ov),.in_ready(writer_ready),.index_in(active_index),
    .spike_in(spike_bit),.last_in(active_last),.buffer_valid(buffer_valid),.buffer_ready(buffer_ready),
    .buffer_index(buffer_index),.frame_finalize(finalize));
  pe_active_index_buffer u_buffer(.clk(clk),.rst_n(rst_n),.frame_clear(1'b0),
    .write_valid(buffer_valid),.write_ready(buffer_ready),.write_index(buffer_index),.finalize(finalize),
    .finalized(finalized),.overflow(overflow),.count(count),.read_addr(read_addr),.read_index(read_index));

  reg mem_start=0,local_ready=1,local_resp=0; wire mem_busy,mem_done,pe_clear,pe_enable,local_valid;
  wire [2:0] mem_phase; wire [15:0] pending; wire [7:0] mem_tag; wire [1:0] pe_mode;
  pe_membrane_sequencer u_mem(.clk(clk),.rst_n(rst_n),.start(mem_start),.lane_mask_in(16'h55aa),
    .tag_in(8'h42),.busy(mem_busy),.done(mem_done),.phase(mem_phase),.pending_mask(pending),
    .tag_out(mem_tag),.pe_clear(pe_clear),.pe_enable(pe_enable),.pe_mode(pe_mode),
    .local_rq_valid(local_valid),.local_rq_ready(local_ready),.local_rq_response_valid(local_resp));

  reg ctl_start=0,phase_done=0; wire [3:0] ctl_state; wire phase_start,ctl_busy,ctl_done;
  pe_array_controller u_ctl(.clk(clk),.rst_n(rst_n),.start(ctl_start),.phase_done(phase_done),
    .state(ctl_state),.phase_start(phase_start),.busy(ctl_busy),.done(ctl_done));

  task tick; begin @(posedge clk); #1; end endtask
  task check_rq;
    input signed [31:0] value_i; input signed [31:0] bias_i;
    input signed [7:0] expected_i; input expected_clip_i; input op_i;
    begin
      @(negedge clk);rq_iv=1;rq_op_i=op_i;rq_value=value_i;rq_mult=1073741824;rq_shift=30;
      rq_bias=bias_i;rq_guard=8;rq_index=77;rq_tag=8'h5a;rq_last=1;tick;rq_iv=0;
      while(!rq_ov) tick;
      if(rq_out!==expected_i || rq_index_o!==77 || rq_tag_o!==8'h5a ||
         !rq_last_o || rq_op!==op_i || rq_clip!==expected_clip_i) errors=errors+1;
      tick;
    end
  endtask
  initial begin #100000; $fatal(1,"FAIL tb_pe_array_support watchdog state=%0d mem_phase=%0d rq_ov=%0d ser_busy=%0d",ctl_state,mem_phase,rq_ov,ser_busy); end
  initial begin
    if (!$value$plusargs("LUT_FILE=%s",lut_file)) lut_file="pe_sigmoid_lut_fb1.hex";
    $readmemh(lut_file,lut_expected);
    repeat(3) tick; rst_n=1; tick;
    for(i=0;i<255;i=i+1) begin @(negedge clk); cfg_we=1;cfg_addr=i;cfg_data=lut_expected[i]; tick; end
    cfg_we=0;
    for(i=0;i<255;i=i+1) begin
      @(negedge clk); lut_iv=1; gate_in=i-127; tick; lut_iv=0;
      if(!lut_ov || lambda!==lut_expected[i]) begin $display("FAIL lut %0d",i);errors=errors+1;end
    end
    $display("SUPPORT_STAGE lut_done");

    ser_values=0; for(i=0;i<16;i=i+1) ser_values[i*32 +:32]=1000+i;
    ser_mask=16'ha55a;ser_base=9'd64;ser_tag=8'hc3;
    @(negedge clk);ser_lv=1;tick;ser_lv=0;seen=0;i=0;
    while(ser_busy) begin
      @(negedge clk);ser_or=(i%3)!=1;i=i+1;
      if(ser_ov&&ser_or) begin
        expected_index=0; while(expected_index<16 && !ser_mask[expected_index]) expected_index=expected_index+1;
        if(ser_index!==64+expected_index || ser_value!==1000+expected_index || ser_tag_o!==8'hc3) errors=errors+1;
        tick;ser_mask[expected_index]=0;seen=seen+1;
      end
      else tick;
    end
    if(seen!=8) errors=errors+1; ser_or=1;
    $display("SUPPORT_STAGE serializer_done seen=%0d",seen);

    check_rq(100,256,1,0,1);
    check_rq(-100,-256,-1,0,0);
    check_rq(127,32768,127,1,1);
    $display("SUPPORT_STAGE requant_done value=%0d",rq_out);

    for(i=0;i<4;i=i+1) begin
      @(negedge clk);spike_iv=1;spike_index=i;spike_last=(i==3);
      case(i) 0:spike_value=-5;1:spike_value=0;2:spike_value=7;default:spike_value=-1;endcase
      tick;
    end
    spike_iv=0;spike_last=0;tick;
    if(count!==2 || !finalized || overflow) errors=errors+1;
    read_addr=0;#1;if(read_index!==1)errors=errors+1;read_addr=1;#1;if(read_index!==2)errors=errors+1;
    $display("SUPPORT_STAGE index_done count=%0d",count);

    @(negedge clk);mem_start=1;tick;mem_start=0;
    while(!local_valid) tick; tick; local_resp=1;tick;local_resp=0;
    while(!mem_done) tick;
    if(pending!==0 || mem_tag!==8'h42) errors=errors+1;
    $display("SUPPORT_STAGE membrane_done");

    @(negedge clk);ctl_start=1;tick;ctl_start=0;
    for(i=1;i<=11;i=i+1) begin
      if(ctl_state!==i) errors=errors+1;
      @(negedge clk);phase_done=1;tick;phase_done=0;
    end
    tick; if(!ctl_done) errors=errors+1;

    if(errors==0) begin test_passed=1;$display("PE_SUPPORT_METRICS sigmoid=255 serializer_items=8 controller_phases=11");$display("PASS tb_pe_array_support");end
    else $fatal(1,"FAIL tb_pe_array_support errors=%0d",errors);
    $finish;
  end
endmodule
