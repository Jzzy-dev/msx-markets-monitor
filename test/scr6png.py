#!/usr/bin/env python3
# scr6png.py - a VRAM dump (128 KB + 64 registers) of SCREEN 6 as a PNG (doubled lines)
import sys
from PIL import Image
d = open(sys.argv[1], 'rb').read()
cols = [(0x24, 0x24, 0x6d), (0xff, 0xff, 0xff), (0x24, 0xdb, 0x24), (0xdb, 0x24, 0x24)]   # navy, white, green, red
im = Image.new('RGB', (512, 424))
px = im.load()
r = d[0x20000:0x20040]
if len(r) == 64 and not r[1] & 0x40:     # R#1 BL = 0: the VDP shows only the border colour
    print('screen blanked (R#1 = %02X)' % r[1])
    im = Image.new('RGB', (512, 424), cols[r[7] & 3]); im.save(sys.argv[2]); sys.exit(0)
for y in range(212):
    for xb in range(128):
        b = d[y * 128 + xb]
        for k in range(4):
            c = cols[(b >> (6 - 2 * k)) & 3]
            px[xb * 4 + k, 2 * y] = c
            px[xb * 4 + k, 2 * y + 1] = c
im.save(sys.argv[2])
