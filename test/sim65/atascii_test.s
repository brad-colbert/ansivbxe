;###################################################################################################################
; atascii_test.s — host-side unit test for atascii.inc and the row_*_char
; primitives in scroll_rgn.inc, run under cc65's sim65.
;
;   make test
;
; Both bodies of code under test are pure CPU work over zero page and a flat
; array of [char, color] cells, so the *exact same source* the XEX builds can be
; assembled for a 6502 simulator and exercised directly.
;
; Screen model: cell(r,c) char at $A100 + r*160 + c*2, color at +1.
;
; Exit code is 0 on success, or the id of the first check that failed.

		.setcpu "6502"
		.feature labels_without_colons

		.export		_main

; --- what the includes require (mirrors ANSIVBXE_ca65.asm) ---

vbxe_screen_top	= $A100
text_color	= $82
row		= $83
column		= $84
scroll_top	= $B0
scroll_bot	= $B1
scr_src		= $B2
scr_dst		= $B4
term_last_col	= $B7
atascii_mode	= $B8
atascii_inv	= $BA

; --- test-local zero page ---

chk_ptr		= $BC				; 2 bytes — row base being examined
chk_col		= $BE
t_code		= $BF				; character code under test
t_expect	= $C0

		.segment "BSS"
sr_top:		.res	1
sr_bot:		.res	1
sr_n:		.res	1
sr_rows:	.res	1
rc_last:	.res	1
rc_floor:	.res	1

		.segment "CODE"

		.include "atascii.inc"
		.include "scroll_rgn.inc"

;###################################################################################################################
; harness

.macro	FAILWITH id
		lda	#id
		rts
.endmacro

.proc fill_row
; Paint the cursor row with char = col+1 and color = $80|col, so a single sampled
; cell pins down both which column a byte came from and that the opacity bit
; survived. char is col+1 rather than col so 0 can mean "blanked".
		ldx	row
		lda	row_addr_lo,x
		sta	chk_ptr
		lda	row_addr_hi,x
		sta	chk_ptr + 1
		ldy	#0
		ldx	#0
loop		txa
		clc
		adc	#1
		sta	(chk_ptr),y		; char = col+1
		iny
		txa
		ora	#$80
		sta	(chk_ptr),y		; color = $80|col
		iny
		inx
		cpx	#80
		bne	loop
		rts
.endproc

.proc cell_char					; X = column → A = that cell's char byte
		stx	chk_col
		ldx	row
		lda	row_addr_lo,x
		sta	chk_ptr
		lda	row_addr_hi,x
		sta	chk_ptr + 1
		lda	chk_col
		asl				; byte offset = col*2
		tay
		lda	(chk_ptr),y
		rts
.endproc

.proc cell_color				; X = column → A = that cell's color byte
		stx	chk_col
		ldx	row
		lda	row_addr_lo,x
		sta	chk_ptr
		lda	row_addr_hi,x
		sta	chk_ptr + 1
		lda	chk_col
		asl
		tay
		iny
		lda	(chk_ptr),y
		rts
.endproc

;###################################################################################################################

.proc _main
		lda	#$87			; white on black, opacity bit set
		sta	text_color

;-------------------------------------------------------------------------------
; 1-4: to_glyph is the identity in ANSI mode, for every one of the 256 codes.
; A regression here would corrupt every CP437 font in the menu.

		lda	#$00
		sta	atascii_mode
		lda	#$00
		sta	t_code
@ansi_loop	lda	t_code
		jsr	to_glyph
		cmp	t_code
		beq	@ansi_next
		FAILWITH 1
@ansi_next	inc	t_code
		bne	@ansi_loop

;-------------------------------------------------------------------------------
; 2: ATASCII mode maps each of the four code bands to the right internal band.
; Spot-check the boundary of every band rather than trusting the .repeat blocks.

		lda	#$01
		sta	atascii_mode

		lda	#$00			; graphics band start: $00 -> $40
		jsr	to_glyph
		cmp	#$40
		beq	:+
		FAILWITH 2
:		lda	#$1F			; graphics band end:   $1F -> $5F
		jsr	to_glyph
		cmp	#$5F
		beq	:+
		FAILWITH 3
:		lda	#$20			; space:               $20 -> $00
		jsr	to_glyph
		cmp	#$00
		beq	:+
		FAILWITH 4
:		lda	#$41			; 'A':                 $41 -> $21
		jsr	to_glyph
		cmp	#$21
		beq	:+
		FAILWITH 5
:		lda	#$5F			; punct/UC band end:   $5F -> $3F
		jsr	to_glyph
		cmp	#$3F
		beq	:+
		FAILWITH 6
:		lda	#$60			; lowercase band:      $60 -> $60
		jsr	to_glyph
		cmp	#$60
		beq	:+
		FAILWITH 7
:		lda	#$7F			; lowercase band end:  $7F -> $7F
		jsr	to_glyph
		cmp	#$7F
		beq	:+
		FAILWITH 8

;-------------------------------------------------------------------------------
; 9-10: bit 7 passes through to select the inverted half of the font, and the
; low seven bits are still translated underneath it.
:
		lda	#$A0			; inverse space -> inverse blank
		jsr	to_glyph
		cmp	#$80
		beq	:+
		FAILWITH 9
:		lda	#$C1			; inverse 'A'
		jsr	to_glyph
		cmp	#$A1
		beq	:+
		FAILWITH 10

;-------------------------------------------------------------------------------
; 11: every translated glyph must stay inside 0-255 with bit 7 owned solely by
; the inverse flag — i.e. the 7-bit translation never itself sets bit 7.
:
		lda	#$00
		sta	t_code
@hi_loop	lda	t_code
		jsr	to_glyph
		bpl	@hi_next		; bit 7 clear, as it must be for a $00-$7F input
		FAILWITH 11
@hi_next	inc	t_code
		lda	t_code
		cmp	#$80
		bne	@hi_loop

;-------------------------------------------------------------------------------
; 12: to_glyph preserves X. put_byte keeps 0 there for its (zp,X) store, so
; clobbering X would write the glyph to the wrong address entirely.

		ldx	#$5A
		lda	#$41
		jsr	to_glyph
		cpx	#$5A
		beq	:+
		FAILWITH 12

;-------------------------------------------------------------------------------
; 13-17: keyboard encoding. The line/edit keys are remapped; everything else in
; the shared range passes through untouched.
:
		lda	#$00
		sta	atascii_inv

		lda	#$0D			; RETURN -> EOL
		jsr	ascii_to_atascii
		cmp	#$9B
		beq	:+
		FAILWITH 13
:		lda	#$08			; BACKSPACE
		jsr	ascii_to_atascii
		cmp	#$7E
		beq	:+
		FAILWITH 14
:		lda	#$09			; TAB
		jsr	ascii_to_atascii
		cmp	#$7F
		beq	:+
		FAILWITH 15
:		lda	#$41			; 'A' is the same in both encodings
		jsr	ascii_to_atascii
		cmp	#$41
		beq	:+
		FAILWITH 16
:		lda	#$1B			; ESC passes through
		jsr	ascii_to_atascii
		cmp	#$1B
		beq	:+
		FAILWITH 17

;-------------------------------------------------------------------------------
; 18-22: with the inverse latch set, printable codes gain bit 7 but the control
; codes must not — otherwise ESC would silently become EOL and CTRL+comma would
; become delete-line.
:
		lda	#$80
		sta	atascii_inv

		lda	#$41			; 'A' -> inverse 'A'
		jsr	ascii_to_atascii
		cmp	#$C1
		beq	:+
		FAILWITH 18
:		lda	#$01			; CTRL+A graphics -> inverse form
		jsr	ascii_to_atascii
		cmp	#$81
		beq	:+
		FAILWITH 19
:		lda	#$1B			; ESC must NOT become $9B (EOL)
		jsr	ascii_to_atascii
		cmp	#$1B
		beq	:+
		FAILWITH 20
:		lda	#$0D			; RETURN still sends a bare EOL
		jsr	ascii_to_atascii
		cmp	#$9B
		beq	:+
		FAILWITH 21
:		lda	#$7C			; $7B+ has no inverse form
		jsr	ascii_to_atascii
		cmp	#$7C
		beq	:+
		FAILWITH 22
:
		lda	#$00
		sta	atascii_inv

;-------------------------------------------------------------------------------
; 23-26: row_delete_char at mid-row, 80 columns. Cells left of the cursor are
; untouched, cells at and right of it shift left by one, the last cell blanks.

		lda	#79
		sta	term_last_col
		lda	#5
		sta	row
		jsr	fill_row
		lda	#10
		sta	column
		jsr	row_delete_char

		ldx	#9			; left of the cursor: untouched
		jsr	cell_char
		cmp	#10
		beq	:+
		FAILWITH 23
:		ldx	#10			; cursor cell now holds what was at column 11
		jsr	cell_char
		cmp	#12
		beq	:+
		FAILWITH 24
:		ldx	#79			; last cell blanked, with a visible colour
		jsr	cell_char
		cmp	#$00
		beq	:+
		FAILWITH 25
:		ldx	#79
		jsr	cell_color
		cmp	text_color
		beq	:+
		FAILWITH 26

;-------------------------------------------------------------------------------
; 27-30: row_insert_char at mid-row. Cells at and right of the cursor shift
; right, the cursor cell blanks, and the cell that fell off the end is gone.
:
		jsr	fill_row
		lda	#10
		sta	column
		jsr	row_insert_char

		ldx	#9			; left of the cursor: untouched
		jsr	cell_char
		cmp	#10
		beq	:+
		FAILWITH 27
:		ldx	#10			; cursor cell vacated
		jsr	cell_char
		cmp	#$00
		beq	:+
		FAILWITH 28
:		ldx	#11			; what was at column 10 moved right one
		jsr	cell_char
		cmp	#11
		beq	:+
		FAILWITH 29
:		ldx	#79			; last cell holds what was at column 78
		jsr	cell_char
		cmp	#79
		beq	:+
		FAILWITH 30

;-------------------------------------------------------------------------------
; 31-33: column 0 — the whole row shifts. This is the case where an off-by-one
; in the loop bound walks off the front of the row into the previous one.
:
		jsr	fill_row
		lda	#0
		sta	column
		jsr	row_delete_char

		ldx	#0
		jsr	cell_char
		cmp	#2
		beq	:+
		FAILWITH 31
:		ldx	#78
		jsr	cell_char
		cmp	#80
		beq	:+
		FAILWITH 32
:		ldx	#79
		jsr	cell_char
		cmp	#$00
		beq	:+
		FAILWITH 33

;-------------------------------------------------------------------------------
; 34-36: cursor already on the last column. There is nothing to shift, so both
; operations degenerate to "blank that one cell" and must not touch column 78.
:
		jsr	fill_row
		lda	#79
		sta	column
		jsr	row_delete_char

		ldx	#78
		jsr	cell_char
		cmp	#79
		beq	:+
		FAILWITH 34
:		ldx	#79
		jsr	cell_char
		cmp	#$00
		beq	:+
		FAILWITH 35

:		jsr	fill_row
		lda	#79
		sta	column
		jsr	row_insert_char
		ldx	#78
		jsr	cell_char
		cmp	#79
		beq	:+
		FAILWITH 36

;-------------------------------------------------------------------------------
; 37-40: 40-column ATASCII mode. Both operations must stop at term_last_col and
; leave columns 40-79 completely alone — that boundary is the whole reason
; term_last_col exists rather than a hard-coded 79.
:
		lda	#39
		sta	term_last_col
		jsr	fill_row
		lda	#10
		sta	column
		jsr	row_delete_char

		ldx	#10			; shifted, as in the 80-column case
		jsr	cell_char
		cmp	#12
		beq	:+
		FAILWITH 37
:		ldx	#39			; the 40-column right edge blanks
		jsr	cell_char
		cmp	#$00
		beq	:+
		FAILWITH 38
:		ldx	#40			; ...and column 40 is untouched
		jsr	cell_char
		cmp	#41
		beq	:+
		FAILWITH 39
:		ldx	#79			; ...as is the far end of the physical row
		jsr	cell_char
		cmp	#80
		beq	:+
		FAILWITH 40

:		jsr	fill_row
		lda	#10
		sta	column
		jsr	row_insert_char
		ldx	#40			; insert must not push a cell past the margin
		jsr	cell_char
		cmp	#41
		beq	:+
		FAILWITH 41
:		ldx	#39
		jsr	cell_char
		cmp	#39
		beq	:+
		FAILWITH 42

;-------------------------------------------------------------------------------
:		lda	#0			; all checks passed
		rts
.endproc
