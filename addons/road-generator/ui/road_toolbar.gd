@tool
extends HBoxContainer


# ------------------------------------------------------------------------------
#endregion
#region Signals, enums, and vars
# ------------------------------------------------------------------------------


signal mode_changed
signal rotation_lock_toggled(axis_id: int, state: bool)
signal snap_distance_updated(value: float)
signal select_terrain_3d_pressed()

enum InputMode {
	NONE,  # e.g. if a Road*Node is not selected.
	SELECT,
	ADD,
	DELETE,
}

var select_mode:Button
var add_mode:Button
var delete_mode:Button
var create_menu:MenuButton
var settings_menu:Button

# Settings menu references
var snap_distance: SpinBox
var lock_rot_x: CheckBox
var lock_rot_y: CheckBox
var lock_rot_z: CheckBox
var terrain_tut: Button
var get_connector: Callable

# Functional utilities
var selected_nodes: Array # of Nodes
var gui # For fetching built in icons (not yet working)
var mode # Passed in by parent


# ------------------------------------------------------------------------------
#endregion
#region Overrides
# ------------------------------------------------------------------------------


func _enter_tree():
	update_refs()
	match mode:
		InputMode.SELECT:
			select_mode.button_pressed = true
		InputMode.ADD:
			add_mode.button_pressed = true
		InputMode.DELETE:
			delete_mode.button_pressed = true


func update_refs():
	select_mode = $select_mode
	add_mode = $add_mode
	delete_mode = $delete_mode
	create_menu = $CreateMenu
	settings_menu = $SettingsMenu

	snap_distance = %snap_distance
	lock_rot_x = %lock_rot_x
	lock_rot_y = %lock_rot_y
	lock_rot_z = %lock_rot_z
	terrain_tut = %terrain3d_tut
	settings_menu.terrain3d_select = %terrain3d


func on_show(
	_selected_nodes: Array,
	_snapping_distance: float,
	_get_connector: Callable,
	x_rotation_locked: bool,
	y_rotation_locked: bool,
	z_rotation_locked: bool
) -> void:
	selected_nodes = _selected_nodes

	var primary_sel = null
	var is_subscene := false
	if len(selected_nodes) > 0:
		primary_sel = selected_nodes[0]

	snap_distance.value = _snapping_distance
	lock_rot_x.button_pressed = x_rotation_locked
	lock_rot_y.button_pressed = y_rotation_locked
	lock_rot_z.button_pressed = z_rotation_locked
	settings_menu.get_connector = _get_connector
	
	create_menu.on_toolbar_show(primary_sel)


func update_icons():
	update_refs()
	var theme = EditorInterface.get_editor_theme()
	# See: https://godotengine.github.io/editor-icons/
	var icn_curve_edit = theme.get_icon("CurveEdit", "EditorIcons")
	var icn_curve_create = theme.get_icon("CurveCreate", "EditorIcons")
	var icn_curve_delete = theme.get_icon("CurveDelete", "EditorIcons")
	var icn_settings = theme.get_icon("GuiTabMenuHl", "EditorIcons")
	var icn_external_link = theme.get_icon("ExternalLink", "EditorIcons")

	select_mode.icon = icn_curve_edit
	add_mode.icon = icn_curve_create
	delete_mode.icon = icn_curve_delete
	settings_menu.icon = icn_settings
	terrain_tut.icon = icn_external_link


# ------------------------------------------------------------------------------
#endregion
#region Top-level modes
# ------------------------------------------------------------------------------


func _on_select_mode_pressed():
	select_mode.button_pressed = true
	add_mode.button_pressed = false
	delete_mode.button_pressed = false
	mode = InputMode.SELECT
	mode_changed.emit(mode)


func _on_add_mode_pressed():
	select_mode.button_pressed = false
	add_mode.button_pressed = true
	delete_mode.button_pressed = false
	mode = InputMode.ADD
	mode_changed.emit(mode)


func _on_delete_mode_pressed():
	select_mode.button_pressed = false
	add_mode.button_pressed = false
	delete_mode.button_pressed = true
	mode = InputMode.DELETE
	mode_changed.emit(mode)


# ------------------------------------------------------------------------------
#endregion
#region Settings menu
# ------------------------------------------------------------------------------


func _on_snap_distance_changed(value: float) -> void:
	snap_distance_updated.emit(value)


func _on_lock_rot_x_toggled(value: bool) -> void:
	rotation_lock_toggled.emit(0, value)


func _on_lock_rot_y_toggled(value: bool) -> void:
	rotation_lock_toggled.emit(1, value)


func _on_lock_rot_z_toggled(value: bool) -> void:
	rotation_lock_toggled.emit(2, value)


func _on_terrain_3d_tut_pressed() -> void:
	var url := "https://github.com/TheDuckCow/godot-road-generator/wiki/Using-the-Terrain3D-Connector"
	OS.shell_open(url)


func _on_terrain_3d_pressed() -> void:
	settings_menu.popup.hide()
	select_terrain_3d_pressed.emit()


#endregion
# ------------------------------------------------------------------------------
