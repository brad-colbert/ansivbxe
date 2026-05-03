;######################################################################################################################################
;
;
;	   ##	 ##   #	  ####	  ###		 #     # #####	 #     # ######
;	  #  #	 # #  #	 #    #	   #		 #     #  #   #	  #   #	  #   #
;	 #    #	 #  # #	 #	       #	     #     #  #   #	   # #	  #   
;	 #    #	 #   ##	  ####	   #	     #     #  ####	    #     ####
;	 ######	 #    #	      #	   #		  #   #	  #   #	   # #	  #   
;	 #    #	 #    #	 #    #	   #		   # #	  #   #	  #   #	  #   #
;	 #    #	 #    #	  ####	  ###		    #	 #####	 #     # ######
;
;	 ####### ######	 #####	 ##   ##  ###	 ##   #	   ##	 ###
;	 #  #  #  #   #	  #   #	 # # # #   #	 # #  #	  #  #	  #
;	    #	  # #	  #   #	 #  #  #   #	 #  # #	 #    #	  #
;	    #	  ###	  ####	 #     #   #	 #   ##	 #    #	  #
;	    #	  # #	  # #	 #     #   #	 #    #	 ######	  #
;	    #	  #   #	  #  #	 #     #   #	 #    #	 #    #	  #   #
;	   ###	 ######	 ###  #	 #     #  ###	 #    #	 #    #	 ######              !!CA65!!
;
;	Converted by:     Brad Colbert
;	Original MADS by: Joseph Zatarski
;	Version: v0.09
;
;	terminal emulator that supports ANSI/ECMA-48 control sequences and a 256 character font
;######################################################################################################################################
;
; TODO:	(from Joey Z) add recieve buffer so that I don't call CIOV to do one character at a time. (done)
;	label scroll contains some unnecesary math (refer to comments near it) (done)
;	add stuff beyond just the C0 (ASCII) and C1 control character/sequence sets (this means finally starting on the cool stuff)
;		SGR - set graphics rendition (color, high intensity, etc.) - done
;		add J code - ED - erase in display (modes 0, 1, 2) - done
;		add A code - CUU - cursor up - done
;		add B code - CUD - cursor down - done
;		add C code - CUF - cursor forward (right) - done
;		add D code - CUB - cursor back (left) - done
;		add H code - CUP - cursor position (absolute) - done
;		add K code - EL - erase in line (modes 0, 1, 2) - done
;		add s code - SCP - save cursor position - done
;		add u code - RCP - restore cursor position - done
;		add f code - HVP - horizontal/vertical position (alias for CUP) - done
;		add E code - CNL - cursor next line - done
;		add F code - CPL - cursor previous line - done
;		add G code - CHA - cursor horizontal absolute - done
;		add S code - SU - scroll up - done
;		add T code - SD - scroll down - done
;

	.setcpu "6502"
	.feature labels_without_colons
	.feature org_per_seg

	.include "atarios_ca65.inc"		; atari OS equates,
	.include "atarihardware_ca65.inc"	; general atari hardware equates,
	.include "VBXE_ca65.inc"		; and VBXE equates

	.import	_vbxe_init, _vbxe_load_files, _vbxe_shutdown

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
saved_row	= $96				; saved cursor row for SCP/RCP
saved_column	= $97				; saved cursor column for SCP/RCP
saved_cur_lo	= $98				; saved cursor_address low byte
saved_cur_hi	= $99				; saved cursor_address high byte
device_type	= $9A				; 0 = R: serial, 1 = N: FujiNet
n_err_code	= $9B				; saved error code from open_n_device
n_unit		= $9C				; FujiNet unit number (1–8), parsed from URL
n_trip		= $9D				; PROCEED interrupt trip flag (0=idle, 1=FujiNet has data)
lf_mode		= $9E				; LF-as-CRLF flag (0=LF only, 1=LF implies CR+LF)
saved_sdmctl	= $9F				; SDMCTL value saved at startup, restored on exit

SOUNDR		= $41				; OS SIO bus sound enable (0 = silent)

	.segment "CODE"
	.org	$2800				; start of program
; apparently this is safe for most DOSes

;###################################################################################################################
; VBXE initialization
; check core version. needs to be fx core.
start
		jsr	_vbxe_init
		bne	vbxe_ok

; print an error message in case of missing or non fx core VBXE
; just set the ICBA and call another routine since printing to E: will be used twice.
		lda	#$00
		sta	memac_bank_sel		; close MEMAC window if it was left open
		sta	memac_control		; disable MEMAC CPU mapping
		sta	video_control		; disable VBXE video path
		lda	#$22
		sta	SDMCTL			; restore a normal ANTIC text DMA mode
		lda	#<no_vbxe_msg
		sta	ICBA
		lda	#>no_vbxe_msg
		sta	ICBA + 1
		jmp	print_error

vbxe_ok
		lda	#<vbxe_load_cfg
		ldx	#>vbxe_load_cfg
		jsr	_vbxe_load_files
		bne	vbxe_load_ok

; library file-load failed; force ANTIC text mode and show a startup error.
		lda	#$00
		sta	memac_bank_sel
		sta	memac_control
		sta	video_control
		lda	#$22
		sta	SDMCTL
		lda	#<load_fail_msg
		sta	ICBA
		lda	#>load_fail_msg
		sta	ICBA + 1
		jmp	print_error

vbxe_load_ok
		jmp	init_terminal_state
		
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
		jmp	exit_to_dos


no_vbxe_msg					; message to display for missing VBXE or non-fx core
		.byte	"No VBXE or non-fx core. Press return to continue.", $9B

load_fail_msg					; message to display if library load step fails
		.byte	"VBXE startup load failed. Press return to continue.", $9B

vbxe_load_cfg					; vbxe_load_cfg_t for _vbxe_load_files
		.addr	font_path
		.addr	pallette_path
		.addr	xdl
		.word	bcb_end - xdl

;###################################################################################################################
; now we start initializing the variables for the terminal state
; initialize the cursor address to be at the home position
init_terminal_state

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

; device type: 0 = R:, 1 = N:
		sta	device_type

; Save OS vectors/PACTL once so exit_to_dos can always restore cleanly.
		lda	VKEYBD
		sta	old_vkeybd
		lda	VKEYBD+1
		sta	old_vkeybd+1
		lda	VPRCED
		sta	n_old_vprced
		lda	VPRCED+1
		sta	n_old_vprced+1
		lda	PACTL
		sta	n_old_pactl

; Install RESET warmstart hook so pressing RESET restores ANTIC/VBXE state first.
		lda	DOSINI
		sta	old_dosini
		lda	DOSINI+1
		sta	old_dosini+1
		lda	#<reset_cleanup
		sta	DOSINI
		lda	#>reset_cleanup
		sta	DOSINI+1

; Silence the OS SIO bus sound (the per-byte click/whine) for the duration of the session.
; TEMPORARILY DISABLED 2026-05-02 — investigating whether SOUNDR=0 was breaking SSH connections.
; Save/restore plumbing kept in place; just skipping the actual silence write for now.
		lda	SOUNDR
		sta	saved_soundr
;		lda	#$00
;		sta	SOUNDR

; LF-as-CRLF mode: default on (most hosts send bare LF expecting terminal to add CR)
		lda	#$01
		sta	lf_mode
		lda	#$00

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

;###################################################################################################################
; device selection: prompt the user to choose R: serial or N: FujiNet

device_select
		jsr	scroll_page		; clear screen
		lda	#$00			; move cursor to top-left
		sta	row
		sta	column
		jsr	recalc_cursor
		lda	#<banner_msg
		ldx	#>banner_msg
		jsr	print_str
		jsr	CR_adr
		jsr	LF_adr
		lda	#<select_prompt
		ldx	#>select_prompt
		jsr	print_str

; make sure IOCB 2 is closed before we open K: on it
		ldx	#$20
		lda	#$0C
		sta	ICCOM+$20
		jsr	CIOV

; open K: on IOCB 2 for immediate (non-line-buffered) keyboard reads
		ldx	#$20
		lda	#$03			; CMD_OPEN
		sta	ICCOM+$20
		lda	#<kbd_dev
		sta	ICBA+$20
		lda	#>kbd_dev
		sta	ICBA+$21
		lda	#$04			; OREAD
		sta	ICAX1+$20
		lda	#$00
		sta	ICAX2+$20
		jsr	CIOV

; read one key (K: returns immediately on key press, no Enter needed)
		ldx	#$20
		lda	#$07			; GET_CHARS
		sta	ICCOM+$20
		lda	#<select_buf
		sta	ICBA+$20
		lda	#>select_buf
		sta	ICBA+$21
		lda	#$01
		sta	ICBL+$20
		lda	#$00
		sta	ICBL+$21
		jsr	CIOV

		lda	select_buf
		cmp	#'N'
		beq	choose_n
		cmp	#'n'
		beq	choose_n
;		cmp	#'Q'
;		beq	choose_quit
;		cmp	#'q'
;		beq	choose_quit

choose_r
; echo 'R' to VBXE, close K:, open R: serial device
		lda	#$00
		sta	device_type		; R: = 0 (clear in case we're retrying after a failed N: attempt)
		lda	#'R'
		sta	temp_char
		jsr	process_char
		jsr	CR_adr
		jsr	LF_adr
		ldx	#$20
		lda	#$0C			; CMD_CLOSE K:
		sta	ICCOM+$20
		jsr	CIOV
		jsr	open_r_device
		jmp	device_open

;choose_quit
;; Close K: on IOCB 2, clean up VBXE, and exit to DOS.
;		ldx	#$20
;		lda	#$0C			; CMD_CLOSE K:
;		sta	ICCOM+$20
;		jsr	CIOV
;		jmp	exit_to_dos

choose_n
; Echo 'N', newline, then step the user through connection details.
		lda	#'N'
		sta	temp_char
		jsr	process_char
		jsr	CR_adr
		jsr	LF_adr

; Always N: unit 1, device type N:
		lda	#$01
		sta	n_unit
		sta	device_type

; Clear caps lock (Atari: unshifted=uppercase, Shift=lowercase)
		lda	#$00
		sta	SHFLOK

; --- PROTOCOL ---
proto_again	lda	#<proto_prompt		; "PROTOCOL [T]CP [S]SH: "
		ldx	#>proto_prompt
		jsr	print_str
		jsr	open_k_iocb2
		ldx	#$20
		lda	#$07			; GET_CHARS — one char
		sta	ICCOM+$20
		lda	#<temp_char
		sta	ICBA+$20
		lda	#>temp_char
		sta	ICBA+$21
		lda	#$01
		sta	ICBL+$20
		lda	#$00
		sta	ICBL+$21
		jsr	CIOV
		ldx	#$20			; close K: IOCB 2
		lda	#$0C
		sta	ICCOM+$20
		jsr	CIOV
		lda	temp_char
		and	#$DF			; force uppercase
		cmp	#'T'
		beq	proto_tcp
		cmp	#'S'
		beq	proto_ssh
		jmp	proto_again		; invalid key, retry

proto_tcp	lda	#'T'
		jmp	proto_store
proto_ssh	lda	#'S'
proto_store	sta	proto_byte
		sta	temp_char
		jsr	process_char		; echo choice letter
		jsr	CR_adr
		jsr	LF_adr

; --- SERVER ---
		lda	#<server_prompt		; "SERVER: "
		ldx	#>server_prompt
		jsr	print_str
		jsr	open_k_iocb2
		lda	#<server_buf
		sta	src_ptr
		lda	#>server_buf
		sta	src_ptr+1
		jsr	read_line_vbxe
		jsr	CR_adr
		jsr	LF_adr

; --- PORT ---
		lda	#<port_prompt		; "PORT (Enter for default): "
		ldx	#>port_prompt
		jsr	print_str
		jsr	open_k_iocb2
		lda	#<port_buf
		sta	src_ptr
		lda	#>port_buf
		sta	src_ptr+1
		jsr	read_line_vbxe
		jsr	CR_adr
		jsr	LF_adr

; Skip credentials for TCP (telnet) — only SSH needs them
		lda	proto_byte
		cmp	#'T'
		beq	build_url

; --- USER ---
		lda	#<user_prompt		; "USER: "
		ldx	#>user_prompt
		jsr	print_str
		jsr	open_k_iocb2
		lda	#<login_buf
		sta	src_ptr
		lda	#>login_buf
		sta	src_ptr+1
		jsr	read_line_vbxe
		jsr	CR_adr
		jsr	LF_adr

; --- PASSWORD ---
		lda	#<pw_prompt		; "PASSWORD: "
		ldx	#>pw_prompt
		jsr	print_str
		jsr	open_k_iocb2
		lda	#<password_buf
		sta	src_ptr
		lda	#>password_buf
		sta	src_ptr+1
		jsr	read_line_vbxe_pw	; echoes asterisks
		jsr	CR_adr
		jsr	LF_adr

; --- BUILD URL ---
build_url
; Construct "N1:TCP://server:port" or "N1:SSH://server:port" in n_url_buf.
		lda	#<n_url_buf
		sta	dst_ptr
		lda	#>n_url_buf
		sta	dst_ptr+1

		lda	#<n1_str		; "N1:"
		sta	src_ptr
		lda	#>n1_str
		sta	src_ptr+1
		jsr	copy_str

		lda	proto_byte
		cmp	#'T'
		bne	url_ssh
		lda	#<tcp_url_str		; "TCP://"
		sta	src_ptr
		lda	#>tcp_url_str
		sta	src_ptr+1
		jmp	url_proto_done
url_ssh		lda	#<ssh_url_str		; "SSH://"
		sta	src_ptr
		lda	#>ssh_url_str
		sta	src_ptr+1
url_proto_done	jsr	copy_str

		lda	#<server_buf		; hostname
		sta	src_ptr
		lda	#>server_buf
		sta	src_ptr+1
		jsr	copy_str

		lda	#':'			; separator
		jsr	put_byte_dst

		lda	port_buf		; did user enter a port?
		cmp	#$9B
		bne	url_user_port
		lda	proto_byte		; no — use default
		cmp	#'T'
		bne	url_ssh_default
		lda	#<tcp_port_str		; "23"
		sta	src_ptr
		lda	#>tcp_port_str
		sta	src_ptr+1
		jmp	url_port_done
url_ssh_default	lda	#<ssh_port_str		; "22"
		sta	src_ptr
		lda	#>ssh_port_str
		sta	src_ptr+1
		jmp	url_port_done
url_user_port	lda	#<port_buf
		sta	src_ptr
		lda	#>port_buf
		sta	src_ptr+1
url_port_done	jsr	copy_str

		lda	#$9B			; FujiNet URL terminator
		jsr	put_byte_dst

; pre-configure SSH credentials via $FD/$FE before open (SSH only)
		lda	proto_byte
		cmp	#'S'
		bne	skip_nlogin
		jsr	nlogin_n_device
skip_nlogin

		lda	#<connecting_msg
		ldx	#>connecting_msg
		jsr	print_str

		jsr	open_n_device
		bmi	n_open_failed

		lda	#<n_open_ok_msg
		ldx	#>n_open_ok_msg
		jsr	print_str
		jmp	device_open

n_open_failed
		sty	n_err_code		; save CIO error code before any other call corrupts Y
		lda	#<no_n_msg
		ldx	#>no_n_msg
		jsr	print_str		; "FujiNet open failed: $"
		lda	n_err_code
		jsr	print_hex_byte		; display two hex digits of error code
		lda	#<press_return_msg
		ldx	#>press_return_msg
		jsr	print_str
		jmp	wait_for_return

wait_for_return
		lda	#$05			; GET_REC on IOCB 0 — waits for Enter
		sta	ICCOM
		lda	#<select_buf
		sta	ICBA
		lda	#>select_buf
		sta	ICBA+1
		lda	#$04
		sta	ICBL
		lda	#$00
		sta	ICBL+1
		jsr	CIOV
		jmp	device_select

device_open
; flush any keystrokes buffered during device selection
		lda	#$00
		sta	sendbufstart
		sta	sendbufend
; save old VKEYBD then install our keyboard handler
		sei				; disable interrupts while changing vectors
		lda	VKEYBD
		sta	old_vkeybd
		lda	VKEYBD+1
		sta	old_vkeybd+1
		lda	#<kbd_irq
		sta	VKEYBD
		lda	#>kbd_irq
		sta	VKEYBD+1
		cli				; re-enable interrupts

; for N: install PROCEED interrupt so FujiNet signals when data is available
		lda	device_type
		beq	wait_for_byte		; R: — no PROCEED interrupt needed

		lda	PACTL
		sta	n_old_pactl
		and	#$FE			; disable PROCEED IRQ while changing vector
		sta	PACTL
		lda	VPRCED
		sta	n_old_vprced
		lda	VPRCED+1
		sta	n_old_vprced+1
		lda	#<n_proceed_irq
		sta	VPRCED
		lda	#>n_proceed_irq
		sta	VPRCED+1
		lda	#$00
		sta	n_trip			; no data waiting yet
		lda	PACTL
		ora	#$01			; enable PROCEED IRQ
		sta	PACTL

wait_for_byte	jsr	check_sendbuf
		lda	device_type
		beq	r_do_recv		; R: — always poll
		lda	n_trip			; N: — only recv when FujiNet has signalled data
		beq	wait_for_byte
r_do_recv	jsr	recv_from_device
		jmp	wait_for_byte		; n_trip clear + PROCEED re-arm now happen inside recv_from_device

handle_disconnect_n
; Tear down the PROCEED interrupt, close N:, print message, restart device selection.
		lda	PACTL
		and	#$FE
		sta	PACTL			; disable PROCEED IRQ
		lda	n_old_vprced
		sta	VPRCED
		lda	n_old_vprced+1
		sta	VPRCED+1		; restore old VPRCED vector
		lda	PACTL
		and	#$FE
		ora	n_old_pactl
		sta	PACTL			; restore old IRQ enable state
		jsr	nclose_n_device		; send CLOSE to FujiNet
; restore the OS keyboard IRQ so K: CIO reads work at device selection
		sei
		lda	old_vkeybd
		sta	VKEYBD
		lda	old_vkeybd+1
		sta	VKEYBD+1
		cli
		lda	#$00
		sta	device_type		; back to no device selected
		lda	#<disconnected_msg
		ldx	#>disconnected_msg
		jsr	print_str
		jsr	CR_adr
		jsr	LF_adr
		jmp	device_select

.proc recv_from_device
		lda	device_type
		bne	n_recv

; R: path — poll concurrent I/O status buffer
		ldx	#$10
		lda	#13			; CMD_STATUS
		sta	ICCOM+$10
		lda	#<r_path
		sta	ICBA+$10
		lda	#>r_path
		sta	ICBA+$11
		lda	#0
		sta	ICAX1+$10
		sta	ICAX2+$10
		jsr	CIOV
		jmp	check_dvstat

; N: path — SIO STATUS to check bytes waiting, then SIO READ
; Clear n_trip and re-arm PROCEED up front so any new burst arriving during
; STATUS/READ/process is caught on the next wait_for_byte pass. Covers all exit
; paths (no-data, disconnect, full read).
n_recv		lda	#$00
		sta	n_trip
		lda	PACTL
		ora	#$01
		sta	PACTL
		lda	#FUJI_ID
		sta	DDEVIC
		lda	n_unit
		sta	DUNIT
		lda	#'S'			; Status command
		sta	DCOMND
		lda	#$40			; read direction (FujiNet sends us 4 status bytes)
		sta	DSTATS
		lda	#<DVSTAT0
		sta	DBUFLO
		lda	#>DVSTAT0
		sta	DBUFHI
		lda	#FUJI_TIMEOUT
		sta	DTIMLO
		lda	#$00
		sta	DTIMHI
		lda	#$04			; 4 status bytes into DVSTAT0-DVSTAT3
		sta	DBYTLO
		lda	#$00
		sta	DBYTHI
		sta	DAUX1			; DAUX must be 0 for STATUS (not the byte count)
		sta	DAUX2
		jsr	SIOV
		bpl	n_recv_status_ok	; positive result → no SIO error
		jmp	n_recv_disconnect	; SIO error (timeout/NAK) → disconnected
n_recv_status_ok
		lda	DVSTAT2			; connection flag (C field): 0 = not connected
		bne	n_recv_dvstat_ok	; non-zero = still connected, proceed
		jmp	n_recv_disconnect	; C=0 → disconnected
n_recv_dvstat_ok
		lda	DVSTAT0			; bytes waiting (lo + hi)
		ora	DVSTAT1
		bne	n_recv_read
		jmp	done			; nothing waiting
n_recv_read

; Clamp to 255 bytes max
		lda	DVSTAT1
		bne	use_max
		lda	DVSTAT0
		bne	use_lo
use_max		lda	#$FF
use_lo		sta	recvbuflen		; how many bytes to read

; SIO READ
		lda	#FUJI_ID
		sta	DDEVIC
		lda	n_unit
		sta	DUNIT
		lda	#'R'			; Read command
		sta	DCOMND
		lda	#$40			; read direction
		sta	DSTATS
		lda	#<recv_buffer
		sta	DBUFLO
		lda	#>recv_buffer
		sta	DBUFHI
		lda	#FUJI_TIMEOUT
		sta	DTIMLO
		lda	#$00
		sta	DTIMHI
		lda	recvbuflen
		sta	DBYTLO
		sta	DAUX1
		lda	#$00
		sta	DBYTHI
		sta	DAUX2
		jsr	SIOV
		jmp	process_bytes

check_dvstat	lda	DVSTAT1			; DVSTAT1 and 2 hold the number of bytes in the input buffer
		ora	DVSTAT2
		beq	done			; nothing waiting, return

; R: read bytes — request exactly DVSTAT bytes via GET_CHARS
		ldx	#$10
		lda	#$07
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
		jsr	CIOV

process_bytes	ldy	#0
next_byte	lda	recv_buffer, y		; get character from buffer
		sta	temp_char		; put it here to pass to process_char
		tya
		pha				; push Y just in case

		jsr 	process_char		; process the character

		pla
		tay				; get Y back

		iny				; next character

		tya				; every 32 bytes, drain queued keystrokes so typing
		and	#$1F			; doesn't wait for the whole batch to finish rendering
		bne	skip_pump
		tya
		pha
		jsr	check_sendbuf
		pla
		tay
skip_pump
		cpy	recvbuflen
		bne	next_byte
done		rts

n_recv_disconnect
; Pop the jsr recv_from_device return address, then jump to disconnect handler.
		pla
		pla
		jmp	handle_disconnect_n
.endproc

.proc process_char
		bit	ctrl_seq_flg
		bvs	is_ctrl_seq		; if overflow set, it's a control sequence
		bpl	not_C1			; if escape flag not set, it's not a C1 character
		lda	#0			; if it is, we clear the escape flag for the next character.
		sta	ctrl_seq_flg
		lda	temp_char
		cmp	#$37			; ESC '7' = DECSC (save cursor)
		beq	do_decsc
		cmp	#$38			; ESC '8' = DECRC (restore cursor)
		beq	do_decrc
		and	#%11100000		; AND mask for C1 set
		cmp	#$40			; if it's $40 after ANDing,
		beq	is_C1			; it's part of the C1 set
		rts				; otherwise, it's some other character preceded by escape, which we do nothing with (don't even print it)
do_decsc	jmp	SCP_adr
do_decrc	jmp	RCP_adr

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
		lda	#0
		sta	inter_byte		; default: no intermediate byte
		ldx	ctrl_seq_index
		dex
		dex
		bmi	find_entry		; only final byte present (index was 1), skip intermediate check
		lda	ctrl_seq_buf,x
		cmp	#$30
		bcs	find_entry		; $30+ is a parameter byte, not intermediate
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
		lda	lf_mode			; if lf_mode set, LF implies CR+LF
		beq	lf_no_cr
		jsr	CR_adr
lf_no_cr	jsr	cursor_off
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
		cmp	#$5
		beq	bold			; blink mapped to bold (no blink on VBXE)
		cmp	#$6
		beq	normal_int		; normal intensity (alias)
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

normal_int	lda	text_color
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
		cmp	#1
		bne	not_mode1
		jmp	clear_to_cursor
not_mode1	cmp	#0
		beq	clear_from_cursor
		rts

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

clear_from_cursor				; n=0: clear from cursor to end of screen
		jsr	cursor_off
		lda	#23
		sec
		sbc	row			; rows remaining below cursor row
		sta	counter+1		; use as outer loop count
		lda	#79
		sec
		sbc	column			; chars remaining on current line
		tax
		beq	skip_first_line
		ldy	#0
cf_loop1	lda	#0
		sta	(cursor_address), y
		iny
		lda	text_color
		sta	(cursor_address), y
		iny
		dex
		bne	cf_loop1
skip_first_line
		lda	counter+1
		beq	cf_done
		; save current cursor state, move to next row col 0
		lda	row
		pha
		lda	column
		pha
		lda	cursor_address
		pha
		lda	cursor_address+1
		pha
		inc	row
		lda	#0
		sta	column
		jsr	recalc_cursor
cf_row_loop	ldx	#80
		ldy	#0
cf_loop2	lda	#0
		sta	(cursor_address), y
		iny
		lda	text_color
		sta	(cursor_address), y
		iny
		dex
		bne	cf_loop2
		inc	row
		lda	#0
		sta	column
		jsr	recalc_cursor
		dec	counter+1
		bne	cf_row_loop
		; restore cursor state
		pla
		sta	cursor_address+1
		pla
		sta	cursor_address
		pla
		sta	column
		pla
		sta	row
cf_done		jmp	cursor_on

clear_to_cursor					; n=1: clear from beginning of screen to cursor
		jsr	cursor_off
		; clear from vbxe_screen_top through cursor position (inclusive)
		; count = row * 80 + column + 1
		lda	#<vbxe_screen_top
		sta	src_ptr
		lda	#>vbxe_screen_top
		sta	src_ptr+1
		lda	row
		tax
		lda	#0
		sta	counter
		sta	counter+1
		cpx	#0
		beq	ct_add_col
ct_add80	lda	counter
		clc
		adc	#80
		sta	counter
		bcc	ct_no_c
		inc	counter+1
ct_no_c		dex
		bne	ct_add80
ct_add_col	lda	counter
		clc
		adc	column
		sta	counter
		bcc	ct_no_c2
		inc	counter+1
ct_no_c2	inc	counter			; +1 to include cursor position
		bne	ct_no_c3
		inc	counter+1
ct_no_c3	ldy	#0
ct_loop		lda	counter
		ora	counter+1
		beq	ct_done
		lda	#0
		sta	(src_ptr), y
		iny
		lda	text_color
		sta	(src_ptr), y
		iny
		bne	ct_noinc
		inc	src_ptr+1
ct_noinc	lda	counter
		bne	ct_nodec
		dec	counter+1
ct_nodec	dec	counter
		jmp	ct_loop
ct_done		jmp	cursor_on
.endproc

;###################################################################################################################
; EL - Erase in Line (ESC[nK)
; n=0: clear from cursor to end of line (default)
; currently only n=0 is supported

;###################################################################################################################
; SCP - Save Cursor Position (ESC[s)

.proc SCP_adr
		lda	row
		sta	saved_row
		lda	column
		sta	saved_column
		lda	cursor_address
		sta	saved_cur_lo
		lda	cursor_address + 1
		sta	saved_cur_hi
		rts
.endproc

;###################################################################################################################
; RCP - Restore Cursor Position (ESC[u)

.proc RCP_adr
		jsr	cursor_off
		lda	saved_row
		sta	row
		lda	saved_column
		sta	column
		lda	saved_cur_lo
		sta	cursor_address
		lda	saved_cur_hi
		sta	cursor_address + 1
		jmp	cursor_on
.endproc

;###################################################################################################################
; HVP - Horizontal and Vertical Position (ESC[r;cf) - same as CUP

HVP_adr	= CUP_adr

;###################################################################################################################
; CNL - Cursor Next Line (ESC[nE) - move cursor to beginning of line n lines down (default 1)

.proc CNL_adr
		jsr	cursor_off
		ldx	#0
		jsr	parse_param
		tay
		bne	has_param
		ldy	#1
has_param
move_loop	lda	row
		cmp	#23
		bcs	at_bottom
		inc	row
		dey
		bne	move_loop
at_bottom	lda	#0
		sta	column
		jsr	recalc_cursor
		jmp	cursor_on
.endproc

;###################################################################################################################
; CPL - Cursor Previous Line (ESC[nF) - move cursor to beginning of line n lines up (default 1)

.proc CPL_adr
		jsr	cursor_off
		ldx	#0
		jsr	parse_param
		tay
		bne	has_param
		ldy	#1
has_param
move_loop	lda	row
		beq	at_top
		dec	row
		dey
		bne	move_loop
at_top		lda	#0
		sta	column
		jsr	recalc_cursor
		jmp	cursor_on
.endproc

;###################################################################################################################
; CHA - Cursor Horizontal Absolute (ESC[nG) - move cursor to column n (default 1, 1-based)

.proc CHA_adr
		jsr	cursor_off
		ldx	#0
		jsr	parse_param
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
; SU - Scroll Up (ESC[nS) - scroll display up by n lines (default 1)

.proc SU_adr
		ldx	#0
		jsr	parse_param
		tay
		bne	has_param
		ldy	#1
has_param
		jsr	cursor_off
scroll_loop	jsr	scroll_1d
		dey
		bne	scroll_loop
		jmp	cursor_on
.endproc

;###################################################################################################################
; SD - Scroll Down (ESC[nT) - scroll down not easily done with current blitter setup, so just ignore for now

SD_adr						; stub - not yet implemented
		rts

;###################################################################################################################
; EL - Erase in Line (ESC[nK)

.proc EL_adr
		jsr	cursor_off
		ldx	#0
		jsr	parse_param		; get n (default 0)
		cmp	#1
		beq	clear_to_cursor
		cmp	#2
		beq	clear_whole_line
		; default: n=0, clear from cursor to end of line
		lda	#80
		sec
		sbc	column			; A = number of chars to clear
		tax
		beq	done			; nothing to clear if at end of line
		ldy	#0
clear_loop	lda	#0			; null character
		sta	(cursor_address), y
		iny
		lda	text_color
		sta	(cursor_address), y
		iny
		dex
		bne	clear_loop
done		jmp	cursor_on

clear_to_cursor					; n=1: clear from beginning of line to cursor
		lda	column
		clc
		adc	#1			; include char at cursor
		tax
		beq	done
		; calculate start of line address = cursor_address - column * 2
		lda	column
		asl	a			; column * 2 (2 bytes per char)
		sta	counter			; temp storage
		lda	cursor_address
		sec
		sbc	counter
		sta	src_ptr
		lda	cursor_address+1
		sbc	#0
		sta	src_ptr+1
		ldy	#0
ct_loop		lda	#0
		sta	(src_ptr), y
		iny
		lda	text_color
		sta	(src_ptr), y
		iny
		dex
		bne	ct_loop
		jmp	cursor_on

clear_whole_line				; n=2: clear entire line
		; calculate start of line address = cursor_address - column * 2
		lda	column
		asl	a			; column * 2 (2 bytes per char)
		sta	counter			; temp storage
		lda	cursor_address
		sec
		sbc	counter
		sta	src_ptr
		lda	cursor_address+1
		sbc	#0
		sta	src_ptr+1
		ldx	#80
		ldy	#0
cw_loop		lda	#0
		sta	(src_ptr), y
		iny
		lda	text_color
		sta	(src_ptr), y
		iny
		dex
		bne	cw_loop
		jmp	cursor_on
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
		
.proc print_str
; Display a $9B-terminated string on the VBXE terminal.
; A = low byte of string address, X = high byte. Trashes A, X, Y.
; Advances src_ptr each iteration so process_char (which corrupts Y) is safe.
		sta	src_ptr
		stx	src_ptr+1
next_char	ldy	#$00
		lda	(src_ptr),y
		cmp	#$9B
		beq	done
		sta	temp_char
		jsr	process_char		; may corrupt all registers including Y
		inc	src_ptr
		bne	next_char
		inc	src_ptr+1
		jmp	next_char
done		rts
.endproc

.proc print_hex_byte
; Display a byte in A as two uppercase hex digits on the VBXE terminal.
; Uses the classic 6502 jsr-into-shared-tail trick: jsr hex_nibble for the
; high nibble returns here (via process_char's rts), then falls through to
; hex_nibble again for the low nibble, tail-calling process_char back to caller.
		pha
		lsr
		lsr
		lsr
		lsr			; high nibble in low 4 bits
		jsr	hex_nibble
		pla
		and	#$0F		; low nibble; fall through to hex_nibble
hex_nibble
		cmp	#10
		bcc	@digit
		adc	#6		; carry set from cmp, so +7 total; biases 10→'A'
@digit		adc	#'0'
		sta	temp_char
		jmp	process_char
.endproc

.proc open_k_iocb2
; Close then open K: on IOCB 2 for single-character reads. Called before each read_line_vbxe.
		ldx	#$20
		lda	#$0C			; CMD_CLOSE (harmless if already closed)
		sta	ICCOM+$20
		jsr	CIOV
		lda	#$03			; CMD_OPEN
		sta	ICCOM+$20
		lda	#<kbd_dev
		sta	ICBA+$20
		lda	#>kbd_dev
		sta	ICBA+$21
		lda	#$04			; OREAD
		sta	ICAX1+$20
		lda	#$00
		sta	ICAX2+$20
		jmp	CIOV
.endproc

.proc read_line_vbxe
; Read a line from K: (IOCB 2), echoing each character to the VBXE terminal.
; On entry: src_ptr = destination buffer. Buffer is $9B-terminated on return.
; Handles BS ($08). Closes K: (IOCB 2) when Enter is pressed.
; Uses counter ($89) as buffer index so Y corruption from CIOV/process_char is harmless.
		lda	#$00
		sta	counter			; buffer index
get_char	ldx	#$20
		lda	#$07			; GET_CHARS (one character, immediate)
		sta	ICCOM+$20
		lda	#<temp_char		; read directly into temp_char ($008D)
		sta	ICBA+$20
		lda	#>temp_char
		sta	ICBA+$21
		lda	#$01
		sta	ICBL+$20
		lda	#$00
		sta	ICBL+$21
		jsr	CIOV			; Y is corrupted by CIOV (returns status in Y)

		lda	temp_char
		cmp	#$9B			; Enter?
		beq	done
		cmp	#$7E			; Delete Back (Atari backspace key)
		beq	do_bs

		ldy	counter
		sta	(src_ptr),y		; store character in buffer
		inc	counter
		beq	done			; buffer full (256 chars)
		jsr	process_char		; echo to VBXE (temp_char set, Y corruption OK)
		jmp	get_char

do_bs		lda	counter
		beq	get_char		; nothing to delete, ignore
		dec	counter
		jsr	BS_adr			; move cursor left
		lda	#' '
		sta	temp_char
		jsr	put_byte		; overwrite the character with a space
		jsr	BS_adr			; move cursor left again
		jmp	get_char

done		ldy	counter
		lda	#$9B
		sta	(src_ptr),y		; terminate buffer with EOL
		ldx	#$20
		lda	#$0C			; CMD_CLOSE K:
		sta	ICCOM+$20
		jsr	CIOV
		rts
.endproc

.proc read_line_vbxe_pw
; Like read_line_vbxe but echoes '*' for each character (password masking).
; On entry: src_ptr = destination buffer, K: open on IOCB 2.
		lda	#$00
		sta	counter
pw_get		ldx	#$20
		lda	#$07			; GET_CHARS
		sta	ICCOM+$20
		lda	#<temp_char
		sta	ICBA+$20
		lda	#>temp_char
		sta	ICBA+$21
		lda	#$01
		sta	ICBL+$20
		lda	#$00
		sta	ICBL+$21
		jsr	CIOV

		lda	temp_char
		cmp	#$9B			; Enter?
		beq	pw_done
		cmp	#$7E			; Delete Back (Atari backspace key)
		beq	pw_bs

		ldy	counter
		sta	(src_ptr),y		; store actual char in buffer
		inc	counter
		beq	pw_done			; buffer full
		lda	#'*'
		sta	temp_char
		jsr	put_byte		; echo '*'
		jmp	pw_get

pw_bs		lda	counter
		beq	pw_get
		dec	counter
		jsr	BS_adr
		lda	#' '
		sta	temp_char
		jsr	put_byte
		jsr	BS_adr
		jmp	pw_get

pw_done		ldy	counter
		lda	#$9B
		sta	(src_ptr),y
		ldx	#$20
		lda	#$0C			; CMD_CLOSE K:
		sta	ICCOM+$20
		jsr	CIOV
		rts
.endproc

; copy_str: copy $9B-terminated string from (src_ptr) to (dst_ptr), advance dst_ptr.
; Does NOT copy the $9B. Trashes A, Y.
.proc copy_str
		ldy	#$00
cs_loop		lda	(src_ptr),y
		cmp	#$9B
		beq	cs_done
		sta	(dst_ptr),y
		iny
		jmp	cs_loop
cs_done		tya
		clc
		adc	dst_ptr
		sta	dst_ptr
		bcc	cs_nc
		inc	dst_ptr+1
cs_nc		rts
.endproc

; put_byte_dst: write byte in A to (dst_ptr), advance dst_ptr. Trashes Y.
.proc put_byte_dst
		ldy	#$00
		sta	(dst_ptr),y
		inc	dst_ptr
		bne	pb_nc
		inc	dst_ptr+1
pb_nc		rts
.endproc

MAX_SEND_BATCH	= 64				; max bytes per SIO/CIO send call (bounds half-duplex stall)

.proc check_sendbuf				; drains queued keystrokes in one coalesced send.
; kbd_irq only mutates sendbufend; we only mutate sendbufstart — race-safe without sei.
; Drain up to MAX_SEND_BATCH bytes from send_buffer into send_stage_buf, then issue one
; SIO 'W' (N:) or one CIO PUT_CHARS (R:) for the whole run.

		lda	sendbufend
		sec
		sbc	sendbufstart		; A = pending count (mod 256, ring math)
		bne	have_data
		rts
have_data	cmp	#MAX_SEND_BATCH+1
		bcc	keep_count
		lda	#MAX_SEND_BATCH
keep_count	sta	send_count

		ldx	#$00
		ldy	sendbufstart
copy_loop	iny				; advance src before reading (mirrors kbd_irq's advance-before-write)
		lda	send_buffer,y
		sta	send_stage_buf,x
		inx
		cpx	send_count
		bne	copy_loop
		sty	sendbufstart		; commit: advance start by send_count (Y wrapped naturally)

		lda	device_type
		bne	n_send

; R: send — CIO PUT_CHARS on IOCB 1, multi-byte
		ldx	#$10
		lda	#$0B
		sta	ICCOM+$10
		lda	#<send_stage_buf
		sta	ICBA+$10
		lda	#>send_stage_buf
		sta	ICBA+$11
		lda	send_count
		sta	ICBL+$10
		lda	#$00
		sta	ICBL+$11
		lda	#$0D
		sta	ICAX1+$10
		jmp	CIOV

; N: send — SIO Write coalesced batch to FujiNet
n_send		lda	#FUJI_ID
		sta	DDEVIC
		lda	n_unit
		sta	DUNIT
		lda	#'W'			; Write command
		sta	DCOMND
		lda	#$80			; write direction
		sta	DSTATS
		lda	#<send_stage_buf
		sta	DBUFLO
		lda	#>send_stage_buf
		sta	DBUFHI
		lda	#FUJI_TIMEOUT
		sta	DTIMLO
		lda	#$00
		sta	DTIMHI
		lda	send_count
		sta	DBYTLO
		sta	DAUX1
		lda	#$00
		sta	DBYTHI
		sta	DAUX2
		jmp	SIOV
.endproc
		
.proc open_r_device
; open and fully configure the R: serial device on IOCB 1.

; open
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

; 9600 baud, 8 data bits, no status line checking
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

; no translation, ignore parity, no LF append
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

; turn on DTR and RTS
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
		jmp	CIOV
.endproc

font_path	.byte	"D:IBMPC.FNT", $9B
pallette_path	.byte	"D:ANSI.PAL", $9B
;test_file	.byte	"D:TEST.ANS", $9B
r_path		.byte	"R1:", $9B
n_url_buf	.res	256, $00		; FujiNet URL buffer — must be 256 bytes (FujiNet SIO OPEN expects exactly 256)

.proc open_n_device
; Open a FujiNet connection via direct SIO (no N: CIO handler required).
; URL is in n_url_buf.  Unit number is parsed from the URL (N1:, N2:, etc.;
; bare N: defaults to unit 1).  Returns Y=$01 (positive) on success,
; Y=SIO error (negative) on failure.  Also saves unit in n_unit for recv/send.

; Parse unit number: n_url_buf[1] is ':' for bare N:, or digit for N1:-N8:
		ldy	#$01
		lda	n_url_buf,y
		cmp	#':'
		bne	has_digit
		lda	#$01			; bare N: → unit 1
		bne	store_unit
has_digit	sec
		sbc	#'0'
store_unit	sta	n_unit

; SIO OPEN: send URL to FujiNet device $71
		lda	#FUJI_ID
		sta	DDEVIC
		lda	n_unit
		sta	DUNIT
		lda	#'O'			; Open command
		sta	DCOMND
		lda	#$80			; write direction (sending URL spec)
		sta	DSTATS
		lda	#<n_url_buf
		sta	DBUFLO
		lda	#>n_url_buf
		sta	DBUFHI
		lda	#FUJI_TIMEOUT
		sta	DTIMLO
		lda	#$00
		sta	DTIMHI
		lda	#$00			; 256 bytes (FujiNet OPEN always expects 256-byte URL buffer)
		sta	DBYTLO
		lda	#$01
		sta	DBYTHI
		lda	#$0C			; OUPDATE (read+write)
		sta	DAUX1
		lda	#$00			; no translation
		sta	DAUX2
		jsr	SIOV

; SIOV stores result in DSTATS: $01=success, negative=error
		lda	DSTATS
		cmp	#$01
		beq	ok
		cmp	#$90			; DERROR — call STATUS to get extended error and clean up
		bne	not_derror
		jsr	n_status_sio
		lda	#$90			; return DERROR ($90, bit 7 set → bmi taken)
not_derror	tay
		rts
ok		ldy	#$01			; positive Y = success
		rts
.endproc

.proc n_status_sio
; Call FujiNet STATUS SIO command. Fills DVSTAT0–DVSTAT3. Requires n_unit set.
		lda	#FUJI_ID
		sta	DDEVIC
		lda	n_unit
		sta	DUNIT
		lda	#'S'
		sta	DCOMND
		lda	#$40			; DREAD
		sta	DSTATS
		lda	#<DVSTAT0
		sta	DBUFLO
		lda	#>DVSTAT0
		sta	DBUFHI
		lda	#FUJI_TIMEOUT
		sta	DTIMLO
		lda	#$00
		sta	DTIMHI
		lda	#$04
		sta	DBYTLO
		lda	#$00
		sta	DBYTHI
		sta	DAUX1
		sta	DAUX2
		jmp	SIOV
.endproc

.proc nlogin_n_device
; Pre-configure SSH credentials via SIO commands $FD (login) and $FE (password).
; Called before open_n_device. Errors ignored — non-SSH connections will reject gracefully.
; Requires n_unit set.
		lda	#FUJI_ID
		sta	DDEVIC
		lda	n_unit
		sta	DUNIT
		lda	#$FD			; login command
		sta	DCOMND
		lda	#$80			; DWRITE
		sta	DSTATS
		lda	#<login_buf
		sta	DBUFLO
		lda	#>login_buf
		sta	DBUFHI
		lda	#FUJI_TIMEOUT
		sta	DTIMLO
		lda	#$00			; 256-byte buffer (hi byte = 1)
		sta	DTIMHI
		sta	DBYTLO
		lda	#$01
		sta	DBYTHI
		lda	#$00
		sta	DAUX1
		sta	DAUX2
		jsr	SIOV			; send username
		lda	#$FE			; password command (reuse most params)
		sta	DCOMND
		lda	#<password_buf
		sta	DBUFLO
		lda	#>password_buf
		sta	DBUFHI
		jsr	SIOV			; send password
		rts
.endproc

.proc nclose_n_device
; Send FujiNet CLOSE SIO command. Requires n_unit set.
		lda	#FUJI_ID
		sta	DDEVIC
		lda	n_unit
		sta	DUNIT
		lda	#'C'
		sta	DCOMND
		lda	#$00
		sta	DSTATS
		sta	DBUFLO
		sta	DBUFHI
		lda	#FUJI_TIMEOUT
		sta	DTIMLO
		lda	#$00
		sta	DTIMHI
		sta	DBYTLO
		sta	DBYTHI
		sta	DAUX1
		sta	DAUX2
		jmp	SIOV
.endproc

.proc n_proceed_irq
; VPRCED interrupt handler — set n_trip=1 when FujiNet PROCEED line goes high.
; PLA+RTI matches the Atari OS convention: OS pushes A before jumping through VPRCED.
		lda	#$01
		sta	n_trip
		pla
		rti
.endproc

.proc restore_os_hooks
; Restore IRQ/vector state that may have been modified while terminal was active.
		lda	old_dosini
		sta	DOSINI
		lda	old_dosini+1
		sta	DOSINI+1

		lda	PACTL
		and	#$FE
		sta	PACTL			; disable PROCEED IRQ before touching VPRCED

		lda	n_old_vprced
		sta	VPRCED
		lda	n_old_vprced+1
		sta	VPRCED+1

		lda	n_old_pactl
		and	#$FE
		sta	PACTL			; restore PACTL state but keep PROCEED IRQ disabled

		sei
		lda	old_vkeybd
		sta	VKEYBD
		lda	old_vkeybd+1
		sta	VKEYBD+1
		cli

		ldx	#$10
		lda	#$0C			; close IOCB 1 (R:/N:) if open
		sta	ICCOM+$10
		jsr	CIOV

		lda	saved_soundr		; restore OS SIO bus sound setting
		sta	SOUNDR
		rts
.endproc

.proc reset_cleanup
; RESET warmstart hook: restore ANTIC/VBXE-visible state before DOS warm init.
		lda	old_dosini
		sta	DOSINI
		lda	old_dosini+1
		sta	DOSINI+1

		lda	#$00
		sta	video_control
		sta	memac_bank_sel
		sta	memac_control

		lda	saved_sdmctl
		sta	SDMCTL
		sta	$D400

		lda	n_old_vprced
		sta	VPRCED
		lda	n_old_vprced+1
		sta	VPRCED+1

		lda	n_old_pactl
		and	#$FE
		sta	PACTL

		sei
		lda	old_vkeybd
		sta	VKEYBD
		lda	old_vkeybd+1
		sta	VKEYBD+1
		cli

		lda	saved_soundr
		sta	SOUNDR

		jmp	(old_dosini)
.endproc

.proc restore_graphics
		lda	#$00
		sta	SDMCTL				; blank ANTIC immediately during teardown
		sta	$D400				; keep shadow/hardware DMACTL in sync

		jsr	_vbxe_shutdown

		; _vbxe_shutdown already restored SDMCTL from startup state.
		; Mirror that restored shadow value to hardware DMACTL immediately.
		lda	SDMCTL
		sta	$D400

		lda	#$00
		sta	$D01B				; PRIOR (hardware): normal GTIA priority mode
		sta	$026F				; GPRIOR shadow

		lda	#$C0
		sta	$D40E				; NMIEN: enable VBI + DLI (OS default-compatible)

		lda	#$00

		sta	$D016				; COLPF0
		sta	$D017				; COLPF1
		sta	$D018				; COLPF2
		sta	$D019				; COLPF3
		sta	$D01A				; COLBK
		sta	$02C4				; COLOR0 shadow
		sta	$02C5				; COLOR1 shadow
		sta	$02C6				; COLOR2 shadow
		sta	$02C7				; COLOR3 shadow
		sta	$02C8				; COLOR4 shadow

		; Re-open IOCB 0 to E: in text mode so DOS resumes on a clean console.
		ldx	#$00
		lda	#$0C
		sta	ICCOM
		jsr	CIOV

		; Force a fresh OS text display list and palette via screen handler.
		lda	#$03
		sta	ICCOM
		lda	#<s_device
		sta	ICBA
		lda	#>s_device
		sta	ICBA+1
		lda	#$00				; graphics mode 0
		sta	ICAX1
		sta	ICAX2
		jsr	CIOV

		lda	#$0C
		sta	ICCOM
		jsr	CIOV

		lda	#$03
		sta	ICCOM
		lda	#<e_device
		sta	ICBA
		lda	#>e_device
		sta	ICBA+1
		lda	#$00
		sta	ICAX1
		sta	ICAX2
		jsr	CIOV
		rts
.endproc

exit_to_dos
		jsr	restore_os_hooks
		jsr	restore_graphics
		jmp	(DOSVEC)		; return directly to DOS command processor

send_stage_buf	.res	MAX_SEND_BATCH, $00		; coalesced outbound staging buffer
send_count	.res	1, $00				; bytes staged for the current send
banner_msg	.byte	$1B,"[31m","V",$1B,"[32m","B",$1B,"[34m","X",$1B,"[33m","E",$1B,"[0m","TERM v0.10 (2026-05-02)", $9B
select_prompt	.byte	"R=Serial  N=FujiNet? ", $9B
no_n_msg	.byte	"FujiNet open failed: $", $9B
press_return_msg	.byte	" - Press Return.", $9B
kbd_dev		.byte	"K:", $9B
s_device	.byte	"S:", $9B
e_device	.byte	"E:", $9B
select_buf	.res	4, $00
connecting_msg	.byte	"Connecting...", $9B
n_open_ok_msg	.byte	"Connected.", $9B
disconnected_msg	.byte	"Disconnected.", $9B
proto_prompt	.byte	"PROTOCOL [T]CP [S]SH: ", $9B
server_prompt	.byte	"SERVER: ", $9B
port_prompt	.byte	"PORT (Enter for default): ", $9B
user_prompt	.byte	"USER: ", $9B
pw_prompt	.byte	"PASSWORD: ", $9B
n1_str		.byte	"N1:", $9B
tcp_url_str	.byte	"TCP://", $9B
ssh_url_str	.byte	"SSH://", $9B
tcp_port_str	.byte	"23", $9B
ssh_port_str	.byte	"22", $9B
server_buf	.res	64, $00
port_buf	.res	8, $00
proto_byte	.res	1, $00
n_old_vprced	.res	2, $00			; saved VPRCED vector
n_old_pactl	.byte	$00			; saved PACTL state
old_vkeybd	.res	2, $00			; saved VKEYBD vector (OS keyboard IRQ)
old_dosini	.res	2, $00			; saved DOSINI warm-init vector for RESET chaining
saved_soundr	.res	1, $00			; saved SOUNDR (SIO bus sound) value
login_buf	.res	256, $00		; username buffer (256 bytes — FujiNet $FD expects 256)
password_buf	.res	256, $00		; password buffer (256 bytes — FujiNet $FE expects 256)

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
		.byte	'f', 0
		.word	HVP_adr			; horizontal/vertical position (alias for CUP)
		.byte	'J', 0
		.word	ED_adr			; erase in display
		.byte	'K', 0
		.word	EL_adr			; erase in line
		.byte	's', 0
		.word	SCP_adr			; save cursor position
		.byte	'u', 0
		.word	RCP_adr			; restore cursor position
		.byte	'E', 0
		.word	CNL_adr			; cursor next line
		.byte	'F', 0
		.word	CPL_adr			; cursor previous line
		.byte	'G', 0
		.word	CHA_adr			; cursor horizontal absolute
		.byte	'S', 0
		.word	SU_adr			; scroll up
		.byte	'T', 0
		.word	SD_adr			; scroll down (stub)
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
version		.byte	"v0.07.2026.04.29"

end						;should be plenty of space after this that is free (like for MEMAC window)
