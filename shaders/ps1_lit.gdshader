shader_type spatial;
// Matériau PS1 éclairé : accroche des sommets, mapping affine, texture nearest,
// couleur de sommet (l'éclairage des lampadaires y est précalculé), brouillard
// par sommet, éclairage par sommet (phares). Double face : la géométrie
// générée n'a pas à se soucier du sens des triangles.
render_mode vertex_lighting, cull_disabled, diffuse_lambert, specular_disabled;

#include "res://shaders/ps1_common.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_enable, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0);
uniform float affine_strength : hint_range(0.0, 1.0) = 1.0;
// Part de la couleur de sommet rendue en émission (lumière précalculée).
uniform float baked_light = 1.0;
// Couleur de la lumière précalculée (sodium des lampadaires), surexposée.
uniform vec3 baked_tint = vec3(2.4, 1.55, 0.85);

varying vec3 affine_uv;
varying float fog_f;

void vertex() {
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 clip = ps1_snap(PROJECTION_MATRIX * view);
	POSITION = clip;
	affine_uv = vec3(UV * uv_scale * clip.w, clip.w);
	fog_f = ps1_fog_factor(-view.z);
}

void fragment() {
	vec2 uv_persp = UV * uv_scale;
	vec2 uv_aff = affine_uv.xy / affine_uv.z;
	vec2 uv = mix(uv_persp, uv_aff, clamp(ps1_affine * affine_strength, 0.0, 1.0));
	vec3 tex = texture(albedo_tex, uv).rgb * albedo_color.rgb;
	// COLOR.rgb : teinte de surface ; COLOR.a : lumière précalculée (0..1).
	vec3 base = tex * COLOR.rgb;
	ALBEDO = base * (1.0 - fog_f);
	EMISSION = base * COLOR.a * baked_light * baked_tint * (1.0 - fog_f) + ps1_fog_color.rgb * fog_f;
}
