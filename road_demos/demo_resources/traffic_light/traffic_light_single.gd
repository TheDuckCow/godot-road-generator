extends Node3D

const TrafficLightSynchronizer = preload("res://road_demos/demo_resources/traffic_light/traffic_light_synchronizer.gd")

## simple traffic light. should be a child of TrafficLightSynchronizer
## on entering the tree searches for RoadLane and attaches to it and propagates to side lanes
## when switched from green to yellow, creates obstacles on all the found lanes
## and removes them when switched to green
## must be close to the lanes it's going to block
## NOTE it's not dynamic and all the fields should be set at the startup
## moving/changing group/etc wont change anything after that

enum LightState {
	OFF,
	RED,
	YELLOW,
	GREEN
}

## NOTE it won't be synchronized if changed on the go. if necessary unregister and register again
@export var group: int
@export var red_yellow: bool = false

var state : LightState = LightState.OFF

@onready var red_mesh: MeshInstance3D = $red_mesh
@onready var yellow_mesh: MeshInstance3D = $yellow_mesh
@onready var green_mesh: MeshInstance3D = $green_mesh

@export var red_material: Material = preload("res://road_demos/demo_resources/traffic_light/traffic_light_red_mat.tres")
@export var yellow_material: Material = preload("res://road_demos/demo_resources/traffic_light/traffic_light_yellow_mat.tres")
@export var green_material: Material = preload("res://road_demos/demo_resources/traffic_light/traffic_light_green_mat.tres")
@export var off_material: Material = preload("res://road_demos/demo_resources/traffic_light/traffic_light_off_mat.tres")

var _block_lanes: Array[RoadLane] = [] # which lanes will be blocked
var _block_offsets: Array[float] = [] # on which offsets
var _block_obstacles: Array[RoadLaneObstacle]
var _road_manager :RoadManager = null
#var _notify_actors: Array #TODO

#TODO these should be in obstacle but for now are required by the actor
var length : Array[float] = [0.5, 0.5]  # lengths of obstacle created
func get_signed_speed() -> float:
	return 0


func _ready() -> void:
	set_state(LightState.OFF)
	var synchronizer = get_parent()
	if !synchronizer || synchronizer is not TrafficLightSynchronizer:
		push_warning("TrafficLightSingle should be a child of TrafficLightSynchronizer")
		return
	var road_manager = synchronizer.get_parent()
	if !road_manager || road_manager is not RoadManager:
		push_warning("TrafficLightSynchronizer should be a child of RoadManager")
		return
	self._road_manager = road_manager
	## expecting manager to be a parent of parent (synchronizer)
	var lane :RoadLane= road_manager.find_nearest_lane(self.global_position, 50.0)
	if lane == null:
		call_deferred("attach") #lanes are not created yet?
	else:
		attach()


func _exit_tree() -> void:
	self._unassign_obstacles()


func attach() -> void:
	var lane := self._road_manager.find_nearest_lane(self.global_position, 50.0)
	if lane == null:
		push_warning("traffic light is too far from any lane")
		return
	while lane.get_side_lane(RoadLane.SideDir.RIGHT):
		lane = lane.get_side_lane(RoadLane.SideDir.RIGHT)
	while lane:
		self._block_lanes.push_back(lane)
		self._block_offsets.push_back(lane.curve.get_closest_offset(lane.to_local(global_position)))
		self._block_obstacles.push_back(RoadLaneObstacle.new(self, RoadLaneObstacle.Type.TRAFFIC_LIGHT))
		lane = lane.get_side_lane(RoadLane.SideDir.LEFT)
	if self.state in [LightState.RED, LightState.YELLOW]:
		_assign_obstacles()


func set_state(new_state: LightState) -> void:
	self.red_mesh.material_override = self.off_material
	self.yellow_mesh.material_override = self.off_material
	self.green_mesh.material_override = self.off_material
	match new_state:
		LightState.RED:
			self.red_mesh.material_override = self.red_material
		LightState.YELLOW:
			if self.state == LightState.GREEN:
				self._assign_obstacles()
			if red_yellow || self.state != LightState.RED:
				self.yellow_mesh.material_override = self.yellow_material
			if self.state == LightState.RED:
				self.red_mesh.material_override = self.red_material
		LightState.GREEN:
			self.green_mesh.material_override = self.green_material
			self._unassign_obstacles()
	self.state = new_state


func _assign_obstacles() -> void:
	assert(self._block_lanes.size() == self._block_offsets.size() &&
			self._block_lanes.size() == self._block_obstacles.size())
	for idx in range(self._block_lanes.size()):
		assert(!self._block_obstacles[idx].is_assigned())
		self._block_obstacles[idx].assign_position(self._block_lanes[idx], self._block_offsets[idx])


func _unassign_obstacles() -> void:
	for idx in range(self._block_lanes.size()):
		if self._block_obstacles[idx].is_assigned():
			self._block_obstacles[idx].unassign_position()
