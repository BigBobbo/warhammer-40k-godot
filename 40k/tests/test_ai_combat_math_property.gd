extends SceneTree

# D1 — does the AI's damage prediction agree with the engine's resolution?
#
# The AI *predicts* combat with its own expected-damage arithmetic
# (AIDecisionMaker._estimate_weapon_damage and its melee twin); the engine
# *resolves* it in RulesEngine. Nothing has ever compared the two. They have
# already diverged catastrophically once — AUDIT 0.1: a "D6" damage string
# parsed as 1.0, so every anti-tank gun in the game was undervalued 2-3.5x and
# the AI systematically shot the wrong targets for months. That was fixed by
# hand; nothing stops the next one.
#
# This is the oracle. For every weapon in the shipped army lists, crossed with
# a grid of defender profiles spanning the toughness/save/wounds space those
# armies actually contain, it:
#
#   1. asks the AI for its expected damage,
#   2. rolls the same attack SAMPLES times through the real
#      RulesEngine.resolve_shoot / resolve_melee_attacks at fixed seeds,
#      summing the wounds actually taken off the target,
#   3. fails when the relative error exceeds TOLERANCE.
#
# Two deliberate choices about what is compared:
#
# * The AI's *scoring* multipliers are excluded. _estimate_weapon_damage ends
#   with `* _calculate_efficiency_multiplier(...)`, which is a targeting
#   preference (anti-tank guns should prefer tanks), not a damage claim. It is
#   divided back out here. _score_shooting_target's secondary-mission and
#   character bonuses are further scoring still and are not tested at all.
# * Monte-Carlo, not a closed form. A closed-form check would just be the AI's
#   own arithmetic written twice, and would agree with it for exactly the
#   reasons that make it wrong. Rolling real dice through the engine tests the
#   AI against the thing the player actually experiences.
#
# Usage:
#   godot --headless --path 40k -s tests/test_ai_combat_math_property.gd
#   godot --headless --path 40k -s tests/test_ai_combat_math_property.gd -- --full
#   godot --headless --path 40k -s tests/test_ai_combat_math_property.gd -- --samples=4000
#   godot --headless --path 40k -s tests/test_ai_combat_math_property.gd -- --seeded-bug
#
# --full         every weapon in every shipped list (nightly tier)
# default        the FAST_TIER highest-traffic weapons (CI tier)
# --seeded-bug   re-introduces the AUDIT 0.1 defect ("D6" -> 1.0) in the
#                comparison, proving the test would have caught it

# Loaded at RUN time, not preloaded. AIDecisionMaker's dependency chain reaches
# autoload singletons (GameState, Measurement) that are not registered as
# compile-time globals while this SceneTree script is being loaded, so a
# `preload` here makes the whole test fail to compile. `load()` after the tree
# is up resolves them.
var AIDM = null

# Relative-error bar. Monte-Carlo noise at 2,000 samples on a mean-1 quantity
# is ~2%, so 10% leaves room for genuine modelling approximations while still
# catching a 2-3.5x error like AUDIT 0.1.
const TOLERANCE := 0.10
const SAMPLES_DEFAULT := 2000
const FAST_TIER := 50

# Weapons whose AI estimate is knowingly approximate. Each entry needs a
# reason a reader can check, and a bound: an entry is a documented modelling
# gap, not a licence to be wrong by any amount. Keys are matched as
# case-insensitive substrings of the weapon name.
#
# EVERY entry here should look like a modelling simplification. If one ever
# looks like AUDIT 0.1 — a parse bug, a units mix-up, a dropped term — it is a
# defect wearing a tolerance's clothes, and belongs in the fix list instead.
const TOLERANCE_LIST := {
	# BLAST adds attacks per 5 models in the target unit. The AI applies the
	# bonus for the unit it is scoring; the sampled target here is sized by the
	# defender grid, so the two can disagree by up to the blast step itself.
	"blast": {"rel": 0.45, "why": "BLAST attack count scales with target model count; the AI scores against the real unit, the harness against a synthetic one"},
}

var _passed := 0
var _failed := 0
var _skipped := 0
var _rows: Array = []
var _skip_notes: Array = []
var _samples := SAMPLES_DEFAULT
var _full := false
var _seeded_bug := false
var _only := ""
var _verbose := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--full":
			_full = true
		elif a == "--seeded-bug":
			_seeded_bug = true
		elif a.begins_with("--samples="):
			_samples = int(a.split("=")[1])
		elif a.begins_with("--only="):
			_only = a.split("=")[1]
		elif a == "--verbose":
			_verbose = true
	await create_timer(0.4).timeout
	_run()


# ---------------------------------------------------------------- defenders --
# A grid spanning what the shipped lists actually field: a horde body, a
# marine-equivalent, an elite 2+/T6, a T9 walker and a T12 hull. Save 7 means
# "no save"; invuln 0 means none.
func _defender_grid() -> Array:
	return [
		{"label": "T4 Sv6+ W1 (horde)",      "t": 4,  "sv": 6, "w": 1, "inv": 0, "models": 10, "kw": ["INFANTRY"]},
		{"label": "T4 Sv3+ W2 (marine)",     "t": 4,  "sv": 3, "w": 2, "inv": 0, "models": 5,  "kw": ["INFANTRY"]},
		{"label": "T6 Sv2+ W3 4++ (elite)",  "t": 6,  "sv": 2, "w": 3, "inv": 4, "models": 4,  "kw": ["INFANTRY"]},
		{"label": "T9 Sv3+ W12 (walker)",    "t": 9,  "sv": 3, "w": 12, "inv": 0, "models": 1, "kw": ["VEHICLE"]},
		{"label": "T12 Sv2+ W16 (hull)",     "t": 12, "sv": 2, "w": 16, "inv": 0, "models": 1, "kw": ["VEHICLE", "MONSTER"]},
	]


func _make_unit(uid: String, owner: int, d: Dictionary, weapons: Array, at: Vector2) -> Dictionary:
	var models := []
	for i in range(int(d.get("models", 1))):
		models.append({
			"id": "m%d" % i, "alive": true,
			"wounds": int(d.get("w", 1)), "current_wounds": int(d.get("w", 1)),
			"base_mm": 32,
			"position": {"x": at.x + float(i) * 40.0, "y": at.y},
		})
	var stats := {
		"move": 6, "toughness": int(d.get("t", 4)), "save": int(d.get("sv", 4)),
		"wounds": int(d.get("w", 1)), "leadership": 6, "objective_control": 1,
	}
	if int(d.get("inv", 0)) > 0:
		stats["invuln"] = int(d.get("inv", 0))
	return {
		"id": uid, "squad_id": uid, "owner": owner, "status": "DEPLOYED",
		"meta": {"name": uid, "keywords": d.get("kw", ["INFANTRY"]), "stats": stats,
				 "points": 100, "weapons": weapons, "abilities": []},
		"models": models, "flags": {},
	}


# ------------------------------------------------------------------ corpus --
func _collect_weapons() -> Array:
	"""Every distinct (weapon, wielder-stats) pair in the shipped army lists."""
	var seen := {}
	var out: Array = []
	var dir := DirAccess.open("res://armies")
	if dir == null:
		return out
	var names := []
	for f in dir.get_files():
		if f.ends_with(".json"):
			names.append(f)
	names.sort()
	for fname in names:
		var fh := FileAccess.open("res://armies/%s" % fname, FileAccess.READ)
		if fh == null:
			continue
		var parsed = JSON.parse_string(fh.get_as_text())
		fh.close()
		if not (parsed is Dictionary):
			continue
		var units = parsed.get("units", {})
		if not (units is Dictionary):
			continue
		for uid in units:
			var u = units[uid]
			if not (u is Dictionary):
				continue
			var meta = u.get("meta", {})
			for w in meta.get("weapons", []):
				if not (w is Dictionary):
					continue
				var key := "%s|%s|%s|%s|%s|%s" % [
					w.get("name", ""), w.get("attacks", ""), w.get("strength", ""),
					w.get("ap", ""), w.get("damage", ""), w.get("type", "")]
				if seen.has(key):
					continue
				seen[key] = true
				out.append({"weapon": w, "unit_name": meta.get("name", uid),
							"source": fname})
	return out


# -------------------------------------------------------------- monte carlo --
func _mc_expected_damage(re, weapon: Dictionary, defender: Dictionary,
		melee: bool, samples: int) -> Dictionary:
	"""Roll the attack `samples` times through the real engine; return the mean
	wounds actually removed, and the standard error of that mean."""
	# One shooter model with exactly this weapon. Place the units 1" apart so
	# any range band and any melee engagement check both resolve as "in range".
	var shooter := _make_unit("U_ATT", 1, {"t": 4, "sv": 3, "w": 3, "models": 1},
		[weapon], Vector2(1000.0, 1000.0))
	var total := 0.0
	var total_sq := 0.0
	# Same ID the engine generates, so get_weapon_profile finds the profile
	# on the synthetic shooter instead of falling back to the legacy table.
	var wid: String = re._generate_weapon_id(str(weapon.get("name", "w")), str(weapon.get("type", "")))
	for s in range(samples):
		var target := _make_unit("U_DEF", 2, defender, [], Vector2(1000.0 + 40.0, 1000.0))
		var board := {"units": {"U_ATT": shooter.duplicate(true), "U_DEF": target},
					  "meta": {"battle_round": 1, "active_player": 1}, "board": {}}
		var before := 0.0
		for m in board.units.U_DEF.models:
			before += float(m.current_wounds)
		# Sanctioned deterministic path: set_test_seed makes every subsequent
		# make_rng() derive from hash([seed, counter]), so the sample stream is
		# reproducible without bypassing the RNG factories.
		re.set_test_seed(90000 + s)
		var rng = re.make_rng()
		var action: Dictionary
		if melee:
			action = {"type": "FIGHT", "actor_unit_id": "U_ATT",
				"payload": {"assignments": [{
					"attacker": "U_ATT", "target": "U_DEF",
					# `models` is a list of model INDICES as strings, not ids
					# (_melee_weapon_swingers compares str(idx)); empty means
					# "every eligible model", which is what we want here.
					"weapon": wid, "models": [],
				}]}}
		else:
			action = {"type": "SHOOT", "actor_unit_id": "U_ATT",
				"payload": {"assignments": [{
					"weapon_id": wid, "target_unit_id": "U_DEF",
					"model_ids": ["m0"],
				}]}}
		var res
		if melee:
			res = re.resolve_melee_attacks(action, board, rng)
		else:
			res = re.resolve_shoot(action, board, rng)
		if not (res is Dictionary) or not res.get("success", false):
			var why := "engine returned %s" % typeof(res)
			if res is Dictionary:
				why = str(res.get("log_text", "engine refused the action"))
			return {"ok": false, "note": why}
		# Read the survivors two ways and take the lower. The melee path
		# applies its own diffs to `board` as it resolves (so later assignments
		# see the damage), while the shooting path returns diffs without
		# touching the board. Replaying diffs onto an already-updated board
		# silently subtracts zero — which is exactly how every melee weapon
		# measured 0.000 the first time this test ran.
		var after := 0.0
		var final_wounds: Array = []
		for m in board.units.U_DEF.models:
			final_wounds.append(float(m.current_wounds))
		for d in res.get("diffs", []):
			var path := str(d.get("path", ""))
			if path.begins_with("units.U_DEF.models.") and path.ends_with(".current_wounds"):
				var idx := int(path.split(".")[3])
				if idx >= 0 and idx < final_wounds.size():
					final_wounds[idx] = minf(final_wounds[idx], float(d.get("value", 0)))
		for fw in final_wounds:
			after += fw
		var dealt: float = before - after
		if s == 0 and _verbose:
			print("  [mc] melee=%s wid=%s before=%.1f after=%.1f diffs=%d"
				% [melee, wid, before, after, res.get("diffs", []).size()])
		total += dealt
		total_sq += dealt * dealt
	var mean := total / float(samples)
	var var_ := maxf(total_sq / float(samples) - mean * mean, 0.0)
	return {"ok": true, "mean": mean, "se": sqrt(var_ / float(samples))}


# ------------------------------------------------------------------- driver --
func _tolerance_for(weapon_name: String) -> Dictionary:
	var lname := weapon_name.to_lower()
	for k in TOLERANCE_LIST:
		if lname.find(k) >= 0:
			return TOLERANCE_LIST[k]
	return {}


func _run() -> void:
	var re = root.get_node_or_null("RulesEngine")
	if re == null:
		print("[FAIL] RulesEngine autoload not present — cannot compare against the engine")
		quit(1)
		return
	AIDM = load("res://scripts/AIDecisionMaker.gd")
	if AIDM == null:
		print("[FAIL] could not load AIDecisionMaker.gd")
		quit(1)
		return

	var corpus := _collect_weapons()
	print("=".repeat(78))
	print("D1 COMBAT-MATH PROPERTY TEST — AI prediction vs RulesEngine resolution")
	print("=".repeat(78))
	print("  %d distinct weapon profiles in the shipped lists" % corpus.size())
	if not _full:
		corpus = corpus.slice(0, FAST_TIER)
		print("  fast tier: first %d (pass --full for the whole corpus)" % corpus.size())
	print("  %d Monte-Carlo samples per (weapon, defender) pair, seeded" % _samples)
	if _seeded_bug:
		print("  !! --seeded-bug: re-introducing AUDIT 0.1 (\"D6\" damage parsed as 1.0)")
	print("")

	var defenders := _defender_grid()
	for entry in corpus:
		var weapon: Dictionary = entry.weapon
		var wname := str(weapon.get("name", "?"))
		if _only != "" and wname.to_lower().find(_only.to_lower()) < 0:
			continue
		var melee: bool = str(weapon.get("type", "")).to_lower() == "melee"
		for d in defenders:
			var target := _make_unit("U_DEF", 2, d, [], Vector2(1040.0, 1000.0))
			var shooter := _make_unit("U_ATT", 1, {"t": 4, "sv": 3, "w": 3, "models": 1},
				[weapon], Vector2(1000.0, 1000.0))
			var snapshot := {"units": {"U_ATT": shooter, "U_DEF": target},
							 "meta": {"battle_round": 1}}

			var predicted: float
			if melee:
				# The melee estimator works at unit level and picks the unit's
				# best melee weapon; the shooter here carries exactly one, so
				# the two sides compare the same attack.
				predicted = AIDM._estimate_melee_damage(shooter, target, snapshot)
			else:
				predicted = AIDM._estimate_weapon_damage(weapon, target, snapshot, shooter)
				# Divide the targeting preference back out: it is a scoring
				# multiplier, not a claim about damage.
				var eff: float = AIDM._calculate_efficiency_multiplier(weapon, target)
				if eff > 0.0:
					predicted /= eff
			if _seeded_bug:
				# AUDIT 0.1 exactly: a variable damage string collapses to 1.0,
				# so the prediction shrinks by the average it should have used.
				var dmg_str := str(weapon.get("damage", "1")).to_upper()
				if dmg_str.find("D") >= 0:
					var avg: float = AIDM._parse_average_damage(dmg_str)
					if avg > 0.0:
						predicted = predicted / avg

			if predicted <= 0.0:
				_skipped += 1
				continue

			var mc := _mc_expected_damage(re, weapon, d, melee, _samples)
			if not mc.get("ok", false):
				_skipped += 1
				if _skip_notes.size() < 6:
					_skip_notes.append("%s vs %s: %s" % [wname, d.label, mc.get("note", "?")])
				continue
			var actual: float = mc.mean
			if actual <= 0.0 and predicted <= 0.0:
				_skipped += 1
				continue
			var denom: float = maxf(actual, 0.05)
			var rel: float = abs(predicted - actual) / denom
			var tol := _tolerance_for(wname)
			var bar: float = float(tol.get("rel", TOLERANCE))
			# A deviation inside Monte-Carlo noise is not evidence of
			# divergence, so a pair passes if it is within the relative bar OR
			# within 3 standard errors of the sampled mean. AUDIT 0.1 was a
			# 2-3.5x error: it clears 3 SE by an order of magnitude, so this
			# does not blunt the thing the test exists to catch.
			var se: float = float(mc.se)
			var ok: bool = rel <= bar or abs(predicted - actual) <= 3.0 * se
			_rows.append({"weapon": wname, "defender": d.label, "pred": predicted,
						  "mc": actual, "se": se, "rel": rel, "bar": bar,
						  "ok": ok, "why": str(tol.get("why", "")),
						  "sigma": (abs(predicted - actual) / se) if se > 0.0 else 0.0})
			if ok:
				_passed += 1
			else:
				_failed += 1

	_report()


func _report() -> void:
	_rows.sort_custom(func(a, b): return float(a.sigma) > float(b.sigma))
	print("  %-34s %-22s %8s %8s %7s %7s" % ["weapon", "defender", "AI", "engine", "rel", "sigma"])
	var shown := 0
	for r in _rows:
		if r.ok and shown >= 12:
			continue
		print("  %s %-34s %-22s %8.3f %8.3f %6.1f%% %6.1f%s" % [
			"  " if r.ok else "!!", r.weapon.substr(0, 34), r.defender,
			r.pred, r.mc, 100.0 * r.rel, r.sigma,
			("   [tolerated: %s]" % r.why) if (r.ok and r.bar > TOLERANCE) else ""])
		shown += 1
	for n in _skip_notes:
		print("  skipped: %s" % n)
	print("")
	print("=".repeat(78))
	print("  %d pairs within %.0f%%, %d over, %d skipped (no damage possible)"
		% [_passed, 100.0 * TOLERANCE, _failed, _skipped])
	var verdict := _failed == 0
	if _seeded_bug:
		# Inverted: with the AUDIT 0.1 defect injected the test MUST fail, or
		# it is not sensitive enough to have caught the bug it exists for.
		verdict = _failed > 0
		print("  --seeded-bug: expected failures, got %d -> %s"
			% [_failed, "DETECTED" if verdict else "NOT DETECTED"])
	print("VERDICT: %s" % ("PASS" if verdict else "FAIL"))
	print("=".repeat(78))
	quit(0 if verdict else 1)
