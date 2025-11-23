extends Node3D

## simple RoadLane with override to despawn anyone assigned to it
class DespawnRoadLane extends RoadLane:
	#TODO should be @tool?
	var _actor_manager = null
	var _despawn_obstacle: RoadLane.Obstacle = null

	func _init(actor_manager):
		super()
		flags = RoadLane.LaneFlags.UTILITY
		_actor_manager = actor_manager

	func register_obstacle(obstacle: RoadLane.Obstacle) -> void:
		assert(_despawn_obstacle == null)
		_despawn_obstacle = obstacle
		if _actor_manager:
			_actor_manager.remove_actor(obstacle.node)
		else:
			obstacle.node.queue_free()

	func unregister_obstacle(obstacle: RoadLane.Obstacle) -> void:
		assert(obstacle == _despawn_obstacle)
		_despawn_obstacle = null

## Defines a traffic spawner.
##
## Spawn [RoadAgent]s at the beginning of the [RoadLane]s that go out of
## the [RoadPoint] for which the spawner is a child
## Despawn Actors that move from the [RoadLane]s that are not linked to
## other [RoadLane], and that go to the [RoadPoint]  for which the spawner
## is a child

## Minimum spawn time for each of the lanes (in seconds)
@export var spawn_time_min: float = 1: set = _set_spawn_time_min
## Maximum spawn time for each of the lanes (in seconds)
@export var spawn_time_max: float = 4: set = _set_spawn_time_max
## Delay (in seconds) between 2 spawn events, to be considered separate
## Used to reduce almost unnecessary timer signal events
## Less than 0.05 is not recommended due to Timer implementation
@export var spawn_time_delta: float = 0.1: set = _set_spawn_time_delta
## Distance to the first actor in lane needed to spawn an actor
@export var spawn_distance_min: float = 4.0
## Road actor manager, that tracks the actors
## Expected methods: add_actor, remove_actor
@export var actor_manager_path: NodePath: set = _set_actor_manager
## Update when there are changes in segments connected to the road point
## Consider using when segments around road point may be changed in game
@export var auto_update:bool = false: set = _set_auto_update

var _actor_manager = null
var _road_container: RoadContainer

var _despawn_lane: DespawnRoadLane = null # lane that will despawn on assign
var _despawn_lanes: Array[RoadLane] = [] # lanes linked to the _despawn_lane

var _spawn_timer: Timer = null
var _spawn_lanes: Array[RoadLane] = [] # where to spawn
var _spawn_delays: Array[float] = [] # how soon to spawn

const DEBUG_OUT: bool = false

# Create spawn Timer node child
# Create new despawn lane node child
# Attach to parent RoadPoint
func _ready() -> void:
	_spawn_timer = Timer.new()
	_spawn_timer.one_shot = true
	_spawn_timer.wait_time = randf_range(spawn_time_min, spawn_time_max)
	_spawn_timer.timeout.connect(_on_spawn_timeout.bind())
	add_child(_spawn_timer)
	if DEBUG_OUT:
		print("Created new spawn timer ", _spawn_timer)

	_despawn_lane = DespawnRoadLane.new(_actor_manager)
	_despawn_lane.curve.add_point(Vector3.ZERO)
	_despawn_lane.curve.add_point(Vector3.FORWARD * 100) # just so it wouldn't be a point
	add_child(_despawn_lane)
	if DEBUG_OUT:
		print("Created new despawn lane ", _despawn_lane)

	_set_to_parent()


func _enter_tree():
	if spawn_time_delta >= spawn_time_min || spawn_time_min > spawn_time_max:
		push_error("Minimum spawn time should be bigger than spawn time delta and less or equal to maximum spawn time")

	_actor_manager = get_node_or_null(actor_manager_path)
	if ! _actor_manager:
		push_error("Actor manager path ", actor_manager_path, " is incorrect")
	elif ! _actor_manager.has_method("add_actor") || ! _actor_manager.has_method("remove_actor"):
		push_error("Actor manager at ", actor_manager_path, " should have add_actor and remove_actor methods")
	if DEBUG_OUT:
		print("Using actor manager ", _actor_manager)

	_set_to_parent()


## Internal function for code deduplication
## Attach to parent RoadPoint and find RoadContainer through it
func _set_to_parent() -> void:
	var parent_rp = get_parent()
	if parent_rp is not RoadPoint:
		push_error("RoadAgentSpawner (" + name + ") is not a child of a RoadPoint")
		return
	if auto_update && ! _road_container:
		_road_container = parent_rp.get_parent() #typecheck in RoadPoint
		_road_container.on_road_updated.connect(_on_road_updated)
	self.call_deferred("_attach")


func _exit_tree():
	if auto_update:
		_road_container.on_road_updated.disconnect(_on_road_updated)
		_road_container = null
	self.call_deferred("_detach")


func _set_spawn_time_min(val: float) -> void:
	if is_inside_tree():
		if val <= spawn_time_delta || val > spawn_time_max:
			push_error("Minimum spawn time should be bigger than spawn time delta and less or equal to maximum spawn time")
	spawn_time_min = val


func _set_spawn_time_max(val: float) -> void:
	if is_inside_tree():
		if val < spawn_time_min:
			push_error("Maximum spawn time max should be bigger or equal to minimum spawn time")
	spawn_time_max = val


func _set_spawn_time_delta(val: float) -> void:
	if val < 0.05:
		push_warning("Spawn time delta(as well as min/max spawn times) less than 0.05s is not recommended due to Timer implementation")
	if is_inside_tree():
		if val >= spawn_time_min:
			push_error("Spawn time delta should be less than minimum spawn time")
	spawn_time_delta = val


func _set_actor_manager(new_path: NodePath) -> void:
	if is_inside_tree():
		var new_actor_manager = get_node_or_null(new_path)
		if ! new_actor_manager:
			push_error("Actor manager path ", new_path, " is incorrect")
		elif ! new_actor_manager.has_method("add_actor") || ! new_actor_manager.has_method("remove_actor"):
			push_error("Actor manager at ", new_path, " should have add_actor and remove_actor methods")
		_actor_manager = new_actor_manager
	actor_manager_path = new_path


func _set_auto_update(val: bool) -> void:
	if auto_update == val:
		return
	auto_update = val
	if auto_update:
		assert(_road_container == null)
		var parent_rp: RoadPoint = get_parent()
		_road_container = parent_rp.get_parent() #typecheck in RoadPoint
		_road_container.on_road_updated.connect(_on_road_updated)
	else:
		_road_container.on_road_updated.disconnect(_on_road_updated)
		_road_container = null


## Reattach the spawner if road segment was updated
## only if no lanes are were attached to the parent RoadPoint
func _on_road_updated(updated_segments) -> void:
	var parent_rp: RoadPoint = get_parent()
	if parent_rp.next_seg in updated_segments or parent_rp.prior_seg in updated_segments:
		_attach()
		return


## When spawn timer is triggered, spawn an actor and restart the timer
## Expecting mostly 2-5 lanes (maybe up to 10?)
## So most probably no need for sorting/bsearch/data structures
## If you see bad performance, I propose to use priority queue by event time
func _on_spawn_timeout() -> void:
	_run_timer(_spawn_timer.wait_time)


## Internal function for code deduplication, see description above
func _run_timer(prior_delay: float) -> void:
	assert( ! _spawn_lanes.is_empty() && _spawn_delays.size() >= _spawn_lanes.size() )
	var new_wait : float = INF
	for idx in _spawn_lanes.size():
		_spawn_delays[idx] -= prior_delay
		if _spawn_delays[idx] <= spawn_time_delta:
			if ! is_instance_valid(_spawn_lanes[idx]):
				if DEBUG_OUT:
					print("No valid lane for spawn ", _spawn_lanes[idx])
				continue
			if DEBUG_OUT:
				print("Spawn timer ", _spawn_timer, " fired for lane ", _spawn_lanes[idx])
			_spawn_delays[idx] = randf_range(spawn_time_min, spawn_time_max)
			var first_obstacle: RoadLane.Obstacle = null if _spawn_lanes[idx].obstacles.is_empty() else _spawn_lanes[idx].obstacles[0]
			if ! first_obstacle || first_obstacle.offset >= spawn_distance_min: #check if another agent is too close
				var lane_start: Vector3 = _spawn_lanes[idx].to_global(_spawn_lanes[idx].curve.get_point_position(0))
				_actor_manager.add_actor(lane_start, _spawn_lanes[idx], 0)
		new_wait = min(new_wait, _spawn_delays[idx])
	assert( ! is_inf(new_wait) )
	_spawn_timer.wait_time = new_wait
	_spawn_timer.start()
	if DEBUG_OUT:
		print("Spawn timer ", _spawn_timer, " started for ", new_wait, " seconds")


## Register lane to be used by spawn timer
func _link_spawn_lane(lane: RoadLane, dir: String) -> bool:
	assert( lane not in _spawn_lanes )
	assert( lane.lane_next_tag[0] == lane.lane_prior_tag[0])
	if lane.lane_next_tag[0] != dir || lane.flags == RoadLane.LaneFlags.DIVERGING:
		return false
	_spawn_lanes.append(lane)
	if _spawn_lanes.size() > _spawn_delays.size():
		_spawn_delays.append(randf_range(spawn_time_min, spawn_time_max))
	if DEBUG_OUT:
		print("Added spawn lane ", lane, " for spawn timer ", _spawn_timer)
	return true


## Link despawn lane end (of parent RoadPoint) if it's not linked to anything else
func _link_despawn_lane(lane: RoadLane, dir: String) -> bool:
	assert( lane not in _despawn_lanes )
	var linked := false
	assert( lane.lane_next_tag[0] == lane.lane_prior_tag[0])
	if lane.lane_next_tag[0] == dir:
		if not lane.get_node_or_null(lane.lane_prior):
			lane.connect_sequential(RoadLane.MoveDir.BACKWARD, _despawn_lane)
			linked = true
	else:
		if not lane.get_node_or_null(lane.lane_next):
			lane.connect_sequential(RoadLane.MoveDir.FORWARD, _despawn_lane)
			linked = true
	if linked:
		if DEBUG_OUT:
			print("Linked lane ", lane, " to despawn lane ", _despawn_lane)
		_despawn_lanes.append(lane)
	elif DEBUG_OUT:
		print("Corresponding end of lane ", lane, " is already linked and won't be linked to to despawn lane ", _despawn_lane)
	return linked


## Attach to current parent RoadPoint
## Link lanes for spawning and despawning, start spawn timer
func _attach() -> void:
	_detach()
	var parent_rp: RoadPoint = get_parent()
	if DEBUG_OUT:
		print("(Re-)Attaching ", name, " to ", parent_rp)
	for dir in ["F", "R"]:
		var seg = parent_rp.next_seg if dir == "R" else parent_rp.prior_seg
		if not is_instance_valid(seg):
			continue
		for lane in seg.get_lanes():
			_link_spawn_lane(lane, dir)
			_link_despawn_lane(lane, dir)
	_run_timer(0)


## Detach from the previous parent RoadPoint
## Stop spawner timer, disconnect all the spawning and despawning lanes
## Update spawn timer delays with time passed, instead of nullifying
##   to reduce traffic unevenness if spawner moves
func _detach() -> void:
	if DEBUG_OUT:
		print("Detaching ", name)
	_spawn_timer.stop()
	_despawn_lanes = []
	var time_passed:float = _spawn_timer.wait_time - _spawn_timer.time_left
	for idx in _spawn_lanes.size():
		_spawn_delays[idx] -= time_passed
	_spawn_lanes = []
	if DEBUG_OUT:
		print("Stopped spawn timer ", _spawn_timer, " after ", time_passed, "s")
	for lane:RoadLane in _despawn_lanes:
		if is_instance_valid(lane):
			if lane.get_node_or_null(lane.lane_prior) == _despawn_lane:
				lane.lane_prior = NodePath("")
			if lane.get_node_or_null(lane.lane_next) == _despawn_lane:
				lane.lane_next = NodePath("")
		if DEBUG_OUT:
			print("Unlinked despawn lane ", _despawn_lane, " from lane ", lane)
