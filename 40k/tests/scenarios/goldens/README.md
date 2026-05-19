# Pinned goldens for the visual-regression loop

Each PNG is the blessed reference frame for one (scenario, step) pair.
Filenames mirror the runner output: `<scenario_id>_step_NN_<act>.png`.
Comparison is grid pHash (3×3 tile breakdown, 64-bit pHash per tile,
max-tile distance vs threshold) with per-scenario overrides in
`_thresholds.json`. See `scripts/loop/golden_diff.py`.

## Per-platform layout

Goldens live in **platform-specific subdirectories**:

```
goldens/
  linux-xvfb/    ← cloud runner / CI goldens
  linux-native/  ← Linux dev with X11 or Wayland session
  darwin/        ← macOS (Metal)
  win32/         ← Windows
  _thresholds.json
  README.md
```

The diff path tries the current platform's subdirectory first and
falls back to the legacy `goldens/<filename>.png` (platform-agnostic)
if nothing platform-specific is blessed. Bless always writes to the
current platform's subdirectory.

Platform auto-detection uses `sys.platform` + `XDG_SESSION_TYPE`. To
override (e.g. forcing `linux-xvfb` semantics on a CI runner that
sets `XDG_SESSION_TYPE`), set the `GOLDENS_PLATFORM` env var.

Why per-platform? Font hinting, anti-aliasing, and subpixel-rendering
choices differ between Linux+xvfb, macOS Metal, and Windows D3D. A
golden captured on the cloud runner will show Hamming distances >0
against a screenshot taken on macOS even with no underlying code
change. Per-platform directories let each platform have its own
baseline.

## Adding/updating a golden

```sh
bash scripts/loop/run_one_scenario_loop.sh --bless <scenario.json>
```

This writes to `goldens/<platform>/<filename>.png` for whatever
platform you're running on. To bless for multiple platforms, run
once on each.

## Removing a golden

```sh
rm 40k/tests/scenarios/goldens/<platform>/<scenario_id>_step_*.png
```

Then re-run the loop. The `missing_golden` status is non-fatal — the
loop exits green and reports which step has no baseline for the
current platform.

## Migration history

Before 2026-05-19, goldens lived directly in `goldens/` with no
platform subdirectory. The 217 goldens captured on the cloud runner
were moved to `goldens/linux-xvfb/`. The diff path's fallback
behaviour means scenarios with un-migrated goldens elsewhere
continue to work (compared against the legacy path).
