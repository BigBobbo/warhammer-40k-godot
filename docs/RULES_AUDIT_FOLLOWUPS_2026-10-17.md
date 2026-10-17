# 11e rules audit — work done 2026-10-17 and what is still open

Continues the zero-context handoff pinned to `a6368a60` (Objective Control,
11e test oracle, charge ceiling, Overwatch timing). Branch
`claude/brave-carson-qbmhbf`. Rule text: `docs/rules/40k_11th_edition_core_rules.txt`.

## Landed

| Area | Change | Evidence |
|---|---|---|
| Test oracle (audit 9.2) | Harness defaults to 11e; 10e only via `WH40K_TEST_EDITION=10` / `-- --edition=10` / scenario `"edition": 10` / test write. Every scenario result records `edition_at_start` + source. | `test_iss002_game_constants` |
| Edition triage | Every test that passed only at 10e was classified (PIN-10 explicit / MIGRATE-11 / BUG-11) against the 11e text and re-checked by a skeptic. No check deleted or weakened. | commit "Triage every test…" |
| CI fail-closed (audit 9.3) | No `\|\| true` / `continue-on-error`; JUnit + per-file known-failure lists that may only shrink (`tests/ci/*`, `tests/scenarios/_known_failures.txt`); audit sharded; jobs decoupled; multi-peer suite runs for the first time; every direct `-s` test runs (`--all`); build job used a non-existent export preset; `loop-prefilter.yml` was invalid YAML. | scenario-suite run on `fb40039` concluded **success** |
| Hang | Secondary deck draw looped forever on a shuffle-back-only deck (froze GUT integration at 11e). | `test_secondary_draw_shuffle_back_terminates` |
| 14.02 Objective Control | Per-model OC sum; group-aware battle-shock; reserves excluded; AI + casualty preference per model. | `test_oc_per_model_14_02` 63/0; `objective_oc_per_model_sum_11e` 64/0 |
| 11.04 charge targets | min(12, roll); Attached unit measured as one unit; HI 15.11 same; UI/AI/network parity. Reverts 0.18.4. | `test_charge_target_within_roll_11e` 123/0; 2 windowed scenarios |
| 15.08/15.07 Overwatch + Rapid Ingress | Once, end of the opponent's Movement phase, non-active player, snap shooting 15.09; RI fixed (was on the Shooting phase); online prompts work. | `test_fire_overwatch_15_08_11e` 140/0; 4 scenarios; two-process MP fo_host 19/19, fo_client 20/20, ri_client 16/16 |
| AI damage oracle (ai-lab D1) | 61 "divergences" were harness artefacts (duel inside ruins + engaged); 10e catalogue was calibrated to them. Two-sided ratchet, sensitivity gate that can fail, profile keys, catalogue regenerated at 11e with isolated causes. | 213 agree / 37 catalogued / 0 new |
| Command-phase reload | Loading/rejoining a game saved in the Command phase re-ran the start-of-turn steps: +1 CP for both players and (11e) 2 more secondary cards per reload. Steps now run once per player turn (`meta.command_start_resolved`); pre-fix saves are stamped on load. | `test_command_phase_start_once` 14/0 (8/14 fail on the unfixed tree) |
| Scenario triage | The 23 windowed scenarios failing only at 11e: 3 PIN-10, 11 MIGRATE-11 (cited), 1 BUG-11 listed, 8 were this reload bug and now pass unmodified. | commit "Triage the windowed scenarios…" |

## Open — 11e engine bugs found by the oracle (tests kept unweakened, listed as known failures)

1. **11.04 "within 1\"" charge obligation not enforced** — `RulesEngine.validate_base_to_base_possible_rules` uses the 2" ER for the 1" bullet. (`test_b2b_rules_standalone_check`, `unit/test_barricade_engagement_range`, `unit/test_base_contact_enforcement`)
2. **11e melee drops attacker +Damage modifiers** (Hall of Armouries, Proper Killy, …) — the 11e branch of `_resolve_melee_assignment` returns before them. (`test_374_enhancement_resolution_398`)
3. **Dice-valued Strength is never rolled** — Zzap gun `S D6+6` wounds as S3 in real games. (D1 catalogue `dice-valued-strength`)
4. **Hold Still mortal wounds skipped on the 11e auto melee path** (suspected). (`unit/test_hold_still_ability`)
5. **FormationsPhase 11e offers a Bodyguard second leader, then rejects it** — AI formations loop stops. (`unit/test_reserves_half_army_cap`)
6. **Legacy `WEAPON_PROFILES` positive AP added to the save at 11e** — test-fixture weapons only. (`test_custodes_lions_silent_hunters`)
7. **Fight pivot cost** (handoff 18.3) — re-probed 2026-10-17: `FightPhase._fight_effective_move_cap` still returns 1.0" (not 3.0") for a rotating 75mm oval MONSTER at 11e. The GUT pivot test was pinned to 10e (movement pivots); no failing 11e test covers the Fight path yet.

## Open — from the work above

- AI estimator gaps (D1 catalogue): TWIN-LINKED not modelled; [ANTI]/[DEVASTATING WOUNDS] maths; `_target_has_benefit_of_cover` is 10e-shaped (13.08 needs every model); no 17.03 −1; RAPID FIRE/MELTA at 0". AI objective thresholds were re-scaled per model but not benchmarked in full games.
- Heroic Intervention: Into the Fray +1CP not charged; target pre-picked before the roll.
- Charge: no AIRCRAFT/FLY filter after the roll; attached CHARACTER can declare alone; re-roll results not mirrored to the client.
- OC: Vexilla +1 baked into the bodyguard's statline; `FLAG_PLUS_OC` on the bodyguard dict misses the leader; sticky objectives tied to the source unit; 40kdc generator emits no per-model OC overrides.
- Overwatch: TORRENT auto-hits during snap shooting (needs a rules call); `movement_phase_end` allows one decision per player; AI `_estimate_overwatch_risk` still models 10e; online Sawbonez/Mekaniak/Grot Oiler prompts still force-complete the phase.
- 11e cover/visibility reads the `TerrainManager` singleton, not the board argument — any simulation must keep both in sync.
- Secondary review dialog: closing it with B/Escape only hides it — `review_completed` never fires and the opponent's pick is auto-resolved.
- Battle-shock: `CommandPhase._units_tested` is phase-local and not saved, so a reload mid-Command phase can offer a unit's test again.
- Hand-built Command-phase fixtures (`custodian_guard_dupes`, `fullauto_pretrigger`: CP 3/3, secondaries uninitialised) now load as saved — they no longer pick up +1 CP on load.
- Test infra: two insane-bravery GUT cases and 4 multi-peer cases are intermittent (`?` in the allowlist); `test_save_load_ai` and `unit/test_reroll_support` hang; fixture `tutorial_t4_shoot` is missing; `army_builder_menu_link` hangs.

## Not started (handoff priorities still open)

Strict 11e army legality (loader still uses the warning-only validator; browser checker accepts illegal lists), attached-unit Leadership and lifecycle, automatic vs interactive allocation parity, Command-phase scoring order, Counter-Offensive sequencing, ingress flag clean-up, universal transport destruction, network Round 5 termination, replay hash coverage, content/mechanics manifest.
