/*
 * vbxe_lib.h — C header for vbxe_lib (cc65 / Atari 8-bit)
 *
 * Include this file in any C translation unit that calls the VBXE library.
 * All four functions use the cc65 __fastcall__ convention.
 *
 * Typical call sequence:
 *
 *   static const char font_path[] = "D:IBMPC.FNT\x9B";
 *   static const char pal_path[]  = "D:ANSI.PAL\x9B";
 *
 *   extern char xdl_data[];          // defined in your .asm file
 *   extern int  xdl_size;            // = bcb_end - xdl (computed in .asm)
 *
 *   vbxe_load_cfg_t cfg = { font_path, pal_path, xdl_data, (unsigned)xdl_size };
 *
 *   if (!vbxe_init())               { /* no VBXE — handle error * / }
 *   vbxe_clear_ram();               // optional: zero all VBXE RAM before loading
 *   if (!vbxe_load_files(&cfg))     { /* I/O error — handle * / }
 *   ...
 *   vbxe_shutdown();                // before returning to DOS
 */

#ifndef VBXE_LIB_H
#define VBXE_LIB_H

/*
 * vbxe_load_cfg_t — configuration passed to vbxe_load_files().
 *
 * font_path and pal_path must be null-terminated Atari device+path strings
 * with the Atari EOL byte ($9B) as the terminator, e.g. "D:IBMPC.FNT\x9B".
 *
 * xdl_data points to the XDL + BCB block that resides in the caller's own
 * memory (typically defined in the assembly source alongside scroll_1d_color
 * and clr_scr_color labels).  xdl_size is the byte count of that block
 * (= bcb_end - xdl in assembly terms).
 */
typedef struct {
    const char   *font_path;   /* e.g. "D:IBMPC.FNT\x9B"              */
    const char   *pal_path;    /* e.g. "D:ANSI.PAL\x9B"               */
    const void   *xdl_data;    /* pointer to XDL + BCB block in RAM    */
    unsigned int  xdl_size;    /* byte count of XDL + BCB block        */
} vbxe_load_cfg_t;

/*
 * vbxe_init — detect the VBXE FX core, save SDMCTL, and open the MEMAC A
 * window as a 4 K CPU-accessible window at $A000 pointing to VBXE bank 0.
 *
 * Returns 1 on success, 0 if no VBXE is present or the core version is
 * below $10 (not an FX-compatible core).
 *
 * Must be called before any other vbxe_* function.
 */
int __fastcall__ vbxe_init(void);

/*
 * vbxe_load_files — load font and palette from disk, program the VBXE
 * palette registers, copy the XDL + BCB block to VBXE RAM at $0800,
 * enable the XDL display, switch the MEMAC window to display RAM, and
 * zero the screen buffer.
 *
 * cfg must point to a fully populated vbxe_load_cfg_t.
 * Uses IOCB 1.  Requires _vbxe_init to have been called first.
 *
 * Returns 1 on success, 0 on any CIO I/O error.
 */
int __fastcall__ vbxe_load_files(vbxe_load_cfg_t *cfg);

/*
 * vbxe_shutdown — disable the VBXE overlay, close the MEMAC window, and
 * restore SDMCTL to the value saved by vbxe_init().
 *
 * Patches the XDL's first OVOFF entry to cover all visible scanlines so
 * nothing is rendered before MEMAC is closed.  Assumes the XDL was loaded
 * by vbxe_load_files() and resides at VBXE $0800.
 */
void __fastcall__ vbxe_shutdown(void);

/*
 * vbxe_clear_ram — zero-fill all 512 K of VBXE RAM using four chained
 * blitter control blocks.  Blocks until the blitter operation completes.
 *
 * Normally called once after vbxe_init() and before vbxe_load_files() to
 * ensure a clean slate in VBXE RAM.
 */
void __fastcall__ vbxe_clear_ram(void);

#endif /* VBXE_LIB_H */
