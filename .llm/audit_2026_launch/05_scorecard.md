# Stage 5 — Per-Faction Launchability Scorecard

**Read first:** every file in `.llm/audit_2026_launch/findings/`. This stage runs after Stages 3+4 land.
**Output:** `.llm/audit_2026_launch/findings/05_scorecard.md`

## Goal

A single steering document that answers: **"Which factions can ship at launch, and what blocks the rest?"**

## Method

Aggregate the findings from Stages 3 and 4. Do not re-discover; only synthesize.

## Required tables

### Table 1 — Per-faction launchability

| Faction | Has Roster | Datasheets in roster | Detachments selectable | Detachments launchable | Faction ability | Stratagems P0 ✅ / total | Enhancements P0 ✅ / total | Notable gaps | Launch verdict |
|---|---|---:|---:|---:|---|---|---|---|---|

26 rows. "Launch verdict" is one of: **READY** (≥1 launchable detachment + faction rule + ≥80% P0 stratagems), **NEEDS WORK** (faction has roster but key gaps), **NOT STARTED** (no roster JSON exists).

### Table 2 — Per-phase scorecard

| Phase | Rules audited | ✅ % | ⚠️ % | ❌ % | 🐛 % | Top gap | Top invisible feature |
|---|---:|---:|---:|---:|---:|---|---|

13 rows (one per Stage 3 file).

### Table 3 — Cross-cutting data scorecard

| Entity | Total | P0 ✅ at U or L | P0 ⚠️/❌ | P1 catalog-only | P2 deferred |
|---|---:|---:|---:|---:|---:|

Rows: Abilities (named), Abilities (inline), Weapon rules, Keywords (rules-bearing), Stratagems, Enhancements, Detachment abilities.

### Table 4 — Invisible-feature shortlist

The 25 most impactful features at depth `C` or `W` but not `U` (engine works, player can't reach it). Sort by frequency-of-use estimated from roster + active-faction overlap.

### Table 5 — Divergence shortlist

The 25 most impactful `🐛` items (engine fires but rule diverges). These are the most dangerous — tests pass, players can't tell.

## Headline numbers

State up-front:
- **Factions launch-ready:** N / 26
- **Detachments launchable:** N / 261
- **Stratagems implemented and reachable:** N / 1,478
- **Enhancements implemented and reachable:** N / 925
- **Named abilities implemented and reachable:** N / 70
- **Inline abilities (roster-fielded) implemented:** N / ~110

## Output prose

A 5-bullet "what would it take to ship 4 factions instead of 3" — the highest-ROI work. A 5-bullet "what would it take to ship every faction" — the 26-faction goal. A short paragraph on confidence: how much of the audit was live-validated vs. depth-`C/W`-only.
