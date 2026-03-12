shader_type canvas_item;

// Desert wasteland shader — sandy dunes with rocky patches, no texture lookups (WebGL-safe).
// Evokes an arid, sun-baked battlefield.

uniform vec4 base_color : source_color = vec4(0.45, 0.35, 0.20, 1.0);
uniform vec4 light_color : source_color = vec4(0.55, 0.45, 0.28, 1.0);
uniform vec4 dark_color : source_color = vec4(0.30, 0.22, 0.12, 1.0);

uniform float dune_scale : hint_range(5.0, 60.0) = 18.0;
uniform float grain_scale : hint_range(40.0, 300.0) = 150.0;
uniform float color_variation : hint_range(0.0, 0.2) = 0.06;

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
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	// Dune-like large shapes
	float dunes = fbm(UV * dune_scale);

	// Fine sand grain — smooth variation
	float grain = value_noise(UV * grain_scale);

	float pattern = dunes * 0.7 + grain * 0.3;

	vec3 col;
	if (pattern < 0.45) {
		col = mix(dark_color.rgb, base_color.rgb, pattern / 0.45);
	} else {
		col = mix(base_color.rgb, light_color.rgb, (pattern - 0.45) / 0.55);
	}

	// Sand shimmer jitter — smooth variation
	float jitter = (value_noise(UV * 250.0) - 0.5) * color_variation;
	col.r += jitter;
	col.g += jitter * 0.85;
	col.b += jitter * 0.5;

	COLOR = vec4(col, 1.0);
}
