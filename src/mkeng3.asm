;==============================================================================
; mkeng3.asm - the market engine, part 3: the chart's time scale, the
; headlines' tape (Yahoo Finance's feed for the region's indices), and the
; disk: MARKETS.CAT (the members of the indices) and MARKETS.INI.
;==============================================================================

;------------------------------------------------------------------------------
; the time scale, in the local time: the day's hours; the days of 5 days; a
; month's weeks; the months; the years. A label where the unit changes, when
; there is room after the one before it
        VAR xs_n, 1
        VAR xs_col, 8
        VAR xs_txt, 64
        VAR xs_st, 1            ; hours a step (the day)
        VAR xs_tt, 4
        VAR xs_i, 2
        VAR xs_key, 2
        VAR xs_hk, 1            ; a key was seen
        VAR xs_last, 2          ; the last label's column (signed)
        VAR xs_y, 2
        VAR xs_mo, 1
        VAR xs_years, 1
        VAR xs_months, 1
        VAR xs_lab, 8
        VAR xs_c, 1
cg_xscale:
        xor a
        ld (xs_n),a
        ld a,(ch_range)
        or a
        jp nz,.pts
        ; hours = dur / 3600: steps of 2, 3 or 6 hours
        ld hl,m_acc
        ld de,cg_dur
        call cpy32
        xor a
        ld (m_acc+4),a
        ld (m_acc+5),a
        ld (m_acc+6),a
        ld (m_acc+7),a
        ld hl,m_opb
        ld de,c3600
        call cpy32
        call div64
        ld a,(m_acc+1)          ; (more than 255 hours: 6)
        or a
        ld a,6
        jr nz,.st
        ld a,(m_acc)
        cp 11
        ld a,2
        jr c,.st
        ld a,(m_acc)
        cp 17
        ld a,3
        jr c,.st
        ld a,6
.st:    ld (xs_st),a
        ; tt = t0 - (h % st) * 3600 - mi * 60 - s: the round hour at or before t0
        ld hl,cg_t0
        call civil
        ld a,(cv_h)
        ld hl,xs_st
.hm:    cp (hl)
        jr c,.hm2
        sub (hl)
        jr .hm
.hm2:   ld hl,xs_tt
        ld de,cg_t0
        call cpy32
        ld l,a                  ; - (h % st) * 3600
        ld h,0
        ld de,3600
        call mul16              ; (at most 5 * 3600: 16 bits)
        call .subhl
        ld a,(cv_mi)
        ld l,a
        ld h,0
        ld de,60
        call mul16
        call .subhl
        ld a,(cv_s)
        ld l,a
        ld h,0
        call .subhl
.hl:    ld a,(xs_n)             ; while tt <= t1 and n < 8
        cp 8
        jp nc,.out
        ld hl,xs_tt
        ld de,cg_t1
        call cmp32u
        jr c,.hl1
        jp nz,.out
.hl1:   ld hl,xs_tt             ; tt >= t0: a label
        ld de,cg_t0
        call cmp32u
        jr c,.hnx
        ld hl,xs_tt
        call civil
        ld de,xs_lab
        ld a,(cv_h)
        call put2
        ld hl,txt_00
        call strcpy
        ; col = (tt - t0) * (width - 1) / dur
        ld hl,m_acc
        ld de,xs_tt
        call cpy32
        ld de,cg_t0
        call sub32
        ld hl,m_opb
        ld a,(cg_w)
        dec a
        call set32
        call mul32
        ld hl,m_opb
        ld de,cg_dur
        call cpy32
        call div64
        ld a,(m_acc)
        call .store
.hnx:   ld a,(xs_st)            ; tt += st * 3600
        ld l,a
        ld h,0
        ld de,3600
        call mul16
        ld (e_t32b),hl
        ld hl,0
        ld (e_t32b+2),hl
        ld hl,xs_tt
        ld de,e_t32b
        call add32
        jp .hl
.subhl: ld (e_t32b),hl          ; xs_tt -= HL
        ld hl,0
        ld (e_t32b+2),hl
        ld hl,xs_tt
        ld de,e_t32b
        jp sub32

.pts:   ; the other ranges: point after point
        ld hl,(ch_n)            ; the last point's year and month
        dec hl
        add hl,hl
        add hl,hl
        ld de,pt_t
        add hl,de
        call civil
        ld hl,(cv_y)
        ld (xs_y),hl
        ld a,(cv_mo)
        ld (xs_mo),a
        ld hl,pt_t              ; the first's
        call civil
        ; years a label (all): by the span
        ld hl,(xs_y)
        ld de,(cv_y)
        or a
        sbc hl,de               ; sp
        ld a,1
        ld de,8
        call .le
        jr c,.yy
        ld a,2
        ld de,15
        call .le
        jr c,.yy
        ld a,5
        ld de,36
        call .le
        jr c,.yy
        ld a,10
        ld de,71
        call .le
        jr c,.yy
        ld a,20
.yy:    ld (xs_years),a
        ; months: every 2nd when more than 8 months
        ld hl,(xs_y)
        call .ym                ; HL = y * 12 (+ mo)
        ld a,(xs_mo)
        call add_hla
        push hl
        ld hl,(cv_y)
        call .ym
        ld a,(cv_mo)
        call add_hla
        ex de,hl
        pop hl
        or a
        sbc hl,de
        ld de,9
        or a
        sbc hl,de
        ld a,1
        jr c,.mm
        ld a,2
.mm:    ld (xs_months),a
        xor a
        ld (xs_hk),a
        ld hl,-100
        ld (xs_last),hl
        ld hl,0
        ld (xs_i),hl
.pl:    ld a,(xs_n)
        cp 8
        jp nc,.out
        ld hl,(xs_i)
        ld de,(ch_n)
        or a
        sbc hl,de
        jp nc,.out
        ld hl,(xs_i)
        add hl,hl
        add hl,hl
        ld de,pt_t
        add hl,de
        push hl
        call civil
        pop hl
        ld de,xs_lab
        ld a,(ch_range)
        cp 1
        jr nz,.r2
        ld hl,(cv_days)         ; 5 days: the day, its weekday
        push hl
        ld hl,wdays
        ld a,(cv_wd)
        call nth
        call strcpy
        pop hl
        jp .key
.r2:    cp 2
        jr nz,.r3
        push hl                 ; a month: the week (from the UTC days), "13 Nov"
        ld hl,(cv_d)
        ld h,0
        call r_fmt_u16
        ld a,' '
        ld (de),a
        inc de
        ld hl,months
        ld a,(cv_mo)
        dec a
        call nth
        call strcpy
        pop hl
        ld de,m_acc             ; (UTC days + 3) / 7
        ex de,hl
        call cpy32
        xor a
        ld (m_acc+4),a
        ld (m_acc+5),a
        ld (m_acc+6),a
        ld (m_acc+7),a
        ld hl,m_opb
        ld de,c86400
        call cpy32
        call div64
        ld hl,(m_acc)
        ld de,3
        add hl,de
        ld de,7
        call div16
        jr .key
.r3:    cp 6
        jr nc,.r6
        ld hl,months            ; 6 months, the year, 1 year: the months
        ld a,(cv_mo)
        dec a
        call nth
        call strcpy
        ld hl,(cv_y)            ; (y * 12 + mo - 1) / months
        call .ym
        ld a,(cv_mo)
        dec a
        call add_hla
        ld a,(xs_months)
        ld e,a
        ld d,0
        call div16
        jr .key
.r6:    ld hl,(cv_y)            ; 5 years, all: the years
        push af
        push hl
        call r_fmt_u16
        xor a
        ld (de),a
        pop hl
        pop af
        cp 6
        jr z,.key
        ld a,(xs_years)
        ld e,a
        ld d,0
        call div16
.key:   ld a,(xs_hk)            ; the same unit as the one before: no label
        or a
        jr z,.k1
        ld de,(xs_key)
        or a
        sbc hl,de
        jp z,.pnx
        add hl,de
.k1:    ld (xs_key),hl
        ld a,(xs_hk)
        ld c,a                  ; C = 0: the first point
        ld a,1
        ld (xs_hk),a
        ld a,c
        or a
        jr nz,.col
        ld a,(ch_range)         ; (the first: the middle of its unit, but for the days)
        cp 1
        jp nz,.pnx
.col:   ld hl,(ch_n)            ; col = i * (width - 1) / (n - 1)
        dec hl
        ld a,h
        or l
        ld a,0
        jr z,.cs
        ld hl,m_acc
        ld de,xs_i
        call zero32
        ld de,(xs_i)
        ld (m_acc),de
        ld hl,m_opb
        ld a,(cg_w)
        dec a
        call set32
        call mul32
        ld hl,m_opb
        call zero32
        ld de,(ch_n)
        dec de
        ld (m_opb),de
        call div64
        ld a,(m_acc)
.cs:    ld (xs_c),a
        ld hl,xs_lab            ; room: col >= last + (len + 1) * 3
        call strlen
        inc c
        ld a,c
        add a,a
        add a,c
        ld e,a
        ld d,0
        ld hl,(xs_last)
        add hl,de
        ex de,hl                ; DE = the least column
        ld a,(xs_c)
        ld l,a
        ld h,0
        or a
        sbc hl,de
        jp m,.pnx
        ld a,(xs_c)
        ld l,a
        ld h,0
        ld (xs_last),hl
        call .store
.pnx:   ld hl,(xs_i)
        inc hl
        ld (xs_i),hl
        jp .pl

; .store: A = the column, xs_lab the label: kept
.store: push af
        ld a,(xs_n)
        ld hl,xs_col
        call add_hla
        pop af
        ld (hl),a
        ld a,(xs_n)
        add a,a
        add a,a
        add a,a
        ld hl,xs_txt
        call add_hla
        ex de,hl
        ld hl,xs_lab
        ld bc,7
        ldir
        xor a
        ld (de),a
        ld hl,xs_n
        inc (hl)
        ret
; .le: CF when HL <= DE - 1 (signed small numbers), A kept
.le:    push hl
        push af
        or a
        sbc hl,de
        pop bc
        ld a,b
        pop hl
        ret
.ym:    add hl,hl               ; HL * 12
        add hl,hl
        push hl
        add hl,hl
        pop de
        add hl,de
        ret

.out:   ld a,(xs_n)
        call rp_byte
        or a
        ret z
        ld b,a
        ld c,0
.o:     push bc
        ld a,c
        ld hl,xs_col
        call add_hla
        ld a,(hl)
        call rp_byte
        ld a,c
        add a,a
        add a,a
        add a,a
        ld hl,xs_txt
        call add_hla
        call rp_str
        pop bc
        inc c
        djnz .o
        ret
txt_00: db ":00",0
c3600:  dd 3600

;------------------------------------------------------------------------------
; the tape: the titles of the feed's items, " +++ " between them
tp_body:
.l:     ld a,b
        or c
        ret z
        ld a,(hl)
        inc hl
        dec bc
        push hl
        push bc
        call tp_char
        pop bc
        pop hl
        ret c                   ; (full)
        jr .l

tp_char:
        ld c,a
        ld a,(tp_in)
        or a
        jr nz,.in
        ld hl,txt_ttl           ; looking for "title":" (tp_tn of it seen)
        ld a,(tp_tn)
        call add_hla
        ld a,c
        cp (hl)
        jr z,.m
        cp '"'                  ; (perhaps its start again)
        ld a,0
        jr nz,.m0
        inc a
.m0:    ld (tp_tn),a
        or a
        ret
.m:     ld hl,tp_tn
        inc (hl)
        ld a,(hl)
        cp 9
        jr nc,.go
        or a
        ret
.go:    xor a
        ld (tp_tn),a
        ld (tp_en),a
        ld (tp_more),a
        ld hl,(tp_new)          ; no room for one more: enough
        ld de,60
        add hl,de
        ld de,TAPE_MAX
        or a
        sbc hl,de
        ccf
        ret c
        ld hl,(tp_new)          ; (the first after the name: no +++)
        ld de,(tp_l0)
        sbc hl,de
        jr z,.t2b
        ld hl,txt_sep
        ld b,5
.sp:    ld a,(hl)
        call tp_put
        inc hl
        djnz .sp
.t2b:   ld a,1
        ld (tp_in),a
        or a
        ret
.in:    ld a,(tp_en)            ; 1: after a backslash, 2-5: in \uXXXX
        or a
        jr z,.n
        dec a
        jr nz,.hx
        ld a,c
        cp 'u'
        jr z,.u
        xor a
        ld (tp_en),a
        ld a,c
        cp 'a'                  ; \n \t ...: a space; \" \\ \/: as they are
        jr c,.lit
        ld a,' '
.lit:   call tp_put
        or a
        ret
.u:     ld a,2
        ld (tp_en),a
        ld hl,0
        ld (tp_cp),hl
        or a
        ret
.hx:    ld a,c
        call hexd
        ld hl,(tp_cp)
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        or l
        ld l,a
        ld (tp_cp),hl
        ld hl,tp_en
        inc (hl)
        ld a,(hl)
        cp 6
        jr nc,.ue
        or a
        ret
.ue:    xor a
        ld (tp_en),a
        ld hl,(tp_cp)
        jp tp_cpt
.n:     ld a,c
        cp #5C
        jr nz,.q
        ld a,1
        ld (tp_en),a
        or a
        ret
.q:     cp '"'                  ; the title's end
        jr nz,.x3
        xor a
        ld (tp_in),a
        ret
.x3:    ld a,(tp_more)          ; UTF-8
        or a
        jr z,.x4
        dec a
        ld (tp_more),a
        ld hl,(tp_cp)           ; cp = cp << 6 | (c & 3Fh)
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld a,c
        and #3F
        or l
        ld l,a
        ld (tp_cp),hl
        ld a,(tp_more)
        or a
        ret nz
        jp tp_cpt
.x4:    ld a,c
        cp #F0
        jr c,.u3
        ld hl,#FFFF             ; (beyond 16 bits: a question mark)
        ld (tp_cp),hl
        ld a,3
        jr .um
.u3:    cp #E0
        jr c,.u2
        and 15
        ld l,a
        ld a,2
        jr .us
.u2:    cp #C0
        jr c,.u1
        and 31
        ld l,a
        ld a,1
.us:    ld h,0
        ld (tp_cp),hl
.um:    ld (tp_more),a
        or a
        ret
.u1:    ld l,c
        ld h,0
        ; fall through
; tp_cp: HL = a code point: as ASCII to the tape
tp_cpt: ld a,h
        or a
        jr nz,.f
        ld a,l
        cp 128
        jr nc,.f
        ld c,a
        jr .c
.f:     call tp_fold
        ld c,a
.c:     ld a,c
        cp 10
        jr z,.sp
        cp 13
        jr z,.sp
        cp 9
        jr nz,.n
.sp:    ld a,' '
.n:     cp ' '
        ccf
        ret nc                  ; (control characters: not)
        call tp_put
        or a
        ret
; tp_put: A to the tape (no second space)
tp_put: push hl
        push de
        push bc
        ld c,a
        ld hl,(tp_new)
        inc hl
        ld de,TAPE_MAX
        or a
        sbc hl,de
        jr nc,.e
        ld a,c
        cp ' '
        jr nz,.p
        ld hl,(tp_new)
        ld a,h
        or l
        jr z,.p
        dec hl
        ld de,tp_nb
        add hl,de
        ld a,(hl)
        cp ' '
        jr z,.e
.p:     ld hl,(tp_new)
        push hl
        ld de,tp_nb
        add hl,de
        ld (hl),c
        pop hl
        inc hl
        ld (tp_new),hl
.e:     pop bc
        pop de
        pop hl
        ret
; tp_fold: HL = a code point above 127 -> A in ASCII
tp_fold:
        ld a,h
        or a
        jr nz,.u
        ld a,l
        cp #A0
        ld a,' '
        ret z
        ld a,l
        cp #C0
        ld a,'?'
        ret c
        ld a,l
        sub #C0
        ld hl,latin
        call add_hla
        ld a,(hl)
        ret
.u:     ld de,folds
.l:     ld a,(de)
        inc de
        or a
        ld a,'?'
        ret z
        dec de
        ld a,(de)
        cp l
        jr nz,.n
        inc de
        ld a,(de)
        cp h
        jr nz,.n1
        inc de
        ld a,(de)
        ret
.n:     inc de
.n1:    inc de
        inc de
        jr .l
latin:  db "AAAAAAACEEEEIIIIDNOOOOOxOUUUUYTs"
        db "aaaaaaaceeeeiiiidnooooo/ouuuuyty"
folds:  dw #2018 : db 39
        dw #2019 : db 39
        dw #201A : db 39
        dw #201C : db '"'
        dw #201D : db '"'
        dw #201E : db '"'
        dw #2013 : db '-'
        dw #2014 : db '-'
        dw #2026 : db '.'
        dw #20AC : db 'E'
        db 0,0
; hexd: A = a hex digit -> A = its value (0 for anything else)
hexd:   sub '0'
        cp 10
        ret c
        or #20
        sub 'a'-'0'
        cp 6
        jr nc,.z
        add a,10
        ret
.z:     xor a
        ret

txt_ttl:    db '"title":"'

;------------------------------------------------------------------------------
; the disk: the disk BASIC's BDOS (F37Dh), its errors caught (H.ERRO)
H_ERRO  equ #FFB1
DBDOS   equ #F37D
        VAR dk_sp, 2
        VAR dk_err, 1
        VAR dk_old, 5
        VAR dk_fcb, 40

; dk_open: DE = 11 characters of a name: open (CF: not there / no disk)
dk_open:
        ld a,(H_PHYD)
        cp #C9
        scf
        ret z
        push de
        ld hl,dk_fcb
        ld de,dk_fcb+1
        ld bc,39
        ld (hl),0
        ldir
        pop hl
        ld de,dk_fcb+1
        ld bc,11
        ldir
        ld de,dk_fcb
        ld c,#0F
        call dbdos
        ret c
        inc a
        scf
        ret z                   ; (FFh: not there)
        ld hl,1                 ; records of 1 byte
        ld (dk_fcb+14),hl
        or a
        ret
; dk_read: HL = where in the file, DE = to, BC = at most -> HL = bytes read
dk_read:
        ld (dk_fcb+33),hl
        ld hl,0
        ld (dk_fcb+35),hl
        push bc
        ld c,#1A
        call dbdos              ; (DE: the DMA)
        pop hl
        ret c
        ld de,dk_fcb
        ld c,#27
        jp dbdos
dk_close:
        ld de,dk_fcb
        ld c,#10
        jp dbdos

; dbdos: C = function, DE = its parameter: A, HL as it gives them (CF: a disk error)
dbdos:  push bc
        push de
        push hl
        ld hl,H_ERRO
        ld de,dk_old
        ld bc,5
        ldir
        ld hl,H_ERRO
        ld (hl),#F7
        inc hl
        ld a,(rom_slot)
        ld (hl),a
        inc hl
        ld (hl),low dk_trap
        inc hl
        ld (hl),high dk_trap
        inc hl
        ld (hl),#C9
        pop hl
        pop de
        pop bc
        ld (dk_sp),sp
        call DBDOS
        ei
        push af
        push hl
        call dk_unhook
        pop hl
        pop af
        or a
        ret
dk_trap:                        ; (H.ERRO: E = the BASIC error)
        ld a,e
        ld (dk_err),a
        ld sp,(dk_sp)
        ei
        call dk_unhook
        scf
        ret
dk_unhook:
        ld hl,dk_old
        ld de,H_ERRO
        ld bc,5
        ldir
        ret

;------------------------------------------------------------------------------
; cat_members: HL = an index's symbol -> mb (its members), mb_name, B = count; CF: none
txt_catname: db "MARKETS CAT"
        VAR cm_sym, 2
        VAR cm_off, 2
        VAR cm_cnt, 1
cat_members:
        ld (cm_sym),hl
        ld de,txt_catname
        call dk_open
        ret c
        ld hl,0                 ; "MKCAT1", u16 directory size, u8 indices
        ld de,mb
        ld bc,9
        call dk_read
        jp c,.fail
        ld hl,mb
        ld de,txt_mkcat
        ld b,6
.sig:   ld a,(de)
        cp (hl)
        jp nz,.fail
        inc hl
        inc de
        djnz .sig
        ld c,(hl)               ; the directory
        inc hl
        ld b,(hl)
        ld hl,400
        or a
        sbc hl,bc
        jr c,.fail
        ld hl,9
        ld de,mb
        call dk_read
        jr c,.fail
        ld a,(mb+0)             ; (count from the header: read again below)
        ld hl,mb                ; find the symbol: symbol 0, name 0, u16 offset, u8 count
.f:     ld a,(hl)
        or a
        jr z,.fail
        push hl
        ld de,(cm_sym)
.c:     ld a,(de)
        cp (hl)
        jr nz,.no
        or a
        jr z,.yes
        inc hl
        inc de
        jr .c
.no:    pop hl
        call skipz
        call skipz
        inc hl
        inc hl
        inc hl
        jr .f
.yes:   pop hl
        call skipz
        ld de,mb_name           ; its name
        ld b,39
.n:     ld a,(hl)
        ld (de),a
        inc hl
        inc de
        or a
        jr z,.ne
        djnz .n
        xor a
        ld (de),a
        call skipz
.ne:    ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld (cm_off),de
        ld a,(hl)
        cp ROWS_MAX+1
        jr c,.cn
        ld a,ROWS_MAX
.cn:    ld (cm_cnt),a
        ld hl,(cm_off)          ; the members
        ld de,mb
        ld bc,1700
        call dk_read
        jr c,.fail
        call dk_close
        ld a,(cm_cnt)
        ld b,a
        or a
        ret
.fail:  call dk_close
        scf
        ret
txt_mkcat: db "MKCAT1"
