;######################################################################################################################################
;
;
;	   ##	 ##   #	  ####	  ###		 #     # #####	 #     # ######
;	  #  #	 # #  #	 #    #	   #		 #     #  #   #	  #   #	  #   #
;	 #    #	 #  # #	 #	   #		 #     #  #   #	   # #	  # #
;	 #    #	 #   ##	  ####	   #	 ######	 #     #  ####	    #	  ###
;	 ######	 #    #	      #	   #		  #   #	  #   #	   # #	  # #
;	 #    #	 #    #	 #    #	   #		   # #	  #   #	  #   #	  #   #
;	 #    #	 #    #	  ####	  ###		    #	 #####	 #     # ######
;
;	 ####### ######	 #####	 ##   ##  ###	 ##   #	   ##	 ###
;	 #  #  #  #   #	  #   #	 # # # #   #	 # #  #	  #  #	  #
;	    #	  # #	  #   #	 #  #  #   #	 #  # #	 #    #	  #
;	    #	  ###	  ####	 #     #   #	 #   ##	 #    #	  #
;	    #	  # #	  # #	 #     #   #	 #    #	 ######	  #
;	    #	  #   #	  #  #	 #     #   #	 #    #	 #    #	  #   #
;	   ###	 ######	 ###  #	 #     #  ###	 #    #	 #    #	 ######
;
;	Converted by:     Brad Colbert
;	Original MADS by: Joseph Zatarski
;	Version: v0.04
;
;	terminal emulator that supports ANSI/ECMA-48 control sequences and a 256 character font
;######################################################################################################################################
;
; TODO:	(from Joey Z) add recieve buffer so that I don't call CIOV to do one character at a time. (done)
;	label scroll contains some unnecesary math (refer to comments near it) (done)
;	add stuff beyond just the C0 (ASCII) and C1 control character/sequence sets (this means finally starting on the cool stuff)
;		SGR - set grahpics rendition (color, high intensity, etc.) - done unless I want to improve support for 'default colors'
;		add J code - ED - erase in page
;		add A code
;		add C code
;		add D code
;

	.setcpu "6502"
	.feature labels_without_colons
	.feature org_per_seg

	.include "atarios_ca65.inc"		; atari OS equates,
	.include "atarihardware_ca65.inc"	; general atari hardware equates,
	.include "VBXE_ca65.inc"		; and VBXE equates

; VBXE equates
vbxe_mem_base	= $A000				; If I put it here, it should be OK and it won't conflict with the extended RAM.

vbxe_screen_top	= vbxe_mem_base + 256		; points to where the first character of the screen would be

recv_buffer	= end				; first free space after the program.

send_buffer	= recv_buffer + 256		; first free space after the receive buffer. This will be 256 characters for the send
						; buffer. This is probably a overkill, but 256 makes it an easy number. This buffer
						; will be implemented like a FIFO. There will be one pointer to the next character to
						; be sent, and one for the next character to be added.

ctrl_seq_buf	= send_buffer + 256		; a buffer for the control sequence. I'll have to mess around with various sizes for
						; this. 256 bytes seems way overkill, so I probably only need 16 or so. For now, it's
						; 256 though.

; Display Handler Equates (among others)

cursor_address	= $80				; points to the address where the text cursor points
text_color	= $82				; current text color to be put on the screen.
row		= $83				; cursor row
column		= $84				; cursor column

src_ptr		= $85				; temporary source pointer on the zero page for memory moves
dst_ptr		= $87				; same as above, but for destination
counter		= $89				; byte counter for above

ctrl_seq_flg	= $8B				; bit 7 indicates escape received, bit 6 indicates CSI received.

cursor_flg	= $8C				; bit 7 indicates whether or not the cursor is currently visible
						; that is, if it's a 1, then the color of the current character
						; has been inverted to show the cursor.
temp_char	= $8D				; holds a character temporarily for the recieve processing routines

temp_key_char	= $8E

recvbuflen	= $8F				; holds the number of bytes in the receive buffer that are waiting to be processed.

sendbufstart	= $90				; holds the position of the last character taken from the send FIFO
sendbufend	= $91				; holds the position of the last character added to the send FIFO
						; if these are equal, the FIFO is empty. if sendbufend is one less than sendbufstart
						; then the buffer is full. This always leaves a pad of one character which won't be
						; used between the start and end, but otherwise you end up with the two pointers being
						; equal as an ambiguous case. it could mean the buffer is full, or it's empty. This
						; means implementing another flag and set of conditionals to indicate and detect this.

ctrl_seq_index	= $92				; points to the current position in the control sequence buffer.

final_byte	= $93				; holds the control sequence final byte
inter_byte	= $94				; holds the control sequence intermediate byte
parameter_val	= $95				; holds a single parameter value

	.segment "CODE"
	.org	$2800				; start of program
; apparently this is safe for most DOSes

;###################################################################################################################
; VBXE initialization
; check core version. needs to be fx core.
start		lda	core_version
		cmp	#$10			; $10 means fx core in core_version
		beq	core_fx

; print an error message in case of missing or non fx core VBXE
; just set the ICBA and call another routine since printing to E: will be used twice.
		lda	#<no_vbxe_msg
		sta	ICBA
		lda	#>no_vbxe_msg
		sta	ICBA + 1
		jmp	print_error

; FX core detected - newer firmware versions may have different core_version values,
; so we're being more permissive now. Just ensure it's an FX-like core.
core_fx						; for FX core compatible versions (1.2x, 1.26, 1.40, etc)
						; we'll accept the FX core and proceed without strict version checking

		lda	#$20			; shut off ANTIC DMA except instruction fetch
		sta	SDMCTL

; begin actually setting up the VBXE
		lda	#$00
		sta 	memac_b_control		; disable memac b window

; vbxe_mem_base is the high address of what we want to use for our VBXE memory window
; the first 4 bits of memac_control are the high nibble of the base address of the window
; bits 0-1: window size (00=4K, 01=8K, 10=16K, 11=32K)
; bit 2: MAE - ANTIC access enable
; bit 3: MCE - CPU access enable
; Keep a 4K window at A000-AFFF to avoid mapping into cartridge/ROM space.

		lda	#(>vbxe_mem_base)|$8	; $08 = 1000b: 4K window (bits 0-1 = 00) + CPU access (bit 3 = 1)
		sta	memac_control

; we are going to put a blitter list which clears the VBXE RAM into the first page of memory
; so we set the bank

		lda	#$80
		sta	memac_bank_sel



.scope						; copy the screen clearing blitter
		ldx	#00
loop		lda	clear_ram_bcb,x
		sta	vbxe_mem_base,x
		inx
		cpx	#(clear_ram_end - clear_ram_bcb)
		bne	loop
.endscope

; start the BCB

		lda	#0
		sta	blt_adr
		sta	blt_adr + 1
		sta	blt_adr + 2
		lda	#1
		sta	blt_start

.scope						; wait until the blitter is done
loop		lda	blt_busy
		bne	loop
.endscope

; turn off the MEMAC_A window so that it doesn't conflict with the extended RAM window
; this was causing issues with SDX
		
		lda	#0
		sta	memac_bank_sel

; done with VBXE init - jump to main program
		jmp	load_files
		
print_error					; prints the error message already set in ICBA
		lda	#$FF
		sta	ICBL
		lda	#09
		sta	ICCOM
		ldx	#$00
		jsr	CIOV

; wait for return press

		lda	#$06
		sta	ICBA+1
		lda	#$00
		sta	ICBA
		sta	ICBL
		sta	ICBL+1
		lda	#$05
		sta	ICCOM
		jsr	CIOV

; go back to DOS

		jmp	(DOSVEC)


no_vbxe_msg					; message to display for missing VBXE or non-fx core
		.byte	"No VBXE or non-fx core. Press return to continue.", $9B

clear_ram_bcb					; blitter routine to clear the whole VBXE RAM. 
						; we can only work with a 512 byte wide and 256 line high portion, or 128K, so we do that four times.
		.faraddr 0			; source doesn't matter, we're using a fill value
		.word	0			; source y step doesn't matter
		.byte	0			; source x step doesn't matter
		.faraddr clear_ram_end-clear_ram_bcb	; don't overwrite the blitter list
		.word	512			; one line is 512 bytes (no lines really though, we're just doing the whole 512K)
		.byte	1			; x step 1
		.word	512-1			; 512 bytes wide
		.byte	256-1			; 256 lines
		.byte	0			; AND mask ignores source
		.byte	0			; XOR mask fills with 0
		.byte	0			; don't worry about collisions
		.byte	0			; no zoom
		.byte	0			; don't worry about patterns
		.byte	%00001000		; there's 3 more of these BCB's, so next bit on, and mode 0 (copy mode)
		
		.faraddr 0			; source doesn't matter, we're using a fill value
		.word	0			; source y step doesn't matter
		.byte	0			; source x step doesn't matter
		.faraddr $020000		; destination starts at 128K
		.word	512			; one line is 512 bytes (no lines really though, we're just doing the whole 512K)
		.byte	1			; x step 1
		.word	512-1			; 512 bytes wide
		.byte	256-1			; 256 lines
		.byte	0			; AND mask ignores source
		.byte	0			; XOR mask fills with 0
		.byte	0			; don't worry about collisions
		.byte	0			; no zoom
		.byte	0			; don't worry about patterns
		.byte	%00001000		; there's 2 more of these BCB's, so next bit on, and mode 0 (copy mode)
		
		.faraddr 0			; source doesn't matter, we're using a fill value
		.word	0			; source y step doesn't matter
		.byte	0			; source x step doesn't matter
		.faraddr $040000		; destination starts at 256K
		.word	512			; one line is 512 bytes (no lines really though, we're just doing the whole 512K)
		.byte	1			; x step 1
		.word	512-1			; 512 bytes wide
		.byte	256-1			; 256 lines
		.byte	0			; AND mask ignores source
		.byte	0			; XOR mask fills with 0
		.byte	0			; don't worry about collisions
		.byte	0			; no zoom
		.byte	0			; don't worry about patterns
		.byte	%00001000		; there's 1 more of these BCB's, so next bit on, and mode 0 (copy mode)
		
		.faraddr 0			; source doesn't matter, we're using a fill value
		.word	0			; source y step doesn't matter
		.byte	0			; source x step doesn't matter
		.faraddr $060000		; destination starts at 384K
		.word	512			; one line is 512 bytes (no lines really though, we're just doing the whole 512K)
		.byte	1			; x step 1
		.word	512-1			; 512 bytes wide
		.byte	256-1			; 256 lines
		.byte	0			; AND mask ignores source
		.byte	0			; XOR mask fills with 0
		.byte	0			; don't worry about collisions
		.byte	0			; no zoom
		.byte	0			; don't worry about patterns
		.byte	%00000000		; there's no more of these BCB's, so next bit off, and mode 0 (copy mode)
clear_ram_end

;###################################################################################################################		
; start of loading files.
load_files

; make sure IOCB 1 is closed

		ldx	#$10
		lda	#$0C
		sta	ICCOM+$10
		jsr	CIOV

; open the font file in IOCB 1

		ldx	#$10
		lda	#$03
		sta	ICCOM+$10
		lda	#<font_path
		sta	ICBA+$10
		lda	#>font_path
		sta	ICBA+$11
		lda	#$04
		sta	ICAX1+$10
		lda	#$00
		sta	ICAX2+$10
		jsr	CIOV
	
; set bank to beginning of VBXE memory with bit 7 set to enable the window
; this is where we will load the font

		lda	#$80
		sta	memac_bank_sel

; load the entire (2K) font into the VBXE memory window

		ldx	#$10			; IOCB 1
		lda	#$07			; read binary record
		sta	ICCOM+$10
		lda	#$00			; buffer address is vbxe_mem_base
		sta	ICBA+$10
		lda	#>vbxe_mem_base
		sta	ICBA+$11
		lda	#$00			; buffer length is 2K
		sta	ICBL+$10
		lda	#$08
		sta	ICBL+$11
		jsr	CIOV

; close the font file (we only need to load it once)

		ldx	#$10
		lda	#$0C
		sta	ICCOM+$10
		jsr	CIOV

; open the pallette file

		ldx	#$10
		lda	#$03
		sta	ICCOM+$10
		lda	#<pallette_path
		sta	ICBA+$10
		lda	#>pallette_path
		sta	ICBA+$11
		lda	#$04
		sta	ICAX1+$10
		lda	#$00
		sta	ICAX2+$10
		jsr	CIOV

; read the pallette to a temporary location inside VBXE memory (which we know is free for now)

		ldx	#$10			; IOCB 1
		lda	#$07			; read binary record
		sta	ICCOM+$10
		lda	#$00			; buffer address is vbxe_mem_base + $0800
		sta	ICBA+$10
		lda	#>vbxe_mem_base + $08
		sta	ICBA+$11
		lda	#$30			; buffer length is 48 bytes ($30)
		sta	ICBL+$10
		lda	#$00
		sta	ICBL+$11
		jsr	CIOV

; close the pallette, we have it in RAM now

		ldx	#$10
		lda	#$0C
		sta	ICCOM+$10
		jsr	CIOV

; initialize csel and psel to start loading colors into the pallette

		lda	#$00
		sta	psel
		sta	csel

.scope						; load the foreground colors into the VBXE
; we use a nested loop here due to the design of the text mode colors
; we need to load the 16 foreground colors into the first 128 colors in order, and do that 8 times
; this order will be like:
; col 1, col 2, col 3, ..., col F, col 1, col 2 etc.

		ldy	#$00			; initialize the outer loop counter
fore_outer_loop	ldx	#$00			; initialize the inner loop counter
fore_inner_loop	lda	vbxe_mem_base + $0800,x	; load the color values. use index x because of the order we need to load colors in
		sta	cr
		lda	vbxe_mem_base + $0801,x
		sta	cg
		lda	vbxe_mem_base + $0802,x
		sta	cb
		inc	csel			; move to next color entry
		inx				; increment 3 times because each color is 3 bytes
		inx
		inx
		cpx	#$30			; once x is equal to $30, we have loaded all the colors
		bne	fore_inner_loop
	
		iny				; increment the outer loop counter
		cpy	#$08			; so we can do it for 8 times total
		bne	fore_outer_loop
.endscope


.scope						; load the background colors into the VBXE
; we use a nested loop here, but differently again due to the design of text mode colors
; we need to load the 8 background colors 16 times in a row each
; that is, load color 0 16 times, then load color 1 16 times, etc.

		ldy	#$00			; initialize the outer loop counter
back_outer_loop	ldx	#$00			; initialize the inner loop counter
back_inner_loop	lda	vbxe_mem_base + $0800,y	; load the color values. use index y because we load each color repeatedly
		sta	cr
		lda	vbxe_mem_base + $0801,y
		sta	cg
		lda	vbxe_mem_base + $0802,y
		sta	cb
		inc	csel			; move to next color entry
		inx				; increment the inner loop
		cpx	#$10			; stop after the color has been loaded 16 times
		bne	back_inner_loop
		iny				; increment 3 times because each color is 3 bytes
		iny
		iny
		cpy	#$18			; when we get to $18, we have loaded all the background colors
		bne	back_outer_loop
.endscope
; load the xdl and blitter lists

		lda	#<xdl			; setup source pointer
		sta	src_ptr
		lda	#>xdl
		sta	src_ptr+1
		
		lda	#<(vbxe_mem_base+$0800)	; destination pointer
		sta	dst_ptr
		lda	#>(vbxe_mem_base+$0800)
		sta	dst_ptr+1
		
		lda	#<(bcb_end - xdl - 1)	; and byte count - 1
		sta	counter
		lda	#>(bcb_end - xdl)
		sta	counter+1
		
		jsr	mem_move
		
; load the xdl address ($0800 in internal VBXE memory)

		lda	#$00
		sta	xdl_adr			; low byte = $00
		lda	#$08
		sta	xdl_adr_mid		; middle byte = $08
		lda	#$00
		sta	xdl_adr_high		; high byte = $00

; enable xdl and disable transparent colors

		lda	#$05
		sta	video_control

; set the memac window to the display ram (the top of VBXE memory)

		lda	#$FF
		sta	memac_bank_sel

; done initializing the VBXE
;###################################################################################################################
; now we start initializing the variables for the terminal state
; initialize the cursor address to be at the home position

		lda	#<vbxe_screen_top
		sta	cursor_address
		lda	#>vbxe_screen_top
		sta	cursor_address + 1

; initialize the text color

		lda	#$87			; $87 is white on black
		sta	text_color

; initialize the cursor position
		lda	#$00
		sta	row
		sta	column
		
; the flags for escape and CSI
		sta	ctrl_seq_flg

; the flag for the cursor
		sta	cursor_flg		; cursor is not on yet.

; indexes for send buffer
		sta	sendbufstart
		sta	sendbufend

; turn the cursor on
; normally, the screen windows starts in a state of all 0.
; that is fine for the characters
; but for the colors, this means the overlay bit is not set
; so all the colors are transparent and the cursor doesn't show up right
; so we clear the page first, which fills the page with null and the default color
		jsr	scroll_page
		jsr	cursor_on
		
;###################################################################################################################
; demo it by writing a file to the screen (for now at least)
; open the test file
;
;		ldx	#$10
;		lda	#$03
;		sta	ICCOM+$10
;		lda	#<test_file
;		sta	ICBA+$10
;		lda	#>test_file
;		sta	ICBA+$11
;		lda	#$04
;		sta	ICAX1+$10
;		lda	#$00
;		sta	ICAX2+$10
;		jsr	CIOV
;
;		lda	RTCLOK
;		sta	starttime
;		lda	RTCLOK + 1
;		sta	starttime + 1
;		lda	RTCLOK + 2
;		sta	starttime + 2

; open the R: device
		ldx	#$10
		lda	#$03
		sta	ICCOM+$10
		lda	#<r_path
		sta	ICBA+$10
		lda	#>r_path
		sta	ICBA+$11
		lda	#$0D
		sta	ICAX1+$10
		lda	#0
		sta	ICAX2+$10
		jsr	CIOV
		
; configure it
; for now, 9600 baud, 8 data bits, no status line checking,

		ldx	#$10
		lda	#36
		sta	ICCOM+$10
		lda	#<r_path
		sta	ICBA+$10
		lda	#>r_path
		sta	ICBA+$11
		lda	#14
		sta	ICAX1+$10
		lda	#0
		sta	ICAX2+$10
		jsr	CIOV
		
; no translation, ignore and do not change parity bit (input or output), and do not append LF to CR
 
		ldx	#$10
		lda	#38
		sta	ICCOM+$10
		lda	#<r_path
		sta	ICBA+$10
		lda	#>r_path
		sta	ICBA+$11
		lda	#32
		sta	ICAX1+$10
		lda	#0
		sta	ICAX2+$10
		jsr	CIOV
		
; turn on DTR and RTS, and don't change xmt state

		ldx	#$10
		lda	#34
		sta	ICCOM+$10
		lda	#<r_path
		sta	ICBA+$10
		lda	#>r_path
		sta	ICBA+$11
		lda	#192+48
		sta	ICAX1+$10
		lda	#0
		sta	ICAX2+$10
		jsr	CIOV
		
; start concurrent I/O

		ldx	#$10
		lda	#40
		sta	ICCOM+$10
		lda	#<r_path
		sta	ICBA+$10
		lda	#>r_path
		sta	ICBA+$11
		lda	#0
		sta	ICAX1+$10
		sta	ICAX2+$10
		jsr	CIOV
		
		; set up the KB interupt handler now that R: is open.
		sei				; disable interupts before we set the new vector
		lda	#<kbd_irq
		sta	VKEYBD
		lda	#>kbd_irq
		sta	VKEYBD+1
		cli				; re-enable interupts
		
wait_for_byte	jsr	check_sendbuf		; check to see if the send buffer has characters to be sent

		ldx	#$10
		lda	#13
		sta	ICCOM+$10
		lda	#<r_path
		sta	ICBA+$10
		lda	#>r_path
		sta	ICBA+$11
		lda	#0
		sta	ICAX1+$10
		sta	ICAX2+$10
		jsr	CIOV
		
		lda	DVSTAT1			; DVSTAT1 and 2 hold the number of bytes in the input buffer
		ora	DVSTAT2
		beq	wait_for_byte		; if they're 0, keep waiting
		
.scope						; read bytes - right now this will get a max of 255 bytes, even though the buffer is
		ldx	#$10			; 256 bytes. This could be fixed later. recvbuflen = 0 could mean 256, since the only
		lda	#$07			; time execution reaches here is if there are more than 0 bytes to be processed.
		sta	ICCOM+$10
		lda	#<recv_buffer
		sta	ICBA + $10
		lda	#>recv_buffer
		sta	ICBA + $11
		lda	DVSTAT2
		bne	maxbuflen
		lda	DVSTAT1
		jmp	storebuflen
maxbuflen	lda	#$FF
storebuflen	sta	ICBL + $10
		sta	recvbuflen
		lda	#$0
		sta	ICBL + $11
		lda	#$0D
		sta	ICAX1 + $10		; turns out you need this for GET or it doesn't work.
		jsr	CIOV			; so after this, the receive buffer should have characters in it to be processed
		
		ldy	#0
next_byte	lda	recv_buffer, y		; get character from buffer
		sta	temp_char		; put it here to pass to process_char
		tya
		pha				; push Y just in case

		jsr 	process_char		; process the character

		pla
		tay				; get Y back

		iny				; next character

		cpy	recvbuflen
		bne	next_byte		; if they're not equal, we get the next byte
		
		jmp	wait_for_byte
.endscope

.proc process_char
		bit	ctrl_seq_flg
		bvs	is_ctrl_seq		; if overflow set, it's a control sequence
		bpl	not_C1			; if escape flag not set, it's not a C1 character
		lda	#0			; if it is, we clear the escape flag for the next character.
		sta	ctrl_seq_flg
		lda	temp_char
		and	#%11100000		; AND mask for C1 set
		cmp	#$40			; if it's $40 after ANDing,
		beq	is_C1			; it's part of the C1 set
		rts				; otherwise, it's some other character preceded by escape, which we do nothing with (don't even print it)

.proc is_ctrl_seq
		lda	temp_char
		cmp	#$20
		bcc	bad_ctrl_seq		; control sequence is bad if character isn't greater than or equal to #$20
		cmp	#$7F			; control sequence is bad if character is greater than or equal to #$7F
		bcs	bad_ctrl_seq		; this is all in the ECMA 48 spec.
		ldx	ctrl_seq_index		; get index
		sta	ctrl_seq_buf,x		; store byte in the buffer
		inx
		stx	ctrl_seq_index
		cmp	#$40			; if control sequence byte is greater than or equal to #$40, then it's the final byte.
		bcs	is_final_byte
		rts
		
bad_ctrl_seq	lda	#0
		sta	ctrl_seq_flg
		rts
		
is_final_byte	sta	final_byte
		lda	#0
		sta	ctrl_seq_flg
		jmp	do_ctrl_seq
.endproc
		

not_C1		lda	temp_char
		cmp	#32
		bcc	is_C0			; if the character is less than 32, it's a part of the C0 control set
		
		jmp	put_byte		; if it's not part of the C0 set, just print it.

		
is_C0		asl				; multiply by two to get an offset into the C0 handler table
		tax				; transfer to X to be used as an index
		lda	C0_handler_table, x	; transfer the address of the proper handler
		sta	jump_C0 + 1
		lda	C0_handler_table + 1, x
		sta	jump_C0 + 2
jump_C0		jmp	$0000			; into the operand of this JMP
				
is_C1
		lda	temp_char
		asl
		tax
		lda	C1_handler_table-$80,x	; transfer the address of the proper handler
		sta	jump_C1 + 1
		lda	C1_handler_table-$7F,x
		sta	jump_C1 + 2
jump_C1		jmp	$0000
.endproc
		
.proc do_ctrl_seq
		ldx	ctrl_seq_index
		dex
		dex
		lda	ctrl_seq_buf,x
		cmp	#$30
		bcs	no_inter_byte		; if this byte is less than #$30, it's an intermediate byte.
		sta	inter_byte
		jmp	find_entry
no_inter_byte	lda	#0
		sta	inter_byte
		
find_entry	ldx	#0
next_entry	lda	ctrl_seq_table,x	; get final byte from table
		beq	last_entry		; if the last entry is reached, jump
		cmp	final_byte		; compare to actual final byte
		bne	wrong_f_byte		; jump if they don't match
		inx
		lda	ctrl_seq_table,x	; get intermediate byte
		cmp	inter_byte		; compare to actual intermediate byte
		bne	wrong_i_byte		; jump if they don't match
		inx				; point at low address of handler
		lda	ctrl_seq_table,x
		sta	ctrl_seq_jmp+1
		lda	ctrl_seq_table+1,x
		sta	ctrl_seq_jmp+2		; set up the jump
		
ctrl_seq_jmp	jmp	$0000			; jump to control sequence handler (the address here will be changed)
		
wrong_f_byte	inx				; points to intermediate byte after this
wrong_i_byte	inx				; points to low address byte after this
		inx				; points to high address byte after this
		inx				; points to next final byte after this
		jmp	next_entry
		
last_entry	rts				; if we searched the whole list and didn't find it, do nothing.
.endproc


.proc put_byte					; put the byte on the screen
		jsr	cursor_off
		ldx	#$00
		lda	temp_char
		sta	(cursor_address, x)
		inc	cursor_address
		lda	text_color		; get the current text color
		sta	(cursor_address, x)
		inc	cursor_address
		bne	no_carry		; if the increment resulted in 0, then we rolled over and need to carry
		inc	cursor_address + 1	; carry means high address needs to be incremented
no_carry	inc	column			; move the cursor forward
		lda	#79
		cmp	column
		bcs	no_new_line		; if 79 >= col, no new line is needed
		lda	row
		cmp	#23			; if row is 23, then we need to scroll a line
		beq	scroll
		inc	row			; otherwise (when col > 79) go to the next line
		lda	#00
		sta	column			; set column back to 0
no_new_line	jmp	cursor_on

scroll		lda	#<(vbxe_mem_base + $1000 - 160)
		sta	cursor_address
		lda	#>(vbxe_mem_base + $1000 - 160)
		sta	cursor_address + 1
no_carry_1	lda	#0			; otherwise, don't
		sta	column			; set column to 0. row stays 23
		jsr	scroll_1d		; run the blitter routine to scroll one line down.
		jmp	cursor_on
.endproc

;###################################################################################################################
; control sequence handlers
SOH_adr						; Start of Header prints a character
STX_adr						; Start of Text prints a character
ETX_adr						; End of Text prints a character
EOT_adr						; End of Transmission prints a character
ACK_adr						; Acknowledge prints a character
SO_adr						; Shift Out prints a character
SI_adr						; Shift In prints a character
DLE_adr						; Data Link Escape prints a character
DC1_adr						; Device Control 1-4 print a character
DC2_adr
DC3_adr
DC4_adr
NAK_adr						; Non-Acknowledge prints a character
SYN_adr						; Synchronous Idle prints a character
ETB_adr						; End of Transmission Block prints a character
CAN_adr						; Cancel prints a character
EM_adr						; End of Medium prints a character
SUB_adr						; Substitute prints a character
IS1_adr						; Information Separator 1-4 print characters
IS2_adr
IS3_adr
IS4_adr
		jmp 	put_byte		; the put_byte routine will return for us
ESC_adr						; Escape sets the escape flag
		lda	#$80
		sta	ctrl_seq_flg
		rts
CSI_adr						; Control Sequence Introducer sets the CSI flag which causes interpretation of a control sequence to begin
		lda	#0
		sta	ctrl_seq_index
		lda	#$40
		sta	ctrl_seq_flg
		rts
VT_adr						; Vertical Tab. for now, same as LF
IND_adr						; Index is same as LF
.proc LF_adr					; Line Feed moves the cursor down one line BUT only if we're not on the last line
						; down one line is forward 80 columns, or 160 bytes
		jsr	cursor_off
		lda	row
		cmp	#23			; if row is at 24,
		beq	scroll			; we scroll
		lda	#160			; otherwise, we add 160.
		clc				; clear the carry in prep for the addition.
		adc	cursor_address		; add 160 to the low part of the cursor address.
		sta	cursor_address
		bcc	no_carry		; if there's a carry,
		inc	cursor_address + 1	; increment the high half of the address.
no_carry	inc	row			; Line Feed increments row
		jmp	cursor_on
scroll		jsr	scroll_1d		; scroll one line down. we don't need to touch the cursor address, the row, or column.
		jmp	cursor_on
.endproc

.proc CR_adr					; Carriage Return puts the cursor at the home position of the current line 
                                                ; (AKA, cursor gets column number * 2 bytes/char subtracted from it)
		jsr	cursor_off
		lda	cursor_address		; get cursor
		sec				; set carry for subtraction
		sbc	column			; do the subtraction
		bcs	no_borrow1		; carry will be clear if no borrow
		dec	cursor_address + 1	; otherwise it borrowed, so decrement cursor_address high byte
no_borrow1	sec				; prepare for another subtraction
		sbc	column			; do it
		bcs	no_borrow2		; borrow thing again...
		dec	cursor_address + 1
no_borrow2	sta	cursor_address		; store the result
		lda 	#00
		sta	column			; set column to 0
		jmp	cursor_on
.endproc

.proc BEL_adr					; Bell is supposed to play a tone, flash the screen, something.
						; this routine is copied out of the atari OS. it is what Atari used to do a bell character.
						; it's slightly modified. the original routine called the keyclick routine 32 (#$20) times.
						; I use a nested loop.
						; perhaps later, I will separate the keyclick routine for my own purposes.
		ldy	#$20
repeat		ldx	#$7E
spk		stx	CONSOL
		lda	VCOUNT
wait		cmp	VCOUNT
		beq	wait
		dex
		dex
		bpl	spk
		dey
		bpl	repeat
		rts
.endproc
		
FF_adr						; Form Feed clears the screen and sets cursor to the home position.
		jsr	cursor_off
		lda	#0			; home the cursor
		sta	row
		sta	column
		lda	#<vbxe_screen_top
		sta	cursor_address
		lda	#>vbxe_screen_top
		sta	cursor_address + 1
		jsr	scroll_page		; clear the screen
		jmp	cursor_on
		
.proc BS_adr					; Back Space moves the cursor left by one character (2 bytes).
		jsr	cursor_off
		lda	column
		bne	not_left		; if we're not at the left side yet, keep going
		rts				; but if we ARE at the left side, do nothing
not_left	dec	column			; if column isn't 0, we just decrement it
		lda	cursor_address
		bne	no_borrow		; if the cursor address low half isn't 0, we don't borrow
		dec	cursor_address + 1	; otherwise, borrow
no_borrow	dec	cursor_address		; if it weren't for the fact that cursor_address should always be even,
		dec 	cursor_address		; we would have to look for a borrow here too.
		jmp	cursor_on
.endproc
NUL_adr						; null does nothing
ENQ_adr						; Enquiry is probably supposed to return an ACK, but for now, it does nothing
HT_adr						; Horizontal Tab normally causes the cursor to move to the next tab stop. for now, nothing
HTS_adr						; no tab stuff just yet
HTJ_adr
VTS_adr
BPH_adr						; BPH doesn't apply in this case.
NBH_adr						; nor do any of the following
SSA_adr
ESA_adr
PLD_adr
PLU_adr
RI_adr
SS2_adr
SS3_adr
DCS_adr
PU1_adr
PU2_adr
STS_adr
CCH_adr
MW_adr
SPA_adr
EPA_adr
SOS_adr
SCI_adr
ST_adr
OSC_adr
PM_adr
APC_adr
		rts
NEL_adr						; Next Line is combination of CR and LF
		jsr	CR_adr
		jmp	LF_adr

.proc SGR_adr					; set graphics rendition control sequence
		ldx	#$FF
next_parm	lda	#0
		sta	parameter_val		; zero parameter value, this is the default value for this control sequence also
next_byte	inx				; increment index
		lda	ctrl_seq_buf,x		; get byte of control sequence
		tay				; save original value
		and	#$F0
		cmp	#$30			; if it's #$3x, then it's a parameter value
		bne	is_last_parm		; otherwise, it has to be the final byte.
		tya				; get value back
		cmp	#$3A
		bcc	add_digit		; if it's less than #$3A, then append the digit to parameter_val
		beq	next_byte		; if it's #$3A, then ignore it
		cmp	#$3B
		beq	parse_parm		; if it's #$3B, then it's the end of a parameter substring
		jmp	next_byte		; otherwise, at this point, it must be a bad value (#$3C through #$3F)

add_digit	and	#$0F			; we just want the last 4 bits
		tay				; save this
		lda	parameter_val		; append the digit to parameter_val
		asl
		asl
		asl
		asl
		sta	parameter_val
		tya
		ora	parameter_val
		sta	parameter_val
		jmp	next_byte
		
parse_parm
		jsr	is_last_parm
		jmp	next_parm
		
.proc is_last_parm
		lda	parameter_val
		and	#$F0
		beq	simple_attrib		; if it's zero, it's a simple attribute (bold, inverse, etc.)
		cmp	#$30
		beq	forecolor_attr		; foreground (text) color change
		cmp	#$40
		beq	backcolor_attr		; background color change
		rts				; otherwise it's not supported

.proc simple_attrib
		lda	parameter_val
		and	#$0F
		beq	default_attr
		cmp	#$1
		beq	bold
		cmp	#$2
		beq	unbold
		cmp	#$7
		beq	inverse
		rts

default_attr	lda	#$87
		sta	text_color
		rts
		
bold		lda	text_color
		ora	#%00001000
		sta	text_color
		rts
		
unbold		lda	text_color
		and	#%11110111
		sta	text_color
		rts
		
inverse		lda	text_color
		eor	#%01110111
		sta	text_color
		rts
.endproc
		
.proc forecolor_attr
		lda	parameter_val
		cmp	#$38
		bcs	ignore
		and	#$0F
		sta	parameter_val
		lda	text_color
		and	#$F8
		ora	parameter_val
		sta	text_color
ignore		rts
.endproc
		
.proc backcolor_attr
		lda	parameter_val
		cmp	#$48
		bcs	ignore
		and	#$0F
		asl
		asl
		asl
		asl
		sta	parameter_val
		lda	text_color
		and	#$8F
		ora	parameter_val
		sta	text_color
ignore		rts
.endproc
		
.endproc					; end is_last_parm

.endproc					; end SGR_adr

;###################################################################################################################
; parse_param: parse a decimal parameter from ctrl_seq_buf starting at index X
; returns the value in A. X is left pointing at the first non-digit byte.
; if no digits are found, A = 0 (caller applies default).

.proc parse_param
		lda	#0
		sta	parameter_val
next_digit	lda	ctrl_seq_buf, x
		cmp	#$30			; '0'
		bcc	done			; < '0', not a digit
		cmp	#$3A			; one past '9'
		bcs	done			; >= ':', not a digit
		and	#$0F			; get digit value 0-9
		pha				; save digit
		lda	parameter_val
		asl				; *2
		asl				; *4
		clc
		adc	parameter_val		; *5
		asl				; *10
		sta	parameter_val
		pla				; get digit back
		clc
		adc	parameter_val
		sta	parameter_val
		inx
		jmp	next_digit
done		lda	parameter_val
		rts
.endproc

;###################################################################################################################
; recalc_cursor: recalculate cursor_address from row and column
; cursor_address = vbxe_screen_top + row * 160 + column * 2

.proc recalc_cursor
		lda	#<vbxe_screen_top
		sta	cursor_address
		lda	#>vbxe_screen_top
		sta	cursor_address + 1
		ldx	row
		beq	add_col
add_row		lda	cursor_address
		clc
		adc	#160
		sta	cursor_address
		bcc	no_carry
		inc	cursor_address + 1
no_carry	dex
		bne	add_row
add_col		lda	column
		asl				; column * 2
		clc
		adc	cursor_address
		sta	cursor_address
		bcc	done
		inc	cursor_address + 1
done		rts
.endproc

;###################################################################################################################
; CUF - Cursor Forward (ESC[nC) - move cursor right by n columns (default 1)

.proc CUF_adr
		jsr	cursor_off
		ldx	#0
		jsr	parse_param
		tay
		bne	has_param
		ldy	#1			; default is 1
has_param
move_loop	lda	column
		cmp	#79
		bcs	done			; at right edge, stop
		inc	column
		lda	cursor_address
		clc
		adc	#2
		sta	cursor_address
		bcc	no_carry
		inc	cursor_address + 1
no_carry	dey
		bne	move_loop
done		jmp	cursor_on
.endproc

;###################################################################################################################
; CUB - Cursor Back (ESC[nD) - move cursor left by n columns (default 1)

.proc CUB_adr
		jsr	cursor_off
		ldx	#0
		jsr	parse_param
		tay
		bne	has_param
		ldy	#1
has_param
move_loop	lda	column
		beq	done			; at left edge, stop
		dec	column
		lda	cursor_address
		sec
		sbc	#2
		sta	cursor_address
		bcs	no_borrow
		dec	cursor_address + 1
no_borrow	dey
		bne	move_loop
done		jmp	cursor_on
.endproc

;###################################################################################################################
; CUU - Cursor Up (ESC[nA) - move cursor up by n rows (default 1)

.proc CUU_adr
		jsr	cursor_off
		ldx	#0
		jsr	parse_param
		tay
		bne	has_param
		ldy	#1
has_param
move_loop	lda	row
		beq	done			; at top, stop
		dec	row
		lda	cursor_address
		sec
		sbc	#160
		sta	cursor_address
		bcs	no_borrow
		dec	cursor_address + 1
no_borrow	dey
		bne	move_loop
done		jmp	cursor_on
.endproc

;###################################################################################################################
; CUD - Cursor Down (ESC[nB) - move cursor down by n rows (default 1)

.proc CUD_adr
		jsr	cursor_off
		ldx	#0
		jsr	parse_param
		tay
		bne	has_param
		ldy	#1
has_param
move_loop	lda	row
		cmp	#23
		bcs	done			; at bottom, stop
		inc	row
		lda	cursor_address
		clc
		adc	#160
		sta	cursor_address
		bcc	no_carry
		inc	cursor_address + 1
no_carry	dey
		bne	move_loop
done		jmp	cursor_on
.endproc

;###################################################################################################################
; CUP - Cursor Position (ESC[row;colH) - move cursor to absolute position (default 1;1)
; ANSI parameters are 1-based; internal row/column are 0-based.

.proc CUP_adr
		jsr	cursor_off
		ldx	#0
		jsr	parse_param		; parse row
		beq	default_row
		sec
		sbc	#1			; convert 1-based to 0-based
		jmp	check_row
default_row	lda	#0
check_row	cmp	#24
		bcc	row_ok
		lda	#23
row_ok		sta	row
		lda	ctrl_seq_buf, x
		cmp	#$3B			; ';' separator?
		bne	default_col
		inx				; skip ';'
		jsr	parse_param		; parse col
		beq	default_col
		sec
		sbc	#1			; convert 1-based to 0-based
		jmp	check_col
default_col	lda	#0
check_col	cmp	#80
		bcc	col_ok
		lda	#79
col_ok		sta	column
		jsr	recalc_cursor
		jmp	cursor_on
.endproc

;###################################################################################################################
; ED - Erase in Display (ESC[nJ)
; n=0: clear from cursor to end of screen (default)
; n=1: clear from beginning of screen to cursor
; n=2: clear entire screen

.proc ED_adr
		ldx	#0
		jsr	parse_param
		cmp	#2
		beq	clear_all
		rts				; only n=2 supported for now
clear_all	jsr	cursor_off
		lda	#0
		sta	row
		sta	column
		lda	#<vbxe_screen_top
		sta	cursor_address
		lda	#>vbxe_screen_top
		sta	cursor_address + 1
		jsr	scroll_page
		jmp	cursor_on
.endproc

;###################################################################################################################
; EL - Erase in Line (ESC[nK)
; n=0: clear from cursor to end of line (default)
; currently only n=0 is supported

.proc EL_adr
		jsr	cursor_off
		ldx	#0
		jsr	parse_param		; get n (default 0)
		cmp	#0
		bne	done			; only n=0 supported for now
		lda	#79
		sec
		sbc	column			; A = number of chars to clear
		tax
		beq	done			; nothing to clear if at end of line
		ldy	#0
clear_loop	lda	#0			; null character
		sta	(cursor_address), y
		iny
		lda	text_color		; current background color
		sta	(cursor_address), y
		iny
		dex
		bne	clear_loop
done		jmp	cursor_on
.endproc
		
.proc mem_move					; memory move routine.
; copies number of bytes in counter + 1 from address in src_ptr to address in dst_ptr

		ldy	#0			; we don't want an offset actually, but the 6502 uses one anyway
loop		lda	(src_ptr),y		; move a byte
		sta	(dst_ptr),y
		inc	src_ptr			; increment the pointer
		bne	no_carry_0		; if it rolled over (to zero)
		inc	src_ptr+1		; then increment the high byte
no_carry_0	inc	dst_ptr			; increment the other pointer
		bne	no_carry_1
		inc	dst_ptr+1
no_carry_1	lda	counter			; check to see if count is 0
		bne	no_borrow		; if it's not, we don't borrow
		lda	counter+1		; check to see if count's high byte is 0 also
		beq	done			; in which case we're done
		dec	counter+1		; but if we're not, we borrow
no_borrow	dec	counter
		jmp	loop
done		rts
.endproc

.proc scroll_1d					; scroll one down routine.
; uses the blitter to move everything up just one line.

		lda	memac_bank_sel		; get the old bank number (should be the last bank, but we can't assume)
		pha
		
		lda	#$80			; bank 0, so we can put the color byte as the fill byte
		sta	memac_bank_sel
		
		lda	text_color		; put the color in the fill pattern location.
		sta	scroll_1d_color-xdl+$0800+vbxe_mem_base
		
		lda	#<(bcb_one_down - xdl + $800)
		sta	blt_adr
		lda	#>(bcb_one_down - xdl + $800)
		sta	blt_adr+1
		lda	#^(bcb_one_down - xdl + $800)
		sta	blt_adr+2
		
		lda	#1
		sta	blt_start
		
loop		lda	blt_busy
		bne	loop
		
		pla
		sta	memac_bank_sel
		rts
.endproc
		
.proc scroll_page				; scroll one page
; used for FF and also to initialize the screen so the color is not all $00

		lda	memac_bank_sel		; get the old bank number (should be the last bank, but we can't assume)
		pha
		
		lda	#$80			; bank 0, so we can put the color byte as the fill byte
		sta	memac_bank_sel
		
		lda	text_color		; put the color in the fill pattern location.
		sta	clr_scr_color-xdl+$0800+vbxe_mem_base
		
		lda	#<(bcb_clr_scr - xdl + $800)
		sta	blt_adr
		lda	#>(bcb_clr_scr - xdl + $800)
		sta	blt_adr+1
		lda	#^(bcb_clr_scr - xdl + $800)
		sta	blt_adr+2
		
		lda	#1
		sta	blt_start
		
loop		lda	blt_busy
		bne	loop
		
		pla
		sta	memac_bank_sel
		rts
.endproc
		
.proc cursor_on					; turn on the cursor
; but ONLY if the cursor isn't already on
		bit	cursor_flg
		bpl	cursor_toggle
skip		rts
.endproc
		
.proc cursor_off				; turn off the cursor
; but ONLY if the cursor isn't already off
		bit	cursor_flg
		bmi	cursor_toggle
skip		rts
.endproc

cursor_toggle					; inverts the color of the current character to show the cursor
		ldy	#1
		lda	(cursor_address),y
		eor	#$77			; invert the color, but not bit 7 (transparency bit) or bit 3 (foreground intensity)
		sta	(cursor_address),y
		lda	cursor_flg
		eor	#$80			; flip the cursor flag
		sta	cursor_flg
		rts
		
.proc kbd_irq
; some of this code is based on the OS keyboard IRQ code. It even reuses some of the same OS variables.

		lda	KBCODE			; get the key
		cmp	CH1			; and check if it's the same as last time
		bne	new_key			; if not, then it's definitely a new press
		lda	KEYDEL			; but if not, we need to see if it's too soon (and therefore a bounce)
		beq	new_key			; so if it is not, then it's a new press
		jmp	bounce			; otherwise, it's a bounce
		
new_key		txa
		pha				; we are going to need X
		lda	#$03			; we put this back in keydel so we can check for bounce again
		sta	KEYDEL
		lda	KBCODE			; if it's not, then we need the keycode again
		sta	CH1			; and we put it in here so we can check for bounce next time

; I guess I will convert the key code to ASCII here, and interpret it, etc.
; I'll probably use an LUT
; for now, I guess I will just convert to ASCII and send. everything (for now) will become one character.
; return will produce CR I suppose. (for now only of course)

		tax
		lda	keycode_table,x		; get the ascii conversion (if there is one) from the table
		beq	no_value		; if it's 0, then we don't do anything

		ldx	sendbufend		; get the current offset in the send FIFO
		inx				; increment it
		cpx	sendbufstart		; if it's now the same as this, then the buffer is actually full
		beq	no_value		; we can't really do anything here, or else we'll cause a buffer overrun
		stx	sendbufend		; but otherwise we're fine, so this becomes the new value
		
		sta	send_buffer,x		; and we can put the character into the buffer here

no_value	lda	#$00			; key down, so reset ATRACT counter
		sta	ATRACT			; not that it matters so much with VBXE, but it'll prevent changing border colors
		pla
		tax				; get x back

bounce		lda	#$30			; we still set the repeat timer on a bounce I guess
		sta	SRTIMR			; that's the way the OS does it
		pla				; apparently the routine which jumps through the keyboard vector pushes A
		rti				; RTI because interupt
.endproc
		
.proc check_sendbuf				; checks to see if the send buffer is empty, and sends it if it's not.
; in the future, there may be a few different cases handled here.
; the first is an empty buffer, so you return.
; the second is a nonempty buffer, but only one character in the buffer (probably the next most common case next to no characters).
; the third is a nonempty buffer with multiple characters in it
; this one breaks down into two more cases, one where the bytes are contiguous, the other where they cross the end of the buffer
; perhaps it's possible to prevent this case by resetting the buffer indexes to 0 once the buffer is empty.
; however, this could conflict with the keyboard interupt if the interupt fires while inside this routine.
; Right now, the only thing saving me from having to disable interupts for that scenario is that I never modify sendbufend
; outside of the KBD IRQ

		lda	sendbufstart
		cmp	sendbufend
		bne	not_empty		; jump if the buffer isn't empty
		
		rts				; or return otherwise

not_empty	ldx	#$10			; for now, we send one character out of the buffer
		lda	#$0B			; this will probably be the most common non-empty possibility anyway
		sta	ICCOM+$10		; it'll still handle multiple characters in the buffer too, just a little more slowly
		lda	#$00			; buffer length 0 uses character in accumulator
		sta	ICBL + $10
		sta	ICBL + $11
		lda	#$0D
		sta	ICAX1 + $10		; turns out you need this for GET or it doesn't work.
		ldy	sendbufstart		; get index of last byte sent (use Y because X isn't free)
		iny				; increment it to get the next byte to be sent
		sty	sendbufstart		; update it
		lda	send_buffer, y		; get the character at the index
		jmp	CIOV			; and send it.
.endproc
		
font_path	.byte	"D:IBMPC.FNT", $9B
pallette_path	.byte	"D:ANSI.PAL", $9B
;test_file	.byte	"D:TEST.ANS", $9B
r_path		.byte	"R1:", $9B

;temp_char	.byte	$00			; temporary location for storing a character

xdl						; start of xdl

; displays 24 scanlines of no overlay (ANTIC display list should be displaying blank
; lines of GTIA background color)

		.byte	%00110100		; OVOFF, MAPOFF, RPTL - overlay off, color map off, repeat scanlines
		.byte	%00001000		; ATT - display size and overlay priority
		.byte	24-1			; 24 scanlines
		.byte	%00000001		; pallette 0, ANTIC normal mode
		.byte	%11111111		; overlay is priority over everything

; now on to the 80x24 text portion

		.byte	%01100001		; RPTL, OVADR
		.byte	%10000001		; CHBASE, XDL_END
		.byte	192-1			; 192 scanlines of text (24 rows)

; overlay address starts at top of memory - 3840. this means the last line is at the top of memory

		.faraddr $080000 - (80*24*2)	; overlay address starts at the top of VBXE memory - bytes per screen
		.word	80 + 80			; each line of text is 80 characters and 80 colors (80 + 80 bytes)
		.byte	$00			; font is at the beginning of memory (far from text window)
xdl_end

bcb_start					; start of blitter lists

bcb_one_down					; blitter to scroll one line down
		.faraddr $07B5A0		; top of VBXE ram is $80000. this address is 5 pages back, plus one line. (src)
                .word	80*2			; one line is 160 bytes wide, and we're working our way down, so positive
                .byte	1			; x step is 1 (we want forwards and to not skip stuff)
                .faraddr $07B500		; top of VBXE ram is $80000. this address is 5 pages back. (dst)
                .word	80*2			; x and y step is the same as the source ones
                .byte	1
                .word	(80*2)-1		; width same as y step less one
		.byte	(5*24)-2		; 5 pages less one line, then minus one because that's what the doc says
		.byte	$FF			; AND mask. don't modify the data
		.byte	$00			; XOR mask. don't modify the data
		.byte	$00			; no collisions
		.byte	$00			; 1:1 zoom
		.byte	$00			; no pattern
		.byte	%00001000		; NOT last entry, copy mode
		
		.faraddr 0			; doesn't matter
		.word	0			; doesn't matter
		.byte	0			; doesn't matter
		.faraddr $7FF60			; one line before the end of the screen
		.word	80*2			; y step really doesn't matter, since we're only doing one line, but it's 80 characters
		.byte	2			; x step is 2, we only want the character bytes, not color (for now)
		.word	80-1			; width is 80 bytes
		.byte	1-1			; just the last line
		.byte	0			; filling with a pattern
		.byte	0			; fill value is 0
		.byte	0			; no collisions
		.byte	0			; 1:1 zoom
		.byte	0			; no pattern
		.byte	%00001000	        ; NOT last entry, copy mode.
		
		.faraddr 0			; doesn't matter
		.word	0			; doesn't matter
		.byte	0			; doesn't matter
		.faraddr $7FF61			; one line before the end of the screen, and one more so we fill the color bytes.
		.word	80*2			; y step really doesn't matter, since we're only doing one line, but it's 80 characters
		.byte	2			; x step is 2, we only want the color bytes, not character
		.word	80-1			; width is 80 bytes
		.byte	1-1			; just the last line
		.byte	0			; filling with a pattern
scroll_1d_color	.byte	0			; fill value will be changed by whatever uses this blitter list
		.byte	0			; no collisions
		.byte	0			; 1:1 zoom
		.byte	0			; no pattern
		.byte	0			; last entry, copy mode.
		
bcb_clr_scr					; blitter to scroll a whole page up
		.faraddr $07C400		; top of VBXE ram is $80000. this address is 4 pages back. (src)
                .word	80*2			; one line is 160 bytes wide, and we're working our way down, so positive
                .byte	1			; x step is 1 (we want forwards and to not skip stuff)
                .faraddr $07B500		; top of VBXE ram is $80000. this address is 5 pages back. (dst)
                .word	80*2			; x and y step is the same as the source ones
                .byte	1
                .word	(80*2)-1		; width same as y step less one
		.byte	(4*24)-1		; number of lines to move less one
		.byte	$FF			; AND mask. don't modify the data
		.byte	$00			; XOR mask. don't modify the data
		.byte	$00			; no collisions
		.byte	$00			; 1:1 zoom
		.byte	$00			; no pattern
		.byte	%00001000		; NOT last entry, copy mode

		.faraddr 0			; doesn't matter
		.word	0			; doesn't matter
		.byte	0			; doesn't matter
		.faraddr $7F100			; one page before the end of the screen
		.word	80*2			; y step is 80 characters
		.byte	2			; x step is 2, we only want the character bytes, not color
		.word	80-1			; width is 80 bytes
		.byte	24-1			; 24 lines
		.byte	0			; filling with a pattern
		.byte	0			; fill value is 0
		.byte	0			; no collisions
		.byte	0			; 1:1 zoom
		.byte	0			; no pattern
		.byte	%00001000		; NOT last entry, copy mode.
		
		.faraddr 0			; doesn't matter
		.word	0			; doesn't matter
		.byte	0			; doesn't matter
		.faraddr $7F101			; one page before the end of the screen, and one more so we fill the color bytes.
		.word	80*2			; y step really doesn't matter, since we're only doing one line, but it's 80 characters
		.byte	2			; x step is 2, we only want the color bytes, not characters
		.word	80-1			; width is 80 bytes
		.byte	24-1			; 24 lines
		.byte	0			; filling with a pattern
clr_scr_color	.byte	0			; fill value will be changed by whatever uses this blitter list
		.byte	0			; no collisions
		.byte	0			; 1:1 zoom
		.byte	0			; no pattern
		.byte	0			; last entry, copy mode.
		
bcb_end

;###################################################################################################################
; table of addresses for control function handlers
C0_handler_table
		.word	NUL_adr
		.word	SOH_adr
		.word	STX_adr
		.word	ETX_adr
		.word	EOT_adr
		.word	ENQ_adr
		.word	ACK_adr
		.word	BEL_adr
		.word	BS_adr
		.word	HT_adr
		.word	LF_adr
		.word	VT_adr
		.word	FF_adr
		.word	CR_adr
		.word	SO_adr
		.word	SI_adr
		.word	DLE_adr
		.word	DC1_adr
		.word	DC2_adr
		.word	DC3_adr
		.word	DC4_adr
		.word	NAK_adr
		.word	SYN_adr
		.word	ETB_adr
		.word	CAN_adr
		.word	EM_adr
		.word	SUB_adr
		.word	ESC_adr
		.word	IS4_adr
		.word	IS3_adr
		.word	IS2_adr
		.word	IS1_adr
		
C1_handler_table
		.word	NUL_adr			; this one is unused
		.word	NUL_adr			; so is this one
		.word	BPH_adr
		.word	NBH_adr
		.word	IND_adr
		.word	NEL_adr
		.word	SSA_adr
		.word	ESA_adr
		.word	HTS_adr
		.word	HTJ_adr
		.word	VTS_adr
		.word	PLD_adr
		.word	PLU_adr
		.word	RI_adr
		.word	SS2_adr
		.word	SS3_adr
		.word	DCS_adr
		.word	PU1_adr
		.word	PU2_adr
		.word	STS_adr
		.word	CCH_adr
		.word	MW_adr
		.word	SPA_adr
		.word	EPA_adr
		.word	SOS_adr
		.word	NUL_adr			; unused
		.word	SCI_adr
		.word	CSI_adr
		.word	ST_adr
		.word	OSC_adr
		.word	PM_adr
		.word	APC_adr
		
;###################################################################################################################
; table of addresses for control sequences
; entry format is this: final byte, intermediate byte, low address, high address
; last entry has 0 for final byte
; if there is no intermediate byte, then it is 0 in the entry.
; I can either implement a sorted list here and do a binary search in the future, or I can implement a list sorted so that more common
; control sequences come first. I don't know which I'll choose for the final design yet, but I'll choose at some point.

ctrl_seq_table
		.byte	'C', 0
		.word	CUF_adr			; cursor forward (right)
		.byte	'A', 0
		.word	CUU_adr			; cursor up
		.byte	'B', 0
		.word	CUD_adr			; cursor down
		.byte	'D', 0
		.word	CUB_adr			; cursor back (left)
		.byte	'H', 0
		.word	CUP_adr			; cursor position
		.byte	'J', 0
		.word	ED_adr			; erase in display
		.byte	'K', 0
		.word	EL_adr			; erase in line
		.byte	'm', 0
		.word	SGR_adr			; set graphics rendition
		.byte	0			; this shows the end of the list.
		
;###################################################################################################################
; keycode to ASCII table
; zero means 'do nothing' for now
;		.byte	ascii-val		;key number - ascii mapping - atari key

keycode_table	.byte	$6C			;0 - l - l
		.byte	$6A			;1 - j - j
		.byte	$3B			;2 - ; - ;
		.byte	0			;3 - no key
		.byte	0			;4 - no key
		.byte	$6B			;5 - k - k
		.byte	$2B			;6 - + - +
		.byte	$2A			;7 - * - *
		.byte	$6F			;8 - o - o
		.byte	0			;9 - no key
		.byte	$70			;10 - p - p
		.byte	$75			;11 - u - u
		.byte	$0D			;12 - CR - return
		.byte	$69			;13 - i - i
		.byte	$2D			;14 - minus sign - minus sign
		.byte	$3D			;15 - = - =
		.byte	$76			;16 - v - v
		.byte	0			;17 - n/a - help
		.byte	$63			;18 - c - c
		.byte	0			;19 - no key
		.byte	0			;20 - no key
		.byte	$62			;21 - b - b
		.byte	$78			;22 - x - x
		.byte	$7A			;23 - z - z
		.byte	$34			;24 - 4 - 4
		.byte	0			;25 - no key
		.byte	$33			;26 - 3 - 3
		.byte	$36			;27 - 6 - 6
		.byte	$1B			;28 - esc - esc
		.byte	$35			;29 - 5 - 5
		.byte	$32			;30 - 2 - 2
		.byte	$31			;31 - 1 - 1
		.byte	$2C			;32 - , - ,
		.byte	$20			;33 - space - space bar
		.byte	$2E			;34 - . - .
		.byte	$6E			;35 - n - n
		.byte	0			;36 - no key
		.byte	$6D			;37 - m - m
		.byte	$2F			;38 - / - /
		.byte	0			;39 - n/a - inverse/atari
		.byte	$72			;40 - r - r
		.byte	0			;41 - no key
		.byte	$65			;42 - e - e
		.byte	$79			;43 - y - y
		.byte	$9			;44 - HT - tab
		.byte	$74			;45 - t - t
		.byte	$77			;46 - w - w
		.byte	$71			;47 - q - q
		.byte	$39			;48 - 9 - 9
		.byte	0			;49 - no key
		.byte	$30			;50 - 0 - 0
		.byte	$37			;51 - 7 - 7
		.byte	$8			;52 - BS - bk sp
		.byte	$38			;53 - 8 - 8
		.byte	$3C			;54 - < - <
		.byte	$3E			;55 - > - >
		.byte	$66			;56 - f - f
		.byte	$68			;57 - h - h
		.byte	$64			;58 - d - d
		.byte	0			;59 - no key
		.byte	0			;60 - n/a - caps
		.byte	$67			;61 - g - g
		.byte	$73			;62 - s - s
		.byte	$61			;63 - a - a

; from here down, everything is a repeat of the above 63 keys, but plus shift

		.byte	$4C			;64 - L - L
		.byte	$4A			;65 - J - J
		.byte	$3A			;66 - : - :
		.byte	0			;67 - no key
		.byte	0			;68 - no key
		.byte	$4B			;69 - K - K
		.byte	$5C			;70 - \ - \
		.byte	$5E			;71 - ^ - ^
		.byte	$4F			;72 - O - O
		.byte	0			;73 - no key
		.byte	$50			;74 - P - P
		.byte	$55			;75 - U - U
		.byte	$0D			;76 - CR - shift+return
		.byte	$49			;77 - I - I
		.byte	$5F			;78 - _ - _
		.byte	$7C			;79 - | - |
		.byte	$56			;80 - V - V
		.byte	0			;81 - n/a - shift+help
		.byte	$43			;82 - C - C
		.byte	0			;83 - no key
		.byte	0			;84 - no key
		.byte	$42			;85 - B - B
		.byte	$58			;86 - X - X
		.byte	$5A			;87 - Z - Z
		.byte	$24			;88 - $ - $
		.byte	0			;89 - no key
		.byte	$23			;90 - # - #
		.byte	$26			;91 - & - &
		.byte	$1B			;92 - esc - shift+esc
		.byte	$25			;93 - % - %
		.byte	$22			;94 - " - "
		.byte	$21			;95 - ! - !
		.byte	$5B			;96 - [ - [
		.byte	$20			;97 - space - shift+space
		.byte	$5D			;98 - ] - ]
		.byte	$4E			;99 - N - N
		.byte	0			;100 - no key
		.byte	$4D			;101 - M - M
		.byte	$3F			;102 - ? - ?
		.byte	0			;103 - n/a - inverse
		.byte	$52			;104 - R - R
		.byte	0			;105 - no key
		.byte	$45			;106 - E - E
		.byte	$59			;107 - Y - Y
		.byte	$9			;108 - HT - shift+tab
		.byte	$54			;109 - T - T
		.byte	$57			;110 - W - W
		.byte	$51			;111 - Q - Q
		.byte	$28			;112 - ( - (
		.byte	0			;113 - no key
		.byte	$29			;114 - ) - )
		.byte	$27			;115 - ' - '
		.byte	$7F			;116 - DEL - shift+BS
		.byte	$40			;117 - @ - @
		.byte	$0C			;118 - FF - clear
		.byte	0			;119 - n/a - insert
		.byte	$46			;120 - F - F
		.byte	$48			;121 - H - H
		.byte	$44			;122 - D - D
		.byte	0			;123 - no key
		.byte	0			;124 - n/a - caps
		.byte	$47			;125 - G - G
		.byte	$53			;126 - S - S
		.byte	$41			;127 - A - A

; from here down, everything is a repeat of the first 63 keys, but plus control

		.byte	$C			;128 - FF - ctrl+l
		.byte	$A			;129 - LF - ctrl+j
		.byte	0			;130 - n/a - ctrl+;
		.byte	0			;131 - no key
		.byte	0			;132 - no key
		.byte	$B			;133 - VT - ctrl+k
		.byte	$1C			;134 - FS - ctrl++ (ctrl+\)
		.byte	$1E			;135 - RS - ctrl+* (ctrl+^)
		.byte	$F			;136 - SI - ctrl+o
		.byte	0			;137 - no key
		.byte	$10			;138 - DLE - ctrl+p
		.byte	$15			;139 - NAK - ctrl+u
		.byte	0			;140 - n/a - ctrl+return
		.byte	$9			;141 - HT - ctrl+i
		.byte	$1F			;142 - US - ctrl+- (ctrl+_)
		.byte	0			;143 - n/a - ctrl+=
		.byte	$16			;144 - SYN - ctrl+v
		.byte	0			;145 - n/a - ctrl+help
		.byte	$3			;146 - ETX - ctrl+c
		.byte	0			;147 - no key
		.byte	0			;148 - no key
		.byte	$2			;149 - STX - ctrl+b
		.byte	$18			;150 - CAN - ctrl+x
		.byte	$1A			;151 - SUB - ctrl+z
		.byte	0			;152 - n/a - ctrl+4
		.byte	0			;153 - no key
		.byte	0			;154 - n/a - ctrl+3
		.byte	0			;155 - n/a - ctrl+6
		.byte	0			;156 - n/a - ctrl+esc
		.byte	0			;157 - n/a - ctrl+5
		.byte	0			;158 - n/a - ctrl+2
		.byte	0			;159 - n/a - ctrl+1
		.byte	$1B			;160 - ESC - ctrl+, (ctrl+[)
		.byte	0			;161 - n/a - ctrl+space
		.byte	$1D			;162 - GS - ctrl+. (ctrl+])
		.byte	$E			;163 - SO - ctrl+n
		.byte	0			;164 - no key
		.byte	$D			;165 - CR - ctrl+m
		.byte	$0F			;166 - SI - ctrl+/ (ctrl+?)
		.byte	0			;167 - n/a - inverse
		.byte	$12			;168 - DC2 - ctrl+r
		.byte	0			;169 - no key
		.byte	$05			;170 - ENQ - ctrl+e
		.byte	$19			;171 - EM - ctrl+y
		.byte	0			;172 - n/a - ctrl+tab
		.byte	$14			;173 - DC4 - ctrl+t
		.byte	$17			;174 - ETB - ctrl+w
		.byte	$11			;175 - DC1 - ctrl+q
		.byte	0			;176 - n/a - ctrl+9
		.byte	0			;177 - no key
		.byte	0			;178 - n/a - ctrl+0
		.byte	0			;179 - n/a - ctrl+7
		.byte	0			;180 - n/a - ctrl+BS
		.byte	0			;181 - n/a - ctrl+8
		.byte	0			;182 - n/a - ctrl+clear
		.byte	0			;183 - n/a - ctrl+insert
		.byte	$6			;184 - ACK - ctrl+f
		.byte	$8			;185 - BS - ctrl+h
		.byte	$4			;186 - EOT - ctrl+d
		.byte	0			;187 - no key
		.byte	0			;188 - n/a - caps
		.byte	$7			;189 - BEL - ctrl+g
		.byte	$13			;190 - DC3 - ctrl+s
		.byte	$1			;191 - SOH - ctrl+a

; from here down, everything is a repeat of the first 63 keys, but plus control and shift
; some of these key combos do not work due to the matrix design
; these are marked with *

		.byte	$C			;*192 - FF - ctrl+L
		.byte	$A			;*193 - LF - ctrl+J
		.byte	0			;*194 - n/a - ctrl+:
		.byte	0			;*195 - no key
		.byte	0			;*196 - no key
		.byte	$B			;*197 - VT - ctrl+K
		.byte	$1C			;*198 - FS - ctrl+\
		.byte	$1E			;*199 - SO - ctrl+^
		.byte	$F			;200 - SI - ctrl+O
		.byte	0			;201 - no key
		.byte	$10			;202 - DLE - ctrl+P
		.byte	$15			;203 - NAK - ctrl+U
		.byte	0			;204 - n/a - ctrl+shift+return
		.byte	$9			;205 - HT - ctrl+I
		.byte	$1F			;206 - US - ctrl+_
		.byte	0			;207 - n/a - ctrl+|
		.byte	$16			;*208 - SYN - ctrl+V
		.byte	0			;*209 - n/a - ctrl+shift+help
		.byte	$3			;*210 - ETX - ctrl+C
		.byte	0			;*211 - no key
		.byte	0			;*212 - no key
		.byte	$2			;*213 - STX - ctrl+B
		.byte	$18			;*214 - CAN - ctrl+X
		.byte	$1A			;*215 - SUB - ctrl+Z
		.byte	0			;216 - n/a - ctrl+$
		.byte	0			;217 - no key
		.byte	0			;218 - n/a - ctrl+#
		.byte	0			;219 - n/a - ctrl+&
		.byte	0			;220 - n/a - ctrl+shift+esc
		.byte	0			;221 - n/a - ctrl+%
		.byte	0			;222 - n/a - ctrl+"
		.byte	0			;223 - n/a - ctrl+!
		.byte	$1B			;224 - ESC - ctrl+[
		.byte	0			;225 - n/a - ctrl+shift+space
		.byte	$1D			;226 - GS - ctrl+]
		.byte	$E			;227 - SO - ctrl+N
		.byte	0			;228 - no key
		.byte	$D			;229 - CR - ctrl+M
		.byte	$1F			;230 - US - ctrl+?
		.byte	0			;231 - n/a - ctrl+inverse
		.byte	$12			;232 - DC2 - ctrl+R
		.byte	0			;233 - no key
		.byte	$05			;234 - ENQ - ctrl+E
		.byte	$19			;235 - EM - ctrl+Y
		.byte	0			;236 - n/a - ctrl+shift+tab
		.byte	$14			;237 - DC4 - ctrl+T
		.byte	$17			;238 - ETB - ctrl+W
		.byte	$11			;239 - DC1 - ctrl+Q
		.byte	0			;240 - n/a - ctrl+(
		.byte	0			;241 - no key
		.byte	0			;242 - n/a - ctrl+)
		.byte	0			;243 - n/a - ctrl+'
		.byte	0			;244 - n/a - ctrl+shift+BS
		.byte	0			;245 - n/a - ctrl+@ (no way to send a null, but this is null)
		.byte	0			;246 - n/a - ctrl+shift+clear
		.byte	0			;247 - n/a - ctrl+shift+insert (no function yet)
		.byte	$6			;248 - ACK - ctrl+F
		.byte	$8			;249 - BS - ctrl+H
		.byte	$4			;250 - EOT - ctrl+D
		.byte	0			;251 - no key
		.byte	0			;252 - n/a - caps
		.byte	$7			;253 - BEL - ctrl+G
		.byte	$13			;254 - DC3 - ctrl+S
		.byte	$1			;255 - SOH - ctrl+A

; Version number field
version		.byte	"v0.03.2026.04.14"

end						;should be plenty of space after this that is free (like for MEMAC window)
