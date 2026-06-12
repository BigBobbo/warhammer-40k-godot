extends SceneTree

# ISS-032: AI cache save/load policy — reset-by-design. Strategic caches
# are not serialized; they must be cleared whenever a game is loaded.
#
# Usage: godot --headless --path . -s tests/test_iss032_ai_cache_policy.gd

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
	print("\n=== test_iss032_ai_cache_policy ===\n")
	var ai_player = root.get_node_or_null("AIPlayer")
	var slm = root.get_node_or_null("SaveLoadManager")
	var aidm = load("res://scripts/AIDecisionMaker.gd")

	# Seed some strategy caches as a mid-game AI would
	aidm._focus_fire_plan["U_X"] = {"target": "U_Y"}
	aidm._focus_fire_plan_built = true
	aidm._phase_plan["move"] = ["U_X"]
	aidm._phase_plan_built = true
	_check("caches seeded", aidm._focus_fire_plan_built and not aidm._focus_fire_plan.is_empty())

	# Policy is wired: AIPlayer listens to load_completed directly
	_check("AIPlayer subscribed to load_completed",
		slm != null and ai_player != null
		and slm.load_completed.is_connected(ai_player._on_save_load_completed))

	# Emitting load_completed clears the caches
	slm.emit_signal("load_completed", "test://fake", {})
	_check("focus-fire cache cleared on load",
		aidm._focus_fire_plan.is_empty() and aidm._focus_fire_plan_built == false)
	_check("phase plan cleared on load",
		aidm._phase_plan.is_empty() and aidm._phase_plan_built == false)

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
