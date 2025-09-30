@tool
class_name RoadTerrain3DConnector
extends Node

const RoadSegment = preload("res://addons/road-generator/nodes/road_segment.gd")

## Workaround to avoid typing errors for people who aren't this connector
## https://github.com/TokisanGames/Terrain3D/blob/bbef16d70f7553caad9da956651336f592512406/src/terrain_3d_region.h#L17C3-L17C14
const TERRAIN_3D_MAPTYPE_HEIGHT:int = 0 # Terrain3DRegion.MapType.TYPE_HEIGHT

# Terrain3D
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
@export var auto_refresh:bool = false:
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
var _skip_scene_load: bool = true

func _ready() -> void:
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


func do_full_refresh() -> void:
	if not is_configured():
		return
	configure_road_update_signal()
	var restart_geo_off: Array[RoadContainer] = []
	var init_auto_refresh: bool = auto_refresh
	for _container in road_manager.get_containers():
		_container = _container as RoadContainer

		if not _container.create_geo:
			#print("Temp enabling geo on RoadContainer:", _container.name)
			init_auto_refresh = false
			_container.create_geo = true
			_container.rebuild_segments(true)
			init_auto_refresh = init_auto_refresh
			restart_geo_off.append(_container)
			
		var segs:Array = _container.get_segments()
		refresh_roadsegments(segs)
		
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
	refresh_roadsegments(container.get_segments())
	container.create_geo = false


func _on_manager_road_updated(segments: Array) -> void:
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
		if not is_instance_valid(_seg):
			# Will happen (at a minimum) when handling RoadContainers which have
			# create geo turned off AND auto_refresh is on; creates an extra
			# deferred call to here when those segments are temporarily added,
			# but will be invalid by the time this function actually runs as
			# they are destroyed right away after a direct call to this func
			continue
		_seg = _seg as RoadSegment

		# check if this segment should be ignored
		if (
			not _seg.container.flatten_terrain
			or (not _seg.start_point.flatten_terrain and not _seg.end_point.flatten_terrain)
		):
			print("Skipping ignored segment %s/%s" % [_seg.get_parent().name, _seg.name])
			continue

		print("Refreshing %s/%s" % [_seg.get_parent().name, _seg.name])
		flatten_terrain_via_roadsegment(_seg)
	terrain.data.update_maps(TERRAIN_3D_MAPTYPE_HEIGHT)


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
	if not is_instance_valid(segment.road_mesh):
		return

	var mesh := segment.road_mesh.mesh
	if mesh == null:
		return

	var curve: Curve3D = segment.curve
	var start_width: float = get_road_width(segment.start_point)
	var end_width: float = get_road_width(segment.end_point)
	var vertex_spacing: float = terrain.vertex_spacing

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

			var closest_distance := curve.get_closest_offset(local_pos)
			var curve_point := curve.sample_baked(closest_distance)
			var world_curve_point := segment.global_transform * curve_point

			# Check if we are beyond the egde of this RoadSegment, and thus
			# would overlap with updates done by the next RoadSegment
			if closest_distance == 0.0:
				var _offset = world_pos - segment.start_point.global_position 
				var zdist := absf(segment.start_point.global_transform.basis.z.dot(_offset))
				if zdist > vertex_spacing:
					z += vertex_spacing
					continue
			if closest_distance == curve.get_baked_length():
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

			var t := clamp(closest_distance / curve.get_baked_length(), 0.0, 1.0)
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
				var smoothed_height := lerpf(road_y, reference_height, ease(factor, -1.5))
				terrain.data.set_height(terrain_pos, smoothed_height)

			z += vertex_spacing
		x += vertex_spacing
