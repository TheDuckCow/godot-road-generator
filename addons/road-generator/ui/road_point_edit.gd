extends EditorInspectorPlugin

const RoadPointPanel = preload("res://addons/road-generator/ui/road_point_panel.tscn")
var panel_instance
var _editor_plugin: EditorPlugin
var _edi :EditorInterface setget set_edi


func _init(editor_plugin: EditorPlugin):
	_editor_plugin = editor_plugin


func can_handle(object):
	# Only road points are supported.
	return object is RoadPoint


# Add controls to the beginning of the Inspector property list
func parse_begin(object):
	panel_instance = RoadPointPanel.instance()
	panel_instance.call("set_edi", _edi)
	panel_instance.call_deferred("update_selected_road_point", object)
	add_custom_control(panel_instance)
	panel_instance.connect(
		"on_lane_change_pressed", self, "_handle_on_lane_change_pressed")
	panel_instance.connect(
		"on_add_connected_rp", self, "_handle_add_connected_rp")



func set_edi(value):
	_edi = value


## Handles signals from the RoadPoint panel to add or remove lanes.
##
## selected: RoadPoint
## change_type: RoadPoint.TrafficUpdate enum value
func _handle_on_lane_change_pressed(selected, change_type):
	var undo_redo = _editor_plugin.get_undo_redo()
	match change_type:
		RoadPoint.TrafficUpdate.ADD_FORWARD:
			undo_redo.create_action("Add forward lane")
			undo_redo.add_do_method(selected, "update_traffic_dir", change_type)
			undo_redo.add_undo_method(selected, "update_traffic_dir", RoadPoint.TrafficUpdate.REM_FORWARD)
		RoadPoint.TrafficUpdate.ADD_REVERSE:
			undo_redo.create_action("Add reverse lane")
			undo_redo.add_do_method(selected, "update_traffic_dir", change_type)
			undo_redo.add_undo_method(selected, "update_traffic_dir", RoadPoint.TrafficUpdate.REM_REVERSE)
		RoadPoint.TrafficUpdate.REM_FORWARD:
			undo_redo.create_action("Remove forward lane")
			undo_redo.add_do_method(selected, "update_traffic_dir", change_type)
			undo_redo.add_undo_method(selected, "update_traffic_dir", RoadPoint.TrafficUpdate.ADD_FORWARD)
		RoadPoint.TrafficUpdate.REM_REVERSE:
			undo_redo.create_action("Remove reverse lane")
			undo_redo.add_do_method(selected, "update_traffic_dir", change_type)
			undo_redo.add_undo_method(selected, "update_traffic_dir", RoadPoint.TrafficUpdate.ADD_REVERSE)
		_:
			push_error("Invalid change type")
			return

	undo_redo.commit_action()


## Handles the press of "Add next/prior" node from panel, if last/start of road.
##
## selection: The initially selected RoadPoint
## point_init_type: Value from RoadPoint.PointInit enum
func _handle_add_connected_rp(selection, point_init_type):
	var undo_redo = _editor_plugin.get_undo_redo()

	match point_init_type:
		RoadPoint.PointInit.PRIOR:
			undo_redo.create_action("Add prior RoadPoint")
		RoadPoint.PointInit.NEXT:
			undo_redo.create_action("Add next RoadPoint")
		_:
			push_error("Invalid point_init_type value, not of type RoadPoint.PointInit")
			return

	undo_redo.add_do_method(self, "_handle_add_connected_rp_do", selection, point_init_type)
	undo_redo.add_undo_method(self, "_handle_add_connected_rp_undo", selection, point_init_type)
	undo_redo.commit_action()


func _handle_add_connected_rp_do(selection, point_init_type):
	var new_road_point = RoadPoint.new()
	selection.add_road_point(new_road_point, point_init_type)
	match point_init_type:
		RoadPoint.PointInit.PRIOR:
			var prior_pt = selection.get_node(selection.prior_pt_init)
			_edi.get_selection().call_deferred("add_node", prior_pt)
		RoadPoint.PointInit.NEXT:
			var next_pt = selection.get_node(selection.next_pt_init)
			_edi.get_selection().call_deferred("add_node", next_pt)

	_edi.get_selection().call_deferred("remove_node", selection)


func _handle_add_connected_rp_undo(selection, point_init_type):
	# Reselect the initial node
	_edi.get_selection().call_deferred("add_node", selection)
	var rp = selection.get_node(selection.prior_pt_init)
	if is_instance_valid(rp):
		rp.queue_free()
