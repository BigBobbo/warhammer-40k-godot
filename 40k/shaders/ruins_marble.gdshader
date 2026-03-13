shader_type canvas_item;

// Ruins marble shader — veined marble for ornate Imperial ruins.
// Procedural, no texture lookups (WebGL-safe).

uniform vec4 base_color : source_color = vec4(0.75, 0.73, 0.70, 1.0);
uniform vec4 vein_color : source_color = vec4(0.35, 0.32, 0.30, 1.0);
uniform vec4 highlight_color : source_color = vec4(0.88, 0.86, 0.82, 1.0);

uniform float vein_scale : hint_range(3.0, 30.0) = 10.0;
uniform float vein_detail : hint_range(20.0, 150.0) = 60.0;
uniform float vein_intensity : hint_range(0.0, 1.0) = 0.5;
uniform float polish : hint_range(0.0, 0.1) = 0.03;

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
	for (int i = 0; i < 4; i++) {
		v += amp * value_noise(p);
		p *= 2.1;
		amp *= 0.45;
	}
	return v;
}

void fragment() {
	// Warped coordinates for marble veining
	vec2 warp = vec2(
		fbm(UV * vein_scale + vec2(0.0, 1.7)),
		fbm(UV * vein_scale + vec2(3.2, 0.0))
	);

	float veins = fbm(UV * vein_scale + warp * 2.0);
	float detail = value_noise(UV * vein_detail);

	// Create vein pattern with sharp transitions
	float vein_mask = smoothstep(0.35, 0.55, veins) * vein_intensity;

	// Base marble color with subtle variation
	float base_pattern = fbm(UV * vein_scale * 0.5);
	vec3 col = mix(base_color.rgb, highlight_color.rgb, base_pattern * 0.4);

	// Apply veins
	col = mix(col, vein_color.rgb, vein_mask);

	// Subtle fine detail
	float micro = (detail - 0.5) * polish;
	col += vec3(micro);

	COLOR = vec4(col, COLOR.a);
}
