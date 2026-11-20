# PYNQ-Z1 / xc7z020clg400-1 out-of-context timing contract.
create_clock -name clk -period 5.000 [get_ports clk]

set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports clk]

set_input_delay -clock clk 0.000 [get_ports {
    rst_n in_valid in_lane_valid[*] value_in[*] multiplier_in[*] shift_in[*]
    tag_in[*] out_ready
}]
set_output_delay -clock clk 0.000 [get_ports {
    in_ready out_valid out_lane_valid[*] value_out[*] tag_out[*]
}]

# rst_n is a synchronous control input and is timed as an ordinary input.
