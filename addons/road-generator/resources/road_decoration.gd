@tool
extends Resource
class_name RoadDecoration

enum Side {
	FORWARD,
	REVERSE,
	BOTH
}

const RoadSegment = preload("res://addons/road-generator/nodes/road_segment.gd")

@export var desc: String = "default"
@export var side: RoadCurb.Side = RoadCurb.Side.REVERSE
@export var offset_start: float = 0.0
@export var offset_end: float = 0.0
@export var offset_lateral: float = -0.5
@export var offset_lateral_profile: Curve

func setup(segment: RoadSegment, decoration_node_wrapper: Node3D) -> void:
	pass


func _get_curve_with_offsets(segment: RoadSegment, edge: Path3D) -> Curve3D:
	## Based on edge curves, apply start/end offsets and lateral offsets (fixed and profile-based)
	# Start from the original edge curve and trim it with start/end offsets (same as base)
	var original_curve: Curve3D = edge.curve
	var new_curve: Curve3D = Curve3D.new()

	var total_length: float = original_curve.get_baked_length()

	# so this might be confusing, but curves go from e.g. RP_002 to RP_001,
	# so basically go reverse, therefore start and end are swapped
	var start_distance: float = offset_end
	var end_distance: float = total_length - offset_start

	var num_points: int = int((end_distance - start_distance) / 0.1) + 1
	if num_points < 2:
		num_points = 2

	# Find the opposite edge to know which way "outwards" is
	var other_edge: Path3D = null
	if edge.name == segment.EDGE_R_NAME and segment.get_parent().has_node(segment.EDGE_F_NAME):
		other_edge = segment.get_parent().get_node(segment.EDGE_F_NAME)
	elif edge.name == segment.EDGE_F_NAME and segment.get_parent().has_node(segment.EDGE_R_NAME):
		other_edge = segment.get_parent().get_node(segment.EDGE_R_NAME)

	if not other_edge:
		return null
	print(edge.name)
	var other_curve: Curve3D = other_edge.curve

	for i in range(num_points):
		var t_along: float = float(i) / float(num_points - 1)  # 0..1 along the curb
		var distance: float = lerp(start_distance, end_distance, t_along)

		var pos: Vector3 = original_curve.sample_baked(distance)

		# Extra lateral offset from profile (in meters)
		var extra_offset: float = 0.0
		if offset_lateral_profile:
			# x axis of the Curve is 0..1 along the curb
			extra_offset = offset_lateral_profile.sample(t_along)
		else:
			extra_offset = offset_lateral

		if extra_offset != 0.0:
			# Use the direction from the opposite edge to this edge as "outwards"
			var other_pos: Vector3 = other_curve.sample_baked(distance)
			var outward_dir: Vector3 = (pos - other_pos).normalized()
			print(outward_dir * extra_offset)
			if outward_dir != Vector3.ZERO:
				pos += outward_dir * extra_offset

		new_curve.add_point(pos)

	return new_curve
