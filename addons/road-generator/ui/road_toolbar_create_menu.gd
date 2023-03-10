tool
extends MenuButton

signal create_2x2_road

enum CREATE_MENU {
	TWO_X_TWO,
}

func _enter_tree() -> void:
	get_popup().clear()
	get_popup().connect("id_pressed", self, "_create_menu_item_clicked")
	get_popup().add_item("2x2 road")

func _exit_tree() -> void:
	get_popup().disconnect("id_pressed", self, "_create_menu_item_clicked")


func _create_menu_item_clicked(id: int) -> void:
	match id:
		CREATE_MENU.TWO_X_TWO:
			emit_signal("create_2x2_road")
