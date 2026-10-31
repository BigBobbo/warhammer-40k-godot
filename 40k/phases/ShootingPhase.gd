extends BasePhase
class_name ShootingPhase

const BasePhase = preload("res://phases/BasePhase.gd")
# WP-O6: Codex: Orks (11e) datasheet abilities (post-shot effects).
const OrkAbilities11eScript = preload("res://scripts/codex/orks/OrkAbilities11e.gd")
# Codex: Orks (11e) detachment rules (WP-O34): Unpredictable Genius, Try Dat Button! lifecycle.
const Ork11eDetachments = preload("res://scripts/codex/orks/OrkDetachments11e.gd")


# ShootingPhase - Full implementation of the Shooting phase following 10e rules
# Supports: Target selection, weapon assignment, attack resolution, damage allocation

signal unit_selected_for_shooting(unit_id: String)
signal targets_available(unit_id: String, eligible_targets: Dictionary)
signal shooting_begun(unit_id: String)
signal shooting_resolved(unit_id: String, target_unit_id: String, result: Dictionary)
signal dice_rolled(dice_data: Dictionary)
signal saves_required(save_data_list: Array)  # For interactive save resolution
signal weapon_order_required(assignments: Array)  # For weapon ordering when 2+ weapon types
signal weapon_order_cancelled(shooter_id: String)  # T06: CANCEL_WEAPON_ORDER handed the declaration back for editing
signal next_weapon_confirmation_required(remaining_weapons: Array, current_index: int, last_weapon_result: Dictionary)  # For sequential resolution pause
signal shooting_stage_paused(stage: String, info: Dictionary)  # Staged sequential: "hits" or "wounds" pause reached (drives WeaponOrderDialog buttons + Command Re-roll)
signal reactive_stratagem_opportunity(defending_player: int, available_stratagems: Array, target_unit_ids: Array)  # For opponent reactive stratagems
signal grenade_result(result: Dictionary)  # For grenade stratagem result display
signal command_reroll_opportunity(unit_id: String, player: int, roll_context: Dictionary)  # For Command Re-roll on save rolls (future expansion)
signal shooting_damage_applied(shooter_id: String, diffs: Array)  # T7-53: For floating damage numbers after saves resolved
signal ai_shooting_visual(shooter_id: String, target_data: Array, result_summary: Dictionary)  # T7-38: AI shooting targeting line + result text
signal throat_slittas_available(unit_id: String, player: int, eligible_targets: Array)  # P1-12: Throat Slittas mortal wounds prompt
signal throat_slittas_result(unit_id: String, results: Dictionary)  # P1-12: Throat Slittas resolution result

# Shooting state tracking
var active_shooter_id: String = ""
# ISS-048 step 2: the 11e shooting type selected for the active shooter
# ("normal"/"assault"/"close_quarters"/"indirect"/"snap"); "" at 10e.
var active_shooting_type: String = ""
var pending_assignments: Array = []  # Weapon assignments before confirmation
var confirmed_assignments: Array = []  # Assignments ready to resolve
var resolution_state: Dictionary = {}  # State for step-by-step resolution
# T06 (design guidelines §3): the weapon-order step (resolution_state.phase
# "awaiting_weapon_order") can be backed out of with CANCEL_WEAPON_ORDER — the
# panel's Esc. These hold the declaration exactly as the player made it at
# CONFIRM_TARGETS (before the merge and the Extra Attacks injection), the
# per-player stratagem-use counts at that moment, and the reason it got locked
# in since (a die rolled for it), so nothing the opponent reacted to can be
# taken back. See weapon_order_cancel_block_reason().
var _wo_declared_assignments: Array = []
var _wo_usage_mark: Array = []
var _wo_lock_reason: String = ""
var dice_log: Array = []
var units_that_shot: Array = []  # Track which units have completed shooting
var phase_shooting_log: Array = []  # T5-UX9: Per-weapon shot summaries persisted across all units in this phase
                                    # Each entry: {shooter_unit_id, shooter_unit_name, weapon_id, weapon_name,
                                    # target_unit_id, target_unit_name, hits, total_attacks, wounds, saves_failed, casualties}
var pending_save_data: Array = []  # Save data awaiting resolution
var pending_hazardous_weapons: Array = []  # HAZARDOUS (T2-3): Weapons needing post-save hazardous check
var pending_one_shot_diffs: Array = []  # ONE SHOT (T4-2): Diffs to mark one-shot weapons as fired
var awaiting_reactive_stratagem: bool = false  # True when waiting for defender stratagem decision
var throat_slittas_pending_unit: String = ""  # P1-12: Unit awaiting Throat Slittas decision
var _targets_hit_by_shooter: Dictionary = {}  # P1-11: Track which enemy units were hit { target_unit_id: hit_count } (post-shot "hit by those attacks")
var _rng = RulesEngine.make_rng()  # P1-11: RNG for battle-shock tests (issue #329: routes through test_mode_seed)
# Issue #386 Big Booms: queued struck-unit IDs from a supa-kannon target selection.
# Resolved after the supa-kannon's attacks against the chosen target finish; D3 MW per struck unit.
var _big_booms_pending: Array = []  # entries: {target_unit_id: String, struck_unit_ids: Array, rolls: Array}
var swift_as_eagle_pending_unit: String = ""
var swift_as_eagle_move_inches: int = 0
var awaiting_swift_as_eagle: bool = false
# The reactive post-shooting-move scaffolding serves SWIFT AS THE EAGLE
# (Lions of the Emperor) and GO GET 'EM! (Green Tide).
var swift_as_eagle_pending_strat: String = "SWIFT AS THE EAGLE"
# (WP-O5: the 10e Kult of Speed Wazblasta post-shooting move is gone — Codex:
# Orks Kult of Speed has Smoky Gubbinz / Competitive Streak.)
# Stratagem window unit_selected_to_shoot (design .llm/ork_codex_11e_design.md
# §3): the unit the window has already been opened for in the CURRENT
# selection, so re-entrant select calls (resume, Throat Slittas decline, the
# atomic SHOOT's inner select) never offer it twice for one selection.
var _sts_window_handled_unit: String = ""
# LV-2 / RV-4: a unit the ShootingController selected AUTOMATICALLY (phase
# entry / next shooter, payload.auto_selected) has not been chosen by the
# player yet, so its unit_selected_to_shoot window is deferred: it opens before
# the first action the player takes with that shooter (_STS_DEFERRED_TRIGGERS,
# or the atomic SHOOT's inner select) and that action is applied once the
# window closes. Only one offer per selection; "Don't offer again" still wins.
var _sts_window_deferred_unit: String = ""
# The unit whose selected-to-shoot window was answered with a USED stratagem in
# the current selection — an explicit re-selection of a unit whose window was
# merely declined is a new selection and is offered again; a used one is not.
var _sts_window_used_unit: String = ""
const _STS_DEFERRED_TRIGGERS := ["ASSIGN_TARGET", "CONFIRM_TARGETS", "RESOLVE_SHOOTING"]
# The rest of a burst of player assignments (quick-assign ALL, Apply to All …)
# whose FIRST ASSIGN_TARGET opened the deferred window: held while it is
# pending (instead of "Waiting for … to decide" rejections) and applied, in
# order, right after the held first action once the window closes.
var _sts_held_actions: Array = []
# AI (synchronous) window diffs produced inside the atomic SHOOT's inner
# select — merged into the SHOOT result so replay / network see the CP spend.
var _sts_carry_diffs: Array = []
# unit_id -> true once _check_kill_diffs processed its destruction this phase
# (framework F12): the same alive=false diffs can reach the kill hook twice —
# e.g. the AI-atomic interactive-saves flow returns the ACCUMULATED changes of
# every APPLY_SAVES — and a second pass double-counts the kill and re-rolls
# Deadly Demise. Same guard as FightPhase._kill_reported_units.
var _kill_reported_units: Dictionary = {}

# PERF-LOS: per-snapshot eligible-target cache. get_eligible_targets() runs a
# base-aware line-of-sight sweep over every enemy unit × weapon × model-pair —
# seconds of work on a full board. The "Select Shooter" list filter calls it for
# EVERY friendly unit, and _refresh_unit_list() re-runs on phase entry AND after
# every target assignment, so without a cache the player paid that sweep again on
# every single click (the reported multi-second pause). Eligibility is a pure
# function of the current game_state_snapshot. Validity is keyed on BOTH the
# snapshot's object identity (a fresh snapshot at any of the ~16 reassignment
# sites invalidates everything) AND a content fingerprint of model positions /
# alive / engagement (so an IN-PLACE mutation of the snapshot — which does not
# change the object reference — still invalidates). See _eligibility_fingerprint.
var _eligible_targets_cache: Dictionary = {}
# PERF-LOS: separate yes/no cache for the "can this unit shoot at all?" list
# filter. It uses the cheap first-match-only scan (stops at the first eligible
# target) rather than building the full map, so the phase-entry sweep over every
# unit is far cheaper. Shares the same invalidation.
var _has_targets_cache: Dictionary = {}
var _eligible_targets_cache_snapshot = null
# PERF-LOS: content fingerprint (model positions + alive) of the snapshot the
# caches were built against. Object identity alone is NOT enough: game_state_snapshot
# can be mutated IN PLACE (e.g. a unit repositioned, or the scenario runner poking
# model positions) without the object reference changing — that must still
# invalidate eligibility. Recomputing this is O(models) and trivially cheap next
# to the line-of-sight sweep it guards.
var _eligibility_cache_fingerprint: int = 0

func _init():
	phase_type = GameStateData.Phase.SHOOTING

# PERF-LOS: fingerprint every model's position + alive flag. Any change here can
# change who is targetable, so a different fingerprint must drop the caches.
func _eligibility_fingerprint() -> int:
	var units = game_state_snapshot.get("units", {}) if game_state_snapshot else {}
	var h: int = hash(units.size())
	for uid in units:
		var u = units[uid]
		h = h * 1000003 + hash(uid)
		for m in u.get("models", []):
			var pos = m.get("position", null)
			var px: float = 0.0
			var py: float = 0.0
			if pos is Dictionary:
				px = pos.get("x", 0.0); py = pos.get("y", 0.0)
			elif pos != null:
				px = pos.x; py = pos.y
			h = h * 1000003 + hash(px)
			h = h * 1000003 + hash(py)
			h = h * 1000003 + (1 if m.get("alive", true) else 0)
		# in_engagement gates which weapons may fire, so fold it in too.
		h = h * 1000003 + (1 if u.get("flags", {}).get("in_engagement", false) else 0)
	# Terrain gates line of sight, so a layout swap must also drop the caches.
	# Without this, a cache warmed against the boot-default layout survived a
	# fixture/save load that replaced the walls — a unit could be stuck at
	# "no eligible targets" (or the reverse) for the whole phase. Fold in each
	# piece's identity and position; wall edits ship as layout changes so
	# id+position is a sufficient proxy for the blocking geometry.
	var tm = get_node_or_null("/root/TerrainManager")
	if tm != null:
		h = h * 1000003 + hash(tm.terrain_features.size())
		for t in tm.terrain_features:
			h = h * 1000003 + hash(str(t.get("id", "")))
			h = h * 1000003 + hash(str(t.get("position", "")))
	return h

# PERF-LOS: drop both eligibility caches when the snapshot object OR its relevant
# content (positions / alive / engagement) changes.
func _ensure_eligibility_cache_fresh() -> void:
	var fp := _eligibility_fingerprint()
	if not is_same(_eligible_targets_cache_snapshot, game_state_snapshot) or fp != _eligibility_cache_fingerprint:
		_eligible_targets_cache.clear()
		_has_targets_cache.clear()
		_eligible_targets_cache_snapshot = game_state_snapshot
		_eligibility_cache_fingerprint = fp

# PERF-LOS: memoized full get_eligible_targets keyed on unit_id, valid while
# game_state_snapshot keeps the same object identity (see cache decl above).
func _cached_eligible_targets(unit_id: String) -> Dictionary:
	_ensure_eligibility_cache_fresh()
	# Return a deep copy: callers (e.g. the controller's live eligible_targets,
	# which it may .clear() on deselect) must never mutate the cached authority.
	# The eligible dict is small (one entry per eligible enemy unit), so the copy
	# cost is trivial next to the seconds of LoS work it saves.
	if _eligible_targets_cache.has(unit_id):
		return _eligible_targets_cache[unit_id].duplicate(true)
	var result = RulesEngine.get_eligible_targets(unit_id, game_state_snapshot)
	_eligible_targets_cache[unit_id] = result
	return result.duplicate(true)

# PERF-LOS: cached yes/no "does this unit have any eligible shooting target?"
# using the first-match-only early-out. Used by the Select-Shooter list filter,
# which is the hot per-unit path on phase entry and every UI refresh.
func _cached_has_eligible_target(unit_id: String) -> bool:
	_ensure_eligibility_cache_fresh()
	if _has_targets_cache.has(unit_id):
		return _has_targets_cache[unit_id]
	# If the full map was already computed (e.g. the unit was selected), reuse it.
	if _eligible_targets_cache.has(unit_id):
		var has_full: bool = not _eligible_targets_cache[unit_id].is_empty()
		_has_targets_cache[unit_id] = has_full
		return has_full
	var has_any: bool = not RulesEngine.get_eligible_targets(unit_id, game_state_snapshot, true).is_empty()
	_has_targets_cache[unit_id] = has_any
	return has_any

func _on_phase_enter() -> void:
	log_phase_message("Entering Shooting Phase")
	active_shooter_id = ""
	pending_assignments.clear()
	_big_booms_pending.clear()
	confirmed_assignments.clear()
	resolution_state.clear()
	dice_log.clear()
	units_that_shot.clear()
	phase_shooting_log.clear()  # T5-UX9: Reset per-phase shot summary log
	pending_hazardous_weapons.clear()
	pending_one_shot_diffs.clear()
	awaiting_reactive_stratagem = false
	throat_slittas_pending_unit = ""
	swift_as_eagle_pending_unit = ""
	swift_as_eagle_move_inches = 0
	awaiting_swift_as_eagle = false
	_targets_hit_by_shooter.clear()
	_kill_reported_units.clear()

	# Apply unit ability effects (leader abilities, always-on abilities)
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr:
		ability_mgr.on_phase_start(GameStateData.Phase.SHOOTING)

	# Refresh snapshot after ability effects mutated GameState flags
	game_state_snapshot = GameState.create_snapshot()

	# Compute in_engagement flags from actual model positions
	_compute_engagement_flags()

	_initialize_shooting()

func _on_phase_exit() -> void:
	log_phase_message("Exiting Shooting Phase")

	# TRY DAT BUTTON! (Dread Mob): Button Effects last until end of phase
	var fam_exit = get_node_or_null("/root/FactionAbilityManager")
	if fam_exit:
		fam_exit.clear_try_dat_flags("ranged")
	Ork11eDetachments.on_phase_end("shooting")  # Codex: Orks (11e) leftover Try Dat Button! / Unpredictable Genius flags (WP-O34)

	# CRITICAL: Clear all shooting visuals BEFORE controller is freed
	# This ensures range circles and other visuals are removed immediately
	_clear_shooting_visuals()

	# NEW: Clear death markers from board at phase end
	_clear_death_markers()

	# Clear shooting flags
	_clear_phase_flags()

	# Clear unit ability effect flags
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr:
		ability_mgr.on_phase_end(GameStateData.Phase.SHOOTING)

	# Clear stratagem flags (Go to Ground, Smokescreen effects expire at end of phase)
	_clear_stratagem_phase_flags()

	# Clear pending save data
	pending_save_data.clear()

	# P3-103: Recheck objective control at end of Shooting phase
	# Per 10e core rules: "A player controls an objective marker at the end of any phase or turn."
	# Units destroyed during shooting can change objective control state.
	if MissionManager:
		MissionManager.check_all_objectives()
		DebugLogger.info("ShootingPhase: P3-103 Updated objective control at end of Shooting phase")

func execute_action(action: Dictionary) -> Dictionary:
	"""Override to detect unit kills from diffs (AI/batch shooting path)."""
	var result = super.execute_action(action)

	# Kill hook: after diffs are applied, scan for alive=false changes
	if result.get("success", false) and result.has("changes"):
		_check_kill_diffs(result.changes)
		# Units destroyed / battle-shocked by Deadly Demise or emergency
		# disembarks above open their stratagem windows too (design §3).
		if _ev_depth == 0:
			_window_events_flush(result)

	return result

## Stratagem-window attribution (enemy_unit_has_attacked): the active shooter.
func _window_attacking_unit_id() -> String:
	return active_shooter_id

func _check_kill_diffs(changes: Array) -> void:
	"""Scan state-change diffs for models set to alive=false, then report unit destruction."""
	var unit_ids_to_check: Dictionary = {}  # Use dict as set for dedup

	for diff in changes:
		if diff.get("op", "") != "set":
			continue
		var path = diff.get("path", "")
		if not path.ends_with(".alive") or diff.get("value", true) != false:
			continue

		# Path format: "units.<UNIT_ID>.models.<IDX>.alive"
		var parts = path.split(".")
		if parts.size() >= 2 and parts[0] == "units":
			unit_ids_to_check[parts[1]] = true

	for unit_id in unit_ids_to_check:
		SecondaryMissionManager.check_and_report_unit_destroyed(unit_id)
		# Track kills for primary mission scoring (Purge the Foe)
		if MissionManager:
			var unit = GameState.state.get("units", {}).get(unit_id, {})
			if not unit.is_empty():
				var all_dead = true
				for model in unit.get("models", []):
					if model.get("alive", true):
						all_dead = false
						break
				# A unit's destruction is processed ONCE per phase (F12) — a
				# repeated alive=false diff must not double-count the kill or
				# re-roll Deadly Demise. A unit that is alive again (returned
				# to the battlefield) may be reported anew.
				if not all_dead:
					_kill_reported_units.erase(unit_id)
				elif _kill_reported_units.has(unit_id):
					DebugLogger.info("ShootingPhase: kill of %s already processed this phase — skipping repeat (no second kill credit / Deadly Demise)" % unit_id)
					continue
				if all_dead:
					_kill_reported_units[unit_id] = true
					# Credit the destroyed unit's OPPONENT (r4:WS-3, r5:F4,
					# framework F9): out-of-turn attacks (GUN-CRAZY SHOW-OFFS'
					# shot back, FLYIN' HEADBUTT's mortal wounds) destroy units
					# of the ACTIVE player, so get_current_player() would credit
					# the victim. Same rule as FightPhase._check_kill_diffs.
					var _kd_owner = int(unit.get("owner", 0))
					var destroyed_by = (2 if _kd_owner == 1 else 1) if _kd_owner in [1, 2] else get_current_player()
					MissionManager.record_unit_destroyed(destroyed_by)
					# T7-57: Track unit kills/losses for AI performance summary
					var destroyed_owner = unit.get("owner", 0)
					if AIPlayer and AIPlayer.enabled:
						if AIPlayer.is_ai_player(destroyed_by):
							AIPlayer.record_ai_unit_killed(destroyed_by)
						if AIPlayer.is_ai_player(destroyed_owner):
							AIPlayer.record_ai_unit_lost(destroyed_owner)
					# P1-60: Check for transport destruction (must happen BEFORE Deadly Demise)
					_resolve_transport_destruction_if_applicable(unit_id)
					# P1-13: Check for Deadly Demise on destroyed unit
					_resolve_deadly_demise_if_applicable(unit_id)
					# (Codex: Adeptus Custodes Superior Creation rolls at the end of the
					# phase — PhaseManager -> CustodesEnhancements.gd, WP-C46.)
					# P3-32: Check if destroyed unit is a transport with embarked units
					_resolve_transport_destroyed_if_applicable(unit_id)

func _resolve_transport_destroyed_if_applicable(destroyed_unit_id: String) -> void:
	"""P3-32: If a destroyed unit is a transport, resolve emergency disembark for embarked units."""
	if not TransportManager.is_transport_with_embarked(destroyed_unit_id):
		return

	var _tx_meta = GameState.state.get("units", {}).get(destroyed_unit_id, {}).get("meta", {})
	var unit_name = _tx_meta.get("display_name", _tx_meta.get("name", destroyed_unit_id))
	DebugLogger.info(str("ShootingPhase: P3-32 Transport %s (%s) destroyed — resolving emergency disembark" % [unit_name, destroyed_unit_id]))
	log_phase_message("Transport %s destroyed! Embarked units must emergency disembark!" % unit_name)

	var result = TransportManager.resolve_transport_destroyed(destroyed_unit_id)
	if result.get("triggered", false):
		var diffs = result.get("diffs", [])
		if not diffs.is_empty():
			PhaseManager.apply_state_changes(diffs)

		# Log per-unit results
		for unit_result in result.get("per_unit", []):
			var msg = "%s: %d models disembarked (rolls: %s)" % [
				unit_result.unit_name, unit_result.models_disembarked, str(unit_result.rolls)]
			if unit_result.casualties > 0:
				var _cas_label = "model" if unit_result.casualties == 1 else "models"
				msg += " — %d %s destroyed!" % [unit_result.casualties, _cas_label]
			log_phase_message(msg)

		if result.total_casualties > 0:
			var _tca_label = "casualty" if result.total_casualties == 1 else "casualties"
			log_phase_message("Emergency disembark: %d total %s from transport destruction" % [result.total_casualties, _tca_label])
			# Check if any disembarked units were fully destroyed
			_check_kill_diffs(diffs)

func _resolve_transport_destruction_if_applicable(destroyed_unit_id: String) -> void:
	"""P1-60: Check if a destroyed unit is a transport with embarked units and resolve emergency disembarkation."""
	var transport_mgr = get_node_or_null("/root/TransportManager")
	if not transport_mgr:
		return
	if not transport_mgr.is_transport_with_embarked_units(destroyed_unit_id):
		return

	var _tx2_meta = GameState.state.get("units", {}).get(destroyed_unit_id, {}).get("meta", {})
	var transport_name = _tx2_meta.get("display_name", _tx2_meta.get("name", destroyed_unit_id))
	DebugLogger.info(str("ShootingPhase: P1-60 Transport destruction detected — %s (%s) has embarked units" % [transport_name, destroyed_unit_id]))
	log_phase_message("Transport %s destroyed! Embarked units must emergency disembark!" % transport_name)

	var result = RulesEngine.resolve_transport_destruction(destroyed_unit_id, GameState.state)

	if not result.get("all_diffs", []).is_empty():
		PhaseManager.apply_state_changes(result.all_diffs)

		for unit_info in result.get("per_unit", []):
			var mw = unit_info.get("mortal_wounds", 0)
			var destroyed_models = unit_info.get("models_destroyed", 0)
			var unit_name = unit_info.get("unit_name", "Unknown")
			var unplaceable = int(unit_info.get("models_unplaceable", 0))
			if mw > 0:
				var _mw_label = "mortal wound" if mw == 1 else "mortal wounds"
				var _md_label = "model" if destroyed_models == 1 else "models"
				log_phase_message("  %s: %d %s, %d %s destroyed" % [unit_name, mw, _mw_label, destroyed_models, _md_label])
			elif unplaceable == 0:
				log_phase_message("  %s: disembarked safely" % unit_name)
			if unplaceable > 0:
				# 18.05: "Each model that cannot be set up in this way is destroyed."
				log_phase_message("  %s: %d model(s) could not be set up wholly within 6\" of the transport and were destroyed (18.05)" % [unit_name, unplaceable])

		# Recursively check if transport destruction casualties caused further deaths
		_check_kill_diffs(result.all_diffs)

## Deadly Demise is resolved by this phase's own kill detection
## (_check_kill_diffs), not by the BasePhase generic event path.
func _phase_resolves_deadly_demise() -> bool:
	return true

func _resolve_deadly_demise_if_applicable(destroyed_unit_id: String) -> void:
	"""P1-13: Check if a destroyed unit has Deadly Demise and resolve it."""
	# Stratagem window unit_destroyed opens BEFORE Deadly Demise (design §3,
	# FLYIN' HEADBUTT): hold the roll until that window closes.
	if _window_hold_deadly_demise(destroyed_unit_id):
		return
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if not ability_mgr:
		return
	if not ability_mgr.has_deadly_demise(destroyed_unit_id):
		return

	var dd_value = ability_mgr.get_deadly_demise_value(destroyed_unit_id)
	if dd_value == "":
		return

	var _dd_meta = GameState.state.get("units", {}).get(destroyed_unit_id, {}).get("meta", {})
	var unit_name = _dd_meta.get("display_name", _dd_meta.get("name", destroyed_unit_id))
	DebugLogger.info(str("ShootingPhase: P1-13 Deadly Demise detected on destroyed unit %s (%s) — value: %s" % [unit_name, destroyed_unit_id, dd_value]))
	log_phase_message("Deadly Demise %s triggered for %s!" % [dd_value, unit_name])

	var dd_result = RulesEngine.resolve_deadly_demise(destroyed_unit_id, dd_value, GameState.state)

	if dd_result.get("triggered", false):
		# Apply the mortal wound diffs
		var diffs = dd_result.get("diffs", [])
		if not diffs.is_empty():
			PhaseManager.apply_state_changes(diffs)
			log_phase_message("Deadly Demise %s: %d mortal wound(s) dealt to %d unit(s)" % [
				dd_value, dd_result.get("total_mortal_wounds", 0), dd_result.get("per_target", []).size()
			])
			# Recursively check if Deadly Demise caused any further unit deaths
			_check_kill_diffs(diffs)
	else:
		log_phase_message("Deadly Demise %s: roll of %d — did not trigger (needed 6)" % [
			dd_value, dd_result.get("trigger_roll", 0)
		])

func _compute_engagement_flags() -> void:
	var units = game_state_snapshot.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("status", 0) != 2:
			continue
		var owner = unit.get("owner", 0)
		var in_engagement = false
		for other_id in units:
			if other_id == unit_id:
				continue
			var other = units[other_id]
			if other.get("owner", 0) == owner:
				continue
			if other.get("status", 0) != 2:
				continue
			if RulesEngine.check_units_in_engagement_range(unit, other, game_state_snapshot):
				in_engagement = true
				break
		var gs_unit = GameState.state["units"].get(unit_id, {})
		if not gs_unit.is_empty():
			if not gs_unit.has("flags"):
				gs_unit["flags"] = {}
			gs_unit["flags"]["in_engagement"] = in_engagement
			if in_engagement:
				log_phase_message("Unit %s is in engagement range" % unit_id)
	game_state_snapshot = GameState.create_snapshot()

func _initialize_shooting() -> void:
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)

	var can_shoot = false
	for unit_id in units:
		var unit = units[unit_id]
		if _can_unit_shoot(unit):
			can_shoot = true
			break

	if not can_shoot:
		log_phase_message("No units available for shooting, ready to end phase")
		# Don't auto-complete - wait for END_SHOOTING action

## Actions that would re-enter or abandon an attack that is already paused on
## the defender's save allocation. Rejected outright while pending_save_data
## holds an unresolved batch — see the DEFENDER CONTROL LOCK in
## get_available_actions(). RESOLVE_SHOOTING was the dangerous one: it re-rolled
## the whole attack while the defender's overlay was still showing the dice from
## the first roll, and the second saves_required it emitted got deduped away.
## END_SHOOTING is deliberately NOT locked: it is the player's manual escape
## hatch (and it clears pending_save_data on the way out). It is still withheld
## from get_available_actions() so the AI never silently abandons a defender's
## window it is supposed to be waiting on.
const _SAVE_LOCKED_ACTIONS := [
	"SELECT_SHOOTER", "ASSIGN_TARGET", "CLEAR_ASSIGNMENT", "CLEAR_ALL_ASSIGNMENTS",
	"CONFIRM_TARGETS", "RESOLVE_SHOOTING", "RESOLVE_WEAPON_SEQUENCE", "SKIP_UNIT",
	"SHOOT", "CONTINUE_SEQUENCE", "COMPLETE_SHOOTING_FOR_UNIT", "CANCEL_WEAPON_ORDER",
]

func validate_action(action: Dictionary) -> Dictionary:
	action = _normalize_attached_shooter(action)
	var action_type = action.get("type", "")

	# Codex: Orks (11e) reactive move follow-up (GRAB IT / GOADED INTO ACTION):
	# its own actions, and nothing else while it is in progress.
	var ork11e_gate := _ork11e_validate_reactive_move_gate(action)
	if not ork11e_gate.is_empty():
		return ork11e_gate

	if not pending_save_data.is_empty() and action_type in _SAVE_LOCKED_ACTIONS:
		var locked_target = str(pending_save_data[0].get("target_unit_name", pending_save_data[0].get("target_unit_id", "the target")))
		DebugLogger.info("ShootingPhase: rejecting %s — %d save batch(es) still pending for %s" % [
			action_type, pending_save_data.size(), locked_target])
		return {
			"valid": false,
			"errors": ["Saves are still pending for %s — resolve them before %s" % [locked_target, action_type]]
		}

	match action_type:
		"SELECT_SHOOTER":
			return _validate_select_shooter(action)
		"ASSIGN_TARGET":
			return _validate_assign_target(action)
		"CLEAR_ASSIGNMENT":
			return _validate_clear_assignment(action)
		"CLEAR_ALL_ASSIGNMENTS":
			return _validate_clear_all_assignments(action)
		"CONFIRM_TARGETS":
			return _validate_confirm_targets(action)
		"RESOLVE_SHOOTING":
			return _validate_resolve_shooting(action)
		"RESOLVE_WEAPON_SEQUENCE":  # Sequential weapon resolution
			return _validate_resolve_weapon_sequence(action)
		"CANCEL_WEAPON_ORDER":  # T06: back out of the weapon-order step to targeting
			return _validate_cancel_weapon_order(action)
		"SKIP_UNIT":
			return _validate_skip_unit(action)
		"END_SHOOTING":
			return _validate_end_shooting(action)
		"SHOOT":  # Full shooting action from UI
			return _validate_shoot(action)
		"APPLY_SAVES":  # Interactive save resolution
			return _validate_apply_saves(action)
		"CONTINUE_SEQUENCE":  # Continue to next weapon in sequential mode
			return _validate_continue_sequence(action)
		"CONTINUE_TO_WOUNDS", "CONTINUE_TO_SAVES", "USE_SHOOTING_REROLL", "FAST_FINISH_SHOOTING":  # Staged sequential steps
			return _validate_staged_continue(action)
		"COMPLETE_SHOOTING_FOR_UNIT":  # Complete shooting after final weapon
			return _validate_complete_shooting_for_unit(action)
		"USE_REACTIVE_STRATAGEM":  # Defender uses a reactive stratagem
			return _validate_use_reactive_stratagem(action)
		"DECLINE_REACTIVE_STRATAGEM":  # Defender declines to use a reactive stratagem
			return _validate_decline_reactive_stratagem(action)
		"USE_GRENADE_STRATAGEM":  # Active player uses GRENADE stratagem
			return _validate_use_grenade_stratagem(action)
		"USE_STRATAGEM":  # Active player uses a proactive (non-grenade) stratagem with phase: "shooting"
			return _validate_use_stratagem(action)
		"USE_THROAT_SLITTAS":  # P1-12: Player uses Throat Slittas mortal wounds
			return _validate_use_throat_slittas(action)
		"DECLINE_THROAT_SLITTAS":  # P1-12: Player declines Throat Slittas
			return _validate_decline_throat_slittas(action)
		"PERFORM_SECONDARY_ACTION":  # Action-based secondary mission (Establish Locus, Cleanse, Deploy Teleport Homer)
			return _validate_perform_secondary_action(action)
		"START_ACTION":  # B1 (16.01): start a generic 11e action (gives up shooting)
			return _validate_start_action(action)
		"BURN_OBJECTIVE":  # Scorched Earth: unit burns an objective instead of shooting
			return _validate_burn_objective(action)
		"PERFORM_RITUAL_ACTION":  # The Ritual: unit performs ritual action at objective
			return _validate_perform_ritual_action(action)
		"PERFORM_TERRAFORM_ACTION":  # Terraform: unit terraforms an objective
			return _validate_perform_terraform_action(action)
		"USE_SWIFT_AS_THE_EAGLE":
			return _validate_use_swift_as_the_eagle(action)
		"DECLINE_SWIFT_AS_THE_EAGLE":
			return _validate_decline_swift_as_the_eagle(action)
		"END_MOVEMENT":
			# Idempotent no-op: previous phase auto-advanced before END_MOVEMENT was dispatched.
			return {"valid": true}
		_:
			return {"valid": false, "errors": ["Unknown action type: " + action_type]}

## Codex: Orks (11e) post-shot hook wrapper (design §3 unit_has_shot /
## enemy_has_shot): runs the phase's own action dispatch, then — when that
## action completed a unit's shooting — opens the post-shot stratagem windows.
## The dispatch itself is unchanged (_process_action_dispatch).
func process_action(action: Dictionary) -> Dictionary:
	# 19.01: an attached CHARACTER shoots in its bodyguard's activation, and
	# when that activation ends the whole Attached unit has shot.
	action = _normalize_attached_shooter(action)
	var shot_before: Array = units_that_shot.duplicate()
	var result: Dictionary = _process_action_with_windows(action)
	if result.get("success", false):
		var mirrored := _mirror_shot_to_attached_group(shot_before)
		if not mirrored.is_empty():
			var merged_changes: Array = result.get("changes", []).duplicate()
			merged_changes.append_array(mirrored)
			result["changes"] = merged_changes
	return result

func _process_action_with_windows(action: Dictionary) -> Dictionary:
	var a_type := str(action.get("type", ""))
	if a_type == "ASSIGN_TARGET" and _sts_deferred_hold_active():
		_sts_held_actions.append(action.duplicate(true))
		log_phase_message("[StratagemWindow] ASSIGN_TARGET held until the unit_selected_to_shoot decision (%d held)" % _sts_held_actions.size())
		return create_result(true, [], "", {"stratagem_window_pending": true})
	if a_type.begins_with("ORK11E_REACTIVE_MOVE_"):
		return _ork11e_process_reactive_move_action(action)
	if a_type == "SELECT_SHOOTER" or a_type == "SHOOT":
		_ork11e_begin_shot_tracking(str(action.get("actor_unit_id", "")))
	if a_type == "SELECT_SHOOTER":
		_sts_note_selection(action)
	elif a_type in _STS_DEFERRED_TRIGGERS and _sts_deferred_window_due(action):
		# The auto-selected shooter's first real action: offer its
		# unit_selected_to_shoot window BEFORE applying the action.
		var sts_unit := _sts_window_deferred_unit
		_sts_window_deferred_unit = ""
		_sts_window_handled_unit = sts_unit
		log_phase_message("[StratagemWindow] %s was auto-selected — unit_selected_to_shoot opens before the player's first %s" % [sts_unit, a_type])
		var sts = _open_selected_to_shoot_window(sts_unit, {"type": "SELECT_SHOOTER", "actor_unit_id": sts_unit}, action)
		var sts_diffs: Array = sts.get("diffs", [])
		if sts.get("paused", false):
			return create_result(true, sts_diffs, "", {"stratagem_window_pending": true})
		if not sts_diffs.is_empty():
			_sts_window_used_unit = sts_unit
			var sts_shot_before := units_that_shot.size()
			var sts_result: Dictionary = _process_action_dispatch(action)
			if sts_result.get("success", false):
				var sts_merged: Array = sts_diffs.duplicate()
				sts_merged.append_array(sts_result.get("changes", []))
				sts_result["changes"] = sts_merged
				_ork11e_queue_post_shot(a_type, sts_shot_before, sts_result)
				sts_result = _ork11e_run_post_shot_windows(sts_result)
			return sts_result
	var shot_before := units_that_shot.size()
	var result: Dictionary = _process_action_dispatch(action)
	if result.get("success", false):
		_ork11e_queue_post_shot(a_type, shot_before, result)
		result = _ork11e_run_post_shot_windows(result)
	return result

func _process_action_dispatch(action: Dictionary) -> Dictionary:
	DebugLogger.info("========================================")
	DebugLogger.info("ShootingPhase: process_action CALLED")
	DebugLogger.info(str("ShootingPhase: action = ", action))

	var action_type = action.get("type", "")
	DebugLogger.info(str("ShootingPhase: action_type = ", action_type))

	match action_type:
		"SELECT_SHOOTER":
			DebugLogger.info("ShootingPhase: Matched SELECT_SHOOTER")
			return _process_select_shooter(action)
		"ASSIGN_TARGET":
			DebugLogger.info("ShootingPhase: Matched ASSIGN_TARGET")
			return _process_assign_target(action)
		"CLEAR_ASSIGNMENT":
			DebugLogger.info("ShootingPhase: Matched CLEAR_ASSIGNMENT")
			return _process_clear_assignment(action)
		"CLEAR_ALL_ASSIGNMENTS":
			DebugLogger.info("ShootingPhase: Matched CLEAR_ALL_ASSIGNMENTS")
			return _process_clear_all_assignments(action)
		"CONFIRM_TARGETS":
			DebugLogger.info("ShootingPhase: Matched CONFIRM_TARGETS")
			return _process_confirm_targets(action)
		"RESOLVE_SHOOTING":
			DebugLogger.info("ShootingPhase: Matched RESOLVE_SHOOTING")
			return _process_resolve_shooting(action)
		"RESOLVE_WEAPON_SEQUENCE":  # Sequential weapon resolution
			DebugLogger.info("ShootingPhase: Matched RESOLVE_WEAPON_SEQUENCE")
			return _process_resolve_weapon_sequence(action)
		"CANCEL_WEAPON_ORDER":  # T06: back out of the weapon-order step to targeting
			DebugLogger.info("ShootingPhase: Matched CANCEL_WEAPON_ORDER")
			return _process_cancel_weapon_order(action)
		"SKIP_UNIT":
			DebugLogger.info("ShootingPhase: Matched SKIP_UNIT")
			return _process_skip_unit(action)
		"END_SHOOTING":
			DebugLogger.info("ShootingPhase: Matched END_SHOOTING")
			return _process_end_shooting(action)
		"SHOOT":  # Full shooting action
			DebugLogger.info("ShootingPhase: Matched SHOOT")
			return _merge_sts_carry_diffs(_process_shoot(action))
		"APPLY_SAVES":  # Interactive save resolution
			DebugLogger.info("ShootingPhase: Matched APPLY_SAVES")
			return _process_apply_saves(action)
		"CONTINUE_SEQUENCE":  # Continue to next weapon in sequential mode
			DebugLogger.info("ShootingPhase: Matched CONTINUE_SEQUENCE")
			return _process_continue_sequence(action)
		"CONTINUE_TO_WOUNDS":  # Staged: roll the wound roll for the current weapon
			DebugLogger.info("ShootingPhase: Matched CONTINUE_TO_WOUNDS")
			return _staged_continue_to_wounds()
		"CONTINUE_TO_SAVES":  # Staged: proceed from wound roll to saving throws
			DebugLogger.info("ShootingPhase: Matched CONTINUE_TO_SAVES")
			return _staged_continue_to_saves()
		"USE_SHOOTING_REROLL":  # Staged: Command Re-roll a hit or wound die
			DebugLogger.info("ShootingPhase: Matched USE_SHOOTING_REROLL")
			return _process_use_shooting_reroll(action)
		"FAST_FINISH_SHOOTING":  # Staged: skip remaining pauses and resolve the rest now
			DebugLogger.info("ShootingPhase: Matched FAST_FINISH_SHOOTING")
			return _process_fast_finish_shooting(action)
		"COMPLETE_SHOOTING_FOR_UNIT":  # Complete shooting after final weapon
			DebugLogger.info("ShootingPhase: Matched COMPLETE_SHOOTING_FOR_UNIT")
			return _process_complete_shooting_for_unit(action)
		"USE_REACTIVE_STRATAGEM":  # Defender uses a reactive stratagem
			DebugLogger.info("ShootingPhase: Matched USE_REACTIVE_STRATAGEM")
			return _process_use_reactive_stratagem(action)
		"DECLINE_REACTIVE_STRATAGEM":  # Defender declines reactive stratagem
			DebugLogger.info("ShootingPhase: Matched DECLINE_REACTIVE_STRATAGEM")
			return _process_decline_reactive_stratagem(action)
		"USE_GRENADE_STRATAGEM":  # Active player uses GRENADE stratagem
			DebugLogger.info("ShootingPhase: Matched USE_GRENADE_STRATAGEM")
			return _process_use_grenade_stratagem(action)
		"USE_STRATAGEM":  # Active player uses a proactive (non-grenade) stratagem with phase: "shooting"
			DebugLogger.info("ShootingPhase: Matched USE_STRATAGEM")
			return _process_use_stratagem(action)
		"USE_THROAT_SLITTAS":  # P1-12: Player uses Throat Slittas
			DebugLogger.info("ShootingPhase: Matched USE_THROAT_SLITTAS")
			return _process_use_throat_slittas(action)
		"DECLINE_THROAT_SLITTAS":  # P1-12: Player declines Throat Slittas
			DebugLogger.info("ShootingPhase: Matched DECLINE_THROAT_SLITTAS")
			return _process_decline_throat_slittas(action)
		"PERFORM_SECONDARY_ACTION":  # Action-based secondary mission
			DebugLogger.info("ShootingPhase: Matched PERFORM_SECONDARY_ACTION")
			return _process_perform_secondary_action(action)
		"START_ACTION":  # B1 (16.01): start a generic 11e action
			DebugLogger.info("ShootingPhase: Matched START_ACTION")
			return _process_start_action(action)
		"BURN_OBJECTIVE":  # Scorched Earth: burn objective
			DebugLogger.info("ShootingPhase: Matched BURN_OBJECTIVE")
			return _process_burn_objective(action)
		"PERFORM_RITUAL_ACTION":  # The Ritual: perform ritual action
			DebugLogger.info("ShootingPhase: Matched PERFORM_RITUAL_ACTION")
			return _process_perform_ritual_action(action)
		"PERFORM_TERRAFORM_ACTION":  # Terraform: terraform an objective
			DebugLogger.info("ShootingPhase: Matched PERFORM_TERRAFORM_ACTION")
			return _process_perform_terraform_action(action)
		"USE_SWIFT_AS_THE_EAGLE":
			DebugLogger.info("ShootingPhase: Matched USE_SWIFT_AS_THE_EAGLE")
			return _process_use_swift_as_the_eagle(action)
		"DECLINE_SWIFT_AS_THE_EAGLE":
			DebugLogger.info("ShootingPhase: Matched DECLINE_SWIFT_AS_THE_EAGLE")
			return _process_decline_swift_as_the_eagle(action)
		"END_MOVEMENT":
			DebugLogger.info("ShootingPhase: Matched END_MOVEMENT (no-op, phase already advanced)")
			return create_result(true, [], "")
		_:
			DebugLogger.info("ShootingPhase: NO MATCH - returning error")
			return create_result(false, [], "Unknown action type: " + action_type)

# Validation Methods

func _validate_select_shooter(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found"]}
	
	if unit.get("owner", 0) != get_current_player():
		return {"valid": false, "errors": ["Unit does not belong to active player"]}
	
	# ISS-048 step 2: at 11e the shooting-type registry (10.02) is
	# authoritative — a unit needs at least one selectable type.
	if GameConstants.edition >= 11:
		var types_11e = ShootingTypes.available_for(unit_id, GameState.state)
		if types_11e.is_empty():
			var why = ShootingTypes.get_type("normal").eligible(unit_id, GameState.state)
			return {"valid": false, "errors": ["No shooting type selectable (10.02): " + str(why.reasons)]}
	elif not _can_unit_shoot(unit):
		return {"valid": false, "errors": ["Unit cannot shoot"]}

	if unit_id in units_that_shot:
		return {"valid": false, "errors": ["Unit has already shot this phase"]}

	# P3-96: "Unless at least one model in a unit has an eligible target,
	# that unit cannot be selected to shoot." (SHOOT-7)
	if not _has_eligible_targets(unit_id):
		DebugLogger.info(str("ShootingPhase: P3-96 Unit %s cannot be selected to shoot — no eligible targets" % unit_id))
		return {"valid": false, "errors": ["Unit has no eligible targets to shoot"]}

	return {"valid": true, "errors": []}

func _validate_assign_target(action: Dictionary) -> Dictionary:
	var payload = action.get("payload", {})
	var weapon_id = payload.get("weapon_id", "")
	var target_unit_id = payload.get("target_unit_id", "")
	var model_ids = payload.get("model_ids", [])
	
	if active_shooter_id == "":
		return {"valid": false, "errors": ["No shooter selected"]}
	
	if weapon_id == "" or target_unit_id == "":
		return {"valid": false, "errors": ["Missing weapon_id or target_unit_id"]}
	
	# P2-91: Allow reassigning a weapon to a different target.
	# The old check blocked reassignment by treating it as "splitting attacks".
	# In reality, _process_assign_target() replaces the old assignment, so
	# there's never two targets for the same weapon simultaneously.
	# No validation needed here — reassignment is always valid.

	var shooter_unit_pre = get_unit(active_shooter_id)
	# ISS-048 step 2 (11e): the selected shooting type's WHILE constraints
	# gate every assignment — weapon_allowed (e.g. [ASSAULT]-only when
	# advanced, CQ weapons vs engaged targets) and target_allowed (17.03
	# baseline + per-type relaxations).
	if GameConstants.edition >= 11 and active_shooting_type != "":
		var st_11e = ShootingTypes.get_type(active_shooting_type)
		var wprofile = RulesEngine.get_weapon_profile(weapon_id, game_state_snapshot)
		var w_ok = st_11e.weapon_allowed(wprofile, shooter_unit_pre, GameState.state)
		if not w_ok.allowed:
			return {"valid": false, "errors": [w_ok.reason]}
		var t_ok = st_11e.target_allowed(active_shooter_id, target_unit_id, wprofile, GameState.state)
		if not t_ok.allowed:
			return {"valid": false, "errors": [t_ok.reason]}

	# MA-25: PISTOL MUTUAL EXCLUSIVITY — per-model check (was unit-wide before MA-25)
	# Per 10e: "If a model is equipped with one or more Pistols, unless it is a
	# MONSTER or VEHICLE model, it can either shoot with its Pistols or with all
	# of its other ranged weapons."
	# Per-model: each model individually must choose pistol or non-pistol, but
	# different models in the same unit can make different choices.
	var shooter_unit = get_unit(active_shooter_id)
	if GameConstants.edition < 11 and not RulesEngine.is_monster_or_vehicle(shooter_unit):
		var new_weapon_is_pistol = RulesEngine.is_pistol_weapon(weapon_id, game_state_snapshot)
		# Check each model in the new assignment against existing assignments
		for new_model_id in model_ids:
			for assignment in pending_assignments:
				var existing_weapon_id = assignment.get("weapon_id", "")
				if existing_weapon_id == "":
					continue
				var existing_model_ids = assignment.get("model_ids", [])
				if new_model_id not in existing_model_ids:
					continue  # This existing assignment doesn't involve this model
				var existing_is_pistol = RulesEngine.is_pistol_weapon(existing_weapon_id, game_state_snapshot)
				if new_weapon_is_pistol and not existing_is_pistol:
					return {"valid": false, "errors": ["Model '%s' cannot fire Pistol weapons when non-Pistol weapons are already assigned — must choose one or the other" % new_model_id]}
				if not new_weapon_is_pistol and existing_is_pistol:
					return {"valid": false, "errors": ["Model '%s' cannot fire non-Pistol weapons when Pistol weapons are already assigned — must choose one or the other" % new_model_id]}

	# Validate with RulesEngine
	var shoot_action = {
		"type": "SHOOT",
		"actor_unit_id": active_shooter_id,
		"payload": {
			"assignments": [{
				"weapon_id": weapon_id,
				"target_unit_id": target_unit_id,
				"model_ids": model_ids
			}]
		}
	}

	var validation = RulesEngine.validate_shoot(shoot_action, game_state_snapshot)
	return validation

func _validate_clear_assignment(action: Dictionary) -> Dictionary:
	var payload = action.get("payload", {})
	var weapon_id = payload.get("weapon_id", "")
	
	if weapon_id == "":
		return {"valid": false, "errors": ["Missing weapon_id"]}
	
	return {"valid": true, "errors": []}

func _validate_clear_all_assignments(action: Dictionary) -> Dictionary:
	return {"valid": true, "errors": []}

func _validate_confirm_targets(action: Dictionary) -> Dictionary:
	if pending_assignments.is_empty():
		return {"valid": false, "errors": ["No targets assigned"]}

	var shooter_unit = get_unit(active_shooter_id)

	# F3 (audit 2026-07): at 11e the selected shooting type is authoritative for
	# BOTH weapon and target legality — run the SAME gate that ASSIGN_TARGET
	# uses, so any plan that assembled also confirms. The old hard-coded check
	# below additionally denied engaged MONSTER/VEHICLE units their 10.06 right
	# to shoot units they are NOT engaged with (it required every target to be
	# in engagement range regardless of keywords), so an engaged vehicle could
	# assign two legal targets and then have CONFIRM_TARGETS reject the plan.
	if GameConstants.edition >= 11 and active_shooting_type != "":
		var st_11e = ShootingTypes.get_type(active_shooting_type)
		for assignment in pending_assignments:
			var wid_11e = assignment.get("weapon_id", "")
			var wprofile = RulesEngine.get_weapon_profile(wid_11e, game_state_snapshot)
			var w_ok = st_11e.weapon_allowed(wprofile, shooter_unit, GameState.state)
			if not w_ok.allowed:
				return {"valid": false, "errors": [w_ok.reason]}
			var t_ok = st_11e.target_allowed(active_shooter_id, assignment.get("target_unit_id", ""), wprofile, GameState.state)
			if not t_ok.allowed:
				return {"valid": false, "errors": [t_ok.reason]}
		return {"valid": true, "errors": []}

	# 10e legacy: engagement range restrictions (Pistol-only, engaged targets only)
	if shooter_unit.get("flags", {}).get("in_engagement", false):
		var is_monster_vehicle = RulesEngine.is_monster_or_vehicle(shooter_unit)
		for assignment in pending_assignments:
			var wid = assignment.get("weapon_id", "")
			var tid = assignment.get("target_unit_id", "")
			if not is_monster_vehicle and not RulesEngine.is_pistol_weapon(wid, game_state_snapshot):
				return {"valid": false, "errors": ["Unit is in engagement — only Pistol weapons can fire"]}
			if not RulesEngine.check_units_in_engagement_range(shooter_unit, get_unit(tid), game_state_snapshot):
				return {"valid": false, "errors": ["Unit is in engagement — can only target engaged units"]}

	return {"valid": true, "errors": []}

func _validate_resolve_shooting(action: Dictionary) -> Dictionary:
	if confirmed_assignments.is_empty():
		return {"valid": false, "errors": ["No confirmed targets to resolve"]}
	
	return {"valid": true, "errors": []}

func _validate_skip_unit(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	return {"valid": true, "errors": []}

func _validate_end_shooting(action: Dictionary) -> Dictionary:
	# Can always end the phase
	return {"valid": true, "errors": []}

func _can_unit_perform_action(unit: Dictionary) -> bool:
	"""Action eligibility — same requirements as shooting, EXCEPT that the
	Codex: Adeptus Custodes Emissaries Imperatus Favoured CONSERVAI (WP-C46)
	lets an Advanced unit perform Actions even when the Advance blocks it
	from shooting (e.g. no Assault weapons)."""
	if _can_unit_shoot(unit):
		return true
	if unit.get("flags", {}).get("advanced", false) \
			and not unit.get("flags", {}).get("fell_back", false) \
			and _cus11e_det().move_keeps_action_eligibility(unit):
		# Re-check the base requirements with the Advance restriction waived:
		# destroyed/embarked/status/has_shot/cannot_shoot still apply.
		if _is_unit_destroyed_check(unit):
			return false
		if unit.get("embarked_in", null) != null:
			return false
		var status = unit.get("status", 0)
		if status != GameStateData.UnitStatus.DEPLOYED and status != GameStateData.UnitStatus.MOVED:
			return false
		var flags = unit.get("flags", {})
		if flags.get("has_shot", false) or flags.get("cannot_shoot", false):
			return false
		log_phase_message("Favoured Conservai (Emissaries Imperatus): %s may perform an action despite Advancing" % unit.get("meta", {}).get("name", "?"))
		return true
	return false

## 19.01: "An attached unit is a single unit for all rules purposes" — it is
## selected to shoot ONCE (10.02) and selects targets for ALL its weapons before
## any attack is resolved (04.02 -> 04.03). The engine keeps the bodyguard and
## its attached CHARACTER(s) as separate unit dicts, but the bodyguard's
## activation already shoots with the whole Attached unit:
## RulesEngine.get_unit_weapons(bodyguard) lists the characters' guns as
## "<char_unit_id>:<model_id>" bearers. So selecting the character on its own
## would split the unit into two activations (and could fire its guns twice).
## Returns the unit that is actually selected when `unit_id` is chosen to shoot:
## the bodyguard for an attached character, else unit_id itself. The character
## is only selected on its own when the bodyguard cannot shoot at all (e.g. it
## Advanced without Assault weapons) — then the character's models are the only
## part of the unit that can shoot, and finishing still ends the whole unit.
func shooting_actor_for(unit_id: String) -> String:
	var bodyguard_id := _attached_bodyguard_for(unit_id)
	if bodyguard_id == "":
		return unit_id
	var bodyguard := get_unit(bodyguard_id)
	if bodyguard_id in units_that_shot or bodyguard.get("flags", {}).get("has_shot", false) or _can_unit_shoot(bodyguard):
		return bodyguard_id
	return unit_id

## Live bodyguard unit `unit_id` is attached to ("" when not attached).
## RulesEngine.attached_unit_target_id walks BOTH sides of the linkage and
## skips a wiped bodyguard (19.05: the leader is its own unit again).
func _attached_bodyguard_for(unit_id: String) -> String:
	var unit := get_unit(unit_id)
	if unit.is_empty():
		return ""
	var bodyguard_id := RulesEngine.attached_unit_target_id(unit_id, GameState.state)
	if bodyguard_id == unit_id or get_unit(bodyguard_id).get("owner", -1) != unit.get("owner", -2):
		return ""
	return bodyguard_id

## Every component of unit_id's Attached unit (bodyguard first), or [unit_id].
func _attached_unit_ids(unit_id: String) -> Array:
	var head := RulesEngine.attached_unit_target_id(unit_id, GameState.state)
	return RulesEngine.attached_unit_component_ids(head, GameState.state)

const _ATTACHED_SHOOTER_ACTIONS := ["SELECT_SHOOTER", "SHOOT", "SKIP_UNIT"]

## Rewrite SELECT_SHOOTER / SHOOT / SKIP_UNIT naming an attached character to
## its bodyguard (SHOOT model ids become "<char_unit_id>:<model_id>" bearers).
func _normalize_attached_shooter(action: Dictionary) -> Dictionary:
	if not str(action.get("type", "")) in _ATTACHED_SHOOTER_ACTIONS:
		return action
	var unit_id := str(action.get("actor_unit_id", ""))
	if unit_id == "":
		return action
	var actor_id := shooting_actor_for(unit_id)
	if actor_id == unit_id:
		return action
	var out: Dictionary = action.duplicate(true)
	out["actor_unit_id"] = actor_id
	if str(action.get("type", "")) == "SHOOT":
		for a in out.get("payload", {}).get("assignments", []):
			var bearers: Array = []
			for mid in a.get("model_ids", []):
				bearers.append(str(mid) if ":" in str(mid) else "%s:%s" % [unit_id, str(mid)])
			a["model_ids"] = bearers
	DebugLogger.info(str("ShootingPhase: [19.01] %s for attached character %s routed to its bodyguard %s (one Attached unit, one activation)" % [action.get("type", ""), unit_id, actor_id]))
	return out

## Every component of an Attached unit that (just) finished shooting / gave
## up shooting is done too: it was part of that one activation. Returns the
## has_shot diffs for the components marked here.
func _mirror_shot_to_attached_group(shot_before: Array) -> Array:
	var out: Array = []
	var units: Dictionary = GameState.state.get("units", {})
	for shooter_id in units_that_shot.duplicate():
		if shooter_id in shot_before:
			continue
		for pid in _attached_unit_ids(str(shooter_id)):
			var partner_id := str(pid)
			if partner_id == str(shooter_id) or partner_id in units_that_shot:
				continue
			units_that_shot.append(partner_id)
			out.append({"op": "set", "path": "units.%s.flags.has_shot" % partner_id, "value": true})
			DebugLogger.info(str("ShootingPhase: [19.01] %s shot as part of %s's Attached unit — marked as shot" % [partner_id, shooter_id]))
	return out

## 19.01: "An attached unit is a single unit for all rules purposes". The
## engine keeps a bodyguard and its attached CHARACTER(s) as separate unit
## dicts, so when one component performs an action (giving up shooting) the
## rest of the Attached unit must give up shooting too. Returns the mirrored
## flag diffs for the other components (performing_action / action_started_turn
## stay on the actor only, so the action completes / scores once).
func _mirror_action_to_attached_group(unit_id: String, changes: Array) -> Array:
	var out: Array = []
	var prefix := "units.%s.flags." % unit_id
	for pid in _attached_unit_ids(unit_id):
		var partner_id := str(pid)
		if partner_id == unit_id:
			continue
		if not partner_id in units_that_shot:
			units_that_shot.append(partner_id)
		if active_shooter_id == partner_id:
			active_shooter_id = ""
			pending_assignments.clear()
			confirmed_assignments.clear()
		for c in changes:
			var path := str(c.get("path", ""))
			if not path.begins_with(prefix):
				continue
			var flag := path.substr(prefix.length())
			if flag in ["performing_action", "action_started_turn"]:
				continue
			out.append({"op": c.get("op", "set"), "path": StateSchema.path_unit_flag(partner_id, flag), "value": c.get("value")})
		DebugLogger.info(str("ShootingPhase: %s is attached to acting unit %s — it gives up shooting too (19.01)" % [partner_id, unit_id]))
	return out

## True when any component of `unit_id`'s Attached unit (bodyguard or attached
## CHARACTER) has already shot / acted this phase.
func _attached_group_has_shot(unit_id: String) -> bool:
	var units: Dictionary = GameState.state.get("units", {})
	for pid in _attached_unit_ids(unit_id):
		if str(pid) in units_that_shot:
			return true
		if str(pid) != unit_id and units.get(str(pid), {}).get("flags", {}).get("has_shot", false):
			return true
	return false

func _validate_perform_secondary_action(action: Dictionary) -> Dictionary:
	"""Validate a unit performing a secondary mission action instead of shooting."""
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}

	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found"]}

	if unit.get("owner", 0) != get_current_player():
		return {"valid": false, "errors": ["Unit does not belong to active player"]}

	# Same eligibility as shooting — deployed, not battle-shocked, hasn't shot
	# (Favoured Conservai — Emissaries Imperatus — waives the Advance restriction)
	if not _can_unit_perform_action(unit):
		return {"valid": false, "errors": ["Unit is not eligible to perform an action (same requirements as shooting)"]}

	if _attached_group_has_shot(unit_id):
		return {"valid": false, "errors": ["Unit has already shot/acted this phase"]}

	var action_name = action.get("payload", {}).get("action_name", "")
	if action_name == "":
		return {"valid": false, "errors": ["Missing action_name in payload"]}

	# 11e Plunder: once per turn, and the unit must be within a terrain area
	# that is not within the player's territory.
	if action_name == "Plunder":
		if _plunder_done_this_turn(get_current_player()):
			return {"valid": false, "errors": ["Plunder has already been performed this turn (once per turn)"]}
		if _get_plunder_terrain_for_unit(unit_id, get_current_player()).is_empty():
			return {"valid": false, "errors": ["Unit is not within a terrain area outside your territory"]}

	return {"valid": true, "errors": []}

func _validate_shoot(action: Dictionary) -> Dictionary:
	# Full shoot action validation
	# 10.02: a unit is selected to shoot once per phase (with 19.01 routing an
	# attached CHARACTER to its bodyguard, this also stops the Attached unit
	# from shooting a second time through the character).
	if str(action.get("actor_unit_id", "")) in units_that_shot:
		return {"valid": false, "errors": ["Unit has already shot this phase"]}
	var validation = RulesEngine.validate_shoot(action, game_state_snapshot)
	return validation

func _validate_resolve_weapon_sequence(action: Dictionary) -> Dictionary:
	"""Validate weapon sequence resolution"""
	var payload = action.get("payload", {})
	var weapon_order = payload.get("weapon_order", [])
	var fast_roll = payload.get("fast_roll", false)

	if weapon_order.is_empty():
		return {"valid": false, "errors": ["Missing weapon_order in payload"]}

	if active_shooter_id == "":
		return {"valid": false, "errors": ["No active shooter"]}

	return {"valid": true, "errors": []}

## T06: CANCEL_WEAPON_ORDER is only legal in the weapon-order step (targets
## confirmed, no die rolled for the attacks yet) and only while the declaration
## is still the player's to take back — see weapon_order_cancel_block_reason().
func _validate_cancel_weapon_order(_action: Dictionary) -> Dictionary:
	if active_shooter_id == "":
		return {"valid": false, "errors": ["No active shooter"]}
	if str(resolution_state.get("phase", "")) != "awaiting_weapon_order":
		return {"valid": false, "errors": ["There is no weapon order waiting to be cancelled"]}
	var reason := weapon_order_cancel_block_reason()
	if reason != "":
		return {"valid": false, "errors": ["Targets are locked in: " + reason]}
	return {"valid": true, "errors": []}

## T06: why the weapon-order step can no longer go back to targeting, or ""
## when it can. Once the opponent has reacted to the declared targets (any
## stratagem used since CONFIRM_TARGETS — SMOKESCREEN, a codex reactive — or
## one used by the shooter's side) or a die was rolled against them, the
## targets stand: taking them back would let the attacker re-aim after seeing
## the reaction. The panel greys its Back button out with this text.
func weapon_order_cancel_block_reason() -> String:
	if _wo_lock_reason != "":
		return _wo_lock_reason
	if _wo_declared_assignments.is_empty() or _wo_usage_mark.size() != 2:
		# e.g. the step was restored from a save: the declaration was not kept.
		return "the declared targets were not recorded for this step"
	var now := _wo_stratagem_usage_mark()
	var defender := 2 if get_current_player() == 1 else 1
	if int(now[defender - 1]) != int(_wo_usage_mark[defender - 1]):
		return "the opponent has already used a stratagem against these targets"
	if now != _wo_usage_mark:
		return "a stratagem has been used since the targets were declared"
	return ""

## Stratagems used so far by player 1 and player 2 (StratagemManager history).
func _wo_stratagem_usage_mark() -> Array:
	return [StratagemManager.usage_count(1), StratagemManager.usage_count(2)]

## T06: hand the declaration back. Nothing is rolled and no game state changes:
## the confirmed (merged, Extra-Attacks-injected) list is dropped and the
## player's own pending assignments return, so the shooting panel can show them
## again for editing — re-confirming runs CONFIRM_TARGETS (and its reactive
## stratagem offer) afresh.
func _process_cancel_weapon_order(_action: Dictionary) -> Dictionary:
	var shooter := active_shooter_id
	pending_assignments = _wo_declared_assignments.duplicate(true)
	confirmed_assignments = []
	resolution_state = {}
	_wo_declared_assignments = []
	_wo_usage_mark = []
	_wo_lock_reason = ""
	log_phase_message("Weapon order cancelled — back to target selection with %d assignment(s); nothing was rolled" % pending_assignments.size())
	emit_signal("weapon_order_cancelled", shooter)
	return create_result(true, [], "", {
		"weapon_order_cancelled": true,
		"pending_assignments": pending_assignments.duplicate(true)
	})

# Processing Methods

func _process_select_shooter(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	# Stratagem window unit_selected_to_shoot (design §3): the unit has been
	# selected to shoot — before any target is confirmed or attack rolled, the
	# active player may use a "when … is selected to shoot" stratagem. Opened
	# once per selection; the resume re-enters this function (guard set).
	# An AUTOMATIC selection (ShootingController auto-select) defers it to the
	# player's first action with the unit (_sts_note_selection, LV-2).
	var sts_auto_selected := bool(action.get("payload", {}).get("auto_selected", false))
	if _sts_window_handled_unit != unit_id and not (sts_auto_selected and _sts_window_deferred_unit == unit_id):
		_sts_window_handled_unit = unit_id
		_sts_window_deferred_unit = ""
		var sts = _open_selected_to_shoot_window(unit_id, action)
		if sts.get("paused", false):
			active_shooter_id = unit_id
			return create_result(true, sts.get("diffs", []), "", {"stratagem_window_pending": true})
		var sts_diffs: Array = sts.get("diffs", [])
		if not sts_diffs.is_empty():
			_sts_window_used_unit = unit_id
			var sts_cont = _process_select_shooter(action)
			if action.get("payload", {}).has("_sts_atomic_action"):
				# Atomic SHOOT: _process_shoot drops the select result's
				# changes — carry the AI's CP/effect diffs to its result.
				_sts_carry_diffs.append_array(sts_diffs)
				return sts_cont
			var sts_merged: Array = sts_diffs.duplicate()
			sts_merged.append_array(sts_cont.get("changes", []))
			sts_cont["changes"] = sts_merged
			return sts_cont
	active_shooter_id = unit_id
	pending_assignments.clear()
	confirmed_assignments.clear()

	# ISS-048 step 2 (11e 10.02): the unit selects ONE shooting type.
	# payload.shooting_type overrides; default = first available
	# (normal > assault > close_quarters > indirect).
	active_shooting_type = ""
	if GameConstants.edition >= 11:
		var types_11e = ShootingTypes.available_for(unit_id, GameState.state)
		var requested = str(action.get("payload", {}).get("shooting_type", ""))
		if requested != "" and requested in types_11e:
			active_shooting_type = requested
		elif requested != "" and not requested in types_11e:
			log_phase_message("[11e] Requested shooting type '%s' not selectable for %s (available: %s)" % [requested, unit_id, str(types_11e)])
			active_shooting_type = types_11e[0] if not types_11e.is_empty() else ""
		elif not types_11e.is_empty():
			active_shooting_type = types_11e[0]
		log_phase_message("[11e] %s shoots with type: %s (available: %s)" % [unit_id, active_shooting_type, str(types_11e)])
	_targets_hit_by_shooter.clear()  # P1-11: Reset hit tracking for new shooter

	# TRY DAT BUTTON! (Dread Mob): roll the Button Effect when a Mek / Orks
	# Walker / Grots Vehicle unit is selected to shoot.
	var fam_tdb = get_node_or_null("/root/FactionAbilityManager")
	if fam_tdb:
		fam_tdb.process_try_dat_button(unit_id, "ranged")

	var unit = get_unit(unit_id)

	# Check if this is a transport with firing deck (24.14)
	if unit.has("transport_data") and unit.transport_data.get("firing_deck", 0) > 0:
		var eligible_embarked := []
		for embarked_id in unit.transport_data.get("embarked_units", []):
			var embarked = get_unit(embarked_id)
			if embarked and not embarked.get("flags", {}).get("has_shot", false):
				eligible_embarked.append(embarked_id)

		if not eligible_embarked.is_empty():
			# 24.14: only prompt when there's a genuine choice to make. When every
			# eligible model has a single ranged weapon, they all fit under Firing
			# Deck X, and none are [HAZARDOUS], auto-loan them onto the transport
			# and skip the selection dialog entirely.
			var fd_plan = _compute_firing_deck_plan(unit_id, eligible_embarked)
			if fd_plan.get("mode", "dialog") == "dialog":
				# Show firing deck dialog to select which embarked models will shoot
				call_deferred("_show_firing_deck_dialog", unit_id)
				log_phase_message("Selected transport %s - choosing firing deck models" % unit.get("meta", {}).get("name", unit_id))
				return create_result(true, [])
			var fd_loans = fd_plan.get("loans", [])
			if not fd_loans.is_empty():
				# No choice to make — loan the weapons and go straight to target
				# selection with them treated as the transport's own guns.
				_apply_firing_deck_loan(unit_id, fd_loans)
				var fd_targets = RulesEngine.get_eligible_targets(unit_id, game_state_snapshot)
				emit_signal("unit_selected_for_shooting", unit_id)
				emit_signal("targets_available", unit_id, fd_targets)
				log_phase_message("Firing deck auto-resolved for %s: %d weapon(s) loaned (no choice to make)" % [unit.get("meta", {}).get("name", unit_id), fd_loans.size()])
				return create_result(true, [])
			# Embarked but no firing-deck-eligible weapons (all melee/[ONE SHOT]);
			# fall through so the transport still shoots its own weapons.
			log_phase_message("Transport %s: no firing-deck-eligible embarked weapons; shooting its own guns" % unit.get("meta", {}).get("name", unit_id))

	# P1-12: Check for Throat Slittas — offer mortal wounds instead of shooting
	if not action.get("payload", {}).get("skip_throat_slittas_check", false):
		var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
		if ability_mgr and ability_mgr.has_throat_slittas_ability(unit_id):
			var ts_targets = _get_throat_slittas_targets(unit_id)
			if not ts_targets.is_empty():
				DebugLogger.info(str("ShootingPhase: P1-12 Throat Slittas: Unit %s has enemies within 9\" — prompting" % unit_id))
				throat_slittas_pending_unit = unit_id

				var current_player = get_current_player()
				emit_signal("throat_slittas_available", unit_id, current_player, ts_targets)

				log_phase_message("Throat Slittas available for %s — awaiting decision" % unit.get("meta", {}).get("name", unit_id))

				return create_result(true, [], "Throat Slittas available", {
					"throat_slittas_available": true,
					"unit_id": unit_id,
					"eligible_targets": ts_targets
				})

	# Normal shooting flow
	# Get eligible targets (PERF-LOS: cached — usually already computed by the
	# Select-Shooter list filter that ran this same phase).
	var eligible_targets = _cached_eligible_targets(unit_id)

	emit_signal("unit_selected_for_shooting", unit_id)
	emit_signal("targets_available", unit_id, eligible_targets)

	log_phase_message("Selected %s for shooting" % unit.get("meta", {}).get("name", unit_id))

	return create_result(true, [])

## Open the unit_selected_to_shoot stratagem window (design §3, §6.2) for the
## active player. Returns {paused: bool, diffs: Array}: paused = a human must
## answer (the resume re-enters the selection, or the atomic SHOOT when the
## selection came from one); diffs = window diffs to merge into the result
## (AI uses are applied synchronously).
func _open_selected_to_shoot_window(unit_id: String, action: Dictionary, deferred_action: Dictionary = {}) -> Dictionary:
	var payload: Dictionary = action.get("payload", {})
	var atomic_action = payload.get("_sts_atomic_action", {})
	var sts_ctx := {"phase": "shooting", "unit_id": unit_id}
	if typeof(atomic_action) == TYPE_DICTIONARY and not atomic_action.is_empty():
		# AI / auto-shoot: the planned targets are already known — the AI's
		# stratagem scoring may read them (humans pick targets afterwards).
		var planned: Array = []
		var planned_bearers: Array = []
		for a in atomic_action.get("payload", {}).get("assignments", []):
			var tid := str(a.get("target_unit_id", ""))
			if tid != "" and not tid in planned:
				planned.append(tid)
			for mid in a.get("model_ids", []):
				if not str(mid) in planned_bearers:
					planned_bearers.append(str(mid))
		sts_ctx["planned_target_unit_ids"] = planned
		sts_ctx["planned_bearer_ids"] = planned_bearers
	var resume_ctx := {"unit_id": unit_id, "select_action": action.duplicate(true)}
	if typeof(atomic_action) == TYPE_DICTIONARY and not atomic_action.is_empty():
		resume_ctx["atomic_action"] = atomic_action.duplicate(true)
	if not deferred_action.is_empty():
		# Auto-selected shooter: the window was opened by the player's first
		# action with it — the resume applies that action (LV-2).
		resume_ctx["deferred_action"] = deferred_action.duplicate(true)
	var decider := get_current_player()
	if open_stratagem_windows([{"player": decider, "window_id": "unit_selected_to_shoot", "ctx": sts_ctx}],
			"_resume_after_selected_to_shoot_window", resume_ctx):
		log_phase_message("Waiting for Player %d's unit_selected_to_shoot stratagem decision for %s" % [decider, unit_id])
		return {"paused": true, "diffs": consume_window_diffs()}
	return {"paused": false, "diffs": consume_window_diffs()}

## Resume point for the unit_selected_to_shoot window (BasePhase framework):
## continue the interrupted selection — or the whole atomic SHOOT.
func _resume_after_selected_to_shoot_window(ctx: Dictionary, _window_result: Dictionary) -> Dictionary:
	var unit_id := str(ctx.get("unit_id", ""))
	_sts_window_handled_unit = unit_id
	_sts_window_deferred_unit = ""
	if bool(_window_result.get("used", false)):
		_sts_window_used_unit = unit_id
	var deferred_action = ctx.get("deferred_action", {})
	if typeof(deferred_action) == TYPE_DICTIONARY and not deferred_action.is_empty():
		# The auto-selected shooter's first action, held while the window was
		# open: re-validate (the stratagem may have changed the state) and apply.
		var dv: Dictionary = validate_action(deferred_action)
		if not dv.get("valid", false):
			var derrs: Array = dv.get("errors", [])
			return create_result(false, [], "%s after the stratagem window: %s" % [
				str(deferred_action.get("type", "")), ", ".join(derrs) if not derrs.is_empty() else "not allowed"])
		log_phase_message("[StratagemWindow] unit_selected_to_shoot closed — applying the held %s for %s" % [str(deferred_action.get("type", "")), unit_id])
		var dres: Dictionary = _process_action_dispatch(deferred_action)
		var held: Array = _sts_held_actions
		_sts_held_actions = []
		for h in held:
			if not dres.get("success", false):
				break
			var hv: Dictionary = validate_action(h)
			if not hv.get("valid", false):
				log_phase_message("[StratagemWindow] held %s dropped after the window: %s" % [str(h.get("type", "")), str(hv.get("errors", []))])
				continue
			var hres: Dictionary = _process_action_dispatch(h)
			if hres.get("success", false):
				var hchanges: Array = dres.get("changes", [])
				hchanges.append_array(hres.get("changes", []))
				dres["changes"] = hchanges
		return dres
	var atomic_action = ctx.get("atomic_action", {})
	if typeof(atomic_action) == TYPE_DICTIONARY and not atomic_action.is_empty():
		return _merge_sts_carry_diffs(_process_shoot(atomic_action))
	var select_action = ctx.get("select_action", {})
	if typeof(select_action) != TYPE_DICTIONARY or select_action.is_empty():
		select_action = {"type": "SELECT_SHOOTER", "actor_unit_id": unit_id}
	return _process_select_shooter(select_action)

## True while the pending window is an auto-selected shooter's deferred
## unit_selected_to_shoot (opened by the player's first action with it).
func _sts_deferred_hold_active() -> bool:
	if not has_pending_stratagem_window():
		return false
	if str(get_pending_stratagem_window().get("window_id", "")) != "unit_selected_to_shoot":
		return false
	var rctx = _window_resume_ctx
	return typeof(rctx) == TYPE_DICTIONARY and rctx.has("deferred_action")

## LV2-B1: the type of the player's action the closing unit_selected_to_shoot
## window will apply on resume ("" when it holds none). The deferred window of
## an auto-selected shooter holds that action (and the rest of its assignment
## burst); the ShootingController reads this from the stratagem_window_closed
## signal — emitted before the resume runs — to refresh its panel from the
## phase once the held ASSIGN_TARGET(s) have been applied.
func sts_window_held_action_type() -> String:
	if typeof(_window_resume_ctx) != TYPE_DICTIONARY:
		return ""
	var held = _window_resume_ctx.get("deferred_action", {})
	if typeof(held) != TYPE_DICTIONARY or held.is_empty():
		return ""
	return str(held.get("type", ""))

## A burst of player assignments may continue while its first action's
## deferred window is pending (held, see _sts_held_actions).
func _window_exempt_action(action_type: String) -> bool:
	if action_type == "ASSIGN_TARGET" and _sts_deferred_hold_active():
		return true
	return super._window_exempt_action(action_type)

## SELECT_SHOOTER bookkeeping for the deferred unit_selected_to_shoot window
## (LV-2 / RV-4). An automatic selection defers the window; an explicit
## (re-)selection of a unit whose window was only declined is a new selection
## and is offered again ("Don't offer again this phase" still suppresses it).
func _sts_note_selection(action: Dictionary) -> void:
	var sel_uid := str(action.get("actor_unit_id", ""))
	if bool(action.get("payload", {}).get("auto_selected", false)):
		_sts_window_deferred_unit = sel_uid if _sts_window_handled_unit != sel_uid else ""
		if _sts_window_deferred_unit != "":
			log_phase_message("[StratagemWindow] %s auto-selected — unit_selected_to_shoot deferred to the player's first action with it" % sel_uid)
		return
	_sts_window_deferred_unit = ""
	if sel_uid != "" and _sts_window_handled_unit == sel_uid and _sts_window_used_unit != sel_uid \
			and active_shooter_id == sel_uid:
		_sts_window_handled_unit = ""
	if _sts_window_used_unit != sel_uid:
		_sts_window_used_unit = ""

## True when `action` is the first real action of an auto-selected shooter
## whose unit_selected_to_shoot window has not been offered yet.
func _sts_deferred_window_due(action: Dictionary) -> bool:
	if _sts_window_deferred_unit == "":
		return false
	if active_shooter_id != _sts_window_deferred_unit or _sts_window_handled_unit == _sts_window_deferred_unit:
		_sts_window_deferred_unit = ""
		return false
	# The controller's own single-target auto-assign is not a player action.
	if str(action.get("type", "")) == "ASSIGN_TARGET" and bool(action.get("payload", {}).get("auto_assigned", false)):
		return false
	return true

## Prepend the AI window diffs carried out of the atomic SHOOT's inner select.
func _merge_sts_carry_diffs(result: Dictionary) -> Dictionary:
	if _sts_carry_diffs.is_empty():
		return result
	var carried: Array = _sts_carry_diffs
	_sts_carry_diffs = []
	if result.get("success", false):
		var merged: Array = carried.duplicate()
		merged.append_array(result.get("changes", []))
		result["changes"] = merged
	return result

func _process_assign_target(action: Dictionary) -> Dictionary:
	var payload = action.get("payload", {})
	var weapon_id = payload.get("weapon_id", "")
	var target_unit_id = payload.get("target_unit_id", "")
	var model_ids = payload.get("model_ids", [])

	# SPLIT-FIRE: A single weapon_id may now have multiple pending assignments
	# (different targets). Enforce the invariant that no physical model_id is
	# assigned twice for the same weapon_id — strip any model_ids that already
	# appear in another pending assignment of the same weapon.
	var already_assigned_models: Array = []
	for a in pending_assignments:
		if a.get("weapon_id", "") == weapon_id and a.get("target_unit_id", "") != target_unit_id:
			for mid in a.get("model_ids", []):
				if mid not in already_assigned_models:
					already_assigned_models.append(mid)

	var filtered_model_ids: Array = []
	for mid in model_ids:
		if mid not in already_assigned_models:
			filtered_model_ids.append(mid)

	# If an assignment already exists for this (weapon, target), merge into it
	# rather than appending a duplicate.
	var existing_index := -1
	for i in range(pending_assignments.size()):
		var a = pending_assignments[i]
		if a.get("weapon_id", "") == weapon_id and a.get("target_unit_id", "") == target_unit_id:
			existing_index = i
			break

	if existing_index >= 0:
		var existing = pending_assignments[existing_index]
		var combined: Array = existing.get("model_ids", []).duplicate()
		for mid in filtered_model_ids:
			if mid not in combined:
				combined.append(mid)
		existing["model_ids"] = combined
		# Audit #17: latest attacker choice for the batch wins.
		if payload.has("lethal_hits_choice"):
			existing["lethal_hits_choice"] = str(payload.get("lethal_hits_choice", ""))
		if payload.has("devastating_wounds_choice"):
			existing["devastating_wounds_choice"] = str(payload.get("devastating_wounds_choice", ""))
	else:
		pending_assignments.append({
			"weapon_id": weapon_id,
			"target_unit_id": target_unit_id,
			"model_ids": filtered_model_ids,
			# Audit #17 (24.10/24.23): attacker's per-batch ability choices —
			# "" keeps the engine defaults.
			"lethal_hits_choice": str(payload.get("lethal_hits_choice", "")),
			"devastating_wounds_choice": str(payload.get("devastating_wounds_choice", "")),
		})

	log_phase_message("Assigned %s × %d to target %s" % [weapon_id, filtered_model_ids.size(), target_unit_id])

	# Issue #386 Big Booms: roll concussive wave on supa-kannon target selection.
	# Trigger phrase: "just after selecting a target for this model's supa-kannon".
	if weapon_id.to_lower().find("supa-kannon") != -1 and active_shooter_id != "":
		var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
		if ability_mgr and ability_mgr.has_method("roll_big_booms_concussive_wave"):
			var rolls = ability_mgr.roll_big_booms_concussive_wave(active_shooter_id, target_unit_id)
			if not rolls.is_empty():
				var struck_ids: Array = []
				for r in rolls:
					if r.get("struck", false):
						struck_ids.append(r.get("unit_id", ""))
				if not struck_ids.is_empty():
					_big_booms_pending.append({
						"target_unit_id": target_unit_id,
						"struck_unit_ids": struck_ids,
						"rolls": rolls,
					})
					log_phase_message("Big Booms concussive wave: %d unit(s) struck (rolls=%s)" % [struck_ids.size(), str(rolls)])
				else:
					log_phase_message("Big Booms concussive wave: no units struck (rolls=%s)" % [str(rolls)])

	return create_result(true, [])

func _process_clear_assignment(action: Dictionary) -> Dictionary:
	var payload = action.get("payload", {})
	var weapon_id = payload.get("weapon_id", "")
	var target_unit_id = payload.get("target_unit_id", "")

	# SPLIT-FIRE: If target_unit_id is given, clear only the matching
	# (weapon, target) pending assignment; otherwise clear every assignment
	# for that weapon (legacy "clear weapon" semantics).
	if target_unit_id != "":
		pending_assignments = pending_assignments.filter(
			func(a): return not (a.weapon_id == weapon_id and a.target_unit_id == target_unit_id)
		)
		log_phase_message("Cleared assignment for %s → %s" % [weapon_id, target_unit_id])
	else:
		pending_assignments = pending_assignments.filter(func(a): return a.weapon_id != weapon_id)
		log_phase_message("Cleared all assignments for %s" % weapon_id)

	return create_result(true, [])

func _process_clear_all_assignments(action: Dictionary) -> Dictionary:
	pending_assignments.clear()
	log_phase_message("Cleared all weapon assignments")
	
	return create_result(true, [])

func _process_confirm_targets(action: Dictionary) -> Dictionary:
	# T06: keep the declaration as the player made it, so the weapon-order
	# step's Esc (CANCEL_WEAPON_ORDER) can hand it back unchanged.
	_wo_declared_assignments = pending_assignments.duplicate(true)
	_wo_usage_mark = _wo_stratagem_usage_mark()
	_wo_lock_reason = ""

	# CRITICAL FIX: Merge assignments with the same weapon_id to ensure all models
	# with the same weapon type are batched together
	var merged_assignments = {}
	for assignment in pending_assignments:
		var weapon_id = assignment.get("weapon_id", "")
		var target_unit_id = assignment.get("target_unit_id", "")

		# Create unique key: weapon_id + target_unit_id
		var key = weapon_id + "_" + target_unit_id

		if merged_assignments.has(key):
			# Merge model_ids with existing assignment
			var existing = merged_assignments[key]
			var existing_model_ids = existing.get("model_ids", [])
			var new_model_ids = assignment.get("model_ids", [])

			# Combine model IDs (avoid duplicates)
			for model_id in new_model_ids:
				if model_id not in existing_model_ids:
					existing_model_ids.append(model_id)

			existing["model_ids"] = existing_model_ids

			# Merge modifiers if present
			if assignment.has("modifiers"):
				existing["modifiers"] = assignment.get("modifiers", {})
		else:
			# First assignment for this weapon+target combo
			merged_assignments[key] = assignment.duplicate(true)

	# Convert merged assignments back to array
	confirmed_assignments = []
	for key in merged_assignments:
		confirmed_assignments.append(merged_assignments[key])

	pending_assignments.clear()

	var _perf_t0 := Time.get_ticks_usec()

	# T3-3: Auto-inject Extra Attacks ranged weapons if not already assigned
	_auto_inject_extra_attacks_weapons_shooting()

	var _perf_t1 := Time.get_ticks_usec()
	emit_signal("shooting_begun", active_shooter_id)
	log_phase_message("Confirmed targets, ready to resolve shooting")
	var _perf_t2 := Time.get_ticks_usec()

	# Codex: Orks (11e) Madcap Meks — Unpredictable Genius (WP-O34): rolled now
	# that every target is known; a Hop Splat with several candidates pauses
	# for the player's pick (resume: _ork11e_resume_after_hop_splat).
	var ork11e_ug: Dictionary = Ork11eDetachments.ug_on_targets_confirmed(active_shooter_id, confirmed_assignments, int(action.get("payload", {}).get("rng_seed", -1)))
	if ork11e_ug.get("applied", false):
		# T06: a die was rolled against these targets — they are locked in.
		_wo_lock_reason = "Unpredictable Genius has already been rolled against these targets"
	if not ork11e_ug.get("hop_splat_options", []).is_empty():
		var hs_entry: Dictionary = Ork11eDetachments.hop_splat_window_entry(active_shooter_id, str(ork11e_ug.target), ork11e_ug.hop_splat_options)
		if open_stratagem_windows([hs_entry], "_ork11e_resume_after_hop_splat", hs_entry.ctx):
			return create_result(true, ork11e_ug.diffs + consume_window_diffs())
		ork11e_ug.diffs.append_array(consume_window_diffs())
	return _ork11e_merge_front(ork11e_ug.diffs, _confirm_targets_tail(_perf_t0, _perf_t1, _perf_t2))

## Codex: Orks (11e) Hop Splat window answered (WP-O34): resolve it, then the
## rest of CONFIRM_TARGETS.
func _ork11e_resume_after_hop_splat(ctx: Dictionary, window_result: Dictionary) -> Dictionary:
	var hs_diffs: Array = Ork11eDetachments.hop_splat_after_window(ctx, window_result)
	var now := Time.get_ticks_usec()
	return _ork11e_merge_front(hs_diffs, _confirm_targets_tail(now, now, now))

func _ork11e_merge_front(diffs: Array, result: Dictionary) -> Dictionary:
	if diffs.is_empty():
		return result
	var merged: Array = diffs.duplicate()
	merged.append_array(result.get("changes", []))
	result["changes"] = merged
	return result

## CONFIRM_TARGETS after the targets are merged (reactive stratagems, then
## resolution) — split out for the Hop Splat pause. (WP-O6: the 10e Distraction
## Grot check that came first is gone with the ability.)
func _confirm_targets_tail(_perf_t0: int, _perf_t1: int, _perf_t2: int) -> Dictionary:
	var _perf_t3 := Time.get_ticks_usec()
	# Measured at ~3 ms total on a 26-unit board, so this normally stays quiet;
	# it exists because the fight phase's equivalent confirm was the source of
	# a multi-second stall and this is the path to check first if shooting ever
	# develops the same symptom.
	if (_perf_t3 - _perf_t0) / 1000.0 >= 5.0:
		DebugLogger.info("[PERF] ShootingPhase.CONFIRM_TARGETS: inject=%.1fms shooting_begun=%.1fms post=%.1fms" % [
			(_perf_t1 - _perf_t0) / 1000.0,
			(_perf_t2 - _perf_t1) / 1000.0,
			(_perf_t3 - _perf_t2) / 1000.0
		])
	# REACTIVE STRATAGEMS: Check if defending player can use Go to Ground or Smokescreen
	var _perf_t4 := Time.get_ticks_usec()
	var reactive_check = _check_reactive_stratagems()
	var _perf_reactive_ms := (Time.get_ticks_usec() - _perf_t4) / 1000.0
	if _perf_reactive_ms >= 5.0:
		DebugLogger.info("[PERF] ShootingPhase.CONFIRM_TARGETS: reactive_stratagems=%.1fms" % [_perf_reactive_ms])
	if reactive_check.has_opportunities:
		# Pause for defender to decide on reactive stratagems
		awaiting_reactive_stratagem = true
		resolution_state = {
			"phase": "awaiting_reactive_stratagem",
			"assignments": confirmed_assignments
		}
		log_phase_message("Opponent may use reactive stratagems...")
		emit_signal("reactive_stratagem_opportunity",
			reactive_check.defending_player,
			reactive_check.available_stratagems,
			reactive_check.target_unit_ids)
		return create_result(true, [], "Awaiting defender stratagem decision", {
			"reactive_stratagem_opportunity": true,
			"defending_player": reactive_check.defending_player,
			"available_stratagems": reactive_check.available_stratagems,
			"target_unit_ids": reactive_check.target_unit_ids
		})

	# No reactive stratagems available - proceed to resolution
	return _continue_after_reactive_stratagems()

func _continue_after_reactive_stratagems() -> Dictionary:
	"""Continue shooting resolution after reactive stratagem decision (or if none available)."""
	# Check if we have multiple weapon types - if so, show weapon order dialog
	var unique_weapons = {}
	for assignment in confirmed_assignments:
		var weapon_id = assignment.get("weapon_id", "")
		unique_weapons[weapon_id] = true

	var weapon_count = unique_weapons.size()
	DebugLogger.info(str("ShootingPhase: Merged and confirmed %d assignments with %d unique weapon types" % [confirmed_assignments.size(), weapon_count]))

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ WEAPON COUNT CHECK IN _process_confirm_targets")
	DebugLogger.info(str("║ weapon_count: ", weapon_count))
	DebugLogger.info(str("║ Will enter sequential mode: ", weapon_count >= 2))
	DebugLogger.info(str("║ Single weapon path: ", weapon_count == 1))
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	# Show the weapon roll dialog for:
	#   • any multi-weapon shot (choose firing order), OR
	#   • a single-weapon shot in NON-networked play — where the dialog auto-starts
	#     STEP-BY-STEP resolution (hit roll → pause → wound roll → pause → saves) so
	#     the attacker can read each roll and use Command Re-roll between steps.
	# Networked single-weapon shots keep the original one-shot resolution below,
	# because the staged pauses (like Command Re-roll) are single-player/host-only.
	var show_roll_dialog = (weapon_count >= 2) or (weapon_count == 1 and not NetworkManager.is_networked())
	if show_roll_dialog:
		if weapon_count >= 2:
			log_phase_message("Multiple weapon types detected - awaiting weapon order selection")
		else:
			log_phase_message("Single weapon - awaiting step-by-step roll dialog")
		emit_signal("weapon_order_required", confirmed_assignments)

		# Initialize resolution state for weapon ordering
		resolution_state = {
			"phase": "awaiting_weapon_order",
			"assignments": confirmed_assignments
		}

		# Return success but don't resolve yet - wait for weapon order
		# IMPORTANT: Include assignments in result for multiplayer sync
		return create_result(true, [], "Awaiting weapon order selection", {
			"weapon_order_required": true,
			"confirmed_assignments": confirmed_assignments
		})

	# Single weapon type (networked) - proceed with normal one-shot resolution
	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ SINGLE WEAPON PATH - _process_confirm_targets")
	DebugLogger.info("║ Initializing resolution_state with mode: 'ready'")
	DebugLogger.info("║ This is NOT sequential mode")
	DebugLogger.info("║ Calling _process_resolve_shooting() directly")
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	# Initialize resolution state
	resolution_state = {
		"current_assignment": 0,
		"phase": "ready",  # ready, hitting, wounding, saving, damage
		"mode": ""  # EXPLICITLY empty - not sequential
	}

	# AUTO-RESOLVE: Immediately trigger shooting resolution
	var initial_result = create_result(true, [])

	# Call resolution directly
	var resolve_result = _process_resolve_shooting({})

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ SINGLE WEAPON - _process_resolve_shooting returned")
	DebugLogger.info(str("║ resolve_result.success: ", resolve_result.success))
	DebugLogger.info(str("║ resolve_result has save_data_list: ", resolve_result.has("save_data_list")))
	if resolve_result.has("save_data_list"):
		DebugLogger.info(str("║ save_data_list size: ", resolve_result.get("save_data_list", []).size()))
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	# Combine results
	if resolve_result.success:
		initial_result.changes.append_array(resolve_result.get("changes", []))
		initial_result["dice"] = resolve_result.get("dice", [])
		initial_result["log_text"] = resolve_result.get("log_text", "")
		# CRITICAL: Copy save_data_list for multiplayer sync
		if resolve_result.has("save_data_list"):
			initial_result["save_data_list"] = resolve_result.get("save_data_list", [])
		# CRITICAL FIX: Copy sequential_pause and related data for single weapon miss!
		if resolve_result.has("sequential_pause"):
			initial_result["sequential_pause"] = resolve_result.get("sequential_pause", false)
			initial_result["remaining_weapons"] = resolve_result.get("remaining_weapons", [])
			initial_result["last_weapon_result"] = resolve_result.get("last_weapon_result", {})
			initial_result["current_weapon_index"] = resolve_result.get("current_weapon_index", 0)
			initial_result["total_weapons"] = resolve_result.get("total_weapons", 1)

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ SINGLE WEAPON - Returning from _process_confirm_targets")
	if initial_result.has("sequential_pause"):
		DebugLogger.info(str("║ ✅ sequential_pause INCLUDED in result: ", initial_result.get("sequential_pause", false)))
		DebugLogger.info(str("║ ✅ remaining_weapons size: ", initial_result.get("remaining_weapons", []).size()))
		DebugLogger.info(str("║ ✅ last_weapon_result exists: ", initial_result.has("last_weapon_result")))
	elif resolve_result.has("save_data_list") and not resolve_result.get("save_data_list", []).is_empty():
		DebugLogger.info("║ Result will trigger saves dialog")
		DebugLogger.info("║ After saves, _process_apply_saves will be called")
	else:
		DebugLogger.info("║ ⚠️  WARNING: No sequential_pause or save_data_list in result!")
		DebugLogger.info("║ This weapon likely missed and dialog won't show!")
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	return initial_result

func _process_resolve_shooting(action: Dictionary) -> Dictionary:
	# Trigger attack animation on the shooting unit
	_trigger_unit_animation(active_shooter_id, "attack")

	# VERBOSE COMBAT LOG: Emit combat header BEFORE resolution so dice can display in real-time
	var _vcl_shooter = game_state_snapshot.get("units", {}).get(active_shooter_id, {})
	var _vcl_shooter_name = _vcl_shooter.get("meta", {}).get("name", active_shooter_id)
	if not confirmed_assignments.is_empty():
		var _vcl_target_id = confirmed_assignments[0].get("target_unit_id", "")
		var _vcl_target = game_state_snapshot.get("units", {}).get(_vcl_target_id, {})
		var _vcl_target_name = _vcl_target.get("meta", {}).get("name", _vcl_target_id)
		var _vcl_weapon_id = confirmed_assignments[0].get("weapon_id", "")
		var _vcl_weapon_profile = RulesEngine.get_weapon_profile(_vcl_weapon_id)
		var _vcl_weapon_name = _vcl_weapon_profile.get("name", _vcl_weapon_id)
		GameEventLog.add_combat_header("P%d: %s shoots at %s with %s" % [
			get_current_player(), _vcl_shooter_name, _vcl_target_name, _vcl_weapon_name])

	# T5-MP5: Build resolution_start block and emit locally + include in result for remote sync
	var _rs_weapon_name = ""
	var _rs_target_name = ""
	if not confirmed_assignments.is_empty():
		var _rs_wid = confirmed_assignments[0].get("weapon_id", "")
		_rs_weapon_name = RulesEngine.get_weapon_profile(_rs_wid).get("name", _rs_wid)
		var _rs_tid = confirmed_assignments[0].get("target_unit_id", "")
		_rs_target_name = game_state_snapshot.get("units", {}).get(_rs_tid, {}).get("meta", {}).get("name", _rs_tid)
	var _rs_msg = "%s → %s" % [_rs_weapon_name, _rs_target_name] if _rs_weapon_name != "" else "Beginning attack resolution..."
	var resolution_start_block = {"context": "resolution_start", "message": _rs_msg}
	emit_signal("dice_rolled", resolution_start_block)

	# Build full shoot action for RulesEngine
	# Issue #329: forward action.payload.rng_seed into the dispatched shoot_action so RulesEngine
	# routes it through RNGService (deterministic when test_mode_seed or explicit seed is set)
	var rs_seed: int = action.get("payload", {}).get("rng_seed", -1)
	var shoot_action = {
		"type": "SHOOT",
		"actor_unit_id": active_shooter_id,
		"payload": {
			"assignments": confirmed_assignments,
			"rng_seed": rs_seed,
			# 10.02/10.07: the SELECTED shooting type drives per-attack consequences
			"shooting_type": active_shooting_type
		}
	}

	# Resolve with RulesEngine UP TO WOUNDS (interactive saves)
	var rng_service = RulesEngine.RNGService.new(rs_seed)
	var result = RulesEngine.resolve_shoot_until_wounds(shoot_action, game_state_snapshot, rng_service)

	if not result.success:
		return create_result(false, [], result.get("log_text", "Shooting failed"))

	# ONE SHOT (T4-2): Collect one-shot diffs from result (weapon marked as fired immediately)
	var one_shot_diffs = result.get("one_shot_diffs", [])

	# Record hit/wound dice rolls
	# T5-MP5: Prepend resolution_start block so remote player sees it in broadcast
	var dice_data = [resolution_start_block] + result.get("dice", [])
	for dice_block in result.get("dice", []):
		dice_log.append(dice_block)
		emit_signal("dice_rolled", dice_block)

	log_phase_message(result.get("log_text", "Attack rolls complete"))

	# Emit hit/wound detail lines from dice data
	_emit_verbose_combat_log(active_shooter_id, dice_data, [], 0, "shooting_hits")

	# Extract hit/wound data from dice blocks and store in resolution_state
	# so _process_apply_saves can build accurate last_weapon_result (T4-15)
	var hit_data = {}
	var wound_data = {}
	for dice_block in dice_data:
		var context = dice_block.get("context", "")
		if context == "hit_roll" or context == "to_hit":
			hit_data = {
				"rolls": dice_block.get("rolls_raw", []),
				"modified_rolls": dice_block.get("rolls_modified", []),
				"successes": dice_block.get("successes", 0),
				"total": dice_block.get("rolls_raw", []).size(),
				"rerolls": dice_block.get("rerolls", []),
				"threshold": dice_block.get("threshold", "")
			}
		elif context == "auto_hit":
			hit_data = {
				"rolls": [],
				"modified_rolls": [],
				"successes": dice_block.get("successes", 0),
				"total": dice_block.get("total_attacks", 0),
				"rerolls": [],
				"threshold": "auto",
				"torrent": true
			}
		elif context == "wound_roll" or context == "to_wound":
			wound_data = {
				"rolls": dice_block.get("rolls_raw", []),
				"modified_rolls": dice_block.get("rolls_modified", []),
				"successes": dice_block.get("successes", 0),
				"total": dice_block.get("rolls_raw", []).size(),
				"threshold": dice_block.get("threshold", "")
			}
	resolution_state.last_weapon_dice_data = dice_data
	resolution_state.last_weapon_hit_data = hit_data
	resolution_state.last_weapon_wound_data = wound_data

	# P1-11: Track hits for Sanctified Flames (single-weapon resolve path)
	var resolve_hits = hit_data.get("successes", 0)
	if resolve_hits > 0 and not confirmed_assignments.is_empty():
		var resolve_tid = confirmed_assignments[0].get("target_unit_id", "")
		if resolve_tid != "":
			_targets_hit_by_shooter[resolve_tid] = _targets_hit_by_shooter.get(resolve_tid, 0) + resolve_hits
			DebugLogger.info(str("ShootingPhase: P1-11 Sanctified Flames tracking (resolve): %d hit(s) on %s" % [resolve_hits, resolve_tid]))

	# Check if any saves are needed
	var save_data_list = result.get("save_data_list", [])

	if save_data_list.is_empty():
		# No wounds caused — finalize the combat log card
		GameEventLog.add_combat_result("  Result: No wounds caused — attack missed")
		DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
		DebugLogger.info("║ NO WOUNDS CAUSED - Weapon missed!")
		DebugLogger.info(str("║ resolution_state.mode: '", resolution_state.get("mode", ""), "'"))
		DebugLogger.info(str("║ Is single weapon: ", resolution_state.get("mode", "") == ""))
		DebugLogger.info(str("║ active_shooter_id: ", active_shooter_id))
		DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

		# HAZARDOUS (T2-3): Still process Hazardous check even if weapon missed
		var haz_diffs_on_miss = []
		var hazardous_weapons_on_miss = result.get("hazardous_weapons", [])
		if not hazardous_weapons_on_miss.is_empty():
			DebugLogger.info(str("║ HAZARDOUS: Processing %d hazardous weapon check(s) despite miss" % hazardous_weapons_on_miss.size()))
			var haz_rng = RulesEngine.RNGService.new(rs_seed)  # Issue #329: forward seed
			for haz_weapon in hazardous_weapons_on_miss:
				var haz_result = RulesEngine.resolve_hazardous_check(
					active_shooter_id,
					haz_weapon.get("weapon_id", ""),
					haz_weapon.get("models_that_fired", 0),
					game_state_snapshot,
					haz_rng
				)
				if haz_result.hazardous_triggered:
					haz_diffs_on_miss.append_array(haz_result.diffs)
				for haz_dice in haz_result.dice:
					dice_log.append(haz_dice)
					dice_data.append(haz_dice)
				if haz_result.log_text:
					log_phase_message(haz_result.log_text)
				_log_hazard_to_game_log(haz_result)  # LV2-G1

		# Check if this is single weapon mode (not sequential)
		var mode = resolution_state.get("mode", "")
		if mode != "sequential" and active_shooter_id != "":
			# Single weapon that missed - show results dialog before completing
			DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
			DebugLogger.info("║ 🎯 SINGLE WEAPON MISS - Showing results dialog")
			DebugLogger.info("║ Building last_weapon_result for missed shot...")
			DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

			# Build last weapon result for missed shot
			var last_weapon_result = {}
			if not confirmed_assignments.is_empty():
				var assignment = confirmed_assignments[0]
				var weapon_id = assignment.get("weapon_id", "")
				var weapon_profile = RulesEngine.get_weapon_profile(weapon_id)
				var target_unit_id = assignment.get("target_unit_id", "")
				var target_unit = get_unit(target_unit_id)

				# T4-15: Retrieve hit/wound data from resolution_state (stored earlier in this function)
				var miss_hit_data = resolution_state.get("last_weapon_hit_data", {})
				var miss_wound_data = resolution_state.get("last_weapon_wound_data", {})
				var hits = miss_hit_data.get("successes", 0)
				var total_attacks = miss_hit_data.get("total", 0)

				var _dice_tgt_meta = target_unit.get("meta", {})
				last_weapon_result = {
					"weapon_id": weapon_id,
					"weapon_name": weapon_profile.get("name", weapon_id),
					"target_unit_id": target_unit_id,
					"target_unit_name": _dice_tgt_meta.get("display_name", _dice_tgt_meta.get("name", target_unit_id)),
					"hits": hits,
					"wounds": 0,  # No wounds caused
					"saves_failed": 0,
					"casualties": 0,
					"total_attacks": total_attacks,
					"dice_rolls": dice_data,
					"hit_data": miss_hit_data,
					"wound_data": miss_wound_data
				}

				# P1-11: Track hits for Sanctified Flames (single weapon miss path)
				if hits > 0 and target_unit_id != "":
					_targets_hit_by_shooter[target_unit_id] = _targets_hit_by_shooter.get(target_unit_id, 0) + hits
					DebugLogger.info(str("ShootingPhase: P1-11 Sanctified Flames tracking (single miss): %d hit(s) on %s" % [hits, target_unit_id]))

				DebugLogger.info("║ last_weapon_result built:")
				DebugLogger.info(str("║   weapon: ", last_weapon_result.get("weapon_name", "")))
				DebugLogger.info(str("║   hits: ", hits, " / ", total_attacks))
				DebugLogger.info("║   wounds: 0 (missed)")
				DebugLogger.info("║   casualties: 0")

				# Record completed weapon so phase_shooting_log captures single-weapon miss
				if not resolution_state.has("completed_weapons"):
					resolution_state["completed_weapons"] = []
				var _miss_tgt_meta = target_unit.get("meta", {})
				resolution_state.completed_weapons.append({
					"weapon_id": weapon_id,
					"target_unit_id": target_unit_id,
					"target_unit_name": _miss_tgt_meta.get("display_name", _miss_tgt_meta.get("name", target_unit_id)),
					"wounds": 0,
					"casualties": 0,
					"hits": hits,
					"total_attacks": total_attacks,
					"saves_failed": 0,
					"dice_rolls": dice_data,
					"hit_data": miss_hit_data,
					"wound_data": miss_wound_data
				})

			# Emit signal with EMPTY remaining_weapons (signals completion)
			DebugLogger.info("║")
			DebugLogger.info("║ 📡 EMITTING next_weapon_confirmation_required SIGNAL (for miss)")
			DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

			emit_signal("next_weapon_confirmation_required", [], 0, last_weapon_result)

			# Return with pause indicator - completion will happen when user clicks "Complete Shooting"
			# IMPORTANT: Do NOT mark has_shot yet - that happens when user confirms
			# ONE SHOT (T4-2): Include one-shot diffs even on miss
			var miss_one_shot_changes = haz_diffs_on_miss.duplicate()
			miss_one_shot_changes.append_array(one_shot_diffs)
			return create_result(true, miss_one_shot_changes, "Single weapon missed - awaiting confirmation", {
				"sequential_pause": true,
				"remaining_weapons": [],
				"last_weapon_result": last_weapon_result,
				"current_weapon_index": 0,
				"total_weapons": 1,
				"dice": dice_data
			})

		# Sequential mode - already handled with dialog
		DebugLogger.info("║ Sequential mode - completing immediately")
		var shooter_id = active_shooter_id  # Store before clearing
		var changes = [{
			"op": "set",
			"path": "units.%s.flags.has_shot" % active_shooter_id,
			"value": true
		}]
		changes.append(_hidden_shot_stamp(active_shooter_id))
		# HAZARDOUS (T2-3): Include hazardous diffs in changes
		changes.append_array(haz_diffs_on_miss)
		# ONE SHOT (T4-2): Include one-shot diffs in changes
		changes.append_array(one_shot_diffs)

		units_that_shot.append(active_shooter_id)
		# Return shooter to idle animation
		_trigger_unit_animation(active_shooter_id, "idle")
		_record_completed_weapons_to_phase_log(shooter_id)  # T5-UX9: capture before clearing
		active_shooter_id = ""
		confirmed_assignments.clear()
		resolution_state.clear()

		# Emit signal to clear visuals
		emit_signal("shooting_resolved", shooter_id, "", {"casualties": 0})

		return create_result(true, changes, "No wounds caused", {"dice": dice_data})

	# Store save data and trigger interactive saves
	pending_save_data = save_data_list

	# HAZARDOUS (T2-3): Store hazardous weapon data for post-save resolution
	pending_hazardous_weapons = result.get("hazardous_weapons", [])

	# ONE SHOT (T4-2): Store one-shot diffs for inclusion in saves result
	pending_one_shot_diffs = one_shot_diffs

	# T5-MP4-RELIABILITY: stamp every entry with a unique broadcast id BEFORE
	# emitting locally / bundling into the result, so the defender's controller
	# and the attacker's ack/retry timer have a precise match key.
	var broadcast_id := _generate_save_broadcast_id()
	_stamp_save_broadcast_id(save_data_list, broadcast_id)

	# LOGGING: Track saves_required emission
	var timestamp = Time.get_ticks_msec()
	var save_context = {
		"timestamp": timestamp,
		"source": "ShootingPhase._process_resolve_shooting",
		"save_count": save_data_list.size(),
		"target": save_data_list[0].get("target_unit_id", "unknown") if save_data_list.size() > 0 else "none",
		"weapon": save_data_list[0].get("weapon_name", "unknown") if save_data_list.size() > 0 else "none",
		"wounds": save_data_list[0].get("wounds_to_save", 0) if save_data_list.size() > 0 else 0,
		"broadcast_id": broadcast_id
	}
	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ SAVES_REQUIRED EMISSION #1 (from resolve_shooting)")
	DebugLogger.info(str("║ Timestamp: ", timestamp))
	DebugLogger.info("║ Source: ShootingPhase._process_resolve_shooting (line 444)")
	DebugLogger.info(str("║ Target: ", save_context.target))
	DebugLogger.info(str("║ Weapon: ", save_context.weapon))
	DebugLogger.info(str("║ Wounds: ", save_context.wounds))
	DebugLogger.info(str("║ Broadcast ID: ", broadcast_id))
	DebugLogger.info(str("║ Save data list size: ", save_data_list.size()))
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	# Emit signal to show save dialog (handled by ShootingController or Main)
	emit_signal("saves_required", save_data_list)

	log_phase_message("Awaiting defender to make saves...")

	# Return success but NO changes yet - changes will come after saves resolved
	# Include save_data_list in result so it can be broadcast to clients
	return create_result(true, [], "Awaiting save resolution", {
		"dice": dice_data,
		"save_data_list": save_data_list  # IMPORTANT: For multiplayer sync
	})

func _process_skip_unit(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	
	units_that_shot.append(unit_id)
	
	var changes = [{
		"op": "set",
		"path": "units.%s.flags.has_shot" % unit_id,
		"value": true
	}]
	
	# Clear any active state
	if active_shooter_id == unit_id:
		active_shooter_id = ""
		pending_assignments.clear()
		confirmed_assignments.clear()
	
	var unit = get_unit(unit_id)
	log_phase_message("Skipped shooting for %s" % unit.get("meta", {}).get("name", unit_id))
	
	return create_result(true, changes)

func _process_perform_secondary_action(action: Dictionary) -> Dictionary:
	"""Process a unit performing a secondary mission action (gives up shooting)."""
	var unit_id = action.get("actor_unit_id", "")
	var payload = action.get("payload", {})
	var action_name = payload.get("action_name", "")

	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var player = get_current_player()

	DebugLogger.info(str("ShootingPhase: %s performs action '%s' (gives up shooting)" % [unit_name, action_name]))

	# Mark unit as having shot (it gave up shooting to perform the action)
	units_that_shot.append(unit_id)
	var changes = [{
		"op": "set",
		"path": "units.%s.flags.has_shot" % unit_id,
		"value": true
	}, {
		"op": "set",
		"path": "units.%s.flags.performed_action" % unit_id,
		"value": action_name
	}]

	# Clear active state if this unit was selected
	if active_shooter_id == unit_id:
		active_shooter_id = ""
		pending_assignments.clear()
		confirmed_assignments.clear()

	# Determine location context for the action
	var action_data = {
		"action_name": action_name,
		"completed": true,
		"unit_id": unit_id,
	}

	match action_name:
		"Establish Locus":
			action_data["location"] = _determine_locus_location(unit_id, player)
		"Deploy Teleport Homer":
			action_data["location"] = _determine_homer_location(unit_id, player)
		"Cleanse":
			action_data["location"] = "objective"
			var obj_id = _determine_cleanse_objective(unit_id)
			if obj_id != "":
				action_data["objective_id"] = obj_id
		"Plunder":
			# Eligibility was checked in _validate_perform_secondary_action.
			action_data["location"] = "terrain"
			var terrain = _get_plunder_terrain_for_unit(unit_id, player)
			action_data["terrain_id"] = terrain.get("id", "")

	# Report action completion to SecondaryMissionManager
	SecondaryMissionManager.on_action_completed(player, action_data)

	log_phase_message("%s performs %s (gives up shooting)" % [unit_name, action_name])

	# 19.01: an Attached unit is one unit — its attached CHARACTER(s) /
	# bodyguard gave up shooting with it.
	changes.append_array(_mirror_action_to_attached_group(unit_id, changes))

	return create_result(true, changes)

# ============================================================================
# BURN OBJECTIVE — Scorched Earth mission action
# ============================================================================

func _validate_burn_objective(action: Dictionary) -> Dictionary:
	"""Validate a burn objective action for Scorched Earth mission."""
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}

	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found"]}

	if unit.get("owner", 0) != get_current_player():
		return {"valid": false, "errors": ["Unit does not belong to active player"]}

	# Same eligibility as shooting (Favoured Conservai waives the
	# Advance restriction)
	if not _can_unit_perform_action(unit):
		return {"valid": false, "errors": ["Unit is not eligible to perform burn action"]}

	if _attached_group_has_shot(unit_id):
		return {"valid": false, "errors": ["Unit has already shot/acted this phase"]}

	var objective_id = action.get("objective_id", "")
	if objective_id == "":
		return {"valid": false, "errors": ["Missing objective_id"]}

	# Verify the objective is actually burnable by this unit
	var burnable = MissionManager.get_burnable_objectives_for_unit(unit_id)
	var found = false
	for b in burnable:
		if b.objective_id == objective_id:
			found = true
			break

	if not found:
		return {"valid": false, "errors": ["Objective %s is not burnable by this unit" % objective_id]}

	return {"valid": true, "errors": []}

func _process_burn_objective(action: Dictionary) -> Dictionary:
	"""Process a burn objective action — unit gives up shooting to burn an objective."""
	var unit_id = action.get("actor_unit_id", "")
	var objective_id = action.get("objective_id", "")

	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var player = get_current_player()

	DebugLogger.info(str("ShootingPhase: %s burns objective %s (gives up shooting)" % [unit_name, objective_id]))

	# Mark unit as having shot (it gave up shooting to burn)
	units_that_shot.append(unit_id)
	var changes = [{
		"op": "set",
		"path": "units.%s.flags.has_shot" % unit_id,
		"value": true
	}]

	# Also mark as unable to charge this turn (burn action costs charging too)
	changes.append({
		"op": "set",
		"path": "units.%s.flags.burned_objective" % unit_id,
		"value": true
	})

	# Clear active state if this unit was selected
	if active_shooter_id == unit_id:
		active_shooter_id = ""
		pending_assignments.clear()
		confirmed_assignments.clear()

	# Register the burn with MissionManager
	var success = MissionManager.register_burn_action(unit_id, objective_id)
	var obj_label = _friendly_objective_name(objective_id)
	if success:
		log_phase_message("SCORCHED EARTH: %s burned %s for Player %d" % [unit_name, obj_label, player])
	else:
		log_phase_message("ERROR: Burn action failed for %s on %s" % [unit_name, obj_label])

	# 19.01: an Attached unit is one unit — its attached CHARACTER(s) /
	# bodyguard gave up shooting with it.
	changes.append_array(_mirror_action_to_attached_group(unit_id, changes))

	return create_result(true, changes)

func _get_burn_objective_options(unit_id: String) -> Array:
	"""Get available burn objective options for a unit (Scorched Earth mission only).
	Returns array of {objective_id, zone, burn_vp, position}."""
	if not MissionManager or not MissionManager.is_scorched_earth_mission():
		return []

	var unit = get_unit(unit_id)
	if unit.is_empty():
		return []

	# Unit must not be battle-shocked
	if unit.get("flags", {}).get("battle_shocked", false):
		return []

	return MissionManager.get_burnable_objectives_for_unit(unit_id)

# ============================================================================
# PERFORM RITUAL ACTION — The Ritual mission action
# ============================================================================

func _validate_perform_ritual_action(action: Dictionary) -> Dictionary:
	"""Validate a ritual action for The Ritual mission."""
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}

	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found"]}

	if unit.get("owner", 0) != get_current_player():
		return {"valid": false, "errors": ["Unit does not belong to active player"]}

	# Same eligibility as shooting — deployed, not battle-shocked, hasn't shot
	# (Favoured Conservai — Emissaries Imperatus — waives the Advance restriction)
	if not _can_unit_perform_action(unit):
		return {"valid": false, "errors": ["Unit is not eligible to perform ritual action"]}

	if _attached_group_has_shot(unit_id):
		return {"valid": false, "errors": ["Unit has already shot/acted this phase"]}

	# Units that Advanced or Fell Back cannot perform actions.
	# Codex: Adeptus Custodes (11e) Emissaries Imperatus Favoured CONSERVAI: being
	# selected to advance does not prevent starting an action (WP-C46; replaces
	# the 10e Silent Hunters Skin-Crawling Disorientation).
	var flags = unit.get("flags", {})
	if flags.get("advanced", false):
		if _cus11e_det().move_keeps_action_eligibility(unit):
			log_phase_message("Favoured Conservai (Emissaries Imperatus): %s may perform actions despite Advancing" % unit.get("meta", {}).get("name", unit_id))
		else:
			return {"valid": false, "errors": ["Unit Advanced this turn and cannot perform actions"]}
	if flags.get("fell_back", false):
		return {"valid": false, "errors": ["Unit Fell Back this turn and cannot perform actions"]}

	var objective_id = action.get("objective_id", "")
	if objective_id == "":
		return {"valid": false, "errors": ["Missing objective_id"]}

	# Verify the objective is valid for ritual by this unit
	var ritual_targets = MissionManager.get_ritual_objectives_for_unit(unit_id)
	var found = false
	for r in ritual_targets:
		if r.objective_id == objective_id:
			found = true
			break

	if not found:
		return {"valid": false, "errors": ["Objective %s is not a valid ritual target for this unit" % objective_id]}

	return {"valid": true, "errors": []}

func _process_perform_ritual_action(action: Dictionary) -> Dictionary:
	"""Process a ritual action — unit gives up shooting to perform ritual at objective."""
	var unit_id = action.get("actor_unit_id", "")
	var objective_id = action.get("objective_id", "")

	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var player = get_current_player()

	DebugLogger.info(str("ShootingPhase: %s performs ritual action at %s (gives up shooting)" % [unit_name, objective_id]))

	# Mark unit as having shot (it gave up shooting to perform the ritual)
	units_that_shot.append(unit_id)
	var changes = [{
		"op": "set",
		"path": "units.%s.flags.has_shot" % unit_id,
		"value": true
	}]

	# Mark as unable to charge this turn (action costs charging too)
	changes.append({
		"op": "set",
		"path": "units.%s.flags.performed_ritual" % unit_id,
		"value": true
	})

	# Clear active state if this unit was selected
	if active_shooter_id == unit_id:
		active_shooter_id = ""
		pending_assignments.clear()
		confirmed_assignments.clear()

	# Register the ritual with MissionManager
	var success = MissionManager.register_ritual_action(unit_id, objective_id)
	var _ritual_obj_label = _friendly_objective_name(objective_id)
	if success:
		log_phase_message("THE RITUAL: %s performed ritual at %s for Player %d" % [unit_name, _ritual_obj_label, player])
	else:
		log_phase_message("ERROR: Ritual action failed for %s at %s" % [unit_name, _ritual_obj_label])

	# 19.01: an Attached unit is one unit — its attached CHARACTER(s) /
	# bodyguard gave up shooting with it.
	changes.append_array(_mirror_action_to_attached_group(unit_id, changes))

	return create_result(true, changes)

func _get_ritual_action_options(unit_id: String) -> Array:
	"""Get available ritual action options for a unit (The Ritual mission only).
	Returns array of {objective_id, position}."""
	if not MissionManager or not MissionManager.is_ritual_mission():
		return []

	var unit = get_unit(unit_id)
	if unit.is_empty():
		return []

	# Unit must not be battle-shocked
	if unit.get("flags", {}).get("battle_shocked", false):
		return []

	# Units that Advanced or Fell Back cannot perform actions.
	# Codex: Adeptus Custodes (11e) Emissaries Imperatus Favoured CONSERVAI: being
	# selected to advance does not prevent starting an action (WP-C46; replaces
	# the 10e Silent Hunters Skin-Crawling Disorientation).
	if unit.get("flags", {}).get("advanced", false) \
			and not _cus11e_det().move_keeps_action_eligibility(unit):
		return []
	if unit.get("flags", {}).get("fell_back", false):
		return []

	return MissionManager.get_ritual_objectives_for_unit(unit_id)

# ============================================================================
# PERFORM TERRAFORM ACTION — Terraform mission action
# ============================================================================

func _validate_perform_terraform_action(action: Dictionary) -> Dictionary:
	"""Validate a terraform action for the Terraform mission."""
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}

	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found"]}

	if unit.get("owner", 0) != get_current_player():
		return {"valid": false, "errors": ["Unit does not belong to active player"]}

	# Same eligibility as shooting — deployed, not battle-shocked, hasn't shot
	# (Favoured Conservai — Emissaries Imperatus — waives the Advance restriction)
	if not _can_unit_perform_action(unit):
		return {"valid": false, "errors": ["Unit is not eligible to perform terraform action"]}

	if _attached_group_has_shot(unit_id):
		return {"valid": false, "errors": ["Unit has already shot/acted this phase"]}

	# Units that Advanced or Fell Back cannot perform actions.
	# Codex: Adeptus Custodes (11e) Emissaries Imperatus Favoured CONSERVAI: being
	# selected to advance does not prevent starting an action (WP-C46; replaces
	# the 10e Silent Hunters Skin-Crawling Disorientation).
	var flags = unit.get("flags", {})
	if flags.get("advanced", false):
		if _cus11e_det().move_keeps_action_eligibility(unit):
			log_phase_message("Favoured Conservai (Emissaries Imperatus): %s may perform actions despite Advancing" % unit.get("meta", {}).get("name", unit_id))
		else:
			return {"valid": false, "errors": ["Unit Advanced this turn and cannot perform actions"]}
	if flags.get("fell_back", false):
		return {"valid": false, "errors": ["Unit Fell Back this turn and cannot perform actions"]}

	var objective_id = action.get("objective_id", "")
	if objective_id == "":
		return {"valid": false, "errors": ["Missing objective_id"]}

	# Verify the objective is valid for terraforming by this unit
	var terraform_targets = MissionManager.get_terraformable_objectives_for_unit(unit_id)
	var found = false
	for t in terraform_targets:
		if t.objective_id == objective_id:
			found = true
			break

	if not found:
		return {"valid": false, "errors": ["Objective %s is not a valid terraform target for this unit" % objective_id]}

	return {"valid": true, "errors": []}

func _process_perform_terraform_action(action: Dictionary) -> Dictionary:
	"""Process a terraform action — unit gives up shooting to terraform an objective."""
	var unit_id = action.get("actor_unit_id", "")
	var objective_id = action.get("objective_id", "")

	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var player = get_current_player()

	DebugLogger.info(str("ShootingPhase: %s performs terraform action at %s (gives up shooting)" % [unit_name, objective_id]))

	# Mark unit as having shot (it gave up shooting to perform the terraform)
	units_that_shot.append(unit_id)
	var changes = [{
		"op": "set",
		"path": "units.%s.flags.has_shot" % unit_id,
		"value": true
	}]

	# Mark as unable to charge this turn (action costs charging too)
	changes.append({
		"op": "set",
		"path": "units.%s.flags.performed_terraform" % unit_id,
		"value": true
	})

	# Clear active state if this unit was selected
	if active_shooter_id == unit_id:
		active_shooter_id = ""
		pending_assignments.clear()
		confirmed_assignments.clear()

	# Register the terraform with MissionManager
	var success = MissionManager.register_terraform_action(unit_id, objective_id)
	var _tf_obj_label = _friendly_objective_name(objective_id)
	if success:
		var is_flip = action.get("is_flip", false)
		if is_flip:
			log_phase_message("TERRAFORM: %s flipped %s for Player %d" % [unit_name, _tf_obj_label, player])
		else:
			log_phase_message("TERRAFORM: %s terraformed %s for Player %d" % [unit_name, _tf_obj_label, player])
	else:
		log_phase_message("ERROR: Terraform action failed for %s at %s" % [unit_name, _tf_obj_label])

	# 19.01: an Attached unit is one unit — its attached CHARACTER(s) /
	# bodyguard gave up shooting with it.
	changes.append_array(_mirror_action_to_attached_group(unit_id, changes))

	return create_result(true, changes)

func _get_terraform_action_options(unit_id: String) -> Array:
	"""Get available terraform action options for a unit (Terraform mission only).
	Returns array of {objective_id, zone, position, is_flip}."""
	if not MissionManager or not MissionManager.is_terraform_mission():
		return []

	var unit = get_unit(unit_id)
	if unit.is_empty():
		return []

	# Unit must not be battle-shocked
	if unit.get("flags", {}).get("battle_shocked", false):
		return []

	# Units that Advanced or Fell Back cannot perform actions.
	# Codex: Adeptus Custodes (11e) Emissaries Imperatus Favoured CONSERVAI: being
	# selected to advance does not prevent starting an action (WP-C46; replaces
	# the 10e Silent Hunters Skin-Crawling Disorientation).
	if unit.get("flags", {}).get("advanced", false) \
			and not _cus11e_det().move_keeps_action_eligibility(unit):
		return []
	if unit.get("flags", {}).get("fell_back", false):
		return []

	return MissionManager.get_terraformable_objectives_for_unit(unit_id)

func _determine_locus_location(unit_id: String, player: int) -> String:
	"""Determine location qualifier for Establish Locus: 'opponent_zone' or 'center'."""
	var unit = get_unit(unit_id)
	var opponent = 2 if player == 1 else 1
	var opponent_zone = SecondaryMissionManager._get_deployment_zone_polygon(opponent)

	# Check opponent zone first (higher VP)
	if not opponent_zone.is_empty() and SecondaryMissionManager._is_unit_wholly_in_zone(unit, opponent_zone):
		return "opponent_zone"

	# Check within 6" of board center
	var board_width = GameState.state.get("board", {}).get("size", {}).get("width", 44)
	var board_height = GameState.state.get("board", {}).get("size", {}).get("height", 60)
	var center_px = Vector2(
		Measurement.inches_to_px(board_width / 2.0),
		Measurement.inches_to_px(board_height / 2.0)
	)
	if SecondaryMissionManager._has_model_within_range(unit, center_px, Measurement.inches_to_px(6.0)):
		return "center"

	return "other"

func _determine_homer_location(unit_id: String, player: int) -> String:
	"""Determine location qualifier for Deploy Teleport Homer: 'opponent_zone' or 'other'."""
	var unit = get_unit(unit_id)
	var opponent = 2 if player == 1 else 1
	var opponent_zone = SecondaryMissionManager._get_deployment_zone_polygon(opponent)

	if not opponent_zone.is_empty() and SecondaryMissionManager._is_unit_wholly_in_zone(unit, opponent_zone):
		return "opponent_zone"

	return "other"

func _determine_cleanse_objective(unit_id: String) -> String:
	"""Find the objective within control range (3\" + 20mm marker base) of a unit's model for Cleanse action. Returns objective id or empty.
	11e: only NON-HOME objectives are cleansable, and an objective another
	unit already cleansed this turn is skipped in favour of a fresh one
	(officially each Cleanse targets one objective; duplicates score nothing)."""
	var unit = get_unit(unit_id)
	var objectives = GameState.state.get("board", {}).get("objectives", [])
	var control_radius = Measurement.inches_to_px(3.78740157)
	var player = get_current_player()

	var fallback := ""
	for obj in objectives:
		var obj_pos = obj.get("position", Vector2.ZERO)
		if obj_pos == Vector2.ZERO:
			continue
		var obj_id = str(obj.get("id", ""))
		if GameConstants.edition >= 11 and _is_home_objective(obj):
			continue
		if not SecondaryMissionManager._unit_in_objective_range(unit, obj):
			continue
		if _objective_cleansed_this_turn(player, obj_id):
			if fallback == "":
				fallback = obj_id
			continue
		return obj_id

	return fallback

func _is_home_objective(obj: Dictionary) -> bool:
	"""A home objective sits in a player's deployment zone (zone 'player1'/'player2')."""
	return str(obj.get("zone", "")).begins_with("player")

func _objective_cleansed_this_turn(player: int, obj_id: String) -> bool:
	for action in SecondaryMissionManager._active_actions.get(str(player), []):
		if action.get("action_name", "") == "Cleanse" and action.get("completed", false) \
				and str(action.get("objective_id", "")) == obj_id:
			return true
	return false

func _plunder_done_this_turn(player: int) -> bool:
	"""11e Plunder is once per turn."""
	for action in SecondaryMissionManager._active_actions.get(str(player), []):
		if action.get("action_name", "") == "Plunder" and action.get("completed", false):
			return true
	return false

func _get_plunder_terrain_for_unit(unit_id: String, player: int) -> Dictionary:
	"""11e Plunder: the unit must be within a terrain area that is NOT within
	the player's territory (approximated as their board half, matching the
	Outflank/Beacon territory approximation). Returns the terrain dict or {}."""
	var unit = get_unit(unit_id)
	var terrain_mgr = get_node_or_null("/root/TerrainManager")
	if not terrain_mgr:
		return {}
	var territory = SecondaryMissionManager._get_own_territory_rect(player)

	for terrain in terrain_mgr.terrain_features:
		if terrain.get("type", "") == "barricade":
			continue  # barricades are obstacles, not terrain areas
		var polygon: PackedVector2Array = terrain.get("polygon", PackedVector2Array())
		if polygon.is_empty():
			continue
		# "not within your territory": no part of the terrain area inside it
		if not territory.is_empty():
			var any_inside := false
			for p in polygon:
				if p.x >= territory["min"].x and p.x <= territory["max"].x \
						and p.y >= territory["min"].y and p.y <= territory["max"].y:
					any_inside = true
					break
			if any_inside:
				continue
		# Unit is within the terrain area while any alive model is inside it
		for model in unit.get("models", []):
			if not model.get("alive", true):
				continue
			var pos = model.get("position")
			if pos == null:
				continue
			if pos is Dictionary:
				pos = Vector2(pos.get("x", 0), pos.get("y", 0))
			if Geometry2D.is_point_in_polygon(pos, polygon):
				return terrain
	return {}

# ── B1: 11e ACTIONS (16.00-16.01) — start a generic action, giving up shooting ──

func get_startable_11e_actions(unit_id: String) -> Array:
	# Exposed for ShootingController's "Start Action" button.
	if GameConstants.edition < 11:
		return []
	var unit = get_unit(unit_id)
	if unit.get("flags", {}).get("has_shot", false):
		return []
	return ActionsManager.get_startable_actions(unit_id, GameState.create_snapshot(), get_current_player(), GameState.get_battle_round())

func _validate_start_action(action: Dictionary) -> Dictionary:
	if GameConstants.edition < 11:
		return {"valid": false, "errors": ["Actions are an 11e system"]}
	var unit_id = action.get("actor_unit_id", "")
	var action_id = action.get("payload", {}).get("action_id", "")
	if unit_id == "" or action_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id or action_id"]}
	var unit = get_unit(unit_id)
	if unit.get("owner", 0) != get_current_player():
		return {"valid": false, "errors": ["Unit does not belong to active player"]}
	if unit.get("flags", {}).get("has_shot", false) or _attached_group_has_shot(unit_id):
		return {"valid": false, "errors": ["Unit has already shot or acted this phase"]}
	var board = GameState.create_snapshot()
	for s in ActionsManager.get_startable_actions(unit_id, board, get_current_player(), GameState.get_battle_round()):
		if s.get("id", "") == action_id:
			return {"valid": true, "errors": []}
	var elig = ActionsManager.can_start_action(unit_id, board)
	return {"valid": false, "errors": elig.reasons if not elig.eligible else ["Action '%s' is not available to this unit" % action_id]}

func _process_start_action(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var action_id = action.get("payload", {}).get("action_id", "")
	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var player = get_current_player()
	var turn = GameState.get_battle_round()
	var board = GameState.create_snapshot()
	var res = ActionsManager.start_action(unit_id, action_id, board, player, turn)
	if not res.get("success", false):
		return create_result(false, [], "Cannot start action: " + ", ".join(res.get("errors", [])))
	var changes: Array = res.get("changes", []).duplicate()
	# Mission-card actions flip their card's scoring to the action path for
	# this turn (started = authoritative, even if the action later fails).
	if action_id.begins_with("mission_") and MissionManager.has_method("on_mission_action_started_11e"):
		MissionManager.on_mission_action_started_11e(action_id, unit_id, player)
	var action_name = ActionsManager.get_action(action_id).get("name", action_id)
	# Codex: Adeptus Custodes CONSERVAI ka'tah (CustodesKatah.gd): starting an
	# action does not prevent the unit from being eligible to shoot.
	if _cus11e_katah().conservai_active(unit):
		log_phase_message("%s started action '%s' (CONSERVAI: the unit can still shoot this phase; cannot charge; completes end of turn)" % [unit_name, action_name])
		changes.append_array(_mirror_action_to_attached_group(unit_id, changes))
		return create_result(true, changes)
	# 16.01: starting an action in the Shooting phase gives up shooting.
	units_that_shot.append(unit_id)
	changes.append({"op": "set", "path": "units.%s.flags.has_shot" % unit_id, "value": true})
	if active_shooter_id == unit_id:
		active_shooter_id = ""
		pending_assignments.clear()
		confirmed_assignments.clear()
	# 19.01: an Attached unit is one unit — its attached CHARACTER(s) /
	# bodyguard gave up shooting with it.
	changes.append_array(_mirror_action_to_attached_group(unit_id, changes))
	log_phase_message("%s started action '%s' (16.01: gives up shooting, cannot charge; completes end of turn)" % [unit_name, action_name])
	return create_result(true, changes)

func _get_secondary_action_options(unit_id: String) -> Array:
	"""Get available secondary action options for a unit based on its position.
	Returns array of dicts: [{action_name, location, description, mission_id}]"""
	var player = get_current_player()
	var options = []

	var action_missions = SecondaryMissionManager.get_action_missions_for_player(player)
	if action_missions.is_empty():
		DebugLogger.info(str("ShootingPhase: _get_secondary_action_options - no action missions for player %d" % player))
		return options
	DebugLogger.info(str("ShootingPhase: _get_secondary_action_options - %d action missions for player %d" % [action_missions.size(), player]))

	var unit = get_unit(unit_id)
	if unit.is_empty():
		DebugLogger.info(str("ShootingPhase: _get_secondary_action_options - unit %s is empty" % unit_id))
		return options

	var opponent = 2 if player == 1 else 1
	var opponent_zone = SecondaryMissionManager._get_deployment_zone_polygon(opponent)
	var board_width = GameState.state.get("board", {}).get("size", {}).get("width", 44)
	var board_height = GameState.state.get("board", {}).get("size", {}).get("height", 60)
	var center_px = Vector2(
		Measurement.inches_to_px(board_width / 2.0),
		Measurement.inches_to_px(board_height / 2.0)
	)

	for mission in action_missions:
		var mission_id = mission.get("id", "")
		var action_info = mission.get("action", {})
		var action_name = action_info.get("name", "")

		match mission_id:
			"establish_locus":
				# Check if unit is in opponent zone (5 VP) or within 6" of center (3 VP)
				var in_opp_zone = not opponent_zone.is_empty() and SecondaryMissionManager._is_unit_wholly_in_zone(unit, opponent_zone)
				var near_center = SecondaryMissionManager._has_model_within_range(unit, center_px, Measurement.inches_to_px(6.0))

				if in_opp_zone:
					options.append({
						"action_name": action_name,
						"location": "opponent_zone",
						"description": "Establish Locus in opponent zone (5 VP)",
						"mission_id": mission_id,
						"vp_value": 5
					})
				elif near_center:
					options.append({
						"action_name": action_name,
						"location": "center",
						"description": "Establish Locus near center (3 VP)",
						"mission_id": mission_id,
						"vp_value": 3
					})

			"deploy_teleport_homer":
				var in_opp_zone = not opponent_zone.is_empty() and SecondaryMissionManager._is_unit_wholly_in_zone(unit, opponent_zone)

				if in_opp_zone:
					options.append({
						"action_name": action_name,
						"location": "opponent_zone",
						"description": "Deploy Homer in opponent zone (5 VP)",
						"mission_id": mission_id,
						"vp_value": 5
					})
				else:
					# Can deploy homer anywhere (3 VP)
					options.append({
						"action_name": action_name,
						"location": "other",
						"description": "Deploy Teleport Homer (3 VP)",
						"mission_id": mission_id,
						"vp_value": 3
					})

			"cleanse":
				# Check if unit has a model within objective control range (3" + 20mm marker base)
				# 11e: only NON-HOME objectives can be cleansed; prefer one not
				# already cleansed this turn (each Cleanse targets one objective).
				var objectives = GameState.state.get("board", {}).get("objectives", [])
				var control_radius = Measurement.inches_to_px(3.78740157)
				DebugLogger.info(str("ShootingPhase: Cleanse check - %d objectives, control_radius=%.1fpx, unit=%s" % [objectives.size(), control_radius, unit_id]))
				var found_cleanse = false
				for obj in objectives:
					var obj_pos = obj.get("position", Vector2.ZERO)
					if obj_pos == Vector2.ZERO:
						DebugLogger.info("ShootingPhase: Cleanse - skipping objective with zero position")
						continue
					var obj_id = obj.get("id", "unknown")
					if GameConstants.edition >= 11 and _is_home_objective(obj):
						DebugLogger.info(str("ShootingPhase: Cleanse - %s is a home objective (11e: non-home only)" % obj_id))
						continue
					if _objective_cleansed_this_turn(player, str(obj_id)):
						DebugLogger.info(str("ShootingPhase: Cleanse - %s already cleansed this turn" % obj_id))
						continue
					var in_range = SecondaryMissionManager._unit_in_objective_range(unit, obj)
					DebugLogger.info(str("ShootingPhase: Cleanse - obj %s at %s, in_range=%s" % [obj_id, obj_pos, in_range]))
					if in_range:
						var obj_label = _friendly_objective_name(obj_id)
						options.append({
							"action_name": action_name,
							"location": "objective",
							"description": "Cleanse %s (2-5 VP)" % obj_label,
							"mission_id": mission_id,
							"vp_value": 2,
							"objective_id": obj_id
						})
						found_cleanse = true
						break  # One cleanse per unit
				if not found_cleanse:
					DebugLogger.info(str("ShootingPhase: Cleanse - no objective in range for unit %s" % unit_id))

			"plunder":
				# 11e Plunder: one unit within a terrain area outside your
				# territory; once per turn; flat 5 VP at end of your turn.
				if _plunder_done_this_turn(player):
					DebugLogger.info("ShootingPhase: Plunder - already performed this turn (once per turn)")
					continue
				var terrain = _get_plunder_terrain_for_unit(unit_id, player)
				if terrain.is_empty():
					DebugLogger.info(str("ShootingPhase: Plunder - %s is not within an eligible terrain area" % unit_id))
					continue
				var terrain_label = str(terrain.get("id", "terrain")).replace("_", " ").capitalize()
				options.append({
					"action_name": action_name,
					"location": "terrain",
					"description": "Plunder %s (5 VP)" % terrain_label,
					"mission_id": mission_id,
					"vp_value": 5,
					"terrain_id": terrain.get("id", "")
				})

	return options

static func _friendly_objective_name(obj_id: String) -> String:
	match obj_id:
		"obj_center": return "Centre"
		_:
			if obj_id.begins_with("obj_nml_"):
				return "No Man's Land %s" % obj_id.trim_prefix("obj_nml_")
			elif obj_id.begins_with("obj_home_"):
				return "Home %s" % obj_id.trim_prefix("obj_home_")
			return obj_id.replace("obj_", "").replace("_", " ").capitalize()

func _process_end_shooting(action: Dictionary) -> Dictionary:
	var changes = []
	if active_shooter_id != "":
		_targets_hit_by_shooter.clear()
		active_shooter_id = ""
	log_phase_message("Ending Shooting Phase")
	emit_signal("phase_completed")
	return create_result(true, changes)

func _process_shoot(action: Dictionary) -> Dictionary:
	# Full atomic shoot action - used exclusively by AI
	# Handles the complete flow: select shooter, assign targets, resolve hits/wounds,
	# auto-roll saves, apply damage, mark unit done, and clear state.
	# Does NOT emit UI signals (weapon_order_required, next_weapon_confirmation_required,
	# saves_required) to avoid creating orphaned dialogs during AI play.
	var unit_id = action.get("actor_unit_id", "")
	# Issue #329: extract action.payload.rng_seed once for all sub-rolls in this method
	var ps_seed: int = action.get("payload", {}).get("rng_seed", -1)

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info(str("║ AI SHOOT (atomic): Starting for unit %s" % unit_id))
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	# Step 1: Select shooter (skip Throat Slittas prompt for AI — handle automatically)
	var select_result = _process_select_shooter({"actor_unit_id": unit_id, "payload": {"skip_throat_slittas_check": true, "_sts_atomic_action": action}})
	if not select_result.success:
		return select_result
	# unit_selected_to_shoot window waiting for a HUMAN decider (e.g. "Shoot
	# All Remaining"): stop here — the resume re-enters _process_shoot(action).
	if select_result.get("stratagem_window_pending", false):
		return select_result

	# P1-12: AI auto-resolve Throat Slittas if applicable
	# The AI always uses Throat Slittas when enemies are within 9"
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr and ability_mgr.has_throat_slittas_ability(unit_id):
		var ts_targets = _get_throat_slittas_targets(unit_id)
		if not ts_targets.is_empty():
			DebugLogger.info(str("║ AI SHOOT: P1-12 Throat Slittas — auto-activating for %s" % unit_id))
			var ts_result = _resolve_throat_slittas(unit_id)
			var ts_changes = ts_result.get("diffs", [])
			ts_changes.append({
				"op": "set",
				"path": "units.%s.flags.has_shot" % unit_id,
				"value": true
			})
			units_that_shot.append(unit_id)
			active_shooter_id = ""
			confirmed_assignments.clear()
			resolution_state.clear()
			pending_save_data.clear()

			var ai_unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)
			return create_result(true, ts_changes, "Throat Slittas resolved", {
				"throat_slittas": true,
				"mortal_wounds": ts_result.get("total_mortal_wounds", 0),
				"casualties": ts_result.get("total_casualties", 0)
			})

	# Step 2: Merge assignments into confirmed_assignments (inline, no signals)
	var assignments = action.get("payload", {}).get("assignments", [])
	var merged_assignments = {}
	for assignment in assignments:
		var weapon_id = assignment.get("weapon_id", "")
		var target_unit_id = assignment.get("target_unit_id", "")
		var key = weapon_id + "_" + target_unit_id
		if merged_assignments.has(key):
			var existing = merged_assignments[key]
			var existing_model_ids = existing.get("model_ids", [])
			var new_model_ids = assignment.get("model_ids", [])
			for model_id in new_model_ids:
				if model_id not in existing_model_ids:
					existing_model_ids.append(model_id)
			existing["model_ids"] = existing_model_ids
		else:
			merged_assignments[key] = assignment.duplicate(true)

	confirmed_assignments = []
	for key in merged_assignments:
		confirmed_assignments.append(merged_assignments[key])
	pending_assignments.clear()

	log_phase_message("AI: Confirmed %d weapon assignments for %s" % [confirmed_assignments.size(), unit_id])
	# Codex: Orks (11e) Madcap Meks — Unpredictable Genius (WP-O34): the atomic SHOOT
	# (AI / Shoot All Remaining) rolls it here and picks a Hop Splat victim itself.
	var ork11e_ug_ai: Dictionary = Ork11eDetachments.ug_on_targets_confirmed(unit_id, confirmed_assignments, ps_seed, true)

	# DEFENDER CONTROL: a HUMAN defender gets their reactive stratagem window
	# (Go to Ground / Smokescreen / faction reactives) when the AI declares
	# targets — mirroring the human-attacker CONFIRM_TARGETS flow. The AI's
	# resolution resumes from USE/DECLINE_REACTIVE_STRATAGEM via the
	# `ai_atomic` marker in resolution_state.
	var ai_reactive_check = _check_reactive_stratagems()
	if ai_reactive_check.get("has_opportunities", false) and _is_player_human(ai_reactive_check.defending_player):
		awaiting_reactive_stratagem = true
		resolution_state = {
			"phase": "awaiting_reactive_stratagem",
			"ai_atomic": true,
			"ai_action": action,
			"assignments": confirmed_assignments
		}
		log_phase_message("AI attack declared — opponent may use reactive stratagems...")
		emit_signal("reactive_stratagem_opportunity",
			ai_reactive_check.defending_player,
			ai_reactive_check.available_stratagems,
			ai_reactive_check.target_unit_ids)
		return create_result(true, ork11e_ug_ai.diffs, "Awaiting defender stratagem decision", {
			"reactive_stratagem_opportunity": true,
			"defending_player": ai_reactive_check.defending_player,
			"available_stratagems": ai_reactive_check.available_stratagems,
			"target_unit_ids": ai_reactive_check.target_unit_ids
		})

	return _ork11e_merge_front(ork11e_ug_ai.diffs, _resolve_ai_shoot(action))

# True when `player` is controlled by a human (no AI enabled, or the AI does
# not own that player). Defender windows only pause for humans.
func _is_player_human(player: int) -> bool:
	var ai_node = get_node_or_null("/root/AIPlayer")
	if ai_node == null or not ai_node.enabled:
		return true
	return not ai_node.is_ai_player(player)

# The owner of the first resolvable target in a save_data batch — in a
# two-player game every target of one attack belongs to the same defender.
func _defending_player_for_save_data(save_data_list: Array) -> int:
	for sd in save_data_list:
		var t = get_unit(str(sd.get("target_unit_id", "")))
		if not t.is_empty():
			return t.get("owner", 0)
	return 0

# Steps 3+ of the AI atomic SHOOT — split out so the reactive-stratagem
# window can pause before it and resume into it.
func _resolve_ai_shoot(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var ps_seed: int = action.get("payload", {}).get("rng_seed", -1)

	# Step 3: Resolve shooting (hits + wounds) via RulesEngine
	# Issue #329: forward action.payload.rng_seed to RulesEngine
	var shoot_action = {
		"type": "SHOOT",
		"actor_unit_id": active_shooter_id,
		"payload": {
			"assignments": confirmed_assignments,
			"rng_seed": ps_seed,
			# 10.02/10.07: the SELECTED shooting type drives per-attack consequences
			"shooting_type": active_shooting_type
		}
	}

	var rng_service = RulesEngine.RNGService.new(ps_seed)
	var result = RulesEngine.resolve_shoot_until_wounds(shoot_action, game_state_snapshot, rng_service)

	if not result.success:
		# Resolution failed - clean up and return
		active_shooter_id = ""
		confirmed_assignments.clear()
		return create_result(false, [], result.get("log_text", "Shooting failed"))

	# Record dice rolls
	var all_dice = []
	var dice_data = result.get("dice", [])
	for dice_block in dice_data:
		dice_log.append(dice_block)
		all_dice.append(dice_block)

	log_phase_message(result.get("log_text", "Attack rolls complete"))

	# Step 4: Resolve saves.
	# DEFENDER CONTROL: when the defender is a HUMAN, they roll their own
	# saves (and pick their own casualties) through the interactive overlay
	# — the AI pauses here and resumes on APPLY_SAVES. Auto-roll only for AI
	# defenders or when the player opted into computer allocation.
	var save_data_list = result.get("save_data_list", [])
	var all_changes = []
	var total_casualties = 0

	if not save_data_list.is_empty() and _should_pause_for_human_saves(save_data_list):
		return _begin_ai_interactive_saves(unit_id, ps_seed, result, all_dice)

	if not save_data_list.is_empty():
		var save_result = _auto_roll_saves(save_data_list)
		all_changes.append_array(save_result.get("changes", []))
		total_casualties = save_result.get("casualties", 0)
		all_dice.append_array(save_result.get("dice_blocks", []))

		DebugLogger.info(str("║ AI SHOOT: Saves resolved - %d casualties" % total_casualties))
	else:
		DebugLogger.info("║ AI SHOOT: No wounds caused (all missed)")

	return _finalize_ai_shoot(unit_id, ps_seed, all_changes, all_dice, total_casualties,
		save_data_list, result.get("hazardous_weapons", []), result.get("one_shot_diffs", []))

# Steps 5-8 of the AI atomic SHOOT: hazardous checks, one-shot ammo, attack
# summary, has_shot flags, per-target phase-summary entries and state
# cleanup. Called by the auto-resolve path directly and by the interactive
# defender-saves path once the last APPLY_SAVES lands.
func _finalize_ai_shoot(unit_id: String, ps_seed: int, all_changes: Array, all_dice: Array, total_casualties: int, save_data_list: Array, hazardous_weapons: Array, one_shot_diffs: Array, skip_damage_signal: bool = false) -> Dictionary:
	var ai_hazard_lines: Array = []  # LV2-G1: Game Log text of each hazard roll
	# HAZARDOUS (T2-3): Process Hazardous self-damage after saves resolve (AI path)
	if not hazardous_weapons.is_empty():
		DebugLogger.info(str("║ AI SHOOT: Processing %d hazardous weapon check(s)" % hazardous_weapons.size()))
		var haz_rng = RulesEngine.RNGService.new(ps_seed)  # Issue #329: forward seed
		for haz_weapon in hazardous_weapons:
			var haz_result = RulesEngine.resolve_hazardous_check(
				active_shooter_id,
				haz_weapon.get("weapon_id", ""),
				haz_weapon.get("models_that_fired", 0),
				game_state_snapshot,
				haz_rng
			)
			if haz_result.hazardous_triggered:
				all_changes.append_array(haz_result.diffs)
			all_dice.append_array(haz_result.dice)
			if haz_result.log_text:
				log_phase_message(haz_result.log_text)
			# LV2-G1: the attack summary below is this SHOOT's Game Log line —
			# carry the hazard roll in it (it was only in the debug log).
			if str(haz_result.get("game_log_text", "")) != "":
				ai_hazard_lines.append(str(haz_result.get("game_log_text", "")))

	# ONE SHOT (T4-2): Include one-shot diffs in AI path
	var ai_one_shot_diffs = one_shot_diffs
	if not ai_one_shot_diffs.is_empty():
		all_changes.append_array(ai_one_shot_diffs)
		DebugLogger.info(str("║ AI SHOOT: ONE SHOT — included %d one-shot diffs" % ai_one_shot_diffs.size()))

	# Step 5: Build comprehensive attack summary for game event log
	var actor_name = game_state_snapshot.get("units", {}).get(unit_id, {}).get("meta", {}).get("name", unit_id)
	var target_names = []
	for a in confirmed_assignments:
		var tid = a.get("target_unit_id", "")
		var tn = game_state_snapshot.get("units", {}).get(tid, {}).get("meta", {}).get("name", tid)
		if tn not in target_names:
			target_names.append(tn)

	var total_hits = 0
	var total_wounds = 0
	var total_saves_passed = 0
	var total_saves_failed = 0
	var grot_shield_msgs: Array = []
	for db in all_dice:
		var ctx = db.get("context", "")
		if ctx == "to_hit" or ctx == "hit_roll" or ctx == "auto_hit":
			total_hits += db.get("successes", 0)
		elif ctx == "to_wound":
			total_wounds += db.get("successes", 0)
		elif ctx == "save_roll":
			total_saves_passed += db.get("successes", 0)
			total_saves_failed += db.get("failed", 0)
		elif ctx == "grot_shields" and str(db.get("message", "")) != "":
			grot_shield_msgs.append(str(db.get("message", "")))

	var target_text = ", ".join(target_names)
	var attack_summary = "%s → %s: %d hits, %d wounds" % [actor_name, target_text, total_hits, total_wounds]
	if total_saves_passed > 0 or total_saves_failed > 0:
		attack_summary += ", %d saved, %d failed" % [total_saves_passed, total_saves_failed]
	if total_casualties > 0:
		attack_summary += " → %d slain" % total_casualties
	# GROT SHIELDS interceptions explain where those hits went (r3:F6).
	if not grot_shield_msgs.is_empty():
		attack_summary += " [%s]" % "; ".join(grot_shield_msgs)
	# LV2-G1: the shooter's own [HAZARDOUS] rolls (native or granted).
	if not ai_hazard_lines.is_empty():
		attack_summary += " [%s]" % "; ".join(ai_hazard_lines)

	# T7-38: Emit AI shooting visual signals BEFORE clearing state
	# Collect unique targets with weapon names for targeting line visualization
	var ai_target_data = []
	var seen_targets = {}
	for a in confirmed_assignments:
		var tid = a.get("target_unit_id", "")
		if tid.is_empty() or seen_targets.has(tid):
			continue
		seen_targets[tid] = true
		var weapon_names_for_target = []
		for a2 in confirmed_assignments:
			if a2.get("target_unit_id", "") == tid:
				var wid = a2.get("weapon_id", "")
				var wp = RulesEngine.get_weapon_profile(wid)
				var wn = wp.get("name", wid)
				if wn not in weapon_names_for_target:
					weapon_names_for_target.append(wn)
		ai_target_data.append({
			"target_unit_id": tid,
			"weapon_names": weapon_names_for_target
		})

	emit_signal("ai_shooting_visual", unit_id, ai_target_data, {
		"hits": total_hits,
		"wounds": total_wounds,
		"saves_passed": total_saves_passed,
		"saves_failed": total_saves_failed,
		"casualties": total_casualties
	})
	DebugLogger.info(str("║ T7-38: Emitted ai_shooting_visual for %d target(s)" % ai_target_data.size()))

	# T7-38: Emit shooting_damage_applied for floating damage numbers (AI path).
	# The interactive defender-saves path already emitted per batch — skip.
	if not skip_damage_signal:
		var damage_diffs = []
		for change in all_changes:
			if change.get("op") == "set":
				var path: String = change.get("path", "")
				if ".models." in path and (path.ends_with(".alive") or path.ends_with(".current_wounds")):
					damage_diffs.append(change)
		if not damage_diffs.is_empty():
			emit_signal("shooting_damage_applied", unit_id, damage_diffs)
			DebugLogger.info(str("║ T7-38: Emitted shooting_damage_applied with %d diffs" % damage_diffs.size()))

	# P1-11: Track hits for Sanctified Flames (AI atomic path)
	# Build _targets_hit_by_shooter from the dice + assignment data
	_targets_hit_by_shooter.clear()
	if total_hits > 0:
		# Assign hits to target units from assignments
		for a in confirmed_assignments:
			var ai_tid = a.get("target_unit_id", "")
			if ai_tid != "":
				# Use total_hits as a proxy — hits are distributed across targets
				# For accuracy, we just need to know which units were hit at all
				_targets_hit_by_shooter[ai_tid] = _targets_hit_by_shooter.get(ai_tid, 0) + 1

	# Step 6: Mark unit as done
	all_changes.append({
		"op": "set",
		"path": "units.%s.flags.has_shot" % unit_id,
		"value": true
	})
	all_changes.append(_hidden_shot_stamp(unit_id))
	units_that_shot.append(unit_id)

	# T5-UX9: Record per-target shot summary for end-of-phase panel.
	# AI atomic path doesn't populate completed_weapons, so build entries from
	# confirmed_assignments + save_data_list + per-target casualties from all_changes.
	var ai_actor_name = game_state_snapshot.get("units", {}).get(unit_id, {}).get("meta", {}).get("name", unit_id)
	var per_target_casualties: Dictionary = {}
	for ch in all_changes:
		var cpath = ch.get("path", "")
		if cpath.ends_with(".alive") and ch.get("value") == false:
			var cparts = cpath.split(".")
			if cparts.size() >= 2 and cparts[0] == "units":
				var dead_uid = cparts[1]
				per_target_casualties[dead_uid] = per_target_casualties.get(dead_uid, 0) + 1
	# Sum hits/wounds/saves_failed per target by scanning save_data_list and all_dice
	# (save_data_list groups data per weapon → target)
	var per_target_aggregate: Dictionary = {}
	for sd in save_data_list:
		var sd_tid = sd.get("target_unit_id", "")
		if sd_tid == "":
			continue
		if not per_target_aggregate.has(sd_tid):
			per_target_aggregate[sd_tid] = {
				"target_unit_name": sd.get("target_unit_name", sd_tid),
				"weapons": [],
				"wounds": 0,
				"saves_failed": 0
			}
		per_target_aggregate[sd_tid].weapons.append(sd.get("weapon_id", ""))
		per_target_aggregate[sd_tid].wounds += int(sd.get("wounds_to_save", 0))
	# Pull saves_failed from save dice blocks per target
	for db in all_dice:
		if db.get("context", "") == "save_roll":
			var db_tname = db.get("target_unit_name", "")
			for tid_key in per_target_aggregate:
				if per_target_aggregate[tid_key].target_unit_name == db_tname:
					per_target_aggregate[tid_key].saves_failed += int(db.get("failed", 0))
					break
	# Also include targets that got assigned but had 0 wounds caused
	for a in confirmed_assignments:
		var a_tid = a.get("target_unit_id", "")
		if a_tid == "" or per_target_aggregate.has(a_tid):
			continue
		var a_target = game_state_snapshot.get("units", {}).get(a_tid, {})
		var a_target_name = a_target.get("meta", {}).get("name", a_tid)
		per_target_aggregate[a_tid] = {
			"target_unit_name": a_target_name,
			"weapons": [a.get("weapon_id", "")],
			"wounds": 0,
			"saves_failed": 0
		}

	# Approximate hits-per-target: split total_hits proportionally by wounds-per-target.
	# When total wounds > 0, share by wound ratio; else share evenly across targets.
	var ai_total_wounds = 0
	for tid_key2 in per_target_aggregate:
		ai_total_wounds += per_target_aggregate[tid_key2].wounds
	for tid_key3 in per_target_aggregate:
		var bucket = per_target_aggregate[tid_key3]
		var hits_share = 0
		if ai_total_wounds > 0:
			hits_share = int(round(float(total_hits) * float(bucket.wounds) / float(ai_total_wounds)))
		elif per_target_aggregate.size() > 0:
			hits_share = int(total_hits / per_target_aggregate.size())
		_append_phase_shooting_entry({
			"shooter_unit_id": unit_id,
			"shooter_unit_name": ai_actor_name,
			"weapon_id": str(bucket.weapons[0]) if not bucket.weapons.is_empty() else "",
			"weapon_name": "",  # AI atomic aggregates across weapons; weapon-level breakdown not available
			"target_unit_id": tid_key3,
			"target_unit_name": bucket.target_unit_name,
			"hits": hits_share,
			"total_attacks": 0,
			"wounds": bucket.wounds,
			"saves_failed": bucket.saves_failed,
			"casualties": int(per_target_casualties.get(tid_key3, 0)),
			"skipped_target_destroyed": false
		})

	# Step 7: Clear state
	var shooter_id = active_shooter_id
	# Return shooter to idle animation
	_trigger_unit_animation(active_shooter_id, "idle")
	active_shooter_id = ""
	confirmed_assignments.clear()
	resolution_state.clear()
	pending_save_data.clear()
	_targets_hit_by_shooter.clear()

	# Step 8: Emit shooting_resolved for visual cleanup (non-blocking)
	emit_signal("shooting_resolved", shooter_id, "", {"casualties": total_casualties})

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info(str("║ AI SHOOT (atomic): Complete for %s - %d casualties" % [unit_id, total_casualties]))
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	return create_result(true, all_changes, "", {
		"dice": all_dice,
		"casualties": total_casualties,
		"log_text": attack_summary
	})

# DEFENDER CONTROL: the AI attacker pauses for a human defender to roll
# their own saves when the defender is human, the game runs the 11e
# allocation flow, and the player has not delegated allocation to the
# computer (auto_allocate_wounds setting).
func _should_pause_for_human_saves(save_data_list: Array) -> bool:
	if GameConstants.edition < 11:
		return false
	if not _is_player_human(_defending_player_for_save_data(save_data_list)):
		return false
	# (null SettingsService only happens in stripped headless harnesses — treat
	# it as auto-allocate so engine-level tests keep one-shot resolution and
	# nothing waits for an APPLY_SAVES that no overlay will ever send. Same
	# fallback, for the same reason, as FightPhase._process_roll_dice and
	# FightPhase.fight_activation_will_stage; in a real game the autoload
	# always exists and the player's setting decides.)
	var ss = get_node_or_null("/root/SettingsService")
	var auto_alloc: bool = ss == null or ss.get_auto_allocate_wounds()
	return not auto_alloc

# Store the AI shoot context and hand the first save batch to the defender.
# Each APPLY_SAVES consumes one batch (see _process_apply_saves_ai_atomic);
# the last one runs _finalize_ai_shoot to complete the activation.
func _begin_ai_interactive_saves(unit_id: String, ps_seed: int, result: Dictionary, all_dice: Array) -> Dictionary:
	var all_save_data: Array = result.get("save_data_list", [])
	pending_save_data = all_save_data
	resolution_state = {
		"mode": "ai_atomic",
		"phase": "awaiting_saves",
		"ai_ctx": {
			"unit_id": unit_id,
			"rng_seed": ps_seed,
			"all_dice": all_dice,
			"hazardous_weapons": result.get("hazardous_weapons", []),
			"one_shot_diffs": result.get("one_shot_diffs", []),
			"save_data_list_full": all_save_data.duplicate(true),
			"accumulated_changes": [],
			"total_casualties": 0
		}
	}
	var first = pending_save_data[0]
	# T5-MP4-RELIABILITY: stamp before EVERY saves_required emission — the
	# local is named save_data_list so the reliability pin's literal
	# `_stamp_save_broadcast_id(save_data_list, broadcast_id)` count holds.
	var save_data_list: Array = [first]
	var broadcast_id := _generate_save_broadcast_id()
	_stamp_save_broadcast_id(save_data_list, broadcast_id)
	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info(str("║ AI SHOOT: DEFENDER CONTROL — pausing for human saves (%d batch(es))" % pending_save_data.size()))
	DebugLogger.info(str("║ First batch: %s vs %s (%d wounds)" % [str(first.get("weapon_name", "")), str(first.get("target_unit_name", "")), int(first.get("wounds_to_save", 0))]))
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")
	log_phase_message("AI attack: awaiting defender saves (%s vs %s)..." % [
		str(first.get("weapon_name", "")), str(first.get("target_unit_name", ""))])
	emit_signal("saves_required", save_data_list)
	return create_result(true, [], "Awaiting defender save resolution", {
		"dice": all_dice,
		"save_data_list": save_data_list
	})

# One APPLY_SAVES from the defender while an AI atomic SHOOT is paused:
# apply the batch, then either hand over the next batch or finish the AI
# activation.
func _process_apply_saves_ai_atomic(action: Dictionary) -> Dictionary:
	var payload = action.get("payload", {})
	var save_results_list = payload.get("save_results_list", [])
	if pending_save_data.is_empty():
		return create_result(false, [], "No pending AI save data")
	if save_results_list.is_empty():
		return create_result(false, [], "Missing save_results_list")
	var ctx: Dictionary = resolution_state.get("ai_ctx", {})
	var save_data: Dictionary = pending_save_data[0]
	var summary: Dictionary = save_results_list[0]
	var this_diffs: Array = []
	var this_casualties := 0
	var target_unit_id = str(save_data.get("target_unit_id", summary.get("target_unit_id", "")))

	if summary.get("is_allocation_11e", false):
		this_diffs.append_array(summary.get("diffs", []))
		this_diffs.append_array(_apply_defender_save_command_reroll(summary, save_data))
		this_casualties = int(summary.get("casualties", 0))
		log_phase_message("%s: %d saves passed, %d failed → %d casualties (defender allocated)" % [
			save_data.get("target_unit_name", target_unit_id),
			summary.get("saves_passed", 0), summary.get("saves_failed", 0), this_casualties])
	else:
		# 10e-format summary (per-wound WoundAllocationOverlay)
		var save_results = []
		if summary.has("save_results"):
			save_results = summary.save_results
		elif summary.has("allocation_history"):
			for alloc in summary.allocation_history:
				save_results.append({
					"saved": alloc.get("saved", false),
					"model_id": alloc.get("model_id", ""),
					"model_index": alloc.get("model_index", 0),
					"roll": alloc.get("roll", 0),
					"damage": alloc.get("damage", 0),
					"model_destroyed": alloc.get("model_destroyed", false)
				})
		var fnp_rng = RulesEngine.RNGService.new(int(ctx.get("rng_seed", -1)))
		var damage_result = RulesEngine.apply_save_damage(save_results, save_data, game_state_snapshot, -1, fnp_rng)
		this_diffs.append_array(damage_result.diffs)
		this_casualties = damage_result.casualties

	if this_casualties > 0 and target_unit_id != "":
		CharacterAttachmentManager.check_bodyguard_destroyed(target_unit_id)

	# Record the defender's save/FNP dice in the dice history. Normalized first
	# so an AI attack's saves render as a "Save (N+)" row on the combat card
	# like a human attack's do — the raw batch blocks use the engine-internal
	# "save" context that the log renderers do not match.
	for dice_block in RulesEngine.normalize_allocation_11e_dice(summary, {
		"target_unit_name": save_data.get("target_unit_name", target_unit_id),
		"weapon_name": save_data.get("weapon_name", ""),
	}):
		dice_log.append(dice_block)
		emit_signal("dice_rolled", dice_block)

	# T7-53: floating damage numbers over the defender's unit
	if not this_diffs.is_empty():
		emit_signal("shooting_damage_applied", active_shooter_id, this_diffs)

	pending_save_data.pop_front()
	ctx["accumulated_changes"] = ctx.get("accumulated_changes", []) + this_diffs
	ctx["total_casualties"] = int(ctx.get("total_casualties", 0)) + this_casualties
	resolution_state["ai_ctx"] = ctx

	if not pending_save_data.is_empty():
		var next: Dictionary = pending_save_data[0]
		# T5-MP4-RELIABILITY: stamp before every saves_required emission
		# (local named save_data_list for the reliability pin's literal count).
		var save_data_list: Array = [next]
		var broadcast_id := _generate_save_broadcast_id()
		_stamp_save_broadcast_id(save_data_list, broadcast_id)
		log_phase_message("AI attack: awaiting defender saves (%s vs %s)..." % [
			str(next.get("weapon_name", "")), str(next.get("target_unit_name", ""))])
		# Deferred: the previous overlay's allocation_complete callback is
		# still on the stack — an immediate emission would be swallowed by
		# ShootingController's duplicate-signal guard.
		call_deferred("emit_signal", "saves_required", save_data_list)
		return create_result(true, this_diffs, "Awaiting defender save resolution (next batch)", {
			"save_data_list": save_data_list
		})

	# All batches resolved — finish the AI activation. Pass the FULL
	# accumulated save diffs (idempotent set-ops; earlier batches are
	# already applied) so the per-target phase summary counts every batch,
	# and skip the damage signal (each batch already emitted its own).
	return _finalize_ai_shoot(
		str(ctx.get("unit_id", active_shooter_id)),
		int(ctx.get("rng_seed", -1)),
		ctx.get("accumulated_changes", []).duplicate(),
		ctx.get("all_dice", []),
		int(ctx.get("total_casualties", 0)),
		ctx.get("save_data_list_full", []),
		ctx.get("hazardous_weapons", []),
		ctx.get("one_shot_diffs", []),
		true)

func _auto_roll_saves(save_data_list: Array) -> Dictionary:
	# Auto-roll saves for AI - no UI interaction needed
	# Returns: {changes: [], casualties: int, dice_blocks: []}
	# 11e (05.03-05.04): the computer allocates for the defender through the
	# SAME grouped allocation engine the interactive AllocationGroupOverlay
	# uses — never the legacy per-wound round-robin below, which spread failed
	# saves across models (two failed D1 saves on two W2 models killed nobody).
	if GameConstants.edition >= 11:
		return _auto_roll_saves_11e(save_data_list)
	var all_changes = []
	var total_casualties = 0
	var all_dice_blocks = []
	# Track which units have been destroyed by previous weapon saves in this batch
	var _destroyed_units_in_batch: Dictionary = {}

	for save_data in save_data_list:
		# Skip saves for targets already destroyed by earlier weapons in this batch
		var target_unit_id = save_data.get("target_unit_id", "")
		if _destroyed_units_in_batch.has(target_unit_id):
			var target_name = save_data.get("target_unit_name", target_unit_id)
			var weapon_name = save_data.get("weapon_name", "Unknown")
			DebugLogger.info(str("ShootingPhase: AI SKIP — %s saves skipped, target %s already destroyed" % [weapon_name, target_name]))
			log_phase_message("Skipped %s — target %s destroyed" % [weapon_name, target_name])
			continue

		var wounds_to_save = save_data.get("wounds_to_save", 0)
		var model_save_profiles = save_data.get("model_save_profiles", [])

		if wounds_to_save <= 0 and save_data.get("devastating_wounds", 0) <= 0:
			continue

		# Roll saves: allocate wounds to models in priority order (wounded first)
		var rng = RulesEngine.make_rng()
		var save_results = []
		var saves_passed = 0
		var saves_failed = 0
		var save_rolls_raw = []

		# Build allocation order: wounded models first, then by model_index
		var allocation_order = []
		# PRECISION (T3-4): Separate character and non-character models
		var character_profiles = []
		var bodyguard_profiles = []
		for profile in model_save_profiles:
			if profile.get("is_character", false):
				character_profiles.append(profile)
			else:
				bodyguard_profiles.append(profile)
			allocation_order.append(profile)

		# Sort: wounded models first (is_wounded = true first)
		allocation_order.sort_custom(func(a, b):
			if a.get("is_wounded", false) and not b.get("is_wounded", false):
				return true
			if not a.get("is_wounded", false) and b.get("is_wounded", false):
				return false
			return a.get("model_index", 0) < b.get("model_index", 0)
		)

		# Defender die-first preference: when the computer allocates for this
		# defender (AI player, or the 'Computer allocates wounds' setting),
		# rank un-wounded models by the same CasualtyPreference order the 11e
		# overlay auto mode uses instead of raw model_index — this was the
		# one auto path still removing lowest-index bases. Wounded-first
		# (05.04) still wins; allocation order is the defender's choice.
		var target_unit_for_pref = game_state_snapshot.get("units", {}).get(target_unit_id, {})
		if not target_unit_for_pref.is_empty():
			var pref = CasualtyPreference.engine_auto_preference(target_unit_for_pref, game_state_snapshot)
			if not pref.is_empty():
				var pref_rank = {}
				for r in range(pref.size()):
					pref_rank[int(pref[r])] = r
				var pref_cmp = func(a, b):
					var aw = a.get("is_wounded", false)
					var bw = b.get("is_wounded", false)
					if aw != bw:
						return aw
					var ra = pref_rank.get(int(a.get("model_index", 0)), 99999)
					var rb = pref_rank.get(int(b.get("model_index", 0)), 99999)
					if ra != rb:
						return ra < rb
					return a.get("model_index", 0) < b.get("model_index", 0)
				allocation_order.sort_custom(pref_cmp)
				bodyguard_profiles.sort_custom(pref_cmp)

		# PRECISION (T3-4): Check if weapon has Precision and there are character models
		var has_precision = save_data.get("has_precision", false)
		var precision_wounds = save_data.get("precision_wounds", 0)
		var precision_wounds_remaining = precision_wounds if has_precision else 0
		var bodyguard_alive = not bodyguard_profiles.is_empty()

		if has_precision and precision_wounds > 0 and not character_profiles.is_empty():
			DebugLogger.info(str("ShootingPhase: PRECISION — %d wounds can target CHARACTER models" % precision_wounds))

		# Roll all saves at once, then allocate to models in priority order
		var all_rolls = rng.roll_d6(wounds_to_save)
		var alloc_idx = 0
		# PRECISION (T3-4): Track character allocation index separately
		var char_alloc_idx = 0
		for w in range(wounds_to_save):
			# PRECISION (T3-4): Allocate precision wounds to CHARACTER models first
			var use_character_target = false
			if precision_wounds_remaining > 0 and not character_profiles.is_empty():
				use_character_target = true
				precision_wounds_remaining -= 1

			var profile: Dictionary
			if use_character_target:
				if char_alloc_idx >= character_profiles.size():
					char_alloc_idx = 0  # Wrap around
				profile = character_profiles[char_alloc_idx]
				char_alloc_idx += 1
			else:
				# Normal allocation: bodyguard models (or all models if no bodyguard)
				var normal_order = bodyguard_profiles if bodyguard_alive else allocation_order
				if normal_order.is_empty():
					break
				if alloc_idx >= normal_order.size():
					alloc_idx = 0  # Wrap around
				profile = normal_order[alloc_idx]
				alloc_idx += 1

			var save_needed = profile.get("save_needed", 7)
			var roll = all_rolls[w]
			save_rolls_raw.append(roll)
			var saved = roll >= save_needed

			save_results.append({
				"saved": saved,
				"model_id": profile.get("model_id", ""),
				"model_index": profile.get("model_index", 0),
				"roll": roll,
				"damage": save_data.get("damage", 1),
				"model_destroyed": false,  # Will be determined by apply_save_damage
				"precision_wound": use_character_target  # PRECISION (T3-4): Track precision wounds
			})

			if saved:
				saves_passed += 1
			else:
				saves_failed += 1

		# Build dice block for save rolls
		if not save_rolls_raw.is_empty():
			var save_threshold = 7
			var using_invuln = false
			if not allocation_order.is_empty():
				save_threshold = allocation_order[0].get("save_needed", 7)
				using_invuln = allocation_order[0].get("using_invuln", false)

			var save_dice_block = {
				"context": "save_roll",
				"threshold": str(save_threshold) + "+",
				"rolls_raw": save_rolls_raw,
				"successes": saves_passed,
				"failed": saves_failed,
				"ap": save_data.get("ap", 0),
				"original_save": save_data.get("base_save", 7),
				"using_invuln": using_invuln,
				"weapon_name": save_data.get("weapon_name", ""),
				"target_unit_name": save_data.get("target_unit_name", "")
			}
			all_dice_blocks.append(save_dice_block)
			dice_log.append(save_dice_block)
			emit_signal("dice_rolled", save_dice_block)

		# Apply damage using RulesEngine
		var fnp_rng = RulesEngine.make_rng()
		var damage_result = RulesEngine.apply_save_damage(
			save_results,
			save_data,
			game_state_snapshot,
			-1,
			fnp_rng
		)

		all_changes.append_array(damage_result.diffs)
		total_casualties += damage_result.casualties

		# Check if bodyguard unit was destroyed
		if damage_result.casualties > 0:
			if target_unit_id != "":
				CharacterAttachmentManager.check_bodyguard_destroyed(target_unit_id)

		# Check if target unit was fully destroyed by this weapon's damage
		# (compute from diffs since game_state_snapshot hasn't been updated yet)
		if damage_result.casualties > 0 and target_unit_id != "":
			var models_killed_count = 0
			for diff in all_changes:
				var dpath = diff.get("path", "")
				if dpath.begins_with("units.%s.models." % target_unit_id) and dpath.ends_with(".alive") and diff.get("value") == false:
					models_killed_count += 1
			var target_unit_data = game_state_snapshot.get("units", {}).get(target_unit_id, {})
			var alive_in_snapshot = 0
			for m in target_unit_data.get("models", []):
				if m.get("alive", true):
					alive_in_snapshot += 1
			if alive_in_snapshot > 0 and models_killed_count >= alive_in_snapshot:
				_destroyed_units_in_batch[target_unit_id] = true
				DebugLogger.info(str("ShootingPhase: AI — target unit %s fully destroyed, will skip remaining saves" % target_unit_id))

		# Log FNP dice blocks
		var fnp_rolls = damage_result.get("fnp_rolls", [])
		for fnp_block in fnp_rolls:
			var fnp_dice_block = {
				"context": "feel_no_pain",
				"threshold": str(fnp_block.get("fnp_value", 0)) + "+",
				"rolls_raw": fnp_block.get("rolls", []),
				"fnp_value": fnp_block.get("fnp_value", 0),
				"wounds_prevented": fnp_block.get("wounds_prevented", 0),
				"wounds_remaining": fnp_block.get("wounds_remaining", 0),
				"total_wounds": fnp_block.get("total_wounds", 0),
				"source": fnp_block.get("source", ""),
				"target_unit_name": save_data.get("target_unit_name", "")
			}
			dice_log.append(fnp_dice_block)
			emit_signal("dice_rolled", fnp_dice_block)
			all_dice_blocks.append(fnp_dice_block)

		var target_name = save_data.get("target_unit_name", "Unknown")
		log_phase_message("AI saves: %s - %d passed, %d failed → %d casualties" % [
			target_name, saves_passed, saves_failed, damage_result.casualties
		])

		# VERBOSE COMBAT LOG: Emit save and FNP detail for this weapon's saves
		_emit_verbose_combat_log(active_shooter_id, [], all_dice_blocks, damage_result.casualties, "shooting_saves")

	return {"changes": all_changes, "casualties": total_casualties, "dice_blocks": all_dice_blocks}

# 11e automatic save resolution for the defender (AI defender, or a human
# who delegated allocation to the computer): one allocation batch per
# save_data via RulesEngine.resolve_allocation_batch_11e — 05.03 groups in a
# legal default order, the batch rolled, damage applied lowest roll first
# onto the current group's wounded model before any other (05.04), devastating
# crits as per-crit mortal wounds, attached characters reached last. The
# casualty choice inside a group uses the same CasualtyPreference ordering as
# the overlay's auto mode. Batches against the same unit see the previous
# batches' damage (a working copy of the board carries it forward).
func _auto_roll_saves_11e(save_data_list: Array) -> Dictionary:
	var all_changes: Array = []
	var total_casualties := 0
	var all_dice_blocks: Array = []
	var work_board: Dictionary = game_state_snapshot.duplicate(true)
	for save_data in save_data_list:
		var target_unit_id := str(save_data.get("target_unit_id", ""))
		var wounds_to_save := int(save_data.get("wounds_to_save", 0))
		var dev_wounds := int(save_data.get("devastating_wounds", 0))
		if wounds_to_save <= 0 and dev_wounds <= 0:
			continue
		var live_target: Dictionary = work_board.get("units", {}).get(target_unit_id, {})
		var any_alive := false
		for m in live_target.get("models", []):
			if m.get("alive", true):
				any_alive = true
				break
		if not any_alive:
			log_phase_message("Skipped %s — target %s destroyed" % [save_data.get("weapon_name", "Unknown"), save_data.get("target_unit_name", target_unit_id)])
			continue

		var virtual_unit: Dictionary = RulesEngine.build_attached_allocation_unit_11e(target_unit_id, work_board).unit
		var defender := int(live_target.get("owner", 0))
		var preferred: Array = CasualtyPreference.compute_preferred_targets(virtual_unit, work_board, {"defender_player": defender})
		# 05.03: the defender also chooses the GROUP order — follow the same
		# preference (the engine's default model-index order could kill a
		# protected Nob's group first and strand the survivors).
		var group_order: Array = CasualtyPreference.group_order_for(Allocation.build_groups(virtual_unit), preferred)
		var batch = RulesEngine.resolve_allocation_batch_11e(save_data, group_order, work_board, RulesEngine.make_rng(), {
			"preferred_targets": preferred,
		})
		var diffs: Array = batch.get("diffs", [])
		all_changes.append_array(diffs)
		_apply_set_diffs_to_board(work_board, diffs)
		var casualties := int(batch.get("casualties", 0))
		total_casualties += casualties
		if casualties > 0 and target_unit_id != "":
			CharacterAttachmentManager.check_bodyguard_destroyed(target_unit_id)

		for blk in RulesEngine.normalize_allocation_11e_dice(batch, {
				"target_unit_name": save_data.get("target_unit_name", ""),
				"weapon_name": save_data.get("weapon_name", "")}):
			if blk.get("context", "") in ["save_roll", "feel_no_pain"]:
				dice_log.append(blk)
				emit_signal("dice_rolled", blk)
			all_dice_blocks.append(blk)

		log_phase_message("AI saves (11e allocation, order %s): %s - %d passed, %d failed → %d casualties" % [
			str(batch.get("order_used", [])), save_data.get("target_unit_name", "Unknown"),
			int(batch.get("saves_passed", 0)), int(batch.get("saves_failed", 0)), casualties])
		_emit_verbose_combat_log(active_shooter_id, [], all_dice_blocks, casualties, "shooting_saves")

	return {"changes": all_changes, "casualties": total_casualties, "dice_blocks": all_dice_blocks}

# Apply `set` diffs on "units.<id>.models.<i>.<field>" paths to a board copy
# (the shape resolve_allocation_batch_11e emits) so later batches in the
# same activation see earlier casualties.
static func _apply_set_diffs_to_board(board: Dictionary, diffs: Array) -> void:
	for diff in diffs:
		if str(diff.get("op", "")) != "set":
			continue
		var parts = str(diff.get("path", "")).split(".")
		if parts.size() != 5 or parts[0] != "units" or parts[2] != "models":
			continue
		var unit = board.get("units", {}).get(parts[1], {})
		var models: Array = unit.get("models", [])
		var mi := int(parts[3])
		if mi >= 0 and mi < models.size():
			models[mi][parts[4]] = diff.get("value")

func _process_resolve_weapon_sequence(action: Dictionary) -> Dictionary:
	"""Process weapon sequence resolution - either fast roll or sequential"""
	DebugLogger.info("========================================")
	DebugLogger.info("ShootingPhase: _process_resolve_weapon_sequence CALLED")
	DebugLogger.info(str("ShootingPhase: action = ", action))

	var payload = action.get("payload", {})
	DebugLogger.info(str("ShootingPhase: payload = ", payload))

	var weapon_order = payload.get("weapon_order", [])
	DebugLogger.info(str("ShootingPhase: weapon_order size = ", weapon_order.size()))

	var fast_roll = payload.get("fast_roll", false)
	DebugLogger.info(str("ShootingPhase: fast_roll = ", fast_roll))

	var is_reorder = payload.get("is_reorder", false)
	DebugLogger.info(str("ShootingPhase: is_reorder = ", is_reorder))

	DebugLogger.info(str("ShootingPhase: active_shooter_id = ", active_shooter_id))
	DebugLogger.info(str("ShootingPhase: confirmed_assignments before = ", confirmed_assignments))

	# If this is a reorder during sequential resolution, update the weapon_order
	if is_reorder and resolution_state.get("mode", "") in ["sequential", "sequential_staged"]:
		DebugLogger.info("ShootingPhase: Updating weapon order for remaining weapons")
		var current_index = resolution_state.get("current_index", 0)
		var existing_order = resolution_state.get("weapon_order", [])

		# Replace remaining weapons with the new order
		var new_full_order = []
		# Keep completed weapons
		for i in range(current_index):
			new_full_order.append(existing_order[i])
		# Add reordered remaining weapons
		new_full_order.append_array(weapon_order)

		resolution_state["weapon_order"] = new_full_order
		resolution_state["phase"] = "ready"
		DebugLogger.info("ShootingPhase: Updated weapon_order, continuing to next weapon")

		# Continue with next weapon
		var next_result = _resolve_next_weapon()
		DebugLogger.info(str("ShootingPhase: _resolve_next_weapon returned = ", next_result))
		DebugLogger.info("========================================")
		return next_result

	# Update confirmed assignments with the ordered weapons
	confirmed_assignments = weapon_order.duplicate(true)
	DebugLogger.info(str("ShootingPhase: confirmed_assignments after = ", confirmed_assignments))

	if fast_roll:
		# SINGLE-PLAYER FAST ROLL: resolve weapon-by-weapon through the SAME
		# sequential-staged machinery with every pause auto-skipped, instead of
		# one combined RulesEngine call. The old combined path rolled ALL
		# weapons up front but the save flow only ever applied the FIRST
		# (weapon, target) batch — then offered "Continue to Next Weapon",
		# RE-ROLLING the remaining weapons and silently discarding any wounds
		# they had already caused. Weapon-by-weapon keeps per-target saves,
		# per-weapon phase-log records and destroyed-target skipping correct.
		# Networked play keeps the combined path (its save broadcast/ack sync
		# depends on the single batched save_data_list).
		if not NetworkManager.is_networked():
			log_phase_message("Fast rolling all weapons (sequential, no pauses)")
			resolution_state = {
				"mode": "sequential_staged",
				"auto_continue": true,
				"weapon_order": weapon_order,
				"current_index": 0,
				"completed_weapons": [],
				"awaiting_saves": false,
				"stage": ""
			}
			var fast_seq_result = _resolve_next_weapon()
			DebugLogger.info(str("ShootingPhase: SP fast roll (auto-continue) result = ", fast_seq_result.get("success", false)))
			DebugLogger.info("========================================")
			return fast_seq_result

		# Fast roll all weapons at once (networked behavior)
		log_phase_message("Fast rolling all weapons")
		resolution_state = {
			"mode": "fast",
			"weapon_order": weapon_order,
			"current_assignment": 0,
			"current_index": 0,
			"completed_weapons": [],
			"awaiting_saves": false,
			"phase": "ready"
		}

		# Call normal resolution
		DebugLogger.info("ShootingPhase: Calling _process_resolve_shooting for fast roll...")
		var resolve_result = _process_resolve_shooting({})
		DebugLogger.info(str("ShootingPhase: Fast roll result = ", resolve_result))
		DebugLogger.info("========================================")
		return resolve_result
	else:
		# Sequential resolution - resolve one weapon at a time.
		# In non-networked play we use the STAGED variant: each weapon rolls to
		# hit, PAUSES (so the attacker can read the result / use Command Re-roll),
		# then rolls to wound, PAUSES again, then goes to saves. Networked games
		# keep the original one-shot "sequential" mode (its saves ack/retry sync
		# is unchanged) to avoid desync — mirrors how Command Re-roll is host/SP
		# only elsewhere.
		var seq_mode = "sequential"
		if not NetworkManager.is_networked():
			seq_mode = "sequential_staged"
		log_phase_message("Starting sequential weapon resolution (%s)" % seq_mode)
		DebugLogger.info("ShootingPhase: Starting sequential resolution... mode=%s" % seq_mode)
		resolution_state = {
			"mode": seq_mode,
			"weapon_order": weapon_order,
			"current_index": 0,
			"completed_weapons": [],
			"awaiting_saves": false,
			"stage": ""
		}
		DebugLogger.info(str("ShootingPhase: resolution_state = ", resolution_state))

		# Start resolving first weapon
		DebugLogger.info("ShootingPhase: Calling _resolve_next_weapon()...")
		var next_result = _resolve_next_weapon()
		DebugLogger.info(str("ShootingPhase: _resolve_next_weapon returned = ", next_result))
		DebugLogger.info("========================================")
		return next_result

func _resolve_next_weapon() -> Dictionary:
	"""Resolve the next weapon in the sequence"""
	DebugLogger.info("========================================")
	DebugLogger.info("ShootingPhase: _resolve_next_weapon CALLED")
	DebugLogger.info(str("ShootingPhase: resolution_state = ", resolution_state))

	var current_index = resolution_state.get("current_index", 0)
	var weapon_order = resolution_state.get("weapon_order", [])

	DebugLogger.info(str("ShootingPhase: current_index = ", current_index))
	DebugLogger.info(str("ShootingPhase: weapon_order.size() = ", weapon_order.size()))
	DebugLogger.info(str("ShootingPhase: active_shooter_id = ", active_shooter_id))

	if current_index >= weapon_order.size():
		# All weapons complete
		DebugLogger.info("ShootingPhase: All weapons complete!")
		log_phase_message("All weapons resolved sequentially")

		# Mark shooter as done
		var shooter_id = active_shooter_id  # Store before clearing
		units_that_shot.append(active_shooter_id)
		var changes = [{
			"op": "set",
			"path": "units.%s.flags.has_shot" % active_shooter_id,
			"value": true
		}]
		changes.append(_hidden_shot_stamp(active_shooter_id))

		# Return shooter to idle animation
		_trigger_unit_animation(active_shooter_id, "idle")

		# T5-UX9: capture per-weapon shot results before clearing resolution_state
		_record_completed_weapons_to_phase_log(shooter_id)

		# Clear state
		active_shooter_id = ""
		confirmed_assignments.clear()
		resolution_state.clear()

		# Emit signal to clear visuals
		emit_signal("shooting_resolved", shooter_id, "", {"casualties": 0})

		return create_result(true, changes, "Sequential weapon resolution complete")

	# Skip weapons whose target unit has been fully destroyed
	while current_index < weapon_order.size():
		var next_assignment = weapon_order[current_index]
		var next_target_id = next_assignment.get("target_unit_id", "")
		if next_target_id == "" or not _is_unit_destroyed(next_target_id):
			break
		# Target is destroyed — skip this weapon
		var skipped_weapon_id = next_assignment.get("weapon_id", "")
		var skipped_weapon_profile = RulesEngine.get_weapon_profile(skipped_weapon_id)
		var skipped_weapon_name = skipped_weapon_profile.get("name", skipped_weapon_id)
		var skipped_target_name = get_unit(next_target_id).get("meta", {}).get("name", next_target_id)
		DebugLogger.info(str("ShootingPhase: SKIPPING weapon %d (%s) — target unit %s is destroyed" % [current_index + 1, skipped_weapon_name, skipped_target_name]))
		log_phase_message("Skipped %s — target %s destroyed" % [skipped_weapon_name, skipped_target_name])
		resolution_state.completed_weapons.append({
			"weapon_id": skipped_weapon_id,
			"target_unit_id": next_target_id,
			"target_unit_name": skipped_target_name,
			"wounds": 0,
			"casualties": 0,
			"hits": 0,
			"total_attacks": 0,
			"saves_failed": 0,
			"dice_rolls": [],
			"hit_data": {},
			"wound_data": {},
			"skipped_target_destroyed": true
		})
		current_index += 1
		resolution_state.current_index = current_index

	# Re-check if all weapons are now complete (some may have been skipped)
	if current_index >= weapon_order.size():
		DebugLogger.info("ShootingPhase: All weapons complete (some skipped due to destroyed targets)")
		log_phase_message("All weapons resolved sequentially")

		var shooter_id = active_shooter_id
		units_that_shot.append(active_shooter_id)
		var changes = [{
			"op": "set",
			"path": "units.%s.flags.has_shot" % active_shooter_id,
			"value": true
		}]

		# T5-UX9: capture before clearing
		_record_completed_weapons_to_phase_log(shooter_id)

		active_shooter_id = ""
		confirmed_assignments.clear()
		resolution_state.clear()

		emit_signal("shooting_resolved", shooter_id, "", {"casualties": 0})

		return create_result(true, changes, "Sequential weapon resolution complete (remaining targets destroyed)")

	# Get current weapon assignment
	var current_assignment = weapon_order[current_index]
	var weapon_id = current_assignment.get("weapon_id", "")

	DebugLogger.info(str("ShootingPhase: Resolving weapon %d of %d: %s" % [current_index + 1, weapon_order.size(), weapon_id]))

	# STAGED sequential resolution (non-networked): roll ONLY the hit roll now and
	# pause. CONTINUE_TO_WOUNDS rolls the wound roll, CONTINUE_TO_SAVES emits saves.
	# Command Re-roll can be used at each pause (USE_SHOOTING_REROLL).
	if resolution_state.get("mode", "") == "sequential_staged":
		return _staged_roll_hits(current_assignment, weapon_id, current_index)

	# VERBOSE COMBAT LOG: Header BEFORE resolution so dice can display in real-time
	var _seq_shooter = game_state_snapshot.get("units", {}).get(active_shooter_id, {})
	var _seq_shooter_name = _seq_shooter.get("meta", {}).get("name", active_shooter_id)
	var _seq_weapon_profile = RulesEngine.get_weapon_profile(weapon_id)
	var _seq_weapon_name = _seq_weapon_profile.get("name", weapon_id)
	var _seq_target = get_unit(current_assignment.target_unit_id)
	var _seq_target_name = _seq_target.get("meta", {}).get("name", current_assignment.target_unit_id)
	GameEventLog.add_combat_header("P%d: %s → %s with %s (weapon %d/%d)" % [
		get_current_player(), _seq_shooter_name, _seq_target_name, _seq_weapon_name,
		current_index + 1, weapon_order.size()])

	# T5-MP5: Build weapon_progress block and emit locally + include in result for remote sync
	var weapon_progress_block = {
		"context": "weapon_progress",
		"message": "Resolving weapon %d of %d" % [current_index + 1, weapon_order.size()],
		"target_unit_id": current_assignment.get("target_unit_id", ""),  # B1: board chip emphasis
		"current_index": current_index,
		"total_weapons": weapon_order.size()
	}
	emit_signal("dice_rolled", weapon_progress_block)

	# Build shoot action for this single weapon
	var shoot_action = {
		"type": "SHOOT",
		"actor_unit_id": active_shooter_id,
		"payload": {
			"assignments": [current_assignment],  # Only this weapon
			"shooting_type": active_shooting_type  # 10.07 consequences follow the selected type
		}
	}

	# Resolve with RulesEngine UP TO WOUNDS
	var rng_service = RulesEngine.make_rng()
	DebugLogger.info("ShootingPhase: Calling RulesEngine.resolve_shoot_until_wounds()...")
	var result = RulesEngine.resolve_shoot_until_wounds(shoot_action, game_state_snapshot, rng_service)
	DebugLogger.info(str("ShootingPhase: RulesEngine returned: success=%s" % result.success))

	if not result.success:
		DebugLogger.info(str("ShootingPhase: ❌ Weapon resolution FAILED: ", result.get("log_text", "")))
		DebugLogger.info("========================================")
		return create_result(false, [], result.get("log_text", "Weapon resolution failed"))

	# ONE SHOT (T4-2): Collect one-shot diffs from result (weapon marked as fired immediately)
	var seq_one_shot_diffs = result.get("one_shot_diffs", [])
	# Store for inclusion in subsequent results
	pending_one_shot_diffs.append_array(seq_one_shot_diffs)

	# Record dice rolls
	# T5-MP5: Prepend weapon_progress block so remote player sees it in broadcast
	var dice_data = [weapon_progress_block] + result.get("dice", [])
	DebugLogger.info(str("ShootingPhase: Dice blocks returned: %d (including weapon_progress)" % dice_data.size()))
	for dice_block in result.get("dice", []):
		dice_log.append(dice_block)
		emit_signal("dice_rolled", dice_block)

	log_phase_message(result.get("log_text", "Weapon attacks complete"))
	DebugLogger.info(str("ShootingPhase: Log text: ", result.get("log_text", "")))

	# Emit hit/wound details
	_emit_verbose_combat_log(active_shooter_id, dice_data, [], 0, "sequential_hits")

	# Extract dice data for storage
	var hit_data = {}
	var wound_data = {}

	for dice_block in dice_data:
		var context = dice_block.get("context", "")
		if context == "hit_roll":
			hit_data = {
				"rolls": dice_block.get("rolls_raw", []),
				"modified_rolls": dice_block.get("rolls_modified", []),
				"successes": dice_block.get("successes", 0),
				"total": dice_block.get("rolls_raw", []).size(),
				"rerolls": dice_block.get("rerolls", []),
				"threshold": dice_block.get("threshold", "")
			}
		elif context == "wound_roll":
			wound_data = {
				"rolls": dice_block.get("rolls_raw", []),
				"modified_rolls": dice_block.get("rolls_modified", []),
				"successes": dice_block.get("successes", 0),
				"total": dice_block.get("rolls_raw", []).size(),
				"threshold": dice_block.get("threshold", "")
			}

	# Get target unit name for display
	var target_unit = get_unit(current_assignment.target_unit_id)
	var target_unit_name = target_unit.get("meta", {}).get("name", current_assignment.target_unit_id)

	# Store dice data in resolution_state for later retrieval (when saves complete)
	resolution_state.last_weapon_dice_data = dice_data
	resolution_state.last_weapon_hit_data = hit_data
	resolution_state.last_weapon_wound_data = wound_data
	resolution_state.last_weapon_target_name = target_unit_name
	resolution_state.last_weapon_target_id = current_assignment.target_unit_id

	# Check if saves are needed (shared tail — see _finish_weapon_resolution)
	var save_data_list = result.get("save_data_list", [])
	return _finish_weapon_resolution(current_assignment, weapon_id, current_index, dice_data, hit_data, wound_data, target_unit_name, save_data_list, result.get("log_text", ""), result.get("hazardous_weapons", []))

# Shared tail for sequential weapon resolution: given a fully-rolled weapon
# (hit + wound dice already emitted), either pauses for saves (wounds) or for
# next-weapon confirmation (no wounds). Called by _resolve_next_weapon (fast /
# non-staged path) AND by the staged re-roll path after the wound stage.
func _finish_weapon_resolution(current_assignment: Dictionary, weapon_id: String, current_index: int, dice_data: Array, hit_data: Dictionary, wound_data: Dictionary, target_unit_name: String, save_data_list: Array, log_text: String, hazardous_weapons: Array) -> Dictionary:
	var weapon_order = resolution_state.get("weapon_order", [])
	# Check if saves are needed
	DebugLogger.info(str("ShootingPhase: save_data_list.size() = %d" % save_data_list.size()))

	if save_data_list.is_empty():
		# No wounds - but still PAUSE for attacker to confirm next weapon (sequential mode)
		DebugLogger.info("ShootingPhase: ⚠ No wounds caused by this weapon")

		# P1-11: Track hits for Sanctified Flames
		var seq_hits = hit_data.get("successes", 0)
		if seq_hits > 0:
			var tid = current_assignment.target_unit_id
			_targets_hit_by_shooter[tid] = _targets_hit_by_shooter.get(tid, 0) + seq_hits
			DebugLogger.info(str("ShootingPhase: P1-11 Sanctified Flames tracking: %d hit(s) on %s (total: %d)" % [seq_hits, tid, _targets_hit_by_shooter[tid]]))

		resolution_state.completed_weapons.append({
			"weapon_id": weapon_id,
			"target_unit_id": current_assignment.target_unit_id,
			"target_unit_name": target_unit_name,
			"wounds": 0,
			"casualties": 0,
			"hits": hit_data.get("successes", 0),
			"total_attacks": hit_data.get("total", 0),
			"saves_failed": 0,
			"dice_rolls": dice_data,
			"hit_data": hit_data,
			"wound_data": wound_data
		})
		resolution_state.current_index += 1
		DebugLogger.info(str("ShootingPhase: Incremented current_index to %d" % resolution_state.current_index))
		DebugLogger.info(str("ShootingPhase: Weapons remaining: %d" % (weapon_order.size() - resolution_state.current_index)))

		# ALWAYS PAUSE for attacker to confirm (even if last weapon)
		# Wait for attacker to confirm before continuing or completing
		DebugLogger.info("ShootingPhase: ⚠ PAUSING - Waiting for attacker to confirm next weapon (no hits)")
		DebugLogger.info(str("ShootingPhase: Weapons remaining: ", weapon_order.size() - resolution_state.current_index))

		# Build remaining weapons with validation (may be empty array if this is the last weapon)
		var remaining_weapons = []

		DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
		DebugLogger.info("║ BUILDING REMAINING WEAPONS (after miss)")
		DebugLogger.info(str("║ weapon_order.size() = %d" % weapon_order.size()))
		DebugLogger.info(str("║ current_index = %d" % resolution_state.current_index))
		DebugLogger.info(str("║ Expected remaining = %d" % (weapon_order.size() - resolution_state.current_index)))

		for i in range(resolution_state.current_index, weapon_order.size()):
			var weapon = weapon_order[i]
			var miss_target_id = weapon.get("target_unit_id", "")

			# Filter out weapons whose target unit is already destroyed
			if miss_target_id != "" and _is_unit_destroyed(miss_target_id):
				var skipped_wid = weapon.get("weapon_id", "")
				var skipped_wp = RulesEngine.get_weapon_profile(skipped_wid)
				DebugLogger.info(str("║ Filtered weapon %d: %s (target %s already destroyed)" % [i, skipped_wp.get("name", skipped_wid), miss_target_id]))
				continue

			remaining_weapons.append(weapon)

			# Validate weapon structure
			var remaining_weapon_id = weapon.get("weapon_id", "")
			if remaining_weapon_id == "":
				push_error("ShootingPhase: Weapon at index %d has EMPTY weapon_id!" % i)
				DebugLogger.info(str("║ ⚠️  WARNING: Weapon %d has no weapon_id" % i))
				DebugLogger.info(str("║   Full weapon object: %s" % str(weapon)))
			else:
				DebugLogger.info(str("║ Added weapon %d: %s" % [i, remaining_weapon_id]))

		DebugLogger.info(str("║ Total remaining weapons: %d" % remaining_weapons.size()))
		if remaining_weapons.is_empty():
			DebugLogger.info("║ ✓ All remaining weapons skipped or this is the FINAL weapon")
		DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

		# AUTO-COMPLETE: If all remaining weapons target destroyed units, skip them
		# and complete shooting automatically (no dialog needed)
		var _has_destroyed_targets = false
		for i in range(resolution_state.current_index, weapon_order.size()):
			var check_tid = weapon_order[i].get("target_unit_id", "")
			if check_tid != "" and _is_unit_destroyed(check_tid):
				_has_destroyed_targets = true
				break

		if remaining_weapons.is_empty() and _has_destroyed_targets:
			DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
			DebugLogger.info("║ AUTO-COMPLETE: All remaining targets destroyed (miss path)")

			var auto_changes = []
			if not pending_one_shot_diffs.is_empty():
				auto_changes.append_array(pending_one_shot_diffs)
				pending_one_shot_diffs.clear()

			# Record skipped weapons in completed_weapons
			for i in range(resolution_state.current_index, weapon_order.size()):
				var skipped_assignment = weapon_order[i]
				var skipped_wid = skipped_assignment.get("weapon_id", "")
				var skipped_tid = skipped_assignment.get("target_unit_id", "")
				var skipped_wp = RulesEngine.get_weapon_profile(skipped_wid)
				var skipped_wname = skipped_wp.get("name", skipped_wid)
				var skipped_tname = get_unit(skipped_tid).get("meta", {}).get("name", skipped_tid)
				DebugLogger.info(str("║ Skipped: %s → %s (target destroyed)" % [skipped_wname, skipped_tname]))
				log_phase_message("Skipped %s — target %s destroyed" % [skipped_wname, skipped_tname])
				resolution_state.completed_weapons.append({
					"weapon_id": skipped_wid,
					"target_unit_id": skipped_tid,
					"target_unit_name": skipped_tname,
					"wounds": 0,
					"casualties": 0,
					"hits": 0,
					"total_attacks": 0,
					"saves_failed": 0,
					"dice_rolls": [],
					"hit_data": {},
					"wound_data": {},
					"skipped_target_destroyed": true
				})

			# Mark shooter as done
			var shooter_id = active_shooter_id
			auto_changes.append({
				"op": "set",
				"path": "units.%s.flags.has_shot" % active_shooter_id,
				"value": true
			})
			units_that_shot.append(active_shooter_id)

			# T5-UX9: capture before clearing
			_record_completed_weapons_to_phase_log(shooter_id)

			# Clear state
			active_shooter_id = ""
			confirmed_assignments.clear()
			resolution_state.clear()
			pending_save_data.clear()
			_targets_hit_by_shooter.clear()

			# Emit signal to clear visuals
			emit_signal("shooting_resolved", shooter_id, "", {"casualties": 0})

			DebugLogger.info("║ Shooting auto-completed — all remaining targets destroyed")
			DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

			return create_result(true, auto_changes, "Sequential weapon resolution complete (remaining targets destroyed)", {
				"dice": dice_data,
				"log_text": log_text
			})

		# FAST ROLL (auto-continue): a weapon that caused no wounds also flows
		# straight into the next weapon — no between-weapon pause.
		if resolution_state.get("auto_continue", false) and not remaining_weapons.is_empty():
			DebugLogger.info("ShootingPhase: FAST ROLL auto-continue (no wounds) — deferring CONTINUE_SEQUENCE")
			var fast_miss_changes = []
			if not pending_one_shot_diffs.is_empty():
				fast_miss_changes.append_array(pending_one_shot_diffs)
				pending_one_shot_diffs.clear()
			call_deferred("_auto_continue_next_weapon")
			return create_result(true, fast_miss_changes, "Weapon %d complete (no wounds) — fast-rolling next weapon" % (current_index + 1), {
				"dice": dice_data,
				"log_text": log_text
			})

		# Get last weapon result for dialog display
		var last_weapon_result = _get_last_weapon_result()

		# Emit signal to show confirmation dialog to attacker
		# NOTE: remaining_weapons may be EMPTY if this is the final weapon
		emit_signal("next_weapon_confirmation_required", remaining_weapons, resolution_state.current_index, last_weapon_result)

		# Return success with pause indicator for multiplayer sync
		# ONE SHOT (T4-2): Include one-shot diffs in the result
		var seq_miss_changes = []
		if not pending_one_shot_diffs.is_empty():
			seq_miss_changes.append_array(pending_one_shot_diffs)
			pending_one_shot_diffs.clear()
		DebugLogger.info("ShootingPhase: Returning result with sequential_pause indicator")
		DebugLogger.info("========================================")
		return create_result(true, seq_miss_changes, "Weapon %d complete (0 hits) - awaiting confirmation" % (current_index + 1), {
			"sequential_pause": true,
			"current_weapon_index": resolution_state.current_index,
			"total_weapons": weapon_order.size(),
			"weapons_remaining": weapon_order.size() - resolution_state.current_index,
			"remaining_weapons": remaining_weapons,
			"last_weapon_result": last_weapon_result,
			"dice": dice_data,
			"log_text": log_text
		})

	# Store save data and trigger interactive saves
	pending_save_data = save_data_list
	resolution_state.awaiting_saves = true

	# HAZARDOUS (T2-3): Store hazardous weapon data for post-save resolution
	pending_hazardous_weapons = hazardous_weapons

	# Add sequence context to save data for WoundAllocationOverlay
	for save_data in save_data_list:
		save_data["sequence_context"] = {
			"current_weapon": current_index + 1,
			"total_weapons": weapon_order.size(),
			"weapon_name": RulesEngine.get_weapon_profile(weapon_id).get("name", weapon_id)
		}

	# T5-MP4-RELIABILITY: Stamp broadcast id (see _generate_save_broadcast_id)
	var broadcast_id := _generate_save_broadcast_id()
	_stamp_save_broadcast_id(save_data_list, broadcast_id)

	# LOGGING: Track saves_required emission
	var timestamp = Time.get_ticks_msec()
	var save_context = {
		"timestamp": timestamp,
		"source": "ShootingPhase._resolve_next_weapon",
		"save_count": save_data_list.size(),
		"target": save_data_list[0].get("target_unit_id", "unknown") if save_data_list.size() > 0 else "none",
		"weapon": save_data_list[0].get("weapon_name", "unknown") if save_data_list.size() > 0 else "none",
		"wounds": save_data_list[0].get("wounds_to_save", 0) if save_data_list.size() > 0 else 0,
		"sequence_weapon": current_index + 1,
		"sequence_total": weapon_order.size(),
		"broadcast_id": broadcast_id
	}
	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ SAVES_REQUIRED EMISSION #2 (from resolve_next_weapon)")
	DebugLogger.info(str("║ Timestamp: ", timestamp))
	DebugLogger.info("║ Source: ShootingPhase._resolve_next_weapon (line 750)")
	DebugLogger.info(str("║ Target: ", save_context.target))
	DebugLogger.info(str("║ Weapon: ", save_context.weapon, " (", save_context.sequence_weapon, "/", save_context.sequence_total, ")"))
	DebugLogger.info(str("║ Wounds: ", save_context.wounds))
	DebugLogger.info(str("║ Broadcast ID: ", broadcast_id))
	DebugLogger.info(str("║ Save data list size: ", save_data_list.size()))
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	# Emit signal to show save dialog
	DebugLogger.info(str("ShootingPhase: ✅ Emitting saves_required signal with %d save data entries" % save_data_list.size()))
	emit_signal("saves_required", save_data_list)

	log_phase_message("Awaiting defender to make saves for weapon %d of %d..." % [current_index + 1, weapon_order.size()])

	# Return success but don't advance to next weapon yet - wait for saves
	DebugLogger.info("ShootingPhase: Returning result with save_data_list for multiplayer broadcast")
	DebugLogger.info(str("ShootingPhase: Result will include %d dice blocks and %d save data entries" % [dice_data.size(), save_data_list.size()]))
	DebugLogger.info("========================================")
	return create_result(true, [], "Awaiting save resolution", {
		"dice": dice_data,
		"save_data_list": save_data_list,
		"log_text": log_text
	})


# ==========================================================================
# STAGED sequential resolution (non-networked): hit roll -> pause -> wound roll
# -> pause -> saves, with Command Re-roll (USE_SHOOTING_REROLL) at each pause.
# ==========================================================================

func _shooting_reroll_available(stage: String = "") -> bool:
	# Codex: Adeptus Custodes PRIME TARGET (CustodesCodex11e.gd): the shooter's free single re-roll of this stage.
	if stage != "" and _cus11e_prime_target_reroll(stage):
		return true
	# A staged hit/wound Command Re-roll is offered when the active player has not
	# already used Command Re-roll this phase and can pay the CP.
	var sm = get_node_or_null("/root/StratagemManager")
	if sm == null or not sm.has_method("is_command_reroll_available"):
		return false
	var chk = sm.is_command_reroll_available(get_current_player(), active_shooter_id)
	return chk.get("available", false)

## Codex: Adeptus Custodes PRIME TARGET (CustodesCodex11e.gd): does the active
## shooter still have its free single re-roll for this stage ("hits"/"wounds",
## or "hit"/"wound")?
func _cus11e_prime_target_reroll(stage: String) -> bool:
	if active_shooter_id == "":
		return false
	var st := "hit" if stage.begins_with("hit") else "wound"
	return bool(_cus11e_codex().single_reroll_available(GameState.get_unit(active_shooter_id), st))

func _cus11e_reroll_label(stage: String) -> String:
	if _cus11e_prime_target_reroll(stage):
		return "PRIME TARGET (free) — click a %s die to re-roll it:" % ("hit" if stage == "hits" else "wound")
	return ""

func _extract_staged_hit_wound(dice_data: Array) -> Array:
	# Pull hit/wound summary dicts out of the emitted to_hit / to_wound blocks so
	# the completed-weapon record (and NextWeaponDialog summary) show real counts.
	var hit_data = {}
	var wound_data = {}
	for db in dice_data:
		var ctx = db.get("context", "")
		if ctx == "to_hit" or ctx == "auto_hit":
			hit_data = {
				"rolls": db.get("rolls_raw", []),
				"modified_rolls": db.get("rolls_modified", []),
				"successes": db.get("successes", 0),
				"total": (db.get("rolls_raw", []) as Array).size(),
				"rerolls": db.get("rerolls", []),
				"threshold": db.get("threshold", "")
			}
		elif ctx == "to_wound":
			wound_data = {
				"rolls": db.get("rolls_raw", []),
				"successes": db.get("successes", 0),
				"total": (db.get("rolls_raw", []) as Array).size(),
				"threshold": db.get("threshold", "")
			}
	return [hit_data, wound_data]

func _staged_roll_hits(current_assignment: Dictionary, weapon_id: String, current_index: int) -> Dictionary:
	var weapon_order = resolution_state.get("weapon_order", [])
	var shooter = game_state_snapshot.get("units", {}).get(active_shooter_id, {})
	var shooter_name = shooter.get("meta", {}).get("name", active_shooter_id)
	var weapon_profile = RulesEngine.get_weapon_profile(weapon_id)
	var weapon_name = weapon_profile.get("name", weapon_id)
	var target = get_unit(current_assignment.get("target_unit_id", ""))
	var target_name = target.get("meta", {}).get("name", current_assignment.get("target_unit_id", ""))

	GameEventLog.add_combat_header("P%d: %s → %s with %s (weapon %d/%d)" % [
		get_current_player(), shooter_name, target_name, weapon_name, current_index + 1, weapon_order.size()])

	# Verbose progress line that NAMES the weapon and target (Part A).
	var progress = {
		"context": "weapon_progress",
		"message": "Weapon %d of %d — %s → %s" % [current_index + 1, weapon_order.size(), weapon_name, target_name],
		"weapon_name": weapon_name,
		"target_name": target_name,
		"target_unit_id": current_assignment.get("target_unit_id", ""),  # B1: board chip emphasis
		"current_index": current_index,
		"total_weapons": weapon_order.size(),
		"stage": "hits"
	}
	emit_signal("dice_rolled", progress)

	# Roll ONLY the hit roll for this weapon.
	var shoot_action = {"type": "SHOOT", "actor_unit_id": active_shooter_id, "payload": {"assignments": [current_assignment], "shooting_type": active_shooting_type}}
	var rng = RulesEngine.make_rng()
	var hres = RulesEngine.resolve_shoot_hits(shoot_action, game_state_snapshot, rng)
	if not hres.get("success", false):
		DebugLogger.info("ShootingPhase: staged hit roll FAILED: " + str(hres.get("log_text", "")))
		return create_result(false, [], hres.get("log_text", "Hit resolution failed"))

	pending_one_shot_diffs.append_array(hres.get("one_shot_diffs", []))

	var dice_data = [progress]
	for db in hres.get("dice", []):
		dice_log.append(db)
		emit_signal("dice_rolled", db)
		dice_data.append(db)
	log_phase_message(hres.get("log_text", ""))
	_emit_verbose_combat_log(active_shooter_id, dice_data, [], 0, "sequential_hits")

	# Stash everything the wound / save stages and the re-roll need.
	resolution_state.stage = "hits_pending"
	resolution_state.staged_hit_context = hres.get("hit_context", {})
	resolution_state.staged_assignment = current_assignment
	resolution_state.staged_weapon_id = weapon_id
	resolution_state.staged_weapon_name = weapon_name
	resolution_state.staged_target_name = target_name
	resolution_state.staged_hazardous = hres.get("hazardous_weapons", [])
	resolution_state.staged_dice = dice_data
	resolution_state.staged_wound_context = {}
	resolution_state.staged_save_data_list = []

	# FAST ROLL (auto-continue): the attacker chose "Fast Roll All", so skip the
	# hit pause and roll straight through wounds to the saving throws.
	# pause=false in _staged_continue_to_wounds also skips the wound pause.
	if resolution_state.get("auto_continue", false):
		return _staged_continue_to_wounds(false)

	var hc = hres.get("hit_context", {})
	var can_reroll = _shooting_reroll_available("hits") and not hc.get("is_torrent", false) \
			and not hc.get("no_hit_rerolls", false) and not (hc.get("hit_rolls", []) as Array).is_empty()

	# Tell the attacker's dialog we are paused after the hit roll (show a
	# "Roll to Wound" button + optional per-die Command Re-roll).
	emit_signal("shooting_stage_paused", "hits", {
		"weapon_name": weapon_name,
		"target_name": target_name,
		"current_index": current_index,
		"total_weapons": weapon_order.size(),
		"reroll_available": can_reroll,
		"reroll_label": _cus11e_reroll_label("hits"),
		"hit_rolls": hc.get("hit_rolls", []),
		"modified_rolls": hc.get("modified_rolls", []),
		"die_evals": hc.get("hit_evals", []),  # per-die re-roll provenance (Captain-General etc.) for the dock chips
		"hits": hc.get("hits", 0),
		"threshold": str(hc.get("hit_threshold_display", str(hc.get("bs", 4)) + "+")),  # effective need (cover / indirect band)
		# Named provenance for every hit modifier that applied — the dock lists
		# these so a shifted threshold is traceable to the rule behind it.
		"modifier_ledger": hc.get("modifier_ledger", [])
	})

	log_phase_message("Weapon %d of %d hit roll complete — awaiting attacker to continue to wound roll" % [current_index + 1, weapon_order.size()])
	return create_result(true, [], "Weapon %d hits rolled — awaiting continue" % (current_index + 1), {
		"staged_pause": "hits",
		"current_weapon_index": current_index,
		"total_weapons": weapon_order.size(),
		"weapon_name": weapon_name,
		"target_name": target_name,
		"reroll_available": can_reroll,
		"hit_rolls": hc.get("hit_rolls", []),
		"hits": hc.get("hits", 0),
		"dice": dice_data
	})

func _staged_continue_to_wounds(pause: bool = true) -> Dictionary:
	# pause == false is the "Fast Roll" escape: roll the wound roll and go straight
	# to the saving throws without stopping at the wound pause.
	if resolution_state.get("stage", "") != "hits_pending":
		return create_result(false, [], "Not awaiting continue-to-wounds")
	var hit_context = resolution_state.get("staged_hit_context", {})
	var current_assignment = resolution_state.get("staged_assignment", {})
	var weapon_id = resolution_state.get("staged_weapon_id", "")
	var target_name = resolution_state.get("staged_target_name", "")
	var current_index = int(resolution_state.get("current_index", 0))
	var weapon_order = resolution_state.get("weapon_order", [])

	var rng = RulesEngine.make_rng()
	var wres = RulesEngine.resolve_shoot_wounds(hit_context, game_state_snapshot, rng)
	# GROT SHIELDS (Codex: Orks 11e): Gretchin mortal-wound diffs from the wound stage.
	pending_one_shot_diffs.append_array(wres.get("one_shot_diffs", []))
	# enemy_has_shot window: the final hit count (after any Command Re-roll).
	_ork11e_note_hits(str(hit_context.get("target_unit_id", "")), int(hit_context.get("hits", 0)))

	var dice_data = (resolution_state.get("staged_dice", []) as Array).duplicate()
	var gs_blocks: Array = []
	for db in wres.get("dice", []):
		dice_log.append(db)
		emit_signal("dice_rolled", db)
		dice_data.append(db)
		if str(db.get("context", "")) == "grot_shields":
			gs_blocks.append(db)
	resolution_state.staged_dice = dice_data
	log_phase_message(wres.get("log_text", ""))
	# GROT SHIELDS intercepts at the wound stage: the staged (dock) flow logged
	# only the hit roll, so say in the Game Log where those hits went (r3:F6).
	if not gs_blocks.is_empty():
		_emit_verbose_combat_log(active_shooter_id, gs_blocks, [], 0, "sequential_wounds")

	var save_data_list = wres.get("save_data_list", [])
	resolution_state.staged_wound_context = wres.get("wound_context", {})
	resolution_state.staged_save_data_list = save_data_list

	var hw = _extract_staged_hit_wound(dice_data)
	var hit_data = hw[0]
	var wound_data = hw[1]
	resolution_state.last_weapon_dice_data = dice_data
	resolution_state.last_weapon_hit_data = hit_data
	resolution_state.last_weapon_wound_data = wound_data
	resolution_state.last_weapon_target_name = target_name
	resolution_state.last_weapon_target_id = current_assignment.get("target_unit_id", "")

	if save_data_list.is_empty():
		# No wounds — go straight to the shared no-wounds / next-weapon tail.
		resolution_state.stage = ""
		return _finish_weapon_resolution(current_assignment, weapon_id, current_index, dice_data, hit_data, wound_data, target_name, [], wres.get("log_text", ""), resolution_state.get("staged_hazardous", []))

	# Wounds caused — PAUSE so the attacker can read the wound roll / Command
	# Re-roll a wound die before the defender makes saves.
	resolution_state.stage = "wounds_pending"
	# Fast Roll: skip the wound pause entirely and hand off to saving throws now.
	if not pause:
		return _staged_continue_to_saves()
	var wc = resolution_state.get("staged_wound_context", {})
	var can_reroll = _shooting_reroll_available("wounds") and not (wc.get("wound_evals", []) as Array).is_empty()
	emit_signal("shooting_stage_paused", "wounds", {
		"current_index": current_index,
		"total_weapons": weapon_order.size(),
		"reroll_available": can_reroll,
		"reroll_label": _cus11e_reroll_label("wounds"),
		"wound_rolls": wc.get("wound_rolls", []),
		"die_evals": wc.get("wound_evals", []),
		"wounds": save_data_list[0].get("wounds_to_save", 0) if not save_data_list.is_empty() else 0,
		"target_name": target_name,
		"threshold": str(wc.get("wound_threshold", 4)) + "+",
		"modifier_ledger": wc.get("modifier_ledger", [])
	})
	log_phase_message("Weapon %d of %d wound roll complete — awaiting attacker to continue to saving throws" % [current_index + 1, weapon_order.size()])
	return create_result(true, [], "Weapon %d wounds rolled — awaiting continue to saves" % (current_index + 1), {
		"staged_pause": "wounds",
		"current_weapon_index": current_index,
		"total_weapons": weapon_order.size(),
		"reroll_available": can_reroll,
		"wounds": save_data_list[0].get("wounds_to_save", 0) if not save_data_list.is_empty() else 0,
		"dice": dice_data
	})

func _staged_continue_to_saves() -> Dictionary:
	if resolution_state.get("stage", "") != "wounds_pending":
		return create_result(false, [], "Not awaiting continue-to-saves")
	var current_assignment = resolution_state.get("staged_assignment", {})
	var weapon_id = resolution_state.get("staged_weapon_id", "")
	var target_name = resolution_state.get("staged_target_name", "")
	var current_index = int(resolution_state.get("current_index", 0))
	var dice_data = resolution_state.get("staged_dice", [])
	var save_data_list = resolution_state.get("staged_save_data_list", [])
	var hw = _extract_staged_hit_wound(dice_data)
	resolution_state.stage = ""
	# Route through the shared tail — emits saves_required with sequence context.
	return _finish_weapon_resolution(current_assignment, weapon_id, current_index, dice_data, hw[0], hw[1], target_name, save_data_list, "", resolution_state.get("staged_hazardous", []))

func _replace_staged_dice_block(context: String, new_block: Dictionary) -> void:
	var dd = resolution_state.get("staged_dice", [])
	for i in range(dd.size()):
		if dd[i].get("context", "") == context:
			dd[i] = new_block
			return
	dd.append(new_block)

func _process_use_shooting_reroll(action: Dictionary) -> Dictionary:
	var payload = action.get("payload", {})
	var stage = str(payload.get("stage", ""))
	var die_index = int(payload.get("die_index", -1))
	var expected = "hits_pending" if stage == "hits" else ("wounds_pending" if stage == "wounds" else "")
	if expected == "" or resolution_state.get("stage", "") != expected:
		return create_result(false, [], "No re-roll available at this stage")
	# A die that was already re-rolled (e.g. by LONG, UNCONTROLLED BURSTS) can
	# never be re-rolled again — refuse BEFORE the CP is spent (r5:F7).
	var rr_ctx: Dictionary = resolution_state.get("staged_hit_context", {}) if stage == "hits" else resolution_state.get("staged_wound_context", {})
	if RulesEngine.staged_die_already_rerolled(rr_ctx, stage, die_index):
		return create_result(false, [], "That die has already been re-rolled — a dice can never be re-rolled more than once")
	# Hit dice that cannot be re-rolled at all (10.07 indirect shooting, a
	# [TORRENT] weapon) — RulesEngine.reroll_hit_die refuses them, but only
	# after the CP / once-per-phase Command Re-roll would already be spent.
	if stage == "hits" and rr_ctx.get("is_torrent", false):
		return create_result(false, [], "Torrent weapons make no hit roll to re-roll")
	if stage == "hits" and rr_ctx.get("no_hit_rerolls", false):
		return create_result(false, [], "Indirect shooting: hit rolls cannot be re-rolled (10.07)")

	# Codex: Adeptus Custodes PRIME TARGET (CustodesCodex11e.gd): the free single
	# re-roll of this stage is spent first; otherwise the Command Re-roll.
	var reroll_source := "Command Re-roll (1 CP)"
	var cus11e_pt_diffs: Array = []
	if _cus11e_prime_target_reroll(stage):
		cus11e_pt_diffs = _cus11e_codex().single_reroll_spend_diffs(active_shooter_id, "hit" if stage == "hits" else "wound")
		PhaseManager.apply_state_changes(cus11e_pt_diffs)
		reroll_source = "PRIME TARGET (free)"
		GameEventLog.add_player_entry(get_current_player(), "PRIME TARGET: %s re-rolls one %s roll" % [GameState.get_unit_display_name(active_shooter_id), "hit" if stage == "hits" else "wound"])
	else:
		# Spend the CP + record the once-per-phase Command Re-roll usage.
		var sm = get_node_or_null("/root/StratagemManager")
		if sm == null or not sm.has_method("execute_command_reroll"):
			return create_result(false, [], "Command Re-roll unavailable")
		var player = get_current_player()
		var strat_result = sm.execute_command_reroll(player, active_shooter_id, {"roll_type": stage + "_roll"})
		if not strat_result.get("success", false):
			return create_result(false, [], str(strat_result.get("reason", "Cannot use Command Re-roll")))

	var rng = RulesEngine.make_rng()
	if stage == "hits":
		var hc = resolution_state.get("staged_hit_context", {})
		var rr = RulesEngine.reroll_hit_die(hc, die_index, rng)
		if not rr.get("success", false):
			return create_result(false, [], str(rr.get("error", "Re-roll failed")))
		emit_signal("dice_rolled", {"context": "reroll_note",
			"message": "%s: hit die %d → %d" % [reroll_source, rr.get("old_display", rr.get("old_value", 0)), rr.get("new_display", rr.get("new_value", 0))]})
		emit_signal("dice_rolled", rr.get("dice_block", {}))
		_replace_staged_dice_block("to_hit", rr.get("dice_block", {}))
		var uhc = rr.get("hit_context", {})
		emit_signal("shooting_stage_paused", "hits", {
			"reroll_available": false,
			"hit_rolls": uhc.get("hit_rolls", []),
			"modified_rolls": uhc.get("modified_rolls", []),
			"die_evals": uhc.get("hit_evals", []),
			"hits": uhc.get("hits", 0),
			"modifier_ledger": uhc.get("modifier_ledger", [])
		})
		return create_result(true, cus11e_pt_diffs, "Hit die re-rolled", {
			"staged_pause": "hits", "reroll_used": true, "reroll_available": false,
			"dice_block": rr.get("dice_block", {}), "hits": rr.get("hit_context", {}).get("hits", 0)
		})
	else:
		var wc = resolution_state.get("staged_wound_context", {})
		var rr = RulesEngine.reroll_wound_die(wc, die_index, game_state_snapshot, rng)
		if not rr.get("success", false):
			return create_result(false, [], str(rr.get("error", "Re-roll failed")))
		var new_wounds = int(rr.get("wounds_caused", 0))
		# Rebuild the pending save list (may now have more/fewer wounds).
		if new_wounds > 0:
			var sd = rr.get("save_data", {})
			# Preserve the sequence context stamped later by _finish_weapon_resolution.
			resolution_state.staged_save_data_list = [sd]
		else:
			resolution_state.staged_save_data_list = []
		emit_signal("dice_rolled", {"context": "reroll_note",
			"message": "%s: wound die %d → %d" % [reroll_source, rr.get("old_value", 0), rr.get("new_value", 0)]})
		emit_signal("dice_rolled", rr.get("dice_block", {}))
		_replace_staged_dice_block("to_wound", rr.get("dice_block", {}))
		emit_signal("shooting_stage_paused", "wounds", {
			"reroll_available": false,
			"wound_rolls": rr.get("wound_context", {}).get("wound_rolls", []),
			"die_evals": rr.get("wound_context", {}).get("wound_evals", []),
			"wounds": new_wounds,
			"modifier_ledger": rr.get("wound_context", {}).get("modifier_ledger", [])
		})
		return create_result(true, cus11e_pt_diffs, "Wound die re-rolled", {
			"staged_pause": "wounds", "reroll_used": true, "reroll_available": false,
			"dice_block": rr.get("dice_block", {}), "wounds": new_wounds
		})

func _validate_staged_continue(action: Dictionary) -> Dictionary:
	var t = action.get("type", "")
	if t == "CONTINUE_TO_WOUNDS":
		if resolution_state.get("stage", "") != "hits_pending":
			return {"valid": false, "errors": ["Not awaiting continue-to-wounds"]}
	elif t == "CONTINUE_TO_SAVES":
		if resolution_state.get("stage", "") != "wounds_pending":
			return {"valid": false, "errors": ["Not awaiting continue-to-saves"]}
	elif t == "USE_SHOOTING_REROLL":
		var stage = str(action.get("payload", {}).get("stage", ""))
		var expected = "hits_pending" if stage == "hits" else ("wounds_pending" if stage == "wounds" else "")
		if expected == "" or resolution_state.get("stage", "") != expected:
			return {"valid": false, "errors": ["No re-roll available at this stage"]}
	elif t == "FAST_FINISH_SHOOTING":
		if resolution_state.get("stage", "") not in ["hits_pending", "wounds_pending"]:
			return {"valid": false, "errors": ["Nothing to fast-finish"]}
	return {"valid": true, "errors": []}

func _process_fast_finish_shooting(_action: Dictionary) -> Dictionary:
	# "Fast Roll" from a staged pause: resolve the remaining step(s) of the current
	# weapon without further pausing. From the hit pause this rolls the wound roll
	# and hands straight off to saving throws; from the wound pause it hands off to
	# saving throws directly. Everything after saves is unchanged.
	if resolution_state.get("mode", "") != "sequential_staged":
		return create_result(false, [], "Not in staged resolution")
	var stage = resolution_state.get("stage", "")
	if stage == "hits_pending":
		return _staged_continue_to_wounds(false)
	elif stage == "wounds_pending":
		return _staged_continue_to_saves()
	return create_result(false, [], "Nothing to fast-finish")


# T5-MP4-RELIABILITY: Save broadcast identity helpers
#
# Each batch of save_data emitted via `saves_required` carries a unique
# `save_broadcast_id` so the defender's controller (and the attacker's retry
# logic) can dedupe re-emissions and match acknowledgments precisely. Without
# the id, the existing dedupe falls back to (target_unit_id + weapon_name),
# which is ambiguous when the same weapon hits the same target across multiple
# rounds or after a retry. The id is `<msec_timestamp>-<monotonic-counter>` so
# it sorts naturally and is unique per broadcast even within the same tick.

static var _save_broadcast_counter: int = 0

static func _generate_save_broadcast_id() -> String:
	_save_broadcast_counter += 1
	return "sbid-%d-%d" % [Time.get_ticks_msec(), _save_broadcast_counter]

static func _stamp_save_broadcast_id(save_data_list: Array, broadcast_id: String) -> void:
	# Mutate each entry in-place so both the locally-emitted signal and the
	# returned result["save_data_list"] carry the same id. Caller passes the
	# id it has already generated so the same value flows into logs.
	for save_data in save_data_list:
		# Don't overwrite an existing id (retry path re-uses the same id).
		if save_data.get("save_broadcast_id", "") == "":
			save_data["save_broadcast_id"] = broadcast_id

# Helper Methods

func _is_unit_destroyed(unit_id: String) -> bool:
	"""Check if a target unit has been fully destroyed (all models dead)."""
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return true
	var models = unit.get("models", [])
	if models.is_empty():
		return true
	for model in models:
		if model.get("alive", true):
			return false
	return true

func _can_unit_shoot(unit: Dictionary) -> bool:
	var status = unit.get("status", 0)
	var flags = unit.get("flags", {})
	var unit_name = unit.get("meta", {}).get("name", unit.get("id", "?"))
	DebugLogger.info(str("ShootingPhase: _can_unit_shoot(%s) — status=%s, destroyed=%s, embarked=%s, has_shot=%s, advanced=%s" % [unit_name, str(status), str(_is_unit_destroyed_check(unit)), str(unit.get("embarked_in", null)), str(flags.get("has_shot", false)), str(flags.get("advanced", false))]))

	# Check if unit is destroyed (all models dead)
	if _is_unit_destroyed_check(unit):
		return false

	# Check if unit is embarked (can't shoot directly, only through transport's firing deck)
	if unit.get("embarked_in", null) != null:
		return false

	# Check if unit is deployed
	if status != GameStateData.UnitStatus.DEPLOYED and status != GameStateData.UnitStatus.MOVED:
		DebugLogger.info(str("ShootingPhase: _can_unit_shoot(%s) — REJECTED: status %s is not DEPLOYED(%d) or MOVED(%d)" % [unit_name, str(status), GameStateData.UnitStatus.DEPLOYED, GameStateData.UnitStatus.MOVED]))
		return false

	# Check if unit has already shot
	if flags.get("has_shot", false):
		return false

	# Issue #383: removed 9e-carryover "battle-shocked cannot shoot" check.
	# 10e Battle-shock effects are: OC=0, Desperate Escape on Fall Back,
	# no stratagem use/target. Cannot-shoot is NOT a battle-shock effect.

	# ASSAULT RULES: Units that Advanced can shoot with Assault weapons ONLY
	# Check this BEFORE cannot_shoot flag since Advanced units CAN shoot (with restrictions)
	# EXCEPTION: Units with advance_and_shoot effect can shoot with ALL weapons after Advancing
	if flags.get("advanced", false):
		if EffectPrimitivesData.has_effect_advance_and_shoot(unit) \
				or FactionAbilityManager.unit_has_detachment_assault(unit):
			DebugLogger.info(str("ShootingPhase: Unit %s advanced but has advance_and_shoot effect — eligible to shoot with all weapons" % unit.get("id", "unknown")))
		else:
			# Unit advanced - can only shoot if it has Assault weapons
			# (Codex: Adeptus Custodes ADVANCED STABILISERS gives a GRAV-ASSAULT
			# unit's ranged weapons [ASSAULT] — CustodesCodex11e.gd).
			return _unit_has_assault_weapons(unit) or _cus11e_codex().may_select_advanced_unit_to_shoot(unit)

	# Units that Fell Back cannot shoot (unless special rules — the
	# fall_back_and_shoot effect or Kult of Speed's Adrenaline Junkies)
	if flags.get("fell_back", false):
		if not EffectPrimitivesData.has_effect_fall_back_and_shoot(unit) \
				and not FactionAbilityManager.unit_has_adrenaline_junkies(unit):
			return false
		else:
			DebugLogger.info(str("ShootingPhase: Unit %s fell back but has fall_back_and_shoot effect — eligible to shoot" % unit.get("id", "unknown")))

	# Check other restriction flags (but skip for advanced units handled above)
	# fall_back_and_shoot effect (e.g., MULTIPOTENTIALITY) overrides the cannot_shoot lockout from Fall Back
	if flags.get("cannot_shoot", false):
		if flags.get("fell_back", false) and (EffectPrimitivesData.has_effect_fall_back_and_shoot(unit) \
				or FactionAbilityManager.unit_has_adrenaline_junkies(unit)):
			DebugLogger.info(str("ShootingPhase: Unit %s fell back but has fall_back_and_shoot effect — overriding cannot_shoot" % unit.get("id", "unknown")))
		else:
			return false

	# Check if this is a transport with firing deck capability
	if unit.has("transport_data") and unit.transport_data.get("firing_deck", 0) > 0:
		# Transport with firing deck can shoot if it has embarked units
		if unit.transport_data.get("embarked_units", []).size() > 0:
			# Check if any embarked unit hasn't shot yet
			for embarked_id in unit.transport_data.embarked_units:
				var embarked = get_unit(embarked_id)
				if embarked and not embarked.get("flags", {}).get("has_shot", false):
					return true  # Transport can use firing deck

	# Check if unit is in engagement range - units in engagement can ONLY shoot with Pistols (10e rules)
	# EXCEPTION: Big Guns Never Tire - Monsters/Vehicles can shoot with any weapon at -1 to hit
	if flags.get("in_engagement", false):
		# Check for Pistol weapons (any unit can shoot Pistols in engagement)
		if _unit_has_pistol_weapons(unit):
			return true

		# Check for Big Guns Never Tire (Monsters/Vehicles can shoot any weapon)
		if RulesEngine.is_monster_or_vehicle(unit):
			return true

		# No valid shooting options while in engagement
		return false
	
	# Check if unit has any alive models
	var has_alive = false
	for model in unit.get("models", []):
		if model.get("alive", true):
			has_alive = true
			break
	
	return has_alive

func _has_eligible_targets(unit_id: String) -> bool:
	"""P3-96: Check if a unit has at least one eligible shooting target.
	Also returns true if the unit has Throat Slittas targets (alternative to shooting)."""
	# PERF-LOS: route through the cached first-match-only check — this is the hot
	# filter path that _refresh_unit_list() calls for every unit on every UI
	# refresh. It stops at the first eligible target instead of scanning them all.
	if _cached_has_eligible_target(unit_id):
		return true
	# Check for Throat Slittas alternative (mortal wounds within 9")
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr and ability_mgr.has_throat_slittas_ability(unit_id):
		var ts_targets = _get_throat_slittas_targets(unit_id)
		if not ts_targets.is_empty():
			return true
	return false

func unit_has_shooting_phase_activity(unit_id: String) -> bool:
	"""Whether a unit has a genuine reason to appear in the 'Select Shooter'
	list by default (the shooting UI's 'show only units that can shoot' filter).
	True when the unit can actually do something this phase:
	  ▪ it has an eligible shooting target (in range + line of sight, or a
	    Throat Slittas mortal-wound target), or
	  ▪ it can perform a secondary MISSION action from its current position
	    (Establish Locus, Deploy Homer, Plunder, …).
	A unit that could technically shoot but has no target in range/LoS and no
	mission action returns false and is hidden unless the player enables
	'Show all units'. Already-shot units and the active shooter are handled
	separately by the controller and always remain listed."""
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return false
	# Gate: the unit must at least be able to participate this phase (alive,
	# deployed, hasn't shot, not embarked — and, for Advanced units, able to
	# shoot with Assault weapons or act via Favoured Conservai).
	if not _can_unit_perform_action(unit):
		return false
	# Can it shoot at something right now?
	if _has_eligible_targets(unit_id):
		return true
	# Does it have a mission action available at its current position?
	if not _get_secondary_action_options(unit_id).is_empty():
		return true
	return false

func _unit_has_pistol_weapons(unit: Dictionary) -> bool:
	"""Check if unit has any Pistol weapons (used for engagement range shooting)"""
	# Find the unit_id by searching through game state units
	var units = game_state_snapshot.get("units", {})
	for unit_id in units:
		if units[unit_id] == unit:
			return RulesEngine.unit_has_pistol_weapons(unit_id, game_state_snapshot)

	# Fallback: search by matching models array reference
	for unit_id in units:
		var u = units[unit_id]
		if u.get("models", []) == unit.get("models", []):
			return RulesEngine.unit_has_pistol_weapons(unit_id, game_state_snapshot)

	return false

func _unit_has_assault_weapons(unit: Dictionary) -> bool:
	"""Check if unit has any Assault weapons (used for shooting after Advancing)"""
	# Find the unit_id by searching through game state units
	var units = game_state_snapshot.get("units", {})
	for unit_id in units:
		if units[unit_id] == unit:
			return RulesEngine.unit_has_assault_weapons(unit_id, game_state_snapshot)

	# Fallback: search by matching models array reference
	for unit_id in units:
		var u = units[unit_id]
		if u.get("models", []) == unit.get("models", []):
			return RulesEngine.unit_has_assault_weapons(unit_id, game_state_snapshot)

	return false

# ============================================================================
# REACTIVE STRATAGEM SUPPORT (Go to Ground, Smokescreen)
# ============================================================================

# T3-3: Auto-inject Extra Attacks ranged weapons that aren't already in confirmed_assignments
# Extra Attacks weapons are used IN ADDITION to other weapons, not instead of them.
func _auto_inject_extra_attacks_weapons_shooting() -> void:
	if active_shooter_id.is_empty():
		return

	var unit = get_unit(active_shooter_id)
	if unit.is_empty():
		return

	var weapons_data = unit.get("meta", {}).get("weapons", [])

	# Find Extra Attacks ranged weapons
	var ea_weapons = []
	for weapon in weapons_data:
		if weapon.get("type", "").to_lower() != "melee":
			if RulesEngine.weapon_data_has_extra_attacks(weapon):
				ea_weapons.append(weapon)

	if ea_weapons.is_empty():
		return

	# Check which EA weapons are already assigned
	var assigned_weapon_ids = {}
	for assignment in confirmed_assignments:
		assigned_weapon_ids[assignment.get("weapon_id", "")] = true

	# Determine default target: use first confirmed assignment's target
	var default_target = ""
	if not confirmed_assignments.is_empty():
		default_target = confirmed_assignments[0].get("target_unit_id", "")

	for weapon in ea_weapons:
		var weapon_name = weapon.get("name", "Unknown")
		var weapon_id = RulesEngine.generate_weapon_id(weapon_name, weapon.get("type", ""))

		if assigned_weapon_ids.has(weapon_id):
			DebugLogger.info(str("[ShootingPhase] T3-3: Extra Attacks weapon '%s' already assigned, skipping" % weapon_name))
			continue

		if default_target.is_empty():
			DebugLogger.info(str("[ShootingPhase] T3-3: No target available for Extra Attacks weapon '%s'" % weapon_name))
			continue

		confirmed_assignments.append({
			"weapon_id": weapon_id,
			"target_unit_id": default_target,
			"model_ids": []
		})
		DebugLogger.info(str("[ShootingPhase] T3-3: Auto-injected Extra Attacks weapon '%s' → '%s'" % [weapon_name, default_target]))

	log_phase_message("T3-3: Extra Attacks weapons auto-included for %s" % active_shooter_id)

func _check_reactive_stratagems() -> Dictionary:
	"""
	Check if the defending player has reactive stratagems available for the current targets.
	Returns { has_opportunities: bool, defending_player: int, available_stratagems: Array, target_unit_ids: Array }
	"""
	var active_player = get_current_player()
	var defending_player = 2 if active_player == 1 else 1

	# Collect unique target unit IDs from confirmed assignments
	var target_unit_ids = []
	for assignment in confirmed_assignments:
		var target_id = assignment.get("target_unit_id", "")
		if target_id != "" and target_id not in target_unit_ids:
			target_unit_ids.append(target_id)

	if target_unit_ids.is_empty():
		return {"has_opportunities": false}

	# "Decline — don't offer again this phase" (design §3.1): the defender's
	# reactive dialog IS the enemy_targets_unit_shooting window, so it honours
	# the same per-phase suppression as every BasePhase window.
	if _window_suppressed.has("%d:enemy_targets_unit_shooting" % defending_player):
		DebugLogger.info("ShootingPhase: reactive stratagems for P%d suppressed (\"don't offer again this phase\")" % defending_player)
		return {"has_opportunities": false}

	# Ask StratagemManager for available reactive stratagems (core + legacy
	# faction reactives + the enemy_targets_unit_shooting window offers)
	var available = StratagemManager.get_reactive_stratagems_for_shooting(defending_player, target_unit_ids,
		{"attacker_unit_id": active_shooter_id})
	available = _filter_reactive_entries_usable(defending_player, available)

	if available.is_empty():
		DebugLogger.info(str("ShootingPhase: No reactive stratagems available for defender (player %d)" % defending_player))
		return {"has_opportunities": false}

	DebugLogger.info(str("ShootingPhase: %d reactive stratagem(s) available for defender (player %d)" % [available.size(), defending_player]))
	for entry in available:
		DebugLogger.info(str("  - %s: eligible units = %s" % [entry.stratagem.name, str(entry.eligible_units)]))

	return {
		"has_opportunities": true,
		"defending_player": defending_player,
		"available_stratagems": available,
		"target_unit_ids": target_unit_ids
	}

## Drop reactive entries / eligible units the defender cannot actually use
## right now: the core list is built with a target-less can_use_stratagem, so
## a unit already targeted by a stratagem this phase (11e 15.01), a
## battle-shocked unit, or a stratagem already used this phase (once per
## phase) would otherwise be offered and then refused on click. This is what
## lets the dialog re-open after a use with only what is still legal (a core
## AND a codex stratagem on the same targeting, each on a different unit).
func _filter_reactive_entries_usable(defending_player: int, available: Array) -> Array:
	var out: Array = []
	for entry in available:
		var sid := str(entry.get("stratagem", {}).get("id", ""))
		if entry.has("window_id"):
			# Window offers were already re-checked unit by unit with their
			# window context by StratagemManager.get_window_offers.
			out.append(entry)
			continue
		var units: Array = []
		for uid in entry.get("eligible_units", []):
			if StratagemManager.can_use_stratagem(defending_player, sid, str(uid)).get("can_use", false):
				units.append(uid)
		if units.is_empty():
			continue
		var kept: Dictionary = entry.duplicate()
		kept["eligible_units"] = units
		out.append(kept)
	return out

## After a reactive stratagem was used: re-open the defender's dialog when
## another stratagem is still usable on this targeting (each stratagem once
## per phase, each on a different unit — 15.01). Returns the paused result
## (stamped like CONFIRM_TARGETS so NetworkManager mirrors it), or {} when
## nothing is left and the attack should resolve.
func _reopen_reactive_window_if_offers(prefix_diffs: Array) -> Dictionary:
	var again = _check_reactive_stratagems()
	if not again.get("has_opportunities", false):
		return {}
	awaiting_reactive_stratagem = true
	log_phase_message("Defender may use another reactive stratagem (%d still available)" % again.available_stratagems.size())
	emit_signal("reactive_stratagem_opportunity", again.defending_player, again.available_stratagems, again.target_unit_ids)
	return create_result(true, prefix_diffs, "Awaiting defender stratagem decision", {
		"reactive_stratagem_opportunity": true,
		"defending_player": again.defending_player,
		"available_stratagems": again.available_stratagems,
		"target_unit_ids": again.target_unit_ids
	})

func _validate_use_reactive_stratagem(action: Dictionary) -> Dictionary:
	"""Validate using a reactive stratagem during opponent's shooting."""
	if not awaiting_reactive_stratagem:
		return {"valid": false, "errors": ["Not waiting for reactive stratagem decision"]}

	var stratagem_id = action.get("stratagem_id", "")
	var target_unit_id = action.get("target_unit_id", "")

	if stratagem_id == "":
		return {"valid": false, "errors": ["Missing stratagem_id"]}
	if target_unit_id == "":
		return {"valid": false, "errors": ["Missing target_unit_id"]}

	# Validate through StratagemManager
	var active_player = get_current_player()
	var defending_player = 2 if active_player == 1 else 1
	var validation = StratagemManager.can_use_stratagem(defending_player, stratagem_id, target_unit_id,
		_reactive_window_context(action))

	if not validation.can_use:
		return {"valid": false, "errors": [validation.reason]}

	return {"valid": true, "errors": []}

func _validate_decline_reactive_stratagem(action: Dictionary) -> Dictionary:
	"""Validate declining to use a reactive stratagem."""
	if not awaiting_reactive_stratagem:
		return {"valid": false, "errors": ["Not waiting for reactive stratagem decision"]}
	return {"valid": true, "errors": []}

func _reactive_window_context(action: Dictionary) -> Dictionary:
	"""Context for a USE_REACTIVE_STRATAGEM. Window stratagems folded into the
	defender's dialog (timing.windows has enemy_targets_unit_shooting — design
	§3.1) need context.window_id plus the window keys; the action may carry the
	dialog's variant/secondary picks in action.context. Core / legacy reactive
	stratagems get the same empty context as before."""
	var ctx: Dictionary = {}
	var action_ctx = action.get("context", {})
	if typeof(action_ctx) == TYPE_DICTIONARY:
		ctx = action_ctx.duplicate(true)
	var strat = StratagemManager.get_stratagem(str(action.get("stratagem_id", "")))
	var windows = strat.get("timing", {}).get("windows", [])
	# WP-S4: the Space Wolves STORM CALLER card has no stratagem row — it is a window offer too.
	# WP-M4a: + the Codex: Space Marines SHROUDING card (Librarian in Phobos Armour).
	if "enemy_targets_unit_shooting" in windows or _sw11e_abilities().handles_id(str(action.get("stratagem_id", ""))) \
			or _sm11e_abilities_a().handles_id(str(action.get("stratagem_id", ""))):
		var target_ids: Array = []
		for assignment in confirmed_assignments:
			var tid = str(assignment.get("target_unit_id", ""))
			if tid != "" and not tid in target_ids:
				target_ids.append(tid)
		ctx["window_id"] = "enemy_targets_unit_shooting"
		ctx["phase"] = "shooting"
		ctx["attacker_unit_id"] = active_shooter_id
		ctx["target_unit_ids"] = target_ids
	return ctx

func _process_use_reactive_stratagem(action: Dictionary) -> Dictionary:
	"""Process the defender using a reactive stratagem (Go to Ground / Smokescreen)."""
	var stratagem_id = action.get("stratagem_id", "")
	var target_unit_id = action.get("target_unit_id", "")
	var active_player = get_current_player()
	var defending_player = 2 if active_player == 1 else 1

	# Use the stratagem via StratagemManager (deducts CP, records usage, applies effects)
	var result = StratagemManager.use_stratagem(defending_player, stratagem_id, target_unit_id,
		_reactive_window_context(action))

	if not result.success:
		return create_result(false, [], result.get("error", "Stratagem use failed"))

	# Refresh game state snapshot so RulesEngine sees the new flags
	game_state_snapshot = GameState.create_snapshot()

	# Clear awaiting state and continue to resolution
	awaiting_reactive_stratagem = false
	log_phase_message("Player %d used %s on %s" % [defending_player, StratagemManager.get_stratagem(stratagem_id).get("name", result.get("stratagem_name", stratagem_id)), target_unit_id])

	# More than one reactive stratagem per targeting (e.g. a core one AND a
	# codex one): while another is still usable, the defender's dialog
	# re-opens and the attack waits (resolution_state is kept as is).
	var reopened := _reopen_reactive_window_if_offers(result.get("diffs", []))
	if not reopened.is_empty():
		reopened["stratagem_used"] = {
			"stratagem_id": stratagem_id,
			"stratagem_name": StratagemManager.get_stratagem(stratagem_id).get("name", result.get("stratagem_name", stratagem_id)),
			"target_unit_id": target_unit_id,
			"player": defending_player
		}
		return reopened

	# Continue shooting resolution (AI atomic attacks resume their own path)
	var continue_result: Dictionary
	if resolution_state.get("ai_atomic", false):
		var stored_ai_action: Dictionary = resolution_state.get("ai_action", {})
		resolution_state = {}
		continue_result = _resolve_ai_shoot(stored_ai_action)
	else:
		continue_result = _continue_after_reactive_stratagems()

	# Merge diffs
	var all_diffs = result.get("diffs", [])
	if continue_result.success:
		all_diffs.append_array(continue_result.get("changes", []))

	# Build combined result
	var combined = create_result(true, all_diffs)
	# Copy over all extra fields from the continue result
	for key in continue_result:
		if key != "success" and key != "changes" and key != "phase" and key != "timestamp":
			combined[key] = continue_result[key]

	combined["stratagem_used"] = {
		"stratagem_id": stratagem_id,
		"stratagem_name": StratagemManager.get_stratagem(stratagem_id).get("name", result.get("stratagem_name", stratagem_id)),
		"target_unit_id": target_unit_id,
		"player": defending_player
	}

	return combined

func _process_decline_reactive_stratagem(action: Dictionary) -> Dictionary:
	"""Process the defender declining to use any reactive stratagem."""
	awaiting_reactive_stratagem = false
	log_phase_message("Defender declined reactive stratagems")
	# "Decline — don't offer again this phase": same suppression key as the
	# BasePhase window of the same id (enemy_targets_unit_shooting).
	if bool(action.get("dont_offer_again", false)):
		var dont_player := 2 if get_current_player() == 1 else 1
		_window_suppressed["%d:enemy_targets_unit_shooting" % dont_player] = true
		log_phase_message("[StratagemWindow] P%d declined enemy_targets_unit_shooting — not offered again this phase" % dont_player)

	# Continue shooting resolution (AI atomic attacks resume their own path)
	if resolution_state.get("ai_atomic", false):
		var stored_ai_action: Dictionary = resolution_state.get("ai_action", {})
		resolution_state = {}
		return _resolve_ai_shoot(stored_ai_action)
	return _continue_after_reactive_stratagems()

# ============================================================================
# CODEX: ORKS (11e) — post-shot windows + opponent-Shooting follow-ups
# (design .llm/ork_codex_11e_design.md §3 / §3.2; OrkCodexShootingReactive.gd)
# ============================================================================
#  unit_has_shot  — decider: active player; ctx {unit_id}
#  enemy_has_shot — decider: non-active player; ctx {attacker_unit_id,
#                   hit_unit_ids, wounded_unit_ids (lost >= 1 wound)}
# Both open (active player's first — 01.03.02 rules sequencing) from
# process_action() after ANY action that completed a shooter's activation
# (single weapon / sequential / staged / atomic AI SHOOT …) — one hook
# instead of one per completion branch. They wait while a reactive window or
# a save batch is still open, and open once it resolves. They do NOT wait for the legacy
# Swift as the Eagle / Go Get 'Em! / Wazblasta prompts (AI-only, no human UI):
# the window opens first (01.03.02 — the active player's triggers resolve
# first) and blocks every other action, and the legacy prompt stays pending
# behind it.
# Follow-ups (design §3.2) executed here:
#  reactive_normal_move (GRAB IT) / surge_move (GOADED INTO ACTION) — judged by
#    ReactiveMove11e (09.05 / 21.02 with the engine's SurgeMove template). A
#    human decider stages the move through the ORK11E_REACTIVE_MOVE_* actions
#    (ShootingController's move panel: drag the unit / Auto-move / Re-roll /
#    Reset / Don't move / Confirm); an AI decider is auto-placed synchronously.
#  shoot (GUN-CRAZY SHOW-OFFS) — AUTO-RESOLVED normal shooting: every ranged
#    weapon of the unit that can target the forced enemy unit (one profile per
#    weapon, the best one against that target) fires at it through
#    RulesEngine.resolve_shoot; saves are rolled automatically (no
#    weapon-assignment UI for a shooter that is not the active player's).

const ReactiveMove11eLib = preload("res://scripts/rules/ReactiveMove11e.gd")

signal ork11e_reactive_move_started(info: Dictionary)
signal ork11e_reactive_move_updated(info: Dictionary)
signal ork11e_reactive_move_ended(info: Dictionary)

## Actions that add the unit to units_that_shot WITHOUT it having shot.
const _ORK11E_NOT_SHOOTING_ACTIONS := ["SKIP_UNIT", "PERFORM_SECONDARY_ACTION", "START_ACTION",
	"BURN_OBJECTIVE", "PERFORM_RITUAL_ACTION", "PERFORM_TERRAFORM_ACTION",
	"USE_THROAT_SLITTAS", "USE_GRENADE_STRATAGEM", "END_SHOOTING"]

var _ork11e_pre_shot_wounds: Dictionary = {}  # enemy unit_id -> wounds left when the shooter was selected
# WP-M4c GLORY OF ULTRAMAR: alive models per unit before the shot ("a model in this unit was destroyed by those attacks").
var _sm11e_pre_shot_alive: Dictionary = {}
var _ork11e_shot_dice_start: int = 0          # dice_log index when the shooter was selected
var _ork11e_shot_hits: Dictionary = {}        # target_unit_id -> hits (staged path, after re-rolls)
var _ork11e_post_shot_queue: Array = []       # shooters whose post-shot windows are still to open
var _ork11e_followup: Dictionary = {}         # human reactive move in progress (see _ork11e_start_reactive_move)

func _ork11e_unit_wounds(unit: Dictionary) -> int:
	var total := 0
	for m in unit.get("models", []):
		if m.get("alive", true):
			total += int(m.get("current_wounds", m.get("wounds", 1)))
	return total

func _ork11e_begin_shot_tracking(shooter_id: String) -> void:
	_ork11e_shot_dice_start = dice_log.size()
	_ork11e_shot_hits.clear()
	_ork11e_pre_shot_wounds.clear()
	_sm11e_pre_shot_alive.clear()  # WP-M4c
	var shooter_owner := int(get_unit(shooter_id).get("owner", get_current_player()))
	var units: Dictionary = GameState.state.get("units", {})
	for uid in units:
		if int(units[uid].get("owner", 0)) != shooter_owner:
			_ork11e_pre_shot_wounds[uid] = _ork11e_unit_wounds(units[uid])
			_sm11e_pre_shot_alive[uid] = units[uid].get("models", []).filter(func(m): return m.get("alive", true)).size()  # WP-M4c

func _ork11e_note_hits(target_unit_id: String, hits: int) -> void:
	if target_unit_id != "" and hits > 0:
		_ork11e_shot_hits[target_unit_id] = int(_ork11e_shot_hits.get(target_unit_id, 0)) + hits

## hit_unit_ids: every unit a hit roll of those attacks hit (dice blocks carry
## target_unit_id); wounded_unit_ids: every enemy unit with fewer wounds left
## than when the shooter was selected.
func _ork11e_post_shot_ctx(shooter_id: String) -> Dictionary:
	var hit := {}
	for i in range(mini(_ork11e_shot_dice_start, dice_log.size()), dice_log.size()):
		var db = dice_log[i]
		if typeof(db) != TYPE_DICTIONARY:
			continue
		var c := str(db.get("context", ""))
		if (c == "to_hit" or c == "hit_roll" or c == "auto_hit") and int(db.get("successes", 0)) > 0:
			var tid := str(db.get("target_unit_id", ""))
			if tid != "":
				hit[tid] = true
	for tid in _ork11e_shot_hits:
		hit[tid] = true
	var wounded: Array = []
	for uid in _ork11e_pre_shot_wounds:
		var u = GameState.get_unit(uid)
		if not u.is_empty() and _ork11e_unit_wounds(u) < int(_ork11e_pre_shot_wounds[uid]):
			wounded.append(uid)
	# Codex: Space Marines (11e) Space Wolves IMPETUOSITY / BATTLE INSTINCTS
	# (SWCodex11e.gd): "an enemy unit that TARGETED a friendly unit has shot" —
	# every unit a hit roll of those attacks was made against (hit or not).
	var targeted := hit.duplicate()
	# WP-M4b SUPPRESSION FIRE (Codex: Space Marines 11e, Astraeus): "an enemy unit
	# hit by this model's Twin Macro-accelerator Cannon" — the units hit, per weapon.
	var hit_by_weapon := {}
	for j in range(mini(_ork11e_shot_dice_start, dice_log.size()), dice_log.size()):
		var tb = dice_log[j]
		if typeof(tb) == TYPE_DICTIONARY and str(tb.get("target_unit_id", "")) != "":
			targeted[str(tb.get("target_unit_id", ""))] = true
			if str(tb.get("weapon_id", "")) != "" and int(tb.get("successes", 0)) > 0:
				var hw: Array = hit_by_weapon.get(str(tb.weapon_id), [])
				if not str(tb.target_unit_id) in hw:
					hw.append(str(tb.target_unit_id))
				hit_by_weapon[str(tb.weapon_id)] = hw
	# WP-M4c GLORY OF ULTRAMAR (Victrix Honour Guard): units that lost a model to those attacks.
	var destroyed: Array = []
	for duid in _sm11e_pre_shot_alive:
		var du = GameState.get_unit(duid)
		if not du.is_empty() and du.get("models", []).filter(func(m): return m.get("alive", true)).size() < int(_sm11e_pre_shot_alive[duid]):
			destroyed.append(duid)
	return {"hit_unit_ids": hit.keys(), "wounded_unit_ids": wounded, "targeted_unit_ids": targeted.keys(), "hit_by_weapon": hit_by_weapon, "models_destroyed_unit_ids": destroyed, "destroyed_unit_ids": destroyed}  # WP-M4c Glory of Ultramar / WP-M3b HAIL OF VENGEANCE

func _ork11e_queue_post_shot(a_type: String, shot_before: int, result: Dictionary) -> void:
	if a_type in _ORK11E_NOT_SHOOTING_ACTIONS or result.get("throat_slittas", false):
		return
	if units_that_shot.size() <= shot_before:
		return
	var active := get_current_player()
	for i in range(shot_before, units_that_shot.size()):
		var sid := str(units_that_shot[i])
		if int(get_unit(sid).get("owner", 0)) == active and not sid in _ork11e_post_shot_queue:
			_ork11e_post_shot_queue.append(sid)
			DebugLogger.info("ShootingPhase: [StratagemWindow] %s completed its shooting (%s) — post-shot windows queued" % [sid, a_type])

func _ork11e_post_shot_blocked() -> bool:
	return has_pending_stratagem_window() or _window_followup_pending or not _ork11e_followup.is_empty() \
		or awaiting_reactive_stratagem or not pending_save_data.is_empty()

## Open the post-shot windows for every queued shooter (result = the result of
## the action that completed the activation; window/AI diffs are merged in).
func _ork11e_run_post_shot_windows(result: Dictionary) -> Dictionary:
	if _ork11e_post_shot_queue.is_empty():
		return result
	if _ork11e_post_shot_blocked():
		DebugLogger.info("ShootingPhase: [StratagemWindow] post-shot windows for %s deferred (window=%s followup=%s/%s reactive=%s saves=%d)" % [
			str(_ork11e_post_shot_queue), str(has_pending_stratagem_window()), str(_window_followup_pending),
			str(not _ork11e_followup.is_empty()), str(awaiting_reactive_stratagem), pending_save_data.size()])
		return result
	# Offers (wounds lost, unengaged, still on the battlefield …) are judged on
	# the state AFTER this action: apply its changes now — idempotent 'set'
	# diffs, the same early apply Swift as the Eagle / Wazblasta rely on.
	var changes: Array = result.get("changes", [])
	if not changes.is_empty():
		PhaseManager.apply_state_changes(changes)
	var merged: Array = changes.duplicate()
	while not _ork11e_post_shot_queue.is_empty():
		var shooter_id := str(_ork11e_post_shot_queue.pop_front())
		# Codex: Orks (11e) "when this unit has attacked" (WP-O34): Try Dat Button!'s
		# two-dice hazard roll; its effects and Unpredictable Genius's end.
		merged.append_array(Ork11eDetachments.on_unit_has_shot(shooter_id))
		var shot := _ork11e_post_shot_ctx(shooter_id)
		var active := get_current_player()
		var other := 2 if active == 1 else 1
		log_phase_message("[StratagemWindow] %s has shot — unit_has_shot (P%d) then enemy_has_shot (P%d); hit=%s wounded=%s" % [
			shooter_id, active, other, str(shot.hit_unit_ids), str(shot.wounded_unit_ids)])
		# Codex: Adeptus Custodes VIGIL UNENDING / IN AURAMITE CLAD end "until
		# that enemy unit has attacked" (CustodesCodex11e.gd).
		_cus11e_codex().on_unit_has_attacked(shooter_id)
		# Codex: Space Marines (11e) Space Wolves HEROIC RESOLVE ends "until that enemy unit has attacked" (SWCodex11e.gd).
		load("res://scripts/codex/space_wolves/SWCodex11e.gd").on_unit_has_attacked(shooter_id)
		# Codex: Space Marines (11e) ARMOUR OF CONTEMPT ends "until that enemy unit has attacked" (SMCodex11e.gd).
		load("res://scripts/codex/space_marines/SMCodex11e.gd").on_unit_has_attacked(shooter_id)
		# WP-M4b SPECIAL-ISSUE OPTICS (Codex: Space Marines 11e): its effects last "until this unit has shot".
		load("res://scripts/codex/space_marines/SMAbilitiesB.gd").on_unit_has_shot(shooter_id)
		# WP-O6: Codex: Orks (11e) "when this unit has shot, select one enemy
		# unit hit" abilities (Rokkit Barrage, Squig Barrage, Bust 'Em, Madcap
		# Artillery) resolve here when exactly one unit was hit; with 2+ hit
		# units they are offered in the unit_has_shot window below.
		merged.append_array(OrkAbilities11eScript.after_unit_shot(shooter_id, shot.hit_unit_ids))
		var paused := open_stratagem_windows([
			{"player": active, "window_id": "unit_has_shot", "ctx": {"phase": "shooting", "unit_id": shooter_id,
				"hit_unit_ids": shot.hit_unit_ids, "wounded_unit_ids": shot.wounded_unit_ids,
				"hit_by_weapon": shot.get("hit_by_weapon", {})}},  # WP-M4b: Suppression Fire
			{"player": other, "window_id": "enemy_has_shot", "ctx": {"phase": "shooting", "attacker_unit_id": shooter_id,
				"hit_unit_ids": shot.hit_unit_ids, "wounded_unit_ids": shot.wounded_unit_ids,
				"targeted_unit_ids": shot.targeted_unit_ids,  # targeted: Space Wolves IMPETUOSITY / BATTLE INSTINCTS
				"models_destroyed_unit_ids": shot.models_destroyed_unit_ids,  # WP-M4c Glory of Ultramar
				"destroyed_unit_ids": shot.get("destroyed_unit_ids", [])}}],  # WP-M3b HAIL OF VENGEANCE
			"_ork11e_resume_after_post_shot_windows", {"unit_id": shooter_id})
		merged.append_array(consume_window_diffs())
		if paused:
			break
	result["changes"] = merged
	return result

## Resume point of the post-shot windows (BasePhase framework): nothing else
## of the completed activation is left — open the next queued shooter's.
func _ork11e_resume_after_post_shot_windows(_ctx: Dictionary, _window_result: Dictionary) -> Dictionary:
	return _ork11e_run_post_shot_windows(create_result(true, []))

## USE/DECLINE_WINDOW_STRATAGEM bypass process_action (BasePhase handles them
## before subclass dispatch), but answering a window can complete a unit's
## shooting: a held atomic SHOOT (AI / "Shoot All Remaining") resumes inside
## the unit_selected_to_shoot window action. Queue + open the post-shot
## windows (unit_has_shot / enemy_has_shot) for it exactly as process_action
## does for every other action (framework F7).
func _process_window_action(action: Dictionary) -> Dictionary:
	var shot_before := units_that_shot.size()
	var result: Dictionary = super._process_window_action(action)
	if result.get("success", false):
		_ork11e_queue_post_shot(str(action.get("type", "")), shot_before, result)
		result = _ork11e_run_post_shot_windows(result)
	return result

## A human's reactive move keeps the AI attacker idle (AIPlayer reads this).
func get_pending_stratagem_window_decider() -> int:
	var decider := super.get_pending_stratagem_window_decider()
	if decider == 0 and not _ork11e_followup.is_empty():
		return int(_ork11e_followup.get("player", 0))
	return decider

func _execute_window_followup(player: int, window_id: String, followup: Dictionary, ctx: Dictionary) -> bool:
	match str(followup.get("type", "")):
		"reactive_normal_move":
			return _ork11e_start_reactive_move(player, "normal", followup)
		"surge_move":
			return _ork11e_start_reactive_move(player, "surge", followup)
		"shoot":
			_ork11e_forced_shoot(player, followup)
			return false
	return super._execute_window_followup(player, window_id, followup, ctx)

# --- reactive moves (GRAB IT / GOADED INTO ACTION) ---------------------------

func _ork11e_roll_d6() -> int:
	return int(RulesEngine.make_rng().roll_d6(1)[0])

func _ork11e_move_opts(fu: Dictionary) -> Dictionary:
	return {"end_condition": str(fu.get("end_condition", "")), "surge_target": str(fu.get("surge_target", "")),
		"reference": fu.get("reference", {})}

## Inches a surging unit needs to end engaged with its surge target.
func _ork11e_surge_needed_inches(fu: Dictionary) -> float:
	var best := INF
	for key in fu.get("origin", {}):
		var parts = str(key).rsplit(":", true, 1)
		var m = GameState.get_unit(parts[0]).get("models", [])[int(parts[1])]
		best = minf(best, ReactiveMove11eLib.model_to_unit_inches(m, str(fu.get("surge_target", "")), GameState.state))
	return maxf(0.0, best - GameConstants.engagement_range_inches())

func _ork11e_start_reactive_move(player: int, kind: String, followup: Dictionary) -> bool:
	var unit_id := str(followup.get("unit_id", ""))
	var fu := {"player": player, "kind": kind, "unit_id": unit_id, "source": str(followup.get("source", "Stratagem")),
		"origin": ReactiveMove11eLib.current_positions(unit_id, GameState.state),
		"max_inches": float(followup.get("max_inches", 0.0)), "end_condition": str(followup.get("end_condition", "")),
		"surge_target": "", "roll": 0, "reroll_allowed": bool(followup.get("reroll_allowed", false)),
		"rerolled": false, "reference": {}}
	var unit_name := GameState.get_unit_display_name(unit_id)
	if kind == "surge":
		fu.surge_target = ReactiveMove11eLib.surge_target(unit_id, GameState.state)
		fu.roll = _ork11e_roll_d6()
		fu.max_inches = float(fu.roll + int(followup.get("roll_bonus", 0)))  # WP-C7 Vengeful Surge: D6+2"
		var msg := "%s: %s rolls D6 = %d — surge move of up to %d\" toward %s" % [fu.source, unit_name, fu.roll, int(fu.max_inches),
			GameState.get_unit_display_name(fu.surge_target) if fu.surge_target != "" else "(no enemy unit)"]
		log_phase_message(msg)
		GameEventLog.add_player_entry(player, msg)
		if fu.surge_target == "":
			log_phase_message("%s: no surge target on the battlefield — no move" % fu.source)
			return false
	if _is_ai_window_decider(player):
		# AI: a riled-up unit re-rolls a surge roll too short to end engaged.
		if kind == "surge" and fu.reroll_allowed and float(fu.roll) < _ork11e_surge_needed_inches(fu):
			fu.roll = _ork11e_roll_d6()
			fu.max_inches = float(fu.roll)
			fu.rerolled = true
			var rmsg := "%s: %s is riled up — re-rolled the D6: %d" % [fu.source, unit_name, fu.roll]
			log_phase_message(rmsg)
			GameEventLog.add_player_entry(player, rmsg)
		var proposed := ReactiveMove11eLib.solve(kind, unit_id, fu.origin, fu.max_inches, _ork11e_move_opts(fu), GameState.state)
		if proposed.is_empty():
			log_phase_message("%s: %s — no legal placement found, the unit does not move" % [fu.source, unit_name])
			return false
		var ai_diffs := ReactiveMove11eLib.position_diffs(proposed)
		PhaseManager.apply_state_changes(ai_diffs)
		_window_sync_diffs.append_array(ai_diffs)
		var done_msg := "%s: %s made a %s move (up to %.0f\")" % [fu.source, unit_name, "surge" if kind == "surge" else "normal", fu.max_inches]
		log_phase_message(done_msg)
		GameEventLog.add_player_entry(player, done_msg)
		return false
	if kind == "surge":
		fu.reference = ReactiveMove11eLib.solve("surge", unit_id, fu.origin, fu.max_inches, {"surge_target": fu.surge_target}, GameState.state)
	_ork11e_followup = fu
	log_phase_message("%s: waiting for Player %d to make %s's %s move (up to %.0f\")" % [fu.source, player, unit_name, kind, fu.max_inches])
	emit_signal("ork11e_reactive_move_started", ork11e_reactive_move_info())
	return true

## The human's move in progress, for the move panel and scenarios.
func ork11e_reactive_move_info(positions: Dictionary = {}) -> Dictionary:
	if _ork11e_followup.is_empty():
		return {}
	var fu := _ork11e_followup
	var current: Dictionary = positions if not positions.is_empty() else ReactiveMove11eLib.current_positions(fu.unit_id, GameState.state)
	var moved := 0.0
	for key in fu.origin:
		if current.has(key):
			moved = maxf(moved, fu.origin[key].distance_to(current[key]) / 40.0)
	var check := ReactiveMove11eLib.validate(fu.kind, fu.unit_id, fu.origin, current, fu.max_inches, _ork11e_move_opts(fu), GameState.state)
	return {"player": fu.player, "kind": fu.kind, "unit_id": fu.unit_id,
		"unit_name": GameState.get_unit_display_name(fu.unit_id), "source": fu.source,
		"max_inches": fu.max_inches, "moved_inches": moved, "roll": fu.roll,
		"reroll_available": fu.kind == "surge" and fu.reroll_allowed and not fu.rerolled,
		"surge_target": fu.surge_target,
		"surge_target_name": GameState.get_unit_display_name(fu.surge_target) if fu.surge_target != "" else "",
		"end_condition": fu.end_condition, "valid": check.ok, "violations": check.violations,
		"translation": {"x": fu.translation.x, "y": fu.translation.y} if fu.has("translation") else {"x": 0.0, "y": 0.0}}

func _ork11e_validate_reactive_move_gate(action: Dictionary) -> Dictionary:
	var t := str(action.get("type", ""))
	if t.begins_with("ORK11E_REACTIVE_MOVE_"):
		if _ork11e_followup.is_empty():
			return {"valid": false, "errors": ["No reactive move is in progress"]}
		if action.has("player") and int(action.get("player", 0)) != int(_ork11e_followup.player):
			return {"valid": false, "errors": ["Player %d is making this move, not Player %d" % [int(_ork11e_followup.player), int(action.get("player", 0))]]}
		if t == "ORK11E_REACTIVE_MOVE_REROLL" and not (_ork11e_followup.kind == "surge" and _ork11e_followup.reroll_allowed and not _ork11e_followup.rerolled):
			return {"valid": false, "errors": ["The D6 cannot be re-rolled"]}
		if not t in ["ORK11E_REACTIVE_MOVE_STAGE", "ORK11E_REACTIVE_MOVE_AUTO", "ORK11E_REACTIVE_MOVE_RESET",
				"ORK11E_REACTIVE_MOVE_REROLL", "ORK11E_REACTIVE_MOVE_CONFIRM", "ORK11E_REACTIVE_MOVE_SKIP"]:
			return {"valid": false, "errors": ["Unknown action type: " + t]}
		return {"valid": true, "errors": []}
	if not _ork11e_followup.is_empty() and not t.begins_with("DEBUG_"):
		return {"valid": false, "errors": ["Waiting for Player %d to finish the %s move (%s)" % [
			int(_ork11e_followup.player), str(_ork11e_followup.kind), str(_ork11e_followup.source)]]}
	return {}

func _ork11e_positions_from(origin: Dictionary, translation: Vector2) -> Dictionary:
	var out := {}
	for key in origin:
		out[key] = origin[key] + translation
	return out

func _ork11e_process_reactive_move_action(action: Dictionary) -> Dictionary:
	var fu := _ork11e_followup
	var t := str(action.get("type", ""))
	var positions: Dictionary = {}
	match t:
		"ORK11E_REACTIVE_MOVE_STAGE":
			# Whole-unit drag: the formation is kept, the translation is
			# measured from where the unit started this move and clamped to the
			# maximum distance. (payload.model_positions stages per model.)
			var payload = action.get("payload", {})
			if payload.has("model_positions"):
				positions = fu.origin.duplicate()
				for key in payload.model_positions:
					if positions.has(key):
						var p = payload.model_positions[key]
						positions[key] = Vector2(float(p.get("x", 0)), float(p.get("y", 0)))
			else:
				var tr = payload.get("translation", {})
				var v := Vector2(float(tr.get("x", 0.0)), float(tr.get("y", 0.0)))
				var max_px := float(fu.max_inches) * 40.0
				if v.length() > max_px:
					v = v.normalized() * max_px
				fu.translation = v
				positions = _ork11e_positions_from(fu.origin, v)
		"ORK11E_REACTIVE_MOVE_AUTO":
			positions = ReactiveMove11eLib.solve(fu.kind, fu.unit_id, fu.origin, fu.max_inches, _ork11e_move_opts(fu), GameState.state)
			if positions.is_empty():
				return create_result(false, [], "%s: no legal placement found for %s — move it by hand or choose Don't move" % [fu.source, GameState.get_unit_display_name(fu.unit_id)])
		"ORK11E_REACTIVE_MOVE_RESET":
			fu.translation = Vector2.ZERO
			positions = fu.origin.duplicate()
		"ORK11E_REACTIVE_MOVE_REROLL":
			fu.roll = _ork11e_roll_d6()
			fu.max_inches = float(fu.roll)
			fu.rerolled = true
			fu.translation = Vector2.ZERO
			fu.reference = ReactiveMove11eLib.solve("surge", fu.unit_id, fu.origin, fu.max_inches, {"surge_target": fu.surge_target}, GameState.state)
			positions = fu.origin.duplicate()
			var rmsg := "%s: %s is riled up — re-rolled the D6: %d" % [fu.source, GameState.get_unit_display_name(fu.unit_id), fu.roll]
			log_phase_message(rmsg)
			GameEventLog.add_player_entry(int(fu.player), rmsg)
		"ORK11E_REACTIVE_MOVE_CONFIRM":
			var current := ReactiveMove11eLib.current_positions(fu.unit_id, GameState.state)
			var check := ReactiveMove11eLib.validate(fu.kind, fu.unit_id, fu.origin, current, fu.max_inches, _ork11e_move_opts(fu), GameState.state)
			if not check.ok:
				return create_result(false, [], "%s: %s" % [fu.source, "; ".join(check.violations)])
			return _ork11e_finish_reactive_move(ReactiveMove11eLib.position_diffs(current), true)
		"ORK11E_REACTIVE_MOVE_SKIP":
			return _ork11e_finish_reactive_move(ReactiveMove11eLib.position_diffs(fu.origin), false)
	var diffs := ReactiveMove11eLib.position_diffs(positions)
	var info := ork11e_reactive_move_info(positions)
	emit_signal("ork11e_reactive_move_updated", info)
	return create_result(true, diffs, "", {"ork11e_reactive_move": info})

func _ork11e_finish_reactive_move(diffs: Array, moved: bool) -> Dictionary:
	var fu := _ork11e_followup
	var unit_name := GameState.get_unit_display_name(fu.unit_id)
	var msg := "%s: %s %s" % [fu.source, unit_name, ("made its %s move" % fu.kind) if moved else "did not move"]
	log_phase_message(msg)
	GameEventLog.add_player_entry(int(fu.player), msg)
	var ended := {"player": fu.player, "unit_id": fu.unit_id, "source": fu.source, "moved": moved}
	_ork11e_followup = {}
	emit_signal("ork11e_reactive_move_ended", ended)
	var result := _finish_window_followup(diffs)
	result["ork11e_reactive_move_ended"] = ended
	return result

# --- GUN-CRAZY SHOW-OFFS: auto-resolved normal shooting at the forced target ---

func _ork11e_weapon_base_name(weapon_id: String, board: Dictionary) -> String:
	var wname := str(RulesEngine.get_weapon_profile(weapon_id, board).get("name", weapon_id))
	for sep in [" – ", " — ", " - "]:
		var idx := wname.find(sep)
		if idx > 0:
			return wname.substr(0, idx)
	return wname

func _ork11e_avg_value(v) -> float:
	var s := str(v).to_upper().replace(" ", "")
	if s.is_valid_float():
		return float(s)
	var plus := 0.0
	if "+" in s:
		var p := s.split("+")
		s = p[0]
		plus = float(p[1]) if p[1].is_valid_float() else 0.0
	var d := s.find("D")
	if d < 0:
		return plus
	var n := 1.0 if d == 0 else (float(s.substr(0, d)) if s.substr(0, d).is_valid_float() else 1.0)
	var faces := float(s.substr(d + 1)) if s.substr(d + 1).is_valid_float() else 6.0
	return n * (faces + 1.0) / 2.0 + plus

## Rough expected damage of one model firing `weapon_id` at the target — used
## only to pick ONE profile per weapon (e.g. Snazzgun – Cutta / Kill Shot).
func _ork11e_profile_value(weapon_id: String, target_id: String, board: Dictionary) -> float:
	var prof = RulesEngine.get_weapon_profile(weapon_id, board)
	var t := float(str(board.get("units", {}).get(target_id, {}).get("meta", {}).get("stats", {}).get("toughness", 4)))
	var s := float(str(prof.get("strength", 4))) if str(prof.get("strength", 4)).is_valid_float() else 4.0
	var p_wound := 3.0 / 6.0
	if s >= 2.0 * t:
		p_wound = 5.0 / 6.0
	elif s > t:
		p_wound = 4.0 / 6.0
	elif s * 2.0 <= t:
		p_wound = 1.0 / 6.0
	elif s < t:
		p_wound = 2.0 / 6.0
	var ap := absf(float(str(prof.get("ap", 0)))) if str(prof.get("ap", 0)).is_valid_float() else 0.0
	return _ork11e_avg_value(prof.get("attacks_raw", prof.get("attacks", 1))) * p_wound \
		* _ork11e_avg_value(prof.get("damage_raw", prof.get("damage", 1))) * (1.0 + 0.15 * ap)

## [CLOSE-QUARTERS] weapon (11e 24.07; [PISTOL] is identical for all rules
## purposes, 24.27) — the same predicate the 11e shooting types use.
func _ork11e_is_close_quarters_weapon(weapon_id: String, board: Dictionary) -> bool:
	if RulesEngine.is_pistol_weapon(weapon_id, board):
		return true
	var abilities: Array = AbilityRegistry.from_weapon(RulesEngine.get_weapon_profile(weapon_id, board))
	return AbilityRegistry.has_ability(abilities, "close_quarters") or AbilityRegistry.has_ability(abilities, "pistol")

func _ork11e_forced_shoot_assignments(unit_id: String, target_id: String, board: Dictionary) -> Array:
	# weapons_in_range already drops Hunter profiles the target cannot be
	# targeted by (04.01.03 — RulesEngine.weapon_profile_can_target).
	var in_range: Array = RulesEngine.get_eligible_targets(unit_id, board).get(target_id, {}).get("weapons_in_range", [])
	if in_range.is_empty():
		return []
	var unit_weapons: Dictionary = RulesEngine.get_unit_weapons(unit_id, board)
	var shooter_is_mv := RulesEngine.is_monster_or_vehicle(board.get("units", {}).get(unit_id, {}))
	var models_for := {}  # weapon_id -> [model ids]
	for model_id in unit_weapons:
		# Per weapon (base name), this model's best in-range profile (04.01.03:
		# one profile per weapon), kept separately for its [CLOSE-QUARTERS]
		# weapons and its other ranged weapons.
		var best_cq := {}     # base name -> weapon id
		var best_other := {}  # base name -> weapon id
		for wid in unit_weapons[model_id]:
			if not wid in in_range:
				continue
			var base := _ork11e_weapon_base_name(wid, board)
			var bucket: Dictionary = best_cq if _ork11e_is_close_quarters_weapon(wid, board) else best_other
			if not bucket.has(base) or _ork11e_profile_value(wid, target_id, board) > _ork11e_profile_value(bucket[base], target_id, board):
				bucket[base] = wid
		var chosen_ids: Array = []
		if shooter_is_mv:
			chosen_ids = best_cq.values() + best_other.values()
		else:
			# 24.07: a non-MONSTER/VEHICLE model using normal shooting fires
			# EITHER its [CLOSE-QUARTERS] weapons OR its other ranged weapons —
			# take whichever set is worth more against this target.
			var cq_value := 0.0
			for w in best_cq.values():
				cq_value += _ork11e_profile_value(w, target_id, board)
			var other_value := 0.0
			for w in best_other.values():
				other_value += _ork11e_profile_value(w, target_id, board)
			chosen_ids = best_other.values() if other_value >= cq_value and not best_other.is_empty() else best_cq.values()
		for chosen in chosen_ids:
			if not models_for.has(chosen):
				models_for[chosen] = []
			models_for[chosen].append(model_id)
	var assignments: Array = []
	for wid in models_for:
		assignments.append({"weapon_id": wid, "target_unit_id": target_id, "model_ids": models_for[wid]})
	return assignments

func _ork11e_forced_shoot(player: int, followup: Dictionary) -> void:
	var unit_id := str(followup.get("unit_id", ""))
	var target_id := str(followup.get("forced_target_id", ""))
	var source := str(followup.get("source", "Stratagem"))
	var unit_name := GameState.get_unit_display_name(unit_id)
	var target_name := GameState.get_unit_display_name(target_id)
	var board := GameState.create_snapshot()
	var assignments := _ork11e_forced_shoot_assignments(unit_id, target_id, board)
	if assignments.is_empty():
		var none_msg := "%s: %s has no ranged weapon that can target %s — no attacks" % [source, unit_name, target_name]
		log_phase_message(none_msg)
		GameEventLog.add_player_entry(player, none_msg)
		return
	var weapon_names: Array = []
	for a in assignments:
		weapon_names.append(str(RulesEngine.get_weapon_profile(a.weapon_id, board).get("name", a.weapon_id)))
	var header := "%s: %s shoots %s (normal shooting, auto-resolved) with %s" % [source, unit_name, target_name, ", ".join(weapon_names)]
	log_phase_message(header)
	GameEventLog.add_combat_header("P%d: %s" % [player, header])
	var res = RulesEngine.resolve_shoot({"type": "SHOOT", "actor_unit_id": unit_id,
		"payload": {"assignments": assignments}}, board, RulesEngine.make_rng())
	var diffs: Array = res.get("diffs", [])
	var hits := 0
	var wounds := 0
	for db in res.get("dice", []):
		var c := str(db.get("context", ""))
		# Every attack here is against the forced target; tag the attack dice
		# with it (the auto path's blocks carry no target id — pinned by the
		# ISS-012 golden corpus).
		if c in ["to_hit", "auto_hit", "to_wound"] and not db.has("target_unit_id"):
			db["target_unit_id"] = target_id
		dice_log.append(db)
		emit_signal("dice_rolled", db)
		if c == "to_hit" or c == "auto_hit":
			hits += int(db.get("successes", 0))
		elif c == "to_wound":
			wounds += int(db.get("successes", 0))
	var casualties := 0
	var damage_diffs: Array = []
	for d in diffs:
		var path := str(d.get("path", ""))
		if ".models." in path and (path.ends_with(".alive") or path.ends_with(".current_wounds")):
			damage_diffs.append(d)
		if path.begins_with("units.%s." % target_id) and path.ends_with(".alive") and d.get("value", true) == false:
			casualties += 1
	if not diffs.is_empty():
		# Event attribution (framework F9): these are the forced shooter's
		# attacks, not the active shooter's. Settle anything detected so far
		# against the previous attacker, apply the shot with the forced
		# shooter as the attacker (unit_destroyed gets its attacker_unit_id,
		# enemy_unit_has_attacked opens for the owner of what it destroyed —
		# e.g. INFESTED WAR ZONE), then restore the attribution.
		_window_events_detect()
		var prev_attacker := _ev_action_attacker
		_ev_action_attacker = unit_id
		PhaseManager.apply_state_changes(diffs)
		_window_sync_diffs.append_array(diffs)
		_window_events_detect()
		_ev_action_attacker = prev_attacker
	emit_signal("ai_shooting_visual", unit_id, [{"target_unit_id": target_id, "weapon_names": weapon_names}],
		{"hits": hits, "wounds": wounds, "saves_passed": 0, "saves_failed": 0, "casualties": casualties})
	if not damage_diffs.is_empty():
		emit_signal("shooting_damage_applied", unit_id, damage_diffs)
	var summary := "%s: %s → %s: %d hit(s), %d wound(s), %d model(s) slain" % [source, unit_name, target_name, hits, wounds, casualties]
	# LV2-G1: the forced shooter's own [HAZARDOUS] roll(s).
	var res_dice: Array = res.get("dice", [])
	var gc_haz_lines: Array = []
	for hi in range(res_dice.size()):
		if str(res_dice[hi].get("context", "")) == "hazardous_check":
			var gc_haz := RulesEngine.hazard_game_log_line(res_dice.slice(hi, hi + 2))
			if gc_haz != "":
				gc_haz_lines.append(gc_haz)
	if not gc_haz_lines.is_empty():
		summary += " [%s]" % "; ".join(gc_haz_lines)
	log_phase_message(summary)
	GameEventLog.add_combat_result("  " + summary)
	GameEventLog.add_player_entry(player, summary)

# ============================================================================
# GRENADE STRATAGEM SUPPORT
# ============================================================================

func _validate_use_grenade_stratagem(action: Dictionary) -> Dictionary:
	"""Validate using the GRENADE stratagem during the active player's shooting phase."""
	var grenade_unit_id = action.get("grenade_unit_id", "")
	var target_unit_id = action.get("target_unit_id", "")

	if grenade_unit_id == "":
		return {"valid": false, "errors": ["Missing grenade_unit_id"]}
	if target_unit_id == "":
		return {"valid": false, "errors": ["Missing target_unit_id"]}

	var current_player = get_current_player()

	# Check that the grenade unit belongs to the active player
	var grenade_unit = get_unit(grenade_unit_id)
	if grenade_unit.is_empty():
		return {"valid": false, "errors": ["Grenade unit not found"]}
	if grenade_unit.get("owner", 0) != current_player:
		return {"valid": false, "errors": ["Grenade unit does not belong to active player"]}

	# Check that the grenade unit hasn't already shot
	if grenade_unit_id in units_that_shot:
		return {"valid": false, "errors": ["Unit has already shot this phase"]}

	# Check that the target is an enemy unit
	var target_unit = get_unit(target_unit_id)
	if target_unit.is_empty():
		return {"valid": false, "errors": ["Target unit not found"]}
	if target_unit.get("owner", 0) == current_player:
		return {"valid": false, "errors": ["Cannot target friendly units with GRENADE"]}

	# Validate through StratagemManager
	var validation = StratagemManager.can_use_stratagem(current_player, "grenade", grenade_unit_id)
	if not validation.can_use:
		return {"valid": false, "errors": [validation.reason]}

	return {"valid": true, "errors": []}

func _process_use_grenade_stratagem(action: Dictionary) -> Dictionary:
	"""Process the GRENADE stratagem: roll 6D6, 4+ = mortal wound."""
	var grenade_unit_id = action.get("grenade_unit_id", "")
	var target_unit_id = action.get("target_unit_id", "")
	var current_player = get_current_player()

	# Execute via StratagemManager (handles CP deduction, dice rolling, mortal wound application)
	# NOTE: execute_grenade applies all diffs internally via PhaseManager.apply_state_changes()
	var result = StratagemManager.execute_grenade(current_player, grenade_unit_id, target_unit_id)

	if not result.success:
		return create_result(false, [], result.get("error", "Grenade stratagem failed"))

	# Mark unit as having shot in our local tracking
	units_that_shot.append(grenade_unit_id)

	# Clear active shooter if this was the active unit
	if active_shooter_id == grenade_unit_id:
		active_shooter_id = ""
		pending_assignments.clear()
		confirmed_assignments.clear()

	# Refresh game state snapshot
	game_state_snapshot = GameState.create_snapshot()

	log_phase_message(result.get("message", "GRENADE used"))

	# Emit grenade result signal for UI
	emit_signal("grenade_result", result)

	# Emit dice rolled for dice log display
	# T5-MP5: Build dice block once, emit locally AND include in result["dice"] so
	# the remote player's dice log gets the same block via NetworkManager broadcast.
	var grenade_dice_block = {
		"context": "grenade",
		"rolls_raw": result.get("dice_rolls", []),
		"successes": result.get("mortal_wounds", 0),
		"threshold": "4+",
		"message": result.get("message", "")
	}
	emit_signal("dice_rolled", grenade_dice_block)

	# Emit shooting resolved to refresh visuals
	emit_signal("shooting_resolved", grenade_unit_id, target_unit_id, {
		"casualties": result.get("casualties", 0),
		"grenade": true
	})

	# Return empty changes since execute_grenade already applied all diffs internally
	# (BasePhase.execute_action would double-apply if we returned diffs here)
	return create_result(true, [], result.get("message", ""), {
		"dice": [grenade_dice_block],
		"grenade_result": {
			"dice_rolls": result.get("dice_rolls", []),
			"mortal_wounds": result.get("mortal_wounds", 0),
			"casualties": result.get("casualties", 0),
			"grenade_unit_id": grenade_unit_id,
			"target_unit_id": target_unit_id,
			"message": result.get("message", "")
		}
	})

# T5-UX9: Persist per-weapon results from the active shooter into the phase-level log.
# Called at the moment a unit's shooting concludes (before resolution_state is cleared).
# Each entry retains shooter identity so the end-of-phase summary can attribute hits.
func _record_completed_weapons_to_phase_log(shooter_id: String) -> void:
	if shooter_id == "":
		return
	var completed = resolution_state.get("completed_weapons", [])
	if completed.is_empty():
		return
	var shooter_unit = get_unit(shooter_id)
	var shooter_name = shooter_unit.get("meta", {}).get("name", shooter_id)
	for entry in completed:
		var weapon_id = entry.get("weapon_id", "")
		var weapon_profile = RulesEngine.get_weapon_profile(weapon_id)
		var weapon_name = weapon_profile.get("name", weapon_id)
		phase_shooting_log.append({
			"shooter_unit_id": shooter_id,
			"shooter_unit_name": shooter_name,
			"weapon_id": weapon_id,
			"weapon_name": weapon_name,
			"target_unit_id": entry.get("target_unit_id", ""),
			"target_unit_name": entry.get("target_unit_name", "Unknown"),
			"hits": entry.get("hits", 0),
			"total_attacks": entry.get("total_attacks", 0),
			"wounds": entry.get("wounds", 0),
			"saves_failed": entry.get("saves_failed", 0),
			"casualties": entry.get("casualties", 0),
			"skipped_target_destroyed": entry.get("skipped_target_destroyed", false)
		})
	DebugLogger.info(str("ShootingPhase: T5-UX9 recorded %d weapon entries for %s into phase_shooting_log (total: %d)" % [
		completed.size(), shooter_name, phase_shooting_log.size()]))

# T5-UX9: Append a single ad-hoc entry to the phase log. Used by the AI atomic path
# which doesn't populate resolution_state.completed_weapons.
func _append_phase_shooting_entry(entry: Dictionary) -> void:
	phase_shooting_log.append(entry)

# T5-UX9: Aggregate phase_shooting_log into per-target-unit totals for the end-of-phase summary panel.
# Returns: {
#   "by_target": { target_unit_id: { target_unit_name, hits, total_attacks, wounds, saves_failed, casualties, shooters: [name,...] } },
#   "totals": { hits, total_attacks, wounds, saves_failed, casualties },
#   "shooters_count": int,           # distinct shooter units
#   "targets_count": int,            # distinct target units
#   "weapon_entries": int,           # number of recorded weapon resolutions
#   "raw_entries": Array             # the full phase_shooting_log for debugging / drill-down
# }
func get_phase_shooting_summary() -> Dictionary:
	var by_target: Dictionary = {}
	var totals = {"hits": 0, "total_attacks": 0, "wounds": 0, "saves_failed": 0, "casualties": 0}
	var shooter_set: Dictionary = {}
	for entry in phase_shooting_log:
		var tid = entry.get("target_unit_id", "")
		if tid == "":
			continue
		if not by_target.has(tid):
			by_target[tid] = {
				"target_unit_id": tid,
				"target_unit_name": entry.get("target_unit_name", tid),
				"hits": 0,
				"total_attacks": 0,
				"wounds": 0,
				"saves_failed": 0,
				"casualties": 0,
				"shooters": []
			}
		var bucket = by_target[tid]
		bucket.hits += int(entry.get("hits", 0))
		bucket.total_attacks += int(entry.get("total_attacks", 0))
		bucket.wounds += int(entry.get("wounds", 0))
		bucket.saves_failed += int(entry.get("saves_failed", 0))
		bucket.casualties += int(entry.get("casualties", 0))
		var sname = entry.get("shooter_unit_name", "")
		if sname != "" and sname not in bucket.shooters:
			bucket.shooters.append(sname)

		totals.hits += int(entry.get("hits", 0))
		totals.total_attacks += int(entry.get("total_attacks", 0))
		totals.wounds += int(entry.get("wounds", 0))
		totals.saves_failed += int(entry.get("saves_failed", 0))
		totals.casualties += int(entry.get("casualties", 0))

		var sid = entry.get("shooter_unit_id", "")
		if sid != "":
			shooter_set[sid] = true

	return {
		"by_target": by_target,
		"totals": totals,
		"shooters_count": shooter_set.size(),
		"targets_count": by_target.size(),
		"weapon_entries": phase_shooting_log.size(),
		"raw_entries": phase_shooting_log.duplicate(true)
	}

func _get_last_weapon_result() -> Dictionary:
	"""Build complete result summary for last weapon"""
	var completed = resolution_state.get("completed_weapons", [])
	if completed.is_empty():
		return {}

	var last_weapon = completed[completed.size() - 1]
	var weapon_profile = RulesEngine.get_weapon_profile(last_weapon.get("weapon_id", ""))

	return {
		"weapon_id": last_weapon.get("weapon_id", ""),
		"weapon_name": weapon_profile.get("name", last_weapon.get("weapon_id", "Unknown")),
		"target_unit_id": last_weapon.get("target_unit_id", ""),
		"target_unit_name": last_weapon.get("target_unit_name", "Unknown"),
		"hits": last_weapon.get("hits", 0),
		"wounds": last_weapon.get("wounds", 0),
		"saves_failed": last_weapon.get("saves_failed", 0),
		"casualties": last_weapon.get("casualties", 0),
		"dice_rolls": last_weapon.get("dice_rolls", []),
		"total_attacks": last_weapon.get("total_attacks", 0),
		"hit_data": last_weapon.get("hit_data", {}),
		"wound_data": last_weapon.get("wound_data", {}),
		"skipped": last_weapon.get("skipped", false),
		"skip_reason": last_weapon.get("skip_reason", "")
	}

func _hidden_shot_stamp(unit_id: String) -> Dictionary:
	# 13.09 HIDDEN: stamp the turn-index when this unit actually made ranged
	# attacks, so TerrainManager.is_model_hidden can apply the "did not shoot
	# this turn or the previous turn" condition. Monotonic across player turns.
	var idx := GameState.get_battle_round() * 2 + (0 if get_current_player() == 1 else 1)
	return {"op": "set", "path": "units.%s.flags.last_shot_idx" % unit_id, "value": idx}

## T09 (BasePhase.has_unit_acted_this_phase): a unit has acted in the
## Shooting phase once flags.has_shot is set — its attacks resolved, it was
## skipped, or it started an action / burned an objective instead (each sets
## the flag; an attached character shares its bodyguard's). Only the active
## player's units count: Fire Overwatch earlier in the turn sets has_shot on
## the opponent's units, and _clear_phase_flags only sweeps it at this phase's
## end.
func has_unit_acted_this_phase(unit_id: String) -> bool:
	return _t09_is_active_players(unit_id) and _t09_unit_flag(unit_id, "has_shot")

func _clear_phase_flags() -> void:
	var units = game_state_snapshot.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if unit.has("flags"):
			unit.flags.erase("has_shot")
			unit.flags.erase("performed_action")
			unit.flags.erase("firing_deck_weapons")
	# The loan lives on live GameState too (applied via state changes) — sweep it
	# there as well so a leftover loan can never survive into a later phase.
	for unit_id in GameState.state.get("units", {}):
		var live_unit = GameState.state.units[unit_id]
		if live_unit.has("flags"):
			live_unit.flags.erase("firing_deck_weapons")

func _clear_stratagem_phase_flags() -> void:
	"""Clear effect-granted flags from all units at end of shooting phase.

	The blanket clear expires phase-scoped stratagem effects (Go to Ground,
	Smokescreen). It must NOT strip Waaagh!-granted effects, which last until
	the owner's next Command phase (bug 2026-07: a unit that Advanced under an
	active Waaagh! lost effect_advance_and_charge here and so was refused a
	charge, and the Waaagh! 5+ invuln vanished after one shooting phase). Snap
	those flags before the wipe and restore them after."""
	var fam = get_node_or_null("/root/FactionAbilityManager")
	var units = game_state_snapshot.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if unit.has("flags"):
			var flags = unit.flags
			var preserved = fam.snapshot_persistent_ability_flags(flags) if fam else {}
			EffectPrimitivesData.clear_all_effect_flags(flags)
			for flag_name in preserved:
				flags[flag_name] = preserved[flag_name]
	# Also tell StratagemManager to clear its phase-scoped effects
	StratagemManager.on_phase_end(GameStateData.Phase.SHOOTING)

func _clear_shooting_visuals() -> void:
	"""Clear all shooting-related visuals from the board when phase ends"""
	# Get the ShootingController from Main
	var main = SceneRefs.main()
	if not main:
		DebugLogger.info("ShootingPhase: Warning - Main node not found for visual cleanup")
		return

	var shooting_controller = main.get("shooting_controller")
	if shooting_controller and is_instance_valid(shooting_controller):
		DebugLogger.info("ShootingPhase: Clearing shooting visuals via controller")
		# Call controller's cleanup method
		if shooting_controller.has_method("_clear_visuals"):
			shooting_controller._clear_visuals()
		DebugLogger.info("ShootingPhase: Shooting visuals cleared")
	else:
		# Fallback: If controller already freed, clean up BoardRoot directly
		DebugLogger.info("ShootingPhase: Controller not available, cleaning BoardRoot directly")
		_cleanup_boardroot_visuals()

func _cleanup_boardroot_visuals() -> void:
	"""Fallback cleanup - remove shooting visuals directly from BoardRoot"""
	var board_root = SceneRefs.board_root()
	if not board_root:
		return

	# Remove shooting-specific visual nodes
	var visual_names = [
		"ShootingRangeVisual",
		"ShootingLoSVisual",
		"ShootingTargetHighlights",
		"LoSDebugVisual"
	]

	for visual_name in visual_names:
		var visual_node = board_root.get_node_or_null(visual_name)
		if visual_node and is_instance_valid(visual_node):
			DebugLogger.info(str("ShootingPhase: Removing ", visual_name, " from BoardRoot"))
			board_root.remove_child(visual_node)
			visual_node.queue_free()

func _clear_death_markers() -> void:
	"""Clear all death markers from the board at phase end"""
	var main = SceneRefs.main()
	if not main:
		DebugLogger.info("ShootingPhase: Warning - Main node not found for death marker cleanup")
		return

	var board_view = main.get_node_or_null("BoardRoot/BoardView")
	if not board_view:
		DebugLogger.info("ShootingPhase: Warning - BoardView not found for death marker cleanup")
		return

	# Find WoundAllocationBoardHighlights instance
	var highlighter = board_view.get_node_or_null("WoundHighlights")
	if highlighter and is_instance_valid(highlighter):
		if highlighter.has_method("clear_death_markers"):
			highlighter.clear_death_markers()
			DebugLogger.info("ShootingPhase: Cleared death markers via highlighter")
		else:
			DebugLogger.info("ShootingPhase: Warning - highlighter has no clear_death_markers method")
	else:
		DebugLogger.info("ShootingPhase: No highlighter found to clear death markers")

func get_available_actions() -> Array:
	var actions = []
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)

	# DEFENDER CONTROL LOCK: an attack is already in flight and the defender
	# owes saves for it. The ONLY legal next action is that batch's APPLY_SAVES.
	# This used to also offer RESOLVE_SHOOTING / CONFIRM_TARGETS /
	# SELECT_SHOOTER / SKIP_UNIT / END_SHOOTING, because active_shooter_id and
	# confirmed_assignments are still populated while the activation is paused.
	# Anything that took one of those re-entered the paused activation:
	# RESOLVE_SHOOTING re-rolled the WHOLE attack behind the defender's back
	# (their open overlay was still showing the discarded dice), emitted a
	# second saves_required that ShootingController deduped, and left the
	# controller's duplicate-signal guard latched — after which no save window
	# ever opened again, pending_save_data never drained, and the AI attacker
	# idled forever on _human_defender_window_pending() with its "thinking"
	# indicator flashing every watchdog tick. Reported 2026-08-03: "the AI
	# stalled after I took a while to roll my saves".
	if not pending_save_data.is_empty():
		actions.append({
			"type": "APPLY_SAVES",
			"description": "Apply pending saves"
		})
		return actions

	# If we have an active shooter with pending assignments
	if active_shooter_id != "" and not pending_assignments.is_empty():
		actions.append({
			"type": "CONFIRM_TARGETS",
			"description": "Confirm target assignments"
		})
		actions.append({
			"type": "CLEAR_ALL_ASSIGNMENTS",
			"description": "Clear all assignments"
		})
	
	# If we have confirmed assignments ready to resolve
	if not confirmed_assignments.is_empty():
		actions.append({
			"type": "RESOLVE_SHOOTING",
			"actor_unit_id": active_shooter_id,
			"description": "Resolve shooting"
		})

	# SWIFT AS THE EAGLE pending — offer use/decline (defender's choice)
	if awaiting_swift_as_eagle and swift_as_eagle_pending_unit != "":
		var sae_unit = get_unit(swift_as_eagle_pending_unit)
		var sae_name = sae_unit.get("meta", {}).get("name", swift_as_eagle_pending_unit) if not sae_unit.is_empty() else swift_as_eagle_pending_unit
		var sae_player = int(sae_unit.get("owner", 0))
		actions.append({
			"type": "USE_SWIFT_AS_THE_EAGLE",
			"actor_unit_id": swift_as_eagle_pending_unit,
			"player": sae_player,
			"description": "%s — %s makes a Normal move of up to %d\"" % [swift_as_eagle_pending_strat, sae_name, swift_as_eagle_move_inches]
		})
		actions.append({
			"type": "DECLINE_SWIFT_AS_THE_EAGLE",
			"actor_unit_id": swift_as_eagle_pending_unit,
			"player": sae_player,
			"description": "Decline %s — %s" % [swift_as_eagle_pending_strat, sae_name]
		})
		return actions

	# P1-12: Throat Slittas pending — offer use/decline
	if throat_slittas_pending_unit != "":
		var ts_unit = get_unit(throat_slittas_pending_unit)
		var ts_name = ts_unit.get("meta", {}).get("name", throat_slittas_pending_unit) if not ts_unit.is_empty() else throat_slittas_pending_unit
		actions.append({
			"type": "USE_THROAT_SLITTAS",
			"actor_unit_id": throat_slittas_pending_unit,
			"description": "Activate Throat Slittas — %s deals mortal wounds" % ts_name
		})
		actions.append({
			"type": "DECLINE_THROAT_SLITTAS",
			"actor_unit_id": throat_slittas_pending_unit,
			"description": "Decline Throat Slittas — %s shoots normally" % ts_name
		})
		# When Throat Slittas is pending, only these actions should be available
		actions.append({
			"type": "END_SHOOTING",
			"description": "End Shooting Phase"
		})
		return actions

	# (Pending saves are handled by the DEFENDER CONTROL LOCK at the top of this
	# function — reaching here means pending_save_data is empty.)

	# Sequential mode: continue or complete (safety net for AI)
	if resolution_state.get("mode", "") in ["sequential", "sequential_staged", "fast"]:
		var idx = resolution_state.get("current_index", 0)
		var order = resolution_state.get("weapon_order", [])
		if idx < order.size():
			actions.append({
				"type": "CONTINUE_SEQUENCE",
				"description": "Continue to next weapon"
			})
		elif active_shooter_id != "":
			actions.append({
				"type": "COMPLETE_SHOOTING_FOR_UNIT",
				"actor_unit_id": active_shooter_id,
				"description": "Complete shooting for unit"
			})

	# Single weapon completed but awaiting confirmation (safety net for AI)
	if resolution_state.get("phase", "") == "awaiting_confirmation" and active_shooter_id != "":
		actions.append({
			"type": "COMPLETE_SHOOTING_FOR_UNIT",
			"actor_unit_id": active_shooter_id,
			"description": "Complete shooting for unit"
		})

	# Units that can shoot
	for unit_id in units:
		var unit = units[unit_id]
		# 19.01: an attached CHARACTER is selected through its bodyguard (the
		# bodyguard's activation already carries the character's weapons).
		if shooting_actor_for(unit_id) != unit_id:
			continue
		if _can_unit_shoot(unit) and unit_id not in units_that_shot:
			# P3-96: "Unless at least one model in a unit has an eligible target,
			# that unit cannot be selected to shoot." (SHOOT-7)
			# Only gate SELECT_SHOOTER/SKIP_UNIT — secondary actions (mission actions,
			# burn, ritual, terraform) are still available without eligible targets.
			var has_targets = _has_eligible_targets(unit_id)

			if has_targets:
				actions.append({
					"type": "SELECT_SHOOTER",
					"actor_unit_id": unit_id,
					"description": "Select %s for shooting" % unit.get("meta", {}).get("display_name", unit.get("meta", {}).get("name", unit_id))
				})

				actions.append({
					"type": "SKIP_UNIT",
					"actor_unit_id": unit_id,
					"description": "Skip shooting for %s" % unit.get("meta", {}).get("display_name", unit.get("meta", {}).get("name", unit_id))
				})

			# Check if unit qualifies for a secondary action
			var action_options = _get_secondary_action_options(unit_id)
			for opt in action_options:
				actions.append({
					"type": "PERFORM_SECONDARY_ACTION",
					"actor_unit_id": unit_id,
					"payload": {
						"action_name": opt.action_name,
						"location": opt.location,
						"mission_id": opt.mission_id,
						"vp_value": opt.get("vp_value", 0),
					},
					"description": "%s: %s" % [unit.get("meta", {}).get("display_name", unit.get("meta", {}).get("name", unit_id)), opt.description]
				})

			# Check if unit can burn an objective (Scorched Earth mission)
			var burn_options = _get_burn_objective_options(unit_id)
			for burn_opt in burn_options:
				actions.append({
					"type": "BURN_OBJECTIVE",
					"actor_unit_id": unit_id,
					"objective_id": burn_opt.objective_id,
					"burn_vp": burn_opt.burn_vp,
					"description": "%s: Burn %s (+%d VP end-of-game)" % [
						unit.get("meta", {}).get("name", unit_id),
						burn_opt.objective_id,
						burn_opt.burn_vp]
				})

			# Check if unit can perform a ritual action (The Ritual mission)
			var ritual_options = _get_ritual_action_options(unit_id)
			for ritual_opt in ritual_options:
				actions.append({
					"type": "PERFORM_RITUAL_ACTION",
					"actor_unit_id": unit_id,
					"objective_id": ritual_opt.objective_id,
					"description": "%s: Perform Ritual at %s (create new objective)" % [
						unit.get("meta", {}).get("name", unit_id),
						ritual_opt.objective_id]
				})

			# Check if unit can perform a terraform action (Terraform mission)
			var terraform_options = _get_terraform_action_options(unit_id)
			for tf_opt in terraform_options:
				var tf_desc = "Terraform %s" % tf_opt.objective_id
				if tf_opt.get("is_flip", false):
					tf_desc = "Flip %s (opponent's terraform)" % tf_opt.objective_id
				actions.append({
					"type": "PERFORM_TERRAFORM_ACTION",
					"actor_unit_id": unit_id,
					"objective_id": tf_opt.objective_id,
					"is_flip": tf_opt.get("is_flip", false),
					"description": "%s: %s" % [
						unit.get("meta", {}).get("name", unit_id),
						tf_desc]
				})

	# Always can end phase
	actions.append({
		"type": "END_SHOOTING",
		"description": "End Shooting Phase"
	})

	return actions

func _should_complete_phase() -> bool:
	# Check if all eligible units have shot or been skipped
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)
	
	for unit_id in units:
		var unit = units[unit_id]
		if _can_unit_shoot(unit) and unit_id not in units_that_shot:
			return false
	
	return true

func get_dice_log() -> Array:
	return dice_log

func get_active_shooter() -> String:
	return active_shooter_id

func get_pending_assignments() -> Array:
	return pending_assignments

func get_confirmed_assignments() -> Array:
	return confirmed_assignments

func get_units_that_shot() -> Array:
	return units_that_shot

func has_active_shooter() -> bool:
	return active_shooter_id != ""

func get_current_shooting_state() -> Dictionary:
	return {
		"active_shooter_id": active_shooter_id,
		"pending_assignments": pending_assignments,
		"confirmed_assignments": confirmed_assignments,
		"units_that_shot": units_that_shot,
		"eligible_targets": {} # Will be populated when targets are queried
	}

# Override create_result to support additional data
func create_result(success: bool, changes: Array = [], error: String = "", additional_data: Dictionary = {}) -> Dictionary:
	var result = {
		"success": success,
		"phase": phase_type,
		"timestamp": Time.get_unix_time_from_system()
	}
	
	if success:
		result["changes"] = changes
		for key in additional_data:
			result[key] = additional_data[key]
	else:
		result["error"] = error
	
	return result

func validate_loaded_state() -> bool:
	"""Validate that the loaded shooting phase state is consistent"""
	# Check if active shooter is valid
	if active_shooter_id != "":
		var shooter = get_unit(active_shooter_id)
		if shooter.is_empty():
			DebugLogger.info(str("WARNING: Invalid active shooter after load: ", active_shooter_id))
			active_shooter_id = ""
			return false
		
		if not _can_unit_shoot(shooter):
			DebugLogger.info(str("WARNING: Active shooter cannot shoot after load: ", active_shooter_id))
			active_shooter_id = ""
			return false
	
	# Validate assignments reference valid units and weapons
	for assignment in pending_assignments:
		var target = get_unit(assignment.target_unit_id)
		if target.is_empty():
			DebugLogger.info(str("WARNING: Invalid target in assignments: ", assignment.target_unit_id))
			return false

	return true

# Transport Firing Deck support

# 24.14: choose the firing-deck weapons automatically so the transport shoots
# with its embarked models' guns without a per-model dialog. Datasheets list
# every wargear OPTION on each model (the loadout isn't pinned per model), so a
# model typically reports several ranged weapons; we pick each model's BASIC
# ranged gun (the plain rank-and-file weapon, not a one-off special upgrade) so a
# mob of Boyz fires ~Shootas rather than, say, a Big Shoota on every model —
# which would over-count a weapon the mob only carries one of. Returns
# {"mode":"auto","loans":[...]}; `loans` may be empty (no deck-eligible weapon),
# in which case the caller just shoots the transport's own guns.
func _compute_firing_deck_plan(transport_id: String, eligible_embarked: Array) -> Dictionary:
	var transport = get_unit(transport_id)
	var t_data = transport.get("transport_data", {})
	var capacity = int(t_data.get("firing_deck", 0))
	# [EMBARKING]: MEGA ARMOUR / JUMP PACK models (and any keyword the transport
	# declares with a capacity_multiplier > 1) count as two for Firing Deck, so
	# each of their weapons consumes 2 of the X slots.
	var multi_keywords := ["MEGA ARMOUR", "JUMP PACK"]
	for mk in t_data.get("capacity_multipliers", {}):
		if int(t_data["capacity_multipliers"][mk]) > 1 and not (mk in multi_keywords):
			multi_keywords.append(mk)
	var board = game_state_snapshot
	# One candidate loan per eligible model, tagged with its Firing Deck slot cost.
	var candidates := []
	for embarked_id in eligible_embarked:
		var embarked = get_unit(embarked_id)
		if embarked.is_empty():
			continue
		var kws = embarked.get("meta", {}).get("keywords", [])
		var slot_cost := 1
		for mk in multi_keywords:
			if mk in kws:
				slot_cost = 2
				break
		var model_weapons = RulesEngine.get_unit_weapons(embarked_id, board)
		for model in embarked.get("models", []):
			if not model.get("alive", true):
				continue
			var mid = str(model.get("id", ""))
			var chosen = _pick_firing_deck_weapon(model_weapons.get(mid, []), board)
			if chosen == "":
				continue  # no auto-eligible (non-[ONE SHOT], non-[HAZARDOUS]) gun
			candidates.append({
				"loan": {"unit_id": embarked_id, "model_id": mid, "weapon_id": chosen},
				"cost": slot_cost
			})
	# Fit the candidates under Firing Deck X (double-counting models cost 2). All
	# models of a unit share the same basic gun, so an over-capacity mob just
	# fires the first X — any subset of identical guns is equivalent.
	var loans := []
	var used := 0
	for c in candidates:
		if used + int(c["cost"]) <= capacity:
			loans.append(c["loan"])
			used += int(c["cost"])
	return {"mode": "auto", "loans": loans}


# Pick a model's BASIC ranged gun for the firing deck from its weapon ids.
# Excludes [ONE SHOT] (24.14 step 2) and [HAZARDOUS] (24.15 — never auto-commit
# the transport to a hazard roll), prefers a non-Pistol, and among what remains
# picks the plainest gun (lowest Damage, then lowest Strength) so a mob fires its
# rank-and-file weapon rather than a special upgrade only one model really has.
# Returns "" when the model has no auto-eligible ranged weapon.
func _pick_firing_deck_weapon(weapon_ids: Array, board: Dictionary) -> String:
	var eligible := []
	for wid in weapon_ids:
		if RulesEngine.is_one_shot_weapon(wid, board):
			continue
		if RulesEngine.is_hazardous_weapon(wid, board):
			continue
		eligible.append(str(wid))
	if eligible.is_empty():
		return ""
	# Prefer non-Pistol guns when the model has any (a Pistol is a fallback gun).
	var pool := []
	for wid in eligible:
		if not RulesEngine.is_pistol_weapon(wid, board):
			pool.append(wid)
	if pool.is_empty():
		pool = eligible
	# Plainest gun wins: lowest Damage, then lowest Strength; ties keep order.
	var best := ""
	var best_dmg := 1 << 30
	var best_str := 1 << 30
	for wid in pool:
		var prof = RulesEngine.get_weapon_profile(wid, board)
		var dmg := _fd_numeric_rank(str(prof.get("damage", "1")))
		var stg := _fd_numeric_rank(str(prof.get("strength", "1")))
		if best == "" or dmg < best_dmg or (dmg == best_dmg and stg < best_str):
			best = wid
			best_dmg = dmg
			best_str = stg
	return best


# Rank a weapon stat string numerically: a plain integer sorts by value; anything
# variable/special (e.g. "D6", "D3", "2D6") sorts high, so a random-damage upgrade
# is never mistaken for the basic gun.
func _fd_numeric_rank(s: String) -> int:
	return int(s) if s.is_valid_int() else (1 << 20)


# 24.14: loan `loans` (each {unit_id, model_id, weapon_id}) onto the transport so
# get_unit_weapons offers them as the transport's own weapons for this
# activation, and mark each contributing embarked unit as having shot. Applied
# out-of-band via the parent so it persists to live GameState; the phase
# snapshot is refreshed so subsequent weapon/target queries see the loan.
func _apply_firing_deck_loan(transport_id: String, loans: Array) -> void:
	var changes := []
	var marked := {}
	for loan in loans:
		var emb_id = str(loan.get("unit_id", ""))
		if emb_id != "" and not marked.has(emb_id):
			marked[emb_id] = true
			changes.append({
				"op": "set",
				"path": "units.%s.flags.has_shot" % emb_id,
				"value": true
			})
	changes.append({
		"op": "set",
		"path": "units.%s.flags.firing_deck_weapons" % transport_id,
		"value": loans.duplicate(true)
	})
	if get_parent() and get_parent().has_method("apply_state_changes"):
		get_parent().apply_state_changes(changes)
	# Refresh the phase snapshot so target/weapon queries see the loan at once.
	game_state_snapshot = GameState.state.duplicate(true)

func _show_firing_deck_dialog(transport_id: String) -> void:
	"""Show dialog to select which embarked models will shoot through firing deck"""
	var transport = get_unit(transport_id)
	var firing_deck_capacity = transport.transport_data.get("firing_deck", 0)
	var embarked_units = transport.transport_data.get("embarked_units", [])

	# Create firing deck dialog
	var dialog_script = load("res://scripts/FiringDeckDialog.gd")
	var dialog = dialog_script.new()
	dialog.setup(transport_id, embarked_units, firing_deck_capacity)
	dialog.models_selected.connect(_on_firing_deck_models_selected.bind(transport_id))

	get_tree().root.add_child(dialog)
	# Bottom-anchored + capped to the viewport so the firing-deck instructions
	# can't push the Confirm button off-screen (see DialogUtils.popup_at_bottom).
	DialogUtils.popup_at_bottom(dialog, DialogConstants.MEDIUM)

func _on_firing_deck_models_selected(selected_weapons: Array, transport_id: String) -> void:
	"""Handle selection of weapons from embarked units for firing deck"""
	# Store the selected weapons as part of transport's temporary shooting state
	if not resolution_state.has("firing_deck_weapons"):
		resolution_state["firing_deck_weapons"] = {}

	resolution_state["firing_deck_weapons"][transport_id] = selected_weapons

	# 24.14: the selected weapons are treated as being equipped by the TRANSPORT
	# model for this activation (RulesEngine.get_unit_weapons offers them as
	# synthetic hull bearers alongside the transport's own guns). The loan is
	# cleared when the transport finishes shooting (_clear_firing_deck_loan) and
	# at end of phase.
	var loans = []
	for weapon_data in selected_weapons:
		loans.append({
			"unit_id": weapon_data.get("unit_id", ""),
			"model_id": weapon_data.get("model_id", ""),
			"weapon_id": weapon_data.get("weapon_id", ""),
		})
	_apply_firing_deck_loan(transport_id, loans)

	# Resume the normal shooting flow so the loaned weapons appear in the weapon
	# tree and the player can pick targets. (Previously the weapon tree was built
	# when the transport was first selected — before the loan existed — and was
	# never refreshed after the dialog confirmed, so the loaned guns stayed
	# invisible.)
	var eligible_targets = RulesEngine.get_eligible_targets(transport_id, game_state_snapshot)
	emit_signal("unit_selected_for_shooting", transport_id)
	emit_signal("targets_available", transport_id, eligible_targets)
	log_phase_message("Firing deck weapons selected for %s" % get_unit(transport_id).get("meta", {}).get("name", transport_id))

func _clear_firing_deck_loan(transport_id: String) -> void:
	"""Remove the firing-deck weapon loan from a transport once its shooting ends.

	Loan-clearing only — it must NOT re-emit target selection (it runs at
	shooting completion; re-arming targeting there spuriously re-selected the
	just-finished transport). The post-selection targeting resume lives in
	_on_firing_deck_models_selected / the auto-resolve path instead."""
	var unit = GameState.state.get("units", {}).get(transport_id, {})
	if unit.is_empty() or not unit.get("flags", {}).has("firing_deck_weapons"):
		return
	unit.flags.erase("firing_deck_weapons")
	if game_state_snapshot.get("units", {}).has(transport_id):
		var snap_flags = game_state_snapshot.units[transport_id].get("flags", {})
		snap_flags.erase("firing_deck_weapons")

# Interactive Save Resolution

func _validate_apply_saves(action: Dictionary) -> Dictionary:
	"""Validate that save data is ready to be applied"""
	if pending_save_data.is_empty():
		return {"valid": false, "errors": ["No pending saves to apply"]}

	var payload = action.get("payload", {})
	if not payload.has("save_results_list"):
		return {"valid": false, "errors": ["Missing save_results_list in payload"]}

	return {"valid": true, "errors": []}

func _validate_continue_sequence(action: Dictionary) -> Dictionary:
	"""Validate continuing to next weapon in sequential mode"""
	# All three multi-weapon modes pause between weapons and continue via
	# CONTINUE_SEQUENCE: "sequential" (networked), "sequential_staged"
	# (single-player hit→wound→saves staging) and "fast". Rejecting the staged
	# mode here dead-ended split-fire after the first target's saves.
	var mode = resolution_state.get("mode", "")
	if mode not in ["sequential", "sequential_staged", "fast"]:
		return {"valid": false, "errors": ["Not in sequential mode"]}

	var current_index = resolution_state.get("current_index", 0)
	var weapon_order = resolution_state.get("weapon_order", [])

	if current_index >= weapon_order.size():
		return {"valid": false, "errors": ["No more weapons to resolve"]}

	return {"valid": true, "errors": []}

func _validate_complete_shooting_for_unit(action: Dictionary) -> Dictionary:
	"""Validate completing shooting for a unit after final weapon"""
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}

	if unit_id != active_shooter_id:
		return {"valid": false, "errors": ["Unit is not the active shooter"]}

	return {"valid": true, "errors": []}

func _process_complete_shooting_for_unit(action: Dictionary) -> Dictionary:
	"""Mark shooter as done and clear state."""
	var unit_id = action.get("actor_unit_id", "")

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ SHOOTING PHASE: COMPLETE_SHOOTING_FOR_UNIT")
	DebugLogger.info(str("║ Unit ID: ", unit_id))
	DebugLogger.info("║ This is triggered when user views final weapon results")
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	# 24.14: the firing-deck weapon loan lasts for this activation only.
	_clear_firing_deck_loan(unit_id)

	var changes = [{
		"op": "set",
		"path": "units.%s.flags.has_shot" % unit_id,
		"value": true
	}]
	# 13.09 HIDDEN: this is the completion the interactive flow reaches after
	# real ranged attacks (the player confirms the final weapon results) —
	# without the stamp here, any unit whose shots caused wounds never lost
	# Hidden. The give-up-shooting action paths (16.01 etc.) correctly do
	# NOT stamp.
	changes.append(_hidden_shot_stamp(unit_id))

	# Issue #386 Big Booms: apply D3 MW per struck unit after supa-kannon attacks finish.
	if not _big_booms_pending.is_empty():
		var bb_board = GameState.create_snapshot()
		# ISS-004: action is in scope — honor/record payload.rng_seed so the
		# action log can replay these rolls.
		var bb_rng = RulesEngine.rng_for_action(action)
		for entry in _big_booms_pending:
			for struck_uid in entry.get("struck_unit_ids", []):
				var d3 = bb_rng.randi_range(1, 3)
				var bb_result = RulesEngine.apply_mortal_wounds(struck_uid, d3, bb_board, bb_rng)
				changes.append_array(bb_result.get("diffs", []))
				log_phase_message("Big Booms: %s suffers %d mortal wound(s)" % [struck_uid, d3])
		_big_booms_pending.clear()

	units_that_shot.append(unit_id)

	# Capture target IDs before clearing for post-shooting checks (Swift as the Eagle)
	var targeted_unit_ids_for_post: Array = []
	for ca in confirmed_assignments:
		var tid = ca.get("target_unit_id", "")
		if tid != "" and tid not in targeted_unit_ids_for_post:
			targeted_unit_ids_for_post.append(tid)

	# Clear state
	var shooter_id = active_shooter_id  # Store before clearing

	# T5-UX9: capture per-weapon shot results before clearing resolution_state
	_record_completed_weapons_to_phase_log(shooter_id)

	# Also capture targets from phase log for multi-weapon shots
	for entry in phase_shooting_log:
		if entry.get("shooter_unit_id", "") == shooter_id:
			var tid = entry.get("target_unit_id", "")
			if tid != "" and tid not in targeted_unit_ids_for_post:
				targeted_unit_ids_for_post.append(tid)

	active_shooter_id = ""
	confirmed_assignments.clear()
	resolution_state.clear()
	pending_save_data.clear()
	_targets_hit_by_shooter.clear()

	log_phase_message("Shooting complete for unit %s" % unit_id)

	# Emit signal to clear visuals
	emit_signal("shooting_resolved", shooter_id, "", {"casualties": 0})

	# SWIFT AS THE EAGLE: After enemy finishes shooting, check if a targeted
	# Custodes non-VEHICLE unit can make a reactive D6" Normal move.
	# Only on opponent's turn (active player is the shooter, defending Custodes player reacts).
	var swift_check = _check_swift_as_the_eagle(shooter_id, targeted_unit_ids_for_post)
	if swift_check.available:
		PhaseManager.apply_state_changes(changes)
		awaiting_swift_as_eagle = true
		swift_as_eagle_pending_unit = swift_check.unit_id
		swift_as_eagle_move_inches = swift_check.move_inches
		swift_as_eagle_pending_strat = swift_check.get("strat_name", "SWIFT AS THE EAGLE")
		log_phase_message("%s available for %s — D6\" Normal move (rolled %d\")" % [swift_as_eagle_pending_strat, swift_check.unit_name, swift_check.move_inches])
		return create_result(true, changes, "%s available" % swift_as_eagle_pending_strat, {
			"swift_as_eagle_available": true,
			"unit_id": swift_check.unit_id,
			"move_inches": swift_check.move_inches,
			"unit_name": swift_check.unit_name,
			"strat_name": swift_as_eagle_pending_strat
		})

	return create_result(true, changes, "Shooting complete")

# (P1-10 Sentinel Storm and the 10e P1-11 automatic Sanctified Flames test
# are gone: no Codex: Adeptus Custodes (11e) datasheet has Sentinel Storm, and
# Sanctified Flames is a unit_has_shot ability card — CustodesAbilities.gd.)

# ============================================================================
# P1-12: THROAT SLITTAS — MORTAL WOUNDS INSTEAD OF SHOOTING (Kommandos)
# ============================================================================
# "At the start of your Shooting phase, if this unit is within 9" of one or more
# enemy units, it can use this ability. If it does, until the end of the phase,
# this unit is not eligible to shoot, but you roll one D6 for each model in this
# unit that is within 9" of an enemy unit: for each 5+, that enemy unit suffers
# 1 mortal wound."

func _validate_use_throat_slittas(action: Dictionary) -> Dictionary:
	"""Validate activating Throat Slittas mortal wounds ability."""
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	if throat_slittas_pending_unit == "" or throat_slittas_pending_unit != unit_id:
		return {"valid": false, "errors": ["No Throat Slittas pending for this unit"]}
	return {"valid": true, "errors": []}

func _validate_decline_throat_slittas(action: Dictionary) -> Dictionary:
	"""Validate declining Throat Slittas ability."""
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	if throat_slittas_pending_unit == "" or throat_slittas_pending_unit != unit_id:
		return {"valid": false, "errors": ["No Throat Slittas pending for this unit"]}
	return {"valid": true, "errors": []}

func _process_use_throat_slittas(action: Dictionary) -> Dictionary:
	"""Player activates Throat Slittas — roll mortal wounds, unit cannot shoot."""
	var unit_id = action.get("actor_unit_id", "")

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ P1-12: THROAT SLITTAS — ACTIVATED")
	DebugLogger.info(str("║ Unit ID: ", unit_id))
	DebugLogger.info("║ Unit will deal mortal wounds instead of shooting")
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	# Clear the pending state
	throat_slittas_pending_unit = ""

	# Resolve the ability
	var result = _resolve_throat_slittas(unit_id)

	# Mark unit as done shooting (cannot shoot after using Throat Slittas)
	var changes = result.get("diffs", [])
	changes.append({
		"op": "set",
		"path": "units.%s.flags.has_shot" % unit_id,
		"value": true
	})
	units_that_shot.append(unit_id)

	# Clear shooter state
	active_shooter_id = ""
	confirmed_assignments.clear()
	resolution_state.clear()
	pending_save_data.clear()

	# Emit signal to clear visuals
	emit_signal("shooting_resolved", unit_id, "", {"casualties": result.get("total_casualties", 0)})

	var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)
	log_phase_message("Throat Slittas: %s dealt %d mortal wound(s) — unit cannot shoot" % [
		unit_name, result.get("total_mortal_wounds", 0)
	])

	return create_result(true, changes, "Throat Slittas resolved")

func _process_decline_throat_slittas(action: Dictionary) -> Dictionary:
	"""Player declines Throat Slittas — proceed with normal shooting."""
	var unit_id = action.get("actor_unit_id", "")

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ P1-12: THROAT SLITTAS — DECLINED")
	DebugLogger.info(str("║ Unit ID: ", unit_id))
	DebugLogger.info("║ Proceeding with normal shooting")
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	# Clear pending state
	throat_slittas_pending_unit = ""

	# Re-process as a normal select_shooter, skipping the Throat Slittas check
	return _process_select_shooter({
		"actor_unit_id": unit_id,
		"payload": {"skip_throat_slittas_check": true}
	})

func _get_throat_slittas_targets(unit_id: String) -> Array:
	"""Find enemy units within 9\" of the unit. Returns array of
	{target_unit_id, target_name, models_in_range} dictionaries."""
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return []

	var unit_owner = unit.get("owner", 0)
	var unit_models = unit.get("models", [])
	var units = game_state_snapshot.get("units", {})
	var targets: Array = []

	for other_id in units:
		var other = units[other_id]
		# Skip friendly units and destroyed units
		if other.get("owner", 0) == unit_owner:
			continue
		var other_alive = false
		for m in other.get("models", []):
			if m.get("alive", true):
				other_alive = true
				break
		if not other_alive:
			continue

		# Count how many of our models are within 9" of this enemy unit
		var models_in_range = _count_models_within_range(unit_models, other, 9.0)
		if models_in_range > 0:
			targets.append({
				"target_unit_id": other_id,
				"target_name": other.get("meta", {}).get("name", other_id),
				"models_in_range": models_in_range
			})

	return targets

func _count_models_within_range(our_models: Array, enemy_unit: Dictionary, range_inches: float) -> int:
	"""Count how many of our alive models are within range_inches of any alive model
	in the enemy unit (edge-to-edge measurement)."""
	var count = 0
	var enemy_models = enemy_unit.get("models", [])

	for our_model in our_models:
		if not our_model.get("alive", true):
			continue

		var in_range = false
		for enemy_model in enemy_models:
			if not enemy_model.get("alive", true):
				continue

			var distance_inches = Measurement.model_to_model_distance_inches(our_model, enemy_model)
			if distance_inches <= range_inches:
				in_range = true
				break

		if in_range:
			count += 1

	return count

func _resolve_throat_slittas(unit_id: String) -> Dictionary:
	"""Resolve Throat Slittas mortal wounds.
	For each enemy unit within 9\", roll 1D6 per model in range. 5+ = 1 mortal wound.
	Returns {diffs: Array, total_mortal_wounds: int, total_casualties: int, per_target: Array}."""
	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var targets = _get_throat_slittas_targets(unit_id)

	var all_diffs: Array = []
	var total_mortal_wounds = 0
	var total_casualties = 0
	var per_target: Array = []

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ P1-12: THROAT SLITTAS — Resolution")
	DebugLogger.info(str("║ Unit: %s (%s)" % [unit_name, unit_id]))
	DebugLogger.info(str("║ Targets within 9\": %d" % targets.size()))

	for target_info in targets:
		var target_unit_id = target_info.get("target_unit_id", "")
		var target_name = target_info.get("target_name", target_unit_id)
		var models_in_range = target_info.get("models_in_range", 0)

		# Roll 1D6 per model in range
		var rolls: Array = []
		var mortal_wounds = 0
		for i in range(models_in_range):
			var roll = _rng.rng.randi_range(1, 6)
			rolls.append(roll)
			if roll >= 5:
				mortal_wounds += 1

		DebugLogger.info(str("║ Target: %s — %d models in range, rolls: %s → %d mortal wound(s)" % [
			target_name, models_in_range, str(rolls), mortal_wounds
		]))

		var target_result = {
			"target_unit_id": target_unit_id,
			"target_name": target_name,
			"models_in_range": models_in_range,
			"rolls": rolls,
			"mortal_wounds": mortal_wounds,
			"casualties": 0
		}

		# Apply mortal wounds as damage (1 damage each, with proper model allocation)
		if mortal_wounds > 0:
			var target_unit = get_unit(target_unit_id)
			var target_models = target_unit.get("models", []).duplicate(true)
			var damage_result = RulesEngine.apply_damage_to_unit_pool(
				target_unit_id, mortal_wounds, target_models, game_state_snapshot
			)
			all_diffs.append_array(damage_result.get("diffs", []))
			target_result["casualties"] = damage_result.get("casualties", 0)
			total_casualties += damage_result.get("casualties", 0)

		total_mortal_wounds += mortal_wounds
		per_target.append(target_result)

	DebugLogger.info(str("║ TOTAL: %d mortal wound(s), %d casualt%s" % [
		total_mortal_wounds, total_casualties,
		"y" if total_casualties == 1 else "ies"
	]))
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	log_phase_message("Throat Slittas (%s): %d mortal wound(s), %d casualt%s" % [
		unit_name, total_mortal_wounds, total_casualties,
		"y" if total_casualties == 1 else "ies"
	])

	# Emit signal for UI display
	var result = {
		"unit_id": unit_id,
		"unit_name": unit_name,
		"total_mortal_wounds": total_mortal_wounds,
		"total_casualties": total_casualties,
		"per_target": per_target,
		"diffs": all_diffs
	}
	emit_signal("throat_slittas_result", unit_id, result)

	return result

# Defender-side save Command Re-roll (1 CP): the AllocationGroupOverlay
# re-rolls one save die locally and stamps `command_reroll` on its summary;
# the phase deducts the CP + records stratagem usage here so the spend is
# authoritative (host-side in multiplayer). Returns the CP diffs.
func _apply_defender_save_command_reroll(save_result_summary: Dictionary, save_data: Dictionary) -> Array:
	var cr = save_result_summary.get("command_reroll", {})
	if not cr.get("used", false):
		return []
	var reroll_player = int(cr.get("player", 0))
	var target_unit_id = str(save_data.get("target_unit_id", save_result_summary.get("target_unit_id", "")))
	var target_name = get_unit(target_unit_id).get("meta", {}).get("name", target_unit_id)
	var result = StratagemManager.execute_command_reroll(reroll_player, target_unit_id, {
		"roll_type": "save_roll",
		"original_rolls": [int(cr.get("original", 0))],
		"unit_name": target_name
	})
	if not result.get("success", false):
		# The overlay's availability check said yes but the authoritative
		# check refused (e.g. CP raced away) — the re-rolled dice stand
		# (they were the source of truth on the defending peer) but log the
		# discrepancy loudly rather than failing the whole save application.
		push_warning("ShootingPhase: defender save Command Re-roll could not be paid: %s" % str(result.get("error", "unknown")))
		log_phase_message("⚠ Save Command Re-roll by player %d could not be paid (%s)" % [reroll_player, str(result.get("error", ""))])
		return []
	log_phase_message("Player %d used COMMAND RE-ROLL on a save for %s (%d → %d)" % [
		reroll_player, target_name, int(cr.get("original", 0)), int(cr.get("new", 0))])
	return result.get("diffs", [])

func _process_apply_saves(action: Dictionary) -> Dictionary:
	"""Process save results and apply damage"""
	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ APPLY_SAVES PROCESSING START")
	DebugLogger.info(str("║ Timestamp: ", Time.get_ticks_msec()))
	DebugLogger.info(str("║ resolution_state: ", resolution_state))
	DebugLogger.info(str("║ pending_save_data.size(): ", pending_save_data.size()))
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	# DEFENDER CONTROL: saves for a paused AI atomic SHOOT consume the
	# pending queue one batch at a time and finish the AI activation.
	if resolution_state.get("mode", "") == "ai_atomic":
		return _process_apply_saves_ai_atomic(action)
	# Issue #329: extract action.payload.rng_seed once for all sub-rolls in this method
	var pas_seed: int = action.get("payload", {}).get("rng_seed", -1)

	var payload = action.get("payload", {})
	var save_results_list = payload.get("save_results_list", [])

	var all_diffs = []
	var total_casualties = 0
	var save_dice_blocks = []  # Collect save dice for dice log + multiplayer sync
	var save_log_parts = []  # Accumulate per-target save summaries for game event log
	var shooter_unit = game_state_snapshot.get("units", {}).get(active_shooter_id, {})
	var shooter_name = shooter_unit.get("meta", {}).get("name", active_shooter_id)

	# Process each save result (one per target unit)
	for i in range(save_results_list.size()):
		if i >= pending_save_data.size():
			break

		var save_result_summary = save_results_list[i]
		var save_data = pending_save_data[i]

		# ISS-045 (11e): the allocation-group overlay already resolved the
		# whole batch (05.03-05.04) on the defending peer — its summary
		# carries idempotent set-diffs, so apply those instead of the 10e
		# per-wound allocation_history conversion below.
		if save_result_summary.get("is_allocation_11e", false):
			all_diffs.append_array(save_result_summary.get("diffs", []))
			# Defender-side save Command Re-roll: the overlay re-rolled one
			# save die — deduct the CP and record usage authoritatively here.
			all_diffs.append_array(_apply_defender_save_command_reroll(save_result_summary, save_data))
			var alloc_casualties = int(save_result_summary.get("casualties", 0))
			total_casualties += alloc_casualties
			var alloc_target_id = save_data.get("target_unit_id", save_result_summary.get("target_unit_id", ""))
			if alloc_casualties > 0 and str(alloc_target_id) != "":
				CharacterAttachmentManager.check_bodyguard_destroyed(alloc_target_id)
			# ARMOUR SAVES IN THE GAME LOG: the 11e flow resolves the whole save
			# batch inside AllocationGroupOverlay, so — unlike the 10e path below
			# — nothing here ever emitted a save dice block. The combat card
			# showed the hit and wound rolls and then jumped to "No models
			# destroyed" with no armour saves explaining why. Replay the batch's
			# saves (and any Feel No Pain) through the normal dice_rolled channel
			# so they land on the combat card, in its details, in the dice log and
			# on the remote peer like every other roll.
			for alloc_block in RulesEngine.normalize_allocation_11e_dice(save_result_summary, {
				"target_unit_name": save_data.get("target_unit_name", alloc_target_id),
				"weapon_name": save_data.get("weapon_name", ""),
			}):
				save_dice_blocks.append(alloc_block)
				dice_log.append(alloc_block)
				emit_signal("dice_rolled", alloc_block)
			log_phase_message("%s: %d saves passed, %d failed → %d casualties (11e allocation)" % [
				save_data.get("target_unit_name", alloc_target_id),
				save_result_summary.get("saves_passed", 0),
				save_result_summary.get("saves_failed", 0),
				alloc_casualties])
			save_log_parts.append("%s → %s: 11e allocation, order %s" % [
				shooter_name, save_data.get("target_unit_name", alloc_target_id),
				str(save_result_summary.get("order_used", []))])
			continue

		DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
		DebugLogger.info(str("║ PROCESSING SAVE RESULT %d" % i))
		DebugLogger.info(str("║ save_result_summary keys: ", save_result_summary.keys()))
		DebugLogger.info(str("║ Has save_results: ", save_result_summary.has("save_results")))
		DebugLogger.info(str("║ Has allocation_history: ", save_result_summary.has("allocation_history")))
		DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

		# Convert allocation_history to save_results format if needed
		var save_results = []
		if save_result_summary.has("save_results"):
			save_results = save_result_summary.save_results
		elif save_result_summary.has("allocation_history"):
			# Convert allocation_history format to save_results format
			DebugLogger.info("║ Converting allocation_history to save_results format")
			for alloc in save_result_summary.allocation_history:
				save_results.append({
					"saved": alloc.get("saved", false),
					"model_id": alloc.get("model_id", ""),
					"model_index": alloc.get("model_index", 0),  # CRITICAL: RulesEngine needs this!
					"roll": alloc.get("roll", 0),
					"damage": alloc.get("damage", 0),
					"model_destroyed": alloc.get("model_destroyed", false)
				})
			DebugLogger.info(str("║ Converted %d allocation entries to save_results" % save_results.size()))

		# DEVASTATING WOUNDS (PRP-012): Get devastating damage from save_result_summary
		var devastating_damage = save_result_summary.get("devastating_damage", 0)
		if devastating_damage > 0:
			DebugLogger.info(str("║ DEVASTATING WOUNDS: %d damage to apply (unsaveable)" % devastating_damage))
			# Update save_data with devastating damage for apply_save_damage
			save_data["devastating_damage"] = devastating_damage

		# Apply damage using RulesEngine (with RNG for Feel No Pain rolls)
		var fnp_rng = RulesEngine.RNGService.new(pas_seed)  # Issue #329: forward seed
		var damage_result = RulesEngine.apply_save_damage(
			save_results,
			save_data,
			game_state_snapshot,
			-1,
			fnp_rng
		)

		# Collect diffs
		all_diffs.append_array(damage_result.diffs)
		total_casualties += damage_result.casualties

		# Check if bodyguard unit was destroyed — detach characters if needed
		if damage_result.casualties > 0:
			var target_unit_id_for_check = save_data.get("target_unit_id", "")
			if target_unit_id_for_check != "":
				CharacterAttachmentManager.check_bodyguard_destroyed(target_unit_id_for_check)

		# Log results
		var target_name = save_data.get("target_unit_name", "Unknown")
		var saved_count = save_result_summary.get("saves_passed", 0)
		var failed_count = save_result_summary.get("saves_failed", 0)

		# Fall back to counting if not in summary
		if saved_count == 0 and failed_count == 0:
			for sr in save_results:
				if sr.get("saved", false):
					saved_count += 1
				else:
					failed_count += 1

		log_phase_message("%s: %d saves passed, %d failed → %d casualties" % [
			target_name,
			saved_count,
			failed_count,
			damage_result.casualties
		])

		# Build verbose save log with dice details
		var verbose_save_parts = ["%s → %s" % [shooter_name, target_name]]
		var weapon_for_log = save_data.get("weapon_name", "")
		if weapon_for_log != "":
			verbose_save_parts[0] += " (%s)" % weapon_for_log
		var save_rolls_for_log = []
		for sr in save_results:
			if sr.has("roll"):
				save_rolls_for_log.append(sr.get("roll", 0))
		var save_threshold_for_log = save_data.get("base_save", 7)
		var ap_for_log = save_data.get("ap", 0)
		var profiles_for_log = save_data.get("model_save_profiles", [])
		var effective_save_for_log = save_threshold_for_log
		var using_invuln_for_log = false
		if not profiles_for_log.is_empty():
			effective_save_for_log = profiles_for_log[0].get("save_needed", 7)
			using_invuln_for_log = profiles_for_log[0].get("using_invuln", false)
		var save_type_str = "Invuln %d+" % effective_save_for_log if using_invuln_for_log else "Save %d+ (AP-%d)" % [effective_save_for_log, ap_for_log]
		if not save_rolls_for_log.is_empty():
			verbose_save_parts.append("%s [%s]: %d passed, %d failed" % [
				save_type_str,
				", ".join(save_rolls_for_log.map(func(r): return str(r))),
				saved_count, failed_count])
		else:
			verbose_save_parts.append("%s: %d passed, %d failed" % [save_type_str, saved_count, failed_count])

		# Include FNP info
		var fnp_prevented_total = damage_result.get("fnp_prevented", 0)
		if fnp_prevented_total > 0:
			verbose_save_parts.append("FNP prevented %d" % fnp_prevented_total)
		# Include devastating wounds info
		if devastating_damage > 0:
			verbose_save_parts.append("%d DEVASTATING damage (no save)" % devastating_damage)

		verbose_save_parts.append("%d slain" % damage_result.casualties)
		save_log_parts.append(" - ".join(verbose_save_parts))

		# Build save dice block for dice log (so both players can see save rolls)
		var save_rolls_raw = []
		for sr in save_results:
			if sr.has("roll"):
				save_rolls_raw.append(sr.get("roll", 0))

		if not save_rolls_raw.is_empty():
			var ap = save_data.get("ap", 0)
			var base_save = save_data.get("base_save", 7)
			# Get the effective save threshold from the first model's profile
			var save_threshold = 7
			var using_invuln = false
			var profiles = save_data.get("model_save_profiles", [])
			if not profiles.is_empty():
				save_threshold = profiles[0].get("save_needed", 7)
				using_invuln = profiles[0].get("using_invuln", false)

			var save_dice_block = {
				"context": "save_roll",
				"threshold": str(save_threshold) + "+",
				"rolls_raw": save_rolls_raw,
				"successes": saved_count,
				"failed": failed_count,
				"ap": ap,
				"original_save": base_save,
				"using_invuln": using_invuln,
				"weapon_name": save_data.get("weapon_name", ""),
				"target_unit_name": target_name
			}
			save_dice_blocks.append(save_dice_block)
			dice_log.append(save_dice_block)
			emit_signal("dice_rolled", save_dice_block)
			DebugLogger.info(str("ShootingPhase: Emitted save_roll dice block - %d rolls, %d passed, %d failed" % [save_rolls_raw.size(), saved_count, failed_count]))

		# FEEL NO PAIN: Emit FNP dice blocks from RulesEngine batch path
		# T5-MP5: Append to save_dice_blocks so the FNP dice are included in the
		# APPLY_SAVES result["dice"] payload and re-emitted on the remote peer.
		var fnp_rolls_from_engine = damage_result.get("fnp_rolls", [])
		for fnp_block in fnp_rolls_from_engine:
			var fnp_dice_block = {
				"context": "feel_no_pain",
				"threshold": str(fnp_block.get("fnp_value", 0)) + "+",
				"rolls_raw": fnp_block.get("rolls", []),
				"fnp_value": fnp_block.get("fnp_value", 0),
				"wounds_prevented": fnp_block.get("wounds_prevented", 0),
				"wounds_remaining": fnp_block.get("wounds_remaining", 0),
				"total_wounds": fnp_block.get("total_wounds", 0),
				"source": fnp_block.get("source", ""),
				"target_unit_name": target_name
			}
			dice_log.append(fnp_dice_block)
			save_dice_blocks.append(fnp_dice_block)
			emit_signal("dice_rolled", fnp_dice_block)
			DebugLogger.info(str("ShootingPhase: Emitted feel_no_pain dice block - %d prevented / %d total" % [fnp_block.get("wounds_prevented", 0), fnp_block.get("total_wounds", 0)]))

		# FEEL NO PAIN: Also collect FNP data from WoundAllocationOverlay allocation_history
		var fnp_rolls_from_overlay = []
		if save_result_summary.has("allocation_history"):
			for alloc in save_result_summary.allocation_history:
				var alloc_fnp_rolls = alloc.get("fnp_rolls", [])
				if not alloc_fnp_rolls.is_empty():
					fnp_rolls_from_overlay.append_array(alloc_fnp_rolls)
			if not fnp_rolls_from_overlay.is_empty():
				var fnp_val = save_result_summary.allocation_history[0].get("fnp_value", 0)
				var total_prevented = 0
				for alloc in save_result_summary.allocation_history:
					total_prevented += alloc.get("fnp_prevented", 0)
				var fnp_overlay_block = {
					"context": "feel_no_pain",
					"threshold": str(fnp_val) + "+",
					"rolls_raw": fnp_rolls_from_overlay,
					"fnp_value": fnp_val,
					"wounds_prevented": total_prevented,
					"wounds_remaining": fnp_rolls_from_overlay.size() - total_prevented,
					"total_wounds": fnp_rolls_from_overlay.size(),
					"source": "interactive_saves",
					"target_unit_name": target_name
				}
				dice_log.append(fnp_overlay_block)
				# T5-MP5: Include in save_dice_blocks for remote-player sync
				save_dice_blocks.append(fnp_overlay_block)
				emit_signal("dice_rolled", fnp_overlay_block)
				DebugLogger.info(str("ShootingPhase: Emitted feel_no_pain dice block from overlay - %d prevented / %d total" % [total_prevented, fnp_rolls_from_overlay.size()]))

	# HAZARDOUS (T2-3): Process Hazardous self-damage after saves resolve
	var hazard_results_for_log: Array = []
	if not pending_hazardous_weapons.is_empty():
		DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
		DebugLogger.info(str("║ HAZARDOUS CHECK — Processing %d hazardous weapon(s)" % pending_hazardous_weapons.size()))
		DebugLogger.info("╚═══════════════════════════════════════════════════════════════")
		var haz_rng = RulesEngine.RNGService.new(pas_seed)  # Issue #329: forward seed
		for haz_weapon in pending_hazardous_weapons:
			var haz_result = RulesEngine.resolve_hazardous_check(
				active_shooter_id,
				haz_weapon.get("weapon_id", ""),
				haz_weapon.get("models_that_fired", 0),
				game_state_snapshot,
				haz_rng
			)
			if haz_result.hazardous_triggered:
				all_diffs.append_array(haz_result.diffs)
			for haz_dice in haz_result.dice:
				dice_log.append(haz_dice)
				# T5-MP5: Include hazardous dice in save_dice_blocks so remote
				# player sees the post-save hazardous self-damage rolls in real time
				save_dice_blocks.append(haz_dice)
				emit_signal("dice_rolled", haz_dice)
			if haz_result.log_text:
				log_phase_message(haz_result.log_text)
			# LV2-G1: logged after this weapon's combat card (below).
			hazard_results_for_log.append(haz_result)
		pending_hazardous_weapons.clear()

	# ONE SHOT (T4-2): Include one-shot diffs in save result changes
	if not pending_one_shot_diffs.is_empty():
		all_diffs.append_array(pending_one_shot_diffs)
		pending_one_shot_diffs.clear()

	# T7-53: Emit shooting_damage_applied signal for floating damage numbers
	# This fires BEFORE diffs are applied by BasePhase.execute_action, allowing
	# handlers to read pre-damage values from GameState (same pattern as FightPhase.attacks_resolved)
	if not all_diffs.is_empty():
		emit_signal("shooting_damage_applied", active_shooter_id, all_diffs)
		DebugLogger.info(str("[ShootingPhase] T7-53: Emitted shooting_damage_applied with %d diffs" % all_diffs.size()))

	# Build combined save log text for game event log
	var save_log_text = ", ".join(save_log_parts)

	# VERBOSE COMBAT LOG: Emit save and result details
	_emit_verbose_combat_log(active_shooter_id, [], save_dice_blocks, total_casualties, "shooting_saves")
	# LV2-G1: the shooter's [HAZARDOUS] roll(s) follow the shot's combat card —
	# before, a failed roll's mortal wounds never reached the Game Log.
	for haz_logged in hazard_results_for_log:
		_log_hazard_to_game_log(haz_logged)

	# Check if we're in sequential weapon resolution mode.
	# CRITICAL: "sequential_staged" (the non-networked hit→wound→saves staged flow)
	# MUST take the sequential path too. It was missing here, so in single-player
	# the first weapon that caused wounds would fall into the single-weapon
	# completion branch below, emit next_weapon_confirmation_required([]) and
	# silently DROP every remaining assignment — "shooting at two targets only
	# rolls the first one".
	var mode = resolution_state.get("mode", "")
	var is_sequential = (mode == "sequential" or mode == "sequential_staged" or mode == "fast")

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ MODE CHECK IN _process_apply_saves")
	DebugLogger.info(str("║ resolution_state keys: ", resolution_state.keys()))
	DebugLogger.info(str("║ mode from resolution_state: '", mode, "'"))
	DebugLogger.info(str("║ is_sequential: ", is_sequential))
	DebugLogger.info(str("║ active_shooter_id: ", active_shooter_id))
	DebugLogger.info(str("║ confirmed_assignments.size(): ", confirmed_assignments.size()))
	DebugLogger.info("║")
	DebugLogger.info("║ PATH DECISION:")
	if is_sequential:
		DebugLogger.info("║ → Will take SEQUENTIAL path (lines 1401-1508)")
	else:
		DebugLogger.info("║ → Will take SINGLE WEAPON path (lines 1510+)")
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	if is_sequential:
		# Sequential mode - record results and PAUSE for attacker to confirm next weapon
		var current_index = resolution_state.get("current_index", 0)
		var weapon_order = resolution_state.get("weapon_order", [])

		DebugLogger.info("========================================")
		DebugLogger.info("ShootingPhase: APPLY_SAVES complete in sequential mode")
		DebugLogger.info(str("ShootingPhase: current_index = %d, weapon_order.size() = %d" % [current_index, weapon_order.size()]))

		if current_index < weapon_order.size():
			var weapon_id = weapon_order[current_index].get("weapon_id", "")
			var current_assignment_data = weapon_order[current_index]
			DebugLogger.info(str("ShootingPhase: Completed weapon %d: %s" % [current_index + 1, weapon_id]))

			# Calculate saves_failed from save results
			var saves_failed = 0
			for save_result in save_results_list:
				saves_failed += save_result.get("saves_failed", 0)

			# Get dice data from resolution_state (stored when weapon was resolved)
			var dice_data = resolution_state.get("last_weapon_dice_data", [])
			var hit_data = resolution_state.get("last_weapon_hit_data", {})
			var wound_data = resolution_state.get("last_weapon_wound_data", {})
			var target_unit_name = resolution_state.get("last_weapon_target_name", "Unknown")
			var target_unit_id = resolution_state.get("last_weapon_target_id", "")

			var hits = hit_data.get("successes", 0)
			var total_attacks = hit_data.get("total", 0)

			# Torrent/auto-hit weapons have empty hit_data — count from dice_data entries
			if hits == 0 and not dice_data.is_empty():
				for dice_entry in dice_data:
					if dice_entry is Dictionary and dice_entry.get("context", "") == "auto_hit":
						hits += dice_entry.get("successes", 0)
						total_attacks += dice_entry.get("total_attacks", 0)

			# P1-11: Track hits for Sanctified Flames
			if hits > 0 and target_unit_id != "":
				_targets_hit_by_shooter[target_unit_id] = _targets_hit_by_shooter.get(target_unit_id, 0) + hits
				DebugLogger.info(str("ShootingPhase: P1-11 Sanctified Flames tracking: %d hit(s) on %s (total: %d)" % [hits, target_unit_id, _targets_hit_by_shooter[target_unit_id]]))

			# Record completed weapon with full data
			resolution_state.completed_weapons.append({
				"weapon_id": weapon_id,
				"target_unit_id": target_unit_id,
				"target_unit_name": target_unit_name,
				"wounds": pending_save_data[0].get("wounds_to_save", 0) if not pending_save_data.is_empty() else 0,
				"casualties": total_casualties,
				"hits": hits,
				"total_attacks": total_attacks,
				"saves_failed": saves_failed,
				"dice_rolls": dice_data,
				"hit_data": hit_data,
				"wound_data": wound_data
			})

			# Move to next weapon INDEX
			resolution_state.current_index += 1
			resolution_state.awaiting_saves = false

			# Clear pending save data
			pending_save_data.clear()

			DebugLogger.info(str("ShootingPhase: Moving to next weapon index: %d" % resolution_state.current_index))
			DebugLogger.info(str("ShootingPhase: Weapons remaining: %d" % (weapon_order.size() - resolution_state.current_index)))

			# ALWAYS PAUSE for attacker to confirm (even if last weapon)
			# Wait for attacker to confirm before continuing or completing
			DebugLogger.info("ShootingPhase: ⚠ PAUSING - Waiting for attacker to confirm next weapon")
			DebugLogger.info(str("ShootingPhase: Remaining weapons: ", weapon_order.size() - resolution_state.current_index))

			# Determine which target units are fully destroyed by the pending diffs
			# (diffs haven't been applied to game state yet, so compute from diff + snapshot)
			var _models_killed_by_unit = {}
			for diff in all_diffs:
				var dpath = diff.get("path", "")
				if dpath.ends_with(".alive") and diff.get("value") == false:
					var dparts = dpath.split(".")
					if dparts.size() >= 2 and dparts[0] == "units":
						var uid = dparts[1]
						_models_killed_by_unit[uid] = _models_killed_by_unit.get(uid, 0) + 1
			var _targets_destroyed_by_diffs = {}
			for uid in _models_killed_by_unit:
				var tunit = get_unit(uid)
				var alive_count = 0
				for m in tunit.get("models", []):
					if m.get("alive", true):
						alive_count += 1
				if alive_count > 0 and alive_count <= _models_killed_by_unit[uid]:
					_targets_destroyed_by_diffs[uid] = true
					DebugLogger.info(str("ShootingPhase: Target unit %s fully destroyed by current saves — will skip remaining weapons targeting it" % uid))

			# Build remaining weapons with validation (may be empty array if this is the last weapon)
			# Filter out weapons targeting units destroyed by the current save diffs
			var remaining_weapons = []

			DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
			DebugLogger.info("║ BUILDING REMAINING WEAPONS (after saves)")
			DebugLogger.info(str("║ weapon_order.size() = %d" % weapon_order.size()))
			DebugLogger.info(str("║ current_index = %d" % resolution_state.current_index))
			DebugLogger.info(str("║ Expected remaining = %d" % (weapon_order.size() - resolution_state.current_index)))

			for i in range(resolution_state.current_index, weapon_order.size()):
				var weapon = weapon_order[i]
				var weapon_target_id = weapon.get("target_unit_id", "")

				# Filter out weapons whose target was just destroyed (for UI display only)
				# Actual skipping and index management is handled by _resolve_next_weapon
				if _targets_destroyed_by_diffs.has(weapon_target_id):
					var skipped_wid = weapon.get("weapon_id", "")
					var skipped_wp = RulesEngine.get_weapon_profile(skipped_wid)
					DebugLogger.info(str("║ Filtered weapon %d: %s (target %s destroyed)" % [i, skipped_wp.get("name", skipped_wid), weapon_target_id]))
					continue

				remaining_weapons.append(weapon)

				# Validate weapon structure
				var remaining_weapon_id = weapon.get("weapon_id", "")
				if remaining_weapon_id == "":
					push_error("ShootingPhase: Weapon at index %d has EMPTY weapon_id!" % i)
					DebugLogger.info(str("║ ⚠️  WARNING: Weapon %d has no weapon_id" % i))
					DebugLogger.info(str("║   Full weapon object: %s" % str(weapon)))
				else:
					DebugLogger.info(str("║ Added weapon %d: %s" % [i, remaining_weapon_id]))

			DebugLogger.info(str("║ Total remaining weapons: %d" % remaining_weapons.size()))
			if remaining_weapons.is_empty():
				DebugLogger.info("║ ✓ All remaining weapons skipped or this is the FINAL weapon")
			DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

			# AUTO-COMPLETE: If all remaining weapons target destroyed units, skip them
			# and complete shooting automatically (no dialog needed)
			if remaining_weapons.is_empty() and not _targets_destroyed_by_diffs.is_empty():
				DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
				DebugLogger.info("║ AUTO-COMPLETE: All remaining targets destroyed — skipping weapons")

				# Record skipped weapons in completed_weapons
				for i in range(resolution_state.current_index, weapon_order.size()):
					var skipped_assignment = weapon_order[i]
					var skipped_wid = skipped_assignment.get("weapon_id", "")
					var skipped_tid = skipped_assignment.get("target_unit_id", "")
					var skipped_wp = RulesEngine.get_weapon_profile(skipped_wid)
					var skipped_wname = skipped_wp.get("name", skipped_wid)
					var skipped_tname = get_unit(skipped_tid).get("meta", {}).get("name", skipped_tid)
					DebugLogger.info(str("║ Skipped: %s → %s (target destroyed)" % [skipped_wname, skipped_tname]))
					log_phase_message("Skipped %s — target %s destroyed" % [skipped_wname, skipped_tname])
					resolution_state.completed_weapons.append({
						"weapon_id": skipped_wid,
						"target_unit_id": skipped_tid,
						"target_unit_name": skipped_tname,
						"wounds": 0,
						"casualties": 0,
						"hits": 0,
						"total_attacks": 0,
						"saves_failed": 0,
						"dice_rolls": [],
						"hit_data": {},
						"wound_data": {},
						"skipped_target_destroyed": true
					})

				# Mark shooter as done
				var shooter_id = active_shooter_id
				all_diffs.append({
					"op": "set",
					"path": "units.%s.flags.has_shot" % active_shooter_id,
					"value": true
				})
				# 13.09 HIDDEN: real ranged attacks were made (they destroyed
				# every remaining target) — stamp the turn index.
				all_diffs.append(_hidden_shot_stamp(active_shooter_id))
				units_that_shot.append(active_shooter_id)

				# T5-UX9: capture before clearing
				_record_completed_weapons_to_phase_log(shooter_id)

				# Clear state
				active_shooter_id = ""
				confirmed_assignments.clear()
				resolution_state.clear()
				pending_save_data.clear()
				_targets_hit_by_shooter.clear()

				# Emit signal to clear visuals
				emit_signal("shooting_resolved", shooter_id, "", {"casualties": total_casualties})

				DebugLogger.info("║ Shooting auto-completed — all remaining targets destroyed")
				DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

				return create_result(true, all_diffs, "Sequential weapon resolution complete (remaining targets destroyed)", {
					"dice": save_dice_blocks,
					"log_text": save_log_text
				})

			# FAST ROLL (auto-continue): no between-weapon pause — after this
			# batch's diffs are applied by BasePhase, continue the sequence as
			# if the attacker pressed "Continue to Next Weapon". Deferred so the
			# casualties from THIS weapon land in GameState before the next
			# weapon rolls (blast/rapid-fire model counts, destroyed-target skip).
			if resolution_state.get("auto_continue", false) and not remaining_weapons.is_empty():
				DebugLogger.info("ShootingPhase: FAST ROLL auto-continue — deferring CONTINUE_SEQUENCE")
				call_deferred("_auto_continue_next_weapon")
				return create_result(true, all_diffs, "Weapon %d complete — fast-rolling next weapon" % (current_index + 1), {
					"dice": save_dice_blocks,
					"log_text": save_log_text
				})

			# Get last weapon result for dialog display
			var last_weapon_result = _get_last_weapon_result()

			# Emit signal to show confirmation dialog to attacker
			# NOTE: remaining_weapons may be EMPTY if this is the final weapon
			DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
			DebugLogger.info("║ EMITTING next_weapon_confirmation_required SIGNAL")
			DebugLogger.info(str("║ remaining_weapons.size(): ", remaining_weapons.size()))
			DebugLogger.info(str("║ current_index: ", resolution_state.current_index))
			DebugLogger.info(str("║ last_weapon_result keys: ", last_weapon_result.keys()))
			DebugLogger.info("╚═══════════════════════════════════════════════════════════════")
			emit_signal("next_weapon_confirmation_required", remaining_weapons, resolution_state.current_index, last_weapon_result)

			# Return success with pause indicator for multiplayer sync
			var result = create_result(true, all_diffs, "Weapon %d complete - awaiting confirmation" % (current_index + 1), {
				"sequential_pause": true,
				"current_weapon_index": resolution_state.current_index,
				"total_weapons": weapon_order.size(),
				"dice": save_dice_blocks,
				"weapons_remaining": weapon_order.size() - resolution_state.current_index,
				"remaining_weapons": remaining_weapons,
				"last_weapon_result": last_weapon_result,
				"log_text": save_log_text
			})

			DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
			DebugLogger.info("║ APPLY_SAVES RESULT (with sequential_pause)")
			DebugLogger.info(str("║ result.sequential_pause: ", result.get("sequential_pause", false)))
			DebugLogger.info(str("║ result.remaining_weapons.size(): ", result.get("remaining_weapons", []).size()))
			DebugLogger.info(str("║ result.current_weapon_index: ", result.get("current_weapon_index", -1)))
			DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

			return result

	# Normal mode (single weapon) or fast mode - show results dialog before completing
	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ 🎯 SINGLE WEAPON PATH REACHED! (Line 1548)")
	DebugLogger.info(str("║ mode: '", mode, "'"))
	DebugLogger.info(str("║ total_casualties: ", total_casualties))
	DebugLogger.info(str("║ confirmed_assignments.size(): ", confirmed_assignments.size()))
	DebugLogger.info(str("║ all_diffs.size(): ", all_diffs.size()))
	DebugLogger.info("║")
	DebugLogger.info("║ NOW: Building last_weapon_result...")
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	# Build last weapon result for single weapon case
	var last_weapon_result = {}
	if not confirmed_assignments.is_empty():
		DebugLogger.info("║ ✓ confirmed_assignments NOT empty, building result...")
		var assignment = confirmed_assignments[0]
		var weapon_id = assignment.get("weapon_id", "")
		DebugLogger.info(str("║   weapon_id: ", weapon_id))

		var weapon_profile = RulesEngine.get_weapon_profile(weapon_id)
		DebugLogger.info(str("║   weapon_name: ", weapon_profile.get("name", weapon_id)))

		var target_unit_id = assignment.get("target_unit_id", "")
		var target_unit = get_unit(target_unit_id)
		DebugLogger.info(str("║   target: ", target_unit.get("meta", {}).get("name", target_unit_id)))

		# Build result from save data
		var saves_failed = 0
		for save_result in save_results_list:
			saves_failed += save_result.get("saves_failed", 0)

		# T4-15: Retrieve hit/wound data from resolution_state (stored during _process_resolve_shooting)
		var sw_dice_data = resolution_state.get("last_weapon_dice_data", [])
		var sw_hit_data = resolution_state.get("last_weapon_hit_data", {})
		var sw_wound_data = resolution_state.get("last_weapon_wound_data", {})
		var sw_hits = sw_hit_data.get("successes", 0)
		var sw_total_attacks = sw_hit_data.get("total", 0)

		# Torrent/auto-hit weapons have empty hit_data — count from dice_data entries
		if sw_hits == 0 and not sw_dice_data.is_empty():
			for dice_entry in sw_dice_data:
				if dice_entry is Dictionary and dice_entry.get("context", "") == "auto_hit":
					sw_hits += dice_entry.get("successes", 0)
					sw_total_attacks += dice_entry.get("total_attacks", 0)

		DebugLogger.info(str("║   saves_failed: ", saves_failed))
		DebugLogger.info(str("║   casualties: ", total_casualties))
		DebugLogger.info(str("║   hits: ", sw_hits, " / ", sw_total_attacks))

		last_weapon_result = {
			"weapon_id": weapon_id,
			"weapon_name": weapon_profile.get("name", weapon_id),
			"target_unit_id": target_unit_id,
			"target_unit_name": target_unit.get("meta", {}).get("name", target_unit_id),
			"hits": sw_hits,
			"wounds": pending_save_data[0].get("wounds_to_save", 0) if not pending_save_data.is_empty() else 0,
			"saves_failed": saves_failed,
			"casualties": total_casualties,
			"total_attacks": sw_total_attacks,
			"dice_rolls": sw_dice_data,
			"hit_data": sw_hit_data,
			"wound_data": sw_wound_data
		}
		DebugLogger.info("║ ✓ last_weapon_result built successfully!")

		# P1-11: Track hits for Sanctified Flames (single-weapon path)
		if sw_hits > 0 and target_unit_id != "":
			_targets_hit_by_shooter[target_unit_id] = _targets_hit_by_shooter.get(target_unit_id, 0) + sw_hits
			DebugLogger.info(str("ShootingPhase: P1-11 Sanctified Flames tracking: %d hit(s) on %s (total: %d)" % [sw_hits, target_unit_id, _targets_hit_by_shooter[target_unit_id]]))

		# Record completed weapon so phase_shooting_log captures single-weapon results
		if not resolution_state.has("completed_weapons"):
			resolution_state["completed_weapons"] = []
		resolution_state.completed_weapons.append({
			"weapon_id": weapon_id,
			"target_unit_id": target_unit_id,
			"target_unit_name": target_unit.get("meta", {}).get("name", target_unit_id),
			"wounds": pending_save_data[0].get("wounds_to_save", 0) if not pending_save_data.is_empty() else 0,
			"casualties": total_casualties,
			"hits": sw_hits,
			"total_attacks": sw_total_attacks,
			"saves_failed": saves_failed,
			"dice_rolls": sw_dice_data,
			"hit_data": sw_hit_data,
			"wound_data": sw_wound_data
		})
	else:
		DebugLogger.info("║ ⚠️  WARNING: confirmed_assignments is EMPTY!")

	# This batch is fully applied — drop it. The sequential branch above already
	# does this; the single-weapon branch did not, so pending_save_data stayed
	# populated after the defender had finished allocating. That entry is what
	# AIPlayer._human_defender_window_pending() reads, so an AI attacker went on
	# idling as though the human were still rolling saves and the phase never
	# advanced. Cleared AFTER last_weapon_result / completed_weapons, both of
	# which read pending_save_data[0] for the wound count.
	pending_save_data.clear()

	# Emit signal with EMPTY remaining_weapons (signals completion)
	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ 📡 EMITTING next_weapon_confirmation_required SIGNAL")
	DebugLogger.info("║ Signal name: 'next_weapon_confirmation_required'")
	DebugLogger.info("║ Parameter 1 (remaining_weapons): [] (empty array)")
	DebugLogger.info("║ Parameter 2 (current_index): 0")
	DebugLogger.info(str("║ Parameter 3 (last_weapon_result): ", last_weapon_result))
	DebugLogger.info("║")
	DebugLogger.info("║ This signal should trigger ShootingController to show dialog!")
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	emit_signal("next_weapon_confirmation_required", [], 0, last_weapon_result)

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ ✅ Signal emitted successfully!")
	DebugLogger.info("║ Returning result with sequential_pause=true")
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	# Return with pause indicator (completion will happen when user clicks "Complete Shooting")
	var result = create_result(true, all_diffs, "Single weapon complete - awaiting confirmation", {
		"sequential_pause": true,
		"remaining_weapons": [],
		"last_weapon_result": last_weapon_result,
		"current_weapon_index": 0,
		"total_weapons": 1,
		"dice": save_dice_blocks,
		"log_text": save_log_text
	})

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ 🎬 SINGLE WEAPON PATH COMPLETE")
	DebugLogger.info("║ Returning to caller with result")
	DebugLogger.info("║ User should now see NextWeaponDialog")
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	return result

# FAST ROLL: drive the next weapon through the normal action pipeline so
# validation, diff application and signals flow exactly like a manual
# "Continue to Next Weapon" press. Deferred from _process_apply_saves /
# _finish_weapon_resolution so the current batch's diffs land in GameState
# before the next weapon rolls.
func _auto_continue_next_weapon() -> void:
	if resolution_state.get("mode", "") != "sequential_staged":
		return
	if not resolution_state.get("auto_continue", false):
		return
	var idx = int(resolution_state.get("current_index", 0))
	var order = resolution_state.get("weapon_order", [])
	if idx >= order.size():
		return
	DebugLogger.info("ShootingPhase: FAST ROLL auto-continue — executing CONTINUE_SEQUENCE (weapon %d of %d)" % [idx + 1, order.size()])
	execute_action({"type": "CONTINUE_SEQUENCE"})

func _process_continue_sequence(action: Dictionary) -> Dictionary:
	"""Process continuation to next weapon in sequential mode"""
	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ SHOOTING PHASE: _process_continue_sequence CALLED")
	DebugLogger.info("║")

	var payload = action.get("payload", {})
	var updated_weapon_order = payload.get("weapon_order", [])

	DebugLogger.info("║ CURRENT STATE:")
	DebugLogger.info(str("║   resolution_state.current_index: ", resolution_state.get("current_index", 0)))
	DebugLogger.info(str("║   resolution_state.weapon_order.size(): ", resolution_state.get("weapon_order", []).size()))
	DebugLogger.info(str("║   resolution_state.completed_weapons: ", resolution_state.get("completed_weapons", []).size()))
	DebugLogger.info("║")
	DebugLogger.info("║ ACTION PAYLOAD:")
	DebugLogger.info(str("║   updated_weapon_order provided: ", not updated_weapon_order.is_empty()))
	DebugLogger.info(str("║   updated_weapon_order.size(): ", updated_weapon_order.size()))
	if not updated_weapon_order.is_empty():
		DebugLogger.info("║   First 3 weapons in updated order:")
		for i in range(min(3, updated_weapon_order.size())):
			DebugLogger.info(str("║     %d: %s" % [i, updated_weapon_order[i].get("weapon_id", "UNKNOWN")]))
	DebugLogger.info("║")

	# If attacker provided a new weapon order (reordering), update it
	if not updated_weapon_order.is_empty():
		DebugLogger.info("║ REORDERING: Attacker provided new weapon order")
		# Keep completed weapons, update remaining
		var current_index = resolution_state.get("current_index", 0)
		var original_order = resolution_state.get("weapon_order", [])

		DebugLogger.info(str("║   current_index: ", current_index))
		DebugLogger.info(str("║   original_order.size(): ", original_order.size()))
		DebugLogger.info(str("║   Keeping first %d completed weapons" % current_index))

		# Build new complete order: completed weapons + reordered remaining weapons
		var new_complete_order = []
		for i in range(current_index):
			if i < original_order.size():
				new_complete_order.append(original_order[i])
				DebugLogger.info(str("║   Kept completed weapon %d: %s" % [i, original_order[i].get("weapon_id", "UNKNOWN")]))

		DebugLogger.info(str("║   Appending %d reordered weapons" % updated_weapon_order.size()))
		new_complete_order.append_array(updated_weapon_order)

		DebugLogger.info("║")
		DebugLogger.info(str("║   NEW COMPLETE ORDER (%d weapons):" % new_complete_order.size()))
		for i in range(min(5, new_complete_order.size())):
			var status = "✓ COMPLETED" if i < current_index else "⏳ PENDING"
			DebugLogger.info(str("║     %d: %s %s" % [i, new_complete_order[i].get("weapon_id", "UNKNOWN"), status]))
		if new_complete_order.size() > 5:
			DebugLogger.info(str("║     ... and %d more weapons" % (new_complete_order.size() - 5)))

		resolution_state.weapon_order = new_complete_order
		DebugLogger.info("║   Updated resolution_state.weapon_order")
	else:
		DebugLogger.info("║ NO REORDERING: Using existing weapon order")

	DebugLogger.info("║")
	DebugLogger.info("║ FINAL STATE BEFORE _resolve_next_weapon():")
	DebugLogger.info(str("║   current_index: ", resolution_state.get("current_index", 0)))
	DebugLogger.info(str("║   weapon_order.size(): ", resolution_state.get("weapon_order", []).size()))
	DebugLogger.info(str("║   Next weapon to resolve: index %d" % resolution_state.get("current_index", 0)))
	if resolution_state.get("current_index", 0) < resolution_state.get("weapon_order", []).size():
		var next_weapon = resolution_state.get("weapon_order", [])[resolution_state.get("current_index", 0)]
		DebugLogger.info(str("║   Next weapon ID: %s" % next_weapon.get("weapon_id", "UNKNOWN")))
	DebugLogger.info("║")
	DebugLogger.info("║ Calling _resolve_next_weapon()...")
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	var next_result = _resolve_next_weapon()

	DebugLogger.info("╔═══════════════════════════════════════════════════════════════")
	DebugLogger.info("║ _resolve_next_weapon() RETURNED")
	DebugLogger.info(str("║   success: ", next_result.get("success", false)))
	DebugLogger.info(str("║   log_text: ", next_result.get("log_text", "")))
	if next_result.has("sequential_pause"):
		DebugLogger.info(str("║   sequential_pause: ", next_result.get("sequential_pause", false)))
		DebugLogger.info(str("║   weapons_remaining: ", next_result.get("weapons_remaining", 0)))
	DebugLogger.info("╚═══════════════════════════════════════════════════════════════")

	return next_result


# ============================================================================
# VERBOSE COMBAT LOG — Detailed dice breakdown for Game Event Log
# ============================================================================

## LV2-G1: a [HAZARDOUS] roll (native or granted, e.g. VINDICTIVE ARTILLERISTS'
## overcharge) gets its own Game Log line, attributed to the shooter's owner:
## "P1: Hazardous: Mek Gunz (Smasha Gun) rolled 2 — failed (1-2): 3 mortal wounds".
## Before, it reached only the debug log, so a failed roll's mortal wounds
## were invisible to the player.
func _log_hazard_to_game_log(haz_result: Dictionary) -> void:
	var line := str(haz_result.get("game_log_text", ""))
	if line == "":
		return
	var haz_owner := int(get_unit(active_shooter_id).get("owner", get_current_player()))
	GameEventLog.add_player_entry(haz_owner, line)
	log_phase_message("[LV2-G1] Game Log: P%d: %s" % [haz_owner, line])

func _emit_verbose_combat_log(shooter_id: String, dice_data: Array, save_dice_blocks: Array, casualties: int, phase_type: String) -> void:
	"""Emit detailed combat log entries to GameEventLog from dice_data and save results.
	Called after combat resolution completes (hits+wounds+saves all done)."""
	var shooter_unit = game_state_snapshot.get("units", {}).get(shooter_id, {})
	var shooter_name = shooter_unit.get("meta", {}).get("name", shooter_id)
	var player = get_current_player()

	# Extract hit and wound dice blocks
	for dice_block in dice_data:
		var context = dice_block.get("context", "")
		if context == "resolution_start":
			continue

		if context == "to_hit" or context == "hit_roll":
			_emit_hit_detail_log(shooter_name, dice_block, player)
		elif context == "auto_hit":
			_emit_torrent_detail_log(shooter_name, dice_block, player)
		elif context == "to_wound" or context == "wound_roll":
			_emit_wound_detail_log(dice_block, player)
		elif context == "grot_shields" and str(dice_block.get("message", "")) != "":
			# GROT SHIELDS (Codex: Orks 11e): say in the Game Log why those hits
			# never reached the wound roll (r3:F6).
			GameEventLog.add_combat_result("  " + str(dice_block.get("message", "")))

	# Save dice blocks ("save" is the engine-internal 11e context; the
	# normalized blocks use "save_roll")
	var saves_passed := 0
	var saves_rolled := 0
	for save_block in save_dice_blocks:
		var scontext = save_block.get("context", "")
		if scontext == "save_roll" or scontext == "save":
			_emit_save_detail_log(save_block)
			saves_passed += int(save_block.get("successes", 0))
			saves_rolled += int(save_block.get("successes", 0)) + int(save_block.get("failed", save_block.get("fails", 0)))
		elif scontext == "feel_no_pain":
			_emit_fnp_detail_log(save_block)

	# Final result line — only show after saves are resolved (not for hit/wound-only phases)
	if phase_type == "shooting_saves":
		# Carry the save tally into the result so "No models destroyed" says WHY
		# nothing died instead of leaving the player to guess.
		var save_tally = ""
		if saves_rolled > 0:
			save_tally = " (%d/%d saves passed)" % [saves_passed, saves_rolled]
		if casualties > 0:
			var _cas_label2 = "model" if casualties == 1 else "models"
			GameEventLog.add_combat_result("  Result: %d %s destroyed%s" % [casualties, _cas_label2, save_tally])
		else:
			GameEventLog.add_combat_result("  Result: No models destroyed%s" % save_tally)

func _emit_hit_detail_log(shooter_name: String, dice_block: Dictionary, player: int) -> void:
	"""Emit detailed hit roll log from a to_hit dice block."""
	var weapon_name = dice_block.get("weapon_name", "")
	var threshold = dice_block.get("threshold", "?")
	var rolls_raw = dice_block.get("rolls_raw", [])
	var rolls_modified = dice_block.get("rolls_modified", [])
	var successes = dice_block.get("successes", 0)
	var base_attacks = dice_block.get("base_attacks", rolls_raw.size())
	var total_attacks = rolls_raw.size()

	# Header - weapon and attack count
	var attacks_desc = "%d attacks" % total_attacks
	# Variable attacks
	if dice_block.get("variable_attacks", false):
		attacks_desc = "%s → %d attacks" % [dice_block.get("attacks_notation", "?"), total_attacks]
	# Rapid fire bonus
	var rf_bonus = dice_block.get("rapid_fire_bonus", 0)
	if rf_bonus > 0:
		attacks_desc += " (incl. +%d Rapid Fire)" % rf_bonus
	# Blast bonus
	var blast_bonus = dice_block.get("blast_bonus_attacks", 0)
	if blast_bonus > 0:
		attacks_desc += " (incl. +%d Blast vs %d models)" % [blast_bonus, dice_block.get("target_model_count", 0)]

	if weapon_name != "":
		GameEventLog.add_combat_detail("  Weapon: %s — %s" % [weapon_name, attacks_desc])

	# Hit rolls line
	var rolls_str = GameEventLog._format_dice_rolls(rolls_raw)
	var hit_line = "  To Hit: needed %s — rolled %s — %d/%d hit" % [threshold, rolls_str, successes, total_attacks]
	GameEventLog.add_combat_detail(hit_line)

	# Modified rolls (if different from raw)
	if not rolls_modified.is_empty() and rolls_modified != rolls_raw:
		GameEventLog.add_combat_detail("    Modified rolls: %s" % GameEventLog._format_dice_rolls(rolls_modified))

	# Hit modifiers description
	var mods_parts = []
	if dice_block.get("heavy_bonus_applied", false):
		mods_parts.append("Heavy +1")
	if dice_block.get("bgnt_penalty_applied", false):
		mods_parts.append("Big Guns Never Tire -1")
	if dice_block.get("indirect_fire_applied", false):
		mods_parts.append("Indirect Fire -1")
	if dice_block.get("conversion_active", false):
		mods_parts.append("Conversion %d+" % dice_block.get("critical_hit_threshold", 6))
	if not mods_parts.is_empty():
		GameEventLog.add_combat_detail("    Hit modifiers: %s" % ", ".join(mods_parts))

	# Rerolls
	var rerolls = dice_block.get("rerolls", [])
	if not rerolls.is_empty():
		var rr_strs = []
		for rr in rerolls:
			rr_strs.append("%d→%d" % [rr.get("original", 0), rr.get("rerolled_to", rr.get("new", 0))])
		GameEventLog.add_combat_detail("    Re-rolls: %s" % ", ".join(rr_strs))

	# Critical hits and special abilities
	var crits = dice_block.get("critical_hits", 0)
	if crits > 0:
		var crit_parts = ["%d critical hit(s)" % crits]
		if dice_block.get("lethal_hits_weapon", false):
			crit_parts.append("Lethal Hits active (crits auto-wound)")
		if dice_block.get("sustained_hits_weapon", false):
			var sh_bonus = dice_block.get("sustained_bonus_hits", 0)
			crit_parts.append("Sustained Hits: +%d bonus hit(s)" % sh_bonus)
		GameEventLog.add_combat_detail("    Criticals: %s" % " | ".join(crit_parts))

func _emit_torrent_detail_log(shooter_name: String, dice_block: Dictionary, player: int) -> void:
	"""Emit log for a Torrent (auto-hit) weapon."""
	var total = dice_block.get("total_attacks", 0)
	GameEventLog.add_combat_detail("  To Hit: Torrent — %d automatic hit(s)" % total)

func _emit_wound_detail_log(dice_block: Dictionary, player: int) -> void:
	"""Emit detailed wound roll log from a to_wound dice block."""
	var threshold = dice_block.get("threshold", "?")
	var rolls_raw = dice_block.get("rolls_raw", [])
	var successes = dice_block.get("successes", 0)
	var total = rolls_raw.size()

	# Auto-wounds from Lethal Hits
	var auto_wounds = dice_block.get("lethal_hits_auto_wounds", 0)
	if auto_wounds > 0:
		GameEventLog.add_combat_detail("  Lethal Hits: %d auto-wound(s) (no roll needed)" % auto_wounds)

	# Wound rolls
	if total > 0:
		var rolls_str = GameEventLog._format_dice_rolls(rolls_raw)
		var wounds_from_rolls = dice_block.get("wounds_from_rolls", successes - auto_wounds)
		var wound_line = "  To Wound: needed %s — rolled %s — %d/%d wounded" % [threshold, rolls_str, wounds_from_rolls, total]
		GameEventLog.add_combat_detail(wound_line)

	# Wound modifiers
	var wound_mod_net = dice_block.get("wound_modifier_net", 0)
	if wound_mod_net != 0:
		GameEventLog.add_combat_detail("    Wound modifier: %+d" % wound_mod_net)

	# Wound rerolls (Twin-linked, etc.)
	var wound_rerolls = dice_block.get("wound_rerolls", [])
	if not wound_rerolls.is_empty():
		var wrr_strs = []
		for wrr in wound_rerolls:
			wrr_strs.append("%d→%d" % [wrr.get("original", 0), wrr.get("rerolled_to", wrr.get("new", 0))])
		var reroll_source = "Twin-linked" if dice_block.get("twin_linked_weapon", false) else "Re-roll"
		GameEventLog.add_combat_detail("    %s: %s" % [reroll_source, ", ".join(wrr_strs)])

	# Anti-keyword
	if dice_block.get("anti_keyword_active", false):
		GameEventLog.add_combat_detail("    Anti-keyword: critical wounds on %d+" % dice_block.get("critical_wound_threshold", 6))

	# Devastating Wounds
	var dw_count = dice_block.get("critical_wounds", 0)
	if dice_block.get("devastating_wounds_weapon", false) and dw_count > 0:
		GameEventLog.add_combat_detail("    DEVASTATING WOUNDS: %d wound(s) bypass saves" % dw_count)

	# Total wounds summary
	GameEventLog.add_combat_detail("  Total wounds caused: %d" % successes)

func _emit_save_detail_log(save_block: Dictionary) -> void:
	"""Emit detailed save roll log from a save_roll dice block."""
	var target_name = save_block.get("target_unit_name", "Unknown")
	var threshold = save_block.get("threshold", "?")
	var rolls_raw = save_block.get("rolls_raw", [])
	var passed = save_block.get("successes", 0)
	var failed = save_block.get("failed", 0)
	var ap = save_block.get("ap", 0)
	var using_invuln = save_block.get("using_invuln", false)
	var weapon_name = save_block.get("weapon_name", "")

	var save_type = ""
	if using_invuln:
		save_type = "Invulnerable Save %s" % threshold
	else:
		# `ap` is stored negative (AP-1 == -1), so "(AP -%d)" printed "AP --1"
		# once the 11e path started reaching this line. Normalise to one "-N"
		# reading regardless of the caller's sign convention.
		var ap_mag = absi(int(ap))
		save_type = "Armour Save %s (AP %s)" % [threshold, ("0" if ap_mag == 0 else "-%d" % ap_mag)]

	var rolls_str = GameEventLog._format_dice_rolls(rolls_raw)
	var save_line = "  %s Saves vs %s: %s — rolled %s — %d passed, %d failed" % [
		target_name, weapon_name, save_type, rolls_str, passed, failed]
	GameEventLog.add_combat_detail(save_line)

func _emit_fnp_detail_log(fnp_block: Dictionary) -> void:
	"""Emit Feel No Pain roll details."""
	var target_name = fnp_block.get("target_unit_name", "Unknown")
	var threshold = fnp_block.get("threshold", "?")
	var rolls_raw = fnp_block.get("rolls_raw", [])
	var prevented = fnp_block.get("wounds_prevented", 0)
	var total = fnp_block.get("total_wounds", 0)

	var rolls_str = GameEventLog._format_dice_rolls(rolls_raw)
	GameEventLog.add_combat_detail("  %s Feel No Pain %s: rolled %s — %d/%d wounds prevented" % [
		target_name, threshold, rolls_str, prevented, total])

func _trigger_unit_animation(unit_id: String, anim_name: String) -> void:
	"""Trigger an animation on all token visuals for a unit."""
	var tl = SceneRefs.token_layer()
	if not tl:
		return
	for child in tl.get_children():
		if child.has_meta("unit_id") and child.get_meta("unit_id") == unit_id:
			if child.has_method("play_animation"):
				child.play_animation(anim_name)
			else:
				for grandchild in child.get_children():
					if grandchild.has_method("play_animation"):
						grandchild.play_animation(anim_name)

# ============================================================================
# STRATAGEM HANDLING (active stratagems with phase: "shooting")
# Mirrors CommandPhase._validate_use_stratagem / _process_use_stratagem.
# Distinct from USE_GRENADE_STRATAGEM (hardcoded grenade carve-out) and
# USE_REACTIVE_STRATAGEM (defender reactive). This is the generic active path.
# ============================================================================

func _validate_use_stratagem(action: Dictionary) -> Dictionary:
	var errors = []
	var stratagem_id = action.get("stratagem_id", "")

	if stratagem_id == "":
		errors.append("Missing stratagem_id")
		return {"valid": false, "errors": errors}

	var strat_manager = get_node_or_null("/root/StratagemManager")
	if not strat_manager:
		errors.append("StratagemManager not available")
		return {"valid": false, "errors": errors}

	var target_unit_id = action.get("target_unit_id", "")
	var current_player = get_current_player()
	var validation = strat_manager.can_use_stratagem(current_player, stratagem_id, target_unit_id)
	if not validation.can_use:
		errors.append(validation.reason)
		return {"valid": false, "errors": errors}

	return {"valid": true, "errors": []}

func _process_use_stratagem(action: Dictionary) -> Dictionary:
	var stratagem_id = action.get("stratagem_id", "")
	var target_unit_id = action.get("target_unit_id", "")
	var current_player = get_current_player()

	var strat_manager = get_node_or_null("/root/StratagemManager")
	if not strat_manager:
		return create_result(false, [], "StratagemManager not available")

	var result = strat_manager.use_stratagem(current_player, stratagem_id, target_unit_id)
	if not result.get("success", false):
		return create_result(false, [], result.get("error", "Stratagem use failed"))

	var strat_name = result.get("stratagem_name", stratagem_id)
	DebugLogger.info(str("ShootingPhase: Stratagem %s used (target=%s)" % [strat_name, target_unit_id]))
	return create_result(true, result.get("diffs", []), "Used " + strat_name)

# ============================================================================
# SWIFT AS THE EAGLE — Reactive D6" Normal move after being shot at
# ============================================================================

func _check_swift_as_the_eagle(shooter_id: String, targeted_unit_ids: Array) -> Dictionary:
	# Reactive post-shooting moves. The same scaffolding serves two stratagems:
	#  - SWIFT AS THE EAGLE (Lions of the Emperor): Custodes non-VEHICLE, D6".
	#  - GO GET 'EM! (Green Tide): Boyz, D6" (best of two D6 while the unit
	#    counts as containing 10+ models).
	var result = {"available": false, "unit_id": "", "unit_name": "", "move_inches": 0, "strat_name": "Swift as the Eagle"}
	if targeted_unit_ids.is_empty():
		return result

	var strat_mgr = get_node_or_null("/root/StratagemManager")
	if not strat_mgr:
		return result

	var shooter_unit = GameState.get_unit(shooter_id)
	if shooter_unit.is_empty():
		return result
	var shooter_owner = int(shooter_unit.get("owner", 0))
	var defending_player = 1 if shooter_owner == 2 else 2

	for strat_name in ["SWIFT AS THE EAGLE", "GO GET 'EM!"]:
		var strat_id = strat_mgr.find_faction_stratagem_by_name(defending_player, strat_name)
		if strat_id == "":
			# Typographic-apostrophe variant of GO GET 'EM!
			strat_id = strat_mgr.find_faction_stratagem_by_name(defending_player, strat_name.replace("'", "’"))
		if strat_id == "":
			continue

		var validation = strat_mgr.can_use_stratagem(defending_player, strat_id)
		if not validation.can_use:
			continue

		for tid in targeted_unit_ids:
			var unit = GameState.get_unit(tid)
			if unit.is_empty():
				continue
			if int(unit.get("owner", 0)) != defending_player:
				continue
			if unit.get("flags", {}).get("battle_shocked", false):
				continue
			var keywords = unit.get("meta", {}).get("keywords", [])
			var eligible = false
			if strat_name == "SWIFT AS THE EAGLE":
				var is_custodes = false
				var is_vehicle = false
				for kw in keywords:
					var kw_upper = kw.to_upper()
					if kw_upper == "ADEPTUS CUSTODES":
						is_custodes = true
					if kw_upper == "VEHICLE":
						is_vehicle = true
				eligible = is_custodes and not is_vehicle
			else:
				for kw in keywords:
					if kw.to_upper() == "BOYZ":
						eligible = true
						break
			if not eligible:
				continue
			var has_alive = false
			for m in unit.get("models", []):
				if m.get("alive", true):
					has_alive = true
					break
			if not has_alive:
				continue
			var d6 = _rng.randi_range(1, 6)
			if strat_name == "GO GET 'EM!" and FactionAbilityManager.unit_counts_as_10(unit):
				var d6b = _rng.randi_range(1, 6)
				log_phase_message("GO GET 'EM!: 10+ models — rolled %d and %d, using %d" % [d6, d6b, maxi(d6, d6b)])
				d6 = maxi(d6, d6b)
			result.available = true
			result.unit_id = tid
			result.unit_name = unit.get("meta", {}).get("name", tid)
			result.move_inches = d6
			result.strat_name = strat_name
			return result
	return result

func _validate_use_swift_as_the_eagle(action: Dictionary) -> Dictionary:
	if not awaiting_swift_as_eagle or swift_as_eagle_pending_unit == "":
		return {"valid": false, "errors": ["No Swift as the Eagle pending"]}
	return {"valid": true, "errors": []}

func _validate_decline_swift_as_the_eagle(action: Dictionary) -> Dictionary:
	if not awaiting_swift_as_eagle or swift_as_eagle_pending_unit == "":
		return {"valid": false, "errors": ["No Swift as the Eagle pending"]}
	return {"valid": true, "errors": []}

func _process_use_swift_as_the_eagle(action: Dictionary) -> Dictionary:
	var unit_id = swift_as_eagle_pending_unit
	var move_inches = swift_as_eagle_move_inches
	var unit = GameState.get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var unit_owner = int(unit.get("owner", 0))

	var strat_mgr = get_node_or_null("/root/StratagemManager")
	if strat_mgr:
		var strat_id = strat_mgr.find_faction_stratagem_by_name(unit_owner, swift_as_eagle_pending_strat)
		if strat_id == "":
			strat_id = strat_mgr.find_faction_stratagem_by_name(unit_owner, swift_as_eagle_pending_strat.replace("'", "’"))
		if strat_id != "":
			strat_mgr.use_stratagem(unit_owner, strat_id, unit_id)

	var changes: Array = [{
		"op": "set",
		"path": "units.%s.flags.effect_swift_as_the_eagle" % unit_id,
		"value": true
	}, {
		"op": "set",
		"path": "units.%s.flags.swift_eagle_move_remaining" % unit_id,
		"value": move_inches
	}]

	log_phase_message("SWIFT AS THE EAGLE: %s can make a Normal move of up to %d\" (D6 rolled %d)" % [unit_name, move_inches, move_inches])
	awaiting_swift_as_eagle = false
	swift_as_eagle_pending_unit = ""
	swift_as_eagle_move_inches = 0
	return create_result(true, changes, "Swift as the Eagle activated — %d\" move" % move_inches)

func _process_decline_swift_as_the_eagle(action: Dictionary) -> Dictionary:
	var unit_name = GameState.get_unit(swift_as_eagle_pending_unit).get("meta", {}).get("name", swift_as_eagle_pending_unit)
	log_phase_message("SWIFT AS THE EAGLE: %s declines reactive move" % unit_name)
	awaiting_swift_as_eagle = false
	swift_as_eagle_pending_unit = ""
	swift_as_eagle_move_inches = 0
	return create_result(true, [], "Swift as the Eagle declined")

