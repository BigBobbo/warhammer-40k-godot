# WH40K Launch Audit (2026-05) — Overview

**Goal:** find the delta between the WH40K 10e Godot implementation and a launchable product. "Launchable" = a player can pick any faction in `Factions.csv`, build an army, and play through a complete game with the rules behaving per Wahapedia 10e core rules.

**Sources of truth:**
- Wahapedia rules pages: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/ + commentary + designers' commentary + faqs-and-errata
- Wahapedia data corpus: `40k/data/*.csv` (last refreshed 2026-05-05; see `01_inventory.md`)
- Active rosters: `40k/armies/*.json`
- Game code: `40k/` (autoloads, phases, scripts, scenes)

---

## Pipeline

| Stage | Purpose | Output | Status |
|---|---|---|---|
| 1 | Inventory & freshness | `01_inventory.md` | ✅ done |
| 2 | Extract universe of rules/data from CSVs + rosters | `universe/*.json`, `_summary.md` | ✅ done |
| 3 | Core mechanics audit (Wahapedia rules pages → code) | `03_core_rules/*.md` (one per phase/system) | prompts ready |
| 4 | Data-entity audit (CSV rows → code) | `04_data_entities/*.md` (one per entity type) | prompts ready |
| 5 | Per-faction launchability scorecard | `05_scorecard.md` | prompt ready |
| 6 | Synthesis — launch-blocker shortlist | `06_synthesis.md` | prompt ready |

Stages 3 and 4 fan out into multiple parallel agent invocations. Stages 5 and 6 each are a single agent invocation that depends on the prior stages landing.

---

## Shared evidence model

Every audit row classifies a rule along two axes.

**Implementation depth** (highest tier achieved):
- `C` — Code exists (function/data present)
- `W` — Wired: invoked from a phase controller / manager / autoload during normal play
- `U` — UI-reachable: a player can trigger it through a visible affordance (button, key, panel) without dev tools or console
- `L` — Live-validated: driven end-to-end via the `addons/godot_mcp` bridge with a screenshot showing the in-game effect

**Correctness vs. Wahapedia** (independent of depth):
- ✅ matches rule
- ⚠️ partial / edge case missing
- ❌ absent
- 🐛 present but diverges from rule (cite the divergence)
- ❓ ambiguous (rule text needs reread; flag for human)

A rule at `C` or `W` but not `U` is the **"invisible feature"** failure mode. Flag those explicitly.

**Evidence requirements:**
- For `C/W` claims: `file:line` of the implementation **and** of the call site.
- For `U` claims: scene path + node name of the affordance, or the input action name.
- For `L` claims: an MCP bridge transcript line (action dispatched → state delta → screenshot path) **OR** the explicit note `LIVE-VALIDATION SKIPPED: <reason>`. Never claim `L` without one.

**Hard rules:**
- No "removed in 10e" claim without a Wahapedia URL citing the current 10e rule. Single-source memory claims don't count.
- Pin tests (`_check("func defined", "func X" in src)`) and "game-running" screenshots are **not** evidence of `U` or `L`. They're regression nets at most.
- Don't re-file findings already tracked in `40k/test_results/audit_2026_05/AUDIT_REPORT.md`, `MASTER_AUDIT.md`, `.llm/rules-audit.md`, or any `AUDIT_*.md` / `*_TASKS.md` at the repo root — read those first and cite issue/PR IDs when overlap exists.

**Output schema** (one row per rule):
```
| Rule | Wahapedia § / Source | Depth | Correctness | Evidence | Notes |
```

Plus a short prose section per audit doc: top 3 launch-blocker gaps and top 3 invisible features.

---

## How to invoke a stage prompt

Each `*.md` under `03_core_rules/` and `04_data_entities/` is self-contained. To run one:

1. Spawn an agent (Explore for read-only deep dives; general-purpose if it needs to drive MCP).
2. Pass the prompt file path as the agent's brief: `read .llm/audit_2026_launch/03_core_rules/05_shooting.md and execute it`.
3. The agent writes its findings to the output path declared inside the prompt.

Stages 3 and 4 are independent — fan them out in parallel up to whatever your machine supports. Stages 5 and 6 must run sequentially after the fan-out finishes.

---

## Known overlap with prior audits

The 2026-05 audit (`40k/test_results/audit_2026_05/AUDIT_REPORT.md`) already verified to spec, on Adeptus Custodes vs Orks, the following items. The new audit should regression-spot-check these but **not refile**:

- Phase machinery (alternation, transitions, fights_first wiring, mandatory consolidation FAQ, end-of-round game-end)
- Heroic Intervention as 10e Core Strategic Ploy (1 CP, opponent's Charge phase) — `phases/ChargePhase.gd:2706-2985`, `autoloads/StratagemManager.gd:302-328`
- Look Out, Sir 10e behaviour — standalone-character protection lives entirely in Lone Operative; 9e wounds-threshold removed
- Enhancement validation (1-per-CHARACTER, 1-of-each-per-army, bearer must be CHARACTER) — `autoloads/ArmyListManager.gd:1275-1304`
- Lone Operative cannot be attached as Leader — `autoloads/CharacterAttachmentManager.gd`
- Cover save 3+ cap is INFANTRY/BEAST/SWARM only — `autoloads/RulesEngine.gd:3674-3704`
- Battle-shock OC=0 enforcement in objective scoring — `autoloads/MissionManager.gd:207-209`
- Battle-shocked units cannot use stratagems — `autoloads/StratagemManager.gd:603,613`
- Per-model fight eligibility validation — `phases/FightPhase.gd:_validate_assign_attacks`
- Benefit of Cover plumbing (ruins/obstacle/barricade behaviour, woods within-only, Indirect Fire override) — verified end-to-end
- Roll-off attacker/defender role storage — `phases/RollOffPhase.gd:184-194`
- Custodes Martial Mastery + Martial Ka'tah (per-fight) + Praesidium Shield
- Orks War Horde "Get Stuck In", Waaagh!, Plant Waaagh Banner (once-per-battle locks)
- Stratagem timing windows (Go to Ground after target select, Tank Shock on vehicle charge, Heroic Intervention end-of-charge, Fire Overwatch on charge declaration, Counter-Offensive after fighter, Epic Challenge on melee selection)
- Weapon keywords: Twin-linked, Sustained Hits 1, BLAST engagement-of-friendlies block, HAZARDOUS post-attack 1s check
- Movement: base move cap, Advance D6 + Command Re-roll, Strategic Reserves edge+9", engaged unit Fall Back / Remain Stationary restrictions, coherency on CONFIRM
- Save/load round-trips: `state.units`, `state.players`, `state.meta`, unit flags

---

## Scope decision

**Broad scope chosen:** the audit covers all 26 factions, all 1,478 stratagems, all 925 enhancements, all 283 detachment abilities, all 70 named abilities + 3,593 inline abilities, all 9,342 weapon profiles. Catalog-only entities (no roster) are P2; roster-fielded entities are P0/P1.

This produces a much larger report but surfaces every gap that would block adding new factions/rosters later.
