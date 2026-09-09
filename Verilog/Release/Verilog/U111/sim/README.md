# U111 bus sizing testbench

`tb_u111_split.v` drives `U111_CYCLE_SM.v` through long word reads from a
16 bit off-board port, the cycles U111 splits into two word reads, and
checks what the CPU would make of them.

The mainboard is modelled as a one clock `_TACK` pulse launched `TCO_MB`
after a bus clock edge (rising for U409/U712, falling for U110 when
`NEGEDGE=1`) and delayed `TRACE` on the way to U111, driven high one clock
later and released after another, the way `U110_CYCLE_TERMINATION.v` does
it. `PULSE` widens the pulse for a rise that is slower than the fall.

The CPU model starts its cycles back to back, samples `_TA` from the end of
C2 on and only accepts it when it is low from 8ns before to 2ns after the
edge (MC68040 specs 22a and 23 at 40MHz). U111's outputs reach the CPU
after `TA_PATH` (pad to pad) and `U111_TCO` (register to pad). Each read
must be acknowledged only after the mainboard did (both halves on a 16 bit
port), with the assembled long word stable through the CPU's data setup
and hold window.

Three sequences run: long word reads from a 16 bit port back to back; the
same with an on-board (U400 style) read in front of each, since the
on-board acknowledge travels over `_TACK` as well; and long word reads from
a 32 bit port (chip RAM) each followed by an on-board read, which checks
the hand-over of the `_TA` line. That line has no pull-up on the Rev 6.0
card, so the bench models it as a net that keeps its last level (a keeper
of weak strength; `TA_PULLUP=1` adds a pull-up). `LBEN_DELAY` is the time
from the CPU's clock edge to `LBENn` at U111 for the next cycle's address.

    iverilog -g2012 -o tb tb_u111_split.v ../U111_CYCLE_SM.v && vvp tb
    ./run_sweep.sh

`U111_CYCLE_SM.v` has its registers declared ahead of their first use so
that Icarus Verilog accepts it; Synplify did not mind the original order.

## What the sweep shows

Rising edge acknowledges (U409, U712) reach the CPU `TCO_MB + TRACE +
TA_PATH` after the edge. Through the plain pass through they have to make
the CPU's 8ns setup at the next edge, so the sum must stay under 17ns; one
nanosecond more and the CPU misses a pulse that is gone again by the edge
after, which is a hang. The iCE40 HX4K datasheet gives 5.4ns for the
mainboard's register to pad and 7.3ns for one pin-LUT-pin path in U111
before any trace or the clock offset between the two boards, so the
budget is spent at the datasheet corner. Falling edge acknowledges (U110)
arrive half a clock later and are fine at the CPU, but they reach U111
about 2ns before its own sampling edge, and U111 sampling a one clock
pulse on one edge only could miss it altogether and leave its cycle state
machine waiting with the data path enabled.

`U111_CYCLE_SM.v` therefore does three things since 8 September 2026:

- `_TACK` is sampled on both clock edges and the first sight of a pulse is
  turned into one event, so no alignment of the pulse can be missed or
  counted twice.
- After an acknowledge that terminates the CPU's own off-board cycle,
  `_TA` is held low for one more clock, so a pulse the CPU could not use at
  one edge is still there at the next. This does not apply to the first
  half of a split cycle, to on-board acknowledges seen on `_TACK`, or while
  an alternate master owns the bus; an earlier version without those
  conditions terminated split cycles early when U110's acknowledge landed
  on U111's sampling edge.
- `_TA` is driven high for one clock after U111 stops passing `_TACK`
  through, instead of being released while it may still be low.

With that, the sweep passes for every rising edge `TCO_MB` from 3 to 14ns,
for falling edge pulses from 3ns on, and for pulses 1.5ns wider than a
clock, with the CPU's setup never below 9ns. A late recognition means the
mainboard has to keep read data valid one bus clock longer than its
acknowledge: chip RAM (the SDRAM's output is held by CKE until the slot
ends), chipset registers (data invalid at the earliest on the next C1
rise), ROM (`ROM_ENn` stays two clocks past the acknowledge), ATA (the
buffers follow the address decode) and the CIAs (chip select stays until
the next E clock phase) all do.
