BLCSETD - DPMI-compatible ThinkPad T430 brightness setter
=============================================================

Purpose
-------
BLCSETD is the DPMI-compatible analogue of BLCSET.

Use BLCSET when direct real-mode/protected-mode switching is available.
Use BLCSETD in a DPMI environment such as the JEMM386/HDPMI32 configuration
used by ASPECTD.

BLCINIT is unchanged and remains suitable for CONFIG.SYS use before a memory
manager is loaded.

Usage
-----
    BLCSETD <hex-duty>

Examples:
    BLCSETD 0045
    BLCSETD 01E7
    BLCSETD 1155

Behavior
--------
BLCSETD preserves BLCSET's verified PWM behavior:

- BAR0 is discovered through PCI BIOS.
- BAR0+48250h is read for CPU PWM control state.
- BAR0+48254h is read for the current CPU PWM duty register.
- BAR0+C8254h is read and its upper 16 bits are used as the maximum duty.
- The requested duty is clamped to that maximum.
- Only BAR0+48254h is written.
- Its upper 16 bits are preserved.
- The low 16-bit duty is read back and verified.

DPMI implementation
-------------------
BLCSETD enters as a 32-bit DPMI client and maps only two 4 KiB physical pages:

    BAR0+48000h
    BAR0+C8000h

It accesses those mappings through DPMI selectors and releases both selectors
and both mappings before terminating.

The implementation follows the DPMI path already verified by ASPECTD with
JEMM386/HDPMI32.

Build
-----
From TOOLS\BRIGHT\BLCSETD:

    TASM /M9 /I..\..\..\INCL BLCSETD.ASM
    TLINK /t BLCSETD.OBJ

All source/build filenames are DOS 8.3 compatible.
