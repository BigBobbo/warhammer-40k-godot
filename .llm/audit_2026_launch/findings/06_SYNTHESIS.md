# Stage 6 — Launch Audit Synthesis (canonical steering document)

**Generated:** 2026-05-06
**Inputs:** all 19 `findings/03_*` and `findings/04_*` files + `05_scorecard.md` + `05a_targeted_live_pass.md`
**Scope override:** Launch = **Adeptus Custodes + Orks** only. Space Marines is OUT OF SCOPE; the other 23 factions are P2 catalog-deferred (counted, not enumerated).
**Evidence tags:** `[L]` live-validated via MCP, `[S]` source-grep + file:line, `[C]` code-only / theoretical.

---

## 1. Launch-blocker shortlist (≤15 items)

Ranked by play frequency (every-turn → every-game → common matchup). Effort: S=≤1 day, M=2-5 days, L=>5 days.

| # | Frequency | Issue | Evidence | File:line | Effort | Finding |
|---|---|---|---|---|---|---|
| 1 | **every shoot/fight** | AP-sign bug: `_calculate_save_needed` does `base_save + ap` with negative AP — improves the save instead of worsening it. Custodian Guard 2+ vs AP-2 returns 2+ (should be 4+). Single fix-point shared by 4 resolver paths. | [L] | `RulesEngine.gd:_calculate_save_needed` (cited in `findings/03_07_fight.md` "Save calculation") | S | `findings/03_07_fight.md`, `findings/03_02_core.md` "Hit/wound/save" |
| 2 | **every shoot** | NEW-S1: `validate_shoot` rejects BGNT MONSTER/VEHICLE actors firing non-Pistol in ER, but eligibility passes them through. Live-confirmed mismatch. | [L] | `findings/03_05_shooting.md` NEW-S1 | M | `findings/03_05_shooting.md` |
| 3 | **every shoot** | NEW-S2: Indirect Fire applies -1 hit, 1-3-fail, and cover unconditionally. RAW: penalties only when target invisible. The "1-3 always fail" rule isn't 10e at all. | [L] | `findings/03_05_shooting.md` NEW-S2; `findings/04_02_weapon_rules.md` divergence #1 | M | `findings/03_05_shooting.md` |
| 4 | **every charge (Orks)** | 'ERE WE GO +2 charge silently rejected: `_map_effects` has no `PLUS_CHARGE` / `REROLL_CHARGE` / `PLUS_N_ATTACKS` primitives. Whole class of effects unimplemented (13+ stratagems). Active Ork roster cannot fire its detachment trick. | [L] TLV-7 | `FactionStratagemLoader.gd:574-718 _map_effects`; `findings/03_06_charge.md` "Charge-roll modifiers" | M | `findings/05a_targeted_live_pass.md` TLV-7 |
| 5 | **every Weirdboy turn** | `da_jump_used_this_turn` flag never resets across turn boundaries — Weirdboy permanently locked after one Da Jump. Active Ork roster. | [L] | `findings/03_08_end_of_turn.md` row 8 | S | `findings/03_08_end_of_turn.md` |
| 6 | **every Da Jump** | Da Jump placement uses center-to-center distance with strict `<`, no board-bounds check, no coherency check, no separate ER check. Off-board placement accepted live. T-105 was closed on a pin test. | [L] TLV-1 | `MovementPhase.gd:2160-2167 _process_place_da_jump` | M | `findings/03_04_movement.md` M23, `05a_targeted_live_pass.md` TLV-1 |
| 7 | **every game (Custodes)** | NBSP in `Adeptus_Custodes_1995_Mar_7.json` detachment name silently drops every Lions stratagem (exact-string match fails). | [L] | `findings/04_05_enhancements_detachments.md` §Top divergences #1 | S (data fix + normaliser) | `findings/04_05_enhancements_detachments.md` |
| 8 | **every game** | 0 / 16 P0 enhancements have effect handlers in `UnitAbilityManager.ABILITY_EFFECTS`. All 8 in-scope (4 Shield Host + 4 War Horde) are display-only labels in `UnitStatsCardPopup`. | [S] | `UnitAbilityManager.ABILITY_EFFECTS`; `findings/04_05_enhancements_detachments.md` §Enhancements P0=16 | L | `findings/04_05_enhancements_detachments.md` |
| 9 | **every game** | 12 of 24 P0 detachment stratagems silently `implemented:false` (load + offer in panel, then reject). In-scope: AVENGE THE FALLEN, VIGILANCE ETERNAL ❌; MOB RULE ❌🐛, 'ERE WE GO ❌, CAREEN! ❌, ORKS IS NEVER BEATEN ❌. | [L] (panel reachable) / [S] (effects unmapped) | `findings/04_04_stratagems.md` §Custodes Shield Host + §Orks War Horde | L | `findings/04_04_stratagems.md` |
| 10 | **every game** | Lone Operative attachment guard absent from `FormationsPhase._validate_declare_leader_attachment` — bypasses the 2026-05 fix at the canonical army-list-time path. **NEW finding (TLV-3).** | [S] thorough source | `FormationsPhase.gd:153-256` (no `CharacterAttachmentManager.can_attach()` call) | S | `findings/05a_targeted_live_pass.md` TLV-3 |
| 11 | **every game (multi-CHARACTER rosters)** | DESIGNATE_WARLORD action defined but no UI button — multi-CHARACTER rosters cannot complete Formations. Players hit "no Warlord" rejection with no path to fix. | [S] grep zero callers | `FormationsPhase.gd:113,140,1117`; zero hits in `40k/dialogs/` or `40k/scripts/` | S | `findings/03_01_pregame.md` row 3, TLV-3 |
| 12 | **every game (deployment)** | Deployment alternation always seats P1 first; CA 25-26 says **defender** deploys first. `meta.attacker / meta.defender` is written by `RollOffPhase` but never read by `_handle_deployment_phase_start`. | [S] thorough source | `TurnManager.gd:176-181`; `RollOffPhase.gd:191-192` (write only) | M | `findings/03_01_pregame.md`, `05a_targeted_live_pass.md` TLV-4 |
| 13 | **every save/load** | `MissionManager` runtime state (sticky objectives, kill counters, supply-drop flag, `_units_alive_at_round_start`, 17+ vars) reset on save/load. No `get_state_for_save` / `load_state` API. **NEW finding (TLV-8).** | [L] TLV-8 | `MissionManager.gd:14-68,143,606`; `SL-NEW-1` | M | `findings/03_13_save_load.md` SL-NEW-1, TLV-8 |
| 14 | **every save/load** | `UnitAbilityManager.get_state_for_save()` exists but is never called — once-per-battle / once-per-round ability locks reset on save/load. Same shape as #338 regression. | [S] grep zero callers | `findings/03_13_save_load.md` SL-NEW-3 | S | `findings/03_13_save_load.md` |
| 15 | **every game** | `Datasheets_leader.csv` (1,899 rows) never consumed; only the curated `armies/*.json can_lead` lists work. Live-confirmed Ghazghkull / Kaptin Badrukk / Nob with Banner all `can_lead=[]` despite canonical pairings. | [L] | `findings/03_11_leader.md` row 1 | M | `findings/03_11_leader.md` |

---

## 2. Invisible-feature top 15

Engine implements; player can't reach. From `05_scorecard.md` Table 4 (top 25 → top 15 in-scope frequency-ranked).

1. `DESIGNATE_WARLORD` action has no UI button — `findings/03_01_pregame.md` row 3 (also #11 above).
2. `Datasheets_leader.csv` never consumed — `findings/03_11_leader.md` row 1 (#15 above).
3. `UnitAbilityManager.get_state_for_save()` orphan — `findings/03_13_save_load.md` SL-NEW-3 (#14 above).
4. `MissionManager` runtime state not persisted — `findings/03_13_save_load.md` SL-NEW-1 (#13 above).
5. 9 of 10 "end of opponent's turn" datasheet abilities unwired (only Acrobatic Escape fires; From Golden Light is in active Custodes roster) — `findings/03_08_end_of_turn.md` row 12.
6. **Big Booms** (Battlewagon supa-kannon concussive wave) `implemented:false` despite Battlewagon in roster — `findings/04_01_abilities.md` §B.2 OA-50.
7. **Waaagh! Energy** ('Eadbanger size scaling) `implemented:false` despite Weirdboy in roster — `findings/04_01_abilities.md` §B.2.
8. **Daughters of the Abyss** FNP-vs-Psychic flag set but never read in `RulesEngine.get_unit_fnp` (Witchseekers/Prosecutors active) — `findings/04_01_abilities.md` §E divergence #1.
9. **Witchseekers Scouts** ability stored as `name:"Core"`; `_unit_has_scout_own` regex never matches (data fix) — `findings/04_01_abilities.md` §E divergence #2.
10. `get_proactive_stratagems_for_phase` orphan — defined in `StratagemManager.gd:2189`, zero callers; UNBRIDLED CARNAGE / ARCHEOTECH / UNWAVERING never auto-offered — `findings/04_04_stratagems.md` F7.
11. `get_available_stratagems_for_trigger` orphan — `StratagemManager.gd:811-856` zero callers — `findings/04_04_stratagems.md` F8.
12. StratagemPanel doesn't gate by phase/trigger — accepts `phase_id` only for the title; SMOKESCREEN fireable in SCORING phase live-confirmed — `findings/04_04_stratagems.md` F1.
13. Combat Squads / Patrol Squad UI prompt missing — `GameState.split_unit_at_deployment` exists, no Deployment-phase UI — `findings/04_01_abilities.md` §D, T-026.
14. Mixed-save defender choice not surfaced — `_calculate_save_needed` auto-picks better save; defender cannot deliberately fail — `findings/03_02_core.md` §invisible features.
15. Fight-phase has zero weapon-keyword icons — Twin-linked, Lethal Hits, Sustained Hits, Anti-X, Devastating Wounds, Precision, Hazardous, Lance, Extra Attacks invisible during melee — `findings/04_02_weapon_rules.md` §Top 10.

---

## 3. Divergence top 10 (🐛 silent wrong-rule)

Most dangerous: tests pass; engine fires the wrong rule. From `05_scorecard.md` Table 5 (top 25 → top 10 in-scope frequency-ranked).

1. **AP-sign in `_calculate_save_needed`** — improves saves under negative AP. Live, `findings/03_07_fight.md` (#1 above).
2. **NEW-S1 BGNT seam** — eligibility allows, validation rejects. Live, `findings/03_05_shooting.md` NEW-S1 (#2 above).
3. **Indirect Fire unconditional penalties** + 10e-non-existent 1-3-always-fail rule. Live, `findings/03_05_shooting.md` NEW-S2 / `findings/04_02_weapon_rules.md` (#3 above).
4. **NBSP detachment-name drop** — Lions roster loads zero stratagems. Live, `findings/04_05_enhancements_detachments.md` (#7 above).
5. **ARCHEOTECH MUNITIONS grants both LETHAL HITS and SUSTAINED HITS** — Wahapedia is "either / or"; live-confirmed both flags applied to Contemptor-Achillus. `findings/04_04_stratagems.md` F3.
6. **MULTIPOTENTIALITY expires `end_of_phase`** instead of `end_of_turn` — Custodes player pays 1 CP for nothing. `findings/04_04_stratagems.md` F5.
7. **CP-grant rule diverges from Wahapedia** — code skips first-Command-phase CP for first-turn player and never grants opponent in your Command phase. `findings/03_03_command.md` row 1.
8. **Battle-shock test uses bodyguard Ld only**, never `max(bodyguard_ld, leader_ld)` — accidentally correct for AC/Ork rosters today, wrong RAW. Live TLV-5, `findings/03_11_leader.md`.
9. **Battle-shocked unit cannot shoot** — Wahapedia 10e BS list is exactly 3 effects (OC=0, Desperate Escape, no Stratagems); cannot-shoot is a `SHOOTING_PHASE_AUDIT.md §2.8` carryover. Live, `findings/03_12_battle_shock.md`.
10. **Aircraft / Towering wall-LoS exception not honoured** — wall fall-back at `EnhancedLineOfSight.gd:381-390` ignores Aircraft/Towering exemptions; `state.board.terrain` permanently empty so impassable check is a no-op. Live, `findings/03_09_terrain.md`.

---

## 4. Data gaps top 10

Roster ↔ engine mismatches; rules referenced by data but engine has no handler (or vice versa).

1. **16 of 19 Wahapedia CSVs unloaded** — `Datasheets`, weapon profiles, abilities, keywords, enhancements all source from `armies/*.json` not the canonical CSV. `findings/01_inventory.md` §1.3.
2. **`Datasheets_leader.csv` ignored** — 1,884 / 1,899 canonical leader pairings invisible. `findings/03_11_leader.md` row 1.
3. **`Strike Force` is not a real detachment** — 3 Ork rosters declare it; loader silently drops every War Horde stratagem. `findings/04_06_factions.md`.
4. **`_map_effects` silently downgrades unmapped effects** to `custom:unmapped` and marks `implemented:false` — 12 of 24 P0 detachment stratagems hit this path. `findings/04_04_stratagems.md` §Counts.
5. **Roster JSONs ~38 % out-of-sync with canonical points** — Telemon 265 vs 225, Custodian Guard 170 vs 160, Kaptin Badrukk 100 vs 80 + invented weapons. `findings/04_06_factions.md` §3.
6. **Caladius/Telemon/Contemptor missing invuln in roster stats** — invuln_save absent in meta.stats. `findings/04_06_factions.md`.
7. **Witchseekers Scouts ability stored as `name:"Core"`** — `_unit_has_scout_own` regex never matches. `findings/04_01_abilities.md` §E.
8. **Ghazghkull missing MAKARI model line**; Kaptin Badrukk roster invents weapons. `findings/04_06_factions.md` §3.
9. **`recommended_deployments` metadata loaded but never displayed** in MainMenu. `findings/03_09_terrain.md`.
10. **`state.board.terrain` permanently empty** — impassable-terrain placement check + OA-28/OA-29 ignore-terrain-≤4″ guards both no-ops because the source list never populates. `findings/03_09_terrain.md`.

---

## 5. 9e carryovers (verified with Wahapedia URL)

The 2026-05 audit closed most. This audit found **only one ambiguous carryover** plus **one rule-text carryover**:

1. **❓ ambiguous: `Objective Secured`** as Datasheet ability on Intercessor Squad in `space_marines.json` (`U_INTERCESSORS_A`) — 10e Intercessors do not have an OS datasheet ability. SM is **out of scope** for launch; defer. `findings/04_06_factions.md` §3.
2. **🐛 confirmed: "battle-shocked unit cannot shoot"** — Wahapedia 10e BS list is exactly 3 effects (OC=0, Desperate Escape, no Stratagems). The cannot-shoot rule is a `SHOOTING_PHASE_AUDIT.md §2.8` carryover. Live-confirmed. `findings/03_12_battle_shock.md` (also div #9 above).

**Cover-cap dispute (3+ save vs AP 0 in cover) is RESOLVED** — see Memory updates below. Current code is RAW-correct (TLV-6 evidence). The 2026-05 audit memo entry "should only apply to INFANTRY/SWARM/BEAST" is itself the wrong reading; the keyword-gated form is the 9e rule.

---

## 6. Per-phase scorecard table

From `05_scorecard.md` Table 2 — verbatim, 13 rows.

| Phase | Rules | ✅ % | ⚠️ % | ❌ % | 🐛 % | Top gap | Top invisible feature |
|---|---:|---:|---:|---:|---:|---|---|
| 03_01 Pre-game | 26 | 65 | 12 | 12 | 4 | No pre-deployment attacker/defender roll-off; deployment alternation always P1 | DESIGNATE_WARLORD action exists but no UI button |
| 03_02 Core | 33 | 67 | 9 | 0 | 12 | AP-sign bug in `_calculate_save_needed` (live) | `_apply_damage_to_unit:9103` 50-line dead helper |
| 03_03 Command | 23 | 78 | 9 | 9 | 4 | CP-grant rule diverges from Wahapedia | Infiltrator Comms Array `regain_cp_on_5plus` zero callers |
| 03_04 Movement | 40 | 70 | 8 | 13 | 10 | AIRCRAFT min-move 20″ + Hover not enforced (Wazbom) | Da Jump placement skips coherency / board / ER / strict-9 |
| 03_05 Shooting | 36 | 78 | 8 | 0 | 11 | NEW-S1 BGNT seam (live) | Wound-modifier flag wired but no UI |
| 03_06 Charge | 33 | 73 | 12 | 9 | 6 | Charge-roll modifiers not wired ('ERE WE GO et al) | StratagemPanel surfaces `implemented:false` |
| 03_07 Fight | 26 | 81 | 8 | 0 | 11 | AP-sign bug (shared) | Fights Last subphase no UI banner |
| 03_08 End of Turn | 25 | 76 | 4 | 12 | 8 | `da_jump_used_this_turn` never resets (live) | 9 of 10 "end of opp turn" abilities unwired |
| 03_09 Terrain | 33 | 64 | 9 | 12 | 15 | Aircraft / Towering wall-LoS not honoured + `state.board.terrain` empty | 4 divergent LoS calculators |
| 03_10 Objectives | 47 | 70 | 9 | 11 | 11 | Tipping Point deployment missing; Hidden Supplies stub falls through | Ritual / Terraform actions selectable, no UI |
| 03_11 Leader | 23 | 65 | 13 | 13 | 9 | `Datasheets_leader.csv` never consumed | Battle-shock Ld test bodyguard-only |
| 03_12 Battle Shock | 22 | 73 | 5 | 14 | 9 | `validate_shoot` blocks BS unit (10e doesn't) | "No Actions while BS" unenforced |
| 03_13 Save / Load | 14 | 71 | 7 | 14 | 7 | MissionManager runtime state not persisted | `UnitAbilityManager.get_state_for_save` orphan |

---

## 7. Per-faction launch-readiness table

In-scope detail; out-of-scope summarised.

| Faction | Verdict | Detail |
|---|---|---|
| **Adeptus Custodes** | NEEDS WORK | 4 rosters, 16/31 datasheets (52%); 2 detachments (Shield Host, Lions); 1 partial (Shield Host); 3✅/6 stratagems (ARCHEOTECH🐛, UNWAVERING⚠️, MULTIPOTENTIALITY🐛, AVENGE❌, VIGILANCE❌); **0✅/4 enhancements**; Lions roster blocked by NBSP; Caladius/Telemon/Contemptor missing invuln; Telemon over-priced 265 vs 225; Daughters-of-the-Abyss FNP-flag never read |
| **Orks** | NEEDS WORK | 5 rosters, 27/87 datasheets (31%); 2 detachments (War Horde + fake Strike Force); 1 partial (War Horde); 2✅/6 stratagems (MOB RULE🐛❌, 'ERE WE GO❌, CAREEN!❌, ORKS IS NEVER BEATEN❌); **0✅/4 enhancements**; `da_jump_used_this_turn` leaks; Strike Force fake-detachment in 3 rosters drops every stratagem; Wazbom AIRCRAFT min-move/Hover unenforced; Big Booms + Waaagh! Energy `implemented:false`; Ghazghkull/Kaptin Badrukk/Nob-with-Banner all `can_lead=[]` |
| Space Marines | OUT OF SCOPE | excluded per launch scope override |
| 23 catalog-only factions (CSM, Aeldari, Necrons, Tyranids, AM, AdM, T'au, GK, AS, etc.) | NOT STARTED | No roster JSON; no army-builder UI; ~258 of 261 detachments have no `DETACHMENT_ABILITIES` entry; 16/19 CSVs unloaded; faction army-rules absent (`Synapse`, `Reanimation Protocols`, `Battle Focus`, `Acts of Faith`, `Dark Pacts`, `Doctrina Imperatives`, etc.) |

**Headline:** **0/26** factions meet the strict bar. **2/26** are NEEDS WORK (Custodes + Orks). **24/26** NOT STARTED (incl. SM).

---

## 8. Recommended sequencing

### Path A — Polish 2 factions (Custodes + Orks) to ship-quality
**Smallest scope. Recommended for fastest launchable product. Filed as GitHub issues #364-#389 on 2026-05-06.**

Sequence as ordered batches; each batch is parallelisable internally.

**Batch A1 — every-turn correctness fixes (S, ~1 week):** #364 (AP-sign), #365 (da_jump reset), #366 (NBSP normaliser), #367 (DESIGNATE_WARLORD UI button), #368 (MULTIPOTENTIALITY end-of-turn), #369 (Battle-shock max-Ld). All trivial code edits.

**Batch A2 — every-shoot / every-charge correctness (M, ~1-2 weeks):** #370 (BGNT seam), #371 (Indirect Fire visibility gate), #372 (charge-roll modifier primitive — unblocks 'ERE WE GO + 12 other faction stratagems), #373 (FormationsPhase Lone Op guard).

**Batch A3 — every-game scaffolding (M-L, ~2-3 weeks):** #374 (P0 enhancement handlers, 0/16), #375 (12 P0 detachment stratagems), #376 (Da Jump bounds), #377 (deployment defender-first), #378 (Datasheets_leader.csv consumer).

**Batch A4 — save/load reliability (S-M, ~1 week):** #379 (MissionManager save API), #380 (UnitAbilityManager wiring) — both copy the #338 pattern from PR #347.

**Batch A5 — ship gates (~1 week):** #381 (ARCHEOTECH either/or), #382 (CP-grant rule), #383 (cannot-shoot carryover), #384 (Aircraft/Towering wall-LoS), #385 (state.board.terrain populator), #386 (Big Booms), #387 (Waaagh! Energy), #388 (Daughters FNP), #389 (Witchseekers Scouts data tag).

**Total Path A:** ~6-8 person-weeks across 26 issues. Endpoint: 2/2 in-scope factions reach the strict bar; both Shield Host and War Horde detachments at "launchable" with full enhancement + stratagem coverage. Filing detail at `.llm/audit_2026_launch/filed_issues.md`.

### Path B — Add a 3rd faction (excluding SM)
**SM is out of scope; pick the closest-to-ready non-playable faction.**

Per `findings/04_06_factions.md` §4, every catalog-only faction is at 0% roster coverage; the differentiator is **detachment-rule complexity**. Lowest-friction candidates:

- **Tyranids** — `Synapse` re-uses Battle-shock immunity (existing primitive). Estimate ~12-15 days for one detachment (`Invasion Fleet`), 10-15 datasheets, 6 stratagems, 4 enhancements, ~30 ability handlers.
- **Astra Militarum** — `Voice of Command` issues orders to BATTLELINE; needs new order-routing autoload but no novel dice mechanic. ~14-18 days.
- **Adepta Sororitas** — `Acts of Faith` / Miracle Dice needs a new dice-pool autoload. Heavier. ~18-22 days.

**Recommendation if Path B chosen:** Tyranids. Ship Custodes + Orks + Tyranids on the Stage 8 audit endpoint after ~10 weeks total (Path A 6-8 weeks + Tyranids 2-3 weeks once cross-cutting plumbing lands).

### Path C — Full 26-faction launch
**24 unplayable factions, sorted by estimated effort to add one detachment each.**

| Tier | Factions | Per-faction days | Notes |
|---|---|---|---|
| Easy (re-uses existing primitives) | Tyranids, AM, Genestealer Cults, Imperial Agents, Unaligned, Adeptus Titanicus, Unbound Adversaries | 12-15 | Synapse / Voice of Command / inheritable ordering |
| Medium | T'au, Death Guard, Thousand Sons, Emperor's Children, Chaos Knights, Imperial Knights, Grey Knights | 15-20 | For the Greater Good, Contagions, Cabal Points, Code Chivalric, single-model-army rules |
| Heavy (novel autoload required) | Necrons, Aeldari, Drukhari, Adepta Sororitas, Adeptus Mechanicus, World Eaters, CSM, Leagues of Votann, Chaos Daemons | 20-30 | Reanimation Protocols, Strands of Fate dice-pool, Power From Pain, Acts of Faith / Miracle Dice, Doctrina Imperatives, Blood Tithe, Dark Pacts, Judgement Tokens, Shadow of Chaos |

**Headline (Path C): 1.5-3 person-years** to take launchability from 2/26 (post-Path-A) to 26/26. Plus engine plumbing (~1.5 person-months for 12 cross-cutting items + in-app army-builder UI) before per-faction work scales. See `05_scorecard.md` §"What it would take to ship every faction". Also requires Wahapedia CSV ingestion (~2 weeks) and tournament-pack closure (~2-3 weeks).

---

## 9. Confidence note

- **~30 % of in-scope claims are depth-`L`** (live-validated through MCP this audit pass or by 2026-05 audit fixtures); **~70 % are depth-`W`** (code-grep + cross-reference).
- **9 fan-out items + 4 promoted-to-live TLV items = 13 evidence-grade findings** drove the launch-blocker shortlist.
  - Fan-out live (9): AP-sign, BGNT seam, Indirect Fire mis-application, NBSP detachment-name drop, GRENADE 8″ check, ARCHEOTECH double-keyword, StratagemPanel phase-gating, `da_jump_used_this_turn` flag leak, MultiPotentiality expiry mismatch.
  - Promoted-to-live in TLV pass (4): Da Jump placement bounds (TLV-1), Battle-shock attached-Ld (TLV-5), 'ERE WE GO charge modifier (TLV-7), MissionManager save/load sticky (TLV-8).
  - Resolved by TLV pass (1): Cover-cap scope dispute (TLV-6) — current code is RAW-correct.
  - Thorough source-grep no screenshot (3 of TLV's 8): Heroic Intervention timing (TLV-2), Formations Lone Op + Warlord UI (TLV-3), Deployment defender-first (TLV-4) — `file:line` proof equivalent to live.
- **Residual risk:** depth-`W` claims for catalog-only factions (Path C) are not exercised against any roster; novel-mechanic effort estimates carry ±50 % variance. The 12 cross-cutting items in Batch A2/A3 may surface deeper refactors when touched (the four duplicated ~3,300-line hit→wound→save pipelines in particular — `findings/03_05_shooting.md` NEW-S3).

---

## 10. Open questions for project lead

1. **Launch scope confirmation:** Path A (2 factions) vs Path B (3 factions, +Tyranids) vs Path C (26 factions). The audit's recommendation is **Path A** — fastest path to a launchable product; Path B only after Path A lands.
2. **Mission pack to encode as canonical:** Leviathan / Pariah Nexus / Chapter Approved 2026? Tipping Point deployment, Hidden Supplies, Burden of Trust, and Battle Ready Army painting bonus all map to specific packs. `findings/03_10_objectives.md` rules 14, 15, 17, 39, 40.
3. **Boarding Actions** in-scope or deferred? 58 of 261 detachments are Boarding-only; current audit assumes deferred.
4. **Catalog-only data fate:** keep `40k/data/*.csv` as future-work spec (audit position), or remove the unloaded 16 CSVs to reduce repo confusion? Pipeline rebuild is ~2 weeks engineering when re-prioritised.
5. **In-app army-builder UI:** required for any path beyond hand-curated JSON rosters. Estimate ~2-3 weeks; gates Path B/C entirely. Path A can ship without it (existing JSONs sufficient for Custodes + Orks).
6. **Roster points-data drift:** Telemon 265 vs 225, Custodian Guard 170 vs 160, Kaptin Badrukk 100 vs 80 — ship as-is (data fix), or hold for Munitorum Field Manual sync (~1 day)?
7. **Datasheets_leader.csv consumer:** ship Path A with the current curated `can_lead` lists (accidentally correct for AC + Ork rosters), or land the CSV consumer (Batch A3, ~3-5 days) to unblock cross-faction parity? Required for Path B/C; optional for Path A.

---

## Memory updates (REQUIRED)

The following audit-memory entries must be reconciled before any further audit work:

1. **REVERSE the 2026-05 audit memo entry:** "Cover save 3+ cap is universal — should only apply to INFANTRY/SWARM/BEAST — FIXED 2026-05-04". This entry is **wrong**. TLV-6 evidence: third-party `datacard.app/40k` quotes the 10e rule verbatim with no keyword restriction; math drive across all five keyword sets (VEHICLE, INFANTRY, MONSTER, BEAST, MOUNTED) returns the same universal cap; commit `6958cff` (2026-05-05) is the **corrective** patch, not a regression. Three sub-agents (`findings/03_02_core.md` row 41, `findings/03_05_shooting.md` NEW-S7, `findings/04_03_keywords.md` divergence #1) flagged the universal form as 🐛; that flag is itself wrong. The Wahapedia core-rules page truncates at the BoC section for all four sub-agents — that's why the conflict happened. `findings/03_09_terrain.md` row "Benefit of Cover 3+ cap" had it correct.

2. **NEW launch-blocker (not in any prior audit):** Lone Operative attachment guard absent from `FormationsPhase._validate_declare_leader_attachment` — the canonical 10e army-list-time path bypasses `CharacterAttachmentManager.can_attach()`. Fixed at the deployment path (`DeploymentController.gd:1153`) and inside `attach_character` (`CharacterAttachmentManager.gd:77,163`) but **not** at the Formations-phase declaration (`FormationsPhase.gd:153-256`). Item #10 in §1 above. **TLV-3 evidence-grade.**

3. **NEW launch-blocker (not in any prior audit):** `MissionManager` runtime state (sticky objectives, kill counters, supply-drop flag, `_units_alive_at_round_start`, 17+ vars) reset on save/load. No `get_state_for_save` / `load_state` API. Same pattern as #338 fixed for `FactionAbilityManager` and `StratagemManager`. Item #13 in §1 above. **TLV-8 evidence-grade.**

4. **Confirm:** `da_jump_used_this_turn` flag leaks across turns (live across 2 turn boundaries — Weirdboy permanently locked after one Da Jump). Item #5 in §1.

5. **Confirm:** Battle-shock attached-unit Ld test reads bodyguard Ld only (live: 6 vs Ld 5 instead of 6 vs Ld 8 with attached Blade Champion). Trivial fix at `CommandPhase.gd:697, 789` to use `max(bodyguard_ld, attached_leader_ld)`.

---

**End of synthesis. Audit Stage 6 complete; project lead converts §1, §2, §3, §4 + memory updates into GitHub issues per the 2026-05 audit pattern (#319-#348).**
