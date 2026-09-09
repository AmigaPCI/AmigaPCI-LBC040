#!/bin/sh
# Sweep the mainboard acknowledge timing against the U111 cycle state machine.
# For each launch edge (NEGEDGE 0: U409/U712, 1: U110) and acknowledge pulse
# width, run the split cycle bench over a range of mainboard clock-to-out
# values and report the failing ones with the smallest _TA setup the CPU saw.
# Compile errors abort the run.
cd "$(dirname "$0")" || exit 1
OUT=${OUT:-/tmp/tb_u111_sweep}
for ne in 0 1; do
  for pulse in 0 1.5; do
    fails=""; minsu=999
    for tco in 4 5 6 7 8 9 9.25 9.5 9.75 10 10.5 11 11.5 12 12.5 13 14 15 16; do
      iverilog -g2012 -P tb_u111_split.NEGEDGE=$ne -P tb_u111_split.TCO_MB=$tco \
        -P tb_u111_split.PULSE=$pulse -o "$OUT" tb_u111_split.v ../U111_CYCLE_SM.v || exit 1
      out=$(vvp "$OUT" 2>/dev/null)
      e=$(echo "$out" | grep -o '=== [0-9]* errors' | grep -o '[0-9]*')
      su=$(echo "$out" | grep -o 'min _TA setup seen at the CPU: [0-9.]*' | grep -o '[0-9.]*$')
      if [ "$e" != "0" ]; then
        fails="$fails ${tco}(early $(echo "$out" | grep -c 'before the second half'), none $(echo "$out" | grep -c 'no _TA'), data $(echo "$out" | grep -c 'not valid through'))"
      elif [ "$(echo "$su < $minsu" | bc)" = 1 ]; then
        minsu=$su
      fi
    done
    echo "NEGEDGE=$ne PULSE=$pulse: min _TA setup ${minsu}ns; failing TCO_MB:$fails"
  done
done
