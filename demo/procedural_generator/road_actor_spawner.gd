extends Node3D

## simple RoadLane with override to despawn anyone assigned to it
class DespawnRoadLane extends RoadLane:
	const DEBUG_OUT: bool = false
	var _actor_manager = null

	func _init(actor_manager):
		super()
		_actor_manager = actor_manager

	func register_vehicle(vehicle: Node) -> void:
		if _actor_manager:
			_actor_manager.remove_actor(vehicle)
		else:
			vehicle.queue_free()


## Defines a traffic spawner.
##
## Spawn [RoadAgent]s at the beginning of the [RoadLane]s that go out of
## the [RoadPoint] for which the spawner is a child
## Despawn Actors that move from the [RoadLane]s that are not linked to
## other [RoadLane], and that go to the [RoadPoint]  for which the spawner
## is a child

## Minimum spawn time for each of the lanes (in seconds)
@export var spawn_time_min: float = 1
## Maximum spawn time for each of the lanes (in seconds)
@export var spawn_time_max: float = 4
## Delay (in seconds) between 2 spawn events, to be considered separate
## Used to reduce almost unnecessary timer signal events
@export var spawn_time_delta: float = 0.05
## Road actor manager, that tracks the actors
## Expected methods: add_actor, remove_actor
@export var actor_manager_path: NodePath
## Update when there are changes in segments connected to the road point
## Consider using when segments around road point may be changed in game
@export var auto_update:bool = false: set = _set_auto_update

const DEBUG_OUT: bool = false
var _actor_manager = null
var _road_container: RoadContainer

var _despawn_lane: DespawnRoadLane = null # lane that will despawn on assign
var _despawn_lanes: Array[RoadLane] = [] # lanes linked to the _despawn_lane

var _spawn_timer: Timer = null
var _spawn_lanes: Array[RoadLane] = [] # where to spawn
var _spawn_delays: Array[float] = [] # how soon to spawn
var _spawn_current_delay: float # how long ago timer was set


func _ready() -> void:
	assert (spawn_time_delta < spawn_time_min && spawn_time_min < spawn_time_max)
	_actor_manager = get_node_or_null(actor_manager_path)
	assert(_actor_manager)

	# create spawn Timer node child
	_spawn_timer = Timer.new()
	_spawn_timer.one_shot = true
	_spawn_timer.wait_time = randf_range(spawn_time_min, spawn_time_max)
	_spawn_timer.timeout.connect(_on_spawn_timeout.bind())
	add_child(_spawn_timer)
	if DEBUG_OUT:
		print("Created new spawn timer ", _spawn_timer)

	# Create new despawn lane node child
	_despawn_lane = DespawnRoadLane.new(_actor_manager)
	# looping despawn lane on itself just in case
	_despawn_lane.lane_next = _despawn_lane.get_path_to(_despawn_lane)
	_despawn_lane.lane_prior = _despawn_lane.get_path_to(_despawn_lane)
	_despawn_lane.curve.add_point(Vector3.ZERO)
	_despawn_lane.curve.add_point(Vector3.FORWARD * 10) # just so it wouldn't be a point
	add_child(_despawn_lane)
	if DEBUG_OUT:
		print("Created new despawn lane ", _despawn_lane)

	_set_to_parent()


func _enter_tree():
	_set_to_parent()


func _set_to_parent() -> void:
	var rp = get_parent()
	if rp is not RoadPoint:
		push_error("RoadAgentSpawner (" + name + ") is not a child of a RoadPoint")
		return
	if auto_update && ! _road_container:
		_road_container = rp.get_parent() #typecheck in RoadPoint
		_road_container.on_road_updated.connect(_on_road_updated)
	self.call_deferred("_attach")


func _exit_tree():
	if auto_update:
		_road_container.on_road_updated.disconnect(_on_road_updated)
		_road_container = null
	self.call_deferred("_detach")


func _set_auto_update(val: bool) -> void:
	if auto_update == val:
		return
	auto_update = val
	if auto_update:
		assert(_road_container == null)
		var rp: RoadPoint = get_parent()
		_road_container = rp.get_parent() #typecheck in RoadPoint
		_road_container.on_road_updated.connect(_on_road_updated)
	else:
		_road_container.on_road_updated.disconnect(_on_road_updated)
		_road_container = null


## Reattach the spawner if road segment was updated
## only if no lanes are were attached to the point or
func _on_road_updated(updated_segments) -> void:
	var rp: RoadPoint = get_parent()
	if rp.next_seg in updated_segments or rp.prior_seg in updated_segments:
		_attach()
		return


## Update despawn lane to continue from the end of a lane
func _link_spawn_lane(lane: RoadLane) -> void:
	assert( lane not in _spawn_lanes )
	_spawn_lanes.append(lane)
	_spawn_delays.append(0)
	if DEBUG_OUT:
		print("Added as spawn lane ", lane)


## When spawn timer is out, spawm an actor and restart the timer
## Expecting mostly 2-5 lanes (maybe up to 10?)
## So most probably no need for sorting/bsearch/data structures
## If you see bad performance, I propose to use priority queue by event time
func _on_spawn_timeout() -> void:
	assert( not _spawn_delays.is_empty() && _spawn_delays.size() == _spawn_lanes.size() )
	var new_current_delay : float = INF
	for idx in _spawn_delays.size():
		_spawn_delays[idx] -= _spawn_current_delay
		if _spawn_delays[idx] <= spawn_time_delta:
			if ! is_instance_valid(_spawn_lanes[idx]):
				if DEBUG_OUT:
					print("No valid lane for spawn ", _spawn_lanes[idx])
				continue
			if DEBUG_OUT:
				print("Spawn timer fired for lane ", _spawn_lanes[idx])
			_spawn_delays[idx] = randf_range(spawn_time_min, spawn_time_max)
			var lane_start: Vector3 = _spawn_lanes[idx].to_global(_spawn_lanes[idx].curve.get_point_position(0))
			_actor_manager.add_actor(lane_start, _spawn_lanes[idx])
		new_current_delay = min(new_current_delay, _spawn_delays[idx])
	assert( not is_inf(new_current_delay) )
	_spawn_current_delay = new_current_delay
	_spawn_timer.wait_time = _spawn_current_delay
	_spawn_timer.start()


## Link lane to the despawn lane
func _link_despawn_lane(lane: RoadLane, dir) -> void:
	assert( lane not in _despawn_lanes )
	if lane.lane_next_tag[0] == dir: #TODO remove spawn on added lane
		if not lane.get_node_or_null(lane.lane_prior):
			lane.lane_prior = lane.get_path_to(_despawn_lane)
	else:
		if not lane.get_node_or_null(lane.lane_next):
			lane.lane_next = lane.get_path_to(_despawn_lane)
	if DEBUG_OUT:
		print("Attached despawn lane to lane ", lane)
	_despawn_lanes.append(lane)


## Attach to current parent.
## reuse or create new spawner timers for every outgoing lane
## reuse or create new despawner lanes and link them to unconnected road lanes
##   (at the parent road point end)
func _attach() -> void:
	_detach()
	var rp: RoadPoint = get_parent()
	if DEBUG_OUT:
		print("(Re-)Attaching ", name, " to ", rp)
	for dir in ["F", "R"]:
		var seg = rp.next_seg if dir == "R" else rp.prior_seg
		if not is_instance_valid(seg):
			continue
		for lane in seg.get_lanes():
			var lane_tag = lane.lane_prior_tag if dir == "R" else lane.lane_next_tag
			if lane_tag[0] == dir && ! lane.transition: #don't spawn on transition lanes
				_link_spawn_lane(lane)
			_link_despawn_lane(lane, dir)
	assert( _spawn_delays.size() == _spawn_lanes.size() )
	_spawn_current_delay = INF
	for idx in _spawn_delays.size():
		_spawn_delays[idx] = randf_range(spawn_time_min, spawn_time_max)
		_spawn_current_delay = min(_spawn_current_delay, _spawn_delays[idx])
	if not is_inf( _spawn_current_delay ):
		if DEBUG_OUT:
			print("Spawn timer started for ", _spawn_current_delay, " seconds")
		_spawn_timer.wait_time = _spawn_current_delay
		_spawn_timer.start()


## Detach from the current parent node
## stop all spawner timers
## disconnect all the despawning lanes
## keep spawn timer nodes and despawning lane nodes in case if we need to reuse them
func _detach() -> void:
	if DEBUG_OUT:
		print("Detaching ", name)
	for lane:RoadLane in _despawn_lanes:
		if is_instance_valid(lane):
			if lane.get_node_or_null(lane.lane_prior) == _despawn_lane:
				lane.lane_prior = NodePath("")
			if lane.get_node_or_null(lane.lane_next) == _despawn_lane:
				lane.lane_next = NodePath("")
		if DEBUG_OUT:
			print("Detached despawn lane from ", lane)
	_despawn_lanes = []
	_spawn_timer.stop()
	_spawn_lanes = []
	_spawn_delays = []
	if DEBUG_OUT:
		print("Stopped spawn timer")
