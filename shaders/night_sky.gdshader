shader_type sky;
// Ciel de nuit : dégradé du zénith à l'horizon. `dawn` (0..1) éclaircira
// l'horizon au fil de la partie (étape M1).

uniform vec3 zenith : source_color = vec3(0.01, 0.012, 0.03);
uniform vec3 horizon : source_color = vec3(0.05, 0.06, 0.12);
uniform vec3 dawn_glow : source_color = vec3(0.55, 0.28, 0.18);
uniform float dawn : hint_range(0.0, 1.0) = 0.0;

void sky() {
	float h = clamp(EYEDIR.y, 0.0, 1.0);
	vec3 c = mix(horizon, zenith, pow(h, 0.45));
	float glow = pow(1.0 - h, 6.0) * dawn;
	COLOR = c + dawn_glow * glow;
}
