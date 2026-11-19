;==============================================================================
; mkeng.asm - the market engine on the MSX: what PicoAmp's engine does on the
; RP2350 (pva_markets.c, engine 0.13), in Z80, on the MSX RSS reader's HTTP
; client (rss_net.asm) through the cartridge's TCP/IP UNAPI. The page
; (markets.asm) sends its commands to eng_cmd as it sends them to the engine.
;
; The prices come from Yahoo Finance's chart service (unofficial, delayed):
;   https://query1.finance.yahoo.com/v8/finance/spark?symbols=A,B,..&range=1d&interval=1d
; up to 20 symbols a request, read as the JSON comes in (no buffer for it).
;
; Differences from the engine: no news reader (MKT_NEWS: not found), the
; members of the indices from MARKETS.CAT on the disk, the settings in
; MARKETS.INI (region=, list=, refresh=, proxy=, tz=).
;==============================================================================

PVA_OK        equ 0
PVA_E_STATE   equ 4
PVA_E_RANGE   equ 5
PVA_E_ARGS    equ 6
PVA_E_NOTFOUND equ 7
PVA_E_UNKNOWN equ 1

ST_IDLE    equ 0
ST_LOADING equ 1
ST_DONE    equ 2
ST_FAILED  equ 3

NERR_NOWIFI  equ 1
NERR_DNS     equ 2
NERR_CONNECT equ 3
NERR_HTTP    equ 4
NERR_TIMEOUT equ 6

ROWS_MAX  equ 100
BATCH     equ 20
PTS_MAX   equ 264
TAPE_MAX  equ 600
MY_MAX    equ 40
QT_SIZE   equ 10                ; price 4, prev 4, have 1, sc 1

Q_NONE   equ 0
Q_QUOTES equ 1
Q_CHART  equ 2
Q_TAPE   equ 3

; fields of a symbol's object
F_FULL  equ 1                   ; fulldayPrice
F_CLOSE equ 2                   ; close
F_CPREV equ 3                   ; chartPreviousClose
F_PREV  equ 4                   ; previousClose
F_TS    equ 5                   ; timestamp
F_START equ 6
F_END   equ 7

        VAR e_region, 1
        VAR e_open, 1           ; the open list (FFh: none)
        VAR e_sub, 1            ; an index's members are open
        VAR e_nrows, 1
        VAR e_state, 1
        VAR e_gen, 1
        VAR e_err, 1
        VAR e_sort, 1
        VAR e_lname, 2          ; the open list's name
        VAR e_have, 1           ; prices came
        VAR e_fnow, 1           ; fetch now
        VAR e_cfirst, 1         ; the request's first row (FFh: no round running)
        VAR e_cn, 1
        VAR e_cgot, 1
        VAR e_stale, 1          ; the request's list was closed meanwhile
        VAR e_q, 1
        VAR e_host, 1
        VAR e_upd, 8            ; "12:53"
        VAR e_updsec, 2
        VAR e_due, 2            ; seconds (e_now) of the next update
        VAR e_retry, 2
        VAR e_refresh, 2
        VAR e_now, 2            ; seconds since the start
        VAR e_jf, 2
        VAR e_jacc, 1
        VAR e_mkrow, 1          ; (the JSON's row)
        VAR rowp, ROWS_MAX*2    ; each row's item: symbol 0, name 0, decimals
        VAR qt, ROWS_MAX*QT_SIZE
        VAR ord, ROWS_MAX
        VAR my_n, 1
        VAR my_items, MY_MAX*33
        VAR mb, 1700            ; the members of an index (from MARKETS.CAT)
        VAR mb_name, 40
        VAR e_url, 300
        ; the chart
        VAR ch_state, 1
        VAR ch_row, 1
        VAR ch_range, 1
        VAR ch_pend, 1
        VAR ch_n, 2
        VAR ch_stride, 2
        VAR ch_start, 4
        VAR ch_end, 4
        VAR ch_prev, 4
        VAR ch_price, 4
        VAR ch_hp, 1
        VAR ch_hpr, 1
        VAR ch_sc, 1
        VAR pt_t, PTS_MAX*4
        VAR pt_v, PTS_MAX*4
        ; the tape
        VAR tp_buf, TAPE_MAX    ; the tape shown
        VAR tp_nb, TAPE_MAX     ; the next one, coming in
        VAR tp_l0, 2            ; its name's length
        VAR tp_k, 1             ; its topic: the index, EUR/USD, gold, US rates, the mover
        VAR tm_b, 1
        VAR tm_x, 4
        VAR tm_y, 4
        VAR tp_len, 2
        VAR tp_new, 2
        VAR tp_pos, 2
        VAR tp_due, 2
        VAR tp_hdue, 1
        VAR tp_region, 1
        VAR tp_st, 1
        VAR tp_tag, 8
        VAR tp_tn, 1
        VAR tp_item, 1
        VAR tp_in, 1
        VAR tp_ent, 8
        VAR tp_en, 1
        VAR tp_cp, 2
        VAR tp_more, 1
        ; the JSON reader
        VAR js_st, 1            ; 0 between, 1 in a string, 2 after a \ in it
        VAR js_dep, 1
        VAR js_stk, 8           ; 'o' / 'a' per depth
        VAR js_ek, 1            ; a key is expected (in an object)
        VAR js_isk, 1           ; the string is a key
        VAR js_key, 24
        VAR js_kn, 1
        VAR js_val, 24
        VAR js_vn, 1
        VAR js_idx, 2           ; the index in an array
        VAR js_row, 1           ; the row of the symbol's object (FFh: none)
        VAR js_fld, 1           ; the field (F_xxx)
        VAR e_t32, 4
        VAR e_t32b, 4

;------------------------------------------------------------------------------
eng_init:
        ld a,#FF
        ld (e_open),a
        ld (e_cfirst),a
        ld (tp_region),a
        xor a
        ld (e_sub),a
        ld (e_nrows),a
        ld (e_sort),a
        ld hl,20
        ld (e_retry),hl
        ld hl,(JIFFY)
        ld (e_jf),hl
        ret

; the seconds go on (from the main loop)
eng_tick:
        ld hl,(JIFFY)
        ld de,(e_jf)
        ld (e_jf),hl
        or a
        sbc hl,de
        ld a,h
        or a
        ld a,l
        jr z,.a
        ld a,255
.a:     ld hl,e_jacc
        add a,(hl)
        jr nc,.n
        ld a,255
.n:     ld (hl),a
.s:     ld a,(hz)
        ld b,a
        ld a,(e_jacc)
        sub b
        ret c
        ld (e_jacc),a
        ld hl,(e_now)
        inc hl
        ld (e_now),hl
        jr .s

; CF: e_now is before the time at HL (seconds)
eng_before:
        ex de,hl
        ld hl,(e_now)
        or a
        sbc hl,de               ; now - t: negative = before
        ld a,h
        rla
        ret

;------------------------------------------------------------------------------
; the rows

; A = row (not sorted) -> HL = its item
row_item:
        ld l,a
        ld h,0
        add hl,hl
        ld de,rowp
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ret
; A = row -> HL = its name (after the symbol)
row_name:
        call row_item
        jp skipz
; A = row -> A = its decimals
row_dec:
        call row_name
        call skipz
        ld a,(hl)
        ret
; A = row -> HL = its quote
row_qt: ld l,a
        ld h,0
        ld e,l
        ld d,h
        add hl,hl
        add hl,hl
        add hl,de
        add hl,hl               ; * 10
        ld de,qt
        add hl,de
        ret
; A = row in the order shown -> A = the row
at:     ld hl,e_nrows
        cp (hl)
        ret nc
        ld hl,ord
        call add_hla
        ld a,(hl)
        ret

; my_add: A = row shown -> A = 0: added to My list, 1: in it already, 2: it is full
my_add: ld hl,e_nrows
        cp (hl)
        ld c,1
        jr nc,.r
        call at
        call row_item           ; HL = its symbol, name, decimals
        push hl
        call my_find
        pop hl
        ld c,1
        jr z,.r
        ld a,(my_n)
        cp MY_MAX
        ld c,2
        jr nc,.r
        push hl
        call my_at
        ex de,hl
        pop hl
        call .cp                ; the symbol
        call .cp                ; the name
        ld a,(hl)               ; the decimals
        ld (de),a
        ld hl,my_n
        inc (hl)
        ld c,0
.r:     ld a,c
        ret
.cp:    ld b,15                 ; at most 15 characters, then 0
.c:     ld a,(hl)
        inc hl
        or a
        jr z,.e
        ld (de),a
        inc de
        djnz .c
.s:     ld a,(hl)
        inc hl
        or a
        jr nz,.s
.e:     ld (de),a
        inc de
        ret

; my_del: A = row shown, when My list is open -> Z: it is removed from My list
my_del: ld hl,(e_lname)
        ld de,txt_mylist
        or a
        sbc hl,de
        ret nz
        call at                 ; A = its place in my_items
        call my_at
        ld d,h                  ; DE = it, HL = the next
        ld e,l
        call my_next
        push hl
        push de
        ld a,(my_n)
        call my_at              ; HL = the end
        pop de
        pop bc
        or a
        sbc hl,bc
        push bc
        ld b,h
        ld c,l
        pop hl
        ld a,b
        or c
        jr z,.z
        ldir
.z:     ld hl,my_n
        dec (hl)
        call close_list         ; (its rows point into the items: opened anew)
        xor a
        ret

; my_at: A = item -> HL = it in my_items (packed: symbol 0, name 0, decimals); A, C
my_at:  ld hl,my_items
        ld c,a
.l:     ld a,c
        or a
        ret z
        call my_next
        dec c
        jr .l
my_next:                        ; HL = an item -> HL = the next; A
        call skipz
        call skipz
        inc hl
        ret

; my_find: HL = symbol -> Z: it is in My list
my_find:
        ld a,(my_n)
        or a
        jr z,.no
        ld b,a
        ld de,my_items
.i:     push hl
        push de
.c:     ld a,(de)
        cp (hl)
        jr nz,.x
        inc hl
        inc de
        or a
        jr nz,.c
        pop de
        pop hl
        ret
.x:     pop de
        pop hl
        ex de,hl
        call my_next
        ex de,hl
        djnz .i
.no:    or 1
        ret

; rowp from a list of items: HL = the first, B = how many
set_rows:
        ld a,b
        ld (e_nrows),a
        or a
        ret z
        ld de,rowp
.l:     ld a,l
        ld (de),a
        inc de
        ld a,h
        ld (de),a
        inc de
        call skipz              ; symbol
        call skipz              ; name
        inc hl                  ; decimals
        djnz .l
        ret

; the rows' order: as the list has them, or by percent (rows without a price last)
        VAR rs_i, 1
        VAR rs_k, 1
        VAR rs_r, 1
        VAR rs_p, 4
        VAR rs_o, 4
        VAR rs_pn, 1
        VAR rs_on, 1
resort: ld a,(e_nrows)
        or a
        ret z
        ld b,a
        ld hl,ord
        xor a
.i:     ld (hl),a
        inc hl
        inc a
        djnz .i
        ld a,(e_sort)
        or a
        ret z
        ld a,1
.o:     ld (rs_i),a
        ld hl,e_nrows
        cp (hl)
        ret nc
        ld hl,ord
        call add_hla
        ld a,(hl)
        ld (rs_r),a
        ld de,rs_p
        call .pct               ; rs_p (A = 1: it has none)
        ld (rs_pn),a
        ld a,(rs_i)
        ld (rs_k),a
.k:     ld a,(rs_k)
        or a
        jr z,.put
        dec a
        ld hl,ord
        call add_hla
        ld a,(hl)
        ld de,rs_o
        call .pct
        ld (rs_on),a
        ; before = p known and (o unknown, or p > o for the risers first, p < o for the fallers)
        ld a,(rs_pn)
        or a
        jr nz,.put
        ld a,(rs_on)
        or a
        jr nz,.mv
        ld hl,rs_p
        ld de,rs_o
        call cmp32s             ; CF: p < o, Z: equal
        jr z,.put
        ld c,0
        jr nc,.ge
        inc c                   ; C = 1: p < o
.ge:    ld a,(e_sort)
        cp 1
        ld a,c
        jr z,.r1
        or a                    ; the fallers first: before when p < o
        jr nz,.mv
        jr .put
.r1:    or a                    ; the risers first: before when p > o
        jr nz,.put
.mv:    ld a,(rs_k)             ; ord[k] = ord[k-1]
        ld hl,ord
        call add_hla
        dec hl
        ld a,(hl)
        inc hl
        ld (hl),a
        ld hl,rs_k
        dec (hl)
        jr .k
.put:   ld a,(rs_k)
        ld hl,ord
        call add_hla
        ld a,(rs_r)
        ld (hl),a
        ld a,(rs_i)
        inc a
        jp .o
; .pct: A = row, DE = where -> its percent there; A = 1 when it has none (else 0)
.pct:   push de
        call row_qt
        push hl
        ld bc,8
        add hl,bc
        ld a,(hl)
        and 3
        cp 3
        pop hl
        pop de
        ld a,1
        ret nz
        push de
        ld d,h
        ld e,l
        inc de
        inc de
        inc de
        inc de
        call pct100
        pop de
        ld hl,n_pct
        ld bc,4
        ldir
        xor a
        ret

;------------------------------------------------------------------------------
; commands: A = command, args, reply (eng_cmd: A = result, Z when PVA_OK, NC)
        VAR rp_ptr, 2
eng_cmd:
        ld hl,reply
        ld (rp_ptr),hl
        ld (hl),0
        sub #46
        jr c,.unk
        cp 11
        jr nc,.unk
        add a,a
        ld hl,.tab
        call add_hla
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        call .go
        ld hl,(rp_ptr)          ; (the reply ends with a 0 as the engine's does)
        ld (hl),0
        or a
        ret
.go:    jp (hl)
.unk:   ld a,PVA_E_UNKNOWN
        or a
        ret
.tab:   dw c_lists, c_region, c_open, c_rows, c_info, c_chart, c_chget, c_members, c_news, c_sort, c_tape

rp_byte:                        ; A to the reply
        push hl
        ld hl,(rp_ptr)
        ld (hl),a
        inc hl
        ld (rp_ptr),hl
        pop hl
        ret
rp_str:                         ; the text at HL with its 0
        ld a,(hl)
        call rp_byte
        inc hl
        or a
        jr nz,rp_str
        ret

; the region's lists: A = n -> HL = its entry (CF: none); region_lists -> B
reg_list:
        ld c,a
        ld hl,cat_lists
.l:     ld a,(hl)
        cp #FF
        scf
        ret z
        ld b,a
        ld a,(e_region)
        cp b
        jr nz,.n
        ld a,c
        or a
        ret z
        dec c
.n:     ld de,6
        add hl,de
        jr .l
reg_count:                      ; B = the region's lists (not My list)
        ld b,0
.l:     ld a,b
        push bc
        call reg_list
        pop bc
        ret c
        inc b
        jr .l

c_lists:
        call reg_count
        push bc
        ld a,(e_region)
        call rp_byte
        ld a,cat_nregions
        call rp_byte
        ld a,(my_n)
        or a
        ld a,b
        jr z,.n
        inc a
.n:     call rp_byte
        ld a,(e_open)
        call rp_byte
        ld hl,cat_regions
        ld a,(e_region)
        call nth
        call rp_str
        pop bc
        ld c,0
.l:     ld a,c
        cp b
        jr nc,.my
        push bc
        call reg_list
        inc hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        call rp_str
        pop bc
        inc c
        jr .l
.my:    ld a,(my_n)
        or a
        jr z,.ok
        ld hl,txt_mylist
        call rp_str
.ok:    xor a
        ret
txt_mylist: db "My list",0

c_region:
        ld a,(args)
        cp #FF
        jr z,.rp
        cp #FE
        jr nz,.s
        ld a,(e_region)
        inc a
        cp cat_nregions
        jr c,.s
        xor a
.s:     cp cat_nregions
        ld b,a
        ld a,PVA_E_RANGE
        ret nc
        ld a,(e_region)
        cp b
        jr z,.rp
        ld a,b
        ld (e_region),a
        call close_list
.rp:    ld a,(e_region)
        call rp_byte
        ld hl,cat_regions
        ld a,(e_region)
        call nth
        call rp_str
        xor a
        ret

close_list:
        ld a,#FF
        ld (e_open),a
        ld (e_cfirst),a
        xor a
        ld (e_sub),a
        ld (e_nrows),a
        ld (e_have),a
        ld (e_state),a
        ld (ch_state),a
        ld (ch_pend),a
        ld (e_upd),a
        ld a,(e_q)
        or a
        ret z
        ld a,1
        ld (e_stale),a
        ret

; a list opens: its rows, no prices yet, fetched at once
open_rows:
        ld hl,qt
        ld de,qt+1
        ld bc,ROWS_MAX*QT_SIZE-1
        ld (hl),0
        ldir
        call resort
        ld a,ST_LOADING
        ld (e_state),a
        xor a
        ld (e_err),a
        ld hl,20
        ld (e_retry),hl
        ld a,1
        ld (e_fnow),a
        ld hl,e_gen
        inc (hl)
        ld a,(e_nrows)
        call rp_byte
        xor a
        ret

c_open: ld a,(args)
        cp #FF
        jr nz,.o
        call close_list
        xor a
        call rp_byte
        xor a
        ret
.o:     ld c,a
        cp #FD                  ; NOW: what is open, again now
        jr nz,.n
        ld a,(e_open)
        cp #FF
        jr z,.n
        ld a,(e_sub)
        or a
        jr nz,.again
        ld a,(e_open)
        ld c,a
.n:     ld a,(e_open)           ; the same one again: its prices now
        cp c
        jr nz,.new
        ld a,(e_sub)
        or a
        jr nz,.new
        ld a,(e_nrows)
        or a
        jr z,.new
.again: ld a,1
        ld (e_fnow),a
        ld a,(e_nrows)
        call rp_byte
        xor a
        ret
.new:   call reg_count          ; B = the region's lists (C kept)
        ld a,c
        cp b
        jr c,.list
        jr nz,.range
        ld a,(my_n)             ; My list
        or a
        jr z,.range
        push bc
        call close_list
        pop bc
        ld a,c
        ld (e_open),a
        ld hl,txt_mylist
        ld (e_lname),hl
        ld hl,my_items
        ld a,(my_n)
        ld b,a
        call set_rows
        jp open_rows
.range: ld a,PVA_E_RANGE
        ret
.list:  push bc
        call close_list
        pop bc
        ld a,c
        ld (e_open),a
        call reg_list
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld (e_lname),de
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld b,(hl)
        ex de,hl
        call set_rows
        jp open_rows

; the members of the index in row r, from MARKETS.CAT
c_members:
        ld a,(e_open)
        cp #FF
        ld a,PVA_E_STATE
        ret z
        ld a,(e_sub)
        or a
        ld a,PVA_E_STATE
        ret nz
        ld a,(args)
        ld hl,e_nrows
        cp (hl)
        ld a,PVA_E_RANGE
        ret nc
        ld a,(args)
        call at
        call row_item           ; HL = its symbol
        call cat_members        ; mb, mb_name, B = count; CF: none
        ld a,PVA_E_NOTFOUND
        ret c
        push bc
        ld a,(e_open)
        push af
        call close_list
        pop af
        ld (e_open),a
        ld a,1
        ld (e_sub),a
        ld hl,mb_name
        ld (e_lname),hl
        pop bc
        ld hl,mb
        call set_rows
        jp open_rows

c_news: ld a,PVA_E_NOTFOUND     ; (no news reader here)
        ret

c_sort: ld a,(args)
        cp #FF
        jr z,.r
        cp 3
        ld a,PVA_E_RANGE
        ret nc
        ld a,(args)
        ld (e_sort),a
        call resort
        ld hl,e_gen
        inc (hl)
.r:     ld a,(e_sort)
        call rp_byte
        xor a
        ret

c_tape: ld hl,(tp_len)          ; 80 characters from tp_pos, and one on
        ld de,40
        or a
        sbc hl,de
        jr c,.none
        ld a,(tp_region)
        ld hl,e_region
        cp (hl)
        jr nz,.none
        ld hl,(tp_len)          ; the period: the tape and " +++ "
        ld de,5
        add hl,de
        ex de,hl                ; DE = period
        ld hl,(tp_pos)
        or a
        sbc hl,de
        add hl,de
        jr c,.p
        ld hl,0
.p:     ld (tp_pos),hl          ; (wrapped: kept, else the tape stops)
        ld b,80
.c:     push bc
        push hl
        ld bc,(tp_len)
        or a
        sbc hl,bc
        jr nc,.sep
        add hl,bc
        ld bc,tp_buf
        add hl,bc
        ld a,(hl)
        jr .put
.sep:   ld bc,txt_sep
        add hl,bc
        ld a,(hl)
.put:   call rp_byte
        pop hl
        inc hl
        or a                    ; HL = (HL + 1) mod period
        sbc hl,de
        add hl,de
        jr c,.w
        ld hl,0
.w:     pop bc
        djnz .c
        ld hl,(tp_pos)
        inc hl
        ld (tp_pos),hl
        xor a
        call rp_byte
        xor a
        ret
.none:  xor a
        call rp_byte
        xor a
        ret
txt_sep: db " +++ "

; the rows: u8 rows, u8 here, per row u8 direction and 39 characters with a 0
        VAR cr_first, 1
        VAR cr_n, 1
c_rows: ld a,(e_open)
        cp #FF
        ld a,PVA_E_STATE
        ret z
        ld a,(e_nrows)
        ld b,a
        ld a,(args)
        cp b
        jr c,.f
        ld a,b
.f:     ld (cr_first),a
        ld c,a
        ld a,b
        sub c                   ; at most what is left, and 40
        ld c,a
        ld a,(args+1)
        cp c
        jr c,.n
        ld a,c
.n:     cp 41
        jr c,.n2
        ld a,40
.n2:    ld (cr_n),a
        ld a,b
        call rp_byte
        ld a,(cr_n)
        call rp_byte
        or a
        ret z
        ld b,a
        ld a,(cr_first)
.r:     push bc
        push af
        call at
        call row_text           ; A = direction, text in rt_buf
        call rp_byte
        ld hl,rt_buf
        call rp_str
        pop af
        inc a
        pop bc
        djnz .r
        xor a
        ret

; row_text: A = row -> A = '+' '-' ' ' '?', rt_buf: name 14, price 10, change 8, percent 7
        VAR rt_buf, 44
        VAR rt_p, 24
        VAR rt_c, 24
        VAR rt_pc, 16
        VAR rt_row, 1
        VAR rt_dir, 1
row_text:
        ld (rt_row),a
        ld a,'-'
        ld (rt_p),a
        xor a
        ld (rt_p+1),a
        ld (rt_c),a
        ld (rt_pc),a
        ld a,'?'
        ld (rt_dir),a
        ld a,(rt_row)
        call row_qt
        push hl
        pop ix                  ; IX = the quote
        ld a,(ix+8)
        and 1
        jr z,.txt
        ld a,(rt_row)
        call row_dec
        ld b,a
        ld c,(ix+9)
        ld de,rt_p
        xor a
        push ix
        call fmt_num            ; (fmt_num keeps IX? it uses it: kept)
        pop ix
        ld a,' '
        ld (rt_dir),a
        ld a,(ix+8)
        and 2
        jr z,.txt
        push ix                 ; the percent
        pop hl
        push hl
        pop de
        inc de
        inc de
        inc de
        inc de
        call pct100
        ld de,rt_pc
        call fmt_pct
        ld hl,e_t32             ; the change: price - prev
        push ix
        pop de
        call cpy32
        push ix
        pop de
        inc de
        inc de
        inc de
        inc de
        call sub32
        ld a,(rt_row)
        call row_dec
        ld b,a
        ld c,(ix+9)
        ld de,rt_c
        ld a,1
        push ix
        ld ix,e_t32
        call fmt_num
        pop ix
        ld hl,n_pct
        call tst32
        ld a,' '
        jr z,.d
        ld a,'+'
        jr nc,.d
        ld a,'-'
.d:     ld (rt_dir),a
.txt:   ld a,(rt_row)           ; "%-14.14s%10.10s%8.8s%7.7s"
        call row_name           ; (row_name uses DE)
        ld de,rt_buf
        ld b,14
        call put_left
        ld hl,rt_p
        ld b,10
        call put_right
        ld hl,rt_c
        ld b,8
        call put_right
        ld hl,rt_pc
        ld b,7
        call put_right
        xor a
        ld (de),a
        ld a,(rt_dir)
        ret
; put_left: HL = text, B = width: at most B of it, spaces after (DE on)
put_left:
.c:     ld a,(hl)
        or a
        jr z,.p
        ld (de),a
        inc hl
        inc de
        djnz .c
        ret
.p:     ld a,' '
.s:     ld (de),a
        inc de
        djnz .s
        ret
; put_right: HL = text, B = width: "%B.Bs" (cut to B characters, spaces before)
put_right:
        push hl
        ld c,0
.l:     ld a,(hl)
        or a
        jr z,.e
        inc hl
        inc c
        jr .l
.e:     pop hl
        ld a,c
        cp b
        jr nc,.cp               ; as long as the width or longer: its first B
        ld a,b
        sub c
        ld b,a
        ld a,' '
.s:     ld (de),a
        inc de
        djnz .s
        ld a,c
        or a
        ret z
        ld b,c
.cp:    ld a,(hl)
        ld (de),a
        inc hl
        inc de
        djnz .cp
        ret

; info: state, rows, u16 seconds since the update, the list's name, the region's, "12:53"
c_info: ld a,(e_open)
        cp #FF
        ld a,PVA_E_STATE
        ret z
        ld a,(e_state)
        call rp_byte
        ld a,(e_nrows)
        call rp_byte
        ld hl,#FFFF
        ld a,(e_have)
        or a
        jr z,.a
        ld hl,(e_now)
        ld de,(e_updsec)
        or a
        sbc hl,de
.a:     ld a,l
        call rp_byte
        ld a,h
        call rp_byte
        ld hl,(e_lname)
        call rp_str
        ld hl,cat_regions
        ld a,(e_region)
        call nth
        call rp_str
        ld hl,e_upd
        call rp_str
        xor a
        ret

c_chart:
        ld a,(e_open)
        cp #FF
        ld a,PVA_E_STATE
        ret z
        ld a,(args)
        ld hl,e_nrows
        cp (hl)
        ld a,PVA_E_RANGE
        ret nc
        ld a,(args)
        call at
        ld (ch_row),a
        ld a,(args+1)
        cp 8
        jr c,.r
        xor a
.r:     ld (ch_range),a
        ld a,ST_LOADING
        ld (ch_state),a
        ld a,1
        ld (ch_pend),a
        xor a
        ret

;------------------------------------------------------------------------------
; the requests (from the main loop): one at a time
eng_poll:
        call http_busy
        ret nz
        ld a,(e_open)
        cp #FF
        ret z
        ld a,(un_type)          ; (no network)
        or a
        ret z
        ld a,(ch_pend)
        or a
        jr z,.nc
        xor a
        ld (ch_pend),a
        jp start_chart
.nc:    ld a,(e_cfirst)         ; the list's next symbols
        cp #FF
        jr z,.nm
        ld hl,e_nrows
        cp (hl)
        jp c,start_quotes
.nm:    ld a,(e_nrows)          ; due?
        or a
        jr z,.tp
        ld a,(e_fnow)
        or a
        jr nz,.due
        ld hl,(e_due)
        call eng_before
        jr c,.tp
.due:   xor a
        ld (e_fnow),a
        ld (e_cfirst),a
        jp start_quotes
.tp:    ld a,(tp_region)        ; the tape: after the prices
        ld hl,e_region
        cp (hl)
        jr z,.tq
        ld hl,0
        ld (tp_len),hl
        xor a
        ld (tp_k),a
        jp start_tape
.tq:    ld a,(tp_hdue)
        or a
        jp z,start_tape
        ld hl,(tp_due)
        call eng_before
        ret c
        jp start_tape

; the URL: the host's part, then the symbols
txt_h1: db "https://query1.finance.yahoo.com/v8/finance/spark?symbols=",0
txt_h2: db "https://query2.finance.yahoo.com/v8/finance/spark?symbols=",0
txt_r1: db "&range=1d&interval=1d",0
url_head:
        ld hl,txt_h1
        ld a,(e_host)
        or a
        jr z,.h
        ld hl,txt_h2
.h:     ld de,e_url
        jp strcpy
; put_sym: the symbol at HL to DE as a URL takes it ("%5EAEX"), DE on the end, B = its length
put_sym:
        ld b,0
.c:     ld a,(hl)
        or a
        jr z,.e
        inc hl
        cp '0'
        jr c,.esc
        cp '9'+1
        jr c,.pl
        cp 'A'
        jr c,.esc
        cp 'Z'+1
        jr c,.pl
        cp 'a'
        jr c,.u
        cp 'z'+1
        jr c,.pl
        jr .esc
.u:     cp '_'
        jr z,.pl
        jr .esc
.pl:    ld (de),a
        inc de
        inc b
        jr .c
.esc:   cp '.'
        jr z,.pl
        cp '-'
        jr z,.pl
        ld c,a
        ld a,'%'
        ld (de),a
        inc de
        ld a,c
        rrca
        rrca
        rrca
        rrca
        call .hx
        ld a,c
        call .hx
        inc b
        inc b
        inc b
        jr .c
.e:     xor a
        ld (de),a
        ret
.hx:    and 15
        add a,'0'
        cp '9'+1
        jr c,.h
        add a,7
.h:     ld (de),a
        inc de
        ret

        VAR sq_len, 1
start_quotes:
        call url_head           ; DE at the end
        xor a
        ld (e_cn),a
        ld (e_cgot),a
        ld (sq_len),a
.k:     ld a,(e_cn)
        cp BATCH
        jr nc,.end
        ld b,a
        ld a,(e_cfirst)
        add a,b
        ld hl,e_nrows
        cp (hl)
        jr nc,.end
        push de
        call row_item
        ld de,js_key            ; (as a scratch: the symbol escaped)
        call put_sym
        pop de
        ld a,(sq_len)           ; room? (the path at most 255: symbols at most 200)
        add a,b
        inc a
        jr c,.end
        cp 200
        jr nc,.end
        ld (sq_len),a
        ld a,(e_cn)
        or a
        jr z,.f
        ld a,','
        ld (de),a
        inc de
.f:     ld hl,js_key
        call strcpy
        ld hl,e_cn
        inc (hl)
        jr .k
.end:   ld hl,txt_r1
        call strcpy
        ld a,Q_QUOTES
        jp start_req

txt_rg: db "&range=1d&interval=15m",0, "&range=5d&interval=60m",0, "&range=1mo&interval=1d",0
        db "&range=6mo&interval=1d",0, "&range=ytd&interval=1d",0, "&range=1y&interval=1d",0
        db "&range=5y&interval=1wk",0, "&range=max&interval=1mo",0
start_chart:
        call url_head
        push de
        ld a,(ch_row)
        call row_item           ; (it uses DE)
        pop de
        call put_sym
        ld hl,txt_rg
        ld a,(ch_range)
        call nth
        call strcpy
        ld hl,0
        ld (ch_n),hl
        inc hl
        ld (ch_stride),hl
        ld hl,ch_start
        call zero32
        ld hl,ch_end
        call zero32
        xor a
        ld (ch_hp),a
        ld (ch_hpr),a
        dec a
        ld (ch_sc),a
        ld a,ST_LOADING
        ld (ch_state),a
        ld a,Q_CHART
        call start_req
        ret nc
        ld a,ST_FAILED
        ld (ch_state),a
        ld a,NERR_NOWIFI
        ld (e_err),a
        ret

; (Yahoo's search, on the API's host: its RSS feeds send EU visitors to a consent page)
txt_tape: db "https://query1.finance.yahoo.com/v1/finance/search?quotesCount=0&newsCount=10&q=",0
txt_tp0:  db "%5ESTOXX50E",0      ; (its news needs a symbol: a text finds none)
txt_tp1:  db "%5EGSPC",0
txt_tp2:  db "%5EN225",0
txt_tq:   db "EURUSD%3DX",0,"EUR/USD",0, "GC%3DF",0,"Gold",0, "%5ETNX",0,"US 10-year yield",0
txt_colon: db ": ",0

; tp_str: the text at HL to the tape
tp_str: ld a,(hl)
        or a
        ret z
        call tp_put
        inc hl
        jr tp_str

; tp_mover: the row of the open list with the largest change (in %) -> A (CF: none)
tp_mover:
        ld a,#FF
        ld (tm_b),a
        ld hl,tm_x
        call zero32
        ld a,(e_nrows)
.l:     or a
        jr z,.e
        dec a
        push af
        ld de,tm_y
        call resort.pct
        or a
        jr nz,.n
        ld hl,tm_y
        call abs32
        ld de,tm_x
        call cmp32u
        jr c,.n
        call cpy32x
        pop af
        ld (tm_b),a
        jr .l
.n:     pop af
        jr .l
.e:     ld a,(tm_b)
        cp #FF
        ccf
        ret
cpy32x: ex de,hl                ; tm_x = tm_y
        jp cpy32
txt_tpf:  db "  No headlines from Yahoo (network error ",0
txt_tph:  db ", HTTP ",0
start_tape:
        ld hl,tp_st             ; the reader from the start
        ld b,tp_more-tp_st+1
.z:     ld (hl),0
        inc hl
        djnz .z
        ld hl,0
        ld (tp_new),hl
        ld a,(e_region)
        ld (tp_region),a
        ld hl,txt_tape
        ld de,e_url
        call strcpy
        ld a,(tp_k)             ; the topic's query, and its name to the tape
        cp 4
        jr z,.mv
        or a
        jr nz,.fx
        ld a,(e_region)         ; 0: the region's index
        push af
        ld hl,txt_tp0
        call nth
        call strcpy
        pop af
        ld hl,cat_regions
        call nth
        jr .lb
.fx:    dec a                   ; 1-3: EUR/USD, gold, US rates
        add a,a
        ld hl,txt_tq
        call nth
        call strcpy
        inc hl
        jr .lb
.mv:    push de                 ; 4: the row of the open list that moves most
        call tp_mover
        jr nc,.m1
        pop de
        xor a
        ld (tp_k),a
        jr start_tape
.m1:    push af
        call row_item           ; (DE: both use it)
        pop af
        pop de
        push af
        call put_sym
        xor a
        ld (de),a
        pop af
        call row_name
.lb:    call tp_str
        ld hl,txt_colon
        call tp_str
        ld hl,(tp_new)
        ld (tp_l0),hl
        ld hl,e_url
        ld de,tp_body
        ld bc,fetch_done
        ld a,Q_TAPE
        ld (e_q),a
        call http_get
        ret nc
        xor a
        ld (e_q),a
        ld a,1
        ld (tp_hdue),a
        ld hl,(e_now)
        ld de,300
        add hl,de
        ld (tp_due),hl
        ret

; start_req: A = Q_xxx, the URL in e_url: CF not started
start_req:
        ld (e_q),a
        xor a                   ; the JSON reader from the start
        ld (js_st),a
        ld (js_dep),a
        ld (js_ek),a
        ld (js_vn),a
        ld (js_kn),a
        ld a,#FF
        ld (js_row),a
        ld (e_mkrow),a
        ld hl,e_url
        ld de,js_body
        ld bc,fetch_done
        call http_get
        ret nc
        xor a
        ld (e_q),a
        scf
        ret

; the error of the request (net_err -> PVA_NERR_xxx)
net_nerr:
        ld a,(net_err)
        cp 4
        ld a,NERR_TIMEOUT
        ret z
        ld a,(net_err)
        cp 4
        ret c                   ; 1 2 3: no network, DNS, connect: as they are
        ld a,NERR_HTTP
        ret

; fetch_done: CF = failed
fetch_done:
        ld c,0                  ; C = 1: failed
        jr nc,.k
        inc c
.k:     ld a,(e_q)
        ld b,a
        xor a
        ld (e_q),a
        ld a,b
        cp Q_TAPE
        jr nz,.nt
        xor a
        ld (e_stale),a
        inc a
        ld (tp_hdue),a
        ld a,c
        or a
        jr nz,.tf
        ld hl,(tp_new)
        ld de,21
        sbc hl,de
        jr c,.tf
.tl:    ld hl,tp_k              ; the next topic
        inc (hl)
        ld a,(hl)
        cp 5
        jr c,.tk
        ld (hl),0
.tk:    ld hl,tp_nb             ; the new tape in place
        ld de,tp_buf
        ld bc,(tp_new)
        ld a,b
        or c
        jr z,.t0
        ldir
.t0:    ld de,120               ; again in 2 minutes
        ld hl,(tp_new)
        ld (tp_len),hl
        ld hl,0
        ld (tp_pos),hl
        ld hl,(e_now)
        add hl,de
        ld (tp_due),hl
        ret
.tf:    ld hl,0                 ; none: why, on the tape (again in 5 minutes)
        ld (tp_new),hl
        ld hl,txt_tpf
        call tp_str
        ld a,(net_err)
        ld l,a
        ld h,0
        call .tn
        ld hl,txt_tph
        call tp_str
        ld hl,(h_status)
        call .tn
        ld a,')'
        call tp_put
        jr .tl
.tn:    ld de,e_url
        push de
        call r_fmt_u16
        xor a
        ld (de),a
        pop hl
        jp tp_str
.nt:    ld a,(e_stale)
        or a
        jr z,.ns
        xor a
        ld (e_stale),a
        ret
.ns:    ld a,b
        cp Q_CHART
        jr nz,.nq
        dec c
        jr z,.chf               ; (failed)
        call pts_pack
        ld hl,(ch_n)
        ld a,h
        or l
        jr z,.che
        ld a,ST_DONE
        ld (ch_state),a
        ret
.che:   ld a,ST_FAILED
        ld (ch_state),a
        ld a,NERR_HTTP
        ld (e_err),a
        ret
.chf:   ld a,ST_FAILED
        ld (ch_state),a
        call net_nerr
        ld (e_err),a
        ld hl,e_host
        ld a,(hl)
        xor 1
        ld (hl),a
        ret
.nq:    cp Q_QUOTES
        ret nz
        dec c
        jr z,.qf
        ld a,(e_cgot)
        or a
        jr z,.qf0
        ld a,(e_cfirst)         ; the next ones (the poll), or all came
        ld hl,e_cn
        add a,(hl)
        ld (e_cfirst),a
        ld hl,e_nrows
        cp (hl)
        ret c
        ld a,1
        ld (e_have),a
        ld a,ST_DONE
        ld (e_state),a
        xor a
        ld (e_err),a
        ld hl,20
        ld (e_retry),hl
        call resort
        ld hl,e_gen
        inc (hl)
        call stamp
        ld hl,(e_now)
        ld de,(e_refresh)
        add hl,de
        ld (e_due),hl
        ld a,#FF
        ld (e_cfirst),a
        ret
.qf0:   or a                    ; (the reply had none of them: as HTTP failed)
        ld a,NERR_HTTP
        jr .qe
.qf:    call net_nerr
.qe:    ld (e_err),a
        ld hl,e_host
        ld a,(hl)
        xor 1
        ld (hl),a
        ld a,(e_have)
        or a
        jr nz,.qh
        ld a,ST_FAILED
        ld (e_state),a
.qh:    ld hl,e_gen
        inc (hl)
        ld a,#FF
        ld (e_cfirst),a
        ld hl,(e_now)
        ld de,(e_retry)
        add hl,de
        ld (e_due),hl
        ld hl,(e_retry)         ; twice as long next time, at most 5 minutes
        ld de,300
        or a
        sbc hl,de
        ret nc
        ld hl,(e_retry)
        add hl,hl
        ld (e_retry),hl
        ret

; stamp: "12:53" (the local time) and the second of the update
stamp:  ld hl,(e_now)
        ld (e_updsec),hl
        xor a
        ld (e_upd),a
        call clk_local          ; HL = days, DE = minutes
        ret c
        ex de,hl
        ld de,e_upd
        call fmt_hm
        xor a
        ld (de),a
        ret
