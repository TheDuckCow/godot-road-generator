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

func setup(segment: RoadSegment, decoration_node_wrapper: Node3D) -> void:
	pass

func _get_curve_with_applied_offsets(edge: Path3D, offset_start: float, offset_end: float) -> Curve3D:
	# Returns a new Curve3D with the specified start and end offsets applied
	var original_curve: Curve3D = edge.curve
	var new_curve: Curve3D = Curve3D.new()

	var total_length: float = original_curve.get_baked_length()

	# so this might be confusing, but curves go from e.g. RP_002 to RP_001,
	# so basically go reverse, therefore start and end are swapped
	var start_distance: float = offset_end
	var end_distance: float = total_length - offset_start

	var num_points: int = int((end_distance - start_distance) / 0.1) + 1
	for i in range(num_points):
		var distance: float = lerp(start_distance, end_distance, float(i) / float(num_points - 1))
		var position: Vector3 = original_curve.sample_baked(distance)
		new_curve.add_point(position)

	return new_curve
