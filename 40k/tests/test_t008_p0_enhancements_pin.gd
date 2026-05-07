extends SceneTree

# 06_SYNTHESIS launch-blocker #8 / issue #374: P0 enhancement effect
# handlers (Adeptus Custodes Shield Host + Orks War Horde, 8 in scope).
#
# Pre-#374 ABILITY_EFFECTS had no entries for these enhancements; the
# StatsCardPopup showed only the printed text and zero runtime effect
# was emitted. Issue #374 added structured ABILITY_EFFECTS rows with
# `condition: "enhancement"` so _apply_enhancement_abilities picks them
# up via unit.meta.enhancements[] and translates them into effect_*
# flags (effect_plus_strength_melee, effect_plus_damage,
# effect_ignores_cover, effect_plus_move, effect_devastating_wounds,
# effect_fall_back_and_shoot, effect_fall_back_and_charge, effect_fnp).
#
# Two of the eight (Auric Mantle, Castellan's Mark) are intentionally
# `implemented: false` because they are list-build mutations / pre-game
# actions, not runtime effects.
#
# Pin verifies:
#   A) All 8 in-scope P0 enhancement names exist in ABILITY_EFFECTS.
#   B) The 6 runtime-effect entries are `implemented: true`.
#   C) The 2 list-build / pre-game entries are `implemented: false`
#      (intentional — kept so popups can show the rule text).
#   D) Each runtime entry has a non-empty effects list keyed by
#      `condition: "enhancement"`.
#
# Usage: godot --headless --path . -s tests/test_t008_p0_enhancements_pin.gd

var passed := 0
var failed := 0

const RUNTIME_IMPLEMENTED = [
	"From the Hall of Armouries",
	"Panoptispex",
	"Follow Me Ladz",
	"Headwoppa's Killchoppa",
	"Kunnin' But Brutal",
	"Supa-Cybork Body",
]
const LIST_BUILD_OR_PREGAME = [
	"Auric Mantle",          # +2 Wounds applied at army instantiation
	"Castellan's Mark",       # Deployment-phase redeploy action
]

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
	print("\n=== test_t008_p0_enhancements_pin ===\n")
	var uam = root.get_node_or_null("UnitAbilityManager")
	if uam == null:
		_check("UnitAbilityManager autoload reachable", false)
		_finish()
		return
	_check("UnitAbilityManager autoload reachable", true)
	var ABILITY_EFFECTS = uam.get_script().get_script_constant_map().get("ABILITY_EFFECTS", {})
	_check("ABILITY_EFFECTS map non-empty", ABILITY_EFFECTS.size() > 0)
	for name in RUNTIME_IMPLEMENTED:
		_check("ABILITY_EFFECTS has '%s'" % name, ABILITY_EFFECTS.has(name))
		if ABILITY_EFFECTS.has(name):
			var entry = ABILITY_EFFECTS[name]
			_check("'%s' condition == enhancement" % name,
				String(entry.get("condition", "")) == "enhancement")
			_check("'%s' implemented == true" % name,
				entry.get("implemented", false) == true)
			_check("'%s' effects[] non-empty" % name,
				entry.get("effects", []).size() > 0,
				"runtime enhancement with no effects -> nothing fires")
	for name in LIST_BUILD_OR_PREGAME:
		_check("ABILITY_EFFECTS has '%s' (list-build/pregame)" % name,
			ABILITY_EFFECTS.has(name))
		if ABILITY_EFFECTS.has(name):
			var entry = ABILITY_EFFECTS[name]
			_check("'%s' condition == enhancement" % name,
				String(entry.get("condition", "")) == "enhancement")
			# implemented:false is INTENTIONAL for these two entries
			_check("'%s' implemented == false (intentional — pre-game / list-build)" % name,
				entry.get("implemented", true) == false,
				"runtime effect path would mis-fire")
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
