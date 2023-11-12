## Manager used to generate the actual road segments when needed.
tool
class_name RoadContainer, "../resources/road_container.png"
extends Spatial

## Emitted when a road segment has been (re)generated, returning the list
## of updated segments of type Array. Will also trigger on segments deleted,
## which will contain a list of nothing.
signal on_road_updated (updated_segments)

const RoadMaterial = preload("res://addons/road-generator/resources/road_texture.material")
const RoadSegment = preload("res://addons/road-generator/nodes/road_segment.gd")

export(Material) var material_resource:Material setget _set_material

# Mesh density of generated segments. -1 implies to use the parent RoadManager's value.
export(float) var density:float = -1.0  setget _set_density

# Generate procedural road geometry
# If off, it indicates the developer will load in their own custom mesh + collision.
export(bool) var create_geo := true setget _set_create_geo
# If create_geo is true, then whether to reduce geo mid transform.
export(bool) var use_lowpoly_preview:bool = false

export(bool) var generate_ai_lanes := false setget _set_gen_ai_lanes
export(String) var ai_lane_group := "road_lanes" setget _set_ai_lane_group

export(bool) var debug := false
export(bool) var draw_lanes_editor := false setget _set_draw_lanes_editor, _get_draw_lanes_editor
export(bool) var draw_lanes_game := false setget _set_draw_lanes_game, _get_draw_lanes_game

## Auto generated exposed variables used to connect this RoadContainer to
## another RoadContainer.
## These should *never* be manually adjusted, they are only export vars to
## facilitate the connection of RoadContainers needing to connect to points in
## different scenes, where said connection needs to be established in the editor

# Paths to other containers, relative to this container (self)
export(Array, NodePath) var edge_containers
# Node paths within other containers, relative to the *target* container (not self here)
export(Array, NodePath) var edge_rp_targets
# Direction of which RP we are connecting to, used to make unique key along with
# the edge_rp_targets path above. Enum value of RoadPoint.PointInit
export(Array, int) var edge_rp_target_dirs
# Node paths within this container, relative to this container
export(Array, NodePath) var edge_rp_locals
# Local RP directions, enum value of RoadPoint.PointInit
export(Array, int) var edge_rp_local_dirs  #

# Mapping maintained of individual segments and their corresponding resources.
var segid_map = {}

# Non-exposed developer control, which allows showing all nodes (including generated) in the scene
# tree. Typcially we don't want to do this, so that users don't accidentally start adding nodes
# or making changes that get immediately removed as soon as a road is regenerated.
var debug_scene_visible:bool = false

# Flag used to defer calls to setup_road_container via _dirty_rebuild_deferred,
# important during scene startup whereby class properties are called in
# succession during scene init and otherwise would lead to duplicate calls.
var _dirty:bool = false

# Flag to auto rebuild specific segments under any relevant setting change.
# Default to true, but should be set by the parent RoadManager
var _auto_refresh = true
var _needs_refresh = false

var _draw_lanes_editor:bool = false
var _draw_lanes_game:bool = false

## Refernce to the parent road manager if any.
var _manager:RoadManager


# ------------------------------------------------------------------------------
# Setup and export setter/getters
# ------------------------------------------------------------------------------


func _ready():
	# setup_road_container won't work in _ready unless call_deferred is used
	call_deferred("setup_road_container")

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

	get_manager()
	update_edges()


# Workaround for cyclic typing
func is_road_container() -> bool:
	return true


func is_subscene() -> bool:
	return filename and self != get_tree().edited_scene_root

func _get_configuration_warning() -> String:

	if get_tree().get_edited_scene_root() != self:
		var any_manager := false
		var _last_par = get_parent()
		while true:
			if _last_par.get_path() == "/root":
				break
			if _last_par.has_method("is_road_manager"):
				any_manager = true
				_last_par._skip_warn_found_rc_child = true
				break
			_last_par = _last_par.get_parent()
		if any_manager == false:
			return "A RoadContainer should either be the scene root, or have a RoadManager somewhere in its parent hierarchy"

	var has_rp_child = false
	for ch in get_children():
		if ch is RoadPoint:
			has_rp_child = true
			break
	if not has_rp_child:
		return "Add RoadPoint nodes as children to form a road, or use the create menu in the 3D view header"

	if _needs_refresh:
		return "Refresh outdated geometry by selecting this node and going to 3D view > Roads menu > Refresh Roads"
	return ""


func _defer_refresh_on_change() -> void:
	if _dirty:
		return
	elif _auto_refresh:
		_dirty = true
		call_deferred("_dirty_rebuild_deferred")
	else: # We would have done a rebuild if auto_refresh, so set the flag.
		_needs_refresh = true


func _set_gen_ai_lanes(value: bool) -> void:
	_defer_refresh_on_change()
	generate_ai_lanes = value


func _set_ai_lane_group(value: String) -> void:
	_defer_refresh_on_change()
	ai_lane_group = value


func _set_density(value) -> void:
	_defer_refresh_on_change()
	density = value


func _set_material(value) -> void:
	_defer_refresh_on_change()
	material_resource = value


func _dirty_rebuild_deferred() -> void:
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


func _set_create_geo(value: bool) -> void:
	if value == create_geo:
		return
	create_geo = value
	for ch in get_children():
		# Cyclic loading, have to use workaround
		if not ch.has_method("is_road_point"):
			continue
		for rp_ch in ch.get_children():
			# Cycling loading, have to use workaround
			if rp_ch.has_method("is_road_segment"):
				rp_ch.do_roadmesh_creation()
	if value == true:
		_dirty = true
		call_deferred("_dirty_rebuild_deferred")


# ------------------------------------------------------------------------------
# Container methods
# ------------------------------------------------------------------------------


## Get the highest-level RoadManager parent to this node.
##
## If multiple in hiearchy, the top-most one will be used.
func get_manager(): # -> Optional[RoadManager]
	var _this_manager = null
	var _last_par = get_parent()
	while true:
		if _last_par == null:
			break
		if _last_par.get_path() == "/root":
			break
		if _last_par.has_method("is_road_manager"):
			_this_manager = _last_par
		_last_par = _last_par.get_parent()
	_manager = _this_manager
	return _manager


func get_roadpoints() -> Array:
	var rps = []
	for obj in get_children():
		if not obj is RoadPoint:
			continue
		if not obj.visible:
			continue # Assume local chunk has dealt with the geo visibility.
		var pt:RoadPoint = obj
		rps.append(pt)
	return rps


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

## Update export variable lengths and counts to account for connection to
## other RoadContainers
func update_edges():

	var _tmp_containers := []
	var _tmp_rp_targets := []
	var _tmp_rp_target_dirs := []
	var _tmp_rp_locals := []
	var _tmp_rp_local_dirs := []

	for ch in get_roadpoints():
		var pt:RoadPoint = ch

		for this_dir in [RoadPoint.PointInit.NEXT, RoadPoint.PointInit.PRIOR]:
			var is_edge := false
			var dir_pt_init
			if this_dir == RoadPoint.PointInit.PRIOR:
				dir_pt_init = pt.prior_pt_init
			else:
				dir_pt_init = pt.next_pt_init

			if dir_pt_init == "":
				# Set this rp to indicate its next point is the container,
				# making it aware it is an "edge".
				is_edge = true
			elif dir_pt_init == pt.get_path_to(self):
				# Already self identified as an edge as connected to this container
				is_edge = true
			else:
				# Must be 'interior' as it is connected but not to container
				is_edge = false

			if is_edge == false:
				continue

			_tmp_rp_locals.append(self.get_path_to(pt))
			_tmp_rp_local_dirs.append(this_dir)

			# Lookup pre-existing connections to apply, match of name + dir
			var idx = -1
			for _find_idx in len(edge_rp_locals):
				if edge_rp_locals[_find_idx] != self.get_path_to(pt):
					continue
				if edge_rp_local_dirs[_find_idx] != this_dir:
					continue
				idx = _find_idx
				break

			if idx >= 0:
				_tmp_containers.append(edge_containers[idx])
				_tmp_rp_targets.append(edge_rp_targets[idx])
				_tmp_rp_target_dirs.append(edge_rp_target_dirs[idx])
			else:
				_tmp_containers.append("")
				_tmp_rp_targets.append("")
				_tmp_rp_target_dirs.append(-1) # -1 to mean an unconnected index, since valid enums are 0+

	# Finally, do a near-synchronous update of the export var references
	edge_containers = _tmp_containers
	edge_rp_targets = _tmp_rp_targets
	edge_rp_target_dirs = _tmp_rp_target_dirs
	edge_rp_locals = _tmp_rp_locals
	edge_rp_local_dirs = _tmp_rp_local_dirs



func rebuild_segments(clear_existing=false):
	update_edges()
	_needs_refresh = false
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
	for obj in get_roadpoints():
		var pt:RoadPoint = obj

		var prior_pt
		var next_pt
		if pt.prior_pt_init:
			prior_pt = pt.get_node(pt.prior_pt_init)
			if not is_instance_valid(prior_pt) or not prior_pt.has_method("is_road_point"):
				prior_pt = null
		if pt.next_pt_init:
			next_pt = pt.get_node(pt.next_pt_init)
			if not is_instance_valid(next_pt) or not next_pt.has_method("is_road_point"):
				next_pt = null

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

	# Aim to do a single signal emission across the whole container update.
	emit_signal("on_road_updated", signal_rebuilt)


## Removes a single RoadSegment, ensuring no leftovers and signal is emitted.
func remove_segment(seg:RoadSegment) -> void:
	if not seg or not is_instance_valid(seg):
		push_warning("RoadSegment is invalid, cannot remove: ")
		#print("Did NOT signal for the removal here", seg)
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

	#var sid = "%s-%s" % [pt1.get_instance_id(), pt2.get_instance_id()]
	var sid = RoadSegment.get_id_for_points(pt1, pt2)
	if sid in segid_map and is_instance_valid(segid_map[sid]):
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
		if pt1.next_pt_init != pt1.get_path_to(pt2):
			new_seg._start_flip = true
		else:
			new_seg._start_flip = false
		if pt2.prior_pt_init != pt2.get_path_to(pt1):
			new_seg._end_flip = true
		else:
			new_seg._end_flip = false
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
		if not obj is RoadPoint:
			continue
		if not obj.visible:
			continue # Assume local chunk has dealt with the geo visibility.
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
	if not _auto_refresh:
		_needs_refresh = true
		return
	elif not is_instance_valid(point):
		return

	var segs_updated = []  # For signal emission
	var res

	if _auto_refresh:
		point.validate_junctions()
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
		if prior.has_method("is_road_point"):  # ie skip road container.
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
		if next.has_method("is_road_point"):  # ie skip road container.
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


## Adds points, segments, and material if they're unassigned
func setup_road_container():
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
