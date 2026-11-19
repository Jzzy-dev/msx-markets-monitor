#!/bin/sh
# build.sh - MKTW.ROM: the 16 KB "WIFI+Telnet" ROM for the MSX Pico+.
# needs sjasmplus and zx0 (ZX0 v2.2), on the PATH or named in $SJASMPLUS / $ZX0.
#
# The index lists come from PicoAmp; when they change there:
#   python3 src/gen_cat.py <PicoAmp>/engine/pva_markets_cat.c src/mk_cat.inc MARKETS.CAT
set -e
SJ=${SJASMPLUS:-sjasmplus}
ZX0=${ZX0:-zx0}
cd "$(dirname "$0")/src"
$SJ --nologo --msg=war --raw=mktw.bin --sym=mktw.sym mktw.asm    # the program: 4000h.., run from RAM
$ZX0 -f mktw.bin mktw.zx0                                         # packed
$SJ --nologo --msg=war --raw=../MKTW.ROM mktwl.asm               # the loader with it: 16384 bytes
ls -l ../MKTW.ROM
