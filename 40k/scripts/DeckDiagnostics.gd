extends RefCounted

# DeckDiagnostics — collect runtime environment info into a text file.
#
# Phase 0 / Phase 1 helper. Intended for the very first Steam Deck (or
# unknown-Linux) launch, where the user needs to confirm:
#   - the joypad was detected
#   - the screen mode / resolution actually ended up where we expected
#   - `user://` resolves where we think it does
#   - CloudStorage isn't going to hang us out to dry
#
# Single entry point: DeckDiagnostics.write_report() returns the absolute
# path of the report file.

class_name DeckDiagnostics


static func write_report() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# Warhammer 40K — Deck diagnostics")
	lines.append("timestamp: %s" % Time.get_datetime_string_from_system())
	lines.append("")
	lines.append("## Engine")
	lines.append("godot_version: %s" % Engine.get_version_info().get("string", "?"))
	lines.append("debug_build: %s" % str(OS.is_debug_build()))
	lines.append("")
	lines.append("## Platform")
	lines.append("os_name: %s" % OS.get_name())
	lines.append("distribution: %s" % OS.get_distribution_name())
	lines.append("model: %s" % OS.get_model_name())
	lines.append("processor: %s" % OS.get_processor_name())
	lines.append("processor_count: %d" % OS.get_processor_count())
	lines.append("memory: %d MiB" % (OS.get_static_memory_usage() / (1024 * 1024)))
	lines.append("user_data_dir: %s" % OS.get_user_data_dir())
	lines.append("executable_path: %s" % OS.get_executable_path())
	lines.append("")
	lines.append("## Feature tags")
	for tag in ["editor", "debug", "release", "linux", "windows", "macos",
				"web", "deck", "gamepad", "pc", "mobile", "x86_64"]:
		lines.append("  %s: %s" % [tag, str(OS.has_feature(tag))])
	lines.append("")
	lines.append("## Display")
	lines.append("screen_count: %d" % DisplayServer.get_screen_count())
	lines.append("primary_screen: %d" % DisplayServer.get_primary_screen())
	lines.append("screen_size: %s" % str(DisplayServer.screen_get_size()))
	lines.append("screen_dpi: %d" % DisplayServer.screen_get_dpi())
	lines.append("screen_refresh_rate: %.1f Hz" % DisplayServer.screen_get_refresh_rate())
	lines.append("window_mode: %d" % DisplayServer.window_get_mode())
	lines.append("window_size: %s" % str(DisplayServer.window_get_size()))
	lines.append("viewport_size: %s" % str(Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 0),
		ProjectSettings.get_setting("display/window/size/viewport_height", 0))))
	lines.append("")
	lines.append("## Joypads")
	var pads := Input.get_connected_joypads()
	lines.append("count: %d" % pads.size())
	for dev in pads:
		lines.append("  device %d: name=%s guid=%s" % [
			int(dev),
			Input.get_joy_name(int(dev)),
			Input.get_joy_guid(int(dev))
		])
	lines.append("")
	lines.append("## GamepadInputAdapter")
	var adapter = Engine.get_main_loop().root.get_node_or_null("GamepadInputAdapter")
	if adapter:
		lines.append("enabled: %s" % str(adapter.enabled))
		lines.append("active_device: %s" % str(adapter.active_device))
	else:
		lines.append("(autoload not present)")
	lines.append("")
	lines.append("## CloudStorage")
	var cs = Engine.get_main_loop().root.get_node_or_null("CloudStorage")
	if cs:
		lines.append("base_url: %s" % str(cs.get("base_url")))
		lines.append("offline: %s" % str(cs.get("offline") if cs.has_method("get") else "?"))
	else:
		lines.append("(autoload not present)")
	lines.append("")
	lines.append("## Steam Input")
	# Best-effort: only meaningful if Steamworks is loaded. Phase 4 territory.
	lines.append("steamworks_loaded: %s" % str(Engine.has_singleton("Steam")))
	lines.append("")

	var ts := Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	var rel := "diagnostics_%s.txt" % ts
	var abs_path := ProjectSettings.globalize_path("user://" + rel)
	var f := FileAccess.open("user://" + rel, FileAccess.WRITE)
	if f == null:
		push_warning("DeckDiagnostics: could not open %s for writing" % abs_path)
		return ""
	f.store_string("\n".join(lines))
	f.close()
	print("[DeckDiagnostics] report written: %s" % abs_path)
	return abs_path
