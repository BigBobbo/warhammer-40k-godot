shader_type canvas_item;

// Grass gaming mat shader - procedural top-down grass texture for tabletop wargaming
// Creates a natural-looking ground surface with fine grass-like detail at miniature scale

uniform vec4 base_color : source_color = vec4(0.18, 0.38, 0.14, 1.0);
uniform vec4 highlight_color : source_color = vec4(0.28, 0.50, 0.18, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.10, 0.22, 0.08, 1.0);
uniform vec4 earth_color : source_color = vec4(0.25, 0.20, 0.12, 1.0);
uniform float noise_scale : hint_range(10.0, 500.0) = 200.0;
uniform float detail_intensity : hint_range(0.0, 1.0) = 0.55;
uniform float earth_amount : hint_range(0.0, 0.3) = 0.06;
uniform float clump_scale : hint_range(5.0, 100.0) = 40.0;

// Hash-based pseudo-random noise (no texture lookups, WebGL-safe)
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractal Brownian Motion - layered noise for natural-looking patterns
float fbm(vec2 p, int octaves) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;

	for (int i = 0; i < octaves; i++) {
		value += amplitude * noise(p * frequency);
		frequency *= 2.17;
		amplitude *= 0.48;
	}
	return value;
}

// Directional noise to simulate grass blade orientation
float grass_directional(vec2 p) {
	// Stretch noise in a direction to create subtle grass-like streaks
	vec2 stretched = p * vec2(1.0, 2.8);
	float n1 = noise(stretched);

	// Second layer at a slightly different angle
	float angle = 0.4;
	vec2 rotated = vec2(
		p.x * cos(angle) - p.y * sin(angle),
		p.x * sin(angle) + p.y * cos(angle)
	) * vec2(1.0, 2.5);
	float n2 = noise(rotated);

	return mix(n1, n2, 0.5);
}

void fragment() {
	vec2 uv = UV * noise_scale;

	// Large-scale color variation (grass clumps / patches)
	float clumps = fbm(UV * clump_scale, 4);

	// Medium-scale detail (individual tuft clusters)
	float medium = fbm(uv * 0.5, 3);

	// Fine grass-like directional detail
	float fine = grass_directional(uv);

	// Very fine grain for micro-texture
	float micro = noise(uv * 3.0) * 0.5 + noise(uv * 5.7) * 0.3 + noise(uv * 11.0) * 0.2;

	// Combine scales for final intensity
	float combined = clumps * 0.35 + medium * 0.30 + fine * 0.20 + micro * 0.15;

	// Earth/bare patches - sparse small spots where ground shows through
	float earth_noise = fbm(UV * clump_scale * 1.7 + vec2(42.0, 17.0), 3);
	float earth_mask = smoothstep(1.0 - earth_amount, 1.0 - earth_amount * 0.3, earth_noise);

	// Build grass color by blending between shadow and highlight based on noise
	vec3 grass = mix(shadow_color.rgb, base_color.rgb, smoothstep(0.25, 0.55, combined));
	grass = mix(grass, highlight_color.rgb, smoothstep(0.55, 0.80, combined) * detail_intensity);

	// Add subtle warm/cool variation
	float warmth = noise(UV * clump_scale * 0.6 + vec2(100.0, 200.0));
	grass += (warmth - 0.5) * vec3(0.02, -0.01, -0.02);

	// Blend in earth patches
	vec3 final_color = mix(grass, earth_color.rgb, earth_mask * 0.6);

	// Subtle brightness variation to break up uniformity
	float brightness = 1.0 + (fbm(UV * clump_scale * 0.3 + vec2(7.0, 13.0), 2) - 0.5) * 0.08;
	final_color *= brightness;

	COLOR = vec4(final_color, base_color.a);
}
