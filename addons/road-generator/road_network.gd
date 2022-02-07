## Manager used to generate the actual road segments when needed.
extends Node


onready var points = $points
onready var segments = $segments

# Mapping maintained of individual segments and their corresponding resources.
var segid_map = {}


func _ready():
	rebuild_segments()


func rebuild_segments():
	# TODO: think of using groups instead, to have a single maanger
	# that is not dependnet on this.
	var seg_ids = []
	for ch in segments.get_children():
		seg_ids.append(ch.get_id())
	
	# Goal is to loop through all RoadPoints, and check if an existing segment
	# is there, or needs to be added.
	for obj in points.get_children():
		if not obj.visible:
			continue # Assume local chunk has dealt with the geo visibility.
		if not obj is RoadPoint:
			push_warning("Invalid child object under points of road network")
			continue
		var pt:RoadPoint = obj
		if not pt.prior_seg or not pt.next_seg:
			print_debug("Not connected to anything yet")
			continue
		
		# TODO: The below will have issues if a "next" goes into "next",
		# but doing this for simplicity now.
		if pt.prior_seg:
			process_seg(pt.prior_seg, obj)
			var sid = "%s-%s" % [pt.prior_seg.get_instance_id(), obj.get_instance_id()]
			if not sid in seg_ids:
				print("Adding new segment")
				
		if pt.next_seg:
			process_seg(obj, pt.next_seg)


func process_seg(pt1, pt2):
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
	segments.add_child(new_seg)
	new_seg.call_deferred("check_refresh")
