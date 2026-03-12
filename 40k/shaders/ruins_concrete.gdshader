shader_type canvas_item;

// Ruins concrete shader — cracked, weathered concrete for ruined buildings.
// Procedural, no texture lookups (WebGL-safe).

uniform vec4 base_color : source_color = vec4(0.42, 0.40, 0.37, 1.0);
uniform vec4 light_color : source_color = vec4(0.55, 0.52, 0.48, 1.0);
uniform vec4 dark_color : source_color = vec4(0.22, 0.20, 0.18, 1.0);
uniform vec4 crack_color : source_color = vec4(0.12, 0.10, 0.08, 1.0);

uniform float slab_scale : hint_range(4.0, 30.0) = 8.0;
uniform float crack_detail : hint_range(30.0, 200.0) = 80.0;
uniform float weathering : hint_range(0.0, 0.15) = 0.07;
uniform float crack_strength : hint_range(0.0, 1.0) = 0.6;

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
	// Large concrete slab pattern
	float slabs = fbm(UV * slab_scale);

	// Fine crack network
	float cracks = value_noise(UV * crack_detail);
	float crack_line = smoothstep(0.48, 0.50, cracks) * crack_strength;

	float pattern = slabs * 0.65 + cracks * 0.35;

	vec3 col;
	if (pattern < 0.4) {
		col = mix(dark_color.rgb, base_color.rgb, pattern / 0.4);
	} else {
		col = mix(base_color.rgb, light_color.rgb, (pattern - 0.4) / 0.6);
	}

	// Apply dark crack lines
	col = mix(col, crack_color.rgb, crack_line);

	// Weathering jitter
	float jitter = (value_noise(UV * 160.0) - 0.5) * weathering;
	col += vec3(jitter);

	// Preserve the vertex color alpha (height-based transparency)
	COLOR = vec4(col, COLOR.a);
}
