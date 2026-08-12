# Reverse Engineering T430LCD

## 1. Purpose

This document records the reverse-engineering process that produced the T430LCD utilities for real MS-DOS.

The project began with a practical ThinkPad T430 problem: LCD brightness had to be restored manually after every DOS boot. The work later expanded to preventing stretched DOS graphics and, in T430LCD 2.3, to providing an explicit pixel-perfect centered display policy.

The utilities were derived through repeated hardware experiments:

1. form a narrow hypothesis
2. write a minimal diagnostic
3. run it on physical hardware
4. record exact register values
5. compare states before and after a known visible change
6. reject unsafe or unsupported approaches
7. keep only behavior supported by hardware readback and visible testing

The ThinkPad T430 remains the primary reverse-engineering and v2.3 regression platform.

## 2. Primary verified system

Primary development machine:

- Lenovo ThinkPad T430
- Intel Core i7-3632QM
- Intel HD Graphics 4000 (Ivy Bridge)
- Intel graphics PCI function 00:02.0
- internal 1600×900 LCD
- external 1680×1050 monitor tested through analog VGA
- external 1680×1050 monitor tested through digital/DVI
- real MS-DOS
- Borland TASM and TLINK

Important PCI values on this machine:

```text
Graphics BAR0: F0000000h
Intel OpRegion ASLS: DAF55018h
```

The complete T430LCD utility set has subsequently also been confirmed on two additional Ivy Bridge/Intel HD Graphics 4000 laptops:

- Lenovo IdeaPad Yoga 13, Core i5-3427U, 1600×900
- HP EliteBook Folio 9470m, Core i5-3427U, 1366×768

ASPECT has additionally been reported working on a Dell Inspiron E5550 with Intel HD Graphics 5500 (Broadwell) and a 1920×1080 panel. Its calculated 4:3 window is 1440×1080 at X=240,Y=0. BLCSET does not work on that laptop, so this is deliberately recorded as ASPECT-only compatibility rather than general Broadwell support.

## 3. Safe physical-memory access

Intel graphics MMIO on the T430 is near `F0000000h`, outside ordinary real-mode addressing.

The working direct backend uses a temporary protected-mode transition:

1. enable A20 through XMS
2. build a runtime GDT
3. enter 16-bit protected mode
4. use a flat 4 GiB data selector for physical MMIO
5. use a writable program-data selector for variables/stack
6. return to real mode
7. restore interrupt/NMI state

### TASM instruction encoding

The 16-bit source uses explicit operand/address-size prefixes where needed. The verified DWORD read from `[ESI]` is:

```asm
db 067h,066h,08Bh,006h
```

and the verified write of EAX to `[ESI]` is:

```asm
db 067h,066h,089h,006h
```

### Triple-fault lesson

An early diagnostic rebooted the T430. The cause was not graphics MMIO but a protected-mode software error: a variable was written through the code selector.

The corrected model became:

```text
CS = executable code selector
ES = writable program-data selector
DS = flat physical-memory selector
SS = writable program-data selector
```

Program variables are never written through `CS:`.

A corrected read-only test returned safely and reported values including:

```text
+48250 CPU_CTL2: 80000000
+48254 CPU_CTL:  00001155
+C8254 PCH_CTL2: 11551155
```

This established that the physical MMIO access itself was valid.

## 4. Brightness reverse engineering

Candidate offsets were sampled at minimum, medium and maximum brightness. The active T430 path was identified as:

```text
BAR0+48250h  CPU backlight control enable/state
BAR0+48254h  active PWM duty
BAR0+C8254h  PCH backlight maximum/current packed value
```

The upper 16 bits of `C8254h` contained the tested hardware maximum:

```text
1155h
```

The legacy `61250h/61254h` candidates did not change.

The final brightness writer therefore:

- discovers BAR0 dynamically
- reads the hardware maximum
- clamps the requested value
- preserves unrelated upper bits
- writes only `BAR0+48254h`
- verifies the resulting duty immediately

This produced `BLCSET`, followed by the CONFIG.SYS `BLCINIT` driver and later the DPMI `BLCSETD` variant.

The Broadwell Dell Inspiron E5550 report is an important limit on generalization: ASPECT works there, but BLCSET does not. The PWM findings above remain primarily Ivy Bridge/T430 findings.

## 5. OpRegion panel-fitting hypothesis

Firmware investigation identified Intel OpRegion fields including:

```text
ASLS+300h  ARDY
ASLS+304h  ASLC
ASLS+308h  TCHE
ASLS+314h  PFIT
ASLS+340h  CPFM
ASLS+344h  EPFM
```

On the T430, the exact ASLS address had to be used; aligning `DAF55018h` down to `DAF55000h` was incorrect.

The corrected FITREAD result included:

```text
Signature: IntelGraphicsMem
ARDY +300h: 00000000
ASLC +304h: 00000000
TCHE +308h: 00000000
PFIT +314h: 80000006
CPFM +340h: 00000000
EPFM +344h: 00000000
```

`PFIT=80000006h` represented stretch text/graphics, but the mailbox readiness/capability state was inactive under DOS. The project therefore moved from an OpRegion request path to direct display-engine MMIO.

## 6. Discovering the active panel fitter

PFDIAG read the legacy fitter and all three CPU panel fitter blocks.

The important T430 internal-LCD Fitter A state was:

```text
PF_A_CTL    = 80800000h
PF_A_POS    = 00000000h
PF_A_SIZE   = 06400384h
PF_A_VSCALE = 000038E4h
PF_A_HSCALE = 0000399Ah
```

`06400384h` decodes to 1600×900.

A centered 4:3 rectangle at full height is:

```text
1200×900 at X=200,Y=0
PF_A_POS  = 00C80000h
PF_A_SIZE = 04B00384h
```

### The critical write rule

Early writers tried rewriting fitter control as well as position/size. Rewriting `PF_A_CTL`, even with the same value, could cause scrambled or flickering restoration.

The stable policy became:

```text
1. write PF_A_POS
2. write PF_A_SIZE
3. verify both
```

Never write:

```text
PF_A_CTL
PF_A_VSCALE
PF_A_HSCALE
```

This remains the v2.3 rule for both `/A` and `/C`.

## 7. Why a TSR was required

A one-shot fitter change lasted only until the next BIOS video mode set. The solution was a resident INT 10h hook watching:

```text
AH=00h    legacy VGA mode set
AX=4F02h  VBE mode set
```

The original BIOS runs first, then the TSR conditionally reapplies its display policy.

This work evolved from PFKEEP into ASPECT.

## 8. External-output failure and PFSNAP

The first generalized ASPECT implementation assumed that the fitter size seen at installation represented a fixed physical output raster. That assumption failed on an external 1680×1050 display.

PFSNAP was created as a read-only TSR to capture before/after BIOS mode-set state while graphics software owned the display. It records:

- requested BIOS mode
- BIOS return state
- fitter A/B/C registers
- pipe configuration/timings
- pipe source dimensions
- skipped VM86 captures

### Analog VGA result

Text mode:

```text
Fitter A SIZE = 02D00190h = 720×400
Pipe A SRC    = 02CF018Fh = 720×400
```

Mode 13h:

```text
Fitter A SIZE = 028001E0h = 640×480
Pipe A SRC    = 027F018Fh = 640×400
```

The external path used mode-specific fitter destinations, so applying an installation-derived internal-LCD window unconditionally was unsafe.

### Digital/DVI result

The tested DVI path already used a 640×480 fitter destination for legacy graphics. It therefore needed no `/A` correction.

These observations led to the conservative rule used today: decide from measured fitter state, not from connector name.

## 9. Fixed-raster safety model

At installation, ASPECT/ASPECTD save the active Fitter A destination as the candidate fixed raster.

After each watched BIOS mode set, normal automatic correction is permitted only when:

```text
current PF_A_SIZE == installation PF_A_SIZE
```

If the BIOS has programmed another size, the TSR assumes that the output path is mode-timed and leaves it alone.

For explicit runtime `/A`↔`/C` switching, v2.3 additionally accepts an exact match to the TSR's last-applied `PF_A_POS` and `PF_A_SIZE`; that proves the current state is owned by the TSR.

This safety/ownership rule is independent from the selected display policy.

## 10. Pre-v2.3 ASPECT behavior

Earlier releases had one display policy: centered 4:3 correction.

They calculated the largest centered 4:3 rectangle from the saved fixed raster. For example:

```text
1600×900 -> 1200×900 at 200,0
1366×768 -> 1024×768 at 171,0
```

Those releases also contained a native-resolution VBE exception: a VBE mode whose reported dimensions matched the detected fixed raster was deliberately left full-screen.

That exception is historical. It was removed in v2.3 once a separate pixel-perfect centered policy existed.

## 11. T430LCD 2.3 policy model

Version 2.3 makes policy selection explicit:

```text
no argument = /A
/A          = centered 4:3 aspect correction
/C          = pixel-perfect centered source raster
/D          = deactivate
/E          = re-enable selected policy
```

Plain ASPECT `/U` physically unloads; ASPECTD `/U` remains equivalent to `/D` because the verified resident DPMI client cannot be safely destroyed later.

### `/A` aspect policy

The existing 4:3 algorithm remains dynamic:

1. try full output height with `width = height × 4 / 3`
2. otherwise use full width with `height = width × 3 / 4`
3. round the calculated changing dimension down to an even value
4. center the result

The old native-VBE exception is gone. A successful native VBE mode follows `/A` like any other compatible mode. On the T430, a native 1600×900 VBE source can therefore be shown as 1200×900 when `/A` is selected.

### `/C` centered policy from PIPESRC

PFSNAP had already shown that Pipe A `PIPESRC` represents the raster reaching the display pipeline. Its format is:

```text
upper 16 bits = width - 1
lower 16 bits = height - 1
```

For example:

```text
027F018Fh -> 640×400
02CF018Fh -> 720×400
```

Mode 13h, logically 320×200, was observed as 640×400 at the pipe. This was strong evidence that the Intel VGA compatibility path can expand a legacy logical mode before panel fitting.

`/C` therefore uses the decoded pipe dimensions directly:

```text
TargetWidth  = PipeWidth
TargetHeight = PipeHeight
X = (FixedWidth  - TargetWidth)  / 2
Y = (FixedHeight - TargetHeight) / 2
```

No even rounding is applied, because the purpose is to preserve the exact source raster.

A native source naturally becomes full-screen at X=0,Y=0; no native-resolution special case is needed.

## 12. Legacy CGA/EGA centered-mode exception

Initial `/C` testing on the T430 exposed a narrow problem:

- CGA 320×200 4-color modes produced a very narrow flickering centered window
- other 320×200 VGA modes worked correctly
- a non-standard Fractint 320×400×256 VGA-register-compatible mode also worked correctly
- tested 640×200 and 640×350 modes already worked without a workaround

Visual inspection showed correct 400-line height but half expected width. The final solution is therefore not a generic low-resolution rule.

Only legacy BIOS modes:

```text
04h
05h
0Dh
```

receive special treatment, and only when Pipe A actually decodes to exactly 320×400:

```text
320×400 -> 640×400
```

Only the width is doubled. After this change, all previously problematic CGA/EGA modes worked correctly.

## 13. Runtime controls and unload safety

### `/D` and `/E`

On deactivation, the original fitter state is restored only if the current position/size exactly match the TSR's last-applied state. Otherwise the current BIOS/output state is left untouched.

`/E` re-enables whichever `/A` or `/C` policy is selected and applies it immediately only when ownership/safety checks allow.

### ASPECT `/U`

Version 2.3 improved physical unload. Before removing vectors or freeing memory, `/U` invokes the same resident restore/deactivation operation used by `/D` while the MMIO engine is still available.

Unload proceeds only after a normal disable outcome and only if ASPECT still owns both `INT 10h` and `INT 2Fh`. A write/readback failure, safety lock, busy result or control-protocol failure prevents physical unload.

### ASPECTD `/U`

The verified HDPMI32 environment does not provide a documented safe physical-unload path for the resident DPMI client, mappings and callback. ASPECTD `/U` therefore remains logical deactivation equivalent to `/D`.

## 14. DPMI development

The direct ASPECT backend cannot execute its CR0/LGDT transition while DOS code is running in EMM386/JEMM386 virtual-8086 mode.

A DPMI implementation was therefore developed with HDPMI32:

- 32-bit client startup
- DPMI physical MMIO mapping
- selectors for mapped MMIO
- a DPMI real-mode callback
- real-mode INT 10h interception
- resident operation

An early callback fault was traced to returning from a 32-bit client callback with a 16-bit IRET. The verified implementation uses the 32-bit IRETD encoding.

ASPECTD 2.3 retains two 4 KiB MMIO mappings:

```text
BAR0+68000h  Fitter A page
BAR0+60000h  Pipe A source/timing page
```

The second mapping is read-only from ASPECTD's policy point of view and exists so `PIPESRC` remains available for `/C`, including runtime switching after installation.

ASPECTD has been verified with JEMM386/HDPMI32 and protected-mode games including Duke Nukem 3D and DOOM.

The same DPMI MMIO approach later produced BLCSETD for interactive brightness control.

## 15. Console-output refinement

During v2.3 testing the TSR output was shortened so normal commands do not print long explanatory paragraphs. The documentation carries those explanations instead.

However, the useful installation diagnostics were deliberately retained:

- detected output resolution
- selected target window dimensions
- selected X/Y position

These values are important for reports from previously untested LCD resolutions and helped validate the 1366×768 and 1920×1080 geometry results.

## 16. Engineering lessons

### Read-only diagnostics first

PFDIAG and PFSNAP were essential because they separated observation from hardware modification.

### Value equality does not imply side-effect equality

Rewriting `PF_A_CTL` with the same numeric value still disturbed live hardware. The final implementation writes only the two proven window registers.

### Connector names are weaker than measured behavior

The safe policy is based on fitter ownership/state, not on hard-coded LVDS/VGA/DVI classification.

### Display policy and access backend are separate concerns

ASPECT and ASPECTD implement the same hardware policy through different CPU/memory-manager mechanisms.

### Resolution alone is not enough for legacy compatibility

The working Fractint 320×400×256 case demonstrated why the CGA/EGA workaround had to include both the BIOS mode number and the observed 320×400 pipe geometry.

### Compatibility is component-specific

The Broadwell Dell Inspiron E5550 report shows that ASPECT can work beyond Ivy Bridge while BLCSET fails on the same system. One successful register family must not be generalized to another.

## 17. Result

T430LCD now includes:

### End-user tools

- `BLCSET`
- `BLCSETD`
- `BLCINIT`
- `ASPECT`
- `ASPECTD`

### Diagnostics

- `FITREAD`
- `PFDIAG`
- `PFSNAP`
- earlier brightness/MMIO discovery programs retained in the project history

### Verified achievements

- direct T430 LCD brightness control under real MS-DOS
- DPMI-compatible interactive brightness control with JEMM386/HDPMI32
- CONFIG.SYS brightness initialization
- dynamic centered 4:3 correction
- v2.3 pixel-perfect centered `/C` mode
- safe runtime `/A`/`/C` policy switching
- hardware-tested CGA/EGA 320-wide compatibility correction
- safe analog VGA and digital/DVI behavior on the primary T430
- safe physical unload for plain-DOS ASPECT after restoration/deactivation
- logical disable/re-enable controls for ASPECT and ASPECTD
- community confirmation of the complete utility set on two additional Ivy Bridge/HD 4000 laptops
- ASPECT-only community confirmation on Broadwell/HD 5500 at 1920×1080

The ThinkPad T430 remains the primary fully documented platform and the source of the detailed v2.3 centered-mode regression matrix.
