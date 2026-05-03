# VBXETERM

An Atari 8-bit terminal emulator that supports ANSI/ECMA-48 control sequences and a 256-character IBM PC font, using the VBXE (Video Board XE) graphics expansion. Renders ANSI art and connects to BBS systems and SSH hosts over serial (R:) or FujiNet (N:).

**Converted to CA65 and updated by:** Brad Colbert  
**Original MADS by:** Joseph Zatarski  
**Version:** v0.11  

<img width="608" height="172" alt="image" src="https://github.com/user-attachments/assets/84c7b30e-c9b0-4522-83ff-6d2b81787d69" />

---

## Features

- 80×24 text display via VBXE overlay text mode
- 256-character IBM CGA-style font
- Editable ANSI color palette (16 colors: 8 standard + 8 high-intensity)
- LF-as-CRLF mode enabled by default (compatible with most remote hosts)
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

### Supported ANSI/ECMA-48 Sequences

#### C0 Controls

| Code | Name | Description |
|------|------|-------------|
| `$00` | NUL | No operation |
| `$07` | BEL | Bell (ignored) |
| `$08` | BS | Backspace — move cursor left |
| `$09` | HT | Horizontal Tab (stub — no-op) |
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
| `ESC[nS` | SU | Scroll Up _n_ lines (default 1) |
| `ESC[nT` | SD | Scroll Down (stub — recognized, not yet implemented) |
| `ESC[s` | SCP | Save Cursor Position |
| `ESC[u` | RCP | Restore Cursor Position |
| `ESC[…m` | SGR | Set Graphics Rendition (see below) |

**Silently ignored CSI sequences** (recognized to avoid display garbage):
`ESC[c` (DA), `ESC[n` (DSR), `ESC[t` (window ops), `ESC[!p` (soft reset), `ESC[!_` (DECSTR)

#### SGR Parameters (`ESC[…m`)

| Parameter | Effect |
|-----------|--------|
| 0 | Reset all — white on black, normal intensity |
| 1 | Bold / high intensity |
| 2 | Normal intensity |
| 5 | Blink (rendered as bold/high intensity) |
| 7 | Inverse video |
| 27 | Inverse off |
| 30–37 | Foreground color (standard) |
| 40–47 | Background color (standard) |
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

---

## Files

| File | Description |
|------|-------------|
| `ANSIVBXE_ca65.asm` | Main source (ca65 assembler) |
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

---

## Palette

`ANSI.PAL` contains 16 RGB color entries (3 bytes each, 48 bytes total):
- **Bytes 0–23:** 8 standard (low-intensity) ANSI colors
- **Bytes 24–47:** 8 high-intensity ANSI colors

The palette is file-based (not hardcoded) to allow customization — notably to reproduce the CGA brown (`#AA5500`) used by many ANSI BBS systems.

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the full release history.

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
