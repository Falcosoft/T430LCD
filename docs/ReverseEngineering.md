# Reverse Engineering T430LCD

## 1. Purpose

This document records the reverse-engineering process that produced the T430LCD utilities for the Lenovo ThinkPad T430 under real MS-DOS.

The project began with a practical problem: the LCD brightness had to be restored manually after every DOS boot. The work later expanded to a second problem: legacy 4:3 DOS video modes were stretched across the internal 16:9 LCD. T430LCD 2.3 later added an explicit pixel-perfect centered display policy while preserving the original aspect-correction policy.

The final utilities were not created from a single undocumented register table. They were derived through repeated experiments:

1. form a narrow hypothesis
2. write a minimal diagnostic
3. run it on physical hardware
4. record the exact register values
5. compare states before and after a known user-visible change
6. reject unsafe or unsupported approaches
7. keep only behavior verified by hardware readback and visible results

The project therefore contains both end-user tools and the diagnostics that established why those tools are safe. Historically relevant experiments, including unsuccessful hypotheses, are retained here because they explain how the final design was reached.

## 2. Verified system

The primary test machine was:

- Lenovo ThinkPad T430
- Intel Core i7-3632QM
- Intel HD Graphics 4000
- Intel graphics PCI function at bus 0, device 2, function 0
- internal 1600×900 LCD
- external 1680×1050 monitor tested through analog VGA
- external 1680×1050 monitor tested through digital/DVI
- real MS-DOS
- Borland TASM and TLINK

The important PCI values were:

```text
Graphics BAR0: F0000000h
Intel OpRegion ASLS: DAF55018h
```

The complete utility set has subsequently also been confirmed working on:

- Lenovo IdeaPad Yoga 13 with Intel Core i5-3427U / Intel HD Graphics 4000 and a 1600×900 internal LCD
- HP EliteBook Folio 9470m with Intel Core i5-3427U / Intel HD Graphics 4000 and a 1366×768 internal LCD

These are community confirmations rather than the primary reverse-engineering platform. The Yoga 13 uses the same 1600×900 panel geometry as the T430. On the 9470m, user feedback and screenshots confirm that ASPECT produces a centered 1024×768 4:3 window at X=171, Y=0 from the 1366×768 internal panel.

ASPECT has additionally been reported working on a Dell Inspiron E5550 with Intel HD Graphics 5500 (Broadwell) and a 1920×1080 internal display. Its 4:3 window is 1440×1080 at X=240, Y=0. BLCSET does not work on that laptop, so this is deliberately recorded as ASPECT-only compatibility rather than general Broadwell/T430LCD support.

Detailed register/output-path/PFSNAP logs for the two additional Ivy Bridge systems and the Broadwell system are not yet recorded.

Compatibility with other systems is not assumed from register layout alone.

## 3. Initial firmware investigation

### 3.1 DSDT and ACPI methods

The first investigation focused on the system DSDT and Intel graphics OpRegion.

Relevant ACPI methods included:

- `PBLS()`
- `BRNS()`
- `AINT()`

These methods showed that the firmware exposed brightness-related and panel-fitting-related data through the Intel OpRegion.

The OpRegion signature was:

```text
IntelGraphicsMem
```

The ASLS address was obtained from Intel graphics PCI configuration offset `FCh`.

### 3.2 Why the OpRegion was useful

The OpRegion was valuable as a source of:

- firmware state
- mailbox structure
- candidate control fields
- hints about which operations were intended to exist

However, a mailbox field does not automatically mean firmware will execute the request under DOS.

This distinction became important later for panel fitting.

## 4. Building safe physical-memory access

### 4.1 Why real mode was insufficient

The Intel graphics MMIO aperture was located near:

```text
F0000000h
```

Ordinary real-mode addressing cannot directly access this region.

The first working solution used a temporary protected-mode transition:

1. enable A20 through XMS
2. build a runtime GDT
3. enter 16-bit protected mode
4. load a flat 4 GiB data selector
5. access physical MMIO
6. return to real mode
7. restore NMI and interrupt state
8. disable A20 when appropriate

This became the direct plain-DOS backend later used by BLCSET and ASPECT.

### 4.2 Explicit instruction encoding

TASM's 16-bit defaults required exact address-size and operand-size encodings for 32-bit memory operations.

The verified read encoding was:

```asm
db 067h,066h,08Bh,006h
```

This represents a 32-bit load using a 32-bit effective address.

The verified write encoding was:

```asm
db 067h,066h,089h,006h
```

The common include file later wrapped these encodings in macros.

### 4.3 The triple-fault bug

An early protected-mode diagnostic rebooted the T430.

The initial suspicion was an unsafe graphics MMIO access. The real cause was a protected-mode software bug:

```asm
mov byte ptr cs:[Checkpoint],1
```

The code selector was readable and executable, but not writable.

This caused a general-protection fault. Because no protected-mode IDT existed, the fault escalated into a triple fault and hardware reset.

The corrected design used:

```text
DS = flat 4 GiB physical-memory selector
ES = writable program-data selector
```

All protected-mode program-variable writes used `ES:`. Physical MMIO reads and writes used `DS:`.

This correction proved that the MMIO access itself was safe.

### 4.4 Safe read-only confirmation

The corrected direct-read diagnostic completed successfully and reported:

```text
Final checkpoint: 07
+48250 CPU_CTL2: 80000000
+48254 CPU_CTL:  00001155
+C8254 PCH_CTL2: 11551155
```

That result established:

- protected-mode entry worked
- flat physical addressing worked
- the explicit read opcode worked
- the Intel graphics BAR was accessible
- the reboot was caused by selector misuse, not by reading MMIO

## 5. Brightness reverse engineering

### 5.1 Candidate registers

The brightness investigation sampled these offsets:

```text
BAR0+48250h
BAR0+48254h
BAR0+61250h
BAR0+61254h
BAR0+C8250h
BAR0+C8254h
```

Measurements were taken at minimum, medium, and maximum brightness.

### 5.2 Observed changes

At minimum brightness:

```text
48250 = 80000000
48254 = 00000045
C8254 = 11551155
```

At medium brightness:

```text
48254 = 000001E7
```

At maximum brightness:

```text
48254 = 00001155
```

The legacy `61250h` registers did not change.

### 5.3 Conclusion

The active brightness path was:

```text
BAR0+48250h  CPU backlight control enable/state
BAR0+48254h  current PWM duty
BAR0+C8254h  PCH backlight maximum/current packed value
```

The upper 16 bits of `C8254h` contained the hardware maximum:

```text
1155h
```

The verified brightness writer preserved unrelated bits, clamped the requested value to the detected maximum, wrote only the active duty register, and immediately verified readback.

### 5.4 BLCSET

`BLCSET` became the interactive command-line utility.

Its important properties were:

- dynamic BAR0 discovery
- dynamic maximum detection
- hexadecimal input
- range clamping
- no hard-coded brightness maximum
- immediate write verification
- reuse of the safe direct protected-mode framework

### 5.5 BLCINIT

The goal for boot-time brightness was simpler: set one fixed value once before the user shell starts.

A CONFIG.SYS device driver was created so the operation could happen during boot.

Important lessons included:

- COM-style entry assumptions do not apply directly to a device driver
- TLINK requires an appropriate device-driver image layout
- displayed values must remain hexadecimal to avoid confusing output such as `1155h` appearing as decimal `1757`

The final BLCINIT build successfully set the LCD brightness during DOS boot.

## 6. First panel-fitting hypothesis: OpRegion ASLE mailbox

### 6.1 Relevant fields

The earlier DSDT and OpRegion investigation identified:

```text
ASLS+300h  ARDY
ASLS+304h  ASLC
ASLS+308h  TCHE
ASLS+314h  PFIT
ASLS+340h  CPFM
ASLS+344h  EPFM
```

The `PFIT` field exposed:

```text
bit 31  valid
bit 0   center
bit 1   stretch text
bit 2   stretch graphics
```

### 6.2 Safe FITREAD diagnostic

The first panel-fitting program initially used an unsafe unreal-mode shortcut and rebooted the T430.

It was replaced with `FITREAD`, using the same protected-mode framework proven by BLCSET.

An address bug was then discovered: the program incorrectly aligned ASLS down to a 4 KiB page.

Incorrect:

```text
DAF55018h -> DAF55000h
```

Correct behavior was to use the exact PCI ASLS value.

### 6.3 Correct OpRegion result

The corrected FITREAD output was:

```text
Signature: IntelGraphicsMem
ARDY +300h: 00000000
ASLC +304h: 00000000
TCHE +308h: 00000000
PFIT +314h: 80000006
CPFM +340h: 00000000
EPFM +344h: 00000000
```

`PFIT=80000006h` already represented stretch text and stretch graphics.

However:

- `ARDY=0`
- `TCHE=0`
- `CPFM=0`
- `EPFM=0`

This showed that the mailbox was not an active DOS control path. Changing PFIT would likely modify only memory, not the live display engine.

The project therefore moved from firmware mailbox experiments to direct display-engine MMIO.

## 7. Discovering the Ivy Bridge panel fitter

### 7.1 Read-only PFDIAG

`PFDIAG` read the legacy fitter and all three Ivy Bridge CPU panel fitters.

The important register groups were:

```text
Fitter A: 68070h–68090h
Fitter B: 68870h–68890h
Fitter C: 69070h–69090h
```

The internal LCD result was:

```text
Legacy fitter: all zero

Fitter A:
CTL    = 80800000
POS    = 00000000
SIZE   = 06400384
VSCALE = 000038E4
HSCALE = 0000399A

Fitter B: disabled
Fitter C: disabled
```

### 7.2 Interpreting the window size

`06400384h` means:

```text
width  = 0640h = 1600
height = 0384h = 900
```

The BIOS was therefore explicitly programming a full-panel 1600×900 destination.

For a centered 4:3 image at full panel height:

```text
target height = 900
target width  = 900 × 4 / 3 = 1200
horizontal offset = (1600 - 1200) / 2 = 200
vertical offset   = 0
```

Encoded values:

```text
PF_A_POS  = 00C80000h
PF_A_SIZE = 04B00384h
```

### 7.3 First writer experiments

Two writer approaches were tested.

The first rewrote:

- fitter control
- window position
- window size

The second, `PFSET`, wrote only:

- position first
- size second

Both could set 4:3 mode, but only PFSET reliably restored full-screen mode.

Rewriting the control register caused scrambled and flickering output during full-screen restoration.

This produced an important rule:

> Do not rewrite `PF_A_CTL`, even with the same numeric value.

The stable sequence was:

```text
write PF_A_POS
write PF_A_SIZE
```

No writes were made to:

- `PF_A_CTL`
- `PF_A_VSCALE`
- `PF_A_HSCALE`

## 8. Why a TSR was required

A one-shot utility corrected only the current mode.

Every later BIOS video mode change restored the BIOS default fitter configuration.

The solution was a resident `INT 10h` hook:

```text
AH=00h    legacy VGA mode set
AX=4F02h  VESA VBE mode set
```

The handler called the original BIOS first, then reapplied the fitter window.

This became PFKEEP and was later renamed ASPECT.

The TSR worked with:

- ordinary VGA programs
- Duke Nukem 3D
- Descent

Although those games use protected mode, their mode-set calls reached the real-mode BIOS hook in a usable context under the tested plain-DOS configuration.

## 9. External-display failure and PFSNAP

### 9.1 Initial wrong assumption

The first generalized ASPECT implementation assumed that the fitter size observed during installation represented the monitor's native physical resolution.

That was true for the internal fixed-raster LCD, but false for external outputs.

When an external 1680×1050 monitor was connected, graphics modes became garbled.

### 9.2 PFSNAP design

A normal diagnostic could not print registers while a graphics program owned the screen.

`PFSNAP` solved this by becoming a read-only TSR.

It captured before and after states for every watched mode set and stored them in a circular buffer.

After the graphics program returned to text mode:

```dos
PFSNAP /D
```

printed the records.

Captured data included:

- request type
- requested mode
- BIOS return value
- fitter A/B/C registers
- pipe A/B/C configuration and timings
- pipe source size
- skipped VM86 captures

## 10. External analog VGA behavior

The analog VGA trace showed:

### Text mode

```text
Fitter A SIZE = 02D00190h = 720×400
Pipe A SRC    = 02CF018Fh = 720×400
```

### Mode 13h

```text
Fitter A SIZE = 028001E0h = 640×480
Pipe A SRC    = 027F018Fh = 640×400
```

The BIOS was already converting the 640×400 source timing into a 640×480 output timing, which gives the intended 4:3 display shape.

The fitter destination changed between modes.

Therefore, treating the startup fitter size as a fixed native raster was incorrect.

The correct policy was to leave mode-dependent output paths untouched.

## 11. External digital/DVI behavior

The DVI trace showed a different but equally important pattern.

Fitter A remained:

```text
SIZE = 028001E0h = 640×480
```

for both text mode and mode 13h.

Pipe source changed:

```text
text:    720×400
mode13h: 640×400
```

The output timing was already 640×480, exactly 4:3.

Therefore no aspect correction was needed.

This showed that the correct distinction was not merely:

```text
internal vs external
digital vs analog
```

The correct decision had to be based on observed fitter behavior.

## 12. ASPECT algorithm through v2.2

### 12.1 Installation-time classification

ASPECT reads the current fitter destination.

If it is already exactly 4:3:

```text
width × 3 == height × 4
```

ASPECT exits without installing a TSR.

This covers already-correct external paths such as 640×480 DVI output.

If the destination is widescreen, ASPECT calculates the largest centered 4:3 rectangle.

For 1600×900:

```text
1200×900 at 200,0
```

For the later community-confirmed 1366×768 EliteBook Folio 9470m:

```text
1024×768 at 171,0
```

That result is confirmed by user feedback and screenshots and demonstrates that the geometry calculation is not hard-coded for 1600×900.

### 12.2 Per-mode conservative check

After each watched BIOS mode change, ASPECT reads the current fitter destination again.

It writes only when:

```text
current PF_A_SIZE == installation PF_A_SIZE
```

This indicates a fixed-raster widescreen path such as the internal LCD.

If the fitter size changed, ASPECT assumes a mode-timed output path and leaves it untouched.

### 12.3 Native VESA exception through v2.2

For `AX=4F02h`, ASPECT queried the VBE mode information using `AX=4F01h`.

If the requested mode's X and Y resolution matched the detected output dimensions, ASPECT did not apply pillarboxing.

This preserved native 1600×900 VESA output on the primary T430 test platform. This behavior is preserved here as part of the historical design; v2.3 deliberately removed this exception after introducing the explicit `/C` pixel-perfect policy.

### 12.4 Safe physical unload through v2.2

`ASPECT /U` originally:

1. located the resident copy through `INT 2Fh`
2. confirmed that ASPECT still owned `INT 10h`
3. confirmed that ASPECT still owned `INT 2Fh`
4. restored both original vectors
5. balanced the XMS global A20 enable
6. freed the resident environment block
7. freed the TSR PSP/program block

If another TSR was installed after ASPECT and owned either interrupt, unload was refused.

### 12.5 Runtime deactivate/re-enable and resident refactor

ASPECT was later extended with:

- `/D` logical deactivation while keeping the TSR resident
- `/E` re-enable/reapply
- preservation of `/U` as physical unload

On `/D`, ASPECT restores the installation fitter state only when the current
`PF_A_POS` and `PF_A_SIZE` exactly match its own applied 4:3 state. Otherwise the
current output state is left untouched.

On `/E`, future correction is enabled immediately. If the current fitter size
matches the installation-time fixed raster, the 4:3 window is applied immediately;
otherwise ASPECT waits for a later compatible BIOS mode set.

The source was also split into resident and transient regions and the repeated
protected-mode transition logic was consolidated. The resulting tested resident
footprint is approximately 3 KB.

### 12.6 T430LCD 2.3 policy model

T430LCD 2.3 generalized ASPECT from one aspect-ratio policy into two explicit display-fitting policies:

- no argument or `/A`: centered 4:3 aspect-ratio correction
- `/C`: pixel-perfect centered mode derived from the active Pipe A source raster

`/A` and `/C` can be selected when installing and can also be switched while the TSR is resident. An immediate switch is allowed only when the current fitter is either at the installation fixed-raster state or exactly matches ASPECT's own last-applied state. Otherwise the selected policy is remembered and applied on a later compatible BIOS mode set.

The old native-resolution VBE exception was removed. Under v2.3, a native 1600×900 VBE mode on the T430 can therefore be corrected to 1200×900 in `/A`, while `/C` naturally remains 1600×900 full-screen and pixel-perfect because its target comes from the actual pipe source.

For `/C`, Pipe A `PIPESRC` at `BAR0+6001Ch` is decoded as:

```text
width  = upper 16 bits + 1
height = lower 16 bits + 1
```

The decoded raster is centered directly inside the saved fixed-raster destination. No generic low-resolution doubling rule is used.

Hardware testing identified one narrow legacy exception. BIOS modes `04h`, `05h` and `0Dh` could appear visually as a half-width centered image. The final v2.3 correction applies only when both conditions are true:

```text
legacy BIOS mode is 04h, 05h or 0Dh
and decoded PIPESRC is exactly 320×400
```

In that case only the horizontal target is doubled, producing 640×400. This geometry guard is important because a non-standard VGA-register-compatible 320×400×256 Fractint mode already works correctly and must remain untouched.

The tested 640×200 and 640×350 CGA/EGA-family modes also work without special handling.

Plain ASPECT `/U` was strengthened in v2.3. Before restoring interrupt vectors or freeing memory, `/U` now invokes the same resident restore/deactivation operation used by `/D`. If that operation reports an unsafe or uncertain result, physical unload is refused. Thus the original fitter state is restored when ASPECT still owns the currently applied state.

Normal command output was shortened in v2.3, but the detected output resolution and selected target window/position diagnostics were deliberately retained because they are useful for reports from previously untested LCD resolutions.

## 13. EMM386 and DPMI development

### 13.1 Why the direct method fails under EMM386

Under EMM386/JEMM386, DOS code runs in virtual-8086 mode.

Instructions such as:

```asm
LGDT
MOV CR0
```

are privileged and cannot be used directly.

The plain-DOS ASPECT handler therefore detects VM86 and skips the direct operation safely. This limitation applies to the direct backend, not to ASPECTD.

### 13.2 XMS move experiment

An attempted shortcut used XMS function `0Bh` to copy an eight-byte buffer to the MMIO address.

The result was repeatable garbage.

The reason was conceptual:

- XMS handle zero does not accept an arbitrary 32-bit physical linear address
- it interprets the offset as a packed real-mode far pointer
- a far pointer cannot represent MMIO near `F0000000h`

Therefore XMS move cannot bridge to the Intel graphics aperture.

### 13.3 Successful DPMI development: ASPECTD

DPMI was preferred over a VCPI-only design because compatibility with VSBHDA was an explicit project goal.

The staged development that had originally been planned was subsequently completed:

1. map the graphics MMIO page through DPMI physical-address mapping
2. verify read-only fitter access
3. verify controlled position/size writes and restoration
4. allocate and verify a DPMI real-mode callback
5. connect the callback to a real-mode INT 10h hook
6. perform automatic post-BIOS aspect correction
7. keep the DPMI client resident
8. test with JEMM386/HDPMI32 and protected-mode DOS software

An early callback version faulted because a 32-bit DPMI client returned from the callback with a 16-bit `IRET`. The verified fix used a 32-bit `IRETD` encoding.

The pre-v2.3 `ASPECTD`:

- mapped the fitter MMIO page through DPMI
- used a protected-mode callback for fitter access
- hooked real-mode `INT 10h`
- preserved the same conservative fixed-raster and native-VESA rules as ASPECT
- wrote only `PF_A_POS` and `PF_A_SIZE`
- verified every fitter write
- safety-locked further writes after a verification failure

ASPECTD was verified with JEMM386/HDPMI32 and protected-mode games including Duke Nukem 3D and DOOM.

HDPMI32 did not provide a documented safe physical-unload mechanism for this resident-client design. A raw-switch unload experiment was unsafe and was discarded. Therefore ASPECTD `/U` and `/D` are logical deactivation commands, while `/E` re-enables correction.

### 13.4 DPMI brightness: BLCSETD

The same DPMI mapping approach was then applied to interactive brightness control.

`BLCSETD`:

- discovers BAR0 through PCI BIOS
- maps only `BAR0+48000h` and `BAR0+C8000h`
- uses DPMI selectors for those two 4 KiB pages
- preserves BLCSET's maximum detection and duty clamping
- writes only `BAR0+48254h`
- preserves its upper 16 bits
- verifies the low 16-bit duty by immediate readback
- releases both selectors and mappings before termination

BLCSETD was verified with JEMM386/HDPMI32 on the T430.

BLCINIT required no DPMI counterpart because it can perform its one-time operation during CONFIG.SYS processing before the memory manager is loaded.

### 13.5 ASPECTD 2.3 centered-mode extension

ASPECTD 2.3 implements the same `/A` and `/C` policy model as plain ASPECT while retaining its DPMI-specific resident architecture.

For `/C`, ASPECTD keeps its existing 4 KiB fitter mapping at `BAR0+68000h` and adds a second read-only 4 KiB mapping at `BAR0+60000h` so Pipe A `PIPESRC` is available to the protected-mode callback. The same mode-specific and geometry-guarded `04h`/`05h`/`0Dh` 320×400 exception is used.

Runtime `/A` and `/C` switching is explicit in the resident callback. ASPECTD `/U` remains equivalent to `/D` because the verified HDPMI32 resident-client design still has no documented safe physical-unload path.

## 14. Engineering lessons

### 14.1 Read-only diagnostics first

The fastest way to lose confidence in a hardware experiment is to combine unknown reads, writes, and mode transitions in one program.

The successful process was:

- isolate read access
- confirm safe return
- identify changing registers
- write one minimal field
- verify readback
- only then automate it

### 14.2 A reboot does not prove MMIO is unsafe

The first reboots were caused by selector protection, not hardware access.

Always distinguish:

- CPU protection faults
- invalid descriptor use
- missing IDT behavior
- actual hardware side effects

### 14.3 Do not write a control register unnecessarily

The ASPECT experiments proved that rewriting an enabled fitter control register with the same value can still disturb live hardware.

Value equality does not imply side-effect equality.

### 14.4 Firmware mailbox state is not the same as active control

The OpRegion contained meaningful fitting flags, but DOS had no active Intel driver to process them.

A documented request field can still be inert.

### 14.5 Connector names are weaker than measured behavior

The final ASPECT logic does not try to identify LVDS, VGA, DVI, or DisplayPort directly.

Instead it observes:

- whether the output is already 4:3
- whether fitter size remains fixed
- whether the BIOS restores the same widescreen destination

This produced a safer and more portable decision rule.

### 14.6 Separate hardware policy from access backend

BLCSET/BLCSETD and ASPECT/ASPECTD demonstrate that the same conservative register policy can be retained while changing how MMIO is reached.

The direct backend and DPMI backend differ in CPU/memory-manager mechanics, not in which hardware registers are considered safe to modify.

### 14.7 Preserve historically relevant investigation

A failed hypothesis can remain technically valuable when it explains why a later design exists. The OpRegion/ASLE investigation, failed XMS move approach, selector fault, external-output failure, and other discarded paths are therefore part of the project's engineering record rather than disposable implementation detail.

Historical documentation should only remove or rewrite such material when there is an explicit and convincing reason, such as a factual error. Newer results should normally be added as later stages so the evolution of the project remains visible.

## 15. Result

The project produced:

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
- earlier brightness and MMIO discovery programs

### Verified achievements

- direct T430 LCD brightness control under real MS-DOS
- DPMI-compatible interactive brightness control with JEMM386/HDPMI32
- boot-time brightness initialization
- automatic internal-LCD 4:3 correction
- explicit pixel-perfect centered `/C` policy in T430LCD 2.3
- runtime `/A` and `/C` policy switching
- DPMI-compatible resident aspect-ratio/centered correction with JEMM386/HDPMI32
- safe handling of external analog VGA
- safe handling of external digital/DVI
- protected-mode-game compatibility in tested plain-DOS and DPMI configurations
- safe restore-before-unload behavior for plain-DOS ASPECT `/U`
- logical disable/re-enable controls for ASPECT and ASPECTD
- documented Intel Ivy Bridge MMIO behavior
- community confirmation on two additional Ivy Bridge/Intel HD Graphics 4000 laptops
- correct dynamic ASPECT geometry confirmed on 1600×900, 1366×768 and, for ASPECT specifically, 1920×1080 internal panels
- community ASPECT confirmation on a Dell Inspiron E5550 with Intel HD Graphics 5500 (Broadwell)

The ThinkPad T430 remains the primary fully documented validation platform and the detailed v2.3 centered-mode regression platform. The complete utility set has also been confirmed working on a Lenovo IdeaPad Yoga 13 with a Core i5-3427U and 1600×900 internal LCD, and an HP EliteBook Folio 9470m with a Core i5-3427U and 1366×768 internal LCD, both using Intel HD Graphics 4000. The Yoga 13 uses the same 1200×900, X=200 correction as the T430; the 9470m is confirmed by user feedback and screenshots to use a 1024×768, X=171 correction. ASPECT has additionally been reported working on a Dell Inspiron E5550 with Intel HD Graphics 5500 and a 1920×1080 panel, producing a 1440×1080 window at X=240, Y=0; BLCSET does not work on that Broadwell system. Detailed output-path/PFSNAP results for the non-T430 systems are not yet recorded.
