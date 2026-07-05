# 40kdc 11th-Edition Data Migration

This branch replaces the game's 10th-edition data with the official
11th-edition launch dataset from the
[`@alpaca-software/40kdc-data`](https://www.npmjs.com/package/@alpaca-software/40kdc-data)
npm package (v1.0.19, "launch" dataslate effective 2026-06-20; upstream
repo: <https://github.com/wn-mitch/40kdc-data>).

## Pipeline

```
scripts/40kdc/
  package.json                    # pins @alpaca-software/40kdc-data 1.0.19
  extract.mjs                     # raw dataset -> 40k/data/40kdc/*.json (27 collections)
  lib.mjs                         # faction-scoped resolver for shared ids + helpers
  generate-armies.mjs             # -> 40k/armies/*.json  (schema-2 rosters, 11e values)
  generate-leader-pairings.mjs    # -> 40k/data/Datasheets.csv + Datasheets_leader.csv
  generate-deployment-zones.mjs   # -> 40k/deployment_zones/*.json (official geometry)
  generate-stratagems.mjs         # -> 40k/data/Stratagems.csv + Factions.csv + Detachments.csv
  generate-terrain-layouts.mjs    # -> 40k/terrain_layouts/*.json + index_11e.json (45 official layouts)
  verify-terrain-layouts.mjs      # geometry gate: emitted polygons == resolveLayout() transposed (4-dp)
```

Refresh flow: `cd scripts/40kdc && npm install && node extract.mjs && node
generate-armies.mjs && node generate-leader-pairings.mjs && node
generate-deployment-zones.mjs && node generate-stratagems.mjs && node
generate-terrain-layouts.mjs` (the terrain generator runs
`verify-terrain-layouts.mjs` automatically and fails on any geometry drift;
it can also be run standalone).

The extractor reads the package's raw embedded bundle rather than its public
API: the API dedups shared record ids first-wins with no faction scoping,
which would hand (e.g.) an Ork `close-combat-weapon` another faction's
statline. `lib.mjs` resolves shared ids to the copy authored in the unit's own
faction block (nearest-anchor assignment; 0 unresolved references across all
995 units).

## What was replaced (10e -> 11e)

| Area | Before | After |
|---|---|---|
| Army rosters (`40k/armies/*.json`) | 10e stats/points/weapons, Wahapedia-derived | Regenerated from 11e dataset; roster lineups preserved |
| Primary missions (11e tables) | Hand-reconstructed from review text, ~19/25 cards `approximate` | Official launch awards (25 cards, Force Disposition matrix) |
| Secondary deck (11e) | 7 of 18 cards approximate, several scorings wrong | Official launch awards (18 cards incl. fixed/tactical splits) |
| Stratagems/Factions/Detachments CSVs | 10e Wahapedia export (untracked local files) | Generated from 11e dataset, committed |
| Leader pairings | Missing CSVs (loader warned at boot) | 920 pairings from 11e leaderAttachments |
| Deployment zones | Hand-rolled, some geometry wrong (H&A 12" vs official 18") | Official geometry, + 11e-new Tipping Point pattern |
| Engine fallback data (RulesEngine WEAPON_PROFILES / placeholder armies) | 10e statlines | 11e statlines |

Removed 10e-only roster content: units with no 11e datasheet (Kaptin
Badrukk, Big Gunz), placeholder "Strike Force" import artifacts, retired
enhancements (Tellyporta, Adamantine Talisman).

**The game is 11th edition only.** `GameConstants.edition` defaults to 11,
every player launch re-asserts 11 at boot (a stale `settings.cfg` from older
builds can no longer pin a player to 10e), and the main-menu "Rules Edition"
selector was removed. The 10e code paths and data tables survive *only* for
the legacy regression suite — the automated harness pins its historical 10e
baseline explicitly — until they are deleted outright.

## Licensing

Dataset enrichment data is CC BY 4.0 (Alpaca Software and the 40kdc community
contributors). See `40k/data/40kdc/ATTRIBUTION.md`. Public deployments must
show "Powered by 40kdc-data" with a link to <https://40kdc.alpacasoft.dev> —
the main menu carries this credit.

## Known gaps for full 11th-edition play

Data-level (dataset limitations):

1. **Stratagem and enhancement rules text/effects.** The dataset deliberately
   stores no GW prose; only 263/2135 stratagems and 175/1576 enhancements have
   machine-readable (Ability-DSL) effects. Generated stratagem rows carry
   correct names/CP/phase/timing/detachment, but most effect text is a stub
   and most stratagems are display-only in the engine (the 11e core set of 10
   stratagems is fully hardcoded in `StratagemManager` and unaffected).
2. **No damaged/degrading profiles.** 11e datasheets with damage brackets are
   not modelled in the dataset; regenerated rosters carry none.
3. **Per-unit BS/WS variants of shared weapons.** The dataset authors one
   copy of e.g. `plasma-pistol` per faction, so units whose BS differs from
   their faction's authored copy inherit the shared statline.
4. **Wargear ability effects** (e.g. shield/vexilla stat bonuses) are name-keyed
   in `ArmyListManager.WARGEAR_STAT_BONUSES`; the dataset's `wargear.json` is
   still stamped 10th-edition upstream.
5. **Transport keyword restrictions** are unused in the dataset
   (`keyword_restrictions` never populated); generated TRANSPORT abilities
   default to `<FACTION> INFANTRY` with the dataset's exclusions (Jump Pack).
6. **~72 units still carry provisional points** upstream (Black Templars /
   Blood Angels wave, `points_provisional: true`), and `sir-hekhtur`
   (Imperial Knights) has no points at all.
7. **Base sizes:** 156 upstream base entries are drafts (hull/flying-base
   without mm); the roster generator falls back to 32 mm round for those.

Engine-level (this codebase, pre-existing):

8. **Datasheet ability behaviors are hardcoded by exact name**
   (`UnitAbilityManager.ABILITY_EFFECTS`, ~122 entries authored against 10e
   wording/values). Regenerated rosters keep the same ability names where the
   engine implements them, but numeric changes inside those effects between
   editions are not automatically picked up. The dataset's Ability DSL (100%
   coverage, machine-readable) is the natural long-term replacement.
9. **AI has no logic for the seven new 11e secondary cards** (Beacon,
   Outflank, Plunder, Forward Position, Burden of Trust, Centre Ground,
   A Grievous Blow) — it can draw and score them, but won't pursue them.
10. **Objective sourcing & count: RESOLVED for the official layouts (D3-a +
    D4).** Every converted 11e layout now authors its own `objectives[]` —
    five markers derived from the card's objective pieces: `obj_home_1/2` at
    the two home-area centroids (player 1 = top of the portrait board),
    `obj_nml_1/2` at the expansion-area centroids, and `obj_center` at the
    linked centre pair's midpoint, which is exactly the board centre (22,30)
    in all 45 layouts (asserted by `verify-terrain-layouts.mjs`).
    `MissionManager._setup_objectives_for_deployment` prefers the loaded
    layout's markers; legacy layouts keep the `40k/deployment_zones/*.json`
    source. D4 finding: the dataset's 6 objective *pieces* per layout are 5
    *markers* (the centre pair straddles one objective), so no 6-objective
    board support is needed for official play — the Inescapable Dominion
    6-objective caveat remains only for hypothetical custom maps.
11. **11e "territory" rules approximated by deployment zones** in a few
    checks (e.g. Search and Scour's end-of-battle condition). The official
    territory polygons are now carried in `40k/deployment_zones/*.json` for a
    future fix. (Unchanged by the terrain-layout conversion.)
12. **Official 11e terrain layouts: CONVERTED.** All 45 GW layout cards
    (15 matchup pairings x 3 variants) are generated into
    `40k/terrain_layouts/<matchup>_<variant>.json` (+ `index_11e.json`
    registry) by `scripts/40kdc/generate-terrain-layouts.mjs`, using the
    package's pinned `resolveLayout()` for geometry, transposed to the game's
    44x60 portrait board with rotation baked into explicit `polygon` vertices
    (spec Decision D1). `TerrainManager` loads polygon pieces natively
    (legacy `size`-rectangle layouts `layout_1..8` still work) and registers
    the 45 ids from the index. Acceptance is **faithful-to-dataset**:
    `scripts/40kdc/verify-terrain-layouts.mjs` asserts every emitted vertex
    equals the transposed resolver output (4-dp) for all 1,966 pieces, and
    the windowed scenario `tests/scenarios/sp/terrain_11e_layouts.json`
    drives a converted layout in the live game (LoS block through an
    obscuring area + the 14.01 terrain-objective control flip). The
    matchup→layout selection UI (spec D5) is wired: changing a
    Force-Disposition dropdown in the main menu offers the pairing's 3
    official layouts (auto-selecting variant 1) and snaps the deployment
    dropdown to the layout card's pattern — incl. the 11e-new
    `tipping_point` option — while the legacy layouts stay available as a
    manual override (windowed scenario
    `tests/scenarios/sp/terrain_11e_menu_matchup.json`). Layout-sourced
    objectives are wired too (D3-a — see gap #10). Remaining follow-up:
    the dataset's `hidden` / `plunging-fire` area keywords (spec §9.5 — no
    engine rules yet; the current 16 templates carry no such overrides).
    Walls/windows are intentionally not emitted (spec D2-a): obscuring
    polygons carry LoS blocking, so converted ruins have no
    see-through-window nuance.
13. **Points validation** treats over-limit armies as warnings, and 11e
    per-army-copy price tiers (2nd+ copies of a datasheet costing more) are
    not enforced by the builder — rosters price every unit at first-copy cost.
