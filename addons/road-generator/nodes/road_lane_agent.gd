@icon("res://addons/road-generator/resources/road_lane_agent.png")
class_name RoadLaneAgent
extends Node
## An agent helper for navigation on [RoadLane]'s.
##
## Inspired, but does not inherit from, NavigationAgent since this does not rely
## on navigation meshes, but instead on explicit path curves.
##
## Used to help calculate position updates, but currently does not directly
## perform these position updates directly.
##
## Needs to be a child of a spatial node which is used as the reference origin
## for calculating positions. This parent can be anywhere if a road_manager_path
## is specified. If it is a (grand)child of a RoadManager, then
## road_manager_path does not need to be specified. This node does not need to
## be a child of an actual RoadLane, but there is no harm in doing so.
##
## @tutorial(Intersection demo with agents): https://github.com/TheDuckCow/godot-road-generator/tree/main/demo/intersections
## @tutorial(Procedural demo with agents): https://github.com/TheDuckCow/godot-road-generator/tree/main/demo/procedural_generator


# ------------------------------------------------------------------------------
#region Signals/Enums/Const/Export/Vars
# ------------------------------------------------------------------------------

enum LaneChangeDir
{
	RIGHT = 1,
	CURRENT = 0,
	LEFT = -1
}

const MoveDir = RoadLane.MoveDir
const DEBUG_OUT: bool = false

static func to_lane_side(dir : LaneChangeDir) -> RoadLane.SideDir:
	assert(dir in [LaneChangeDir.LEFT, LaneChangeDir.RIGHT] )
	return RoadLane.SideDir.RIGHT if dir == LaneChangeDir.RIGHT else RoadLane.SideDir.LEFT
static func other_side(dir: LaneChangeDir) -> LaneChangeDir:
	return -1 * dir

## Directly assign the path to the [RoadManager] instance, otherwise will assume it
## is in the parent hierarchy. Should refer to [RoadManager] nodes only.
@export var road_manager_path: NodePath
## Debug option to mark the current [RoadLane] visible ingame.[br][br]
##
## Can be slow, best to turn it off for production use.
@export var visualize_lane: bool = false

## Reference spatial to assume where this agent's position is assumed to be at
var actor: Node3D
## The RoadManager instance that is containing all RoadContainers to consider,
## primarily needed to fetch the initial nearest RoadLane
var road_manager: RoadManager

## The agent's current position on the road network, expressed as a
## [RoadLaneObstacle]. This is also what other agents see when checking what's
## ahead of/behind them via [RoadLaneObstacle.sequential_obstacles],
## iterating throught the list or through search on a side lane.
## Read [RoadLaneObstacle.lane] and [RoadLaneObstacle.offset]
## to find where this agent currently is; use [method assign_lane_position]
## or [method assign_closest_lane_position] to move it, don't set fields on
## it directly.
var lane_position := RoadLaneObstacle.new(visualize_lane)

## Working state for the current or most recent [method move_along_lane] call.
## Fields here (e.g. [member MoveAlongLane.lane_sequence_end]) reflect the
## outcome of that last move and are only meaningful to read right after
## calling it - see [MoveAlongLane].
var move := RoadLaneAgent.MoveAlongLane.new()


# ------------------------------------------------------------------------------
#endregion
#region Setup and builtin overrides
# ------------------------------------------------------------------------------


func _ready() -> void:
	var res = assign_actor()
	assert(res == OK)
	res = assign_manager()
	assert(res == OK)
	if DEBUG_OUT:
		print("Finished setup for road lane agent ", self, " with: ", road_manager)


func _exit_tree() -> void:
	self.unassign_lane()


# ------------------------------------------------------------------------------
#endregion
#region Functions
# ------------------------------------------------------------------------------

## True if this agent currently has a valid position on a [RoadLane].
## Call [method assign_nearest_lane] or [method assign_lane_position] first
## if this returns false before doing any lane-relative movement.
func is_lane_position_valid() -> bool:
	assert( !self.lane_position.is_assigned() || ( is_instance_valid(self.lane_position.lane) && self.lane_position.check_sanity() ) )
	return self.lane_position.is_assigned()

## Snap this agent onto [param new_lane] at whichever offset is closest to
## the actor's current global position. Use this when you know which lane
## the agent should be on but not the exact offset (e.g. initial placement,
## or recovering after the agent left the road network). No-ops with a
## warning if [param new_lane] is invalid.
func assign_closest_lane_position(new_lane: RoadLane) -> void:
	if not is_instance_valid(new_lane):
		push_warning("Attempted moving to invalid lane via %s" % self)
		return
	var new_offset = new_lane.curve.get_closest_offset(
			new_lane.to_local(
				get_closest_path_point( new_lane,
					actor.global_transform.origin)))
	if DEBUG_OUT:
		print("Found new offset ", new_offset," for ", self )
	self.lane_position.assign_position(new_lane, new_offset)
	if DEBUG_OUT:
		print("Assigned new lane: %s" % new_lane.get_path())

## Place this agent at an exact [param new_offset] on [param new_lane].
## Use this over [method assign_closest_lane_position] when the offset is
## already known (e.g. spawning, or moving to a computed merge point).
## No-ops with a warning if [param new_lane] is invalid.
func assign_lane_position(new_lane: RoadLane, new_offset: float) -> void:
	if not is_instance_valid(new_lane):
		push_warning("Attempted moving to invalid lane via %s" % self)
		return
	self.lane_position.assign_position(new_lane, new_offset)

## Remove this agent from whatever [RoadLane] it's currently on.
## [method is_lane_position_valid] will return false afterwards. Call this
## before freeing the agent/actor, or before assigning a new position on a
## disconnected part of the road network, to avoid leaving stale obstacle
## links behind.
func unassign_lane() -> void:
	self.lane_position.unassign_position()


## remember actual vehicle node - it should be a parent of the agent
func assign_actor() -> Error:
	var par = get_parent()
	if not par is Node3D:
		push_error("RoadLaneAgent should be a child of a spatial")
		return FAILED
	actor = par
	return OK


## assign road manager (mostly used to search for nearby lanes)
func assign_manager() -> Error:
	# First try the provided manager path if any
	var _target_manager: Node
	if road_manager_path:
		_target_manager = get_node_or_null(road_manager_path)
		if not is_instance_valid(_target_manager) || not _target_manager is RoadManager:
			push_error("road_manager_path is invalid")
			return FAILED
		road_manager = _target_manager
		return OK

	# Fall back to implied parent
	var _last_par = get_parent()
	while true:
		if _last_par == null:
			break
		if _last_par.get_path() == ^"/root":
			break
		if _last_par.has_method("is_road_manager"):
			_target_manager = _last_par
			break # Get the shallow-most manager found
		_last_par = _last_par.get_parent()
	if is_instance_valid(_target_manager) and _target_manager is RoadManager:
		road_manager = _target_manager
		return OK
	else:
		push_error("Could not find road manager parent for %s" % self)
		return FAILED


## Get closest global position on the follow path given a global position
func get_closest_path_point(path: Path3D, pos:Vector3) -> Vector3:
	var interp_point = path.curve.get_closest_point(path.to_local(pos))
	return path.to_global(interp_point)


## Put the actor on the closest lane position
func assign_nearest_lane() -> Error:
	var res := find_nearest_lane()
	if is_instance_valid(res):
		assign_closest_lane_position(res)
		if DEBUG_OUT:
			print("Assigned nearest lane: ", lane_position.lane)
		return OK
	else:
		return FAILED


## Brute force find the nearest lane out of all RoadLanes across the RoadManager
## if pos is null, actor's position will be used. don't look further than distance
func find_nearest_lane(pos = null, distance: float = 50.0) -> RoadLane:
	if not is_instance_valid(actor) or not is_instance_valid(road_manager):
		return null
	if pos == null:
		pos = actor.global_transform.origin
	var closest_lane = null
	var closest_dist = distance # Ignore all lanes further than that

	#TODO: for a case with a lot of lanes/agents, some spatial map would be beneficial for search
	var all_lanes:Array = []
	var groups_checked:Array = [] # Technically, each container could have its own group name
	var containers := road_manager.get_containers() as Array

	if not road_manager.ai_lane_group in groups_checked:
		var new_lanes = get_tree().get_nodes_in_group(road_manager.ai_lane_group)
		all_lanes.append_array(new_lanes)
		groups_checked.append(road_manager.ai_lane_group)
	for _cont in containers:
		if _cont.ai_lane_group in groups_checked:
			continue
		var new_lanes = get_tree().get_nodes_in_group(_cont.ai_lane_group)
		all_lanes.append_array(new_lanes)
		groups_checked.append(_cont.ai_lane_group)

	for lane in all_lanes:
		if not lane is RoadLane or not is_instance_valid(lane):
			push_warning("Non RoadLane in lanes list (%s)" % lane)
			continue
		var this_lane_closest = get_closest_path_point(lane, pos)
		var this_lane_dist = pos.distance_to(this_lane_closest)
		if this_lane_dist < closest_dist:
			closest_lane = lane
			closest_dist = this_lane_dist
	return closest_lane


## Finds the position this many units forward (or backwards, if negative)
## along the current lane, assigning a new lane if the next one is reached
func move_along_lane(move_distance: float) -> Vector3:
	var pos = test_move_along_lane(move_distance)
	if move_distance != 0:
		lane_position.move_along_lane_to(self.move.lane, self.move.offset, MoveDir.FORWARD if self.move.dir_sign > 0 else MoveDir.BACKWARD)
	return pos


## Finds the closest position on a new (newly set or disconnected) lane
## and move the rest of the distance along it
func continue_along_new_lane(new_lane: RoadLane) -> Vector3:
	if ! new_lane:
		return self.move.get_position()
	assign_closest_lane_position(new_lane)
	return move_along_lane(self.move.distance_left)


## Fast find a position on the side lane
## and move the rest of the distance along it
func continue_along_side_lane(new_lane: RoadLane) -> Vector3:
	if ! new_lane:
		return self.move.get_position()
	var new_offset = project_on_side_lane(new_lane)
	assign_lane_position(new_lane, new_offset)
	return move_along_lane(self.move.distance_left)


## Finds the position this many units forward (or backwards, if negative)
## along the current lane, without assigning a new lane
func test_move_along_lane(move_distance: float) -> Vector3:
	if ! is_lane_position_valid():
		return actor.global_transform.origin
	self.move.set_by_lane_position(lane_position, move_distance)
	self.move.along_lane()
	return self.move.get_position()


## It's a heuristic to quickly find closest offset on a side lane
## expecting lanes to not be too creative.
## transform offset to fraction of a lane and transform same fraction
## to offset on the side lane
## as side lane normally can be longer/shorter, reusing same offset
## would be imprecise
## NOTE only use for lanes in the same segment
func project_on_side_lane(side_lane: RoadLane) -> float:
	return clamp(self.lane_position.offset *
					side_lane.curve.get_baked_length() / self.lane_position.lane.curve.get_baked_length(),
					0, side_lane.curve.get_baked_length() )


## Input of < 0 or > 0 to move abs(direction) amount of left or right lanes accordingly
func change_lane(direction: int) -> Error:
	if !direction:
		return OK
	var _new_lane := lane_position.lane
	var dec = sign(direction)
	while direction != 0:
		_new_lane = _new_lane.get_side_lane(to_lane_side(dec))
		if not is_instance_valid(_new_lane):
			return FAILED
		direction -= dec
	assign_lane_position(_new_lane, self.project_on_side_lane(_new_lane))
	return OK


## Returns how many cars are in the current lane (lane_change_dir == 0)
## left lane (lane_change_dir == -1) or right lane (lane_change_dir = 1)
## Used for simple heuristic decision making of traffic balancing
func cars_in_lane(lane_change_dir: LaneChangeDir) -> int:
	if ! is_lane_position_valid():
		return -1
	if lane_change_dir == LaneChangeDir.CURRENT:
		return lane_position.lane.obstacles.size()
	var _lane := lane_position.lane.get_side_lane(to_lane_side(lane_change_dir))
	if ! _lane:
		return -1;
	return _lane.obstacles.size()


## find position to an obstacle in front of the agent on a sidelane
## uses project_on_side_lane with its limitation
func find_obstacle_on_side_lane(lane_change_dir: LaneChangeDir) -> RoadLaneObstacle:
	assert(self.lane_position.check_sanity())
	assert(lane_change_dir in [ LaneChangeDir.RIGHT, LaneChangeDir.LEFT ])
	var side_lane: RoadLane = self.lane_position.lane.get_side_lane(to_lane_side(lane_change_dir))
	if ! side_lane:
		return null
	return side_lane.find_next_obstacle( self.project_on_side_lane(side_lane) )


## Holds the result of the most recent [method RoadLaneAgent.move_along_lane]
## / [method RoadLaneAgent.test_move_along_lane] call. Read these fields
## immediately after calling one of those - they're overwritten by the next
## call and don't represent a "live" state otherwise.
## TODO Overengineered? look once more at what happens here
class MoveAlongLane:
	var lane_position: RoadLaneObstacle
	var offset: float
	var lane: RoadLane
	var lane_sequence_end: bool
	var distance_left: float

	var dir_sign: float
	func move_dir() -> MoveDir:
		return int(dir_sign < 0)

	const DEBUG_OUT := false

	func set_by_lane_position(lane_position: RoadLaneObstacle, move_distance: float) -> void:
		assert(lane_position.check_sanity(false, false))
		self.lane_position = lane_position
		self.offset = lane_position.offset
		self.lane = lane_position.lane
		self.lane_sequence_end = false
		self.distance_left = abs(move_distance)
		self.dir_sign = sign(move_distance)

	func get_signed_distance_left() -> float:
		return self.dir_sign * distance_left

	func get_position() -> Vector3:
		return self.lane.to_global(self.lane.curve.sample_baked(self.offset))

	func along_lane() -> void:
		var dir := move_dir()
		if DEBUG_OUT:
			print(self.lane_position, " is moving ", MoveDir.find_key(dir), " from offset ", self.offset, " ingoring obstacles, distance to go ", self.distance_left)
		# Find how much space is left along the RoadLane in this direction
		if self.distance_left == 0:
			return
		var lane_length := lane_position.distance_to_end(dir)
		while distance_left >= lane_length:
			var lane_check := self.lane.get_sequential_lane(dir)
			if lane_check == null:
				self.lane_sequence_end = true
				break
			self.distance_left -= lane_length
			self.lane = lane_check
			lane_length = self.lane.curve.get_baked_length()
			self.offset = 0 if dir == MoveDir.FORWARD else lane_length
		var dist_to_end := min(self.distance_left, lane_length)
		self.distance_left -= dist_to_end
		self.offset += dist_to_end if dir == MoveDir.FORWARD else -dist_to_end
		if DEBUG_OUT:
			if self.distance_left:
				print(self.lane_position, " stopping at ", self.offset, " because lane sequence ended, distance to go ", self.distance_left)
			else:
				print(self.lane_position, " stopping at ", self.offset, ", all good")


#endregion
# ------------------------------------------------------------------------------
