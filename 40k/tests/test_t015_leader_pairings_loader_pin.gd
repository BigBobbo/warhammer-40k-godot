extends SceneTree

# 06_SYNTHESIS launch-blocker #15 / issue #378: LeaderPairingsLoader.
#
# Wahapedia's Datasheets_leader.csv ships 1,899 canonical leader/bodyguard
# pairings. Pre-#378 only the curated armies/*.json `can_lead` lists were
# consumed; rosters with empty / stale lists (Ghazghkull Thraka, Kaptin
# Badrukk, Nob With Waaagh! Banner et al) silently failed to attach
# despite canonical pairings existing.
#
# The loader autoload is in place. CharacterAttachmentManager.can_attach
# at line ~36-53 falls back to the canonical list when meta.leader_data.
# can_lead is empty.
#
# Pin verifies:
#   A) LeaderPairingsLoader autoload is registered and loaded the CSVs.
#   B) Canonical lookups return non-empty results for the three rosters
#      called out by the synthesis (Ghazghkull / Kaptin Badrukk / Nob).
#   C) CharacterAttachmentManager.can_attach falls back to
#      LeaderPairingsLoader.get_canonical_can_lead_keywords when
#      leader_data.can_lead is empty.
#   D) Live drive: synthetic Ghazghkull (no can_lead) attaching to a
#      Boyz unit returns valid=true via the canonical fallback.
#
# Usage: godot --headless --path . -s tests/test_t015_leader_pairings_loader_pin.gd

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

func _read(path: String) -> String:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t = f.get_as_text()
	f.close()
	return t

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_t015_leader_pairings_loader_pin ===\n")
	_test_loader_autoload()
	_test_canonical_lookups()
	_test_attachment_manager_fallback()
	_test_live_canonical_attach()
	_finish()

func _test_loader_autoload() -> void:
	print("\n-- A: LeaderPairingsLoader autoload + CSVs loaded --")
	var lp = root.get_node_or_null("LeaderPairingsLoader")
	if lp == null:
		_check("LeaderPairingsLoader autoload reachable", false)
		return
	_check("LeaderPairingsLoader autoload reachable", true)
	_check("get_canonical_attached_names exists",
		lp.has_method("get_canonical_attached_names"))
	_check("get_canonical_can_lead_keywords exists",
		lp.has_method("get_canonical_can_lead_keywords"))
	_check("can_lead_canonical exists",
		lp.has_method("can_lead_canonical"))

func _test_canonical_lookups() -> void:
	print("\n-- B: canonical lookups return non-empty for synthesis trio --")
	var lp = root.get_node("LeaderPairingsLoader")
	# Ghazghkull Thraka should canonically lead at least Boyz / Meganobz / Nobz.
	var ghaz = lp.get_canonical_attached_names("Ghazghkull Thraka")
	_check("Ghazghkull canonical bodyguards non-empty (was [] pre-#378)",
		ghaz.size() > 0,
		"got %s" % str(ghaz))
	# Nob With Waaagh! Banner: canonical leader for Boyz / Breaka Boyz / Nobz
	var nob = lp.get_canonical_attached_names("Nob With Waaagh! Banner")
	_check("Nob With Waaagh! Banner canonical bodyguards non-empty",
		nob.size() > 0,
		"got %s" % str(nob))
	# Kaptin Badrukk
	var kaptin = lp.get_canonical_attached_names("Kaptin Badrukk")
	_check("Kaptin Badrukk canonical bodyguards non-empty",
		kaptin.size() > 0,
		"got %s" % str(kaptin))
	# Keyword variant should be uppercase
	var ghaz_kw = lp.get_canonical_can_lead_keywords("Ghazghkull Thraka")
	var any_upper = false
	for k in ghaz_kw:
		if String(k) == String(k).to_upper() and String(k).length() > 0:
			any_upper = true
			break
	_check("get_canonical_can_lead_keywords returns uppercase keywords",
		any_upper,
		"got %s" % str(ghaz_kw))

func _test_attachment_manager_fallback() -> void:
	print("\n-- C: CharacterAttachmentManager.can_attach falls back to canonical list --")
	var src = _read("res://autoloads/CharacterAttachmentManager.gd")
	_check("CharacterAttachmentManager.gd readable", not src.is_empty())
	_check("can_attach references LeaderPairingsLoader",
		"LeaderPairingsLoader" in src)
	_check("can_attach calls get_canonical_can_lead_keywords",
		"get_canonical_can_lead_keywords" in src,
		"fallback path missing — empty meta.can_lead would still reject")

func _test_live_canonical_attach() -> void:
	print("\n-- D: synthetic Ghazghkull + Boyz pair attaches via canonical fallback --")
	var cam = root.get_node_or_null("CharacterAttachmentManager")
	var gs = root.get_node_or_null("GameState")
	if cam == null or gs == null:
		_check("autoloads reachable", false)
		return
	_check("autoloads reachable", true)
	# Inject a Ghazghkull-shaped CHARACTER with EMPTY can_lead, plus a Boyz
	# unit with the BOYZ keyword. Pre-#378 the empty can_lead would reject.
	var prev_units = gs.state.get("units", {}).duplicate(true)
	gs.state["units"] = {
		"U_TEST_GHAZ": {
			"id": "U_TEST_GHAZ",
			"owner": 1,
			"meta": {
				"name": "Ghazghkull Thraka",
				"keywords": ["CHARACTER", "INFANTRY"],
				"abilities": [],
				"leader_data": {"can_lead": []},  # empty by design
			},
		},
		"U_TEST_BOYZ": {
			"id": "U_TEST_BOYZ",
			"owner": 1,
			"meta": {
				"name": "Boyz",
				"keywords": ["BOYZ", "INFANTRY"],
			},
		},
	}
	var result = cam.call("can_attach", "U_TEST_GHAZ", "U_TEST_BOYZ")
	gs.state["units"] = prev_units
	_check("can_attach returns valid=true via canonical fallback",
		result is Dictionary and result.get("valid", false) == true,
		"got %s" % str(result))

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
