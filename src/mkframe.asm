;==============================================================================
; mkframe.asm - what PicoAmp's player gives its market page (markets.asm),
; here on its own: the VDP's names, the font, the palette, text helpers,
; 'cmd' to the engine (mkeng*.asm, in this program), the clock block, the
; settings in MARKETS.INI, and the main loop.
;==============================================================================

RG1SAV  equ #F3E0
RG8SAV  equ #FFE7
RG9SAV  equ #FFE8
VDP_C   equ #99
VDP_P   equ #9A
CGTABL  equ #0004
WHITE   equ 5
GREEN   equ 8
RED     equ 11
NAVY    equ 14
PG_CLOCK   equ 1
PG_WEATHER equ 2
PG_NEWS    equ 3
C_NLIST    equ #3A
CK_SEQ   equ 0
CK_FLAGS equ 1
CK_SEC   equ 2
CK_NST   equ 32
CK_NCOUNT equ 33
CK_NFEED equ 34
CKF_TIME equ 1

        VAR args, 8
        VAR reply, 900
        VAR ckb, 48
        VAR font, 96*8
        VAR pg_t0, 64
        VAR quit, 1
        VAR ck_lmin, 2

; palette: 16 x (0RRR0BBB, 00000GGG), PicoAmp's; and the MSX's for colours 0-3
palette:        db #00,#00, #00,#00, #13,#01, #26,#02, #37,#06, #77,#07, #45,#04, #01,#04
                db #22,#07, #71,#07, #70,#04, #71,#01, #66,#02, #23,#02, #02,#00, #56,#05
palette_msx:    db #00,#00, #00,#00, #11,#06, #33,#07

eng_minor:      db 13
mk_ksel:        db 0
mk_ksub:        db #FF
mk_last:        db 0
nw_ext:         db 0
fmt_started:    db 0

; strcpy: HL -> DE, DE on the 0 (HL on it too) (PicoAmp's)
strcpy: ld a,(hl)
        ld (de),a
        or a
        ret z
        inc hl
        inc de
        jr strcpy

; fmt_u16: HL in decimal to DE, DE on the 0 after it (PicoAmp's)
fmt_u16:
        push bc
        xor a
        ld (fmt_started),a
        ld bc,10000
        call .digit
        ld bc,1000
        call .digit
        ld bc,100
        call .digit
        ld bc,10
        call .digit
        ld a,l
        add a,'0'
        ld (de),a
        inc de
        xor a
        ld (de),a
        pop bc
        ret
.digit: ld a,'0'-1
.d:     inc a
        or a
        sbc hl,bc
        jr nc,.d
        add hl,bc
        cp '0'
        jr nz,.w
        push af
        ld a,(fmt_started)
        or a
        jr nz,.w1
        pop af
        ret
.w1:    pop af
.w:     ld (de),a
        inc de
        ld a,1
        ld (fmt_started),a
        ret

; the engine's commands (as PicoAmp's cmd: NC, Z when PVA_OK, A = result)
cmd:    jp eng_cmd
cmd0:   jp eng_cmd
cmd_u8: push af
        ld a,e
        ld (args),a
        pop af
        jp eng_cmd

; the page leaves: ESC / $ end the program; C, W, T: not here
fs_close:
        ld a,1
        ld (quit),a
        ret
pg_enter:
keys_common:
        ret

; row 0: what PicoAmp plays; here the program and the network
pg_row0_text:
        ld de,pg_t0
        ld hl,txt_row0
        call strcpy
        ld hl,un_name
        ld a,(hl)
        or a
        jr z,.e
        ld a,' '
        ld (de),a
        inc de
        ld a,'('
        ld (de),a
        inc de
        call strcpy
        ld a,')'
        ld (de),a
        inc de
        xor a
        ld (de),a
.e:     ld hl,pg_t0
        ret
txt_row0: db "Markets for the MSX Pico+",0

; back to BASIC's screen: its colours 0-3, a text screen
screen_init:
        di
        xor a
        out (VDP_C),a
        ld a,#80+16
        out (VDP_C),a
        ld hl,palette_msx
        ld b,8
.p:     ld a,(hl)
        out (VDP_P),a
        inc hl
        djnz .p
        ei
        jp INITXT

; the font: the machine's, a dot to the right (it is drawn in 6-dot cells)
font_init:
        ld hl,(CGTABL)
        ld de,32*8
        add hl,de
        ld de,font
        ld bc,96*8
.f:     ld a,(hl)
        srl a
        ld (de),a
        inc hl
        inc de
        dec bc
        ld a,b
        or c
        jr nz,.f
        ret

; the clock block: the local time (when known), the markets' state
ck_fill:
        ld a,(e_state)
        ld (ckb+CK_MST),a
        ld a,(e_gen)
        ld (ckb+CK_MGEN),a
        ld a,(ch_state)
        ld (ckb+CK_MCH),a
        ld a,(e_err)
        ld (ckb+CK_MERR),a
        ld a,(clk_sec)
        ld (ckb+CK_SEC),a
        call clk_local          ; HL = days, DE = minutes (CF: not known)
        ld a,0
        jr c,.f
        push hl
        ld hl,(ck_lmin)         ; (the date only when the minute changed)
        or a
        sbc hl,de
        pop hl
        ld a,CKF_TIME
        jr z,.f
        ld (ck_lmin),de
        push de
        call days_civ
        pop hl
        ld de,60
        call div16
        ld a,e
        ld (ckb+CK_SEC+1),a
        ld a,l
        ld (ckb+CK_SEC+2),a
        ld a,(dc_wd)
        ld (ckb+CK_SEC+3),a
        ld a,(dc_d)
        ld (ckb+CK_SEC+4),a
        ld a,(dc_m)
        ld (ckb+CK_SEC+5),a
        ld a,CKF_TIME
.f:     ld (ckb+CK_FLAGS),a
        ret

;------------------------------------------------------------------------------
; MARKETS.INI: region=europe|americas|asia, list=ASML.AS,AAPL,BTC-EUR,
; refresh=60 (seconds), proxy=host:port, tz=+60 (minutes)
INI_MAX equ 400
        VAR ini_buf, INI_MAX+1
        VAR ini_len, 2
txt_ininame: db "MARKETS INI"
txt_k_region:  db "region=",0
txt_k_list:    db "list=",0
txt_k_refresh: db "refresh=",0
txt_k_proxy:   db "proxy=",0
txt_k_tz:      db "tz=",0

ini_load:
        ld hl,60
        ld (e_refresh),hl
        xor a
        ld (ini_buf),a
        ld (my_n),a
        ld hl,0
        ld (ini_len),hl
        ld de,txt_ininame
        call dk_open
        jr c,.none
        ld hl,0
        ld de,ini_buf
        ld bc,INI_MAX
        call dk_read
        push hl
        call dk_close
        pop hl
        ld (ini_len),hl
        ld de,ini_buf
        add hl,de
        ld (hl),0
        ld hl,ini_buf           ; (an EOF mark ends it)
.e:     ld a,(hl)
        or a
        jr z,.none
        cp #1A
        jr z,.z
        inc hl
        jr .e
.z:     ld (hl),0
        ld de,ini_buf
        or a
        sbc hl,de
        ld (ini_len),hl
.none:  ; region=
        ld de,txt_k_region
        call ini_find
        jr nz,.nr
        ld c,0
        ld de,cat_codes
.rc:    ld a,c
        cp cat_nregions
        jr nc,.nr
        push hl
        push de
.rcc:   ld a,(de)
        or a
        jr z,.rce
        cp (hl)
        jr nz,.rcn
        inc hl
        inc de
        jr .rcc
.rce:   ld a,(hl)               ; (the code ends there too)
        cp ' '+1
        jr nc,.rcn
        pop de
        pop hl
        ld a,c
        ld (e_region),a
        jr .nr
.rcn:   pop de
        pop hl
        ex de,hl
        call skipz
        ex de,hl
        inc c
        jr .rc
.nr:    ; refresh=
        ld de,txt_k_refresh
        call ini_find
        jr nz,.nf
        call num
        ld hl,20
        or a
        sbc hl,de
        jr c,.f1
        ld de,20
.f1:    ld hl,3600
        or a
        sbc hl,de
        jr nc,.f2
        ld de,3600
.f2:    ld (e_refresh),de
.nf:    ; tz=
        ld de,txt_k_tz
        call ini_find
        jr nz,.nt
        ld a,(hl)
        cp '-'
        push af
        jr z,.tm
        cp '+'
        jr nz,.tn
.tm:    inc hl
.tn:    call num
        ex de,hl
        pop af
        call z,neg_hl
        ld (tz_min),hl
        ld a,1
        ld (tz_set),a
.nt:    ; proxy=host:port
        ld de,txt_k_proxy
        call ini_find
        jr nz,.np
        ld de,prx_host
        ld b,HOST_MAX
.ph:    ld a,(hl)
        cp ':'
        jr z,.pe
        cp ' '+1
        jr c,.pe
        ld (de),a
        inc hl
        inc de
        djnz .ph
.pe:    xor a
        ld (de),a
        ld de,8080
        ld a,(hl)
        cp ':'
        jr nz,.pn
        inc hl
        call num
.pn:    ld (prx_port),de
.np:    ; list=: My list
        ld de,txt_k_list
        call ini_find
        ret nz
        ld de,my_items
        ld c,0                  ; C = symbols
.sym:   ld a,c
        cp MY_MAX
        jr nc,.end
.sk:    ld a,(hl)               ; separators: , space ;
        cp ','
        jr z,.s1
        cp ' '
        jr z,.s1
        cp ';'
        jr nz,.s2
.s1:    inc hl
        jr .sk
.s2:    cp ' '
        jr c,.end               ; (the line's end)
        push de                 ; the symbol, upper case, at most 15
        ld b,0
.sc:    ld a,(hl)
        cp ' '+1
        jr c,.se
        cp ','
        jr z,.se
        cp ';'
        jr z,.se
        cp 'a'
        jr c,.up
        cp 'z'+1
        jr nc,.up
        sub 32
.up:    ld (de),a
        inc hl
        inc de
        inc b
        ld a,b
        cp 16
        jr c,.sc
        pop de                  ; (too long: left out)
.skp:   ld a,(hl)
        cp ' '+1
        jr c,.sym
        cp ','
        jr z,.sym
        inc hl
        jr .skp
.se:    xor a
        ld (de),a
        inc de
        ex (sp),hl              ; HL = its start: the name is the symbol again
        push bc
.cn:    ld a,(hl)
        ld (de),a
        inc hl
        inc de
        or a
        jr nz,.cn
        pop bc
        ; decimals: 4 for a currency pair ("=X" at the end), else 2
        dec de                  ; DE on the name's 0
        push de
        dec de
        ld a,(de)
        cp 'X'
        jr nz,.d2
        dec de
        ld a,(de)
        cp '='
        jr nz,.d2
        ld a,4
        jr .d
.d2:    ld a,2
.d:     pop de
        inc de
        ld (de),a
        inc de
        pop hl
        inc c
        jr .sym
.end:   ld a,c
        ld (my_n),a
        ret

; ini_find: DE = "key=" -> HL after it (Z), on a line's start
ini_find:
        ld hl,ini_buf
.line:  ld a,(hl)
        or a
        jr z,.no
        push hl
        push de
.c:     ld a,(de)
        or a
        jr z,.yes
        cp (hl)
        jr nz,.nx
        inc hl
        inc de
        jr .c
.yes:   pop de
        pop af                  ; (the line's start)
        xor a
        ret
.nx:    pop de
        pop hl
.n:     ld a,(hl)               ; the next line
        or a
        jr z,.no
        inc hl
        cp 10
        jr nz,.n
        jr .line
.no:    or 1
        ret

; ini_save: MARKETS.INI again, region= and list= as they are now (the other lines
; as they were); it is put together in the page's work area (the page has gone)
ini_out equ vizbuf
        ASSERT INI_MAX+80+MY_MAX*16 <= 2304
ini_save:
        ld de,ini_out
        ld hl,ini_buf
.l:     ld a,(hl)
        or a
        jr z,.add
        ld bc,txt_k_region      ; region= and list= lines: left out (written at the end)
        call .is
        jr z,.sk
        ld bc,txt_k_list
        call .is
        jr nz,.cp
.sk:    ld a,(hl)
        or a
        jr z,.add
        inc hl
        cp 10
        jr nz,.sk
        jr .l
.cp:    ld a,(hl)               ; another line: as it is
        or a
        jr z,.add
        ld (de),a
        inc hl
        inc de
        cp 10
        jr nz,.cp
        jr .l
.add:   ld hl,txt_k_region
        call strcpy
        ld hl,cat_codes
        ld a,(e_region)
        call nth
        call strcpy
        call .crlf
        ld a,(my_n)
        or a
        jr z,.len
        ld b,a
        ld hl,txt_k_list
        call strcpy
        ld hl,my_items
.my:    push bc
        call strcpy             ; the symbol (HL on its 0)
        ld a,','
        ld (de),a
        inc de
        inc hl
        call skipz              ; its name and decimals
        inc hl
        pop bc
        djnz .my
        dec de                  ; (no , after the last)
        call .crlf
.len:   ld hl,ini_out           ; HL = the length
        ex de,hl
        or a
        sbc hl,de
        push hl
        ld a,(H_PHYD)
        cp #C9
        pop bc
        ret z
        push bc
        ld hl,dk_fcb            ; create, write, close
        ld de,dk_fcb+1
        ld bc,39
        ld (hl),0
        ldir
        ld hl,txt_ininame
        ld de,dk_fcb+1
        ld bc,11
        ldir
        ld de,dk_fcb
        ld c,#16
        call dbdos
        pop bc
        ret c
        inc a
        ret z
        ld hl,1
        ld (dk_fcb+14),hl
        ld hl,0
        ld (dk_fcb+33),hl
        ld (dk_fcb+35),hl
        push bc
        ld de,ini_out
        ld c,#1A
        call dbdos
        pop hl
        ld de,dk_fcb
        ld c,#26
        call dbdos
        jp dk_close
; .is: HL = a line, BC = "key=" -> Z: the line starts with it (HL, DE kept)
.is:    push hl
.i:     ld a,(bc)
        or a
        jr z,.y
        cp (hl)
        jr nz,.y
        inc hl
        inc bc
        jr .i
.y:     pop hl
        ret
.crlf:  ld a,13
        ld (de),a
        inc de
        ld a,10
        ld (de),a
        inc de
        ret

;------------------------------------------------------------------------------
; the program
mt_main:
        call sys_init
        call font_init
        call eng_init
        call net_init
        call ini_load
        xor a
        ld (quit),a
        ld hl,#FFFF
        ld (ck_lmin),hl
        call ck_fill
        call mod_mk             ; the page opens
.loop:  call clk_tick
        call eng_tick
        call ck_fill
        call http_poll
        ld (mt_data),a
        call eng_poll
        call mod_mk+3           ; its pass
        call getkey
        or a
        jr z,.nk
        ld b,a
        call mod_mk+9           ; its keys
.nk:    ld a,(quit)
        or a
        jr nz,.end
        ld a,(mt_data)
        or a
        jr nz,.loop
        call http_busy
        jr z,.idle
        call net_wait
        jr .loop
.idle:  ei
        halt
        jr .loop
.end:   call http_stop
        jp mod_mk+18            ; it leaves (BASIC's screen again)
        VAR mt_data, 1
