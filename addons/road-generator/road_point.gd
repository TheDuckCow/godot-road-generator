## Definition for a single point handle, which 2+ road segments connect to.
@tool
# class_name RoadPoint, "road_point.png"
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


enum PointInit {
	NEXT,
	PRIOR,
}

const UI_TIMEOUT = 50 # Time in ms to delay further refresh updates.
const COLOR_YELLOW = Color(0.7, 0.7, 0,7)
const COLOR_RED = Color(0.7, 0.3, 0.3)
const SEG_DIST_MULT: float = 8.0 # How many road widths apart to add next RoadPoint.

# Assign the direction of traffic order.
var _traffic_dir: Array[LaneDir] = [
		LaneDir.REVERSE, LaneDir.REVERSE, LaneDir.FORWARD, LaneDir.FORWARD]
@export var traffic_dir:Array[LaneDir] = [
		LaneDir.REVERSE, LaneDir.REVERSE, LaneDir.FORWARD, LaneDir.FORWARD]:
	get:
		return _traffic_dir
	set(value):
		_traffic_dir = value
		_notify_network_on_set(value)

# Enables auto assignment of the lanes array below, based on traffic_dir setup.
var _auto_lanes: bool = true
@export var auto_lanes: bool = true:
	get:
		return _auto_lanes
	set(value):
		_auto_lanes = value
		_notify_network_on_set(value)

# Assign the textures to use for each lane.
# Order is left to right when oriented such that the RoadPoint is facing towards
# the top of the screen in a top down orientation.
var _lanes: Array[LaneType] = [LaneType.SLOW, LaneType.FAST, LaneType.FAST, LaneType.SLOW]
@export var lanes:Array[LaneType] = [LaneType.SLOW, LaneType.FAST, LaneType.FAST, LaneType.SLOW]:
	get:
		return _lanes
	set(value):
		_lanes = value
		_notify_network_on_set(value)

var _lane_width: float = 4.0
@export var lane_width := 4.0:
	get:
		return _lane_width
	set(value):
		_lane_width = value
		_notify_network_on_set(value)

var _shoulder_width_l: float = 2
@export var shoulder_width_l := 2:
	get:
		return _shoulder_width_l
	set(value):
		_shoulder_width_l = value
		_notify_network_on_set(value)

var _shoulder_width_r: float = 2
@export var shoulder_width_r := 2:
	get:
		return _shoulder_width_r
	set(value):
		_shoulder_width_r = value
		_notify_network_on_set(value)

# Profile: x: how far out the gutter goes, y: how far down to clip.
var _gutter_profile: Vector2 = Vector2(0.5, -0.5)
@export var gutter_profile: Vector2 = Vector2(0.5, -0.5):
	get:
		return _gutter_profile
	set(value):
		_gutter_profile = value
		_notify_network_on_set(value)

var _prior_pt_init: NodePath
@export var prior_pt_init: NodePath:
	get:
		return _prior_pt_init
	set(value):
		_prior_pt_init = value
		_notify_network_on_set(value)

var _next_pt_init: NodePath
@export var next_pt_init: NodePath:
	get:
		return _next_pt_init
	set(value):
		_next_pt_init = value
		_notify_network_on_set(value)

# Handle magniture
var _prior_mag: float = 5.0
@export var prior_mag: float = 5.0:
	get:
		return _prior_mag
	set(value):
		_prior_mag = value
		if not is_instance_valid(network):
			return  # Might not be initialized yet.
		_notification(Node3D.NOTIFICATION_TRANSFORM_CHANGED)

var _next_mag: float = 5.0
@export var next_mag: float = 5.0:
	get:
		return _next_mag
	set(value):
		_next_mag = value
		if not is_instance_valid(network):
			return  # Might not be initialized yet.
		_notification(Node3D.NOTIFICATION_TRANSFORM_CHANGED)

var rev_width_mag := -8.0
var fwd_width_mag := 8.0
# Ultimate assignment if any export path specified
#var prior_pt:Node3D # Road Point or Junction
var prior_seg
#var next_pt:Node3D # Road Point or Junction
var next_seg

var network # The managing network node for this road segment (grandparent).
var geom:ImmediateMesh # For tool usage, drawing lane directions and end points
#var refresh_geom := true

var _last_update_ms # To calculate min updates.


func _ready():
	# Ensure the transform notificaitons work
	set_notify_transform(true)
	set_notify_local_transform(true)
	#set_ignore_transform_notification(false)

	if not network:
		network = get_parent().get_parent()

	connect("on_transform", Callable(network,"on_point_update"))


func _to_string():
	var parname
	if self.get_parent():
		parname = self.get_parent()
	else:
		parname = "[not in scene]"
	return "RoadPoint of [%s] at %s between [%s]:[%s]" % [
		parname,  self.position, prior_pt_init, next_pt_init]

# ------------------------------------------------------------------------------
# Editor visualizing
# ------------------------------------------------------------------------------

func _notify_network_on_set(_value):
	if is_instance_valid(network):
		emit_on_transform()


# ------------------------------------------------------------------------------
# Editor interactions
# ------------------------------------------------------------------------------

func _notification(what):
	if not is_instance_valid(network):
		return  # Might not be initialized yet.
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		var low_poly = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Engine.is_editor_hint()
		emit_on_transform(low_poly)


func emit_on_transform(low_poly=false):
	if auto_lanes:
		assign_lanes()
	# TODO: Fix refefnce. GD4 says gizmo is unknown, and tbh, not sure how GD3 did know what it was.
	#if is_instance_valid(gizmo):
	#	gizmo.get_plugin().refresh_gizmo(gizmo)
	emit_signal("on_transform", self, low_poly)


# ------------------------------------------------------------------------------
# Utilities
# ------------------------------------------------------------------------------

# Goal is to assign the appropriate sequence of textures for this lane.
#
# This will intelligently construct the sequence of left-right textures, knowing
# where to apply middle vs outter vs inner lanes.
func assign_lanes():
	lanes.clear()
	if len(traffic_dir) == 1:
		if traffic_dir[0] == LaneDir.NONE:
			lanes.append(LaneType.NO_MARKING)
		else:
			# Direction doesn't matter, since there is only a single lane here.
			lanes.append(LaneType.ONE_WAY)
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

	if not is_instance_valid(network):
		return  # Might not be initialized yet.
	emit_on_transform()


## Takes an existing RoadPoint and returns a new copy
func copy_settings_from(ref_road_point: RoadPoint) -> void:
	auto_lanes = false
	lanes = ref_road_point.lanes.duplicate(true)
	traffic_dir = ref_road_point.traffic_dir.duplicate(true)
	auto_lanes = ref_road_point.auto_lanes
	lane_width = ref_road_point.lane_width
	shoulder_width_l = ref_road_point.shoulder_width_l
	shoulder_width_r = ref_road_point.shoulder_width_r
	gutter_profile.x = ref_road_point.gutter_profile.x
	gutter_profile.y = ref_road_point.gutter_profile.y
	prior_mag = ref_road_point.prior_mag
	next_mag = ref_road_point.next_mag
	global_transform = ref_road_point.global_transform
	_last_update_ms = ref_road_point._last_update_ms


## Returns true if RoadPoint is primary selection in Scene panel
func is_road_point_selected(editor_selection: EditorSelection) -> bool:
	var selected := false
	var sel_nodes = editor_selection.get_selected_nodes()
	if sel_nodes.size() == 1:
		if sel_nodes[0] == self:
			selected = true
	return selected


## Adds a numeric sequence to the end of a RoadPoint name
func increment_name(name: String) -> String:
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
func add_road_point(new_road_point: RoadPoint, pt_init):
	var points = get_parent()
	points.add_child(new_road_point, true)
	new_road_point.copy_settings_from(self)
	var basis_z = new_road_point.transform.basis.z

	new_road_point.name = increment_name(name)
	new_road_point.owner = points.owner

	match pt_init:
		PointInit.NEXT:
			new_road_point.transform.origin += SEG_DIST_MULT * lane_width * basis_z
			new_road_point.prior_pt_init = new_road_point.get_path_to(self)
			next_pt_init = get_path_to(new_road_point)
		PointInit.PRIOR:
			new_road_point.transform.origin -= SEG_DIST_MULT * lane_width * basis_z
			new_road_point.next_pt_init = new_road_point.get_path_to(self)
			prior_pt_init = get_path_to(new_road_point)


func _exit_tree():
	# Proactively disconnected any connected road segments, no longer valid.
	if is_instance_valid(prior_seg):
		prior_seg.queue_free()
	if is_instance_valid(next_seg):
		next_seg.queue_free()

	# Clean up references to this RoadPoint to anything connected to it.
	for rp_init in [prior_pt_init, next_pt_init]:
		if rp_init.is_empty() or not is_instance_valid(get_node(rp_init)):
			continue
		var rp_ref = get_node(rp_init)

		# Clean up the right connection, could be either or both prior and next
		# (think: circle with just two roadpoints)
		for singling_rp_ref in [rp_ref.prior_pt_init, rp_ref.next_pt_init]:
			if not singling_rp_ref:
				continue
			if singling_rp_ref != rp_ref.get_path_to(self):
				pass
			singling_rp_ref = null
