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

var agent_pos := RoadLane.Obstacle.new(visualize_lane)
var agent_pos_secondary := RoadLane.Obstacle.new() ## for merging/diverging and lane change
var agent_move := RoadLaneAgent.MoveAlongLane.new()


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


# ------------------------------------------------------------------------------
#endregion
#region Functions
# ------------------------------------------------------------------------------


func is_lane_position_valid() -> bool:
	assert( !self.agent_pos.lane || ( is_instance_valid(self.agent_pos.lane) && self.agent_pos.check_sanity() ) )
	return true if self.agent_pos.lane else false

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
	self.agent_pos.assign_position(new_lane, new_offset)


func assign_lane_position(new_lane: RoadLane, new_offset: float) -> void:
	if not is_instance_valid(new_lane):
		push_warning("Attempted moving to invalid lane via %s" % self)
		return
	self.agent_pos.assign_position(new_lane, new_offset)


func unassign_lane() -> RoadLane:
	var old_lane: RoadLane = self.agent_pos.lane
	self.agent_pos.unassign_position()
	return old_lane


func assign_actor() -> Error:
	var par = get_parent()
	if not par is Node3D:
		push_error("RoadLaneAgent should be a child of a spatial")
		return FAILED
	actor = par
	return OK


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


func assign_nearest_lane() -> Error:
	var res := find_nearest_lane()
	if is_instance_valid(res):
		assign_closest_lane_position(res)
		if DEBUG_OUT:
			print("Assigned nearest lane: ", agent_pos.lane)
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


## Finds the poistion this many many units forward (or backwards, if negative)
## along the current lane, assigning a new lane if the next one is reached
func move_along_lane(move_distance: float) -> Vector3:
	var pos = test_move_along_lane(move_distance)
	agent_pos.move_along_lane(agent_move.lane, agent_move.offset, MoveDir.FORWARD if agent_move.dir_sign > 0 else MoveDir.BACKWARD)
	return pos


## Finds the poistion this many many units forward (or backwards, if negative)
## along the current lane, assigning a new lane if the next one is reached
func continue_along_new_lane(new_lane: RoadLane) -> Vector3:
	if ! new_lane:
		return agent_move.get_position()
	assign_closest_lane_position(new_lane)
	return move_along_lane(agent_move.distance_left)

func continue_along_side_lane(new_lane: RoadLane) -> Vector3:
	if ! new_lane:
		return agent_move.get_position()
	var new_offset = _position_on_side_lane(new_lane)
	assign_lane_position(new_lane, new_offset)
	return move_along_lane(agent_move.distance_left)

## Finds the position this many many units forward (or backwards, if negative)
## along the current lane, without assigning a new lane
func test_move_along_lane(move_distance: float) -> Vector3:
	if ! is_lane_position_valid():
		return actor.global_transform.origin
	agent_move.set_by_agent_pos(agent_pos, move_distance)
	agent_move.along_lane()
	return agent_move.get_position()


## It's a heuristic to search
func _position_on_side_lane(other_lane: RoadLane) -> float:
	return clamp(self.agent_pos.offset *
					other_lane.curve.get_baked_length() / self.agent_pos.lane.curve.get_baked_length(),
					0, other_lane.curve.get_baked_length() )


## Input of < 0 or > 0 to move abs(direction) amount of left or right lanes accordingly
func change_lane(direction: int) -> Error:
	if !direction:
		return OK
	var _new_lane := agent_pos.lane
	var dec = sign(direction)
	while direction != 0:
		_new_lane = _new_lane.get_side_lane(to_lane_side(dec))
		if not is_instance_valid(_new_lane):
			return FAILED
		direction -= dec
	assign_lane_position(_new_lane, _position_on_side_lane(_new_lane))
	return OK


## Returns how many cars are in the current lane (lane_change_dir == 0)
## left lane (lane_change_dir == -1) or right lane (lane_change_dir = 1)
## Used for simple heuristic decision making of traffic balancing
func cars_in_lane(lane_change_dir: LaneChangeDir) -> int:
	if ! is_lane_position_valid():
		return -1
	if lane_change_dir == LaneChangeDir.CURRENT:
		return agent_pos.lane.obstacles.size()
	var _lane := agent_pos.lane.get_side_lane(to_lane_side(lane_change_dir))
	if ! _lane:
		return -1;
	return _lane.obstacles.size()


func find_obstacle_on_side_lane(lane_change_dir: LaneChangeDir) -> RoadLane.Obstacle:
	assert(self.agent_pos.check_sanity())
	assert(lane_change_dir in [ LaneChangeDir.RIGHT, LaneChangeDir.LEFT ])
	var side_lane: RoadLane = self.agent_pos.lane.get_side_lane(to_lane_side(lane_change_dir))
	if ! side_lane:
		return null
	return side_lane.find_next_obstacle( self._position_on_side_lane(side_lane) )


class MoveAlongLane:
	var agent_pos: RoadLane.Obstacle
	var offset: float
	var lane: RoadLane
	var lane_sequence_end: bool
	var distance_left: float

	var dir_sign: float
	func move_dir() -> MoveDir:
		return int(dir_sign < 0)

	const DEBUG_OUT := false

	func set_by_agent_pos(agent_pos: RoadLane.Obstacle, move_distance: float) -> void:
		assert(agent_pos.check_sanity(false, false))
		self.agent_pos = agent_pos
		self.offset = agent_pos.offset
		self.lane = agent_pos.lane
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
			print(self.agent_pos, " is moving ", MoveDir.find_key(dir), " from offset ", self.offset, " ingoring obstacles, distance to go ", self.distance_left)
		# Find how much space is left along the RoadLane in this direction
		if self.distance_left == 0:
			return
		var lane_length := agent_pos.distance_to_end(dir)
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
				print(self.agent_pos, " stopping at ", self.offset, " because lane sequence ended, distance to go ", self.distance_left)
			else:
				print(self.agent_pos, " stopping at ", self.offset, ", all good")


## Returns the expect target position based on the closest target pos
#func get_fwd_tangent_for_position(position: Vector3) -> Vector3:
#	return Vector3.ZERO


#endregion
# ------------------------------------------------------------------------------
