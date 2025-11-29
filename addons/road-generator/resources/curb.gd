@tool
extends RoadDecoration
class_name RoadCurb

enum Side {
	FORWARD,
	REVERSE,
	BOTH
}

# @export var offset_start: float = 0.0
# @export var offset_end: float = -0.0
@export var side: RoadCurb.Side = RoadCurb.Side.REVERSE
@export var primary_color: Color = Color.RED
@export var use_stripes: bool = false
@export var secondary_color: Color = Color.WHITE
@export_range(0.1, 10.0, 0.1, "or_greater") var stripe_length: float = 3.0

func setup(segment: RoadSegment) -> void:
	print("Setup curb for ", segment.start_point.name, " to ", segment.end_point.name)

	# first clear curbs on this segment
	_remove_all_curbs(segment)

	# Create new curbs based on the selected side(s)
	if side == RoadCurb.Side.BOTH or side == RoadCurb.Side.REVERSE:
		var edge: Path3D = segment.get_parent().get_node(segment.EDGE_R_NAME)
		_create_curb_on_edge(segment, edge, "curb_R")
	
	if side == RoadCurb.Side.BOTH or side == RoadCurb.Side.FORWARD:
		var edge: Path3D = segment.get_parent().get_node(segment.EDGE_F_NAME)
		_create_curb_on_edge(segment, edge, "curb_F")


func _remove_all_curbs(segment: RoadSegment) -> void:
	# Remove all children that are CSGPolygon3D curb nodes
	for child in segment.get_children():
		if child is CSGPolygon3D and child.name.begins_with("curb_"):
			segment.remove_child(child)
			child.queue_free()


func _create_curb_on_edge(segment: RoadSegment, edge: Path3D, curb_name: String):
	"""Create a curb CSGPolygon3D on the specified edge curve."""
	if not edge or not is_instance_valid(edge):
		push_error("Invalid edge provided to _create_curb_on_edge")
		return

	var curb = CSGPolygon3D.new()
	curb.name = curb_name
	curb.mode = CSGPolygon3D.MODE_PATH
	curb.path_node = edge.get_path()
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
	if curb_name == "curb_R":
		polygon = PackedVector2Array([
			Vector2(0, 0),
			Vector2(2, 0.15),
			Vector2(2, 0)
		])
	else: # curb_F
		polygon = PackedVector2Array([
			Vector2(0, 0),
			Vector2(-2, 0.15),
			Vector2(-2, 0)
		])
	curb.polygon = polygon

	segment.add_child(curb)
	curb.set_owner(segment.get_tree().get_edited_scene_root())
	# go to global coordinates and then into edge local coordinates
	curb.transform = curb.transform * curb.global_transform.inverse() * edge.global_transform



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


