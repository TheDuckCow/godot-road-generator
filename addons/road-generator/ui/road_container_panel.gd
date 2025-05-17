@tool
# Panel which is added to UI and used to trigger callbacks to update RoadContainers
extends VBoxContainer

signal export_gltf

var _edi : set = set_edi

func set_edi(value):
	_edi = value

func _on_export_gltf_pressed() -> void:
	export_gltf.emit()
