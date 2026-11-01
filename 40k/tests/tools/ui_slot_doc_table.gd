extends RefCounted

# Parses the strict color-slot table in docs/design_guidelines_2d_topdown.md
# §9 ("Color, motion, and visual budget") into {SLOT_CONSTANT: "rrggbb"}.
#
# ONE parser, two consumers, so the doc and the UIConstants autoload are
# cross-checked the same way everywhere:
#   - tests/test_ui_constants_slots.gd (headless, in the validation gate)
#   - tests/tools/ui_slot_palette_card.gd (the windowed T01 scenario renders
#     the doc hex next to the live autoload hex)
#
# A slot row is a table row with one cell that is exactly a backticked
# UPPER_SNAKE constant (`FRIENDLY_PLAYER_TEAL`) and one cell that is an
# (optionally backticked) #RRGGBB hex. Rows with neither (the header, the
# separator, the per-army Faction row) are skipped; a row with only one of the
# two is reported as an error, as is a slot listed twice.
#
# Usage: load("res://tests/tools/ui_slot_doc_table.gd").parse()
#   -> {"slots": {"FRIENDLY_PLAYER_TEAL": "00b3b3", ...},
#       "errors": [String, ...], "section_found": bool}

const DOC_PATH := "res://docs/design_guidelines_2d_topdown.md"
const SECTION_PREFIX := "### 9."


static func parse(path: String = DOC_PATH) -> Dictionary:
	var slots := {}
	var errors: Array = []
	var section_found := false

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("cannot open %s (error %d)" % [path, FileAccess.get_open_error()])
		return {"slots": slots, "errors": errors, "section_found": false}
	var text := f.get_as_text()
	f.close()

	var const_re := RegEx.new()
	const_re.compile("^`([A-Z][A-Z0-9_]*)`$")
	var hex_re := RegEx.new()
	hex_re.compile("^`?#([0-9A-Fa-f]{6})`?$")

	var in_section := false
	for raw in text.split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("#"):
			if line.begins_with(SECTION_PREFIX):
				in_section = true
				section_found = true
				continue
			# The next heading of equal or higher level ends §9.
			if in_section and (line.begins_with("## ") or line.begins_with("### ")):
				break
		if not in_section or not line.begins_with("|"):
			continue
		var constant := ""
		var hex := ""
		for cell in line.split("|"):
			var c: String = cell.strip_edges()
			var m := const_re.search(c)
			if m != null:
				constant = m.get_string(1)
			var h := hex_re.search(c)
			if h != null:
				hex = h.get_string(1).to_lower()
		if constant == "" and hex == "":
			continue
		if constant == "" or hex == "":
			errors.append("malformed slot row (needs both a `CONSTANT` and a #RRGGBB cell): %s" % line)
			continue
		if slots.has(constant):
			errors.append("slot listed twice: %s" % constant)
			continue
		slots[constant] = hex

	if not section_found:
		errors.append("section '%s' not found in %s" % [SECTION_PREFIX, path])
	return {"slots": slots, "errors": errors, "section_found": section_found}
