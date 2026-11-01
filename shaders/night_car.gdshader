shader_type spatial;
// Peinture de carrosserie laquée : éclairage par pixel des lumières proches,
// reflets nets sur le vernis, ciel et lueurs de la ville renvoyés selon
// l'angle (Fresnel). La couleur vient des sommets ; alpha 0 = vitre ou pneu
// (plus sombre, vernis différent).
render_mode unshaded, cull_disabled;

#include "res://shaders/night_common.gdshaderinc"

uniform float gloss = 1.0;
// Lumière d'appoint (lampadaires qui ne sont pas dans les lumières proches).
uniform float fill = 0.2;
uniform vec3 fill_tint = vec3(1.0, 0.8, 0.6);
uniform vec3 horizon_glow : source_color = vec3(0.35, 0.22, 0.25);

void fragment() {
	vec3 P = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (night_below_mirror(P, CAMERA_POSITION_WORLD)) {
		discard;
	}
	vec3 N = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 V = normalize(CAMERA_POSITION_WORLD - P);
	// Normale toujours tournée vers la caméra, quel que soit le sens des triangles.
	if (dot(N, V) < 0.0) {
		N = -N;
	}
	vec3 base = COLOR.rgb;
	float paint = COLOR.a;
	vec3 dif;
	vec3 spe;
	night_lights(P, N, V, mix(40.0, 180.0, paint), dif, spe);
	vec3 amb = sky_ambient.rgb * (0.5 + 0.5 * max(N.y, 0.0)) + fill_tint * fill;
	vec3 col = base * (amb + dif + night_headlight(P, N) * 0.3) + spe * mix(0.15, 0.45, paint) * gloss;
	// Vernis : il renvoie le ciel (sombre en haut, lueur de la ville à l'horizon).
	vec3 R = reflect(-V, N);
	vec3 env = mix(horizon_glow, sky_ambient.rgb * 0.6, smoothstep(-0.1, 0.5, R.y));
	float fres = night_fresnel(N, V, mix(0.03, 0.06, paint));
	col += env * fres * gloss * (0.6 + paint);
	col = mix(night_tonemap(col), fog_color.rgb, night_fog(length(CAMERA_POSITION_WORLD - P)));
	ALBEDO = col;
}
