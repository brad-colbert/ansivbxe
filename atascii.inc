;###################################################################################################################
; atascii.inc — ATASCII character-encoding primitives.
;
; Included by ANSIVBXE_ca65.asm (the real build) and by test/sim65/atascii_test.s
; (a host-side unit test run under cc65's sim65). Keep it free of Atari/VBXE
; hardware references so both includers can use it.
;
; The includer must define, before including:
;     atascii_mode      zero page, 0 = ANSI/CP437, 1 = ATASCII
;     atascii_inv       zero page, $00 or $80 — sticky keyboard inverse latch
;
; These are pure lookups over a byte, which is exactly why they live here: the
; mapping is easy to get subtly wrong and easy to verify exhaustively.

;###################################################################################################################
; character code -> VBXE glyph index

.proc to_glyph
; A = character code on entry, A = glyph index on exit.
;
; In ANSI mode this is the identity: every font in disk/ is CP437-ordered, so
; the byte value already IS the glyph index.
;
; In ATASCII mode the font is the OS ROM charset built by _vbxe_font_from_rom,
; which is in *internal* (screen code) order, not ATASCII order — so the code
; has to be permuted (see atascii_to_int below).  Bit 7 passes through
; untouched: it selects the inverted half of the font, which is exactly how
; ANTIC renders an inverse-video character.
;
; Preserves X (put_byte holds 0 there for its indexed-indirect store).
; Clobbers Y — safe, every caller of process_char already saves it.
		ldy	atascii_mode
		beq	done
		pha				; stash the code so we can recover bit 7
		and	#$7F
		tay				; Y = code without the inverse bit
		pla
		and	#$80			; A = the inverse bit alone
		ora	atascii_to_int,y	; merge it back onto the translated code
done		rts
.endproc

; ATASCII code ($00-$7F) -> Atari internal screen code.  The ROM charset is
; stored in internal order, which groups the glyphs differently from ATASCII:
; punctuation/digits/uppercase come first, then the graphics characters, then
; lowercase.  Generated rather than hand-written so the mapping is checkable
; by eye.
;
; The first entry matters beyond its own glyph: ATASCII space ($20) maps to
; internal $00, so every "blank this cell" site in the terminal — blank_rows,
; ED_adr, EL_adr and the two blitter fill bytes — keeps writing char $00 and
; keeps producing a blank cell in both modes, with no change.
atascii_to_int
		.repeat	32, i
			.byte	i + $40		; $00-$1F graphics  -> internal $40-$5F
		.endrep
		.repeat	64, i
			.byte	i		; $20-$5F punct/UC  -> internal $00-$3F
		.endrep
		.repeat	32, i
			.byte	i + $60		; $60-$7F lowercase -> internal $60-$7F
		.endrep

;###################################################################################################################
; keyboard byte -> what ATASCII mode should transmit

.proc ascii_to_atascii
; A = the byte keycode_table produced → A = what ATASCII mode should send.
;
; The two encodings already agree across $20-$7A, and CTRL+letter yields $01-$1A
; in both — ATASCII draws those as its graphics characters, which is exactly
; what CTRL+letter puts on the screen of a real Atari. Only the line and edit
; keys genuinely differ.
;
; The inverse latch is applied last and only to codes that actually have an
; inverse counterpart, so RETURN still sends a bare EOL while inverse is on,
; the way it does on hardware. $1B-$1F are excluded as well: setting bit 7
; there would turn ESC into EOL and the cursor keys into line-edit commands.
		cmp	#$0D
		beq	eol
		cmp	#$08
		beq	backspace
		cmp	#$09
		beq	tab

		cmp	#$1B
		bcc	apply_inverse		; $00-$1A graphics
		cmp	#$20
		bcc	done			; $1B-$1F would collide with the control set
		cmp	#$7B
		bcs	done			; $7B and up have no inverse form
apply_inverse	ora	atascii_inv
done		rts

eol		lda	#$9B
		rts
backspace	lda	#$7E
		rts
tab		lda	#$7F
		rts
.endproc
