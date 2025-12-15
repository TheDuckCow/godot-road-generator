@tool
extends RoadDecoration
class_name SingleMeshSceneAlongCurve

@export_group("Instance Properties")
## Scene with Mesh to instance along the curve
@export var mesh_source_scene: PackedScene:
	set(value):
		mesh_source_scene = value
		decoration_changed.emit()

## Relative position along the (trimmed) curve where the object is placed.
## 0.0 = at the start after applying offsets, 1.0 = at the end.
@export_range(0.0, 1.0) var position_along_curve: float = 0.5:
	set(value):
		position_along_curve = value
		decoration_changed.emit()

## Manual scaling of object
@export var manual_scaling_object: Vector3 = Vector3.ONE:
	set(value):
		manual_scaling_object = value
		decoration_changed.emit()

## Rotation of object in degrees when placed along curve
## If your mesh points along X axis, you might want to set Y to 90 degrees.
@export var rotation_object_degree: Vector3 = Vector3(0, -90, 0):
	set(value):
		rotation_object_degree = value
		decoration_changed.emit()

## Move object by this much when placing in local coords.
## Try to work with the placement of the mesh in the scene itself first. Also offset lateral might help.
## This is just included to offer maximum flexibility.
@export var manual_offset_object: Vector3 = Vector3.ZERO:
	set(value):
		manual_offset_object = value
		decoration_changed.emit()

func _init() -> void:
	description = "single_scene_mesh_along_curve"

func setup(segment: RoadSegment, decoration_node_wrapper: Node3D) -> void:
	if not mesh_source_scene:
		push_error("No mesh_source_scene assigned for SingleMeshSceneAlongCurve decoration.")
		return

	# place scene based on the selected side(s)
	if side == RoadCurb.Side.BOTH or side == RoadCurb.Side.REVERSE:
		var edge_r: Path3D = segment.get_parent().get_node(segment.EDGE_R_NAME)
		_instance_scene_on_edge(decoration_node_wrapper, segment, edge_r, "R")
	
	if side == RoadCurb.Side.BOTH or side == RoadCurb.Side.FORWARD:
		var edge_f: Path3D = segment.get_parent().get_node(segment.EDGE_F_NAME)
		_instance_scene_on_edge(decoration_node_wrapper, segment, edge_f, "F")


func _instance_scene_on_edge(decoration_node_wrapper: Node3D, segment: RoadSegment, edge: Path3D, side: String) -> void:
	"""Instance a single scene along the edge curve with banking/elevation."""
	if not edge or not is_instance_valid(edge):
		push_error("Invalid edge provided to _instance_scene_on_edge")
		return

	var original_curve: Curve3D = edge.curve
	if original_curve == null:
		push_error("Edge curve is null in _instance_scene_on_edge")
		return

	var total_length: float = original_curve.get_baked_length()
	if total_length <= 0.0:
		push_error("Original curve has zero length.")
		return

	# --- Trim original curve by offset_start / offset_end ---
	# offset_start: cut this fraction from the *start* of the curve
	# offset_end:   cut this fraction from the *end* of the curve
	var trimmed_start: float = offset_start * total_length
	var trimmed_end: float = total_length - offset_end * total_length
	var trimmed_length: float = trimmed_end - trimmed_start

	if trimmed_length <= 0.0:
		push_error("Trimmed length <= 0. Check offset_start / offset_end.")
		return

	# --- Position along the trimmed range (0..1) ---
	var t: float = clampf(position_along_curve, 0.0, 1.0)
	var distance_on_original: float = trimmed_start + t * trimmed_length

	# Banked frame on the original curve at that distance
	var frame := _compute_bank_frame(segment, edge, distance_on_original)
	var basis: Basis = frame.basis
	var position_on_edge: Vector3 = frame.position
	var outward_dir: Vector3 = frame.outward_dir

	# --- Apply lateral offset / profile in the same way as _get_curve_with_offsets ---
	var extra_offset: float = 0.0
	if offset_lateral_profile:
		# t_for_profile is 0..1 along the trimmed range
		var t_for_profile: float = 0.0
		if trimmed_length > 0.0:
			t_for_profile = (distance_on_original - trimmed_start) / trimmed_length
		t_for_profile = clampf(t_for_profile, 0.0, 1.0)
		# Same convention as in _get_curve_with_offsets: sample(1.0 - t)
		extra_offset = offset_lateral_profile.sample(1.0 - t_for_profile)
	else:
		extra_offset = offset_lateral

	var final_position: Vector3 = position_on_edge
	if extra_offset != 0.0 and outward_dir != Vector3.ZERO:
		final_position += outward_dir * extra_offset

	# Extra rotation in local path frame
	var extra_rot: Basis = Basis.from_euler(Vector3(
		deg_to_rad(rotation_object_degree.x),
		deg_to_rad(rotation_object_degree.y),
		deg_to_rad(rotation_object_degree.z)
	))
	basis = basis * extra_rot

	# Create and place the instance
	var decomesh: Node3D = mesh_source_scene.instantiate()
	if decomesh == null:
		push_error("Failed to instance mesh_source_scene in _instance_scene_on_edge")
		return

	decomesh.name = side + "_single_instance"
	decomesh.scale = manual_scaling_object

	# Apply orientation and final position (+ local manual offset)
	decomesh.basis = basis
	decomesh.position = final_position + basis * manual_offset_object

	decoration_node_wrapper.add_child(decomesh)
	decomesh.set_owner(segment.get_tree().get_edited_scene_root())
