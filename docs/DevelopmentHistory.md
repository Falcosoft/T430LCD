# Development History

## Phase 1 – Brightness

The project started from a practical request: restore the preferred LCD brightness automatically after booting DOS.

This led to:

- PCI discovery
- MMIO discovery
- protected-mode framework
- BLCSET
- BLCINIT

## Phase 2 – Panel fitting

The next goal was preventing stretched 4:3 graphics on the internal LCD.

Important milestones included:

- FITREAD
- PFDIAG
- PFSET
- ASPECT
- PFSNAP

Repeated experiments on internal LCD, analog VGA and digital DVI revealed that the correct decision criterion is whether the BIOS restores a fixed-raster destination rather than the connector type.

## Phase 3 – Documentation

The repository evolved from T430BLC into T430LCD, adding structured user, developer and reverse-engineering documentation together with an MIT license and public development history.

## Phase 4 – DPMI aspect-ratio support

The direct ASPECT backend cannot perform its CR0/LGDT protected-mode transition while DOS is running in EMM386/JEMM386 virtual-8086 mode.

A staged DPMI development path verified:

- 32-bit DPMI client startup under HDPMI32
- graphics MMIO physical mapping
- read-only fitter access
- controlled fitter writes and restoration
- a DPMI real-mode callback
- temporary real-mode INT 10h interception
- automatic post-BIOS correction
- resident operation

This became `ASPECTD`, the DPMI counterpart of ASPECT. It was verified with JEMM386/HDPMI32 and protected-mode DOS games including Duke Nukem 3D and DOOM.

ASPECTD keeps the DPMI client resident. Its `/U` and `/D` commands therefore logically deactivate correction instead of attempting an unsafe physical unload; `/E` re-enables correction.

## Phase 5 – Runtime controls and DPMI brightness

The plain-DOS ASPECT TSR was extended with:

- `/D` logical deactivation
- `/E` re-enable/reapply
- preservation of `/U` as true physical unload
- exact-state restoration rules on deactivation
- write/readback safety locking
- a resident/transient source split
- a shared protected-mode MMIO engine

The refactor reduced the tested resident footprint to approximately 3 KB while adding the new controls.

`BLCSETD` then applied the successful DPMI MMIO approach to interactive brightness control. It preserves BLCSET's register semantics but maps the required PWM pages through DPMI and releases all DPMI resources before terminating.

Subsequent community testing confirmed the complete T430LCD utility set on two additional Ivy Bridge/Intel HD Graphics 4000 laptops:

- Lenovo IdeaPad Yoga 13 with Intel Core i5-3427U and a 1600×900 internal LCD
- HP EliteBook Folio 9470m with Intel Core i5-3427U and a 1366×768 internal LCD

The Yoga 13 uses the same ASPECT geometry as the T430: a centered 1200×900 4:3 window at X=200, Y=0. On the 9470m, user feedback and screenshots confirm a centered 1024×768 window at X=171, Y=0, demonstrating correct dynamic geometry on a second native panel resolution.

## Phase 6 – v2.3 policy-based display fitting

The next step was to add a second display policy equivalent in intent to the pixel-perfect centered option available in modern graphics drivers.

The command model became:

- no argument — historical default, identical to `/A`
- `/A` — centered 4:3 aspect correction
- `/C` — pixel-perfect centered source raster
- `/D` — deactivate
- `/E` — re-enable the currently selected policy
- `/U` — physical unload for ASPECT; logical deactivate for ASPECTD

### Discovering a usable centered-mode source

PFSNAP had already shown that Pipe A `PIPESRC` describes the raster entering the display path. For example, BIOS mode 13h, logically 320×200, was observed as 640×400 at the pipe. That made `PIPESRC` a better centered-mode source than hard-coded DOS mode tables.

The `/C` implementation therefore reads `BAR0+6001Ch`, decodes the `(dimension-1)` fields and uses that exact raster as the fitter window. The window is centered inside the saved fixed-raster destination without additional rounding.

The direct ASPECT backend already has a flat physical selector and needed no additional mapping. ASPECTD gained a second resident 4 KiB DPMI mapping for `BAR0+60000h` so Pipe A source information is always available, even after runtime switching from `/A` to `/C`.

### Runtime policy switching

The resident state was generalized from a single aspect target to a selected policy plus the exact last-applied position and size.

A live `/A` or `/C` switch is applied immediately only when the fitter is either:

- at the saved installation-time fixed-raster state, or
- exactly at the position/size last written by ASPECT/ASPECTD.

Otherwise the new policy is remembered for a later compatible BIOS mode set. This keeps the external-output safety model intact.

### Removing the native-VBE exception

Earlier ASPECT releases preserved a VBE mode matching the panel's native dimensions as a special full-screen case.

Once `/C` existed, that exception became conceptually redundant. v2.3 removed it:

- `/A` now consistently means 4:3 aspect correction, even for a successful native-resolution VBE mode.
- `/C` naturally keeps a native pipe source at 1:1 full-screen.

This also removed the need for the resident VBE ModeInfo query/buffer used only by the old exception.

### Legacy CGA/EGA exception

Initial `/C` testing exposed a narrow Intel VGA-compatibility quirk. CGA 320×200 4-color modes produced a very narrow flickering centered window while other 320×200 VGA modes worked.

Visual testing indicated that the affected path had normal 400-line height but half the expected width. The existing centered algorithm worked for a non-standard Fractint 320×400×256 VGA-register-compatible mode, proving that a generic 320×400 rule would be wrong.

The final hardware-driven workaround is therefore both mode-specific and geometry-guarded:

- BIOS mode `04h`
- BIOS mode `05h`
- BIOS mode `0Dh` (EGA 320×200×16)

Only when one of these modes reaches Pipe A as exactly 320×400 is the target width doubled to 640 while height remains 400.

After the change, all previously problematic CGA/EGA modes worked correctly. The tested 640×200 and 640×350 CGA/EGA-family modes had already worked in earlier builds and require no special handling.

### Final runtime cleanup

Two final usability/safety refinements were made:

- Normal TSR messages were shortened, while the useful install-time diagnostics showing detected output resolution and selected target window/position were retained for future hardware reports.
- Plain ASPECT `/U` was changed to run the resident `/D` restore/deactivation path before removing interrupt vectors and freeing memory. An uncertain restore now prevents physical unload.

The completed and hardware-tested state became T430LCD **v2.3**.

A subsequent community report extended ASPECT validation beyond Ivy Bridge: on a Dell Inspiron E5550 with Intel HD Graphics 5500 (Broadwell) and a 1920×1080 panel, ASPECT produced the expected 1440×1080 4:3 window at X=240, Y=0. BLCSET did not work on that laptop, so this result is deliberately recorded as ASPECT-only compatibility rather than general T430LCD Broadwell support.

## Future

- collect detailed output-path/PFSNAP logs for the additional verified systems
- additional Ivy Bridge hardware validation
- reports from previously untested internal LCD resolutions
- community testing and contributions
- additional diagnostics where new hardware behavior differs
