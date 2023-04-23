## Manager used to generate the actual road segments when needed.
tool
class_name RoadNetwork, "road_segment.png"
extends Spatial

#const RoadPoint = preload("res://addons/road-generator/road_point.gd")
const RoadMaterial = preload("res://addons/road-generator/road_texture.material")

export(bool) var auto_refresh = true setget _ui_refresh_set, _ui_refresh_get
export(Material) var material_resource:Material setget _set_material

export(float) var density:float = 0.5  setget _set_density # Mesh density of generated segments.
export(bool) var use_lowpoly_preview:bool = false  # Whether to reduce geo mid transform.

# UI-selectable points and segments
export(NodePath) var points setget _set_points # Where RoadPoints should be placed.
export(NodePath) var segments setget _set_segments # Where generated segment meshes will go.


export(NodePath) var debug_prior
export(NodePath) var debug_next

# Mapping maintained of individual segments and their corresponding resources.
var segid_map = {}

export(bool) var generate_ai_lanes := false setget _set_gen_ai_lanes
export(bool) var debug := false


func _ready():
	# setup_road_network won't work in _ready unless call_deferred is used
	call_deferred("setup_road_network")
	call_deferred("rebuild_segments", true)


func _ui_refresh_set(value):
	auto_refresh = value
	if auto_refresh:
		call_deferred("rebuild_segments", true)


func _ui_refresh_get():
	return auto_refresh


func _set_gen_ai_lanes(value):
	generate_ai_lanes = value
	if auto_refresh:
		call_deferred("rebuild_segments", true)


func _set_density(value):
	density = value
	if auto_refresh:
		call_deferred("rebuild_segments", true)


func _set_material(value):
	material_resource = value
	if auto_refresh:
		call_deferred("rebuild_segments", true)


func _set_points(value):
	points = value
	if auto_refresh:
		call_deferred("rebuild_segments", true)


func _set_segments(value):
	segments = value
	if auto_refresh:
		call_deferred("rebuild_segments", true)


func rebuild_segments(clear_existing=false):
	# print("Rebuilding segments")
	if not get_node(segments) or not is_instance_valid(get_node(segments)):
		push_error("Segments node path not found")
		return # Could be before ready called.
	if clear_existing:
		segid_map = {}
		for ch in get_node(segments).get_children():
			ch.queue_free()
	else:
		# TODO: think of using groups instead, to have a single manager
		# that is not dependnet on this parenting structure.
		pass

	# Goal is to loop through all RoadPoints, and check if an existing segment
	# is there, or needs to be added.
	var rebuilt = 0
	for obj in get_node(points).get_children():
		if not obj.visible:
			continue # Assume local chunk has dealt with the geo visibility.
		if not obj is RoadPoint:
			push_warning("Invalid child object under points of road network")
			continue
		var pt:RoadPoint = obj

		var prior_pt
		var next_pt
		if pt.prior_pt_init:
			prior_pt = pt.get_node(pt.prior_pt_init)
		if pt.next_pt_init:
			next_pt = pt.get_node(pt.next_pt_init)

		if not prior_pt and not next_pt:
			push_warning("Road point %s not connected to anything yet" % pt.name)
			continue

		if prior_pt and prior_pt.visible:
			rebuilt += process_seg(prior_pt, pt)
		if next_pt and next_pt.visible:
			rebuilt += process_seg(pt, next_pt)
	if debug:
		print_debug("Road segs rebuilt: ", rebuilt)


# Create a new road segment based on input prior and next RoadPoints.
func process_seg(pt1:RoadPoint, pt2:RoadPoint, low_poly:bool=false) -> int:
	# TODO: The id setup below will have issues if a "next" goes into "prior", ie rev dir
	# but doing this for simplicity now.

	var sid = "%s-%s" % [pt1.get_instance_id(), pt2.get_instance_id()]
	if sid in segid_map:
		if not is_instance_valid(segid_map[sid]):
			push_error("Instance was not valid on sid: %s" % sid)
		segid_map[sid].check_rebuild()
		return 0
	else:
		var new_seg = RoadSegment.new(self)
		get_node(segments).add_child(new_seg)
		new_seg.low_poly = low_poly
		new_seg.start_point = pt1
		new_seg.end_point = pt2
		segid_map[sid] = new_seg
		new_seg.material = material_resource
		new_seg.check_rebuild()

		if generate_ai_lanes:
			print("Doing lane segments")
			new_seg.generate_lane_segments(debug)

		return 1


# Update the position and contents of the curves for the given point object.
func update_debug_paths(point:RoadPoint):
	var prior_path
	var next_path
	if debug_prior:
		prior_path = get_node(debug_prior)
	if debug_next:
		next_path = get_node(debug_next)

	var prior_seg = point.prior_seg
	var next_seg = point.next_seg

	if prior_path and prior_seg and prior_seg.curve:
		prior_path.visible = true
		prior_path.global_transform.origin = prior_seg.global_transform.origin
		prior_path.curve = prior_seg.curve
	else:
		prior_path.visible = false
	if next_path and next_seg and next_seg.curve:
		next_path.visible = true
		next_path.global_transform.origin = next_seg.global_transform.origin
		next_path.curve = next_seg.curve
	else:
		next_path.visible = false


# Triggered by adjusting RoadPoint transform in editor via signal connection.
func on_point_update(point:RoadPoint, low_poly:bool):
	if not auto_refresh:
		return
	elif not is_instance_valid(point):
		return
	var use_lowpoly = low_poly and use_lowpoly_preview
	if is_instance_valid(point.prior_seg):
		point.prior_seg.low_poly = use_lowpoly
		point.prior_seg.is_dirty = true
		point.prior_seg.call_deferred("check_rebuild")
		if not use_lowpoly:
			point.prior_seg.generate_lane_segments(debug)
		else:
			point.prior_seg.clear_lane_segments()
	elif point.prior_pt_init and point.get_node(point.prior_pt_init).visible:
		var prior = point.get_node(point.prior_pt_init)
		process_seg(prior, point, use_lowpoly)
	if is_instance_valid(point.next_seg):
		point.next_seg.low_poly = use_lowpoly
		point.next_seg.is_dirty = true
		point.next_seg.call_deferred("check_rebuild")
		if not use_lowpoly:
			point.next_seg.generate_lane_segments(debug)
		else:
			if point.prior_seg:
				point.prior_seg.clear_lane_segments()
	elif point.next_pt_init and point.get_node(point.next_pt_init).visible:
		var next = point.get_node(point.next_pt_init)
		process_seg(point, next, use_lowpoly)


# Callback from a modification of a RoadSegment object.
func segment_rebuild(road_segment:RoadSegment):
	road_segment.check_rebuild()


# Cleanup the road segments specifically, in case they aren't children.
func _exit_tree():
	# TODO: Verify we don't get orphans below.
	# However, at the time of this early exit, doing this prevented roads
	# from being drawn on scene load due to errors unloading against
	# freed instances.
	segid_map = {}
	return

	#segid_map = {}
	#if not segments or not is_instance_valid(get_node(segments)):
	#	return
	#for seg in get_node(segments).get_children():
	#	seg.queue_free()


## Adds points, segments, and material if they're unassigned
func setup_road_network():
	use_lowpoly_preview = true

	# In order for points and segments to show up in the Scene dock, they must
	# be assigned an "owner". Use the RoadNetwork's owner. But, the RoadNetwork
	# won't have an owner if it is the scene root. In that case, make the
	# RoadNetwork the owner.
	var own
	if owner:
		own = owner
	else:
		own = self

	if not points or not is_instance_valid(get_node(points)):
		var new_points = Spatial.new()
		new_points.name = "points"
		add_child(new_points)
		new_points.set_owner(own)
		points = get_path_to(new_points)
		print("Added points to ", name)

	if not segments or not is_instance_valid(get_node(segments)):
		var new_segments = Spatial.new()
		new_segments.name = "segments"
		add_child(new_segments)
		new_segments.set_owner(own)
		segments = get_path_to(new_segments)
		print("Added segments to ", name)

	if not material_resource:
		material_resource = RoadMaterial
		print("Added material to ", name)



