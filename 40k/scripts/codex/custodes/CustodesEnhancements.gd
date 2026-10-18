extends RefCounted

## CustodesEnhancements — the 29 Codex: Adeptus Custodes (11th edition)
## enhancements (WP-C46). Source: .llm/codex_11e_wahapedia/custodes/RULES.md
## ("Enh" lines; Emperor's Light / Auriferous Orb weapon profiles from the
## Wahapedia faction page — the CSV export drops the weapon table).
## Rulings: RULINGS.md § WP-C46.
##
## The engine hooks never call this file directly: CustodesDetachments.gd is the
## façade (it loads this module lazily and folds its contributions in), except
## for the list-build pass (ArmyListManager) and the phase-start window.
##
##  Guardians of the Throne  Bane of Abominations (+1 wound vs CHAR/MON/VEH),
##                           Emperor's Light (melee weapon), Castellan's Mark
##                           (redeploy 3 — FactionAbilityManager redeploy table),
##                           Eagle's Eye (+1 W; once: 3+ InSv when attacked)
##  Aquilan Shield           Not a Shell Wasted (unit ranged +1 A),
##                           Pareldor's Caducatrix (once: heal D3+3, phase start)
##  Dread Host               Flawless Bladework (melee [SUSTAINED HITS 1]),
##                           Auric Exemplar (melee [CLEAVE 1])
##  Emperor's Chosen         From the Hall of Armouries (melee [DEVASTATING
##                           WOUNDS]), Radiant Mantle (-1 to hit vs the unit)
##  Emissaries Imperatus     Edge of the Blade (charged: re-roll hit/wound 1s),
##                           Auriferous Orb (ranged weapon + BLINDING LIGHT)
##  Shadowkeepers            Unstoppable Destroyer (4" pile-in / consolidation,
##                           any consolidation mode), Genalchemic Warding (FNP 5+)
##  Solar Watch              Sally Forth (start of Charge phase: an advanced unit
##                           can charge), Auric Eagle (+1 advance / charge rolls)
##  Honoured Companions      Arae-Shrike (enemy ingress 12" away),
##                           Celeritous Sentries (HEROIC INTERVENTION -1CP)
##  Auric Champions          Shroud of the Hidden Blade (Stealth, Lone Operative),
##                           Superior Creation (once: 2+ back with 3 wounds),
##                           Inspirational Exemplar (round: lift battle-shock)
##  Lions of the Emperor     Lightning Descent (ingress in the first Movement
##                           phase), Leonine Ferocity (RAPID INGRESS -1CP)
##  Might of the Moritoi     Memento Moritoi (melee +1 A/S/D), Augury Uplink
##                           (FNP 5+)
##  Grav-Assault Force       Anti-gravitic Mobility (fall back and shoot),
##                           Combat Deployment (disembarked: re-roll charges, no
##                           snap shooting at it)
##  Null Maiden Vigil        Oblivion Knight (+1 hit; +1 wound vs PSYKER /
##                           battle-shocked), Huntress' Eye (Movement phase:
##                           battle-shock roll at -1)

const Common = preload("res://scripts/codex/custodes/CustodesCommon.gd")
const GameStateData = preload("res://autoloads/GameState.gd")

# ---------------------------------------------------------------------------
# Enhancement keys (normalised: lower case, folded apostrophes, no "(one per
# army)" / "(upgrade)" suffix)
# ---------------------------------------------------------------------------

const BANE := "bane of abominations"
const EMPERORS_LIGHT := "emperor's light"
const CASTELLANS_MARK := "castellan's mark"
const EAGLES_EYE := "eagle's eye"
const NOT_A_SHELL := "not a shell wasted"
const CADUCATRIX := "pareldor's caducatrix"
const FLAWLESS := "flawless bladework"
const AURIC_EXEMPLAR := "auric exemplar"
const HALL_OF_ARMOURIES := "from the hall of armouries"
const RADIANT_MANTLE := "radiant mantle"
const EDGE_OF_THE_BLADE := "edge of the blade"
const AURIFEROUS_ORB := "auriferous orb"
const UNSTOPPABLE := "unstoppable destroyer"
const GENALCHEMIC := "genalchemic warding"
const SALLY_FORTH := "sally forth"
const AURIC_EAGLE := "auric eagle"
const ARAE_SHRIKE := "arae-shrike"
const CELERITOUS := "celeritous sentries"
const SHROUD := "shroud of the hidden blade"
const SUPERIOR_CREATION := "superior creation"
const INSPIRATIONAL := "inspirational exemplar"
const LIGHTNING_DESCENT := "lightning descent"
const LEONINE := "leonine ferocity"
const MEMENTO := "memento moritoi"
const AUGURY := "augury uplink"
const ANTI_GRAV := "anti-gravitic mobility"
const COMBAT_DEPLOYMENT := "combat deployment"
const OBLIVION_KNIGHT := "oblivion knight"
const HUNTRESS := "huntress' eye"

## key -> codex detachment key (CustodesDetachments det_key) and display name.
const ENHANCEMENTS := {
	BANE: {"detachment": "guardians of the throne", "name": "Bane of Abominations"},
	EMPERORS_LIGHT: {"detachment": "guardians of the throne", "name": "Emperor's Light"},
	CASTELLANS_MARK: {"detachment": "guardians of the throne", "name": "Castellan's Mark"},
	EAGLES_EYE: {"detachment": "guardians of the throne", "name": "Eagle's Eye"},
	NOT_A_SHELL: {"detachment": "aquilan shield", "name": "Not a Shell Wasted"},
	CADUCATRIX: {"detachment": "aquilan shield", "name": "Pareldor's Caducatrix"},
	FLAWLESS: {"detachment": "dread host", "name": "Flawless Bladework"},
	AURIC_EXEMPLAR: {"detachment": "dread host", "name": "Auric Exemplar"},
	HALL_OF_ARMOURIES: {"detachment": "emperor's chosen", "name": "From the Hall of Armouries"},
	RADIANT_MANTLE: {"detachment": "emperor's chosen", "name": "Radiant Mantle"},
	EDGE_OF_THE_BLADE: {"detachment": "emissaries imperatus", "name": "Edge of the Blade"},
	AURIFEROUS_ORB: {"detachment": "emissaries imperatus", "name": "Auriferous Orb"},
	UNSTOPPABLE: {"detachment": "shadowkeepers", "name": "Unstoppable Destroyer"},
	GENALCHEMIC: {"detachment": "shadowkeepers", "name": "Genalchemic Warding"},
	SALLY_FORTH: {"detachment": "solar watch", "name": "Sally Forth"},
	AURIC_EAGLE: {"detachment": "solar watch", "name": "Auric Eagle"},
	ARAE_SHRIKE: {"detachment": "honoured companions", "name": "Arae-Shrike"},
	CELERITOUS: {"detachment": "honoured companions", "name": "Celeritous Sentries"},
	SHROUD: {"detachment": "auric champions", "name": "Shroud of the Hidden Blade"},
	SUPERIOR_CREATION: {"detachment": "auric champions", "name": "Superior Creation"},
	INSPIRATIONAL: {"detachment": "auric champions", "name": "Inspirational Exemplar"},
	LIGHTNING_DESCENT: {"detachment": "lions of the emperor", "name": "Lightning Descent"},
	LEONINE: {"detachment": "lions of the emperor", "name": "Leonine Ferocity"},
	MEMENTO: {"detachment": "might of the moritoi", "name": "Memento Moritoi"},
	AUGURY: {"detachment": "might of the moritoi", "name": "Augury Uplink"},
	ANTI_GRAV: {"detachment": "grav-assault force", "name": "Anti-gravitic Mobility"},
	COMBAT_DEPLOYMENT: {"detachment": "grav-assault force", "name": "Combat Deployment"},
	OBLIVION_KNIGHT: {"detachment": "null maiden vigil", "name": "Oblivion Knight"},
	HUNTRESS: {"detachment": "null maiden vigil", "name": "Huntress' Eye"},
}

## Weapons granted at list build (unique names: RulesEngine.get_weapon_profile
## resolves weapons by name across units, so a granted weapon must never share
## a name with a datasheet weapon).
const GRANTED_WEAPONS := {
	EMPERORS_LIGHT: {"name": "Emperor's Light", "type": "Melee", "range": "Melee", "attacks": "3", "weapon_skill": "2",
		"strength": "5", "ap": "-2", "damage": "2", "special_rules": "extra attacks",
		"abilities": [{"id": "extra_attacks"}]},
	AURIFEROUS_ORB: {"name": "Auriferous Orb", "type": "Ranged", "range": "12", "attacks": "3", "ballistic_skill": "2",
		"strength": "1", "ap": "0", "damage": "1", "special_rules": "anti-non-monster/vehicle 2+, blinding light, devastating wounds",
		"abilities": [{"id": "devastating_wounds"}]},
}

## Abilities granted at list build (existing consumers: has_lone_operative,
## has_stealth_ability, ...).
const GRANTED_ABILITIES := {
	SHROUD: ["Stealth", "Lone Operative"],
}

## Characteristic bonuses applied at list build.
const STAT_BONUSES := {
	EAGLES_EYE: {"stat": "wounds", "bonus": 1},
}

# ---------------------------------------------------------------------------
# Rule offers (free choices in stratagem windows)
# ---------------------------------------------------------------------------

const RULE_PREFIX := "cus11e_rule_enh_"
const RULE_EAGLES_EYE := "cus11e_rule_enh_eagles_eye"
const RULE_CADUCATRIX := "cus11e_rule_enh_caducatrix"
const RULE_INSPIRATIONAL := "cus11e_rule_enh_inspirational_exemplar"
const RULE_SALLY_FORTH := "cus11e_rule_enh_sally_forth"
const RULE_HUNTRESS := "cus11e_rule_enh_huntress_eye"
const RULE_BLINDING_LIGHT := "cus11e_rule_enh_blinding_light"

const WINDOW_PHASE_START := "cus11e_phase_start"

# ---------------------------------------------------------------------------
# Flags (clear points listed; no effect_ prefix)
# ---------------------------------------------------------------------------

## Eagle's Eye used (once per battle, per army) — on the bearer, never cleared.
const F_EAGLES_EYE_USED := "cus11e_eagles_eye_used"
## Eagle's Eye 3+ InSv active: phase stamp; cleared at the end of the phase.
const F_EAGLES_EYE_ACTIVE := "cus11e_eagles_eye_active"
## Pareldor's Caducatrix used (once per battle) — on the bearer.
const F_CADUCATRIX_USED := "cus11e_caducatrix_used"
## Inspirational Exemplar: battle round it was used (once per battle round).
const F_INSPIRATIONAL_ROUND := "cus11e_inspirational_round"
## Sally Forth: turn stamp "<round>:<active>" on the selected unit (+ group);
## its advance does not prevent a charge this turn. Cleared at the next
## Command phase start.
const F_SALLY_FORTH := "cus11e_sally_forth"
## Sally Forth used this Charge phase (on the bearer): phase stamp.
const F_SALLY_FORTH_STAMP := "cus11e_sally_forth_stamp"
## Huntress' Eye used this Movement phase (on the bearer): phase stamp.
const F_HUNTRESS_STAMP := "cus11e_huntress_stamp"
## Blinding Light on the ENEMY unit: the Orb player's number; its attacks have
## -1 to hit until the start of that player's next turn (cleared at their next
## Command phase start).
const F_BLINDING_LIGHT := "cus11e_blinding_light_by"
## Blinding Light used (on the bearer): phase stamp (one selection per shot).
const F_BLINDING_LIGHT_STAMP := "cus11e_blinding_light_stamp"
## Combat Deployment: turn stamp on the disembarked unit (+ group): re-roll
## charges, no snap shooting at it, until the end of the turn.
const F_COMBAT_DEPLOYMENT := "cus11e_combat_deployment"
## Superior Creation resolved (once per battle, per army) — on the bearer.
const F_SUPERIOR_CREATION_DONE := "cus11e_superior_creation_done"
## Leonine Ferocity / Celeritous Sentries: phase stamp of the -1CP use.
const F_LEONINE_STAMP := "cus11e_leonine_stamp"
const F_CELERITOUS_STAMP := "cus11e_celeritous_stamp"

const INSPIRATIONAL_RANGE_IN := 9.0
const SALLY_FORTH_RANGE_IN := 6.0
const HUNTRESS_RANGE_IN := 12.0
const ARAE_SHRIKE_RANGE_IN := 12.0
const UNSTOPPABLE_MOVE_IN := 4.0
const SUPERIOR_CREATION_WOUNDS := 3

# ===========================================================================
# Basics
# ===========================================================================

static func enabled() -> bool:
	return GameConstants.edition >= 11

static func enh_key(name: String) -> String:
	var k := name.replace(" ", " ").replace("’", "'").replace("‘", "'").strip_edges().to_lower()
	for suffix in [" (one per army)", " (upgrade)"]:
		if k.ends_with(suffix):
			k = k.substr(0, k.length() - suffix.length()).strip_edges()
	return k

static func is_codex_enhancement(name: String) -> bool:
	return ENHANCEMENTS.has(enh_key(name))

static func display_name(key: String) -> String:
	return str(ENHANCEMENTS.get(key, {}).get("name", key))

static func _board_or_state(board: Dictionary) -> Dictionary:
	return board if board.has("units") else Common.state()

## Enhancement keys a unit dictionary carries (meta.enhancements: strings or
## {name}).
static func unit_enhancements(u: Dictionary) -> Array:
	var out: Array = []
	for e in u.get("meta", {}).get("enhancements", []):
		var n := ""
		if e is String:
			n = e
		elif e is Dictionary:
			n = str(e.get("name", ""))
		if n != "":
			out.append(enh_key(n))
	return out

## True when THIS unit dict carries the enhancement (the bearer's own unit).
static func has(u: Dictionary, key: String) -> bool:
	return enabled() and not u.is_empty() and key in unit_enhancements(u)

## The unit dicts of `u`'s Attached unit (the caller's dict stands for its
## own unit).
static func group_units(u: Dictionary, board: Dictionary = {}) -> Array:
	var uid := str(u.get("id", ""))
	if uid == "":
		return [u]
	var units: Dictionary = _board_or_state(board).get("units", {})
	var out: Array = []
	for gid in Common.attached_group_ids(uid):
		var gu = u if str(gid) == uid else units.get(str(gid), {})
		if not gu.is_empty():
			out.append(gu)
	if out.is_empty():
		out.append(u)
	return out

## The component of `u`'s Attached unit that carries the enhancement ({}).
static func group_bearer(u: Dictionary, key: String, board: Dictionary = {}) -> Dictionary:
	if not enabled() or u.is_empty():
		return {}
	for gu in group_units(u, board):
		if key in unit_enhancements(gu):
			return gu
	return {}

static func group_has(u: Dictionary, key: String, board: Dictionary = {}) -> bool:
	return not group_bearer(u, key, board).is_empty()

static func group_kw(u: Dictionary, kw: String, board: Dictionary = {}) -> bool:
	for gu in group_units(u, board):
		if Common.has_keyword(gu, kw):
			return true
	return false

## Every unit of `player` that carries the enhancement (normally 0 or 1).
static func bearers(player: int, key: String) -> Array:
	var out: Array = []
	if not enabled():
		return out
	var units: Dictionary = Common.state().get("units", {})
	for uid in units:
		var u: Dictionary = units[uid]
		if int(u.get("owner", 0)) == player and key in unit_enhancements(u):
			out.append(u)
	return out

## True when the attacks of this batch are the BEARER model's own: the
## attacker unit is the bearer and (ranged, Attached unit) no listed firing
## model belongs to another component. Ruling: a ranged batch that mixes the
## bearer with other models firing the same weapon does not get a
## bearer-only effect (the engine resolves one profile per batch).
static func attacks_by_bearer(attacker: Dictionary, key: String, board: Dictionary = {}, ctx: Dictionary = {}) -> bool:
	if not enabled() or attacker.is_empty():
		return false
	var mids: Array = ctx.get("model_ids", [])
	if has(attacker, key):
		for mid in mids:
			if str(mid).find(":") > 0:
				return false
		return true
	if mids.is_empty():
		return false
	var units: Dictionary = _board_or_state(board).get("units", {})
	for mid in mids:
		var s := str(mid)
		var sep := s.find(":")
		if sep <= 0:
			return false
		if not has(units.get(s.substr(0, sep), {}), key):
			return false
	return true

static func stamp() -> String:
	var meta: Dictionary = Common.state().get("meta", {})
	return "%d:%d:%d" % [int(meta.get("battle_round", 1)), int(meta.get("active_player", 1)), int(meta.get("phase", -1))]

static func turn_stamp() -> String:
	var meta: Dictionary = Common.state().get("meta", {})
	return "%d:%d" % [int(meta.get("battle_round", 1)), int(meta.get("active_player", 1))]

static func _log(msg: String) -> void:
	Common.log_info("[CustodesEnhancements] " + msg)

static func _event(player: int, msg: String) -> void:
	Common.game_log(player, msg)

static func _toast(msg: String) -> void:
	var tm = Common.autoload("ToastManager")
	if tm and tm.has_method("show_toast"):
		tm.show_toast(msg, Color.GOLD)

static func _rng():
	var re = Common.rules()
	return re.make_rng() if re else null

static func _d6(rng) -> int:
	return int(rng.roll_d6(1)[0]) if rng else 1

static func _flag_diffs_group(unit_id: String, flag: String, value) -> Array:
	return Common.set_flag_diffs(Common.attached_group_ids(unit_id), flag, value)

static func _battle_shocked(u: Dictionary) -> bool:
	for gu in group_units(u):
		if bool(gu.get("flags", {}).get("battle_shocked", false)):
			return true
	return false

# ===========================================================================
# List build (ArmyListManager hook — runs once per unit at army load)
# ===========================================================================

## Apply the list-build effects of the unit's codex enhancements: +1 W
## (Eagle's Eye), granted abilities (Shroud of the Hidden Blade) and weapons
## (Emperor's Light, Auriferous Orb). Idempotent. Returns log lines.
static func apply_list_build(unit_id: String, unit: Dictionary) -> Array:
	var lines: Array = []
	if not unit.has("meta"):
		return lines
	var meta: Dictionary = unit.meta
	var flags: Dictionary = unit.get("flags", {})
	for key in unit_enhancements(unit):
		if not ENHANCEMENTS.has(key):
			continue
		var done_flag: String = "cus11e_listbuild_" + str(key).replace(" ", "_").replace("'", "")
		if bool(flags.get(done_flag, false)):
			continue
		if STAT_BONUSES.has(key):
			var sb: Dictionary = STAT_BONUSES[key]
			var stat := str(sb.stat)
			var bonus := int(sb.bonus)
			if meta.has("stats") and meta.stats.has(stat):
				meta.stats[stat] = int(meta.stats[stat]) + bonus
			if stat == "wounds":
				for m in unit.get("models", []):
					var old_w := int(m.get("wounds", 1))
					var full: bool = int(m.get("current_wounds", old_w)) >= old_w
					m["wounds"] = old_w + bonus
					if full:
						m["current_wounds"] = m["wounds"]
			lines.append("%s on %s: %s +%d" % [display_name(key), unit_id, stat, bonus])
		for ab in GRANTED_ABILITIES.get(key, []):
			if not meta.has("abilities") or not (meta.abilities is Array):
				meta["abilities"] = []
			var have := false
			for a in meta.abilities:
				var an: String = a if a is String else (str(a.get("name", "")) if a is Dictionary else "")
				if an.to_lower() == str(ab).to_lower():
					have = true
			if not have:
				meta.abilities.append({"name": ab, "type": "Enhancement", "description": "Granted by %s." % display_name(key)})
				lines.append("%s on %s: grants %s" % [display_name(key), unit_id, ab])
		if GRANTED_WEAPONS.has(key):
			if not meta.has("weapons") or not (meta.weapons is Array):
				meta["weapons"] = []
			var w: Dictionary = GRANTED_WEAPONS[key].duplicate(true)
			# `granted_by` keeps the weapon through the MA-LOADOUT narrowing
			# (UnitLoadoutResolver / RulesEngine._get_model_weapon_ids): it is
			# not roster wargear, so the wargear filter would otherwise drop it.
			w["granted_by"] = display_name(key)
			var exists := false
			for ow in meta.weapons:
				if str(ow.get("name", "")) == str(w.name):
					exists = true
			if not exists:
				meta.weapons.append(w)
				lines.append("%s on %s: gains the %s weapon" % [display_name(key), unit_id, w.name])
		if not unit.has("flags"):
			unit["flags"] = {}
		unit.flags[done_flag] = true
	for l in lines:
		_log("list build — " + str(l))
	return lines

## The bearer models of a granted weapon (MA-LOADOUT): every model of the
## bearer unit (enhancement bearers are single-model CHARACTER units).
static func granted_weapon_names() -> Array:
	var out: Array = []
	for k in GRANTED_WEAPONS:
		out.append(str(GRANTED_WEAPONS[k].name))
	return out

# ===========================================================================
# Combat (via CustodesDetachments façade)
# ===========================================================================

static func hit_effects(attacker: Dictionary, target: Dictionary, is_melee: bool, board: Dictionary = {}, ctx: Dictionary = {}) -> Array:
	var out: Array = []
	if not enabled():
		return out
	# Radiant Mantle: "Attacks that target this unit have -1 to hit rolls."
	if int(attacker.get("owner", 0)) != int(target.get("owner", -1)) and group_has(target, RADIANT_MANTLE, board):
		out.append({"kind": "minus_one", "source": "Radiant Mantle", "note": "defender's enhancement"})
	# Blinding Light: the attacker was blinded by an Auriferous Orb.
	for gu in group_units(attacker, board):
		var by := int(gu.get("flags", {}).get(F_BLINDING_LIGHT, 0))
		if by > 0 and by == int(target.get("owner", -1)):
			out.append({"kind": "minus_one", "source": "Blinding Light (Auriferous Orb)", "note": "until the start of the Orb player's next turn"})
			break
	# Oblivion Knight: "This unit's attacks have +1 to hit rolls" (either option).
	if group_has(attacker, OBLIVION_KNIGHT, board):
		out.append({"kind": "plus_one", "source": "Oblivion Knight", "note": "bearer's unit"})
	# Edge of the Blade: charged this turn — this model re-rolls hit rolls of 1.
	if attacks_by_bearer(attacker, EDGE_OF_THE_BLADE, board, ctx) and _charged_this_turn(attacker, board):
		out.append({"kind": "reroll_ones", "source": "Edge of the Blade", "note": "bearer made a charge move this turn"})
	return out

static func wound_effects(attacker: Dictionary, target: Dictionary, _is_melee: bool, _strength: int, _toughness: int, board: Dictionary = {}, ctx: Dictionary = {}) -> Array:
	var out: Array = []
	if not enabled():
		return out
	if int(attacker.get("owner", 0)) == int(target.get("owner", -1)):
		return out
	# Bane of Abominations: +1 to wound vs CHARACTER / MONSTER / VEHICLE units.
	if attacks_by_bearer(attacker, BANE, board, ctx) and (group_kw(target, "CHARACTER", board) or group_kw(target, "MONSTER", board) or group_kw(target, "VEHICLE", board)):
		out.append({"kind": "plus_one", "source": "Bane of Abominations", "note": "target is a CHARACTER, MONSTER or VEHICLE unit"})
	# Oblivion Knight (second option): +1 to wound vs PSYKER / battle-shocked.
	if group_has(attacker, OBLIVION_KNIGHT, board) and (group_kw(target, "PSYKER", board) or _battle_shocked(target)):
		out.append({"kind": "plus_one", "source": "Oblivion Knight", "note": "target is a PSYKER or battle-shocked unit"})
	# Edge of the Blade: re-roll wound rolls of 1 after a charge.
	if attacks_by_bearer(attacker, EDGE_OF_THE_BLADE, board, ctx) and _charged_this_turn(attacker, board):
		out.append({"kind": "reroll_ones", "source": "Edge of the Blade", "note": "bearer made a charge move this turn"})
	return out

static func _charged_this_turn(u: Dictionary, board: Dictionary = {}) -> bool:
	for gu in group_units(u, board):
		if bool(gu.get("flags", {}).get("charged_this_turn", false)):
			return true
	return false

## Melee weapon-ability grants of the BEARER model (Flawless Bladework,
## From the Hall of Armouries, Auric Exemplar). Melee attacks of an Attached
## unit's CHARACTER are resolved under its own unit id, so a unit check is the
## model check.
static func melee_weapon_grants(attacker: Dictionary, _target: Dictionary, _board: Dictionary = {}) -> Dictionary:
	var out := {"sustained": "", "lethal": "", "devastating": "", "cleave": 0, "cleave_source": ""}
	if has(attacker, FLAWLESS):
		out.sustained = "Flawless Bladework"
	if has(attacker, HALL_OF_ARMOURIES):
		out.devastating = "From the Hall of Armouries"
	if has(attacker, AURIC_EXEMPLAR):
		out.cleave = 1
		out.cleave_source = "Auric Exemplar"
	return out

## Memento Moritoi: "This model's melee attacks have +1 A, S and D."
## {a, s, d, source} (0 = none).
static func melee_profile_bonus(attacker: Dictionary) -> Dictionary:
	if has(attacker, MEMENTO):
		return {"a": 1, "s": 1, "d": 1, "source": "Memento Moritoi"}
	return {"a": 0, "s": 0, "d": 0, "source": ""}

## Not a Shell Wasted: "This unit's ranged attacks have +1 A" — +1 Attacks per
## firing model of the bearer's (Attached) unit.
static func ranged_attacks_bonus(actor: Dictionary, board: Dictionary = {}) -> int:
	if group_has(actor, NOT_A_SHELL, board):
		return 1
	return 0

## Feel No Pain of the bearer model (Genalchemic Warding, Augury Uplink): 5.
static func fnp(u: Dictionary) -> int:
	if has(u, GENALCHEMIC) or has(u, AUGURY):
		return 5
	return 0

## Eagle's Eye 3+ InSv while used this phase (the bearer only).
static func invuln_save(target: Dictionary, _is_melee: bool, _board: Dictionary = {}) -> int:
	if has(target, EAGLES_EYE) and str(target.get("flags", {}).get(F_EAGLES_EYE_ACTIVE, "")) == stamp():
		return 3
	return 0

# ===========================================================================
# Movement / charge / fight
# ===========================================================================

## Auric Eagle: the bearer unit (an Upgrade on a non-CHARACTER unit) has +1 to
## advance rolls and charge rolls.
static func advance_roll_bonus(u: Dictionary) -> int:
	return 1 if group_has(u, AURIC_EAGLE) else 0

static func charge_roll_bonus(u: Dictionary) -> int:
	return 1 if group_has(u, AURIC_EAGLE) else 0

## Combat Deployment: a unit that disembarked from the bearer TRANSPORT this
## turn can re-roll charge rolls.
static func charge_reroll_source(u: Dictionary) -> String:
	for gu in group_units(u):
		if str(gu.get("flags", {}).get(F_COMBAT_DEPLOYMENT, "")) == turn_stamp():
			return "Combat Deployment"
	return ""

## Combat Deployment: enemy units cannot target that unit with snap shooting.
static func blocks_snap_shooting(target: Dictionary) -> bool:
	return enabled() and charge_reroll_source(target) != ""

## TransportManager.disembark_unit hook: a friendly ADEPTUS CUSTODES unit made
## a disembark move from a Combat Deployment TRANSPORT.
static func on_unit_disembarked(unit_id: String, transport_id: String) -> Array:
	if not enabled():
		return []
	var t := Common.unit(transport_id)
	var u := Common.unit(unit_id)
	if not has(t, COMBAT_DEPLOYMENT) or not Common.has_keyword(u, "ADEPTUS CUSTODES"):
		return []
	if int(u.get("owner", 0)) != int(t.get("owner", -1)):
		return []
	var diffs := Common.set_flag_diffs([unit_id], F_COMBAT_DEPLOYMENT, turn_stamp())
	Common.apply_diffs(diffs)
	var msg := "COMBAT DEPLOYMENT — %s disembarked from %s: it can re-roll charge rolls and cannot be targeted by snap shooting this turn" % [Common.unit_name(unit_id), Common.unit_name(transport_id)]
	_log(msg)
	_event(int(u.get("owner", 0)), msg)
	return diffs

## Anti-gravitic Mobility: the GRAV-ASSAULT bearer unit's fall-back move does
## not prevent it from being eligible to shoot.
static func fall_back_allows_shoot(u: Dictionary) -> bool:
	return group_has(u, ANTI_GRAV) and group_kw(u, "GRAV-ASSAULT")

## Sally Forth: the unit selected at the start of the Charge phase may charge
## although it advanced this turn.
static func advance_allows_charge(u: Dictionary) -> bool:
	for gu in group_units(u):
		if str(gu.get("flags", {}).get(F_SALLY_FORTH, "")) == turn_stamp():
			return true
	return false

## Unstoppable Destroyer: the bearer's unit "can move up to 4"" when selected
## to make a pile-in / consolidation move.
static func fight_move_cap(unit_id: String, cap: float, _board: Dictionary = {}) -> float:
	var u := Common.unit(unit_id)
	if group_has(u, UNSTOPPABLE):
		return maxf(cap, UNSTOPPABLE_MOVE_IN)
	return cap

## Unstoppable Destroyer: any consolidation mode, regardless of the Before
## Moving restrictions (each mode's own condition still applies).
static func any_consolidation_mode(unit_id: String) -> bool:
	return group_has(Common.unit(unit_id), UNSTOPPABLE)

## Lightning Descent: in your first Movement phase the bearer's unit can make
## an ingress move (strategic reserves normally arrive from battle round 2).
static func can_ingress_first_round(u: Dictionary) -> bool:
	if not group_has(u, LIGHTNING_DESCENT):
		return false
	return Common.battle_round() == 1 and int(Common.current_phase()) == int(GameStateData.Phase.MOVEMENT) \
		and Common.active_player() == int(u.get("owner", 0))

## Arae-Shrike: "Enemy units that are selected to make an ingress move cannot be
## set up within 12" of this unit." The bearer units' models an arriving unit of
## `arriving_owner` must stay more than 12" from.
static func ingress_exclusion_units(arriving_owner: int) -> Array:
	var out: Array = []
	if not enabled():
		return out
	var units: Dictionary = Common.state().get("units", {})
	for uid in units:
		var u: Dictionary = units[uid]
		if int(u.get("owner", 0)) == arriving_owner or not Common.is_on_battlefield(u):
			continue
		if key_in_group(u, ARAE_SHRIKE):
			out.append(str(uid))
	return out

static func key_in_group(u: Dictionary, key: String) -> bool:
	return group_has(u, key)

## Validation error for an ingress set-up position (px) of `arriving_unit_id`
## ("" = fine): within 12" of an Arae-Shrike unit.
static func arae_shrike_violation(arriving_unit_id: String, pos: Vector2, base_radius_px: float) -> String:
	if not enabled():
		return ""
	var owner := int(Common.unit(arriving_unit_id).get("owner", 0))
	for sid in ingress_exclusion_units(owner):
		for gid in Common.attached_group_ids(sid):
			for m in Common.unit(str(gid)).get("models", []):
				if not m.get("alive", true) or m.get("position", null) == null:
					continue
				var mp := Common._pos(m)
				var meas = Common.autoload("Measurement")
				var r := 0.0
				if meas and meas.has_method("base_radius_px"):
					r = float(meas.base_radius_px(int(m.get("base_mm", 32))))
				var edge_in := (pos.distance_to(mp) - base_radius_px - r) / Common.PX_PER_INCH
				if edge_in <= ARAE_SHRIKE_RANGE_IN:
					return "within 12\" of %s (Arae-Shrike: enemy units cannot be set up within 12\" when making an ingress move)" % Common.unit_name(sid)
	return ""

# ===========================================================================
# Stratagem overrides (Leonine Ferocity — RAPID INGRESS; Celeritous Sentries —
# HEROIC INTERVENTION): StratagemManager.can_use_stratagem / use hooks.
# ===========================================================================

## {applies, source, cost_delta, flag} when `player` targets the bearer's unit
## with that core stratagem and the enhancement's once-per-phase is unused.
static func stratagem_override(player: int, stratagem_id: String, target_unit_id: String) -> Dictionary:
	var none := {"applies": false}
	if not enabled() or target_unit_id == "":
		return none
	var sid := stratagem_id.replace("_11e", "")
	var u := Common.unit(target_unit_id)
	if u.is_empty() or int(u.get("owner", 0)) != player:
		return none
	if sid == "rapid_ingress":
		var b := group_bearer(u, LEONINE)
		if b.is_empty():
			return none
		# (Once per phase, per army)
		for bb in bearers(player, LEONINE):
			if str(bb.get("flags", {}).get(F_LEONINE_STAMP, "")) == stamp():
				return none
		return {"applies": true, "source": "Leonine Ferocity", "cost_delta": -1, "flag": F_LEONINE_STAMP, "bearer_id": str(b.get("id", ""))}
	if sid == "heroic_intervention":
		var b2 := group_bearer(u, CELERITOUS)
		if b2.is_empty() or not group_kw(u, "TRUSTED SENTINEL"):
			return none
		# (Once per phase, per unit)
		if str(b2.get("flags", {}).get(F_CELERITOUS_STAMP, "")) == stamp():
			return none
		return {"applies": true, "source": "Celeritous Sentries", "cost_delta": -1, "flag": F_CELERITOUS_STAMP, "bearer_id": str(b2.get("id", ""))}
	return none

## Record the override use (StratagemManager.use_stratagem hook).
static func record_stratagem_override(ov: Dictionary) -> Array:
	if not bool(ov.get("applies", false)):
		return []
	var diffs: Array = [{"op": "set", "path": "units.%s.flags.%s" % [str(ov.bearer_id), str(ov.flag)], "value": stamp()}]
	Common.apply_diffs(diffs)
	_log("%s: stratagem use at -1CP that does not prevent other uses this phase" % str(ov.source))
	return diffs

# ===========================================================================
# Superior Creation — end of a phase in which the bearer was destroyed
# (PhaseManager phase-transition hook; host only)
# ===========================================================================

## Roll for each destroyed Superior Creation bearer whose once-per-battle (per
## army) roll is unspent. 2+: set it back up as close as possible to where it
## was destroyed, unengaged, with 3 wounds remaining. {diffs, log_lines}.
static func resolve_superior_creation(rng = null) -> Dictionary:
	var out := {"diffs": [], "log_lines": []}
	if not enabled():
		return out
	var units: Dictionary = Common.state().get("units", {})
	for p in [1, 2]:
		var spent := false
		for b in bearers(p, SUPERIOR_CREATION):
			if bool(b.get("flags", {}).get(F_SUPERIOR_CREATION_DONE, false)):
				spent = true
		if spent:
			continue
		for b in bearers(p, SUPERIOR_CREATION):
			if Common.is_alive(b):
				continue
			var uid := str(b.get("id", ""))
			var models: Array = b.get("models", [])
			var idx := -1
			for i in range(models.size()):
				if models[i].get("position", null) != null:
					idx = i
			if idx < 0:
				continue  # never on the battlefield (destroyed in reserves / embarked)
			if rng == null:
				rng = _rng()
			var roll := _d6(rng)
			out.diffs.append({"op": "set", "path": "units.%s.flags.%s" % [uid, F_SUPERIOR_CREATION_DONE], "value": true})
			if roll < 2:
				out.log_lines.append("SUPERIOR CREATION: %s rolled %d — stays destroyed (needed 2+)" % [Common.unit_name(uid), roll])
				_event(p, str(out.log_lines.back()))
				continue
			var m: Dictionary = models[idx]
			var death_pos := Common._pos(m)
			var meas = Common.autoload("Measurement")
			var radius := float(meas.base_radius_px(int(m.get("base_mm", 32)))) if meas else 16.0
			var pos := superior_creation_position(death_pos, radius, p, Common.state())
			var w := mini(SUPERIOR_CREATION_WOUNDS, int(m.get("wounds", 1)))
			out.diffs.append({"op": "set", "path": "units.%s.models.%d.alive" % [uid, idx], "value": true})
			out.diffs.append({"op": "set", "path": "units.%s.models.%d.current_wounds" % [uid, idx], "value": w})
			out.diffs.append({"op": "set", "path": "units.%s.models.%d.position" % [uid, idx], "value": {"x": pos.x, "y": pos.y}})
			out.log_lines.append("SUPERIOR CREATION: %s rolled %d — set back up with %d wounds remaining (once per battle)" % [Common.unit_name(uid), roll, w])
			_event(p, str(out.log_lines.back()))
			_toast(str(out.log_lines.back()))
	for line in out.log_lines:
		_log(str(line))
	return out

## "As close as possible to where it was destroyed, unengaged": the death
## position if legal, else the closest spot on rings of 0.5" (up to 18") that
## overlaps no base and is outside Engagement Range of every enemy model.
static func superior_creation_position(death_pos: Vector2, radius_px: float, owner: int, board: Dictionary) -> Vector2:
	if _spot_legal(death_pos, radius_px, owner, board):
		return death_pos
	var step_px := 0.5 * Common.PX_PER_INCH
	for ring in range(1, 37):
		for angle_step in range(0, 16):
			var angle := angle_step * PI / 8.0
			var cand := death_pos + Vector2(cos(angle), sin(angle)) * step_px * ring
			if not _on_battlefield(cand, radius_px, board):
				continue
			if _spot_legal(cand, radius_px, owner, board):
				return cand
	Common.log_info("[CustodesEnhancements] Superior Creation: no legal spot within 18\" — death position used")
	return death_pos

static func _spot_legal(pos: Vector2, radius_px: float, owner: int, board: Dictionary) -> bool:
	var er := float(GameConstants.engagement_range_inches())
	var meas = Common.autoload("Measurement")
	for oid in board.get("units", {}):
		var other: Dictionary = board.units[oid]
		var enemy := int(other.get("owner", 0)) != owner
		for om in other.get("models", []):
			if not om.get("alive", true) or om.get("position", null) == null:
				continue
			var opos := Common._pos(om)
			var orad := float(meas.base_radius_px(int(om.get("base_mm", 32)))) if meas else 16.0
			var dist := pos.distance_to(opos)
			if dist < radius_px + orad:
				return false
			if enemy and (dist - radius_px - orad) / Common.PX_PER_INCH <= er:
				return false
	return true

static func _on_battlefield(pos: Vector2, radius_px: float, board: Dictionary) -> bool:
	var size: Dictionary = board.get("board", {}).get("size", {})
	if size.is_empty():
		return true
	var w := float(size.get("width", 44)) * Common.PX_PER_INCH
	var h := float(size.get("height", 60)) * Common.PX_PER_INCH
	return pos.x >= radius_px and pos.y >= radius_px and pos.x <= w - radius_px and pos.y <= h - radius_px

# ===========================================================================
# Rule offers
# ===========================================================================

static func is_rule_offer_id(sid: String) -> bool:
	return sid.begins_with(RULE_PREFIX)

static func window_offers(player: int, window_id: String, ctx: Dictionary) -> Array:
	var out: Array = []
	if not enabled():
		return out
	match window_id:
		WINDOW_PHASE_START:
			out.append_array(_caducatrix_offers(player))
			out.append_array(_inspirational_offers(player))
			out.append_array(_sally_forth_offers(player))
		"movement_phase_end":
			out.append_array(_huntress_offers(player))
		"unit_has_shot":
			out.append_array(_blinding_light_offers(player, ctx))
		"enemy_targets_unit_fight", "enemy_targets_unit_shooting":
			out.append_array(_eagles_eye_offers(player, ctx))
	return out

## Players with something to decide at the start of this phase, active player
## first (BasePhase.enter_phase hook). Entries in open_stratagem_windows shape.
static func phase_start_window_entries() -> Array:
	var out: Array = []
	if not enabled():
		return out
	var ph := int(Common.current_phase())
	if not ph in [int(GameStateData.Phase.COMMAND), int(GameStateData.Phase.MOVEMENT), int(GameStateData.Phase.SHOOTING),
			int(GameStateData.Phase.CHARGE), int(GameStateData.Phase.FIGHT)]:
		return out
	var active := Common.active_player()
	for p in [active, 2 if active == 1 else 1]:
		if window_offers(p, WINDOW_PHASE_START, {}).is_empty():
			continue
		out.append({"player": p, "window_id": WINDOW_PHASE_START, "ctx": {"header": "Start of the phase — enhancement abilities", "decider_prompt": "use an enhancement ability?"}})
	return out

static func use_rule_offer(player: int, sid: String, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	match sid:
		RULE_CADUCATRIX:
			return _use_caducatrix(player, target_unit_id)
		RULE_INSPIRATIONAL:
			return _use_inspirational(player, target_unit_id, ctx)
		RULE_SALLY_FORTH:
			return _use_sally_forth(player, target_unit_id, ctx)
		RULE_HUNTRESS:
			return _use_huntress(player, target_unit_id, ctx)
		RULE_BLINDING_LIGHT:
			return _use_blinding_light(player, target_unit_id, ctx)
		RULE_EAGLES_EYE:
			return _use_eagles_eye(player, target_unit_id)
	return {"success": false, "error": "unknown Custodes enhancement rule offer %s" % sid, "diffs": []}

static func _offer(sid: String, name: String, type_text: String, effect: String, targets: Array) -> Dictionary:
	return {"stratagem_id": sid, "name": name, "cp_cost": 0, "cus11e_rule": true, "rule": true,
		"type": type_text, "effect_text": effect, "targets": targets}

# --- Pareldor's Caducatrix ---------------------------------------------------

static func _caducatrix_offers(player: int) -> Array:
	var targets: Array = []
	for b in bearers(player, CADUCATRIX):
		if bool(b.get("flags", {}).get(F_CADUCATRIX_USED, false)) or not Common.is_on_battlefield(b):
			continue
		var lost := 0
		for m in b.get("models", []):
			if m.get("alive", true):
				lost += int(m.get("wounds", 1)) - int(m.get("current_wounds", m.get("wounds", 1)))
		if lost <= 0:
			continue
		targets.append({"unit_id": str(b.id), "label": "%s (%d wound%s lost)" % [Common.unit_name(str(b.id)), lost, "" if lost == 1 else "s"]})
	if targets.is_empty():
		return []
	return [_offer(RULE_CADUCATRIX, "PARELDOR'S CADUCATRIX", "Enhancement — Aquilan Shield (once per battle, free)",
		"(Once per battle, per army) At the start of any phase, this model heals D3+3 wounds.", targets)]

static func _use_caducatrix(player: int, uid: String) -> Dictionary:
	var ok := false
	for o in _caducatrix_offers(player):
		for t in o.targets:
			ok = ok or str(t.unit_id) == uid
	if not ok:
		return {"success": false, "error": "Pareldor's Caducatrix cannot be used on %s now" % uid, "diffs": []}
	var u := Common.unit(uid)
	var rng = _rng()
	var heal := int(ceil(float(_d6(rng)) / 2.0)) + 3
	var diffs: Array = [{"op": "set", "path": "units.%s.flags.%s" % [uid, F_CADUCATRIX_USED], "value": true}]
	var healed := 0
	var models: Array = u.get("models", [])
	for i in range(models.size()):
		var m: Dictionary = models[i]
		if not m.get("alive", true):
			continue
		var maxw := int(m.get("wounds", 1))
		var cur := int(m.get("current_wounds", maxw))
		var nw := mini(maxw, cur + heal - healed)
		healed += nw - cur
		diffs.append({"op": "set", "path": "units.%s.models.%d.current_wounds" % [uid, i], "value": nw})
		break  # "this model"
	Common.apply_diffs(diffs)
	var msg := "PARELDOR'S CADUCATRIX — %s heals %d wound%s (rolled D3+3 = %d)" % [Common.unit_name(uid), healed, "" if healed == 1 else "s", heal]
	_log(msg)
	_event(player, msg)
	_toast(msg)
	return {"success": true, "diffs": diffs, "stratagem_name": "Pareldor's Caducatrix", "message": msg}

# --- Inspirational Exemplar ---------------------------------------------------

static func _inspirational_offers(player: int) -> Array:
	var bs := bearers(player, INSPIRATIONAL)
	if bs.is_empty():
		return []
	for b in bs:
		if int(b.get("flags", {}).get(F_INSPIRATIONAL_ROUND, -1)) == Common.battle_round():
			return []  # once per battle round, per army
	var targets: Array = []
	var units: Dictionary = Common.state().get("units", {})
	for b in bs:
		if not Common.is_on_battlefield(b):
			continue
		for uid in units:
			var u: Dictionary = units[uid]
			if int(u.get("owner", 0)) != player or not Common.is_on_battlefield(u):
				continue
			if u.get("attached_to", null) != null and str(u.get("attached_to", "")) != "":
				continue
			if not Common.has_keyword(u, "ADEPTUS CUSTODES") or not _battle_shocked(u):
				continue
			if targets.any(func(t): return t.unit_id == str(uid)):
				continue
			var d := INF
			for gu in group_units(u):
				d = minf(d, Common.unit_distance_inches(gu, b))
			if d <= INSPIRATIONAL_RANGE_IN + 0.001:
				targets.append({"unit_id": str(uid), "label": "%s (%.1f\")" % [Common.unit_name(str(uid)), d], "bearer_id": str(b.id)})
	if targets.is_empty():
		return []
	return [_offer(RULE_INSPIRATIONAL, "INSPIRATIONAL EXEMPLAR", "Enhancement — Auric Champions (once per battle round, free)",
		"(Once per battle round, per army) At the start of any phase, you can select one friendly battle-shocked ADEPTUS CUSTODES unit within 9\" of this model. That unit is no longer battle-shocked.", targets)]

static func _use_inspirational(player: int, uid: String, _ctx: Dictionary) -> Dictionary:
	var bearer := ""
	for o in _inspirational_offers(player):
		for t in o.targets:
			if str(t.unit_id) == uid:
				bearer = str(t.bearer_id)
	if bearer == "":
		return {"success": false, "error": "Inspirational Exemplar cannot target %s now" % uid, "diffs": []}
	var diffs: Array = [{"op": "set", "path": "units.%s.flags.%s" % [bearer, F_INSPIRATIONAL_ROUND], "value": Common.battle_round()}]
	diffs.append_array(Common.set_flag_diffs(Common.attached_group_ids(uid), "battle_shocked", false))
	Common.apply_diffs(diffs)
	var msg := "INSPIRATIONAL EXEMPLAR — %s is no longer battle-shocked" % Common.unit_name(uid)
	_log(msg)
	_event(player, msg)
	_toast(msg)
	return {"success": true, "diffs": diffs, "stratagem_name": "Inspirational Exemplar", "message": msg}

# --- Sally Forth ----------------------------------------------------------------

static func _sally_forth_offers(player: int) -> Array:
	if int(Common.current_phase()) != int(GameStateData.Phase.CHARGE) or Common.active_player() != player:
		return []
	var targets: Array = []
	var units: Dictionary = Common.state().get("units", {})
	for b in bearers(player, SALLY_FORTH):
		if not Common.is_on_battlefield(b) or str(b.get("flags", {}).get(F_SALLY_FORTH_STAMP, "")) == stamp():
			continue
		for uid in units:
			var u: Dictionary = units[uid]
			if int(u.get("owner", 0)) != player or not Common.is_on_battlefield(u):
				continue
			if u.get("attached_to", null) != null and str(u.get("attached_to", "")) != "":
				continue
			if not (Common.has_keyword(u, "ADEPTUS CUSTODES") and group_kw(u, "INFANTRY")):
				continue
			var d := INF
			for gu in group_units(u):
				d = minf(d, Common.unit_distance_inches(gu, b))
			if d > SALLY_FORTH_RANGE_IN + 0.001:
				continue
			var advanced := false
			for gu in group_units(u):
				if bool(gu.get("flags", {}).get("advanced", false)):
					advanced = true
			targets.append({"unit_id": str(uid), "label": "%s%s" % [Common.unit_name(str(uid)), " (advanced)" if advanced else ""], "bearer_id": str(b.id), "advanced": advanced})
	if targets.is_empty():
		return []
	return [_offer(RULE_SALLY_FORTH, "SALLY FORTH", "Enhancement — Solar Watch (free)",
		"At the start of your Charge phase, select one friendly ADEPTUS CUSTODES INFANTRY unit within 6\" of this model. If that unit made an advance move this turn, that advance move does not prevent that unit from being eligible to declare a charge.", targets)]

static func _use_sally_forth(player: int, uid: String, _ctx: Dictionary) -> Dictionary:
	var bearer := ""
	for o in _sally_forth_offers(player):
		for t in o.targets:
			if str(t.unit_id) == uid:
				bearer = str(t.bearer_id)
	if bearer == "":
		return {"success": false, "error": "Sally Forth cannot select %s now" % uid, "diffs": []}
	var diffs: Array = [{"op": "set", "path": "units.%s.flags.%s" % [bearer, F_SALLY_FORTH_STAMP], "value": stamp()}]
	diffs.append_array(_flag_diffs_group(uid, F_SALLY_FORTH, turn_stamp()))
	Common.apply_diffs(diffs)
	var msg := "SALLY FORTH — %s's advance move does not prevent it from declaring a charge this turn" % Common.unit_name(uid)
	_log(msg)
	_event(player, msg)
	return {"success": true, "diffs": diffs, "stratagem_name": "Sally Forth", "message": msg, "reopen_window": false}

# --- Huntress' Eye ----------------------------------------------------------------

static func _huntress_offers(player: int) -> Array:
	if Common.active_player() != player or int(Common.current_phase()) != int(GameStateData.Phase.MOVEMENT):
		return []
	var targets: Array = []
	var units: Dictionary = Common.state().get("units", {})
	var re = Common.rules()
	for b in bearers(player, HUNTRESS):
		if not Common.is_on_battlefield(b) or str(b.get("flags", {}).get(F_HUNTRESS_STAMP, "")) == stamp():
			continue
		var head := Common.head_id(str(b.id))
		var opts: Array = []
		for eid in units:
			var e: Dictionary = units[eid]
			if int(e.get("owner", 0)) == player or not Common.is_on_battlefield(e):
				continue
			if e.get("attached_to", null) != null and str(e.get("attached_to", "")) != "":
				continue
			var d := INF
			var visible := false
			for gid in Common.attached_group_ids(head):
				var gu := Common.unit(str(gid))
				d = minf(d, Common.unit_distance_inches(gu, e))
				if re and re.has_method("_has_los_to_target_unit") and bool(re._has_los_to_target_unit(str(gid), str(eid), Common.state())):
					visible = true
			if d > HUNTRESS_RANGE_IN + 0.001 or not visible:
				continue
			opts.append({"id": str(eid), "label": "%s (%.1f\")" % [Common.unit_name(str(eid)), d]})
		if opts.is_empty():
			continue
		targets.append({"unit_id": str(b.id), "label": Common.unit_name(str(b.id)),
			"secondary": {"kind": "unit", "prompt": "HUNTRESS' EYE: select one visible enemy unit within 12\" — it makes a battle-shock roll at -1", "options": opts}})
	if targets.is_empty():
		return []
	return [_offer(RULE_HUNTRESS, "HUNTRESS' EYE", "Enhancement — Null Maiden Vigil (free)",
		"In your Movement phase, you can select one visible enemy unit within 12\" of this unit. That unit makes a battle-shock roll, with -1 to that battle-shock roll.", targets)]

static func _use_huntress(player: int, bearer_id: String, ctx: Dictionary) -> Dictionary:
	var eid := str(ctx.get("secondary_id", ""))
	var ok := false
	for o in _huntress_offers(player):
		for t in o.targets:
			if str(t.unit_id) != bearer_id:
				continue
			for opt in t.get("secondary", {}).get("options", []):
				ok = ok or str(opt.id) == eid
	if not ok:
		return {"success": false, "error": "Huntress' Eye: pick a visible enemy unit within 12\"", "diffs": []}
	var diffs: Array = [{"op": "set", "path": "units.%s.flags.%s" % [bearer_id, F_HUNTRESS_STAMP], "value": stamp()}]
	Common.apply_diffs(diffs)
	var line := "HUNTRESS' EYE — %s glares at %s" % [Common.unit_name(bearer_id), Common.unit_name(eid)]
	var fam = Common.autoload("FactionAbilityManager")
	var e := Common.unit(eid)
	var cp = load("res://phases/CommandPhase.gd")
	var immune: bool = cp != null and bool(cp._has_battle_shock_immunity(e.get("meta", {}).get("keywords", []), e.get("meta", {}).get("abilities", [])))
	if immune:
		line += ": it is immune to battle-shock"
	elif fam and fam.has_method("force_battle_shock_test"):
		var r: Dictionary = fam.force_battle_shock_test(eid, -1, "Huntress' Eye")
		diffs.append_array(r.get("diffs", []))
		line += ": battle-shock roll %s -1 = %d vs Ld %d — %s" % [str(r.get("dice", [])), int(r.get("total", 0)), int(r.get("leadership", 0)),
			"passed" if r.get("passed", true) else "FAILED, battle-shocked"]
	_log(line)
	_event(player, line)
	_toast(line)
	return {"success": true, "diffs": diffs, "stratagem_name": "Huntress' Eye", "message": line}

# --- Auriferous Orb: BLINDING LIGHT -----------------------------------------------

static func _blinding_light_offers(player: int, ctx: Dictionary) -> Array:
	if Common.active_player() != player or int(Common.current_phase()) != int(GameStateData.Phase.SHOOTING):
		return []
	var shooter := str(ctx.get("unit_id", ""))
	if shooter == "":
		return []
	var bearer := {}
	for gid in Common.attached_group_ids(shooter):
		var gu := Common.unit(str(gid))
		if has(gu, AURIFEROUS_ORB):
			bearer = gu
	if bearer.is_empty() or str(bearer.get("flags", {}).get(F_BLINDING_LIGHT_STAMP, "")) == stamp():
		return []
	var orb_hits: Array = orb_hit_unit_ids(shooter)
	var opts: Array = []
	for tid in orb_hits:
		var t := Common.unit(str(tid))
		if t.is_empty() or not Common.is_alive(t) or int(t.get("owner", 0)) == player:
			continue
		opts.append({"id": str(tid), "label": Common.unit_name(str(tid))})
	if opts.is_empty():
		return []
	return [_offer(RULE_BLINDING_LIGHT, "BLINDING LIGHT (Auriferous Orb)", "Enhancement weapon ability — Emissaries Imperatus (free)",
		"In your Shooting phase, when this unit has shot, select one enemy unit hit by this unit's Auriferous Orb weapon. That enemy unit's attacks have -1 to hit rolls until the start of your next turn.",
		[{"unit_id": str(bearer.id), "label": Common.unit_name(str(bearer.id)),
			"secondary": {"kind": "unit", "prompt": "BLINDING LIGHT: select one enemy unit hit by the Auriferous Orb", "options": opts}}])]

static func _use_blinding_light(player: int, bearer_id: String, ctx: Dictionary) -> Dictionary:
	var eid := str(ctx.get("secondary_id", ""))
	var ok := false
	for o in _blinding_light_offers(player, ctx):
		for t in o.targets:
			for opt in t.get("secondary", {}).get("options", []):
				ok = ok or str(opt.id) == eid
	if not ok:
		return {"success": false, "error": "Blinding Light: pick an enemy unit hit by the Auriferous Orb", "diffs": []}
	var diffs: Array = [{"op": "set", "path": "units.%s.flags.%s" % [bearer_id, F_BLINDING_LIGHT_STAMP], "value": stamp()}]
	diffs.append_array(_flag_diffs_group(Common.head_id(eid), F_BLINDING_LIGHT, player))
	Common.apply_diffs(diffs)
	var msg := "BLINDING LIGHT — %s's attacks have -1 to hit until the start of your next turn" % Common.unit_name(eid)
	_log(msg)
	_event(player, msg)
	_toast(msg)
	return {"success": true, "diffs": diffs, "stratagem_name": "Blinding Light", "message": msg, "reopen_window": true}

## Auriferous Orb hits this phase: "<shooter head>|<stamp>" -> [target ids]
## (host-side ledger fed by the RulesEngine ranged hit tally; cleared at the
## end of every phase).
static var _orb_hits: Dictionary = {}

static func note_orb_hits(shooter_id: String, target_unit_id: String, hits: int) -> void:
	if shooter_id == "" or target_unit_id == "" or hits <= 0:
		return
	var key := "%s|%s" % [Common.head_id(shooter_id), stamp()]
	var arr: Array = _orb_hits.get(key, [])
	var head := Common.head_id(target_unit_id)
	if not head in arr:
		arr.append(head)
	_orb_hits[key] = arr
	_log("Auriferous Orb (%s) hit %s — BLINDING LIGHT target" % [shooter_id, head])

## The enemy units the Auriferous Orb of `shooter_id`'s (Attached) unit hit this phase.
static func orb_hit_unit_ids(shooter_id: String) -> Array:
	return _orb_hits.get("%s|%s" % [Common.head_id(shooter_id), stamp()], []).duplicate()

# --- Eagle's Eye ------------------------------------------------------------------

static func _eagles_eye_offers(player: int, ctx: Dictionary) -> Array:
	var targets: Array = []
	var tids: Array = ctx.get("target_unit_ids", [])
	for b in bearers(player, EAGLES_EYE):
		if bool(b.get("flags", {}).get(F_EAGLES_EYE_USED, false)) or not Common.is_alive(b):
			continue
		var head := Common.head_id(str(b.id))
		var targeted := false
		for tid in tids:
			if Common.head_id(str(tid)) == head:
				targeted = true
		if not targeted:
			continue
		targets.append({"unit_id": str(b.id), "label": Common.unit_name(str(b.id))})
	if targets.is_empty():
		return []
	return [_offer(RULE_EAGLES_EYE, "EAGLE'S EYE", "Enhancement — Guardians of the Throne (once per battle, free)",
		"(Once per battle, per army) When attacks are allocated to this model, you can use this ability. If you do, this model has 3+ InSv (until the end of the phase).", targets)]

static func _use_eagles_eye(player: int, bearer_id: String) -> Dictionary:
	var b := Common.unit(bearer_id)
	if not has(b, EAGLES_EYE) or int(b.get("owner", 0)) != player or bool(b.get("flags", {}).get(F_EAGLES_EYE_USED, false)):
		return {"success": false, "error": "Eagle's Eye cannot be used on %s" % bearer_id, "diffs": []}
	var diffs: Array = [
		{"op": "set", "path": "units.%s.flags.%s" % [bearer_id, F_EAGLES_EYE_USED], "value": true},
		{"op": "set", "path": "units.%s.flags.%s" % [bearer_id, F_EAGLES_EYE_ACTIVE], "value": stamp()},
	]
	Common.apply_diffs(diffs)
	var msg := "EAGLE'S EYE — %s has a 3+ invulnerable save this phase (once per battle)" % Common.unit_name(bearer_id)
	_log(msg)
	_event(player, msg)
	_toast(msg)
	return {"success": true, "diffs": diffs, "stratagem_name": "Eagle's Eye", "message": msg}

# ===========================================================================
# AI (synchronous — never stalls a window)
# ===========================================================================

static func ai_decide(player: int, _window_id: String, offers: Array, ctx: Dictionary) -> Dictionary:
	for offer in offers:
		var sid := str(offer.get("stratagem_id", ""))
		if not is_rule_offer_id(sid):
			continue
		var targets: Array = offer.get("targets", [])
		if targets.is_empty():
			continue
		match sid:
			RULE_CADUCATRIX:
				# Heal once the bearer has lost at least 4 wounds (D3+3 is used in full).
				for t in targets:
					var u := Common.unit(str(t.unit_id))
					for m in u.get("models", []):
						if m.get("alive", true) and int(m.get("wounds", 1)) - int(m.get("current_wounds", 0)) >= 4:
							return _ai(sid, str(t.unit_id), {}, offer)
			RULE_INSPIRATIONAL, RULE_SALLY_FORTH:
				var pick := ""
				for t in targets:
					if sid == RULE_SALLY_FORTH and not bool(t.get("advanced", false)):
						continue
					pick = str(t.unit_id)
					break
				if pick != "":
					return _ai(sid, pick, {}, offer)
			RULE_HUNTRESS, RULE_BLINDING_LIGHT:
				var t0: Dictionary = targets[0]
				var opts: Array = t0.get("secondary", {}).get("options", [])
				var best := ""
				var best_pts := -1.0
				for o in opts:
					var e := Common.unit(str(o.id))
					if sid == RULE_HUNTRESS and _battle_shocked(e):
						continue
					var pts := float(e.get("meta", {}).get("points", 0))
					if pts > best_pts:
						best_pts = pts
						best = str(o.id)
				if best != "":
					return _ai(sid, str(t0.unit_id), {"secondary_id": best}, offer)
			RULE_EAGLES_EYE:
				# Use it when the bearer stands alone (attacks are allocated to it).
				for t in targets:
					var bu := Common.unit(str(t.unit_id))
					var attached := bu.get("attached_to", null) != null and str(bu.get("attached_to", "")) != ""
					if not attached:
						return _ai(sid, str(t.unit_id), {}, offer)
	return {}

static func _ai(sid: String, uid: String, c: Dictionary, offer: Dictionary) -> Dictionary:
	return {"use": true, "stratagem_id": sid, "target_unit_id": uid, "context": c, "name": str(offer.get("name", sid))}

# ===========================================================================
# Lifecycle
# ===========================================================================

## Start of `player`'s Command phase (= start of their turn): Blinding Light
## they applied ends; Sally Forth / Combat Deployment turn flags are stale.
static func on_command_phase_start(player: int) -> void:
	var units: Dictionary = Common.state().get("units", {})
	var diffs: Array = []
	for uid in units:
		var flags: Dictionary = units[uid].get("flags", {})
		if flags.has(F_BLINDING_LIGHT) and int(flags.get(F_BLINDING_LIGHT, 0)) == player:
			diffs.append({"op": "remove", "path": "units.%s.flags.%s" % [uid, F_BLINDING_LIGHT]})
		for f in [F_SALLY_FORTH, F_COMBAT_DEPLOYMENT]:
			if flags.has(f) and str(flags.get(f, "")) != turn_stamp():
				diffs.append({"op": "remove", "path": "units.%s.flags.%s" % [uid, f]})
	if not diffs.is_empty():
		var gs = Common.game_state()
		if gs and gs.has_method("apply_state_changes"):
			gs.apply_state_changes(diffs)
		_log("start of P%d's Command phase — %d enhancement flag op(s) cleared" % [player, diffs.size()])

## End of a phase: Eagle's Eye's 3+ InSv ends; the Orb hit ledger resets.
static func on_phase_end(_phase: int) -> void:
	_orb_hits.clear()
	var units: Dictionary = Common.state().get("units", {})
	var diffs: Array = []
	for uid in units:
		if units[uid].get("flags", {}).has(F_EAGLES_EYE_ACTIVE):
			diffs.append({"op": "remove", "path": "units.%s.flags.%s" % [uid, F_EAGLES_EYE_ACTIVE]})
	if not diffs.is_empty():
		var gs = Common.game_state()
		if gs and gs.has_method("apply_state_changes"):
			gs.apply_state_changes(diffs)
