;==============================================================================
; mktw.asm - MKTW: PicoAmp's market monitor for the MSX Pico+ (and any MSX2
; with a TCP/IP UNAPI with TLS): PicoAmp's page (markets.asm) in its own
; look, its engine's work done on the Z80 (mkeng*.asm) with the MSX RSS
; reader's HTTP client.
;
; Built at 4000h as RSS.ROM is (it starts at H.STKE, when the disk is ready),
; but it runs from RAM: MKTWL (mktwl.asm) unpacks it there, as RSSW.ROM does
; with the RSS reader. The variables after the code in page 2, up to DA00h
; (the loader's routine is at DA00h).
;
;   sjasmplus --raw=mktw.bin mktw.asm
;
; This work is licensed under a "Creative Commons Attribution-NonCommercial-
; ShareAlike 4.0 International License".
;==============================================================================

USRTAB  equ #F39A
FCERR   equ #475A

vizbuf  equ #A000               ; PicoAmp's work area for the page (256-aligned, 2 KB+)
VARS    equ #A900
VARS_TOP equ #DA00
vp = VARS
        macro VAR _vn, _vs
_vn equ vp
vp = vp + _vs
        endm

        org #4000
        db "AB"
        dw rom_init
        dw 0,0,0
        ds 6

; INIT: our slot into H.STKE (run when BASIC starts: the disk is ready);
; USRTAB changed, so that Nextor starts Disk BASIC 2 (FAT16), not MSX-DOS 1 mode
rom_init:
        in a,(#A8)
        rrca
        rrca
        and 3
        ld c,a
        ld b,0
        ld hl,EXPTBL
        add hl,bc
        ld a,(hl)
        and #80
        jr z,.p
        or c
        ld c,a
        inc hl
        inc hl
        inc hl
        inc hl
        ld a,(hl)
        and #0C
        or c
        ld c,a
.p:     ld hl,FCERR+1
        ld (USRTAB),hl
        ld hl,H_STKE
        ld (hl),#F7
        inc hl
        ld (hl),c
        inc hl
        ld (hl),low rom_start
        inc hl
        ld (hl),high rom_start
        inc hl
        ld (hl),#C9
        ret

rom_start:
        ld a,(H_STKE+1)         ; (our slot)
        ld hl,H_STKE
        ld b,5
.c:     ld (hl),#C9
        inc hl
        djnz .c
        ld hl,FCERR
        ld (USRTAB),hl
        push af
        ; the TCP/IP UNAPI asked for once now: the ESP8266 BIOS takes its 30
        ; bytes under HIMEM on that first call, before HIMEM is used below
        ld a,(HOKVLD)
        rrca
        jr nc,.nx
        ld hl,txt_tcpip
        ld de,ARG
        ld bc,7
        ldir
        xor a
        ld b,a
        ld de,#2222
        call EXTBIO
        ld a,b
        or a
        jr z,.nx
        ld a,1
        ld de,#2222
        call EXTBIO
.nx:    pop af
        ld c,a
        ld hl,(HIMEM)           ; 256 bytes of BASIC's stack kept at HIMEM - 768
        ld de,-768
        add hl,de
        push hl
        ld de,VARS_TOP+176      ; (the loader's routine is below that)
        or a
        sbc hl,de
        pop de
        jp c,.small
        ld ix,0
        add ix,sp
        push ix
        pop hl
        push bc
        ld bc,256
        ldir
        pop bc
        ld hl,-256
        add hl,de
        ld sp,(HIMEM)
        push ix
        push hl
        push bc
        call vars_clear
        pop bc
        pop hl
        ld (rom_sa),hl
        pop hl
        ld (rom_sp),hl
        ld a,c
        ld (rom_slot),a
        in a,(#A8)              ; page 2: ours too (back at the end)
        rrca
        rrca
        rrca
        rrca
        and 3
        ld e,a
        ld d,0
        ld hl,EXPTBL
        add hl,de
        ld a,(hl)
        and #80
        jr z,.np
        or e
        ld e,a
        inc hl
        inc hl
        inc hl
        inc hl
        ld a,(hl)
        rrca
        rrca
        and #0C
        or e
        ld e,a
.np:    ld a,e
        ld (rom_p2),a
        ld a,(rom_slot)
        ld h,#80
        call #0024
        ei
        call mt_main
        ld a,(rom_p2)
        ld h,#80
        call #0024
        di
        ld hl,(rom_sa)
        ld de,(rom_sp)
        ld bc,256
        ldir
        ld sp,(rom_sp)
        ei
        ret
.small: ld hl,txt_small
.m:     ld a,(hl)
        or a
        ret z
        push hl
        call #00A2
        pop hl
        inc hl
        jr .m
txt_small: db "Markets: not enough memory under HIMEM",13,10,0
        VAR rom_slot, 1
        VAR rom_p2, 1
        VAR rom_sp, 2
        VAR rom_sa, 2
        VAR has_disk, 1

vars_clear:
        ld hl,VARS
        ld de,VARS+1
        ld bc,VARS_END-VARS-1
        ld (hl),0
        ldir
        ret

        include "rss_sys.asm"
        include "rss_date.asm"
        include "rss_net.asm"
        include "mkmath.asm"
        include "mknum.asm"
        include "mkframe.asm"
        include "mkeng.asm"
        include "mkeng2.asm"
        include "mkeng3.asm"
        include "markets.asm"
        include "mk_cat.inc"

code_end:
        display "code ends at ",/H,code_end,", variables ",/H,VARS,"-",/H,vp
        ASSERT code_end <= vizbuf, the code runs into the page's work area
VARS_END equ vp
        ASSERT VARS_END <= VARS_TOP, too many variables
