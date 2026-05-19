extends RefCounted
class_name PixelDiff

# Image pixel-diff utility. Compares two PNGs and reports diff percentages,
# optionally for named regions.
#
# Used by ScenarioRunner's `pixel_diff` step type and by the standalone
# self-test in tests/tools/pixel_diff_unit_test.gd.
#
# A pixel is "different" if any RGBA channel differs by more than
# CHANNEL_THRESHOLD (out of 255). This swallows micro-aliasing while still
# catching genuine rendering changes.

const CHANNEL_THRESHOLD := 6


static func diff(before_path: String, after_path: String, regions: Dictionary = {}) -> Dictionary:
	var before := _load(before_path)
	var after := _load(after_path)
	if before == null:
		return {"error": "could not load before: %s" % before_path}
	if after == null:
		return {"error": "could not load after: %s" % after_path}
	if before.get_size() != after.get_size():
		return {"error": "size mismatch: before=%s after=%s" % [str(before.get_size()), str(after.get_size())]}

	var full_rect := Rect2i(Vector2i.ZERO, before.get_size())
	var total_pct := _diff_pct(before, after, full_rect)

	var region_results := {}
	for name in regions:
		var arr = regions[name]
		if typeof(arr) != TYPE_ARRAY or arr.size() != 4:
			region_results[name] = {"error": "region must be [x,y,w,h]"}
			continue
		var rect := Rect2i(int(arr[0]), int(arr[1]), int(arr[2]), int(arr[3]))
		region_results[name] = _diff_pct(before, after, rect)
	return {"total_diff_pct": total_pct, "regions": region_results}


static func _load(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	var err := img.load(path)
	if err != OK:
		return null
	return img


static func _diff_pct(before: Image, after: Image, rect: Rect2i) -> float:
	var sz := before.get_size()
	var x0: int = max(rect.position.x, 0)
	var y0: int = max(rect.position.y, 0)
	var x1: int = min(rect.position.x + rect.size.x, sz.x)
	var y1: int = min(rect.position.y + rect.size.y, sz.y)
	var total := 0
	var differ := 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			var c1 := before.get_pixel(x, y)
			var c2 := after.get_pixel(x, y)
			total += 1
			var dr: int = abs(int(c1.r8) - int(c2.r8))
			var dg: int = abs(int(c1.g8) - int(c2.g8))
			var db: int = abs(int(c1.b8) - int(c2.b8))
			var da: int = abs(int(c1.a8) - int(c2.a8))
			if dr > CHANNEL_THRESHOLD or dg > CHANNEL_THRESHOLD or db > CHANNEL_THRESHOLD or da > CHANNEL_THRESHOLD:
				differ += 1
	if total == 0:
		return 0.0
	return 100.0 * float(differ) / float(total)
