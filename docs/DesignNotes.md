# Design Notes

## Philosophy

T430LCD intentionally follows a conservative engineering philosophy:

- Measure before modifying.
- Prefer read-only diagnostics first.
- Change the smallest possible register set.
- Verify every hardware write by readback and visible behaviour.
- Generalize only after confirming behaviour on real hardware.

## Brightness design

Only the active PWM duty register is written. The maximum duty cycle is detected
from hardware instead of being hard-coded. Requested values are clamped.

`BLCSET` uses the direct plain-DOS protected-mode backend.

`BLCSETD` preserves the same register policy through DPMI. It maps only the two
4 KiB MMIO pages required for the CPU and PCH PWM registers, accesses them through
DPMI selectors, verifies the duty readback, and releases all mappings/selectors
before terminating.

`BLCINIT` performs the same one-time brightness operation during CONFIG.SYS
processing, before a memory manager normally becomes active.

## ASPECT design

The final algorithm is based on observed display-engine behaviour rather than
connector type.

At installation:

1. Read the current panel-fitter destination.
2. If it is already 4:3, do not install.
3. Otherwise compute the largest centred 4:3 rectangle.

After each watched mode change:

1. Skip native VESA modes.
2. Read the current fitter destination.
3. Apply the correction only if the BIOS restored the same fixed-raster
   destination captured during installation.

This avoids disturbing external outputs that already generate correct timings.

The real-mode ASPECT also supports runtime logical control:

- `/D` deactivates correction while keeping the TSR resident.
- `/E` re-enables correction and reapplies it immediately when the current fitter
  size matches the installation-time fixed raster.
- `/U` remains the true physical unload command.

On deactivation, the original fitter state is restored only when the current
position and size exactly match ASPECT's own applied 4:3 state.

## Direct protected-mode backend

The original plain-DOS utilities use a temporary protected-mode transition because
graphics MMIO resides near F0000000h. The framework:

- enables A20 through XMS
- installs a runtime GDT
- enters 16-bit protected mode
- uses a flat 4 GiB data selector
- restores real mode immediately after the operation

This backend is used by tools such as `BLCSET` and the plain-DOS `ASPECT`.

It must not be entered from EMM386/JEMM386 virtual-8086 mode.

## DPMI backend

`ASPECTD` and `BLCSETD` provide the memory-manager-compatible path.

The DPMI design uses:

- a resident 32-bit DPMI host such as HDPMI32
- DPMI physical-memory mapping
- DPMI selectors for the mapped graphics MMIO
- a DPMI real-mode callback for the resident ASPECTD INT 10h service

ASPECTD keeps its DPMI client and real-mode interrupt hooks resident. Because the
verified HDPMI32 configuration does not provide a documented safe physical-unload
path for this design, ASPECTD `/U` is intentionally a logical deactivation command,
equivalent to `/D`.

BLCSETD is simpler because it is not resident: it maps the two required PWM pages,
changes and verifies the duty, releases the DPMI resources, and exits.

The DPMI path has been verified with JEMM386/HDPMI32 on the ThinkPad T430,
including protected-mode DOS games with ASPECTD. DPMI was preferred over a
VCPI-only design because compatibility with VSBHDA is an explicit project goal.

## Why PF_A_CTL is never written

Experiments showed that rewriting PF_A_CTL could produce flickering or corrupted
output even when writing back the same value. Stable operation required changing
only PF_A_POS followed by PF_A_SIZE.

The same write policy is used by ASPECT and ASPECTD.

## Current direction

Current follow-up work is focused on:

- additional Ivy Bridge/Intel HD Graphics 4000 hardware validation
- documenting exact models and configurations reported by community testers
- additional output-path diagnostics where new hardware differs
- continued regression testing of both the direct and DPMI backends
