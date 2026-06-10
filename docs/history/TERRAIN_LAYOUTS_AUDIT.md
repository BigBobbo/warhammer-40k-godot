# Phase 3: Terrain Layouts - Audit Report

## Status: COMPLETE

**Branch**: `claude/phase-3-terrain-layouts-t1iv6`
**Date**: 2026-02-13

---

## What Was Implemented

### 1. Data-Driven Terrain Loading System
- **New directory**: `40k/terrain_layouts/` with 8 JSON layout files
- **JSON format** stores terrain piece definitions with:
  - Position in inches (converted to pixels at load time via `Measurement.PX_PER_INCH`)
  - Size in inches (small 6x4, medium 10x5, large 12x6)
  - Height category (low/medium/tall) for LoS rules
  - Rotation in degrees
  - Wall definitions in piece-local coordinates (auto-converted to world space)
  - Layout metadata: name, description, recommended deployments

### 2. TerrainManager.gd Updates
- Added `_load_layout_from_json()` method for JSON-based terrain loading
- Added `_convert_json_walls()` for local-to-world wall coordinate transformation
- Added `_preload_layout_metadata()` for UI recommendations at startup
- Added `get_layout_metadata()`, `get_all_layout_ids()`, `get_recommended_deployments()`
- JSON loading attempted first; hardcoded Layout 2 preserved as fallback
- Save/load enhanced: stores `layout` ID and `rotation` per piece, reloads full JSON on restore

### 3. MainMenu.gd Updates
- Terrain dropdown expanded from 1 option to all 8 Chapter Approved layouts
- Default selection is Layout 1 (most popular tournament layout, ~32% of games played)

### 4. All 8 Terrain Layouts Defined

| Layout | Style | Pieces | Walls | Recommended Deployments |
|--------|-------|--------|-------|------------------------|
| 1 | Cornerstone - Big L-shapes in diagonal corners | 12 | 18 | Search & Destroy, Crucible, Hammer & Anvil |
| 2 | Classic - L-shaped corner ruins, diagonal center | 12 | 18 | Hammer & Anvil, Dawn of War, Crucible |
| 3 | Open Field - Sparse terrain, long firing lanes | 12 | 15 | Dawn of War, Hammer & Anvil |
| 4 | Close Quarters - Dense center, 10" apart | 12 | 16 | Search & Destroy, Sweeping, Crucible |
| 5 | Flanking Lines - Side-to-side optimized | 12 | 16 | Sweeping Engagement, Dawn of War |
| 6 | Balanced Grid - Even distribution | 12 | 18 | All deployments |
| 7 | Corridor - L-shapes 8" from edges | 12 | 16 | Hammer & Anvil |
| 8 | Fortress - U-shaped ruins, low center | 12 | 17 | Hammer & Anvil, Crucible |

---

## Architecture Decisions

### Why JSON over GDScript methods?
- **Extensibility**: Users can create custom layouts by adding JSON files
- **Separation of concerns**: Layout data separate from code logic
- **Consistency**: All layouts use the same loading pipeline
- **Moddability**: No code changes needed for new layouts

### Why local wall coordinates?
- Walls are defined relative to terrain piece center before rotation
- TerrainManager applies rotation and translation automatically
- This makes layouts easier to author and modify
- Eliminates manual pixel coordinate calculation per rotated piece

### Backward compatibility
- The hardcoded `_setup_layout_2()` is preserved as fallback if JSON loading fails
- Existing save files without layout metadata will reconstruct terrain from raw position data
- The `_add_sample_walls_to_terrain()` fallback remains for the hardcoded path

---

## Known Limitations / Future Work

### APPROXIMATE Terrain Positions
Terrain positions are **approximate**, derived from publicly available descriptions of the GW Chapter Approved Tournament Companion layouts (Goonhammer articles, web searches). The official GW PDF (https://assets.warhammer-community.com/eng_4-xglmycxyvf.pdf) returned 403 during development.

**Action needed**: When the official PDF becomes accessible, verify and adjust positions in each `layout_*.json` file.

### Wall Coverage
Not every terrain piece has walls. Current wall coverage:
- Most TALL pieces have 1-2 LoS-blocking solid walls
- MEDIUM pieces have 1 solid or window wall
- LOW pieces generally have no walls
- Wall types: solid (blocks LoS), window (doesn't block LoS), door (opening)

**Action needed**: Add more detailed wall configurations to match the official layout cards.

### No Terrain-Deployment Pairing UI
The `recommended_deployments` metadata is stored in each layout JSON but not yet surfaced in the UI. The MainMenu dropdown allows any terrain+deployment combination.

**Action needed**: Phase 4 or later could add a recommendation indicator in the UI.

---

## Files Changed

| File | Change Type | Description |
|------|-------------|-------------|
| `40k/autoloads/TerrainManager.gd` | Modified | Added JSON loading, wall conversion, metadata preload |
| `40k/scripts/MainMenu.gd` | Modified | Expanded terrain dropdown to 8 options |
| `40k/terrain_layouts/layout_1.json` | New | Cornerstone layout definition |
| `40k/terrain_layouts/layout_2.json` | New | Classic layout definition (JSON version) |
| `40k/terrain_layouts/layout_3.json` | New | Open Field layout definition |
| `40k/terrain_layouts/layout_4.json` | New | Close Quarters layout definition |
| `40k/terrain_layouts/layout_5.json` | New | Flanking Lines layout definition |
| `40k/terrain_layouts/layout_6.json` | New | Balanced Grid layout definition |
| `40k/terrain_layouts/layout_7.json` | New | Corridor layout definition |
| `40k/terrain_layouts/layout_8.json` | New | Fortress layout definition |

---

## Suggested Next Task

Based on the `PLAN_missions_deployments_terrain.md` roadmap:

### Phase 4: Polish & Rules
1. **Objective position verification** for all deployment maps - Cross-check objective positions in `DeploymentZoneData.gd` against official deployment cards
2. **Terrain position refinement** - Verify terrain positions against official PDF when available
3. **Player-2 end-of-game scoring adjustment** - Player going second scores end of Turn 5 instead of Command phase
4. **Terrain-deployment pairing UI** - Show recommended layout+deployment pairings in the MainMenu

### Alternative: Phase 2 Completion (Mission Infrastructure)
If Phase 2 is not yet complete, the next priority should be:
1. Implement `Scorched Earth` mission (burn mechanic for objectives)
2. Implement `Purge the Foe` mission (kill/hold comparison scoring)
3. Implement `Supply Drop` mission (objective removal mechanic)
4. Wire mission selection through config to MissionManager
