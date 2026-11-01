shader_type canvas_item;
// Post-process : gouttes de pluie sur l'écran (réfraction), vignette, puis
// palette 15 bits + dithering Bayer 4x4 (repris de YTSLEEP), à la résolution
// interne.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform bool enabled = true;
uniform float color_bits : hint_range(1.0, 8.0, 1.0) = 5.0;
uniform float dither_strength : hint_range(0.0, 2.0) = 1.0;
// Densité des gouttes (0 = temps sec).
uniform float rain = 1.0;
uniform float vignette = 0.35;
uniform float exposure = 1.18;

const float BAYER[16] = float[](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Une couche de gouttes : chaque case de `cell` pixels porte au plus une goutte
// qui apparaît, glisse un peu vers le bas et s'évapore. Renvoie le décalage de
// réfraction (xy) et la brillance du bord (z).
vec3 drops(vec2 px, float cell, float t, float seed, float density) {
	vec2 id = floor(px / cell);
	float r = hash21(id + seed);
	if (r > rain * density) {
		return vec3(0.0);
	}
	float period = 2.5 + r * 4.0;
	float life = fract(t / period + hash21(id + seed + 3.0));
	vec2 center = (id + vec2(0.25 + 0.5 * hash21(id + 7.0), 0.2 + 0.4 * hash21(id + 9.0))) * cell;
	center.y += life * life * cell * 0.6;
	float radius = cell * (0.12 + 0.12 * hash21(id + 11.0)) * (1.0 - life * 0.4);
	vec2 d = px - center;
	d.y *= 0.8;
	float dist = length(d) / radius;
	if (dist > 1.0) {
		return vec3(0.0);
	}
	float fade = smoothstep(1.0, 0.75, life);
	// La goutte agit comme une petite lentille : image inversée, grossie.
	vec2 offset = -d * 1.6 * fade;
	float rim = smoothstep(0.7, 1.0, dist) * (d.y < 0.0 ? 0.45 : 0.08) * fade;
	return vec3(offset, rim);
}

void fragment() {
	vec2 px = FRAGCOORD.xy;
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec3 a = drops(px, 30.0, TIME, 0.0, 0.16);
	vec3 b = drops(px + vec2(13.0, 7.0), 19.0, TIME * 1.3, 5.0, 0.1);
	vec2 off = a.xy + b.xy;
	vec3 c = texture(screen_tex, SCREEN_UV + off / res).rgb;
	c += vec3(0.55, 0.6, 0.7) * (a.z + b.z) * 0.25;
	c *= exposure;
	// Vignette douce.
	vec2 q = SCREEN_UV - 0.5;
	c *= 1.0 - vignette * dot(q, q) * 2.0;
	if (enabled) {
		ivec2 p = ivec2(FRAGCOORD.xy) % 4;
		float bayer = (BAYER[p.y * 4 + p.x] + 0.5) / 16.0 - 0.5;
		float levels = exp2(color_bits) - 1.0;
		c = floor(clamp(c, 0.0, 1.0) * levels + 0.5 + bayer * dither_strength) / levels;
	}
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
