extends SceneTree

# ISS-037: 11e datasheet/army schema (schema 2).
#
# Checks:
#   A) Every real army file is schema 2: no legacy invulnerable_save
#      spelling remains; faction.schema == 2.
#   B) Units missing 11e-required stats carry needs_11e_review (the manual
#      datasheet pass finds them via this flag — see PRD open question 2).
#   C) Armies still load through ArmyListManager (ability validation incl.).
#   D) The 1.1.0 -> 1.2.0 save migration normalizes invuln spelling.
#
# Usage: godot --headless --path . -s tests/test_iss037_schema2.gd

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
	print("\n=== test_iss037_schema2 ===\n")

	print("-- A/B: army files at schema 2 --")
	var dir = DirAccess.open("res://armies")
	var legacy_spelling := []
	var not_schema2 := []
	var review_flags := 0
	var files := 0
	dir.list_dir_begin()
	var entry = dir.get_next()
	while entry != "":
		if entry.ends_with(".json"):
			var data = JSON.parse_string(FileAccess.get_file_as_string("res://armies/" + entry))
			if data is Dictionary and data.get("faction") is Dictionary:
				files += 1
				if int(data["faction"].get("schema", 0)) != 2:
					not_schema2.append(entry)
				for uid in data.get("units", {}):
					var meta = data["units"][uid].get("meta", {})
					if meta.get("stats", {}).has("invulnerable_save"):
						legacy_spelling.append("%s/%s" % [entry, uid])
					if meta.get("needs_11e_review", false):
						review_flags += 1
		entry = dir.get_next()
	dir.list_dir_end()
	_check("all %d army files at schema 2" % files, not_schema2.is_empty(), str(not_schema2))
	_check("no legacy invulnerable_save spelling", legacy_spelling.is_empty(), str(legacy_spelling))
	# The manual-review pass is complete: the 40kdc 11e regeneration
	# (docs/40KDC_11E_MIGRATION.md) rebuilt every roster from official data,
	# so no unit should carry needs_11e_review anymore. The original >= 1
	# expectation guarded the flags' enumerability while the pass was open;
	# it now guards the opposite — unreviewed 11e data must not creep back in.
	_check("no lingering 11e-review flags (%d)" % review_flags, review_flags == 0)

	print("\n-- C: armies still load --")
	var alm = root.get_node_or_null("ArmyListManager")
	for army in ["orks", "adeptus_custodes", "space_marines"]:
		var loaded = alm.load_army_list(army, 1)
		_check("%s loads at schema 2" % army, not loaded.is_empty())

	print("\n-- D: 1.1.0 -> 1.2.0 migration normalizes spelling --")
	var ser = root.get_node_or_null("StateSerializer")
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/saves/v1_1_0.w40ksave"))
	# inject a legacy-spelled stat into a saved unit
	var uid0 = data["units"].keys()[0]
	data["units"][uid0]["meta"]["stats"]["invulnerable_save"] = 5
	var migrated = ser.migrate_save_data(data)
	_check("migration reaches CURRENT_VERSION (chain includes 1.2.0 normalization)",
		migrated["_serialization"]["version"] == ser.CURRENT_VERSION)
	var st = migrated["units"][uid0]["meta"]["stats"]
	_check("invuln normalized in saved unit",
		not st.has("invulnerable_save") and int(st.get("invuln", 0)) == 5, str(st))

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
