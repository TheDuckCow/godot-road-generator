# Road Point Gizmo.
## Created largely while following:
## https://docs.godotengine.org/en/stable/tutorials/plugins/editor/spatial_gizmos.html
extends EditorSpatialGizmoPlugin


func get_name():
	return "RoadPoint"


func _init():
	create_material("main", Color(1,0,0))
	create_handle_material("handles")


func has_gizmo(spatial):
	return spatial is RoadPoint


func redraw(gizmo):
	gizmo.clear()

	var spatial = gizmo.get_spatial_node()

	var lines = PoolVector3Array()

	lines.push_back(Vector3(0, 1, 0))
	lines.push_back(Vector3(0, 1, 0))

	var handles = PoolVector3Array()

	handles.push_back(Vector3(0, 1, 0))
	handles.push_back(Vector3(0, 1, 0))

	gizmo.add_lines(lines, get_material("main", gizmo), false)
	gizmo.add_handles(handles, get_material("handles", gizmo))
