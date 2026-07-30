# Isometric View — Feasibility Study

**Date:** 2026-07-30
**Status:** Research only — no implementation. This document assesses whether (and how) the
game could move from its current top-down 2D presentation to an isometric view.

---

## 1. Executive summary

Converting the game to an isometric view is **feasible, but it is a presentation-layer
project with an unusually wide blast radius** because the codebase currently treats
"board space", "world space", and "screen space" as the same 2D pixel space
(40 px = 1 inch, `Measurement.PX_PER_INCH`). Every controller, visual, test harness and
the MCP bridge implicitly relies on that identity.

Four viable strategies exist, in increasing order of cost:

| Option | What it is | Effort | Risk | Visual payoff |
|---|---|---|---|---|
| **0. Depth cues only** | Keep top-down; add shadows, wall height sprites, layering | Days | Trivial | Low |
| **A. Tilted-table view** | Render the existing 2D board into a `SubViewport`, display it on a tilted quad under an orthographal `Camera3D` as a **toggle** | 1–2 weeks | Low | Medium — "table seen at an angle", like a digital board game 3D toggle |
| **B. Native 2D isometric projection** | Apply a dimetric transform to `BoardRoot`; counter-skew labels; y-sort tokens/terrain | 3–6 weeks | Medium-high | Medium-high |
| **C. Full 3D presentation layer** | Keep 2D rules engine as-is; build a synchronized 3D scene (orthographic camera, real terrain height, standee/3D minis) | 2–4+ months + art pipeline | High | High — the "Moonbreaker/Battlesector look" |

**Recommendation:** If the goal is "the game looks flat, make it feel more physical",
do **Option 0 now and Option A as a view toggle** — top-down stays the authoritative
tactical view (which matches how measurement-based wargames are actually played), and the
isometric/tilted view is presentational. Only commit to Option C if the project is ready
to invest in an art pipeline; **Option B is the worst value** — near-3D effort for a
result that still uses flat art. A grid-based isometric TileMap approach (Godot's
built-in iso support) is **not applicable at all**: this game is gridless,
continuous-measurement, and that support assumes tiles.

---

## 2. Current architecture snapshot (what the conversion touches)

Verified directly in the codebase:

- **Scene shape** (`40k/scenes/Main.tscn`): root `CanvasLayer` → `BoardRoot` (`Node2D`)
  containing `Camera2D`, `BoardView`, `DeploymentZones` (`Polygon2D`s), `TokenLayer`,
  `GhostLayer`. The HUD panels are siblings on the `CanvasLayer`. Everything on the board
  is **pure 2D CanvasItem rendering — there is no 3D anywhere in the project.**
- **One shared coordinate space** (`40k/autoloads/Measurement.gd`):
  `PX_PER_INCH = 40.0`; all distances, ranges, base sizes (circular / rectangular / oval
  base shapes), movement paths, and the 0.05" distance tolerance are computed in board
  pixels. `SettingsService.gd`, `TerrainManager.gd`, `FactionAbilityManager.gd`, the
  RulesEngine, AI, LoS, deployment zones — all operate in this same space.
- **~40 custom-drawn visual scripts** using immediate-mode `_draw()`:
  `TokenVisual`, `BoardVisual`, `TerrainVisual`, `WallVisual`, `DeploymentZoneVisual`,
  `ChargeArrowVisual`, `ChargeDirectionVisual`, `ChargeTrajectoryPreview`,
  `CoherencyCircleVisual`, `ShootingLineVisual`, `ThreatOverlay`, `TerrainCoverOverlay`,
  `DeepStrikeExclusionVisual`, `StrategicReservesZoneVisual`, `AIMovementPathVisual`,
  `RulerTool`, `MeasuringTapeManager`, `WoundAllocationBoardHighlights`, and more.
  Each draws circles/lines/polygons in board pixels and assumes an orthogonal view.
- **Terrain height is categorical, not geometric** (`TerrainManager.HeightCategory`):
  terrain pieces are 2D polygons tagged low/medium/tall for LoS purposes. There is no
  height geometry to project — an isometric view would have to *invent* heights.
- **Art is top-down**: tokens are drawn base shapes (circles/ovals/rectangles) with
  insignia, plus some top-down sprites (`TokenTankSprites`, `SpriteResolver`). None of it
  is usable as isometric art.
- **Systems that consume positions but must NOT change**: RulesEngine, save/load
  (`StateSerializer`), multiplayer sync (`NetworkManager`/`WebSocketRelay`),
  `ReplayManager`, AI (`AIPlayer`, `AIDecisionMaker`), LoS
  (`EnhancedLineOfSight`, `LineOfSightManager`). As long as game logic stays in board
  pixels, all of these are untouched by any option below.
- **The validation harness is screen-space-coupled**: windowed scenarios
  (`40k/tests/scenarios/`) drive the real UI via the MCP bridge's `simulate_click`,
  `scene_snapshot`/`diff_snapshot`, `capture_screenshot`. Any change to the
  board→screen mapping changes where clicks must land and what snapshots contain.

**The single most important structural fact:** because board space and canvas space are
currently identical, code freely mixes `position`, `global_position`, and
`get_global_mouse_position()`. The moment a projection transform is inserted anywhere in
the tree, those stop being interchangeable. An audit-and-fix of every such usage is the
hidden cost inside options B and C.

---

## 3. What "isometric" can mean here — the four options

### Option 0 — Stay top-down, add depth cues (days)
Drop shadows under tokens, subtle wall/terrain height shading, ruined-building sprites
with painted-on verticality, damage decals. No coordinate change, no risk. This is what
top-down digital adaptations (Vassal-style) do, and it is cheap. Worth doing regardless
of the other options.

### Option A — "Tilted table" via SubViewport (1–2 weeks)
Render the entire existing `BoardRoot` into a `SubViewport`; place that texture on a quad
in a minimal 3D scene viewed by an orthographic `Camera3D` pitched ~30–45°. Nothing in
the 2D game changes — it just renders off-screen.

- **Input:** raycast screen → quad → UV → board pixel; feed the existing input path.
  One conversion function, in one place.
- **Toggle:** keep top-down as default; `V` to switch views (many digital board games —
  chess apps, Tabletop Simulator's table views — offer exactly this 2D/3D toggle).
- **Payoff/limitation:** the board genuinely reads as a physical table at an angle, but
  tokens remain flat printed counters lying on it — no standing miniatures. Text on the
  board is foreshortened (mitigate: render measurement labels in a screen-space overlay).
- **Why it's safe:** rules, tests, multiplayer, saves all untouched; the windowed
  scenario harness keeps running against the top-down view.

### Option B — Native 2D dimetric projection (3–6 weeks, medium-high risk)
Apply a classic 2:1 dimetric transform (rotate 45°, scale Y ×0.5 — expressible as a
`Transform2D` or `Node2D.skew`/scale on `BoardRoot`) so the whole board renders
diamond-shaped, plus `y_sort_enabled` on the token/terrain layers.

- Godot's canvas transform automatically maps input back for code using
  *local* coordinates — but every `get_global_mouse_position()`-vs-`position` mix-up
  breaks (see §2). Expect a long tail of picking, drag-ghost, camera-limit and
  zoom bugs.
- `draw_circle` etc. project correctly to ellipses under the transform (bases *should*
  look elliptical when a flat board is viewed at an angle), but **all text drawn on the
  board skews** and must be counter-transformed per label; line widths distort.
- Tall terrain still needs new art to actually look tall; without it the result is
  "rotated diamond board", not "isometric game".
- **Verdict: technically sound, poor value.** Most of the cost of 3D, little of the look.

### Option C — Full 3D presentation layer (2–4+ months + art)
Keep the entire rules/logic layer in 2D board pixels (positions stay `Vector2`), and
build a parallel 3D scene: board plane, extruded terrain meshes from the existing 2D
polygons + `HeightCategory`, tokens as standees (billboarded sprites) or 3D minis,
orthographic `Camera3D` at the classic −30°/45° angles — the approach the Godot
community converges on for isometric today (3D + orthogonal camera, not 2D tricks).

- Mapping is mechanical: board px `(x, y)` → 3D `(x/40, height, y/40)` (1 unit = 1").
- Picking = ray-to-ground-plane intersection; feeds existing controllers with board px.
- Every one of the ~40 `_draw()` visuals needs a 3D re-implementation (lines →
  `ImmediateMesh`/`MeshInstance3D` ribbons, zones → decals/flat meshes, range circles →
  rings on the ground plane).
- **Art is the real cost**: standee sprites or models for every unit in every faction,
  terrain meshes, walls. Code is weeks; art is months and ongoing per new unit.
- New problems inherited from real isometric games: **occlusion** (tall ruins hiding
  units — needs silhouette/x-ray shaders or camera-rotation steps), **depth sorting** of
  transparent billboards, camera rotation UX. These are the canonical iso pain points
  reported across engines (depth sorting, mouse picking, tall-object occlusion).
- **Container/CI caveat:** the remote validation environment renders via Mesa llvmpipe
  (software GL). A 3D scene will run there but measurably slower; screenshot-based
  scenario validation stays possible but scenario scripts need a 3D picking path.

---

## 4. How comparable games approach this (online research)

The pattern across the genre is consistent and instructive:

- **Measurement-based (gridless) miniature wargames go full-3D with a free camera, not
  fixed isometric.** [Moonbreaker](https://store.steampowered.com/app/845890/Moonbreaker/)
  (Unknown Worlds' digital minis game) simulates picking up and dropping models on a 3D
  table ([overview](https://www.thegamer.com/moonbreaker-early-access-preview-digital-miniatures/),
  [Wikipedia](https://en.wikipedia.org/wiki/Moonbreaker)).
  [Tabletop Simulator](https://steamcommunity.com/app/286160/discussions/0/360670708782808394)
  gives a free camera plus an on-demand tape measure (hold Tab for a distance line) —
  measurement is a *tool you invoke*, not something read off the projection. Dedicated
  wargame sims ([Wargame Simulator](https://www.wargamesimulator.com/),
  [Warhall](https://www.warhall.eu/)) follow the same free-3D-camera pattern.
  The reason maps directly to this project: **when exact distances decide legality, a
  player must never have to judge them from a distorted projection** — either you give a
  top-down view or you give explicit measuring tools. Official grid-based 40k
  adaptations (Battlesector, Gladius) sidestep this entirely by *changing the rules* to
  tiles/hexes — not an option when replicating the tabletop core rules.
- **In Godot, the modern isometric approach is 3D + orthographic camera**, not 2D
  projection tricks: a `Camera3D` set orthographic, pitched ~−30/−45° and yawed 45°
  ([Godot forum](https://forum.godotengine.org/t/how-can-i-move-and-rotate-an-isometric-camera-in-3d/51832),
  [isometric-3d-toolkit for Godot 4](https://github.com/marinho/isometric-3d-toolkit),
  [camera demo](https://lexmo.itch.io/godot4-isometric-camera-demo),
  [devlog](https://www.youtube.com/watch?v=LpTA98rgCjQ),
  [archived Q&A](https://godotengine.org/qa/33673/camera-positioning-transformation-isometric-style-in-3d)).
  Godot's built-in 2D isometric support is TileMap-shaped (diamond tiles, grid
  positions) and assumes tiled worlds — inapplicable to a continuous board.
  Mixed 2D/3D ("2.5D") setups are documented and workable
  ([forum](https://forum.godotengine.org/t/isometric-2-5d-mixed-3d-and-2d-pre-renderred-background-game-and-2-cameras/66363),
  [official 2.5D demo](https://godotengine.org/asset-library/asset/2783),
  [pure-2D iso experiment](https://github.com/fengjiongmax/3D_iso_in_2D)).
- **Isometric's classic engineering costs are well documented**: depth sorting has "no
  perfect method" ([tutsplus](https://gamedevelopment.tutsplus.com/tutorials/isometric-depth-sorting-for-moving-platforms--cms-30226),
  [Phaser guide](https://generalistprogrammer.com/tutorials/phaser-isometric-game-tutorial)),
  mouse picking requires screen→world inversion, and **tall structures hiding units**
  forces transparency/silhouette systems or camera rotation
  ([guide](https://300mind.studio/blog/how-to-create-an-isometric-game/)). Every one of
  these lands on this project the moment the view tilts.

**Takeaway:** no successful digital adaptation of a *measurement-based* tabletop game
uses a fixed isometric view as its primary tactical view. They use either top-down 2D
(what this project already has) or free-camera 3D with explicit measuring tools.
Isometric-as-a-toggle is common; isometric-as-the-only-view is not.

---

## 5. Risks, challenges and limitations (detailed)

### Gameplay/UX risks — the ones that can sink the feature
1. **Measurement anisotropy.** Under any tilted projection, N screen-pixels represent
   different board distances depending on direction. Judging 1" engagement range,
   base-to-base contact (0.05" tolerance!), 2" coherency, or a 12" rapid-fire band *by
   eye* becomes unreliable. Mitigations: keep numeric readouts authoritative everywhere
   (ruler, charge distances, move remaining), draw range indicators in board space so
   they project consistently (a 6" circle correctly becomes an ellipse), and keep a
   top-down toggle for precise play.
2. **Occlusion.** Top-down has none; iso does. Tall ruins in front of a melee scrum hide
   it. Requires silhouette shaders/transparency-on-hover (Option C) — extra systems that
   don't exist today.
3. **Dense-formation readability.** 20-model boyz mobs already overlap visually;
   y-sorted iso stacks them vertically on screen, making individual model selection
   (wound allocation!) harder. Needs hover-highlight + click-cycling affordances.
4. **Precision placement.** Deployment and pile-in/consolidate demand mm-level drops.
   Foreshortened Y-axis halves vertical screen precision (2:1 iso). Mitigation: snap
   assists, zoom, or do precision actions in top-down.

### Technical risks
5. **The board-space == canvas-space assumption** (§2). Every
   `get_global_mouse_position()` / `global_position` / manual screen-math site is a
   latent bug under options B/C. This audit is unavoidable and hard to scope precisely
   (hundreds of call sites across ~239 scripts).
6. **~40 `_draw()` visuals** re-verified (B) or rewritten (C).
7. **On-board text skewing** (B) — every label needs counter-transform; or all labels
   move to a screen-space overlay layer keyed to projected positions (also needed for A).
8. **Terrain has no height geometry** — inventing it (art + data) is a prerequisite for
   any real iso look; `HeightCategory` gives only 3 buckets to extrude from.
9. **Test-harness coupling.** Windowed scenarios click screen positions and snapshot
   node states. A projection changes screen positions; scenario tooling needs a
   board→screen helper so scripts express clicks in board inches, not pixels. Budget
   real time for this — the project's own validation gate (windowed scenarios via the
   MCP bridge) applies to the iso view itself.
10. **Software-rendering CI** (llvmpipe): Option C's 3D adds real per-frame cost to the
    validation environment; keep scene complexity budgeted or scenarios get slow/flaky.
11. **Art pipeline** (C): per-unit standees/models across all factions is the dominant,
    *recurring* cost — every future unit needs art in two representations.

### What is *not* at risk (if logic stays in board pixels)
Save format, multiplayer sync, replays, AI decisions, RulesEngine math, LoS results —
all are presentation-independent today and should be kept that way. **Hard rule for any
implementation: the projection is applied at render/input time only; nothing that
touches `GameState` ever sees projected coordinates.**

---

## 6. Suggested path (if/when this is pursued)

1. **Now (days):** Option 0 depth cues. Also introduce a single
   `BoardTransform`-style seam (`board_to_screen()` / `screen_to_board()`), initially
   identity, and migrate obvious call sites to it — this de-risks every later option.
2. **Next (1–2 weeks):** Option A tilted-table **toggle** ('V'), default top-down;
   measurement labels moved to a screen-space overlay. Windowed scenarios keep running
   in top-down; add 2–3 iso-toggle scenarios (toggle on → click a unit via the
   conversion helper → assert selection → screenshot).
3. **Later, only with art budget (months):** Option C as a synchronized 3D presentation
   scene, keeping the 2D scene as the tactical/fallback view — mirroring how
   TTS/Moonbreaker pair a free 3D view with explicit measurement tools.
4. **Skip Option B** unless a deliberate "diamond-board" aesthetic is wanted cheaply.

---

## 7. Sources

- https://store.steampowered.com/app/845890/Moonbreaker/ · https://en.wikipedia.org/wiki/Moonbreaker · https://www.thegamer.com/moonbreaker-early-access-preview-digital-miniatures/
- https://steamcommunity.com/app/286160/discussions/0/360670708782808394 (TTS tape-measure)
- https://www.wargamesimulator.com/ · https://www.warhall.eu/
- https://forum.godotengine.org/t/how-can-i-move-and-rotate-an-isometric-camera-in-3d/51832 · https://godotengine.org/qa/33673/camera-positioning-transformation-isometric-style-in-3d
- https://github.com/marinho/isometric-3d-toolkit · https://lexmo.itch.io/godot4-isometric-camera-demo · https://www.youtube.com/watch?v=LpTA98rgCjQ
- https://forum.godotengine.org/t/isometric-2-5d-mixed-3d-and-2d-pre-renderred-background-game-and-2-cameras/66363 · https://godotengine.org/asset-library/asset/2783 · https://github.com/fengjiongmax/3D_iso_in_2D
- https://gamedevelopment.tutsplus.com/tutorials/isometric-depth-sorting-for-moving-platforms--cms-30226 · https://generalistprogrammer.com/tutorials/phaser-isometric-game-tutorial · https://300mind.studio/blog/how-to-create-an-isometric-game/
