@tool
@icon("res://addons/road-generator/resources/road_lane.png")
class_name RoadLane
extends Path3D
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

const COLOR_PRIMARY := Color(0.6, 0.3, 0.0)
const COLOR_START := Color(0.1, 0.9, 0.0)
const COLOR_END := Color(0.8, 0.1, 0.1) #Color(0.4, 0.7, 0,7)


# ------------------------------------------------------------------------------
#endregion
#region Export vars
# ------------------------------------------------------------------------------


# -------------------------------------
@export_group("Connections")
# -------------------------------------


## Reference to the next left-side [RoadLane] if any, for allowed lane transitions.
@export var lane_left:NodePath
## Reference to the next right-side [RoadLane] if any, for allowed lane transitions.
@export var lane_right:NodePath
## The [RoadLane]s agents may continue into; more than one is a fork.
@export var lanes_next: Array[NodePath] = []
## The [RoadLane]s that continue into this one; more than one is a merge.
@export var lanes_prior: Array[NodePath] = []

## Tags are used help populate the lanes_next and lanes_prior NodePaths above.[br][br]
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
@export var lane_next_tag:String
## See description above for [member RoadLane.lane_next_tag] which is the equivalent.
@export var lane_prior_tag:String


# -------------------------------------
@export_group("Behavior")
# -------------------------------------

## Visualize this [RoadLane] and its direction during the game runtime.
@export var draw_in_game = false: get = _get_draw_in_game, set = _set_draw_in_game
## Visualize this [RoadLane] and its direction in the editor directly.
@export var draw_in_editor = false: get = _get_draw_in_editor, set = _set_draw_in_editor

## Mesh instanced along the lane to visualize its direction. All lanes share
## the same resource by default; assign another mesh to customize the shape.
@export var lane_pointer_mesh: Mesh = preload("res://addons/road-generator/resources/road_lane_pointer_mesh.res"): set = _set_lane_pointer_mesh

## Auto queue-free the actors of agents on this lane when the lane exits the
## tree, for agents with [member RoadLaneAgent.auto_register] on.
@export var auto_free_vehicles: bool = true


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


var road_segment = null ## Will be populatd at runtime if an auto generated lane
var refresh_geom = true
var geom:MultiMesh # For tool usage, drawing lane directions and end points
var geom_node: MultiMeshInstance3D
# Internal field used by agents for intra-segment lane changes
var transition: bool = false

var _agents: Array[RoadLaneAgent] = [] # Sorted by current_lane_offset, rearmost first
var _agent_resort_queued := false
var _link_refresh_queued := false
var _draw_in_game: bool = false
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


func _ready():
	set_notify_transform(true)
	set_notify_local_transform(true)
	connect("curve_changed", Callable(self, "curve_changed"))
	rebuild_geom()
	#_instantiate_geom()


func _exit_tree() -> void:
	var leaving := _agents.duplicate()
	_agents.clear()
	for agent in leaving:
		agent._index_in_lane = -1
		agent.refresh_agent_ahead()
		if auto_free_vehicles and agent.auto_register and is_instance_valid(agent.actor):
			agent.actor.call_deferred("queue_free")
	notify_upstream()


## Loads the single lane_next/lane_prior properties from older scenes.
func _set(property: StringName, value: Variant) -> bool:
	if property != &"lane_next" and property != &"lane_prior":
		return false
	if value is NodePath and not value.is_empty():
		if property == &"lane_next" and not lanes_next.has(value):
			lanes_next = _appended(lanes_next, value)
		elif property == &"lane_prior" and not lanes_prior.has(value):
			lanes_prior = _appended(lanes_prior, value)
	return true


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


## Valid [RoadLane]s this lane continues into.
func get_next_lanes() -> Array[RoadLane]:
	return _resolve_lanes(lanes_next)


## Valid [RoadLane]s that continue into this lane.
func get_prior_lanes() -> Array[RoadLane]:
	return _resolve_lanes(lanes_prior)


## Add a lane this one continues into. Only updates this lane, not [param lane].
func add_lane_next(lane: RoadLane) -> void:
	if _find_link(lanes_next, lane) == -1:
		lanes_next = _appended(lanes_next, get_path_to(lane))
		_queue_link_refresh()


## Add a lane that continues into this one. Only updates this lane, not [param lane].
func add_lane_prior(lane: RoadLane) -> void:
	if _find_link(lanes_prior, lane) == -1:
		lanes_prior = _appended(lanes_prior, get_path_to(lane))
		_queue_link_refresh()


func remove_lane_next(lane: RoadLane) -> void:
	var result := _removed(lanes_next, lane)
	if result != lanes_next:
		lanes_next = result
		_queue_link_refresh()


func remove_lane_prior(lane: RoadLane) -> void:
	var result := _removed(lanes_prior, lane)
	if result != lanes_prior:
		lanes_prior = result
		_queue_link_refresh()


## Clear all next and prior links, including the links back to this lane from
## those neighbors.
func clear_lane_links() -> void:
	for lane in get_next_lanes():
		lane.remove_lane_prior(self)
	for lane in get_prior_lanes():
		lane.remove_lane_next(self)
	lanes_next = []
	lanes_prior = []
	_queue_link_refresh()


func _resolve_lanes(paths: Array[NodePath]) -> Array[RoadLane]:
	var lanes: Array[RoadLane] = []
	for path in paths:
		var lane := get_node_or_null(path) as RoadLane
		if is_instance_valid(lane):
			lanes.append(lane)
	return lanes


func _find_link(paths: Array[NodePath], lane: RoadLane) -> int:
	for idx in range(paths.size()):
		if get_node_or_null(paths[idx]) == lane:
			return idx
	return -1


# Copies rather than mutating, since Node.duplicate() shares array references.
func _appended(paths: Array[NodePath], path: NodePath) -> Array[NodePath]:
	var result: Array[NodePath] = paths.duplicate()
	result.append(path)
	return result


func _removed(paths: Array[NodePath], lane: RoadLane) -> Array[NodePath]:
	var idx := _find_link(paths, lane)
	if idx == -1:
		return paths
	var result: Array[NodePath] = paths.duplicate()
	result.remove_at(idx)
	return result


## Add an agent at its [member RoadLaneAgent.current_lane_offset], keeping
## agents sorted. Called by [method RoadLaneAgent.assign_lane].
func register_agent(agent: RoadLaneAgent) -> void:
	var idx := _bisect(agent.current_lane_offset, true)
	_agents.insert(idx, agent)
	_reindex_agents(idx)
	agent.refresh_agent_ahead()
	_notify_behind(idx)


## Remove an agent; a no-op if it isn't on this lane.
func unregister_agent(agent: RoadLaneAgent) -> void:
	var idx := _agents.find(agent)
	if idx == -1:
		return
	_agents.remove_at(idx)
	_reindex_agents(idx)
	_notify_behind(idx)


## Move an agent whose offset changed back into sorted order.
func update_agent_order(agent: RoadLaneAgent) -> void:
	var idx := agent._index_in_lane
	if idx < 0 or idx >= _agents.size() or _agents[idx] != agent:
		idx = _agents.find(agent)
		if idx == -1:
			return
	var start_idx := idx
	while idx > 0 and _is_behind(agent, _agents[idx - 1]):
		_swap_agents(idx, idx - 1)
		idx -= 1
	while idx < _agents.size() - 1 and _is_behind(_agents[idx + 1], agent):
		_swap_agents(idx, idx + 1)
		idx += 1
	if idx == start_idx:
		return
	var lo := mini(start_idx, idx)
	for i in range(maxi(lo - 1, 0), maxi(start_idx, idx) + 1):
		_agents[i].refresh_agent_ahead()
	if lo == 0:
		notify_upstream()


## Has the frontmost agent of each lane leading into this one re-find its agent
## ahead, walking back through empty lanes within the look-ahead limits.
func notify_upstream() -> void:
	var visited := {self: true}
	var frontier: Array = [[self, 0.0, 0]] # lane, empty length behind it, empty lane count
	while not frontier.is_empty():
		var entry: Array = frontier.pop_front()
		for prior in (entry[0] as RoadLane).get_prior_lanes():
			if visited.has(prior):
				continue
			visited[prior] = true
			if not prior.get_agents().is_empty():
				prior.get_agents().back().refresh_agent_ahead()
				continue
			var gap: float = entry[1] + prior.curve.get_baked_length()
			var empty_count: int = entry[2] + 1
			# Mirrors RoadLaneAgent.refresh_agent_ahead, which only looks past lanes with one next lane.
			if (prior.get_next_lanes().size() == 1
					and empty_count < RoadLaneAgent.lookahead_max_hops
					and gap <= RoadLaneAgent.lookahead_max_distance):
				frontier.append([prior, gap, empty_count])


## Has whoever could see the agent at [param idx] as their agent ahead re-check.
func _notify_behind(idx: int) -> void:
	if idx == 0:
		notify_upstream()
	elif idx <= _agents.size():
		_agents[idx - 1].refresh_agent_ahead()


## Agents on this lane, sorted rearmost first. Don't modify the returned array.
func get_agents() -> Array[RoadLaneAgent]:
	return _agents


## Actors of the agents on this lane, without duplicates.
func get_vehicles() -> Array:
	var vehicles: Array = []
	for agent in _agents:
		if is_instance_valid(agent.actor) and not agent.actor in vehicles:
			vehicles.append(agent.actor)
	return vehicles


## Agents within [param distance] of [param offset] along this lane, continuing
## into every next and prior lane when the range runs past either end.
func get_agents_near(offset: float, distance: float) -> Array[RoadLaneAgent]:
	var found: Array[RoadLaneAgent] = []
	_collect_agents_near(offset - distance, offset + distance, 0, found, {})
	return found


## [param dir] limits the search to next (1) or prior (-1) lanes once it has left the starting lane.
func _collect_agents_near(from: float, to: float, dir: int, found: Array[RoadLaneAgent], visited: Dictionary) -> void:
	if visited.has(self):
		return
	visited[self] = true
	for idx in range(_bisect(from, false), _bisect(to, true)):
		found.append(_agents[idx])
	var length := curve.get_baked_length()
	if dir >= 0 and to > length:
		for lane in get_next_lanes():
			lane._collect_agents_near(0.0, to - length, 1, found, visited)
	if dir <= 0 and from < 0.0:
		for lane in get_prior_lanes():
			var prior_length := lane.curve.get_baked_length()
			lane._collect_agents_near(prior_length + from, prior_length, -1, found, visited)


## Index of the first agent at or past [param offset], or strictly past it if [param after_equal].
func _bisect(offset: float, after_equal: bool) -> int:
	var lo := 0
	var hi := _agents.size()
	while lo < hi:
		var mid := (lo + hi) / 2
		var mid_offset := _agents[mid].current_lane_offset
		if mid_offset < offset or (after_equal and mid_offset == offset):
			lo = mid + 1
		else:
			hi = mid
	return lo


static func _is_behind(a: RoadLaneAgent, b: RoadLaneAgent) -> bool:
	return a.current_lane_offset < b.current_lane_offset


func _swap_agents(idx_a: int, idx_b: int) -> void:
	var agent := _agents[idx_a]
	_agents[idx_a] = _agents[idx_b]
	_agents[idx_b] = agent
	_agents[idx_a]._index_in_lane = idx_a
	_agents[idx_b]._index_in_lane = idx_b


func _reindex_agents(from_idx: int) -> void:
	for idx in range(from_idx, _agents.size()):
		_agents[idx]._index_in_lane = idx


## Re-derive every agent's offset from its actor and re-sort, after the curve changed.
func _resort_agents() -> void:
	_agent_resort_queued = false
	for agent in _agents:
		agent._reproject_offset()
	_agents.sort_custom(_is_behind)
	_reindex_agents(0)
	for agent in _agents:
		agent.refresh_agent_ahead()
	notify_upstream()


func _queue_link_refresh() -> void:
	if Engine.is_editor_hint() or _link_refresh_queued:
		return
	_link_refresh_queued = true
	_refresh_after_link_change.call_deferred()


## Paths through this lane changed, so re-check choices and agents ahead that depend on them.
func _refresh_after_link_change() -> void:
	_link_refresh_queued = false
	for agent in _agents.duplicate():
		agent._validated_chosen_lane_next()
	if not _agents.is_empty():
		_agents.back().refresh_agent_ahead()
	notify_upstream()


func _instantiate_geom() -> void:

	if Engine.is_editor_hint():
		_display_fins = _draw_in_editor or _draw_override
	else:
		_display_fins = _draw_in_game or _draw_override

	if not _display_fins:
		if geom:
			geom.instance_count = 0
		return
	if refresh_geom == false:
		return
	refresh_geom = false

	# Setup geo node if not already.
	if geom == null:
		geom = MultiMesh.new()
		geom.set_name("geom")
		geom.transform_format = MultiMesh.TRANSFORM_3D
		geom.use_colors = true
		geom.mesh = lane_pointer_mesh
		if not is_instance_valid(geom_node):
			geom_node = MultiMeshInstance3D.new()
			geom_node.multimesh = geom
			add_child(geom_node)
		else:
			geom_node.multimesh = geom

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


## Place pointer mesh instances along the path, indicating lane direction.
func _draw_shark_fins() -> void:
	var curve_length := curve.get_baked_length()
	var draw_dist := 1 # place a new pointer at this interval in m
	var tri_count: int = floor(curve_length / draw_dist)

	if tri_count == 0 or lane_pointer_mesh == null:
		geom.instance_count = 0
		return
	geom.mesh = lane_pointer_mesh
	# Forward extent of the pointer, to pin the last one against the lane end.
	var pointer_length: float = lane_pointer_mesh.get_aabb().size.z
	geom.instance_count = tri_count
	for i in range (0, tri_count):
		var f: float = i * curve_length / tri_count
		if i == tri_count - 1:
			# Land the end pointer's tip on the lane end, nudging the next
			# lane's start pointer.
			f = maxf(curve_length - pointer_length, 0.0)
		var origin: Vector3 = curve.sample_baked(f)
		# use sample_baked_with_rotation?
		var lookat: Vector3 = (
			curve.sample_baked(f + 0.1) - origin
		).normalized()
		var upvec := curve.sample_baked_up_vector(f, true).normalized()

		var basis := Basis()
		if lookat.length_squared() > 0.5 and absf(lookat.dot(upvec)) < 0.999:
			basis = Basis.looking_at(lookat, upvec)
		geom.set_instance_transform(i, Transform3D(basis, origin))

		if i == 0:
			geom.set_instance_color(i, COLOR_START)
		elif i == tri_count - 1:
			geom.set_instance_color(i, COLOR_END)
		else:
			geom.set_instance_color(i, COLOR_PRIMARY)


func rebuild_geom() -> void:
	if refresh_geom:
		call_deferred("_instantiate_geom")


func curve_changed() -> void:
	refresh_geom = true
	rebuild_geom()
	if _agents.is_empty():
		return
	for agent in _agents:
		agent.invalidate_offset()
	# Curves are rebuilt point by point, so resort once after the burst of changes.
	if not _agent_resort_queued:
		_agent_resort_queued = true
		_resort_agents.call_deferred()


func _set_lane_pointer_mesh(value: Mesh) -> void:
	lane_pointer_mesh = value
	refresh_geom = true
	rebuild_geom()


func _set_draw_in_game(value: bool) -> void:
	refresh_geom = true
	_draw_in_game = value
	rebuild_geom()

func _get_draw_in_game() -> bool:
	return _draw_in_game

func _set_draw_in_editor(value: bool) -> void:
	refresh_geom = true
	_draw_in_editor = value
	rebuild_geom()

func _get_draw_in_editor() -> bool:
	return _draw_in_editor


func show_fins(value: bool) -> void:
	_draw_override = value
	rebuild_geom()


#endregion
# ------------------------------------------------------------------------------
