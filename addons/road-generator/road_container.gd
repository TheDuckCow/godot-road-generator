## Manager used to generate the actual road segments when needed.
tool
class_name RoadContainer, "road_segment.png"
extends Spatial

## Emitted when a road segment has been (re)generated, returning the list
## of updated segments of type Array. Will also trigger on segments deleted,
## which will contain a list of nothing.
signal on_road_updated (updated_segments)

const RoadMaterial = preload("res://addons/road-generator/road_texture.material")
const RoadSegment = preload("res://addons/road-generator/road_segment.gd")

export(bool) var auto_refresh = true setget _ui_refresh_set
export(Material) var material_resource:Material setget _set_material

export(float) var density:float = 1.0  setget _set_density # Mesh density of generated segments.
export(bool) var use_lowpoly_preview:bool = false  # Whether to reduce geo mid transform.


# Mapping maintained of individual segments and their corresponding resources.
var segid_map = {}

export(bool) var generate_ai_lanes := false setget _set_gen_ai_lanes
export(String) var ai_lane_group := "road_lanes" setget _set_ai_lane_group

export(bool) var debug := false
export(bool) var draw_lanes_editor := false setget _set_draw_lanes_editor, _get_draw_lanes_editor
export(bool) var draw_lanes_game := false setget _set_draw_lanes_game, _get_draw_lanes_game

var _draw_lanes_editor:bool = false
var _draw_lanes_game:bool = false

# Non-exposed developer control, which allows showing all nodes (including generated) in the scene
# tree. Typcially we don't want to do this, so that users don't accidentally start adding nodes
# or making changes that get immediately removed as soon as a road is regenerated.
var debug_scene_visible:bool = false

# Flag used to defer calls to setup_road_network via _dirty_rebuild_deferred,
# important during scene startup whereby class properties are called in
# succession during scene init and otherwise would lead to duplicate calls.
var _dirty:bool = false


func _ready():
	# setup_road_network won't work in _ready unless call_deferred is used
	call_deferred("setup_road_network")

	# Per below, this is technicaly redundant/not really doing anything.
	_dirty = true
	call_deferred("_dirty_rebuild_deferred")

	# If we call this now, it will end up generating roads twice.
	#rebuild_segments(true)
	# This is due, evidently, to godot loading the scene in such a way where
	# it actually sets the value to each property and thus also trigger its
	# setget, and result in calling _dirty_rebuild_deferred. Class properties
	# are assigned, thus triggering functions like _set_density, before the
	# _ready function is ever called. Thus by the time _ready is happening,
	# the _dirty flag is already set.

func _get_configuration_warning() -> String:
	var has_rp_child = false
	for ch in get_children():
		if ch is RoadPoint:
			has_rp_child = true
			break
	if not has_rp_child:
		return "Add RoadPoint nodes as children to form a road, or use the create menu in the 3D view header"
	return ""


func _ui_refresh_set(value):
	if value and not _dirty:
		_dirty = true
		call_deferred("_dirty_rebuild_deferred")
	auto_refresh = value


func _set_gen_ai_lanes(value: bool):
	if auto_refresh and not _dirty:
		_dirty = true
		call_deferred("_dirty_rebuild_deferred")
	generate_ai_lanes = value


func _set_ai_lane_group(value: String):
	if auto_refresh and not _dirty:
		_dirty = true
		call_deferred("_dirty_rebuild_deferred")
	ai_lane_group = value


func _set_density(value):
	if auto_refresh and not _dirty:
		_dirty = true
		call_deferred("_dirty_rebuild_deferred")
	density = value


func _set_material(value):
	if auto_refresh and not _dirty:
		_dirty = true
		call_deferred("_dirty_rebuild_deferred")
	material_resource = value


func _dirty_rebuild_deferred():
	if _dirty:
		_dirty = false
		call_deferred("rebuild_segments", true)


func _set_draw_lanes_editor(value: bool):
	_draw_lanes_editor = value
	call_deferred("rebuild_segments", true)


func _get_draw_lanes_editor() -> bool:
	return _draw_lanes_editor


func _set_draw_lanes_game(value: bool):
	_draw_lanes_game = value
	call_deferred("rebuild_segments", true)


func _get_draw_lanes_game() -> bool:
	return _draw_lanes_game


## Returns all RoadSegments which are directly children of RoadPoints.
##
## Will not return RoadSegmetns of nested scenes, presumed to be static.
func get_segments() -> Array:
	var segs = []
	for ch in get_children():
		if not ch is RoadPoint:
			continue
		for pt_ch in ch.get_children():
			if not pt_ch is RoadSegment:
				continue
			segs.append(pt_ch)
	return segs


func rebuild_segments(clear_existing=false):
	if debug:
		print("Rebuilding RoadSegments")

	if clear_existing:
		segid_map = {}
		for ch in get_segments():
			ch.queue_free()
	else:
		# TODO: think of using groups instead, to have a single manager
		# that is not dependnet on this parenting structure.
		pass

	# Goal is to loop through all RoadPoints, and check if an existing segment
	# is there, or needs to be added.
	var rebuilt = 0
	var signal_rebuilt = []
	for obj in get_children():
		if not obj.visible:
			continue # Assume local chunk has dealt with the geo visibility.
		if not obj is RoadPoint:
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
		var res
		if prior_pt and prior_pt.visible:
			res = _process_seg(prior_pt, pt)
			if res[0] == true:
				rebuilt += 1
				signal_rebuilt.append(res[1])
		if next_pt and next_pt.visible:
			res = _process_seg(pt, next_pt)
			if res[0] == true:
				rebuilt += 1
				signal_rebuilt.append(res[1])

	# Once all RoadSegments (and their lanes) exist, update next/prior lanes.
	if generate_ai_lanes:
		update_lane_seg_connections()

	if debug:
		print_debug("Road segs rebuilt: ", rebuilt)

	# Aim to do a single signal emission across the whole network update.
	emit_signal("on_road_updated", signal_rebuilt)


## Removes a single RoadSegment, ensuring no leftovers and signal is emitted.
func remove_segment(seg:RoadSegment) -> void:
	if not seg or not is_instance_valid(seg):
		print("What is seg now?, ", seg)
		push_warning("RoadSegment is invalid, cannot remove")
		print("Did NOT signal for the removal here", seg)
		return
	var id := seg.get_id()
	seg.queue_free()
	segid_map.erase(id)

	# If this function is triggered by during an onpoint update (such as
	# setting next_pt_init to ""), then this would be a repeat signal call.
	#emit_signal("on_road_updated", [])


## Create a new road segment based on input prior and next RoadPoints.
## Returns Array[was_updated: bool, RoadSegment]
func _process_seg(pt1:RoadPoint, pt2:RoadPoint, low_poly:bool=false) -> Array:
	# TODO: The id setup below will have issues if a "next" goes into "prior", ie rev dir
	# but doing this for simplicity now.

	var sid = "%s-%s" % [pt1.get_instance_id(), pt2.get_instance_id()]
	if sid in segid_map:
		if not is_instance_valid(segid_map[sid]):
			push_error("Instance was not valid on sid: %s" % sid)
		var was_rebuilt = segid_map[sid].check_rebuild()
		return [was_rebuilt, segid_map[sid]]
	else:
		var new_seg = RoadSegment.new(self)

		# We want to, as much as possible, deterministically add the RoadSeg
		# as a child of a consistent RoadPoint. Even though the segment is
		# connected to two road points, it will only be placed as a parent of
		# one of them
		pt1.add_child(new_seg)
		if debug_scene_visible:
			new_seg.owner = self.owner
		new_seg.low_poly = low_poly
		new_seg.start_point = pt1
		new_seg.end_point = pt2
		segid_map[sid] = new_seg
		new_seg.material = material_resource
		new_seg.check_rebuild()

		if generate_ai_lanes:
			new_seg.generate_lane_segments()

		return [true, new_seg]

# Update the lane_next and lane_prior connections based on tags assigned.
#
# Process over each end of "connecting" Lanes, therefore best to iterate
# over RoadPoints.
func update_lane_seg_connections():
	for obj in get_children():
		if not obj.visible:
			continue # Assume local chunk has dealt with the geo visibility.
		if not obj is RoadPoint:
			continue
		var pt:RoadPoint = obj

		# update prior lanes to match next lanes first.
		var prior_valid = pt.prior_seg and is_instance_valid(pt.prior_seg)
		var next_valid = pt.next_seg and is_instance_valid(pt.next_seg)

		if not (prior_valid and next_valid):
			# Nothing to update
			# TODO: technically should clear next lane and prior lanes,
			# but for now since lanes are re-generated each time, there's no
			# risk of having faulty connections.
			continue

		var prior_seg_lanes = pt.prior_seg.get_lanes()
		var next_seg_lanes = pt.next_seg.get_lanes()

		# Check lanes attributed to the *prior* segment
		for ln in prior_seg_lanes:
			# prior lane be set to track to a next lane
			for next_ln in next_seg_lanes:
				if next_ln.lane_prior_tag == ln.lane_next_tag:
					if ln.reverse_direction:
						# if reverse, then a "next" lane becomes the "prior"
						ln.lane_prior = ln.get_path_to(next_ln)
					else:
						ln.lane_next = ln.get_path_to(next_ln)
		# Check lanes attributed to the *next* segment
		for ln in next_seg_lanes:
			# next lane be set to track to a prior lane
			for prior_ln in prior_seg_lanes:
				if prior_ln.lane_next_tag == ln.lane_prior_tag:
					if ln.reverse_direction:
						# if reverse, then a "prior" lane becomes the "next"
						ln.lane_next = ln.get_path_to(prior_ln)
					else:
						ln.lane_prior = ln.get_path_to(prior_ln)


# Triggered by adjusting RoadPoint transform in editor via signal connection.
func on_point_update(point:RoadPoint, low_poly:bool) -> void:
	if not auto_refresh:
		return
	elif not is_instance_valid(point):
		return

	var segs_updated = []  # For signal emission
	var res

	point.validate_junctions(auto_refresh)
	var use_lowpoly = low_poly and use_lowpoly_preview
	if is_instance_valid(point.prior_seg):
		point.prior_seg.low_poly = use_lowpoly
		point.prior_seg.is_dirty = true
		point.prior_seg.call_deferred("check_rebuild")
		if not use_lowpoly:
			point.prior_seg.generate_lane_segments()
		else:
			point.prior_seg.clear_lane_segments()
		segs_updated.append(point.prior_seg)  # Track an updated RoadSegment

	elif point.prior_pt_init and point.get_node(point.prior_pt_init).visible:
		var prior = point.get_node(point.prior_pt_init)
		res = _process_seg(prior, point, use_lowpoly)
		if res[0] == true:
			segs_updated.append(res[1])  # Track an updated RoadSegment

	if is_instance_valid(point.next_seg):
		point.next_seg.low_poly = use_lowpoly
		point.next_seg.is_dirty = true
		point.next_seg.call_deferred("check_rebuild")
		if not use_lowpoly:
			point.next_seg.generate_lane_segments()
		else:
			if point.next_seg:
				point.next_seg.clear_lane_segments()
		segs_updated.append(point.next_seg)  # Track an updated RoadSegment
	elif point.next_pt_init and point.get_node(point.next_pt_init).visible:
		var next = point.get_node(point.next_pt_init)
		res = _process_seg(point, next, use_lowpoly)
		if res[0] == true:
			segs_updated.append(res[1])  # Track an updated RoadSegment

	if len(segs_updated) > 0:
		if self.debug:
			print_debug("Road segs rebuilt: ", len(segs_updated))
		emit_signal("on_road_updated", segs_updated)


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
	# be assigned an "owner". Use the RoadContainer's owner. But, the RoadContainer
	# won't have an owner if it is the scene root. In that case, make the
	# RoadContainer the owner.
	var own
	if owner:
		own = owner
	else:
		own = self

	if not material_resource:
		material_resource = RoadMaterial
		print("Added material to ", name)

	_check_migrate_points()


## Detect and move legacy node hierharcy layout.
##
## With addon v0.3.4 and earlier, RoadPoints were parented to an intermediate
## "points" spatial which was automatically generated
func _check_migrate_points():
	var moved_pts: int = 0
	var pts = get_node_or_null("points")
	if pts == null:
		return

	for ch in pts.get_children():
		if ch is RoadPoint:
			pts.remove_child(ch)
			self.add_child(ch)
			ch.owner = self.owner
			moved_pts += 1

	if moved_pts == 0:
		return

	push_warning("Perofrmed a one-time move of %s point(s) from points to RoadContainer parent %s" % [
		moved_pts, self.name
	])

