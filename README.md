# ANSI VBXE Terminal Emulator

An Atari 8-bit terminal emulator that supports ANSI/ECMA-48 control sequences and a 256-character IBM PC font, using the VBXE (Video Board XE) graphics expansion.

**Written by:** Joseph Zatarski
**Updated by:** Brad Colbert

---

## Features

- Full **ANSI/ECMA-48 C0 and C1 control function** set support
- **ANSI SGR** (Set Graphics Rendition) — colors, bold, inverse, etc.
- 256-character IBM CGA-style font via VBXE text mode
- Editable ANSI color palette (16 colors: 8 standard + 8 high-intensity)
- Serial communication via Atari R: device (850 interface or compatible)
- Concurrent I/O for non-blocking receive

## Requirements

- Atari 8-bit computer (800XL, 130XE, etc.)
- **VBXE (Video Board XE)** with FX core
- Atari 850 interface (or compatible) for R: device serial I/O
- DOS with `CIOV` support (e.g., SpartaDOS X, MyDOS)

## Files

| File | Description |
|------|-------------|
| `ANSIVBXE.asm` | Main source code (MADS assembler, ORG'd at `$2800`) |
| `ANSIVBXE.XEX` | Compiled binary |
| `ANSIVBXE.ATR` | ATR disk image with DOS and the terminal (set as D1:) |
| `IBMPC.FNT` | 256-character IBM PC CGA font for the terminal |
| `first.fnt` | First 128 characters of `IBMPC.FNT` |
| `second.fnt` | Second 128 characters of `IBMPC.FNT` |
| `ANSI.PAL` | ANSI color palette — 16 colors as 3-byte RGB entries |
| `VBXE.equ` | VBXE hardware equates |
| `atarihardware.equ` | General Atari hardware equates |
| `atarios.equ` | Atari OS equates |
| `changelog.txt` | Version history, features, and known bugs |
| `license.txt` | License terms |

## Building

The source is written for the **[MADS assembler](http://mads.atari8.info/)**.

```
mads ANSIVBXE.asm
```

The code is ORG'd at `$2800`. It is not relocatable, but the base address can be changed by modifying the `ORG` statements in the source.

## Usage

1. Set `ANSIVBXE.ATR` as `D1:` in your emulator or write it to a real disk.
2. Boot the disk. The terminal will start automatically.
3. The `TEST.ANS` file on the disk can be modified to display different ANSI art/text.
4. Connect via the R: device (default: 9600 baud, 8 data bits).

## Font

The IBM PC CGA font was recreated as two 128-character halves (`first.fnt`, `second.fnt`) using an Atari 8-bit font editor, then concatenated into the full 256-character `IBMPC.FNT`. Characters are 8×8 pixels, matching VBXE's native text mode cell size. The CGA font was chosen because many ANSI BBS systems relied on IBM extended graphics characters.

## Palette

`ANSI.PAL` contains 16 RGB color entries (3 bytes each, 48 bytes total):
- **Bytes 0–23:** 8 standard (low-intensity) ANSI colors
- **Bytes 24–47:** 8 high-intensity ANSI colors

The palette is file-based (not hardcoded) to allow customization — notably to reproduce the CGA brown (`#AA5500`) used by many ANSI BBS systems in place of dark yellow.

## Changelog

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
