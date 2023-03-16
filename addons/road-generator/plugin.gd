## Road and Highway generator addon.
tool
extends EditorPlugin

const RoadPointGizmo = preload("res://addons/road-generator/road_point_gizmo.gd")

var road_point_gizmo = RoadPointGizmo.new(self)
var road_point_editor = preload("res://addons/road-generator/ui/road_point_edit.gd").new()
var _road_toolbar = preload("res://addons/road-generator/ui/road_toolbar.tscn").instance()
var _edi = get_editor_interface()
var _eds = get_editor_interface().get_selection()
var _last_point: Node
var _last_lane: Node


func _enter_tree():
	add_spatial_gizmo_plugin(road_point_gizmo)
	add_inspector_plugin(road_point_editor)
	road_point_editor.call("set_edi", _edi)
	_eds.connect("selection_changed", self, "_on_selection_changed")
	_eds.connect("selection_changed", road_point_gizmo, "on_selection_changed")
	connect("scene_changed", self, "_on_scene_changed")
	connect("scene_closed", self, "_on_scene_closed")
	add_custom_type("RoadPoint", "Spatial", preload("road_point.gd"), preload("road_point.png"))
	add_custom_type("RoadNetwork", "Spatial", preload("road_network.gd"), preload("road_segment.png"))
	# TODO: Set a different icon for lane segments.
	add_custom_type("LaneSegment", "Curve3d", preload("lane_segment.gd"), preload("road_segment.png"))


func _exit_tree():
	_eds.disconnect("selection_changed", self, "_on_selection_changed")
	_eds.disconnect("selection_changed", road_point_gizmo, "on_selection_changed")
	disconnect("scene_changed", self, "_on_scene_changed")
	disconnect("scene_closed", self, "_on_scene_closed")
	_road_toolbar.queue_free()
	remove_spatial_gizmo_plugin(road_point_gizmo)
	remove_inspector_plugin(road_point_editor)
	remove_custom_type("RoadPoint")
	remove_custom_type("RoadNetwork")


## Render the editor indicators for RoadPoints and LaneSegments if selected.
func _on_selection_changed() -> void:
	var selected_node = get_selected_node(_eds.get_selected_nodes())

	if not selected_node:
		_hide_road_toolbar()
		return

	if _last_lane:
		_last_lane.show_fins(false)

	if selected_node is RoadPoint:
		_last_point = selected_node
		selected_node.on_transform()
	elif selected_node is LaneSegment:
		_last_lane = selected_node
		_last_lane.show_fins(true)

	if selected_node is RoadPoint or selected_node is RoadNetwork:
		_show_road_toolbar()
	else:
		_hide_road_toolbar()


func _on_scene_changed(scene_root: Node) -> void:
	var selected = get_selected_node(_eds.get_selected_nodes())
	if selected and (selected is RoadNetwork or selected is RoadPoint):
		_show_road_toolbar()
	else:
		_hide_road_toolbar()


func _on_scene_closed(_value) -> void:
	_hide_road_toolbar()


func refresh() -> void:
	get_editor_interface().get_inspector().refresh()


func _show_road_toolbar() -> void:
	if not _road_toolbar.get_parent():
		add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _road_toolbar)
		_road_toolbar.create_menu.connect("create_2x2_road", self, "_create_2x2_road")


func _hide_road_toolbar() -> void:
	if _road_toolbar.get_parent():
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _road_toolbar)
		_road_toolbar.create_menu.disconnect("create_2x2_road", self, "_create_2x2_road")


## Adds a 2x2 RoadSegment to the Scene
func _create_2x2_road():
	var selected_node = get_selected_node(_eds.get_selected_nodes())
	var default_name = "RP_001"

	if is_instance_valid(selected_node) and selected_node is RoadNetwork:
		# Add new Segment at default location (World Origin)
		selected_node.setup_road_network()
		var points = selected_node.get_node("points")
		var first_road_point = RoadPoint.new()
		var second_road_point = RoadPoint.new()
		first_road_point.name = first_road_point.increment_name(default_name)
		second_road_point.name = second_road_point.increment_name(default_name)
		points.add_child(first_road_point, true)
		first_road_point.owner = points.owner
		first_road_point.add_road_point(second_road_point, RoadPoint.PointInit.NEXT)


## Returns the primary selection or null if nothing is selected
func get_selected_node(selected_nodes: Array) -> Node:
	# TTD: Update this algorithm to figure out which node is really the
	# primary selection rather than always assuming index 0 is the selection.
	if not selected_nodes.empty():
		return selected_nodes[0]
	else:
		return null
