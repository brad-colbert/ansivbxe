# VBXETERM

An Atari 8-bit terminal emulator that supports ANSI/ECMA-48 control sequences and a 256-character IBM PC font, using the VBXE (Video Board XE) graphics expansion. Renders ANSI art and connects to BBS systems and SSH hosts over serial (R:) or FujiNet (N:). Also speaks ATASCII, for Atari boards.

**Converted to CA65 and updated by:** Brad Colbert  
**Original MADS by:** Joseph Zatarski  
**Version:** v0.24  

<img width="608" height="172" alt="image" src="https://github.com/user-attachments/assets/84c7b30e-c9b0-4522-83ff-6d2b81787d69" />

---

## Features

- 80×24 text display via VBXE overlay text mode
- 256-character IBM CGA-style font
- **ANSI and ATASCII terminal modes**, switchable at any time from the OPTION menu
- Editable ANSI color palette (16 colors: 8 standard + 8 high-intensity)
- LF-as-CRLF mode enabled by default (compatible with most remote hosts)
- OS SIO bus sound silenced during FujiNet N: sessions (no per-byte whine), restored on disconnect and exit
- Step-by-step connection wizard — no manual URL construction required
- R: serial device or FujiNet N: device (Telnet or SSH)
- FujiNet SSH username and password entry (with asterisk masking)
- Automatic disconnect detection — returns to device selection on remote close or drop
- RESET button restarts the application cleanly (drops any active connection, reinitializes display)
- Keyboard input with auto-repeat via custom IRQ handler
- Concurrent/non-blocking receive

### Connection Wizard (N: FujiNet)

Selecting `N` at the device prompt steps through:

1. **PROTOCOL** — press `T` for Telnet or `S` for SSH
2. **SERVER** — hostname or IP address
3. **PORT** — port number; press Return for the default (23 for Telnet, 22 for SSH)
4. **USER** — username (SSH only)
5. **PASSWORD** — password (SSH only, displayed as `*`)

The FujiNet URL is constructed automatically. Backspace works at every field.

### ATASCII Mode

Press **OPTION** and set `Mode:` to `ATASCII` to talk to an Atari BBS. ATASCII is a
terminal mode rather than a font choice: it brings its own control set, its own
character encoding and its own keyboard encoding, and the ANSI parser is bypassed
entirely while it is active — it has to be, because `$1B` in ATASCII quotes the
following byte instead of introducing an escape sequence, and `$9B` is EOL rather
than CSI.

The character set is built at runtime from the Atari OS charset ROM at `$E000`, so
nothing extra ships on the disk. Glyphs `$00-$7F` are the ROM charset and `$80-$FF`
are the same bitmaps inverted, which is how bit 7 gives you inverse video for free.

Selecting ATASCII also sets the auto-wrap column to 40, since ATASCII art is drawn
for a 40-column screen; the `Width:` row switches it back to 80. The display stays
physically 80 columns wide either way — only the wrap point moves, so 40-column art
occupies the left half of the screen.

Selecting any of the CP437 fonts switches back to ANSI, so the two can never
disagree.

| Code | Name | Description |
|------|------|-------------|
| `$1B` | ESC | Print the next byte literally, whatever it is |
| `$1C`–`$1F` | Cursor | Up / down / left / right — **wraps** at the screen edges (ANSI's CUU/CUD clamp instead) |
| `$7D` | Clear | Clear screen and home the cursor |
| `$7E` | Backspace | Move left and erase |
| `$7F` | Tab | Advance to the next 8-column stop |
| `$9B` | EOL | End of line (CR + LF) |
| `$9C` / `$9D` | Delete / Insert line | Within the current scrolling region |
| `$9E` / `$9F` | Clear / set tab stop | No-ops — tab stops are fixed at 8 columns, as with ANSI HTS/VTS |
| `$FD` | Buzzer | Bell |
| `$FE` / `$FF` | Delete / Insert character | Within the current row, bounded by the wrap column |

Everything else prints, including the whole `$80-$FF` inverse range.

In ATASCII mode the keyboard sends ATASCII too: RETURN sends `$9B`, BACKSPACE
`$7E`, TAB `$7F`, and the arrow keys send single `$1C`–`$1F` codes rather than
`ESC [ x`. The Atari **inverse-video key** becomes a sticky bit-7 latch, as on
hardware — though it is deliberately not applied to `$1B`–`$1F`, so inverse+ESC
cannot silently turn into EOL, and RETURN still sends a bare EOL with inverse on.

### Keyboard

Standard Atari keyboard, plus these terminal-specific bindings:

| Key combo | Sends | Purpose |
|-----------|-------|---------|
| Arrow keys (CTRL+`-` / `=` / `+` / `*`) | `ESC[A` / `ESC[B` / `ESC[D` / `ESC[C` | VT100/ANSI cursor up / down / left / right — works in bash readline, vim, less, mc, etc. |
| CTRL+`<` | `{` | Curly-brace entry. The Atari has no `{`/`}` keys, so these are mapped onto the otherwise-unused CTRL combos on the dedicated `<` and `>` keys (top row). |
| CTRL+`>` | `}` | (see above) |
| CTRL+SHIFT+`+` / `*` / `-` | FS / RS / US (`$1C` / `$1E` / `$1F`) | The C0 control characters that used to live on plain CTRL+`+` / `*` / `-`, relocated here when those keys became cursor arrows. |

### Supported ANSI/ECMA-48 Sequences

#### C0 Controls

| Code | Name | Description |
|------|------|-------------|
| `$00` | NUL | No operation |
| `$07` | BEL | Bell (ignored) |
| `$08` | BS | Backspace — move cursor left |
| `$09` | HT | Horizontal Tab — advance to next 8-column stop |
| `$0A` | LF | Line Feed — also emits CR when LF-as-CRLF mode is on |
| `$0B` | VT | Vertical Tab — treated as LF |
| `$0C` | FF | Form Feed — clears screen, home cursor |
| `$0D` | CR | Carriage Return |
| `$1B` | ESC | Escape — begins escape sequence |

#### ESC Sequences (two-character)

| Sequence | Name | Description |
|----------|------|-------------|
| `ESC 7` | DECSC | Save cursor position |
| `ESC 8` | DECRC | Restore cursor position |
| `ESC [`  | CSI  | Control Sequence Introducer |

#### C1 Controls (via ESC + byte in `$40`–`$5F`)

| Sequence | Name | Description |
|----------|------|-------------|
| `ESC D` (IND) | Index | Same as LF |
| `ESC E` (NEL) | Next Line | CR + LF |
| `ESC [` (CSI) | CSI | Begin control sequence |

#### CSI Sequences

| Sequence | Code | Description |
|----------|------|-------------|
| `ESC[nA` | CUU | Cursor Up _n_ lines (default 1) |
| `ESC[nB` | CUD | Cursor Down _n_ lines (default 1) |
| `ESC[nC` | CUF | Cursor Forward (right) _n_ columns (default 1) |
| `ESC[nD` | CUB | Cursor Back (left) _n_ columns (default 1) |
| `ESC[nE` | CNL | Cursor Next Line — down _n_, column 1 (default 1) |
| `ESC[nF` | CPL | Cursor Previous Line — up _n_, column 1 (default 1) |
| `ESC[nG` | CHA | Cursor Horizontal Absolute — column _n_ (default 1) |
| `ESC[r;cH` | CUP | Cursor Position — row _r_, column _c_ (default 1;1) |
| `ESC[r;cf` | HVP | Horizontal/Vertical Position — alias for CUP |
| `ESC[nJ` | ED | Erase in Display: 0=cursor→end, 1=start→cursor, 2=whole screen |
| `ESC[nK` | EL | Erase in Line: 0=cursor→EOL, 1=start→cursor, 2=whole line |
| `ESC[nL` | IL | Insert _n_ blank lines at the cursor row, pushing the rest down (default 1). Cursor column unchanged |
| `ESC[nM` | DL | Delete _n_ lines at the cursor row, pulling the rest up (default 1). Cursor column unchanged |
| `ESC[nS` | SU | Scroll Up _n_ lines (default 1) |
| `ESC[nT` | SD | Scroll Down _n_ lines (default 1) |
| `ESC[s` | SCP | Save Cursor Position |
| `ESC[u` | RCP | Restore Cursor Position |
| `ESC[…m` | SGR | Set Graphics Rendition (see below) |

`IL` and `DL` are what make **vim scroll correctly under `TERM=ansi`**. That terminfo entry has
no `csr` and no `ri`, so vim emulates a scrolling region with `il1`/`dl1` rather than setting one.

**Not yet implemented:** `ESC[r` (DECSTBM scrolling region) and `ESC M` (RI, reverse index) — both
needed for `TERM=vt100`/`xterm`, which scroll with `csr`+`ri`. Also `ESC[n@` (ICH), `ESC[nP` (DCH),
`ESC[nX` (ECH) and `ESC[nd` (VPA); the `ansi` terminfo advertises these, but vim never emits them.

**Silently ignored CSI sequences** (recognized to avoid display garbage):
`ESC[c` (DA), `ESC[n` (DSR), `ESC[t` (window ops), `ESC[!p` (soft reset), `ESC[!_` (DECSTR),
and any sequence with a private-parameter prefix `?` `>` `=` `<` (e.g. `ESC[?25l`, `ESC[>4;2m`)

#### SGR Parameters (`ESC[…m`)

| Parameter | Effect |
|-----------|--------|
| 0 | Reset all — white on black, normal intensity |
| 1 | Bold / high intensity |
| 2 | Normal intensity |
| 3 | Italic (aliased to inverse video — VBXE has no italic font) |
| 4 | Underline (acknowledged, no rendering — VBXE has no underline) |
| 5 | Blink (rendered as bold/high intensity) |
| 7 | Inverse video |
| 22 | Normal intensity (cancel bold) |
| 23 | Italic off (cancels the inverse alias) |
| 24 | Underline off (no-op) |
| 25 | Blink off (cancels the bold alias) |
| 27 | Inverse off |
| 30–37 | Foreground color (standard) |
| 40–47 | Background color (standard) |
| 51–55 | Framed / encircled / overlined and their cancels (acknowledged, no rendering) |
| 90–97 | Foreground color (high intensity) |
| 100–107 | Background color (high intensity) |

---

## Requirements

- Atari 8-bit computer (800XL, 130XE, etc.)
- **VBXE (Video Board XE)** with FX core
- **FujiNet** for N: device (Telnet/SSH), or Atari 850 interface (or compatible) for R: serial
- DOS with `CIOV` support (e.g., SpartaDOS X, MyDOS)

### Build Tools

- **[ca65/ld65](https://cc65.github.io/doc/ca65.html)** (cc65 suite) — primary assembler/linker
- **dir2atr** — for creating bootable ATR disk images
- **cl65 / sim65** (cc65 suite) — only needed for `make test`

---

## Files

| File | Description |
|------|-------------|
| `ANSIVBXE_ca65.asm` | Main source (ca65 assembler) |
| `scroll_rgn.inc` | CPU row/cell-move primitives for the scrolling region (shared with the unit test) |
| `atascii.inc` | ATASCII character and keyboard encoding (shared with the unit test) |
| `test/sim65/scroll_test.s` | Host-side unit test for `scroll_rgn.inc` (`make test`) |
| `test/sim65/atascii_test.s` | Host-side unit test for `atascii.inc` and the row cell moves (`make test`) |
| `test/smoke.sh`, `test/scroll.sh` | Visual tests, run on the remote host over a live session |
| `atarios_ca65.inc` | Atari OS equates |
| `atarihardware_ca65.inc` | Atari hardware equates |
| `VBXE_ca65.inc` | VBXE hardware equates |
| `IBMPC.FNT` | 256-character IBM PC CGA font |
| `first.fnt` | First 128 characters of `IBMPC.FNT` |
| `second.fnt` | Second 128 characters of `IBMPC.FNT` |
| `ANSI.PAL` | ANSI color palette — 16 colors as 3-byte RGB entries |
| `Makefile` | Build rules |
| `CHANGELOG.md` | Version history |
| `license.txt` | License terms |

---

## Building

Build the ca65 version (primary target):

```sh
make ca65
```

Build bootable ATR disk image:

```sh
make disk
```

Run the unit tests:

```sh
make test
```

The scrolling-region primitives in `scroll_rgn.inc` are pure CPU memory moves over the flat
80×24 cell array and reference no Atari or VBXE hardware, so the *same source* the XEX builds
is assembled for cc65's `sim65` 6502 simulator and exercised directly. Requires `cl65` and
`sim65` from the cc65 suite. For anything that needs the real screen, run `test/scroll.sh`
(or `test/smoke.sh`) on the remote host once the Atari has connected.

Clean build artifacts:

```sh
make clean
```

The code is ORG'd at `$2800`.

---

## Usage

1. Set `ANSIVBXE_ca65.ATR` as `D1:` in your emulator or write it to a real disk.
2. Boot the disk. The application starts automatically.
3. The banner shows the application name and version, followed by the device prompt.
4. Press `R` for serial (R: device) or `N` for FujiNet.
5. For FujiNet, follow the connection wizard (protocol → server → port; SSH also prompts for user → password).
6. To exit a session, log out from the remote host — the application detects the disconnect and returns to the device selection prompt.
7. Pressing **RESET** drops any active connection, reinitializes the display, and returns to the device selection prompt.

---

## Font

The IBM PC CGA font was recreated as two 128-character halves (`first.fnt`, `second.fnt`) and concatenated into `IBMPC.FNT`. Characters are 8×8 pixels, matching VBXE's native text mode cell size. The CGA font was chosen because most ANSI BBS systems rely on IBM extended graphics characters.

All the fonts in `disk/` are CP437-ordered, so in ANSI mode the received byte value *is* the glyph index and no translation is needed.

ATASCII mode is the exception: its character set is built at runtime from the Atari OS charset ROM at `$E000` rather than loaded from disk. The ROM is 1 KB / 128 glyphs and is copied into VBXE font RAM twice — verbatim into glyphs `$00-$7F` and inverted into `$80-$FF`. That gives inverse video for free, since inverting the bitmap is exactly what ANTIC does for a character with bit 7 set.

The ROM charset is stored in *internal* (screen code) order, and that order is kept rather than permuting the font into ATASCII order, because internal `$00` is space. Every "blank this cell" site in the terminal writes character `$00`, so all of them keep working unchanged in both modes. The ATASCII code is instead permuted on the way to the screen by `to_glyph` in `atascii.inc`.

---

## Palette

`ANSI.PAL` contains 16 RGB color entries (3 bytes each, 48 bytes total):
- **Bytes 0–23:** 8 standard (low-intensity) ANSI colors
- **Bytes 24–47:** 8 high-intensity ANSI colors

The palette is file-based (not hardcoded) to allow customization — notably to reproduce the CGA brown (`#AA5500`) used by many ANSI BBS systems.

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the full release history.

### v0.24 — 2026-08-14
- **Fixed the R: hangs and crashes introduced in v0.23.** `kbd_irq` saved A and X but not Y, and v0.23's ATASCII support added `ldy atascii_mode` onto the ordinary keypress path — so from v0.23 on, nearly every keystroke returned from the interrupt with Y clobbered. That is specifically fatal on R:, which polls CIO STATUS on IOCB 1 every main-loop iteration and so is almost always inside CIO's IOCB-to-zero-page copy loop, a loop indexed by X *and* Y. A keypress mid-copy left the loop mis-aligned, filling CIO's work area with a slice spanning two IOCBs; CIO then wrote that back over IOCB 1, and the next R: I/O dispatched through a bogus handler index straight into zero page. It affected ANSI mode too, not just ATASCII — the `ldy` runs whatever the mode is.
- **Fixed a double OPEN of R: when selecting a font** from the settings menu. `font_load_selected` issued one CLOSE but two OPENs, because v0.23 moved the reopen into `font_load_index` without dropping the caller's own trailing restore. The second OPEN did not fail cleanly: the XL OS skips the device lookup when the IOCB is still open, so it re-entered the 850 handler's OPEN on a live port.

### v0.23 — 2026-08-09
- **Added ATASCII terminal mode**, selectable from the OPTION menu. ATASCII is handled as a mode rather than a font: it has its own control set (`$9B` EOL, `$1C-$1F` cursor, `$7D` clear, `$9C`/`$9D` line insert/delete, `$FE`/`$FF` character insert/delete), its own character encoding, and its own keyboard encoding. The ANSI parser is bypassed entirely while it is active, since `$1B` quotes the next byte there and `$9B` is EOL rather than CSI.
- The ATASCII character set is built from the OS charset ROM at `$E000` at runtime, so nothing extra ships on the disk — and because it does no disk I/O, it needs none of the R: close/reopen bracketing a disk font load requires. It is kept in internal (screen code) order so that internal `$00` remains space and every existing cell-blanking site keeps working untouched.
- Selecting ATASCII sets the auto-wrap column to 40 to match how ATASCII art is drawn; a new `Width:` row switches it back to 80. Only auto-wrap moves — absolute positioning and all erase/scroll blanking stay physical-80.
- **The OPTION menu is now a settings menu, not just a font picker.** `Mode:` and `Width:` rows sit above a divider, with the font list below and a `*` marking the loaded font. The menu engine gained non-selectable rows, value rows that redraw without dismissing, and font-aware box and label glyphs — without the last of those, switching to ATASCII would have redrawn the menu itself in garbage.
- The 13 identical `font_load_*` procs collapsed into one table-driven action; adding a font is now a label, a path and a menu line instead of four coordinated edits.
- Added `test/sim65/atascii_test.s` — 42 checks over the encoding and row-editing primitives, run by `make test` alongside the scrolling tests.
- Fixed the `version` data field, which still read `v0.21` after the 0.22 release.

### v0.22 — 2026-08-02
- **Fixed the red screen after RESET.** The ANSI palette was being loaded into VBXE palette **0**, which is the palette VBXE renders the ordinary ANTIC/GTIA picture through. RESET stops XDL processing and hands the display back to ANTIC, but nothing restores palette 0, so DOS came back red on red — GR.0's `COLPF2 = $94` landed on entry 148 (ANSI colour 1) and the hi-res foreground `$9A` on entry 154 (also colour 1). The overlay now uses palette 1, which is VBXE's own default for it, and palette 0 is never touched.
- **Fixed transposed `PSEL`/`CSEL` equates.** The FX register map is `Dx44 = CSEL`, `Dx45 = PSEL`; both `VBXE.equ` and `VBXE_ca65.inc` had them the other way round. The bug was invisible because every VBXE register reads back as `$FF`, so the `inc csel` in the palette loops was really an `inc` of PSEL that stored `$00` — pinning the palette to bank 0 while `CB`'s own auto-increment did the colour stepping. Selecting any palette but 0 was impossible until this was corrected.
- **The BASIC ROM is now banked out at startup.** The MEMAC A window sits at `$A000`, the same address as the XL/XE BASIC ROM; with BASIC banked in, the ROM answers every access to the window, so the palette file reads back as ROM bytes and screen writes are lost. Cold boot happened to work because DOS boots with OPTION held, but the XL OS re-reads OPTION on warm start too — so pressing RESET without holding it banked BASIC back in and the terminal restarted onto a garbled display. `PORTB` bit 1 is now set before the window is opened, and the original value is restored on exit.

### v0.21 — 2026-07-07
- **Fixed vim scrolling under `TERM=ansi`.** Implemented `IL` (`ESC[nL`) and `DL` (`ESC[nM`), and replaced the `SD` (`ESC[nT`) stub with a real implementation. The `ansi` terminfo entry has no `csr` and no `ri`, so vim emulates a scrolling region with `il1`/`dl1` — neither of which existed, and both of which were silently swallowed by the CSI dispatcher. Only the *up* direction was broken because scrolling down needs no control sequence at all, just LF.
- Fixed `ED` (`ESC[J`) leaving the last cell of the cursor's row unerased (it used `79 - column` where `EL` correctly uses `80 - column`), and erasing nothing at all with the cursor at column 79.
- CSI sequences with a private-parameter prefix (`?` `>` `=` `<`) are now swallowed instead of falling into a public handler with a bogus parameter list — `ESC[>4;2m` was reaching `SGR_adr`.
- Silenced the OS SIO bus sound (`SOUNDR`) for FujiNet N: sessions. N: performs a raw SIO transaction per poll/read/keystroke-batch, so the serial bus whine played continuously. R: is unaffected (it streams over CIO concurrent mode). Restored on disconnect, exit and RESET.
- Added `make test`: the scrolling-region primitives live in `scroll_rgn.inc`, touch no Atari or VBXE hardware, and are unit-tested against the same source under cc65's `sim65` 6502 simulator. Also `test/scroll.sh` for visual verification over a live session.

### v0.20 — 2026-07-07
- Fixed a freeze when opening the OPTION font menu and selecting a font *before* a device (R:/N:) is chosen. `device_type` defaults to `0` (indistinguishable from "R: selected"), so the font swap ran the R: reopen/reconfigure against an R: device that was never opened and hung in `CIOV`. A new `dev_ready` flag now tracks whether a device is actually open, so pre-connection font loads only swap VBXE font RAM — no serial I/O, no hang. Font previewing before connecting still works; in-session R:/N: swap behavior is unchanged.

### v0.19 — 2026-05-11
- Popup menu border now uses CP437 single-line box-drawing glyphs (`┌ ┐ └ ┘ ─ │`) instead of ASCII `+ - |`. Affects the OPTION-key font selector and the pre-terminal device-select menu. All 13 shipped fonts are CP437-compatible so the border renders cleanly under every one.

### v0.18 — 2026-05-10
- Font menu now works on R: while connected (was blocked in v0.17). Wraps the font load with a pre-CLOSE + post-OPEN on IOCB 1 so the FujiNet R: handler cleanly exits concurrent mode before the disk SIO and re-enters it afterward. Tested with an active SSH session on FujiNet R: — the session survives the swap

### v0.17 — 2026-05-10
- OPTION-key font menu now opens mid-session, not just at the device-select prompt. On N: connections the full font menu works without disrupting the FujiNet session
- On R: connections OPTION opens a "Disconnect to change fonts" info dialog instead of the font menu (superseded in v0.18)

### v0.16 — 2026-05-10
- 11 additional fonts in the OPTION font menu (AscPrint, Balloon, Bozo, Bzzz2, Casual GT, Computer, Cursive, Hero, Newsletter, Preppie, Shadow); menu now lists 13 fonts total
- Font-menu labels switched to compact mixed-case style ("IBMPC", "AtariPC", etc.) — dropped the " font" suffix
- Fixed `menu_draw_box` off-by-one: right border was missing on item rows because the middle-cell loop wrote one cell short and the misplaced border was overwritten by the row clear
- Fixed 5 font menu entries that silently failed to load — `dir2atr` truncates >8-char basenames to MyDOS 8.3, so the `font_path_*` strings needed the truncated names

### v0.14 — 2026-05-05
- Curly braces `{` and `}` typeable via CTRL+`<` and CTRL+`>` (previously displayable from the host but unsendable from the keyboard)
- Arrow keys (CTRL+`-` / `=` / `+` / `*`) now send VT100/ANSI cursor escape sequences (`ESC[A`/`B`/`D`/`C`) instead of single C0 control characters; bash readline, vim, less, mc, etc. now respond as expected. Down-arrow previously sent nothing at all.
- New generic multi-byte escape-sequence dispatch in `kbd_irq` — adding HOME / END / PAGE UP / DOWN / F-keys later is a one-line table append per key
- CTRL+SHIFT+`+` / `*` / `-` retain their FS / RS / US bindings so those C0 controls remain reachable

### v0.12 — 2026-05-03
- `HT` (Horizontal Tab, `$09`) now advances the cursor to the next 8-column stop instead of being a no-op
- `SGR 3` (italic) is aliased to inverse video for visible feedback; `SGR 23` cancels it
- `SGR 22 / 24 / 25 / 27` (cancel bold / underline / blink / inverse) now route correctly — they were silently dropped because the dispatcher's high-BCD-nibble routing had no entry for `$20`
- `SGR 4` (underline) and `SGR 51 – 55` (framed / encircled / overlined) acknowledged as documented no-ops so the parser state can't drift
- Refactored the SGR `is_last_parm` dispatch to long branches (`bne skip / jmp target / skip:`) so future additions don't hit the 6502's ±127-byte branch reach
- `HTS` and `SD` stub comments rewritten to honestly describe why they remain unimplemented; orphaned `EL` header comment removed

### v0.11 — 2026-05-03
- Fixed FujiNet SSH authentication on real hardware: the `$FE` password SIO call was missing a `DSTATS = $80` reset between it and the preceding `$FD` username call, so the OS sent the command frame with no transfer direction and the password buffer was never transmitted

### v0.10 — 2026-05-02
- FujiNet N: device responsiveness improvements: keyboard sends now coalesce up to 64 bytes per SIO write (faster paste and burst typing), keystrokes flush during long inbound bursts so typing stays responsive while output renders, and PROCEED is re-armed earlier so back-to-back bursts have no render-time gap
- OS SIO bus sound (`SOUNDR`) silenced during the session and restored on exit, so FujiNet traffic no longer clicks

### v0.09 — 2026-05-01
- Colorized the `VBXE` letters in the startup banner using ANSI SGR sequences (Red, Green, Blue, Yellow)

### v0.08 — 2026-05-01
- On a failed FujiNet connection, pressing Return now returns to the device selection prompt (clears screen) instead of quitting
- Device selection screen now clears the display and homes the cursor before printing the banner, so it always appears at the top
- Q=Quit option removed from device selection prompt
- Fixed bug where selecting R: serial after a failed N: FujiNet attempt caused key presses to be ignored (device_type was left set to N:)

### v0.07 — 2026-04-29
- Restore OS keyboard IRQ (VKEYBD) before returning to device selection after disconnect, so CIO K: reads work correctly
- Restore VBXE/ANTIC state cleanly on exit to DOS

### v0.06 — 2026-04-28
- Telnet connection wizard no longer prompts for USER or PASSWORD — credentials are SSH-only

### v0.05 — 2026-04-27
- Renamed application to **VBXETERM**
- Banner with application name and version shown at device selection prompt
- RESET button now restarts the application cleanly (closes any active connection, reinitializes VBXE display) instead of leaving the screen in a broken state
- FujiNet disconnect detection: returns to device selection on remote close (graceful logout), abrupt drop, or SIO timeout
- Replaced raw URL entry with step-by-step connection wizard (PROTOCOL / SERVER / PORT / USER / PASSWORD)
- Password entry masked with asterisks
- Backspace (Atari Delete Back key, ATASCII `$7E`) works correctly in all input fields
- LF-as-CRLF mode implemented and enabled by default
- ESC 7 / ESC 8 (DECSC/DECRC) cursor save and restore
- CSI intermediate byte parsing corrected (was misidentifying parameter bytes as intermediate)
- Silently ignore CSI `c`, `n`, `t`, `!p`, `!_` sequences to avoid display corruption on terminals that probe capabilities

### v0.04 — 2026-04-14
- FujiNet N: device support via raw SIO (no N: CIO handler required)
- Telnet and SSH connections via FujiNet
- PROCEED interrupt handler for non-blocking FujiNet receive
- FujiNet nlogin ($FD/$FE) pre-configures SSH credentials before OPEN
- R: serial device confirmed working; send buffer ring-buffer bug fixed

### v0.02 — 2026-04-07
- Relaxed VBXE FX core detection to accept FX-compatible firmware revisions
- Corrected palette initialization

### v0.01 — 2015-04-07
- VBXE memory window moved to `$A000–$AFFF` to avoid conflict with extended RAM

### v0.00 — 2015-04-06
- Initial release
- C0/C1 control set, SGR, basic CSI sequences

---

## License

See [license.txt](license.txt) for full terms. In short:

- Free to use and distribute
- May be sold only if the buyer is informed it is also available for free and agrees to pay anyway
- Derivative works must retain license notices and credit original authors

---

## Snapshots

DarkForce BBS
<img width="1470" height="1197" alt="image" src="https://github.com/user-attachments/assets/c8fb58ac-1469-4b29-9b02-d87ea72c83ee" />
