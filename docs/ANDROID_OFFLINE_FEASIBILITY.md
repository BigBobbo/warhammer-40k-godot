# Android (Offline) Feasibility Plan

**Date:** 2026-07-12
**Question:** Can this game be played on an Android phone, offline? What would it take?
**Verdict:** **Yes — feasible and reasonable.** The engine-level port is nearly free (Godot 4.6
exports to Android natively, and the project already uses the mobile-friendly GL Compatibility
renderer with mobile texture compression enabled). The game is already fully offline-capable for
its main modes (Human vs AI, local hotseat). The real cost is **not** the port — it is the
**touch input model** and, above all, the **UI/text scale rework** you already suspected.
Roughly: getting a playable-but-clunky APK on your phone is days of work; making it genuinely
pleasant to play on a 6-inch screen is a multi-week UI project.

Everything below is aspect-by-aspect: what the codebase does today (with file references), why it
matters for Android, what has to change, and how much work that is.

---

## 0. What I did and did not validate

Per project rules, claims vs. facts:

- **Verified against the codebase** (read the actual files): renderer settings, texture import
  flags, stretch mode, every autoload's network usage, input handling (mouse buttons, keyboard
  shortcuts, absence of touch handlers), font-size overrides (histogram below), HUD layout
  anchors, save paths, MCP server gating, export presets.
- **Not validated** (no Android SDK in this container, and no physical device available to any
  session): an actual Android export build, on-device performance, and on-device behavior of
  CloudStorage when the network is absent. These are called out inline as "verify" items —
  none of them looks like a blocker, but they are assumptions until a build runs on a phone.

---

## 1. What is already in your favor

These are facts of the current project, not aspirations:

| Aspect | Current state | Why it helps Android |
|---|---|---|
| Renderer | `gl_compatibility`, incl. explicit `renderer/rendering_method.mobile="gl_compatibility"` (`40k/project.godot` [rendering]) | This is exactly the renderer Godot recommends for Android. No renderer migration needed. |
| Texture compression | `import_etc2_astc=true` already set | ETC2/ASTC is the Android GPU format. Assets are already being imported in a mobile-compatible form. |
| Stretch mode | `canvas_items` + `expand` at 1920×1080 base | The whole UI already scales to arbitrary window sizes/aspects — the scaling *mechanism* exists; only the *proportions* are wrong for phones (see §5). |
| Offline game modes | Main menu has Human/AI dropdowns per player (`MainMenu.gd:339-345`, default is Human vs AI); hotseat Human vs Human is the base mode | The primary single-player experience needs **zero network**. Multiplayer is a separate, optional path. |
| Game data | All rules data, armies, missions, terrain are local JSON under `res://data/`, `res://armies/` (~11 MB + ~0.5 MB), loaded via `FileAccess` | Fully bundled into the APK; nothing is fetched at runtime to play. |
| Saves | `user://` paths throughout (`SaveLoadManager`, `ArmyListManager`) | `user://` maps to app-private storage on Android automatically. Save/load works unchanged. |
| Performance envelope | The game already ships as a **Web export** (itch.io preset in `export_presets.cfg`) and runs under Mesa llvmpipe *software* rendering in CI | A game that runs in a browser and on a software rasterizer will not stress a modern phone GPU. It's a 2D board with ~38 custom-draw scripts — light by mobile standards. |
| Project size | ~121 MB working tree, but the shippable parts (data + fonts + scripts + scenes + textures) are ~30 MB | Expected APK ≈ 60–90 MB including the Godot runtime. No asset-size problem, no expansion files needed. |

**Bottom line:** there is no architectural blocker. This is a 2D, turn-based, mouse-driven desktop
game — the friendliest possible genre to port.

---

## 2. Build & export pipeline

**What's needed** (one-time setup, per [Godot 4.6 Android export docs](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_android.html)):

1. **JDK 17** and the **Android SDK** (installable via Android Studio or command-line tools;
   Platform-Tools ≥ 35).
2. **Godot Android export templates** (Editor → Manage Export Templates, same as the macOS ones).
3. An **Android export preset** in `export_presets.cfg` (currently only macOS and Web exist).
4. A **debug keystore** (auto-generated) for sideload builds; a proper release keystore only if/when
   publishing.

**Effort:** ~half a day. This can also be put in GitHub Actions (there are maintained
`godot-export` actions) so every push produces an APK artifact you download straight to your
phone — worth doing early, since neither of us has an Android device attached to a dev machine.

**Distribution choice:**
- **Sideload the APK** (recommended for you): install directly, no store, no review, no target-API
  compliance clock, updates by downloading the new APK. This matches the "play it myself" goal.
- **Google Play** (only if you ever want public distribution): requires AAB format, release
  signing, Play Console account, and meeting Google's current target-API requirement. This adds
  ongoing maintenance burden and is **not** needed for the stated goal. Defer indefinitely.

---

## 3. Offline capability — audit of every network touchpoint

The game has four network-flavored autoloads. None of them should block offline play, but two need
explicit gating for a clean Android build:

| Autoload | What it does | Offline impact | Action |
|---|---|---|---|
| `CloudStorage.gd` | On `_ready()`, picks a server URL (fly.dev in web builds, `localhost:9080` otherwise!) and fires a player-registration HTTP request | Requests are async via `HTTPRequest`; failure emits a `request_failed` signal rather than blocking. **But** note the desktop/Android default URL is `localhost:9080` — on a phone that's guaranteed dead. Startup *should* proceed fine (verify on first build). | Feature-flag it off entirely on mobile (`OS.has_feature("android")`), or make cloud saves an explicit opt-in. Local saves already work without it. |
| `WebSocketRelay.gd` | Connects to the relay server **only when online multiplayer is initiated** — `_ready()` just computes the URL | None for offline play | No change needed; the Multiplayer menu button can be hidden or left as-is (it will simply fail to connect without network). |
| `NetworkManager.gd` | ENet/LAN multiplayer, connection driven by user action | None for offline play | No change needed. |
| `MCPServer` (`addons/godot_mcp/mcp_server.gd`) | **Listens on TCP 127.0.0.1:9080 even in exported builds** unless the env var `GODOT_MCP_DISABLED=1` is set — and you cannot set env vars for an Android app | Not a play blocker, but a dev tool must not ship in a phone build (it also collides with CloudStorage's localhost port assumption) | Gate it: skip `listen()` when `OS.has_feature("android")` (or exclude the addon via export preset filters, along with `gut` and the `tests/` tree — this also shrinks the APK). |

**Conclusion:** offline is essentially already true. The work is ~1 day of gating + verifying the
first build boots with airplane mode on.

---

## 4. Input — the first real gap (touch vs mouse/keyboard)

**Current state (verified):** there are **zero** `InputEventScreenTouch` / `InputEventScreenDrag`
handlers in game scripts. The entire game is mouse + keyboard:

- **Left-click / left-drag** — select, place, and drag models (`MovementController`,
  `DeploymentController`, etc.).
- **Right-click** — four distinct uses: model **rotation** during moves
  (`MovementController.gd:1912`), **cancel repositioning** (`DeploymentController.gd:125`),
  cancel in `DisembarkController.gd:371`, and a **context menu** for unit color/label editing
  (`Main.gd:5139`).
- **Keyboard-only camera**: pan is WASD/arrows, zoom is `+`/`-` (`Main.gd:5535-5560`). There is
  **no mouse-wheel zoom and no drag-pan** — meaning on a phone there would be *no way to move the
  camera at all* without new code.
- **~20 single-key hotkeys** gate whole features: `U` army panel, `I` datasheet, `S` stratagems,
  `V` VP timeline, `G` grid, `A` auras, `F` fit-to-board, `Tab`, `?` help, quick save/load, etc.
  (`Main.gd:5112-5260`). Some of these have button equivalents in panels; several do not.

**What Godot gives you for free:** `emulate_mouse_from_touch` is on by default, so one-finger tap
and drag arrive as left-click events. **Selecting, placing, and dragging models will work on day
one with no code changes.** That's the majority of moment-to-moment gameplay.

**What must be built (in priority order):**

1. **Touch camera** — two-finger pan + pinch zoom (`InputEventMagnifyGesture`/`InputEventPanGesture`
   are delivered natively on Android, plus a manual two-touch fallback). This is the single most
   important new feature; without it the game is unplayable on a phone. ~1–2 sessions including
   tuning.
2. **Right-click alternatives** — long-press is the standard mobile idiom and maps cleanly to all
   four uses (long-press = rotate handle / cancel / context menu). Alternatively, model rotation
   deserves a proper on-screen rotation handle, which would improve desktop too. ~1–2 sessions.
3. **Hotkey surfacing** — every hotkey-only feature needs a button. Most panels already have
   toggle buttons in the HUD; audit `Main.gd`'s key handler list against on-screen affordances and
   add a compact toolbar for the gaps. ~1–2 sessions, overlaps naturally with the UI rework in §5.
4. **Hover-dependent UI** — 19 scripts use `mouse_entered`/tooltips. Tooltips simply don't exist
   on touch; anything where a tooltip is the *only* way to get the information needs a tap-to-show
   fallback (the datasheet popup pattern already in the game covers most of this). ~1 session of
   audit + fixes.

**Effort total: roughly 4–6 focused sessions.** None of it is hard; it's all well-trodden mobile
UX territory, and all of it is testable in the existing windowed-scenario harness (touch events
can be synthesized the same way `simulate_click` works today).

---

## 5. Text size and screen real estate — the big one (you were right)

This is where your instinct is exactly correct, and it's worth being concrete about *why*.

**The numbers (measured from the codebase):**

- The UI hardcodes font sizes via ~900 `font_size` overrides across `scripts/` and `dialogs/`
  (88 in `Main.gd` alone, 49 in `MathhammerUI.gd`, 44 in `CommandController.gd`, …).
- The distribution is dominated by small sizes: **~550 of them are 10–14 px**, at a 1920×1080
  design canvas. Sizes 9 px and below also appear.
- Physical reality: a 6.4-inch phone in landscape is ~140 mm wide. With the 1080p canvas stretched
  across it, one canvas pixel ≈ 0.07 mm, so **12 px text renders ~0.9 mm tall**. Android's
  accessibility floor for body text (~12 sp) is ≈ 1.9 mm — the game's typical text would be
  **less than half the minimum readable size**. This isn't a tuning issue; it's flatly unreadable.
- Touch targets have the same problem: buttons specced at `custom_minimum_size` 120×30 / rows of
  32 px (`scenes/Main.tscn`) render ~2 mm tall vs. Android's 48 dp ≈ 9 mm guideline — **4× too
  small to tap reliably.**

**Why the "easy fix" isn't enough on its own:** Godot lets you scale everything uniformly with one
line (`window.content_scale_factor = 2.0`). Text becomes readable — but the effective canvas
shrinks to ~960×540, and the HUD's two **fixed 400 px side panels** (`Main.tscn` anchors, verified)
would then eat 800 of those 960 px, leaving a sliver of board. Uniform scaling makes text readable
and the *layout* impossible. So the real work is layout, not fonts.

**Recommended strategy — three tiers, in order:**

1. **Global scale infrastructure (cheap, do first).** Add a `UIScale` autoload that computes a
   scale factor from `DisplayServer.screen_get_dpi()`/screen size and applies
   `content_scale_factor` on mobile. Route new code through it. Landscape-only orientation lock
   (portrait is hopeless for a wide battlefield and shouldn't be attempted). ~1 session.
2. **Mobile HUD layout (the core work).** The desktop layout is
   left-panel + board + right-panel + bottom-bar, all visible simultaneously. A phone gets *one*
   of those at a time. The standard pattern, and the right one here:
   - Side panels become **slide-in drawers / bottom sheets**, toggled by a persistent edge toolbar,
     fullscreen-width when open, with 48 dp rows.
   - The bottom action bar (phase actions: End Move, Confirm, etc.) stays permanently visible but
     grows to thumb size — it is the primary interaction surface.
   - Dialogs (`dialogs/` — attack assignment, fight selection, save/load, …) go fullscreen on
     mobile instead of floating windows.
   - Since panel *content* is built in code (`HBoxContainer`/`VBoxContainer` with those font-size
     overrides), the overrides need to be swept to scale-aware values — mechanical but broad
     (~30 files). A `theme`-based approach (one mobile theme with larger default sizes, deleting
     redundant per-node overrides) cuts this down and improves the desktop codebase too.
   - **Effort: 3–5 weeks of sessions.** This is 70–80 % of the whole Android project. It can land
     incrementally (phase by phase: deployment first, then movement, shooting, …) behind an
     `is_mobile` branch so desktop is untouched.
3. **Density triage (ongoing polish).** Some screens are intrinsically information-dense
   (Mathhammer, unit stat cards, weapon tables). On mobile these become scrollable/tabbed rather
   than shrunk. Do these last, driven by actual play on your phone.

**Alternative considered and rejected:** shipping with uniform 1.5× scale and no layout work
("squint mode"). It would technically run, but text at ~1.3 mm with 3 mm buttons fails the point
of the exercise — you'd try it twice and never again. If the layout work is out of budget, the
honest answer is *don't ship Android* rather than ship that.

---

## 6. Housekeeping items (small, necessary)

- **Export filters:** exclude `addons/gut/`, `addons/godot_mcp/`, `tests/`,
  `tests_archived_disabled/`, `test_results/`, `*.md` from the Android preset (`export_filter`
  currently ships `all_resources`). Smaller APK, no dev tooling on device.
- **Quit button:** Android apps don't self-quit via button (`MainMenu` QuitButton) — hide on mobile.
- **Back gesture:** map Android back (`ui_cancel` / `NOTIFICATION_WM_GO_BACK_REQUEST`) to the
  existing ESC behavior (close panel → cancel action), which `Main.gd:5070` already centralizes.
- **Debug logging:** `DebugLogger` writes to `user://logs/` — works on Android and stays useful
  (retrievable via the in-game log or `adb`). Keep it.
- **Custom army import:** `ArmyListManager` reads extra armies from `user://armies/` — on Android
  that folder isn't user-visible. Eventually add an "import army JSON" flow via the OS file picker;
  bundled armies work regardless. Low priority.
- **Screen sleep:** long turn-based sessions need `DisplayServer.screen_set_keep_on(true)`.
- **Multiplayer on Android** (bonus, not in scope of "offline"): the WebSocket relay path is
  platform-agnostic and should work when the phone *is* online — a free extra once the port exists.

---

## 7. Phased plan with effort estimates

| Phase | Deliverable | Contents | Effort |
|---|---|---|---|
| **0 — Proof of concept** | APK on your phone, boots to menu, can fumble through a turn | Android SDK/JDK setup or CI action, export preset, MCP/GUT excluded, CloudStorage gated, orientation lock, verify airplane-mode boot | 2–4 sessions |
| **1 — Playable** | Full Human-vs-AI game finishable by touch, ugly but functional | Pinch zoom + two-finger pan, long-press for right-click roles, hotkey→button audit, back-gesture, keep-screen-on | 4–6 sessions |
| **2 — Readable (the big one)** | Text and targets at Android-normal sizes; drawer-based HUD | `UIScale` + mobile theme, side panels → drawers, thumb-sized action bar, fullscreen dialogs, font-size override sweep, phase-by-phase rollout | 3–5 weeks of sessions |
| **3 — Polish** | "Actually nice on the couch" | Density triage of stat/math screens, tooltip fallbacks, haptics on dice rolls, icon/splash, optional Play Store track | open-ended, on demand |

Phases 0 and 1 are low-risk and independently valuable: after Phase 1 you can genuinely (if
squintingly) play offline on the phone, and every Phase 2 improvement is immediately testable on
real hardware.

**Testing note:** the project's windowed-scenario gate extends to this work — scenarios can run at
a phone-shaped window (e.g. 2400×1080 logical) with synthesized touch events in CI, so mobile
layouts get regression coverage without a device farm. On-device checks stay manual on your phone
via sideloaded builds.

---

## 8. Risks and open questions

1. **On-device performance** — *low risk.* Evidence (web build, llvmpipe CI) is strong but
   indirect; Phase 0 answers it definitively. The 38 `_draw()`-based visuals and the LoS
   calculations are the only CPU-ish suspects, and they're already fine on weaker targets.
2. **CloudStorage offline startup** — *low risk, must verify.* Async and signal-based, but the
   first airplane-mode boot in Phase 0 should explicitly confirm no startup stall.
3. **UI rework scope creep** — *the real risk.* Phase 2 touches most player-facing scripts. The
   mitigations are the mobile-theme approach (delete overrides rather than edit them), an
   `is_mobile` branch keeping desktop untouched, and phase-by-phase delivery.
4. **Two UIs to maintain** — every future feature needs a desktop and a mobile presentation pass.
   The theme/drawer infrastructure minimizes this, but it is a permanent tax; worth accepting
   consciously before starting Phase 2.

---

## 9. Final answer

**Feasible, and reasonably so — with one honest caveat.** The port itself (build, offline, data,
saves, rendering) is almost trivially achievable because the project already made the right
choices (GL Compatibility, ETC2/ASTC imports, local JSON data, `user://` saves, an offline AI
opponent). Touch input is a modest, well-understood addition. The text-size problem you flagged is
real, measurably severe (typical text would render at under half of Android's minimum readable
size, touch targets at a quarter of the guideline), and is *the* cost center: fixing it properly
means a drawer-based mobile HUD and a font/theme sweep — several weeks, not several days. If that
UI investment isn't worth it, stop after Phase 1 (or don't start); shipping the desktop layout
shrunk onto a phone is the one outcome that would genuinely not be reasonable.

**Sources:**
- [Exporting for Android — Godot Engine 4.6 documentation](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_android.html)
- [Exporting for Android — Godot Engine (stable) documentation](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html)
