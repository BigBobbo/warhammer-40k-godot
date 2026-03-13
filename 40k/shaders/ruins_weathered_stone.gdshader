shader_type canvas_item;

// Weathered stone shader — ancient, moss-touched stone blocks for ruins.
// Procedural, no texture lookups (WebGL-safe).

uniform vec4 stone_base : source_color = vec4(0.38, 0.36, 0.32, 1.0);
uniform vec4 stone_light : source_color = vec4(0.50, 0.48, 0.42, 1.0);
uniform vec4 moss_color : source_color = vec4(0.20, 0.32, 0.15, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.15, 0.14, 0.12, 1.0);

uniform float block_scale : hint_range(3.0, 25.0) = 7.0;
uniform float moss_amount : hint_range(0.0, 1.0) = 0.35;
uniform float erosion : hint_range(0.0, 0.12) = 0.06;

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

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		v += amp * value_noise(p);
		p *= 2.3;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	// Stone block pattern — irregular blocks
	float blocks = fbm(UV * block_scale);
	float detail = value_noise(UV * block_scale * 8.0);

	// Base stone color with block variation
	vec3 col;
	float pattern = blocks * 0.7 + detail * 0.3;
	if (pattern < 0.35) {
		col = mix(shadow_color.rgb, stone_base.rgb, pattern / 0.35);
	} else {
		col = mix(stone_base.rgb, stone_light.rgb, (pattern - 0.35) / 0.65);
	}

	// Moss growth in crevices and shaded areas
	float moss_pattern = fbm(UV * block_scale * 1.5 + vec2(5.7, 2.3));
	float moss_mask = smoothstep(0.45, 0.65, moss_pattern) * moss_amount;
	// Moss prefers darker areas
	moss_mask *= smoothstep(0.6, 0.3, pattern);
	col = mix(col, moss_color.rgb, moss_mask);

	// Erosion — subtle pitting and wear
	float erosion_noise = (value_noise(UV * 140.0) - 0.5) * erosion;
	col += vec3(erosion_noise);

	COLOR = vec4(col, COLOR.a);
}
