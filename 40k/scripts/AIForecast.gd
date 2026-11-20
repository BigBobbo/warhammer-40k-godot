extends RefCounted
class_name AIForecast

# Game VP forecast for the AI — a GDScript port of the Combat Calc forecast
# (server/public/calc/forecast.mjs, 11e GDM 2026 mission deck). It simulates
# the rest of the battle many times for both players — the tactical secondary
# deck (draws, when-drawn rules, scoring, caps), each player's primary card
# from who holds which objective in each remaining battle round, and units
# destroyed each turn — and returns the spread of final scores.
#
# It is a planning model, not a game engine: objective ownership per round is
# an INPUT (the "plan"), kills come from a per-turn rate, and position cards
# score from a per-turn chance (the AI feeds its own board-aware achievability
# there). Card VP values and caps are exact. Keep the card logic in step with
# forecast.mjs — tests/unit/test_ai_forecast.gd checks the card ids and
# timings against server/public/calc/missions-11e.mjs.
#
# Card ids use the game's SecondaryMissionData ids (underscores); players are
# the ints 1 and 2. Everything is static and deterministic for a given seed.

const ROUNDS := 5
const DRAW_PER_TURN := 2
const PRIMARY_CAP := 45
const PRIMARY_ROUND_CAP := 15
const SECONDARY_CAP := 45
const SECONDARY_ROUND_CAP := 15
const FIXED_CARD_CAP := 20
const BATTLE_READY := 10

# timing: own = end of your turn, opp = end of the opponent's turn (or end of
# R5), any = end of either turn. kind: kill / hold / position / action.
const CARDS := {
	"a_grievous_blow": {"timing": "any", "kind": "kill", "target": "ss13", "fixed": true},
	"a_tempting_target": {"timing": "own", "kind": "hold"},
	"assassination": {"timing": "any", "kind": "kill", "target": "character", "fixed": true},
	"beacon": {"timing": "opp", "kind": "position"},
	"behind_enemy_lines": {"timing": "own", "kind": "position"},
	"bring_it_down": {"timing": "any", "kind": "kill", "target": "w10", "fixed": true},
	"burden_of_trust": {"timing": "opp", "kind": "hold"},
	"centre_ground": {"timing": "own", "kind": "position"},
	"cleanse": {"timing": "own", "kind": "action", "pair": "plunder"},
	"defend_stronghold": {"timing": "opp", "kind": "hold", "min_round": 2},
	"display_of_might": {"timing": "own", "kind": "position"},
	"engage_on_all_fronts": {"timing": "own", "kind": "position", "fixed": true},
	"forward_position": {"timing": "own", "kind": "hold"},
	"no_prisoners": {"timing": "any", "kind": "kill", "target": "any"},
	"outflank": {"timing": "own", "kind": "position"},
	"overwhelming_force": {"timing": "any", "kind": "kill", "target": "onObjective"},
	"plunder": {"timing": "own", "kind": "action", "pair": "cleanse"},
	"secure_no_mans_land": {"timing": "own", "kind": "hold"},
}
const CARD_MAX := 5
# Cards whose chance comes from where the units are (the AI's achievability).
const POSITION_CARDS := ["behind_enemy_lines", "engage_on_all_fronts", "outflank",
	"centre_ground", "display_of_might", "beacon", "plunder"]
const RATING_NORMAL := 0.5
# Expected kills per turn are scaled by round: the first player's R1 is light.
const ROUND_KILL := {"first": [0.45, 1.0, 1.1, 1.0, 0.9], "second": [0.75, 1.05, 1.1, 1.0, 0.9]}
const DEFAULT_KILL_RATE := 1.3

static func other(p: int) -> int:
	return 2 if p == 1 else 1

static func card_ids() -> Array:
	var ids: Array = CARDS.keys()
	ids.sort()
	return ids

# ---------------------------------------------------------------------------
# Army profile (what the cards care about)

static func army_profile(units: Array) -> Dictionary:
	"""units: [{name, models, characters, characters_w4, w10, ss13, aircraft}]"""
	var us: Array = []
	for u in units:
		us.append({
			"name": str(u.get("name", "")), "models": int(u.get("models", 1)),
			"characters": int(u.get("characters", 0)), "characters_w4": int(u.get("characters_w4", 0)),
			"w10": int(u.get("w10", 0)), "ss13": bool(u.get("ss13", false)),
			"aircraft": bool(u.get("aircraft", false)),
		})
	return {"units": us}

static func _target_dead(target: String, alive: Array) -> bool:
	match target:
		"character":
			for u in alive:
				if int(u.characters) > 0:
					return false
			return true
		"w10":
			for u in alive:
				if int(u.w10) > 0:
					return false
			return true
		"ss13":
			for u in alive:
				if bool(u.ss13):
					return false
			return true
	return false

static func card_dead(id: String, enemy_alive: Array) -> bool:
	"""A kill card whose targets no longer exist (enemy_alive: profile units)."""
	return _target_dead(str(CARDS.get(id, {}).get("target", "")), enemy_alive)

# ---------------------------------------------------------------------------
# Objectives: [{id, cls: home|exp|central, side: 1|2|0}] seen by player P

static func _holdings(objs: Array, owner: Dictionary, p: int) -> Dictionary:
	var h := {"total": 0, "home": 0, "opp_home": 0, "exp": 0, "opp_exp": 0, "central": 0,
		"non_home": 0, "nml": 0, "opp_territory": 0, "ids": []}
	for o in objs:
		if int(owner.get(o.id, 0)) != p:
			continue
		h.total += 1
		h.ids.append(o.id)
		if o.cls == "home":
			if int(o.side) == p:
				h.home += 1
			else:
				h.opp_home += 1
				h.opp_territory += 1
		elif o.cls == "central":
			h.central += 1
			h.nml += 1
		elif int(o.side) == p:
			h.exp += 1
			h.nml += 1
		else:
			h.opp_exp += 1
			h.nml += 1
			h.opp_territory += 1
	h.non_home = h.total - h.home
	return h

# ---------------------------------------------------------------------------
# Random helpers (RandomNumberGenerator: native speed, seeded = deterministic)

static func _poisson(lam: float, rng: RandomNumberGenerator) -> int:
	if lam <= 0.0:
		return 0
	var l := exp(-lam)
	var k := 0
	var p := 1.0
	while true:
		k += 1
		p *= rng.randf()
		if p <= l:
			break
	return k - 1

static func _binom(n: int, p: float, rng: RandomNumberGenerator) -> int:
	var c := 0
	for i in range(n):
		if rng.randf() < p:
			c += 1
	return c

static func _any_kill_roll(kills: Array, p: float, rng: RandomNumberGenerator) -> bool:
	# kills.some(() => rnd() < p) — short-circuits like the JS
	for _v in kills:
		if rng.randf() < p:
			return true
	return false

static func _killed_on_objective(c: Dictionary) -> bool:
	for v in c.kills:
		if bool(v.get("on_obj", false)):
			return true
	return false

static func _more(c: Dictionary) -> bool:
	return int(c.h.total) > int(c.h_opp.total)

# ---------------------------------------------------------------------------
# Primary missions (keyed by card name). c: {r, h, h_opp, kills, lost_prev,
# newly, p_act, ms, rng, enemy_alive, rate, pos}. Returns {C, EOT}.

static func _primary(name: String, c: Dictionary) -> Dictionary:
	var r: int = c.r
	var h: Dictionary = c.h
	var rng: RandomNumberGenerator = c.rng
	var nk: int = c.kills.size()
	var ms: Dictionary = c.ms
	var p_act: float = c.p_act
	match name:
		"Battlefield Dominance":
			return {"EOT": 2 if (r <= 2 and _more(c)) else 0,
				"C": (3 * h.total + (2 * h.non_home if h.home > 0 else 0)) if r >= 2 else 0}
		"Determined Acquisition":
			return {"EOT": 2 * int(c.newly), "C": (3 * h.total + 3 * h.opp_territory) if r >= 2 else 0}
		"Immovable Object":
			return {"EOT": 3 if h.central > 0 else 0, "C": 5 * h.non_home if r >= 2 else 0}
		"Inescapable Dominion":
			return {"EOT": 4 if h.total >= 3 else 0,
				"C": ((5 if h.total >= 2 else 0) + (4 if _more(c) else 0)) if r >= 2 else 0}
		"Purge and Secure":
			return {"EOT": (3 if _killed_on_objective(c) else 0) + (3 if (r >= 2 and int(c.newly) > 0) else 0),
				"C": 4 * h.non_home if r >= 2 else 0}
		"Consecrate":
			var can: int = maxi(0, 4 - int(ms.get("consecrated", 0)))
			var add: int = mini(can, _binom(nk, 0.45 * p_act, rng))
			ms["consecrated"] = int(ms.get("consecrated", 0)) + add
			if h.opp_home > 0 and add > 0:
				ms["opp_home_cons"] = bool(ms.get("opp_home_cons", false)) or rng.randf() < 0.5
			var n: int = ms.consecrated
			return {"EOT": 6 if n >= 3 else (3 if n >= 1 else 0),
				"C": ((4 if h.non_home > 0 else 0) + (4 if _more(c) else 0)) if r >= 2 else 0}
		"Destroyer's Wrath":
			return {"EOT": (3 if nk > 0 else 0) + (4 if (r >= 2 and nk > int(c.lost_prev)) else 0),
				"C": ((4 if h.non_home > 0 else 0) + (6 if _more(c) else 0)) if r >= 2 else 0}
		"Meatgrinder":
			var mg := 3 if nk > 0 else 0
			if r >= 2:
				mg += (5 if nk > int(c.lost_prev) else 0) + (5 if h.opp_home > 0 else 0)
			return {"EOT": mg, "C": 4 if (r >= 2 and h.non_home > 0) else 0}
		"Punishment":
			var pc: float = minf(1.0, 3.0 / float(maxi(1, int(c.enemy_alive) + nk)))
			return {"EOT": 5 if _any_kill_roll(c.kills, pc, rng) else 0,
				"C": ((4 if h.non_home > 0 else 0) + (5 if _more(c) else 0)) if r >= 2 else 0}
		"Unstoppable Force":
			return {"EOT": (3 if nk > 0 else 0) + (3 if (r >= 2 and int(c.newly) > 0) else 0),
				"C": 4 * h.non_home if r >= 2 else 0}
		"Gather Intel":
			var eot := 6 if (r == 1 and h.central > 0) else 0
			if r >= 2:
				var done := _binom(h.nml, p_act, rng)
				ms["markers"] = int(ms.get("markers", 0)) + done
				if done > 0 and h.opp_home > 0:
					ms["marker_opp_home"] = true
				eot += 7 * done
			return {"EOT": eot, "C": 4 if (r >= 2 and h.non_home > 0) else 0}
		"Reconnaissance Sweep":
			var q := _quarters(c)
			return {"EOT": (6 if q >= 4 else (3 if q >= 3 else 0)) + nk, "C": 3 if (r >= 2 and h.non_home > 0) else 0}
		"Search and Scour":
			return {"EOT": (3 if h.central > 0 else 0) + (2 if _any_kill_roll(c.kills, 0.4, rng) else 0),
				"C": 4 * h.non_home if r >= 2 else 0}
		"Surveil the Foe":
			return {"EOT": (4 if rng.randf() < p_act else 0) + (5 if (r >= 2 and rng.randf() < 0.5 * p_act) else 0),
				"C": ((4 if h.non_home > 0 else 0) + (4 if _more(c) else 0)) if r >= 2 else 0}
		"Triangulation":
			if r >= 2 and h.total > 0 and rng.randf() < p_act:
				var tri: int = int(ms.get("tri", 0))
				ms["tri"] = mini(h.total + tri, tri + 1)
			var t: int = int(ms.get("tri", 0))
			return {"EOT": (10 if t >= 3 else (6 if t == 2 else (3 if t == 1 else 0))) if r >= 2 else 0,
				"C": 4 if (r >= 2 and h.non_home > 0) else 0}
		"Extract Relic":
			return {"EOT": (4 if (h.central > 0 and rng.randf() < p_act) else 0) + (3 if _killed_on_objective(c) else 0)
				+ (4 if (r >= 4 and rng.randf() < 0.3 * p_act) else 0),
				"C": 4 if (r >= 2 and h.non_home > 0) else 0}
		"Sabotage":
			var own := _binom(h.non_home - h.opp_territory, p_act, rng)
			var deep := _binom(h.opp_territory, p_act, rng)
			return {"EOT": 3 * own + 5 * deep, "C": 4 if (r >= 2 and h.non_home > 0) else 0}
		"Secure Asset":
			return {"EOT": (4 if (h.non_home > 0 and rng.randf() < p_act) else 0) + (2 if _any_kill_roll(c.kills, 0.25, rng) else 0),
				"C": ((4 if h.non_home > 0 else 0) + (4 if h.total >= 3 else 0)) if r >= 2 else 0}
		"Vanguard Operation":
			var pv: float = p_act * (0.25 if r == 1 else (0.55 if r == 2 else 0.7))
			return {"EOT": (4 if rng.randf() < pv else 0) + (2 if nk > 0 else 0),
				"C": 4 if (r >= 2 and h.non_home > 0) else 0}
		"Vital Link":
			if h.central > 0 and rng.randf() < p_act:
				ms["links"] = int(ms.get("links", 0)) + 1
			return {"EOT": (2 + int(ms.get("links", 0))) if h.central > 0 else 0,
				"C": (4 + (4 if h.central > 0 else 0)) if (r >= 2 and h.non_home > 0) else 0}
		"Death Trap":
			var dt := 0
			if rng.randf() < p_act:
				dt += 2
				if rng.randf() < 0.5:
					dt += 3
				ms["traps"] = int(ms.get("traps", 0)) + 1
			if int(ms.get("traps", 0)) > 0 and _any_kill_roll(c.kills, 0.3, rng):
				dt += 3
			return {"EOT": dt, "C": 4 if (r >= 2 and h.non_home > 0) else 0}
		"Delaying Action":
			return {"EOT": 2 * nk + (3 if (r >= 2 and h.central > 0 and (h.exp + h.opp_exp) > 0) else 0),
				"C": 4 if (r >= 2 and h.non_home > 0) else 0}
		"Locate and Deny":
			return {"EOT": (4 if _killed_on_objective(c) else 0) + (4 if (r >= 4 and rng.randf() < 0.3 * p_act) else 0),
				"C": 4 if (r >= 2 and h.non_home > 0) else 0}
		"Outmanoeuvre":
			return {"EOT": (10 if h.opp_home > 0 else 0) + (4 * h.non_home if r == 1 else (6 * h.non_home if r >= 4 else 0)),
				"C": 5 * h.non_home if (r == 2 or r == 3) else 0}
		"Smoke and Mirrors":
			var d := _binom(h.non_home, p_act, rng)
			var deep_d: int = mini(d, h.opp_territory)
			ms["decoyed"] = d
			return {"EOT": 2 * d + 2 * deep_d, "C": 4 if (r >= 2 and h.non_home > 0) else 0}
	return {"EOT": 0, "C": 0}

static func _end_of_battle(name: String, c: Dictionary) -> int:
	var h: Dictionary = c.h
	var rng: RandomNumberGenerator = c.rng
	var ms: Dictionary = c.ms
	var p_act: float = c.p_act
	match name:
		"Inescapable Dominion": return 5 if h.opp_home > 0 else 0
		"Consecrate": return 5 if bool(ms.get("opp_home_cons", false)) else 0
		"Punishment": return 8 if h.opp_home > 0 else 0
		"Unstoppable Force": return 5 if h.central > 0 else 0
		"Gather Intel": return (5 if int(ms.get("markers", 0)) >= 3 else 0) + (5 if bool(ms.get("marker_opp_home", false)) else 0)
		"Search and Scour": return 5 if rng.randf() < 0.5 else 0
		"Triangulation": return 10 if h.total >= 4 else 0
		"Extract Relic": return 5 if rng.randf() < 0.3 * p_act else 0
		"Vanguard Operation": return 10 if h.opp_home > 0 else 0
		"Vital Link": return 10 if h.opp_home > 0 else 0
		"Locate and Deny": return 5 if rng.randf() < 0.3 * p_act else 0
		"Smoke and Mirrors": return 10 if int(ms.get("decoyed", 0)) >= 4 else 0
	return 0

static func _rated(c: Dictionary, id: String, lo: int, hi: int) -> int:
	var p: float = clampf(float(c.rate.get(id, RATING_NORMAL)), 0.0, 1.0)
	var x: float = c.rng.randf()
	if x < p / 2.0:
		return hi
	if x < p:
		return lo
	return 0

static func _quarters(c: Dictionary) -> int:
	var p: float = clampf(float(c.rate.get("engage_on_all_fronts", RATING_NORMAL)), 0.0, 1.0)
	var x: float = c.rng.randf()
	return 4 if x < p / 2.0 else (3 if x < p else 2)

# ---------------------------------------------------------------------------
# Secondary cards: VP for this scoring moment

static func _score_secondary(id: String, c: Dictionary) -> int:
	var r: int = c.r
	var h: Dictionary = c.h
	var rng: RandomNumberGenerator = c.rng
	var kills: Array = c.kills
	match id:
		"no_prisoners":
			return mini(5, 2 * kills.size())
		"overwhelming_force":
			var on := 0
			for v in kills:
				if bool(v.get("on_obj", false)):
					on += 1
			return mini(5, 3 * on)
		"assassination":
			for v in kills:
				if int(v.characters) > 0:
					return 5
			return 5 if (int(c.enemy_chars_left) == 0 and bool(c.enemy_had_chars)) else 0
		"bring_it_down":
			for v in kills:
				if int(v.w10) > 0:
					return 5
			return 0
		"a_grievous_blow":
			for v in kills:
				if bool(v.ss13):
					return 5
			return 0
		"a_tempting_target":
			return 5 if (h.total > 0 and rng.randf() < float(c.tempting_p)) else 0
		"defend_stronghold":
			if r < 2 or h.home <= 0:
				return 0
			return 3 + (2 if rng.randf() < 0.5 else 0)
		"beacon":
			return _rated(c, id, 3, 5)
		"behind_enemy_lines":
			return _rated(c, id, 3, 5)
		"burden_of_trust":
			return mini(5, 2 * h.total)
		"centre_ground":
			return _rated(c, id, 3, 5)
		"cleanse":
			var n := _binom(h.non_home, float(c.p_act), rng)
			return 5 if n >= 2 else (2 if n == 1 else 0)
		"display_of_might":
			var met: bool = rng.randf() < clampf(float(c.rate.get(id, RATING_NORMAL)), 0.0, 1.0)
			return (5 if c.timing == "opp" else 2) if met else 0
		"engage_on_all_fronts":
			var q: int = _rated(c, id, 3, 4)
			if q == 0:
				q = 2
			if bool(c.get("fixed_mode", false)):
				return 4 if q >= 4 else (2 if q >= 3 else 0)
			return 5 if q >= 4 else (3 if q >= 3 else 0)
		"forward_position":
			return 5 if (h.opp_home > 0 or h.exp + h.opp_exp >= 2) else 0
		"outflank":
			return _rated(c, id, 3, 5)
		"plunder":
			return _rated(c, id, 5, 5)
		"secure_no_mans_land":
			return 5 if h.nml >= 2 else 0
	return 0

static func _score_fixed(id: String, c: Dictionary) -> int:
	match id:
		"assassination":
			var a := 0
			for v in c.kills:
				a += 3 * int(v.characters) + int(v.characters_w4)
			return a
		"bring_it_down":
			var b := 0
			for v in c.kills:
				b += 4 * int(v.w10)
			return b
		"a_grievous_blow":
			var g := 0
			for v in c.kills:
				if bool(v.ss13):
					g += 4
			return g
		"engage_on_all_fronts":
			if c.timing == "own":
				var c2: Dictionary = c.duplicate()
				c2["fixed_mode"] = true
				return _score_secondary(id, c2)
	return 0

# ---------------------------------------------------------------------------
# One game

static func _draw_card(st: Dictionary, rng: RandomNumberGenerator) -> String:
	if st.deck.is_empty():
		return ""
	var i: int = int(floor(rng.randf() * st.deck.size()))
	var id: String = st.deck[i]
	st.deck.remove_at(i)
	return id

static func _draw_with_rules(st: Dictionary, r: int, rng: RandomNumberGenerator) -> void:
	var guard := 0
	while guard < 12:
		guard += 1
		var id := _draw_card(st, rng)
		if id == "":
			return
		var card: Dictionary = CARDS.get(id, {})
		var reshuffle: bool = (r == 1 and id in ["behind_enemy_lines", "forward_position", "defend_stronghold"]) \
			or (card.has("pair") and st.hand.has(card.pair))
		if reshuffle:
			st.deck.append(id)
			continue
		if card_dead(id, st.enemy_alive):
			st.used.append(id)
			continue
		st.hand.append(id)
		st.drawn_at[id] = st.turn_no
		var stats: Dictionary = st.stats
		if not stats.has(id):
			stats[id] = {"drawn": 0, "vp": 0, "scored": 0}
		stats[id].drawn += 1
		return

static func _pick_victims(alive: Array, n: int, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for _i in range(n):
		if alive.is_empty():
			break
		var w: Array = []
		var tot := 0.0
		for u in alive:
			var wi := 1.0
			if int(u.characters) > 0 and int(u.models) <= int(u.characters):
				wi = 0.6
			elif int(u.w10) > 0:
				wi = 0.85
			w.append(wi)
			tot += wi
		var x: float = rng.randf() * tot
		var j := 0
		while j < w.size() - 1 and x > w[j]:
			x -= w[j]
			j += 1
		out.append(alive[j])
		alive.remove_at(j)
	return out

static func _add_primary(s: Dictionary, r: int, vp: int) -> void:
	var room: int = mini(PRIMARY_ROUND_CAP - int(s.prim[r - 1]), PRIMARY_CAP - int(s.prim_total))
	var g: int = maxi(0, mini(room, vp))
	s.prim[r - 1] += g
	s.prim_total += g

static func _add_secondary(s: Dictionary, r: int, vp: int) -> int:
	var room: int = mini(SECONDARY_ROUND_CAP - int(s.sec[r - 1]), SECONDARY_CAP - int(s.sec_total))
	var g: int = maxi(0, mini(room, vp))
	s.sec[r - 1] += g
	s.sec_total += g
	return g

static func _bank_card(s: Dictionary, id: String, g: int) -> void:
	if id == str(s.get("tagged", "")):
		s.tag_vp += g
	s.hand.erase(id)
	s.used.append(id)
	var stats: Dictionary = s.stats
	if not stats.has(id):
		stats[id] = {"drawn": 0, "vp": 0, "scored": 0}
	stats[id].vp += g
	stats[id].scored += 1

static func _score_secondaries(s: Dictionary, r: int, timing: String, env: Dictionary) -> void:
	var pl: Dictionary = s.pl
	var chars_left := 0
	for u in s.enemy_alive:
		chars_left += int(u.characters)
	var c := {
		"r": r, "timing": timing, "h": env.h, "h_opp": env.h_opp, "kills": env.kills, "rng": env.rng,
		"rate": pl.get("rate", {}), "p_act": float(pl.get("action_p", 0.7)),
		"tempting_p": float(pl.get("tempting_p", 0.45)),
		"enemy_chars_left": chars_left, "enemy_had_chars": s.enemy_had_chars,
	}
	if str(pl.get("mode", "tactical")) == "fixed":
		for id in pl.get("fixed", []):
			var before: int = int(s.fixed_vp.get(id, 0))
			var vp: int = mini(FIXED_CARD_CAP - before, _score_fixed(id, c))
			if vp > 0:
				var g := _add_secondary(s, r, vp)
				s.fixed_vp[id] = before + g
		return
	var rng: RandomNumberGenerator = env.rng
	for id in s.hand.duplicate():
		var card: Dictionary = CARDS.get(id, {})
		if card.is_empty():
			continue
		var when: String = card.timing
		if not (when == "any" or when == timing or id == "display_of_might"):
			continue
		if r < int(card.get("min_round", 0)):
			continue
		var vp := _score_secondary(id, c)
		# Display of Might: hold the 2 VP at the end of your turn when the 5 VP at
		# the end of theirs is likely
		if id == "display_of_might" and timing == "own" and vp > 0 and r < ROUNDS and rng.randf() < 0.5:
			vp = 0
		if vp > 0:
			_bank_card(s, id, _add_secondary(s, r, vp))
	# "end of your opponent's turn or the end of the fifth battle round": when you
	# take the last turn of the battle, those cards score at the end of it
	if timing == "own" and bool(env.last_turn):
		for id in s.hand.duplicate():
			var card2: Dictionary = CARDS.get(id, {})
			if card2.is_empty() or card2.timing != "opp":
				continue
			var c2: Dictionary = c.duplicate()
			c2["timing"] = "opp"
			var vp2 := _score_secondary(id, c2)
			if vp2 > 0:
				_bank_card(s, id, _add_secondary(s, r, vp2))

static func _dup_units(units: Array) -> Array:
	var out: Array = []
	for u in units:
		out.append(u.duplicate())
	return out

static func _sample_owners(objectives: Array, probs: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	"""One owner per objective from {obj_id: [p1, p2]} (the rest: nobody). One
	draw per objective whatever the numbers, so two plans stay on common
	random numbers."""
	var own := {}
	for o in objectives:
		var u := rng.randf()
		var pr = probs.get(o.id, null)
		if pr == null:
			own[o.id] = 0
			continue
		var p1: float = float(pr[0])
		own[o.id] = 1 if u < p1 else (2 if u < p1 + float(pr[1]) else 0)
	return own

static func _simulate_game(P: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var first: int = int(P.get("first", 0))
	if first != 1 and first != 2:
		first = 1 if rng.randf() < 0.5 else 2
	var order := [first, other(first)]
	var S := {}
	for X in [1, 2]:
		var pl: Dictionary = P.players[X]
		var start: Dictionary = pl.get("start", {})
		var out := {}
		for id in start.get("used", []):
			out[id] = true
		for id in start.get("hand", []):
			out[id] = true
		var deck: Array = []
		if start.has("deck"):
			for id in start.deck:
				if CARDS.has(id) and not out.has(id):
					deck.append(id)
		else:
			for id in card_ids():
				if not out.has(id):
					deck.append(id)
		var hand: Array = []
		for id in start.get("hand", []):
			if CARDS.has(id):
				hand.append(id)
		S[X] = {
			"X": X, "pl": pl, "deck": deck, "hand": hand, "used": (start.get("used", []) as Array).duplicate(),
			"prim": [0, 0, 0, 0, 0], "sec": [0, 0, 0, 0, 0],
			"prim_total": int(start.get("primary", 0)), "sec_total": int(start.get("secondary", 0)),
			"fixed_vp": (start.get("fixed_vp", {}) as Dictionary).duplicate(), "ms": {}, "stats": {},
			"lost_prev": 0, "drawn_at": {}, "turn_no": 0, "enemy_alive": [], "enemy_had_chars": false,
			"tagged": "", "tag_vp": 0,
		}
	for X in [1, 2]:
		var enemy_pl: Dictionary = P.players[other(X)]
		var dead := {}
		for n in enemy_pl.get("start", {}).get("destroyed", []):
			dead[n] = true
		var alive: Array = []
		var had := false
		for u in enemy_pl.army.units:
			if int(u.characters) > 0:
				had = true
			if not dead.has(u.name):
				alive.append(u.duplicate())
		S[X].enemy_alive = alive
		S[X].enemy_had_chars = had
	# extra_draw_for: draw one more card for that player now and track the VP it
	# brings (the value of New Orders / replacing a card = a fresh draw)
	var xd: int = int(P.get("extra_draw_for", 0))
	if xd == 1 or xd == 2:
		var before: Array = (S[xd].hand as Array).duplicate()
		_draw_with_rules(S[xd], int(P.get("start_round", 1)), rng)
		for id in S[xd].hand:
			if not before.has(id):
				S[xd].tagged = id
	var objectives: Array = P.objectives
	var obj_by_id := {}
	for o in objectives:
		obj_by_id[o.id] = o
	var conf_home: float = float(P.get("confidence", {}).get("home", 0.95))
	var conf_other: float = float(P.get("confidence", {}).get("other", 0.8))
	var obj_conf: Dictionary = P.get("obj_confidence", {})
	var plan: Dictionary = P.get("plan", {})
	var owners := {}
	for r in range(1, ROUNDS + 1):
		var cells: Dictionary = plan.get(r, {})
		var own := {}
		for o in objectives:
			var v: int = int(cells.get(o.id, 0))
			# a plan is not a certainty: a planned objective is lost to the other
			# side now and then (home objectives rarely); contested = coin flip
			var keep: float = conf_home if o.cls == "home" else conf_other
			if obj_conf.has(o.id):
				keep = float(obj_conf[o.id])
			if v == 0:
				own[o.id] = 1 if rng.randf() < 0.5 else 2
			else:
				own[o.id] = v if rng.randf() < keep else other(v)
		owners[r] = own
	var start_round: int = int(P.get("start_round", 1))
	var start_turn: int = int(P.get("start_turn", 0))
	var last_own := {1: {}, 2: {}}
	if P.has("prev_own"):
		last_own = (P.prev_own as Dictionary).duplicate(true)
	var f_obj: float = float(P.get("f_obj", 0.45))
	# turn_plan (AIPositionSim): the next player turns, in play order from the
	# start turn. Each entry: own_start / own_end {obj_id: [p1, p2]} = chance
	# each player controls it at the Command phase / at the end of that turn,
	# lam {1: x, 2: y} = expected units destroyed BY each player that turn.
	# The state after one turn is the state at the next one's Command phase, so
	# each boundary is sampled once. Turns past the list use the round model.
	var turn_plan: Array = P.get("turn_plan", [])
	var tp_states: Array = []
	for k in range(turn_plan.size()):
		var tp: Dictionary = turn_plan[k]
		if k == 0:
			tp_states.append(_sample_owners(objectives, tp.get("own_start", {}), rng))
		tp_states.append(_sample_owners(objectives, tp.get("own_end", {}), rng))
	var end_round: int = clampi(int(P.get("end_round", ROUNDS)), start_round, ROUNDS)
	var turn_k := -1
	for r in range(start_round, end_round + 1):
		for t in range(2):
			if r == start_round and t < start_turn:
				continue
			turn_k += 1
			var X: int = order[t]
			var Y: int = other(X)
			var sx: Dictionary = S[X]
			var sy: Dictionary = S[Y]
			sx.turn_no += 1
			sy.turn_no += 1
			var own: Dictionary = owners[r]
			var own_c: Dictionary = own  # at this turn's Command phase
			var planned: bool = turn_k < turn_plan.size()
			if planned:
				own_c = tp_states[turn_k]
				own = tp_states[turn_k + 1]
			var prev_own: Dictionary = last_own[X]
			last_own[X] = own
			var hx := _holdings(objectives, own, X)
			var hy := _holdings(objectives, own, Y)
			# --- Command phase: draw
			if str(sx.pl.get("mode", "tactical")) != "fixed":
				var skip_draw: bool = r == start_round and t == start_turn and bool(P.get("start_after_draw", false))
				if not skip_draw:
					for _d in range(DRAW_PER_TURN):
						_draw_with_rules(sx, r, rng)
			# --- kills this turn (by the active player; some fight-back by the other)
			var lam_x: float = float(sx.pl.get("kill_rate", DEFAULT_KILL_RATE)) * float(ROUND_KILL["first" if t == 0 else "second"][r - 1])
			var lam_y: float = 0.25 * float(sy.pl.get("kill_rate", DEFAULT_KILL_RATE))
			if planned and (turn_plan[turn_k] as Dictionary).has("lam"):
				var tl: Dictionary = turn_plan[turn_k].lam
				lam_x = float(tl.get(X, lam_x))
				lam_y = float(tl.get(Y, lam_y))
			var kills_x := _pick_victims(sx.enemy_alive, _poisson(lam_x, rng), rng)
			var kills_y := _pick_victims(sy.enemy_alive, _poisson(lam_y, rng), rng)
			for v in kills_x:
				v["on_obj"] = rng.randf() < f_obj
			for v in kills_y:
				v["on_obj"] = rng.randf() < f_obj
			# --- primary (active player): Command phase + end of turn
			var newly := 0
			for id in hx.ids:
				var o: Dictionary = obj_by_id[id]
				if int(prev_own.get(id, 0)) != X and not (o.cls == "home" and int(o.side) == X):
					newly += 1
			var mission: String = str(sx.pl.get("mission", ""))
			var prim_gain := 0
			var ctx := {"r": r, "h": hx, "h_opp": hy, "kills": kills_x, "lost_prev": sx.lost_prev, "newly": newly,
				"p_act": float(sx.pl.get("action_p", 0.7)), "ms": sx.ms, "rng": rng,
				"enemy_alive": sx.enemy_alive.size(), "rate": sx.pl.get("rate", {})}
			if mission != "":
				var v2 := _primary(mission, ctx)
				if planned:
					# Command-phase VP reads the holdings at the START of the turn
					# (mission state is advanced by the end-of-turn call only)
					var ctx_c: Dictionary = ctx.duplicate()
					ctx_c["h"] = _holdings(objectives, own_c, X)
					ctx_c["h_opp"] = _holdings(objectives, own_c, Y)
					ctx_c["ms"] = (sx.ms as Dictionary).duplicate(true)
					v2["C"] = int(_primary(mission, ctx_c).C)
				# starting mid-turn after the Command phase: its VP is already banked
				var c_vp: int = 0 if (r == start_round and t == start_turn and bool(P.get("skip_command_primary", false))) else int(v2.C)
				prim_gain += c_vp + int(v2.EOT)
				if r == ROUNDS and t == 1:
					prim_gain += _end_of_battle(mission, ctx)
			_add_primary(sx, r, prim_gain)
			# --- secondaries at the end of this turn: active player first
			var last_turn: bool = r == ROUNDS and t == 1
			_score_secondaries(sx, r, "own", {"h": hx, "h_opp": hy, "kills": kills_x, "rng": rng, "last_turn": last_turn})
			_score_secondaries(sy, r, "opp", {"h": hy, "h_opp": hx, "kills": kills_y, "rng": rng, "last_turn": last_turn})
			sy.lost_prev = kills_x.size()
			if r == ROUNDS and t == 1:
				var my: String = str(sy.pl.get("mission", ""))
				if my != "":
					var ctx_y := {"r": r, "h": hy, "h_opp": hx, "kills": [], "lost_prev": 0, "newly": 0,
						"p_act": float(sy.pl.get("action_p", 0.7)), "ms": sy.ms, "rng": rng,
						"enemy_alive": sy.enemy_alive.size(), "rate": sy.pl.get("rate", {})}
					_add_primary(sy, r, _end_of_battle(my, ctx_y))
	var res := {}
	for X in [1, 2]:
		var s: Dictionary = S[X]
		var br: int = 0 if s.pl.get("battle_ready", true) == false else BATTLE_READY
		res[X] = {"prim_total": s.prim_total, "sec_total": s.sec_total, "total": s.prim_total + s.sec_total + br,
			"stats": s.stats, "prim": s.prim, "sec": s.sec, "tag_vp": s.tag_vp}
	return res

# ---------------------------------------------------------------------------
# Public: forecast

static func forecast(P: Dictionary) -> Dictionary:
	"""Simulate the rest of the battle `trials` times.
	P: { players: {1: {mission, mode, fixed, army, kill_rate, action_p, rate,
	       tempting_p, battle_ready, start: {hand, used, deck, primary, secondary,
	       destroyed, fixed_vp}}, 2: {...}},
	     objectives: [{id, cls, side}], plan: {round: {obj_id: 1|2|0}},
	     confidence: {home, other}, obj_confidence: {obj_id: p}, prev_own,
	     first, start_round, start_turn, start_after_draw, trials, seed, f_obj }
	Returns {trials, mean: {1, 2}, sd: {1, 2}, p_win: {1, 2}, p_draw,
	         margin_mean (P1 - P2), cards: {1: {id: {per_draw, draw_rate}}, 2: ...}}"""
	var trials: int = maxi(1, int(P.get("trials", 400)))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(P.get("seed", 0xC0FFEE))
	var sum := {1: 0.0, 2: 0.0}
	var sq := {1: 0.0, 2: 0.0}
	var win := {1: 0, 2: 0}
	var draw := 0
	var margin := 0.0
	var cards := {1: {}, 2: {}}
	var tag := {1: 0.0, 2: 0.0}
	# crn: reseed every trial, so two forecasts that differ in one input stay
	# on common random numbers trial by trial (their difference is then far
	# less noisy than two independent runs)
	var crn: bool = bool(P.get("crn", false))
	var base_seed: int = int(P.get("seed", 0xC0FFEE))
	for _i in range(trials):
		if crn:
			rng.seed = base_seed + 7919 * (_i + 1)
		var g := _simulate_game(P, rng)
		for X in [1, 2]:
			tag[X] += float(g[X].tag_vp)
			var tot: float = float(g[X].total)
			sum[X] += tot
			sq[X] += tot * tot
			for id in g[X].stats:
				var st: Dictionary = g[X].stats[id]
				if not cards[X].has(id):
					cards[X][id] = {"drawn": 0, "vp": 0}
				cards[X][id].drawn += int(st.drawn)
				cards[X][id].vp += int(st.vp)
		var d: float = float(g[1].total) - float(g[2].total)
		margin += d
		if d > 0.0:
			win[1] += 1
		elif d < 0.0:
			win[2] += 1
		else:
			draw += 1
	var out := {"trials": trials, "mean": {}, "sd": {}, "p_win": {}, "cards": {1: {}, 2: {}}}
	for X in [1, 2]:
		var m: float = sum[X] / trials
		out.mean[X] = m
		out.sd[X] = sqrt(maxf(0.0, sq[X] / trials - m * m))
		out.p_win[X] = float(win[X]) / trials
		for id in cards[X]:
			var a: Dictionary = cards[X][id]
			out.cards[X][id] = {"per_draw": float(a.vp) / a.drawn if a.drawn > 0 else 0.0,
				"draw_rate": float(a.drawn) / trials, "vp_per_game": float(a.vp) / trials}
	out["p_draw"] = float(draw) / trials
	out["tag_vp"] = {1: tag[1] / trials, 2: tag[2] / trials}
	out["margin_mean"] = margin / trials
	return out

# ---------------------------------------------------------------------------
# Live game -> forecast inputs

const PHASE_COMMAND := 6

static func _num(v, d = 0):
	if v == null:
		return d
	return v

static func objectives_from_snapshot(snapshot: Dictionary) -> Array:
	"""[{id, cls, side, pos}] from board.objectives. An expansion objective
	belongs to the half whose home objective is closer."""
	var objs: Array = snapshot.get("board", {}).get("objectives", [])
	var removed: Array = snapshot.get("mission_manager", {}).get("removed_objectives", [])
	var homes := {}
	for o in objs:
		if str(o.get("designation", "")) == "home":
			var z := str(o.get("zone", ""))
			homes[1 if z == "player1" else 2] = _pos(o.get("position"))
	var out: Array = []
	for o in objs:
		var id := str(o.get("id", ""))
		if id == "" or id in removed:
			continue
		var des := str(o.get("designation", ""))
		var zone := str(o.get("zone", ""))
		var pos := _pos(o.get("position"))
		var cls := "central"
		var side := 0
		if des == "home" or zone == "player1" or zone == "player2":
			cls = "home"
			side = 1 if zone == "player1" else 2
		elif des == "expansion":
			cls = "exp"
			if homes.has(1) and homes.has(2):
				side = 1 if pos.distance_to(homes[1]) <= pos.distance_to(homes[2]) else 2
		out.append({"id": id, "cls": cls, "side": side, "pos": pos})
	return out

static func _pos(v) -> Vector2:
	if v is Vector2:
		return v
	if v is Dictionary:
		return Vector2(float(v.get("x", 0.0)), float(v.get("y", 0.0)))
	if v is String:
		var s: String = v.strip_edges().trim_prefix("(").trim_suffix(")")
		var parts := s.split(",")
		if parts.size() == 2:
			return Vector2(float(parts[0]), float(parts[1]))
	return Vector2.ZERO

static func army_from_snapshot(snapshot: Dictionary, player: int) -> Dictionary:
	"""{army: profile (every unit, alive or not), destroyed: [unit ids]}"""
	var units: Array = []
	var destroyed: Array = []
	var su: Dictionary = snapshot.get("units", {})
	for uid in su:
		var u: Dictionary = su[uid]
		if int(_num(u.get("owner"), 0)) != player:
			continue
		var meta: Dictionary = u.get("meta", {})
		var kws: Array = meta.get("keywords", [])
		var models: Array = u.get("models", [])
		var alive := 0
		var w10 := 0
		var w4 := 0
		for m in models:
			if not bool(m.get("alive", true)):
				continue
			alive += 1
			var w := int(_num(m.get("wounds"), _num(meta.get("stats", {}).get("wounds"), 1)))
			if w >= 10:
				w10 += 1
			if w >= 4:
				w4 += 1
		var is_char: bool = "CHARACTER" in kws
		var ss := int(_num(meta.get("starting_strength"), models.size()))
		units.append({"name": str(uid), "models": maxi(alive, 1),
			"characters": alive if is_char else 0, "characters_w4": w4 if is_char else 0,
			"w10": w10, "ss13": ss >= 13, "aircraft": "AIRCRAFT" in kws})
		if alive == 0:
			destroyed.append(str(uid))
	return {"army": army_profile(units), "destroyed": destroyed}

static func kills_by_player(snapshot: Dictionary) -> Dictionary:
	var kpr = snapshot.get("mission_manager", {}).get("kills_per_round", {})
	var out := {1: 0, 2: 0}
	if kpr is Dictionary:
		for r in kpr:
			var row = kpr[r]
			if row is Dictionary:
				out[1] += int(_num(row.get("1", row.get(1, 0)), 0))
				out[2] += int(_num(row.get("2", row.get(2, 0)), 0))
	return out

static func turn_order(snapshot: Dictionary) -> Dictionary:
	var meta: Dictionary = snapshot.get("meta", {})
	var first := int(_num(meta.get("first_turn_player"), 1))
	if first != 1 and first != 2:
		first = 1
	var active := int(_num(meta.get("active_player"), first))
	var rnd := int(_num(meta.get("battle_round"), 1))
	return {"first": first, "active": active, "round": rnd, "turn_idx": 0 if active == first else 1,
		"phase": int(_num(meta.get("phase"), PHASE_COMMAND))}

static func turns_done(order: Dictionary, player: int) -> int:
	"""Turns this player has finished (the current turn is not counted)."""
	var done: int = int(order.round) - 1
	if player == int(order.first) and int(order.turn_idx) == 1:
		done += 1
	return maxi(done, 0)

static func build_from_snapshot(snapshot: Dictionary, opts: Dictionary = {}) -> Dictionary:
	"""Forecast inputs for the rest of the game from a live snapshot.
	opts:
	  from: "this_turn" (default; the active player's draw is done) or
	        "next_turn" (the current turn is over — scoring-phase decisions)
	  rates: {player: {card_id: p}} per-turn chance for position cards
	  plan: {round: {obj_id: 1|2|0}} ownership override (default: current
	        control persists)
	  obj_confidence: {obj_id: p}; trials; seed
	Returns P for forecast(), or {} when the battle is over."""
	var order := turn_order(snapshot)
	var start_round: int = order.round
	var start_turn: int = order.turn_idx
	var after_draw := true
	var skip_c: bool = int(order.phase) > PHASE_COMMAND
	if str(opts.get("from", "this_turn")) == "next_turn":
		after_draw = false
		skip_c = false
		if start_turn == 0:
			start_turn = 1
		else:
			start_turn = 0
			start_round += 1
	if start_round > ROUNDS:
		return {}
	var mm: Dictionary = snapshot.get("mission_manager", {})
	var control: Dictionary = mm.get("objective_control_state", {})
	var objectives := objectives_from_snapshot(snapshot)
	var plan := {}
	var given_plan: Dictionary = opts.get("plan", {})
	for r in range(1, ROUNDS + 1):
		if given_plan.has(r):
			plan[r] = given_plan[r]
			continue
		var cells := {}
		for o in objectives:
			cells[o.id] = int(_num(control.get(o.id), 0))
		plan[r] = cells
	var kills := kills_by_player(snapshot)
	var sm_state: Dictionary = snapshot.get("secondary_missions", {}).get("player_state", {})
	var primaries: Dictionary = mm.get("player_primary_missions", {})
	var players := {}
	var rates: Dictionary = opts.get("rates", {})
	for X in [1, 2]:
		var ps: Dictionary = snapshot.get("players", {}).get(str(X), {})
		var st: Dictionary = sm_state.get(str(X), {})
		var mode := str(st.get("mode", "tactical"))
		var hand: Array = []
		for m in st.get("active", []):
			hand.append(str(m.get("id", "")))
		var used: Array = []
		for id in st.get("discard", []):
			used.append(str(id))
		var deck: Array = []
		for id in st.get("deck", []):
			deck.append(str(id))
		var army := army_from_snapshot(snapshot, X)
		var td := turns_done(order, X)
		var kr: float = (DEFAULT_KILL_RATE * 2.0 + float(kills[X])) / (2.0 + float(td))
		var start := {"hand": hand, "used": used, "primary": int(_num(ps.get("primary_vp"), 0)),
			"secondary": int(_num(ps.get("secondary_vp"), 0)), "destroyed": [],
			"fixed_vp": st.get("vp_by_mission", {})}
		if bool(st.get("initialized", false)):
			start["deck"] = deck
		var card: Dictionary = primaries.get(str(X), {})
		players[X] = {"mission": str(card.get("name", "")), "mode": mode,
			"fixed": hand if mode == "fixed" else [], "army": army.army,
			"kill_rate": kr, "action_p": 0.7, "rate": rates.get(X, {}), "start": start}
	# a unit destroyed is dead for the enemy's kill cards
	for X in [1, 2]:
		players[X].start["destroyed"] = army_from_snapshot(snapshot, X).destroyed
	var prev := {1: {}, 2: {}}
	for X in [1, 2]:
		for o in objectives:
			prev[X][o.id] = int(_num(control.get(o.id), 0))
	return {"players": players, "objectives": objectives, "plan": plan, "first": order.first,
		"start_round": start_round, "start_turn": start_turn, "start_after_draw": after_draw,
		"skip_command_primary": skip_c, "prev_own": prev,
		"obj_confidence": opts.get("obj_confidence", {}),
		"trials": int(opts.get("trials", 400)),
		"seed": int(opts.get("seed", 1000003 * start_round + 7919 * start_turn + 17))}

static func secondary_values(P: Dictionary, player: int) -> Dictionary:
	"""Expected VP each card in `player`'s hand brings over the rest of the
	game (keep), and what one card drawn now would bring (draw_now).
	Two runs on the same seed: the baseline and one with an extra draw."""
	var base := forecast(P)
	var keep := {}
	for id in P.players[player].start.get("hand", []):
		keep[id] = float(base.cards[player].get(id, {}).get("vp_per_game", 0.0))
	var draw_now := 0.0
	var deck_left: int = (P.players[player].start.get("deck", CARDS.keys()) as Array).size()
	if deck_left > 0 and str(P.players[player].get("mode", "tactical")) != "fixed":
		var P2 := P.duplicate()
		P2["extra_draw_for"] = player
		draw_now = float(forecast(P2).tag_vp[player])
	return {"keep": keep, "draw_now": draw_now, "base": base}
