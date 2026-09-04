# U400 SDRAM controller simulation

`tb_u400.v` drives `U400_TOP` with an MC68040 bus master model (long word, byte,
word and line transfers using the 40 MHz output delays from the MC68040 user's
manual), an alternate bus master with `_MI` snooping, and two behavioural ISSI
IS42S32160F SDRAMs (`sdram_model.v`, -7 speed grade) that check tRCD, tRP,
tRAS min and max, tRC, tRFC, tMRD, the mode register bank address, auto
precharge rules, and data setup/hold. Read data is checked at the CPU sampling
edge with the 3 ns setup / 3 ns hold the MC68040 needs at 40 MHz, `_TA` with
the 8 ns setup and 2 ns hold.

Besides plain and line transfers the testbench covers: a request during the
power up delay, an off-board cycle directly followed by a RAM cycle, alternate
bus master cycles with `_MI` (snoop inhibited, snoop lookup, snoop hit), back to
back alternate master cycles with a late `_MI`, a snoop hit landing during a
refresh (swept across the refresh window), a warm reset in the middle of a line
write, and random traffic across several refresh periods.

Requires Icarus Verilog (`brew install icarus-verilog`).

    cd sim
    iverilog -g2012 -o tb_u400 tb_u400.v sdram_model.v ../U400_TOP.v \
        ../U400_ADDRESS_DECODE.v ../U400_SDRAM_CONTROLLER.v
    vvp -n tb_u400

Parameters can be overridden on the command line, for example
`-P tb_u400.FAST_READ=0`, `-P tb_u400.CLK40_SKEW=-1.5`, `-P tb_u400.RAMCLK_SKEW=2.0`
or `-P tb_u400.CPU_TCO=25`. Keep `CLK40_SKEW` above -2.4 (the testbench models
skew as a positive delay on top of a 2.5 ns base). `run_sweep.sh` runs a grid of CPU output delays and
clock skews; `FAST_READ=0 ./run_sweep.sh` does the same for the slower, higher
margin read schedule. Results of the last sweeps are in `sweep_fast.txt` and
`sweep_safe.txt`. The grid deliberately includes 4 ns of combined adverse clock
skew (`CLK40_SKEW=-2.0` with `RAMCLK_SKEW=2.0`), which is beyond the 3 ns the
fast read schedule is designed for: those `FAST_READ=1` runs fail on read data
setup and `FAST_READ=0` passes them.
