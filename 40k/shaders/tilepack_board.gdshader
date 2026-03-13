shader_type canvas_item;

// Tilepack grass board shader — classic top-down game look.
// Uses two tile variants placed in a grid, randomly selecting and
// rotating per cell for natural variety without visible repetition.

uniform sampler2D tile_texture_1 : source_color, filter_linear, repeat_enable;
uniform sampler2D tile_texture_2 : source_color, filter_linear, repeat_enable;

// Number of tiles across the board width. Height tiles are calculated
// automatically to keep tiles square.
uniform float tiles_across : hint_range(4.0, 80.0) = 44.0;

// Overall brightness tweak.
uniform float brightness : hint_range(0.5, 1.5) = 1.0;

// ---- hash helper ----
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Rotate UV 90-degree increments: 0, 1, 2, 3 → 0°, 90°, 180°, 270°.
vec2 rotate_uv(vec2 uv, int steps) {
	if (steps == 1) {
		return vec2(1.0 - uv.y, uv.x);        // 90° CW
	} else if (steps == 2) {
		return vec2(1.0 - uv.x, 1.0 - uv.y);  // 180°
	} else if (steps == 3) {
		return vec2(uv.y, 1.0 - uv.x);         // 270° CW
	}
	return uv;                                   // 0°
}

void fragment() {
	// Work out tile grid coordinates.
	// tiles_across controls how many tiles fit the board width;
	// the aspect ratio of the board determines the vertical count.
	vec2 tile_coord = UV * vec2(tiles_across, tiles_across * (1.0 / TEXTURE_PIXEL_SIZE.x * TEXTURE_PIXEL_SIZE.y));
	vec2 tile_id = floor(tile_coord);
	vec2 local_uv = fract(tile_coord);

	// Per-tile randomness.
	float h = hash(tile_id);

	// Pick rotation (0-3).
	int rotation = int(floor(h * 4.0));
	vec2 rotated_uv = rotate_uv(local_uv, rotation);

	// Pick tile variant using a second hash channel.
	float h2 = hash(tile_id + vec2(7.31, 13.97));
	vec3 col;
	if (h2 < 0.5) {
		col = texture(tile_texture_1, rotated_uv).rgb;
	} else {
		col = texture(tile_texture_2, rotated_uv).rgb;
	}

	col *= brightness;

	COLOR = vec4(col, 1.0);
}
