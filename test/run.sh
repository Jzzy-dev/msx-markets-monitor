#!/bin/sh
# run.sh - builds the test programs and runs the number tests.
# needs gcc, python3 with Pillow, sjasmplus, and the Z80 core from
# https://github.com/superzazu/z80 (z80.c, z80.h) in $Z80 (default: ./z80).
set -e
cd "$(dirname "$0")"
Z80=${Z80:-./z80}
gcc -O2 -o z80run z80run.c $Z80/z80.c -I$Z80
gcc -O2 -o z80_mk z80_mk.c $Z80/z80.c -I$Z80
gcc -O2 -o test_rssw test_rssw.c $Z80/z80.c -I$Z80
python3 test_math.py
python3 test_num.py
# the loader: unpacks the program right, on an MSX2 and on an MSX1
RS=$(grep "^rom_start:" ../src/mktw.sym | sed 's/.*0x0000//')
./test_rssw ../MKTW.ROM ../src/mktw.bin $RS
./test_rssw ../MKTW.ROM ../src/mktw.bin $RS msx1
