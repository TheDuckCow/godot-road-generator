extends Node3D

## NOTE: it's a convention to have a root point of the vehicle at the center of the rear axle
## reason is - it shouldn't move sideways and the car can normally only rotate around that point
## at the same time front weels are actually the ones that should follow the lane curve.
## for that reason the point that moves on the lane curve is the center of the front axle, and
## where the RoadLaneAgent actually is - the back one is calculated as being dragged

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
@export var forward_speed := 30.0  # in meters per sec (can't be 0)
@export var reverse_speed := 5.0  # in meters per sec (can't be 0)
@export var visualize_lane := false # show lane for debugging
@export var rotate_to_distance := 0.5 # How many meters in front of agent to seek rotation
@export var keep_distance := 0.5 # minimal distance
@export var safe_headway := 1.5 # how big a distance in seconds (depends on speed)
@export var sleep_velocity := 0.025 # stop the vehicle completely for small velocity
@export var half_width := 1.0 # half the width of the vehicle; will be used for oblong distance calcuation
@export var length : Array[float] = [1, 3]  # length of the vehicle from the root point (FORWARD, BACKWARD); will be used on on-lane distance calculation

@onready var agent:RoadLaneAgent = get_node("%road_lane_agent")

# how big car difference triggers lane change
var lane_change_tolerance = 3

var velocity := Vector3.ZERO
var front_axle := Vector3.ZERO # root point is on the rear axle. this one is on the front axle

const transition_time_close := 0.05 # how close to end of a transition lane actor has to switch lane

const DEBUG_OUT: bool = false

func _ready() -> void:
	if drive_state != DriveState.PLAYER:
		forward_speed = randf_range(forward_speed_min, forward_speed_max)
	agent.visualize_lane = visualize_lane
	agent.agent_pos.node = self
	if DEBUG_OUT:
		print("Agent state: %s par, %s lane (%s offset), %s manager" % [
			agent.actor, agent.agent_pos.lane if agent.agent_pos else null, agent.agent_pos.offset if agent.agent_pos else NAN, agent.road_manager
		])


## Generic function to calc speed
func get_signed_speed() -> float:
	return -velocity.z


func get_input(obstacle: RoadLane.Obstacle, obstacle_dist: float) -> Vector3:
	match drive_state:
		DriveState.AUTO:
			return _get_auto_input(obstacle, obstacle_dist)
		DriveState.PLAYER:
			return _get_player_input()
		_:
			return Vector3.ZERO

## For more info see Intelligent driver model
## https://en.wikipedia.org/wiki/Intelligent_driver_model
func _compute_idm_acceleration(obstacle: RoadLane.Obstacle, obstacle_dist: float) -> float:
	const delta_exp := 4.0 # constant emulating acceleration/braking profile
	var speed := self.get_signed_speed() # if delta_exp is changed from even, make speed abs
	var target_speed := forward_speed
	var accela := acceleration
	var breaka := breaking
	var dyn_accel = accela * (1 - pow(speed / target_speed, delta_exp))
	var reversed_move := speed < 0
	if reversed_move:
		dyn_accel = acceleration
		accela = breaking
		breaka = acceleration
	if obstacle:
		assert(obstacle_dist >= 0)
		var speed_lead: float = obstacle.speed
		var gap := obstacle_dist - keep_distance
		if gap <= 0.0:
			dyn_accel = -breaka
		else:
			var s_star := ( keep_distance + speed * safe_headway +
				(speed * (speed - speed_lead)) / (2 * sqrt(accela * breaka)) )
			dyn_accel -= accela * sign(s_star) * pow(s_star / gap, 2)
	dyn_accel = clamp(dyn_accel, -accela, breaka)
	return dyn_accel

func _get_auto_input(obstacle: RoadLane.Obstacle, obstacle_dist: float)-> Vector3:
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
	var dyn_accel := _compute_idm_acceleration(obstacle, obstacle_dist)

	return Vector3(lane_move, 0, dyn_accel)

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

func _process_collision(other) -> void:
	const elasticity := 1.2 # 1.0 - fully elastic, 0.0 - fully inelastic; 1.2 just for fun
	var self_mass := 1.0
	var other_mass := 1.0
	var self_speed := self.velocity.z
	var other_speed: float = other.velocity.z
	self.velocity.z = ((self_mass - elasticity * other_mass) * self_speed + (1 + elasticity) * other_mass * other_speed) / (self_mass + other_mass)
	other.velocity.z = ((other_mass - elasticity * self_mass) * other_speed + (1 + elasticity) * self_mass * self_speed) / (self_mass + other_mass)

func _move_to_next_lane() -> void:
	var dir := agent.agent_move.move_dir()
	var primary_lane := agent.agent_pos.lane.get_primary_lane(dir)
	if primary_lane:
		var next_pos = agent.continue_along_side_lane(primary_lane)
		global_transform.origin = next_pos
	#else:
		#workaround for missing connections
		#var next_lane = agent.find_nearest_lane(global_transform.origin - global_transform.basis.z * agent.agent_move.dir_sign, 1)
		#if is_instance_valid(next_lane) && next_lane != agent.agent_pos.lane: # TODO: it's still possible to find merging transition lanes
			#var next_pos = agent.continue_along_new_lane(next_lane)
			#global_transform.origin = next_pos

# distance is not precise(can be bigger in corner cases) for performance reasons
func segment_distance_fast(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3) -> float:
	const EPS := 1e-8
	var u := a1 - a0
	var v := b1 - b0
	var w := a0 - b0
	var a := u.dot(u)
	var b := u.dot(v)
	var c := v.dot(v)
	var d := u.dot(w)
	var e := v.dot(w)
	var D := a * c - b * b
	var s = clamp((b * e - c * d) / D, 0.0, 1.0) if D > EPS else 0.0
	var t = clamp((s * b + e) / c, 0.0, 1.0) if c > EPS else 0.0
	s = clamp((t * b - d) / a, 0.0, 1.0) if a > EPS else 0.0
	return (a0 + u * s).distance_to(b0 + v * t)


# find distance to another RoadActor
func distance_to_other(other) -> float:
	var dist :float
	const MIN_POINT_DISTANCE_SQUARED := 2500.0 # at this squared distance we can assume that the car is a point
	#const MIN_OBLONG_DISTANCE_SQUARED := 100.0 # at this squared distance we can assume that the car is an expanded segment (capsule) #TODO: rectangle
	var dist_sq_to_root :float = self.global_position.distance_squared_to(other.global_position)
	if dist_sq_to_root >= MIN_POINT_DISTANCE_SQUARED:
		return sqrt(dist_sq_to_root)
	else: # if dist_to_start >= MIN_OBLONG_DISTANCE_SQUARED #TODO: rectangle
		dist = segment_distance_fast(self.front_axle, self.global_position, other.front_axle, other.global_position) - self.half_width - other.half_width
		return dist if dist > 0 else 0
	# else: #TODO: rectangle

# find distance to another RoadActor
# first look on the current+next lanes to make it fast in 1D.
# only use it for obstacle in front
func distance_to_other_sequential(obstacle: RoadLane.Obstacle) -> float:
	var dist :float
	if self.agent.agent_pos.lane == obstacle.lane:
		dist = (obstacle.offset - obstacle.node.length[RoadLane.MoveDir.BACKWARD]) - (self.agent.agent_pos.offset + self.length[RoadLane.MoveDir.FORWARD])
		return dist if dist > 0 else 0
	if self.agent.agent_pos.lane.get_sequential_lane(RoadLane.MoveDir.FORWARD) == obstacle.lane:
		dist = (obstacle.distance_to_end(RoadLane.MoveDir.BACKWARD) - obstacle.node.length[RoadLane.MoveDir.BACKWARD]) + (self.agent.agent_pos.distance_to_end(RoadLane.MoveDir.FORWARD) - self.length[RoadLane.MoveDir.FORWARD])
		return dist if dist > 0 else 0
	return distance_to_other(obstacle.node)


func _physics_process(delta: float) -> void:
	if ! agent.is_lane_position_valid():
		var res = agent.assign_nearest_lane()
		if not res == OK:
			print("Failed to find new lane")
			queue_free()
			return

	velocity.y = 0
	var move_dir := RoadLane.MoveDir.FORWARD #TODO obstacle list update not ready for reverse... RoadLane.MoveDir.BACKWARD if self.get_signed_speed() < 0 else RoadLane.MoveDir.FORWARD

	var obstacle := self.agent.agent_pos.sequential_obstacles[move_dir]
	var obstacle_dist := self.distance_to_other_sequential(obstacle) if obstacle.flags & RoadLane.Obstacle.ObstacleFlags.LANE_END == 0 else INF
	#if self.agent.agent_pos_secondary.check_sanity():
	#	assert(false) #TODO if closer on seconary
	var target_dir:Vector3 = get_input(obstacle, obstacle_dist)
	var old_velocity := velocity.z
	velocity.z -= delta * target_dir.z
	if old_velocity && sign(old_velocity) != sign(velocity.z):
		velocity.z = 0
	velocity.z = clamp(velocity.z, -forward_speed * 2, 0) # TODO reverse_speed * 2) #obstacle list update not ready for reverse
	if abs(velocity.z) < sleep_velocity:
		velocity.z = 0

	move_dir = RoadLane.MoveDir.BACKWARD if self.get_signed_speed() < 0 else RoadLane.MoveDir.FORWARD

	agent.agent_pos.speed = self.get_signed_speed()

	var lane_change := int(target_dir.x)
	if lane_change:
		var next_obstacle_side = agent.find_obstacle_on_side_lane(lane_change)
		var obstacle_dist_side = self.distance_to_other(next_obstacle_side.node) if next_obstacle_side.flags & RoadLane.Obstacle.ObstacleFlags.LANE_END == 0 else INF
		#TODO var prev_obstacle_side = next_obstacle_side.prev_obstacle
		if obstacle_dist_side == 0:
			lane_change = 0;
		agent.change_lane(lane_change)
		if lane_change:
			#TODO
			pass

	# Find the next position to jump to; note that the car's forward is the
	# negative Z direction (conventional with Vector3.FORWARD), and thus
	# we flip the direction along the Z axis so that positive move direction
	# matches a positive move_along_lane call, while negative would be
	# going in reverse in the lane's intended direction.
	var move_dist:float = get_signed_speed() * delta

	var collided = false
	if obstacle_dist < abs(move_dist):
		move_dist = sign(move_dist) * obstacle_dist
		collided = true

	var next_pos: Vector3 = agent.move_along_lane(move_dist)
	global_transform.origin = next_pos # has to set it before switching lanes (in case if we move to the end of the lane)
	if agent.agent_move.lane_sequence_end:
		#assert(!collided)
		_move_to_next_lane()
	elif collided:
		_process_collision(obstacle.node)

	# Get another point a little further in front for orientation seeking,
	# without actually moving the vehicle (ie don't update the assign lane
	# if this margin puts us into the next lane in front)
	var orientation:Vector3 = agent.test_move_along_lane(rotate_to_distance)

	if ! global_transform.origin.is_equal_approx(orientation):
		look_at(orientation, Vector3.UP)
