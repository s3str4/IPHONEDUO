shader_type sky;
// Ciel de nuit : dégradé, étoiles, lune et son halo, nuages éclairés par en
// dessous, deux chaînes de montagnes et une ville illuminée à l'horizon.
// `dawn` (0..1) éclaircit tout au fil de la partie : c'est la jauge d'avancement.

uniform vec3 zenith : source_color = vec3(0.01, 0.012, 0.03);
uniform vec3 horizon : source_color = vec3(0.05, 0.06, 0.12);
uniform vec3 dawn_glow : source_color = vec3(0.95, 0.45, 0.25);
uniform vec3 city_glow : source_color = vec3(0.9, 0.45, 0.2);
uniform vec3 moon_dir = vec3(-0.45, 0.32, -0.83);
uniform float dawn : hint_range(0.0, 1.0) = 0.0;
// Éclair (0..1) : les nuages s'illuminent de l'intérieur, le ciel blanchit.
uniform float flash = 0.0;
// Soleil levant (scènes de fin) : hauteur en radians, sous l'horizon = caché.
uniform float sun = -0.3;
// Direction (azimut, rad) de la ville et du lever du soleil.
uniform float city_azimuth = 0.6;
uniform float sun_azimuth = -0.2;
// 0 : pas de ville à l'horizon (scènes de fin loin de la ville).
uniform float city_amount = 1.0;
// Taille d'un pixel de l'écran en radians (voir Main), pour l'anticrénelage
// des fenêtres de la ville à l'horizon.
uniform float pixel_angle = 0.002;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), u.x),
			mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

// Écart angulaire signé entre deux azimuts, dans [-pi, pi].
float az_delta(float a, float b) {
	return mod(a - b + 3.14159265, 6.2831853) - 3.14159265;
}

// Créneau périodique allumé sur [a, 1) de chaque période, moyenné sur une
// largeur w (en périodes) : l'intégrale exacte, sans crénelage.
float pulse_integral(float x, float a) {
	return floor(x) * (1.0 - a) + max(fract(x) - a, 0.0);
}
float pulse_aa(float x, float a, float w) {
	w = max(w, 1e-4);
	return (pulse_integral(x + w * 0.5, a) - pulse_integral(x - w * 0.5, a)) / w;
}


void sky() {
	vec3 d = normalize(EYEDIR);
	float az = atan(d.x, -d.z);
	float h = d.y;
	float hp = max(h, 0.0);

	// Dégradé, plus une lueur d'aube côté soleil levant.
	vec3 col = mix(horizon, zenith, pow(hp, 0.45));
	float sun_side = 0.5 + 0.5 * cos(az_delta(az, sun_azimuth));
	col += dawn_glow * pow(1.0 - hp, 5.0) * dawn * (0.35 + 0.65 * sun_side);
	// Halo orangé de la ville au-dessus de l'horizon.
	float city_side = exp(-pow(az_delta(az, city_azimuth) / 0.35, 2.0));
	col += city_glow * city_side * pow(1.0 - hp, 9.0) * 0.35 * (1.0 - dawn);

	// Étoiles : grille sur la sphère, scintillement, effacées par l'aube.
	vec2 sp = vec2(az * 60.0, h * 80.0);
	vec2 cell = floor(sp);
	float r = hash21(cell);
	if (r > 0.972 && h > 0.08) {
		vec2 c = fract(sp) - 0.5;
		float tw = 0.6 + 0.4 * sin(TIME * (1.5 + r * 4.0) + r * 40.0);
		float star = smoothstep(0.32, 0.0, length(c)) * tw * (0.5 + (r - 0.972) * 40.0);
		col += vec3(0.85, 0.9, 1.0) * star * smoothstep(0.08, 0.3, h) * (1.0 - dawn);
	}

	// Lune : disque cratérisé et halo.
	vec3 md = normalize(moon_dir);
	float mc = dot(d, md);
	float moon = smoothstep(0.99955, 0.99975, mc);
	vec3 moon_col = vec3(0.95, 0.93, 0.85) * (0.8 + 0.3 * noise(d.xy * 900.0));
	col += vec3(0.5, 0.55, 0.75) * pow(max(mc, 0.0), 300.0) * 0.5 * (1.0 - dawn * 0.7);

	// Nuages : couche projetée sur un plafond, dérive lente, éclairés par en
	// dessous (ville, aube) et bordés par la lune.
	float cloud_amt = 0.0;
	if (h > 0.0) {
		vec2 cuv = d.xz / (h + 0.12) * 1.4 + vec2(TIME * 0.006, TIME * 0.002);
		float n = fbm(cuv);
		float cloud = smoothstep(0.48, 0.78, n) * smoothstep(0.0, 0.12, h) * (1.0 - smoothstep(0.55, 0.9, h));
		vec3 under = mix(vec3(0.06, 0.06, 0.1), city_glow * 0.35, city_side * 0.8);
		under = mix(under, dawn_glow * 0.75, dawn * (0.4 + 0.6 * sun_side));
		vec3 rim = vec3(0.6, 0.65, 0.85) * pow(max(mc, 0.0), 40.0);
		vec3 cloud_col = under + rim * 0.5;
		col = mix(col, cloud_col, cloud * 0.85);
		moon *= 1.0 - cloud;
		cloud_amt = cloud;
	}
	col = mix(col, moon_col, moon);

	// Soleil rétro synthwave : grand disque posé sur l'horizon, du jaune au
	// magenta, coupé de bandes horizontales de plus en plus larges vers le bas.
	// Il monte un peu avec l'aube.
	{
		float sa = az_delta(az, sun_azimuth);
		float sc = mix(0.15, 0.22, dawn);
		vec2 q = vec2(sa, h - sc);
		float rad = 0.2;
		float r = length(q) / rad;
		float disc = 1.0 - smoothstep(1.0 - pixel_angle * 2.0 / rad, 1.0, r);
		float yy = q.y / rad;
		// Bandes : seulement dans la moitié basse, épaisseur croissante.
		float band = 1.0;
		if (yy < 0.35) {
			float k = (0.35 - yy) * 8.0;
			float gap = clamp(0.1 + (0.35 - yy) * 0.5, 0.0, 0.75);
			// Bord de bande anticrénelé (taille d'un pixel en unités de bande).
			float aa = pixel_angle / rad * 8.0;
			band = smoothstep(gap - aa, gap + aa, fract(k));
		}
		vec3 sun_top = vec3(1.0, 0.86, 0.35);
		vec3 sun_bot = vec3(1.0, 0.18, 0.62);
		vec3 sunc = mix(sun_bot, sun_top, smoothstep(-0.2, 0.9, yy)) * 1.2;
		col = mix(col, sunc, disc * band);
		// Halo rose autour du soleil.
		col += vec3(1.0, 0.25, 0.6) * exp(-max(r - 1.0, 0.0) * 3.0) * 0.25 * (1.0 - disc);
	}
	// Montagnes : deux silhouettes, la plus lointaine noyée dans la brume.
	float far_h = 0.07 + 0.11 * fbm(vec2(az * 3.0, 1.7)) + 0.03 * sin(az * 5.0);
	float near_h = 0.03 + 0.07 * fbm(vec2(az * 6.0 + 9.0, 3.1));
	vec3 haze = mix(horizon, dawn_glow * 0.5 + horizon * 0.6, dawn * 0.6);
	if (h < far_h) {
		col = mix(haze, zenith * 2.0, 0.35);
	}
	if (h < near_h) {
		col = zenith * 0.6 + haze * 0.15;
	}
	// Crêtes soulignées d'un trait néon (magenta au loin, cyan devant).
	float lw = pixel_angle * 1.6;
	col += vec3(1.0, 0.25, 0.75) * (1.0 - smoothstep(0.0, lw, abs(h - far_h))) * 0.9 * step(near_h, h);
	col += vec3(0.25, 0.85, 1.0) * (1.0 - smoothstep(0.0, lw, abs(h - near_h))) * 1.1;
	// Ville : immeubles aux fenêtres allumées, dans sa direction.
	float bx = az * 90.0;
	float bcell = floor(bx);
	float bh = 0.05 + 0.07 * pow(hash21(vec2(bcell, 7.0)), 2.0) * smoothstep(0.55, 0.0, abs(az_delta(az, city_azimuth)));
	if (city_amount > 0.5 && h < bh && abs(az_delta(az, city_azimuth)) < 0.55) {
		col = zenith * 1.5;
		vec2 w = vec2(fract(bx) * 2.0, h * 220.0);
		// Part de chaque pixel couverte par une fenêtre allumée, calculée exactement
		// (filtre boîte) : sans ça, ces fenêtres de 2 à 3 pixels scintillaient en roulant.
		float lit = step(0.62, hash21(floor(w) + bcell * 3.1))
				* pulse_aa(w.x, 0.3, pixel_angle * 180.0) * pulse_aa(w.y, 0.35, pixel_angle * 220.0);
		col += vec3(1.0, 0.75, 0.4) * lit * 0.9 * (1.0 - dawn * 0.8);
	}
	col += vec3(0.7, 0.75, 1.0) * flash * (0.6 + cloud_amt * 2.5) * smoothstep(-0.1, 0.3, h);
	// Soleil : disque et grand halo chaud, dans la direction du lever.
	vec3 sd = normalize(vec3(sin(sun_azimuth) * cos(sun), sin(sun), -cos(sun_azimuth) * cos(sun)));
	float sc = dot(d, sd);
	float disc = smoothstep(0.9994, 0.99965, sc) * step(far_h, h);
	vec3 sun_col = vec3(1.0, 0.72, 0.42);
	col += sun_col * pow(max(sc, 0.0), 60.0) * 0.8 * smoothstep(-0.25, 0.0, sun);
	col += sun_col * pow(max(sc, 0.0), 6.0) * 0.25 * smoothstep(-0.25, 0.05, sun);
	col = mix(col, vec3(1.0, 0.85, 0.6) * 1.4, disc);
	COLOR = col;
}
