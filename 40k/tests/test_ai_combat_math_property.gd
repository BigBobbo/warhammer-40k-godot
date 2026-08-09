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
	# TORRENT weapons auto-hit, and their attack count is rolled (D6). The AI
	# scores the average; a sampled mean over a rolled-attacks weapon converges
	# more slowly than a fixed one, so this needs a wider band, not a different
	# answer.
	"torrent": {"rel": 0.20, "why": "rolled attack count (D6) plus auto-hit — sampled mean converges slowly"},
}

# Divergences that are REAL and REPRODUCED live in a committed catalogue,
# `tests/ai_combat_math_known_divergences.json`, not in this file. Each entry
# records the weapon, the defender, and the RATIO of predicted to resolved
# damage measured when it was catalogued, plus a `why` that is honest about
# whether the cause is known.
#
# Listing a pair there is not a claim that it is acceptable. It is a claim that
# it is known, measured, and owned by a named follow-up task — and it is a
# ratchet: a catalogued pair fails the moment it drifts further from the engine
# than the ratio recorded for it, and a pair that is NOT catalogued must simply
# agree. Regenerate with --write-catalogue after a deliberate change, and read
# the diff.
const CATALOGUE_PATH := "res://tests/ai_combat_math_known_divergences.json"
const DRIFT_ALLOWANCE := 0.15

var _passed := 0
var _failed := 0
var _skipped := 0
var _rows: Array = []
var _skip_notes: Array = []
var _drifted: Array = []
var _catalogue: Dictionary = {}
var _write_catalogue := false
var _new_catalogue: Dictionary = {}
var _known := 0
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
		elif a == "--write-catalogue":
			_write_catalogue = true
	await create_timer(0.4).timeout
	_run()


# ---------------------------------------------------------------- defenders --
# A grid spanning the toughness/save/wounds space the shipped lists actually
# field: a horde body, a marine-equivalent, an elite 2+/T6, a T9 walker and a
# T12 hull. Save 7 means "no save"; invuln 0 means none.
#
# Every defender is ONE model, and the comparison clips the AI's prediction at
# that model's wound pool. Both halves of that are load-bearing, and both were
# learned the hard way:
#
# * One model, because with several the diff stream stops being a usable
#   ruler. A multi-casualty volley through resolve_shoot emits a
#   `models.0.current_wounds` / `models.0.alive` pair PER CASUALTY — every one
#   naming index 0 — and the board handed to it is not updated, so applying the
#   stream (even with the engine's own _apply_diff_to_board) can only ever kill
#   one model. Measured: a 30-model 1-wound target reported exactly 0.999
#   damage for every weapon tested, which is the ceiling, not the answer. That
#   asymmetry with the melee path (which does mutate in place, and reports
#   distinct indices) is recorded in the task notes as an open question about
#   the auto-resolve path; it is NOT diagnosed here and nothing below assumes
#   an answer to it.
# * Every model carries 10+ wounds, so a volley never saturates it. A 1-wound
#   model caps the engine at 1.0 however much is shot at it, and clipping the
#   AI's prediction at that ceiling does not fix the comparison either, because
#   E[min(X, W)] is not min(E[X], W) — the clipped version still reported a
#   40% "divergence" on weapons whose arithmetic is exactly right. Fat targets
#   remove the ceiling from the comparison entirely.
#
# What this grid does NOT cover, and does not pretend to: multi-model
# allocation (spill-over, BLAST scaling) and the per-model wound-overflow cap.
# The cap fix that came out of this test was verified separately against a
# 30-model target before the grid was narrowed (Big choppa: 3.472 predicted vs
# 3.554 resolved, 2.3%).
func _defender_grid() -> Array:
	return [
		{"label": "T4 Sv6+ W10 (soft)",      "t": 4,  "sv": 6, "w": 10, "inv": 0, "models": 1, "kw": ["INFANTRY"]},
		{"label": "T4 Sv3+ W10 (armoured)",  "t": 4,  "sv": 3, "w": 10, "inv": 0, "models": 1, "kw": ["INFANTRY"]},
		{"label": "T6 Sv2+ W10 4++ (elite)", "t": 6,  "sv": 2, "w": 10, "inv": 4, "models": 1, "kw": ["INFANTRY"]},
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
		# Apply the engine's diffs with the engine's own applier, then read the
		# survivors off the board. The melee path already applied them in
		# place, so re-applying a `set` is a no-op there.
		for d in res.get("diffs", []):
			re._apply_diff_to_board(board, d)
		var after := 0.0
		for m in board.units.U_DEF.models:
			if m.get("alive", true):
				after += float(m.current_wounds)
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
func _tolerance_for(weapon_name: String, special: String) -> Dictionary:
	var hay := (weapon_name + " " + special).to_lower()
	for k in TOLERANCE_LIST:
		if hay.find(k) >= 0:
			return TOLERANCE_LIST[k]
	return {}


func _load_catalogue() -> Dictionary:
	var fh := FileAccess.open(CATALOGUE_PATH, FileAccess.READ)
	if fh == null:
		return {}
	var parsed = JSON.parse_string(fh.get_as_text())
	fh.close()
	if not (parsed is Dictionary):
		return {}
	return parsed.get("divergences", {})


func _known_divergence(weapon_name: String, defender_label: String) -> Dictionary:
	var key := "%s|%s" % [weapon_name, defender_label]
	if _catalogue.has(key):
		return _catalogue[key]
	return {}


func _run() -> void:
	var re = root.get_node_or_null("RulesEngine")
	if re == null:
		print("[FAIL] RulesEngine autoload not present — cannot compare against the engine")
		quit(1)
		return
	_catalogue = _load_catalogue()
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
			var tol := _tolerance_for(wname, str(weapon.get("special_rules", "")))
			var bar: float = float(tol.get("rel", TOLERANCE))
			# A deviation inside Monte-Carlo noise is not evidence of
			# divergence, so a pair passes if it is within the relative bar OR
			# within 3 standard errors of the sampled mean. AUDIT 0.1 was a
			# 2-3.5x error: it clears 3 SE by an order of magnitude, so this
			# does not blunt the thing the test exists to catch.
			var se: float = float(mc.se)
			var ok: bool = rel <= bar or abs(predicted - actual) <= 3.0 * se
			# A known, owned divergence does not fail the build, but it is a
			# ratchet: it may not drift further from the engine than the ratio
			# recorded when it was catalogued.
			var ratio: float = (predicted / actual) if actual > 0.0 else INF
			var known := _known_divergence(wname, str(d.label))
			var known_hit := false
			if not ok and _write_catalogue:
				_new_catalogue["%s|%s" % [wname, d.label]] = {
					"ratio": snappedf(ratio, 0.01),
					"predicted": snappedf(predicted, 0.001),
					"resolved": snappedf(actual, 0.001),
					"why": str(known.get("why", "not yet diagnosed — owned by task D1b")),
				}
				ok = true
				known_hit = true
			elif not ok and not known.is_empty():
				var recorded: float = float(known.get("ratio", 1.0))
				var within: bool = (ratio <= recorded * (1.0 + DRIFT_ALLOWANCE)) if recorded >= 1.0 \
					else (ratio >= recorded * (1.0 - DRIFT_ALLOWANCE))
				if within:
					ok = true
					known_hit = true
				else:
					_drifted.append("%s vs %s: ratio %.2f worse than the catalogued %.2f (%s)"
						% [wname, d.label, ratio, recorded, known.get("why", "")])
			_rows.append({"weapon": wname, "defender": d.label, "pred": predicted,
						  "mc": actual, "se": se, "rel": rel, "bar": bar,
						  "ok": ok, "known": known_hit,
						  "why": str(known.get("why", tol.get("why", ""))),
						  "sigma": (abs(predicted - actual) / se) if se > 0.0 else 0.0})
			if known_hit:
				_known += 1
			elif ok:
				_passed += 1
			else:
				_failed += 1

	_report()


func _report() -> void:
	_rows.sort_custom(func(a, b): return float(a.sigma) > float(b.sigma))
	print("  %-34s %-22s %8s %8s %7s %7s" % ["weapon", "defender", "AI", "engine", "rel", "sigma"])
	var shown := 0
	for r in _rows:
		if r.ok and not r.known and shown >= 10:
			continue
		print("  %s %-34s %-22s %8.3f %8.3f %6.1f%% %6.1f%s" % [
			("~~" if r.known else ("  " if r.ok else "!!")), r.weapon.substr(0, 34), r.defender,
			r.pred, r.mc, 100.0 * r.rel, r.sigma,
			("   [%s]" % r.why) if r.why != "" else ""])
		shown += 1
	for n in _skip_notes:
		print("  skipped: %s" % n)
	print("")
	print("=".repeat(78))
	for msg in _drifted:
		print("  DRIFT: %s" % msg)
	print("  %d pairs agree within %.0f%%, %d known+owned divergences (~~), %d NEW failures, %d skipped"
		% [_passed, 100.0 * TOLERANCE, _known, _failed, _skipped])
	if _write_catalogue:
		var fh := FileAccess.open("user://ai_combat_math_known_divergences.json", FileAccess.WRITE)
		fh.store_string(JSON.stringify({
			"note": "Generated by tests/test_ai_combat_math_property.gd --write-catalogue. Each entry is a REPRODUCED divergence between the AI's expected-damage arithmetic and RulesEngine resolution, with the ratio measured when it was catalogued. This file is a ratchet, not an excuse: an uncatalogued pair must agree, and a catalogued pair must not drift further.",
			"generated": "2026-08-07", "samples": _samples,
			"divergences": _new_catalogue}, "  "))
		fh.close()
		print("  catalogue written to user://ai_combat_math_known_divergences.json (%d entries)"
			% _new_catalogue.size())
	var verdict := _failed == 0 and _drifted.is_empty()
	if _seeded_bug:
		# Inverted: with the AUDIT 0.1 defect injected the test MUST fail, or
		# it is not sensitive enough to have caught the bug it exists for.
		verdict = _failed > 0
		print("  --seeded-bug: expected failures, got %d -> %s"
			% [_failed, "DETECTED" if verdict else "NOT DETECTED"])
	print("VERDICT: %s" % ("PASS" if verdict else "FAIL"))
	print("=".repeat(78))
	quit(0 if verdict else 1)
