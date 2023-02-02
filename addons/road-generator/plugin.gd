## Road and Highway generator addon.
tool
extends EditorPlugin

const RoadPointGizmo = preload("res://addons/road-generator/road_point_gizmo.gd")

var road_point_gizmo = RoadPointGizmo.new(self)
var road_point_editor = preload("res://addons/road-generator/ui/road_point_edit.gd").new()
var _edi = get_editor_interface()
var _eds = get_editor_interface().get_selection()
var _last_point: Node
var _last_lane: Node


func _enter_tree():
	add_spatial_gizmo_plugin(road_point_gizmo)
	add_inspector_plugin(road_point_editor)
	road_point_editor.call("set_edi", _edi)
	_eds.connect("selection_changed", self, "_on_selection_changed")
	add_custom_type("RoadPoint", "Spatial", preload("road_point.gd"), preload("road_point.png"))
	add_custom_type("RoadNetwork", "Node", preload("road_network.gd"), preload("road_segment.png"))
	# TODO: Set a different icon for lane segments.
	add_custom_type("LaneSegment", "Curve3d", preload("lane_segment.gd"), preload("road_segment.png"))


func _exit_tree():
	remove_spatial_gizmo_plugin(road_point_gizmo)
	remove_inspector_plugin(road_point_editor)
	remove_custom_type("RoadPoint")
	remove_custom_type("RoadNetwork")


## Render the editor indicators for RoadPoints and LaneSegments if selected.
func _on_selection_changed() -> void:
	# Returns an array of selected nodes
	var selected = _eds.get_selected_nodes()
	if selected.empty():
		return
	# Always pick first node in selection
	var selected_node = selected[0]
	if is_instance_valid(_last_point):
		_last_point.hide_gizmo()
	if _last_lane:
		_last_lane.show_fins(false)

	if selected_node is RoadPoint:
		_last_point = selected_node
		selected_node.show_gizmo()
		selected_node.on_transform()
	elif selected_node is LaneSegment:
		_last_lane = selected_node
		_last_lane.show_fins(true)


func refresh() -> void:
	get_editor_interface().get_inspector().refresh()
