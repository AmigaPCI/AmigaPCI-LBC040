#!/bin/sh
# Runs the U400 testbench over a range of clock skews and MC68040 output delays.
cd "$(dirname "$0")"
SRC="tb_u400.v sdram_model.v ../U400_TOP.v ../U400_ADDRESS_DECODE.v ../U400_SDRAM_CONTROLLER.v"
FR=${FAST_READ:-1}
fail=0
for tco in 6.5 15 20 25; do
 for sk40 in -2.0 0.7 3.0; do
  for skram in -2.0 0.0 2.0; do
   for fpga in 2.0 5.0; do
    iverilog -g2012 -o tb_run_$FR -P tb_u400.CPU_TCO=$tco -P tb_u400.CLK40_SKEW=$sk40 -P tb_u400.RAMCLK_SKEW=$skram -P tb_u400.FPGA_TCO=$fpga -P tb_u400.RAND_CYCLES=300 -P tb_u400.FAST_READ=$FR $SRC || exit 1
    res=$(vvp -n tb_run_$FR | tail -2 | tr '\n' ' ')
    echo "FAST_READ=$FR TCO=$tco CLK40_SKEW=$sk40 RAMCLK_SKEW=$skram FPGA_TCO=$fpga : $res"
    case "$res" in *PASS*) ;; *) fail=1;; esac
   done
  done
 done
done
[ $fail = 0 ] && echo "SWEEP PASS" || echo "SWEEP FAIL"
