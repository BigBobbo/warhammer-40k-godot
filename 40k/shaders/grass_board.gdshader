shader_type canvas_item;

// Pixelated grass board shader — 16-bit / retro RTS style.
// Inspired by classic top-down games (Zelda, Command & Conquer, Z).
// Uses tile-based patterns with a limited palette for that authentic
// pixel-art look. Procedural, no texture lookups (WebGL-safe).

// ---- Palette colors (classic 16-bit grass) ----
uniform vec4 color_dark    : source_color = vec4(0.09, 0.18, 0.05, 1.0);  // deep shadow
uniform vec4 color_base    : source_color = vec4(0.15, 0.30, 0.08, 1.0);  // main grass
uniform vec4 color_mid     : source_color = vec4(0.22, 0.42, 0.12, 1.0);  // medium highlight
uniform vec4 color_light   : source_color = vec4(0.30, 0.52, 0.15, 1.0);  // light tuft tips
uniform vec4 color_bright  : source_color = vec4(0.40, 0.60, 0.18, 1.0);  // brightest accent
uniform vec4 color_dirt    : source_color = vec4(0.22, 0.16, 0.08, 1.0);  // dirt patches

// ---- Controls ----
uniform float pixel_size : hint_range(2.0, 12.0) = 4.0;          // size of each "pixel" in screen pixels
uniform float tile_size  : hint_range(8.0, 64.0) = 24.0;         // size of each grass tile in pixels
uniform float tuft_density : hint_range(0.1, 0.8) = 0.40;        // how many grass tufts per tile
uniform float dirt_amount  : hint_range(0.0, 0.3) = 0.08;        // chance of dirt patches
uniform float pattern_variety : hint_range(1.0, 8.0) = 5.0;      // number of tile pattern variations

// ---- Hash helpers ----

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash2(vec2 p) {
	return vec2(hash(p), hash(p + vec2(127.1, 311.7)));
}

// Integer hash for tile pattern selection
float ihash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// ---- Tile pattern generators ----
// Each returns a palette index (0-4) for the pixel within a tile.

// Pattern 0: Dense clumpy grass — clusters of lighter tufts on dark base
float pattern_clumpy(vec2 local, vec2 tile_id) {
	float base_val = 1.0; // color_base by default

	// Place 3-5 tuft clusters using tile hash as seed
	for (float i = 0.0; i < 5.0; i++) {
		vec2 center = hash2(tile_id + vec2(i * 7.3, i * 13.1));
		float radius = 0.15 + hash(tile_id + vec2(i * 3.7, 0.0)) * 0.20;
		float dist = length(local - center);
		if (dist < radius) {
			// Inner part is brighter
			if (dist < radius * 0.4) {
				base_val = 3.0; // light
			} else {
				base_val = 2.0; // mid
			}
		}
	}

	// Scattered individual bright pixels (grass blade tips)
	float blade_h = hash(local * 47.0 + tile_id);
	if (blade_h > (1.0 - tuft_density * 0.3)) {
		base_val = max(base_val, 3.0);
	}

	// Dark shadow pixels at bottom-right of clumps
	float shadow_h = hash(local * 31.0 + tile_id + vec2(0.02, 0.02));
	if (shadow_h > 0.92 && base_val <= 1.0) {
		base_val = 0.0;
	}

	return base_val;
}

// Pattern 1: Striped grass — horizontal-ish bands of color
float pattern_striped(vec2 local, vec2 tile_id) {
	float band = floor(local.y * 6.0);
	float band_hash = hash(vec2(band, tile_id.x + tile_id.y));

	float val = 1.0;
	if (band_hash < 0.3) {
		val = 0.0; // dark band
	} else if (band_hash < 0.5) {
		val = 2.0; // mid band
	}

	// Add scattered highlights
	float h = hash(local * 39.0 + tile_id);
	if (h > 0.85) {
		val = 3.0;
	}

	return val;
}

// Pattern 2: Sparse tufts — mostly base with a few distinct grass clumps
float pattern_sparse(vec2 local, vec2 tile_id) {
	float val = 1.0;

	// Just 2 tufts
	for (float i = 0.0; i < 2.0; i++) {
		vec2 center = hash2(tile_id + vec2(i * 11.3, i * 5.7));
		float dist = length(local - center);
		if (dist < 0.18) {
			val = dist < 0.08 ? 4.0 : 3.0;
		}
	}

	// Subtle variation in base
	float h = hash(local * 23.0 + tile_id);
	if (h > 0.88 && val <= 1.0) {
		val = 2.0;
	}
	if (h < 0.08) {
		val = 0.0;
	}

	return val;
}

// Pattern 3: Dense meadow — lots of mid-tones, lush look
float pattern_meadow(vec2 local, vec2 tile_id) {
	float val = 2.0; // start with mid-tone

	float h1 = hash(local * 33.0 + tile_id);
	float h2 = hash(local * 51.0 + tile_id + vec2(5.0, 3.0));

	if (h1 < 0.25) val = 1.0;       // base patches
	if (h1 > 0.8)  val = 3.0;       // light tips
	if (h2 > 0.93) val = 4.0;       // bright accents
	if (h1 < 0.08) val = 0.0;       // shadow spots

	// Larger feature: a diagonal lighter strip
	float diag = local.x + local.y;
	if (fract(diag * 3.0 + hash(tile_id) * 2.0) < 0.3) {
		val = max(val, 2.0);
	}

	return val;
}

// Pattern 4: Patchy — irregular patches of different tones (C&C style)
float pattern_patchy(vec2 local, vec2 tile_id) {
	// Use low-frequency hash to create larger patches
	vec2 coarse = floor(local * 3.0) / 3.0;
	float patch = hash(coarse + tile_id);

	float val;
	if (patch < 0.25) {
		val = 0.0;
	} else if (patch < 0.50) {
		val = 1.0;
	} else if (patch < 0.75) {
		val = 2.0;
	} else {
		val = 3.0;
	}

	// Per-pixel jitter within patches
	float fine = hash(local * 41.0 + tile_id);
	if (fine > 0.9) {
		val = min(val + 1.0, 4.0);
	}

	return val;
}

// ---- Fragment ----

void fragment() {
	vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;

	// Snap to pixel grid — this creates the chunky pixelated look
	vec2 uv_pixels = UV * screen_size;
	vec2 snapped = floor(uv_pixels / pixel_size) * pixel_size;
	vec2 uv_snapped = snapped / screen_size;

	// Determine which tile this pixel belongs to
	vec2 tile_px = floor(snapped / tile_size);
	vec2 local = fract(snapped / tile_size); // position within tile [0,1)

	// Select pattern for this tile based on hash
	float tile_h = ihash(tile_px);
	int pattern_id = int(floor(tile_h * pattern_variety));

	// Get palette index from selected pattern
	float palette_idx;
	// Use modular pattern selection
	int p = pattern_id % 5;
	if (p == 0) {
		palette_idx = pattern_clumpy(local, tile_px);
	} else if (p == 1) {
		palette_idx = pattern_striped(local, tile_px);
	} else if (p == 2) {
		palette_idx = pattern_sparse(local, tile_px);
	} else if (p == 3) {
		palette_idx = pattern_meadow(local, tile_px);
	} else {
		palette_idx = pattern_patchy(local, tile_px);
	}

	// Tile-level brightness variation — some tiles are slightly darker/lighter
	float tile_brightness = 0.9 + tile_h * 0.2; // range 0.9 to 1.1

	// Dirt patches: some tiles are partially or fully dirt
	float dirt_h = hash(tile_px + vec2(999.0, 777.0));
	bool is_dirt = dirt_h < dirt_amount;

	// Sub-tile dirt: occasional dirt pixels within grass tiles
	float sub_dirt = hash(snapped * 0.1 + vec2(333.0, 555.0));
	bool is_sub_dirt = sub_dirt < dirt_amount * 0.5 && !is_dirt;

	// Map palette index to actual color
	vec3 col;
	if (is_dirt) {
		// Full dirt tile with slight variation
		float dirt_var = hash(snapped * 0.07 + tile_px);
		col = color_dirt.rgb * (0.85 + dirt_var * 0.3);
		// Some grass poking through dirt
		if (hash(local * 29.0 + tile_px) > 0.75) {
			col = mix(col, color_dark.rgb, 0.5);
		}
	} else if (is_sub_dirt) {
		col = color_dirt.rgb * (0.9 + sub_dirt * 0.2);
	} else {
		// Grass palette lookup
		if (palette_idx <= 0.5) {
			col = color_dark.rgb;
		} else if (palette_idx <= 1.5) {
			col = color_base.rgb;
		} else if (palette_idx <= 2.5) {
			col = color_mid.rgb;
		} else if (palette_idx <= 3.5) {
			col = color_light.rgb;
		} else {
			col = color_bright.rgb;
		}
		col *= tile_brightness;
	}

	// Subtle tile edge darkening — hints at the tile grid without being obvious
	float edge_x = min(local.x, 1.0 - local.x);
	float edge_y = min(local.y, 1.0 - local.y);
	float edge = min(edge_x, edge_y);
	// Only darken right at the edge (1 pixel worth in tile-local space)
	float edge_threshold = 1.0 / tile_size;
	if (edge < edge_threshold) {
		col *= 0.88;
	}

	COLOR = vec4(col, 1.0);
}
