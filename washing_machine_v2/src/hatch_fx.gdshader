shader_type canvas_item;
render_mode blend_mix;

uniform float radius = 0.48;
uniform float softness = 0.06;

uniform float glass_strength = 0.42;
uniform float shadow_strength = 0.55;
uniform float light_bias = 0.35;

void fragment() {

    vec2 uv = UV * 2.0 - 1.0;
    float d = length(uv);

    // --- circular mask ---
    float mask = smoothstep(radius, radius - softness, d);

    // --- directional light (top-left) ---
    vec2 light_dir = normalize(vec2(-0.6, -0.8));
    float directional = dot(uv, light_dir);
    directional = clamp(1.0 - directional, 0.0, 1.0);

    // --- glass density (non linear) ---
    float glass = 1.0 - (d / radius);
    glass = pow(glass, 2.2) * glass_strength;

    // --- compression effect (thick glass look) ---
    float compression = pow(1.0 - d, 3.0) * 0.25;

    // --- bottom-weighted shadow (not radial) ---
    float bottom = smoothstep(-0.2, 0.9, uv.y);
    float shadow = pow(bottom, 2.0) * shadow_strength;

    // --- highlight bloom (off-center) ---
    vec2 highlight_uv = uv + vec2(0.25, 0.25);
    float highlight = smoothstep(0.35, 0.0, length(highlight_uv));
    highlight *= 0.25;

    float final_light =
        glass
        + compression
        + highlight
        + directional * light_bias
        - shadow;

    vec3 col = vec3(final_light);

    COLOR = vec4(col, mask * 0.6);
}