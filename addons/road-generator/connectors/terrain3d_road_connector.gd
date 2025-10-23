@tool
class_name RoadTerrain3DConnector
extends Node

const RoadSegment = preload("res://addons/road-generator/nodes/road_segment.gd")

## Workaround to avoid typing errors for people who aren't using this connector
## https://github.com/TokisanGames/Terrain3D/blob/bbef16d70f7553caad9da956651336f592512406/src/terrain_3d_region.h#L17C3-L17C14
const TERRAIN_3D_MAPTYPE_HEIGHT:int = 0 # Terrain3DRegion.MapType.TYPE_HEIGHT
const TERRAIN_3D_MAPTYPE_CONTROL:int = 1 # Terrain3DRegion.MapType.TYPE_CONTROL
@export var road_collision_layer = 2

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

enum Flatten_terrain_option {CURVED, RAYCAST}

@export var flatten_terrain_method :Flatten_terrain_option = Flatten_terrain_option.CURVED

## Immediately level the terrain to match roads
## Only supported in Godot 4.4+, re-enable if that applies to you
#@export_tool_button("Refresh", "Callable") var refresh_action = do_full_refresh
#@export_tool_button("Bake Holes", "Callable") var bake_holes_action = bake_holes

# If using Auto Refresh, how often to update the UI (lower values = heavier cpu use)
var refresh_timer: float = 0.05

var _pending_updates:Dictionary[RoadSegment,bool] = {} # Hashset of RoadSegments to be updated
var _timer:SceneTreeTimer
var _mutex:Mutex = Mutex.new()
var _skip_scene_load: bool = true

func _ready() -> void:
	if not flatten_terrain_method:
		flatten_terrain_method = Flatten_terrain_option.CURVED
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

## Removes mesh under roads as a baking process.
func bake_holes() -> void:
	if not is_configured():
		return
	for _container in road_manager.get_containers():
		_container = _container as RoadContainer
		var segs:Array = _container.get_segments()
		for _seg in segs:
			cull_terrain_via_roadsegment(_seg)
			
	terrain.data.update_maps(TERRAIN_3D_MAPTYPE_CONTROL)

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
		
		print(str(flatten_terrain_method))
		match flatten_terrain_method:
			Flatten_terrain_option.CURVED:
				flatten_terrain_via_roadsegment(_seg)
			Flatten_terrain_option.RAYCAST:
				flatten_terrain_via_roadsegment_raycast(_seg)
			_:
				flatten_terrain_via_roadsegment(_seg)
		
	terrain.data.update_maps(TERRAIN_3D_MAPTYPE_HEIGHT)


## Flatten and Culling Methods
func flatten_terrain_via_roadsegment_raycast(segment: RoadSegment) -> void:
	if not validate_segment(segment):
		return
	
	road_manager.on_road_updated.disconnect(_on_manager_road_updated)
	road_manager.on_container_transformed.disconnect(_on_container_transform)
	
	# add extra width to the shoulders for the raycasting,
	var buffer = edge_margin + edge_falloff
	segment.start_point.shoulder_width_l += buffer
	segment.start_point.shoulder_width_r += buffer
	segment.end_point.shoulder_width_l += buffer
	segment.end_point.shoulder_width_r += buffer
	segment.container.rebuild_segments()
	
	var mesh := segment.road_mesh.mesh
	if mesh == null:
		return
	
	# clean up any lingering collision meshes
	for ch in segment.road_mesh.get_children():
		ch.queue_free()  # Prior collision meshes
	
	# create new colission mesh for eventual raycasting
	segment.road_mesh.create_trimesh_collision()
	var space_states: Array[PhysicsDirectSpaceState3D] = []
	for ch in segment.road_mesh.get_children():
		var sbody := ch as StaticBody3D # Set to null if casting fails
		if not sbody:
			continue
		sbody.collision_layer = road_collision_layer
		sbody.collision_mask = road_collision_layer
		space_states.append(sbody.get_world_3d().direct_space_state)

	# Create a 2D Mask for segment to reduce 3D raycasts	
	var curve: Curve3D = segment.curve
	var boundingCurve: Curve2D = curve_3d_to_2d(curve)
	var start_width: float = get_road_width(segment.start_point)
	var end_width: float = get_road_width(segment.end_point)
	var bounding_box_offset = Vector2(segment.start_point.global_position.x,segment.start_point.global_position.z)
	var bounding_polygon: PackedVector2Array = curve_2d_to_boundingbox(boundingCurve,start_width,end_width, bounding_box_offset)
	
	var vertex_spacing: float = terrain.vertex_spacing

	# Get global bounding box from mesh, expanded by affected smoothing radius
	var offsets := Vector3(buffer, 0, buffer)
	var aabb: AABB = segment.road_mesh.global_transform * segment.road_mesh.get_aabb()
	var aabb_min := aabb.position - offsets
	var aabb_max := aabb.position + aabb.size + offsets

	# Snap bounds to terrain grid
	var min := Vector3(aabb_min.x, 0, aabb_min.z).snapped(Vector3(vertex_spacing, 0, vertex_spacing))
	var max := Vector3(aabb_max.x, 0, aabb_max.z).snapped(Vector3(vertex_spacing, 0, vertex_spacing)) + Vector3(vertex_spacing, 0, vertex_spacing)

	# itterate over the xz plane of the curve
	var x = min.x
	while x <= max.x:
		var z = min.z
		while z <= max.z:
			if not Geometry2D.is_point_in_polygon(Vector2(x,z), bounding_polygon):
				z+= vertex_spacing
				continue
			
			# create raycast to check the height at the (x,z) coords
			var height := get_road_height(x,z,aabb_min.y,aabb_max.y,space_states)
			if height.size() > 0:
				terrain.data.set_height(Vector3(x, height[0], z), height[0] + offset)
			
			z += vertex_spacing
		x += vertex_spacing
		
	# free the temporary collision meshs we created
	for ch in segment.road_mesh.get_children():
		ch.queue_free()
		
	# cleanup the extra shoulder width and rebuild the original mesh
	segment.start_point.shoulder_width_l -= buffer
	segment.start_point.shoulder_width_r -= buffer
	segment.end_point.shoulder_width_l -= buffer
	segment.end_point.shoulder_width_r -= buffer
	segment.container.rebuild_segments()
	
	#re-enable the signal for road updates since they were turned off prior
	configure_road_update_signal()

func flatten_terrain_via_roadsegment(segment: RoadSegment) -> void:
	if not validate_segment(segment):
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
		
func cull_terrain_via_roadsegment(segment: RoadSegment) -> void:
	if not validate_segment(segment):
		print_debug("not valid for culling")
		return

	var mesh := segment.road_mesh.mesh
	if mesh == null:
		print_debug("no mesh found for road, won't cut")
		return
	
	# clean up any lingering collision meshes
	for ch in segment.road_mesh.get_children():
		ch.queue_free()  # Prior collision meshes
	
	# create new colission mesh for eventual raycasting
	print_debug("creating trimesh for hole culling")
	segment.road_mesh.create_trimesh_collision()
	var space_states: Array[PhysicsDirectSpaceState3D] = []
	for ch in segment.road_mesh.get_children():
		var sbody := ch as StaticBody3D # Set to null if casting fails
		if not sbody:
			continue
		sbody.collision_layer = road_collision_layer
		sbody.collision_mask = road_collision_layer
		space_states.append(sbody.get_world_3d().direct_space_state)
	
	# Create a 2D Mask for segment to reduce 3D raycasts	
	var curve: Curve3D = segment.curve
	var boundingCurve: Curve2D = curve_3d_to_2d(curve)
	var start_width: float = get_road_width(segment.start_point)
	var end_width: float = get_road_width(segment.end_point)
	var bounding_box_offset = Vector2(segment.start_point.global_position.x,segment.start_point.global_position.z)
	var bounding_polygon: PackedVector2Array = curve_2d_to_boundingbox(boundingCurve,start_width,end_width, bounding_box_offset)
	
	var vertex_spacing: float = terrain.vertex_spacing

	# Get global bounding box from mesh, expanded by affected smoothing radius
	var offsets := Vector3(edge_margin+edge_falloff, 0, edge_margin+edge_falloff)
	var aabb: AABB = segment.road_mesh.global_transform * segment.road_mesh.get_aabb()
	var aabb_min := aabb.position - offsets
	var aabb_max := aabb.position + aabb.size + offsets

	# Snap bounds to terrain grid
	var min := Vector3(aabb_min.x, 0, aabb_min.z).snapped(Vector3(vertex_spacing, 0, vertex_spacing))
	var max := Vector3(aabb_max.x, 0, aabb_max.z).snapped(Vector3(vertex_spacing, 0, vertex_spacing)) + Vector3(vertex_spacing, 0, vertex_spacing)

	# hashset for xz plane where the road overlaps the Terrain
	var intersect_coords: Dictionary[Vector2,bool]
	
	# itterate over the xz plane of the curve to find intersecting points which are hidden
	var x = min.x
	while x <= max.x:
		var z = min.z
		while z <= max.z:
			# ignore the coords outside of the bounding polygon
			if not Geometry2D.is_point_in_polygon(Vector2(x,z), bounding_polygon):
				z+= vertex_spacing
				continue
			# check that the road does infact cover the terrain on (x,z)
			if get_road_height(x,z,aabb_min.y,aabb_max.y,space_states,0).size() > 0:
				intersect_coords[Vector2(x,z)] = true
			z += vertex_spacing
		x += vertex_spacing
		
	# free the temporary collision meshs we created
	for ch in segment.road_mesh.get_children():
		ch.queue_free()
	
	print(str(intersect_coords.keys()))
	# add hole for each point which has all 8 neighbours on x-z plane
	for point in intersect_coords.keys():
		if intersect_coords.has(Vector2(point.x - vertex_spacing,point.y)) \
		and intersect_coords.has(Vector2(point.x + vertex_spacing,point.y)) \
		and intersect_coords.has(Vector2(point.x,point.y - vertex_spacing)) \
		and intersect_coords.has(Vector2(point.x,point.y + vertex_spacing)) \
		and intersect_coords.has(Vector2(point.x - vertex_spacing,point.y - vertex_spacing)) \
		and intersect_coords.has(Vector2(point.x + vertex_spacing,point.y + vertex_spacing)) \
		and intersect_coords.has(Vector2(point.x + vertex_spacing,point.y - vertex_spacing)) \
		and intersect_coords.has(Vector2(point.x - vertex_spacing,point.y + vertex_spacing)): 
			terrain.data.set_control_hole(Vector3(point.x, 0, point.y), true)

## Helper Methods
# TODO: Move this utility into the RoadSegment (with offset) or RoadPoint class (no offset)
func get_road_width(point: RoadPoint) -> float:
	return (point.gutter_profile.x*2
		+ point.shoulder_width_l
		+ point.shoulder_width_r
		+ point.lane_width * point.lanes.size()
	)

## Used to create a "Mask" 
func curve_3d_to_2d(curve: Curve3D) -> Curve2D:
	var curve2d := Curve2D.new()
	var point_count := curve.get_point_count()
	
	for i in point_count:
		var pos3 = curve.get_point_position(i)
		var in3 = curve.get_point_in(i)
		var out3 = curve.get_point_out(i)
		var tilt = curve.get_point_tilt(i)

		# Project to XZ plane (drop Y)
		var pos2 = Vector2(pos3.x, pos3.z)
		var in2 = Vector2(in3.x, in3.z)
		var out2 = Vector2(out3.x, out3.z)

		curve2d.add_point(pos2, in2, out2)

	return curve2d

func curve_2d_to_boundingbox(curve: Curve2D, start_width: float, end_width: float, offset: Vector2) -> PackedVector2Array:
	var baked := curve.get_baked_points()
	var count := baked.size()
	var result := PackedVector2Array()
	if count < 2:
		return result

	var left_points: Array[Vector2] = []
	var right_points: Array[Vector2] = []

	
	# first tangent
	var extrapolated_neg_1 = baked[0] - baked[1]
	var tangent: Vector2 = (baked[0] - extrapolated_neg_1).normalized()
	var perpendicular_right = tangent.rotated(deg_to_rad(90))
	var perpendicular_left = tangent.rotated(deg_to_rad(-90))
	left_points.append(extrapolated_neg_1 + perpendicular_left * start_width + offset)
	right_points.append(extrapolated_neg_1 + perpendicular_right * start_width + offset)
		
	for i in count:
		if i == 0:
			tangent = (baked[1] - baked[0]).normalized()
		elif i == count - 1:
			tangent = (baked[i] - baked[i - 1]).normalized()
		else:
			tangent = (baked[i+1] - baked[i-1]).normalized()
		perpendicular_right = tangent.rotated(deg_to_rad(90))
		perpendicular_left = tangent.rotated(deg_to_rad(-90))
		var t := float(i) / float(count - 1)
		var width := lerpf(start_width, end_width, t) * 0.5
		left_points.append(baked[i] + perpendicular_left * width + offset)
		right_points.append(baked[i] + perpendicular_right * width + offset)
		
	var extrapolated_last = baked[count - 1] + (baked[count - 1] - baked[count - 2])
	tangent = (extrapolated_last - baked[count - 1]).normalized()
	perpendicular_right = tangent.rotated(deg_to_rad(90))
	perpendicular_left = tangent.rotated(deg_to_rad(-90))
	left_points.append(extrapolated_last + perpendicular_left * end_width + offset)
	right_points.append(extrapolated_last + perpendicular_right * end_width + offset)
		
	right_points.reverse()
	result.append_array(PackedVector2Array(left_points))
	result.append_array(PackedVector2Array(right_points))
	return result

func validate_segment(segment: RoadSegment) -> bool:
	if not is_instance_valid(segment):
		return false
	if not is_instance_valid(segment.start_point) or not is_instance_valid(segment.end_point):
		return false
	return is_instance_valid(segment.road_mesh)

# can't be nullable so an empty array indicates null (failed to find a height)
func get_road_height(x: float, z: float, min_y: float, max_y: float, space_states: Array[PhysicsDirectSpaceState3D], order: int = 1) -> Array[float]:
	var ray := PhysicsRayQueryParameters3D.create(Vector3(x, max_y, z),Vector3(x, min_y, z))
	ray.collision_mask = road_collision_layer
	var set_height := false
	var height:float = 0.0 
	for state in space_states:
		var result = state.intersect_ray(ray)
		if not result.is_empty() and result.has("position"):
			if not set_height: 
				set_height = true
				height = result["position"].y
			else:
				height = max(height, result["position"].y)
	if set_height:
		return [height]
	elif order == 0:
		return []
	var vertex_spacing = terrain.vertex_spacing
	var approx = []
	approx.append_array(get_road_height(x+vertex_spacing,z,min_y,max_y,space_states, order - 1))
	approx.append_array(get_road_height(x-vertex_spacing,z,min_y,max_y,space_states, order - 1))
	approx.append_array(get_road_height(x,z+vertex_spacing,min_y,max_y,space_states, order - 1))
	approx.append_array(get_road_height(x,z-vertex_spacing,min_y,max_y,space_states, order - 1))
	if approx.size() > 0:
		return [approx.min()]
	return []
