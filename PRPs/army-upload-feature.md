# PRP: Army List Upload Feature

## Problem Statement

Users currently can only use pre-built army JSON files that ship with the game (`40k/armies/*.json`). They cannot import their own army lists from popular list-building tools like ListEngine, New Recruit, or the GW App. Creating a JSON file by hand is impractical because the game's format requires full datasheet data (stats, weapons, abilities, keywords, model counts, base sizes) — not just unit names and points.

## Proposed Solution: Static Web Frontend on Existing Server

Add a **static HTML/JS army upload tool** served from the existing Fly.io relay server. No new hosting costs. The tool lives at `https://warhammer-40k-godot.fly.dev/army-builder`.

### Architecture Overview

```
┌──────────────────────────────────────────────┐
│  User's Browser                              │
│                                              │
│  ┌────────────────────────────────────────┐  │
│  │  Army Builder Web App (static HTML/JS) │  │
│  │                                        │  │
│  │  1. User pastes army list text         │  │
│  │  2. Parser extracts unit names/config  │  │
│  │  3. Lookup unit data from bundled DB   │  │
│  │  4. Generate game-compatible JSON      │  │
│  │  5. Upload via existing /api/armies    │  │
│  └────────────────┬───────────────────────┘  │
│                   │                          │
└───────────────────┼──────────────────────────┘
                    │ HTTP PUT /api/armies/:name
                    ▼
┌──────────────────────────────────────────────┐
│  Fly.io Server (relay-server.js)             │
│                                              │
│  ┌──────────────┐  ┌──────────────────────┐  │
│  │ Static Files  │  │ Existing REST API    │  │
│  │ /public/      │  │ /api/armies/:name    │  │
│  │ - index.html  │  │ (already exists!)    │  │
│  │ - app.js      │  │                      │  │
│  │ - style.css   │  │ SQLite army_lists    │  │
│  │ - data/*.json │  │ table (exists!)      │  │
│  └──────────────┘  └──────────────────────┘  │
└──────────────────────────────────────────────┘
                    │
                    │ CloudStorage.get_army()
                    ▼
┌──────────────────────────────────────────────┐
│  Godot Game (browser or desktop)             │
│  - ArmyListManager loads from cloud armies   │
│  - User selects uploaded army in lobby        │
└──────────────────────────────────────────────┘
```

### Why This Approach

| Consideration | Decision |
|---|---|
| **No extra hosting cost** | Static files served from existing Fly.io server |
| **No extra backend** | Parsing happens client-side in JS; uses existing `/api/armies` REST endpoint |
| **Existing infrastructure** | `army_lists` SQLite table, `CloudStorage.gd` client, `ArmyListManager.gd` loader all exist |
| **Offline-capable** | Could also work as a downloaded HTML file (except the upload step) |
| **Maintainable** | Pure HTML/JS/CSS, no framework, no build step |

---

## Detailed Implementation Plan

### Phase 1: Datasheet Database (the hardest part)

The core challenge is that a pasted army list only contains unit names, points, and selected wargear. But the game JSON needs full stats, all weapon profiles, abilities, keywords, model counts, and base sizes. This data must come from somewhere.

**Approach: Build a JSON datasheet database from Wahapedia CSV exports.**

Wahapedia provides [pipe-delimited CSV exports](https://wahapedia.ru/wh40k10ed/the-rules/data-export/) with tables for:
- `Datasheets.csv` — unit profiles (M, T, Sv, W, Ld, OC per datasheet)
- `Datasheets_abilities.csv` — abilities linked to datasheets
- `Datasheets_keywords.csv` — keywords per datasheet
- `Datasheets_wargear.csv` — wargear options
- `Datasheets_models.csv` — model composition (counts, base sizes)
- `Wargear_list.csv` — weapon profiles (type, range, A, BS/WS, S, AP, D, special)

**Build step:** A Node.js script (`server/tools/build-datasheet-db.js`) that:
1. Downloads Wahapedia CSVs (or reads from local copies)
2. Joins them by `datasheet_id`
3. Outputs a single `datasheets.json` file organized by faction → unit name
4. This file is placed in `server/public/data/datasheets.json` and served statically

**Output structure per unit:**
```json
{
  "Space Marines": {
    "Intercessor Squad": {
      "faction": "Space Marines",
      "name": "Intercessor Squad",
      "keywords": ["INFANTRY", "PRIMARIS", "IMPERIUM", "ADEPTUS ASTARTES"],
      "stats": {
        "move": 6, "toughness": 4, "save": 3,
        "wounds": 2, "leadership": 6, "objective_control": 2
      },
      "weapons": [
        {
          "name": "Bolt rifle",
          "type": "Ranged",
          "range": "24",
          "attacks": "2",
          "ballistic_skill": "3",
          "strength": "4",
          "ap": "-1",
          "damage": "1",
          "special_rules": "assault, heavy"
        }
      ],
      "abilities": [
        {
          "name": "Oath of Moment",
          "type": "Faction",
          "description": "..."
        }
      ],
      "unit_composition": {
        "min": 5, "max": 10,
        "models": [
          {"description": "1 Intercessor Sergeant", "line": 1},
          {"description": "4-9 Intercessors", "line": 2}
        ]
      },
      "base_mm": 32,
      "points_per_model_count": {
        "5": 90,
        "10": 180
      },
      "leader_data": null,
      "can_lead": null,
      "transport_capacity": null,
      "wargear_options": [...]
    }
  }
}
```

**Estimated size:** ~2-5MB compressed for all factions. Can be lazy-loaded per faction.

**Alternative approach (simpler, less comprehensive):** Instead of full Wahapedia ingestion, start with a manually curated database covering 3-5 popular factions (Space Marines, Orks, Custodes, Necrons, Tyranids). Expand over time. This is more realistic for a first pass.

---

### Phase 2: Text Parser (client-side JavaScript)

The parser needs to handle the common text formats used when sharing army lists. These formats are quite consistent:

**Standard format (used by GW App, New Recruit, ListEngine):**
```
Faction Name (Points)
Detachment Name

Unit Name (Points)
  • Wargear 1
  • Wargear 2
  • Enhancement: Enhancement Name

Unit Name (Points)
  • Wargear 1
```

**Parser pipeline:**
```
Raw Text Input
    │
    ▼
┌─────────────────────────┐
│ 1. Normalize whitespace  │
│ 2. Detect format variant │
│ 3. Extract header:       │
│    - Faction name        │
│    - Total points        │
│    - Detachment          │
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│ 4. Split into unit      │
│    blocks (blank-line    │
│    separated)            │
│ 5. For each unit block:  │
│    - Extract unit name   │
│    - Extract points      │
│    - Extract wargear     │
│    - Extract enhancement │
│    - Extract model count │
│      (if specified)      │
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│ 6. Fuzzy-match unit     │
│    names against DB      │
│ 7. Look up full stats   │
│ 8. Generate game JSON   │
└─────────────────────────┘
```

**Key parsing rules:**
- Unit header line: name followed by `(###)` or `(### pts)` or `(### points)`
- Wargear lines: indented or prefixed with `•`, `·`, `-`, `*`, or numbered
- Enhancement lines: contain "Enhancement:" or "Enhancements:" prefix
- Blank lines separate units
- First non-blank section is the army header (faction + detachment)

**Fuzzy matching:** Unit names in pasted text may not exactly match the database. Use Levenshtein distance or token-based matching (e.g., "Intercessors" should match "Intercessor Squad").

---

### Phase 3: JSON Generator

Converts parsed units + looked-up datasheet data into the game's army JSON format.

**For each parsed unit:**
1. Look up full datasheet from the database
2. Generate a unique unit ID: `U_{UNIT_NAME_UPPER}_{LETTER}` (e.g., `U_INTERCESSORS_A`)
   - Increment letter suffix for duplicate unit types
3. Determine model count from points (most units have fixed points-per-size tiers)
4. Generate `models` array with correct wound values and base sizes
5. Filter weapons to match selected wargear (if specified)
6. Include all abilities from datasheet
7. Set `owner: 1`, `status: "UNDEPLOYED"`, etc.

**Output format matches existing army JSON exactly** — as validated by `ArmyListManager.validate_army_structure()`.

---

### Phase 4: Web Frontend (static HTML/JS/CSS)

**Location:** `server/public/` directory

**Files:**
- `index.html` — Main page
- `army-builder.html` — The army upload tool (or a route in index.html)
- `css/style.css` — Styling
- `js/parser.js` — Text parsing logic
- `js/generator.js` — JSON generation
- `js/app.js` — UI logic, API calls
- `data/datasheets.json` — Unit database (or per-faction files)

**UI Flow:**

```
┌──────────────────────────────────────────────────┐
│                ARMY LIST UPLOADER                 │
│                                                   │
│  ┌──────────────────────────────────────────────┐│
│  │ Paste your army list here:                   ││
│  │                                              ││
│  │ ┌──────────────────────────────────────────┐ ││
│  │ │                                          │ ││
│  │ │  (large textarea)                        │ ││
│  │ │                                          │ ││
│  │ └──────────────────────────────────────────┘ ││
│  │                                              ││
│  │ [Parse Army List]                            ││
│  └──────────────────────────────────────────────┘│
│                                                   │
│  ┌──────────────────────────────────────────────┐│
│  │ PARSED RESULTS                               ││
│  │                                              ││
│  │ Faction: Space Marines                       ││
│  │ Detachment: Gladius Task Force               ││
│  │ Points: 2000                                 ││
│  │                                              ││
│  │ ✅ Intercessor Squad (90 pts) — matched      ││
│  │ ✅ Bladeguard Veterans (100 pts) — matched   ││
│  │ ⚠️ Captain (80 pts) — ambiguous match        ││
│  │    → [Captain in Terminator Armour]          ││
│  │    → [Captain with Jump Pack]                ││
│  │    → [Captain in Phobos Armour]              ││
│  │ ❌ Custom Character — not found in database  ││
│  │                                              ││
│  │ [Download JSON]  [Upload to Game Server]     ││
│  └──────────────────────────────────────────────┘│
│                                                   │
│  ┌──────────────────────────────────────────────┐│
│  │ JSON PREVIEW                                 ││
│  │ ┌──────────────────────────────────────────┐ ││
│  │ │ { "faction": { ... }, "units": { ... } } │ ││
│  │ └──────────────────────────────────────────┘ ││
│  └──────────────────────────────────────────────┘│
└──────────────────────────────────────────────────┘
```

**Features:**
1. **Paste & Parse** — Large textarea, parse button
2. **Match Review** — Show matched/unmatched units with manual override options
3. **JSON Preview** — Expandable JSON viewer so users can verify
4. **Download** — Download the JSON file directly (works without server)
5. **Upload** — Push to the game server via `PUT /api/armies/:name`
   - Requires the player ID from the game (shown in-game, entered here)
   - OR: Generate a shareable link/code

---

### Phase 5: Server Changes

**Minimal changes to `relay-server.js`:**

1. **Serve static files** — Add static file serving for the `/public` directory:
```javascript
// In handleHTTPRequest, before the API routing:
if (parts[0] !== 'api') {
  return serveStaticFile(req, res);
}
```

2. **Add a new public army upload endpoint** (optional enhancement):
```
POST /api/armies/public/:name
```
This would allow uploading armies without a player ID, generating a shareable code. The game could then import by code. However, the existing player-ID-based system works fine as a first pass.

3. **Add CORS for the static page** — Already configured (`Access-Control-Allow-Origin: *`).

**No changes needed to the Godot game** for the basic flow, because:
- `CloudStorage.gd` already has `list_armies()`, `get_army()`, `put_army()`
- `ArmyListManager.gd` already loads from `user://armies/`
- The game already has army selection dropdowns in lobbies

**One small Godot enhancement (Phase 6):** Make the game's lobby UI also show cloud-stored armies alongside the bundled ones. Currently `get_available_armies()` only scans `res://` and `user://` directories — it doesn't query the cloud API. This bridge would let uploaded armies appear in the dropdown.

---

### Phase 6: Godot Integration (connecting cloud armies to game UI)

**Changes to `ArmyListManager.gd`:**
- Add `load_cloud_armies()` method that calls `CloudStorage.list_armies()`
- On response, merge cloud army names into `available_armies` array
- When loading a cloud army, fetch via `CloudStorage.get_army()` instead of reading from file

**Changes to `MainMenu.gd` / `WebLobby.gd`:**
- After scanning local armies, also fetch cloud armies
- Show cloud armies in dropdown with a "(cloud)" suffix or icon
- When selected, download the army JSON before game start

---

## Implementation Order

| Step | What | Effort | Dependency |
|------|------|--------|------------|
| 1 | Add static file serving to relay-server.js | Small | None |
| 2 | Build initial datasheet DB (start with 3-5 factions manually or via Wahapedia CSV) | Medium-Large | None |
| 3 | Build text parser in JS | Medium | None |
| 4 | Build JSON generator in JS | Medium | Step 2 |
| 5 | Build web UI (HTML/CSS/JS) | Medium | Steps 3, 4 |
| 6 | Connect Godot game to cloud armies | Small | Step 1 |
| 7 | Test end-to-end: paste → parse → upload → play | Small | All above |
| 8 | Expand datasheet DB to more factions | Ongoing | Step 2 |

---

## Key Decisions & Trade-offs

### 1. Where does parsing happen?
**Client-side (chosen)** vs Server-side

Client-side is better because:
- No server load for parsing
- Works offline (except upload)
- Faster feedback loop for users
- Simpler server code

### 2. Where does the datasheet database live?
**Bundled as static JSON (chosen)** vs Server-side database

Bundled is better because:
- No API calls during parsing — instant feedback
- Can work offline
- Easy to cache
- Server stays simple

Trade-off: Larger initial page load (~2-5MB). Mitigated by:
- Lazy-load per faction (user picks faction first, then data loads)
- Aggressive caching headers

### 3. How does the Godot game discover uploaded armies?
**Cloud storage API (chosen)** — The server already has `GET /api/armies` and `GET /api/armies/:name`. The game just needs to query these endpoints in addition to scanning local files.

### 4. Player ID linking
The web tool needs to know the player's ID to upload to the right account. Options:
- **Option A:** User copies their player ID from the game's settings screen and enters it in the web tool
- **Option B:** Generate a one-time upload code in the game, enter it in the web tool
- **Option C:** The web tool generates its own player ID and the game can import by army name/code

**Recommended: Option A** (simplest). Show the player ID in the game's settings. User copies it to the web tool. The web tool stores it in localStorage for future visits.

### 5. What text formats to support initially?
- **Standard GW/New Recruit/ListEngine format** (most common)
- These are all very similar: faction header, then unit blocks with name(points) and wargear lines
- BattleScribe format can be added later (it uses `++` markers)

---

## Files to Create/Modify

### New Files
| File | Purpose |
|------|---------|
| `server/public/index.html` | Landing page / redirect |
| `server/public/army-builder.html` | Army upload tool |
| `server/public/css/style.css` | Styling |
| `server/public/js/parser.js` | Text parsing logic |
| `server/public/js/generator.js` | JSON generation |
| `server/public/js/datasheets.js` | Datasheet DB loader |
| `server/public/js/app.js` | UI logic and API |
| `server/public/data/datasheets.json` | Unit database |
| `server/tools/build-datasheet-db.js` | Wahapedia CSV → JSON converter |

### Modified Files
| File | Change |
|------|--------|
| `server/relay-server.js` | Add static file serving |
| `server/Dockerfile` | COPY public/ directory |
| `40k/autoloads/ArmyListManager.gd` | Add cloud army loading |
| `40k/scripts/MainMenu.gd` | Show cloud armies in dropdown |
| `40k/scripts/WebLobby.gd` | Show cloud armies in dropdown |

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| **Wahapedia CSVs change format** | Build script is idempotent; re-run when format changes |
| **Unit name matching fails** | Fuzzy matching + manual override UI + user can edit JSON |
| **Missing factions in DB** | Start with popular factions; users can also upload raw JSON directly |
| **Large datasheet DB size** | Lazy-load per faction; cache aggressively |
| **IP/copyright concerns with data** | Wahapedia explicitly allows derivative use with attribution |
| **Player ID UX friction** | Show ID prominently in game; store in web tool localStorage |

---

## Alternative Approaches Considered

### 1. Build army editor directly in Godot
- **Pro:** No separate web tool
- **Con:** Godot text input is poor on web; no clipboard paste support; much more complex UI in GDScript; can't easily do fuzzy matching

### 2. Use a third-party service (e.g., separate Vercel/Netlify site)
- **Pro:** Better hosting for static sites
- **Con:** Extra service to manage; user said they'd prefer not to pay for another thing

### 3. Raw JSON upload only (no parsing)
- **Pro:** Simplest to implement
- **Con:** Terrible UX; nobody wants to write 500 lines of JSON by hand

### 4. Support BattleScribe .rosz file import
- **Pro:** Direct file import from most popular tool
- **Con:** .rosz is a compressed XML format; more complex parsing; less shareable than text
- **Future consideration:** Could add as a second input method later
