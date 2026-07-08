extends SceneTree

# Staged shooting resolution + Command Re-roll (RulesEngine).
#
# Proves:
#   A) resolve_shoot_hits() + resolve_shoot_wounds() driven with the SAME rng
#      as resolve_shoot_until_wounds() consumes dice in the identical order and
#      produces identical to_hit / to_wound dice records (the split is a pure
#      re-shape of the monolith).
#   B) resolve_shoot_hits() returns ONLY the hit roll (no wound record) + a
#      hit_context; resolve_shoot_wounds(hit_context) returns the wound record.
#   C) reroll_hit_die() re-rolls exactly one die, recomputes hits and
#      total_hits_for_wounds, and leaves the untouched dice unchanged.
#   D) reroll_wound_die() re-rolls one die and rebuilds wounds_caused + save_data.
#
# Usage: godot --headless --path . -s tests/test_staged_shooting_reroll.gd

var passed := 0
var failed := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init():
	root.connect("ready", Callable(self, "_run"))
	create_timer(0.1).timeout.connect(_run)

func _make_board() -> Dictionary:
	var shooter_models = []
	for i in range(5):
		shooter_models.append({
			"id": "ms%d" % i,
			"position": {"x": 0, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 1, "current_wounds": 1
		})
	var target_models = []
	for i in range(10):
		target_models.append({
			"id": "mt%d" % i,
			"position": {"x": 40, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 1, "current_wounds": 1,
			"stats": {"toughness": 4, "save": 4}
		})
	return {
		"units": {
			"U_SHOOTER": {
				"id": "U_SHOOTER", "owner": 1,
				"meta": {"name": "Shooters", "keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 3}},
				"models": shooter_models, "flags": {}
			},
			"U_TARGET": {
				"id": "U_TARGET", "owner": 2,
				"meta": {"name": "Targets", "keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 4}},
				"models": target_models, "flags": {}
			}
		}
	}

func _action() -> Dictionary:
	return {
		"type": "SHOOT",
		"actor_unit_id": "U_SHOOTER",
		"payload": {"assignments": [{
			"weapon_id": "bolt_rifle",
			"target_unit_id": "U_TARGET",
			"model_ids": ["ms0", "ms1", "ms2", "ms3", "ms4"],
			"attacks_override": 12
		}]}
	}

func _find(dice: Array, ctx: String) -> Dictionary:
	for d in dice:
		if d.get("context", "") == ctx:
			return d
	return {}

func _run():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_staged_shooting_reroll ===\n")
	var rules = root.get_node_or_null("RulesEngine")
	if rules == null:
		_check("RulesEngine autoload reachable", false)
		_finish()
		return

	var SEED := 424242

	# --- A) Equivalence: monolith vs staged with the same seed ---
	var mono = rules.resolve_shoot_until_wounds(_action(), _make_board(), rules.RNGService.new(SEED))
	var mono_hit = _find(mono.get("dice", []), "to_hit")
	var mono_wound = _find(mono.get("dice", []), "to_wound")

	var staged_rng = rules.RNGService.new(SEED)
	var board2 = _make_board()
	var hits_res = rules.resolve_shoot_hits(_action(), board2, staged_rng)
	var wounds_res = rules.resolve_shoot_wounds(hits_res.get("hit_context", {}), board2, staged_rng)
	var staged_hit = _find(hits_res.get("dice", []), "to_hit")
	var staged_wound = _find(wounds_res.get("dice", []), "to_wound")

	_check("A: monolith produced a to_hit record", not mono_hit.is_empty())
	_check("A: monolith produced a to_wound record", not mono_wound.is_empty())
	_check("A: staged hit rolls == monolith hit rolls",
		str(staged_hit.get("rolls_raw", [])) == str(mono_hit.get("rolls_raw", [])),
		"staged=%s mono=%s" % [str(staged_hit.get("rolls_raw", [])), str(mono_hit.get("rolls_raw", []))])
	_check("A: staged hit successes == monolith",
		staged_hit.get("successes", -1) == mono_hit.get("successes", -2))
	_check("A: staged wound rolls == monolith wound rolls",
		str(staged_wound.get("rolls_raw", [])) == str(mono_wound.get("rolls_raw", [])),
		"staged=%s mono=%s" % [str(staged_wound.get("rolls_raw", [])), str(mono_wound.get("rolls_raw", []))])
	_check("A: staged wound successes == monolith",
		staged_wound.get("successes", -1) == mono_wound.get("successes", -2))

	# --- B) hits stage returns ONLY the hit roll + a hit_context ---
	var hits_only = rules.resolve_shoot_hits(_action(), _make_board(), rules.RNGService.new(SEED))
	_check("B: hits stage has to_hit record", not _find(hits_only.get("dice", []), "to_hit").is_empty())
	_check("B: hits stage has NO to_wound record", _find(hits_only.get("dice", []), "to_wound").is_empty())
	_check("B: hits stage returns a hit_context", hits_only.has("hit_context") and not hits_only.hit_context.is_empty())

	# --- C) reroll_hit_die: one die changes, totals recompute, others stable ---
	var hc = hits_only.get("hit_context", {})
	var evals_before = (hc.get("hit_evals", []) as Array).duplicate(true)
	var hits_before = int(hc.get("hits", 0))
	var idx := 0  # pick a failed die if present, else 0
	for i in range(evals_before.size()):
		if not evals_before[i].get("is_hit", false):
			idx = i
			break
	var rr = rules.reroll_hit_die(hc, idx, rules.RNGService.new(99))
	_check("C: reroll_hit_die succeeded", rr.get("success", false), str(rr.get("error", "")))
	_check("C: exactly one hit die changed",
		_count_diff(evals_before, hc.get("hit_evals", [])) == 1,
		"diffs=%d" % _count_diff(evals_before, hc.get("hit_evals", [])))
	_check("C: total_hits_for_wounds == hits + sustained",
		int(hc.get("total_hits_for_wounds", -1)) == int(hc.get("hits", 0)) + int(hc.get("sustained_bonus_hits", 0)))
	_check("C: hits recomputed consistently with evals",
		int(hc.get("hits", -1)) == _count_hits(hc.get("hit_evals", [])),
		"hits=%d evals_hits=%d" % [int(hc.get("hits", -1)), _count_hits(hc.get("hit_evals", []))])
	print("    (hits %d -> %d after re-rolling die %d)" % [hits_before, int(hc.get("hits", 0)), idx])

	# --- D) reroll_wound_die: rebuild wounds + save_data ---
	# Fresh resolve to a wound stage with wounds present.
	var d_rng = rules.RNGService.new(SEED)
	var d_board = _make_board()
	var d_hits = rules.resolve_shoot_hits(_action(), d_board, d_rng)
	var d_wounds = rules.resolve_shoot_wounds(d_hits.get("hit_context", {}), d_board, d_rng)
	if d_wounds.has("wound_context") and not d_wounds.get("save_data_list", []).is_empty():
		var wc = d_wounds.get("wound_context", {})
		var wev_before = (wc.get("wound_evals", []) as Array).duplicate(true)
		var w_rr = rules.reroll_wound_die(wc, 0, d_board, rules.RNGService.new(7))
		_check("D: reroll_wound_die succeeded", w_rr.get("success", false), str(w_rr.get("error", "")))
		_check("D: exactly one wound die changed",
			_count_diff(wev_before, wc.get("wound_evals", [])) == 1)
		_check("D: rebuilt save_data has wounds_to_save == wounds_caused",
			int(w_rr.get("save_data", {}).get("wounds_to_save", -1)) == int(w_rr.get("wounds_caused", -2))
				or int(w_rr.get("wounds_caused", 0)) == 0)
	else:
		print("    (no wounds this seed — D skipped, not a failure)")

	_finish()

func _count_diff(a: Array, b: Array) -> int:
	var n = 0
	for i in range(min(a.size(), b.size())):
		if str(a[i]) != str(b[i]):
			n += 1
	return n

func _count_hits(evals: Array) -> int:
	var n = 0
	for e in evals:
		if e.get("is_hit", false):
			n += 1
	return n

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit()
