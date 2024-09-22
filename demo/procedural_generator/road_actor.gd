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

@onready var agent = get_node("%road_lane_agent")

var velocity := Vector3.ZERO

func _ready() -> void:
	agent.visualize_lane = visualize_lane
	agent.auto_register = auto_register
	print("Agent state: %s par, %s lane, %s manager" % [
		agent.actor, agent.current_lane, agent.road_manager
	])


## Generic function to calc speed
func get_velocity() -> float:
	return velocity.z


func get_input() -> Vector3:
	match drive_state:
		DriveState.AUTO:
			return _get_auto_input()
		DriveState.PLAYER:
			return _get_player_inptu()
		_:
			return Vector3.ZERO


func _get_auto_input() -> Vector3:
	# Using controversial take to make "forward" be positive z
	return Vector3.FORWARD


func _get_player_inptu() -> Vector3:
	var dir:float = 0
	var lane_move:int = 0
	if Input.is_action_pressed("ui_up"):
		dir += 1
	if Input.is_action_pressed("ui_down"):
		dir -= 1

	if Input.is_action_just_pressed("ui_left"):
		lane_move -= 1
	if Input.is_action_pressed("ui_right"):
		lane_move += 1
	return Vector3(lane_move, 0, -dir) # neg z is "forward"


func _physics_process(delta: float) -> void:
	velocity.y = 0
	var target_dir:Vector3 = get_input()
	var target_velz = lerp(velocity.z, target_dir.z * target_speed, delta * acceleration)
	velocity.z = target_velz

	if target_dir.x > 0:
		agent.change_lane(1)
	elif target_dir.x < 0:
		agent.change_lane(-1)

	if not is_instance_valid(agent.current_lane):
		var res = agent.assign_nearest_lane()
		if not res == OK:
			print("Failed to find new lane")
			return

	# Find the next position to jump to; note that the car's forward is the
	# negative Z direction (conventional with Vector3.FORWARD), and thus
	# we flip the direction along the Z axis so that positive move direction
	# matches a positive move_along_lane call, while negative would be
	# going in reverse in the lane's intended direction.
	var move_dist = -velocity.z * delta
	var next_pos:Vector3 = agent.move_along_lane(move_dist)
	# Get another point a little further in front for orientation seeking,
	# without actually moving the vehicle (ie don't update the assign lane
	# if this margin puts us into the next lane in front)
	var orientation:Vector3 = agent.test_move_along_lane(move_dist + 0.05)

	# Position and orient the vehicle
	global_transform.origin = next_pos
	if next_pos != orientation:
		look_at(orientation, Vector3.UP)
