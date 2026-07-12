# Visual Polish — Session Handoff

Continuation notes for the battlefield visual-polish work. Written after Tiers 1
and 2 shipped; the previous session's context grew too large (accumulated
full-res screenshots exceeded the API request cap) so this is a clean restart.

## Status: what is DONE and merged to `main`

All merged via **PR #572** (`claude/game-visual-polish-review-dpg715`). `main`
is now at version `0.30.0` (other people's PRs moved it past ours).

**Tier 1 — fixes & tuning** (changelog `0.26.0`):
- Opaque HUD panels — board tokens/zone fills no longer bleed through the
  right/bottom panels. (`Main.gd` `_fix_hud_layout`, `WhiteDwarfTheme.gd`
  `create_panel_style` → alpha 1.0.)
- `SettingsService.unit_style_changed` signal → `TokenVisual` redraws on style
  switch immediately (was: only on hover).
- One name plate per unit (`TokenVisual._is_unit_label_anchor`) — 17-model mobs
  no longer print 17 overlapping labels.
- Terrain id labels + LoS badges are debug-only behind
  **Settings → Visual → Terrain Debug Labels** (`SettingsService.terrain_debug_labels`,
  `TerrainVisual._debug_labels_enabled`).
- Dice pips in the weapon-resolution dialog (`NextWeaponDialog` uses
  `DiceRowVisual`); empty "Resolution Start" block removed.
- Overlay tuning: `RangeCircle` no fill (outline+label only), deployment-zone
  fill alpha 0.65→0.30 (`Main.update_deployment_zone_visibility`), shooting
  target highlights are thin per-base rings (`ShootingController._create_target_highlight`).
- Scenario: `40k/tests/scenarios/sp/tier1_visual_polish.json` (26/26 pass).

**Tier 2 — sprite assets** (changelog `0.27.0`):
- `40k/assets/tilepack/` — CC0 Kenney subset (tank bodies/turrets ×5 colorways,
  crates, barrels, sandbags, trees, oil-spill, barricades, explosion+smoke
  flipbook) + `CREDITS.md`. Imported (.import files committed).
- `TokenTankSprites.gd` — faction→colorway map. `TokenVisual` letter mode draws
  a top-down tank hull + turret (rotated by model facing) for VEHICLE/TITANIC
  tokens instead of a letter.
- `ObjectiveVisual` — 40mm marker disc (plate, compass-star emblem, hub) with a
  gold rim that tints to the controlling player (`_create_marker_disc`,
  `update_control` sets `marker_trim.default_color`).
- `TerrainVisual._scatter_props` — deterministic (id-seeded) sprite scatter:
  crates/barrels/sandbags in ruins, trees in woods, oil-spill in craters,
  barricade segments on barricades.
- `DamageFeedbackVisual._spawn_explosion_sprite` — explosion→smoke flipbook on
  model death (hooked into `play_death_animation`).
- Enhanced/retro token bodies use `FactionPalettes` primary color
  (`TokenVisual._get_faction_primary_color`) instead of hardcoded player blue/red.
- Scenario: `40k/tests/scenarios/sp/tier2_asset_polish.json` (17/17 pass) with
  helper `40k/tests/helpers/tier2_probe.gd`.

## REMAINING WORK (candidate directions)

The user's steering question was: **"Are you able to create sprites that reflect
each of the models themselves?"** Honest answer given:
- **Cannot** generate photorealistic / GW-model-accurate art (no image-gen tool
  in the environment; GW imagery is copyrighted).
- **Can** draw procedural top-down sprites distinct **by faction and role**
  (Ork mob = hunched green + choppa, Custodes = tall gold + spear, Dreadnought =
  walker, bike = elongated + wheels, monster = organic). Recognizable by type,
  not a portrait of the exact kit. No external assets needed.
- **Can** make the drop-in art pipeline first-class: `SpriteResolver` already
  loads `user://sprites/<unit_name>.png` if present (exact name → faction+type →
  generic type). Make that seamless so real per-model PNGs "just work", with the
  procedural sprites as the fallback.

### Direction A — Infantry/character/monster procedural sprite library (BIGGEST WIN)
Vehicles have sprites; infantry are still letter discs. This is the half-done
Vassal-style transformation. Plan:
1. Extend `TokenDrawUtils` (or a new `TokenBodySprites.gd`) with per-role
   procedural top-down draws that take a faction primary/secondary color:
   infantry, heavy-infantry/terminator, character (add a chevron/banner),
   walker, monster/beast, mounted/bike, artillery/gretchin-swarm.
2. Make them faction-flavored via `FactionPalettes` + keyword hints
   (e.g. ORK bulkier, CUSTODES tall+halberd line, TYRANID organic).
3. Draw them in `TokenVisual` letter mode for non-VEHICLE units (VEHICLE already
   uses `_draw_tank_sprite`), keeping base ellipse + name plate + health bar.
4. **First: build a small POC** (the archetypes in the current test armies) and
   send screenshots to the user to calibrate whether the fidelity is "good
   enough" BEFORE rolling out to all factions — "reflects each model" may mean
   photorealistic, which is not achievable, so confirm the bar first.
5. Also polish `SpriteResolver` drop-in flow + document the naming so users can
   add real art.

### Direction B — Depth & finish pass (BEST value-per-effort, no assets)
Drop shadows under token bases, a board vignette, and a subtle grain/noise
overlay. Touches every render mode at once. Likely a new `Node2D` under
`BoardRoot` drawn below tokens (shadows) + a full-board `CanvasLayer` overlay
(vignette/grain). Low risk.

### Direction C — Fix the "Tilepack" board style (visible BUG) + tidy textures
The **Tilepack** board option (`SettingsService.board_style == "tilepack"`,
`shaders/tilepack_board.gdshader`, `BoardVisual.gd`) renders as near-flat green
at fit-to-board zoom — looks broken. Rebuild it as a real `TileMapLayer` from
the grass/sand tiles (see `TILEPACKS/` for road/transition tiles) or remove the
option. Also the mud/desert/felt/stone shader textures are samey noise fields.

### Direction D — Charge/fight-phase visual review (COVERAGE GAP)
`ChargeArrowVisual` and `PileInMovementVisual` were NEVER validated live — the AI
resolved its turn in ~3s every time so those visuals never triggered in view.
Drive charge + fight in a controlled setup (human-vs-human, or slow the AI) and
review/fix.

### Other smaller items noted in the review
- Main menu is a plain settings form — no faction key art. (`MainMenu.gd`,
  `WhiteDwarfTheme.gd`.)
- Enhanced mode: the big model numeral dominates; shrink it so the silhouette
  leads. Retro mode draws the same humanoid for bikes as for infantry.

## OPERATIONAL CHEAT-SHEET (how to run + validate — saves a lot of trial/error)

**Fresh clone import (once):**
```bash
export PATH="$HOME/bin:$PATH"
godot --path /home/user/warhammer-40k-godot/40k --headless --import   # USE ABSOLUTE PATH
```
Relative `--path 40k` fails if cwd isn't the repo root — always use the absolute path.

**Launch windowed (xvfb auto-wrapped by the shim):**
```bash
godot --path /home/user/warhammer-40k-godot/40k --rendering-method gl_compatibility > /tmp/game.log 2>&1 &
until grep -q "GodotMCP] Listening" /tmp/game.log; do sleep 1; done
```
Bridge listens on `127.0.0.1:9080`. There is a tiny NDJSON client + helpers in
the previous session's scratchpad (`bridge.py`: `send()`, `fit_board()`,
`zoom_to(cx,cy,z)`, `shot(name)`; `dshot.py`: half-res JPEG capture;
`boot_fixture.py`: menu→Start→load "End of movement phase" save). Recreate as
needed — `send(cmd, params)` writes one JSON line, reads one back.

**GOTCHAS (hit repeatedly last session):**
- **`pkill -f Godot` / `pkill -f rendering-method` matches its OWN command line**
  → the Bash tool reports exit 144 and kills the shell. Use
  `pgrep Godot | xargs -r kill` instead.
- **Image size / 32MB request cap**: reading many full-res 1920×1080 PNGs into
  context accumulates and eventually every request is rejected ("Request too
  large (max 32MB)") — this is what crashed the last session. DO:
  - Prefer **node inspection via `execute_script`** to verify structure
    (counts, texture paths, colors) instead of reading screenshots.
  - To let the USER see a visual, use **`SendUserFile`** (goes to their side
    panel, NOT into your context) — downscale to half-res JPEG first (Pillow is
    installed: `pip install Pillow`).
  - Only `Read` an image when you truly must self-verify, and read sparingly.
- **`execute_script` single-line mode can't see autoloads** ("Invalid named
  index 'SettingsService'"). Always pass `{"code": "...", "multiline": true}`;
  the node is `node`, tree is `tree`; call methods on those.
- **ScenarioRunner `execute_script` act uses `Expression`** (single expression,
  no `var`/multi-statement). Put tree-walking asserts in a helper `.gd` with
  instance methods and call as one chained expression (see `tier2_probe.gd`).
- **Scenario `equals` with numbers**: JSON `4` parses as float `4.0`; GDScript
  `int` `4` won't `==` it in the runner's strict compare. Return floats, or
  assert a bool / use `expect_min`.
- **Deploying via the bridge**: `DEPLOY_UNIT` needs `model_positions` (array of
  {x,y} in board px = inches×40) wholly inside the zone and not overlapping
  walls/models; big units → `PLACE_IN_RESERVES`. There's a 50% points reserve
  cap. Fastest path to a populated board is loading the `End of movement phase`
  save fixture (28 units already placed) then swapping to `Main.tscn`.

**Validation gate (project rule — see CLAUDE.md):** a UI feature isn't "done"
until a **windowed scenario** drives it. Pattern: add
`40k/tests/scenarios/sp/<id>.json`, run
`bash 40k/tests/run_scenarios.sh tests/scenarios/sp/<id>.json`, and finish with
the `verify_delivery` MCP command (`verdict: PASS`, 0 log errors). Copy save
fixtures first: `cp -n 40k/tests/saves/*.w40ksave 40k/saves/` (run_scenarios.sh
does this automatically).

**Changelog:** PREPEND a new entry to `40k/data/version_history.json`
(tab-indented! `json.dump(..., indent="\t")` — do NOT reformat the whole file)
for any player-facing change. Bump minor for features. It's `releases` list,
newest first; the merge last time duplicated entries — dedupe if merging main.

**Git:** the previous branch `claude/game-visual-polish-review-dpg715` PR is
MERGED. Start fresh from latest `main` (this handoff commit already did that).
Per repo policy, open a NEW PR for new work; don't reuse the merged one.

## KEY FILES
- Tokens: `40k/scripts/TokenVisual.gd` (letter/enhanced/retro draw), `TokenDrawUtils.gd`
  (procedural silhouettes), `TokenTankSprites.gd`, `FactionPalettes.gd`.
- Terrain: `40k/scripts/TerrainVisual.gd`, `TerrainCoverOverlay.gd`.
- Objectives: `40k/scripts/ObjectiveVisual.gd`.
- Board: `40k/scripts/BoardVisual.gd`, `40k/shaders/*_board.gdshader`.
- Damage/VFX: `40k/scripts/DamageFeedbackVisual.gd`.
- Sprite pipeline: `40k/autoloads/SpriteResolver.gd` (drop-in `user://sprites/`).
- Settings: `40k/autoloads/SettingsService.gd`, `40k/scripts/SettingsMenu.gd`.
- Assets: `40k/assets/tilepack/` (imported), repo-root `TILEPACKS/` (full Kenney drop).
