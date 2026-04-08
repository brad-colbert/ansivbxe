list of files:
ANSIVBXE.asm
        Source code for the terminal. It contains one init segment, and one run
        segment. Both are ORG'ed to $2800. The code is not relocatable, but it
        can be built for a different address by changing the ORG statements.
        The source is written for MADS assembler.
VBXETERM.atr
        An ATR which has DOS and the terminal demo on it. Set it as D1. The
        TEST.ANS file can be modified to display different text. As of right
        now, the program interprets ASCII control codes, but no other control
        functions or sequences as defined by the ANSI or the ECMA-48
        specification.
atarihardware.equ
        Some Atari hardware equates.
atarios.equ
        Some OS equates.
VBXE.equ
        Finally, the VBXE equates.
first.fnt
        This is the first half of the IBMPC.FNT file. I used an A8 font editor
        to make two 128 character fonts which were then concatenated to form
        the full 256 character font. The order of the characters in the font
        are the same as ascii.
second.fnt
        Second half of the IBMPC.FNT file.
IBMPC.FNT
	Font for the terminal.
ANSI.PAL 
        The pallette file for the ANSI colors. Each color is 3 bytes in RGB
        order. First are the 8 low intensity colors, then the 8 high intensity
        colors. Some ANSI BBS'es took advantage of the fact that IBM CGA
        graphics replaced one of the yellows with a brown. This is the primary
        reason that the pallette is editable as a file rather than hardcoded.
cga8.png
        The picture of the IBM CGA font which I used to make the font for this
        program. I did not use the bottom version, which I believe is supposed
        to be the bold version. I chose the CGA font because they are 8x8
        characters, the same as VBXE, and many ANSI BBS'es take advantage of
        IBM extended graphics characters.
ReadMe.txt
        This file.
ANSIVBXE.XEX
        ANSIVBXE.asm compiled by MADS ORG'ed at $2800
changelog.txt
	list of version numbers, added features, known bugs, bugfixes, etc.
	
licensing:
	to be determined, for now, "don't be a dick" should suffice.