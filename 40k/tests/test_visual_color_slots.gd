extends SceneTree

# T12 — the board-overlay scripts take every colour from UIConstants.
#
# Scope: the nine scripts T12 names (MovementRangeVisual with its DragRuler,
# EngagementRangeVisual, CoherencyCircleVisual, ChargeTrajectoryPreview,
# DeepStrikeExclusionVisual, DamageFeedbackVisual, ChargeArrowVisual,
# DeploymentZoneVisual, AIMovementPathVisual) plus the two twins that shared
# their literals (HumanMovementPathVisual, InfiltratorExclusionVisual).
#
# 1. Source regression net (the task's Tier A grep): no `Color(` and no named
#    `Color.X` constant anywhere in the eleven files, comments included.
# 2. Class walk: every Color constant and every Color script variable (fresh
#    instance) is a UIConstants slot or one of its two neutral chrome
#    backdrops, never an ad-hoc value.
# 3. Semantic map: each constant sits in the slot its meaning calls for, so a
#    wrong-slot swap (green for a failed charge) fails even though it would
#    pass (2).
# 4. UIConstants chrome + with_alpha(): the chrome stays out of the slot table
#    (seven slots, slot_name("") for chrome), with_alpha() keeps the RGB.
# 5. Behaviour through the production code paths: the colours the scripts
#    actually hand to their labels / backdrops / state (damage numbers, kill
#    notification, result summary, coherency in/out, engagement defaults, the
#    drag-ruler outline), and the death debris: every particle a
#    INVALID_RED..WARNING_ORANGE blend darkened at most
#    DEATH_PARTICLE_MAX_DARKEN, drawn from exactly three randf() per particle
#    as before T12 (the replayed RNG stream matches angle / speed / size).
#
# At d612200 (pre-T12) this file does not even parse (UIConstants had no
# chrome constants and no with_alpha()), and the eleven scripts held 101
# literal lines. With T12's UIConstants, swapping one pre-T12 script back in
# fails its source / walk / semantic checks (ChargeArrowVisual alone: 23).
#
# Usage: godot --headless --path . -s tests/test_visual_color_slots.gd

const UIC := preload("res://autoloads/UIConstants.gd")

const SCRIPTS := [
	"MovementRangeVisual", "EngagementRangeVisual", "CoherencyCircleVisual",
	"ChargeTrajectoryPreview", "DeepStrikeExclusionVisual", "DamageFeedbackVisual",
	"ChargeArrowVisual", "DeploymentZoneVisual", "AIMovementPathVisual",
	"HumanMovementPathVisual", "InfiltratorExclusionVisual",
]

# script -> {constant: slot or chrome name}. Every Color constant of every
# script is listed, so a new colour constant has to be classified here too.
const EXPECTED := {
	"MovementRangeVisual.DragRuler": {"SHADOW": "OVERLAY_SHADOW"},
	"CoherencyCircleVisual": {"COLOR_GREEN": "CONFIRMED_GREEN", "COLOR_RED": "INVALID_RED"},
	"ChargeTrajectoryPreview": {
		"TRAJECTORY_COLOR": "WARNING_ORANGE", "SUMMARY_BG_COLOR": "OVERLAY_LABEL_BG",
		"SUMMARY_GOOD_COLOR": "CONFIRMED_GREEN", "SUMMARY_MID_COLOR": "MARGINAL_YELLOW",
		"SUMMARY_HARD_COLOR": "INVALID_RED", "LABEL_BG_COLOR": "OVERLAY_LABEL_BG"},
	"DeepStrikeExclusionVisual": {
		"LINE_COLOR": "INVALID_RED", "GLOW_COLOR": "INVALID_RED", "FILL_COLOR": "INVALID_RED",
		"LABEL_BG_COLOR": "OVERLAY_LABEL_BG"},
	"InfiltratorExclusionVisual": {
		"LINE_COLOR": "INVALID_RED", "GLOW_COLOR": "INVALID_RED", "LABEL_BG_COLOR": "OVERLAY_LABEL_BG"},
	"DamageFeedbackVisual": {
		"DAMAGE_FLASH_COLOR": "INVALID_RED", "DAMAGE_FLASH_CORE_COLOR": "WARNING_ORANGE",
		"DEATH_RING_COLOR": "INVALID_RED", "DEATH_FLASH_COLOR": "WARNING_ORANGE",
		"FLOAT_NUMBER_COLOR_DAMAGE": "INVALID_RED", "FLOAT_NUMBER_COLOR_KILL": "INVALID_RED",
		"KILL_NOTIFY_COLOR": "INVALID_RED", "RESULT_SUMMARY_TEXT_COLOR": "NEUTRAL_UI_PALE_WHITE"},
	"ChargeArrowVisual": {
		"ARROW_COLOR": "WARNING_ORANGE", "ARROW_GLOW_COLOR": "WARNING_ORANGE",
		"ARROW_SUCCESS_COLOR": "CONFIRMED_GREEN", "ARROW_FAIL_COLOR": "INVALID_RED",
		"CHARGE_FLASH_COLOR": "WARNING_ORANGE", "CHARGE_FLASH_CORE_COLOR": "NEUTRAL_UI_PALE_WHITE",
		"LABEL_BG_COLOR": "OVERLAY_LABEL_BG", "PENDING_TEXT_COLOR": "MARGINAL_YELLOW"},
	"DeploymentZoneVisual": {"LABEL_BG_COLOR": "OVERLAY_LABEL_BG"},
	"AIMovementPathVisual": {"P1_TRAIL_COLOR": "FRIENDLY_PLAYER_TEAL", "P2_TRAIL_COLOR": "ENEMY_PLAYER_MAGENTA"},
	"HumanMovementPathVisual": {
		"P1_TRAIL_COLOR": "FRIENDLY_PLAYER_TEAL", "P2_TRAIL_COLOR": "ENEMY_PLAYER_MAGENTA",
		"OVER_CAP_COLOR": "INVALID_RED", "LABEL_BG_COLOR": "OVERLAY_LABEL_BG"},
}

# script -> {script variable: slot} for the Color variables' defaults.
const EXPECTED_VARS := {
	"EngagementRangeVisual": {"circle_color": "WARNING_ORANGE"},
	"CoherencyCircleVisual": {"circle_color": "CONFIRMED_GREEN"},
	"DeploymentZoneVisual": {"border_color": "NEUTRAL_UI_PALE_WHITE"},
}

var passed := 0
var failed := 0
var ui: Node = null


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])


func _init() -> void:
	# Autoloads are added after SceneTree._init — run once they are live.
	call_deferred("_run")


func _run() -> void:
	print("\n=== test_visual_color_slots (T12) ===\n")
	ui = root.get_node_or_null("UIConstants")
	_check("UIConstants autoload is live", ui != null)
	if ui == null:
		_finish()
		return
	_test_source()
	_test_class_walk()
	_test_uiconstants_chrome()
	await _test_behaviour()
	_finish()


func _name_of(c: Color) -> String:
	var n: String = ui.slot_name(c)
	if n == "" and ui.has_method("chrome_name"):
		n = ui.chrome_name(c)
	return n


func _classes() -> Array:
	var out: Array = []
	for n in SCRIPTS:
		out.append([n, load("res://scripts/%s.gd" % n)])
	out.append(["MovementRangeVisual.DragRuler", load("res://scripts/MovementRangeVisual.gd").DragRuler])
	return out


# ---------------------------------------------------------------------------
# 1. source
# ---------------------------------------------------------------------------

func _test_source() -> void:
	print("-- source: no Color( / Color.X in the eleven scripts --")
	var re := RegEx.new()
	re.compile("Color\\(|\\bColor\\.[A-Z]")
	var total := 0
	for n in SCRIPTS:
		var path := "res://scripts/%s.gd" % n
		var text := FileAccess.get_file_as_string(path)
		_check("%s readable" % path, text != "")
		var hits: Array = []
		var lines := text.split("\n")
		for i in range(lines.size()):
			if re.search(lines[i]) != null:
				hits.append("%d: %s" % [i + 1, lines[i].strip_edges()])
		total += hits.size()
		_check("%s has no Color( literal or named Color.X" % n, hits.is_empty(), str(hits))
	_check("eleven scripts, 0 literal lines in total (101 before T12)", total == 0, "%d lines" % total)


# ---------------------------------------------------------------------------
# 2. class walk + 3. semantic map
# ---------------------------------------------------------------------------

func _test_class_walk() -> void:
	print("-- class walk: every Color constant / script variable is a slot or chrome --")
	var colours := 0
	for pair in _classes():
		var label: String = pair[0]
		var s: Script = pair[1]
		_check("%s loads" % label, s != null)
		if s == null:
			continue
		var cm: Dictionary = s.get_script_constant_map()
		var want: Dictionary = EXPECTED.get(label, {})
		var seen: Array = []
		for k in cm:
			if typeof(cm[k]) != TYPE_COLOR:
				continue
			colours += 1
			seen.append(k)
			var c: Color = cm[k]
			var got := _name_of(c)
			_check("%s.%s is a UIConstants colour (%s)" % [label, k, got if got != "" else "#" + c.to_html()],
				got != "")
			_check("%s.%s is opaque (alpha applied at draw time)" % [label, k], c.a == 1.0, "a=%s" % str(c.a))
			_check("%s.%s is %s" % [label, k, str(want.get(k, "<classified in EXPECTED>"))],
				want.has(k) and got == want[k], "got %s" % got)
		for k in want:
			_check("%s still defines %s" % [label, k], k in seen)
		var inst = s.new()
		var want_vars: Dictionary = EXPECTED_VARS.get(label, {})
		for prop in inst.get_property_list():
			if prop.type != TYPE_COLOR or not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
				continue
			colours += 1
			var v: Color = inst.get(prop.name)
			var got := _name_of(v)
			_check("%s.%s default is %s" % [label, prop.name, str(want_vars.get(prop.name, "<classified in EXPECTED_VARS>"))],
				want_vars.has(prop.name) and got == want_vars[prop.name], "got %s (#%s)" % [got, v.to_html()])
		inst.free()
	_check("42 colours walked (constants + script variables)", colours == 42, "walked %d" % colours)


# ---------------------------------------------------------------------------
# 4. UIConstants chrome + with_alpha
# ---------------------------------------------------------------------------

func _test_uiconstants_chrome() -> void:
	print("-- UIConstants neutral chrome + with_alpha --")
	_check("chrome_name() / all_chrome() exist", ui.has_method("chrome_name") and ui.has_method("all_chrome"))
	if not ui.has_method("all_chrome"):
		return
	var chrome: Dictionary = ui.all_chrome()
	_check("two chrome colours", chrome.size() == 2 and chrome.has("OVERLAY_LABEL_BG") and chrome.has("OVERLAY_SHADOW"),
		str(chrome.keys()))
	_check("all_slots() still lists the seven doc §9 slots", ui.all_slots().size() == 7)
	for n in chrome:
		var c: Color = chrome[n]
		_check("%s is opaque" % n, c.a == 1.0)
		_check("%s is no slot (slot_name == \"\")" % n, ui.slot_name(c) == "")
		_check("chrome_name round-trips %s" % n, ui.chrome_name(c) == n)
	for n in ui.all_slots():
		_check("slot %s is no chrome" % n, ui.chrome_name(ui.all_slots()[n]) == "")
	_check("OVERLAY_LABEL_BG is the old label chip #1A140D",
		UIC.OVERLAY_LABEL_BG.to_html(false) == "1a140d", UIC.OVERLAY_LABEL_BG.to_html(false))
	var faded: Color = UIC.with_alpha(UIC.WARNING_ORANGE, 0.25)
	_check("with_alpha keeps RGB and sets alpha (static, via the preloaded script)",
		faded.r == UIC.WARNING_ORANGE.r and faded.g == UIC.WARNING_ORANGE.g
		and faded.b == UIC.WARNING_ORANGE.b and is_equal_approx(faded.a, 0.25))
	_check("with_alpha leaves the constant opaque", UIC.WARNING_ORANGE.a == 1.0)


# ---------------------------------------------------------------------------
# 5. behaviour through the production code paths
# ---------------------------------------------------------------------------

func _test_behaviour() -> void:
	print("-- behaviour: the colours the scripts hand out --")
	var holder := Node2D.new()
	root.add_child(holder)

	# DamageFeedbackVisual: numbers, kill notification, summary, backdrops.
	var dfb = load("res://scripts/DamageFeedbackVisual.gd").new()
	holder.add_child(dfb)
	dfb.play_floating_number(Vector2(100, 100), 3, false)
	dfb.play_floating_number(Vector2(200, 100), 2, true)
	dfb.play_kill_notification(Vector2(300, 100), "Custodian Guard")
	dfb.play_result_summary(Vector2(400, 100), "2 hits, 1 wound")
	var labels := {}
	var backdrops: Array = []
	for c in dfb.get_children():
		if c is Label:
			labels[c.text] = c.get_theme_color("font_color")
		elif c is ColorRect:
			backdrops.append(c.color)
	var shade: float = float(dfb.get_script().get_script_constant_map().get("DEEP_RED_SHADE", -1.0))
	_check("damage number -3 is INVALID_RED", labels.get("-3", Color.TRANSPARENT) == UIC.INVALID_RED,
		str(labels.get("-3", "missing")))
	_check("kill number -2 is INVALID_RED a DEEP_RED_SHADE (0.2) darker",
		shade == 0.2 and labels.get("-2", Color.TRANSPARENT).is_equal_approx(UIC.INVALID_RED.darkened(0.2)),
		str(labels.get("-2", "missing")))
	_check("kill notification is INVALID_RED",
		labels.get("DESTROYED: Custodian Guard", Color.TRANSPARENT) == UIC.INVALID_RED)
	_check("result summary is NEUTRAL_UI_PALE_WHITE",
		labels.get("2 hits, 1 wound", Color.TRANSPARENT) == UIC.NEUTRAL_UI_PALE_WHITE)
	var alphas: Array = []
	var all_shadow := backdrops.size() == 2
	for b in backdrops:
		alphas.append(b.a)
		all_shadow = all_shadow and b.r == 0.0 and b.g == 0.0 and b.b == 0.0
	alphas.sort()
	_check("both backdrops are OVERLAY_SHADOW at 0.70 / 0.75",
		all_shadow and is_equal_approx(alphas[0], 0.7) and is_equal_approx(alphas[1], 0.75),
		"%s %s" % [str(backdrops), str(alphas)])

	# Death debris: slot blend, darkened <= DEATH_PARTICLE_MAX_DARKEN, three
	# randf() per particle (replay the stream the function consumed).
	seed(4242)
	dfb.play_death_animation(Vector2(500, 500), 20.0)
	var parts: Array = []
	for e in dfb._effects:
		if e.type == "death_particles":
			parts = e.particles
	_check("eight debris particles", parts.size() == dfb.DEATH_PARTICLE_COUNT, "%d" % parts.size())
	seed(4242)
	randf()  # _spawn_explosion_sprite: rotation
	var stream_ok := true
	var colour_ok := true
	var max_dark := 0.0
	var r: Color = UIC.INVALID_RED
	var o: Color = UIC.WARNING_ORANGE
	for p in range(parts.size()):
		var angle := (float(p) / float(dfb.DEATH_PARTICLE_COUNT)) * TAU + randf() * 0.3
		var _speed := 20.0 * (1.5 + randf() * 2.0)
		var size := 2.0 + randf() * 3.0
		var t := randf()
		var d := randf() * float(dfb.DEATH_PARTICLE_MAX_DARKEN)
		var a := 0.8 + randf() * 0.2
		var want: Color = UIC.with_alpha(r.lerp(o, t).darkened(d), a)
		var got: Color = parts[p].color
		stream_ok = stream_ok and is_equal_approx(parts[p].angle, angle) and is_equal_approx(parts[p].size, size)
		colour_ok = colour_ok and got.is_equal_approx(want)
		max_dark = max(max_dark, d)
	_check("debris angle / size match the replayed stream (3 randf per particle colour, as before T12)", stream_ok)
	_check("each debris colour is INVALID_RED..WARNING_ORANGE darkened <= %.2f" % dfb.DEATH_PARTICLE_MAX_DARKEN,
		colour_ok and max_dark <= dfb.DEATH_PARTICLE_MAX_DARKEN)
	dfb.clear_all()

	# CoherencyCircleVisual: in / out of coherency.
	var cc = load("res://scripts/CoherencyCircleVisual.gd").new()
	holder.add_child(cc)
	cc.set_in_range(false)
	_check("coherency out of range -> INVALID_RED", cc.circle_color == UIC.INVALID_RED)
	cc.set_in_range(true)
	_check("coherency in range -> CONFIRMED_GREEN", cc.circle_color == UIC.CONFIRMED_GREEN)

	# EngagementRangeVisual: a caller that omits the colour gets the slots.
	var er = load("res://scripts/EngagementRangeVisual.gd").new()
	holder.add_child(er)
	er.setup_engagement_range(60.0)
	_check("engagement ring default -> WARNING_ORANGE", er.circle_color == UIC.WARNING_ORANGE)
	er.setup_target_highlight(35.0)
	_check("eligible target default -> CONFIRMED_GREEN", er.circle_color == UIC.CONFIRMED_GREEN)
	er.setup_engagement_range(60.0, Color(0.85, 0.6, 0.2, 1.0))
	_check("a caller's own colour still wins (PersistentEngagementOverlay amber)",
		er.circle_color.is_equal_approx(Color(0.85, 0.6, 0.2, 1.0)))

	# DragRuler: slot runs and the OVERLAY_SHADOW outline on its label.
	var dr = load("res://scripts/MovementRangeVisual.gd").DragRuler.new()
	holder.add_child(dr)
	_check("drag ruler slot colours", dr.slot_color("CONFIRMED_GREEN") == UIC.CONFIRMED_GREEN
		and dr.slot_color("MARGINAL_YELLOW") == UIC.MARGINAL_YELLOW and dr.slot_color("INVALID_RED") == UIC.INVALID_RED)
	var outline: Color = dr.get_node("DragRulerLabel").get_theme_color("font_outline_color")
	_check("drag ruler label outline is OVERLAY_SHADOW at 0.6",
		outline.is_equal_approx(UIC.with_alpha(UIC.OVERLAY_SHADOW, 0.6)), str(outline))

	await process_frame
	holder.queue_free()
	await process_frame


func _finish() -> void:
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
