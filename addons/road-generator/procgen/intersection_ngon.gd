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

## Model to store the different points useful for mesh generation.
class EdgePositions:
	## Array[Array[Vector3][2]]
	var edge_shoulders: Array[Array] = []
	## Array[Array[Vector3][2]]
	var edge_gutters: Array[Array] = []
	## Array[Array[Vector3][2]]
	var edge_road_sides: Array[Array] = []
	func _init() -> void:
		edge_shoulders = []
		edge_gutters = []
		edge_road_sides = []


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

	# TODO if low poly:
	# return _generate_debug_mesh(intersection, edges, container)
	return _generate_full_mesh(intersection, edges, container)


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

func _generate_stop_rows_and_get_positions(edges: Array[RoadPoint], intersection: Node3D, stop_row_size: float, surface_tool: SurfaceTool, uv_width: float, uv_gutter_width: float) -> EdgePositions:
	if not intersection.has_method("is_road_intersection"):
		push_error("intersection is not an intersection node. Cannot generate stop rows on mesh.")
		return null

	var edge_positions: EdgePositions = EdgePositions.new()
	var parent_transform: Transform3D = intersection.transform

	for edge: RoadPoint in edges:
		var facing: _IntersectNGonFacing = _get_edge_facing(edge, intersection)
		if facing == _IntersectNGonFacing.OTHER:
			push_error("Unexpected RoadPoint state in IntersectionNGon mesh generation (next/prior points both null or defined on %s). Returning an empty mesh." % [edge.name])
			return null
		
		var lane_width: float = edge.lane_width
		var lanes_count = edge.lanes.size()
		var lanes_tot_width: float = lane_width * lanes_count
		var shoulder_offset_l: float = edge.shoulder_width_l
		var shoulder_offset_r: float = edge.shoulder_width_r
		var gutter: Vector2 = edge.gutter_profile
		
		# Aim for real-world texture proportions width:height of 2:1 matching texture,
		# but then the hight of 1 full UV is half the with across all lanes, so another 2x
		var uv_height := stop_row_size / lane_width / 8.0 # ratio of 1/4th down vs width of image to be square

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

		var shoulder_l_stop: Vector3 = shoulder_l + parallel_v * stop_row_size
		var shoulder_r_stop: Vector3 = shoulder_r + parallel_v * stop_row_size
		var gutter_l_stop: Vector3 = gutter_l + parallel_v * stop_row_size
		var gutter_r_stop: Vector3 = gutter_r + parallel_v * stop_row_size
		var road_side_l_stop: Vector3 = road_side_l + parallel_v * stop_row_size
		var road_side_r_stop: Vector3 = road_side_r + parallel_v * stop_row_size

		if facing == _IntersectNGonFacing.ORIGIN:	
			edge_positions.edge_shoulders.append([shoulder_l_stop, shoulder_r_stop])
			edge_positions.edge_gutters.append([gutter_l_stop, gutter_r_stop])
			edge_positions.edge_road_sides.append([road_side_l_stop, road_side_r_stop])
		else: # facing == _IntersectNGonFacing.AWAY
			edge_positions.edge_shoulders.append([shoulder_r_stop, shoulder_l_stop])
			edge_positions.edge_gutters.append([gutter_r_stop, gutter_l_stop])
			edge_positions.edge_road_sides.append([road_side_r_stop, road_side_l_stop])

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
			var lane_left_side_stop: Vector3 = lane_left_side + parallel_v * stop_row_size
			var lane_right_side_stop: Vector3 = lane_right_side + parallel_v * stop_row_size

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

	return edge_positions


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
	
	const uv_width := 0.125 # 1/8 for breakdown of texture.
	const uv_gutter_width := uv_width * SegGeo.UV_MID_SHOULDER
	var density := container.effective_density()

	var edge_positions: EdgePositions = _generate_stop_rows_and_get_positions(edges, intersection, STOP_ROW_SIZE, surface_tool, uv_width, uv_gutter_width)
	if edge_positions == null:
		push_error("Failed to generate stop rows and positions for IntersectionNGon mesh generation. Returning an empty mesh.")
		return Mesh.new() # Empty mesh.
	var edge_shoulders: Array[Array] = edge_positions.edge_shoulders
	var edge_gutters: Array[Array] = edge_positions.edge_gutters
	var edge_road_sides: Array[Array] = edge_positions.edge_road_sides

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

func _generate_full_mesh(intersection: Node3D, edges: Array[RoadPoint], container: RoadContainer) -> Mesh:
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
	
	const uv_width := 0.125 # 1/8 for breakdown of texture.
	const uv_gutter_width := uv_width * SegGeo.UV_MID_SHOULDER
	var density := container.effective_density()

	var edge_positions: EdgePositions = _generate_stop_rows_and_get_positions(edges, intersection, STOP_ROW_SIZE, surface_tool, uv_width, uv_gutter_width)
	if edge_positions == null:
		push_error("Failed to generate stop rows and positions for IntersectionNGon mesh generation. Returning an empty mesh.")
		return Mesh.new() # Empty mesh.
	var edge_shoulders: Array[Array] = edge_positions.edge_shoulders
	var edge_gutters: Array[Array] = edge_positions.edge_gutters
	var edge_road_sides: Array[Array] = edge_positions.edge_road_sides

	# Then, connect edges with its siblings (gutters and shoulders quads).
	# To do so we use a bezier curve (2 points) through a Curve3D
	# for smoothness and somewhat robust easing.

	# /!\ /!\ /!\ only support nodes in a very specific order
	# (edges should be sorted by the caller)

	# excluded = do not include vertices directly connecting to road edges.
	# Array[Array[Vector3]]
	var to_next_edge_vertices_excluded: Array[Array] = []
	var to_next_edge_directions_excluded: Array[Array] = []
	var edge_facing: Array[_IntersectNGonFacing] = []

	const CONTROL_LENGTH_DIVIDER = 5.0
	for i in range(edges.size()):
		var edge: RoadPoint = edges[i]
		var next_i: int = (i + 1) % edge_shoulders.size()
		var next_edge: RoadPoint = edges[next_i]
		var gutter_to_gutter_distance: float = (edge_gutters[next_i][1] - edge_gutters[i][0]).length()

		var control_length_from = min(
			edge.transform.origin.distance_to(parent_transform.origin) / CONTROL_LENGTH_DIVIDER,
			gutter_to_gutter_distance / CONTROL_LENGTH_DIVIDER
		)
		var control_length_to = min(
			next_edge.transform.origin.distance_to(parent_transform.origin) / CONTROL_LENGTH_DIVIDER,
			gutter_to_gutter_distance / CONTROL_LENGTH_DIVIDER
		)

		# NOTE: curve could be used later on for decoration paths.

		var parallel_v_from: Vector3 = (edge.transform.basis.z).normalized()

		var i_facing: _IntersectNGonFacing = _get_edge_facing(edge, intersection)
		edge_facing.append(i_facing)
		var i_facing_coefficient = 1
		var i1_facing: _IntersectNGonFacing = _get_edge_facing(next_edge, intersection)
		var i1_facing_coefficient = 1
		if i_facing == _IntersectNGonFacing.ORIGIN:
			i_facing_coefficient = -1
		if i1_facing == _IntersectNGonFacing.ORIGIN:
			i1_facing_coefficient = -1
		var curve = Curve3D.new()
		curve.bake_interval = density

		curve.add_point(
			edge_gutters[i][0],
			Vector3.ZERO,
			(edge.basis.z.normalized() * control_length_from * i_facing_coefficient)
		)
		curve.add_point(
			edge_gutters[next_i][1],
			(next_edge.basis.z.normalized() * control_length_to * i1_facing_coefficient),
			Vector3.ZERO
		)

		var baked_points: PackedVector3Array = curve.get_baked_points()
		var baked_up_vectors: PackedVector3Array = curve.get_baked_up_vectors()
		
		var from_gutter: Vector2 = edge.gutter_profile
		var to_gutter: Vector2 = next_edge.gutter_profile

		# create shoulder/gutter and shoulder/lane quads using point i and i+1
		for j in range(baked_points.size() - 1):
			var i_gutter: Vector3 = baked_points[j]
			var i1_gutter: Vector3 = baked_points[j + 1]
			var i_shoulder: Vector3 = Vector3.ZERO
			var i1_shoulder: Vector3 = Vector3.ZERO
			var i_lane: Vector3 = Vector3.ZERO
			var i1_lane: Vector3 = Vector3.ZERO
			
			var this_up: Vector3 = edge.transform.basis.y.normalized()
			var next_up: Vector3 = next_edge.transform.basis.y.normalized()

			## First vector is the shoulder point, second is the direction of the vertices column
			var get_shoulder_and_dir: Callable = func (index) -> Array[Vector3]:
				var prev_p = baked_points[index - 1]
				var this_p = baked_points[index]
				var next_p = baked_points[index + 1]

				var gutter_profile: Vector2 = lerp(from_gutter, to_gutter, float(index) / float(baked_points.size() - 1))

				var dir_v: Vector3 = (next_p - prev_p).normalized()
				var blended_up: Vector3 = this_up.slerp(next_up, float(index) / float(baked_points.size() - 1)).normalized() 
				var perpendicular_v: Vector3 = dir_v.cross(blended_up).normalized()
				return [
					this_p + perpendicular_v * gutter_profile[0] - blended_up * gutter_profile[1],
					perpendicular_v
				]

			to_next_edge_vertices_excluded.append([])
			to_next_edge_directions_excluded.append([])

			if (j == 0):
				i_shoulder = edge_shoulders[i][0]
				i_lane = edge_road_sides[i][0]
			else:
				var result = get_shoulder_and_dir.call(j)
				i_shoulder = result[0]
				var dir: Vector3 = result[1]
				i_lane = i_shoulder + dir * lerp(edge.shoulder_width_l, next_edge.shoulder_width_r, float(j) / float(baked_points.size() - 1))
			
			if (j + 1 == baked_points.size() - 1):
				i1_shoulder = edge_shoulders[next_i][1]
				i1_lane = edge_road_sides[next_i][1]
			else:
				var result = get_shoulder_and_dir.call(j + 1)
				i1_shoulder = result[0]
				var dir: Vector3 = result[1]
				i1_lane = i1_shoulder + dir * lerp(edge.shoulder_width_l, next_edge.shoulder_width_r, float(j + 1) / float(baked_points.size() - 1))

				to_next_edge_vertices_excluded[i].append(i1_lane)
				to_next_edge_directions_excluded[i].append(dir)

			# gutter/shoulder quad
			# TODO UV
			surface_tool.add_vertex(i_shoulder - parent_transform.origin)
			surface_tool.add_vertex(i_gutter - parent_transform.origin)
			surface_tool.add_vertex(i1_shoulder - parent_transform.origin)

			surface_tool.add_vertex(i1_shoulder - parent_transform.origin)
			surface_tool.add_vertex(i_gutter - parent_transform.origin)
			surface_tool.add_vertex(i1_gutter - parent_transform.origin)

			# shoulder/lane quad
			# TODO UV
			surface_tool.add_vertex(i_lane - parent_transform.origin)
			surface_tool.add_vertex(i_shoulder - parent_transform.origin)
			surface_tool.add_vertex(i1_lane - parent_transform.origin)

			surface_tool.add_vertex(i1_lane - parent_transform.origin)
			surface_tool.add_vertex(i_shoulder - parent_transform.origin)
			surface_tool.add_vertex(i1_shoulder - parent_transform.origin)
			
	
	# Now, we want to connect lanes to each other whenever there is a matching lane
	# on the next edge. We do this until we fail to find a matching lane for every edge.
	# This process aim to create a UV friendly continuous surface between edges.

	var successes: Array[bool] = []
	var remaining_lanes: Array[int] = []
	var taken_slots_from_left: Array[int] = []
	var taken_slots_from_right: Array[int] = []
	for edge in edges:
		successes.append(true)
		remaining_lanes.append(edge.lanes.size())
		taken_slots_from_left.append(0)
		taken_slots_from_right.append(0)

	var while_i: int = 0
	const MIN_LANES_GAP: int = 1

	## Array[Array[Vector3]]
	var to_next_edge_border_vertices_included: Array[Array] = []
	for i in range(edges.size()):
		to_next_edge_border_vertices_included.append([])
		to_next_edge_border_vertices_included[i].append(edge_road_sides[i][0])
		for j in range(to_next_edge_vertices_excluded[i].size()):
			to_next_edge_border_vertices_included[i].append(to_next_edge_vertices_excluded[i][j])
		to_next_edge_border_vertices_included[i].append(edge_road_sides[(i + 1) % edges.size()][1])

	while true in successes:
		var edge: RoadPoint = edges[while_i]
		var next_i: int = (while_i + 1) % edges.size()
		var next_edge: RoadPoint = edges[next_i]
		var possible: bool = remaining_lanes[while_i] > MIN_LANES_GAP and remaining_lanes[next_i] > MIN_LANES_GAP
		if possible:
			var this_lane_width = edge.lane_width
			var next_lane_width = next_edge.lane_width

			# build quads from i to i+1
			# size excluded + 1 quads to build
			for j in range(to_next_edge_vertices_excluded[while_i].size() + 1):
				# print("Building lane quad between edge %d and %d, vertex slot %d, vertices: %d, directions: %d" % [i, next_i, j, to_next_edge_vertices_excluded.size(), to_next_edge_directions_excluded.size()])
				# ext = closest to shoulder/gutter
				var ext_vertex_i: Vector3 = Vector3.ZERO
				var ext_vertex_i1: Vector3 = Vector3.ZERO
				var int_vertex_i: Vector3 = Vector3.ZERO
				var int_vertex_i1: Vector3 = Vector3.ZERO
				var dir_i: Vector3 = Vector3.ZERO
				var dir_i1: Vector3 = Vector3.ZERO
				var lane_width_i: float = lerp(this_lane_width, next_lane_width, float(j) / float(to_next_edge_vertices_excluded[while_i].size() + 1))
				var lane_width_i1: float = lerp(this_lane_width, next_lane_width, float(j + 1) / float(to_next_edge_vertices_excluded[while_i].size() + 1))

				var this_edge_dir = edge.transform.basis.x.normalized()
				if edge_facing[while_i] == _IntersectNGonFacing.AWAY:
					this_edge_dir = -this_edge_dir
				var next_edge_dir = next_edge.transform.basis.x.normalized()
				if edge_facing[next_i] == _IntersectNGonFacing.ORIGIN:
					next_edge_dir = -next_edge_dir

				if (j == 0):
					ext_vertex_i = edge_road_sides[while_i][0] + this_edge_dir * (lane_width_i * taken_slots_from_left[while_i])
					int_vertex_i = ext_vertex_i + this_edge_dir * lane_width_i

					# Update the border in preparation for filling the center (0)
					to_next_edge_border_vertices_included[while_i][j] = int_vertex_i
				else:
					var i_dir = to_next_edge_directions_excluded[while_i][j - 1]
					ext_vertex_i = to_next_edge_vertices_excluded[while_i][j - 1] + i_dir * (lane_width_i * taken_slots_from_left[while_i])
					int_vertex_i = ext_vertex_i + i_dir * lane_width_i

				# if last index
				if (j == to_next_edge_vertices_excluded[while_i].size()):
					ext_vertex_i1 = edge_road_sides[next_i][1] + next_edge_dir * (lane_width_i1 * taken_slots_from_right[next_i])
					int_vertex_i1 = ext_vertex_i1 + next_edge_dir * lane_width_i1

					# Update the border in preparation for filling the center (n)
					to_next_edge_border_vertices_included[while_i][j+1] = int_vertex_i1
				else:
					var i1_dir = to_next_edge_directions_excluded[while_i][j]
					ext_vertex_i1 = to_next_edge_vertices_excluded[while_i][j] + i1_dir * (lane_width_i1 * taken_slots_from_right[next_i])
					int_vertex_i1 = ext_vertex_i1 + i1_dir * lane_width_i1

					# Update the border in preparation for filling the center ([1, n-1])
					to_next_edge_border_vertices_included[while_i][j+1] = int_vertex_i1



				# lane quad
				# TODO UV
				surface_tool.add_vertex(int_vertex_i - parent_transform.origin)
				surface_tool.add_vertex(ext_vertex_i - parent_transform.origin)
				surface_tool.add_vertex(int_vertex_i1 - parent_transform.origin)

				surface_tool.add_vertex(int_vertex_i1 - parent_transform.origin)
				surface_tool.add_vertex(ext_vertex_i - parent_transform.origin)
				surface_tool.add_vertex(ext_vertex_i1 - parent_transform.origin)
					

			remaining_lanes[while_i] -= 1
			remaining_lanes[next_i] -= 1
			taken_slots_from_left[while_i] += 1
			taken_slots_from_right[next_i] += 1

		successes[while_i] = possible

		while_i = next_i


	# Before doing the center fill, we partially extend the remaining gaps between lanes
	# at edges.

	var to_next_edge_border_eaten_start: Array[int] = []
	var to_next_edge_border_eaten_end: Array[int] = []
	for i in range(edges.size()):
		# -1 = we must also include the edge vertices when building the border for center fill.
		# (reminder from earlier, excluded means we do not include the edge vertices in the arrays)
		to_next_edge_border_eaten_start.append(-1)
		to_next_edge_border_eaten_end.append(-1)

	for i in range(edges.size()):
		var curr_edge: RoadPoint = edges[i]
		var prev_i = (i - 1 + edges.size()) % edges.size()
		var prev_edge: RoadPoint = edges[prev_i]
		var curr_border = to_next_edge_border_vertices_included[i]
		var prev_border = to_next_edge_border_vertices_included[prev_i]
		var quad_columns: int = remaining_lanes[i];
		var border_index: int = 0

		var next_curr_edge_border_vertex: Vector3 = curr_border[border_index + 1]
		var next_prev_edge_border_vertex: Vector3 = prev_border[prev_border.size() - 1 - (border_index + 1)]
		var next_vertices_row_length_in_lanes: float = next_curr_edge_border_vertex.distance_to(next_prev_edge_border_vertex) / curr_edge.lane_width

		#TODO test edge case, two edges facing each other and parallel with same lane width and count,
		# will it go beyond the other edge?

		while (
			next_vertices_row_length_in_lanes < quad_columns + 2
			and (curr_border.size() - to_next_edge_border_eaten_end[i] - to_next_edge_border_eaten_start[i]) > 0
			and (prev_border.size() - to_next_edge_border_eaten_end[prev_i] - to_next_edge_border_eaten_start[prev_i]) > 0
		):
			var edge_side_row_vertices: Array[Vector3] = []
			var center_side_row_vertices: Array[Vector3] = []
			var curr_border_vertex: Vector3 = curr_border[border_index]
			var prev_border_vertex: Vector3 = prev_border[prev_border.size() - 1 - border_index]
			var next_curr_border_vertex: Vector3 = curr_border[border_index + 1]
			var next_prev_border_vertex: Vector3 = prev_border[prev_border.size() - 1 - (border_index + 1)]
			# build the quad row
			for j in range(quad_columns + 1):
				var ratio: float = float(j) / float(quad_columns)
				edge_side_row_vertices.append(
					prev_border_vertex.lerp(curr_border_vertex, ratio)
				)
				center_side_row_vertices.append(
					next_prev_border_vertex.lerp(next_curr_border_vertex, ratio)
				)

			# add quads
			for j in range(quad_columns):
				# lane quad
				# TODO UV
				surface_tool.add_vertex(center_side_row_vertices[j] - parent_transform.origin)
				surface_tool.add_vertex(edge_side_row_vertices[j] - parent_transform.origin)
				surface_tool.add_vertex(center_side_row_vertices[j + 1] - parent_transform.origin)

				surface_tool.add_vertex(center_side_row_vertices[j + 1] - parent_transform.origin)
				surface_tool.add_vertex(edge_side_row_vertices[j] - parent_transform.origin)
				surface_tool.add_vertex(edge_side_row_vertices[j + 1] - parent_transform.origin)
			
			# update loop values
			border_index += 1
			to_next_edge_border_eaten_start[i] += 1
			to_next_edge_border_eaten_end[prev_i] += 1
			next_vertices_row_length_in_lanes = next_curr_border_vertex.distance_to(next_prev_border_vertex) / curr_edge.lane_width

	# Finish up the mesh

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
