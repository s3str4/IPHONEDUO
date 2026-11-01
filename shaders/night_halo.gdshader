shader_type spatial;
// Halo lumineux toujours face caméra. Chaque halo est un quad dont les 4
// sommets sont au centre ; UV donne le coin (-1..1), UV2.x la taille en mètres.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://shaders/night_common.gdshaderinc"

uniform float intensity = 1.0;

varying float fade;
varying vec2 corner;

void vertex() {
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	view.xy += UV * UV2.x;
	POSITION = PROJECTION_MATRIX * view;
	// Tout près de la caméra, un halo emplirait l'écran ; au loin, la brume l'éteint.
	fade = smoothstep(5.0, 16.0, -view.z) * (1.0 - night_fog(-view.z) * 0.7);
	corner = UV;
}

void fragment() {
	float r = length(corner);
	float a = exp(-r * r * 5.0) * (1.0 - smoothstep(0.85, 1.0, r));
	ALBEDO = COLOR.rgb * COLOR.a * a * intensity * fade;
}
