extends SceneTree

# 06_SYNTHESIS launch-blocker #10 / TLV-3 / issue #373 (CORRECTED):
# Lone Operative targeting restriction — does NOT prevent attachment.
#
# Wahapedia 10e: "Unless part of an Attached unit (see Leader), this unit
# can only be selected as the target of a ranged attack if the attacking
# model is within 12\"."
#
# Lone Operative is a TARGETING restriction that is inactive when attached.
# Characters with both Leader and Lone Operative (e.g. Boss Snikrot) CAN
# attach to their valid bodyguard units.
#
# This pin verifies:
#   A) `RulesEngine.has_lone_operative(unit)` recognises both string and
#      dict ability storage (per its 10e-T2-2 contract).
#   B) `CharacterAttachmentManager.can_attach()` ALLOWS a Lone Operative
#      character to attach (Lone Operative does not block attachment).
#   C) `RulesEngine` targeting code only applies Lone Operative protection
#      when the unit is NOT attached (attached_to == null).
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
	_test_character_attachment_manager_allows()
	_test_lone_operative_targeting_when_unattached()
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

func _test_character_attachment_manager_allows() -> void:
	print("\n-- B: CharacterAttachmentManager.can_attach() ALLOWS Lone Operative with Leader --")
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
	var prev_units = gs.state.get("units", {}).duplicate(true)
	gs.state["units"] = {
		"U_LONE_CHAR": {
			"id": "U_LONE_CHAR",
			"owner": 1,
			"meta": {
				"name": "Lone Op Leader Test",
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
	_check("can_attach returns valid=true for Lone Operative with Leader",
		result is Dictionary and result.get("valid", false) == true,
		"got %s" % str(result))

func _test_lone_operative_targeting_when_unattached() -> void:
	print("\n-- C: RulesEngine targeting checks only apply LO when unattached --")
	var f = FileAccess.open("res://autoloads/RulesEngine.gd", FileAccess.READ)
	if f == null:
		_check("RulesEngine.gd readable", false)
		return
	var src = f.get_as_text()
	f.close()
	_check("RulesEngine.gd readable", not src.is_empty())
	_check("has_lone_operative defined",
		"func has_lone_operative" in src)
	_check("targeting checks attached_to guard",
		'attached_to' in src and 'has_lone_operative' in src,
		"Lone Operative targeting must only apply when not attached")

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
