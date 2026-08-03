class_name ModifierLedger
extends RefCounted

## Provenance for hit / wound roll modifiers — "WHY is this a 2+?".
##
## The engine has always tracked WHAT a modifier was (a bitmask of ±1 and
## re-roll flags) but never WHERE IT CAME FROM, so every player-facing surface
## could only say "+1 to hit" or "Wound modifier: +1". A Lions of the Emperor
## player wounding on 2+ from Against All Odds had no way to confirm the
## detachment rule was firing at all.
##
## A ledger is a plain Array of Dictionaries — no object churn on the hot
## resolution path, and it survives being stashed in hit_context/wound_context,
## dice blocks and phase stage-pause payloads without special handling:
##
##     {"source": "Against All Odds", "kind": "wound",
##      "effect": "plus_one", "detail": "no other friendly unit within 6\""}
##
## `effect` is a SEMANTIC string, deliberately not the HitModifier/WoundModifier
## enum value: those two enums assign different integers to the same concept
## (PLUS_ONE is 2 for hits but 4 for wounds), so a raw flag is meaningless
## without knowing which enum produced it.
##
## Consumers: DiceLogFormatter (named notes under each dice block),
## ResolutionDockBase (the MODIFIERS section in both resolution docks).

# --- effect kinds -----------------------------------------------------------
const PLUS_ONE := "plus_one"
const MINUS_ONE := "minus_one"
const REROLL_ONES := "reroll_ones"
const REROLL_FAILED := "reroll_failed"
## A rule that STRIPS other modifiers (Captain-General, [PSYCHIC]) rather than
## adding one. Recorded so the dock can explain a bonus that vanished.
const IGNORED := "ignored"
## 11e worsens/improves the BS/WS CHARACTERISTIC rather than the roll for cover
## (13.08) and plunging fire (22.05). Mathematically distinct from ±1 to the
## roll — it moves the threshold and is not subject to the ±1 dice cap — but to
## a player it is still "why am I hitting on 4+ instead of 3+", so it belongs
## in the same readout, named honestly.
const WORSEN_BS := "worsen_bs"
const IMPROVE_BS := "improve_bs"

const KIND_HIT := "hit"
const KIND_WOUND := "wound"

# Colors for the Dice Log notes / dock rows, by whether the entry helps the
# attacker. Kept here so both surfaces agree.
const COLOR_BONUS := "#9FE09F"
const COLOR_PENALTY := "#E89090"
const COLOR_REROLL := "#7FC8E8"
const COLOR_IGNORED := "#C0A0E0"
## An entry a suppression rule stripped after the fact — shown, but muted.
const COLOR_CANCELLED := "#808088"


## Record one modifier and where it came from. Safe to call with a null/absent
## ledger so resolution paths that don't collect provenance stay untouched.
static func note(ledger, source: String, kind: String, effect: String, detail: String = "") -> void:
	if ledger == null or not (ledger is Array):
		return
	ledger.append({
		"source": source,
		"kind": kind,
		"effect": effect,
		"detail": detail,
	})


## Record every source that fed an 11e ModifierStack net result. The stack
## already names its sources (benefit_of_cover, plunging_fire, heavy, …) — this
## converts those snake_case ids into player-facing names.
static func note_stack(ledger, sources: Array, kind: String, effect: String) -> void:
	for s in sources:
		note(ledger, prettify_source(str(s)), kind, effect, "")


## Flag every already-recorded entry that a suppression rule just stripped, so
## the readout can show "Against All Odds: +1 to hit (cancelled)" rather than
## claiming a bonus the maths no longer applies. Call this alongside the
## IGNORED note, with the effects the rule actually strips — Captain-General
## removes both ±1, [PSYCHIC] removes only the penalty.
static func mark_ignored(ledger, kind: String, effects: Array) -> void:
	for e in _entries(ledger):
		if str(e.get("kind", "")) != kind:
			continue
		if str(e.get("effect", "")) in effects:
			e["cancelled"] = true


## snake_case stack source id → display name. Unknown ids are title-cased so a
## newly added stack source still reads sensibly instead of vanishing.
static func prettify_source(id: String) -> String:
	match id:
		"benefit_of_cover":
			return "Benefit of cover"
		"plunging_fire":
			return "Plunging fire"
		"heavy":
			return "[HEAVY]"
		"close_quarters_monster_vehicle":
			return "Shooting while engaged"
		"engaged_monster_vehicle_target":
			return "Target is engaged"
		_:
			return id.replace("_", " ").capitalize()


## "+1 to hit" / "re-roll failed wound rolls" / "modifiers ignored".
static func effect_text(kind: String, effect: String) -> String:
	var noun := "hit" if kind == KIND_HIT else "wound"
	match effect:
		PLUS_ONE:
			return "+1 to %s" % noun
		MINUS_ONE:
			return "-1 to %s" % noun
		REROLL_ONES:
			return "re-roll %s rolls of 1" % noun
		REROLL_FAILED:
			return "re-roll failed %s rolls" % noun
		IGNORED:
			return "%s roll modifiers ignored" % noun.capitalize()
		WORSEN_BS:
			return "worsens the to-hit characteristic by 1"
		IMPROVE_BS:
			return "improves the to-hit characteristic by 1"
		_:
			return effect


static func color_for(effect: String) -> String:
	match effect:
		PLUS_ONE, IMPROVE_BS:
			return COLOR_BONUS
		MINUS_ONE, WORSEN_BS:
			return COLOR_PENALTY
		IGNORED:
			return COLOR_IGNORED
		_:
			return COLOR_REROLL


## One display line per entry: "Against All Odds: +1 to wound — no other
## friendly unit within 6"". Entries are de-duplicated (source+effect), because
## the same rule can legitimately be recorded on both the hit and wound thirds.
static func lines(ledger, kind: String = "") -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for e in _entries(ledger):
		if kind != "" and str(e.get("kind", "")) != kind:
			continue
		var key := "%s|%s|%s" % [e.get("source", ""), e.get("kind", ""), e.get("effect", "")]
		if seen.has(key):
			continue
		seen[key] = true
		var line := "%s: %s" % [e.get("source", "?"), effect_text(str(e.get("kind", "")), str(e.get("effect", "")))]
		var detail := str(e.get("detail", ""))
		if detail != "":
			line += " — %s" % detail
		var col := color_for(str(e.get("effect", "")))
		if e.get("cancelled", false):
			line += "  (cancelled)"
			col = COLOR_CANCELLED
		out.append({"text": line, "color": col})
	return out


## Compact one-liner for tight surfaces: "Against All Odds +1, Cover -1".
static func compact(ledger, kind: String = "") -> String:
	var parts: Array = []
	var seen: Dictionary = {}
	for e in _entries(ledger):
		if kind != "" and str(e.get("kind", "")) != kind:
			continue
		var key := "%s|%s|%s" % [e.get("source", ""), e.get("kind", ""), e.get("effect", "")]
		if seen.has(key):
			continue
		seen[key] = true
		var sym := ""
		match str(e.get("effect", "")):
			PLUS_ONE:
				sym = "+1"
			MINUS_ONE:
				sym = "-1"
			REROLL_ONES:
				sym = "rr1"
			REROLL_FAILED:
				sym = "rr"
			IGNORED:
				sym = "ignores mods"
			WORSEN_BS:
				sym = "worsens BS"
			IMPROVE_BS:
				sym = "improves BS"
		parts.append("%s %s" % [e.get("source", "?"), sym])
	return ", ".join(parts)


## Does this ledger name `source` at all? Used by tests and by the fight dock
## to highlight the detachment rule that prompted all this.
static func has_source(ledger, source: String) -> bool:
	for e in _entries(ledger):
		if str(e.get("source", "")) == source:
			return true
	return false


static func _entries(ledger) -> Array:
	if ledger == null or not (ledger is Array):
		return []
	return ledger
