# Plan: Adding Missions, Deployment Zones, and Terrain Layouts

## Current State

The game currently supports **one** of each:
- **Mission**: Take and Hold
- **Deployment Zone**: Hammer and Anvil (functions misleadingly named `_get_dawn_of_war_zone_*_coords()`)
- **Terrain Layout**: Chapter Approved Layout 2

The architecture already has dropdowns in the Main Menu and a config dictionary passed to `_initialize_game_with_config()`, so the plumbing for selection exists. The work is in defining the data and wiring it through.

---

## Scope of Work

### A. Deployment Zones (4 new + fix existing)
### B. Objective Positions per Deployment Map (5 maps)
### C. Primary Missions (4-5 new)
### D. Terrain Layouts (7 new)
### E. Mission Rules (stretch goal)

---

## A. Deployment Zones

Board is 44" wide x 60" tall. All coordinates in inches. Origin is top-left (0,0).

### A1. Fix existing naming
**File**: `GameState.gd`
- Rename `_get_dawn_of_war_zone_1_coords()` -> `_get_hammer_anvil_zone_1_coords()`
- Rename `_get_dawn_of_war_zone_2_coords()` -> `_get_hammer_anvil_zone_2_coords()`

### A2. Refactor `initialize_default_state()` to accept deployment type
**File**: `GameState.gd`
- Add parameter to `initialize_default_state()` or add new method `set_deployment_zones(deployment_type: String)`
- `deployment_zones` in `state.board` should be set based on the selected deployment type

### A3. Define all 5 deployment zone types

#### 1. Hammer and Anvil (EXISTS)
- Players deploy on **short edges** (top/bottom)
- P1 Zone: full width (0-44"), depth 12" from top (y: 0-12)
- P2 Zone: full width (0-44"), depth 12" from bottom (y: 48-60)
- No Man's Land: 24" gap

```
P1: [(0,0), (44,0), (44,12), (0,12)]
P2: [(0,48), (44,48), (44,60), (0,60)]
```

#### 2. Dawn of War (NEW)
- Players deploy on **long edges** (left/right)
- P1 Zone: full height (0-60"), depth 12" from left (x: 0-12)
- P2 Zone: full height (0-60"), depth 12" from right (x: 32-44)
- No Man's Land: 20" gap

```
P1: [(0,0), (12,0), (12,60), (0,60)]
P2: [(32,0), (44,0), (44,60), (32,60)]
```

#### 3. Search and Destroy (NEW)
- Players deploy in **opposite corners**
- Each zone is a rectangle in the corner, extending 9" from center along each axis
- P1 Zone: top-left quadrant corner area
- P2 Zone: bottom-right quadrant corner area
- Zone definitions (approximately 24x24" rectangles offset by 9" from center):

```
P1: [(0,0), (22,0), (22,6), (6,6), (6,24), (0,24)]
  (L-shaped zone: top strip 22" wide x 6" deep + left strip 6" wide x 24" deep)
P2: [(22,36), (38,36), (38,54), (44,54), (44,60), (22,60)]
  (mirrored L-shape in bottom-right)
```

Note: The exact Search and Destroy zone shapes are L-shaped. The deployment zone covers the entire corner up to about 24" from each player's corner along both axes, with a 9" exclusion from center. These dimensions should be verified against the official deployment card.

#### 4. Sweeping Engagement (NEW - Pariah Nexus version)
- Stepped deployment along long edges
- P1 Zone (left side): 8" deep on the outer portion, stepping out to 14" in the middle
- P2 Zone (right side): mirror of P1

```
P1: [(0,0), (8,0), (8,12), (14,12), (14,48), (8,48), (8,60), (0,60)]
P2: [(36,0), (44,0), (44,60), (36,60), (36,48), (30,48), (30,12), (36,12)]
```

Note: The exact step dimensions need verification against the official card. The Pariah Nexus version replaced the original diagonal zones with stepped zones.

#### 5. Crucible of Battle (NEW)
- Stepped deployment along short edges
- P1 Zone (top): 8" deep on sides, stepping to 14" in the center
- P2 Zone (bottom): mirror

```
P1: [(0,0), (44,0), (44,8), (34,8), (34,14), (10,14), (10,8), (0,8)]
P2: [(0,52), (10,52), (10,46), (34,46), (34,52), (44,52), (44,60), (0,60)]
```

Note: These approximate the stepped variant. Exact dimensions need verification.

### A4. Implementation steps for deployment zones

1. **Create `DeploymentZoneData.gd`** (new file in `autoloads/` or `scripts/data/`)
   - Dictionary mapping deployment_type_id -> zone polygon coordinates for each player
   - Static method: `get_zones(deployment_type: String) -> Array[Dictionary]`
   - Static method: `get_objectives(deployment_type: String) -> Array[Dictionary]`

2. **Update `GameState.gd`**:
   - `initialize_default_state()` accepts deployment type
   - Calls `DeploymentZoneData.get_zones(type)` instead of hardcoded `_get_dawn_of_war_zone_*`
   - Remove/deprecate the old `_get_dawn_of_war_zone_*` functions

3. **Update `MainMenu.gd`**:
   - Add all 5 deployment options to `deployment_options` array
   - Pass selected deployment to game initialization

4. **Update `MissionManager.gd`**:
   - `_setup_strike_force_objectives()` should accept deployment type
   - Objective positions vary by deployment map
   - Call `DeploymentZoneData.get_objectives(type)`

5. **Update `DeploymentController.gd`** and `DeploymentZoneVisual.gd`**:
   - Should already work with polygon-based zones (verify)
   - May need updates if they assume rectangular zones

---

## B. Objective Positions per Deployment Map

Each deployment map defines 5 objective positions. These are the approximate standard positions:

### Hammer and Anvil (EXISTS)
```
obj_home_1: (22, 6)    # Center of P1 zone
obj_nml_1:  (10, 20)   # No man's land, P1 side
obj_center: (22, 30)   # Board center
obj_nml_2:  (34, 40)   # No man's land, P2 side
obj_home_2: (22, 54)   # Center of P2 zone
```
Current positions are close: (22,30), (10,14), (34,14), (10,46), (34,46). These should be reviewed against the official card.

### Dawn of War
```
obj_home_1: (6, 30)    # Center of P1 zone (left)
obj_nml_1:  (16, 15)   # No man's land, upper
obj_center: (22, 30)   # Board center
obj_nml_2:  (28, 45)   # No man's land, lower
obj_home_2: (38, 30)   # Center of P2 zone (right)
```

### Search and Destroy
```
obj_home_1: (6, 6)     # P1 corner
obj_nml_1:  (11, 22)   # No man's land near P1
obj_center: (22, 30)   # Board center
obj_nml_2:  (33, 38)   # No man's land near P2
obj_home_2: (38, 54)   # P2 corner
```

### Sweeping Engagement
```
obj_home_1: (6, 30)    # P1 zone center
obj_nml_1:  (18, 15)   # No man's land, upper
obj_center: (22, 30)   # Board center
obj_nml_2:  (26, 45)   # No man's land, lower
obj_home_2: (38, 30)   # P2 zone center
```

### Crucible of Battle
```
obj_home_1: (22, 6)    # P1 zone center
obj_nml_1:  (10, 20)   # No man's land left
obj_center: (22, 30)   # Board center
obj_nml_2:  (34, 40)   # No man's land right
obj_home_2: (22, 54)   # P2 zone center
```

**Note**: All objective positions above are approximate. The exact positions should be verified against the official Chapter Approved 2025-26 deployment cards. Each objective is a 40mm (1.57") diameter flat marker.

---

## C. Primary Missions

### C1. Mission data structure

Create a **mission registry** in `MissionManager.gd` or a new `MissionData.gd` file:

```gdscript
var MISSIONS = {
    "take_and_hold": {
        "name": "Take and Hold",
        "scoring_type": "hold_objectives",
        "start_round": 2,
        "vp_per_objective": 5,
        "max_vp_per_turn": 15,
        "max_vp_total": 50,
        "special_rules": []
    },
    "scorched_earth": {
        "name": "Scorched Earth",
        "scoring_type": "hold_and_burn",
        "start_round": 2,
        "vp_per_objective": 5,
        "max_vp_per_turn": 10,
        "max_vp_total": 50,
        "special_rules": ["burn_objectives"]
    },
    ...
}
```

### C2. Missions to implement

#### 1. Take and Hold (EXISTS)
- 5VP per objective held, max 15VP/turn
- Scoring: Command phase from Round 2
- Player going second scores end of Turn 5 instead of Command phase

#### 2. Scorched Earth (NEW)
- 5VP per objective held, max 10VP/turn (note: lower cap than Take and Hold)
- **Burn action**: Starting Round 2, one unit within range of a no-man's-land or enemy deployment zone objective can start a burn action
- Burn completes at end of opponent's next turn
- Burned objective is removed from the board
- Bonus: +5VP per no-man's-land objective burned, +10VP for enemy deployment zone objective burned
- **Implementation needs**:
  - New "burn" action on objectives
  - Track burn-in-progress state per objective
  - Objective removal mechanic
  - Visual indicator for burning objectives

#### 3. Supply Drop (NEW)
- Only score VP from no-man's-land objectives (not home objectives)
- 5VP per no-man's-land objective held, starting Round 2
- Turn 4: Randomly remove one no-man's-land objective
- Turn 5: Only one no-man's-land objective remains, worth extra VP
- **Implementation needs**:
  - Filter scoring to only no-man's-land objectives
  - Random objective removal at turn boundaries
  - Visual update when objectives disappear

#### 4. Purge the Foe (NEW)
- Holding objectives: 4VP if you hold any, 8VP if you hold more than opponent
- Destroying units: 4VP for destroying any enemy unit, 8VP if you destroyed more than opponent
- Scored each Command phase from Round 2
- **Implementation needs**:
  - Track unit destruction counts per turn per player
  - Compare holding counts between players
  - Compare destruction counts between players

#### 5. Sites of Power (NEW - if still in the 2025-26 pool)
- Character must be on a no-man's-land objective
- 5VP at start for placing character, continues to award VP while character stays
- Even if opponent takes control, character staying awards points
- **Implementation needs**:
  - Track which objectives have characters on them
  - Per-objective VP tracking separate from control

### C3. Implementation steps for missions

1. **Create mission data registry** - define all missions with their rules as data
2. **Refactor `MissionManager.initialize_default_mission()`** to accept mission ID from config
3. **Update `score_primary_objectives()`** to dispatch to mission-specific scoring logic
4. **Add mission-specific scoring methods**:
   - `_score_take_and_hold()`
   - `_score_scorched_earth()`
   - `_score_supply_drop()`
   - `_score_purge_the_foe()`
5. **Add objective modification methods** (for Scorched Earth burn, Supply Drop removal)
6. **Update `MainMenu.gd`** with all mission options
7. **Wire mission selection through config to MissionManager**
8. **Add UI elements** for mission-specific actions (burn button for Scorched Earth)

---

## D. Terrain Layouts

### D1. Current Layout 2 structure
Layout 2 uses 12 terrain pieces:
- 4x 6"x4" ruins (240x160px)
- 2x 10"x5" ruins (400x200px)
- 6x 12"x6" ruins (480x240px)
- Various rotations and wall configurations

### D2. Terrain layouts to add

All GW Tournament Companion layouts use the same 44"x60" board and generally the same terrain piece sizes. Each layout varies in:
- **Number of pieces** (typically 10-14)
- **Positions** on the board
- **Rotations**
- **Height categories** (which affects LoS)
- **Wall configurations**

The exact positions for each layout are defined in the official Chapter Approved Tournament Companion PDF. Since we cannot currently access the PDF directly, the implementation approach should be:

#### Layouts 1 through 8

Each layout needs to be added as a new method in `TerrainManager.gd`:
- `_setup_layout_1()` through `_setup_layout_8()`

The standard terrain piece sizes used across layouts are:
- **Small**: 6"x4" (240x160px)
- **Medium**: 10"x5" (400x200px)
- **Large**: 12"x6" (480x240px)

### D3. Terrain-Deployment pairing

The Tournament Companion recommends specific terrain layout + deployment pairings:
- Layout 5 is only recommended for Sweeping Engagement and Dawn of War
- Layout 8 works well on Hammer and Anvil and Crucible of Battle
- Other pairings exist but are less critical

The game could optionally show recommended pairings in the UI but should allow any combination.

### D4. Implementation steps for terrain

1. **Add layout methods** to `TerrainManager.gd` (`_setup_layout_1()` through `_setup_layout_8()`)
2. **Update the `match` statement** in `load_terrain_layout()` to handle all layouts
3. **Update `MainMenu.gd`** `terrain_options` array with all 8 layouts
4. **Define terrain positions** - Each layout needs exact positions from the official PDF. These should be entered by referencing the physical layout cards. As a starting point, terrain pieces should be placed to:
   - Block major firing lanes
   - Provide cover in no-man's-land
   - Be roughly symmetrical
   - Not overlap deployment zone edges awkwardly
5. **Add wall configurations** for each layout's terrain pieces

### D5. Data-driven terrain alternative

Instead of hardcoding each layout, consider a data-driven approach:
- Create JSON files in a `terrain_layouts/` directory
- Each JSON defines terrain pieces, positions, rotations, walls
- `TerrainManager` loads from JSON instead of GDScript methods
- This makes it easier for users to create custom layouts

Example JSON structure:
```json
{
    "id": "layout_1",
    "name": "Chapter Approved Layout 1",
    "pieces": [
        {
            "id": "ruins_1",
            "type": "ruins",
            "position": [720, 200],
            "size": [240, 160],
            "height": "tall",
            "rotation": 90.0,
            "walls": [
                {
                    "id": "wall_north",
                    "start": [640, 80],
                    "end": [800, 80],
                    "type": "solid",
                    "blocks_los": true
                }
            ]
        }
    ]
}
```

---

## E. Mission Rules (Stretch Goal)

The Chapter Approved deck includes 12 different Mission Rules that modify gameplay. These are separate from Primary Missions and add additional conditions. Examples:

- **Chilling Rain**: No Overwatch allowed
- **Sweep and Clear**: Units that kill an enemy unit in melee can immediately consolidate onto a nearby objective
- **Hidden Supplies**: Extra objectives placed during the game
- Etc.

These are lower priority but the architecture should support them. A `MissionRule` system could be added that hooks into phase events.

---

## Implementation Order (Recommended)

### Phase 1: Deployment Zone Infrastructure
1. Create `DeploymentZoneData.gd` with all 5 deployment zone definitions
2. Refactor `GameState.gd` to use the new data source
3. Update `MainMenu.gd` dropdown with all options
4. Wire deployment selection through to game initialization
5. Test each deployment zone renders correctly

### Phase 2: Mission Infrastructure
1. Create mission data registry
2. Refactor `MissionManager.gd` to support multiple missions
3. Implement `Scorched Earth` (moderate complexity - adds burn mechanic)
4. Implement `Purge the Foe` (moderate - tracks kills and comparisons)
5. Implement `Supply Drop` (moderate - objective removal)
6. Update `MainMenu.gd` with mission options
7. Wire mission selection through to MissionManager

### Phase 3: Terrain Layouts
1. Design data-driven terrain loading (JSON or extended GDScript)
2. Implement layouts 1, 3-8 (Layout 2 exists)
3. Add wall configurations for each
4. Update `MainMenu.gd` terrain dropdown
5. Optional: Add terrain-deployment pairing recommendations to UI

### Phase 4: Polish & Rules
1. Objective position verification for all deployment maps
2. Player-2 end-of-game scoring adjustment
3. Mission Rules system (stretch)
4. Challenger system (stretch)

---

## Files That Need Changes

| File | Changes |
|------|---------|
| `autoloads/GameState.gd` | Refactor deployment zone setup, accept deployment type parameter |
| `autoloads/MissionManager.gd` | Multi-mission support, scoring dispatch, objective modification |
| `autoloads/TerrainManager.gd` | Add layouts 1, 3-8; optional JSON loading |
| `scripts/MainMenu.gd` | Add all options to dropdowns, wire config |
| `scripts/DeploymentController.gd` | Verify polygon-based zone validation works for all shapes |
| `scripts/DeploymentZoneVisual.gd` | Verify rendering works for non-rectangular zones |
| `scripts/ObjectiveVisual.gd` | Support objective removal/burning visual states |
| `scripts/Main.gd` | Pass deployment type and mission type during init |
| **NEW**: `scripts/data/DeploymentZoneData.gd` | Deployment zone & objective position definitions |
| **NEW**: `scripts/data/MissionData.gd` | Mission definitions and rules |
| **NEW** (optional): `terrain_layouts/*.json` | Data-driven terrain layout files |

---

## Key Risks & Considerations

1. **Exact positions unknown**: The official deployment card positions and terrain layout positions are in the GW PDF which returned 403. Positions in this plan are approximate and need to be verified against the physical cards or PDF.

2. **Non-rectangular zones**: Search and Destroy, Sweeping Engagement, and Crucible of Battle use L-shaped or stepped polygons. The existing `DeploymentController` needs verification that it handles concave polygon validation correctly (Godot's `Geometry2D.is_point_in_polygon()` does support concave polygons).

3. **Multiplayer sync**: All mission/deployment state must be synchronized between players. The existing `NetworkManager` handles GameState sync, but new state (burn actions, objective removal) must be included.

4. **Save/Load**: New mission types and deployment zones need to save/load correctly. The `SaveLoadManager` serializes GameState, so new fields must be serializable.

5. **Scorched Earth complexity**: The burn mechanic is the most complex new feature - it requires an action system (start burn, track progress, complete burn, remove objective) that spans multiple player turns.

---

## Sources

- [Goonhammer: 10th Edition Mission Pack Review](https://www.goonhammer.com/goonhammer-reviews-warhammer-40000-10th-edition-part-4-the-mission-pack/)
- [Goonhammer: 2025-26 Tournament Companion Review](https://www.goonhammer.com/goonhammer-reviews-the-2025-26-tournament-companion/)
- [Goonhammer: Pariah Nexus Deployments Math](https://www.goonhammer.com/hammer-of-math-pariah-nexus-deployments/)
- [Goonhammer: Terrain Layout 1](https://www.goonhammer.com/40k-start-competing-gw-terrain-layout-1/)
- [Goonhammer: Terrain Layout 6](https://www.goonhammer.com/40k-start-competing-gw-terrain-layout-6/)
- [Goonhammer: Terrain Layout 8](https://www.goonhammer.com/40k-start-competing-gw-terrain-layout-8/)
- [Spikey Bits: Chapter Approved Mission Deck Review](https://spikeybits.com/new-warhammer-40k-chapter-approved-mission-deck-objectives/)
- [Official GW Tournament Companion PDF](https://assets.warhammer-community.com/eng_4-xglmycxyvf.pdf)
- [Interactive Layout Tool](https://tabletop.labrador.dev/40k_layouts)
