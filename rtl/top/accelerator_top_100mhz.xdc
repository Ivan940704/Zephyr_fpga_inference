# Out-of-context clock for the Step-4 production integration shell.
# The future Vivado block design owns generated clocks, CDC, and I/O delays.
create_clock -period 10.000 -name clk [get_ports clk]
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports clk]
