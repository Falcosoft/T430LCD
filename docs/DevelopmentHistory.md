# Development History

## Phase 1 – Brightness

The project started from a practical request: restore the preferred LCD
brightness automatically after booting DOS.

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

Repeated experiments on internal LCD, analog VGA and digital DVI revealed that
the correct decision criterion is whether the BIOS restores a fixed-raster
destination rather than the connector type.

## Phase 3 – Documentation

The repository evolved from T430BLC into T430LCD, adding structured user,
developer and reverse-engineering documentation together with an MIT license and
public development history.

## Phase 4 – DPMI aspect-ratio support

The direct ASPECT backend cannot perform its CR0/LGDT protected-mode transition
while DOS is running in EMM386/JEMM386 virtual-8086 mode.

A staged DPMI development path first verified:

- 32-bit DPMI client startup under HDPMI32
- graphics MMIO physical mapping
- read-only fitter access
- controlled fitter writes and restoration
- a DPMI real-mode callback
- temporary real-mode INT 10h interception
- automatic post-BIOS correction
- resident operation

This became `ASPECTD`, the DPMI counterpart of ASPECT. It was verified with
JEMM386/HDPMI32 and protected-mode DOS games including Duke Nukem 3D and DOOM.

ASPECTD keeps the DPMI client resident. Its `/U` and `/D` commands therefore
logically deactivate correction instead of attempting an unsafe physical unload;
`/E` re-enables correction.

## Phase 5 – Runtime controls and DPMI brightness

The plain-DOS ASPECT TSR was extended with:

- `/D` logical deactivation
- `/E` re-enable/reapply
- preservation of `/U` as true physical unload
- exact-state restoration rules on deactivation
- write/readback safety locking
- a resident/transient source split
- a shared protected-mode MMIO engine

The refactor reduced the tested resident footprint to approximately 3 KB while
adding the new controls.

`BLCSETD` then applied the successful DPMI MMIO approach to interactive brightness
control. It preserves BLCSET's register semantics but maps the required PWM pages
through DPMI and releases all DPMI resources before terminating.

## Future

- document exact models/configurations from additional successful Ivy Bridge/HD 4000 tests
- additional Ivy Bridge hardware validation
- community testing and contributions
- additional diagnostics where new hardware behavior differs
