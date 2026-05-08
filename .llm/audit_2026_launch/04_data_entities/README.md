# Stage 4 — Data-Entity Audit

Each prompt audits one data type. Together they classify every row of the Wahapedia corpus against the codebase using the shared evidence model.

## Shared instructions

1. **Read first:** `00_overview.md`, `01_inventory.md`, and the relevant `universe/*.json` from Stage 2.
2. **Don't enumerate by hand.** The audit's universe is the `universe/*.json` files. Iterate them; classify every row.
3. **Priority tiers** (bake into the output):
   - **P0** — entity used by a unit in any active `40k/armies/*.json` roster.
   - **P1** — entity belonging to a faction with at least one active roster, even if not currently fielded (cross-faction stratagems, unused enhancements).
   - **P2** — catalog-only (no active roster for that faction).
4. **Live-validate** the top-N most-referenced P0 entities per audit (N specified per file).
5. **Output schema:**
   ```
   | Entity ID | Name | Faction / Detachment | Priority | Depth | Correctness | Evidence | Notes |
   ```
   Plus: counts (P0/P1/P2 × ✅/⚠️/❌/🐛), top-10 invisible features, top-10 divergences.
6. Don't re-audit items already in `project_stratagem_sweep_2026_05` — read the AUDIT_REPORT.md appendix first and copy verified findings.

## Files

| File | Entity | Universe |
|---|---|---|
| `01_abilities.md` | 70 named + 3,593 inline | `universe/abilities.json` + scan of `armies/*.json meta.abilities[]` |
| `02_weapon_rules.md` | 37 distinct tokens | `universe/weapon_rules.json` |
| `03_keywords.md` | 1,420 distinct | `universe/keywords.json` |
| `04_stratagems.md` | 1,478 stratagems | `universe/stratagems.json` |
| `05_enhancements_detachments.md` | 925 + 283 + 261 | `universe/enhancements.json`, `universe/detachment_abilities.json` |
| `06_factions_rosters.md` | 26 factions × N detachments | data dir + `armies/*.json` |
