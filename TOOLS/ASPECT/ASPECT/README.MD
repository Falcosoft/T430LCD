# ASPECT

T430LCD 2.3 plain-DOS resident display corrector.

ASPECT supports two policies:

- `/A` — centered 4:3 aspect-ratio correction
- `/C` — pixel-perfect centered mode derived from Pipe A `PIPESRC`

No argument defaults to `/A`.

## Commands

```dos
ASPECT
ASPECT /A
ASPECT /C
ASPECT /D
ASPECT /E
ASPECT /U
```

`/A` and `/C` may also switch policy while the TSR is resident when the fitter ownership checks allow a safe immediate update. `/D` deactivates correction, and `/E` re-enables the selected policy.

`/U` is a true physical unload. In v2.3 it first performs the same safe restore/deactivation operation as `/D`; the TSR is not removed if that operation cannot complete safely. ASPECT also verifies that it still owns `INT 10h` and `INT 2Fh` before restoring the saved vectors.

Normal output is intentionally compact, but installation retains the detected output resolution and selected target window/position diagnostics because these are useful for hardware reports.

## Build

Run:

```dos
BUILD
```

The build script supplies the repository `INCL` directory to TASM.

See the main T430LCD documentation for the v2.3 legacy CGA/EGA centered-mode exception, supported hardware, external-output safety rules, and MMIO write policy.
