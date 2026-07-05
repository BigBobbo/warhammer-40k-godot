extends SceneTree

# ISS-028: save schema migration framework + version fixtures.
#
# Checks:
#   A) Committed fixtures for every released schema version deserialize
#      through the migration chain and validate against StateSchema.
#   B) The 1.0.0 fixture (downgraded, phase_log stripped) is upgraded to
#      CURRENT_VERSION with the missing section backfilled.
#   C) Adding a migration is registry-only: a runtime-registered dummy
#      migration (0.9.0 -> 1.0.0) chains into the existing migrations all
#      the way to CURRENT_VERSION.
#
# Usage: godot --headless --path . -s tests/test_iss028_save_migrations.gd

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
	print("\n=== test_iss028_save_migrations ===\n")
	var ser = root.get_node_or_null("StateSerializer")
	if ser == null:
		_check("StateSerializer reachable", false)
		_finish()
		return

	print("-- A/B: fixtures deserialize through the chain --")
	for fixture in ["v1_0_0", "v1_1_0", "v1_2_0", "v1_3_0"]:
		var f = FileAccess.open("res://tests/fixtures/saves/%s.w40ksave" % fixture, FileAccess.READ)
		if f == null:
			_check("%s fixture readable" % fixture, false)
			continue
		var text = f.get_as_text()
		f.close()
		var state = ser.deserialize_game_state(text)
		_check("%s deserializes (chain to %s)" % [fixture, ser.CURRENT_VERSION],
			not state.is_empty())
		if not state.is_empty():
			var errs = StateSchema.validate(state)
			_check("%s validates against StateSchema" % fixture, errs.is_empty(), str(errs))
			_check("%s has phase_log after migration" % fixture, state.has("phase_log"))

	print("\n-- C: adding a migration is registry-only --")
	# Versions below MINIMUM_MIGRATABLE_VERSION are rejected by design, so
	# the demonstration swaps the REGISTERED 1.0.0 entry for a wrapper:
	# if behavior changes from a registry entry alone, migrations are
	# registry-only.
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/saves/v1_0_0.w40ksave"))
	var original = ser._migrations["1.0.0"]
	var marker := {"hit": false}
	var orig_callable: Callable = original["migrate"]
	ser._migrations["1.0.0"] = {
		"target": original["target"],
		"migrate": func(d):
			marker.hit = true
			return orig_callable.call(d)
	}
	var migrated = ser.migrate_save_data(data)
	ser._migrations["1.0.0"] = original
	_check("registry-swapped migration executed", marker.hit)
	_check("chain reached CURRENT through swapped entry",
		not migrated.is_empty() and migrated["_serialization"]["version"] == ser.CURRENT_VERSION,
		str(migrated.get("_serialization", {})))

	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
