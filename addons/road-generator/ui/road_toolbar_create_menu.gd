@tool
extends MenuButton

const ICN_CT = preload("../resources/road_container.png")
const ICN_RP = preload("../resources/road_point.png")
const ICN_LN = preload("../resources/road_lane.png")
const ICN_AG = preload("../resources/road_lane_agent.png")


signal regenerate_pressed
signal select_container_pressed
signal create_container
signal create_roadpoint
signal create_lane
signal create_lane_agent
signal create_2x2_road


enum CreateMenu {
	REGENERATE,
	SELECT_CONTAINER,
	CONTAINER,
	POINT,
	LANE,
	LANEAGENT,
	TWO_X_TWO,
}

enum MenuMode {
	STANDARD,
	SAVED_SUBSCENE, # Don't offer to create children
	EDGE_SELECTED, # Not yet used, could offer intersections/next pieces to add.
}

var menu_mode = MenuMode.STANDARD


func _enter_tree() -> void:
	var pup:Popup = get_popup()
	pup.connect("id_pressed", Callable(self, "_create_menu_item_clicked"))


func on_toolbar_show(primary_sel: Node) -> void:
	if primary_sel.has_method("is_subscene") and primary_sel.is_subscene():
		menu_mode = MenuMode.SAVED_SUBSCENE
	else:
		menu_mode = MenuMode.STANDARD

	var pup:Popup = get_popup()
	var idx = 0
	pup.clear()

	pup.add_item("Refresh roads", CreateMenu.REGENERATE)
	pup.set_item_tooltip(idx, "Re-generate geometry and resolve warnings")
	idx += 1
	pup.add_item("Select container", CreateMenu.SELECT_CONTAINER)
	pup.set_item_tooltip(idx, "Select this RoadPoint's parent RoadContainer")
	idx += 1

	if menu_mode == MenuMode.SAVED_SUBSCENE:
		# Don't offer to modify subscenes
		return

	pup.add_separator()
	idx += 1
	pup.add_icon_item(ICN_CT, "RoadContainer", CreateMenu.CONTAINER)
	pup.set_item_tooltip(idx, "Adds a RoadContianer child to RoadManager")
	idx += 1
	pup.add_icon_item(ICN_RP, "RoadPoint", CreateMenu.POINT)
	pup.set_item_tooltip(idx, "Adds a new RoadPoint")
	idx += 1
	pup.add_icon_item(ICN_LN, "RoadLane (AI path)", CreateMenu.LANE)
	pup.set_item_tooltip(idx, "Adds a RoadLane which can be used for AI paths")
	idx += 1
	pup.add_icon_item(ICN_AG, "RoadLaneAgent (AI)", CreateMenu.LANEAGENT)
	pup.set_item_tooltip(idx, "Adds a RoadLaneAgent to follow RoadLane paths")
	idx += 1
	pup.add_separator()
	idx += 1
	pup.add_item("2x2 road", CreateMenu.TWO_X_TWO)
	pup.set_item_tooltip(idx, "Adds a segment of road with 2 lanes each way")
	idx += 1


func _exit_tree() -> void:
	get_popup().disconnect("id_pressed", Callable(self, "_create_menu_item_clicked"))


func _create_menu_item_clicked(id: int) -> void:
	match id:
		CreateMenu.REGENERATE:
			emit_signal("regenerate_pressed")
		CreateMenu.SELECT_CONTAINER:
			emit_signal("select_container_pressed")
		CreateMenu.CONTAINER:
			emit_signal("create_container")
		CreateMenu.POINT:
			emit_signal("create_roadpoint")
		CreateMenu.LANE:
			emit_signal("create_lane")
		CreateMenu.LANEAGENT:
			emit_signal("create_lane_agent")
		CreateMenu.TWO_X_TWO:
			emit_signal("create_2x2_road")
