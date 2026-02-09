extends Node

# Sprite path resolution and texture caching for the hybrid sprite system.
# Scans user://sprites/ directory for PNG files and resolves them by priority:
#   1. Exact unit name: blade_champion.png
#   2. Faction + type: adeptus_custodes_infantry.png
#   3. Generic type: infantry.png, vehicle.png, monster.png
# Uses FileAccess.get_buffer() + Image.load_png_from_buffer() for WebGL safety.

var _texture_cache: Dictionary = {}  # path -> Texture2D
var _available_sprites: Dictionary = {}  # lowercase filename (no ext) -> full path
var _sprites_dir: String = "user://sprites/"
var _initialized: bool = false


func _ready() -> void:
	_ensure_sprites_directory()
	_scan_sprites()
	_initialized = true
	DebugLogger.info("[SpriteResolver] Initialized. Found %d sprite(s) in %s" % [_available_sprites.size(), _sprites_dir])


func _ensure_sprites_directory() -> void:
	if not DirAccess.dir_exists_absolute(_sprites_dir):
		var err = DirAccess.make_dir_recursive_absolute(_sprites_dir)
		if err == OK:
			DebugLogger.info("[SpriteResolver] Created sprites directory: %s" % _sprites_dir)
		else:
			DebugLogger.info("[SpriteResolver] WARNING: Failed to create sprites directory: %s (error %d)" % [_sprites_dir, err])


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
	_scan_sprites()
	DebugLogger.info("[SpriteResolver] Rescanned. Found %d sprite(s)" % _available_sprites.size())


func get_sprite_count() -> int:
	return _available_sprites.size()
