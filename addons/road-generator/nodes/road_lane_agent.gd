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

const MoveDir = RoadLane.LaneDirection

enum LaneChangeDir
{
	RIGHT = 1,
	CURRENT = 0,
	LEFT = -1
}
static func to_lane_side(dir : LaneChangeDir) -> RoadLane.LaneSideways:
	return RoadLane.LaneSideways.RIGHT if dir == LaneChangeDir.RIGHT else RoadLane.LaneSideways.LEFT
static func flip_side(dir: LaneChangeDir) -> LaneChangeDir:
	return -1 * dir


## LanePosition should be set and replaced as one in case of race conditions.
## so its (essentially) immutable
class LanePosition:
	var lane: RoadLane = null:
		set(new_lane): assert(lane == null); lane = new_lane
	var offset: float = NAN:
		set(new_offset): assert(is_nan(offset)); offset = new_offset

	func _init(new_lane: RoadLane, new_offset: float) -> void:
		assert( is_instance_valid(new_lane) && ! is_nan(new_offset) )
		assert( new_offset >= 0 && new_offset <= new_lane.curve.get_baked_length() )
		lane = new_lane
		offset = new_offset

	func distance_to_end(dir: MoveDir) -> float:
		assert(dir in [MoveDir.FORWARD, MoveDir.BACKWARD] )
		return offset if dir == MoveDir.BACKWARD else lane.curve.get_baked_length() - offset

	func is_valid() -> bool:
		assert( ! is_nan(offset) || lane == null)
		return is_instance_valid(lane)

static func compare_offset(a1: RoadLaneAgent, a2: RoadLaneAgent) -> bool:
	return a1.lane_pos.offset < a2.lane_pos.offset



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
## The current RoadLane and offset on it
## used as the linking reference to all adjacent lanes
## and position on all the lanes
var lane_pos: LanePosition = null

## Cache just to check whether the prior lane was made visible by visualize_lane
var _did_make_lane_visible := false

var adjacent_agents: Array[RoadLaneAgent] = [null, null] # next FORWARD/BACKWARD

const DEBUG_OUT: bool = true


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
	return lane_pos.is_valid() if lane_pos else false


func assign_lane(new_lane: RoadLane, new_offset := NAN) -> void:
	if not is_instance_valid(new_lane):
		push_warning("Attempted moving to invalid lane via %s" % self)
		return
	assert(self.check_linked_agents())
	var _initial_lane: RoadLane = null
	var link_agents := (self.lane_pos == null) || is_nan(new_offset)
	assert(self.lane_pos == null || is_instance_valid(self.lane_pos.lane) )
	var old_adj_agents: Array[RoadLaneAgent]
	if link_agents:
		var not_empty = self.adjacent_agents[0] || self.adjacent_agents[1]
		old_adj_agents = self.adjacent_agents
		self.adjacent_agents = [null, null]
	else:
		old_adj_agents = [null, null]
	if is_lane_position_valid():
		assert( !is_nan(new_offset) || ( self.lane_pos.lane != new_lane && self.lane_pos.lane.get_path_to(new_lane) not in self.lane_pos.lane.adjacent_lanes ) )
		_initial_lane = lane_pos.lane
	if is_nan(new_offset):
		new_offset = new_lane.curve.get_closest_offset(
				new_lane.to_local(
					get_closest_path_point( new_lane,
						actor.global_transform.origin)))
		if DEBUG_OUT:
			print("Found new offset ", new_offset," for ", self )
	self.lane_pos = LanePosition.new(new_lane, new_offset)
	assert(new_lane.is_agent_list_correct())
	if new_lane != _initial_lane:
		# In race conditions, better to have a vehcile registered in two lanes at
		# once to avoid getting lost in the void if something freed in between
		new_lane.register_agent(self, link_agents)
		if _initial_lane:
			_unassign_lane(_initial_lane, old_adj_agents)
		if not new_lane.draw_in_game and visualize_lane:
			new_lane.draw_in_game = true
			_did_make_lane_visible = true
	new_lane.find_adjacent_agents(self)
	assert(self.check_linked_agents())
	emit_signal("on_lane_changed", _initial_lane)


func unassign_lane() -> RoadLane:
	var old_lane: RoadLane = lane_pos.lane
	_unassign_lane(lane_pos.lane, adjacent_agents)
	lane_pos = null
	if DEBUG_OUT:
		print("Cleaning adjacent agents of agent ", self)
	self.adjacent_agents = [null, null]
	return old_lane


func _unassign_lane(old_lane: RoadLane, adj_agents: Array[RoadLaneAgent]) -> void:
	for dir in MoveDir.values():
		if adj_agents[dir]:
			if DEBUG_OUT:
				print(Time.get_ticks_usec(), " Unlinking previously linked agent ", adj_agents[dir], " (",adj_agents[dir].lane_pos.lane, ") from agent ", self)
			var dir_back = RoadLane.flip_dir(dir)
			assert( adj_agents[dir].adjacent_agents[dir_back] == self )
			adj_agents[dir].adjacent_agents[dir_back] = adj_agents[dir_back]
	if is_instance_valid(old_lane):
		old_lane.unregister_agent(self)
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
			print("Assigned nearest lane: ", lane_pos.lane)
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
	return _move_along_lane(move_distance, true)


## Finds the poistion this many many units forward (or backwards, if negative)
## along the current lane, without assigning a new lane
func test_move_along_lane(move_distance: float) -> Vector3:
	return _move_along_lane(move_distance, false)


func check_linked_agents() -> bool:
	return true
	for dir in MoveDir.values():
		var agent := self.adjacent_agents[dir]
		if agent:
			if agent == self:
				print( "agent ", self, " is linked on itself in direction ", MoveDir.find_key(dir) )
				return false
			var dir_back = RoadLane.flip_dir(dir)
			if agent.adjacent_agents[dir_back] != self:
				print( "agent ", agent, " is linked to ", agent.adjacent_agents[dir_back] , " instead of ", self," in direction ", MoveDir.find_key(dir) )
				return false
			var pos = agent.lane_pos
			if self.lane_pos.lane == pos.lane:
				if pos.offset == self.lane_pos.offset || (dir == MoveDir.FORWARD) == (pos.offset < self.lane_pos.offset):
					print( "agent ", self, " offset ", self.lane_pos.offset, " is incorrect against ", pos.offset ," of agent ", agent, " linked in direction ", MoveDir.find_key(dir) )
					return false
			else:
				var next_lane: RoadLane = self.lane_pos.lane.get_adjacent_lane(dir)
				var count = 10 #just not expecting more distance, but it's possible in reality
				while next_lane && count:
					if next_lane == pos.lane:
						if next_lane._agents_in_lane.is_empty():
							print( "agent ", agent, " is not registered in lane ", next_lane, " as it is marked in its lane position" )
							return false
						var idx := 0 if dir == MoveDir.FORWARD else -1
						var next_agent = next_lane._agents_in_lane[idx]
						if next_agent != agent:
							print( "agent ", agent, " is not found at index ", idx, " of actors registered in lane ", next_lane)
							return false
						break
					next_lane = next_lane.get_adjacent_lane(dir)
					count -= 1
				if ! next_lane:
					print( "agent ", agent, " is not found in direction ", MoveDir.find_key(dir) )
					return false
				if ! count:
					print( "agent ", agent, " is found (but it's possible that its just further than we look) in direction ", MoveDir.find_key(dir) )
	return true


##
func link_next_agent(next_agent: RoadLaneAgent, dir: MoveDir) -> void:
	if DEBUG_OUT:
		print(Time.get_ticks_usec(), " Linking agent ", self, " to agent ", next_agent, " (in direction ", MoveDir.find_key(dir) ,")")
	assert(next_agent)
	assert(self != next_agent)
	assert(self.adjacent_agents[dir] == null)
	assert(next_agent.check_linked_agents())
	var dir_back = RoadLane.flip_dir(dir)
	var prev_agent := next_agent.adjacent_agents[dir_back]
	assert (self != prev_agent)
	if prev_agent && prev_agent != self.adjacent_agents[dir_back]:
		print(Time.get_ticks_usec(), " Linking agent " , self, " backward to agent ", prev_agent)
		assert( self.adjacent_agents[dir_back] == null )
		self.adjacent_agents[dir_back] = prev_agent
		assert( prev_agent.adjacent_agents[dir] == next_agent )
		prev_agent.adjacent_agents[dir] = self
	self.adjacent_agents[dir] = next_agent
	next_agent.adjacent_agents[dir_back] = self
	assert(self.check_linked_agents())


func clip_offset_jump_over(new_offset: float, move_distance: float) -> float:
	var dir:MoveDir = int(move_distance < 0)
	var next_agent = self.adjacent_agents[dir]
	if (dir == MoveDir.FORWARD) == (new_offset > next_agent.lane_pos.offset):
		var clip_offset: float = clamp(next_agent.lane_pos.offset - sign(move_distance) * 0.01, 0.0, next_agent.lane_pos.lane.curve.get_baked_length())
		push_warning("Agent collision of ", self, " (offset ", new_offset, ") that moves ", MoveDir.find_key(dir), " (distance ", move_distance,") with ", next_agent, " (offset ", next_agent.lane_pos.offset, ") on lane ", next_agent.lane_pos.lane, ". trying to stop agent early (on offset ", clip_offset, ")")
		if DEBUG_OUT:
			print("Attempt workaround for agent collision of ", self, " with ", next_agent, "  on lane ", next_agent.lane_pos.lane)
		new_offset = clip_offset
	return new_offset


## Get the next position along the RoadLane based on moving this amount
## from the current position (in meters)
func _move_along_lane(move_distance: float, update_lane: bool = true) -> Vector3:
	# Find how much space is left along the RoadLane in this direction
	if ! is_lane_position_valid():
		return actor.global_transform.origin
	if move_distance == 0:
		return self.lane_pos.lane.to_global(self.lane_pos.lane.curve.sample_baked(self.lane_pos.offset))
	var init_offset := lane_pos.offset
	var check_next_offset := init_offset + move_distance
	var _update_lane := lane_pos.lane
	var lane_length := _update_lane.curve.get_baked_length()
	var distance_left := 0.0

	var dir:MoveDir = int(move_distance < 0)
	var next_agent := adjacent_agents[ dir ]
	var next_lane_pos: LanePosition = next_agent.lane_pos if next_agent else null

	if check_next_offset > lane_length:
		while check_next_offset > lane_length && (!update_lane || next_lane_pos == null || next_lane_pos.lane != _update_lane): # Target point is past the end of this curve
			var check_lane = _update_lane.get_node_or_null( _update_lane.lane_next )
			if ! is_instance_valid(check_lane):
				distance_left = check_next_offset - lane_length
				check_next_offset = lane_length
				break
			check_next_offset -= lane_length
			_update_lane = check_lane
			lane_length = _update_lane.curve.get_baked_length()
	else:
		while check_next_offset < 0:
			check_next_offset = 0
			break #TODO
			var check_lane = _update_lane.get_node_or_null( _update_lane.lane_prior )
			if ! is_instance_valid(check_lane):
				distance_left = check_next_offset - init_offset
				check_next_offset = 0
				break
			init_offset = 0
			_update_lane = check_lane
			check_next_offset += _update_lane.curve.get_baked_length()
	if update_lane:
		if next_lane_pos && next_lane_pos.lane == _update_lane:
			check_next_offset = clip_offset_jump_over(check_next_offset, move_distance)
		assign_lane(_update_lane, check_next_offset)
	var ref_local = _update_lane.curve.sample_baked(check_next_offset)
	var new_point: Vector3 = _update_lane.to_global(ref_local)
	#TODO
	#if update_lane && distance_left != 0: #workaround for missing connections
		#_update_lane = find_nearest_lane(actor.global_transform.origin - actor.global_transform.basis.z * sign(move_distance), 1)
		#if is_instance_valid(_update_lane) && _update_lane != lane_pos.lane: # TODO: it's still possible to find merging transition lanes
			#assign_lane(_update_lane, 0)
	return new_point


## Input of < 0 or > 0 to move abs(direction) amount of left or right lanes accordingly
func change_lane(direction: int) -> Error:
	if !direction:
		return OK
	var _new_lane := lane_pos.lane
	var dec = sign(direction)
	while direction != 0:
		var _new_lane_path = _new_lane.side_lanes[to_lane_side(dec)]
		if not _new_lane_path:
			# push_error("No lane to change to in target direction")
			return FAILED
		_new_lane = _new_lane.get_node_or_null(_new_lane_path)
		if not is_instance_valid(_new_lane):
			push_error("Invalid target lane change nodepath")
			return FAILED
		direction -= dec
	assign_lane(_new_lane) # recalculate offset, as new lane may be longer/shorter
	return OK


## Returns true if the current lane is going to end soon
## proximity is a distance until the end of the lane in forward (move_dir == 1)
## or backward (move_dir == -1) direction
## Used for decision to change lanes from transition lanes (as there are no direct connection)
func close_to_lane_end(proximity: float, move_dir: MoveDir) -> bool:
	if ! is_instance_valid(lane_pos.lane) || proximity == 0:
		return false
	if lane_pos.lane.adjacent_lanes[move_dir]:
		return false
	var dist := lane_pos.distance_to_end(move_dir)
	return dist < proximity


## Returns how many lanes left (lane_change_dir == -1) or right (lane_change_dir == 1)
## the road continues forward (move_dir == 1) or backward (move_dir == -1)
## Used for decision to change lanes from transition lanes (as there are no direct connection)
func find_continued_lane(lane_change_dir: LaneChangeDir, move_dir: MoveDir) -> int:
	assert(move_dir != MoveDir.STOP && (lane_change_dir == LaneChangeDir.LEFT || lane_change_dir == LaneChangeDir.RIGHT))
	var _new_lane := lane_pos.lane
	var count:int = 0
	while true:
		var _new_lane_path = _new_lane.side_lanes[to_lane_side(lane_change_dir)]
		_new_lane = _new_lane.get_node_or_null(_new_lane_path)
		if ! _new_lane:
			return 0
		count += lane_change_dir
		if _new_lane.get_node_or_null(_new_lane.adjacent_lanes[move_dir]):
			return count
	return 0


## Returns how many cars are in the current lane (lane_change_dir == 0)
## left lane (lane_change_dir == -1) or right lane (lane_change_dir = 1)
## Used for simple heuristic decision making of traffic balancing
func cars_in_lane(lane_change_dir: LaneChangeDir) -> int:
	if ! is_lane_position_valid():
		return -1
	if lane_change_dir == LaneChangeDir.CURRENT:
		return len(lane_pos.lane.get_agents())
	var _lane_path = lane_pos.lane.adjacent_lanes[to_lane_side(lane_change_dir)]
	var _lane:RoadLane = lane_pos.lane.get_node_or_null(_lane_path)
	if ! _lane:
		return -1;
	return len(_lane.get_agents())


func find_agent_by_move_dir(max_distance: float, dir: MoveDir) -> RoadLaneAgent:
	assert( dir in [MoveDir.FORWARD, MoveDir.BACKWARD] )
	if ! lane_pos.is_valid():
		return null
	assert( self in self.lane_pos.lane._agents_in_lane )
	var dir_on_lane: RoadLane.LaneDirection = dir
	var dir_back: MoveDir = RoadLane.flip_dir(dir)
	var lane := self.lane_pos.lane
	var distance := -lane_pos.distance_to_end(dir_back)
	var agent_found: RoadLaneAgent = null
	var agent_position: LanePosition = null
	var idx: int = self.lane_pos.lane.find_agent_index(self, true)
	assert( self.lane_pos.lane._agents_in_lane[idx] == self )
	if self.lane_pos.lane._agents_in_lane[idx] != self:
		return null
	if idx == (self.lane_pos.lane._agents_in_lane.size() -1 if dir == MoveDir.FORWARD else 0):
		while is_instance_valid(lane) && distance > max_distance:
			if ! lane._agents_in_lane.is_empty():
				agent_found = self.lane_pos.lane._agents_in_lane[0 if dir == MoveDir.FORWARD else -1]
				break
			distance += lane.curve.get_baked_length()
			lane = get_node_or_null(lane.adjacent_lanes[dir_on_lane])
	else:
		var shift := 1 if dir == MoveDir.FORWARD else -1
		agent_found = lane._agents_in_lane[idx + shift]
	if agent_found:
		assert(lane == agent_found.lane_pos.lane)
		distance += agent_found.lane_pos.distance_to_end(dir_back)
		#assert(distance > 0) #TODO
		if distance < 0:
			return null
		if distance <= max_distance:
			return agent_found
	return null



#func distance_to_agent_on_lane(other: RoadLaneAgent, max_distance: float, dir: MoveDir) -> float:
	#assert( max_distance >= 0)
	#if ! is_instance_valid(other) || ! self.is_lane_position_valid() || ! other.is_lane_position_valid():
		#return NAN
	#var dir_on_lane := move_dir_to_lane_dir(dir)
	#var dir_on_lane_back := RoadLane.flip_dir(dir_on_lane)
	#var lane := self.lane_pos.lane
	#var distance := -lane.distance_to_end_by_dir(self.offset, dir_on_lane_back)
	#while is_instance_valid(lane) && distance > max_distance:
		#if lane == other.lane_pos.lane:
			#distance += lane.distance_to_end_by_dir(other.offset, dir_on_lane_back)
			#if distance < 0 || distance > max_distance:
				#return NAN # not in the direction we're looking for
			#return distance
		#distance += lane.curve.get_baked_length()
		#lane = get_node_or_null(lane.adjacent_lanes[dir_on_lane])
	#return NAN


## Returns the expect target position based on the closest target pos
#func get_fwd_tangent_for_position(position: Vector3) -> Vector3:
#	return Vector3.ZERO


#endregion
# ------------------------------------------------------------------------------
