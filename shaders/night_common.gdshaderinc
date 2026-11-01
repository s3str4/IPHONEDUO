// Éclairage de nuit commun à tout le décor. Les lumières proches (lampadaires,
// stations, tunnels) arrivent par une petite texture de données, écrite à
// chaque image par scripts/light_field.gd : ligne 0 = position (xyz) et
// portée (w), ligne 1 = couleur (rgb) et intensité (a). Paramètres globaux
// déclarés dans project.godot [shader_globals].

global uniform vec4 fog_color;
global uniform float fog_start;
global uniform float fog_end;
global uniform sampler2D lights_tex : filter_nearest;
global uniform float light_count;
global uniform vec3 head_pos;
global uniform vec3 head_dir;
global uniform sampler2D reflection_tex : filter_linear, repeat_disable;
global uniform float reflection_on;
// Plan du miroir (n.xyz, d) : pendant le rendu du reflet (caméra sous le plan),
// tout ce qui est sous la route est écarté, sinon le terrain vu par en dessous
// masquerait tout.
global uniform vec4 mirror_plane;
global uniform vec4 sky_ambient;

const int MAX_LIGHTS = 16;
const vec3 HEADLIGHT_COLOR = vec3(1.0, 0.93, 0.78);

bool night_below_mirror(vec3 P, vec3 cam) {
	float side_cam = dot(mirror_plane.xyz, cam) + mirror_plane.w;
	return side_cam < 0.0 && dot(mirror_plane.xyz, P) + mirror_plane.w < -0.05;
}

float night_fog(float dist) {
	return smoothstep(fog_start, fog_end, dist) * fog_color.a;
}

// Somme des lumières proches : diffus et spéculaire (Blinn-Phong normalisé).
void night_lights(vec3 P, vec3 N, vec3 V, float shininess, out vec3 diffuse, out vec3 specular) {
	diffuse = vec3(0.0);
	specular = vec3(0.0);
	int n = int(light_count);
	for (int i = 0; i < MAX_LIGHTS; i++) {
		if (i >= n) {
			break;
		}
		vec4 a = texelFetch(lights_tex, ivec2(i, 0), 0);
		vec3 L = a.xyz - P;
		float d = length(L);
		if (d > a.w) {
			continue;
		}
		vec4 b = texelFetch(lights_tex, ivec2(i, 1), 0);
		L /= d;
		float att = 1.0 - d / a.w;
		att *= att;
		vec3 c = b.rgb * b.a * att;
		diffuse += c * max(dot(N, L), 0.0);
		vec3 H = normalize(L + V);
		// Reflet normalisé, plafonné : un vernis très lisse ne doit pas éblouir.
		specular += c * pow(max(dot(N, H), 0.0), shininess) * min((shininess + 8.0) * 0.04, 4.0);
	}
}

// Phares de la voiture du joueur : un cône qui éclaire la route devant.
vec3 night_headlight(vec3 P, vec3 N) {
	vec3 L = P - head_pos;
	float d = length(L);
	if (d > 75.0 || d < 0.01) {
		return vec3(0.0);
	}
	float cone = smoothstep(0.86, 0.97, dot(L / d, head_dir));
	float att = 1.0 - d / 75.0;
	return HEADLIGHT_COLOR * cone * att * att * 2.2 * max(dot(N, -L / d), 0.0);
}

// Courbe de tonalité (approximation ACES) : l'image est écrite sur 8 bits,
// sans elle une carrosserie sous un lampadaire sature et bave dans le bloom.
vec3 night_tonemap(vec3 c) {
	c *= 0.9;
	return clamp((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14), 0.0, 1.0);
}

// Fresnel de Schlick.
float night_fresnel(vec3 N, vec3 V, float f0) {
	return f0 + (1.0 - f0) * pow(1.0 - clamp(dot(N, V), 0.0, 1.0), 5.0);
}

// Bruit de valeur (gouttes, flaques, rides).
float night_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float night_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(night_hash(i), night_hash(i + vec2(1, 0)), u.x),
			mix(night_hash(i + vec2(0, 1)), night_hash(i + vec2(1, 1)), u.x), u.y);
}
