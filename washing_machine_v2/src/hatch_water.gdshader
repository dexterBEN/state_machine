shader_type canvas_item;
render_mode blend_mix;

uniform float fill_level : hint_range(0.0, 1.0) = 0.0;
uniform float wave_amplitude = 0.015;
uniform float wave_frequency = 11.0;
uniform float wave_speed = 1.0;
// Driven by the hatch's interpolated visual amount, including the fade after WASH.
uniform float foam_amount : hint_range(0.0, 1.0) = 0.0;
// Continuous visual rotation, independent of the drum reversal.
uniform float swirl_angle = 0.0;
uniform float swirl_twist : hint_range(0.0, 8.0) = 5.0;
uniform vec4 foam_color : source_color = vec4(0.97, 0.985, 1.0, 0.90);
uniform bool debug_magenta = false;
uniform bool debug_exaggerated = false;

uniform vec4 water_top : source_color = vec4(0.56, 0.86, 0.94, 0.42);
uniform vec4 water_bottom : source_color = vec4(0.34, 0.70, 0.86, 0.62);

// A full water surface seen along the vortex axis, behind the fixed glass.
vec4 vortex_water(vec2 uv, float foam_strength) {
	vec2 offset = uv - vec2(0.5);
	float radius = length(offset) * 2.0;
	float angle = atan(offset.y, offset.x + 0.00001);
	float phase = angle - swirl_angle - swirl_twist * radius;

	// Two broad spiral currents, with a slightly darker (not empty) center.
	vec3 liquid = mix(water_bottom.rgb, water_top.rgb, smoothstep(0.0, 0.85, radius));
	liquid = mix(liquid, foam_color.rgb, 0.14 + 0.07 * cos(phase * 2.0));
	liquid *= mix(0.92, 1.0, smoothstep(0.0, 0.24, radius));
	float liquid_alpha = 0.76;

	// Approximate distance normal to a spiral arm to keep its width readable.
	float arm_distance = abs(sin(phase)) * radius * 0.5
		/ sqrt(1.0 + swirl_twist * swirl_twist * radius * radius);
	float arm_width = 0.015 + 0.003 * sin(radius * 65.0);
	float foam_mask = 1.0 - smoothstep(arm_width, arm_width + 0.006, arm_distance);

	// Overlapping round lobes soften the two ribbons into bubbly foam.
	for (int i = 0; i < 64; i++) {
		float seed = float(i);
		float along = floor(seed * 0.5) / 31.0;
		float bubble_radius = mix(0.12, 0.95, along);
		float bubble_angle = swirl_angle + swirl_twist * bubble_radius + mod(seed, 2.0) * 3.14159265;
		vec2 center = vec2(0.5) + vec2(cos(bubble_angle), sin(bubble_angle)) * bubble_radius * 0.5;
		float size = 0.016 + 0.007 * (0.5 + 0.5 * sin(seed * 2.7));
		float lobe = 1.0 - smoothstep(size - 0.003, size + 0.003, length(uv - center));
		foam_mask = max(foam_mask, lobe);
	}
	foam_mask *= smoothstep(0.055, 0.17, radius) * (1.0 - smoothstep(0.92, 1.0, radius));
	float foam_alpha = foam_mask * foam_color.a * foam_strength;
	float alpha = foam_alpha + liquid_alpha * (1.0 - foam_alpha);
	vec3 color = (foam_color.rgb * foam_alpha + liquid * liquid_alpha * (1.0 - foam_alpha)) / alpha;
	return vec4(color, alpha);
}

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
			// Keep the original horizontal water surface outside WASH.
			float foam_strength = smoothstep(0.0, 0.4, foam_amount);
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

			if (foam_strength > 0.001) {
				float depth = UV.y - surface;
				// A continuous base joins the rounded lobes into a surface raft.
				float foam_mask = smoothstep(-0.012, 0.003, depth)
					* (1.0 - smoothstep(0.025, 0.055, depth));
				for (int i = 0; i < 16; i++) {
					float seed = float(i);
					float center_x = (seed + 0.5) / 16.0
						+ sin(TIME * 0.55 + seed * 2.4) * 0.008;
					float center_y = 1.0 - level
						+ sin(center_x * wave_frequency + TIME * wave_speed) * wave_amplitude;
					float radius = 0.030 + 0.010 * (0.5 + 0.5 * sin(seed * 2.7 + TIME * 0.7));
					float distance_to_lobe = length(UV - vec2(center_x, center_y));
					float lobe = 1.0 - smoothstep(radius - 0.004, radius + 0.004, distance_to_lobe);
					foam_mask = max(foam_mask, lobe);
				}

				// Lightly cloud the submerged water; preserve its blue tint.
				water.rgb = mix(water.rgb, foam_color.rgb, foam_strength * 0.22);
				water.a = min(1.0, water.a + water_mask * foam_strength * 0.10);
				vec3 suds = mix(foam_color.rgb, vec3(0.84, 0.91, 0.95),
					smoothstep(-0.02, 0.06, depth) * 0.22);
				float foam_alpha = foam_mask * foam_strength * foam_color.a;
				// Compose in straight alpha so foam above the water stays white.
				float combined_alpha = foam_alpha + water.a * (1.0 - foam_alpha);
				water.rgb = (suds * foam_alpha + water.rgb * water.a * (1.0 - foam_alpha))
					/ max(combined_alpha, 0.0001);
				water.a = combined_alpha;
			}

			// Crossfade in premultiplied space to avoid a dark edge over clear glass.
			// 0.32 is the existing visual foam target for WASH.
			float vortex_strength = smoothstep(0.0, 0.32, foam_amount);
			if (vortex_strength > 0.001) {
				vec4 vortex = vortex_water(UV, foam_strength);
				float alpha = mix(water.a, vortex.a, vortex_strength);
				vec3 premultiplied = mix(water.rgb * water.a, vortex.rgb * vortex.a, vortex_strength);
				water = vec4(premultiplied / max(alpha, 0.0001), alpha);
			}
			COLOR = water;
		}
	}
}
