## Manager used to generate the actual road segments when needed.
tool
extends Node

#const RoadPoint = preload("res://addons/road-generator/road_point.gd")

export(bool) var auto_refresh = true setget _ui_refresh_set, _ui_refresh_get
export(Material) var material_resource:Material

export(NodePath) var debug_prior
export(NodePath) var debug_next

onready var points = $points
onready var segments = $segments

# Mapping maintained of individual segments and their corresponding resources.
var segid_map = {}


func _ready():
	rebuild_segments(true)


func _ui_refresh_set(value):
	auto_refresh = value
	if auto_refresh:
		rebuild_segments(true)


func _ui_refresh_get():
	return auto_refresh


func rebuild_segments(clear_existing=false):
	if not segments:
		return # Could be before ready called.
	if clear_existing:
		segid_map = {}
		for ch in segments.get_children():
			ch.queue_free()
	else:
		# TODO: think of using groups instead, to have a single maanger
		# that is not dependnet on this.
		pass
	
	# Goal is to loop through all RoadPoints, and check if an existing segment
	# is there, or needs to be added.
	for obj in points.get_children():
		if not obj.visible:
			continue # Assume local chunk has dealt with the geo visibility.
		if not obj is RoadPoint:
			push_warning("Invalid child object under points of road network")
			continue
		var pt:RoadPoint = obj
		if not pt.prior_pt or not pt.next_pt:
			print_debug("Not connected to anything yet")
			continue
		
		if pt.prior_pt:
			process_seg(pt.prior_pt, pt)
		if pt.next_pt:
			process_seg(pt, pt.next_pt)


func process_seg(pt1, pt2):
	# TODO: The id setup below will have issues if a "next" goes into "prior", ie rev dir
	# but doing this for simplicity now.
	var sid = "%s-%s" % [pt1.get_instance_id(), pt2.get_instance_id()]
	if sid in segid_map:
		print("Segment existed already, running refresh")
		segid_map[sid].check_refresh()
		return
	print("Adding new segment and running refresh")
	var new_seg = RoadSegment.new()
	new_seg.start_point = pt1
	new_seg.end_point = pt2
	segid_map[sid] = new_seg
	new_seg.material = material_resource
	segments.add_child(new_seg)
	new_seg.call_deferred("check_refresh")


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
	
	if prior_path and prior_seg and prior_seg.path and prior_seg.path.curve:
		prior_path.visible = true
		prior_path.global_transform.origin = prior_seg.global_transform.origin
		prior_path.curve = prior_seg.path.curve
	else:
		prior_path.visible = false
	if next_path and next_seg and next_seg.path and next_seg.path.curve:
		next_path.visible = true
		next_path.global_transform.origin = next_seg.global_transform.origin
		next_path.curve = next_seg.path.curve
	else:
		next_path.visible = false
		
