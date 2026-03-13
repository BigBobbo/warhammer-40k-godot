shader_type canvas_item;

// Ruins brick shader — old, weathered brick walls for ruined buildings.
// Procedural, no texture lookups (WebGL-safe).

uniform vec4 brick_color_1 : source_color = vec4(0.55, 0.28, 0.18, 1.0);
uniform vec4 brick_color_2 : source_color = vec4(0.48, 0.22, 0.14, 1.0);
uniform vec4 mortar_color : source_color = vec4(0.60, 0.58, 0.52, 1.0);

uniform float brick_scale_x : hint_range(5.0, 40.0) = 16.0;
uniform float brick_scale_y : hint_range(5.0, 40.0) = 24.0;
uniform float mortar_width : hint_range(0.02, 0.15) = 0.06;
uniform float weathering : hint_range(0.0, 0.15) = 0.08;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	// Brick grid coordinates
	vec2 brick_uv = UV * vec2(brick_scale_x, brick_scale_y);

	// Offset every other row for brick staggering
	float row = floor(brick_uv.y);
	if (mod(row, 2.0) > 0.5) {
		brick_uv.x += 0.5;
	}

	// Fractional position within current brick cell
	vec2 brick_frac = fract(brick_uv);

	// Mortar lines (gap between bricks)
	float mortar_x = smoothstep(0.0, mortar_width, brick_frac.x) * smoothstep(0.0, mortar_width, 1.0 - brick_frac.x);
	float mortar_y = smoothstep(0.0, mortar_width, brick_frac.y) * smoothstep(0.0, mortar_width, 1.0 - brick_frac.y);
	float mortar_mask = 1.0 - mortar_x * mortar_y;

	// Per-brick color variation
	vec2 brick_id = floor(brick_uv);
	float brick_hash = hash(brick_id);
	vec3 brick_col = mix(brick_color_1.rgb, brick_color_2.rgb, brick_hash);

	// Add surface noise within each brick
	float surface_noise = value_noise(UV * 120.0);
	brick_col += (surface_noise - 0.5) * weathering;

	// Darken some bricks for age/damage
	float age = hash(brick_id + vec2(17.3, 91.7));
	if (age > 0.7) {
		brick_col *= 0.75;
	}

	// Combine brick face with mortar
	vec3 col = mix(brick_col, mortar_color.rgb, mortar_mask);

	COLOR = vec4(col, COLOR.a);
}
