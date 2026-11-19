
vp = #8000
        macro VAR _vn, _vs
_vn equ vp
vp = vp + _vs
        endm
        org #4000
start:  ld ix,#8400
        ld iy,#B000
        ld bc,300
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
