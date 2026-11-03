shader_type canvas_item;
// Post-traitement : gouttes de pluie sur l'écran (réfraction), flou radial et
// aberration chromatique à grande vitesse, étalonnage (ombres bleutées,
// lumières chaudes), vignette et grain.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
// Densité des gouttes (0 = temps sec).
uniform float rain = 1.0;
// Vitesse de la voiture (0..1, plus sous turbo) : flou radial et aberration.
uniform float speed = 0.0;
// Choc (0..1, retombe vite) : flash chaud et aberration.
uniform float hit = 0.0;
// Police dans le dos : lueur de gyrophare (couleur, force) sur les bords bas.
uniform vec4 siren = vec4(0.0);
uniform float vignette = 0.45;
uniform float grain = 0.035;
uniform float exposure = 1.08;
uniform vec3 shadow_tint = vec3(0.92, 0.97, 1.12);
uniform vec3 light_tint = vec3(1.08, 1.0, 0.92);
// Mode pixel art (réglages) : gros pixels nets (art_lines lignes à l'écran),
// palette synthwave de 16 couleurs avec trame ordonnée, contours sombres.
uniform float pixel_art = 0.0;
uniform float art_lines = 240.0;
const vec3 PALETTE[16] = vec3[16](
	vec3(0.051, 0.008, 0.129), vec3(0.106, 0.043, 0.231), vec3(0.16, 0.24, 0.86), vec3(0.29, 0.102, 0.478),
	vec3(0.478, 0.122, 0.635), vec3(0.69, 0.141, 0.612), vec3(0.902, 0.188, 0.549), vec3(1.0, 0.31, 0.475),
	vec3(1.0, 0.541, 0.361), vec3(1.0, 0.784, 0.341), vec3(1.0, 0.953, 0.69), vec3(0.239, 0.839, 0.961),
	vec3(0.169, 0.561, 0.851), vec3(0.122, 0.306, 0.612), vec3(0.059, 0.165, 0.361), vec3(0.94, 0.94, 1.0));

float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i.y * 4 + i.x]) + 0.5) / 16.0;
}

vec3 to_palette(vec3 c, float d) {
	vec3 best = PALETTE[0];
	float bd = 1e9;
	vec3 q = c + (d - 0.5) * 0.07;
	for (int i = 0; i < 16; i++) {
		vec3 e = q - PALETTE[i];
		// Distance pondérée (l'œil est plus sensible au vert).
		float dd = dot(e * e, vec3(0.3, 0.59, 0.11));
		if (dd < bd) {
			bd = dd;
			best = PALETTE[i];
		}
	}
	return best;
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Une couche de gouttes en coordonnées d'écran normalisées (indépendantes de
// la résolution). Renvoie le décalage de réfraction (xy) et le reflet du bord (z).
vec3 drops(vec2 uv, float aspect, float cell, float t, float seed, float density) {
	vec2 p = vec2(uv.x * aspect, uv.y) / cell;
	vec2 id = floor(p);
	float r = hash21(id + seed);
	if (r > rain * density) {
		return vec3(0.0);
	}
	float period = 2.5 + r * 4.0;
	float life = fract(t / period + hash21(id + seed + 3.0));
	vec2 center = id + vec2(0.25 + 0.5 * hash21(id + 7.0), 0.2 + 0.4 * hash21(id + 9.0));
	center.y += life * life * 0.6;
	float radius = (0.1 + 0.1 * hash21(id + 11.0)) * (1.0 - life * 0.4);
	vec2 d = p - center;
	d.y *= 0.85;
	float dist = length(d) / radius;
	if (dist > 1.0) {
		return vec3(0.0);
	}
	float fade = smoothstep(1.0, 0.75, life);
	float lens = sqrt(1.0 - dist * dist);
	vec2 offset = -d * cell * 1.4 * lens * fade;
	offset.x /= aspect;
	float rim = smoothstep(0.65, 1.0, dist) * (d.y < 0.0 ? 0.5 : 0.1) * fade;
	return vec3(offset, rim);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	// Pixel art : tout l'image est lue au centre de gros pixels.
	float ps = max(1.0, res.y / art_lines);
	vec2 cell_px = floor(SCREEN_UV * res / ps);
	if (pixel_art > 0.5) {
		uv = (cell_px + 0.5) * ps / res;
	}
	float aspect = res.x / res.y;
	vec3 a = drops(uv, aspect, 0.075, TIME, 0.0, 0.16);
	vec3 b = drops(uv + vec2(0.37, 0.11), aspect, 0.045, TIME * 1.3, 5.0, 0.1);
	uv += a.xy + b.xy;

	// Flou radial et aberration chromatique vers les bords, à grande vitesse.
	vec2 dir = uv - vec2(0.5, 0.55);
	float edge = dot(dir, dir);
	float blur = speed * speed * 0.035 * edge * 4.0;
	vec3 c = vec3(0.0);
	// À l'arrêt ou au ralenti, pas de flou : une seule lecture au lieu de six
	// (l'écran est grand sur iPhone, chaque lecture compte).
	int taps = (speed > 0.05 || hit > 0.01) ? 6 : 1;
	for (int i = 0; i < 6; i++) {
		if (i >= taps) {
			break;
		}
		float k = taps > 1 ? float(i) / 5.0 : 0.0;
		vec2 o = dir * blur * k;
		float ca = (speed * 0.004 + hit * 0.012) * edge * 4.0;
		c.r += texture(screen_tex, uv - o * (1.0 + ca * 40.0) - dir * ca).r;
		c.g += texture(screen_tex, uv - o).g;
		c.b += texture(screen_tex, uv - o * (1.0 - ca * 40.0) + dir * ca).b;
	}
	c /= float(taps);
	c += vec3(0.55, 0.6, 0.7) * (a.z + b.z) * 0.3;
	c += vec3(0.35, 0.12, 0.05) * hit * (0.3 + edge * 3.0);

	// Étalonnage : ombres froides, lumières chaudes, léger contraste.
	c *= exposure;
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	c *= mix(shadow_tint, light_tint, smoothstep(0.05, 0.6, lum));
	c = mix(vec3(lum), c, 1.12);
	c = c * c * (3.0 - 2.0 * c) * 0.25 + c * 0.75;
	// Gyrophares derrière : les bords de l'écran (surtout en bas) se teintent.
	vec2 sq = SCREEN_UV - vec2(0.5, 1.05);
	float rim = smoothstep(0.25, 0.75, length(sq * vec2(1.6, 1.0)));
	c += siren.rgb * siren.a * rim * 0.55;
	// Vignette et grain.
	vec2 q = SCREEN_UV - 0.5;
	c *= 1.0 - vignette * dot(q, q) * 2.0;
	if (pixel_art > 0.5) {
		// Contours : un gros pixel nettement plus clair que son voisin du bas ou
		// de droite devient un trait sombre.
		vec2 step_uv = ps / res;
		float l0 = dot(texture(screen_tex, uv).rgb, vec3(0.33));
		float l1 = dot(texture(screen_tex, uv + vec2(step_uv.x, 0.0)).rgb, vec3(0.33));
		float l2 = dot(texture(screen_tex, uv + vec2(0.0, step_uv.y)).rgb, vec3(0.33));
		float edge = step(0.18, max(abs(l0 - l1), abs(l0 - l2))) * step(l0, 0.35);
		// Moyenne de 4 points dans le gros pixel (moins de grain), étalonnée comme c.
		vec2 o = step_uv * 0.25;
		vec3 avg = (texture(screen_tex, uv + vec2(-o.x, -o.y)).rgb + texture(screen_tex, uv + vec2(o.x, -o.y)).rgb
				+ texture(screen_tex, uv + vec2(-o.x, o.y)).rgb + texture(screen_tex, uv + vec2(o.x, o.y)).rgb) * 0.25;
		float lc = dot(texture(screen_tex, uv).rgb, vec3(0.33));
		c *= (dot(avg, vec3(0.33)) + 0.02) / (lc + 0.02);
		// Un peu plus clair : la palette écrase les tons sombres (la voiture s'y perdait).
		c = to_palette(clamp(c * 1.3 + 0.02, 0.0, 1.0), bayer4(cell_px));
		c = mix(c, PALETTE[0], edge * 0.8);
	} else {
		c += (hash21(SCREEN_UV * res + fract(TIME) * 61.0) - 0.5) * grain;
	}
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
