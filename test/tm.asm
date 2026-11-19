
vp = #8000
        macro VAR _vn, _vs
_vn equ vp
vp = vp + _vs
        endm
        org #4000
start:  ld ix,#9000
        ld iy,#B000
        ld b,200 & 255
        ld c,200 >> 8
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
