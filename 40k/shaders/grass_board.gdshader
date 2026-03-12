shader_type canvas_item;

// Grass gaming board shader — procedural, no texture lookups (WebGL-safe).
// Designed to look like a flocked / static-grass tabletop mat when viewed
// from a typical top-down game camera distance.

// Tunable uniforms — all have sensible defaults for a 40 K grass mat.
uniform vec4 base_color : source_color = vec4(0.16, 0.38, 0.13, 1.0);
uniform vec4 tip_color  : source_color = vec4(0.28, 0.52, 0.18, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.08, 0.20, 0.06, 1.0);

uniform float blade_density : hint_range(20.0, 400.0) = 120.0;
uniform float color_variation : hint_range(0.0, 0.3) = 0.08;
uniform float clump_scale : hint_range(5.0, 80.0) = 25.0;
uniform float fine_detail : hint_range(40.0, 300.0) = 160.0;

// ---- hash / noise helpers (pure math, no texture lookups) ----

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f); // smoothstep
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractional Brownian Motion — three octaves for natural clumping.
float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		v += amp * value_noise(p);
		p *= 2.17;
		amp *= 0.5;
	}
	return v;
}

// ---- fragment ----

void fragment() {
	// Large-scale clumps — patches of lighter / darker grass.
	float clumps = fbm(UV * clump_scale);

	// Medium blade-level variation — gives the "thousands of blades" feel.
	float blades = value_noise(UV * blade_density);

	// Fine micro-detail — adds grit / grain at very close zoom.
	float micro = hash(floor(UV * fine_detail));

	// Combine layers (weighted toward clumps for realism from afar).
	float pattern = clumps * 0.55 + blades * 0.30 + micro * 0.15;

	// Map pattern to a color ramp: shadow → base → tip.
	vec3 col;
	if (pattern < 0.4) {
		col = mix(shadow_color.rgb, base_color.rgb, pattern / 0.4);
	} else {
		col = mix(base_color.rgb, tip_color.rgb, (pattern - 0.4) / 0.6);
	}

	// Per-pixel hue jitter — prevents the "too uniform" look.
	float jitter = (hash2(UV * 200.0) - 0.5) * color_variation;
	col.r += jitter * 0.6;
	col.g += jitter;
	col.b += jitter * 0.3;

	COLOR = vec4(col, 1.0);
}
