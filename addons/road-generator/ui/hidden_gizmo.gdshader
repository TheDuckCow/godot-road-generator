shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_disabled, unshaded, depth_test_disabled, ambient_light_disabled, fog_disabled;
// Special shader to just be transparent/not influence the scene in any way
//
// Meant to be assigned to a copy of the road mesh gizmo, the mesh must be visualized
// in order for it to be selectable in the UI, but we don't want to render anything
// since we already visualize the road mesh itself.

void fragment() {
	discard;
}
