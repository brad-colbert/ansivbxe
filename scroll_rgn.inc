;###################################################################################################################
; scroll_rgn.inc — CPU row-move primitives for the scrolling region.
;
; Included by ANSIVBXE_ca65.asm (the real build) and by test/sim65/scroll_test.s
; (a host-side unit test run under cc65's sim65). Keep it free of Atari/VBXE hardware
; references so both includers can use it.
;
; The includer must define, before including:
;     vbxe_screen_top   address of screen cell (0,0); rows are 160 bytes apart
;     text_color        zero page, current color byte (bit 7 = VBXE overlay opacity)
;     scroll_top        zero page, 0-based top row of the region
;     scroll_bot        zero page, 0-based bottom row of the region
;     scr_src, scr_dst  zero page, 2 bytes each (must not alias src_ptr/dst_ptr/counter)
;     sr_top, sr_bot, sr_n, sr_rows   one byte each, anywhere
;
; CPU row-move primitives for the scrolling region (IL/DL/SD/SU/RI).
;
; The whole 80x24 screen is CPU-visible: the MEMAC A window maps VBXE $7F000-$7FFFF to
; CPU $A000-$AFFF, so the screen is a flat 3840-byte array at vbxe_screen_top ($A100),
; 24 rows of 160 bytes, cell = [char, color]. No blitter needed, and none of these
; routines touch memac_bank_sel — the screen stays readable at every instruction boundary.
;
; Rows are always at least one full row (160 bytes) apart, so source and destination
; never overlap byte-wise. That means there is exactly ONE byte-copy loop; the direction
; of the move is carried entirely by the row-pointer stride (+160 or -160).
;
; All of these require the cursor to be OFF (cursor_toggle EORs $77 into the color byte
; at cursor_address; scrolling with it on bakes the inversion into the wrong cell).
; They clobber A, X, Y, scr_src, scr_dst and sr_* — but never src_ptr/dst_ptr/counter.

; row_addr_lo/hi[r] = vbxe_screen_top + r*160 for r = 0..23  (row 0 = $A100, row 23 = $AF60)

row_addr_lo	.repeat 24, r
		.byte	<(vbxe_screen_top + r*160)
		.endrepeat
row_addr_hi	.repeat 24, r
		.byte	>(vbxe_screen_top + r*160)
		.endrepeat

.proc copy_row_fwd				; copy 160 bytes (scr_src) -> (scr_dst)
		ldy	#159
loop		lda	(scr_src),y
		sta	(scr_dst),y
		dey
		bne	loop
		lda	(scr_src),y		; y = 0, the loop above stops one short
		sta	(scr_dst),y
		rts
.endproc

.proc blank_rows				; A = first row (0-23), X = row count (>= 1)
; Fills whole rows with char 0 and the current text_color. The color byte MUST be
; text_color and not $00: bit 7 is the overlay opacity bit, so a $00 color is invisible.
		cpx	#0
		beq	out			; guard: X=0 would loop 256 rows and trash $B000+
		stx	sr_rows
		tax				; X = first row
		lda	row_addr_lo,x
		sta	scr_dst
		lda	row_addr_hi,x
		sta	scr_dst + 1
row_loop	ldy	#0
cell_loop	lda	#0
		sta	(scr_dst),y		; character byte
		iny
		lda	text_color
		sta	(scr_dst),y		; color byte (bit 7 = opacity)
		iny
		cpy	#160
		bne	cell_loop
		lda	scr_dst
		clc
		adc	#160
		sta	scr_dst
		bcc	no_carry
		inc	scr_dst + 1
no_carry	dec	sr_rows
		bne	row_loop
out		rts
.endproc

.proc scroll_rgn_up				; A = top row, X = bottom row, Y = count (>= 1)
; Moves rows [top+n .. bot] up to [top .. bot-n], then blanks rows [bot-n+1 .. bot].
; If n >= region height, the whole region is blanked.
		sta	sr_top
		stx	sr_bot
		sty	sr_n

		txa				; A = bot
		sec
		sbc	sr_top			; bot - top
		clc
		adc	#1			; region height (>= 1)
		sec
		sbc	sr_n			; rows to move
		bcc	blank_all		; n > height
		beq	blank_all		; n == height
		sta	sr_rows

		ldx	sr_top			; scr_dst = row_addr(top)
		lda	row_addr_lo,x
		sta	scr_dst
		lda	row_addr_hi,x
		sta	scr_dst + 1

		lda	sr_top			; scr_src = row_addr(top + n)
		clc
		adc	sr_n
		tax
		lda	row_addr_lo,x
		sta	scr_src
		lda	row_addr_hi,x
		sta	scr_src + 1

row_loop	jsr	copy_row_fwd
		lda	scr_src			; stride +160
		clc
		adc	#160
		sta	scr_src
		bcc	src_ok
		inc	scr_src + 1
src_ok		lda	scr_dst
		clc
		adc	#160
		sta	scr_dst
		bcc	dst_ok
		inc	scr_dst + 1
dst_ok		dec	sr_rows
		bne	row_loop

		lda	sr_bot			; blank rows [bot-n+1 .. bot]
		sec
		sbc	sr_n
		clc
		adc	#1
		ldx	sr_n
		jmp	blank_rows		; tail call

blank_all	lda	sr_bot
		sec
		sbc	sr_top
		tax
		inx				; X = region height
		lda	sr_top
		jmp	blank_rows
.endproc

.proc scroll_rgn_down				; A = top row, X = bottom row, Y = count (>= 1)
; Moves rows [top .. bot-n] down to [top+n .. bot], then blanks rows [top .. top+n-1].
; Walks bottom-up so the not-yet-read source rows are never overwritten first.
; If n >= region height, the whole region is blanked.
		sta	sr_top
		stx	sr_bot
		sty	sr_n

		txa
		sec
		sbc	sr_top
		clc
		adc	#1			; region height
		sec
		sbc	sr_n			; rows to move
		bcc	blank_all
		beq	blank_all
		sta	sr_rows

		ldx	sr_bot			; scr_dst = row_addr(bot)
		lda	row_addr_lo,x
		sta	scr_dst
		lda	row_addr_hi,x
		sta	scr_dst + 1

		lda	sr_bot			; scr_src = row_addr(bot - n)
		sec
		sbc	sr_n
		tax
		lda	row_addr_lo,x
		sta	scr_src
		lda	row_addr_hi,x
		sta	scr_src + 1

row_loop	jsr	copy_row_fwd
		lda	scr_src			; stride -160
		sec
		sbc	#160
		sta	scr_src
		bcs	src_ok
		dec	scr_src + 1
src_ok		lda	scr_dst
		sec
		sbc	#160
		sta	scr_dst
		bcs	dst_ok
		dec	scr_dst + 1
dst_ok		dec	sr_rows
		bne	row_loop

		lda	sr_top			; blank rows [top .. top+n-1]
		ldx	sr_n
		jmp	blank_rows		; tail call

blank_all	lda	sr_bot
		sec
		sbc	sr_top
		tax
		inx
		lda	sr_top
		jmp	blank_rows
.endproc

.proc reset_margins				; full-screen scrolling region
		lda	#0
		sta	scroll_top
		lda	#23
		sta	scroll_bot
		rts
.endproc
