extends RefCounted

## OrkCodexShooting — Codex: Orks (11e) stratagems of the SHOOTING group:
## Shooting-phase stratagems (own-turn selected/has-shot windows and the opponent-Shooting reactive windows).
##
## Contract: .llm/ork_codex_11e_design.md §3–§4 (and §6 "how to add a hook").
## The dispatcher OrkCodex11e.gd routes every csv_id in IDS here. A stratagem
## counts as mechanically implemented ONLY when its csv_id is in IMPLEMENTED —
## everything else stays "not yet mechanically implemented" (S panel) and is
## never offered in a window. See OrkCodexFight.gd (HIT 'EM HARDER) for a
## complete worked handler.
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
	"grab-it-wreckas",
	"grot-shields-runt-swarm",
	"hulking-brutes-bully-boyz",
	"speediest-freeks-kult-of-speed",
	"gun-crazy-show-offs-wreckas",
	"goaded-into-action-da-big-hunt",
]

## csv_ids whose handler is complete and validated. Empty until the group's
## handlers land.
const IMPLEMENTED: Dictionary = {}

const AI_KIND: Dictionary = {}


static func eligible_targets(_strat: Dictionary, _player: int, _window_id: String, _ctx: Dictionary) -> Array:
	return []


static func validate(strat: Dictionary, _player: int, _target_unit_id: String, _ctx: Dictionary) -> Dictionary:
	return {"ok": false, "reason": "%s is not yet mechanically implemented" % strat.get("name", "?")}


static func apply(strat: Dictionary, _target_unit_id: String, _ctx: Dictionary) -> Variant:
	Common.log_error("OrkCodexShooting: apply() called for unimplemented %s" % strat.get("csv_id", "?"))
	return []


static func clear(_strat: Dictionary, _unit_id: String) -> void:
	pass


static func ai_kind(strat: Dictionary) -> String:
	return str(AI_KIND.get(str(strat.get("csv_id", "")), "utility"))


## CP cost of a variant offered in a target entry's `variants` (e.g. HULKING
## BRUTES' +1 CP upgrade). -1 = unknown variant (the base cp_cost applies).
static func variant_cp_cost(_strat: Dictionary, _variant_id: String) -> int:
	return -1


## True when the stratagem may target a battle-shocked unit (BREAKIN' HEADS:
## "You can target that unit with this stratagem even though it is
## battle-shocked"). Default false — the core 15.01 battle-shock lock applies.
static func allows_battle_shocked_target(_strat: Dictionary, _ctx: Dictionary) -> bool:
	return false


static func ai_score(_strat: Dictionary, _player: int, _target_unit_id: String, _window_id: String, _ctx: Dictionary) -> float:
	return 0.0
