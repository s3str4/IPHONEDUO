// Fonctions communes du look PS1 (reprises de YTSLEEP). Les paramètres globaux
// sont déclarés dans project.godot [shader_globals].

global uniform vec2 ps1_snap_resolution;  // grille d'accroche des sommets (pixels écran)
global uniform float ps1_jitter;          // 0 = pas d'accroche, 1 = accroche franche
global uniform float ps1_affine;          // 0 = perspective correcte, 1 = affine pur
global uniform vec4 ps1_fog_color;        // a = force du brouillard
global uniform float ps1_fog_start;
global uniform float ps1_fog_end;

vec4 ps1_snap(vec4 clip) {
	if (clip.w <= 0.0) {
		return clip;
	}
	vec2 grid = ps1_snap_resolution * 0.5;
	vec2 ndc = clip.xy / clip.w;
	vec2 snapped = round(ndc * grid) / grid;
	clip.xy = mix(ndc, snapped, ps1_jitter) * clip.w;
	return clip;
}

// Brouillard de distance, calculé par sommet comme sur PS1.
float ps1_fog_factor(float view_depth) {
	return smoothstep(ps1_fog_start, ps1_fog_end, view_depth) * ps1_fog_color.a;
}
