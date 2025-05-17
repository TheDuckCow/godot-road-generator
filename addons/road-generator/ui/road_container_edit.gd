extends EditorInspectorPlugin

const RoadContainerPanel = preload("res://addons/road-generator/ui/road_container_panel.tscn")
var panel_instance
var _editor_plugin: EditorPlugin
# EditorInterface, don't use as type:
# https://github.com/godotengine/godot/issues/85079
var _edi : set = set_edi


func _init(editor_plugin: EditorPlugin):
	_editor_plugin = editor_plugin


func _can_handle(object):
	return object is RoadContainer


# Add controls to the beginning of the Inspector property list
func _parse_category(object: Object, category: String) -> void:
	if category != "road_container.gd":
		return
	panel_instance = RoadContainerPanel.instantiate()
	panel_instance.call("set_edi", _edi)
	add_custom_control(panel_instance)
	panel_instance.export_gltf.connect(_editor_plugin._export_mesh_modal)


func set_edi(value):
	_edi = value
