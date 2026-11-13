extends Node3D

enum DriveState {
	PARK,
	AUTO,
	PLAYER
}

@export var drive_state: DriveState = DriveState.AUTO

# Target speed in meters per second
@export var acceleration := 1 # in meters per sec squared
@export var target_speed := 30  # in meters per sec
@export var visualize_lane := false
@export var seek_ahead := 5.0 # How many meters in front of agent to seek position
@export var auto_register: bool = true
@export var rotate_to_distance := 0.5 # How many meters in front of agent to seek rotation

@onready var agent:RoadLaneAgent = get_node("%road_lane_agent")

# how big car difference triggers lane change
var lane_change_tolerance = 3

var velocity_on_lane := 0.0

const transition_time_close := 0.05 # how close to end of a transition lane actor has to switch lane

const DEBUG_OUT: bool = false

func _ready() -> void:
	agent.visualize_lane = visualize_lane
	agent.auto_register = auto_register
	if DEBUG_OUT:
		print("Agent state: %s par, %s lane, %s manager" % [
			agent.actor, agent.current_lane, agent.road_manager
		])

	if not visible:
		set_process(false)
		set_physics_process(false)


func cleanup_for_reuse() -> void:
	agent.unassign_lane()

## Generic function to calc speed
func get_signed_speed() -> float:
	return -velocity_on_lane


func get_input() -> Vector3:
	match drive_state:
		DriveState.AUTO:
			return _get_auto_input()
		DriveState.PLAYER:
			return _get_player_input()
		_:
			return Vector3.ZERO


func _get_auto_input() -> Vector3:
	if ! agent.lane_position.is_assigned():
		return Vector3.ZERO

	var lane_move:int = 0
	var speed = get_signed_speed()
	var cur_cars:int = agent.cars_in_lane(RoadLaneAgent.LaneChangeDir.CURRENT)
	if (cur_cars > 1):
		var cur_cars_l:int = agent.cars_in_lane(agent.LaneChangeDir.LEFT)
		var cur_cars_r:int = agent.cars_in_lane(agent.LaneChangeDir.RIGHT)
		if (cur_cars_l >= 0) && (cur_cars - cur_cars_l > lane_change_tolerance):
			lane_move -= 1
		elif (cur_cars_r >= 0) && (cur_cars - cur_cars_r > lane_change_tolerance):
			lane_move += 1
	return Vector3(lane_move, 0, -1) # neg z is "forward"


func _get_player_input() -> Vector3:
	if ! agent.lane_position.is_assigned():
		return Vector3.ZERO

	var dir:float = 0
	var lane_move:int = 0
	if Input.is_action_pressed("ui_up"):
		dir += 1
	if Input.is_action_pressed("ui_down"):
		dir -= 1

	var speed = get_signed_speed()
	if Input.is_action_just_pressed("ui_left"):
		lane_move -= 1
	if Input.is_action_just_pressed("ui_right"):
		lane_move += 1
	return Vector3(lane_move, 0, -dir) # neg z is "forward"


func _move_to_next_lane() -> void:
	assert(agent.move_along_lane_distance_left != 0)
	var dir := agent.get_move_dir_by_move_distance(agent.move_along_lane_distance_left)
	var primary_lane := agent.lane_position.lane.get_primary_lane(dir)
	if primary_lane:
		var next_pos = agent.continue_along_side_lane(primary_lane)
		global_transform.origin = next_pos
	else:
		#workaround for missing connections
		var next_lane = agent.find_nearest_lane(global_transform.origin - global_transform.basis.z * sign(agent.move_along_lane_distance_left), 1)
		if is_instance_valid(next_lane) && next_lane != agent.lane_position.lane: # TODO: it's still possible to find merging transition lanes
			var next_pos = agent.continue_along_new_lane(next_lane)
			global_transform.origin = next_pos


func _physics_process(delta: float) -> void:
	var target_dir:Vector3 = get_input()
	velocity_on_lane = lerp(velocity_on_lane, target_dir.z * target_speed, delta * acceleration)

	agent.change_lane(int(target_dir.x))

	if !agent.lane_position.is_assigned():
		var res = agent.assign_nearest_lane()
		if not res == OK:
			print("Failed to find new lane")
			queue_free()
			return

	# Find the next position to jump to; note that the car's forward is the
	# negative Z direction (conventional with Vector3.FORWARD), and thus
	# we flip the direction along the Z axis so that positive move direction
	# matches a positive move_along_lane call, while negative would be
	# going in reverse in the lane's intended direction.
	var move_dist:float = get_signed_speed() * delta
	
	var next_pos: Vector3 = agent.move_along_lane(move_dist)
	global_transform.origin = next_pos # has to set it before switching lanes (in case if we move to the end of the lane)
	if agent.move_along_lane_distance_left != 0:
		_move_to_next_lane()

	# Get another point a little further in front for orientation seeking,
	# without actually moving the vehicle (ie don't update the assign lane
	# if this margin puts us into the next lane in front)
	var orientation:Vector3 = agent.test_move_along_lane(self.rotate_to_distance)

	if ! global_transform.origin.is_equal_approx(orientation):
		look_at(orientation, Vector3.UP)
