extends SceneTree

# T01 — UIConstants color-slot autoload contract + doc §9 drift check.
#
# 1. Registration / "no autoload conflicts": UIConstants is registered exactly
#    once in project.godot as an enabled singleton running
#    res://autoloads/UIConstants.gd, no autoload name is listed twice, and no
#    autoload name is also a class_name global (that would shadow it).
# 2. The live autoload exposes the seven strict slots as typed, fully opaque
#    Color CONSTANTS, pairwise distinct.
# 3. The slot table in docs/design_guidelines_2d_topdown.md §9 matches the
#    autoload 1:1 — same slot names, same #RRGGBB. Changing a hex (or adding /
#    renaming a slot) in one place but not the other FAILS here.
# 4. slot_name() round-trips every slot, also after an 8-bit (#RRGGBB) round
#    trip, and returns "" for an off-table color.
# 5. striped_pattern(Color.YELLOW) returns a Texture2D whose pixels are
#    continuous diagonal stripes of the input color over transparency, half
#    and half, seamless when tiled — the doc §9 resolution for semantic yellow
#    colliding with a yellow faction color.
#
# Usage: godot --headless --path . -s tests/test_ui_constants_slots.gd

const DOC_TABLE := preload("res://tests/tools/ui_slot_doc_table.gd")
const AUTOLOAD_SCRIPT := "res://autoloads/UIConstants.gd"
const AUTOLOAD_ENTRY := "*res://autoloads/UIConstants.gd"

# The seven slots T01 names, in doc order. Explicit (not reflected from
# all_slots()) so dropping or renaming a constant fails here too.
const SLOT_NAMES := [
	"FRIENDLY_PLAYER_TEAL", "ENEMY_PLAYER_MAGENTA", "WARNING_ORANGE",
	"CONFIRMED_GREEN", "MARGINAL_YELLOW", "INVALID_RED", "NEUTRAL_UI_PALE_WHITE",
]

var passed := 0
var failed := 0


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
	print("\n=== test_ui_constants_slots ===\n")

	_test_autoload_registration()

	var ui: Node = root.get_node_or_null("UIConstants")
	_check("UIConstants autoload is live at /root/UIConstants", ui != null)
	if ui != null:
		var script: Script = ui.get_script()
		_check("autoload runs %s" % AUTOLOAD_SCRIPT,
			script != null and script.resource_path == AUTOLOAD_SCRIPT,
			"script=%s" % (script.resource_path if script != null else "<none>"))
		if script != null:
			var consts: Dictionary = script.get_script_constant_map()
			_test_slot_constants(ui, consts)
			_test_doc_table_matches(consts)
			_test_slot_name(ui, consts)
		_test_striped_pattern(ui)

	_finish()


# ---------------------------------------------------------------------------
# 1. project.godot registration
# ---------------------------------------------------------------------------

func _test_autoload_registration() -> void:
	print("-- autoload registration --")
	var f := FileAccess.open("res://project.godot", FileAccess.READ)
	_check("project.godot readable", f != null)
	if f == null:
		return
	var entries := {}      # name -> value
	var duplicates: Array = []
	var in_autoload := false
	for raw in f.get_as_text().split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("["):
			in_autoload = line == "[autoload]"
			continue
		if not in_autoload or line == "" or line.begins_with(";"):
			continue
		var eq := line.find("=")
		if eq <= 0:
			continue
		var key := line.substr(0, eq)
		var value := line.substr(eq + 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
		if entries.has(key):
			duplicates.append(key)
		entries[key] = value
	f.close()

	_check("[autoload] section parsed (%d entries)" % entries.size(), entries.size() > 0)
	_check("no autoload name is listed twice", duplicates.is_empty(), "duplicates: %s" % str(duplicates))
	_check("UIConstants is registered", entries.has("UIConstants"))
	_check("UIConstants entry is the enabled singleton %s" % AUTOLOAD_ENTRY,
		entries.get("UIConstants", "") == AUTOLOAD_ENTRY,
		"got '%s'" % str(entries.get("UIConstants", "")))
	_check("UIConstants script file exists", FileAccess.file_exists(AUTOLOAD_SCRIPT))
	_check("ProjectSettings resolves autoload/UIConstants to the same entry",
		str(ProjectSettings.get_setting("autoload/UIConstants", "")) == AUTOLOAD_ENTRY)

	# A class_name global with an autoload's name shadows the singleton
	# ("Class X hides an autoload singleton").
	var shadowed: Array = []
	for cls in ProjectSettings.get_global_class_list():
		if entries.has(str(cls.get("class", ""))):
			shadowed.append(str(cls.get("class", "")))
	_check("no class_name global shares an autoload's name", shadowed.is_empty(),
		"shadowed: %s" % str(shadowed))


# ---------------------------------------------------------------------------
# 2. typed, opaque, distinct slot constants
# ---------------------------------------------------------------------------

func _test_slot_constants(ui: Node, consts: Dictionary) -> void:
	print("-- slot constants --")
	var hexes := {}
	for n in SLOT_NAMES:
		var c = consts.get(n)
		_check("%s is a const of type Color" % n, typeof(c) == TYPE_COLOR,
			"type=%s" % type_string(typeof(c)))
		if typeof(c) != TYPE_COLOR:
			continue
		_check("%s is fully opaque (a == 1.0)" % n, c.a == 1.0, "a=%s" % str(c.a))
		_check("%s is readable through the autoload instance" % n, ui.get(n) == c)
		hexes[c.to_html(false)] = hexes.get(c.to_html(false), []) + [n]

	var collisions: Array = []
	for h in hexes:
		if hexes[h].size() > 1:
			collisions.append("#%s: %s" % [h, str(hexes[h])])
	_check("the seven slots are pairwise distinct", collisions.is_empty(), str(collisions))

	var table: Dictionary = ui.all_slots()
	_check("all_slots() lists exactly the seven slots", table.size() == SLOT_NAMES.size()
		and SLOT_NAMES.all(func(n): return table.has(n)), "keys=%s" % str(table.keys()))
	var same := true
	for n in table:
		if table[n] != consts.get(n):
			same = false
	_check("all_slots() values equal the constants", same)


# ---------------------------------------------------------------------------
# 3. doc §9 table <-> autoload, 1:1
# ---------------------------------------------------------------------------

func _test_doc_table_matches(consts: Dictionary) -> void:
	print("-- doc §9 table vs UIConstants --")
	var doc: Dictionary = DOC_TABLE.parse()
	_check("doc §9 section found", bool(doc.get("section_found", false)))
	_check("doc §9 slot table parses cleanly", doc.get("errors", []).is_empty(),
		str(doc.get("errors", [])))
	var slots: Dictionary = doc.get("slots", {})
	_check("doc §9 table lists exactly %d slots" % SLOT_NAMES.size(),
		slots.size() == SLOT_NAMES.size(), "doc slots=%s" % str(slots.keys()))
	for n in slots:
		_check("doc slot %s exists in UIConstants" % n, SLOT_NAMES.has(n),
			"the doc names a slot the autoload does not have")
	for n in SLOT_NAMES:
		var c = consts.get(n)
		var code_hex: String = c.to_html(false) if typeof(c) == TYPE_COLOR else "<missing>"
		_check("doc §9 hex for %s == UIConstants (#%s)" % [n, code_hex.to_upper()],
			slots.get(n, "") == code_hex,
			"doc=#%s code=#%s" % [str(slots.get(n, "<missing>")).to_upper(), code_hex.to_upper()])


# ---------------------------------------------------------------------------
# 4. slot_name round trips
# ---------------------------------------------------------------------------

func _test_slot_name(ui: Node, consts: Dictionary) -> void:
	print("-- slot_name --")
	for n in SLOT_NAMES:
		var c = consts.get(n)
		if typeof(c) != TYPE_COLOR:
			continue
		_check("slot_name(%s) == \"%s\"" % [n, n], ui.slot_name(c) == n,
			"got \"%s\"" % ui.slot_name(c))
		var quantized := Color.html(c.to_html(false))
		_check("slot_name survives the #%s round trip" % c.to_html(false).to_upper(),
			ui.slot_name(quantized) == n, "got \"%s\"" % ui.slot_name(quantized))
	_check("slot_name(off-table color) == \"\"", ui.slot_name(Color(0.1, 0.2, 0.3, 1.0)) == "")


# ---------------------------------------------------------------------------
# 5. striped_pattern
# ---------------------------------------------------------------------------

func _test_striped_pattern(ui: Node) -> void:
	print("-- striped_pattern --")
	var tex = ui.striped_pattern(Color.YELLOW)
	_check("striped_pattern(Color.YELLOW) is non-null", tex != null)
	_check("striped_pattern(Color.YELLOW) is a Texture2D", tex is Texture2D,
		"class=%s" % (tex.get_class() if tex != null else "<null>"))
	if not (tex is Texture2D):
		return
	_check("default tile is 16x16", tex.get_width() == 16 and tex.get_height() == 16,
		"%dx%d" % [tex.get_width(), tex.get_height()])
	var img: Image = tex.get_image()
	_check("tile image is readable", img != null and not img.is_empty())
	if img == null or img.is_empty():
		return

	var w := img.get_width()
	var h := img.get_height()
	var on := []
	var on_count := 0
	var stray := 0
	for y in range(h):
		var row := []
		for x in range(w):
			var p := img.get_pixel(x, y)
			var is_on := p.a8 == 255 and p.r8 == 255 and p.g8 == 255 and p.b8 == 0
			var is_off := p.a8 == 0
			if not (is_on or is_off):
				stray += 1
			row.append(is_on)
			on_count += 1 if is_on else 0
		on.append(row)
	_check("every pixel is either the input color or fully transparent", stray == 0,
		"%d stray pixels" % stray)
	_check("half the tile is striped (on=%d of %d)" % [on_count, w * h], on_count * 2 == w * h)

	# Stripes run along the anti-diagonal: (x, y) and (x+1, y-1) always agree,
	# including across the tile edge, so a tiled fill has no seams.
	var breaks := 0
	for y in range(h):
		for x in range(w):
			if on[y][x] != on[(y - 1 + h) % h][(x + 1) % w]:
				breaks += 1
	_check("stripes are continuous diagonals, seamless when tiled", breaks == 0,
		"%d breaks" % breaks)

	# Along one row the stripe alternates every 4 px (default stripe_width).
	var runs := 1
	for x in range(1, w):
		if on[0][x] != on[0][x - 1]:
			runs += 1
	_check("row 0 alternates in 4 px runs (%d runs over %d px)" % [runs, w], runs == w / 4)

	# The pattern takes any color: semantic MARGINAL_YELLOW stripes read back
	# as that slot. Image.set_pixel truncates to 8 bits while Color.to_html
	# rounds (0.85 * 255 = 216.75 -> stored 216 = 0xD8, to_html says 0xD9), so
	# allow 1/255 per channel — slot_name()'s 0.005 tolerance absorbs it.
	var marginal: Color = ui.MARGINAL_YELLOW
	var img2: Image = ui.striped_pattern(marginal).get_image()
	var p0 := img2.get_pixel(0, 0)
	var within_one: bool = (absi(p0.r8 - marginal.r8) <= 1 and absi(p0.g8 - marginal.g8) <= 1
		and absi(p0.b8 - marginal.b8) <= 1 and p0.a8 == 255)
	_check("striped_pattern(MARGINAL_YELLOW) stripe pixel is that slot (within 1/255)",
		within_one and ui.slot_name(p0) == "MARGINAL_YELLOW",
		"pixel(0,0)=#%s slot_name=\"%s\"" % [p0.to_html(true), ui.slot_name(p0)])
	var big = ui.striped_pattern(Color.YELLOW, 32, 8)
	_check("tile_size argument is honoured (32x32)", big.get_width() == 32 and big.get_height() == 32)


func _finish() -> void:
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
