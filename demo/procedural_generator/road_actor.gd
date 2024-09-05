extends KinematicBody


enum DriveState {
	PARK,
	AUTO,
	PLAYER
}

export(DriveState) var drive_state = DriveState.AUTO

# Target speed in meters per second
export var acceleration := 1 # in meters per sec squared
export var target_speed := 30  # in meters per sec
export var visualize_lane := false
export var seek_ahead := 5.0 # How many meters in front of agent to seek position

onready var agent = get_node("%road_lane_agent")
onready var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

var velocity := Vector3.ZERO

func _ready() -> void:
	print("Agent state: %s par, %s lane, %s manager" % [
		agent.actor, agent.current_lane, agent.road_manager
	])


## Generic function to calc speed
func get_speed() -> float:
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
	# Add the gravity.
	if not is_on_floor():
		print("Falling")
		velocity -= Vector3.UP * gravity * delta
		var target_velz = lerp(velocity.z, 0, delta)
		velocity.z = target_velz
		var _res = move_and_slide(velocity, Vector3.UP, true, 4, PI/4, false)
	else:
		velocity.y = 0
		var target_dir:Vector3 = get_input()
		var target_velz = lerp(velocity.z, target_dir.z * target_speed, delta * acceleration)
		#target_dir.z = clamp(target_velz, -target_speed, target_speed)
		velocity.z = target_velz

		var new_lane_path = null
		if target_dir.x > 0:
			agent.change_lane(1)
		elif target_dir.x < 0:
			agent.change_lane(-1)

	if not is_instance_valid(agent.current_lane):
		var res = agent.assign_nearest_lane()
		if not res == OK:
			print("Failed to find new lane")
		else:
			print("Assigned new lane ", agent.current_lane)
		# Just move forward, or stay still?
		#var _res = move_and_slide(velocity, Vector3.UP, true, 4, PI/4, false)
		return

	# Find the next position to jump to; noting that car's forward is the
	# negative Z direction (conventional with Vector3.FORWARD), and thus
	# we flip the direction along the Z axis so that positive distance count
	# is the forward direction in move_along_lane, while negative would be
	# going in reverse in the lane's intended direction.
	var move_dist = -velocity.z * delta
	var next_pos:Vector3 = agent.move_along_lane(move_dist)
	var orientation:Vector3 = agent.move_along_lane(move_dist + 0.05)

	global_transform.origin = next_pos
	if next_pos != orientation:
		look_at(orientation, Vector3.UP)

	# gd3 defaults:
	#move_and_slide(linear_velocity: Vector3, up_direction: Vector3 = Vector3( 0, 0, 0 ), stop_on_slope: bool = false, max_slides: int = 4, floor_max_angle: float = 0.785398, infinite_inertia: bool = true)
	#var _res = move_and_slide(velocity, Vector3.UP, true, 4, PI/4, false)
	#print(velocity)

	# Now snap the car and orientation back to the lane


