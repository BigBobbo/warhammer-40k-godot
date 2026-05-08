# 04.06 — Factions, Rosters, and Datasheet Coverage

**Read first:** `00_overview.md`, `01_inventory.md`, `04_data_entities/README.md`, `universe/roster_priority.json`.
**Output:** `.llm/audit_2026_launch/findings/04_06_factions.md`

## Scope

Audits the **breadth** dimension: which factions, detachments, and datasheets are actually playable.

### Per-faction roll-up (26 factions in `Factions.csv`)

For each faction, produce one row:
- Faction name
- Datasheets in catalog (`Datasheets.csv` filter)
- Datasheets present in any roster JSON (`armies/*.json`)
- Detachments in catalog (`Detachments.csv` filter)
- Detachments selectable in active rosters (count distinct from `armies/*.json` `faction.detachment`)
- Faction army rule (the row from `Abilities.csv` with matching faction_id, type=Faction) — implemented Y/N
- Number of named abilities used by this faction's roster units that have engine handlers

Currently 3 factions have rosters: Adeptus Custodes, Orks, Space Marines.

### Per-detachment depth (within each faction)

For each (faction × detachment) appearing in `armies/*.json`:
- Detachment ability implemented? (cross-reference `04_05`)
- Number of legal enhancements implemented (cross-reference `04_05`)
- Number of legal stratagems implemented (cross-reference `04_04`)
- Verdict: launchable Y/N (≥80% bar from `04_05`)

### Per-datasheet spot check (sampling)

Pick 20 datasheets from active rosters spanning all three playable factions:
- Statline matches `Datasheets_models.csv` (M, T, Sv, W, Ld, OC, base)
- Weapon profiles match `Datasheets_wargear.csv` (range, A, BS/WS, S, AP, D, special_rules)
- Abilities listed match `Datasheets_abilities.csv` (named + inline)
- Keywords match `Datasheets_keywords.csv`
- Points cost matches `Datasheets_models_cost.csv` for the chosen model count

Any divergence is a `🐛` because the canonical Wahapedia data and the curated roster JSON have drifted.

### Faction roster delta

For the 3 playable factions, produce `roster_completeness` per faction:
- Datasheets in catalog / Datasheets in any roster — close to 100% means a complete faction
- Datasheets in roster but missing from catalog — likely typo or stale data

For the 23 non-playable factions, list what would need to exist for them to become playable: at minimum, one roster JSON per faction × detachment. Estimate the work.

## Live-validation

- Build a roster from each playable faction in the army-builder UI; confirm it deploys and plays through one full Battle Round
- Attempt to build a roster for Aeldari (no roster JSON present) → expected: cannot proceed past faction selection. Flag the failure mode UX.

## Output prose

The headline number: **launchable factions out of 26**. Currently expected: 3. Confirm or correct.
The headline number: **launchable detachments out of 261**.
The launchability map: per-faction table sorted by completeness percent.
The 9e carryover sweep: any datasheet rule cited in roster JSON but verified-removed-in-10e per Wahapedia.
