extends SceneTree

# 06_SYNTHESIS launch-blocker #10 / TLV-3 / issue #373:
# Lone Operative attachment guard at the army-list-time path.
#
# Wahapedia 10e: a unit with the Lone Operative ability cannot be part of
# an Attached unit. Two paths must enforce this:
#   1) `CharacterAttachmentManager.can_attach()` — runtime declaration
#   2) `FormationsPhase._validate_declare_leader_attachment()` — pre-game
#       formation declaration
#
# This pin verifies:
#   A) `RulesEngine.has_lone_operative(unit)` recognises both string and
#      dict ability storage (per its 10e-T2-2 contract).
#   B) `CharacterAttachmentManager.can_attach()` rejects a Lone Operative
#      character with a Wahapedia-aligned reason string.
#   C) `FormationsPhase._validate_declare_leader_attachment()` rejects the
#      same character with a reason string the UI can show.
#   D) Both paths share the SAME underlying check (have_lone_operative).
#      Catches drift if someone refactors one without the other.
#
# Usage: godot --headless --path . -s tests/test_t010_lone_operative_attachment_pin.gd

# RulesEngine + CharacterAttachmentManager are autoloads; reach them via
# /root rather than preloading because Godot 4's Expression/static-method
# resolution on preloaded GDScripts is brittle when the Script also has
# `extends Node`.

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
	print("\n=== test_t010_lone_operative_attachment_pin ===\n")
	_test_has_lone_operative()
	_test_character_attachment_manager_rejects()
	_test_formations_phase_rejects()
	_test_paths_share_check()
	_finish()

func _test_has_lone_operative() -> void:
	print("\n-- A: RulesEngine.has_lone_operative recognises string + dict abilities --")
	# String-form ability
	var u1 = {"meta": {"abilities": ["Lone Operative", "Other"]}}
	_check("string-form 'Lone Operative' detected",
		root.get_node("RulesEngine").has_lone_operative(u1) == true)
	# Dict-form ability
	var u2 = {"meta": {"abilities": [{"name": "Lone Operative", "details": "..."}]}}
	_check("dict-form 'Lone Operative' detected",
		root.get_node("RulesEngine").has_lone_operative(u2) == true)
	# Case-insensitive
	var u3 = {"meta": {"abilities": ["lone operative"]}}
	_check("case-insensitive lower match",
		root.get_node("RulesEngine").has_lone_operative(u3) == true)
	var u4 = {"meta": {"abilities": ["LONE OPERATIVE"]}}
	_check("case-insensitive upper match",
		root.get_node("RulesEngine").has_lone_operative(u4) == true)
	# Not present
	var u5 = {"meta": {"abilities": ["Stealth", "Deep Strike"]}}
	_check("non-Lone-Op unit returns false",
		root.get_node("RulesEngine").has_lone_operative(u5) == false)
	# Empty abilities
	var u6 = {"meta": {}}
	_check("missing abilities returns false",
		root.get_node("RulesEngine").has_lone_operative(u6) == false)

func _test_character_attachment_manager_rejects() -> void:
	print("\n-- B: CharacterAttachmentManager.can_attach() rejects Lone Operative --")
	var cam = root.get_node("CharacterAttachmentManager")
	if cam == null:
		_check("CharacterAttachmentManager autoload reachable", false, "got null")
		return
	_check("CharacterAttachmentManager autoload reachable", true)
	if not cam.has_method("can_attach"):
		_check("CharacterAttachmentManager exposes can_attach", false,
			"autoload missing the method (Godot may have fallen back to base Node)")
		return
	_check("CharacterAttachmentManager exposes can_attach", true)
	var gs = root.get_node("GameState")
	# Stash and inject a synthetic pair: a Lone Operative character + a
	# bodyguard with the right keyword to lead.
	var prev_units = gs.state.get("units", {}).duplicate(true)
	gs.state["units"] = {
		"U_LONE_CHAR": {
			"id": "U_LONE_CHAR",
			"owner": 1,
			"meta": {
				"name": "Lone Op Test",
				"keywords": ["CHARACTER", "INFANTRY"],
				"abilities": ["Lone Operative"],
				"leader_data": {"can_lead": ["INFANTRY"]},
			},
		},
		"U_TEST_BG": {
			"id": "U_TEST_BG",
			"owner": 1,
			"meta": {
				"name": "Bodyguard Test",
				"keywords": ["INFANTRY"],
			},
		},
	}
	var result = cam.call("can_attach", "U_LONE_CHAR", "U_TEST_BG")
	gs.state["units"] = prev_units  # restore
	_check("can_attach returns valid=false",
		result is Dictionary and result.get("valid", true) == false,
		"got %s" % str(result))
	if result is Dictionary:
		_check("can_attach reason mentions Lone Operative",
			"Lone Operative" in str(result.get("reason", "")),
			"got reason=%s" % str(result.get("reason", "")))

func _test_formations_phase_rejects() -> void:
	print("\n-- C: FormationsPhase._validate_declare_leader_attachment() rejects Lone Op --")
	# Source-pin: confirm the validator delegates to has_lone_operative.
	# (We can't easily instantiate FormationsPhase headless without a full
	# game state init, so the source pin is the most stable proof.)
	var f = FileAccess.open("res://phases/FormationsPhase.gd", FileAccess.READ)
	if f == null:
		_check("FormationsPhase.gd readable", false)
		return
	var src = f.get_as_text()
	f.close()
	_check("FormationsPhase.gd readable", not src.is_empty())
	_check("_validate_declare_leader_attachment defined",
		"func _validate_declare_leader_attachment" in src)
	_check("validator calls RulesEngine.has_lone_operative",
		"RulesEngine.has_lone_operative" in src,
		"validator must reuse the same canonical check as CharacterAttachmentManager")
	_check("validator emits 'Lone Operative' reason string",
		"Lone Operative units cannot attach" in src,
		"reason string drift will silently break the UI error")

func _test_paths_share_check() -> void:
	print("\n-- D: both paths share the canonical check --")
	# Both files must reference RulesEngine(Data).has_lone_operative — drift
	# (e.g. if one path inlines the abilities loop) would cause silent
	# divergence between deployment and Formations enforcement.
	var f1 = FileAccess.open("res://phases/FormationsPhase.gd", FileAccess.READ)
	var s1 = f1.get_as_text() if f1 else ""
	if f1: f1.close()
	var f2 = FileAccess.open("res://autoloads/CharacterAttachmentManager.gd", FileAccess.READ)
	var s2 = f2.get_as_text() if f2 else ""
	if f2: f2.close()
	_check("FormationsPhase reuses has_lone_operative",
		"has_lone_operative" in s1)
	_check("CharacterAttachmentManager reuses has_lone_operative",
		"has_lone_operative" in s2)

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
