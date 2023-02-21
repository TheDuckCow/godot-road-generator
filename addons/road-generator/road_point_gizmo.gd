# Road Point Gizmo.
## Created largely while following:
## https://docs.godotengine.org/en/stable/tutorials/plugins/editor/spatial_gizmos.html
extends EditorSpatialGizmoPlugin

enum HandleType {
	PRIOR_MAG,
	NEXT_MAG,
	REV_WIDTH_MAG,
	FWD_WIDTH_MAG
}

const GizmoBlueHandle := preload("res://addons/road-generator/gizmo_blue_handle.png")
const LaneOffset := 0.25

var _editor_plugin: EditorPlugin
var _editor_selection: EditorSelection
# Either value, or null if not mid action (magnitude handle mid action).
var init_handle
var collider := CubeMesh.new()
var collider_tri_mesh: TriangleMesh
var lane_widget := Spatial.new()
var lane_widget_mat := SpatialMaterial.new()
var arrow_left := MeshInstance.new()
var arrow_right := MeshInstance.new()
var lane_divider := MeshInstance.new()
var lane_dividers := Spatial.new()
var road_width_line := MeshInstance.new()
var arrow_left_mesh:= PrismMesh.new()
var arrow_right_mesh := PrismMesh.new()
var lane_divider_mesh := CubeMesh.new()
var road_width_line_mesh := CubeMesh.new()


func get_name():
	return "RoadPoint"


func _init(editor_plugin: EditorPlugin):
	_editor_plugin = editor_plugin
	_editor_selection = editor_plugin.get_editor_interface().get_selection()
	create_material("main", Color(0,1,0))
	create_material("collider", Color8(0, 178, 217, 255))
	create_handle_material("handles")
	create_handle_material("blue_handles", false, GizmoBlueHandle)
	init_handle = null
	collider.size = Vector3(2, 0.175, 2)
	collider_tri_mesh = collider.generate_triangle_mesh()
	setup_lane_widgets()


func setup_lane_widgets():
	# Setup material
	lane_widget_mat.albedo_color = Color8(64, 221, 255, 255)
	lane_widget_mat.flags_unshaded = true
	lane_widget_mat.flags_do_not_receive_shadows = true

	# Setup left arrow
	arrow_left_mesh.size = Vector3(2, 0.8, 0.4)
	arrow_left.mesh	= arrow_left_mesh
	arrow_left.rotation_degrees = Vector3(90, 0, 90)
	arrow_left.translation = Vector3(-5, 0, 0)
	arrow_left.material_override = lane_widget_mat
	lane_widget.add_child(arrow_left)

	# Setup right arrow
	arrow_right_mesh.size = Vector3(2, 0.8, 0.4)
	arrow_right.mesh = arrow_right_mesh
	arrow_right.rotation_degrees = Vector3(90, 0, -90)
	arrow_right.translation = Vector3(5, 0, 0)
	arrow_right.material_override = lane_widget_mat
	lane_widget.add_child(arrow_right)
#	lane_widget.translation = Vector3(0, 0.5, 5)

	# Setup road width line
	road_width_line_mesh.size = Vector3(6, 0.2, 0.2)
	road_width_line.mesh = road_width_line_mesh
	road_width_line.material_override = lane_widget_mat
	lane_widget.add_child(road_width_line)

	# Setup lane divider template and node container
	lane_divider_mesh.size = Vector3(0.2, 0.2, 2)
	lane_divider.mesh = lane_divider_mesh
	lane_divider.translation = Vector3(0, 0, 0)
	lane_divider.material_override = lane_widget_mat
	lane_widget.add_child(lane_dividers)

	lane_widget.visible = false
	_editor_plugin.add_child(lane_widget)


func has_gizmo(spatial) -> bool:
	return spatial is RoadPoint


func redraw(gizmo) -> void:
	gizmo.clear()
	var point = gizmo.get_spatial_node() as RoadPoint

	var lines = PoolVector3Array()
	lines.push_back(Vector3(0, 1, 0))
	lines.push_back(Vector3(0, 1, 0))
	gizmo.add_lines(lines, get_material("main", gizmo), false)

	gizmo.add_collision_triangles(collider_tri_mesh)
	gizmo.add_mesh(collider, false, null, get_material("collider", gizmo))
	if point.is_road_point_selected(_editor_selection):

		# Add mag handles
		var handles = PoolVector3Array()
		handles.push_back(Vector3(0, 0, -point.prior_mag))
		handles.push_back(Vector3(0, 0, point.next_mag))
		gizmo.add_handles(handles, get_material("handles", gizmo))

		# Add width handles
		var width_handles = PoolVector3Array()
		var rev_width_idle = get_handle_value(gizmo, HandleType.REV_WIDTH_MAG)
		var fwd_width_idle = get_handle_value(gizmo, HandleType.FWD_WIDTH_MAG)
		var rev_width_mag = point.rev_width_mag
		var fwd_width_mag = point.fwd_width_mag
		width_handles.push_back(Vector3(rev_width_mag, 0, 0))
		width_handles.push_back(Vector3(fwd_width_mag, 0, 0))
		gizmo.add_handles(width_handles, get_material("blue_handles", gizmo))

		# Add lane widget
		lane_widget.visible = true
		lane_widget.transform = point.transform
		arrow_left.translation = Vector3(rev_width_mag, 0, 0)
		arrow_right.translation = Vector3(fwd_width_mag, 0, 0)
		var line_width = fwd_width_mag - rev_width_mag
		var line_pos = (rev_width_mag + fwd_width_mag) / 2
		road_width_line_mesh.size = Vector3(line_width, 0.2, 0.2)
		road_width_line.translation = Vector3(line_pos, 0, 0)

		# Add lane dividers:
		# Start placing dividers at side opposite of dragged handle. Draw
		# dividers for real and potential lanes based on handle position. Re-use
		# existing dividers. Create more dividers when needed. Hide dividers
		# when not needed.
		var lane_width = point.lane_width
		var lane_count
		var div_start_pos
		var lane_width_offset = lane_width * LaneOffset

		if rev_width_mag != rev_width_idle:
			div_start_pos = fwd_width_idle - lane_width_offset
			lane_count = floor(abs((fwd_width_idle - rev_width_mag + lane_width_offset) / lane_width)) + 1
			lane_width = -lane_width
		else:
			div_start_pos = rev_width_idle + lane_width_offset
			lane_count = floor(abs((rev_width_idle - fwd_width_mag - lane_width_offset) / lane_width)) + 1

		var x_pos = div_start_pos
		var div_count = lane_dividers.get_child_count()
		var div: Spatial
		for i in range(max(lane_count, div_count)):
			if div_count == 0 or i >= div_count:
				div = lane_divider.duplicate()
				lane_dividers.add_child(div)
			else:
				div = lane_dividers.get_child(i)

			if i < lane_count:
				div.visible = true
				div.translation = Vector3(x_pos, 0, 0)
				x_pos += lane_width
			else:
				div.visible = false


func get_handle_name(gizmo: EditorSpatialGizmo, index: int) -> String:
	var point = gizmo.get_spatial_node() as RoadPoint
	match index:
		HandleType.PRIOR_MAG:
			return "RoadPoint %s backwards handle" % point.name
		HandleType.NEXT_MAG:
			return "RoadPoint %s forward handle" % point.name
		HandleType.REV_WIDTH_MAG:
			return "RoadPoint %s left handle" % point.name
		HandleType.FWD_WIDTH_MAG:
			return "RoadPoint %s right handle" % point.name
		_:
			return "RoadPoint %s unknown handle" % point.name


func get_handle_value(gizmo: EditorSpatialGizmo, index: int) -> float:
#	print("get_handle_value")
	var point = gizmo.get_spatial_node() as RoadPoint
	var lane_width = point.lane_width
	var lane_count = len(point.traffic_dir)
	var width_mag: float = lane_count * lane_width / 2

	match index:
		HandleType.PRIOR_MAG:
			return point.prior_mag
		HandleType.NEXT_MAG:
			return point.next_mag
		HandleType.REV_WIDTH_MAG:
			return -width_mag - (lane_width * LaneOffset)
		HandleType.FWD_WIDTH_MAG:
			return width_mag + (lane_width * LaneOffset)
		_:
			push_warning("RoadPoint %s unknown handle" % point.name)
			return 0.0


## Function called when user drags the roadpoint handles.
func set_handle(gizmo: EditorSpatialGizmo, index: int, camera: Camera, point: Vector2) -> void:
	match index:
		HandleType.PRIOR_MAG, HandleType.NEXT_MAG:
			#set_mag_handle(gizmo, index, camera, point)
			set_mag_handle(gizmo, index, camera, point)
		HandleType.REV_WIDTH_MAG, HandleType.FWD_WIDTH_MAG:
			set_width_handle(gizmo, index, camera, point)
			#old_set_width_handle(gizmo, index, camera, point)


func set_mag_handle(gizmo: EditorSpatialGizmo, index: int, camera: Camera, point: Vector2) -> void:
	# Calculate intersection between screen point clicked and a plane aligned to
	# the handle's vector. Then, calculate new handle magnitude.
	var roadpoint = gizmo.get_spatial_node() as RoadPoint
	var src = camera.project_ray_origin(point) # Camera initial position.
	var nrm = camera.project_ray_normal(point) # Normal camera is facing
	var old_mag_vector # Handle's old local position.

	if index == 0:
		old_mag_vector = Vector3(0, 0, -roadpoint.prior_mag)
	else:
		old_mag_vector = Vector3(0, 0, roadpoint.next_mag)

	var plane_vector : Vector3 = roadpoint.to_global(old_mag_vector)
	var camera_basis : Basis = camera.get_transform().basis
	var plane := Plane(plane_vector, plane_vector + camera_basis.x, plane_vector + camera_basis.y)
	var intersect = plane.intersects_ray(src, nrm)

	# Then isolate to just the magnitude of the z component.
	var new_mag = roadpoint.to_local(intersect).z

	#Stop the handle at 0 if the cursor crosses over the road point
	if (new_mag < 0 and index > 0) or (new_mag > 0 and index == 0):
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
	# Calculate intersection between screen point clicked and a plane aligned to
	# the handle's vector. Then, calculate new handle magnitude.
	var roadpoint = gizmo.get_spatial_node() as RoadPoint
	if roadpoint.is_road_point_selected(_editor_selection):
		var old_mag_vector # Handle's old local position.
		if index == HandleType.REV_WIDTH_MAG:
			old_mag_vector = Vector3(get_handle_value(gizmo, HandleType.REV_WIDTH_MAG), 0, 0)
		else: # HandleType.FWD_WIDTH_MAG
			old_mag_vector = Vector3(get_handle_value(gizmo, HandleType.FWD_WIDTH_MAG), 0, 0)
		var intersect = _intersect_2D_point_with_3D_plane(roadpoint, old_mag_vector, camera, point)

		# Then isolate to just the magnitude of the x component.
		var new_mag = roadpoint.to_local(intersect).x

		# Prevent handles from crossing over road divider
		var lane_width = roadpoint.lane_width
		var lane_count = len(roadpoint.traffic_dir)
		var half_road_width = lane_count * lane_width / 2
		var rev_lane_width = roadpoint.get_rev_lane_count() * lane_width
		var road_divider = -half_road_width + rev_lane_width
		var road_div_rev_limit = road_divider - (lane_width * LaneOffset)
		var road_div_fwd_limit = road_divider + (lane_width * LaneOffset)
		if index == HandleType.REV_WIDTH_MAG and new_mag > road_div_rev_limit:
			new_mag = road_div_rev_limit
		elif index == HandleType.FWD_WIDTH_MAG and new_mag < road_div_fwd_limit:
			new_mag = road_div_fwd_limit

		# Update handle position
		match index:
			HandleType.REV_WIDTH_MAG:
				roadpoint.rev_width_mag = new_mag
			HandleType.FWD_WIDTH_MAG:
				roadpoint.fwd_width_mag = new_mag
		redraw(gizmo)


func commit_handle(gizmo: EditorSpatialGizmo, index: int, restore, cancel: bool = false) -> void:

	match index:
		HandleType.PRIOR_MAG, HandleType.NEXT_MAG:
			commit_mag_handle(gizmo, index, restore, cancel)
		HandleType.REV_WIDTH_MAG, HandleType.FWD_WIDTH_MAG:
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

		if index == HandleType.PRIOR_MAG:
			undo_redo.create_action("RoadPoint %s in handle" % point.name)
			undo_redo.add_do_property(point, "prior_mag", current_value)
			undo_redo.add_undo_property(point, "prior_mag", init_handle)
			print("This commit ", current_value, "-", init_handle)
		elif index == HandleType.NEXT_MAG:
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
	var point = gizmo.get_spatial_node() as RoadPoint

	if (cancel):
		print("Cancel")
		refresh_gizmo(gizmo)
	else:
		var new_fwd_mag = point.fwd_width_mag
		var new_rev_mag = point.rev_width_mag
		var rev_width_mag = get_handle_value(gizmo, HandleType.REV_WIDTH_MAG)
		var fwd_width_mag = get_handle_value(gizmo, HandleType.FWD_WIDTH_MAG)
		var old_mag_sum = fwd_width_mag + rev_width_mag
		var new_mag_sum = new_fwd_mag + new_rev_mag
		var mag_change = new_mag_sum - old_mag_sum
		var lane_width = point.lane_width
		var lane_width_offset = lane_width * LaneOffset
		var lane_change = round(mag_change / lane_width)

		if index == HandleType.REV_WIDTH_MAG:
			lane_change  = round((mag_change - lane_width_offset) / lane_width)
		else:
			lane_change  = round((mag_change + lane_width_offset) / lane_width)

		if lane_change > 0:
			match index:
				HandleType.REV_WIDTH_MAG:
					for i in range(lane_change):
						point.update_traffic_dir(RoadPoint.TrafficUpdate.REM_REVERSE)
				HandleType.FWD_WIDTH_MAG:
					for i in range(lane_change):
						point.update_traffic_dir(RoadPoint.TrafficUpdate.ADD_FORWARD)
		elif lane_change < 0:
			match index:
				HandleType.REV_WIDTH_MAG:
					for i in range(lane_change, 0):
						point.update_traffic_dir(RoadPoint.TrafficUpdate.ADD_REVERSE)
				HandleType.FWD_WIDTH_MAG:
					for i in range(lane_change, 0):
						point.update_traffic_dir(RoadPoint.TrafficUpdate.REM_FORWARD)

		refresh_gizmo(gizmo)


## Calculate intersection between screen point clicked and a camera-aligned
## plane at a target position.
func _intersect_2D_point_with_3D_plane(spatial, target, camera, screen_point) -> Vector3:
	var src = camera.project_ray_origin(screen_point) # Camera initial position.
	var nrm = camera.project_ray_normal(screen_point) # Normal camera is facing
	var plane_pos : Vector3 = spatial.to_global(target)
	var camera_basis: Basis = camera.get_transform().basis
	var plane := Plane(plane_pos, plane_pos + camera_basis.x, plane_pos + camera_basis.y)
	var intersect = plane.intersects_ray(src, nrm)
	return intersect

## Sets width handles to outside lane edges, hides lane widget, and redraws.
func refresh_gizmo(gizmo: EditorSpatialGizmo):
	var point = gizmo.get_spatial_node()
	point.rev_width_mag = get_handle_value(gizmo, HandleType.REV_WIDTH_MAG)
	point.fwd_width_mag = get_handle_value(gizmo, HandleType.FWD_WIDTH_MAG)
	lane_widget.visible = false
	redraw(gizmo)
