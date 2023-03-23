extends EditorInspectorPlugin

const RoadPointPanel = preload("res://addons/road-generator/ui/road_point_panel.tscn")
var panel_instance
var _edi :EditorInterface setget set_edi


func can_handle(object):
	# Only road points are supported.
	return object is RoadPoint


# Add controls to the beginning of the Inspector property list
func parse_begin(object):
	panel_instance = RoadPointPanel.instance()
	panel_instance.call("set_edi", _edi)
	panel_instance.call_deferred("update_selected_road_point", object)
	add_custom_control(panel_instance)

func set_edi(value):
	_edi = value
