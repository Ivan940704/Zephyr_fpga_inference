# Sequential-v4 connected PE/memory subsystem out-of-context target.
create_clock -name clk -period 10.000 [get_ports clk]
# Give OOC implementation a concrete global-clock origin so post-route skew is
# estimated instead of left unspecified by Vivado.
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports clk]
