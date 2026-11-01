shader_type spatial;
// Lumières additives : ampoules, feux, vitrines, reflets. UV.y donne un dégradé
// (1 au centre, 0 au bord) pour les reflets et faisceaux.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://shaders/night_common.gdshaderinc"

uniform float intensity = 1.0;

void fragment() {
	if (night_below_mirror((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, CAMERA_POSITION_WORLD)) {
		discard;
	}
	float dist = length(VERTEX);
	float g = smoothstep(0.0, 1.0, UV.y);
	ALBEDO = COLOR.rgb * COLOR.a * g * intensity * (1.0 - night_fog(dist) * 0.85);
}
