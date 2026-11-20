# PYNQ-Z1 / xc7z020clg400-1 out-of-context timing contract.
create_clock -name clk -period 5.000 [get_ports clk]

# Give OOC timing a concrete clock-root assumption, as recommended by Vivado.
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports clk]

# The lane connects to synchronous registered PE Array logic.  Zero external
# delay exposes all port-to-register and register-to-port paths against 5 ns.
set_input_delay -clock clk 0.000 [get_ports {
    in_valid value_in[*] multiplier_in[*] shift_in[*] tag_in[*] out_ready
}]
set_output_delay -clock clk 0.000 [get_ports {
    in_ready out_valid value_out[*] tag_out[*]
}]

# rst_n is a synchronous control input and is timed as an ordinary input.

