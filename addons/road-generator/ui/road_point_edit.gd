extends EditorInspectorPlugin

const RoadPointPanel = preload("res://addons/road-generator/ui/road_point_panel.tscn")
var panel_instance


func can_handle(object):
	# Only road points are supported.
	return object is RoadPoint


# Add controls to the beginning of the Inspector property list
#func parse_begin(object):
#	panel_instance = RoadPointPanel.instance()
#	add_custom_control(panel_instance)


# Add controls to the end of the Inspector property list
#func parse_end():
#	panel_instance = RoadPointPanel.instance()
#	add_custom_control(panel_instance)


# Add controls to the beginning of an Inspector category
func parse_category(object, category):
	#print("obj %s, cat %s" % [object, category])
	if category == "Spatial":
		panel_instance = RoadPointPanel.instance()
		add_custom_control(panel_instance)
		panel_instance.call_deferred("update_selected_road_point", object)


# Add controls to a specific property in the Inspector
#func parse_property(object, type, path, hint, hint_text, usage):
#	print(path, usage)
#	if path == "translation": # Place directly after the obj-scale transform
#		panel_instance = RoadPointPanel.instance()
#		add_custom_control(panel_instance)
#
#	# Bool return value determines if default property editor is replaced.
#	return false
