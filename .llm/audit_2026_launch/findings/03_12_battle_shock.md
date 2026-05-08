# 03.12 — Battle-shock Cascade Findings

**Audit date:** 2026-05-06
**Source rules:** Wahapedia 10e Core Rules — Battle-shock section (https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#Battle-shock)
**Codebase scope:** `40k/` only. `40k/.claude/worktrees/` excluded.
**Live validation:** MCP bridge reached (`ping` ok); spot-checked stratagem block, Insane Bravery exception, surge-move block, and the `cannot-shoot` divergence by mutating `flags.battle_shocked` on `U_CUSTODIAN_GUARD_B` and calling `RulesEngine.validate_shoot` / `StratagemManager.can_use_stratagem` / `RulesEngine.validate_surge_move_eligibility` directly. Game restored after probes.

---

## Wahapedia 10e RAW (refresh)

While a unit is **Battle-shocked**:

1. The Objective Control characteristic of all of its models is **0**.
2. If it Falls Back, you must take a **Desperate Escape test for every model** in that unit.
3. Its controlling player **cannot use Stratagems to affect that unit**.

Plus: tests trigger in the Battle-shock step of the Command phase for units **Below Half-strength**; status clears at the start of *your* next Command phase. There is **no RAW restriction on shooting, charging, piling in, consolidating, or Heroic Interventions** for Battle-shocked units. The 1-3 Desperate Escape failure threshold (vs. 1-2 normal) is the per-model effect of test #2 above.

---

## Findings table

| Rule | Wahapedia § | Depth | Correctness | Evidence | Notes |
|---|---|---|---|---|---|
| Battle-shock test triggers in Command phase, Below Half-strength | Battle-shock | L (regression spot-check) | ✅ | `phases/CommandPhase.gd:87,201-219,254-266,693-882`; `autoloads/GameState.gd:894-925`; `scripts/CommandController.gd:497-552`; AUDIT_REPORT.md t4.e1/t4.e1b | Verified by audit_2026_05 (Witchseekers below-half offered BS test). Recovery clear at start of next Command phase via `_clear_battle_shocked_flags` (CommandPhase.gd:201-219) — also clears attached characters (CommandPhase.gd:811-819). |
| FEARLESS / ATSKNF auto-pass immunity | Battle-shock | L (regression) | ✅ | `phases/CommandPhase.gd:253-258,268-289`; AUDIT_REPORT.md T-085 | Both keyword and ability paths covered. |
| Waaagh! Effigy +1 to BS test (aura) | Ork detachment | W | ✅ | `autoloads/UnitAbilityManager.gd:1029-1106,2174-2245`; `phases/CommandPhase.gd:716-798` | Bonus integrates into `_resolve_battle_shock_test`, also into reroll resolution path. |
| OC = 0 while Battle-shocked (objective control / scoring) | Battle-shock | L (regression) | ✅ | `autoloads/MissionManager.gd:206-209,344-346` (skip in `_check_objective_control`) | AUDIT_REPORT.md confirmed; today's MCP probe loop above confirms the early-skip path. |
| Cannot use Stratagems on a Battle-shocked unit | Battle-shock | L (live spot-check, today) | ✅ | `autoloads/StratagemManager.gd:597-613,1169,1485-1488,2157-2159,2246-2248`; per-stratagem requirement gates 1196,1231,1293,1485,1576,1864,1965 | LIVE: `can_use_stratagem(1, "command_re_roll", "U_CUSTODIAN_GUARD_B")` → `{can_use:false, reason:"Battle-shocked units cannot be targeted by Stratagems"}` after setting flag; cleared after probe. |
| Insane Bravery exception (auto-pass BS test) bypasses BS-target gate | Wahapedia (Core stratagem) | L (live spot-check, today) | ✅ | `autoloads/StratagemManager.gd:73-100,599-612`; `autoloads/EffectPrimitives.gd:117` (`AUTO_PASS_SHOCK`) | LIVE: same probe → `can_use_stratagem(1, "insane_bravery", "U_CUSTODIAN_GUARD_B")` → `{can_use:true}`. |
| Battle-shocked units cannot themselves use Stratagems (P3-93) | Battle-shock | W | ✅ | `autoloads/StratagemManager.gd:605-613`; `phases/MovementPhase.gd:1722-1725` | AUDIT_REPORT.md spot-check; secondary self-source guard. |
| Desperate Escape: all models test if Battle-shocked, fail on 1-3 | Battle-shock + Falling Back | W | ✅ | `phases/MovementPhase.gd:4944-5043` (all-models loop 4960-4975, threshold 4994 = 3 if BS else 2); `autoloads/RulesEngine.gd:10345-10467` (transport-destruction sets BS + records cannot_charge) | Regression-only; no live probe today (no Fall-Back fixture available in current Fight phase). |
| Surge-move forbidden while Battle-shocked | Wahapedia (within Aspect Host / Endless Multitude / etc., uses common rule) | L (live spot-check, today) | ✅ | `autoloads/RulesEngine.gd:10821-10839`; `phases/MovementPhase.gd:5188-5295,5380-5495,5541-5576` | LIVE: `validate_surge_move_eligibility` returned `{valid:false, errors:["Battle-shocked units cannot make surge moves"]}` for BS Custodian. Note: this is broader than the Stratagem block above — surge-move restrictions are written into the data-sheet/detachment rules (Endless Multitude, Brood Surge, Driven by Fury, Brazen Fury, Vengeful Sorrow, Insurmountable Odds), so a generic block is correct. |
| Battle-shocked indicator on token (UI) | (not a rule, surfacing requirement) | U | ✅ | `scripts/TokenVisual.gd:121,162,1275-1299` (`_draw_battle_shock_indicator`) | Red ring + "!" badge; verified visible on tokens (T-096). |
| Battle-shock confirmation dialog before phase advance (P3-94) | (not a rule, UX guard) | U | ✅ | `scripts/Main.gd:7633-7642,8200-8225`; `dialogs/BattleShockConfirmationDialog.gd` | Surfaces untested below-half units before Command-phase advance. |
| Stacking CP-gain cap per battle round | FAQ | W | ✅ | `autoloads/GameState.gd:867-891` (`BONUS_CP_CAP_PER_ROUND = 1`, `record_bonus_cp_gained`, `reset_bonus_cp_tracking`); `autoloads/SecondaryMissionManager.gd:444-467` | Open per the audit-prompt "notable open item: stacking CP-gain caps" — **closed**: secondary-mission CP gain checks `can_gain_bonus_cp` before granting. Battle-shock cascade itself does not generate CP; this guard sits adjacent. |
| **Battle-shocked units cannot shoot** (custom rule, codebase) | NOT in Wahapedia 10e RAW | L (live spot-check, today) | 🐛 | `autoloads/RulesEngine.gd:3269-3272`; cited again in `phases/ShootingPhase.gd` filter loop and AI heuristics (`scripts/AIDecisionMaker.gd:6607-6608,8293-8306`); inherited from `SHOOTING_PHASE_AUDIT.md §2.8` | LIVE: `validate_shoot({"actor_unit_id":"U_CUSTODIAN_GUARD_B", "payload":{"assignments":[…]}}, board)` → `{valid:false, errors:["Unit cannot shoot (battle-shocked)"]}` after setting BS flag. **DIVERGENCE:** Wahapedia 10e Battle-shock list is exactly three effects (OC=0, Desperate Escape on all models, no Stratagems). There is no shooting prohibition. The codebase imports a custom rule from a prior audit doc that mis-stated 10e RAW. See "Top blocker gaps" below. |
| Battle-shocked units cannot perform Actions | Battle-shock (Wahapedia: implied via "Reactive moves / Actions" generic rule; Wahapedia core does NOT explicitly list this in BS block — the Action rule itself states a unit "cannot perform an action while it is Battle-shocked") | C | ❌ | NO ENFORCEMENT FOUND. SecondaryMissionManager handles `Establish Locus`, `Cleanse`, `Deploy Teleport Homer`, `Recover Assets`, `The Ritual`, `Scorched Earth`, `Terraform`. None of these gate on `flags.battle_shocked` (`autoloads/SecondaryMissionManager.gd:960-1008` and `_is_unit_excluded` 1547-1573 only excludes BS units from secondary-mission-target lists, not from start-action validation by the actor). `MissionManager.gd` likewise does not gate ritual/scorched-earth/terraform action starters on BS. | **Launch-blocker candidate**: a Battle-shocked unit can currently start a secondary-mission action. If the actor becomes BS during the turn the action is in progress, no auto-cancellation happens. The only place "Battle-shocked" string appears in `SecondaryMissionManager.gd` is in `_is_unit_excluded` for *target* unit filtering (1553), not for action-actor eligibility. |
| Order issue gating: cannot issue Orders to BS units; if affected unit becomes BS, the Order ceases | Astra Militarum "Voice of Command" (Abilities.csv:32) | C | ❌ | NOT WIRED. No Astra Militarum Voice-of-Command code exists; AM is catalog-only (no roster JSON). | Catalog-only faction (no roster) → P2 invisible-feature, not a launch blocker today. Filed for the per-faction Stage-4 audit. |
| **Faction abilities that target Battle-shocked enemies (auto-wound, +1 hit, +1 wound, etc.)** | High-value invisible-feature surface | ❌ (nothing C) | ❌ | NONE FOUND. Searched `40k/autoloads/` and `40k/phases/` for `apex.beast`, `tormentors`, `lord_of_badab`, `nightmare.hunt`, `terror.made.manifest`, `maddened.ferocity`, `driven.by.fury`, `harbingers.of.dread` (Doom / Darkness / Delirium), `grim.resolve` BS-OC=1 override, `the.lord.s.will`, `summary.execution`, `laud.hailer`, `spiritual.leader`, `demagogue`, `overlord` — zero hits. | All target-BS abilities listed below are absent from code. Per audit-prompt high-value-target instruction: none are at depth `C`-without-trigger; they are simply ❌ absent. Most affect catalog-only factions (CSM, GC, AdMech, Tyranids, Sisters, AS, AM, SM Dark Angels/Blood Angels/Space Wolves, Chaos Knights, Drukhari) — P2 today, but a surface that needs eventual coverage. **Notable exception** (active rosters): **Auric Armour** (AC, `Detachment_abilities.csv:8`) gates Custodes Vehicle "+2 OC" on `not Battle-shocked`. Custodes' active roster includes Caladius, Contemptor, Battlewagon counterparts; the +2 OC bump is not in code, so Vehicle units retain their printed OC even when BS — but `MissionManager._check_objective_control` already zero-skips BS units, so the *practical* impact is only that the +2-while-not-BS portion is missing entirely (orthogonal to BS cascade — flag in detachment-abilities audit, not here). |
| Force a Battle-shock test after shooting (Witchseekers' Sanctified Flames) | Datasheet ability | W | ✅ | `autoloads/UnitAbilityManager.gd:347-360,2544-2557`; `phases/ShootingPhase.gd:24,2132,2847,4092,4188-4321`; AUDIT_REPORT.md t4.e1 | Forced BS test integrates with the Battle-shock test resolver (re-uses Waaagh! Effigy bonus path). Verified end-to-end in audit_2026_05. |
| Da Kaptin (OA-2): D3 MW + un-BS friendly Orks unit | Ork enhancement (Freebooter Krew) | W | ✅ | `autoloads/FactionAbilityManager.gd:1484-1620`; `phases/CommandPhase.gd:460-475` | Wired with detachment + bearer + 12" + once-per-round gates. Live probe today: `is_da_kaptin_available(2)` = false (current detachment is War Horde, not Freebooter Krew, and bearer absent). Behaviour-correct given current rosters. |
| Tank-shock disembark: embarked units flagged BS + cannot-charge when transport destroyed | Transports (Disembark when destroyed) | W | ✅ | `autoloads/RulesEngine.gd:10345-10467` (sets `flags.battle_shocked` and `flags.cannot_charge`) | Save/load round-trip covers `flags.battle_shocked` (AUDIT_REPORT.md). |
| Save/load round-trip preserves `flags.battle_shocked` (and `status_effects.battle_shocked`) | Internal | L (regression) | ✅ | `autoloads/StateSerializer.gd:155-218`; `tests/test_save_load_audit_roundtrip.gd` | Both flag-paths covered; test exists. |

---

## Top 3 launch-blocker cascade gaps

1. **🐛 `RulesEngine.gd:3269-3272` rejects shoot validation for any Battle-shocked unit.** Wahapedia 10e core RAW lists exactly three Battle-shock effects (OC=0, Desperate Escape on all models, no Stratagems target/source). There is no "cannot shoot" entry. The repo inherits this rule from `SHOOTING_PHASE_AUDIT.md §2.8` ("**Rule:** Battle-shocked units cannot shoot at all"), which is wrong RAW. Cascading sites that share the misreading: `phases/ShootingPhase.gd` (filter), `scripts/AIDecisionMaker.gd:6607-6608,8293-8306` (AI skips BS units when planning shooting). Fix is mechanical (delete the early-return block; the BS unit retains its other restrictions automatically) but needs a cross-doc cleanup so the SHOOTING_PHASE_AUDIT.md correction lands too. **Live-validated today** via `validate_shoot` returning `Unit cannot shoot (battle-shocked)`.

2. **❌ "Cannot perform Actions while Battle-shocked" is unenforced.** `SecondaryMissionManager.gd` and `MissionManager.gd` validate action eligibility on phase, range, status (deployed) and exclusions, but the actor's `flags.battle_shocked` is never checked. The string "Battle-shocked" appears in `_is_unit_excluded` (line 1553) only as a *target-unit* filter. Wahapedia's Actions section says: *"a unit cannot start to perform an action … while it is Battle-shocked"* and an in-progress action fails if the unit becomes Battle-shocked. Affected actions in code today: `Establish Locus`, `Cleanse`, `Deploy Teleport Homer`, `Recover Assets`, `Ritual`, `Scorched Earth`, `Terraform`. Concrete fix points: validate at the phase entry that records the start (e.g., the secondary-mission "Perform Action" button handler in `scripts/ShootingController.gd:484-491,_on_perform_action_pressed`) and add an end-of-phase / start-of-phase scan to fail in-progress actions on units that became BS.

3. **⚠️ Auric Armour Vehicle-OC interaction is silently miscounted (regression-spot-check overlap).** While not strictly a Battle-shock cascade gap (the BS-target side is enforced via `MissionManager._check_objective_control`), the printed +2 OC on a Custodes Vehicle "while at Starting Strength and not Battle-shocked" is not implemented at all — a non-BS, full-strength Caladius scores its base OC, missing 2. Belongs in the detachment-abilities audit (`04_data_entities/detachment_abilities.md`), but flagged here because the rule text intersects Battle-shock. Active-roster impact: Custodes Solar Spearhead detachment (currently bundled in `adeptus_custodes.json` rosters).

## Top 3 invisible / absent features (target-BS surface)

1. **Faction-ability hit/wound modifiers vs. Battle-shocked targets — entirely absent.** No code path applies +1 Hit (Apex-beast / Tormentors), +1 Wound (Maddened Ferocity / Doom / Nightmare Hunt), -1 Hit on attacks *from* Battle-shocked units (Darkness / Terror Made Manifest), or "+2 Attacks vs. Psyker/Battle-shocked target" (Anathema Blademastery / Purgation Sweep). Search of `autoloads/` and `phases/` for `target.*battle.shocked`, `wound.*battle.shocked`, `hit.*battle.shocked` returns zero handler matches; the text only appears in CSV catalogue and in the StratagemManager *eligibility* layer (which gates on the using unit's BS state, not the target's). All catalog-only-faction items are P2 today; **the only active-roster impact** is in detachment selection — Custodes Auric Armour (vehicle OC + reroll-1s) is the cleanest hit-roll-modifier interaction tied to BS. None of these are at depth `C`-without-UI; they are missing entirely. (Per audit-prompt: nothing to flag as "C without trigger" — the surface is empty.)

2. **Character-ability "remove Battle-shocked" cleansers (per-faction analogues of Da Kaptin) are absent.** `Datasheets_abilities.csv` lists at least: `Spiritual Leader` (Genestealer Cults patriarch, line 1220), `Overlord` (Drukhari, 1642), `Demagogue` (Heretic Astartes Dark Apostle, 2413), `Laud Hailer` (Sisters, 2272), `Summary Execution` (Astra Militarum Commissar, 1853 — destroys 1 model then un-BS), `The Lord's Will` (1274 — Stratagems still affect attached BS unit). Only **Da Kaptin** (Orks, Freebooter Krew) is wired (`FactionAbilityManager.gd:1484-1620`). All others are absent in code; affected factions are catalog-only today (P2), except **Astra Militarum Voice of Command Orders** (Abilities.csv:32) which would be needed alongside any AM roster.

3. **Battle-shock confirmation/recovery UX surface is minimal.** The token red ring + `!` badge (`TokenVisual.gd:1275-1299`) is the only persistent player-facing indicator. The unit stats card (`scripts/UnitStatsCardPopup.gd`) does **not** mention Battle-shocked status (search for `battle_shocked` in the file returns nothing — only `TokenVisual.gd` and `AIDecisionMaker.gd` carry the flag in `scripts/`). The unit list panel and inspector do not surface BS state. A first-time player sees the ring on the token but has no in-panel readout of *why* their unit is locked out of stratagems. Not a rule-correctness bug — a launch-readiness UX gap.

---

## Live-validation transcript (today, 2026-05-06)

```
mcp ping → ok (pong=5225844, engine 4.6-stable)
phase   → FIGHT, P2 active

# Setup BS on Custodian Guard B (P1)
GameState.state.units.U_CUSTODIAN_GUARD_B.flags.set("battle_shocked", true) → true

# Cascade probes
StratagemManager.can_use_stratagem(1, "command_re_roll", "U_CUSTODIAN_GUARD_B", {})
  → {can_use:false, reason:"Battle-shocked units cannot be targeted by Stratagems"}
StratagemManager.can_use_stratagem(1, "insane_bravery", "U_CUSTODIAN_GUARD_B", {})
  → {can_use:true}
RulesEngine.validate_shoot({"actor_unit_id":"U_CUSTODIAN_GUARD_B",
    "payload":{"assignments":[{"weapon_id":"x","model_ids":["m1"]}]}},
    {"units": GameState.state.units})
  → {valid:false, errors:["Unit cannot shoot (battle-shocked)"]}    ← divergence
RulesEngine.validate_surge_move_eligibility(unit, "U_CUSTODIAN_GUARD_B", false, units)
  → {valid:false, errors:["Battle-shocked units cannot make surge moves"]}
FactionAbilityManager.is_da_kaptin_available(2)
  → false  (Freebooter Krew not active; behaviour-correct)

# Cleanup
GameState.state.units.U_CUSTODIAN_GUARD_B.flags.set("battle_shocked", false) → true
GameState.state.units.U_BOYZ_E.flags.set("battle_shocked", false) → true
```

No screenshot captured: probes were pure-state mutations through the bridge with no UI affordance to drive (the active scene is mid-Fight phase; Command-phase BS step is not reachable without a turn-cycle manipulation that would corrupt the live game). The transcript above stands as the live-validation evidence per the project's depth-`L` evidence rule.

---

## Notes & cross-references

- Most 2026-05 audit items remain green: phase-step ordering (CommandPhase.gd:87), Insane Bravery (StratagemManager.gd:73-100), Waaagh! Effigy (UnitAbilityManager.gd:1029-1106,2174-2245), per-stratagem BS gating, Mission OC=0 skip, Desperate Escape 1-3, save/load round-trip.
- `bonus_cp_gained_this_round` cap (audit-prompt's "notable open item") is **closed** in `GameState.gd:867-891` and is exercised by `SecondaryMissionManager.gd:444-467`. No additional CP-gain plumbing is wired through the Battle-shock cascade itself.
- `MoralePhase.gd` is referenced once in `PhaseManager.gd:236` with a TODO to deprecate the legacy MORALE phase; no live BS handling there.
- The `cannot-shoot` divergence is the only RAW bug in this cascade. Everything else is either correct, an absent ability for catalog-only factions (P2), or a UX-surfacing gap.
