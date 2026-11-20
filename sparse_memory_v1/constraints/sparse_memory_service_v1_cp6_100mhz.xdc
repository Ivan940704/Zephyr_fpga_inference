# CP6 service-only OOC clock constraint for PYNQ-Z1.
create_clock -period 10.000 -name cp6_sparse_service_clk [get_ports clk]
# Model the insertion point used when this OOC block is integrated beneath a
# 7-series BUFG; otherwise Vivado explicitly marks OOC clock delay/skew as
# inestimable.
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports clk]
