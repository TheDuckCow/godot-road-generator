@tool
@icon("res://addons/road-generator/resources/road_lane.png")
class_name RoadLane
extends Path3D

const RoadSegment = preload("res://addons/road-generator/nodes/road_segment.gd")

## Defines a directional lane of traffic for AI with references to adjacent lanes.
##
## These are generated as children of [RoadPoint]'s automatically if its given
## [member RoadContainer.generate_ai_lanes] is set to true.
##
## @tutorial(Using RoadLanes with custom meshes): https://github.com/TheDuckCow/godot-road-generator/wiki/User-guide:-Custom-road-meshes
## @tutorial(Procedural demo with agents): https://github.com/TheDuckCow/godot-road-generator/tree/main/demo/procedural_generator

# ------------------------------------------------------------------------------
#region Signals/Enums/Const
# ------------------------------------------------------------------------------

signal on_transform

enum LaneFlags {
	# primary and secondary here are about connectivity - primary lane is going to be connected to the next/prior primary lane
	#  and which lane is going to be used for agent collision evasion by RoadLaneAgent
	# we know which lanes are meging/diverging and to where they're merging into/diverging from in road segments
	# for intersections the idea is to use the least curvy or the priority lane as the main one
	# while it may be possible to make such cases as two lanes, where first is main for merging and second is main for divering
	#  the first is diverging from second and second is merging into first - i wouldn't expect RoadLaneAgent to work with it
	NORMAL = 0x0, # plain simple lane
	MERGE_INTO = 0x1, # main lane to which all seconady lane(s) merging into (mutually exclusive with MERGING)
	MERGING = 0x2, # secondary lane that merges into the primary lane (mutually exclusive with MERGE_INTO, see merge_lane)
	DIVERGE_FROM = 0x4, # main lane from which secondary lanes diverging from (mutually exclusive with DIVERGING)
	DIVERGING = 0x8, # secondary lane that diverges from the primary lane (mutually exclusive with DIVERGE_FROM, see diverge_from)
	INTERSECTION = 0x10, # the lane is a part of intersection. it may intersect other lanes (see intersection_points)
	BOTH_WAYS = 0x20, # the lane have a twin RoadLane with reverse direction (see opposite_lane)
	PERSONAL = 0x40000000, # the lane is created for one RoadLaneAgent, other agents or lanes are not aware of it - e.g. for lane changing (in which case it's also MERGING and DIVERGING)
	UTILITY = 0x80000000, # lanes that are created for some internal reason - e.g. despawn lane
}

enum MoveDir
{
	FORWARD,
	BACKWARD,
}
static func reverse_move_dir(dir: MoveDir) -> MoveDir:
	return 1 - dir

enum SideDir
{
	RIGHT,
	LEFT,
}
static func other_side(side: SideDir) -> SideDir:
	return 1 - side

const COLOR_PRIMARY := Color(0.6, 0.3, 0,3)
const COLOR_START := Color(0.7, 0.7, 0,7)

const TRAFFIC_CHUNK_LENGTH := 2.5 #not longer the than shortest vehicle #TODO make var, move to road container?

const DEBUG_OUT := false
const ENABLE_HEAVY_CKECKS := true

class Obstacle:
	enum ObstacleFlags {
		REAL = 0x0, # the node is on this lane
		IMMINENT = 0x1, # the node from another lane won't be able to stop before it gets to this position
		PARTIAL = 0x2, # the node is from another lane but it partially blocks this lane
		LANE_END = 0x8, # end of the lane sequence (no link to the beginning)
	}
	const END_OFFSET_MAX = 5.0

	var visualize_lane : bool

	var flags := ObstacleFlags.REAL
	var lane: RoadLane
	var offset: float
	var node: Node3D
	var sequential_obstacles: Array[Obstacle] = [null, null]

	## Obstacle is essentially an oblong/capsule
	var end_offsets: Array[float] = [0.0, 0.0]
	var width: float = 0.0

	## approximate speed an obstacle on lane (m/s)
	## for example if actor moves with an angle from tagent, its obstacle's speed
	## should be just a fraction (dependent on the angle) of actor's speed
	## Note: the obstacle won't be moved along lane automatically
	var speed: float

	func _init(visualize_lane := false) -> void:
		self.visualize_lane = visualize_lane

	func distance_to_end(dir: RoadLane.MoveDir) -> float:
		assert(check_valid())
		return self.lane.offset_from_end(self.offset, dir)


	func segment_distance_fast(a0, a1, b0, b1) -> float:
		const EPS := 1e-8
		var u = a1 - a0
		var v = b1 - b0
		var w = a0 - b0
		var D = u.dot(u) * v.dot(v) - pow(u.dot(v), 2)
		if abs(D) < EPS:
			return a0.distance_to(b0)
		var s = clamp((u.dot(v) * v.dot(w) - v.dot(v) * u.dot(w)) / D, 0.0, 1.0)
		var t = clamp((u.dot(u) * v.dot(w) - u.dot(v) * u.dot(w)) / D, 0.0, 1.0)
		return (a0 + u * s).distance_to(b0 + v * t)


	func distance_to(obstacle: Obstacle) -> float:
		var pos_forward = self.node.global_position - self.node.global_basis.z * self.end_offsets[MoveDir.FORWARD]
		var pos_backward = self.node.global_position - self.node.global_basis.z * self.end_offsets[MoveDir.BACKWARD]
		var pos_forward_other = obstacle.node.global_position - obstacle.node.global_basis.z * obstacle.end_offsets[MoveDir.FORWARD]
		var pos_backward_other = obstacle.node.global_position - obstacle.node.global_basis.z * obstacle.end_offsets[MoveDir.BACKWARD]
		return segment_distance_fast(pos_forward, pos_backward, pos_forward_other, pos_backward_other) - self.width - obstacle.width


	func check_valid() -> bool:
		if ! RoadLane.ENABLE_HEAVY_CKECKS:
			return true
		var all_good := true
		if !is_instance_valid(self.node):
			print(self, " Obst. has invalid node ", self.node)
			all_good = false
		for dir in MoveDir.values():
			if self.end_offsets[dir] < 0:
				print(self, " Obst. negative ", MoveDir.find_key(dir), " end offset ", self.end_offsets[dir])
				all_good = false
			elif self.end_offsets[dir] > END_OFFSET_MAX:
				print(self, " Obst. too big ", MoveDir.find_key(dir), " end offset ", self.end_offsets[dir])
				all_good = false
		if !is_instance_valid(self.lane):
			print(self, " Obst. has invalid lane ", self.lane)
			all_good = false
		else:
			if self not in self.lane.obstacles:
				print(self, " Obst. is not registered in ", self.lane)
				all_good = false
			if self.offset < 0:
				print(self, " Obst. has negative offset ", self.offset)
				all_good = false
			elif self.offset > self.lane.curve.get_baked_length():
				print(self, " Obst. has too big offset ", self.offset, " - lane's length is ", self.lane.curve.get_baked_length())
				all_good = false
		return all_good


	func _insert_in_obstacle_list(next: Obstacle, dir: MoveDir) -> void:
		assert(next)
		var dir_back := RoadLane.reverse_move_dir(dir)
		var prior := next.sequential_obstacles[dir_back]
		next.sequential_obstacles[dir_back] = self
		self.sequential_obstacles[dir] = next
		if prior:
			assert(prior.sequential_obstacles[dir] == next)
			prior.sequential_obstacles[dir] = self
			self.sequential_obstacles[dir_back] = next


	func _remove_from_obstacle_list() -> void:
		for dir in RoadLane.MoveDir.values():
			if self.sequential_obstacles[dir]:
				var dir_back := RoadLane.reverse_move_dir(dir)
				assert(self.sequential_obstacles[dir].sequential_obstacles[dir_back] == self)
				self.sequential_obstacles[dir].sequential_obstacles[dir_back] = self.sequential_obstacles[dir_back]
		for dir in RoadLane.MoveDir.values():
			self.sequential_obstacles[dir] = null


	func _update_lane_sequence(dir: MoveDir, from: Obstacle, to: Obstacle) -> Obstacle:
		var lane = self.lane
		var offset = self.offset
		while lane:
			var prior := lane._replace_next_obstacle(offset, from, to, dir)
			if prior:
				return prior
			lane = lane.get_sequential_lane(MoveDir.BACKWARD)
			offset = INF
		return null


	func _insert_to_list() -> void:
		var next := self.lane.find_next_obstacle(offset) #all lane sequences must end with an obstacle for obstacle search reasons
		assert(next)
		self._insert_in_obstacle_list(next, RoadLane.MoveDir.FORWARD)
		self._update_lane_sequence(MoveDir.FORWARD, next, self)


	func _remove_from_list() -> void:
		self._update_lane_sequence(MoveDir.FORWARD, self, self.sequential_obstacles[MoveDir.FORWARD])
		self._remove_from_obstacle_list()


	func _place_to(lane: RoadLane, offset: float) -> void:
		if DEBUG_OUT:
			print(self, " assigning ", offset, " on ", lane )
		if lane != self.lane:
			if self.lane:
				self.lane.unregister_obstacle(self)
			lane.register_obstacle(self)
		self.lane = lane
		self.offset = offset


	func assign_position(lane: RoadLane, offset: float) -> void:
		_place_to(lane, offset)
		self._insert_to_list()


	func unassign_position() -> void:
		self._remove_from_list()
		self.lane.unregister_obstacle(self)
		self.lane = null
		self.offset = NAN


	func move_along_lane(lane: RoadLane, offset: float, dir: MoveDir) -> void:
		var seq_obstacle := self.sequential_obstacles[dir]
		if seq_obstacle:
			var jump_over := false
			if lane != self.lane:
				assert(self.lane.get_sequential_lane(dir) == lane) #TODO store lane-to-index for road lane sequence in road manager?
				if seq_obstacle.lane == self.lane:
					jump_over = true
			if seq_obstacle.lane == lane && seq_obstacle.offset < offset:
				jump_over = true
			if jump_over:
				self._remove_from_list()
				self._place_to(lane, offset)
				self._insert_to_list()
				return
		self._place_to(lane, offset)
		_update_lane_sequence(dir, seq_obstacle, self)


# ------------------------------------------------------------------------------
#endregion
#region Export vars
# ------------------------------------------------------------------------------

# -------------------------------------
@export_group("Connections")
# -------------------------------------


var _side_lanes : Array[NodePath] = ["", ""]
## Reference to the next left-side [RoadLane] if any, for allowed lane transitions.
@export var lane_left: NodePath:
	get:
		return _side_lanes[SideDir.LEFT]
	set(val):
		assert(get_node_or_null(val) != self)
		_side_lanes[SideDir.LEFT] = val
## Reference to the next right-side [RoadLane] if any, for allowed lane transitions.
@export var lane_right: NodePath:
	get:
		return _side_lanes[SideDir.RIGHT]
	set(val):
		assert(get_node_or_null(val) != self)
		_side_lanes[SideDir.RIGHT] = val


var _sequential_lanes: Array[NodePath] = ["", ""]
## The next forward [RoadLane] for agents to follow along.
@export var lane_next: NodePath:
	get:
		return _sequential_lanes[MoveDir.FORWARD]
	set(val):
		assert(get_node_or_null(val) != self)
		_sequential_lanes[MoveDir.FORWARD] = val
## The prior [RoadLane] for agents to follow (if going backwards).
@export var lane_prior: NodePath:
	get:
		return _sequential_lanes[MoveDir.BACKWARD]
	set(val):
		assert(get_node_or_null(val) != self)
		_sequential_lanes[MoveDir.BACKWARD] = val

## Tags are used help populate the lane_next and lane_prior NodePaths above.[br][br]
##
## Given two segments (seg_A followed by seg_B), a lane_A of seg_A will be auto
## matched to lane_B of seg_B if lane_A's lane_next_tag is the same as lane_B's
## lane_prior_tag (since lane_B follows lane_A in this situation).[br][br]
##
## Any matching name will do, and it will match the first match. Auto-generated
## lanes have a convention of a prefix F or R (for forward or reverse lane,
## relative to the road segment) followed by a 0-indexed integer, based on how
## far from the middle of the road (middle = where the lane direction flips).[br][br]
##
## This way, the inner most lanes are always matched together. A lane F2 being
## removed on the right (forward) will be recognized as needing to have it's
## lane_next_tag set to F1, representing cars merging from this removed lane into
## the next interior lane.[br][br]
##
## e.g. R0, R1,...R#, F0, F1, ... F#.
var sequential_lane_tags: Array[String] = ["", ""]
@export var lane_next_tag: String:
	get: return sequential_lane_tags[MoveDir.FORWARD]
	set(val): sequential_lane_tags[MoveDir.FORWARD] = val
## See description above for [member RoadLane.lane_next_tag] which is the equivalent.
@export var lane_prior_tag: String:
	get: return sequential_lane_tags[MoveDir.BACKWARD]
	set(val): sequential_lane_tags[MoveDir.BACKWARD] = val


## lanes to which this lane merges and diverges from
var _primary_lanes : Array[NodePath] = ["", ""]
@export var lane_merge_to: NodePath:
	get: return _primary_lanes[MoveDir.FORWARD]
	set(val): assert(get_node_or_null(val) != self); _primary_lanes[MoveDir.FORWARD] = val
@export var lane_diverge_from: NodePath:
	get: return _primary_lanes[MoveDir.BACKWARD]
	set(val): assert(get_node_or_null(val) != self); _primary_lanes[MoveDir.BACKWARD] = val

# -------------------------------------
@export_group("Behavior")
# -------------------------------------

## Visualize this [RoadLane] and its direction in the editor directly.
@export var draw_in_game = false: get = _get_draw_in_game, set = _set_draw_in_game
## Visualize this [RoadLane] and its direction during the game runtime.
@export var draw_in_editor = false: get = _get_draw_in_editor, set = _set_draw_in_editor

## Auto queue-free any vehicles registered to this lane with the road lane exits.
@export var auto_free_vehicles: bool = false


# -------------------------------------
@export_group("Editor tools")
# -------------------------------------


# TODO: remove when moved to Godot 4.4 and changed to simple button
# the variable is not used - only to provide GUI element
## UI tool to easily flip the order of points of the curve.[br][br]
##
## Property will remain unchecked but will perform the action described. Will be
## replaced with a tool button once this addon targets Godot 4.4 as the minimum.
@export var reverse_direction = false: set = _set_reverse_direction

var this_road_segment :RoadSegment = null
var refresh_geom := true
var geom:ImmediateMesh # For tool usage, drawing lane directions and end points
var geom_node: MeshInstance3D

# Internal field used by agents for intra-segment lane changes
var flags: RoadLane.LaneFlags = LaneFlags.NORMAL

# Obstacles registered to this lane
var obstacles: Array[RoadLane.Obstacle] = []

# next obstacle (not necessary on this lane).
# lane length is split in chunks of TRAFFIC_CHUNK_LENGTH
var _next_obstacles: Array[RoadLane.Obstacle] = []

## this obstacle have to be set on the last lane of lane sequence,
## so that _next_obstacles would always be possible to find
var _end_obstacle: RoadLane.Obstacle

var _draw_in_game_counter :int = 0
var _draw_in_editor: bool = false
var _draw_override: bool = false
var _display_fins: bool = false


# ------------------------------------------------------------------------------
#endregion
#region Setup and builtin overrides
# ------------------------------------------------------------------------------


func _init():
	if not is_instance_valid(curve):
		curve = Curve3D.new()
	_end_obstacle = Obstacle.new()
	_end_obstacle.node = self


func _ready():
	set_notify_transform(true)
	set_notify_local_transform(true)
	connect("curve_changed", Callable(self, "curve_changed"))
	rebuild_geom()


func _exit_tree() -> void:
	if auto_free_vehicles:
		for obstable in obstacles:
			if is_instance_valid(obstable):
				obstable.node.call_deferred("queue_free")


# ------------------------------------------------------------------------------
#endregion
#region Functions
# ------------------------------------------------------------------------------


#TODO: remove when moved to Godot 4.4 and changed to simple button
func _set_reverse_direction(value: bool) -> void:
	on_reverse_lane()


## Reverse geometry of lane curve
func on_reverse_lane() -> void:
	var reversed_curve = Curve3D.new()
	for i in range(self.curve.point_count - 1, -1, -1):
		var pos = self.curve.get_point_position(i)
		var in_tangent = self.curve.get_point_in(i)
		var out_tangent = self.curve.get_point_out(i)
		reversed_curve.add_point(pos, out_tangent, in_tangent)
	self.curve = reversed_curve
	refresh_geom = true
	rebuild_geom()


func get_lane_start() -> Vector3:
	return to_global(curve.get_point_position(0))


func get_lane_end() -> Vector3:
	return to_global(curve.get_point_position(curve.get_point_count()-1))


func get_sequential_lane(dir : MoveDir) -> RoadLane:
	var lane: RoadLane = get_node_or_null(self._sequential_lanes[dir])
	assert(lane != self)
	return lane


func get_primary_lane(dir : MoveDir) -> RoadLane:
	var lane: RoadLane = get_node_or_null(self._primary_lanes[dir])
	assert(lane != self)
	return lane


func _get_path(lane: RoadLane) -> NodePath:
	return self.get_path_to(lane) if lane else NodePath("")



func set_primary_lane(dir : MoveDir, lane: RoadLane) -> void:
	self._primary_lanes[dir] = _get_path(lane)


func get_side_lane(dir : SideDir) -> RoadLane:
	var lane: RoadLane = get_node_or_null(self._side_lanes[dir])
	assert(lane != self)
	return lane


func connect_sequential(dir: MoveDir, lane: RoadLane) -> void:
	if DEBUG_OUT:
		print(self, "connect to ", lane, " in direction ", dir)
	#TODO if a line is to be deleted _next_obstacles doesn't have to be updated end _end_obstacle may be moved from it as an optimization
	if dir == MoveDir.FORWARD && !lane._next_obstacles.is_empty():
		if lane: #connect 2 lanes
			if self.get_sequential_lane(dir) != null:
				assert(self.get_sequential_lane(dir) == lane)
				return
			var prior_obstacle := self._replace_next_obstacle(INF, _end_obstacle, lane._next_obstacles[0], MoveDir.FORWARD)
			if prior_obstacle:
				assert(lane._next_obstacles[0].sequential_obstacles[MoveDir.BACKWARD] == null)
				assert(prior_obstacle.sequential_obstacles[MoveDir.FORWARD] == self._end_obstacle)
				lane._next_obstacles[0].sequential_obstacles[MoveDir.BACKWARD] = prior_obstacle
				prior_obstacle.sequential_obstacles[MoveDir.FORWARD] = lane._next_obstacles[0]
		else: #disconnect 2 lanes
			lane = self.get_sequential_lane(dir)
			var prior_obstacle := self._replace_next_obstacle(INF, lane._next_obstacles[0], _end_obstacle, MoveDir.FORWARD)
			if prior_obstacle:
				assert(lane._next_obstacles[0].sequential_obstacles[MoveDir.BACKWARD] == prior_obstacle)
				assert(prior_obstacle.sequential_obstacles[MoveDir.FORWARD] == lane._next_obstacles[0])
				lane._next_obstacles[0].sequential_obstacles[MoveDir.BACKWARD] = null
				prior_obstacle.sequential_obstacles[MoveDir.FORWARD] = self._end_obstacle
	self._sequential_lanes[dir] = _get_path(lane)


## Register a agent to be connected to (on, following) this lane.
func register_obstacle(obstacle: RoadLane.Obstacle) -> void:
	if DEBUG_OUT:
		print("Registering ", obstacle, " on lane ", self, " with lanes connected FORWARD ", self.get_sequential_lane(MoveDir.FORWARD), " and BACKWARD ", self.get_sequential_lane(MoveDir.BACKWARD))
	_draw_in_game_counter += int(obstacle.visualize_lane)
	assert(obstacle not in obstacles)
	obstacles.append(obstacle)


## Optional but good cleanup of references.
func unregister_obstacle(obstacle: RoadLane.Obstacle) -> void:
	if DEBUG_OUT:
		print("Unregistering ", obstacle, " from lane ", self)
	_draw_in_game_counter -= int(obstacle.visualize_lane)
	assert( obstacle in obstacles )
	obstacles.erase(obstacle)


func get_lane_end_point_by_dir(dir: MoveDir) -> Vector3:
	assert(dir in MoveDir.values())
	return get_lane_start() if dir == MoveDir.FORWARD else get_lane_end()


func offset_from_end(distance: float, dir: RoadLane.MoveDir) -> float:
	assert(distance >= 0 && distance <= self.curve.get_baked_length())
	return (self.curve.get_baked_length() - distance) if dir == MoveDir.FORWARD else distance


func _instantiate_geom() -> void:
	if Engine.is_editor_hint():
		_display_fins = _draw_in_editor or _draw_override
	else:
		_display_fins = _draw_in_game_counter > 0 or _draw_override

	if not _display_fins:
		if geom:
			geom.clear_surfaces()
		return
	if refresh_geom == false:
		return
	refresh_geom = false

	# Setup immediate geo node if not already.
	if geom == null:
		geom = ImmediateMesh.new()
		geom.set_name("geom")
		if not is_instance_valid(geom_node):
			geom_node = MeshInstance3D.new()
			geom_node.mesh = geom
			add_child(geom_node)
		else:
			geom_node.mesh = geom

		var mat = StandardMaterial3D.new()
		mat.flags_unshaded = true
		mat.flags_disable_ambient_light = true
		mat.params_depth_draw_mode = StandardMaterial3D.DEPTH_DRAW_DISABLED
		mat.flags_do_not_receive_shadows = true
		mat.flags_no_depth_test = true
		mat.flags_do_not_receive_shadows = true
		mat.params_cull_mode = mat.CULL_DISABLED
		mat.vertex_color_use_as_albedo = true
		geom_node.material_override = mat

	_draw_shark_fins()


## Generate the triangles along the path, indicating lane direction.
func _draw_shark_fins() -> void:
	var curve_length = curve.get_baked_length()
	var draw_dist = 3 # draw a new triangle at this interval in m
	var tri_count = floor(curve_length / draw_dist)

	geom.clear_surfaces()
	for i in range (0, tri_count):
		var f = i * curve_length / tri_count
		var xf = Transform3D()

		xf.origin = curve.sample_baked(f)
		var lookat = (
			curve.sample_baked(f + 0.1) - xf.origin
		).normalized()

		geom.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		if i == 0:
			geom.surface_set_color(COLOR_START)
		else:
			geom.surface_set_color(COLOR_PRIMARY)
		geom.surface_add_vertex(xf.origin)
		geom.surface_add_vertex(xf.origin + Vector3(0, 0.5, 0) - lookat*0.2)
		geom.surface_add_vertex(xf.origin + lookat * 1)
		geom.surface_end()


func rebuild_geom() -> void:
	if refresh_geom:
		call_deferred("_instantiate_geom")


func curve_changed() -> void:
	refresh_geom = true
	if DEBUG_OUT:
		print(self, " changed curve")
	if self.curve.get_baked_length() != 0:
		self._next_obstacles.resize(int(self.curve.get_baked_length() / TRAFFIC_CHUNK_LENGTH) + 1)
		for idx in len(_next_obstacles):
			_next_obstacles[idx] = _end_obstacle
		_end_obstacle.assign_position(self, self.curve.get_baked_length())
		#TODO what to do if there are road lane agents on the lane already? if offset is bigger than new one?

	rebuild_geom()


func _set_draw_in_game(value: bool) -> void:
	refresh_geom = true
	_draw_in_game_counter = value
	rebuild_geom()

func _get_draw_in_game() -> bool:
	return _draw_in_game_counter > 0

func _set_draw_in_editor(value: bool) -> void:
	refresh_geom = true
	_draw_in_editor = value
	rebuild_geom()

func _get_draw_in_editor() -> bool:
	return _draw_in_editor


func show_fins(value: bool) -> void:
	_draw_override = value
	rebuild_geom()


func find_next_obstacle(offset: float) -> Obstacle:
	assert(offset >= 0 && offset <= self.curve.get_baked_length())
	return self._next_obstacles[int(offset / TRAFFIC_CHUNK_LENGTH)]


## dir is flipped - when obstacle moves forward se propagate from the end position backwards
func _replace_next_obstacle(offset: float, from: Obstacle, to: Obstacle, dir: MoveDir) -> Obstacle:
	assert(is_inf(offset) || ( offset >= 0 && offset <= self.curve.get_baked_length() ) )
	var start := (len(_next_obstacles) -1 if dir == MoveDir.FORWARD else 0) if is_inf(offset) else int(offset / TRAFFIC_CHUNK_LENGTH)
	var end := -1 if dir == MoveDir.FORWARD else len(_next_obstacles) -1
	var step := -1 if dir == MoveDir.FORWARD else 1
	for i in range(start, end, step):
		if self._next_obstacles[i] != from:
			return self._next_obstacles[i]
		self._next_obstacles[i] = to
	return null

#endregion
# ------------------------------------------------------------------------------
