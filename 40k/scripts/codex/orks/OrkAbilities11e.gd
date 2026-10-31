extends RefCounted

## OrkAbilities11e — Codex: Orks (11e) DATASHEET abilities (WP-O6).
##
## Contract: .llm/codex_11e_wahapedia/IMPLEMENTATION.md (§2 code layout, §4
## ownership). Printed text: .llm/codex_11e_wahapedia/orks/wahapedia/
## Datasheets_abilities.csv. Audit + rulings: .llm/codex_11e_wahapedia/
## ork_abilities_audit.md and RULINGS.md (WP-O6).
##
## Everything is static. Engine files only call into this module through thin
## hooks (one line + a comment):
##   RulesEngine        attack / defence modifiers (attack_mods, defence_mods,
##                      incoming_wound_penalty), Lone Operative, objective OC
##   EffectPrimitives   invulnerable save / damage reduction / AP worsening of
##                      the TARGET (one hook per getter covers every resolver)
##   ModifierStack      [IGNORES COVER] / benefit of cover
##   StratagemManager   activated abilities ride the stratagem-window framework:
##                      get_all_window_offers appends window_offers(); use_stratagem
##                      routes "ork11e_ab_*" ids to use()
##   AIDecisionMaker    ai_score() for those offers (the AI never stalls: windows
##                      are answered synchronously)
##   PhaseManager       on_phase_transition() — flag expiry
##   phases             charge / advance / move characteristic modifiers and the
##                      automatic triggers (Mobbed, Thievin' Scavengers, ...)
##
## Ability names are matched FOLDED (case, apostrophes ’/' and punctuation
## ignored, a trailing "(…)" dropped), so army files, the browser army builder
## (its canon table predates this module) and old saves all dispatch.
##
## Autoloads are reached late-bound through OrkCodexCommon (a headless
## `godot -s` test compiles this script before autoloads are registered).

const Common = preload("res://scripts/stratagems/ork_codex/OrkCodexCommon.gd")

const PX_PER_INCH := 40.0

# Phase enum mirror (GameState.Phase) — kept local so this script never needs
# the GameState autoload at compile time.
const PH_COMMAND := 6
const PH_MOVEMENT := 7
const PH_SHOOTING := 8
const PH_CHARGE := 9
const PH_FIGHT := 10

## slug -> FOLDED printed name (see fold()).
const NAMES := {
	"boss_ammo_runt": "boss ammo runt",
	"might_is_right": "might is right",
	"intimidating_motivation": "intimidating motivation",
	"krushin_impetus": "krushin impetus",
	"waaagh_energy": "waaagh energy",
	"fix_dat_armour_up": "fix dat armour up",
	"more_dakka": "more dakka",
	"kustom_force_field": "kustom force field",
	"grand_warlords_ladz": "da grand warlords ladz",
	"makari": "makari hoist dat banner",
	"prophet": "prophet of da great waaagh",
	"kunnin_infiltrator": "kunnin infiltrator",
	"deff_from_the_shadows": "deff from the shadows",
	"kustom_dakka": "kustom dakka",
	"clever_know_wotz": "clever know wotz",
	"crude_surgery": "crude surgery",
	"catch_dat_red_bit": "catch dat red bit",
	"ammo_runts": "ammo runts",
	"tide_of_muscle": "tide of muscle",
	"never_too_busy": "never too busy to fight",
	"downtrodden": "downtrodden",
	"thievin_scavengers": "thievin scavengers",
	"rokkit_barrage": "rokkit barrage",
	"bomb_squigs": "bomb squigs",
	"pulsa_rokkit": "pulsa rokkit",
	"get_out_da_way": "get out da way",
	"paired_krumpas": "paired krumpas",
	"arrogant_invulnerability": "arrogant invulnerability",
	"krumpin_time": "krumpin time",
	"found_em": "found em",
	"taktikal_know_wotz": "taktikal know wotz",
	"nowhere_to_hide": "nowhere to hide",
	"bomb_squig": "bomb squig",
	"pilin_out": "pilin out",
	"rokkit_charge": "rokkit charge",
	"deff_from_above": "deff from above",
	"aerial_manoover": "aerial manoover",
	"strafing_run": "strafing run",
	"burna_bomb": "burna bomb",
	"boom_bomb": "boom bomb",
	"go_fer_da_weak_spot": "go fer da weak spot",
	"blastajet_force_field": "blastajet force field",
	"high_speed_carnage": "high speed carnage",
	"drive_by_skorchin": "drive by skorchin",
	"madcap_artillery": "madcap artillery",
	"mobile_fortress": "mobile fortress",
	"dread_ard": "dread ard",
	"spiteful_power_trip": "spiteful power trip",
	"gut_hatch": "gut hatch",
	"big_an_shooty": "big an shooty",
	"big_an_stompy": "big an stompy",
	"finderz_keeperz": "finderz keeperz",
	"idol_of_belligerence": "idol of belligerence",
	"waaagh_effigy": "waaagh effigy",
	"walking_bastion": "walking bastion",
	"support_shokka": "support shokka",
	"get_back_in_da_race": "get back in da race",
	"fuel_mixa_grot": "fuel mixa grot",
	"super_runts": "super runts",
	"keep_huntin": "keep huntin",
	"dodge_dis": "dodge dis",
	"thundering_stampede": "thundering stampede",
	"boss_of_da_hunt": "boss of da hunt",
	"push_dat_bit_back_in": "push dat bit back in",
	"hardy_bioniks": "hardy bioniks",
	"runnin_wiv_da_herd": "runnin wiv da herd",
	"one_last_kill": "one last kill",
	"da_bigger_dey_iz": "da bigger dey iz",
	"beast_snagga_following": "beast snagga following",
	"mobbed": "mobbed",
	"brutal_impact": "brutal impact",
	"wurrboy": "wurrboy",
	"fully_loaded_butchery": "fully loaded butchery",
	"tramplasquig_charge": "tramplasquig charge",
	"raucous_occupants": "raucous occupants",
	"fortification": "fortification",
	"ramshackle_cover": "ramshackle cover",
	"shokk_boosta": "shokk boosta",
	"trophy_hunters": "trophy hunters",
	"full_throttle": "full throttle",
	"turbo_engine": "turbo engine",
	"shokk_attack_engine": "shokk attack engine",
	"pulse_jet": "pulse jet",
	"waaagh_banner": "waaagh banner",
	"sumfin_to_prove": "sumfin to prove",
	"even_more_dakka": "even more dakka",
	"blitz_dem_gitz": "blitz dem gitz",
	"thatll_learn_ya": "thatll learn ya",
	"speednob_support": "speednob support",
	"bust_em": "bust em",
	"mobile_arsenal": "mobile arsenal",
	"nazdregs_know_wotz": "nazdregs know wotz",
	"supreme_kunnin": "supreme kunnin",
	"squig_barrage": "squig barrage",
	"da_jump": "da jump",
	"warpath": "warpath",
	"beastscent": "beastscent",
}

## Display names (logs, dialog cards).
const DISPLAY := {
	"boss_ammo_runt": "Boss' Ammo Runt", "ammo_runts": "Ammo Runts", "pulsa_rokkit": "Pulsa Rokkit",
	"bomb_squigs": "Bomb Squigs", "bomb_squig": "Bomb Squig", "rokkit_charge": "Rokkit Charge",
	"krushin_impetus": "Krushin' Impetus", "intimidating_motivation": "Intimidating Motivation",
	"get_back_in_da_race": "Get Back in da Race!", "keep_huntin": "Keep Huntin'!",
	"clever_know_wotz": "Clever Know-wotz", "makari": "Makari, Hoist Dat Banner!",
	"found_em": "Found 'Em!", "drive_by_skorchin": "Drive-by Skorchin'", "gut_hatch": "Gut Hatch",
	"supreme_kunnin": "Supreme Kunnin'", "kunnin_infiltrator": "Kunnin' Infiltrator",
	"aerial_manoover": "Aerial Manoover", "burna_bomb": "Burna Bomb", "boom_bomb": "Boom Bomb",
	"rokkit_barrage": "Rokkit Barrage", "squig_barrage": "Squig Barrage", "bust_em": "Bust 'Em",
	"madcap_artillery": "Madcap Artillery", "thatll_learn_ya": "That'll Learn Ya",
	"crude_surgery": "Crude Surgery", "catch_dat_red_bit": "Catch Dat Red Bit",
	"fix_dat_armour_up": "Fix Dat Armour Up", "push_dat_bit_back_in": "Push Dat Bit Back In",
	"full_throttle": "Full Throttle", "shokk_attack_engine": "Shokk Attack Engine",
	"shokk_boosta": "Shokk-boosta", "warpath": "Warpath", "da_jump": "Da Jump",
	"beastscent": "Beastscent", "mobbed": "Mobbed", "thievin_scavengers": "Thievin' Scavengers",
	"idol_of_belligerence": "Idol of Belligerence", "pilin_out": "Pilin' Out",
	"one_last_kill": "One Last Kill", "taktikal_know_wotz": "Taktikal Know-wotz",
}

# ---------------------------------------------------------------------------
# Flags written by this module (unit flags; never the effect_ prefix, which
# ShootingPhase wipes on exit). Each has a clear point in on_phase_transition.
# ---------------------------------------------------------------------------
const F_PHASE := "ork11e_ab_phase"            # {flag_name: phase stamp} for phase-scoped flags
const F_AMMO_RUNTS := "ork11e_ab_ammo_runts"  # +1 to hit, ranged (this unit)
const F_BOSS_AMMO_RUNT := "ork11e_ab_boss_ammo_runt"  # +1 to hit, ranged (this model)
const F_PULSA_TARGET := "ork11e_ab_pulsa_target"     # target unit id: +1 AP, [LETHAL HITS]
const F_ROKKIT_CHARGE := "ork11e_ab_rokkit_charge"   # melee +1 A, +1 S, [HAZARDOUS]
const F_WARPATH := "ork11e_ab_warpath"        # "weirdboy" | "kill_rig"
const F_KNOW_WOTZ := "ork11e_ab_know_wotz"    # {player}: +1 to hit until the start of P's next Movement phase
const F_FOUND_EM := "ork11e_ab_found_em"      # {player}: +3" detection range until the end of the turn
const F_NO_OVERWATCH := "ork11e_ab_no_overwatch"  # {player}: cannot be targeted with Fire Overwatch until end of turn
const F_RILED := "ork11e_ab_riled"            # {player, until, source, set}: riled up by a datasheet ability
const F_SQUIG_COVERED := "ork11e_ab_squig_covered"  # {player}: -1 to hit until the start of P's next turn
const F_BUSTED := "ork11e_ab_busted"          # {player}: friendly SPEED FREEKS attacks vs it have [LETHAL HITS] (end of turn)
const F_MADCAP := "ork11e_ab_madcap"          # {player, effect}: wobbled / zapped / smashed / grounded
const F_BURNA_BOMBED := "ork11e_ab_burna_bombed"  # {player}: cannot be hidden; ranged attacks vs it [IGNORES COVER]
const F_BEASTSCENT := "ork11e_ab_beastscent"  # {player}: +1 to wound vs MONSTER/VEHICLE until the end of the turn
const F_ENGINE := "ork11e_ab_engine"          # {player, engine}: Full Throttle choice until the start of P's next Command phase
const F_USES := "ork11e_ab_uses"              # {slug: {battle, round_key, turn_key, phase_key}} usage counters
const F_DA_JUMP_DS := "ork11e_ab_da_jump_ds"  # true: this unit has Deep Strike (Da Jump)
const F_SHOKK_BOOSTA := "ork11e_ab_shokk_boosta"  # true while the boosted advance move is being made
const F_FOD_MODE := "ork11e_fod_mode"          # shared with OrkCodexFight (Fight On Death)
const F_FOD_SOURCE := "ork11e_fod_source"

const SID_PREFIX := "ork11e_ab_"

## WP-O5: Codex: Orks (11e) ENHANCEMENTS (OrkEnhancements11e.gd) — loaded on
## first use (it preloads this script; no preload cycle). Its activated
## enhancements ride this module's ability-offer path ("ork11e_ab_enh_*").
static var _enh_script = null
static func _enh():
	if _enh_script == null:
		_enh_script = load("res://scripts/codex/orks/OrkEnhancements11e.gd")
	return _enh_script

# ===========================================================================
# Names
# ===========================================================================

## Folded ability name: lower case, apostrophes and a trailing "(…)" dropped,
## every other non-alphanumeric run turned into one space.
static func fold(name: String) -> String:
	var s := str(name).strip_edges()
	var p := s.find("(")
	if p > 0:
		s = s.substr(0, p)
	s = s.to_lower().replace("’", "").replace("‘", "").replace("'", "").replace("`", "").replace("…", " ")
	var out := ""
	var pending_space := false
	for c in s:
		var alnum: bool = (c >= "a" and c <= "z") or (c >= "0" and c <= "9")
		if alnum:
			if pending_space and out != "":
				out += " "
			out += c
			pending_space = false
		else:
			pending_space = true
	return out

static func _ability_name(ab) -> String:
	if ab is Dictionary:
		return str(ab.get("name", ""))
	if ab is String:
		return ab
	return ""

## True when unit `u` itself carries the codex ability `slug`.
static func has(u: Dictionary, slug: String) -> bool:
	var want: String = NAMES.get(slug, "")
	if want == "" or u.is_empty():
		return false
	# Taktikal Know-wotz (Kommandos): after the 5 + 5 split, one half has Bomb
	# Squig and the other Found 'Em! (GameState.split_unit_at_deployment).
	var tk = u.get("flags", {}).get("ork11e_ab_tk_split", null)
	if tk != null and slug in ["bomb_squig", "found_em"] and str(tk) != slug:
		return false
	for ab in u.get("meta", {}).get("abilities", []):
		if fold(_ability_name(ab)) == want:
			return true
	# WP-O5 Boss Boomer: a WAGON carrying an embarked WARBOSS has its
	# Intimidating Motivation / Keep Huntin'.
	if slug == "intimidating_motivation" or slug == "keep_huntin":
		return _enh().boss_boomer_grants(u, slug)
	return false

static func has_id(unit_id: String, slug: String) -> bool:
	return has(Common.unit(unit_id), slug)

## Alive components of the (Attached) unit `unit_id` (head first). 19.04: a
## leader's / bodyguard's ability stops applying once its last model is gone.
static func group(unit_id: String) -> Array:
	var out: Array = []
	for gid in Common.attached_group_ids(unit_id):
		if Common.is_alive(Common.unit(str(gid))):
			out.append(str(gid))
	if out.is_empty() and unit_id != "":
		out.append(unit_id)
	return out

## Head (bodyguard) id of the Attached unit containing `unit_id`.
static func head_id(unit_id: String) -> String:
	var g := Common.attached_group_ids(unit_id)
	return str(g[0]) if not g.is_empty() else unit_id

## Id of the alive component of `unit_id`'s Attached unit that carries `slug`
## ("" when none) — "this unit has ..." abilities apply to the whole unit.
static func group_holder(unit_id: String, slug: String) -> String:
	for gid in group(unit_id):
		if has(Common.unit(gid), slug):
			return gid
	return ""

static func group_has(unit_id: String, slug: String) -> bool:
	return group_holder(unit_id, slug) != ""

static func group_riled_up(unit_id: String) -> bool:
	for gid in group(unit_id):
		if Common.is_riled_up(Common.unit(gid)):
			return true
	return false

static func group_flag(unit_id: String, flag: String):
	for gid in group(unit_id):
		var v = Common.unit(gid).get("flags", {}).get(flag, null)
		if _flag_set(v):
			return v
	return null

## A flag value counts as set unless it is null or the bool false (values are
## also strings / dictionaries — never compare those with a bool).
static func _flag_set(v) -> bool:
	if v == null:
		return false
	if typeof(v) == TYPE_BOOL:
		return bool(v)
	return true

## group_flag, but the unit dict the caller holds (the resolver's board copy)
## is consulted first — a board that differs from the live GameState (replays,
## headless boards) still sees its own unit's flags.
static func _gf(u: Dictionary, flag: String):
	var v = u.get("flags", {}).get(flag, null)
	if _flag_set(v):
		return v
	return group_flag(_uid(u), flag)

static func group_has_keyword(unit_id: String, kw: String) -> bool:
	for gid in group(unit_id):
		if Common.has_keyword(Common.unit(gid), kw):
			return true
	return false

static func _uid(u: Dictionary) -> String:
	return str(u.get("id", ""))

static func display(slug: String) -> String:
	return str(DISPLAY.get(slug, slug.capitalize()))

static func _phase() -> int:
	var gs = Common.game_state()
	return int(gs.get_current_phase()) if gs != null else -1

static func _round() -> int:
	var gs = Common.game_state()
	return int(gs.get_battle_round()) if gs != null else 0

static func _turn_key() -> String:
	return "%d:%d" % [_round(), Common.active_player()]

static func _phase_key() -> String:
	return "%d:%d:%d" % [_round(), Common.active_player(), _phase()]

static func _event_log(player: int, text: String) -> void:
	var gel = Common.autoload("GameEventLog")
	if gel and gel.has_method("add_player_entry"):
		gel.add_player_entry(player, text)

static func _rng():
	var re = Common.rules()
	if re and re.has_method("make_rng"):
		return re.make_rng()
	return null

static func _d6(rng) -> int:
	if rng != null:
		return int(rng.roll_d6(1)[0])
	return randi_range(1, 6)

static func _d3(rng) -> int:
	return int(ceil(float(_d6(rng)) / 2.0))

# ===========================================================================
# Usage limits (stored on unit / player flags so saves, replays and the
# network all see them)
# ===========================================================================

## Uses of `slug` by `unit_id`: {battle: n, turn_key, turn: n, round_key, round: n, phase_key}.
static func uses(unit_id: String, slug: String) -> Dictionary:
	var all = Common.unit(unit_id).get("flags", {}).get(F_USES, {})
	if typeof(all) != TYPE_DICTIONARY:
		return {}
	var u = all.get(slug, {})
	return u if typeof(u) == TYPE_DICTIONARY else {}

static func used_in_battle(unit_id: String, slug: String) -> int:
	return int(uses(unit_id, slug).get("battle", 0))

static func used_this_turn(unit_id: String, slug: String) -> bool:
	return str(uses(unit_id, slug).get("turn_key", "")) == _turn_key()

static func used_this_round(unit_id: String, slug: String) -> bool:
	return int(uses(unit_id, slug).get("round", -1)) == _round()

static func used_this_phase(unit_id: String, slug: String) -> bool:
	return str(uses(unit_id, slug).get("phase_key", "")) == _phase_key()

## Diff recording one use of `slug` by `unit_id`.
static func use_diff(unit_id: String, slug: String) -> Dictionary:
	var all = Common.unit(unit_id).get("flags", {}).get(F_USES, {})
	var copy: Dictionary = all.duplicate(true) if typeof(all) == TYPE_DICTIONARY else {}
	var u: Dictionary = copy.get(slug, {}) if typeof(copy.get(slug, {})) == TYPE_DICTIONARY else {}
	u["battle"] = int(u.get("battle", 0)) + 1
	u["turn_key"] = _turn_key()
	u["round"] = _round()
	u["phase_key"] = _phase_key()
	copy[slug] = u
	return {"op": "set", "path": "units.%s.flags.%s" % [unit_id, F_USES], "value": copy}

## Army-wide limits ("once per battle round, per army", "once per phase, per
## army", "once per battle, per army") live on the player record.
static func army_uses(player: int, slug: String) -> Dictionary:
	var all = Common.state().get("players", {}).get(str(player), {}).get(F_USES, {})
	if typeof(all) != TYPE_DICTIONARY:
		return {}
	var u = all.get(slug, {})
	return u if typeof(u) == TYPE_DICTIONARY else {}

static func army_used_this_round(player: int, slug: String) -> bool:
	return int(army_uses(player, slug).get("round", -1)) == _round()

static func army_used_this_phase(player: int, slug: String) -> bool:
	return str(army_uses(player, slug).get("phase_key", "")) == _phase_key()

static func army_used_in_battle(player: int, slug: String) -> int:
	return int(army_uses(player, slug).get("battle", 0))

static func army_use_diff(player: int, slug: String) -> Dictionary:
	var all = Common.state().get("players", {}).get(str(player), {}).get(F_USES, {})
	var copy: Dictionary = all.duplicate(true) if typeof(all) == TYPE_DICTIONARY else {}
	var u: Dictionary = copy.get(slug, {}) if typeof(copy.get(slug, {})) == TYPE_DICTIONARY else {}
	u["battle"] = int(u.get("battle", 0)) + 1
	u["round"] = _round()
	u["phase_key"] = _phase_key()
	copy[slug] = u
	return {"op": "set", "path": "players.%d.%s" % [player, F_USES], "value": copy}

# ===========================================================================
# Geometry helpers
# ===========================================================================

static func _models_of(unit_id: String, board: Dictionary = {}) -> Array:
	var out: Array = []
	var units: Dictionary = board.get("units", {}) if not board.is_empty() else Common.state().get("units", {})
	for gid in group(unit_id):
		for m in units.get(gid, Common.unit(gid)).get("models", []):
			if m.get("alive", true) and m.get("position", null) != null:
				out.append(m)
	return out

## Closest edge-to-edge distance (inches) between two Attached units (all components).
static func dist_in(a_id: String, b_id: String, board: Dictionary = {}) -> float:
	var meas = Common.autoload("Measurement")
	var best := INF
	for ma in _models_of(a_id, board):
		for mb in _models_of(b_id, board):
			var d := INF
			if meas and meas.has_method("model_to_model_distance_inches"):
				d = float(meas.model_to_model_distance_inches(ma, mb))
			else:
				d = Common._pos(ma).distance_to(Common._pos(mb)) / PX_PER_INCH
			best = minf(best, d)
	return best

static func within(a_id: String, b_id: String, inches: float, board: Dictionary = {}) -> bool:
	return dist_in(a_id, b_id, board) <= inches + 0.001

## "each model in this unit is within X of ..." (Speednob Support).
static func each_model_within(a_id: String, b_id: String, inches: float) -> bool:
	var meas = Common.autoload("Measurement")
	var bm := _models_of(b_id)
	var am := _models_of(a_id)
	if am.is_empty() or bm.is_empty():
		return false
	for ma in am:
		var best := INF
		for mb in bm:
			var d := INF
			if meas and meas.has_method("model_to_model_distance_inches"):
				d = float(meas.model_to_model_distance_inches(ma, mb))
			else:
				d = Common._pos(ma).distance_to(Common._pos(mb)) / PX_PER_INCH
			best = minf(best, d)
		if best > inches + 0.001:
			return false
	return true

static func _on_board(unit_id: String) -> bool:
	return Common.is_on_battlefield(Common.unit(unit_id))

static func _visible(from_id: String, to_id: String) -> bool:
	var re = Common.rules()
	if re == null or not re.has_method("_has_los_to_target_unit"):
		return true
	return bool(re._has_los_to_target_unit(head_id(from_id), head_id(to_id), Common.state()))

static func _engaged(unit_id: String) -> bool:
	for gid in group(unit_id):
		if Common.is_engaged(gid):
			return true
	return false

## Enemy (Attached-unit heads) of `player` matching `pred` (Callable(id) -> bool).
static func _enemy_heads(player: int, pred: Callable = Callable()) -> Array:
	var out: Array = []
	for uid in Common.state().get("units", {}):
		var u = Common.unit(str(uid))
		if int(u.get("owner", 0)) == player or not Common.is_on_battlefield(u):
			continue
		if head_id(str(uid)) != str(uid):
			continue  # attached character: its bodyguard represents the unit
		if pred.is_valid() and not bool(pred.call(str(uid))):
			continue
		out.append(str(uid))
	return out

static func _friendly_heads(player: int, pred: Callable = Callable()) -> Array:
	var out: Array = []
	for uid in Common.state().get("units", {}):
		var u = Common.unit(str(uid))
		if int(u.get("owner", 0)) != player or not Common.is_on_battlefield(u):
			continue
		if head_id(str(uid)) != str(uid):
			continue
		if pred.is_valid() and not bool(pred.call(str(uid))):
			continue
		out.append(str(uid))
	return out

static func _is_monster_or_vehicle(unit_id: String) -> bool:
	return group_has_keyword(unit_id, "MONSTER") or group_has_keyword(unit_id, "VEHICLE")

## Highest T among the alive models of the (Attached) target unit.
static func _highest_toughness(unit_id: String) -> int:
	var best := 0
	for gid in group(unit_id):
		var u := Common.unit(gid)
		var unit_t := int(u.get("meta", {}).get("stats", {}).get("toughness", 4))
		for m in u.get("models", []):
			if not m.get("alive", true):
				continue
			var mt = m.get("meta", {}).get("stats", {}).get("toughness", null)
			if mt == null:
				mt = m.get("toughness", null)
			best = maxi(best, int(mt) if mt != null else unit_t)
	return best

## 13.09: a unit counts as hidden while every one of its alive models is
## hidden (ruling — "hidden" is defined per model).
static func unit_is_hidden(unit_id: String) -> bool:
	var tm = Common.autoload("TerrainManager")
	if tm == null or not tm.has_method("is_model_hidden"):
		return false
	var any := false
	for gid in group(unit_id):
		var u := Common.unit(gid)
		for m in u.get("models", []):
			if not m.get("alive", true) or m.get("position", null) == null:
				continue
			any = true
			if not tm.is_model_hidden(m, u):
				return false
	return any

## "within range of an objective" (MissionManager's terrain-aware predicate).
static func unit_in_objective_range(unit_id: String) -> bool:
	var mm = Common.autoload("MissionManager")
	var objs: Array = Common.state().get("board", {}).get("objectives", [])
	if objs.is_empty():
		return false
	for m in _models_of(unit_id):
		for obj in objs:
			if mm and mm.has_method("model_in_objective_range"):
				if mm.model_in_objective_range(m, obj):
					return true
	return false

## Objectives `player` controls with `unit_id` within range of them.
static func controlled_objectives_in_range(unit_id: String, player: int) -> Array:
	var mm = Common.autoload("MissionManager")
	var out: Array = []
	if mm == null:
		return out
	for obj in Common.state().get("board", {}).get("objectives", []):
		var oid := str(obj.get("id", ""))
		if int(mm.objective_control_state.get(oid, 0)) != player:
			continue
		for m in _models_of(unit_id):
			if mm.model_in_objective_range(m, obj):
				out.append(oid)
				break
	return out

static func _embarked_model_count(transport_id: String) -> int:
	var n := 0
	var t := Common.unit(transport_id)
	for eid in t.get("transport_data", {}).get("embarked_units", []):
		for m in Common.unit(str(eid)).get("models", []):
			if m.get("alive", true):
				n += 1
	return n

static func _embarked_units(transport_id: String) -> Array:
	var out: Array = []
	for eid in Common.unit(transport_id).get("transport_data", {}).get("embarked_units", []):
		if Common.is_alive(Common.unit(str(eid))):
			out.append(str(eid))
	return out

static func _weapon_name(weapon_profile: Dictionary) -> String:
	return str(weapon_profile.get("name", "")).to_lower()

## The unit that owns a ranged bearer id ("<char_unit>:<model>" composite ids
## belong to attached characters; plain model ids to the attacking unit).
static func _bearer_unit_id(actor_id: String, bearer) -> String:
	var b := str(bearer)
	var at := b.find("@")  # firing-deck loan "<hull>@fd<i>"
	if at > 0:
		return actor_id
	var c := b.find(":")
	if c > 0:
		return b.substr(0, c)
	return actor_id

## "this model's attacks": every bearer of the batch belongs to `holder_id`
## (melee batches are always resolved per fighting unit — empty bearer list).
static func _batch_is_holder(actor_id: String, holder_id: String, bearer_ids: Array) -> bool:
	if bearer_ids.is_empty():
		return actor_id == holder_id
	for b in bearer_ids:
		if _bearer_unit_id(actor_id, b) != holder_id:
			return false
	return true

# ===========================================================================
# PASSIVE COMBAT MODIFIERS
# ===========================================================================
# attack_mods(): every ATTACKER-side datasheet ability (and the debuffs the
# activated ones leave behind) for one attack batch (attacker, target, weapon).
# RulesEngine folds the result into each resolver path (interactive ranged
# hit / wound / save prep, auto-resolve ranged, overwatch, melee hit / wound /
# save prep). Hit / wound roll modifiers are capped at ±1 by the engine.
#
# Result keys:
#   hit_plus / hit_minus (bool), hit_reroll ("" | "ones" | "failed"),
#   ignore_hit_penalties (bool, Walking Bastion),
#   wound_plus (bool), wound_reroll ("" | "ones" | "failed"),
#   ap (int, improve by), damage (int, +D), strength (int, +S),
#   attacks (int, +A per attacking model), ws (int, improve WS by),
#   lethal (bool), sustained (int), ignores_cover (bool), target_cover (bool),
#   hazardous (bool), psychic (bool),
#   sources: [{name, kind ("hit"/"wound"/"other"), effect, note}]

static func _empty_mods() -> Dictionary:
	return {"hit_plus": false, "hit_minus": false, "hit_reroll": "", "ignore_hit_penalties": false,
		"wound_plus": false, "wound_reroll": "", "ap": 0, "damage": 0, "strength": 0, "attacks": 0,
		"ws": 0, "lethal": false, "sustained": 0, "ignores_cover": false, "target_cover": false,
		"hazardous": false, "psychic": false, "sources": []}

static func _src(m: Dictionary, name: String, kind: String, effect: String, note: String = "") -> void:
	(m["sources"] as Array).append({"name": name, "kind": kind, "effect": effect, "note": note})

static func _reroll_max(a: String, b: String) -> String:
	var rank := {"": 0, "ones": 1, "failed": 2}
	return a if int(rank.get(a, 0)) >= int(rank.get(b, 0)) else b

static func attack_mods(actor_unit: Dictionary, target_unit: Dictionary, weapon_profile: Dictionary, is_melee: bool, _board: Dictionary = {}, bearer_ids: Array = []) -> Dictionary:
	var m := _empty_mods()
	var actor_id := _uid(actor_unit)
	if actor_id == "" or actor_unit.is_empty():
		return m
	var target_id := _uid(target_unit)
	var phase := _phase()
	var owner := int(actor_unit.get("owner", 0))
	var own_turn := owner == Common.active_player()
	var flags: Dictionary = actor_unit.get("flags", {})
	var charged := bool(flags.get("charged_this_turn", false))
	var wname := _weapon_name(weapon_profile)
	var ranged := not is_melee
	var own_shooting := ranged and own_turn and phase == PH_SHOOTING

	# --- debuffs on the attacker (any faction) --------------------------------
	if _gf(actor_unit, F_SQUIG_COVERED) != null:
		m.hit_minus = true
		_src(m, "Squig Barrage", "hit", "minus_one", "attacker is covered in Squigs")
	var madcap = _gf(actor_unit, F_MADCAP)
	if ranged and typeof(madcap) == TYPE_DICTIONARY and str(madcap.get("effect", "")) == "wobbled":
		m.target_cover = true
		_src(m, "Madcap Artillery (wobbled)", "other", "target_cover", "a wobbled unit's targets have the benefit of cover")
	# --- target-side markers that help the attacker ------------------------------
	if target_id != "":
		var bb = _gf(target_unit, F_BURNA_BOMBED)
		if ranged and typeof(bb) == TYPE_DICTIONARY and int(bb.get("player", 0)) == owner:
			m.ignores_cover = true
			_src(m, "Burna Bomb", "other", "ignores_cover", "ranged attacks that target that unit have [IGNORES COVER]")
		var busted = _gf(target_unit, F_BUSTED)
		if typeof(busted) == TYPE_DICTIONARY and int(busted.get("player", 0)) == owner and group_has_keyword(actor_id, "SPEED FREEKS"):
			m.lethal = true
			_src(m, "Bust 'Em", "other", "lethal_hits", "target is busted")
		var pulsa = _gf(actor_unit, F_PULSA_TARGET)
		if pulsa != null and str(pulsa) != "" and head_id(str(pulsa)) == head_id(target_id):
			m.ap += 1
			m.lethal = true
			_src(m, "Pulsa Rokkit", "other", "ap_lethal", "+1 AP and [LETHAL HITS] against the selected unit")
	if not group_has_keyword(actor_id, "ORKS"):
		return m

	# --- flags left by activated abilities ---------------------------------------
	if ranged and _gf(actor_unit, F_AMMO_RUNTS) != null:
		m.hit_plus = true
		_src(m, "Ammo Runts", "hit", "plus_one", "used when selected to shoot")
	if ranged and _batch_is_holder(actor_id, _flag_holder(actor_id, F_BOSS_AMMO_RUNT), bearer_ids):
		m.hit_plus = true
		_src(m, "Boss' Ammo Runt", "hit", "plus_one", "this model's ranged attacks")
	if is_melee and flags.has(F_ROKKIT_CHARGE):
		m.attacks += 1
		m.strength += 1
		m.hazardous = true
		_src(m, "Rokkit Charge", "other", "a_s_hazardous", "+1 A, +1 S, [HAZARDOUS]")
	var warpath := str(flags.get(F_WARPATH, ""))
	if is_melee and warpath != "":
		m.psychic = true
		if warpath == "kill_rig":
			m.lethal = true
			_src(m, "Warpath", "other", "lethal_hits", "[LETHAL HITS] and [PSYCHIC]")
		else:
			m.wound_reroll = _reroll_max(m.wound_reroll, "ones")
			_src(m, "Warpath", "wound", "reroll_ones", "re-roll wound rolls of 1, [PSYCHIC]")
	if _gf(actor_unit, F_KNOW_WOTZ) != null:
		m.hit_plus = true
		_src(m, "Clever Know-wotz", "hit", "plus_one", "Mek-tuned vehicle")
	if target_id != "" and _gf(actor_unit, F_BEASTSCENT) != null and _is_monster_or_vehicle(target_id):
		m.wound_plus = true
		_src(m, "Beastscent", "wound", "plus_one", "target is a MONSTER or VEHICLE")

	# --- "this model" abilities ----------------------------------------------------
	if is_melee and charged and has(actor_unit, "might_is_right"):
		m.attacks += 3
		m.strength += 2
		_src(m, "Might Is Right", "other", "a_s", "+3 A, +2 S after a charge move")
	if has(actor_unit, "paired_krumpas") and wname.contains("kustom krumpa"):
		m.hit_reroll = "failed"
		m.wound_reroll = "failed"
		_src(m, "Paired Krumpas", "hit", "reroll_failed", "Kustom Krumpa")
		_src(m, "Paired Krumpas", "wound", "reroll_failed", "Kustom Krumpa")
	if is_melee and wname.contains("butcha boyz") and has(actor_unit, "fully_loaded_butchery"):
		var fl := mini(22, 2 * _embarked_model_count(actor_id))
		if fl > 0:
			m.attacks += fl
			_src(m, "Fully Loaded Butchery", "other", "attacks", "+%d A (%d embarked models)" % [fl, fl / 2])
	if own_shooting and wname.contains("blitzkannon") and target_id != "" and not _is_monster_or_vehicle(target_id) \
			and has(actor_unit, "blitz_dem_gitz"):
		m.attacks += 6
		_src(m, "Blitz Dem Gitz!", "other", "attacks", "+6 A against a non-MONSTER/VEHICLE unit")

	# --- "this unit" abilities (whole Attached unit) -----------------------------
	var riled := group_riled_up(actor_id)
	var cover_src := ""
	for slug in ["more_dakka", "kustom_dakka", "nazdregs_know_wotz"]:
		if cover_src == "" and group_has(actor_id, slug):
			cover_src = {"more_dakka": "More Dakka", "kustom_dakka": "Kustom Dakka", "nazdregs_know_wotz": "Nazdreg's Know-wotz"}[slug]
	if ranged and cover_src != "":
		m.ignores_cover = true
		_src(m, cover_src, "other", "ignores_cover", "ranged [IGNORES COVER]")
	if ranged and riled and (group_has(actor_id, "more_dakka") or group_has(actor_id, "even_more_dakka")):
		m.sustained = maxi(m.sustained, 1)
		_src(m, "More Dakka" if group_has(actor_id, "more_dakka") else "Even More Dakka", "other", "sustained_hits", "riled up: [SUSTAINED HITS 1]")
	if is_melee and phase == PH_FIGHT and charged and group_has(actor_id, "tide_of_muscle"):
		m.lethal = true
		_src(m, "Tide of Muscle", "other", "lethal_hits", "charged this turn")
	if phase == PH_FIGHT and riled and group_has(actor_id, "krumpin_time"):
		m.hit_plus = true
		_src(m, "Krumpin' Time", "hit", "plus_one", "riled up in the Fight phase")
	if target_id != "" and group_has(actor_id, "nowhere_to_hide") and unit_is_hidden(target_id):
		m.hit_plus = true
		_src(m, "Nowhere to Hide", "hit", "plus_one", "target is hidden")
	if own_shooting and group_has(actor_id, "deff_from_above") and _made_ingress_this_turn(actor_id):
		m.hit_plus = true
		_src(m, "Deff from Above", "hit", "plus_one", "made an ingress move this turn")
	if own_shooting and target_id != "" and group_has(actor_id, "strafing_run") and not group_has_keyword(target_id, "FLY"):
		m.hit_plus = true
		_src(m, "Strafing Run", "hit", "plus_one", "target has no FLY")
	if own_shooting and target_id != "" and group_has(actor_id, "go_fer_da_weak_spot") and _is_monster_or_vehicle(target_id):
		m.wound_plus = true
		_src(m, "Go fer da Weak Spot", "wound", "plus_one", "target is a MONSTER or VEHICLE")
	if is_melee and charged and group_has(actor_id, "high_speed_carnage"):
		m.strength += 1
		m.damage += 1
		_src(m, "High-speed Carnage", "other", "s_d", "+1 S and +1 D after a charge move")
	if target_id != "" and group_has(actor_id, "spiteful_power_trip") and _highest_toughness(target_id) < 7:
		m.hit_plus = true
		_src(m, "Spiteful Power Trip", "hit", "plus_one", "target has no T7+ model")
	if own_shooting and group_has(actor_id, "big_an_shooty"):
		m.hit_reroll = _reroll_max(m.hit_reroll, "ones")
		_src(m, "Big an' Shooty", "hit", "reroll_ones")
	if is_melee and group_has(actor_id, "big_an_stompy"):
		m.hit_reroll = _reroll_max(m.hit_reroll, "ones")
		_src(m, "Big an' Stompy", "hit", "reroll_ones")
	if own_shooting and group_has(actor_id, "mobile_arsenal"):
		m.hit_reroll = _reroll_max(m.hit_reroll, "ones")
		_src(m, "Mobile Arsenal", "hit", "reroll_ones")
	if own_shooting and group_has(actor_id, "finderz_keeperz") and target_id != "" \
			and (unit_in_objective_range(actor_id) or unit_in_objective_range(target_id)):
		m.ap += 1
		_src(m, "Finderz Keeperz", "other", "ap", "+1 AP (within range of an objective)")
	if group_has(actor_id, "walking_bastion"):
		m.ignore_hit_penalties = true
		_src(m, "Walking Bastion", "hit", "ignored", "ignores modifiers to BS/WS and hit rolls")
	if wname.contains("scavenged shivs") and group_has(actor_id, "super_runts"):
		m.attacks += 1
		m.ws += 1
		m.strength += 1
		_src(m, "Super Runts", "other", "a_ws_s", "Scavenged Shivs +1 A, WS and S")
	if group_has(actor_id, "dodge_dis"):
		m.hit_plus = true
		_src(m, "Dodge Dis!", "hit", "plus_one")
	if is_melee and target_id != "" and group_has(actor_id, "da_bigger_dey_iz") and _is_monster_or_vehicle(target_id):
		m.wound_reroll = "failed"
		_src(m, "Da Bigger Dey Iz…", "wound", "reroll_failed", "target is a MONSTER or VEHICLE")
	if charged and group_has(actor_id, "brutal_impact"):
		m.damage += 1
		_src(m, "Brutal Impact", "other", "damage", "+1 D after a charge move")
	if is_melee and group_has(actor_id, "sumfin_to_prove"):
		m.hit_plus = true
		_src(m, "Sumfin' to Prove", "hit", "plus_one")
	# --- auras -------------------------------------------------------------------
	if is_melee and _in_prophet_aura(actor_id, owner):
		m.hit_plus = true
		m.wound_plus = true
		_src(m, "Prophet of da Great Waaagh!", "hit", "plus_one", "within 6\" of Ghazghkull")
		_src(m, "Prophet of da Great Waaagh!", "wound", "plus_one", "within 6\" of Ghazghkull")
	# WP-O5: Codex: Orks (11e) enhancements of the attacker.
	return _enh().merge_attack_mods(m, actor_unit, target_unit, weapon_profile, is_melee, _board, bearer_ids)

static func _flag_holder(actor_id: String, flag: String) -> String:
	for gid in group(actor_id):
		if Common.unit(gid).get("flags", {}).get(flag, false):
			return gid
	return "__none__"

static func _made_ingress_this_turn(unit_id: String) -> bool:
	for gid in group(unit_id):
		var u := Common.unit(gid)
		if int(u.get("owner", 0)) != Common.active_player():
			continue
		if int(u.get("arrived_from_reserves_turn", -1)) == _round():
			return true
	return false

## Prophet of da Great Waaagh! (Aura): a friendly ORKS unit within 6" of
## Ghazghkull's unit (22.01: a model is always within range of its own aura).
static func _in_prophet_aura(actor_id: String, owner: int) -> bool:
	for uid in Common.state().get("units", {}):
		var u := Common.unit(str(uid))
		if int(u.get("owner", 0)) != owner or not has(u, "prophet") or not Common.is_on_battlefield(u):
			continue
		if head_id(str(uid)) == head_id(actor_id):
			return true
		if within(str(uid), actor_id, 6.0):
			return true
	return false

## TARGET-side modifiers (defender abilities). Also folded into the
## EffectPrimitives getters (target-only, phase as the ranged/melee proxy).
## Returns {ap_worsen, damage_minus, invuln, sources}.
static func defence_mods(target_unit: Dictionary, is_melee: bool) -> Dictionary:
	var d := {"ap_worsen": 0, "damage_minus": 0, "invuln": 0, "sources": []}
	var tid := _uid(target_unit)
	if tid == "" or target_unit.is_empty():
		return d
	if not group_has_keyword(tid, "ORKS"):
		return d
	if group_has(tid, "arrogant_invulnerability"):
		d.ap_worsen = 1
		d.sources.append("Arrogant Invulnerability")
	if not is_melee and group_has(tid, "kustom_force_field"):
		d.invuln = 4
		d.sources.append("Kustom Force Field")
	if group_has(tid, "blastajet_force_field"):
		d.invuln = 5 if d.invuln == 0 else mini(d.invuln, 5)
		d.sources.append("Blastajet Force Field")
	if group_has(tid, "dread_ard"):
		d.damage_minus = 1
		d.sources.append("Dread 'Ard")
	elif not is_melee and group_has(tid, "mobile_fortress"):
		d.damage_minus = 1
		d.sources.append("Mobile Fortress")
	return _enh().merge_defence_mods(d, target_unit, is_melee)  # WP-O5 Blitzboss (transport 5+ InSv)

## Phase-proxy variant for the EffectPrimitives getters (no attack context):
## the Fight phase resolves melee attacks, every other phase ranged ones.
static func defence_mods_now(target_unit: Dictionary) -> Dictionary:
	return defence_mods(target_unit, _phase() == PH_FIGHT)

## Hardy Bioniks: attacks that target this unit with S > its T have -1 to wound.
static func incoming_wound_penalty(target_unit: Dictionary, strength: int, toughness: int) -> bool:
	if strength <= toughness:
		return false
	var tid := _uid(target_unit)
	return tid != "" and group_has(tid, "hardy_bioniks")

## Enemy Attached-unit heads engaged with `unit_id`'s (Attached) unit.
static func _engaged_enemy_ids(unit_id: String) -> Array:
	var out: Array = []
	var me := head_id(unit_id)
	var owner := int(Common.unit(unit_id).get("owner", 0))
	for uid in Common.state().get("units", {}):
		var u := Common.unit(str(uid))
		if int(u.get("owner", 0)) == owner or not Common.is_on_battlefield(u) or head_id(str(uid)) != str(uid):
			continue
		if _units_engaged(me, str(uid)):
			out.append(str(uid))
	return out

## Any model of one Attached unit within engagement range of any model of the
## other (Measurement's shape-aware 11e predicate, as RulesEngine uses).
static func _units_engaged(a_id: String, b_id: String) -> bool:
	var meas = Common.autoload("Measurement")
	for ma in _models_of(a_id):
		for mb in _models_of(b_id):
			if meas and meas.has_method("is_in_engagement_range_shape_aware"):
				if meas.is_in_engagement_range_shape_aware(ma, mb):
					return true
			elif Common._pos(ma).distance_to(Common._pos(mb)) / PX_PER_INCH <= 2.0:
				return true
	return false

static func _model_engaged_with_unit(model: Dictionary, b_id: String) -> bool:
	var meas = Common.autoload("Measurement")
	for mb in _models_of(b_id):
		if meas and meas.has_method("is_in_engagement_range_shape_aware"):
			if meas.is_in_engagement_range_shape_aware(model, mb):
				return true
	return false

# ===========================================================================
# MOVEMENT / CHARGE / KEYWORD-STYLE PASSIVES
# ===========================================================================

## +N to charge rolls: Trophy Hunters, Waaagh! Banner ("this unit has +1 to
## charge rolls") and Thundering Stampede (Aura: friendly BEAST SNAGGA units
## within 6" of the Beastboss on Squigosaur). Different abilities stack.
static func charge_roll_bonus(unit_id: String) -> Dictionary:
	var out := {"bonus": 0, "sources": []}
	if unit_id == "" or not group_has_keyword(unit_id, "ORKS"):
		return out
	for slug in ["trophy_hunters", "waaagh_banner"]:
		if group_has(unit_id, slug):
			out.bonus += 1
			out.sources.append({"trophy_hunters": "Trophy Hunters", "waaagh_banner": "Waaagh! Banner"}[slug])
	if group_has_keyword(unit_id, "BEAST SNAGGA"):
		var owner := int(Common.unit(unit_id).get("owner", 0))
		for uid in Common.state().get("units", {}):
			var u := Common.unit(str(uid))
			if int(u.get("owner", 0)) != owner or not has(u, "thundering_stampede") or not Common.is_on_battlefield(u):
				continue
			if head_id(str(uid)) == head_id(unit_id) or within(str(uid), unit_id, 6.0):
				out.bonus += 1
				out.sources.append("Thundering Stampede")
				break
	return out

## +N to advance rolls (Fuel-mixa Grot: "This unit has +1 to advance rolls").
static func advance_roll_bonus(unit_id: String) -> int:
	return 1 if unit_id != "" and group_has(unit_id, "fuel_mixa_grot") else 0

## Move characteristic modifier for a unit: Runnin' wiv da Herd (+4" while the
## Painboss is attached to a MOUNTED unit) and Madcap Artillery "smashed" (-2").
static func move_modifier(unit: Dictionary) -> float:
	var uid := _uid(unit)
	if uid == "":
		return 0.0
	var mod := 0.0
	var madcap = group_flag(uid, F_MADCAP)
	if typeof(madcap) == TYPE_DICTIONARY and str(madcap.get("effect", "")) == "smashed":
		mod -= 2.0
	if has(unit, "runnin_wiv_da_herd"):
		var bg = unit.get("attached_to", null)
		if bg != null and str(bg) != "" and Common.has_keyword(Common.unit(str(bg)), "MOUNTED"):
			mod += 4.0
	mod += float(_enh().move_modifier(unit))  # WP-O5 Follow Me Ladz / Cybork Boosta / Blitzboss
	return mod

## Madcap Artillery "grounded": the unit cannot take to the skies.
static func cannot_take_to_skies(unit_id: String) -> bool:
	var madcap = group_flag(unit_id, F_MADCAP)
	return typeof(madcap) == TYPE_DICTIONARY and str(madcap.get("effect", "")) == "grounded"

## Madcap Artillery "zapped": -1 Ld (a worse Ld — the roll needs 1 more).
static func leadership_penalty(unit_id: String) -> int:
	var madcap = group_flag(unit_id, F_MADCAP)
	var zapped := 1 if typeof(madcap) == TYPE_DICTIONARY and str(madcap.get("effect", "")) == "zapped" else 0
	return zapped + int(_enh().leadership_penalty(unit_id))  # WP-O5 Enhanced Runt-maw (infested: -1 to leadership rolls)

## Conditional Lone Operative (24.24) of a standalone unit: Da Grand Warlord's
## Ladz, Support Shokka, Boss of da Hunt, Beast Snagga Following, Speednob
## Support.
static func conditional_lone_operative(unit: Dictionary) -> bool:
	var uid := _uid(unit)
	if uid == "" or not Common.is_on_battlefield(Common.unit(uid)):
		return false
	if _enh().conditional_lone_operative(unit):  # WP-O5 Dreadherder (within 3" of an ORKS WALKER)
		return true
	var owner := int(unit.get("owner", 0))
	if has(unit, "grand_warlords_ladz") or has(unit, "support_shokka"):
		var excl_bmsag := has(unit, "support_shokka")
		for fid in _friendly_heads(owner):
			if head_id(fid) == head_id(uid) or not group_has_keyword(fid, "ORKS") or not group_has_keyword(fid, "INFANTRY"):
				continue
			if excl_bmsag and group_has_keyword(fid, "BIG MEK WITH SHOKK ATTACK GUN"):
				continue
			if within(uid, fid, 3.0):
				return true
	if has(unit, "boss_of_da_hunt") or has(unit, "beast_snagga_following"):
		for fid in _friendly_heads(owner):
			if head_id(fid) == head_id(uid) or not group_has_keyword(fid, "BEAST SNAGGA"):
				continue
			if group_has_keyword(fid, "MONSTER") and group_has_keyword(fid, "CHARACTER"):
				continue
			if within(uid, fid, 3.0):
				return true
	if has(unit, "speednob_support"):
		for fid in _friendly_heads(owner):
			if head_id(fid) == head_id(uid) or not group_has_keyword(fid, "SPEED FREEKS") or group_has_keyword(fid, "WARTRAKKS"):
				continue
			if each_model_within(uid, fid, 3.0):
				return true
	return false

## "This unit has Deep Strike" from Da Jump (the Weirdboy in strategic reserves).
static func grants_deep_strike(unit: Dictionary) -> bool:
	return bool(unit.get("flags", {}).get(F_DA_JUMP_DS, false))

## Found 'Em!: +3" detection range until the end of the turn.
static func detection_range_bonus(unit: Dictionary) -> float:
	var uid := _uid(unit)
	if uid == "":
		return 0.0
	# WP-O5 Extra Sneaky (Gretchin): -3" detection range.
	return (3.0 if group_flag(uid, F_FOUND_EM) != null else 0.0) + float(_enh().detection_range_bonus(unit))

## Burna Bomb: "That enemy unit cannot be hidden until the end of your next turn."
static func cannot_be_hidden(unit: Dictionary) -> bool:
	var uid := _uid(unit)
	return uid != "" and group_flag(uid, F_BURNA_BOMBED) != null

## Drive-by Skorchin': "That enemy unit cannot be targeted with the Fire
## Overwatch stratagem until the end of the turn."
static func blocks_fire_overwatch(unit_id: String) -> bool:
	return unit_id != "" and group_flag(unit_id, F_NO_OVERWATCH) != null

## Downtrodden: for transport capacity each 2 Gretchin models (rounding up)
## take up the space of 1 model. Returns the capacity the unit's models use.
static func transport_space(unit_id: String, alive_models: int) -> int:
	if not has_id(unit_id, "downtrodden"):
		return alive_models
	var gretchin := 0
	var other := 0
	for m in Common.unit(unit_id).get("models", []):
		if not m.get("alive", true):
			continue
		var mt := str(m.get("model_type", m.get("name", ""))).to_lower()
		if mt.contains("runtherd"):
			other += 1
		else:
			gretchin += 1
	return int(ceil(float(gretchin) / 2.0)) + other

## Tramplasquig Charge (Hunta Rig): "When you target this unit with the
## Crushing Impact stratagem, that use is -1 CP." Returns the CP discount for
## `strat_name` used on `target_unit_id` (StratagemManager applies it).
static func stratagem_cp_discount(strat_name: String, target_unit_id: String) -> int:
	if not _edition_11() or target_unit_id == "":
		return 0
	if fold(strat_name) != "crushing impact":
		return 0
	return 1 if has_id(target_unit_id, "tramplasquig_charge") else 0

## Never Too Busy to Fight: being engaged does not prevent this unit from
## being eligible to start an action.
static func engaged_can_start_action(unit_id: String) -> bool:
	return unit_id != "" and group_has(unit_id, "never_too_busy")

## Get Out da Way!: while making a charge move, this unit can move through
## models (excluding MONSTER/VEHICLE models).
static func charge_moves_through_models(unit_id: String) -> bool:
	return unit_id != "" and group_has(unit_id, "get_out_da_way")

## Turbo Engine (Full Throttle): "When this unit is selected to make an
## advance/fall-back move, that move does not prevent this unit from being
## eligible to declare a charge."
static func engine_of(unit_id: String) -> String:
	var e = Common.unit(unit_id).get("flags", {}).get(F_ENGINE, null)
	return str(e.get("engine", "")) if typeof(e) == TYPE_DICTIONARY else ""

## Shokk-boosta: this advance roll is a 6 and the unit can move through all
## types of model while making the boosted advance move.
static func shokk_boosta_active(unit_id: String) -> bool:
	return unit_id != "" and group_flag(unit_id, F_SHOKK_BOOSTA) != null

# ===========================================================================
# BATTLE-SHOCK ROLLS (01.07: a leadership roll — 2D6 >= one of the unit's Ld)
# ===========================================================================

static func best_leadership(unit_id: String) -> int:
	var best := 99
	for gid in group(unit_id):
		var u := Common.unit(gid)
		var ld := int(u.get("meta", {}).get("stats", {}).get("leadership", 7))
		best = mini(best, ld)
	return (best if best < 99 else 7) + leadership_penalty(unit_id)

## Make a battle-shock roll for `unit_id` with `mod` added to the roll.
## Returns {diffs, roll: [d1, d2], total, ld, passed}.
static func battle_shock_roll(unit_id: String, mod: int, rng, source: String) -> Dictionary:
	var d1 := _d6(rng)
	var d2 := _d6(rng)
	var total := d1 + d2 + mod
	var ld := best_leadership(unit_id)
	var passed := total >= ld
	var diffs: Array = []
	if not passed:
		for gid in group(unit_id):
			diffs.append({"op": "set", "path": "units.%s.flags.battle_shocked" % gid, "value": true})
	Common.log_info("OrkAbilities11e: %s — %s battle-shock roll %d+%d%s = %d vs Ld %d+: %s" % [
		source, Common.unit_name(unit_id), d1, d2, (" %+d" % mod) if mod != 0 else "", total, ld,
		"passed" if passed else "FAILED (battle-shocked)"])
	return {"diffs": diffs, "roll": [d1, d2], "total": total, "ld": ld, "passed": passed}

# ===========================================================================
# RILED UP (the 11e Waaagh! state) granted by a datasheet ability
# ===========================================================================
# Mirrors DREAD POWER (OrkCodexMovement._dread_power_apply): waaagh_active +
# ork11e_riled_up feed every riled-up consumer; 5+ InSv, ranged [ASSAULT]
# (effect_advance_and_shoot) and advance-then-charge (effect_advance_and_charge)
# are the riled-up benefits. The marker records which flags this module set so
# the clear never strips another source's grant.

static func rile_up_diffs(unit_id: String, player: int, until: String, source: String) -> Array:
	var diffs: Array = []
	for gid in group(unit_id):
		var u := Common.unit(gid)
		var flags: Dictionary = u.get("flags", {})
		var set_list: Array = []
		var prev = flags.get(F_RILED, null)
		if typeof(prev) == TYPE_DICTIONARY:
			set_list = (prev.get("set", []) as Array).duplicate()
		for f in ["waaagh_active", "ork11e_riled_up", "effect_advance_and_charge", "effect_advance_and_shoot"]:
			if not bool(flags.get(f, false)):
				diffs.append({"op": "set", "path": "units.%s.flags.%s" % [gid, f], "value": true})
				if not f in set_list:
					set_list.append(f)
		var inv := int(flags.get("effect_invuln", 0))
		if inv == 0 or inv > 5:
			diffs.append({"op": "set", "path": "units.%s.flags.effect_invuln" % gid, "value": 5})
			diffs.append({"op": "set", "path": "units.%s.flags.effect_invuln_source" % gid, "value": "Riled up (%s)" % source})
			if not "effect_invuln" in set_list:
				set_list.append("effect_invuln")
		var marker := {"player": player, "until": until, "source": source, "set": set_list,
			"set_turn_key": _turn_key()}
		if typeof(prev) == TYPE_DICTIONARY and str(prev.get("until", "")) == "permanent":
			marker["until"] = "permanent"
		diffs.append({"op": "set", "path": "units.%s.flags.%s" % [gid, F_RILED], "value": marker})
	return diffs

## Clear a datasheet-ability riled-up marker in place (expiry runs on every
## peer at the same phase transition, like the stratagem expiry).
static func _clear_riled(gid: String) -> void:
	var u := Common.unit(gid)
	if u.is_empty():
		return
	var flags: Dictionary = u.get("flags", {})
	var marker = flags.get(F_RILED, null)
	if typeof(marker) != TYPE_DICTIONARY:
		return
	var fam = Common.autoload("FactionAbilityManager")
	var owner := int(u.get("owner", 0))
	var army_waaagh: bool = fam != null and fam.has_method("is_waaagh_active") and fam.is_waaagh_active(owner) \
			and fam.has_method("_unit_has_waaagh_ability") and fam._unit_has_waaagh_ability(u)
	for f in marker.get("set", []):
		var fs := str(f)
		if army_waaagh and fs in ["waaagh_active", "effect_advance_and_charge", "effect_invuln"]:
			continue
		if fs == "effect_invuln":
			if str(flags.get("effect_invuln_source", "")).begins_with("Riled up"):
				flags.erase("effect_invuln")
				flags.erase("effect_invuln_source")
			continue
		if fs == "ork11e_riled_up" and flags.get("ork11e_dread_power", false):
			continue
		flags.erase(fs)
	flags.erase(F_RILED)
	Common.log_info("OrkAbilities11e: riled up (%s) expired on %s" % [str(marker.get("source", "?")), gid])

static func clear_battle_shock_diffs(unit_id: String) -> Array:
	var diffs: Array = []
	for gid in group(unit_id):
		if Common.unit(gid).get("flags", {}).get("battle_shocked", false):
			diffs.append({"op": "set", "path": "units.%s.flags.battle_shocked" % gid, "value": false})
	return diffs

# ===========================================================================
# HEALING (02.02.04 as the engine implements it: each healed wound restores a
# lost wound on a wounded model; with none wounded, a destroyed model returns
# with 1 wound) — as diffs over every component of the (Attached) unit.
# ===========================================================================

static func heal_diffs(unit_id: String, amount: int) -> Dictionary:
	var diffs: Array = []
	var healed := 0
	var revived := 0
	var sim: Dictionary = {}  # "gid:idx" -> {alive, wounds}
	var comps := Common.attached_group_ids(unit_id)
	for _i in range(amount):
		var done := false
		for gid in comps:
			var models: Array = Common.unit(str(gid)).get("models", [])
			for idx in range(models.size()):
				var key := "%s:%d" % [gid, idx]
				var m: Dictionary = models[idx]
				var st: Dictionary = sim.get(key, {"alive": m.get("alive", true), "cw": int(m.get("current_wounds", m.get("wounds", 1)))})
				if st.alive and st.cw < int(m.get("wounds", 1)):
					st.cw += 1
					sim[key] = st
					healed += 1
					done = true
					break
			if done:
				break
		if done:
			continue
		for gid in comps:
			var models2: Array = Common.unit(str(gid)).get("models", [])
			for idx in range(models2.size()):
				var key2 := "%s:%d" % [gid, idx]
				var m2: Dictionary = models2[idx]
				var st2: Dictionary = sim.get(key2, {"alive": m2.get("alive", true), "cw": int(m2.get("current_wounds", m2.get("wounds", 1)))})
				if not st2.alive and not m2.get("ork11e_never_revive", false):
					st2.alive = true
					st2.cw = 1
					sim[key2] = st2
					revived += 1
					done = true
					break
			if done:
				break
		if not done:
			break
	for key in sim:
		var parts := str(key).rsplit(":", true, 1)
		var st3: Dictionary = sim[key]
		diffs.append({"op": "set", "path": "units.%s.models.%s.current_wounds" % [parts[0], parts[1]], "value": st3.cw})
		diffs.append({"op": "set", "path": "units.%s.models.%s.alive" % [parts[0], parts[1]], "value": st3.alive})
	return {"diffs": diffs, "healed": healed, "revived": revived}

static func unit_wounds_lost(unit_id: String) -> int:
	var lost := 0
	for gid in Common.attached_group_ids(unit_id):
		for m in Common.unit(str(gid)).get("models", []):
			if m.get("alive", true):
				lost += maxi(0, int(m.get("wounds", 1)) - int(m.get("current_wounds", m.get("wounds", 1))))
			else:
				lost += 1
	return lost

# ===========================================================================
# STRATEGIC RESERVES (Kunnin' Infiltrator, Aerial Manoover, Shokk Attack
# Engine, Da Jump) — the same diffs the FightPhase strategic_reserves
# follow-up builds (status, reserve_type, positions wiped).
# ===========================================================================

static func strategic_reserves_diffs(unit_id: String) -> Array:
	var diffs: Array = []
	for gid in Common.attached_group_ids(unit_id):
		var u := Common.unit(str(gid))
		if u.is_empty():
			continue
		diffs.append({"op": "set", "path": "units.%s.status" % gid, "value": 7})  # UnitStatus.IN_RESERVES
		diffs.append({"op": "set", "path": "units.%s.reserve_type" % gid, "value": "strategic_reserves"})
		diffs.append({"op": "set", "path": "units.%s.flags.repositioned_to_reserves" % gid, "value": true})
		var models: Array = u.get("models", [])
		for i in range(models.size()):
			diffs.append({"op": "set", "path": "units.%s.models.%d.position" % [gid, i], "value": null})
	return diffs

# ===========================================================================
# EXPIRY — called by PhaseManager.transition_to_phase (thin hook) after the
# outgoing phase has exited and before the new one is entered. Runs on every
# peer (transition_to_phase runs on host and client), mutating in place like
# the stratagem expiry (StratagemManager._clear_stratagem_flags).
# ===========================================================================

const PHASE_SCOPED := [F_AMMO_RUNTS, F_BOSS_AMMO_RUNT, F_PULSA_TARGET, F_ROKKIT_CHARGE, F_WARPATH, F_SHOKK_BOOSTA]
const END_OF_TURN := [F_FOUND_EM, F_NO_OVERWATCH, F_BUSTED, F_BEASTSCENT]

static func on_phase_transition(old_phase: int, new_phase: int) -> void:
	var units: Dictionary = Common.state().get("units", {})
	var active := Common.active_player()
	var cleared: Array = []
	if old_phase == PH_COMMAND and new_phase != PH_COMMAND:
		on_command_phase_exit(active)
	for uid in units:
		var u: Dictionary = units[uid]
		var flags: Dictionary = u.get("flags", {})
		if flags.is_empty():
			continue
		for f in PHASE_SCOPED:
			if flags.has(f):
				if f == F_ROKKIT_CHARGE and typeof(flags[f]) == TYPE_DICTIONARY and bool(flags[f].get("set_hazardous", false)):
					flags.erase("effect_grant_hazardous_melee")
				flags.erase(f)
				cleared.append("%s.%s" % [uid, f])
		# One Last Kill's Fight On Death marker lasts the Fight phase.
		if old_phase == PH_FIGHT and new_phase != PH_FIGHT and str(flags.get(F_FOD_SOURCE, "")) == "One Last Kill":
			flags.erase(F_FOD_MODE)
			flags.erase(F_FOD_SOURCE)
			cleared.append("%s.%s" % [uid, F_FOD_MODE])
		if new_phase == PH_COMMAND:
			for f in END_OF_TURN:
				if flags.has(f):
					flags.erase(f)
					cleared.append("%s.%s" % [uid, f])
			for f in [F_SQUIG_COVERED, F_MADCAP, F_ENGINE]:
				var v = flags.get(f, null)
				if typeof(v) == TYPE_DICTIONARY and int(v.get("player", 0)) == active:
					if f == F_ENGINE:
						_clear_engine_grants(flags)
					flags.erase(f)
					cleared.append("%s.%s" % [uid, f])
			var bb = flags.get(F_BURNA_BOMBED, null)
			if typeof(bb) == TYPE_DICTIONARY:
				if int(bb.get("player", 0)) == active:
					bb["armed"] = true   # the user's next turn has begun
				elif bool(bb.get("armed", false)):
					flags.erase(F_BURNA_BOMBED)  # that turn has ended
					cleared.append("%s.%s" % [uid, F_BURNA_BOMBED])
			var riled = flags.get(F_RILED, null)
			if typeof(riled) == TYPE_DICTIONARY and str(riled.get("until", "")) == "start_of_your_next_turn" \
					and int(riled.get("player", 0)) == active and str(riled.get("set_turn_key", "")) != _turn_key():
				_clear_riled(str(uid))
				cleared.append("%s.%s" % [uid, F_RILED])
		if new_phase == PH_MOVEMENT:
			var kw = flags.get(F_KNOW_WOTZ, null)
			if typeof(kw) == TYPE_DICTIONARY and int(kw.get("player", 0)) == active and str(kw.get("set_turn_key", "")) != _turn_key():
				flags.erase(F_KNOW_WOTZ)
				cleared.append("%s.%s" % [uid, F_KNOW_WOTZ])
		if flags.get(F_DA_JUMP_DS, false) and int(u.get("status", 0)) != 7:
			flags.erase(F_DA_JUMP_DS)
			cleared.append("%s.%s" % [uid, F_DA_JUMP_DS])
	if not cleared.is_empty():
		Common.log_info("OrkAbilities11e: phase %d -> %d expired %s" % [old_phase, new_phase, str(cleared)])
	_apply_permanent_states(new_phase)
	_enh().on_phase_transition(old_phase, new_phase)  # WP-O5 enhancement expiry / Mekwaaagh! / Surly as a Squiggoth

## Waaagh! Effigy / Super Runts ("This unit is riled up") and One Last Kill
## (Fight On Death for Mozrog) — re-asserted at every phase start.
static func _apply_permanent_states(new_phase: int) -> void:
	var units: Dictionary = Common.state().get("units", {})
	for uid in units:
		var u: Dictionary = units[uid]
		if not Common.is_on_battlefield(u) and not (u.get("embarked_in", null) != null and str(u.get("embarked_in", "")) != ""):
			continue
		if has(u, "waaagh_effigy") or has(u, "super_runts"):
			var src := "Waaagh! Effigy" if has(u, "waaagh_effigy") else "Super Runts"
			var need := false
			for gid in group(str(uid)):
				if not Common.is_riled_up(Common.unit(gid)) or typeof(Common.unit(gid).get("flags", {}).get(F_RILED, null)) != TYPE_DICTIONARY:
					need = true
			if need:
				var diffs := rile_up_diffs(str(uid), int(u.get("owner", 0)), "permanent", src)
				for d in diffs:
					var parts := str(d.path).split(".")
					var target: Dictionary = units.get(parts[1], {})
					if target.is_empty():
						continue
					if not target.has("flags"):
						target["flags"] = {}
					target["flags"][parts[3]] = d.value
		if new_phase == PH_FIGHT and has(u, "one_last_kill"):
			var flags: Dictionary = u.get("flags", {})
			if str(flags.get(F_FOD_MODE, "")) == "":
				flags[F_FOD_MODE] = "one_last_kill"
				flags[F_FOD_SOURCE] = "One Last Kill"

static func _clear_engine_grants(flags: Dictionary) -> void:
	var e = flags.get(F_ENGINE, null)
	if typeof(e) != TYPE_DICTIONARY:
		return
	for f in e.get("set", []):
		flags.erase(str(f))

# ===========================================================================
# ACTIVATED ABILITIES — offered through the stratagem-window framework
# ===========================================================================
# An activated ability is an offer in the same window dialog the codex
# stratagems use (StratagemDialog Card_<sid>/Buttons/Use_<sid>_<uid>), with
# stratagem_id "ork11e_ab_<slug>", cp_cost 0 and is_ability: true. Picking it
# sends the ordinary USE_WINDOW_STRATAGEM; StratagemManager.use_stratagem
# routes the id here (use()). The AI answers synchronously (ai_score), so a
# window can never stall on an ability.

## window id -> slugs offered there.
const WINDOW_ABILITIES := {
	"unit_selected_to_shoot": ["boss_ammo_runt", "ammo_runts", "pulsa_rokkit"],
	"unit_has_shot": ["rokkit_barrage", "squig_barrage", "bust_em", "madcap_artillery"],
	"unit_selected_to_move": ["intimidating_motivation", "get_back_in_da_race", "keep_huntin",
		"clever_know_wotz", "shokk_boosta", "found_em", "drive_by_skorchin"],
	"unit_ended_normal_move": ["bomb_squigs", "bomb_squig", "gut_hatch", "intimidating_motivation",
		"get_back_in_da_race", "keep_huntin", "clever_know_wotz", "found_em", "drive_by_skorchin"],
	"movement_phase_start": ["makari", "da_jump"],
	"movement_phase_end": ["da_jump"],
	"enemy_ended_move": ["supreme_kunnin"],
	"unit_selected_to_fight": ["rokkit_charge", "warpath"],
	"unit_ended_charge_move": ["krushin_impetus"],
	"fight_phase_end": ["kunnin_infiltrator", "aerial_manoover", "burna_bomb", "boom_bomb"],
	"battle_shock_step_start": ["crude_surgery", "fix_dat_armour_up", "push_dat_bit_back_in",
		"full_throttle", "shokk_attack_engine"],
	"unit_battle_shocked": ["thatll_learn_ya"],
}

## Short effect text shown on the window card (the printed rule, condensed).
const EFFECT_TEXT := {
	"boss_ammo_runt": "Once per battle: this model's ranged attacks have +1 to hit rolls.",
	"ammo_runts": "Once per battle: this unit's ranged attacks have +1 to hit rolls.",
	"pulsa_rokkit": "Once per battle: select one enemy MONSTER/VEHICLE unit within 24\". This unit's attacks that target that unit have +1 AP and [LETHAL HITS].",
	"bomb_squigs": "Once per turn, twice per battle: select one visible enemy unit within 12\" and roll one D6 — on a 3+ it suffers D3 mortal wounds.",
	"bomb_squig": "Once per battle: select one visible enemy unit within 12\" and roll one D6 — on a 3+ it suffers D3 mortal wounds.",
	"rokkit_charge": "This unit made a charge move: its melee attacks have +1 A and S and [HAZARDOUS].",
	"krushin_impetus": "Select one enemy unit engaged with this unit: roll one D6 per model in this unit engaged with it — each 3+ inflicts 1 mortal wound.",
	"intimidating_motivation": "Once per battle round, per army: one friendly ORKS unit within 6\" is no longer battle-shocked and is riled up until the start of your next turn.",
	"get_back_in_da_race": "Once per battle round, per army: one friendly SPEED FREEKS unit within 6\" (and units embarked in it) is no longer battle-shocked and is riled up until the start of your next turn.",
	"keep_huntin": "Once per battle round, per army: one friendly BEAST SNAGGA unit within 6\" is no longer battle-shocked and is riled up until the start of your next turn.",
	"clever_know_wotz": "One friendly ORKS VEHICLE model (excluding AIRCRAFT/TITANIC) within 3\" heals D3 wounds; its attacks have +1 to hit rolls until the start of your next Movement phase.",
	"makari": "Once per battle, per army: select up to as many friendly ORKS units as the battle round number — they are riled up until the start of your next turn.",
	"found_em": "Select one enemy unit within 12\": it has +3\" detection range until the end of the turn.",
	"drive_by_skorchin": "Select one visible enemy unit (excluding MONSTER/VEHICLE) within 6\": it cannot be targeted with the Fire Overwatch stratagem until the end of the turn.",
	"gut_hatch": "Units embarked within this unit can make an assault disembark move.",
	"shokk_boosta": "This advance roll is a 6 and this unit can move through all types of model; when it ends that advance move, make a hazard roll for each of its models.",
	"supreme_kunnin": "Once per phase, per army: this unit makes a normal move of up to D6\" (or up to 5\" if it is riled up).",
	"warpath": "Psychic roll (D6, on a 1 this unit is battle-shocked). Melee attacks gain the Warpath effect and [PSYCHIC].",
	"da_jump": "Psychic roll (D6, on a 1 this unit is battle-shocked). Place this unit in strategic reserves; it has Deep Strike.",
	"kunnin_infiltrator": "Every model in this unit is hidden and unengaged: place this unit in strategic reserves.",
	"aerial_manoover": "This unit is unengaged: place this unit in strategic reserves.",
	"burna_bomb": "Select one visible enemy unit (excluding Lone Operative and MONSTER/VEHICLE) within 36\" and roll one D6 — on a 2+: D3 mortal wounds, it cannot be hidden and ranged attacks that target it have [IGNORES COVER] until the end of your next turn.",
	"boom_bomb": "Select one visible enemy unit (excluding Lone Operative) within 24\" and roll one D6 — 1-3: D3 mortal wounds; 4-5: 3 mortal wounds; 6: D3+3 mortal wounds.",
	"rokkit_barrage": "Select one enemy unit hit by this unit's attacks: it makes a battle-shock roll with -1.",
	"squig_barrage": "Select one enemy unit (excluding MONSTER/VEHICLE) hit by this unit's Squig Launchas: until the start of your next turn its attacks have -1 to hit rolls.",
	"bust_em": "Select one enemy unit hit by this unit's attacks: until the end of the turn, friendly SPEED FREEKS units' attacks that target it have [LETHAL HITS].",
	"madcap_artillery": "Select one enemy unit hit by this unit's attacks: until the start of your next turn it is wobbled / zapped / smashed / grounded (by the Mek Gunz' weapon).",
	"crude_surgery": "This unit heals 3 wounds (Catch Dat Red Bit, once per battle: +D3).",
	"fix_dat_armour_up": "Once per battle: this unit heals 3 wounds.",
	"push_dat_bit_back_in": "Once per battle: one friendly BEAST SNAGGA unit within 6\" heals 3 wounds.",
	"full_throttle": "Select one Throttlerokkit Shokka Engine ability; this unit has it until the start of your next Command phase.",
	"shokk_attack_engine": "This unit is unengaged: place it in strategic reserves.",
	"thatll_learn_ya": "Once per battle round: roll one D3 — that many Gretchin models in this unit are destroyed and this unit is no longer battle-shocked.",
}

static func handles_id(sid: String) -> bool:
	return str(sid).begins_with(SID_PREFIX)

static func slug_of(sid: String) -> String:
	return str(sid).substr(SID_PREFIX.length())

static func sid_of(slug: String) -> String:
	return SID_PREFIX + slug

static func _edition_11() -> bool:
	return int(GameConstants.edition) >= 11

## Offers for `player` in `window_id` (StratagemManager.get_all_window_offers
## appends these after the stratagem offers).
static func window_offers(player: int, window_id: String, ctx: Dictionary) -> Array:
	var offers: Array = []
	if not _edition_11():
		return offers
	for slug in WINDOW_ABILITIES.get(window_id, []):
		var targets: Array = _targets(str(slug), player, window_id, ctx)
		if targets.is_empty():
			continue
		offers.append({
			"stratagem_id": sid_of(str(slug)),
			"name": display(str(slug)),
			"cp_cost": 0,
			"cost_text": "Ability",
			"effect_text": str(EFFECT_TEXT.get(str(slug), "")),
			"type": "Datasheet ability",
			"is_ability": true,
			"targets": targets,
		})
	if not offers.is_empty():
		Common.log_info("OrkAbilities11e: window %s P%d — ability offers %s" % [window_id, player, str(offers.map(func(o): return o.name))])
	offers.append_array(_enh().window_offers(player, window_id, ctx))  # WP-O5 activated enhancements
	return offers

static func _entry(unit_id: String, extra: Dictionary = {}) -> Dictionary:
	return Common.target_entry(unit_id, extra)

static func _unit_options(ids: Array, prompt: String) -> Dictionary:
	var opts: Array = []
	for uid in ids:
		opts.append({"id": str(uid), "label": Common.unit_name(str(uid))})
	return {"kind": "unit", "prompt": prompt, "options": opts}

## The alive holder of `slug` in the unit named by ctx.unit_id, owned by `player`.
static func _ctx_holder(slug: String, player: int, ctx: Dictionary) -> String:
	var uid := str(ctx.get("unit_id", ""))
	if uid == "":
		return ""
	var u := Common.unit(uid)
	if u.is_empty() or int(u.get("owner", 0)) != player:
		return ""
	return group_holder(uid, slug)

## Eligible target entries for one ability in one window.
static func _targets(slug: String, player: int, window_id: String, ctx: Dictionary) -> Array:
	var active := Common.active_player()
	var own_turn := player == active
	match slug:
		"boss_ammo_runt", "ammo_runts":
			var h := _ctx_holder(slug, player, ctx)
			if h == "" or used_in_battle(h, slug) >= 1:
				return []
			return [_entry(h)]
		"pulsa_rokkit":
			var h := _ctx_holder(slug, player, ctx)
			if h == "" or used_in_battle(h, slug) >= 1:
				return []
			var cands := _enemy_heads(player, func(eid): return _is_monster_or_vehicle(eid) and within(h, eid, 24.0))
			if cands.is_empty():
				return []
			cands.sort_custom(func(a, b): return Common.points(Common.unit(a)) > Common.points(Common.unit(b)))
			return [_entry(h, {"secondary": _unit_options(cands, "PULSA ROKKIT: select one enemy MONSTER/VEHICLE unit within 24\"")})]
		"bomb_squigs", "bomb_squig":
			var h := _ctx_holder(slug, player, ctx)
			if h == "" or not own_turn:
				return []
			var cap := 2 if slug == "bomb_squigs" else 1
			if used_in_battle(h, slug) >= cap or used_this_turn(h, slug):
				return []
			var cands := _enemy_heads(player, func(eid): return within(h, eid, 12.0) and _visible(h, eid))
			if cands.is_empty():
				return []
			cands.sort_custom(func(a, b): return Common.points(Common.unit(a)) > Common.points(Common.unit(b)))
			return [_entry(h, {"secondary": _unit_options(cands, "%s: select one visible enemy unit within 12\"" % display(slug).to_upper())})]
		"rokkit_charge":
			var h := _ctx_holder(slug, player, ctx)
			if h == "" or not Common.unit(h).get("flags", {}).get("charged_this_turn", false):
				return []
			if group_flag(h, F_ROKKIT_CHARGE) != null:
				return []
			return [_entry(h)]
		"warpath":
			var h := _ctx_holder(slug, player, ctx)
			if h == "" or Common.is_battle_shocked(Common.unit(h)) or group_flag(h, F_WARPATH) != null:
				return []
			if not _psychic_budget_ok(h, PSY_WARPATH):
				return []
			return [_entry(h)]
		"krushin_impetus":
			var h := _ctx_holder(slug, player, ctx)
			if h == "" or not own_turn or used_this_phase(h, slug):
				return []
			var cands := _engaged_enemy_ids(h)
			if cands.is_empty():
				return []
			return [_entry(h, {"secondary": _unit_options(cands, "KRUSHIN' IMPETUS: select one enemy unit engaged with this unit")})]
		"intimidating_motivation", "get_back_in_da_race", "keep_huntin":
			var h := _ctx_holder(slug, player, ctx)
			if h == "" or not own_turn or army_used_this_round(player, slug):
				return []
			var kw: String = {"intimidating_motivation": "ORKS", "get_back_in_da_race": "SPEED FREEKS", "keep_huntin": "BEAST SNAGGA"}[slug]
			var cands := _friendly_heads(player, func(fid): return group_has_keyword(fid, kw) and (head_id(fid) == head_id(h) or within(h, fid, 6.0)))
			if cands.is_empty():
				return []
			cands.sort_custom(func(a, b): return _rile_value(a) > _rile_value(b))
			return [_entry(h, {"secondary": _unit_options(cands, "%s: select one friendly %s unit within 6\"" % [display(slug).to_upper(), kw])})]
		"clever_know_wotz":
			var h := _ctx_holder(slug, player, ctx)
			if h == "" or not own_turn or used_this_phase(h, slug):
				return []
			var cands := _friendly_heads(player, func(fid): return group_has_keyword(fid, "ORKS") and group_has_keyword(fid, "VEHICLE") \
				and not group_has_keyword(fid, "AIRCRAFT") and not group_has_keyword(fid, "TITANIC") and _own_models_within(h, fid, 3.0))
			if cands.is_empty():
				return []
			cands.sort_custom(func(a, b): return unit_wounds_lost(a) > unit_wounds_lost(b))
			return [_entry(h, {"secondary": _unit_options(cands, "CLEVER KNOW-WOTZ: select one friendly ORKS VEHICLE model within 3\"")})]
		"shokk_boosta":
			var h := _ctx_holder(slug, player, ctx)
			if h == "" or not own_turn or str(ctx.get("move_type", "")) != "advance" or shokk_boosta_active(h):
				return []
			return [_entry(h)]
		"found_em":
			var h := _ctx_holder(slug, player, ctx)
			if h == "" or not own_turn or used_this_phase(h, slug):
				return []
			var cands := _enemy_heads(player, func(eid): return within(h, eid, 12.0) and group_flag(eid, F_FOUND_EM) == null)
			if cands.is_empty():
				return []
			cands.sort_custom(func(a, b): return (1 if unit_is_hidden(a) else 0) > (1 if unit_is_hidden(b) else 0))
			return [_entry(h, {"secondary": _unit_options(cands, "FOUND 'EM!: select one enemy unit within 12\"")})]
		"drive_by_skorchin":
			var h := _ctx_holder(slug, player, ctx)
			if h == "" or not own_turn or used_this_phase(h, slug):
				return []
			var cands := _enemy_heads(player, func(eid): return not _is_monster_or_vehicle(eid) and within(h, eid, 6.0) and _visible(h, eid))
			if cands.is_empty():
				return []
			cands.sort_custom(func(a, b): return Common.points(Common.unit(a)) > Common.points(Common.unit(b)))
			return [_entry(h, {"secondary": _unit_options(cands, "DRIVE-BY SKORCHIN': select one visible enemy unit within 6\"")})]
		"gut_hatch":
			var uid := str(ctx.get("unit_id", ""))
			if uid == "" or not own_turn or not has_id(uid, "gut_hatch") or int(Common.unit(uid).get("owner", 0)) != player:
				return []
			if _embarked_units(uid).is_empty():
				return []
			return [_entry(uid)]
		"makari":
			if not own_turn:
				return []
			var used := army_uses(player, "makari")
			var picks := int(used.get("picks", 0))
			var continuing := int(used.get("battle", 0)) >= 1 and str(used.get("phase_key", "")) == _phase_key() and picks < _round()
			if int(used.get("battle", 0)) >= 1 and not continuing:
				return []
			var ghaz := ""
			for uid in Common.state().get("units", {}):
				var u := Common.unit(str(uid))
				if int(u.get("owner", 0)) == player and has(u, "makari") and Common.is_on_battlefield(u):
					ghaz = str(uid)
					break
			if ghaz == "":
				return []
			var already: Array = used.get("picked", []) if continuing else []
			var cands := _friendly_heads(player, func(fid): return group_has_keyword(fid, "ORKS") and not fid in already)
			if cands.is_empty():
				return []
			cands.sort_custom(func(a, b): return _rile_value(a) > _rile_value(b))
			var left := _round() - picks if continuing else _round()
			return [_entry(ghaz, {"label": "Ghazghkull Thraka (%d unit%s left)" % [left, "" if left == 1 else "s"],
				"secondary": _unit_options(cands, "MAKARI, HOIST DAT BANNER!: select a friendly ORKS unit to rile up (%d left)" % left)})]
		"da_jump":
			if not own_turn or army_used_this_round(player, "da_jump"):
				return []
			var out: Array = []
			for uid in Common.state().get("units", {}):
				var u := Common.unit(str(uid))
				if int(u.get("owner", 0)) != player or not has(u, "da_jump") or not Common.is_on_battlefield(u):
					continue
				if Common.is_battle_shocked(u) or _engaged(str(uid)) or not _psychic_budget_ok(str(uid), PSY_DA_JUMP):
					continue
				out.append(_entry(str(uid)))
			return out
		"supreme_kunnin":
			if own_turn or army_used_this_phase(player, slug):
				return []
			var enemy := str(ctx.get("enemy_unit_id", ""))
			if enemy == "":
				return []
			var out: Array = []
			for uid in Common.state().get("units", {}):
				var u := Common.unit(str(uid))
				if int(u.get("owner", 0)) != player or not has(u, "supreme_kunnin") or not Common.is_on_battlefield(u):
					continue
				var hid := head_id(str(uid))
				if _engaged(hid) or not within(hid, enemy, 8.0):
					continue
				var vs: Array = [{"id": "d6", "label": "Normal move up to D6\"", "cp_cost": 0}]
				if group_riled_up(hid):
					vs.append({"id": "riled5", "label": "Riled up: normal move up to 5\"", "cp_cost": 0})
				out.append(_entry(hid, {"variants": vs, "require_variant": true, "ai_variant": "riled5" if group_riled_up(hid) else "d6"}))
			return out
		"kunnin_infiltrator", "aerial_manoover":
			if own_turn:
				return []
			var out: Array = []
			for uid in Common.state().get("units", {}):
				var u := Common.unit(str(uid))
				if int(u.get("owner", 0)) != player or not has(u, slug) or not Common.is_on_battlefield(u):
					continue
				var hid := head_id(str(uid))
				if _engaged(hid):
					continue
				if slug == "kunnin_infiltrator" and not unit_is_hidden(hid):
					continue
				out.append(_entry(hid))
			return out
		"burna_bomb", "boom_bomb":
			if own_turn:
				return []
			var out: Array = []
			var rng_in := 36.0 if slug == "burna_bomb" else 24.0
			for uid in Common.state().get("units", {}):
				var u := Common.unit(str(uid))
				if int(u.get("owner", 0)) != player or not has(u, slug) or not Common.is_on_battlefield(u):
					continue
				# One drop per bommer: the trigger ("at the end of your opponent's
				# Fight phase") happens once per phase.
				if used_this_phase(str(uid), slug):
					continue
				var bid := str(uid)
				var cands := _enemy_heads(player, func(eid): return within(bid, eid, rng_in) and _visible(bid, eid) \
					and not _target_lone_operative(eid) and (slug == "boom_bomb" or not _is_monster_or_vehicle(eid)))
				if cands.is_empty():
					continue
				cands.sort_custom(func(a, b): return Common.points(Common.unit(a)) > Common.points(Common.unit(b)))
				out.append(_entry(bid, {"secondary": _unit_options(cands, "%s: select one visible enemy unit within %d\"" % [display(slug).to_upper(), int(rng_in)])}))
			return out
		"rokkit_barrage", "squig_barrage", "bust_em", "madcap_artillery":
			var h := _ctx_holder(slug, player, ctx)
			if h == "" or not own_turn or used_this_phase(h, slug):
				return []
			var cands := _post_shot_candidates(slug, h, ctx)
			if cands.size() < 2:
				return []  # 0 = nothing hit; 1 = resolved automatically (after_unit_shot)
			if slug == "madcap_artillery" and _madcap_effect(h) == "":
				return []
			return [_entry(h, {"secondary": _unit_options(cands, "%s: select one enemy unit hit by those attacks" % display(slug).to_upper())})]
		"crude_surgery":
			if not own_turn:
				return []
			var out: Array = []
			for uid in Common.state().get("units", {}):
				var u := Common.unit(str(uid))
				if int(u.get("owner", 0)) != player or not has(u, "crude_surgery") or not Common.is_on_battlefield(u):
					continue
				if used_this_phase(str(uid), "crude_surgery") or unit_wounds_lost(str(uid)) <= 0:
					continue
				var vs: Array = [{"id": "heal3", "label": "Heal 3 wounds", "cp_cost": 0}]
				if has(u, "catch_dat_red_bit") and used_in_battle(str(uid), "catch_dat_red_bit") == 0:
					vs.append({"id": "heal3_d3", "label": "Heal 3 + D3 wounds (Catch Dat Red Bit, once per battle)", "cp_cost": 0})
				out.append(_entry(str(uid), {"variants": vs, "require_variant": true,
					"ai_variant": "heal3_d3" if unit_wounds_lost(str(uid)) >= 4 and vs.size() > 1 else "heal3"}))
			return out
		"fix_dat_armour_up":
			if not own_turn:
				return []
			var out: Array = []
			for uid in Common.state().get("units", {}):
				var u := Common.unit(str(uid))
				if int(u.get("owner", 0)) != player or not has(u, slug) or not Common.is_on_battlefield(u):
					continue
				if used_in_battle(str(uid), slug) >= 1 or unit_wounds_lost(str(uid)) <= 0:
					continue
				out.append(_entry(str(uid)))
			return out
		"push_dat_bit_back_in":
			if not own_turn:
				return []
			var out: Array = []
			for uid in Common.state().get("units", {}):
				var u := Common.unit(str(uid))
				if int(u.get("owner", 0)) != player or not has(u, slug) or not Common.is_on_battlefield(u):
					continue
				if used_in_battle(str(uid), slug) >= 1:
					continue
				var pid := str(uid)
				var cands := _friendly_heads(player, func(fid): return group_has_keyword(fid, "BEAST SNAGGA") and unit_wounds_lost(fid) > 0 \
					and (head_id(fid) == head_id(pid) or within(pid, fid, 6.0)))
				if cands.is_empty():
					continue
				cands.sort_custom(func(a, b): return unit_wounds_lost(a) > unit_wounds_lost(b))
				out.append(_entry(pid, {"secondary": _unit_options(cands, "PUSH DAT BIT BACK IN: select one friendly BEAST SNAGGA unit within 6\"")}))
			return out
		"full_throttle":
			if not own_turn:
				return []
			var out: Array = []
			for uid in Common.state().get("units", {}):
				var u := Common.unit(str(uid))
				if int(u.get("owner", 0)) != player or not has(u, slug) or not Common.is_on_battlefield(u):
					continue
				if used_this_phase(str(uid), slug):
					continue
				var vs: Array = []
				for e in [["turbo", "Turbo Engine"], ["shokk", "Shokk Attack Engine"], ["pulse", "Pulse Jet"]]:
					if has(u, {"turbo": "turbo_engine", "shokk": "shokk_attack_engine", "pulse": "pulse_jet"}[e[0]]):
						vs.append({"id": e[0], "label": e[1], "cp_cost": 0})
				if vs.is_empty():
					continue
				out.append(_entry(str(uid), {"variants": vs, "require_variant": true, "ai_variant": "turbo"}))
			return out
		"shokk_attack_engine":
			if not own_turn:
				return []
			var out: Array = []
			for uid in Common.state().get("units", {}):
				var u := Common.unit(str(uid))
				if int(u.get("owner", 0)) != player or not Common.is_on_battlefield(u) or engine_of(str(uid)) != "shokk":
					continue
				if used_this_phase(str(uid), slug) or _engaged(str(uid)):
					continue
				out.append(_entry(str(uid)))
			return out
		"thatll_learn_ya":
			var uid := str(ctx.get("unit_id", ""))
			var h := group_holder(uid, slug) if uid != "" else ""
			if h == "" or int(Common.unit(h).get("owner", 0)) != player or used_this_round(h, slug):
				return []
			if _gretchin_alive(uid).size() < 4:
				return []
			return [_entry(head_id(uid))]
	return []

static func _target_lone_operative(unit_id: String) -> bool:
	var re = Common.rules()
	var u := Common.unit(unit_id)
	if u.get("attached_to", null) != null and str(u.get("attached_to", "")) != "":
		return false
	if not u.get("attachment_data", {}).get("attached_characters", []).is_empty():
		return false
	return re != null and re.has_method("has_lone_operative") and re.has_lone_operative(u)

static func _own_models_within(holder_id: String, other_id: String, inches: float) -> bool:
	var meas = Common.autoload("Measurement")
	for ma in Common.unit(holder_id).get("models", []):
		if not ma.get("alive", true) or ma.get("position", null) == null:
			continue
		for mb in _models_of(other_id):
			var d := INF
			if meas and meas.has_method("model_to_model_distance_inches"):
				d = float(meas.model_to_model_distance_inches(ma, mb))
			else:
				d = Common._pos(ma).distance_to(Common._pos(mb)) / PX_PER_INCH
			if d <= inches + 0.001:
				return true
	return false

## How much a friendly unit gains from being riled up (AI ordering): a
## battle-shocked unit first, then units close to the enemy.
static func _rile_value(unit_id: String) -> float:
	var v := 0.0
	var u := Common.unit(unit_id)
	if Common.is_battle_shocked(u):
		v += 10.0
	if group_riled_up(unit_id):
		v -= 5.0
	var best := INF
	for eid in _enemy_heads(int(u.get("owner", 0))):
		best = minf(best, dist_in(unit_id, eid))
	if best < INF:
		v += maxf(0.0, 12.0 - best) / 2.0
	# ADV-CHG-1: a unit that riling up lets Advance-and-charge an enemy this
	# turn is the best pick (+1 per 5% of charge odds gained).
	v += 20.0 * _rile_charge_gain(unit_id)
	return v

## MAKARI-R1: min charge-odds gain that justifies spending Makari in round 1.
const MAKARI_R1_MIN_CHARGE_GAIN := 0.25
const MAKARI_R1_MIN_ADVANCE_CHANCE := 0.35

static var _aidm_script = null
static func _aidm():
	if _aidm_script == null:
		_aidm_script = load("res://scripts/AIDecisionMaker.gd")
	return _aidm_script

## ADV-CHG-1: how much riling `unit_id` up raises its best charge odds THIS
## turn — max over enemies of (Advance-then-charge odds - Move-then-charge
## odds), counted only when the Advance odds reach MAKARI_R1_MIN_ADVANCE_CHANCE.
## 0 when it is already riled up / may already charge after Advancing, or has
## no melee weapons.
static func _rile_charge_gain(unit_id: String) -> float:
	var u := Common.unit(unit_id)
	if u.is_empty() or group_riled_up(unit_id):
		return 0.0
	var ai = _aidm()
	if ai == null or not bool(ai._unit_has_melee_weapons(u)) or bool(ai._can_advance_and_charge(u)):
		return 0.0
	var gain := 0.0
	for eid in _enemy_heads(int(u.get("owner", 0))):
		var odds: Dictionary = ai.charge_odds_this_turn(u, Common.unit(eid))
		if odds.is_empty() or float(odds.get("p_advance", 0.0)) < MAKARI_R1_MIN_ADVANCE_CHANCE:
			continue
		gain = maxf(gain, float(odds.p_advance) - float(odds.p_move))
	return gain

## MAKARI-R1: best _rile_charge_gain over the ORKS units Makari could pick.
static func _makari_best_charge_gain(player: int) -> float:
	var best := 0.0
	for fid in _friendly_heads(player, func(f): return group_has_keyword(f, "ORKS")):
		best = maxf(best, _rile_charge_gain(str(fid)))
	return best

static func _gretchin_alive(unit_id: String) -> Array:
	var out: Array = []
	for gid in group(unit_id):
		var u := Common.unit(gid)
		if not Common.has_keyword(u, "GRETCHIN") and not Common.has_keyword(u, "GROTS"):
			continue
		var models: Array = u.get("models", [])
		for i in range(models.size()):
			var m: Dictionary = models[i]
			if not m.get("alive", true):
				continue
			var mt := str(m.get("model_type", m.get("name", ""))).to_lower()
			if mt.contains("runtherd"):
				continue
			out.append([gid, i])
	return out

## Psychic level budget: Unstable Energies is WP-O34's army rule
## (OrkArmyRules11e.can_use_psychic / record_psychic_use — psyker level per
## battle round + 22.03.01 once per phase); this module only asks it. Units
## outside that budget (no Unstable Energies / not a PSYKER) are not limited.
const PSY_DA_JUMP := "Da Jump (psychic level 1)"
const PSY_WARPATH := "Warpath (psychic level 1)"
const PSY_BEASTSCENT := "Beastscent (psychic level 1)"

static func _army_rules():
	return load("res://scripts/codex/orks/OrkArmyRules11e.gd")

static func _psychic_budget_ok(unit_id: String, ability_name: String) -> bool:
	var ar = _army_rules()
	if ar == null:
		return true
	return bool(ar.can_use_psychic(unit_id, ability_name).get("ok", true))

static func _psychic_spend_diffs(unit_id: String, ability_name: String) -> Array:
	var ar = _army_rules()
	if ar == null:
		return []
	return ar.record_psychic_use(unit_id, ability_name)

## Enemy units hit by the shooter this activation (ShootingPhase post-shot
## ctx.hit_unit_ids), filtered per ability.
static func _post_shot_candidates(slug: String, holder_id: String, ctx: Dictionary) -> Array:
	var owner := int(Common.unit(holder_id).get("owner", 0))
	var out: Array = []
	for tid in ctx.get("hit_unit_ids", []):
		var t := str(tid)
		var tu := Common.unit(t)
		if tu.is_empty() or int(tu.get("owner", 0)) == owner or not Common.is_alive(tu):
			continue
		var h := head_id(t)
		if h in out:
			continue
		if slug == "squig_barrage" and _is_monster_or_vehicle(h):
			continue
		out.append(h)
	return out

## Madcap Artillery: the effect named by the Mek Gunz' (identical) weapon, or
## "" when the unit's guns differ.
static func _madcap_effect(unit_id: String) -> String:
	# "if all ranged weapons EQUIPPED by each Mek Gunz model are the same": the
	# per-model loadout the engine resolves from the roster's wargear (a
	# generated datasheet lists every option in meta.weapons — MA-LOADOUT), so
	# the names are the guns each model actually carries.
	var u := Common.unit(unit_id)
	var names: Array = []
	var re = Common.rules()
	if re and re.has_method("_get_model_weapon_ids"):
		if re.has_method("_ensure_loadout_resolved"):
			re._ensure_loadout_resolved(u)
		for m in u.get("models", []):
			if not m.get("alive", true):
				continue
			for wid in re._get_model_weapon_ids(u, m, "Ranged"):
				names.append(str(wid).replace("_", " "))
	else:
		for w in u.get("meta", {}).get("weapons", []):
			if str(w.get("type", "")).to_lower() != "melee":
				names.append(str(w.get("name", "")))
	var found := ""
	for nm in names:
		var n := str(nm).to_lower()
		var e := ""
		if n.contains("bubblechukka"):
			e = "wobbled"
		elif n.contains("kustom mega-kannon") or n.contains("kustom mega kannon"):
			e = "zapped"
		elif n.contains("smasha gun"):
			e = "smashed"
		elif n.contains("traktor kannon"):
			e = "grounded"
		else:
			continue
		if found != "" and found != e:
			return ""
		found = e
	return found

## Windows that may offer more than one ability use: after a use the same
## window re-opens with what is still on offer (BasePhase generic follow-up
## "ork11e_reoffer").
const REOFFER_WINDOWS := ["battle_shock_step_start", "movement_phase_start", "movement_phase_end", "fight_phase_end"]
## Windows re-opened only while another ABILITY is still on offer there (e.g.
## Boss' Ammo Runt then Ammo Runts on a Warboss-led Boyz mob — both apply to
## the same selection; the held action resumes once the queue is empty).
const REOFFER_IF_ABILITY_LEFT := ["unit_selected_to_shoot", "unit_selected_to_move", "unit_ended_normal_move", "unit_has_shot"]

## USE_WINDOW_STRATAGEM on an ability (routed by StratagemManager.use_stratagem).
## Returns the use_stratagem result shape: {success, diffs (already applied),
## stratagem_name, followup?, error?}.
static func use(player: int, sid: String, target_unit_id: String, context: Dictionary) -> Dictionary:
	if _enh().handles_id(sid):  # WP-O5: an activated enhancement ("ork11e_ab_enh_*")
		return _enh().use(player, sid, target_unit_id, context)
	var slug := slug_of(sid)
	var window_id := str(context.get("window_id", ""))
	var targets := _targets(slug, player, window_id, context)
	var entry: Dictionary = {}
	for t in targets:
		if str(t.get("unit_id", "")) == target_unit_id:
			entry = t
	if entry.is_empty():
		return {"success": false, "error": "%s cannot be used on %s now" % [display(slug), Common.unit_name(target_unit_id)], "diffs": []}
	var secondary := str(context.get("secondary_id", ""))
	if entry.has("secondary"):
		var ok := false
		for o in entry.secondary.get("options", []):
			if str(o.get("id", "")) == secondary:
				ok = true
		if not ok:
			return {"success": false, "error": "%s needs a valid target unit" % display(slug), "diffs": []}
	var variant := str(context.get("variant_id", ""))
	if bool(entry.get("require_variant", false)):
		var vok := false
		for v in entry.get("variants", []):
			if str(v.get("id", "")) == variant:
				vok = true
		if not vok:
			return {"success": false, "error": "%s needs one of its options" % display(slug), "diffs": []}
	var res := _apply(slug, player, target_unit_id, secondary, variant, context)
	var diffs: Array = res.get("diffs", [])
	var gs = Common.game_state()
	if not diffs.is_empty() and gs:
		gs.apply_state_changes(diffs)
	var log_text := str(res.get("log", ""))
	if log_text != "":
		Common.log_info("OrkAbilities11e: %s" % log_text)
		_event_log(player, log_text)
	var out := {"success": true, "diffs": diffs, "stratagem_name": display(slug), "cp_cost": 0}
	var followup: Dictionary = res.get("followup", {})
	if followup.is_empty() and (window_id in REOFFER_WINDOWS or window_id in REOFFER_IF_ABILITY_LEFT):
		var wctx: Dictionary = context.duplicate(true)
		for k in ["secondary_id", "variant_id", "variant_label"]:
			wctx.erase(k)
		if window_id in REOFFER_WINDOWS or not window_offers(player, window_id, wctx).is_empty():
			followup = {"type": "ork11e_reoffer", "player": player, "window_id": window_id, "ctx": wctx}
	if not followup.is_empty():
		out["followup"] = followup
	return out

static func _flag_diffs_group(unit_id: String, flag: String, value) -> Array:
	return Common.set_flag_diffs(group(unit_id), flag, value)

static func _mw_diffs(target_id: String, mw: int) -> Dictionary:
	var re = Common.rules()
	if re == null or mw <= 0:
		return {"diffs": [], "casualties": 0}
	return re.apply_mortal_wounds_to_unit(head_id(target_id), mw, Common.state())

static func _apply(slug: String, player: int, uid: String, secondary: String, variant: String, ctx: Dictionary) -> Dictionary:
	var rng = _rng()
	var name := Common.unit_name(uid)
	match slug:
		"boss_ammo_runt":
			return {"diffs": [{"op": "set", "path": "units.%s.flags.%s" % [uid, F_BOSS_AMMO_RUNT], "value": true}, use_diff(uid, slug)],
				"log": "%s uses Boss' Ammo Runt: its ranged attacks have +1 to hit this phase" % name}
		"ammo_runts":
			return {"diffs": [{"op": "set", "path": "units.%s.flags.%s" % [uid, F_AMMO_RUNTS], "value": true}, use_diff(uid, slug)],
				"log": "%s uses Ammo Runts: its ranged attacks have +1 to hit this phase" % name}
		"pulsa_rokkit":
			return {"diffs": [{"op": "set", "path": "units.%s.flags.%s" % [uid, F_PULSA_TARGET], "value": secondary}, use_diff(uid, slug)],
				"log": "%s fires a Pulsa Rokkit at %s: attacks against it have +1 AP and [LETHAL HITS]" % [name, Common.unit_name(secondary)]}
		"bomb_squigs", "bomb_squig":
			var roll := _d6(rng)
			var diffs: Array = [use_diff(uid, slug)]
			var text := "%s sends a bomb squig at %s: D6 = %d" % [name, Common.unit_name(secondary), roll]
			if roll >= 3:
				var mw := _d3(rng)
				var applied := _mw_diffs(secondary, mw)
				diffs.append_array(applied.get("diffs", []))
				text += " — %d mortal wound%s" % [mw, "" if mw == 1 else "s"]
			else:
				text += " — no effect"
			return {"diffs": diffs, "log": text}
		"rokkit_charge":
			var d: Array = []
			for gid in group(uid):
				var had := bool(Common.unit(gid).get("flags", {}).get("effect_grant_hazardous_melee", false))
				d.append({"op": "set", "path": "units.%s.flags.%s" % [gid, F_ROKKIT_CHARGE], "value": {"set_hazardous": not had}})
				if not had:
					d.append({"op": "set", "path": "units.%s.flags.effect_grant_hazardous_melee" % gid, "value": true})
			return {"diffs": d, "log": "%s uses Rokkit Charge: melee attacks have +1 A and S and [HAZARDOUS]" % name}
		"warpath":
			var roll := _d6(rng)
			roll = _enh().psychic_reroll(uid, roll, rng)  # WP-O5 Warphead
			var mode := "kill_rig" if has_id(uid, "wurrboy") or group_has_keyword(uid, "KILL RIG") else "weirdboy"
			var d: Array = _flag_diffs_group(uid, F_WARPATH, mode)
			d.append_array(_psychic_spend_diffs(uid, PSY_WARPATH))
			var text := "%s manifests Warpath (psychic roll %d)" % [name, roll]
			if roll == 1:
				for gid in group(uid):
					d.append({"op": "set", "path": "units.%s.flags.battle_shocked" % gid, "value": true})
				text += " — a 1: the unit is battle-shocked"
			text += "; its melee attacks have %s and [PSYCHIC]" % ("[LETHAL HITS]" if mode == "kill_rig" else "re-roll wound rolls of 1")
			return {"diffs": d, "log": text}
		"krushin_impetus":
			var n := _models_engaged_with(uid, secondary)
			var rolls: Array = []
			var mw := 0
			for _i in range(n):
				var r := _d6(rng)
				rolls.append(r)
				if r >= 3:
					mw += 1
			var d: Array = [use_diff(uid, slug)]
			d.append_array(_mw_diffs(secondary, mw).get("diffs", []))
			return {"diffs": d, "log": "%s — Krushin' Impetus vs %s: %d dice %s → %d mortal wound%s" % [name, Common.unit_name(secondary), n, str(rolls), mw, "" if mw == 1 else "s"]}
		"intimidating_motivation", "get_back_in_da_race", "keep_huntin":
			var d: Array = [army_use_diff(player, slug)]
			var tgt_ids: Array = [secondary]
			if slug == "get_back_in_da_race":
				tgt_ids.append_array(_embarked_units(secondary))
			for t in tgt_ids:
				d.append_array(clear_battle_shock_diffs(str(t)))
				d.append_array(rile_up_diffs(str(t), player, "start_of_your_next_turn", display(slug)))
			return {"diffs": d, "log": "%s uses %s: %s is no longer battle-shocked and is riled up until the start of your next turn" % [name, display(slug), Common.unit_name(secondary)]}
		"clever_know_wotz":
			var heal := _d3(rng)
			var hd := heal_diffs(secondary, heal)
			var d: Array = [use_diff(uid, slug)]
			d.append_array(hd.diffs)
			for gid in group(secondary):
				d.append({"op": "set", "path": "units.%s.flags.%s" % [gid, F_KNOW_WOTZ], "value": {"player": player, "set_turn_key": _turn_key()}})
			return {"diffs": d, "log": "%s uses Clever Know-wotz on %s: heals %d (D3 = %d) and its attacks have +1 to hit until the start of your next Movement phase" % [name, Common.unit_name(secondary), int(hd.healed) + int(hd.revived), heal]}
		"shokk_boosta":
			return {"diffs": [{"op": "set", "path": "units.%s.flags.%s" % [uid, F_SHOKK_BOOSTA], "value": true}],
				"log": "%s uses its Shokk-boosta: the advance roll is a 6 and it can move through models (hazard rolls when the move ends)" % name}
		"found_em":
			var d: Array = [use_diff(uid, slug)]
			d.append_array(_flag_diffs_group(secondary, F_FOUND_EM, {"player": player}))
			return {"diffs": d, "log": "%s — Found 'Em!: %s has +3\" detection range until the end of the turn" % [name, Common.unit_name(secondary)]}
		"drive_by_skorchin":
			var d: Array = [use_diff(uid, slug)]
			d.append_array(_flag_diffs_group(secondary, F_NO_OVERWATCH, {"player": player}))
			return {"diffs": d, "log": "%s — Drive-by Skorchin': %s cannot be targeted with Fire Overwatch until the end of the turn" % [name, Common.unit_name(secondary)]}
		"gut_hatch":
			return {"diffs": [use_diff(uid, slug)], "followup": {"type": "assault_disembark", "transport_id": uid},
				"log": "%s opens its Gut Hatch: embarked units can make an assault disembark move" % name}
		"makari":
			var used := army_uses(player, "makari")
			var continuing := int(used.get("battle", 0)) >= 1
			var picks := (int(used.get("picks", 0)) if continuing else 0) + 1
			var picked: Array = (used.get("picked", []) as Array).duplicate() if continuing else []
			picked.append(secondary)
			var all = Common.state().get("players", {}).get(str(player), {}).get(F_USES, {})
			var copy: Dictionary = all.duplicate(true) if typeof(all) == TYPE_DICTIONARY else {}
			var mk: Dictionary = copy.get("makari", {}) if typeof(copy.get("makari", {})) == TYPE_DICTIONARY else {}
			mk["battle"] = 1
			mk["round"] = _round()
			mk["phase_key"] = _phase_key()
			mk["picks"] = picks
			mk["picked"] = picked
			copy["makari"] = mk
			var rec := {"op": "set", "path": "players.%d.%s" % [player, F_USES], "value": copy}
			var d: Array = [rec]
			d.append_array(rile_up_diffs(secondary, player, "start_of_your_next_turn", "Makari"))
			var res := {"diffs": d, "log": "Makari, Hoist Dat Banner!: %s is riled up until the start of your next turn (%d/%d)" % [Common.unit_name(secondary), picks, _round()]}
			return res
		"da_jump":
			var roll := _d6(rng)
			roll = _enh().psychic_reroll(uid, roll, rng)  # WP-O5 Warphead
			var d: Array = [army_use_diff(player, slug)]
			d.append_array(_psychic_spend_diffs(uid, PSY_DA_JUMP))
			var text := "%s manifests Da Jump (psychic roll %d)" % [name, roll]
			if roll == 1:
				for gid in group(uid):
					d.append({"op": "set", "path": "units.%s.flags.battle_shocked" % gid, "value": true})
				text += " — a 1: the unit is battle-shocked"
			d.append_array(strategic_reserves_diffs(uid))
			for gid in Common.attached_group_ids(uid):
				d.append({"op": "set", "path": "units.%s.flags.%s" % [gid, F_DA_JUMP_DS], "value": true})
			text += "; it is placed in strategic reserves and has Deep Strike"
			return {"diffs": d, "log": text}
		"supreme_kunnin":
			var cap := 5.0
			var roll := 0
			if variant != "riled5":
				roll = _d6(rng)
				cap = float(roll)
			return {"diffs": [army_use_diff(player, slug)],
				"followup": {"type": "reactive_normal_move", "unit_id": uid, "max_inches": cap, "roll": roll,
					"source": "Supreme Kunnin'", "away_from_unit_id": str(ctx.get("enemy_unit_id", ""))},
				"log": "%s uses Supreme Kunnin': a normal move of up to %d\"%s" % [name, int(cap), (" (D6 = %d)" % roll) if roll > 0 else " (riled up)"]}
		"kunnin_infiltrator", "aerial_manoover", "shokk_attack_engine":
			var d: Array = [use_diff(uid, slug)]
			d.append_array(strategic_reserves_diffs(uid))
			return {"diffs": d, "log": "%s uses %s: placed in strategic reserves" % [name, display(slug)]}
		"burna_bomb":
			var roll := _d6(rng)
			var d: Array = [use_diff(uid, slug)]
			var text := "%s drops a Burna Bomb on %s: D6 = %d" % [name, Common.unit_name(secondary), roll]
			if roll >= 2:
				var mw := _d3(rng)
				d.append_array(_mw_diffs(secondary, mw).get("diffs", []))
				d.append_array(_flag_diffs_group(secondary, F_BURNA_BOMBED, {"player": player, "armed": false}))
				text += " — %d mortal wound%s; it cannot be hidden and ranged attacks against it have [IGNORES COVER] until the end of your next turn" % [mw, "" if mw == 1 else "s"]
			else:
				text += " — no effect"
			return {"diffs": d, "log": text}
		"boom_bomb":
			var roll := _d6(rng)
			var mw := 0
			if roll <= 3:
				mw = _d3(rng)
			elif roll <= 5:
				mw = 3
			else:
				mw = _d3(rng) + 3
			var d: Array = [use_diff(uid, slug)]
			d.append_array(_mw_diffs(secondary, mw).get("diffs", []))
			return {"diffs": d, "log": "%s drops a Boom Bomb on %s: D6 = %d — %d mortal wounds" % [name, Common.unit_name(secondary), roll, mw]}
		"rokkit_barrage", "squig_barrage", "bust_em", "madcap_artillery":
			return _post_shot_apply(slug, player, uid, secondary, rng)
		"crude_surgery":
			var amount := 3
			var d: Array = [use_diff(uid, slug)]
			var text := "%s uses Crude Surgery" % name
			if variant == "heal3_d3":
				var extra := _d3(rng)
				amount += extra
				d.append(use_diff(uid, "catch_dat_red_bit"))
				text += " + Catch Dat Red Bit (D3 = %d)" % extra
			var hd := heal_diffs(uid, amount)
			d.append_array(hd.diffs)
			text += ": heals %d of %d" % [int(hd.healed) + int(hd.revived), amount]
			return {"diffs": d, "log": text}
		"fix_dat_armour_up":
			var hd := heal_diffs(uid, 3)
			var d: Array = [use_diff(uid, slug)]
			d.append_array(hd.diffs)
			return {"diffs": d, "log": "%s uses Fix Dat Armour Up: heals %d of 3" % [name, int(hd.healed) + int(hd.revived)]}
		"push_dat_bit_back_in":
			var hd := heal_diffs(secondary, 3)
			var d: Array = [use_diff(uid, slug)]
			d.append_array(hd.diffs)
			return {"diffs": d, "log": "%s uses Push Dat Bit Back In on %s: heals %d of 3" % [name, Common.unit_name(secondary), int(hd.healed) + int(hd.revived)]}
		"full_throttle":
			var u := Common.unit(uid)
			var flags: Dictionary = u.get("flags", {})
			var d: Array = [use_diff(uid, slug)]
			var set_list: Array = []
			var prev = flags.get(F_ENGINE, null)
			if typeof(prev) == TYPE_DICTIONARY:
				for f in prev.get("set", []):
					d.append({"op": "remove", "path": "units.%s.flags.%s" % [uid, str(f)]})
			if variant == "turbo":
				for f in ["effect_advance_and_charge", "effect_fall_back_and_charge"]:
					if not bool(flags.get(f, false)) or (typeof(prev) == TYPE_DICTIONARY and f in prev.get("set", [])):
						d.append({"op": "set", "path": "units.%s.flags.%s" % [uid, f], "value": true})
						set_list.append(f)
			d.append({"op": "set", "path": "units.%s.flags.%s" % [uid, F_ENGINE], "value": {"player": player, "engine": variant, "set": set_list}})
			var label: String = {"turbo": "Turbo Engine", "shokk": "Shokk Attack Engine", "pulse": "Pulse Jet"}.get(variant, variant)
			return {"diffs": d, "log": "%s — Full Throttle: %s until the start of your next Command phase" % [name, label]}
		"thatll_learn_ya":
			var roll := _d3(rng)
			var grots := _gretchin_alive(uid)
			var d: Array = []
			var h := group_holder(uid, slug)
			d.append(use_diff(h, slug))
			var killed := 0
			for i in range(mini(roll, grots.size())):
				var gm: Array = grots[grots.size() - 1 - i]
				d.append({"op": "set", "path": "units.%s.models.%d.alive" % [str(gm[0]), int(gm[1])], "value": false})
				d.append({"op": "set", "path": "units.%s.models.%d.current_wounds" % [str(gm[0]), int(gm[1])], "value": 0})
				killed += 1
			d.append_array(clear_battle_shock_diffs(uid))
			return {"diffs": d, "log": "That'll Learn Ya: D3 = %d — %d Gretchin destroyed; %s is no longer battle-shocked" % [roll, killed, name]}
	return {"diffs": [], "log": ""}

static func _models_engaged_with(unit_id: String, enemy_id: String) -> int:
	var n := 0
	for gid in group(unit_id):
		for m in Common.unit(gid).get("models", []):
			if not m.get("alive", true) or m.get("position", null) == null:
				continue
			if _model_engaged_with_unit(m, enemy_id):
				n += 1
	return n

static func _post_shot_apply(slug: String, player: int, uid: String, target: String, rng) -> Dictionary:
	var name := Common.unit_name(uid)
	var d: Array = [use_diff(uid, slug)]
	match slug:
		"rokkit_barrage":
			var bs := battle_shock_roll(target, -1, rng, "Rokkit Barrage")
			d.append_array(bs.diffs)
			return {"diffs": d, "log": "%s — Rokkit Barrage: %s battle-shock roll %d+%d -1 = %d vs Ld %d+ — %s" % [
				name, Common.unit_name(target), bs.roll[0], bs.roll[1], bs.total, bs.ld, "passed" if bs.passed else "FAILED, battle-shocked"]}
		"squig_barrage":
			d.append_array(_flag_diffs_group(target, F_SQUIG_COVERED, {"player": player}))
			return {"diffs": d, "log": "%s — Squig Barrage: %s is covered in Squigs (its attacks have -1 to hit until the start of your next turn)" % [name, Common.unit_name(target)]}
		"bust_em":
			d.append_array(_flag_diffs_group(target, F_BUSTED, {"player": player}))
			return {"diffs": d, "log": "%s — Bust 'Em: %s is busted (friendly SPEED FREEKS attacks against it have [LETHAL HITS] this turn)" % [name, Common.unit_name(target)]}
		"madcap_artillery":
			var eff := _madcap_effect(uid)
			if eff == "":
				return {"diffs": d, "log": ""}
			d.append_array(_flag_diffs_group(target, F_MADCAP, {"player": player, "effect": eff}))
			var what: String = {"wobbled": "wobbled (its targets have the benefit of cover)", "zapped": "zapped (-1 Ld)",
				"smashed": "smashed (-2\" M)", "grounded": "grounded (cannot take to the skies)"}.get(eff, eff)
			return {"diffs": d, "log": "%s — Madcap Artillery: %s is %s until the start of your next turn" % [name, Common.unit_name(target), what]}
	return {"diffs": d, "log": ""}

## Post-shot abilities with exactly one enemy unit hit resolve on their own
## (the rule is mandatory — "select one enemy unit hit"); with two or more the
## unit_has_shot window offers the choice. Called by ShootingPhase (thin hook)
## before the post-shot windows open; returns the applied diffs.
static func after_unit_shot(shooter_id: String, hit_unit_ids: Array) -> Array:
	var all: Array = []
	if not _edition_11():
		return all
	var u := Common.unit(shooter_id)
	if u.is_empty():
		return all
	var player := int(u.get("owner", 0))
	if player != Common.active_player():
		return all
	var ctx := {"unit_id": shooter_id, "hit_unit_ids": hit_unit_ids}
	var rng = _rng()
	for slug in ["rokkit_barrage", "squig_barrage", "bust_em", "madcap_artillery"]:
		var h := group_holder(shooter_id, slug)
		if h == "" or used_this_phase(h, slug):
			continue
		var cands := _post_shot_candidates(slug, h, ctx)
		if cands.size() != 1:
			continue
		if slug == "madcap_artillery" and _madcap_effect(h) == "":
			continue
		var res := _post_shot_apply(slug, player, h, str(cands[0]), rng)
		var diffs: Array = res.get("diffs", [])
		var gs = Common.game_state()
		if gs and not diffs.is_empty():
			gs.apply_state_changes(diffs)
		all.append_array(diffs)
		if str(res.get("log", "")) != "":
			Common.log_info("OrkAbilities11e: %s" % res.log)
			_event_log(player, str(res.log))
	# WP-O5: Enhanced Runt-maw / Temperamental Shokka / Supa-glowy Fing.
	all.append_array(_enh().after_unit_shot(shooter_id, hit_unit_ids))
	return all

# ===========================================================================
# AI
# ===========================================================================

## Score for an ability offer (AIDecisionMaker.decide_window_stratagem uses it
## with a 1.0 threshold — abilities cost no CP).
static func ai_score(player: int, sid: String, target_unit_id: String, window_id: String, ctx: Dictionary) -> float:
	if _enh().handles_id(sid):  # WP-O5 activated enhancements
		return float(_enh().ai_score(player, sid, target_unit_id, window_id, ctx))
	var slug := slug_of(sid)
	match slug:
		"boss_ammo_runt", "ammo_runts":
			return 2.0 if _has_ranged(target_unit_id) else 0.0
		"pulsa_rokkit":
			return 3.0
		"bomb_squigs", "bomb_squig", "krushin_impetus", "burna_bomb", "boom_bomb":
			return 3.0
		"rokkit_charge":
			return 2.5
		"warpath":
			return 2.0 if _engaged(target_unit_id) else 0.0
		"intimidating_motivation", "get_back_in_da_race", "keep_huntin":
			return 2.5
		"makari":
			# Once per battle and its pick count grows with the round, so round 1
			# spends it only when riling a unit up turns a long shot into a real
			# Advance-and-charge this turn (ADV-CHG-1 / MAKARI-R1).
			if _round() >= 2:
				return 2.5
			var gain := _makari_best_charge_gain(player)
			if gain >= MAKARI_R1_MIN_CHARGE_GAIN:
				Common.log_info("OrkAbilities11e: MAKARI round 1 — riling up turns on an Advance-and-charge (+%d%% charge odds)" % int(round(gain * 100.0)))
				return 2.5
			return 0.0
		"clever_know_wotz":
			return 2.0
		"shokk_boosta":
			return 0.0  # hazard rolls on every model: the AI keeps its ordinary advance
		"found_em", "drive_by_skorchin":
			return 1.5
		"gut_hatch":
			return 2.0
		"da_jump":
			return 0.0  # repositioning through reserves is a plan-level decision
		"supreme_kunnin":
			return 1.5
		"kunnin_infiltrator", "aerial_manoover":
			return 0.0
		"rokkit_barrage", "squig_barrage", "bust_em", "madcap_artillery":
			return 2.0
		"crude_surgery", "fix_dat_armour_up", "push_dat_bit_back_in":
			return 2.0
		"full_throttle":
			return 2.0
		"shokk_attack_engine":
			return 0.0
		"thatll_learn_ya":
			return 2.0 if _gretchin_alive(target_unit_id).size() >= 6 else 0.0
	return 0.0

static func _has_ranged(unit_id: String) -> bool:
	for gid in group(unit_id):
		for w in Common.unit(gid).get("meta", {}).get("weapons", []):
			if str(w.get("type", "")).to_lower() == "ranged":
				return true
	return false

# ===========================================================================
# AUTOMATIC TRIGGERS (thin hooks in the phases)
# ===========================================================================

## Mobbed (Beast Snagga Boyz): when this unit ends a charge move, each enemy
## MONSTER/VEHICLE unit engaged with it makes a battle-shock roll with -1 (-2
## if this unit has 13+ models). Returns the applied diffs.
static func on_charge_move_ended(unit_id: String) -> Array:
	var all: Array = []
	if not _edition_11() or unit_id == "":
		return all
	var h := group_holder(unit_id, "mobbed")
	if h == "":
		return all
	var count := 0
	for gid in group(unit_id):
		for m in Common.unit(gid).get("models", []):
			if m.get("alive", true):
				count += 1
	var mod := -2 if count >= 13 else -1
	var rng = _rng()
	var player := int(Common.unit(unit_id).get("owner", 0))
	for eid in _engaged_enemy_ids(unit_id):
		if not _is_monster_or_vehicle(eid):
			continue
		var bs := battle_shock_roll(eid, mod, rng, "Mobbed")
		all.append_array(bs.diffs)
		_event_log(player, "Mobbed: %s battle-shock roll %d+%d %+d = %d vs Ld %d+ — %s" % [
			Common.unit_name(eid), bs.roll[0], bs.roll[1], mod, bs.total, bs.ld, "passed" if bs.passed else "FAILED, battle-shocked"])
	var gs = Common.game_state()
	if gs and not all.is_empty():
		gs.apply_state_changes(all)
	return all

## Thievin' Scavengers (Gretchin): at the end of your Movement phase, if this
## unit is controlling an objective, that objective is secured (14.03).
static func on_movement_phase_end(player: int) -> void:
	if not _edition_11():
		return
	var mm = Common.autoload("MissionManager")
	if mm == null or not mm.has_method("secure_objective"):
		return
	if mm.has_method("check_all_objectives"):
		mm.check_all_objectives()
	for uid in Common.state().get("units", {}):
		var u := Common.unit(str(uid))
		if int(u.get("owner", 0)) != player or not has(u, "thievin_scavengers") or not Common.is_on_battlefield(u):
			continue
		if Common.is_battle_shocked(u):
			continue
		for oid in controlled_objectives_in_range(str(uid), player):
			# 14.03: "that objective is secured" — by the army (no source unit),
			# so it persists until the opponent takes control, not until uid dies.
			mm.secure_objective(str(oid), player, "")
			_event_log(player, "Thievin' Scavengers: %s secures objective %s" % [Common.unit_name(str(uid)), str(oid)])
			Common.log_info("OrkAbilities11e: Thievin' Scavengers — %s secured %s for P%d" % [uid, oid, player])

## Idol of Belligerence (Stompa) + Beastscent (Kill Rig): a unit disembarks
## from `transport_id` in its controller's Movement phase. Returns diffs
## (already applied).
static func on_disembark(unit_id: String, transport_id: String) -> Array:
	var all: Array = []
	if not _edition_11() or unit_id == "" or transport_id == "":
		return all
	if _phase() != PH_MOVEMENT:
		return all
	var t := Common.unit(transport_id)
	var player := int(t.get("owner", 0))
	if player != Common.active_player():
		return all
	if has(t, "idol_of_belligerence"):
		all.append_array(rile_up_diffs(unit_id, player, "start_of_your_next_turn", "Idol of Belligerence"))
		_event_log(player, "Idol of Belligerence: %s disembarks from %s riled up (until the start of your next turn)" % [Common.unit_name(unit_id), Common.unit_name(transport_id)])
	if has(t, "beastscent") and not Common.is_battle_shocked(t) and _psychic_budget_ok(transport_id, PSY_BEASTSCENT):
		var rng = _rng()
		var roll := _d6(rng)
		roll = _enh().psychic_reroll(transport_id, roll, rng)  # WP-O5 Warphead
		all.append_array(_psychic_spend_diffs(transport_id, PSY_BEASTSCENT))
		if roll == 1:
			all.append({"op": "set", "path": "units.%s.flags.battle_shocked" % transport_id, "value": true})
		all.append_array(_flag_diffs_group(unit_id, F_BEASTSCENT, {"player": player}))
		_event_log(player, "Beastscent (psychic roll %d%s): %s's attacks against MONSTER/VEHICLE units have +1 to wound until the end of the turn" % [
			roll, " — the Kill Rig is battle-shocked" if roll == 1 else "", Common.unit_name(unit_id)])
	var gs = Common.game_state()
	if gs and not all.is_empty():
		gs.apply_state_changes(all)
	return all

## Shokk-boosta: the boosted advance move ended — one hazard roll per model.
static func on_advance_move_ended(unit_id: String) -> Array:
	var all: Array = []
	var h := ""
	for gid in group(unit_id):
		if Common.unit(gid).get("flags", {}).get(F_SHOKK_BOOSTA, false):
			h = gid
	if h == "":
		return all
	var rng = _rng()
	var re = Common.rules()
	var player := int(Common.unit(unit_id).get("owner", 0))
	for gid in group(unit_id):
		var u := Common.unit(gid)
		var n := 0
		for m in u.get("models", []):
			if m.get("alive", true):
				n += 1
		if n == 0:
			continue
		var hz: Dictionary = AttackSequence.hazard_rolls(u, n, rng) if rng != null else {"mortal_wounds": 0, "rolls": []}
		if int(hz.get("mortal_wounds", 0)) > 0 and re:
			var applied = re.apply_mortal_wounds_to_unit(gid, int(hz.mortal_wounds), Common.state())
			all.append_array(applied.get("diffs", []))
		_event_log(player, "Shokk-boosta: hazard rolls for %s %s — %d mortal wound(s)" % [Common.unit_name(gid), str(hz.get("rolls", [])), int(hz.get("mortal_wounds", 0))])
	for gid in group(unit_id):
		all.append({"op": "remove", "path": "units.%s.flags.%s" % [gid, F_SHOKK_BOOSTA]})
	var gs = Common.game_state()
	if gs and not all.is_empty():
		gs.apply_state_changes(all)
	return all

## Crude Surgery is mandatory ("this unit heals 3 wounds"): a Painboy whose
## unit lost wounds and that did not use it in the Command phase heals 3 at
## the end of that phase (no D3 — Catch Dat Red Bit is a choice). Deterministic
## (no dice), so it runs in place on every peer at the phase transition.
static func on_command_phase_exit(player: int) -> void:
	if not _edition_11():
		return
	for uid in Common.state().get("units", {}):
		var u := Common.unit(str(uid))
		if int(u.get("owner", 0)) != player or not has(u, "crude_surgery") or not Common.is_on_battlefield(u):
			continue
		if used_this_phase(str(uid), "crude_surgery") or unit_wounds_lost(str(uid)) <= 0:
			continue
		var hd := heal_diffs(str(uid), 3)
		var gs = Common.game_state()
		if gs and not hd.diffs.is_empty():
			gs.apply_state_changes(hd.diffs)
			gs.apply_state_changes([use_diff(str(uid), "crude_surgery")])
		_event_log(player, "Crude Surgery: %s heals %d wound(s)" % [Common.unit_name(str(uid)), int(hd.healed) + int(hd.revived)])
