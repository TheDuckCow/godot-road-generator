# Road Point Gizmo.
## Created largely while following:
## https://docs.godotengine.org/en/stable/tutorials/plugins/editor/spatial_gizmos.html
extends EditorSpatialGizmoPlugin

var _editor_plugin: EditorPlugin

# Either value, or null if not mid action (magnitude handle mid action).
var init_handle
var fwd_width_mag
var rev_width_mag

func get_name():
	return "RoadPoint"


func _init(editor_plugin: EditorPlugin):
	_editor_plugin = editor_plugin
	create_material("main", Color(0,1,0))
	create_handle_material("handles")
	init_handle = null
	fwd_width_mag = null
	rev_width_mag = null


func has_gizmo(spatial) -> bool:
	print("has_gizmo")
	return spatial is RoadPoint


func redraw(gizmo) -> void:
#	print(Time.get_ticks_msec(), " redraw")
	gizmo.clear()
	var point = gizmo.get_spatial_node() as RoadPoint
	
	var lines = PoolVector3Array()
	lines.push_back(Vector3(0, 1, 0))
	lines.push_back(Vector3(0, 1, 0))

	var handles = PoolVector3Array()
	handles.push_back(Vector3(0, 0, -point.prior_mag))
	handles.push_back(Vector3(0, 0, point.next_mag))
	if not fwd_width_mag:
		fwd_width_mag = get_handle_value(gizmo, 2)
	if not rev_width_mag:
		rev_width_mag = get_handle_value(gizmo, 3)
	handles.push_back(Vector3(fwd_width_mag, 0, 0))
	handles.push_back(Vector3(rev_width_mag, 0, 0))
	
	gizmo.add_lines(lines, get_material("main", gizmo), false)
	gizmo.add_handles(handles, get_material("handles", gizmo))


func get_handle_name(gizmo: EditorSpatialGizmo, index: int) -> String:
	var point = gizmo.get_spatial_node() as RoadPoint
	match index:
		0:
			return "RoadPoint %s backwards handle" % point.name
		1:
			return "RoadPoint %s forward handle" % point.name
		2:
			return "RoadPoint %s left handle" % point.name
		3:
			return "RoadPoint %s right handle" % point.name
		_:
			return "RoadPoint %s unknown handle" % point.name


func get_handle_value(gizmo: EditorSpatialGizmo, index: int) -> float:
#	print("get_handle_value")
	var point = gizmo.get_spatial_node() as RoadPoint
	var lane_width = point.lane_width
	var lane_count = len(point.traffic_dir)
	var lane_mag: float = lane_count * lane_width / 2

	match index:
		0:
			return point.prior_mag
		1:
			return point.next_mag
		2:
			return lane_mag + (lane_width * 0.25)
		3:
			return -lane_mag - (lane_width * 0.25)
		_:
			push_warning("RoadPoint %s unknown handle" % point.name)
			return 0.0


## Function called when user drags the roadpoint handles.
func set_handle(gizmo: EditorSpatialGizmo, index: int, camera: Camera, point: Vector2) -> void:
	match index:
		0, 1:
			set_mag_handle(gizmo, index, camera, point)
		2, 3:
			set_width_handle(gizmo, index, camera, point)

## Function called when user drags the roadpoint in/out magnitude handle.
func set_mag_handle(gizmo: EditorSpatialGizmo, index: int, camera: Camera, point: Vector2) -> void:
	
	# Calculate intersection between screen point clicked and a plane aligned to
	# the handle's vector. Then, calculate new handle magnitude.
	var roadpoint = gizmo.get_spatial_node() as RoadPoint
	var old_mag_vector # Handle's old local position.
	if index == 0:
		old_mag_vector = Vector3(0, 0, -roadpoint.prior_mag)
	else:
		old_mag_vector = Vector3(0, 0, roadpoint.next_mag)
	var intersect = _intersect_2D_point_with_3D_plane(roadpoint, old_mag_vector, camera, point)
	
	# Then isolate to just the magnitude of the z component.
	var new_mag = roadpoint.to_local(intersect).z
	
	#Stop the handle at 0 if the cursor crosses over the road point
	if (new_mag < 0 and index == 1) or (new_mag > 0 and index == 0):
		new_mag = 0
		
	if init_handle == null:
		init_handle = new_mag
	if index == 0:
		roadpoint.prior_mag = -new_mag
	else:
		roadpoint.next_mag = new_mag
	redraw(gizmo)

## Function called when user drags the roadpoint left/right magnitude handle.
func set_width_handle(gizmo: EditorSpatialGizmo, index: int, camera: Camera, point: Vector2) -> void:
	print(Time.get_ticks_msec(), " set_width_handle")

	# Calculate intersection between screen point clicked and a plane aligned to
	# the handle's vector. Then, calculate new handle magnitude.
	var roadpoint = gizmo.get_spatial_node() as RoadPoint
	var old_mag_vector # Handle's old local position.
	if index == 2:
		old_mag_vector = Vector3(0, 0, get_handle_value(gizmo, 2))
	else:
		old_mag_vector = Vector3(0, 0, -get_handle_value(gizmo, 3))
	var intersect = _intersect_2D_point_with_3D_plane(roadpoint, old_mag_vector, camera, point)
	
	# Then isolate to just the magnitude of the x component.
	var new_mag = roadpoint.to_local(intersect).x
	
#	#Stop the handle at 0 if the cursor crosses over the road point
#	if (new_mag < 0 and index == 1) or (new_mag > 0 and index == 0):
#		new_mag = 0

		
#	if init_handle == null:
#		init_handle = new_mag
	
	# Total lane_width = fwd + rev
	# Get difference between old and new values
	var old_fwd_mag = fwd_width_mag
	var old_rev_mag = rev_width_mag
	var old_mag_sum = old_fwd_mag + old_rev_mag
	# Round difference to nearest multiple of lane_width
	match index:
		2:
			fwd_width_mag = new_mag
		3:
			rev_width_mag = new_mag
	var new_mag_sum = fwd_width_mag + rev_width_mag
	var mag_change = new_mag_sum - old_mag_sum
	# Todo: Update the lane count
	redraw(gizmo)



func commit_handle(gizmo: EditorSpatialGizmo, index: int, restore, cancel: bool = false) -> void:
	
	match index:
		0, 1:
			commit_mag_handle(gizmo, index, restore, cancel)
		2, 3:
			commit_width_handle(gizmo, index, restore, cancel)
		_:
			push_warning("Unknown gizmo handle %s, %s" % [index, gizmo])


func commit_mag_handle(gizmo: EditorSpatialGizmo, index: int, restore, cancel: bool = false) -> void:
	var point = gizmo.get_spatial_node() as RoadPoint
	var current_value = get_handle_value(gizmo, index)
	
	if (cancel):
		print("Cancel")
	else:
		if init_handle == null:
			init_handle = current_value
		
		var undo_redo = _editor_plugin.get_undo_redo()
		
		if index == 0:
			undo_redo.create_action("RoadPoint %s in handle" % point.name)
			undo_redo.add_do_property(point, "prior_mag", current_value)
			undo_redo.add_undo_property(point, "prior_mag", init_handle)
			print("This commit ", current_value, "-", init_handle)
		elif index == 1:

			undo_redo.create_action("RoadPoint %s out handle" % point.name)
			undo_redo.add_do_property(point, "next_mag", current_value)
			undo_redo.add_undo_property(point, "next_mag", init_handle)

		# Either way, force gizmo redraw with do/undo (otherwise waits till hover)
		undo_redo.add_do_method(self, "redraw", gizmo)
		undo_redo.add_undo_method(self, "redraw", gizmo)
		
		undo_redo.commit_action()
		point._notification(Spatial.NOTIFICATION_TRANSFORM_CHANGED)
		init_handle = null


func commit_width_handle(gizmo: EditorSpatialGizmo, index: int, restore, cancel: bool = false) -> void:
	print("commit_rp_width_handle")
	var point = gizmo.get_spatial_node() as RoadPoint
	var current_value = get_handle_value(gizmo, index)
	
	# Update the lanes on the RoadPoint if lane_count changed
	
	if (cancel):
		print("Cancel")
	else:
#		pass
#		if init_handle == null:
#			init_handle = current_value
		
		var undo_redo = _editor_plugin.get_undo_redo()
		
#		if index == 0:
#			undo_redo.create_action("RoadPoint %s in handle" % point.name)
#			undo_redo.add_do_property(point, "prior_mag", current_value)
#			undo_redo.add_undo_property(point, "prior_mag", init_handle)
#			print("This commit ", current_value, "-", init_handle)
#		elif index == 1:
#
#			undo_redo.create_action("RoadPoint %s out handle" % point.name)
#			undo_redo.add_do_property(point, "next_mag", current_value)
#			undo_redo.add_undo_property(point, "next_mag", init_handle)
#
#		# Either way, force gizmo redraw with do/undo (otherwise waits till hover)
#		undo_redo.add_do_method(self, "redraw", gizmo)
#		undo_redo.add_undo_method(self, "redraw", gizmo)
#
#		undo_redo.commit_action()
#		point._notification(Spatial.NOTIFICATION_TRANSFORM_CHANGED)
#	init_handle = null
	# Get closest lane position, snap handle to it, and update lanes
	# Start by printing handle value
	# Total lane_width = fwd + rev
	# Get difference between old and new values
	var new_fwd_mag = fwd_width_mag
	var new_rev_mag = rev_width_mag
	fwd_width_mag = get_handle_value(gizmo, 2)
	rev_width_mag = get_handle_value(gizmo, 3)
	var old_mag_sum = fwd_width_mag + rev_width_mag
	var new_mag_sum = new_fwd_mag + new_rev_mag
	var mag_change = new_mag_sum - old_mag_sum
	var lane_width = point.lane_width
	var lane_change = mag_change / lane_width
	
	match index:
		2:
			point.update_traffic_dir(RoadPoint.TrafficUpdate.ADD_FORWARD)
		3:
			point.update_traffic_dir(RoadPoint.TrafficUpdate.ADD_REVERSE)
	
	
	print("rev_pos %s, fwd_pos %s, mag_chg %s, lane_chg %s" % [rev_width_mag, fwd_width_mag, mag_change, round(lane_change)])
	
#	print("rev %s, fwd %s" % [rev_width_mag, fwd_width_mag])
	redraw(gizmo)


func _intersect_2D_point_with_3D_plane(spatial, target, camera, screen_point) -> Vector3:
	# Calculate intersection between screen point clicked and a plane aligned to
	# a target's position.
	var src = camera.project_ray_origin(screen_point) # Camera initial position.
	var nrm = camera.project_ray_normal(screen_point) # Normal camera is facing
	var plane_pos : Vector3 = spatial.to_global(target)
	var camera_basis: Basis = camera.get_transform().basis
	var plane := Plane(plane_pos, plane_pos + camera_basis.x, plane_pos + camera_basis.y)
	var intersect = plane.intersects_ray(src, nrm)
	return intersect


func refresh_gizmo(gizmo: EditorSpatialGizmo):
	fwd_width_mag = null
	rev_width_mag = null
	redraw(gizmo)
