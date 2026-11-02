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
uniform float vignette = 0.45;
uniform float grain = 0.035;
uniform float exposure = 1.08;
uniform vec3 shadow_tint = vec3(0.92, 0.97, 1.12);
uniform vec3 light_tint = vec3(1.08, 1.0, 0.92);

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
	float aspect = res.x / res.y;
	vec3 a = drops(uv, aspect, 0.075, TIME, 0.0, 0.16);
	vec3 b = drops(uv + vec2(0.37, 0.11), aspect, 0.045, TIME * 1.3, 5.0, 0.1);
	uv += a.xy + b.xy;

	// Flou radial et aberration chromatique vers les bords, à grande vitesse.
	vec2 dir = uv - vec2(0.5, 0.55);
	float edge = dot(dir, dir);
	float blur = speed * speed * 0.035 * edge * 4.0;
	vec3 c = vec3(0.0);
	for (int i = 0; i < 6; i++) {
		float k = float(i) / 5.0;
		vec2 o = dir * blur * k;
		float ca = (speed * 0.004 + hit * 0.012) * edge * 4.0;
		c.r += texture(screen_tex, uv - o * (1.0 + ca * 40.0) - dir * ca).r;
		c.g += texture(screen_tex, uv - o).g;
		c.b += texture(screen_tex, uv - o * (1.0 - ca * 40.0) + dir * ca).b;
	}
	c /= 6.0;
	c += vec3(0.55, 0.6, 0.7) * (a.z + b.z) * 0.3;
	c += vec3(0.35, 0.12, 0.05) * hit * (0.3 + edge * 3.0);

	// Étalonnage : ombres froides, lumières chaudes, léger contraste.
	c *= exposure;
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	c *= mix(shadow_tint, light_tint, smoothstep(0.05, 0.6, lum));
	c = mix(vec3(lum), c, 1.12);
	c = c * c * (3.0 - 2.0 * c) * 0.25 + c * 0.75;
	// Vignette et grain.
	vec2 q = SCREEN_UV - 0.5;
	c *= 1.0 - vignette * dot(q, q) * 2.0;
	c += (hash21(SCREEN_UV * res + fract(TIME) * 61.0) - 0.5) * grain;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
