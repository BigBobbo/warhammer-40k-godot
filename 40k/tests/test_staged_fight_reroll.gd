extends SceneTree

# Staged fight resolution + Command Re-roll (RulesEngine).
#
# Proves:
#   A) resolve_melee_hits() + resolve_melee_wounds() + resolve_melee_saves_auto()
#      driven with the SAME rng as resolve_melee_attacks() consumes dice in the
#      identical order and produces identical hit_roll_melee / wound_roll_melee /
#      save dice records and diffs (the split is a pure re-shape of the monolith).
#   B) resolve_melee_hits() returns ONLY the hit roll (no wound record) + a
#      hit_context; resolve_melee_wounds(hit_context) returns the wound record.
#   C) reroll_hit_die() works on a MELEE hit_context: re-rolls exactly one die,
#      recomputes hits and total_hits_for_wounds, leaves untouched dice unchanged.
#   D) reroll_wound_die() works on a MELEE wound_context and rebuilds save_data
#      via the melee save-resolution path.
#   E) resolve_melee_attacks_interactive() (P0-58 path) produces the same
#      save_data wounds as the staged hits+wounds calls with the same seed.
#
# Usage: godot --headless --path . -s tests/test_staged_fight_reroll.gd

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
	# Attacker and target columns 40px (1") apart — every model in engagement range.
	var attacker_models = []
	for i in range(5):
		attacker_models.append({
			"id": "ma%d" % i,
			"position": {"x": 0, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 2, "current_wounds": 2
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
			"U_FIGHTER": {
				"id": "U_FIGHTER", "owner": 1,
				"meta": {"name": "Fighters", "keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 3}},
				"models": attacker_models, "flags": {}
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
		"type": "FIGHT",
		"actor_unit_id": "U_FIGHTER",
		"payload": {"assignments": [{
			"attacker": "U_FIGHTER",
			"target": "U_TARGET",
			"weapon": "lance_melee",
			"models": ["0", "1", "2", "3", "4"]
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
	print("\n=== test_staged_fight_reroll ===\n")
	var rules = root.get_node_or_null("RulesEngine")
	if rules == null:
		_check("RulesEngine autoload reachable", false)
		_finish()
		return

	var SEED := 424242

	# --- A) Equivalence: monolith vs staged thirds with the same seed ---
	var mono = rules.resolve_melee_attacks(_action(), _make_board(), rules.RNGService.new(SEED))
	var mono_hit = _find(mono.get("dice", []), "hit_roll_melee")
	var mono_wound = _find(mono.get("dice", []), "wound_roll_melee")

	var staged_rng = rules.RNGService.new(SEED)
	var board2 = _make_board()
	var hits_res = rules.resolve_melee_hits(_action(), board2, staged_rng)
	var staged_hit = _find(hits_res.get("dice", []), "hit_roll_melee")
	_check("A: monolith produced a hit_roll_melee record", not mono_hit.is_empty())
	_check("A: staged hit rolls == monolith hit rolls",
		str(staged_hit.get("rolls_raw", [])) == str(mono_hit.get("rolls_raw", [])),
		"staged=%s mono=%s" % [str(staged_hit.get("rolls_raw", [])), str(mono_hit.get("rolls_raw", []))])
	_check("A: staged hit successes == monolith",
		staged_hit.get("successes", -1) == mono_hit.get("successes", -2))

	if not hits_res.get("no_hits", true):
		var wounds_res = rules.resolve_melee_wounds(hits_res.get("hit_context", {}), board2, staged_rng)
		var staged_wound = _find(wounds_res.get("dice", []), "wound_roll_melee")
		_check("A: monolith produced a wound_roll_melee record", not mono_wound.is_empty())
		_check("A: staged wound rolls == monolith wound rolls",
			str(staged_wound.get("rolls_raw", [])) == str(mono_wound.get("rolls_raw", [])),
			"staged=%s mono=%s" % [str(staged_wound.get("rolls_raw", [])), str(mono_wound.get("rolls_raw", []))])
		_check("A: staged wound successes == monolith",
			staged_wound.get("successes", -1) == mono_wound.get("successes", -2))

		# NOTE: resolve_melee_wounds rolls Hold Still MW (0 here — no Painboy) and
		# does NOT consume rng otherwise; saves_auto must then match the monolith's
		# save/damage tail dice.
		if not wounds_res.get("no_wounds", true):
			var saves_res = rules.resolve_melee_saves_auto(hits_res.get("hit_context", {}), wounds_res.get("wound_result", {}), board2, staged_rng)
			var mono_save_ctxs = []
			for db in mono.get("dice", []):
				var c = db.get("context", "")
				if c != "hit_roll_melee" and c != "wound_roll_melee":
					mono_save_ctxs.append([c, str(db.get("rolls_raw", db.get("rolls", [])))])
			var staged_save_ctxs = []
			for db in saves_res.get("dice", []):
				staged_save_ctxs.append([db.get("context", ""), str(db.get("rolls_raw", db.get("rolls", [])))])
			_check("A: staged save/damage dice == monolith tail dice",
				str(staged_save_ctxs) == str(mono_save_ctxs),
				"staged=%s mono=%s" % [str(staged_save_ctxs), str(mono_save_ctxs)])
			_check("A: staged diffs count == monolith diffs count",
				saves_res.get("diffs", []).size() == mono.get("diffs", []).size(),
				"staged=%d mono=%d" % [saves_res.get("diffs", []).size(), mono.get("diffs", []).size()])

	# --- B) hits stage returns ONLY the hit roll + a hit_context ---
	var hits_only = rules.resolve_melee_hits(_action(), _make_board(), rules.RNGService.new(SEED))
	_check("B: hits stage has hit_roll_melee record", not _find(hits_only.get("dice", []), "hit_roll_melee").is_empty())
	_check("B: hits stage has NO wound_roll_melee record", _find(hits_only.get("dice", []), "wound_roll_melee").is_empty())
	_check("B: hits stage returns a hit_context", hits_only.has("hit_context") and not hits_only.hit_context.is_empty())
	_check("B: melee hit_context flagged is_melee", hits_only.get("hit_context", {}).get("is_melee", false))

	# --- C) reroll_hit_die on the melee context ---
	var hc = hits_only.get("hit_context", {})
	var evals_before = (hc.get("hit_evals", []) as Array).duplicate(true)
	var hits_before = int(hc.get("hits", 0))
	var idx := 0  # pick a failed die if present, else 0
	for i in range(evals_before.size()):
		if not evals_before[i].get("is_hit", false):
			idx = i
			break
	var rr = rules.reroll_hit_die(hc, idx, rules.RNGService.new(99))
	_check("C: reroll_hit_die succeeded on melee context", rr.get("success", false), str(rr.get("error", "")))
	_check("C: exactly one hit die changed",
		_count_diff(evals_before, hc.get("hit_evals", [])) == 1,
		"diffs=%d" % _count_diff(evals_before, hc.get("hit_evals", [])))
	_check("C: total_hits_for_wounds == hits + sustained",
		int(hc.get("total_hits_for_wounds", -1)) == int(hc.get("hits", 0)) + int(hc.get("sustained_bonus_hits", 0)))
	_check("C: hits recomputed consistently with evals",
		int(hc.get("hits", -1)) == _count_hits(hc.get("hit_evals", [])),
		"hits=%d evals_hits=%d" % [int(hc.get("hits", -1)), _count_hits(hc.get("hit_evals", []))])
	_check("C: reroll dice block uses melee context name",
		rr.get("dice_block", {}).get("context", "") == "hit_roll_melee",
		"ctx=%s" % rr.get("dice_block", {}).get("context", ""))
	print("    (hits %d -> %d after re-rolling die %d)" % [hits_before, int(hc.get("hits", 0)), idx])

	# --- D) reroll_wound_die on the melee wound_context ---
	var d_rng = rules.RNGService.new(SEED)
	var d_board = _make_board()
	var d_hits = rules.resolve_melee_hits(_action(), d_board, d_rng)
	var d_wounds = rules.resolve_melee_wounds(d_hits.get("hit_context", {}), d_board, d_rng)
	if not d_wounds.get("wound_context", {}).is_empty() and not d_wounds.get("save_data_list", []).is_empty():
		var wc = d_wounds.get("wound_context", {})
		_check("D: melee wound_context flagged is_melee", wc.get("is_melee", false))
		var wev_before = (wc.get("wound_evals", []) as Array).duplicate(true)
		var w_rr = rules.reroll_wound_die(wc, 0, d_board, rules.RNGService.new(7))
		_check("D: reroll_wound_die succeeded on melee context", w_rr.get("success", false), str(w_rr.get("error", "")))
		_check("D: exactly one wound die changed",
			_count_diff(wev_before, wc.get("wound_evals", [])) == 1)
		_check("D: rebuilt save_data has wounds_to_save == wounds_caused",
			int(w_rr.get("save_data", {}).get("wounds_to_save", -1)) == int(w_rr.get("wounds_caused", -2))
				or int(w_rr.get("wounds_caused", 0)) == 0)
		_check("D: reroll dice block uses melee context name",
			w_rr.get("dice_block", {}).get("context", "") == "wound_roll_melee",
			"ctx=%s" % w_rr.get("dice_block", {}).get("context", ""))
	else:
		print("    (no wounds this seed — D skipped, not a failure)")

	# --- E) interactive path (P0-58) matches staged save_data with same seed ---
	var e_int = rules.resolve_melee_attacks_interactive(_action(), _make_board(), rules.RNGService.new(SEED))
	var e_rng = rules.RNGService.new(SEED)
	var e_board = _make_board()
	var e_hits = rules.resolve_melee_hits(_action(), e_board, e_rng)
	var e_wounds = rules.resolve_melee_wounds(e_hits.get("hit_context", {}), e_board, e_rng)
	var int_sd = e_int.get("save_data_list", [])
	var staged_sd = e_wounds.get("save_data_list", [])
	_check("E: interactive and staged agree on save_data presence",
		int_sd.is_empty() == staged_sd.is_empty())
	if not int_sd.is_empty() and not staged_sd.is_empty():
		_check("E: interactive and staged agree on wounds_to_save",
			int(int_sd[0].get("wounds_to_save", -1)) == int(staged_sd[0].get("wounds_to_save", -2)),
			"int=%d staged=%d" % [int(int_sd[0].get("wounds_to_save", -1)), int(staged_sd[0].get("wounds_to_save", -2))])

	# --- F) Hold Still (OA-19) — the extracted helper matches the interactive
	#        monolith with the same seed (Painboy 'Urty Syringe, crit wounds) ---
	var hs_seed := 0
	var hs_int = {}
	var hs_found := false
	for try_seed in range(1, 60):
		hs_int = rules.resolve_melee_attacks_interactive(_hs_action(), _hs_board(), rules.RNGService.new(try_seed))
		var sdl = hs_int.get("save_data_list", [])
		if not sdl.is_empty() and int(sdl[0].get("hold_still_mortal_wounds", 0)) > 0:
			hs_seed = try_seed
			hs_found = true
			break
	if hs_found:
		var f_rng = rules.RNGService.new(hs_seed)
		var f_board = _hs_board()
		var f_hits = rules.resolve_melee_hits(_hs_action(), f_board, f_rng)
		var f_wounds = rules.resolve_melee_wounds(f_hits.get("hit_context", {}), f_board, f_rng)
		var int_hs = int(hs_int.get("save_data_list", [])[0].get("hold_still_mortal_wounds", -1))
		var staged_hs_sd = f_wounds.get("save_data_list", [])
		var staged_hs = int(staged_hs_sd[0].get("hold_still_mortal_wounds", -2)) if not staged_hs_sd.is_empty() else -2
		_check("F: Hold Still MW identical between interactive and staged (seed %d)" % hs_seed,
			int_hs == staged_hs, "int=%d staged=%d" % [int_hs, staged_hs])
	else:
		_check("F: found a seed producing Hold Still mortal wounds", false, "no crit wounds in 60 seeds?")

	_finish()

func _hs_board() -> Dictionary:
	var b = _make_board()
	b.units.U_FIGHTER.meta["abilities"] = [{"name": "Hold Still and Say 'Aargh!'", "description": "test"}]
	b.units.U_FIGHTER.meta["weapons"] = [{
		"name": "'Urty Syringe", "type": "Melee", "range": "Melee",
		"attacks": "4", "weapon_skill": "3", "strength": "4",
		"ap": "0", "damage": "1", "special_rules": ""
	}]
	return b

func _hs_action() -> Dictionary:
	return {
		"type": "FIGHT",
		"actor_unit_id": "U_FIGHTER",
		"payload": {"assignments": [{
			"attacker": "U_FIGHTER",
			"target": "U_TARGET",
			"weapon": "'Urty Syringe",
			"models": ["0", "1", "2", "3", "4"]
		}]}
	}

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
