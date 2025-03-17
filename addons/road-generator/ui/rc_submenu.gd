extends PopupMenu

const DEFAULT_DIR := "res://addons/road-generator/custom_containers/"

signal pressed_add_custom_roadcontainer(path) # String

var directory: String
var dir_selector: FileDialog


func _ready() -> void:
	# TODO: how to load this value from plugin? Or maybe we don't need to,
	# if the value lasts
	directory = DEFAULT_DIR
	reload_items()


func _enter_tree() -> void:
	connect("id_pressed", Callable(self, "_create_menu_item_clicked"))
	dir_selector = FileDialog.new()
	dir_selector.current_dir = directory
	dir_selector.use_native_dialog = false # Does work on OSX if true but too broad access
	dir_selector.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dir_selector.mode_overrides_title = true
	dir_selector.title = "Select folder with RoadContainer TSCN files"
	dir_selector.add_filter("*.tscn ; TSCN files")
	dir_selector.dir_selected.connect(_on_folder_selected)
	EditorInterface.get_base_control().add_child(dir_selector)


func _exit_tree() -> void:
	disconnect("id_pressed", Callable(self, "_create_menu_item_clicked"))
	if is_instance_valid(dir_selector):
		dir_selector.queue_free()


func reload_items() -> void:
	self.clear()
	var idx = 0
	self.add_item("Change folder", idx)
	self.set_item_tooltip(idx, "Pick a another folder containing tscn's with RoadContainer as the root")
	idx += 1
	self.add_item("Reset to default", idx)
	self.set_item_tooltip(idx, "Reset to the default plugin intersection folder")
	idx += 1
	self.add_item("Reload folder", idx)
	self.set_item_tooltip(idx, "Refresh the current directory of tscn's")
	idx += 1

	# TODO: could add "reset" one too

	self.add_separator()
	var contents := dir_contents(directory)
	for _tscn in contents:
		self.add_item(_tscn.get_basename(), idx)
		self.set_item_metadata(idx, _tscn)
		idx += 1


func reset_folder() -> void:
	directory = DEFAULT_DIR
	reload_items()


func _create_menu_item_clicked(id: int) -> void:
	if id == 0:
		prompt_folder_selection()
	elif id == 1:
		reset_folder()
	elif id == 2:
		reload_items()
	else:
		var metadata = self.get_item_metadata(id)
		print("Clicked: ", metadata)
		var abs_path = "%s/%s" % [directory, metadata]
		emit_signal("pressed_add_custom_roadcontainer", abs_path)


func dir_contents(path: String) -> Array:
	var dir = DirAccess.open(path)
	var contents:Array = []
	if dir:
		dir.list_dir_begin()
		var file_name:String = dir.get_next()
		while file_name != "":
			if dir.current_is_dir():
				pass
			else:
				if file_name.get_extension() == "tscn":
					contents.append(file_name)
			file_name = dir.get_next()
	else:
		print("An error occurred when trying to access the path.")
	contents.sort()
	return contents


func prompt_folder_selection() -> void:
	dir_selector.popup_centered_ratio()


func _on_folder_selected(_new_dir: String) -> void:
	directory = _new_dir
	reload_items()
