# Android build (MVP)

## Install on your phone
1. Copy `warhammer40k.apk` to the phone (or download it there).
2. Open it. Android asks to allow "Install unknown apps" for your file manager / browser; allow it.
3. Launch **40K Battle Sim**. It runs landscape and full screen.

Or over USB: `adb install -r warhammer40k.apk`.

Requires a 64-bit (arm64) Android phone. Any phone from ~2017 onwards is fine.

## Touch controls
| Gesture | Does |
|---|---|
| Tap | Left click (double-tap = double click) |
| Drag a model | Move it (tap the unit first to select it, same as desktop) |
| Hold + drag while placing (deploy / disembark) | The model follows your finger; it drops when you lift |
| Drag a model you already placed (deployment) | Pick it up again (desktop: Shift+click) |
| Drag on a list/menu | Scroll it |
| Long-press (~0.5 s) | Right click: unit menu, cancel tape, cancel reposition |
| Hold a model + tap ⟲ ⟳ with a second finger | Turn it 15° per tap (vehicles, non-round bases) |
| Two-finger drag | Pan the board (scrolls if over a list) |
| Pinch | Zoom |
| Back button | Esc (close dialog / cheat sheet) |

Battle toolbar (bottom centre, under game pop-ups): `▾` hide it, `+` `−` zoom,
**Fit** board, **Board** rotate view 90°, **Tape** measure, `⟲` `⟳` rotate model
(Q/E), **All** select the whole unit (Ctrl+A), **Multi** sticky Ctrl (charge
several targets / add models), **Undo** deployment, **Info** datasheet,
**R-tap** next touch is a right-click, **?** touch cheat sheet, **Esc**.

All seven tutorial lessons have touch wording and touch-specific steps.

The UI starts at 1.25× scale on mobile; change it in Settings › UI Scale.

## Build the APK (Linux)
```bash
bash tools/android/setup_android_export.sh   # once: JDK 17, apksigner, templates, keystore
bash tools/android/build_apk.sh              # -> 40k/exports/android/warhammer40k.apk
```
The setup uses Ubuntu's `apksigner`/`zipalign`/`adb` packages instead of the
full Android SDK, which isn't needed for Godot's non-Gradle export.

On macOS: install Android Studio (for the SDK) + JDK 17, set the paths in
Godot › Editor Settings › Export › Android, then use Project › Export ›
Android (preset already configured in `40k/export_presets.cfg`).

## Implementation
- `40k/autoloads/TouchInputAdapter.gd`: gesture → mouse/camera translation + toolbar.
  It auto-enables on touchscreen mobile. For desktop testing, pass `--touch` or call `TouchInputAdapter.set_enabled(true)`.
- Windowed scenarios: `40k/tests/scenarios/sp/touch_mvp_deploy.json`, `touch_mvp_movement.json`, `touch_v2_controls.json`, `tut_t1_touch.json`, `tut_t3_touch_wagon_turn.json`.
