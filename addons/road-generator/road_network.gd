## Manager used to generate the actual road segments when needed.
tool
extends Node

export(bool) var refresh setget _ui_refresh_set, _ui_refresh_get
export(Material) var material_resource:Material

onready var points = $points
onready var segments = $segments

# Mapping maintained of individual segments and their corresponding resources.
var segid_map = {}




func _ready():
	rebuild_segments(true)


func _ui_refresh_set(value):
	refresh = value
	rebuild_segments(true)


func _ui_refresh_get():
	return refresh


func rebuild_segments(clear_existing=false):
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
