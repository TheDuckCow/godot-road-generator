@tool
extends Button

@onready var popup: PopupPanel = get_node("../settings_panel")

var get_connector: Callable
var terrain3d_select: Button
var _connector: Node

var _connector_parent: HBoxContainer
var _conenctor_left_col: VBoxContainer
var _conenctor_right_col: VBoxContainer


func _ready():
	pressed.connect(_on_pressed)
	popup.popup_hide.connect(_on_popup_closed)


func _on_pressed():
	var pos := self.global_position
	var win_offset := DisplayServer.window_get_position()
	if get_connector:
		_connector = get_connector.call()
	else:
		_connector = null
	populate_connector()
	pos.y += self.size.y + win_offset.y
	pos.x += win_offset.x
	popup.reset_size()
	popup.popup(Rect2i(pos, popup.size))


func populate_connector() -> void:
	if not _connector:
		terrain3d_select.disabled = true
		terrain3d_select.text = "Not found"
		terrain3d_select.icon = null
		terrain3d_select.tooltip_text = "First add\nRoadTerrain\n3DConnector\nto scene"
		return
	terrain3d_select.disabled = false
	if _connector.is_configured():
		terrain3d_select.text = "Select connector"
		terrain3d_select.icon = null
		terrain3d_select.tooltip_text = "Select connector\nin scene tree"
	else:
		terrain3d_select.text = "Not configured"
		terrain3d_select.icon = EditorInterface.get_editor_theme().get_icon("NodeWarning", "EditorIcons")
		terrain3d_select.tooltip_text = "Press to select\nand connect\nRoadManager and\nterrain nodes"
	
	# Configure columns for labels + export var inputs
	var vbox := %terrain3d_tut.get_parent().get_parent()
	_connector_parent = HBoxContainer.new()
	_conenctor_left_col = VBoxContainer.new()
	_conenctor_right_col = VBoxContainer.new()
	vbox.add_child(_connector_parent)
	_connector_parent.add_child(_conenctor_left_col)
	_connector_parent.add_child(_conenctor_right_col)
	
	# Usage type, at the time of writing resolves to 4102
	const usage_filter: int = PROPERTY_USAGE_SCRIPT_VARIABLE | PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_STORAGE
	
	for _prop in _connector.get_property_list():
		PROPERTY_USAGE_EDITOR
		if _prop.usage != usage_filter:
			continue
		match _prop.type:
			TYPE_OBJECT:
				continue # Skip for now, see potential approach here:
				# https://forum.godotengine.org/t/inspector-plugin-that-reuses-the-export-node-prompt/64588/2
			TYPE_FLOAT:
				var exportvar: SpinBox = SpinBox.new()
				exportvar.allow_lesser = true
				exportvar.allow_greater = true
				exportvar.step = 0.01 # Can't easily get from editor, assume this granularity
				exportvar.value = _connector.get(_prop.name)
				exportvar.value_changed.connect(func(_value: float):
					_connector.set(_prop.name, _value)
				)
				add_exportvar_row(_prop.name, exportvar)
			TYPE_BOOL:
				var exportvar: CheckBox = CheckBox.new()
				exportvar.button_pressed = _connector.get(_prop.name)
				exportvar.toggled.connect(func(_state: bool):
					_connector.set(_prop.name, _state)
				)
				add_exportvar_row(_prop.name, exportvar)


func add_exportvar_row(name: String, control: Control) -> void:
	var label = Label.new()
	label.text = _capitalize_text(name)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_conenctor_left_col.add_child(label)
	_conenctor_right_col.add_child(control)


func _on_popup_closed():
	if is_instance_valid(_connector_parent):
		_connector_parent.queue_free()
	release_focus()


func _capitalize_text(text: String) -> String:
	var words: PackedStringArray = text.split("_")
	for i in range(words.size()):
		words[i] = words[i].capitalize()
	return " ".join(words)
