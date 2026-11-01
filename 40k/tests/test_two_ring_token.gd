extends SceneTree

# T08 — two-ring token (design doc §2).
#
# Covers the parts of TokenVisual's two rings that do not need a window:
#   - every token carries FactionRing (inner) and SlotRing (outer) child nodes;
#     SlotRing.scale > FactionRing.scale and both rest at alpha >= 0.9
#   - SlotRing.modulate is the owner's player-slot colour from UIConstants
#     (FRIENDLY_PLAYER_TEAL for P1, ENEMY_PLAYER_MAGENTA for P2), the same on
#     every unit of that player
#   - FactionRing.modulate is the unit's colour from the army data: a colour of
#     the owner's faction palette (Custodes gold for the first Custodes squad,
#     Ork green for the first Ork squad), distinct for two same-name squads,
#     and it follows Right-click > Change Color
#   - the rings are painted by the letter style only (visible flag follows the
#     unit style and debug mode)
#   - ring geometry stays inside the base, the slot ring is the thinner of the
#     two, the bands do not overlap and the faction band stays in the outer
#     part of the base (clear of the central letter / art)
#   - the MA-20 model-type ring sits just inside the slot ring, not on it
#   - T19 interplay: the colour sync keeps a pulsed alpha, and stop_pulse()
#     returns the slot ring to the resting T08 alpha (not the old 0.7)
#
# Pixel rendering (the rings actually painted beneath the art) is covered by the
# windowed scenario tests/scenarios/visual/T08_two_ring_token.json.
#
# Usage: godot --headless --path . -s tests/test_two_ring_token.gd

var passed := 0
var failed := 0
var _ran := false


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])


func _init():
	create_timer(0.1).timeout.connect(_run_tests)


func _finish() -> void:
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _unit(owner: int, unit_name: String, keywords: Array, base_mm: int) -> Dictionary:
	return {
		"owner": owner,
		"status": 2,
		"meta": {"name": unit_name, "display_name": unit_name, "keywords": keywords},
		"flags": {},
		"models": [{"id": "m1", "alive": true, "wounds": 1, "current_wounds": 1,
			"base_mm": base_mm, "position": {"x": 100.0, "y": 100.0}}],
	}


func _token(TV, uid: String, owner: int, model: Dictionary) -> Node2D:
	var t = TV.new()
	t.owner_player = owner
	t.set_model_data(model.duplicate(true))
	t.set_meta("unit_id", uid)
	t.set_meta("model_id", "m1")
	root.add_child(t)
	return t


var FP = null  # FactionPalettes, loaded at runtime (it references the GameState autoload)


func _palette_hexes(faction_name: String) -> Array:
	var out: Array = []
	for c in FP.get_palette(faction_name):
		out.append(c.to_html(false))
	return out


func _run_tests() -> void:
	if _ran:
		return
	_ran = true
	print("\n=== test_two_ring_token (T08) ===\n")
	var gs = root.get_node_or_null("GameState")
	var uic = root.get_node_or_null("UIConstants")
	var ss = root.get_node_or_null("SettingsService")
	if gs == null or uic == null or ss == null:
		_check("GameState / UIConstants / SettingsService reachable", false)
		_finish()
		return
	var TV = load("res://scripts/TokenVisual.gd")
	FP = load("res://scripts/FactionPalettes.gd")
	_check("TokenVisual and FactionPalettes scripts load", TV != null and FP != null)
	if TV == null or FP == null:
		_finish()
		return

	# Default token look: letter style, ring colour display.
	ss.unit_visual_style = "letter"
	ss.unit_color_display_mode = "ring"

	# Army data: P1 Adeptus Custodes (two same-name Custodian Guard squads),
	# P2 Orks. Unit colours start unassigned, as on a fresh deployment.
	gs.state["factions"] = {"1": {"name": "Adeptus Custodes"}, "2": {"name": "Orks"}}
	gs.state["unit_visuals"] = {}
	gs.state["units"] = {
		"U_T08_GUARD_A": _unit(1, "Custodian Guard", ["ADEPTUS CUSTODES", "INFANTRY"], 40),
		"U_T08_GUARD_B": _unit(1, "Custodian Guard", ["ADEPTUS CUSTODES", "INFANTRY"], 40),
		"U_T08_WITCH_C": _unit(1, "Witchseekers", ["ADEPTUS CUSTODES", "ANATHEMA PSYKANA", "INFANTRY"], 32),
		"U_T08_BOYZ_A": _unit(2, "Boyz", ["ORKS", "INFANTRY"], 32),
	}
	var guard_a := _token(TV, "U_T08_GUARD_A", 1, gs.state["units"]["U_T08_GUARD_A"]["models"][0])
	var guard_b := _token(TV, "U_T08_GUARD_B", 1, gs.state["units"]["U_T08_GUARD_B"]["models"][0])
	var witch := _token(TV, "U_T08_WITCH_C", 1, gs.state["units"]["U_T08_WITCH_C"]["models"][0])
	var boyz := _token(TV, "U_T08_BOYZ_A", 2, gs.state["units"]["U_T08_BOYZ_A"]["models"][0])
	var tokens := {"U_T08_GUARD_A": guard_a, "U_T08_GUARD_B": guard_b, "U_T08_WITCH_C": witch, "U_T08_BOYZ_A": boyz}

	# --- 1. Nodes, scale, alpha, slot colour, faction colour from army data ---
	for uid in tokens:
		var t: Node2D = tokens[uid]
		var f = t.get_node_or_null("FactionRing")
		var s = t.get_node_or_null("SlotRing")
		_check("%s has FactionRing and SlotRing" % uid, f != null and s != null)
		if f == null or s == null:
			continue
		_check("%s SlotRing.scale > FactionRing.scale (outer larger)" % uid,
			s.scale.x > f.scale.x and s.scale.y > f.scale.y, "%s vs %s" % [s.scale, f.scale])
		_check("%s both rings at alpha >= 0.9" % uid, f.modulate.a >= 0.9 and s.modulate.a >= 0.9,
			"faction %.2f slot %.2f" % [f.modulate.a, s.modulate.a])
		var owner: int = int(gs.state["units"][uid]["owner"])
		var want_slot: Color = uic.FRIENDLY_PLAYER_TEAL if owner == 1 else uic.ENEMY_PLAYER_MAGENTA
		_check("%s SlotRing.modulate == %s" % [uid, "FRIENDLY_PLAYER_TEAL" if owner == 1 else "ENEMY_PLAYER_MAGENTA"],
			s.modulate == want_slot, "%s" % s.modulate)
		var unit_color: Color = gs.get_unit_color(uid)
		_check("%s FactionRing.modulate == the unit's colour in the army data" % uid,
			unit_color != Color.TRANSPARENT and f.modulate == unit_color,
			"ring %s unit %s" % [f.modulate.to_html(), unit_color.to_html()])
		var faction_name: String = gs.get_faction_name(owner)
		_check("%s FactionRing colour is from the %s faction palette" % [uid, faction_name],
			f.modulate.to_html(false) in _palette_hexes(faction_name), f.modulate.to_html(false))
		_check("%s rings are painted in the letter style (visible)" % uid, f.visible and s.visible)

	var custodes_gold: String = FP.get_primary_color("Adeptus Custodes").to_html(false)
	var ork_green: String = FP.get_primary_color("Orks").to_html(false)
	_check("Custodes palette gold is d9b333", custodes_gold == "d9b333", custodes_gold)
	_check("first Custodes squad's FactionRing is Custodes gold",
		guard_a.get_node("FactionRing").modulate.to_html(false) == custodes_gold,
		guard_a.get_node("FactionRing").modulate.to_html(false))
	_check("first Ork squad's FactionRing is Ork green",
		boyz.get_node("FactionRing").modulate.to_html(false) == ork_green,
		boyz.get_node("FactionRing").modulate.to_html(false))
	_check("two same-name squads keep distinct inner rings",
		guard_a.get_node("FactionRing").modulate != guard_b.get_node("FactionRing").modulate)
	_check("every P1 unit shares one outer ring colour",
		guard_a.get_node("SlotRing").modulate == guard_b.get_node("SlotRing").modulate
		and guard_b.get_node("SlotRing").modulate == witch.get_node("SlotRing").modulate)
	_check("the two rings of a token differ in colour",
		guard_a.get_node("FactionRing").modulate != guard_a.get_node("SlotRing").modulate
		and boyz.get_node("FactionRing").modulate != boyz.get_node("SlotRing").modulate)

	# --- 2. Change Color reaches the inner ring; the outer ring stays ---
	var new_color: Color = FP.get_palette("Adeptus Custodes")[3]
	gs.set_unit_color("U_T08_WITCH_C", new_color)
	witch.t08_refresh_ring_colors()
	_check("Change Color repaints FactionRing with the picked colour",
		witch.get_node("FactionRing").modulate.to_html(false) == new_color.to_html(false),
		witch.get_node("FactionRing").modulate.to_html(false))
	_check("Change Color leaves SlotRing on the slot colour",
		witch.get_node("SlotRing").modulate == uic.FRIENDLY_PLAYER_TEAL)
	_check("Change Color keeps the inner ring opaque",
		witch.get_node("FactionRing").modulate.a >= 0.9)

	# --- 3. Owner change re-slots the outer ring ---
	witch.owner_player = 2
	witch.t08_refresh_ring_colors()
	_check("owner change -> SlotRing becomes ENEMY_PLAYER_MAGENTA",
		witch.get_node("SlotRing").modulate == uic.ENEMY_PLAYER_MAGENTA)
	witch.owner_player = 1
	witch.t08_refresh_ring_colors()

	# --- 4. A token without a unit falls back to the army's faction colour ---
	var bare = TV.new()
	bare.owner_player = 2
	root.add_child(bare)
	var want_fallback: Color = uic.faction_color_for_player(2)
	want_fallback.a = 1.0
	_check("token without a unit: FactionRing == UIConstants.faction_color_for_player(owner)",
		bare.get_node("FactionRing").modulate == want_fallback,
		"%s vs %s" % [bare.get_node("FactionRing").modulate, want_fallback])

	# --- 5. Painted only by the letter style ---
	ss.unit_visual_style = "classic"
	guard_a._on_unit_style_changed("classic")
	_check("classic style: rings not painted (hidden)",
		not guard_a.get_node("FactionRing").visible and not guard_a.get_node("SlotRing").visible)
	ss.unit_visual_style = "letter"
	guard_a._on_unit_style_changed("letter")
	_check("back to letter style: rings painted again",
		guard_a.get_node("FactionRing").visible and guard_a.get_node("SlotRing").visible)
	guard_a.set_debug_mode(true)
	_check("debug mode: rings not painted", not guard_a.get_node("SlotRing").visible)
	guard_a.set_debug_mode(false)
	_check("debug mode off: rings painted", guard_a.get_node("SlotRing").visible)

	# --- 6. Geometry: inside the base, slot ring thinner, no overlap, clear of the centre ---
	# (has_method guards: a missing helper fails a check instead of aborting the
	# run with a SCRIPT ERROR that never reaches _finish().)
	var geo_token: Node2D = guard_a
	var has_geo: bool = geo_token.has_method("_t08_ring_geometry") \
		and geo_token.has_method("_t08_model_type_ring_radius") and geo_token.has_method("t08_ring_geometry")
	_check("ring geometry helpers exist (_t08_ring_geometry, _t08_model_type_ring_radius, t08_ring_geometry)", has_geo)
	for r in ([19.69, 25.2, 31.5, 47.24, 78.74, 120.0] if has_geo else []):
		var g: Dictionary = geo_token._t08_ring_geometry(r)
		var slot_outer: float = g["slot_mid"] + g["slot_width"] * 0.5
		var slot_inner: float = g["slot_mid"] - g["slot_width"] * 0.5
		var fac_outer: float = g["faction_mid"] + g["faction_width"] * 0.5
		var fac_inner: float = g["faction_mid"] - g["faction_width"] * 0.5
		_check("r=%.1f slot ring stays inside the base rim" % r, slot_outer <= r + 0.001, "outer %.2f" % slot_outer)
		_check("r=%.1f slot ring is the thinner ring" % r, g["slot_width"] < g["faction_width"],
			"%.2f vs %.2f" % [g["slot_width"], g["faction_width"]])
		_check("r=%.1f bands separated by a gap" % r, slot_inner - fac_outer >= 0.5,
			"gap %.2f" % (slot_inner - fac_outer))
		_check("r=%.1f faction band clear of the centre (inner edge >= 0.55r)" % r, fac_inner >= 0.55 * r,
			"inner %.2f" % fac_inner)
		_check("r=%.1f MA-20 type ring sits inside the slot ring" % r,
			geo_token._t08_model_type_ring_radius(r) + 1.0 <= slot_inner + 0.001)
	var seam: Dictionary = guard_a.t08_ring_geometry() if has_geo else {}
	_check("t08_ring_geometry() seam reports the token's base radius (40mm = 31.5px)",
		absf(float(seam.get("radius", 0.0)) - 31.496) < 0.05, str(seam.get("radius")))

	# --- 7. T19 interplay ---
	var slot_ring = guard_b.get_node("SlotRing")
	var has_sync: bool = guard_b.has_method("_t08_sync_ring_colors")
	_check("ring colour sync helper exists (_t08_sync_ring_colors)", has_sync)
	if has_sync:
		slot_ring.modulate.a = 0.75
		guard_b._t08_sync_ring_colors()
		_check("colour sync keeps a pulsed slot alpha", is_equal_approx(slot_ring.modulate.a, 0.75),
			"%.2f" % slot_ring.modulate.a)
		_check("colour sync keeps the slot colour", Color(slot_ring.modulate, 1.0) == uic.FRIENDLY_PLAYER_TEAL)
	guard_b.start_pulse()
	_check("start_pulse sets is_pulsing", guard_b.is_pulsing)
	guard_b.stop_pulse()
	var rest_alpha: float = float(guard_b.get("T08_RING_ALPHA")) if guard_b.get("T08_RING_ALPHA") != null else -1.0
	_check("stop_pulse returns SlotRing to the resting alpha (>= 0.9)",
		rest_alpha >= 0.9 and is_equal_approx(slot_ring.modulate.a, rest_alpha),
		"alpha %.2f rest %.2f" % [slot_ring.modulate.a, rest_alpha])

	_finish()
