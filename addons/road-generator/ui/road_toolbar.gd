@tool
extends HBoxContainer

signal mode_changed

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

var selected_nodes: Array # of Nodes
var gui # For fetching built in icons (not yet working)
var mode # Passed in by parent


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


func on_show(_selected_nodes: Array):
	selected_nodes = _selected_nodes

	var primary_sel = null
	var is_subscene := false
	if len(selected_nodes) > 0:
		primary_sel = selected_nodes[0]
	create_menu.on_toolbar_show(primary_sel)


func update_icons():
	update_refs()
	var theme = EditorInterface.get_editor_theme()
	var icn_curve_edit = theme.get_icon("CurveEdit", "EditorIcons")  # File icon_curve_edit.svg
	var icn_curve_create = theme.get_icon("CurveCreate", "EditorIcons")  # File icon_curve_create.svg
	var icn_curve_delete = theme.get_icon("CurveDelete", "EditorIcons")  # File icon_curve_close.svg

	select_mode.icon = icn_curve_edit
	add_mode.icon = icn_curve_create
	delete_mode.icon = icn_curve_delete


func _on_select_mode_pressed():
	select_mode.button_pressed = true
	add_mode.button_pressed = false
	delete_mode.button_pressed = false
	mode = InputMode.SELECT
	emit_signal("mode_changed", mode)


func _on_add_mode_pressed():
	select_mode.button_pressed = false
	add_mode.button_pressed = true
	delete_mode.button_pressed = false
	mode = InputMode.ADD
	emit_signal("mode_changed", mode)


func _on_delete_mode_pressed():
	select_mode.button_pressed = false
	add_mode.button_pressed = false
	delete_mode.button_pressed = true
	mode = InputMode.DELETE
	emit_signal("mode_changed", mode)
