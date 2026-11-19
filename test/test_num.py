#!/usr/bin/env python3
# test_num.py - mknum.asm against a Python port of pva_markets.c's number code
import random, struct, subprocess, sys, os
random.seed(11)
HERE = os.path.dirname(os.path.abspath(__file__))
import tempfile; TMP = tempfile.gettempdir()
SJ = os.environ.get('SJASMPLUS', 'sjasmplus')
INT64_MAX = (1 << 63) - 1

# ---- the C engine, ported
def parse_num(s):
    i = 0; neg = False
    if s[i:i+1] == '-': neg = True; i += 1
    elif s[i:i+1] == '+': i += 1
    if not (s[i:i+1].isdigit() or s[i:i+1] == '.'): return None
    m = 0; sc = 0; digits = 0
    while i < len(s) and s[i].isdigit():
        if digits < 12:                      # (17 in the C engine; 12 here: inputs have fewer)
            m = m * 10 + int(s[i])
            if m: digits += 1
        else: sc += 1
        i += 1
    if s[i:i+1] == '.':
        i += 1
        while i < len(s) and s[i].isdigit():
            if digits < 12:
                m = m * 10 + int(s[i]); sc -= 1
                if m: digits += 1
            i += 1
    if s[i:i+1] in ('e', 'E'):
        j = i + 1; sg = 1
        if s[j:j+1] == '-': sg = -1; j += 1
        elif s[j:j+1] == '+': j += 1
        k = j
        while k < len(s) and s[k].isdigit(): k += 1
        e = int(s[j:k] or '0') * sg
        e = max(-30, min(30, e))
        sc += e
    sc += 6
    while sc > 0 and m < INT64_MAX // 10: m *= 10; sc -= 1
    while sc < 0:
        r = m % 10; m //= 10
        if sc == -1 and r >= 5: m += 1
        sc += 1
    return -m if neg else m

def scale_for(micro):
    sc = 6; micro = abs(micro)
    while sc and micro >= 1000000000: micro //= 10; sc -= 1
    return sc

def to_scale(micro, sc):
    d = 10 ** (6 - sc)
    return (micro + d // 2) // d if micro >= 0 else -((-micro + d // 2) // d)

def fmt_num(v, sc, dec, sign):
    if dec > sc: dec = sc
    neg = v < 0; a = abs(v)
    div = 10 ** (sc - dec)
    a = (a + div // 2) // div
    whole, frac = a // 10 ** dec, a % 10 ** dec
    if not a: neg = False
    sg = '-' if neg else ('+' if sign and a else '')
    whole = min(whole, 999999999)
    return '%s%d.%0*d' % (sg, whole, dec, frac) if dec else '%s%d' % (sg, whole)

def pct100(price, prev):
    if prev <= 0: return 0
    d = (price - prev) * 10000
    r = (d + prev // 2) // prev if d >= 0 else -((-d + prev // 2) // prev)
    return max(-999999, min(999999, r))

def fmt_pct(p):
    a = abs(p)
    return '%s%d.%02d%%' % ('-' if p < 0 else '+' if p > 0 else '', a // 100, a % 100)

# ---- cases
def rnum():
    k = random.random()
    if k < 0.08: return random.choice(['null', '0', '0.0', '-0', '.5', '1e3', '2.5E-4', '-4.0E-4', '1141.03', '0.000123456', '123456789012', '9.99999999e8'])
    whole = str(random.randint(0, 10 ** random.randint(0, 9)))
    frac = ''.join(random.choice('0123456789') for _ in range(random.randint(0, 8)))
    s = whole + ('.' + frac if frac or random.random() < 0.1 else '')
    if random.random() < 0.1: s = '-' + s
    if random.random() < 0.08: s += random.choice(['e', 'E']) + random.choice(['', '-', '+']) + str(random.randint(0, 9))
    return s
N = 300
cases = []
import os as _o
for _ in range(N if not _o.environ.get('ONLY') else 0):
    s = rnum()
    dec = random.randint(0, 6); sign = random.randint(0, 1)
    p1 = random.randint(1, 10 ** random.randint(1, 9)); p2 = random.randint(-5, 10 ** random.randint(1, 9))
    pv = random.choice([p1, p2, p1, 0])
    pr = max(1, p1 + random.randint(-p1 // 3 - 1, p1 // 3 + 1)) if random.random() < 0.8 else random.randint(1, 10 ** 9)
    pv = min(pv, 999999999); pr = min(pr, 999999999)
    cases.append((s, dec, sign, pr, pv))

if _o.environ.get('ONLY'):
    for t in _o.environ['ONLY'].split(';'):
        a=t.split(',')
        cases.append((a[0], int(a[1]), int(a[2]), int(a[3]), int(a[4])))
    N=len(cases)
IN, OUT = 0x8400, 0xB000
inp = bytearray()
for s, dec, sign, pr, pv in cases:
    b = s.encode() + b'\0'
    inp += b.ljust(24, b'\0') + bytes([dec, sign]) + struct.pack('<ii', pr, pv)     # 34 bytes
asm = f'''
vp = #8000
        macro VAR _vn, _vs
_vn equ vp
vp = vp + _vs
        endm
        org #4000
start:  ld ix,#{IN:04X}
        ld iy,#{OUT:04X}
        ld bc,{N}
.case:  push bc
        push ix
        pop hl                  ; pnum: the value and its scale (FF: not a number)
        call pnum
        ld a,#FF
        jr c,.nn
        ld a,(n_sc)
.nn:    ld (iy+4),a
        ld hl,n_val
        call put4
        inc iy
        ; fmt_num of the parsed one (when it is one) with the case's decimals and sign
        ld (iy+0),0
        ld a,(iy-1)
        cp #FF
        jr z,.nf
        ld c,a
        ld b,(ix+24)
        ld a,(ix+25)
        push iy
        pop de
        push ix
        ld ix,n_val
        call fmt_num
        pop ix
.nf:    ld bc,20
        add iy,bc
        ; pct100 of the pair, then fmt_pct
        push ix
        pop hl
        ld bc,26
        add hl,bc
        ld d,h
        ld e,l
        inc de
        inc de
        inc de
        inc de
        call pct100
        ld hl,n_pct
        call put4
        push iy
        pop de
        call fmt_pct
        ld bc,12
        add iy,bc
        ld bc,34
        add ix,bc
        pop bc
        dec bc
        ld a,b
        or c
        jp nz,.case
        ret
put4:   ld b,4
.l:     ld a,(hl)
        ld (iy+0),a
        inc hl
        inc iy
        djnz .l
        ret
        include "../src/rss_sys.asm"
        include "../src/mkmath.asm"
        include "../src/mknum.asm"
'''
open(os.path.join(HERE, 'tn.asm'), 'w').write(asm)
r = subprocess.run([SJ, '--nologo', '--msg=war', '--raw=' + TMP + '/tn.bin', 'tn.asm'], capture_output=True, text=True, cwd=HERE)
if r.returncode: print(r.stdout[-3000:], r.stderr[-2000:]); sys.exit(1)
code = open(TMP + '/tn.bin', 'rb').read()
img = bytearray(0xC000); img[0:len(code)] = code; img[IN - 0x4000:IN - 0x4000 + len(inp)] = inp
open(TMP + '/tn_full.bin', 'wb').write(img)
r = subprocess.run([os.path.join(HERE, 'z80run'), TMP + '/tn_full.bin', '4000', '4000', TMP + '/tn.dump'], capture_output=True, text=True)
print(r.stdout.strip(), '(code %d bytes)' % len(code))
m = open(TMP + '/tn.dump', 'rb').read()
o = OUT
bad = {}
def cstr(off):
    e = m.index(b'\0', off); return m[off:e].decode('latin-1')
for s, dec, sign, pr, pv in cases:
    val = struct.unpack_from('<i', m, o)[0]; sc = m[o + 4]; txt = cstr(o + 5); o += 25
    pc = struct.unpack_from('<i', m, o)[0]; ptxt = cstr(o + 4); o += 16
    micro = parse_num(s)
    if micro is not None and abs(micro) >= (1 << 31) * 10**6: continue   # (over 2^31 even unscaled: no price is near)
    if micro is None: want = (None,)
    else:
        wsc = scale_for(micro); wv = to_scale(micro, wsc); wv = (wv + (1 << 31)) % (1 << 32) - (1 << 31)
        want = (wv, wsc)
    got = (None,) if sc == 0xFF else (val, sc)
    if got != want: bad.setdefault('pnum', []).append((s, got, want))
    elif micro is not None:
        w = fmt_num(want[0], want[1], dec, sign)
        if txt != w: bad.setdefault('fmt_num', []).append((s, want, dec, sign, txt, w))
    if pc != pct100(pr, pv): bad.setdefault('pct100', []).append((pr, pv, pc, pct100(pr, pv)))
    elif ptxt != fmt_pct(pc): bad.setdefault('fmt_pct', []).append((pc, ptxt, fmt_pct(pc)))
for k in ['pnum', 'fmt_num', 'pct100', 'fmt_pct']:
    e = bad.get(k, [])
    print('%-5s %-8s %d bad of %d' % ('OK' if not e else 'FAIL', k, len(e), N), e[:3] if e else '')
sys.exit(1 if bad else 0)
