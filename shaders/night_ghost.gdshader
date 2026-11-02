shader_type spatial;
// Fantôme du record : un hologramme additif, contour lumineux (Fresnel) et
// fines lignes qui défilent. Pas d'ombre, pas d'écriture de profondeur.
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

#include "res://shaders/night_common.gdshaderinc"

uniform vec3 tint : source_color = vec3(0.3, 0.85, 1.0);
uniform float strength = 1.0;

void fragment() {
	vec3 P = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (night_below_mirror(P, CAMERA_POSITION_WORLD)) {
		discard;
	}
	vec3 N = normalize(NORMAL);
	vec3 V = normalize(-VERTEX);
	float rim = pow(1.0 - abs(dot(N, V)), 2.0);
	float lines = 0.75 + 0.25 * sin(P.y * 40.0 - TIME * 8.0);
	float dist = length(VERTEX);
	ALBEDO = tint * (0.08 + rim * 0.9) * lines * strength * (1.0 - night_fog(dist));
}
