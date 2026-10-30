;=============================================================================
; BLOKK 3D  -  Blockout-ihletesu jatek Videoton TV-Computer 64K-ra   (v02)
; 4 szinu mod (256x240), Z80 @ 3.125 MHz, sjasmplus
;
; Memoria (lapozas $90 = U0 | U1 | VID | U3):
;   $0000-$3FFF  U0   rendszervaltozok, BASIC betolto ($19EF), kod, tablak
;   $4000-$7FFF  U1   tablak folytatasa, BSS, verem ($8000-tol lefele)
;   $8000-$BBFF  VID  kepernyo, 64 bajt/sor, 240 sor
;   $C000-$FBFF  U3   hatterkep masolata (akna + lerakott kockak)
; Megszakitasok tiltva, a 50 Hz-es CRTC flip-flopot a $59-es porton figyeljuk.
;=============================================================================

        DEVICE NOSLOT64K

VRAM        equ $8000
BGCOPY      equ $C000
SCRBYTES    equ 64*240
P_SAVE      equ $0003
PORT03      equ $0B11           ; ROM masolatok (TVC ROM leiras)
PORT05      equ $0B12
PORT06      equ $0B13
INKV        equ $0B4D
PAPERV      equ $0B4E
BORDERV     equ $0B4F
VP_A        equ 1               ; 64+: a ket rajzlap (a 0. a BASIC-e marad)
VP_B        equ 2
LEVEL_3D    equ 3               ; 0-tol szamolt szint: ettol jonnek a ket retegu elemek (4. szint)
MAP_GAME    equ $90             ; U0,U1,VID,U3
MAP_ALL     equ $B0             ; U0,U1,U2,U3 (cimkep-adatok olvasasa)

; palettaszinek: 0 I 0 G 0 R 0 B
PAL0        equ $00             ; fekete
PAL1        equ $10             ; zold   (racs)
PAL2        equ $44             ; vilagos piros (lerakott kockak)
PAL3        equ $55             ; feher  (eso elem, szamok)
BORDER      equ $00

CM_GRID     equ $F0             ; 1-es szin minden pixelre
CM_RED      equ $0F             ; 2-es szin
CM_PIECE    equ $FF             ; 3-as szin

REP_FIRST   equ 12
REP_NEXT    equ 4

OR_N        equ 12              ; orientacio rekord: 6 forgatas + 6 kiterjedes, utana a kockak szama

; billentyu-bitek (keys: also bajt, keys+1: felso bajt)
K_LEFT      equ $01
K_RIGHT     equ $02
K_UP        equ $04
K_DOWN      equ $08
K_Q         equ $10
K_A         equ $20
K_W         equ $40
K_S         equ $80
K_E         equ $01             ; felso bajt
K_D         equ $02
K_DROP      equ $04
K_ESC       equ $08

;-----------------------------------------------------------------------------
; BASIC betolto: 10 PRINT USR(6659)
;-----------------------------------------------------------------------------
        ORG $19EF
        db $0F,$0A,$00,$DD
        db " USR"
        db $96
        db "6659"
        db $95,$FF
        db 0,0,0,0,0            ; program vege + kitoltes -> $1A03

        ASSERT $ == 6659

;=============================================================================
start:
        di
        ld (quit_sp+1),sp       ; BASIC verem a kilepeshez
        ld a,MAP_GAME
        ld (P_SAVE),a
        out ($02),a
        ld sp,STACK_TOP         ; a verem az U3 vegen van
        xor a
        out ($05),a             ; hang es hang-IT ki
        out ($03),a
        ld a,1
        out ($06),a             ; 4 szinu mod
        ld a,BORDER
        out ($00),a
        ld a,PAL0 : out ($60),a
        ld a,PAL1 : out ($61),a
        ld a,PAL2 : out ($62),a
        ld a,PAL3 : out ($63),a

        ; BSS torlese
        ld hl,BSS_START
        ld de,BSS_START+1
        ld bc,BSS_END-BSS_START-1
        ld (hl),0
        ldir

        ld a,r
        ld (seed),a
        ld a,$5A
        ld (seed+1),a
        jp title

new_game:
        ld sp,STACK_TOP
        ld hl,GAME_PAL
        call set_pal
        call set_or
        ld hl,PIT
        ld de,PIT+1
        ld bc,PIT_SIZE-1
        ld (hl),0
        ldir
        ld hl,score             ; score(3) level layers(2) cubes(2) dropcnt
        ld de,score+1
        ld bc,STATS_LEN-1
        ld (hl),0
        ldir
        ld a,(FALLTAB)
        ld (fallspeed),a
        call full_redraw
        call spawn
        jp c,game_over
        call show_piece

;-----------------------------------------------------------------------------
main_loop:
        call vsync
    IFDEF PLUS
        call do_flip            ; a kesz hatso lap megjelenitese a kepkocka elejen
    ENDIF
        call snd_tick
        call read_keys

        xor a
        ld (dirty),a

        ; --- ESC: uj jatek
        ld a,(knew+1)
        and K_ESC
        jr z,.noesc
        call update_hiscore
        jp title
.noesc:
    IFDEF PLUS
        ld a,(dropping)         ; ejtes-animacio alatt nincs iranyitas
        or a
        jp nz,.anim
    ENDIF
        ; --- mozgatas ismetlessel
        ld a,(keys)
        and K_LEFT|K_RIGHT|K_UP|K_DOWN
        jr z,.nomove
        ld b,a
        ld a,(knew)
        and K_LEFT|K_RIGHT|K_UP|K_DOWN
        jr z,.held
        ld a,REP_FIRST
        ld (repcnt),a
        jr .domove
.held:
        ld a,(repcnt)
        dec a
        ld (repcnt),a
        jr nz,.nomove
        ld a,REP_NEXT
        ld (repcnt),a
.domove:
        ld a,b
        call try_moves
.nomove:
        ; --- forgatasok (csak lenyomaskor)
        ld a,(knew)
        ld c,a
        ld b,0
        bit 4,c : call nz,try_rot        ; Q  (b=0)
        inc b : bit 5,c : call nz,try_rot ; A
        inc b : bit 6,c : call nz,try_rot ; W
        inc b : bit 7,c : call nz,try_rot ; S
        ld a,(knew+1)
        ld c,a
        inc b : bit 0,c : call nz,try_rot ; E
        inc b : bit 1,c : call nz,try_rot ; D

        ; --- ejtes
        ld a,(knew+1)
        and K_DROP
        jr z,.nodrop
.droplp:
        call copy_cur_try
        ld hl,try_pz
        inc (hl)
        call collide
        jr c,.dropend
        call accept_try
        ld hl,dropcnt
        inc (hl)
        jr .droplp
.dropend:
    IFDEF PLUS
        ld a,(dropcnt)          ; mar a fenekan: azonnal lerakjuk
        or a
        jp z,.lock
        ld a,1                  ; kulonben az animacio vegen
        ld (dropping),a
        ld hl,SFX_WHOOSH
        ld a,2
        call snd_play
        jr .anim
    ELSE
        jp .lock
    ENDIF
.nodrop:
        ; --- gravitacio (1. szint: nincs, az elem csak ejtesre esik)
        ld a,(fallspeed)
        or a
        jr z,.nofall
        ld hl,fallcnt
        dec (hl)
        jr nz,.nofall
        ld a,(fallspeed)
        ld (hl),a
        call copy_cur_try
        ld hl,try_pz
        inc (hl)
        call collide
        jp c,.lock
        call accept_try
.nofall:
    IFDEF PLUS
.anim:  ; a lathato melyseg kozelitese a logikaihoz: 1/4 reteg/kep, ejteskor 1 reteg/kep
        ld a,(piece_pz)
        add a,a
        add a,a
        ld b,a
        ld a,(piece_vz)
        cp b
        jr z,.vdone
        jr nc,.vsnap
        ld c,1
        ld a,(dropping)
        or a
        jr z,$+4
        ld c,4
        ld a,(piece_vz)
        add a,c
        cp b
        jr c,$+3
        ld a,b
        jr .vset
.vsnap: ld a,b
.vset:  ld (piece_vz),a
        ld a,1
        ld (dirty),a
.vdone: ld a,(dropping)
        or a
        jr z,.show
        ld a,(piece_vz)
        cp b
        jp z,.lock              ; leert: lerakas
.show:
    ENDIF
        ld a,(dirty)
        or a
        call nz,show_piece
        jp main_loop

.lock:
    IFDEF PLUS
        xor a
        ld (dropping),a
        ld a,(piece_pz)
        add a,a
        add a,a
        ld (piece_vz),a
        ld hl,SFX_LOCK          ; a suvitas mar az ejtes elejen szolt
    ELSE
        ld hl,SFX_LOCK          ; ejtesnel suvito + puffanas, kulonben csak puffanas
        ld a,(dropcnt)
        or a
        jr z,$+5
        ld hl,SFX_DROP
    ENDIF
        ld a,3
        call snd_play
        call lock_piece
        call score_lock
        call orient_ptr
        ld de,OR_N
        add hl,de
        ld e,(hl)
        ld d,0
        ld hl,(cubes)
        add hl,de
        ld (cubes),hl
        call clear_layers       ; A = torolt retegek szama
        or a
        jr nz,.full
        call redraw_new         ; csak az uj kockak kornyeke
        call panel_update
        jr .spawn
.full:  call score_clear
        call full_redraw
.spawn: call spawn
        jp c,game_over          ; nem fer be: jatek vege
        call show_piece
        jp main_loop

;-----------------------------------------------------------------------------
; jatek vege: felirat az akna kozepen, Szokoz/Tuz/Esc uj jatekot indit
game_over:
        ld hl,SFX_OVER
        ld a,6
        call snd_play
        call erase_piece
    IFDEF PLUS
        xor a
        ld (flip_pend),a        ; a felirat az elso lapra kerul, az marad lathato
    ENDIF
        xor a
        ld (pat0),a
        ld (pat1),a
        ld d,PIT_CX-26
        ld e,PIT_CX+25
        ld b,PIT_CY-10
        ld c,PIT_CY+12
        call fillrect
        ld a,CM_PIECE
        ld (tcol),a
        ld a,(PIT_CX-20)/4
        ld (pc_col),a
        ld a,PIT_CY-4
        ld (pc_y),a
        ld hl,STR_OVER
        call print_str
.w:     call vsync
        call snd_tick
        call read_keys
        ld a,(knew+1)
        and K_ESC|K_DROP
        jr z,.w
        call update_hiscore
        jp title

; update_hiscore: ha a pont nagyobb a rekordnal, atmasolja
update_hiscore:
        ld hl,score+2
        ld de,hiscore+2
        ld b,3
.c:     ld a,(de)
        cp (hl)
        jr c,.copy              ; rekord < pont
        ret nz                  ; rekord > pont
        dec hl
        dec de
        djnz .c
        ret
.copy:  ld hl,score
        ld de,hiscore
        ld bc,3
        ldir
        ret

;=============================================================================
; CIMKEPERNYO: RLE-tomoritett hatter, forgo drotvaz-elem (XOR), villogo felirat
;=============================================================================
title:
        ld sp,STACK_TOP
    IFDEF PLUS
        ; a cimkep a nem lathato lapon (soha nem a BASIC 0. lapjan) epul fel
        xor a
        ld (flip_pend),a
        call other_page
        ld (vp_back),a
        call map_win
    ENDIF
        ld a,MAP_ALL            ; a cimkep-adatok az U2-be is atnyulhatnak
        call set_map
        ld hl,TITLE_RLE
        ld de,BGCOPY
        call rle_unpack
        ld a,MAP_GAME
        call set_map
        call restore_bg         ; U3 -> kepernyo
    IFDEF PLUS
        call flip_now           ; kepkocka elejen lapvaltas, rogton utana paletta
    ENDIF
        ld hl,TITLE_PALT        ; paletta csak a kesz kephez
        call set_pal
    IFDEF PLUS
        call other_page         ; a hatso lap mindig a masik jatekos lap
        ld (vp_back),a
        xor a
        ld (obA),a
        ld (obB),a
        ld a,(vp_front)
        call map_win            ; a cimkep a lathato lapon fut tovabb
    ENDIF
        ld a,CM_PIECE
        call set_color
        call set_or
        ld a,CM_PIECE
        ld (tcol),a
        ld a,HISCORE_COL : ld (pc_col),a
        ld a,HISCORE_Y : ld (pc_y),a
        ld hl,hiscore
        ld a,7
        call print_num
        xor a
        ld (an_cur),a
        ld (an_tick),a
        ld (an_blink),a
        ld (an_div),a
        call blink_toggle
        ld hl,SFX_TITLE
        ld a,6
        call snd_play
.loop:  call vsync
        call snd_tick
        call read_keys
        ld a,(knew+1)
        and K_ESC
        jp nz,quit
        ld a,(knew+1)
        and K_DROP
        jp nz,new_game
        ld hl,an_tick
        inc (hl)
        ld hl,an_div
        inc (hl)
        ld a,(hl)
        cp 3
        jr c,.nost
        ld (hl),0
        call anim_step          ; 3 kepkockankent (16,7/s)
.nost:
        ld a,(an_tick)
        and 31
        call z,blink_toggle
        jr .loop

; anim_step: a kovetkezo allas off-screen (U3) rajzolasa, majd egy menetben
; a kepernyore masolasa: a nezo sosem lat felkesz allapotot.
anim_step:
        ; 1) munkateglalap torlese U3-ban
        ld b,ANIM_Y0
        call rowaddr
        ld a,h : add a,BGCOPY/256-VRAM/256 : ld h,a
        ld a,l : or ANIM_C0 : ld l,a
        ld b,ANIM_ROWS
.cl:    push bc
        push hl
        ex de,hl
        ld hl,ZEROS
        call LDIBLK+(64-ANIM_W)*2
        pop hl
        ld bc,64
        add hl,bc
        pop bc
        djnz .cl
        ; 2) rajzolas U3-ba (az allasok az U2-ben is lehetnek)
        ld a,MAP_ALL
        call set_map
        ld a,BGCOPY/256
        ld (ra_base+1),a
        ld a,(an_cur)
        call anim_draw
        ld a,VRAM/256
        ld (ra_base+1),a
        ld a,MAP_GAME
        call set_map
        ; 3) masolas a kepernyore
        ld b,ANIM_Y0
        call rowaddr
        ld a,l : or ANIM_C0 : ld l,a
        ld d,h : ld e,l
        ld a,h : add a,BGCOPY/256-VRAM/256 : ld h,a
        ld b,ANIM_ROWS
.cp:    push bc
        push hl
        push de
        call LDIBLK+(64-ANIM_W)*2
        pop hl
        ld bc,64
        add hl,bc
        ex de,hl
        pop hl
        ld bc,64
        add hl,bc
        pop bc
        djnz .cp
        ld a,(an_cur)
        inc a
        cp ANIM_NF
        jr c,$+3
        xor a
        ld (an_cur),a
        ret

ZEROS:  ds ANIM_W,0

; anim_draw: A = kockaszam
anim_draw:
        add a,a
        ld e,a
        ld d,0
        ld hl,ANIM_FP
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld (an_base),hl
        ld hl,ANIM_E
        ld b,ANIM_NE
.e:     push bc
        ld a,(hl) : inc hl
        ld c,(hl) : inc hl
        push hl
        ld hl,(an_base)
        add a,l : ld l,a
        jr nc,$+3 : inc h
        ld d,(hl) : inc hl : ld e,(hl)          ; x1,y1
        ld hl,(an_base)
        ld a,c
        add a,l : ld l,a
        jr nc,$+3 : inc h
        ld b,(hl) : inc hl : ld c,(hl)          ; x2,y2
        call line
        pop hl
        pop bc
        djnz .e
        ret

blink_toggle:
        ld a,(an_blink)
        xor 1
        ld (an_blink),a
        ld hl,STR_BLINK
        jr nz,.p
        ld hl,STR_NOBLINK
.p:     ld a,CM_RED
        ld (tcol),a
        ld a,BLINK_COL : ld (pc_col),a
        ld a,BLINK_Y : ld (pc_y),a
        jp print_str

; rle_unpack: HL = forras, DE = cel
; ctrl < $80: ctrl+1 literal bajt; $80..$FE: kovetkezo bajt (ctrl-$80)+3-szor; $FF vege
rle_unpack:
.l:     ld a,(hl)
        inc hl
        cp $FF
        ret z
        cp $80
        jr nc,.rep
        inc a
        ld c,a
        ld b,0
        ldir
        jr .l
.rep:   sub $80-3
        ld b,a
        ld a,(hl)
        inc hl
.r:     ld (de),a
        inc de
        djnz .r
        jr .l

; panel_update: melysegjelzo + szamok (64+: mindket lapon)
panel_update:
    IFDEF PLUS
        ld a,(vp_back)
        call map_win
        call update_gauge
        call print_stats
        ld a,(vp_front)
        call map_win
    ENDIF
        call update_gauge
        jp print_stats

    IFDEF PLUS
; map_win: A = a $8000-es ablakban lathato videolap; a megjelenitett a vp_front
map_win:
        ld (vp_win),a
apply_vp:
        ld a,(vp_front)
        add a,a
        add a,a
        ld b,a
        ld a,(vp_win)
        or b
        add a,a
        add a,a                 ; b5-b4: megjelenitett lap, b3-b2: ablak
        out ($0F),a
        ret

; do_flip: ha van kesz hatso lap, az lesz a lathato
do_flip:
        ld a,(flip_pend)
        or a
        ret z
        xor a
        ld (flip_pend),a
        ld a,(vp_front)
        ld b,a
        ld a,(vp_back)
        ld (vp_front),a
        ld a,b
        ld (vp_back),a
        jr apply_vp

; other_page: A = az 1./2. lap kozul az, amelyik most nem latszik
other_page:
        ld a,(vp_front)
        cp VP_A
        ld a,VP_B
        ret z
        ld a,VP_A
        ret

; flip_now: varakozas a kepkocka elejere es lapvaltas
flip_now:
        call vsync
        ld a,1
        ld (flip_pend),a
        jr do_flip

; erase_back: a hatso lapon (ablak = hatso) levo elem torlese a hatterbol
erase_back:
        call back_ob
        ld a,(hl)
        or a
        ret z
        ld (hl),0
        inc hl
        ld a,$EB
        jp copy_rect

; back_ob: HL = a hatso lap elem-befoglaloja (ervenyes, x1, y1, x2, y2)
back_ob:
        ld a,(vp_back)
        cp VP_A
        ld hl,obA
        ret z
        ld hl,obB
        ret
    ENDIF

; set_map: A = lapozas ($02 port + P_SAVE)
set_map:
        ld (P_SAVE),a
        out ($02),a
        ret

; restore_bg: teljes hatter (U3) -> kepernyo
restore_bg:
        ld hl,BGCOPY
        ld de,VRAM
        ld bc,SCRBYTES
.l:
        REPT 16
        ldi
        ENDR
        jp pe,.l
        ret

; set_pal: HL -> 4 palettaszin a $60-$63 portokra
set_pal:
        ld c,$60
        ld b,4
.l:     ld a,(hl)
        out (c),a
        inc hl
        inc c
        djnz .l
        ret

GAME_PAL:   db PAL0,PAL1,PAL2,PAL3
TITLE_PALT: db TITLE_PAL0,TITLE_PAL1,TITLE_PAL2,TITLE_PAL3

; vonalrajzolas modja: OR (jatek) vagy XOR (cimkepernyo animacio)
set_or:
        ld a,$B6                ; or (hl)
        jr set_mode
set_xor:
        ld a,$AE                ; xor (hl)
set_mode:
        ld (xm_cm+2),a
        ld (ym_cm+2),a
        ret

;-----------------------------------------------------------------------------
; quit: vissza a BASIC-be. Billentyu-felengedes, lapozas, portok es keret a ROM
; masolataibol, paletta: PAPER -> fekete, INK -> feher, kepernyotorles a ROM-mal.
quit:
        call snd_stop
.rel:   call vsync
        call read_keys
        ld hl,(keys)
        ld a,h
        or l
        jr nz,.rel
        ld a,$70
        ld (P_SAVE),a
        out ($02),a
    IFDEF PLUS
        xor a
        out ($0F),a             ; 0. videolap: a BASIC kepernyoje erintetlen
    ENDIF
        ld a,(PORT06) : out ($06),a
        ld a,(PORT05) : out ($05),a
        ld a,(PORT03) : out ($03),a
        ld a,(BORDERV) : out ($00),a
        ld a,(PAPERV) : and 3 : add a,$60 : ld c,a
        xor a
        out (c),a
        ld a,(INKV) : and 3 : add a,$60 : ld c,a
        ld a,$55
        out (c),a
        out ($07),a             ; fuggo IT torlese
quit_sp:
        ld sp,0                 ; onmodosito: BASIC verem
        ei
        rst $30
        db $05                  ; CLS
        ret

;-----------------------------------------------------------------------------
; try_moves: A = lenyomott iranybitek
try_moves:
        ld c,a
        bit 0,c : jr z,.r
        call copy_cur_try
        ld hl,try_px : dec (hl)
        call try_accept
.r:     bit 1,c : jr z,.u
        call copy_cur_try
        ld hl,try_px : inc (hl)
        call try_accept
.u:     bit 2,c : jr z,.d
        call copy_cur_try
        ld hl,try_py : dec (hl)
        call try_accept
.d:     bit 3,c : ret z
        call copy_cur_try
        ld hl,try_py : inc (hl)
        ; fall through
try_accept:
        push bc
        call collide
        jr c,.no
        call accept_try
        ld hl,SFX_MOVE
        ld a,1
        call snd_play
.no:    pop bc
        ret

;-----------------------------------------------------------------------------
; try_rot: B = forgatas sorszama (0..5). Rugas: 0, -x, +x, -y, +y, +z
try_rot:
        push bc
        call copy_cur_try       ; BC-t megorzi
        call orient_ptr
        ld e,b
        ld d,0
        add hl,de
        ld a,(hl)
        ld (try_or),a
        ld hl,KICKS
        ld b,6
.k:     push bc
        push hl
        ld a,(piece_px) : add a,(hl) : ld (try_px),a : inc hl
        ld a,(piece_py) : add a,(hl) : ld (try_py),a : inc hl
        ld a,(piece_pz) : add a,(hl) : ld (try_pz),a
        call collide
        pop hl
        pop bc
        jr nc,.ok
        inc hl : inc hl : inc hl
        djnz .k
        pop bc
        ret
.ok:    call accept_try
        ld hl,SFX_ROT
        ld a,1
        call snd_play
        pop bc
        ret

KICKS:  db 0,0,0, -1,0,0, 1,0,0, 0,-1,0, 0,1,0, 0,0,1

copy_cur_try:
        push bc
        ld hl,piece_px
        ld de,try_px
        ld bc,4
        ldir
        pop bc
        ret

accept_try:
        push bc
        ld hl,try_px
        ld de,piece_px
        ld bc,4
        ldir
    IFDEF PLUS
        call vz_clamp
    ENDIF
        pop bc
    IFNDEF PLUS
        ld a,(piece_pz)         ; 64K: a lathato melyseg azonnal kovet
        add a,a
        add a,a
        ld (piece_vz),a
    ENDIF
        ld a,1
        ld (dirty),a
        ret

    IFDEF PLUS
; vz_clamp: a lathato melyseg nem lehet olyan kicsi, hogy az elem legfelso kockaja
; a nyilas fole (negativ melysegre) keruljon - pl. forgatasi +z rugas utan, mikozben
; a lathato melyseg meg csak kozeliti a logikait. (-zmin*4 <= pz*4, tehat nem ugrik tul.)
vz_clamp:
        call orient_ptr
        ld de,10                ; kiterjedes: zmin (elojeles, <= 0)
        add hl,de
        ld a,(hl)
        add a,a
        add a,a
        neg
        ld b,a
        ld a,(piece_vz)
        cp b
        ret nc
        ld a,b
        ld (piece_vz),a
        ret
    ENDIF

; HL = ORPTR[piece_or]
orient_ptr:
        ld a,(piece_or)
orient_ptr_a:
        ld l,a
        ld h,0
        add hl,hl
        ld de,ORPTR
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ret

; pit_addr: A = z, E = y*8+x  ->  HL = PIT + z*64 + y*8 + x
pit_addr:
        rrca : rrca
        ld d,a
        and $C0
        add a,e
        ld l,a
        ld a,d
        and $3F
        adc a,PIT/256
        ld h,a
        ret

;-----------------------------------------------------------------------------
; collide: try_* allapot utkozik-e?  Cy=1 ha igen.
collide:
        ld a,(try_or)
        call orient_ptr_a
        ld de,OR_N
        add hl,de
        ld b,(hl)               ; kockak szama
        inc hl
.c:     ld a,(try_px) : add a,(hl) : inc hl
        cp PIT_W : jr nc,.hit
        ld e,a
        ld a,(try_py) : add a,(hl) : inc hl
        cp PIT_H : jr nc,.hit
        add a,a : add a,a : add a,a
        add a,e
        ld e,a
        ld a,(try_pz) : add a,(hl) : inc hl
        cp PIT_D : jr nc,.hit
        push hl
        call pit_addr
        ld a,(hl)
        pop hl
        or a
        jr nz,.hit
        djnz .c
        or a                    ; Cy=0
        ret
.hit:   scf
        ret

;-----------------------------------------------------------------------------
; spawn: uj veletlen elem az akna tetejen. Cy=1 ha nem fer el.
spawn:
        call rand
        ld b,a
        ld a,(level)
        cp LEVEL_3D
        ld a,b
        ld c,NFLAT              ; korai szinteken csak lapos elemek
        jr c,.mod
        ld c,NPIECES
.mod:   cp c
        jr c,.m2
        sub c
        jr .mod
.m2:    ld e,a
        ld d,0
        ld hl,PIECE_FIRST
        add hl,de
        ld a,(hl)
        ld (try_or),a
        ld a,SPAWN_X : ld (try_px),a
        ld a,SPAWN_Y : ld (try_py),a
        xor a : ld (try_pz),a
        ld (dropcnt),a
        ld a,(fallspeed) : ld (fallcnt),a
        call collide
        ret c
        call accept_try
        xor a
        ld (piece_vz),a
        ld (dropping),a
        or a
        ret

; rand: A = pszeudo-veletlen bajt (16 bites xorshift + R)
rand:
        ld hl,(seed)
        ld a,h
        rra
        ld a,l
        rra
        xor h
        ld h,a
        ld a,l
        rra
        ld a,h
        rra
        xor l
        ld l,a
        xor h
        ld h,a
        ld (seed),hl
        ld b,a
        ld a,r
        xor b
        and $7F
        ret

;-----------------------------------------------------------------------------
; lock_piece: az aktualis elem kockait beirja az aknaba
lock_piece:
        call orient_ptr
        ld de,OR_N
        add hl,de
        ld b,(hl)
        inc hl
.c:     ld a,(piece_px) : add a,(hl) : inc hl
        ld e,a
        ld a,(piece_py) : add a,(hl) : inc hl
        add a,a : add a,a : add a,a
        add a,e
        ld e,a
        ld a,(piece_pz) : add a,(hl) : inc hl
        push hl
        call pit_addr
        ld (hl),1
        pop hl
        djnz .c
        ret

;-----------------------------------------------------------------------------
; clear_layers: teli retegek torlese, a felettuk levok lejjebb csusznak
; ki: A = torolt retegek szama
clear_layers:
        xor a
        ld (cleared),a
        ld c,PIT_D-1
.z:     ld l,c
        ld h,0
        add hl,hl : add hl,hl : add hl,hl
        add hl,hl : add hl,hl : add hl,hl
        ld de,PIT
        add hl,de
        push hl
        ld d,PIT_H
.y:     ld b,PIT_W
        push hl
.x:     ld a,(hl)
        or a
        jr z,.notfull
        inc hl
        djnz .x
        pop hl
        ld a,l : add a,8 : ld l,a
        jr nc,$+3 : inc h
        dec d
        jr nz,.y
        ; teli: PIT[0 .. c*64-1] -> PIT[64 ..]
        ld hl,cleared
        inc (hl)
        pop hl                  ; reteg eleje
        ld a,c
        or a
        jr z,.top
        push bc
        dec hl                  ; forras vege = PIT + c*64 - 1
        ld d,h : ld e,l
        ld a,e : add a,64 : ld e,a
        jr nc,$+3 : inc d       ; cel vege = forras vege + 64
        ld l,c
        ld h,0
        add hl,hl : add hl,hl : add hl,hl
        add hl,hl : add hl,hl : add hl,hl
        ld b,h : ld c,l         ; hossz = c*64
        ld h,d : ld l,e
        ld a,l : sub 64 : ld l,a
        jr nc,$+3 : dec h
        lddr
        pop bc
.top:   ld hl,PIT
        ld de,PIT+1
        ld (hl),0
        push bc
        ld bc,63
        ldir
        pop bc
        jr .z                   ; ugyanazt a reteget ujra vizsgaljuk
.notfull:
        pop hl
        pop hl
        dec c
        jp p,.z
        ld a,(cleared)
        ret

;-----------------------------------------------------------------------------
; Pontozas
;   lerakas: kockak szama * (szint+1), plusz az ejtessel megtett retegek
;   retegtorles: CLEARPTS[n] * (szint+1); 5 reteg utan szintlepes
score_lock:
        call orient_ptr
        ld de,OR_N
        add hl,de
        ld l,(hl)
        ld h,0
        call add_score_lvl
        ld a,(dropcnt)
        ld l,a
        ld h,0
        jp add_score

score_clear:
        ld a,(level)
        ld (oldlevel),a
        ld a,(cleared)
        ld c,a
        ld b,0
        ld hl,(layers)
        add hl,bc
        ld (layers),hl
        cp 5
        jr c,$+4
        ld a,4
        add a,a
        ld e,a
        ld d,0
        ld hl,CLEARPTS
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        call add_score_lvl
        ; szint = min(9, layers/5)
        ld hl,(layers)
        ld de,5
        ld b,0
.lv:    or a
        sbc hl,de
        jr c,.lvd
        inc b
        ld a,b
        cp 9
        jr c,.lv
.lvd:   ld a,b
        ld (level),a
        ld e,a
        ld d,0
        ld hl,FALLTAB
        add hl,de
        ld a,(hl)
        ld (fallspeed),a
        ; hang: szintlepes > tobb reteg > egy reteg
        ld a,(oldlevel)
        cp b
        ld hl,SFX_LEVEL
        ld a,5
        jp nz,snd_play
        ld a,(cleared)
        cp 2
        ld hl,SFX_CLEAR1
        jr c,$+5
        ld hl,SFX_CLEARN
        ld a,4
        jp snd_play

; add_score_lvl: HL * (szint+1) hozzaadasa
add_score_lvl:
        ld a,(level)
        inc a
        ld b,a
.l:     call add_score
        djnz .l
        ret

; add_score: HL hozzaadasa a 24 bites ponthoz (csak A valtozik)
add_score:
        ld a,(score)
        add a,l
        ld (score),a
        ld a,(score+1)
        adc a,h
        ld (score+1),a
        ld a,(score+2)
        adc a,0
        ld (score+2),a
        ret

CLEARPTS:   dw 0, 100, 300, 600, 1000
FALLTAB:    db 0, 50, 42, 35, 29, 24, 20, 16, 13, 10   ; 0 = nincs automatikus eses

;-----------------------------------------------------------------------------
; vsync: varakozas a 50 Hz-es CRTC flip-flopra (port $59 bit4 = 0), idokorlattal
vsync:
        ld hl,3000
.w:     in a,($59)
        and $10
        jr z,.got
        dec hl
        ld a,h
        or l
        jr nz,.w
.got:   out ($07),a
        ret

;-----------------------------------------------------------------------------
; read_keys: keys = aktualis, knew = uj lenyomasok
read_keys:
        ld hl,(keys)
        ld (kprev),hl
        ld de,0
        ; 8. sor: fel=02 le=04 tuz=08 jobb=20 bal=40
        ld a,8 : out ($03),a : in a,($58) : cpl
        ld c,a
        bit 6,c : jr z,$+4 : set 0,e
        bit 5,c : jr z,$+4 : set 1,e
        bit 1,c : jr z,$+4 : set 2,e
        bit 2,c : jr z,$+4 : set 3,e
        bit 3,c : jr z,$+4 : set 2,d   ; tuz = ejtes
        ; 2. sor: Q=40 W=04 E=02
        ld a,2 : out ($03),a : in a,($58) : cpl
        ld c,a
        bit 6,c : jr z,$+4 : set 4,e
        bit 2,c : jr z,$+4 : set 6,e
        bit 1,c : jr z,$+4 : set 0,d
        ; 4. sor: A=40 S=04 D=02
        ld a,4 : out ($03),a : in a,($58) : cpl
        ld c,a
        bit 6,c : jr z,$+4 : set 5,e
        bit 2,c : jr z,$+4 : set 7,e
        bit 1,c : jr z,$+4 : set 1,d
        ; 7. sor: Esc=08 Space=20
        ld a,7 : out ($03),a : in a,($58) : cpl
        ld c,a
        bit 3,c : jr z,$+4 : set 3,d
        bit 5,c : jr z,$+4 : set 2,d
        ld (keys),de
        ld hl,(kprev)
        ld a,l : cpl : and e : ld (knew),a
        ld a,h : cpl : and d : ld (knew+1),a
        ret

;=============================================================================
; ESO ELEM
;=============================================================================

; show_piece: regi terulet visszaallitasa + uj elem kirajzolasa
show_piece:
    IFDEF PROFILE
        ld a,1 : out ($FE),a
        ld a,13 : out ($FE),a
    ENDIF
    IFDEF PLUS
        ; 64+: a hatso lapon toroljuk a ket frissitessel korabbi allast, oda rajzolunk,
        ; a kovetkezo kepkocka elejen lapot valtunk
        ld a,(vp_back)
        call map_win
        call back_ob
        ld a,(hl)
        or a
        jr z,.noer
        push hl
        inc hl
        ld a,$EB
        call copy_rect
        pop hl
.noer:
    IFDEF PROFILE
        ld a,14 : out ($FE),a
    ENDIF
        push hl
        call draw_piece
        pop hl
        ld (hl),1
        inc hl
        ex de,hl
        ld hl,bx1
        ld bc,4
        ldir
        ld a,1
        ld (flip_pend),a
    IFDEF PROFILE
        ld a,2 : out ($FE),a
    ENDIF
        ret
    ENDIF
        call erase_piece
    IFDEF PROFILE
        ld a,14 : out ($FE),a
    ENDIF
        call draw_piece
        ld hl,bx1
        ld de,obx1
        ld bc,4
        ldir
        ld a,1
        ld (bbvalid),a
    IFDEF PROFILE
        ld a,2 : out ($FE),a
    ENDIF
        ret

; erase_piece: ha van kirajzolt elem, a teruletet visszaallitja a hatterbol
; (64+: mindket lapon, utana az ablak az elulso lapon all)
erase_piece:
    IFDEF PLUS
        ld a,VP_A
        call map_win
        ld hl,obA
        call .one
        ld a,VP_B
        call map_win
        ld hl,obB
        call .one
        ld a,(vp_front)
        jp map_win
.one:   ld a,(hl)
        or a
        ret z
        ld (hl),0
        inc hl
        ld a,$EB
        jp copy_rect
    ENDIF
        ld a,(bbvalid)
        or a
        ret z
        xor a
        ld (bbvalid),a
        ld hl,obx1
        ld a,$EB                ; ex de,hl -> hatter -> kepernyo
        jr copy_rect

; save_rect: bx1..by2 terulet kepernyo -> hatter
save_rect:
        ld hl,bx1
        xor a                   ; nop -> kepernyo -> hatter

; copy_rect: HL -> x1,y1,x2,y2 (pixel); A = $00 (VRAM->BG) vagy $EB (BG->VRAM)
; Soronkent egy 64-es LDI blokk kozepebe ugrunk (16 ciklus/bajt).
copy_rect:
        ld (cr_dir),a
        ld d,(hl) : inc hl      ; x1
        ld b,(hl) : inc hl      ; y1
        ld e,(hl) : inc hl      ; x2
        ld a,(hl)               ; y2
        sub b
        inc a
        ld c,a                  ; sorok szama
        ld a,d
        rrca : rrca : and $3F
        ld d,a                  ; elso bajt
        ld a,e
        rrca : rrca : and $3F
        sub d
        inc a                   ; bajtok szama (1..64)
        neg
        add a,64
        add a,a                 ; (64-n)*2
        ld e,a
        push de
        ld d,0
        ld hl,LDIBLK
        add hl,de
        ld (cr_jp+1),hl
        pop de
        call rowaddr
        ld a,d
        or l
        ld l,a
        ld b,c
cr_row: push bc
        push hl
        ld d,h : ld e,l
        ld a,h : add a,BGCOPY/256-VRAM/256 : ld d,a   ; DE = hatter
cr_dir: nop                     ; onmodosito: nop / ex de,hl
        call cr_jp
        pop hl
        ld bc,64
        add hl,bc
        pop bc
        djnz cr_row
        ret
cr_jp:  jp 0                    ; onmodosito
LDIBLK:
        REPT 64
        ldi
        ENDR
        ret

;-----------------------------------------------------------------------------
; draw_piece: az eso elem drotvaza a lathato (negyedreteg) melysegen.
; A befoglalo teglalap a racspont-kiterjedesbol.
draw_piece:
        ld a,CM_PIECE
        call set_color
        ld a,(piece_px) : sub 2 : ld (bxp),a
        ld a,(piece_py) : sub 2 : ld (byp),a
        ld a,(piece_vz) : sub 8 : ld (bzq),a      ; negyedreteg, racs-eltolas -2 reteg
        call orient_ptr
        push hl
        call piece_bbox
        pop hl
        ld de,OR_N
        add hl,de
        ld a,(hl)               ; kockak szama
        inc hl
        ld b,a
        add a,a
        add a,b
        ld e,a
        ld d,0
        add hl,de
        ld b,(hl)               ; elek szama
        inc hl
.e:     push bc
        ld c,(hl)               ; axis<<6 | ly<<3 | lx
        inc hl
        ld a,(hl)               ; len<<4 | lz
        inc hl
        push hl
        ld b,a
        and $0F
        add a,a
        add a,a
        ld e,a
        ld a,(bzq)
        add a,e
        ld (ezq),a
        call zq_set
        ld a,b
        rrca : rrca : rrca : rrca
        and $0F
        ld (elen),a
        ld a,c
        and 7
        ld e,a
        ld a,(bxp)
        add a,e
        ld (ex),a
        ld a,c
        rrca : rrca : rrca
        and 7
        ld e,a
        ld a,(byp)
        add a,e
        ld (ey),a
        ld a,c
        and $C0
        jr z,.ax0
        cp $40
        jr z,.ax1
        ; --- Z iranyu el: altalanos vonal
        ld a,(ex) : ld c,a : call sxq : ld d,a
        ld a,(ey) : ld c,a : call syq : ld e,a
        ld a,(elen) : add a,a : add a,a : ld c,a
        ld a,(ezq) : add a,c
        call zq_set
        ld a,(ex) : ld c,a : call sxq : ld b,a
        ld a,(ey) : ld c,a : call syq : ld c,a
        call line
        jr .next
.ax0:   ; --- X iranyu el: vizszintes
        ld a,(ey) : ld c,a : call syq : ld b,a
        ld a,(ex) : ld c,a : call sxq : ld d,a
        ld a,(elen) : add a,c : ld c,a : call sxq : ld e,a
        call hline
        jr .next
.ax1:   ; --- Y iranyu el: fuggoleges
        ld a,(ex) : ld c,a : call sxq : ld d,a
        ld a,(ey) : ld c,a : call syq : ld b,a
        ld a,(elen) : add a,c : ld c,a : call syq : ld e,a
        call vline
.next:  pop hl
        pop bc
        dec b
        jp nz,.e
        ret

; zq_set: A = melyseg negyedretegben -> (eq_lo),(eq_hi) = A*8   (HL, A)
zq_set:
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld a,l
        ld (eq_lo),a
        ld a,h
        ld (eq_hi),a
        ret

; sxq / syq: C = racsindex -> A = SXQ/SYQ[eq + C]   (HL, A)
sxq:    ld a,(eq_hi) : add a,SXQ/256 : ld h,a
        ld a,(eq_lo) : add a,c : ld l,a
        ld a,(hl)
        ret
syq:    ld a,(eq_hi) : add a,SYQ/256 : ld h,a
        ld a,(eq_lo) : add a,c : ld l,a
        ld a,(hl)
        ret

; piece_bbox: HL = orientacio rekord -> bx1,by1,bx2,by2 (lathato melysegen)
; x-ben a bal szel a legkozelebbi vagy a legtavolabbi melysegen van (monoton).
piece_bbox:
        ld de,6
        add hl,de
        ld a,(piece_px) : add a,(hl) : ld (pb_x0),a : inc hl
        ld a,(piece_px) : add a,(hl) : ld (pb_x1),a : inc hl
        ld a,(piece_py) : add a,(hl) : ld (pb_y0),a : inc hl
        ld a,(piece_py) : add a,(hl) : ld (pb_y1),a : inc hl
        ld a,(hl) : add a,a : add a,a : ld b,a
        ld a,(piece_vz) : add a,b : ld (pb_z0),a : inc hl
        ld a,(hl) : add a,a : add a,a : ld b,a
        ld a,(piece_vz) : add a,b : ld (pb_z1),a
        ; kozeli melyseg ertekei
        ld a,(pb_z0) : call zq_set
        ld a,(pb_x0) : ld c,a : call sxq : ld (pb_a),a
        ld a,(pb_x1) : ld c,a : call sxq : ld (pb_a+1),a
        ld a,(pb_y0) : ld c,a : call syq : ld (pb_a+2),a
        ld a,(pb_y1) : ld c,a : call syq : ld (pb_a+3),a
        ; tavoli melyseg es min/max
        ld a,(pb_z1) : call zq_set
        ld a,(pb_x0) : ld c,a : call sxq
        ld hl,pb_a : cp (hl) : jr c,$+3 : ld a,(hl)
        ld (bx1),a
        ld a,(pb_x1) : ld c,a : call sxq
        ld hl,pb_a+1 : cp (hl) : jr nc,$+3 : ld a,(hl)
        ld (bx2),a
        ld a,(pb_y0) : ld c,a : call syq
        ld hl,pb_a+2 : cp (hl) : jr c,$+3 : ld a,(hl)
        ld (by1),a
        ld a,(pb_y1) : ld c,a : call syq
        ld hl,pb_a+3 : cp (hl) : jr nc,$+3 : ld a,(hl)
        ld (by2),a
        ret

; bb_add: D=x, E=y pont hozzaadasa a bx.. befoglalohoz
bb_add:
        ld a,(bx1) : cp d : jr c,$+6 : ld a,d : ld (bx1),a
        ld a,(bx2) : cp d : jr nc,$+6 : ld a,d : ld (bx2),a
        ld a,(by1) : cp e : jr c,$+6 : ld a,e : ld (by1),a
        ld a,(by2) : cp e : jr nc,$+6 : ld a,e : ld (by2),a
        ret

; bb_rect: D=x1 E=x2 B=y1 C=y2 hozzaadasa (regiszterek megmaradnak)
bb_rect:
        push de
        push de
        ld e,b
        call bb_add
        pop de
        ld d,e
        ld e,c
        call bb_add
        pop de
        ret

bb_reset:
        ld a,255 : ld (bx1),a : ld (by1),a
        xor a : ld (bx2),a : ld (by2),a
        ret

;=============================================================================
; HATTER: akna, lerakott kockak, panel
;=============================================================================

full_redraw:
    IFDEF PLUS
        ld a,(vp_back)          ; a rejtett lapon epul fel
        call map_win
    ENDIF
    IFDEF PROFILE
        ld a,3 : out ($FE),a
        ld a,5 : out ($FE),a
    ENDIF
        call cls
    IFDEF PROFILE
        ld a,6 : out ($FE),a
        ld a,7 : out ($FE),a
    ENDIF
        call draw_grid
    IFDEF PROFILE
        ld a,8 : out ($FE),a
    ENDIF
        call draw_panel
    IFDEF PROFILE
        ld a,9 : out ($FE),a
    ENDIF
        call draw_settled
    IFDEF PROFILE
        ld a,10 : out ($FE),a
    ENDIF
        call update_gauge
        call print_stats
    IFDEF PROFILE
        ld a,11 : out ($FE),a
    ENDIF
        call save_bg
    IFDEF PROFILE
        ld a,12 : out ($FE),a
    ENDIF
    IFDEF PLUS
        call flip_now           ; kesz kep elore
        ld a,(vp_back)          ; a masik lap a hatterbol
        call map_win
        call restore_bg
        xor a
        ld (obA),a
        ld (obB),a
    ENDIF
        xor a
        ld (bbvalid),a
    IFDEF PROFILE
        ld a,4 : out ($FE),a
    ENDIF
        ret

cls:
        ld (.sp+1),sp
        ld sp,VRAM+SCRBYTES
        ld de,0
        ld b,SCRBYTES/64
.l:
        REPT 32
        push de
        ENDR
        djnz .l
.sp:    ld sp,0
        ret

save_bg:
        ld hl,VRAM
        ld de,BGCOPY
        ld bc,SCRBYTES
.l:
        REPT 16
        ldi
        ENDR
        ret po
        ld a,e
        or a
        call z,snd_poll         ; 256 bajtonkent hang-leptetes
        jp .l

draw_grid:
        ld a,CM_GRID
        call set_color
        ld hl,GRIDLIST
.g:     call snd_poll
        ld a,(hl)
        cp $FF
        ret z
        inc hl
        push af
        ld a,(hl) : inc hl      ; a
        ld d,(hl) : inc hl      ; b
        ld e,(hl) : inc hl      ; c
        ld c,(hl) : inc hl      ; d
        ld b,a
        pop af
        push hl
        or a
        jr z,.h
        dec a
        jr z,.v
        ld a,b                  ; vonal: x1=B y1=D x2=E y2=C
        ld b,e
        ld e,d
        ld d,a
        call line
        jr .n
.h:     call hline              ; y=B x1=D x2=E
        jr .n
.v:     ld a,b                  ; x=B y1=D y2=E
        ld b,d
        ld d,a
        call vline
.n:     pop hl
        jr .g

;-----------------------------------------------------------------------------
; Panel
draw_panel:
        ld a,CM_RED
        ld (tcol),a
        ld hl,PANEL_TEXT
.t:     ld a,(hl)
        or a
        ret z
        ld (pc_col),a
        inc hl
        ld a,(hl)
        ld (pc_y),a
        inc hl
        call print_str
        inc hl
        jr .t

PANEL_TEXT:
        db PANEL_COL,4,"PONT",0
        db PANEL_COL,34,"SZINT",0
        db PANEL_COL,64,"KOCKA",0
        db PANEL_COL,94,"MELYSEG",0
        db 0
STR_OVER:
        db "JATEK VEGE",0

; print_stats: pont (7 jegy), szint (2), lerakott elemek (5)
print_stats:
        ld a,CM_PIECE
        ld (tcol),a
        ld a,PANEL_COL : ld (pc_col),a
        ld a,16 : ld (pc_y),a
        ld hl,score
        ld a,7
        call print_num
        ld a,(level)
        inc a
        ld (tmpv),a
        xor a
        ld (tmpv+1),a
        ld (tmpv+2),a
        ld a,PANEL_COL : ld (pc_col),a
        ld a,46 : ld (pc_y),a
        ld hl,tmpv
        ld a,2
        call print_num
        ld hl,(cubes)
        ld (tmpv),hl
        xor a
        ld (tmpv+2),a
        ld a,PANEL_COL : ld (pc_col),a
        ld a,76 : ld (pc_y),a
        ld hl,tmpv
        ld a,5
        jp print_num

; update_gauge: melysegjelzo, minden reteg egy cella (z=0 felul)
update_gauge:
        ld c,0
.z:     call snd_poll
        push bc
        ; foglalt-e a reteg?
        ld a,c
        ld e,0
        call pit_addr
        ld b,64
        xor a
.o:     or (hl)
        inc hl
        djnz .o
        pop bc
        push bc
        ld hl,0
        or a
        jr z,.empty
        ld a,c
        add a,a
        ld e,a
        ld d,0
        ld hl,LAYERPAT
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
.empty: ld a,l : ld (pat0),a
        ld a,h : ld (pat1),a
        ld e,c
        ld d,0
        ld hl,GAUGE_Y
        add hl,de
        ld b,(hl)
        ld a,b
        add a,GAUGE_H
        ld c,a
        ld (gy2),a
        ld a,b
        ld (gy1),a
        ld d,GAUGE_X1
        ld e,GAUGE_X2
        call fillrect
        ld a,CM_GRID
        call set_color
        ld a,(gy1) : ld b,a : ld d,GAUGE_X1 : ld e,GAUGE_X2 : call hline
        ld a,(gy2) : ld b,a : ld d,GAUGE_X1 : ld e,GAUGE_X2 : call hline
        ld a,(gy1) : ld b,a : ld a,(gy2) : ld e,a : ld d,GAUGE_X1 : call vline
        ld a,(gy1) : ld b,a : ld a,(gy2) : ld e,a : ld d,GAUGE_X2 : call vline
        pop bc
        inc c
        ld a,c
        cp PIT_D
        jp c,.z
        ret

;-----------------------------------------------------------------------------
; Szoveg. pc_col = bajtoszlop (4 pixel), pc_y = sor, tcol = szinmaszk
; print_chr: A = karakter (32..90); 3x5-os betu, sorai duplazva (10 sor)
print_chr:
        sub 32
        ld l,a
        ld h,0
        ld d,h
        ld e,l
        add hl,hl
        add hl,hl
        add hl,de
        ld de,FONT
        add hl,de
        ex de,hl
        ld a,(pc_y)
        ld b,a
        call rowaddr
        ld a,(pc_col)
        or l
        ld l,a
        ld a,(tcol)
        ld c,a
        ld b,5
.r:     ld a,(de)
        and c
        ld (hl),a
        ld a,l : add a,64 : ld l,a
        jr nc,$+3 : inc h
        ld a,(de)
        and c
        ld (hl),a
        ld a,l : add a,64 : ld l,a
        jr nc,$+3 : inc h
        inc de
        djnz .r
        ld hl,pc_col
        inc (hl)
        ret

; print_str: HL = 0-val zart szoveg (kilepeskor HL a lezaro 0-ra mutat)
print_str:
.c:     ld a,(hl)
        or a
        ret z
        push hl
        call print_chr
        pop hl
        inc hl
        jr .c

; print_num: HL -> 3 bajtos ertek, A = kiirt jegyek szama (vezeto nullakkal)
print_num:
        push af
        call num24
        pop af
        ld e,a
        ld a,8
        sub e
        ld e,a
        ld d,0
        ld hl,NUMBUF
        add hl,de
        jp print_str

; num24: HL -> 24 bites ertek  ->  NUMBUF 8 ASCII jegy
num24:
        ld a,(hl) : inc hl
        ld b,(hl) : inc hl
        ld c,(hl)
        ld l,a
        ld h,b                  ; C:H:L = ertek
        ld de,POW10
        ld ix,NUMBUF
        ld a,8
        ld (n_cnt),a
.d:     ld (ix+0),'0'
.s:     ld a,(de) : ld b,a : ld a,l : sub b : ld l,a
        inc de
        ld a,(de) : ld b,a : ld a,h : sbc a,b : ld h,a
        inc de
        ld a,(de) : ld b,a : ld a,c : sbc a,b : ld c,a
        dec de
        dec de
        jr c,.u
        inc (ix+0)
        jr .s
.u:     ld a,(de) : add a,l : ld l,a
        inc de
        ld a,(de) : adc a,h : ld h,a
        inc de
        ld a,(de) : adc a,c : ld c,a
        inc de
        inc ix
        ld a,(n_cnt)
        dec a
        ld (n_cnt),a
        jr nz,.d
        ret

POW10:  d24 10000000, 1000000, 100000, 10000, 1000, 100, 10, 1

;=============================================================================
; LERAKOTT KOCKAK
;=============================================================================

; draw_settled: minden lerakott kocka, hatulrol elore; retegenkent eloszor az
; oldallapok, aztan a tetok
draw_settled:
        ld a,PIT_D-1
        ld (zmaxn),a
        ld a,1
        ld (ds_all),a
        jr ds_go

; redraw_new: lerakas utan (reteg-torles nelkul) csak az uj kockak es az
; oket takaro kozelebbi kockak rajzolodnak ujra; a valtozott terulet a hatterbe megy.
redraw_new:
    IFDEF PROFILE
        ld a,15 : out ($FE),a
    ENDIF
    IFDEF PLUS
        ld a,(vp_back)          ; a hatso lapon dolgozunk, elol meg a leert elem latszik
        call map_win
        call erase_back
    ELSE
        call erase_piece
    ENDIF
        call bb_reset
        xor a
        ld (zmaxn),a
        call orient_ptr
        ld de,OR_N
        add hl,de
        ld b,(hl)
        inc hl
.c:     push bc
        ld a,(piece_px) : add a,(hl) : ld (fx),a : inc hl
        ld a,(piece_py) : add a,(hl) : ld (fy),a : inc hl
        ld a,(piece_pz) : add a,(hl) : ld (fz),a : inc hl
        push hl
        ld hl,zmaxn
        cp (hl)
        jr c,$+3
        ld (hl),a
        call foot_rect
        call bb_rect
        pop hl
        pop bc
        djnz .c
        ld hl,bx1
        ld de,nbx1
        ld bc,4
        ldir
        xor a                   ; szures be
        ld (ds_all),a
        call ds_go
        call save_rect
    IFDEF PLUS
        call flip_now           ; a kockak egyszerre jelennek meg
        ld a,(vp_back)          ; a masik lapon: elem torlese, valtozott terulet
        call map_win
        call erase_back
        ld hl,bx1
        ld a,$EB
        call copy_rect
    ENDIF
    IFDEF PROFILE
        ld a,16 : out ($FE),a
    ENDIF
        ret

ds_go:
        ld a,(zmaxn)
ds_z:   ld (fz),a
        xor a
        ld (ds_pass),a
ds_p:   xor a
ds_y:   ld (fy),a
        xor a
ds_x:   ld (fx),a
        call cell_addr
        ld a,(hl)
        or a
        jr z,ds_next
        ld a,(ds_all)
        or a
        jr nz,ds_draw
        call foot_rect          ; D=x1 E=x2 B=y1 C=y2
        ld hl,nbx1+2 : ld a,(hl) : cp d : jr c,ds_next      ; nbx2 < x1
        ld hl,nbx1   : ld a,e : cp (hl) : jr c,ds_next      ; x2 < nbx1
        ld hl,nbx1+3 : ld a,(hl) : cp b : jr c,ds_next      ; nby2 < y1
        ld hl,nbx1+1 : ld a,c : cp (hl) : jr c,ds_next      ; y2 < nby1
        call bb_rect
ds_draw:
        ld a,(ds_pass)
        or a
        jr nz,ds_top
        call draw_sides
        jr ds_next
ds_top: call face_rect
        call draw_face
ds_next:
        call snd_poll
        ld a,(fx) : inc a : cp PIT_W : jr c,ds_x
        ld a,(fy) : inc a : cp PIT_H : jr c,ds_y
        ld a,(ds_pass)
        or a
        jr nz,ds_zn
        inc a
        ld (ds_pass),a
        jr ds_p
ds_zn:  ld a,(fz)
        dec a
        jp p,ds_z
        ret

; cell_addr: (fx,fy,fz) -> HL es (cell_ptr)
cell_addr:
        ld a,(fy) : add a,a : add a,a : add a,a
        ld hl,fx : add a,(hl)
        ld e,a
        ld a,(fz)
        call pit_addr
        ld (cell_ptr),hl
        ret

; face_rect: (fx,fy,fz) teteje -> D=x1 E=x2 B=y1 C=y2
face_rect:
        ld a,(fz)
        add a,a : add a,a : add a,a
        ld c,a
        ld a,(fx) : add a,c : ld l,a : ld h,SXTAB/256
        ld d,(hl) : inc l : ld e,(hl)
        ld a,(fy) : add a,c : ld l,a : ld h,SYTAB/256
        ld b,(hl) : inc l : ld c,(hl)
        ret

; foot_rect: a kocka teljes kepernyo-befoglaloja (z es z+1 melyseg) -> D E B C
foot_rect:
        ld a,(fz)
        add a,a : add a,a : add a,a
        ld (zb0),a
        add a,8
        ld (zb1),a
        ld h,SXTAB/256
        ld a,(fx) : ld c,a
        call .lo : ld d,a
        inc c
        call .hi : ld e,a
        ld h,SYTAB/256
        ld a,(fy) : ld c,a
        call .lo : ld b,a
        inc c
        call .hi
        ld c,a
        ret
.lo:    ld a,(zb0) : add a,c : ld l,a : ld a,(hl) : ld (fr_t),a
        ld a,(zb1) : add a,c : ld l,a : ld a,(hl)
        push hl : ld hl,fr_t : cp (hl) : jr c,$+3 : ld a,(hl) : pop hl
        ret
.hi:    ld a,(zb0) : add a,c : ld l,a : ld a,(hl) : ld (fr_t),a
        ld a,(zb1) : add a,c : ld l,a : ld a,(hl)
        push hl : ld hl,fr_t : cp (hl) : jr nc,$+3 : ld a,(hl) : pop hl
        ret

; draw_face: D=x1 E=x2 B=y1 C=y2, (fz) reteg -> fekete keret + retegminta
draw_face:
        xor a
        ld (pat0),a
        ld (pat1),a
        push bc
        push de
        call fillrect
        pop de
        pop bc
        inc d
        dec e
        ld a,e : cp d : ret c
        inc b
        dec c
        ld a,c : cp b : ret c
        push bc
        ld a,(fz)
        add a,a
        ld c,a
        ld b,0
        ld hl,LAYERPAT
        add hl,bc
        ld a,(hl) : ld (pat0),a
        inc hl
        ld a,(hl) : ld (pat1),a
        pop bc
        jp fillrect

;-----------------------------------------------------------------------------
; draw_sides: (fx,fy,fz) kocka kozep fele nezo, szabad oldallapjai
draw_sides:
        ld a,(fz)
        add a,a
        ld e,a
        ld d,0
        ld hl,SIDEPAT
        add hl,de
        ld a,(hl) : ld (pat0),a
        inc hl
        ld a,(hl) : ld (pat1),a
        ld a,(fz)
        add a,a : add a,a : add a,a
        ld (zb0),a
        add a,8
        ld (zb1),a
        ; +x lap (X = x+1 sik): 2x+2 < W es a jobb szomszed ures
        ld a,(fx) : add a,a : add a,2
        cp PIT_W
        jr nc,.nx1
        ld hl,(cell_ptr) : inc hl : ld a,(hl) : or a : jr nz,.nx1
        ld a,(fx) : inc a : ld c,a
        call sx0 : ld (t_s),a
        call sx1 : ld (t_e),a
        ld a,(fy) : ld c,a
        call sy0 : ld (e1a),a
        call sy1 : ld (e1b),a
        inc c
        call sy0 : ld (e2a),a
        call sy1 : ld (e2b),a
        call vtrap
.nx1:   ; -x lap (X = x sik): 2x > W es a bal szomszed ures
        ld a,(fx) : add a,a
        cp PIT_W+1
        jr c,.nx2
        ld hl,(cell_ptr) : dec hl : ld a,(hl) : or a : jr nz,.nx2
        ld a,(fx) : ld c,a
        call sx1 : ld (t_s),a
        call sx0 : ld (t_e),a
        ld a,(fy) : ld c,a
        call sy1 : ld (e1a),a
        call sy0 : ld (e1b),a
        inc c
        call sy1 : ld (e2a),a
        call sy0 : ld (e2b),a
        call vtrap
.nx2:   ; +y lap (Y = y+1 sik): 2y+2 < H es az also szomszed ures
        ld a,(fy) : add a,a : add a,2
        cp PIT_H
        jr nc,.ny1
        ld hl,(cell_ptr) : ld de,8 : add hl,de : ld a,(hl) : or a : jr nz,.ny1
        ld a,(fy) : inc a : ld c,a
        call sy0 : ld (t_s),a
        call sy1 : ld (t_e),a
        ld a,(fx) : ld c,a
        call sx0 : ld (e1a),a
        call sx1 : ld (e1b),a
        inc c
        call sx0 : ld (e2a),a
        call sx1 : ld (e2b),a
        call htrap
.ny1:   ; -y lap (Y = y sik): 2y > H es a felso szomszed ures
        ld a,(fy) : add a,a
        cp PIT_H+1
        ret c
        ld hl,(cell_ptr) : ld de,-8 : add hl,de : ld a,(hl) : or a : ret nz
        ld a,(fy) : ld c,a
        call sy1 : ld (t_s),a
        call sy0 : ld (t_e),a
        ld a,(fx) : ld c,a
        call sx1 : ld (e1a),a
        call sx0 : ld (e1b),a
        inc c
        call sx1 : ld (e2a),a
        call sx0 : ld (e2b),a
        jp htrap

; tablazat-olvasok: C = index, (zb0)/(zb1) a melyseg*8
sx0:    ld a,(zb0) : add a,c : ld l,a : ld h,SXTAB/256 : ld a,(hl) : ret
sx1:    ld a,(zb1) : add a,c : ld l,a : ld h,SXTAB/256 : ld a,(hl) : ret
sy0:    ld a,(zb0) : add a,c : ld l,a : ld h,SYTAB/256 : ld a,(hl) : ret
sy1:    ld a,(zb1) : add a,c : ld l,a : ld h,SYTAB/256 : ld a,(hl) : ret

; vtrap: oszlopok t_s..t_e; felso el e1a->e1b, also el e2a->e2b
vtrap:
        call trap_setup
.c:     ld a,(t_x) : ld d,a
        ld a,(acc1+1) : ld b,a
        ld a,(acc2+1) : ld e,a
        call vspan
        call trap_step
        jr nz,.c
        ret

; htrap: sorok t_s..t_e; bal el e1a->e1b, jobb el e2a->e2b
htrap:
        call trap_setup
.r:     ld a,(acc1+1) : ld d,a
        ld a,(acc2+1) : ld e,a
        cp d
        jr nc,$+4
        ld e,d
        ld d,a
        ld a,(t_x) : ld b,a : ld c,a
        call fillrect
        call trap_step
        jr nz,.r
        ret

; trap_setup: lepesszam, 8.8-as meredeksegek es akkumulatorok
trap_setup:
        ld a,(t_s)
        ld (t_x),a
        ld b,a
        ld a,(t_e)
        sub b
        ld (t_n),a
        inc a
        ld (t_cnt),a
        ld a,(e1a) : ld d,a : ld a,(e1b) : ld e,a
        call slope_n
        ld (sl1),hl
        ld a,(e2a) : ld d,a : ld a,(e2b) : ld e,a
        call slope_n
        ld (sl2),hl
        ld a,(e1a) : ld h,a : ld l,128 : ld (acc1),hl
        ld a,(e2a) : ld h,a : ld l,128 : ld (acc2),hl
        ret

; trap_step: akkumulatorok leptetese; Z=1 ha vege
trap_step:
        ld hl,(acc1) : ld de,(sl1) : add hl,de : ld (acc1),hl
        ld hl,(acc2) : ld de,(sl2) : add hl,de : ld (acc2),hl
        ld hl,t_x : inc (hl)
        ld hl,t_cnt : dec (hl)
        ret

; slope_n: D = kezdo, E = veg ertek, (t_n) lepes -> HL = (E-D)*256/n elojelesen
slope_n:
        ld a,(t_n)
        or a
        jr nz,.go
        ld hl,0
        ret
.go:    ld c,a
        ld a,e
        sub d
        jr c,.neg
        ld h,a
        ld l,0
        jr div_hl_c
.neg:   neg
        ld h,a
        ld l,0
        call div_hl_c
        xor a
        sub l
        ld l,a
        sbc a,a
        sub h
        ld h,a
        ret

; div_hl_c: HL = HL / C (elojel nelkul)
div_hl_c:
        xor a
        ld b,16
.l:     add hl,hl
        rla
        jr c,.s
        cp c
        jr c,.n
.s:     sub c
        inc l
.n:     djnz .l
        ret

;=============================================================================
; HANG: egycsatornas negyszogjel, kepkockankent leptetett effektek prioritassal
; effekt: lepesek (kepkockak, pitch also, pitch felso, hangero), 0 = vege
;=============================================================================

; snd_play: HL = effekt, A = prioritas (alacsonyabb nem szakit felbe magasabbat)
snd_play:
        ld e,a
        ld a,(snd_ptr+1)
        or a
        jr z,.go
        ld a,(snd_pri)
        cp e
        jr z,.go
        ret nc
.go:    ld a,e
        ld (snd_pri),a
        ld (snd_ptr),hl
        jr snd_next

; snd_tick: kepkockankent egyszer
snd_tick:
        ld a,(snd_ptr+1)
        or a
        ret z
        ld hl,snd_cnt
        dec (hl)
        ret nz
snd_next:
        ld hl,(snd_ptr)
        ld a,(hl)
        or a
        jr z,snd_stop
        ld (snd_cnt),a
        inc hl
        ld a,(hl)
        out ($04),a             ; pitch also 8 bit
        inc hl
        ld a,(hl)
        or $10                  ; pitch felso 4 bit + hang be
        out ($05),a
        inc hl
        ld a,(hl)
        add a,a
        add a,a
        or 1                    ; hangero (b2-b5) + 4 szinu mod
        out ($06),a
        inc hl
        ld (snd_ptr),hl
        ret

snd_stop:
        xor a
        out ($05),a
        ld a,1
        out ($06),a
        ld hl,0
        ld (snd_ptr),hl
        ret

; snd_poll: hosszu rajzolas kozben: ha eltelt egy kepkocka, lep egyet a hang
snd_poll:
        in a,($59)
        and $10
        ret nz
        out ($07),a
        push bc
        push de
        push hl
        call snd_tick
        pop hl
        pop de
        pop bc
        ret

;=============================================================================
; PRIMITIVEK
;=============================================================================
set_color:
        ld (cmask),a
        ld (xm_cm+1),a
        ld (ym_cm+1),a
        ret

; rowaddr: B = y  ->  HL = VRAM + y*64     (A, HL)
rowaddr:
        ld a,b
        rrca
        rrca
        ld l,a
        and $3F
ra_base:
        or VRAM/256             ; onmodosito: VRAM ($80) vagy U3 ($C0)
        ld h,a
        ld a,l
        and $C0
        ld l,a
        ret

; hline: B=y, D=x1, E=x2   (OR a cmask szinnel)
hline:
        ld a,e
        cp d
        jr nc,.o
        ld e,d
        ld d,a
.o:     call rowaddr
        ld a,d
        rrca : rrca : and $3F
        ld c,a
        or l
        ld l,a
        ld a,e
        rrca : rrca : and $3F
        sub c
        ld c,a
        push hl
        ld h,MASKTAB/256
        ld a,d : and 3 : ld l,a : ld d,(hl)
        ld a,e : and 3 : add a,4 : ld l,a : ld e,(hl)
        pop hl
        ld a,(cmask)
        ld b,a
        ld a,c
        or a
        jr nz,.multi
        ld a,d
        and e
        and b
        or (hl)
        ld (hl),a
        ret
.multi: ld a,d
        and b
        or (hl)
        ld (hl),a
        inc l
        dec c
        jr z,.last
.mid:   ld a,b
        or (hl)
        ld (hl),a
        inc l
        dec c
        jr nz,.mid
.last:  ld a,e
        and b
        or (hl)
        ld (hl),a
        ret

; vline: D=x, B=y1, E=y2  (OR, ket pixel/kor kibontva)
vline:
        ld a,e
        cp b
        jr nc,.o
        ld e,b
        ld b,a
.o:     ld a,e
        sub b
        inc a
        ld c,a                  ; pixelszam
        call rowaddr
        ld a,d
        rrca : rrca : and $3F
        or l
        ld l,a
        ld a,d
        and 3
        add a,8
        push hl
        ld l,a
        ld h,MASKTAB/256
        ld a,(cmask)
        and (hl)
        pop hl
        ld de,64
        srl c
        jr nc,.even
        ld b,a
        or (hl)
        ld (hl),a
        add hl,de
        ld a,b
.even:  inc c
        dec c
        ret z
        ld b,c
        ld c,a
.l:     ld a,(hl)
        or c
        ld (hl),a
        add hl,de
        ld a,(hl)
        or c
        ld (hl),a
        add hl,de
        djnz .l
        ret

; line: (D,E) -> (B,C)   altalanos Bresenham, onmodosito iranykoddal
line:
        ld a,b
        cp d
        jr nc,ln_ord
        ld a,d : ld d,b : ld b,a
        ld a,e : ld e,c : ld c,a
ln_ord: ld a,b
        sub d
        ld (ldx),a
        ld a,c
        sub e
        jr c,ln_up
        ld (ldy),a
        ld a,$C6                ; add a,n
        ld h,$24                ; inc h
        jr ln_dir
ln_up:  neg
        ld (ldy),a
        ld a,$D6                ; sub n
        ld h,$25                ; dec h
ln_dir: ld (xm_op),a
        ld (ym_op),a
        ld a,h
        ld (xm_inc),a
        ld (ym_inc),a
        ld b,e
        call rowaddr
        ld a,d
        rrca : rrca : and $3F
        or l
        ld l,a
        ld a,d
        and 3
        add a,8
        push hl
        ld l,a
        ld h,MASKTAB/256
        ld c,(hl)               ; pixelmaszk
        pop hl
        ld a,(ldy)
        ld d,a
        ld a,(ldx)
        cp d
        jr c,ln_ymaj
        ld (xm_dx+1),a
        ld b,a
        inc b
        srl a
        ld e,a
ln_xl:  ld a,c
xm_cm:  and $FF
        or (hl)
        ld (hl),a
        rrc c
        jr nc,ln_x1
        inc l
ln_x1:  ld a,e
        sub d
        jr nc,ln_x2
xm_dx:  add a,0
        ld e,a
        ld a,l
xm_op:  add a,64
        ld l,a
        jr nc,ln_x3
xm_inc: inc h
ln_x3:  djnz ln_xl
        ret
ln_x2:  ld e,a
        djnz ln_xl
        ret
ln_ymaj:
        ld e,a                  ; dx
        ld a,d                  ; dy
        ld (ym_dy+1),a
        ld b,a
        inc b
        srl a
        ld d,e                  ; D = dx
        ld e,a                  ; E = dy/2
ln_yl:  ld a,c
ym_cm:  and $FF
        or (hl)
        ld (hl),a
        ld a,l
ym_op:  add a,64
        ld l,a
        jr nc,ln_y1
ym_inc: inc h
ln_y1:  ld a,e
        sub d
        jr nc,ln_y2
ym_dy:  add a,0
        ld e,a
        rrc c
        jr nc,ln_y3
        inc l
ln_y3:  djnz ln_yl
        ret
ln_y2:  ld e,a
        djnz ln_yl
        ret

; vspan: D=x, B=y1, E=y2  csere-mod, sorparitas szerinti pat0/pat1
vspan:
        ld a,e
        cp b
        jr nc,.o
        ld e,b
        ld b,a
.o:     ld a,e
        sub b
        inc a
        push af                 ; pixelszam
        call rowaddr
        ld a,d
        rrca : rrca : and $3F
        or l
        ld l,a
        ld a,d
        and 3
        add a,8
        push hl
        ld l,a
        ld h,MASKTAB/256
        ld c,(hl)               ; pixelmaszk
        pop hl
        ld a,(pat1)
        ld e,a
        ld a,(pat0)
        xor e
        ld (vs_px+1),a
        bit 0,b
        jr nz,.odd
        xor e
        ld e,a
.odd:   pop af
        ld b,a
vs_l:   ld a,(hl) : xor e : and c : xor (hl) : ld (hl),a
        ld a,l : add a,64 : ld l,a
        jr nc,$+3 : inc h
        ld a,e
vs_px:  xor 0
        ld e,a
        djnz vs_l
        ret

; fillrect: D=x1 E=x2 B=y1 C=y2 (rendezett), csere-mod: paros sor pat0, paratlan pat1
fillrect:
        ld h,MASKTAB/256
        ld a,e : and 3 : add a,4 : ld l,a : ld a,(hl) : ld (fr_rm+1),a
        ld a,d : and 3 : ld l,a : ld a,(hl) : ld (fr_lm+1),a
        ld a,e : rrca : rrca : and $3F : ld l,a          ; x2 bajt
        ld a,d : rrca : rrca : and $3F : ld h,a          ; x1 bajt
        ld a,l
        sub h
        ld (fr_n+1),a
        jr nz,fr_m
        ld a,(fr_rm+1)
        ld l,a
        ld a,(fr_lm+1)
        and l
        ld (fr_lm+1),a
fr_m:   ld a,c
        sub b
        inc a
        ld c,a                  ; sorok szama
        ld a,h
        push af
        call rowaddr
        pop af
        or l
        ld l,a
        ld a,(pat1)
        ld e,a
        ld a,(pat0)
        xor e
        ld (fr_px+1),a
        bit 0,b
        jr nz,fr_row            ; paratlan sor: E = pat1
        xor e
        ld e,a                  ; paros sor: E = pat0
fr_row: push hl
fr_lm:  ld d,0
        ld a,(hl) : xor e : and d : xor (hl) : ld (hl),a
fr_n:   ld a,0
        or a
        jr z,fr_done
        ld b,a
        dec b
        jr z,fr_last
fr_mid: inc l
        ld (hl),e
        djnz fr_mid
fr_last:
        inc l
fr_rm:  ld d,0
        ld a,(hl) : xor e : and d : xor (hl) : ld (hl),a
fr_done:
        pop hl
        ld a,l : add a,64 : ld l,a
        jr nc,$+3 : inc h
        ld a,e
fr_px:  xor 0
        ld e,a
        dec c
        jr nz,fr_row
        ret

;=============================================================================
        align 256
MASKTAB:
        db $FF,$77,$33,$11      ; bal maszk: pixel p..3
        db $88,$CC,$EE,$FF      ; jobb maszk: pixel 0..q
        db $88,$44,$22,$11      ; egy pixel

        INCLUDE "tables.inc"
HOT_END:
        ASSERT HOT_END <= $8000         ; jatek kozben csak U0/U1 latszik
        INCLUDE "title.inc"             ; elejen a feliratok, utana a hideg adatok (U2-be is mehet)
        ASSERT STR_END <= $8000

IMAGE_END:
        ASSERT IMAGE_END < $B000        ; a BASIC verem a HI-MEM ($BFFF) alatt marad

;=============================================================================
; BSS (nem kerul a CAS-ba): az U3 vegen, a hattermasolat ($C000-$FBFF) utan
        ORG $FC00
BSS_START:
PIT         equ BSS_START
PIT_SIZE    equ PIT_D*64
            ORG PIT + PIT_SIZE
piece_px    ds 1
piece_py    ds 1
piece_pz    ds 1
piece_or    ds 1
try_px      ds 1
try_py      ds 1
try_pz      ds 1
try_or      ds 1
bx1         ds 1
by1         ds 1
bx2         ds 1
by2         ds 1
obx1        ds 1
oby1        ds 1
obx2        ds 1
oby2        ds 1
nbx1        ds 4
bbvalid     ds 1
bxp         ds 1
byp         ds 1
ex          ds 1
ey          ds 1
elen        ds 1
pb_x1       ds 1
pb_y0       ds 1
pb_y1       ds 1
ldx         ds 1
ldy         ds 1
cmask       ds 1
fx          ds 1
fy          ds 1
fz          ds 1
zb0         ds 1
zb1         ds 1
fr_t        ds 1
cell_ptr    ds 2
pat0        ds 1
pat1        ds 1
ds_all      ds 1
ds_pass     ds 1
zmaxn       ds 1
t_s         ds 1
t_e         ds 1
t_x         ds 1
t_n         ds 1
t_cnt       ds 1
e1a         ds 1
e1b         ds 1
e2a         ds 1
e2b         ds 1
sl1         ds 2
sl2         ds 2
acc1        ds 2
acc2        ds 2
gy1         ds 1
gy2         ds 1
tcol        ds 1
pc_col      ds 1
pc_y        ds 1
n_cnt       ds 1
tmpv        ds 3
NUMBUF      ds 9                   ; 8 jegy + lezaro 0
keys        ds 2
kprev       ds 2
knew        ds 2
repcnt      ds 1
fallcnt     ds 1
fallspeed   ds 1
dirty       ds 1
cleared     ds 1
seed        ds 2
hiscore     ds 3
an_cur      ds 1
an_div      ds 1
an_tick     ds 1
an_blink    ds 1
an_base     ds 2
snd_ptr     ds 2
snd_cnt     ds 1
snd_pri     ds 1
oldlevel    ds 1
score       ds 3
level       ds 1
layers      ds 2
cubes       ds 2
dropcnt     ds 1
STATS_LEN   equ $ - score
piece_vz    ds 1                   ; lathato melyseg negyedretegben
dropping    ds 1
bzq         ds 1
ezq         ds 1
eq_lo       ds 1
eq_hi       ds 1
pb_x0       ds 1
pb_z0       ds 1
pb_z1       ds 1
pb_a        ds 4
    IFDEF PLUS
vp_front    ds 1
vp_back     ds 1
flip_pend   ds 1
vp_win      ds 1
obA         ds 5                   ; laponkent: ervenyes, x1,y1,x2,y2
obB         ds 5
    ENDIF
BSS_END:
STACK_BOTTOM:
            ds $FFFE - $
STACK_TOP:
        ASSERT STACK_TOP - BSS_END >= 120

        SAVEBIN "blokk.bin", $19EF, IMAGE_END-$19EF
