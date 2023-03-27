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
