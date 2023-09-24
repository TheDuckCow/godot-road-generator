## Manager for all children RoadContainers
tool
class_name RoadManager, "../resources/road_manager.png"
extends Spatial

var _skip_warn_found_rc_child := false


# ------------------------------------------------------------------------------
# Setup and export setter/getters
# ------------------------------------------------------------------------------


func _get_configuration_warning() -> String:
	if _skip_warn_found_rc_child:
		return ""
	var any_containers := false
	for ch in get_children():
		if ch.has_method("is_road_container"):
			any_containers = true
			break

	if any_containers:
		return ""
	else:
		return "No RoadContainer children. Start creating a road by activating the + mode and clicking in the 3D view"


# Workaround for cyclic typing
func is_road_manager() -> bool:
	return true
