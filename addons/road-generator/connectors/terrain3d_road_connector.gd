@tool
class_name RoadTerrain3DConnector
extends Node

const RoadSegment = preload("res://addons/road-generator/nodes/road_segment.gd")
const IntersectionNGon = preload("res://addons/road-generator/procgen/intersection_ngon.gd")

## Workaround to avoid typing errors for people who aren't this connector
## https://github.com/TokisanGames/Terrain3D/blob/bbef16d70f7553caad9da956651336f592512406/src/terrain_3d_region.h#L17C3-L17C14
const TERRAIN_3D_MAPTYPE_HEIGHT:int = 0 # Terrain3DRegion.MapType.TYPE_HEIGHT


## Reference to the Terrain3D instance, to be flattened
@export var terrain:Node3D: #Terrain3D:
	set(value):
		terrain = value
		configure_road_update_signal()
		if is_node_ready():
			_skip_scene_load = false
## Reference to the RoadManager instance, read only
@export var road_manager:RoadManager:
	set(value):
		road_manager = value
		configure_road_update_signal()
		if is_node_ready():
			_skip_scene_load = false
## Vertical offset to help avoid z-fighting, negative values will sink the terrain underneath the road
@export var offset:float = -0.25
## Additional flattening to do beyond the edge of the road in meters
@export var edge_margin:float = 0.5
## The falloff to apply for height changes from the edge of the road.
## This falloff range begins beyond the edge of the road + edge margin
@export var edge_falloff:float = 2
## If enabled, auto refresh the terrain while manipulating roads. 
##
## WARNING: if left on, each time scene is opened (tabbed over to), the terrain
## will continue to be flattened, eventually making the smooth falloff not so smooth
@export var auto_refresh:bool = true:
	set(value):
		auto_refresh = value
		configure_road_update_signal()


## Immediately level the terrain to match roads
## Only supported in Godot 4.4+, re-enable if that applies to you
#@export_tool_button("Refresh", "Callable") var refresh_action = do_full_refresh

# If using Auto Refresh, how often to update the UI (lower values = heavier cpu use)
var refresh_timer: float = 0.05

var _pending_updates:Dictionary = {} # TODO: type as RoadSegments, need to update internal typing
var _timer:SceneTreeTimer
var _mutex:Mutex = Mutex.new()
var _skip_scene_load: bool = true # Also directly referecned by plugin to ensure top-level refresh works


func _ready() -> void:
	configure_road_update_signal()


func _enter_tree() -> void:
	if is_node_ready():
		configure_road_update_signal.call_deferred()


func _exit_tree() -> void:
	_disconnect_signals()
	_skip_scene_load = true


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if not is_instance_valid(road_manager):
		warnings.append("Road manager not assigned for terrain flattening")
	if not is_instance_valid(terrain):
		warnings.append("Terrain not assigned for terrain flattening")
	return warnings


func is_configured() -> bool:
	var has_error:bool = false
	if not is_instance_valid(road_manager):
		push_warning("Road manager not assigned for terrain flattening")
		has_error = true
	if not is_instance_valid(terrain):
		push_warning("Terrain not assigned for terrain flattening")
		has_error = true
	return not has_error


func configure_road_update_signal() -> void:
	if not Engine.is_editor_hint():
		# Don't run outside of an editor context
		return
	if not is_instance_valid(road_manager):
		return

	# Handle signals from each RoadContainer when there are updated segments
	if auto_refresh and not road_manager.on_road_updated.is_connected(_on_manager_road_updated):
		road_manager.on_road_updated.connect(_on_manager_road_updated)
	elif not auto_refresh and road_manager.on_road_updated.is_connected(_on_manager_road_updated):
		road_manager.on_road_updated.disconnect(_on_manager_road_updated)
		
	# Handle transforms on containers themelves
	if auto_refresh and not road_manager.on_container_transformed.is_connected(_on_container_transform):
		road_manager.on_container_transformed.connect(_on_container_transform)
	elif not auto_refresh and road_manager.on_container_transformed.is_connected(_on_container_transform):
		road_manager.on_container_transformed.disconnect(_on_container_transform)


## Disconnects signals so avoid excessive refreshing if scene tab is opened again in the editor
func _disconnect_signals() -> void:
	if is_instance_valid(road_manager) and road_manager.on_road_updated.is_connected(_on_manager_road_updated):
		road_manager.on_road_updated.disconnect(_on_manager_road_updated)
	if is_instance_valid(road_manager) and road_manager.on_container_transformed.is_connected(_on_container_transform):
		road_manager.on_container_transformed.disconnect(_on_container_transform)


func do_full_refresh() -> void:
	if not is_configured():
		return
	configure_road_update_signal()
	var restart_geo_off: Array[RoadContainer] = []
	var init_auto_refresh: bool = auto_refresh
	for _container in road_manager.get_containers():
		_container = _container as RoadContainer

		if not _container.create_geo:
			init_auto_refresh = false
			_container.create_geo = true
			_container.rebuild_segments(true)
			init_auto_refresh = init_auto_refresh
			restart_geo_off.append(_container)
			
		var mesh_parents: Array = []
		for inter in _container.get_intersections():
			mesh_parents.append(inter)
		mesh_parents += _container.get_segments() # Always add RoadSegments last
		refresh_roads(mesh_parents)
		
		# Restore the geo setting where temporarily turned on
		for _rc in restart_geo_off:
			_rc.create_geo = false


## Workaround helper to transform geo for intersection scenes or other
## scenarios where "create_geo" is turned off, by temporairly turning it on.
func _on_container_transform(container:RoadContainer) -> void:
	if container.create_geo or not auto_refresh:
		return
	container.create_geo = true
	# This will trigger deferred updates which will have invalid instances,
	# but will be safely ignored
	container.rebuild_segments(true)
	# Must directly update terrain now on these segments, before they get
	# removed again when geo is turned off
	var mesh_parents: Array
	for inter in container.get_intersections():
		mesh_parents.append(inter)
	mesh_parents += container.get_segments()
	refresh_roads(mesh_parents) # Always add RoadSegments last
	container.create_geo = false


func _on_manager_road_updated(segments: Array) -> void:
	if not road_manager or not terrain:
		return # one or the other is not defined
	if not road_manager.is_node_ready() or not terrain.is_node_ready():
		# Likely loading scene for the first time, and thus roads will be
		# generated but it's not expected to perform flattening
		return
	_schedule_refresh(segments)


## Accumulates road segments to be refreshed while an operation is in progress
func _schedule_refresh(segments: Array) -> void:
	if _skip_scene_load:
		_skip_scene_load = false
		return
	_mutex.lock()
	for _seg in segments:
		# Using a dictionary to accumulate updates to process
		_pending_updates[_seg] = true
	if not is_instance_valid(_timer):
		_timer = get_tree().create_timer(refresh_timer)
	else:
		pass
	if not _timer.timeout.is_connected(_refresh_scheduled_segments):
		_timer.timeout.connect(_refresh_scheduled_segments)
	_mutex.unlock()


func _refresh_scheduled_segments() -> void:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_mutex.lock()
		_timer = null
		call_deferred("_schedule_refresh", [])
		_mutex.unlock()
		return
	_mutex.lock()
	var _mesh_parents := _pending_updates.keys()
	_pending_updates.clear()
	_timer = null
	_mutex.unlock()
	refresh_roads(_mesh_parents)


## Refreshes all segments of road identified
##
## Order of segments should be first intersections if any, then road segments
## so that the combined flattening is proper.
func refresh_roads(mesh_parents: Array) -> void:
	if not is_configured():
		push_warning("Terrain-Road configuration invalid")
		return
	if not terrain.data:
		push_warning("No terrain data available (yet)")
		return

	var skip_repeat_refreshes: Array = []
	
	var segs: Array = [] # RoadSegment

	# First flatten all road intersections and gather their adjacent segments
	for _seg in mesh_parents:
		if not is_instance_valid(_seg):
			# Will happen (at a minimum) when handling RoadContainers which have
			# create geo turned off AND auto_refresh is on; creates an extra
			# deferred call to here when those segments are temporarily added,
			# but will be invalid by the time this function actually runs as
			# they are destroyed right away after a direct call to this func
			continue
		if _seg is RoadIntersection:
			var inter := _seg as RoadIntersection
			if inter.container.flatten_terrain and inter.flatten_terrain:
				flatten_terrain_via_intersection(inter)
				# Since the intersection flattening is a little too greedy,
				# must post-flatten the adjacent segments too, even if they
				# weren't scheduled
				var adj_segs = intersection_adjacent_segments(inter)
				segs += adj_segs
				# In case these segmetns were already in the list, avoid repeat
				# flattening them
				# TODO: handle case where one segment is directly connected to
				# two intersections
				skip_repeat_refreshes += inter.edge_points
			continue
		elif _seg is RoadSegment:
			segs.append(_seg)
	
	# Now flatten all accumulated segments
	for _seg in segs:
		if not is_instance_valid(_seg):
			continue
		_seg = _seg as RoadSegment
		if not _seg:
			print("Unexpected non-RoadSegment element")
			continue
		if _seg in skip_repeat_refreshes:
			print("Skipped repeat refresh: ", _seg)
			continue
		# check if this segment should be ignored
		if (
			not _seg.container.flatten_terrain
			or (not _seg.start_point.flatten_terrain and not _seg.end_point.flatten_terrain)
		):
			# print("Skipping ignored segment %s/%s" % [_seg.get_parent().name, _seg.name])
			continue
		#print("Refreshing %s/%s" % [_seg.get_parent().name, _seg.name])
		flatten_terrain_via_roadsegment(_seg)
		skip_repeat_refreshes.append(_seg)
	
	terrain.data.update_maps(TERRAIN_3D_MAPTYPE_HEIGHT)


# TODO: Move this utility into the RoadSegment (with offset) or RoadPoint class (no offset)
func get_road_width(point: RoadPoint) -> float:
	return (point.gutter_profile.x*2
		+ point.shoulder_width_l
		+ point.shoulder_width_r
		+ point.lane_width * point.lanes.size()
	)


## Returns the distance from a 2D point to a line segment (XZ plane).
func _distance_point_to_segment_2d(p: Vector2, a: Vector2, b: Vector2) -> float:
	var v := b - a
	var u := p - a
	var v_len_sq := v.length_squared()
	if is_zero_approx(v_len_sq):
		return p.distance_to(a)
	var t := clampf(u.dot(v) / v_len_sq, 0.0, 1.0)
	var closest := a + t * v
	return p.distance_to(closest)


## Returns the minimum distance from a 2D point to any edge of the polygon.
## Used for points outside the polygon to compute margin/falloff.
func _distance_to_polygon_boundary_2d(point: Vector2, polygon: PackedVector2Array) -> float:
	if polygon.size() < 2:
		return INF
	var min_dist := INF
	for i in range(polygon.size()):
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		var d := _distance_point_to_segment_2d(point, a, b)
		if d < min_dist:
			min_dist = d
	return min_dist


func _flatten_curve(curve: Curve3D, normalization_value: float):
	if is_zero_approx(normalization_value):
		push_error("Division by zero imminent, curve flattening aborted")
		return
		
	for i in range(curve.point_count):
		var pos:Vector3 = curve.get_point_position(i)
		var pos_in:Vector3 = curve.get_point_in(i)
		var pos_out:Vector3 = curve.get_point_out(i)
		
		# Instead of setting pos.y to 0 we divide it by a large enough value so that it becomes effectively flat
		# This is necessary so we can retrieve the height at a later point. 
		pos.y /= normalization_value 
		pos_in.y /= normalization_value 
		pos_out.y /= normalization_value 
		
		curve.set_point_position(i,pos)
		curve.set_point_in(i,pos_in)
		curve.set_point_out(i,pos_out)


func flatten_terrain_via_intersection(inter: RoadIntersection) -> void:
	if not is_instance_valid(inter):
		return
	if not inter.settings is IntersectionNGon:
		push_warning("Intersection flattening only supported for IntersectionNGon. Skipping.")
		return
	if not inter.edge_points.size():
		push_warning("Intersection has no edge points. Skipping terrain flatten.")
		return
	print("Flattening ", inter)

	var center_global: Vector3 = inter.global_position
	var center_y: float = center_global.y + offset
	var vertex_spacing: float = terrain.vertex_spacing

	# Build triangle-fan boundary in world space: [side_l_0, side_r_0, side_l_1, side_r_1, ...]
	# This relies on the fact that edge_points should already be in a clockwise order
	var boundary_world: PackedVector2Array = PackedVector2Array()
	var edge_heights: Array[float] = [center_y]
	for edge in inter.edge_points:
		if not is_instance_valid(edge):
			continue
		var width: float = get_road_width(edge)
		var perp: Vector3 = edge.global_transform.basis.x.normalized()
		
		# TODO: Account for alignment offset once intersections do as well.
		var side_l: Vector3 = edge.global_position - perp * (width * 0.5)
		var side_r: Vector3 = edge.global_position + perp * (width * 0.5)
		if edge.get_prior_road_node(true) == inter:
			# Must insert in the clockwise order, so depends on RP orientation
			var tmp: Vector3 = side_l
			side_l = side_r
			side_r = tmp

		boundary_world.append(Vector2(side_l.x, side_l.z))
		boundary_world.append(Vector2(side_r.x, side_r.z))
		edge_heights.append(edge.global_position.y + offset)
	
	# Simplification for now to just use the lowest y-height amongst all points
	var min_height:float = edge_heights.min()
	if boundary_world.size() < 3:
		return

	# AABB from center and all boundary points, expanded by margin + falloff
	var aabb_min := center_global
	var aabb_max := center_global
	for i in range(boundary_world.size()):
		var v := Vector3(boundary_world[i].x, center_global.y, boundary_world[i].y)
		aabb_min = aabb_min.min(v)
		aabb_max = aabb_max.max(v)
	var offsets := Vector3(edge_margin + edge_falloff, 0.0, edge_margin + edge_falloff)
	aabb_min -= offsets
	aabb_max += offsets

	var min_xz := Vector3(aabb_min.x, 0.0, aabb_min.z).snapped(Vector3(vertex_spacing, 0.0, vertex_spacing))
	var max_xz := Vector3(aabb_max.x, 0.0, aabb_max.z).snapped(Vector3(vertex_spacing, 0.0, vertex_spacing)) + Vector3(vertex_spacing, 0.0, vertex_spacing)

	var x := min_xz.x
	while x <= max_xz.x:
		var z := min_xz.z
		while z <= max_xz.z:
			var pt_2d := Vector2(x, z)

			# TODO: Improve by finding the edge which this point is pointing towards,
			# interpolating the cloesting matching point along that edge,
			# then interpolate along to the center.
			# Instead, for now, we'll just pick the lowest point between them all
			var road_y: float = min_height

			var inside: bool = Geometry2D.is_point_in_polygon(pt_2d, boundary_world)
			var dist_to_boundary: float
			if inside:
				dist_to_boundary = 0.0
			else:
				dist_to_boundary = _distance_to_polygon_boundary_2d(pt_2d, boundary_world)

			if dist_to_boundary <= edge_margin:
				var terrain_pos := Vector3(x, road_y, z)
				terrain.data.set_height(terrain_pos, road_y)
			elif dist_to_boundary <= edge_margin + edge_falloff:
				var terrain_pos := Vector3(x, road_y, z)
				var reference_height: float = terrain.data.get_height(terrain_pos)
				var factor: float = (dist_to_boundary - edge_margin) / edge_falloff
				var smoothed_height: float = _lerp_smoothed_height(road_y, reference_height, factor)
				terrain.data.set_height(terrain_pos, smoothed_height)

			z += vertex_spacing
		x += vertex_spacing


## Called after intersection flattening has completed, to avoid overlap
func intersection_adjacent_segments(inter: RoadIntersection) -> Array:
	var segs: Array = []
	for _edge in inter.edge_points:
		var rp: RoadPoint = _edge as RoadPoint
		if rp.prior_seg:
			segs.append(rp.prior_seg)
		if rp.next_seg:
			segs.append(rp.next_seg)
	return segs


func flatten_terrain_via_roadsegment(segment: RoadSegment) -> void:
	if not is_instance_valid(segment):
		return
	if not is_instance_valid(segment.start_point) or not is_instance_valid(segment.end_point):
		return
	if not is_instance_valid(segment.road_mesh):
		return
	print("Flattening ", segment)
	var mesh := segment.road_mesh.mesh
	if mesh == null:
		return

	var curve: Curve3D = segment.curve
	var start_width: float = get_road_width(segment.start_point)
	var end_width: float = get_road_width(segment.end_point)
	var vertex_spacing: float = terrain.vertex_spacing
	
	# Creat the flattened version of the curve. 
	# Check out the following Issue for more information why this is necessary: https://github.com/TheDuckCow/godot-road-generator/issues/322
	var flattened_curve: Curve3D = curve.duplicate(true)
	# The normalization factor is picked arbitrary here. The steeper the road, the bigger this value needs to be
	# Values that are too big can cause issues because of float accuracy, too small causes the terrain height to be wrong
	var normalization_factor:float = 10000
	_flatten_curve(flattened_curve,normalization_factor)
	
	# Get global bounding box from mesh, expanded by affected smoothing radius
	var offsets := Vector3(edge_margin+edge_falloff, 0, edge_margin+edge_falloff)
	var aabb: AABB = segment.road_mesh.global_transform * segment.road_mesh.get_aabb()
	var aabb_min := aabb.position - offsets
	var aabb_max := aabb.position + aabb.size + offsets

	# Snap bounds to terrain grid
	var min := Vector3(aabb_min.x, 0, aabb_min.z).snapped(Vector3(vertex_spacing, 0, vertex_spacing))
	var max := Vector3(aabb_max.x, 0, aabb_max.z).snapped(Vector3(vertex_spacing, 0, vertex_spacing)) + Vector3(vertex_spacing, 0, vertex_spacing)

	var world_to_local := segment.global_transform.inverse()

	var x = min.x
	while x <= max.x:
		var z = min.z
		while z <= max.z:
			var world_pos := Vector3(x, 0.0, z)
			var local_pos := world_to_local * world_pos

			var closest_distance := flattened_curve.get_closest_offset(local_pos)
			var curve_point := flattened_curve.sample_baked(closest_distance)
			curve_point.y *= normalization_factor
			var world_curve_point := segment.global_transform * curve_point

			# Check if we are beyond the egde of this RoadSegment, and thus
			# would overlap with updates done by the next RoadSegment
			if closest_distance == 0.0:
				var _offset = world_pos - segment.start_point.global_position 
				var zdist := absf(segment.start_point.global_transform.basis.z.dot(_offset))
				if zdist > vertex_spacing:
					z += vertex_spacing
					continue
			if closest_distance == flattened_curve.get_baked_length():
				var _offset = world_pos - segment.end_point.global_position # check this, also if can be flipped..???
				var zdist:float = abs(segment.end_point.global_transform.basis.z.dot(_offset))
				if zdist > vertex_spacing:
					z += vertex_spacing
					continue
			
			# TODO: project this world position onto the xz plane of the transform
			# returned at this curvepoint, to account for road tilting
			# Likely making use of: sample_baked_with_rotation
			var road_y := world_curve_point.y + offset
			
			var lateral_vector := world_pos - Vector3(world_curve_point.x, 0.0, world_curve_point.z)

			var t := clamp(closest_distance / flattened_curve.get_baked_length(), 0.0, 1.0)
			# Note: this will not be exact as it's not actually linear, as there
			# is some ease/smoothing done for lane count / width changes
			# TODO: Need to account for RoadPoint alignment, right now assumes CENTERED
			# Offset by lane_width * number rev lanes if not centered.
			var width := lerpf(start_width, end_width, t)
			
			var lat_dist: float = lateral_vector.length()
			if lat_dist <= width / 2.0 + edge_margin:
				# Flatten to exactly match the road, adding shoulder margin
				var terrain_pos := Vector3(x, road_y, z)
				terrain.data.set_height(terrain_pos, road_y)
			elif lat_dist <= width / 2.0 + edge_margin + edge_falloff:
				# Smoothly interpolate height beyon shoulder to prior height
				# TODO: improve possible creasing issues caused here
				var terrain_pos := Vector3(x, road_y, z)
				var reference_height:float = terrain.data.get_height(terrain_pos)
				var factor: float = (lat_dist - edge_margin - width / 2.0) / edge_falloff
				var smoothed_height := _lerp_smoothed_height(road_y, reference_height, factor)
				terrain.data.set_height(terrain_pos, smoothed_height)

			z += vertex_spacing
		x += vertex_spacing


## Reusable function to perform consistent falloff rate
func _lerp_smoothed_height(road_y: float, terrain_y: float, factor: float) -> float:
	return lerpf(road_y, terrain_y, ease(factor, -1.5))
