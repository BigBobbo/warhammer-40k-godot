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
| Drag on a list/menu | Scroll it |
| Long-press (~0.5 s) | Right click: unit menu, cancel tape, cancel reposition |
| Long-press, keep holding + drag | Right-drag: rotate a vehicle / non-round base |
| Two-finger drag | Pan the board (scrolls if over a panel) |
| Pinch | Zoom |
| Back button | Esc (close dialog) |

Battle toolbar (bottom centre): `+` `−` zoom, **Fit** board, **Tape** measure,
`⟲` `⟳` rotate model (Q/E), **Undo** deployment, **R-tap** (next touch is a
right-click), **Esc**.

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
- Windowed scenarios: `40k/tests/scenarios/sp/touch_mvp_deploy.json`, `touch_mvp_movement.json`.
