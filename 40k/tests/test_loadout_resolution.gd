extends SceneTree

# MA-LOADOUT: validate per-model ranged-loadout resolution across ALL army files.
#
# For every unit in every res://armies/*.json, drive the REAL
# RE.get_unit_weapons and check:
#   * RESOLVED units (wargear pinned the loadout) report exactly ONE ranged gun
#     per model, and the per-gun totals match the unit's wargear counts.
#   * The change only ever REDUCES over-counting — a unit's total ranged
#     instances never goes UP versus the raw model_profiles menu.
# Plus targeted spot-checks (Boyz -> Slugga, orks Lootas unchanged, Burna Boyz).
#
# Usage: godot --headless --path . -s tests/test_loadout_resolution.gd

var passed := 0
var failed := 0
var RE  # RulesEngine autoload (fetched via node — not available as a compile-time identifier under -s)

func _init():
	root.connect("ready", Callable(self, "_run"))
	create_timer(0.2).timeout.connect(_run)

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, ("  --  " + detail) if detail != "" else ""])

func _list_army_files() -> Array:
	var out := []
	var d = DirAccess.open("res://armies")
	if d == null:
		return out
	d.list_dir_begin()
	var f = d.get_next()
	while f != "":
		if f.ends_with(".json"):
			out.append("res://armies/%s" % f)
		f = d.get_next()
	d.list_dir_end()
	out.sort()
	return out

func _load_json(path: String):
	var fa = FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return null
	var txt = fa.get_as_text()
	fa.close()
	return JSON.parse_string(txt)

# Count ranged instances a unit reports WITHOUT resolution (raw menu) — mirrors
# the pre-change _get_model_weapon_ids so we can prove totals only go down.
func _raw_ranged_total(unit: Dictionary) -> int:
	var meta = unit.get("meta", {})
	var mp = meta.get("model_profiles", {})
	var total := 0
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		var mt = model.get("model_type", "")
		var use_profile = not mp.is_empty() and mt != "" and mp.has(mt)
		var allowed = mp[mt].get("weapons", []) if use_profile else []
		for w in meta.get("weapons", []):
			if str(w.get("type", "")).to_lower() != "ranged":
				continue
			if use_profile and not (w.get("name", "") in allowed):
				continue
			total += 1
	return total

func _run():
	if passed > 0 or failed > 0:
		return
	RE = root.get_node_or_null("RulesEngine")
	if RE == null:
		_check("RulesEngine autoload present", false)
		print("=== test_loadout_resolution: %d passed, %d failed ===" % [passed, failed])
		quit(1)
		return
	var resolved_units := 0
	var unresolved_multimodel := []
	var special_units := []  # Task B: units with special-weapon model(s) flagged
	var melee_resolved_units := 0  # Task D: units with resolved melee loadout
	for path in _list_army_files():
		var data = _load_json(path)
		if typeof(data) != TYPE_DICTIONARY:
			continue
		var units = data.get("units", {})
		if typeof(units) != TYPE_DICTIONARY:
			continue
		var fname = path.get_file()
		for uid in units:
			var unit = units[uid]
			if typeof(unit) != TYPE_DICTIONARY:
				continue
			var models = unit.get("models", [])
			if models.is_empty():
				continue
			var raw_total = _raw_ranged_total(unit)
			var board = {"units": {uid: unit}}
			var mw = RE.get_unit_weapons(uid, board)  # runs resolution
			# Per-model ranged counts + total after resolution
			var new_total := 0
			var worst := 0
			for mid in mw:
				var c = mw[mid].size()
				new_total += c
				worst = max(worst, c)
			# INVARIANT 1: resolution never ADDS ranged instances.
			_check("no-increase %s/%s" % [fname, uid], new_total <= raw_total,
				"raw=%d new=%d" % [raw_total, new_total])
			# Did this unit get resolved?
			var got_resolved := false
			for m in models:
				if m.has("ranged_loadout"):
					got_resolved = true
					break
			# INVARIANT 4: single-model units (VEHICLE/MONSTER/character) fire ALL
			# their guns — they must NEVER be resolved/collapsed, and their weapon
			# count must be untouched.
			if models.size() < 2:
				_check("single-model-untouched %s/%s" % [fname, uid],
					not got_resolved and new_total == raw_total,
					"resolved=%s raw=%d new=%d" % [str(got_resolved), raw_total, new_total])
			if got_resolved:
				resolved_units += 1
				# INVARIANT 2 (generalized for Task C): every resolved model reports
				# the SAME number k of ranged guns (k>=1) — a uniform loadout size.
				# This still catches over-counting but allows legit multi-gun models
				# (Deffkopta k=2) alongside one-gun mobs (k=1).
				var kmin := 999999
				var kmax := 0
				for mid in mw:
					var c = mw[mid].size()
					kmin = min(kmin, c)
					kmax = max(kmax, c)
				_check("resolved-uniform-k %s/%s" % [fname, uid], kmin == kmax and kmin >= 1,
					"kmin=%d kmax=%d" % [kmin, kmax])
				# INVARIANT 3 (generalized): total ranged == k × alive models.
				var alive := 0
				for m in models:
					if m.get("alive", true):
						alive += 1
				_check("resolved-total==k*alive %s/%s" % [fname, uid], new_total == kmax * alive,
					"total=%d k=%d alive=%d" % [new_total, kmax, alive])
				# INVARIANT 5 (Task C): every stamped gun is one the model_type may
				# actually take — never invent a weapon a model can't have.
				var mp2 = unit.get("meta", {}).get("model_profiles", {})
				var meta_ranged := {}
				for w in unit.get("meta", {}).get("weapons", []):
					if str(w.get("type", "")).to_lower() == "ranged":
						meta_ranged[str(w.get("name", ""))] = true
				for m in models:
					if not m.has("ranged_loadout"):
						continue
					var mt2 = str(m.get("model_type", ""))
					var use_prof = not mp2.is_empty() and mt2 != "" and mp2.has(mt2)
					var allowed2 = mp2[mt2].get("weapons", []) if use_prof else []
					for wname in m["ranged_loadout"]:
						var ok2 = (str(wname) in allowed2) if use_prof else meta_ranged.has(str(wname))
						_check("resolved-gun-allowed %s/%s" % [fname, uid], ok2,
							"'%s' not allowed for model_type '%s'" % [str(wname), mt2])
			elif models.size() >= 2 and worst > 1:
				unresolved_multimodel.append("%s/%s(%s)" % [fname, uid, str(unit.get("meta", {}).get("name", ""))])

			# Task B: collect special-weapon models (minority resolved gun). Also
			# assert the marked models are a strict subset of alive models (never
			# mark every model — that would defeat "stands out").
			var special = RE.get_special_weapon_model_ids(unit)
			if special.size() > 0:
				var alive_now := 0
				for m in models:
					if m.get("alive", true):
						alive_now += 1
				_check("special-subset %s/%s" % [fname, uid], special.size() < alive_now,
					"special=%d alive=%d" % [special.size(), alive_now])
				special_units.append("%s/%s(%s): %d special" % [fname, uid, str(unit.get("meta", {}).get("name", "")), special.size()])

			# ---- Task D: melee resolution invariants (mirror of ranged) ----
			var raw_melee = _raw_melee_total(unit)
			var mm = RE.get_unit_melee_weapons(uid, board)  # resolves melee
			var new_melee := 0
			var worst_melee := 0
			for mid in mm:
				var c = mm[mid].size()
				new_melee += c
				worst_melee = max(worst_melee, c)
			# INVARIANT: melee resolution never ADDS melee instances.
			_check("melee-no-increase %s/%s" % [fname, uid], new_melee <= raw_melee,
				"raw=%d new=%d" % [raw_melee, new_melee])
			var got_melee_resolved := false
			for m in models:
				if m.has("melee_loadout"):
					got_melee_resolved = true
					break
			# INVARIANT: single-model units never get a resolved melee loadout.
			if models.size() < 2:
				_check("single-model-melee-untouched %s/%s" % [fname, uid], not got_melee_resolved, "")
			if got_melee_resolved:
				melee_resolved_units += 1
				var kmin_m := 999999
				var kmax_m := 0
				for mid in mm:
					kmin_m = min(kmin_m, mm[mid].size())
					kmax_m = max(kmax_m, mm[mid].size())
				# INVARIANT: resolved melee is uniform (all models same count k>=1).
				_check("melee-uniform-k %s/%s" % [fname, uid], kmin_m == kmax_m and kmin_m >= 1,
					"kmin=%d kmax=%d" % [kmin_m, kmax_m])

	# -------- Targeted spot-checks --------
	_spot_check_boyz()
	_spot_check_orks_lootas_unchanged()
	_spot_check_burna()
	_spot_check_boyz_incomplete()   # Task C: incomplete-but-consistent (20-Boy mob, 10x Slugga)
	_spot_check_deffkopta()         # Task C: uniform dual-gun (kopta rokkits + slugga)
	_spot_check_special_weapons()   # Task B: minority-gun model detection
	_spot_check_melee()             # Task D: melee loadout resolution

	# Task C: widening coverage must RESOLVE MORE units than the Phase-1 baseline
	# (16) and leave fewer over-counters. Lower/upper bounds so future additions
	# only make this stronger.
	_check("Task C: resolved count increased vs Phase-1 baseline (16)", resolved_units >= 24,
		"resolved=%d (expected >=24)" % resolved_units)
	_check("Task C: unresolved over-counters decreased vs baseline (24)", unresolved_multimodel.size() <= 16,
		"unresolved=%d (expected <=16)" % unresolved_multimodel.size())

	print("")
	print("Resolved units (loadout pinned from wargear): %d" % resolved_units)
	print("Unresolved multi-model over-counters left as-is (data-limited): %d" % unresolved_multimodel.size())
	print("")
	print("Units with special-weapon model(s) flagged (Task B): %d" % special_units.size())
	for u in special_units:
		print("   * %s" % u)
	print("")
	print("Units with resolved MELEE loadout (Task D): %d" % melee_resolved_units)
	for u in unresolved_multimodel:
		print("   - %s" % u)
	print("")
	print("=== test_loadout_resolution: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _weapon_hist(uid: String, unit: Dictionary) -> Dictionary:
	var board = {"units": {uid: unit}}
	var mw = RE.get_unit_weapons(uid, board)
	var hist := {}
	for mid in mw:
		for wid in mw[mid]:
			hist[wid] = int(hist.get(wid, 0)) + 1
	return hist

func _spot_check_boyz():
	var data = _load_json("res://armies/orks.json")
	if typeof(data) != TYPE_DICTIONARY:
		_check("orks.json loads", false); return
	var u = data["units"].get("U_BOYZ_K", {})
	var hist = _weapon_hist("U_BOYZ_K", u)
	# wargear = 10x Slugga -> expect 10 sluggas, and NO shoota/big shoota/rokkit.
	_check("Boyz -> 10 Slugga", hist.get("slugga_ranged", 0) == 10, str(hist))
	_check("Boyz -> no Shoota (menu suppressed)", not hist.has("shoota_ranged"), str(hist))
	_check("Boyz -> no Big shoota", not hist.has("big_shoota_ranged"), str(hist))
	_check("Boyz -> no Rokkit", not hist.has("rokkit_launcha_ranged"), str(hist))

func _spot_check_orks_lootas_unchanged():
	# orks.json Lootas is ALREADY resolved via model_type -> must be untouched.
	var data = _load_json("res://armies/orks.json")
	var u = data["units"].get("U_LOOTAS_A", {})
	var hist = _weapon_hist("U_LOOTAS_A", u)
	_check("orks Lootas -> 8 Deffgun (model_type resolved, unchanged)", hist.get("deffgun_ranged", 0) == 8, str(hist))
	_check("orks Lootas -> 3 KMB (unchanged)", hist.get("kustom_mega_blasta_ranged", 0) == 3, str(hist))
	_check("orks Lootas -> no Big shoota", not hist.has("big_shoota_ranged"), str(hist))

func _spot_check_burna():
	var data = _load_json("res://armies/battlewagons.json")
	if typeof(data) != TYPE_DICTIONARY:
		return
	var u = data["units"].get("U_BURNA_BOYZ_A", {})
	if u.is_empty():
		return
	var hist = _weapon_hist("U_BURNA_BOYZ_A", u)
	# wargear = 4x Burna + 1x Big shoota
	_check("Burna Boyz -> 4 Burna", hist.get("burna_ranged", 0) == 4, str(hist))
	_check("Burna Boyz -> 1 Big shoota", hist.get("big_shoota_ranged", 0) == 1, str(hist))

func _spot_check_boyz_incomplete():
	# Task C CASE C: a 20-model Boyz mob whose wargear records only "9x Slugga,
	# 1x Slugga" (10 Slugga < 20 models, one consistent gun) -> every model Slugga.
	var data = _load_json("res://armies/orks.json")
	if typeof(data) != TYPE_DICTIONARY:
		return
	for uid in ["U_BOYZ_E", "U_BOYZ_F"]:
		var u = data["units"].get(uid, {})
		if u.is_empty():
			continue
		var n = u.get("models", []).size()
		var hist = _weapon_hist(uid, u)
		_check("Boyz %s -> %d Slugga (incomplete-consistent)" % [uid, n], hist.get("slugga_ranged", 0) == n, str(hist))
		_check("Boyz %s -> no Big shoota" % uid, not hist.has("big_shoota_ranged"), str(hist))
		_check("Boyz %s -> no Rokkit" % uid, not hist.has("rokkit_launcha_ranged"), str(hist))
		_check("Boyz %s -> no Shoota" % uid, not hist.has("shoota_ranged"), str(hist))

func _spot_check_deffkopta():
	# Task C CASE B: Deffkoptas carry a Kopta rokkits AND a Slugga (2 ranged each);
	# wargear "3x Kopta rokkits, 3x Slugga" over 3 models -> uniform 2-gun set.
	var data = _load_json("res://armies/battlewagons.json")
	if typeof(data) != TYPE_DICTIONARY:
		return
	var u = data["units"].get("U_DEFFKOPTAS_A", {})
	if u.is_empty():
		return
	var n = u.get("models", []).size()
	var hist = _weapon_hist("U_DEFFKOPTAS_A", u)
	_check("Deffkoptas -> %d Kopta rokkits" % n, hist.get("kopta_rokkits_ranged", 0) == n, str(hist))
	_check("Deffkoptas -> %d Slugga" % n, hist.get("slugga_ranged", 0) == n, str(hist))
	# Each model is stamped resolved with a 2-gun set (not left as the raw menu).
	var m0 = u.get("models", [])[0]
	_check("Deffkoptas -> model stamped 2-gun set", m0.get("ranged_loadout", []).size() == 2, str(m0.get("ranged_loadout", [])))
	# Task B: a uniform 2-gun mob has no stand-out model.
	_check("Deffkoptas -> 0 special (uniform)", RE.get_special_weapon_model_ids(u).size() == 0, str(RE.get_special_weapon_model_ids(u)))

func _spot_check_special_weapons():
	# Task B: minority-gun model detection (the special/heavy-weapon models).
	# Burna Boyz (battlewagons): 4 Burna + 1 Big shoota -> exactly 1 special.
	var bw = _load_json("res://armies/battlewagons.json")
	if typeof(bw) == TYPE_DICTIONARY:
		var u = bw["units"].get("U_BURNA_BOYZ_A", {})
		if not u.is_empty():
			var sp = RE.get_special_weapon_model_ids(u)
			_check("Burna Boyz -> 1 special-weapon model", sp.size() == 1, "special=%s" % str(sp))
	var ork = _load_json("res://armies/orks.json")
	if typeof(ork) == TYPE_DICTIONARY:
		# orks Lootas: 8 Deffgun + 3 KMB (model_type resolved) -> 3 special (KMB minority).
		var lu = ork["units"].get("U_LOOTAS_A", {})
		if not lu.is_empty():
			var sp2 = RE.get_special_weapon_model_ids(lu)
			_check("orks Lootas -> 3 special (KMB minority)", sp2.size() == 3, "special=%s" % str(sp2))
		# Boyz K: all Slugga -> 0 special (uniform).
		var bk = ork["units"].get("U_BOYZ_K", {})
		if not bk.is_empty():
			_check("Boyz K (all Slugga) -> 0 special", RE.get_special_weapon_model_ids(bk).size() == 0, str(RE.get_special_weapon_model_ids(bk)))
		# Boyz E: Task-C resolved to all Slugga -> 0 special.
		var be = ork["units"].get("U_BOYZ_E", {})
		if not be.is_empty():
			_check("Boyz E (all Slugga) -> 0 special", RE.get_special_weapon_model_ids(be).size() == 0, str(RE.get_special_weapon_model_ids(be)))
	# Single-model units never get a special marker (guarded on models.size()).
	var sm = _load_json("res://armies/space_marines.json")
	if typeof(sm) == TYPE_DICTIONARY:
		for uid in sm.get("units", {}):
			var su = sm["units"][uid]
			if typeof(su) == TYPE_DICTIONARY and su.get("models", []).size() == 1:
				_check("single-model %s -> 0 special" % uid, RE.get_special_weapon_model_ids(su).size() == 0, "")
				break

# Count melee instances a unit reports WITHOUT resolution (menu-based), mirroring
# the pre-change get_unit_melee_weapons so we can prove melee totals only go down.
func _raw_melee_total(unit: Dictionary) -> int:
	var meta = unit.get("meta", {})
	var mp = meta.get("model_profiles", {})
	var all_melee := []
	for w in meta.get("weapons", []):
		if str(w.get("type", "")).to_lower() == "melee":
			var wn = w.get("name", "")
			if wn not in all_melee:
				all_melee.append(wn)
	var total := 0
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		var mt = model.get("model_type", "")
		if not mp.is_empty() and mt != "" and mp.has(mt):
			var allowed = mp[mt].get("weapons", [])
			for wn in all_melee:
				if wn in allowed:
					total += 1
		else:
			total += all_melee.size()
	return total

func _melee_hist(uid: String, unit: Dictionary) -> Dictionary:
	var board = {"units": {uid: unit}}
	var mm = RE.get_unit_melee_weapons(uid, board)
	var hist := {}
	for mid in mm:
		for wn in mm[mid]:
			hist[str(wn)] = int(hist.get(str(wn), 0)) + 1
	return hist

func _spot_check_melee():
	# Task D: melee loadout resolution (mirror of the ranged spot-checks).
	# Beast Snagga Boyz (Orks_2000): wargear 9x Choppa + 1x Power snappa over 10
	# models -> 9 Choppa + 1 Power snappa, dropping the Close combat weapon ghost.
	var o = _load_json("res://armies/Orks_2000.json")
	if typeof(o) == TYPE_DICTIONARY:
		var bs = o["units"].get("U_BEAST_SNAGGA_BOYZ_A", {})
		if not bs.is_empty():
			var mmh = _melee_hist("U_BEAST_SNAGGA_BOYZ_A", bs)
			_check("Beast Snagga melee -> 9 Choppa", mmh.get("Choppa", 0) == 9, str(mmh))
			_check("Beast Snagga melee -> 1 Power snappa", mmh.get("Power snappa", 0) == 1, str(mmh))
			_check("Beast Snagga melee -> no Close combat weapon", not mmh.has("Close combat weapon"), str(mmh))
		# Kommandos: wargear says 10x Choppa but the Boss Nob's profile only allows
		# Big choppa — so the cross-check SAFELY declines (never invent a weapon a
		# model can't take) and melee falls back to the menu rather than resolving.
		var k = o["units"].get("U_KOMMANDOS_A", {})
		if not k.is_empty():
			var board_k = {"units": {"U_KOMMANDOS_A": k}}
			RE.get_unit_melee_weapons("U_KOMMANDOS_A", board_k)
			var kommandos_resolved := false
			for m in k.get("models", []):
				if m.has("melee_loadout"):
					kommandos_resolved = true
					break
			_check("Kommandos melee -> fallback (boss can't take Choppa)", not kommandos_resolved, "")
	# Burna Boyz (battlewagons): 4x Cuttin' flames + 1x Close combat weapon.
	var bw = _load_json("res://armies/battlewagons.json")
	if typeof(bw) == TYPE_DICTIONARY:
		var b = bw["units"].get("U_BURNA_BOYZ_A", {})
		if not b.is_empty():
			var mmh2 = _melee_hist("U_BURNA_BOYZ_A", b)
			_check("Burna melee -> 4 Cuttin' flames", mmh2.get("Cuttin' flames", 0) == 4, str(mmh2))
			_check("Burna melee -> 1 Close combat weapon", mmh2.get("Close combat weapon", 0) == 1, str(mmh2))
	# A melee menu that can't be pinned falls back (keeps the menu) — Boyz have no
	# melee wargear, so melee stays unresolved (no melee_loadout), NOT collapsed.
	var ork = _load_json("res://armies/orks.json")
	if typeof(ork) == TYPE_DICTIONARY:
		var bk = ork["units"].get("U_BOYZ_K", {})
		if not bk.is_empty():
			var board = {"units": {"U_BOYZ_K": bk}}
			RE.get_unit_melee_weapons("U_BOYZ_K", board)  # trigger resolution attempt
			var any_melee_lo := false
			for m in bk.get("models", []):
				if m.has("melee_loadout"):
					any_melee_lo = true
					break
			_check("Boyz K melee unresolved (no wargear) -> fallback", not any_melee_lo, "")
