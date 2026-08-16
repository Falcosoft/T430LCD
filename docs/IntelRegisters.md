# Intel Register Reference for T430LCD

## 1. Scope

This document lists the Intel graphics registers and firmware fields used or examined by T430LCD.

All offsets are relative to the Intel graphics MMIO BAR0 unless explicitly described otherwise.

Verified BAR0 on the primary T430:

```text
F0000000h
```

The project writes only a small subset of the registers listed here. T430LCD 2.4 also uses the verified PF0 programmable coefficient interface for `/AS` and `/S`, while Pipe A `PIPESRC` remains read only for `/C`. No pipe register is written.

## 2. PCI configuration

### Intel graphics device

```text
Bus      0
Device   2
Function 0
```

### BAR0

```text
PCI offset 10h
```

Purpose:

- graphics MMIO base address

Verified value on the primary T430:

```text
F0000000h
```

Mask low attribute bits before use:

```asm
and eax,0FFFFFFF0h
```

### ASLS

```text
PCI offset FCh
```

Purpose:

- physical address of Intel graphics OpRegion

Verified T430 value:

```text
DAF55018h
```

Important: do not align ASLS down to a page boundary. The low `18h` is part of the actual address on the tested T430.

## 3. Intel OpRegion

### Signature

Offset:

```text
ASLS+0000h
```

Expected text:

```text
IntelGraphicsMem
```

### ASLE mailbox fields

| Offset | Name | Role | T430 DOS result |
|---:|---|---|---:|
| `+300h` | ARDY | ASLE readiness/status | `00000000h` |
| `+304h` | ASLC | ASLE command/status | `00000000h` |
| `+308h` | TCHE | technology/capability flags | `00000000h` |
| `+314h` | PFIT | requested panel fitting | `80000006h` |
| `+340h` | CPFM | current panel-fitting mode | `00000000h` |
| `+344h` | EPFM | enabled/supported fitting modes | `00000000h` |

### PFIT bits

| Bit | Meaning |
|---:|---|
| 31 | request valid |
| 0 | center |
| 1 | stretch text |
| 2 | stretch graphics |

Observed:

```text
80000006h
```

The mailbox was not an active control path under DOS because readiness, capability, current, and enabled fields were zero.

## 4. Backlight PWM registers

### CPU backlight control 2

```text
BAR0+48250h
```

Observed on the T430:

```text
80000000h
```

T430LCD does not need to rewrite this register for ordinary brightness changes.

### CPU backlight duty

```text
BAR0+48254h
```

Observed values:

```text
minimum: 00000045h
medium:  000001E7h
maximum: 00001155h
```

This is the primary brightness register written by BLCSET, BLCSETD, and BLCINIT.

### PCH backlight control 2

```text
BAR0+C8254h
```

Observed:

```text
11551155h
```

On the tested T430, the upper 16 bits contain the maximum PWM value (`1155h`).

### Legacy backlight candidates

```text
BAR0+61250h
BAR0+61254h
```

These did not change during brightness-key testing and were not used by the final utilities.

The brightness register policy is hardware-generation-specific. A community report confirms ASPECT on a Broadwell Dell Inspiron E5550 / Intel HD Graphics 5500, but BLCSET does not work on that laptop; therefore the Ivy Bridge PWM findings in this section must not be generalized to Broadwell.

## 5. Legacy panel fitter

Candidate legacy registers:

```text
BAR0+61230h  control
BAR0+61234h  programmed ratios
BAR0+61238h  automatic ratios
```

Observed on the tested T430:

```text
00000000h
00000000h
00000000h
```

The active path used the CPU panel fitter A instead.

## 6. CPU panel fitters used by the primary Ivy Bridge investigation

### Fitter A

| Offset | Name |
|---:|---|
| `68070h` | PF_A_POS |
| `68074h` | PF_A_SIZE |
| `68080h` | PF_A_CTL |
| `68084h` | PF_A_VSCALE |
| `68090h` | PF_A_HSCALE |
| `680A0h` | PF_A_HCOEF_INDEX |
| `680A4h` | PF_A_HCOEF_DATA |
| `680B0h` | PF_A_VCOEF_INDEX |
| `680B4h` | PF_A_VCOEF_DATA |

### Fitter B

| Offset | Name |
|---:|---|
| `68870h` | PF_B_POS |
| `68874h` | PF_B_SIZE |
| `68880h` | PF_B_CTL |
| `68884h` | PF_B_VSCALE |
| `68890h` | PF_B_HSCALE |

### Fitter C

| Offset | Name |
|---:|---|
| `69070h` | PF_C_POS |
| `69074h` | PF_C_SIZE |
| `69080h` | PF_C_CTL |
| `69084h` | PF_C_VSCALE |
| `69090h` | PF_C_HSCALE |

### Control register

Verified T430 internal-LCD value:

```text
PF_A_CTL = 80800000h
```

Important observed behavior:

- fitter A was active
- fitters B and C were disabled
- rewriting `PF_A_CTL` caused unstable full-screen restoration in one experiment

Historical rule from the geometry experiments:

```text
Do not blindly rewrite PF_A_CTL.
```

T430LCD 2.4 refines this rule: `/AS` and `/S` deliberately modify only the verified filter-selector field while preserving all unrelated bits. The programmed-filter selector is `00b`; Intel Medium 3×3 is restored with the corresponding verified selector value. Every control write is read back and verified.

### Position encoding

`PF_A_POS` encodes:

```text
upper 16 bits = X position
lower 16 bits = Y position
```

Example `00C80000h` means X=200, Y=0.

### Size encoding

`PF_A_SIZE` encodes:

```text
upper 16 bits = width
lower 16 bits = height
```

Examples:

```text
06400384h = 1600×900
04B00384h = 1200×900
028001E0h = 640×480
02D00190h = 720×400
```

### Stable write order

The verified sequence is:

```text
1. write PF_A_POS
2. write PF_A_SIZE
```

Do not write unrelated `PF_A_CTL` bits, and do not write:

- `PF_A_VSCALE`
- `PF_A_HSCALE`

### Internal LCD values

T430 BIOS full-screen state:

```text
PF_A_POS  = 00000000h
PF_A_SIZE = 06400384h
```

T430 `/A` 4:3 state:

```text
PF_A_POS  = 00C80000h
PF_A_SIZE = 04B00384h
```

Additional confirmed `/A` geometry:

```text
1366×768  -> 1024×768 at X=171,Y=0  (EliteBook Folio 9470m / HD 4000)
1920×1080 -> 1440×1080 at X=240,Y=0 (Dell Inspiron E5550 / HD 5500, ASPECT report)
```

The Broadwell report demonstrates compatible ASPECT behavior on that system but does not turn the Ivy Bridge register observations into a universal Intel programming contract.

### External VGA examples

Text mode:

```text
PF_A_SIZE = 02D00190h = 720×400
```

Mode 13h:

```text
PF_A_SIZE = 028001E0h = 640×480
```

### External DVI example

Legacy mode output:

```text
PF_A_SIZE = 028001E0h = 640×480
```

This is already 4:3 and requires no `/A` correction.

## 7. Display pipe registers

PFSNAP captured these groups on the primary T430.

### Pipe A

```text
PIPECONF  70008h
HTOTAL    60000h
HBLANK    60004h
HSYNC     60008h
VTOTAL    6000Ch
VBLANK    60010h
VSYNC     60014h
PIPESRC   6001Ch
```

### Pipe B

```text
PIPECONF  71008h
HTOTAL    61000h
HBLANK    61004h
HSYNC     61008h
VTOTAL    6100Ch
VBLANK    61010h
VSYNC     61014h
PIPESRC   6101Ch
```

### Pipe C

```text
PIPECONF  72008h
HTOTAL    62000h
HBLANK    62004h
HSYNC     62008h
VTOTAL    6200Ch
VBLANK    62010h
VSYNC     62014h
PIPESRC   6201Ch
```

### PIPESRC dimension encoding

`PIPESRC` uses:

```text
upper 16 bits = width - 1
lower 16 bits = height - 1
```

Example:

```text
PIPESRC = 027F018Fh -> 640×400
```

### Pipe A examples

Text-style source:

```text
PIPESRC = 02CF018Fh -> 720×400
```

Mode 13h source:

```text
PIPESRC = 027F018Fh -> 640×400
```

The mode 13h observation was important to v2.3 `/C`: the logical 320×200 VGA mode is already represented as a 640×400 pipe source on the tested path.

## 8. T430LCD 2.4 display policies

### `/A` aspect policy

Installation geometry uses the active fixed-raster fitter size. Exact 4:3 is tested as:

```text
width × 3 == height × 4
```

For a widescreen fixed raster, first try:

```text
target width  = height × 4 / 3
target height = height
```

If that width does not fit:

```text
target width  = width
target height = width × 3 / 4
```

The changing dimension is rounded down to an even value and the result is centered.

The old native-resolution VBE bypass was removed in v2.3. A successful native VBE mode follows `/A` when the normal fitter safety conditions allow correction.

### `/AS` and `/S` programmable sharp filter

The v2.4 sharp modes use the PF0 coefficient interfaces:

```text
BAR0+680A0h  PF_A_HCOEF_INDEX
BAR0+680A4h  PF_A_HCOEF_DATA
BAR0+680B0h  PF_A_VCOEF_INDEX
BAR0+680B4h  PF_A_VCOEF_DATA
```

The horizontal table contains 120 DWORDs and the vertical table 86 DWORDs. The code uses auto-increment and rollover to position and restore the hardware index state. FIR-91 applies the same symmetric 3-tap coefficients to every phase: 4.4921875% / 91.015625% / 4.4921875%.

`/AS` combines these coefficients with `/A` geometry. `/S` preserves the current geometry and rewrites the unchanged size only to latch the filter change.

### `/C` pixel-perfect centered policy

`/C` reads Pipe A `PIPESRC`, decodes the exact source dimensions and uses them as the fitter target:

```text
target width  = PIPESRC width
target height = PIPESRC height
X = (fixed width  - target width)  / 2
Y = (fixed height - target height) / 2
```

No even rounding is applied in `/C` because the source dimensions must remain exact.

A native source therefore naturally produces X=0,Y=0 and full-screen 1:1 output.

### Legacy 320-wide compatibility exception

Hardware testing found that standard BIOS modes `04h`, `05h` and `0Dh` can exhibit a half-width centered result when Pipe A reports exactly 320×400. The final rule is deliberately narrow:

```text
if AH=00h legacy mode is 04h, 05h or 0Dh
and PIPESRC is exactly 320×400:
    use target 640×400
else:
    use PIPESRC exactly
```

Only the horizontal dimension is doubled. Other tested 320×200 VGA modes, the Fractint non-standard 320×400×256 VGA-register-compatible mode, and tested 640×200 / 640×350 CGA/EGA-family modes work without this exception.

### Per-mode ownership/safety rule

After a watched mode set:

```text
if current PF_A_SIZE != installation fixed-raster PF_A_SIZE:
    do not write
```

For explicit runtime `/A`↔`/C` switching, an exact match to the TSR's last-applied `PF_A_POS` and `PF_A_SIZE` is also accepted as owned state.

This prevents corrupting mode-timed external outputs.

## 9. Register-write policy

### Registers written by BLCSET/BLCSETD/BLCINIT

```text
BAR0+48254h
```

The write preserves unrelated upper bits and is verified immediately.

### Registers written by ASPECT/ASPECTD

Geometry path (`/A`, `/AS`, `/C`):

```text
BAR0+68070h  PF_A_POS
BAR0+68074h  PF_A_SIZE
```

Sharp-filter path (`/AS`, `/S`):

```text
BAR0+68080h  PF_A_CTL          filter-selector bits only
BAR0+680A0h  PF_A_HCOEF_INDEX
BAR0+680A4h  PF_A_HCOEF_DATA
BAR0+680B0h  PF_A_VCOEF_INDEX
BAR0+680B4h  PF_A_VCOEF_DATA
```

The geometry write order remains position first, size second. Sharp-mode coefficient/control writes are also verified by readback.

### Registers read by `/C`

```text
BAR0+6001Ch  Pipe A PIPESRC
```

This register is read only.

### Registers/bits intentionally not written

```text
unrelated bits of BAR0+68080h  PF_A_CTL
BAR0+68084h                    PF_A_VSCALE
BAR0+68090h                    PF_A_HSCALE
all pipe timing/source registers
```

## 10. MMIO access conventions

### Direct plain-DOS backend

The safe direct protected-mode design used by BLCSET and ASPECT uses:

```text
CS = 16-bit executable code selector
ES = writable program-data selector
DS = flat 4 GiB physical-memory selector
SS = writable program-data selector
```

Rules:

- MMIO is addressed through DS
- program variables are written through ES
- never write through CS
- disable interrupts and NMI during the transition
- restore real-mode segments before DOS or BIOS calls
- use XMS for A20 control
- do not execute the direct transition under EMM386/JEMM386 VM86

The flat selector already exposes `BAR0+6001Ch`, so ASPECT `/C` needs no extra mapping.

### DPMI backend

BLCSETD and ASPECTD use DPMI instead of direct CR0/LGDT switching.

The verified ASPECTD 2.3 design retains:

- a 4 KiB mapping at `BAR0+68000h` for fitter A position/size
- a separate 4 KiB mapping at `BAR0+60000h` for read-only Pipe A `PIPESRC`
- DPMI selectors configured for both mappings
- a DPMI real-mode callback for the resident INT 10h path

The Pipe A mapping remains resident even when ASPECTD starts in `/A`, allowing later `/C` switching.

## 11. Explicit MMIO instruction encodings

### Read DWORD from DS:[ESI]

```asm
db 067h,066h,08Bh,006h
```

### Write EAX to DS:[ESI]

```asm
db 067h,066h,089h,006h
```

These encodings are used by the 16-bit direct protected-mode sources where needed. DPMI clients can access mapped MMIO through their DPMI selectors.

## 12. Known limits

- The detailed register layout and primary measurements are based on the ThinkPad T430 / Intel HD Graphics 4000.
- Fitter A was the active fitter on the primary T430 test paths.
- Other firmware may select different fitters or use different register behavior.
- The direct CR0/LGDT backend is not usable from EMM386/JEMM386 virtual-8086 mode.
- ASPECTD and BLCSETD provide the DPMI path and have been verified with JEMM386/HDPMI32 on the T430.
- The detailed v2.3 `/C` legacy-mode matrix is from the T430.
- ASPECT has a positive community report on a Broadwell Dell Inspiron E5550 / Intel HD Graphics 5500, but BLCSET does not work there. This is component-specific compatibility evidence, not general Broadwell support.
- Other DPMI hosts, memory-manager combinations, Intel generations, and systems require independent testing.
- This reference documents measured behavior, not a universal Intel programming contract.
