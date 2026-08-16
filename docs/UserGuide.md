# T430LCD User Guide

## 1. Introduction

T430LCD addresses practical LCD/display problems under real DOS on physical Intel hardware:

1. restoring a preferred LCD brightness automatically at boot
2. preventing legacy 4:3 DOS modes from being stretched across a widescreen LCD
3. providing a pixel-perfect centered display mode for users who prefer the active source raster without additional fitter scaling

The primary development and validation platform is a physical Lenovo ThinkPad T430 with Intel HD Graphics 4000.

T430LCD v2.4 gives ASPECT and ASPECTD four explicit display policies:

- `/A` — centered 4:3 aspect-ratio correction using Intel Medium 3×3 filtering
- `/AS` — the same centered 4:3 geometry using the FIR-91 sharp programmable filter
- `/S` — FIR-91 sharp filtering only, preserving the current fitter geometry
- `/C` — pixel-perfect centered mode based on the active Intel display-pipe source raster

With no argument, ASPECT and ASPECTD retain the historical behavior and use `/A`.

The utilities use two MMIO access paths:

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

The complete T430LCD utility set has also been confirmed working on:

- Lenovo IdeaPad Yoga 13 — Intel Core i5-3427U / Intel HD Graphics 4000 — internal 1600×900 LCD
- HP EliteBook Folio 9470m — Intel Core i5-3427U / Intel HD Graphics 4000 — internal 1366×768 LCD

ASPECT has additionally been confirmed on:

- Dell Inspiron E5550 — Intel HD Graphics 5500 (Broadwell) — internal 1920×1080 LCD — ASPECT confirmed; BLCSET does not work

These are community hardware confirmations. The Yoga 13 and EliteBook reports cover the complete utility set. The Dell Broadwell report is ASPECT-specific and should not be interpreted as brightness support because BLCSET was reported not to work. The detailed v2.3 `/C` regression matrix is from the primary ThinkPad T430.

Confirmed `/A` geometry includes:

| System | Fixed-raster destination | Corrected 4:3 window | Position |
|--------|--------------------------|----------------------|----------|
| ThinkPad T430 | 1600×900 | 1200×900 | X=200, Y=0 |
| IdeaPad Yoga 13 | 1600×900 | 1200×900 | X=200, Y=0 |
| EliteBook Folio 9470m | 1366×768 | 1024×768 | X=171, Y=0 |
| Dell Inspiron E5550 / Intel HD 5500 | 1920×1080 | 1440×1080 | X=240, Y=0 |

### Software

Required for the direct plain-DOS tools:

- real DOS on physical hardware
- HIMEM/XMS
- no active EMM386/JEMM386 virtual-8086 environment while running `BLCSET` or `ASPECT`

Required for the DPMI tools:

- real DOS on physical hardware
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

BLCSET is not a generic Intel-generation brightness utility. In particular, it was reported not to work on the Broadwell Dell Inspiron E5550 / Intel HD Graphics 5500 system on which ASPECT itself does work.

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

ASPECT is the real-mode TSR for plain DOS.

### Install with the default aspect policy

```dos
ASPECT
```

No argument is equivalent to selecting `/A` at installation.

### Select aspect-ratio correction

```dos
ASPECT /A
```

`/A` selects the existing centered 4:3 correction algorithm. When ASPECT is already resident, `/A` switches the current policy back to aspect correction.

For a fixed-raster 1600×900 destination the calculated target is 1200×900 at X=200,Y=0. For 1366×768 it is 1024×768 at X=171,Y=0. A community Broadwell report confirms the same dynamic calculation on a 1920×1080 Dell Inspiron E5550 / Intel HD 5500, producing 1440×1080 at X=240,Y=0.

Like v2.3, v2.4 has no native-resolution VBE bypass. A successful native VBE mode is treated like any other compatible mode. Therefore a native 1600×900 VBE mode can be shown as 1200×900 centered when `/A` is selected.

### Select sharp 4:3 aspect correction

```dos
ASPECT /AS
```

`/AS` uses the same dynamic centered 4:3 target geometry as `/A`, but programs the hardware-verified Ivy Bridge PF0 coefficient tables with the FIR-91 kernel and selects the programmable-filter mode. FIR-91 is a symmetric 3-tap kernel using approximately 4.4921875% / 91.015625% / 4.4921875% for every phase. The result is visibly sharper than the normal Intel Medium 3×3 filter while retaining the same aspect-corrected window size and position.

### Select sharp filtering without changing geometry

```dos
ASPECT /S
```

`/S` programs the same FIR-91 filter but preserves the current `PF_A_POS` and `PF_A_SIZE`. This is useful when the BIOS or another display path has already chosen the desired geometry and only the scaling filter should change. The current size is rewritten unchanged only to latch the filter change.

Leaving `/AS` or `/S` for `/A`, `/C`, `/D` or `/U` restores the Intel Medium 3×3 filter. Filter/coefficient writes are verified by readback; a failure safety-locks further writes.

### Select pixel-perfect centered mode

```dos
ASPECT /C
```

`/C` selects pixel-perfect centered mode. For a compatible fixed-raster output, ASPECT reads Pipe A `PIPESRC` at `BAR0+6001Ch`, decodes the source dimensions and centers that raster directly inside the detected fitter destination:

```text
source width  = upper 16 bits + 1
source height = lower 16 bits + 1
X = (fixed width  - source width)  / 2
Y = (fixed height - source height) / 2
```

No extra even rounding is applied in `/C`. If one unused pixel remains because of an odd difference, it is left on the right or bottom side so that the source dimensions remain exact.

Examples on the 1600×900 T430 fixed-raster panel are:

| Source raster | `/C` target | Position |
|---------------|-------------|----------|
| 720×400 | 720×400 | X=440, Y=250 |
| 640×400 | 640×400 | X=480, Y=250 |
| 640×480 | 640×480 | X=480, Y=210 |
| 800×600 | 800×600 | X=400, Y=150 |
| 1024×768 | 1024×768 | X=288, Y=66 |
| 1600×900 | 1600×900 | X=0, Y=0 |

The native 1600×900 case therefore becomes naturally pixel-perfect/full-screen in `/C`; no native-VBE special case is required.

### Legacy CGA/EGA 320-wide exception

Hardware testing found one deliberately narrow exception to direct `PIPESRC` centering. Standard BIOS modes:

```text
04h  CGA 320×200 4-color
05h  CGA 320×200 4-color
0Dh  EGA 320×200 16-color
```

can reach Pipe A in a 320×400 form where vertical doubling is already present but the horizontal doubling needed for correct centered display is absent.

For those BIOS mode numbers only, and only when `PIPESRC` decodes to exactly 320×400, `/C` changes the target to 640×400. Only the width is doubled. The same guarded principle is used for 40×25 text modes `00h` and `01h`: if and only if Pipe A reports exactly 360×400, the target becomes 720×400.

This is intentionally not a generic 320-wide rule. Other 320×200 VGA modes worked without it, and a non-standard VGA-register-compatible 320×400×256 Fractint mode also worked correctly and remains untouched. Standard 640×200 and 640×350 legacy modes likewise worked without special handling.

### Short command help

```dos
ASPECT /?
```

The DPMI counterpart accepts `ASPECTD /?` and prints the corresponding short command summary.

### Runtime policy switching

`/A`, `/AS`, `/S` and `/C` can be selected while ASPECT is resident. Immediate application is allowed only when ASPECT can prove that the fitter is either:

- at the saved installation fixed-raster state, or
- exactly at ASPECT's own last-applied position and size.

If neither condition is true, the selected policy is remembered but the current output is not overwritten; ASPECT waits for a later compatible BIOS mode set.

### Deactivate without unloading

```dos
ASPECT /D
```

`/D` disables future correction while leaving the TSR resident. If the current `PF_A_POS` and `PF_A_SIZE` exactly match ASPECT's own last-applied state, ASPECT restores the installation-time fitter position and size. If the current fitter state belongs to another BIOS/output state, it is left untouched.

### Re-enable

```dos
ASPECT /E
```

`/E` re-enables whichever policy (`/A`, `/AS`, `/S` or `/C`) is currently selected. If the current fitter state is compatible, the target is applied immediately; otherwise ASPECT waits for a later compatible mode set.

### Physical unload

```dos
ASPECT /U
```

`/U` is the true physical unload command, but v2.3 first executes the same resident restore/deactivation operation used by `/D` while the MMIO engine and hooks are still available. Only after that operation reports a safe normal result does ASPECT restore interrupt vectors and free its memory.

If the restore/deactivation path reports a fitter verification failure, safety lock, busy state or control-protocol error, `/U` refuses to unload rather than discard a TSR whose display state may be uncertain.

ASPECT still unloads only when it is the newest handler on both `INT 10h` and `INT 2Fh`. If another TSR hooked either interrupt afterward, ASPECT refuses to unload to avoid breaking the chain.

### AUTOEXEC.BAT example

```bat
@ECHO OFF
C:\T430LCD\ASPECT.COM
PATH C:\DOS;C:\UTIL
```

### Fixed-raster safety rule

After a watched BIOS mode change, ASPECT applies the selected policy only when the post-BIOS `PF_A_SIZE` equals the fixed-raster size captured at installation. This avoids disturbing external/mode-timed output paths whose fitter size changes with the mode.

For live `/A`↔`/C` switching, ASPECT also accepts the exact last-applied state as owned state.

For `/A` and `/C`, ASPECT retains the established `PF_A_POS` → `PF_A_SIZE` geometry path. `/AS` and `/S` additionally program the verified PF0 coefficient tables and change only the filter-selector bits of `PF_A_CTL`; unrelated control bits are preserved. `PF_A_VSCALE` and `PF_A_HSCALE` are never modified. Pipe A `PIPESRC` is read only.

### Mode changes watched

```text
INT 10h AH=00h
INT 10h AX=4F02h
```

A failed VBE `4F02h` call never triggers a fitting update.

## 7. ASPECTD

ASPECTD is the DPMI counterpart of ASPECT for systems using a resident 32-bit DPMI host.

Commands:

```dos
ASPECTD
ASPECTD /A
ASPECTD /AS
ASPECTD /S
ASPECTD /C
ASPECTD /D
ASPECTD /E
ASPECTD /U
ASPECTD /?
```

No argument defaults to `/A`; when already resident, the no-argument form reports resident state.

`/A`, `/AS`, `/S`, `/C`, `/D`, `/E` and `/?` have the same policy semantics as ASPECT. The display policy can be switched at runtime using the same ownership and verification rules.

For ASPECTD, `/U` and `/D` are logical deactivation commands. The DPMI client and interrupt hooks remain resident because the verified HDPMI32 environment does not provide a documented safe way to destroy this resident client context later.

ASPECTD uses two retained 4 KiB DPMI MMIO mappings:

- the Fitter A page at `BAR0+68000h` for `PF_A_POS` and `PF_A_SIZE`
- the Pipe A page at `BAR0+60000h` for the read-only `PIPESRC` value used by `/C`

The second mapping is retained even if ASPECTD starts in `/A`, so later runtime switching to `/C` does not require a new resident mapping operation.

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

Its Pipe A source measurements were important to the v2.3 `/C` design. For example, mode 13h was observed as a 640×400 `PIPESRC`, demonstrating that the Intel legacy VGA path can internally expand a lower logical VGA resolution before the panel fitter.

## 10. Troubleshooting

### Immediate reboot or protection fault

With the current verified builds, an immediate reboot should not be expected.

For the direct tools, first check that EMM386/JEMM386 is not active and that you are using the final hardware-verified source. The direct CR0/LGDT transition is a plain-DOS path.

For a memory-manager configuration, use `BLCSETD` or `ASPECTD` with a resident 32-bit DPMI host instead of the direct variants.

Unsupported hardware or an obsolete experimental build can also cause failures.

### BLCSETD or ASPECTD reports no DPMI host

Load a supported 32-bit DPMI host first. The verified configuration uses resident HDPMI32.

### ASPECT reports that output is already 4:3

In `/A` this is expected for output paths whose installation-time fitter destination is already exactly 4:3. No correction hook is required for that policy.

`/C` is independent of the 4:3 test and can still be useful on a fixed-raster output because it centers the actual pipe source.

### External display becomes garbled

Use the final conservative v2.3 ASPECT/ASPECTD builds. Older experimental builds applied startup-derived sizes more broadly and could disturb mode-dependent external outputs.

### ASPECT /U refuses to unload

Possible reasons include:

- another TSR owns `INT 10h` or `INT 2Fh` after ASPECT
- the pre-unload `/D` restore/deactivation operation could not be completed safely
- ASPECT is safety-locked after a fitter write/readback failure

Correct the later TSR chain or reboot as appropriate.

### ASPECTD /U does not remove the TSR

This is expected. ASPECTD `/U` is a logical deactivation command, equivalent to `/D`; the DPMI client remains resident.

### XMS MMIO test returns repeatable garbage

XMS function `0Bh` handle-zero offsets are packed real-mode far pointers, not arbitrary 32-bit physical addresses. This mechanism cannot access MMIO near `F0000000h`.

## 11. Tested software and modes

Confirmed during development on the primary T430 include:

Plain-DOS ASPECT:

- MS-DOS text mode
- standard VGA programs
- Duke Nukem 3D
- Descent
- v2.3 `/C` testing across VGA/VBE modes and the legacy CGA/EGA cases documented above

DPMI ASPECTD with JEMM386/HDPMI32:

- Duke Nukem 3D
- DOOM
- `/A` and `/C` runtime policy control

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

For ASPECT/ASPECTD reports, include the detected output resolution and selected target window/position lines. For diagnostic reports, include complete output rather than selected lines.

## 13. License and attribution

T430LCD is licensed under the MIT License.

Zoltán Bacskó performed hardware investigation, compilation, testing, validation, and maintenance. OpenAI ChatGPT generated and refined implementation code, debugging analysis, refactoring, and documentation. Supported behavior is based on physical-hardware testing rather than emulator-only assumptions.
