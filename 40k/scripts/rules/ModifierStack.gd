class_name ModifierStack
extends RefCounted

## ISS-016 — consolidated typed modifier stack.
##
## Sources register typed modifiers; consumers query `net(type)`. The
## ±1 net cap on DICE-ROLL modifiers lives HERE and nowhere else
## (acceptance: +2 worth of hit bonuses nets +1). CHARACTERISTIC
## modifiers (BS/WS worsen/improve, 11e 13.08/22.05) are cumulative and
## NOT subject to the dice cap — for "bs"/"ws", a POSITIVE value worsens
## the threshold (3+ becomes 4+) and a negative one improves it.
##
## First migrated sources are the ones 11e changes on the hit side:
##  ▪ benefit of cover incl. STEALTH (13.08 / 24.33) — worsen BS by 1
##  ▪ plunging fire (22.05)                          — improve BS by 1
##  ▪ [HEAVY] (24.16)                                — +1 to the hit roll
## The 10e bitfield path is untouched (golden corpus pins it); the 11e
## resolution flow consumes this stack (ISS-041/053).

const DICE_ROLL_TYPES := ["hit_roll", "wound_roll", "save_roll", "charge_roll", "advance_roll"]

var entries: Array = []


func add(type: String, value: int, source: String) -> void:
	entries.append({"type": type, "value": value, "source": source})


func raw_sum(type: String) -> int:
	var total := 0
	for e in entries:
		if e.type == type:
			total += e.value
	return total


## Net modifier for a type. Dice-roll modifiers are summed then capped
## at ±1 (Modifying Dice Rolls); characteristic modifiers accumulate.
func net(type: String) -> int:
	var total := raw_sum(type)
	if type in DICE_ROLL_TYPES:
		return clampi(total, -1, 1)
	return total


func sources(type: String) -> Array:
	var out: Array = []
	for e in entries:
		if e.type == type:
			out.append(e.source)
	return out


func describe() -> String:
	var parts: Array = []
	for e in entries:
		parts.append("%s%+d (%s)" % [e.type, e.value, e.source])
	return ", ".join(parts)


# Lazy autoload lookups (compile-time autoload identifiers error in bare
# `godot -s` contexts when used from class_name scripts).
static func _terrain() -> Node:
	var loop = Engine.get_main_loop()
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null("TerrainManager")


static func _rules() -> Node:
	var loop = Engine.get_main_loop()
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null("RulesEngine")


## 11e ranged-attack hit context for one weapon batch.
## opts:
##   attacker_models: Array  — the firing models; plunging fire is granted
##                             when EVERY firing model qualifies (per-model
##                             attack tracking refines this with ISS-048)
##   ignores_cover: bool     — override; otherwise derived from the weapon's
##                             abilities + the attacker's effect flag
## 13.08/[IGNORES COVER]: whether this attack disregards the benefit of cover.
static func attack_ignores_cover(attacker_unit: Dictionary, weapon_profile: Dictionary, opts: Dictionary = {}) -> bool:
	var abilities: Array = AbilityRegistry.from_weapon(weapon_profile)
	return bool(opts.get("ignores_cover", false)) \
		or AbilityRegistry.has_ability(abilities, "ignores_cover") \
		or attacker_unit.get("flags", {}).get(EffectPrimitivesData.FLAG_IGNORES_COVER, false)

static func collect_hit_context_11e(attacker_unit: Dictionary, target_unit: Dictionary, weapon_profile: Dictionary, board: Dictionary, opts: Dictionary = {}) -> ModifierStack:
	var stack := ModifierStack.new()
	if GameConstants.edition < 11:
		return stack
	var terrain := _terrain()
	var abilities: Array = AbilityRegistry.from_weapon(weapon_profile)

	# Benefit of cover (13.08; STEALTH 24.33 grants it): worsen BS by 1.
	# Audit #7: callers that split cover PER ATTACKING MODEL (13.08's
	# "not fully visible to the attacking model" is per-attack) pass
	# per_attack_cover=true and apply the worsening per attack themselves.
	var ignores_cover: bool = attack_ignores_cover(attacker_unit, weapon_profile, opts)
	if not ignores_cover and not bool(opts.get("per_attack_cover", false)):
		var has_cover := false
		if terrain != null and terrain.has_method("unit_has_cover_11e"):
			# ISS-052/053: pass the first firing model so the
			# not-fully-visible half of 13.08 participates.
			var cover_attacker: Dictionary = {}
			for fm in opts.get("attacker_models", []):
				if fm is Dictionary and fm.get("alive", true):
					cover_attacker = fm
					break
			has_cover = terrain.unit_has_cover_11e(target_unit, cover_attacker)
		if not has_cover and target_unit.get("flags", {}).get("stratagem_cover", false):
			has_cover = true
		if not has_cover and not (terrain != null) and UnitAbilities.unit_has(target_unit, "stealth"):
			# No TerrainManager in this context: STEALTH still grants cover.
			has_cover = true
		if has_cover:
			stack.add("bs", 1, "benefit_of_cover")

	# Plunging fire (22.05): improve BS by 1.
	if terrain != null and terrain.has_method("plunging_fire_applies"):
		var attacker_models: Array = opts.get("attacker_models", [])
		if not attacker_models.is_empty():
			var all_qualify := true
			for m in attacker_models:
				if not terrain.plunging_fire_applies(m, attacker_unit, target_unit):
					all_qualify = false
					break
			if all_qualify:
				stack.add("bs", -1, "plunging_fire")

	# Close-quarters shooting (10.06) + engaged MONSTER/VEHICLE targets
	# (17.03) — these replace 10e's Big Guns Never Tire / pistol rules.
	var rules := _rules()
	if rules != null:
		var attacker_id := str(attacker_unit.get("id", ""))
		var target_id := str(target_unit.get("id", ""))
		var is_cq: bool = AbilityRegistry.has_ability(abilities, "close_quarters") \
			or AbilityRegistry.has_ability(abilities, "pistol")  # 24.27
		var engaged_with_target: bool = rules.check_units_in_engagement_range(attacker_unit, target_unit, board)
		# 10.06: an engaged MONSTER/VEHICLE shooter takes -1 unless the
		# attack is a [CLOSE-QUARTERS] weapon against an engaged target.
		var atk_keywords: Array = attacker_unit.get("meta", {}).get("keywords", [])
		if ("MONSTER" in atk_keywords or "VEHICLE" in atk_keywords) \
				and rules.is_unit_engaged(attacker_id, board) \
				and not (is_cq and engaged_with_target):
			stack.add("hit_roll", -1, "close_quarters_monster_vehicle")
		# 17.03: shooting an ENGAGED MONSTER/VEHICLE is -1 to hit, except
		# [CLOSE-QUARTERS] attacks from a unit engaged with the target.
		var tgt_keywords: Array = target_unit.get("meta", {}).get("keywords", [])
		if ("MONSTER" in tgt_keywords or "VEHICLE" in tgt_keywords) \
				and rules.is_unit_engaged(target_id, board) \
				and not (is_cq and engaged_with_target):
			stack.add("hit_roll", -1, "engaged_monster_vehicle_target")

	# [HEAVY] (24.16): +1 to the hit roll while the attacking unit is
	# unengaged, was not set up this turn, and no model moved more than 3"
	# this turn (MovementPhase records flags.moved_max_inches).
	if AbilityRegistry.has_ability(abilities, "heavy") and heavy_applies_11e(attacker_unit, board):
		stack.add("hit_roll", 1, "heavy")

	return stack


static func heavy_applies_11e(unit: Dictionary, board: Dictionary) -> bool:
	var flags: Dictionary = unit.get("flags", {})
	if flags.get("set_up_this_turn", false) or flags.get("arrived_from_reserves", false) \
			or flags.get("deep_struck", false):
		return false
	# 11e 24.16: qualifies if it remained stationary OR no model moved more
	# than 3" this turn (MovementPhase records flags.moved_max_inches on both
	# the move-confirm and remain-stationary paths).
	var qualifies := false
	if flags.get("remained_stationary", false):
		qualifies = true
	elif flags.has("moved_max_inches"):
		qualifies = float(flags.get("moved_max_inches", 999.0)) <= 3.0
	if not qualifies:
		return false
	var rules := _rules()
	if rules != null:
		return rules.is_unit_unengaged(str(unit.get("id", "")), board)
	return true
