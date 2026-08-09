# Changelog

All notable changes to T430LCD are documented here.

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
