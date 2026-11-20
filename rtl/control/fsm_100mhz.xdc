# PYNQ-Z1 / xc7z020clg400-1 out-of-context timing contract.
create_clock -name clk -period 10.000 [get_ports clk]

# Give OOC timing a concrete clock-root assumption, as recommended by Vivado.
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports clk]

# The FSM connects to synchronous logic in the 100 MHz AXI/control domain.
# Zero external delay exposes all port/register paths against the full period.
set_input_delay -clock clk 0.000 \
    [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_output_delay -clock clk 0.000 \
    [get_ports -filter {DIRECTION == OUT}]
