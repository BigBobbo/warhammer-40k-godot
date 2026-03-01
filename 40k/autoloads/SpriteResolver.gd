extends Node

# Sprite path resolution and texture caching for the hybrid sprite system.
# Scans user://sprites/ directory for PNG files and resolves them by priority:
#   1. Exact unit name: blade_champion.png
#   2. Faction + type: adeptus_custodes_infantry.png
#   3. Generic type: infantry.png, vehicle.png, monster.png
# Uses FileAccess.get_buffer() + Image.load_png_from_buffer() for WebGL safety.
#
# Animated sprite support:
#   Scans user://sprites/animated/ for subdirectories or sprite sheets.
#   Supported formats:
#     A) Individual frame PNGs in a subdirectory:
#        user://sprites/animated/intercessor_squad/idle_0.png, idle_1.png, ...
#     B) Sprite sheet + config JSON:
#        user://sprites/animated/intercessor_squad.png + intercessor_squad.json
#        JSON format: { "frame_width": 64, "frame_height": 64, "animations": {
#          "idle": { "row": 0, "frames": 4, "fps": 4, "loop": true }, ... } }
#   Resolution priority is the same: exact name -> faction+type -> generic type.

var _texture_cache: Dictionary = {}  # path -> Texture2D
var _available_sprites: Dictionary = {}  # lowercase filename (no ext) -> full path
var _sprites_dir: String = "user://sprites/"
var _animated_dir: String = "user://sprites/animated/"
var _initialized: bool = false

# Animated sprite caches
var _animated_dirs: Dictionary = {}       # clean_name -> directory path
var _animated_sheets: Dictionary = {}     # clean_name -> { "sheet": path, "config": path }
var _animation_cache: Dictionary = {}     # cache_key -> Dictionary of animation_name -> SpriteAnimationData


func _ready() -> void:
	_ensure_sprites_directory()
	_ensure_animated_directory()
	_scan_sprites()
	_scan_animated_sprites()
	_initialized = true
	DebugLogger.info("[SpriteResolver] Initialized. Found %d static sprite(s), %d animated set(s)" % [_available_sprites.size(), _animated_dirs.size() + _animated_sheets.size()])


func _ensure_sprites_directory() -> void:
	if not DirAccess.dir_exists_absolute(_sprites_dir):
		var err = DirAccess.make_dir_recursive_absolute(_sprites_dir)
		if err == OK:
			DebugLogger.info("[SpriteResolver] Created sprites directory: %s" % _sprites_dir)
		else:
			DebugLogger.info("[SpriteResolver] WARNING: Failed to create sprites directory: %s (error %d)" % [_sprites_dir, err])


func _ensure_animated_directory() -> void:
	if not DirAccess.dir_exists_absolute(_animated_dir):
		var err = DirAccess.make_dir_recursive_absolute(_animated_dir)
		if err == OK:
			DebugLogger.info("[SpriteResolver] Created animated sprites directory: %s" % _animated_dir)
		else:
			DebugLogger.info("[SpriteResolver] WARNING: Failed to create animated sprites directory: %s (error %d)" % [_animated_dir, err])


func _scan_sprites() -> void:
	_available_sprites.clear()
	var dir = DirAccess.open(_sprites_dir)
	if dir == null:
		DebugLogger.info("[SpriteResolver] Could not open sprites directory: %s" % _sprites_dir)
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.to_lower().ends_with(".png"):
			var base_name = file_name.get_basename().to_lower().replace(" ", "_").replace("-", "_")
			var full_path = _sprites_dir + file_name
			_available_sprites[base_name] = full_path
			DebugLogger.info("[SpriteResolver] Found sprite: %s -> %s" % [base_name, full_path])
		file_name = dir.get_next()
	dir.list_dir_end()


func resolve_sprite(unit_name: String, faction_name: String, unit_type: String) -> Texture2D:
	# Resolution priority chain:
	# 1. Exact unit name
	# 2. Faction + type
	# 3. Generic type

	var clean_unit = _clean_name(unit_name)
	var clean_faction = _clean_name(faction_name)
	var clean_type = _clean_name(unit_type)

	# Priority 1: Exact unit name
	if clean_unit != "" and _available_sprites.has(clean_unit):
		return _load_texture(_available_sprites[clean_unit])

	# Priority 2: Faction + type
	if clean_faction != "" and clean_type != "":
		var faction_type_key = clean_faction + "_" + clean_type
		if _available_sprites.has(faction_type_key):
			return _load_texture(_available_sprites[faction_type_key])

	# Priority 3: Generic type
	if clean_type != "" and _available_sprites.has(clean_type):
		return _load_texture(_available_sprites[clean_type])

	return null


func _load_texture(path: String) -> Texture2D:
	# Check cache first
	if _texture_cache.has(path):
		return _texture_cache[path]

	# Load using WebGL-safe method (avoids load()/preload() on user:// files)
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		DebugLogger.info("[SpriteResolver] WARNING: Could not open file: %s" % path)
		return null

	var buffer = file.get_buffer(file.get_length())
	file.close()

	var image = Image.new()
	var err = image.load_png_from_buffer(buffer)
	if err != OK:
		DebugLogger.info("[SpriteResolver] WARNING: Failed to load PNG from: %s (error %d)" % [path, err])
		return null

	var texture = ImageTexture.create_from_image(image)
	_texture_cache[path] = texture
	DebugLogger.info("[SpriteResolver] Loaded and cached texture: %s" % path)
	return texture


func _clean_name(name: String) -> String:
	return name.to_lower().strip_edges().replace(" ", "_").replace("-", "_")


func rescan() -> void:
	# Public method to force a re-scan of the sprites directory
	_texture_cache.clear()
	_animation_cache.clear()
	_scan_sprites()
	_scan_animated_sprites()
	DebugLogger.info("[SpriteResolver] Rescanned. Found %d static sprite(s), %d animated set(s)" % [_available_sprites.size(), _animated_dirs.size() + _animated_sheets.size()])


func get_sprite_count() -> int:
	return _available_sprites.size()


func get_animated_sprite_count() -> int:
	return _animated_dirs.size() + _animated_sheets.size()


# --- Animated sprite scanning ---

func _scan_animated_sprites() -> void:
	_animated_dirs.clear()
	_animated_sheets.clear()

	var dir = DirAccess.open(_animated_dir)
	if dir == null:
		DebugLogger.info("[SpriteResolver] Could not open animated sprites directory: %s" % _animated_dir)
		return

	dir.list_dir_begin()
	var entry = dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			# Subdirectory with individual frame PNGs
			var clean = _clean_name(entry)
			_animated_dirs[clean] = _animated_dir + entry + "/"
			DebugLogger.info("[SpriteResolver] Found animated sprite dir: %s -> %s" % [clean, _animated_dirs[clean]])
		elif not dir.current_is_dir() and entry.to_lower().ends_with(".png"):
			# Sprite sheet - check for matching JSON config
			var base = entry.get_basename()
			var clean = _clean_name(base)
			var json_path = _animated_dir + base + ".json"
			if FileAccess.file_exists(json_path):
				_animated_sheets[clean] = {
					"sheet": _animated_dir + entry,
					"config": json_path
				}
				DebugLogger.info("[SpriteResolver] Found animated sprite sheet: %s" % clean)
		entry = dir.get_next()
	dir.list_dir_end()


func resolve_animated_sprite(unit_name: String, faction_name: String, unit_type: String) -> Dictionary:
	# Returns a Dictionary of animation_name -> SpriteAnimationData, or empty if none found.
	# Uses the same priority chain as static sprites.
	var clean_unit = _clean_name(unit_name)
	var clean_faction = _clean_name(faction_name)
	var clean_type = _clean_name(unit_type)

	# Priority 1: Exact unit name
	var result = _try_load_animations(clean_unit)
	if not result.is_empty():
		return result

	# Priority 2: Faction + type
	if clean_faction != "" and clean_type != "":
		result = _try_load_animations(clean_faction + "_" + clean_type)
		if not result.is_empty():
			return result

	# Priority 3: Generic type
	if clean_type != "":
		result = _try_load_animations(clean_type)
		if not result.is_empty():
			return result

	return {}


func _try_load_animations(key: String) -> Dictionary:
	# Check cache first
	if _animation_cache.has(key):
		return _animation_cache[key]

	var animations: Dictionary = {}

	# Try subdirectory with individual frame PNGs
	if _animated_dirs.has(key):
		animations = _load_animations_from_dir(_animated_dirs[key])

	# Try sprite sheet + config JSON
	if animations.is_empty() and _animated_sheets.has(key):
		var sheet_info = _animated_sheets[key]
		animations = _load_animations_from_sheet(sheet_info["sheet"], sheet_info["config"])

	if not animations.is_empty():
		_animation_cache[key] = animations

	return animations


func _load_animations_from_dir(dir_path: String) -> Dictionary:
	# Scans a directory for frame PNGs named: <animation>_<frame_number>.png
	# e.g. idle_0.png, idle_1.png, move_0.png, move_1.png
	var animations: Dictionary = {}
	var frame_map: Dictionary = {}  # animation_name -> Array of { "index": int, "path": String }

	var dir = DirAccess.open(dir_path)
	if dir == null:
		DebugLogger.info("[SpriteResolver] WARNING: Could not open animated dir: %s" % dir_path)
		return animations

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.to_lower().ends_with(".png"):
			var base = file_name.get_basename().to_lower()
			# Parse animation name and frame index from filename
			var last_underscore = base.rfind("_")
			if last_underscore > 0:
				var anim_name = base.substr(0, last_underscore)
				var frame_str = base.substr(last_underscore + 1)
				if frame_str.is_valid_int():
					var frame_idx = frame_str.to_int()
					if not frame_map.has(anim_name):
						frame_map[anim_name] = []
					frame_map[anim_name].append({
						"index": frame_idx,
						"path": dir_path + file_name
					})
		file_name = dir.get_next()
	dir.list_dir_end()

	# Check for a config.json in the directory for fps/loop overrides
	var config = _load_anim_config(dir_path + "config.json")

	# Build SpriteAnimationData for each animation
	for anim_name in frame_map.keys():
		var frame_entries = frame_map[anim_name]
		# Sort by frame index
		frame_entries.sort_custom(func(a, b): return a["index"] < b["index"])

		var textures: Array[Texture2D] = []
		for entry in frame_entries:
			var tex = _load_texture(entry["path"])
			if tex:
				textures.append(tex)

		if textures.size() > 0:
			var fps = 4.0
			var loop = true
			# Apply config overrides if available
			if config.has("animations") and config["animations"].has(anim_name):
				var anim_config = config["animations"][anim_name]
				fps = anim_config.get("fps", 4.0)
				loop = anim_config.get("loop", anim_name == "idle" or anim_name == "move")
			else:
				# Default settings per animation type
				match anim_name:
					"idle": fps = 4.0; loop = true
					"move": fps = 8.0; loop = true
					"attack": fps = 10.0; loop = false
					"death": fps = 6.0; loop = false
					_: fps = 4.0; loop = true

			var anim_data = SpriteAnimationData.new(anim_name, textures, fps, loop)
			animations[anim_name] = anim_data
			DebugLogger.info("[SpriteResolver] Loaded animation '%s' with %d frames at %d fps" % [anim_name, textures.size(), int(fps)])

	return animations


func _load_animations_from_sheet(sheet_path: String, config_path: String) -> Dictionary:
	# Loads animations from a sprite sheet using a JSON config that specifies
	# frame dimensions and row-based animation layout.
	var animations: Dictionary = {}

	var config = _load_anim_config(config_path)
	if config.is_empty():
		DebugLogger.info("[SpriteResolver] WARNING: Empty or invalid config for sheet: %s" % config_path)
		return animations

	var frame_width = int(config.get("frame_width", 64))
	var frame_height = int(config.get("frame_height", 64))
	var anim_defs = config.get("animations", {})

	if anim_defs.is_empty():
		DebugLogger.info("[SpriteResolver] WARNING: No animations defined in config: %s" % config_path)
		return animations

	# Load the full sheet image
	var sheet_texture = _load_texture(sheet_path)
	if sheet_texture == null:
		return animations

	var sheet_image = sheet_texture.get_image()
	if sheet_image == null:
		DebugLogger.info("[SpriteResolver] WARNING: Could not get image from sheet texture: %s" % sheet_path)
		return animations

	# Extract frames for each animation
	for anim_name in anim_defs.keys():
		var anim_def = anim_defs[anim_name]
		var row = int(anim_def.get("row", 0))
		var frame_count = int(anim_def.get("frames", 1))
		var fps = float(anim_def.get("fps", 4.0))
		var loop = bool(anim_def.get("loop", anim_name == "idle" or anim_name == "move"))

		var textures: Array[Texture2D] = []
		for i in range(frame_count):
			var src_rect = Rect2i(i * frame_width, row * frame_height, frame_width, frame_height)
			# Bounds check
			if src_rect.position.x + src_rect.size.x > sheet_image.get_width():
				break
			if src_rect.position.y + src_rect.size.y > sheet_image.get_height():
				break

			var frame_image = sheet_image.get_region(src_rect)
			var frame_texture = ImageTexture.create_from_image(frame_image)
			textures.append(frame_texture)

		if textures.size() > 0:
			var anim_data = SpriteAnimationData.new(anim_name, textures, fps, loop)
			animations[anim_name] = anim_data
			DebugLogger.info("[SpriteResolver] Loaded sheet animation '%s' with %d frames at %d fps" % [anim_name, textures.size(), int(fps)])

	return animations


func _load_anim_config(config_path: String) -> Dictionary:
	# Loads a JSON config file for animation parameters
	if not FileAccess.file_exists(config_path):
		return {}

	var file = FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		return {}

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var err = json.parse(json_text)
	if err != OK:
		DebugLogger.info("[SpriteResolver] WARNING: Failed to parse animation config: %s (error: %s)" % [config_path, json.get_error_message()])
		return {}

	var result = json.get_data()
	if result is Dictionary:
		return result
	return {}
