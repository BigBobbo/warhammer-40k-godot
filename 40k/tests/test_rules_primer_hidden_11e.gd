extends SceneTree

# The LLM critic's rules primer (tools/llm_critic/rules_primer.md, prepended to
# every critic prompt) must state the 13.09 HIDDEN rule the engine applies —
# the errata version ("within a terrain area that contains one or more
# light/dense terrain features"), not the launch text's dense-only wording — and
# must point the critic at the errata/FAQ/commentary file, which wins over the
# launch text.
#
# Regression: the primer still said "a terrain area with a dense feature" after
# the engine (TerrainManager.category_allows_hidden) started hiding units in
# light areas too, so the critic judged moves and shots against a rule the
# engine no longer applies.
#
# Usage: godot --headless --path . -s tests/test_rules_primer_hidden_11e.gd

var passed := 0
var failed := 0
var _completed := false  # set by the last line of _run(): an aborted run (script error) counts as a failure

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _initialize() -> void:
	await create_timer(0.2).timeout
	_run()
	if not _completed:
		failed += 1
		print("  FAIL: the run aborted before its last check (see the SCRIPT ERROR above)")
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t

## The primer's "Hidden (13.09 ...)" bullet, up to the next bullet.
func _hidden_bullet(primer: String) -> String:
	var i := primer.find("**Hidden (13.09")
	if i < 0:
		return ""
	var j := primer.find("\n- ", i)
	return primer.substr(i, (j - i) if j > i else -1)

func _run() -> void:
	print("\n=== test_rules_primer_hidden_11e ===")
	var primer := _read("res://tools/llm_critic/rules_primer.md")
	_check("rules_primer.md readable", primer != "")
	var bullet := _hidden_bullet(primer)
	print("   bullet: %s" % bullet.replace("\n", " "))
	_check("the primer has a Hidden (13.09) bullet", bullet != "")
	_check("... light OR dense terrain features hide (13.09 errata)", bullet.contains("light or dense"), bullet)
	_check("... not the launch text's dense-only wording", not bullet.contains("with a dense\n  feature") and not bullet.contains("with a dense feature"), bullet)
	_check("... only ENEMY models are limited by detection range", bullet.contains("ENEMY models"), bullet)
	_check("... snap shooting counts as ranged attacks", bullet.contains("snap shooting"), bullet)
	_check("... a hidden unit has at least one hidden model (01.02.07)", bullet.contains("at least one hidden model"), bullet)
	_check("the primer points the critic at the errata/FAQ/commentary file", primer.contains("docs/rules/40k_11th_edition_errata_faq_commentary.md"))
	var errata := _read(ProjectSettings.globalize_path("res://").path_join("../docs/rules/40k_11th_edition_errata_faq_commentary.md"))
	_check("... which exists and carries the 13.09 light/dense errata", errata.contains("contains one or more light/dense terrain features"))
	var tm = root.get_node("TerrainManager")
	_check("the engine agrees: light and dense hide, exposed does not",
		tm.category_allows_hidden("light") and tm.category_allows_hidden("dense") and not tm.category_allows_hidden("exposed"))
	_completed = true
