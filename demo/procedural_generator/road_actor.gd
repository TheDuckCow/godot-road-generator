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
	
	if not visible:
		set_process(false)
		set_physics_process(false)


## Generic function to calc speed
func get_velocity() -> float:
	return velocity.z


func get_input() -> Vector3:
	match drive_state:
		DriveState.AUTO:
			return _get_auto_input()
		DriveState.PLAYER:
			return _get_player_input()
		_:
			return Vector3.ZERO


func _get_auto_input() -> Vector3:
	if ! is_instance_valid(agent.current_lane):
		return Vector3.ZERO

	var lane_move:int = 0
	if agent.current_lane.transition && agent.close_to_lane_end(-velocity.z):
		# transition line ended, try to automatically switch to the lane that has lane ahead linked
		lane_move = agent.find_continued_lane(-1, -velocity.z)
	else:#
		var cur_cars:int   = agent.cars_in_lane(0)
		if (cur_cars > 1):
			var cur_cars_l:int = agent.cars_in_lane(-1)
			var cur_cars_r:int = agent.cars_in_lane(1)
			if (cur_cars_l >= 0) && (cur_cars - cur_cars_l > 3):
				lane_move -= 1
			elif (cur_cars_r >= 0) && (cur_cars - cur_cars_r > 3):
				lane_move += 1
			#lane_move = 0
	return Vector3(lane_move, 0, -1) # neg z is "forward"


func _get_player_input() -> Vector3:
	if ! is_instance_valid(agent.current_lane):
		return Vector3.ZERO

	var dir:float = 0
	var lane_move:int = 0
	if Input.is_action_pressed("ui_up"):
		dir += 1
	if Input.is_action_pressed("ui_down"):
		dir -= 1

	if agent.current_lane.transition && agent.close_to_lane_end(-velocity.z):
		# transition line ends soon, try to automatically switch to the lane that has lane ahead linked
		lane_move = agent.find_continued_lane(-1, -velocity.z)
	else:
		if Input.is_action_just_pressed("ui_left"):
			lane_move -= 1
		if Input.is_action_just_pressed("ui_right"):
			lane_move += 1
	return Vector3(lane_move, 0, -dir) # neg z is "forward"


func _physics_process(delta: float) -> void:
	velocity.y = 0
	var target_dir:Vector3 = get_input()
	var target_velz = lerp(velocity.z, target_dir.z * target_speed, delta * acceleration)
	velocity.z = target_velz

	agent.change_lane(target_dir.x)

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
	var move_dist:float = -velocity.z * delta

	var next_pos: Vector3 = agent.move_along_lane(move_dist)
	global_transform.origin = next_pos

	# Get another point a little further in front for orientation seeking,
	# without actually moving the vehicle (ie don't update the assign lane
	# if this margin puts us into the next lane in front)
	var orientation:Vector3 = agent.test_move_along_lane(0.05)

	if ! global_transform.origin.is_equal_approx(orientation):
		look_at(orientation, Vector3.UP)
