extends SceneTree

# 06_SYNTHESIS audit #5 round 2: per-turn unit-flag reset coverage sync.
#
# Two paths exist for clearing per-turn unit flags at the end of a
# scoring phase:
#   1) GameManager._create_flag_reset_diffs(player)           [multiplayer]
#   2) ScoringPhase._create_flag_reset_changes(player)        [single-player]
#
# A flag missing from one list silently de-syncs MP from SP. The
# Da Jump / has_fought / is_engaged / fight_priority / burned_objective
# bugs were all instances of this drift. This pin makes the lists
# inseparable: every flag that lives in ScoringPhase MUST also live in
# GameManager and vice versa.
#
# Pin verifies:
#   A) Both source files contain a `flags_to_reset = [...]` block.
#   B) The set of flag-name string literals in the two blocks is equal.
#   C) The list contains the regression-flagged mandatory entries
#      (catches a future refactor that drops one of them by accident).
#
# Usage: godot --headless --path . -s tests/test_t005b_flag_reset_sync_pin.gd

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

func _extract_flag_set(src: String, anchor_token: String) -> Dictionary:
	# Locate the `var flags_to_reset = [` block following anchor_token,
	# then scan forward to the matching `]` and pull every "string"
	# literal out of it.
	var anchor = src.find(anchor_token)
	if anchor < 0:
		return {}
	var bracket = src.find("flags_to_reset", anchor)
	if bracket < 0:
		return {}
	var open_b = src.find("[", bracket)
	if open_b < 0:
		return {}
	# Find matching ] at depth 0 (no nested arrays expected here).
	var close_b = src.find("]", open_b)
	if close_b < 0:
		return {}
	var block = src.substr(open_b + 1, close_b - open_b - 1)
	var out := {}
	var i = 0
	while i < block.length():
		var q = block.find("\"", i)
		if q < 0:
			break
		var q2 = block.find("\"", q + 1)
		if q2 < 0:
			break
		var name = block.substr(q + 1, q2 - q - 1)
		# Filter to plain identifiers (snake_case lowercase). Comments
		# inside the array literal aren't lifted because comments live on
		# their own lines and don't contain quoted identifier strings.
		if name.is_valid_identifier() and name == name.to_lower():
			out[name] = true
		i = q2 + 1
	return out

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_t005b_flag_reset_sync_pin ===\n")

	var gm_src = _read("res://autoloads/GameManager.gd")
	var sp_src = _read("res://phases/ScoringPhase.gd")
	_check("GameManager.gd readable", not gm_src.is_empty())
	_check("ScoringPhase.gd readable", not sp_src.is_empty())

	var gm_flags = _extract_flag_set(gm_src, "_create_flag_reset_diffs")
	var sp_flags = _extract_flag_set(sp_src, "_create_flag_reset_changes")
	_check("GameManager flags_to_reset extracted (>=10 entries)", gm_flags.size() >= 10,
		"got %d" % gm_flags.size())
	_check("ScoringPhase flags_to_reset extracted (>=10 entries)", sp_flags.size() >= 10,
		"got %d" % sp_flags.size())

	# Symmetric difference: anything in one but not the other
	var only_gm: Array = []
	var only_sp: Array = []
	for k in gm_flags:
		if not sp_flags.has(k):
			only_gm.append(k)
	for k in sp_flags:
		if not gm_flags.has(k):
			only_sp.append(k)
	only_gm.sort()
	only_sp.sort()
	_check("flags only in GameManager (should be empty)",
		only_gm.is_empty(),
		"GameManager has flags ScoringPhase does not: %s" % str(only_gm))
	_check("flags only in ScoringPhase (should be empty)",
		only_sp.is_empty(),
		"ScoringPhase has flags GameManager does not: %s" % str(only_sp))

	# Mandatory entries -- regressions caught by this list:
	var mandatory = [
		"moved", "advanced", "fell_back", "remained_stationary",
		"cannot_shoot", "cannot_charge", "cannot_move",
		"has_shot", "has_fought", "charged_this_turn", "fights_first",
		"has_been_charged", "is_engaged", "fight_priority",
		"da_jump_used_this_turn", "awaiting_da_jump_placement",
	]
	for f in mandatory:
		_check("mandatory flag '%s' in GameManager.flags_to_reset" % f,
			gm_flags.has(f))
		_check("mandatory flag '%s' in ScoringPhase.flags_to_reset" % f,
			sp_flags.has(f))

	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
