shader_type canvas_item;

// Green felt gaming table shader - hash-based noise, no texture lookups (WebGL-safe)
uniform vec4 base_color : source_color = vec4(0.15, 0.35, 0.12, 1.0);
uniform float noise_strength : hint_range(0.0, 0.2) = 0.04;
uniform float noise_scale : hint_range(1.0, 200.0) = 80.0;

// Hash-based pseudo-random noise (no texture lookups)
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f); // Smoothstep

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 uv = UV * noise_scale;

	// Layer two noise octaves for subtle felt texture
	float n = noise(uv) * 0.6 + noise(uv * 2.3) * 0.4;

	// Apply noise as subtle color variation around the base green
	vec3 felt = base_color.rgb + (n - 0.5) * noise_strength;

	COLOR = vec4(felt, base_color.a);
}
