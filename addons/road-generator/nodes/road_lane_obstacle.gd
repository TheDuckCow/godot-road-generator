class_name RoadLaneObstacle
extends RefCounted

## RoadLaneObstacle is an entity that is "placed" on a RoadLane
## its main goal is for actors to be aware of its environment
## for decision making
## specifically whats going on on the current and side lanes
## obstacle is linked ot its main node and to obstacles in front
## and back of it

enum Flags {
	REAL = 0x0, # the node is on this lane
	IMMINENT = 0x1, # the node from another lane won't be able to stop before it gets to this position
	PARTIAL = 0x2, # the node is from another lane but it partially blocks this lane
	LANE_END = 0x8, # end of the lane sequence (no link to the beginning)
}
const END_OFFSET_MAX = 5.0
const DEBUG_OUT := 0 # 1 for obstacle lists, 2 for actions. 3 for everything
const ENABLE_HEAVY_CHECKS := false # turning on checks in this module that require significant time. use for development and debugging.

var visualize_lane : bool

var flags := RoadLaneObstacle.Flags.REAL
var lane: RoadLane: #set through assign_position or move_along_lane
	get:
		return _lane
	set(val):
		assert(false)

var offset: float: #set through assign_position or move_along_lane
	get:
		return _offset
	set(val):
		assert(false)

var _lane: RoadLane
var _offset: float
var node: Node3D
## next and prior obstacles links
var sequential_obstacles: Array[RoadLaneObstacle] = [null, null]

## approximate speed an obstacle on lane (m/s)
## for example if actor moves with an angle from tangent, its obstacle's speed
## should be just a fraction (dependent on the angle) of actor's speed
## Note: the obstacle won't be moved along lane automatically
var speed: float

func _init(visualize_lane := false) -> void:
	self.visualize_lane = visualize_lane

## is obstacle active (is on lane)
func is_assigned() -> bool:
	return self._lane != null

## distance from this obstacle to beginning (RoadLane.MoveDir.BACKWARD) or end (RoadLane.MoveDir.FORWARD) of the RoadLane its assigned to
func distance_to_end(dir: RoadLane.MoveDir) -> float:
	assert(check_sanity(true))
	return self.lane.offset_from_end(self.offset, dir)

## various sanity checks for the obstacle
## check_end - obstacle should always be linked forward (except LANE_END flagged, which never is)
## check_list - obstacle linkage must be correct
func check_sanity(check_end := false, check_list := true) -> bool:
	if ! ENABLE_HEAVY_CHECKS:
		return true
	var all_good := true
	if !(self.flags & RoadLaneObstacle.Flags.LANE_END):
		if !is_instance_valid(self.node):
			print(self, " Obst. has invalid node ", self.node)
			all_good = false
	else:
		if self.node != null:
			print(self, " Obst. is an end obstacle and has a node set ", self.node)
			all_good = false
	if check_list:
		for dir in RoadLane.MoveDir.values():
			var dir_back := RoadLane.reverse_move_dir(dir)
			var seq_obstacle := self.sequential_obstacles[dir]
			if ! seq_obstacle:
				continue
			if seq_obstacle == self:
				print(self, " Obst. linked to itself in direction ", RoadLane.MoveDir.find_key(dir))
				all_good = false
				continue
			if seq_obstacle.sequential_obstacles[dir_back] != self:
				print(self, " Obst. sequential obstacle ", seq_obstacle, " in direction ", RoadLane.MoveDir.find_key(dir), " is not linked back, instead to ", seq_obstacle.sequential_obstacles[dir_back])
				all_good = false
			if !seq_obstacle.is_assigned():
				print(self, " Obst. linked to ", seq_obstacle, " in direction ", RoadLane.MoveDir.find_key(dir), " that is not assigned to a lane")
				all_good = false
			else:
				if ENABLE_HEAVY_CHECKS:
					var found := false
					var lane := self.lane;
					while lane && !found:
						if seq_obstacle.lane == lane: #TODO multilane
							found = true
						lane = lane.get_sequential_lane(dir)
					if !found:
						print(self, " Obst. linked to ", seq_obstacle, " in direction ", RoadLane.MoveDir.find_key(dir), " that is not in the lane sequence in that direction")
						all_good = false
	if self.lane == null:
		return all_good
	if !is_instance_valid(self.lane):
		print(self, " Obst. has invalid lane ", self.lane)
		all_good = false
	else:
		if self.flags & RoadLaneObstacle.Flags.LANE_END:
			if check_end && check_list && self.sequential_obstacles[RoadLane.MoveDir.FORWARD] != null:
				print(self, " lane end Obst. linked to something forward ", self.sequential_obstacles[RoadLane.MoveDir.FORWARD])
				all_good = false
		else:
			if check_end && check_list && self.sequential_obstacles[RoadLane.MoveDir.FORWARD] == null:
				print(self, " Obst. not a lane end but isn't linked forward")
				all_good = false
		if bool(self.flags & RoadLaneObstacle.Flags.LANE_END) != (self == self.lane._end_obstacle):
			print(self, " Obst. conflict between end obstacle(", self == self.lane._end_obstacle, ") and flags ", self.flags)
			all_good = false
		if self not in self.lane.obstacles && !(self.flags & RoadLaneObstacle.Flags.LANE_END):
			print(self, " Obst. is not registered in ", self.lane)
			all_good = false
		if self.offset < 0:
			print(self, " Obst. has negative offset ", self.offset)
			all_good = false
		elif self.offset > self.lane.curve.get_baked_length():
			print(self, " Obst. has too big offset ", self.offset, " - lane's length is ", self.lane.curve.get_baked_length())
			all_good = false
	return all_good


## insert the obstacle after specific 'next' in the double-linked list of obstacles
func _insert_in_obstacle_list(next: RoadLaneObstacle, dir: RoadLane.MoveDir) -> void:
	if next == null:
		return
	assert(check_sanity(false, false))
	var dir_back := RoadLane.reverse_move_dir(dir)
	var prior := next.sequential_obstacles[dir_back]
	if DEBUG_OUT & 1:
		prints(self, "inserting in obstacle list before", next, "after", prior, "(direction", RoadLane.MoveDir.find_key(dir), ")")
	next.sequential_obstacles[dir_back] = self
	self.sequential_obstacles[dir] = next
	if prior:
		assert(prior.sequential_obstacles[dir] == next)
		prior.sequential_obstacles[dir] = self
		self.sequential_obstacles[dir_back] = prior
	assert(check_sanity())

## remove the obstacle in the double-linked list of obstacles
func _remove_from_obstacle_list() -> void:
	if self.sequential_obstacles[RoadLane.MoveDir.FORWARD] == null: # linking disabled
		return
	assert(check_sanity())
	if DEBUG_OUT & 1:
		prints(self, "removing from obstacle list linked to", self.sequential_obstacles)
	for dir in RoadLane.MoveDir.values():
		var seq_obstacle = self.sequential_obstacles[dir]
		if seq_obstacle:
			var dir_back := RoadLane.reverse_move_dir(dir)
			assert(seq_obstacle.sequential_obstacles[dir_back] == self)
			seq_obstacle.sequential_obstacles[dir_back] = self.sequential_obstacles[dir_back]
	for dir in RoadLane.MoveDir.values():
		self.sequential_obstacles[dir] = null
	assert(check_sanity(false))

## update obstacle search array in the lane sequence
func _update_lane_sequence(dir: RoadLane.MoveDir, from: RoadLaneObstacle, to: RoadLaneObstacle) -> void:
	assert(check_sanity())
	var lane = self.lane
	var offset = self.offset
	while lane:
		var done := lane._replace_next_obstacle(offset, from, to, dir)
		if done:
			return
		lane = lane.get_sequential_lane(RoadLane.MoveDir.BACKWARD)
		offset = INF
	assert(check_sanity())

## used for sanity check that clean up (when removed from the lane) was successful
func _is_in_lane_sequence() -> bool:
	var lane := self.lane
	for dir in RoadLane.MoveDir.values():
		while lane:
			if lane.is_in_next_obstacles(self):
				print(self, " is in the next_obstacles list on ", lane )
				return true
			lane = lane.get_sequential_lane(dir)
	return false

## insert the obstacle in the double-linked list of obstacles
func _insert_to_list() -> void:
	assert(check_sanity(false, false))
	assert(self.sequential_obstacles[RoadLane.MoveDir.FORWARD] == null)
	assert(self.sequential_obstacles[RoadLane.MoveDir.BACKWARD] == null)
	var next := self.lane.find_next_obstacle(self.offset) #all lane sequences must end with an obstacle for obstacle search reasons
	if next:
		assert(next != self)
		self._insert_in_obstacle_list(next, RoadLane.MoveDir.FORWARD)
		self._update_lane_sequence(RoadLane.MoveDir.FORWARD, next, self)
		assert(check_sanity())

## remove obstacle from both list and search array
func _remove_from_list() -> void:
	assert(check_sanity())
	self._update_lane_sequence(RoadLane.MoveDir.FORWARD, self, self.sequential_obstacles[RoadLane.MoveDir.FORWARD])
	if ENABLE_HEAVY_CHECKS:
		if self._is_in_lane_sequence():
			assert(false)
	self._remove_from_obstacle_list()
	assert(check_sanity(false))

## set obstacle position on lane and _register it
func _place_to(lane: RoadLane, offset: float, _register := true) -> void:
	if DEBUG_OUT & 2:
		print(self, " assigning position ", offset, " on ", lane )
	var lane_update := _register && lane != self.lane
	if lane_update && self.lane:
		self.lane.unregister_obstacle(self)
	self._lane = lane
	self._offset = offset
	if lane_update:
		lane.register_obstacle(self)
	assert(self.check_sanity(false, false))

## put obstacle on a lane and _register it
## insert in the obstacle list and search array
func assign_position(lane: RoadLane, offset: float, _register := true) -> void:
	if self.is_assigned():
		assert(_register == (self in self.lane.obstacles))
		self.unassign_position(_register)
	self._place_to(lane, offset, _register)
	self._insert_to_list()

## remove obstacle from the lane it is on and _unregister it
## remove from obstacle list and search array
func unassign_position(_unregister := true) -> void:
	if DEBUG_OUT & 2:
		print(self, " unassigning position")
	self._remove_from_list()
	if _unregister:
		self.lane.unregister_obstacle(self)
	self._lane = null
	self._offset = NAN

## when changing obstacle position while it just moved along the lane
## to not update search arrays and obstacle list
## when it has to jump over an obstacle (because new offset overcome an offset of next)
##   it will essentially remove and add it again automatically
## TODO moving backwards
func move_along_lane(lane: RoadLane, offset: float, dir: RoadLane.MoveDir) -> void:
	assert(check_sanity())
	if DEBUG_OUT & 2:
		prints(self, "moving obstacle along lane")
	var seq_obstacle := self.sequential_obstacles[dir]
	if seq_obstacle:
		var jump_over := false
		if lane != self.lane:
			assert(self.lane.get_sequential_lane(dir) == lane) #can fail for very short lanes #TODO store lane-to-index for road lane sequence in road manager?
			if seq_obstacle.lane == self.lane:
				jump_over = true
		if seq_obstacle.lane == lane && seq_obstacle.offset < offset:
			jump_over = true
		if jump_over:
			if DEBUG_OUT & 2:
				prints(self, "jumps over an obstacle")
			self._remove_from_list()
			self._place_to(lane, offset)
			self._insert_to_list()
			return
	self._place_to(lane, offset)
	_update_lane_sequence(dir, seq_obstacle, self)
	assert(self.check_sanity())

## get global position of the obstacle
func get_position() -> Vector3:
	if !is_assigned():
		return Vector3.INF
	return self.lane.to_global(self.lane.curve.sample_baked(self.offset))
