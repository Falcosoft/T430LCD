# T430LCD User Guide

## 1. Introduction

T430LCD addresses two practical Lenovo ThinkPad T430 problems under real MS-DOS:

1. restoring a preferred LCD brightness automatically at boot
2. preventing legacy 4:3 DOS modes from being stretched across the internal widescreen LCD

The utilities communicate directly with Intel HD Graphics 4000 hardware. The primary development and validation platform is a physical ThinkPad T430.

T430LCD provides two MMIO access paths:

- `BLCSET` and `ASPECT` use the direct plain-DOS protected-mode backend.
- `BLCSETD` and `ASPECTD` use a 32-bit DPMI host and are intended for memory-manager environments such as the tested JEMM386/HDPMI32 configuration.

`BLCINIT` runs during CONFIG.SYS processing and is intended to set brightness before a memory manager is loaded.

## 2. Requirements

### Verified hardware

Primary verified platform:

- Lenovo ThinkPad T430
- Intel HD Graphics 4000
- internal 1600×900 LCD
- external analog VGA output
- external digital/DVI output

Additional Ivy Bridge/Intel HD Graphics 4000 laptops have also been reported working, but their exact models and detailed test results are not yet documented here.

### Software

Required for the direct plain-DOS tools:

- real MS-DOS
- HIMEM/XMS
- no active EMM386/JEMM386 virtual-8086 environment while running `BLCSET` or `ASPECT`

Required for the DPMI tools:

- real MS-DOS
- a 32-bit DPMI host
- the verified memory-manager configuration uses JEMM386/JEMMEX with resident HDPMI32

Borland TASM/TLINK are required only when building from source.

Not currently supported:

- Windows DOS boxes or NTVDM
- emulators without compatible physical Intel hardware access

Recommended plain-DOS baseline:

```ini
DEVICE=C:\DOS\HIMEM.SYS
DOS=HIGH
```

## 3. Installation layout

A convenient layout is:

```text
C:\T430LCD\
    BLCSET.COM
    BLCSETD.COM
    BLCINIT.SYS
    ASPECT.COM
    ASPECTD.COM
```

You only need the variants appropriate for the configuration you actually use.

Diagnostics may be kept in:

```text
C:\T430LCD\DIAG\
    FITREAD.COM
    PFDIAG.COM
    PFSNAP.COM
```

## 4. Brightness control

### BLCSET

`BLCSET` is the interactive brightness utility for plain DOS.

Syntax:

```dos
BLCSET hexadecimal-value
```

Example:

```dos
BLCSET 0800
```

The value is hexadecimal. The primary tested T430 reported a maximum of `1155h`.

Example values:

```dos
BLCSET 0040
BLCSET 0400
BLCSET 0800
BLCSET 1155
```

BLCSET locates Intel BAR0, detects the maximum PWM value, clamps the request, writes the active duty register, and verifies the readback.

Do not run BLCSET from an EMM386/JEMM386 virtual-8086 environment because its direct CR0/LGDT protected-mode transition is intentionally a plain-DOS path.

### BLCSETD

`BLCSETD` provides the same interactive PWM duty control through DPMI.

Syntax:

```dos
BLCSETD hexadecimal-value
```

Examples:

```dos
BLCSETD 0040
BLCSETD 0800
BLCSETD 1155
```

BLCSETD preserves BLCSET's verified hardware policy:

- BAR0 is discovered through PCI BIOS.
- `BAR0+48250h` is read for CPU PWM control state.
- `BAR0+48254h` is read for the current duty.
- the upper 16 bits of `BAR0+C8254h` provide the detected maximum.
- the requested duty is clamped to that maximum.
- only `BAR0+48254h` is written.
- its upper 16 bits are preserved.
- the low 16-bit duty is read back and verified.

BLCSETD maps only the two 4 KiB MMIO pages required by the brightness path and releases its DPMI selectors and mappings before terminating.

BLCSETD has been verified with JEMM386/HDPMI32 on the ThinkPad T430.

## 5. BLCINIT

### CONFIG.SYS syntax

```ini
DEVICE=C:\T430LCD\BLCINIT.SYS hexadecimal-value
```

Example:

```ini
DEVICE=C:\DOS\HIMEM.SYS
DEVICE=C:\T430LCD\BLCINIT.SYS 0800
```

BLCINIT sets brightness once during boot and then finishes initialization. It avoids repeatedly pressing the ThinkPad brightness hotkey, which may conflict with application shortcuts such as Norton Commander file-order controls.

BLCINIT is normally loaded before EMM386/JEMM386, so no DPMI-specific BLCINIT variant is needed.

## 6. ASPECT

### Install

```dos
ASPECT
```

ASPECT is the real-mode TSR for plain DOS.

### Deactivate without unloading

```dos
ASPECT /D
```

`/D` disables future aspect-ratio correction while leaving the TSR resident. If the current `PF_A_POS` and `PF_A_SIZE` exactly match ASPECT's own applied 4:3 state, ASPECT restores the installation-time fitter position and size. If the current fitter state belongs to another BIOS/output state, it is left untouched.

### Re-enable

```dos
ASPECT /E
```

`/E` re-enables correction. If the current fitter size matches the installation-time fixed raster, correction is applied immediately. Otherwise ASPECT waits for a later BIOS mode set that restores the compatible fitter size.

### Physical unload

```dos
ASPECT /U
```

`/U` remains the true physical unload command.

ASPECT unloads only when it is still the newest handler on both `INT 10h` and `INT 2Fh`. If another TSR hooked either interrupt afterward, ASPECT refuses to unload to avoid breaking the chain.

### AUTOEXEC.BAT example

```bat
@ECHO OFF
C:\T430LCD\ASPECT.COM
PATH C:\DOS;C:\UTIL
```

### Internal LCD

On the verified 1600×900 panel:

```text
native fitter destination: 1600×900
calculated 4:3 window:      1200×900
position:                   200,0
```

### External analog VGA

The BIOS generates mode-specific output timings, for example 720×400 text and 640×480 for mode 13h. ASPECT detects the changing destination and leaves it unchanged.

### External DVI

The tested DVI path already uses a 640×480 destination for legacy graphics modes. Since this is 4:3, ASPECT does not install a correction hook.

### Native VESA modes

A VESA mode matching the detected output dimensions remains full-screen.

### Mode changes watched

```text
INT 10h AH=00h
INT 10h AX=4F02h
```

### Decision logic

At installation:

```text
read PF_A_SIZE

if destination is 4:3:
    do not install
else:
    save widescreen destination
    calculate centered 4:3 window
    install TSR
```

After each watched mode change:

```text
if native VESA mode:
    do nothing
else if current PF_A_SIZE equals saved widescreen size:
    apply the calculated 4:3 window
else:
    leave BIOS programming untouched
```

ASPECT writes only `PF_A_POS` followed by `PF_A_SIZE`. It never rewrites `PF_A_CTL`, `PF_A_VSCALE`, or `PF_A_HSCALE`.

## 7. ASPECTD

ASPECTD is the DPMI counterpart of ASPECT for systems using a resident 32-bit DPMI host.

### Install or show state

```dos
ASPECTD
```

### Deactivate

```dos
ASPECTD /D
```

or:

```dos
ASPECTD /U
```

For ASPECTD, `/U` and `/D` are logical deactivation commands. The DPMI client and interrupt hooks remain resident; there is no physical unload path.

If the current fitter state is exactly ASPECTD's own applied 4:3 state, the original fitter state is restored. Otherwise the current BIOS/output state is left untouched.

### Re-enable

```dos
ASPECTD /E
```

If the current fitter size matches the installation-time fixed raster, correction is reapplied immediately. Otherwise ASPECTD waits for a later compatible BIOS mode set.

ASPECTD uses a DPMI real-mode callback to perform protected MMIO correction after the original BIOS `INT 10h` handler has completed. It preserves the same conservative fixed-raster test and native-VESA exception as ASPECT.

A fitter write/readback failure permanently disables further ASPECTD writes until reboot.

## 8. Memory managers and DPMI

### Plain-DOS backend

`BLCSET` and `ASPECT` use a direct protected-mode transition:

- A20 is controlled through XMS.
- a runtime GDT is installed.
- the program enters 16-bit protected mode.
- a flat selector accesses graphics MMIO.
- the program returns to real mode.

This path must not be entered from EMM386/JEMM386 virtual-8086 mode.

### DPMI backend

`BLCSETD` and `ASPECTD` avoid direct CR0/LGDT switching and use DPMI physical-memory mapping and selectors instead.

The ASPECTD development path was verified with a configuration of this form:

```dos
JEMMEX.EXE
HDPMI32.EXE -R
JEMMEX.EXE NOVCPI
VSBHDA.EXE
ASPECTD
```

The important points are that HDPMI32 is made resident before VCPI is disabled and that ASPECTD uses the resident DPMI host. BLCSETD can then use the same DPMI environment for one-shot brightness changes.

DPMI was preferred over a VCPI-only design because compatibility with VSBHDA was an explicit project goal.

## 9. Diagnostics

### FITREAD

Reads Intel OpRegion panel-fitting fields.

### PFDIAG

Reads all three Ivy Bridge panel-fitter blocks.

### PFSNAP

Install:

```dos
PFSNAP /I
```

Clear:

```dos
PFSNAP /C
```

Run a graphics program, return to DOS, then dump:

```dos
PFSNAP /D
```

PFSNAP records requested BIOS modes, before/after state, fitter A/B/C registers, pipe timing registers, source sizes, and skipped VM86 captures.

## 10. Troubleshooting

### Immediate reboot or protection fault

With the current verified builds, an immediate reboot should not be expected.

For the direct tools, first check that EMM386/JEMM386 is not active and that you are using the final hardware-verified source. The direct CR0/LGDT transition is a plain-DOS path.

For a memory-manager configuration, use `BLCSETD` or `ASPECTD` with a resident 32-bit DPMI host instead of the direct variants.

Unsupported hardware or an obsolete experimental build can also cause failures.

### BLCSETD or ASPECTD reports no DPMI host

Load a supported 32-bit DPMI host first. The verified configuration uses resident HDPMI32.

### ASPECT reports that output is already 4:3

This is expected for external outputs where the BIOS already generates a correct legacy timing. No correction TSR is needed.

### External display becomes garbled

Use only the conservative final ASPECT/ASPECTD builds. Older experimental builds applied startup-derived window sizes unconditionally and could corrupt mode-dependent external outputs.

### ASPECT /U refuses to unload

Another TSR owns `INT 10h` or `INT 2Fh` after ASPECT. Unload the later TSR first or reboot.

### ASPECTD /U does not remove the TSR

This is expected. ASPECTD `/U` is a logical deactivation command, equivalent to `/D`; the DPMI client remains resident.

### XMS MMIO test returns repeatable garbage

XMS function `0Bh` handle-zero offsets are packed real-mode far pointers, not arbitrary 32-bit physical addresses. This mechanism cannot access MMIO near `F0000000h`.

## 11. Tested software

Confirmed during development on the primary T430 include:

Plain-DOS ASPECT:

- MS-DOS text mode
- standard VGA programs
- Duke Nukem 3D
- Descent

DPMI ASPECTD with JEMM386/HDPMI32:

- Duke Nukem 3D
- DOOM

Other confirmed use:

- Norton Commander coexistence with boot-time brightness initialization
- BLCSETD brightness adjustment with JEMM386/HDPMI32

## 12. Reporting results

Include:

```text
Computer model:
CPU:
Integrated GPU:
Internal panel resolution:
Connection type:
DOS version:
HIMEM version:
EMM386/JEMM386 configuration:
DPMI host and version:
Utility and command:
Exact output:
Visible result:
```

For diagnostic reports, include complete output rather than selected lines.

## 13. License and attribution

T430LCD is licensed under the MIT License.

Zoltán Bacskó performed hardware investigation, compilation, testing, validation, and maintenance. OpenAI ChatGPT generated and refined implementation code, debugging analysis, refactoring, and documentation. Supported behavior is based on physical-hardware testing rather than emulator-only assumptions.
