shader_type canvas_item;
// Blurs the screen and darkens its edges as the player's oxygen runs low.
// `blur` is driven from ResourcesService: 0 = no effect, 1 = strongest.
// The maximums are kept small so interfaces underneath stay readable.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

uniform float blur : hint_range(0.0, 1.0) = 0.0;
// Largest sample spread in pixels.
uniform float max_radius = 2.5;
// Largest mipmap level used for the base blur.
uniform float max_lod = 1.2;
// How much the screen edges darken at full strength.
uniform float vignette_strength = 0.5;

void fragment() {
	float lod = blur * max_lod;
	vec2 spread = SCREEN_PIXEL_SIZE * blur * max_radius;

	// Center sample plus a ring of 8 around it.
	vec3 sum = textureLod(screen_texture, SCREEN_UV, lod).rgb;
	for (int i = 0; i < 8; i++) {
		float angle = float(i) * 0.785398;
		sum += textureLod(screen_texture, SCREEN_UV + vec2(cos(angle), sin(angle)) * spread, lod).rgb;
	}
	vec3 color = sum / 9.0;

	float edge = smoothstep(0.35, 0.9, distance(SCREEN_UV, vec2(0.5)));
	color = mix(color, color * vec3(0.5, 0.55, 0.65), edge * blur * vignette_strength);

	COLOR = vec4(color, 1.0);
}
