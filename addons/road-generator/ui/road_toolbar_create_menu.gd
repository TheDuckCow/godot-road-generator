tool
extends MenuButton

signal regenerate_pressed
signal select_network_pressed
signal create_2x2_road

enum CreateMenu {
	REGENERATE,
	SELECT_NETWORK,
	TWO_X_TWO,
}

func _enter_tree() -> void:
	get_popup().clear()
	get_popup().connect("id_pressed", self, "_create_menu_item_clicked")

	get_popup().add_item("Refresh roads", CreateMenu.REGENERATE)
	get_popup().add_item("Select network", CreateMenu.SELECT_NETWORK)

	get_popup().add_separator()
	get_popup().add_item("2x2 road", CreateMenu.TWO_X_TWO)

func _exit_tree() -> void:
	get_popup().disconnect("id_pressed", self, "_create_menu_item_clicked")


func _create_menu_item_clicked(id: int) -> void:
	match id:
		CreateMenu.REGENERATE:
			emit_signal("regenerate_pressed")
		CreateMenu.SELECT_NETWORK:
			emit_signal("select_network_pressed")
		CreateMenu.TWO_X_TWO:
			emit_signal("create_2x2_road")
