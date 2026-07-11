extends SceneTree

# Reproduction harness for the reported bug: AI Custodian Guard declares a
# charge, the 2D6 roll SUCCEEDS (e.g. 7" vs 6.8" needed), but APPLY_CHARGE_MOVE
# is then REJECTED by ChargePhase._validate_charge_movement_constraints and the
# AI falls back to SKIP_CHARGE ("charge move failed — skipping").
#
# This runs the AI's REAL placement code (AIDecisionMaker._compute_charge_move)
# against the phase's REAL validator over many seeded geometries mirroring the
# reported board: 5 Custodian Guard (40mm circular) charging a congested cluster
# of Deffkoptas (75x42mm oval bases, FLY VEHICLE) with a second Deffkoptas unit
# adjacent. It tallies which validation categories reject the AI's move.
#
# Usage: godot --headless --path . -s tests/test_repro_ai_charge_congestion.gd

const PX := 40.0  # pixels per inch

var category_counts := {}
var example_per_category := {}
var total := 0
var rejected := 0
var ai_skipped := 0

func _init():
	create_timer(0.2).timeout.connect(_run)

func _make_custodians(id: String, owner: int, positions: Array) -> Dictionary:
	var models = []
	for i in range(positions.size()):
		models.append({
			"id": "m%d" % (i + 1),
			"alive": true,
			"current_wounds": 3,
			"wounds": 3,
			"base_mm": 40,
			"base_type": "circular",
			"rotation": 0.0,
			"position": {"x": positions[i].x, "y": positions[i].y},
		})
	return {
		"id": id, "squad_id": id, "owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"flags": {},
		"meta": {"name": "Custodian Guard", "keywords": ["INFANTRY", "IMPERIUM", "ADEPTUS CUSTODES"], "stats": {"move": 6, "toughness": 6, "save": 2, "wounds": 3}},
		"models": models,
		"embarked_in": null,
	}

# entries: Array of {pos: Vector2, rot: float, alive: bool}
func _make_koptas(id: String, owner: int, entries: Array) -> Dictionary:
	var models = []
	for i in range(entries.size()):
		var e = entries[i]
		models.append({
			"id": "m%d" % (i + 1),
			"alive": e.alive,
			"current_wounds": 4 if e.alive else 0,
			"wounds": 4,
			"base_mm": 75,
			"base_type": "oval",
			"base_dimensions": {"length": 42, "width": 75},
			"rotation": e.rot,
			"position": {"x": e.pos.x, "y": e.pos.y},
		})
	return {
		"id": id, "squad_id": id, "owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"flags": {},
		"meta": {"name": id, "keywords": ["DEFFKOPTAS", "FLY", "GRENADES", "ORKS", "SPEED FREEKS", "VEHICLE"], "stats": {"move": 12, "toughness": 6, "save": 4, "wounds": 4}},
		"models": models,
		"embarked_in": null,
	}

func _setup_state(units: Dictionary) -> void:
	var gs = root.get_node("GameState")
	gs.state = {
		"meta": {"phase": GameStateData.Phase.CHARGE, "active_player": 2, "battle_round": 5, "turn_number": 5, "game_id": "repro"},
		"units": units,
		"players": {"1": {"cp": 6, "vp": 24}, "2": {"cp": 1, "vp": 53}},
		"board": {"terrain": []},
		"phase_log": [],
	}

# Min shape-aware edge-to-edge distance between two units (inches)
func _min_unit_gap(unit_a: Dictionary, unit_b: Dictionary) -> float:
	var m = root.get_node("Measurement")
	var best := INF
	for ma in unit_a.models:
		if not ma.alive:
			continue
		for mb in unit_b.models:
			if not mb.alive:
				continue
			best = min(best, m.model_to_model_distance_inches(ma, mb))
	return best

func _run():
	print("\n=== REPRO: AI charge move vs phase validator (congested oval targets) ===")
	GameConstants.edition = 11
	var tm = root.get_node("TerrainManager")
	tm.terrain_features.clear()

	var phase = load("res://phases/ChargePhase.gd").new()
	root.add_child(phase)

	var rng = RandomNumberGenerator.new()

	# seed 0 doubles as the PINNED report case: the whole-unit gap is forced
	# to 6.8" and the roll to 7 — the exact numbers from the player report
	# ("charge roll [3,4] = 7\" vs 6.8\" needed - SUCCESS" then "charge move
	# failed — skipping").
	for seed_i in range(300):
		rng.seed = 100000 + seed_i
		# variants: 150-199 multi-target declarations, 200-249 ruins walls
		# near the target cluster, 250-299 higher rolls (deep charges)
		var variant_multi: bool = seed_i >= 150 and seed_i < 200
		var variant_walls: bool = seed_i >= 200 and seed_i < 250
		var variant_deep: bool = seed_i >= 250

		# --- Deffkoptas Alpha: 6 ovals in a loose 2x3 blob, jitter + rotations ---
		var kc = Vector2(1000.0, 800.0)
		var alpha_entries = []
		var dead_idx := rng.randi_range(0, 5) if rng.randf() < 0.7 else -1  # usually 5/6 alive
		for i in range(6):
			var col = i % 3
			var row = i / 3
			var p = kc + Vector2(
				(col - 1) * rng.randf_range(110.0, 140.0) + rng.randf_range(-20.0, 20.0),
				(row - 0.5) * rng.randf_range(100.0, 130.0) + rng.randf_range(-20.0, 20.0))
			alpha_entries.append({"pos": p, "rot": rng.randf_range(0.0, PI), "alive": i != dead_idx})

		# --- Deffkoptas Beta: adjacent blob (like the reported board) ---
		var include_beta: bool = seed_i % 3 != 2 or variant_multi  # 2/3 of runs have the second unit nearby
		var beta_entries = []
		if include_beta:
			var bc = kc + Vector2(rng.randf_range(-260.0, -140.0), rng.randf_range(-200.0, -80.0))
			if variant_multi:
				# multi-target charges need Beta adjacent AND reachable
				bc = kc + Vector2(rng.randf_range(-240.0, -160.0), rng.randf_range(40.0, 100.0))
			for i in range(6):
				var col = i % 3
				var row = i / 3
				var p = bc + Vector2(
					(col - 1) * rng.randf_range(110.0, 140.0) + rng.randf_range(-15.0, 15.0),
					(row - 0.5) * rng.randf_range(100.0, 130.0) + rng.randf_range(-15.0, 15.0))
				beta_entries.append({"pos": p, "rot": rng.randf_range(0.0, PI), "alive": true})

		# --- Custodians: 5-model blob south of Alpha, then translate so the
		#     min edge-to-edge gap to Alpha matches the desired charge gap ---
		var desired_gap: float = rng.randf_range(5.0, 7.5)  # inches (report was 6.8")
		if seed_i == 0:
			desired_gap = 6.8  # pinned report case
		var cc = kc + Vector2(rng.randf_range(-60.0, 60.0), 480.0)
		var cust_pos = []
		for i in range(5):
			var col = i % 3
			var row = i / 3
			cust_pos.append(cc + Vector2(
				(col - 1) * rng.randf_range(85.0, 110.0) + rng.randf_range(-10.0, 10.0),
				(row - 0.5) * rng.randf_range(85.0, 110.0) + rng.randf_range(-10.0, 10.0)))

		var units = {}
		var alpha = _make_koptas("U_DEFFKOPTAS_A", 1, alpha_entries)
		var cust = _make_custodians("U_CUSTODIAN_GUARD_A", 2, cust_pos)

		# translate custodians to match desired gap
		var cur_gap = _min_unit_gap(cust, alpha)
		if cur_gap == INF:
			continue
		var shift = Vector2(0, (cur_gap - desired_gap) * PX)
		for mm in cust.models:
			mm.position.y -= shift.y
		cur_gap = _min_unit_gap(cust, alpha)

		units["U_DEFFKOPTAS_A"] = alpha
		units["U_CUSTODIAN_GUARD_A"] = cust
		var beta
		if include_beta:
			beta = _make_koptas("U_DEFFKOPTAS_B", 1, beta_entries)
			units["U_DEFFKOPTAS_B"] = beta

		# Ruins with walls around the target cluster (mirrors the reported
		# board: koptas hovering in a ruin; INFANTRY may cross walls but may
		# not END on one)
		var tm2 = root.get_node("TerrainManager")
		tm2.terrain_features.clear()
		if variant_walls:
			var poly = PackedVector2Array([
				kc + Vector2(-260, -220), kc + Vector2(260, -220),
				kc + Vector2(260, 180), kc + Vector2(-260, 180)])
			var walls = [
				{"start": kc + Vector2(-260, 180), "end": kc + Vector2(-40, 180)},
				{"start": kc + Vector2(80, 180), "end": kc + Vector2(260, 180)},
				{"start": kc + Vector2(-260, -220), "end": kc + Vector2(-260, 180)},
			]
			tm2.terrain_features.append({
				"id": "repro_ruin", "type": "ruins", "polygon": poly,
				"height_category": "tall", "walls": walls,
				"can_move_through": {"INFANTRY": true, "VEHICLE": false, "MONSTER": false},
			})

		_setup_state(units)
		phase.game_state_snapshot = root.get_node("GameState").state

		# Roll: smallest success is ceil(gap - ER); the report had gap 6.8, roll 7.
		var er = GameConstants.engagement_range_inches()
		var min_roll = int(ceil(cur_gap - er))
		var roll = clamp(min_roll + rng.randi_range(0, 3), 2, 12)
		if variant_deep:
			roll = clamp(min_roll + rng.randi_range(3, 6), 2, 12)
		if seed_i == 0:
			roll = 7  # pinned report case: 7" roll vs 6.8" gap

		var targets = ["U_DEFFKOPTAS_A"]
		if variant_multi:
			# declare both kopta units when Beta is genuinely reachable
			var beta_gap = _min_unit_gap(cust, beta)
			if beta_gap <= roll + er - 0.2:
				targets = ["U_DEFFKOPTAS_A", "U_DEFFKOPTAS_B"]

		total += 1
		var action = AIDecisionMaker._compute_charge_move(root.get_node("GameState").state, "U_CUSTODIAN_GUARD_A", roll, targets, 2)
		if action.get("type", "") != "APPLY_CHARGE_MOVE":
			ai_skipped += 1
			print("REPRO seed=%d gap=%.2f roll=%d -> AI self-skipped (%s)" % [seed_i, cur_gap, roll, action.get("_ai_description", "?")])
			continue

		var paths = action.payload.per_model_paths
		# 11e: the post-roll selection travels with the move and REPLACES the
		# target list before constraint validation (see _validate_apply_charge_move)
		var validate_targets = action.payload.get("target_unit_ids", targets)
		var validation = phase._validate_charge_movement_constraints("U_CUSTODIAN_GUARD_A", paths, {"distance": roll, "targets": validate_targets})
		if not validation.valid:
			rejected += 1
			var cats = {}
			for ce in validation.categorized_errors:
				cats[ce.category] = true
			for c in cats:
				category_counts[c] = category_counts.get(c, 0) + 1
				if not example_per_category.has(c):
					var details = []
					for ce in validation.categorized_errors:
						if ce.category == c:
							details.append(ce.detail)
					example_per_category[c] = "seed=%d gap=%.2f roll=%d beta=%s: %s" % [seed_i, cur_gap, roll, str(include_beta), str(details)]
			print("REPRO seed=%d gap=%.2f roll=%d beta=%s REJECTED cats=%s" % [seed_i, cur_gap, roll, str(include_beta), str(cats.keys())])
		# (accepted runs stay quiet to keep the log readable)

	print("\n=== SUMMARY ===")
	print("total=%d  accepted=%d  rejected=%d  ai_self_skipped=%d" % [total, total - rejected - ai_skipped, rejected, ai_skipped])
	print("rejection rate: %.1f%%" % (100.0 * rejected / max(1, total)))
	for c in category_counts:
		print("  category %s: %d runs" % [c, category_counts[c]])
	print("\n--- one example per category ---")
	for c in example_per_category:
		print("  [%s] %s" % [c, example_per_category[c]])

	# ── Regression gate ──
	# The AI must NEVER submit a charge move the phase validator rejects
	# ("charge roll SUCCESS → charge move failed — skipping"). Honest
	# self-skips are only tolerated for the rare genuinely-blocked geometry
	# (walled targets on a minimum roll).
	var ok := true
	if rejected > 0:
		print("REGRESSION: %d AI charge moves were rejected by the validator" % rejected)
		ok = false
	if ai_skipped > 3:
		print("REGRESSION: %d/%d AI self-skips — placement engine too conservative" % [ai_skipped, total])
		ok = false
	print("\n=== %s ===" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
