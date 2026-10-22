# Codex: Space Marines (11e) — Space Wolves — plan

Status: ACTIVE (2026-10-22). Owner ask: "build the 11e Space Marines codex
module, just focus on Space Wolves: abilities, stratagems, wargear options and
detachments; fully ensure each can be used within the game itself."

Same process as the Custodes / Orks codex work (`PLAN.md`, contract
`IMPLEMENTATION.md` — read both; this file only lists what differs).

## Rules source

- `space-marines/SPACE_WOLVES.md` — every rule in scope, printed text: army
  rules, the three Space Wolves detachments (rule, enhancements, stratagems,
  incl. the page-only Master of Wolves text) and the abilities, wargear options
  and Leader lists of the 21 Space Wolves datasheets.
- `space-marines/RULES.md` / `space-marines/wahapedia/*.csv` — the full export.
- Stratagem rows: `scripts/40kdc/curated/space_wolves_codex_11e.json`
  (`when`, `target`, `effect`, `windows`).
- Core rules: https://wahapedia.ru/wh40k11ed/the-rules/core-rules/

Notable codex facts:
- **Oath of Moment is gone** from Codex: Space Marines. The army rule every
  datasheet carries is **Combat Doctrines** (now army-wide, not Gladius-only).
  WP-S1 already gives every unit of a Space Wolves army "Combat Doctrines" and
  no "Oath of Moment" (data), so FactionAbilityManager never offers the Oath to
  a Space Wolves army.
- Gladius Task Force's rule is now "Codex Discipline" (one doctrine one extra
  time). Gladius itself is a generic detachment and out of scope EXCEPT the
  interaction with Space Wolves doctrines (see WP-S2).

## Scope decisions

| # | Decision |
|---|---|
| SW-D1 | Only Space Wolves armies get the codex rules (gate: `SWCommon.is_sw_army(player)` — 11e and faction "Space Wolves" or any SPACE WOLVES unit). Other Space Marine armies keep today's index rules (Oath of Moment, 10e Gladius) until their chapter is imported. |
| SW-D2 | Generic Space Marine datasheets (Intercessors, Captains, ...) keep their 40kdc 1.4.5 records; only the 21 Space Wolves datasheets were re-imported (WP-S1). Their datasheet abilities are out of scope. |
| SW-D3 | Generic codex detachments (Gladius, Assault Brethren, ...) are out of scope, except Gladius' Codex Discipline (it modifies the doctrines). |
| SW-D4 | Legends / Boarding Actions: ignore (as D2/D3 of PLAN.md). |

## Shipped: WP-S1 data (commit b23aeb7)

- `wahapedia-import.mjs --faction adeptus-astartes` (scoped: sources = Space
  Wolves, detachments = the 3 SW ones, filed under the `space-wolves` faction).
- 12 stratagem rows `SW|…` marked `custom:sw11e` (curated file above).
- `armies/sw11e_codex_test.json`: all 21 SW datasheets (+ a second copy of
  each with a wargear option taken) + Intercessor Squad + Captain; faction
  "Space Wolves", detachments Saga of the Great Wolf + Champions of Fenris.
- `tests/test_sw11e_codex_data.gd` (28/0) — data through the real loaders.
- Engine: per-model resolution of several options on one model, and single-
  model option swaps that replace across weapon types.

## Rules work packages (parallel)

| WP | Scope | Owns | Thin hooks allowed in |
|---|---|---|---|
| **S2** army rules + detachments + enhancements | Combat Doctrines (army rule: selection, once-per-battle, the three effects, per-unit override / extra), Gladius Codex Discipline for SW armies, Transhuman Strategist, Curse of the Wulfen (OC aura + Bestial Forms transport), Sons of Russ (army validation); detachment rules The Great Wolf Watches, Legendary Slayers, Master of Wolves (incl. Howling Onslaught + the chapter restriction); the 8 enhancements | `scripts/codex/space_wolves/SWArmyRules11e.gd`, `SWDetachments11e.gd`, `SWEnhancements11e.gd`; the doctrine selection UI | FactionAbilityManager (skip the 10e Gladius doctrine path for SW armies), CommandPhase, Movement/Charge/Shooting phases (doctrine effects), RulesEngine, ArmyListManager (validation, enhancement ownership), AIDecisionMaker |
| **S3** stratagems | The 12 SW stratagems in their windows; `custom:sw11e` dispatch | `scripts/codex/space_wolves/SWCodex11e.gd` + group scripts, `curated/space_wolves_codex_11e.json` windows (+ `CONFIRMED_WINDOWS` in curate-from-wahapedia.mjs, re-run `npm run codex11e`) | StratagemManager (dispatch `custom:sw11e` like `custom:custodes11e`), BasePhase / phases (any new window), AIDecisionMaker |
| **S4** datasheet abilities + Librarius | Every datasheet / wargear ability of the 21 SW datasheets (~45, list in SPACE_WOLVES.md) incl. Njal's three psychic abilities and the Librarius psyker-level budget | `scripts/codex/space_wolves/SWAbilities11e.gd` (+ `SWPsychic11e.gd` if useful) | UnitAbilityManager (`ABILITY_EFFECTS` rows), RulesEngine, phases, dialogs for activated abilities, AIDecisionMaker |

Shared: `scripts/codex/space_wolves/SWCommon.gd` (generic helpers copied from
CustodesCommon + `is_sw_army`, `has_combat_doctrines`, and the **doctrine state
API** `active_doctrines(unit)` / `doctrine_active(unit, name)`; the state keys
are documented there). Every package reads doctrines ONLY through it. S2 owns
writing the army-wide doctrine; S3 (Grimnar's Command) and S4 (Guile of the
Wolf) write the per-unit keys documented in SWCommon. Add helpers to SWCommon
only by APPENDING (keeps merges clean).

Flags: `sw11e_<slug>`. Windowed ports (GODOT_MCP_PORT): S2 9880, S3 9980,
S4 10080. Every windowed launch: `flock /tmp/codex11e_godot_window.lock …`.
Scenarios: `40k/tests/scenarios/sp/sw11e_*.json`. Changelog bullets:
`changelog/WP-S<n>.md`. Rulings: a `## WP-S<n>` section in `RULINGS.md`.
Do NOT edit `40k/data/version_history.json` (the integrator does).

## Integration (S5)

Merge S2, S3, S4; run the full gate (`bash 40k/tests/run_pretrigger_tests.sh`),
re-run every `sw11e_*` scenario, a full AI-vs-AI game with the Space Wolves test
army, live screenshots; one `version_history.json` entry; push.
