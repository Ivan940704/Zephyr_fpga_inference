# CP6 isolated-subsystem validation-harness OOC clock constraint for PYNQ-Z1.
create_clock -period 10.000 -name cp6_sparse_validation_clk [get_ports clk]
# Give the isolated implementation a concrete 7-series global-clock source so
# post-route clock delay/skew is meaningful.
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports clk]
