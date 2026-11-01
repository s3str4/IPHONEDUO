shader_type spatial;
// Halo lumineux toujours face caméra (ampoules, feux, enseignes). Chaque halo
// est un quad dont les 4 sommets sont au centre ; UV donne le coin (-1..1) et
// UV2.x la taille en mètres. Dégradé en anneaux, comme un sprite PS1.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

#include "res://shaders/ps1_common.gdshaderinc"

uniform float intensity = 1.0;

varying float fog_f;
varying vec2 corner;

void vertex() {
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	view.xy += UV * UV2.x;
	POSITION = ps1_snap(PROJECTION_MATRIX * view);
	fog_f = ps1_fog_factor(-view.z);
	corner = UV;
}

void fragment() {
	float r = length(corner);
	float a = clamp(1.0 - r, 0.0, 1.0);
	a = a * a;
	a = floor(a * 5.0 + 0.5) / 5.0;
	ALBEDO = COLOR.rgb * COLOR.a * a * intensity * (1.0 - fog_f * 0.7);
}
