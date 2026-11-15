shader_type canvas_item;
// A red glow around the screen edges. ResourcesService pulses `intensity` slowly while a
// resource is low. The middle of the screen stays clear so nothing becomes hard to read.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.95, 0.05, 0.05, 1.0);

void fragment() {
	float edge = smoothstep(0.3, 0.85, distance(UV, vec2(0.5)) * 1.45);
	COLOR = vec4(tint.rgb, edge * intensity);
}
