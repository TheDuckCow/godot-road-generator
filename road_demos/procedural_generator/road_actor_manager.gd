extends Node3D

## Defines a traffic manager.
##
## Adds and removes actors
## Can reuse removed actors. In this case instead of freeing,
## hides and pauses actor node, then restores on "creation"
## restored process_mode is PROCESS_MODE_INHERIT

## How many vehicles are allowed to be created, -1 is unlimited
@export var vehicles_max: int = -1
## Actor scenes that will be spawned randomly
@export var road_actor_scenes: Array[PackedScene]
## Don't free actors right away. Instead reuse them when spawned
@export var reuse_removed: bool = true

const DEBUG_OUT = false
var _stashed_vehicles: Array = [] #these are to be added on spawn


func _ready():
	if road_actor_scenes.is_empty():
		push_error("Road Actor Scenes are empty in ", name, ". No actor will be created")
		return null


## Spawn random actor (from road_actor_scenes) at the pos
## if actor has road_lane_agent child, assign lane
## if possible reuse one of the hidden actors. otherwise create new
func add_actor(pos: Vector3, lane: RoadLane = null, offset: float = NAN) -> Node3D:
	if vehicles_max >= 0 && get_actor_count() >= vehicles_max:
		if DEBUG_OUT:
			print("Can't create new actor, amount of vehicles is already at the limit")
		return null
	var new_actor: Node3D
	if reuse_removed && ! _stashed_vehicles.is_empty():
		var reused_idx = randi_range(0, _stashed_vehicles.size() -1)
		new_actor = _stashed_vehicles[reused_idx]
		_stashed_vehicles.remove_at(reused_idx)
		new_actor.process_mode = Node.PROCESS_MODE_INHERIT
		new_actor.visible = true
		if DEBUG_OUT:
			print("Reusing old actor ", new_actor)
	else:
		var chosen_actor_scene: PackedScene = road_actor_scenes[randi_range(0, road_actor_scenes.size() -1)]
		new_actor = chosen_actor_scene.instantiate()
		self.add_child(new_actor)
		if DEBUG_OUT:
			print("Creating new actor ", new_actor)
	new_actor.global_transform.origin = pos
	var agent = new_actor.get_node_or_null("road_lane_agent")
	if lane != null:
		if is_instance_valid(agent) && agent is RoadLaneAgent:
			agent.assign_lane(lane, offset)
		else:
			push_error("Trying to assign actor ", new_actor, " to lane ", lane, " but it doesn't have immediate child agent:RoadLaneAgent")
	return new_actor


## Despawn an actor
## depending on reuse_removed, free or hide
func remove_actor(actor: Node3D):
	if ! is_instance_valid(actor):
		push_error("Trying to remove invalid actor")
		return
	assert(actor.get_parent() == self)
	var agent = actor.get_node_or_null("road_lane_agent")
	if reuse_removed:
		assert(actor not in _stashed_vehicles)
		actor.visible = false
		actor.velocity = Vector3.ZERO
		if actor.process_mode != Node.PROCESS_MODE_INHERIT:
			push_warning("Actor ", actor, " has process_mode ", actor.process_mode, " that will be changed to PROCESS_MODE_INHERIT when the actor is reused")
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		if is_instance_valid(agent) && agent is RoadLaneAgent:
			agent.unassign_lane()
		_stashed_vehicles.append(actor)
		if DEBUG_OUT:
			print("Hid actor ", actor)
	else:
		if is_instance_valid(agent) && agent is RoadLaneAgent:
			agent.unassign_lane()
		actor.queue_free()
		if DEBUG_OUT:
			print("Freed actor ", actor)


## Get amount of actors active in the scene
## All children are expected to be actors
## Hidden actors are ignored
func get_actor_count():
	return self.get_child_count() - _stashed_vehicles.size()
