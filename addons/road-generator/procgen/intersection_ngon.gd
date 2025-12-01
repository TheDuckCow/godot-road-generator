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

const SegGeo := preload("res://addons/road-generator/procgen/segment_geo.gd")

# ------------------------------------------------------------------------------
#endregion
#region Abstract overrides
# ------------------------------------------------------------------------------

func generate_mesh(intersection: Node3D, edges: Array[RoadPoint], container: RoadContainer) -> Mesh:
	if not can_generate_mesh(intersection.transform, edges):
		push_error("Conditions for NGon mesh generation not met. Returning an empty mesh.")
		return Mesh.new() # Empty mesh.
	if edges.size() == 0:
		push_error("No edges provided for NGon mesh generation. Returning an empty mesh.")
		return Mesh.new() # Empty mesh.
	if not intersection.has_method("is_road_intersection"):
		push_error("intersection is not an intersection node. Returning an empty mesh.")
		return Mesh.new() # Empty mesh.
	return _generate_debug_mesh(intersection, edges, container)


func get_min_distance_from_intersection_point(rp: RoadPoint) -> float:
	# TODO TBD when mesh generation is implemented.
	return 0.0


# ------------------------------------------------------------------------------
#endregion
#region Generation functions
# ------------------------------------------------------------------------------



func _get_edge_facing(edge: RoadPoint, intersection: Node3D) -> _IntersectNGonFacing:
	if not intersection.has_method("is_road_intersection"):
		push_error("intersection is not an intersection node. Returning OTHER facing.")
		return _IntersectNGonFacing.OTHER

	var facing: _IntersectNGonFacing = _IntersectNGonFacing.OTHER
	# TODO detect the intersection node instead of checking for null.
	# The above todo (related to the two below) can only be done once
	# intersections are properly linked to road points.
	# TODO should be: if edge.get_node(edge.prior_pt_init) == intersection:
	if edge.get_node_or_null(edge.prior_pt_init) == intersection:
		facing = _IntersectNGonFacing.ORIGIN
	# TODO should be: elif edge.get_node(edge.next_pt_init) == intersection:
	elif edge.get_node_or_null(edge.next_pt_init) == intersection:
		facing = _IntersectNGonFacing.AWAY
	else:
		facing = _IntersectNGonFacing.OTHER
	return facing


## Generates a triangles from shoulders to intersection point,
## and triangles from an edge's shoulders to the intersection point.
## The end result is a very low-poly n-gon.[br][br]
## Edges MUST have been sorted by angle from intersection beforehand.
func _generate_debug_mesh(intersection: Node3D, edges: Array[RoadPoint], container: RoadContainer) -> Mesh:
	if not intersection.has_method("is_road_intersection"):
		push_error("intersection is not an intersection node. Returning an empty mesh.")
		return Mesh.new() # Empty mesh.

	var parent_transform: Transform3D = intersection.transform
	
	# origin is the intersection position, coords are relative to it.
	var surface_tool: SurfaceTool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	const TOPSIDE_SMOOTHING_GROUP = 1
	surface_tool.set_smooth_group(TOPSIDE_SMOOTHING_GROUP)

	const STOP_ROW_SIZE: float = 2.0  # TODO: make proportional to density
	
	# First, add an additional row of quads to each edge,
	# to give a UV space for stop marks or other markings.
	# We also prepare the intersection by storing appropriate
	# shoulder and gutter positions.

	## Array[Array[Vector3][2]]
	var edge_shoulders: Array[Array] = []
	## Array[Array[Vector3][2]]
	var edge_gutters: Array[Array] = []
	## Array[Array[Vector3][2]]
	var edge_road_sides: Array[Array] = []
	
	const uv_width := 0.125 # 1/8 for breakdown of texture.
	const uv_gutter_width := uv_width * SegGeo.UV_MID_SHOULDER
	var density := container.effective_density()

	for edge: RoadPoint in edges:
		var facing: _IntersectNGonFacing = _get_edge_facing(edge, intersection)
		if facing == _IntersectNGonFacing.OTHER:
			push_error("Unexpected RoadPoint state in IntersectionNGon mesh generation (next/prior points both null or defined on %s). Returning an empty mesh." % [edge.name])
			return Mesh.new() # Empty mesh.
		
		var lane_width: float = edge.lane_width
		var lanes_count = edge.lanes.size()
		var lanes_tot_width: float = lane_width * lanes_count
		var shoulder_offset_l: float = edge.shoulder_width_l
		var shoulder_offset_r: float = edge.shoulder_width_r
		var gutter: Vector2 = edge.gutter_profile
		
		# Aim for real-world texture proportions width:height of 2:1 matching texture,
		# but then the hight of 1 full UV is half the with across all lanes, so another 2x
		var uv_height := STOP_ROW_SIZE / lane_width / 8.0 # ratio of 1/4th down vs width of image to be square

		var perpendicular_v: Vector3 = (edge.transform.basis.x).normalized()
		var up_vector: Vector3 = (edge.transform.basis.y).normalized()
		var parallel_v: Vector3 = (edge.transform.basis.z).normalized()

		var road_side_l: Vector3 = edge.position
		var road_side_r: Vector3 = edge.position
		road_side_l -= perpendicular_v * (lanes_tot_width / 2.0)
		road_side_r += perpendicular_v * (lanes_tot_width / 2.0)

		var shoulder_l: Vector3 = road_side_l
		var shoulder_r: Vector3 = road_side_r
		shoulder_l -= shoulder_offset_l * perpendicular_v
		shoulder_r += shoulder_offset_r * perpendicular_v

		var gutter_l: Vector3 = shoulder_l + (gutter[0] * -perpendicular_v + gutter[1] * up_vector)
		var gutter_r: Vector3 = shoulder_r + (gutter[0] * perpendicular_v + gutter[1] * up_vector)

		if facing == _IntersectNGonFacing.ORIGIN:	
			parallel_v = -parallel_v

		var shoulder_l_stop: Vector3 = shoulder_l + parallel_v * STOP_ROW_SIZE
		var shoulder_r_stop: Vector3 = shoulder_r + parallel_v * STOP_ROW_SIZE
		var gutter_l_stop: Vector3 = gutter_l + parallel_v * STOP_ROW_SIZE
		var gutter_r_stop: Vector3 = gutter_r + parallel_v * STOP_ROW_SIZE
		var road_side_l_stop: Vector3 = road_side_l + parallel_v * STOP_ROW_SIZE
		var road_side_r_stop: Vector3 = road_side_r + parallel_v * STOP_ROW_SIZE

		if facing == _IntersectNGonFacing.ORIGIN:	
			edge_shoulders.append([shoulder_l_stop, shoulder_r_stop])
			edge_gutters.append([gutter_l_stop, gutter_r_stop])
			edge_road_sides.append([road_side_l_stop, road_side_r_stop])
		else: # facing == _IntersectNGonFacing.AWAY
			edge_shoulders.append([shoulder_r_stop, shoulder_l_stop])
			edge_gutters.append([gutter_r_stop, gutter_l_stop])
			edge_road_sides.append([road_side_r_stop, road_side_l_stop])

		# swap sides if needed
		if facing == _IntersectNGonFacing.ORIGIN:
			var temp: Vector3 = shoulder_l
			shoulder_l = shoulder_r
			shoulder_r = temp
			temp = shoulder_l_stop
			shoulder_l_stop = shoulder_r_stop
			shoulder_r_stop = temp
			temp = gutter_l
			gutter_l = gutter_r
			gutter_r = temp
			temp = gutter_l_stop
			gutter_l_stop = gutter_r_stop
			gutter_r_stop = temp
			temp = road_side_l
			road_side_l = road_side_r
			road_side_r = temp
			temp = road_side_l_stop
			road_side_l_stop = road_side_r_stop
			road_side_r_stop = temp

		# Left gutter quad
		surface_tool.set_uv(Vector2(0.0, uv_height))
		surface_tool.add_vertex(gutter_l_stop - parent_transform.origin)
		surface_tool.set_uv(Vector2(0.0, 0.0))
		surface_tool.add_vertex(gutter_l - parent_transform.origin)
		surface_tool.set_uv(Vector2(uv_gutter_width, 0.0))
		surface_tool.add_vertex(shoulder_l - parent_transform.origin)

		surface_tool.set_uv(Vector2(uv_gutter_width, uv_height))
		surface_tool.add_vertex(shoulder_l_stop - parent_transform.origin)
		surface_tool.set_uv(Vector2(0.0, uv_height))
		surface_tool.add_vertex(gutter_l_stop - parent_transform.origin)
		surface_tool.set_uv(Vector2(uv_gutter_width, 0.0))
		surface_tool.add_vertex(shoulder_l - parent_transform.origin)

		# Left shoulder quad
		surface_tool.set_uv(Vector2(uv_width, uv_height))
		surface_tool.add_vertex(road_side_l_stop - parent_transform.origin)
		surface_tool.set_uv(Vector2(uv_gutter_width, uv_height))
		surface_tool.add_vertex(shoulder_l_stop - parent_transform.origin)
		surface_tool.set_uv(Vector2(uv_gutter_width, 0.0))
		surface_tool.add_vertex(shoulder_l - parent_transform.origin)

		surface_tool.set_uv(Vector2(uv_width, 0.0))
		surface_tool.add_vertex(road_side_l - parent_transform.origin)
		surface_tool.set_uv(Vector2(uv_width, uv_height))
		surface_tool.add_vertex(road_side_l_stop - parent_transform.origin)
		surface_tool.set_uv(Vector2(uv_gutter_width, 0.0))
		surface_tool.add_vertex(shoulder_l - parent_transform.origin)

		# Lanes quads
		for i in range(lanes_count):
			var current_perpendicular_v: Vector3 = perpendicular_v
			if facing == _IntersectNGonFacing.ORIGIN:
				current_perpendicular_v = -perpendicular_v
			var lane_left_side: Vector3 = road_side_l + current_perpendicular_v * (lane_width * i)
			var lane_right_side: Vector3 = road_side_l + current_perpendicular_v * (lane_width * (i + 1))
			var lane_left_side_stop: Vector3 = lane_left_side + parallel_v * STOP_ROW_SIZE
			var lane_right_side_stop: Vector3 = lane_right_side + parallel_v * STOP_ROW_SIZE

			# Lane quad
			var u_near := uv_width*6
			var u_far := uv_width*7
			
			surface_tool.set_uv(Vector2(uv_width*7, uv_height))
			surface_tool.add_vertex(lane_left_side - parent_transform.origin)
			surface_tool.set_uv(Vector2(uv_width*6, uv_height))
			surface_tool.add_vertex(lane_right_side - parent_transform.origin)
			surface_tool.set_uv(Vector2(uv_width*6, 0.0))
			surface_tool.add_vertex(lane_right_side_stop - parent_transform.origin)

			surface_tool.set_uv(Vector2(uv_width*7, uv_height))
			surface_tool.add_vertex(lane_left_side - parent_transform.origin)
			surface_tool.set_uv(Vector2(uv_width*6, 0.0))
			surface_tool.add_vertex(lane_right_side_stop - parent_transform.origin)
			surface_tool.set_uv(Vector2(uv_width*7, 0.0))
			surface_tool.add_vertex(lane_left_side_stop - parent_transform.origin)

		# Right shoulder quad
		surface_tool.set_uv(Vector2(uv_width, uv_height))
		surface_tool.add_vertex(road_side_r_stop - parent_transform.origin)
		surface_tool.set_uv(Vector2(uv_width, 0.0))
		surface_tool.add_vertex(road_side_r - parent_transform.origin)
		surface_tool.set_uv(Vector2(uv_gutter_width, 0.0))
		surface_tool.add_vertex(shoulder_r - parent_transform.origin)

		surface_tool.set_uv(Vector2(uv_gutter_width, uv_height))
		surface_tool.add_vertex(shoulder_r_stop - parent_transform.origin)
		surface_tool.set_uv(Vector2(uv_width, uv_height))
		surface_tool.add_vertex(road_side_r_stop - parent_transform.origin)
		surface_tool.set_uv(Vector2(uv_gutter_width, 0.0))
		surface_tool.add_vertex(shoulder_r - parent_transform.origin)

		# Right gutter quad
		surface_tool.set_uv(Vector2(0.0, 0.0))
		surface_tool.add_vertex(gutter_r - parent_transform.origin)
		surface_tool.set_uv(Vector2(0.0, uv_height))
		surface_tool.add_vertex(gutter_r_stop - parent_transform.origin)
		surface_tool.set_uv(Vector2(uv_gutter_width, 0.0))
		surface_tool.add_vertex(shoulder_r - parent_transform.origin)

		surface_tool.set_uv(Vector2(0.0, uv_height))
		surface_tool.add_vertex(gutter_r_stop - parent_transform.origin)
		surface_tool.set_uv(Vector2(uv_gutter_width, uv_height))
		surface_tool.add_vertex(shoulder_r_stop - parent_transform.origin)
		surface_tool.set_uv(Vector2(uv_gutter_width, 0.0))
		surface_tool.add_vertex(shoulder_r - parent_transform.origin)

	# Then, connect edges with its siblings (gutters and shoulders quads).
	# At the same time, create triangles from shoulders to intersection point;
	# to form a triangle fan filling the intersection.

	var iteration_i = 0
	for sides in edge_road_sides:
		var side_l: Vector3 = sides[0]
		var side_r: Vector3 = sides[1]

		# add vertices

		# add "road edge" triangle
		# Below is ((right-orign)-(left-origin)).length() expanded out
		# This is ((side_l) + (side_r))/2 expanded
		var mid_point := (side_l + side_r - parent_transform.origin*2)/2.0
		# Distance from edge to the intersection center
		var sibling_dist:float = mid_point.length()
		var sibling_width:float = (side_r - side_l).length()
		var v_dist: float = sibling_width / 16.0
		# find center point between left/right, and get length to center
		var center_dist := sibling_dist / 2.0 / sibling_width
		surface_tool.set_uv(Vector2(uv_width*7, 0.0))
		surface_tool.add_vertex(side_r - parent_transform.origin)
		surface_tool.set_uv(Vector2(uv_width*6, 0.0))
		surface_tool.add_vertex(side_l - parent_transform.origin)
		surface_tool.set_uv(Vector2(uv_width*6.5, center_dist))
		surface_tool.add_vertex(Vector3.ZERO)

		# add "sibling" triangle
		# /!\ /!\ /!\ only support nodes in a very specific order
		# (edges should be sorted by the caller)
		if (edge_shoulders.size() > 1):
			var next_iteration_i: int = (iteration_i + 1) % edge_shoulders.size()
			var next_side_r: Vector3 = edge_road_sides[next_iteration_i][1]
			# This is ((next_side_r) + (side_l))/2 expanded
			mid_point = (next_side_r + side_l - parent_transform.origin*2.0)/2.0
			sibling_dist = mid_point.length()
			sibling_width = (next_side_r - side_l).length()
			var v_span_dist: float = sibling_dist / 2.0 / sibling_width

			surface_tool.set_uv(Vector2(uv_width*6.5, 0.0))
			surface_tool.add_vertex(Vector3.ZERO)
			surface_tool.set_uv(Vector2(uv_width*7, v_span_dist))
			surface_tool.add_vertex(side_l - parent_transform.origin)
			surface_tool.set_uv(Vector2(uv_width*6, v_span_dist))
			surface_tool.add_vertex(next_side_r - parent_transform.origin)

			# also add the gutter profile and the shoulder offset
			# on the intersection exterior border
			# (quad from one edge's gutter to the next edge's gutter, same for shoulders).

			# shoulder quad
			var shoulder_l: Vector3 = edge_shoulders[iteration_i][0]
			var next_shoulder_r: Vector3 = edge_shoulders[next_iteration_i][1]

			surface_tool.set_uv(Vector2(uv_gutter_width, 0.0))
			surface_tool.add_vertex(shoulder_l - parent_transform.origin)
			surface_tool.set_uv(Vector2(uv_gutter_width, v_dist))
			surface_tool.add_vertex(next_shoulder_r - parent_transform.origin)
			surface_tool.set_uv(Vector2(uv_width, v_dist))
			surface_tool.add_vertex(next_side_r - parent_transform.origin)

			surface_tool.set_uv(Vector2(uv_width, 0.0))
			surface_tool.add_vertex(side_l - parent_transform.origin)
			surface_tool.set_uv(Vector2(uv_gutter_width, 0.0))
			surface_tool.add_vertex(shoulder_l - parent_transform.origin)
			surface_tool.set_uv(Vector2(uv_width, v_dist))
			surface_tool.add_vertex(next_side_r - parent_transform.origin)

			# gutter quad
			var current_gutter_l: Vector3 = edge_gutters[iteration_i][0]
			var next_gutter_r: Vector3 = edge_gutters[next_iteration_i][1]

			surface_tool.set_uv(Vector2(uv_gutter_width, 0.0))
			surface_tool.add_vertex(shoulder_l - parent_transform.origin)
			surface_tool.set_uv(Vector2(0.0, 0.0))
			surface_tool.add_vertex(current_gutter_l - parent_transform.origin)
			surface_tool.set_uv(Vector2(uv_gutter_width, v_dist))
			surface_tool.add_vertex(next_shoulder_r - parent_transform.origin)
			
			surface_tool.set_uv(Vector2(uv_gutter_width, v_dist))
			surface_tool.add_vertex(next_shoulder_r - parent_transform.origin)
			surface_tool.set_uv(Vector2(0.0, 0.0))
			surface_tool.add_vertex(current_gutter_l - parent_transform.origin)
			surface_tool.set_uv(Vector2(0.0, v_dist))
			surface_tool.add_vertex(next_gutter_r - parent_transform.origin)

		iteration_i += 1
	
	surface_tool.index()
	var material: Material = container.effective_surface_material()
	if material:
		surface_tool.set_material(material)
	surface_tool.generate_normals()
	var mesh: ArrayMesh = surface_tool.commit()  # should be MeshInstance3D?
	#mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh


#endregion
# ------------------------------------------------------------------------------
