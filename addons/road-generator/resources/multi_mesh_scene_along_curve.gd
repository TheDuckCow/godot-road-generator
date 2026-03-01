@tool
extends RoadDecoration
class_name MultiMeshSceneAlongCurve

@export_group("Instance Properties")
## Scene with Mesh to instance along the curve
@export var mesh_source_scene: PackedScene:
	set(value):
		mesh_source_scene = value
		decoration_changed.emit()
## Space between objects when placing along curve
@export var spacing_along_curve: float = 0:
	set(value):
		spacing_along_curve = value
		decoration_changed.emit()

## Automatically scale object to fit curve length (considers offsets below).
## This overrides manual scaling.
## Works best if the mesh is short. This checks how often mesh would fit along curve.
## If it would fit 8.6 times, it will be scaled so that it fits exactly 9 times.
@export var automatic_scaling: bool = true:
	set(value):
		automatic_scaling = value
		decoration_changed.emit()
@export_subgroup("Advanced Properties")
## If x axes is automatically scaled, scale y axes the same way
@export var automatic_scaling_along_y_axes: bool = true:
	set(value):
		automatic_scaling_along_y_axes = value
		decoration_changed.emit()
## If x axes is automatically scaled, scale z axes the same way
@export var automatic_scaling_along_z_axes: bool = true:
	set(value):
		automatic_scaling_along_z_axes = value
		decoration_changed.emit()
## Manual scaling of object. Not used if automatic_scaling is true.
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
	description = "multi_scene_mesh_along_curve"

func setup(segment: RoadSegment, decoration_node_wrapper: Node3D) -> void:
	if not mesh_source_scene:
		push_error("No mesh_source_scene assigned for InstanceAlongCurve decoration.")
		return
	
	# check if source scene has a mesh
	var decomesh = mesh_source_scene.instantiate()
	if not decomesh or not decomesh.has_method("get_aabb"):
		push_error("The mesh_source_scene does not have a mesh or is invalid.")
		return

	# place scene based on the selected side(s)
	if side == RoadCurb.Side.BOTH or side == RoadCurb.Side.REVERSE:
		var edge: Path3D = segment.get_parent().get_node(segment.EDGE_R_NAME)
		_instance_scene_on_edge(decoration_node_wrapper, segment, edge, "R")
	
	if side == RoadCurb.Side.BOTH or side == RoadCurb.Side.FORWARD:
		var edge: Path3D = segment.get_parent().get_node(segment.EDGE_F_NAME)
		_instance_scene_on_edge(decoration_node_wrapper, segment, edge, "F")

func _instance_scene_on_edge(decoration_node_wrapper: Node3D, segment: RoadSegment, edge: Path3D, side: String) -> void:
	"""Instance the scene along the edge curve with banking/elevation."""
	if not edge or not is_instance_valid(edge):
		push_error("Invalid edge provided to _instance_scene_on_edge")
		return

	var decomesh = mesh_source_scene.instantiate()

	# Get object length from its bounding box (along local X)
	var aabb: AABB = decomesh.mesh.get_aabb()
	var object_length: float = aabb.size.x

	# Curve with offsets (trimmed + lateral)
	var curve_with_offsets: Curve3D = _get_curve_with_offsets(segment, edge)
	if curve_with_offsets == null:
		push_error("curve_with_offsets is null in _instance_scene_on_edge")
		return

	var curve_length: float = curve_with_offsets.get_baked_length()
	if curve_length <= 0.0:
		push_error("curve_with_offsets has zero length.")
		return

	# Trim parameters on the original edge curve
	var original_curve: Curve3D = edge.curve
	var trim := _get_trim_parameters(original_curve)
	var start_distance: float = trim.start_distance
	var end_distance: float = trim.end_distance
	var trimmed_length: float = trim.trimmed_length
	if trimmed_length <= 0.0:
		push_error("Trimmed length <= 0 in _instance_scene_on_edge")
		return

	# How many objects fit along the offset curve
	var num_fit: float = (curve_length - spacing_along_curve) / (object_length + spacing_along_curve)
	var num_fit_rounded: int = int(round(num_fit))
	if num_fit_rounded < 1:
		num_fit_rounded = 1

	# Automatic scaling along X
	if automatic_scaling:
		var scale_factor_x: float = (curve_length - spacing_along_curve * num_fit_rounded) / (object_length * num_fit_rounded)

		var scale_factor_y: float = scale_factor_x if automatic_scaling_along_y_axes else 1.0
		var scale_factor_z: float = scale_factor_x if automatic_scaling_along_z_axes else 1.0

		decomesh.scale = Vector3(scale_factor_x, scale_factor_y, scale_factor_z)
	else:
		decomesh.scale = manual_scaling_object

	var number_objects_placed: int = 0
	var current_length_covered: float = 0.0

	while number_objects_placed < num_fit_rounded:
		# Position on offset curve (already trimmed + lateral)
		var position_on_offset_curve: Vector3 = curve_with_offsets.sample_baked(current_length_covered)

		# 0..1 along offset curve
		var s_along_offset: float = current_length_covered / curve_length
		s_along_offset = clampf(s_along_offset, 0.0, 1.0)

		# Map to distance along original trim
		var distance_on_original_center: float = lerp(start_distance, end_distance, s_along_offset)

		# Sample orientation closer to the object's center
		var center_offset: float = object_length * decomesh.scale.x * 0.5
		distance_on_original_center = clampf(
			distance_on_original_center + center_offset,
			start_distance,
			end_distance
		)

		# Banked local frame from RoadDecoration helper
		var frame := _compute_bank_frame(segment, edge, distance_on_original_center)
		var basis: Basis = frame.basis

		# Add user-defined extra rotation in local path frame
		var extra_rot: Basis = Basis.from_euler(Vector3(
			deg_to_rad(rotation_object_degree.x),
			deg_to_rad(rotation_object_degree.y),
			deg_to_rad(rotation_object_degree.z)
		))
		basis = basis * extra_rot

		# Create instance
		var new_deco_mesh: Node3D = decomesh.duplicate()
		new_deco_mesh.name = side + "_instance_" + str(number_objects_placed)

		# First set orientation
		new_deco_mesh.basis = basis
		# Then position + manual local offset
		new_deco_mesh.position = position_on_offset_curve + basis * manual_offset_object

		decoration_node_wrapper.add_child(new_deco_mesh)
		new_deco_mesh.set_owner(segment.get_tree().get_edited_scene_root())

		current_length_covered += object_length * decomesh.scale.x + spacing_along_curve
		number_objects_placed += 1
