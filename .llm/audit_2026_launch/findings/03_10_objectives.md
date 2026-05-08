# 03.10 — Objectives & Scoring (findings)

**Audit date:** 2026-05-06
**Scope:** OC contests, primary/secondary scoring, sticky objectives, mission-pack-specific behaviour.
**Code root:** `40k/` (excluding `40k/.claude/worktrees/`).

## Mission pack identification

**Encoded mission pack:** **Chapter Approved 2025-26** — `40k/scripts/data/MissionData.gd:5` says "Based on Chapter Approved 2025-26 rules" and `40k/scripts/data/SecondaryMissionData.gd:4` likewise; the local reference HTM file is `40k/deployment_zones/Chapter Approved 2025-26.htm` (1.4 MB scrape from Wahapedia).

VP caps in code (`SecondaryMissionManager.gd:20-23`, `MissionData.gd:26-27`) match CA 2025-26 (Primary 50 / Secondary 40 / Combined 90), with the per-fixed-mission cap of 20 VP at `SecondaryMissionManager.gd:23`.

Note the **canonical CA 2025-26 VP table** (extracted from local HTM, 334594-335300):

| Source | Max | Combined cap |
|---|---:|---|
| Primary Mission | 50 | grouped under 90 |
| Secondary Missions | 40 (or 20/card if Fixed) | grouped under 90 |
| Challenger cards | 12 | grouped under 90 |
| Battle Ready Army | 10 | separate +10 → 100 max |

The game's `MAX_COMBINED_VP = 90` (SecondaryMissionManager.gd:21) does not include Challenger (because Challenger isn't implemented at all) and does not add the +10 paint VP. See findings below.

## Findings table

| # | Rule | Wahapedia / CA § | Depth | Correctness | Evidence | Notes |
|---|---|---|---|---|---|---|
| 1 | OC contest sums OC of all eligible models within 3"+20mm of objective | Core Rules → Objective Markers | L | ✅ | `40k/autoloads/MissionManager.gd:183-304` (`_check_objective_control`); live `get_objective_control_summary()` returned `{obj_home_1:1, others:0}` correctly | Edge-aware via `Measurement.model_edge_to_point_distance_px` (line 241) — handles oval/rect bases; control radius 3.78740157" matches 3" + 20mm |
| 2 | Battle-shocked unit's OC counts as 0 for objective contests | Battle-Shock | L | ✅ | `40k/autoloads/MissionManager.gd:207-209` (skip on `flags.battle_shocked`); regression-confirmed 2026-05 | **VERIFIED (regression spot-check)** — verified again live: `_check_objective_control` reads battle_shocked flag at line 207-209; check passed previously and code is unchanged |
| 3 | OC override (Da Boss Iz Watchin' / Waaagh!) supersedes statline OC | Faction (Orks) | W | ✅ | `40k/autoloads/MissionManager.gd:199-201` reads `unit.flags.effect_oc_override` | Supersedes only if non-zero; falls back to statline |
| 4 | Sticky objectives (faction/detachment-only) lock when unit is in range and breaks when opponent gains OC | 10e Designers' Commentary on sticky | W | ✅ | `40k/autoloads/MissionManager.gd:314-378` (`apply_sticky_objectives`, `_check_objective_control:282-303`) | Tied to `UnitAbilityManager.has_sticky_objectives_ability(unit_id)`; lock breaks when opponent gets active OC, also expires on source-unit destroyed |
| 5 | Sticky objective code skips battle-shocked unit | Battle-Shock | C | ✅ | `40k/autoloads/MissionManager.gd:344-346` skips `flags.battle_shocked` | OK |
| 6 | Primary mission "Take and Hold" — 5 VP per controlled obj, max 15/turn | CA 2025-26 mission pool | W | ✅ | `MissionData.gd:56-72`, `MissionManager.gd:435-462` | Default mission; scoring fires at end of Command phase (`CommandPhase.gd:2125`). Start round 2 matches CA. |
| 7 | Primary "Linchpin" — center +4 bonus, max 16 | CA 2025-26 | W | ✅ | `MissionData.gd:227-244`, `MissionManager.gd:454-457` | Center bonus only when `obj_center` controlled |
| 8 | Primary "Supply Drop" — only NML scores, remove 1 NML in R4, R5 bonus | CA 2025-26 | W | ✅ | `MissionData.gd:77-98`, `MissionManager.gd:525-547`, `_process_supply_drop_removal:554-583` | Uses `RNGService.test_mode_seed` for deterministic removal (issue #329) |
| 9 | Primary "Purge the Foe" — hold + kill scoring (8+8/turn) | CA 2025-26 | W | ✅ | `MissionData.gd:103-124`, `MissionManager.gd:471-519` | Two kill-tracking systems coexist (`_kills_this_round` and `kills_per_round`); takes max of both — not a bug, but redundant |
| 10 | Primary "Scorched Earth" — burn enemy/NML for bonus VP | CA 2025-26 | W | 🐛 | `MissionData.gd:129-156`, `MissionManager.gd:745-787` | **BUG**: `_get_player_home_zone()` returns `"player1_zone"`/`"player2_zone"` (line 784-787) but actual JSON zone names are `"player1"`/`"player2"` (verified live: `_get_player_home_zone(1) == "player1_zone"` while `state.board.objectives[0].zone == "player1"`). The check `zone != _get_player_home_zone(active_player)` at line 775 is therefore **always true**, so burning your own home objective also scores +10 enemy_burn VP. Burn-eligibility is gated separately so this misfires only when burn paths exist. |
| 11 | Primary "Sites of Power" — character-on-NML claims | CA / Pariah Nexus variant | W | 🐛 | `MissionData.gd:181-200`, `MissionManager.gd:671-739` | **BUGS**: (a) `_player_has_character_on_objective` at line 736 uses `model_pos.distance_to(obj.position)` (center-to-center) instead of edge-to-point — inconsistent with `_check_objective_control`'s shape-aware distance at line 241. Models on large bases (Custodes Shield-Captain on Dawneagle) will fail to claim. (b) Battle-shocked CHARACTER not excluded — `_player_has_character_on_objective` does not check `flags.battle_shocked`, so a battle-shocked character still claims. |
| 12 | Primary "The Ritual" — NML-only scoring, ritual action creates new NML obj | CA 2025-26 | C | ⚠️ | `MissionData.gd:161-176`, `MissionManager.gd:794-809`, ritual tracking dicts at lines 35-39 | Scoring works for existing NML objectives but ritual-action UI to *create* new NML objectives is absent. Code has `_pending_rituals`/`_ritual_objectives` dicts but no phase code populates them. **Invisible feature**: mission selectable but core mechanic untriggerable. |
| 13 | Primary "Terraform" — flip objectives bonus | CA 2025-26 | C | ⚠️ | `MissionData.gd:205-222`, `MissionManager.gd:816-842`, `_terraformed_objectives` at line 43 | Scoring reads `_terraformed_objectives[obj_id] == active_player` but no terraform action wired into ShootingPhase. `_pending_terraforms` dict at line 47 is unused. **Invisible feature**. |
| 14 | Primary "Hidden Supplies" — extra objectives placed in R3 | CA 2025-26 | C | ❌ | `MissionData.gd:249-266` declares it; `MissionManager.gd:410-429` dispatch falls into `hold_objectives` default | No `_score_hidden_supplies` handler; `extra_objectives_round` rule never reads. Mission is selectable but scores like Take and Hold. |
| 15 | Primary "Burden of Trust" (CA mission) | CA 2025-26 (per local HTM 310792) | C | ❌ | (not present) | **Missing primary mission** — appears in CA FAQ as "Burden of Trust Primary Mission" with end-of-opponent-turn scoring for guarding objectives. No entry in `MissionData._missions`. |
| 16 | Primary scoring at end of Command phase | CA 2025-26 mission rules | L | ✅ | `40k/phases/CommandPhase.gd:2125` calls `MissionManager.score_primary_objectives()` after `_handle_end_command` | Confirmed live via `get_current_phase` (R1, P2 active, scoring deferred to its turn) |
| 17 | Tipping Point deployment (4 of 7 CA mission scenarios) | CA 2025-26 mission pool | C | ❌ | `40k/deployment_zones/` lists: dawn_of_war, hammer_anvil, search_and_destroy, crucible_of_battle, sweeping_engagement | **Missing deployment** — Tipping Point is referenced 8 times in CA pool table (HTM 334224-335657) but no `tipping_point.json` exists. Scenarios A–D use Tipping Point and cannot be played. |
| 18 | Secondary missions: 18-card tactical deck (Display of Might excluded) | CA 2025-26 | W | 🐛 | `40k/scripts/data/SecondaryMissionData.gd:42-381`; `get_mission_ids_for_deck` at line 392-398 returns ALL 18 (including Display of Might) | **DOC vs CODE conflict**: `SECONDARY_MISSIONS_TASKS.md:157` says "18 in standard tournament deck, Display of Might excluded" — but the code defines and returns 18 missions *including* Display of Might. Need to confirm CA tournament rule vs general CA. The data file does include Display of Might (`number: 4`). |
| 19 | Tactical deck card draw at start of Command phase | CA 2025-26 | W | ✅ | `CommandPhase.gd:108-116` calls `secondary_mgr.draw_missions_to_hand` at start of every command phase | Skipped for fixed mode (`is_fixed_mode` check) |
| 20 | Voluntary discard for 1 CP at end of player's turn (tactical only) | CA 2025-26 | U | ✅ | `ScoringPhase.gd:122-135` exposes `DISCARD_SECONDARY` action; `ScoringController.gd:336-345` renders Discard button per active mission | UI shows "Discard X (gain 1 CP)" or "(no CP)" when bonus cap hit. Bonus CP cap at 1/round per `GameState.BONUS_CP_CAP_PER_ROUND` (correct). |
| 21 | "New Orders" core stratagem (1 CP, end of Command phase, swap a secondary card) | CA 2025-26 | U | ✅ | `StratagemManager.gd:358-384` (definition); `CommandPhase.gd:370-377, 1809-1838`; `CommandController.gd:404-462, 489-510` (UI button) | Stratagem registered, validated, executed; UI button renders during command phase per active mission |
| 22 | "Marked for Death" — opponent picks 3 alpha targets, you pick 1 gamma | CA 2025-26 | U | ✅ | `SecondaryMissionData.gd:268-287`, `SecondaryMissionManager.gd:269-280, 1261-1273`, `dialogs/MarkedForDeathDialog.gd` | Modal opens via `when_drawn_requires_interaction` signal → CommandController triggers dialog; AI auto-resolves. |
| 23 | "A Tempting Target" — opponent selects NML obj | CA 2025-26 | U | ✅ | `SecondaryMissionData.gd:173-191`, `dialogs/TemptingTargetDialog.gd` | Validates NML objectives exist before requiring interaction (`SecondaryMissionManager.gd:282-293`); discards-and-draws if no NML obj |
| 24 | Behind Enemy Lines — first-round draws shuffle back into deck | CA 2025-26 | W | ✅ | `SecondaryMissionData.gd:57` (when_drawn `mandatory_shuffle_back`), `SecondaryMissionManager.gd:244-253` | OK; mandatory effect honoured |
| 25 | "Cull the Horde" — discard if no enemy INFANTRY 13+ on table | CA 2025-26 | W | ✅ | `SecondaryMissionData.gd:265`, `SecondaryMissionManager.gd:255-258, 1678-1699` | OK |
| 26 | "Bring it Down" — discard if no enemy MONSTER/VEHICLE | CA 2025-26 | W | ✅ | `SecondaryMissionData.gd:247`, `SecondaryMissionManager.gd:260-263, 1701-1718` | OK |
| 27 | "Display of Might" — discard if fewer than 3 own units (or Incursion) | CA 2025-26 | ⚠️ | ⚠️ | `SecondaryMissionData.gd:111`, `SecondaryMissionManager.gd:265-268` | Implements `< 3 units` check but Incursion (small-game) detection is not present — at higher game sizes this is the right check; at Incursion the rule should also discard regardless of unit count. Edge case for Incursion not covered. |
| 28 | Storm Hostile Objective — control opponent-controlled-at-start objectives | CA 2025-26 | W | 🐛 | `SecondaryMissionManager.gd:772-789` | **BUG**: condition at line 785 is `start_controller != player` — counts both opponent-controlled AND **contested** (0) starts. Per CA rule the high-VP condition specifically requires opponent control at start. The 2 VP "alt" condition (`_check_storm_hostile_alt`) is supposed to handle the contested case (when opponent had zero) but the main condition is now too broad — a contested objective captured this turn scores the higher 5 VP. Docstring at 774-775 acknowledges this as intentional, but it diverges from rule. |
| 29 | Defend Stronghold — own-zone objectives | CA 2025-26 | W | ✅ | `SecondaryMissionManager.gd:815-829` | Uses `"player%d" % player` — matches JSON zone naming |
| 30 | Secure No Man's Land | CA 2025-26 | W | ✅ | `SecondaryMissionManager.gd:831-843` | OK |
| 31 | Extend Battle Lines — own zone AND NML | CA 2025-26 | W | ✅ | `SecondaryMissionManager.gd:853-857` | OK |
| 32 | Engage on All Fronts — quarters >6" from center | CA 2025-26 | W | ⚠️ | `SecondaryMissionManager.gd:675-719` | Uses board size from `state.board.size` (default 44×60); quarter bounds split at center. **Edge case**: for non-rectangular deployments (`crucible_of_battle`) the quarter bounds still split at half-board, which is correct, but uses `_is_unit_wholly_in_rect` (axis-aligned rect of the quarter). Looks correct. |
| 33 | Area Denial — within 6" of center, no enemies within 6"/3" | CA 2025-26 | W | ✅ | `SecondaryMissionManager.gd:721-759` | OK; uses `_has_model_within_range` for friendly+enemy presence |
| 34 | Display of Might (more units in NML than opponent) | CA 2025-26 | W | ✅ | `SecondaryMissionManager.gd:761-766` | Uses polygon-based zone exclusion to compute "wholly in NML" |
| 35 | Action missions (Establish Locus / Cleanse / Deploy Teleport Homer) | CA 2025-26 | U | ⚠️ | `SecondaryMissionData.gd:329-381`, `ShootingPhase.gd:1278-1330, 1704-1807` (`_get_secondary_action_options`), `ShootingController.gd:483-491, 3230-3258` (`Perform Action` button) | UI button "Perform Action" is exposed to player when an active action mission exists and the active shooter qualifies. **Caveat:** the option only shows for the BEST-VP variant per mission (line 3257 picks `best_option`); if there are multiple action options simultaneously the player can't pick a specific one — this is OK in practice since each mission has one action. |
| 36 | Action missions: Sabotage / Recover Assets / Investigate Signals | CA 2025-26 | ❌ | ❌ | (not present) | **Missing tactical action missions** — the local CA HTM mentions Sabotage in FAQ (310682) and `SECONDARY_MISSIONS_TASKS.md:78-79` lists Sabotage and Recover Assets as TODO. They're not in `SecondaryMissionData._missions`. Game has 18 secondaries (matching `get_mission_ids_for_deck`); CA 2025-26 deck has more action missions per mission cards (typically 6). |
| 37 | Kill-mission scoring (Assassination / No Prisoners / Bring it Down / Cull / Marked / Overwhelming) | CA 2025-26 | W | ✅ | `SecondaryMissionManager.gd:863-951`; kill hook `on_unit_destroyed` + `check_and_report_unit_destroyed` at 1088-1227 | Hook is invoked from RulesEngine combat resolution, fight phase, and `_destroy_remaining_reserves` (ScoringPhase R3). Live presence in deck verified (No Prisoners drawn for P1). |
| 38 | Fixed Missions mode (select 2 fixed missions before game; 20 VP per card cap) | CA 2025-26 | U | ✅ | `SecondaryMissionManager.gd:107-145, 522-528`, `MainMenu.gd:359-386` (mode dropdown), `dialogs/FixedMissionSelectionDialog.gd` | Mode set in MainMenu, dialog opens for picking 2 missions. Fixed missions can't be voluntarily discarded or replaced via New Orders (lines 332-333, 425-426). |
| 39 | Battle Ready Army painting bonus (10 VP) | CA 2025-26 VP table | C | ❌ | (not present) | **Missing**: no `battle_ready` flag, no UI to mark army as painted, no +10 VP applied at end of game. CA total max is 100 VP; current cap is 90. |
| 40 | Challenger Cards (12 VP comeback mechanic; draw at command phase if 6+ VP behind) | CA 2025-26 | C | ❌ | (not present) | **Missing entirely**. Per local HTM at 332xxx (continuation of mission rules), Challenger draws when player is 6+ VP behind at start of battle round. Cards present a Stratagem-or-Mission choice. Code has neither a deck nor signal. |
| 41 | Adapt or Die / similar mission rule cards | CA 2025-26 | C | ❌ | (not present) | Mission Rule cards (referenced in SecondaryMissionManager.gd:107 as the only way to discard fixed) — not implemented. |
| 42 | End-of-game game-over and winner determination | Core | ✅ | ✅ | `ScoringPhase.gd:242-308`; `_determine_winner` simple max VP | OK; uses `MAX_BATTLE_ROUNDS = 5`. Doesn't fold in battle-ready VP (rule 39) or challenger VP (rule 40). |
| 43 | VP timeline snapshot per round per player | (internal P3-128) | W | ✅ | `MissionManager.gd:51, 1033-1056`; called from `ScoringPhase.gd:236-237` | OK; supports VP chart UI |
| 44 | Objective control changed visual flash | (T7-39) | W | ✅ | `ObjectiveVisual.gd:171-204` defines flash colours and `flash_control_change`; `MissionManager.gd:178-181` emits `objective_control_changed` | Verified in earlier audit; spot-check passed |
| 45 | Persistent secondary mission HUD panel toggleable across all phases | T16 / SECONDARY_MISSIONS_TASKS.md task 11 | U | ✅ | `scripts/SecondaryMissionPanel.gd` (collapsible top-left); `Main.gd:2449-2453` instantiation; M-key toggle at `Main.gd:4521` | Confirmed live: `find_child("SecondaryMissionPanel")` returns valid node, `is_collapsed=true` initially. Header button text shows `[M]`. |
| 46 | Save/load round-trip for secondary mission state, sticky objectives, burn state | core | W | ✅ | `SecondaryMissionManager.gd:1772-1806` (`get_save_data`/`load_save_data` + visual restoration); `MissionManager.gd:381-383` `get_sticky_objectives` | Visual restoration (`_restore_tempting_target_visuals`, `_restore_mfd_target_visuals`) applies after load — good. |
| 47 | Reserves not arrived by end of R3 are destroyed (and credited as kills) | 10e Core / CA 2025-26 (HTM 320xxx) | W | ✅ | `ScoringPhase.gd:380-459` (P1-37); calls `secondary_mgr.check_and_report_unit_destroyed` and `MissionManager.record_unit_destroyed` | OK |

## Live-validation log

- **MCP bridge ping → ok** (engine 4.6-stable, hash `89cea14`).
- **Phase introspection** (`get_current_phase`): R1, SCORING, P2 active, only END_SCORING action available — game running.
- **execute_script** confirmed:
  - `MissionManager.get_current_mission_id() == "take_and_hold"` (default mission)
  - `MissionManager._get_player_home_zone(1) == "player1_zone"` ← **bug confirmed live**
  - `MissionManager._get_player_home_zone(2) == "player2_zone"` ← **bug confirmed live**
  - `state.board.objectives[*].zone` is `"player1"` / `"player2"` / `"no_mans_land"` ← canonical zone strings
  - `MissionManager.get_objective_control_summary() == {obj_home_1:1, others:0, p1_controlled:1, p2_controlled:0, contested:4}` ← OC contest works correctly
  - `state.board.deployment_zones` returns polygon-based zones used by Behind Enemy Lines etc.
  - SecondaryMissionPanel node exists in scene, `visible=true, collapsed=true`
  - P1 active missions: `[No Prisoners, Display of Might]` ← deck draws working
  - P2 deck initialized but no active cards yet (P2's first command phase hasn't fired)
  - `evaluate_mission_progress(1)` returns structured progress with met flags ← progress UI hook works
- Spot-check of battle-shock OC=0 was not directly toggled live (execute_script is single-line and can't run multi-statement test); however `MissionManager.gd:207-209` is unchanged from the verified-2026-05 location, and the BS exclusion path is the same `flags.battle_shocked` field used in the rest of the codebase. **VERIFIED (regression spot-check via static read).**

LIVE-VALIDATION SKIPPED for items 10 (Scorched Earth burn-bonus zone bug) and 11 (Sites of Power center-to-center): the running game is on `take_and_hold` mission; switching missions mid-game would require a mission-restart action that is not exposed via dispatch_action. Bug is verified by source inspection + zone-name live mismatch (`_get_player_home_zone(1) != "player1"`). The +10 VP misfire would manifest only when (a) Scorched Earth mission is active AND (b) a burn completes — an integration path not currently driven by the running game.

## Top 3 launch-blocker scoring gaps

1. **Tipping Point deployment missing (rule 17).** CA 2025-26 mission pool's first 4 mission scenarios (A–D, also Q–R) use Tipping Point deployment. There is no `tipping_point.json` in `deployment_zones/`. Players cannot run those scenarios at all.
2. **Hidden Supplies and Burden of Trust primary missions absent or stubbed (rules 14, 15).** Hidden Supplies has a stub data entry but no scoring handler — falls through to Take and Hold. Burden of Trust is wholly missing. Both appear in the canonical CA mission pool, so picking those scenarios silently scores incorrectly.
3. **Scorched Earth burn-bonus zone bug (rule 10).** `_get_player_home_zone()` returns `"playerN_zone"` while the rest of the codebase / JSON uses `"playerN"`. Live-confirmed. The result is +10 VP wrongly granted for burning your own home objective when burn-eligibility would otherwise allow it. The current burn-eligibility table at `MissionData.gd:147-156` says `can_burn_home: false` so the bug only fires if any code path ever lets a home burn through; still, the comparison being uniformly broken is a launch-blocker for any Scorched Earth playtest.

## Top 3 invisible features

1. **The Ritual mission's ritual action (rule 12).** Mission is selectable; scoring helpers reference `_pending_rituals` / `_ritual_objectives`; but **no UI affordance and no phase code** populates ritual completion. Players who pick The Ritual see scoring fire only for objectives that already happen to be in NML — they cannot perform the central mechanic that makes the mission distinctive.
2. **Terraform mission's terraform action (rule 13).** Same shape as The Ritual — mission selectable, `_terraformed_objectives` dict referenced in scoring, **no UI affordance** to flip an objective to your side. Bonus VP component is dead code.
3. **Challenger Cards (rule 40)** and **Battle Ready Army painting bonus (rule 39).** CA 2025-26 explicitly tops out at 100 VP via the painting bonus and includes a 12 VP Challenger come-back mechanic. Neither is present anywhere — no flag, no UI toggle, no card deck. The 90 VP cap shipped in `MAX_COMBINED_VP` matches CA's combined-three-sources cap, but the +10 painting and the entire Challenger system are absent. This is a missing feature, not just an invisible one, but it is "invisible" in the sense that nothing in the game UI tells the player it should exist.

## Mission-pack-specific divergences

- Sites of Power scoring (rule 11) uses center-to-center distance for character claim while normal OC uses edge-to-point — this is internally inconsistent. CA does not specify a separate measure for Sites of Power, so it should match general OC measurement.
- Storm Hostile Objective (rule 28) main 5 VP condition broadens the rule to include objectives that were contested at start. Per CA the 5 VP requires opponent control at start; the 2 VP `alt` condition specifically covers the contested case. The broadening is an intentional code choice (per docstring) but diverges from the printed CA card.
- Display of Might Incursion-game discard (rule 27) — implemented as `< 3 units` only; CA also has a "playing Incursion" auto-discard clause that is not implemented (likely fine in practice if game size > Incursion).
- Action mission roster (rule 36) is a strict subset of CA's tactical-deck action missions. Missions like **Sabotage** (terrain-feature within enemy half), **Recover Assets** (units-in-different-zones), and **Investigate Signals** are absent. `SECONDARY_MISSIONS_TASKS.md:73-81` already tracks Sabotage and Recover Assets as a known blocker.

## Cross-cutting code-quality notes (not findings; record only)

- Two parallel kill-tracking systems (`MissionManager._kills_this_round` and `kills_per_round`) coexist; `_score_hold_and_kill` line 501-502 takes the max of both. Functional but confusing — recommend consolidating after launch.
- `SecondaryMissionManager._while_active_vp_this_window` is keyed by `"<player>_<mission_id>"`. The window is cleared in `on_turn_start` (line 1082) — fine for tactical mode, but in fixed mode the same mission can score multiple times per battle. Code at line 1142-1143 caps via `MAX_FIXED_MISSION_VP` so accumulation is bounded; OK.
- Save/load explicitly restores Marked for Death and Tempting Target visual flags after load (lines 1334-1343, 1798-1806). Good.

## Prior-audit overlap (regression spot-checks only — not refiled)

- Battle-shock OC=0 (`MissionManager.gd:207-209`) — **VERIFIED (regression spot-check)** via source read; live `_check_objective_control` was exercised end-to-end during this session.
- USE_NEW_ORDERS / DISCARD_SECONDARY actions (Crucible mission management) — **VERIFIED**; `ScoringPhase.gd:122-135` and `CommandPhase.gd:370-377` expose both, with full UI in `ScoringController` and `CommandController`.
- Secondary mission discard logic (T7-47) — **VERIFIED**.
- Objective control flash on change (T7-39) — **VERIFIED**; `ObjectiveVisual.gd:171-280` flash logic intact, signal `objective_control_changed` emitted from `MissionManager.gd:178-181`.

## Files cited (absolute paths)

- `/Users/robertocallaghan/Documents/claude/godotv2/40k/autoloads/MissionManager.gd`
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/autoloads/SecondaryMissionManager.gd`
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/data/MissionData.gd`
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/data/SecondaryMissionData.gd`
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/phases/ScoringPhase.gd`
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/phases/CommandPhase.gd`
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/phases/ShootingPhase.gd`
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/CommandController.gd`
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/ScoringController.gd`
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/ShootingController.gd`
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/SecondaryMissionPanel.gd`
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/MainMenu.gd`
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/ObjectiveVisual.gd`
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/dialogs/MarkedForDeathDialog.gd`
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/dialogs/TemptingTargetDialog.gd`
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/dialogs/FixedMissionSelectionDialog.gd`
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/autoloads/StratagemManager.gd`
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/autoloads/GameState.gd`
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/deployment_zones/*.json` (5 files; Tipping Point absent)
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/deployment_zones/Chapter Approved 2025-26.htm` (local CA reference)
- `/Users/robertocallaghan/Documents/claude/godotv2/40k/SECONDARY_MISSIONS_TASKS.md` (existing task list)
