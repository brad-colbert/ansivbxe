# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Version numbers follow the format `x.zz.yyyy.mm.dd` where `x` is incremented for major new features and `zz` for bugfixes and minor features.

---

## [0.23] - 2026-08-09

### Added
- **ATASCII terminal mode.** The terminal can now be pointed at an Atari BBS. ATASCII is handled as a *mode*, not a font — it has its own control set, its own character encoding and its own keyboard encoding, and `process_char` forks to a separate dispatcher for it. That fork is not optional: `$1B` in ATASCII quotes the next byte rather than introducing an escape sequence, and `$9B` is EOL rather than CSI, so the ANSI parser cannot be reused for even one byte of it.

  Implemented controls: `$1B` quote-next, `$1C-$1F` cursor up/down/left/right (wrapping at the screen edges, where ANSI's CUU/CUD clamp — which is why none of the ANSI handlers could be shared), `$7D` clear + home, `$7E` destructive backspace, `$7F` tab, `$9B` EOL, `$9C`/`$9D` delete/insert line, `$9E`/`$9F` clear/set tab stop (no-ops, matching the existing fixed 8-column `HTS`/`VTS` behaviour), `$FD` buzzer, `$FE`/`$FF` delete/insert character. Everything else prints, including the whole `$80-$FF` inverse range.

- **The ATASCII character set is built from the OS ROM at `$E000`, not loaded from disk** (`_vbxe_font_from_rom`). The ROM charset is 1 KB / 128 glyphs; it is copied verbatim into glyphs `$00-$7F` and again inverted into `$80-$FF`, so bit 7 of a screen byte selects inverse video with no attribute handling anywhere — which is exactly what ANTIC does with an inverse character. Because this does no CIO and therefore no SIO, it needs none of the R: close/reopen bracketing that every disk font load requires.

  The font is deliberately built in **internal (screen code) order rather than ATASCII order**, and the ATASCII code is permuted into it by `to_glyph` on the way to the screen. Internal `$00` is space, so every "blank this cell" site in the terminal — `blank_rows`, `ED_adr`, `EL_adr` and the two blitter fill bytes — keeps writing char `$00` and keeps producing a blank cell, unchanged. An ATASCII-ordered font would have made glyph `$00` a heart and required patching all seven sites plus runtime-patching two blitter control blocks; `scroll_rgn.inc` and its unit test would have needed a blank-character parameter threaded through them.

- **`row_insert_char` / `row_delete_char`** in `scroll_rgn.inc` — within-row cell moves backing ATASCII `$FF`/`$FE`. They bound themselves by `term_last_col`, so in 40-column mode they leave columns 40-79 untouched. Hardware-free, so they are unit-tested; they also make ANSI ICH/DCH nearly free later.

- **ATASCII keyboard encoding.** RETURN sends `$9B`, BACKSPACE `$7E`, TAB `$7F`, and the arrow keys send single `$1C-$1F` codes instead of three-byte `ESC [ x` sequences. The Atari inverse-video key — keycodes 39/103/167/231, all previously dead entries in `keycode_table` — becomes a sticky bit-7 latch. The latch is applied only to codes that have an inverse counterpart: `$1B-$1F` are excluded so that inverse+ESC cannot silently become EOL, and RETURN still sends a bare EOL with inverse switched on, as on hardware.

- **A 40/80-column auto-wrap setting** (`term_last_col`). ATASCII art is drawn for a 40-column screen, so selecting ATASCII sets the wrap column to 40; the Width row switches it back to 80 for hosts that assume it. Only auto-wrap is affected — absolute ANSI positioning and every erase/scroll blanking operation stay physical-80, since a stale glyph left in column 45 after a clear would be worse than an unreachable column.

- **`atascii.inc`** and `test/sim65/atascii_test.s` — the encoding primitives are hardware-free, so the same source the XEX builds runs under `sim65`. 42 checks: `to_glyph` as the identity across all 256 codes in ANSI mode, each of the four ATASCII code bands at its boundaries, bit-7 pass-through, X preservation (`put_byte` keeps 0 there for its `(zp,X)` store), the keyboard remapping with and without the inverse latch, and `row_insert_char`/`row_delete_char` at column 0, mid-row, at the margin, and against a 40-column margin with columns 40-79 verified untouched.

### Changed
- **The OPTION menu is now a settings menu rather than a font picker.** It gains a `Mode:` row (ANSI / ATASCII) and a `Width:` row (80 / 40) above a divider, with the font list below. Selecting any CP437 font also selects ANSI, so mode and font can never disagree and one Mode row is sufficient for mutual exclusion; switching to ATASCII and back reloads whichever font row is marked active. The loaded font is marked with a `*`.

  The menu engine grew three things to support this: rows whose `action_ptr` is `$0000` are non-selectable (the highlight steps over them, RETURN ignores them), value rows rewrite their own label and redraw without dismissing, and the box-drawing glyphs and all label text now go through the active font's glyph set — otherwise selecting ATASCII would have redrawn the menu in garbage, since `menu_draw_box` writes raw CP437 glyph indices and `menu_put_str_at` writes raw ASCII.

- The 13 identical `font_load_*` procs collapsed into one `font_load_selected` driven by the row's own position in `main_menu`, plus a `font_path_table`. Adding a font was four coordinated edits; it is now a label, a path, and a menu line.

- The program's own screen output (banner, prompts, connection wizard) now goes through `process_char_ansi`, which always uses the ANSI control interpretation regardless of mode. Only the *parser* fork is bypassed — glyph translation still applies, so the text draws correctly in whichever font is loaded. Without this the banner's colour sequences would have printed as literal `[31m` runs in ATASCII mode, since `$1B` there quotes the following byte.

### Fixed
- The `version` data field still read `v0.21.2026.07.07`; it was missed in the 0.22 bump.

## [0.22] - 2026-08-02

### Fixed
- **The screen turned red after RESET, and DOS came back unreadable.** The ANSI palette was loaded into VBXE palette **0**. Palette 0 is not a spare bank — it is the palette VBXE renders the ordinary ANTIC/GTIA picture through, so overwriting it remaps every OS colour-register value on the machine. Pressing RESET terminates XDL processing and hands the display back to ANTIC, but per the FX manual "no RESET is able to restore the default VBXE palette if it has been already modified by a program". The result was arithmetically exact: GR.0's background `COLPF2 = $94` indexes entry 148, which the background half of the ANSI layout (8 colours × 16 entries starting at 128) fills with colour 1, `$AA0000`; the ANTIC hi-res foreground byte `$9A` (COLPF2's hue + COLPF1's luma) indexes entry 154, also colour 1. Red text on a red background.

  The overlay now uses palette **1** — VBXE's own default for the Overlay, chosen by the `XDL OV PALETTE` field of the XDL's ATT block (`%00010001`) — and palette 0 is left alone. Verified in Altirra: after RESET, `.vbxe_pal $90` shows the stock Atari ramp with entry `$94` back to `1C4092`, and MyDOS returns to its normal blue menu.

- **`PSEL` and `CSEL` were transposed in the register equates.** The FX core register map is `Dx44 = CSEL`, `Dx45 = PSEL`; `VBXE.equ` and `VBXE_ca65.inc` both had it backwards. Nothing appeared to be wrong because every VBXE register reads back as `$FF`: the `inc csel` in the palette loops was really an `inc` of PSEL, which read `$FF` and stored `$00`, pinning the palette to bank 0 forever — and the colour stepping everyone assumed that `inc` was doing was actually `CB`'s documented auto-increment of CSEL. The two bugs cancelled out precisely as long as the target was palette 0, and selecting any other palette was impossible until this was fixed.

  The ca65 loops now also write CSEL explicitly for every entry instead of leaning on the auto-increment, which the FX manual documents but which older cores predate.

- **The BASIC ROM is banked out before the MEMAC window is opened.** The MEMAC A window is mapped at `$A000`, which on an XL/XE is also where the BASIC ROM lives; with BASIC banked in, the ROM answers every CPU access to the window, so the palette file reads back as ROM bytes and every screen write is lost. Cold boot happened to work because the machine boots with OPTION held to load DOS, but the XL OS re-reads OPTION on *warm* start too — so pressing RESET without holding OPTION banked BASIC back in, and the terminal restarted onto a garbled display (a uniform lavender screen, being whatever BASIC ROM bytes the palette loader happened to read). `_vbxe_init` now sets `PORTB` bit 1 on entry, so the window is ours on every start, cold or post-RESET; `restore_os_hooks` puts the original `PORTB` back on the way out.

## [0.21] - 2026-07-07

### Added
- **IL — Insert Line (`ESC[nL`)** and **DL — Delete Line (`ESC[nM`)**. These are what fixes vim scrolling over an SSH session with `TERM=ansi`, which was the reported symptom: scrolling down worked, but moving the cursor up never inserted lines at the top.

  The `ansi` terminfo entry has **no `csr`** (scrolling region) and **no `ri`** (reverse index), so vim cannot set a scroll region and instead emulates one with `il1`/`dl1`. Capturing vim's actual output under a real 80×24 pty confirms it: scrolling up past the top of the window emits `ESC[L` (18 emissions for 18 scroll events) and nothing else; `dd` emits `ESC[M`; `o` emits `ESC[L`. Scrolling *down* emits no control sequence at all — just LF — which is exactly why only the up direction was broken. Neither `ESC[T` nor `ESC M` is ever emitted under `TERM=ansi`.

  Per xterm and the Linux console, IL and DL leave the cursor column alone. (Real DEC hardware homed it to the left margin; nothing modern does, and vim re-positions afterwards regardless.)

- **SD — Scroll Down (`ESC[nT`, terminfo `rin`)** is now implemented. It had been a bare `rts` with a comment claiming it needed a reverse-direction blitter. It does not: the entire 80×24 screen is CPU-visible at `$A100-$AFFF` through the 4K MEMAC A window, so a plain backwards row copy suffices.

- `scroll_rgn.inc` — shared CPU row-move primitives (`copy_row_fwd`, `blank_rows`, `scroll_rgn_up`, `scroll_rgn_down`) plus `row_addr_lo`/`row_addr_hi` lookup tables. Rows are always at least 160 bytes apart, so source and destination never overlap byte-wise; there is exactly one byte-copy loop, and the direction of the move is carried entirely by the row-pointer stride (`+160`/`-160`). Groundwork for a real DECSTBM scrolling region.

- `make test` — a host-side unit test (`test/sim65/scroll_test.s`) that runs the *same* `scroll_rgn.inc` source under cc65's `sim65` 6502 simulator. 16 checks: full-screen up/down for n=1/3/23/24/99/255, a bounded region `[5,20]` verifying rows outside it never move, the degenerate one-row region (IL/DL with the cursor on the bottom margin), `blank_rows`, and the `X=0` guard. The fill pattern makes each cell's colour a function of both row *and* column, so a single dropped or misplaced byte anywhere in a row changes a sampled cell.

- `test/scroll.sh` — visual companion to `test/smoke.sh` for eyeballing IL/DL/SU/SD boundaries over a live session.

### Fixed
- **`ED` (`ESC[J`, erase-in-display, mode 0) was off by one column.** It computed the cell count as `79 - column` where `EL` correctly uses `80 - column`. The last cell of the cursor's row was never erased, and with the cursor at column 79 the row was not touched at all. `ESC[J` is `ed` in the `ansi` terminfo and vim emits it constantly, so this left stray characters at the right edge independently of the scrolling bug.

- **Private-parameter CSI sequences no longer reach public handlers.** `is_ctrl_seq` stores a leading `?` / `>` / `=` / `<` (`$3C-$3F`) as an ordinary parameter byte, so `ESC[>4;2m` (xterm `modifyOtherKeys`, which some ssh setups emit) was dispatching into `SGR_adr` with a garbage parameter list. `do_ctrl_seq` now swallows any sequence whose first parameter byte is in `$3C-$3F`. This is also a prerequisite for adding DECSTBM (`ESC[r`), since `ESC[?1049r` would otherwise reset the margins.

### Changed
- **The OS SIO bus sound (`SOUNDR`, `$41`) is now silenced for the duration of an N: session.** N: issues a raw `jsr SIOV` for every status poll, every read and every coalesced keystroke batch, so POKEY channel 4 — left audible while channels 3+4 clock the serial bit stream — whines continuously. `device_open` zeroes `SOUNDR` when `device_type` is N:; `device_select` restores it on the way back out (disconnect or menu dismiss), and `restore_os_hooks`/`reset_cleanup` already covered exit and RESET.

  R: is deliberately left alone: it streams over CIO concurrent mode and never enters the OS SIO sound path.

  Note that v0.19's changelog claimed this was already done. It wasn't — the write was committed already commented out (`cf3a698`, "Testing stoping SIO sound. I don't think it worked."), with a source comment blaming a suspected SSH breakage the commit message doesn't mention. Nothing in the codebase resets `SOUNDR` mid-session (`restore_os_hooks` runs only at exit), so the earlier attempt should have worked. It is scoped to N: now regardless.

- `SU` (`ESC[nS`) now honours the scrolling region. With no margins set — the only case today — it still uses the `scroll_1d` blitter, which is roughly 20× faster than the CPU path and matters because terminfo `nel` is `\r\E[S`.
- Removed `mem_move`, which was dead (`vbxe_lib.asm` carries its own private copy) and forward-only, so unusable for insert-line anyway.
- Version strings reconciled: the source header said `v0.19`, the `version` string said `v0.19.2026.05.11`, and the banner said `v0.20`.

### Notes on the implementation (for posterity)
- `scroll_top`/`scroll_bot` and the row-copy pointers live at `$B0-$B5`, **not** `$A3-$A9`. `$A3-$AF` is the OPTION-menu state (`menu_row`…`ps_str`), and the menu is reachable mid-session, so anything parked there is clobbered the moment the user presses OPTION.
- The row-copy pointers are `scr_src`/`scr_dst`, deliberately *not* `src_ptr`/`dst_ptr`/`counter`. `print_str` keeps its string pointer in `src_ptr` and `read_line_vbxe` keeps its buffer index in `counter`, both live across `jsr process_char` — which can reach a scroll. This was safe only because `scroll_1d` is a pure blitter that touches no zero page; a CPU memmove built on `src_ptr` would have corrupted both.
- Blanked cells are filled with `text_color`, never `$00`: colour-byte bit 7 is the VBXE overlay opacity bit, so a `$00` colour renders the cell transparent rather than blank.

### Still missing
- No DECSTBM (`ESC[r`) scrolling region, and `ESC M` (RI) is still a no-op. Both are needed for `TERM=vt100` and `TERM=xterm`, which scroll with `csr`+`ri` rather than `il`/`dl` and are considerably more efficient over SIO. `ESC D` (IND) also still routes through `LF_adr` and so wrongly honours `lf_mode`, doing CR+LF instead of a bare index.
- `ICH` (`ESC[n@`), `DCH` (`ESC[nP`), `ECH` (`ESC[nX`) and `VPA` (`ESC[nd`) remain unimplemented. The `ansi` terminfo advertises all four, but the pty capture shows vim never emits any of them — it redraws the line instead.

---

## [0.20] - 2026-07-07

### Fixed
- **Font selection no longer freezes when used before a device is selected.** Opening the OPTION font menu at the device-select screen (before choosing R: or N:) and picking a font could hang the machine. `device_type` defaults to `0` at cold start, which is indistinguishable from "R: selected", so `font_swap_done` ran the R: recovery path — `open_r_device` → `configure_r_device` (CIO OPEN "R1:" + XIO 36/38/34/40) — against an R: device that was never opened and may be absent, hanging in `CIOV` (no timeout, no status check). The same stale-`device_type == 0` window also occurs after an N: disconnect returns to `device_select`.
- Added a `dev_ready` flag as a dedicated "a device is currently open" signal, set in the common `device_open` routine (reached only after a successful R: or N: open) and cleared at the top of `device_select` (cold start, every disconnect, and each menu dismiss). `font_swap_prep_r` and `font_swap_done` now gate their R: CLOSE/OPEN on `dev_ready`, so a font load with no device open only swaps VBXE font RAM — no serial I/O, no hang. Font previewing before connecting still works, and the in-session R:/N: swap behavior (v0.18) is unchanged.

---

## [0.19] - 2026-05-11

### Changed
- **Popup menu border now uses CP437 single-line box-drawing glyphs.** The OPTION-key font selector and the pre-terminal device-select menu previously drew their border with plain ASCII `+`, `-`, `|`. With all 13 shipped fonts being CP437-compatible, `menu_draw_box` now uses `┌ ┐ └ ┘ ─ │` (218 / 191 / 192 / 217 / 196 / 179) for cleaner borders. Stems use bit `$10` and the horizontal sits at row 4, so corner/edge junctions are pixel-clean under every shipped font. New `BOX_*` equates and a sibling `mb_corner_r` zero-page byte split the previously-single corner glyph into left/right so top/bottom rows can use distinct corners (┌┐ vs └┘).

---

## [0.18] - 2026-05-10

### Added
- **Font menu now works on R: while connected.** v0.17 blocked OPTION on R: with a "Disconnect to change fonts" dialog because the disk SIO inside `_vbxe_load_font` would clobber POKEY's serial config and wedge the FujiNet R: handler unrecoverably. v0.18 wraps the font load with a pre-CLOSE + post-OPEN on IOCB 1, so the R: handler cleanly exits concurrent mode before the disk SIO and re-enters it afterward. Tested with active SSH session on FujiNet R: — the session survives the swap.

### Changed
- New `font_swap_prep_r` helper, called at the top of every `font_load_*` proc. On R:, issues `CMD_CLOSE` to IOCB 1 while the handler is still healthy — equivalent to the `NS_EndConcurrent` teardown sequence in the FujiNet netstream reference handler (disable POKEY serial IRQs, restore VSER* vectors, deassert motor line). No-op on N:, which is unaffected by interleaved disk SIO.
- `font_swap_done` now re-opens IOCB 1 via `open_r_device` (→ `configure_r_device`) on R: to put the R: handler back into concurrent mode after the disk SIO completes. N: path is unchanged.
- Removed `main_menu_r_blocked`, `lbl_r_blocked`, and `action_dismiss_only` — unreachable now that R: supports the full font menu.

### Notes on the prior investigation (for posterity)
- Earlier rounds (v0.17 development, Phases 3–6) tried to recover R: *after* the disk SIO had run, including: re-issuing `configure_r_device` (XIO 36/38/34/40), explicit POKMSK/IRQEN re-enable, direct POKEY hardware register write-back with the FujiNet R: working values (AUDCTL=$78, SKCTL=$73, AUDF1/3=$56), and post-disk-SIO close+reopen. POKEY could be made byte-perfect but R: stayed dead; the close+reopen hung in CIOV because the wedged R: handler never responded. **The unexplored angle was acting *before* the disk SIO while R: was still healthy** — that's what v0.18 implements. Lesson: concurrent-mode protocols need explicit enter/exit cooperation; restoring downstream hardware state isn't sufficient.

---

## [0.17] - 2026-05-10

### Added
- **OPTION-key font menu now accessible mid-session.** Previously OPTION only opened the menu at the device-select prompt; once connected, the user had to disconnect to change fonts. The main `wait_for_byte` loop now polls `CONSOL` bit 2 each pass and opens the menu on demand. On N: (FujiNet) the full 13-font menu works without disrupting the connection — disk SIO during the font load is request/response on the SIO bus and doesn't interfere with N:'s own SIO traffic.

### Changed
- On R: connections, OPTION opens a one-line "Disconnect to change fonts" info dialog instead of the font menu. ENTER or ESC dismisses; no font swap is attempted. See *Known Limitation* below for the reason.

### Known Limitation
- **Font swap is unsupported on R: while connected.** The disk SIO inside `_vbxe_load_font` triggers the OS's `SIOInitHardware`, which clobbers POKEY's serial-port config (AUDCTL, AUDF3/AUDF4 baud divisors, SKCTL) and clears POKMSK serial-IRQ bits 4–5. Diagnostic snapshots (Altirra `.pokey` + IOCB/vector dumps) confirmed:
  - VSERIN/VSEROR/VSEROC vectors at $020A–$020F are preserved through the disk SIO and still point to the FujiNet R: handler.
  - IOCB 1 contents (handler ID, device, command, AUX) are preserved.
  - POKEY hardware can be rewritten back to the working values byte-for-byte and POKMSK/IRQEN re-enabled — but R: still won't pass data.
  - Any subsequent CIO call to attempt close+reopen recovery hangs in CIOV indefinitely; the FujiNet R: handler is in an unresponsive state from which no Atari-side action recovers.

  Conclusion: the failure is internal to the FujiNet R: firmware's handling of an external POKEY clobber while concurrent mode is active. A fix would require firmware-side logic (detect POKEY clobber, re-init concurrent state). Until that lands, the menu blocks font selection on R: rather than silently breaking the connection.

---

## [0.16] - 2026-05-10

### Added
- **11 additional fonts in the OPTION font menu.** AscPrint, Balloon, Bozo, Bzzz2, Casual GT, Computer, Cursive, Hero, Newsletter, Preppie, Shadow — all bundled in the ATR and selectable from the same OPTION-key popup that previously only offered IBMPC and ATARIPC. The menu now lists 13 fonts; the new entries are appended in alphabetical order beneath IBMPC + AtariPC so the cursor still defaults to IBMPC.

### Changed
- Font-menu label style: dropped the trailing " font" suffix and switched to compact mixed-case names ("IBMPC", "AtariPC", "AscPrint", etc.) so 13 rows fit cleanly in the 14-char interior width.

### Fixed
- `menu_draw_box` off-by-one in the middle-cell loop drew the right border one column too far left. On item rows the misplaced border landed inside `menu_redraw_items`'s row-clear range and was overwritten with a space, so the right `|` was invisible on every middle row. Top/bottom rows kept their misplaced `+` because they're never re-cleared. Loop exit condition (`cmp #$02` → `cmp #$01`) corrected; box now renders the full perimeter for any width. Bug existed in the v1 menu too — masked by the smaller box.
- Five font menu entries (AscPrint, Casual GT, Cursive, Newsletter, Preppie) silently failed to load. Their source filenames in `disk/` exceed 8 chars; `dir2atr` silently truncates to MyDOS 8.3 (e.g. `ASCPRINPC.FNT` → `ASCPRINP.FNT`), but the asm `font_path_*` strings still requested the long names. Updated the 5 path strings to match the truncated 8-char names already on the ATR. The other 8 fonts have ≤8-char basenames and were unaffected.

---

## [0.15] - 2026-05-08

### Added
- **Settings menu at device select.** Pressing OPTION at the R/N prompt opens a popup menu where the user can pick a font before connecting. v1 ships with two choices — IBMPC and ATARIPC — but the framework is extensible: add an entry to `main_menu`, define a label string and a leaf action proc (do work → set `menu_dismiss = 1` → rts), and the new item shows up. Arrow keys navigate, ENTER selects, ESC dismisses. The screen content under the box is saved and restored byte-for-byte.
- `_vbxe_load_font(path)` exported from `vbxe_lib`. Loads a 2 KB font file via CIO into VBXE font RAM at $0000 and restores the prior MEMAC bank, so it can be called with the screen overlay live without disturbing it. Uses **IOCB 3** so it never collides with R: device on IOCB 1 or with the K: synchronous-read path on IOCB 2.

### Changed
- `device_select` now installs `kbd_irq` (with `menu_active = 1`) for the duration of the prompt and polls `menu_key_ready` instead of doing a blocking `K: GET_CHARS`. This lets it detect OPTION (CONSOL bit 2) and letter keys (R/N) in the same loop. The OS VKEYBD vector is restored before falling through to `choose_n` or `choose_r` so the K: CIO calls in the FujiNet connection wizard continue to work unchanged.
- `open_r_device` split into `open_r_device` (CIO open) + new `configure_r_device` (XIO 36/38/34/40). No behavior change at startup; the split exists so post-OPEN configuration can be re-applied later if needed (an earlier attempt to recover R: from disk-SIO POKEY clobber used this — left in place for future reuse).

### Fixed
- `kbd_irq` no longer translates every keypress to the letter `l`. The menu-divert check (`lda menu_active / beq @no_menu`) clobbers A before the `tax / lda keycode_table,x` lookup; reloading `KBCODE` into A at `@no_menu` before the `tax` restores correct behavior. Without this fix every keystroke routed through `keycode_table[0]` ($6C, ASCII 'l').

---

## [0.14] - 2026-05-05

### Added
- Curly braces `{` and `}` are now typeable via **CTRL+`<`** and **CTRL+`>`**. The Atari character set has no curly-brace keys, but VBXETERM renders the PC font that includes them — `{` and `}` were previously displayable from a remote host but unsendable from the keyboard. The two CTRL+`<`/`>` table slots (keycodes 182 and 183) were both unused (`0`), so no existing keyboard behavior is lost.
- Arrow keys now send VT100/ANSI cursor escape sequences. CTRL+`-` / CTRL+`=` / CTRL+`+` / CTRL+`*` (UP / DOWN / LEFT / RIGHT — the symbols printed on the upper half of those Atari keys) now emit `ESC[A` / `ESC[B` / `ESC[D` / `ESC[C` instead of single C0 control characters. Bash readline history, `vim`/`vi` cursor motion, `less` paging, `mc` navigation, etc. now work as expected on remote hosts. Down-arrow previously sent no character at all.

### Changed
- `kbd_irq` gained a generic multi-byte sequence dispatch: `keycode_table` entries with bit 7 set are interpreted as indexes into a new `escape_seq` table (3 bytes per entry). Adding HOME / END / PAGE UP / PAGE DOWN / F-key bindings later is now a one-line append per key with no further IRQ changes. The dispatch checks for at least 3 free slots in the send FIFO before pushing so partial sequences are never queued (the whole keypress is dropped if the buffer can't hold it).
- CTRL+SHIFT+`+` / `*` / `-` retain their existing FS / RS / US bindings (`$1C` / `$1E` / `$1F`) so those C0 control characters remain reachable from the keyboard for anyone who needs them.

---

## [0.13] - 2026-05-04

### Fixed
- ESC sequences with an intermediate byte (`$20–$2F`) — most commonly the VT100/VT220 character-set designators `ESC ( <c>`, `ESC ) <c>`, `ESC * <c>`, `ESC + <c>`, and `ESC # <c>` — leaked their final byte to the screen. Only the intermediate byte was consumed; the third byte fell through `process_char` with no flags set and was printed as text (e.g. `ESC ( @` rendered a stray `@`). The escape dispatcher now recognises intermediate bytes per ECMA-48 and sets a new "eat next byte" state on `ctrl_seq_flg` (bit 5) so the final byte is silently consumed.
- DCS (`ESC P …`), SOS (`ESC X …`), OSC (`ESC ] …`), PM (`ESC ^ …`), and APC (`ESC _ …`) sequences leaked their entire body to the screen. The C1 introducers were stubbed as a shared `rts` with no state change, so every subsequent byte — title text, embedded CSI like `[3;52H`, and the terminator — printed as literal characters until something happened to look like a fresh ESC sequence. The five introducers now enter a "string mode" that consumes bytes silently until BEL (`$07`) or ST (`ESC \`).

### Changed
- `ctrl_seq_flg` (`$8B`) now uses bit 5 (eat-next-byte) and bit 4 (string mode) in addition to bits 7 (escape) and 6 (CSI).
- `process_char` now leads with a single `LDA / BNE` on `ctrl_seq_flg` so the no-state hot path saves a cycle versus the previous `BIT / BVS / BPL` chain. The state-aware paths (escape, CSI, string mode) are reached via a follow-up `BIT` only when at least one flag bit is set.

---

## [0.12] - 2026-05-03

### Added
- `HT` (Horizontal Tab, `$09`) advances the cursor to the next 8-column stop instead of being a no-op. Bash and other shells that emit raw tabs now align as expected.
- `SGR 3` (italic) is aliased to inverse video so apps that emit italic now have a visible effect (VBXE has no italic font; real italic glyphs are tracked as a follow-up).
- `SGR 23` (italic off) cancels the inverse alias.

### Fixed
- `SGR 22 / 24 / 25 / 27` (cancel bold / underline / blink / inverse) were silently dropped because the dispatcher's high-BCD-nibble routing had no entry for `$20`. They now reach the existing `un_bold` / `un_inverse` handlers (or a documented no-op for codes with no VBXE rendering, like underline).
- `SGR 4` (underline) was silently dropped in `simple_attrib`'s cmp-chain. Now explicitly routed to a no-op so the parser state can't drift on apps that toggle underline.
- `SGR 51 – 55` (framed / encircled / overlined / cancellations) were silently dropped. They now route to a documented no-op so the parser doesn't accidentally fall through into unrelated handlers.

### Changed
- Refactored the SGR `is_last_parm` dispatch from short branches (`beq target`) to long branches (`bne skip / jmp target / skip:`). The 6502's ±127-byte branch reach was about to break with the new entries; the long-branch pattern future-proofs the SGR area against the next addition.
- `HTS` (`$88`) and `SD` (`ESC[T`) comments updated to honestly describe why they remain stubbed (custom tab-stop tables and reverse-direction blitter, respectively) instead of misrepresenting them as forgotten.
- Removed an orphaned `EL` header comment block that incorrectly claimed only `n=0` was supported (the actual handler supports modes 0/1/2).

---

## [0.11] - 2026-05-03

### Fixed
- FujiNet SSH password was never transmitted on real hardware. The `nlogin_n_device` routine sent the `$FD` (login) and `$FE` (password) SIO commands back-to-back without re-asserting `DSTATS = $80` between them. After the first `SIOV`, the OS overwrites `DSTATS` with the result code (`$01` on success), so the second `SIOV` ran with no data-transfer direction and the 256-byte password buffer was never sent. SSH authentication then failed regardless of the entered password. Now matches the netcat reference, which sets `dstats = 0x80` before each call.

---

## [0.10] - 2026-05-02

### Changed
- FujiNet N: device responsiveness improvements:
  - Keyboard sends are now coalesced into a single SIO write (up to 64 bytes per call) instead of one SIO transaction per byte. Paste and burst typing are noticeably faster.
  - Queued keystrokes are flushed every 32 received bytes during inbound rendering, so typing remains responsive while large server bursts are still drawing to the screen.
  - PROCEED interrupt is cleared and re-armed at the start of the receive routine instead of after the batch finishes rendering, so back-to-back inbound bursts no longer have a render-time gap.
- OS SIO bus sound (`SOUNDR`) is silenced for the duration of the session and restored on exit, so the per-byte click/whine no longer plays during FujiNet traffic. **(Correction, v0.21: this never actually shipped — the `sta SOUNDR` was committed commented out. It is live as of v0.21, scoped to N: sessions.)**

---

## [0.09] - 2026-05-01

### Added
- Colorized `VBXE` letters in the startup banner using ANSI SGR sequences (Red, Green, Blue, Yellow), then reset attributes for the remainder of the banner text.

---

## [0.08] - 2026-05-01

### Fixed
- On a failed FujiNet connection, pressing Return now returns to the device selection prompt instead of quitting to DOS.
- Device selection screen clears the display and homes the cursor before printing the banner.
- Fixed bug where selecting R: serial after a failed N: FujiNet attempt caused key presses to be ignored (`device_type` was not reset to 0).

### Changed
- Q=Quit option removed from device selection prompt.

---

## [0.03] - 2026-04-22

### Added
- Startup device selection between Atari R: serial I/O and FujiNet N: URLs.
- FujiNet N: open, status, read, and write handling based on the netcat-asm SIO path.

### Changed
- The startup flow now prompts for the FujiNet URL when N: is selected and keeps the existing R: path intact.

---

## [0.02] - 2026-04-07

### Changed
- Relaxed VBXE FX core detection so the terminal accepts FX-compatible firmware revisions instead of requiring a strict 1.2x minor revision match.
- Clarified XDL address initialization by assigning the low, middle, and high bytes explicitly during VBXE setup.

### Fixed
- Corrected palette initialization so `csel` advances while loading both foreground and background color entries into the VBXE palette.

---

## [0.01] - 2015-04-07

### Added
- Version number embedded in the main source file as human-readable data in compiled form.

### Fixed
- VBXE memory window no longer conflicts with extended memory. Window moved to `$A000–$AFFF`. This overlaps the cartridge area, but cartridges have priority over the VBXE memory window, so it works correctly as long as no cartridge is present.

---

## [0.00] - 2015-04-06

Initial release.

### Added
- ANSI/ECMA-48 C0 control function set support.
- ANSI C1 control function set support.
- ANSI SGR (Set Graphics Rendition) control sequence support.
- Basic control sequence handling mechanism.

### Known Bugs
- Init routine left the VBXE memory window open, overlapping the banking window for banked RAM. This caused incompatibility with SpartaDOS X on machines with extended RAM.
