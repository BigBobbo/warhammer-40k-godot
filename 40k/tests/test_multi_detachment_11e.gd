extends SceneTree

# 11e MULTI-DETACHMENT ARMIES (core rules 25.03 / 25.04) —
# scripts/codex/ArmyDetachments11e.gd and every rule hook that used to read
# only faction.detachment. An army may select several detachments within the
# Detachment Points pool; ALL of them are active (rule, stratagems,
# enhancements, keyword grants).
#   A. army JSON helpers: names, DP pool (lone 3 DP at Incursion), tags,
#      Force Dispositions, the disposition dropdown restriction
#   B. ArmyListManager 11e construction warnings
#   C. Custodes: a SECOND detachment's rule applies (Honoured Companions),
#      the Favoured Ka'tah comes from the Shield Host detachment wherever it
#      sits, Null Maiden Vigil as a second detachment allows the AP warlord
#   D. Orks: two detachments' melee [SUSTAINED HITS] grants and two
#      BATTLELINE grants at once
#   E. stratagems of every detachment load (StratagemManager)
#   F. FactionAbilityManager.player_has_detachment / get_player_detachments
#   G. a stale faction.detachments after a primary swap does not keep the old one
#
# Board: tests/saves/cus11e_c3_custodes_active.w40ksave (P1 Custodes, P2 Orks).
# Usage: godot --headless --path 40k --script tests/test_multi_detachment_11e.gd

const FIXTURE := "cus11e_c3_custodes_active"
const CG := "U_CUSTODIAN_GUARD_B"
const WS_C := "U_WITCHSEEKERS_C"
const BOYZ := "U_BOYZ_B"
const MEGA := "U_MEGANOBZ_A"
const GRETS := "U_GRETCHIN_C"

var passed := 0
var failed := 0
var GS = null
var SM = null
var A = null   # ArmyDetachments11e
var D = null   # CustodesDetachments
var K = null   # CustodesKatah
var O = null   # OrkDetachments11e


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


func _unit(uid: String) -> Dictionary:
	return GS.state.units.get(uid, {})


func _set_dets(player: int, names: Array) -> void:
	GS.state.factions[str(player)]["detachment"] = names[0]
	GS.state.factions[str(player)]["detachments"] = names.duplicate()


func _army(names: Array, points: int, disposition: String = "") -> Dictionary:
	var dets: Array = []
	for n in names:
		var rec: Dictionary = load("res://scripts/codex/EnhancementRules11e.gd").find_detachment(n)
		dets.append({"name": n, "dp_cost": int(rec.get("detachment_points", 1))})
	return {"faction": {"name": "Adeptus Custodes", "points": points, "detachment": names[0],
		"detachments": names.duplicate(), "force_disposition": disposition}, "detachments": dets, "units": {}}


func _pos(p) -> Vector2:
	return Vector2(float(p.x), float(p.y)) if p is Dictionary else p


func _onto_objective(uid: String, obj_id: String) -> void:
	var c := Vector2.ZERO
	for o in GS.state.board.objectives:
		if str(o.id) == obj_id:
			c = _pos(o.position)
	var models: Array = _unit(uid).models
	for i in range(models.size()):
		models[i]["position"] = {"x": c.x + (i - (models.size() - 1) / 2.0) * 45.0, "y": c.y + 20.0}


func _has_kind(contribs: Array, kind: String, source_part: String) -> bool:
	for c in contribs:
		if str(c.get("kind", "")) == kind and str(c.get("source", "")).find(source_part) >= 0:
			return true
	return false


func _run() -> void:
	GS = root.get_node("GameState")
	SM = root.get_node("StratagemManager")
	A = load("res://scripts/codex/ArmyDetachments11e.gd")
	D = load("res://scripts/codex/custodes/CustodesDetachments.gd")
	K = load("res://scripts/codex/custodes/CustodesKatah.gd")
	O = load("res://scripts/codex/orks/OrkDetachments11e.gd")
	var ai = root.get_node("AIPlayer")
	ai.enabled = false
	ai.ai_players = {1: false, 2: false}
	GS.set_edition(11)
	print("\n=== test_multi_detachment_11e ===\n")
	_check("fixture %s loads" % FIXTURE, _stage_fixture())
	GS.set_edition(11)

	_section_helpers()
	_section_construction()
	_section_custodes()
	_section_orks()
	_section_stratagems()
	_section_fam()
	_section_stale_list()


func _section_helpers() -> void:
	print("\n-- A. army JSON helpers --")
	var army := {"faction": {"detachment": "Lions of the Emperor", "detachments": ["Lions of the Emperor", "Solar Watch"]},
		"detachments": [{"name": "Solar Watch", "dp_cost": 1}, {"name": "Null Maiden Vigil", "dp_cost": 1}]}
	_check("names: primary first, faction.detachments + top-level, deduped",
		A.names_from_army(army) == ["Lions of the Emperor", "Solar Watch", "Null Maiden Vigil"], str(A.names_from_army(army)))
	_check("an old single-detachment army still reads its one detachment",
		A.names_from_army({"faction": {"detachment": "Guardians of the Throne"}}) == ["Guardians of the Throne"])
	_check("Strike Force pool 3 DP, Incursion 2 DP", A.dp_pool(2000) == 3 and A.dp_pool(1000) == 2)
	_check("allowed dispositions: one per detachment, game ids, primary first",
		A.allowed_dispositions(_army(["Lions of the Emperor", "Solar Watch"], 2000)) == ["disruption", "reconnaissance"],
		str(A.allowed_dispositions(_army(["Lions of the Emperor", "Solar Watch"], 2000))))
	_check("declared disposition read in game form",
		A.declared_disposition(_army(["Solar Watch"], 2000, "purge-the-foe")) == "purge_the_foe")
	_check("unknown detachments: no restriction (every disposition)", A.allowed_dispositions({"faction": {"detachment": "Nope"}}).is_empty())
	# The dropdown restriction (MainMenu / lobbies).
	var dd := OptionButton.new()
	var disps: Array = load("res://scripts/data/PrimaryMissionData11e.gd").DISPOSITIONS
	for d in disps:
		dd.add_item(str(d))
	dd.select(disps.find("take_and_hold"))
	var target: String = A.restrict_disposition_dropdown(dd, _army(["Lions of the Emperor", "Solar Watch"], 2000, "reconnaissance"), disps, true)
	_check("army change: switch to the army's own pick", target == "reconnaissance", target)
	_check("Take and Hold greyed out (no detachment gives it)", dd.is_item_disabled(disps.find("take_and_hold")))
	_check("Disruption / Reconnaissance stay selectable",
		not dd.is_item_disabled(disps.find("disruption")) and not dd.is_item_disabled(disps.find("reconnaissance")))
	dd.select(disps.find("disruption"))
	_check("same army, a legal pick is kept", A.restrict_disposition_dropdown(dd, _army(["Lions of the Emperor", "Solar Watch"], 2000, "reconnaissance"), disps, false) == "")
	dd.free()


func _section_construction() -> void:
	print("\n-- B. construction (DP pool, lone 3 DP, tags, disposition) --")
	_check("Lions + Solar Watch + Null Maiden at 2000 (3 DP): legal",
		A.construction_problems(_army(["Lions of the Emperor", "Solar Watch", "Null Maiden Vigil"], 2000)).is_empty())
	var over: Array = A.construction_problems(_army(["Lions of the Emperor", "Solar Watch", "Null Maiden Vigil"], 1000))
	_check("…at 1000 (pool 2): over the pool", over.size() == 1 and str(over[0]).contains("3 DP, pool is 2"), str(over))
	_check("Guardians of the Throne (3 DP) alone at 1000: legal (Incursion exception)",
		A.construction_problems(_army(["Guardians of the Throne"], 1000)).is_empty())
	_check("Guardians of the Throne + Lions at 2000: over the pool",
		not A.construction_problems(_army(["Guardians of the Throne", "Lions of the Emperor"], 2000)).is_empty())
	var tag: Array = A.construction_problems(_army(["Solar Watch", "Shadowkeepers"], 2000))
	_check("Solar Watch + Shadowkeepers share 'Unique: Shield Host'", tag.size() == 1 and str(tag[0]).contains("Shield Host"), str(tag))
	var alm = root.get_node("ArmyListManager")
	var v: Dictionary = alm.validate_army_construction_11e(_army(["Solar Watch", "Shadowkeepers"], 2000, "disruption"))
	var joined := " | ".join(PackedStringArray(v.warnings.map(func(w): return str(w))))
	_check("ArmyListManager warns about the shared tag", joined.contains("share the Unique"), joined)
	_check("…and a disposition no detachment gives", joined.contains("Force Disposition disruption"), joined)
	var ok: Dictionary = alm.validate_army_construction_11e(_army(["Lions of the Emperor", "Solar Watch"], 2000, "reconnaissance"))
	var ok_joined := " | ".join(PackedStringArray(ok.warnings.map(func(w): return str(w))))
	_check("a legal two-detachment list: no detachment / disposition warning",
		not ok_joined.contains("DP") and not ok_joined.contains("Unique") and not ok_joined.contains("Force Disposition"), ok_joined)


func _section_custodes() -> void:
	print("\n-- C. Custodes: every selected detachment is active --")
	_set_dets(1, ["Lions of the Emperor", "Honoured Companions"])
	_check("has_det: primary and second", D.has_det(1, D.LIONS) and D.has_det(1, D.HONOURED))
	_onto_objective(CG, "obj_nml_1")
	_check("Honoured Companions (second detachment): Companion's Watch re-rolls wound 1s",
		_has_kind(D.wound_effects(_unit(CG), _unit(BOYZ), true, 6, 5), "reroll_ones", "Companion's Watch"))
	_set_dets(1, ["Lions of the Emperor"])
	_check("without it: no re-roll", not _has_kind(D.wound_effects(_unit(CG), _unit(BOYZ), true, 6, 5), "reroll_ones", "Companion's Watch"))
	_set_dets(1, ["Lions of the Emperor", "Solar Watch"])
	_check("Favoured Ka'tah from the Shield Host detachment taken second: Calistus", K.favoured_katah(1) == "calistus", K.favoured_katah(1))
	_check("its text names Talon Sortie", K.favoured_katah_text(1, "calistus").contains("+2"), K.favoured_katah_text(1, "calistus"))
	_set_dets(1, ["Lions of the Emperor"])
	_check("no Shield Host detachment: no Favoured Ka'tah", K.favoured_katah(1) == "")
	var ws: Dictionary = _unit(WS_C).duplicate()
	ws["id"] = WS_C
	ws.meta["keywords"] = ws.meta.get("keywords", []) + ["CHARACTER"]
	_check("an ANATHEMA PSYKANA warlord is refused under Lions alone", K.warlord_block_reason(ws, ["Lions of the Emperor"]) != "")
	_check("…allowed with Null Maiden Vigil as a second detachment",
		K.warlord_block_reason(ws, ["Lions of the Emperor", "Null Maiden Vigil"]) == "")
	_set_dets(1, ["Guardians of the Throne"])


func _section_orks() -> void:
	print("\n-- D. Orks: two detachments' rules at once --")
	_set_dets(2, ["Bully Boyz", "Green Tide"])
	var mega: Dictionary = O.melee_sustained_hits(_unit(MEGA))
	var boyz: Dictionary = O.melee_sustained_hits(_unit(BOYZ))
	_check("Bully Boyz (primary): Meganobz melee [SUSTAINED HITS 1]", int(mega.value) == 1 and str(mega.source).contains("Bully Boyz"), str(mega))
	_check("Green Tide (second): Boyz melee [SUSTAINED HITS 1]", int(boyz.value) == 1 and str(boyz.source).contains("Green Tide"), str(boyz))
	_set_dets(2, ["Bully Boyz"])
	_check("without Green Tide the Boyz get nothing", int(O.melee_sustained_hits(_unit(BOYZ)).value) == 0)
	var grets: Dictionary = _unit(GRETS)
	var kws: Array = grets.meta.keywords
	kws.erase("BATTLELINE")
	_set_dets(2, ["Bully Boyz", "Runt Swarm"])
	O.apply_keyword_grants(2)
	_check("Runt Swarm as a second detachment grants Gretchin BATTLELINE", "BATTLELINE" in _unit(GRETS).meta.keywords)
	_set_dets(2, ["War Horde"])


func _section_stratagems() -> void:
	print("\n-- E. stratagems of every detachment --")
	_set_dets(1, ["Lions of the Emperor", "Solar Watch"])
	SM.load_faction_stratagems_for_player(1)
	var names: Array = []
	for sid in SM._player_faction_stratagems.get("1", []):
		names.append(str(SM.stratagems.get(sid, {}).get("name", "")).to_upper())
	_check("Lions of the Emperor stratagem loaded (Unleash the Lions)", "UNLEASH THE LIONS" in names, str(names))
	_check("Solar Watch stratagem loaded (Inexorable)", "INEXORABLE" in names, str(names))
	_check("no other detachment's stratagems (Guardians' Prime Target)", not "PRIME TARGET" in names, str(names))
	_set_dets(1, ["Guardians of the Throne"])
	SM.load_faction_stratagems_for_player(1)


func _section_fam() -> void:
	print("\n-- F. FactionAbilityManager --")
	var fam = root.get_node("FactionAbilityManager")
	_set_dets(2, ["Freebooter Krew", "Taktikal Brigade"])
	_check("player_has_detachment: primary", fam.player_has_detachment(2, "Freebooter Krew"))
	_check("player_has_detachment: second", fam.player_has_detachment(2, "Taktikal Brigade"))
	_check("…not one it did not take", not fam.player_has_detachment(2, "Dread Mob"))
	_check("get_player_detachments lists both", fam.get_player_detachments(2) == ["Freebooter Krew", "Taktikal Brigade"], str(fam.get_player_detachments(2)))
	_set_dets(2, ["War Horde"])


func _section_stale_list() -> void:
	print("\n-- G. primary swapped after load --")
	_set_dets(1, ["Lions of the Emperor", "Solar Watch"])
	GS.state.factions["1"]["detachment"] = "Dread Host"
	var names: Array = A.player_detachments(1)
	_check("the swapped-in primary replaces the old one; the extra stays", names == ["Dread Host", "Solar Watch"], str(names))
	_set_dets(1, ["Guardians of the Throne"])
