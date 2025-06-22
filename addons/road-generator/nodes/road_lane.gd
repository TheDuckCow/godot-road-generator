@tool
@icon("res://addons/road-generator/resources/road_lane.png")
class_name RoadLane
extends Path3D
## Defines a directional lane of traffic for AI with references to adjacent lanes.
##
## These are generated as children of [RoadPoint]'s automatically if its given
## [member RoadContainer.generate_ai_lanes] is set to true.
##
## @tutorial(Using RoadLanes with custom meshes): https://github.com/TheDuckCow/godot-road-generator/wiki/User-guide:-Custom-road-meshes
## @tutorial(Procedural demo with agents): https://github.com/TheDuckCow/godot-road-generator/tree/main/demo/procedural_generator

# ------------------------------------------------------------------------------
#region Signals/Enums/Const
# ------------------------------------------------------------------------------


signal on_transform

const COLOR_PRIMARY := Color(0.6, 0.3, 0,3)
const COLOR_START := Color(0.7, 0.7, 0,7)

class Obstacle:
	var lane: RoadLane
	var offset: float
	var node: Node3D


	## RoadLaneAgent will only use following if agent/actor find it on a position above
	## they shouldn't be too far from original lane_offset, but could overflow to another lane
	## offsets to the front and back - in positive direction of lane of the obstacle (meters)
	## as obstacles shouldn't be at the same point of the lane, zero offsets may be problematic
	var end_offsets: Array[float] = [0.0, 0.0]
	const END_OFFSET_MAX = 5.0

	## approximate speed an obstacle on lane (m/s)
	## for example if actor moves with an angle from tagent, its obstacle's speed
	## should be just a fraction (dependent on the angle) of actor's speed
	## Note: the obstacle won't be moved along lane automatically
	var speed: float

	static func compare_offset(a1: RoadLane.Obstacle, a2: RoadLane.Obstacle) -> bool:
		return a1.offset < a2.offset

	func distance_to_end(dir: RoadLane.MoveDir) -> float:
		assert(check_valid())
		return self.lane.offset_from_end(self.offset, dir)

	func check_valid() -> bool:
		var all_good = true
		if !is_instance_valid(self.node):
			print(self, " has invalid node ", self.node)
			all_good = false
		for dir in MoveDir.values():
			if self.end_offsets[dir] < 0:
				print(self, " negative ", MoveDir.find_key(dir), " end offset ", self.end_offsets[dir])
				all_good = false
			elif self.end_offsets[dir] > END_OFFSET_MAX:
				print(self, " too big ", MoveDir.find_key(dir), " end offset ", self.end_offsets[dir])
				all_good = false
		if !is_instance_valid(self.lane):
			print(self, " has invalid lane ", self.lane)
			all_good = false
		else:
			if self not in self.lane.obstacles:
				print(self, " is not registered in ", self.lane)
				all_good = false
			if self.offset < 0:
				print(self, " has negative offset ", self.offset)
				all_good = false
			elif self.offset > self.lane.curve.get_baked_length():
				print(self, " has too big offset ", self.offset, " - lane's length is ", self.lane.curve.get_baked_length())
				all_good = false
		return all_good


enum MoveDir
{
	FORWARD,
	BACKWARD,
}
static func reverse_move_dir(dir: MoveDir) -> MoveDir:
	return 1 - dir

enum SideDir
{
	RIGHT,
	LEFT,
}
static func other_side(side: SideDir) -> SideDir:
	return 1 - side


# ------------------------------------------------------------------------------
#endregion
#region Export vars
# ------------------------------------------------------------------------------

# -------------------------------------
@export_group("Connections")
# -------------------------------------


var side_lanes : Array[NodePath] = ["", ""]
## Reference to the next left-side [RoadLane] if any, for allowed lane transitions.
@export var lane_left: NodePath:
	get: return side_lanes[SideDir.LEFT]
	set(val): assert(get_node_or_null(val) != self); side_lanes[SideDir.LEFT] = val
## Reference to the next right-side [RoadLane] if any, for allowed lane transitions.
@export var lane_right: NodePath:
	get: return side_lanes[SideDir.RIGHT]
	set(val): assert(get_node_or_null(val) != self); side_lanes[SideDir.RIGHT] = val


var sequential_lanes: Array[NodePath] = ["", ""]
## The next forward [RoadLane] for agents to follow along.
@export var lane_next: NodePath:
	get: return sequential_lanes[MoveDir.FORWARD]
	set(val): assert(get_node_or_null(val) != self); sequential_lanes[MoveDir.FORWARD] = val
## The prior [RoadLane] for agents to follow (if going backwards).
@export var lane_prior: NodePath:
	get: return sequential_lanes[MoveDir.BACKWARD]
	set(val): assert(get_node_or_null(val) != self); sequential_lanes[MoveDir.BACKWARD] = val

## Tags are used help populate the lane_next and lane_prior NodePaths above.[br][br]
##
## Given two segments (seg_A followed by seg_B), a lane_A of seg_A will be auto
## matched to lane_B of seg_B if lane_A's lane_next_tag is the same as lane_B's
## lane_prior_tag (since lane_B follows lane_A in this situation).[br][br]
##
## Any matching name will do, and it will match the first match. Auto-generated
## lanes have a convention of a prefix F or R (for forward or reverse lane,
## relative to the road segment) followed by a 0-indexed integer, based on how
## far from the middle of the road (middle = where the lane direction flips).[br][br]
##
## This way, the inner most lanes are always matched together. A lane F2 being
## removed on the right (forward) will be recognized as needing to have it's
## lane_next_tag set to F1, representing cars merging from this removed lane into
## the next interior lane.[br][br]
##
## e.g. R0, R1,...R#, F0, F1, ... F#.
var sequential_lane_tags: Array[String] = ["", ""]
@export var lane_next_tag: String:
	get: return sequential_lane_tags[MoveDir.FORWARD]
	set(val): sequential_lane_tags[MoveDir.FORWARD] = val
## See description above for [member RoadLane.lane_next_tag] which is the equivalent.
@export var lane_prior_tag: String:
	get: return sequential_lane_tags[MoveDir.BACKWARD]
	set(val): sequential_lane_tags[MoveDir.BACKWARD] = val

# -------------------------------------
@export_group("Behavior")
# -------------------------------------

## Visualize this [RoadLane] and its direction in the editor directly.
@export var draw_in_game = false: get = _get_draw_in_game, set = _set_draw_in_game
## Visualize this [RoadLane] and its direction during the game runtime.
@export var draw_in_editor = false: get = _get_draw_in_editor, set = _set_draw_in_editor

## Auto queue-free any vehicles registered to this lane with the road lane exits.
@export var auto_free_vehicles: bool = false


# -------------------------------------
@export_group("Editor tools")
# -------------------------------------


# TODO: remove when moved to Godot 4.4 and changed to simple button
# the variable is not used - only to provide GUI element
## UI tool to easily flip the order of points of the curve.[br][br]
##
## Property will remain unchecked but will perform the action described. Will be
## replaced with a tool button once this addon targets Godot 4.4 as the minimum.
@export var reverse_direction = false: set = _set_reverse_direction


var this_road_segment = null # RoadSegment
var refresh_geom = true
var geom:ImmediateMesh # For tool usage, drawing lane directions and end points
var geom_node: MeshInstance3D
# Internal field used by agents for intra-segment lane changes
var transition: bool = false

# this container should contain obstacles in order:
# from beginning to the end, i.e. agents' lower offset to higher offset
# also offsets are expected but not enforced to be unique
var obstacles: Array[RoadLane.Obstacle] = [] # Registration

var _draw_in_game: bool = false
var _draw_in_editor: bool = false
var _draw_override: bool = false
var _display_fins: bool = false

const DEBUG_OUT := false


# ------------------------------------------------------------------------------
#endregion
#region Setup and builtin overrides
# ------------------------------------------------------------------------------


func _init():
	if not is_instance_valid(curve):
		curve = Curve3D.new()


func _ready():
	set_notify_transform(true)
	set_notify_local_transform(true)
	connect("curve_changed", Callable(self, "curve_changed"))
	rebuild_geom()
	#_instantiate_geom()


func _exit_tree() -> void:
	if auto_free_vehicles:
		for _vehicle in _vehicles_in_lane:
			if is_instance_valid(_vehicle):
				_vehicle.call_deferred("queue_free")


# ------------------------------------------------------------------------------
#endregion
#region Functions
# ------------------------------------------------------------------------------


#TODO: remove when moved to Godot 4.4 and changed to simple button
func _set_reverse_direction(value: bool) -> void:
	on_reverse_lane()


## Reverse geometry of lane curve
func on_reverse_lane() -> void:
	var reversed_curve = Curve3D.new()
	for i in range(self.curve.point_count - 1, -1, -1):
		var pos = self.curve.get_point_position(i)
		var in_tangent = self.curve.get_point_in(i)
		var out_tangent = self.curve.get_point_out(i)
		reversed_curve.add_point(pos, out_tangent, in_tangent)
	self.curve = reversed_curve
	refresh_geom = true
	rebuild_geom()


func get_lane_start() -> Vector3:
	return to_global(curve.get_point_position(0))


func get_lane_end() -> Vector3:
	return to_global(curve.get_point_position(curve.get_point_count()-1))


func is_obstacle_list_correct() -> bool:
	var all_good := true
	if RoadLane.Obstacle.END_OFFSET_MAX > self.curve.get_baked_length():
		print(self, " is shorter than maximum obstacle end offset")
		return false
	for obstacle in self.obstacles:
		if not is_instance_valid(obstacle):
			print("invalid obstacle ", obstacle, " on lane ", self)
			return false
		if obstacle.is_queued_for_deletion():
			print("obstacle ", obstacle, " on lane ", self, " is queued to be freed")
			all_good = false
		if obstacle.lane != self:
			print("on lane ", self, " wrong lane (", obstacle.lane, ") assigned to ", obstacle)
			all_good = false
		if ! obstacle.check_valid():
			all_good = false
	for i in range(self.obstacles.size() - 1):
		var prior_obst := obstacles[i]
		var next_obst := obstacles[i +1]
		if prior_obst.offset >= next_obst.offset:
			print("on lane ", self, " offset ", prior_obst.offset, " (prior ", prior_obst,") >= ",  next_obst.offset, " (next ", next_obst, ")")
			all_good = false
		var prior_forward_end := prior_obst.offset + prior_obst.end_offsets[MoveDir.FORWARD]
		var back_backward_end := next_obst.offset + next_obst.end_offsets[MoveDir.BACKWARD]
		if prior_forward_end >= back_backward_end:
			print("on lane ", self, " forward end ", prior_forward_end, " (prior ", prior_obst, ") overlaps with backward end ", back_backward_end, " (next ", next_obst, ")" )
			all_good = false
	#TODO check sequential lanes for intersections?
	return all_good


func find_obstable_index(agent: RoadLane.Obstacle, before: bool) -> int:
	assert(self.is_obstacle_list_correct())
	var idx = self.obstacles.bsearch_custom(agent, RoadLane.Obstacle.compare_offset, before)
	return idx


func get_sequential_lane(dir : MoveDir) -> RoadLane:
	var lane: RoadLane = get_node_or_null(self.sequential_lanes[dir])
	assert(lane != self)
	return lane

func get_side_lane(dir : SideDir) -> RoadLane:
	var lane: RoadLane = get_node_or_null(self.side_lanes[dir])
	assert(lane != self)
	return lane


## Register a agent to be connected to (on, following) this lane.
func register_obstacle(obstacle: RoadLane.Obstacle) -> void:
	if DEBUG_OUT:
		print("Registering ", obstacle, " on lane ", self, " with lanes connected FORWARD ", self.get_sequential_lane(MoveDir.FORWARD), " and BACKWARD ", self.get_sequential_lane(MoveDir.BACKWARD))
	assert(self.is_obstacle_list_correct())
	assert(obstacle not in obstacles)
	var idx = find_obstable_index(obstacle, false)
	assert(idx == obstacles.size() || obstacles[idx].offset > obstacle.offset)
	assert(idx == 0 || obstacles[idx -1].offset < obstacle.offset)
	obstacles.insert(idx, obstacle)
	assert(self.is_obstacle_list_correct())


## Optional but good cleanup of references.
func unregister_obstacle(obstacle: RoadLane.Obstacle) -> void:
	if DEBUG_OUT:
		print("Unregistering ", obstacle, " from lane ", self)
	assert( obstacle in obstacles )
	obstacles.erase(obstacle)


func get_lane_end_point_by_dir(dir: MoveDir) -> Vector3:
	assert(dir in MoveDir.values())
	return get_lane_start() if dir == MoveDir.FORWARD else get_lane_end()


func offset_from_end(distance: float, dir: RoadLane.MoveDir) -> float:
	assert(distance >= 0 && distance <= self.curve.get_baked_length())
	return (self.curve.get_baked_length() - distance) if dir == MoveDir.FORWARD else distance


func _instantiate_geom() -> void:
	if Engine.is_editor_hint():
		_display_fins = _draw_in_editor or _draw_override
	else:
		_display_fins = _draw_in_game or _draw_override

	if not _display_fins:
		if geom:
			geom.clear_surfaces()
		return
	if refresh_geom == false:
		return
	refresh_geom = false

	# Setup immediate geo node if not already.
	if geom == null:
		geom = ImmediateMesh.new()
		geom.set_name("geom")
		if not is_instance_valid(geom_node):
			geom_node = MeshInstance3D.new()
			geom_node.mesh = geom
			add_child(geom_node)
		else:
			geom_node.mesh = geom

		var mat = StandardMaterial3D.new()
		mat.flags_unshaded = true
		mat.flags_disable_ambient_light = true
		mat.params_depth_draw_mode = StandardMaterial3D.DEPTH_DRAW_DISABLED
		mat.flags_do_not_receive_shadows = true
		mat.flags_no_depth_test = true
		mat.flags_do_not_receive_shadows = true
		mat.params_cull_mode = mat.CULL_DISABLED
		mat.vertex_color_use_as_albedo = true
		geom_node.material_override = mat

	_draw_shark_fins()


## Generate the triangles along the path, indicating lane direction.
func _draw_shark_fins() -> void:
	var curve_length = curve.get_baked_length()
	var draw_dist = 3 # draw a new triangle at this interval in m
	var tri_count = floor(curve_length / draw_dist)

	geom.clear_surfaces()
	for i in range (0, tri_count):
		var f = i * curve_length / tri_count
		var xf = Transform3D()

		xf.origin = curve.sample_baked(f)
		var lookat = (
			curve.sample_baked(f + 0.1) - xf.origin
		).normalized()

		geom.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		if i == 0:
			geom.surface_set_color(COLOR_START)
		else:
			geom.surface_set_color(COLOR_PRIMARY)
		geom.surface_add_vertex(xf.origin)
		geom.surface_add_vertex(xf.origin + Vector3(0, 0.5, 0) - lookat*0.2)
		geom.surface_add_vertex(xf.origin + lookat * 1)
		geom.surface_end()


func rebuild_geom() -> void:
	if refresh_geom:
		call_deferred("_instantiate_geom")


func curve_changed() -> void:
	refresh_geom = true
	rebuild_geom()


func _set_draw_in_game(value: bool) -> void:
	refresh_geom = true
	_draw_in_game = value
	rebuild_geom()

func _get_draw_in_game() -> bool:
	return _draw_in_game

func _set_draw_in_editor(value: bool) -> void:
	refresh_geom = true
	_draw_in_editor = value
	rebuild_geom()

func _get_draw_in_editor() -> bool:
	return _draw_in_editor


func show_fins(value: bool) -> void:
	_draw_override = value
	rebuild_geom()


func _exit_tree() -> void:
	if auto_free_vehicles:
		for obstable in obstacles:
			if is_instance_valid(obstable):
				obstable.node.call_deferred("queue_free")


#endregion
# ------------------------------------------------------------------------------
