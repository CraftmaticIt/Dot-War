shader_type canvas_item;
render_mode blend_add;

// Soft neon dot: bright core with radial falloff. Colour comes from the MultiMesh instance.
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float core = smoothstep(0.55, 0.1, d);
	float halo = smoothstep(1.0, 0.2, d) * 0.6;
	COLOR = vec4(COLOR.rgb * (core + halo) * 1.6, (core + halo) * COLOR.a);
}
