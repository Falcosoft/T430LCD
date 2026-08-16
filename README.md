# T430LCD

**LCD Brightness, Aspect-Ratio and Pixel-Perfect Centering Control for the Lenovo ThinkPad T430 under Real MS-DOS**

The tools can also work with other Ivy Bridge/Intel HD Graphics 4000 laptops. The complete utility set has been confirmed working on a Lenovo IdeaPad Yoga 13 with a Core i5-3427U and an HP EliteBook Folio 9470m with a Core i5-3427U.


Aspect ratio corrected DOOM:

<img width="1156" height="651" alt="doom_ar_corrected" src="https://github.com/user-attachments/assets/91dc5051-2819-43cd-a886-4baf82a154a3" />  

Aspect ratio corrected Norton Commander:

<img width="1156" height="651" alt="norton_ar_corrected" src="https://github.com/user-attachments/assets/07afd952-f327-4a82-98b7-af684d500083" />  

Duke Nukem 3D in pixel perfect and centered 1024x768 mode on 1600x900 HD+ LCD:


<img width="1902" height="1296" alt="duke3d_pixelperfect_centered" src="https://github.com/user-attachments/assets/b0154ca8-e5b0-4cd5-9168-cb689a2de39a" />  


>
T430LCD is an open-source collection of utilities that restores modern LCD functionality when running real MS-DOS on a Lenovo ThinkPad T430 with Intel HD Graphics 4000 (Ivy Bridge).

The project provides:

- Interactive LCD brightness control
- Automatic boot-time brightness initialization
- Automatic 4:3 aspect-ratio correction for legacy DOS video modes
- Pixel-perfect centered display mode based on the active Intel display-pipe source raster
- DPMI-compatible brightness and display-correction variants for memory-manager environments
- Reverse-engineering and diagnostic utilities
- Complete technical documentation

---

> [!NOTE]
> **Current release:** **v2.4**
>
> **Implemented**
>
> - ✔ LCD brightness control
> - ✔ CONFIG.SYS brightness driver
> - ✔ DPMI-compatible brightness control for EMM386/JEMM386 systems
> - ✔ Automatic 4:3 aspect-ratio TSR
> - ✔ Pixel-perfect centered `/C` policy
> - ✔ FIR-91 sharp filtering with `/AS` and `/S`
> - ✔ Runtime `/A`, `/AS`, `/S` and `/C` policy switching
> - ✔ Built-in `/?` command help
> - ✔ DPMI-compatible ASPECTD implementation
> - ✔ Internal LCD support
> - ✔ External VGA support
> - ✔ External DVI support
> - ✔ Reverse-engineering diagnostics
> - ✔ Comprehensive documentation

---

## Features

### Brightness

- **BLCSET** – Interactive LCD brightness control for plain DOS
- **BLCSETD** – DPMI-compatible version of BLCSET for systems using EMM386/JEMM386 and a resident 32-bit DPMI host such as HDPMI32
- **BLCINIT** – CONFIG.SYS device driver to set LCD brightness at boot time

### Display fitting

- **ASPECT** – Plain-DOS TSR. With no argument it retains the historical `/A` behavior: centered 4:3 correction with Intel Medium 3×3 filtering. `/AS` uses the same 4:3 geometry with the hardware-verified FIR-91 sharp programmable filter, `/S` applies FIR-91 without changing the current fitter geometry, and `/C` selects pixel-perfect centered mode. `/D` deactivates, `/E` re-enables the selected policy, `/U` safely restores/deactivates before physically unloading, and `/?` shows a short command summary.
- **ASPECTD** – DPMI-compatible counterpart for systems using EMM386/JEMM386 and a resident DPMI host such as HDPMI32. It supports the same `/A`, `/AS`, `/S`, `/C`, `/D`, `/E` and `/?` model; `/U` remains a logical deactivation because the resident DPMI client cannot be safely destroyed later on the verified HDPMI32 path.

In `/C` mode the target is derived from Pipe A `PIPESRC` rather than from a hard-coded DOS resolution. This provides a true centered 1:1 source raster on the fixed internal LCD. Hardware testing also identified narrow legacy compatibility exceptions in `/C`: BIOS modes `00h`/`01h` use 360×400 → 720×400 when that exact Pipe A source is observed, while modes `04h`, `05h` and `0Dh` use 320×400 → 640×400. In both cases only the missing horizontal doubling is supplied.

### Diagnostic Utilities

Brightness:

- BLCPWM
- OPREGPM

Display fitting:

- FITREAD
- PFDIAG
- PFSNAP

---

## Supported Hardware

The current project has been verified on:

| Hardware | Internal LCD | Status |
|----------|--------------|--------|
| Lenovo ThinkPad T430 | 1600×900 | ✅ Fully verified primary platform; v2.4 `/A`, `/AS`, `/S` and `/C` development/testing platform |
| Lenovo IdeaPad Yoga 13, Core i5-3427U / Intel HD 4000 | 1600×900 | ✅ Complete utility set confirmed working |
| HP EliteBook Folio 9470m, Core i5-3427U / Intel HD 4000 | 1366×768 | ✅ Complete utility set confirmed working |
| Dell Inspiron E5550 / Intel HD Graphics 5500 (Broadwell) | 1920×1080 | ✅ ASPECT confirmed; BLCSET does not work |
| Intel HD Graphics 4000 (Ivy Bridge) | — | ✅ Verified on the systems above |
| External VGA monitor on T430 | — | ✅ Verified |
| External DVI monitor on T430 | — | ✅ Verified |

The **ThinkPad T430 remains the primary fully documented and officially supported platform**. The IdeaPad Yoga 13 and EliteBook Folio 9470m are community-confirmed compatible with the complete T430LCD utility set. ASPECT has additionally been confirmed on a Broadwell Dell Inspiron E5550 with Intel HD Graphics 5500, but BLCSET does not work on that system. The detailed v2.3 centered-mode regression matrix is from the T430.

Confirmed `/A` internal-LCD geometry:

- ThinkPad T430, 1600×900 → **1200×900**, centered at **X=200, Y=0**
- IdeaPad Yoga 13, 1600×900 → **1200×900**, centered at **X=200, Y=0**
- EliteBook Folio 9470m, 1366×768 → **1024×768**, centered at **X=171, Y=0**
- Dell Inspiron E5550 / Intel HD Graphics 5500, 1920×1080 → **1440×1080**, centered at **X=240, Y=0** (ASPECT confirmed)

The v2.4 `/C` implementation was additionally tested on the T430 with standard VGA, CGA/EGA legacy modes, VESA modes and non-standard VGA-register-compatible modes. The 640×200 and 640×350 CGA/EGA-family modes worked without special handling; the 320-wide legacy BIOS modes `04h`, `05h` and `0Dh` use the narrow 320×400 → 640×400 horizontal-only correction described above.

---

## Repository Layout

```text
T430LCD/
│
├── TOOLS/      End-user utilities
├── DIAG/       Reverse-engineering diagnostics
├── INCL/       Shared include files
├── BIN/        Optional compiled binaries
└── docs/       Project documentation
```

---

## Documentation

- [User Guide](docs/UserGuide.md)
- [Reverse Engineering](docs/ReverseEngineering.md)
- [Intel Registers](docs/IntelRegisters.md)
- [Design Notes](docs/DesignNotes.md)
- [Development History](docs/DevelopmentHistory.md)
- [Contributing](CONTRIBUTING.md)
- [Coding Conventions](CODING.MD)
- [Hardware Tests](HARDWARE_TESTS.md)

---

## Building

Requirements:

- Borland Turbo Assembler (TASM)
- Borland TLINK

Build everything:

```dos
BUILDALL
```

Clean generated files:

```dos
CLEANALL
```

Every utility also contains its own `BUILD.BAT` and `CLEAN.BAT`.

---

## Design Philosophy

- Perform read-only diagnostics before modifying hardware.
- Modify only the smallest verified register set.
- Keep hardware-sensitive code explicit and easy to audit.
- Validate every change on real hardware.
- Preserve diagnostic output needed for useful hardware reports.
- Preserve all reverse-engineering tools and documentation.

---

## Compatibility

Verified with:

- MS-DOS
- PC DOS
- FreeDOS

Brightness-tool compatibility:

- **BLCSET** is intended for plain DOS where its direct protected-mode MMIO path is available.
- **BLCSETD** provides the same interactive PWM duty control through DPMI and has been verified with JEMM386/HDPMI32.
- **BLCINIT** remains suitable for CONFIG.SYS use before EMM386/JEMM386 is loaded.

Display-correction TSR compatibility:

- **ASPECT** is intended for plain DOS without EMM386/JEMM386. No argument defaults to `/A`. `/A` selects 4:3 correction with Medium 3×3 filtering, `/AS` selects the same geometry with FIR-91 sharp filtering, `/S` selects FIR-91 filtering without changing geometry, `/C` selects pixel-perfect centering, `/D` deactivates, `/E` re-enables the selected policy, `/U` first performs the safe `/D` restore/deactivation path before physical unload, and `/?` prints help.
- **ASPECTD** provides the same policy model in DPMI environments and has been verified with JEMM386/HDPMI32. `/U` remains equivalent to `/D` and does not physically remove the resident DPMI client.

---

## External Links

- Latest Releases: https://github.com/Falcosoft/T430LCD/releases
- Repository: https://github.com/Falcosoft/T430LCD
- VOGONS discussion: https://www.vogons.org/viewtopic.php?t=111978

---

## License

Released under the **MIT License**.

See [LICENSE](LICENSE).

---

## Development and attribution

This project was developed through an interactive collaboration:

- Zoltán Bacskó: problem definition, hardware investigation, compilation, testing on physical hardware, validation, and project maintenance.
- OpenAI ChatGPT (GPT-5.6): software implementation, debugging analysis, source-code generation, refactoring, and documentation drafting.

The code did not emerge as a one-shot generation. It was refined through repeated experiments on real Ivy Bridge hardware.

---

## Version History

### v2.4

Major additions since v2.3:

- Added `/AS`, which keeps the proven `/A` 4:3 geometry but replaces Intel Medium 3×3 filtering with the hardware-verified FIR-91 programmable sharp filter.
- Added `/S`, which applies the same FIR-91 filter while preserving the current fitter position and size.
- Added `/?` short command help to ASPECT and ASPECTD.
- Added verified programming of the Ivy Bridge PF0 horizontal and vertical coefficient tables at `680A0h/680A4h` and `680B0h/680B4h`.
- FIR-91 uses the symmetric 4.4921875% / 91.015625% / 4.4921875% kernel for all phases.
- Sharp-mode table writes and filter-selector changes are read back and verified; any verification failure disables further writes for safety.
- Leaving `/AS` or `/S` restores Intel Medium 3×3 filtering while preserving unrelated `PF_A_CTL` bits.
- Refined the old `PF_A_CTL` rule: arbitrary/full-register rewrites remain unsafe, but v2.4 deliberately changes only the verified filter-selector bits required for `/AS` and `/S`. `PF_A_VSCALE` and `PF_A_HSCALE` remain untouched.
- Added the `/C` 40×25 text-mode compatibility fix: BIOS modes `00h`/`01h` use 360×400 → 720×400 only when that exact Pipe A source geometry is observed.
- Reduced ASPECT resident memory by reusing the otherwise-unused PSP area below `0100h` as the private interrupt stack and by replacing large literal FIR tables with compact generated templates.

### v2.3

Major additions since v2.2:

- Added `/A` as the explicit 4:3 policy selector to both ASPECT and ASPECTD.
- Added `/C` pixel-perfect centered mode based on Pipe A `PIPESRC`.
- Added safe live switching between `/A` and `/C` when the current fitter state is owned by the TSR or is the saved fixed raster.
- Removed the old native-resolution VBE bypass. `/A` now consistently applies the 4:3 policy to successful native VBE modes; `/C` naturally preserves a native source at 1:1 full screen.
- Added the hardware-verified horizontal-only compatibility correction for legacy BIOS modes `04h`, `05h` and `0Dh` when `PIPESRC` is exactly 320×400.
- Updated ASPECTD to keep a second read-only DPMI MMIO mapping for the Pipe A source page.
- Changed ASPECT `/U` to execute the safe `/D` restore/deactivation operation before physical unload.
- Shortened normal TSR status text while retaining detected output resolution and selected target window/position diagnostics.

### v2.2

Major additions since v2.1:

- `BLCSETD` DPMI-compatible interactive LCD brightness control
- Added `/D` and `/E` runtime control to `ASPECT` while retaining `/U` as true physical unload
- Refactored `ASPECT` to reduce its resident memory footprint
- Extended JEMM386/HDPMI32 support to interactive brightness adjustment

### v2.1

Major additions since v2.0:

- `ASPECTD` DPMI-compatible automatic aspect-ratio TSR
- JEMM386/HDPMI32 support for automatic aspect-ratio correction in protected-mode DOS environments

### v2.0

Major additions since v1.0:

- `BLCINIT` CONFIG.SYS brightness driver
- `ASPECT` automatic aspect-ratio TSR
- Complete reverse-engineering diagnostic suite
- Comprehensive documentation
- Modular repository organization
- DOS-native build system
- Project coding conventions

---

Contributions, hardware test reports, bug reports, and suggestions are always welcome.
