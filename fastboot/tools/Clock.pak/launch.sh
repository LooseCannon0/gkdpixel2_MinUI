#!/bin/sh
# MinUI Clock tool (upstream skeleton). Fast mode has no RTC and no network
# time; launch-fast.sh saves the time to datetime.txt when this exits.
cd "$(dirname "$0")"
./clock.elf
