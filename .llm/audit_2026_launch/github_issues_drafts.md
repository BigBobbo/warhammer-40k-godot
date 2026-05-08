# Path A — GitHub Issue Drafts (26 issues, 5 batches)

**Generated:** 2026-05-06
**Audit:** 2026-05-06 launch audit (Path A scope: Custodes + Orks)
**Synthesis ref:** `.llm/audit_2026_launch/findings/06_SYNTHESIS.md`
**Repo:** BigBobbo/warhammer-40k-godot

Each issue uses the project's existing format (Summary / Reproduction / Per WH40K 10e / Fix / Severity / Discovered during). All cite the canonical finding doc + file:line.

Recommended common labels: `bug`, `MVP`, `audit_2026_launch` (NEW — create if missing). Per-issue labels listed inline.

---

## Batch A1 — Every-turn correctness (~1 week, S effort each)

### A1-1. AP-sign bug in `_calculate_save_needed` improves saves under negative AP

**Labels:** `bug`, `pri_high`, `MVP`, `shooting_phase`, `charge_phase`

```
## AP-sign bug in `_calculate_save_needed` — saves IMPROVE under negative AP

### Summary
`RulesEngine._calculate_save_needed` computes `armour_save = base_save + ap` with AP stored as a negative integer. Result: AP-2 vs Sv 2+ returns `save_needed: 2` instead of `4+`. The bug affects shooting AND melee equally — both call into the same shared helper. `40k/TEST_VALIDATION_REPORT.md` documents this with explicit "known AP sign bug" comments in two test files (`tests/unit/test_save_roll_auto_fail.gd`, `tests/unit/test_go_to_ground_smokescreen.gd`) but no GitHub issue or PR was filed.

### Reproduction (live, captured during 2026-05-06 audit)
`execute_script` against running game:
- `RulesEngine._calculate_save_needed(2, -2, false, 4)` → `{armour: 2, ...}` (should be 4)
Live in-game: Custodian Guard 2+ vs Power klaw AP -2 displayed `save_needed: 2` in `WoundAllocationOverlay` — screenshot at `audit_07_fight_save_dialog_powerklaw_vs_2plus.png`.

### Per WH40K 10e
Negative AP worsens the save (higher number needed). AP -2 vs Sv 2+ → 4+.

### Fix
`RulesEngine.gd:_calculate_save_needed` (line ~3694): `armour_save = base_save + ap` should be `armour_save = base_save - ap` (since `ap` is stored negative) OR `armour_save = base_save + abs(ap)`. One-line change shared by all four resolver paths (`_resolve_assignment_until_wounds`, `_resolve_assignment`, `_resolve_overwatch_assignment`, `_resolve_melee_assignment`).

### Severity
**Critical**. Single most damaging bug surfaced by the audit — every shoot/fight rolls the wrong save threshold. Tests have been knowingly papering over it.

### Discovered during
2026-05-06 audit fan-out, fight-phase agent (`findings/03_07_fight.md`); core-concepts agent confirmed the duplicated-resolver root cause (`findings/03_02_core.md`).
```

### A1-2. `da_jump_used_this_turn` flag never resets — Weirdboy permanently locked

**Labels:** `bug`, `pri_high`, `MVP`, `unit_data`

```
## `da_jump_used_this_turn` flag leaks across turn boundaries — Weirdboy permanently locked

### Summary
`MovementPhase.gd:2109` sets `unit.flags.da_jump_used_this_turn = true` after a Weirdboy uses Da Jump, but the flag is NOT in either reset list (`ScoringPhase.gd:332-341`, `GameManager.gd:1107-1112`). After one Da Jump use, the Weirdboy cannot use it again for the rest of the game. Affects every Ork roster shipping a Weirdboy.

### Reproduction (live, 2026-05-06)
Drove dispatch_action through MCP across two turn boundaries; flag remained `true` post-scoring/end-of-turn. Re-attempting USE_DA_JUMP returned the rejection.

### Per WH40K 10e
Da Jump is once per turn (Weirdboy psychic ability). It should be available again next turn.

### Fix
Add `da_jump_used_this_turn` to the per-turn reset lists in `ScoringPhase._handle_end_turn` (line ~332) and `GameManager.process_end_scoring` (line ~1107). One-line addition in each.

### Severity
**High**. Active Ork roster has a Weirdboy; the bug crippling-disables a core faction tool after R1.

### Discovered during
2026-05-06 audit, end-of-turn agent (`findings/03_08_end_of_turn.md` row 8). Live-reproduced through 2 turn boundaries.
```

### A1-3. NBSP in detachment names silently drops every Lions stratagem

**Labels:** `bug`, `pri_high`, `MVP`, `unit_data`

```
## NBSP in `Adeptus_Custodes_1995_Mar_7.json` detachment name → exact-string match drops every Lions stratagem

### Summary
The roster JSON `40k/armies/Adeptus_Custodes_1995_Mar_7.json` stores its detachment name `"Lions of the Emperor"` with non-breaking spaces (U+00A0) instead of regular spaces. `FactionStratagemLoader.gd:150` does an exact-string compare against `Detachments.csv` (which uses regular spaces). Every Lions stratagem load is silently dropped.

### Reproduction (live, 2026-05-06)
`execute_script` returns `"Lions of the Emperor" == "Lions of the Emperor"` → `false` (one side has NBSP). Same pattern affects 3 Ork rosters that declare detachment as `"Strike Force"` — not in `Detachments.csv` at all, also silently dropped.

### Per WH40K 10e
Detachments declared in the army list provide stratagems and a detachment ability. Both should resolve regardless of whitespace variants.

### Fix
Two-part:
1. **Data fix:** normalise the NBSP in `Adeptus_Custodes_1995_Mar_7.json` to ASCII space (and audit the other 9 JSONs for similar). Replace the `"Strike Force"` string in 3 Ork rosters with the actual detachment name (`"War Horde"` or whatever was intended).
2. **Code fix:** `FactionStratagemLoader.gd:150` should normalise both sides before compare: `name.replace(" ", " ").strip_edges().to_lower()` on both lookup key and CSV entry.

### Severity
**High** for the affected Custodes roster (entire detachment trick is silent no-op). Plus systemic risk for any future hand-edited roster JSON.

### Discovered during
2026-05-06 audit, enhancements/detachments agent (`findings/04_05_enhancements_detachments.md` §Top divergences #1).
```

### A1-4. DESIGNATE_WARLORD action defined but no UI button — multi-CHARACTER rosters cannot complete Formations

**Labels:** `bug`, `MVP`, `needs_menu`

```
## DESIGNATE_WARLORD action defined but no UI button — multi-CHARACTER rosters cannot complete Formations

### Summary
`FormationsPhase.gd:113, 140, 1117` defines the `DESIGNATE_WARLORD` action (validation handler, processor, available-action list). Grep across `40k/dialogs/` and `40k/scripts/` for `DESIGNATE_WARLORD` returns ZERO matches — the dialog (`FormationsDeclarationDialog.gd`) does not surface the action. Multi-CHARACTER rosters that hit `CONFIRM_FORMATIONS` get rejected with "no Warlord designated" and the player has no way to fix it.

### Reproduction
Load any roster with ≥2 CHARACTER units; advance to FORMATIONS phase; observe no Warlord-selection UI in `FormationsDeclarationDialog`. Attempt CONFIRM_FORMATIONS → rejection with no UI path forward.

### Per WH40K 10e
The army-list-time Formations step requires designating one CHARACTER as Warlord. Mandatory.

### Fix
Add a Warlord-section to `FormationsDeclarationDialog.gd`: list eligible CHARACTER units with a radio-button or single-select dropdown; on selection, dispatch `DESIGNATE_WARLORD` with the chosen `unit_id`. Wire to existing handler at `FormationsPhase.gd:140`.

### Severity
**High** (launch-blocker). The default Custodes and Ork rosters both have multiple CHARACTERS.

### Discovered during
2026-05-06 audit, pre-game agent (`findings/03_01_pregame.md` row 3). Confirmed via grep in TLV-3.
```

### A1-5. MULTIPOTENTIALITY expires `end_of_phase` instead of `end_of_turn`

**Labels:** `bug`, `pri_high`, `MVP`

```
## MULTIPOTENTIALITY expires at end of phase instead of end of turn — Custodes player pays CP for nothing

### Summary
`StratagemManager.gd:782-795` (or nearby — exact line in `findings/04_04_stratagems.md` F5) marks the MULTIPOTENTIALITY effect as expiring `end_of_phase`. Per Wahapedia, the stratagem's effect lasts "until the end of the turn". With end-of-phase expiry, the effect dies before the next phase begins, so a Custodes unit that paid 1 CP in Movement loses the effect before Shooting/Charge.

### Reproduction
USE_STRATAGEM `multipotentiality` on a target unit during P1 Movement; advance to P1 Shooting; check `flags.effect_fall_back_and_shoot` — already cleared.

### Per WH40K 10e
Custodes Shield Host MULTIPOTENTIALITY: "Until the end of the turn, your unit can shoot and declare a charge in your subsequent Shooting and Charge phases this turn even if it Fell Back this turn."

### Fix
Change MULTIPOTENTIALITY's expiry trigger from `end_of_phase` to `end_of_turn` in the stratagem definition (probably in `StratagemManager._load_core_stratagems` or wherever Custodes Shield Host detachment-stratagems are registered).

### Severity
**Medium**. Distinct from #356 (which fixed cannot_shoot override); this is the duration timing bug.

### Discovered during
2026-05-06 audit, stratagems agent (`findings/04_04_stratagems.md` F5).
```

### A1-6. Battle-shock test reads bodyguard's Ld only, never `max(bodyguard_ld, leader_ld)` for attached units

**Labels:** `bug`, `pri_high`, `MVP`

```
## Battle-shock attached-unit Ld test uses bodyguard Ld only — should use `max(bodyguard_ld, leader_ld)`

### Summary
`CommandPhase.gd:697` (in `_handle_battle_shock_test`) and `:789` (in `_resolve_battle_shock_test`) both read:
```
var leadership = unit.get("meta", {}).get("stats", {}).get("leadership", 7)
```
This returns ONLY the bodyguard unit's Ld, regardless of whether a CHARACTER with higher Ld is attached. Per Wahapedia 10e, the test uses "the best Leadership characteristic in that unit". The current behaviour is accidentally correct for AC/Ork rosters (where bodyguard Ld ≥ leader Ld) but wrong for Daemons / Death Guard / Tyranids and for any custom roster.

### Reproduction (live, TLV-5)
- Set `U_CUSTODIAN_GUARD_B.meta.stats.leadership = 5`, `U_BLADE_CHAMPION_A.meta.stats.leadership = 8`
- Attach Blade Champion to Custodian Guard via `CharacterAttachmentManager.attach_character`
- Force half-strength
- Call `_resolve_battle_shock_test("U_CUSTODIAN_GUARD_B", 3, 3)`
- Engine reply: `"Custodian Guard passed battle-shock test (rolled 6 vs Ld 5)"`
- Should have failed (rolled 6 vs Ld 8 — best Ld in unit).

### Per WH40K 10e
"Take that test by rolling 2D6: if the result is greater than or equal to the **best Leadership** characteristic in that unit, the test is passed."

### Fix
At both call sites (lines 697, 789), compute:
```
var leadership = unit.get("meta", {}).get("stats", {}).get("leadership", 7)
for char_id in GameState.get_attached_characters(unit_id):
    var char = GameState.state.units.get(char_id, {})
    var char_ld = char.get("meta", {}).get("stats", {}).get("leadership", 7)
    leadership = mini(leadership, char_ld)  # Ld is "lower is better"
```
(Note: in 10e Ld is "roll ≥ Ld value to pass"; lower Ld values are better, so `min` is the right operator.)

### Severity
**High**. New finding from TLV-5; not in any prior audit.

### Discovered during
2026-05-06 audit, leader-attachment agent (`findings/03_11_leader.md` row "Battle-shock test") + Stage 5a TLV-5 live evidence (`findings/05a_targeted_live_pass.md`).
```

---

## Batch A2 — Every-shoot / every-charge correctness (~1-2 weeks, M effort each)

### A2-1. NEW-S1: BGNT seam — `validate_shoot` rejects MONSTER/VEHICLE in ER even though eligibility allows them

**Labels:** `bug`, `pri_high`, `MVP`, `shooting_phase`

```
## BGNT auto/interactive seam: `validate_shoot` rejects MONSTER/VEHICLE actors firing non-Pistol in ER

### Summary
The shooting eligibility path (`_can_unit_shoot`) correctly exempts MONSTER/VEHICLE units from the in-ER block per the Big Guns Never Tire (BGNT) rule. But `RulesEngine.validate_shoot` at `RulesEngine.gd:3306-3307, 3367-3371` does NOT — it rejects non-Pistol weapon attempts from MONSTER/VEHICLE actors that are in engagement range. Result: the unit appears eligible to shoot but every weapon-pick attempt is rejected.

### Reproduction (live, 2026-05-06)
`execute_script` confirmed: `validate_shoot` returns `valid: false` with reason "Non-Pistol weapon ... cannot be fired while in engagement range" for a VEHICLE/MONSTER actor in ER. The eligibility check passed.

### Per WH40K 10e
"Big Guns Never Tire": MONSTER and VEHICLE units can shoot in ER at -1 BS. They can target the unit they're in ER with or another visible target.

### Fix
`RulesEngine.validate_shoot` should mirror `_can_unit_shoot`'s BGNT check: if actor unit has MONSTER or VEHICLE keyword, skip the in-ER non-Pistol block. The deeper architectural problem is the **four duplicated ~3,300-line resolver pipelines** (`_resolve_assignment_until_wounds`, `_resolve_assignment`, `_resolve_overwatch_assignment`, `_resolve_melee_assignment` + `validate_shoot`) — refactor recommended into a shared `_resolve_attack_sequence` helper. For this issue, the minimal fix is the BGNT branch in `validate_shoot`; the broader refactor can be a follow-up.

### Severity
**High**. Active Ork roster has Battlewagon (VEHICLE), Wazbom Blastajet (VEHICLE/AIRCRAFT); active Custodes has Caladius / Telemon / Contemptor (all VEHICLE). Affects every game where any of these end up in ER.

### Discovered during
2026-05-06 audit, shooting agent (`findings/03_05_shooting.md` NEW-S1). Live-confirmed.
```

### A2-2. NEW-S2: Indirect Fire applies -1 hit / 1-3-fail / cover unconditionally — RAW: only when target invisible

**Labels:** `bug`, `pri_high`, `MVP`, `shooting_phase`

```
## Indirect Fire penalties applied unconditionally — RAW only when target is not visible

### Summary
Indirect Fire weapon handling at `RulesEngine.gd:1605-1609, 9258-9262` (interactive path) and `:2438-2442, 3045-3052` (auto path) applies -1 BS, the "1-3 always fail" rule, and +1 cover to defender — all **unconditionally**. Per Wahapedia 10e, the penalties only apply when the target is not visible to the firing model. Additionally, the **"unmodified 1-3 always fail" rule does not exist in 10e at all** (`RulesEngine.gd:1676-1681, 2510-2515`); the actual rule is just `-1 to Hit` + `Benefit of Cover`.

### Reproduction
Fire any Indirect Fire weapon at a fully-visible target — the engine still applies all penalties as if the target were unseen.

### Per WH40K 10e (Wahapedia, fetched 2026-05-06)
"Indirect Fire" weapon ability:
- When firing at a target that is NOT visible to any model in the firing unit: -1 to Hit + target gets Benefit of Cover
- When firing at a target that IS visible: weapon profile applies normally; no automatic penalties

The 1-3-always-fail rule is NOT in the 10e core rules.

### Fix
1. **Visibility gate:** wrap the -1 BS / +1 cover application in `if not target_visible_to_firing_unit`. Both interactive and auto paths.
2. **Remove the 1-3-always-fail check** at `RulesEngine.gd:1676-1681, 2510-2515` entirely.

Both changes ship together since they affect the same weapon ability.

### Severity
**High**. Affects every artillery / indirect weapon. Plus the 1-3-fail removal will materially change hit rates.

### Discovered during
2026-05-06 audit, shooting agent (`findings/03_05_shooting.md` NEW-S2) + weapon-rules agent (`findings/04_02_weapon_rules.md` divergence #1).
```

### A2-3. Charge-roll modifier primitive missing in `_map_effects` — 'ERE WE GO + 12 stratagems silently rejected

**Labels:** `bug`, `pri_high`, `MVP`, `charge_phase`

```
## `FactionStratagemLoader._map_effects` has no charge-roll modifier branches — 13+ stratagems silently `implemented:false`

### Summary
`FactionStratagemLoader.gd:574-718 _map_effects` parses stratagem effect text into `EffectPrimitivesData` constants. It maps stat-modifiers (PLUS_ONE_HIT, etc.), keyword grants (LETHAL_HITS, etc.), invuln/cover/stealth/FNP, crit thresholds, re-roll hits/wounds/saves, and fall-back-and-shoot/charge. **It does NOT map any charge-roll modifier** — no branch parses "add N to the charge roll", "re-roll the charge roll", "+N to charge", etc. `EffectPrimitives.gd:100-162` has `REROLL_CHARGE` and `ADVANCE_AND_CHARGE` constants but no `PLUS_CHARGE`. As a result 13+ faction stratagems flow through as `custom:unmapped` and load with `implemented:false`.

### Reproduction (live, TLV-7, 2026-05-06)
```
StratagemManager.can_use_stratagem(2, "faction_ork_war_horde_ere_we_go", "U_BOYZ_E")
→ {"can_use": false, "reason": "ERE WE GO is not yet mechanically implemented"}
```
'ERE WE GO is loaded for the active War Horde Ork roster but rejected on attempted use.

### Affected stratagems (active rosters underlined)
**'ERE WE GO +2** (active Ork War Horde), Tide of Muscle +1, Furious Dedication +2, Shock Assault re-roll, Da Big Hunt re-roll, Reavers' Haste +1, From All Sides +1/per friendly, Spreading Madness +2, Hive Sight +1, Stimulated Bio-Surge +1, Refusal to be Outdone +2, Subterranean Assault re-roll, Tireless Fervour re-roll, Divine Imperative +1+re-roll, Portal of Spite +2.

### Per WH40K 10e
Each stratagem above modifies the 2D6 charge roll. Implementations differ in detail (flat +N, re-roll, conditional +N, etc.) but share the underlying primitive: an effect on the charge dice pipeline.

### Fix
Multi-step:
1. Add `PLUS_CHARGE` and `REROLL_CHARGE` to `EffectPrimitivesData` (latter exists; former does not).
2. Add `_map_effects` branches matching "add N to the charge roll" / "re-roll the charge roll" / "add N to your charge roll" patterns. Set `value` to the parsed N.
3. In `ChargePhase._resolve_charge_roll` (line ~635-721), read the unit's `flags.effect_plus_charge` (sum across stacked effects, capped per ±1 modifier rule) and apply to the charge total. Apply re-roll handling similarly.
4. Ship a regression test for each: 'ERE WE GO with deterministic dice should add +2 to the rolled total.

### Severity
**High** (launch-blocker for Ork War Horde). 'ERE WE GO is the central detachment trick.

### Discovered during
2026-05-06 audit, charge-phase agent (`findings/03_06_charge.md` row "Charge-roll modifiers") + Stage 5a TLV-7 (`findings/05a_targeted_live_pass.md`).
```

### A2-4. Lone Operative attachment guard absent from `FormationsPhase._validate_declare_leader_attachment`

**Labels:** `bug`, `pri_high`, `MVP`, `unit_data`

```
## Lone Operative attach guard missing from canonical Formations attachment path

### Summary
`CharacterAttachmentManager.can_attach()` at `40k/autoloads/CharacterAttachmentManager.gd:36-41` rejects Lone Operative attachment with "Lone Operative units cannot attach to a bodyguard". This guard was added in the 2026-05 audit (verified). However, `FormationsPhase._validate_declare_leader_attachment` (lines 153-256) — the canonical 10e army-list-time attachment path — duplicates 7 inline validation checks (CHARACTER keyword, can_lead match, dual-leader, etc.) but **never calls `can_attach()`**. Comprehensive grep: `CharacterAttachmentManager` and `can_attach` return ZERO matches in `FormationsPhase.gd`. Lone Operative CHARACTERS can be attached through Formations, bypassing the 2026-05 fix.

### Reproduction
Construct a synthetic CHARACTER with `meta.abilities=[{name: "Lone Operative"}]` AND `meta.leader_data.can_lead=["BOYZ"]`. Dispatch `DECLARE_LEADER_ATTACHMENT` from FORMATIONS phase with that character → Boyz unit. Expected: rejected. Actual: succeeds (no Lone Op check in this path).

### Per WH40K 10e
Lone Operative units have a self-restriction: they "cannot be attached to a unit". The guard must apply at army list construction (Formations) — not just at the deployment-time `can_attach` callers.

### Fix
In `FormationsPhase._validate_declare_leader_attachment` (lines 153-256), after the existing CHARACTER and leader_data.can_lead checks, add:
```
if RulesEngineData.has_lone_operative(character):
    errors.append("Lone Operative units cannot attach to a bodyguard")
```
Or refactor to delegate to `CharacterAttachmentManager.can_attach` and surface its `reason` field. Refactor is cleaner long-term; the inline check is the surgical fix.

### Severity
**High**. New finding from TLV-3; not in any prior audit. The 2026-05 fix is currently bypassed at the canonical entry point.

### Discovered during
2026-05-06 audit, leader-attachment agent (`findings/03_11_leader.md`) + Stage 5a TLV-3 (`findings/05a_targeted_live_pass.md`).
```

---

## Batch A3 — Every-game scaffolding (~2-3 weeks, M-L effort)

### A3-1. P0 enhancement effect handlers absent — 0 of 16 in-scope enhancements have effects (display-only labels)

**Labels:** `bug`, `pri_high`, `MVP`, `unit_data`

```
## 0 of 16 P0 enhancements have effect handlers in `UnitAbilityManager.ABILITY_EFFECTS`

### Summary
For Custodes Shield Host (4 enhancements) + Ork War Horde (4 enhancements), zero have effect handlers in `UnitAbilityManager.ABILITY_EFFECTS`. The names display in `UnitStatsCardPopup.gd:124-132` as labels but the underlying rule never fires. Only `Freebooter Krew` enhancements are wired today, and that detachment has no roster.

### Affected enhancements (in-scope)
**Custodes Shield Host (4):** Auric Mantle, Castellan's Mark, Hall of Armouries, Panoptispex.
**Ork War Horde (4):** Follow Me Ladz, Headwoppa's Killchoppa, Kunnin' But Brutal, Supa-Cybork Body.

### Per WH40K 10e
Each enhancement adds a specific effect to the bearer (extra wound, +1 attack to a weapon, FNP X+, re-rolls, etc.). Per Wahapedia, the bearer must be a CHARACTER (validated 2026-05) and the cost matches `Enhancements.csv`.

### Fix
For each of the 8 enhancements:
1. Read its rule text from `40k/data/Enhancements.csv`.
2. Add a handler entry to `UnitAbilityManager.ABILITY_EFFECTS` keyed by the enhancement name. Reuse existing primitives where possible (`grant_invuln`, `set_effect_fnp`, `add_to_weapon_attacks`, etc.).
3. Hook the handler into the Stratagem/Effect application pipeline so the bearer's flags reflect the enhancement at battle start.
4. Update `UnitStatsCardPopup.gd:124-132` to show the enhancement's actual effect text (not just the name).

Some enhancements may need new primitives (e.g., Hall of Armouries grants extra weapon options at list-build) — track those as follow-up issues.

### Severity
**Critical** (launch-blocker). Without these, neither Custodes nor Ork rosters can use any enhancement at battle.

### Discovered during
2026-05-06 audit, enhancements/detachments agent (`findings/04_05_enhancements_detachments.md` §Enhancements P0=16).
```

### A3-2. P0 detachment stratagems silently `implemented:false` — 12 of 24 in-scope unreachable

**Labels:** `bug`, `pri_high`, `MVP`, `charge_phase`, `shooting_phase`

```
## 12 of 24 P0 detachment stratagems load with `implemented:false`

### Summary
Of the 24 detachment-specific stratagems available to Shield Host + War Horde rosters, 12 load via FactionStratagemLoader but flow through `_map_effects` as `custom:unmapped` and end up rejected at use-time with "is not yet mechanically implemented". The StratagemPanel shows them as available, the player spends mental budget on them, and the click is silently rejected.

### Affected stratagems (in-scope)
**Custodes Shield Host:** AVENGE THE FALLEN ❌, VIGILANCE ETERNAL ❌, plus existing 🐛 (ARCHEOTECH MUNITIONS — see A5-1, MULTIPOTENTIALITY — see A1-5, UNWAVERING SENTINELS — scope nit).
**Orks War Horde:** MOB RULE ❌🐛 (target-parser inversion at `FactionStratagemLoader.gd:490-491`), 'ERE WE GO ❌ (see A2-3 charge modifier), CAREEN! ❌, ORKS IS NEVER BEATEN ❌.

### Per WH40K 10e
Each stratagem has Wahapedia-defined CP cost, timing window, target restrictions, and effect. All should be playable.

### Fix
For each of the 12, implement the effect:
1. Read the stratagem text from `40k/data/Stratagems.csv` (filter by detachment + faction_id).
2. Where possible, add a parser branch in `_map_effects` for the effect type (e.g., MOB RULE — composite "+1 to Battle-shock test" + "Heroic Stand" effect).
3. Where the effect needs new primitives, add them to `EffectPrimitivesData` and the resolution paths.
4. For MOB RULE specifically: fix the inverted "not Below Half-strength" parser at `FactionStratagemLoader.gd:490-491`.

This issue can be split into 12 sub-issues (one per stratagem) if useful for parallelisation.

### Severity
**Critical** (launch-blocker). 50% of in-scope detachment trickery is non-functional.

### Discovered during
2026-05-06 audit, stratagems agent (`findings/04_04_stratagems.md` §Custodes Shield Host + §Orks War Horde).
```

### A3-3. Da Jump placement validation skips coherency / board / ER / strict-9 — pin test masked the bug

**Labels:** `bug`, `pri_high`, `MVP`

```
## Da Jump placement validation: strict-`<` lets exactly-9.0″ pass, no board/coherency/ER checks

### Summary
`MovementPhase.gd:_process_place_da_jump` (lines 2160-2167) validates each placed model against enemy positions with a single check:
```
if pv.distance_to(ev) < nine_inches_px:
    return reject
```
- Strict `<` accepts exactly 9.0" (per Wahapedia "more than 9″", should reject)
- No board-bounds check — placements off-board are accepted
- No coherency check (single-model unit hides this; multi-model would be a problem)
- No separate engagement-range check (the 9″ check subsumes ER but does not enforce ER-to-ER edge distance)

T-105 was closed in the 2026-05 audit on a pin test (source-grep regression net) — not a live placement test.

### Reproduction (live, TLV-1, 2026-05-06)
1. Set `awaiting_da_jump_placement: true` on `U_WEIRDBOY_J`.
2. Dispatch `PLACE_DA_JUMP` to `(1600, 460)` — exactly 360px = 9.0″ from enemy at `(1600, 100)`. Engine returned `success: true` ❌.
3. Dispatch `PLACE_DA_JUMP` to `(-500, -500)` — clearly off-board. Engine returned `success: true` ❌.

### Per WH40K 10e
Da Jump (Weirdboy psychic): "set up anywhere on the battlefield that is **more than 9"** horizontally away from all enemy units, and not within enemy ER".

### Fix
At `MovementPhase.gd:2160-2167`:
1. Use base-to-base distance, not center-to-center (mirror `_validate_place_reinforcement`).
2. Use `<=` not `<` (or use an explicit "must be more than 9″" comparison).
3. Add board-bounds check against `state.board.size`.
4. Add coherency check across the unit's models.
5. Add separate ER check (1″ horiz, 5″ vert).

Mirror `_validate_place_reinforcement` which already has these checks.

### Severity
**High** (launch-blocker). Active Ork roster fields a Weirdboy.

### Discovered during
2026-05-06 audit, movement agent (`findings/03_04_movement.md` M23) + Stage 5a TLV-1 live evidence (`findings/05a_targeted_live_pass.md`).
```

### A3-4. Deployment alternation always seats P1 first — CA 25-26 says defender deploys first

**Labels:** `bug`, `MVP`, `deployment`

```
## `_handle_deployment_phase_start` hard-codes P1 first — defender role ignored

### Summary
`TurnManager.gd:176-181`:
```
if player1_has_units:
    _set_active_player(1)
elif player2_has_units:
    _set_active_player(2)
```
This always seats Player 1 as the initial deployer. `meta.attacker` and `meta.defender` (written by `RollOffPhase.gd:191-192`) are NEVER read by deployment-alternation code (`check_deployment_alternation`, `_handle_deployment_phase_start`). Per Chapter Approved 2025-26, the **defender** deploys first.

### Reproduction
Set `meta.attacker = 1, meta.defender = 2` after the pre-deployment roll-off; enter DEPLOYMENT; observe `TurnManager.get_current_player_for_deployment()` returns 1 instead of 2.

### Per Chapter Approved 2025-26
After the pre-deployment roll-off determines attacker and defender, the defender selects deployment zone and deploys first.

### Fix
At `TurnManager.gd:_handle_deployment_phase_start`:
```
var defender = GameState.state.get("meta", {}).get("defender", 1)
if _has_undeployed_units(defender):
    _set_active_player(defender)
elif _has_undeployed_units(3 - defender):
    _set_active_player(3 - defender)
```
Plus a separate fix to add a pre-deployment attacker/defender roll-off (currently the only roll-off is post-deployment via `RollOffPhase`). Track that as a follow-up issue if not covered here.

### Severity
**Medium**. Affects every multiplayer game; doesn't crash or corrupt state but mis-sequences the canonical setup flow.

### Discovered during
2026-05-06 audit, pre-game agent (`findings/03_01_pregame.md`) + Stage 5a TLV-4 (`findings/05a_targeted_live_pass.md`).
```

### A3-5. `Datasheets_leader.csv` (1,899 canonical pairings) never consumed — game uses hand-curated `armies/*.json can_lead`

**Labels:** `bug`, `pri_high`, `MVP`, `unit_data`

```
## `Datasheets_leader.csv` never consumed — 1,884/1,899 canonical leader pairings invisible

### Summary
The Wahapedia data download includes `40k/data/Datasheets_leader.csv` (1,899 rows; header `leader_id|attached_id|`) — the canonical (leader → bodyguard) join. Comprehensive grep across `40k/` confirms this CSV is **never loaded by any code path**. The runtime trusts only `meta.leader_data.can_lead` arrays in `40k/armies/*.json`, which are hand-curated. Live-confirmed regressions: Ghazghkull Thraka, Kaptin Badrukk, Nob with Waaagh! Banner, Shield-captain on Dawneagle Jetbike all have `can_lead=[]` in the Ork/Custodes rosters despite canonical pairings; Warboss in Mega Armour `can_lead=["BOYZ"]` should be `["MEGANOBZ"]` per canonical mapping.

### Reproduction (live, 2026-05-06)
`CharacterAttachmentManager.can_attach("U_GHAZGHKULL_THRAKA_A", "<any Boyz unit>")` returns rejection because `can_lead=[]`. Same for Kaptin Badrukk, Nob with Banner, SC Jetbike. ~7 active-roster pairings affected.

### Per WH40K 10e
Each leader's datasheet specifies which bodyguard units it can lead. Wahapedia compiled this into `Datasheets_leader.csv`.

### Fix
1. Load `40k/data/Datasheets_leader.csv` at game startup (similar to `FactionStratagemLoader._init`). Index by `leader_id` → list of `attached_id`s.
2. In `CharacterAttachmentManager.can_attach` and `FormationsPhase._validate_declare_leader_attachment`, prefer the CSV-derived `can_lead` list over `meta.leader_data.can_lead`. Fall back to JSON for units whose `datasheet_id` doesn't match the CSV (some custom units may not be in Wahapedia).
3. Optionally: keep the JSON `can_lead` as an override for non-canonical content, and warn when JSON disagrees with CSV.

### Severity
**High** (launch-blocker). Players who pick canonical Custodes or Ork rosters can't attach the canonical character pairings.

### Discovered during
2026-05-06 audit, leader-attachment agent (`findings/03_11_leader.md` row 1).
```

---

## Batch A4 — Save/load reliability (~1 week, S-M effort)

### A4-1. `MissionManager` runtime state (sticky objectives, kill counters, supply-drop) reset on save/load

**Labels:** `bug`, `pri_high`, `MVP`, `saves`

```
## `MissionManager` 17+ runtime state vars not persisted — sticky objectives reset on every load

### Summary
`MissionManager.gd` declares 17+ gameplay-bearing member vars (`_sticky_objectives`, `_kills_this_round`, `_burned_objectives`, `supply_drop_resolved_round_4`, `_units_alive_at_round_start`, etc.) but has NO `get_state_for_save` / `load_state` API. The autoload is not registered with `SaveLoadManager` for snapshot inclusion. Save → load drops all of this state.

This is the same shape as #338 which PR #347 fixed for `FactionAbilityManager` and `StratagemManager` — that fix was scoped to those two; MissionManager (and others) repeat the pattern.

### Reproduction (live, TLV-8, 2026-05-06)
1. Set `MissionManager._sticky_objectives = {"OBJ_TEST_STICKY": {"player": 2, "source_unit_id": "U_BOYZ_E"}}`.
2. Verified in-memory: `get_sticky_objectives()` → `{"OBJ_TEST_STICKY": {...}}`.
3. `SaveLoadManager.save_game("test")` → `true`.
4. `MissionManager._sticky_objectives.clear()` → verified `{}`.
5. `SaveLoadManager.load_game("test")` → `true`.
6. `get_sticky_objectives()` → `{}` ❌. Sticky entry was lost.

### Per WH40K 10e + game requirements
A sticky objective controlled by a Faction-with-Sticky persists until contested. Mid-game save → load must preserve this.

### Fix
Add `get_state_for_save()` and `load_state(data)` methods to `MissionManager.gd` covering all 17+ runtime vars. Wire into `GameState.create_snapshot()` (around line 1012) and `GameState.load_from_snapshot()` (around line 1174) — same pattern PR #347 used. Pre-trigger fixtures in `40k/saves/*_pretrigger.w40ksave` give regression coverage.

### Severity
**High**. Any mid-game save/load corrupts mission state. Affects every player who saves a game.

### Discovered during
2026-05-06 audit, save/load agent (`findings/03_13_save_load.md` SL-NEW-1) + Stage 5a TLV-8 (`findings/05a_targeted_live_pass.md`).
```

### A4-2. `UnitAbilityManager.get_state_for_save()` exists but is never called — once-per-battle ability locks reset on save/load

**Labels:** `bug`, `pri_high`, `MVP`, `saves`

```
## `UnitAbilityManager.get_state_for_save()` orphan — once-per-battle ability locks reset on save/load

### Summary
`UnitAbilityManager.get_state_for_save()` exists at `:3747-3768` (the API was added) but no caller invokes it. `GameState.create_snapshot()` (around line 979-1037) does NOT include UnitAbilityManager state in the snapshot; `GameState.load_from_snapshot` does NOT restore it. Once-per-battle / once-per-round ability locks (Waaagh!, Plant Banner, Sentinel Storm, Acrobatic Escape, etc.) reset on save/load. Same shape as #338 — UnitAbilityManager was missed by PR #347's scope.

### Reproduction
1. Trigger Waaagh! (Ork once-per-battle).
2. Save game.
3. Load game.
4. Waaagh! is available again — should be locked.

### Per WH40K 10e
Once-per-battle abilities have a battle-long lock. Mid-game save/load must preserve.

### Fix
Add 4 lines to `GameState.create_snapshot` and `GameState.load_from_snapshot` to wire in `UnitAbilityManager.get_state_for_save()` / `.load_state()`. Mirror the existing pattern that was added for FactionAbilityManager and StratagemManager in PR #347 (issue #338).

### Severity
**High**. Affects every game where the player saves after using a once-per-battle ability.

### Discovered during
2026-05-06 audit, save/load agent (`findings/03_13_save_load.md` SL-NEW-3).
```

---

## Batch A5 — Ship gates (~1 week, mixed S/M)

### A5-1. ARCHEOTECH MUNITIONS grants both LETHAL HITS and SUSTAINED HITS — should be either/or

**Labels:** `bug`, `MVP`, `shooting_phase`

```
## ARCHEOTECH MUNITIONS auto-mapper grants both [LETHAL HITS] AND [SUSTAINED HITS 1] — should be either/or

### Summary
`FactionStratagemLoader.gd:621-626` parses ARCHEOTECH MUNITIONS' effect text and grants BOTH `LETHAL_HITS` and `SUSTAINED_HITS` to the target unit, when Wahapedia specifies the player picks ONE. Live-confirmed both flags applied to Contemptor-Achillus when the stratagem fires. Same pattern likely affects other "either/or" stratagems.

### Reproduction
Use ARCHEOTECH MUNITIONS on Contemptor-Achillus; inspect target's flags after USE_STRATAGEM dispatch. Both `effect_lethal_hits = true` and `effect_sustained_hits = true` are set.

### Per WH40K 10e
Custodes Shield Host ARCHEOTECH MUNITIONS: "Until the end of the phase, weapons equipped by models in your unit have either the [LETHAL HITS] ability OR the [SUSTAINED HITS 1] ability — choose which when you select this Stratagem."

### Fix
At `FactionStratagemLoader.gd:621-626`, replace the auto-grant of both with a UI prompt: when ARCHEOTECH MUNITIONS is used, show a choice dialog (Lethal Hits / Sustained Hits 1) and apply only the chosen flag. Pass the chosen flag through the action payload so the StratagemPanel can drive the prompt.

This pattern fix should also be applied to other either/or stratagems detected by similar logic: scan `_map_effects` for any branch that grants multiple keywords from a single text-match.

### Severity
**Medium** (powers up the stratagem beyond RAW; in-scope for Custodes Shield Host).

### Discovered during
2026-05-06 audit, stratagems agent (`findings/04_04_stratagems.md` F3) + enhancements agent (`findings/04_05_enhancements_detachments.md` §Top divergences #2).
```

### A5-2. CP-grant rule diverges from current Wahapedia text

**Labels:** `bug`, `MVP`

```
## CP-grant rule diverges from current Wahapedia: should grant 1 CP to BOTH players each Command phase

### Summary
`CommandPhase.gd:77-85, 148-160` skips CP for the first-turn player on round 1 and only grants CP to the **active player** in their own Command phase. Wahapedia 10e (fetched 2026-05-06) is unambiguous: "**both players gain 1CP**" at the start of every Command phase, no first-turn exception. PR #336 from the 2026-05 audit was based on a stale interpretation.

### Reproduction
Track CP across rounds 1-3:
- Current: P1 starts at 0 CP (round 1 P1 Command); P2 gets +1 in P1 Command? Actually P2 gets 0 in P1's Command — only active player gets CP.
- Per Wahapedia: P1 should gain 1 CP at start of P1 Command, AND P2 should gain 1 CP at start of P1 Command (and again at start of P2 Command). Round 1 first-turn-player exception does not exist in current rules.

### Per WH40K 10e (Wahapedia, fetched 2026-05-06)
"At the start of your Command phase, **both players gain 1CP** (with the per-round cap of 1 CP from any source). The first-turn player exception was removed in earlier dataslate updates."

### Fix
At `CommandPhase.gd:77-85, 148-160`:
1. Remove the round-1 / first-turn-player skip.
2. Grant 1 CP to BOTH players (subject to the per-round `bonus_cp_gained_this_round` cap which is already implemented at `GameState.gd:867-892`).

Update PR #336's fix description with the correction.

### Severity
**Medium**. Affects every game's CP economy.

### Discovered during
2026-05-06 audit, command-phase agent (`findings/03_03_command.md` row 1).
```

### A5-3. Battle-shocked unit cannot shoot — 9e carryover, not in 10e RAW

**Labels:** `bug`, `MVP`, `shooting_phase`

```
## `RulesEngine.validate_shoot` blocks Battle-shocked units from shooting — not in 10e RAW

### Summary
`RulesEngine.gd:3269-3272` rejects any shoot attempt by a Battle-shocked unit with "Unit cannot shoot (battle-shocked)". This is a carryover from `SHOOTING_PHASE_AUDIT.md §2.8` which mis-stated the 10e rule. Wahapedia 10e Battle-shock effects are exactly three: OC=0, all-models Desperate Escape test on Fall Back, and "no Stratagems used by or targeting this unit". Cannot-shoot is not a Battle-shock effect.

### Reproduction (live, 2026-05-06)
Battle-shock any unit; attempt SELECT_SHOOTER → `validate_shoot` returns `valid: false, reason: "Unit cannot shoot (battle-shocked)"`. Engine cascades into `ShootingPhase.gd` and `AIDecisionMaker.gd:6607-6608, 8293-8306`.

### Per WH40K 10e (Wahapedia)
Battle-shocked unit effects:
1. Objective Control becomes 0
2. Cannot perform Stratagems (and stratagems cannot target it)
3. If Falling Back: every model takes a Desperate Escape test (1-3 fail instead of 1-2)

That's it. Shooting is NOT prohibited.

### Fix
1. Remove the `flags.battle_shocked` check from `RulesEngine.validate_shoot` (lines 3269-3272).
2. Audit `ShootingPhase.gd` for any other battle-shocked-blocks-shooting check; remove.
3. Audit `AIDecisionMaker.gd:6607-6608, 8293-8306` and remove the same; the AI should be allowed to shoot with battle-shocked units.

### Severity
**Medium**. Cleanup of an inherited error; in-scope for both factions when their units get Battle-shocked.

### Discovered during
2026-05-06 audit, battle-shock cascade agent (`findings/03_12_battle_shock.md`).
```

### A5-4. Aircraft / Towering wall-LoS exception not honoured — wall fall-back in `EnhancedLineOfSight` ignores keyword exemptions

**Labels:** `bug`, `MVP`, `battlefield`

```
## `EnhancedLineOfSight` wall-LoS fall-back ignores AIRCRAFT / TOWERING exemptions

### Summary
`EnhancedLineOfSight.gd:381-390` post-loop wall fall-back evaluates every Ruin wall against the LoS line regardless of shooter keywords. The polygon-LoS path correctly skips ruins for AIRCRAFT and TOWERING actors, but the wall fall-back does not. Live-confirmed: an AIRCRAFT shooter with `keywords: ["AIRCRAFT"]` returns `has_los: false, blocking_terrain: ["ruins_1_wall"]` even though the rule says it should see over the wall.

### Reproduction (live, 2026-05-06)
`_check_single_line_of_sight((720, 200), (900, 200), [ruins_1], {keywords: ["AIRCRAFT"]})` → `has_los: false, blocking_terrain: ["ruins_1_wall"]`.

### Per WH40K 10e
AIRCRAFT, TOWERING, and FLY-during-Movement units treat Ruin walls as not blocking LoS (with caveats per terrain category).

### Fix
At `EnhancedLineOfSight.gd:381-390` (the wall fall-back loop), check the actor's keywords before treating a wall as blocking:
```
var actor_keywords = ...  # already accessible in scope
if "AIRCRAFT" in actor_keywords or "TOWERING" in actor_keywords:
    continue  # skip this wall as blocker
```

### Severity
**Medium**. Affects every game with an AIRCRAFT or TOWERING shooter (Ork Wazbom Blastajet in active roster).

### Discovered during
2026-05-06 audit, terrain agent (`findings/03_09_terrain.md`).
```

### A5-5. `state.board.terrain` permanently empty — impassable check is a no-op

**Labels:** `bug`, `MVP`, `battlefield`

```
## `state.board.terrain` always empty — impassable-terrain placement check is a permanent no-op

### Summary
`MovementPhase._position_intersects_terrain` (`40k/phases/MovementPhase.gd:6095-6120`) reads `state.board.terrain`. `GameState.gd:39` initialises this as `[]` (empty list). No code path writes to `state.board.terrain` — confirmed via grep. Plus the 8 shipped layouts under `40k/terrain_layouts/` have no `type:"impassable"` pieces. Result: models can be placed inside any terrain polygon during deployment / movement / charge end-position validation.

OA-28/OA-29 ("Clankin' Forward / Stompin' Forward — ignore terrain ≤4″") guard rails are also unreachable for the same reason.

### Reproduction
Drag any model into the middle of a Ruin polygon — placement is accepted.

### Per WH40K 10e
Models cannot end their move on impassable terrain features. Per Pariah Nexus / Chapter Approved layouts, certain pieces (typically large rocks, fortifications) are designated impassable.

### Fix
Two-part:
1. **Code:** `TerrainManager._preload_layout_metadata` should populate `state.board.terrain` from the layout JSON's terrain pieces (or `MovementPhase._position_intersects_terrain` should read from `TerrainManager` directly instead of `state.board.terrain`).
2. **Data:** mark explicitly impassable pieces in the 8 shipped layouts with `type:"impassable"`. Pariah Nexus terrain has tagged impassable; mirror the canonical tags.

### Severity
**Medium**. Affects placement validation across deployment/movement/charge.

### Discovered during
2026-05-06 audit, terrain agent (`findings/03_09_terrain.md`).
```

### A5-6. Big Booms (Battlewagon supa-kannon) `implemented:false` — Battlewagon in active Ork roster

**Labels:** `bug`, `MVP`, `unit_data`

```
## Big Booms ability not implemented — Battlewagon supa-kannon shoot-twice rule unwired

### Summary
The Battlewagon's "Big Booms" datasheet ability (concussive wave / supa-kannon area effect) is registered in `UnitAbilityManager.ABILITY_EFFECTS` with `implemented: false`. The Battlewagon is in the active Ork roster.

### Per WH40K 10e
Battlewagon's "Big Booms" — when it makes a ranged attack with its supa-kannon: the attack inflicts the listed damage AND a secondary blast effect (D6 mortal wounds on the unit, or similar). Wahapedia text TBD verbatim.

### Fix
Implement the ability handler in `UnitAbilityManager`. Add a hook in the shooting attack-pipeline that fires the secondary effect when the supa-kannon profile is used.

### Severity
**Low-Medium** (in-scope but not a critical-path datasheet).

### Discovered during
2026-05-06 audit, abilities agent (`findings/04_01_abilities.md` §B.2 OA-50 open).
```

### A5-7. Waaagh! Energy ('Eadbanger size scaling) `implemented:false` — Weirdboy in active Ork roster

**Labels:** `bug`, `MVP`, `unit_data`

```
## Waaagh! Energy ability not implemented — 'Eadbanger size-scaling effect missing

### Summary
The Weirdboy's "Waaagh! Energy" datasheet ability (the 'Eadbanger psychic attack scales by target unit size) is registered with `implemented: false` in `UnitAbilityManager.ABILITY_EFFECTS`. Weirdboy is in the active Ork roster.

### Per WH40K 10e
Weirdboy's 'Eadbanger ranged attack: damage scales with the target unit's model count. Wahapedia text TBD verbatim.

### Fix
Implement in `UnitAbilityManager`. Hook into the shooting damage pipeline when the 'Eadbanger profile is used.

### Severity
**Low-Medium**.

### Discovered during
2026-05-06 audit, abilities agent (`findings/04_01_abilities.md` §B.2).
```

### A5-8. Daughters of the Abyss FNP-vs-Psychic flag set but never read in damage path

**Labels:** `bug`, `MVP`, `unit_data`

```
## Daughters of the Abyss `effect_fnp_psychic_mortal: 3` flag set but never read by `RulesEngine.get_unit_fnp`

### Summary
Witchseekers (active Custodes roster) have the "Daughters of the Abyss" ability that grants Feel No Pain 3+ against Psychic Attacks and mortal wounds. The flag `effect_fnp_psychic_mortal: 3` is correctly set on the unit. But `RulesEngine.get_unit_fnp_for_attack(unit, true)` only fires for mortal wounds and DW spillover — non-mortal psychic damage NEVER triggers FNP-vs-psychic.

### Per WH40K 10e
"Daughters of the Abyss (Aura): While a friendly Adeptus Custodes unit is within 6\", models in that unit have the Feel No Pain 5+ ability against Psychic Attacks and mortal wounds." (Witchseekers' on-roster value is 3+ via additional aura; verify against Wahapedia.)

### Fix
In `RulesEngine.get_unit_fnp_for_attack` (or wherever the FNP roll is applied), check `flags.effect_fnp_psychic_mortal` against the attack's PSYCHIC keyword. Apply the FNP threshold when the attack is psychic AND the flag is set, even for non-mortal damage.

### Severity
**Medium**. Active Custodes roster fields Witchseekers Alpha + Beta both with this flag.

### Discovered during
2026-05-06 audit, abilities agent (`findings/04_01_abilities.md` §E divergence #1).
```

### A5-9. Witchseekers Scouts ability stored as `name:"Core"` — `_unit_has_scout_own` regex never matches

**Labels:** `bug`, `MVP`, `unit_data`

```
## Witchseekers Scouts ability has `name:"Core"` in roster JSON — Scouts detection regex fails

### Summary
Witchseekers' Scouts ability in the Custodes roster JSON is stored as `{name: "Core", description: "Scouts X..."}` (the `name` field has the literal string `"Core"`, treating it as the ability TYPE rather than the ability NAME). `_unit_has_scout_own` checks `name.to_lower().begins_with("scout")` — never matches. Witchseekers cannot perform Scout pre-game move.

### Per WH40K 10e
Witchseekers Scouts X" allows the unit to make a pre-game move of up to X" before first turn.

### Fix
**Data fix:** in the active Custodes roster JSON, change the Witchseekers ability entry's `name` from `"Core"` to `"Scouts 6\""` (or whatever the canonical Scouts value is). Audit other roster JSONs for similar `name: "Core"` mis-tags.

**Belt-and-suspenders code fix:** in `_unit_has_scout_own`, match against either `name` or `type` field, looking for "Scouts" prefix.

### Severity
**Low** (Witchseekers Scouts is a niche pre-game move). But indicative of broader data-tagging hygiene issues across roster JSONs.

### Discovered during
2026-05-06 audit, abilities agent (`findings/04_01_abilities.md` §E divergence #2).
```

---

## Filing checklist

When ready to file:
- [ ] Confirm `audit_2026_launch` label exists or create it (no `gh label` subcommand; use `gh api repos/.../labels -f name=audit_2026_launch -f color=...` or via web)
- [ ] File issues in batch order (A1-1 through A5-9) so dependencies in body text resolve as expected
- [ ] Tag each with `audit_2026_launch` + the relevant existing label (`bug`, `pri_high`, `MVP`, etc.)
- [ ] Cross-link related issues in their bodies after filing (e.g., A2-1 references the broader resolver refactor)
- [ ] Update `06_SYNTHESIS.md` Path A batches table with the assigned issue numbers

Total: 26 issues across 5 batches; ~6-8 person-weeks engineering.
