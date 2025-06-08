extends Node3D

class DespawnRoadLane extends RoadLane:
	const DEBUG_OUT: bool = false
	func register_vehicle(vehicle: Node) -> void:
		if DEBUG_OUT:
			print("Despawned actor ", vehicle)
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
## Road actor container or manager, that tracks the actors
@export var agent_manager_path: NodePath
## Actor scenes that will be spawned
## Don't change when the spawner object is attached
@export var road_actor_scenes: Array[PackedScene]
## Update when there are changes in segments connected to the road point
## Consider using when segments around road point may be changed in game
@export var auto_update:bool = false: set = _set_auto_update

const DEBUG_OUT: bool = false
var agent_manager = null
var _road_container: RoadContainer
var _despawn_lanes: Dictionary = {}
var _spawn_timers: Dictionary = {}


func _ready() -> void:
	agent_manager = get_node_or_null(agent_manager_path)
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


## Create new spawn tmer (if all previously created are already used)
func _create_spawn_timer() -> Timer:
	var timer = Timer.new()
	timer.one_shot = true
	timer.wait_time = randf_range(spawn_time_min, spawn_time_max)
	timer.timeout.connect(_on_spawn_timeout.bind(timer))
	add_child(timer)
	_spawn_timers[timer] = null
	if DEBUG_OUT:
		print("Created new spawn timer ", timer)
	return timer


## Update despawn lane to continue from the end of a lane
func _set_spawn_timer(timer: Timer, lane: RoadLane) -> void:
	_spawn_timers[timer] = lane
	if DEBUG_OUT:
		print("Attached spawn timer ", timer, " to lane ", lane)
	timer.start()


## When spawn timer is out, spawm an actor and restart the timer
func _on_spawn_timeout(timer: Timer) -> void:
	if ! is_instance_valid(_spawn_timers[timer]):
		if DEBUG_OUT:
			print("Timer ", timer, " has no valid lane")
		return
	if DEBUG_OUT:
		print("Spawn timer ", timer, " fired for lane ", _spawn_timers[timer])
		print("Spawn timer ", timer, " stopped for ease of output reading")
		return
	_spawn_actor(_spawn_timers[timer])
	timer.wait_time = randf_range(spawn_time_min, spawn_time_max)
	timer.start()


## Create new despawn lane (if all previously created are already used)
func _create_despawn_lane() -> RoadLane:
	var despawn_lane = DespawnRoadLane.new()
	# looping despawn lane on itself just in case
	despawn_lane.lane_next = despawn_lane.get_path_to(despawn_lane)
	despawn_lane.lane_prior = despawn_lane.get_path_to(despawn_lane)
	for idx in 2:
		despawn_lane.curve.add_point(Vector3.ZERO)
	add_child(despawn_lane)
	_despawn_lanes[despawn_lane] = null
	if DEBUG_OUT:
		print("Created new despawn lane ", despawn_lane)
	return despawn_lane


## Update despawn lane to continue from the end of a lane
## link said lane to despawn lane
func _set_despawn_lane(despawn_lane:DespawnRoadLane, lane: RoadLane, dir) -> bool:
	# try to continue the lane just in case (so there would not be flickering)
	# otherwise we could have just one lane and link everything to it
	# and we need at least some geometry so it to work for road agent
	var pts: Array[Vector3]
	if lane.lane_next_tag[0] == dir:
		if not lane.get_node_or_null(lane.lane_prior):
			lane.lane_prior = lane.get_path_to(despawn_lane)
			pts = [ lane.curve.get_point_position(1),
					lane.curve.get_point_position(1) - lane.curve.get_point_in(1) ]
	else:
		if not lane.get_node_or_null(lane.lane_next):
			lane.lane_next = lane.get_path_to(despawn_lane)
			pts = [ lane.curve.get_point_position(0) - lane.curve.get_point_out(0),
					lane.curve.get_point_position(0) ]
	if pts.is_empty():
		return false # didn't lane is already linked somewhere
	if pts[1] == pts[0]:
		pts[1 if lane.lane_next_tag[0] == dir else 0] += Vector3.FORWARD
	for idx in pts.size():
		despawn_lane.curve.set_point_position(idx, pts[idx])
	if DEBUG_OUT:
		print("Attached despawn lane ", despawn_lane, " to lane ", lane)
	_despawn_lanes[despawn_lane] = lane
	return true


## Attach to current parent.
## reuse or create new spawner timers for every outgoing lane
## reuse or create new despawner lanes and link them to unconnected road lanes
##   (at the parent road point end)
func _attach() -> void:
	if Engine.is_editor_hint():
		return
	_detach()
	var rp: RoadPoint = get_parent()
	if DEBUG_OUT:
		print("(Re-)Attaching ", name, " to ", rp)
	var dls = _despawn_lanes.keys()
	var sts = _spawn_timers.keys()
	var dlx = 0
	var stx = 0
	for dir in ["F", "R"]:
		var seg = rp.next_seg if dir == "R" else rp.prior_seg
		if not is_instance_valid(seg):
			continue
		for lane in seg.get_lanes():
			if lane.lane_next_tag[0] == dir:
				var st = sts[stx] if stx < sts.size() else _create_spawn_timer()
				stx += 1
				_set_spawn_timer(st, lane)
			var despawn_lane = dls[dlx] if dlx < dls.size() else _create_despawn_lane()
			if _set_despawn_lane(despawn_lane, lane, dir):
				dlx += 1


## Detach from the current parent node
## stop all spawner timers
## disconnect all the despawning lanes
## keep spawn timer nodes and despawning lane nodes in case if we need to reuse them
func _detach() -> void:
	if DEBUG_OUT:
		print("Detaching ", name)
	for despawn_lane:DespawnRoadLane in _despawn_lanes:
		if is_instance_valid(_despawn_lanes[despawn_lane]):
			var lane: RoadLane = _despawn_lanes[despawn_lane]
			if lane.get_node_or_null(lane.lane_prior) == despawn_lane:
				lane.lane_prior = NodePath("")
			if lane.get_node_or_null(lane.lane_next) == despawn_lane:
				lane.lane_next = NodePath("")
		_despawn_lanes[despawn_lane] = null
		if DEBUG_OUT:
			print("Detached despawn lane ", despawn_lane)
	for timer in _spawn_timers:
		timer.stop()
		_spawn_timers[timer] = null
		if DEBUG_OUT:
			print("Stopped spawn timer ", timer)


## Spawn random actor (from road_actor_scenes) at the beginning of the lane
## if actor has road_lane_agent child, assign lane
## if agent managing container is present, add actor there as a child
func _spawn_actor(lane: RoadLane) -> void:
	var chosen_actor_scene = road_actor_scenes[randi_range(0, road_actor_scenes.size() -1)]
	var new_actor = chosen_actor_scene.instantiate()
	if agent_manager:
		agent_manager.add_child(new_actor)
	new_actor.global_transform.origin = lane.to_global(lane.curve.get_point_position(0))
	var agent = new_actor.get_node_or_null("road_lane_agent")
	if is_instance_valid(agent) && agent is RoadLaneAgent:
		agent.assign_lane(lane)
	if DEBUG_OUT:
		print("Spawned new actor ", new_actor)
