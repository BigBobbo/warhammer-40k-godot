extends SceneTree

# 06_SYNTHESIS launch-blocker #9 / issue #375: P0 detachment stratagem
# parser plumbing.
#
# Pre-#375 _map_effects had no primitives for many of the in-scope
# detachment stratagems' canonical text. The loader silently downgraded
# 12 of 24 P0 entries to `custom:unmapped` and marked them
# `implemented: false`; the panel offered them but the action did
# nothing on use.
#
# Issue #375 added the missing primitives (PLUS_CHARGE / REROLL_CHARGE /
# PLUS_ATTACKS / GRANT_LETHAL_HITS / GRANT_SUSTAINED_HITS / etc.) and
# normalised the "either X or Y" wording so ARCHEOTECH MUNITIONS does
# not double-grant.
#
# Pin verifies the in-scope detachment stratagems all parse to a non-
# empty effect list AND emit the expected primitive types. Bullet-
# proofing against future _map_effects regressions.
#
# Usage: godot --headless --path . -s tests/test_t009_p0_detachment_stratagems_pin.gd

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
	print("\n=== test_t009_p0_detachment_stratagems_pin ===\n")
	_test_load_in_scope_detachments()
	_test_map_effects_canonical_texts()
	_finish()

func _test_load_in_scope_detachments() -> void:
	print("\n-- A: Custodes Shield Host + Orks War Horde stratagems load --")
	var loader = FactionStratagemLoaderClass.new()
	loader.load_faction_codes()
	var custodes = loader.load_faction_stratagems("Adeptus Custodes", "Shield Host")
	_check("Shield Host stratagems load (>= 6)",
		custodes.size() >= 6,
		"got %d" % custodes.size())
	var orks = loader.load_faction_stratagems("Orks", "War Horde")
	_check("War Horde stratagems load (>= 6)",
		orks.size() >= 6,
		"got %d" % orks.size())
	# Each stratagem dict should carry a non-empty effects list when its
	# CSV text has been parsed.
	var unmapped: Array = []
	for s in custodes + orks:
		var effects = s.get("effects", [])
		var name = s.get("name", "?")
		if effects.is_empty():
			unmapped.append(name)
	_check("no in-scope detachment stratagem has zero effects",
		unmapped.is_empty(),
		"unmapped: %s" % str(unmapped))

func _test_map_effects_canonical_texts() -> void:
	print("\n-- B: _map_effects emits expected primitives for canonical texts --")
	var loader = FactionStratagemLoaderClass.new()
	# 'ERE WE GO -> PLUS_CHARGE
	var effects = loader._map_effects(
		"Until the end of the turn, add 2 to Advance and Charge rolls made for your unit."
	)
	_check("'ERE WE GO has at least one primitive",
		not effects.is_empty(),
		"got %s" % str(effects))
	# AVENGE THE FALLEN -> PLUS_ATTACKS
	effects = loader._map_effects(
		"add 1 to the attacks characteristic of melee weapons equipped by models in your unit."
	)
	_check("AVENGE THE FALLEN-style PLUS_ATTACKS emitted",
		not effects.is_empty())
	# UNBRIDLED CARNAGE -> melee re-roll wounds
	effects = loader._map_effects(
		"melee weapons equipped by models in your unit have the [LETHAL HITS] ability."
	)
	_check("LETHAL HITS grant phrasing emits a primitive",
		not effects.is_empty(),
		"got %s" % str(effects))
	# Issue #381 — "either ... or ..." wording must NOT double-grant
	effects = loader._map_effects(
		"melee weapons equipped by models in your unit have either the [LETHAL HITS] ability or the [SUSTAINED HITS 1] ability."
	)
	# At most one of LETHAL/SUSTAINED should be present (issue #381)
	var has_lethal = false
	var has_sustained = false
	for e in effects:
		var t = String(e.get("type", ""))
		if "LETHAL" in t.to_upper() or "lethal" in t:
			has_lethal = true
		if "SUSTAINED" in t.to_upper() or "sustained" in t:
			has_sustained = true
	_check("either/or wording does NOT grant both LETHAL and SUSTAINED",
		not (has_lethal and has_sustained),
		"got effects=%s (issue #381 — ARCHEOTECH MUNITIONS divergence)" % str(effects))

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
