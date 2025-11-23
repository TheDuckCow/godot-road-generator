@tool
@icon("res://addons/road-generator/resources/road_intersection.png")

class_name IntersectionNGon
extends IntersectionSettings
## Defines an intersection where each edge is connected
## to its siblings with curve shoulders, forming a filled n-gon.

# ------------------------------------------------------------------------------
#region Signals/Enums/Const/Export/Vars
# ------------------------------------------------------------------------------

enum _IntersectNGonFacing {
	ORIGIN,
	AWAY,
	OTHER
}

# ------------------------------------------------------------------------------
#endregion
# ------------------------------------------------------------------------------

func generate_mesh(parent_transform: Transform3D, edges: Array[RoadPoint], container: RoadContainer) -> Mesh:
	if not can_generate_mesh(parent_transform, edges):
		push_error("Conditions for NGon mesh generation not met. Returning an empty mesh.")
		return Mesh.new() # Empty mesh.
	if edges.size() == 0:
		push_error("No edges provided for NGon mesh generation. Returning an empty mesh.")
		return Mesh.new() # Empty mesh.
	return _generate_debug_mesh(parent_transform, edges, container)


func get_min_distance_from_intersection_point(rp: RoadPoint) -> float:
	# TODO TBD when mesh generation is implemented.
	return 0.0


## Generates a triangles from shoulders to intersection point,
## and triangles from an edge's shoulders to the intersection point.
## The end result is a very low-poly n-gon.
func _generate_debug_mesh(parent_transform: Transform3D, edges: Array[RoadPoint], container: RoadContainer) -> Mesh:
	## Array[Array[Vector3][2]]
	var edge_shoulders: Array[Array] = []
	## Array[Array[Vector3][2]]
	var edge_gutters: Array[Array] = []
	for edge: RoadPoint in edges:
		var facing: _IntersectNGonFacing = _IntersectNGonFacing.OTHER
		# TODO: needs to be if edge.get_node(edge.prior_pt_init) == self.intersection
		if edge.next_pt_init.is_empty():
			facing = _IntersectNGonFacing.AWAY
		# TODO: needs to be if edge.get_node(edge.next_pt_init) == self.intersection
		elif edge.prior_pt_init.is_empty():
			facing = _IntersectNGonFacing.ORIGIN
		else:
			facing = _IntersectNGonFacing.OTHER
		
		if facing == _IntersectNGonFacing.OTHER:
			push_error("Unexpected RoadPoint state in IntersectionNGon mesh generation (next/prior points both null or defined on %s). Returning an empty mesh." % [edge.name])
			return Mesh.new() # Empty mesh.

		var edge_road_width: float = edge.get_width()
		# assuming the point is the center, and shoulders are
		# at equal distances to it.
		var left_shoulder: Vector3 = edge.global_position
		var right_shoulder: Vector3 = edge.global_position
		var perpendicular_vector: Vector3 = (edge.global_transform.basis.x).normalized()
		var up_vector: Vector3 = (edge.global_transform.basis.y).normalized()
		left_shoulder -= perpendicular_vector * (edge_road_width / 2.0)
		right_shoulder += perpendicular_vector * (edge_road_width / 2.0)
		if facing == _IntersectNGonFacing.ORIGIN:	
			edge_shoulders.append([left_shoulder, right_shoulder])
		else: # facing == _IntersectNGonFacing.AWAY
			edge_shoulders.append([right_shoulder, left_shoulder])
		var gutter = edge.gutter_profile
		var gutter_left = left_shoulder + (gutter[0] * -perpendicular_vector + gutter[1] * up_vector)
		var gutter_right = right_shoulder + (gutter[0] * perpendicular_vector + gutter[1] * up_vector)
		if facing == _IntersectNGonFacing.ORIGIN:
			edge_gutters.append([gutter_left, gutter_right])
		else: # facing == _IntersectNGonFacing.AWAY
			edge_gutters.append([gutter_right, gutter_left])


	# mesh indices: [[1,2], [3,4], ...] with 0 for the center point
	# origin is the intersection position, coords are relative to it.
	var surface_tool: SurfaceTool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	const TOPSIDE_SMOOTHING_GROUP = 1
	surface_tool.set_smooth_group(TOPSIDE_SMOOTHING_GROUP)

	var iteration_i = 0
	for shoulders in edge_shoulders:
		var left_shoulder: Vector3 = shoulders[0]
		var right_shoulder: Vector3 = shoulders[1]
		var left_index: int = iteration_i * 2 + 1
		var right_index: int = iteration_i * 2 + 2

		# add vertices

		# add "edge" triangle
		surface_tool.set_uv(Vector2(0.0, 0.0))
		surface_tool.add_vertex(Vector3.ZERO)
		surface_tool.set_uv(Vector2(0.0, 0.0))
		surface_tool.add_vertex(right_shoulder - parent_transform.origin)
		surface_tool.set_uv(Vector2(0.0, 0.0))
		surface_tool.add_vertex(left_shoulder - parent_transform.origin)

		# add "sibling" triangle
		# FIXME: only support nodes in a very specific order
		# (sort edges by angle from intersection and given axis?)
		if (edge_shoulders.size() > 1):
			var next_iteration_i: int = (iteration_i + 1) % edge_shoulders.size()
			var next_right_shoulder: Vector3 = edge_shoulders[next_iteration_i][1]
			var current_left_gutter: Vector3 = edge_gutters[iteration_i][0]
			var next_right_gutter: Vector3 = edge_gutters[next_iteration_i][1]

			surface_tool.set_uv(Vector2(0.0, 0.0))
			surface_tool.add_vertex(Vector3.ZERO)
			surface_tool.set_uv(Vector2(0.0, 0.0))
			surface_tool.add_vertex(left_shoulder - parent_transform.origin)
			surface_tool.set_uv(Vector2(0.0, 0.0))
			surface_tool.add_vertex(next_right_shoulder - parent_transform.origin)

			# also add the gutter profile on the intersection exterior border
			# (rectangle from one edge's shoulder and gutter to the next edge's
			# shoulder and gutter)
			surface_tool.set_uv(Vector2(0.0, 0.0))
			surface_tool.add_vertex(left_shoulder - parent_transform.origin)
			surface_tool.set_uv(Vector2(0.0, 0.0))
			surface_tool.add_vertex(current_left_gutter - parent_transform.origin)
			surface_tool.set_uv(Vector2(0.0, 0.0))
			surface_tool.add_vertex(next_right_shoulder - parent_transform.origin)
			
			surface_tool.set_uv(Vector2(0.0, 0.0))
			surface_tool.add_vertex(next_right_shoulder - parent_transform.origin)
			surface_tool.set_uv(Vector2(0.0, 0.0))
			surface_tool.add_vertex(current_left_gutter - parent_transform.origin)
			surface_tool.set_uv(Vector2(0.0, 0.0))
			surface_tool.add_vertex(next_right_gutter - parent_transform.origin)

		iteration_i += 1
	
	surface_tool.index()
	var material: Material = container.effective_surface_material()
	if material:
		surface_tool.set_material(material)
	surface_tool.generate_normals()
	var mesh: ArrayMesh = surface_tool.commit()  # should be MeshInstance3D?
	#mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh
