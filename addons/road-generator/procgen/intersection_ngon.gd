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

func generate_mesh(intersection: Transform3D, edges: Array[RoadPoint]) -> Mesh:
	print("mesh?")
	if not can_generate_mesh(intersection, edges):
		return ArrayMesh.new() # Empty mesh.
	if edges.size() == 0:
		return ArrayMesh.new() # Empty mesh.
	print("mesh.")
	return _generate_debug_mesh(intersection, edges)

func get_min_distance_from_intersection_point(rp: RoadPoint) -> float:
	# TODO TBD when mesh generation is implemented.
	return 0.0


## Generates a triangles from shoulders to intersection point,
## and triangles from an edge's shoulders to the intersection point.
## The end result is a very low-poly n-gon.
func _generate_debug_mesh(intersection: Transform3D, edges: Array[RoadPoint]) -> Mesh:
	## Array[Array[Vector3[2]]]
	var edge_shoulders: Array[Array] = []
	for edge in edges:
		var facing: _IntersectNGonFacing = _IntersectNGonFacing.OTHER
		print(edge.next_pt_init)
		print(edge.prior_pt_init)
		if edge.next_pt_init.is_empty():
			facing = _IntersectNGonFacing.AWAY
		elif edge.prior_pt_init.is_empty():
			facing = _IntersectNGonFacing.ORIGIN
		else:
			facing = _IntersectNGonFacing.OTHER
		
		if facing == _IntersectNGonFacing.OTHER:
			push_error("Unexpected RoadPoint state in IntersectionNGon mesh generation (next/prior points both null or defined on %s). Returning an empty mesh." % [edge.name])
			return ArrayMesh.new() # Empty mesh.

		var edge_road_width: float = edge.get_width()
		# assuming the point is the center, and shoulders are
		# at equal distances to it.
		var left_shoulder: Vector3 = edge.global_position
		var right_shoulder: Vector3 = edge.global_position
		var perpendicular_vector: Vector3 = (edge.global_transform.basis.x).normalized()
		left_shoulder -= perpendicular_vector * (edge_road_width / 2.0)
		right_shoulder += perpendicular_vector * (edge_road_width / 2.0)
		if facing == _IntersectNGonFacing.ORIGIN:	
			edge_shoulders.append([left_shoulder, right_shoulder])
		else: # facing == _IntersectNGonFacing.AWAY
			edge_shoulders.append([right_shoulder, left_shoulder])


	# mesh indices: [[1,2], [3,4], ...] with 0 for the center point
	# origin is the intersection position, coords are relative to it.
	var surface_tool: SurfaceTool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	var iteration_i = 0
	for shoulders in edge_shoulders:
		var left_shoulder: Vector3 = shoulders[0]
		var right_shoulder: Vector3 = shoulders[1]
		var left_index: int = iteration_i * 2 + 1
		var right_index: int = iteration_i * 2 + 2

		# add vertices

		# add "edge" triangle
		surface_tool.add_vertex(Vector3.ZERO)
		surface_tool.add_vertex(right_shoulder - intersection.origin)
		surface_tool.add_vertex(left_shoulder - intersection.origin)

		# add "sibling" triangle
		if (edge_shoulders.size() > 1):
			var next_iteration_i: int = (iteration_i + 1) % edge_shoulders.size()

			surface_tool.add_vertex(Vector3.ZERO)
			surface_tool.add_vertex(left_shoulder - intersection.origin)
			surface_tool.add_vertex(edge_shoulders[next_iteration_i][1] - intersection.origin)

		iteration_i += 1
	
	# surface_tool.index()
	surface_tool.generate_normals()
	surface_tool.set_material(StandardMaterial3D.new())
	var mesh: ArrayMesh = surface_tool.commit()
	print("meh")
	return mesh
