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
# TODO: add property for density
# TODO: add property for falloff beyond edges of road
## If enabled, auto refresh the terrain when updating roads
@export var auto_refresh:bool = false:
	set(value):
		auto_refresh = value
		configure_road_update_signal()
## Immediately level the terrain to match roads
@export_tool_button("Refresh", "Callable") var refresh_action = do_full_refresh

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
		var segs:Array = _container.get_segments()
		refresh_roadsegments(segs)


func _schedule_refresh(segments: Array) -> void:
	print("_schedule_refresh")
	_mutex.lock()
	for _seg in segments:
		# Using a dictionary to accumulate updates to process
		_pending_updates[_seg] = true
	if not is_instance_valid(_timer):
		print("\tCreated timer")
		_timer = get_tree().create_timer(0.2)
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
	refresh_roadsegments(_segs.keys())
	

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
	terrain.data.update_maps(Terrain3DRegion.MapType.TYPE_HEIGHT)



# TODO: Move this utility into the RoadSegment (with offset) or RoadPoint class (no offset)
func get_road_width(point: RoadPoint) -> float:
	return (point.gutter_profile.x*2
		+ point.shoulder_width_l
		+ point.shoulder_width_r
		+ point.lane_width * point.lanes.size()
	)


func flatten_terrain_via_roadsegment(segment:RoadSegment):
	var curve:Curve3D = segment.curve
	var points = curve.get_baked_points()
	
	if not is_instance_valid(segment.start_point) or not is_instance_valid(segment.end_point):
		return
	
	# Get the starting/ending widths to interpolate between
	var start_width:float = get_road_width(segment.start_point)
	#var end_width:float = get_road_width(segment.end_point)
	
	var _prev = segment.global_transform.origin + segment.global_transform.basis * points[0]
	for pidx in range(1, points.size()):
		var point = segment.global_transform.origin + segment.global_transform.basis * points[pidx]
		var road_height = point.y + offset # Subtract some to avoid z-fighting
		terrain.data.set_height(point, road_height)
		var fwd = (point - _prev).normalized()
		var side = Vector3.UP.cross(fwd)
		var width = start_width / 2 # todo, interpolate betwen start/end widths
		# Start at 1 since we already hit 0
		for i in range(1, width):
			terrain.data.set_height(point + (side*i), road_height)
			terrain.data.set_height(point - (side*i), road_height)
		#print("\t\tFlattening %s:%s offset %s to %s" % [pidx, point, side, road_height])
		_prev = point
	
