# Reverse Engineering T430LCD

## 1. Purpose

This document records the reverse-engineering process that produced the T430LCD utilities for the Lenovo ThinkPad T430 under real MS-DOS.

The project began with a practical problem: the LCD brightness had to be restored manually after every DOS boot. The work later expanded to a second problem: legacy 4:3 DOS video modes were stretched across the internal 16:9 LCD.

The final utilities were not created from a single undocumented register table. They were derived through repeated experiments:

1. form a narrow hypothesis
2. write a minimal diagnostic
3. run it on physical hardware
4. record the exact register values
5. compare states before and after a known user-visible change
6. reject unsafe or unsupported approaches
7. keep only behavior verified by hardware readback and visible results

The project therefore contains both end-user tools and the diagnostics that established why those tools are safe.

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

- Lenovo IdeaPad Yoga 13 with Intel Core i5-3427U / Intel HD Graphics 4000
- HP EliteBook Folio 9470m with Intel Core i5-3427U / Intel HD Graphics 4000

These are community confirmations rather than the primary reverse-engineering
platform. Their exact internal panel resolutions and detailed register/output-path
logs are not yet recorded.

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

## 12. Final ASPECT algorithm

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

### 12.2 Per-mode conservative check

After each watched BIOS mode change, ASPECT reads the current fitter destination again.

It writes only when:

```text
current PF_A_SIZE == installation PF_A_SIZE
```

This indicates a fixed-raster widescreen path such as the internal LCD.

If the fitter size changed, ASPECT assumes a mode-timed output path and leaves it untouched.

### 12.3 Native VESA exception

For `AX=4F02h`, ASPECT queries the VBE mode information using `AX=4F01h`.

If the requested mode's X and Y resolution match the detected output dimensions, ASPECT does not apply pillarboxing.

This preserves native 1600×900 VESA output.

### 12.4 Safe physical unload

`ASPECT /U`:

1. locates the resident copy through `INT 2Fh`
2. confirms that ASPECT still owns `INT 10h`
3. confirms that ASPECT still owns `INT 2Fh`
4. restores both original vectors
5. balances the XMS global A20 enable
6. frees the resident environment block
7. frees the TSR PSP/program block

If another TSR was installed after ASPECT and owns either interrupt, unload is refused.

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

The final `ASPECTD`:

- maps the fitter MMIO page through DPMI
- uses a protected-mode callback for fitter access
- hooks real-mode `INT 10h`
- preserves the same conservative fixed-raster and native-VESA rules as ASPECT
- writes only `PF_A_POS` and `PF_A_SIZE`
- verifies every fitter write
- safety-locks further writes after a verification failure

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
- DPMI-compatible resident aspect-ratio correction with JEMM386/HDPMI32
- safe handling of external analog VGA
- safe handling of external digital/DVI
- protected-mode-game compatibility in tested plain-DOS and DPMI configurations
- safe physical unload for plain-DOS ASPECT
- logical disable/re-enable controls for ASPECT and ASPECTD
- documented Intel Ivy Bridge MMIO behavior

The ThinkPad T430 remains the primary fully documented validation platform. The complete utility set has also been confirmed working on a Lenovo IdeaPad Yoga 13 with a Core i5-3427U and an HP EliteBook Folio 9470m with a Core i5-3427U, both using Intel HD Graphics 4000. Their exact internal panel resolutions and detailed output-path/PFSNAP results are not yet recorded.
