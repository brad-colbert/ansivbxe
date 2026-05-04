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
;	OS Equates
;###################################################################################################################
; IOCB equates
ICCOM		=	$342			; command
ICSTA		=	$343			; status
ICBA		=	$344			; 2 bytes, buffer address for data or filename
ICBL		=	$348			; 2 bytes, buffer length
ICAX1		=	$34A			; Auxiliary byte 1
ICAX2		=	$34B			; Auxiliary byte 2

DVSTAT0		=	$2EA			; holds that status bytes after a status command
DVSTAT1		=	$2EB
DVSTAT2		=	$2EC
DVSTAT3		=	$2ED
; OS vectors and addresses
CIOV		=	$E456			; address for CIO
SIOV		=	$E459			; address for SIO
DOSVEC		=	$A			; vector for DOS
DOSINI		=	$0C			; DOS warm-init vector (called during RESET warmstart)
WARMSV		=	$E474			; OS warmstart entry (RESET path)

; SIO parameter block
DDEVIC		=	$300			; device ID
DUNIT		=	$301			; unit number
DCOMND		=	$302			; command byte
DSTATS		=	$303			; data direction / status
DBUFLO		=	$304			; buffer address low
DBUFHI		=	$305			; buffer address high
DTIMLO		=	$306			; timeout (low byte)
DTIMHI		=	$307			; timeout (high byte)
DBYTLO		=	$308			; byte count low
DBYTHI		=	$309			; byte count high
DAUX1		=	$30A			; auxiliary byte 1
DAUX2		=	$30B			; auxiliary byte 2

; FujiNet SIO constants
FUJI_ID		=	$71			; FujiNet SIO device ID
FUJI_TIMEOUT	=	$1F			; ~30 second SIO timeout
SHFLOK		=	$2BE			; keyboard shift/caps lock (bit 6 = caps lock; 0 = off, allows Shift for lowercase)
VKEYBD		=	$208			; vector for KB interupt
VPRCED		=	$0202			; vector for SIO proceed interrupt (FujiNet data-ready signal)
PACTL		=	$D302			; PIA port A control register (bit 0 = PROCEED IRQ enable)
; OS variables and shadow registers
SDMCTL		=	$22F			; DMA Control
RTCLOK		=	$12			; jiffy counter
CH1		=	$2F2			; used for KB IRQ
KEYDEL		=	$2F1			; key delay counter for debouncing
ATRACT		=	$4D			; attract mode timer/flag
SRTIMR		=	$22B			; key repeat delay counter. decremented once every jiffy.