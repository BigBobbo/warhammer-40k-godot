extends RefCounted
class_name AIPositionSim

# AIPositionSim — a position-aware look-ahead for the game forecast.
#
# AIForecast.gd sees who holds each objective, not where anything is. This
# plays the next few player turns forward on the real positions, in expected
# values (no dice): units walk toward objectives at their Move, shoot and
# charge what they can reach, and lose a share of their strength to the
# expected damage coming back. The output is what the forecast needs —
# per player turn, the chance each side controls each objective at the
# Command phase and at the end of the turn, and the units each side is
# expected to destroy — as AIForecast `turn_plan` rows.
#
# Pure data in, pure data out (AIDecisionMaker._possim_world builds the world
# from a snapshot), so it can be unit-tested without a game.
#
# world: { units: {uid: U}, objectives: [{id, pos}], first, round, active,
#          control: {obj_id: player}, secured: {obj_id: player} }
#   U: { side, pos (Vector2, inches), move, oc (unit total), wounds (unit
#        total left), radius (inches, models' spread), seeker (chases
#        enemies), charger (charges what it can reach),
#        shoot: {target_uid: [[range_in, dmg], ...]}, melee: {target_uid: dmg},
#        acted (bool: already moved this turn) }
# intents: {uid: {goal: Vector2 | null, goal_obj: String, mode: "move" |
#          "advance" | "stay", target: uid}} for the active side THIS turn
# opts: { end_round, damage (bool), policy (bool), los, ... } see DEFAULTS

const CONTROL_IN := 3.0
const ADVANCE_IN := 3.5
const ENGAGE_IN := 1.0
const DEFAULTS := {
	"damage": true,      # shooting / melee wear units down
	"policy": true,      # units without an intent pick objectives themselves
	"los": 0.5,          # share of in-range shooting that has line of sight
	"lethality": 0.7,    # all expected damage x this (fitted: units really lost per turn)
	"charge_min_p": 0.35, # a unit charges when 2D6 makes it at least this often
	"oc_soft": 3.0,      # OC lead that makes control near-certain (plus 15% of the OC there)
	"ctrl_c": 5.5,       # control reach from the unit's centre, inches ...
	"ctrl_m": 3.0,       # ... plus this many times its models' mean spread
	"stick": 0.7,        # an objective nobody out-OCs stays with its last controller this often
	"sim_turns": 0,      # play only this many player turns, then hold ownership as it stands
	                     # to the end of the window (0 = play every turn). 1 = "what does
	                     # this move take or lose THIS turn" — the part real games bear out
	"sat_penalty": 1.5,  # turns added to an objective the side already out-OCs
}

static func other(p: int) -> int:
	return 2 if p == 1 else 1

static func p_dead(x: float) -> float:
	"""Chance a unit is gone once expected damage is x times its wounds."""
	return clampf((x - 0.6) / 0.8, 0.0, 1.0)

static func alive(u: Dictionary) -> float:
	"""Share of the unit's OC and output still standing."""
	var x: float = float(u.get("x", 0.0))
	return (1.0 - p_dead(x)) * maxf(0.2, 1.0 - x)

static func charge_p(d: float) -> float:
	"""P(2D6 >= d)."""
	var need: int = int(ceil(d))
	if need <= 2:
		return 1.0
	if need > 12:
		return 0.0
	var ways := 0
	for a in range(1, 7):
		for b in range(1, 7):
			if a + b >= need:
				ways += 1
	return float(ways) / 36.0

static func _edge(a: Dictionary, b: Dictionary) -> float:
	return (a.pos as Vector2).distance_to(b.pos) - float(a.radius) - float(b.radius)

static func oc_weight(u: Dictionary, opos: Vector2, opts: Dictionary = {}) -> float:
	"""Share of the unit's models in range of the objective, from its centre
	and spread: all of them when the centre is close, none once the centre is
	ctrl_c + ctrl_m x spread away. Fitted on real games (possim_truth.py): a
	unit strung out toward an objective holds it with its front models while
	its centre is still 6-7 in short."""
	var d: float = (u.pos as Vector2).distance_to(opos)
	var reach: float = float(opts.get("ctrl_m", DEFAULTS.ctrl_m)) * float(u.radius)
	return clampf((float(opts.get("ctrl_c", DEFAULTS.ctrl_c)) + reach - d) / (2.0 * reach), 0.0, 1.0)

static func oc_at(units: Dictionary, opos: Vector2, opts: Dictionary = {}) -> Dictionary:
	var oc := {1: 0.0, 2: 0.0}
	for uid in units:
		var u: Dictionary = units[uid]
		var w := oc_weight(u, opos, opts)
		if w > 0.0:
			oc[int(u.side)] += float(u.oc) * alive(u) * w
	return oc

static func ownership(units: Dictionary, objectives: Array, opts: Dictionary, prev: Dictionary = {}, secured: Dictionary = {}) -> Dictionary:
	"""{obj_id: [p1, p2]}: chance each side controls it right now.
	prev {obj_id: [p1, p2]}: who controlled it a turn ago. What OC does not
	decide (nobody in range, or a tie) stays with the previous controller
	`stick` of the time — in real games an objective usually outlives its
	holders walking off (11e secured objectives, and front models the centre
	distance misses). secured {obj_id: player}: stays for certain (14.03)
	until the other side out-OCs it."""
	var out := {}
	var soft: float = float(opts.get("oc_soft", DEFAULTS.oc_soft))
	var stick: float = float(opts.get("stick", DEFAULTS.stick))
	for o in objectives:
		var oc := oc_at(units, o.pos, opts)
		var a: float = oc[1]
		var b: float = oc[2]
		var p1 := 0.0
		var p2 := 0.0
		if a + b >= 0.25:
			var s: float = soft + 0.15 * (a + b)
			var q: float = 1.0 / (1.0 + exp(-(a - b) / (s * 0.5)))
			# a near-tie is mostly nobody's (equal OC controls nothing)
			var tie: float = exp(-pow((a - b) / s, 2.0)) * 0.5
			p1 = q * (1.0 - tie)
			p2 = (1.0 - q) * (1.0 - tie)
		var free: float = maxf(0.0, 1.0 - p1 - p2)
		var pv: Array = prev.get(o.id, [0.0, 0.0])
		var sp: int = int(secured.get(o.id, 0))
		var k1: float = 1.0 if sp == 1 else stick
		var k2: float = 1.0 if sp == 2 else stick
		out[o.id] = [p1 + free * k1 * float(pv[0]), p2 + free * k2 * float(pv[1])]
	return out

static func _engaged(u: Dictionary, units: Dictionary) -> bool:
	for vid in units:
		var v: Dictionary = units[vid]
		if int(v.side) != int(u.side) and alive(v) > 0.03 and _edge(u, v) <= ENGAGE_IN + 0.5:
			return true
	return false

static func _hit(units: Dictionary, tid: String, dmg: float, by_side: int, kills: Dictionary) -> void:
	var t: Dictionary = units[tid]
	var before := p_dead(float(t.x))
	t["x"] = float(t.x) + dmg * float(kills.get("scale", 1.0)) / maxf(1.0, float(t.wounds))
	kills[by_side] += p_dead(float(t.x)) - before

static func _shoot_dmg(u: Dictionary, tid: String, d_edge: float) -> float:
	var total := 0.0
	for row in u.shoot.get(tid, []):
		if float(row[0]) >= d_edge:
			total += float(row[1])
	return total

static func _move_toward(u: Dictionary, goal: Vector2, dist_in: float, units: Dictionary) -> void:
	var from: Vector2 = u.pos
	var d: float = from.distance_to(goal)
	if d < 0.05:
		return
	var step: float = minf(dist_in, d)
	var dir: Vector2 = (goal - from) / d
	# a move cannot end inside an enemy unit's engagement range: back off
	while step > 0.0:
		u["pos"] = from + dir * step
		var blocked := false
		for vid in units:
			var v: Dictionary = units[vid]
			if int(v.side) != int(u.side) and alive(v) > 0.03 and _edge(u, v) < ENGAGE_IN + 0.1:
				blocked = true
				break
		if not blocked:
			return
		step -= 0.5
	u["pos"] = from

static func _pick_objective(u: Dictionary, units: Dictionary, objectives: Array, committed: Dictionary, opts: Dictionary, skip_id: String = "") -> Dictionary:
	var best := {}
	var best_s := INF
	var side: int = int(u.side)
	for o in objectives:
		if str(o.id) == skip_id:
			continue
		var d: float = maxf(0.0, (u.pos as Vector2).distance_to(o.pos) - CONTROL_IN)
		var turns: float = ceil(d / maxf(1.0, float(u.move)))
		var oc := oc_at(units, o.pos, opts)
		var mine: float = float(committed[side].get(o.id, 0.0))
		var s: float = turns
		if mine > maxf(oc[other(side)], 0.5):
			s += float(opts.get("sat_penalty", DEFAULTS.sat_penalty))
		if s < best_s:
			best_s = s
			best = o
	return best

static func run(world: Dictionary, intents: Dictionary, opts_in: Dictionary = {}) -> Dictionary:
	"""Play from the active side's Movement phase to the end of opts.end_round.
	Returns {turns: [{round, side, own_start, own_end, lam: {1, 2}}], units}."""
	var opts: Dictionary = DEFAULTS.duplicate()
	for k in opts_in:
		opts[k] = opts_in[k]
	var units := {}
	for uid in world.units:
		var u: Dictionary = (world.units[uid] as Dictionary).duplicate()
		u["x"] = float(u.get("x", 0.0))
		u["goal_obj"] = ""
		units[uid] = u
	var objectives: Array = world.objectives
	var obj_pos := {}
	for o in objectives:
		obj_pos[o.id] = o.pos
	var first: int = int(world.get("first", 1))
	var active: int = int(world.get("active", first))
	var start_round: int = int(world.get("round", 1))
	var end_round: int = int(opts.get("end_round", start_round + 1))
	var do_damage: bool = bool(opts.damage)
	var do_policy: bool = bool(opts.policy)
	var los: float = float(opts.los)
	var turns: Array = []
	var first_turn := true
	# who controls each objective now (world.control {obj_id: player}); the
	# sim carries this forward turn by turn
	var secured: Dictionary = world.get("secured", {})
	var prev_own := {}
	for o in objectives:
		var cp: int = int(world.get("control", {}).get(o.id, 0))
		prev_own[o.id] = [1.0 if cp == 1 else 0.0, 1.0 if cp == 2 else 0.0]
	for r in range(start_round, end_round + 1):
		for t in range(2):
			var side: int = first if t == 0 else other(first)
			if r == start_round and t == 0 and active != first:
				continue
			var row := {"round": r, "side": side, "own_start": prev_own.duplicate(true)}
			if int(opts.sim_turns) > 0 and turns.size() >= int(opts.sim_turns):
				# past the played turns: nothing moves, ownership stands, and the
				# forecast keeps its own kill rates (no "lam")
				row["own_end"] = prev_own.duplicate(true)
				if bool(opts.get("trace", false)):
					row["units"] = (turns[turns.size() - 1] as Dictionary).get("units", {})
					row["oc_end"] = (turns[turns.size() - 1] as Dictionary).get("oc_end", {})
				turns.append(row)
				continue
			var kills := {1: 0.0, 2: 0.0, "scale": float(opts.lethality)}
			# --- Movement
			var committed := {1: {}, 2: {}}
			for uid in units:
				var cu: Dictionary = units[uid]
				for o in objectives:
					var w := oc_weight(cu, o.pos, opts)
					if w >= 0.5 or str(cu.goal_obj) == str(o.id):
						committed[int(cu.side)][o.id] = float(committed[int(cu.side)].get(o.id, 0.0)) + float(cu.oc) * alive(cu)
			# one keeper per objective: the unit of this side nearest its centre.
			# In real games a unit alone on an objective stays (93%); of units
			# sharing one, about half move on (possim_truth.py).
			var keeper := {}
			var keeper_d := {}
			for uid in units:
				var ku: Dictionary = units[uid]
				if int(ku.side) != side or alive(ku) <= 0.03 or float(ku.oc) <= 0.0:
					continue
				for o in objectives:
					if oc_weight(ku, o.pos, opts) >= 0.5:
						var kd: float = (ku.pos as Vector2).distance_to(o.pos)
						if not keeper_d.has(o.id) or kd < float(keeper_d[o.id]):
							keeper_d[o.id] = kd
							keeper[o.id] = uid
			var advanced := {}
			for uid in units:
				var u: Dictionary = units[uid]
				if int(u.side) != side or alive(u) <= 0.03:
					continue
				var goal = null
				var mode := "move"
				if first_turn:
					if not intents.has(uid):
						continue  # already moved, or nothing planned: stays
					var it: Dictionary = intents[uid]
					mode = str(it.get("mode", "move"))
					if mode == "stay":
						u["goal_obj"] = str(it.get("goal_obj", ""))
						continue
					goal = it.get("goal", null)
					u["goal_obj"] = str(it.get("goal_obj", ""))
					if goal == null and it.has("target") and units.has(it.target):
						goal = units[it.target].pos
				else:
					if _engaged(u, units):
						continue
					if str(u.goal_obj) != "" and obj_pos.has(u.goal_obj):
						goal = obj_pos[u.goal_obj]
					elif not do_policy:
						continue
					else:
						if bool(u.get("seeker", false)):
							var near := INF
							for vid in units:
								var v: Dictionary = units[vid]
								if int(v.side) != side and alive(v) > 0.03:
									var e := _edge(u, v)
									if e < near and e <= float(u.move) + 9.0:
										near = e
										goal = v.pos
						if goal == null:
							var on_oid := ""
							for o in objectives:
								if oc_weight(u, o.pos, opts) >= 0.5:
									on_oid = str(o.id)
									break
							if on_oid != "" and (str(keeper.get(on_oid, "")) == str(uid) or not keeper.has(on_oid)):
								continue
							var pick := _pick_objective(u, units, objectives, committed, opts, on_oid)
							if pick.is_empty():
								continue
							goal = pick.pos
							u["goal_obj"] = str(pick.id)
							committed[side][pick.id] = float(committed[side].get(pick.id, 0.0)) + float(u.oc) * alive(u)
					# a unit with nothing to shoot after a normal move advances
					if goal != null and (u.pos as Vector2).distance_to(goal) > float(u.move) + CONTROL_IN:
						var can_shoot := false
						for vid in u.shoot:
							if units.has(vid) and alive(units[vid]) > 0.03 and _shoot_dmg(u, vid, _edge(u, units[vid]) - float(u.move)) > 0.0:
								can_shoot = true
								break
						if not can_shoot:
							mode = "advance"
				if goal == null:
					continue
				var reach: float = float(u.move) + (ADVANCE_IN if mode == "advance" else 0.0)
				if mode == "advance":
					advanced[uid] = true
				_move_toward(u, goal, reach, units)
				if str(u.goal_obj) != "" and obj_pos.has(u.goal_obj) and (u.pos as Vector2).distance_to(obj_pos[u.goal_obj]) <= 1.5:
					u["goal_obj"] = ""  # arrived: holds from now on
					u["holding"] = true
			if do_damage:
				# --- Shooting (active side)
				for uid in units:
					var u: Dictionary = units[uid]
					if int(u.side) != side or alive(u) <= 0.03 or advanced.has(uid) or (u.shoot as Dictionary).is_empty():
						continue
					if _engaged(u, units):
						continue
					var best_t := ""
					var best_v := 0.0
					var best_d := 0.0
					for tid in u.shoot:
						if not units.has(tid):
							continue
						var tu: Dictionary = units[tid]
						if alive(tu) <= 0.03 or _engaged(tu, units):
							continue
						var dmg: float = _shoot_dmg(u, tid, _edge(u, tu)) * alive(u) * los
						if dmg <= 0.0:
							continue
						var left: float = maxf(0.0, 1.4 - float(tu.x)) * float(tu.wounds)
						var val: float = minf(dmg, left) / maxf(1.0, float(tu.wounds))
						for o in objectives:
							if oc_weight(tu, o.pos, opts) > 0.0:
								val *= 1.5
								break
						if val > best_v:
							best_v = val
							best_t = tid
							best_d = dmg
					if best_t != "":
						_hit(units, best_t, best_d, side, kills)
				# --- Charges (active side), then everyone in engagement fights
				for uid in units:
					var u: Dictionary = units[uid]
					if int(u.side) != side or alive(u) <= 0.03 or advanced.has(uid) or _engaged(u, units):
						continue
					if not bool(u.get("charger", u.get("seeker", false))):
						continue
					var best_t := ""
					var best_v := 0.0
					var best_p := 0.0
					for tid in u.melee:
						if not units.has(tid):
							continue
						var tu: Dictionary = units[tid]
						if alive(tu) <= 0.03:
							continue
						var p := charge_p(_edge(u, tu) - ENGAGE_IN)
						if p < float(opts.charge_min_p):
							continue
						var val: float = p * minf(float(u.melee[tid]) * alive(u), float(tu.wounds)) / maxf(1.0, float(tu.wounds))
						if val > best_v:
							best_v = val
							best_t = tid
							best_p = p
					if best_t != "":
						var tu: Dictionary = units[best_t]
						_hit(units, best_t, float(u.melee[best_t]) * alive(u) * best_p, side, kills)
						_hit(units, uid, float(tu.melee.get(uid, 0.0)) * alive(tu) * best_p, int(tu.side), kills)
						if best_p >= 0.5:
							var dir: Vector2 = ((u.pos as Vector2) - (tu.pos as Vector2)).normalized()
							u["pos"] = (tu.pos as Vector2) + dir * (float(u.radius) + float(tu.radius) + 0.5)
							u["charged"] = true
				for uid in units:
					var u: Dictionary = units[uid]
					if alive(u) <= 0.03 or bool(u.get("charged", false)):
						continue
					var best_t := ""
					var best_d := 0.0
					for tid in u.melee:
						if not units.has(tid):
							continue
						var tu: Dictionary = units[tid]
						if alive(tu) <= 0.03 or _edge(u, tu) > ENGAGE_IN + 0.5:
							continue
						if float(u.melee[tid]) > best_d:
							best_d = float(u.melee[tid])
							best_t = tid
					if best_t != "":
						_hit(units, best_t, best_d * alive(u), int(u.side), kills)
				for uid in units:
					units[uid].erase("charged")
			prev_own = ownership(units, objectives, opts, prev_own, secured)
			row["own_end"] = prev_own.duplicate(true)
			kills.erase("scale")
			if do_damage:
				row["lam"] = kills
			if bool(opts.get("trace", false)):
				var tr := {}
				for uid in units:
					var tu: Dictionary = units[uid]
					tr[uid] = [snappedf(alive(tu), 0.01), snappedf(p_dead(float(tu.x)), 0.01), snappedf((tu.pos as Vector2).x, 0.1), snappedf((tu.pos as Vector2).y, 0.1)]
				row["units"] = tr
				var ocs := {}
				for o in objectives:
					var oo := oc_at(units, o.pos, opts)
					ocs[o.id] = [snappedf(oo[1], 0.1), snappedf(oo[2], 0.1)]
				row["oc_end"] = ocs
			turns.append(row)
			first_turn = false
	return {"turns": turns, "units": units}
