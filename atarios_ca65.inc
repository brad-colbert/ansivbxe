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
DOSVEC		=	$A			; vector for DOS
VKEYBD		=	$208			; vector for KB interupt
; OS variables and shadow registers
SDMCTL		=	$22F			; DMA Control
RTCLOK		=	$12			; jiffy counter
CH1		=	$2F2			; used for KB IRQ
KEYDEL		=	$2F1			; key delay counter for debouncing
ATRACT		=	$4D			; attract mode timer/flag
SRTIMR		=	$22B			; key repeat delay counter. decremented once every jiffy.