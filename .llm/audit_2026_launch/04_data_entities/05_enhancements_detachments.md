# 04.05 — Enhancements + Detachment Abilities

**Read first:** `00_overview.md`, `01_inventory.md`, `04_data_entities/README.md`, `universe/enhancements.json`, `universe/detachment_abilities.json`.
**Output:** `.llm/audit_2026_launch/findings/04_05_enhancements_detachments.md`

## Scope

Two related entity types — auditing them together because they're consumed as a bundle when a player selects a detachment.

### Enhancements (925 in `Enhancements.csv`)

Each row: `faction_id, id, name, cost, detachment, detachment_id, description`. P0 = enhancements legal under any active roster's selected detachment. P1 = same faction, different detachment. P2 = different faction.

For each P0:
- Find the engine effect (often a named hook in `RulesEngine.gd` or in a faction-specific manager)
- Verify the bearer restriction (CHARACTER, sometimes a specific keyword like PSYKER)
- Verify the cost matches `Enhancements.csv` `cost` column
- Confirm it shows in the army builder UI

For each P0: **also verify the rule it confers is itself implemented.** An enhancement that says "Your bearer has Lethal Hits with all melee weapons" needs the underlying Lethal Hits handler to exist and to be applied to the right weapons — cross-reference with `04_02_weapon_rules.md`.

### Detachment abilities (283 in `Detachment_abilities.csv`)

Each row: `id, faction_id, name, legend, description, detachment, detachment_id`. The army-rule that fires when a detachment is selected. P0 = detachment is selected by an active roster.

For each P0:
- Find the implementation (often in a faction-specific ability manager or stratagem manager)
- Verify the trigger and effect
- Confirm UI affordance (e.g., Custodes Martial Mastery per-round selection panel)

### Detachments themselves (261 in `Detachments.csv`)

For each detachment: count its (a) detachment ability, (b) enhancements (typically 4-6), (c) stratagems (typically 6-8). A detachment is **launchable** when ≥80% of (a)+(b)+(c) reach depth `U`. Output a table: `detachment, faction, ability ✅, enhancements N/M ✅, stratagems N/M ✅, launchable Y/N`.

## Live-validation

For each detachment in active rosters (≤6 detachments to test):
- Trigger the detachment ability and capture the effect (e.g., Custodes Martial Mastery selection at start of round)
- Take an enhancement on a CHARACTER and confirm both the cost validation and the rule effect
- Use 2-3 detachment-locked stratagems

## Prior-audit overlap

- 2026-05 verified Custodes Shield Host detachment (Martial Mastery + Martial Ka'tah) + Custodian Guard's Sentinel Storm + Ork War Horde "Get Stuck In"
- Enhancement validator (1-per-CHARACTER, 1-of-each-per-army, bearer must be CHARACTER) — `ArmyListManager.gd:1275-1304`

## Output prose

Top 5 enhancements at `❌`. The launchable-detachment count (out of 261). Per-faction roll-up: how many of the faction's detachments are launchable.
