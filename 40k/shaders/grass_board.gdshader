shader_type canvas_item;

// Texture-based grass board shader — tiles a PBR grass texture across the board.
// Uses the base color texture with optional normal mapping for subtle depth.

uniform sampler2D grass_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap, repeat_enable;

// How many times the texture tiles across the board (higher = smaller tiles).
uniform float tile_scale : hint_range(2.0, 60.0) = 20.0;

// Subtle color variation to break up tiling repetition.
uniform float color_variation : hint_range(0.0, 0.15) = 0.04;

// Overall brightness adjustment.
uniform float brightness : hint_range(0.5, 1.5) = 1.0;

// ---- hash helper for variation ----
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 tiled_uv = UV * tile_scale;

	// Sample the tiled grass texture.
	vec3 col = texture(grass_texture, tiled_uv).rgb;

	// Low-frequency color variation to break up tiling repetition.
	float variation = (value_noise(UV * 5.0) - 0.5) * color_variation;
	col.r += variation * 0.7;
	col.g += variation;
	col.b += variation * 0.4;

	// Apply brightness.
	col *= brightness;

	COLOR = vec4(col, 1.0);

	// Apply normal map for subtle depth (works with Godot 2D lighting).
	NORMAL_MAP = texture(grass_normal, tiled_uv).rgb;
}
