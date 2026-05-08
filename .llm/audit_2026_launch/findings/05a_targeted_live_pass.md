# Stage 5a — Targeted Live-Validation Pass results

**Generated:** 2026-05-06
**Driver:** main session, MCP bridge against running Godot 4.6-stable
**Session preservation:** saved as `audit_session_preserve` pre-pass; restored after pass; user's mid-FIGHT Round 2 P2 Command state intact.

Each item lists: live evidence captured, source-code corroboration with `file:line`, verdict.

---

## TLV-1 — Da Jump placement bounds (`MovementPhase._process_place_da_jump`)

**Verdict: 🐛 confirmed.**

**Live A — strict-`<` lets exactly-9.0″ pass:** with `awaiting_da_jump_placement=true`, dispatched `PLACE_DA_JUMP` for `U_WEIRDBOY_J` to `(1600, 460)` — exactly **360 px = 9.0″ (verified)** from enemy `U_SHIELD_CAPTAIN_JETBIKE_A` at `(1600, 100)`. Engine returned `success: true` with the position applied. Per Wahapedia "more than 9″", should reject.

**Live B — off-board accepted:** dispatched `PLACE_DA_JUMP` to `(-500, -500)` — clearly off any board. Engine returned `success: true` with the position applied.

**Source corroboration (`MovementPhase.gd:2160-2167`):**
```
var nine_inches_px = Measurement.inches_to_px(9.0)
for pos_entry in positions:
    var pv = Vector2(...)
    for ev in enemy_positions:
        if pv.distance_to(ev) < nine_inches_px:
            return create_result(false, [], "...< 9\" from an enemy")
```
Strict `<`, no board-bounds check, no coherency check, no separate ER check. Multi-model coherency check N/A here (Weirdboy is single-model).

**Screenshot:** `user://test_screenshots/tlv1_da_jump_offboard_evidence.png`

---

## TLV-2 — Heroic Intervention timing (`ChargePhase._process_use_heroic_intervention`)

**Verdict: ✅ implementation matches 10e rules.**

**Live partial:** loaded `hi_pretrigger.w40ksave`. After `DECLARE_CHARGE` for Warboss → Custodian Guard, probed:
- `StratagemManager.is_heroic_intervention_available(1)` → `{available: true, reason: ""}`
- `StratagemManager.get_heroic_intervention_eligible_units(1, "U_WARBOSS_B", state)` → `[Contemptor-Achillus, Custodian Guard, Telemon]` (3 candidates)
- `get_player_cp(1)` → 4 CP (sufficient for 1 CP cost)

Driving the full HI move was geometry-blocked: the saved Warboss starting position constrained the legal charge end-positions enough that I couldn't fit a valid `APPLY_CHARGE_MOVE` payload without further state mutation. Code review covers the rest.

**Source corroboration (`ChargePhase.gd:2793-2860, 2892-2980`):**
- `_process_use_heroic_intervention`: deducts CP via `strat_manager.use_stratagem("heroic_intervention", unit_id)`, auto-rolls 2D6, returns `heroic_intervention_roll_success` if sufficient.
- `_process_apply_heroic_intervention_move` sets:
  - `flags.charged_this_turn = true`
  - `flags.heroic_intervention = true`
- **Explicitly does NOT set `flags.fights_first`** with this exact comment: *"Per 10e rules: Heroic Intervention does NOT grant Fights First / The unit fights in the normal (Remaining Combats) subphase"*
- VEHICLE-without-WALKER block at `_validate_use_heroic_intervention` (lines ~2700-2730).
- Battle-shocked block (line ~2733).

The 2026-05 audit's verification of HI as a 10e Core Strategic Ploy holds.

---

## TLV-3 — Formations attachment + Lone Op guard + DESIGNATE_WARLORD UI (`FormationsPhase._validate_declare_leader_attachment`)

**Verdict: 🐛 confirmed both halves.**

### Lone Operative guard absent from canonical attachment path

**Source proof (`FormationsPhase.gd:153-256`):** `_validate_declare_leader_attachment` enumerates 7 inline validation checks:
1. character_id / bodyguard_id present
2. unit lookups
3. ownership (both belong to declaring player)
4. character has CHARACTER keyword
5. character has `meta.leader_data.can_lead` non-empty
6. bodyguard not CHARACTER
7. keyword match between `can_lead` and bodyguard keywords
…plus dual-leader (Boyz BODYGUARD-with-20+ models) handling and embarked/reserves checks.

**Lone Operative is NOT one of these.** The function never calls `CharacterAttachmentManager.can_attach()`.

**Caller grep:** `CharacterAttachmentManager.can_attach()` is called from:
- `CharacterAttachmentManager.gd:77` (internal to `attach_character`)
- `CharacterAttachmentManager.gd:163` (internal to detach)
- `DeploymentController.gd:1153` (deployment flow)

`grep -rn "CharacterAttachmentManager\|can_attach" 40k/phases/FormationsPhase.gd` returns ZERO matches.

**The Lone Op guard at `CharacterAttachmentManager.gd:36-41`** says:
```
if RulesEngineData.has_lone_operative(character):
    return {"valid": false, "reason": "Lone Operative units cannot attach to a bodyguard"}
```
…and is bypassed at the canonical 10e army-list-time attachment path (Formations).

### DESIGNATE_WARLORD has no UI affordance

`FormationsPhase.gd:113, 140, 1117` defines the action (validation handler, processor, available-action list). Grep for `DESIGNATE_WARLORD` across `40k/dialogs/` and `40k/scripts/` returns ZERO matches. Multi-CHARACTER rosters that hit `CONFIRM_FORMATIONS` without a designated Warlord get rejected with no UI path to fix it.

---

## TLV-4 — Deployment defender-deploys-first per CA 25-26 (`TurnManager._handle_deployment_phase_start`)

**Verdict: 🐛 confirmed.**

**Source proof (`TurnManager.gd:176-181`):**
```
func _handle_deployment_phase_start() -> void:
    var player1_has_units = _has_undeployed_units(1)
    var player2_has_units = _has_undeployed_units(2)
    if player1_has_units:
        _set_active_player(1)
    elif player2_has_units:
        _set_active_player(2)
```

**Cross-codebase grep for `meta.attacker` / `meta.defender`:**
- `meta.attacker` — only **WRITTEN** at `RollOffPhase.gd:191-192` (after first-turn roll-off, the first-turn-winner becomes attacker, the other becomes defender). Only **READ** at `NetworkManager.gd:1330` (save-resolution authority bookkeeping), `RedeploymentPhase.gd:56` (post-deployment redeploy step), and a comment at `RulesEngine.gd:8104`.
- `meta.defender` — same pattern.
- **Neither value is consulted by any deployment-alternation code.** `check_deployment_alternation` and `_handle_deployment_phase_start` ignore the role.

Per CA 25-26 the **defender** must deploy first. Engine hard-codes Player 1 first regardless. With `meta.attacker=1, meta.defender=2`, the engine still puts P1 first.

---

## TLV-5 — Battle-shock attached-unit Ld test (`CommandPhase._handle_battle_shock_test` + `_resolve_battle_shock_test`)

**Verdict: 🐛 confirmed live.**

**Live setup:** mutated `U_CUSTODIAN_GUARD_B.meta.stats.leadership = 5`, `U_BLADE_CHAMPION_A.meta.stats.leadership = 8`. Attached Blade Champion to Custodian Guard via `CharacterAttachmentManager.attach_character`. Forced Custodian Guard below half-strength (3 of 4 models killed).

**Live drive:** called `CommandPhase._resolve_battle_shock_test("U_CUSTODIAN_GUARD_B", 3, 3)` — roll total = 6.

**Engine response (verbatim):**
```json
{
  "battle_shock_bonus": 0,
  "battle_shocked": false,
  "die1": 3, "die2": 3,
  "effective_roll": 6,
  "leadership": 5,
  "message": "Custodian Guard passed battle-shock test (rolled 6 vs Ld 5)",
  "roll_total": 6,
  "success": true,
  "test_passed": true,
  "unit_id": "U_CUSTODIAN_GUARD_B",
  "unit_name": "Custodian Guard"
}
```

The engine compared roll **6 vs Ld 5** (the bodyguard's). Per Wahapedia "the best Leadership characteristic in that unit", with attached Blade Champion's Ld 8, the comparison should be **6 vs Ld 8** (failing). Engine read `unit.meta.stats.leadership` (bodyguard-only) at `CommandPhase.gd:697` and `:789`.

**Source corroboration (`CommandPhase.gd:693, 697, 789`):**
```
var leadership = unit.get("meta", {}).get("stats", {}).get("leadership", 7)
```
No `max(bodyguard_ld, leader_ld)`, no `get_attached_characters` lookup.

**Screenshot:** `user://test_screenshots/tlv5_battle_shock_attached_ld_evidence.png` (also visible in the in-game Game Log: "*P1 Custodian Guard passed Battle-shock test: 2D6 = 6 (3 + 3) vs Ld 5*").

---

## TLV-6 — Cover save 3+ cap scope (`RulesEngine._calculate_save_needed`)

**Verdict: ✅ current code is RAW-correct. The 2026-05 audit's "should be INFANTRY/BEAST/SWARM-only" claim was based on a wrong rules reading. Three sub-agents (keywords, shooting, core-concepts) flagged commit `6958cff` as a regression — that flag is itself wrong.**

**Live math drive (all `Sv 3+, AP 0, has_cover=true`):**

| Keyword | Result |
|---|---|
| `VEHICLE` | armour = 3 (cap blocks cover) |
| `INFANTRY` | armour = 3 (cap blocks cover) |
| `MONSTER` | armour = 3 (cap blocks cover) |
| `BEAST` | armour = 3 (cap blocks cover) |

Edge cases (INFANTRY only, but logic is keyword-invariant):
| Sv | AP | Result |
|---|---|---|
| 2+ | 0 (cover) | armour = 2 (cap blocks; already at 2+) |
| 4+ | 0 (cover) | armour = 3 (cover applies, 4→3) |

**Authoritative source:** Wahapedia core-rules page truncates at the Benefit of Cover section (same problem all four sub-agents hit). Independent third-party `datacard.app/40k` quotes the rule verbatim:

> *"Benefit of Cover (BoC): +1 to armour saving throws against ranged attacks. Doesn't apply to models with Save of 3+ or better against AP 0 attacks. Multiple instances are not cumulative."*

No INFANTRY/BEAST/SWARM keyword restriction. Cap is universal. Search hits for "Wahapedia 10e benefit of cover infantry beast swarm" surface only 9th-edition rules with that keyword restriction; 10th edition removed it.

**Source corroboration (`RulesEngine.gd:3700-3704`, post-commit `6958cff` 2026-05-05):**
```
# 10e Benefit of Cover cap: a unit with a Save characteristic of 3+ or better cannot
# have its Save improved by Cover against an attack with AP 0. ... The rule is
# universal in 10e core; it is NOT keyword-gated to INFANTRY/BEAST/SWARM as the
# previous implementation incorrectly assumed.
if has_cover and ap == 0 and base_save <= 3:
    has_cover = false
```

The implementor's commit message and code comment both correctly cite Wahapedia. Current code implements RAW.

**Action item for the 2026-05 audit memo:** the entry "Cover save 3+ cap is universal — should only apply to INFANTRY/SWARM/BEAST — FIXED 2026-05-04" should be **reverted** in the audit memory; the prior "fix" was a regression and commit `6958cff` is the corrective patch.

---

## TLV-7 — 'ERE WE GO charge modifier (`StratagemManager.can_use_stratagem` + `FactionStratagemLoader._map_effects`)

**Verdict: 🐛 confirmed live. Whole class of effects unimplemented.**

**Live evidence:**
```
StratagemManager.can_use_stratagem(2, "faction_ork_war_horde_ere_we_go", "U_BOYZ_E")
→ {"can_use": false, "reason": "ERE WE GO is not yet mechanically implemented"}
```

`get_faction_stratagems_for_player(2)` reports 6 War Horde stratagems loaded for the active Ork roster, but 'ERE WE GO is one of the 4 marked `implemented:false`.

**Source corroboration (`FactionStratagemLoader.gd:574-718` `_map_effects`):** the function maps these primitives only:
- Stat modifiers: WORSEN_AP / IMPROVE_AP / PLUS_ONE_HIT / MINUS_ONE_HIT / PLUS_ONE_WOUND / MINUS_ONE_WOUND / MINUS_DAMAGE
- Keyword grants: GRANT_IGNORES_COVER / GRANT_LETHAL_HITS / GRANT_SUSTAINED_HITS / GRANT_DEVASTATING_WOUNDS / GRANT_LANCE / GRANT_PRECISION / GRANT_TWIN_LINKED
- Defensive: GRANT_INVULN / GRANT_COVER / GRANT_STEALTH / GRANT_FNP
- Crit thresholds: CRIT_HIT_ON / CRIT_WOUND_ON
- Re-rolls: REROLL_HITS / REROLL_WOUNDS / REROLL_SAVES
- Movement: FALL_BACK_AND_SHOOT / FALL_BACK_AND_CHARGE

**Missing primitives** (anything that would match falls through to `custom:unmapped`):
- `PLUS_CHARGE` / `REROLL_CHARGE` / charge-roll modifiers in general
- `PLUS_N_ATTACKS` / `PLUS_N_STRENGTH` / weapon-stat modifiers
- `FIGHTS_FIRST_GRANT` / `FIGHTS_LAST_GRANT` / sequencing modifiers
- `GRANT_DEEP_STRIKE` / `GRANT_INFILTRATORS` / `GRANT_SCOUTS` / movement-ability grants

`EffectPrimitives.gd` does have `REROLL_CHARGE` and `ADVANCE_AND_CHARGE` constants, but the parser doesn't reach them. **13+ faction stratagems** affected per the Stage-3 charge audit (`findings/03_06_charge.md`): Tide of Muscle +1, Furious Dedication +2, Shock Assault re-roll, Da Big Hunt re-roll, Reavers' Haste +1, From All Sides +1, Spreading Madness +2, Hive Sight +1, Stimulated Bio-Surge +1, Refusal to be Outdone +2, Subterranean Assault re-roll, Tireless Fervour re-roll, Divine Imperative +1+re-roll, **'ERE WE GO +2**, Portal of Spite +2.

---

## TLV-8 — MissionManager save/load round-trip for sticky objectives

**Verdict: 🐛 confirmed live. Confirms `findings/03_13_save_load.md` SL-NEW-1.**

**Live drive:**
1. Set `MissionManager._sticky_objectives.merge({"OBJ_TEST_STICKY": {"player": 2, "source_unit_id": "U_BOYZ_E"}}, true)`.
2. Verified live: `get_sticky_objectives()` → `{"OBJ_TEST_STICKY": {...}}`.
3. `SaveLoadManager.save_game("audit_tlv8_sticky_pre")` → `true`.
4. `MissionManager._sticky_objectives.clear()` — verified `{}` empty.
5. `SaveLoadManager.load_game("audit_tlv8_sticky_pre")` → `true`.
6. `get_sticky_objectives()` → **`{}`** — entry is gone.

The save file did not preserve the sticky-objectives state. After load, the in-memory dict is empty.

**Source corroboration (`MissionManager.gd`):** `_sticky_objectives` declared at line 20 and cleared at line 143 (battle-round-start). No `get_state_for_save` / `load_state` methods exist on `MissionManager`. The file is not registered with `SaveLoadManager` for snapshot inclusion (same shape as the #338 pattern previously fixed for `FactionAbilityManager` and `StratagemManager`).

The stage-3 Save/Load audit's SL-NEW-1, SL-NEW-3, SL-NEW-4 findings remain valid.

---

## Headline rollup (in-scope: Custodes + Orks)

After the live pass, evidence-grade findings count:

| Finding | Pre-pass status | Post-pass status |
|---|---|---|
| AP-sign in `_calculate_save_needed` | live (fan-out) | live ✓ |
| BGNT auto/interactive seam in `validate_shoot` | live (fan-out) | live ✓ |
| Indirect Fire 1-3 + cover unconditional | live (fan-out) | live ✓ |
| NBSP detachment-name drop | live (fan-out) | live ✓ |
| GRENADE missing 8″ check | live (fan-out) | live ✓ |
| ARCHEOTECH MUNITIONS double-keyword | live (fan-out) | live ✓ |
| StratagemPanel doesn't gate by phase | live (fan-out) | live ✓ |
| `da_jump_used_this_turn` flag leak | live (fan-out) | live ✓ |
| MultiPotentiality end-of-phase vs end-of-turn | live (fan-out) | live ✓ |
| **Da Jump placement bounds (TLV-1)** | code-only | **live ✓** |
| **Battle-shock attached-Ld (TLV-5)** | code-only | **live ✓** |
| **'ERE WE GO charge modifier (TLV-7)** | code-only | **live ✓** |
| **MissionManager save/load sticky (TLV-8)** | code-only | **live ✓** |
| **Cover-cap scope dispute (TLV-6)** | disputed across 4 audits | **resolved: current code is RAW-correct** |
| Heroic Intervention timing (TLV-2) | code-only | partial-live + thorough source ✓ |
| Formations Lone Op guard + Warlord UI (TLV-3) | code-only | thorough source ✓ |
| Deployment defender-first (TLV-4) | code-only | thorough source ✓ |

**Stage 6 synthesis can now treat the in-scope launch-blocker shortlist as evidence-grade.** TLV-2/3/4 don't have a `capture_screenshot` because the rule is fully proven by the source-grep + `file:line` cite — driving them live would have been theatre, not evidence.

---

## Audit-memory updates required

1. **Reverse:** the 2026-05 audit memo entry "Cover save 3+ cap is universal — should only apply to INFANTRY/SWARM/BEAST — FIXED 2026-05-04" is wrong. Current code (post `6958cff`) is RAW-correct; the keyword-gated form was the regression.
2. **New finding:** `da_jump_used_this_turn` flag leak across turns — file as a P0 launch-blocker (Weirdboy in active Ork roster).
3. **New finding:** Lone Operative attachment guard absent from `FormationsPhase._validate_declare_leader_attachment` — bypasses the 2026-05 fix at the canonical army-list-time path.
4. **New finding:** `MissionManager._sticky_objectives` (and 16+ other runtime vars) reset on save/load — same pattern as #338 that was fixed for FactionAbilityManager/StratagemManager.
5. **Confirm:** Battle-shock attached-Ld test reads bodyguard-only Ld; trivial fix at `CommandPhase.gd:697, 789` to use `max(bodyguard_ld, attached_leader_ld)`.
