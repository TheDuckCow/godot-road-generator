extends Control

@export_file("*.tscn") var demo_scenes:Array[String]

@onready var vbox := %vbox

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for scn_path in demo_scenes:
		var btn := Button.new()
		
		var on_btn_press = func():
			load_scene(scn_path)
		btn.pressed.connect(on_btn_press)
		btn.text = scn_path.get_file()
		vbox.add_child(btn)


func load_scene(path:String) -> void:
	var error = get_tree().change_scene_to_file(path)
	if error != OK:
		print("Failed to change scene: ", error)
