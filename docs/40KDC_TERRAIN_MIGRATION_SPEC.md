# Implementation Spec: Convert Official 11e Terrain Layouts (40kdc → game)

**Audience:** an engineer/LLM implementing this end-to-end.
**Goal:** replace the game's 8 hand-made terrain layouts with the 45 official
11th-edition GW terrain-layout cards shipped in the 40kdc dataset, wired to the
Force-Disposition mission matchups, and validated in the running game.

This document is self-contained. Read it top to bottom. Everything references
concrete files and fields in this repo. **Section 9 flags what is NOT known and
what external resources you will need** — read it before starting.

> **ACCEPTANCE BAR (decided): faithful to the 40kdc dataset.** "Done" means the
> converted layouts reproduce the dataset's geometry (via `resolveLayout`),
> transposed to the game board — NOT verified against Games Workshop's printed
> cards. This makes geometry acceptance fully automatable in-repo (compare the
> emitted JSON to the transposed resolver output; §8) and needs no external card
> images. Resolves unknown §9.1.

---

## 0. Definition of done

1. A generator `scripts/40kdc/generate-terrain-layouts.mjs` produces game-format
   layout JSON from the dataset, following the existing pipeline conventions
   (see the sibling generators in `scripts/40kdc/`).
2. The game can load and render every generated layout with correct geometry
   (positions, shapes, rotations) on the 44"×60" portrait board.
3. Terrain pieces behave correctly in-engine: LoS blocking (obscuring/tall),
   difficult ground, cover, and — for "area" pieces — the 11e terrain-as-
   objective control rule (§14.01).
4. Layouts are selectable and tied to the Force-Disposition matchup + deployment
   pattern (the dataset keys each layout to a matchup).
5. Objectives are placed per the layout/matchup (not just the generic deployment
   zone), OR an explicit decision is recorded to keep objectives in the
   deployment-zone data (see §5, Decision D3).
6. At least one **windowed scenario** (per the project's validation gate in
   `CLAUDE.md` / `40k/tests/TESTING_METHODOLOGY.md`) drives a game on a converted
   layout and asserts terrain renders + a LoS/cover/objective interaction works,
   with a screenshot and `verify_delivery` PASS.
7. `docs/40KDC_11E_MIGRATION.md` gap #10/#11/#12 updated to reflect completion.

---

## 1. The two data models

### 1a. Source: the 40kdc dataset (already extracted in-repo)

- `40k/data/40kdc/terrainLayouts.json` — **45 layouts**. Each: `id`, `name`,
  `source` ("gw-11e"), `description`, `mission_matchup_id`, `variant` (1–3),
  `deployment_pattern_id`, `pieces[]`.
- `40k/data/40kdc/terrainTemplates.json` — **16 templates** (the shape catalog
  the pieces reference): 5 `kind:"area"` (gameplay terrain areas: `area-large`,
  `area-trapezoid`, `area-medium`, `area-long-line`, `area-short-line`) + 11
  `kind:"feature"` (scenery: `corner-tiny`, `corner-short`, `barricade`, `pipe`,
  `gantry`, `catwalk`, `generator`, `corner-ruin-*`).
- `40k/data/40kdc/missionMatchups.json` — **25 matchups** (Force-Disposition
  pairs → mission_id). Layouts key to these via `mission_matchup_id`.
- `40k/data/40kdc/deploymentPatterns.json` — 6 patterns (already converted to
  the game's `40k/deployment_zones/*.json`).

**Piece structure** (`terrainLayouts.json` → `pieces[]`, and template
`features[]`): `id`, `name`, `piece_type` ("area" | "feature"), `template` (id
into templates) and/or `footprint` (inline, authoritative if present),
`position` (centroid, board inches), `rotation_degrees`, `mirror`
("none"|"horizontal"|"vertical"), `parent_area_id` (feature riding an area),
`floor`, `height_inches` (override), `terrain_area_keywords` (override; enum
`obscuring`|`hidden`|`plunging-fire`), `link_group`, `objective_role`
("home"|"expansion"|"center", implies is_objective), `is_objective`, `objective`
({position?, control_range_inches?}), `keystones[]` (tape-measure reference
lines — ignore for the game).

**Template structure** (`terrainTemplates.json`): `id`, `name`, `kind`
("area"|"feature"), `footprint` (`rectangle {width,height}` |
`right-triangle {width,height}` | `polygon {points:[{x,y}]}`),
`default_height_inches`, `default_blocking`, `default_terrain_area_keywords`,
`terrain_category` ("exposed"|"light"|"dense"), `features[]` (composed
sub-features), `upper_floor {footprint, floor}` (elevated platform).

**Coordinate system:** board inches, origin at a corner, **y-down**, on a
**60"×44" LANDSCAPE** board (`BOARD_INCHES = {width:60, height:44}` in the
package). Footprints authored local-y-down; the resolver re-centres each on its
polygon-area centroid so `position` is the centroid (invariant under
rotation/mirror).

### 1b. Target: the game's terrain format

**On-disk layout JSON** — `40k/terrain_layouts/layout_N.json` (see `layout_2.json`
for a full example): top-level `id`, `name`, `description`,
`recommended_deployments` (array of deployment-pattern ids), `pieces[]`.

**On-disk piece** (current loader `TerrainManager._load_layout_from_json`,
`autoloads/TerrainManager.gd:147–168`): `id`, `type` ("ruins"|"woods"),
`position` ([x,y] inches, **44×60 PORTRAIT board, y-down, origin top-left**),
`size` ([w,h] inches — **defines an axis-aligned rectangle**), `height`
("low"|"medium"|"tall"), `rotation` (degrees, clockwise), `traits`
(["obscuring","difficult_ground"]), `walls[]`.

**On-disk wall:** `id`, `local_start` [x,y] (inches, relative to piece centre),
`local_end` [x,y], `type` ("solid"|"window"|"door"), `blocks_los` (bool).

**Board:** 44"×60" portrait, `Measurement.PX_PER_INCH = 40` → 1760×2400 px.
`SettingsService.board_width_inches=44`, `board_height_inches=60`.

**KEY FACT — the runtime already supports arbitrary polygons.** The loader today
builds a *rectangle* polygon from `position`+`size`
(`TerrainManager._add_terrain_piece`, `:244–268`), but every downstream consumer
(LoS in `EnhancedLineOfSight`, cover, movement, `TerrainVisual` rendering at
`scripts/TerrainVisual.gd:155` which draws `piece.polygon`) reads a
`polygon: PackedVector2Array` field on the runtime terrain dict
(`TerrainManager.gd:282`). So **the engine can render/handle any polygon** — the
only rectangle limitation is the JSON→runtime loader. This is the single most
important design lever (Decision D1).

**Objectives** are currently NOT in layout files — they live in
`40k/deployment_zones/*.json` (`objectives[]` with `id`, `position`, `zone`),
read by `DeploymentZoneData.get_objectives`. See Decision D3.

---

## 2. The resolver — do NOT reimplement the geometry

The dataset stores template references + centroid placements + rotation/mirror,
NOT absolute vertices. **The npm package resolves them for you.** Use it in the
generator (Node, ESM):

```js
import { resolveLayout, BOARD_INCHES } from '@alpaca-software/40kdc-data';
// resolveLayout(layout, templates) -> ResolvedPiece[]
//   ResolvedPiece = { id, name, piece_type: "area"|"feature",
//                     floor: number, vertices: {x,y}[] }  // absolute, y-down, 60x44
```

`vertices` are absolute board-space polygon vertices (4-dp), already
mirror→rotate→translated, including composed template `features` and
parent-area-relative features. **Emission order matters and is pinned** (pieces
in `layout.pieces` order; composed features right after their area). The
resolver output gives you geometry + piece_type + floor; **everything else
(height, blocking, keywords, category, objective flags, link_group) you read
from the raw layout piece and its template** and join by index/id.

The package is already installed under `scripts/40kdc/node_modules` and pinned in
`scripts/40kdc/package.json`. Reuse `scripts/40kdc/lib.mjs`'s `loadCollection`.

---

## 3. The board transform (dataset 60×44 landscape → game 44×60 portrait)

Identical to the transform already used and verified in
`scripts/40kdc/generate-deployment-zones.mjs`: **transpose**.

```
game_x = dc_y      (dc_y ∈ [0,44]  → game_x ∈ [0,44])
game_y = dc_x      (dc_x ∈ [0,60]  → game_y ∈ [0,60])
```

Verified invariant: the board centre objective (30,22) in dataset space maps to
(22,30) in game space. Apply this to every resolved vertex and every objective
position. **Rotation:** a transpose (swap x/y) mirrors handedness, so a
clockwise angle in dataset space becomes counter-clockwise in game space. Since
you are emitting explicit polygons (not size+rotation), bake rotation into the
vertices via the resolver and set the game piece `rotation: 0` — this sidesteps
the angle-handedness question entirely. (If you instead emit size+rotation, you
must negate the angle; prefer polygons.)

---

## 4. Recommended output shape (game layout JSON, extended)

Emit one `40k/terrain_layouts/<matchup>_<variant>.json` per dataset layout.
Extend the piece schema with an explicit `polygon` (this is Decision D1 —
strongly recommended):

```jsonc
{
  "id": "take-and-hold-mirror-1",
  "name": "Take and Hold Mirror 1",
  "description": "…from the 40kdc gw-11e layout card.",
  "mission_matchup_id": "take-and-hold-vs-take-and-hold",   // NEW: for wiring
  "variant": 1,                                             // NEW
  "recommended_deployments": ["search_and_destroy"],        // from deployment_pattern_id → game id
  "objectives": [ /* optional, see D3 */ ],
  "pieces": [
    {
      "id": "area-trapezoid-1",
      "type": "ruins",                    // mapped from template/category (§6)
      "piece_class": "area",              // NEW: "area" | "feature" (drives 14.01)
      "polygon": [[x,y], …],              // NEW: game-inch vertices (transposed)
      "position": [cx, cy],               // centroid, game inches (for label/badge)
      "height": "tall",                   // mapped from height_inches (§6)
      "rotation": 0,                      // rotation baked into polygon
      "traits": ["obscuring"],            // mapped from keywords/category (§6)
      "floor": 0,
      "is_objective": true,               // from objective_role/is_objective
      "objective_role": "center",         // "home"|"expansion"|"center"
      "link_group": "Center",
      "walls": []                         // see Decision D2
    }
  ]
}
```

Then extend `TerrainManager._load_layout_from_json` (`:147`) so that when a piece
has a `polygon`, it uses it directly instead of deriving a rectangle from
`size`; keep the `size` path as the fallback for the legacy hand-made layouts.
`_add_terrain_piece` (`:244`) already builds the runtime dict with a `polygon`
field — add an overload/branch that accepts a pre-built polygon. Also plumb
`piece_class`, `floor`, `is_objective`, `objective_role`, `link_group` onto the
runtime terrain dict so mission code can read them.

---

## 5. Design decisions (make these explicitly; recommendations given)

**D1 — Polygon vs bounding-box.** Dataset footprints include trapezoids and
right-triangles. **Recommendation: emit true polygons** and extend the loader
(§4). The runtime already renders/uses polygons, so this is low-risk and
loss-free. (Alternative: approximate each as its bounding-box rectangle — lossy,
not recommended.)

**D2 — Walls.** The dataset has **no wall data** (no window/door granularity).
The hand-made layouts use walls so LoS can pass through windows. Options:
  - (a) **Recommended for v1:** emit no walls; rely on the polygon + `obscuring`
    trait + `height` for LoS blocking (the engine already blocks LoS through
    obscuring/tall polygons — `EnhancedLineOfSight.gd:315–378`). This makes
    converted ruins fully LoS-blocking, which matches the 11e default "Ruins are
    Obscuring" behaviour, at the cost of the window see-through nuance.
  - (b) Generate a `solid, blocks_los` wall per polygon edge for obscuring
    pieces (more faithful to the "walls block, interior is area" model, more
    work, still no windows).
  Record which you chose. Flag the lost window/door nuance to the product owner.

**D3 — Objective source.** The dataset layout embeds objective positions per
matchup (`pieces[].objective_role` / `objective`), and 11e ties objectives to
the specific board/terrain. Today objectives come from
`40k/deployment_zones/*.json` via `DeploymentZoneData.get_objectives`. Options:
  - (a) **Recommended:** emit an `objectives[]` array into each layout JSON
    (ids `obj_home_1/2`, `obj_center`, `obj_nml_1/2`, plus `zone` tag) derived
    from the layout's objective pieces, and teach `MissionManager` /
    `DeploymentZoneData` to prefer the layout's objectives when present, falling
    back to the deployment-zone objectives otherwise.
  - (b) Keep objectives in deployment-zone data; ignore the layout's objective
    pieces. Simpler, but loses per-matchup objective placement fidelity.
  This decision interacts with gap #10 (5 vs 6 objectives) — see D4.

**D4 — 5 vs 6 objectives.** Some 11e primaries assume 6-objective boards
(`Inescapable Dominion` is flagged `approximate` for this in
`40k/scripts/data/PrimaryMissionData11e.gd`). Count the objective pieces per
dataset layout: if any layout has 6, decide whether to support 6-objective
boards. This touches `MissionManager` objective designation
(`_assign_objective_designations`) and the primary scoring caps. **Recommendation
for v1:** convert geometry faithfully (emit however many objectives the layout
has) and file the scoring-cap adjustments as a follow-up if 6-objective layouts
appear.

**D5 — Matchup→layout selection UI.** The dataset gives 15 unordered matchup
pairings × 3 variants. The game main menu currently has separate "Terrain
Layout" and "Deployment Zone" dropdowns (`scripts/MainMenu.gd`) plus per-player
Force-Disposition dropdowns. **Recommendation:** once both players' dispositions
are chosen, resolve the matchup, then offer the 3 variant layouts (and default
the deployment dropdown to the layout's `deployment_pattern_id`). Keep a manual
override for testing. This is UI wiring in `MainMenu.gd` + `TerrainManager`
layout registration (`DEPLOYMENT_TYPES`-style list, and the
`_preload_layout_metadata` loop at `TerrainManager.gd:50`).

---

## 6. Field-by-field mapping (dataset → game)

| Game field | Source | Rule |
|---|---|---|
| piece `polygon` | `resolveLayout().vertices`, transposed (§3) | direct |
| piece `position` (centroid) | `resolveLayout` piece centroid (mean of vertices) or raw `position`, transposed | for label/badge only |
| piece `piece_class` | raw piece `piece_type` | "area" / "feature" |
| piece `type` | template `kind` + `terrain_category` | area or ruin-feature → `"ruins"`; if a woods-like template appears → `"woods"` (none in current 16 templates — default `"ruins"`) |
| piece `height` | `height_inches` override else template `default_height_inches` | `<2"→"low"`, `2–4"→"medium"`, `>4"→"tall"` (confirm thresholds against `TerrainManager._parse_height_category` / height-inches usage `:356,792`) |
| piece `traits` | `terrain_area_keywords` (override else template default) + `terrain_category` | `obscuring` keyword or `dense` category → `"obscuring"`; `light`/area templates → `"difficult_ground"`; `hidden`/`plunging-fire` → see D-unknown (§9.5) |
| piece `floor` | `resolveLayout().floor` | direct (0 = ground) |
| piece `is_objective` / `objective_role` / `link_group` | raw piece fields | direct |
| objective position | raw piece `objective.position` (parent-relative → resolve) or piece centroid, transposed | D3 |
| layout `recommended_deployments` | `deployment_pattern_id` → game id | via the ID_MAP already in `generate-deployment-zones.mjs` (e.g. `search-and-destroy`→`search_and_destroy`) |
| layout `mission_matchup_id`, `variant` | raw layout fields | direct (for D5 wiring) |

Height thresholds and the category→trait mapping are the main **judgment calls** —
verify them against how the engine reads height/traits (`TerrainManager.gd`
`is_terrain_obscuring`, `_get_terrain_height_inches`, difficult-ground handling
`:440–483`, cover `TerrainCoverOverlay.gd`).

---

## 7. Implementation steps (ordered)

1. **Generator skeleton.** Create `scripts/40kdc/generate-terrain-layouts.mjs`.
   Load `terrainLayouts.json` + `terrainTemplates.json` via `lib.mjs`. For each
   layout call `resolveLayout(layout, templates)`. Join resolved pieces (by
   index / emission order) back to raw pieces + templates for the non-geometry
   fields. Transpose all coordinates (§3). Emit one game JSON per layout into
   `40k/terrain_layouts/`. Strip legacy hand-made layouts or keep them behind a
   flag (decide; recommend keeping `layout_1..8` until parity is confirmed, then
   remove).
2. **Loader extension.** Extend `TerrainManager._load_layout_from_json` (`:147`)
   to read `polygon`, `piece_class`, `floor`, `is_objective`, `objective_role`,
   `link_group`; branch `_add_terrain_piece` to accept a pre-built polygon.
   Preserve the legacy `size`-rectangle path.
3. **Layout registry + metadata.** Register the new layout ids so
   `TerrainManager._preload_layout_metadata` (`:50`) and the menu see them.
   Consider generating a small index (matchup → [variant layout ids]) for D5.
4. **Objectives (D3).** If chosen: emit `objectives[]` and make
   `MissionManager` / `DeploymentZoneData.get_objectives` prefer the layout's.
5. **Selection wiring (D5).** Update `MainMenu.gd` to resolve matchup→layout and
   default the deployment dropdown.
6. **Regenerate + run.** `cd scripts/40kdc && node generate-terrain-layouts.mjs`.
   Build the import cache (`godot --headless --path 40k --import`), launch the
   game windowed (see `CLAUDE.md` "You CAN run the game…"), load a converted
   layout, screenshot, and eyeball geometry against the dataset (use
   `tools/render_layout.py` to PNG-render the game JSON for a side-by-side, and
   compare to the dataset via the resolver — see §9.1 for the official-card
   caveat).
7. **Windowed scenario.** Add `40k/tests/scenarios/sp/<id>_terrain_11e.json`
   that loads a converted layout, asserts N terrain pieces present with polygons,
   drives one LoS or cover or terrain-objective (14.01) interaction, screenshots,
   and passes `verify_delivery`. Run via `bash 40k/tests/run_scenarios.sh`.
8. **Docs.** Update `docs/40KDC_11E_MIGRATION.md` (gaps #10–#12) and add the
   generator to the "Refresh flow".

---

## 8. Validation & acceptance

- **Geometry (the primary acceptance gate — "faithful to the dataset"):** a
  headless Node check MUST assert, for **all 45 layouts**, that every emitted
  piece polygon equals `resolveLayout(layout, templates)` output with the §3
  transpose applied (compare vertex-for-vertex, 4-dp; account for emission
  order). This is the definition of "done" for geometry — make it a committed
  test (e.g. `scripts/40kdc/verify-terrain-layouts.mjs`) and run it in the
  generator's flow. No GW card images are required or in scope.
- Also assert every transposed polygon lies within the 44×60 board.
- Engine: the **windowed scenario** is the gate (project rule — headless is
  necessary but NOT sufficient; see `CLAUDE.md`). Must show terrain rendered and
  a real terrain interaction working, with a screenshot and `verify_delivery`
  PASS.
- No `ERROR`/`SCRIPT ERROR` in the debug log while loading every converted layout
  (loop over all 45 via `execute_script` + `read_debug_log`).

---

## 9. UNKNOWNS & EXTERNAL RESOURCES NEEDED (read before starting)

These are things I could not determine from the repo/dataset and that the
implementer must obtain or decide:

1. **RESOLVED — no GW card images needed.** The acceptance bar is **faithful to
   the 40kdc dataset** (decided by the product owner), not verified against
   GW's printed cards. So the geometry gate is the automated resolver-equality
   check in §8; the community-authored ("source":"gw-11e") dataset geometry is
   taken as the source of truth. Do NOT block on obtaining official GW /
   gdmissions card images — they are explicitly out of scope. (If the bar is
   ever raised to "verified against GW," you would then need those card images;
   until then, ignore.)

2. **Terrain-type semantics (ruins vs woods vs area).** The dataset's 16
   templates are ruins/industrial scenery + abstract "area" zones; there is no
   explicit "woods" analogue. Whether any layout should render/behave as Woods
   (difficult ground, LoS-through but blocks at >... ) vs Ruins (Obscuring) is a
   mapping judgment. Confirm the intended 11e terrain-feature taxonomy with the
   product owner, or map everything to Ruins for v1.

3. **Objective sourcing & count (D3/D4).** Whether objectives should move into
   the layout data and whether to support 6-objective boards are **product
   decisions** with scoring implications. Get a ruling before wiring objectives.

4. **Selection-UX intent (D5).** How the player should pick a layout in 11e
   (auto from matchup vs manual) is a UX decision. Confirm desired flow.

5. **11e terrain special rules coverage.** The dataset carries
   `terrain_category` (exposed/light/dense) and `terrain_area_keywords`
   (`hidden`, `plunging-fire`) that the current engine does NOT implement
   (it models Obscuring, difficult ground, cover, height/walls). Decide whether
   Hidden and Plunging Fire are in scope. If yes, that is **additional engine
   work** beyond the geometry port (new rules in the shooting/LoS path), and the
   11e core rules text for those (wahapedia / GW) is the needed reference.

6. **Visual assets (optional).** The game renders terrain as colored polygons +
   labels (no per-shape sprites required), so v1 needs no art. If nicer visuals
   for trapezoid/L-ruins are wanted, terrain sprite/texture assets would be
   needed (not blocking).

7. **Wall/window fidelity (D2).** The dataset has no window/door data, so
   converted ruins lose the see-through-window LoS nuance the hand-made layouts
   have. Confirm this is acceptable for v1.

---

## 10. File inventory

**Read:**
- `40k/data/40kdc/terrainLayouts.json`, `terrainTemplates.json`,
  `missionMatchups.json`, `deploymentPatterns.json`
- `scripts/40kdc/generate-deployment-zones.mjs` (the transform + ID_MAP to copy),
  `scripts/40kdc/lib.mjs`
- `40k/autoloads/TerrainManager.gd` (loader `:147`, `_add_terrain_piece` `:244`,
  metadata `:50`, height/traits/objective helpers)
- `40k/autoloads/EnhancedLineOfSight.gd` (how walls/obscuring/height block LoS)
- `40k/scripts/TerrainVisual.gd` (polygon rendering, `:155`)
- `40k/autoloads/MissionManager.gd` (terrain-as-objective 14.01 `:361`;
  objective designation)
- `40k/scripts/data/DeploymentZoneData.gd` (`get_objectives`)
- `40k/scripts/MainMenu.gd` (terrain/deployment/disposition dropdowns)
- `40k/terrain_layouts/layout_2.json` (format reference)
- `tools/render_layout.py`, `tools/PARSE_TERRAIN_GUIDE.md` (visual QA)
- Package resolver typings: `node_modules/@alpaca-software/40kdc-data/dist/terrain/*.d.ts`

**Create:**
- `scripts/40kdc/generate-terrain-layouts.mjs`
- `40k/terrain_layouts/<matchup>_<variant>.json` × 45 (generated)
- `40k/tests/scenarios/sp/<id>_terrain_11e.json` (windowed validation)

**Edit:**
- `40k/autoloads/TerrainManager.gd` (polygon loader + new fields)
- possibly `40k/autoloads/MissionManager.gd` / `DeploymentZoneData.gd` (D3)
- `40k/scripts/MainMenu.gd` (D5)
- `docs/40KDC_11E_MIGRATION.md` (gaps #10–#12)
- `scripts/40kdc/` refresh-flow docs

---

## 11. Effort & risk

- Generator + polygon loader + render one layout: the core, ~self-contained,
  low risk (the resolver and polygon runtime already exist).
- Objective/matchup/UI wiring (D3/D5): medium, touches mission + menu code.
- Hidden/Plunging-Fire rules (§9.5): out of scope unless explicitly wanted —
  that's new rules engine work, not a data port.

Recommended v1: geometry + polygon loader + Ruins/Obscuring mapping + one
windowed scenario, keeping objectives in the existing deployment-zone data
(D3-b). Then iterate objectives/UI/extra terrain rules as follow-ups.
