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
func test_t6_every_ork_model_can_fight() -> void:
	var state := _load_fixture("tutorial_t6_fight")
	assert_false(state.is_empty(), "tutorial_t6_fight must deserialize")
	if state.is_empty():
		return

	var boyz: Dictionary = state["units"]["U_BOYZ_T"]
	var warboss: Dictionary = state["units"]["U_WARBOSS_T"]

	assert_eq(
		RulesEngine.get_eligible_melee_model_indices(boyz, state).size(),
		boyz.get("models", []).size(),
		"every Boy must be able to make attacks — the lesson says the mob is already in contact"
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
			for enemy in custodes:
				var d := Measurement.model_to_model_distance_inches(model, enemy)
				if d <= RulesEngine.BASE_CONTACT_TOLERANCE_INCHES:
					in_contact += 1
					break

	# 5 front-rank Boyz + the Warboss wrapping the right-hand end of the line.
	assert_eq(in_contact, 6, "expected 6 Ork models touching the Custodian Guard line")


func test_t6_rear_rank_touches_the_front_rank() -> void:
	# The rear rank is what makes "already in contact" true for the whole unit:
	# each rear model is in base contact with a front-rank model that is itself
	# in base contact with an enemy (RulesEngine's chain rule), as well as being
	# inside 11e's 2" engagement range.
	var state := _load_fixture("tutorial_t6_fight")
	if state.is_empty():
		return

	var boyz: Array = state["units"]["U_BOYZ_T"].get("models", [])
	for model in boyz:
		var touching := false
		for other in boyz:
			if other.get("id", "") == model.get("id", ""):
				continue
			if Measurement.model_to_model_distance_inches(model, other) <= RulesEngine.BASE_CONTACT_TOLERANCE_INCHES:
				touching = true
				break
		assert_true(touching, "Boy %s must touch another Boy — the mob has to read as one packed blob" % model.get("id", "?"))
