shader_type spatial;
// Lumières additives sans éclairage : ampoules, feux, reflets sur la route
// mouillée. UV.y sert de dégradé (1 au centre, 0 au bord) pour les reflets.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

#include "res://shaders/ps1_common.gdshaderinc"

uniform float intensity = 1.0;

varying float fog_f;

void vertex() {
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = ps1_snap(PROJECTION_MATRIX * view);
	fog_f = ps1_fog_factor(-view.z);
}

void fragment() {
	// Dégradé crénelé en 4 paliers, comme une texture PS1 de 4 pixels.
	float g = floor(UV.y * 4.0 + 0.5) / 4.0;
	ALBEDO = COLOR.rgb * COLOR.a * g * intensity * (1.0 - fog_f * 0.85);
}
