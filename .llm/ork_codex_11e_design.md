# Codex: Orks (11th edition) stratagems — design contract

Status: design for branch `claude/bold-pasteur-45wgjz` (2026-10-11).
Audience: every agent implementing or validating this work. Read it all before
touching code. Where this doc and older code comments disagree, this doc wins.

## 0. Goal

1. Move the game's data to `@alpaca-software/40kdc-data` **1.4.5** (from 1.0.19).
2. Ship all **43** stratagems of the 11th-edition Codex: Orks (15 detachments) with
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

## 2. The 43 stratagems (source of truth: `scripts/40kdc/curated/orks_codex_11e.json`)

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
Taktikal Brigade 3, Wurrband 0, Brute Bosses 0 = 43.)

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
| enemy_ended_move | after CONFIRM_UNIT_MOVE of any move by the active player's unit (after overwatch/other existing reactive prompts) | non-active | `enemy_unit_id`, `move_type` |
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
  `OrkCodexFight.gd`, `OrkCodexShooting.gd`, `OrkCodexMovement.gd`,
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
fixtures. Every other hook point and stratagem is for the group agents.

### 6.1 Files

| file | role |
|---|---|
| `40k/scripts/stratagems/ork_codex/OrkCodex11e.gd` | dispatcher (`class_name OrkCodex11e`, static); StratagemManager / AIDecisionMaker **preload** it (no class-cache dependency) |
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
