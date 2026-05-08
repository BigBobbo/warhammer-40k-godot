# Stage 3 — Core Mechanics Audit

Each prompt in this folder audits one phase or cross-cutting system against Wahapedia 10e. They run in parallel.

## Shared instructions for every Stage 3 agent

1. **Read first:** `.llm/audit_2026_launch/00_overview.md` (evidence model, prior-audit overlap), `.llm/audit_2026_launch/01_inventory.md` (data freshness, code consumers).
2. **Source rules:** fetch the relevant Wahapedia page section. **Do NOT work from a curated list inside this file** — enumerate from the source page so any rule the audit author missed is still covered. Any per-section rule list inside this file is illustrative, not exhaustive.
3. **Codebase scope:** `40k/` only. Exclude `40k/.claude/worktrees/`.
4. **Output:** one Markdown file per the path declared in the prompt. Use the schema:
   ```
   | Rule | Wahapedia § | Depth (C/W/U/L) | Correctness (✅⚠️❌🐛❓) | Evidence | Notes |
   ```
   Followed by a short prose section: **Top 3 launch-blocker gaps** and **Top 3 invisible features**.
5. **Live validation:** spot-check ≥ 2 rules per phase by driving them through `mcp__godot-mcp-bridge__*` with the Godot editor running. Capture: action dispatched → state delta → screenshot of the in-game effect. If MCP isn't reachable: write `LIVE-VALIDATION SKIPPED: <reason>` per rule. Do not silently downgrade depth.
6. **Don't re-file** items in `40k/test_results/audit_2026_05/AUDIT_REPORT.md`, `MASTER_AUDIT.md`, `.llm/rules-audit.md`, or repo-root `AUDIT_*.md` — cite their issue/PR IDs when overlap exists. Regression-spot-check those items but report them as `✅ VERIFIED (regression spot-check)` rather than refiling.
7. **No "removed in 10e" claim** without a Wahapedia URL citing the current 10e rule.

## Files in this folder

| File | Phase / system | Wahapedia section |
|---|---|---|
| `01_pregame_setup.md` | Pre-game, Battle Formations, deployment | Pre-game / Setup |
| `02_core_concepts.md` | Datasheet, models, units, LoS, ER, modifiers, mortal wounds | Core Concepts |
| `03_command.md` | Command phase | Command Phase |
| `04_movement.md` | Movement phase | Movement Phase |
| `05_shooting.md` | Shooting phase + weapon abilities (sequence only; per-token audit is in 04_data_entities/weapon_rules.md) | Shooting Phase |
| `06_charge.md` | Charge phase | Charge Phase |
| `07_fight.md` | Fight phase | Fight Phase |
| `08_end_of_turn.md` | End of turn, Battle-shock recovery, scoring boundaries | (combined) |
| `09_terrain.md` | Terrain, cover, Ruins, visibility | Terrain rules |
| `10_objectives_scoring.md` | OC contests, primary/secondary scoring, sticky objectives | Mission rules |
| `11_leader_attachment.md` | Character attachment, LOS!, Precision interaction | Leader / Attached units |
| `12_battle_shock_cascade.md` | Where battle-shock effects propagate (cross-phase) | Battle-shock |
| `13_save_load_state.md` | Pure-state round-trip (headless OK) | Internal |

Each file states its specific scope, output path, and live-validation focus.
