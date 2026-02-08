extends Control

const MAIN_SCENE := "res://road_demos/demo_menu.tscn"

@onready var back: Button = %Back

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action("ui_cancel") and event.is_released():
		var focus_owner = get_viewport().gui_get_focus_owner()
		get_viewport().set_input_as_handled()
		if focus_owner == back:
			_on_back_pressed()
		else:
			back.grab_focus()


func _on_back_pressed() -> void:
	var error = get_tree().change_scene_to_file(MAIN_SCENE)
	if error != OK:
		print("Failed to change scene: ", error)


func _on_reload_pressed() -> void:
	get_tree().reload_current_scene()
