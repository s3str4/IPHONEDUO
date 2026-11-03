shader_type spatial;
// Surfaces du décor (route, terrain, eau, bâtiments) : éclairage par pixel des
// lumières proches, phares, reflet miroir de la route mouillée (caméra de
// réflexion, scripts/reflection.gd), lumière précalculée au loin, brouillard.
render_mode unshaded, cull_disabled;

#include "res://shaders/night_common.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0);
// 0 = sec et mat ; 1 = flaque miroir. L'alpha de la texture module (flaques).
uniform float wet : hint_range(0.0, 1.0) = 0.0;
// Part du reflet miroir sur les zones mouillées.
uniform float reflectivity : hint_range(0.0, 1.0) = 0.0;
uniform float specular_strength = 0.4;
// Lumière précalculée dans l'alpha des couleurs de sommet (lampadaires
// lointains, hors des lumières proches) et sa teinte.
uniform vec3 baked_tint = vec3(1.0, 0.62, 0.28);
uniform float baked_strength = 1.6;
uniform float ripples = 0.0;
// Route : la peinture des marquages (texels clairs) est moins glissante sous la
// pluie et renvoie la lumière des phares vers la voiture (rétroréflexion).
uniform float marking = 0.0;
// Néon des marquages (route) : la peinture luit d'elle-même.
uniform vec3 marking_glow = vec3(0.0);
// Grille néon synthwave sur le terrain (lignes du monde en x et z, en mètres).
uniform float grid = 0.0;
uniform vec3 grid_color : source_color = vec3(1.0, 0.25, 0.75);
uniform float grid_size = 8.0;

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
	float dist = length(CAMERA_POSITION_WORLD - P);
	vec4 tex = texture(albedo_tex, UV * uv_scale);
	vec3 base = tex.rgb * albedo_color.rgb * COLOR.rgb;
	float wetness = wet * mix(0.45, 1.0, tex.a);
	float paint = marking * smoothstep(0.18, 0.35, dot(tex.rgb, vec3(0.333)));
	wetness *= 1.0 - paint * 0.75;

	// Rides de pluie : la normale tremble un peu dans les flaques.
	vec2 rip = vec2(0.0);
	if (ripples > 0.0) {
		vec2 q = P.xz * 1.7;
		rip = (vec2(night_noise(q + vec2(TIME * 1.3, 0.0)), night_noise(q.yx - vec2(0.0, TIME * 1.1))) - 0.5) * ripples;
		N = normalize(N + vec3(rip.x, 0.0, rip.y) * 0.6);
	}

	float shininess = mix(90.0, 360.0, wetness);
	vec3 dif;
	vec3 spe;
	night_lights(P, N, V, shininess, dif, spe);
	vec3 amb = sky_ambient.rgb * (0.4 + 0.6 * max(N.y, 0.0));
	float far = smoothstep(80.0, 150.0, dist);
	vec3 baked = baked_tint * COLOR.a * baked_strength * mix(0.25, 1.0, far);
	vec3 head = night_headlight(P, N);
	vec3 col = base * (amb + dif + baked + head * (1.0 + paint * 2.5)) + base * paint * 0.05
			+ spe * specular_strength * (0.1 + 0.9 * wetness * wetness);

	// Reflet miroir : la caméra de réflexion voit la scène sous la route.
	if (reflection_on > 0.5 && reflectivity > 0.0) {
		float fres = night_fresnel(N, V, 0.04);
		vec2 ruv = SCREEN_UV + rip * 0.02;
		vec3 refl = texture(reflection_tex, ruv).rgb;
		float k = clamp(fres * wetness * reflectivity * 1.4, 0.0, 0.6);
		col = col * (1.0 - k * 0.6) + refl * k;
	}
	col += marking_glow * paint;
	// Grille : traits fins anticrénelés ; quand les cases deviennent trop petites
	// à l'écran (au loin), elle s'efface au lieu de fourmiller.
	if (grid > 0.0) {
		vec2 g = P.xz / grid_size;
		vec2 fw = max(fwidth(g), vec2(1e-4));
		vec2 a = abs(fract(g - 0.5) - 0.5) / fw;
		float line = 1.0 - min(min(a.x, a.y) / 1.2, 1.0);
		line *= 1.0 - smoothstep(0.12, 0.45, max(fw.x, fw.y));
		col += grid_color * line * grid * 1.6;
	}
	col = mix(night_tonemap(col), fog_color.rgb, night_fog(dist));
	ALBEDO = col;
}
