extends RefCounted
class_name MathhhammerRuleModifiers

# MathhhammerRuleModifiers - Rule modifier system for Mathhammer simulations
# Handles special rules and combat modifiers for accurate statistical analysis
# Integrates with existing RulesEngine while adding simulation-specific rule application

# Rule categories for organization
enum RuleCategory {
	HIT_MODIFIER,
	WOUND_MODIFIER, 
	SAVE_MODIFIER,
	DAMAGE_MODIFIER,
	SITUATIONAL
}

# Rule definition structure
class RuleDefinition:
	var id: String
	var name: String
	var description: String
	var category: RuleCategory
	var conflicts_with: Array = []
	var requires: Array = []
	var apply_function: Callable
	
	func _init(rule_id: String, rule_name: String, rule_desc: String, rule_category: RuleCategory):
		id = rule_id
		name = rule_name
		description = rule_desc
		category = rule_category

# Static rule registry
static var RULE_REGISTRY: Dictionary = {}

# Initialize the rule system
static func initialize_rules() -> void:
	if not RULE_REGISTRY.is_empty():
		return  # Already initialized
	
	_register_hit_modifiers()
	_register_wound_modifiers() 
	_register_save_modifiers()
	_register_damage_modifiers()
	_register_situational_modifiers()

# Register hit roll modifiers
static func _register_hit_modifiers() -> void:
	var rule = RuleDefinition.new("lethal_hits", "Lethal Hits", "6s to hit automatically wound", RuleCategory.HIT_MODIFIER)
	rule.apply_function = _apply_lethal_hits
	RULE_REGISTRY[rule.id] = rule
	
	rule = RuleDefinition.new("sustained_hits", "Sustained Hits", "6s to hit generate extra hits", RuleCategory.HIT_MODIFIER)
	rule.apply_function = _apply_sustained_hits
	RULE_REGISTRY[rule.id] = rule
	
	rule = RuleDefinition.new("torrent", "Torrent", "Auto-hit (no hit roll, no critical hits)", RuleCategory.HIT_MODIFIER)
	rule.conflicts_with = ["hit_plus_1", "hit_minus_1"]
	rule.apply_function = _apply_torrent
	RULE_REGISTRY[rule.id] = rule

	rule = RuleDefinition.new("hit_plus_1", "+1 to Hit", "Add 1 to hit rolls", RuleCategory.HIT_MODIFIER)
	rule.conflicts_with = ["hit_minus_1", "torrent"]
	rule.apply_function = _apply_hit_modifier.bind(1)
	RULE_REGISTRY[rule.id] = rule

	rule = RuleDefinition.new("hit_minus_1", "-1 to Hit", "Subtract 1 from hit rolls", RuleCategory.HIT_MODIFIER)
	rule.conflicts_with = ["hit_plus_1", "torrent"]
	rule.apply_function = _apply_hit_modifier.bind(-1)
	RULE_REGISTRY[rule.id] = rule

# Register wound roll modifiers
static func _register_wound_modifiers() -> void:
	var rule = RuleDefinition.new("devastating_wounds", "Devastating Wounds", "6s to wound become mortal wounds", RuleCategory.WOUND_MODIFIER)
	rule.apply_function = _apply_devastating_wounds
	RULE_REGISTRY[rule.id] = rule
	
	rule = RuleDefinition.new("anti_infantry_4", "Anti-Infantry 4+", "Critical wounds on 4+ vs INFANTRY", RuleCategory.WOUND_MODIFIER)
	rule.apply_function = _apply_anti_keyword.bind("INFANTRY", 4)
	RULE_REGISTRY[rule.id] = rule

	rule = RuleDefinition.new("anti_vehicle_4", "Anti-Vehicle 4+", "Critical wounds on 4+ vs VEHICLE", RuleCategory.WOUND_MODIFIER)
	rule.apply_function = _apply_anti_keyword.bind("VEHICLE", 4)
	RULE_REGISTRY[rule.id] = rule

	rule = RuleDefinition.new("anti_monster_4", "Anti-Monster 4+", "Critical wounds on 4+ vs MONSTER", RuleCategory.WOUND_MODIFIER)
	rule.apply_function = _apply_anti_keyword.bind("MONSTER", 4)
	RULE_REGISTRY[rule.id] = rule
	
	rule = RuleDefinition.new("twin_linked", "Twin-linked", "Re-roll failed wound rolls", RuleCategory.WOUND_MODIFIER)
	rule.apply_function = _apply_twin_linked
	RULE_REGISTRY[rule.id] = rule

	rule = RuleDefinition.new("wound_plus_1", "+1 to Wound", "Add 1 to wound rolls", RuleCategory.WOUND_MODIFIER)
	rule.conflicts_with = ["wound_minus_1"]
	rule.apply_function = _apply_wound_modifier.bind(1)
	RULE_REGISTRY[rule.id] = rule
	
	rule = RuleDefinition.new("wound_minus_1", "-1 to Wound", "Subtract 1 from wound rolls", RuleCategory.WOUND_MODIFIER)
	rule.conflicts_with = ["wound_plus_1"]
	rule.apply_function = _apply_wound_modifier.bind(-1)
	RULE_REGISTRY[rule.id] = rule

# Register save modifiers
static func _register_save_modifiers() -> void:
	var rule = RuleDefinition.new("ignores_cover", "Ignores Cover", "Target cannot benefit from cover", RuleCategory.SAVE_MODIFIER)
	rule.conflicts_with = ["cover"]
	rule.apply_function = _apply_ignores_cover
	RULE_REGISTRY[rule.id] = rule
	
	rule = RuleDefinition.new("cover", "Target in Cover", "Target gains cover save bonus", RuleCategory.SAVE_MODIFIER)
	rule.conflicts_with = ["ignores_cover"]
	rule.apply_function = _apply_cover_bonus
	RULE_REGISTRY[rule.id] = rule

# Register damage modifiers
static func _register_damage_modifiers() -> void:
	var rule = RuleDefinition.new("feel_no_pain_6", "Feel No Pain 6+", "Ignore wounds on 6+", RuleCategory.DAMAGE_MODIFIER)
	rule.apply_function = _apply_feel_no_pain.bind(6)
	RULE_REGISTRY[rule.id] = rule
	
	rule = RuleDefinition.new("feel_no_pain_5", "Feel No Pain 5+", "Ignore wounds on 5+", RuleCategory.DAMAGE_MODIFIER)
	rule.conflicts_with = ["feel_no_pain_6", "feel_no_pain_4"]
	rule.apply_function = _apply_feel_no_pain.bind(5)
	RULE_REGISTRY[rule.id] = rule
	
	rule = RuleDefinition.new("feel_no_pain_4", "Feel No Pain 4+", "Ignore wounds on 4+", RuleCategory.DAMAGE_MODIFIER)
	rule.conflicts_with = ["feel_no_pain_6", "feel_no_pain_5"]
	rule.apply_function = _apply_feel_no_pain.bind(4)
	RULE_REGISTRY[rule.id] = rule

# Register situational modifiers
static func _register_situational_modifiers() -> void:
	var rule = RuleDefinition.new("rapid_fire", "Rapid Fire Range", "+X attacks at half range (per model)", RuleCategory.SITUATIONAL)
	rule.apply_function = _apply_rapid_fire
	RULE_REGISTRY[rule.id] = rule

	rule = RuleDefinition.new("waaagh_active", "Waaagh! Active", "Ork faction ability active", RuleCategory.SITUATIONAL)
	rule.apply_function = _apply_waaagh
	RULE_REGISTRY[rule.id] = rule

	rule = RuleDefinition.new("conversion_4", "Conversion 4+", "Critical hits on 4+ at 12\"+ range (expanded crit range)", RuleCategory.SITUATIONAL)
	rule.apply_function = _apply_conversion.bind(4)
	RULE_REGISTRY[rule.id] = rule

	rule = RuleDefinition.new("conversion_5", "Conversion 5+", "Critical hits on 5+ at 12\"+ range (expanded crit range)", RuleCategory.SITUATIONAL)
	rule.conflicts_with = ["conversion_4"]
	rule.apply_function = _apply_conversion.bind(5)
	RULE_REGISTRY[rule.id] = rule

# Extract available rules from unit data
static func extract_unit_rules(unit_ids: Array) -> Array:
	var available_rules = []
	var rule_set = {}
	
	for unit_id in unit_ids:
		if not GameState:
			continue
			
		var unit = GameState.get_unit(unit_id)
		if unit.is_empty():
			continue
		
		# Extract rules from weapons
		var weapons = unit.get("meta", {}).get("weapons", [])
		for weapon in weapons:
			var special_rules = weapon.get("special_rules", "")
			if special_rules != "":
				var weapon_rules = _parse_weapon_special_rules(special_rules)
				for rule_id in weapon_rules:
					rule_set[rule_id] = true
		
		# Extract rules from abilities
		var abilities = unit.get("meta", {}).get("abilities", [])
		for ability in abilities:
			var ability_rules = _parse_ability_rules(ability)
			for rule_id in ability_rules:
				rule_set[rule_id] = true
		
		# Extract faction-specific rules
		var keywords = unit.get("meta", {}).get("keywords", [])
		if "ORKS" in keywords:
			rule_set["waaagh_active"] = true
	
	# Convert to array and add common modifiers
	available_rules = rule_set.keys()
	
	# Add universal modifiers that are always available
	var universal_rules = [
		"hit_plus_1", "hit_minus_1", "wound_plus_1", "wound_minus_1",
		"cover", "ignores_cover", "rapid_fire", "torrent"
	]
	
	for rule_id in universal_rules:
		if not rule_id in available_rules:
			available_rules.append(rule_id)
	
	return available_rules

# Parse weapon special rules into rule IDs
static func _parse_weapon_special_rules(special_rules: String) -> Array:
	var rule_ids = []
	var rules_text = special_rules.to_lower()
	
	# Map special rule text to rule IDs
	var rule_mappings = {
		"lethal hits": "lethal_hits",
		"sustained hits": "sustained_hits", 
		"devastating wounds": "devastating_wounds",
		"twin-linked": "twin_linked",
		"anti-infantry": "anti_infantry_4",
		"anti-vehicle": "anti_vehicle_4",
		"anti-monster": "anti_monster_4",
		"ignores cover": "ignores_cover",
		"rapid fire": "rapid_fire",
		"torrent": "torrent",
		"conversion": "conversion_4"
	}
	
	for rule_text in rule_mappings:
		if rule_text in rules_text:
			rule_ids.append(rule_mappings[rule_text])
	
	return rule_ids

# Parse ability rules into rule IDs
static func _parse_ability_rules(ability: Dictionary) -> Array:
	var rule_ids = []
	var description = ability.get("description", "").to_lower()
	
	# Look for Feel No Pain abilities
	if "feel no pain" in description:
		if "4+" in description:
			rule_ids.append("feel_no_pain_4")
		elif "5+" in description:
			rule_ids.append("feel_no_pain_5")
		elif "6+" in description:
			rule_ids.append("feel_no_pain_6")
	
	return rule_ids

# Apply rule modifiers to simulation configuration
static func apply_rule_modifiers(config: Dictionary, active_rules: Dictionary) -> Dictionary:
	initialize_rules()
	
	var modified_config = config.duplicate(true)
	
	# Validate rule compatibility
	var validation = validate_rule_combination(active_rules)
	if not validation.valid:
		push_error("Invalid rule combination: " + str(validation.errors))
		return modified_config
	
	# Apply each active rule
	for rule_id in active_rules:
		if active_rules[rule_id] and RULE_REGISTRY.has(rule_id):
			var rule_def = RULE_REGISTRY[rule_id]
			if rule_def.apply_function.is_valid():
				rule_def.apply_function.call(modified_config)
	
	return modified_config

# Validate rule combination for conflicts
static func validate_rule_combination(active_rules: Dictionary) -> Dictionary:
	initialize_rules()
	
	var errors = []
	var active_rule_list = []
	
	# Get list of active rules
	for rule_id in active_rules:
		if active_rules[rule_id]:
			active_rule_list.append(rule_id)
	
	# Check for conflicts
	for rule_id in active_rule_list:
		if not RULE_REGISTRY.has(rule_id):
			errors.append("Unknown rule: " + rule_id)
			continue
		
		var rule_def = RULE_REGISTRY[rule_id]
		for conflict in rule_def.conflicts_with:
			if conflict in active_rule_list:
				errors.append("Rule conflict: %s conflicts with %s" % [rule_id, conflict])
	
	return {
		"valid": errors.is_empty(),
		"errors": errors
	}

# Rule application functions
static func _apply_lethal_hits(config: Dictionary) -> void:
	# Lethal Hits: 6s to hit automatically wound
	config["modifiers"] = config.get("modifiers", {})
	config.modifiers["lethal_hits"] = true

static func _apply_sustained_hits(config: Dictionary) -> void:
	# Sustained Hits: 6s to hit generate extra hits
	config["modifiers"] = config.get("modifiers", {})
	config.modifiers["sustained_hits"] = true

static func _apply_torrent(config: Dictionary) -> void:
	# Torrent: All attacks automatically hit — no hit roll made, no critical hits possible
	config["modifiers"] = config.get("modifiers", {})
	config.modifiers["torrent"] = true

static func _apply_twin_linked(config: Dictionary) -> void:
	# Twin-linked: Re-roll all failed wound rolls (10e rules)
	config["modifiers"] = config.get("modifiers", {})
	config.modifiers["reroll_wounds"] = true

static func _apply_hit_modifier(modifier: int, config: Dictionary) -> void:
	# Generic hit roll modifier
	config["modifiers"] = config.get("modifiers", {})
	config.modifiers["hit_modifier"] = config.modifiers.get("hit_modifier", 0) + modifier

static func _apply_devastating_wounds(config: Dictionary) -> void:
	# Devastating Wounds: 6s to wound become mortal wounds
	config["modifiers"] = config.get("modifiers", {})
	config.modifiers["devastating_wounds"] = true

static func _apply_anti_keyword(keyword: String, threshold: int, config: Dictionary) -> void:
	# Anti-[KEYWORD] X+: Lowers the critical wound threshold (e.g., Anti-Infantry 4+ = crits on wound rolls of 4+)
	# This is NOT a re-roll; it makes wound rolls of X+ count as critical wounds vs matching keyword targets.
	config["modifiers"] = config.get("modifiers", {})
	# Store anti-keyword entries so Mathhammer can inject them into weapon special_rules
	if not config.modifiers.has("anti_keyword_entries"):
		config.modifiers["anti_keyword_entries"] = []
	config.modifiers["anti_keyword_entries"].append({
		"keyword": keyword,
		"threshold": threshold,
		"text": "anti-%s %d+" % [keyword.to_lower(), threshold]
	})

static func _apply_wound_modifier(modifier: int, config: Dictionary) -> void:
	# Generic wound roll modifier
	config["modifiers"] = config.get("modifiers", {})
	config.modifiers["wound_modifier"] = config.modifiers.get("wound_modifier", 0) + modifier

static func _apply_ignores_cover(config: Dictionary) -> void:
	# Ignores Cover: Target cannot use cover save
	config["modifiers"] = config.get("modifiers", {})
	config.modifiers["ignores_cover"] = true

static func _apply_cover_bonus(config: Dictionary) -> void:
	# Cover: Target gets cover save bonus
	config["modifiers"] = config.get("modifiers", {})
	config.modifiers["has_cover"] = true

static func _apply_feel_no_pain(threshold: int, config: Dictionary) -> void:
	# Feel No Pain: Ignore wounds on dice roll
	config["modifiers"] = config.get("modifiers", {})
	config.modifiers["feel_no_pain"] = threshold

static func _apply_rapid_fire(config: Dictionary) -> void:
	# Rapid Fire: Double attacks at close range
	config["modifiers"] = config.get("modifiers", {})
	config.modifiers["rapid_fire"] = true

static func _apply_waaagh(config: Dictionary) -> void:
	# Waaagh!: Ork faction ability bonuses
	config["modifiers"] = config.get("modifiers", {})
	config.modifiers["waaagh_active"] = true

static func _apply_conversion(threshold: int, config: Dictionary) -> void:
	# Conversion X+: At 12"+ range, critical hits on X+ instead of only 6
	# Injected into weapon special_rules so RulesEngine picks it up
	config["modifiers"] = config.get("modifiers", {})
	config.modifiers["conversion_threshold"] = threshold

# Get rule definition by ID
static func get_rule_definition(rule_id: String) -> RuleDefinition:
	initialize_rules()
	return RULE_REGISTRY.get(rule_id, null)

# Get all available rules
static func get_all_rules() -> Array:
	initialize_rules()
	return RULE_REGISTRY.values()

# Get rules by category
static func get_rules_by_category(category: RuleCategory) -> Array:
	initialize_rules()
	var filtered_rules = []
	
	for rule in RULE_REGISTRY.values():
		if rule.category == category:
			filtered_rules.append(rule)
	
	return filtered_rules