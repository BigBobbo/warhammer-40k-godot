extends SceneTree

# Codex: Adeptus Custodes (11e) stratagems (WP-C5) — dispatcher + window
# framework pins. Against tests/saves/cus11e_c5_active.w40ksave (P1 Custodes
# active vs P2 Orks):
#   A. registry: 41 csv ids in their groups, all implemented, every AC CSV row
#      carries the custom:custodes11e marker and maps to a group
#   B. RulesEngine HitModifier / WoundModifier values the dispatcher hardcodes
#   C. the eight new windows: generator KNOWN_WINDOWS, WINDOW_WHEN_TEXT,
#      StratagemDialog header text
#   D. window gating (S panel refused for window stratagems, "Offered
#      automatically when …"), panel stratagems have no windows
#   E. duration phrases -> expiry (end_of_turn / next_own_command_phase)
#   F. StratagemManager dispatch: implemented marking, battle-shock gate,
#      variant label, AIDecisionMaker codex lookup, player_has_window_stratagem
#
# Usage: godot --headless --path 40k --script tests/test_custodes_codex_framework.gd

const FIXTURE := "cus11e_c5_active"

var passed := 0
var failed := 0
var SM = null
var GS = null
var PM = null
var Codex = null


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])


func _initialize() -> void:
	await create_timer(0.3).timeout
	await _run()
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _stage_fixture() -> bool:
	var slm = root.get_node("SaveLoadManager")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(slm.save_directory))
	for ext in [".w40ksave", ".meta"]:
		var src = "res://tests/saves/" + FIXTURE + ext
		if FileAccess.file_exists(src):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(slm.save_directory + FIXTURE + ext))
	return slm.load_game(FIXTURE)


func _set_detachment(player: int, det: String) -> void:
	GS.state.factions[str(player)]["detachment"] = det
	SM.load_faction_stratagems_for_player(player)


func _sid(player: int, csv: String) -> String:
	for s in SM.get_faction_stratagems_for_player(player):
		if str(s.get("csv_id", "")) == csv:
			return str(s.id)
	return ""


func _run() -> void:
	SM = root.get_node("StratagemManager")
	GS = root.get_node("GameState")
	PM = root.get_node("PhaseManager")
	Codex = load("res://scripts/codex/custodes/CustodesCodex11e.gd")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	print("\n=== test_custodes_codex_framework ===\n")
	_check("fixture %s loads" % FIXTURE, _stage_fixture())
	GameConstants.edition = 11
	_check("fixture: P1 is Adeptus Custodes", str(GS.state.factions["1"].get("name", GS.state.factions["1"].get("faction", ""))).to_lower().contains("custodes")
		or str(GS.get_faction_name(1)).to_lower().contains("custodes"), str(GS.state.factions["1"]))
	_section_registry()
	_section_modifier_pins()
	_section_windows()
	_section_gating()
	_section_expiry()
	_section_dispatch()


# ---------------------------------------------------------------------------
func _section_registry() -> void:
	print("\n-- A. registry --")
	var ids: Array = Codex.all_registered_ids()
	_check("41 csv ids registered", ids.size() == 41, str(ids.size()))
	var uniq := {}
	for i in ids:
		uniq[i] = true
	_check("no csv id registered twice", uniq.size() == ids.size())
	var groups := {
		"res://scripts/codex/custodes/CustodesCodexFight.gd": 11,
		"res://scripts/codex/custodes/CustodesCodexShooting.gd": 9,
		"res://scripts/codex/custodes/CustodesCodexMovement.gd": 13,
		"res://scripts/codex/custodes/CustodesCodexOther.gd": 8,
	}
	for path in groups:
		var g = load(path)
		_check("%s owns %d ids" % [path.get_file(), groups[path]], g.IDS.size() == groups[path], str(g.IDS.size()))
		var missing_ai: Array = []
		for csv in g.IDS:
			if not g.AI_KIND.has(csv):
				missing_ai.append(csv)
		_check("%s: every id has an AI kind" % path.get_file(), missing_ai.is_empty(), str(missing_ai))
	var impl: Array = Codex.all_implemented_ids()
	_check("all 41 implemented", impl.size() == 41, str(impl.size()))

	var rows: Array = SM._faction_loader.load_faction_stratagems("Adeptus Custodes", "")
	var marker_rows := 0
	var unregistered: Array = []
	var no_windows: Array = []
	for s in rows:
		if Codex.handles(s):
			marker_rows += 1
			if Codex.group_for(s) == null:
				unregistered.append(str(s.get("csv_id", "?")))
			if s.get("timing", {}).get("windows", []).is_empty():
				no_windows.append(str(s.get("csv_id", "")))
	_check("all 41 AC CSV rows carry the custom:custodes11e marker", marker_rows == 41, str(marker_rows))
	_check("every AC CSV row is registered", unregistered.is_empty(), str(unregistered))
	no_windows.sort()
	_check("exactly the three S-panel stratagems have no window", no_windows == ["gilded-champion-auric-champions",
		"honoured-interred-might-of-the-moritoi", "unleash-the-lions-lions-of-the-emperor"], str(no_windows))
	# Duplicated names are told apart by csv_id.
	var by_name := {}
	for s in rows:
		var n := str(s.get("name", ""))
		by_name[n] = int(by_name.get(n, 0)) + 1
	_check("IN AURAMITE CLAD / SUPERHUMAN FOCUS / SWIFT AS THE EAGLE are printed twice",
		int(by_name.get("IN AURAMITE CLAD", 0)) == 2 and int(by_name.get("SUPERHUMAN FOCUS", 0)) == 2 and int(by_name.get("SWIFT AS THE EAGLE", 0)) == 2, str(by_name))


func _section_modifier_pins() -> void:
	print("\n-- B. RulesEngine modifier bit values --")
	var RE = root.get_node("RulesEngine")
	_check("HitModifier.REROLL_ONES == HIT_REROLL_ONES", int(RE.HitModifier.REROLL_ONES) == Codex.HIT_REROLL_ONES)
	_check("HitModifier.PLUS_ONE == HIT_PLUS_ONE", int(RE.HitModifier.PLUS_ONE) == Codex.HIT_PLUS_ONE)
	_check("HitModifier.MINUS_ONE == HIT_MINUS_ONE", int(RE.HitModifier.MINUS_ONE) == Codex.HIT_MINUS_ONE)
	_check("HitModifier.REROLL_FAILED == 8 (masked by PRIME TARGET's re-roll)", int(RE.HitModifier.REROLL_FAILED) == 8)
	_check("HitModifier.REROLL_NON_CRIT == 16 (masked by PRIME TARGET's re-roll)", int(RE.HitModifier.REROLL_NON_CRIT) == 16)
	_check("WoundModifier.PLUS_ONE == WOUND_PLUS_ONE", int(RE.WoundModifier.PLUS_ONE) == Codex.WOUND_PLUS_ONE)
	_check("WoundModifier.MINUS_ONE == WOUND_MINUS_ONE", int(RE.WoundModifier.MINUS_ONE) == Codex.WOUND_MINUS_ONE)
	_check("WoundModifier.REROLL_ONES == 1 / REROLL_FAILED == 2 (masked)", int(RE.WoundModifier.REROLL_ONES) == 1 and int(RE.WoundModifier.REROLL_FAILED) == 2)


const NEW_WINDOWS := ["phase_end", "unit_ended_advance_move", "unit_selected_to_ingress", "unit_selected_to_pile_in",
	"unit_selected_to_consolidate", "enemy_has_fought", "charge_phase_start", "charge_phase_end"]

func _section_windows() -> void:
	print("\n-- C. the new windows --")
	var gen := FileAccess.get_file_as_string("res://../scripts/40kdc/generate-stratagems.mjs")
	if gen == "":
		gen = FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../scripts/40kdc/generate-stratagems.mjs"))
	for w in NEW_WINDOWS:
		_check("KNOWN_WINDOWS has %s" % w, gen == "" or ("'%s'" % w) in gen)
		_check("WINDOW_WHEN_TEXT has %s" % w, SM.WINDOW_WHEN_TEXT.has(w))
	var Dlg = load("res://dialogs/StratagemDialog.gd")
	var dlg = Dlg.new()
	var generic := 0
	for w in NEW_WINDOWS:
		dlg.window_id = w
		dlg.window_ctx = {"phase": "fight", "unit_id": "U_CUSTODIAN_GUARD_A", "enemy_unit_id": "U_BOYZ_B"}
		var h: String = dlg._window_header_text()
		if h.begins_with("Stratagem opportunity"):
			generic += 1
			print("    generic header for %s: %s" % [w, h])
	_check("StratagemDialog has a specific header for every new window", generic == 0, str(generic))
	dlg.free()
	# Every AC row's windows are KNOWN (the generator refuses unknown ones).
	var unknown: Array = []
	for s in SM._faction_loader.load_faction_stratagems("Adeptus Custodes", ""):
		for w in s.get("timing", {}).get("windows", []):
			if not SM.WINDOW_WHEN_TEXT.has(str(w)):
				unknown.append("%s:%s" % [s.get("csv_id", ""), w])
	_check("every AC row's windows have a when-text", unknown.is_empty(), str(unknown))


func _section_gating() -> void:
	print("\n-- D. window gating --")
	_set_detachment(1, "Guardians of the Throne")
	var sid := _sid(1, "prime-target-guardians-of-the-throne")
	_check("PRIME TARGET loaded (Guardians of the Throne)", sid != "")
	var r = SM.can_use_stratagem(1, sid, "U_PROSECUTORS_A")
	_check("S panel use of a window stratagem refused ('Offered automatically when …')", not r.can_use and "Offered automatically" in str(r.reason), str(r))
	r = SM.can_use_stratagem(1, sid, "U_PROSECUTORS_A", {"window_id": "unit_selected_to_fight", "unit_id": "U_PROSECUTORS_A"})
	_check("wrong window refused", not r.can_use, str(r))
	var sf := _sid(1, "superhuman-focus-guardians-of-the-throne")
	r = SM.can_use_stratagem(1, sf, "U_PROSECUTORS_A")
	_check("SUPERHUMAN FOCUS (phase_end) not usable from the S panel", not r.can_use and "Offered automatically" in str(r.reason), str(r))
	_check("phase_end when-text names the end of a phase", "phase ends" in str(SM.window_when_text("phase_end")).to_lower(), SM.window_when_text("phase_end"))


func _section_expiry() -> void:
	print("\n-- E. duration -> expiry --")
	var rows: Array = SM._faction_loader.load_faction_stratagems("Adeptus Custodes", "")
	var want := {
		"preternatural-rapidity-dread-host": "until the end of the turn",
		"at-spears-length-solar-watch": "until the end of the turn",
		"manoeuvre-and-fire-aquilan-shield": "until the end of the turn",
		"no-escape-shadowkeepers": "until the end of the turn",
		"golden-light-of-the-moiraides-dread-host": "until the start of your next command phase",
		"unceasing-onslaught-might-of-the-moritoi": "until the end of the turn",
		"unlimited-endurance-guardians-of-the-throne": "until the end of the turn",
		"inexorable-solar-watch": "until the end of the turn",
		"psy-chaff-volley-null-maiden-vigil": "until the end of the turn",
	}
	for s in rows:
		var csv := str(s.get("csv_id", ""))
		if want.has(csv):
			_check("%s effect text carries '%s'" % [csv, want[csv]], str(want[csv]) in str(s.get("effect_text", "")).to_lower(), str(s.get("effect_text", "")))


func _section_dispatch() -> void:
	print("\n-- F. StratagemManager / AI dispatch --")
	for det in ["Null Maiden Vigil", "Auric Champions", "Lions of the Emperor", "Might of the Moritoi", "Shadowkeepers",
			"Guardians of the Throne", "Honoured Companions", "Solar Watch", "Emperor's Chosen", "Emissaries Imperatus",
			"Aquilan Shield", "Grav-Assault Force", "Dread Host"]:
		_set_detachment(1, det)
		var rows: Array = SM.get_faction_stratagems_for_player(1)
		var codex_rows := 0
		var unimpl: Array = []
		for s in rows:
			if Codex.handles(s):
				codex_rows += 1
				if not bool(s.get("implemented", false)):
					unimpl.append(str(s.get("csv_id", "")))
				var adm = load("res://scripts/AIDecisionMaker.gd")
				if adm._codex_for_strat(s) != Codex:
					unimpl.append("AI:" + str(s.get("csv_id", "")))
				if SM.codex_for(s) != Codex:
					unimpl.append("SM:" + str(s.get("csv_id", "")))
		_check("%s: %d codex rows, all implemented + dispatched to CustodesCodex11e" % [det, codex_rows], codex_rows >= 2 and unimpl.is_empty(), str(unimpl))
	_set_detachment(1, "Dread Host")
	_check("player_has_window_stratagem: Dread Host has unit_selected_to_ingress", Codex.player_has_window_stratagem(1, "unit_selected_to_ingress"))
	_check("player_has_window_stratagem: Dread Host has unit_selected_to_pile_in", Codex.player_has_window_stratagem(1, "unit_selected_to_pile_in"))
	_check("player_has_window_stratagem: Dread Host has no unit_selected_to_consolidate", not Codex.player_has_window_stratagem(1, "unit_selected_to_consolidate"))
	_check("player_has_window_stratagem: the Ork player has none", not Codex.player_has_window_stratagem(2, "unit_selected_to_pile_in"))
	_set_detachment(1, "Null Maiden Vigil")
	var bm := _sid(1, "anathema-blademastery-null-maiden-vigil")
	_check("variant label: ANATHEMA BLADEMASTERY lethal", Codex.variant_label(SM.get_stratagem(bm), "lethal_hits") == "[LETHAL HITS]")
	_check("variant label: ANATHEMA BLADEMASTERY sustained", Codex.variant_label(SM.get_stratagem(bm), "sustained_hits") == "[SUSTAINED HITS 1]")
	# Battle-shocked target refused (15.01) for a codex row.
	PM.transition_to_phase(10)
	GS.state.units["U_VIGILATORS_A"]["flags"]["battle_shocked"] = true
	var r = SM.can_use_stratagem(1, bm, "U_VIGILATORS_A", {"window_id": "unit_selected_to_fight", "unit_id": "U_VIGILATORS_A", "variant_id": "lethal_hits"})
	_check("battle-shocked VIGILATOR SQUAD refused", not r.can_use, str(r))
	GS.state.units["U_VIGILATORS_A"]["flags"].erase("battle_shocked")
	r = SM.can_use_stratagem(1, bm, "U_VIGILATORS_A", {"window_id": "unit_selected_to_fight", "unit_id": "U_VIGILATORS_A", "variant_id": "lethal_hits"})
	_check("same use allowed once not battle-shocked", r.can_use, str(r))
