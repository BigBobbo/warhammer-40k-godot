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
