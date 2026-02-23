extends Control

const PLUGIN_CFG := "res://addons/road-generator/plugin.cfg"

@export_file("*.tscn") var demo_scenes:Array[String]

@onready var vbox := %vbox
@onready var version := %version_label
@onready var quit_btn := %quit

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if OS.get_name() == "Web":
		quit_btn.queue_free()

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
		vbox.move_child(btn, -3)
		if not focussed:
			btn.grab_focus()
			focussed = true


func load_scene(path:String) -> void:
	var error = get_tree().change_scene_to_file(path)
	if error != OK:
		print("Failed to change scene: ", error)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_wiki_pressed() -> void:
	const WIKI_URL := "https://github.com/TheDuckCow/godot-road-generator/wiki"
	OS.shell_open(WIKI_URL)


func _on_bug_report_pressed() -> void:
	const BUG_REPORT_URL := "https://github.com/TheDuckCow/godot-road-generator/issues"
	OS.shell_open(BUG_REPORT_URL)


func _on_feedback_survey_pressed() -> void:
	const FORM_BASE_URL := "https://docs.google.com/forms/d/e/1FAIpQLSdNbtXvw0FYQGEKpnqhpJZyujxFsabTk4i3SHPXYA6UGRdG9w/viewform"
	OS.shell_open(FORM_BASE_URL)


func _on_patreon_pressed() -> void:
	const PATREON_URL := "https://www.patreon.com/c/wheelstealgame/collections"
	OS.shell_open(PATREON_URL)
