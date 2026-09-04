# U400 timing constraints.
#
# CLK80 clocks the SDRAM and the state machine, CLK40 is the MC68040 bus clock.
# Both come from the same PLL in U111 (CLK40 = CLK80 / 2, rising edges aligned),
# so the tools treat them as related clocks and time the paths between the
# CLK40 registered bus inputs (TS_R, MI_R, TA_R) and the CLK80 state machine as
# half a CLK80 period (12.5ns), which is what the design relies on: those
# registers are only consumed on the CLK80 edges between CLK40 edges.
#
# Two things are not covered by these constraints and must be kept in mind:
# 1. Skew between the CLK40 and CLK80 pins eats into the 12.5ns above and into
#    the 6.25ns margin of the phase detector (CLK40 sampled as data on the
#    falling edge of CLK80). Keep the two clock traces from U111 matched; the
#    design was simulated with up to 3ns of skew.
# 2. The CLK40 pin is used as a data input by the phase detector. That path is
#    an input to register path with no set_input_delay, so it is not timed.
create_clock -period  25.0000 [get_ports {CLK40}]
create_clock -period  12.5000 [get_ports {CLK80}]
