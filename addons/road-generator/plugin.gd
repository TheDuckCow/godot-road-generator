## Road and Highway generator addon.
tool
extends EditorPlugin

const RoadPointGizmo = preload("res://addons/road-generator/road_point_gizmo.gd")

var road_point_gizmo = RoadPointGizmo.new()
var _eds = get_editor_interface().get_selection()
var _last_point


func _enter_tree():
	add_spatial_gizmo_plugin(road_point_gizmo)
	_eds.connect("selection_changed", self, "_on_selection_changed")


func _exit_tree():
	remove_spatial_gizmo_plugin(road_point_gizmo)


func _on_selection_changed():
	# Returns an array of selected nodes
	var selected = _eds.get_selected_nodes()
	if selected.empty():
		return
	# Always pick first node in selection
	var selected_node = selected[0]
	if _last_point:
		_last_point.hide_gizmo()
	if selected_node is RoadPoint:
		_last_point = selected_node
		selected_node.show_gizmo()
		selected_node.on_transform()
