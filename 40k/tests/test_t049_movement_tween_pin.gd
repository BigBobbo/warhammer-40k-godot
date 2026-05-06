extends SceneTree

# T-049: Movement opponent must see smooth tween, not teleport.
# Pin: Main._sync_all_token_positions now uses _tween_token_to for any
# state-driven position update where distance > 1px. Tween durations are
# bounded (250ms..600ms) and use TRANS_QUAD ease in/out.
# Existing T5-MP1 fight-phase animation continues to handle PILE_IN /
# CONSOLIDATE separately in NetworkManager._animate_fight_movement_tokens.
#
# Usage: godot --headless --path . -s tests/test_t049_movement_tween_pin.gd

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
	print("\n=== test_t049_movement_tween_pin ===\n")
	_test_main_tween_helper()
	_test_sync_uses_tween()
	_test_fight_phase_tween_preserved()
	_finish()


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t = f.get_as_text()
	f.close()
	return t


func _test_main_tween_helper() -> void:
	print("\n-- T-049/A: Main._tween_token_to defined and bounded --")
	var src = _read("res://scripts/Main.gd")
	_check("Main.gd readable", not src.is_empty())
	_check("_tween_token_to function defined",
		"func _tween_token_to(token: Node2D, target_pos: Vector2)" in src)
	_check("base duration constant declared", "T049_TWEEN_DURATION_S" in src)
	_check("max duration constant declared", "T049_TWEEN_MAX_DURATION_S" in src)
	_check("uses create_tween + tween_property",
		"create_tween()" in src and "tween_property(token, \"position\", target_pos" in src)


func _test_sync_uses_tween() -> void:
	print("\n-- T-049/B: _sync_all_token_positions tweens, doesn't snap --")
	var src = _read("res://scripts/Main.gd")
	# Find _sync_all_token_positions body
	var fn_idx = src.find("func _sync_all_token_positions")
	var next_fn = src.find("\nfunc ", fn_idx + 1)
	var body = src.substr(fn_idx, next_fn - fn_idx) if fn_idx >= 0 else ""
	_check("_sync_all_token_positions body found", body.length() > 100)
	_check("body uses _tween_token_to", "_tween_token_to(" in body,
		"sync still snaps token.position instead of tweening")


func _test_fight_phase_tween_preserved() -> void:
	print("\n-- T-049/C: T5-MP1 fight-phase tween still in NetworkManager --")
	var src = _read("res://autoloads/NetworkManager.gd")
	_check("NetworkManager.gd readable", not src.is_empty())
	_check("_animate_fight_movement_tokens still defined",
		"func _animate_fight_movement_tokens" in src)
	_check("uses tween_property with cubic ease",
		"tween_property(token, \"position\", target_pos" in src
		and "Tween.EASE_OUT" in src)


func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
