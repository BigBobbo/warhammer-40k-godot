# 03.02 — Core Concepts

**Read first:** `00_overview.md`, `03_core_rules/README.md`.
**Output:** `.llm/audit_2026_launch/findings/03_02_core.md`

## Scope

Audit the foundational mechanics that every phase depends on. Enumerate rules from these Wahapedia sections:
- Datasheets (anatomy: M, T, Sv, W, Ld, OC; weapon: Range, A, BS/WS, S, AP, D)
- Models, Units, coherency
- Visibility / Line of Sight (true LoS)
- Engagement Range (1" horizontal, 5" vertical)
- Modifiers (cap ±1 to-hit/to-wound/to-save; final modifiers, not stacked)
- Re-rolls (applied before modifiers; cannot re-roll a re-roll)
- Random values (per-attack vs. per-phase determination)
- Mortal wounds (resolution, FNP applies, spillover within unit)
- Damage allocation (one model at a time until destroyed; held wounds)
- Mixed-save resolution (defender chooses which model)
- Out-of-phase abilities ordering (active player first)
- Natural roll-of-1 always fails; natural roll-of-6 always succeeds (hit/wound)
- Critical Hit / Critical Wound (unmodified 6)
- Rolling off ties

## Codebase entry points

`40k/autoloads/RulesEngine.gd` (this is the single most important file for this audit), `40k/autoloads/Measurement.gd`, `40k/autoloads/LineOfSightManager.gd`, `40k/autoloads/EnhancedLineOfSight.gd`, `40k/autoloads/BoardState.gd`, `40k/autoloads/EffectPrimitives.gd`.

## Live-validation focus

- Stack three modifiers on a hit roll (cover, Stealth, Heavy stationary) and confirm cap of ±1 holds
- Allocate damage to a wounded model first vs. spread incorrectly to a fresh model
- Trigger a mortal-wound spillover into the next model in a unit
- Verify Critical Hit on natural 6 even when modified to ≤5 still triggers Lethal Hits / Sustained Hits effects

## Prior-audit overlap

- Cover save 3+ cap is INFANTRY/BEAST/SWARM only — verified 2026-05-04 in `autoloads/RulesEngine.gd:3674-3704`
- Heavy / Stealth modifier sources cap at ±1 — confirmed at clamp sites `autoloads/RulesEngine.gd:596,647`

## Output prose

Top 3 launch-blocker core-concept gaps; top 3 invisible features. Highlight any case where the engine evaluates rules differently between Shooting and Fight phases (a single helper should resolve the attack sequence for both — flag if duplicated).
