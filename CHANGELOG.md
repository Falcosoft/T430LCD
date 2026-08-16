# Changelog

All notable changes to T430LCD are documented here.

## [2.4.0] — 2026-08-16

### ASPECT / ASPECTD

- Added `/AS`: existing `/A` centered 4:3 geometry with the hardware-verified FIR-91 programmable sharp filter.
- Added `/S`: FIR-91 sharp filtering while preserving the current fitter geometry.
- Added `/?` short command help.
- Added verified PF0 horizontal/vertical coefficient programming through `680A0h/680A4h` and `680B0h/680B4h`.
- Selected FIR-91 as the final sharp kernel: symmetric 4.4921875% / 91.015625% / 4.4921875% for every phase.
- Added complete readback verification for coefficient tables, index restoration, filter-selector changes and the size write used to latch the filter.
- Restored Intel Medium 3×3 filtering automatically when leaving a sharp policy.
- Refined the historical `PF_A_CTL` rule: arbitrary/full-register rewrites remain avoided, but v2.4 deliberately modifies only the verified filter-selector field while preserving all unrelated bits.
- Kept `PF_A_VSCALE` and `PF_A_HSCALE` untouched.
- Added `/C` handling for BIOS 40×25 text modes `00h`/`01h`: only when Pipe A reports exactly 360×400, the target becomes 720×400.
- Reduced ASPECT resident memory by using unused PSP space below `0100h` as its private interrupt stack and by generating FIR table values from compact templates.

### Documentation

- Updated the user guide, README, design notes, register reference and hardware-test documentation for the four-policy v2.4 model.
- Preserved historical reverse-engineering and development-history material and added the v2.4 sharp-filter work as a later development stage.

## [2.3.0] — 2026-08-12

### ASPECT / ASPECTD

- Added `/A` as the explicit centered 4:3 aspect-ratio policy selector while preserving no-argument `/A` behavior for backward compatibility.
- Added `/C` pixel-perfect centered mode. The target is derived dynamically from Pipe A `PIPESRC` rather than from a hard-coded DOS mode table.
- Added safe runtime switching between `/A` and `/C`. Immediate policy changes are applied only when the fitter is at the installation fixed-raster state or exactly matches the TSR's own last-applied state.
- Removed the old native-resolution VBE bypass. `/A` now consistently applies aspect correction to successful native VBE modes when the fitter safety checks allow it; `/C` naturally preserves a native source at 1:1 full screen.
- Added a narrow hardware-verified compatibility correction for legacy BIOS modes `04h`, `05h` and `0Dh`: only when Pipe A reports exactly 320×400, the `/C` target becomes 640×400 by doubling width only.
- Confirmed that other 320×200 VGA modes, a non-standard VGA-register-compatible 320×400×256 Fractint mode, and tested 640×200 / 640×350 CGA/EGA-family modes do not require this exception.
- ASPECTD now retains a second 4 KiB DPMI mapping for `BAR0+60000h` so Pipe A `PIPESRC` is available to `/C` and to later runtime policy switching.
- Preserved the established external-output safety rule and the write policy of modifying only `PF_A_POS` followed by `PF_A_SIZE` with immediate readback verification.
- Changed plain ASPECT `/U` to execute the same safe resident restore/deactivation path as `/D` before restoring interrupt vectors and freeing the TSR. Unsafe or uncertain restore outcomes now prevent physical unload.
- Kept ASPECTD `/U` as logical deactivation equivalent to `/D` because the verified resident HDPMI32 client has no documented safe physical-unload path.
- Shortened normal command/status output while retaining the detected output resolution and selected target window/position diagnostics needed for future hardware reports.

### Hardware validation

- Completed v2.3 `/C` regression testing on the primary ThinkPad T430. All previously problematic CGA/EGA modes work with the final mode-specific exception.
- Retained successful behavior for tested 640×200 and 640×350 legacy modes without special handling.
- Added a community ASPECT compatibility report for a Dell Inspiron E5550 with Intel HD Graphics 5500 (Broadwell) and a 1920×1080 internal display. ASPECT produces a 1440×1080 4:3 window at X=240, Y=0.
- BLCSET was reported not to work on that Broadwell system, so the report is intentionally ASPECT-specific and is not a claim of general T430LCD/Broadwell compatibility.

### Project

- Set the project release documentation and final ASPECT/ASPECTD source headers to T430LCD 2.3.
- Updated user, design, hardware-test and development-history documentation for the policy-based display-fitting model.

## [2.2.0] — 2026-08-09

### ASPECT

- Added `/D` to deactivate automatic aspect-ratio correction without unloading the real-mode TSR.
- Added `/E` to re-enable correction and immediately reapply it when the current fitter state is compatible.
- Preserved `/U` as the original true physical unload command.
- On `/D`, the original fitter state is restored only when the current `PF_A_POS` and `PF_A_SIZE` exactly match ASPECT's own applied 4:3 state; otherwise the current fitter state is left untouched.
- Added write/readback failure handling that disables further correction writes for safety.
- Refactored the TSR into separate resident and transient regions so the installer, command parser, `/U` unloader, console output, messages, and installation-only helpers are discarded after installation.
- Consolidated repeated protected-mode transition logic into a shared resident MMIO engine.
- Reduced the tested resident memory footprint to approximately 3 KB while adding the new runtime controls.

### BLCSETD

- Added `BLCSETD.COM`, a DPMI-compatible version of BLCSET for memory-manager environments.
- Replaced BLCSET's direct CR0 protected-mode transition with a 32-bit DPMI client and DPMI physical-memory mappings.
- Mapped only the two 4 KiB MMIO pages required by the brightness path: `BAR0+48000h` and `BAR0+C8000h`.
- Added DPMI selectors for the mapped CPU and PCH PWM pages and release of all selectors and mappings before program termination.
- Preserved BLCSET's PCI BIOS discovery of the Intel graphics BAR0.
- Preserved detection of the active PWM maximum from the upper 16 bits of `BAR0+C8254h`.
- Preserved clamping of the requested duty to the detected maximum.
- Preserved the upper 16 bits of `BAR0+48254h`; only the low duty word is modified.
- Preserved immediate readback verification of the applied duty.
- Confirmed operation on the ThinkPad T430 with JEMM386/HDPMI32.
- Kept `BLCINIT.SYS` unchanged because it can run from CONFIG.SYS before EMM386/JEMM386 is loaded.

### Project

- Added DPMI-compatible interactive LCD brightness control for memory-manager environments.
- Added logical disable/re-enable controls to the plain-DOS ASPECT TSR.
- Updated the project documentation for ASPECT, BLCSETD, and release 2.2.

## [2.1.0] — 2026-08-09

### ASPECTD

- Added `ASPECTD.COM`, a DPMI-compatible version of ASPECT for systems using EMM386/JEMM386.
- Added protected MMIO access through a resident 32-bit DPMI host such as HDPMI32.
- Added resident real-mode `INT 10h` interception with a DPMI real-mode callback for protected MMIO correction.
- Added support for legacy VGA mode sets through `INT 10h AH=00h`.
- Added support for VESA mode sets through `INT 10h AX=4F02h`.
- Preserved the same conservative fixed-raster detection and native VESA mode exception used by ASPECT.
- Preserved safe external-output behavior by applying correction only when `PF_A_SIZE` matches the installation-time fitter size.
- Confirmed operation with protected-mode DOS games including Duke Nukem 3D and DOOM.
- Added `/U` and `/D` commands to deactivate aspect-ratio correction while leaving the DPMI client resident.
- Added `/E` command to re-enable correction and immediately reapply it when the current fitter state is compatible.
- Added restoration of the original fitter state on deactivation when the current state is exactly ASPECTD's applied 4:3 state.
- Added write/readback verification and a safety lock that disables further fitter writes after a verification failure.
- Confirmed that only `PF_A_POS` and `PF_A_SIZE` are written.
- Added ASPECTD to the shared T430LCD include/build structure.

### Project

- Added DPMI-compatible aspect-ratio correction for EMM386/JEMM386 environments.
- Updated the project documentation for ASPECTD and release 2.1.

## [2.0.0] — 2026-07-26

### Project

- Renamed T430BLC to T430LCD.
- Reorganized the project into user tools, diagnostics, and documentation.
- Retained the MIT License.
- Added explicit documentation of the collaborative development process.
- Added a dedicated Vogons community discussion.

### ASPECT

- Added resident automatic 4:3 aspect-ratio correction.
- Added interception of legacy VGA mode sets through `INT 10h AH=00h`.
- Added interception of VESA mode sets through `INT 10h AX=4F02h`.
- Confirmed operation with Duke Nukem 3D and Descent under plain DOS.
- Added safe virtual-8086 detection.
- Added dynamic fitter-destination detection.
- Added centered 4:3 window calculation.
- Added native VESA mode exception.
- Added conservative fixed-raster detection.
- Added automatic skip when the BIOS output is already 4:3.
- Added automatic skip when the fitter destination changes between modes.
- Added correct behavior for internal LCD, external analog VGA, and external DVI.
- Added safe `/U` unloading.
- Added interrupt-chain ownership checks before unloading.
- Added restoration of original `INT 10h` and `INT 2Fh` vectors.
- Added release of resident environment and PSP memory blocks.
- Confirmed that only `PF_A_POS` and `PF_A_SIZE` should be written.
- Confirmed that rewriting `PF_A_CTL` can cause flickering and corrupted output.

### Diagnostics

- Added FITREAD for Intel OpRegion panel-fitting inspection.
- Added PFDIAG for all Ivy Bridge panel-fitter blocks.
- Added PFSNAP read-only TSR for before/after BIOS mode-change snapshots.
- Added pipe timing and source-size capture.
- Documented fixed-raster internal LCD behavior versus mode-timed external outputs.

### Future work

- DPMI-compatible MMIO access under EMM386.
- Compatibility testing on other Ivy Bridge ThinkPads.
- Additional output-path diagnostics.

## [1.0.0] — 2026-07-24

Initial release under the **T430BLC** name. The project was later renamed T430LCD when its scope expanded from backlight control to broader LCD and display-engine control.

### BLCSET

- Added `BLCSET.COM` command-line LCD brightness control under real MS-DOS.
- Added dynamic Intel graphics BAR0 discovery through PCI BIOS.
- Added active backlight PWM maximum detection from `BAR0+C8254h`.
- Added duty-value clamping and readback verification.
- Preserved the upper word of `BAR0+48254h`.
- Confirmed active T430 brightness registers at `BAR0+48250h`, `BAR0+48254h`, and `BAR0+C8254h`.

### BLCINIT

- Added `BLCINIT.SYS` CONFIG.SYS device driver for one-time brightness initialization.
- Added boot-driver private-stack handling and discardable initialization section.
- Added hexadecimal argument parsing and corrected hexadecimal display output.
- Corrected SYS linking instructions.
- Confirmed successful execution during DOS boot before EMM386.

### Protected-mode framework

- Added temporary protected-mode entry from real DOS.
- Added runtime-patched GDT and flat 4 GiB physical-memory descriptor.
- Added XMS-controlled A20 handling and interrupt/NMI masking.
- Fixed a triple fault caused by writing through a non-writable code selector.
- Added explicit address-size and operand-size encodings required by TASM.

### Documentation

- Added complete technical documentation and attribution.
