;==============================================================================
; mkeng2.asm - the market engine, part 2: the JSON reader (a byte at a time,
; as the reply comes in), the prices and the chart's points, MKT_CHART_GET,
; the headlines' tape, and the members of the indices from MARKETS.CAT.
;==============================================================================

;------------------------------------------------------------------------------
; js_body: HL = bytes, BC = count (the HTTP client's body routine; NC: more)
js_body:
.l:     ld a,b
        or c
        ret z                   ; (NC)
        ld a,(hl)
        inc hl
        dec bc
        push hl
        push bc
        call js_char
        pop bc
        pop hl
        jr .l

js_char:
        ld c,a
        ld a,(js_st)
        cp 2
        jr nz,.n2
        ld a,1                  ; after a backslash: the character as it is
        ld (js_st),a
        ld a,c
        jp .kch
.n2:    or a
        jr z,.out
        ld a,c                  ; in a string
        cp #5C                  ; (a backslash)
        jr nz,.n3
        ld a,2
        ld (js_st),a
        ret
.n3:    cp '"'
        jr nz,.kch
        xor a
        ld (js_st),a
        ld a,(js_isk)
        or a
        ret z
        xor a
        ld (js_ek),a
        ld hl,js_key
        ld a,(js_kn)
        call add_hla
        ld (hl),0
        jp js_key_end
.kch:   ld a,(js_isk)           ; a key's character
        or a
        ret z
        ld a,(js_kn)
        cp 23
        ret nc
        ld hl,js_key
        call add_hla
        ld (hl),c
        ld hl,js_kn
        inc (hl)
        ret
.out:   ld a,c                  ; between
        cp '"'
        jr nz,.o1
        ld a,1
        ld (js_st),a
        ld a,(js_ek)
        ld (js_isk),a
        xor a
        ld (js_kn),a
        ret
.o1:    cp '{'
        jr nz,.o2
        ld a,'o'
        call .push
        ld a,1
        ld (js_ek),a
        ret
.o2:    cp '['
        jr nz,.o3
        ld a,'a'
        call .push
        xor a
        ld (js_ek),a
        ld h,a
        ld l,a
        ld (js_idx),hl
        ret
.o3:    cp '}'
        jr z,.close
        cp ']'
        jr nz,.o4
.close: call js_flush
        ld a,(js_dep)
        or a
        ret z
        dec a
        ld (js_dep),a
        xor a
        ld (js_ek),a
        ret
.o4:    cp ','
        jr nz,.o5
        call js_flush
        call .top
        cp 'a'
        jr nz,.ob
        ld hl,(js_idx)
        inc hl
        ld (js_idx),hl
        ret
.ob:    ld a,1
        ld (js_ek),a
        ret
.o5:    cp ':'
        jr nz,.o6
        xor a
        ld (js_ek),a
        ret
.o6:    cp ' '+1                ; (spaces, line ends)
        ret c
        ld a,(js_ek)
        or a
        ret nz
        ld a,(js_vn)            ; a number's (or null's) character
        cp 23
        ret nc
        ld hl,js_val
        call add_hla
        ld (hl),c
        ld hl,js_vn
        inc (hl)
        ret
.push:  ld c,a
        ld a,(js_dep)
        cp 8
        jr nc,.p8
        ld hl,js_stk
        call add_hla
        ld (hl),c
.p8:    ld hl,js_dep
        inc (hl)
        ret
.top:   ld a,(js_dep)
        or a
        ret z
        dec a
        cp 8
        ld a,0
        ret nc
        ld a,(js_dep)
        dec a
        ld hl,js_stk
        call add_hla
        ld a,(hl)
        ret

; a key: at depth 1 a symbol (its row), at depth 2 a field
js_key_end:
        ld a,(js_dep)
        cp 1
        jr nz,.f
        ld a,#FF
        ld (js_row),a
        ld a,(e_q)
        cp Q_CHART
        jr nz,.q
        ld a,(ch_row)
        call .cmp
        ret nz
        ld a,(ch_row)
        ld (js_row),a
        ret
.q:     ld a,(e_cfirst)         ; the rows of this request
        ld c,a
        ld a,(e_cn)
        ld b,a
        or a
        ret z
.qr:    ld a,c
        ld hl,e_nrows
        cp (hl)
        ret nc
        push bc
        call .cmp
        pop bc
        jr z,.qf
        inc c
        djnz .qr
        ret
.qf:    ld a,c
        ld (js_row),a
        ld hl,e_cgot
        inc (hl)
        ret
.cmp:   call row_item           ; Z: the key is row A's symbol
        ld de,js_key
.c:     ld a,(de)
        cp (hl)
        ret nz
        or a
        ret z
        inc hl
        inc de
        jr .c
.f:     cp 2
        ret nz
        ld hl,js_ftab           ; the field
        ld b,1
.ft:    ld a,(hl)
        or a
        jr z,.fn
        push hl
        ld de,js_key
.fc:    ld a,(de)
        cp (hl)
        jr nz,.fx
        or a
        jr z,.fy
        inc hl
        inc de
        jr .fc
.fy:    pop hl
        ld a,b
        ld (js_fld),a
        ret
.fx:    pop hl
        call skipz
        inc b
        jr .ft
.fn:    xor a
        ld (js_fld),a
        ret
js_ftab: db "fulldayPrice",0,"close",0,"chartPreviousClose",0,"previousClose",0
        db "timestamp",0,"start",0,"end",0,0

; a value ends (at a , ] or }): to js_value when it belongs to a row
js_flush:
        ld a,(js_vn)
        or a
        ret z
        ld hl,js_val
        call add_hla
        ld (hl),0
        xor a
        ld (js_vn),a
        ld a,(js_row)
        cp #FF
        ret z
        ld a,(js_dep)
        cp 2
        jr z,.s
        cp 3
        ret nz
        ld hl,(js_idx)          ; in the field's array
        jr .v
.s:     ld hl,0
.v:     ld (jv_idx),hl
        ld a,(js_fld)
        or a
        ret z
        ld (jv_fld),a
        ld a,(e_q)
        cp Q_CHART
        jp z,jv_chart
        cp Q_QUOTES
        ret nz
        ; fall through
        VAR jv_idx, 2
        VAR jv_fld, 1
        VAR jv_ok, 1
; a quote's value
jv_quote:
        ld a,(js_row)
        call row_qt
        push hl
        pop ix
        ld a,(jv_fld)
        cp F_FULL
        jr nz,.n1
        call .num
        ret c
        xor a
        call put_quote
        ld a,(ix+8)
        or 5
        ld (ix+8),a
        ret
.n1:    cp F_CLOSE
        jr nz,.n2
        bit 2,(ix+8)
        ret nz
        call .num
        ret c
        xor a
        call put_quote
        set 0,(ix+8)
        ret
.n2:    cp F_CPREV
        jr nz,.n3
        call .pos
        ret c
        ld a,1
        call put_quote
        ld a,(ix+8)
        or 10
        ld (ix+8),a
        ret
.n3:    cp F_PREV
        ret nz
        bit 3,(ix+8)
        ret nz
        call .pos
        ret c
        ld a,1
        call put_quote
        set 1,(ix+8)
        ret
.num:   ld hl,js_val
        jp pnum
.pos:   call .num               ; a number above 0: NC
        ret c
        ld hl,n_val
        call tst32
        jr z,.np
        ret c                   ; (negative)
        or a
        ret
.np:    scf
        ret

; put_quote: IX = the quote, A = 1 the previous close (else the price): n_val, n_sc
        VAR pq_prev, 1
        VAR pq_sc, 1
        VAR pq_save, 5
put_quote:
        ld (pq_prev),a
        ld a,(n_sc)
        ld (pq_sc),a
        ld a,(pq_prev)          ; the other one is there?
        or a
        ld a,1
        jr nz,.ob
        ld a,2
.ob:    and (ix+8)
        jr z,.set
        ld a,(ix+9)             ; it has fewer decimals: those
        ld hl,pq_sc
        cp (hl)
        jr nc,.ge
        ld (hl),a
        jr .set
.ge:    jr z,.set
        ; it has more: the other one rounded to pq_sc
        ld hl,n_val
        ld de,pq_save
        ld bc,5
        ldir
        ld a,(pq_prev)
        or a
        push ix
        pop hl
        jr nz,.op               ; (the price is the other one of a previous close)
        ld bc,4
        add hl,bc
.op:    push hl
        ld de,n_val
        ex de,hl
        call cpy32
        ld a,(ix+9)
        ld (n_sc),a
        ld a,(pq_sc)
        call rescale
        pop hl
        ld de,n_val
        call cpy32
        ld hl,pq_save
        ld de,n_val
        ld bc,5
        ldir
.set:   ld a,(pq_sc)
        ld (ix+9),a
        call rescale            ; the new one to pq_sc
        push ix
        pop hl
        ld a,(pq_prev)
        or a
        jr z,.p
        ld bc,4
        add hl,bc
.p:     ld de,n_val
        jp cpy32

;------------------------------------------------------------------------------
; the chart's values
c2e9:   dd 2000000000
jv_chart:
        ld a,(jv_fld)
        cp F_TS
        jp z,.ts
        cp F_START
        jr z,.se
        cp F_END
        jr nz,.pr
.se:    ld hl,js_val            ; start / end: a time (null: not)
        call pu32
        ret c
        ld a,(jv_fld)
        ld hl,ch_start
        cp F_START
        jr z,.s1
        ld hl,ch_end
.s1:    ld de,e_t32
        jp cpy32
.pr:    ld hl,js_val            ; a price: above 0
        call pnum
        ret c
        ld hl,n_val
        call tst32
        ret z
        ret c
        ld a,(ch_sc)
        cp #FF
        jr nz,.cv
        ld a,(n_sc)             ; the first price sets the scale, a digit to spare
        ld (ch_sc),a
        or a
        jr z,.cv
        ld hl,e_t32
        ld de,n_val
        call cpy32
        ld de,e_t32
        call add32
        ld de,c1e9
        call cmp32u
        jr c,.cv
        ld hl,ch_sc
        dec (hl)
.cv:    ; y = the value at ch_sc (e_t32); too large: a decimal less for all
        ld hl,n_val
        ld de,pq_save
        ld bc,5
        ldir
.cv1:   ld hl,pq_save
        ld de,n_val
        ld bc,5
        ldir
        ld a,(ch_sc)
        ld hl,n_sc
        cp (hl)
        jr nc,.up
        call rescale            ; fewer decimals: rounded
        jr .ck
.up:    sub (hl)                ; more: * 10 each
        jr z,.ck
        ld b,a
.m:     push bc
        ld hl,n_val
        call mul10
        pop bc
        jr c,.big
        djnz .m
.ck:    ld hl,n_val
        ld de,c2e9
        call cmp32u
        jr c,.ok
.big:   ld a,(ch_sc)
        or a
        ret z                   ; (it does not fit at all)
        dec a
        ld (ch_sc),a
        call pts_div10
        jr .cv1
.ok:    ld a,(jv_fld)
        cp F_CLOSE
        jr nz,.n1
        call .k                 ; idx % stride = 0 and idx / stride < PTS_MAX: HL = the point
        ret c
        ld de,PTS_MAX*4         ; (pt_v: pt_t + PTS_MAX*4)
        add hl,de
        ld de,n_val
        jp cpy32
.n1:    cp F_CPREV
        jr nz,.n2
.sp:    ld a,1
        ld (ch_hp),a
        ld hl,ch_prev
        ld de,n_val
        jp cpy32
.n2:    cp F_PREV
        jr nz,.n3
        ld a,(ch_hp)
        or a
        ret nz
        jr .sp
.n3:    ld a,1                  ; fulldayPrice
        ld (ch_hpr),a
        ld hl,ch_price
        ld de,n_val
        jp cpy32
; .k: the point of index jv_idx: HL = its pt_t entry; CF: not kept
.k:     ld hl,(ch_stride)
        dec hl
        ld de,(jv_idx)
        ld a,l
        and e
        ld c,a
        ld a,h
        and d
        or c
        scf
        ret nz
        ld hl,(jv_idx)          ; / stride (a power of two)
        ld de,(ch_stride)
.kd:    srl d
        rr e
        ld a,d
        or e
        jr z,.kk
        srl h
        rr l
        jr .kd
.kk:    ld de,PTS_MAX
        or a
        sbc hl,de
        add hl,de
        ccf
        ret c
        add hl,hl
        add hl,hl
        ld de,pt_t
        add hl,de
        or a
        ret
.ts:    ld hl,js_val            ; a time
        call pu32
        ret c
.ts1:   call .k
        jr nc,.tk
        ; not kept: when it is a multiple of the stride but too far, the points
        ; are halved (every 2nd) and the stride doubled
        ld hl,(ch_stride)
        dec hl
        ld de,(jv_idx)
        ld a,l
        and e
        ld c,a
        ld a,h
        and d
        or c
        ret nz
        ld hl,pt_t              ; pt_t[i] = pt_t[2i], i < PTS_MAX/2
        ld de,pt_t
        ld b,PTS_MAX/2
.h:     push bc
        ld bc,4
        ldir
        ld bc,4
        add hl,bc
        pop bc
        djnz .h
        ld hl,(ch_stride)
        add hl,hl
        ld (ch_stride),hl
        ld hl,PTS_MAX/2
        ld (ch_n),hl
        jr .ts1
.tk:    push hl
        ld de,e_t32
        call cpy32
        ld de,PTS_MAX*4
        add hl,de
        call zero32
        pop hl
        ld de,pt_t              ; k = (HL - pt_t) / 4; ch_n = max(ch_n, k+1)
        or a
        sbc hl,de
        srl h
        rr l
        srl h
        rr l
        inc hl
        ld de,(ch_n)
        or a
        sbc hl,de
        ret c
        ret z
        add hl,de
        ld (ch_n),hl
        ret

; pu32: HL = digits -> e_t32 (unsigned); CF: no digit
pu32:   ld a,(hl)
        sub '0'
        cp 10
        ccf
        ret c
        push hl
        ld hl,e_t32
        call zero32
        pop hl
.l:     ld a,(hl)
        sub '0'
        cp 10
        jr nc,.e
        inc hl
        push hl
        push af
        ld hl,e_t32
        call mul10
        pop af
        ld hl,e_t32b
        call set32
        ld hl,e_t32
        ld de,e_t32b
        call add32
        pop hl
        jr .l
.e:     or a
        ret

; the chart's prices / 10 (a decimal less): pt_v, ch_prev, ch_price
pts_div10:
        ld bc,(ch_n)
        ld hl,pt_v
.l:     ld a,b
        or c
        jr z,.e
        call div10
        inc hl
        inc hl
        inc hl
        inc hl
        dec bc
        jr .l
.e:     ld hl,ch_prev
        call div10
        ld hl,ch_price
        jp div10

; the points that have a price, in their order
pts_pack:
        ld bc,(ch_n)
        ld hl,pt_t              ; HL = from, DE = to
        ld de,pt_t
        ld ix,0                 ; IX = how many kept
.l:     ld a,b
        or c
        jr z,.e
        push bc
        push hl
        push de
        ld bc,PTS_MAX*4
        add hl,bc
        call tst32              ; its price > 0?
        pop de
        pop hl
        jr z,.skip
        jr c,.skip
        push hl                 ; the time and the price to the next kept place
        ld bc,4
        ldir
        pop hl
        push hl
        push de
        ld bc,PTS_MAX*4
        add hl,bc
        ex de,hl
        add hl,bc
        ex de,hl
        dec de                  ; (DE went on by 4 already: back)
        dec de
        dec de
        dec de
        ld bc,4
        ldir
        pop de
        pop hl
        inc ix
.skip:  ld bc,4
        add hl,bc
        pop bc
        dec bc
        jr .l
.e:     ld (ch_n),ix
        ret

;------------------------------------------------------------------------------
; MKT_CHART_GET: args u8 columns, u8 levels
        VAR cg_w, 1
        VAR cg_lv, 1
        VAR cg_lo, 4
        VAR cg_hi, 4
        VAR cg_dlo, 4
        VAR cg_dhi, 4
        VAR cg_last, 4
        VAR cg_span, 4
        VAR cg_t0, 4
        VAR cg_t1, 4
        VAR cg_dur, 4
        VAR cg_first, 4
        VAR cg_lastt, 4
        VAR cg_v, 4
        VAR cg_tx, 4
        VAR cg_k, 2
        VAR cg_x, 1
        VAR cg_dec, 1
        VAR cg_txt, 40
        VAR cg_step, 4
        VAR cg_base, 4
        VAR cg_n, 1
        VAR cg_fr, 1
c_chget:
        ld a,(ch_state)
        cp ST_DONE
        ld a,PVA_E_STATE
        ret nz
        ld hl,(ch_n)
        ld a,h
        or l
        ld a,PVA_E_STATE
        ret z
        ld a,(args)
        ld (cg_w),a
        cp 8
        jr c,.ea
        cp 241
        jr nc,.ea
        ld a,(args+1)
        ld (cg_lv),a
        cp 8
        jr c,.ea
        cp 121
        jr c,.ok
.ea:    ld a,PVA_E_ARGS
        ret
.ok:    ld a,(ch_row)
        call row_dec
        ld (cg_dec),a
        ; lo, hi of the points
        ld hl,cg_lo
        ld de,pt_v
        call cpy32
        ld hl,cg_hi
        call cpy32
        ld bc,(ch_n)
        ld hl,pt_v
.mm:    ex de,hl
        ld hl,cg_lo
        call cmp32s             ; lo > v?
        jr c,.m1
        jr z,.m1
        call cpy32
.m1:    ld hl,cg_hi
        call cmp32s             ; hi < v?
        jr nc,.m2
        call cpy32
.m2:    ex de,hl
        inc hl
        inc hl
        inc hl
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,.mm
        ld hl,cg_dlo
        ld de,cg_lo
        call cpy32
        ld hl,cg_dhi
        ld de,cg_hi
        call cpy32
        ld hl,cg_last           ; last: the day's price, else the last point
        ld de,ch_price
        ld a,(ch_hpr)
        or a
        jr nz,.la
        ld de,(ch_n)
        dec de
        ex de,hl
        add hl,hl
        add hl,hl
        ld de,pt_v
        add hl,de
        ex de,hl
        ld hl,cg_last
.la:    call cpy32
        ld a,(ch_hp)            ; the previous close in the range too
        or a
        jr z,.np
        ld hl,cg_lo
        ld de,ch_prev
        call cmp32s
        jr c,.p1
        jr z,.p1
        call cpy32
.p1:    ld hl,cg_hi
        call cmp32s
        jr nc,.np
        call cpy32
.np:    ld hl,cg_span           ; span = hi - lo (at least 1)
        ld de,cg_hi
        call cpy32
        ld de,cg_lo
        call sub32
        call tst32
        jr c,.s1
        jr nz,.s2
.s1:    ld a,1
        call set32
.s2:    ; the times: t0, t1 (the exchange's day when the reply has it)
        ld hl,cg_first
        ld de,pt_t
        call cpy32
        ld hl,(ch_n)
        dec hl
        add hl,hl
        add hl,hl
        ld de,pt_t
        add hl,de
        ex de,hl
        ld hl,cg_lastt
        call cpy32
        ld hl,cg_t0
        ld de,cg_first
        call cpy32
        ld hl,ch_start          ; start and start <= first: start
        call tst32
        jr z,.t0
        ld hl,ch_start
        ld de,cg_first
        call cmp32u
        jr c,.t0s
        jr nz,.t0
.t0s:   ld hl,cg_t0
        ld de,ch_start
        call cpy32
.t0:    ld hl,cg_t1
        ld de,cg_lastt
        call cpy32
        ld hl,cg_lastt          ; end > last: end
        ld de,ch_end
        call cmp32u
        jr nc,.t1
        ld hl,cg_t1
        call cpy32
.t1:    ld hl,cg_dur            ; more than 2 days: the points' own
        ld de,cg_t1
        call cpy32
        ld de,cg_t0
        call sub32
        ld de,c172800
        call cmp32u
        jr c,.du
        jr z,.du
        ld hl,cg_t0
        ld de,cg_first
        call cpy32
        ld hl,cg_t1
        ld de,cg_lastt
        call cpy32
        ld hl,cg_dur
        ld de,cg_t1
        call cpy32
        ld de,cg_t0
        call sub32
.du:    ld hl,cg_dur            ; (at least 1)
        call tst32
        jr nz,.dn
        ld a,1
        call set32
.dn:    ; the reply: columns, the previous close's level, the texts
        ld a,(cg_w)
        call rp_byte
        xor a
        ld b,a
        ld a,(ch_hp)
        or a
        jr z,.pl
        ld hl,ch_prev
        call level
        ld b,a
.pl:    ld a,b
        call rp_byte
        ld a,(ch_row)
        call row_name
        call rp_str
        ld ix,cg_last           ; the price
        xor a
        call cg_num
        ld a,(ch_hp)            ; the change and its percent
        or a
        jr z,.nc
        ld hl,cg_v
        ld de,cg_last
        call cpy32
        ld de,ch_prev
        call sub32
        ld ix,cg_v
        ld a,(ch_sc)
        ld c,a
        ld a,(cg_dec)
        ld b,a
        ld a,1
        ld de,cg_txt
        call fmt_num
        ld a,' '
        ld (de),a
        inc de
        ld (de),a
        inc de
        push de
        ld hl,cg_last
        ld de,ch_prev
        call pct100
        pop de
        call fmt_pct
        ld hl,cg_txt
        call rp_str
        jr .hl
.nc:    xor a
        call rp_byte
.hl:    ld ix,cg_dhi
        xor a
        call cg_num
        ld ix,cg_dlo
        xor a
        call cg_num
        ld a,(ch_hp)
        or a
        jr z,.np2
        ld ix,ch_prev
        xor a
        call cg_num
        jr .cols
.np2:   xor a
        call rp_byte
.cols:  call cg_columns
        call cg_yscale
        jp cg_xscale

c172800: dd 172800

; cg_num: IX = a value: fmt_num with the chart's scale and the row's decimals, to the reply
cg_num: push af
        ld a,(ch_sc)
        ld c,a
        ld a,(cg_dec)
        ld b,a
        pop af
        ld de,cg_txt
        call fmt_num
        ld hl,cg_txt
        jp rp_str

; level: HL = a value -> A = 1 + (v - lo) * (levels - 1) / span
level:  ld de,m_acc
        ex de,hl
        call cpy32
        ld de,cg_lo
        call sub32
        ld hl,m_opb
        ld a,(cg_lv)
        dec a
        call set32
        call mul32
        ld hl,m_opb
        ld de,cg_span
        call cpy32
        call div64
        ld a,(m_acc)
        inc a
        ret

; the columns: by the time (the day), or point after point
cg_columns:
        ld hl,0
        ld (cg_k),hl
        xor a
        ld (cg_x),a
.x:     ld a,(cg_x)
        ld hl,cg_w
        cp (hl)
        ret nc
        ld a,(ch_range)
        or a
        jp nz,.pp
        ; tx = t0 + dur * x / (width - 1)
        ld hl,m_acc
        ld de,cg_dur
        call cpy32
        ld hl,m_opb
        ld a,(cg_x)
        call set32
        call mul32
        ld hl,m_opb
        ld a,(cg_w)
        dec a
        call set32
        call div64
        ld hl,cg_tx
        ld de,m_acc
        call cpy32
        ld de,cg_t0
        call add32
        ld de,cg_first          ; outside the points: nothing
        call cmp32u
        jp c,.zero
        ld hl,cg_lastt
        ld de,cg_tx
        call cmp32u
        jp c,.zero
.adv:   ld hl,(cg_k)            ; while k+1 < n and t[k+1] <= tx: k++
        inc hl
        ld de,(ch_n)
        or a
        sbc hl,de
        jr nc,.ak
        add hl,de
        add hl,hl
        add hl,hl
        ld de,pt_t
        add hl,de
        ld de,cg_tx
        call cmp32u             ; t[k+1] <= tx: CF or Z
        jr c,.inc
        jr nz,.ak
.inc:   ld hl,(cg_k)
        inc hl
        ld (cg_k),hl
        jr .adv
.ak:    call .vk                ; v = pt_v[k], HL = pt_t[k]
        ld de,(cg_k)            ; k+1 < n and t[k+1] > t[k]: between them
        inc de
        push hl
        ld hl,(ch_n)
        or a
        sbc hl,de
        pop hl
        jp c,.lev
        jp z,.lev
        push hl
        pop ix                  ; IX = t[k]
        ld bc,4
        add hl,bc               ; HL = t[k+1]
        ex de,hl
        push ix
        pop hl
        call cmp32u             ; t[k] < t[k+1]?
        jp nc,.lev
        ; num = tx - t[k], den = t[k+1] - t[k]
        push de
        ld hl,cg_tx
        ld de,m_mp              ; (scratch: m_mp is mul32's own, set again there)
        ex de,hl
        ld de,cg_tx
        call cpy32
        push ix
        pop de
        ld hl,m_mp
        call sub32
        pop de
        ld hl,cg_step           ; (scratch) = t[k+1] - t[k]
        call cpy32
        push ix
        pop de
        call sub32
        ld hl,m_mp
        ld de,cg_base
        ex de,hl
        call cpy32              ; cg_base = num
        call .between           ; v += (v[k+1] - v[k]) * cg_base / cg_step
        jr .lev
.pp:    ; f = x * (n-1) * 256 / (width-1); k = f >> 8, the fraction f & 255
        ld hl,m_acc
        ld a,(cg_x)
        call set32
        ld de,(ch_n)
        dec de
        ld hl,m_opb
        call zero32
        ld (m_opb),de
        call mul32
        ld hl,m_acc+3           ; * 256
        ld de,m_acc+4
        ld bc,4
        lddr
        xor a
        ld (m_acc),a
        ld hl,m_opb
        ld a,(cg_w)
        dec a
        call set32
        call div64
        ld a,(m_acc)
        ld (cg_fr),a
        ld hl,(m_acc+1)
        ld (cg_k),hl
        call .vk
        ld hl,(cg_k)
        inc hl
        ld de,(ch_n)
        or a
        sbc hl,de
        jr nc,.lev
        ld hl,cg_base
        ld a,(cg_fr)
        call set32
        ld hl,cg_step
        call zero32
        ld hl,256
        ld (cg_step),hl
        call .between
.lev:   ld hl,cg_v
        call level
        ld b,a
        ld a,(ch_hp)
        or a
        jr z,.put
        push bc
        ld hl,cg_v
        ld de,ch_prev
        call cmp32s
        pop bc
        jr nc,.put
        set 7,b
.put:   ld a,b
.put0:  call rp_byte
        ld hl,cg_x
        inc (hl)
        jp .x
.zero:  xor a
        jr .put0
; .vk: cg_v = pt_v[cg_k], HL = &pt_t[cg_k]
.vk:    ld hl,(cg_k)
        add hl,hl
        add hl,hl
        ld de,pt_t
        add hl,de
        push hl
        ld de,PTS_MAX*4
        add hl,de
        ex de,hl
        ld hl,cg_v
        call cpy32
        pop hl
        ret
; .between: cg_v += (pt_v[k+1] - pt_v[k]) * cg_base / cg_step (towards 0)
.between:
        ld hl,(cg_k)
        add hl,hl
        add hl,hl
        ld de,pt_v
        add hl,de
        push hl
        ld de,4
        add hl,de
        ex de,hl
        ld hl,m_acc
        call cpy32              ; m_acc = v[k+1]
        pop de
        call sub32              ; - v[k]
        call abs32
        push af
        xor a
        ld (m_acc+4),a
        ld (m_acc+5),a
        ld (m_acc+6),a
        ld (m_acc+7),a
        ld hl,m_opb
        ld de,cg_base
        call cpy32
        call mul32
        ld hl,m_opb
        ld de,cg_step
        call cpy32
        call div64
        pop af
        jr nc,.bp
        ld hl,m_acc
        call neg32
.bp:    ld hl,cg_v
        ld de,m_acc
        jp add32

; the price scale: round prices (1, 2, 5 times a power of ten), 3 to 9 of them
cg_yscale:
        ld hl,cg_base
        ld a,1
        call set32
        ld c,0                  ; C = e % 3
.e:     push bc
        ld a,c                  ; step = base * (1, 2, 5)
        ld hl,m125
        call add_hla
        ld a,(hl)
        ld hl,m_opb
        call set32
        ld hl,m_acc
        ld de,cg_base
        call cpy32
        call mul32
        ld hl,cg_step
        ld de,m_acc
        call cpy32
        ld hl,m_acc             ; span / step <= 8?
        ld de,cg_span
        call cpy32
        xor a
        ld (m_acc+4),a
        ld (m_acc+5),a
        ld (m_acc+6),a
        ld (m_acc+7),a
        ld hl,m_opb
        ld de,cg_step
        call cpy32
        call div64
        ld hl,m_acc
        ld de,c8
        call cmp32u
        pop bc
        jr c,.f
        jr z,.f
        ld hl,cg_base           ; (a base of 10^9: the last)
        ld de,c1e9
        call cmp32u
        jr nc,.f
        inc c
        ld a,c
        cp 3
        jr c,.e
        ld c,0
        ld hl,cg_base
        call mul10
        jr .e
.f:     ; the decimals: ch_sc less the step's zeros
        ld hl,m_acc
        ld de,cg_step
        call cpy32
        ld a,(ch_sc)
        ld b,a
        ld c,0
.z:     ld a,c
        cp b
        jr nc,.ze
        ld hl,m_acc
        ld de,m_mp
        ex de,hl
        ld de,m_acc
        call cpy32
        ld hl,m_mp
        call div10
        or a
        jr nz,.ze
        ld hl,m_acc
        ld de,m_mp
        call cpy32
        inc c
        jr .z
.ze:    ld a,b
        sub c
        ld (cg_dec),a
        ; v0 = (lo + step - 1) / step * step
        ld hl,m_acc
        ld de,cg_lo
        call cpy32
        ld de,cg_step
        call add32
        ld hl,m_acc
        ld de,c_one
        call sub32
        xor a
        ld (m_acc+4),a
        ld (m_acc+5),a
        ld (m_acc+6),a
        ld (m_acc+7),a
        ld hl,m_opb
        ld de,cg_step
        call cpy32
        call div64
        call mul32
        ld hl,cg_v
        ld de,m_acc
        call cpy32
        ; how many (v <= hi, at most 9)
        ld hl,cg_tx
        ld de,cg_v
        call cpy32
        ld b,0
.c:     ld a,b
        cp 9
        jr nc,.ce
        ld hl,cg_tx
        ld de,cg_hi
        call cmp32s
        jr z,.cc
        jr nc,.ce
.cc:    inc b
        ld de,cg_step
        call add32
        jr .c
.ce:    ld a,b
        ld (cg_n),a
        call rp_byte
        or a
        ret z
.o:     push bc
        ld hl,cg_v
        call level
        call rp_byte
        ld ix,cg_v
        ld a,(ch_sc)
        ld c,a
        ld a,(cg_dec)
        ld b,a
        xor a
        ld de,cg_txt
        call fmt_num
        ld hl,cg_txt
        call rp_str
        ld hl,cg_v
        ld de,cg_step
        call add32
        pop bc
        djnz .o
        ret
m125:   db 1, 2, 5
c8:     dd 8
c_one:  dd 1

; civil: HL = a time (u32 at HL) -> cv_y, cv_mo, cv_d, cv_h, cv_mi, cv_wd (local),
; cv_days (local days since 1970)
        VAR cv_y, 2
        VAR cv_mo, 1
        VAR cv_d, 1
        VAR cv_h, 1
        VAR cv_mi, 1
        VAR cv_wd, 1
        VAR cv_days, 2
        VAR cv_s, 1
civil:  ld de,m_acc
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
        ld hl,(m_acc)           ; days (UTC)
        push hl
        ld hl,(m_rem)           ; seconds of the day (below 86400: 17 bits)
        ld a,(m_rem+2)
        ; minutes = seconds / 60
        ld (m_acc),hl
        ld (m_acc+2),a
        xor a
        ld (m_acc+3),a
        ld (m_acc+4),a
        ld (m_acc+5),a
        ld (m_acc+6),a
        ld (m_acc+7),a
        ld hl,m_opb
        ld a,60
        call set32
        call div64
        ld a,(m_rem)
        ld (cv_s),a
        ld de,(m_acc)
        pop hl
        call to_local
        ld (cv_days),hl
        push de
        call days_civ
        pop hl
        ld de,60
        call div16              ; HL = hours, DE = minutes
        ld a,l
        ld (cv_h),a
        ld a,e
        ld (cv_mi),a
        ld a,(dc_wd)
        ld (cv_wd),a
        ld hl,(dc_y)
        ld (cv_y),hl
        ld a,(dc_m)
        ld (cv_mo),a
        ld a,(dc_d)
        ld (cv_d),a
        ret
c86400: dd 86400
