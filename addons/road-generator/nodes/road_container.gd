@tool
@icon("res://addons/road-generator/resources/road_container.png")
class_name RoadContainer
extends Node3D
## The parent node for [RoadPoint]'s and controller of actual geo creation.
##
## A Road is defined by a [RoadContainer] with two or more [RoadPoint] children
## who are connected together.
##
## Can be saved as the root of a scene for reuse, otherwise should be placed as
## the child of a [RoadManager] node.
##
## @tutorial(Getting started): https://github.com/TheDuckCow/godot-road-generator/wiki/A-getting-started-tutorial
## @tutorial(Custom Materials Tutorial): https://github.com/TheDuckCow/godot-road-generator/wiki/Creating-custom-materials
## @tutorial(Custom Mesh Tutorial): https://github.com/TheDuckCow/godot-road-generator/wiki/User-guide:-Custom-road-meshes


# ------------------------------------------------------------------------------
#region Signals/Enums/Const
# ------------------------------------------------------------------------------


## Emitted when a road segment has been (re)generated, returning the list
## of updated segments of type Array.
signal on_road_updated(updated_segments: Array)

## For internal purposes, to handle drag events in the editor.
signal on_transform(node)

const RoadSegment = preload("res://addons/road-generator/nodes/road_segment.gd")
const RoadMaterial = preload("res://addons/road-generator/resources/road_texture.material")

# ------------------------------------------------------------------------------
# How road meshes are generated
@export_group("Road Generation")
# ------------------------------------------------------------------------------


## Generate procedural road geometry.[br][br]
##
## If off, it indicates the developer will load in their own custom mesh + collision.
@export var create_geo := true: set = _set_create_geo

## Material applied to the generated meshes, expects specific trimsheet UV layout[br][br]
##
## If cleared, will utilize the default specificed by the [RoadManager].
@export var material_resource: Material: set = _set_material

## Material applied to the underside of the generated meshes[br][br]
##
## If cleared, will utilize the default specificed by the [RoadManager].
@export var material_underside: Material: set = _set_material_underside

## Defines the distance in meters between road loop cuts.[br][br]
##
## This mirrors the same term used in native Curve3D objects where a higher
## density means a larger spacing between loops and fewer overall verticies.[br][br]
##
## A value of -1 indicates the density of the RoadManager will be used, or the
## internal default of 4.0 if no manager is present.
@export var density: float = -1.0: set = _set_density

## Use fewer loop cuts for performance during transform.
@export var use_lowpoly_preview: bool = false

## Flatten terrain when transforming this RoadContainer or child RoadPoints[br]
## if a terrain connector is set up.
## flatten terrain underneath them if a terrain connector is used.
@export var flatten_terrain: bool = true

## Defines the thickness in meters of the underside part of the road.[br][br]
##
## A value of -1 indicates the thickness of the RoadRoadManager will be used, or the
## underside will not be generated at all.
@export var underside_thickness: float = -1.0: set = _set_thickness

# ------------------------------------------------------------------------------
# Properties defining how to set up the road's StaticBody3D
@export_group("Collision")
# ------------------------------------------------------------------------------


## The PhysicsMaterial to apply to static bodies.[br][br]
##
## An override for any present on the parent [member RoadManager.physics_material] .
@export var physics_material: PhysicsMaterial:
	set(value):
		physics_material = value
		_defer_refresh_on_change()

## Group name to assign to the staic bodies created within a RoadSegment.
@export var collider_group_name := "": set = _set_collider_group
## Meta property name to assign to the static bodies created within a RoadSegment.
@export var collider_meta_name := "": set = _set_collider_meta

## If enabled, use collision_layer and collision_mask defined on this RoadContainer instead of the [RoadManager].
@export var override_collision_layers:bool = false
## Collision layer to assign to the generated [StaticBody3D]'s own collision_layer.
@export_flags_3d_physics var collision_layer: int = 1:
	set(value):
		collision_layer = value
		_defer_refresh_on_change()
## Collision mask to assign to the generated [StaticBody3D]'s own collision_mask.
@export_flags_3d_physics var collision_mask: int = 1:
	set(value):
		collision_mask = value
		_defer_refresh_on_change()


# ------------------------------------------------------------------------------
# Properties relating to how RoadLanes and AI tooling is set up
@export_group("Lanes and AI")
# ------------------------------------------------------------------------------


## Whether to auto-generate [RoadLane]'s for AI agents to follow.[br][br]
##
## These are extensions of the native 3D Curve, added to the runtime game as a
## child of RoadPoints when connections exist.
@export var generate_ai_lanes := false: set = _set_gen_ai_lanes

## The group name to assign to any procedurally generated [RoadLane]'s.
@export var ai_lane_group := "": set = _set_ai_lane_group

## Setter applied to [RoadLane] on whether to auto-free registered vehicles on _exit_tree.[br][br]
##
## This lets the road generator handle the cleanup of any vehicles listed as
## following a road segment about to be deleted anyways, even when the vehicle
## is not a direct child of the segments being removed.
@export var auto_free_vehicles := true: set = _set_auto_free_vehicles

## Visualize [RoadLane]'s and their directions in the editor directly.
@export var draw_lanes_editor := false: get = _get_draw_lanes_editor, set = _set_draw_lanes_editor
## Visualize [RoadLane]'s and their directions during the game runtime.
@export var draw_lanes_game := false: get = _get_draw_lanes_game, set = _set_draw_lanes_game


# ------------------------------------------------------------------------------
# Properties which assist with further decorating of roads, such as sidewalks
# and railings
@export_group("Decoration")
# ------------------------------------------------------------------------------


## Create approximated curves along the left, right, and center of the road.[br][br]
##
## Exposed in the editor, useful for adding procedural generation along road
## edges or center lane.
@export var create_edge_curves := false: set = _set_create_edge_curves


# ------------------------------------------------------------------------------
# Auto generated exposed variables used to connect this RoadContainer to
# another RoadContainer.
# These should *never* be manually adjusted, they are only export vars to
# facilitate the connection of RoadContainers needing to connect to points in
# different scenes, where said connection needs to be established in the editor.
# TODO: In Godot 4.3ish, these should be @export_storage, hidden to users
# https://github.com/godotengine/godot/pull/82122
@export_group("Internal data")
# ------------------------------------------------------------------------------

## Output additional debug information, does not change functionality.
@export var debug := false

## Considered private, not meant for editor or script interaction.[br][br]
##
## Paths to other containers, relative to this container (self)
@export var edge_containers: Array[NodePath]
## Considered private, not meant for editor or script interaction.[br][br]
##
## Node paths within other containers, relative to the *target* container (not self here)
@export var edge_rp_targets: Array[NodePath]
## Considered private, not meant for editor or script interaction.[br][br]
##
## Direction of which RP we are connecting to, used to make unique key along with
## the edge_rp_targets path above. Enum value of RoadPoint.PointInit
@export var edge_rp_target_dirs: Array[int]
## Considered private, not meant for editor or script interaction.[br][br]
##
## Node paths within this container, relative to this container
@export var edge_rp_locals: Array[NodePath]
## Considered private, not meant for editor or script interaction.[br][br]
##
## Local RP directions, enum value of RoadPoint.PointInit
@export var edge_rp_local_dirs: Array[int]


# ------------------------------------------------------------------------------
#endregion
#region Runtime variables
# ------------------------------------------------------------------------------


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

# Edge-related error state
var _edge_error: String = ""

# Variables for internal handling of drag events
# Constants used for adhoc meta tags for internal state assignments
var _drag_init_transform # : Transform3D can't type as it needs to be nullable
var _drag_source_rp: RoadPoint
var _drag_target_rp: RoadPoint

# Flag used internally during initial setup to avoid repeat generation
var _is_ready := false


# ------------------------------------------------------------------------------
#endregion
#region Setup and export setter/getters
# ------------------------------------------------------------------------------


func _ready():
	# setup_road_container won't work in _ready unless call_deferred is used
	setup_road_container.call_deferred()

	set_notify_transform(true) # TOOD: check if both of these are necessary
	set_notify_local_transform(true)

	get_manager()
	update_edges()
	validate_edges()

	# Waiting to mark _is_ready = true is the way we prevent each property
	# value change from re-triggering rebuilds during scene setup. It's because
	# each property value functionally gets "assigned" the value loaded from
	# the tscn file, and thus triggers its set(get) functions which perform work
	_is_ready = true
	rebuild_segments(true)


func _enter_tree() -> void:
	pass


## Cleanup the road segments specifically, in case they aren't children.
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


func _get_configuration_warnings() -> PackedStringArray:
	var warnstr

	if get_tree().get_edited_scene_root() != self:
		var any_manager := false
		var _last_par = get_parent()
		while true:
			if _last_par.get_path() == ^"/root":
				break
			if _last_par.has_method("is_road_manager"):
				any_manager = true
				_last_par._skip_warn_found_rc_child = true
				break
			_last_par = _last_par.get_parent()
		if any_manager == false:
			warnstr = "A RoadContainer should either be the scene root, or have a RoadManager somewhere in its parent hierarchy"
			return [warnstr]

	var has_rp_child = false
	for ch in get_children():
		if ch is RoadPoint:
			has_rp_child = true
			break
	if not has_rp_child:
		warnstr = "Add RoadPoint nodes as children to form a road, or use the Roads menu in the 3D view header"
		return [warnstr]

	if _needs_refresh:
		warnstr = "Refresh outdated geometry by selecting this node and going to 3D view > Roads menu > Refresh Roads"
		return [warnstr]

	if _edge_error != "":
		warnstr = "Refresh roads to clear invalid connections:\n%s" % _edge_error
		return [warnstr]
	return []


## Workaround for cyclic typing
func is_road_container() -> bool:
	return true


## Temp added
func get_owner() -> Node:
	return self.owner if is_instance_valid(self.owner) else self


func is_subscene() -> bool:
	return scene_file_path and self != get_tree().edited_scene_root


func _defer_refresh_on_change() -> void:
	if _dirty:
		return
	elif not is_node_ready():
		return # assume it'll be called by the main ready function once, well, ready
	elif _auto_refresh:
		_dirty = true
		call_deferred("_dirty_rebuild_deferred")
	else: # We would have done a rebuild if auto_refresh, so set the flag.
		_needs_refresh = true


func _set_gen_ai_lanes(value: bool) -> void:
	generate_ai_lanes = value
	_defer_refresh_on_change()


func _set_ai_lane_group(value: String) -> void:
	ai_lane_group = value
	_defer_refresh_on_change()


func _set_auto_free_vehicles(value: bool) -> void:
	auto_free_vehicles = value
	for seg in get_segments():
		for _lane in seg.get_lanes():
			_lane.auto_free_vehicles = value


func _set_collider_group(value: String) -> void:
	collider_group_name = value
	_defer_refresh_on_change()


func _set_collider_meta(value: String) -> void:
	collider_meta_name = value
	_defer_refresh_on_change()


func _set_density(value) -> void:
	density = value
	_defer_refresh_on_change()


func _set_thickness(value) -> void:
	underside_thickness = value
	_defer_refresh_on_change()


func _set_material(value) -> void:
	material_resource = value
	_defer_refresh_on_change()


func _set_material_underside(value) -> void:
	material_underside = value
	_defer_refresh_on_change()


func _dirty_rebuild_deferred() -> void:
	if not is_node_ready():
		return
	if _dirty:
		_dirty = false
		call_deferred("rebuild_segments", true)


func _set_draw_lanes_editor(value: bool):
	_draw_lanes_editor = value
	for seg in get_segments():
		if not generate_ai_lanes:
			seg.clear_lane_segments()
		else:
			seg.update_lane_visibility()


func _get_draw_lanes_editor() -> bool:
	return _draw_lanes_editor


func _set_draw_lanes_game(value: bool):
	_draw_lanes_game = value
	for seg in get_segments():
		seg.update_lane_visibility()


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


func _set_create_edge_curves(value: bool) -> void:
	create_edge_curves = value
	if create_edge_curves:
		for seg in get_segments():
			seg.generate_edge_curves()
	else:
		for seg in get_segments():
			seg.clear_edge_curves()


# ------------------------------------------------------------------------------
#endregion
#region Editor interactions
# ------------------------------------------------------------------------------


func _notification(what):
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		var lmb_down = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		if lmb_down and not _drag_init_transform:
			self._drag_init_transform = global_transform
		elif not lmb_down:
			on_transform.emit(self)
			var manager = get_manager()
			if is_instance_valid(manager):
				manager.on_container_transformed.emit(self)
			_drag_init_transform = null


# ------------------------------------------------------------------------------
#endregion
#region Functions
# ------------------------------------------------------------------------------


## Get the highest-level RoadManager parent to this node.
##
## If multiple in hiearchy, the top-most one will be used.
func get_manager(): # -> Optional[RoadManager]
	var _this_manager = null
	var _last_par = get_parent()
	while true:
		if _last_par == null or not _last_par.is_inside_tree():
			break
		if _last_par.get_path() == ^"/root":
			break
		if _last_par.has_method("is_road_manager"):
			_this_manager = _last_par
		_last_par = _last_par.get_parent()
	_manager = _this_manager
	return _manager


func get_roadpoints(skip_edge_connected=false) -> Array:
	var rps = []
	for obj in get_children():
		if not obj is RoadPoint:
			continue
		if not obj.visible:
			continue # Assume local chunk has dealt with the geo visibility.
		if obj.is_queued_for_deletion():
			continue # To be cleaned up anyways
		var pt:RoadPoint = obj
		rps.append(pt)

	if skip_edge_connected:
		# Filter out pts which shouldn't be lane-changed (ie due to containers)
		for itm in rps:
			if itm.cross_container_connected():
				rps.erase(itm)

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
			if pt_ch.is_queued_for_deletion():
				continue
			segs.append(pt_ch)
	return segs


## Recursively gets all RoadContainers within a root node
func get_all_road_containers(root: Node)->Array:
	var nodes: Array = []
	var dist: float

	for n in root.get_children():
		if n.get_child_count() > 0:
			if n.has_method("is_road_container"):
				nodes.append(n)
			nodes.append_array(get_all_road_containers(n))
		else:
			if n.has_method("is_road_container"):
				nodes.append(n)
	return nodes


## Transforms sel_rp's parent road container such that sel_rp is perfectly
## aligned (or flip-aligned) with tgt_rp
func snap_to_road_point(sel_rp: RoadPoint, tgt_rp: RoadPoint):
	var res := get_transform_for_snap_rp(sel_rp, tgt_rp)
	global_transform = res[0]
	var sel_dir:int = res[1]
	var tgt_dir:int = res[2]
	sel_rp.connect_container(sel_dir, tgt_rp, tgt_dir)


func get_transform_for_snap_rp(src_rp: RoadPoint, tgt_rp: RoadPoint) -> Array:
	var rp_trans:Transform3D = src_rp.global_transform
	var tgt_trans:Transform3D = tgt_rp.global_transform
	var cont_trans:Transform3D = global_transform

	var start_dir: int
	var end_dir: int

	# Add 180 degrees to Y rotation if needed
	var is_prior_prior: bool = src_rp.next_pt_init and tgt_rp.next_pt_init
	var is_next_next: bool = src_rp.prior_pt_init and tgt_rp.prior_pt_init
	if is_prior_prior or is_next_next:
		tgt_trans.basis = tgt_trans.basis.rotated(Vector3(0, 1, 0), PI) # fkip around y
	if is_next_next:
		start_dir = RoadPoint.PointInit.NEXT
		end_dir = RoadPoint.PointInit.NEXT
	elif is_prior_prior:
		start_dir = RoadPoint.PointInit.PRIOR
		end_dir = RoadPoint.PointInit.PRIOR
	elif not src_rp.next_pt_init:
		start_dir = RoadPoint.PointInit.NEXT
		end_dir = RoadPoint.PointInit.PRIOR
	else:
		start_dir = RoadPoint.PointInit.PRIOR
		end_dir = RoadPoint.PointInit.NEXT

	var transform_difference = tgt_trans * rp_trans.affine_inverse()

	# Return structure designed to enable new placement and calling src_rp.connect_container
	return [transform_difference * cont_trans, start_dir, end_dir]


## Get edge RoadPoint closest to input 3D position.
func get_closest_edge_road_point(g_search_pos: Vector3)->RoadPoint:
	var closest_rp: RoadPoint
	var closest_dist: float

	for rp in get_open_edges():
		var this_dist = g_search_pos.distance_squared_to(rp.global_position)
		if not closest_dist or this_dist < closest_dist:
			closest_dist = this_dist
			closest_rp = rp
	return closest_rp


## Get Edge RoadPoints that are open and available for connections
func get_open_edges()->Array:
	var rp_edges: Array = []
	for idx in len(edge_rp_locals):
		var edge: RoadPoint = get_node_or_null(edge_rp_locals[idx])
		var connected: RoadPoint = get_node_or_null(edge_rp_targets[idx])
		if connected:
			# Edge is already connected
			continue
		elif edge and edge.terminated:
			# Edge is terminated (TODO: remove this branch, should not longer be in edge list now)
			continue
		elif edge:
			# Edge is available for connections
			rp_edges.append(edge)
		else:
			# Edge is non-existent
			continue
	return rp_edges


## Get Edge RoadPoints that are unavailable for connections. Returns
## local Edges, target Edges, and target containers.
func get_connected_edges()->Array:
	var rp_edges: Array = []
	for idx in len(edge_rp_locals):
		var edge: RoadPoint = get_node_or_null(edge_rp_locals[idx])
		var target_cont: RoadContainer = get_node_or_null(edge_containers[idx])
#		var is_scene =
		# Find out if the target container is a scene
		if target_cont and target_cont.scene_file_path:
			print("%s %s is a scene %s" % [Time.get_ticks_msec(), target_cont.name, target_cont.scene_file_path])
#		else:
#			print("target_cont is null")
		if not target_cont:
			continue
		var target: RoadPoint = target_cont.get_node_or_null(edge_rp_targets[idx])
		if target and edge:
			# Edge is already connected
			rp_edges.append([edge, target, target_cont])
		elif edge and edge.terminated:
			# Edge is terminated
			continue
		elif edge:
			# Edge is available for connections
			continue
		else:
			# Edge is non-existent
			continue
	return rp_edges

## Returns array of connected Edges that are not in a nested scene.
func get_moving_edges()->Array:
	var rp_edges: Array = []
	for rp in get_connected_edges():
		var edge: RoadPoint = rp[0]
		var target: RoadPoint = rp[1]
		var target_cont: RoadContainer = rp[2]
		# Skip Edge if target container is nested scene
		if target_cont and target_cont.is_subscene():
			continue
		# Add Edge to list
		rp_edges.append([edge, target, target_cont])
	return rp_edges


## Moves RoadPoints connected to this container if this is
## a nested scene and target is not a nested scene.
func move_connected_road_points():
	# Bail if this is not a nested scene
	if not is_subscene():
		return
	# Iterate only moving RoadPoints
	for rp in get_moving_edges():
		var sel_rp: RoadPoint = rp[0]
		var tgt_rp: RoadPoint = rp[1]
		# Move connected RoadPoint
		tgt_rp.global_transform = sel_rp.global_transform

		# Add 180 degrees to Y rotation if needed
		var is_prior_prior: bool = sel_rp.next_pt_init and tgt_rp.next_pt_init
		var is_next_next: bool = sel_rp.prior_pt_init and tgt_rp.prior_pt_init
		if is_prior_prior or is_next_next:
			var basis_y = sel_rp.global_transform.basis.y
			sel_rp.rotate(basis_y, PI)

## Update export variable lengths and counts to account for connection to
## other RoadContainers
func update_edges():
	# TODO: Optomize parent callers to avoid re-calls, e.g. on save.
	#print("Debug: Updating container edges %s" % self.name)

	var _tmp_containers:Array[NodePath] = []
	var _tmp_rp_targets:Array[NodePath] = []
	var _tmp_rp_target_dirs:Array[int] = []
	var _tmp_rp_locals:Array[NodePath] = []
	var _tmp_rp_local_dirs:Array[int] = []

	for ch in get_roadpoints():
		var pt:RoadPoint = ch
		if pt.terminated:
			# Terminated points should not be counted as external edges
			continue

		for this_dir in [RoadPoint.PointInit.NEXT, RoadPoint.PointInit.PRIOR]:
			var is_edge := false
			var dir_pt_init
			if this_dir == RoadPoint.PointInit.PRIOR:
				dir_pt_init = pt.prior_pt_init
			else:
				dir_pt_init = pt.next_pt_init

			if dir_pt_init == ^"":
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

			if idx >= 0 and len(edge_containers) > idx:
				_tmp_containers.append(edge_containers[idx])
				_tmp_rp_targets.append(edge_rp_targets[idx])
				_tmp_rp_target_dirs.append(edge_rp_target_dirs[idx])
			else:
				_tmp_containers.append(^"")
				_tmp_rp_targets.append(^"")
				_tmp_rp_target_dirs.append(-1) # -1 to mean an unconnected index, since valid enums are 0+

	# Finally, do a near-synchronous update of the export var references
	edge_containers = _tmp_containers
	edge_rp_targets = _tmp_rp_targets
	edge_rp_target_dirs = _tmp_rp_target_dirs
	edge_rp_locals = _tmp_rp_locals
	edge_rp_local_dirs = _tmp_rp_local_dirs


## Check for any invalid connections between containers
##
## Checks to see that connections are reciprocol.
## Returns true if any invalid/autofixed (reciprocol disconnection)
func validate_edges(autofix: bool = false) -> bool:
	var is_valid := true
	for _idx in range(len(edge_rp_locals)):
		var this_pt_path = edge_rp_locals[_idx]

		# Pre-check, ensure local node paths are good.
		var this_pt = get_node_or_null(this_pt_path)
		if not is_instance_valid(this_pt):
			is_valid = false
			_invalidate_edge(_idx, autofix, "edge_rp_local node reference is invalid")
			continue

		var this_dir = edge_rp_local_dirs[_idx]
		var target_pt = edge_rp_targets[_idx]
		var target_dir = edge_rp_target_dirs[_idx]
		var target = null  # the presumed connected RP.

		if this_dir == this_pt.PointInit.NEXT:
			if this_pt.next_pt_init != ^"":
				# Shouldn't be marked as connecting to another local pt, "" indicates edge pt.
				is_valid = false
				_invalidate_edge(_idx, autofix, "next_pt_init should be empty for this edge's next pt")
				continue
			else:
				target = this_pt.get_next_rp()
		elif this_dir == this_pt.PointInit.PRIOR:
			if this_pt.prior_pt_init != ^"":
				# Shouldn't be marked as connecting to another local pt, "" indicates edge pt.
				is_valid = false
				_invalidate_edge(_idx, autofix, "prior_pt_init should be empty for this edge's prior pt")
				continue
			else:
				target = this_pt.get_prior_rp()
		elif this_dir == -1:
			# The local dir should never be -1, since it's defined locally.
			is_valid = false
			_invalidate_edge(_idx, autofix, "edge_rp_local_dir is -1, should not happen")
			continue
		else:
			# Invalid value assigned for direction.
			is_valid = false
			_invalidate_edge(_idx, autofix, "edge_rp_local_dirs value invalid")
			continue

		if edge_containers[_idx] != ^"":
			# Connection should be there, verify values.
			var cont = get_node_or_null(edge_containers[_idx])
			if not is_instance_valid(cont):
				is_valid = false
				_invalidate_edge(_idx, autofix, "edge_container reference not valid")
				continue

			var tg_node = cont.get_node_or_null(target_pt)
			if not is_instance_valid(tg_node):
				is_valid = false
				_invalidate_edge(_idx, autofix, "edge_rp_target reference not valid")
				continue
			if not target_dir in [tg_node.PointInit.NEXT, tg_node.PointInit.PRIOR]:
				is_valid = false
				_invalidate_edge(_idx, autofix, "edge_rp_target_dirs value invalid")
				continue

			var tg_ready = is_instance_valid(tg_node.container) and tg_node.container.is_node_ready()
			var this_ready = is_instance_valid(this_pt.container) and this_pt.container.is_node_ready()
			if not tg_ready or not this_ready:
				continue

			# check they occupy the same position / size / etc
			if tg_node.global_transform.origin != this_pt.global_transform.origin:
				var loc_diff = tg_node.global_transform.origin - this_pt.global_transform.origin
				if loc_diff.length() < 0.001:
					pass  # floating point rounding margin
				elif autofix:
					snap_and_update(tg_node, this_pt)
					continue
				else:
					# don't auto-clear this ever, as it's not related to export var references
					is_valid = false
					_invalidate_edge(_idx, false, "Edge points don't occupy the same location: %s/%s and %s/%s" % [
						tg_node.container.name, tg_node.name, this_pt.container.name, this_pt.name
					])
					continue

		else:
			# If edge_container is empty, then ensure that RP in that direction
			# does not think it's connected.
			pass
	if is_valid:
		_edge_error = ""
	elif debug:
		print("Found invalid edges on %s" % self.name)
	return is_valid


## A data cleanup way to clear invalid edges.
##
## Normally would use a roadpoint's disconnect_container function,
## but if there's data inconsistency, we need to manually clear connections.
func _invalidate_edge(_idx, autofix: bool, reason=""):
	# First, try to clear the reciprocol container.
	_edge_error = reason
	var reason_str = "" if reason == "" else " due to %s" % reason
	if _drag_init_transform:
		# We are mid-drag, so don't mess with edges yet
		return
	push_warning("Invalid cross-container connection, %s with edge index %s%s" % [
		self.name, _idx, reason_str
	])
	if not autofix:
		return
	edge_containers[_idx] = ^""
	edge_rp_targets[_idx] = ^""
	edge_rp_target_dirs[_idx] = -1


func rebuild_segments(clear_existing := false):
	if not is_inside_tree() or not is_node_ready():
		# This most commonly happens in the editor on project restart, where
		# each opened scene tab is quickly loaded and then apparently unloaded,
		# so tab one last saved as not active will defer call rebuild, and by
		# the time rebuild_segments occurs, it has already been disable.
		# With this early return, we avoid all the issues of this nature:
		# Cannot get path of node as it is not in a scene tree.
		# scene/3d/spatial.cpp:407 - Condition "!is_inside_tree()" is true. Returned: Transform()
		return
	var manager = get_manager()
	if is_instance_valid(manager):
		if not manager.is_node_ready():
			# Defer segment building
			return
	update_edges()
	validate_edges(clear_existing)
	_needs_refresh = false
	if debug:
		print("Rebuilding RoadSegments %s" % self.name)

	if clear_existing:
		segid_map = {}
		for ch in get_segments():
			ch.queue_free()
	else:
		# TODO: think of using groups instead, to have a single manager
		# that is not dependent on this parenting structure.
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
			prior_pt = pt.get_node_or_null(pt.prior_pt_init)
			if not is_instance_valid(prior_pt) or not prior_pt.has_method("is_road_point"):
				prior_pt = null
		if pt.next_pt_init:
			next_pt = pt.get_node_or_null(pt.next_pt_init)
			if not is_instance_valid(next_pt) or not next_pt.has_method("is_road_point"):
				next_pt = null

		if not prior_pt and not next_pt:
			push_warning("Road point %s/%s not connected to anything yet" % [pt.get_parent().name, pt.name])
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

	if signal_rebuilt.size() > 0:
		_emit_road_updated(signal_rebuilt)


## Removes a single RoadSegment, ensuring no leftovers and signal is emitted.
func remove_segment(seg:RoadSegment) -> void:
	if not seg or not is_instance_valid(seg):
		push_warning("RoadSegment is invalid, cannot remove: ")
		#print("Did NOT signal for the removal here", seg)
		return
	seg.clear_lane_segments()
	var id := seg.get_id()
	seg.queue_free()
	segid_map.erase(id)

	# If this function is triggered by during an onpoint update (such as
	# setting next_pt_init to ""), then this would be a repeat signal call.
	#emit_signal("on_road_updated", [])


## Attempt to relocate a given pair of RoadPoints to each other with aligned settings.
##
## Useful to fix or update after the transformation of points / road containers
## with connections to other containers.
func snap_and_update(rp_a: Node, rp_b: Node) -> void:
	if debug:
		print("Snapping %s and %s" % [rp_a.name, rp_b.name])
	var rpa_sub = rp_a.container.is_subscene()
	var rpb_sub = rp_b.container.is_subscene()
	if rpa_sub and rpb_sub:
		push_warning("Cannot snap together two RoadPoints both of saved subscenes")
		return

	var src_pt
	var tgt_pt

	# Prefer to snap the other point to this one, since this one is most likely
	# the one which was just (intentionally) moved by the user.
	if rpb_sub:
		src_pt = rp_b
		tgt_pt = rp_a
	else: # rpa_sub is true or both not subscenes: move B (exterior) to A (selected container)
		src_pt = rp_a
		tgt_pt = rp_b
	if debug:
		print("Snapping %s/%s to position/settings of %s/%s" % [
			tgt_pt.container.name, tgt_pt.name, src_pt.container.name, src_pt.name])

	# Update all other settings; this (possibly badly!) assumes that the
	# edge being updated is oriented the same way as the source (ie prio -> next)
	tgt_pt._is_internal_updating = true
	tgt_pt._is_internal_updating = true
	tgt_pt.global_transform = src_pt.global_transform
	tgt_pt.copy_settings_from(src_pt)
	tgt_pt._is_internal_updating = false
	tgt_pt._is_internal_updating = false
	# Trigger emit_transform only once
	# tgt_pt.emit_transform() causes crashing, but is *definitely* in need of refreshing.


## Create a new road segment based on input prior and next RoadPoints.
## Returns Array[was_updated: bool, RoadSegment]
func _process_seg(pt1:RoadPoint, pt2:RoadPoint, low_poly:bool=false) -> Array:
	var sid = RoadSegment.get_id_for_points(pt1, pt2)
	if sid in segid_map and is_instance_valid(segid_map[sid]):
		var was_rebuilt = segid_map[sid].check_rebuild()
		return [was_rebuilt, segid_map[sid]]
	else:
		var new_seg = RoadSegment.new(self)

		# Must not move from origin, else geometry offsets would occur. Also
		# implies to user to not interact with this item if ever exposed.
		new_seg.set_meta("_edit_lock_", true)
		new_seg.set_meta("_edit_group_", true)

		# We want to, as much as possible, deterministically add the RoadSeg
		# as a child of a consistent RoadPoint. Even though the segment is
		# connected to two road points, it will only be placed as a parent of
		# one of them
		pt1.add_child(new_seg)
		if debug_scene_visible:
			new_seg.owner = self.get_owner()
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

		if material_resource:
			new_seg.material = material_resource
		elif is_instance_valid(_manager) and _manager.material_resource:
			new_seg.material = _manager.material_resource

		if material_underside:
			new_seg.material_underside = material_underside
		elif is_instance_valid(_manager) and _manager.material_underside:
			new_seg.material_underside = _manager.material_underside

		new_seg.check_rebuild()

		var segment_thickness: float
		#if
		# VISSA ANCHOR POINT

		return [true, new_seg]


## Update the lane_next and lane_prior connections based on tags assigned.
##
## Process over each end of "connecting" Lanes, therefore best to iterate
## over RoadPoints.
func update_lane_seg_connections():
	for obj in get_children():
		if not obj is RoadPoint:
			continue
		if not obj.visible:
			continue # Assume local chunk has dealt with the geo visibility.
		if obj.is_queued_for_deletion():
			continue # To be cleaned up anyways
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
		for prior_ln in prior_seg_lanes:
			# prior lane be set to track to a next lane
			for next_ln in next_seg_lanes:
				if prior_ln.lane_next_tag == next_ln.lane_prior_tag:
					# TODO: When directionality is made consistent, we should no longer
					# need to invert the direction assignment here.
					if prior_ln.lane_next_tag[0] == "F":
						prior_ln.lane_prior = prior_ln.get_path_to(next_ln)
						next_ln.lane_next = next_ln.get_path_to(prior_ln)
					else:
						assert(prior_ln.lane_next_tag[0] == "R")
						prior_ln.lane_next = prior_ln.get_path_to(next_ln)
						next_ln.lane_prior = next_ln.get_path_to(prior_ln)


## Triggered by adjusting RoadPoint transform in editor via signal connection.
func on_point_update(point:RoadPoint, low_poly:bool) -> void:
	if not _auto_refresh:
		_needs_refresh = true
		return
	elif not is_instance_valid(point):
		return
	# Update warnings for this or connected containers
	if point.is_on_edge():
		#var prior = point.get_prior_rp()
		#var next = point.get_next_rp()
		# TODO: Need to trigger transform updates on these nodes,
		# without triggering emit_transform etc, these turn into infinite loops or godot crashes
		#if is_instance_valid(prior) and prior.container != self:
		#	snap_and_update(point, prior) # many prop changes, ensure internal skip
		#if is_instance_valid(next) and next.container != self:
		#	snap_and_update(point, next) # many prop changes, ensure internal skip

		point.container.validate_edges()  # could still have problems, if both are subscene.

	var segs_updated = []  # For signal emission
	var res

	if _auto_refresh:
		point.validate_junctions()
	var use_lowpoly = low_poly and use_lowpoly_preview
	
	# Batch updates to reduce signal emissions
	var needs_update = false
	
	if is_instance_valid(point.prior_seg):
		point.prior_seg.low_poly = use_lowpoly
		point.prior_seg.is_dirty = true
		point.prior_seg.call_deferred("check_rebuild")
		segs_updated.append(point.prior_seg)  # Track an updated RoadSegment
		needs_update = true

	elif point.prior_pt_init and point.get_node(point.prior_pt_init).visible:
		var prior = point.get_node(point.prior_pt_init)
		if prior.has_method("is_road_point"):  # ie skip road container.
			res = _process_seg(prior, point, use_lowpoly)
			if res[0] == true:
				segs_updated.append(res[1])  # Track an updated RoadSegment
				needs_update = true

	if is_instance_valid(point.next_seg):
		point.next_seg.low_poly = use_lowpoly
		point.next_seg.is_dirty = true
		point.next_seg.call_deferred("check_rebuild")
		segs_updated.append(point.next_seg)  # Track an updated RoadSegment
		needs_update = true
	elif point.next_pt_init and point.get_node(point.next_pt_init).visible:
		var next = point.get_node(point.next_pt_init)
		if next.has_method("is_road_point"):  # ie skip road container.
			res = _process_seg(point, next, use_lowpoly)
			if res[0] == true:
				segs_updated.append(res[1])  # Track an updated RoadSegment
				needs_update = true

	if needs_update and len(segs_updated) > 0:
		_emit_road_updated(segs_updated)


## Callback from a modification of a RoadSegment object.
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

	_check_migrate_points()
	if not is_instance_valid(get_manager()):
		# Assign a road material by default if there's no parent RoadManager
		material_resource = RoadMaterial


## Signals the segments whichhave been just (re)built
func _emit_road_updated(segments: Array) -> void:
	if self.debug:
		print_debug("Road segs rebuilt: ", len(segments))
	on_road_updated.emit(segments)
	if is_instance_valid(_manager):
		_manager.on_container_update(segments)


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
			ch.owner = self.get_owner()
			moved_pts += 1

	if moved_pts == 0:
		return

	push_warning("Perofrmed a one-time move of %s point(s) from points to RoadContainer parent %s" % [
		moved_pts, self.name
	])


#endregion
# ------------------------------------------------------------------------------
