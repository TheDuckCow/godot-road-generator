# Road Point Gizmo.
## Created largely while following:
## https://docs.godotengine.org/en/stable/tutorials/plugins/editor/spatial_gizmos.html
extends EditorSpatialGizmoPlugin

var _editor_plugin: EditorPlugin


func get_name():
	return "RoadPoint"


func _init(editor_plugin: EditorPlugin):
	_editor_plugin = editor_plugin
	create_material("main", Color(0,1,0))
	create_handle_material("handles")


func has_gizmo(spatial) -> bool:
	return spatial is RoadPoint


func redraw(gizmo) -> void:
	gizmo.clear()
	var point = gizmo.get_spatial_node() as RoadPoint
	var lines = PoolVector3Array()

	lines.push_back(Vector3(0, 1, 0))
	lines.push_back(Vector3(0, 1, 0))

	var handles = PoolVector3Array()
	handles.push_back(Vector3(0, 0, -point.prior_mag))
	handles.push_back(Vector3(0, 0, point.next_mag))
	gizmo.add_lines(lines, get_material("main", gizmo), false)
	gizmo.add_handles(handles, get_material("handles", gizmo))


func get_handle_name(gizmo: EditorSpatialGizmo, index: int) -> String:
	var point = gizmo.get_spatial_node() as RoadPoint
	if index == 0:
		return "RoadPoint %s backwards handle" % point.name
	else:
		return "RoadPoint %s forward handle" % point.name


func get_handle_value(gizmo: EditorSpatialGizmo, index: int) -> float:
	var point = gizmo.get_spatial_node() as RoadPoint
	if index == 0:
		return point.prior_mag
	else:
		return point.next_mag


# Function called when user drags the roadpoint in/out magnitude handle.
func set_handle(gizmo: EditorSpatialGizmo, index: int, camera: Camera, point: Vector2) -> void:
	var roadpoint = gizmo.get_spatial_node() as RoadPoint
	
	# First, we must map the vector2 point of the current handle to the Z axis
	# of the gizmo in question. First project to the xz plane of the object,
	# and then constrain to the z axis.
	var src = camera.project_ray_origin(point) # Camera initial position.
	var nrm = camera.project_ray_normal(point) # Normal camera is facing
	var basis = roadpoint.global_transform.basis
	var plane := Plane(basis.y, 0)
	var intersect = plane.intersects_ray(src, nrm)
	var new_mag = (intersect - roadpoint.global_transform.origin).length()
	
	if index == 0:
		roadpoint.prior_mag = new_mag
	else:
		roadpoint.next_mag = new_mag
	
	# Then isolate to just the magnitude of the z component.
	redraw(gizmo)


func commit_handle(gizmo: EditorSpatialGizmo, index: int, restore, cancel: bool = false) -> void:
	var point = gizmo.get_spatial_node() as RoadPoint
	var current_value = get_handle_value(gizmo, index)
	
	if (cancel):
		print("Cancel")
	else:
		var undo_redo = _editor_plugin.get_undo_redo()
		# TODO: This doesn't actually work with undo yet.
		undo_redo.create_action("Update RoadPoint handle")
		if index == 0:
			undo_redo.add_do_method(point, "_set_prior_mag", current_value)
			undo_redo.add_undo_method(point, "_set_prior_mag", point.prior_mag) # ? 
		else:
			undo_redo.add_do_method(point, "_set_next_mag", current_value)
			undo_redo.add_undo_method(point, "_set_next_mag", point.next_mag) # ? 
		
		undo_redo.commit_action()
