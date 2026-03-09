# Undone Audit Tasks

Tasks from previous `run_audit_tasks.sh` runs that were never completed.

---

## MASTER_AUDIT.md (5 undone)

| Task ID | Description |
|---------|-------------|
| T4-20 | **Auto-detect weapon abilities from unit datasheet** — Weapon keywords (Lethal Hits, Sustained Hits, etc.) exist in unit data but aren't auto-enabled as toggles. `extract_unit_rules()` exists but isn't connected to UI. |
| T5-MP7 | **Game over UI with winner and reason** — Code TODO in `NetworkManager.gd:1474` |
| T6-3 | **Add E2E workflow tests** — No full deployment -> movement -> shooting -> fight test. No multi-turn game simulation. |
| T7-41 | **AI army-specific strategies** — Identical heuristics regardless of army. Detect archetype based on weapon/keyword distribution: melee-focused (aggressive advance, early charges), shooting-focused (castle, maintain range), balanced, elite (protect key models). |
| T7-48 | **AI Pistol usage in engagement range** — Doesn't fire Pistols when units are in engagement range. |

---

## ABILITIES_AUDIT.md (9 undone)

| Task ID | Description |
|---------|-------------|
| P2-21 | **Fix Daughters of the Abyss** — Restrict FNP 3+ to psychic/mortal wounds only |
| P2-22 | **Fix Stand Vigil** — Add objective-conditional reroll-all upgrade |
| P2-32 | **Implement Transport capacity** — Embark/disembark mechanics |
| P2-33 | **Add optional wargear** — Helix Gauntlet (FNP 6+), Infiltrator Comms Array (CP regen) |
| P2-38 | **Add per-model undo during deployment** — Current undo resets entire unit. Add Ctrl+Z to undo only the last placed model. Keep full-unit reset as separate button. |
| P2-40 | **Add opponent deployment camera pan and notification in multiplayer** — When opponent deploys a unit: briefly pan camera, show toast, add deployment log panel. |
| P3-34 | **Implement Devoted to Destruction** — +2 Attacks with dual Telemon caestus |
| P3-35 | **Implement Bodyguard (20-model)** — Double Leader attachment for large Boyz units |
| P3-126 | **Add phase transition sound effects** — Audio cues for phase changes in PhaseTransitionBanner.gd (VIS-13) |

---

## SAVE_AUDIT.md (3 undone)

| Task ID | Description |
|---------|-------------|
| P0-2 | **Fix multiplayer load sync confirmation** — Add client acknowledgment mechanism (SAVE-2) |
| P0-4 | **Fix _refresh_after_load() to fully restore state** — Clear old visuals, reinit controllers, reinit AI (SAVE-4) |
| P3-19 | **Add save file export/import** — Portable format for sharing (SAVE-19) |

---

## MODEL_ATTRIBUTES_TASKS.md (11 undone)

### Phase 0: Bug Fixes (3 failed)

| Task ID | Description |
|---------|-------------|
| MA-36 | **Fix ESC key not opening menu during shooting phase** — ESC during shooting phase does not open the game menu. May be intercepted by weapon/target selection or a modal dialog. Needs ESC to cancel action first, then open menu on second press. |
| MA-38 | **Fix movement range using strict less-than instead of less-than-or-equal** — Movement validation uses `<` instead of `<=` against Move characteristic. Per 10th Ed rules, a model can move "up to" its Move value (inclusive). Also applies to Advance, charge, pile-in, and consolidate. |
| MA-42 | **Block active player actions while reactive stratagem decision is pending** — When a reactive stratagem prompt (Fire Overwatch, Rapid Ingress, etc.) is shown to the non-active player, the active player can still act. Needs input blocking, "Waiting for opponent..." indicator, and 5-second auto-decline timer. |

### Phase 2: Core Weapon Assignment (1 failed)

| Task ID | Description |
|---------|-------------|
| MA-8 | **Update weapon filter functions for per-model profiles** — `get_pistol_weapons()`, `get_assault_weapons()`, `get_heavy_weapons()`, `get_rapid_fire_weapons()`, `get_torrent_weapons()` need per-model filtering when `model_profiles` exists. Fallback to current behavior without profiles. |

### Phase 3: Per-Model Stats in Combat Resolution (1 failed)

| Task ID | Description |
|---------|-------------|
| MA-12 | **Per-model save characteristics in wound allocation** — `prepare_save_resolution()` builds save profiles from unit-level stats. Needs `stats_override` merge for per-model `save` and `invuln`. Pass through to `model_save_profiles` used by WoundAllocationOverlay. Both interactive and auto-resolve paths. |

### Phase 4: Deployment Model Selection (2 failed)

| Task ID | Description |
|---------|-------------|
| MA-18 | **Update formation deployment for mixed base sizes** — `calculate_spread_formation()` and `calculate_tight_formation()` use first model's `base_mm` for all. With heterogeneous units, models may have different base sizes. Fix: use each model's actual `base_mm` for spacing, coherency, and base-touching. |
| MA-19 | **Combined deployment (character + bodyguard) with model types** — Model picker should show character models as their own type group alongside bodyguard types. Character models should always be placeable. Extend `combined_models` to include `model_type`. |

### Phase 5: Token Visuals & Model Identity (1 failed)

| Task ID | Description |
|---------|-------------|
| MA-22 | **Show model type in casualty reporting** — Death logging should include model type profile label: "Spanner (m11) destroyed" instead of "m11 destroyed". Update RulesEngine damage application and WoundAllocationOverlay. |

### Phase 7: Ability & Effect Integration (3 failed)

| Task ID | Description |
|---------|-------------|
| MA-27 | **Add per-model stat lookup helper** — Create `RulesEngine.get_model_effective_stats(unit, model)` that returns unit base stats merged with model's `stats_override`. Used by hit resolution (BS/WS), save resolution, wound allocation. Falls back to base stats without profiles. |
| MA-28 | **Per-model FNP (stretch goal)** — `get_unit_fnp()` returns single FNP for unit. Add `get_model_fnp(unit, model)` checking `stats_override.fnp` first. Update `roll_feel_no_pain()` to accept per-model FNP. Only needed when a unit with mixed FNP models exists. |
| MA-29 | **Ability weapon targeting filter (stretch goal)** — Add optional `target_weapon_names` field to ability effect definitions. When applying attack bonuses, filter to only models whose profile includes the named weapon. Currently all abilities apply unit-wide. |
