extends GutTest

# Guards the melee geometry baked into the tutorial checkpoint fixtures.
#
# The T6 lesson ("Krumpin'") opens on a Pile In step. It used to say "Yer Boyz
# are already in contact, so just hit End Pile In" — a step with nothing in it —
# and it now asks the player to make a real 3" pile-in with the Boyz' back rank
# (see test_t6_the_pile_in_step_has_something_to_do below). For three releases
# the "already in contact" claim was false in three separate ways, and none of
# it was catchable by the lesson scenario (which only drove buttons):
#
#   1. The Custodian Guard sat on a 60px pitch. A 40mm base is 62.99px across at
#      40 px/inch, so every adjacent pair of Custodians overlapped by ~3px —
#      visibly intersecting base rings.
#   2. No Ork model was actually in base-to-base contact (nearest was 0.135",
#      outside RulesEngine.BASE_CONTACT_TOLERANCE_INCHES), and Boyz m1/m9 sat
#      ~2.4" away — outside 11e's 2" engagement range, so they could not fight
#      at all. The prompt promised a full mob swinging; two Boyz never did.
#   3. U_WARBOSS_T carried status UNDEPLOYED even though it is attached to the
#      Boyz and holds a board position. Main._recreate_unit_visuals() only
#      builds tokens for status >= DEPLOYED, so da boss was never drawn on the
#      board in ANY lesson. (DeploymentPhase.gd auto-deploys attached
#      characters to DEPLOYED for exactly this reason.)
#
# These are data assertions over shipped files, so they belong headless. The
# player-facing half — the tokens the player actually sees — is pinned by the
# windowed scenario tests/scenarios/sp/tut_t6_krumpin.json.
#
# Regenerate the fixtures with tools/fix_tutorial_fight_fixtures.py.

const FIXTURES_DIR := "res://data/tutorials/fixtures/"

# Every checkpoint that puts models on the table.
const FIXTURES := [
	"tutorial_postdeploy",
	"tutorial_t4_shoot",
	"tutorial_t5_charge",
	"tutorial_t6_fight",
	"tutorial_t7_round2",
]


func _load_fixture(name: String) -> Dictionary:
	var path := FIXTURES_DIR + name + ".w40ksave"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	return StateSerializer.deserialize_game_state(text)


func _placed_models(state: Dictionary) -> Array:
	# [{unit_id, model_id, model}] for every alive model with a position.
	var out := []
	for unit_id in state.get("units", {}):
		var unit: Dictionary = state["units"][unit_id]
		for model in unit.get("models", []):
			if not model.get("alive", true):
				continue
			if model.get("position", null) == null:
				continue
			out.append({"unit_id": unit_id, "model_id": model.get("id", "?"), "model": model})
	return out


# ------------------------------------------------------------------------
# Every fixture: no base may overlap another base.
# ------------------------------------------------------------------------
func test_no_model_bases_overlap_in_any_fixture() -> void:
	for name in FIXTURES:
		var state := _load_fixture(name)
		assert_false(state.is_empty(), "%s must deserialize" % name)
		if state.is_empty():
			continue
		var placed := _placed_models(state)
		for i in range(placed.size()):
			for j in range(i + 1, placed.size()):
				var a: Dictionary = placed[i]
				var b: Dictionary = placed[j]
				assert_false(
					Measurement.models_overlap(a.model, b.model),
					"%s: %s/%s overlaps %s/%s" % [name, a.unit_id, a.model_id, b.unit_id, b.model_id]
				)


# ------------------------------------------------------------------------
# Every fixture: an attached character that is on the table must be DEPLOYED,
# or Main._recreate_unit_visuals() silently drops its token.
# ------------------------------------------------------------------------
func test_attached_characters_on_the_table_are_deployed() -> void:
	for name in FIXTURES:
		var state := _load_fixture(name)
		if state.is_empty():
			continue
		for unit_id in state.get("units", {}):
			var unit: Dictionary = state["units"][unit_id]
			if unit.get("attached_to", null) == null:
				continue
			if unit.get("embarked_in", null) != null:
				continue
			var has_position := false
			for model in unit.get("models", []):
				if model.get("position", null) != null:
					has_position = true
					break
			if not has_position:
				continue
			assert_eq(
				int(unit.get("status", 0)),
				int(GameStateData.UnitStatus.DEPLOYED),
				"%s: attached character %s holds a board position but is not DEPLOYED — it will not be rendered" % [name, unit_id]
			)


# ------------------------------------------------------------------------
# T6 specifically: the Pile In prompt's promise has to be true.
# ------------------------------------------------------------------------
func _alive_count(unit: Dictionary) -> int:
	var n := 0
	for model in unit.get("models", []):
		if model.get("alive", true):
			n += 1
	return n


func _closest_enemy_inches(model: Dictionary, enemies: Array) -> float:
	var best := INF
	for enemy in enemies:
		if not enemy.get("alive", true):
			continue
		best = minf(best, Measurement.model_to_model_distance_inches(model, enemy))
	return best


# The T6 fixture as the FIGHT sees it — i.e. after the lesson's Pile In step.
# The board that actually swings is not the one on disk any more: the back rank
# starts out of engagement range and the player moves it in, so anything about
# attack volume has to be measured here, not at boot.
func _load_t6_after_pile_in() -> Dictionary:
	var state := _load_fixture("tutorial_t6_fight")
	if state.is_empty():
		return state
	var boyz: Dictionary = state["units"]["U_BOYZ_T"]
	var movements: Dictionary = AIDecisionMaker._compute_pile_in_movements(state, "U_BOYZ_T", boyz, 1)
	for key in movements:
		var to: Vector2 = movements[key]
		boyz["models"][int(str(key))]["position"] = {"x": to.x, "y": to.y}
	return state


# The whole point of the step: the back rank must start OUTSIDE engagement
# range (so those Boyz genuinely cannot fight and the player has a reason to
# move them) and INSIDE 3" (so one legal pile-in move fixes it). Get either
# bound wrong and the lesson either teaches nothing or cannot be completed.
func test_t6_the_pile_in_step_has_something_to_do() -> void:
	var state := _load_fixture("tutorial_t6_fight")
	assert_false(state.is_empty(), "tutorial_t6_fight must deserialize")
	if state.is_empty():
		return

	var boyz: Dictionary = state["units"]["U_BOYZ_T"]
	var custodes: Array = state["units"]["U_CUSTODIAN_GUARD_T"].get("models", [])
	var er := GameConstants.engagement_range_inches()
	var pile_in_inches := 3.0

	var stranded: Array = []
	for model in boyz.get("models", []):
		if not model.get("alive", true):
			continue
		var d := _closest_enemy_inches(model, custodes)
		if d <= er:
			continue
		stranded.append(str(model.get("id", "?")))
		assert_lt(
			d, pile_in_inches,
			"Boy %s starts %.2f\" from the Custodian Guard — more than the 3\" a pile-in may cover, so the lesson's move step could never bring it into the fight" % [
				str(model.get("id", "?")), d]
		)

	assert_gt(
		stranded.size(), 0,
		"no Boy is out of engagement range — the Pile In step would have nothing for the player to do (that is exactly the state this fixture used to ship in)"
	)
	assert_eq(
		RulesEngine.get_eligible_melee_model_indices(boyz, state).size(),
		_alive_count(boyz) - stranded.size(),
		"the Boyz out of engagement range must be exactly the ones that cannot swing yet: %s" % str(stranded)
	)
	assert_eq(
		RulesEngine.get_eligible_melee_model_indices(state["units"]["U_WARBOSS_T"], state).size(),
		1,
		"da boss must be in engagement range"
	)


# ...and the move the lesson walks the player through has to WORK: the same
# solver behind the dialog's "Auto Pile In" button must bring every stranded
# Boy back into engagement range, legally and in coherency. This is the assert
# that would have caught a too-wide gap before it shipped.
func test_t6_one_pile_in_brings_the_whole_mob_back_into_the_fight() -> void:
	var state := _load_fixture("tutorial_t6_fight")
	if state.is_empty():
		return

	var boyz: Dictionary = state["units"]["U_BOYZ_T"]
	var movements: Dictionary = AIDecisionMaker._compute_pile_in_movements(state, "U_BOYZ_T", boyz, 1)
	assert_gt(movements.size(), 0, "the pile-in solver must find a move for the stranded Boyz")

	for key in movements:
		var index := int(str(key))
		var from: Dictionary = boyz["models"][index]["position"]
		var to: Vector2 = movements[key]
		assert_lte(
			Measurement.distance_inches(Vector2(from.x, from.y), to), 3.0 + 0.001,
			"model index %d is moved further than the 3\" a pile-in allows" % index
		)
		boyz["models"][index]["position"] = {"x": to.x, "y": to.y}

	assert_eq(
		RulesEngine.get_eligible_melee_model_indices(boyz, state).size(),
		_alive_count(boyz),
		"after ONE pile-in every surviving Boy must be able to swing — the lesson's payoff, and what the rest of T6 (the Power klaw / choppa split, the Custodes surviving to swing back) is balanced around"
	)
	assert_true(
		AttackSequence.check_unit_coherency(boyz).coherent,
		"the mob must still be in coherency after the pile-in the lesson asks for (03.01)"
	)


func test_t6_front_rank_is_in_real_base_contact() -> void:
	var state := _load_fixture("tutorial_t6_fight")
	if state.is_empty():
		return

	var custodes: Array = state["units"]["U_CUSTODIAN_GUARD_T"].get("models", [])
	var in_contact := 0
	for unit_id in ["U_BOYZ_T", "U_WARBOSS_T"]:
		for model in state["units"][unit_id].get("models", []):
			if not model.get("alive", true):
				continue
			for enemy in custodes:
				var d := Measurement.model_to_model_distance_inches(model, enemy)
				if d <= RulesEngine.BASE_CONTACT_TOLERANCE_INCHES:
					in_contact += 1
					break

	# 5 surviving Boyz + the Warboss wrapping the right-hand end of the line.
	assert_eq(in_contact, 6, "expected 6 Ork models touching the Custodian Guard line")


func test_t6_the_mob_boots_in_a_legal_formation() -> void:
	# The back rank is deliberately held back, but the fixture still has to be a
	# position the rules allow: PileInMove.after_moving_conditions re-checks
	# coherency, so a mob that boots OUT of coherency can never confirm the
	# pile-in the lesson asks for — the step would soft-lock.
	var state := _load_fixture("tutorial_t6_fight")
	if state.is_empty():
		return

	for unit_id in ["U_BOYZ_T", "U_WARBOSS_T", "U_CUSTODIAN_GUARD_T"]:
		var coh := AttackSequence.check_unit_coherency(state["units"][unit_id])
		assert_true(coh.coherent, "%s boots out of coherency: %s" % [unit_id, str(coh.offenders)])

	# And the unit as a whole is still engaged (12.03 needs that to be true both
	# before and after the pile-in, or the move is illegal).
	assert_true(
		RulesEngine.is_unit_engaged("U_BOYZ_T", state),
		"the Boyz must be engaged — the pile-in is only offered to an engaged (or charging) unit, and 12.03 requires it to still be engaged afterwards"
	)


# ------------------------------------------------------------------------
# T6: the enemy has to still be there to swing back.
#
# Reported 2026-07-30: the Boyz wiped the whole Custodian Guard, so the step
# that teaches alternating activation ("da enemy swings back") had no enemy
# left to activate. The cause was attack VOLUME — the melee engine gave the
# picked weapon to every eligible model, so all 10 Boyz swung the Boss Nob's
# Power klaw: 30 attacks at S9 AP-2 D2 into 4 Custodians (16 wounds). Measured
# over 250 seeded resolutions: Power klaw wiped the squad 94/250 (38%), Big
# choppa 21/250, Choppa 0/250.
#
# Melee now honours per-model loadouts (RulesEngine._melee_weapon_swingers), so
# the klaw is three attacks from one model and the other nine swing choppas.
# The fixture is the original full mob again; these tests pin the fix from the
# lesson's side — the carrier split, and a seeded sweep of every weapon the
# dialog offers that must always leave a Custodian standing.
#
# Both run on the board AFTER the lesson's pile-in (_load_t6_after_pile_in),
# because that is the mob that actually swings: at boot only the front rank is
# in engagement range.
# ------------------------------------------------------------------------
const T6_WIPE_TRIALS := 40


func test_t6_only_the_boss_nob_swings_the_power_klaw() -> void:
	var state := _load_t6_after_pile_in()
	if state.is_empty():
		return

	var boyz: Dictionary = state["units"]["U_BOYZ_T"]
	assert_eq(_alive_count(boyz), 10, "the full mob fights — its damage is bounded by loadouts, not by casualties")
	assert_eq(_alive_count(state["units"]["U_CUSTODIAN_GUARD_T"]), 4, "the Custodian Guard the mob has to leave standing")

	# The mob's resolved kit is "1x Big choppa, 9x Choppa" (RulesEngine
	# ._ensure_loadout_resolved reads the datasheet default), so the Boss Nob's
	# weapon is swung by exactly one model and the rest swing choppas. Weapons
	# the roster never bought — the Power klaw among them — are not offered by
	# the attack dialog at all (unit_has_melee_weapon is false), which is why
	# they are asserted separately below rather than through the carrier funnel
	# (that deliberately falls back to "everyone" when it cannot attribute).
	var eligible := RulesEngine.get_eligible_melee_model_indices(boyz, state)
	var expected := {"Big choppa": 1, "Choppa": 9}
	for weapon_name in expected:
		var weapon_id := RulesEngine.generate_weapon_id(weapon_name, "Melee")
		var carriers := RulesEngine.get_melee_weapon_swingers(boyz, weapon_id, eligible, [])
		assert_eq(
			carriers.size(), int(expected[weapon_name]),
			"%s: %d model(s) should swing it, got %d — the mob's datasheet kit gives the big choppa to the Boss Nob alone" % [
				weapon_name, int(expected[weapon_name]), carriers.size()]
		)
	assert_false(
		RulesEngine.unit_has_melee_weapon(boyz, RulesEngine.generate_weapon_id("Power klaw", "Melee")),
		"the Boyz never bought a Power klaw — the attack panel must not offer them one (da boss carries it, and he activates separately)"
	)
	assert_true(
		RulesEngine.unit_has_melee_weapon(state["units"]["U_WARBOSS_T"], RulesEngine.generate_weapon_id("Power klaw", "Melee")),
		"da boss's Power klaw is the one in this fight"
	)


func test_t6_boyz_cannot_wipe_the_custodian_guard() -> void:
	var state := _load_t6_after_pile_in()
	if state.is_empty():
		return

	# Every weapon the attack dialog offers, resolved exactly the way it builds
	# the plan: the pick goes to its carriers, everyone else swings a Choppa
	# (or a Close combat weapon when Choppa IS the pick).
	#
	# "Offers" is the resolved kit, not the datasheet menu: the mob bought 1x Big
	# choppa + 9x Choppa, and the panel omits the options it never took. Sweeping
	# a Power klaw here would resolve through get_melee_weapon_swingers' "cannot
	# attribute it, so everyone swings it" fallback — 30 S9 AP-2 D2 attacks the
	# player has no way to ask for.
	var boyz: Dictionary = state["units"]["U_BOYZ_T"]
	var eligible := RulesEngine.get_eligible_melee_model_indices(boyz, state)
	var choppa_id := RulesEngine.generate_weapon_id("Choppa", "Melee")
	var ccw_id := RulesEngine.generate_weapon_id("Close combat weapon", "Melee")

	for weapon_name in ["Big choppa", "Choppa"]:
		var weapon_id := RulesEngine.generate_weapon_id(weapon_name, "Melee")
		var carriers := RulesEngine.get_melee_weapon_swingers(boyz, weapon_id, eligible, [])
		var carrier_refs: Array = []
		for idx in carriers:
			carrier_refs.append(str(idx))
		var rest: Array = []
		for idx in eligible:
			if not idx in carriers:
				rest.append(str(idx))

		var assignments: Array = [{
			"attacker": "U_BOYZ_T", "weapon": weapon_id,
			"target": "U_CUSTODIAN_GUARD_T", "models": carrier_refs
		}]
		if not rest.is_empty():
			assignments.append({
				"attacker": "U_BOYZ_T",
				"weapon": ccw_id if weapon_id == choppa_id else choppa_id,
				"target": "U_CUSTODIAN_GUARD_T", "models": rest
			})

		# resolve_melee_attacks mutates the board it is handed, so each trial
		# gets its own copy. Da boss swings after the mob, at the same squad.
		var wipes := 0
		var worst := 0
		for i in range(T6_WIPE_TRIALS):
			var board: Dictionary = state.duplicate(true)
			var killed := 0
			for action in [
				{"type": "FIGHT", "actor_unit_id": "U_BOYZ_T", "payload": {"assignments": assignments}},
				{"type": "FIGHT", "actor_unit_id": "U_WARBOSS_T", "payload": {"assignments": [{
					"attacker": "U_WARBOSS_T",
					"weapon": RulesEngine.generate_weapon_id("Power klaw", "Melee"),
					"target": "U_CUSTODIAN_GUARD_T"}]}}
			]:
				var rng = RulesEngine.RNGService.new(4242 + i * 31)
				var result = RulesEngine.resolve_melee_attacks(action, board, rng)
				for diff in result.get("diffs", []):
					var path := str(diff.get("path", ""))
					if path.begins_with("units.U_CUSTODIAN_GUARD_T.models.") and path.ends_with(".alive") \
							and diff.get("value") == false:
						killed += 1
			worst = maxi(worst, killed)
			if killed >= 4:
				wipes += 1

		assert_eq(
			wipes, 0,
			"%s: the Boyz + Warboss wiped the Custodian Guard in %d/%d seeded rolls (worst: %d of 4 slain) — the next lesson step needs someone left to swing back" % [
				weapon_name, wipes, T6_WIPE_TRIALS, worst]
		)
