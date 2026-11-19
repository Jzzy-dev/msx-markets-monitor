#!/usr/bin/env python3
# test_math.py - mkmath.asm against Python: random cases for every routine.
import random, struct, subprocess, sys, os
random.seed(7)
HERE = os.path.dirname(os.path.abspath(__file__))
import tempfile; TMP = tempfile.gettempdir()
SJ = os.environ.get('SJASMPLUS', 'sjasmplus')
N = 200
IN, OUT = 0x9000, 0xB000
M32 = 0xFFFFFFFF

def rnd32():
    k = random.choice([1, 2, 3, 4, 4, 4])
    v = random.getrandbits(8 * k)
    return v
cases = []
for i in range(N):
    a, b = rnd32(), rnd32()
    if random.random() < 0.1: b = a
    if random.random() < 0.05: a = 0
    hi = random.getrandbits(32) if random.random() < 0.5 else random.getrandbits(16)
    a64 = (hi << 32) | a
    bd = b or 1
    cases.append((a, b, a64, bd))

inp = bytearray()
for a, b, a64, bd in cases:
    inp += struct.pack('<IIQI', a, b, a64, bd)     # 20 bytes a case
asm = f'''
vp = #8000
        macro VAR _vn, _vs
_vn equ vp
vp = vp + _vs
        endm
        org #4000
start:  ld ix,#{IN:04X}
        ld iy,#{OUT:04X}
        ld b,{N} & 255
        ld c,{N} >> 8
.case:  push bc
        ; mul32: a * b
        push ix
        pop hl
        ld de,m_acc
        ld bc,4
        ldir
        ld de,m_opb
        ld bc,4
        ldir
        call mul32
        ld hl,m_acc
        call put8
        ; div64: a64 / bd
        push ix
        pop hl
        ld bc,8
        add hl,bc
        ld de,m_acc
        ld bc,8
        ldir
        ld de,m_opb
        ld bc,4
        ldir
        call div64
        ld hl,m_acc
        call put8
        ld hl,m_rem
        call put4
        ; add32, sub32 (a +- b), neg32 (a), abs32 (a) + CF
        call ld_t1
        ld hl,t1
        ld de,t2
        call add32
        call put4
        call ld_t1
        ld hl,t1
        ld de,t2
        call sub32
        call put4
        call ld_t1
        ld hl,t1
        call neg32
        call put4
        call ld_t1
        ld hl,t1
        call abs32
        ld a,0
        rla
        push af
        call put4
        pop af
        call put1
        ; cmp32s, cmp32u: flags (CF bit 0, Z bit 1)
        call ld_t1
        ld hl,t1
        ld de,t2
        call cmp32s
        call flags
        call cmp32u
        call flags
        ; tst32 a: flags
        call tst32
        call flags
        ; div10 a: quotient, remainder
        call div10
        push af
        call put4
        pop af
        call put1
        ; mul10 a: result, CF
        call ld_t1
        ld hl,t1
        call mul10
        ld a,0
        rla
        push af
        call put4
        pop af
        call put1
        ld bc,20
        add ix,bc
        pop bc
        dec b
        jp nz,.case
        dec c
        jp p,.case
        ret
ld_t1:  push ix
        pop hl
        ld de,t1
        ld bc,8
        ldir
        ld hl,t1
        ret
flags:  push af
        pop bc
        ld a,c
        and 1
        bit 6,c
        jr z,.n
        or 2
.n:     call put1
        ld hl,t1
        ld de,t2
        ret
put8:   ld b,8
        jr putn
put4:   ld b,4
putn:   ld a,(hl)
        ld (iy+0),a
        inc hl
        inc iy
        djnz putn
        ld hl,t1
        ret
put1:   ld (iy+0),a
        inc iy
        ret
t1:     ds 4
t2:     ds 4
        include "../src/mkmath.asm"
'''
open(os.path.join(HERE,'tm.asm'), 'w').write(asm)
os.chdir('/tmp')
r = subprocess.run([SJ, '--nologo', '--msg=war', '--raw=' + TMP + '/tm.bin', '--sym=' + TMP + '/tm.sym', 'tm.asm'], capture_output=True, text=True,
                   cwd=os.path.join(HERE))
if r.returncode: print(r.stdout, r.stderr); sys.exit(1)
code = open(TMP + '/tm.bin', 'rb').read()
img = bytearray(65536); img[0x4000:0x4000 + len(code)] = code; img[IN:IN + len(inp)] = inp
open(TMP + '/tm_full.bin', 'wb').write(img[0x4000:])
r = subprocess.run([os.path.join(HERE, 'z80run'), TMP + '/tm_full.bin', '4000', '4000', TMP + '/tm.dump'], capture_output=True, text=True)
print(r.stdout.strip())
m = open(TMP + '/tm.dump', 'rb').read()
o = OUT
bad = {}
def s32(v): return v - (1 << 32) if v & 0x80000000 else v
def chk(name, got, want, ctx):
    if got != want:
        bad.setdefault(name, []).append((ctx, got, want))
for a, b, a64, bd in cases:
    mul = struct.unpack_from('<Q', m, o)[0]; o += 8
    q = struct.unpack_from('<Q', m, o)[0]; o += 8
    rm = struct.unpack_from('<I', m, o)[0]; o += 4
    ad, sb, ng, ab = struct.unpack_from('<IIII', m, o); o += 16
    abc = m[o]; o += 1
    fs, fu, ft = m[o], m[o + 1], m[o + 2]; o += 3
    d10 = struct.unpack_from('<I', m, o)[0]; o += 4
    r10 = m[o]; o += 1
    m10 = struct.unpack_from('<I', m, o)[0]; o += 4
    c10 = m[o]; o += 1
    ctx = (hex(a), hex(b), hex(a64), hex(bd))
    chk('mul32', mul, a * b, ctx)
    chk('div64', (q, rm), (a64 // bd, a64 % bd) if a64 // bd < (1 << 64) else None, ctx)
    chk('add32', ad, (a + b) & M32, ctx)
    chk('sub32', sb, (a - b) & M32, ctx)
    chk('neg32', ng, (-a) & M32, ctx)
    chk('abs32', (ab, abc), (abs(s32(a)) & M32, 1 if s32(a) < 0 else 0), ctx)
    sa, sb2 = s32(a), s32(b)
    chk('cmp32s', fs, (1 if sa < sb2 else 0) | (2 if sa == sb2 else 0), ctx)
    chk('cmp32u', fu, (1 if a < b else 0) | (2 if a == b else 0), ctx)
    chk('tst32', ft, (1 if sa < 0 else 0) | (2 if a == 0 else 0), ctx)
    chk('div10', (d10, r10), (a // 10, a % 10), ctx)
    want = (a * 10, 0) if a * 10 <= M32 else (a, 1)
    chk('mul10', (m10, c10), want, ctx)
for k in ['mul32', 'div64', 'add32', 'sub32', 'neg32', 'abs32', 'cmp32s', 'cmp32u', 'tst32', 'div10', 'mul10']:
    e = bad.get(k, [])
    print('%-5s %-7s %d/%d' % ('OK' if not e else 'FAIL', k, N - len(e), N), '' if not e else e[:2])
sys.exit(1 if bad else 0)
