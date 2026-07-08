;###################################################################################################################
; scroll_test.s — host-side unit test for scroll_rgn.inc, run under cc65's sim65.
;
;   make test
;
; The scrolling primitives are pure CPU memory moves over a flat 80x24 array of
; [char, color] cells. They touch no Atari or VBXE hardware, so the *exact same source*
; that the XEX builds can be assembled for a 6502 simulator and exercised directly.
;
; Screen model: cell(r,c) char at $A100 + r*160 + c*2, color at +1.
; fill_screen paints char = r+1 (so 0 can mean "blank") and color = $80|c, which lets a
; single check catch three separate classes of bug: rows moved to the wrong place, rows
; blanked that shouldn't be (or vice versa), and columns shifted within a row.
;
; Exit code is 0 on success, or the id of the first check that failed.

		.setcpu "6502"
		.feature labels_without_colons

		.export		_main

; --- what the includer must supply (mirrors ANSIVBXE_ca65.asm) ---

vbxe_screen_top	= $A100
text_color	= $82
scroll_top	= $B0
scroll_bot	= $B1
scr_src		= $B2
scr_dst		= $B4

; --- test-local zero page ---

exp_ptr		= $BA				; 2 bytes — expected-char table for the current check
chk_ptr		= $BC				; 2 bytes — row base being examined
chk_row		= $BE
chk_col		= $BF
exp_char	= $C0
exp_color	= $C1

		.segment "BSS"
sr_top:		.res	1
sr_bot:		.res	1
sr_n:		.res	1
sr_rows:	.res	1

		.segment "CODE"

		.include "scroll_rgn.inc"

;###################################################################################################################
; harness

BLANK		= 0				; expected-char value meaning "this row was blanked"

.proc fill_screen				; char = row+1, color = $80|col
		lda	#0
		sta	chk_row
row_loop	ldx	chk_row
		lda	row_addr_lo,x
		sta	chk_ptr
		lda	row_addr_hi,x
		sta	chk_ptr + 1
		ldy	#0
		ldx	#0
col_loop	lda	chk_row
		clc
		adc	#1			; char = row+1
		sta	(chk_ptr),y
		iny
		stx	chk_col			; color = $80 | ((char + col) & $7F)
		clc				; depends on BOTH row and column, so a single
		adc	chk_col			; dropped or misplaced byte anywhere in the row
		and	#$7F			; changes a sampled cell. Opacity bit always set.
		ora	#$80
		sta	(chk_ptr),y
		iny
		inx
		cpx	#80
		bne	col_loop
		inc	chk_row
		lda	chk_row
		cmp	#24
		bne	row_loop
		rts
.endproc

col_tab		.byte	0, 1, 39, 78, 79	; columns sampled per row (both ends included)
NCOLS		= 5

.proc check_rows
; exp_ptr -> 24 expected chars. Returns A=0 pass, A=1 fail.
; For a non-blank row the color must still be $80|col (columns did not shift);
; for a blank row the char must be 0 and the color must be text_color (opacity bit set,
; otherwise the cell is invisible on real hardware).
		lda	#0
		sta	chk_row
row_loop	ldx	chk_row
		lda	row_addr_lo,x
		sta	chk_ptr
		lda	row_addr_hi,x
		sta	chk_ptr + 1
		ldy	chk_row
		lda	(exp_ptr),y
		sta	exp_char

		ldx	#0
col_loop	lda	col_tab,x
		sta	chk_col
		lda	exp_char
		beq	blank_cell
		clc
		adc	chk_col			; $80 | ((char + col) & $7F), same law as fill_screen
		and	#$7F
		ora	#$80
		jmp	got_color
blank_cell	lda	text_color
got_color	sta	exp_color

		lda	chk_col
		asl				; byte offset = col*2
		tay
		lda	(chk_ptr),y
		cmp	exp_char
		bne	fail
		iny
		lda	(chk_ptr),y
		cmp	exp_color
		bne	fail

		inx
		cpx	#NCOLS
		bne	col_loop

		inc	chk_row
		lda	chk_row
		cmp	#24
		bne	row_loop
		lda	#0
		rts
fail		lda	#1
		rts
.endproc

.proc set_exp					; A/X = lo/hi of expected table
		sta	exp_ptr
		stx	exp_ptr + 1
		rts
.endproc

;###################################################################################################################
; expected screens (24 chars, one per row; 0 = blank)

e_up1		.byte	2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24, 0
e_up3		.byte	4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24, 0,0,0
e_up23		.byte	24, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
e_dn1		.byte	0, 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
e_dn3		.byte	0,0,0, 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21
e_dn23		.byte	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 1
e_allblank	.byte	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
e_lastrow	.byte	1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23, 0
; region [5,20], scroll up 2: rows 5..18 <- old 7..20, rows 19,20 blanked, rest untouched
e_rup2		.byte	1,2,3,4,5, 8,9,10,11,12,13,14,15,16,17,18,19,20,21, 0,0, 22,23,24
; region [5,20], scroll down 2: rows 5,6 blanked, rows 7..20 <- old 5..18, rest untouched
e_rdn2		.byte	1,2,3,4,5, 0,0, 6,7,8,9,10,11,12,13,14,15,16,17,18,19, 22,23,24
e_untouched	.byte	1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24
e_blank34	.byte	1,2,3, 0,0, 6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24

;###################################################################################################################

.macro	CHECK	id, tbl
		lda	#<tbl
		ldx	#>tbl
		jsr	set_exp
		jsr	check_rows
		beq	:+
		lda	#id
		rts
:
.endmacro

.proc _main
		lda	#$87			; default_attr: white on black, opacity set
		sta	text_color

; --- full screen, scroll up ---
		jsr	fill_screen
		lda	#0
		ldx	#23
		ldy	#1
		jsr	scroll_rgn_up
		CHECK	1, e_up1

		jsr	fill_screen
		lda	#0
		ldx	#23
		ldy	#3
		jsr	scroll_rgn_up
		CHECK	2, e_up3

		jsr	fill_screen		; n == height-1: one row survives
		lda	#0
		ldx	#23
		ldy	#23
		jsr	scroll_rgn_up
		CHECK	3, e_up23

		jsr	fill_screen		; n == height: blank_all via beq
		lda	#0
		ldx	#23
		ldy	#24
		jsr	scroll_rgn_up
		CHECK	4, e_allblank

		jsr	fill_screen		; n > height: blank_all via bcc
		lda	#0
		ldx	#23
		ldy	#99
		jsr	scroll_rgn_up
		CHECK	5, e_allblank

; --- full screen, scroll down ---
		jsr	fill_screen
		lda	#0
		ldx	#23
		ldy	#1
		jsr	scroll_rgn_down
		CHECK	6, e_dn1

		jsr	fill_screen
		lda	#0
		ldx	#23
		ldy	#3
		jsr	scroll_rgn_down
		CHECK	7, e_dn3

		jsr	fill_screen
		lda	#0
		ldx	#23
		ldy	#23
		jsr	scroll_rgn_down
		CHECK	8, e_dn23

		jsr	fill_screen
		lda	#0
		ldx	#23
		ldy	#24
		jsr	scroll_rgn_down
		CHECK	9, e_allblank

		jsr	fill_screen
		lda	#0
		ldx	#23
		ldy	#255
		jsr	scroll_rgn_down
		CHECK	10, e_allblank

; --- bounded region [5,20]: rows outside must not move ---
		jsr	fill_screen
		lda	#5
		ldx	#20
		ldy	#2
		jsr	scroll_rgn_up
		CHECK	11, e_rup2

		jsr	fill_screen
		lda	#5
		ldx	#20
		ldy	#2
		jsr	scroll_rgn_down
		CHECK	12, e_rdn2

; --- degenerate one-row region: this is IL/DL with the cursor on the bottom margin ---
		jsr	fill_screen
		lda	#23
		ldx	#23
		ldy	#1
		jsr	scroll_rgn_up
		CHECK	13, e_lastrow

		jsr	fill_screen
		lda	#23
		ldx	#23
		ldy	#1
		jsr	scroll_rgn_down
		CHECK	14, e_lastrow

; --- blank_rows on its own ---
		jsr	fill_screen
		lda	#3
		ldx	#2
		jsr	blank_rows
		CHECK	15, e_blank34

		jsr	fill_screen		; X = 0 must be a no-op, not 256 rows
		lda	#3
		ldx	#0
		jsr	blank_rows
		lda	#<e_untouched
		ldx	#>e_untouched
		jsr	set_exp
		jsr	check_rows
		beq	all_pass
		lda	#16
		rts

all_pass	lda	#0
		rts
.endproc

