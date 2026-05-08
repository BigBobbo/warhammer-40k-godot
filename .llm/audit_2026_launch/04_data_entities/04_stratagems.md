# 04.04 — Stratagems

**Read first:** `00_overview.md`, `01_inventory.md`, `04_data_entities/README.md`, `universe/stratagems.json`. **Also read** `~/.claude/projects/-Users-robertocallaghan-Documents-claude-godotv2/memory/project_stratagem_sweep_2026_05.md` and the appended sections of `40k/test_results/audit_2026_05/AUDIT_REPORT.md` — most P0 stratagems were already covered there.
**Output:** `.llm/audit_2026_launch/findings/04_04_stratagems.md`

## Scope

1,478 stratagems. Iterate `universe/stratagems.json` (sorted by `datasheet_count` descending). For each row classify per evidence model.

Stratagem records include `phase`, `cp_cost`, `turn` (Your turn / Either player's turn / Your opponent's turn), `detachment`, `description`. Group findings by **detachment-in-use**:

- **Tier P0:** stratagem is in `Stratagems.csv` AND `(faction_id, detachment_id)` matches any active roster's faction + selected detachment.
- **Tier P1:** stratagem belongs to a faction in active rosters but a different detachment.
- **Tier P2:** catalog-only.

For each P0 stratagem:
1. Find handler in `40k/autoloads/StratagemManager.gd` (or `FactionStratagemLoader.gd` if data-only).
2. Verify the timing window (`when`), target restrictions, and effect match the Wahapedia text.
3. Confirm the stratagem appears in the in-game stratagem panel (`40k/scripts/StratagemPanel.gd`) when its trigger window is open.
4. Confirm reactive vs. proactive timing is honoured.

For each P1: code path may exist but the stratagem isn't reachable until the faction switches detachments. Flag as "data ready, detachment-gated."

For each P2: list as table, mark `data-only` without deep audit.

## Cross-cuts

- **Core stratagems** (faction_id is empty) — Command Re-roll, Counter-Offensive, Heroic Intervention, Tank Shock, Smokescreen, Fire Overwatch, Grenade, Insane Bravery, Go to Ground, Strategic Reserves, Rapid Ingress, Epic Challenge — these are the most-used. Audit each one's Wahapedia text vs. handler text in detail.
- **Boarding Actions stratagems** — present in `Source.csv` (v1.1, July 2025). Are these gated to Boarding Actions mode? If always available, that's a 🐛.

## Live-validation

Drive ≥ 15 P0 stratagems live via MCP, spanning all phases and both proactive and reactive timing:
- Command phase: Insane Bravery, faction CP-gen
- Movement: Rapid Ingress (end of opponent's), Grenade (sometimes Movement?), Smokescreen
- Shooting: Go to Ground (after target select), Fire Overwatch (rare in Shooting), Suppression Fire
- Charge: Heroic Intervention (opponent's Charge phase), Fire Overwatch (on charge declaration), Tank Shock
- Fight: Counter-Offensive (after fighter), Epic Challenge (on melee selection)
- Any phase: Command Re-roll
- Detachment-specific from active roster (Custodes, Orks, SM)

Each live validation must capture: timing window honoured, CP deducted, effect applied, UI surface shown.

## Prior-audit overlap

The 2026-05 stratagem sweep covered most P0. Read the appendix in `AUDIT_REPORT.md` and copy verified findings; only deep-audit items not covered.

`STRATAGEMS_AND_ABILITIES_PLAN.md` at repo root is the existing implementation plan — reference its IDs.

## Output prose

Top 10 stratagems at `❌` or `🐛`. Top 10 detachments where ≥80% of stratagems are missing — these detachments are unplayable. Per-phase scorecard: how many stratagems per phase reach depth `U`.
