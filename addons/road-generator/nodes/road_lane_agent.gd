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


signal on_lane_changed(old_lane)

const MoveDir = RoadLane.MoveDir

enum LaneChangeDir
{
	RIGHT = 1,
	CURRENT = 0,
	LEFT = -1
}
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

var agent_pos := RoadLane.Obstacle.new()
var agent_move := RoadLaneAgent.MoveAlongLane.new()

## Cache just to check whether the prior lane was made visible by visualize_lane
var _did_make_lane_visible := false

const DEBUG_OUT: bool = false


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
	assert( !agent_pos.lane || ( is_instance_valid(agent_pos.lane) && agent_pos.check_valid() ) )
	return true if agent_pos.lane else false


func assign_lane(new_lane: RoadLane, new_offset := NAN) -> void:
	if not is_instance_valid(new_lane):
		push_warning("Attempted moving to invalid lane via %s" % self)
		return
	if DEBUG_OUT:
		print(agent_pos, " assigning ", new_offset, " on ", new_lane )
	var _initial_lane: RoadLane = null
	if is_lane_position_valid():
		assert( !is_nan(new_offset) || ( self.agent_pos.lane != new_lane && self.agent_pos.lane.get_path_to(new_lane) not in self.agent_pos.lane.sequential_lanes ) )
		_initial_lane = agent_pos.lane
	if is_nan(new_offset):
		new_offset = new_lane.curve.get_closest_offset(
				new_lane.to_local(
					get_closest_path_point( new_lane,
						actor.global_transform.origin)))
		if DEBUG_OUT:
			print("Found new offset ", new_offset," for ", self )
	agent_pos.lane = new_lane
	agent_pos.offset = new_offset
	if new_lane != _initial_lane:
		if _initial_lane:
			for dir in MoveDir.values():
				var old_shared_part := _initial_lane.shared_parts[dir]
				if old_shared_part:
					old_shared_part.remove_blocks(agent_pos)
			_unassign_lane(_initial_lane)
		new_lane.register_obstacle(agent_pos)
		if not new_lane.draw_in_game and visualize_lane:
			new_lane.draw_in_game = true
			_did_make_lane_visible = true
	for dir in MoveDir.values():
		var shared_part := new_lane.shared_parts[dir]
		if shared_part:
			shared_part.update_blocks(agent_pos)
	assert(new_lane.is_obstacle_list_correct())
	emit_signal("on_lane_changed", _initial_lane)


func unassign_lane() -> RoadLane:
	var old_lane: RoadLane = self.agent_pos.lane
	_unassign_lane(self.agent_pos.lane)
	self.agent_pos.lane = null
	if DEBUG_OUT:
		print("Cleaning adjacent agents of agent ", self)
	return old_lane


func _unassign_lane(old_lane: RoadLane) -> void:
		assert(is_instance_valid(old_lane))
		old_lane.unregister_obstacle(self.agent_pos)
		if old_lane.draw_in_game and _did_make_lane_visible:
			old_lane.draw_in_game = false


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
		assign_lane(res)
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
	if ! is_lane_position_valid():
		return actor.global_transform.origin
	agent_move.set_by_agent_pos(agent_pos, move_distance)
	agent_move.along_lane_ignore_obstacles()
	assign_lane(agent_move.lane, agent_move.offset)
	return agent_move.get_position()


func move_along_lane_check_obstacles(move_distance: float) -> Vector3:
	if ! is_lane_position_valid():
		return actor.global_transform.origin
	agent_move.set_by_agent_pos(agent_pos, move_distance)
	agent_move.along_lane()
	assign_lane(agent_move.lane, agent_move.offset)
	return agent_move.get_position()


## Finds the poistion this many many units forward (or backwards, if negative)
## along the current lane, assigning a new lane if the next one is reached
func continue_along_new_lane(new_lane: RoadLane) -> Vector3:
	if new_lane:
		assign_lane(new_lane)
		agent_move.set_by_agent_pos(agent_pos, agent_move.distance_left)
		agent_move.along_lane()
		assign_lane(agent_move.lane, agent_move.offset)
	return agent_move.get_position()


## Finds the position this many many units forward (or backwards, if negative)
## along the current lane, without assigning a new lane
func test_move_along_lane(move_distance: float) -> Vector3:
	if ! is_lane_position_valid():
		return actor.global_transform.origin
	agent_move.set_by_agent_pos(agent_pos, move_distance)
	agent_move.along_lane_ignore_obstacles()
	return agent_move.get_position()


## It's a heuristic to search
func _position_on_side_lane(other_lane: RoadLane) -> float:
	return ( self.agent_pos.offset *
			other_lane.curve.get_baked_length() / self.agent_pos.lane.curve.get_baked_length() )


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
	assign_lane(_new_lane, _position_on_side_lane(_new_lane))
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


func find_obstacle(lookup_distance: float, dir: MoveDir) -> Array:
	assert(agent_pos.check_valid())
	var idx = agent_pos.lane.find_existing_obstacle_index(agent_pos)
	return agent_pos.lane.find_next_obstacle_from_index(idx, lookup_distance, dir, -agent_pos.end_offsets[dir])


func find_obstacle_on_side_lane(lane_change_dir: LaneChangeDir, lookup_distance: float, dir: MoveDir, node_ignore) -> Array:
	assert(agent_pos.check_valid())
	assert(lane_change_dir in [ LaneChangeDir.RIGHT, LaneChangeDir.LEFT ])
	var side_lane: RoadLane = self.agent_pos.lane.get_side_lane(to_lane_side(lane_change_dir))
	if ! side_lane:
		return [ NAN, null ]
	return side_lane.find_next_obstacle_from_offset( self._position_on_side_lane(side_lane), lookup_distance, dir, -agent_pos.end_offsets[dir], node_ignore )


class MoveAlongLane:
	enum MoveBlock
	{
		NOTHING,
		OBSTACLE,
		NO_LANE
	}

	var agent_pos: RoadLane.Obstacle
	var offset: float
	var lane: RoadLane
	var block: MoveBlock
	var distance_left: float
	var obstacle: RoadLane.Obstacle

	var dir_sign: float
	func move_dir() -> MoveDir:
		return int(dir_sign < 0)

	const DEBUG_OUT := false

	func set_by_agent_pos(agent_pos: RoadLane.Obstacle, move_distance: float) -> void:
		assert(agent_pos.check_valid())
		self.agent_pos = agent_pos
		self.offset = agent_pos.offset
		self.lane = agent_pos.lane
		self.block = MoveBlock.NOTHING
		self.obstacle = null
		self.distance_left = abs(move_distance)
		self.dir_sign = sign(move_distance)

	func get_signed_distance_left() -> float:
		return self.dir_sign * distance_left

	func get_position() -> Vector3:
		return self.lane.to_global(self.lane.curve.sample_baked(self.offset))

	func _up_to_obstacle(obstacle: RoadLane.Obstacle, dist_to_obst: float):
		dist_to_obst = max(dist_to_obst, 0) #in case of overlap
		if self.distance_left > dist_to_obst:
			self.distance_left -= dist_to_obst
			self.offset += self.dir_sign * dist_to_obst
			self.block = MoveBlock.OBSTACLE
			self.obstacle = obstacle
			if DEBUG_OUT:
				print(self.agent_pos, " stopping at ", self.offset, " because of ", self.obstacle, " at distance ", dist_to_obst, ", distance to go ", self.distance_left)
		else:
			_up_to_distance()

	func _up_to_distance():
		self.offset += self.dir_sign * self.distance_left
		self.distance_left = 0
		if DEBUG_OUT:
			print(self.agent_pos, " stopping at ", self.offset, ", all good")

	func _up_to_lane_end(lane_length: float, dir: MoveDir):
		var dist_to_end := lane_length - self.agent_pos.end_offsets[dir]
		dist_to_end = max(dist_to_end, 0)
		self.distance_left -= dist_to_end
		self.offset += self.dir_sign * dist_to_end
		self.block = MoveBlock.NO_LANE
		if DEBUG_OUT:
			print(self.agent_pos, " stopping at ", self.offset, " because lane sequence ended, distance to go ", self.distance_left)

	#TODO remove
	func along_lane() -> void:
		var dir := move_dir()
		if DEBUG_OUT:
			print(self.agent_pos, " is moving ", MoveDir.find_key(dir), " from offset ", self.offset, ", distance to go ", self.distance_left)
		# Find how much space is left along the RoadLane in this direction
		if self.distance_left == 0:
			return
		var dir_back := RoadLane.reverse_move_dir(dir)
		var obstacle: RoadLane.Obstacle = null
		var dist_to_obst: float
		var idx := lane.find_existing_obstacle_index(agent_pos)
		if idx != ((lane.obstacles.size() -1) if dir == MoveDir.FORWARD else 0):
			# we have obstacle in front that is on the current lane
			obstacle = lane.obstacles[idx + (1 if dir == MoveDir.FORWARD else -1)]
			dist_to_obst = abs(obstacle.offset - agent_pos.offset) - agent_pos.end_offsets[dir] - obstacle.end_offsets[dir_back]
			return _up_to_obstacle(obstacle, dist_to_obst)
		var lane_length := agent_pos.distance_to_end(dir)
		var lane_next := lane.get_sequential_lane(dir)
		assert(lane_next != lane)
		while true:
			# there is also no obstacle on the current lane
			if distance_left <= lane_length - agent_pos.end_offsets[dir] - (0 if ! lane_next || lane_next.obstacles.is_empty() else (RoadLane.Obstacle.END_OFFSET_MAX)):
				# nothing is expected in the range we're moving
				return _up_to_distance()
			if ! lane_next:
				# not enough on the lane sequence to move
				return _up_to_lane_end(lane_length, dir)
			if ! lane_next.obstacles.is_empty():
				obstacle = lane_next.obstacles[0 if dir == MoveDir.FORWARD else -1]
				dist_to_obst = obstacle.distance_to_end(dir_back) - obstacle.end_offsets[dir_back] - agent_pos.end_offsets[dir]
				if dist_to_obst <= 0:
					# obstacle is on the other lane but it's possible to collide while staying on this lane
					dist_to_obst = lane_length + dist_to_obst
					return _up_to_obstacle(obstacle, dist_to_obst)
			if distance_left < lane_length:
				# nothing blocks us from moving to the requested distance
				return _up_to_distance()
			# transition to the next lane is needed and nothing blocks us from it
			distance_left -= lane_length
			assert(distance_left >= 0)
			offset = lane_next.offset_from_end(0, dir_back)
			if DEBUG_OUT:
				print(self.agent_pos, " changing lane from ", lane, " to ", lane_next, ", distance to go ", self.distance_left, ", offset ", self.offset)
			lane = lane_next
			if obstacle:
				# there is an obstacle on the current lane (with closest end). we found it while still on the previous lane
				return _up_to_obstacle(obstacle, dist_to_obst)
			lane_length = lane.curve.get_baked_length()
			lane_next = lane.get_sequential_lane(dir)
			assert(lane_next != lane)

	func along_lane_ignore_obstacles() -> void:
		var dir := move_dir()
		if DEBUG_OUT:
			print(self.agent_pos, " is moving ", MoveDir.find_key(dir), " from offset ", self.offset, " ingoring obstacles, distance to go ", self.distance_left)
		# Find how much space is left along the RoadLane in this direction
		if self.distance_left == 0:
			return
		var lane_length = agent_pos.distance_to_end(dir)
		while distance_left >= lane_length:
			var lane_check := lane.get_sequential_lane(dir)
			if lane_check == null:
				block = MoveBlock.NO_LANE
				break
			distance_left -= lane_length
			lane = lane_check
			lane_length = lane.curve.get_baked_length()
			offset = 0 if dir == MoveDir.FORWARD else lane_length
		var dist_to_end := min(distance_left, lane_length)
		distance_left -= dist_to_end
		offset += dist_to_end if dir == MoveDir.FORWARD else -dist_to_end


## Returns the expect target position based on the closest target pos
#func get_fwd_tangent_for_position(position: Vector3) -> Vector3:
#	return Vector3.ZERO


#endregion
# ------------------------------------------------------------------------------
