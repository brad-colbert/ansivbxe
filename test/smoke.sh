#!/bin/bash

printf '\e[2J\e[H=== ANSIVBXE smoke test ===\n\n'
printf '1. SGR cancel:    \e[1;7mBOLD-INV\e[22m NO-BOLD\e[27m NO-INV\e[0m\n'
printf '2. Italic alias:  \e[3mITALIC\e[23m normal\n'
printf '3. Decoration:    \e[51mFRAMED\e[0m \e[52mENCIRCLED\e[0m (both plain)\n'
printf '4. Tabs:          A\tB\tC\tD\n'
printf '5. Color FG:      '
for fg in 30 31 32 33 34 35 36 37; do printf '\e[%dm##\e[0m' $fg; done
printf '\n6. Color BG:      '
for bg in 40 41 42 43 44 45 46 47; do printf '\e[%dm  \e[0m' $bg; done
printf '\n=== done ===\n'