extends EditorInspectorPlugin

const RoadPointPanel = preload("res://addons/road-generator/ui/road_point_panel.tscn")
var panel_instance
var _editor_plugin: EditorPlugin
# EditorInterface, don't use as type:
# https://github.com/godotengine/godot/issues/85079
var _edi setget set_edi
var copy_ref:RoadPoint  # For use in panel to copy settings


func _init(editor_plugin: EditorPlugin):
	_editor_plugin = editor_plugin

#gd4
#func can_handle(object):
func can_handle(object):
	# Only road points are supported.
	# TODO: Add RoadContainer and RoadManager in future for bulk ops.
	return object is RoadPoint


# Add controls to the beginning of the Inspector property list
#gd4
#func _parse_begin(object):
func parse_begin(object):
	#gd4
	#panel_instance = RoadPointPanel.instantiate()
	panel_instance = RoadPointPanel.instance()
	panel_instance.call("set_edi", _edi)
	panel_instance.call_deferred("update_selected_road_point", object)
	add_custom_control(panel_instance)
	#gd4
	#panel_instance.on_lane_change_pressed.connect(_handle_on_lane_change_pressed)
	#panel_instance.on_add_connected_rp.connect(_handle_add_connected_rp)
	panel_instance.connect("on_lane_change_pressed", self, "_handle_on_lane_change_pressed")
	panel_instance.connect("on_add_connected_rp", self, "_handle_add_connected_rp")
	panel_instance.connect("assign_copy_target", self, "_assign_copy_target")
	panel_instance.connect("apply_settings_target", self, "_apply_settings_target")

	panel_instance.has_copy_ref = true and _editor_plugin.copy_attributes  # hack to bool-ify



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
	_edi.get_selection().call_deferred("add_node", selection)
	var rp = null
	match point_init_type:
		RoadPoint.PointInit.PRIOR:
			rp = selection.get_node(selection.prior_pt_init)
			selection.prior_pt_init = null
		RoadPoint.PointInit.NEXT:
			rp = selection.get_node(selection.next_pt_init)
			selection.next_pt_init = null
	_edi.get_selection().call_deferred("remove_node", rp)
	if is_instance_valid(rp):
		rp.queue_free()


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
