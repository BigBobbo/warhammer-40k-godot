extends RefCounted
class_name DiceLogFormatter

## DiceLogFormatter — structured, step-based rendering for the shared Dice Log
## (the "Dice Log" tab of the left GameLogPanel).
##
## Before this existed, every phase controller appended free-form BBCode prose
## to the shared RichTextLabel, so a shooting sequence read as a wall of text
## with dice emblems sprinkled in. This class gives all phases ONE visual
## grammar, so a player can see at a glance which attack is resolving and
## which step of the sequence each roll belongs to:
##
##   ⚔ ATTACK HEADER                      gold band — one per attack sequence
##   ▸ weapon sub-header                  white band — one per weapon resolved
##   [1·HIT 3+]  ⚀⚁⚂ → 7/10 hit          numbered colored step chip in a
##   [2·WOUND 4+] ⚀⚁ → 4/7 wound          2-column table row: chips align in
##   [3·SAVE 5+]  ⚀ → 2 failed            a fixed-width left column, dice +
##       · +1 to hit (Heavy)              result on the right; notes render
##   ✔ / ✘ outcome band                   small + dim under their step
##
## All helpers are static and take the target RichTextLabel first, so the
## Shooting / Fight / Charge / Movement controllers can share them without
## changing how they resolve `dice_log_display`.

const CHIP_WIDTH := 100.0
# Inner content width of every chip (text + invisible spacer). The table
# ignores cell min/max size overrides in practice, so uniform chip width is
# enforced by padding the cell content itself to this exact width.
const CHIP_INNER_WIDTH := 92.0
const CHIP_FONT_SIZE := 12
const DIE_PX := 18
const NOTE_FONT_SIZE := 12
const NOTE_INDENT := "      "

# Step chip styling: label + background color per step kind. Colors mirror the
# per-step colors already used by the Game Log combat cards (hit blue, wound
# orange, save purple, FNP green, damage gold) so both logs speak one language.
const CHIP_STYLES := {
	"attacks": {"label": "ATTACKS", "bg": Color(0.30, 0.34, 0.40)},
	"hit":     {"label": "HIT",     "bg": Color(0.16, 0.38, 0.62)},
	"wound":   {"label": "WOUND",   "bg": Color(0.66, 0.38, 0.12)},
	"save":    {"label": "SAVE",    "bg": Color(0.44, 0.30, 0.66)},
	"fnp":     {"label": "FNP",     "bg": Color(0.10, 0.52, 0.34)},
	"damage":  {"label": "DAMAGE",  "bg": Color(0.58, 0.48, 0.10)},
	"charge":  {"label": "CHARGE",  "bg": Color(0.62, 0.56, 0.10)},
	"advance": {"label": "ADVANCE", "bg": Color(0.18, 0.42, 0.62)},
	"generic": {"label": "ROLL",    "bg": Color(0.32, 0.35, 0.40)},
}

const COLOR_GOOD := "#7ED87E"
const COLOR_BAD := "#FF6B6B"
const COLOR_NEUTRAL := "#D8C070"
const COLOR_NOTE := "#8F9AA8"
const COLOR_HIT_TEXT := "#9FD0FF"
const COLOR_WOUND_TEXT := "#FFC08A"

const META_STEP := "dlf_step_counter"


# ==========================================================================
# Building blocks
# ==========================================================================

## Gold band opening a whole attack sequence (e.g. "Bolt rifle → Termagants").
## Resets the step numbering for the block that follows.
static func attack_header(rtl: RichTextLabel, text: String) -> void:
	if rtl == null:
		return
	_reset_steps(rtl)
	if rtl.get_total_character_count() > 0:
		rtl.append_text("\n")
	rtl.append_text("[bgcolor=#2a2314][b][color=#E8C477] ⚔ %s [/color][/b][/bgcolor]\n" % text)


## Sub-band for one weapon inside a sequence (e.g. "Weapon 1 of 2 — Slugga → Boyz").
## Also resets step numbering — each weapon's steps count from 1.
static func weapon_header(rtl: RichTextLabel, text: String) -> void:
	if rtl == null:
		return
	_reset_steps(rtl)
	rtl.append_text("[bgcolor=#1d222b][b][color=#D8E0E8] ▸ %s [/color][/b][/bgcolor]\n" % text)


## One resolution step: a fixed-width colored chip ("2· WOUND 4+") in the left
## column, dice icons + summary in the right column. Chips align vertically
## across rows because every step renders as a single-row 2-column table with
## the same chip column width.
static func step(rtl: RichTextLabel, kind: String, threshold_text: String, rolls: Array, threshold_num: int, crit_threshold: int, summary_bbcode: String, modified: Array = [], numbered: bool = true) -> void:
	if rtl == null:
		return
	var style: Dictionary = CHIP_STYLES.get(kind, CHIP_STYLES["generic"])
	var chip_text: String = str(style["label"])
	if numbered:
		chip_text = "%d· %s" % [_next_step(rtl), chip_text]
	if threshold_text != "":
		chip_text += " %s" % threshold_text

	rtl.push_table(2)
	rtl.set_table_column_expand(0, false)
	rtl.set_table_column_expand(1, true)

	# Chip cell — solid step color. Every step renders as its own single-row
	# table, and RichTextLabel sizes each table's chip column to its content
	# (cell size overrides are not honored), so chips would come out ragged.
	# Uniform width is therefore enforced on the CONTENT: the first line of
	# every chip cell is an invisible 1px-tall spacer image stretched to
	# CHIP_INNER_WIDTH, so every cell's widest line — and therefore every
	# chip — is exactly the same width and all right edges align. Labels
	# wider than the spacer simply wrap inside the chip.
	rtl.push_cell()
	var bg: Color = style["bg"]
	rtl.set_cell_row_background_color(bg, bg)
	rtl.set_cell_padding(Rect2(6, 2, 6, 2))
	# The spacer line rendered at font size 1 so it adds ~1px of height, not a
	# full empty text line above the label.
	rtl.push_font_size(1)
	rtl.add_image(_spacer_texture(), int(CHIP_INNER_WIDTH), 1, Color.WHITE, INLINE_ALIGNMENT_CENTER)
	rtl.add_text("\n")
	rtl.pop()
	rtl.push_font_size(CHIP_FONT_SIZE)
	rtl.push_bold()
	rtl.push_color(Color(1, 1, 1, 0.95))
	rtl.add_text(chip_text)
	rtl.pop()
	rtl.pop()
	rtl.pop()
	rtl.pop()  # cell

	# Content cell — the bold result first (right next to the chip, so the
	# number you care about is scannable), then the dice icons as detail.
	rtl.push_cell()
	rtl.set_cell_padding(Rect2(6, 2, 0, 2))
	if summary_bbcode != "":
		rtl.append_text(summary_bbcode)
		if not rolls.is_empty():
			rtl.append_text("   ")
	if not rolls.is_empty():
		append_dice(rtl, rolls, threshold_num, crit_threshold, modified)
	rtl.pop()  # cell
	rtl.pop()  # table
	# Tables render as inline blocks — without this newline the next appended
	# text (e.g. an outcome band) continues on the same visual line.
	rtl.append_text("\n")


## Small dim indented note line — modifiers, keywords, re-roll details. These
## visually recede so the step rows stay dominant.
static func note(rtl: RichTextLabel, text: String, color: String = COLOR_NOTE) -> void:
	if rtl == null:
		return
	rtl.append_text("[font_size=%d][color=%s]%s· %s[/color][/font_size]\n" % [NOTE_FONT_SIZE, color, NOTE_INDENT, text])


## Bold ✔ / ✘ / ◆ band closing a block ("2 models destroyed", "Charge failed…").
static func outcome(rtl: RichTextLabel, text: String, kind: String = "neutral") -> void:
	if rtl == null:
		return
	var col := COLOR_NEUTRAL
	var sym := "◆"
	if kind == "good":
		col = COLOR_GOOD
		sym = "✔"
	elif kind == "bad":
		col = COLOR_BAD
		sym = "✘"
	rtl.append_text("[b][color=%s] %s %s[/color][/b]\n" % [col, sym, text])


## Dim single-line status chatter (selection hints, sync notes). Keeps the
## informational lines visually quieter than the roll structure.
static func info(rtl: RichTextLabel, text: String, color: String = COLOR_NOTE) -> void:
	if rtl == null:
		return
	rtl.append_text("[color=%s]%s[/color]\n" % [color, text])


## Grouped inline d6 icons: one icon per distinct value (sorted ascending) with
## an "xN" count — same grouping the shooting log used, now shared everywhere.
## Colors: crit gold (>= crit_threshold), pass green / fail red vs threshold
## (checked against the MODIFIED value when provided), neutral blue otherwise.
static func append_dice(rtl: RichTextLabel, rolls: Array, threshold_num: int, crit_threshold: int = 7, modified: Array = []) -> void:
	if rtl == null:
		return
	if rolls.is_empty():
		rtl.append_text("[color=gray]—[/color]")
		return
	var counts := {}
	var mod_for := {}
	for i in range(rolls.size()):
		var v := int(rolls[i])
		counts[v] = int(counts.get(v, 0)) + 1
		if not mod_for.has(v):
			mod_for[v] = int(modified[i]) if i < modified.size() else v
	var values := counts.keys()
	values.sort()
	for idx in range(values.size()):
		var v := int(values[idx])
		var count := int(counts[v])
		var bg := _die_color(v, int(mod_for[v]), threshold_num, crit_threshold)
		rtl.add_image(DiceFaceIcons.get_face(v, bg), DIE_PX, DIE_PX, Color.WHITE, INLINE_ALIGNMENT_CENTER)
		if count > 1:
			rtl.append_text(" [color=#cfd6dd]x%d[/color]" % count)
		if idx < values.size() - 1:
			rtl.append_text("  ")


static func _die_color(raw: int, mod: int, threshold_num: int, crit_threshold: int) -> Color:
	if raw >= crit_threshold:
		return DiceFaceIcons.COLOR_CRITICAL
	if threshold_num > 0:
		return DiceFaceIcons.COLOR_SUCCESS if mod >= threshold_num else DiceFaceIcons.COLOR_FAIL
	return DiceFaceIcons.COLOR_NEUTRAL


# ==========================================================================
# Shared roll-block translator (Shooting + Fight)
# ==========================================================================

## Render one `dice_rolled` block from ShootingPhase / FightPhase into the
## structured format. Handles every context both phases emit; controllers keep
## their side-effects (docks, animated dice, history) and delegate display here.
static func format_roll_block(rtl: RichTextLabel, dice_data: Dictionary) -> void:
	if rtl == null:
		return
	var context := str(dice_data.get("context", ""))

	match context:
		"resolution_start":
			attack_header(rtl, str(dice_data.get("message", "Attack resolution")))
			return
		"weapon_progress":
			weapon_header(rtl, str(dice_data.get("message", "")))
			return
		"reroll_note":
			note(rtl, "↻ %s" % str(dice_data.get("message", "Re-roll")), "#FFA850")
			return
		"mathhammer_prediction":
			note(rtl, str(dice_data.get("message", "")), "#6FBFD8")
			return
		"feel_no_pain":
			_format_feel_no_pain(rtl, dice_data)
			return
		"variable_damage":
			_format_variable_damage(rtl, dice_data)
			return
		"auto_hit":
			_format_auto_hit(rtl, dice_data)
			return

	_format_generic_roll(rtl, dice_data, context)


static func _format_feel_no_pain(rtl: RichTextLabel, dice_data: Dictionary) -> void:
	var fnp_val := int(dice_data.get("fnp_value", 0))
	var prevented := int(dice_data.get("wounds_prevented", 0))
	var remaining := int(dice_data.get("wounds_remaining", 0))
	var total := int(dice_data.get("total_wounds", 0))
	var target_name := str(dice_data.get("target_unit_name", ""))
	var summary := ""
	if target_name != "":
		summary += "[color=%s]%s:[/color] " % [COLOR_NOTE, target_name]
	if prevented > 0:
		summary += "[color=%s]%d/%d prevented[/color]" % [COLOR_GOOD, prevented, total]
	else:
		summary += "[color=%s]0/%d prevented[/color]" % [COLOR_BAD, total]
	if remaining > 0:
		summary += "[color=%s], %d through[/color]" % [COLOR_BAD, remaining]
	step(rtl, "fnp", "%d+" % fnp_val, dice_data.get("rolls_raw", []), fnp_val, 7, summary)


static func _format_variable_damage(rtl: RichTextLabel, dice_data: Dictionary) -> void:
	var notation := str(dice_data.get("notation", ""))
	var total_dmg := int(dice_data.get("total_damage", 0))
	var dmg_values := []
	for r in dice_data.get("rolls", []):
		dmg_values.append(int(r.get("value", 0)))
	step(rtl, "damage", notation, dmg_values, 0, 7, "[b]= %d damage[/b]" % total_dmg)


static func _format_auto_hit(rtl: RichTextLabel, dice_data: Dictionary) -> void:
	# Variable attack roll first, as its own ATTACKS step.
	if dice_data.get("variable_attacks", false):
		var attack_values := []
		for r in dice_data.get("attacks_rolls", []):
			attack_values.append(int(r.get("value", 0)))
		var notation := str(dice_data.get("attacks_notation", ""))
		var base_atk := int(dice_data.get("base_attacks", 0))
		step(rtl, "attacks", notation, attack_values, 0, 7, "[b]= %d attacks[/b]" % base_atk)
	if dice_data.get("blast_weapon", false):
		var bonus := int(dice_data.get("blast_bonus_attacks", 0))
		if bonus > 0:
			note(rtl, "[BLAST] +%d attacks (%d models in target)" % [bonus, int(dice_data.get("target_model_count", 0))], "#9FE09F")
	var hits := int(dice_data.get("successes", 0))
	step(rtl, "hit", "auto", [], 0, 7, "[color=#9FE09F][b]%d automatic hits[/b] (Torrent)[/color]" % hits)
	if dice_data.get("lethal_hits_weapon", false) or dice_data.get("sustained_hits_weapon", false):
		note(rtl, "Lethal/Sustained Hits don't trigger (no hit roll)")


static func _format_generic_roll(rtl: RichTextLabel, dice_data: Dictionary, context: String) -> void:
	var rolls_raw: Array = dice_data.get("rolls_raw", [])
	var rolls_modified: Array = dice_data.get("rolls_modified", [])
	var rerolls: Array = dice_data.get("rerolls", [])
	if rerolls.is_empty() and "wound" in context:
		rerolls = dice_data.get("wound_rerolls", [])
	var successes := int(dice_data.get("successes", -1))
	var threshold := str(dice_data.get("threshold", ""))
	var threshold_num := threshold.replace("+", "").to_int() if threshold != "" else 0
	var crit_threshold := int(dice_data.get("critical_hit_threshold", 6))

	var kind := "generic"
	if "hit" in context:
		kind = "hit"
	elif "wound" in context:
		kind = "wound"
	elif "save" in context:
		kind = "save"

	# Variable attacks roll precedes the hit roll as its own ATTACKS step.
	if dice_data.get("variable_attacks", false):
		var attack_values := []
		for r in dice_data.get("attacks_rolls", []):
			attack_values.append(int(r.get("value", 0)))
		var notation := str(dice_data.get("attacks_notation", ""))
		var base_attacks := int(dice_data.get("base_attacks", 0))
		step(rtl, "attacks", notation, attack_values, 0, 7, "[b]= %d attacks[/b]" % base_attacks)

	# --- Pre-roll notes: keywords and modifiers, small + dim under the block ---
	if dice_data.get("heavy_bonus_applied", false):
		note(rtl, "[HEAVY] +1 to hit (unit stationary)", "#7FC8E8")
	var rapid_fire_bonus := int(dice_data.get("rapid_fire_bonus", 0))
	if rapid_fire_bonus > 0:
		note(rtl, "[RAPID FIRE %d] +%d attacks (%d models in half range)" % [int(dice_data.get("rapid_fire_value", 1)), rapid_fire_bonus, int(dice_data.get("models_in_half_range", 0))], "#FFB070")
	if dice_data.get("blast_weapon", false) and kind == "hit":
		var blast_bonus := int(dice_data.get("blast_bonus_attacks", 0))
		var target_models := int(dice_data.get("target_model_count", 0))
		if blast_bonus > 0:
			note(rtl, "[BLAST] +%d attacks (%d models in target)" % [blast_bonus, target_models], "#9FE09F")
		else:
			note(rtl, "[BLAST] no bonus (%d models in target < 5)" % target_models)
	if dice_data.get("lethal_hits_weapon", false) and kind == "hit":
		note(rtl, "[LETHAL HITS] critical hits auto-wound", "#E890E8")
	if dice_data.get("sustained_hits_weapon", false) and kind == "hit":
		var sh_value := int(dice_data.get("sustained_hits_value", 0))
		var sh_display := "D%d" % sh_value if dice_data.get("sustained_hits_is_dice", false) else str(sh_value)
		note(rtl, "[SUSTAINED HITS %s] critical hits generate +%s hits" % [sh_display, sh_display], "#7FC8E8")
	# Modifier provenance. The engine now records WHERE each ±1 / re-roll came
	# from (RulesEngine → ModifierLedger), so name the source instead of
	# printing an anonymous "+1 to hit" that leaves the player guessing which
	# rule fired. The bitmask/net fallbacks below still run for dice blocks
	# produced before the ledger existed (old saves, replays) or by paths that
	# don't collect one.
	var ledger: Array = dice_data.get("modifier_ledger", [])
	var named := false
	if kind == "hit" or kind == "wound":
		for entry in ModifierLedger.lines(ledger, kind):
			note(rtl, str(entry.get("text", "")), str(entry.get("color", COLOR_NOTE)))
			named = true
	if kind == "wound" and not named:
		var wm_net := int(dice_data.get("wound_modifier_net", 0))
		if wm_net != 0:
			note(rtl, "Wound modifier: %s" % ("+%d" % wm_net if wm_net > 0 else str(wm_net)), "#7FC8E8")
	if kind == "hit" and not named:
		var hm_bitmask := int(dice_data.get("modifiers_applied", 0))
		if hm_bitmask != 0:
			var hm_parts: Array = []
			if hm_bitmask & 2:
				hm_parts.append("+1 to hit")
			if hm_bitmask & 4:
				hm_parts.append("-1 to hit")
			if hm_bitmask & 1:
				hm_parts.append("re-roll 1s")
			if hm_bitmask & 8:
				hm_parts.append("re-roll failed")
			if not hm_parts.is_empty():
				note(rtl, ", ".join(hm_parts), "#7FC8E8")
	if not rerolls.is_empty():
		var rr_parts: Array = []
		for reroll in rerolls:
			rr_parts.append("%d→%d" % [int(reroll.get("original", 0)), int(reroll.get("rerolled_to", 0))])
		note(rtl, "Re-rolled: %s" % " ".join(rr_parts), "#E8D070")

	# --- The step row itself ---
	var total := rolls_raw.size()
	var summary := ""
	match kind:
		"hit":
			if successes >= 0:
				summary = "[color=%s][b]%d/%d hit[/b][/color]" % [COLOR_HIT_TEXT, successes, total]
			var critical_hits := int(dice_data.get("critical_hits", 0))
			if critical_hits > 0:
				summary += " [color=#E890E8](%d crit)[/color]" % critical_hits
		"wound":
			if successes >= 0:
				summary = "[color=%s][b]%d/%d wound[/b][/color]" % [COLOR_WOUND_TEXT, successes, total]
		"save":
			var failed := int(dice_data.get("failed", 0))
			var saved := successes if successes >= 0 else 0
			if failed > 0:
				summary = "[color=%s]%d saved[/color], [color=%s][b]%d failed[/b][/color]" % [COLOR_GOOD, saved, COLOR_BAD, failed]
			else:
				summary = "[color=%s][b]all %d saved[/b][/color]" % [COLOR_GOOD, saved]
		_:
			if successes >= 0:
				summary = "[b]%d/%d passed[/b]" % [successes, total]

	var chip_threshold := threshold
	var display_kind := kind
	if kind == "save" and dice_data.get("using_invuln", false):
		chip_threshold = "%s inv" % threshold

	# Save rolls belong to the DEFENDER — name them so the flip of perspective
	# is visible in the log.
	if kind == "save":
		var target_name := str(dice_data.get("target_unit_name", ""))
		if target_name != "":
			summary = "[color=%s]%s —[/color] %s" % [COLOR_NOTE, target_name, summary]

	# Only unmodified hit dice can crit; disable gold on other steps.
	var effective_crit := crit_threshold if kind == "hit" else 7
	var check_rolls: Array = rolls_modified if not rolls_modified.is_empty() else rolls_raw
	var show_rolls: Array = rolls_raw if not rolls_raw.is_empty() else check_rolls
	if kind == "generic" and context != "":
		# Unknown context — keep its name visible rather than a bare ROLL chip.
		summary = "[color=%s]%s[/color]  %s" % [COLOR_NOTE, context.capitalize().replace("_", " "), summary]
	step(rtl, display_kind, chip_threshold, show_rolls, threshold_num, effective_crit, summary, check_rolls)

	# --- Post-roll notes ---
	var sustained_bonus_hits := int(dice_data.get("sustained_bonus_hits", 0))
	if kind == "hit" and sustained_bonus_hits > 0:
		note(rtl, "[SUSTAINED HITS] +%d bonus hits → %d total to wound" % [sustained_bonus_hits, int(dice_data.get("total_hits_for_wounds", 0))], "#7FC8E8")
	var lethal_auto_wounds := int(dice_data.get("lethal_hits_auto_wounds", 0))
	if kind == "wound" and lethal_auto_wounds > 0:
		note(rtl, "[LETHAL HITS] %d auto-wounds + %d from rolls" % [lethal_auto_wounds, int(dice_data.get("wounds_from_rolls", 0))], "#E890E8")
	if kind == "save" and not dice_data.get("using_invuln", false):
		var original_save := int(dice_data.get("original_save", 0))
		var save_ap := int(dice_data.get("ap", 0))
		if original_save > 0 and save_ap != 0:
			note(rtl, "%d+ base save, AP-%d" % [original_save, abs(save_ap)])


# ==========================================================================
# Charge / Advance blocks
# ==========================================================================

## One charge roll: optional gold header naming the unit, then a CHARGE step
## with both dice and the total. Callers add outcome() bands for success/fail.
static func charge_roll(rtl: RichTextLabel, unit_name: String, rolls: Array, total: int, with_header: bool = true) -> void:
	if rtl == null:
		return
	if with_header:
		attack_header(rtl, "Charge — %s" % unit_name)
	var dice_values := []
	for r in rolls:
		dice_values.append(int(r))
	step(rtl, "charge", "2D6", dice_values, 0, 7, "[b]= %d\"[/b]" % total, [], false)


## One advance roll: header naming the unit + an ADVANCE step with the die.
static func advance_roll(rtl: RichTextLabel, unit_name: String, roll: int) -> void:
	if rtl == null:
		return
	weapon_header(rtl, "Advance — %s" % unit_name)
	step(rtl, "advance", "D6", [roll], 0, 7, "[b]= +%d\" move[/b]" % roll, [], false)


# ==========================================================================
# Chip width enforcement
# ==========================================================================

static var _spacer_tex: ImageTexture = null


## 1x1 transparent texture, stretched via add_image to pad chip cells to a
## uniform width (images contribute exact width and are never trimmed).
static func _spacer_texture() -> ImageTexture:
	if _spacer_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		_spacer_tex = ImageTexture.create_from_image(img)
	return _spacer_tex


# ==========================================================================
# Step numbering (per attack/weapon block, stored on the label)
# ==========================================================================

static func _reset_steps(rtl: RichTextLabel) -> void:
	rtl.set_meta(META_STEP, 0)


static func _next_step(rtl: RichTextLabel) -> int:
	var n := int(rtl.get_meta(META_STEP, 0)) + 1
	rtl.set_meta(META_STEP, n)
	return n
