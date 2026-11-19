;==============================================================================
; mknum.asm - the market engine's numbers, as PicoAmp's engine (pva_markets.c)
; has them: a price in units of 10^-sc (sc 0..6, as many decimals as 9 digits
; leave), read from the JSON text and written with a row's decimals.
;
;   pnum     HL = text -> n_val (int32, units of 10^-n_sc), n_sc; CF: not a number
;            (parse_num, scale_for and to_scale of the C engine)
;   rescale  n_val from n_sc to A decimals (fewer), rounded; n_sc = A
;   fmt_num  IX = int32, C = its scale, B = decimals, A = 1: a '+' before a
;            positive one -> text at DE (0-terminated, DE on the 0)
;   pct100   HL = price, DE = previous close (int32, the same scale) -> n_pct
;            (the change in hundredths of a percent, -999999..999999)
;   fmt_pct  n_pct -> text at DE ("+0.08%", DE on the 0)
;   fmt_u32  (HL) unsigned in decimal -> DE (DE on the 0)
;==============================================================================

        VAR n_val, 4
        VAR n_sc, 1
        VAR n_neg, 1
        VAR n_pct, 4
        VAR n_dig, 1
        VAR n_esc, 2            ; the exponent of ten (signed)
        VAR n_t, 4
        VAR n_u, 4
        VAR n_buf, 12

; m_acc (64) *= 10, + A; CF: the top byte would not be 0 any more
mac10:  push hl
        push de
        push bc
        ld c,a
        ld hl,m_acc
        ld de,m_mc              ; m_mc = m_acc * 2, m_acc = m_acc * 8 + m_mc
        ld b,8
        or a
.c:     ld a,(hl)
        rla
        ld (de),a
        inc hl
        inc de
        djnz .c
        ld hl,m_acc
        ld b,3
.x8:    push bc
        ld b,8
        or a
        push hl
.s:     rl (hl)
        inc hl
        djnz .s
        pop hl
        pop bc
        djnz .x8
        ld de,m_mc
        ld b,8
        ld a,(de)               ; and the digit
        add a,c
        ld (de),a
        ld b,7
        inc de
.p:     ld a,(de)
        adc a,0
        ld (de),a
        inc de
        djnz .p
        ld hl,m_acc
        ld de,m_mc
        ld b,8
        or a
.a:     ld a,(de)
        adc a,(hl)
        ld (hl),a
        inc hl
        inc de
        djnz .a
        ld a,(m_acc+7)
        cp #0C                  ; (below 2^59.6: a *10 still fits 63 bits)
        ccf
        pop bc
        pop de
        pop hl
        ret

; m_acc (64) /= 10, A = the remainder
mdiv10: push hl
        push bc
        ld hl,m_acc+7
        ld b,8
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

; Z: m_acc (64) is 0
mzero:  push hl
        push bc
        ld hl,m_acc
        ld b,8
        xor a
.l:     or (hl)
        inc hl
        djnz .l
        pop bc
        pop hl
        ret

; CF: m_acc (64) < 10^9
mlt1e9: ld a,(m_acc+4)
        ld hl,m_acc+5
        or (hl)
        inc hl
        or (hl)
        inc hl
        or (hl)
        ret nz                  ; (NC)
        ld hl,m_acc
        ld de,c1e9
        jp cmp32u
c1e9:   dd 1000000000

;------------------------------------------------------------------------------
; pnum: "1141.03", "-4.0E-4", "null" -> n_val, n_sc (CF: not a number)
pnum:   xor a
        ld (n_neg),a
        ld (n_dig),a
        ld (n_esc),a
        ld (n_esc+1),a
        ld b,8
        push hl
        ld hl,m_acc
.z:     ld (hl),a
        inc hl
        djnz .z
        pop hl
        ld a,(hl)
        cp '-'
        jr nz,.np
        ld a,1
        ld (n_neg),a
        inc hl
        jr .d0
.np:    cp '+'
        jr nz,.d0
        inc hl
.d0:    ld a,(hl)
        cp '.'
        jr z,.ok
        sub '0'
        cp 10
        ccf
        ret c                   ; not a number
.ok:
.int:   ld a,(hl)               ; the whole part
        sub '0'
        cp 10
        jr nc,.ie
        inc hl
        call .digit
        jr c,.ix                ; (no more room: a power of ten)
        jr .int
.ix:    call .escinc
        jr .int
.ie:    ld a,(hl)
        cp '.'
        jr nz,.ex
        inc hl
.fr:    ld a,(hl)
        sub '0'
        cp 10
        jr nc,.ex
        inc hl
        push af
        ld a,(n_dig)
        cp 12
        jr nc,.fskip
        pop af
        call .digit
        call .escdec
        jr .fr
.fskip: pop af
        jr .fr
.ex:    ld a,(hl)               ; e+12 / E-4
        or #20
        cp 'e'
        jr nz,.sc
        inc hl
        ld a,(hl)
        cp '-'
        push af
        jr z,.em
        cp '+'
        jr nz,.en
.em:    inc hl
.en:    call num                ; DE = the exponent
        ld a,d                  ; (at most 30)
        or a
        jr nz,.eb
        ld a,e
        cp 31
        jr c,.ea
.eb:    ld de,30
.ea:    pop af
        jr nz,.ep
        ld hl,0
        or a
        sbc hl,de
        ex de,hl
.ep:    ld hl,(n_esc)
        add hl,de
        ld (n_esc),hl
.sc:    ; micro: the exponent + 6
        ld hl,(n_esc)
        ld de,6
        add hl,de
        ld (n_esc),hl
.up:    ld hl,(n_esc)           ; while sc > 0: *10
        ld a,h
        or a
        jp m,.dn
        or l
        jr z,.done
        xor a
        call mac10
        jr c,.done
        call .escdec
        jr .up
.dn:    ld hl,(n_esc)           ; while sc < 0: /10, the last one rounded
        ld a,h
        or l
        jr z,.done
        call mdiv10
        push af
        call .escinc
        ld hl,(n_esc)
        ld a,h
        or l
        jr nz,.nr
        pop af
        cp 5
        jr c,.done
        ld hl,m_acc             ; m++
        ld b,8
.inc:   inc (hl)
        jr nz,.done
        inc hl
        djnz .inc
        jr .done
.nr:    pop af
        jr .dn
.done:  ; scale_for: the most decimals (up to 6) with which it has 9 digits or less
        ld hl,m_acc             ; (the micro value kept in m_tmp for to_scale)
        ld de,n_buf
        ld bc,8
        ldir
        ld a,6
        ld (n_sc),a
.sf:    call mlt1e9
        jr c,.sfe
        ld a,(n_sc)
        or a
        jr z,.sfe
        dec a
        ld (n_sc),a
        call mdiv10
        jr .sf
.sfe:   ld hl,n_buf             ; to_scale: (micro + d/2) / d, d = 10^(6-sc)
        ld de,m_acc
        ld bc,8
        ldir
        ld a,(n_sc)
        neg
        add a,6
        call p10
        ex de,hl
        ld hl,m_opb
        call cpy32
        ld hl,n_u               ; + d/2
        ld de,m_opb
        call cpy32
        ld hl,n_u+3
        or a
        ld b,4
.h:     rr (hl)
        dec hl
        djnz .h
        call acc_add
        call div64
        ld hl,n_val
        ld de,m_acc
        call cpy32
        ld a,(n_neg)
        or a
        ret z                   ; (NC)
        ld hl,n_val
        call neg32
        or a
        ret
; a digit (A) into m_acc while there is room (12 digits): CF when not taken
.digit: push hl
        ld c,a
        ld a,(n_dig)
        cp 12
        jr nc,.dfull
        ld a,c
        call mac10
        call mzero
        jr z,.dz
        ld hl,n_dig
        inc (hl)
.dz:    pop hl
        or a
        ret
.dfull: pop hl
        scf
        ret
.escinc:
        push hl
        ld hl,(n_esc)
        inc hl
        ld (n_esc),hl
        pop hl
        ret
.escdec:
        push hl
        ld hl,(n_esc)
        dec hl
        ld (n_esc),hl
        pop hl
        ret

;------------------------------------------------------------------------------
; rescale: n_val from n_sc decimals to A (A <= n_sc), rounded (away from 0)
rescale:
        ld b,a
        ld a,(n_sc)
        sub b
        ret z
        ret c
        ld c,a
        ld a,b
        ld (n_sc),a
        ld a,c
        ; fall through
; rdiv: n_val = n_val / 10^A, rounded half away from zero
rdiv:   call p10
        ex de,hl                ; DE = 10^A
        ld hl,n_t
        call cpy32
        ld hl,n_val
        call abs32
        push af
        ld hl,m_acc
        ld de,n_val
        call cpy32
        xor a
        ld (m_acc+4),a
        ld (m_acc+5),a
        ld (m_acc+6),a
        ld (m_acc+7),a
        ld hl,m_opb
        ld de,n_t
        call cpy32
        ld hl,n_t+3             ; d/2
        ld b,4
        or a
.h:     rr (hl)
        dec hl
        djnz .h
        ld hl,m_acc
        ld de,n_t
        call add32
        call div64
        ld hl,n_val
        ld de,m_acc
        call cpy32
        pop af
        ret nc
        ld hl,n_val
        jp neg32

;------------------------------------------------------------------------------
; fmt_u32: (HL) in decimal to DE, 0-terminated (DE on the 0)
        VAR fu_de, 2
fmt_u32:
        push hl
        push bc
        ld (fu_de),de
        ld de,n_u
        ex de,hl
        call cpy32
        ld b,0
.d:     ld hl,n_u
        call div10
        add a,'0'
        push af
        inc b
        call tst32
        jr nz,.d
        ld de,(fu_de)
.o:     pop af
        ld (de),a
        inc de
        djnz .o
        xor a
        ld (de),a
        pop bc
        pop hl
        ret

; fmt_num: IX = the value, C = its scale, B = decimals, A = 1: a '+' sign
        VAR fn_sign, 1
        VAR fn_dec, 1
        VAR fn_neg, 1
fmt_num:
        ld (fn_sign),a
        ld a,b                  ; dec > sc: dec = sc
        cp c
        jr c,.d
        ld a,c
.d:     ld (fn_dec),a
        push de
        push ix
        pop hl
        ld de,n_val
        ex de,hl
        call cpy32
        ld hl,n_val
        call abs32
        ld a,0
        rla
        ld (fn_neg),a
        ld a,(fn_dec)           ; rounded to dec decimals
        neg
        add a,c
        call rdiv
        ld hl,n_val
        call tst32
        jr nz,.nz
        xor a
        ld (fn_neg),a
        ld (fn_sign),a
.nz:    pop de
        ld a,(fn_neg)
        or a
        ld a,'-'
        jr nz,.sg
        ld a,(fn_sign)
        or a
        jr z,.ns
        ld a,'+'
.sg:    ld (de),a
        inc de
.ns:    ld a,(fn_dec)           ; whole = a / 10^dec, frac = a % 10^dec
        call p10
        push de
        ex de,hl
        ld hl,m_opb
        call cpy32
        ld hl,m_acc
        ld de,n_val
        call cpy32
        xor a
        ld (m_acc+4),a
        ld (m_acc+5),a
        ld (m_acc+6),a
        ld (m_acc+7),a
        call div64
        pop de
        ld hl,m_acc             ; (at most 999999999)
        push de
        ld de,c999999999
        call cmp32u
        pop de
        jr c,.w
        push de
        ld de,c999999999
        call cpy32
        pop de
.w:     call fmt_u32
        ld a,(fn_dec)
        or a
        ret z
        ld b,a
        ld a,'.'
        ld (de),a
        inc de
        ld hl,m_rem             ; frac, dec digits with the zeros in front
        push de
        ld hl,n_u
        ld de,m_rem
        call cpy32
        pop de
        ld c,b
.f:     ld hl,n_u               ; the digits from the right
        call div10
        add a,'0'
        push af
        dec c
        jr nz,.f
.fo:    pop af
        ld (de),a
        inc de
        djnz .fo
        xor a
        ld (de),a
        ret

;------------------------------------------------------------------------------
; pct100: HL = price, DE = previous close -> n_pct (hundredths of a percent):
; ((price - prev) * 10000 +- prev/2) / prev, at most +-999999; prev <= 0: 0
pct100: push hl
        ex de,hl
        call tst32
        ex de,hl
        pop hl
        jp c,.zero
        jp z,.zero
        push de
        ex de,hl                ; n_t = price - prev
        ld hl,n_t
        call cpy32
        pop de
        call sub32
        call abs32
        ld a,0
        rla
        ld (fn_neg),a
        push de
        ld hl,m_acc             ; |d| * 10000
        ld de,n_t
        call cpy32
        ld hl,m_opb
        ld de,c10000
        call cpy32
        call mul32
        pop de
        ld hl,n_u               ; + prev / 2
        call cpy32
        push de
        ld hl,n_u+3
        ld b,4
        or a
.h:     rr (hl)
        dec hl
        djnz .h
        call acc_add
        pop de
        ld hl,m_opb             ; / prev (the most when it would not fit 32 bits)
        call cpy32
        ld hl,m_acc+4
        ld de,m_opb
        call cmp32u
        jr nc,.max
        call div64
        ld hl,m_acc
        ld de,c999999
        call cmp32u
        jr c,.in
.max:   ld hl,n_pct
        ld de,c999999
        call cpy32
        jr .sgn
.in:    ld hl,n_pct
        ld de,m_acc
        call cpy32
.sgn:   ld a,(fn_neg)
        or a
        ret z
        ld hl,n_pct
        jp neg32
.zero:  ld hl,n_pct
        jp zero32

; acc_add: m_acc (64) += n_u (32)
acc_add:
        ld hl,m_acc
        ld de,n_u
        ld b,4
        or a
.a:     ld a,(de)
        adc a,(hl)
        ld (hl),a
        inc hl
        inc de
        djnz .a
        ld b,4
.c:     ld a,(hl)
        adc a,0
        ld (hl),a
        inc hl
        djnz .c
        ret
c10000: dd 10000
c999999: dd 999999
c999999999: dd 999999999

; fmt_pct: n_pct -> "+0.08%" at DE (DE on the 0)
fmt_pct:
        ld hl,n_pct
        call tst32
        jr z,.p
        ld a,'+'
        jr nc,.s
        ld a,'-'
.s:     ld (de),a
        inc de
.p:     push de
        ld hl,n_t
        ld de,n_pct
        call cpy32
        call abs32
        pop de
        ld a,100
        ld hl,m_opb
        call set32
        push de
        ld hl,m_acc
        ld de,n_t
        call cpy32
        xor a
        ld (m_acc+4),a
        ld (m_acc+5),a
        ld (m_acc+6),a
        ld (m_acc+7),a
        call div64
        pop de
        ld hl,m_acc
        call fmt_u32
        ld a,'.'
        ld (de),a
        inc de
        ld a,(m_rem)
        call put2
        ld a,'%'
        ld (de),a
        inc de
        xor a
        ld (de),a
        ret
