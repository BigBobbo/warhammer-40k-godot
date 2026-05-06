extends SceneTree

# T-023: pre-game / general stratagem UI shell — must list all eligible
# stratagems for the active phase + player with CP cost and eligibility state.
#
# Pins: scripts/StratagemPanel.gd exists with populate(player, phase_id);
# scenes/Main.tscn has the StratagemPanelButton; scripts/Main.gd wires the
# toggle + KEY_S hotkey + use-requested handler.
#
# Usage: godot --headless --path . -s tests/test_t023_stratagem_panel_pin.gd

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
	print("\n=== test_t023_stratagem_panel_pin ===\n")
	_test_panel_script_present()
	_test_main_scene_button_present()
	_test_main_gd_wires_panel()
	_finish()


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t = f.get_as_text()
	f.close()
	return t


func _test_panel_script_present() -> void:
	print("\n-- T-023/A: StratagemPanel.gd exists with required API --")
	var src = _read("res://scripts/StratagemPanel.gd")
	_check("scripts/StratagemPanel.gd readable", not src.is_empty())
	_check("class_name StratagemPanel", "class_name StratagemPanel" in src)
	_check("extends AcceptDialog", "extends AcceptDialog" in src)
	_check("populate(player, phase_id) signature",
		"func populate(player: int, phase_id: int" in src)
	_check("calls StratagemManager.can_use_stratagem", "can_use_stratagem" in src)
	_check("renders CP cost", "CP" in src and "cp_cost" in src)
	_check("group buckets Core/Faction/Detachment",
		"Core" in src and "Faction" in src and "Detachment" in src)
	_check("greys out ineligible rows", "Color(0.55, 0.55, 0.55)" in src)
	_check("emits stratagem_use_requested signal",
		"signal stratagem_use_requested" in src and "emit_signal(\"stratagem_use_requested\"" in src)


func _test_main_scene_button_present() -> void:
	print("\n-- T-023/B: Main.tscn contains StratagemPanelButton --")
	var src = _read("res://scenes/Main.tscn")
	_check("Main.tscn readable", not src.is_empty())
	_check("StratagemPanelButton node declared",
		"[node name=\"StratagemPanelButton\" type=\"Button\" parent=\"HUD_Bottom/HBoxContainer\"]" in src)
	_check("button text=Stratagems", "text = \"Stratagems\"" in src)


func _test_main_gd_wires_panel() -> void:
	print("\n-- T-023/C: Main.gd wires button + KEY_S hotkey + use handler --")
	var src = _read("res://scripts/Main.gd")
	_check("Main.gd readable", not src.is_empty())
	_check("preload of StratagemPanel script",
		"preload(\"res://scripts/StratagemPanel.gd\")" in src)
	_check("@onready stratagem_panel_button declared",
		"@onready var stratagem_panel_button" in src)
	_check("_toggle_stratagem_panel function defined",
		"func _toggle_stratagem_panel" in src)
	_check("KEY_S hotkey wired in _input",
		"event.keycode == KEY_S" in src and "_toggle_stratagem_panel" in src)
	_check("button.pressed connected to toggle",
		"stratagem_panel_button.pressed.connect(_toggle_stratagem_panel)" in src)
	_check("use-requested handler wires StratagemManager.use_stratagem",
		"func _on_stratagem_panel_use_requested" in src
		and "use_stratagem" in src)


func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
