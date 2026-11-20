# Bring-up top OOC synthesis target.  All logic is in the FCLK0-equivalent
# 100 MHz domain; block-design clock/reset wiring is validated separately.
create_clock -name aclk -period 10.000 [get_ports aclk]
