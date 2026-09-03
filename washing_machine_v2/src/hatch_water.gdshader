shader_type canvas_item;
render_mode blend_mix;

uniform float fill_level : hint_range(0.0, 1.0) = 0.0;
uniform float wave_amplitude = 0.015;
uniform float wave_frequency = 11.0;
uniform float wave_speed = 1.0;
uniform bool debug_magenta = false;
uniform bool debug_exaggerated = false;

uniform vec4 water_top : source_color = vec4(0.56, 0.86, 0.94, 0.42);
uniform vec4 water_bottom : source_color = vec4(0.34, 0.70, 0.86, 0.62);

void fragment() {
	if (debug_magenta) {
		COLOR = vec4(1.0, 0.0, 1.0, 0.85);
	} else if (debug_exaggerated) {
		float y = UV.y;

		if (y < 0.25) {
			COLOR = vec4(1.0, 0.0, 0.0, 0.9);
		} else if (y < 0.5) {
			COLOR = vec4(1.0, 1.0, 0.0, 0.9);
		} else if (y < 0.75) {
			COLOR = vec4(0.0, 1.0, 1.0, 0.9);
		} else {
			COLOR = vec4(0.0, 0.0, 1.0, 0.9);
		}
	} else {
		float level = clamp(fill_level, 0.0, 1.0);

		if (level <= 0.001) {
			COLOR = vec4(0.0);
		} else {
			float wave = sin(UV.x * wave_frequency + TIME * wave_speed) * wave_amplitude;
			float surface = 1.0 - level + wave;
			float surface_softness = 0.025;
			float water_mask = smoothstep(
				surface - surface_softness,
				surface + surface_softness,
				UV.y
			);

			vec4 water = mix(water_top, water_bottom, clamp(UV.y, 0.0, 1.0));
			water.a *= water_mask;

			float surface_line = 1.0 - smoothstep(0.0, 0.018, abs(UV.y - surface));
			water.rgb = mix(water.rgb, vec3(0.88, 0.98, 1.0), surface_line * 0.45);
			water.a = max(water.a, surface_line * 0.32);

			COLOR = water;
		}
	}
}
