# ASPECTD

T430LCD 2.3 resident DPMI display corrector for the primary Lenovo ThinkPad T430 / Intel HD Graphics 4000 target.

ASPECTD is the DPMI counterpart of `ASPECT`. It is intended for environments where a 32-bit DPMI host such as resident HDPMI32 is available, including the tested JEMM/VSBHDA configuration.

## Display policies

- `/A` — centered 4:3 aspect-ratio correction
- `/C` — pixel-perfect centered mode derived from Pipe A `PIPESRC`

No argument installs with `/A`; if ASPECTD is already resident, no argument reports its current state and selected policy.

## Commands

```dos
ASPECTD
ASPECTD /A
ASPECTD /C
ASPECTD /U
ASPECTD /D
ASPECTD /E
```

`/A` and `/C` may switch policy while ASPECTD is resident when its ownership checks permit a safe immediate update. `/D` deactivates correction and `/E` re-enables the selected policy.

`/U` and `/D` both perform logical deactivation. The DPMI client and interrupt hooks remain resident because the verified HDPMI32 design has no documented safe physical-unload path.

## v2.3 DPMI mappings

ASPECTD retains two 4 KiB MMIO mappings:

1. Fitter A page at `BAR0+68000h` for `PF_A_POS` and `PF_A_SIZE`.
2. Pipe A page at `BAR0+60000h` for read-only `PIPESRC` access in `/C`.

Keeping the Pipe A mapping resident allows later runtime switching from `/A` to `/C`.

## Safety policy

ASPECTD writes only Fitter A position and size, in this order:

1. `PF_A_POS`
2. `PF_A_SIZE`

Every write is verified by immediate readback. A verification failure permanently disables further fitter writes until reboot. `PF_A_CTL`, `PF_A_VSCALE`, `PF_A_HSCALE`, and pipe registers are never modified.

The resident INT 10h hook watches legacy `AH=00h` and VBE `AX=4F02h` mode sets. The original BIOS handler runs first. A successful native VBE mode is no longer bypassed specially: `/A` follows the aspect policy, while `/C` naturally remains pixel-perfect when the source equals the fixed raster.

Normal status output is compact, while installation retains detected output resolution and selected target window/position diagnostics for hardware reports.

## Build

Run:

```dos
BUILD
```

The build script supplies the repository `INCL` directory to TASM. See the main T430LCD documentation for the v2.3 legacy CGA/EGA centered-mode exception and detailed verified behavior.
