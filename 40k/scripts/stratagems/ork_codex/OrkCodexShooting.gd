extends RefCounted

## OrkCodexShooting — Codex: Orks (11e) stratagems of the SHOOTING group:
## own-turn Shooting-phase stratagems offered when a unit is selected to shoot.
## (The has-shot and opponent-Shooting reactive ones live in OrkCodexShootingReactive.gd.)
##
## Contract: .llm/ork_codex_11e_design.md §3–§4 (and §6 "how to add a hook").
## The dispatcher OrkCodex11e.gd routes every csv_id in IDS here. A stratagem
## counts as mechanically implemented ONLY when its csv_id is in IMPLEMENTED —
## everything else stays "not yet mechanically implemented" (S panel) and is
## never offered in a window. See OrkCodexFight.gd (HIT 'EM HARDER) for a
## complete worked handler.
##
## Every stratagem here is offered in the unit_selected_to_shoot window
## (ShootingPhase._process_select_shooter -> _open_selected_to_shoot_window),
## targets the unit that was just selected to shoot, and lasts until the end
## of the phase (expires end_of_phase -> clear()). The effects are unit flags
## read by the RulesEngine ranged resolvers through the ork11e_* helper block
## (RulesEngine.gd "Codex: Orks (11e) — when a unit is selected to shoot"):
##   CLOSE-RANGE DAKKA          ork11e_close_range_dakka         RAPID FIRE +1 (0 -> 1)
##   VINDICTIVE ARTILLERISTS    ork11e_vindictive_artillerists   = variant id; plus the
##                              ranged-only effect_lethal_hits_ranged / effect_grant_hazardous
##   DRIVE-BY BUSTIN'           ork11e_drive_by_bustin           +1 hit, Firing Deck weapons
##   KUSTOM DAKKA               ork11e_kustom_dakka              +1 wound vs non-MONSTER/VEHICLE
##   GLOWIN' DAKKA              ork11e_glowin_dakka              +1 AP vs a target within 9"
##   NEVER ENOUGH DAKKA         ork11e_never_enough_dakka        ranged [SUSTAINED HITS 1]
##   LONG, UNCONTROLLED BURSTS  ork11e_long_uncontrolled_bursts  re-roll hits vs FLY
##   DAKKASTORM                 ork11e_dakkastorm                ranged [SUSTAINED HITS 1]
## None of the flags uses the effect_ prefix except the two reused EffectPrimitives
## flags (ShootingPhase wipes effect_* at phase end, which is this duration anyway).
##
## Handler API (all static; called by the dispatcher only):
##   eligible_targets(strat, player, window_id, ctx) -> Array of target entries
##       ({unit_id, label, variants?, secondary?} — see Common.target_entry)
##   validate(strat, player, target_unit_id, ctx) -> {ok: bool, reason: String}
##   apply(strat, target_unit_id, ctx) -> Array of diffs OR {diffs, followup}
##   clear(strat, unit_id) -> void          (effect expiry; mutate flags in place)
##   ai_kind(strat) -> "offensive" | "defensive" | "utility"
##   ai_score(strat, player, target_unit_id, window_id, ctx) -> float
##   variant_cp_cost(strat, variant_id) -> int   (-1 = base cost)
##   allows_battle_shocked_target(strat, ctx) -> bool

const Common = preload("res://scripts/stratagems/ork_codex/OrkCodexCommon.gd")

## Every csv_id owned by this group (registry). Do not move ids between groups.
const IDS: Array = [
	"close-range-dakka-war-horde",
	"vindictive-artillerists-madcap-meks",
	"drive-by-bustin-wreckas",
	"kustom-dakka-shoota-boyz",
	"glowin-dakka-shoota-boyz",
	"never-enough-dakka-shoota-boyz",
	"long-uncontrolled-bursts-flyboyz",
	"dakkastorm-kult-of-speed",
]

## csv_ids whose handler is complete and validated.
const IMPLEMENTED: Dictionary = {
	"close-range-dakka-war-horde": true,
	"vindictive-artillerists-madcap-meks": true,
	"drive-by-bustin-wreckas": true,
	"kustom-dakka-shoota-boyz": true,
	"glowin-dakka-shoota-boyz": true,
	"never-enough-dakka-shoota-boyz": true,
	"long-uncontrolled-bursts-flyboyz": true,
	"dakkastorm-kult-of-speed": true,
}

const AI_KIND: Dictionary = {
	"close-range-dakka-war-horde": "offensive",
	"vindictive-artillerists-madcap-meks": "offensive",
	"drive-by-bustin-wreckas": "offensive",
	"kustom-dakka-shoota-boyz": "offensive",
	"glowin-dakka-shoota-boyz": "offensive",
	"never-enough-dakka-shoota-boyz": "offensive",
	"long-uncontrolled-bursts-flyboyz": "offensive",
	"dakkastorm-kult-of-speed": "offensive",
}

const WINDOW := "unit_selected_to_shoot"

# Flag names (mirrored by RulesEngine.ORK11E_FLAG_* — keep in sync).
const FLAG_CLOSE_RANGE_DAKKA := "ork11e_close_range_dakka"
const FLAG_VINDICTIVE_ARTILLERISTS := "ork11e_vindictive_artillerists"
const FLAG_DRIVE_BY_BUSTIN := "ork11e_drive_by_bustin"
const FLAG_KUSTOM_DAKKA := "ork11e_kustom_dakka"
const FLAG_GLOWIN_DAKKA := "ork11e_glowin_dakka"
const FLAG_NEVER_ENOUGH_DAKKA := "ork11e_never_enough_dakka"
const FLAG_LONG_UNCONTROLLED_BURSTS := "ork11e_long_uncontrolled_bursts"
const FLAG_DAKKASTORM := "ork11e_dakkastorm"
# Reused ranged-only EffectPrimitives flags (VINDICTIVE ARTILLERISTS).
const FLAG_LETHAL_HITS_RANGED := "effect_lethal_hits_ranged"
const FLAG_GRANT_HAZARDOUS := "effect_grant_hazardous"

# VINDICTIVE ARTILLERISTS variants: "Your unit's ranged attacks have:
# [Lethal Hits] / Or: [Sustained Hits 1] / Or: [Hazardous], [Lethal Hits],
# [Sustained Hits 1]" — the player chooses exactly one.
const VA_LETHAL := "lethal_hits"
const VA_SUSTAINED := "sustained_hits"
const VA_OVERCHARGE := "overcharge"
const VA_VARIANTS: Array = [
	{"id": VA_LETHAL, "label": "[LETHAL HITS]"},
	{"id": VA_SUSTAINED, "label": "[SUSTAINED HITS 1]"},
	{"id": VA_OVERCHARGE, "label": "[HAZARDOUS] + [LETHAL HITS] + [SUSTAINED HITS 1]"},
]

## Per stratagem: display name, the keyword gate on the selected unit
## (all_of keywords + any_of keywords) and the single effect flag.
const SPEC: Dictionary = {
	"close-range-dakka-war-horde": {"name": "CLOSE-RANGE DAKKA", "all_of": ["ORKS"], "any_of": [], "flag": FLAG_CLOSE_RANGE_DAKKA, "kw_text": "an ORKS unit"},
	"vindictive-artillerists-madcap-meks": {"name": "VINDICTIVE ARTILLERISTS", "all_of": ["MEK GUNZ"], "any_of": [], "flag": FLAG_VINDICTIVE_ARTILLERISTS, "kw_text": "a MEK GUNZ unit"},
	"drive-by-bustin-wreckas": {"name": "DRIVE-BY BUSTIN'", "all_of": ["ORKS", "TRANSPORT"], "any_of": [], "flag": FLAG_DRIVE_BY_BUSTIN, "kw_text": "an ORKS TRANSPORT unit"},
	"kustom-dakka-shoota-boyz": {"name": "KUSTOM DAKKA", "all_of": ["ORKS", "INFANTRY"], "any_of": [], "flag": FLAG_KUSTOM_DAKKA, "kw_text": "an ORKS INFANTRY unit"},
	"glowin-dakka-shoota-boyz": {"name": "GLOWIN' DAKKA", "all_of": ["ORKS", "INFANTRY"], "any_of": [], "flag": FLAG_GLOWIN_DAKKA, "kw_text": "an ORKS INFANTRY unit"},
	"never-enough-dakka-shoota-boyz": {"name": "NEVER ENOUGH DAKKA", "all_of": ["ORKS", "INFANTRY"], "any_of": [], "flag": FLAG_NEVER_ENOUGH_DAKKA, "kw_text": "an ORKS INFANTRY unit"},
	"long-uncontrolled-bursts-flyboyz": {"name": "LONG, UNCONTROLLED BURSTS", "all_of": ["ORKS"], "any_of": ["AIRCRAFT", "DEFFKOPTAS"], "flag": FLAG_LONG_UNCONTROLLED_BURSTS, "kw_text": "an ORKS AIRCRAFT/DEFFKOPTAS unit"},
	"dakkastorm-kult-of-speed": {"name": "DAKKASTORM", "all_of": ["SPEED FREEKS"], "any_of": [], "flag": FLAG_DAKKASTORM, "kw_text": "a SPEED FREEKS unit"},
}


static func _spec(strat: Dictionary) -> Dictionary:
	return SPEC.get(str(strat.get("csv_id", "")), {})


static func eligible_targets(strat: Dictionary, player: int, window_id: String, ctx: Dictionary) -> Array:
	var spec = _spec(strat)
	if spec.is_empty() or window_id != WINDOW:
		return []
	var uid := str(ctx.get("unit_id", ""))
	var check = _validate_selected_unit(strat, spec, player, uid, ctx)
	if not check.ok:
		return []
	if str(strat.get("csv_id", "")) == "vindictive-artillerists-madcap-meks":
		var cost := int(strat.get("cp_cost", 1))
		var variants: Array = []
		for v in VA_VARIANTS:
			variants.append({"id": v.id, "label": v.label, "cp_cost": cost})
		return [Common.target_entry(uid, {"variants": variants, "require_variant": true,
			"ai_variant": _va_best_variant(uid, ctx)})]
	return [Common.target_entry(uid)]


static func validate(strat: Dictionary, player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var spec = _spec(strat)
	if spec.is_empty():
		return {"ok": false, "reason": "%s is not yet mechanically implemented" % strat.get("name", "?")}
	var check = _validate_selected_unit(strat, spec, player, target_unit_id, ctx)
	if not check.ok:
		return check
	if str(strat.get("csv_id", "")) == "vindictive-artillerists-madcap-meks":
		var variant := str(ctx.get("variant_id", ""))
		if variant != "" and not variant in [VA_LETHAL, VA_SUSTAINED, VA_OVERCHARGE]:
			return {"ok": false, "reason": "VINDICTIVE ARTILLERISTS: unknown option '%s'" % variant}
	return {"ok": true, "reason": ""}


## The rule checks shared by every stratagem of the group: WHEN "Your Shooting
## phase, when a friendly <KEYWORDS> unit is selected to shoot" / TARGET "That
## <KEYWORDS> unit." (turn / phase / window / CP are gated by StratagemManager.)
static func _validate_selected_unit(strat: Dictionary, spec: Dictionary, player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var sname := str(spec.get("name", strat.get("name", "?")))
	var u = Common.unit(target_unit_id)
	if u.is_empty():
		return {"ok": false, "reason": "%s needs a target unit" % sname}
	if int(u.get("owner", 0)) != player:
		return {"ok": false, "reason": "%s must target a unit from your army" % sname}
	for kw in spec.get("all_of", []):
		if not Common.has_keyword(u, str(kw)):
			return {"ok": false, "reason": "%s can only target %s" % [sname, spec.get("kw_text", "")]}
	var any_of: Array = spec.get("any_of", [])
	if not any_of.is_empty() and not Common.has_any_keyword(u, any_of):
		return {"ok": false, "reason": "%s can only target %s" % [sname, spec.get("kw_text", "")]}
	if not Common.is_on_battlefield(u):
		return {"ok": false, "reason": "%s: that unit is not on the battlefield" % sname}
	var selected := str(ctx.get("unit_id", ""))
	if selected != "" and selected != target_unit_id:
		return {"ok": false, "reason": "%s must target the unit that was selected to shoot" % sname}
	return {"ok": true, "reason": ""}


static func apply(strat: Dictionary, target_unit_id: String, ctx: Dictionary) -> Variant:
	var spec = _spec(strat)
	if spec.is_empty():
		Common.log_error("OrkCodexShooting: apply() called for unimplemented %s" % strat.get("csv_id", "?"))
		return []
	var group = Common.attached_group_ids(target_unit_id)
	var diffs: Array = []
	var csv_id := str(strat.get("csv_id", ""))
	if csv_id == "vindictive-artillerists-madcap-meks":
		var variant := str(ctx.get("variant_id", ""))
		if not variant in [VA_LETHAL, VA_SUSTAINED, VA_OVERCHARGE]:
			Common.log_error("OrkCodexShooting: VINDICTIVE ARTILLERISTS used on %s without a chosen option (variant_id '%s') — effect NOT applied" % [target_unit_id, variant])
			return []
		diffs.append_array(Common.set_flag_diffs(group, FLAG_VINDICTIVE_ARTILLERISTS, variant))
		if variant == VA_LETHAL or variant == VA_OVERCHARGE:
			diffs.append_array(Common.set_flag_diffs(group, FLAG_LETHAL_HITS_RANGED, true))
		if variant == VA_OVERCHARGE:
			diffs.append_array(Common.set_flag_diffs(group, FLAG_GRANT_HAZARDOUS, true))
		Common.log_info("OrkCodexShooting: VINDICTIVE ARTILLERISTS (%s) — ranged attacks of %s gain %s until the end of the phase" % [
			variant, str(group), _va_label(variant)])
		return diffs
	diffs.append_array(Common.set_flag_diffs(group, str(spec.flag), true))
	Common.log_info("OrkCodexShooting: %s — %s on %s until the end of the phase" % [spec.name, _effect_summary(csv_id), str(group)])
	return diffs


static func clear(strat: Dictionary, unit_id: String) -> void:
	var spec = _spec(strat)
	if spec.is_empty():
		return
	var group = Common.attached_group_ids(unit_id)
	var csv_id := str(strat.get("csv_id", ""))
	if csv_id == "vindictive-artillerists-madcap-meks":
		var to_erase: Array = [FLAG_VINDICTIVE_ARTILLERISTS]
		var variant := str(Common.unit(unit_id).get("flags", {}).get(FLAG_VINDICTIVE_ARTILLERISTS, ""))
		if variant == VA_LETHAL or variant == VA_OVERCHARGE:
			to_erase.append(FLAG_LETHAL_HITS_RANGED)
		if variant == VA_OVERCHARGE:
			to_erase.append(FLAG_GRANT_HAZARDOUS)
		Common.erase_flags(group, to_erase)
		Common.log_info("OrkCodexShooting: VINDICTIVE ARTILLERISTS expired — cleared %s on %s" % [str(to_erase), str(group)])
		return
	Common.erase_flags(group, [str(spec.flag)])
	Common.log_info("OrkCodexShooting: %s expired — cleared %s on %s" % [spec.name, spec.flag, str(group)])


static func ai_kind(strat: Dictionary) -> String:
	return str(AI_KIND.get(str(strat.get("csv_id", "")), "utility"))


## CP cost of a variant offered in a target entry's `variants`. VINDICTIVE
## ARTILLERISTS' three options all cost the stratagem's base CP.
static func variant_cp_cost(strat: Dictionary, variant_id: String) -> int:
	if str(strat.get("csv_id", "")) == "vindictive-artillerists-madcap-meks" \
			and variant_id in [VA_LETHAL, VA_SUSTAINED, VA_OVERCHARGE]:
		return int(strat.get("cp_cost", 1))
	return -1


## True when the stratagem may target a battle-shocked unit (BREAKIN' HEADS:
## "You can target that unit with this stratagem even though it is
## battle-shocked"). Default false — the core 15.01 battle-shock lock applies.
static func allows_battle_shocked_target(_strat: Dictionary, _ctx: Dictionary) -> bool:
	return false


static func ai_score(strat: Dictionary, player: int, target_unit_id: String, window_id: String, ctx: Dictionary) -> float:
	if window_id != WINDOW:
		return 0.0
	var targets: Array = _ai_targets(target_unit_id, ctx)
	if targets.is_empty():
		return 0.0
	var prof = _ranged_profile(target_unit_id)
	if prof.attacks <= 0.0:
		return 0.0
	match str(strat.get("csv_id", "")):
		"close-range-dakka-war-horde":
			# Each bearer within half range of a target gathers one more attack die.
			return float(_bearers_within_half_range(target_unit_id, targets)) * prof.hit_p * 1.2
		"vindictive-artillerists-madcap-meks":
			return _va_score(target_unit_id, _va_best_variant(target_unit_id, ctx), prof)
		"drive-by-bustin-wreckas":
			# +1 to hit on the Firing Deck guns only (loaned or about to be).
			# An atomic SHOOT that plans no Firing Deck bearer ("<hull>@fd<i>")
			# would waste it — the AI's assignments are fixed before the loan.
			var planned_bearers: Array = ctx.get("planned_bearer_ids", [])
			if ctx.has("planned_bearer_ids") and not planned_bearers.any(func(m): return str(m).find("@fd") != -1):
				return 0.0
			return _firing_deck_attacks(target_unit_id) / 6.0 * 1.5
		"kustom-dakka-shoota-boyz":
			for tid in targets:
				var t = Common.unit(str(tid))
				if not Common.has_any_keyword(t, ["MONSTER", "VEHICLE"]):
					return prof.attacks * prof.hit_p / 6.0 * 2.0
			return 0.0
		"glowin-dakka-shoota-boyz":
			for tid in targets:
				if Common.within_inches(target_unit_id, str(tid), 9.0):
					return prof.attacks * prof.hit_p * 0.5 / 6.0 * 2.0
			return 0.0
		"never-enough-dakka-shoota-boyz", "dakkastorm-kult-of-speed":
			return prof.attacks / 6.0 * 1.2
		"long-uncontrolled-bursts-flyboyz":
			for tid in targets:
				if Common.has_keyword(Common.unit(str(tid)), "FLY"):
					return prof.attacks * (1.0 - prof.hit_p) * prof.hit_p * 1.2
			return 0.0
	return 0.0


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _va_label(variant: String) -> String:
	for v in VA_VARIANTS:
		if v.id == variant:
			return str(v.label)
	return variant


static func _effect_summary(csv_id: String) -> String:
	match csv_id:
		"close-range-dakka-war-horde":
			return "ranged attacks gain [RAPID FIRE 1] (+1 to an existing RAPID FIRE)"
		"drive-by-bustin-wreckas":
			return "+1 to hit for weapons selected for the Firing Deck ability"
		"kustom-dakka-shoota-boyz":
			return "+1 to wound for ranged attacks vs non-MONSTER/VEHICLE targets"
		"glowin-dakka-shoota-boyz":
			return "+1 AP for ranged attacks vs targets within 9\""
		"never-enough-dakka-shoota-boyz", "dakkastorm-kult-of-speed":
			return "ranged attacks gain [SUSTAINED HITS 1]"
		"long-uncontrolled-bursts-flyboyz":
			return "re-roll hit rolls for ranged attacks vs FLY targets"
	return "effect"


## Targets the AI scores against: the planned targets of an atomic SHOOT
## (ctx.planned_target_unit_ids) or, failing that, every enemy unit on the
## battlefield within reach of the unit's longest ranged weapon.
static func _ai_targets(unit_id: String, ctx: Dictionary) -> Array:
	var planned: Array = ctx.get("planned_target_unit_ids", [])
	if not planned.is_empty():
		return planned
	var out: Array = []
	var u = Common.unit(unit_id)
	var reach := _longest_range(unit_id)
	if reach <= 0.0:
		return out
	for tid in Common.state().get("units", {}):
		var t = Common.unit(str(tid))
		if int(t.get("owner", 0)) == int(u.get("owner", 0)) or not Common.is_on_battlefield(t):
			continue
		if Common.unit_distance_inches(unit_id, str(tid)) <= reach:
			out.append(str(tid))
	return out


static func _weapons(unit_id: String) -> Dictionary:
	var re = Common.rules()
	if re == null or not re.has_method("get_unit_weapons"):
		return {}
	return re.get_unit_weapons(unit_id, Common.state())


static func _profile(weapon_id: String) -> Dictionary:
	var re = Common.rules()
	if re == null or not re.has_method("get_weapon_profile"):
		return {}
	return re.get_weapon_profile(weapon_id, Common.state())


static func _longest_range(unit_id: String) -> float:
	var best := 0.0
	var weapons = _weapons(unit_id)
	for mid in weapons:
		for wid in weapons[mid]:
			best = maxf(best, float(_profile(str(wid)).get("range", 0)))
	return best


## Expected ranged attack count and the average chance to hit (from BS) of
## the unit's ranged weapons.
static func _ranged_profile(unit_id: String) -> Dictionary:
	var attacks := 0.0
	var hit_weighted := 0.0
	var weapons = _weapons(unit_id)
	for mid in weapons:
		for wid in weapons[mid]:
			var p = _profile(str(wid))
			if p.is_empty() or str(p.get("type", "Ranged")).to_lower() == "melee":
				continue
			var a := float(p.get("attacks", 1))
			var bs := clampi(int(p.get("bs", 4)), 2, 6)
			attacks += a
			hit_weighted += a * (7.0 - float(bs)) / 6.0
	return {"attacks": attacks, "hit_p": (hit_weighted / attacks) if attacks > 0.0 else 0.0}


static func _bearers_within_half_range(unit_id: String, targets: Array) -> int:
	var u = Common.unit(unit_id)
	var weapons = _weapons(unit_id)
	var meas = Common.autoload("Measurement")
	var count := 0
	for mid in weapons:
		var model := {}
		for m in u.get("models", []):
			if str(m.get("id", "")) == str(mid).get_slice("@", 0):
				model = m
		if model.is_empty() or not model.get("alive", true):
			continue
		for wid in weapons[mid]:
			var half := float(_profile(str(wid)).get("range", 0)) / 2.0
			if half <= 0.0:
				continue
			var near := false
			for tid in targets:
				for tm in Common.unit(str(tid)).get("models", []):
					if not tm.get("alive", true) or meas == null:
						continue
					if float(meas.model_to_model_distance_inches(model, tm)) <= half:
						near = true
						break
				if near:
					break
			if near:
				count += 1
	return count


## Attacks the transport's Firing Deck guns make (loaned already, or the best
## estimate from its embarked units while the loan is still to be chosen).
static func _firing_deck_attacks(unit_id: String) -> float:
	var u = Common.unit(unit_id)
	var attacks := 0.0
	var loans = u.get("flags", {}).get("firing_deck_weapons", [])
	if loans is Array and not loans.is_empty():
		for loan in loans:
			attacks += float(_profile(str(loan.get("weapon_id", ""))).get("attacks", 1))
		return attacks
	var capacity := int(u.get("transport_data", {}).get("firing_deck", 0))
	if capacity <= 0:
		return 0.0
	var slots := 0
	for emb_id in u.get("transport_data", {}).get("embarked_units", []):
		var emb = Common.unit(str(emb_id))
		if emb.is_empty() or emb.get("flags", {}).get("has_shot", false):
			continue
		var prof = _ranged_profile(str(emb_id))
		var alive := 0
		for m in emb.get("models", []):
			if m.get("alive", true):
				alive += 1
		if alive <= 0 or prof.attacks <= 0.0:
			continue
		var per_model: float = float(prof.attacks) / float(alive)
		while slots < capacity and alive > 0:
			attacks += per_model
			slots += 1
			alive -= 1
	return attacks


## VINDICTIVE ARTILLERISTS: the variant the AI prefers — the overcharged
## option unless its hazard rolls are too likely to cripple the unit.
static func _va_best_variant(unit_id: String, ctx: Dictionary) -> String:
	var prof = _ranged_profile(unit_id)
	var best := VA_SUSTAINED
	var best_score := -INF
	for v in [VA_SUSTAINED, VA_LETHAL, VA_OVERCHARGE]:
		var s := _va_score(unit_id, v, prof)
		if s > best_score:
			best_score = s
			best = v
	return best


static func _va_score(unit_id: String, variant: String, prof: Dictionary) -> float:
	var crits: float = float(prof.get("attacks", 0.0)) / 6.0
	var score := 0.0
	if variant == VA_SUSTAINED or variant == VA_OVERCHARGE:
		score += crits * 1.5
	if variant == VA_LETHAL or variant == VA_OVERCHARGE:
		score += crits * 1.2
	if variant == VA_OVERCHARGE:
		# 11e 06.03: a hazard roll fails on 1-2; 3 mortal wounds when every
		# model is a MONSTER/VEHICLE (Mek Gunz), else 1. Cost scales with how
		# much of the unit those wounds would take.
		var u = Common.unit(unit_id)
		var weapons := 0
		var w = _weapons(unit_id)
		for mid in w:
			weapons += w[mid].size()
		var wounds := 0
		for m in u.get("models", []):
			if m.get("alive", true):
				wounds += int(m.get("current_wounds", m.get("wounds", 1)))
		var mw := 3.0 if Common.has_any_keyword(u, ["MONSTER", "VEHICLE"]) else 1.0
		var expected_mw := float(weapons) * (2.0 / 6.0) * mw
		score -= expected_mw / maxf(1.0, float(wounds)) * 6.0
	return score
