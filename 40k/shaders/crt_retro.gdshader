shader_type canvas_item;

// CRT / Retro scanline post-processing shader
// Applied as a full-screen overlay via a ColorRect on a CanvasLayer.
// Toggleable at runtime via modulate alpha or visibility.

uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.18;
uniform float scanline_frequency : hint_range(1.0, 8.0) = 3.0;
uniform float chromatic_aberration : hint_range(0.0, 3.0) = 0.8;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.3;
uniform float brightness_boost : hint_range(0.0, 0.3) = 0.06;
uniform float flicker_speed : hint_range(0.0, 10.0) = 2.0;
uniform float flicker_intensity : hint_range(0.0, 0.05) = 0.01;

void fragment() {
	vec2 uv = SCREEN_UV;

	// --- Chromatic aberration (RGB split) ---
	float ca = chromatic_aberration / 1000.0;
	float r = texture(SCREEN_TEXTURE, uv + vec2(ca, 0.0)).r;
	float g = texture(SCREEN_TEXTURE, uv).g;
	float b = texture(SCREEN_TEXTURE, uv - vec2(ca, 0.0)).b;
	vec3 col = vec3(r, g, b);

	// --- Scanlines ---
	// Use screen pixel coordinates for consistent scanline spacing
	float scan_pos = gl_FragCoord.y * scanline_frequency;
	float scanline = 1.0 - scanline_intensity * (0.5 + 0.5 * sin(scan_pos * PI));

	col *= scanline;

	// --- Subtle phosphor glow between scanlines ---
	float glow = smoothstep(0.4, 0.6, fract(scan_pos * 0.5)) * 0.03;
	col += glow;

	// --- Vignette ---
	vec2 vig_uv = uv * 2.0 - 1.0;
	float vig = 1.0 - dot(vig_uv, vig_uv) * vignette_strength;
	vig = clamp(vig, 0.0, 1.0);
	col *= vig;

	// --- Subtle brightness flicker (simulates CRT power fluctuation) ---
	float flicker = 1.0 + sin(TIME * flicker_speed) * flicker_intensity;
	col *= flicker;

	// --- Brightness boost to compensate for scanline darkening ---
	col += brightness_boost;

	COLOR = vec4(col, 1.0);
}
