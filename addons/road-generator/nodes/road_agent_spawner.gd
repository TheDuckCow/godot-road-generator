@tool
@icon("res://addons/road-generator/resources/road_agent_spawner.png")

class_name RoadAgentSpawner
extends Node3D

## Defines a traffic spawner.
##
## Spawn [RoadAgent]s at the beginning of the [RoadLane]s that go out of 
## the [RoadPoint] for which the spawner is a child
## Despawn Actors that move from the [RoadLane]s that are not linked to
## other [RoadLane], and that go to the [RoadPoint]  for which the spawner
## is a child
## TODO: now the spawner has to be reattached if road point is changed
## (linked or the lanes are changed)

## Minimum spawn time for each of the lanes (in seconds)
@export var spawn_time_min: float = 1
## Maximum spawn time for each of the lanes (in seconds)
@export var spawn_time_max: float = 4
## Road actor container or manager, that tracks the actors
@export var agent_manager_path: NodePath
## Actor scenes that will be spawned
@export var road_actor_scenes: Array[PackedScene]

var agent_manager
var spawn_timer: float
var _despawn_lanes: Dictionary = {}
var _spawn_lanes: Array[Array] = [] # [[time1, lane1]...[timeN, laneN]]
var road_point: RoadPoint

func _ready() -> void:
	spawn_timer = randf_range(spawn_time_min, spawn_time_max)
	agent_manager = get_node_or_null(agent_manager_path)
	await get_tree().create_timer(0.5).timeout # wait 0.5 seconds so lanes are hopefully created #TODO fix properly
	attach(get_parent())


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	despawn()
	if road_actor_scenes.is_empty():
		return
	for sl in _spawn_lanes:
		sl[0] -= _delta
		if sl[0] <= 0:
			sl[0] = randf_range(spawn_time_min, spawn_time_max)
			if is_instance_valid(sl[1]):
				spawn(sl[1])


func _exit_tree():
	detach()


func _enter_tree():
	attach(get_parent())


func attach(rp: RoadPoint) -> void:
	if road_point != null:
		detach()
	road_point = rp
	for dir in ["F", "R"]:
		var seg = road_point.next_seg if dir == "R" else road_point.prior_seg
		if not is_instance_valid(seg):
			continue
		for l: RoadLane in seg.get_lanes():
			if l.lane_next_tag[0] == dir:
				_spawn_lanes.append([randf_range(spawn_time_min, spawn_time_max), l])
			var pseudo_lane = RoadLane.new()
			_despawn_lanes[l] = pseudo_lane
			pseudo_lane.lane_next = pseudo_lane.get_path_to(pseudo_lane)
			pseudo_lane.lane_prior = pseudo_lane.get_path_to(pseudo_lane)
			var pt0 = l.curve.get_point_position(1)
			var pt1 = pt0 - l.curve.get_point_in(1)
			if pt1 == pt0:
				pt1 += Vector3.FORWARD
			pseudo_lane.curve.add_point(pt0)
			pseudo_lane.curve.add_point(pt1)
			add_child(pseudo_lane)
			if l.lane_next_tag[0] == dir:
				if not l.get_node_or_null(l.lane_prior):
					l.lane_prior = l.get_path_to(pseudo_lane)
			else:
				if not l.get_node_or_null(l.lane_next):
					l.lane_next = l.get_path_to(pseudo_lane)


func detach() -> void:
	if is_instance_valid(road_point):
		for seg in [road_point.prior_seg, road_point.next_seg]:
			if not is_instance_valid(seg):
				continue
			for l: RoadLane in seg.get_lanes():
				if not _despawn_lanes.find_key(l):
					continue
				if l.get_node_or_null(l.lane_prior) == _despawn_lanes[l]:
					l.lane_prior = NodePath("")
				if l.get_node_or_null(l.lane_next) == _despawn_lanes[l]:
					l.lane_next = NodePath("")
	despawn()
	for l:RoadLane in _despawn_lanes.values():
		l.queue_free()
		remove_child(l)
	_despawn_lanes = {}
	_spawn_lanes = []
	road_point = null


func despawn() -> void:
	for l in _despawn_lanes.values():
		for actor in l.get_vehicles():
			if is_instance_valid(actor):
				actor.queue_free()


func spawn(l: RoadLane) -> void:
	var chosen_actor_scene = road_actor_scenes[randi_range(0, road_actor_scenes.size() -1)]
	var new_actor = chosen_actor_scene.instantiate()
	if agent_manager:
		agent_manager.add_child(new_actor)
	new_actor.global_transform.origin = l.to_global(l.curve.get_point_position(0))
	var agent:RoadLaneAgent = new_actor.get_node("road_lane_agent")
	if is_instance_valid(agent):
		agent.assign_lane(l)
	print("new_instance %s " % new_actor)
