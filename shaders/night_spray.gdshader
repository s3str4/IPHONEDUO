shader_type spatial;
// Gerbe d'eau derrière une roue : une nappe translucide dont la brume défile
// vers l'arrière, dense au pneu et dissipée au bout. UV.y : 0 au pneu, 1 au bout.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://shaders/night_common.gdshaderinc"

uniform float amount = 0.0;
uniform vec3 tint : source_color = vec3(0.7, 0.75, 0.85);

void fragment() {
	vec2 q = vec2(UV.x * 5.0, UV.y * 3.0 - TIME * 9.0);
	float mist = night_noise(q) * 0.6 + night_noise(q * 2.3 + 7.0) * 0.4;
	float along = (1.0 - UV.y) * smoothstep(0.0, 0.08, UV.y);
	float across = 1.0 - abs(UV.x - 0.5) * 2.0;
	ALBEDO = tint;
	ALPHA = clamp(amount * mist * along * across * 2.6, 0.0, 0.85);
}
