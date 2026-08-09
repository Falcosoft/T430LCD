# ASPECTD

Resident DPMI 4:3 aspect-ratio corrector for the Lenovo ThinkPad T430 with Intel HD Graphics 4000.

ASPECTD is the DPMI counterpart of `ASPECT`. It is intended for environments where a 32-bit DPMI host such as resident HDPMI32 is available, including the tested JEMM/VSBHDA configuration.

## Build

Run:

```dos
BUILD
```

The build script supplies the repository `INCL` directory to TASM. ASPECTD includes `T430LCD.INC` and uses the shared verified Fitter A register definitions from `REGISTRS.INC`.

## Commands

```dos
ASPECTD
ASPECTD /U
ASPECTD /D
ASPECTD /E
```

`ASPECTD` installs the TSR, or reports its current state if it is already resident.

`/U` and `/D` deactivate aspect correction. The DPMI client and interrupt hooks remain resident because HDPMI32 does not provide a documented safe physical-unload path for this resident client design. If the current fitter state is exactly ASPECTD's applied 4:3 state, the original fitter state is restored immediately; otherwise the current BIOS/output state is left untouched.

`/E` re-enables correction. If the current fitter size matches the installation-time fixed raster, correction is reapplied immediately. Otherwise ASPECTD waits for a later BIOS mode set that restores the installation fitter size.

## Safety policy

ASPECTD writes only Fitter A position and size, in this order:

1. `PF_A_POS`
2. `PF_A_SIZE`

Every write is verified by immediate readback. A verification failure permanently disables further fitter writes until reboot. `PF_A_CTL`, `PF_A_VSCALE`, and `PF_A_HSCALE` are never modified.

The resident INT 10h hook watches legacy `AH=00h` and VBE `AX=4F02h` mode sets. The original BIOS handler runs first. Correction is applied only when the post-BIOS `PF_A_SIZE` equals the fixed-raster size detected during installation. Native-resolution VBE modes are left full-screen.
