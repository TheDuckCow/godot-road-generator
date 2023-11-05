tool
extends HBoxContainer

const ToolbarMenu = preload("res://addons/road-generator/ui/road_toolbar_create_menu.gd")

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
			select_mode.pressed = true
		InputMode.ADD:
			add_mode.pressed = true
		InputMode.DELETE:
			delete_mode.pressed = true


func update_refs():
	select_mode = $select_mode
	add_mode = $add_mode
	delete_mode = $delete_mode
	create_menu = $CreateMenu


func on_show(_selected_nodes: Array):
	selected_nodes = _selected_nodes
	print("On show:", selected_nodes)

	var primary_sel = null
	var is_subscene := false
	if len(selected_nodes) > 0:
		primary_sel = selected_nodes[0]
		if primary_sel.has_method("is_subscene"):
			is_subscene = primary_sel.is_subscene()
	create_menu.on_toolbar_show()
	if is_subscene:
		create_menu.menu_mode = create_menu.MenuMode.SAVED_SUBSCENE
	else:
		create_menu.menu_mode = create_menu.MenuMode.STANADARD


func update_icons():
	update_refs()
	var icn_curve_edit = gui.get_icon("CurveEdit", "EditorIcons")  # File icon_curve_edit.svg
	var icn_curve_create = gui.get_icon("CurveCreate", "EditorIcons")  # File icon_curve_create.svg
	var icn_curve_delete = gui.get_icon("CurveDelete", "EditorIcons")  # File icon_curve_close.svg

	select_mode.icon = icn_curve_edit
	add_mode.icon = icn_curve_create
	delete_mode.icon = icn_curve_delete


func _on_select_mode_pressed():
	select_mode.pressed = true
	add_mode.pressed = false
	delete_mode.pressed = false
	mode = InputMode.SELECT
	emit_signal("mode_changed", mode)


func _on_add_mode_pressed():
	select_mode.pressed = false
	add_mode.pressed = true
	delete_mode.pressed = false
	mode = InputMode.ADD
	emit_signal("mode_changed", mode)


func _on_delete_mode_pressed():
	select_mode.pressed = false
	add_mode.pressed = false
	delete_mode.pressed = true
	mode = InputMode.DELETE
	emit_signal("mode_changed", mode)
