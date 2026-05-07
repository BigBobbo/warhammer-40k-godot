extends SceneTree

# 06_SYNTHESIS launch-blocker #4 / TLV-7 / issues #372 + #375:
# Charge-modifier effect primitives in FactionStratagemLoader._map_effects.
#
# Pre-#372 the loader had no PLUS_CHARGE / REROLL_CHARGE primitives, so
# 'ERE WE GO (+2 Advance and Charge), Plummeting Descent (re-roll charge),
# Swift Onslaught (re-roll charge), and ~10 other stratagems silently
# downgraded to `custom:unmapped` and were marked `implemented:false`.
# Pre-#375 the PLUS_ATTACKS primitive was also missing for AVENGE THE
# FALLEN-style "add N to the Attacks characteristic" effects.
#
# Pin verifies the primitives + their parser regex still wire correctly:
#   A) Source pin: REROLL_CHARGE branch on charge re-roll wording.
#   B) Source pin: PLUS_CHARGE branch parses "add N to ... charge rolls".
#   C) Source pin: PLUS_ATTACKS branch parses "add N to the attacks
#      characteristic".
#   D) Driving _map_effects against canonical stratagem texts produces
#      the expected primitive types and values:
#        - 'ERE WE GO -> PLUS_CHARGE value=2 (Advance + Charge)
#        - "re-roll the charge roll" -> REROLL_CHARGE
#        - "add 2 to the attacks characteristic of melee weapons"
#          -> PLUS_ATTACKS value=2 scope=melee
#
# Usage: godot --headless --path . -s tests/test_t004_charge_modifier_primitives_pin.gd

const FactionStratagemLoaderClass = preload("res://autoloads/FactionStratagemLoader.gd")
const EffectPrimitivesDataClass = preload("res://autoloads/EffectPrimitives.gd")

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
	print("\n=== test_t004_charge_modifier_primitives_pin ===\n")
	_test_source_pins()
	_test_drive_map_effects()
	_finish()

func _test_source_pins() -> void:
	print("\n-- A/B/C: source pins for charge + attacks primitives --")
	var src = _read("res://autoloads/FactionStratagemLoader.gd")
	_check("FactionStratagemLoader.gd readable", not src.is_empty())
	_check("REROLL_CHARGE primitive emitted on `re-roll the charge roll`",
		"REROLL_CHARGE" in src and "re-roll the charge roll" in src,
		"Issue #372 — Plummeting Descent / Swift Onslaught et al")
	_check("PLUS_CHARGE primitive emitted with value parsed from text",
		"PLUS_CHARGE" in src and "advance and )?charge rolls" in src,
		"Issue #375 — 'ERE WE GO +2 to Advance and Charge")
	_check("PLUS_ATTACKS primitive emitted with value parsed from text",
		"PLUS_ATTACKS" in src and "add (\\\\d) to the attacks characteristic" in src,
		"Issue #375 — AVENGE THE FALLEN +1/+2 melee attacks")

func _test_drive_map_effects() -> void:
	print("\n-- D: drive _map_effects against canonical stratagem texts --")
	var loader = FactionStratagemLoaderClass.new()
	# 'ERE WE GO canonical text -> PLUS_CHARGE value=2
	var ere_we_go_text = "Until the end of the turn, add 2 to Advance and Charge rolls made for your unit."
	var ere_we_go_effects: Array = loader._map_effects(ere_we_go_text)
	var plus_charge_match = {}
	for e in ere_we_go_effects:
		if int(e.get("type", -1)) == int(EffectPrimitivesDataClass.PLUS_CHARGE):
			plus_charge_match = e
			break
	_check("'ERE WE GO maps to PLUS_CHARGE",
		not plus_charge_match.is_empty(),
		"got effects=%s" % str(ere_we_go_effects))
	_check("'ERE WE GO PLUS_CHARGE value == 2",
		int(plus_charge_match.get("value", -1)) == 2,
		"got value=%s" % str(plus_charge_match.get("value", "")))

	# Re-roll-the-charge-roll text -> REROLL_CHARGE
	var reroll_text = "the unit can re-roll the charge roll for that charge."
	var reroll_effects: Array = loader._map_effects(reroll_text)
	var reroll_match = false
	for e in reroll_effects:
		if int(e.get("type", -1)) == int(EffectPrimitivesDataClass.REROLL_CHARGE):
			reroll_match = true
			break
	_check("re-roll charge phrasing maps to REROLL_CHARGE",
		reroll_match,
		"got effects=%s" % str(reroll_effects))

	# AVENGE THE FALLEN-style PLUS_ATTACKS
	var add_attacks_text = "add 2 to the attacks characteristic of melee weapons equipped by models in your unit."
	var add_attacks_effects: Array = loader._map_effects(add_attacks_text)
	var plus_attacks = {}
	for e in add_attacks_effects:
		if int(e.get("type", -1)) == int(EffectPrimitivesDataClass.PLUS_ATTACKS):
			plus_attacks = e
			break
	_check("add-attacks phrasing maps to PLUS_ATTACKS",
		not plus_attacks.is_empty(),
		"got effects=%s" % str(add_attacks_effects))
	_check("PLUS_ATTACKS value == 2",
		int(plus_attacks.get("value", -1)) == 2)
	_check("PLUS_ATTACKS scope == melee",
		String(plus_attacks.get("scope", "")) == "melee")

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
