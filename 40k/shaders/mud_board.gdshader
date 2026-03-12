shader_type canvas_item;

// Muddy battlefield shader — dark brown churned earth, no texture lookups (WebGL-safe).
// Designed to look like a war-torn muddy field.

uniform vec4 base_color : source_color = vec4(0.18, 0.13, 0.08, 1.0);
uniform vec4 light_color : source_color = vec4(0.28, 0.20, 0.12, 1.0);
uniform vec4 dark_color : source_color = vec4(0.08, 0.06, 0.04, 1.0);

uniform float detail_scale : hint_range(20.0, 300.0) = 80.0;
uniform float roughness : hint_range(0.0, 0.3) = 0.10;
uniform float crack_scale : hint_range(5.0, 60.0) = 20.0;

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
	for (int i = 0; i < 4; i++) {
		v += amp * value_noise(p);
		p *= 2.13;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	// Large-scale terrain variation
	float terrain = fbm(UV * crack_scale);

	// Fine mud detail
	float detail = value_noise(UV * detail_scale);

	// Combined pattern
	float pattern = terrain * 0.6 + detail * 0.4;

	// Map to color ramp: dark → base → light
	vec3 col;
	if (pattern < 0.4) {
		col = mix(dark_color.rgb, base_color.rgb, pattern / 0.4);
	} else {
		col = mix(base_color.rgb, light_color.rgb, (pattern - 0.4) / 0.6);
	}

	// Roughness jitter — smooth variation
	float jitter = (value_noise(UV * 200.0) - 0.5) * roughness;
	col += vec3(jitter * 0.8, jitter * 0.7, jitter * 0.5);

	COLOR = vec4(col, 1.0);
}
