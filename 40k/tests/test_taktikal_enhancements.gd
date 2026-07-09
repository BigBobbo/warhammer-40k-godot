extends SceneTree

# Taktikal Brigade enhancements (Orks):
#   Skwad Leader   — Warboss can attach to a Kommandos unit; while leading it,
#                    the unit has Infiltrators and Stealth.
#   Mek Kaptin     — Big Mek can attach to a Flash Gitz unit; ranged attacks
#                    from the bearer's unit re-roll the Hit roll.
#   Mork's Kunnin' — after deployment, redeploy up to 3 ORKS units (they can
#                    be placed into Strategic Reserves).
#   Gob Boomer     — extends the Taktiks (Lissen 'Ere) issue range; the
#                    detachment rule itself is not implemented yet, so the
#                    enhancement has no runtime effect (documented gap).
#
# Run: godot --headless --path 40k --script tests/test_taktikal_enhancements.gd

var _passed = 0
var _failed = 0


func _initialize():
	await create_timer(0.2).timeout
	_run()
	print("\n=== RESULTS: %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _check(label: String, cond: bool) -> void:
	if cond:
		print("[PASS] %s" % label)
		_passed += 1
	else:
		print("[FAIL] %s" % label)
		_failed += 1


func _sum_wounds(result: Dictionary) -> int:
	var total := 0
	for d in result.get("dice", []):
		var ctx = str(d.get("context", "")).to_lower()
		if "wound" in ctx and d.has("successes"):
			total += int(d.get("successes", 0))
	return total


func _warboss(enhancements: Array) -> Dictionary:
	return {"id": "U_WARBOSS", "owner": 1, "status": 2, "attached_to": null,
		"meta": {"name": "Warboss", "keywords": ["CHARACTER", "INFANTRY", "ORKS", "WARBOSS"],
			"leader_data": {"can_lead": ["BOYZ"]}, "enhancements": enhancements, "abilities": []},
		"flags": {},
		"models": [{"id": "m0", "position": {"x": 0.0, "y": 0.0}, "alive": true, "wounds": 6, "current_wounds": 6}]}


func _kommandos() -> Dictionary:
	return {"id": "U_KOMMANDOS", "owner": 1, "status": 2,
		"meta": {"name": "Kommandos", "keywords": ["GRENADES", "INFANTRY", "KOMMANDOS", "ORKS", "SMOKE"],
			"enhancements": [], "abilities": []},
		"flags": {}, "attachment_data": {"attached_characters": []},
		"models": [{"id": "m0", "position": {"x": 40.0, "y": 0.0}, "alive": true, "wounds": 1, "current_wounds": 1}]}


func _run():
	var GS = root.get_node("GameState")
	var CAM = root.get_node("CharacterAttachmentManager")
	var UAM = root.get_node("UnitAbilityManager")
	var FAM = root.get_node("FactionAbilityManager")
	var rules = root.get_node("RulesEngine")
	if GS == null or CAM == null or UAM == null or FAM == null or rules == null:
		_check("autoloads present", false)
		return

	# ------------------------------------------------------------------
	# 1. Skwad Leader — attach permission (can_lead extension)
	# ------------------------------------------------------------------
	print("\n=== Skwad Leader — attachment ===")
	GS.state["units"] = {
		"U_WARBOSS": _warboss([]),
		"U_KOMMANDOS": _kommandos(),
	}
	var without = CAM.can_attach("U_WARBOSS", "U_KOMMANDOS")
	_check("Warboss WITHOUT Skwad Leader cannot join Kommandos", not without.get("valid", true))

	GS.state["units"]["U_WARBOSS"] = _warboss(["Skwad Leader"])
	var with_enh = CAM.can_attach("U_WARBOSS", "U_KOMMANDOS")
	_check("Warboss WITH Skwad Leader can join Kommandos", with_enh.get("valid", false))
	_check("get_eligible_bodyguards_for_character lists the Kommandos",
		"U_KOMMANDOS" in GS.get_eligible_bodyguards_for_character("U_WARBOSS"))

	# ------------------------------------------------------------------
	# 2. Skwad Leader — Infiltrators + Stealth while leading Kommandos
	# ------------------------------------------------------------------
	print("\n=== Skwad Leader — Infiltrators + Stealth while leading ===")
	_check("unattached bearer: Kommandos have no Infiltrators yet",
		not GS.unit_has_infiltrators("U_KOMMANDOS"))
	# Attach the bearer
	CAM.attach_character("U_WARBOSS", "U_KOMMANDOS")
	_check("bearer attached to Kommandos",
		GS.state["units"]["U_WARBOSS"].get("attached_to", null) == "U_KOMMANDOS")
	_check("led Kommandos unit has Infiltrators", GS.unit_has_infiltrators("U_KOMMANDOS"))
	_check("attached bearer deploys with Infiltrators too", GS.unit_has_infiltrators("U_WARBOSS"))

	# Stealth: enhancement ability application grants effect_stealth to the led unit
	UAM._applied_this_phase = {}
	UAM._apply_enhancement_abilities(1)
	_check("led Kommandos unit gains effect_stealth (Stealth)",
		GS.state["units"]["U_KOMMANDOS"].get("flags", {}).get("effect_stealth", false))
	_check("RulesEngine sees the Stealth grant",
		rules.has_stealth_ability(GS.state["units"]["U_KOMMANDOS"]))

	# Gate: while leading a NON-Kommandos unit there is no Stealth grant
	GS.state["units"] = {
		"U_WARBOSS": _warboss(["Skwad Leader"]),
		"U_BOYZ": {"id": "U_BOYZ", "owner": 1, "status": 2,
			"meta": {"name": "Boyz", "keywords": ["BOYZ", "INFANTRY", "ORKS"], "enhancements": [], "abilities": []},
			"flags": {}, "attachment_data": {"attached_characters": []},
			"models": [{"id": "m0", "position": {"x": 40.0, "y": 0.0}, "alive": true, "wounds": 1, "current_wounds": 1}]},
	}
	CAM.attach_character("U_WARBOSS", "U_BOYZ")
	UAM._applied_this_phase = {}
	UAM._apply_enhancement_abilities(1)
	_check("leading Boyz grants NO Stealth (Kommandos-only gate)",
		not GS.state["units"]["U_BOYZ"].get("flags", {}).get("effect_stealth", false))
	_check("leading Boyz grants NO Infiltrators", not GS.unit_has_infiltrators("U_BOYZ"))

	# ------------------------------------------------------------------
	# 3. Mek Kaptin — attach permission + ranged hit re-roll
	# ------------------------------------------------------------------
	print("\n=== Mek Kaptin ===")
	# Fictional leader name so the canonical LeaderPairingsLoader CSV cannot
	# contribute pairings — isolates the enhancement-driven can_lead extras.
	var big_mek = {"id": "U_BIGMEK", "owner": 1, "status": 2, "attached_to": null,
		"meta": {"name": "Test Mek Boss", "keywords": ["BIG MEK", "CHARACTER", "INFANTRY", "ORKS"],
			"leader_data": {"can_lead": ["LOOTAS"]}, "enhancements": ["Mek Kaptin"], "abilities": []},
		"flags": {},
		"models": [{"id": "m0", "position": {"x": 0.0, "y": 0.0}, "alive": true, "wounds": 5, "current_wounds": 5}]}
	var flash_gitz = {"id": "U_FLASHGITZ", "owner": 1, "status": 2,
		"meta": {"name": "Flash Gitz", "keywords": ["FLASH GITZ", "INFANTRY", "ORKS"], "enhancements": [], "abilities": []},
		"flags": {}, "attachment_data": {"attached_characters": []},
		"models": [{"id": "m0", "position": {"x": 40.0, "y": 0.0}, "alive": true, "wounds": 2, "current_wounds": 2}]}
	GS.state["units"] = {"U_BIGMEK": big_mek, "U_FLASHGITZ": flash_gitz}
	var mek_attach = CAM.can_attach("U_BIGMEK", "U_FLASHGITZ")
	_check("Big Mek WITH Mek Kaptin can join Flash Gitz", mek_attach.get("valid", false))
	GS.state["units"]["U_BIGMEK"]["meta"]["enhancements"] = []
	_check("Big Mek WITHOUT Mek Kaptin cannot join Flash Gitz",
		not CAM.can_attach("U_BIGMEK", "U_FLASHGITZ").get("valid", true))

	# Re-roll detection: direct, via attached bearer, and absent otherwise
	var board_units = {
		"U_GITZ": {"id": "U_GITZ", "owner": 1,
			"meta": {"name": "Flash Gitz", "keywords": ["FLASH GITZ", "ORKS"], "enhancements": [], "abilities": []},
			"flags": {}, "attachment_data": {"attached_characters": ["U_MEK"]},
			"models": []},
		"U_MEK": {"id": "U_MEK", "owner": 1, "attached_to": "U_GITZ",
			"meta": {"name": "Big Mek", "keywords": ["BIG MEK", "CHARACTER", "ORKS"], "enhancements": ["Mek Kaptin"], "abilities": []},
			"flags": {}, "models": []},
	}
	var board = {"units": board_units}
	_check("unit with attached Mek Kaptin bearer re-rolls",
		rules.unit_has_mek_kaptin_reroll(board_units["U_GITZ"], board))
	_check("the bearer's own unit re-rolls",
		rules.unit_has_mek_kaptin_reroll(board_units["U_MEK"], board))
	var plain_unit = {"meta": {"enhancements": [], "abilities": []}, "flags": {}, "attachment_data": {"attached_characters": []}}
	_check("unrelated unit does not re-roll",
		not rules.unit_has_mek_kaptin_reroll(plain_unit, board))

	# Seeded shooting: a full hit re-roll consumes extra dice from the shared
	# RNG stream, so a single seed can legitimately land fewer wounds — assert
	# the AGGREGATE improvement across seeds instead of per-seed monotonicity.
	var seeds = [3, 7, 21, 42, 63, 99, 123, 200]
	var total_off := 0
	var total_on := 0
	var better := 0
	for s in seeds:
		var off = _shoot_with_enh(rules, [], s)
		var on = _shoot_with_enh(rules, ["Mek Kaptin"], s)
		print("  seed %d: wounds off=%d on=%d" % [s, off, on])
		total_off += off
		total_on += on
		if on > off:
			better += 1
	print("  aggregate: off=%d on=%d (better on %d/%d seeds)" % [total_off, total_on, better, seeds.size()])
	_check("Mek Kaptin re-roll increases total wounds across seeds", total_on > total_off)
	_check("Mek Kaptin re-roll helps on several seeds", better >= 3)

	# ------------------------------------------------------------------
	# 4. Mork's Kunnin' — redeploy machinery
	# ------------------------------------------------------------------
	print("\n=== Mork's Kunnin' ===")
	GS.state["units"] = {
		"U_WARBOSS_MK": {"id": "U_WARBOSS_MK", "owner": 1, "status": 2, "attached_to": null,
			"meta": {"name": "Warboss", "keywords": ["CHARACTER", "INFANTRY", "ORKS", "WARBOSS"],
				"enhancements": ["Mork's Kunnin'"], "abilities": []},
			"flags": {}, "models": [{"id": "m0", "position": {"x": 0.0, "y": 0.0}, "alive": true, "wounds": 6, "current_wounds": 6}]},
		"U_BOYZ_MK": {"id": "U_BOYZ_MK", "owner": 1, "status": 2,
			"meta": {"name": "Boyz", "keywords": ["BOYZ", "INFANTRY", "ORKS"], "enhancements": [], "abilities": []},
			"flags": {}, "models": [{"id": "m0", "position": {"x": 40.0, "y": 0.0}, "alive": true, "wounds": 1, "current_wounds": 1}]},
		"U_WAGON_MK": {"id": "U_WAGON_MK", "owner": 1, "status": 2,
			"meta": {"name": "Battlewagon", "keywords": ["ORKS", "VEHICLE", "TRANSPORT"], "enhancements": [], "abilities": []},
			"flags": {}, "models": [{"id": "m0", "position": {"x": 80.0, "y": 0.0}, "alive": true, "wounds": 16, "current_wounds": 16}]},
		"U_MARINES_MK": {"id": "U_MARINES_MK", "owner": 2, "status": 2,
			"meta": {"name": "Intercessors", "keywords": ["ADEPTUS ASTARTES", "INFANTRY"], "enhancements": [], "abilities": []},
			"flags": {}, "models": [{"id": "m0", "position": {"x": 900.0, "y": 900.0}, "alive": true, "wounds": 2, "current_wounds": 2}]},
	}
	# Reset usage counters (fresh battle)
	FAM._morks_kunnin_redeploys_used = {"1": 0, "2": 0}
	_check("has_morks_kunnin detects the bearer (typographic-apostrophe safe)",
		FAM.has_morks_kunnin(1))
	var eligible = FAM.get_morks_kunnin_eligible_units(1)
	var eligible_ids := []
	for e in eligible:
		eligible_ids.append(e.get("unit_id", ""))
	_check("eligible units include ORKS INFANTRY", "U_BOYZ_MK" in eligible_ids)
	_check("eligible units include ORKS VEHICLES (not INFANTRY-only)", "U_WAGON_MK" in eligible_ids)
	_check("enemy units are not eligible", not "U_MARINES_MK" in eligible_ids)
	_check("redeploys remaining starts at 3", FAM.get_morks_kunnin_redeploys_remaining(1) == 3)

	var redeployable = GS.get_redeploy_units_for_player(1)
	_check("get_redeploy_units_for_player includes Mork's Kunnin' units",
		"U_BOYZ_MK" in redeployable and "U_WAGON_MK" in redeployable)

	FAM.mark_morks_kunnin_redeploy_used(1)
	FAM.mark_morks_kunnin_redeploy_used(1)
	FAM.mark_morks_kunnin_redeploy_used(1)
	_check("after 3 redeploys none remain", FAM.get_morks_kunnin_redeploys_remaining(1) == 0)
	_check("is_morks_kunnin_redeploy_available is false after 3 uses",
		not FAM.is_morks_kunnin_redeploy_available(1))
	_check("exhausted Mork's Kunnin' adds no redeploy units",
		GS.get_redeploy_units_for_player(1).is_empty())
	FAM._morks_kunnin_redeploys_used = {"1": 0, "2": 0}

	# Typographic-apostrophe form (as written by the 40kdc army builder)
	GS.state["units"]["U_WARBOSS_MK"]["meta"]["enhancements"] = ["Mork’s Kunnin’"]
	_check("typographic-apostrophe enhancement name still detected", FAM.has_morks_kunnin(1))


func _shoot_with_enh(rules, enhancements: Array, seed_val: int) -> int:
	var shooters = []
	for i in range(10):
		shooters.append({"id": "ms%d" % i, "position": {"x": 0.0, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular", "alive": true, "wounds": 1, "current_wounds": 1})
	var targets = []
	for i in range(5):
		targets.append({"id": "mt%d" % i, "position": {"x": 200.0, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular", "alive": true, "wounds": 2, "current_wounds": 2,
			"stats": {"toughness": 5, "save": 3}})
	var board = {"units": {
		"U_GITZ_S": {"id": "U_GITZ_S", "owner": 1,
			"meta": {"name": "Flash Gitz", "keywords": ["FLASH GITZ", "ORKS", "INFANTRY"],
				"enhancements": enhancements, "abilities": [],
				"stats": {"toughness": 5, "save": 4, "wounds": 2}},
			"flags": {}, "models": shooters},
		"U_TGT_S": {"id": "U_TGT_S", "owner": 2,
			"meta": {"name": "Marines", "keywords": ["INFANTRY"], "abilities": [],
				"stats": {"toughness": 5, "save": 3, "wounds": 2}},
			"flags": {}, "models": targets}
	}, "meta": {"phase": 8, "active_player": 1, "battle_round": 1}}
	rules.set_test_seed(seed_val)
	var rng = rules.RNGService.new()
	var action := {"type": "SHOOT", "actor_unit_id": "U_GITZ_S",
		"payload": {"assignments": [{"weapon_id": "bolt_rifle", "target_unit_id": "U_TGT_S",
			"model_ids": ["ms0","ms1","ms2","ms3","ms4","ms5","ms6","ms7","ms8","ms9"]}]}}
	return _sum_wounds(rules.resolve_shoot(action, board, rng))
