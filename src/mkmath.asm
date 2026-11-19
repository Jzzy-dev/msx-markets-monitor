;==============================================================================
; mkmath.asm - 32-bit numbers (and 64-bit products and quotients) for the
; market engine. Numbers are in memory, low byte first; the routines take
; pointers: HL = the one changed (or compared), DE = the other. HL, DE and
; BC are kept unless said otherwise.
;
;   cpy32  (HL) = (DE)              add32  (HL) += (DE)       sub32  (HL) -= (DE)
;   neg32  (HL) = -(HL)             abs32  (HL) = |(HL)|, CF: it was negative
;   cmp32s signed (HL) - (DE): CF (HL) < (DE), Z equal
;   cmp32u the same, unsigned
;   zero32 (HL) = 0                 set32  (HL) = A (0..255)
;   tst32  Z: (HL) = 0, CF: negative (bit 31)
;   mul32  m_acc = m_acc(low 32) * m_opb      (a 64-bit result)
;   div64  m_acc = m_acc / m_opb, m_rem = the remainder (unsigned, 64 / 32)
;   div10  (HL) = (HL) / 10 (unsigned), A = the remainder
;   mul10  (HL) = (HL) * 10, CF: more than 32 bits (then (HL) is not changed)
;   p10    A = 0..9 -> HL = the address of 10^A (32-bit)
;==============================================================================

        VAR m_acc, 8
        VAR m_opb, 4
        VAR m_rem, 4
        VAR m_mc, 8             ; (mul32: the multiplicand, shifted)
        VAR m_mp, 4             ; (mul32: the multiplier, shifted)

cpy32:  push hl
        push de
        push bc
        ex de,hl
        ld bc,4
        ldir
        pop bc
        pop de
        pop hl
        ret

add32:  push hl
        push de
        push bc
        ld b,4
        or a
.l:     ld a,(de)
        adc a,(hl)
        ld (hl),a
        inc hl
        inc de
        djnz .l
        pop bc
        pop de
        pop hl
        ret

sub32:  push hl
        push de
        push bc
        ld b,4
        or a
.l:     ld a,(de)
        ld c,a
        ld a,(hl)
        sbc a,c
        ld (hl),a
        inc hl
        inc de
        djnz .l
        pop bc
        pop de
        pop hl
        ret

neg32:  push hl
        push bc
        ld b,4
        or a
.l:     ld a,0
        sbc a,(hl)
        ld (hl),a
        inc hl
        djnz .l
        pop bc
        pop hl
        ret

abs32:  push hl
        inc hl
        inc hl
        inc hl
        ld a,(hl)
        pop hl
        rla
        ret nc
        call neg32
        scf
        ret

cmp32s: push hl
        push de
        push bc
        inc hl
        inc hl
        inc hl
        inc de
        inc de
        inc de
        ld a,(de)               ; the top bytes with their signs flipped
        xor #80
        ld c,a
        ld a,(hl)
        xor #80
        jr cmp32_t
cmp32u: push hl
        push de
        push bc
        inc hl
        inc hl
        inc hl
        inc de
        inc de
        inc de
        ld a,(de)
        ld c,a
        ld a,(hl)
cmp32_t:
        ld b,3
.l:     cp c
        jr nz,.e
        dec hl
        dec de
        ld a,(de)
        ld c,a
        ld a,(hl)
        djnz .l
        cp c
.e:     pop bc
        pop de
        pop hl
        ret

zero32: xor a
set32:  push hl
        ld (hl),a
        inc hl
        xor a
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld (hl),a
        pop hl
        ret

tst32:  push hl
        push bc
        ld a,(hl)
        inc hl
        or (hl)
        inc hl
        or (hl)
        inc hl
        ld b,(hl)
        or b                    ; Z: all zero (and NC)
        ld a,b
        pop bc
        pop hl
        ret z
        rla                     ; CF = the sign (rla leaves Z as it is: NZ)
        ret

; m_acc = m_acc(low 32) * m_opb: for each multiplier bit from bit 0 on, the
; multiplicand (shifted one more each time) is added when the bit is 1
mul32:  push hl
        push de
        push bc
        ld hl,m_acc
        ld de,m_mc
        ld bc,4
        ldir
        xor a
        ld (m_mc+4),a
        ld (m_mc+5),a
        ld (m_mc+6),a
        ld (m_mc+7),a
        ld hl,m_opb
        ld de,m_mp
        ld bc,4
        ldir
        ld hl,m_acc
        ld b,8
.z:     ld (hl),0
        inc hl
        djnz .z
        ld c,32
.bit:   ld hl,m_mp+3            ; the multiplier >> 1, its bit 0 into CF
        ld b,4
        or a
.r:     rr (hl)
        dec hl
        djnz .r
        jr nc,.sh
        ld hl,m_acc
        ld de,m_mc
        ld b,8
        or a
.ad:    ld a,(de)
        adc a,(hl)
        ld (hl),a
        inc hl
        inc de
        djnz .ad
.sh:    ld hl,m_mc              ; the multiplicand << 1
        ld b,8
        or a
.s:     rl (hl)
        inc hl
        djnz .s
        dec c
        ld hl,m_mp              ; (no more multiplier bits: done)
        ld a,(hl)
        inc hl
        or (hl)
        inc hl
        or (hl)
        inc hl
        or (hl)
        jr z,.done
        jr .bit
.done:  pop bc
        pop de
        pop hl
        ret

; m_acc / m_opb -> m_acc, m_rem. When the top 32 bits are below the divisor
; (the quotient fits 32 bits) only 32 steps.
div64:  push hl
        push de
        push bc
        ld hl,m_rem
        call zero32
        ld hl,m_acc+4
        ld de,m_opb
        call cmp32u             ; high < divisor?
        ld c,64
        jp nc,.go
        ; 32 steps in registers: the remainder DE:HL (from the top 32 bits),
        ; the dividend / quotient DE':HL' (the low 32 bits), the divisor m_opb
        ld hl,(m_acc+4)
        ld de,(m_acc+6)
        exx
        ld hl,(m_acc)
        ld de,(m_acc+2)
        exx
        ld b,32
.r:     exx                     ; quotient <<= 1, its top bit into the remainder
        add hl,hl
        ex de,hl
        adc hl,hl
        ex de,hl
        exx
        adc hl,hl
        ex de,hl
        adc hl,hl
        ex de,hl
        jr c,.rs                ; (a 33rd bit: not less)
        push hl
        push de
        ld a,(m_opb)            ; remainder - divisor
        ld c,a
        ld a,l
        sub c
        ld l,a
        ld a,(m_opb+1)
        ld c,a
        ld a,h
        sbc a,c
        ld h,a
        ld a,(m_opb+2)
        ld c,a
        ld a,e
        sbc a,c
        ld e,a
        ld a,(m_opb+3)
        ld c,a
        ld a,d
        sbc a,c
        ld d,a
        jr c,.rb                ; it was less: as it was
        pop af
        pop af
        jr .r1
.rb:    pop de
        pop hl
        jr .rn
.rs:    ld a,(m_opb)            ; (the 33rd bit: subtract, the borrow is that bit)
        ld c,a
        ld a,l
        sub c
        ld l,a
        ld a,(m_opb+1)
        ld c,a
        ld a,h
        sbc a,c
        ld h,a
        ld a,(m_opb+2)
        ld c,a
        ld a,e
        sbc a,c
        ld e,a
        ld a,(m_opb+3)
        ld c,a
        ld a,d
        sbc a,c
        ld d,a
.r1:    exx
        inc l                   ; this quotient bit: 1
        exx
.rn:    djnz .r
        ld (m_rem),hl
        ld (m_rem+2),de
        exx
        ld (m_acc),hl
        ld (m_acc+2),de
        exx
        ld hl,0
        ld (m_acc+4),hl
        ld (m_acc+6),hl
        pop bc
        pop de
        pop hl
        ret
.go64:  ld c,64
.go:    ; a step: (m_rem:m_acc) <<= 1; if m_rem >= m_opb: m_rem -= m_opb, bit 0 = 1
.step:  ld hl,m_acc
        ld b,8
        or a
.s1:    rl (hl)
        inc hl
        djnz .s1
        ld hl,m_rem
        ld b,4
.s2:    rl (hl)
        inc hl
        djnz .s2
        jr c,.sub               ; (a 33rd bit: certainly not less)
        ld hl,m_rem
        ld de,m_opb
        call cmp32u
        jr c,.nos
.sub:   ld hl,m_rem
        ld de,m_opb
        call sub32
        ld hl,m_acc
        set 0,(hl)
.nos:   dec c
        jr nz,.step
        pop bc
        pop de
        pop hl
        ret

; (HL) /= 10, A = the remainder
div10:  push hl
        push bc
        inc hl
        inc hl
        inc hl
        ld b,4
        xor a
.l:     push bc
        ld c,(hl)
        ld b,8
.b:     sla c
        rla
        cp 10
        jr c,.n
        sub 10
        inc c
.n:     djnz .b
        ld (hl),c
        dec hl
        pop bc
        djnz .l
        pop bc
        pop hl
        ret

; (HL) *= 10; CF: more than 32 bits (then (HL) stays). x*8 + x*2 by shifts
mul10:  push hl
        push de
        push bc
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld c,(hl)
        inc hl
        ld b,(hl)
        push hl                 ; (byte 3's place)
        sla e
        rl d
        rl c
        rl b                    ; *2
        jr c,.of
        push bc
        push de                 ; (*2 kept)
        sla e
        rl d
        rl c
        rl b
        jr c,.of2
        sla e
        rl d
        rl c
        rl b                    ; *8
        jr c,.of2
        pop hl                  ; + *2: the low half,
        add hl,de
        ex de,hl
        pop hl                  ; the high half
        adc hl,bc
        jr c,.of0
        ld b,h
        ld c,l
        pop hl
        ld (hl),b
        dec hl
        ld (hl),c
        dec hl
        ld (hl),d
        dec hl
        ld (hl),e
        or a
        jr .e
.of2:   pop de
        pop bc
.of:    pop hl
        scf
        jr .e
.of0:   pop hl
        scf
.e:     pop bc
        pop de
        pop hl
        ret

; A = 0..9: HL = the address of 10^A
p10:    push de
        add a,a
        add a,a
        ld e,a
        ld d,0
        ld hl,p10t
        add hl,de
        pop de
        ret
p10t:   dd 1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000, 1000000000
