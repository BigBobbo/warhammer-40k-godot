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
# a grid of defender profiles spanning the toughness/save/keyword space those
# armies actually contain, it:
#
#   1. asks the AI for its expected damage,
#   2. rolls the same attack SAMPLES times through the real
#      RulesEngine.resolve_shoot / resolve_melee_attacks at fixed seeds,
#      summing the wounds actually taken off the target,
#   3. fails when the relative error exceeds TOLERANCE.
#
# It runs at the harness's default rules edition (11e — SettingsService pins
# automated runs to 11 unless WH40K_TEST_EDITION=10 opts into legacy), and the
# known-divergence catalogue is stamped with the edition it was measured at: a
# run at any other edition fails rather than comparing against ratios that
# were measured under different rules.
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
# And one deliberate choice about WHERE the duel happens: on open ground, with
# both sides shown the same (empty) terrain, unengaged for ranged attacks.
# The 11e engine reads cover (13.08) per attack from the live TerrainManager
# singleton, not from the board it is handed, so a duel set up inside the boot
# layout's ruins silently worsens every engine attack by 1 BS while the AI —
# handed no terrain — models none; and a ranged duel set up with bases touching
# is ENGAGED, so the engine applies 17.03's -1 to hit against MONSTER/VEHICLE
# targets (and the AI's RAPID FIRE/MELTA half-range check reads 0" as
# "unknown"). Both were measured: together they produced every one of the 61
# "new failures" the first 11e run of this test reported. They are harness
# artifacts, not AI arithmetic, so the harness now neutralises terrain for the
# run and asserts, for every ranged pair, that the defender is in no terrain
# area, that neither the engine nor the AI grants it cover, and that the units
# are not engaged — loudly failing the run if any of that ever stops holding.
# Cover and engaged-target shooting are real AI gaps in their own right —
# AIDecisionMaker._target_has_benefit_of_cover is still the 10e-shaped
# majority-of-models predicate rather than 13.08's every-model test, and the
# estimator has no 17.03 term — but they belong in deliberately labelled
# cases once the estimator models them, not in an accident of where the boot
# layout puts its ruins.
#
# Usage:
#   godot --headless --path 40k -s tests/test_ai_combat_math_property.gd
#   godot --headless --path 40k -s tests/test_ai_combat_math_property.gd -- --full
#   godot --headless --path 40k -s tests/test_ai_combat_math_property.gd -- --samples=4000
#   godot --headless --path 40k -s tests/test_ai_combat_math_property.gd -- --seeded-bug
#   godot --headless --path 40k -s tests/test_ai_combat_math_property.gd -- --write-catalogue
#
# --full             every weapon in every shipped list (nightly tier)
# default            the FAST_TIER first weapon profiles (CI tier)
# --seeded-bug       re-introduces the AUDIT 0.1 defect ("D6" -> 1.0) in the
#                    comparison, proving the test would have caught it. Only
#                    the pairs the seed actually changes are rolled, and each
#                    is judged twice against the SAME Monte-Carlo samples —
#                    once with the clean prediction, once with the seeded one —
#                    so detection is measured against the unseeded baseline and
#                    cannot pass just because the baseline is already red.
# --write-catalogue  writes every pair that does not agree to
#                    user://ai_combat_math_known_divergences.json, stamped with
#                    the edition/samples/tier, for a deliberate regeneration.
#                    Copy it over tests/ai_combat_math_known_divergences.json
#                    and give EVERY entry its isolated cause before committing.
# --only=<substr>    restrict to weapons whose name contains <substr>
# --verbose          per-pair Monte-Carlo trace

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

# Duel geometry. Positions are board pixels (Measurement.PX_PER_INCH = 40).
# Ranged duels sit 4" centre-to-centre: with 32mm bases that is a 2.74" gap,
# beyond the 2" (11e) / 1" (10e) engagement range and inside half range of
# every ranged weapon in the shipped lists (the shortest is 6"), so RAPID FIRE
# and MELTA always apply on both sides. Melee duels stay 1" apart (bases
# touching), which is engaged and within any reach.
const PX_PER_INCH := 40.0
const ATTACKER_POS := Vector2(1000.0, 1000.0)
const RANGED_SEPARATION_IN := 4.0
const MELEE_SEPARATION_IN := 1.0
const BASE_MM := 32

# Every defender is ONE model with enough wounds that no volley in the shipped
# lists can destroy it (the largest maximum volley is Deffkannon's 3D6 x D6 =
# 108). See _defender_grid for why; _mc_expected_damage fails the run loudly if
# any sample ever destroys the defender, so this number cannot silently go
# stale when a bigger gun is added.
const DEFENDER_WOUNDS := 120

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
# records the weapon PROFILE, the defender, and the RATIO of predicted to
# resolved damage measured when it was catalogued, plus a `why` naming the
# isolated cause.
#
# Listing a pair there is not a claim that it is acceptable. It is a claim that
# it is known, measured, and owned by a named follow-up task — and it is a
# ratchet: a catalogued pair fails the moment its error flips to the other
# side of 1.0, or drifts further from the engine than the ratio recorded for
# it (measured symmetrically in log space, so a 2x over-prediction and a 2x
# under-prediction are held to the same bar), and a pair that is NOT
# catalogued must simply agree. Regenerate with --write-catalogue after a
# deliberate change, and read the diff.
const CATALOGUE_PATH := "res://tests/ai_combat_math_known_divergences.json"
const DRIFT_ALLOWANCE := 0.15

var _passed := 0
var _failed := 0
var _skipped := 0
var _rows: Array = []
var _skip_notes: Array = []
var _drifted: Array = []
var _harness_errors: Array = []
var _retired: Array = []
var _catalogue: Dictionary = {}
var _catalogue_meta: Dictionary = {}
var _exercised_keys: Dictionary = {}
var _write_catalogue := false
var _new_catalogue: Dictionary = {}
var _known := 0
var _samples := SAMPLES_DEFAULT
var _full := false
var _seeded_bug := false
var _only := ""
var _verbose := false
# --seeded-bug sensitivity bookkeeping (see _run)
var _seed_unaffected := 0
var _seed_caught: Array = []
var _seed_missed: Array = []
var _seed_absorbed: Array = []
var _seed_unmeasurable: Array = []
var _seed_weapons: Dictionary = {}
# Terrain neutralised for the run, restored before quit.
var _saved_terrain = null
var _tm = null
var _measurement = null


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
# A grid spanning the toughness/save/keyword space the shipped lists actually
# field: a horde body, a marine-equivalent, an elite 2+/T6, a T9 walker and a
# T12 hull. Save 7 means "no save"; invuln 0 means none.
#
# Every defender is ONE model with DEFENDER_WOUNDS wounds. Both halves of that
# are load-bearing, and both were learned the hard way:
#
# * One model, because with several the diff stream stopped being a usable
#   ruler: a 30-model 1-wound target reported exactly 0.999 damage for every
#   weapon tested. That was later diagnosed as a 10e-only engine bug — the
#   legacy auto-resolve save loop reads current_wounds from the unmutated board
#   and never writes the result back, so repeated failed saves overwrite each
#   other (RulesEngine's 10e regular-save loop; the 11e 05.03/05.04 allocation
#   path counts correctly). Multi-model allocation is still not covered here.
# * No volley can destroy the model. The engine caps a whole volley at the
#   target's wound pool; the AI caps only per-attack damage, and
#   E[min(X, W)] is not min(E[X], W). The first grid used W10-W16 single
#   models, and a handful of high-output weapons (Twin arachnus, Twin
#   iliastus, Watcher's Axe) saturated them — which both manufactured
#   divergences and MASKED others (Twin arachnus vs the W12 walker read "ok"
#   only because saturation cancelled the missing TWIN-LINKED re-roll). A
#   DEFENDER_WOUNDS model removes the ceiling from the comparison entirely, and
#   the per-sample destroyed-defender check proves it stays removed.
#
# What this grid does NOT cover, and does not pretend to: multi-model
# allocation (spill-over, BLAST scaling) and the per-model wound-overflow cap.
# The cap fix that came out of this test was verified separately against a
# 30-model target before the grid was narrowed (Big choppa: 3.472 predicted vs
# 3.554 resolved, 2.3%).
func _defender_grid() -> Array:
	var w := DEFENDER_WOUNDS
	return [
		{"label": "T4 Sv6+ W%d (soft)" % w,      "t": 4,  "sv": 6, "w": w, "inv": 0, "models": 1, "kw": ["INFANTRY"]},
		{"label": "T4 Sv3+ W%d (armoured)" % w,  "t": 4,  "sv": 3, "w": w, "inv": 0, "models": 1, "kw": ["INFANTRY"]},
		{"label": "T6 Sv2+ W%d 4++ (elite)" % w, "t": 6,  "sv": 2, "w": w, "inv": 4, "models": 1, "kw": ["INFANTRY"]},
		{"label": "T9 Sv3+ W%d (walker)" % w,    "t": 9,  "sv": 3, "w": w, "inv": 0, "models": 1, "kw": ["VEHICLE"]},
		{"label": "T12 Sv2+ W%d (hull)" % w,     "t": 12, "sv": 2, "w": w, "inv": 0, "models": 1, "kw": ["VEHICLE", "MONSTER"]},
	]


func _make_unit(uid: String, owner: int, d: Dictionary, weapons: Array, at: Vector2) -> Dictionary:
	var models := []
	for i in range(int(d.get("models", 1))):
		models.append({
			"id": "m%d" % i, "alive": true,
			"wounds": int(d.get("w", 1)), "current_wounds": int(d.get("w", 1)),
			"base_mm": BASE_MM,
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


func _is_melee(weapon: Dictionary) -> bool:
	return str(weapon.get("type", "")).to_lower() == "melee"


func _defender_pos(melee: bool) -> Vector2:
	var sep_in: float = MELEE_SEPARATION_IN if melee else RANGED_SEPARATION_IN
	return ATTACKER_POS + Vector2(sep_in * PX_PER_INCH, 0.0)


# ------------------------------------------------------------------ corpus --
# A weapon PROFILE is everything that changes how the attack resolves: name,
# range, A, BS/WS, S, AP, D and its special rules. Two profiles that share a
# name (the 11e codex Slugga with CLOSE QUARTERS + LETHAL HITS vs the legacy
# BS4 pistol, a BS5 Big shoota vs a BS4 one) are different weapons, and both
# are tested. The signature is also the catalogue key, so it has to be
# readable — `_collect_weapons` fails the run if two kept profiles ever
# collapse onto one signature.
func _profile_signature(w: Dictionary) -> String:
	var melee := _is_melee(w)
	var skill_key := "weapon_skill" if melee else "ballistic_skill"
	var skill := str(w.get(skill_key, ""))
	var skill_txt := ("%s%s+" % ["WS" if melee else "BS", skill]) if skill.is_valid_int() \
		else ("%s%s" % ["WS" if melee else "BS", skill])
	var rng := "Melee" if melee else ("%s\"" % str(w.get("range", "?")))
	var rules := str(w.get("special_rules", "")).strip_edges().to_lower()
	var sig := "%s A%s %s S%s AP%s D%s" % [rng, _sig_value(w.get("attacks", "")), skill_txt,
		_sig_value(w.get("strength", "")), str(w.get("ap", "")), _sig_value(w.get("damage", ""))]
	if rules != "" and rules != "<null>":
		sig += "; " + rules
	return "%s [%s]" % [str(w.get("name", "?")), sig]


func _sig_value(v) -> String:
	# Dice-valued characteristics read as A(D6+3) / S(D6+6) / D(D6), not "AD6+3".
	var t := str(v)
	return t if t.is_valid_int() else "(%s)" % t


func _collect_weapons() -> Array:
	"""Every distinct weapon profile in the shipped army lists."""
	var seen := {}
	var sigs := {}
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
				# Dedupe on the WHOLE profile (sorted-key JSON), not on a
				# hand-picked subset: the old name|A|S|AP|D|type key silently
				# dropped 10 profiles that differ only in BS/WS or rules.
				var key := JSON.stringify(w, "", true)
				if seen.has(key):
					continue
				seen[key] = true
				var sig := _profile_signature(w)
				if sigs.has(sig):
					_harness_errors.append("two distinct profiles share the catalogue signature '%s' (%s and %s) — extend _profile_signature"
						% [sig, sigs[sig], fname])
					continue
				sigs[sig] = fname
				out.append({"weapon": w, "unit_name": meta.get("name", uid),
							"source": fname, "sig": sig})
	return out


# ----------------------------------------------------------- duel invariants --
func _ranged_duel_problems(re, weapon: Dictionary, shooter: Dictionary, target: Dictionary,
		snapshot: Dictionary) -> Array:
	"""Everything that would make a ranged pair measure something other than
	the AI's arithmetic. Empty means the duel is clean."""
	var problems: Array = []
	var att_model: Dictionary = shooter.models[0]
	for m in target.models:
		var p := Vector2(float(m.position.x), float(m.position.y))
		if _tm != null:
			var piece: Dictionary = _tm.area_at(p)
			if not piece.is_empty():
				problems.append("defender model %s is inside terrain area '%s'" % [m.id, str(piece.get("id", "?"))])
	if _tm != null:
		var ap := Vector2(float(att_model.position.x), float(att_model.position.y))
		var apiece: Dictionary = _tm.area_at(ap)
		if not apiece.is_empty():
			problems.append("attacker is inside terrain area '%s'" % str(apiece.get("id", "?")))
		if _tm.unit_has_cover_11e(target, att_model):
			problems.append("engine grants the defender 13.08 cover (TerrainManager.unit_has_cover_11e)")
	if AIDM._target_has_benefit_of_cover(target, shooter, snapshot):
		problems.append("AI grants the defender cover (_target_has_benefit_of_cover)")
	if re.is_unit_engaged("U_DEF", snapshot) or re.is_unit_engaged("U_ATT", snapshot):
		problems.append("attacker and defender are engaged (17.03 / close-quarters shooting would apply)")
	if _measurement != null:
		var edge_in: float = _measurement.model_to_model_distance_inches(att_model, target.models[0])
		var range_in: float = str(weapon.get("range", "0")).to_float()
		if range_in > 0.0 and edge_in > range_in / 2.0:
			problems.append("defender is %.2f\" away, outside half range of a %.0f\" weapon (RAPID FIRE/MELTA would not apply)"
				% [edge_in, range_in])
	return problems


# -------------------------------------------------------------- monte carlo --
func _mc_expected_damage(re, weapon: Dictionary, defender: Dictionary,
		melee: bool, samples: int, terrain: Array) -> Dictionary:
	"""Roll the attack `samples` times through the real engine; return the mean
	wounds actually removed, and the standard error of that mean."""
	# One shooter model with exactly this weapon, placed per _defender_pos:
	# ranged unengaged and inside half range, melee in base contact.
	var shooter := _make_unit("U_ATT", 1, {"t": 4, "sv": 3, "w": 3, "models": 1},
		[weapon], ATTACKER_POS)
	var total := 0.0
	var total_sq := 0.0
	# Same ID the engine generates, so get_weapon_profile finds the profile
	# on the synthetic shooter instead of falling back to the legacy table.
	var wid: String = re._generate_weapon_id(str(weapon.get("name", "w")), str(weapon.get("type", "")))
	for s in range(samples):
		var target := _make_unit("U_DEF", 2, defender, [], _defender_pos(melee))
		# The board carries the same terrain the AI snapshot was given (the
		# 10e cover path reads board.terrain_features; the 11e path reads the
		# TerrainManager singleton, which _run has neutralised to match).
		var board := {"units": {"U_ATT": shooter.duplicate(true), "U_DEF": target},
					  "meta": {"battle_round": 1, "active_player": 1},
					  "board": {"terrain_features": terrain}}
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
			else:
				# Saturation guard: a destroyed defender means the engine
				# capped this volley at the wound pool and the comparison is
				# measuring the cap, not the arithmetic.
				return {"ok": false, "harness": true,
						"note": "sample %d destroyed the defender (%.0f wounds) — the comparison is saturated; raise DEFENDER_WOUNDS"
							% [s, before]}
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
	_catalogue_meta = parsed
	return parsed.get("divergences", {})


func _catalogue_key(sig: String, defender_label: String) -> String:
	return "%s|%s" % [sig, defender_label]


# The ratchet. A catalogued pair keeps passing only while its error stays on
# the SAME side of 1.0 as when it was catalogued and is no larger, in log
# space, than the recorded error plus DRIFT_ALLOWANCE. Log space makes the bar
# symmetric: recorded 2.0 (2x over) tolerates up to 2.3, recorded 0.5 (2x
# under) tolerates down to 0.435. The old one-sided check (`ratio <= recorded`
# for over-predictions) waved through any under-prediction at all — including
# the seeded AUDIT 0.1 defect at ratios of 0.12-0.28.
func _ratchet_holds(ratio: float, recorded: float) -> bool:
	if ratio <= 0.0 or recorded <= 0.0 or is_inf(ratio) or is_inf(recorded) \
			or is_nan(ratio) or is_nan(recorded):
		return false
	var lr := log(ratio)
	var lrec := log(recorded)
	if signf(lr) != signf(lrec):
		return false
	return absf(lr) <= absf(lrec) + log(1.0 + DRIFT_ALLOWANCE)


func _judge(predicted: float, actual: float, se: float, bar: float, known: Dictionary) -> Dictionary:
	"""Verdict for one prediction against one Monte-Carlo result. `green` is the
	pass/fail; `agree` means it passed outright (no catalogue needed)."""
	var denom: float = maxf(actual, 0.05)
	var rel: float = abs(predicted - actual) / denom
	# A deviation inside Monte-Carlo noise is not evidence of divergence, so a
	# pair passes if it is within the relative bar OR within 3 standard errors
	# of the sampled mean. AUDIT 0.1 was a 2-3.5x error: it clears 3 SE by an
	# order of magnitude, so this does not blunt the thing the test exists to
	# catch.
	var agree: bool = rel <= bar or abs(predicted - actual) <= 3.0 * se
	var ratio: float = (predicted / actual) if actual > 0.0 else INF
	var out := {"rel": rel, "ratio": ratio, "agree": agree, "known": false,
				"green": agree, "drift": ""}
	if agree or known.is_empty():
		return out
	# A known, owned divergence does not fail the build, but it is a ratchet.
	var recorded: float = float(known.get("ratio", 1.0))
	if _ratchet_holds(ratio, recorded):
		out.known = true
		out.green = true
	else:
		var how := "flipped to the other side of 1.0 from" if signf(log(maxf(ratio, 1e-9))) != signf(log(maxf(recorded, 1e-9))) \
			else "drifted further from the engine than"
		out.drift = "ratio %.2f %s the catalogued %.2f" % [ratio, how, recorded]
	return out


func _seeded_prediction(weapon: Dictionary, predicted: float) -> float:
	# AUDIT 0.1 exactly: a variable damage string collapses to 1.0, so the
	# prediction shrinks by the average it should have used.
	var dmg_str := str(weapon.get("damage", "1")).to_upper()
	if dmg_str.find("D") >= 0:
		var avg: float = AIDM._parse_average_damage(dmg_str)
		if avg > 0.0:
			return predicted / avg
	return predicted


func _neutralise_terrain() -> Array:
	"""Clear the live TerrainManager layout for the run (restored in _finish).
	Returns the terrain both sides are shown — empty, the same array object."""
	_tm = root.get_node_or_null("TerrainManager")
	if _tm == null:
		print("  terrain: no TerrainManager autoload — engine cover reads nothing")
		return []
	_saved_terrain = _tm.terrain_features
	print("  terrain: boot layout '%s' had %d piece(s); cleared for the run (restored at exit)"
		% [str(_tm.current_layout), _saved_terrain.size()])
	_tm.terrain_features = []
	if not _tm.terrain_features.is_empty():
		_harness_errors.append("TerrainManager.terrain_features could not be cleared")
	return _tm.terrain_features


func _finish(code: int) -> void:
	if _tm != null and _saved_terrain != null:
		_tm.terrain_features = _saved_terrain
	quit(code)


func _run() -> void:
	var re = root.get_node_or_null("RulesEngine")
	if re == null:
		print("[FAIL] RulesEngine autoload not present — cannot compare against the engine")
		quit(1)
		return
	if _write_catalogue and _seeded_bug:
		print("[FAIL] --write-catalogue and --seeded-bug are mutually exclusive")
		quit(1)
		return
	_measurement = root.get_node_or_null("Measurement")
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
	print("  rules edition %d" % GameConstants.edition)
	print("  %d distinct weapon profiles in the shipped lists" % corpus.size())
	if not _full:
		corpus = corpus.slice(0, FAST_TIER)
		print("  fast tier: first %d (pass --full for the whole corpus)" % corpus.size())
	print("  %d Monte-Carlo samples per (weapon, defender) pair, seeded" % _samples)
	print("  duel: ranged %.0f\" centre-to-centre (unengaged, in half range), melee %.0f\"; defender 1 model x W%d"
		% [RANGED_SEPARATION_IN, MELEE_SEPARATION_IN, DEFENDER_WOUNDS])
	var terrain := _neutralise_terrain()
	if not _write_catalogue:
		var cat_ed := int(_catalogue_meta.get("edition", 0))
		if cat_ed != GameConstants.edition:
			_harness_errors.append("catalogue %s was measured at edition %s but this run is edition %d — its ratios are not comparable; run at the harness default or regenerate"
				% [CATALOGUE_PATH, (str(cat_ed) if _catalogue_meta.has("edition") else "<unstamped>"), GameConstants.edition])
	if _seeded_bug:
		print("  !! --seeded-bug: re-introducing AUDIT 0.1 (\"D6\" damage parsed as 1.0)")
		print("     only pairs whose prediction the seed changes are rolled; each is judged")
		print("     clean AND seeded against the same samples")
	print("")

	var defenders := _defender_grid()
	for entry in corpus:
		var weapon: Dictionary = entry.weapon
		var wname := str(weapon.get("name", "?"))
		var sig := str(entry.sig)
		if _only != "" and wname.to_lower().find(_only.to_lower()) < 0:
			continue
		var melee: bool = _is_melee(weapon)
		for d in defenders:
			var target := _make_unit("U_DEF", 2, d, [], _defender_pos(melee))
			var shooter := _make_unit("U_ATT", 1, {"t": 4, "sv": 3, "w": 3, "models": 1},
				[weapon], ATTACKER_POS)
			var snapshot := {"units": {"U_ATT": shooter, "U_DEF": target},
							 "meta": {"battle_round": 1},
							 "board": {"terrain_features": terrain}}
			var key := _catalogue_key(sig, str(d.label))

			if not melee:
				var problems := _ranged_duel_problems(re, weapon, shooter, target, snapshot)
				if not problems.is_empty():
					_harness_errors.append("%s vs %s: %s" % [sig, d.label, "; ".join(PackedStringArray(problems))])
					continue

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
			var clean_predicted := predicted
			if _seeded_bug:
				predicted = _seeded_prediction(weapon, clean_predicted)
				if absf(predicted - clean_predicted) <= 1e-9 * maxf(1.0, absf(clean_predicted)):
					# Identical to the unseeded run by construction — rolling it
					# again proves nothing about sensitivity.
					_seed_unaffected += 1
					continue

			if predicted <= 0.0:
				_skipped += 1
				continue

			var mc := _mc_expected_damage(re, weapon, d, melee, _samples, terrain)
			if not mc.get("ok", false):
				if mc.get("harness", false):
					_harness_errors.append("%s vs %s: %s" % [sig, d.label, mc.get("note", "?")])
					continue
				_skipped += 1
				if _skip_notes.size() < 6:
					_skip_notes.append("%s vs %s: %s" % [sig, d.label, mc.get("note", "?")])
				continue
			var actual: float = mc.mean
			if actual <= 0.0 and predicted <= 0.0:
				_skipped += 1
				continue
			var se: float = float(mc.se)
			var tol := _tolerance_for(wname, str(weapon.get("special_rules", "")))
			var bar: float = float(tol.get("rel", TOLERANCE))
			var known: Dictionary = _catalogue.get(key, {})
			if not known.is_empty():
				_exercised_keys[key] = true

			var j := _judge(predicted, actual, se, bar, known)
			var known_hit: bool = j.known
			var ok: bool = j.green
			if _write_catalogue and not j.agree:
				_new_catalogue[key] = {
					"kind": "melee" if melee else "ranged",
					"ratio": snappedf(float(j.ratio), 0.001),
					"predicted": snappedf(predicted, 0.001),
					"resolved": snappedf(actual, 0.001),
					"se": snappedf(se, 0.001),
					"why": str(known.get("why", "UNDIAGNOSED — name the isolated cause before committing")),
				}
				ok = true
				known_hit = true
			elif not ok and j.drift != "":
				_drifted.append("%s vs %s: %s (%s)" % [sig, d.label, j.drift, known.get("why", "")])
			if j.agree and not known.is_empty() and not _seeded_bug:
				_retired.append("%s: catalogued %.2f, now agrees at %.2f" % [key, float(known.get("ratio", 0.0)), float(j.ratio)])

			if _seeded_bug:
				# Sensitivity is measured against the unseeded baseline on the
				# SAME samples: only a pair that is green with the clean
				# prediction can show that the seed is what turned it red.
				var jc := _judge(clean_predicted, actual, se, bar, known)
				var label := "%s vs %s (clean %.3f, seeded %.3f, engine %.3f)" % [sig, d.label, clean_predicted, predicted, actual]
				if not jc.green:
					_seed_unmeasurable.append(label)
				else:
					var wstat: Dictionary = _seed_weapons.get(sig, {"caught": 0, "measurable": 0})
					wstat.measurable += 1
					if not ok:
						wstat.caught += 1
						_seed_caught.append(label)
					elif known_hit:
						# Waved through by a catalogue entry: the ratchet is too
						# loose to see AUDIT 0.1 on this pair.
						_seed_absorbed.append(label)
					else:
						# Agrees even when seeded — the seeded error is inside
						# this pair's Monte-Carlo noise (tiny expected damage).
						_seed_missed.append(label)
					_seed_weapons[sig] = wstat

			_rows.append({"weapon": sig, "defender": d.label, "pred": predicted,
						  "mc": actual, "se": se, "rel": j.rel, "bar": bar,
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
	print("  %-58s %-26s %8s %8s %7s %7s" % ["weapon profile", "defender", "AI", "engine", "rel", "sigma"])
	var shown := 0
	for r in _rows:
		if r.ok and not r.known and shown >= 10:
			continue
		print("  %s %-58s %-26s %8.3f %8.3f %6.1f%% %6.1f%s" % [
			("~~" if r.known else ("  " if r.ok else "!!")), r.weapon.substr(0, 58), r.defender,
			r.pred, r.mc, 100.0 * r.rel, r.sigma,
			("   [%s]" % r.why) if r.why != "" else ""])
		shown += 1
	for n in _skip_notes:
		print("  skipped: %s" % n)
	print("")
	print("=".repeat(78))
	for msg in _harness_errors:
		print("  HARNESS: %s" % msg)
	for msg in _drifted:
		print("  DRIFT: %s" % msg)
	for msg in _retired:
		print("  RETIRED (catalogued, now agrees — delete the entry): %s" % msg)
	var unexercised := 0
	for k in _catalogue:
		if not _exercised_keys.has(k):
			unexercised += 1
	if unexercised > 0 and not _seeded_bug:
		print("  note: %d catalogue entr%s not exercised by this tier/filter"
			% [unexercised, "y was" if unexercised == 1 else "ies were"])
	print("  %d pairs agree within %.0f%%, %d known+owned divergences (~~), %d NEW failures, %d skipped"
		% [_passed, 100.0 * TOLERANCE, _known, _failed, _skipped])
	if _write_catalogue:
		var fh := FileAccess.open("user://ai_combat_math_known_divergences.json", FileAccess.WRITE)
		fh.store_string(JSON.stringify({
			"note": "Generated by tests/test_ai_combat_math_property.gd --write-catalogue. Each entry is a REPRODUCED divergence between the AI's expected-damage arithmetic and RulesEngine resolution, with the ratio measured when it was catalogued. This file is a ratchet, not an excuse: an uncatalogued pair must agree, and a catalogued pair must not drift further or flip sides.",
			"generated": Time.get_date_string_from_system(), "samples": _samples,
			"edition": GameConstants.edition, "tier": "full" if _full else "fast",
			"defender_wounds": DEFENDER_WOUNDS,
			"divergences": _new_catalogue}, "  ", true))
		fh.close()
		print("  catalogue written to user://ai_combat_math_known_divergences.json (%d entries)"
			% _new_catalogue.size())
		print("  path: %s" % ProjectSettings.globalize_path("user://ai_combat_math_known_divergences.json"))
	var harness_ok := _harness_errors.is_empty()
	if not harness_ok:
		print("  HARNESS INVALID: %d harness error(s) above — the comparison does not measure the AI's arithmetic"
			% _harness_errors.size())
	var verdict := harness_ok and _failed == 0 and _drifted.is_empty()
	if _seeded_bug:
		# Inverted: with the AUDIT 0.1 defect injected the test MUST fail, or
		# it is not sensitive enough to have caught the bug it exists for.
		# Measured against the unseeded baseline, on the same samples:
		#   * a pair counts only if it is green with the CLEAN prediction — a
		#     pair already red unseeded cannot show sensitivity (that is what
		#     made the old `_failed > 0` verdict vacuous);
		#   * AUDIT 0.1 is a per-weapon defect, so EVERY weapon the seed
		#     changes must be caught (turned red) on at least one defender;
		#   * no pair may be waved through by a catalogue entry — that would
		#     mean the ratchet is too loose to see the defect it exists for.
		# A seeded pair that still agrees only because its expected damage is
		# inside Monte-Carlo noise is reported but does not fail the check
		# while the same weapon is caught elsewhere.
		for msg in _seed_caught:
			print("  seeded caught: %s" % msg)
		for msg in _seed_absorbed:
			print("  seeded ABSORBED by the catalogue: %s" % msg)
		for msg in _seed_missed:
			print("  seeded within noise: %s" % msg)
		for msg in _seed_unmeasurable:
			print("  seeded unmeasurable (already red unseeded): %s" % msg)
		var weapons_caught := 0
		for wsig in _seed_weapons:
			if int(_seed_weapons[wsig].caught) > 0:
				weapons_caught += 1
			else:
				print("  seeded weapon NOT CAUGHT on any defender: %s" % wsig)
		verdict = harness_ok and not _seed_weapons.is_empty() \
			and weapons_caught == _seed_weapons.size() and _seed_absorbed.is_empty()
		print("  --seeded-bug: caught %d of %d weapon(s) the seed changes; pairs: %d caught, %d absorbed by the catalogue, %d within noise, %d unmeasurable, %d unchanged (not rolled) -> %s"
			% [weapons_caught, _seed_weapons.size(), _seed_caught.size(), _seed_absorbed.size(),
			   _seed_missed.size(), _seed_unmeasurable.size(), _seed_unaffected,
			   "DETECTED" if verdict else "NOT DETECTED"])
	print("VERDICT: %s" % ("PASS" if verdict else "FAIL"))
	print("=".repeat(78))
	_finish(0 if verdict else 1)
