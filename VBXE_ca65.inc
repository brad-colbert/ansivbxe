;###################################################################################################################
;
;
;	   ##	 #######   ##	 #####	  ###		 ######	  ####	 #    #	   ##	 ####### ######	  ####
;	  #  #	 #  #  #  #  #	  #   #	   #		  #   #	 #    #	 #    #	  #  #	 #  #  #  #   #	 #    #
;	 #    #	    #	 #    #   #   #	   #		  # #	 #    #	 #    #	 #    #	    #	  # #	 #
;	 #    #	    #	 #    #	  ####	   #		  ###	 #    #	 #    #	 #    #	    #	  ###	  ####
;	 ######	    #	 ######   # #	   #		  # #	 #  # #	 #    #	 ######	    #	  # #	      #
;	 #    #	    #	 #    #	  #  #	   #		  #   #	  ####	 #    #	 #    #	    #	  #   #	 #    #
;	 #    #	   ###	 #    #	 ###  #	  ###		 ######	      ##  ####	 #    #	   ###	 ######	  ####
;
;	VBXE Equates
;###################################################################################################################
; VBXE equates
core_version	=	$D640			; tells us whether FX or GTIA-emu core (READ-only)

; XDL address registers (3 consecutive bytes for 24-bit address)
xdl_adr		=	$D641			; XDL address low byte
xdl_adr_mid	=	$D642			; XDL address middle byte  
xdl_adr_high	=	$D643			; XDL address high byte

; memory window B control register
; bit 0 - 4 - bank number (banks are all 16K)
; bit 6 - MBAE - ANTIC access enable
; bit 7 - MBCE - CPU access enable

memac_b_control	=	$D65D

; memory window A control register
; bit 0 and 1 - window size - 00 for 4K, 01 for 8K, 10 for 16K, 11 for 32K
; bit 2 - MAE - when set, antic can see VBXE RAM
; bit 3 - MCE - when set, CPU can see VBXE RAM

memac_control	=	$D65E

memac_bank_sel	=	$D65F			; controls bank number of movable window (MEMAC A). bit 7 is an enable bit
psel		=	$D644			; selects the pallette number to load into
csel		=	$D645			; selects current color number for write
cr		=	$D646			; red component value
cg		=	$D647			; green component value
cb		=	$D648			; blue component value

; video control register (WRITE to $D640)
; bit 0 - xdl_enabled - set to enable XDL
; bit 1 - xcolor - set to enable 16 luminances and separate ANTIC hi-res foreground and background hues
; bit 2 - no_trans - clear means color 0 is transparent
; bit 3	- trans15 - allows additional transparent colors. only works when no_trans is 0

video_control	=	$D640

colmask		=	$D649			; AND mask for collisions with GTIA/ANTIC and VBXE stuff
colclr		=	$D64A			; clears coldetect (any value written here)
coldetect	=	$D64A			; collisions detected.
blt_adr		=	$D650			; blitter list address (3 bytes, consecutive)
blt_collision	=	$D650			; collision codes that blitter has set
blt_start	=	$D653			; bit 0 set to start blitter
blt_busy	=	$D653			; bit 1 for busy, bit 0 for BCB load. register will read 0 when blitter is stopped.
irq_control	=	$D654			; set bit 0 to enable blitter IRQ
irq_status	=	$D654			; bit 0 set means blitter threw an IRQ
P0		=	$D655			; priority select registers when attribute map is enabled.
P1		=	$D656
P2		=	$D657
P3		=	$D658
.struct	BCB
src_adr		.byte	3
src_step_y	.word
src_step_x	.byte
dest_adr	.byte	3
dest_step_y	.word
dest_step_x	.byte
blt_width	.word
blt_height	.byte
blt_and_mask	.byte
blt_xor_mask	.byte
blt_coll_mask	.byte
blt_zoom	.byte
pattern_feature	.byte
blt_control	.byte
.endstruct