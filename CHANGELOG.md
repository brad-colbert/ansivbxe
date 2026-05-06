# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Version numbers follow the format `x.zz.yyyy.mm.dd` where `x` is incremented for major new features and `zz` for bugfixes and minor features.

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
- OS SIO bus sound (`SOUNDR`) is silenced for the duration of the session and restored on exit, so the per-byte click/whine no longer plays during FujiNet traffic.

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
