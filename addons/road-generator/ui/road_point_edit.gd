extends EditorInspectorPlugin

const RoadPointPanel = preload("res://addons/road-generator/ui/road_point_panel.tscn")
var panel_instance
var _editor_plugin: EditorPlugin
# EditorInterface, don't use as type:
# https://github.com/godotengine/godot/issues/85079
var _edi : set = set_edi
var copy_ref:RoadPoint  # For use in panel to copy settings


func _init(editor_plugin: EditorPlugin):
	_editor_plugin = editor_plugin

func _can_handle(object):
	# Only road points are supported.
	# TODO: Add RoadContainer and RoadManager in future for bulk ops.
	return object is RoadPoint


# Add controls to the beginning of the Inspector property list
func _parse_begin(object):
	panel_instance = RoadPointPanel.instantiate()
	panel_instance.call("set_edi", _edi)
	panel_instance.call_deferred("update_selected_road_point", object)
	add_custom_control(panel_instance)
	panel_instance.on_lane_change_pressed.connect(_handle_on_lane_change_pressed)
	panel_instance.on_add_connected_rp.connect(_handle_add_connected_rp)
	panel_instance.assign_copy_target.connect(_assign_copy_target)
	panel_instance.apply_settings_target.connect(_apply_settings_target)

	if is_instance_valid(_editor_plugin): 
		panel_instance.has_copy_ref = true and _editor_plugin.copy_attributes 
	else:
		panel_instance.has_copy_ref = false


func set_edi(value):
	_edi = value


## Handles signals from the RoadPoint panel to add or remove lanes.
##
## selected: RoadPoint
## change_type: RoadPoint.TrafficUpdate enum value
func _handle_on_lane_change_pressed(selected, change_type, bulk:bool):
	var undo_redo = _editor_plugin.get_undo_redo()
	var loop_over := []
	if bulk:
		loop_over = selected.container.get_roadpoints(true) # skip connected edges
	else:
		loop_over = [selected]

	match change_type:
		RoadPoint.TrafficUpdate.ADD_FORWARD:
			undo_redo.create_action("Add forward lane")
			for _rp in loop_over:
				undo_redo.add_do_method(_rp, "update_traffic_dir", change_type)
				undo_redo.add_undo_method(_rp, "update_traffic_dir", RoadPoint.TrafficUpdate.REM_FORWARD)
		RoadPoint.TrafficUpdate.ADD_REVERSE:
			undo_redo.create_action("Add reverse lane")
			for _rp in loop_over:
				undo_redo.add_do_method(_rp, "update_traffic_dir", change_type)
				undo_redo.add_undo_method(_rp, "update_traffic_dir", RoadPoint.TrafficUpdate.REM_REVERSE)
		RoadPoint.TrafficUpdate.REM_FORWARD:
			undo_redo.create_action("Remove forward lane")
			for _rp in loop_over:
				undo_redo.add_do_method(_rp, "update_traffic_dir", change_type)
				undo_redo.add_undo_method(_rp, "update_traffic_dir", RoadPoint.TrafficUpdate.ADD_FORWARD)
		RoadPoint.TrafficUpdate.REM_REVERSE:
			undo_redo.create_action("Remove reverse lane")
			for _rp in loop_over:
				undo_redo.add_do_method(_rp, "update_traffic_dir", change_type)
				undo_redo.add_undo_method(_rp, "update_traffic_dir", RoadPoint.TrafficUpdate.ADD_REVERSE)
		_:
			push_error("Invalid change type")
			return

	undo_redo.commit_action()


## Handles the press of "Add next/prior" node from panel, if last/start of road.
##
## selection: The initially selected RoadPoint
## point_init_type: Value from RoadPoint.PointInit enum
func _handle_add_connected_rp(selection, point_init_type):
	var pos:Vector3 = selection.transform.origin
	match point_init_type:
		RoadPoint.PointInit.NEXT:
			pos += RoadPoint.SEG_DIST_MULT * selection.lane_width * selection.transform.basis.z
		RoadPoint.PointInit.PRIOR:
			pos -= RoadPoint.SEG_DIST_MULT * selection.lane_width * selection.transform.basis.z
	_editor_plugin._add_next_rp_on_click(pos, Vector3.ZERO, selection)


func _assign_copy_target(target) -> void:
	_editor_plugin.copy_attributes = {
		"traffic_dir": target.traffic_dir,
		"auto_lanes": target.auto_lanes,
		"lanes": target.lanes,
		"lane_width": target.lane_width,
		"shoulder_width_l": target.shoulder_width_l,
		"shoulder_width_r": target.shoulder_width_r,
		"gutter_profile": target.gutter_profile,
		"create_geo": target.create_geo
	}

func _apply_settings_target(target, all:bool) -> void:
	var undo_redo = _editor_plugin.get_undo_redo()

	var _pts: Array
	if all:
		undo_redo.create_action("Apply settings to all container RoadPoints")
		_pts = target.container.get_roadpoints(false) # Skip cross connected
	else:
		undo_redo.create_action("Apply settings to RoadPoint")
		_pts = [target]

	for itm in _pts:
		for key in _editor_plugin.copy_attributes.keys():
			undo_redo.add_do_property(itm, key, _editor_plugin.copy_attributes[key])
			undo_redo.add_undo_property(itm, key, itm.get(key))

	# Ensure geometry gets updated
	if all:
		undo_redo.add_do_method(target.container, "rebuild_segments")
		undo_redo.add_undo_method(target.container, "rebuild_segments")
	else:
		undo_redo.add_do_method(target, "emit_transform")
		undo_redo.add_undo_method(target, "emit_transform")
	undo_redo.commit_action()
