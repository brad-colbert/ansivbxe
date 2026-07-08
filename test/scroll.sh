#!/bin/bash
#
# Visual test for the scrolling-region sequences (IL/DL/SU/SD).
# Run this on the remote host once the Atari has connected (N: ssh, or R:).
#
# Each step pauses so you can eyeball the result; the expected outcome is printed
# on the bottom line. Rows are labelled so a misplaced row is obvious at a glance.
#
# The automated companion is `make test`, which unit-tests the row-move arithmetic
# under a 6502 simulator. This script exercises the parser and the real VBXE screen.

STEP=${STEP:-3}   # seconds to look at each result

pause () { printf '\e[24;1H\e[K>> %s' "$1"; sleep "$STEP"; }

board () {        # rows 1..23 labelled, row 24 left free for the message line
    printf '\e[2J\e[H'
    for i in $(seq 1 23); do printf 'row %02d ---------------------------------\n' "$i"; done
}

# 1. IL: open 3 blank lines at row 5.
board
printf '\e[5;1H\e[3L'
pause 'IL 3 @row5: rows 5-7 blank, old row 5 now at row 8'

# 2. IL must NOT move the cursor column (xterm / Linux-console behaviour).
#    The X must land at column 40, not column 1.
board
printf '\e[10;40H\e[2L'
printf 'X'
pause 'IL 2 @row10 col40: X sits at col 40, cursor column unchanged'

# 3. DL: delete 2 lines at row 10.
board
printf '\e[10;1H\e[2M'
pause 'DL 2 @row10: old row 12 now at row 10; rows 22-23 blank'

# 4. IL / DL on the bottom row must blank just that row.
board
printf '\e[23;1H\e[1L'
pause 'IL 1 @row23: only row 23 blank, rows 1-22 untouched'
board
printf '\e[23;1H\e[5M'
pause 'DL 5 @row23: only row 23 blank, rows 1-22 untouched'

# 5. Clamping: n larger than the number of rows below the cursor.
board
printf '\e[20;1H\e[99L'
pause 'IL 99 @row20: rows 20-24 blank, rows 1-19 untouched, no hang'

# 6. SU / SD  (terminfo indn / rin). SD was a bare rts before this change.
board
printf '\e[2S'
pause 'SU 2: content up 2, bottom 2 rows blank'
board
printf '\e[2T'
pause 'SD 2: content down 2, top 2 rows blank'
board
printf '\e[99T'
pause 'SD 99: whole screen blank (clamped, must not hang)'

# 7. Blanked cells must be OPAQUE. VBXE colour-byte bit 7 is the overlay opacity
#    bit, so a blank written with colour $00 is invisible. The rows IL opens must
#    be painted in the current background, not show through to the ANTIC layer.
board
printf '\e[44;37m'                       # white on blue
printf '\e[8;1H\e[4L'
printf '\e[0m'
pause 'IL with blue bg: rows 8-11 solid blue, NOT transparent'

# 8. ED regression: ESC[J must erase through column 80, including the cursor cell.
#    (It used to compute 79-column and leave the last cell of the row alone.)
printf '\e[2J\e[H'
for r in 1 2 3 4 5; do
    printf '\e[%d;1H' "$r"
    for c in $(seq 1 80); do printf 'Z'; done   # exactly fills the row
done
printf '\e[3;80H\e[J'
pause 'ED @row3 col80: that last Z is erased; row 3 cols 1-79 keep their Z'

printf '\e[2J\e[H=== scroll test done ===\n'
