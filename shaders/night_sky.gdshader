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
// Direction (azimut, rad) de la ville et du lever du soleil.
uniform float city_azimuth = 0.6;
uniform float sun_azimuth = -0.2;

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
	// Ville : immeubles aux fenêtres allumées, dans sa direction.
	float bx = az * 90.0;
	float bcell = floor(bx);
	float bh = 0.05 + 0.07 * pow(hash21(vec2(bcell, 7.0)), 2.0) * smoothstep(0.55, 0.0, abs(az_delta(az, city_azimuth)));
	if (h < bh && abs(az_delta(az, city_azimuth)) < 0.55) {
		col = zenith * 1.5;
		vec2 w = vec2(fract(bx) * 4.0, h * 400.0);
		float lit = step(0.62, hash21(floor(w) + bcell * 3.1)) * step(0.3, fract(w.x)) * step(0.35, fract(w.y));
		col += vec3(1.0, 0.75, 0.4) * lit * 0.9 * (1.0 - dawn * 0.8);
	}
	col += vec3(0.7, 0.75, 1.0) * flash * (0.6 + cloud_amt * 2.5) * smoothstep(-0.1, 0.3, h);
	COLOR = col;
}
