extends SceneTree

# T-007 / 06_SYNTHESIS launch-blocker #7: NBSP-tolerant detachment matching.
#
# The Lions of the Emperor detachment was historically dropped from the
# stratagem load because some hand-edited roster JSONs contained a
# non-breaking space (U+00A0) in the detachment name; an exact-string
# compare against the CSV detachment column failed silently and Lions
# rosters loaded zero detachment stratagems.
#
# `FactionStratagemLoader._normalise_detachment_name` now lower-cases,
# replaces NBSP with regular space, and strips edges. This pin verifies:
#   A) the normaliser handles every flavour we expect (NBSP, mixed case,
#      surrounding whitespace, plain pass-through);
#   B) the actual `load_faction_stratagems` integration matches a CSV row
#      whose detachment column has NBSP against a roster name without it;
#   C) currently-checked-in armies/*.json files do NOT regress to having
#      NBSP in the detachment name (catches data drift).
#
# Usage: godot --headless --path . -s tests/test_t007_detachment_nbsp_pin.gd

const FactionStratagemLoaderClass = preload("res://autoloads/FactionStratagemLoader.gd")

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
	print("\n=== test_t007_detachment_nbsp_pin ===\n")
	_test_normaliser()
	_test_loader_integration()
	_test_data_drift_guard()
	_finish()

func _test_normaliser() -> void:
	print("\n-- A: _normalise_detachment_name table --")
	# NBSP is U+00A0; in GDScript source it's encoded as the literal Unicode
	# escape  . We rely on String concat to construct the inputs so the
	# test source file itself stays ASCII-safe.
	var nbsp = String.chr(0x00A0)
	var nrm = FactionStratagemLoaderClass._normalise_detachment_name
	_check("plain pass-through (lowercased)",
		nrm.call("Shield Host") == "shield host")
	_check("NBSP -> regular space",
		nrm.call("Lions" + nbsp + "of" + nbsp + "the" + nbsp + "Emperor") == "lions of the emperor")
	_check("mixed case + NBSP normalised",
		nrm.call("LIONS" + nbsp + "OF THE EMPEROR") == "lions of the emperor")
	_check("surrounding whitespace stripped",
		nrm.call("  War Horde  ") == "war horde")
	_check("empty string returns empty",
		nrm.call("") == "")
	_check("NBSP-only string preserved as space then stripped",
		nrm.call(nbsp) == "")

func _test_loader_integration() -> void:
	print("\n-- B: load_faction_stratagems with NBSP in CSV row --")
	var loader = FactionStratagemLoaderClass.new()
	# Synthetic CSV with one row whose detachment cell uses NBSP. The roster
	# side passes a plain-space "Lions of the Emperor"; the matcher must
	# return success.
	var nbsp = String.chr(0x00A0)
	var csv_path = "user://_test_stratagems_nbsp.csv"
	var f = FileAccess.open(csv_path, FileAccess.WRITE)
	# Header order mirrors the real 40k/data/Stratagems.csv:
	# faction_id|name|id|type|cp_cost|legend|turn|phase|detachment|detachment_id|description|
	f.store_string("faction_id|name|id|type|cp_cost|legend|turn|phase|detachment|detachment_id|description|\n")
	f.store_string(
		"AC|TEST_STRATAGEM_NBSP|TST001|Auric Champions – Battle Tactic Stratagem|1|fluff|Your turn|Movement phase|"
		+ "Lions" + nbsp + "of" + nbsp + "the" + nbsp + "Emperor"
		+ "|000000863|effect text|\n"
	)
	f.close()
	var globalised_path = ProjectSettings.globalize_path(csv_path)
	# Loader expects res:// or user:// path; we pass user:// so it can read
	# our scratch file. (The real loader works the same way.)
	# We need faction codes loaded so AC resolves to "Adeptus Custodes".
	loader.load_faction_codes()
	var rows: Array = loader.load_faction_stratagems("Adeptus Custodes", "Lions of the Emperor", csv_path)
	_check("NBSP-containing CSV row matched against plain-space roster name",
		rows.size() == 1,
		"got %d rows, expected 1; csv at %s" % [rows.size(), globalised_path])
	if rows.size() == 1:
		_check("matched row name is TEST_STRATAGEM_NBSP",
			str(rows[0].get("name", "")) == "TEST_STRATAGEM_NBSP",
			"got name=%s" % str(rows[0].get("name", "")))

func _test_data_drift_guard() -> void:
	print("\n-- C: armies/*.json detachment names stay NBSP-free --")
	# Catches a future data drift where a hand-edited roster reintroduces
	# NBSP. The matcher is now NBSP-tolerant, but keeping the data clean
	# is still the better long-term defense.
	var nbsp = String.chr(0x00A0)
	var dir = DirAccess.open("res://armies")
	if dir == null:
		_check("res://armies readable", false, "DirAccess.open returned null")
		return
	dir.list_dir_begin()
	var fname = dir.get_next()
	var checked = 0
	var bad: Array = []
	while fname != "":
		if fname.ends_with(".json"):
			var path = "res://armies/" + fname
			var fh = FileAccess.open(path, FileAccess.READ)
			if fh != null:
				var blob = fh.get_as_text()
				fh.close()
				var parsed = JSON.parse_string(blob)
				if parsed is Dictionary:
					var fac = parsed.get("faction", {})
					var det: String = ""
					if fac is Dictionary:
						det = str(fac.get("detachment", ""))
					else:
						det = str(parsed.get("detachment", ""))
					if det.find(nbsp) != -1:
						bad.append(fname)
					checked += 1
		fname = dir.get_next()
	dir.list_dir_end()
	_check("checked at least 1 roster", checked >= 1, "checked=%d" % checked)
	_check("no roster file contains NBSP in detachment name",
		bad.is_empty(),
		"NBSP detachment in: %s" % str(bad))

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
