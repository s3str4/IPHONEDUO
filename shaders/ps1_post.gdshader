shader_type canvas_item;
// Post-process PS1 (repris de YTSLEEP) : palette 15 bits + dithering Bayer 4x4,
// appliqué à la résolution interne.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform bool enabled = true;
uniform float color_bits : hint_range(1.0, 8.0, 1.0) = 5.0;
uniform float dither_strength : hint_range(0.0, 2.0) = 1.0;

const float BAYER[16] = float[](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	if (enabled) {
		ivec2 p = ivec2(FRAGCOORD.xy) % 4;
		float b = (BAYER[p.y * 4 + p.x] + 0.5) / 16.0 - 0.5;
		float levels = exp2(color_bits) - 1.0;
		c = floor(clamp(c, 0.0, 1.0) * levels + 0.5 + b * dither_strength) / levels;
	}
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
