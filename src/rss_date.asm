;------------------------------------------------------------------------------
; parse_date: HL = "Thu, 29 Oct 2026 20:15:00 GMT" / "+0100" / "EST",
; "2026-10-29T18:30:00Z" / "+01:00" -> pd_days, pd_min, pd_sec (UTC); CF: not understood
        VAR pd_h, 1
        VAR pd_mi, 1
parse_date:
        call skipsp
        xor a
        ld (pd_sec),a
        push hl
        ld bc,4
        add hl,bc
        ld a,(hl)
        pop hl
        cp '-'
        jr nz,.rfc
        call num                ; ISO: 2026-10-29T18:30[:00][.000][Z|+01:00]
        ret c
        ld (dc_y),de
        inc hl
        call num
        ret c
        ld a,e
        ld (dc_m),a
        inc hl
        call num
        ret c
        ld a,e
        ld (dc_d),a
        ld a,(hl)
        inc hl
        cp 'T'
        jr z,.it
        cp ' '
        scf
        ret nz
.it:    call .hms
        ret c
.fr:    ld a,(hl)
        cp '.'
        jr z,.f1
        sub '0'
        cp 10
        jr nc,.zone
.f1:    inc hl
        jr .fr
.rfc:   push hl                 ; "Thu, " (a ',' in the first 5)
        ld b,5
.c:     ld a,(hl)
        inc hl
        cp ','
        jr z,.cf
        or a
        jr z,.cn
        djnz .c
.cn:    pop hl
        jr .r2
.cf:    pop af
.r2:    call skipsp
        call num
        ret c
        ld a,e
        ld (dc_d),a
        call skipsp
        ld de,months            ; "Oct"
        ld b,1
.mo:    push hl
        push de
        call .m3
        pop de
        pop hl
        jr z,.mf
        ex de,hl
        call skipz
        ex de,hl
        inc b
        ld a,b
        cp 13
        jr c,.mo
        scf
        ret
.mf:    ld a,b
        ld (dc_m),a
        inc hl
        inc hl
        inc hl
        call skipsp
        call num
        ret c
        ld (dc_y),de
        call skipsp
        call .hms
        ret c
        call skipsp
.zone:  ; HL at the zone
        ld de,0                 ; the offset in minutes
        ld a,(hl)
        cp '+'
        jr z,.off
        cp '-'
        jr z,.off
        push hl
        ld ix,zones
.z:     ld a,(ix)
        or a
        jr z,.zn
        pop hl
        push hl
        ld a,(ix)
        cp (hl)
        jr nz,.zx
        inc hl
        ld a,(ix+1)
        cp (hl)
        jr nz,.zx
        inc hl
        ld a,(ix+2)
        cp (hl)
        jr nz,.zx
        ld a,(ix+3)
        ld l,a
        ld h,0
        bit 7,a
        jr z,.zp
        dec h
.zp:    ld de,60
        call mul16
        ex de,hl
        jr .zn
.zx:    inc ix
        inc ix
        inc ix
        inc ix
        jr .z
.zn:    pop hl
        jr .calc
.off:   push af
        inc hl                  ; +hh:mm or +hhmm
        ld a,(hl)
        sub '0'
        cp 10
        jr nc,.ob
        ld b,a
        add a,a
        add a,a
        add a,b
        add a,a
        ld b,a
        inc hl
        ld a,(hl)
        sub '0'
        add a,b
        inc hl
        push hl
        ld l,a
        ld h,0
        ld de,60
        call mul16
        ex de,hl
        pop hl
        ld a,(hl)
        cp ':'
        jr nz,.om
        inc hl
.om:    ld a,(hl)
        sub '0'
        cp 10
        jr nc,.oe
        ld b,a
        add a,a
        add a,a
        add a,b
        add a,a
        ld b,a
        inc hl
        ld a,(hl)
        sub '0'
        add a,b
        ex de,hl
        call add_hla
        ex de,hl
.oe:    pop af
        cp '-'
        jr nz,.calc
        ex de,hl
        call neg_hl
        ex de,hl
        jr .calc
.ob:    pop af
        ld de,0
.calc:  ; days, then minutes - the offset (into the day before / after)
        push de
        ld hl,(dc_y)
        ld de,100
        or a
        sbc hl,de
        jr nc,.y4
        ld hl,(dc_y)
        ld de,2000
        add hl,de
        ld (dc_y),hl
.y4:    call days_civ_in
        pop de
        ret c
        ld a,(pd_h)
        cp 24
        ccf
        ret c
        ld a,(pd_mi)
        cp 60
        ccf
        ret c
        ld (pd_days),hl
        push de
        ld a,(pd_h)
        ld l,a
        ld h,0
        ld de,60
        call mul16
        ld a,(pd_mi)
        call add_hla
        pop de
        or a
        sbc hl,de               ; UTC = local - offset
        ex de,hl
        ld hl,(pd_days)
        bit 7,d
        jr z,.p
        dec hl
        ex de,hl
        ld bc,1440
        add hl,bc
        ex de,hl
        jr .st
.p:     push hl
        ex de,hl
        ld bc,1440
        or a
        sbc hl,bc
        ex de,hl
        pop hl
        jr c,.u
        inc hl
        jr .st
.u:     ex de,hl
        add hl,bc
        ex de,hl
.st:    ld (pd_days),hl
        ld (pd_min),de
        or a
        ret
; .hms: hh:mm[:ss]
.hms:   call num
        ret c
        ld a,e
        ld (pd_h),a
        ld a,(hl)
        cp ':'
        scf
        ret nz
        inc hl
        call num
        ret c
        ld a,e
        ld (pd_mi),a
        ld a,(hl)
        cp ':'
        jr nz,.hx
        inc hl
        call num
        ld a,e
        ld (pd_sec),a
.hx:    or a
        ret
; .m3: Z when HL begins with the 3 letters at DE
.m3:    ld c,3
.m3l:   ld a,(de)
        cp (hl)
        ret nz
        inc hl
        inc de
        dec c
        jr nz,.m3l
        ret

zones:  db "GMT",0, "UTC",0, "EST",-5, "EDT",-4, "CST",-6, "CDT",-5, "MST",-7, "MDT",-6
        db "PST",-8, "PDT",-7, "CET",1, "CES",2, "BST",1, "MET",1, "EET",2, "JST",9, 0
