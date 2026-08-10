# Intel Register Reference for T430LCD

## 1. Scope

This document lists the Intel Ivy Bridge graphics registers and firmware fields used or examined by T430LCD.

All offsets are relative to the Intel graphics MMIO BAR0 unless explicitly described otherwise.

Verified BAR0 on the primary T430:

```text
F0000000h
```

The project writes only a small subset of the registers listed here.

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

Verified value:

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

Verified value:

```text
DAF55018h
```

Important:

Do not align ASLS down to a page boundary. The low `18h` is part of the actual address on the tested T430.

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

Interpretation:

- valid
- stretch text
- stretch graphics

The mailbox was not an active control path under DOS because readiness, capability, current, and enabled fields were zero.

## 4. Backlight PWM registers

### CPU backlight control 2

```text
BAR0+48250h
```

Observed:

```text
80000000h
```

Role:

- active CPU backlight control enable/state

T430LCD does not need to rewrite this register for ordinary brightness changes.

### CPU backlight duty

```text
BAR0+48254h
```

Role:

- current active PWM duty

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

Interpretation on the tested T430:

- upper 16 bits contain maximum PWM value
- maximum = `1155h`

### Legacy backlight candidates

```text
BAR0+61250h
BAR0+61254h
```

These did not change during brightness-key testing and were not used by the final utilities.

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

The active path used Ivy Bridge CPU panel fitter A instead.

## 6. Ivy Bridge CPU panel fitters

### Fitter A

| Offset | Name |
|---:|---|
| `68070h` | PF_A_POS |
| `68074h` | PF_A_SIZE |
| `68080h` | PF_A_CTL |
| `68084h` | PF_A_VSCALE |
| `68090h` | PF_A_HSCALE |

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

Verified internal-LCD value:

```text
PF_A_CTL = 80800000h
```

Important observed behavior:

- bit 31 indicates enabled state
- fitter A was active
- fitters B and C were disabled
- rewriting `PF_A_CTL` caused unstable full-screen restoration in one experiment

Final rule:

```text
Do not write PF_A_CTL.
```

### Position encoding

`PF_A_POS` encodes:

```text
upper 16 bits = X position
lower 16 bits = Y position
```

Example:

```text
00C80000h
```

means:

```text
X = 200
Y = 0
```

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

Do not write:

- control
- vertical scale
- horizontal scale

### Internal LCD values

BIOS full-screen state:

```text
PF_A_POS  = 00000000h
PF_A_SIZE = 06400384h
```

ASPECT/ASPECTD 4:3 state:

```text
PF_A_POS  = 00C80000h
PF_A_SIZE = 04B00384h
```

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

This is already 4:3 and requires no correction.

## 7. Display pipe registers

The PFSNAP diagnostic captured the following groups.

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

### Dimension encoding

Many timing and source fields encode dimensions as:

```text
stored value = dimension - 1
```

Example:

```text
PIPESRC = 027F018Fh
```

decodes to:

```text
width  = 027Fh + 1 = 640
height = 018Fh + 1 = 400
```

### Pipe A examples

#### Internal/external text-style source

```text
PIPESRC = 02CF018Fh
```

decodes to:

```text
720×400
```

#### Mode 13h source

```text
PIPESRC = 027F018Fh
```

decodes to:

```text
640×400
```

## 8. Register-write policy

### Registers written by BLCSET/BLCSETD/BLCINIT

```text
BAR0+48254h
```

The write preserves unrelated upper bits and is verified immediately.

### Registers written by ASPECT/ASPECTD

```text
BAR0+68070h
BAR0+68074h
```

The write order is position first, size second.

### Registers intentionally not written

```text
BAR0+68080h  PF_A_CTL
BAR0+68084h  PF_A_VSCALE
BAR0+68090h  PF_A_HSCALE
```

Neither ASPECT nor ASPECTD writes pipe timing registers.

## 9. MMIO access conventions

### Direct plain-DOS backend

The safe direct protected-mode design used by tools such as BLCSET and ASPECT uses:

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

### DPMI backend

BLCSETD and ASPECTD use DPMI instead of direct CR0/LGDT switching.

The verified DPMI design uses:

- a resident 32-bit DPMI host such as HDPMI32
- DPMI function `0800h` physical-address mapping
- DPMI selectors configured for the mapped MMIO
- a DPMI real-mode callback for the resident ASPECTD INT 10h path
- release of temporary BLCSETD selectors/mappings before termination

ASPECTD keeps its mapped fitter page, selector, callback, and DPMI client resident
for later BIOS mode changes.

## 10. Explicit MMIO instruction encodings

### Read DWORD from DS:[ESI]

```asm
db 067h,066h,08Bh,006h
```

### Write EAX to DS:[ESI]

```asm
db 067h,066h,089h,006h
```

These encodings are used by the 16-bit direct protected-mode sources where needed.
DPMI clients can access mapped MMIO through their DPMI selectors.

## 11. Conservative aspect-ratio rules

At installation:

```text
if width × 3 == height × 4:
    output is already 4:3
    do not install correction hook
```

For widescreen fixed-raster output:

```text
target width  = height × 4 / 3
target height = height
```

If that width does not fit:

```text
target width  = width
target height = width × 3 / 4
```

Centering:

```text
X = (output width  - target width)  / 2
Y = (output height - target height) / 2
```

After a mode set:

```text
if current PF_A_SIZE != installation PF_A_SIZE:
    do not write
```

This prevents corrupting external mode-timed outputs.

## 12. Known limits

- The detailed register layout and values in this document are based primarily on the tested T430.
- Fitter A was the active fitter on all primary T430 test paths.
- Other firmware may select fitter B or C.
- The direct CR0/LGDT backend is not usable from EMM386/JEMM386 virtual-8086 mode.
- ASPECTD and BLCSETD provide the DPMI path and have been verified with JEMM386/HDPMI32 on the T430.
- Other DPMI hosts, memory-manager combinations, and Ivy Bridge systems require independent testing.
- The register reference documents measured behavior, not a universal Intel programming contract.
