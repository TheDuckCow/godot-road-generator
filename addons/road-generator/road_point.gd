## Definition for a single point handle, which 2+ road segments connect to.
tool
class_name RoadPoint, "road_point.png"
extends Spatial

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

const UI_TIMEOUT = 50 # Time in ms to delay further refrehs updates.
const COLOR_YELLOW = Color(0.7, 0.7, 0,7)
const COLOR_RED = Color(0.7, 0.3, 0.3)

# Assign both the texture to use, as well as the path direction to generate.
# Order is left to right when oriented such that the RoadPoint is facing towards
# the top of the screen in a top down orientation.
export(Array, LaneType) var lanes:Array = [
	LaneType.SLOW, LaneType.FAST, LaneType.FAST, LaneType.SLOW
	] setget _set_lanes, _get_lanes
# Enables auto assignment of the lanes array above, subverting manual assignment.
export(bool) var auto_lanes := true setget _set_auto_lanes, _get_auto_lanes
export(Array, LaneDir) var traffic_dir:Array = [
	LaneDir.REVERSE, LaneDir.REVERSE, LaneDir.FORWARD, LaneDir.FORWARD
	] setget _set_dir, _get_dir

export var lane_width := 4.0 setget _set_lane_width, _get_lane_width
export var shoulder_width_l := 2 setget _set_shoulder_width_l, _get_shoulder_width_l
export var shoulder_width_r := 2 setget _set_shoulder_width_r, _get_shoulder_width_r
# Profile: x: how far out the gutter goes, y: how far down to clip.
export(Vector2) var gutter_profile := Vector2(0.5, -0.5) setget _set_profile, _get_profile
export(NodePath) var prior_pt_init setget _set_prior_pt, _get_prior_pt
export(NodePath) var next_pt_init setget _set_next_pt, _get_next_pt
# Handle magniture
export(float) var prior_mag := 5.0 setget _set_prior_mag, _get_prior_mag
export(float) var next_mag := 5.0 setget _set_next_mag, _get_next_mag

# Ultimate assignment if any export path specified
#var prior_pt:Spatial # Road Point or Junction
var prior_seg
#var next_pt:Spatial # Road Point or Junction
var next_seg

var network # The managing network node for this road segment (grandparent).
var geom:ImmediateGeometry # For tool usage, drawing lane directions and end points
#var refresh_geom := true

var _last_update_ms # To calculate min updates.


func _ready():
	# Ensure the transform notificaitons work
	set_notify_transform(true)
	set_notify_local_transform(true)
	#set_ignore_transform_notification(false)
	
	if not network:
		network = get_parent().get_parent()
	
	connect("on_transform", network, "on_point_update")


func _to_string():
	var parname
	if self.get_parent():
		parname = self.get_parent()
	else:
		parname = "[not in scene]"
	return "RoadPoint of [%s] at %s between [%s]:[%s]" % [
		parname,  self.translation, prior_pt_init, next_pt_init]

# ------------------------------------------------------------------------------
# Editor visualizing
# ------------------------------------------------------------------------------

func _set_lanes(values):
	lanes = values
	if not is_instance_valid(network):
		return  # Might not be initialized yet.
	rebuild_geom()
	on_transform()
func _get_lanes():
	return lanes


func _set_auto_lanes(value):
	auto_lanes = value
	if not is_instance_valid(network):
		return  # Might not be initialized yet.
	rebuild_geom()
	on_transform()
func _get_auto_lanes():
	return auto_lanes


func _set_dir(values):
	traffic_dir = values
	if not is_instance_valid(network):
		return  # Might not be initialized yet.
	rebuild_geom()
	on_transform()
func _get_dir():
	return traffic_dir


func _set_lane_width(value):
	lane_width = value
	if not is_instance_valid(network):
		return  # Might not be initialized yet.
	rebuild_geom()
	on_transform()
func _get_lane_width():
	return lane_width


func _set_shoulder_width_l(value):
	shoulder_width_l = value
	if not is_instance_valid(network):
		return  # Might not be initialized yet.
	rebuild_geom()
	on_transform()
func _get_shoulder_width_l():
	return shoulder_width_l


func _set_shoulder_width_r(value):
	shoulder_width_r = value
	if not is_instance_valid(network):
		return  # Might not be initialized yet.
	rebuild_geom()
	on_transform()
func _get_shoulder_width_r():
	return shoulder_width_r


func _set_profile(value:Vector2):
	gutter_profile = value
	if not is_instance_valid(network):
		return  # Might not be initialized yet.
	rebuild_geom()
	on_transform()
func _get_profile():
	return gutter_profile
	

func _set_prior_pt(value):
	prior_pt_init = value
	if not is_instance_valid(network):
		return  # Might not be initialized yet.
	rebuild_geom()
	on_transform()
func _get_prior_pt():
	return prior_pt_init


func _set_next_pt(value):
	next_pt_init = value
	if not is_instance_valid(network):
		return  # Might not be initialized yet.
	rebuild_geom()
	on_transform()
func _get_next_pt():
	return next_pt_init


func _set_prior_mag(value):
	prior_mag = value
	if not is_instance_valid(network):
		return  # Might not be initialized yet.
	rebuild_geom()
	_notification(Spatial.NOTIFICATION_TRANSFORM_CHANGED)
func _get_prior_mag():
	return prior_mag


func _set_next_mag(value):
	next_mag = value
	if not is_instance_valid(network):
		return  # Might not be initialized yet.
	rebuild_geom()
	_notification(Spatial.NOTIFICATION_TRANSFORM_CHANGED)
func _get_next_mag():
	return next_mag


# ------------------------------------------------------------------------------
# Editor interactions
# ------------------------------------------------------------------------------

func _notification(what):
	if not is_instance_valid(network):
		return  # Might not be initialized yet.
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		var low_poly = Input.is_mouse_button_pressed(BUTTON_LEFT) and Engine.is_editor_hint()
		on_transform(low_poly)


func on_transform(low_poly=false):
	if auto_lanes:
		assign_lanes()
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
	rebuild_geom()
	on_transform()


# ------------------------------------------------------------------------------
# Gizmo handling and drawing.
# ------------------------------------------------------------------------------


func show_gizmo():
	rebuild_geom()


func hide_gizmo():
	geom.clear()
	

func rebuild_geom():
	# if refresh_geom:
	call_deferred("_instantiate_geom")


func _instantiate_geom():
	if not Engine.is_editor_hint():
		if geom:
			geom.clear()
		return
	
	if geom == null:
		geom = ImmediateGeometry.new()
		geom.set_name("geom")
		add_child(geom)
		
		var mat = SpatialMaterial.new()
		mat.flags_unshaded = true
		mat.flags_do_not_receive_shadows = true
		mat.params_cull_mode = mat.CULL_DISABLED
		mat.vertex_color_use_as_albedo = true
		geom.material_override = mat
	else:
		geom.clear()
	
	_draw_lane_width()



func _draw_lane_width():
	var offy = Vector3(0, 0.05, 0)
	var half_width = lanes.size() * lane_width / 2.0
	geom.begin(Mesh.PRIMITIVE_TRIANGLES)
	geom.set_color(COLOR_YELLOW)
	geom.add_vertex(Vector3(-half_width, 0, 0) + offy)
	geom.add_vertex(Vector3(0, 0, 0.5) + offy)
	geom.add_vertex(Vector3(half_width, 0, 0) + offy)
	geom.set_color(COLOR_RED)
	# Top triangle
	geom.add_vertex(Vector3(-half_width, 0, -0.5) + offy)
	geom.add_vertex(Vector3(half_width, 0, -0.5) + offy)
	geom.add_vertex(Vector3(half_width, 0, 0) + offy)
	# Bottom triangle
	geom.add_vertex(Vector3(half_width, 0, 0) + offy)
	geom.add_vertex(Vector3(-half_width, 0, 0) + offy)
	geom.add_vertex(Vector3(-half_width, 0, -0.5) + offy)
	
	geom.end()
