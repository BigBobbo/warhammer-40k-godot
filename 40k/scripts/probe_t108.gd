extends RefCounted

const AIDM := preload("res://scripts/AIDecisionMaker.gd")

static func probe_range_band(snapshot: Dictionary) -> Dictionary:
	var u = snapshot.get("units", {})
	var shooter_id = ""
	var target_id = ""
	for uid in u:
		var unit = u[uid]
		if unit.get("owner", 0) != 1:
			continue
		var has_ranged = false
		for w in unit.get("meta", {}).get("weapons", []):
			if str(w.get("type", "")).to_lower() == "ranged":
				has_ranged = true
				break
		if has_ranged:
			shooter_id = uid
			break
	for uid in u:
		if u[uid].get("owner", 0) == 2 and u[uid].get("status", 0) == 0:
			target_id = uid
			break
	if shooter_id == "" or target_id == "":
		return {"err": "no_pair", "ids": [shooter_id, target_id]}
	var shooter = u[shooter_id]
	var target = u[target_id]
	var weapon = {}
	for w in shooter.get("meta", {}).get("weapons", []):
		if str(w.get("type", "")).to_lower() == "ranged":
			weapon = w
			break
	if weapon.is_empty():
		return {"err": "no_weapon"}
	var weapon_range = float(str(weapon.get("range", "24")).replace("\"", ""))
	var dist = AIDM._get_closest_model_distance_inches(shooter, target)
	var ratio = dist / weapon_range if weapon_range > 0 else 0.0
	var multiplier = 1.0
	if ratio <= 0.5:
		multiplier = 1.10
	elif ratio <= 0.75:
		multiplier = 1.0
	else:
		multiplier = 0.85
	var base_score = AIDM._score_shooting_target(weapon, target, snapshot, shooter)
	# Now spoof a faraway target by mutating distance via a synthetic target
	return {
		"shooter_id": shooter_id,
		"target_id": target_id,
		"weapon_name": weapon.get("name", "?"),
		"weapon_range_in": weapon_range,
		"distance_in": dist,
		"range_ratio": ratio,
		"range_band_multiplier": multiplier,
		"score_with_band": base_score,
	}

static func probe_range_band_synthetic() -> Dictionary:
	# Test 3 ratios independently
	var ratios = [0.3, 0.6, 0.9]
	var out = []
	for r in ratios:
		var m = 1.0
		if r <= 0.5: m = 1.10
		elif r <= 0.75: m = 1.0
		else: m = 0.85
		out.append({"ratio": r, "expected_multiplier": m})
	return {"synth": out}

static func probe_secondaries(snapshot: Dictionary, player: int) -> Dictionary:
	var awareness = AIDM._build_secondary_awareness(snapshot, player)
	# Try the cache path too
	AIDM._secondary_awareness_p2 = awareness if player == 2 else AIDM._secondary_awareness_p2
	AIDM._secondary_awareness_p1 = awareness if player == 1 else AIDM._secondary_awareness_p1
	return awareness

static func probe_fight_order(snapshot: Dictionary, player: int) -> Dictionary:
	var plan = AIDM._build_fight_order_plan(snapshot, player)
	# Show fight prio for each unit
	var rows = []
	for uid in plan:
		var u = snapshot.get("units", {}).get(uid, {})
		rows.append({"uid": uid, "name": u.get("name", "?"), "owner": u.get("owner", 0)})
	return {"plan": plan, "rows": rows}

static func probe_character_threat(snapshot: Dictionary, player: int) -> Dictionary:
	var u = snapshot.get("units", {})
	var character = {}
	var non_character = {}
	for uid in u:
		var unit = u[uid]
		if unit.get("owner", 0) != player:
			continue
		var kw = unit.get("meta", {}).get("keywords", [])
		var is_char = "CHARACTER" in kw and not ("VEHICLE" in kw)
		if is_char and character.is_empty():
			character = unit
		elif not is_char and non_character.is_empty():
			non_character = unit
	if character.is_empty() or non_character.is_empty():
		return {"err": "no_pair", "have_char": not character.is_empty(), "have_nonchar": not non_character.is_empty()}
	# Build minimal threat data: one fake enemy at known dist
	var threat_data = [{
		"unit_id": "fake_enemy",
		"centroid": Vector2(500, 500),
		"has_melee": true,
		"has_ranged": true,
		"charge_threat_px": 600.0,
		"shoot_threat_px": 800.0,
		"unit_value": 100.0,
	}]
	var test_pos = Vector2(700, 700)
	var char_eval = AIDM._evaluate_position_threat(test_pos, threat_data, character)
	var noncar_eval = AIDM._evaluate_position_threat(test_pos, threat_data, non_character)
	return {
		"character_id": character.get("id", "?"),
		"character_name": character.get("meta", {}).get("name", "?"),
		"character_total_threat": char_eval.get("total_threat", -1.0),
		"non_char_id": non_character.get("id", "?"),
		"non_char_name": non_character.get("meta", {}).get("name", "?"),
		"non_char_total_threat": noncar_eval.get("total_threat", -1.0),
		"character_multiplier_inferred": char_eval.get("total_threat", 0.0) / max(noncar_eval.get("total_threat", 1.0), 0.001),
	}

static func probe_matchup_classify(snapshot: Dictionary, player: int) -> Dictionary:
	var u = snapshot.get("units", {})
	var rows = []
	for uid in u:
		var unit = u[uid]
		if unit.get("owner", 0) != player:
			continue
		var role = AIDM._classify_deployment_role(unit)
		rows.append({"id": uid, "name": unit.get("meta", {}).get("name", uid), "role": role})
	return {"player": player, "classifications": rows}

static func probe_late_game_pivot() -> Dictionary:
	return {
		"round_1": AIDM._get_round_strategy_modifiers(1),
		"round_3": AIDM._get_round_strategy_modifiers(3),
		"round_5": AIDM._get_round_strategy_modifiers(5),
	}
