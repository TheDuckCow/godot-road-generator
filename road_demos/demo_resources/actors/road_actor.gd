extends Node3D

enum DriveState {
	PARK,
	AUTO,
	PLAYER
}

@export var drive_state: DriveState = DriveState.AUTO

# Target speed in meters per second
@export var acceleration := 10.0 # in meters per sec squared
@export var breaking := 20.0 # in meters per sec squared
@export var forward_speed_min := 15.0  # in meters per sec
@export var forward_speed_max := 30.0  # in meters per sec
@export var forward_speed := 30.0  # in meters per sec
@export var reverse_speed := 10.0  # in meters per sec
@export var visualize_lane := false
@export var rotate_to_distance := 0.5 # How many meters in front of agent to seek rotation
@export var auto_register: bool = true
@export var keep_distance := 2.0
@export var safe_headway := 1.5 # (secs)
@export var looking_forward := 50.0

@onready var agent:RoadLaneAgent = get_node("%road_lane_agent")

# how big car difference triggers lane change
var lane_change_tolerance = 3

var velocity := Vector3.ZERO

const transition_time_close := 0.05 # how close to end of a transition lane actor has to switch lane

var was_lane_end := false

const DEBUG_OUT: bool = false

func _ready() -> void:
	if drive_state != DriveState.PLAYER:
		forward_speed = randf_range(forward_speed_min, forward_speed_max)
	agent.visualize_lane = visualize_lane
	agent.agent_pos.node = self
	agent.agent_pos.end_offsets = [2.0, 2.0]
	if DEBUG_OUT:
		print("Agent state: %s par, %s lane (%s offset), %s manager" % [
			agent.actor, agent.agent_pos.lane if agent.agent_pos else null, agent.agent_pos.offset if agent.agent_pos else NAN, agent.road_manager
		])


## Generic function to calc speed
func get_signed_speed() -> float:
	return -velocity.z


func get_input() -> Vector3:
	match drive_state:
		DriveState.AUTO:
			return _get_auto_input()
		DriveState.PLAYER:
			return _get_player_input()
		_:
			return Vector3.ZERO


## For more info see Intelligent driver model
## https://en.wikipedia.org/wiki/Intelligent_driver_model
func compute_idm_acceleration(target_speed: float, accel: float, follow: bool) -> float:
	assert(target_speed != 0)
	const delta_exp := 4.0 # constant emulating acceleration/braking profile
	var speed := self.get_signed_speed() # if delta_exp is changed from even, make speed abs
	var dyn_accel := accel * (1 - pow(speed / target_speed, delta_exp))
	if follow:
		var vo_pair = agent.find_obstacle(looking_forward, RoadLaneAgent.MoveDir.FORWARD)
		var forward_distance: float = vo_pair[0]
		var forward_obstacle: RoadLane.Obstacle = vo_pair[1]
		if forward_obstacle:
			assert(forward_distance >= 0)
			var speed_lead: float = forward_obstacle.speed
			var gap := forward_distance - keep_distance
			var s_star := ( keep_distance + speed * safe_headway +
				(speed * (speed - speed_lead)) / (2 * sqrt(accel * breaking)) )
			dyn_accel -= accel * pow(s_star / max(gap, 0.1), 2)
	dyn_accel = clamp(dyn_accel, -breaking, acceleration)
	return dyn_accel


func player_breaking(decel: float) -> float:
	const speed_coeff = 2.0 # without it breaking on speed close to maximum is too slow
	return compute_idm_acceleration(forward_speed * speed_coeff, decel, false)


func _get_auto_input() -> Vector3:
	if ! agent.is_lane_position_valid():
		return Vector3.ZERO
	var lane_move:int = 0
	var cur_cars:int = agent.cars_in_lane(RoadLaneAgent.LaneChangeDir.CURRENT)
	if (cur_cars > 1):
		var cur_cars_l:int = agent.cars_in_lane(agent.LaneChangeDir.LEFT)
		var cur_cars_r:int = agent.cars_in_lane(agent.LaneChangeDir.RIGHT)
		if (cur_cars_l >= 0) && (cur_cars - cur_cars_l > lane_change_tolerance):
			lane_move -= 1
		elif (cur_cars_r >= 0) && (cur_cars - cur_cars_r > lane_change_tolerance):
			lane_move += 1
	var dyn_accel := compute_idm_acceleration(forward_speed, acceleration, true)

	return Vector3(lane_move, 0, dyn_accel)
	#return Vector3(0, 0, dyn_accel)


func _get_player_input() -> Vector3:
	if ! agent.is_lane_position_valid():
		return Vector3.ZERO

	var speed := self.get_signed_speed()
	var dyn_accel:float = 0

	var up := Input.is_action_pressed("ui_up")
	var down := Input.is_action_pressed("ui_down")
	if up == down:
		if speed != 0:
			dyn_accel -= sign(speed) * player_breaking(breaking / 2.0)
	elif up || down:
		var reversed_move: bool = speed < 0 #accelerate from low negative speeds
		if speed != 0 && up == reversed_move:
			dyn_accel -= sign(speed) * player_breaking(breaking)
		elif up:
			dyn_accel += compute_idm_acceleration(forward_speed, acceleration, false)
		elif down:
			dyn_accel -= compute_idm_acceleration(reverse_speed, acceleration, false)

	var lane_move:int = 0
	if Input.is_action_just_pressed("ui_left"):
		lane_move -= 1
	if Input.is_action_just_pressed("ui_right"):
		lane_move += 1
	return Vector3(lane_move, 0, dyn_accel)


func _physics_process(delta: float) -> void:
	velocity.y = 0
	var target_dir:Vector3 = get_input()
	velocity.z -= delta * target_dir.z
	velocity.z = clamp(velocity.z, -forward_speed * 2, reverse_speed * 2)

	agent.agent_pos.speed = self.get_signed_speed()

	agent.change_lane(int(target_dir.x))

	if ! agent.is_lane_position_valid():
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

	was_lane_end = false
	var next_pos: Vector3 = agent.move_along_lane(move_dist)
	global_transform.origin = next_pos # has to set it before switching lanes
	if agent.agent_move.block == RoadLaneAgent.MoveBlock.OBSTACLE:
		var other := agent.agent_move.obstacle.node
		var elasticity := 1.5 # more than fully elastic (1.0) just for the fun of it
		var self_mass := 1.0
		var other_mass := 1.0
		var self_speed := self.velocity.z
		var other_speed: float = other.velocity.z
		self.velocity.z = ((self_mass - elasticity*other_mass)*self_speed + (1 + elasticity)*other_mass*other_speed) / (self_mass + other_mass)
		other.velocity.z = ((other_mass - elasticity*self_mass)*other_speed + (1 + elasticity)*self_mass*self_speed) / (self_mass + other_mass)
	elif agent.agent_move.block == RoadLaneAgent.MoveBlock.NO_LANE:
		var dir: RoadLane.MoveDir = RoadLane.MoveDir.FORWARD if move_dist > 0 else RoadLane.MoveDir.BACKWARD
		var shared_part := agent.agent_pos.lane.shared_parts[dir]
		if shared_part && shared_part._primary_lane != agent.agent_pos.lane:
			next_pos = agent.continue_along_new_lane(shared_part._primary_lane)
			global_transform.origin = next_pos

	# Get another point a little further in front for orientation seeking,
	# without actually moving the vehicle (ie don't update the assign lane
	# if this margin puts us into the next lane in front)
	var orientation:Vector3 = agent.test_move_along_lane(rotate_to_distance)

	if ! global_transform.origin.is_equal_approx(orientation):
		look_at(orientation, Vector3.UP)
