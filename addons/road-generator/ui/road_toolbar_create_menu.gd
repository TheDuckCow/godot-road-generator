tool
extends MenuButton

const ICN_CT = preload("../resources/road_container.png")
const ICN_RP = preload("../resources/road_point.png")
const ICN_LN = preload("../resources/road_lane.png")

signal regenerate_pressed
signal select_container_pressed
signal create_container
signal create_roadpoint
signal create_lane
signal create_2x2_road


enum CreateMenu {
	REGENERATE,
	SELECT_CONTAINER,
	CONTAINER,
	POINT,
	LANE
	TWO_X_TWO,
}

func _enter_tree() -> void:
	get_popup().clear()
	get_popup().connect("id_pressed", self, "_create_menu_item_clicked")

	get_popup().add_item("Refresh roads", CreateMenu.REGENERATE)
	get_popup().add_item("Select container", CreateMenu.SELECT_CONTAINER)

	get_popup().add_separator()
	get_popup().add_icon_item(ICN_CT, "RoadContainer", CreateMenu.CONTAINER)
	get_popup().add_icon_item(ICN_RP, "RoadPoint", CreateMenu.POINT)
	get_popup().add_icon_item(ICN_LN, "RoadLane (AI path)", CreateMenu.LANE)
	get_popup().add_separator()
	get_popup().add_item("2x2 road", CreateMenu.TWO_X_TWO)


func _exit_tree() -> void:
	get_popup().disconnect("id_pressed", self, "_create_menu_item_clicked")


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
		CreateMenu.TWO_X_TWO:
			emit_signal("create_2x2_road")
