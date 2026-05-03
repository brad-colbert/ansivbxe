# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Version numbers follow the format `x.zz.yyyy.mm.dd` where `x` is incremented for major new features and `zz` for bugfixes and minor features.

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
