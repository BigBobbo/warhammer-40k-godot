shader_type canvas_item;

// Shader for model highlights during wound allocation
// Supports pulsing animation and color variations

uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 0.5);
uniform bool pulse = false;
uniform float pulse_speed = 2.0;
uniform float pulse_min_alpha = 0.3;
uniform float pulse_max_alpha = 0.8;

void fragment() {
	// Get base texture color
	vec4 tex = texture(TEXTURE, UV);

	// Apply base color tint
	vec4 final_color = tex * base_color;

	// Apply pulsing effect if enabled
	if (pulse) {
		float pulse_factor = sin(TIME * pulse_speed) * 0.5 + 0.5;  // Oscillates 0-1
		float alpha = mix(pulse_min_alpha, pulse_max_alpha, pulse_factor);
		final_color.a = alpha;
	}

	COLOR = final_color;
}
