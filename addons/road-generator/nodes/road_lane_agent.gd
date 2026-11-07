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
## Emitted when [member agent_ahead] changes to a different agent (or null).
signal agent_ahead_changed(old_agent: RoadLaneAgent)

enum MoveDir
{
	FORWARD = 1,
	STOP = 0,
	BACKWARD = -1
}
enum LaneChangeDir
{
	RIGHT = 1,
	CURRENT = 0,
	LEFT = -1
}


## Directly assign the path to the [RoadManager] instance, otherwise will assume it
## is in the parent hierarchy. Should refer to [RoadManager] nodes only.
@export var road_manager_path: NodePath
## Let the [RoadLane] this agent is on queue-free the actor when the lane is
## removed (see [member RoadLane.auto_free_vehicles]).[br][br]
##
## Agents are always tracked by their lane; this only controls freeing, so it
## likely should be off for player agents.
@export var auto_register: bool = true
## Debug option to mark the current [RoadLane] visible ingame.[br][br]
##
## Can be slow, best to turn it off for production use.
@export var visualize_lane: bool = false

## Reference spatial to assume where this agent's position is assumed to be at
var actor: Node3D
## The RoadManager instance that is containing all RoadContainers to consider,
## primarily needed to fetch the initial nearest RoadLane
var road_manager: RoadManager
## The current RoadLane, used as the linking reference to all adjacent lanes
var current_lane: RoadLane
## The lane this agent will continue into after [member current_lane], picked
## whenever a lane is assigned.
var chosen_lane_next: RoadLane:
	set(value):
		chosen_lane_next = value
		if _is_in_current_lane():
			refresh_agent_ahead()
## Optional picker used when a lane has more than one next lane, called as
## [code](agent: RoadLaneAgent, options: Array[RoadLane]) -> RoadLane[/code].
## A random option is picked when not set.
var lane_next_chooser: Callable
## Distance along [member current_lane]'s curve to the actor, kept up to date as
## the agent moves.
var current_lane_offset: float = 0.0
## World position [member current_lane_offset] was last derived from.
var _current_lane_offset_reference_position := Vector3.INF

## The nearest agent ahead in the lane's direction: on the same lane, or on the
## lanes ahead via [member chosen_lane_next] and then lanes with a single next
## lane. Kept up to date as agents and lanes change, not re-searched per frame.
var agent_ahead: RoadLaneAgent:
	set(value):
		if value == agent_ahead:
			return
		var old_agent := agent_ahead
		agent_ahead = value
		agent_ahead_changed.emit(old_agent)
## Total length of the empty lanes between this agent's lane and [member agent_ahead]'s.
var _ahead_gap: float = 0.0

## How far past the current lane, in empty lanes, to look for [member agent_ahead].
## Shared by all agents, since we also walk backwards to notify followers, and one with a longer distance wouldn't be found.
## Note: ignores remaining distance in our lane and [member agent_ahead]'s offset in theirs, so values returned by distance_to_agent_ahead() can be higher than this.
static var lookahead_max_distance: float = 100.0
## How many lanes past the current one to look for [member agent_ahead].
static var lookahead_max_hops: int = 8

## Position in the current lane's sorted agents, maintained by [RoadLane].
var _index_in_lane: int = -1

## Cache just to check whether the prior lane was made visible by visualize_lane
var _did_make_lane_visible := false

const DEBUG_OUT: bool = false
## How far the actor may be moved by something else before the offset is re-projected.
const OFFSET_DRIFT_TOLERANCE := 0.01


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
		print("Finished setup for road lane agent with: ", road_manager, " and ", current_lane)


func _exit_tree() -> void:
	unassign_lane()


# ------------------------------------------------------------------------------
#endregion
#region Functions
# ------------------------------------------------------------------------------


## Move this agent onto [param new_lane] at [param offset] along it, or at the
## actor's closest point on the lane if [param offset] is negative.
func assign_lane(new_lane: RoadLane, offset: float = -1.0) -> void:
	if not is_instance_valid(new_lane):
		push_warning("Attempted moving to invalid lane via %s" % self)
		return
	if not new_lane.draw_in_game and visualize_lane:
		new_lane.draw_in_game = true
		_did_make_lane_visible = true
	var old_lane: RoadLane = current_lane if is_instance_valid(current_lane) else null
	current_lane = new_lane
	if offset >= 0.0:
		current_lane_offset = offset
		_current_lane_offset_reference_position = Vector3.INF
	else:
		current_lane_offset = _project_offset(new_lane)
		_current_lane_offset_reference_position = actor.global_position
	chosen_lane_next = _pick_lane_next(new_lane)
	if old_lane == new_lane:
		new_lane.update_agent_order(self)
	else:
		# Join the new lane before leaving the old, so the agent is never on neither.
		# Registering may itself unassign this agent (e.g. a despawning lane).
		new_lane.register_agent(self)
		if old_lane:
			_leave_lane(old_lane)
	emit_signal("on_lane_changed", old_lane)
	if DEBUG_OUT:
		print("Assigned new lane: %s" % new_lane.get_path())


func unassign_lane() -> RoadLane:
	var prev_lane: RoadLane = null
	if is_instance_valid(current_lane):
		_leave_lane(current_lane)
		prev_lane = current_lane
	current_lane = null
	chosen_lane_next = null
	_current_lane_offset_reference_position = Vector3.INF
	_ahead_gap = 0.0
	agent_ahead = null
	return prev_lane


func _leave_lane(lane: RoadLane) -> void:
	lane.unregister_agent(self)
	if lane.draw_in_game and _did_make_lane_visible:
		lane.draw_in_game = false


## Updates [member current_lane_offset] from the actor's position, unless the
## actor is still where this agent last placed it. Returns the offset.
func sync_offset() -> float:
	if not is_instance_valid(current_lane):
		return 0.0
	if _is_offset_stale():
		_set_lane_offset(_project_offset(current_lane), actor.global_position)
	return current_lane_offset


## Forces the next [method sync_offset] to re-project the actor onto the lane.
func invalidate_offset() -> void:
	_current_lane_offset_reference_position = Vector3.INF


## Re-projects without re-sorting; used by [RoadLane] which re-sorts all agents after.
func _reproject_offset() -> void:
	current_lane_offset = _project_offset(current_lane)
	_current_lane_offset_reference_position = actor.global_position


## Offset of the actor along the current lane, without updating the cache.
func _peek_offset() -> float:
	if _is_offset_stale():
		return _project_offset(current_lane)
	return current_lane_offset


func _is_offset_stale() -> bool:
	return actor.global_position.distance_squared_to(_current_lane_offset_reference_position) > OFFSET_DRIFT_TOLERANCE * OFFSET_DRIFT_TOLERANCE


func _project_offset(lane: RoadLane) -> float:
	return lane.curve.get_closest_offset(lane.to_local(actor.global_position))


func _set_lane_offset(offset: float, ref_pos: Vector3) -> void:
	current_lane_offset = offset
	_current_lane_offset_reference_position = ref_pos
	current_lane.update_agent_order(self)


## Distance along the lanes to [member agent_ahead], or INF if there is none.
func distance_to_agent_ahead() -> float:
	if not is_instance_valid(agent_ahead) or not is_instance_valid(current_lane):
		return INF
	if agent_ahead.current_lane == current_lane:
		return agent_ahead.current_lane_offset - current_lane_offset
	var remaining := current_lane.curve.get_baked_length() - current_lane_offset
	return remaining + _ahead_gap + agent_ahead.current_lane_offset


## Re-find [member agent_ahead]. Called by [RoadLane] when agents or lanes change.
func refresh_agent_ahead() -> void:
	if not _is_in_current_lane():
		_ahead_gap = 0.0
		agent_ahead = null
		return
	var lane_agents := current_lane.get_agents()
	if _index_in_lane + 1 < lane_agents.size():
		_ahead_gap = 0.0
		agent_ahead = lane_agents[_index_in_lane + 1]
		return
	var gap := 0.0
	var hops := 0
	var visited := {current_lane: true}
	var lane: RoadLane = null
	if is_instance_valid(chosen_lane_next) and chosen_lane_next in current_lane.get_next_lanes():
		lane = chosen_lane_next
	while lane != null and not visited.has(lane) and hops < lookahead_max_hops and gap <= lookahead_max_distance:
		visited[lane] = true
		hops += 1
		if not lane.get_agents().is_empty():
			_ahead_gap = gap
			agent_ahead = lane.get_agents()[0]
			return
		gap += lane.curve.get_baked_length()
		var nexts := lane.get_next_lanes()
		lane = nexts[0] if nexts.size() == 1 else null
	_ahead_gap = 0.0
	agent_ahead = null


func _is_in_current_lane() -> bool:
	if not is_instance_valid(current_lane):
		return false
	var lane_agents := current_lane.get_agents()
	return _index_in_lane >= 0 and _index_in_lane < lane_agents.size() and lane_agents[_index_in_lane] == self


func assign_actor() -> int:
	var par = get_parent()
	if not par is Node3D:
		push_error("RoadLaneAgent should be a child of a spatial")
		return FAILED
	actor = par
	return OK


func assign_manager() -> int:
	# First try the provided manager path if any
	var _target_manager: Node
	if road_manager_path:
		_target_manager = get_node_or_null(road_manager_path)
		if not is_instance_valid(_target_manager):
			push_error("road_manager_path is invalid")
			return FAILED
		elif not _target_manager is RoadManager:
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


func assign_nearest_lane() -> int:
	var res = find_nearest_lane()
	if is_instance_valid(res) and res is RoadLane:
		assign_lane(res)
		if DEBUG_OUT:
			print("Assigned nearest lane: ", current_lane)
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
	return _move_along_lane(move_distance, true, false).origin


## Finds the poistion this many many units forward (or backwards, if negative)
## along the current lane, without assigning a new lane
func test_move_along_lane(move_distance: float) -> Vector3:
	return _move_along_lane(move_distance, false, false).origin


## Like [method move_along_lane], but returns the global transform there, facing
## along the lane (-Z). Up follows the road surface between the [RoadPoint]s for
## lanes generated by a [RoadSegment], otherwise the lane curve's tilt.
func move_in_lane_with_rotation(move_distance: float) -> Transform3D:
	return _move_along_lane(move_distance, true, true)


## Get the next transform along the RoadLane based on moving this amount
## from the current position (in meters)
func _move_along_lane(move_distance: float, update_lane: bool = true, with_rotation: bool = false) -> Transform3D:
	if not is_instance_valid(current_lane):
		current_lane = null
		return actor.global_transform
	var pos = actor.global_transform.origin
	var init_offset: float = sync_offset() if update_lane else _peek_offset()
	var check_next_offset:float = init_offset + move_distance
	var _update_lane = current_lane
	var lane_length = current_lane.curve.get_baked_length()
	var distance_left = 0
	if check_next_offset > lane_length:
		var is_first_hop := true
		while check_next_offset > lane_length: # Target point is past the end of this curve
			var check_lane := _next_lane_for_move(_update_lane, is_first_hop, update_lane)
			is_first_hop = false
			if DEBUG_OUT:
				print_debug("Agent wrapping to next, paths %s vs node %s" % [
					_update_lane.lanes_next, check_lane])
			if ! is_instance_valid(check_lane):
				distance_left = check_next_offset - lane_length
				check_next_offset = lane_length
				break
			check_next_offset -= lane_length
			_update_lane = check_lane
			lane_length = _update_lane.curve.get_baked_length()
	else:
		while check_next_offset < 0:
			var prior_lanes: Array[RoadLane] = _update_lane.get_prior_lanes()
			var check_lane: RoadLane = null if prior_lanes.is_empty() else prior_lanes[0]
			if DEBUG_OUT:
				print_debug("Agent wrapping to prior, paths %s vs node %s" % [
					_update_lane.lanes_prior, check_lane])
			if ! is_instance_valid(check_lane):
				distance_left = check_next_offset - init_offset
				check_next_offset = 0
				break
			init_offset = 0
			_update_lane = check_lane
			check_next_offset += _update_lane.curve.get_baked_length()
	var new_transform: Transform3D
	if with_rotation:
		new_transform = _get_lane_transform(_update_lane, check_next_offset)
	else:
		new_transform = Transform3D(Basis.IDENTITY, _update_lane.to_global(_update_lane.curve.sample_baked(check_next_offset)))
	var new_point := new_transform.origin
	if update_lane:
		if _update_lane != current_lane:
			assign_lane(_update_lane, check_next_offset)
		if current_lane == _update_lane:
			_set_lane_offset(check_next_offset, new_point)
	if update_lane && distance_left != 0: #workaround for missing connections
		_update_lane = find_nearest_lane(pos - actor.global_transform.basis.z * sign(move_distance), 1)
		if is_instance_valid(_update_lane) && _update_lane != current_lane: # it's still possible to find merging transition lanes
			assign_lane(_update_lane)
	return new_transform


func _get_lane_transform(lane: RoadLane, offset: float) -> Transform3D:
	var lane_length := lane.curve.get_baked_length()
	if lane_length <= 0.001:
		return Transform3D(actor.global_basis, lane.to_global(lane.curve.sample_baked(offset)))
	var lane_transform := lane.global_transform * lane.curve.sample_baked_with_rotation(offset, false, true)
	var segment = lane.road_segment
	if not is_instance_valid(segment):
		return lane_transform.orthonormalized()
	var forward := -lane_transform.basis.z.normalized()
	var road_progress := offset / lane_length
	var lane_start := lane.get_lane_start()
	# Reverse lanes run from the segment's end point to its start point.
	if lane_start.distance_squared_to(segment.start_point.global_position) > lane_start.distance_squared_to(segment.end_point.global_position):
		road_progress = 1.0 - road_progress
	# Matches how the road mesh blends between the RoadPoints' up vectors.
	var start_up: Vector3 = segment.start_point.global_basis.y
	var end_up: Vector3 = segment.end_point.global_basis.y
	var up := start_up.lerp(end_up, ease(road_progress, segment.smooth_amount)).slide(forward)
	if up.length_squared() <= 0.000001:
		up = segment.global_basis.y
	up = up.normalized()
	return Transform3D(Basis(forward.cross(up).normalized(), up, -forward), lane_transform.origin)


## Next lane to move into from [param from_lane]. Only picks, or re-picks a
## stale [member chosen_lane_next], when [param commit] is true.
func _next_lane_for_move(from_lane: RoadLane, is_first_hop: bool, commit: bool) -> RoadLane:
	if is_first_hop and commit:
		return _validated_chosen_lane_next()
	var options := from_lane.get_next_lanes()
	if is_first_hop and is_instance_valid(chosen_lane_next) and chosen_lane_next in options:
		return chosen_lane_next
	if commit:
		return _pick_lane_next(from_lane)
	if options.is_empty():
		return null
	return options[0]


## Returns [member chosen_lane_next], re-picking it first if it's no longer a
## next lane of [member current_lane].
func _validated_chosen_lane_next() -> RoadLane:
	if not is_instance_valid(chosen_lane_next) or chosen_lane_next not in current_lane.get_next_lanes():
		chosen_lane_next = _pick_lane_next(current_lane)
	return chosen_lane_next


func _pick_lane_next(lane: RoadLane) -> RoadLane:
	var options := lane.get_next_lanes()
	if options.is_empty():
		return null
	if options.size() == 1:
		return options[0]
	if lane_next_chooser.is_valid():
		return lane_next_chooser.call(self, options)
	return options.pick_random()


## Input of < 0 or > 0 to move abs(direction) amount of left or right lanes accordingly
func change_lane(direction: int) -> int:
	if !direction:
		return OK
	var _new_lane = current_lane
	var dec = sign(direction)
	while direction != 0:
		var _new_lane_path = _new_lane.lane_right if direction > 0 else _new_lane.lane_left
		if not _new_lane_path:
			# push_error("No lane to change to in target direction")
			return FAILED
		_new_lane = _new_lane.get_node_or_null(_new_lane_path)
		if not is_instance_valid(_new_lane):
			push_error("Invalid target lane change nodepath")
			return FAILED
		elif not _new_lane is RoadLane:
			push_error("Target to change lane to is not a RoadLane")
			return FAILED
		direction -= dec
	assign_lane(_new_lane)
	return OK


## Returns true if the current lane is going to end soon
## proximity is a distance until the end of the lane in forward (move_dir == 1)
## or backward (move_dir == -1) direction
## Used for decision to change lanes from transition lanes (as there are no direct connection)
func close_to_lane_end(proximity: float, move_dir: MoveDir) -> bool:
	if ! is_instance_valid(current_lane) || proximity == 0 || move_dir == MoveDir.STOP:
		return false
	var links := current_lane.get_next_lanes() if move_dir == MoveDir.FORWARD else current_lane.get_prior_lanes()
	if not links.is_empty():
		return false
	var offset := sync_offset()
	var dist:float
	if move_dir == MoveDir.FORWARD:
		dist = current_lane.curve.get_baked_length() - offset
	else:
		assert(move_dir == MoveDir.BACKWARD)
		dist = offset
	return dist < proximity


## Returns how many lanes left (lane_change_dir == -1) or right (lane_change_dir == 1)
## the road continues forward (move_dir == 1) or backward (move_dir == -1)
## Used for decision to change lanes from transition lanes (as there are no direct connection)
func find_continued_lane(lane_change_dir: LaneChangeDir, move_dir: MoveDir) -> int:
	assert(move_dir != MoveDir.STOP && (lane_change_dir == LaneChangeDir.LEFT || lane_change_dir == LaneChangeDir.RIGHT))
	var _new_lane = current_lane
	var count:int = 0
	while true:
		var _new_lane_path = _new_lane.lane_right if lane_change_dir == LaneChangeDir.RIGHT else _new_lane.lane_left
		_new_lane = _new_lane.get_node_or_null(_new_lane_path)
		if ! _new_lane:
			return 0
		count += lane_change_dir
		var links: Array[RoadLane] = _new_lane.get_next_lanes() if move_dir == MoveDir.FORWARD else _new_lane.get_prior_lanes()
		if not links.is_empty():
			return count
	return 0


## Returns how many cars are in the current lane (lane_change_dir == 0)
## left lane (lane_change_dir == -1) or right lane (lane_change_dir = 1)
## Used for simple heuristic decision making of traffic balancing
func cars_in_lane(lane_change_dir: LaneChangeDir) -> int:
	if ! is_instance_valid(current_lane):
		return -1
	if lane_change_dir == LaneChangeDir.CURRENT:
		return len(current_lane.get_vehicles())
	var _lane_path = current_lane.lane_right if lane_change_dir == LaneChangeDir.RIGHT else current_lane.lane_left
	var _lane:RoadLane = current_lane.get_node_or_null(_lane_path)
	if ! _lane:
		return -1;
	return len(_lane.get_vehicles())


## Returns the expect target position based on the closest target pos
#func get_fwd_tangent_for_position(position: Vector3) -> Vector3:
#	return Vector3.ZERO


#endregion
# ------------------------------------------------------------------------------
