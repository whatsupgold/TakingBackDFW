shader_type spatial;
// Moving water: two layers of ripples drifting different ways over slow swells, darker where
// it's deep and see-through in the shallows, and surf lines rolling in to break on the shore
// (worked out from how far the ground is behind the water surface).
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;

uniform vec3 deep_color : source_color = vec3(0.05, 0.17, 0.28);
uniform vec3 shallow_color : source_color = vec3(0.15, 0.40, 0.47);
uniform vec3 foam_color : source_color = vec3(0.93, 0.96, 0.97);
uniform vec2 origin = vec2(0.0);           // the floating origin (wrapped), so the waves don't jump
uniform float surf = 1.0;                  // waves breaking on the shore (0: lakes and rivers)
uniform float depth_tint = 1.0;            // darker when deep (0: lakes and rivers keep one colour)
uniform float min_alpha = 0.55;
uniform float ripple = 0.65;
uniform sampler2D ripples_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D ripples_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

varying vec2 wxz;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wxz = w.xz + origin;
}

void fragment() {
	float t = TIME;
	// Ripples: two layers sliding across each other, and a slow swell under them. The water is
	// flat, so the bumps tilt "up" directly (no tangents needed: the lake meshes have none).
	vec3 a = texture(ripples_a, wxz / 160.0 + vec2(t * 0.011, t * 0.007)).rgb * 2.0 - 1.0;
	vec3 b = texture(ripples_b, wxz / 96.0 + vec2(-t * 0.009, t * 0.012)).rgb * 2.0 - 1.0;
	vec3 c = texture(ripples_a, wxz / 768.0 + vec2(t * 0.0021, -t * 0.0016)).rgb * 2.0 - 1.0;
	vec2 slope = (a.xy + b.xy + c.xy * 1.4) * ripple * 0.5;
	vec3 nw = normalize(vec3(slope.x, 1.0, slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	// How much water is behind this point, along the view (game metres)
	float raw = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, raw) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw);
#endif
	vec4 v = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	v.xyz /= v.w;
	float thick = max(VERTEX.z - v.z, 0.0);

	float deep = clamp(thick / 30.0, 0.0, 1.0) * depth_tint;
	vec3 col = mix(shallow_color, deep_color, deep);
	float alpha = mix(min_alpha, 0.94, clamp(thick / 4.0, 0.0, 1.0));

	// Surf: foam where the water meets the shore, and bands of it rolling in
	// (the Gulf coast shelves very gently, so this all happens in the first metre of depth)
	float edge = 1.0 - smoothstep(0.0, 0.18, thick);
	float bands = smoothstep(0.86, 1.0, sin(thick * 26.0 - t * 1.5) * 0.5 + 0.5) * (1.0 - smoothstep(0.25, 0.75, thick));
	float n = texture(foam_noise, wxz / 48.0 + vec2(t * 0.012, -t * 0.008)).r;
	float f = clamp(edge * smoothstep(0.2, 0.5, n + edge * 0.4) + bands * 0.8 * smoothstep(0.35, 0.65, n), 0.0, 1.0) * surf;

	ALBEDO = mix(col, foam_color, f);
	ALPHA = max(alpha, f);
	ROUGHNESS = mix(0.04, 0.85, f);
	SPECULAR = 0.6;
	METALLIC = 0.0;
}
