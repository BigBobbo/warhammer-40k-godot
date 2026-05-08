# 04.01 — Abilities

**Read first:** `00_overview.md`, `01_inventory.md`, `04_data_entities/README.md`, `universe/abilities.json`.
**Output:** `.llm/audit_2026_launch/findings/04_01_abilities.md`

## Scope

Two universes to audit:

### A. Named/core abilities catalog (70 deduped rows in `universe/abilities.json`)

These are the keyword abilities (Deep Strike, Feel No Pain, Leader, Lone Operative, Scouts, Stealth, Fights First, Deadly Demise, Infiltrators, Firing Deck, Oath of Moment, Dark Pacts, Waaagh!, Martial Ka'tah, Acts of Faith, Synapse, Battle Focus, etc.). Top 10 by reference count: Deadly Demise (729), Leader (415), Deep Strike (354), Oath of Moment (275), Dark Pacts (163), Feel No Pain (116), Scouts (110), Battle Focus (99), Waaagh! (87), Stealth (79).

For each, find:
- The implementation in `40k/autoloads/RulesEngine.gd`, autoloads, phase controllers
- The call site (where it's invoked)
- Any UI affordance (button, panel, tooltip, indicator)
- Wahapedia rule text vs. implementation behaviour

Classify `C/W/U/L` × ✅⚠️❌🐛❓ per row.

### B. Inline (datasheet-specific) abilities — 3,593 rows in `40k/data/Datasheets_abilities.csv` where `ability_id` is empty

These are the unit-specific abilities written into individual datasheets (Vox-link, Banner of the Emperor Triumphant, Bomb Squigs, Praesidium Shield, Vexilla, Gun-Crazy Show-offs, etc.). The Wahapedia data contains the prose; the game implements them per-unit.

Iterate by **rosters first** to keep this tractable: every unique ability name in `armies/*.json` `meta.abilities[]` (where `type != "Core"` and not in the named catalog). Cross-reference with `Datasheets_abilities.csv` filtered to those datasheets to get the canonical text.

For each: find the engine handler (often a name-keyed dispatch in `RulesEngine.gd` or `FactionAbilityManager.gd`); classify.

Catalog-only inline abilities (rows in the CSV not referenced by any roster) are P2 — list as a table count, do not deep-audit individually.

## Live-validation

Drive the top 10 P0 named abilities live via MCP: trigger them in a real game and capture the effect.
- Deep Strike → arrival via Reinforcements, >9" rule
- Leader → attach + LOS!
- Feel No Pain → roll-after-damage, before wound loss
- Oath of Moment → target selection, +1 to wound vs designated unit
- Dark Pacts → Lethal Hits / Sustained Hits 1 trade for mortal wound on 1
- Scouts → pre-game move
- Stealth → -1 to hit
- Waaagh! → once-per-battle, Round-2-onwards lock, +1 charge / +1 attack effects
- Martial Ka'tah → per-fight stance selection
- Battle Focus → faction-specific Aeldari movement

Plus top 5 P0 inline abilities by ref count from the rosters (e.g., Praesidium Shield, Vexilla, Bomb Squigs).

## Prior-audit overlap

- `ABILITIES_AUDIT.md` and `AUDIT_ABILITIES_2.md` (20 KB) at repo root — read first
- `ORK_ABILITIES_TASKS.md` and `MODEL_ATTRIBUTES_TASKS.md` for Ork-specific
- 2026-05 audit verified Custodes Martial Mastery + Ka'tah + Praesidium, Orks Waaagh + Plant Banner

## Output prose

Top 10 abilities with depth `C` or `W` but not `U` (the invisible-feature shortlist). Top 10 with `🐛` (engine present but rule diverges). Per-faction summary: how many of the faction's abilities reach `U`.
