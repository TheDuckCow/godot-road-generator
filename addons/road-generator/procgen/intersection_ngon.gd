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

const STOP_ROW_SIZE: float = 2.0  # TODO: make proportional to density

## Prefix for generated edge-curve nodes, named `edge_{starting RoadPoint name}`.
const EDGE_PREFIX := "edge_"

## Meters of lateral error treated as equivalent to one radian of facing
## misalignment when scoring primary candidates. Lateral offset is weighted more
## heavily than angle, so a candidate the source aims squarely at is preferred
## over one that merely faces back from off to the side.
const _PRIMARY_ANGLE_WEIGHT: float = 6.0
## Error added to a candidate sitting beside or behind the source, ruling out
## same-side edges as through partners.
const _PRIMARY_BEHIND_PENALTY: float = 1.0e6

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


func generate_lanes(intersection: Node3D, edges: Array[RoadPoint], container: RoadContainer) -> void:
	var active_lanes: Array[RoadLane] = []
	if not container.generate_ai_lanes:
		_clear_generated_lanes(intersection, active_lanes)
		return

	var used_names := {}
	var manager: RoadManager = container.get_manager()
	var primaries := _compute_edge_primaries(edges, intersection)

	for i in range(edges.size()):
		var edge: RoadPoint = edges[i]
		if not is_instance_valid(edge):
			continue
		var facing: _IntersectNGonFacing = _get_edge_facing(edge, intersection)
		if facing == _IntersectNGonFacing.OTHER:
			continue
		var entering := _directional_lanes(edge, _entering_dir(facing))
		if entering.is_empty():
			continue
		var entry_dir := _edge_inward_dir(edge, intersection)
		var primary: int = primaries[i]

		# Through lanes: every entering lane routes straight across to this edge's
		# primary target. Surplus lanes merge onto its outermost exit lane, built
		# from the divider outward.
		if primary >= 0:
			var exiting := _edge_exit_lanes(edges[primary], intersection)
			for k in range(entering.size()):
				var src: Dictionary = entering[k]
				var entry := _lane_stop_position(edge, intersection, src["index"])
				var exit_point := intersection.global_transform.origin
				var exit_dir := entry_dir
				var next_tag := ""
				var merged := false
				if not exiting.is_empty():
					merged = k >= exiting.size()
					var target: Dictionary = exiting[mini(k, exiting.size() - 1)]
					exit_point = _lane_stop_position(target["edge"], intersection, target["index"])
					exit_dir = -_edge_inward_dir(target["edge"], intersection)
					next_tag = target["tag"]
				var lane_name := _tagged_lane_name(used_names, edge.name, src["tag"], "r" if merged else "")
				# entry/exit_dir has magnitude to indicate the offset amount
				entry_dir = entry_dir.normalized() * edge.lane_width / RoadPoint.DEFAULT_LANE_WIDTH
				exit_dir = exit_dir.normalized() * edge.lane_width / RoadPoint.DEFAULT_LANE_WIDTH
				_emit_lane(intersection, container, manager, active_lanes, lane_name,
						src["tag"], next_tag, entry, entry_dir, exit_point, exit_dir,
						not exiting.is_empty())

		# Turn lanes: the turn-side entering lane reaches each remaining edge.
		for j in range(edges.size()):
			if j == i or j == primary or not is_instance_valid(edges[j]):
				continue
			var target_edge: RoadPoint = edges[j]
			var target_facing: _IntersectNGonFacing = _get_edge_facing(target_edge, intersection)
			if target_facing == _IntersectNGonFacing.OTHER:
				continue
			var target_exit := _directional_lanes(target_edge, _exiting_dir(target_facing))
			if target_exit.is_empty():
				continue
			var reference_edge: RoadPoint = edges[primary] if primary >= 0 else null
			var clockwise := _turn_is_clockwise(edge, target_edge, reference_edge, intersection)
			var turn_src: Dictionary = entering[entering.size() - 1] if clockwise else entering[0]
			var turn_dst: Dictionary = target_exit[target_exit.size() - 1] if clockwise else target_exit[0]
			var turn_entry := _lane_stop_position(edge, intersection, turn_src["index"])
			var turn_exit := _lane_stop_position(target_edge, intersection, turn_dst["index"])
			var turn_exit_dir := -_edge_inward_dir(target_edge, intersection)
			var turn_name := _tagged_lane_name(used_names, edge.name, turn_src["tag"], "a")
			# entry/exit_dir has magnitude to indicate the offset amount
			entry_dir = entry_dir.normalized() * reference_edge.lane_width / RoadPoint.DEFAULT_LANE_WIDTH
			turn_exit_dir = turn_exit_dir.normalized() * reference_edge.lane_width / RoadPoint.DEFAULT_LANE_WIDTH
			_emit_lane(intersection, container, manager, active_lanes, turn_name,
					turn_src["tag"], turn_dst["tag"], turn_entry, entry_dir, turn_exit, turn_exit_dir)

	_clear_generated_lanes(intersection, active_lanes)


## Builds one exterior edge curve per branch, spanning from each edge to its
## counter-clockwise neighbour so the curve named after an edge hugs that edge's
## right-hand side (drive-on-right), the intuitive parent for right-side decoration
## like sidewalks. Sweeps away curves whose branch is gone. Edges MUST have been
## sorted beforehand; the neighbour is simply the previous sorted edge, so a removed
## branch's curve is dropped and its neighbour regenerated automatically.
func generate_edge_curves(intersection: Node3D, edges: Array[RoadPoint], container: RoadContainer) -> void:
	# A lone branch has no exterior span to bound.
	if edges.size() < 2:
		_clear_generated_edge_curves(intersection, [])
		return

	var active: Array[Path3D] = []
	var count := edges.size()
	for i in range(count):
		var edge: RoadPoint = edges[i]
		var neighbor: RoadPoint = edges[(i - 1 + count) % count]
		if not is_instance_valid(edge) or not is_instance_valid(neighbor):
			continue
		if _get_edge_facing(edge, intersection) == _IntersectNGonFacing.OTHER:
			continue
		if _get_edge_facing(neighbor, intersection) == _IntersectNGonFacing.OTHER:
			continue

		var path := _get_or_create_edge_curve(intersection, EDGE_PREFIX + edge.name)
		active.append(path)

		# Anchor at this edge's s1 (right-hand) corner and run to the neighbour's s0,
		# putting the named curve on the edge's right rather than its left.
		var here := _edge_exterior_corners(edge, intersection)
		var there := _edge_exterior_corners(neighbor, intersection)
		_assign_edge_curve(path, here["s1"], here["s1_stop"], there["s0_stop"], there["s0"])

	_clear_generated_edge_curves(intersection, active)


func clear_edge_curves(intersection: Node3D, edges: Array[RoadPoint], container: RoadContainer) -> void:
	_clear_generated_edge_curves(intersection, [])


# ------------------------------------------------------------------------------
#endregion
#region Generation functions
# ------------------------------------------------------------------------------



func _get_edge_facing(edge: RoadPoint, intersection: Node3D) -> _IntersectNGonFacing:
	if not intersection.has_method("is_road_intersection"):
		push_error("intersection is not an intersection node. Returning OTHER facing.")
		return _IntersectNGonFacing.OTHER

	var facing: _IntersectNGonFacing = _IntersectNGonFacing.OTHER
	if edge.get_node_or_null(edge.prior_pt_init) == intersection:
		facing = _IntersectNGonFacing.ORIGIN
	elif edge.get_node_or_null(edge.next_pt_init) == intersection:
		facing = _IntersectNGonFacing.AWAY
	else:
		push_warning("Failed to find intersection connection between %s and %s" % [edge.name, intersection.name])
		facing = _IntersectNGonFacing.OTHER
	return facing


## World-space direction along an edge pointing toward the intersection (the
## travel direction of its entering lanes).
func _edge_inward_dir(edge: RoadPoint, intersection: Node3D) -> Vector3:
	var facing: _IntersectNGonFacing = _get_edge_facing(edge, intersection)
	var parallel_v: Vector3 = edge.global_transform.basis.z.normalized()
	if facing == _IntersectNGonFacing.ORIGIN:
		parallel_v = -parallel_v
	return parallel_v


## World-space center of an edge's stop line, where its lanes meet the intersection.
func _edge_stop_center(edge: RoadPoint, intersection: Node3D) -> Vector3:
	return edge.global_transform.origin + _edge_inward_dir(edge, intersection) * STOP_ROW_SIZE * edge.lane_width / RoadPoint.DEFAULT_LANE_WIDTH


func _entering_dir(facing: _IntersectNGonFacing) -> int:
	return RoadPoint.LaneDir.REVERSE if facing == _IntersectNGonFacing.AWAY else RoadPoint.LaneDir.FORWARD


func _exiting_dir(facing: _IntersectNGonFacing) -> int:
	return RoadPoint.LaneDir.FORWARD if facing == _IntersectNGonFacing.AWAY else RoadPoint.LaneDir.REVERSE


## Lanes of the given direction on an edge, ordered from the centerline outward,
## each as a dictionary with its `index` in traffic_dir and its `F#`/`R#` `tag`.
func _directional_lanes(edge: RoadPoint, dir: int) -> Array:
	var rev_count := edge.get_rev_lane_count()
	var result: Array = []
	for i in range(edge.traffic_dir.size()):
		if edge.traffic_dir[i] != dir:
			continue
		var tag: String
		if dir == RoadPoint.LaneDir.FORWARD:
			tag = "F%d" % (i - rev_count)
		else:
			tag = "R%d" % (rev_count - 1 - i)
		result.append({"index": i, "tag": tag})
	result.sort_custom(func(a, b): return int(a["tag"].substr(1)) < int(b["tag"].substr(1)))
	return result


## Exit lanes available on an edge, tagged with the edge they belong to so a
## through lane can target them.
func _edge_exit_lanes(edge: RoadPoint, intersection: Node3D) -> Array:
	var facing: _IntersectNGonFacing = _get_edge_facing(edge, intersection)
	if facing == _IntersectNGonFacing.OTHER:
		return []
	var lanes := _directional_lanes(edge, _exiting_dir(facing))
	for lane in lanes:
		lane["edge"] = edge
	return lanes


## True when the edge at `index` is a valid, intersection-facing edge eligible
## to take part in lane matching.
func _edge_is_eligible(edges: Array[RoadPoint], index: int, intersection: Node3D) -> bool:
	if not is_instance_valid(edges[index]):
		return false
	return _get_edge_facing(edges[index], intersection) != _IntersectNGonFacing.OTHER


## Perpendicular distance from `rel` to the ray along `dir`, scaled by lane width
## so the lateral-vs-angle balance in pairing holds for roads built at any lane
## size: a road with wide lanes spaces its edges proportionally wider, and without
## this the inflated lateral distances would swamp the width-independent angle.
func _pairing_lateral_cost(rel: Vector3, dir: Vector3, lane_width: float) -> float:
	var along := rel.dot(dir)
	return (rel - dir * along).length() * RoadPoint.DEFAULT_LANE_WIDTH / lane_width


## Picks each edge's primary target with a projection loss: cast the edge's
## travel ray forward through the intersection and score every other edge by how
## far it sits laterally from that ray (it should lie dead ahead) blended with how
## head-on the two roads face (their travel directions should oppose). Lowest
## combined error wins, so both position and facing rotation count. The returned
## array holds each edge's primary index, or -1 when it has none. Every eligible
## edge routes its entering lanes through to its primary, reciprocated or not.
func _compute_edge_primaries(edges: Array[RoadPoint], intersection: Node3D) -> Array[int]:
	var count := edges.size()
	var primary: Array[int] = []
	primary.resize(count)
	primary.fill(-1)
	for i in range(count):
		if not _edge_is_eligible(edges, i, intersection):
			continue
		var origin_i := edges[i].global_transform.origin
		var dir_i := _edge_inward_dir(edges[i], intersection)
		var best := -1
		var best_loss := INF
		for j in range(count):
			if j == i or not _edge_is_eligible(edges, j, intersection):
				continue
			var rel := edges[j].global_transform.origin - origin_i
			var along := rel.dot(dir_i)
			var lateral := _pairing_lateral_cost(rel, dir_i, edges[i].lane_width)
			var dir_j := _edge_inward_dir(edges[j], intersection)
			var angle := acos(clampf(-dir_i.dot(dir_j), -1.0, 1.0))
			var loss := lateral + _PRIMARY_ANGLE_WEIGHT * angle
			if along <= 0.0:
				loss += _PRIMARY_BEHIND_PENALTY
			if loss < best_loss:
				best_loss = loss
				best = j
		primary[i] = best
	return primary


## True if the target edge lies clockwise (to the right) of the straight-through
## direction toward this edge's `reference` (primary) target. Measuring handedness
## against the primary, rather than the raw inbound facing, ties every left/right
## flip to the moment the edge's primary pairing changes, so a turn never crosses
## traffic mid-rotation. Falls back to inbound facing when there is no primary.
## A right turn sources from the outer entering lane; a left turn from the inner
## (divider-side) lane.
func _turn_is_clockwise(edge: RoadPoint, target: RoadPoint, reference: RoadPoint, intersection: Node3D) -> bool:
	var up: Vector3 = intersection.global_transform.basis.y.normalized()
	var ahead: Vector3
	if is_instance_valid(reference):
		ahead = reference.global_transform.origin - edge.global_transform.origin
	else:
		ahead = _edge_inward_dir(edge, intersection)
	var to_target := target.global_transform.origin - edge.global_transform.origin
	# Around +Y, a right turn yields a negative signed angle from ahead to target.
	return ahead.signed_angle_to(to_target, up) < 0.0


## Finds an existing generated lane by name or creates one, ensuring group
## membership and editor metadata.
func _get_or_create_lane(intersection: Node3D, container: RoadContainer, manager: RoadManager, lane_name: String) -> RoadLane:
	var existing := intersection.get_node_or_null(lane_name)
	var lane: RoadLane
	if existing is RoadLane:
		lane = existing
	else:
		lane = RoadLane.new()
		intersection.add_child(lane)
		lane.name = lane_name
		lane.set_meta("_edit_lock_", true)
		lane.auto_free_vehicles = container.auto_free_vehicles
		if container.debug_scene_visible:
			lane.owner = container.get_owner()
	if container.ai_lane_group != "":
		lane.add_to_group(container.ai_lane_group)
	elif is_instance_valid(manager) and manager.ai_lane_group != "":
		lane.add_to_group(manager.ai_lane_group)
	return lane


## Creates or updates a single lane with its tags, curve and draw settings.
## Lanes the user has promoted to editable (given an owner) are left untouched.
func _emit_lane(
		intersection: Node3D,
		container: RoadContainer,
		manager: RoadManager,
		active_lanes: Array[RoadLane],
		lane_name: String,
		prior_tag: String,
		next_tag: String,
		entry: Vector3,
		entry_dir: Vector3,
		exit_point: Vector3,
		exit_dir: Vector3,
		extend_exit: bool = true) -> void:
	var existing := intersection.get_node_or_null(lane_name)
	var lane := _get_or_create_lane(intersection, container, manager, lane_name)
	active_lanes.append(lane)
	if existing is RoadLane and is_instance_valid(existing.owner):
		return
	lane.lane_prior_tag = prior_tag
	lane.lane_next_tag = next_tag
	_assign_through_curve(lane, intersection, entry, exit_point, entry_dir, exit_dir, extend_exit)
	lane.draw_in_editor = container.draw_lanes_editor
	lane.draw_in_game = container.draw_lanes_game
	lane.refresh_geom = true
	lane.rebuild_geom()


## World-space center of a single lane at its edge's stop line. Geometric edges
## center their lanes; divider-aligned edges keep the direction split at origin.
func _lane_stop_position(edge: RoadPoint, intersection: Node3D, lane_index: int) -> Vector3:
	var reference := edge.traffic_dir.size() / 2.0
	if edge.alignment == RoadPoint.Alignment.DIVIDER:
		reference = edge.get_rev_lane_count()
	var offset := (lane_index - reference + 0.5) * edge.lane_width
	var perpendicular_v: Vector3 = edge.global_transform.basis.x.normalized()
	return _edge_stop_center(edge, intersection) + perpendicular_v * offset


## Curve from an entry RoadPoint to an exit RoadPoint, in the lane's local space.
## The lane runs straight from each RoadPoint up to its stop line, then arcs
## across the intersection with bezier handles aligned to the entry and exit
## travel directions (staying straight when those directions are colinear). With
## no exit edge to reach, the lane simply ends at the stop line.
##
## Note: entry_dir and exit_dir are NOT normalized, so we can pull out .length()
## which matches the corresponding edge RP lane_width
func _assign_through_curve(lane: RoadLane, intersection: Node3D, entry: Vector3, exit_point: Vector3, entry_dir: Vector3, exit_dir: Vector3, extend_exit: bool = true) -> void:
	var to_local: Transform3D = lane.global_transform.affine_inverse()
	var dir_in := (to_local.basis * entry_dir).normalized()
	var dir_out := (to_local.basis * exit_dir).normalized()
	var entry_stop := to_local * entry
	var exit_stop := to_local * exit_point
	var entry_stopsize := STOP_ROW_SIZE * entry_dir.length() # / RoadPoint.DEFAULT_LANE_WIDTH
	var lead := dir_in * (entry_stopsize / 3.0) # TODO: fix non lane-width aware row size
	var handle := entry_stop.distance_to(exit_stop) / 3.0

	var curve := Curve3D.new()
	# Lead in from the entry RoadPoint to its stop line, then arc across.
	curve.add_point(entry_stop - dir_in * entry_stopsize, Vector3.ZERO, lead)
	curve.add_point(entry_stop, -lead, dir_in * handle)
	if extend_exit:
		# Arc to the exit stop line, then lead out to the exit RoadPoint.
		var exit_stopsize := STOP_ROW_SIZE * exit_dir.length() # / RoadPoint.DEFAULT_LANE_WIDTH
		var out_lead := dir_out * (exit_stopsize / 3.0) # TODO: fix non lane-width aware row size
		curve.add_point(exit_stop, -dir_out * handle, out_lead)
		curve.add_point(exit_stop + dir_out * exit_stopsize, -out_lead, Vector3.ZERO) # TODO: fix non lane-width aware row size
	else:
		curve.add_point(exit_stop, -dir_out * handle, Vector3.ZERO)
	lane.curve = curve


## Builds a lane's tagged name in the segment-lane style, prefixed by the source
## edge: `edge_pTAG_nTAG` for a straight through lane, with an `a` suffix for a
## turn or `r` for an outer lane squeezed into a merge. A counter is appended when
## a name would otherwise repeat (e.g. two turns off the same lane), keeping every
## lane uniquely and stably named for reuse across rebuilds.
func _tagged_lane_name(used: Dictionary, edge_name: String, tag: String, suffix: String) -> String:
	var base := "%s_p%s_n%s%s" % [edge_name, tag, tag, suffix]
	var lane_name := base
	var counter := 2
	while used.has(lane_name):
		lane_name = "%s%d" % [base, counter]
		counter += 1
	used[lane_name] = true
	return lane_name


## World-space outer gutter corners of an edge, matching the intersection mesh's
## exterior border. Returns the two facing-normalised sides (`s0`/`s1`, ordered as
## the mesh stores them in edge_gutters) each at the RoadPoint (`s0`/`s1`) and at
## the stop line (`s0_stop`/`s1_stop`). Held in the road plane (no vertical gutter
## drop) and offset like the [RoadSegment] edge curves so the two line up across
## the RoadPoint. Divider-aligned edges split their offset by direction to match
## the segment edge curves rather than the mesh's geometric centreline.
func _edge_exterior_corners(edge: RoadPoint, intersection: Node3D) -> Dictionary:
	var facing: _IntersectNGonFacing = _get_edge_facing(edge, intersection)
	var perpendicular_v: Vector3 = edge.global_transform.basis.x.normalized()
	var parallel_v: Vector3 = edge.global_transform.basis.z.normalized()
	if facing == _IntersectNGonFacing.ORIGIN:
		parallel_v = -parallel_v
	var origin: Vector3 = edge.global_transform.origin

	var offset_l: float
	var offset_r: float
	if edge.alignment == RoadPoint.Alignment.GEOMETRIC:
		var half_width: float = edge.lanes.size() * edge.lane_width * 0.5
		offset_l = half_width
		offset_r = half_width
	else:
		offset_l = edge.get_rev_lane_count() * edge.lane_width
		offset_r = edge.get_fwd_lane_count() * edge.lane_width
	offset_l += edge.shoulder_width_l + edge.gutter_profile[0]
	offset_r += edge.shoulder_width_r + edge.gutter_profile[0]

	var gutter_l: Vector3 = origin - perpendicular_v * offset_l
	var gutter_r: Vector3 = origin + perpendicular_v * offset_r
	var stop: Vector3 = parallel_v * STOP_ROW_SIZE

	if facing == _IntersectNGonFacing.ORIGIN:
		return {
			"s0": gutter_l, "s0_stop": gutter_l + stop,
			"s1": gutter_r, "s1_stop": gutter_r + stop,
		}
	return {
		"s0": gutter_r, "s0_stop": gutter_r + stop,
		"s1": gutter_l, "s1_stop": gutter_l + stop,
	}


## Finds an existing edge curve by name or creates one, mirroring the editor
## metadata of [RoadSegment] edge curves. The existing node is always reused so
## any children the user has parented to it survive regeneration.
func _get_or_create_edge_curve(intersection: Node3D, edge_name: String) -> Path3D:
	var existing := intersection.get_node_or_null(edge_name)
	if existing is Path3D:
		return existing
	var path := Path3D.new()
	intersection.add_child(path)
	path.name = edge_name
	path.owner = intersection.owner
	path.set_meta("_edit_lock_", true)
	return path


## Writes the four-point exterior boundary curve for one edge into `path`, in its
## local space: from the edge's outer RoadPoint corner along its gutter to the
## stop line, across to the neighbour's stop line, then out to the neighbour's
## RoadPoint corner. Handles are sharp (non-aligned) at the two bends, pointing
## straight at the source corner and the opposite corner, matching the low-poly
## [RoadSegment] edge-curve profile. A fresh [Curve3D] is assigned rather than the
## node replaced, so the path node and its children persist.
func _assign_edge_curve(path: Path3D, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> void:
	var to_local: Transform3D = path.global_transform.affine_inverse()
	var l0: Vector3 = to_local * p0
	var l1: Vector3 = to_local * p1
	var l2: Vector3 = to_local * p2
	var l3: Vector3 = to_local * p3

	var curve := Curve3D.new()
	curve.add_point(l0, Vector3.ZERO, (l1 - l0) / 3.0)
	curve.add_point(l1, (l0 - l1) / 3.0, (l2 - l1) / 3.0)
	curve.add_point(l2, (l1 - l2) / 3.0, (l3 - l2) / 3.0)
	curve.add_point(l3, (l2 - l3) / 3.0, Vector3.ZERO)
	path.curve = curve


## Frees previously generated edge curves that are no longer active, identified by
## the `edge_` prefix. RoadLanes (also Path3D children) are left untouched. Nodes
## are detached before being freed, mirroring [method RoadSegment.clear_edge_curves],
## so their names are released immediately rather than on the deferred free.
func _clear_generated_edge_curves(intersection: Node3D, keep: Array) -> void:
	for child in intersection.get_children():
		if child is RoadLane:
			continue
		if not (child is Path3D):
			continue
		if not str(child.name).begins_with(EDGE_PREFIX):
			continue
		if keep.has(child):
			continue
		intersection.remove_child(child)
		child.queue_free()


## Frees previously generated lanes that are no longer active.
func _clear_generated_lanes(intersection: Node3D, keep: Array[RoadLane]) -> void:
	for child in intersection.get_children():
		if not (child is RoadLane):
			continue
		if is_instance_valid(child.owner):
			continue
		if keep.has(child):
			continue
		child.queue_free()


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
	## RoadPoint-side counterparts of the stop-line arrays, for the underside.
	var edge_shoulders_rp: Array[Array] = []
	var edge_gutters_rp: Array[Array] = []
	## Per-edge up vector, to drop the underside by thickness.
	var edge_ups: Array[Vector3] = []
	## Per-edge underside thickness resolved from each RoadPoint.
	var edge_thicknesses: Array[float] = []
	
	const uv_width := 0.125 # 1/8 for breakdown of texture.
	const uv_gutter_width := uv_width * SegGeo.UV_MID_SHOULDER
	var density := container.effective_density()

	for edge: RoadPoint in edges:
		var facing: _IntersectNGonFacing = _get_edge_facing(edge, intersection)
		if facing == _IntersectNGonFacing.OTHER:
			push_error("Unexpected RoadPoint state in IntersectionNGon mesh generation (next/prior points both null or defined on %s). Returning an empty mesh." % [edge.name])
			return Mesh.new() # Empty mesh.
		
		var lane_width: float = edge.lane_width
		var lanes_count = edge.traffic_dir.size() # use traffic_dir over lanes for consistency with segment generation
		var lanes_tot_width: float = lane_width * lanes_count
		var shoulder_offset_l: float = edge.shoulder_width_l
		var shoulder_offset_r: float = edge.shoulder_width_r
		var gutter: Vector2 = edge.gutter_profile
		var alignment_offset: float = 0.0
		if edge.alignment == RoadPoint.Alignment.DIVIDER:
			alignment_offset = (edge.get_rev_lane_count() - edge.traffic_dir.size() / 2.0) * edge.lane_width
		
		# Aim for real-world texture proportions width:height of 2:1 matching texture,
		# but then the hight of 1 full UV is half the with across all lanes, so another 2x
		var uv_height := STOP_ROW_SIZE / lane_width / RoadPoint.DEFAULT_LANE_WIDTH / 2 # ratio of 1/4th down vs width of image to be square

		var perpendicular_v: Vector3 = (edge.transform.basis.x).normalized()
		var up_vector: Vector3 = (edge.transform.basis.y).normalized()
		var parallel_v: Vector3 = (edge.transform.basis.z).normalized()

		var road_side_l: Vector3 = edge.position
		var road_side_r: Vector3 = edge.position
		road_side_l -= perpendicular_v * (lanes_tot_width / 2.0)
		road_side_r += perpendicular_v * (lanes_tot_width / 2.0)
		road_side_l -= perpendicular_v * alignment_offset
		road_side_r -= perpendicular_v * alignment_offset

		var shoulder_l: Vector3 = road_side_l
		var shoulder_r: Vector3 = road_side_r
		shoulder_l -= shoulder_offset_l * perpendicular_v
		shoulder_r += shoulder_offset_r * perpendicular_v

		var gutter_l: Vector3 = shoulder_l + (gutter[0] * -perpendicular_v + gutter[1] * up_vector)
		var gutter_r: Vector3 = shoulder_r + (gutter[0] * perpendicular_v + gutter[1] * up_vector)

		if facing == _IntersectNGonFacing.ORIGIN:
			parallel_v = -parallel_v

		var stopsize := STOP_ROW_SIZE * edge.lane_width / RoadPoint.DEFAULT_LANE_WIDTH

		var shoulder_l_stop: Vector3 = shoulder_l + parallel_v * stopsize
		var shoulder_r_stop: Vector3 = shoulder_r + parallel_v * stopsize
		var gutter_l_stop: Vector3 = gutter_l + parallel_v * stopsize
		var gutter_r_stop: Vector3 = gutter_r + parallel_v * stopsize
		var road_side_l_stop: Vector3 = road_side_l + parallel_v * stopsize
		var road_side_r_stop: Vector3 = road_side_r + parallel_v * stopsize

		if facing == _IntersectNGonFacing.ORIGIN:
			edge_shoulders.append([shoulder_l_stop, shoulder_r_stop])
			edge_gutters.append([gutter_l_stop, gutter_r_stop])
			edge_road_sides.append([road_side_l_stop, road_side_r_stop])
			edge_shoulders_rp.append([shoulder_l, shoulder_r])
			edge_gutters_rp.append([gutter_l, gutter_r])
		else: # facing == _IntersectNGonFacing.AWAY
			edge_shoulders.append([shoulder_r_stop, shoulder_l_stop])
			edge_gutters.append([gutter_r_stop, gutter_l_stop])
			edge_road_sides.append([road_side_r_stop, road_side_l_stop])
			edge_shoulders_rp.append([shoulder_r, shoulder_l])
			edge_gutters_rp.append([gutter_r, gutter_l])
		edge_ups.append(up_vector)
		edge_thicknesses.append(edge.get_thickness())

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
			var lane_left_side_stop: Vector3 = lane_left_side + parallel_v * stopsize
			var lane_right_side_stop: Vector3 = lane_right_side + parallel_v * stopsize

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

	# Underside only when every edge resolves a thickness, so e.g. a raised ramp
	# leading into a ground-level intersection does not force underside geo.
	if edges.size() >= 2 and edge_thicknesses.min() >= 0.0:
		surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		_insert_underside_geo(surface_tool, edge_thicknesses, parent_transform,
				edge_shoulders_rp, edge_shoulders, edge_gutters_rp, edge_gutters, edge_ups)
		surface_tool.index()
		var underside_material: Material = container.effective_underside_material()
		if underside_material:
			surface_tool.set_material(underside_material)
		surface_tool.generate_normals()
		surface_tool.commit(mesh)
	return mesh


## Generates the underside as a second surface: a triangle fan over the
## stop-line perimeter, one quad per branch out to its RoadPoint line, and rim
## quads rising back up to the top surface's gutter lip. Deliberately less
## detailed than the top side, but folding at the same stop line so top and
## underside shear at the same point.
## Thickness comes from each edge RoadPoint (caller ensures all are >= 0),
## interpolating across connections, with the center at the average depth.
## The crossings at each RoadPoint line stay open so the underside profile mates
## with the adjoining [RoadSegment] underside (flat bottom spanning the
## shoulders, then a slope out to the gutter lip).
## Point arrays follow the facing-normalised [s0, s1] ordering of the top-side
## arrays; edges MUST have been sorted beforehand.
func _insert_underside_geo(
		st: SurfaceTool,
		thicknesses: Array[float],
		parent_transform: Transform3D,
		shoulders_rp: Array[Array],
		shoulders_stop: Array[Array],
		gutters_rp: Array[Array],
		gutters_stop: Array[Array],
		ups: Array[Vector3]) -> void:
	const UNDERSIDE_RIM_SMOOTHING_GROUP = 1
	const MIN_THICKNESS = 0.001 # Prevents Z-fighting, matching segment undersides
	# Match segment undersides: one UV tile spans four default-width lanes.
	var uv_scale := 1.0 / (4.0 * RoadPoint.DEFAULT_LANE_WIDTH)
	var origin := parent_transform.origin

	# Perimeter walk per branch: from the s1 stop corner out to the RoadPoint,
	# across the RP line, back in along s0 to its stop corner, then over to the
	# next branch. Bottom points are shoulder corners dropped by the edge's own
	# thickness; rim tops are the matching gutter corners on the top surface.
	var bottom: Array[Vector3] = []
	var rim_top: Array[Vector3] = []
	var has_rim: Array[bool] = []
	var avg_thickness := 0.0
	for i in range(shoulders_rp.size()):
		var thickness: float = maxf(thicknesses[i], MIN_THICKNESS)
		avg_thickness += thickness / shoulders_rp.size()
		var drop: Vector3 = -ups[i] * thickness
		bottom.append(shoulders_stop[i][1] + drop - origin)
		bottom.append(shoulders_rp[i][1] + drop - origin)
		bottom.append(shoulders_rp[i][0] + drop - origin)
		bottom.append(shoulders_stop[i][0] + drop - origin)
		rim_top.append(gutters_stop[i][1] - origin)
		rim_top.append(gutters_rp[i][1] - origin)
		rim_top.append(gutters_rp[i][0] - origin)
		rim_top.append(gutters_stop[i][0] - origin)
		has_rim.append(true)   # s1 lateral side
		has_rim.append(false)  # RP line, left open to mate with the segment
		has_rim.append(true)   # s0 lateral side
		has_rim.append(true)   # connection toward the next branch

	# Bottom fan from the dropped center over the stop-line corners only, so the
	# underside folds at the stop line like the top surface. Wound to face down.
	var center: Vector3 = -parent_transform.basis.y.normalized() * avg_thickness
	var count := bottom.size()
	st.set_smooth_group(0)
	for k in range(0, count, 4):
		var s1_stop: Vector3 = bottom[k]
		var s0_stop: Vector3 = bottom[k + 3]
		var next_s1_stop: Vector3 = bottom[(k + 4) % count]
		# Wedge across this branch's stop line, then to the next branch.
		for tri in [[s0_stop, s1_stop], [next_s1_stop, s0_stop]]:
			st.set_uv(Vector2(center.x, center.z) * uv_scale)
			st.add_vertex(center)
			st.set_uv(Vector2(tri[0].x, tri[0].z) * uv_scale)
			st.add_vertex(tri[0])
			st.set_uv(Vector2(tri[1].x, tri[1].z) * uv_scale)
			st.add_vertex(tri[1])

	# One quad per branch from its stop line out to the RoadPoint line.
	for k in range(0, count, 4):
		var pts: Array = [bottom[k + 3], bottom[k + 2], bottom[k + 1], bottom[k]]
		var uvs: Array = []
		for pt in pts:
			uvs.append(Vector2(pt.x, pt.z) * uv_scale)
		SegGeo.quad(st, uvs, pts)

	# Rim quads from the bottom perimeter up to the gutter lip, U continuing
	# along the perimeter, V spanning the slant height.
	var run := 0.0
	for k in range(count):
		var k_next := (k + 1) % count
		var g1: Vector3 = rim_top[k]
		var g2: Vector3 = rim_top[k_next]
		var width := (g2 - g1).length()
		if not has_rim[k]:
			run += width
			continue
		var b1: Vector3 = bottom[k]
		var b2: Vector3 = bottom[k_next]
		SegGeo.quad(st,
			[
				Vector2((run + width) * uv_scale, 0.0),
				Vector2(run * uv_scale, 0.0),
				Vector2(run * uv_scale, (g1 - b1).length() * uv_scale),
				Vector2((run + width) * uv_scale, (g2 - b2).length() * uv_scale),
			],
			[g2, g1, b1, b2],
			UNDERSIDE_RIM_SMOOTHING_GROUP)
		run += width


#endregion
# ------------------------------------------------------------------------------
