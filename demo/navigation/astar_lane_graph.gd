extends Node3D
## AStar3D pathfinding demo scene
##
## A simple demonstration of pathfinding over RoadLanes, using an AStar3D graph.
## Left-click to set path start, right-click to set path end.

## Pathfinding will look for alternate start/endpoints within this radius
const search_radius_squared := 100.0
## Distance between astar points along road lanes
const astar_point_interval := 10.0

## Mesh used to mark AStar points along RoadLanes
@export var path_marker_mesh: Mesh
## Material used for markers along the current path
@export var path_highlight_material: Material

## Used to track the astar indices of the start & end points of each RoadLane
var endpoints_dict: Dictionary = {}
## AStar point IDs for the most recently plotted route
var id_path: PackedInt64Array

@onready var marker_container: Node3D = $AStarMarkers
@onready var path_start_marker: MeshInstance3D = $PathStartMarker
@onready var path_end_marker: MeshInstance3D = $PathEndMarker
@onready var astar := AStar3D.new()


func _ready() -> void:
	var _road_lanes: Array[Node] = find_children("*", "RoadLane", true, false)
	prints(str(len(_road_lanes)), "RoadLane nodes in scene")

	# Loop over RoadLanes, and place AStar3D points at intervals along each curve
	for _road_lane: RoadLane in _road_lanes:
		var lane_points := _road_lane.curve.get_baked_points()
		var increment_amount := ceili(
				astar_point_interval / _road_lane.curve.bake_interval)
		var idx: int = 0
		var previous_point_id: int

		while idx < len(lane_points) - 1:
			var new_id := astar.get_available_point_id()
			astar.add_point(new_id, _road_lane.to_global(lane_points[idx]))

			var astar_marker := MeshInstance3D.new()
			astar_marker.mesh = path_marker_mesh
			marker_container.add_child(astar_marker)
			astar_marker.global_position = _road_lane.to_global(lane_points[idx])
			astar_marker.set_meta("point_id", new_id)

			if idx == 0: # If this is the first point on this lane, store its id
				endpoints_dict[new_id] = _road_lane
			else: # Make a one-way connection from the previous point to this one
				astar.connect_points(previous_point_id, new_id, false)
			previous_point_id = new_id
			idx += increment_amount

		# Add an astar point at the end of the lane's curve
		var _endpoint_id := astar.get_available_point_id()
		astar.add_point(_endpoint_id,
				_road_lane.to_global(lane_points[len(lane_points) - 1]))
		astar.connect_points(previous_point_id, _endpoint_id, false)

		endpoints_dict[_endpoint_id] = _road_lane # Store the id of this endpoint

		var end_marker := MeshInstance3D.new()
		end_marker.mesh = path_marker_mesh
		marker_container.add_child(end_marker)
		end_marker.global_position = _road_lane.to_global(
				lane_points[len(lane_points) - 1])
		end_marker.set_meta("point_id", _endpoint_id)

	# Loop over endpoints and connect lanes to each other
	for point_idx: int in endpoints_dict.keys():
		var point_pos := astar.get_point_position(point_idx)
		var road_lane: RoadLane = endpoints_dict[point_idx]
		if point_pos == road_lane.to_global(road_lane.curve.get_point_position(0)):
			# Find nearby endpoints and connect them to this one
			var overlapping_indices := endpoints_dict.keys().filter(func(i):
				var other_point_pos := astar.get_point_position(i)
				var other_lane: RoadLane = endpoints_dict[i]
				var other_lane_end_pos := other_lane.to_global(
					other_lane.curve.get_point_position(other_lane.curve.point_count - 1)
				)
				if other_point_pos != other_lane_end_pos:
					return false
				return other_point_pos.distance_squared_to(point_pos) < 1
			)
			for _overlapping_index in overlapping_indices:
				astar.connect_points(_overlapping_index, point_idx, false)

	prints(str(astar.get_point_count()), "points in AStar3D graph")
	return


func _unhandled_input(event: InputEvent) -> void:
	if (
			event is InputEventMouseButton and not event.is_echo()
			and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed()
	):
		var space_state = get_world_3d().direct_space_state
		var ray_params := PhysicsRayQueryParameters3D.new()
		ray_params.from = $Camera3D.project_ray_origin(
				DisplayServer.mouse_get_position())
		ray_params.to = ray_params.from + (
				$Camera3D.project_ray_normal(get_viewport().get_mouse_position()) * $Camera3D.far)

		# Move our start marker to the clicked location, and plot a route
		var _result = space_state.intersect_ray(ray_params)
		if _result.size() > 0:
			path_start_marker.visible = true
			path_start_marker.position = _result.position
			path_start_marker.position.y += 2
			id_path = plot_route()

	if (
			event is InputEventMouseButton and not event.is_echo()
			and event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed()
	):
		var space_state = get_world_3d().direct_space_state
		var ray_params := PhysicsRayQueryParameters3D.new()
		ray_params.from = $Camera3D.project_ray_origin(
				DisplayServer.mouse_get_position())
		ray_params.to = ray_params.from + (
				$Camera3D.project_ray_normal(get_viewport().get_mouse_position()) * $Camera3D.far)

		# Move our end marker to the clicked location, plot a route
		var _result = space_state.intersect_ray(ray_params)
		if _result.size() > 0:
			path_end_marker.visible = true
			path_end_marker.position = _result.position
			path_end_marker.position.y += 2
			id_path = plot_route()
	return

## Return an array of astar point ids, representing a path through our astar graph
func plot_route() -> PackedInt64Array:
	var possible_starts: PackedInt64Array
	var possible_ends: PackedInt64Array
	var nearest_start := astar.get_point_position(
			astar.get_closest_point(path_start_marker.position))
	var nearest_end := astar.get_point_position(
			astar.get_closest_point(path_end_marker.position))

	for _id in astar.get_point_ids(): # Get alternate start and end points
		if (
				astar.get_point_position(_id)
				.distance_squared_to(nearest_start) < search_radius_squared
		):
			possible_starts.push_back(_id)

		if (
				astar.get_point_position(_id)
				.distance_squared_to(nearest_end) < search_radius_squared
		):
			possible_ends.push_back(_id)
	
	var lowest_cost := INF
	var shortest_id_path: PackedInt64Array
	# Loop over possible start & end points to find shortest path
	for possible_start in possible_starts:
		for possible_end in possible_ends:
			var _test_id_path := astar.get_id_path(possible_start, possible_end)
			if len(_test_id_path) == 0: continue
			var path_cost := get_path_cost(_test_id_path)
			if path_cost < lowest_cost:
				lowest_cost = path_cost
				shortest_id_path = _test_id_path

	var markers := marker_container.get_children()
	# Highlight markers along path, un-highlight others
	for marker: MeshInstance3D in markers:
		if marker.get_meta("point_id") in shortest_id_path:
			marker.set_surface_override_material(0, path_highlight_material)
			marker.scale = Vector3(2, 2, 2)
		else:
			marker.set_surface_override_material(0, null)
			marker.scale = Vector3.ONE

	prints("Path cost:", str(roundi(lowest_cost)))
	return shortest_id_path

## Calculate the cost of a given astar path
func get_path_cost(_id_path: PackedInt64Array) -> float:
	var path_cost := 0.0
	var i: int = 0
	while i < len(_id_path) - 2:
		path_cost += astar.get_point_position(_id_path[i]).distance_to(
				astar.get_point_position(_id_path[i + 1])) * astar.get_point_weight_scale(_id_path[i + 1])
		i += 1
	return path_cost
