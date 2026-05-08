# 03.07 — Fight Phase (Findings)

**Date:** 2026-05-06
**Auditor:** Stage-3 fight-phase agent
**Source rules:** https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#FIGHT-PHASE plus FAQ / Designer Commentary
**Code root:** `40k/phases/FightPhase.gd` (4,340 lines), `40k/scripts/FightController.gd` (3,020 lines), `40k/autoloads/RulesEngine.gd` (10,886 lines), `40k/dialogs/{Fight,Attack,PileIn,Consolidate,Heroic,EndFight}*.gd`.
**Live validation:** ✅ MCP bridge reachable; drove SELECT_FIGHTER → DECLINE_EPIC_CHALLENGE → PILE_IN → BATCH_FIGHT_ACTIONS on `U_WARBOSS_B` vs `U_CUSTODIAN_GUARD_B`. Screenshots `audit_07_fight_select_warboss.png`, `audit_07_fight_save_dialog_powerklaw_vs_2plus.png` under `user://test_screenshots/`.

> **Headline:** much of the 2026-05 audit closure list still verifies. Fight order (charged-first, alternation by defender, three subphases incl. Fights Last), Counter-Offensive, Epic Challenge, Heroic Intervention (now in ChargePhase), per-model fight eligibility, Lance, Extra Attacks (auto-injection AND dialog UI), Sustained Hits, Lethal Hits, Devastating Wounds, Twin-linked, Hazardous, Aircraft restrictions, "no cover in melee", base-to-base enforcement, mandatory consolidation FAQ, consolidation-triggers-new-fights — **all wired and live-driveable**. ONE catastrophic correctness bug surfaced: `_calculate_save_needed` inverts AP. Already documented in `40k/TEST_VALIDATION_REPORT.md` but **not fixed and not filed as a github issue** — this is the single highest launch-blocker the fight audit can hand back.

---

## Findings table

| Rule | Wahapedia § | Depth (C/W/U/L) | Correctness | Evidence | Notes |
|---|---|---|---|---|---|
| Eligible to fight = within ER (1") OR within 2" of friend already in ER | Fight Phase → Eligible Units | L | ✅ | `phases/FightPhase.gd:1479-1496 _is_unit_in_combat`, `autoloads/RulesEngine.gd:3173-3238 get_eligible_melee_model_indices` (per-model two-pass with base-to-base chain) | Live: `U_WARBOSS_B` (charged) and `U_CUSTODIAN_GUARD_B` correctly placed in `fights_first_sequence["2"]` and `normal_sequence["1"]` respectively. ✅ VERIFIED (regression spot-check) — already closed in audit_2026_05. |
| Per-model fight eligibility validated on ASSIGN_ATTACKS | Eligible Units (10e wording) | L | ✅ | `phases/FightPhase.gd:683-710 _validate_assign_attacks` (calls `RulesEngine.get_eligible_melee_model_indices`) | ✅ VERIFIED (regression spot-check) — `.llm/rules-audit.md` MED row, audit_2026_05. |
| Fights First / Remaining Combats / Fights Last subphases | Fight Phase → The Fights First Step | L | ✅ | `phases/FightPhase.gd:77-82 Subphase enum`, `phases/FightPhase.gd:2243-2283 _transition_subphase` (FF → RC → FL → COMPLETE) | **Closes FIGHT_PHASE_AUDIT.md §2.6 (was Open).** Code transitions through all three subphases; Fights Last subphase no longer dead-ends after Remaining Combats. |
| Fights First + Fights Last cancellation | Rules Commentary 10e | C/W | ✅ | `phases/FightPhase.gd:2076-2111 _get_fight_priority` lines 2100-2103: if both flags true → returns NORMAL | **Closes FIGHT_PHASE_AUDIT.md §2.7 (was Open).** Could not live-validate (no unit with both flags in current saved game). LIVE-VALIDATION SKIPPED: no in-game stratagem currently applies fights_last to a charged unit; covered by `_get_fight_priority` unit branch. |
| Charged unit gets Fights First (but Heroic Intervention units do NOT) | Charge Phase → "If a unit ends a Charge move…" | L | ✅ | `phases/FightPhase.gd:2083-2085` checks `flags.charged_this_turn` and explicitly excludes `flags.heroic_intervention` | Live: `U_WARBOSS_B.flags = {charged_this_turn:true, fight_priority:0, fights_first:true, is_engaged:true}`, sequence `fights_first_sequence["2"]=["U_WARBOSS_B"]`. |
| Defending player selects first; alternation by player | Fight Phase → "Starting with the player whose turn it is NOT…" | L | ✅ | `phases/FightPhase.gd:131,200-202 current_selecting_player = _get_defending_player()`, `:2237-2241 _switch_selecting_player` after each consolidate | Live: active=2, selecting=2 → after WARBOSS resolves it switches to 1. |
| Pile-in: ≤3" toward closest enemy | Fight Phase → Pile-in | C/W | ✅ | `phases/FightPhase.gd:556-634 _validate_pile_in` (3" cap with `MOVEMENT_CAP_EPSILON`, direction check, coherency, no-overlap, b2b-if-possible, post-move ER) | LIVE-VALIDATION SKIPPED for direction/3" cap: no contested pile-in geometry available without a deep test fixture. |
| Pile-in must end with unit IN coherency AND in ER | Fight Phase → Pile-in | L | ✅ | `phases/FightPhase.gd:617-624 _can_unit_maintain_engagement_after_movement` post-check | **Closes FIGHT_PHASE_AUDIT.md §2.2 (was Open).** Live: dispatched `PILE_IN movements:{}` → accepted (already in ER, no movement required). |
| Pile-in: base-to-base if possible | Pile-in (10e wording) | C/W | ✅ | `phases/FightPhase.gd:626-633` calls `_validate_base_to_base_if_possible(unit_id, movements, 3.0)`; same helper used for engagement-mode consolidation | **Closes FIGHT_PHASE_AUDIT.md §2.3 (was Open).** |
| Pile-in: models already in base contact cannot move | Pile-in (10e wording) | C | ✅ | `phases/FightPhase.gd:590-596` (T4-5) — non-zero move on a model already in b2b is rejected | **Closes FIGHT_PHASE_AUDIT.md §2.11 (was Open).** Same enforcement mirrored in consolidate path at `:994-1000`. |
| Per-model attack assignment; weapon must be melee | Make Attacks | L | ✅ | `phases/FightPhase.gd:678-681` (`weapon.type == "melee"`); `_validate_assign_attacks` rejects non-melee weapons | Live: assigned `power_klaw_melee` to Custodian Guard, accepted. Attack squig (Extra Attacks) auto-injected. |
| Extra Attacks weapons used IN ADDITION to chosen weapon | Weapon Abilities → Extra Attacks | L | ✅ | `phases/FightPhase.gd:1766-1815 _auto_inject_extra_attacks_weapons` runs in `_process_confirm_and_resolve_attacks`; `dialogs/AttackAssignmentDialog.gd:13-14,57-106` shows them as auto-included with mandatory target selector | **Closes FIGHT_PHASE_AUDIT.md §2.8 (was Open).** Live: BATCH dispatched only `power_klaw_melee` for `m0` — the Attack squig (Extra Attacks) was nonetheless resolved as a second hit/wound block in the dice array (`weapon: "attack_squig_melee", total_attacks: 2`). |
| WS hit roll, S vs T wound, no cover in melee | Make Attacks | L | ✅ | `autoloads/RulesEngine.gd:7929-end _resolve_melee_assignment`; `:8077` `ws = weapon_profile.get("ws", 4)`; `:9439` `prepare_melee_save_resolution` passes `has_cover: false` | Live: Warboss WS=4+, Power klaw S=9 vs T=6 wound on 3+, no cover applied. |
| Critical hit on unmodified 6 (or 5 with Martial Mastery) | Critical Hits | C/W | ✅ | `autoloads/RulesEngine.gd:8210-8218 melee_crit_threshold` (6 default; 5 with Shield Host detachment or `effect_crit_hit_on`) | LIVE-VALIDATION SKIPPED: no critical hits in this run (rolls 4,3,4 / 1,5). Code path mirrors shooting and is exercised in fight tests. |
| Lethal Hits → critical hits auto-wound | Weapon Abilities → Lethal Hits | C/W | ✅ | `autoloads/RulesEngine.gd:8127,8167 has_lethal_hits`; auto-wound branch `:8426-8462` (Lethal Hits crits go to `regular_wound_count`, NOT critical for Devastating Wounds — correct per 10e) | ✅ VERIFIED (regression spot-check) — audit_2026_05 closed this. **Helper `has_lethal_hits` is shared between melee and shooting** — see "Watch for" below. |
| Sustained Hits → critical hits generate bonus hits (1 / D3 / D6) | Weapon Abilities → Sustained Hits | C/W | ✅ | `autoloads/RulesEngine.gd:8128,8302-8327 get_sustained_hits_value + roll_sustained_hits` | **Helper shared with shooting.** Get Stuck In (War Horde) and Here Be Loot (Freebooter Krew) inject Sustained Hits 1 cleanly. ✅ VERIFIED. |
| Devastating Wounds → critical wounds bypass saves | Weapon Abilities → Devastating Wounds | C/W | ✅ | `autoloads/RulesEngine.gd:8129,8456-8462`; melee-only Beastly Rage grants DW post-charge `:8131-8133` | **Helper shared.** ✅ VERIFIED. |
| Twin-linked → re-roll all failed wound rolls | Weapon Abilities → Twin-linked | C/W | ✅ | `autoloads/RulesEngine.gd:8348-8366 has_twin_linked → WoundModifier.REROLL_FAILED` | **Helper shared.** ✅ VERIFIED (regression spot-check). |
| Lance → +1 to wound on charge that turn | Weapon Abilities → Lance | L | ✅ | `autoloads/RulesEngine.gd:4719-4742 is_lance_weapon`, melee branch `:8395-8400`, shooting branch `:1853-1858` and `:2684-2689` | Lance applied IFF `attacker_unit.flags.charged_this_turn`. Live: U_WARBOSS_B has the flag set; Power klaw is not Lance so no +1, but the path is reachable. **Helper shared with shooting** (10e Lance is melee-only per Wahapedia, but the helper is generic and would correctly +1 to wound either path). |
| Anti-[KEYWORD] X+ → critical wound threshold drops vs matching target | Weapon Abilities → Anti-X | C/W | ✅ | `autoloads/RulesEngine.gd:8176-8179, 8345-8346 get_anti_keyword_data, get_critical_wound_threshold` | **Helper shared.** |
| Hazardous post-attack 1s check | Weapon Abilities → Hazardous | C/W | ✅ | `autoloads/RulesEngine.gd:7813-7822 (resolve_melee_attacks)`, `:7910-7919 (interactive)` call `is_hazardous_weapon + resolve_hazardous_check` | ✅ VERIFIED (regression spot-check). |
| Torrent → auto-hit | Weapon Abilities → Torrent | C/W | ✅ | `autoloads/RulesEngine.gd:8190-8204 is_torrent + auto-hit branch` | **Helper shared with shooting.** |
| Precision → wounds can be allocated to attached CHARACTER | Weapon Abilities → Precision | C/W | ✅ | `autoloads/RulesEngine.gd:8136 has_precision`; melee path also accepts EPIC CHALLENGE stratagem-granted Precision; save data carries `has_precision`, `precision_critical_hits`, `precision_wounds` to overlay | **Helper shared.** Verified live: `precision_weapon: false` field present in melee hit-roll dice block. |
| Mandatory consolidation FAQ | Designer Commentary 10e (FGT-1) | C/W | ✅ | `phases/FightPhase.gd:759-761,1947-1953` — empty movements valid for unit-level mandatory step; `_validate_skip_unit:1119-1121` rejects skip when active unit hasn't consolidated | ✅ VERIFIED (regression spot-check), 2026-05 closure. |
| Consolidation: 3" toward closest enemy OR objective fallback | Consolidate | L | ✅ | `phases/FightPhase.gd:781-802 _determine_consolidate_mode` (ENGAGEMENT/OBJECTIVE/NONE), `:972-1031 _validate_consolidate_engagement_range` (b2b-if-possible enforced), `:1033-1083 _validate_consolidate_objective` | ✅ VERIFIED (regression spot-check). |
| Consolidation by enemy → previously-ineligible units now eligible | Fight Phase → Consolidate (10e) | C/W | ✅ | `phases/FightPhase.gd:1995, 2909-3033 _scan_newly_eligible_units_after_consolidation` — appends to `normal_sequence` and `fight_sequence`, emits `fight_sequence_updated`; result includes `newly_eligible_units` for client sync | **Closes FIGHT_PHASE_AUDIT.md §2.4 (was Open).** Considers Aircraft/FLY pairing rules. LIVE-VALIDATION SKIPPED in this session: requires geometric setup not present in current save. |
| Counter-Offensive (1 CP) interrupts alternation | Stratagem (10e Core) | L | ✅ | `phases/FightPhase.gd:2003-2024 _process_consolidate` — after a unit fights, `StratagemManager.is_counter_offensive_available(opponent_player)` + `get_counter_offensive_eligible_units` triggers `awaiting_counter_offensive`; processed by `_validate_use_counter_offensive` `:412-415, 3396` | **Closes FIGHT_PHASE_AUDIT.md §2.9 (was Open).** Wired to dialog and NetworkManager. Could not live-test stratagem prompt without a second non-fought unit; structural code path verified. |
| Epic Challenge (1 CP) on melee selection | Stratagem (10e Core) | L | ✅ | `phases/FightPhase.gd:1146-1156 _process_select_fighter` — emits `epic_challenge_opportunity`, surfaces `trigger_epic_challenge` to client | Live: dispatching SELECT_FIGHTER on U_WARBOSS_B returned `trigger_epic_challenge: true, epic_challenge_player: 2`. Followed up with DECLINE_EPIC_CHALLENGE and proceeded normally. ✅ |
| Heroic Intervention 10e Core Strategic Ploy | Stratagem (10e Core) | L | ✅ | `phases/ChargePhase.gd:27, 59-63, 117-121, 197-204, 247-254, 854-951 USE_HEROIC_INTERVENTION + CHARGE_ROLL + APPLY_MOVE`; `phases/FightPhase.gd:2068-2073 _process_heroic_intervention` redirects to ChargePhase | ✅ VERIFIED (regression spot-check) — audit_2026_05 closed in #324–#348. FightPhase's HI handler is a deliberate idempotent stub since 10e moved the timing window to end-of-charge. |
| Aircraft cannot Pile-in / Consolidate; non-FLY ignore Aircraft for closest-enemy | Aircraft (10e) | C/W | ✅ | `phases/FightPhase.gd:571-579 (pile-in)`, `:745-753 (consolidate)`, `:2965-3009 (newly-eligible scan considers Aircraft/FLY)`, `:2314-2330` filter targets | **Closes FIGHT_PHASE_AUDIT.md §2.10 (was Open).** Couldn't live-test (no AIRCRAFT in current rosters). |
| Engagement range = 1" horizontal AND ≤5" vertical | ER (10e Core) | C/W | ✅ | `autoloads/Measurement.gd:222-229 is_in_engagement_range_shape_aware` (horiz `er_inches` default 1.0, vert ≤5.0) | ✅ VERIFIED (regression spot-check). |
| Sweeping Advance (Custodes detachment / unit ability) | Faction-specific | C/W | ✅ | `phases/FightPhase.gd:38, 92-93, 420-423, 474-477, 3497-3511 _get_sweeping_advance_eligible_units → trigger` | New since FIGHT_PHASE_AUDIT.md was written. Wired to dialog and net-sync. |
| Acrobatic Escape (Callidus Assassin) | Faction-specific | C/W | ✅ | `phases/FightPhase.gd:39, 96-97, 424-427, 478-481` | Wired to its dialog. |
| Save calculation: AP applied as worsening modifier | Make Attacks → Allocate Wound, Saves | **L** | **🐛 BUG (CRITICAL)** | `autoloads/RulesEngine.gd:3694-3729 _calculate_save_needed`. **Live test:** `_calculate_save_needed(2, -2, false, 4) → {armour:2, inv:4, use_invuln:false, save_needed:2}`. WoundAllocationOverlay save card displays `save_needed: 2` for Custodian Guard m1 against AP-2 Power klaw. Correct 10e value: 4+ (2+ armour worsened by AP-2, equal to 4+ invuln → either path needs 4+). | **NOT a refile — already documented in `40k/TEST_VALIDATION_REPORT.md` as a known P0 game-rules bug, BUT not yet filed as a github issue and not yet fixed.** Root cause: line 3696 `armour_save = base_save + ap` — but AP is stored negative (`ap_value = -int(ap_num_str)` at `:4462`), so the sum IMPROVES the save instead of worsening it. The cap at `:3712-3717` (`improvement > 1` clamps to base-1 then floor 2+) hides the bug for high-base saves but not enough to be correct. Affects ALL save resolution: shooting auto-resolve, shooting interactive (`prepare_save_resolution :9165`), melee auto-resolve (`:8624`), melee interactive (`prepare_melee_save_resolution :9354`), Overwatch (`:1179`). |
| WoundAllocationOverlay shows correct save threshold | UX | L | 🐛 | `autoloads/RulesEngine.gd:9441-9455 model_save_profiles[*].save_needed` | Inherits the `_calculate_save_needed` bug. Defender sees a wrong "Save: 2+" for Custodian Guard vs AP-2. |
| Mathhammer prediction shows correct expected damage | UX | C | 🐛 | `phases/FightPhase.gd:1817-1900 _show_mathhammer_predictions` calls into the same RulesEngine save math | Inherits the AP sign bug → predictions overstate target survivability. |

---

## Top 3 launch-blocker Fight-phase gaps

1. **AP sign bug in `_calculate_save_needed` (CRITICAL).** `armour_save = base_save + ap` with AP stored negative produces save-improving math for every weapon with AP < 0. Live: Custodian Guard 2+ vs Power klaw AP-2 returns 2+ instead of 4+. This affects shooting AND melee equally (both call into the same helper). **Fix:** flip the operator to `base_save - ap` (or `base_save + abs(ap)`), then audit `cap_applied` semantics — the existing improvement-cap branch is dead code under the corrected formula and should be replaced by an `armour_save = max(2, base_save - ap)` floor and a separate cover-cap branch. Tests in `tests/unit/test_save_roll_auto_fail.gd` and `tests/unit/test_go_to_ground_smokescreen.gd` already pin the buggy behaviour with explicit "known AP sign bug" comments — those expectations need to flip together with the fix. Already documented in `40k/TEST_VALIDATION_REPORT.md`; **not yet a github issue, not yet a PR.**
2. **No live-validation coverage for the consolidate-creates-new-fight branch.** `_scan_newly_eligible_units_after_consolidation` is correctly wired (FightPhase.gd:2909) but I could not exercise it with the current saved-state geometry. Recommend a dedicated windowed scenario under `40k/tests/scenarios/` that drops a non-engaged P1 unit just outside the WARBOSS's pre-consolidation footprint, then verifies (a) `newly_eligible_units` returns it, (b) `normal_sequence["1"]` grows by one, (c) the FightSelectionDialog picks it up after the alternation switch.
3. **Counter-Offensive UI flow is not driveable from MCP without dialog automation.** `_process_consolidate` correctly emits `counter_offensive_opportunity` and waits, but the dialog-confirm path uses `ChosenUnitId` from `CounterOffensiveDialog`; there is no MCP affordance equivalent to the dialog OK button. Recommend exposing a `dispatch_action({type:"USE_COUNTER_OFFENSIVE", unit_id:...})` shortcut so the new windowed scenarios can validate the alternation interrupt without driving Control nodes.

## Top 3 invisible features

1. **Fights Last subphase exists but has no UI banner / cue.** `Subphase.FIGHTS_LAST` works internally (transitions wired :2266-2277), but `FightPhaseStateBanner.gd` (referenced in scripts/) does not currently appear to render a "Fights Last" callout — players will see the same generic "Remaining Combats" UI when a debuff puts a unit into fights-last. Verify under play; if confirmed, file as UX/visibility issue.
2. **Fights First + Last cancellation has no player-visible explanation.** When `_get_fight_priority` returns NORMAL because both flags are present (lines 2100-2103), only a `log_phase_message` is emitted. No tooltip, no chat-log entry visible to the player explains why their charging unit with a Fights Last debuff fights in Remaining Combats. The rule itself is correct; the rationale is invisible.
3. **`newly_eligible_units` array is returned to the client but the UI does not appear to surface it.** The fight-selection dialog re-renders, but there is no flash / highlight / log banner saying "X became eligible to fight after Y consolidated." Players competing vs an AI consolidator will be surprised when a unit they thought was safe is suddenly in the alternation.

---

## Watch-for follow-up: melee-vs-shooting handler convergence

The audit prompt called out: *"weapon-keyword handlers in melee diverging from shooting handlers — should be the same helper."*

**Status: shared keyword detection helpers, separate resolution functions.**

Shared (same helper called from both `_resolve_assignment` shooting at `RulesEngine.gd:2131` and `_resolve_melee_assignment` at `:7929`):

- `has_lethal_hits` (`:4932`)
- `get_sustained_hits_value` (`:5014`)
- `has_devastating_wounds` (`:5092`)
- `has_twin_linked` (`:5116`)
- `has_precision` (`:5141`)
- `is_lance_weapon` (`:4719`)
- `has_extra_attacks` (`:4744`)
- `is_hazardous_weapon` (`:6290`)
- `is_torrent_weapon` (`:6240`)
- `get_anti_keyword_data` (`:5312`)
- `get_critical_hit_threshold` (`:5997`)
- `get_critical_wound_threshold` (used in both)
- `apply_hit_modifiers`, `apply_wound_modifiers`, `roll_sustained_hits`, `roll_variable_characteristic`, `_calculate_wound_threshold`
- Save resolution: `_calculate_save_needed` (shared — and shares the AP sign bug)
- `prepare_save_resolution` (shooting) and `prepare_melee_save_resolution` (melee) — these differ deliberately (cover/indirect/melta omitted in melee), but they BOTH call the buggy `_calculate_save_needed`.

**Not shared (intentional — different rule sets):**

- Per-model attack count loop: shooting iterates `model_ids` against weapon range / RF / Blast / Indirect; melee iterates eligible-fight-models against engagement-range chain.
- Save flow: shooting includes cover, indirect-fire-cover-override, Melta half-range bonus; melee skips all three and adds Lance / Beastly Rage / Da Boss' Ladz wound modifiers.

**Verdict: convergence is good for keyword detection.** Both paths reuse the same helper functions for keyword presence, threshold derivation, and modifier application — the engine has been kept single-source for the per-weapon ability rules. The two resolution functions diverge only on the rule-mandated differences (cover, melta, RF, Lance scope). **The single shared bug between them (`_calculate_save_needed`) cascades as a single fix point** — that's the upside of the convergence.

---

## Live-validation transcript (this session)

```
ping → ok (engine 4.6-stable)
get_current_phase → FIGHT, active_player=2, available SELECT_FIGHTER U_WARBOSS_B
execute_script /root/PhaseManager get_current_phase_instance().Subphase.keys()[...current_subphase] → "FIGHTS_FIRST"
execute_script (sequence dump) →
  ff_p1=[], ff_p2=[U_WARBOSS_B], n_p1=[U_CUSTODIAN_GUARD_B], n_p2=[],
  fl_p1=[], fl_p2=[], selecting=2, active=""
dispatch SELECT_FIGHTER U_WARBOSS_B → success, trigger_epic_challenge=true (Custodes is a CHARACTER unit eligible for Epic Challenge offer)
dispatch DECLINE_EPIC_CHALLENGE → success, trigger_pile_in=true, pile_in_distance=3
execute_script flags["U_WARBOSS_B"] → {charged_this_turn:true, fight_priority:0, fights_first:true, is_engaged:true}
dispatch PILE_IN U_WARBOSS_B movements:{} → success, trigger_attack_assignment=true, targets={U_CUSTODIAN_GUARD_B:Custodian Guard}
dispatch BATCH_FIGHT_ACTIONS [ASSIGN_ATTACKS power_klaw_melee m0, CONFIRM, ROLL_DICE] →
  dice[0] hit_roll_melee  4+ rolls=[4,3,4] → 2 hits (power_klaw)
  dice[1] wound_roll_melee 3+ S9 vs T6 rolls=[2,6] → 1 wound, regular
  dice[2] hit_roll_melee 4+ rolls=[1,5] → 1 hit (attack_squig — auto-injected as Extra Attacks!)
  dice[3] wound_roll_melee 5+ S4 vs T6 rolls=[4] → 0 wounds
  awaiting_melee_saves=true
  save_data_list[0]: target=U_CUSTODIAN_GUARD_B, weapon=Power klaw, ap=-2, damage=2,
    model_save_profiles[0].save_needed=2 ❌ (should be 4+)
execute_script /root/RulesEngine _calculate_save_needed(2,-2,false,4) → {armour:2, cap_applied:true, inv:4, use_invuln:false}
execute_script /root/RulesEngine _calculate_save_needed(4,-1,false,5) → {armour:3, ...}  ❌ (should be 5+)
capture_screenshot audit_07_fight_select_warboss.png (pre-pile-in)
capture_screenshot audit_07_fight_save_dialog_powerklaw_vs_2plus.png (overlay showing wrong 2+ save)
```

Live transcript is the evidence record for the AP sign bug. Two screenshots saved at `user://test_screenshots/audit_07_fight_select_warboss.png` and `user://test_screenshots/audit_07_fight_save_dialog_powerklaw_vs_2plus.png`.

---

## Status of FIGHT_PHASE_AUDIT.md (repo root) items

This audit's regression spot-check vs the repo-root `FIGHT_PHASE_AUDIT.md` (which itself flags items as Open vs Resolved):

| FIGHT_PHASE_AUDIT.md item | Reported | Reality (this audit) |
|---|---|---|
| §2.1 Per-model fight eligibility | RESOLVED | ✅ verified — `_validate_assign_attacks` at `phases/FightPhase.gd:683-710` |
| §2.2 Pile-in must end with unit in ER | Open | ✅ **CLOSED** — `phases/FightPhase.gd:617-624 _can_unit_maintain_engagement_after_movement` |
| §2.3 b2b enforced in pile-in / consolidate | RESOLVED | ✅ verified — `_validate_base_to_base_if_possible` at `phases/FightPhase.gd:626-633, 1027-1029` |
| §2.4 Consolidate triggers new fights | Open | ✅ **CLOSED** — `_scan_newly_eligible_units_after_consolidation` at `:2909-3033` |
| §2.5 Heroic Intervention | Open (Stub) | ✅ **CLOSED** — moved to ChargePhase per 10e timing; `phases/ChargePhase.gd:854-951` (audit_2026_05 #324–#348) |
| §2.6 Fights Last subphase | Open (Partial) | ✅ **CLOSED** — full FF→RC→FL transition at `phases/FightPhase.gd:2243-2283` |
| §2.7 Fights First + Last cancellation | Open | ✅ **CLOSED** — at `phases/FightPhase.gd:2100-2103` |
| §2.8 Extra Attacks weapon ability | Open | ✅ **CLOSED** — `_auto_inject_extra_attacks_weapons` at `:1766-1815` + `dialogs/AttackAssignmentDialog.gd:13-14, 57-106` |
| §2.9 Counter-Offensive | Open | ✅ **CLOSED** — `_process_consolidate` triggers at `:2003-2024`; validators at `:412-415` |
| §2.10 Aircraft restrictions | Open | ✅ **CLOSED** — pile-in `:571-579`, consolidate `:745-753`, eligibility `:2314-2330`, newly-eligible scan `:2965-3009` |
| §2.11 Models in b2b should not be moved in pile-in | Open | ✅ **CLOSED** — `:590-596` and `:994-1000` |
| §3.3 Race condition in dialog sequencing | Open | ✅ **CLOSED** — `BATCH_FIGHT_ACTIONS` at `:428-429, 1465-1529` resolves sequencing atomically |
| §3.4 Initial dialog sync for client | Workaround | ✅ replaced — `get_pending_fight_selection_data` at `:2202-2208` (T3-13) |
| §3.5 Pile-in / consolidate validation feedback | Open | not regression-checked here; defer to multiplayer audit |
| §3.6 Drag movement not synced visually | DONE | ✅ verified per FIGHT_PHASE_AUDIT.md notes |

`FIGHT_PHASE_AUDIT.md` is therefore stale — most items it lists as Open are now closed (PRs #324–#348 plus other Tx-y batches). Recommend updating that document or marking it superseded.
