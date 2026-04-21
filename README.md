# ANSI VBXE Terminal Emulator

An Atari 8-bit terminal emulator that supports ANSI/ECMA-48 control sequences and a 256-character IBM PC font, using the VBXE (Video Board XE) graphics expansion. Renders ANSI art and interacts with BBS systems over serial.

**Converted to CA65 and updated by:** Brad Colbert
**Original MADS by:** Joseph Zatarski

---

## Features

- 80×24 text display via VBXE overlay text mode
- 256-character IBM CGA-style font
- Editable ANSI color palette (16 colors: 8 standard + 8 high-intensity)
- Serial communication via Atari R: device (850 interface or compatible)
- Concurrent I/O for non-blocking receive
- Keyboard input with auto-repeat via custom IRQ handler

### Supported ANSI/ECMA-48 Sequences

| Sequence | Code | Description |
|----------|------|-------------|
| C0 control set | `$00`–`$1F` | NUL, BEL, BS, LF, VT, FF, CR, ESC, etc. |
| C1 control set | ESC + `$40`–`$5F` | IND, NEL, CSI, and others |
| SGR | `ESC[…m` | Set Graphics Rendition — foreground/background color, bold, blink (as bold), inverse, default, normal intensity, inverse off |
| CUF | `ESC[nC` | Cursor Forward (right) by _n_ columns (default 1) |
| CUB | `ESC[nD` | Cursor Back (left) by _n_ columns (default 1) |
| CUU | `ESC[nA` | Cursor Up by _n_ rows (default 1) |
| CUD | `ESC[nB` | Cursor Down by _n_ rows (default 1) |
| CUP | `ESC[r;cH` | Cursor Position — move to row _r_, column _c_ (1-based, default 1;1) |
| HVP | `ESC[r;cf` | Horizontal and Vertical Position — alias for CUP |
| CNL | `ESC[nE` | Cursor Next Line — move to beginning of line _n_ lines down (default 1) |
| CPL | `ESC[nF` | Cursor Previous Line — move to beginning of line _n_ lines up (default 1) |
| CHA | `ESC[nG` | Cursor Horizontal Absolute — move to column _n_ (1-based, default 1) |
| ED | `ESC[nJ` | Erase in Display — mode 0 (cursor to end), mode 1 (start to cursor), mode 2 (entire screen) |
| EL | `ESC[nK` | Erase in Line — mode 0 (cursor to EOL), mode 1 (start to cursor), mode 2 (entire line) |
| SCP | `ESC[s` | Save Cursor Position |
| RCP | `ESC[u` | Restore Cursor Position |
| SU | `ESC[nS` | Scroll Up by _n_ lines (default 1) |
| SD | `ESC[nT` | Scroll Down (stub — recognized but not yet implemented) |

## Requirements

- Atari 8-bit computer (800XL, 130XE, etc.)
- **VBXE (Video Board XE)** with FX core
- Atari 850 interface (or compatible) for R: device serial I/O
- DOS with `CIOV` support (e.g., SpartaDOS X, MyDOS)

### Build tools

- **[ca65/ld65](https://cc65.github.io/doc/ca65.html)** (cc65 suite) — primary assembler/linker for the CA65 source
- **[MADS assembler](http://mads.atari8.info/)** — for building the original MADS source
- **dir2atr** — for creating bootable ATR disk images

## Files

| File | Description |
|------|-------------|
| `ANSIVBXE_ca65.asm` | Main source code (ca65 assembler) |
| `ANSIVBXE.asm` | Original MADS assembler source |
| `atarios_ca65.inc` | Atari OS equates (ca65) |
| `atarihardware_ca65.inc` | General Atari hardware equates (ca65) |
| `VBXE_ca65.inc` | VBXE hardware equates (ca65) |
| `atarios.equ` | Atari OS equates (MADS) |
| `atarihardware.equ` | General Atari hardware equates (MADS) |
| `VBXE.equ` | VBXE hardware equates (MADS) |
| `IBMPC.FNT` | 256-character IBM PC CGA font for the terminal |
| `first.fnt` | First 128 characters of `IBMPC.FNT` |
| `second.fnt` | Second 128 characters of `IBMPC.FNT` |
| `ANSI.PAL` | ANSI color palette — 16 colors as 3-byte RGB entries |
| `Makefile` | Build rules for both ca65 and MADS targets |
| `CHANGELOG.md` | Version history, features, and known bugs |
| `license.txt` | License terms |

## Building

The `Makefile` supports both the **ca65** (cc65 suite) and **MADS** assemblers.

Build both targets:

```sh
make all
```

Build only the ca65 version:

```sh
make ca65
```

Build only the MADS version:

```sh
make mads
```

Build bootable ATR disk images:

```sh
make disk
```

Clean build artifacts:

```sh
make clean
```

The code is ORG'd at `$2800`. It is not relocatable, but the base address can be changed by modifying the `ORG`/`.org` statement in the source (or setting `START_ADDR` for the ca65 build).

## Usage

1. Set `ANSIVBXE_ca65.ATR` (or `ANSIVBXE.ATR`) as `D1:` in your emulator or write it to a real disk.
2. Boot the disk. The terminal will start automatically.
3. Connect via the R: device (default: 9600 baud, 8 data bits, no parity).
4. The `TEST.ANS` file on the disk can be used to test ANSI art rendering.

## Font

The IBM PC CGA font was recreated as two 128-character halves (`first.fnt`, `second.fnt`) using an Atari 8-bit font editor, then concatenated into the full 256-character `IBMPC.FNT`. Characters are 8×8 pixels, matching VBXE's native text mode cell size. The CGA font was chosen because many ANSI BBS systems relied on IBM extended graphics characters.

## Palette

`ANSI.PAL` contains 16 RGB color entries (3 bytes each, 48 bytes total):
- **Bytes 0–23:** 8 standard (low-intensity) ANSI colors
- **Bytes 24–47:** 8 high-intensity ANSI colors

The palette is file-based (not hardcoded) to allow customization — notably to reproduce the CGA brown (`#AA5500`) used by many ANSI BBS systems in place of dark yellow.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the full release history.

### v0.02 — 2026-04-07
- Relaxed VBXE FX core detection to accept FX-compatible firmware revisions instead of requiring a strict 1.2x minor revision match
- Clarified XDL address initialization by assigning the low, middle, and high bytes explicitly during VBXE setup
- Corrected palette initialization so `csel` advances while loading both foreground and background palette entries

### v0.01 — 2015-04-07
- VBXE memory window moved to `$A000–$AFFF` to avoid conflict with extended RAM (SDX fix)
- Version number embedded in compiled binary as human-readable data

### v0.00 — 2015-04-06
- Initial release
- C0/C1 control function set support
- SGR control sequence support and basic control sequence handling

## License

See [license.txt](license.txt) for full terms. In short:

- Free to use and distribute
- May be sold only if the buyer is informed it is also available for free and agrees to pay anyway
- Derivative works must retain license notices and credit original authors
