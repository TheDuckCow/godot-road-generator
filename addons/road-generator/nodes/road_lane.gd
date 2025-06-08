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

const COLOR_PRIMARY := Color(0.6, 0.3, 0,3)
const COLOR_START := Color(0.7, 0.7, 0,7)

enum LaneDirection
{
	FORWARD,
	BACKWARD,
}
static func flip_dir(dir: LaneDirection) -> LaneDirection:
	return 1 - dir

enum LaneSideways
{
	RIGHT,
	LEFT,
}
static func flip_side(side: LaneSideways) -> LaneSideways:
	return 1 - side


# ------------------------------------------------------------------------------
#endregion
#region Export vars
# ------------------------------------------------------------------------------

# -------------------------------------
@export_group("Connections")
# -------------------------------------


var side_lanes : Array[NodePath] = ["", ""]
## Reference to the next left-side [RoadLane] if any, for allowed lane transitions.
@export var lane_left: NodePath:
	get: return side_lanes[LaneSideways.LEFT]
	set(val): side_lanes[LaneSideways.LEFT] = val
## Reference to the next right-side [RoadLane] if any, for allowed lane transitions.
@export var lane_right: NodePath:
	get: return side_lanes[LaneSideways.RIGHT]
	set(val): side_lanes[LaneSideways.RIGHT] = val


var adjacent_lanes: Array[NodePath] = ["", ""]
## The next forward [RoadLane] for agents to follow along.
@export var lane_next: NodePath:
	get: return adjacent_lanes[LaneDirection.FORWARD]
	set(val): assert(get_node_or_null(val) != self); adjacent_lanes[LaneDirection.FORWARD] = val
## The prior [RoadLane] for agents to follow (if going backwards).
@export var lane_prior: NodePath:
	get: return adjacent_lanes[LaneDirection.BACKWARD]
	set(val): adjacent_lanes[LaneDirection.BACKWARD] = val

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
var adjacent_lane_tags: Array[String] = ["", ""]
@export var lane_next_tag: String:
	get: return adjacent_lane_tags[LaneDirection.FORWARD]
	set(val): adjacent_lane_tags[LaneDirection.FORWARD] = val
## See description above for [member RoadLane.lane_next_tag] which is the equivalent.
@export var lane_prior_tag: String:
	get: return adjacent_lane_tags[LaneDirection.BACKWARD]
	set(val): adjacent_lane_tags[LaneDirection.BACKWARD] = val

# -------------------------------------
@export_group("Behavior")
# -------------------------------------

## Visualize this [RoadLane] and its direction in the editor directly.
@export var draw_in_game = false: get = _get_draw_in_game, set = _set_draw_in_game
## Visualize this [RoadLane] and its direction during the game runtime.
@export var draw_in_editor = false: get = _get_draw_in_editor, set = _set_draw_in_editor

## Auto queue-free any vehicles registered to this lane with the road lane exits.
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


var this_road_segment = null # RoadSegment
var refresh_geom = true
var geom:ImmediateMesh # For tool usage, drawing lane directions and end points
var geom_node: MeshInstance3D
# Internal field used by agents for intra-segment lane changes
var transition: bool = false

# this container should contain agents in order:
# from beginning to the end, i.e. agents' lower offset to higher offset
# also offsets are expected but not enforced to be unique
var _agents_in_lane: Array[RoadLaneAgent] = [] # Registration
var _draw_in_game: bool = false
var _draw_in_editor: bool = false
var _draw_override: bool = false
var _display_fins: bool = false

const DEBUG_OUT := true


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
	if auto_free_vehicles:
		for _vehicle in _vehicles_in_lane:
			if is_instance_valid(_vehicle):
				_vehicle.call_deferred("queue_free")


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


func is_agent_list_correct():
	for i in range(self._agents_in_lane.size() - 1):
		if _agents_in_lane[i].lane_pos.offset >= _agents_in_lane[i + 1].lane_pos.offset:
			print("on lane ", self, " offset of agent ", _agents_in_lane[i], " is not less than offset of agent ", _agents_in_lane[i +1])
			return false
		if _agents_in_lane[i].adjacent_agents[LaneDirection.FORWARD] != _agents_in_lane[i + 1]:
			print("on lane ", self, " agent ", _agents_in_lane[i +1], " is not next for agent ", _agents_in_lane[i])
			return false
		if _agents_in_lane[i] != _agents_in_lane[i + 1].adjacent_agents[LaneDirection.BACKWARD]:
			print("on lane ", self, " agent ", _agents_in_lane[i], " is not prior for agent ", _agents_in_lane[i +1])
			return false
	return true


func find_agent_index(agent: RoadLaneAgent, before: bool) -> int:
	assert(self.is_agent_list_correct())
	var idx = self._agents_in_lane.bsearch_custom(agent, RoadLaneAgent.compare_offset, before)
	return idx


func get_first_agent() -> RoadLaneAgent:
	return null if self._agents_in_lane.is_empty() else _agents_in_lane[0]


func get_adjacent_lane(dir : LaneDirection) -> RoadLane:
	return get_node_or_null(self.adjacent_lanes[dir])


## Register a agent to be connected to (on, following) this lane.
func register_agent(agent: RoadLaneAgent, link_agents: bool) -> void:
	if DEBUG_OUT:
		print(Time.get_ticks_usec(), " Registering agent ", agent, " on lane ", self, " with lanes connected FORWARD ", self.get_adjacent_lane(LaneDirection.FORWARD), " and BACKWARD ", self.get_adjacent_lane(LaneDirection.BACKWARD))
	assert(self.is_agent_list_correct())
	assert(agent not in _agents_in_lane)
	assert(agent.lane_pos)
	var idx = find_agent_index(agent, false)
	assert(idx == _agents_in_lane.size() || _agents_in_lane[idx].lane_pos.offset > agent.lane_pos.offset)
	assert(idx == 0 || _agents_in_lane[idx -1].lane_pos.offset < agent.lane_pos.offset)
	_agents_in_lane.insert(idx, agent)
	if link_agents:
		for dir in LaneDirection.values():
			#print(agent, " HERE2 ", idx, "/", _agents_in_lane.size() )
			if agent.adjacent_agents[dir] == null && idx != ((_agents_in_lane.size() -1) if dir == LaneDirection.FORWARD else 0):
				agent.link_next_agent(self._agents_in_lane[idx + (1 if dir == LaneDirection.FORWARD else -1)], dir)
	assert(self.is_agent_list_correct())


func find_adjacent_agents(agent: RoadLaneAgent) -> void:
	for dir in LaneDirection.values(): # didn't find any of the agents on the lane, will look on adjacent lanes
		if agent.adjacent_agents[dir] == null:
			var lane: RoadLane = self.get_adjacent_lane(dir)
			var count := 3
			while lane && count:
				#print(self, " -> ", lane, " HERE1 ",  agent, " ", count)
				if ! lane._agents_in_lane.is_empty():
					agent.link_next_agent(lane._agents_in_lane[0 if dir == LaneDirection.FORWARD else -1], dir)
					break
				lane = lane.get_adjacent_lane(dir)
				count -= 1
	for dir in LaneDirection.values(): # didn't find any of the agents on the lane, will look on adjacent lanes
		if agent.adjacent_agents[dir] == null:
			var lane: RoadLane = self.get_adjacent_lane(dir)
			assert(!lane || lane._agents_in_lane.is_empty())



## Optional but good cleanup of references.
func unregister_agent(agent: RoadLaneAgent) -> void:
	if DEBUG_OUT:
		print("Unregistering ", agent, " from lane ", self)
	assert( agent in _agents_in_lane )
	_agents_in_lane.erase(agent)
	assert( agent not in _agents_in_lane )


## Return all agents registered to this lane, performing cleanup as needed.
func get_agents() -> Array[RoadLaneAgent]:
	for agent in _agents_in_lane:
		if (not is_instance_valid(agent)) or agent.is_queued_for_deletion():
			print("problematic agent ", agent, " in lane ", self)
			_agents_in_lane.erase(agent)
	return _agents_in_lane


func get_lane_end_point_by_dir(dir: LaneDirection) -> Vector3:
	return get_lane_start() if dir == LaneDirection.FORWARD else get_lane_end()


func _instantiate_geom() -> void:
	if Engine.is_editor_hint():
		_display_fins = _draw_in_editor or _draw_override
	else:
		_display_fins = _draw_in_game or _draw_override

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


func _exit_tree() -> void:
	if auto_free_vehicles:
		for agent in _agents_in_lane:
			if is_instance_valid(agent):
				agent.actor.call_deferred("queue_free")


#endregion
# ------------------------------------------------------------------------------
