@tool
@icon("res://addons/road-generator/resources/road_point.png")
## Definition for a single point handle, which 2+ road segments connect to.
class_name RoadPoint
extends Node3D

signal on_transform(node, low_poly)

enum LaneType {
	NO_MARKING, # Default no marking placed first, but is last texture UV column.
	SHOULDER, # Left side of texture...
	SLOW, # White line on one side, dotted white on other.
	MIDDLE, # Dotted line on both sides.
	FAST, # Double yellow one side, dotted line on other.
	TWO_WAY, # White line one side, double yellow on other.
	ONE_WAY, # white lines on both sides.
	SINGLE_LINE, # ...right side of texture.
	TRANSITION_ADD, # Default gray texture.
	TRANSITION_REM, # Default gray texture.
}

enum LaneDir {
	NONE,
	FORWARD,
	REVERSE,
	BOTH
}

enum TrafficUpdate{
	ADD_FORWARD,
	ADD_REVERSE,
	REM_FORWARD,
	REM_REVERSE,
	MOVE_DIVIDER_LEFT,
	MOVE_DIVIDER_RIGHT
}

# TODO: swap these, so that "NEXT" is intuitively a higher enum int value.
enum PointInit {
	NEXT,
	PRIOR,
}

const UI_TIMEOUT = 50 # Time in ms to delay further refresh updates.
const COLOR_YELLOW = Color(0.7, 0.7, 0,7)
const COLOR_RED = Color(0.7, 0.3, 0.3)
const SEG_DIST_MULT: float = 8.0 # How many road widths apart to add next RoadPoint.

# Assign the direction of traffic order.
# TODO: decide whether to do this
#gd4, not needed?
#var _traffic_dir: Array[LaneDir] = [
#		LaneDir.REVERSE, LaneDir.REVERSE, LaneDir.FORWARD, LaneDir.FORWARD]
#@export var traffic_dir:Array[LaneDir] = [
#		LaneDir.REVERSE, LaneDir.REVERSE, LaneDir.FORWARD, LaneDir.FORWARD]:
#	get:
#		return _traffic_dir
#	set(value):
#		_traffic_dir = value
#		_notify_network_on_set(value)
@export var traffic_dir:Array[LaneDir]: get = _get_dir, set = _set_dir

# Enables auto assignment of the lanes array below, based on traffic_dir setup.
@export var auto_lanes := true: get = _get_auto_lanes, set = _set_auto_lanes

# Assign the textures to use for each lane.
# Order is left to right when oriented such that the RoadPoint is facing towards
# the top of the screen in a top down orientation.
@export var lanes:Array[LaneType]: get = _get_lanes, set = _set_lanes

@export var lane_width := 4.0: get = _get_lane_width, set = _set_lane_width
@export var shoulder_width_l := 2.0: get = _get_shoulder_width_l, set = _set_shoulder_width_l
@export var shoulder_width_r := 2.0: get = _get_shoulder_width_r, set = _set_shoulder_width_r
# Profile: x: how far out the gutter goes, y: how far down to clip.
@export var gutter_profile := Vector2(2.0, -0.5): get = _get_profile, set = _set_profile

# Path to next/prior RoadPoint, relative to this RoadPoint itself.
@export var prior_pt_init: NodePath: get = _get_prior_pt_init, set = _set_prior_pt_init
@export var next_pt_init: NodePath: get = _get_next_pt_init, set = _set_next_pt_init
@export var terminated := false: set = _set_terminated
# Handle magniture
@export var prior_mag := 5.0: get = _get_prior_mag, set = _set_prior_mag
@export var next_mag := 5.0: get = _get_next_mag, set = _set_next_mag

# Generate procedural road geometry
# If off, it indicates the developer will load in their own custom mesh + collision.
@export var create_geo := true: set = _set_create_geo

var rev_width_mag := -8.0
var fwd_width_mag := 8.0
# Ultimate assignment if any export path specified
#var prior_pt:Spatial # Road Point or Junction
var prior_seg
#var next_pt:Spatial # Road Point or Junction
var next_seg

var container # The managing container node for this road segment (direct parent).
var geom:ImmediateMesh # For tool usage, drawing lane directions and end points
#var refresh_geom := true

var _last_update_ms # To calculate min updates.
var _is_internal_updating: bool = false # Very special cases to bypass autofix cyclic


# ------------------------------------------------------------------------------
# Setup and export setter/getters
# ------------------------------------------------------------------------------


func _init():
	# Workaround to avoid linked export arrays between duplicates, see:
	# https://github.com/TheDuckCow/godot-road-generator/issues/86
	# and
	# https://github.com/TheDuckCow/godot-road-generator/pull/87
	traffic_dir = [
		LaneDir.REVERSE, LaneDir.REVERSE, LaneDir.FORWARD, LaneDir.FORWARD
	]
	lanes = [
		LaneType.SLOW, LaneType.FAST, LaneType.FAST, LaneType.SLOW
	]


func _ready():
	# Ensure the transform notificaitons work
	set_notify_transform(true) # TODO: Validate if both are necessary
	set_notify_local_transform(true)
	#set_ignore_transform_notification(false)

	if not container or not is_instance_valid(container):
		var par = get_parent()
		# Can't type check, circular dependency -____-
		#if not par is RoadContainer:
		if not par.has_method("is_road_container"):
			push_warning("Parent of RoadPoint %s is not a RoadContainer" % self.name)
		container = par

	connect("on_transform", Callable(container, "on_point_update"))

	# TODO: If a new roadpoint is just added, we need to trigger this. But,
	# if this is just a scene startup, would be better to call it once only
	# across all roadpoint children. Consequence could be updating references
	# that aren't ready.
	container.update_edges()


func _to_string():
	var parname
	if self.get_parent():
		parname = self.get_parent()
	else:
		parname = "[not in scene]"
	return "RoadPoint %s (id:%s)" % [self.name,  self.get_instance_id()]


func _get_configuration_warnings() -> PackedStringArray:
	var par = get_parent()
	# Can't type check, circular dependency -____-
	#if not par is RoadContainer:
	if not par.has_method("is_road_container"):
		return ["Must be a child of a RoadContainer"]
	return []


# Workaround for cyclic typing
func is_road_point() -> bool:
	return true


# ------------------------------------------------------------------------------
# Editor visualizing
# ------------------------------------------------------------------------------


func _set_lanes(values):
	lanes = values
	if not is_instance_valid(container):
		return  # Might not be initialized yet.
	emit_transform()
func _get_lanes():
	return lanes


func _set_auto_lanes(value):
	auto_lanes = value
	if not is_instance_valid(container):
		return  # Might not be initialized yet.
	emit_transform()
func _get_auto_lanes():
	return auto_lanes


func _set_dir(values):
	traffic_dir = values
	if not is_instance_valid(container):
		return  # Might not be initialized yet.
	emit_transform()
func _get_dir():
	return traffic_dir


func _set_lane_width(value):
	lane_width = value
	if not is_instance_valid(container):
		return  # Might not be initialized yet.
	emit_transform()
func _get_lane_width():
	return lane_width


func _set_shoulder_width_l(value):
	shoulder_width_l = value
	if not is_instance_valid(container):
		return  # Might not be initialized yet.
	emit_transform()
func _get_shoulder_width_l():
	return shoulder_width_l


func _set_shoulder_width_r(value):
	shoulder_width_r = value
	if not is_instance_valid(container):
		return  # Might not be initialized yet.
	emit_transform()
func _get_shoulder_width_r():
	return shoulder_width_r


func _set_profile(value:Vector2):
	gutter_profile = value
	if not is_instance_valid(container):
		return  # Might not be initialized yet.
	emit_transform()


func _get_profile():
	return gutter_profile


func _set_prior_pt_init(value:NodePath):
	var _pre_assign = prior_pt_init
	prior_pt_init = value
	if not is_instance_valid(container):
		return  # Might not be initialized yet.

	# Attempt an auto fix to ensure dependencies are updated. This should happen
	# even if auto_refresh is off, since we want to make sure the container static
	# data is always in a good state *ready* for the next refresh
	_autofix_noncyclic_references(_pre_assign, value, true)

	emit_transform()


func _get_prior_pt_init():
	return prior_pt_init


func _set_next_pt_init(value:NodePath):
	var _pre_assign = next_pt_init
	next_pt_init = value
	if not is_instance_valid(container):
		return  # Might not be initialized yet.

	# Attempt an auto fix to ensure dependencies are updated. This should happen
	# even if auto_refresh is off, since we want to make sure the container static
	# data is always in a good state *ready* for the next refresh
	_autofix_noncyclic_references(_pre_assign, value, false)

	emit_transform()


func _set_terminated(value: bool) -> void:
	terminated = value
	if is_instance_valid(container):
		container.update_edges()

func _get_next_pt_init():
	return next_pt_init


func _set_prior_mag(value):
	prior_mag = value
	if not is_instance_valid(container):
		return  # Might not be initialized yet.
	_notification(Node3D.NOTIFICATION_TRANSFORM_CHANGED)
func _get_prior_mag():
	return prior_mag


func _set_next_mag(value):
	next_mag = value
	if not is_instance_valid(container):
		return  # Might not be initialized yet.
	_notification(Node3D.NOTIFICATION_TRANSFORM_CHANGED)
func _get_next_mag():
	return next_mag


func _set_create_geo(value: bool) -> void:
	if value == create_geo:
		return
	create_geo = value
	for ch in get_children():
		# Due to cyclic reference, can't check class here.
		if ch.has_method("is_road_segment"):
			ch.do_roadmesh_creation()
	if value == true:
		emit_transform()


# ------------------------------------------------------------------------------
# Editor interactions
# ------------------------------------------------------------------------------

func _notification(what):
	if not is_instance_valid(container):
		return  # Might not be initialized yet.
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		var low_poly = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Engine.is_editor_hint()
		emit_transform(low_poly)


func emit_transform(low_poly=false):
	if _is_internal_updating:
		# Special internal update should bypass emit_transform, such as moving two edges in parallel
		return
	if auto_lanes:
		assign_lanes()
	var _gizmos:Array[Node3DGizmo] = get_gizmos()
	if !_gizmos.is_empty():
		var _gizmo:Node3DGizmo = _gizmos[0]
		if is_instance_valid(_gizmo):
			_gizmo.get_plugin().refresh_gizmo(_gizmo)
	emit_signal("on_transform", self, low_poly)


# ------------------------------------------------------------------------------
# Utilities
# ------------------------------------------------------------------------------

## Checks if this RoadPoint is an open edge connection for its parent container.
func is_on_edge() -> bool:
	if self.prior_pt_init and self.next_pt_init:
		return false
	return true


## Returns true if either the forward or reverse RP connection exists to another container
##
## Useful for filtering out edges which should not be modified (given it
## would no longer match the mirrored RoadPoint on the other container).
func cross_container_connected() -> bool:
	if not is_on_edge():
		return false
	var _pr = get_prior_rp()
	if is_instance_valid(_pr) and _pr.container != self.container:
		return true
	var _nt = get_next_rp()
	if is_instance_valid(_nt) and _nt.container != self.container:
		return true
	return false


## Indicates whether this direction is connected, accounting for container connections
func is_prior_connected() -> bool:
	if self.prior_pt_init:
		return true
	# If no sibling point, could still have a cross-container connection
	for _idx in range(len(container.edge_rp_locals)):
		if container.get_node(container.edge_rp_locals[_idx]) != self:
			continue
		if container.edge_rp_local_dirs[_idx] != PointInit.PRIOR:
			continue
		return container.edge_containers[_idx] != ^""
	if not self.terminated:
		push_warning("RP should have been present in container edge list (is_prior_connected)")
	return false


## Indicates whether this direction is connected, accounting for container connections
func is_next_connected() -> bool:
	if self.next_pt_init:
		return true
	# If no sibling point, could still have a cross-container connection
	for _idx in range(len(container.edge_rp_locals)):
		if container.get_node(container.edge_rp_locals[_idx]) != self:
			continue
		if container.edge_rp_local_dirs[_idx] != PointInit.NEXT:
			continue
		return container.edge_containers[_idx] != ^""
	if not self.terminated:
		push_warning("RP should have been present in container edge list (is_next_connected)")
	return false


## Returns prior RP direct reference, accounting for cross-container connections
func get_prior_rp():
	if self.prior_pt_init:
		return get_node(prior_pt_init)
	# If no sibling point, could still have a cross-container connection
	for _idx in range(len(container.edge_rp_locals)):
		if container.get_node(container.edge_rp_locals[_idx]) != self:
			continue
		if container.edge_rp_local_dirs[_idx] != PointInit.PRIOR:
			continue
		if not container.edge_containers[_idx]:
			return null
		var target_container = container.get_node(container.edge_containers[_idx])
		return target_container.get_node(container.edge_rp_targets[_idx])
	if not self.terminated:
		push_warning("RP should have been present in container edge list (get_prior_rp)")
	return null


## Returns prior RP direct reference, accounting for cross-container connections
func get_next_rp():
	if self.next_pt_init:
		return get_node(next_pt_init)
	# If no sibling point, could still have a cross-container connection
	for _idx in range(len(container.edge_rp_locals)):
		if container.get_node(container.edge_rp_locals[_idx]) != self:
			continue
		if container.edge_rp_local_dirs[_idx] != PointInit.NEXT:
			continue
		if not container.edge_containers[_idx]:
			return null
		var target_container = container.get_node(container.edge_containers[_idx])
		return target_container.get_node(container.edge_rp_targets[_idx])
	if not self.terminated:
		push_warning("RP should have been present in container edge list (get_next_rp)")
	return null


## Get the last RoadPoint in this direction, allowing for intermediate flipped directions
func get_last_rp(direction: int):
	var _next_itr_point = null
	var _prev_itr_point = null
	var first_loop := true
	while _next_itr_point != self:  # Exit cond for a full circle around
		if first_loop:
			first_loop = false
			# First iteration, should be deterministic which way to go
			if direction == PointInit.NEXT:
				if not self.next_pt_init:
					return self
				_next_itr_point = self.get_node_or_null(self.next_pt_init)
			else:
				if not self.prior_pt_init:
					return self
				_next_itr_point = self.get_node_or_null(self.prior_pt_init)
			if not is_instance_valid(_next_itr_point) or not _next_itr_point.has_method("is_road_point"):
				return self
			_prev_itr_point = self
			continue

		# Thereafter, just make sure the next selection != the last
		var this_tmp = _next_itr_point.get_node_or_null(_next_itr_point.next_pt_init)
		if this_tmp == null or not this_tmp.has_method("is_road_point"):
			# means it was the end of the line (as the other dir would be the prior iter)
			return _next_itr_point
		if this_tmp == _prev_itr_point:
			# Doubled back maybe due to flipped dir; Just try the other direction
			this_tmp = _next_itr_point.get_node_or_null(_next_itr_point.prior_pt_init)
		if this_tmp == null or not this_tmp.has_method("is_road_point"):
			# means it was the end of the line!
			return _next_itr_point
		if this_tmp == _prev_itr_point:
			# Infinite loop issue, shouldn't happen. Just return.
			return this_tmp
		_prev_itr_point = _next_itr_point
		_next_itr_point = this_tmp

	# failed to return early, must be a loop
	return self


# Goal is to assign the appropriate sequence of textures for this lane.
#
# This will intelligently construct the sequence of left-right textures, knowing
# where to apply middle vs outter vs inner lanes.
func assign_lanes():
	lanes.clear()
	if len(traffic_dir) == 1:
		lanes.append(LaneType.NO_MARKING)
		return

	var flips = [] # Track changes in direction between lanes.
	var only_fwd_rev = true # If false, a non supported complex scenario.
	var fwd_rev = [LaneDir.FORWARD, LaneDir.REVERSE]
	for i in range(len(traffic_dir)-1):
		if not traffic_dir[i] in fwd_rev:
			only_fwd_rev = false
			break
		if not traffic_dir[i+1] in fwd_rev:
			only_fwd_rev = false
			break
		var reversed = traffic_dir[i] != traffic_dir[i+1]
		flips.append(reversed)

	if only_fwd_rev:
		var running_same_dir = 0
		for i in range(len(traffic_dir) - 1): # One less, since not final edge
			if flips[i]: # The next lane to the right flips direction.
				if i == 0:
					lanes.append(LaneType.TWO_WAY) # Left side solid white
				elif running_same_dir == 0: # Left side solid yellow
					# No matching texture! Should be something would double
					# yellow lines on both sides. Mark as a "one way" for now.
					push_warning("No texture available for double-yellow on both sides of lane, using one-way")
					lanes.append(LaneType.ONE_WAY)
				else: # Left side is a dotted line.
					lanes.append(LaneType.FAST)
				running_same_dir = 0
			else: # Next lane is going the same direction.
				if i == 0:
					lanes.append(LaneType.SLOW) # Left side solid white
				elif running_same_dir == 0: # Left side yellow
					lanes.append(LaneType.FAST)
				else: # Left side is a dotted line.
					lanes.append(LaneType.MIDDLE)
				running_same_dir += 1

		# Now complete the final lane.
		if running_same_dir > 0:
			if running_same_dir == len(flips):
				#  Special texture case for the "inside" lane of a way one road
				if traffic_dir[-1] == LaneDir.FORWARD:
					lanes.append(LaneType.SLOW)
					lanes[0] = LaneType.NO_MARKING
				else:
					lanes.append(LaneType.NO_MARKING)
			else:
				lanes.append(LaneType.SLOW)
		else:
			lanes.append(LaneType.TWO_WAY)
	else:
		# Unable to handle situations that use NONE or BOTH lanes if more than
		# one lane is involved.
		push_warning("Unable to auto generate roads, using unmarked lanes")
		for i in range(len(traffic_dir)):
			if i == 0:
				lanes.append(LaneType.SINGLE_LINE)
			elif i == len(traffic_dir)-1:
				lanes.append(LaneType.SINGLE_LINE)
			else:
				lanes.append(LaneType.NO_MARKING)


## Returns the number of lanes in the Forward direction for the road point
##
## This function assumes Reverse lanes are always at the start of traffic_dir
## and Forward lanes at the end.
func get_fwd_lane_count() -> int:
	var td = traffic_dir
	var fwd_lane_count = 0

	for i in range(len(td) - 1, -1, -1):
		if td[i] == LaneDir.FORWARD:
			fwd_lane_count += 1
		if td[i] == LaneDir.REVERSE:
			break

	return fwd_lane_count


## Returns the number of lanes in the Reverse direction for the road point
##
## This function assumes Reverse lanes are always at the start of traffic_dir
## and Forward lanes at the end.
func get_rev_lane_count() -> int:
	var td = traffic_dir
	var rev_lane_count = 0

	for i in range(0, len(td)):
		if td[i] == LaneDir.REVERSE:
			rev_lane_count += 1
		if td[i] == LaneDir.FORWARD:
			break

	return rev_lane_count


func update_traffic_dir(traffic_update):
	var fwd_lane_count = get_fwd_lane_count()
	var rev_lane_count = get_rev_lane_count()
	var lane_count = fwd_lane_count + rev_lane_count

	# Add/remove lanes. But, always make sure at least one remains.
	match traffic_update:
		TrafficUpdate.ADD_FORWARD:
			traffic_dir.append(LaneDir.FORWARD)
		TrafficUpdate.ADD_REVERSE:
			traffic_dir.push_front(LaneDir.REVERSE)
		TrafficUpdate.REM_FORWARD:
			if lane_count > 1 and fwd_lane_count > 0:
				traffic_dir.pop_back()
		TrafficUpdate.REM_REVERSE:
			if lane_count > 1 and rev_lane_count > 0:
				traffic_dir.pop_front()
		TrafficUpdate.MOVE_DIVIDER_LEFT:
			pass
		TrafficUpdate.MOVE_DIVIDER_RIGHT:
			pass

	if not is_instance_valid(container):
		return  # Might not be initialized yet.
	emit_transform()


## Takes an existing RoadPoint and returns a new copy
func copy_settings_from(ref_road_point: RoadPoint, copy_transform: bool = true) -> void:
	var tmp_auto_lane = ref_road_point.auto_lanes
	auto_lanes = false
	lanes = ref_road_point.lanes.duplicate(true)
	traffic_dir = ref_road_point.traffic_dir.duplicate(true)
	auto_lanes = tmp_auto_lane
	lane_width = ref_road_point.lane_width
	shoulder_width_l = ref_road_point.shoulder_width_l
	shoulder_width_r = ref_road_point.shoulder_width_r
	gutter_profile.x = ref_road_point.gutter_profile.x
	gutter_profile.y = ref_road_point.gutter_profile.y
	create_geo = ref_road_point.create_geo
	_last_update_ms = ref_road_point._last_update_ms

	if copy_transform:
		prior_mag = ref_road_point.prior_mag
		next_mag = ref_road_point.next_mag
		global_transform = ref_road_point.global_transform


## Returns true if RoadPoint is primary selection in Scene panel
##
## input: of type EditorSelection, but cannot type as this class is not
##        available at time of export.
func is_road_point_selected(editor_selection) -> bool:
	var selected := false
	var sel_nodes = editor_selection.get_selected_nodes()
	if sel_nodes.size() == 1:
		if sel_nodes[0] == self:
			selected = true
	return selected


## Adds a numeric sequence to the end of a RoadPoint name
static func increment_name(name: String) -> String:
	# The original intent of this routine was to numerically increment node
	# names. But, it turned out that Godot already did a pretty good job of that
	# if a name ended in a number. So, this routine mainly makes sure that
	# names end in a number. We can use the same number over and over. Godot
	# will automatically increment the number if needed.
	var new_name = name
	if not new_name[-1].is_valid_int():
		new_name += "001"
	return new_name


## Adds a RoadPoint to SceneTree and transfers settings from another RoadPoint
func add_road_point(new_road_point: RoadPoint, direction):
	container.add_child(new_road_point, true)
	new_road_point.copy_settings_from(self)
	var basis_z = new_road_point.transform.basis.z

	new_road_point.name = increment_name(name)
	new_road_point.set_owner(get_tree().get_edited_scene_root())

	# Override the magnitude values, to better match the lane width.
	new_road_point.prior_mag = lane_width * len(lanes)
	new_road_point.next_mag = lane_width * len(lanes)

	var refresh = container._auto_refresh
	container._auto_refresh = false
	match direction:
		PointInit.NEXT:
			new_road_point.transform.origin += SEG_DIST_MULT * lane_width * basis_z
			new_road_point.prior_pt_init = new_road_point.get_path_to(self)
			next_pt_init = get_path_to(new_road_point)
		PointInit.PRIOR:
			new_road_point.transform.origin -= SEG_DIST_MULT * lane_width * basis_z
			new_road_point.next_pt_init = new_road_point.get_path_to(self)
			prior_pt_init = get_path_to(new_road_point)
	container._auto_refresh = refresh
	if not container._auto_refresh:
		container._needs_refresh = true


## Function to explicitly connect this RoadNode to another
##
## this_direction & target_direction: of type PointInit
## returns bool. True if success, and false on failure + a pushed error.
func connect_roadpoint(this_direction: int, target_rp: Node, target_direction: int) -> bool:
	if not target_rp.has_method("is_road_point"):
		push_error("Second input must be a valid RoadPoint")
		return false

	if self.container != target_rp.container:
		push_error("Wrong function: Connecting roadpoints from different RoadContainers should use connect_container")
		return false

	var local_path = get_path_to(target_rp)
	var target_path = target_rp.get_path_to(self)
	#print("Connecting %s (%s) and %s (%s)" % [self, this_direction, target_rp, target_direction])

	var refresh = container._auto_refresh
	container._auto_refresh = false

	# Skip the auto fix, so we can override both directions at once.
	self._is_internal_updating = true
	target_rp._is_internal_updating = true

	# Short circuit before setting any properties if we need to exit.
	match target_direction:
		PointInit.NEXT:
			if target_rp.next_pt_init:
				push_error("The connecting RP's next point is already set %s:%s" % [
					target_rp.name, target_rp.next_pt_init])
				return false # already connected
		PointInit.PRIOR:
			if target_rp.prior_pt_init:
				push_error("The connecting RP's prior point is already set: %s:%s" % [
					target_rp.name, target_rp.prior_pt_init])
				return false


	# Now do actual property setting
	match this_direction:
		PointInit.NEXT:
			if self.next_pt_init:
				push_error("This RP's next point is already set: %s:%s" % [
					self.name, self.next_pt_init])
				return false # already connected
			self.next_pt_init = local_path
		PointInit.PRIOR:
			if self.prior_pt_init:
				push_error("This RP's prior point is already set: %s:%s" % [
					self.name, self.prior_pt_init])
				return false # already connected
			self.prior_pt_init = local_path

	# Alreaedy short circuited prior connections for target
	match target_direction:
		PointInit.NEXT:
			target_rp.next_pt_init = target_path
		PointInit.PRIOR:
			target_rp.prior_pt_init = target_path

	container._auto_refresh = refresh
	if not container._auto_refresh:
		container._needs_refresh = true

	self._is_internal_updating = false
	target_rp._is_internal_updating = false

	container.update_edges()
	emit_transform()
	return true


## Function to explicitly connect this RoadNode to another
##
## Only meant to connect RoadPoints belonging to the same RoadContainer.
func disconnect_roadpoint(this_direction: int, target_direction: int) -> bool:
	#print("Disconnecting %s (%s) and the target's (%s)" % [self, this_direction, target_direction])
	var disconnect_from: Node

	self._is_internal_updating = true
	var seg

	match this_direction:
		PointInit.NEXT:
			if not next_pt_init:
				push_error("Failed to disconnect, not already connected to target RoadPoint in the Next direction")
				return false
			disconnect_from = get_node(next_pt_init)
			self.next_pt_init = ^""
			seg = self.next_seg
		PointInit.PRIOR:
			if not prior_pt_init:
				push_error("Failed to disconnect, not already connected to target RoadPoint in the Next direction")
				return false
			disconnect_from = get_node(prior_pt_init)
			self.prior_pt_init = ^""
			seg = self.prior_seg

	disconnect_from._is_internal_updating = true

	if self.container != disconnect_from.container:
		push_warning("Wrong function: Disconnecting roadpoints from different RoadContainers, should use disconnect_container")
		# already made some changes, so continue.

	match target_direction:
		PointInit.NEXT:
			disconnect_from.next_pt_init = ^""
		PointInit.PRIOR:
			disconnect_from.prior_pt_init = ^""
	self._is_internal_updating = false
	disconnect_from._is_internal_updating = false

	container.remove_segment(seg)

	self.validate_junctions()
	disconnect_from.validate_junctions()

	container.update_edges()
	return true


## Function to explicitly connect this RoadPoint to another container and corresponding RP.
##
## this_direction & target_direction: of type PointInit
## returns whether connection was a success, if false there will be an accompanying error pushed.
##
## This function will assign values to each of the 5 export vars used to identify
## cross-RoadContainer paths:
## - edge_containers
## - edge_rp_targets
## - edge_rp_target_dirs
## - edge_rp_locals -> Already set locally, for reading only
## - edge_rp_local_dirs -> Already set locally, for reading only
func connect_container(this_direction: int, target_rp: Node, target_direction: int) -> bool:
	if not target_rp.has_method("is_road_point"):
		push_error("Second input must be a valid RoadPoint")
		return false

	if self.container == target_rp.container:
		push_error("Wrong function: Connecting roadpoints from same RoadContainers, should use connect_roadpoint")
		return false

	# Identify which container edge this RP and target RP are.
	var target_ct = target_rp.container
	var this_idx = -1
	var target_idx = -1
	for idx in range(len(container.edge_rp_locals)):
		var _rp_local = container.edge_rp_locals[idx]
		var _rp_localdir = container.edge_rp_local_dirs[idx]
		if container.get_node(_rp_local) == self and _rp_localdir == this_direction:
			this_idx = idx
			break
	for idx in range(len(target_ct.edge_rp_locals)):
		var _rp_local = target_ct.edge_rp_locals[idx]
		var _rp_localdir = target_ct.edge_rp_local_dirs[idx]
		if target_ct.get_node(_rp_local) == target_rp and _rp_localdir == target_direction:
			target_idx = idx
			break

	if this_idx < 0:
		push_error("Local RP not at edge of RoadContainer: %s" % self.name)
		return false
	elif target_idx < 0:
		push_error("Target RP not at edge of RoadContainer: %s" % target_rp.name)
		return false

	# Update this container pointing to target rp
	container.edge_containers[this_idx] = container.get_path_to(target_ct)
	container.edge_rp_targets[this_idx] = target_ct.get_path_to(target_rp)
	container.edge_rp_target_dirs[this_idx] = target_direction

	# Update target container pointing to this rp
	target_ct.edge_containers[target_idx] = target_ct.get_path_to(container)
	target_ct.edge_rp_targets[target_idx] = container.get_path_to(self)
	target_ct.edge_rp_target_dirs[target_idx] = this_direction

	# Ensure that both RoadPoints have the same position and orientation
	# TODO: Should be able to deterministically specify which z direction is "correct",
	# instead of allowing both ways.
	var same_origin = self.global_transform.origin == target_rp.global_transform.origin
	var same_basis = self.global_transform.basis.z == target_rp.global_transform.basis.z
	var same_basis_rev = self.global_transform.basis.z*-1 == target_rp.global_transform.basis.z
	if not same_origin or not (same_basis or same_basis_rev):
		if is_instance_valid(container) and container._drag_init_transform:
			pass
		else:
			push_warning("Newly connected RoadPoints don't have the same position/orientation")

	# container.update_edges()
	emit_transform() # Only changes that should happen: Update connections of AI lanes.
	target_rp.emit_transform()
	return true


## Function to explicitly disconnect this edge RP from another edge RP
func disconnect_container(this_direction: int, target_direction: int) -> bool:

	# Identify which container edge this RP and target RP are.
	var this_idx = -1
	var target_idx = -1
	for idx in range(len(container.edge_rp_locals)):
		var _rp_local = container.edge_rp_locals[idx]
		var _rp_localdir = container.edge_rp_local_dirs[idx]
		if container.get_node(_rp_local) == self and _rp_localdir == this_direction:
			this_idx = idx
			break

	if this_idx < 0:
		push_error("RoadPoint not found to be an edge RoadPoint for its container, cannot disconnect")
		return false

	var target_ct_path = container.edge_containers[this_idx]
	var target_pt_path = container.edge_rp_targets[this_idx]

	var target_ct
	var target_pt

	if not target_ct_path:
		push_error("Failed to disconnect container, empty path to target container")
		return false
	elif not target_pt_path:
		push_error("Failed to disconnect container, empty path to target point")
		return false
	else:
		target_ct = container.get_node(target_ct_path)
		target_pt = target_ct.get_node(target_pt_path)
		for idx in range(len(target_ct.edge_rp_locals)):
			var _rp_local = target_ct.edge_rp_locals[idx]
			var _rp_localdir = target_ct.edge_rp_local_dirs[idx]
			if _rp_local == target_pt_path and _rp_localdir == target_direction:
				target_idx = idx
				break

	# Update this container pointing to target rp
	container.edge_containers[this_idx] = ^""
	container.edge_rp_targets[this_idx] = ^""
	container.edge_rp_target_dirs[this_idx] = -1

	# Update target container pointing to this rp
	if not target_ct:
		pass # alert would have already happened above
	elif this_idx < 0:
		push_error("Target RoadContainer did not indicate being connected to this RoadPoint/container")
		return false
	else:
		target_ct.edge_containers[target_idx] = ^""
		target_ct.edge_rp_targets[target_idx] = ^""
		target_ct.edge_rp_target_dirs[target_idx] = -1
		if target_pt and is_instance_valid(target_pt):
			target_pt.emit_transform()

	emit_transform() # Only changes that should happen: Update connections of AI lanes.
	return true


func _exit_tree():
	# Proactively disconnected any connected road segments, no longer valid.
	if is_instance_valid(prior_seg):
		prior_seg.queue_free()
	if is_instance_valid(next_seg):
		next_seg.queue_free()


## Evaluates THIS RoadPoint's prior/next_pt_inits and verifies that they
## describe a valid junction. A junction is valid if THIS RoadPoint agrees with
## what the associated RoadPoint is saying. Invalid junctions are cleared.
##
## Only meant to consider RoadPoints of the same RoadContainer.
func validate_junctions():
	var prior_point: RoadPoint
	var next_point: RoadPoint

	# Get valid Prior and Next RoadPoints for THIS RoadPoint
	var _tmp_ref
	if not prior_pt_init.is_empty():
		_tmp_ref = get_node(prior_pt_init)
		if is_instance_valid(_tmp_ref) and _tmp_ref.has_method("is_road_point"):
			prior_point = _tmp_ref
	if not next_pt_init.is_empty():
		_tmp_ref = get_node(next_pt_init)
		if is_instance_valid(_tmp_ref) and _tmp_ref.has_method("is_road_point"):
			next_point = get_node(next_pt_init)

	# Clear invalid junctions
	if is_instance_valid(prior_point):
		if not _is_junction_valid(prior_point):
			prior_pt_init = ^""
	if is_instance_valid(next_point):
		if not _is_junction_valid(next_point):
			next_pt_init = ^""


## Evaluates INPUT RoadPoint's prior/next_pt_inits.
##
## Returns true if at least one of them references THIS RoadPoint, or if both
## are empty. Otherwise, returns false.
func _is_junction_valid(point: RoadPoint)->bool:
	var prior_point: RoadPoint
	var next_point: RoadPoint

	# Get valid Prior and Next RoadPoints for INPUT RoadPoint
	if not point.prior_pt_init.is_empty():
		prior_point = get_node(point.prior_pt_init)
	if not point.next_pt_init.is_empty():
		next_point = get_node(point.next_pt_init)

	# Verify THIS RoadPoint is identified as Prior or Next
	if is_instance_valid(prior_point):
		if prior_point == self:
			return true
	if is_instance_valid(next_point):
		if next_point == self:
			return true
	return false


## If one RoadPoint references the other, but not the other way around,
## but itself has an empty slot in the right "orientation", then we assume
## that the user is manually connecting these two points, and we should finish
## the reference by making the reference bidirectional.
##
## Args:
##   old_point_path: The currently connected RoadPoint (as a NodePath)
##   new_point_path: The to-be connected RoadPoint (as a NodePath)
##   for_prior: If true, indicates the new+old are both the prior_pt_init for
##     self; if false, then presume these are both the next_pt_init.
##
## Returns true if any updates made, false if nothing changed.
func _autofix_noncyclic_references(
		old_point_path: NodePath,
		new_point_path: NodePath,
		for_prior: bool) -> void:
	if _is_internal_updating:
		return
	var init_refresh = container._auto_refresh
	var point:RoadPoint
	var is_clearing: bool # clearing value vs setting new path.

	#var which_init = "prior_pt_init" if for_prior else "next_pt_init"
	#print("autofix %s.%s: %s -> %s" % [self.name, which_init, old_point_path, new_point_path])

	if old_point_path.is_empty() and new_point_path.is_empty():
		return
	elif old_point_path == new_point_path:
		return

	if not new_point_path.is_empty():
		# Use the just recently set value.
		is_clearing = false
		var connection = get_node(new_point_path)
		if connection.has_method("is_road_container"):
			return # Nothing further to update now.
		else:
			point = connection
	else:
		# we are in clearing mode, so use the value that was just overwritten
		is_clearing = true
		var connection = get_node(old_point_path)
		if connection.has_method("is_road_container"):
			return # Nothing further to update now.
		point = connection

	if not is_instance_valid(point):
		# Shouldn't get to this branch, we check valid upstream first!
		push_warning("Instance not valid on point for cyclic check")
		return

	container._auto_refresh = false
	self._is_internal_updating = true

	if is_clearing:
		# Scenario where the user is attempting to CLEAR the _pt_init
		# Therefore, we want to clear the new path instead.
		# Key detail: this new point_path value has *not* yet been assigned,
		# so we can still read self.next_pt_init
		var seg  # RoadSegment.
		if for_prior:
			point.next_pt_init = ^""
			seg = self.prior_seg
		else:
			point.prior_pt_init = ^""
			seg = self.next_seg
		container.remove_segment(seg)
	elif for_prior and not point.next_pt_init.is_empty():
		# self's prior RP is `point`, so make point's next RP be self if slot was empty
		point.next_pt_init = point.get_path_to(self)
		#print_debug(point.get_path_to(self), " -> ", point.next_pt_init)
	elif not for_prior and point.prior_pt_init.is_empty():
		# Flipped scenario
		point.prior_pt_init = point.get_path_to(self)
		#print_debug(point.get_path_to(self), " -> ", point.prior_pt_init)
	else:
		if container and is_instance_valid(container) and container.debug:
			print_debug("Cannot auto-fix cyclic reference")

	# This would ordinarily actually trigger a full rebuild, which
	# would not be great, as this sets the dirty flag for rebuilding all.
	# Hacky solution: by setting to false the dirty flag and unsetting, we skip
	# the internal call_deferred to rebuild. But not good to depend on this,
	# sine the implementation could change technically.
	# TODO: Implement better solution not depending on self-internals.
	container._dirty = true
	container._auto_refresh = init_refresh
	container._dirty = false
	self._is_internal_updating = false

	# In the event of change in edges, update all references.
	container.update_edges()
