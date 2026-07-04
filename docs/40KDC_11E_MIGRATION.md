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
```

Refresh flow: `cd scripts/40kdc && npm install && node extract.mjs && node
generate-armies.mjs && node generate-leader-pairings.mjs && node
generate-deployment-zones.mjs && node generate-stratagems.mjs`.

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
enhancements (Tellyporta, Adamantine Talisman). The engine's 10e *mode*
(edition-gated mission/secondary/stratagem code paths behind
`GameConstants.edition < 11`) is retained so old saves, scenarios, and the
10e regression suite keep working; it no longer leaks into 11e play.

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
10. **Five-objective maps.** All layouts place 5 objectives; some 11e cards
    assume 6-objective maps (Inescapable Dominion) — scoring stays capped
    accordingly.
11. **11e "territory" rules approximated by deployment zones** in a few
    checks (e.g. Search and Scour's end-of-battle condition). The official
    territory polygons are now carried in `40k/deployment_zones/*.json` for a
    future fix.
12. **Official 11e terrain layouts not yet converted.** The dataset ships all
    45 GW layout cards (15 matchup pairings x 3 variants, template-based,
    keyed to the Force Disposition matrix) in `40k/data/40kdc/terrainLayouts.json`;
    the game still uses its own 8 hand-made layouts. Conversion is scoped as
    follow-up work (footprint -> piece/wall translation + 90° board rotation).
13. **Points validation** treats over-limit armies as warnings, and 11e
    per-army-copy price tiers (2nd+ copies of a datasheet costing more) are
    not enforced by the builder — rosters price every unit at first-copy cost.
