@tool
extends RoadDecoration
class_name RoadCurb

## Define profile (geometry) of curb. Left is inside of track. Only points will be used - not tangents - when drawing curb, linearity is assumed
@export var profile: Curve
@export var primary_color: Color = Color("#FF2400")
@export var use_stripes: bool = false
## Secondary color for stripes (if enabled)
@export var secondary_color: Color = Color("#F9F6EE")
@export_range(0.1, 10.0, 0.1, "or_greater") var stripe_length: float = 3.0

func _init() -> void:
	desc = "curbs"
	# basic linear curb shape
	profile = Curve.new()
	profile.bake_resolution = 5
	profile.max_domain = 2.0
	profile.max_value = 0.5
	profile.add_point(Vector2(0, 0),0,0,1,1)
	profile.add_point(Vector2(1.7, 0.15),0,0,1,1)
	profile.add_point(Vector2(2.0, 0),0,0,1,1)


func setup(segment: RoadSegment, decoration_node_wrapper: Node3D) -> void:
	print("Setup curb for ", segment.start_point.name, " to ", segment.end_point.name)

	# Create new curbs based on the selected side(s)
	if side == RoadCurb.Side.BOTH or side == RoadCurb.Side.REVERSE:
		var edge: Path3D = segment.get_parent().get_node(segment.EDGE_R_NAME)
		_create_curb_on_edge(decoration_node_wrapper, segment, edge, "curb_R")
	
	if side == RoadCurb.Side.BOTH or side == RoadCurb.Side.FORWARD:
		var edge: Path3D = segment.get_parent().get_node(segment.EDGE_F_NAME)
		_create_curb_on_edge(decoration_node_wrapper, segment, edge, "curb_F")


func _create_curb_on_edge(decoration_node_wrapper: Node3D, segment: RoadSegment, edge: Path3D, curb_name: String):
	"""Create a curb CSGPolygon3D on the specified edge curve."""
	if not edge or not is_instance_valid(edge):
		push_error("Invalid edge provided to _create_curb_on_edge")
		return
	
	# we create a new path3d and curve3d for every curb to allow for offsets and independency in case multiple curbs are created
	var curve_with_offsets: Curve3D = _get_curve_with_applied_offsets(edge, offset_start, offset_end)
	var curb_path: Path3D = Path3D.new()
	curb_path.name = edge.name + "_curb_path"
	curb_path.curve = curve_with_offsets
	decoration_node_wrapper.add_child(curb_path)
	curb_path.set_owner(segment.get_tree().get_edited_scene_root())
	# go to global coordinates and then into edge local coordinates
	curb_path.transform = curb_path.transform * curb_path.global_transform.inverse() * edge.global_transform

	# create curb
	var curb = CSGPolygon3D.new()
	curb.name = curb_name
	curb.mode = CSGPolygon3D.MODE_PATH
	curb.path_node = curb_path.get_path()
	curb.path_local = true

	var material = StandardMaterial3D.new()

	# Check if we should use striped pattern
	if use_stripes:
		# Create a simple 2-pixel wide texture with alternating colors
		var stripe_texture = _create_stripe_texture(primary_color, secondary_color)
		material.albedo_texture = stripe_texture

		# Set UV repeat to control stripe length
		# The stripe_length parameter defines how many meters per color stripe
		# X-axis controls stripes along the path direction
		material.uv1_scale = Vector3(1.0 / stripe_length, 1.0, 1.0)
		material.uv1_triplanar = false
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	else:
		# Use solid color
		material.albedo_color = primary_color

	curb.material = material

	# Set a simple curb polygon profile
	var polygon: PackedVector2Array

	var points_curb_profile = profile.get_point_count()

	if curb_name == "curb_R":
		for i in range(points_curb_profile):
			var point: Vector2 = profile.get_point_position(i)
			polygon.append(Vector2(point.x + offset_lateral, point.y))
	else: # curb_F
		for i in range(points_curb_profile):
			var point: Vector2 = profile.get_point_position(i)
			polygon.append(Vector2(-point.x - offset_lateral, point.y))

	curb.polygon = polygon

	curb_path.add_child(curb)
	curb.set_owner(segment.get_tree().get_edited_scene_root())


func _create_stripe_texture(color1: Color, color2: Color) -> ImageTexture:
	"""Create a simple 2-pixel horizontal texture for striped pattern along path."""
	var image = Image.create(2, 2, false, Image.FORMAT_RGBA8)

	# Set first column to color1
	image.set_pixel(0, 0, color1)
	image.set_pixel(0, 1, color1)

	# Set second column to color2
	image.set_pixel(1, 0, color2)
	image.set_pixel(1, 1, color2)

	var texture = ImageTexture.create_from_image(image)
	return texture
