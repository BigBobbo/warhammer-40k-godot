extends GutTest

# Guards the melee geometry baked into the tutorial checkpoint fixtures.
#
# The T6 lesson ("Krumpin'") opens on a Pile In step whose prompt says "Yer Boyz
# are already in contact, so just hit End Pile In". For three releases that was
# false, in three separate ways, and none of it was catchable by the lesson
# scenario (which only drove buttons):
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


func test_t6_every_ork_model_can_fight() -> void:
	var state := _load_fixture("tutorial_t6_fight")
	assert_false(state.is_empty(), "tutorial_t6_fight must deserialize")
	if state.is_empty():
		return

	var boyz: Dictionary = state["units"]["U_BOYZ_T"]
	var warboss: Dictionary = state["units"]["U_WARBOSS_T"]

	assert_eq(
		RulesEngine.get_eligible_melee_model_indices(boyz, state).size(),
		_alive_count(boyz),
		"every surviving Boy must be able to make attacks — the lesson says the mob is already in contact"
	)
	assert_eq(
		RulesEngine.get_eligible_melee_model_indices(warboss, state).size(),
		1,
		"da boss must be in engagement range"
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


func test_t6_every_boy_is_locked_into_the_enemy_line() -> void:
	# What makes "already in contact" true for the WHOLE unit, per RulesEngine's
	# chain rule: every alive Boy is either in base contact with an enemy itself,
	# or in base contact with a friendly model that is. The fixture used to lean
	# on the second half of that (a rear rank touching the front); the survivors
	# now sit in one rank, each on the Custodian Guard line directly. Either
	# shape satisfies the prompt — this asserts the rule, not the formation.
	var state := _load_fixture("tutorial_t6_fight")
	if state.is_empty():
		return

	var custodes: Array = state["units"]["U_CUSTODIAN_GUARD_T"].get("models", [])
	var boyz: Array = state["units"]["U_BOYZ_T"].get("models", [])

	var on_the_line := {}
	for model in boyz:
		if not model.get("alive", true):
			continue
		for enemy in custodes:
			if Measurement.model_to_model_distance_inches(model, enemy) <= RulesEngine.BASE_CONTACT_TOLERANCE_INCHES:
				on_the_line[model.get("id", "?")] = true
				break

	assert_gt(on_the_line.size(), 0, "at least one Boy has to be on the Custodian Guard line")

	for model in boyz:
		if not model.get("alive", true):
			continue
		var mid: String = str(model.get("id", "?"))
		var reaches: bool = on_the_line.has(mid)
		if not reaches:
			for other in boyz:
				if not other.get("alive", true) or other.get("id", "") == model.get("id", ""):
					continue
				if not on_the_line.has(str(other.get("id", "?"))):
					continue
				if Measurement.model_to_model_distance_inches(model, other) <= RulesEngine.BASE_CONTACT_TOLERANCE_INCHES:
					reaches = true
					break
		assert_true(reaches, "Boy %s touches neither an enemy nor a Boy who does — it cannot fight" % mid)


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
# ------------------------------------------------------------------------
const T6_WIPE_TRIALS := 40


func test_t6_only_the_boss_nob_swings_the_power_klaw() -> void:
	var state := _load_fixture("tutorial_t6_fight")
	if state.is_empty():
		return

	var boyz: Dictionary = state["units"]["U_BOYZ_T"]
	assert_eq(_alive_count(boyz), 10, "the full mob fights — its damage is bounded by loadouts, not by casualties")
	assert_eq(_alive_count(state["units"]["U_CUSTODIAN_GUARD_T"]), 4, "the Custodian Guard the mob has to leave standing")

	var eligible := RulesEngine.get_eligible_melee_model_indices(boyz, state)
	var expected := {"Power klaw": 1, "Big choppa": 1, "Choppa": 10, "Close combat weapon": 9}
	for weapon_name in expected:
		var weapon_id := RulesEngine.generate_weapon_id(weapon_name, "Melee")
		var carriers := RulesEngine.get_melee_weapon_swingers(boyz, weapon_id, eligible, [])
		assert_eq(
			carriers.size(), int(expected[weapon_name]),
			"%s: %d model(s) should swing it, got %d — the mob's datasheet gives the klaw and big choppa to the Boss Nob alone" % [
				weapon_name, int(expected[weapon_name]), carriers.size()]
		)


func test_t6_boyz_cannot_wipe_the_custodian_guard() -> void:
	var state := _load_fixture("tutorial_t6_fight")
	if state.is_empty():
		return

	# Every weapon the attack dialog offers, resolved exactly the way it builds
	# the plan: the pick goes to its carriers, everyone else swings a Choppa
	# (or a Close combat weapon when Choppa IS the pick).
	var boyz: Dictionary = state["units"]["U_BOYZ_T"]
	var eligible := RulesEngine.get_eligible_melee_model_indices(boyz, state)
	var choppa_id := RulesEngine.generate_weapon_id("Choppa", "Melee")
	var ccw_id := RulesEngine.generate_weapon_id("Close combat weapon", "Melee")

	for weapon_name in ["Power klaw", "Big choppa", "Choppa", "Close combat weapon"]:
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
