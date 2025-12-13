@tool
extends Resource
class_name RoadDecoration

enum Side {
	FORWARD,
	REVERSE,
	BOTH
}

const RoadSegment = preload("res://addons/road-generator/nodes/road_segment.gd")

var parent_road_point: RoadPoint = null

@export_group("General Decoration Properties")
## Description used for nodes in scene tree
@export var description: String = "default":
	set(value):
		description = value
		check_auto_refresh()
## which side to place decoration on
@export var side: RoadDecoration.Side = RoadDecoration.Side.REVERSE:
	set(value):
		side = value
		check_auto_refresh()
## relative start offset along the segment
## 0.2 means that decoration starts after 20% length along the segment
@export_range(0,1) var offset_start: float = 0.0:
	set(value):
		offset_start = value
		check_auto_refresh()
## relative end offset along the segment
## 0.2 means that decoration ends at 80% length along the segment
@export_range(0,1) var offset_end: float = 0.0:
	set(value):
		offset_end = value
		check_auto_refresh()
## absolut lateral offset in meters from the edge curve along the whole curve
## negative values go "inwards", positive values "outwards" from the road
## use offset_lateral_profile for more advanced lateral offsets
@export var offset_lateral: float = -0.5:
	set(value):
		offset_lateral = value
		check_auto_refresh()
## specify lateral offset profile (Curve) from 0..1 along the curb
## domain needs to be between 0 and 1, they describe the relative position along the curve.
## The value offset is the same as in parameter offset_lateral, just that you can vary it along the curve.
@export var offset_lateral_profile: Curve = null:
	set(value):
		offset_lateral_profile = value
		check_auto_refresh()

# this saved the road point for later use
func init(road_point: RoadPoint) -> void:
	parent_road_point = road_point

# this must be overwritten in subclasses
# should be translated to abstract class in future Godot versions
func setup(segment: RoadSegment, decoration_node_wrapper: Node3D) -> void:
	pass


# If auto-refresh is enabled on the container, trigger a rebuild
func check_auto_refresh():
	var container = parent_road_point.container
	if container.get_manager().auto_refresh:
		container.rebuild_segments(true)
	

func _get_curve_with_offsets(segment: RoadSegment, edge: Path3D) -> Curve3D:
	## Based on edge curves, apply start/end offsets and lateral offsets (fixed and profile-based)
	# Start from the original edge curve and trim it with start/end offsets (same as base)
	var original_curve: Curve3D = edge.curve
	var new_curve: Curve3D = Curve3D.new()

	var total_length: float = original_curve.get_baked_length()

	# so this might be confusing, but curves go from e.g. RP_002 to RP_001,
	# so basically go reverse, therefore start and end are swapped
	var start_distance: float = offset_end * total_length
	var end_distance: float = total_length - offset_start * total_length
	var trimmed_length: float = end_distance - start_distance
	if trimmed_length <= 0.0:
		return null

	var num_points: int = int(trimmed_length / 0.1) + 1
	if num_points < 2:
		num_points = 2

	# Find the opposite edge to know which way "outwards" is
	var other_edge: Path3D = _get_other_edge(segment, edge)
	if not other_edge:
		return null
	
	var other_curve: Curve3D = other_edge.curve
	var other_curve_total_length: float = other_curve.get_baked_length()
	var ratio_curve_lengths: float = 1.0
	if total_length > 0.0:
		ratio_curve_lengths = other_curve_total_length / total_length

	for i in range(num_points):
		var t_along: float = float(i) / float(num_points - 1)  # 0..1 along the curb
		var distance: float = lerp(start_distance, end_distance, t_along)

		var pos: Vector3 = original_curve.sample_baked(distance)

		# Extra lateral offset from profile (in meters)
		var extra_offset: float = 0.0
		if offset_lateral_profile:
			# x axis of the Curve is 0..1 along the curb
			# as for start and end distance, we go reverse along the edge curve for intuitive reasons
			extra_offset = offset_lateral_profile.sample(1.0 - t_along)
		else:
			extra_offset = offset_lateral

		if extra_offset != 0.0:
			# Use the direction from the opposite edge to this edge as "outwards"
			var other_pos: Vector3 = other_curve.sample_baked(distance * ratio_curve_lengths)
			var outward_dir: Vector3 = (pos - other_pos).normalized()
			
			if outward_dir != Vector3.ZERO:
				pos += outward_dir * extra_offset

		new_curve.add_point(pos)

	return new_curve


func _get_other_edge(segment: RoadSegment, edge: Path3D) -> Path3D:
	# Returns the opposite edge of the road (R <-> F)
	var parent := segment.get_parent()
	if edge.name == segment.EDGE_R_NAME and parent.has_node(segment.EDGE_F_NAME):
		return parent.get_node(segment.EDGE_F_NAME)
	elif edge.name == segment.EDGE_F_NAME and parent.has_node(segment.EDGE_R_NAME):
		return parent.get_node(segment.EDGE_R_NAME)
	return null


func _get_trim_parameters(curve: Curve3D) -> Dictionary:
	# Returns total_length, start_distance, end_distance, trimmed_length
	var total_length: float = curve.get_baked_length()
	var start_distance: float = offset_end * total_length
	var end_distance: float = total_length - offset_start * total_length
	return {
		"total_length": total_length,
		"start_distance": start_distance,
		"end_distance": end_distance,
		"trimmed_length": end_distance - start_distance,
	}


func _compute_bank_frame(segment: RoadSegment, edge: Path3D, distance_on_original: float) -> Dictionary:
	# Compute a banked local frame on the original edge at a given distance.
	# Returns:
	# {
	#   "position": Vector3,
	#   "basis": Basis,
	#   "forward_dir": Vector3,
	#   "up_dir": Vector3,
	#   "outward_dir": Vector3,
	# }

	var original_curve: Curve3D = edge.curve
	var trim := _get_trim_parameters(original_curve)
	var total_length: float = trim.total_length

	if total_length <= 0.0:
		return {
			"position": Vector3.ZERO,
			"basis": Basis(),
			"forward_dir": Vector3.FORWARD,
			"up_dir": Vector3.UP,
			"outward_dir": Vector3.RIGHT,
		}

	distance_on_original = clampf(distance_on_original, 0.0, total_length)

	var pos_edge: Vector3 = original_curve.sample_baked(distance_on_original)

	# Forward direction along the edge
	var delta_d: float = 0.1
	var distance_ahead: float = min(distance_on_original + delta_d, total_length)
	var pos_ahead: Vector3 = original_curve.sample_baked(distance_ahead)

	var forward_dir: Vector3 = (pos_ahead - pos_edge).normalized()
	if forward_dir == Vector3.ZERO:
		var distance_back: float = max(distance_on_original - delta_d, 0.0)
		var pos_back: Vector3 = original_curve.sample_baked(distance_back)
		forward_dir = (pos_edge - pos_back).normalized()
	if forward_dir == Vector3.ZERO:
		forward_dir = Vector3.FORWARD

	# Outward direction using opposite edge
	var other_edge: Path3D = _get_other_edge(segment, edge)
	var outward_dir: Vector3 = Vector3.RIGHT

	if other_edge:
		var other_curve: Curve3D = other_edge.curve
		var other_len: float = other_curve.get_baked_length()
		var ratio_curve_lengths: float = 1.0
		if total_length > 0.0:
			ratio_curve_lengths = other_len / total_length

		var other_pos: Vector3 = other_curve.sample_baked(distance_on_original * ratio_curve_lengths)
		outward_dir = (pos_edge - other_pos).normalized()
		if outward_dir == Vector3.ZERO:
			outward_dir = Vector3.RIGHT

	# Up direction encodes banking
	var up_dir: Vector3 = forward_dir.cross(outward_dir).normalized()
	if up_dir == Vector3.ZERO:
		up_dir = Vector3.UP

	# Ensure up is not upside down relative to world up
	if up_dir.dot(Vector3.UP) < 0.0:
		up_dir = -up_dir
		outward_dir = -outward_dir

	# Right dir – orthonormal basis
	var right_dir: Vector3 = up_dir.cross(forward_dir).normalized()
	if right_dir == Vector3.ZERO:
		right_dir = outward_dir

	var basis: Basis = Basis(right_dir, up_dir, forward_dir)

	return {
		"position": pos_edge,
		"basis": basis,
		"forward_dir": forward_dir,
		"up_dir": up_dir,
		"outward_dir": outward_dir,
	}
