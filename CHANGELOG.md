# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Version numbers follow the format `x.zz.yyyy.mm.dd` where `x` is incremented for major new features and `zz` for bugfixes and minor features.

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
