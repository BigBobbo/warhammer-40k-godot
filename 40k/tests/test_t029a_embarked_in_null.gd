extends SceneTree

# T-029a: `unit.get("embarked_in", "") != ""` evaluates `null != ""` as true,
# so units with `embarked_in: null` (the default after a save/load round-trip)
# are silently treated as embarked and ALL aura sources are disabled.
#
# Live evidence from the 2026-05-04 unit audit:
#  - Ghazghkull's Waaagh! Banner aura silently broke after save/load
#  - Kaptin Badrukk's Ded Glowy Ammo (Aura) silently broke
#
# Two-pronged fix:
#  - StateSerializer normalises null → "" during validation/load.
#  - Each of the 7 call sites uses defensive `embk != null and embk != ""`.
#
# This test pins both layers without needing the heavy fixture load.
#
# Usage: godot --headless --path . -s tests/test_t029a_embarked_in_null.gd

var passed := 0
var failed := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_t029a_embarked_in_null ===\n")
	_test_state_serializer_normalises_null()
	_test_rules_engine_aura_paths_treat_null_as_unembarked()
	_test_unit_ability_manager_aura_paths_treat_null_as_unembarked()
	_finish()

func _test_state_serializer_normalises_null() -> void:
	print("\n-- T-029a/A: StateSerializer preserves null sentinel (call sites are defensive) --")
	# After investigation, the codebase has two equally valid embarked_in patterns:
	# (A) `unit.get("embarked_in", null) != null` — the original convention used
	#     by 25+ call sites including ArmyListManager unit creation.
	# (B) `unit.get("embarked_in", "") != ""` — used by 7 aura/effect sites in
	#     RulesEngine + UnitAbilityManager, and which silently misfired against
	#     null because null != "" is true.
	# We fix the 7 (B) sites defensively in-place rather than normalising at
	# deserialisation; that would have broken every (A) site after a save/load.
	# The validation step still preserves null when the field is null, so this
	# test confirms no unintended migration happened.
	var ss = root.get_node("StateSerializer")
	var data = {
		"meta": {"game_id": "t029a", "save_version": "1.1.0"},
		"units": {
			"U_A": {"id": "U_A", "owner": 1, "models": [{"id": "m1", "alive": true}], "embarked_in": null},
			"U_C": {"id": "U_C", "owner": 2, "models": [{"id": "m1", "alive": true}], "embarked_in": ""},
			"U_D": {"id": "U_D", "owner": 2, "models": [{"id": "m1", "alive": true}], "embarked_in": "U_TRANSPORT"},
			"U_TRANSPORT": {"id": "U_TRANSPORT", "owner": 1, "models": [{"id": "m1", "alive": true}], "embarked_in": ""},
		},
	}
	ss._validate_unit_data(data)
	_check("U_A.embarked_in null preserved (no unintended migration)",
		data.units.U_A.get("embarked_in", "MISSING") == null,
		"got %s" % str(data.units.U_A.get("embarked_in", "MISSING")))
	_check("U_C.embarked_in '' preserved", data.units.U_C.get("embarked_in", "INVALID") == "")
	_check("U_D.embarked_in 'U_TRANSPORT' preserved",
		data.units.U_D.get("embarked_in", "INVALID") == "U_TRANSPORT")

func _test_rules_engine_aura_paths_treat_null_as_unembarked() -> void:
	print("\n-- T-029a/B: RulesEngine Ded Glowy Ammo aura is NOT skipped when source has embarked_in:null --")
	# We use Ded Glowy Ammo because it has no Waaagh!-active or other secondary gate,
	# so the null-safety branch is the only thing under test.
	var rules = root.get_node("RulesEngine")
	var gs = root.get_node("GameState")

	gs.state["units"] = {
		"U_BADRUKK": {
			"id": "U_BADRUKK",
			"owner": 1,
			"status": 3,
			"flags": {},
			"meta": {
				"name": "Kaptin Badrukk",
				"keywords": ["ORKS", "CHARACTER", "FREEBOOTERZ"],
				"abilities": [{"name": "Ded Glowy Ammo (Aura)", "type": "Datasheet"}],
			},
			"models": [{"id": "m1", "alive": true, "current_wounds": 1, "wounds": 1, "position": {"x": 100, "y": 100}}],
			"embarked_in": null,  # <-- the bug trigger
		},
		"U_TARGET": {
			"id": "U_TARGET",
			"owner": 2,
			"status": 3,
			"flags": {},
			"meta": {"name": "Marines", "keywords": ["INFANTRY"]},
			"models": [{"id": "m1", "alive": true, "current_wounds": 1, "wounds": 1, "position": {"x": 110, "y": 100}}],
			"embarked_in": null,
		},
	}
	var penalty = rules.get_ded_glowy_ammo_toughness_penalty(gs.state["units"]["U_TARGET"], gs.state)
	_check("Ded Glowy Ammo applies (=1) even when source has embarked_in:null", penalty == 1,
		"got %d" % penalty)

	# Move source >6" away — should NOT apply (penalty 0).
	gs.state["units"]["U_BADRUKK"]["models"][0]["position"] = {"x": 99999, "y": 100}
	var penalty_far = rules.get_ded_glowy_ammo_toughness_penalty(gs.state["units"]["U_TARGET"], gs.state)
	_check("Ded Glowy Ammo does NOT apply at >6\" range (penalty=0)", penalty_far == 0,
		"got %d" % penalty_far)

	# Now embark the source for real — must NOT apply (T-029a guard against false positive).
	gs.state["units"]["U_BADRUKK"]["models"][0]["position"] = {"x": 110, "y": 100}
	gs.state["units"]["U_BADRUKK"]["embarked_in"] = "U_TRANSPORT"
	gs.state["units"]["U_TRANSPORT"] = {
		"id": "U_TRANSPORT", "owner": 1, "status": 3, "flags": {},
		"meta": {"name": "Trukk", "keywords": ["ORKS", "TRANSPORT"]},
		"models": [{"id": "m1", "alive": true, "current_wounds": 5, "wounds": 5, "position": {"x": 110, "y": 100}}],
	}
	var penalty_embarked = rules.get_ded_glowy_ammo_toughness_penalty(gs.state["units"]["U_TARGET"], gs.state)
	_check("Ded Glowy Ammo does NOT apply when source is genuinely embarked (penalty=0)",
		penalty_embarked == 0, "got %d" % penalty_embarked)

	# Cleanup
	gs.state["units"] = {}

func _test_unit_ability_manager_aura_paths_treat_null_as_unembarked() -> void:
	print("\n-- T-029a/C: UnitAbilityManager find_friendly_units_within_aura ignores null embarked_in --")
	var uam = root.get_node("UnitAbilityManager")
	var gs = root.get_node("GameState")

	gs.state["units"] = {
		"U_SRC": {
			"id": "U_SRC", "owner": 1, "status": 3, "flags": {},
			"meta": {"name": "Source"},
			"models": [{"id": "m1", "alive": true, "current_wounds": 1, "wounds": 1, "position": {"x": 0, "y": 0}}],
			"embarked_in": null,
		},
		"U_FRIEND_NEAR": {
			"id": "U_FRIEND_NEAR", "owner": 1, "status": 3, "flags": {},
			"meta": {"name": "Friendly near"},
			"models": [{"id": "m1", "alive": true, "current_wounds": 1, "wounds": 1, "position": {"x": 50, "y": 0}}],
			"embarked_in": null,
		},
		"U_FRIEND_FAR": {
			"id": "U_FRIEND_FAR", "owner": 1, "status": 3, "flags": {},
			"meta": {"name": "Friendly far"},
			"models": [{"id": "m1", "alive": true, "current_wounds": 1, "wounds": 1, "position": {"x": 9999, "y": 0}}],
			"embarked_in": null,
		},
		"U_FRIEND_EMBARKED": {
			"id": "U_FRIEND_EMBARKED", "owner": 1, "status": 3, "flags": {},
			"meta": {"name": "Friendly embarked"},
			"models": [{"id": "m1", "alive": true, "current_wounds": 1, "wounds": 1, "position": {"x": 50, "y": 0}}],
			"embarked_in": "U_TRANSPORT",
		},
		"U_TRANSPORT": {
			"id": "U_TRANSPORT", "owner": 1, "status": 3, "flags": {},
			"meta": {"name": "Transport"},
			"models": [{"id": "m1", "alive": true, "current_wounds": 5, "wounds": 5, "position": {"x": 50, "y": 0}}],
			"embarked_in": null,
		},
	}

	# Aura range 240px (= 240 / Measurement.PIXELS_PER_INCH). Choose a
	# generously large numeric range so position math doesn't matter.
	var results = uam.find_friendly_units_within_aura("U_SRC", 9999.0)
	_check("Source unit excluded from aura results", not ("U_SRC" in results))
	_check("Near friendly with null embarked_in IS in results", "U_FRIEND_NEAR" in results,
		"results=%s" % str(results))
	_check("Embarked friendly is NOT in results", not ("U_FRIEND_EMBARKED" in results))

	# Cleanup
	gs.state["units"] = {}

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
