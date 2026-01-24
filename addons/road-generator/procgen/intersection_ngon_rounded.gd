@tool
@icon("res://addons/road-generator/resources/road_intersection.png")

class_name IntersectionNGonRounded
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

class Edge:
	var p1: Vector2i
	var p2: Vector2i
	func _init(p1: Vector2i, p2: Vector2i) -> void:
		self.p1 = p1
		self.p2 = p2
	static func up(i: int, j: int) -> Edge:
		return Edge.new(Vector2i(i, j), Vector2i(i + 1, j))
	
	static func right(i: int, j: int) -> Edge:
		return Edge.new(Vector2i(i + 1, j), Vector2i(i + 1, j + 1))

	static func down(i: int, j: int) -> Edge:
		return Edge.new(Vector2i(i, j + 1), Vector2i(i + 1, j + 1))

	static func left(i: int, j: int) -> Edge:
		return Edge.new(Vector2i(i, j), Vector2i(i, j + 1))

	func _to_string() -> String:
		return "Edge(%s -> %s)" % [p1, p2]
	static func array_to_string(edges: Array[Edge]) -> String:
		var strs: Array[String] = []
		for edge in edges:
			strs.append(edge._to_string())
		return "[" + ", ".join(strs) + "]"

	## Returns true if the given edge is in the edges array
	## (p1 and p2 equals on both instances).
	static func array_has_edge(edges: Array[Edge], edge: Edge) -> bool:
		for e in edges:
			if e.p1 == edge.p1 and e.p2 == edge.p2:
				return true
		return false

	## Removes the given edge from the edges array if found
	## (p1 and p2 equals on both instances).
	static func array_remove_edge(edges: Array[Edge], edge: Edge) -> void:
		for i in range(edges.size()):
			var e: Edge = edges[i]
			if e.p1 == edge.p1 and e.p2 == edge.p2:
				edges.remove_at(i) # OK as we stop the loop
				return

enum IndexVertexType {
	GRID_RING,
	EDGE_RING
}

## Represents the vertex of the associated ring array `vertex_type`.
## Its index associated to the ring array allows to retrieve the actual vertex position.
## (in 2D or 3D depending of the used ring array).
## It is the user responsibility to keep both in sync.
class IndexVertex:
	var vertex_type: IndexVertexType
	var index: int
	func _init(vertex_type: IndexVertexType, index: int) -> void:
		self.vertex_type = vertex_type
		self.index = index

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
	## Array[Array[Vector3]]
	var edge_offset_border_vertices_included: Array[Array] = []
	for i in range(edges.size()):
		to_next_edge_border_eaten_start.append(0)
		to_next_edge_border_eaten_end.append(0)
		edge_offset_border_vertices_included.append([])

	for i in range(edges.size()):
		var curr_edge: RoadPoint = edges[i]
		var prev_i = (i - 1 + edges.size()) % edges.size()
		var prev_edge: RoadPoint = edges[prev_i]
		var curr_border = to_next_edge_border_vertices_included[i]
		var prev_border = to_next_edge_border_vertices_included[prev_i]
		var quad_columns: int = remaining_lanes[i];
		var border_index: int = 0

		# building the initial offset edge border row in case we can't extend at all
		edge_offset_border_vertices_included[i] = []
		for j in range(quad_columns + 1):
			var ratio: float = float(j) / float(quad_columns)
			# HACK only works if lanes are of equal width on the edge.
			edge_offset_border_vertices_included[i].append(
				prev_border[prev_border.size() - 1 - border_index].lerp(
					curr_border[border_index],
					ratio
				)
			)

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
			
			# update edge offsets
			edge_offset_border_vertices_included[i] = center_side_row_vertices

			# update loop values
			border_index += 1
			to_next_edge_border_eaten_start[i] += 1
			to_next_edge_border_eaten_end[prev_i] += 1
			next_vertices_row_length_in_lanes = next_curr_border_vertex.distance_to(next_prev_border_vertex) / curr_edge.lane_width


	# DEBUGGING PRINTS: =====
	# print("offset_borders for %s:" % intersection.get_parent_node_3d().name)
	# for edge_border in edge_offset_border_vertices_included:
	# 	print(edge_border)
	# 	print("    - length: %d" % edge_border.size())

	# print("to_next_edge_borders for %s:" % intersection.get_parent_node_3d().name)
	# for i in range(to_next_edge_border_vertices_included.size()):
	# 	var edge_border = to_next_edge_border_vertices_included[i]
	# 	print(edge_border)
	# 	print("    - length: %d" % edge_border.size())
	# 	print("    - eaten start: %d" % to_next_edge_border_eaten_start[i])
	# 	print("    - eaten end: %d" % to_next_edge_border_eaten_end[i])
	# =======================

	
	
	
	# Finally, fill the center of the intersection with quads.
	# We define its 3D border from the remaining vertices.
	var center_border_vertices: Array[Vector3] = []
	for i in range(edges.size()):
		# first, add the offset edge border vertices

		for j in range( 	edge_offset_border_vertices_included[i].size()):
			center_border_vertices.append(edge_offset_border_vertices_included[i][j])

		# then, append the non eaten border vertices to next edge.
		# We exclude "cordners" which are already included in the offset edge border vertices.
		
		for j in range(
			to_next_edge_border_eaten_start[i] + 1,
			to_next_edge_border_vertices_included[i].size() - to_next_edge_border_eaten_end[i]
		):
			center_border_vertices.append(to_next_edge_border_vertices_included[i][j])

	var evenly_spaced_border_vertices: Array[Vector3] = []
	for i in range(center_border_vertices.size()):
		var next_i: int = (i + 1) % center_border_vertices.size()
		var start_vertex: Vector3 = center_border_vertices[i]
		var end_vertex: Vector3 = center_border_vertices[next_i]
		var segment_length: float = start_vertex.distance_to(end_vertex)
		var num_subdivisions: int = int(floor(segment_length / density))
		evenly_spaced_border_vertices.append(start_vertex)
		for j in range(num_subdivisions):
			var t: float = 1.0 / float(num_subdivisions+1) * float(j + 1)
			var point: Vector3 = start_vertex.lerp(end_vertex, t)
			evenly_spaced_border_vertices.append(point)
	center_border_vertices = evenly_spaced_border_vertices

	# print("Filling center with border vertices:")
	# print(center_border_vertices)

	# We want to fill the center with a grid. To make the process easier,
	# We project the center border vertices on a best-fit plane to work in 2D.
	# We choose the plane made by the intersection point's up vector as the plane normal.
	var center_plane: Plane = Plane(parent_transform.basis.y.normalized(), parent_transform.origin)
	var x_parallel_plane: Plane = Plane(parent_transform.basis.z.normalized(), parent_transform.origin)
	var z_parallel_plane: Plane = Plane(parent_transform.basis.x.normalized(), parent_transform.origin)
	# print("Center plane center: %s" % center_plane.get_center())
	# print("Intersection position: %s" % parent_transform.origin)
	# print("Center plane normal: %s" % center_plane.normal)
	# print("Intersection up vector: %s" % parent_transform.basis.y.normalized())
	# print("planes intersection: %s" % center_plane.intersect_3(x_parallel_plane, z_parallel_plane))

	# We go from the road container's 3D basis (vertices are built from edges local positions which
	# are children of the container), to the plane's 2D basis.
	var projected_center_border_vertices_2d: Array[Vector2] = []
	for vertex in center_border_vertices:
		var projected_point: Vector3 = center_plane.project(vertex)
		var projected_x: Vector3 = x_parallel_plane.project(projected_point)
		var projected_z: Vector3 = z_parallel_plane.project(projected_point)
		var x: float = projected_x.distance_to(parent_transform.origin) * sign((projected_x - parent_transform.origin).dot(parent_transform.basis.x))
		var z: float = projected_z.distance_to(parent_transform.origin) * sign((projected_z - parent_transform.origin).dot(parent_transform.basis.z))
		projected_center_border_vertices_2d.append(Vector2(x, z))

	# print("Projected center border vertices 2D:")
	# print(projected_center_border_vertices_2d)

	# We find grid boundaries...
	var min_z: float = 100_000_000
	var max_z: float = -100_000_000
	var min_x: float = 100_000_000
	var max_x: float = -100_000_000
	for p in projected_center_border_vertices_2d:
		if p.x > max_x:
			max_x = p.x
		if p.x < min_x:
			min_x = p.x
		if p.y > max_z:
			max_z = p.y
		if p.y < min_z:
			min_z = p.y
	
	# print("Center fill grid bounds: X[%d, %d], Z[%d, %d]" % [min_x, max_x, min_z, max_z])
	
	# ...then generate the grid, figuring out which points are inside the polygon.
	# Array[Array[bool]]
	var grid: Array[Array] = []
	var points:int = 0
	var x = min_x
	var grid_width: int = int(floor((max_x - min_x + 1) / density))
	var grid_height: int = int(floor((max_z - min_z + 1) / density))

	# We inset the polygon to avoid edge cases when filling the ring hole.
	var inset_polygons: Array[PackedVector2Array] = Geometry2D.offset_polygon(
		projected_center_border_vertices_2d,
		-density * 0.5,
	)

	for i in range(grid_width):
		var row: Array[bool] = []
		for j in range(grid_height):
			var in_polygon: bool = false
			for inset_polygon in inset_polygons:
				if Geometry2D.is_point_in_polygon(
					Vector2(min_x + i * density, min_z + j * density),
					PackedVector2Array(inset_polygon)
				):
					in_polygon = true
					break
			row.append(in_polygon)
			if in_polygon:
				points += 1
		grid.append(row)

	# print("Center fill grid generated with %d points." % points)
	# _debug_add_grid_mesh(grid, surface_tool, parent_transform, min_x, min_z, grid_density)
	# _debug_add_polygon_2D(surface_tool, parent_transform, projected_center_border_vertices_2d)
	# _debug_add_polygon_3D(surface_tool, parent_transform, center_border_vertices)

	# We project the grid back to 3D space
	## Array[Array[Vector3]]
	var grid_positions_3d: Array[Array] = []
	for i in range(grid.size()):
		grid_positions_3d.append([])
		for j in range(grid[i].size()):
			grid_positions_3d[i].append(Vector3.ZERO)

	# We do a weighted average of the distance from the plane along the up vector
	# for each border vertex, to get the Y component of the grid points.
	# var total_distance: float = 0.0
	var vertices_distances: Array[float] = []
	for vertex in center_border_vertices:
		var distance: float = center_plane.distance_to(vertex)
		vertices_distances.append(distance)
	vertices_distances.append(0.0) # intersection point distance
	
	var weight_points: Array[Vector2] = []
	for vertex_2d in projected_center_border_vertices_2d:
		weight_points.append(vertex_2d)
	weight_points.append(Vector2.ZERO) # intersection point (which is the origin)

	for i in range(grid.size()):
		for j in range(grid[i].size()):
			if grid[i][j]:
				var px: float = min_x + i * density
				var pz: float = min_z + j * density
				var p_2d: Vector2 = Vector2(px, pz)

				# weighted average distance
				var total_weights: float = 0.0
				var weights: Array[float] = []
				for k in range(weight_points.size()):
					var distance: float = p_2d.distance_to(weight_points[k])
					# the power of distance changes the smoothing behaviour
					var weight: float = 1 / max(pow(distance, 3) - density, 0.00001)

					weights.append(weight)
					total_weights += weight
				

				var weighted_distance: float = 0.0
				for w in range(weights.size()):
					weighted_distance += weights[w] * vertices_distances[w]
				weighted_distance /= total_weights
				var p_3d: Vector3 = (
					parent_transform.origin
					+ parent_transform.basis.x.normalized() * px
					+ parent_transform.basis.z.normalized() * pz
					+ parent_transform.basis.y.normalized() * (weighted_distance)
				)
				grid_positions_3d[i][j] = p_3d
	
	

	# Generate grid quads
	var origin: Vector3 = parent_transform.origin
	for i in range(grid.size() - 1):
		for j in range(grid[i].size() - 1):
			if grid[i][j]:
				if grid[i + 1][j] and grid[i][j + 1] and grid[i + 1][j + 1]:
					# quad
					var x_z: Vector3 = grid_positions_3d[i][j]
					var x1_z: Vector3 = grid_positions_3d[i + 1][j]
					var x_z1: Vector3 = grid_positions_3d[i][j + 1]
					var x1_z1: Vector3 = grid_positions_3d[i + 1][j + 1]

					surface_tool.add_vertex(x1_z1 - origin)
					surface_tool.add_vertex(x_z - origin)
					surface_tool.add_vertex(x1_z - origin)

					surface_tool.add_vertex(x_z1 - origin)
					surface_tool.add_vertex(x_z - origin)
					surface_tool.add_vertex(x1_z1 - origin)

	# We still need to fill the gap between the border and the grid.
	# Assuming a single island only. (i.e. multi islands not supported.)
	# We need to find the ring enclosing the island first.
	# The ring is a concave hull around the grid border vertices.
	# We work in 2D space for simplicity.

	# Working in a 2D grid makes it easy, by only having to find
	# adjacent empty and filled cells and creating edges accordingly.
	# Then we build the concave hull by attaching the edges together.

	
	
	## cell defined by its top-left vertex corner.
	## Array[Array[bool]]
	var grid_filled_cells: Array[Array] = []
	for i in range(grid.size() - 1):
		var row: Array[bool] = []
		for j in range(grid[i].size() - 1):
			if grid[i][j] and grid[i + 1][j] and grid[i][j + 1] and grid[i + 1][j + 1]:
				row.append(true)
			else:
				row.append(false)
		grid_filled_cells.append(row)
				
	
	var grid_border_edges: Array[Edge] = []

	for i in range(grid_filled_cells.size()):
		for j in range(grid_filled_cells[i].size()):
			if grid_filled_cells[i][j]:
				# up edge
				if j == 0 or not grid_filled_cells[i][j - 1]:
					grid_border_edges.append(Edge.up(i, j))
				# down edge
				if j == grid_filled_cells[i].size() - 1 or not grid_filled_cells[i][j + 1]:
					grid_border_edges.append(Edge.down(i, j))
				# left edge
				if i == 0 or not grid_filled_cells[i - 1][j]:
					grid_border_edges.append(Edge.left(i, j))
				# right edge
				if i == grid_filled_cells.size() - 1 or not grid_filled_cells[i + 1][j]:
					grid_border_edges.append(Edge.right(i, j))

	

	var grid_ring_indices: Array[Vector2i] = []
	# Reconstruct border ring from balloon edges
	if grid_border_edges.size() > 0:
		var start_edge: Edge = grid_border_edges[0]
		grid_ring_indices.append(start_edge.p1)
		grid_ring_indices.append(start_edge.p2)
		Edge.array_remove_edge(grid_border_edges, start_edge)
		var current_index: Vector2i = start_edge.p2
		while grid_border_edges.size() > 0:
			var found_next: bool = false
			for e in grid_border_edges:
				if e.p1 == current_index:
					grid_ring_indices.append(e.p2)
					current_index = e.p2
					Edge.array_remove_edge(grid_border_edges, e)
					found_next = true
					break
				elif e.p2 == current_index:
					grid_ring_indices.append(e.p1)
					current_index = e.p1
					Edge.array_remove_edge(grid_border_edges, e)
					found_next = true
					break
			if not found_next:
				push_error("Failed to walk the border of the intersection center fill grid. Aborting border fill.")
				push_error("Remaining edges: %d" % grid_border_edges.size())
				push_error("%s" % Edge.array_to_string(grid_border_edges))
				break

		
	var grid_ring_vertices_2d: Array[Vector2] = []
	for index in grid_ring_indices:
		grid_ring_vertices_2d.append(Vector2(
			min_x + index.x * density,
			min_z + index.y * density
		))

	# fill the border ring to the center border vertices
	# we walk through both arrays side by side, creating quads or triangles depending
	# on the closest distance pairs between the current and next vertices, and their closest border vertices.
	# We still work in 2D for simplicity.

	# print("border length: %d, ring length: %d" % [projected_center_border_vertices_2d.size(), grid_ring_vertices_2d.size()])
	# _debug_add_polygon_2D(surface_tool, parent_transform, grid_ring_vertices_2d)
	var center_border_ring_start_index: int = -1
	var closest_distance: float = 100_000_000.0
	for i in range(projected_center_border_vertices_2d.size()):
		var distance: float = projected_center_border_vertices_2d[i].distance_to(grid_ring_vertices_2d[0])
		if distance < closest_distance:
			closest_distance = distance
			center_border_ring_start_index = i

	# Done after the closest point search to keep both arrays
	# (grid and approximate shape) in sync. Makes it easier afterwards.
	var approx_island_shape: Array[Vector2] = []
	const APPROX_ISLAND_SHAPE_STEP: int = 5
	for i in range(0, grid_ring_vertices_2d.size(), APPROX_ISLAND_SHAPE_STEP):
		approx_island_shape.append(grid_ring_vertices_2d[(center_border_ring_start_index + i) % grid_ring_vertices_2d.size()])
	# print("Approx island shape vertices:")
	# print(approx_island_shape)


	## every 3 vertices make a triangle
	var index_triangles: Array[IndexVertex] = []

	# grid_ring_vertices_2d.reverse()


	var center_border_ring_current_index: int = center_border_ring_start_index
	var grid_border_ring_current_index: int = 0
	var ring_fill_ran_once: bool = false
	var ring_fill_iterations: int = 0
	const MAX_RING_FILL_ITERATIONS: int = 1_000
	var center_ring_progress: int = 0
	var grid_ring_progress: int = 0

	while (
		(
			center_ring_progress < center_border_vertices.size()
			and grid_ring_progress < grid_ring_vertices_2d.size()
		)
		or not ring_fill_ran_once
	):
		var grid_ring_current_index: int = grid_border_ring_current_index
		var grid_ring_current: Vector2 = grid_ring_vertices_2d[grid_border_ring_current_index]
		var grid_ring_next_index: int = (grid_border_ring_current_index + 1) % grid_ring_vertices_2d.size()
		var grid_ring_next: Vector2 = grid_ring_vertices_2d[grid_ring_next_index]
		var grid_ring_prior: Vector2 = grid_ring_vertices_2d[(grid_border_ring_current_index - 1 + grid_ring_vertices_2d.size()) % grid_ring_vertices_2d.size()]

		var center_border_ring_current: Vector2 = projected_center_border_vertices_2d[center_border_ring_current_index]
		var center_border_ring_next_index: int = (center_border_ring_current_index + 1) % projected_center_border_vertices_2d.size()
		var center_border_ring_next: Vector2 = projected_center_border_vertices_2d[center_border_ring_next_index]

		var approx_shape_index: int = grid_border_ring_current_index / APPROX_ISLAND_SHAPE_STEP # integer division
		var shape_dir: Vector2 = (
			approx_island_shape[(approx_shape_index + 1) % approx_island_shape.size()]
			- approx_island_shape[approx_shape_index]
		).normalized()
		# print("shape dir: %s" % shape_dir)

		var curr_border_to_curr_ring: Vector2 = grid_ring_current - center_border_ring_current
		var next_border_to_next_ring: Vector2 = grid_ring_next - center_border_ring_next
		var curr_border_to_next_ring: Vector2 = grid_ring_next - center_border_ring_current
		var next_border_to_curr_ring: Vector2 = grid_ring_current - center_border_ring_next
		var average_quad_dir: Vector2 = (curr_border_to_curr_ring + next_border_to_next_ring).normalized()
		var quad_alignment: float = average_quad_dir.dot(shape_dir)
		var center_ring_late_indicator: float = (curr_border_to_curr_ring.normalized()).dot(shape_dir)
		var aligned_with_grid_prior: bool = (grid_ring_current - grid_ring_prior).dot(grid_ring_next - grid_ring_current) > 0.25
		
		## Array[Vector2 | null]
		var curr_border_curr_grid_intersections_grid: Array[Variant] = []
		## Array[Vector2 | null]
		var curr_border_next_grid_intersections_grid: Array[Variant] = []
		## Array[Vector2 | null]
		var next_border_curr_grid_intersections_grid: Array[Variant] = []
		## Array[Vector2 | null]
		var next_border_next_grid_intersections_grid: Array[Variant] = []
		for i in range(grid_ring_vertices_2d.size()):
			var next_i: int = (i + 1) % grid_ring_vertices_2d.size()
			var edge_start: Vector2 = grid_ring_vertices_2d[i]
			var edge_end: Vector2 = grid_ring_vertices_2d[next_i]

			if (edge_start != grid_ring_current and edge_end != grid_ring_current):
				curr_border_curr_grid_intersections_grid.append(Geometry2D.segment_intersects_segment(
					center_border_ring_current,
					grid_ring_current,
					edge_start,
					edge_end
				))
				next_border_curr_grid_intersections_grid.append(Geometry2D.segment_intersects_segment(
					center_border_ring_next,
					grid_ring_current,
					edge_start,
					edge_end
				))
			if (edge_start != grid_ring_next and edge_end != grid_ring_next):
				curr_border_next_grid_intersections_grid.append(Geometry2D.segment_intersects_segment(
					center_border_ring_current,
					grid_ring_next,
					edge_start,
					edge_end
				))
				next_border_next_grid_intersections_grid.append(Geometry2D.segment_intersects_segment(
					center_border_ring_next,
					grid_ring_next,
					edge_start,
					edge_end
				))
		## Array[Vector2 | null]
		var curr_border_curr_grid_intersections_edge: Array[Variant] = []
		## Array[Vector2 | null]
		var curr_border_next_grid_intersections_edge: Array[Variant] = []
		## Array[Vector2 | null]
		var next_border_curr_grid_intersections_edge: Array[Variant] = []
		## Array[Vector2 | null]
		var next_border_next_grid_intersections_edge: Array[Variant] = []

		for i in range(projected_center_border_vertices_2d.size()):
			var next_i: int = (i + 1) % projected_center_border_vertices_2d.size()
			var edge_start: Vector2 = projected_center_border_vertices_2d[i]
			var edge_end: Vector2 = projected_center_border_vertices_2d[next_i]

			if (edge_start != center_border_ring_current and edge_end != center_border_ring_current):
				curr_border_curr_grid_intersections_edge.append(Geometry2D.segment_intersects_segment(
					center_border_ring_current,
					grid_ring_current,
					edge_start,
					edge_end
				))
				curr_border_next_grid_intersections_edge.append(Geometry2D.segment_intersects_segment(
					center_border_ring_current,
					grid_ring_next,
					edge_start,
					edge_end
				))
			if (edge_start != center_border_ring_next and edge_end != center_border_ring_next):
				next_border_curr_grid_intersections_edge.append(Geometry2D.segment_intersects_segment(
					center_border_ring_next,
					grid_ring_current,
					edge_start,
					edge_end
				))
				next_border_next_grid_intersections_edge.append(Geometry2D.segment_intersects_segment(
					center_border_ring_next,
					grid_ring_next,
					edge_start,
					edge_end
				))
		var curr_border_curr_grid_crossing_grid: bool = curr_border_curr_grid_intersections_grid.any(func(v): return v != null)
		var curr_border_next_grid_crossing_grid: bool = curr_border_next_grid_intersections_grid.any(func(v): return v != null)
		var next_border_curr_grid_crossing_grid: bool = next_border_curr_grid_intersections_grid.any(func(v): return v != null)
		var next_border_next_grid_crossing_grid: bool = next_border_next_grid_intersections_grid.any(func(v): return v != null)

		var curr_border_curr_grid_crossing_edge: bool = curr_border_curr_grid_intersections_edge.any(func(v): return v != null)
		var curr_border_next_grid_crossing_edge: bool = curr_border_next_grid_intersections_edge.any(func(v): return v != null)
		var next_border_curr_grid_crossing_edge: bool = next_border_curr_grid_intersections_edge.any(func(v): return v != null)
		var next_border_next_grid_crossing_edge: bool = next_border_next_grid_intersections_edge.any(func(v): return v != null)

		# print("Iteration %d:" % ring_fill_iterations)
		# print("  grid intersections: curr/curr: %s, curr/next: %s, next/curr: %s, next/next: %s" % [
		# 	str(curr_border_curr_grid_crossing_grid),
		# 	str(curr_border_next_grid_crossing_grid),
		# 	str(next_border_curr_grid_crossing_grid),
		# 	str(next_border_next_grid_crossing_grid),
		# ])
		# print("  edge intersections: curr/curr: %s, curr/next: %s, next/curr: %s, next/next: %s" % [
		# 	str(curr_border_curr_grid_crossing_edge),
		# 	str(curr_border_next_grid_crossing_edge),
		# 	str(next_border_curr_grid_crossing_edge),
		# 	str(next_border_next_grid_crossing_edge),
		# ])

		# print("quad alignment: %f, center ring late indicator: %f, aligned with grid prior: %s" % [quad_alignment, center_ring_late_indicator, str(aligned_with_grid_prior)])
		if (
			quad_alignment <= -0.5 # 0 = flat, -1 = perfect 90 deg 
			and aligned_with_grid_prior
			and not curr_border_curr_grid_crossing_grid
			and not next_border_next_grid_crossing_grid
			and not next_border_curr_grid_crossing_grid
			and not curr_border_curr_grid_crossing_edge
			and not next_border_next_grid_crossing_edge
			and not next_border_curr_grid_crossing_edge
		): # more or less on sync
			# quad
			# Have the quad always facing the "top".
			var center_to_grid_next: Vector2 = grid_ring_next - center_border_ring_next
			var center_to_grid_current: Vector2 = grid_ring_current - center_border_ring_next
			if ((center_to_grid_current).angle_to(center_to_grid_next) < 0):
				index_triangles.append(IndexVertex.new(
					IndexVertexType.GRID_RING,
					grid_ring_next_index,
				))
				index_triangles.append(IndexVertex.new(
					IndexVertexType.GRID_RING,
					grid_ring_current_index,
				))
				index_triangles.append(IndexVertex.new(
					IndexVertexType.EDGE_RING,
					center_border_ring_next_index,
				))
			else:
				index_triangles.append(IndexVertex.new(
					IndexVertexType.GRID_RING,
					grid_ring_current_index,
				))
				index_triangles.append(IndexVertex.new(
					IndexVertexType.GRID_RING,
					grid_ring_next_index,
				))
				index_triangles.append(IndexVertex.new(
					IndexVertexType.EDGE_RING,
					center_border_ring_next_index,
				))

			var grid_to_center_current: Vector2 = center_border_ring_current - grid_ring_current
			var grid_to_center_next: Vector2 = center_border_ring_next - grid_ring_current
			if ((grid_to_center_current).angle_to(grid_to_center_next) < 0):
				index_triangles.append(IndexVertex.new(
					IndexVertexType.EDGE_RING,
					center_border_ring_next_index,
				))
				index_triangles.append(IndexVertex.new(
					IndexVertexType.EDGE_RING,
					center_border_ring_current_index,
				))
				index_triangles.append(IndexVertex.new(
					IndexVertexType.GRID_RING,
					grid_ring_current_index,
				))
			else:
				index_triangles.append(IndexVertex.new(
					IndexVertexType.GRID_RING,
					grid_ring_current_index,
				))
				index_triangles.append(IndexVertex.new(
					IndexVertexType.EDGE_RING,
					center_border_ring_current_index,
				))
				index_triangles.append(IndexVertex.new(
					IndexVertexType.EDGE_RING,
					center_border_ring_next_index,
				))

			grid_border_ring_current_index = (grid_border_ring_current_index + 1) % grid_ring_vertices_2d.size()
			center_border_ring_current_index = (center_border_ring_current_index + 1) % projected_center_border_vertices_2d.size()
			center_ring_progress += 1
			grid_ring_progress += 1
		else:
			var grid_triangle_possible: bool = (
				not curr_border_curr_grid_crossing_grid
				and not curr_border_next_grid_crossing_grid
				and not curr_border_curr_grid_crossing_edge
				and not curr_border_next_grid_crossing_edge
			)
			var border_triangle_possible: bool = (
				not curr_border_curr_grid_crossing_grid
				and not next_border_curr_grid_crossing_grid
				and not curr_border_curr_grid_crossing_edge
				and not next_border_curr_grid_crossing_edge
			)
			var grid_ring_lag_behind: bool = center_ring_late_indicator < 0
			if not grid_triangle_possible and not border_triangle_possible:
				push_warning("No triangle possible this iteration (%d), forcing triangle based on lag." % ring_fill_iterations)
				if grid_ring_lag_behind:
					grid_triangle_possible = true
				else:
					border_triangle_possible = true
				
			if (grid_ring_lag_behind and grid_triangle_possible) or not border_triangle_possible: # grid ring lag behind
				# triangle
				var center_to_grid_next: Vector2 = grid_ring_next - center_border_ring_current
				var center_to_grid_current: Vector2 = grid_ring_current - center_border_ring_current
				# Have the triangle always facing the "top".
				if ((center_to_grid_current).angle_to(center_to_grid_next) > 0):
					index_triangles.append(IndexVertex.new(
						IndexVertexType.GRID_RING,
						grid_ring_next_index,
					))
					index_triangles.append(IndexVertex.new(
						IndexVertexType.EDGE_RING,
						center_border_ring_current_index,
					))
					index_triangles.append(IndexVertex.new(
						IndexVertexType.GRID_RING,
						grid_ring_current_index,
					))
				else:
					index_triangles.append(IndexVertex.new(
						IndexVertexType.GRID_RING,
						grid_ring_current_index,
					))
					index_triangles.append(IndexVertex.new(
						IndexVertexType.EDGE_RING,
						center_border_ring_current_index,
					))
					index_triangles.append(IndexVertex.new(
						IndexVertexType.GRID_RING,
						grid_ring_next_index,
					))
				grid_border_ring_current_index = (grid_border_ring_current_index + 1) % grid_ring_vertices_2d.size()
				grid_ring_progress += 1
			elif border_triangle_possible: # center ring lag behind
				# triangle
				# Have the triangle always facing the "top".
				var grid_to_center_next: Vector2 = center_border_ring_next - grid_ring_current
				var grid_to_center_current: Vector2 = center_border_ring_current - grid_ring_current
				if ((grid_to_center_current).angle_to(grid_to_center_next) > 0):
					index_triangles.append(IndexVertex.new(
						IndexVertexType.EDGE_RING,
						center_border_ring_current_index,
					))
					index_triangles.append(IndexVertex.new(
						IndexVertexType.EDGE_RING,
						center_border_ring_next_index,
					))
					index_triangles.append(IndexVertex.new(
						IndexVertexType.GRID_RING,
						grid_ring_current_index,
					))
				else:
					index_triangles.append(IndexVertex.new(
						IndexVertexType.GRID_RING,
						grid_ring_current_index,
					))
					index_triangles.append(IndexVertex.new(
						IndexVertexType.EDGE_RING,
						center_border_ring_next_index,
					))
					index_triangles.append(IndexVertex.new(
						IndexVertexType.EDGE_RING,
						center_border_ring_current_index,
					))
				center_border_ring_current_index = (center_border_ring_current_index + 1) % projected_center_border_vertices_2d.size()
				center_ring_progress += 1
			else:
				push_error("Failed to decide on triangle/quad for ring fill. Aborting.")
				break

		ring_fill_ran_once = true
		ring_fill_iterations += 1
		# print("ring fill iteration %d: center progress %d / %d, grid progress %d / %d" % [
		# 	ring_fill_iterations,
		# 	center_ring_progress,
		# 	center_border_vertices.size(),
		# 	grid_ring_progress,
		# 	grid_ring_vertices_2d.size(),
		# ])
		if ring_fill_iterations >= MAX_RING_FILL_ITERATIONS:
			push_warning("Max ring fill iterations reached (%d)." % MAX_RING_FILL_ITERATIONS)
			break













	# commit triangles
	# print("Filling border ring with %d triangles." % (index_triangles.size() / 3))
	
	var grid_ring_vertices_3d: Array[Vector3] = []
	for index in grid_ring_indices:
		grid_ring_vertices_3d.append(grid_positions_3d[int(index.x)][int(index.y)])
	
	# print("Grid ring vertices 3D length: %d" % grid_ring_vertices_3d.size())
	# print("Center border vertices length: %d" % center_border_vertices.size())

	for i in range(0, index_triangles.size(), 3):
		var iv1: IndexVertex = index_triangles[i]
		var iv2: IndexVertex = index_triangles[i + 1]
		var iv3: IndexVertex = index_triangles[i + 2]

		var v1: Vector3
		var v2: Vector3
		var v3: Vector3
		var v1_2d: Vector2
		var v2_2d: Vector2
		var v3_2d: Vector2

		if iv1.vertex_type == IndexVertexType.GRID_RING:
			if iv1.index >= grid_ring_vertices_3d.size():
				push_error("Index out of bounds accessing grid ring vertices (%d >= %d)." % [iv1.index, grid_ring_vertices_3d.size()])
				continue
			v1 = grid_ring_vertices_3d[iv1.index]
			v1_2d = grid_ring_vertices_2d[iv1.index]
		else:
			if iv1.index >= center_border_vertices.size():
				push_error("Index out of bounds accessing center border vertices (%d >= %d)." % [iv1.index, center_border_vertices.size()])
				continue
			v1 = center_border_vertices[iv1.index]
			v1_2d = projected_center_border_vertices_2d[iv1.index]

		if iv2.vertex_type == IndexVertexType.GRID_RING:
			if iv2.index >= grid_ring_vertices_3d.size():
				push_error("Index out of bounds accessing grid ring vertices (%d >= %d)." % [iv2.index, grid_ring_vertices_3d.size()])
				continue
			v2 = grid_ring_vertices_3d[iv2.index]
			v2_2d = grid_ring_vertices_2d[iv2.index]
		else:
			if iv2.index >= center_border_vertices.size():
				push_error("Index out of bounds accessing center border vertices (%d >= %d)." % [iv2.index, center_border_vertices.size()])
				continue
			v2 = center_border_vertices[iv2.index]
			v2_2d = projected_center_border_vertices_2d[iv2.index]

		if iv3.vertex_type == IndexVertexType.GRID_RING:
			if iv3.index >= grid_ring_vertices_3d.size():
				push_error("Index out of bounds accessing grid ring vertices (%d >= %d)." % [iv3.index, grid_ring_vertices_3d.size()])
				continue
			v3 = grid_ring_vertices_3d[iv3.index]
			v3_2d = grid_ring_vertices_2d[iv3.index]
		else:
			if iv3.index >= center_border_vertices.size():
				push_error("Index out of bounds accessing center border vertices (%d >= %d)." % [iv3.index, center_border_vertices.size()])
				continue
			v3 = center_border_vertices[iv3.index]
			v3_2d = projected_center_border_vertices_2d[iv3.index]

		surface_tool.add_vertex(v1 - parent_transform.origin)
		surface_tool.add_vertex(v2 - parent_transform.origin)
		surface_tool.add_vertex(v3 - parent_transform.origin)
		# _debug_add_polygon_2D(surface_tool, parent_transform, [
		# 	v1_2d,
		# 	v2_2d,
		# 	v3_2d,
		# ])

	
	# FIXME if no grid? -> triangle fan

	
	

	if center_border_ring_current_index != center_border_ring_start_index:
		push_warning("Border ring fill incomplete, filling the gap with a triangle fan.")
		# A gap is left, fill it with a triangle fan where the center is
		# the last next ring vertex (i.e. index 0).
		var last_ring_vertex: Vector3 = grid_ring_vertices_3d[0]
		while center_border_ring_current_index != center_border_ring_start_index:
			var center_border_current: Vector3 = center_border_vertices[center_border_ring_current_index]
			var center_border_next_index: int = (center_border_ring_current_index + 1) % center_border_vertices.size()
			var center_border_next: Vector3 = center_border_vertices[center_border_next_index]

			# triangle
			surface_tool.add_vertex(last_ring_vertex - parent_transform.origin)
			surface_tool.add_vertex(center_border_current - parent_transform.origin)
			surface_tool.add_vertex(center_border_next - parent_transform.origin)

			center_border_ring_current_index = center_border_next_index





	# Finish up and commit the mesh

	surface_tool.index()
	var material: Material = container.effective_surface_material()
	if material:
		surface_tool.set_material(material)
	surface_tool.generate_normals()
	var mesh: ArrayMesh = surface_tool.commit()  # should be MeshInstance3D?
	#mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh

func _debug_add_grid_mesh(grid: Array[Array], surface_tool: SurfaceTool, parent_transform: Transform3D, min_x: int, min_z: int, density: float) -> void:
	# print("Debugging grid mesh:")
	var origin: Vector3 = parent_transform.origin
	var basis_x: Vector3 = parent_transform.basis.x.normalized()
	var basis_z: Vector3 = parent_transform.basis.z.normalized()
	for i in range(grid.size() - 1):
		for j in range(grid[i].size() - 1):
			var x = min_x + i * density
			var z = min_z + j * density
			if grid[i][j]:
				if grid[i + 1][j] and grid[i][j + 1] and grid[i + 1][j + 1]:
					# quad
					var x_z: Vector3 = origin + basis_x * float(x) + basis_z * float(z)
					var x1_z: Vector3 = origin + basis_x * float(x + density) + basis_z * float(z)
					var x_z1: Vector3 = origin + basis_x * float(x) + basis_z * float(z + density)
					var x1_z1: Vector3 = origin + basis_x * float(x + density) + basis_z * float(z + density)

					surface_tool.add_vertex(x1_z1 - origin)
					surface_tool.add_vertex(x_z - origin)
					surface_tool.add_vertex(x1_z - origin)

					surface_tool.add_vertex(x_z1 - origin)
					surface_tool.add_vertex(x_z - origin)
					surface_tool.add_vertex(x1_z1 - origin)


func _debug_add_polygon_3D(surface_tool: SurfaceTool, parent_transform: Transform3D, polygon: Array[Vector3]) -> void:
	# print("Debugging triangulated polygon mesh:")
	for i in range(polygon.size()):
		var current_point: Vector3 = polygon[i]
		var next_point: Vector3 = polygon[(i + 1) % polygon.size()]

		var dir: Vector3 = (next_point - current_point).normalized()
		var cross: Vector3 = dir.cross(Vector3.UP).normalized()

		var thickness: float = 0.1
		var p1: Vector3 = current_point + cross * thickness
		var p2: Vector3 = current_point - cross * thickness
		var p3: Vector3 = next_point + cross * thickness
		var p4: Vector3 = next_point - cross * thickness

		surface_tool.add_vertex(p1 - parent_transform.origin)
		surface_tool.add_vertex(p2 - parent_transform.origin)
		surface_tool.add_vertex(p3 - parent_transform.origin)

		surface_tool.add_vertex(p4 - parent_transform.origin)
		surface_tool.add_vertex(p3 - parent_transform.origin)
		surface_tool.add_vertex(p2 - parent_transform.origin)

## draw quad lines for the polygon
func _debug_add_polygon_2D(surface_tool: SurfaceTool, parent_transform: Transform3D, polygon: Array[Vector2]) -> void:
	# print("Debugging triangulated polygon mesh:")
	var basis_x: Vector3 = parent_transform.basis.x.normalized()
	var basis_z: Vector3 = parent_transform.basis.z.normalized()
	var origin: Vector3 = parent_transform.origin
	for i in range(polygon.size()):
		var current_point: Vector2 = polygon[i]
		var next_point: Vector2 = polygon[(i + 1) % polygon.size()]

		var current_point_3d: Vector3 = origin + basis_x * current_point.x + basis_z * current_point.y
		var next_point_3d: Vector3 = origin + basis_x * next_point.x + basis_z * next_point.y

		var dir: Vector3 = (next_point_3d - current_point_3d).normalized()
		var cross: Vector3 = dir.cross(Vector3.UP).normalized()

		var thickness: float = 0.1
		var p1: Vector3 = current_point_3d + cross * thickness
		var p2: Vector3 = current_point_3d - cross * thickness
		var p3: Vector3 = next_point_3d + cross * thickness
		var p4: Vector3 = next_point_3d - cross * thickness

		surface_tool.add_vertex(p1 - parent_transform.origin)
		surface_tool.add_vertex(p2 - parent_transform.origin)
		surface_tool.add_vertex(p3 - parent_transform.origin)

		surface_tool.add_vertex(p4 - parent_transform.origin)
		surface_tool.add_vertex(p3 - parent_transform.origin)
		surface_tool.add_vertex(p2 - parent_transform.origin)

#endregion
# ------------------------------------------------------------------------------
