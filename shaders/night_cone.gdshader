shader_type spatial;
// Cône de lumière sous un lampadaire, dans la pluie : plus dense en haut, fondu
// sur les bords (selon l'angle de vue), parcouru de gouttes qui tombent.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://shaders/night_common.gdshaderinc"

uniform float intensity = 1.0;
uniform float rain = 1.0;

void fragment() {
	if (night_below_mirror((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, CAMERA_POSITION_WORLD)) {
		discard;
	}
	float edge = abs(dot(NORMAL, normalize(-VERTEX)));
	float body = pow(edge, 1.6) * pow(1.0 - UV.y, 1.3);
	vec2 q = vec2(UV.x * 40.0, UV.y * 6.0 + TIME * 7.0);
	float streak = smoothstep(0.75, 1.0, night_noise(vec2(q.x, q.y * 0.4))) * rain;
	float dist = length(VERTEX);
	// Tout près de la caméra, le cône emplirait l'écran.
	float near = smoothstep(6.0, 22.0, dist);
	ALBEDO = COLOR.rgb * COLOR.a * body * (0.55 + streak * 1.4) * intensity * (1.0 - night_fog(dist)) * near;
}
