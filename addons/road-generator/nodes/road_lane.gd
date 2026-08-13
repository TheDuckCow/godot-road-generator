@tool
@icon("res://addons/road-generator/resources/road_lane.png")
class_name RoadLane
extends Path3D

const RoadSegment = preload("res://addons/road-generator/nodes/road_segment.gd")

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

enum Flags {
	# primary and secondary here are about connectivity - primary lane is going to be connected to the next/prior primary lane
	#  and which lane is going to be used for agent collision evasion by RoadLaneAgent
	# we know which lanes are meging/diverging and to where they're merging into/diverging from in road segments
	# for intersections the idea is to use the least curvy or the priority lane as the main one
	# while it may be possible to make such cases as two lanes, where first is main for merging and second is main for divering
	#  the first is diverging from second and second is merging into first - i wouldn't expect RoadLaneAgent to work with it
	NORMAL = 0x0, # plain simple lane
	MERGE_INTO = 0x1, # main lane to which all seconady lane(s) merging into (mutually exclusive with MERGING)
	MERGING = 0x2, # secondary lane that merges into the primary lane (mutually exclusive with MERGE_INTO, see merge_lane)
	DIVERGE_FROM = 0x4, # main lane from which secondary lanes diverging from (mutually exclusive with DIVERGING)
	DIVERGING = 0x8, # secondary lane that diverges from the primary lane (mutually exclusive with DIVERGE_FROM, see diverge_from)
	INTERSECTION = 0x10, # the lane is a part of intersection. it may intersect other lanes (see intersection_points) #TODO not implemented
	BOTH_WAYS = 0x20, # the lane have a twin RoadLane with reverse direction (see opposite_lane) #TODO not implemented
	UTILITY = 0x80000000, # lanes that are created for some internal reason - e.g. despawn lane
}

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

const COLOR_PRIMARY := Color(0.6, 0.3, 0,3)
const COLOR_START := Color(0.1, 0.9, 0.0)
const COLOR_END := Color(0.8, 0.1, 0.1) #Color(0.4, 0.7, 0,7)

const DEBUG_OUT := false
const ENABLE_HEAVY_CHECKS := false # turning on checks in this module that require significant time. use for development and debugging.

# ------------------------------------------------------------------------------
#endregion
#region Export vars
# ------------------------------------------------------------------------------

# -------------------------------------
@export_group("Connections")
# -------------------------------------


var _side_lanes : Array[NodePath] = ["", ""]
var _lane_left_ptr: RoadLane:
	get: return self.get_side_lane(SideDir.LEFT)
var _lane_right_ptr: RoadLane:
	get: return self.get_side_lane(SideDir.RIGHT)
## Reference to the next left-side [RoadLane] if any, for allowed lane transitions.
@export var lane_left: NodePath:
	get:
		return _side_lanes[SideDir.LEFT]
	set(val):
		set_side_lane(val, SideDir.LEFT)

## Reference to the next right-side [RoadLane] if any, for allowed lane transitions.
@export var lane_right: NodePath:
	get:
		return _side_lanes[SideDir.RIGHT]
	set(val):
		set_side_lane(val, SideDir.RIGHT)

var _sequential_lanes: Array[NodePath] = ["", ""]
var _lane_next_ptr: RoadLane:
	get: return self.get_sequential_lane(MoveDir.FORWARD)
var _lane_prior_ptr: RoadLane:
	get: return self.get_sequential_lane(MoveDir.BACKWARD)
## The next forward [RoadLane] for agents to follow along.
@export var lane_next: NodePath:
	get:
		return _sequential_lanes[MoveDir.FORWARD]
	set(val):
		set_sequential_lane(val, MoveDir.FORWARD)

## The prior [RoadLane] for agents to follow (if going backwards).
@export var lane_prior: NodePath:
	get:
		return _sequential_lanes[MoveDir.BACKWARD]
	set(val):
		set_sequential_lane(val, MoveDir.BACKWARD)

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


## lanes to which this lane merges and diverges from
var _primary_lanes : Array[NodePath] = ["", ""]
var _lane_merge_to_ptr: RoadLane:
	get: return self.get_primary_lane(MoveDir.FORWARD)
var _lane_diverge_from_ptr: RoadLane:
	get: return self.get_primary_lane(MoveDir.BACKWARD)
@export var lane_merge_to: NodePath:
	get: return _primary_lanes[MoveDir.FORWARD]
	set(val):
		if get_node_or_null(val) == self:
			push_error("trying to make lane merging into itself")
		else:
			_primary_lanes[MoveDir.FORWARD] = val
@export var lane_diverge_from: NodePath:
	get: return _primary_lanes[MoveDir.BACKWARD]
	set(val):
		if get_node_or_null(val) == self:
			push_error("trying to make lane diverge from itself")
		else:
			_primary_lanes[MoveDir.BACKWARD] = val


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

var refresh_geom := true
var geom:ImmediateMesh # For tool usage, drawing lane directions and end points
var geom_node: MeshInstance3D

## special properties of the lane used by agents
var flags: RoadLane.Flags = RoadLane.Flags.NORMAL

## obstacles registered to this lane
var obstacles: Array[RoadLaneObstacle] = []

## next obstacle search array
## lane length is split in chunks of traffic_chunk_length (array initialized on geometry change)
## should keep first obstacle in chunk in case if there are more than one
## so it is only for rough search obstacle linked list should be used for more precision
var _next_obstacles: Array[RoadLaneObstacle] = []

## FOOTGUN: length of chunk on lane (in meters) for searching next vehicle
## it's going to be set from road_manager on scene add and used when curve is changed/set
## search array won't be updated on change here or in RoadManager and may break
## if <= 0, vehicle search functionality is disabled
## expected to be set once (maybe trasformed into const)
var traffic_chunk_length := 2.5

## this obstacle have to be set at the end of the last lane of lane sequence,
## so that _next_obstacles would always be possible to search for
## e.g. if we want to look back we'll find next here and then prior to it
## one _end_obstacle per lane (which may not be used) for simplicity of ownership when splitting
## TODO get end obstacles when needed from RoadManager instead?
var _end_obstacle: RoadLaneObstacle = null

var _draw_in_game_counter :int = 0
var _draw_in_editor: bool = false
var _draw_override: bool = false
var _display_fins: bool = false


# ------------------------------------------------------------------------------
#endregion
#region Setup and builtin overrides
# ------------------------------------------------------------------------------


func _init():
	if not is_instance_valid(curve):
		curve = Curve3D.new()
	if self.traffic_chunk_length > 0:
		_end_obstacle = RoadLaneObstacle.new(null, RoadLaneObstacle.Flags.LANE_END)
		if self.curve.get_baked_length() != 0:
			_initialize_next_obstacles()
		self._end_obstacle._place_to(self, self.curve.get_baked_length(), false) # don't use assign_position as list is in the right state and _next_obstacles is updated
																				# will be set properly in curve_changed after geomtry is instantiated


func _ready():
	set_notify_transform(true)
	set_notify_local_transform(true)
	connect("curve_changed", Callable(self, "curve_changed"))
	rebuild_geom()
	if self._get_manager():
		self.traffic_chunk_length = self._get_manager().traffic_chunk_length


func _exit_tree() -> void:
	for dir in MoveDir.values():
		self.disconnect_sequential(dir)
		self._primary_lanes[dir] = NodePath("")
	for dir in SideDir.values():
		self.disconnect_side(dir)
	while !self.obstacles.is_empty():
		var obstacle := self.obstacles.back()
		if is_instance_valid(obstacle):
			obstacle.unassign_position() # lane goes out, unassign now necessary as to avoid leaks (links between obstacles) and not to leave lane position dangling
			if auto_free_vehicles:
				obstacle.node.call_deferred("queue_free")


# ------------------------------------------------------------------------------
#endregion
#region Functions
# ------------------------------------------------------------------------------

## a function to get a manager in case if somebody (despawner lane) needs to change the path
func _get_manager() -> RoadManager:
	if ! self.get_parent().container:
		return
	return self.get_parent().container.get_manager()


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


func get_sequential_lane(dir : MoveDir) -> RoadLane:
	var lane: RoadLane = get_node_or_null(self._sequential_lanes[dir])
	assert(lane != self)
	return lane


func set_sequential_lane(val, dir :MoveDir) -> void:
	if get_node_or_null(val) == self:
		push_error("trying to connect a lane to itself")
		return
	if val == _sequential_lanes[dir]:
		return
	if _sequential_lanes[dir]:
		disconnect_sequential(dir)
	var lane = get_node_or_null(val)
	if lane != null && lane is RoadLane:
		if dir == MoveDir.BACKWARD:
			lane.connect_next(self)
		else:
			self.connect_next(lane)


func get_primary_lane(dir : MoveDir) -> RoadLane:
	var lane: RoadLane = get_node_or_null(self._primary_lanes[dir])
	assert(lane != self)
	return lane


func set_primary_lane(dir : MoveDir, lane: RoadLane) -> void:
	self._primary_lanes[dir] = self.get_path_to(lane) if lane else NodePath("")


func get_side_lane(dir : SideDir) -> RoadLane:
	var lane: RoadLane = get_node_or_null(self._side_lanes[dir])
	assert(lane != self)
	return lane

func set_side_lane(val, dir : SideDir) -> void:
	if get_node_or_null(val) == self:
		push_error("trying to connect a lane to itself")
		return
	if val == _side_lanes[dir]:
		return
	if _side_lanes[dir]:
		disconnect_side(dir)
	var lane = get_node_or_null(val)
	if lane != null && lane is RoadLane:
		self.connect_side(lane, dir)

## connect 2 lanes. self is the prior lane, next is the new next lane
## concatenate 2 RoadLaneObstacle lists when enabled (and remove self._end_obstacle)
func connect_next(next: RoadLane) -> void:
	if self.get_sequential_lane(MoveDir.FORWARD) == next:
		return
	assert(self.get_sequential_lane(MoveDir.FORWARD) == null)
	assert(next.get_sequential_lane(MoveDir.BACKWARD) == null)
	if DEBUG_OUT:
		print(self, " connecting to ", next)
	self._sequential_lanes[MoveDir.FORWARD] = self.get_path_to(next)
	next._sequential_lanes[MoveDir.BACKWARD] = next.get_path_to(self)
	if self.traffic_chunk_length > 0:
		assert(next._next_obstacles[0].prior_obstacle == null)
		self._end_obstacle.sequential_obstacles[MoveDir.FORWARD] = next._next_obstacles[0]
		next._next_obstacles[0].sequential_obstacles[MoveDir.BACKWARD] = self._end_obstacle
		self._end_obstacle.unassign_position(false) # propagate next._next_obstacles[0] in place of now unused self._end_obstacle
		assert(next._next_obstacles[0].check_sanity(true))

## function to split RoadLaneObstacle list when one lane is disconnected from another
func _split_obstacle_list_at_end() -> void:
	assert(self.traffic_chunk_length > 0)
	assert(self.get_sequential_lane(MoveDir.FORWARD)._next_obstacles[0].check_sanity())
	#insert - update links and next obstacle fast search list
	self._end_obstacle.assign_position(self, self.curve.get_baked_length(), false)
	#disconnect - sever links between this end obstacle and an obstacle after it
	self._end_obstacle.sequential_obstacles[MoveDir.FORWARD].sequential_obstacles[MoveDir.BACKWARD] = null
	self._end_obstacle.sequential_obstacles[MoveDir.FORWARD] = null

## function for disconnecting lanes and clean up
## split RoadLaneObstacle list when enabled (and remove self._end_obstacle)
func disconnect_sequential(dir : MoveDir) -> void:
	var next := self.get_sequential_lane(dir)
	if ! next:
		return
	var dir_back := RoadLane.reverse_move_dir(dir)
	assert(next.get_sequential_lane(dir_back) == self)
	if self.traffic_chunk_length > 0:
		if DEBUG_OUT:
			print(self, " disconnecting from ", MoveDir.find_key(dir), " linked ", next)
		if dir == MoveDir.FORWARD:
			self._split_obstacle_list_at_end()
		else:
			next._split_obstacle_list_at_end()
		#TODO if a line is to be deleted _next_obstacles doesn't have to be updated end _end_obstacle may be moved from it as an optimization
	self._sequential_lanes[dir] = NodePath("")
	next._sequential_lanes[dir_back] = NodePath("")
	assert(self._end_obstacle == null || self._end_obstacle.check_sanity(true))

## function for connecting side lanes (in both directions)
func connect_side(side_lane :RoadLane, dir :SideDir) -> void:
	if self.get_side_lane(dir) == side_lane:
		return
	assert(self.get_side_lane(dir) == null)
	var dir_back := other_side(dir)
	assert(side_lane.get_side_lane(dir_back) == null)
	if ! side_lane:
		return
	if DEBUG_OUT:
		print(self, " connecting to ", side_lane, " in direction ", SideDir.find_key(dir))
	self._side_lanes[dir] = self.get_path_to(side_lane)
	side_lane._side_lanes[dir_back] = side_lane.get_path_to(self)

## function for disconnecting side lanes
func disconnect_side(dir :SideDir) -> void:
	var lane_side := self.get_side_lane(dir)
	if ! lane_side:
		return
	var dir_back := RoadLane.other_side(dir)
	assert(lane_side.get_side_lane(dir_back) == self)
	if DEBUG_OUT:
		print(self, " disconnecting from ", SideDir.find_key(dir), " linked ", lane_side)
	self._side_lanes[dir] = NodePath("")
	lane_side._side_lanes[dir_back] = NodePath("")
	for lane:RoadLane in [self, lane_side]:
		if (lane.flags & (RoadLane.Flags.DIVERGING | RoadLane.Flags.MERGING)) != 0:
			push_warning("disconnecting ", lane , " that is marked as merging/diverging. its primary lanes are ", lane._primary_lanes[MoveDir.FORWARD], " and ", lane._primary_lanes[MoveDir.BACKWARD])
			#TODO how to hide the warning when the respective RoadSegment - or the whole RoadManager is being taken off?
			#TODO what woulb be a better cleanup? disconnect all the merging/diverging from primary if necessary? assign new primary if previous one is disconnected and propagate it? change flags?


## Register a agent to be connected to (on, following) this lane.
func register_obstacle(obstacle: RoadLaneObstacle) -> void:
	if DEBUG_OUT:
		print("Registering ", obstacle, " on lane ", self, " with lanes connected FORWARD ", self.get_sequential_lane(MoveDir.FORWARD), " and BACKWARD ", self.get_sequential_lane(MoveDir.BACKWARD))
	self._draw_in_game_counter += int(obstacle.visualize_lane)
	assert(obstacle not in self.obstacles)
	self.obstacles.append(obstacle)


## Unregister obstacle from the lane
func unregister_obstacle(obstacle: RoadLaneObstacle) -> void:
	if DEBUG_OUT:
		print("Unregistering ", obstacle, " from lane ", self)
	self._draw_in_game_counter -= int(obstacle.visualize_lane)
	assert( obstacle in self.obstacles )
	self.obstacles.erase(obstacle)


func get_lane_end_point_by_dir(dir: MoveDir) -> Vector3:
	assert(dir in MoveDir.values())
	return get_lane_start() if dir == MoveDir.FORWARD else get_lane_end()


func offset_from_end(offset: float, dir: RoadLane.MoveDir) -> float:
	assert(offset >= 0 && offset <= self.curve.get_baked_length())
	return (self.curve.get_baked_length() - offset) if dir == MoveDir.FORWARD else offset


func get_global_position_at_offset(offset: float) -> Vector3:
	assert(offset >= 0 && offset <= self.curve.get_baked_length())
	return self.to_global(self.curve.sample_baked(offset))


func _instantiate_geom() -> void:
	if Engine.is_editor_hint():
		_display_fins = _draw_in_editor or _draw_override
	else:
		_display_fins = _draw_in_game_counter > 0 or _draw_override

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
	var curve_length := curve.get_baked_length()
	var draw_dist := 1 # draw a new triangle at this interval in m
	var tri_count := floor(curve_length / draw_dist)

	geom.clear_surfaces()
	geom.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range (0, tri_count):
		var f: float = i * curve_length / tri_count
		var xf := Transform3D()

		xf.origin = curve.sample_baked(f)
		# use sample_baked_with_rotation?
		var lookat: Vector3 = (
			curve.sample_baked(f + 0.1) - xf.origin
		).normalized()
		var upvec := curve.sample_baked_up_vector(f, true).normalized()
		var right := lookat.cross(upvec)

		if i == 0:
			geom.surface_set_color(COLOR_START)
		elif i == tri_count - 1:
			geom.surface_set_color(COLOR_END)
		else:
			geom.surface_set_color(COLOR_PRIMARY)

		# Verts
		var pt_front_low := xf.origin + lookat * .5
		var pt_back_right := xf.origin + right*0.2
		var pt_back_left := xf.origin - right*0.2
		var pt_back_high := xf.origin + upvec * 0.2

		# right fin
		geom.surface_add_vertex(pt_front_low)
		geom.surface_add_vertex(pt_back_right)
		geom.surface_add_vertex(pt_back_high)
		# left fin
		geom.surface_add_vertex(pt_front_low)
		geom.surface_add_vertex(pt_back_high)
		geom.surface_add_vertex(pt_back_left)

	geom.surface_end()


func rebuild_geom() -> void:
	if refresh_geom:
		call_deferred("_instantiate_geom")

## resize _next_obstacles search array on creation or change of lane
## geometry, fill with _end_obstacle for proper state
## NOTE when changed with obstacles assigned to the lane, they can change order
func _initialize_next_obstacles() -> void:
		assert(self.traffic_chunk_length > 0)
		assert(self.curve.get_baked_length() > 0)
		var next_lane := self.get_sequential_lane(MoveDir.FORWARD)
		assert(!next_lane || !next_lane._next_obstacles.is_empty()) #we would need to actually initialize obstacle list with an obstacle from next but we can't
		var next_obstacles_size := int(self.curve.get_baked_length() / self.traffic_chunk_length) + 1
		if next_obstacles_size == self._next_obstacles.size():
			return
		var obstacles_copy : Array[RoadLaneObstacle] = []
		while !self.obstacles.is_empty():
			var obstacle := self.obstacles.back()
			obstacles_copy.push_back(obstacle)
			obstacle.unassign_position()
		var obstacle_fill := self._end_obstacle if !next_lane else next_lane._next_obstacles[0]
		self._next_obstacles.resize(next_obstacles_size)
		for idx in len(_next_obstacles):
			assert(self._next_obstacles[idx] in [null, obstacle_fill])
			self._next_obstacles[idx] = obstacle_fill
		for obstacle in obstacles_copy:
			obstacle.assign_closest_lane_position(self, obstacle.node.global_position)


func curve_changed() -> void:
	refresh_geom = true
	if DEBUG_OUT:
		print(self, " changed curve")
	if self.traffic_chunk_length > 0:
		if self.curve.get_baked_length() != 0:
			_initialize_next_obstacles()
		if self.traffic_chunk_length > 0 && self._end_obstacle.lane && self._end_obstacle.offset != self.curve.get_baked_length():
			self._end_obstacle._place_to(self, self.curve.get_baked_length(), false) # don't use assign_position as list is in the right state and _next_obstacles is updated
	rebuild_geom()


func _set_draw_in_game(value: bool) -> void:
	refresh_geom = true
	_draw_in_game_counter = value
	rebuild_geom()

func _get_draw_in_game() -> bool:
	return _draw_in_game_counter > 0

func _set_draw_in_editor(value: bool) -> void:
	refresh_geom = true
	_draw_in_editor = value
	rebuild_geom()

func _get_draw_in_editor() -> bool:
	return _draw_in_editor


func show_fins(value: bool) -> void:
	_draw_override = value
	rebuild_geom()


## use _next_obstacles search array to find next obstacle by offset
## (it may be on a different lane in the same sequence!)
func find_next_obstacle(offset: float) -> RoadLaneObstacle:
	if self.traffic_chunk_length <= 0:
		return null
	assert(!self._next_obstacles.is_empty())
	assert(offset >= 0 && offset <= self.curve.get_baked_length())
	var next := self._next_obstacles[int(offset / self.traffic_chunk_length)]
	if ENABLE_HEAVY_CHECKS && !(next.flags & RoadLaneObstacle.Flags.LANE_END):
		var lane := self
		var found := false
		while lane && !found:
			if next in lane.obstacles:
				found = true
			lane = lane.get_sequential_lane(MoveDir.FORWARD)
		if ! found:
			print(next, " is not registered in ", lane, " or lanes linked in front of it")
		assert(found)
	while next.lane == self && next.offset < offset:
		# if there is more than one obstacle on the same chunk of lane, we may need to skip a couple of them
		next = next.next_obstacle
	return next


## update _next_obstacles search array with the new obstacle (e.g. when it's inserted)
## relies on that chunk between 'to' and its prior are already set to 'to'
## returns true when it stopped updating before end of the lane
##   and false otherwise (and so update should continue on the next lane)
## search array _next_obstacles will always contain first obstacle in chunk
## because of how we update the array:
## e.g. `from` will be next obstacle and `to` new inserted even if there is an obstacle
## on the same chunk and new one is later than previous it won't find `from` there and leave it as is
## chunk_offset is for not updating current chunk (for moving backwards and not cleaning where it is now)
##   it's not going to apply if offset is INF
func _replace_next_obstacle(offset: float, from: RoadLaneObstacle, to: RoadLaneObstacle, dir: MoveDir, chunk_offset: int) -> bool:
	if self.traffic_chunk_length <= 0:
		return true
	assert(!self._next_obstacles.is_empty())
	assert(is_inf(offset) || ( offset >= 0 && offset <= self.curve.get_baked_length() ) )
	var start := (0 if dir == MoveDir.FORWARD else len(_next_obstacles) -1)
	if !is_inf(offset):
		start = int(offset / self.traffic_chunk_length) + chunk_offset
	var end := len(_next_obstacles) if dir == MoveDir.FORWARD else -1
	var step := 1 if dir == MoveDir.FORWARD else -1
	for i in range(start, end, step):
		if self._next_obstacles[i] != from:
			if DEBUG_OUT:
				if start != i:
					print(self, " changed next_obstacles between ", start, " and ", i, " from ", from, " to ", to)
				else:
					print(self, " changed nothing in next_obstacles. starting at ", start, " from ", from, " to ", to)
			return true
		self._next_obstacles[i] = to
	if DEBUG_OUT:
		print(self, " changed next_obstacles between ", start, " and lane end ", end, " from ", from, " to ", to)
	return false

## used to check that obstacles are properly cleaned up when removed from the lane
func is_in_next_obstacles(obstacle: RoadLaneObstacle) -> bool:
	if self.traffic_chunk_length <= 0:
		return false
	return obstacle in self._next_obstacles


#endregion
# ------------------------------------------------------------------------------
