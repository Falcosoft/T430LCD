# Verified Hardware

| System | Internal LCD | Status |
|--------|--------------|--------|
| Lenovo ThinkPad T430 + Intel HD 4000 | 1600×900 | Fully verified primary platform; v2.3 `/A` and `/C` validation platform |
| Lenovo IdeaPad Yoga 13 + Core i5-3427U / Intel HD 4000 | 1600×900 | Complete T430LCD utility set confirmed working |
| HP EliteBook Folio 9470m + Core i5-3427U / Intel HD 4000 | 1366×768 | Complete T430LCD utility set confirmed working |
| Dell Inspiron E5550 + Intel HD Graphics 5500 (Broadwell) | 1920×1080 | ASPECT confirmed working; BLCSET does not work |

The IdeaPad Yoga 13 and EliteBook Folio 9470m results are community hardware reports confirming operation of the complete T430LCD utility set. The Dell Inspiron E5550 report confirms ASPECT on Intel HD Graphics 5500/Broadwell, but does not generalize the brightness path: BLCSET was reported not to work there. The detailed v2.3 centered-mode regression work described below was performed on the primary ThinkPad T430.

## Verified ASPECT `/A` internal-LCD geometry

| System | Native fitter size | Corrected 4:3 window | Position | Confirmation |
|--------|--------------------|------------------------|----------|--------------|
| Lenovo ThinkPad T430 | 1600×900 | 1200×900 | X=200, Y=0 | Fully verified during development |
| Lenovo IdeaPad Yoga 13 | 1600×900 | 1200×900 | X=200, Y=0 | All utilities confirmed working |
| HP EliteBook Folio 9470m | 1366×768 | 1024×768 | X=171, Y=0 | User feedback and screenshots confirm correct output |
| Dell Inspiron E5550 / Intel HD 5500 | 1920×1080 | 1440×1080 | X=240, Y=0 | Community ASPECT report |

The 9470m result is especially useful because it confirms the dynamic 4:3 geometry calculation on a 1366×768 fixed-raster panel rather than only the 1600×900 geometry used by the T430 and Yoga 13.

## Verified v2.3 centered-mode behavior on the T430

`/C` centers the active Pipe A source raster without applying the normal 4:3 calculation. The source dimensions are decoded from `PIPESRC` (`BAR0+6001Ch`) and used as the fitter target when the existing fixed-raster safety checks allow a write.

Hardware testing confirmed correct centered behavior for:

- ordinary VGA modes, including the 320×200 VGA cases that already reach the display pipe in a usable expanded raster
- VESA/VBE modes such as 640×480, 800×600 and 1024×768
- the native 1600×900 VBE mode, which remains pixel-perfect/full-screen in `/C`
- a non-standard VGA-register-compatible 320×400 256-color mode used by Fractint
- 640×200 CGA/EGA-family modes without any special handling
- 640×350 EGA modes without any special handling

Three standard 320-wide legacy BIOS modes required a narrow compatibility correction:

| BIOS mode | Logical mode | Observed failure before fix | v2.3 handling |
|-----------|--------------|-----------------------------|---------------|
| `04h` | CGA 320×200 4-color | half-width centered/flickering window | if `PIPESRC` is exactly 320×400, target becomes 640×400 |
| `05h` | CGA 320×200 4-color | same legacy half-width behavior | if `PIPESRC` is exactly 320×400, target becomes 640×400 |
| `0Dh` | EGA 320×200 16-color | same half-width behavior | if `PIPESRC` is exactly 320×400, target becomes 640×400 |

The correction doubles only the horizontal target. It is mode-specific and geometry-guarded; it is not applied to other 320-wide modes such as the working Fractint 320×400×256 VGA-register-compatible mode.

## Verified policy behavior

- No argument defaults to the original 4:3 aspect policy.
- `/A` explicitly selects the 4:3 policy.
- `/C` selects pixel-perfect centered mode.
- `/A` and `/C` can be switched at runtime when the current fitter state is either the saved fixed-raster state or exactly the state last written by ASPECT/ASPECTD.
- `/D` deactivates correction and restores the original fitter state only when the current state is still owned by the TSR.
- `/E` re-enables the selected policy.
- Plain ASPECT `/U` first executes the same safe restore/deactivation logic as `/D`, then physically unloads only if it is still safe to do so.
- ASPECTD `/U` remains a logical deactivation equivalent to `/D`.

The old native-resolution VBE bypass was removed in v2.3. A native 1600×900 VBE mode can therefore be 1200×900 centered in `/A`, while `/C` naturally keeps the 1600×900 source full-screen and pixel-perfect.

## Verified display paths

The detailed display-path results below are from the primary ThinkPad T430 validation platform.

| Output | Result |
|--------|--------|
| Internal LCD 1600×900 | Brightness ✓ `/A` aspect ✓ `/C` centered ✓ |
| External VGA 1680×1050 | BIOS mode-specific timings preserved ✓ |
| External DVI 1680×1050 | Already-correct legacy output preserved ✓ |

Detailed PFSNAP/output-path logs for the Yoga 13 and EliteBook Folio 9470m are not yet recorded.
