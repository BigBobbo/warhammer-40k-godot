shader_type canvas_item;

// Stone / urban ruins shader — cracked grey stone slabs, no texture lookups (WebGL-safe).
// Evokes a ruined cityscape or flagstone battlefield.

uniform vec4 base_color : source_color = vec4(0.25, 0.24, 0.22, 1.0);
uniform vec4 light_color : source_color = vec4(0.35, 0.33, 0.30, 1.0);
uniform vec4 dark_color : source_color = vec4(0.12, 0.11, 0.10, 1.0);

uniform float slab_scale : hint_range(5.0, 40.0) = 12.0;
uniform float crack_detail : hint_range(40.0, 200.0) = 100.0;
uniform float weathering : hint_range(0.0, 0.15) = 0.05;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0); // quintic smoothstep
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
	// Large slab variation
	float slabs = fbm(UV * slab_scale);

	// Crack-like fine detail
	float cracks = value_noise(UV * crack_detail);

	float pattern = slabs * 0.6 + cracks * 0.4;

	vec3 col;
	if (pattern < 0.4) {
		col = mix(dark_color.rgb, base_color.rgb, pattern / 0.4);
	} else {
		col = mix(base_color.rgb, light_color.rgb, (pattern - 0.4) / 0.6);
	}

	// Weathering jitter — subtle grey variation
	float jitter = (value_noise(UV * 180.0) - 0.5) * weathering;
	col += vec3(jitter);

	COLOR = vec4(col, 1.0);
}
