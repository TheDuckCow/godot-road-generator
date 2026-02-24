extends Node3D
## AStar3D pathfinding demo scene
##
## A simple demonstration of pathfinding over RoadLanes, using an AStar3D graph.
## Left-click to set path start, right-click to set path end.

## The camera to be used for raycasting, to find where the user is clicking. 
@export var camera: Camera3D
## RoadManager node used to identify RoadLanes and respond to updates.
@export var road_manager: RoadManager
## Mesh used to mark AStar3D points along RoadLanes.
@export var path_marker_mesh: Mesh
## Material used for markers along the current path.
@export var path_highlight_material: Material
## Pathfinding will look for alternate start/endpoints within this radius.
@export var path_search_radius := 10.0
## When reloading the AStar3D graph, lanes whose start & end points are closer
## than this will be connected to each other.
@export var lane_connection_distance := 1.0
## When reloading the graph, AStar3D points will be placed along each RoadLane
## with this much distance between them (except for the final point).
@export var astar_point_interval := 10.0
## Used to track the AStar3D indices of the start & end points of each RoadLane.
var endpoints_dict: Dictionary = {}
## AStar3D point IDs for the most recently plotted route.
var id_path: PackedInt64Array

@onready var marker_container: Node3D = $AStarMarkers
@onready var path_start_marker: MeshInstance3D = $PathStartMarker
@onready var path_end_marker: MeshInstance3D = $PathEndMarker
@onready var astar := AStar3D.new()
@onready var path_search_radius_squared := pow(path_search_radius, 2)
@onready var lane_connection_distance_squared := pow(lane_connection_distance, 2)

## Workaround to forward actions from unhandled input to _physics_process to
## safely perform raycasts
var _raycast_next_phys_frame: bool = false
var _triggering_event: InputEvent

func _ready() -> void:
	reload_graph()
	return


func _physics_process(delta: float) -> void:
	if not _raycast_next_phys_frame:
		return
	_raycast_next_phys_frame = false
	
	if _triggering_event.button_index == MOUSE_BUTTON_LEFT:
		var space_state = get_world_3d().direct_space_state
		var ray_params := PhysicsRayQueryParameters3D.new()
		ray_params.from = camera.project_ray_origin(
				DisplayServer.mouse_get_position())
		ray_params.to = ray_params.from + (
				camera.project_ray_normal(get_viewport().get_mouse_position()) * camera.far)

		# Move our start marker to the clicked location, and plot a route
		var result = space_state.intersect_ray(ray_params)
		if result.size() > 0:
			path_start_marker.visible = true
			path_start_marker.position = result.position
			path_start_marker.position.y += 2
			id_path = plot_route()
	else:
		var space_state = get_world_3d().direct_space_state
		var ray_params := PhysicsRayQueryParameters3D.new()
		ray_params.from = camera.project_ray_origin(
				DisplayServer.mouse_get_position())
		ray_params.to = ray_params.from + (
				camera.project_ray_normal(get_viewport().get_mouse_position()) * camera.far)

		# Move our end marker to the clicked location, plot a route
		var result = space_state.intersect_ray(ray_params)
		if result.size() > 0:
			path_end_marker.visible = true
			path_end_marker.position = result.position
			path_end_marker.position.y += 2
			id_path = plot_route()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.is_pressed() or event.is_echo():
		return
	elif event.button_index == MOUSE_BUTTON_LEFT:
		_raycast_next_phys_frame = true
		_triggering_event = event
		get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_raycast_next_phys_frame = true
		_triggering_event = event
		get_viewport().set_input_as_handled()


## Reload our astar graph.
func reload_graph() -> void:
	if not is_instance_valid(road_manager):
		push_error("RoadManager not defined")
		return

	var road_lanes: Array[Node] = get_tree().get_nodes_in_group(road_manager.ai_lane_group)
	prints(str(len(road_lanes)), "RoadLane nodes in scene")

	# Loop over RoadLanes, and place AStar3D points at intervals along each curve
	for road_lane: RoadLane in road_lanes:
		var lane_points := road_lane.curve.get_baked_points()
		var increment_amount := ceili(
				astar_point_interval / road_lane.curve.bake_interval)
		var idx: int = 0
		var previous_point_id: int

		while idx < len(lane_points) - 1:
			var new_id := astar.get_available_point_id()
			astar.add_point(new_id, road_lane.to_global(lane_points[idx]))

			var astar_marker := MeshInstance3D.new()
			astar_marker.mesh = path_marker_mesh
			marker_container.add_child(astar_marker)
			astar_marker.global_position = road_lane.to_global(lane_points[idx])
			astar_marker.set_meta("point_id", new_id)

			if idx == 0: # If this is the first point on this lane, store its id
				endpoints_dict[new_id] = road_lane
			else: # Make a one-way connection from the previous point to this one
				astar.connect_points(previous_point_id, new_id, false)
			previous_point_id = new_id
			idx += increment_amount

		# Add an astar point at the end of the lane's curve
		var endpoint_id := astar.get_available_point_id()
		astar.add_point(endpoint_id,
				road_lane.to_global(lane_points[len(lane_points) - 1]))
		astar.connect_points(previous_point_id, endpoint_id, false)

		endpoints_dict[endpoint_id] = road_lane # Store the id of this endpoint

		var end_marker := MeshInstance3D.new()
		end_marker.mesh = path_marker_mesh
		marker_container.add_child(end_marker)
		end_marker.global_position = road_lane.to_global(
				lane_points[len(lane_points) - 1])
		end_marker.set_meta("point_id", endpoint_id)

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
				return other_point_pos.distance_squared_to(point_pos) < lane_connection_distance_squared
			)
			for overlapping_index in overlapping_indices:
				astar.connect_points(overlapping_index, point_idx, false)

	prints(str(astar.get_point_count()), "points in AStar3D graph")
	return

## Return an array of astar point ids, representing a path through our astar graph.
func plot_route() -> PackedInt64Array:
	var possible_starts: PackedInt64Array
	var possible_ends: PackedInt64Array
	var nearest_start := astar.get_point_position(
			astar.get_closest_point(path_start_marker.position))
	var nearest_end := astar.get_point_position(
			astar.get_closest_point(path_end_marker.position))

	for point_id in astar.get_point_ids(): # Get alternate start and end points
		if (
				astar.get_point_position(point_id)
				.distance_squared_to(nearest_start) < path_search_radius_squared
		):
			possible_starts.push_back(point_id)

		if (
				astar.get_point_position(point_id)
				.distance_squared_to(nearest_end) < path_search_radius_squared
		):
			possible_ends.push_back(point_id)
	
	var lowest_cost := INF
	var shortest_id_path: PackedInt64Array
	# Loop over possible start & end points to find shortest path
	for possible_start in possible_starts:
		for possible_end in possible_ends:
			var test_id_path := astar.get_id_path(possible_start, possible_end)
			if len(test_id_path) == 0: continue
			var path_cost := get_path_cost(test_id_path)
			if path_cost < lowest_cost:
				lowest_cost = path_cost
				shortest_id_path = test_id_path

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

## Calculate the cost of a given astar path.
func get_path_cost(_id_path: PackedInt64Array) -> float:
	var path_cost := 0.0
	var i: int = 0
	while i < len(_id_path) - 2:
		path_cost += astar.get_point_position(_id_path[i]).distance_to(
				astar.get_point_position(_id_path[i + 1])) * astar.get_point_weight_scale(_id_path[i + 1])
		i += 1
	return path_cost
