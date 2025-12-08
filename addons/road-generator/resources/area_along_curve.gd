@tool
extends RoadDecoration
class_name AreaAlongCurve

## Shader for striped areas (lives in its own .gdshader file)
const STRIPE_SHADER := preload("res://addons/road-generator/shaders/area_stripes.gdshader")

@export_group("Area Properties")
## Define profile (geometry) of side area. Left is inside of track. Only points will be used - not tangents - when drawing curb, linearity is assumed.
## Profile needs at least 2 points.
@export var profile: Curve
## Define width of side area along the road segment.
## So at domain=0 a value of 2 would mean that the area extends 2 meters from the road edge (assuming max_domain of profile is 1) 
## at the start of the road segment. At domain=1 it would be at the end of the road segment and you can vary the width along it.
@export var width: Curve
@export var primary_color: Color = Color("#006400")

## If true, use a striped shader instead of a solid color.
@export var use_stripes: bool = false
## Secondary color for stripes (if enabled).
@export var secondary_color: Color = Color("#F9F6EE")
## Width of each stripe in meters (if stripes are enabled).
@export_range(0.1, 10.0, 0.1, "or_greater") var stripe_width: float = 3.0
## Rotation of stripes in degrees (0 means they go parallel to road direction).
@export_range(0, 90, 1) var stripe_rotation_degree: float = 0.0


func _init() -> void:
	description = "side_area"
	# Basic horizontal area shape.
	profile = Curve.new()
	profile.bake_resolution = 5
	profile.max_domain = 1
	profile.max_value = 0.5
	profile.add_point(Vector2(0, 0.05), 0, 0, 1, 1)
	profile.add_point(Vector2(1, 0.1), 0, 0, 1, 1)

	# Default width of side area along road segment.
	width = Curve.new()
	width.bake_resolution = 10
	width.max_domain = 1
	width.max_value = 30
	width.add_point(Vector2(0, 1), 0, 0, 1, 1)
	width.add_point(Vector2(1, 1), 0, 0, 1, 1)


func setup(segment: RoadSegment, decoration_node_wrapper: Node3D) -> void:
	# Create new areas based on the selected side(s).
	if side == RoadCurb.Side.BOTH or side == RoadCurb.Side.REVERSE:
		var edge: Path3D = segment.get_parent().get_node(segment.EDGE_R_NAME)
		_create_area_next_to_edge(decoration_node_wrapper, segment, edge, "area_R")
	
	if side == RoadCurb.Side.BOTH or side == RoadCurb.Side.FORWARD:
		var edge: Path3D = segment.get_parent().get_node(segment.EDGE_F_NAME)
		_create_area_next_to_edge(decoration_node_wrapper, segment, edge, "area_F")


func _create_area_next_to_edge(
	decoration_node_wrapper: Node3D,
	segment: RoadSegment,
	edge: Path3D,
	area_name: String
) -> void:
	"""Create an area mesh next to the specified edge with width varying along the path."""
	if not edge or not is_instance_valid(edge):
		push_error("Invalid edge provided to _create_area_next_to_edge")
		return

	# Get the inner edge curve with start/end & lateral offsets applied.
	var curve_with_offsets: Curve3D = _get_curve_with_offsets(segment, edge)
	if curve_with_offsets == null:
		push_error("curve_with_offsets is null in _create_area_next_to_edge")
		return

	var inner_length: float = curve_with_offsets.get_baked_length()
	if inner_length <= 0.0:
		push_error("curve_with_offsets has zero length.")
		return

	# Build geometry (inner/outer points + stripe coordinates) in a separate helper.
	var geom = _build_area_geometry(segment, edge, area_name, curve_with_offsets, inner_length)
	if geom == null:
		push_error("Failed to build area geometry.")
		return

	var inner_points: PackedVector3Array = geom.inner_points
	var outer_points: PackedVector3Array = geom.outer_points
	var s_coords: PackedFloat32Array = geom.s_coords
	var widths: PackedFloat32Array = geom.widths

	if inner_points.size() < 2 or outer_points.size() < 2:
		push_error("Not enough points to build area mesh.")
		return

	# Build mesh from geometry (triangle strip, normals, UV/UV2).
	var mesh: ArrayMesh = _build_area_mesh(inner_points, outer_points, s_coords, widths, area_name)
	if mesh == null:
		push_error("Failed to create side area mesh.")
		return

	# Visual material: stripes or solid color.
	var material: Material = _create_area_material()

	# Create MeshInstance + StaticBody + CollisionShape in one helper.
	_create_area_nodes_with_collision(
		decoration_node_wrapper,
		segment,
		mesh,
		material,
		area_name
	)


func _build_area_geometry(
	segment: RoadSegment,
	edge: Path3D,
	area_name: String,
	curve_with_offsets: Curve3D,
	inner_length: float
):
	## Compute the sample points for the side area:
	## - inner_points: points along the edge with vertical profile applied
	## - outer_points: points offset outwards by width curve + profile
	## - s_coords: distance along curve in meters (for UV2.x in shader)
	## - widths: width in meters at each sample (for UV2.y in shader)

	# Trim parameters on the original edge curve (for orientation).
	var original_curve: Curve3D = edge.curve
	var trim := _get_trim_parameters(original_curve)
	var start_distance: float = trim.start_distance
	var end_distance: float = trim.end_distance
	var trimmed_length: float = trim.trimmed_length
	if trimmed_length <= 0.0:
		push_error("Trimmed length <= 0 in _build_area_geometry")
		return null

	# Choose sampling resolution along the curve.
	var num_samples: int = int(inner_length) + 2
	if num_samples < 4:
		num_samples = 4

	var inner_points: PackedVector3Array = PackedVector3Array()
	var outer_points: PackedVector3Array = PackedVector3Array()
	var s_coords: PackedFloat32Array = PackedFloat32Array()
	var widths: PackedFloat32Array = PackedFloat32Array()

	# Simple vertical profile: use first and last profile samples as heights.
	var inner_height: float = profile.sample(0.0)   # y-value at x = 0
	var outer_height: float = profile.sample(1.0)   # y-value at x = 1

	# Right side (area_R) should go outwards, not onto the track.
	var side_sign: float = 1.0
	if area_name == "area_R":
		side_sign = -1.0

	for i in range(num_samples):
		var t: float = float(i) / float(num_samples - 1)  # 0..1 along segment

		# Distance on inner (offset) curve for inner position.
		var dist_on_inner: float = t * inner_length
		var inner_pos: Vector3 = curve_with_offsets.sample_baked(dist_on_inner)

		# Distance on original edge for frame orientation.
		var dist_on_original: float = lerp(start_distance, end_distance, t)
		var frame := _compute_bank_frame(segment, edge, dist_on_original)
		var outward_dir: Vector3 = frame.outward_dir * side_sign
		var up_dir: Vector3 = frame.up_dir

		# Width in meters at this position.
		# NOTE: as in your original code we sample width at (1 - t).
		var w: float = max(width.sample(1.0 - t), 0.0)

		# Apply vertical profile: inner and outer have slightly different heights.
		var final_inner_pos: Vector3 = inner_pos + up_dir * inner_height
		var final_outer_pos: Vector3 = inner_pos + outward_dir * w + up_dir * outer_height

		inner_points.append(final_inner_pos)
		outer_points.append(final_outer_pos)
		s_coords.append(dist_on_inner)  # real meters along the curve
		widths.append(w)                # local width in meters

	return {
		"inner_points": inner_points,
		"outer_points": outer_points,
		"s_coords": s_coords,
		"widths": widths,
	}


func _build_area_mesh(
	inner_points: PackedVector3Array,
	outer_points: PackedVector3Array,
	s_coords: PackedFloat32Array,
	widths: PackedFloat32Array,
	area_name: String
):
	## Build the actual ArrayMesh from the sampled geometry.
	## This keeps your triangle ordering and per-side normal logic.

	if inner_points.size() < 2 or outer_points.size() < 2:
		return null

	var num_samples: int = inner_points.size()

	# Build triangle strip between inner and outer points.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var is_right_side := area_name == "area_R"

	for i in range(num_samples - 1):
		var i0: Vector3 = inner_points[i]
		var i1: Vector3 = inner_points[i + 1]
		var o0: Vector3 = outer_points[i]
		var o1: Vector3 = outer_points[i + 1]

		var s0: float = s_coords[i]
		var s1: float = s_coords[i + 1]
		var w0: float = widths[i]
		var w1: float = widths[i + 1]

		# Base normal from the "right side" variant (i0, i1, o1).
		var base_normal: Vector3 = (i1 - i0).cross(o1 - i0)
		if base_normal == Vector3.ZERO:
			base_normal = Vector3.UP
		base_normal = base_normal.normalized()

		# Right side uses this base normal.
		# Left side uses the inverted normal.
		var normal: Vector3 = base_normal if is_right_side else -base_normal

		# UV along curve (0..1) – optional, if you ever want to use a texture.
		var u0: float = float(i) / float(num_samples - 1)
		var u1: float = float(i + 1) / float(num_samples - 1)

		if not is_right_side:
			# Left side: triangle ordering variant A.
			# Triangle 1: i0, i1, o1
			st.set_normal(normal)
			st.set_uv(Vector2(u0, 0.0))
			st.set_uv2(Vector2(s0, 0.0))           # inner: width 0
			st.add_vertex(i0)

			st.set_normal(normal)
			st.set_uv(Vector2(u1, 0.0))
			st.set_uv2(Vector2(s1, 0.0))
			st.add_vertex(i1)

			st.set_normal(normal)
			st.set_uv(Vector2(u1, 1.0))
			st.set_uv2(Vector2(s1, w1))           # outer at s1, width w1
			st.add_vertex(o1)

			# Triangle 2: i0, o1, o0
			st.set_normal(normal)
			st.set_uv(Vector2(u0, 0.0))
			st.set_uv2(Vector2(s0, 0.0))
			st.add_vertex(i0)

			st.set_normal(normal)
			st.set_uv(Vector2(u1, 1.0))
			st.set_uv2(Vector2(s1, w1))
			st.add_vertex(o1)

			st.set_normal(normal)
			st.set_uv(Vector2(u0, 1.0))
			st.set_uv2(Vector2(s0, w0))           # outer at s0, width w0
			st.add_vertex(o0)
		else:
			# Right side: triangle ordering variant B (different vertex order).
			# Triangle 1: i0, o1, i1
			st.set_normal(normal)
			st.set_uv(Vector2(u0, 0.0))
			st.set_uv2(Vector2(s0, 0.0))
			st.add_vertex(i0)

			st.set_normal(normal)
			st.set_uv(Vector2(u1, 1.0))
			st.set_uv2(Vector2(s1, w1))
			st.add_vertex(o1)

			st.set_normal(normal)
			st.set_uv(Vector2(u1, 0.0))
			st.set_uv2(Vector2(s1, 0.0))
			st.add_vertex(i1)

			# Triangle 2: i0, o0, o1
			st.set_normal(normal)
			st.set_uv(Vector2(u0, 0.0))
			st.set_uv2(Vector2(s0, 0.0))
			st.add_vertex(i0)

			st.set_normal(normal)
			st.set_uv(Vector2(u0, 1.0))
			st.set_uv2(Vector2(s0, w0))
			st.add_vertex(o0)

			st.set_normal(normal)
			st.set_uv(Vector2(u1, 1.0))
			st.set_uv2(Vector2(s1, w1))
			st.add_vertex(o1)

	var mesh: ArrayMesh = st.commit()
	return mesh


func _create_area_material() -> Material:
	## Create either striped ShaderMaterial (using external .gdshader) or solid StandardMaterial3D.
	if use_stripes:
		var shader_mat := ShaderMaterial.new()
		shader_mat.shader = STRIPE_SHADER
		shader_mat.set_shader_parameter("primary_color", primary_color)
		shader_mat.set_shader_parameter("secondary_color", secondary_color)
		shader_mat.set_shader_parameter("stripe_width_m", stripe_width)
		shader_mat.set_shader_parameter("stripe_angle_deg", stripe_rotation_degree)
		return shader_mat
	else:
		var std_mat := StandardMaterial3D.new()
		std_mat.albedo_color = primary_color
		std_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		return std_mat


func _create_area_nodes_with_collision(
	decoration_node_wrapper: Node3D,
	segment: RoadSegment,
	mesh: ArrayMesh,
	material: Material,
	area_name: String
) -> void:
	## Create the MeshInstance3D for rendering and a StaticBody3D with a ConcavePolygonShape3D for collisions.

	# Visual mesh instance.
	var area_mesh_instance := MeshInstance3D.new()
	area_mesh_instance.name = area_name
	area_mesh_instance.mesh = mesh
	area_mesh_instance.material_override = material

	decoration_node_wrapper.add_child(area_mesh_instance)
	area_mesh_instance.set_owner(segment.get_tree().get_edited_scene_root())

	# Collision setup.
	var static_body := StaticBody3D.new()
	static_body.name = area_name + "_static_body"

	# Make it a child of the visual mesh, as requested.
	area_mesh_instance.add_child(static_body)
	static_body.set_owner(segment.get_tree().get_edited_scene_root())

	var collision_shape := CollisionShape3D.new()
	collision_shape.name = area_name + "_collision"

	# Build a concave collision shape from the mesh geometry.
	var shape := ConcavePolygonShape3D.new()

	if mesh.get_surface_count() == 0:
		push_error("Area mesh has no surfaces, cannot build collision.")
	else:
		var arrays: Array = mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]

		if verts.size() == 0:
			push_error("Area mesh has no vertices, cannot build collision.")
		else:
			# Verts are already in triangle order from SurfaceTool.
			shape.data = verts
			collision_shape.shape = shape

			static_body.add_child(collision_shape)
			collision_shape.set_owner(segment.get_tree().get_edited_scene_root())
