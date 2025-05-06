@icon("res://addons/road-generator/resources/road_lane_agent.png")

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
class_name RoadLaneAgent
extends Node

signal on_lane_changed(old_lane)

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
## Automatically register and unregiter this vehicle to RoadLanes as we travel.[br][br]
##
## Useful to let RoadLanes auto-queue free registered vehicles when the lane is
## being removed, but likely should turn off for player agents to avoid freeing.
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

## Cache just to check whether the prior lane was made visible by visualize_lane
var _did_make_lane_visible := false


func _ready() -> void:
	var res = assign_actor()
	assert(res == OK)
	res = assign_manager()
	assert(res == OK)
	print("Finished setup for road lane agent with: ", road_manager, " and ", current_lane)


func assign_lane(new_lane:RoadLane) -> void:
	if not is_instance_valid(new_lane):
		push_warning("Attempted moving to invalid lane via %s" % self)
		return
	# In race conditions, better to have a vehcile registered in two lanes at
	# once to avoid getting lost in the void if something freed in between
	if auto_register:
		new_lane.register_vehicle(actor)
	if is_instance_valid(current_lane) and current_lane is RoadLane:
		# Even if auto_register is off, no harm in attempt to unregister, in
		# case the setting had recently changed
		current_lane.unregister_vehicle(actor)
		if current_lane.draw_in_game and _did_make_lane_visible:
			current_lane.draw_in_game = false
	if not new_lane.draw_in_game and visualize_lane:
		new_lane.draw_in_game = true
		_did_make_lane_visible = true
	var _initial_lane = current_lane
	current_lane = new_lane
	emit_signal("on_lane_changed", _initial_lane)


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
	var containers = road_manager.get_containers()
	containers.push_front(road_manager)
	
	for _cont in containers:
		if _cont.ai_lane_group in groups_checked:
			continue
		var new_lanes = get_tree().get_nodes_in_group(_cont.ai_lane_group)
		all_lanes.append_array(new_lanes)
		groups_checked.append(_cont.ai_lane_group)

	for lane in all_lanes:
		if not lane is RoadLane:
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


## Get the next position along the RoadLane based on moving this amount
## from the current position (in meters)
func _move_along_lane(move_distance: float, update_lane: bool = true) -> Vector3:
	var pos = actor.global_transform.origin
	var lane_pos:Vector3 = get_closest_path_point(current_lane, pos)
	# Find how much space is left along the RoadLane in this direction
	var init_offset:float = current_lane.curve.get_closest_offset(current_lane.to_local(lane_pos))
	var check_next_offset:float = init_offset + move_distance
	var _update_lane = current_lane
	var lane_length = current_lane.curve.get_baked_length()
	var distance_left = 0
	if check_next_offset > lane_length:
		while check_next_offset > lane_length: # Target point is past the end of this curve
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
			var check_lane = _update_lane.get_node_or_null( _update_lane.lane_prior )
			if ! is_instance_valid(check_lane):
				distance_left = check_next_offset - init_offset
				check_next_offset = 0
				break
			init_offset = 0
			_update_lane = check_lane
			check_next_offset += _update_lane.curve.get_baked_length()
	if update_lane && _update_lane != current_lane:
		assign_lane(_update_lane)
	var ref_local = _update_lane.curve.sample_baked(check_next_offset)
	var new_point: Vector3 = _update_lane.to_global(ref_local)
	if update_lane && distance_left != 0: #workaround for missing connections
		_update_lane = find_nearest_lane(pos - actor.global_transform.basis.z * sign(move_distance), 1)
		if is_instance_valid(_update_lane) && _update_lane != current_lane: # it's still possible to find merging transition lanes
			assign_lane(_update_lane)
	return new_point


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
	var link_test = current_lane.lane_next if move_dir == MoveDir.FORWARD else current_lane.lane_prior
	if link_test:
		return false
	var pos = actor.global_transform.origin
	var lane_pos:Vector3 = get_closest_path_point(current_lane, pos)
	# Find how much space is left along the RoadLane in this direction
	var offset:float = current_lane.curve.get_closest_offset(current_lane.to_local(lane_pos))
	var lane_len = current_lane.curve.get_baked_length()
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
	assert ( move_dir != MoveDir.STOP && (lane_change_dir == LaneChangeDir.LEFT || lane_change_dir == LaneChangeDir.RIGHT) )
	var _new_lane = current_lane
	var count:int = 0
	while true:
		var _new_lane_path = _new_lane.lane_right if lane_change_dir == LaneChangeDir.RIGHT else _new_lane.lane_left
		_new_lane = _new_lane.get_node_or_null(_new_lane_path)
		if ! _new_lane:
			return 0
		count += lane_change_dir
		var link_test = _new_lane.lane_next if move_dir == MoveDir.FORWARD else _new_lane.lane_prior
		if link_test:
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
