# Road Point Gizmo.
## Created largely while following:
## https://docs.godotengine.org/en/stable/tutorials/plugins/editor/spatial_gizmos.html
extends EditorNode3DGizmoPlugin


const GizmoBlueHandle := preload("res://addons/road-generator/ui/gizmo_blue_handle.png")

var _editor_plugin: EditorPlugin
var _editor_selection  # Of type: EditorSelection, but can't type due to exports.
# Either value, or null if not mid action (magnitude handle mid action).
var collider := CylinderMesh.new()
var collider_tri_mesh: TriangleMesh
var intersection_widget := Node3D.new()
var widget_mat := StandardMaterial3D.new()

var prior_lane_width_avg: float = -1


func get_name() -> String:
	return "RoadIntersection"


func _get_gizmo_name() -> String:
	return get_name()


func _init(editor_plugin: EditorPlugin):
	_editor_plugin = editor_plugin
	_editor_selection = editor_plugin.get_editor_interface().get_selection()
	create_material("main", Color(0,1,0))
	create_material("collider", Color8(0, 178, 217, 255))
	create_handle_material("handles")
	create_handle_material("blue_handles")
	var mat_blue_handles = get_material("blue_handles")
	mat_blue_handles.albedo_texture = GizmoBlueHandle
	collider.bottom_radius = RoadPoint.DEFAULT_LANE_WIDTH / 2.0
	collider.top_radius = RoadPoint.DEFAULT_LANE_WIDTH  / 2.0
	collider.height = RoadPoint.DEFAULT_LANE_WIDTH / 20.0
	collider_tri_mesh = collider.generate_triangle_mesh()
	setup_intersection_widgets()


func setup_intersection_widgets():
	# Setup material
	widget_mat.albedo_color = Color8(64, 221, 255, 255)
	widget_mat.flags_unshaded = true
	widget_mat.flags_do_not_receive_shadows = true

	intersection_widget.visible = false
	_editor_plugin.add_child(intersection_widget)


func _has_gizmo(spatial) -> bool:
	return spatial is RoadIntersection


func _redraw(gizmo) -> void:
	gizmo.clear()
	var intersection = gizmo.get_node_3d() as RoadIntersection

	var lines = PackedVector3Array()
	lines.push_back(Vector3.UP)
	lines.push_back(Vector3.UP)
	gizmo.add_lines(lines, get_material("main", gizmo), false)

	gizmo.add_collision_triangles(collider_tri_mesh)
	gizmo.add_mesh(collider, get_material("collider", gizmo))
	
	# Re-process the handler
	var _new_avg_width = get_avg_lane_width(intersection)
	var need_size_update = prior_lane_width_avg < 0 or prior_lane_width_avg != _new_avg_width
	prior_lane_width_avg = _new_avg_width

	if need_size_update:
		collider.bottom_radius = prior_lane_width_avg / 2.0  # resulting
		collider.top_radius = prior_lane_width_avg / 2.0
		collider.height = prior_lane_width_avg / 20.0
	
	intersection_widget.visible = true
	intersection_widget.transform = intersection.global_transform


## Sets width handles to outside lane edges, hides lane widget, and redraws.
func refresh_gizmo(gizmo: EditorNode3DGizmo):
	#var intersection = gizmo.get_node_3d()
	intersection_widget.visible = false
	_redraw(gizmo)


func set_visible():
	intersection_widget.visible = true


func set_hidden():
	intersection_widget.visible = false


func get_avg_lane_width(intersection: RoadIntersection) -> float:
	var count:int = 0
	var sum:float = 0
	for _pt in intersection.edge_points:
		if not is_instance_valid(_pt):
			continue
		count += 1
		sum += _pt.lane_width
	return sum / count if count > 0 else -1.0
