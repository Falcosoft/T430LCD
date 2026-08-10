# Contributing

Hardware reports and patches are welcome.

Please include:

- Exact laptop model and CPU/GPU configuration.
- DOS version and memory-manager configuration.
- HIMEM version when relevant.
- DPMI host and version when using `BLCSETD` or `ASPECTD`.
- The exact utility and command used.
- The requested PWM value for brightness tests.
- Complete program output.
- Visible result.

Please distinguish clearly between tests of:

- `BLCSET`
- `BLCSETD`
- `BLCINIT`
- `ASPECT`
- `ASPECTD`

Do not test direct MMIO changes on unsupported hardware without a recovery boot method. Keep source changes compatible with Borland TASM syntax unless a separate port is clearly identified.

All DOS build-time paths and filenames must remain 8.3 compatible.
