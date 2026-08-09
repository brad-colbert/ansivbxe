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
;   and, for row_insert_char / row_delete_char only:
;     row               zero page, 0-based cursor row
;     column            zero page, 0-based cursor column
;     term_last_col     zero page, highest column the row operations may touch
;     rc_last, rc_floor one byte each, anywhere
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

;###################################################################################################################
; Within-row cell moves, for ATASCII insert/delete character ($FF/$FE).
;
; Both work on the cursor row between `column` and `term_last_col` inclusive, so
; in 40-column ATASCII mode they leave columns 40-79 alone. Cells are 2 bytes,
; and the shift is exactly one cell, so both routines set up scr_dst at the row
; base and scr_src one cell further along and let a single Y index walk the pair
; — the same trick copy_row_fwd uses between rows.
;
; Like the row movers above, these require the cursor to be OFF, and they
; clobber A, X, Y, scr_src, scr_dst, rc_last and rc_floor.

.proc row_setup_ptrs				; scr_dst = row base, scr_src = row base + one cell
; Also computes rc_last = byte offset of the last writable cell in the row and
; rc_floor = byte offset of the cursor cell. Clobbers A, X.
		lda	row
		tax
		lda	row_addr_lo,x
		sta	scr_dst
		clc
		adc	#2			; one cell further along the same row
		sta	scr_src
		lda	row_addr_hi,x
		sta	scr_dst + 1
		adc	#0			; propagate the carry from the low byte
		sta	scr_src + 1

		lda	term_last_col		; max 79, so *2 cannot overflow a byte
		asl
		sta	rc_last
		lda	column
		asl
		sta	rc_floor
		rts
.endproc

.proc row_delete_char				; pull cells left over the cursor cell
; cell[c] <- cell[c+1] for c = column .. term_last_col-1, then blank the last cell.
		jsr	row_setup_ptrs
		ldy	rc_floor
@loop		cpy	rc_last
		bcs	@blank			; reached the last cell: nothing left to pull in
		lda	(scr_src),y		; character
		sta	(scr_dst),y
		iny
		lda	(scr_src),y		; colour
		sta	(scr_dst),y
		iny
		jmp	@loop
@blank		lda	#0			; Y = rc_last — vacate the rightmost cell
		sta	(scr_dst),y
		iny
		lda	text_color		; NOT $00: bit 7 is the overlay opacity bit
		sta	(scr_dst),y
		rts
.endproc

.proc row_insert_char				; push cells right, opening a hole at the cursor
; cell[c] <- cell[c-1] for c = term_last_col .. column+1, then blank the cursor cell.
; Walks downward so a cell is read before it is overwritten.
		jsr	row_setup_ptrs

		lda	rc_last
		sec
		sbc	#2			; start at the second-to-last cell
		bcc	@blank			; row has no room to shift at all
		cmp	rc_floor
		bcc	@blank			; cursor is at or past the last cell
		tay
@loop		lda	(scr_dst),y		; cell[c-1] ...
		sta	(scr_src),y		; ... becomes cell[c]
		iny
		lda	(scr_dst),y
		sta	(scr_src),y
		tya				; step back one cell: Y is at the colour byte,
		sec				; so that is minus 3, not minus 2
		sbc	#3
		bcc	@blank			; walked off the front of the row
		cmp	rc_floor
		bcc	@blank			; walked past the cursor cell
		tay
		jmp	@loop

@blank		ldy	rc_floor		; vacate the cursor cell
		lda	#0
		sta	(scr_dst),y
		iny
		lda	text_color
		sta	(scr_dst),y
		rts
.endproc
