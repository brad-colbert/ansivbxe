;######################################################################################################################################
;
;  vbxe_lib.asm — VBXE library for cc65/ca65
;
;  Provides VBXE initialisation, file-loading, shutdown and RAM-clear as
;  callable procedures.  All four functions obey the cc65 __fastcall__
;  convention (single pointer argument passed in A/X; return value in A/X).
;  They are therefore callable from both C and assembly.
;
;  Exported symbols (underscore prefix = cc65 C linkage):
;    _vbxe_init         — detect FX core, save SDMCTL, open MEMAC window
;    _vbxe_load_files   — load font+palette from disk, copy XDL+BCBs, enable display
;    _vbxe_shutdown     — hide VBXE overlay, close MEMAC, restore SDMCTL
;    _vbxe_clear_ram    — zero-fill all 512 K of VBXE RAM via blitter
;
;  Assembly callers: JSR _vbxe_init etc.  A/X on entry for _vbxe_load_files.
;  C callers:        #include "vbxe_lib.h" and call as normal C functions.
;
;######################################################################################################################################

	.setcpu		"6502"
	.feature	labels_without_colons
	.feature	org_per_seg

	.include	"atarios_ca65.inc"
	.include	"atarihardware_ca65.inc"
	.include	"VBXE_ca65.inc"

;----------------------------------------------------------------------
; Fixed zero-page addresses — must match the calling program's ZP layout
;----------------------------------------------------------------------

vbxe_mem_base	= $A000		; CPU address of MEMAC A window

; Shared ZP temporaries (same addresses used by ANSIVBXE_ca65.asm)
src_ptr		= $85		; 2-byte source pointer for mem_move
dst_ptr		= $87		; 2-byte destination pointer for mem_move
counter		= $89		; 2-byte byte-count for mem_move

saved_sdmctl	= $9F		; SDMCTL saved by _vbxe_init, restored by _vbxe_shutdown

;----------------------------------------------------------------------
; Exports
;----------------------------------------------------------------------

	.export	_vbxe_init
	.export	_vbxe_load_files
	.export	_vbxe_shutdown
	.export	_vbxe_clear_ram

;----------------------------------------------------------------------
; BSS: local temporaries used by _vbxe_load_files
;   (zero-initialised at load time; not valid until _vbxe_load_files is called)
;----------------------------------------------------------------------

	.segment "BSS"

vl_font_ptr	.res 2		; extracted font_path pointer (lo, hi)
vl_pal_ptr	.res 2		; extracted pal_path pointer  (lo, hi)
vl_xdl_ptr	.res 2		; extracted xdl_data pointer  (lo, hi)
vl_xdl_sz	.res 2		; extracted xdl_size          (lo, hi)

;######################################################################################################################################
;
;  CODE segment — all four exported functions
;
;######################################################################################################################################

	.segment "CODE"

;======================================================================
;
;  int __fastcall__ vbxe_init (void)
;
;  Detect the VBXE FX core, save SDMCTL, disable ANTIC DMA (except
;  instruction fetch), open the MEMAC A window as a 4 K CPU-accessible
;  window at $A000 pointing to VBXE bank 0.
;
;  Returns: A=1, X=0 on success
;           A=0, X=0 if no VBXE or core version < $10 (not FX)
;
;  Must be called before any other _vbxe_* function.
;
;======================================================================

.proc _vbxe_init

		lda	core_version
		cmp	#$10			; accept FX-compatible core versions $10 and above
		bcc	@no_vbxe

		; FX-compatible core detected
		lda	SDMCTL
		sta	saved_sdmctl
		lda	#$20			; instruction-fetch only — shut off ANTIC display DMA
		sta	SDMCTL

		lda	#$00
		sta	memac_b_control		; disable MEMAC B window

		lda	#(>vbxe_mem_base)|$8	; 4 K window ($00), CPU access enabled (MCE bit 3)
		sta	memac_control

		lda	#$80			; bank 0, window enable bit set
		sta	memac_bank_sel

		ldx	#0
		lda	#1			; return success (sets Z=0 for assembly BNE callers)
		rts

@no_vbxe
		ldx	#0
		lda	#0			; return failure (sets Z=1 for assembly BNE callers)
		rts

.endproc


;======================================================================
;
;  int __fastcall__ vbxe_load_files (vbxe_load_cfg_t *cfg)
;
;  Load the font and palette files from disk, program the VBXE palette
;  registers, copy the XDL + BCB block into VBXE RAM at $0800, enable
;  the XDL, switch the MEMAC window to display RAM, and zero the screen
;  buffer.
;
;  On entry: A = lo byte of cfg pointer, X = hi byte of cfg pointer.
;
;  cfg points to a vbxe_load_cfg_t (see vbxe_lib.h):
;    offset 0-1 : font_path  (char *) — Atari path string, e.g. "D:IBMPC.FNT",$9B
;    offset 2-3 : pal_path   (char *) — Atari path string, e.g. "D:ANSI.PAL",$9B
;    offset 4-5 : xdl_data   (void *) — pointer to XDL+BCB bytes in CPU RAM
;    offset 6-7 : xdl_size   (unsigned int) — byte count of XDL+BCB block
;
;  Uses IOCB 1 ($10).  Requires MEMAC already open (call _vbxe_init first).
;
;  Returns: A=1, X=0 on success
;           A=0, X=0 on any CIO I/O error (IOCB left open — caller should close)
;
;======================================================================

.proc _vbxe_load_files

		; ---- save cfg pointer in src_ptr for indirect reads ----
		sta	src_ptr
		stx	src_ptr+1

		; ---- extract the four fields from the cfg struct ----
		ldy	#0
		lda	(src_ptr),y		; font_path lo
		sta	vl_font_ptr
		iny
		lda	(src_ptr),y		; font_path hi
		sta	vl_font_ptr+1
		iny
		lda	(src_ptr),y		; pal_path lo
		sta	vl_pal_ptr
		iny
		lda	(src_ptr),y		; pal_path hi
		sta	vl_pal_ptr+1
		iny
		lda	(src_ptr),y		; xdl_data lo
		sta	vl_xdl_ptr
		iny
		lda	(src_ptr),y		; xdl_data hi
		sta	vl_xdl_ptr+1
		iny
		lda	(src_ptr),y		; xdl_size lo
		sta	vl_xdl_sz
		iny
		lda	(src_ptr),y		; xdl_size hi
		sta	vl_xdl_sz+1

		; ---- close IOCB 1 in case it is already open ----
		ldx	#$10
		lda	#$0C
		sta	ICCOM+$10
		jsr	CIOV

		; ---- open the font file on IOCB 1 ----
		ldx	#$10
		lda	#$03			; CMD_OPEN
		sta	ICCOM+$10
		lda	vl_font_ptr		; buffer address = pointer to path string
		sta	ICBA+$10
		lda	vl_font_ptr+1
		sta	ICBA+$11
		lda	#$04			; OREAD
		sta	ICAX1+$10
		lda	#$00
		sta	ICAX2+$10
		jsr	CIOV
		bpl	@font_open_ok
		jmp	@io_error
@font_open_ok

		; ---- set MEMAC bank 0 so $A000-$AFFF = VBXE $0000-$0FFF ----
		lda	#$80
		sta	memac_bank_sel

		; ---- read the 2 K font into VBXE $0000 (CPU $A000) ----
		ldx	#$10
		lda	#$07			; CMD_GET_CHARS
		sta	ICCOM+$10
		lda	#$00			; buffer lo = $00 → address $A000
		sta	ICBA+$10
		lda	#>vbxe_mem_base		; buffer hi = $A0
		sta	ICBA+$11
		lda	#$00			; buffer length lo = 0 ($0800 = 2 K)
		sta	ICBL+$10
		lda	#$08			; buffer length hi = $08
		sta	ICBL+$11
		jsr	CIOV
		bpl	@font_read_ok
		jmp	@io_error
@font_read_ok

		; ---- close the font file ----
		ldx	#$10
		lda	#$0C
		sta	ICCOM+$10
		jsr	CIOV

		; ---- open the palette file on IOCB 1 ----
		ldx	#$10
		lda	#$03
		sta	ICCOM+$10
		lda	vl_pal_ptr
		sta	ICBA+$10
		lda	vl_pal_ptr+1
		sta	ICBA+$11
		lda	#$04
		sta	ICAX1+$10
		lda	#$00
		sta	ICAX2+$10
		jsr	CIOV
		bpl	@pal_open_ok
		jmp	@io_error
@pal_open_ok

		; ---- read 48 bytes of palette data into VBXE $0800 (CPU $A800) ----
		ldx	#$10
		lda	#$07
		sta	ICCOM+$10
		lda	#$00			; buffer lo = $00 → address $A800
		sta	ICBA+$10
		lda	#>vbxe_mem_base + $08	; buffer hi = $A8  ($A0 + $08)
		sta	ICBA+$11
		lda	#$30			; buffer length = 48 bytes
		sta	ICBL+$10
		lda	#$00
		sta	ICBL+$11
		jsr	CIOV
		bpl	@pal_read_ok
		jmp	@io_error
@pal_read_ok

		; ---- close the palette file ----
		ldx	#$10
		lda	#$0C
		sta	ICCOM+$10
		jsr	CIOV

		; ---- program VBXE palette registers from the loaded data at VBXE $0800 ----
		; Palette data at CPU $A800 (VBXE $0800 via MEMAC bank $80):
		;   16 colours × 3 bytes (R,G,B) = 48 bytes covering both foreground and background.
		;
		; Foreground layout: 16 FG colours, loaded 8 times = 128 entries (CSEL 0-127)
		; Background layout: 8 BG colours, each loaded 16 times = 128 entries (CSEL 128-255)

		lda	#$00
		sta	psel
		sta	csel

		; --- foreground: outer loop 8 repetitions, inner loop 16 colours (48 bytes) ---
		ldy	#$00
@fore_outer
		ldx	#$00
@fore_inner
		lda	vbxe_mem_base + $0800, x	; red
		sta	cr
		lda	vbxe_mem_base + $0801, x	; green
		sta	cg
		lda	vbxe_mem_base + $0802, x	; blue
		sta	cb
		inc	csel
		inx
		inx
		inx
		cpx	#$30			; 16 colours × 3 bytes = $30
		bne	@fore_inner
		iny
		cpy	#$08			; 8 repetitions
		bne	@fore_outer

		; --- background: outer loop 8 colours (3 bytes each), inner loop 16 entries each ---
		ldy	#$00
@back_outer
		ldx	#$00
@back_inner
		lda	vbxe_mem_base + $0800, y	; red  (fixed for this outer iteration)
		sta	cr
		lda	vbxe_mem_base + $0801, y	; green
		sta	cg
		lda	vbxe_mem_base + $0802, y	; blue
		sta	cb
		inc	csel
		inx
		cpx	#$10			; 16 entries per background colour
		bne	@back_inner
		iny
		iny
		iny				; advance by 3 bytes to next colour
		cpy	#$18			; 8 background colours × 3 = $18
		bne	@back_outer

		; ---- copy XDL + BCB block from CPU RAM to VBXE $0800 ----
		; This overwrites the temporary palette data (already programmed above).
		lda	vl_xdl_ptr
		sta	src_ptr
		lda	vl_xdl_ptr+1
		sta	src_ptr+1

		lda	#<(vbxe_mem_base + $0800)	; = $00
		sta	dst_ptr
		lda	#>(vbxe_mem_base + $0800)	; = $A8  (CPU $A800 = VBXE $0800)
		sta	dst_ptr+1

		; counter = xdl_size - 1  (mem_move copies counter+1 bytes)
		lda	vl_xdl_sz
		sta	counter
		lda	vl_xdl_sz+1
		sta	counter+1
		lda	counter
		bne	@no_borrow
		dec	counter+1
@no_borrow
		dec	counter

		jsr	mem_move

		; ---- set XDL base address to VBXE $000800 ----
		lda	#$00
		sta	xdl_adr			; low byte
		lda	#$08
		sta	xdl_adr_mid		; middle byte
		lda	#$00
		sta	xdl_adr_high		; high byte

		; ---- enable XDL display (bit 0) with colour 0 opaque (bit 2) ----
		lda	#$05
		sta	video_control

		; ---- switch MEMAC window to display RAM bank $FF (VBXE $7F000-$7FFFF) ----
		lda	#$FF
		sta	memac_bank_sel

		; ---- zero the screen buffer: VBXE $7F100-$7FFFF, CPU $A100-$AFFF ----
		; 15 pages × 256 bytes = 3840 bytes.  A=0 stored to every byte.
		lda	#$00
		sta	dst_ptr
		lda	#$A1
		sta	dst_ptr+1		; dst_ptr → $A100 (VBXE $7F100 via MEMAC $FF)
		ldx	#15			; 15 full pages
		lda	#$00			; explicit: A must be $00 for the fill
@pg
		ldy	#$00
@by
		sta	(dst_ptr),y
		iny
		bne	@by
		inc	dst_ptr+1
		dex
		bne	@pg

		ldx	#0
		lda	#1			; return success (sets Z=0 for assembly BNE callers)
		rts

@io_error
		ldx	#0
		lda	#0			; return failure (sets Z=1 for assembly BNE callers)
		rts

.endproc


;======================================================================
;
;  void __fastcall__ vbxe_shutdown (void)
;
;  Make the VBXE overlay invisible by patching the XDL's first OVOFF
;  entry to cover all 216 visible scanlines, then disable the MEMAC
;  window and restore SDMCTL to the value saved by _vbxe_init.
;
;  Assumes _vbxe_load_files was called and that the XDL was loaded to
;  VBXE $0800 with the OVOFF scanline count at VBXE $0802.
;
;======================================================================

.proc _vbxe_shutdown

		; Open bank 0 so we can patch the XDL at VBXE $0802 (CPU $A802)
		lda	#$80
		sta	memac_bank_sel

		lda	#216-1
		sta	vbxe_mem_base + $802	; patch OVOFF line count — covers full display

		lda	#$01			; XDL enabled, no_trans clear — OVOFF hides everything
		sta	video_control

		; Disable MEMAC A window
		lda	#$00
		sta	memac_bank_sel		; clear enable bit
		sta	memac_control		; clear MCE (CPU access disabled)

		; Restore ANTIC DMA
		lda	saved_sdmctl
		sta	SDMCTL

		rts

.endproc


;======================================================================
;
;  void __fastcall__ vbxe_clear_ram (void)
;
;  Zero-fill all 512 K of VBXE RAM using four chained blitter control
;  blocks.  The BCB table is copied to VBXE bank 0 first, then the
;  blitter is triggered and polled to completion.
;
;  Requires MEMAC already open (call _vbxe_init first).
;  Normally called once after _vbxe_init and before _vbxe_load_files.
;
;======================================================================

.proc _vbxe_clear_ram

		; ---- copy the BCB table to VBXE $0000 via MEMAC bank 0 ----
		lda	#$80
		sta	memac_bank_sel		; bank 0: $A000-$AFFF = VBXE $0000-$0FFF

		lda	#<clear_ram_bcb
		sta	src_ptr
		lda	#>clear_ram_bcb
		sta	src_ptr+1

		lda	#$00			; destination = CPU $A000 (VBXE $0000)
		sta	dst_ptr
		lda	#>vbxe_mem_base
		sta	dst_ptr+1

		lda	#<(clear_ram_bcb_end - clear_ram_bcb - 1)
		sta	counter
		lda	#>(clear_ram_bcb_end - clear_ram_bcb)
		sta	counter+1

		jsr	mem_move

		; ---- trigger blitter at VBXE address $000000 ----
		lda	#$00
		sta	blt_adr
		sta	blt_adr+1
		sta	blt_adr+2

		lda	#1
		sta	blt_start

		; ---- poll until blitter finishes ----
@wait
		lda	blt_busy
		bne	@wait

		; ---- close MEMAC window (caller reopens as needed) ----
		lda	#$00
		sta	memac_bank_sel

		rts

.endproc


;======================================================================
;
;  mem_move — internal copy routine (not exported)
;
;  Copies (counter + 1) bytes from address in src_ptr to address in
;  dst_ptr.  Both pointers are advanced during the copy.
;  Clobbers: A, X (preserved by caller if needed), Y, src_ptr, dst_ptr, counter.
;
;  On return: A = 0 (last counter check value).
;
;======================================================================

.proc mem_move

		ldy	#0
@loop
		lda	(src_ptr),y
		sta	(dst_ptr),y
		inc	src_ptr
		bne	@nc0
		inc	src_ptr+1
@nc0
		inc	dst_ptr
		bne	@nc1
		inc	dst_ptr+1
@nc1
		lda	counter
		bne	@nb
		lda	counter+1
		beq	@done
		dec	counter+1
@nb
		dec	counter
		jmp	@loop
@done
		rts

.endproc


;######################################################################################################################################
;
;  RODATA segment — blitter control blocks for _vbxe_clear_ram
;
;  Four chained BCBs that zero-fill all 512 K of VBXE RAM.
;  This table is copied to VBXE $0000 at runtime; the blitter is then
;  triggered from VBXE address $000000.
;
;  Fill mode: AND mask = $00 forces result = 0 regardless of source.
;  Destination of the first BCB starts immediately after the BCB table
;  itself (clear_ram_bcb_end - clear_ram_bcb bytes in), so the BCB data
;  is not overwritten while the blitter reads it.
;
;######################################################################################################################################

	.segment "RODATA"

clear_ram_bcb

	; BCB 0: fill VBXE $000000+sizeof(BCBs) … $01FFFF  (128 K, skipping BCB table)
	.faraddr 0					; source (irrelevant — fill via masks)
	.word	0					; source y-step
	.byte	0					; source x-step
	.faraddr clear_ram_bcb_end - clear_ram_bcb	; dst = first byte after BCB table in VBXE RAM
	.word	512					; y-step (line width)
	.byte	1					; x-step
	.word	512-1					; width - 1
	.byte	256-1					; height - 1
	.byte	$00					; AND mask → 0 (fill with 0)
	.byte	$00					; XOR mask → 0
	.byte	$00					; collision register
	.byte	$00					; zoom
	.byte	$00					; pattern
	.byte	%00001000				; next BCB present, mode 0 (copy)

	; BCB 1: fill VBXE $020000 … $03FFFF  (128 K)
	.faraddr 0
	.word	0
	.byte	0
	.faraddr $020000
	.word	512
	.byte	1
	.word	512-1
	.byte	256-1
	.byte	$00
	.byte	$00
	.byte	$00
	.byte	$00
	.byte	$00
	.byte	%00001000

	; BCB 2: fill VBXE $040000 … $05FFFF  (128 K)
	.faraddr 0
	.word	0
	.byte	0
	.faraddr $040000
	.word	512
	.byte	1
	.word	512-1
	.byte	256-1
	.byte	$00
	.byte	$00
	.byte	$00
	.byte	$00
	.byte	$00
	.byte	%00001000

	; BCB 3: fill VBXE $060000 … $07FFFF  (128 K, last entry)
	.faraddr 0
	.word	0
	.byte	0
	.faraddr $060000
	.word	512
	.byte	1
	.word	512-1
	.byte	256-1
	.byte	$00
	.byte	$00
	.byte	$00
	.byte	$00
	.byte	$00
	.byte	%00000000				; last BCB (next-bit clear), mode 0

clear_ram_bcb_end
