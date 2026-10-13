# Codex: Orks (11th edition) stratagems — design contract

Status: shipped on branch `claude/bold-pasteur-45wgjz` (design 2026-10-11; final
state, rulings, limitations and test inventory in §7, 2026-10-13).
Audience: every agent implementing or validating this work. Read it all before
touching code. Where this doc and older code comments disagree, this doc wins.

## 0. Goal

1. Move the game's data to `@alpaca-software/40kdc-data` **1.4.5** (from 1.0.19).
2. Ship all **40** stratagems of the 11th-edition Codex: Orks (15 detachments) with
   rules text taken from Wahapedia (verified copy:
   `scripts/40kdc/curated/orks_codex_11e.json`, see §2).
3. Every one of them must be usable by a **human** player, offered **in the correct
   timing window** through the game UI (not only via the AI, not only via the S panel
   at an arbitrary moment). The AI must keep working (use them or decline, never stall).
4. Validate thoroughly: headless tests per handler + a windowed scenario per
   stratagem that drives the real window through UI clicks + screenshots.

Out of scope (flag, don't build): detachment *rules* and *enhancements* of the new
detachments, non-Ork 1.4.5 stratagem changes, terrain-layout regeneration,
mirror-match (same faction + same detachment on both sides) id collisions.

## 1. Data policy

- Bump `scripts/40kdc/package.json` to `1.4.5`; `npm install` there; run `node extract.mjs`
  (all collections, all factions). Re-apply known local hand patches that extract wipes
  (e.g. Wazdakka Gutsmek oval base `120x92`) — check `git diff` of `40k/data/40kdc/` for
  anything hand-edited before overwriting.
- **CSV outputs (`Stratagems.csv`, `Detachments.csv`, `Datasheets.csv`,
  `Datasheets_leader.csv`) are regenerated but only the `ORK` rows are spliced into the
  committed files; every other faction's rows stay byte-identical.** (Avoids ~400
  unreviewed non-Ork behaviour changes.) The generators get an `--only-faction ORK`
  splice mode or an equivalent post-process step that is committed with them.
- Ork stratagem rows come from the curated file, not from 1.4.5's metadata (1.4.5 is
  stale for Dread Mob and Blitz Brigade and misspells three names).
- New optional CSV column **`window`** appended to `Stratagems.csv`
  (`…|timing|effects_json|window`). Value = comma-separated window ids (§3). The loader
  stores it as `strat.timing.windows: Array[String]` (and keeps `timing.trigger`
  inference for rows without it). Empty = no window = S-panel stratagem.
- Ork rows: `effects_json = [{"type":"custom:ork11e"}]`; `implemented` is decided by the
  Ork codex registry (§4), never by name lists or text regexes.
- Army files that use removed detachments are migrated by hand (do not run
  `generate-armies.mjs` wholesale): `battlewagons.json` → `Blitz Brigade`,
  `recon_stomps.json` → a codex detachment that fits its units; replace enhancements
  that no longer exist with valid ones from the new detachment; keep points/units unless
  a unit no longer loads. Update AI-plan `detachment_hint`s that name removed
  detachments.
- After extract, compare resolved loadouts (`UnitLoadoutResolver`) for **every** army
  file before vs after; any change must be explained by the codex (removed datasheet,
  renamed weapon) and fixed in the army file where the unit should keep working.
- Update `ATTRIBUTION.md`, `generate-armies.mjs` data_source string,
  `server/public/js/lib/gameformat.mjs` `DEFAULT_DATA_SOURCE`, and fix
  `factionRuleAbility()` for `faction_rule_ids[]` (1.4.5 schema change) so the web
  builder keeps army rules.

## 2. The 40 stratagems (source of truth: `scripts/40kdc/curated/orks_codex_11e.json`)

CSV `id` (= `csv_id` in game) | display name | detachment | CP | turn | phase | window(s)

| csv id | name | det | CP | turn | phase | window(s) |
|---|---|---|---|---|---|---|
| breakin-heads-war-horde | BREAKIN' HEADS | War Horde | 1 | either | any | unit_battle_shocked |
| hit-em-harder-war-horde | HIT 'EM HARDER | War Horde | 1 | either | fight | unit_selected_to_fight |
| orks-is-never-beaten-war-horde | ORKS IS NEVER BEATEN | War Horde | 1 | either | fight | enemy_targets_unit_fight |
| mow-em-down-war-horde | MOW 'EM DOWN | War Horde | 1 | either | fight | unit_selected_to_fight |
| fungus-fuel-injection-war-horde | FUNGUS-FUEL INJECTION | War Horde | 1 | your | movement | unit_selected_to_move |
| close-range-dakka-war-horde | CLOSE-RANGE DAKKA | War Horde | 1 | your | shooting | unit_selected_to_shoot |
| vindictive-artillerists-madcap-meks | VINDICTIVE ARTILLERISTS | Madcap Meks | 1 | your | shooting | unit_selected_to_shoot |
| infested-war-zone-runt-swarm | INFESTED WAR ZONE | Runt Swarm | 2 | either | any | enemy_unit_has_attacked |
| scarper-runt-swarm | SCARPER! | Runt Swarm | 1 | opponent | movement | enemy_ended_move |
| grot-shields-runt-swarm | GROT SHIELDS | Runt Swarm | 1 | opponent | shooting | enemy_targets_unit_shooting |
| drive-by-bustin-wreckas | DRIVE-BY BUSTIN' | Wreckas | 1 | your | shooting | unit_selected_to_shoot |
| grab-it-wreckas | GRAB IT | Wreckas | 1 | your | shooting | unit_has_shot |
| gun-crazy-show-offs-wreckas | GUN-CRAZY SHOW-OFFS | Wreckas | 1 | opponent | shooting | enemy_has_shot |
| too-arrogant-to-die-bully-boyz | TOO ARROGANT TO DIE | Bully Boyz | 1 | either | fight | enemy_targets_unit_fight |
| armed-to-da-teef-bully-boyz | ARMED TO DA TEEF | Bully Boyz | 1 | either | shooting_or_fight | unit_selected_to_shoot,unit_selected_to_fight |
| hulking-brutes-bully-boyz | HULKING BRUTES | Bully Boyz | 1 (+1 upgrade) | opponent | shooting | enemy_targets_unit_shooting |
| where-dya-fink-youre-going-da-big-hunt | WHERE D'YA FINK YOU'RE GOING? | Da Big Hunt | 1 | opponent | movement | enemy_selected_to_fall_back |
| goaded-into-action-da-big-hunt | GOADED INTO ACTION | Da Big Hunt | 1 | opponent | shooting | enemy_has_shot |
| instinctive-hunters-da-big-hunt | INSTINCTIVE HUNTERS | Da Big Hunt | 1 | opponent | fight | fight_phase_end |
| crazed-rampage-dread-mob | CRAZED RAMPAGE | Dread Mob | 1 | either | fight | enemy_targets_unit_fight |
| dread-power-dread-mob | DREAD POWER | Dread Mob | 1 | your | movement | (panel) |
| stomping-juggernaut-dread-mob | STOMPING JUGGERNAUT | Dread Mob | 1 | your | movement_or_charge | unit_selected_to_move,unit_declares_charge |
| kustom-dakka-shoota-boyz | KUSTOM DAKKA | Shoota Boyz | 1 | your | shooting | unit_selected_to_shoot |
| glowin-dakka-shoota-boyz | GLOWIN' DAKKA | Shoota Boyz | 1 | your | shooting | unit_selected_to_shoot |
| never-enough-dakka-shoota-boyz | NEVER ENOUGH DAKKA | Shoota Boyz | 1 | your | shooting | unit_selected_to_shoot |
| flyin-headbutt-flyboyz | FLYIN' HEADBUTT | Flyboyz | 1 | either | any | unit_destroyed |
| long-uncontrolled-bursts-flyboyz | LONG, UNCONTROLLED BURSTS | Flyboyz | 1 | your | shooting | unit_selected_to_shoot |
| whirligig-evasion-flyboyz | WHIRLIGIG EVASION | Flyboyz | 1 | opponent | movement | enemy_ended_move |
| delicious-eating-squigs-kult-of-speed | DELICIOUS EATING SQUIGS | Kult of Speed | 1 | your | movement | (panel) |
| dakkastorm-kult-of-speed | DAKKASTORM | Kult of Speed | 1 | your | shooting | unit_selected_to_shoot |
| speediest-freeks-kult-of-speed | SPEEDIEST FREEKS | Kult of Speed | 1 | opponent | shooting | enemy_targets_unit_shooting |
| keep-it-runnin-blitz-brigade | KEEP IT RUNNIN' | Blitz Brigade | 1 | either | fight | fight_phase_end |
| readied-brawlers-blitz-brigade | READIED BRAWLERS | Blitz Brigade | 1 | your | movement | unit_ended_normal_move |
| impending-krunch-blitz-brigade | IMPENDING KRUNCH | Blitz Brigade | 1 | your | charge | unit_ended_charge_move |
| unbridled-carnage-green-tide | UNBRIDLED CARNAGE | Green Tide | 1 | either | fight | unit_selected_to_fight |
| mob-mentality-green-tide | MOB MENTALITY | Green Tide | 1 | your | command | battle_shock_step_start |
| ere-we-go-green-tide | 'ERE WE GO | Green Tide | 1 | your | movement | unit_selected_to_move |
| dubious-restraint-taktikal-brigade | DUBIOUS RESTRAINT | Taktikal Brigade | 1 | your | movement | movement_phase_start,movement_phase_end |
| mind-mostly-on-the-mission-taktikal-brigade | MIND MOSTLY ON THE MISSION | Taktikal Brigade | 1 | your | movement | unit_selected_to_move |
| while-their-backs-are-turned-taktikal-brigade | WHILE THEIR BACKS ARE TURNED | Taktikal Brigade | 1 | opponent | movement | movement_phase_end |

(War Horde 6, Madcap Meks 1, Runt Swarm 3, Wreckas 3, Bully Boyz 3, Da Big Hunt 3,
Dread Mob 3, Shoota Boyz 3, Flyboyz 3, Kult of Speed 3, Blitz Brigade 3, Green Tide 3,
Taktikal Brigade 3, Wurrband 0, Brute Bosses 0 = 40.)

Names in the CSV use straight apostrophes (`'`) so ids and node paths are stable.
`Detachments.csv` Ork rows = the 15 codex detachments (removed: More Dakka!, Freebooter
Krew, Rollin' Deff, Speedwaaagh!). The old Dread Mob six and Blitz Brigade six are
**dropped** (codex replaced them).

Rules text: the WHEN/TARGET/EFFECT text from the curated file goes into the
`description` column with the literal `<b>WHEN:</b>` … markers. Durations in the
EFFECT text drive `expires` (`use_stratagem`), so add the duration phrase where the
codex leaves it implicit (e.g. "until the end of the phase").

## 3. Stratagem windows

A *window* is a game event at which a stratagem can be used. A window is **opened**
by phase code at the hook point; it computes **offers** for one **decider** player
and either resolves synchronously (no offers / AI decider) or pauses the phase until
the human decides.

| window id | hook point (phase) | decider | ctx keys (always include `phase`) |
|---|---|---|---|
| battle_shock_step_start | Command phase, start of the battle-shock step (before any test) | active player | — |
| unit_battle_shocked | wherever a unit becomes battle-shocked (any phase) | owner of that unit | `unit_id` |
| movement_phase_start | Movement phase start (after phase-start bookkeeping) | active, then non-active | — |
| movement_phase_end | END_MOVEMENT, before the phase actually ends (after Rapid Ingress etc.) | active, then non-active | `engaged_at_phase_start: Array[unit_id]` |
| unit_selected_to_move | BEGIN_NORMAL_MOVE / BEGIN_ADVANCE / BEGIN_FALL_BACK, **before** any roll or cap is computed | active (unit owner) | `unit_id`, `move_type` (normal/advance/fall_back) |
| unit_ended_normal_move | after CONFIRM_UNIT_MOVE of a *normal* move | active | `unit_id` |
| enemy_ended_move | after CONFIRM_UNIT_MOVE of any move by the active player's unit, and after a disembark move or a reinforcement (ingress) set-up (after overwatch/other existing reactive prompts) | non-active | `enemy_unit_id`, `move_type` |
| enemy_selected_to_fall_back | BEGIN_FALL_BACK, before the fall-back mode/move is set up | non-active | `enemy_unit_id` |
| unit_selected_to_shoot | when a shooter is selected (before targets are confirmed / attacks rolled) | active | `unit_id` |
| unit_has_shot | after a unit's shooting has fully resolved | active | `unit_id` |
| enemy_targets_unit_shooting | after the attacker confirms targets (the existing reactive point) | non-active | `attacker_unit_id`, `target_unit_ids` |
| enemy_has_shot | after the attacker's shooting has fully resolved | non-active | `attacker_unit_id`, `hit_unit_ids`, `wounded_unit_ids` (lost ≥1 wound) |
| unit_declares_charge | DECLARE_CHARGE, before the charge roll | active | `unit_id`, `target_unit_ids` |
| unit_ended_charge_move | after the charge move is applied | active | `unit_id` |
| unit_selected_to_fight | when a unit is selected to fight (either player's unit), before attacks | owner of the fighter | `unit_id` |
| enemy_targets_unit_fight | after an enemy fighter's targets are known, before any attack is rolled | owner of the targeted unit | `attacker_unit_id`, `target_unit_ids` |
| fight_phase_end | end of Fight phase, before it actually ends | active, then non-active | — |
| unit_destroyed | when a unit is destroyed, **before** its Deadly Demise is resolved | owner of the destroyed unit | `unit_id`, `attacker_unit_id` (may be "") |
| enemy_unit_has_attacked | after an enemy unit's attacks finish (shooting, fight, overwatch…) | owner of units destroyed by those attacks | `attacker_unit_id`, `destroyed_unit_ids` |

Turn gating still uses the CSV `turn` column relative to the active player and the
decider. A stratagem is offered in window W only if `W in strat.timing.windows`.

**Usage gating:** `can_use_stratagem` rejects a stratagem that has `timing.windows`
unless `context.window_id` is one of them (reason shown in the S panel:
"Offered automatically when …"). Panel stratagems (no windows) keep today's panel path.

### 3.1 Framework API (StratagemManager + BasePhase)

```
# StratagemManager
func get_window_offers(player: int, window_id: String, ctx: Dictionary) -> Array
# -> [{stratagem_id, name, cp_cost, effect_text,
#      targets: [{unit_id, label,
#                 variants?: [{id, label, cp_cost}],          # e.g. HULKING BRUTES upgrade
#                 secondary?: {kind: "unit"|"objective", prompt, options: [{id, label}]}}]}]
# Uses OrkCodex11e.eligible_targets(...) for registered stratagems, else generic
# can_use_stratagem over ctx candidate units.

# BasePhase
signal stratagem_window_opened(player: int, window_id: String, offers: Array, ctx: Dictionary)
signal stratagem_window_closed(player: int, window_id: String, used: bool)
func open_stratagem_window(player: int, window_id: String, ctx: Dictionary, resume_method: String) -> bool
#  true  = paused, a human must answer; the phase will call resume_method(ctx, result) later
#  false = nothing to wait for (no offers, or AI decided synchronously); caller continues
# Actions handled generically in BasePhase.execute_action (before subclass validation):
#  {type:"USE_WINDOW_STRATAGEM", player, window_id, stratagem_id, target_unit_id,
#   context:{variant_id?, secondary_id?}}
#  {type:"DECLINE_WINDOW_STRATAGEM", player, window_id}
# While a window is pending, every other action except the two above (and UI/debug-only
# actions) is rejected with "Waiting for <player> to decide on a stratagem".
```

- Several windows may need to open at one hook (e.g. active then non-active at
  `movement_phase_end`): use a per-phase queue; resume when the queue is empty.
- Own-turn windows offer only stratagems the player can afford and that have ≥1
  eligible target. The dialog has **Decline** and **"Don't offer again this phase"**.
- AI decider: `AIDecisionMaker.decide_window_stratagem(player, window_id, offers, ctx)`
  returns `{use: bool, stratagem_id, target_unit_id, context}`; called synchronously
  from `open_stratagem_window`, so the AI can never stall a window.
- Network: both actions are turn-exempt in `NetworkManager.validate_action`; the host
  re-emits the window on the client like `reactive_stratagem_opportunity`; only the
  decider's machine shows the dialog, the other shows the waiting overlay.
- UI: one dialog for every window — extend `dialogs/StratagemDialog.gd` (header text
  per window, cards per stratagem, `Use_<sid>_<uid>[_<variant>]` buttons, Decline,
  don't-offer-again). Secondary choices use the existing
  `StratagemChoiceDialog`/`StratagemTargetDialog` pattern (`Choice_<id>`/`Pick_<id>`).
  Main.gd connects to the current phase's `stratagem_window_opened` whenever the
  phase instance changes. Node names must be stable for scenarios:
  `/root/StratagemDialog/…/Card_<sid>/Buttons/Use_<sid>_<uid>` (sid passed through
  `validate_node_name()`).
- The existing opponent-shooting reactive path (`get_reactive_stratagems_for_shooting`
  + `USE_REACTIVE_STRATAGEM`) is folded into / feeds the same dialog: core GO TO
  GROUND / SMOKESCREEN keep working, and `enemy_targets_unit_shooting` offers appear in
  the same dialog with the same button names.

### 3.2 Follow-ups

Some effects need more than flags. A handler's `apply` may return
`{diffs: [...], followup: {...}}`; the phase that opened the window executes it:

| followup.type | used by | executor |
|---|---|---|
| reactive_normal_move {unit_id, max_inches, end_condition?} | SCARPER!, WHIRLIGIG EVASION, WHILE THEIR BACKS ARE TURNED (Movement), GRAB IT (Shooting; must end within range of an objective) | human drags the move with the normal move UI; AI auto-moves |
| surge_move {unit_id, max_inches, reroll_allowed} | GOADED INTO ACTION (opponent's Shooting) | 11e surge rules (21.02) |
| shoot {unit_id, forced_target_id} | GUN-CRAZY SHOW-OFFS | out-of-phase shooting at the forced target |
| embark {unit_id, transport_id} | KEEP IT RUNNIN' | TransportManager |
| assault_disembark {transport_id} | READIED BRAWLERS | 18.06 assault disembark |
| strategic_reserves {unit_id} | INSTINCTIVE HUNTERS | existing reserves path |
| new_reserve_unit {source_unit_id} | INFESTED WAR ZONE | clone at starting strength into strategic reserves |

## 4. Code layout

- `40k/scripts/stratagems/ork_codex/OrkCodex11e.gd` — dispatcher (`class_name
  OrkCodex11e`, static). Registry csv_id → group script. Shared helpers:
  `is_riled_up(unit)` (= `flags.waaagh_active` or `flags.ork11e_riled_up`),
  `has_keyword(unit, kw)`, distance helpers. API:
  `handles(strat) -> bool`, `eligible_targets(strat, player, window_id, ctx) -> Array`,
  `validate(strat, player, target_unit_id, ctx) -> Dictionary`,
  `apply(strat, target_unit_id, ctx) -> Variant` (Array of diffs or `{diffs, followup}`),
  `clear(strat, unit_id) -> void`.
- Group scripts (one per implementation group, so parallel work does not collide):
  `OrkCodexFight.gd`, `OrkCodexShooting.gd` (own-turn selected-to-shoot),
  `OrkCodexShootingReactive.gd` (GRAB IT + opponent-Shooting windows), `OrkCodexMovement.gd`,
  `OrkCodexOther.gd` (Command / Charge / any-phase).
- StratagemManager calls the dispatcher **first** (before the legacy name-keyed
  handlers) in `_apply_stratagem_effects`, `_clear_stratagem_flags`, implemented
  marking, and `can_use_stratagem`. Dispatch is keyed by **csv_id**, so legacy 10e
  handlers that share a name (TOO ARROGANT TO DIE, ARMED TO DA TEEF, DAKKASTORM, …)
  can never fire for a codex row.
- Flags set by codex handlers: prefer real, scoped EffectPrimitives flags when the
  generic consumer is correct for the rule; otherwise `ork11e_<slug>` flags read by a
  helper called from **every** resolver path (interactive ranged, auto ranged,
  overwatch, melee, save paths, previews). Flags that must outlive the Shooting phase
  must not use the `effect_` prefix (ShootingPhase wipes every `effect_*` flag on exit).
- "Riled up" = the 11e Waaagh! state. A stratagem that makes a unit riled up (DREAD
  POWER) must give that unit the same riled-up benefits the Waaagh! gives
  (FactionAbilityManager has a single-unit Waaagh! helper used by GRAB AND BASH).

## 5. Validation requirements (per stratagem)

1. Headless test (`40k/tests/test_ork_codex_<group>.gd`, `GameState.set_edition(11)`):
   offer appears in the right window and not in others; target eligibility edge cases;
   effect (A/B with the same seed for combat modifiers); CP spent; expiry.
   Add the files to `40k/tests/run_pretrigger_tests.sh`.
2. Windowed scenario `40k/tests/scenarios/sp/ork11e_<slug>.json` that drives the real
   window with real clicks (no `emit_pressed`): trigger the event, assert the dialog
   card + button are visible and enabled, click Use (and variant/secondary), assert
   effect + CP delta, take screenshots. For opponent-turn windows, drive the
   opponent's action that opens the window.
3. No `SCRIPT ERROR` / `ERROR` in stdout or the debug log during the scenario.
4. Windowed Godot runs share one virtual display budget: wrap every windowed run in
   `flock /tmp/ork11e_godot_window.lock …`.

## 6. Framework as built (window framework step) — how to add a hook / a stratagem

Status: framework step done on `claude/bold-pasteur-45wgjz`. Built: the dispatcher
and the four group scripts, `StratagemManager` wiring, the `BasePhase` window
framework, `AIDecisionMaker.decide_window_stratagem`, network plumbing, the window
mode of `StratagemDialog`, the hook points `unit_selected_to_fight` (FightPhase) and
`enemy_targets_unit_shooting` (fold-in), **HIT 'EM HARDER** end to end, and the two
fixtures. The group steps then added every other hook point and stratagem (§7).

### 6.1 Files

| file | role |
|---|---|
| `40k/scripts/stratagems/ork_codex/OrkCodex11e.gd` | dispatcher (`class_name OrkCodex11e`, static); StratagemManager **preloads** it (no class-cache dependency); AIDecisionMaker loads it on first use (`_ork_codex()`, RG-F6: a const preload extended the `godot -s` compile cascade) |
| `…/OrkCodexCommon.gd` | shared helpers (late-bound autoloads, `is_riled_up`, `has_keyword`, `attached_group_ids`, `unit_distance_inches`, `set_flag_diffs`, `erase_flags`, `target_entry`). Groups preload ONLY this file, never each other or the dispatcher |
| `…/OrkCodexFight.gd`, `…Shooting.gd`, `…Movement.gd`, `…Other.gd` | one group each: `IDS` (registry, the full csv ids — e.g. `hit-em-harder-war-horde`), `IMPLEMENTED` (the ONLY source of "implemented"), `AI_KIND`, and the handler API below |
| `40k/phases/BasePhase.gd` | window framework (bottom of the file) |
| `40k/dialogs/StratagemDialog.gd` | `setup_window(...)` (window mode) + the legacy `setup(...)` shooting reactive mode |
| `40k/scripts/Main.gd` | `_connect_stratagem_window_signal` (end of `setup_phase_controllers`), `_on_stratagem_window_opened`, secondary picks, `_dispatch_window_action` |
| `40k/tests/test_ork_codex_framework.gd` | headless framework + HIT 'EM HARDER test (in `run_pretrigger_tests.sh`) |
| `40k/tests/scenarios/sp/ork11e_hit_em_harder_own_turn.json`, `…_opponent_turn.json` | windowed scenarios (real clicks) |
| `40k/tests/helpers/gen_ork11e_fixtures.gd` | fixture generator (§6.6) |

Group handler API (all `static`, called only by the dispatcher):
`eligible_targets(strat, player, window_id, ctx) -> Array` (target entries
`{unit_id, label, variants?: [{id,label,cp_cost}], secondary?: {kind, prompt, options:[{id,label}]}}`;
`unit_id ""` = target-less use, button `Use_<sid>_none`),
`validate(strat, player, target_unit_id, ctx) -> {ok, reason}`,
`apply(strat, target_unit_id, ctx) -> Array | {diffs, followup}`,
`clear(strat, unit_id)`, `ai_kind(strat)` (`offensive`/`defensive`/`utility`),
`ai_score(strat, player, target_unit_id, window_id, ctx) -> float`,
`variant_cp_cost(strat, variant_id) -> int` (-1 = base cost),
`allows_battle_shocked_target(strat, ctx) -> bool` (BREAKIN' HEADS).

StratagemManager order for a codex row (`effects_json == [{"type":"custom:ork11e"}]`):
implemented marking = `OrkCodex.is_implemented`; `can_use_stratagem` → owner →
implemented → **window gate** (`context.window_id` must be in `timing.windows`, else
"Offered automatically when …", shown in the S panel) → CP (`_base_cp_cost` honours
`context.variant_id`) → once-per-phase → 15.01 → out-of-phase → battle-shock (codex may
opt out) → **`OrkCodex.validate`** (replaces the CSV-parsed TARGET conditions) →
turn/phase gate. `_apply_stratagem_effects` / `_clear_stratagem_flags` call the
dispatcher FIRST and return. `use_stratagem` returns `followup` and `stratagem_name`.

### 6.2 How to add a hook point (real example: `unit_selected_to_fight`)

At the hook, build the window ctx (always `phase` + the keys of the §3 table), open
the window for the decider, and split the rest of the interrupted flow into a
continuation the resume method can call. This is the code in
`FightPhase._process_select_fighter`:

```gdscript
	emit_signal("fighter_selected", active_fighter_id)  # Compatibility signal

	var fighter_owner := int(get_unit(active_fighter_id).get("owner", current_selecting_player))
	var stf_ctx := {"phase": "fight", "unit_id": active_fighter_id}
	if open_stratagem_window(fighter_owner, "unit_selected_to_fight", stf_ctx, "_resume_after_selected_to_fight_window"):
		log_phase_message("Waiting for Player %d's unit_selected_to_fight stratagem decision for %s" % [fighter_owner, active_fighter_id])
		return create_result(true, consume_window_diffs())        # PAUSED for a human
	var after_window = _after_selected_to_fight_windows(active_fighter_id)   # no offers / AI answered
	var stf_sync_diffs = consume_window_diffs()                 # AI use: CP + effect diffs
	if not stf_sync_diffs.is_empty():
		stf_sync_diffs.append_array(after_window.get("changes", []))
		after_window["changes"] = stf_sync_diffs
	return after_window

## Resume point for the unit_selected_to_fight window (BasePhase framework).
func _resume_after_selected_to_fight_window(ctx: Dictionary, _window_result: Dictionary) -> Dictionary:
	return _after_selected_to_fight_windows(str(ctx.get("unit_id", active_fighter_id)))

## Everything that follows "selected to fight" once the window has closed.
func _after_selected_to_fight_windows(fighter_id: String) -> Dictionary:
	active_fighter_id = fighter_id
	# … Epic Challenge → Martial Ka'tah → Dread Foe → attack assignment (unchanged code)
```

Rules for a new hook:
1. `open_stratagem_window(player, window_id, ctx, resume_method) -> bool`: `true` =
   paused (return a plain success result; BasePhase stamps `stratagem_window_opened`
   on it for the network client); `false` = continue inline AND merge
   `consume_window_diffs()` into your result's `changes` (AI uses happen synchronously).
   Both-players windows: `open_stratagem_window_both_players(window_id, ctx, resume)`
   (active first, then non-active) or `open_stratagem_windows([...entries], resume, ctx)`.
2. The resume method `func _resume_x(ctx: Dictionary, window_result: Dictionary) -> Dictionary`
   returns the phase result of the continued flow (signals it emits — attack dialog,
   next picker — reach the UI normally). `window_result` = `{used, player, window_id,
   stratagem_id?, target_unit_id?, diffs?}` of the LAST answered window.
3. Nothing else is needed for USE/DECLINE: BasePhase handles `USE_WINDOW_STRATAGEM`
   / `DECLINE_WINDOW_STRATAGEM` before subclass validation, rejects every other action
   while pending ("Waiting for Player N to decide on a stratagem"), and NetworkManager
   validates them through `BasePhase._validate_window_action` (turn-exempt).
4. Re-entrancy: opening a window while one is pending logs an ERROR and returns false
   (nested windows are not supported yet). Batch actions must stop when a window pauses
   (see `FightPhase._process_batch_fight_actions`).
5. Windows never open while a tutorial lesson is active (scripted steps).
6. "Don't offer again this phase" suppresses `player:window_id` on the phase instance
   (a new instance is created for every phase, so it resets automatically).

Follow-ups (§3.2): override `_execute_window_followup(player, window_id, followup, ctx) -> bool`
in the phase. Return `false` if it resolved immediately, or `true` if it pauses the
phase (e.g. a reactive move the human drags) and call `return _finish_window_followup(diffs)`
from the action that completes it (continues the queue, then the resume method). The
BasePhase default logs an ERROR "unsupported followup '<type>'" (stdout + debug log) so a
missing executor fails `verify_delivery` / the scenario log checks.

`enemy_targets_unit_shooting` is the one window that is NOT a BasePhase window: it is
folded into the existing opponent-Shooting reactive path. `get_reactive_stratagems_for_shooting(def, targets, {attacker_unit_id})`
appends `get_window_offers(def, "enemy_targets_unit_shooting", ctx)` entries
(`{stratagem, eligible_units, window_id, window_ctx, offer}`), the same StratagemDialog
renders them with the same `Card_<sid>/Buttons/Use_<sid>_<uid>[_<variant>]` names, and
`USE_REACTIVE_STRATAGEM` (+ `context.variant_id` / `secondary_id`) gets the window keys
from `ShootingPhase._reactive_window_context`. GROT SHIELDS / HULKING BRUTES /
SPEEDIEST FREEKS only need their group handlers (and AI scores — the reactive AI calls
`OrkCodex11e.ai_score` for window entries).

### 6.3 How to implement a stratagem (real example: HIT 'EM HARDER, `OrkCodexFight.gd`)

1. `eligible_targets`: return `[Common.target_entry(uid)]` only for legal targets in the
   right window (`_hit_em_harder_targets`: window `unit_selected_to_fight`, `ctx.unit_id`
   is a friendly ORKS unit on the battlefield). StratagemManager re-checks each target
   with `can_use_stratagem` (CP, once-per-phase, 15.01, turn/phase, window, validate).
2. `validate`: the same rule checks for an explicit target (also used by the AI and by
   `USE_WINDOW_STRATAGEM`). The S panel calls `can_use_stratagem(player, sid)` with NO
   target and no context: window stratagems never get that far (window gate), but the
   two panel stratagems (DREAD POWER, DELICIOUS EATING SQUIGS) do — their `validate` must
   return `ok` for `target_unit_id == ""` when the stratagem could be used at all (Main's
   generic friendly picker then calls it again per unit).
3. `apply`: return diffs; flag writes for an Attached unit go on every component
   (`Common.attached_group_ids`). HIT 'EM HARDER writes the existing melee-only
   `effect_lethal_hits_melee` (read only in `_resolve_melee_assignment_hits`) plus a marker
   `ork11e_hit_em_harder`.
4. `clear`: erase exactly what apply wrote (expiry comes from the EFFECT duration
   phrase → `end_of_phase`).
5. `ai_kind` / `ai_score`: `offensive` + `_melee_offense_score` (0 unless the unit has
   melee weapons and is engaged). `decide_window_stratagem` uses offensive ones only
   with ≥ 2 CP and score ≥ 2.0; defensive at score ≥ 1.5 × CP; utility at ≥ 2.0.
6. Add the csv id to `IMPLEMENTED` — that is what makes it "implemented" and offered.
7. Tests: headless section in `tests/test_ork_codex_<group>.gd` (offer / not offered,
   CP, effect A/B with the same seeds, expiry) + windowed scenario that clicks the real
   `Use_<sid>_<uid>` button (see the two `ork11e_hit_em_harder_*` scenarios).

### 6.4 UI node paths

- Window dialog: `/root/StratagemDialog/Content/Header` (e.g. "Boyz has been selected to
  fight"), `/root/StratagemDialog/Content/StratScroll/StratList/Card_<sid>/Buttons/Use_<sid>_<uid>[_<variant>]`,
  `/root/StratagemDialog/Content/DeclineButton`, `/root/StratagemDialog/Content/DontOfferAgainButton`,
  examine toggle `Content/ExamineBoard/ExamineBoardToggle`. `<sid>` = stratagem id through
  `validate_node_name()` (HIT 'EM HARDER: `faction_ork_war_horde_hit_em_harder`).
- Secondary picks: `/root/StratagemTargetDialog/Content/Pick_<id>` (units) or
  `/root/StratagemChoiceDialog/Content/Choice_<id>`; Cancel re-opens the window dialog.
- Hot-seat: when the decider is not the active player the MA-42 overlay shows
  "Player N (<faction>) — stratagem decision" (`Main.show_reactive_stratagem_waiting(name, decider)`).
  Networked: dialog only on the decider's machine, overlay on the other.

### 6.5 Scenario notes

- The fixtures load into the Command phase, so CP at the Fight phase is fixture CP + 1 (7).
- `transition_to_phase` builds the FightSequencer at phase entry; Fights First set
  afterwards does not change who picks first. Set such flags in the Charge phase and
  `END_CHARGE` into the Fight phase (as `ork11e_hit_em_harder_opponent_turn` does). In the
  reactive fixture the end of the Custodes' Charge phase offers the Orks Heroic
  Intervention — decline it (`/root/HeroicInterventionDialog/Content/Buttons/DeclineButton`).
- Pile In: pass both halves (`PileInStepPanel/EndPileInButton`) before selecting fighters.
- Multiline `execute_script` has `tree`/`node`, not `main`.

### 6.6 Fixtures

Regenerate with `godot --headless --path 40k -s tests/helpers/gen_ork11e_fixtures.gd`
(optional `-- --only=<name>`); it writes `user://saves` and copies into `40k/tests/saves/`.
Both are 11e, battle round 2, Command phase, CP 6 each, every unit DEPLOYED with no flags,
on the test-only EMPTY terrain layout `terrain_layouts/test_open_field.json` (not in
`index_11e.json`, never offered in menus — ranges, LoS and engagement are exact; add
cover in a scenario if needed). Objectives: shell `mirror_custodes_postdeploy`
(`obj_center` (22,30)", `obj_nml_1` (10,22)", `obj_nml_2` (34,38)", `obj_home_1` (22,4)",
`obj_home_2` (22,56)"). The generator refuses to write unless every unit is coherent, on
the board, the five pairs below are engaged and every other unit is unengaged.

- `ork11e_orks_active`: P1 = Orks `ork11e_codex_test` (War Horde, 22 units) **active**;
  P2 = Adeptus Custodes `custodes_lions` (11 units). Orks hold the top half (small y).
- `ork11e_orks_reactive`: P2 = the same Orks (non-active), P1 = Custodes **active**; the
  same battlefield rotated 180° about the board centre ((x,y) → (44-x, 60-y)), so the
  Orks hold the bottom half and every unit keeps its objective relationships.

Placement (inches, `ork11e_orks_active` orientation; centre x / front-edge y; rows
extend away from the opposing side). Attached: **U_WARBOSS_A → U_BOYZ_B**.

| band | Ork unit (P1) | at | engaged with (P2) | at |
|---|---|---|---|---|
| A, line y=30 | U_NOBZ_A (5) | 8 / 29.5 | U_CUSTODIAN_GUARD_B (5) | 8 / 30.5 |
| A | U_BOYZ_B (10) + U_WARBOSS_A behind | 22 / 29.5 (Warboss 22 / 26.6) — on obj_center | U_CUSTODIAN_GUARD_A (5) | 22 / 30.5 |
| A | U_MEGANOBZ_A (3) | 36 / 29.5 | U_BLADE_CHAMPION_A | 36 / 30.5 |
| B, line y=21 (Ork half) | U_DEFF_DREAD_A | 14 / 20.5 | U_PROSECUTORS_A (4) | 14 / 21.5 |
| B | U_BEAST_SNAGGA_BOYZ_A (10) | 30 / 20.5 | U_ALLARUS_CUSTODIANS_A (5) | 30 / 21.5 |

Unengaged Orks (> 2" from every enemy): rank R1 front y=16.5 — U_FLASH_GITZ_A x4,
U_TANKBUSTAS_A x10, U_BREAKA_BOYZ_A x16, U_KOMMANDOS_A x22.5, U_STORMBOYZ_A x38;
rank R2 front y=12.5 — U_GRETCHIN_C x4 (U_RUNTHERD_A behind, x4 front 10.1, not
attached), U_GRETCHIN_D x10.5, U_MEK_GUNZ_A x15.5, U_KILLA_KANS_A x20, U_DEFFKOPTAS_A x29,
U_WARBIKERS_A x39; vehicles front y=8.5 — U_BATTLEWAGON_A x9.5, U_TRUKK_A x17.5,
U_RUKKATRUKK_SQUIGBUGGIES_A x25, U_DAKKAJET_A x32.
Unengaged Custodes: U_CUSTODIAN_GUARD_C x8 / U_CUSTODIAN_GUARD_D x22 /
U_CUSTODIAN_GUARD_E x36 (front y=38), U_BLADE_CHAMPION_B x15 / U_BLADE_CHAMPION_C x29
(front y=37), U_CUSTODIAN_GUARD_F x22 (front y=45) — 6–15" from the Ork band A line
(charge range), 13–25" from the Ork rear ranks (shooting range).
Reposition with `execute_script` (e.g. move a unit's `models[i].position`) when a test
needs a different geometry.

### 6.7 Framework rules added by the fix pass (cluster A) and known limitations

Regression checks: `tests/test_ork_codex_framework_fixes.gd` (one section per finding).

- **Phase completion waits for windows (F1).** `BasePhase.execute_action` does not emit
  `phase_completed` while `_window_blocks_phase_completion()` (a pending window, a queued
  window, `_window_followup_pending`, or `get_pending_stratagem_window_decider() > 0`); the
  phase completes on the action that answers the last of them (e.g. GRAB IT after the last
  shooter). The S panel's Use path is refused during a window *or* a follow-up (F14).
- **Who may act during a window (F3 / AI-04 / AI-05).** `BasePhase.allows_cross_turn_action`
  lets the window decider (or follow-up owner) pass NetworkManager's "Not your turn" layer;
  `MovementPhase` additionally allows the reactive-move owner's move actions on that unit.
  The follow-up gate refuses any other player ("Player N is making this … move"). In
  hot-seat `NetworkIntegration.route_action` stamps `action.player` with the decider.
- **Networking (F4).** Windows and event detection are host-only: a client never opens a
  window, snapshots an event baseline or holds Deadly Demise. The host's state reaches the
  client in the action result (`stratagem_window_opened`, `_ork11e_followup` → mirrored
  by `NetworkManager._mirror_host_window_state` / `_apply_followup_mirror`). When either
  army has window stratagems, `END_MOVEMENT` / `END_FIGHT` are not executed optimistically
  on the client (they may open a window instead of ending the phase).
- **Pre-applied save casualties (LIVE-1 / F2).** The save overlay writes casualties into
  GameState before `APPLY_SAVES` / `APPLY_MELEE_SAVES` arrives; those two actions diff
  against the baseline taken before the overlay (`_EV_PREAPPLIED_ACTIONS`), so
  `unit_destroyed`, held Deadly Demise and `enemy_unit_has_attacked` still open. The
  overlay refuses "Roll Saves" for a further batch while a window is pending.
- **Event order (F10).** A post-shot window (`unit_has_shot`, …) first runs event
  detection, so the windows of units the shot destroyed open before it.
- **AI seats (AI-01 … AI-07).** `AIPlayer` answers a window or follow-up owned by an AI
  seat even when that seat was taken over mid-decision (disconnect → "continue vs AI");
  the watchdog counts such a seat as active. A human defender's dialog that is on screen
  (or being examined) is not a stall.
- **Save / load (F11) — limitation.** Window state is *not* saved: `_window_pending`,
  `_window_queue`, `_window_followup_pending` / the follow-up dicts, `_window_suppressed`
  ("don't offer again") and a held Deadly Demise live on the phase instance only. Loading
  a save made while a window or follow-up was open builds a fresh phase instance with
  nothing pending, so the game is never stuck (test section L). A window whose trigger was
  not committed (e.g. `unit_selected_to_fight` before the fighter was locked in) is
  offered again when the action is repeated; a follow-up that started after its CP was
  paid (GRAB IT / SCARPER! move, READIED BRAWLERS disembark, …) is lost — the CP stays spent.
- **UI.** The StratagemDialog grows its card list to the content (up to the room under the
  top HUD) and scrolls the first Use button into view when it still has to scroll
  (`first_use_button()`, `use_buttons_visibility()`); a "+1CP Or:" upgrade is printed as
  its own "Upgrade (+1 CP) — instead: …" line and its button names unit and cost;
  variant-only cards say "Choose one"; the game log names the chosen variant. Secondary
  pickers (`StratagemTargetDialog` / `StratagemChoiceDialog`) show their instruction as
  `Content/Prompt` (title = stratagem name) and objectives by their board names
  ("CENTER [NML]"). The hot-seat waiting banner sits under the top HUD strip; the fight
  dock says "Waiting for Player N's stratagem decision" while an
  `enemy_targets_unit_fight` window holds the hit roll.

## 7. Final state (2026-10-13)

### 7.1 What shipped

- **Data:** `@alpaca-software/40kdc-data` 1.4.5 with ORK-only CSV splices (§1). The
  40 Ork stratagem rows come from `scripts/40kdc/curated/orks_codex_11e.json`, carry
  `effects_json = [{"type":"custom:ork11e"}]` and the `window` column, and belong to
  the 15 codex detachments. More Dakka!, Freebooter Krew, Rollin' Deff and
  Speedwaaagh! are gone; army files, AI plans and test saves were migrated
  (`.llm/ork_codex_11e_retired_tests.md`). Local keyword patches
  (`scripts/40kdc/local-patches.mjs` patch 4): Trukk gains SPEED FREEKS, Deffkoptas
  VEHICLE → MOUNTED, Big Mek Dakkarig gains VEHICLE, Mozrog Skragbad and Beastboss on
  Squigosaur MOUNTED → MONSTER.
- **All 40 codex stratagems are implemented** (the group scripts' `IMPLEMENTED`
  lists): Fight 9 (HIT 'EM HARDER, MOW 'EM DOWN, UNBRIDLED CARNAGE, ARMED TO DA TEEF,
  ORKS IS NEVER BEATEN, TOO ARROGANT TO DIE, CRAZED RAMPAGE, KEEP IT RUNNIN',
  INSTINCTIVE HUNTERS); Shooting 8 (CLOSE-RANGE DAKKA, VINDICTIVE ARTILLERISTS,
  DRIVE-BY BUSTIN', KUSTOM DAKKA, GLOWIN' DAKKA, NEVER ENOUGH DAKKA, LONG UNCONTROLLED
  BURSTS, DAKKASTORM); Shooting-reactive 6 (GRAB IT, GROT SHIELDS, HULKING BRUTES,
  SPEEDIEST FREEKS, GUN-CRAZY SHOW-OFFS, GOADED INTO ACTION); Movement 12
  (FUNGUS-FUEL INJECTION, 'ERE WE GO, STOMPING JUGGERNAUT, MIND MOSTLY ON THE MISSION,
  DUBIOUS RESTRAINT, READIED BRAWLERS, SCARPER!, WHIRLIGIG EVASION, WHERE D'YA FINK
  YOU'RE GOING?, WHILE THEIR BACKS ARE TURNED, DREAD POWER, DELICIOUS EATING SQUIGS);
  Other 5 (MOB MENTALITY, BREAKIN' HEADS, IMPENDING KRUNCH, FLYIN' HEADBUTT, INFESTED
  WAR ZONE). 38 are offered in their windows; DREAD POWER and DELICIOUS EATING SQUIGS
  are S-panel stratagems with a friendly-target picker.
- **Windows (all 19 of §3 are hooked):** `battle_shock_step_start` (CommandPhase),
  `unit_battle_shocked` / `unit_destroyed` / `enemy_unit_has_attacked` (BasePhase
  event detection around each outermost action; Deadly Demise held while the owner
  has a `unit_destroyed` offer), `movement_phase_start`, `movement_phase_end`,
  `unit_selected_to_move`, `unit_ended_normal_move`, `enemy_ended_move`,
  `enemy_selected_to_fall_back` (MovementPhase), `unit_selected_to_shoot`,
  `unit_has_shot`, `enemy_has_shot` and the `enemy_targets_unit_shooting` fold-in
  (ShootingPhase), `unit_declares_charge`, `unit_ended_charge_move` (ChargePhase),
  `unit_selected_to_fight`, `enemy_targets_unit_fight`, `fight_phase_end`
  (FightPhase).
- **Follow-ups (all 7 of §3.2):** `reactive_normal_move` (MovementPhase for SCARPER! /
  WHIRLIGIG EVASION / WHILE THEIR BACKS ARE TURNED; ShootingPhase for GRAB IT, with
  `Ork11eReactiveMovePanel`), `surge_move` (GOADED INTO ACTION), `shoot` (GUN-CRAZY
  SHOW-OFFS, auto-resolved), `embark` (KEEP IT RUNNIN'), `assault_disembark` (READIED
  BRAWLERS, plus `SKIP_ASSAULT_DISEMBARK`), `strategic_reserves` (INSTINCTIVE HUNTERS),
  `new_reserve_unit` (INFESTED WAR ZONE, `BasePhase._followup_new_reserve_unit`).
  Plus the Fight On Death mechanic (ORKS IS NEVER BEATEN / TOO ARROGANT TO DIE /
  CRAZED RAMPAGE) in FightPhase + AllocationGroupOverlay.
- **Framework:** BasePhase windows + queue + follow-ups, `USE/DECLINE_WINDOW_STRATAGEM`,
  "Don't offer again this phase", AI decider (`AIDecisionMaker.decide_window_stratagem`,
  synchronous), AI takeover of a pending window/follow-up, network plumbing
  (host-only windows, mirrored to the client), StratagemDialog window mode (§6.4),
  the fix-pass rules of §6.7.
- **Engine fixes made on the way** (outside the codex but needed by it): granted
  [HAZARDOUS] now rolls; signed 11e AP for every "+N AP" site (`improve_ap` /
  `worsen_ap`); per-turn charge flags reset at END_SCORING for the player whose turn
  ended; MOBILE honoured by the charge climb penalty (13.06); disembark "wholly
  within 3""; kill credit to the destroyed unit's opponent; Deadly Demise in the
  Movement/Charge/Command phases; Command Re-roll checked per unit (15.01); the 10e
  Waaagh! +1 A / +1 S melee bonus gated to edition < 11; Ctrl+A no longer pans the
  camera.

### 7.2 Rulings made by the implementers

Framework-wide:
- Window order: the active player's window first, then the opponent's (phase start /
  end, post-shot). A `unit_selected_to_*` window is offered again when the player
  selects another unit and comes back; an uncommitted trigger re-offers its window.
- Windows stay closed while a tutorial lesson is active or loading.
- Codex windows open ahead of the legacy Swift as the Eagle / Go Get 'Em! / Wazblasta
  prompts, which wait behind them.
- Reactive moves set no persistent "has moved" flags.
- Keyword checks look at the whole Attached unit; TITANIC is excluded wherever the
  text says so.
- Sustained Hits 1 from a stratagem applies only when the weapon has no Sustained
  Hits of its own (11e duplicates do not stack).
- Overwatch: no codex consumers (snap-shot hits are never critical and get no
  re-rolls; the effects expire at the end of your own Shooting phase).
- Kill credit goes to the destroyed unit's opponent; a Fight On Death removal is
  credited to the destroying attacker; a unit destroyed by its own Hazardous roll
  credits the opponent (not checked against an official ruling).
- Fight On Death: "selected to fight" = SELECT_FIGHTER (cancelling undoes it); "has
  fought" = its activation finished; kept models are alive at 0 W, still fight, take
  no further allocation, and are removed when the unit has fought or at the end of
  the phase (before `fight_phase_end`); destruction-triggered rules (kill credit,
  Deadly Demise) resolve at removal.

Per stratagem:
- **HIT 'EM HARDER:** melee [LETHAL HITS] on every component of an Attached unit.
- **MOW 'EM DOWN:** a weapon without [CLEAVE] gains CLEAVE 1, otherwise +1; kept Fight
  On Death models still count for the Cleave target count; [CLEAVE] counts the whole
  attached target unit.
- **UNBRIDLED CARNAGE / MOW 'EM DOWN:** "made a charge move this turn" reads
  `charged_this_turn`, which is now reset when the turn ends.
- **ARMED TO DA TEEF:** offered in both the shoot and fight windows; riled up = re-roll
  failed hits, with an optional "non-critical hits too" variant (re-roll any
  non-critical hit) only for weapons with lethal/sustained hits; never downgrades an
  existing re-roll and restores it on expiry; riled-up status is read at use.
- **ORKS IS NEVER BEATEN / TOO ARROGANT TO DIE:** +1 to the Fight On Death roll if
  riled up; not offered for a unit already selected to fight this phase.
- **CRAZED RAMPAGE:** +3 for a DEFF DREAD, no riled-up bonus.
- **KEEP IT RUNNIN':** "able to embark" = the 18.02 conditions minus the 3"; "wholly
  within 6"" = edge distance + base size; with 2+ eligible Trukks the player picks one;
  writes `embarked_this_phase`; the AI does not use it on a unit holding an objective.
- **INSTINCTIVE HUNTERS:** every model's position is cleared; the unit is spared by the
  end-of-battle-round-3 reserves cull (`repositioned_to_reserves`).
- **CLOSE-RANGE DAKKA:** the +1 applies after other Rapid Fire grants (0 → 1); half
  range counts attached leaders.
- **VINDICTIVE ARTILLERISTS:** one of the three options must be picked (no plain Use).
- **DRIVE-BY BUSTIN':** +1 to hit per attack in mixed hull / Firing Deck batches; not
  offered when no Firing Deck weapon can be selected.
- **GLOWIN' DAKKA:** 9" measured unit to unit (closest models), Attached units as a
  whole; the AP improvement is signed (0 → −1).
- **LONG, UNCONTROLLED BURSTS:** re-roll failed hits against FLY targets only.
- **GROT SHIELDS:** targets the Gretchin unit (15.01 / battle-shock); the shielded unit
  is a secondary pick (most valuable candidate when none is picked or the AI
  decides); 3" is group-aware; critical hits are intercepted first, Sustained extras
  of intercepted hits are dropped, Torrent is never intercepted.
- **GRAB IT:** offered only with an objective (including terrain-hosted objective
  areas) within 6"; its charge lock cannot be overridden.
- **GUN-CRAZY SHOW-OFFS:** offered only if a weapon can target the attacker; resolved
  automatically (every eligible ranged weapon fires, best profile per weapon, saves
  auto-rolled); the unit is not marked as having shot; Hunter profiles fall back to
  MONSTER/VEHICLE targets.
- **GOADED INTO ACTION:** the surge target must be on the battlefield and not embarked;
  AIRCRAFT are ignored unless the unit can FLY; an out-of-coherency unit is offered it
  only if a 6" surge can restore coherency.
- **HULKING BRUTES:** "+1CP Or" is a variant button (2 CP).
- **'ERE WE GO:** offered only for advance moves. **MIND MOSTLY ON THE MISSION:** only
  for advance and fall-back moves.
- **DUBIOUS RESTRAINT:** lists only objectives the unit controls that its army has not
  already secured; only end-of-phase objective checks can break a secured objective.
- **DELICIOUS EATING SQUIGS:** heals EVERY eligible ORKS INFANTRY unit within 3"
  (needs at least one); 02.02.04 revives dead non-CHARACTER models, set up in
  coherency (01.02.03) after a Confirm/Cancel preview.
- **READIED BRAWLERS:** needs at least one embarked unit eligible to disembark; units
  disembark at once, one at a time.
- **SCARPER! / WHIRLIGIG EVASION:** the 6" alternative is used whenever its condition
  holds, otherwise one D6.
- **WHERE D'YA FINK YOU'RE GOING?:** forces desperate escape; three extra hazard rolls
  per engaged BEAST SNAGGA unit, the −1 applies to those extra rolls only.
- **DREAD POWER:** riled up until the Orks' next Command phase = Waaagh! state, 5+
  invulnerable save, advance-and-charge, ranged [ASSAULT].
- **STOMPING JUGGERNAUT:** MOBILE is honoured by the Movement and Charge terrain checks
  (no climb cost through dense terrain, 13.06).
- **`enemy_ended_move`** fires after CONFIRM_UNIT_MOVE, a disembark move and a
  reinforcement set-up; **`unit_ended_normal_move`** opens before Overwatch (01.03.02).
- **MOB MENTALITY:** Attached models count towards 13+; the selected unit may be the
  target itself; only units that must take a battle-shock roll this step are listed;
  the window opens when the Battle-shock step starts (roll call, first test or End
  Command).
- **BREAKIN' HEADS:** "attached" = has a living attached CHARACTER; also offered after
  End Command auto-resolves a failed test.
- **IMPENDING KRUNCH:** uses the out-of-Command-phase battle-shock roll (2D6 vs
  effective Ld, −1); a failure opens the owner's `unit_battle_shocked` window (nested).
- **FLYIN' HEADBUTT:** 12" is measured from the destroyed models; usable with no enemy
  within 12" (removes Deadly Demise, no dice).
- **INFESTED WAR ZONE:** "just destroyed" = destroyed by that enemy unit's attacks; only
  the GRETCHIN unit is copied (not an attached CHARACTER), as a fresh unit at full
  strength in Strategic Reserves.

### 7.3 Known limitations / deferred

- **Two-peer network play is not validated live.** Windows, follow-ups and the
  reactive moves are host-only and mirrored to the client (§6.7), covered headless
  only; the client still runs some other actions ahead of the host and can briefly
  show stale state (e.g. CP).
- **Mirror match, same detachment:** stratagem ids are faction + detachment scoped
  and `get_stratagem_owner` returns the first player listing an id, so only P1 can
  use codex stratagems (P2 gets no offers, rows or AI uses; no error, no stall).
  Reloading one player's detachment also erases definitions the other still lists.
- **Waaagh! optional advance re-roll is not offered** (r2:F1 part deferred): an
  automatic re-roll broke the T3 tutorial's Command Re-roll lesson; the correct form
  is an optional free re-roll in the advance dialog.
- **Pending window / follow-up state is not saved** (§6.7 F11): loading drops it; a
  follow-up that started after its CP was paid is lost and the CP stays spent.
- **Detachment rules and enhancements of the new detachments are not implemented.**
  The 10e rule/enhancement code still runs for the names it knows; the More Dakka! /
  Rollin' Deff / Speedwaaagh! helpers stay in the code but no shipped detachment
  reaches them.
- **Non-Ork 1.4.5 stratagem changes are not applied** (CSV splices are ORK-only, §1).
- **The web builder is still on the 1.0.19 bundle** (`server/public/js/vendor/40kdc-data.mjs`):
  the server round-trip test reports mismatches for the migrated armies and
  `ork11e_codex_test.json` (RG-F5) until `bundle-browser` is re-run for 1.4.5.
- **The AI uses only some codex stratagems.** In 28 AI-vs-AI games it used 14 of the
  40 (AI-08); after the movement tuning FUNGUS-FUEL INJECTION is used and SCARPER! /
  WHIRLIGIG EVASION only against units that can still charge. STOMPING JUGGERNAUT and
  MIND MOSTLY ON THE MISSION score 0 by design; DRIVE-BY BUSTIN' is dead for the AI
  (it does not plan Firing Deck weapons); the HULKING BRUTES upgrade is never picked.
  Several follow-ups (GOADED surge, READIED BRAWLERS, INFESTED WAR ZONE, KEEP IT
  RUNNIN', INSTINCTIVE HUNTERS) are exercised for the AI headless only.
- Smaller items: overwatch has no codex consumers (ruling above); ordinary shooting
  still does not enforce the 24.07 close-quarters either/or (only GUN-CRAZY's forced
  picker does); an already re-rolled die still looks clickable (the re-roll is
  refused before CP is spent); the round-base vs curved-hull "wholly within" check can
  slightly over-estimate; secured objectives and the Ammo Runt / Swift as the Eagle /
  Wazblasta prompts are pre-existing gaps; the multiplayer GUT harness race in
  `TestModeHandler._check_for_commands` (RG-F7) is unfixed; the legacy 10e Ork
  handlers are still in StratagemManager but no codex row can reach them (dispatch is
  by csv_id).
- Coverage: `autoloads.FactionStratagemLoader.curated_effects` and
  `autoloads.EffectPrimitives.minus_one_wound_defense` stay `uncovered` (no ork11e
  scenario exercises them; see the retired-tests doc).

### 7.4 Test inventory

Headless (`40k/tests/`, all in `run_pretrigger_tests.sh`, `GameState.set_edition(11)`):

| file | covers | passed/failed (2026-10-13 pretrigger run: 4393/0 over 132 files) |
|---|---|---|
| `test_ork_codex_11e_data.gd` | curated rows, window column, detachment match, legacy kits, keyword patches | 94/0 |
| `test_ork_codex_framework.gd` | window framework + HIT 'EM HARDER | 105/0 |
| `test_ork_codex_framework_fixes.gd` | cluster A fixes (overlay deaths, cross-turn actions, network mirror, phase completion, save/load, AI takeover, stale boot stratagems) | 108/0 |
| `test_ork_codex_fight.gd` | Fight group + Fight On Death + fight windows/follow-ups | 196/0 |
| `test_ork_codex_shooting.gd` | own-turn Shooting group + `unit_selected_to_shoot` | 237/0 |
| `test_ork_codex_shooting_reactive.gd` | reactive Shooting group, post-shot windows, follow-ups | 156/0 |
| `test_ork_codex_shooting_fixes.gd` | cluster B fixes (auto-select, kill credit, AP sign, Rapid Fire, GROT SHIELDS, re-rolls) | 110/0 |
| `test_ork_codex_movement.gd` | Movement group, movement windows, follow-ups, MOBILE, Waaagh! at 11e, DES revive | 285/0 |
| `test_ork_codex_other.gd` | Command / Charge / any-phase group + event windows | 197/0 |
| `test_ork_codex_turn_flow_fixes.gd` | cluster C fixes (charge flags, MOBILE charge, reserves ghost, disembark, fight/command stratagems) | 108/0 |
| `test_keybinding_chord_no_pan.gd` | Ctrl+A does not pan | 8/0 |
| `test_fullauto_faction_rules.gd` (rewritten) | War Horde codex rows | 42/0 |

Outside the pretrigger list: `test_ork_detachments_sweep.gd` (codex row load per
detachment + the surviving detachment-rule / enhancement checks, 194/0) and the GUT
`unit/test_faction_stratagems.gd` (War Horde rows, Epic Deed timing column). Fixture
generator: `tests/helpers/gen_ork11e_fixtures.gd`.

Windowed scenarios (`40k/tests/scenarios/sp/`, 63, real clicks):
- One or more per stratagem: `ork11e_hit_em_harder_own_turn`,
  `ork11e_hit_em_harder_opponent_turn`, `ork11e_mow_em_down`,
  `ork11e_unbridled_carnage`, `ork11e_armed_to_da_teef`, `ork11e_orks_is_never_beaten`,
  `ork11e_too_arrogant_to_die`, `ork11e_crazed_rampage`, `ork11e_keep_it_runnin`,
  `ork11e_instinctive_hunters`, `ork11e_close_range_dakka`,
  `ork11e_vindictive_artillerists`, `ork11e_drive_by_bustin`, `ork11e_kustom_dakka`,
  `ork11e_glowin_dakka`, `ork11e_never_enough_dakka`, `ork11e_long_uncontrolled_bursts`,
  `ork11e_dakkastorm`, `ork11e_dakkastorm_trukk`, `ork11e_grab_it`,
  `ork11e_grab_it_last_shooter`, `ork11e_auto_shoot_grab_it`, `ork11e_hulking_brutes`,
  `ork11e_speediest_freeks`, `ork11e_grot_shields`, `ork11e_gun_crazy_show_offs`,
  `ork11e_goaded_into_action`, `ork11e_fungus_fuel_injection`, `ork11e_ere_we_go`,
  `ork11e_stomping_juggernaut`, `ork11e_stomping_juggernaut_charge`,
  `ork11e_mind_mostly_on_the_mission`, `ork11e_dubious_restraint`,
  `ork11e_readied_brawlers`, `ork11e_scarper`, `ork11e_scarper_after_disembark`,
  `ork11e_whirligig_evasion`, `ork11e_where_dya_fink`,
  `ork11e_while_their_backs_are_turned`, `ork11e_dread_power`,
  `ork11e_delicious_eating_squigs`, `ork11e_delicious_eating_squigs_after_move`,
  `ork11e_mob_mentality`, `ork11e_breakin_heads`, `ork11e_impending_krunch`,
  `ork11e_flyin_headbutt`, `ork11e_flyin_headbutt_defender_saves`,
  `ork11e_flyin_headbutt_ai_attacker_defender_saves`, `ork11e_infested_war_zone`,
  `ork11e_infested_war_zone_defender_saves`,
  `ork11e_infested_war_zone_melee_defender_saves`.
- Framework / AI / UI: `ork11e_reactive_core_then_codex`,
  `ork11e_reactive_dont_offer_again`, `ork11e_ai_selected_to_shoot`,
  `ork11e_ai_attacker_reactive_dialog_shown`, `ork11e_ai_takeover_pending_window`,
  `ork11e_ai_takeover_pending_followup`, `ork11e_autoselect_first_shooter`,
  `ork11e_autoselect_prompt_no_recursion`, `ork11e_no_stale_boot_stratagems`,
  `ork11e_charge_flags_end_of_turn`, `ork11e_waaagh_riled_up_11e`,
  `ork11e_ctrl_a_select_all_no_pan`.
- Existing scenarios adapted: `shoot_quick_assign_rejected_no_crash`,
  `fullauto_movement_stratagems`, `recon_stomps_base_army`,
  `taktikal_enhancements_load`, `iss058_disembark_11e`, `tut_t3_get_movin(_pad)`, and
  (RG-F1) `aao_lions_isolated_plus_one`, `cover_hit_label_wound_reroll_11e`,
  `game_log_armour_saves_11e`, `game_log_armour_saves_no_kill_11e`.
