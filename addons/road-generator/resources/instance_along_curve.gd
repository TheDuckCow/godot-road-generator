@tool
extends RoadDecoration
class_name InstanceAlongCurve

@export_group("Instance Properties")
## Scene with Mesh to instance along the curve
@export var mesh_source_scene: PackedScene
## Space between objects when placing along curve
@export var spacing_along_curve: float = 0

## Automatically scale object to fit curve length (considers offsets below).
## This overrides manual scaling.
## Works best if the mesh is short. This checks how often mesh would fit along curve.
## If it would fit 8.6 times, it will be scaled so that it fits exactly 9 times.
@export var automatic_scaling: bool = true
@export_subgroup("Advanced Properties")
## If x axes is automatically scaled, scale y axes the same way
@export var automatic_scaling_along_y_axes: bool = true
## If x axes is automatically scaled, scale z axes the same way
@export var automatic_scaling_along_z_axes: bool = true
## Manual scaling of object. Not used if automatic_scaling is true.
@export var manual_scaling_object: Vector3 = Vector3.ONE
## Rotation of object in degrees when placed along curve
## If your mesh points along X axis, you might want to set Y to 90 degrees.
@export var rotation_object_degree: Vector3 = Vector3(0, -90, 0)
## Move object by this much when placing in local coords.
## Try to work with the placement of the mesh in the scene itself first. Also offset lateral might help.
## This is just included to offer maximum flexibility.
@export var manual_offset_object: Vector3 = Vector3.ZERO

func _init() -> void:
	description = "objects_along_curve"

func setup(segment: RoadSegment, decoration_node_wrapper: Node3D) -> void:
	if not mesh_source_scene:
		push_error("No mesh_source_scene assigned for InstanceAlongCurve decoration.")
		return
	
	# check if source scene has a mesh
	var decomesh = mesh_source_scene.instantiate()
	if not decomesh or not decomesh.has_method("get_aabb"):
		push_error("The mesh_source_scene does not have a mesh or is invalid.")
		return

	# Create new curbs based on the selected side(s)
	if side == RoadCurb.Side.BOTH or side == RoadCurb.Side.REVERSE:
		var edge: Path3D = segment.get_parent().get_node(segment.EDGE_R_NAME)
		_instance_scene_on_edge(decoration_node_wrapper, segment, edge, "R")
	
	if side == RoadCurb.Side.BOTH or side == RoadCurb.Side.FORWARD:
		var edge: Path3D = segment.get_parent().get_node(segment.EDGE_F_NAME)
		_instance_scene_on_edge(decoration_node_wrapper, segment, edge, "F")

func _instance_scene_on_edge(decoration_node_wrapper: Node3D, segment: RoadSegment, edge: Path3D, side: String):
	"""Instance the scene along the edge curve."""

	if not edge or not is_instance_valid(edge):
		push_error("Invalid edge provided to _instance_scene_on_edge")
		return

	var decomesh = mesh_source_scene.instantiate()

	# smallest box size to fit the mesh
	var aabb = decomesh.mesh.get_aabb()
	var box_size = aabb.size

	var object_length: float = box_size.x

	# we create a new path3d and curve3d for every curb to allow for offsets and independency in case multiple curbs are created
	var curve_with_offsets: Curve3D = _get_curve_with_offsets(segment, edge)
	if curve_with_offsets == null:
		push_error("curve_with_offsets is null in _instance_scene_on_edge")
		return

	var curve_length: float = curve_with_offsets.get_baked_length()
	if curve_length <= 0.0:
		push_error("curve_with_offsets has zero length.")
		return
	
	# compute same start/end distances as in _get_curve_with_offsets
	var original_curve: Curve3D = edge.curve
	var total_length: float = original_curve.get_baked_length()

	# same logic as in _get_curve_with_offsets
	var start_distance: float = offset_end * total_length
	var end_distance: float = total_length - offset_start * total_length
	var trimmed_length: float = end_distance - start_distance
	if trimmed_length <= 0.0:
		push_error("Trimmed length <= 0 in _instance_scene_on_edge")
		return

	# Find opposite edge to compute outward direction
	var other_edge: Path3D = null
	if edge.name == segment.EDGE_R_NAME and segment.get_parent().has_node(segment.EDGE_F_NAME):
		other_edge = segment.get_parent().get_node(segment.EDGE_F_NAME)
	elif edge.name == segment.EDGE_F_NAME and segment.get_parent().has_node(segment.EDGE_R_NAME):
		other_edge = segment.get_parent().get_node(segment.EDGE_R_NAME)

	var other_curve: Curve3D = null
	var ratio_curve_lengths: float = 1.0
	if other_edge:
		other_curve = other_edge.curve
		var other_curve_total_length: float = other_curve.get_baked_length()
		if total_length > 0.0:
			ratio_curve_lengths = other_curve_total_length / total_length
	else:
		push_warning("No opposite edge found. Banking may be wrong.")
		# We can still fall back to world up later.

	# How many objects fit along the (offset) curve
	var num_fit: float = (curve_length-spacing_along_curve) / (object_length+spacing_along_curve)
	var num_fit_rounded: int = int(round(num_fit))

	if automatic_scaling:
		var scale_factor_x: float = (curve_length - spacing_along_curve * num_fit_rounded) / (object_length*num_fit_rounded)
		
		var scale_factor_y: float
		var scale_factor_z: float

		if automatic_scaling_along_y_axes:
			scale_factor_y = scale_factor_x
		else:
			scale_factor_y = 1
		
		if automatic_scaling_along_z_axes:
			scale_factor_z = scale_factor_x
		else:
			scale_factor_z = 1
		
		var scale_factor: Vector3 = Vector3(scale_factor_x, scale_factor_y, scale_factor_z)
		
		decomesh.scale = scale_factor
	else:
		decomesh.scale = manual_scaling_object

	var number_objects_placed: int = 0
	var current_length_covered: float = 0.0

	while number_objects_placed < num_fit_rounded:
		# 1) Position from curve_with_offsets (already trimmed + lateral offset)
		var position_on_offset_curve: Vector3 = curve_with_offsets.sample_baked(current_length_covered)

		# 2) Normalized 0..1 along offset curve
		var s_along_offset: float = current_length_covered / curve_length
		s_along_offset = clampf(s_along_offset, 0.0, 1.0)

		# 3) Map to distance along original trimmed curve
		var distance_on_original: float = lerp(start_distance, end_distance, s_along_offset)
		distance_on_original = clampf(distance_on_original, 0.0, total_length)

		# --- Build orientation frame from geometry (no sample_baked_with_rotation) ---

		# Edge position at this distance
		var pos_edge: Vector3 = original_curve.sample_baked(distance_on_original)

		# Slightly ahead along the edge to compute forward direction
		var delta_d: float = 0.1
		var distance_ahead: float = min(distance_on_original + delta_d, total_length)
		var pos_ahead: Vector3 = original_curve.sample_baked(distance_ahead)

		var forward_dir: Vector3 = (pos_ahead - pos_edge).normalized()
		if forward_dir == Vector3.ZERO:
			# fallback: look backwards
			var distance_back: float = max(distance_on_original - delta_d, 0.0)
			var pos_back: Vector3 = original_curve.sample_baked(distance_back)
			forward_dir = (pos_edge - pos_back).normalized()

		# Outward direction from opposite edge (if available)
		var outward_dir: Vector3 = Vector3.RIGHT
		if other_curve:
			var other_pos: Vector3 = other_curve.sample_baked(distance_on_original * ratio_curve_lengths)
			outward_dir = (pos_edge - other_pos).normalized()
			if outward_dir == Vector3.ZERO:
				outward_dir = Vector3.RIGHT

		# Up direction as cross product (this encodes banking!)
		var up_dir: Vector3 = forward_dir.cross(outward_dir).normalized()
		if up_dir == Vector3.ZERO:
			up_dir = Vector3.UP

		# Ensure up is not upside down compared to global up
		# If it points more downward than upward, flip both up and outward
		if up_dir.dot(Vector3.UP) < 0.0:
			up_dir = -up_dir
			outward_dir = -outward_dir		

		# Recompute lateral/right to ensure orthonormal basis
		var right_dir: Vector3 = up_dir.cross(forward_dir).normalized()
		if right_dir == Vector3.ZERO:
			right_dir = outward_dir

		# Build basis: X = right, Y = up, Z = forward
		var basis: Basis = Basis(right_dir, up_dir, forward_dir)

		# Add user-defined extra rotation (in local space of the path frame)
		var extra_rot: Basis = Basis.from_euler(Vector3(
			deg_to_rad(rotation_object_degree.x),
			deg_to_rad(rotation_object_degree.y),
			deg_to_rad(rotation_object_degree.z)
		))
		basis = basis * extra_rot

		# Create mesh instance
		var new_deco_mesh: Node3D = decomesh.duplicate()
		new_deco_mesh.name = side + "_instance_" + str(int(current_length_covered / (object_length * decomesh.scale.x)))

		# Set basis first (orientation)
		new_deco_mesh.basis = basis

		# Apply position and manual offset in the local frame of the basis
		new_deco_mesh.position = position_on_offset_curve + basis * manual_offset_object

		decoration_node_wrapper.add_child(new_deco_mesh)
		new_deco_mesh.set_owner(segment.get_tree().get_edited_scene_root())

		current_length_covered += object_length * decomesh.scale.x + spacing_along_curve
		number_objects_placed += 1
