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
@export var rotation_object_degree: Vector3 = Vector3(0, 90, 0)
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

	print("Setup InstanceAlongCurve for ", segment.start_point.name, " to ", segment.end_point.name)
	print("Source scene: ", mesh_source_scene)

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

	var curve_length: float = curve_with_offsets.get_baked_length()

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
		# position to place object
		var position: Vector3 = curve_with_offsets.sample_baked(current_length_covered)
		
		# we take the rotation from the center of the object
		var transform: Transform3D = curve_with_offsets.sample_baked_with_rotation(current_length_covered+object_length*decomesh.scale.x*0.5)
		var rotation: Vector3 = transform.basis.get_euler()

		# get new mesh object
		var new_deco_mesh = decomesh.duplicate()
		new_deco_mesh.name = side + "_instance_" + str(int(current_length_covered / object_length*decomesh.scale.x))
		
		# add user defined position offset to position on curve
		new_deco_mesh.position = position + transform.basis * manual_offset_object
		
		# apply offset_lateral relative to curve sideways direction
		# var lateral_dir: Vector3 = transform.basis.x.normalized()
		# var lateral_sign = -1.0 if side == "R" else 1.0
		# var offset_lateral = offset_profile.sample(current_length_covered/curve_length)
		# new_deco_mesh.position += lateral_dir * offset_lateral * lateral_sign


		# set mesh rotation to rotation on curve 
		new_deco_mesh.rotation = rotation

		# add user defined rotation
		new_deco_mesh.rotation += Vector3(
			deg_to_rad(rotation_object_degree.x),
			deg_to_rad(rotation_object_degree.y),
			deg_to_rad(rotation_object_degree.z)
		)

		decoration_node_wrapper.add_child(new_deco_mesh)
		new_deco_mesh.set_owner(segment.get_tree().get_edited_scene_root())

		current_length_covered += object_length*decomesh.scale.x + spacing_along_curve
		number_objects_placed += 1
