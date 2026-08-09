# T430LCD

**LCD Brightness and Aspect Ratio Control for the Lenovo ThinkPad T430 under Real MS-DOS**

<img width="1156" height="651" alt="doom_ar_corrected" src="https://github.com/user-attachments/assets/91dc5051-2819-43cd-a886-4baf82a154a3" />
<img width="1156" height="651" alt="norton_ar_corrected" src="https://github.com/user-attachments/assets/07afd952-f327-4a82-98b7-af684d500083" />

T430LCD is an open-source collection of utilities that restores modern LCD functionality when running real MS-DOS on a Lenovo ThinkPad T430 with Intel HD Graphics 4000 (Ivy Bridge).

The project provides:

- Interactive LCD brightness control
- Automatic boot-time brightness initialization
- Automatic 4:3 aspect ratio correction for legacy DOS video modes
- Reverse-engineering and diagnostic utilities
- Complete technical documentation

---

> [!NOTE]
> **Current release:** **v2.1**
>
> **Implemented**
>
> - ✔ LCD brightness control
> - ✔ CONFIG.SYS brightness driver
> - ✔ Automatic aspect-ratio TSR
> - ✔ DPMI-compatible aspect-ratio TSR for EMM386/JEMM386 systems
> - ✔ Internal LCD support
> - ✔ External VGA support
> - ✔ External DVI support
> - ✔ Reverse-engineering diagnostics
> - ✔ Comprehensive documentation

---

## Features

### Brightness

- **BLCSET** – Interactive LCD brightness control
- **BLCINIT** – CONFIG.SYS device driver to set LCD brightness at boot time

### Aspect Ratio

- **ASPECT** – TSR that automatically restores the correct 4:3 aspect ratio for legacy DOS text and graphics modes
- **ASPECTD** – DPMI-compatible version of ASPECT for systems using EMM386/JEMM386 and a resident DPMI host such as HDPMI32

### Diagnostic Utilities

Brightness:

- BLCPWM
- OPREGPM

Aspect ratio:

- FITREAD
- PFDIAG
- PFSNAP

---

## Supported Hardware

The current release has been verified on:

| Hardware | Status |
|----------|--------|
| Lenovo ThinkPad T430 | ✅ Verified |
| Intel HD Graphics 4000 (Ivy Bridge) | ✅ Verified |
| Internal 1600×900 LCD | ✅ Verified |
| External VGA monitor | ✅ Verified |
| External DVI monitor | ✅ Verified |

At present, **only the Lenovo ThinkPad T430 is officially supported.**

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
- [Contributing](docs/Contributing.md)
- [Coding Conventions](CODING.MD)
- [Hardware Tests](HARDWARE_TESTS.md)
- [Known Limitations](KNOWN_LIMITATIONS.md)

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
- Preserve all reverse-engineering tools and documentation.

---

## Compatibility

Verified with:

- MS-DOS
- PC DOS
- FreeDOS

Aspect-ratio TSR compatibility:

- **ASPECT** is intended for plain DOS without EMM386/JEMM386.
- **ASPECTD** provides the same automatic aspect-ratio correction in DPMI environments and has been verified with JEMM386/HDPMI32.

See [Known Limitations](KNOWN_LIMITATIONS.md).

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
  - OpenAI ChatGPT (GPT-5.6 Thinking): software implementation, debugging analysis, source-code generation, refactoring, and documentation drafting.

The code did not emerge as a one-shot generation. It was refined through repeated experiments on a real ThinkPad T430.

---

## Version History

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
