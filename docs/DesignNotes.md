# Design Notes

## Philosophy

T430LCD intentionally follows a conservative engineering philosophy:

- Measure before modifying.
- Prefer read-only diagnostics first.
- Change the smallest possible register set.
- Verify every hardware write by readback and visible behaviour.
- Generalize only after confirming behaviour on real hardware.
- Preserve useful numeric diagnostics for future hardware reports.

## Brightness design

Only the active PWM duty register is written. The maximum duty cycle is detected from hardware instead of being hard-coded. Requested values are clamped.

`BLCSET` uses the direct plain-DOS protected-mode backend.

`BLCSETD` preserves the same register policy through DPMI. It maps only the two 4 KiB MMIO pages required for the CPU and PCH PWM registers, accesses them through DPMI selectors, verifies the duty readback, and releases all mappings/selectors before terminating.

`BLCINIT` performs the same one-time brightness operation during CONFIG.SYS processing, before a memory manager normally becomes active.

## ASPECT v2.4 policy design

ASPECT/ASPECTD v2.4 separate *safety/ownership* from *display policy* and add a verified programmable-filter path.

The four policies are:

- `/A` — centered 4:3 aspect correction with Intel Medium 3×3 filtering
- `/AS` — the same centered 4:3 geometry with FIR-91 sharp filtering
- `/S` — FIR-91 sharp filtering with the current geometry preserved
- `/C` — pixel-perfect centered source raster

No argument selects `/A` for backward compatibility.

### Installation-time classification

The active Fitter A destination is read at installation and saved as the fixed/native destination.

For `/A`, if the destination is already exactly 4:3, no correction hook is required. Otherwise ASPECT calculates the largest centered 4:3 rectangle.

For `/C`, the 4:3 classification is not used as a reason to skip installation because centered mode is independent of output aspect ratio.

Confirmed `/A` internal-panel geometry includes:

- 1600×900 on the ThinkPad T430 and IdeaPad Yoga 13 → 1200×900 at X=200, Y=0
- 1366×768 on the HP EliteBook Folio 9470m → 1024×768 at X=171, Y=0
- 1920×1080 on the Dell Inspiron E5550 / Intel HD Graphics 5500 → 1440×1080 at X=240, Y=0 (ASPECT community report)

### Per-mode ownership rule

After the original BIOS mode-set handler runs, normal automatic correction is performed only when the current `PF_A_SIZE` equals the installation-time fixed-raster size.

This avoids disturbing external output paths where the BIOS programs a mode-specific fitter destination.

For explicit runtime `/A`↔`/C` switching, immediate application is also permitted when the current `PF_A_POS` and `PF_A_SIZE` exactly match the TSR's last-applied state. That proves ownership without assuming connector type.

### `/A`: aspect policy

The aspect policy uses the existing dynamic 4:3 algorithm:

1. Try full output height with `width = height × 4 / 3`.
2. If that does not fit, use full output width with `height = width × 3 / 4`.
3. Round the calculated changing dimension down to an even value.
4. Center the result.

The old native-resolution VBE exception was removed in v2.3. A successful native VBE mode therefore follows the selected policy like any other mode. This makes `/A` semantically consistent: if the user selects aspect correction, native VBE can also be pillarboxed to 4:3.

### `/C`: pixel-perfect centered policy

`/C` reads Pipe A `PIPESRC` at `BAR0+6001Ch`. The register encodes `(width-1)` in the upper word and `(height-1)` in the lower word.

The decoded dimensions are used directly:

```text
TargetWidth  = PipeSourceWidth
TargetHeight = PipeSourceHeight
X = (NativeWidth  - TargetWidth)  / 2
Y = (NativeHeight - TargetHeight) / 2
```

No even rounding is performed because `/C` must preserve exact source dimensions.

A native source therefore naturally becomes full-screen at X=0, Y=0 without any native-VBE exception.

### Legacy CGA/EGA horizontal-doubling exception

Hardware testing found that BIOS modes `04h`, `05h` and `0Dh` can reach Pipe A as 320×400 while visually requiring a 640×400 centered target. This indicates that vertical doubling is already represented while horizontal doubling is absent from the raster that the fitter would otherwise use.

The workaround is deliberately narrow:

```text
if legacy BIOS mode is 04h, 05h or 0Dh
and PIPESRC decodes to exactly 320×400:
    target = 640×400
else:
    target = PIPESRC exactly
```

This rule is both mode-specific and geometry-guarded. It does not affect other working 320-wide modes, including a non-standard VGA-register-compatible 320×400×256 Fractint mode.

The tested 640×200 and 640×350 CGA/EGA-family modes need no workaround.

### `/AS` and `/S`: programmable FIR-91 filtering

Ivy Bridge PF0 exposes programmable horizontal and vertical coefficient tables. v2.4 uses the verified index/data interfaces at `680A0h/680A4h` and `680B0h/680B4h`, with index movement performed through auto-increment/rollover rather than unsafe backwards index writes.

FIR-91 is the selected compromise from the hardware-tested sharp-filter experiments. Every phase uses the same symmetric 3-tap kernel:

```text
4.4921875% / 91.015625% / 4.4921875%
```

`/AS` combines this filter with the normal `/A` 4:3 geometry. `/S` changes only the filter and leaves the current fitter geometry untouched. Coefficient tables, index restoration, filter-selector changes and the size write used to latch the filter are all verified.

## Runtime controls

Both ASPECT and ASPECTD support:

- `/A` select aspect policy with Medium 3×3 filtering
- `/AS` select aspect policy with FIR-91 sharp filtering
- `/S` select FIR-91 sharp filtering without changing geometry
- `/C` select centered policy
- `/D` deactivate
- `/E` re-enable the selected policy

On `/D`, the original fitter state is restored only when the current position and size exactly match the TSR's last-applied state. If some other BIOS/output path changed the fitter, the current state is left untouched.

`/E` re-enables the selected policy and applies it immediately only when ownership/safety conditions allow.

### Plain ASPECT `/U`

ASPECT `/U` is a true physical unload, but v2.3 first sends the resident `CMD_DISABLE` operation so the same safe `/D` restore/deactivation path runs while all resident MMIO machinery is still available.

Physical unload proceeds only for normal disable outcomes. It is refused after write/readback failure, safety lock, busy state or resident-control failure. ASPECT also retains the original interrupt-chain ownership checks before restoring `INT 10h` and `INT 2Fh` and freeing memory.

### ASPECTD `/U`

ASPECTD keeps the DPMI client and real-mode interrupt hooks resident. Because the verified HDPMI32 configuration does not provide a documented safe physical-unload path for this design, ASPECTD `/U` remains a logical deactivation equivalent to `/D`.

## Console-output policy

TSR status output is intentionally compact. Long explanatory sentences belong in the documentation.

Useful install-time hardware diagnostics are retained:

- detected output resolution
- selected target window dimensions
- selected X/Y position

These values are important for reports from previously untested LCD resolutions.

## Direct protected-mode backend

The plain-DOS utilities use a temporary protected-mode transition because graphics MMIO resides near `F0000000h`. The framework:

- enables A20 through XMS
- installs a runtime GDT
- enters 16-bit protected mode
- uses a flat 4 GiB data selector
- restores real mode immediately after the operation

This backend is used by `BLCSET` and plain-DOS `ASPECT`. It must not be entered from EMM386/JEMM386 virtual-8086 mode.

ASPECT's flat selector already maps physical address space, so `/C` can read Pipe A `PIPESRC` without an additional resident mapping.

## DPMI backend

`ASPECTD` and `BLCSETD` provide the memory-manager-compatible path.

ASPECTD v2.3 uses:

- a resident 32-bit DPMI host such as HDPMI32
- DPMI physical-memory mapping
- DPMI selectors
- a DPMI real-mode callback for the resident INT 10h service
- one 4 KiB fitter mapping at `BAR0+68000h`
- one 4 KiB Pipe A mapping at `BAR0+60000h` used read-only for `PIPESRC`

Both mappings are retained regardless of the initial policy so runtime `/C` switching remains available.

The DPMI path has been verified with JEMM386/HDPMI32 on the ThinkPad T430, including protected-mode DOS games with ASPECTD. DPMI was preferred over a VCPI-only design because compatibility with VSBHDA is an explicit project goal.

## Refined PF_A_CTL write policy

The original panel-fitting experiments showed that blindly rewriting the complete `PF_A_CTL` value could produce flickering or corrupted output even when the numeric value appeared unchanged. That historical result remains important: **full-register or unrelated control rewrites are still avoided**.

T430LCD 2.4 narrows the exception to the hardware-verified filter selector used by `/AS` and `/S`. The code reads `PF_A_CTL`, preserves every unrelated bit, changes only the filter-selection field, verifies the readback, and latches the change through `PF_A_SIZE`. `/A` and `/C` continue to use the established geometry write path. `PF_A_VSCALE` and `PF_A_HSCALE` remain untouched; `PIPESRC` remains read only.

## Additional verified hardware

Community testing has confirmed the T430LCD utility set on:

- Lenovo IdeaPad Yoga 13 with Intel Core i5-3427U / Intel HD Graphics 4000 and a 1600×900 internal LCD
- HP EliteBook Folio 9470m with Intel Core i5-3427U / Intel HD Graphics 4000 and a 1366×768 internal LCD

The v2.3 detailed centered-mode regression matrix is from the primary ThinkPad T430 and should not be generalized to the additional systems without equivalent testing.

## Broadwell compatibility report

ASPECT has also been reported working on a Dell Inspiron E5550 with Intel HD Graphics 5500 (Broadwell) and a 1920×1080 internal display. The dynamically calculated `/A` window is 1440×1080 at X=240, Y=0. This is useful evidence that the Fitter A policy can extend beyond Ivy Bridge. It does **not** imply that all T430LCD hardware paths extend to Broadwell: BLCSET was reported not to work on the same laptop.

## Current direction

Current follow-up work is focused on:

- additional Ivy Bridge/Intel HD Graphics 4000 hardware validation
- collecting detailed output-path/PFSNAP logs for community-verified systems
- reports from additional native LCD resolutions using the retained geometry diagnostics
- continued regression testing of both the direct and DPMI backends
