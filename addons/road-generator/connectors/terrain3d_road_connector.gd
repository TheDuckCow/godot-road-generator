@tool
extends Node

const RoadSegment = preload("res://addons/road-generator/nodes/road_segment.gd")

# Terrain3D
## Reference to the Terrain3D instance, to be flattened
@export var terrain:Terrain3D:
	set(value):
		terrain = value
		configure_road_update_signal()
## Reference to the RoadManager instance, read only
@export var road_manager:RoadManager:
	set(value):
		road_manager = value
		configure_road_update_signal()
## Vertical offset to help avoid z-fighting, negative values will sink the terrain underneath the road
@export var offset:float = -0.5
## Additional flattening to do beyond the edge of the road in meters
## Note: Not yet implemented
@export var edge_margin:float = 0.1
## The falloff to apply for height changes from the edge of the road
## Note: Not yet implemented
@export var edge_falloff:float = 2
# TODO: add property for density
# TODO: add property for falloff beyond edges of road
## If enabled, auto refresh the terrain while manipulating roads
@export var auto_refresh:bool = false:
	set(value):
		auto_refresh = value
		configure_road_update_signal()

# TODO this can be switched to a Dictionary[RoadPoint, RoadPoint]
# once https://github.com/godotengine/godot/issues/103082 is fixed
## Can be used to ignore specific segments of road when performing
## terrain flattening. Array should look like:
## [
##  start of segnment 1,
##  end of segment 1,
##  start of segment 2,
##  end of segment 2,
##  ...
## ]
@export var ignored_road_segments: Array[RoadPoint] = []

## Immediately level the terrain to match roads
@export_tool_button("Refresh", "Callable") var refresh_action = do_full_refresh

# If using Auto Refresh, how often to update the UI (lower values = heavier cpu use)
var refresh_timer: float = 0.05

var _pending_updates:Dictionary = {} # TODO: type as RoadSegments, need to update internal typing
var _timer:SceneTreeTimer
var _mutex:Mutex

func _ready() -> void:
	_mutex = Mutex.new()
	configure_road_update_signal()


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
	# TODO: Primary road generator project to expose this on the manager level, to bubble up from
	# individual containers
	for _cont in road_manager.get_containers():
		_cont = _cont as RoadContainer
		if auto_refresh and not _cont.on_road_updated.is_connected(_schedule_refresh):
			_cont.on_road_updated.connect(_schedule_refresh)
		elif not auto_refresh and _cont.on_road_updated.is_connected(_schedule_refresh):
			_cont.on_road_updated.disconnect(_schedule_refresh)


func do_full_refresh() -> void:
	if not is_configured():
		return
	configure_road_update_signal()
	for _container in road_manager.get_containers():
		_container = _container as RoadContainer
		var segs:Array = _container.get_segments()
		refresh_roadsegments(segs)


func _schedule_refresh(segments: Array) -> void:
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
	var _segs := _pending_updates.keys()
	_pending_updates.clear()
	_timer = null
	_mutex.unlock()
	refresh_roadsegments(_segs)
	

func refresh_roadsegments(segments: Array) -> void:
	if not is_configured():
		push_warning("Terrain-Road configuration invalid")
		return
	if not terrain.data:
		push_warning("No terrain data available (yet)")
		return
	for _seg in segments:
		_seg = _seg as RoadSegment

		# check if this segment should be ignored
		var should_ignore := false
		for i in range(0, ignored_road_segments.size(), 2):
			if i + 1 < ignored_road_segments.size():
				var ignored_start := ignored_road_segments[i]
				var ignored_end := ignored_road_segments[i + 1]

				var ignore_from_start = _seg.start_point == ignored_start and _seg.end_point == ignored_end
				var ignore_from_end = _seg.start_point == ignored_end and _seg.end_point == ignored_start

				if ignore_from_start or ignore_from_end:
					should_ignore = true
					break

		if should_ignore:
			print("Skipping ignored segment %s/%s" % [_seg.get_parent().name, _seg.name])
			continue

		print("Refreshing %s/%s" % [_seg.get_parent().name, _seg.name])
		flatten_terrain_via_roadsegment(_seg)
	terrain.data.update_maps(Terrain3DRegion.MapType.TYPE_HEIGHT)


# TODO: Move this utility into the RoadSegment (with offset) or RoadPoint class (no offset)
func get_road_width(point: RoadPoint) -> float:
	return (point.gutter_profile.x*2
		+ point.shoulder_width_l
		+ point.shoulder_width_r
		+ point.lane_width * point.lanes.size()
	)


func flatten_terrain_via_roadsegment(segment: RoadSegment) -> void:
	if not is_instance_valid(segment):
		return
	if not is_instance_valid(segment.start_point) or not is_instance_valid(segment.end_point):
		return

	var mesh := segment.road_mesh.mesh
	if mesh == null:
		return

	var curve: Curve3D = segment.curve
	var start_width: float = get_road_width(segment.start_point)
	var end_width: float = get_road_width(segment.end_point)
	var vertex_spacing: float = terrain.vertex_spacing

	# Get global bounding box from mesh, expanded by affected smoothing radius
	var local_aabb: AABB = mesh.get_aabb()
	var offsets := Vector3(edge_margin+edge_falloff, 0, edge_margin+edge_falloff)
	var aabb: AABB = segment.road_mesh.global_transform * segment.road_mesh.get_aabb()
	var aabb_min := aabb.position - offsets
	var aabb_max := aabb.position + aabb.size + offsets

	# Snap bounds to terrain grid
	var min := Vector3(aabb_min.x, 0, aabb_min.z).snapped(Vector3(vertex_spacing, 0, vertex_spacing))
	var max := Vector3(aabb_max.x, 0, aabb_max.z).snapped(Vector3(vertex_spacing, 0, vertex_spacing)) + Vector3(vertex_spacing, 0, vertex_spacing)

	var world_to_local := segment.global_transform.affine_inverse()

	var x = min.x
	while x <= max.x:
		var z = min.z
		while z <= max.z:
			var world_pos := Vector3(x, 0.0, z)
			var local_pos := world_to_local * world_pos

			var closest_distance := curve.get_closest_offset(local_pos)
			var curve_point := curve.sample_baked(closest_distance)
			var world_curve_point := segment.global_transform * curve_point

			# Check if we are beyond the egde of this RoadSegment, and thus
			# would overlap with updates done by the next RoadSegment
			if closest_distance == 0.0:
				var _offset = world_pos - segment.start_point.global_position 
				var zdist:float = abs(segment.start_point.global_transform.basis.z.dot(_offset))
				if zdist > vertex_spacing:
					z += vertex_spacing
					continue
			if closest_distance == curve.get_baked_length():
				var _offset = world_pos - segment.start_point.global_position 
				var zdist:float = abs(segment.end_point.global_transform.basis.z.dot(_offset))
				if zdist > vertex_spacing:
					z += vertex_spacing
					continue
			
			# TODO: project this world position onto the xz plane of the transform
			# returned at this curvepoint, to account for road tilting
			# Likely making use of: sample_baked_with_rotation
			var road_y := world_curve_point.y + offset
			
			var lateral_vector := world_pos - Vector3(world_curve_point.x, 0.0, world_curve_point.z)

			var t := clamp(closest_distance / curve.get_baked_length(), 0.0, 1.0)
			# Note: this will not be exact as it's not actually linear, as there
			# is some ease/smoothing done for lane count / width changes
			# TODO: Need to account for RoadPoint alignment, right now assumes CENTERED
			# Offset by lane_width * number rev lanes if not centered.
			var width := lerp(start_width, end_width, t)
			
			var lat_dist: float = lateral_vector.length()
			if lat_dist <= width / 2.0 + edge_margin:
				# Flatten to exactly match the road, adding shoulder margin
				var terrain_pos := Vector3(x, road_y, z)
				terrain.data.set_height(terrain_pos, road_y)
			elif lat_dist <= width / 2.0 + edge_margin + edge_falloff:
				# Smoothly interpolate height beyon shoulder to prior height
				# TODO: improve possible creasing issues caused here
				var terrain_pos := Vector3(x, road_y, z)
				var reference_height := terrain.data.get_height(terrain_pos)
				var factor: float = (lat_dist - edge_margin - width / 2.0) / edge_falloff
				var smoothed_height := lerp(road_y, reference_height, ease(factor, -1.5))
				terrain.data.set_height(terrain_pos, smoothed_height)

			z += vertex_spacing
		x += vertex_spacing
