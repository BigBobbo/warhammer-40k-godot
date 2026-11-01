extends SceneTree

# T15 — unit-type silhouette glyphs (design doc §2: "faction = hue, type =
# silhouette").
#
# Covers the parts of TokenVisual's silhouette glyph and letter label that do
# not need a window:
#   - TokenVisual.silhouette_category_for_keywords() maps keyword sets to the
#     seven categories, body type first (AIRCRAFT, WALKER, MOUNTED, VEHICLE,
#     MONSTER/BEAST(S)/SWARM), then CHARACTER, else infantry - a FLY grav-tank is
#     a tank, a MOUNTED CHARACTER mounted, a WALKER CHARACTER a walker
#   - the seven SVGs exist under res://assets/icons/unit_silhouettes/, are 64x64
#     viewBox glyphs, and import as 256 px textures with mipmaps
#   - every token exposes silhouette_category from its unit's keywords (through
#     the unit_id meta) and carries a Silhouette spec node whose texture is that
#     category's SVG
#   - the glyph is painted (visible) in the letter style for tokens without
#     dedicated art; art tokens and tanks with the generic tank sprite keep their
#     art, walkers drop the tank sprite for their glyph; classic style and debug
#     mode do not paint it
#   - the tint is the base's contrast colour (light on the dark ring-mode base,
#     dark on a light full-colour base)
#   - the Label child is the unit's letter counter, laid out centred under the
#     base (below a rotated oval's lowest point and clear of the status tick),
#     drawn beneath the tokens, follows a custom label on the next sync, and the
#     old model-number stub is gone; the model carrying the unit's name plate
#     leaves it empty (the plate names the unit there), and that moves with the
#     plate when the first model dies or name plates are switched off
#   - re-tagging a token with another unit re-resolves its glyph
#
# The glyph actually painted on screen (template match against the SVG, pre-T15
# vs post-T15 pixel diff) is covered by the windowed scenario
# tests/scenarios/visual/T15_silhouettes.json.
#
# Usage: godot --headless --path . -s tests/test_unit_silhouettes.gd

var passed := 0
var failed := 0
var _ran := false

const CATS := ["infantry", "tank", "walker", "beast", "character", "aircraft", "mounted"]
const DIR := "res://assets/icons/unit_silhouettes/"


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


func _unit(owner: int, unit_name: String, keywords: Array, model: Dictionary) -> Dictionary:
	var m := {"id": "m1", "alive": true, "wounds": 1, "current_wounds": 1,
		"base_mm": 32, "position": {"x": 100.0, "y": 100.0}}
	m.merge(model, true)
	return {
		"owner": owner,
		"status": 2,
		"meta": {"name": unit_name, "display_name": unit_name, "keywords": keywords},
		"flags": {},
		"models": [m],
	}


func _token(TV, uid: String, owner: int, model: Dictionary) -> Node2D:
	var t = TV.new()
	t.owner_player = owner
	t.set_model_data(model.duplicate(true))
	t.set_meta("unit_id", uid)
	t.set_meta("model_id", "m1")
	root.add_child(t)
	return t


func _radius(t) -> float:
	var b = t.base_shape.get_bounds()
	return min(b.size.x, b.size.y) / 2.0


func _run_tests() -> void:
	if _ran:
		return
	_ran = true
	print("\n=== test_unit_silhouettes (T15) ===\n")
	var gs = root.get_node_or_null("GameState")
	var ss = root.get_node_or_null("SettingsService")
	if gs == null or ss == null:
		_check("GameState / SettingsService reachable", false)
		_finish()
		return
	var TV = load("res://scripts/TokenVisual.gd")
	_check("TokenVisual script loads", TV != null)
	if TV == null:
		_finish()
		return
	var has_api: bool = TV.has_method("silhouette_category_for_keywords") and TV.has_method("silhouette_texture_for")
	_check("TokenVisual exposes silhouette_category_for_keywords / silhouette_texture_for", has_api)
	if not has_api:
		_finish()
		return

	# --- 1. Keyword -> category table (independent of the token) ---
	var table := [
		[["INFANTRY", "BATTLELINE"], "infantry"],                       # Intercessors / Boyz
		[["INFANTRY", "FLY", "JUMP PACK"], "infantry"],                 # jump infantry stay infantry
		[["CHARACTER", "INFANTRY"], "character"],                       # Warboss, Captain
		[["CHARACTER", "INFANTRY", "FLY"], "character"],
		[["VEHICLE", "FLY"], "tank"],                                   # Caladius Grav-tank
		[["VEHICLE", "TRANSPORT", "DEDICATED TRANSPORT"], "tank"],      # Rhino / Trukk
		[["VEHICLE", "TITANIC"], "tank"],
		[["VEHICLE", "WALKER"], "walker"],                              # Dreadnought
		[["CHARACTER", "VEHICLE", "WALKER"], "walker"],                 # Bjorn the Fell-Handed
		[["TITANIC", "TOWERING", "TRANSPORT", "VEHICLE", "WALKER"], "walker"],  # Stompa
		[["AIRCRAFT", "FLY", "VEHICLE"], "aircraft"],                   # Wazbom Blastajet
		[["MOUNTED"], "mounted"],                                       # Warbikers, Outriders
		[["MOUNTED", "FLY"], "mounted"],                                # Deffkoptas
		[["CHARACTER", "MOUNTED"], "mounted"],                          # Captain on Bike
		[["CHARACTER", "MOUNTED", "VEHICLE"], "mounted"],               # Wazdakka Gutsmek
		[["MONSTER"], "beast"],
		[["CHARACTER", "MONSTER"], "beast"],                            # Roboute Guilliman
		[["BEASTS"], "beast"],                                          # Fenrisian Wolves
		[["BEAST"], "beast"],
		[["SWARM"], "beast"],
		[[], "infantry"],                                               # no body keyword
		[["ORKS", "GROTS"], "infantry"],
		[["infantry", "character"], "character"],                       # case-insensitive
		[[" Vehicle ", "walker"], "walker"],                            # whitespace-tolerant
	]
	for row in table:
		var got: String = TV.silhouette_category_for_keywords(row[0])
		_check("keywords %s -> %s" % [str(row[0]), row[1]], got == row[1], "got %s" % got)

	# --- 2. The seven SVG glyphs and their imported textures ---
	for c in CATS:
		var path: String = DIR + c + ".svg"
		var text := FileAccess.get_file_as_string(path)
		_check("%s.svg exists and is a 64x64 SVG" % c,
			text.begins_with("<svg") and text.find('viewBox="0 0 64 64"') != -1, path)
		var tex: Texture2D = TV.silhouette_texture_for(c)
		_check("%s glyph imports as a texture" % c, tex != null)
		if tex == null:
			continue
		_check("%s texture comes from its SVG" % c, tex.resource_path == path, tex.resource_path)
		_check("%s texture is 256x256 (4x raster)" % c, tex.get_size() == Vector2(256, 256), str(tex.get_size()))
		var img: Image = tex.get_image()
		_check("%s texture has mipmaps" % c, img != null and img.has_mipmaps())
		if img != null:
			# White fill on a black keyline: the centre column holds both, and
			# the corners are clear.
			var white := 0
			var black := 0
			for y in range(256):
				var p: Color = img.get_pixel(128, y)
				if p.a > 0.98 and p.r > 0.9:
					white += 1
				elif p.a > 0.98 and p.r < 0.1:
					black += 1
			_check("%s glyph is white on a black keyline" % c, white > 20 and black > 4,
				"white %d black %d" % [white, black])
			_check("%s glyph corners are transparent" % c,
				img.get_pixel(2, 2).a < 0.05 and img.get_pixel(253, 253).a < 0.05)
			# Drawn at 0.66 r, nothing may reach the faction band's mid-line
			# (0.74 r): the art stays within 1.1x the glyph's half-size.
			var reach := 0.0
			for y in range(0, 256, 2):
				for x in range(0, 256, 2):
					if img.get_pixel(x, y).a > 0.5:
						reach = max(reach, Vector2(x + 0.5 - 128.0, y + 0.5 - 128.0).length() / 128.0)
			_check("%s glyph art stays within 1.1x its half-size (%.3f)" % [c, reach], reach > 0.8 and reach <= 1.1)
	_check("unknown category has no glyph", TV.silhouette_texture_for("mech") == null)

	# --- 3. Tokens: category from the unit's keywords, spec node, painted rule ---
	ss.unit_visual_style = "letter"
	ss.unit_color_display_mode = "ring"
	gs.state["factions"] = {"1": {"name": "Orks"}, "2": {"name": "Adeptus Custodes"}}
	gs.state["unit_visuals"] = {}
	gs.state["units"] = {
		"U_T15_BOYZ": _unit(1, "Boyz", ["ORKS", "INFANTRY", "BATTLELINE"], {}),
		"U_T15_WARBOSS": _unit(1, "Warboss", ["ORKS", "CHARACTER", "INFANTRY"], {"base_mm": 40}),
		"U_T15_CALADIUS": _unit(2, "Caladius Grav-tank", ["ADEPTUS CUSTODES", "VEHICLE", "FLY"],
			{"base_mm": 170, "base_type": "oval", "base_dimensions": {"length": 109.0, "width": 170.0}, "wounds": 14, "current_wounds": 14}),
		"U_T15_DREAD": _unit(2, "Contemptor-Achillus Dreadnought", ["ADEPTUS CUSTODES", "VEHICLE", "WALKER"], {"base_mm": 60}),
		"U_T15_JET": _unit(1, "Wazbom Blastajet", ["ORKS", "AIRCRAFT", "FLY", "VEHICLE"],
			{"base_mm": 150, "base_type": "oval", "base_dimensions": {"length": 95.0, "width": 150.0}, "rotation": 0.6}),
		"U_T15_BIKE": _unit(2, "Shield-Captain on Dawneagle Jetbike", ["ADEPTUS CUSTODES", "CHARACTER", "MOUNTED", "FLY"],
			{"base_mm": 75, "base_type": "oval", "base_dimensions": {"length": 42.0, "width": 75.0}}),
		"U_T15_GHAZ": _unit(1, "Ghazghkull Thraka", ["ORKS", "MONSTER", "CHARACTER", "EPIC HERO"], {"base_mm": 80}),
		"U_T15_GUARD": _unit(2, "Custodian Guard", ["ADEPTUS CUSTODES", "INFANTRY", "BATTLELINE"], {"base_mm": 40}),
	}
	var expect := {
		"U_T15_BOYZ": "infantry", "U_T15_WARBOSS": "character", "U_T15_CALADIUS": "tank",
		"U_T15_DREAD": "walker", "U_T15_JET": "aircraft", "U_T15_BIKE": "mounted",
		"U_T15_GHAZ": "beast", "U_T15_GUARD": "infantry",
	}
	var tokens := {}
	for uid in expect:
		tokens[uid] = _token(TV, uid, int(gs.state["units"][uid]["owner"]), gs.state["units"][uid]["models"][0])
	for uid in expect:
		var t = tokens[uid]
		_check("%s silhouette_category == %s" % [uid, expect[uid]], t.silhouette_category == expect[uid],
			"got %s" % t.silhouette_category)
		var s = t.get_node_or_null("Silhouette")
		_check("%s has a Silhouette spec node" % uid, s != null)
		if s == null:
			continue
		_check("%s Silhouette.texture is the %s glyph" % [uid, expect[uid]],
			s.texture != null and s.texture == TV.silhouette_texture_for(expect[uid]))
		_check("%s Silhouette.scale is the glyph size (0.66 of the base radius)" % uid,
			is_equal_approx(s.scale.x, 0.66) and is_equal_approx(s.scale.y, 0.66), str(s.scale))

	var painted := {"U_T15_BOYZ": true, "U_T15_WARBOSS": true, "U_T15_DREAD": true, "U_T15_JET": true,
		"U_T15_BIKE": true, "U_T15_GHAZ": true, "U_T15_CALADIUS": false, "U_T15_GUARD": false}
	for uid in painted:
		var t = tokens[uid]
		_check("%s glyph painted == %s" % [uid, str(painted[uid])],
			t.get_node("Silhouette").visible == painted[uid])
	_check("Custodian Guard keeps its dedicated top-down art",
		tokens["U_T15_GUARD"]._get_unit_sprite_texture() != null)
	_check("the Caladius (tank) keeps the generic tank sprite",
		tokens["U_T15_CALADIUS"]._t15_uses_tank_sprite())
	_check("the Dreadnought (walker) gets its glyph, not the generic tank sprite",
		not tokens["U_T15_DREAD"]._t15_uses_tank_sprite() and tokens["U_T15_DREAD"].get_node("Silhouette").visible)

	# A tank whose generic tank sprite is missing falls back to its glyph.
	var cal = tokens["U_T15_CALADIUS"]
	cal._tank_resolved = true
	cal._tank_body_tex = null
	cal._t15_update_silhouette()
	_check("a tank without the tank sprite shows its tank glyph", cal.get_node("Silhouette").visible)
	cal._tank_resolved = false
	cal._t15_update_silhouette()
	_check("the tank sprite back -> the glyph is not painted", not cal.get_node("Silhouette").visible)

	# Painted only by the letter style; debug mode never.
	var boyz = tokens["U_T15_BOYZ"]
	ss.unit_visual_style = "classic"
	boyz._on_unit_style_changed("classic")
	_check("classic style: glyph not painted", not boyz.get_node("Silhouette").visible)
	ss.unit_visual_style = "letter"
	boyz._on_unit_style_changed("letter")
	_check("back to letter style: glyph painted", boyz.get_node("Silhouette").visible)
	boyz.set_debug_mode(true)
	_check("debug mode: glyph not painted", not boyz.get_node("Silhouette").visible)
	boyz.set_debug_mode(false)
	_check("debug mode off: glyph painted", boyz.get_node("Silhouette").visible)

	# --- 4. Tint: the base's contrast colour ---
	var dark_base := Color(0.24, 0.24, 0.27)
	var sil = boyz._t15_silhouette_for_paint(dark_base)
	_check("ring mode (dark base): glyph painted light", sil != null and sil.modulate.get_luminance() > 0.8,
		str(sil.modulate) if sil != null else "null")
	sil = boyz._t15_silhouette_for_paint(Color(0.95, 0.85, 0.3))
	_check("full mode on a light unit colour: glyph painted dark", sil != null and sil.modulate.get_luminance() < 0.2,
		str(sil.modulate) if sil != null else "null")
	_check("a token keeping its art paints no glyph",
		tokens["U_T15_GUARD"]._t15_silhouette_for_paint(dark_base) == null)
	var rect: Dictionary = boyz.t15_silhouette_rect()
	var r32: float = _radius(boyz)
	_check("t15_silhouette_rect() seam: centred square of 2 x 0.66 r",
		rect.get("painted", false) and (rect["size"] as Vector2).is_equal_approx(Vector2.ONE * 2.0 * 0.66 * r32)
		and (rect["position"] as Vector2).is_equal_approx(-Vector2.ONE * 0.66 * r32), str(rect))
	var fgeo: Dictionary = boyz._t08_ring_geometry(r32)
	_check("glyph body (30/32 of its half-size) sits inside the faction band's inner edge",
		0.66 * r32 * 30.0 / 32.0 <= fgeo["faction_mid"] - fgeo["faction_width"] * 0.5 + 0.01)
	_check("glyph extremes (1.1x its half-size) stop short of the faction band's mid-line",
		0.66 * r32 * 1.1 < fgeo["faction_mid"])

	# --- 5. Letter label under the base ---
	# Single-model units carry their unit's name plate under the base, so their
	# Label stays empty; with name plates off they show their letter counter.
	for uid in expect:
		var t = tokens[uid]
		var l = t.get_node_or_null("Label")
		_check("%s has its Label" % uid, l != null)
		if l == null:
			continue
		_check("%s (single model) draws the name plate and leaves its Label empty" % uid,
			t._t15_name_plate_shown() and l.text == "", "'%s'" % l.text)
		_check("%s Label is drawn beneath the tokens (z_index -1, relative)" % uid,
			l.z_index == -1 and l.z_as_relative)
	ss.show_unit_labels = false
	for uid in expect:
		tokens[uid]._t15_sync_letter_label()
	for uid in expect:
		var t = tokens[uid]
		var l = t.get_node("Label")
		_check("%s name plates off: Label shows the unit's letter counter ('%s')" % [uid, t._get_letter_label()],
			not t._t15_name_plate_shown() and l.text == t._get_letter_label() and l.text != "" and l.text != str(t.model_number), l.text)
		var lowest := -INF
		for p in t._get_shape_polygon(t.model_data.get("rotation", 0.0)):
			lowest = max(lowest, p.y)
		var r: float = _radius(t)
		var tick_bottom: float = r + 3.0 + max(3.0, r * 0.08)
		_check("%s Label sits under the base (top %.1f >= lowest point %.1f and status tick %.1f)" % [uid, l.position.y, lowest, tick_bottom],
			l.position.y >= lowest and l.position.y >= tick_bottom)
		_check("%s Label is centred under the base" % uid, absf(l.position.x + l.size.x / 2.0) < 0.75,
			"x %.2f w %.2f" % [l.position.x, l.size.x])
		var lf: Font = l.get_theme_font("font")
		_check("%s Label is 13 px Rajdhani Bold with an outline" % uid,
			l.get_theme_font_size("font_size") == 13 and l.get_theme_constant("outline_size") >= 2
			and lf != null and lf.resource_path.ends_with("Rajdhani-Bold.ttf"),
			"%d %d %s" % [l.get_theme_font_size("font_size"), l.get_theme_constant("outline_size"), lf.resource_path if lf else "null"])
	_check("Warboss letter counter is 'War'", tokens["U_T15_WARBOSS"].get_node("Label").text == "War",
		tokens["U_T15_WARBOSS"].get_node("Label").text)

	# A rotated oval: the label clears the base's rotated lowest point.
	var jet = tokens["U_T15_JET"]
	var jl = jet.get_node("Label")
	_check("rotated oval: Label below the rotated base (top %.1f > minor radius %.1f)" % [jl.position.y, _radius(jet)],
		jl.position.y > _radius(jet) + 1.0)
	var md: Dictionary = jet.model_data.duplicate(true)
	md["rotation"] = 0.0
	jet.set_model_data(md)
	var jl_top_flat: float = jl.position.y
	md["rotation"] = PI / 2.0
	jet.set_model_data(md)
	_check("set_model_data re-lays the Label out for the new rotation",
		absf(jl.position.y - jl_top_flat) > 5.0, "%.1f vs %.1f" % [jl.position.y, jl_top_flat])
	ss.show_unit_labels = true
	for uid in expect:
		tokens[uid]._t15_sync_letter_label()
	_check("name plates back on: single-model Labels empty again",
		tokens["U_T15_WARBOSS"].get_node("Label").text == "" and tokens["U_T15_JET"].get_node("Label").text == "")

	# A three-model mob: the first alive model carries the name plate, the rest
	# show the letter counter; the plate (and the empty Label) migrates when the
	# first model dies.
	var mob := _unit(1, "Kommandos", ["ORKS", "INFANTRY"], {})
	for i in [2, 3]:
		var mm: Dictionary = (mob["models"][0] as Dictionary).duplicate(true)
		mm["id"] = "m%d" % i
		mm["position"] = {"x": 100.0 + 45.0 * (i - 1), "y": 100.0}
		mob["models"].append(mm)
	gs.state["units"]["U_T15_MOB"] = mob
	var mob_tokens := []
	for i in range(3):
		var mt = TV.new()
		mt.owner_player = 1
		mt.set_model_data((mob["models"][i] as Dictionary).duplicate(true))
		mt.set_meta("unit_id", "U_T15_MOB")
		mt.set_meta("model_id", "m%d" % (i + 1))
		root.add_child(mt)
		mob_tokens.append(mt)
	var letter: String = mob_tokens[1]._get_letter_label()
	_check("mob m1 carries the name plate (empty Label)", mob_tokens[0].get_node("Label").text == "")
	_check("mob m2 / m3 show the letter counter '%s' under the base" % letter,
		letter != "" and mob_tokens[1].get_node("Label").text == letter and mob_tokens[2].get_node("Label").text == letter)
	var ml = mob_tokens[1].get_node("Label")
	_check("mob m2 Label centred under its base", ml.position.y >= _radius(mob_tokens[1]) and absf(ml.position.x + ml.size.x / 2.0) < 0.75,
		"%s %s" % [str(ml.position), str(ml.size)])
	mob["models"][0]["current_wounds"] = 0
	for mt in mob_tokens:
		mt._t15_sync_letter_label()
	_check("first model dead: m2 now carries the plate (empty Label), m3 keeps its letter",
		mob_tokens[1].get_node("Label").text == "" and mob_tokens[2].get_node("Label").text == letter)
	mob["models"][0]["current_wounds"] = 1
	for mt in mob_tokens:
		mt._t15_sync_letter_label()

	# A custom label reaches the Label on the next sync (a repaint does this).
	var boyz_label_token = mob_tokens[2]
	gs.set_unit_label("U_T15_MOB", "Ld")
	boyz_label_token._t15_sync_letter_label()
	_check("custom unit label shows under the base", boyz_label_token.get_node("Label").text == "Ld",
		boyz_label_token.get_node("Label").text)
	gs.set_unit_label("U_T15_MOB", "")
	boyz_label_token._t15_sync_letter_label()
	_check("clearing the custom label restores the letter counter",
		boyz_label_token.get_node("Label").text == boyz_label_token._get_letter_label())

	# --- 6. Re-tagging a token re-resolves its glyph ---
	boyz.set_meta("unit_id", "U_T15_DREAD")
	boyz._t15_silhouette_for_paint(dark_base)
	_check("re-tagged token: silhouette_category follows the new unit (walker)",
		boyz.silhouette_category == "walker", boyz.silhouette_category)
	_check("re-tagged token: Silhouette.texture follows (walker glyph)",
		boyz.get_node("Silhouette").texture == TV.silhouette_texture_for("walker"))

	_finish()
