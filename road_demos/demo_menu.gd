extends Control

const PLUGIN_CFG := "res://addons/road-generator/plugin.cfg"

@export_file("*.tscn") var demo_scenes:Array[String]

@onready var vbox := %vbox
@onready var version := %version_label

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var config = ConfigFile.new()
	var res = config.load(PLUGIN_CFG)
	if res == OK:
		var version_value = config.get_value("plugin", "version", null)
		if version_value != null:
			version.text = "v%s" % version_value
		else:
			version.text = ""
	
	var focussed: bool = false
	for scn_path in demo_scenes:
		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.text = scn_path.get_file().get_basename().capitalize()
		
		var on_btn_press = func():
			load_scene(scn_path)
		btn.pressed.connect(on_btn_press)
		vbox.add_child(btn)
		if not focussed:
			btn.grab_focus()
			focussed = true


func load_scene(path:String) -> void:
	var error = get_tree().change_scene_to_file(path)
	if error != OK:
		print("Failed to change scene: ", error)


func _on_quit_pressed() -> void:
	get_tree().quit()
