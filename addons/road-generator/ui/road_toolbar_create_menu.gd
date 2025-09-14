@tool
extends MenuButton

signal regenerate_pressed
signal select_container_pressed
signal create_container
signal create_roadpoint
signal create_lane
signal create_lane_agent
signal create_2x2_road
signal export_mesh
signal lock_rotation_x_toggled(locked: bool)
signal lock_rotation_y_toggled(locked: bool)
signal lock_rotation_z_toggled(locked: bool)

# ripple up from children
signal pressed_add_custom_roadcontainer(path)

enum CreateMenu {
	REGENERATE,
	SELECT_CONTAINER,
	CONTAINER,
	POINT,
	LANE,
	LANEAGENT,
	TWO_X_TWO,
	EXPORT_MESH,
	LOCK_ROTATION_X,
	LOCK_ROTATION_Y,
	LOCK_ROTATION_Z,
}

enum MenuMode {
	STANDARD,
	SAVED_SUBSCENE,  # Don't offer to create children
	EDGE_SELECTED,  # Not yet used, could offer intersections/next pieces to add.
}

const ICN_CT = preload("../resources/road_container.png")
const ICN_RP = preload("../resources/road_point.png")
const ICN_LN = preload("../resources/road_lane.png")
const ICN_AG = preload("../resources/road_lane_agent.png")
const RcSubMenu = preload("./rc_submenu.gd")

var menu_mode = MenuMode.STANDARD
var rc_submenu: PopupMenu


func _enter_tree() -> void:
	var pup: Popup = get_popup()

	pup.id_pressed.connect(_create_menu_item_clicked)

	if not is_instance_valid(rc_submenu):
		load_submenu()


func load_submenu() -> void:
	var pup: Popup = get_popup()
	rc_submenu = RcSubMenu.new()
	rc_submenu.pressed_add_custom_roadcontainer.connect(_on_pressed_add_custom_roadcontainer)
	pup.add_child(rc_submenu)


func on_toolbar_show(
	primary_sel: Node, x_rotation_locked: bool, y_rotation_locked: bool, z_rotation_locked: bool
) -> void:
	if primary_sel.has_method("is_subscene") and primary_sel.is_subscene():
		menu_mode = MenuMode.SAVED_SUBSCENE
	else:
		menu_mode = MenuMode.STANDARD

	var pup: PopupMenu = get_popup()

	# this prevents the menu from closing when a check item is clicked
	pup.hide_on_checkable_item_selection = false

	var idx = 0
	pup.clear()

	pup.add_item("Refresh roads", CreateMenu.REGENERATE)
	pup.set_item_tooltip(idx, "Re-generate geometry and resolve warnings")
	idx += 1
	pup.add_item("Select container", CreateMenu.SELECT_CONTAINER)
	pup.set_item_tooltip(idx, "Select this RoadPoint's parent RoadContainer")
	idx += 1

	#if menu_mode == MenuMode.SAVED_SUBSCENE:
	#	# Don't offer to modify subscenes
	#	return

	# Set icon width so that it's scaled for the UI properly
	# Though it would seem like DisplayServer.screen_get_scale() would be good to
	# use, it seems that the icon scale is already correctly handled on mac OSX
	# even when setting a single size on 1x vs 2x monitors, and the function
	# is itself not implemented on windows. Thus, we'll just assign values based
	# on OS, since 32x looks too large on windows.
	var width := 32 if OS.get_name() == "macOS" else 16

	pup.add_separator()
	idx += 1

	pup.add_icon_item(ICN_CT, "RoadContainer", CreateMenu.CONTAINER)
	pup.set_item_icon_max_width(idx, width)
	pup.set_item_tooltip(idx, "Adds a RoadContianer child to RoadManager")
	idx += 1

	pup.add_icon_item(ICN_RP, "RoadPoint", CreateMenu.POINT)
	pup.set_item_icon_max_width(idx, width)
	pup.set_item_tooltip(idx, "Adds a new RoadPoint")
	idx += 1

	pup.add_icon_item(ICN_LN, "RoadLane (AI path)", CreateMenu.LANE)
	pup.set_item_icon_max_width(idx, width)
	pup.set_item_tooltip(idx, "Adds a RoadLane which can be used for AI paths")
	idx += 1

	pup.add_icon_item(ICN_AG, "RoadLaneAgent (AI)", CreateMenu.LANEAGENT)
	pup.set_item_icon_max_width(idx, width)
	pup.set_item_tooltip(idx, "Adds a RoadLaneAgent to follow RoadLane paths")
	idx += 1

	pup.add_separator()
	idx += 1

	pup.add_item("2x2 road", CreateMenu.TWO_X_TWO)
	pup.set_item_tooltip(idx, "Adds a segment of road with 2 lanes each way")
	idx += 1

	# rc_items must be name of the child of this menu
	if not is_instance_valid(rc_submenu):
		load_submenu()

	rc_submenu.name = "rc_items"
	pup.add_submenu_item("RoadContainer presets", "rc_items", idx)
	idx += 1

	pup.add_separator("Lock new node rotation?")
	idx += 1

	pup.add_check_item("Lock X", CreateMenu.LOCK_ROTATION_X)
	pup.set_item_checked(idx, x_rotation_locked)
	idx += 1

	pup.add_check_item("Lock Y", CreateMenu.LOCK_ROTATION_Y2)
	pup.set_item_checked(idx, y_rotation_locked)
	idx += 1

	pup.add_check_item("Lock Z", CreateMenu.LOCK_ROTATION_Z)
	pup.set_item_checked(idx, z_rotation_locked)
	idx += 1

	pup.add_separator()
	idx += 1

	pup.add_item("Export RoadContainer", CreateMenu.EXPORT_MESH)
	if not primary_sel is RoadContainer:
		pup.set_item_disabled(idx, true)


func _exit_tree() -> void:
	get_popup().id_pressed.disconnect(_create_menu_item_clicked)


func _create_menu_item_clicked(id: int) -> void:
	match id:
		CreateMenu.REGENERATE:
			regenerate_pressed.emit()
		CreateMenu.SELECT_CONTAINER:
			select_container_pressed.emit()
		CreateMenu.CONTAINER:
			create_container.emit()
		CreateMenu.POINT:
			create_roadpoint.emit()
		CreateMenu.LANE:
			create_lane.emit()
		CreateMenu.LANEAGENT:
			create_lane_agent.emit()
		CreateMenu.TWO_X_TWO:
			create_2x2_road.emit()
		CreateMenu.EXPORT_MESH:
			export_mesh.emit()
		CreateMenu.LOCK_ROTATION_X:
			var new_checked = _toggle_check_item(id)
			lock_rotation_x_toggled.emit(new_checked)
		CreateMenu.LOCK_ROTATION_Y:
			var new_checked = _toggle_check_item(id)
			lock_rotation_y_toggled.emit(new_checked)
		CreateMenu.LOCK_ROTATION_Z:
			var new_checked = _toggle_check_item(id)
			lock_rotation_z_toggled.emit(new_checked)


## Toggle the given check item and return its new state
func _toggle_check_item(id: int) -> bool:
	var pup: PopupMenu = get_popup()
	var index = pup.get_item_index(id)
	var new_checked = not pup.is_item_checked(index)
	pup.set_item_checked(index, new_checked)
	return new_checked


func _on_pressed_add_custom_roadcontainer(path: String) -> void:
	pressed_add_custom_roadcontainer.emit(path)
