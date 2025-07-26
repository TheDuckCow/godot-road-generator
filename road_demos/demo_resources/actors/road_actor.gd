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
@export var keep_distance := 0.5
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
	agent.agent_pos.end_offsets = [2.5, 2.5]
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
func _compute_idm_acceleration() -> float:
	const delta_exp := 4.0 # constant emulating acceleration/braking profile
	var speed := self.get_signed_speed() # if delta_exp is changed from even, make speed abs
	var vo_pair = agent.find_obstacle(looking_forward, RoadLaneAgent.MoveDir.FORWARD)
	var forward_distance: float = vo_pair[0]
	var forward_obstacle: RoadLane.Obstacle = vo_pair[1]
	var target_speed := forward_speed
	var accela := acceleration
	var breaka := breaking
	var dyn_accel = accela * (1 - pow(speed / target_speed, delta_exp))
	var reversed_move := speed < 0
	if reversed_move:
		dyn_accel = acceleration
		accela = breaking
		breaka = acceleration
	if forward_obstacle:
		assert(forward_distance >= 0)
		var speed_lead: float = forward_obstacle.speed
		var gap := forward_distance - keep_distance
		if gap <= 0.0:
			dyn_accel = -breaka
		else:
			var s_star := ( keep_distance + speed * safe_headway +
				(speed * (speed - speed_lead)) / (2 * sqrt(accela * breaka)) )
			dyn_accel -= accela * sign(s_star) * pow(s_star / gap, 2)
	dyn_accel = clamp(dyn_accel, -accela, breaka)
	return dyn_accel

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
	var dyn_accel := _compute_idm_acceleration()

	#return Vector3(lane_move, 0, dyn_accel)
	return Vector3(0, 0, dyn_accel)

func _compute_player_acceleration(target_speed: float, accel: float) -> float:
	const delta_exp := 4.0 # constant emulating acceleration/braking profile
	# if delta_exp is changed from even, make speed abs
	return accel * (1 - pow(self.get_signed_speed() / target_speed, delta_exp))

func _compute_player_breaking(decel: float) -> float:
	const speed_coeff = 2.0 # without it breaking on speed close to maximum is too slow
	return sign(self.get_signed_speed()) * _compute_player_acceleration(forward_speed * speed_coeff, decel)

func _get_player_input() -> Vector3:
	if ! agent.is_lane_position_valid():
		return Vector3.ZERO

	var speed := self.get_signed_speed()
	var dyn_accel:float = 0

	var up := Input.is_action_pressed("ui_up")
	var down := Input.is_action_pressed("ui_down")
	if up == down:
		if speed != 0:
			dyn_accel -= _compute_player_breaking(breaking / 2.0)
	elif up || down:
		var reversed_move := speed < 0
		if speed != 0 && up == reversed_move:
			dyn_accel -= _compute_player_breaking(breaking)
		elif up:
			dyn_accel += _compute_player_acceleration(forward_speed, acceleration)
		elif down:
			dyn_accel -= _compute_player_acceleration(-reverse_speed, acceleration)

	var lane_move:int = 0
	if Input.is_action_just_pressed("ui_left"):
		lane_move -= 1
	if Input.is_action_just_pressed("ui_right"):
		lane_move += 1
	return Vector3(lane_move, 0, dyn_accel)

func _process_collision() -> void:
	var other = agent.agent_move.obstacle.node
	var elasticity := 1.2 # 1.0 - fully elastic, 0.0 - fully inelastic; 1.2 just for fun
	var self_mass := 1.0
	var other_mass := 1.0
	var self_speed := self.velocity.z
	var other_speed: float = other.velocity.z
	self.velocity.z = ((self_mass - elasticity*other_mass)*self_speed + (1 + elasticity)*other_mass*other_speed) / (self_mass + other_mass)
	other.velocity.z = ((other_mass - elasticity*self_mass)*other_speed + (1 + elasticity)*self_mass*self_speed) / (self_mass + other_mass)

func _move_to_next_lane() -> void:
	var dir := agent.agent_move.move_dir()
	var shared_part := agent.agent_pos.lane.shared_parts[dir]
	if shared_part && shared_part._primary_lane != agent.agent_pos.lane:
		var next_pos = agent.continue_along_new_lane(shared_part._primary_lane)
		global_transform.origin = next_pos
	#else:
		#workaround for missing connections
		#var next_lane = agent.find_nearest_lane(global_transform.origin - global_transform.basis.z * agent.agent_move.dir_sign, 1)
		#if is_instance_valid(next_lane) && next_lane != agent.agent_pos.lane: # TODO: it's still possible to find merging transition lanes
			#var next_pos = agent.continue_along_new_lane(next_lane)
			#global_transform.origin = next_pos

func _physics_process(delta: float) -> void:
	velocity.y = 0
	var target_dir:Vector3 = get_input()
	velocity.z -= delta * target_dir.z
	velocity.z = clamp(velocity.z, -forward_speed * 2, reverse_speed * 2)
	if abs(velocity.z) < 0.025:
		velocity.z = 0

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
	global_transform.origin = next_pos # has to set it before switching lanes (in case if we move to the end of the lane)
	if agent.agent_move.block == RoadLaneAgent.MoveBlock.OBSTACLE:
		_process_collision()
	elif agent.agent_move.block == RoadLaneAgent.MoveBlock.NO_LANE:
		_move_to_next_lane()

	# Get another point a little further in front for orientation seeking,
	# without actually moving the vehicle (ie don't update the assign lane
	# if this margin puts us into the next lane in front)
	var orientation:Vector3 = agent.test_move_along_lane(rotate_to_distance)

	if ! global_transform.origin.is_equal_approx(orientation):
		look_at(orientation, Vector3.UP)
