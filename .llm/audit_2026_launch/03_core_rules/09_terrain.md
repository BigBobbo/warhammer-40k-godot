# 03.09 — Terrain

**Read first:** `00_overview.md`, `03_core_rules/README.md`.
**Output:** `.llm/audit_2026_launch/findings/03_09_terrain.md`

## Scope

Enumerate rules from the Wahapedia Terrain section + current mission pack's terrain features section. Cover at minimum:
- Terrain feature categories: Hills, Obstacles, Ruins, Woods, Craters/Sand Dunes
- Cover types: Light Cover (+1 save vs. ranged), Heavy Cover (verify exact rule)
- Ruins: walls block LoS for non-FLY ground; INFANTRY/BEAST/SWARM may climb; upper-floor occupancy restricted to INFANTRY / SWARM / BEAST / FLY
- Benefit of Cover trigger (some part of base inside terrain footprint OR wholly behind an obstacle of certain height)
- Obscuring (if used in current mission pack)
- Towering keyword: can draw LoS over Ruin walls
- Vertical movement on terrain (1:1 cost)
- Models cannot end on impassable terrain
- Terrain feature placement rules (pre-game, mission-specified zones)

## Codebase entry points

`40k/autoloads/TerrainManager.gd`, `40k/autoloads/LineOfSightManager.gd`, `40k/autoloads/EnhancedLineOfSight.gd`, `40k/terrain_layouts/*.json`, `40k/scripts/TerrainPainter.gd` (if exists), `40k/shaders/tilepack_board.gdshader`.

## Live-validation focus

- Place a model behind a Ruin wall, attempt to draw LoS through → blocked for non-FLY
- Towering unit attempting to draw LoS over the same wall → allowed
- INFANTRY climb to upper floor of Ruin → allowed; VEHICLE attempt → rejected
- Within-terrain cover trigger vs. wholly-behind-obstacle cover trigger — both should grant +1 save
- Indirect Fire override of cover → confirm +1 cover applies regardless of LoS

## Prior-audit overlap

- Benefit of Cover plumbing (ruins/obstacle/barricade = within-or-behind; woods/crater/area_terrain/forest = within-only) → save flow → cap — verified 2026-05
- Indirect Fire automatic cover override — `RulesEngine.gd:3036`
- Difficult terrain trait — `T3-16`

`TERRAIN_LAYOUTS_AUDIT.md` covers existing terrain layouts.

## Output prose

Top 3 launch-blocker terrain gaps; top 3 invisible features. Particularly: terrain features that exist as data (`terrain_layouts/*.json`) but have no engine effect, or LoS algorithms that diverge between the simple and Enhanced LoS managers.
