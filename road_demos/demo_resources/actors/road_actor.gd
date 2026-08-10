extends Node3D

## NOTE: it's a convention to have a root point of the vehicle at the center of the rear axle
## reason is - it shouldn't move sideways and the car can normally only rotate around that point.
## at the same time front wheels are actually the ones that should follow the lane curve.
## for that reason the center of the front axle will be a root point (and position of RoadLaneAgend),
## and the rear axle center is calculated as being dragged fron the new point
## These 2 points is at the same time are used for the capsule for distance calculation

enum DriveState {
	PARK,
	AUTO,
	PLAYER
}

@export var drive_state: DriveState = DriveState.AUTO
@export var rotate_to_distance := 0.5 # How many meters in front of agent to seek rotation
# Target speed in meters per second
@export var acceleration := 10.0 # in meters per sec squared
@export var breaking := 20.0 # in meters per sec squared
@export var forward_speed_min := 15.0  # in meters per sec
@export var forward_speed_max := 30.0  # in meters per sec
@export var forward_speed := 30.0  # in meters per sec (can't be 0)
@export var reverse_speed := 5.0  # in meters per sec (can't be 0)
@export var visualize_lane := false # show lane for debugging
@export var keep_distance := 0.5 # minimal distance
@export var safe_headway := 1.5 # how big a distance in seconds (depends on speed)
@export var sleep_velocity := 0.025 # stop the vehicle completely for small velocity
@export var half_width := 1.0 # half the width of the vehicle; will be used for oblong distance calcuation
@export var length : Array[float] = [1.0, 4.0]  # length of the vehicle from the root point (FORWARD, BACKWARD); will be used on on-lane distance calculation
@export var rear_axle_offset := 2.8  # root point is on the front axle. this one an offset by z for rear axle

@onready var agent:RoadLaneAgent = get_node("%road_lane_agent")

# how big car difference triggers lane change
var lane_change_tolerance = 3

var velocity_on_lane := 0.0
var secondary_obstacle :RoadLaneObstacle # used for notifications on lane change/merge/diverge/intersections #TODO pooling?

const transition_time_close := 0.05 # how close to end of a transition lane actor has to switch lane

# these two are fr getting info from the function find_obstacle
var _obstacle : RoadLaneObstacle
var _obstacle_distance : float
var _last_lane : RoadLane

const DEBUG_OUT: bool = false

func _ready() -> void:
	if drive_state != DriveState.PLAYER:
		self.forward_speed = randf_range(self.forward_speed_min, self.forward_speed_max)
	self.agent.visualize_lane = self.visualize_lane
	self.agent.lane_position.node = self
	if DEBUG_OUT:
		print("Agent state: %s par, %s lane (%s offset), %s manager" % [
			agent.actor, agent.lane_position.lane if agent.lane_position else null, agent.lane_position.offset if agent.lane_position else NAN, agent.road_manager
		])
	self.secondary_obstacle = RoadLaneObstacle.new(visualize_lane)
	self.secondary_obstacle.node = self
	self.secondary_obstacle.flags = RoadLaneObstacle.Flags.PARTIAL


func cleanup_for_reuse() -> void:
	agent.unassign_lane()
	secondary_obstacle.unassign_position()
	assert(agent.lane_position.next_obstacle == null && agent.lane_position.prior_obstacle == null)
	assert(secondary_obstacle.next_obstacle == null && secondary_obstacle.prior_obstacle == null)

func _exit_tree() -> void:
	secondary_obstacle.unassign_position() # agent and its obstacle will unassign itself

## Generic function to calc speed
func get_signed_speed() -> float:
	return -velocity_on_lane

## get input from player or ai actor
## returns Vector3 with .x being change in lane and .z being acceleration. .y is unused
func get_input(obstacle: RoadLaneObstacle, obstacle_dist: float) -> Vector3:
	match drive_state:
		DriveState.AUTO:
			return _get_auto_input(obstacle, obstacle_dist)
		DriveState.PLAYER:
			return _get_player_input()
		_:
			return Vector3.ZERO


## For more info see Intelligent driver model
## https://en.wikipedia.org/wiki/Intelligent_driver_model
func _compute_idm_acceleration(obstacle: RoadLaneObstacle, obstacle_dist: float) -> float:
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
		var speed_lead: float = obstacle.node.get_signed_speed()
		var gap := obstacle_dist - keep_distance
		if gap <= 0.0:
			dyn_accel = -breaka
		else:
			var s_star := ( keep_distance + speed * safe_headway +
				(speed * (speed - speed_lead)) / (2 * sqrt(accela * breaka)) )
			dyn_accel -= accela * sign(s_star) * pow(s_star / gap, 2) #sign(s_star) change here is for trying to evade and going backwards
	dyn_accel = clamp(dyn_accel, -accela, breaka)
	return dyn_accel

#TODO backward motion intelligent model (decision making currently only sees forward obstacle)
#TODO doesn't matter too much as backward actor will try to evade as well
func _get_auto_input(obstacle: RoadLaneObstacle, obstacle_dist: float)-> Vector3:
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
	var self_speed := self.velocity_on_lane
	var other_speed: float = other.velocity_on_lane
	self.velocity_on_lane = ((self_mass - elasticity * other_mass) * self_speed + (1 + elasticity) * other_mass * other_speed) / (self_mass + other_mass)
	other.velocity_on_lane = ((other_mass - elasticity * self_mass) * other_speed + (1 + elasticity) * self_mass * self_speed) / (self_mass + other_mass)


func _move_to_next_lane() -> void:
	var dir := agent.get_move_dir_by_move_distance(agent.move_along_lane_distance_left)
	var primary_lane := agent.lane_position.lane.get_primary_lane(dir)
	if primary_lane:
		var next_pos = agent.continue_along_side_lane(primary_lane)
		global_transform.origin = next_pos
	#else:
		#workaround for missing connections
		#var next_lane = agent.find_nearest_lane(global_transform.origin - global_transform.basis.z * agent.move.dir_sign, 1)
		#if is_instance_valid(next_lane) && next_lane != agent.lane_position.lane: # TODO: it's still possible to find merging transition lanes
			#var next_pos = agent.continue_along_new_lane(next_lane)
			#global_transform.origin = next_pos


## distance between 2 segments
## reported distance is not precise - can bigger in corner cases for performance reasons
static func segment_distance_fast(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3) -> float:
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


## find approximate distance between two RoadActors
## can't use `self` as they may not be in order
## precision works in stages. using squared distance between root points decide how precise the distance we will have
## INF or distance between: root points, capsules or rectangles
## TODO will it make sense to check with bounding box first?
static func distance_between(first, second) -> float:
	const MIN_INF_DISTANCE_SQUARED := 250000.0 # 500m at this squared distance we can assume that the obstacle is not there
	const MIN_POINT_DISTANCE_SQUARED := 2500.0 # 50m at this squared distance we can assume that the obstacle is a point
	#const MIN_OBLONG_DISTANCE_SQUARED := 100.0 # 10m at this squared distance we can assume that the car is an expanded segment (capsule) #TODO: rectangle
	var dist :float
	var dist_sq_to_root :float = first.global_position.distance_squared_to(second.global_position)
	if dist_sq_to_root >= MIN_POINT_DISTANCE_SQUARED:
		return INF if dist_sq_to_root >= MIN_INF_DISTANCE_SQUARED else sqrt(dist_sq_to_root)
	else: # if dist_to_start >= MIN_OBLONG_DISTANCE_SQUARED #TODO: rectangle
		dist = segment_distance_fast(first.global_position,
									first.global_position + first.global_basis.z * first.rear_axle_offset,
									second.global_position,
									second.global_position + second.global_basis.z * second.rear_axle_offset) - first.half_width - second.half_width
		return max(0, dist)
	# else: #TODO: rectangle


## find distance between two RoadActors (through obstacles) in the current lane
## first look on the current+next lanes to make it fast in 1D.
## use it only for obstacles on the same lane sequence - in order!
## if distance on lane is less than need_direct_distance, calculate precise - for faster calculation on side lane
static func distance_between_sequential(rear: RoadLaneObstacle, front: RoadLaneObstacle) -> float:
	const MIN_REAL_DISTANCE_PARTIAL := 10.0 # 10m at this distance distance on lane is good enough even for partial blocks
	var need_direct_distance = -INF if ((rear.flags | front.flags) & RoadLaneObstacle.Flags.PARTIAL) == 0 else MIN_REAL_DISTANCE_PARTIAL
	var dist :float
	if rear.lane == front.lane:
		dist = (front.offset - front.node.length[RoadLane.MoveDir.BACKWARD]) - (rear.offset + rear.node.length[RoadLane.MoveDir.FORWARD])
		if dist > need_direct_distance:
			return max(0, dist)
	var next_lane := rear.lane.get_sequential_lane(RoadLane.MoveDir.FORWARD)
	if next_lane && next_lane == front.lane:
		dist = (front.distance_to_end(RoadLane.MoveDir.BACKWARD) - front.node.length[RoadLane.MoveDir.BACKWARD]) + (rear.distance_to_end(RoadLane.MoveDir.FORWARD) - rear.node.length[RoadLane.MoveDir.FORWARD])
		if dist > need_direct_distance:
			return max(0, dist)
	return distance_between(rear.node, front.node)


## find closest obstacle for collision detection and decision making
## sets _obstacle and _obstacle_distance
func find_obstacle(move_dir : RoadLane.MoveDir) -> void:
	_obstacle = null
	_obstacle_distance = INF
	_obstacle = self.agent.lane_position.sequential_obstacles[move_dir]
	if _obstacle && (_obstacle.flags & RoadLaneObstacle.Flags.LANE_END) == 0:
		if move_dir == RoadLane.MoveDir.FORWARD:
			_obstacle_distance = self.distance_between_sequential(self.agent.lane_position, _obstacle)
		else:
			_obstacle_distance = self.distance_between_sequential(_obstacle, self.agent.lane_position)
	else:
		_obstacle = null #no need to pass lane end to decision making or collsion
	if self.secondary_obstacle.is_assigned():
		var next_obstacle_secondary = secondary_obstacle.sequential_obstacles[move_dir]
		if next_obstacle_secondary && (next_obstacle_secondary.flags & RoadLaneObstacle.Flags.LANE_END) == 0:
			var obstacle_secondary_dist : float
			if move_dir == RoadLane.MoveDir.FORWARD:
				obstacle_secondary_dist = self.distance_between_sequential(self.secondary_obstacle, next_obstacle_secondary)
			else:
				obstacle_secondary_dist = self.distance_between_sequential(next_obstacle_secondary, self.secondary_obstacle)
			if obstacle_secondary_dist < _obstacle_distance:
				_obstacle = next_obstacle_secondary
				_obstacle_distance = obstacle_secondary_dist


## setting additional obstacle on primary lane in case of merging/diverging lanes
## TODO better processing for partial obstacle
func set_secondary_obstacle(move_dir : RoadLane.MoveDir) -> void:
	var current_lane := self.agent.lane_position.lane
	assert(!(bool(current_lane.flags & RoadLane.Flags.MERGING) && bool(current_lane.flags & RoadLane.Flags.DIVERGING))) # TODO should be possible in intersections
	if _last_lane != current_lane && self.secondary_obstacle.is_assigned(): #TODO do it on lane change only?
		self.secondary_obstacle.unassign_position()
	var secondary_lane :RoadLane
	if (current_lane.flags & RoadLane.Flags.MERGING) != 0:
		secondary_lane = current_lane._lane_merge_to_ptr
	elif (current_lane.flags & RoadLane.Flags.DIVERGING) != 0:
		secondary_lane = current_lane._lane_diverge_from_ptr
	assert(!secondary_lane || !(bool(secondary_lane.flags & RoadLane.Flags.MERGING) && bool(secondary_lane.flags & RoadLane.Flags.DIVERGING)))
	if secondary_lane:
		var secondary_offset := self.agent.project_on_side_lane(secondary_lane)
		if self.secondary_obstacle.is_assigned():
			assert(self.secondary_obstacle.lane == secondary_lane)
			self.secondary_obstacle.move_along_lane_to(secondary_lane, secondary_offset, move_dir)
		else:
			self.secondary_obstacle.assign_position(secondary_lane, secondary_offset )
	_last_lane = current_lane


func _physics_process(delta: float) -> void:
	if ! agent.is_lane_position_valid(): # move player to the lane initially
		var res = agent.assign_nearest_lane()
		if not res == OK:
			print("Failed to find new lane")
			queue_free()
			return
		global_transform.origin = self.agent.lane_position.get_position()
		# Get another point a little further in front for orientation seeking,
		# without actually moving the vehicle (ie don't update the assign lane
		# if this margin puts us into the next lane in front)
		look_at(agent.test_move_along_lane(rotate_to_distance), Vector3.UP)

	find_obstacle(RoadLane.MoveDir.FORWARD)

	var target_dir:Vector3 = get_input(_obstacle, _obstacle_distance)
	var old_velocity := velocity_on_lane
	velocity_on_lane -= delta * target_dir.z
	if old_velocity && sign(old_velocity) != sign(velocity_on_lane):
		velocity_on_lane = 0
	velocity_on_lane = clamp(velocity_on_lane, -forward_speed * 2, reverse_speed * 2)
	if abs(velocity_on_lane) < sleep_velocity:
		velocity_on_lane = 0

	var move_dir := RoadLane.MoveDir.BACKWARD if self.get_signed_speed() < 0 else RoadLane.MoveDir.FORWARD
	if move_dir == RoadLane.MoveDir.BACKWARD:
		find_obstacle(RoadLane.MoveDir.BACKWARD)

	var lane_change := int(target_dir.x)
	if lane_change:
		const BLOCK_DISTANCE := 2.0
		#prevent lane change if another car is there
		assert(lane_change in [-1, 1])
		var next_obstacle_side: RoadLaneObstacle
		var prior_obstacle_side: RoadLaneObstacle
		var obstacle_dist_side : float = INF
		if self.secondary_obstacle.is_assigned() && self.agent.lane_position.lane.get_side_lane(RoadLaneAgent.to_lane_side(lane_change)) == self.secondary_obstacle.lane:
			next_obstacle_side = self.secondary_obstacle.next_obstacle #we don't want to find our own secondary obstacle
			prior_obstacle_side = self.secondary_obstacle.prior_obstacle
			if next_obstacle_side && (next_obstacle_side.flags & RoadLaneObstacle.Flags.LANE_END) == 0:
				obstacle_dist_side = self.distance_between_sequential(self.secondary_obstacle, next_obstacle_side)
			if prior_obstacle_side && obstacle_dist_side > BLOCK_DISTANCE:
				obstacle_dist_side = min(obstacle_dist_side, self.distance_between_sequential(prior_obstacle_side, self.secondary_obstacle) )
		else:
			next_obstacle_side = agent.find_obstacle_on_side_lane(lane_change)
			prior_obstacle_side = next_obstacle_side.prior_obstacle if next_obstacle_side else null
			if next_obstacle_side && (next_obstacle_side.flags & RoadLaneObstacle.Flags.LANE_END) == 0:
				obstacle_dist_side = self.distance_between(self, next_obstacle_side.node)
			if prior_obstacle_side && obstacle_dist_side > BLOCK_DISTANCE:
				obstacle_dist_side = min(obstacle_dist_side, self.distance_between(self, prior_obstacle_side.node))

		if obstacle_dist_side < BLOCK_DISTANCE: #TODO: use lane width?
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
	var move_distance:float = get_signed_speed() * delta

	var collided = false
	if _obstacle_distance < abs(move_distance):
		move_distance = sign(move_distance) * _obstacle_distance
		collided = true

	#var prior_front_axle := self.global_position
	var next_pos: Vector3 = agent.move_along_lane(move_distance)
	global_transform.origin = next_pos # has to set it before switching lanes (in case if we move to the end of the lane)
	if agent.move_along_lane_distance_left != 0:
		_move_to_next_lane()
	elif collided:
		_process_collision(_obstacle.node)

	var orientation:Vector3 = global_transform.origin + global_transform.origin - agent.test_move_along_lane(-rear_axle_offset) #attach front and rear axle centers to the curve #TODO KBM
	if ! orientation.is_zero_approx():
		look_at(orientation, Vector3.UP)

	# TODO Kinematic Bicycle Model - too tricky in reverse to make it work now
	#var max_dtheta_per_sec: float = deg_to_rad(30.0)
	#var max_dtheta_per_step = max_dtheta_per_sec * delta
	#var delta_move: Vector3 = self.global_position - prior_front_axle
	#if !delta_move.is_zero_approx():
		#var up := global_basis.y
		#var forward := -global_basis.z
		#var right := up.cross(forward)
		#var lateral: float = delta_move.dot(right)
		#var dtheta: float = lateral / rear_axle_offset
		#dtheta = clamp(dtheta, -max_dtheta_per_step, max_dtheta_per_step)
		#global_transform.basis = global_transform.basis.rotated(up, dtheta)

	set_secondary_obstacle(move_dir)
