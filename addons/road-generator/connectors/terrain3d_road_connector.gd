@tool
extends Node

const RoadSegment = preload("res://addons/road-generator/nodes/road_segment.gd")

# Terrain3D
## Reference to the Terrain3D instance, to be flattened
@export var terrain: Terrain3D:
	set(value):
		terrain = value
		configure_road_update_signal()
## Reference to the RoadManager instance, read only
@export var road_manager: RoadManager:
	set(value):
		road_manager = value
		configure_road_update_signal()
## Vertical offset to help avoid z-fighting, applied to edge of road , negative values will sink the terrain underneath the road
@export var gutter_offset: float = 0.0
## Vertical offset to help avoid z-fighting, applied to center of road , negative values will sink the terrain underneath the road
@export var center_offset: float = -1.0
## Horizontal offset to flatten around the road
@export var horizontal_offset: float = 1
# TODO: add property for density
## Horizontal offset to soften  around the height difference after the horizontal_offset
@export var falloff: float = 1
## falloff x = 0 : edge of road, x = falloff away from road, y=1 height of road, y=0 height of terrain, uses smoothstep if null
@export var falloff_curve: Curve
## If enabled, auto refresh the terrain when updating roads. Be careful, changes to terrain are non reversible
@export var auto_refresh: bool = false:
	set(value):
		auto_refresh = value
		configure_road_update_signal()
## Immediately level the terrain to match roads
@export_tool_button("Refresh", "Callable") var refresh_action = do_full_refresh



var _pending_updates: Array = [] # TODO: type as RoadSegments, need to update internal typing
var _timer: SceneTreeTimer
var _mutex: Mutex

#TODO: maybe density
var _traversal_factor := 0.25
var _width_factor := 0.7

var _edited_regions: Dictionary[Terrain3DRegion, bool]


func _ready() -> void:
	_mutex = Mutex.new()
	configure_road_update_signal()


func is_configured() -> bool:
	var has_error: bool = false
	if not is_instance_valid(road_manager):
		push_warning("Road manager not assigned for terrain flattening")
		has_error = true
	if not is_instance_valid(terrain):
		push_warning("Terrain not assigned for terrain flattening")
		has_error = true
	return not has_error


func configure_road_update_signal() -> void:
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


func do_full_refresh():
	print("do_full_refresh")
	if not is_configured():
		return
	for _container in road_manager.get_containers():
		_container = _container as RoadContainer
		var segs: Array = _container.get_segments()
		refresh_roadsegments(segs)


func refresh_roadsegments(segments: Array) -> void:
	print("refresh_roadsegments")
	if not is_configured():
		push_warning("Terrain-Road configuration invalid")
		return
	if not terrain.data:
		push_warning("No terrain data available (yet)")
		return
	for _seg in segments:
		_seg = _seg as RoadSegment
		print("Refreshing %s/%s" % [_seg.get_parent().name, _seg.name])
		flatten_terrain_via_roadsegment(_seg)

	terrain.data.update_maps(Terrain3DRegion.TYPE_HEIGHT, false)
	for region in _edited_regions:
		region.set_edited(false)
	_edited_regions.clear()


# TODO: Move this utility into the RoadSegment (with offset) or RoadPoint class (no offset)
func get_road_width(point: RoadPoint) -> float:
	return(point.gutter_profile.x * 2
		+ point.shoulder_width_l
		+ point.shoulder_width_r
		+ point.lane_width * point.lanes.size()
	)

# TODO: Move this utility into the RoadSegment (with offset) or RoadPoint class (no offset)
func get_half_road_width(point: RoadPoint, first: bool) -> float:
	var count_lanes := 0
	var lane_dir := point.traffic_dir[0]

	for lane in point.traffic_dir:
		if lane == lane_dir:
			count_lanes += 1

	if not first:
		count_lanes = point.traffic_dir.size() - count_lanes

	return(point.gutter_profile.x
		+ point.shoulder_width_l
		+ point.lane_width * count_lanes
	)


func flatten_terrain_via_roadsegment(segment: RoadSegment):

	var curve: Curve3D = segment.curve
	var points := curve.get_baked_points()

	if not is_instance_valid(segment.start_point) or not is_instance_valid(segment.end_point):
		return

	var vertex_spacing := terrain.get_vertex_spacing()
	var next_offset := vertex_spacing

	var size: float = curve.get_baked_length()

	# Get the starting/ending widths to interpolate between
	var start_width_l: float
	var start_width_r: float
	var end_width_l: float
	var end_width_r: float
	
	#get correct width according to alignment
	if segment.start_point.alignment == RoadPoint.Alignment.DIVIDER:
		start_width_l = get_half_road_width(segment.start_point, true)
		start_width_r = get_half_road_width(segment.start_point, false)
	else:
		var width := get_road_width(segment.start_point)
		start_width_l = width * 0.5
		start_width_r = start_width_l

	if segment.end_point.alignment == RoadPoint.Alignment.DIVIDER:
		end_width_l = get_half_road_width(segment.end_point, true)
		end_width_r = get_half_road_width(segment.end_point, false)
	else:
		var width := get_road_width(segment.end_point)
		end_width_l = width * 0.5
		end_width_r = start_width_l

	var pt_a := curve.get_point_position(0)
	var pt_b := curve.get_point_position(0) + curve.get_point_out(0)
	var pt_c := curve.get_point_position(1) + curve.get_point_in(1)
	var pt_d := curve.get_point_position(1)

	var forward := _bezier_tangent_cubic(pt_a, pt_b, pt_c, pt_d, 0).normalized()
	var next_forward := _bezier_tangent_cubic(pt_a, pt_b, pt_c, pt_d, 0).normalized()
	var pidx := 0.0

	while pidx <= size:
		var curve_offset := pidx / size

		var local_point := curve.sample_baked(pidx, true)

		var point := segment.global_transform.origin + segment.global_transform.basis * local_point

		var _region_0 := terrain.data.get_regionp(point)
		if not _edited_regions.has(_region_0):
			_region_0.set_edited(true)
			_edited_regions.set(_region_0, true)

		#interpolating width
		var side := segment._normal_for_offset(curve, curve_offset)
		var width_l := lerpf(start_width_l, end_width_l, curve_offset)
		var width_r := lerpf(start_width_r, end_width_r, curve_offset)

		#interpolating gutter height
		var start_offset: float = segment.start_point._get_profile().y
		var end_offset: float = segment.end_point._get_profile().y
		var gutter_height := lerp(start_offset, end_offset, curve_offset)

		#calculate instantaneous curve radius
		var local_point_1 := curve.sample_baked(pidx - next_offset * .5, true)
		var local_point_2 := curve.sample_baked(pidx + next_offset * .5, true)

		var R := circle_radius_from_3pts(local_point_1, local_point, local_point_2)

		var projection := 1 + (maxf(width_l, width_r) + horizontal_offset + falloff) / R
		
		next_offset = (vertex_spacing * _traversal_factor) / projection

		var tan := _bezier_tangent_cubic(pt_a, pt_b, pt_c, pt_d, minf((pidx + next_offset) / size, 1))
		tan.y = 0

		forward = next_forward
		next_forward = tan.normalized()

		#to know which side is outer and inner
		var signed_angle := forward.signed_angle_to(next_forward, Vector3.UP)

		var start_terminated := (pidx == 0 and segment.start_point.terminated)
		var end_terminated := (pidx > (size - next_offset) and segment.end_point.terminated)

		var side_offset := point
		side_offset = _flatten_sides(point, width_l, R, -signed_angle, -side, forward, next_forward, gutter_height, vertex_spacing, [start_terminated, end_terminated])

		var _region_1 = terrain.data.get_regionp(side_offset)
		if not _edited_regions.has(_region_1):
			_region_1.set_edited(true)
			_edited_regions.set(_region_1, true)

		side_offset = _flatten_sides(point, width_r, R, signed_angle, side, forward, next_forward, gutter_height, vertex_spacing, [start_terminated, end_terminated])

		var _region_2 := terrain.data.get_regionp(side_offset)
		if not _edited_regions.has(_region_2):
			_region_2.set_edited(true)
			_edited_regions.set(_region_2, true)

		pidx += next_offset
		terrain.data.update_maps(Terrain3DRegion.TYPE_HEIGHT, false)
		for region in _edited_regions:
			region.set_edited(false)
		_edited_regions.clear()




func circle_radius_from_3pts(p_A: Vector3, p_B: Vector3, p_C: Vector3) -> float:
	var A := Vector2(p_A.x, p_A.z)
	var B := Vector2(p_B.x, p_B.z)
	var C := Vector2(p_C.x, p_C.z)

	var a = B.distance_to(C)
	var b = C.distance_to(A)
	var c = A.distance_to(B)

	var cross = (B.x - A.x) * (C.y - A.y) - (B.y - A.y) * (C.x - A.x)
	var area = abs(cross) * 0.5
	if area < 1e-9:
		return INF
	return(a * b * c) / (4.0 * area)


func _bezier_tangent_cubic(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var u = 1.0 - t
	var term1 = (3.0 * u * u) * (p1 - p0)
	var term2 = (6.0 * u * t) * (p2 - p1)
	var term3 = (3.0 * t * t) * (p3 - p2)
	return term1 + term2 + term3


func _flatten_sides(
	central_point: Vector3,
	width: float,
	R: float,
	signed_angle: float,
	side: Vector3,
	forward: Vector3,
	next_forward: Vector3,
	gutter_height: float,
	vertex_spacing: float,
	terminated_ends: Array[bool]
) -> Vector3:
	var side_offset := 0.0
	var side_point := central_point
	var limit := width + horizontal_offset + falloff

	var array: PackedVector3Array = []

	while true:
		var projection := (1 + (side_offset) / R)
		var stretch := ((vertex_spacing / projection if signed_angle > 0 else(vertex_spacing * projection)))
		var cur_stretch := stretch


		var is_terminated := (terminated_ends[1] or terminated_ends[0])

		#sub iteration to cover more distance when road curve is bigger
		while cur_stretch >= 0:
			var dir_weight := (cur_stretch / stretch)
			var dir := forward.lerp(next_forward, dir_weight)
			side_point = central_point + (side * side_offset) + dir * cur_stretch
			var max_offset := central_point + (side * (limit + vertex_spacing)) + (dir * cur_stretch)

			var v_offset := ((gutter_height + gutter_offset) if side_offset > width else(gutter_height + gutter_offset + center_offset * (1 - side_offset / width)))

			var base_height := side_point.y + v_offset
			var height := base_height
			
			#apply falloff to sides of roadsegmen
			if side_offset >= width:
				if not is_zero_approx(falloff):
					var x := clampf((side_offset - (width + horizontal_offset)) / falloff, 0, 1)
					var falloff_weight := ((1 - falloff_curve.sample_baked(x)) if falloff_curve != null
						else smoothstep(width + horizontal_offset, limit, side_offset))
					height = lerp(base_height, terrain.data.get_height(max_offset), falloff_weight)

			terrain.data.set_height(side_point, height)

			#apply falloff to terminated roadpoints
			base_height = height - (v_offset if side_offset < width else 0.0)
			if is_terminated and not is_zero_approx(falloff):
				dir = forward if terminated_ends[1] else - forward
				dir.y = 0
				var idx := 0.0
				var end_point := side_point
				var max_end_offset := end_point + (dir * (falloff + vertex_spacing))
				while idx <= falloff:

					var x := clampf(idx / falloff, 0, 1)
					var falloff_weight := ((1 - falloff_curve.sample_baked(x)) if falloff_curve != null
						else smoothstep(0, falloff, idx))

					height = lerp(base_height, terrain.data.get_height(max_end_offset), falloff_weight)
					end_point = side_point + (dir * idx)
					terrain.data.set_height(end_point, height)

					idx += vertex_spacing * _width_factor

					var _region := terrain.data.get_regionp(max_end_offset)
					if not _edited_regions.has(_region):
						_region.set_edited(true)
						_edited_regions.set(_region, true)

			cur_stretch -= vertex_spacing * _width_factor

		if side_offset > limit:
			break
		side_offset += vertex_spacing * _width_factor

	return side_point


func _schedule_refresh(segments: Array) -> void:
	print("_schedule_refresh")
	_mutex.lock()
	_pending_updates += segments
	if not is_instance_valid(_timer):
		print("\tCreated timer")
		_timer = get_tree().create_timer(0.5)
	else:
		print("\tTime left: ", _timer.get_time_left())
	if not _timer.timeout.is_connected(_refresh_scheduled_segments):
		print("\tConnecting timer")
		_timer.timeout.connect(_refresh_scheduled_segments)
	_mutex.unlock()


func _refresh_scheduled_segments() -> void:
	print("_refresh_scheduled_segments")
	_mutex.lock()
	var _segs := _pending_updates.duplicate()
	_pending_updates.clear()
	_timer = null
	_mutex.unlock()
	refresh_roadsegments(_segs)
