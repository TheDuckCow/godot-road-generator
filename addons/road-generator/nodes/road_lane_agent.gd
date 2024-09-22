@icon("res://addons/road-generator/resources/road_lane_agent.png")
## An agent helper for navigation on RoadLanes, inspired but not inheriting
## from NavigationAgent, as we are not using navigation meshes
##
## Used to help calculate position updates, but currently does not directly
## perform these position updates directly.
##
## Needs to be a child of a spatial node which is used as the reference origin
## for calculating positions. This parent can be anywhere if a road_manager_path
## is specified. If it is a (grand)child of a RoadManager, then
## road_manager_path does not need to be specified. This node does not need to
## be a child of an actual RoadLane, but there is no harm in doing so.
class_name RoadLaneAgent
extends Node

signal on_lane_changed(old_lane)

## Directly assign the path to the RoadManager instance, otherwise will assume it
## is in the parent hierarchy. Should refer to RoadManager nodes only.
@export var road_manager_path: NodePath
## Automatically register and unregiter this vehicle to RoadLanes as we travel.
## Useful to let RoadLanes auto-queue free registered vehicles when the lane is
## being removed, but likely should turn off for player agents to avoid freeing
@export var auto_register: bool = true
## Debug tool to make the current lane visible in the game. Can be slow, best
## to turn it off for production use.
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


func assign_lane(new_lane:RoadLane):
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
func find_nearest_lane() -> RoadLane:
	if not is_instance_valid(actor) or not is_instance_valid(road_manager):
		return null
	var pos = actor.global_transform.origin
	var closest_lane = null
	var closest_dist = null

	var all_lanes:Array = []
	var groups_checked:Array = [] # Technically, each container could have its own group name
	var containers = road_manager.get_containers()
	for _cont in containers:
		if _cont.ai_lane_group in groups_checked:
			continue
		var new_lanes = get_tree().get_nodes_in_group(_cont.ai_lane_group)
		all_lanes.append_array(new_lanes)

	for lane in all_lanes:
		if not lane is RoadLane:
			push_warning("Non RoadLane in lanes list (%s)" % lane)
			continue
		var this_lane_closest = get_closest_path_point(lane, pos)
		var this_lane_dist = pos.distance_to(this_lane_closest)
		if this_lane_dist > 50:
			continue
		elif closest_lane == null:
			closest_lane = lane
			closest_dist = this_lane_dist
		elif this_lane_dist < closest_dist:
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
	var new_point: Vector3 = pos
	var lane_pos:Vector3 = get_closest_path_point(current_lane, pos)

	# Find how much space is left along the RoadLane in this direction
	var init_offset:float = current_lane.curve.get_closest_offset(current_lane.to_local(lane_pos))
	var lane_length = current_lane.curve.get_baked_length()

	# Account for the lane's UI setting for direction
	var dir:int = -1 if current_lane.reverse_direction else 1
	var check_next_offset:float = init_offset + move_distance * dir
	var going_to_next:bool = dir > 0
	var _update_lane
	if check_next_offset > lane_length: # Target point is past the end of this curve
		if going_to_next:
			_update_lane = current_lane.get_node_or_null(current_lane.lane_next) # not lane_next?
			#print("Need to jump to next lane (overflow)")
		else:
			_update_lane = current_lane.get_node_or_null(current_lane.lane_prior)
			#print("Need to jump to prior lane (overflow)")
		if not is_instance_valid(_update_lane):
			#push_warning("No next node on path %s " % current_lane.name)
			return new_point
		# TODO: go the "rest of the way" onto the next RoadLane to get final position
		if update_lane:
			assign_lane(_update_lane)
	elif check_next_offset < 0: # Target point is before start of this curve
		if going_to_next:
			_update_lane = current_lane.get_node_or_null(current_lane.lane_prior)
			#print("Need to jump to prior lane (underflow)")
		else:
			_update_lane = current_lane.get_node_or_null(current_lane.lane_next)
			#print("Need to jump to next lane (underflow)")
		if not is_instance_valid(_update_lane):
			#push_warning("No next node on path %s " % current_lane.name)
			return new_point
		# TODO: go the "rest of the way" onto the next RoadLane to get final position
		if update_lane:
			assign_lane(_update_lane)
	else: # Target point lies within the length of this curve
		var ref_local = current_lane.curve.sample_baked(check_next_offset)
		new_point = current_lane.to_global(ref_local)

	return new_point


## Input of -1 or 1 to assign left or right lane accordingly
func change_lane(direction: int) -> int:
	var _new_lane_path
	if direction == 1:
		_new_lane_path = current_lane.lane_right
	elif direction == -1:
		_new_lane_path = current_lane.lane_left
	if not _new_lane_path:
		# push_error("No lane to change to in target direction")
		return FAILED
	var _new_lane = current_lane.get_node_or_null(_new_lane_path)
	if not is_instance_valid(_new_lane):
		push_error("Invalid target lane change nodepath")
		return FAILED
	elif not _new_lane is RoadLane:
		push_error("Target to change lane to is not a RoadLane")
		return FAILED

	assign_lane(_new_lane)
	return OK

## Returns the expect target position based on the closest target pos
#func get_fwd_tangent_for_position(position: Vector3) -> Vector3:
#	return Vector3.ZERO
