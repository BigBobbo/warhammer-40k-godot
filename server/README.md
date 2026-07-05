# w40k relay server + Army Builder

Two things live here:

1. **relay-server.js** — the multiplayer relay + persistence server (WebSocket
   game relay, SQLite-backed `/api/saves` and `/api/armies`, static hosting of
   `public/`). Deployed to fly.io as `warhammer-40k-godot` (see `fly.toml`).
2. **public/** — the **Army Builder** web app served at `/`: build 40k lists in
   the browser, import existing ones, edit them, and save them where the game
   reads them.

## Army Builder

The page is a full list builder driven by the
[`@alpaca-software/40kdc-data`](https://40kdc.alpacasoft.dev) engine — the same
dataset + roster/loadout/legality code behind list-builder.alpacasoft.dev —
bundled for the browser at `public/js/vendor/40kdc-data.mjs`.

Player flow:

- **Build**: pick faction (all ~23 dataset factions; Orks / Adeptus Custodes /
  Space Marines / Agents allies have full in-game rule automation, others are
  badged), detachment, points (1000/2000), Force Disposition; add datasheets;
  per unit set squad size (real point tiers, 11e ordinal-banded pricing), edit
  wargear with legal-bounds steppers (swaps auto-balance per the authored
  wargear options), pick an enhancement, designate the warlord, attach leaders.
- **Import**: paste GW app / New Recruit (text or JSON) / ListForge /
  rosterizer exports (package importer), or the old loose format
  (`js/parser.js` fallback), or upload a saved game army JSON. Squad sizes
  snap to point tiers, loadouts normalize into legal bounds, unmatched units
  stay listed with fuzzy datasheet suggestions.
- **Validate**: live army-construction + per-unit loadout legality
  (`checkRoster`) in the validation panel. Violations never block export —
  the game loads permissively and warns, same as always.
- **Save**: *Save to cloud* (`PUT /api/armies/<name>`) makes the list appear in
  the game's army dropdowns as `<name> (Cloud)` — immediately playable, and
  editable again later via *My Lists*. Also: download game JSON, dev-mode save
  straight into `40k/armies/`, and text export via the package serializers.
- Drafts autosave to localStorage; `/#army=<name>` deep-links a cloud list.

In-game: the main menu has **Army Builder (browser)** (opens this page at the
configured server URL) and **Refresh Cloud Armies** (re-fetches the dropdown
list without restarting).

### Code layout

| Path | What |
| --- | --- |
| `public/js/builder/` | the app: `store.js` (roster state over the package engine), `main.js` (views), `dialogs.js`, `importers.js`, `api.js`, `ui.js` |
| `public/js/lib/gameformat.mjs` | **shared** Roster ⇄ schema-2 game JSON converter — also used by `scripts/40kdc/generate-armies.mjs`; change it there for both |
| `public/js/lib/dckit.mjs` | shared pure dataset helpers (faction-scoped resolver etc.) |
| `public/js/lib/canon.mjs` | generated: game-name canonicalization table from the .gd dispatch tables |
| `public/js/vendor/40kdc-data.mjs` | generated: the package + RAW_DATA bundled for the browser (7.6MB, ~0.8MB gzipped — the server gzips it) |
| `public/js/parser.js` | legacy loose-format text parser (fallback import path) |

Regenerate the two generated files after bumping the dataset package or when
the game's ability-dispatch tables change:

```bash
cd scripts/40kdc && npm install && npm run bundle
```

### The army JSON contract

Exports are schema-2 army files (the format under `40k/armies/`):
`ArmyListManager` validates structured weapon abilities against
`AbilityRegistry`, dispatches faction/ability/enhancement behavior on exact
names, and parses transport capacity from ability text — the converter
(`gameformat.mjs`) emits all of those in the game's expected shapes, with
canonicalized names. Round-trip fidelity is pinned by tests.

## Running locally

```bash
cd server && npm install
node relay-server.js            # http://localhost:9080
```

The desktop game defaults to `http://localhost:9080` (override with a
`40k/server_config.json` containing `{"api_url": "..."}`), so a local server
gives you the full loop: build in the browser → save to cloud → the game's
menu lists it.

Note: the in-game MCP bridge also defaults to port 9080 — when running both,
start the game with `GODOT_MCP_PORT=9082`.

## Tests

```bash
cd server
npm test          # converter round-trip/golden tests + legacy parser tests
npm run test:e2e  # boots the server on a temp DB and drives the real page
                  # headless (Playwright; uses /opt/pw-browsers/chromium)
```

## Licensing

The dataset is CC BY 4.0 (Alpaca Software and the 40kdc community
contributors). Public deployments must keep the visible **"Powered by
40kdc-data"** credit + link (page footer here; main-menu credit in the game).
