# Verified Hardware

| System | Internal LCD | Status |
|--------|--------------|--------|
| Lenovo ThinkPad T430 + Intel HD 4000 | 1600×900 | Fully verified primary platform |
| Lenovo IdeaPad Yoga 13 + Core i5-3427U / Intel HD 4000 | 1600×900 | All utilities confirmed working |
| HP EliteBook Folio 9470m + Core i5-3427U / Intel HD 4000 | 1366×768 | All utilities confirmed working |

The IdeaPad Yoga 13 and EliteBook Folio 9470m results are community hardware reports confirming operation of the complete T430LCD utility set.

## Verified ASPECT internal-LCD geometry

| System | Native fitter size | Corrected 4:3 window | Position | Confirmation |
|--------|--------------------|------------------------|----------|--------------|
| Lenovo ThinkPad T430 | 1600×900 | 1200×900 | X=200, Y=0 | Fully verified during development |
| Lenovo IdeaPad Yoga 13 | 1600×900 | 1200×900 | X=200, Y=0 | All utilities confirmed working |
| HP EliteBook Folio 9470m | 1366×768 | 1024×768 | X=171, Y=0 | User feedback and screenshots confirm correct ASPECT output |

The 9470m result is especially useful because it confirms ASPECT's dynamic geometry calculation on a 1366×768 fixed-raster panel rather than only the 1600×900 geometry used by the T430 and Yoga 13.

## Verified display paths

The detailed display-path results below are from the primary ThinkPad T430 validation platform.

| Output | Result |
|--------|--------|
| Internal LCD 1600×900 | Brightness ✓ Aspect ✓ |
| External VGA 1680×1050 | BIOS timings preserved ✓ |
| External DVI 1680×1050 | Already 4:3 for legacy modes ✓ |

Detailed PFSNAP/output-path logs for the Yoga 13 and EliteBook Folio 9470m are not yet recorded here.
